--!strict
-- The run: lobby, waves, merges, breathers, bosses, rewards and the end (docs/INTERFACES.md
-- "C1 contracts" → "Waves"). One run per server, entirely on the server clock.
--
-- Two things are deliberate here:
-- * The pacing director only ever changes PACING — spawn interval, merges, breather length,
--   the one extra elite. It never touches enemy HP or damage; only Overdrive does that.
-- * Rewards are banked into a per-wave pool and flushed to the profiles at every wave clear, so
--   a disconnect, a wipe or a crash costs at most the wave in progress. This is the only place
--   under src/combat that writes a profile, and it writes nothing but cash, materials, valor,
--   combat stats and the mission record.
--
-- C2 adds the co-op edges: the lobby start rule (ArenaService.CanStart), the wave boundary that
-- lets waiting members in, the Mentor bonus at a boss clear, and the group return home after
-- coop.returnGroupSeconds on the summary card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Combat = require(sharedFolder:WaitForChild("Combat"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local EnemyService = require(script.Parent:WaitForChild("EnemyService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local ReturnService = require(script.Parent:WaitForChild("ReturnService"))

-- Degrade value: without Combat.json the place never leaves the lobby, but the broadcast loop
-- still needs a legal period.
local DEFAULT_STATE_HZ = 4
local FIRST_WAVE = 1

type PendingSpawn = {
	key: string,
	isBoss: boolean,
	stats: Types.EnemyStats,
	boss: Types.BossDef?,
	-- Summons appear beside their boss instead of on the rim.
	at: Vector3?,
}

local phase: Types.RunPhase = "lobby"
local wave = 0
-- The highest wave whose rewards have been flushed; a merged pair clears both at once.
local clearedThrough = 0
local merged = false
local forcedNextWave: number? = nil
local pending: { PendingSpawn } = {}
-- Boss summons (C2.5): same spawn path and maxAlive cap as the wave, but not paced by the spawn
-- interval, because a summon is a telegraphed event the party just watched wind up.
local summons: { PendingSpawn } = {}
local spec: Combat.WaveSpec? = nil
local spawnedThisGroup = 0
local spawnCursor = 0
local nextSpawnAt = 0
local breatherUntil = 0
local runEndsAt = 0
-- os.clock() the summary card sends everyone home together; 0 = no group return pending.
local returnAt = 0
local tempo = 1
local pool = { cash = 0, materials = 0, valor = 0, kills = 0 }
local killsByUser: { [number]: number } = {}
local bossClearsThisFlush = 0
local killStamps: { number } = {}
local bossEnemy: EnemyService.Enemy? = nil
local broadcastAccumulator = 0
local loopConnection: RBXScriptConnection? = nil

local WaveService = {}

local function config(): Types.CombatConfig?
	return Catalog.GetCombatConfig()
end

local function stateHz(): number
	local combatConfig = config()
	local hz = if combatConfig ~= nil then combatConfig.remotes.combatStateHz else DEFAULT_STATE_HZ
	if hz <= 0 then
		return DEFAULT_STATE_HZ
	end
	return hz
end

local function aliveEnemies(): number
	return EnemyService.AliveCount()
end

local function pushRunFields(): ()
	local boss = bossEnemy
	local bossInfo: { name: string, hp: number, maxHp: number }? = nil
	if boss ~= nil and not boss.dead then
		bossInfo = { name = boss.displayName, hp = boss.hp, maxHp = boss.maxHp }
	end
	local now = os.clock()
	ArenaService.SetRunFields({
		phase = phase,
		wave = wave,
		alive = aliveEnemies(),
		remaining = #pending + #summons,
		tempo = tempo,
		merged = merged,
		breatherEndsIn = if phase == "breather" then math.max(0, breatherUntil - now) else nil,
		runEndsIn = if runEndsAt > 0 then math.max(0, runEndsAt - now) else 0,
		boss = bossInfo,
		inRun = phase == "wave" or phase == "breather" or phase == "boss",
		returnIn = if phase == "summary" and returnAt > 0 then math.max(0, returnAt - now) else nil,
	})
end

local function broadcast(): ()
	pushRunFields()
	ArenaService.Broadcast(phase)
end

local function setPhase(next: Types.RunPhase): ()
	if phase == next then
		return
	end
	phase = next
	broadcast()
end

-- Kills inside director.windowSeconds, against the pace the wave was budgeted for. Held at 1.0
-- through the warmup so the very first seconds of a run never trigger a merge or an elite.
local function updateTempo(combatConfig: Types.CombatConfig, mission: Types.MissionConfig): ()
	local director = combatConfig.director
	local now = os.clock()
	local cutoff = now - director.windowSeconds
	while #killStamps > 0 and killStamps[1] < cutoff do
		table.remove(killStamps, 1)
	end
	if ArenaService.RunSeconds() < director.tempoWarmupSeconds then
		tempo = 1
		return
	end
	local current = spec
	local count = if current ~= nil then current.count else 0
	local expected = if mission.targetWaveSeconds > 0 then count / mission.targetWaveSeconds else 0
	tempo = Combat.Tempo(#killStamps, director.windowSeconds, expected, director)
end

-- The one enemy the director may add: an elite, and only when the party is clearly ahead.
local function eliteKeyFor(mission: Types.MissionConfig, weights: { [string]: number }): string?
	local keys: { string } = {}
	for key in weights do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local def = mission.enemies[key]
		if def ~= nil and def.elite then
			return key
		end
	end
	return nil
end

local function queueWave(
	mission: Types.MissionConfig,
	combatConfig: Types.CombatConfig,
	waveNumber: number
): ()
	local overdrive = ArenaService.IsOverdrive()
	local resolved =
		Combat.WaveSpec(mission, waveNumber, ArenaService.PartySize(), overdrive, combatConfig)
	spec = resolved

	local queue: { PendingSpawn } = {}
	local boss = resolved.boss
	if boss ~= nil then
		local bossStats = Combat.EnemyStats(mission, boss.enemy, resolved, true)
		if bossStats ~= nil then
			table.insert(queue, {
				key = boss.enemy,
				isBoss = true,
				stats = bossStats,
				boss = boss,
			})
		end
	end

	local order = Combat.WaveComposition(resolved.count, resolved.weights)
	if tempo >= combatConfig.director.eliteTempo then
		local elite = eliteKeyFor(mission, resolved.weights)
		if elite ~= nil then
			table.insert(order, elite)
		end
	end
	for _, key in order do
		local stats = Combat.EnemyStats(mission, key, resolved, false)
		if stats ~= nil then
			table.insert(queue, { key = key, isBoss = false, stats = stats, boss = nil })
		end
	end

	table.move(queue, 1, #queue, #pending + 1, pending)
	spawnedThisGroup += #queue
	nextSpawnAt = os.clock()
	CombatService.PushFx({
		kind = "wave",
		wave = waveNumber,
		merged = merged,
		boss = boss ~= nil,
	})
end

local function beginWave(waveNumber: number): ()
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	wave = waveNumber
	merged = false
	spawnedThisGroup = 0
	bossEnemy = nil
	-- A wave boundary: anyone who arrived (or died) mid-wave enters now. Before queueWave, so
	-- they count as fighters for everything this wave does.
	ArenaService.ReleaseWaiting()
	queueWave(mission, combatConfig, waveNumber)
	setPhase("wave")
	broadcast()
	ArenaService.PublishRun()
end

local function missionRecord(state: Types.PlayerState, missionId: string): Types.MissionRecord
	local record = state.combat.missions[missionId]
	if record == nil then
		record = { bestWave = 0, bossClears = 0, overdriveBest = 0 }
		state.combat.missions[missionId] = record
	end
	return record
end

-- Mentor bonus at a cleared boss group (docs/INTERFACES.md "C2 contracts"): each human is paid
-- Combat.MentorBonus against the rates of the OTHER members present whose raw share of THIS
-- flush reached coop.mentorMinDamageShare, so an idle alt parked in the party earns its main
-- nothing. Bots report debug.botIncomeRate and are never mentors.
local function payMentors(combatConfig: Types.CombatConfig, tally: { [number]: number }): ()
	local total = 0
	for _, damage in tally do
		total += damage
	end
	if total <= 0 then
		return
	end
	local coop = combatConfig.coop
	local members = ArenaService.GetMembers()
	for _, mentor in members do
		local player = mentor.player
		-- Same floor as a mentee (lead ruling): a mentor parked on the pad, or one who let the
		-- party carry the boss, earns nothing for "carrying".
		if
			mentor.bot
			or player == nil
			or mentor.waiting
			or (tally[mentor.userId] or 0) / total < coop.mentorMinDamageShare
		then
			continue
		end
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		local menteeRates: { number } = {}
		for _, other in members do
			if
				other ~= mentor
				and (tally[other.userId] or 0) / total >= coop.mentorMinDamageShare
			then
				table.insert(menteeRates, other.incomeRate)
			end
		end
		local bonus = Combat.MentorBonus(combatConfig, mentor.incomeRate, menteeRates)
		if bonus <= 0 then
			continue
		end
		state.combat.valor += bonus
		ArenaService.CreditMentor(mentor.userId, bonus)
		CombatService.PushFx({
			kind = "mentor",
			userId = mentor.userId,
			valor = bonus,
			-- MentorBonus pays mentorValor per carried member, so this recovers the head count.
			mentees = if coop.mentorValor > 0 then math.round(bonus / coop.mentorValor) else 0,
		})
	end
end

-- The wave pot, split by damage share with a floor and written straight into the profiles. Bots
-- take a share so party scaling is honest, and then it is discarded. `cleared` = the group was
-- actually beaten (not the partial flush at a wipe or the run cap), the only case that can pay
-- the Mentor bonus.
local function flushPool(waveNumber: number, waveCount: number, cleared: boolean): ()
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	local tally = CombatService.TakeDamageTally()
	if cleared and bossClearsThisFlush > 0 then
		-- Before the per-member loop below, whose snapshot then carries the Mentor Valor too.
		payMentors(combatConfig, tally)
	end
	local shares = Combat.ContributionShares(tally, combatConfig.coop.contributionFloor)
	local split = Combat.SplitPool(pool, shares)
	local gameConfig = Catalog.GetGameConfig()
	local shopConfig = Catalog.GetLegacyShopConfig()
	local overdrive = ArenaService.IsOverdrive()

	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if member.bot or player == nil then
			continue
		end
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		local share = split[member.userId]
		local kills = killsByUser[member.userId] or 0
		if share ~= nil then
			local mult = Combat.CombatCashMult(state, gameConfig, shopConfig)
			local cash = math.floor(share.cash * mult)
			state.cash += cash
			state.combat.valor += share.valor
			if share.materials > 0 then
				local owned = state.combat.materials[mission.material] or 0
				state.combat.materials[mission.material] = owned + share.materials
			end
			state.combat.stats.cashFromCombat += cash
			ArenaService.CreditSummary(
				member.userId,
				cash,
				mission.material,
				share.materials,
				share.valor,
				kills
			)
		end
		state.combat.stats.kills += kills
		state.combat.stats.wavesCleared += waveCount
		local record = missionRecord(state, mission.id)
		record.bestWave = math.max(record.bestWave, waveNumber)
		record.bossClears += bossClearsThisFlush
		if overdrive then
			record.overdriveBest = math.max(record.overdriveBest, waveNumber)
		end
		-- The wallet strip is fed by Snapshots in this place (EconomyService is hub-only).
		ArenaService.SendSnapshot(player)
	end

	ArenaService.MarkWaveCleared(waveNumber, waveCount)
	pool = { cash = 0, materials = 0, valor = 0, kills = 0 }
	killsByUser = {}
	bossClearsThisFlush = 0
end

function WaveService.EndRun(reason: string): ()
	if phase == "summary" or phase == "ended" then
		return
	end
	-- Rewards banked since the last wave clear are kept: dying on wave 7 still pays for wave 7's
	-- kills, which is what makes a failed run worth starting. The wave in progress was NOT
	-- cleared though, so bestWave is credited to the last wave actually finished (0 when they
	-- died in wave 1) and wavesCleared gains nothing.
	if wave > clearedThrough then
		flushPool(clearedThrough, 0, false)
	end
	pending = {}
	summons = {}
	spec = nil
	bossEnemy = nil
	EnemyService.ClearAll()
	phase = "summary"
	local combatConfig = config()
	returnAt = if combatConfig ~= nil then os.clock() + combatConfig.coop.returnGroupSeconds else 0
	pushRunFields()
	ArenaService.BroadcastSummary()
	-- Queued, never awaited: this runs inside the Heartbeat tick and the registry retries with a
	-- task.wait backoff. The run stops being joinable the moment it ends, even though the party
	-- is still here reading the summary card.
	ArenaService.ClearRegistry(ArenaService.GetHostUserId())
	warn(`[WaveService] run ended ({reason}) at wave {wave}`)
end

local function onEnemyKilled(enemy: EnemyService.Enemy, byUserId: number): ()
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	table.insert(killStamps, os.clock())
	pool.cash += enemy.cash
	pool.materials += enemy.materials
	pool.kills += 1
	if ArenaService.GetMember(byUserId) ~= nil then
		killsByUser[byUserId] = (killsByUser[byUserId] or 0) + 1
	end
	local valor = 0
	if enemy.isBoss and mission ~= nil and combatConfig ~= nil then
		valor = Combat.BossValor(mission, wave, ArenaService.IsOverdrive(), combatConfig)
		pool.valor += valor
		bossClearsThisFlush += 1
		bossEnemy = nil
		CombatService.PushFx({ kind = "bossDown", name = enemy.displayName, valor = valor })
	end
	CombatService.PushFx({
		kind = "kill",
		enemyId = enemy.id,
		position = enemy.root.Position,
		cash = enemy.cash,
		materials = enemy.materials,
		byUserId = byUserId,
	})
end

local function spawnSummons(combatConfig: Types.CombatConfig): ()
	while #summons > 0 and aliveEnemies() < combatConfig.director.maxAlive do
		local entry = table.remove(summons, 1)
		if entry == nil then
			return
		end
		spawnCursor += 1
		EnemyService.Spawn(entry.key, entry.stats, false, spawnCursor, nil, entry.at)
	end
end

-- EnemyService calls this from inside its AI tick when a boss's summon lands, so it only queues.
-- Summoned enemies use the current wave's stats, count toward the group (merge maths, clear) and
-- pay normal rewards through the normal kill path.
local function onSummon(key: string, count: number, near: Vector3): ()
	if phase ~= "wave" and phase ~= "boss" then
		return
	end
	local mission = ArenaService.GetMission()
	local current = spec
	if mission == nil or current == nil then
		return
	end
	local stats = Combat.EnemyStats(mission, key, current, false)
	if stats == nil then
		return
	end
	for _ = 1, count do
		table.insert(summons, { key = key, isBoss = false, stats = stats, boss = nil, at = near })
	end
	spawnedThisGroup += count
end

local function spawnNext(mission: Types.MissionConfig, combatConfig: Types.CombatConfig): ()
	if #pending == 0 or aliveEnemies() >= combatConfig.director.maxAlive then
		return
	end
	local now = os.clock()
	if now < nextSpawnAt then
		return
	end
	local entry = table.remove(pending, 1)
	if entry == nil then
		return
	end
	spawnCursor += 1
	local enemy = EnemyService.Spawn(entry.key, entry.stats, entry.isBoss, spawnCursor, entry.boss)
	if enemy ~= nil and entry.isBoss then
		bossEnemy = enemy
		setPhase("boss")
	end
	local current = spec
	if current ~= nil then
		nextSpawnAt = now
			+ Combat.SpawnInterval(
				mission,
				current,
				tempo,
				ArenaService.IsOverdrive(),
				combatConfig
			)
	end
end

-- Humans in the fight (waiting members are on the pad and do not count), how many of those are
-- alive, and how many humans are alive on the pad.
local function humanCounts(): (number, number, number)
	local fighters = 0
	local fightersAlive = 0
	local waitingAlive = 0
	for _, member in ArenaService.GetMembers() do
		if member.bot then
			continue
		end
		local alive = ArenaService.IsAlive(member)
		if member.waiting then
			if alive then
				waitingAlive += 1
			end
			continue
		end
		fighters += 1
		if alive then
			fightersAlive += 1
		end
	end
	return fighters, fightersAlive, waitingAlive
end

local function tickBots(combatConfig: Types.CombatConfig): ()
	local now = os.clock()
	local fighters, fightersAlive = humanCounts()
	-- As at C1: bots come back only while a human is still fighting (or there are none at all,
	-- a bots-only Studio run that only the run cap ends).
	local mayRespawn = fightersAlive > 0 or fighters == 0
	for _, member in ArenaService.GetMembers() do
		if not member.bot then
			continue
		end
		if ArenaService.IsAlive(member) then
			member.respawnAt = 0
			continue
		end
		if member.respawnAt == 0 then
			member.respawnAt = now + combatConfig.player.respawnSeconds
		elseif now >= member.respawnAt and mayRespawn then
			ArenaService.RespawnBot(member)
		end
	end
end

-- Breather regen: the only healing in a run, and it only happens between waves.
local function regen(combatConfig: Types.CombatConfig, delta: number): ()
	local perSecond = combatConfig.player.breatherRegenPerSecond
	if perSecond <= 0 then
		return
	end
	for _, member in ArenaService.GetMembers() do
		local humanoid = member.humanoid
		if humanoid ~= nil and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + perSecond * delta)
		end
	end
end

local function advanceAfterBreather(mission: Types.MissionConfig): ()
	local nextWave = forcedNextWave or (wave + 1)
	forcedNextWave = nil
	if nextWave > mission.waves then
		WaveService.EndRun("cleared")
		return
	end
	beginWave(nextWave)
end

-- The group return: once, when the summary countdown runs out. Everyone still here goes home in
-- ONE teleport with the party hint, so the hub can re-form the party. Spawned: it yields.
local function tickSummary(): ()
	if returnAt <= 0 or os.clock() < returnAt then
		return
	end
	returnAt = 0
	pushRunFields()
	local players: { Player } = {}
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if player ~= nil then
			table.insert(players, player)
		end
	end
	if #players > 0 then
		task.spawn(ReturnService.SendHomeGroup, players, "runOver")
	end
end

local function tick(delta: number): ()
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	if phase == "lobby" then
		-- The expected-party / lobbyWaitSeconds half of the start rule has no event of its own,
		-- so it is polled here; RequestReady also checks it for an instant start.
		if ArenaService.CanStart() then
			WaveService.Start()
		end
		return
	end
	if phase == "summary" then
		tickSummary()
		return
	end
	if phase == "ended" then
		return
	end

	updateTempo(combatConfig, mission)
	tickBots(combatConfig)

	local now = os.clock()
	if runEndsAt > 0 and now >= runEndsAt then
		WaveService.EndRun("runCap")
		return
	end
	local fighters, fightersAlive, waitingAlive = humanCounts()
	if fightersAlive == 0 then
		if fighters > 0 then
			-- A death with no other fighting human alive is a wipe (C1 rule), even with a joiner
			-- on the pad.
			WaveService.EndRun("wipe")
			return
		end
		if waitingAlive > 0 then
			-- Every fighter LEFT (nobody died): the joiners on the pad take over now rather than
			-- watching an unattended wave until the run cap.
			ArenaService.ReleaseWaiting()
			broadcast()
		end
	end

	if phase == "breather" then
		regen(combatConfig, delta)
		if now >= breatherUntil then
			advanceAfterBreather(mission)
		end
		return
	end

	spawnSummons(combatConfig)
	spawnNext(mission, combatConfig)

	local boss = bossEnemy
	if boss ~= nil and not boss.dead then
		setPhase("boss")
	elseif phase == "boss" then
		setPhase("wave")
	end

	if #pending > 0 or #summons > 0 then
		return
	end

	local alive = aliveEnemies()
	if alive > 0 then
		-- Still spawning is over; the director may fold the next wave in on top of this one.
		local deadFraction = if spawnedThisGroup > 0
			then (spawnedThisGroup - alive) / spawnedThisGroup
			else 0
		if
			wave < mission.waves
			and Combat.ShouldMerge(tempo, deadFraction, combatConfig.director)
		then
			merged = true
			wave += 1
			queueWave(mission, combatConfig, wave)
			broadcast()
			ArenaService.PublishRun()
		end
		return
	end

	-- Wave (or merged pair) cleared.
	local count = wave - clearedThrough
	clearedThrough = wave
	flushPool(wave, count, true)
	ArenaService.PublishRun()
	if wave >= mission.waves then
		WaveService.EndRun("cleared")
		return
	end
	breatherUntil = now + Combat.BreatherSeconds(tempo, combatConfig.director)
	-- The breather is a wave boundary: the waiting enter now, so they get the regen too.
	ArenaService.ReleaseWaiting()
	setPhase("breather")
end

function WaveService.Start(): ()
	if phase ~= "lobby" then
		return
	end
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	local startWave = forcedNextWave or FIRST_WAVE
	forcedNextWave = nil
	clearedThrough = startWave - 1
	tempo = 1
	pool = { cash = 0, materials = 0, valor = 0, kills = 0 }
	killsByUser = {}
	bossClearsThisFlush = 0
	killStamps = {}
	spawnCursor = 0
	CombatService.ResetDamageTally()
	ArenaService.MarkRunStarted()
	runEndsAt = os.clock() + combatConfig.director.runCapSeconds
	returnAt = 0
	beginWave(startWave)
end

function WaveService.GetPhase(): Types.RunPhase
	return phase
end

function WaveService.GetWave(): number
	return wave
end

-- Debug lever: in the lobby it chooses the wave the run starts at, mid-run the wave that comes
-- after this one.
function WaveService.ForceWave(waveNumber: number): ()
	local target = math.max(1, math.floor(waveNumber))
	forcedNextWave = target
	if phase == "lobby" then
		return
	end
	local mission = ArenaService.GetMission()
	if mission == nil then
		return
	end
	pending = {}
	summons = {}
	EnemyService.ClearAll()
	breatherUntil = 0
	-- Skipping forward is not clearing: without this, jumping from wave 2 to wave 9 would credit
	-- seven waves nobody fought the next time the pool flushed.
	clearedThrough = target - 1
	advanceAfterBreather(mission)
end

-- Debug lever: one extra enemy of `key` at the next rim spawn, using the current wave's stats.
function WaveService.SpawnOne(key: string): ()
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	local existing = spec
	-- Before wave 1 there is no spec yet, so the lever borrows wave 1's numbers.
	local current: Combat.WaveSpec = if existing ~= nil
		then existing
		else Combat.WaveSpec(
			mission,
			math.max(wave, FIRST_WAVE),
			ArenaService.PartySize(),
			ArenaService.IsOverdrive(),
			combatConfig
		)
	local stats = Combat.EnemyStats(mission, key, current, false)
	if stats == nil then
		return
	end
	spawnCursor += 1
	spawnedThisGroup += 1
	EnemyService.Spawn(key, stats, false, spawnCursor, nil)
end

-- Debug lever: every alive enemy dies with its normal rewards.
function WaveService.KillAll(): ()
	EnemyService.KillAll(0)
end

-- The last member left: a reserved server can be reused by a later arrival, and a service still
-- sitting in `summary` would refuse to ever start another run here.
function WaveService.Reset(): ()
	phase = "lobby"
	wave = 0
	clearedThrough = 0
	merged = false
	forcedNextWave = nil
	pending = {}
	summons = {}
	spec = nil
	spawnedThisGroup = 0
	spawnCursor = 0
	breatherUntil = 0
	runEndsAt = 0
	returnAt = 0
	tempo = 1
	bossEnemy = nil
	killStamps = {}
	killsByUser = {}
	bossClearsThisFlush = 0
	pool = { cash = 0, materials = 0, valor = 0, kills = 0 }
	CombatService.ResetDamageTally()
	EnemyService.ClearAll()
	pushRunFields()
end

function WaveService.Init(): ()
	CombatService.SetKillHandler(onEnemyKilled)
	EnemyService.SetSummonHandler(onSummon)
	ArenaService.SetResetHook(WaveService.Reset)
end

-- The boot hook, NOT the run start: Start() above is the contract's "the lobby is ready, go".
-- Main wires this one into the ordered Init/Start pass.
function WaveService.Boot(): ()
	if loopConnection ~= nil then
		return
	end
	loopConnection = RunService.Heartbeat:Connect(function(delta: number)
		tick(delta)
		broadcastAccumulator += delta
		local period = 1 / stateHz()
		if broadcastAccumulator >= period then
			broadcastAccumulator = 0
			broadcast()
		end
	end)
end

return WaveService
