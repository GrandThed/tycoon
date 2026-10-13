--!strict
-- The run: lobby, waves, merges, breathers, bosses, rewards and the end (docs/INTERFACES.md
-- "C1 contracts" → "Waves"). One run per server, entirely on the server clock.
--
-- Two things are deliberate here:
-- * The pacing director only ever changes PACING — burst interval, merges, breather length,
--   the one extra elite. It never touches enemy HP or damage; only Overdrive does that.
-- * Rewards are banked into a per-wave pool and flushed to the profiles at every wave clear, so
--   a disconnect, a wipe or a crash costs at most the wave in progress. This is the only place
--   under src/combat that writes a profile, and it writes nothing but cash, materials, valor,
--   combat stats and the mission record.
--
-- C2 adds the co-op edges: the lobby start rule (ArenaService.CanStart), the wave boundary that
-- lets waiting members in, the Mentor bonus at a boss clear, and the group return home after
-- coop.returnGroupSeconds on the summary card.
--
-- P5 (docs/INTERFACES.md "P5 contracts", rulings 13-19): the waves are crowd groups. They come
-- from the mission's `crowd` block (Combat.CrowdWave) and arrive in bursts at the arena's rim;
-- a kill pays its kind's fixed reward and books the HP its body lost per player (CrowdKillInfo).
-- The damage tally and the run's damage map live here now (CombatService's until P5). A down is
-- this file's to rule on (OnDown), and in a Studio proving build the run loops in place.
-- EnemyService and CombatService take no part: a mission without a `crowd` block is refused at
-- arrival, so every run that reaches this file is a crowd run.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Combat = require(sharedFolder:WaitForChild("Combat"))
local CombatMode = require(sharedFolder:WaitForChild("CombatMode"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local ReturnService = require(script.Parent:WaitForChild("ReturnService"))
local CrowdService = require(script.Parent:WaitForChild("CrowdService"))
local VitalsService = require(script.Parent:WaitForChild("VitalsService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local RunFx = require(script.Parent:WaitForChild("RunFx"))

-- Degrade value: without Combat.json the place never leaves the lobby, but the broadcast loop
-- still needs a legal period.
local DEFAULT_STATE_HZ = 4
local FIRST_WAVE = 1
local FIGHT = "fight"

-- One burst of one group: up to crowd.burst bodies of a kind, arriving together at one rim point
-- in a grid. `placed` survives a hold (maxAlive, or a refused spawn), so the grid carries on.
type Burst = { kind: string, left: number, placed: number, at: Vector3? }

type Pool = Combat.RewardPool

-- Everything a run holds, in one table (Studio's 200-local limit and one place to reset).
type Run = {
	phase: Types.RunPhase,
	wave: number,
	-- The highest wave whose rewards have been flushed; a merged pair clears both at once.
	clearedThrough: number,
	merged: boolean,
	forcedNextWave: number?,
	queue: { Burst },
	-- Bodies the current group put on the field (the boss and the director's elite included),
	-- for the merge test's dead fraction.
	spawnedThisGroup: number,
	-- The crowd wave being spawned, and the boss it still has to place (spawned first).
	spec: Combat.CrowdWaveSpec?,
	bossPending: Types.MissionCrowdBoss?,
	bossHpMult: number,
	-- The living boss body's crowd id (0 = none), and the Valor its kill pays.
	bossId: number,
	bossValor: number,
	burstsThisWave: number,
	rimCursor: number,
	nextBurstAt: number,
	breatherUntil: number,
	runEndsAt: number,
	-- os.clock() the summary card sends everyone home together (or, proving, restarts the run);
	-- 0 = nothing pending.
	returnAt: number,
	-- Proving loop: os.clock() the lobby first held a human; 0 = not yet.
	lobbySince: number,
	tempo: number,
	pool: Pool,
	killsByUser: { [number]: number },
	bossClearsThisFlush: number,
	killStamps: { number },
	-- The damage split of the current flush, and of the whole run (PartyMember.damageShare and
	-- RunSummary.damageShare read the latter; it is never drained mid-run).
	damageTally: { [number]: number },
	runDamage: { [number]: number },
	runDamageTotal: number,
}

local function emptyPool(): Pool
	return { cash = 0, materials = 0, valor = 0, kills = 0 }
end

local function freshRun(): Run
	return {
		phase = "lobby",
		wave = 0,
		clearedThrough = 0,
		merged = false,
		forcedNextWave = nil,
		queue = {},
		spawnedThisGroup = 0,
		spec = nil,
		bossPending = nil,
		bossHpMult = 1,
		bossId = 0,
		bossValor = 0,
		burstsThisWave = 0,
		rimCursor = 0,
		nextBurstAt = 0,
		breatherUntil = 0,
		runEndsAt = 0,
		returnAt = 0,
		lobbySince = 0,
		tempo = 1,
		pool = emptyPool(),
		killsByUser = {},
		bossClearsThisFlush = 0,
		killStamps = {},
		damageTally = {},
		runDamage = {},
		runDamageTotal = 0,
	}
end

local run = freshRun()
local boot = {
	mission = false,
	proving = false,
	-- The crowd's bounds are set once, by the first run (every arena is built at the origin).
	boundsSet = false,
	warnedStartWave = false,
	broadcastAccumulator = 0,
	loop = nil :: RBXScriptConnection?,
}

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

local function queuedBodies(): number
	local bodies = 0
	for _, burst in run.queue do
		bodies += burst.left
	end
	if run.bossPending ~= nil then
		bodies += 1
	end
	return bodies
end

local function pushRunFields(): ()
	local now = os.clock()
	local phase: Types.RunPhase = run.phase
	ArenaService.SetRunFields({
		phase = phase,
		wave = run.wave,
		alive = CrowdService.AliveCount(),
		remaining = queuedBodies(),
		tempo = run.tempo,
		merged = run.merged,
		breatherEndsIn = if phase == "breather" then math.max(0, run.breatherUntil - now) else nil,
		runEndsIn = if run.runEndsAt > 0 then math.max(0, run.runEndsAt - now) else 0,
		-- Ruling 22: the crowd's boss bar is the client's (CrowdRenderer); this one stays empty.
		boss = nil,
		inRun = phase == "wave" or phase == "breather" or phase == "boss",
		returnIn = if phase == "summary" and run.returnAt > 0
			then math.max(0, run.returnAt - now)
			else nil,
	})
end

local function broadcast(): ()
	pushRunFields()
	ArenaService.Broadcast(run.phase)
end

local function setPhase(next: Types.RunPhase): ()
	if run.phase == next then
		return
	end
	run.phase = next
	broadcast()
end

-- Raw (pre-floor) share of everything dealt this run, 0-1.
local function damageShare(userId: number): number
	if run.runDamageTotal <= 0 then
		return 0
	end
	return (run.runDamage[userId] or 0) / run.runDamageTotal
end

-- Humans and their players, in party order.
local function humanPlayers(): { Player }
	local players: { Player } = {}
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if not member.bot and player ~= nil then
			table.insert(players, player)
		end
	end
	return players
end

-- Ruling 13: in the fight right now (admitted, not on the pad, alive). Down is VitalsService's.
local function mayJudge(player: Player): boolean
	local member = ArenaService.GetMemberFor(player)
	return member ~= nil and ArenaService.IsFighting(member)
end

-- Ruling 21: an attack or ability only from a fighting member, standing, in a run.
local function mayAct(player: Player): boolean
	return ArenaService.InRun() and mayJudge(player) and not VitalsService.IsDown(player)
end

-- Ruling 11: the player's gear decides their bar (the baked proving gear in a proving mission;
-- WeaponService.GearOf already knows which).
local function maxHpOf(player: Player): number?
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		return nil
	end
	local gear, ascension = WeaponService.GearOf(player)
	return Armory.MaxHp(armoryConfig, gear, ascension)
end

-- The mission's rules for VitalsService; the scales come from the run's crowd spec, neutral until
-- a run has started (the lobby has no enemies, but its bar must already be the gear's).
local function missionRules(spec: Combat.CrowdWaveSpec?): VitalsService.MissionRules
	return {
		mayJudge = mayJudge,
		onDown = function(player: Player)
			WaveService.OnDown(player)
		end,
		maxHpOf = maxHpOf,
		damageScale = if spec ~= nil then spec.damageScale else 1,
		regenShare = if spec ~= nil then spec.regenShare else 0,
	}
end

-- Ruling 18: every downed member stands up at a wave boundary (until the Wave 4 revive).
local function standUpDowned(): ()
	for _, player in humanPlayers() do
		if VitalsService.IsDown(player) then
			VitalsService.StandUp(player)
		end
	end
end

-- Kills inside director.windowSeconds, against the pace the wave was budgeted for. Held at 1.0
-- through the warmup so the very first seconds of a run never trigger a merge or an elite.
local function updateTempo(combatConfig: Types.CombatConfig, mission: Types.MissionConfig): ()
	local director = combatConfig.director
	local now = os.clock()
	local cutoff = now - director.windowSeconds
	local stamps = run.killStamps
	while #stamps > 0 and stamps[1] < cutoff do
		table.remove(stamps, 1)
	end
	if ArenaService.RunSeconds() < director.tempoWarmupSeconds then
		run.tempo = 1
		return
	end
	local spec = run.spec
	local total = if spec ~= nil then spec.total else 0
	local expected = if mission.targetWaveSeconds > 0 then total / mission.targetWaveSeconds else 0
	run.tempo = Combat.Tempo(#stamps, director.windowSeconds, expected, director)
end

-- The next rim point, round-robin; the arena centre when the arena has none.
local function nextRimPoint(): Vector3
	local points = ArenaService.EnemySpawnPoints()
	if #points == 0 then
		return Vector3.zero
	end
	run.rimCursor += 1
	return points[(run.rimCursor - 1) % #points + 1]
end

-- The `index`-th body (0-based) of a burst of `size` at rim point `at`: a grid of pitch
-- `spacing`, its rows stepping in toward the arena centre and centred across, so a burst at the
-- fence arrives as a block rather than a line along the fence.
local function gridPoint(at: Vector3, size: number, index: number, spacing: number): Vector3
	local inward = Vector3.new(-at.X, 0, -at.Z)
	inward = if inward.Magnitude > 1e-3 then inward.Unit else Vector3.new(0, 0, 1)
	local across = Vector3.new(-inward.Z, 0, inward.X)
	local columns = math.max(math.ceil(math.sqrt(size)), 1)
	local row = index // columns
	local column = index % columns
	local offset = across * ((column - (columns - 1) / 2) * spacing) + inward * (row * spacing)
	return Vector3.new(at.X + offset.X, 0, at.Z + offset.Z)
end

local function crowdOf(mission: Types.MissionConfig): Types.MissionCrowdConfig?
	return mission.crowd
end

-- Queues one wave's groups as bursts, the boss to be placed first. Ruling 17: a boss wave takes
-- no extra elite (bosses are judged as whole fights).
local function queueWave(
	mission: Types.MissionConfig,
	combatConfig: Types.CombatConfig,
	waveNumber: number
): ()
	local crowd = crowdOf(mission)
	local spec = Combat.CrowdWave(
		mission,
		waveNumber,
		ArenaService.PartySize(),
		ArenaService.IsOverdrive(),
		combatConfig
	)
	run.spec = spec
	if crowd == nil or spec == nil then
		warn(`[WaveService] {mission.id} has no crowd wave {waveNumber}; nothing spawns`)
		return
	end
	local burstSize = math.max(math.floor(crowd.burst), 1)
	local bursts = 0
	local function add(kind: string, count: number): ()
		local left = count
		while left > 0 do
			local size = math.min(left, burstSize)
			table.insert(run.queue, { kind = kind, left = size, placed = 0, at = nil })
			left -= size
			bursts += 1
		end
	end
	for _, group in spec.groups do
		add(group.kind, group.count)
	end
	local boss = spec.boss
	local elite = crowd.eliteKind
	if boss == nil and elite ~= nil and run.tempo >= combatConfig.director.eliteTempo then
		add(elite, 1)
		run.spawnedThisGroup += 1
	end
	if boss ~= nil then
		run.bossPending = boss
		run.bossHpMult = spec.bossHpMult
		run.bossValor = math.round(boss.valor * spec.rewardMult)
	end
	run.burstsThisWave = bursts
	run.spawnedThisGroup += spec.total
	run.nextBurstAt = os.clock()
	RunFx.Push({
		kind = "wave",
		wave = waveNumber,
		merged = run.merged,
		boss = boss ~= nil,
	})
end

local function beginWave(waveNumber: number): ()
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	run.wave = waveNumber
	run.merged = false
	run.spawnedThisGroup = 0
	run.bossId = 0
	run.bossPending = nil
	run.queue = {}
	-- A wave boundary: anyone who arrived mid-wave enters now, and anyone down stands up. Before
	-- queueWave, so they count as fighters for everything this wave does.
	standUpDowned()
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
		RunFx.Push({
			kind = "mentor",
			userId = mentor.userId,
			valor = bonus,
			-- MentorBonus pays mentorValor per carried member, so this recovers the head count.
			mentees = if coop.mentorValor > 0 then math.round(bonus / coop.mentorValor) else 0,
		})
	end
end

-- The wave pot, split by damage share with a floor and written straight into the profiles.
-- `cleared` = the group was actually beaten (not the partial flush at a wipe or the run cap), the
-- only case that can pay the Mentor bonus.
local function flushPool(waveNumber: number, waveCount: number, cleared: boolean): ()
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	local tally = run.damageTally
	run.damageTally = {}
	if cleared and run.bossClearsThisFlush > 0 then
		-- Before the per-member loop below, whose snapshot then carries the Mentor Valor too.
		payMentors(combatConfig, tally)
	end
	local shares = Combat.ContributionShares(tally, combatConfig.coop.contributionFloor)
	local split = Combat.SplitPool(run.pool, shares)
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
		local kills = run.killsByUser[member.userId] or 0
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
		record.bossClears += run.bossClearsThisFlush
		if overdrive then
			record.overdriveBest = math.max(record.overdriveBest, waveNumber)
		end
		-- The wallet strip is fed by Snapshots in this place (EconomyService is hub-only).
		ArenaService.SendSnapshot(player)
	end

	ArenaService.MarkWaveCleared(waveNumber, waveCount)
	run.pool = emptyPool()
	run.killsByUser = {}
	run.bossClearsThisFlush = 0
end

-- The crowd and everything it had in the air go, and the players' shots with them.
local function clearField(): ()
	run.queue = {}
	run.bossPending = nil
	run.bossId = 0
	CrowdService.Clear()
	VitalsService.ClearThreats()
	WeaponService.AbandonProjectiles()
end

function WaveService.EndRun(reason: string): ()
	if run.phase == "summary" or run.phase == "ended" or run.phase == "lobby" then
		return
	end
	-- Rewards banked since the last wave clear are kept: dying on wave 7 still pays for wave 7's
	-- kills, which is what makes a failed run worth starting. The wave in progress was NOT
	-- cleared though, so bestWave is credited to the last wave actually finished (0 when they
	-- died in wave 1) and wavesCleared gains nothing.
	if run.wave > run.clearedThrough then
		flushPool(run.clearedThrough, 0, false)
	end
	clearField()
	run.spec = nil
	run.phase = "summary"
	local combatConfig = config()
	run.returnAt = if combatConfig ~= nil
		then os.clock() + combatConfig.coop.returnGroupSeconds
		else 0
	pushRunFields()
	ArenaService.BroadcastSummary()
	-- Queued, never awaited: this runs inside a Heartbeat and the registry retries with a
	-- task.wait backoff. The run stops being joinable the moment it ends, even though the party
	-- is still here reading the summary card.
	ArenaService.ClearRegistry(ArenaService.GetHostUserId())
	warn(`[WaveService] run ended ({reason}) at wave {run.wave}`)
end

-- Ruling 14: a kill pays its kind's fixed reward into the pool and books the HP its body lost.
-- Runs inside the strike that killed it (CrowdService's callbacks are synchronous threads), so
-- it must not yield.
local function onCrowdKilled(id: number, byUserId: number, info: CrowdService.CrowdKillInfo): ()
	local phase = run.phase
	if phase ~= "wave" and phase ~= "boss" and phase ~= "breather" then
		return
	end
	local mission = ArenaService.GetMission()
	local spec = run.spec
	if mission == nil then
		return
	end
	if spec ~= nil then
		local cash, materials = Combat.CrowdReward(mission, info.kind, spec)
		run.pool.cash += cash
		run.pool.materials += materials
	end
	run.pool.kills += 1
	for userId, damage in info.damageBy do
		run.damageTally[userId] = (run.damageTally[userId] or 0) + damage
		run.runDamage[userId] = (run.runDamage[userId] or 0) + damage
		run.runDamageTotal += damage
	end
	if ArenaService.GetMember(byUserId) ~= nil then
		run.killsByUser[byUserId] = (run.killsByUser[byUserId] or 0) + 1
	end
	table.insert(run.killStamps, os.clock())
	if info.boss and id == run.bossId then
		run.bossId = 0
		run.pool.valor += run.bossValor
		run.bossClearsThisFlush += 1
		local def = Tuning.Get().crowd.kinds[info.kind]
		local name = if def ~= nil and def.name ~= nil then def.name else info.kind
		RunFx.Push({ kind = "bossDown", name = name, valor = run.bossValor })
	end
end

-- The boss first, at its own spot, with the party HP factor (ruling 16). A refused spawn stays
-- pending and is tried again next frame.
local function spawnBoss(): ()
	local boss = run.bossPending
	if boss == nil then
		return
	end
	local at = Vector3.new(boss.at[1] or 0, 0, boss.at[2] or 0)
	local id = CrowdService.Spawn(boss.kind, at, FIGHT, Vector3.zero, run.bossHpMult)
	if id ~= 0 then
		run.bossPending = nil
		run.bossId = id
		setPhase("boss")
	end
end

-- Ruling 15: the next burst, when its time has come and the field has room. A burst held by
-- maxAlive (or a refused spawn) stays at the head of the queue and carries on as room frees.
local function spawnBursts(mission: Types.MissionConfig, combatConfig: Types.CombatConfig): ()
	local crowd = crowdOf(mission)
	if crowd == nil then
		return
	end
	local burst = run.queue[1]
	if burst == nil then
		return
	end
	local now = os.clock()
	if burst.placed == 0 and now < run.nextBurstAt then
		return
	end
	local maxAlive = crowd.maxAlive
	local at: Vector3 = burst.at or nextRimPoint()
	burst.at = at
	local size = burst.placed + burst.left
	while burst.left > 0 and CrowdService.AliveCount() < maxAlive do
		local position = gridPoint(at, size, burst.placed, crowd.burstSpacing)
		if CrowdService.Spawn(burst.kind, position, FIGHT, Vector3.zero) == 0 then
			break
		end
		burst.placed += 1
		burst.left -= 1
	end
	if burst.left > 0 then
		return
	end
	table.remove(run.queue, 1)
	run.nextBurstAt = now
		+ Combat.BurstInterval(
			mission,
			run.burstsThisWave,
			run.tempo,
			ArenaService.IsOverdrive(),
			combatConfig
		)
end

-- Humans in the fight (waiting members are on the pad and do not count), how many of those are
-- alive, and how many humans are alive on the pad. A down is alive here: OnDown rules on it.
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

-- Ruling 18: no fighting human left standing ends the run, each fighter marked as having died.
-- "down" when any of them is down; "wipe" when every one of them died outright (a reset).
local function endIfLost(): boolean
	local members = ArenaService.GetMembers()
	local lost, fallen = VitalsService.RunLost(members)
	if not lost then
		return false
	end
	local reason = "wipe"
	for _, member in members do
		local player = member.player
		if
			player ~= nil
			and table.find(fallen, member.userId) ~= nil
			and VitalsService.IsDown(player)
		then
			reason = "down"
		end
	end
	for _, userId in fallen do
		ArenaService.MarkDied(userId)
	end
	WaveService.EndRun(reason)
	return true
end

local function advanceAfterBreather(mission: Types.MissionConfig): ()
	local nextWave = run.forcedNextWave or (run.wave + 1)
	run.forcedNextWave = nil
	if nextWave > mission.waves then
		WaveService.EndRun("cleared")
		return
	end
	beginWave(nextWave)
end

-- Is `waveNumber` a boss wave of this mission's crowd?
local function isBossWave(mission: Types.MissionConfig, waveNumber: number): boolean
	local crowd = crowdOf(mission)
	local waveDef = if crowd ~= nil then crowd.waves[waveNumber] else nil
	return waveDef ~= nil and waveDef.boss ~= nil
end

-- Ruling 19: a proving mission does not send anyone home; it resets in place and starts again.
local function restartProving(): ()
	local members = ArenaService.GetMembers()
	run = freshRun()
	ArenaService.ResetSummaries()
	for _, member in members do
		member.ready = false
	end
	run.lobbySince = os.clock()
	broadcast()
end

-- The group return: once, when the summary countdown runs out. Everyone still here goes home in
-- ONE teleport with the party hint, so the hub can re-form the party. Spawned: it yields.
local function tickSummary(): ()
	if run.returnAt <= 0 or os.clock() < run.returnAt then
		return
	end
	run.returnAt = 0
	if boot.proving then
		restartProving()
		return
	end
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

-- Ruling 19: no Ready button in a proving mission; the run starts provingStartDelay after the
-- lobby first holds a human, at provingStartWave.
local function tickProvingLobby(mission: Types.MissionConfig, combatConfig: Types.CombatConfig): ()
	if #humanPlayers() == 0 then
		run.lobbySince = 0
		return
	end
	local now = os.clock()
	if run.lobbySince == 0 then
		run.lobbySince = now
	end
	local debugConfig = combatConfig.debug :: any
	local delay = tonumber(debugConfig.provingStartDelay) or 0
	if now - run.lobbySince < delay then
		return
	end
	if run.forcedNextWave == nil then
		local startWave = tonumber(debugConfig.provingStartWave)
		local crowd = crowdOf(mission)
		if startWave ~= nil then
			startWave = math.max(math.floor(startWave), FIRST_WAVE)
			if crowd ~= nil and crowd.waves[startWave] ~= nil then
				run.forcedNextWave = startWave
			elseif not boot.warnedStartWave then
				-- Once per server: the loop restarts every run, and wave 1 is the safe start.
				boot.warnedStartWave = true
				warn(
					`[WaveService] provingStartWave {startWave} has no crowd wave; starting at wave 1`
				)
			end
		end
	end
	WaveService.Start()
end

local function tickWave(mission: Types.MissionConfig, combatConfig: Types.CombatConfig): ()
	local now = os.clock()
	spawnBoss()
	spawnBursts(mission, combatConfig)

	if run.bossId ~= 0 or run.bossPending ~= nil then
		setPhase("boss")
	elseif run.phase == "boss" then
		setPhase("wave")
	end

	if #run.queue > 0 or run.bossPending ~= nil then
		return
	end

	local alive = CrowdService.AliveCount()
	if alive > 0 then
		-- Spawning is over; the director may fold the next wave in on top of this one, but
		-- never into or out of a boss wave (ruling 17).
		local spawned = run.spawnedThisGroup
		local deadFraction = if spawned > 0 then math.max(spawned - alive, 0) / spawned else 0
		if
			run.wave < mission.waves
			and not isBossWave(mission, run.wave)
			and not isBossWave(mission, run.wave + 1)
			and Combat.ShouldMerge(run.tempo, deadFraction, combatConfig.director)
		then
			run.merged = true
			run.wave += 1
			queueWave(mission, combatConfig, run.wave)
			broadcast()
			ArenaService.PublishRun()
		end
		return
	end

	-- Wave (or merged pair) cleared.
	local count = run.wave - run.clearedThrough
	run.clearedThrough = run.wave
	flushPool(run.wave, count, true)
	ArenaService.PublishRun()
	if run.wave >= mission.waves then
		WaveService.EndRun("cleared")
		return
	end
	-- No flat breather regen in crowd missions: VitalsService's regen is the only healing.
	run.breatherUntil = now + Combat.BreatherSeconds(run.tempo, combatConfig.director)
	-- The breather is a wave boundary: the waiting enter now, and the downed stand up.
	standUpDowned()
	ArenaService.ReleaseWaiting()
	setPhase("breather")
end

local function tick(): ()
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	local phase = run.phase
	if phase == "lobby" then
		if boot.proving then
			tickProvingLobby(mission, combatConfig)
		elseif ArenaService.CanStart() then
			-- The expected-party / lobbyWaitSeconds half of the start rule has no event of its
			-- own, so it is polled here; RequestReady also checks it for an instant start.
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
	if run.runEndsAt > 0 and os.clock() >= run.runEndsAt then
		WaveService.EndRun("runCap")
		return
	end
	-- Ruling 18 from state, every frame: OnDown only hears of a down, and the last standing
	-- fighter may instead leave, die to a reset or respawn onto the pad after it.
	if endIfLost() then
		return
	end
	local fighters, _fightersAlive, waitingAlive = humanCounts()
	if fighters == 0 and waitingAlive > 0 then
		-- Every fighter LEFT (nobody fell): the joiners on the pad take over now rather than
		-- watching an unattended wave until the run cap.
		ArenaService.ReleaseWaiting()
		broadcast()
	end

	if run.phase == "breather" then
		if os.clock() >= run.breatherUntil then
			advanceAfterBreather(mission)
		end
		return
	end
	tickWave(mission, combatConfig)
end

function WaveService.Start(): ()
	if run.phase ~= "lobby" then
		return
	end
	local mission = ArenaService.GetMission()
	local combatConfig = config()
	if mission == nil or combatConfig == nil then
		return
	end
	local startWave = run.forcedNextWave or FIRST_WAVE
	local spec = Combat.CrowdWave(
		mission,
		startWave,
		ArenaService.PartySize(),
		ArenaService.IsOverdrive(),
		combatConfig
	)
	if spec == nil then
		-- Forgotten, so the next start is wave 1 rather than the same refusal every frame.
		run.forcedNextWave = nil
		run.lobbySince = os.clock()
		warn(`[WaveService] {mission.id} has no crowd wave {startWave}; the run cannot start there`)
		return
	end
	run.forcedNextWave = nil
	run.clearedThrough = startWave - 1
	run.tempo = 1
	run.pool = emptyPool()
	run.killsByUser = {}
	run.bossClearsThisFlush = 0
	run.killStamps = {}
	run.damageTally = {}
	run.runDamage = {}
	run.runDamageTotal = 0
	run.rimCursor = 0
	run.lobbySince = 0
	CrowdService.SetScales({ hp = spec.hpScale, plate = spec.plateScale })
	VitalsService.SetMission(missionRules(spec))
	if not boot.boundsSet then
		boot.boundsSet = true
		local center, halfSize = ArenaService.ArenaBounds()
		WeaponService.SetArena(center, halfSize)
		CrowdService.SetBounds(center, halfSize)
	end
	clearField()
	-- Every member starts the run on their feet, at full health, with the gear's bar (a body
	-- prepared before the mission rules were set would still hold the range's).
	for _, player in humanPlayers() do
		VitalsService.RefreshMaxHp(player)
		VitalsService.StandUp(player)
	end
	ArenaService.MarkRunStarted()
	run.runEndsAt = os.clock() + combatConfig.director.runCapSeconds
	run.returnAt = 0
	beginWave(startWave)
end

function WaveService.GetPhase(): Types.RunPhase
	return run.phase
end

function WaveService.GetWave(): number
	return run.wave
end

-- Ruling 18, the one rule for a down (WaveService's until the Wave 4 revive): when no fighting
-- human is left standing the run ends, and each of them is marked as having died.
function WaveService.OnDown(_player: Player): ()
	local phase = run.phase
	if phase ~= "wave" and phase ~= "boss" and phase ~= "breather" then
		return
	end
	-- Someone still standing: the run goes on, and the downed get up at the boundary. tick asks
	-- the same question every frame, for the partner who leaves or dies later.
	endIfLost()
end

-- Debug lever (ruling 25): the crowd and its threats go and `waveNumber` starts at once; nothing
-- skipped is credited. In the lobby the run starts there.
function WaveService.ForceWave(waveNumber: number): ()
	local mission = ArenaService.GetMission()
	if mission == nil then
		return
	end
	-- Clamped: past the last wave, clearedThrough would overtake the wave in progress and the
	-- run's end would skip the flush of what that wave had banked.
	local target = math.clamp(math.floor(waveNumber), 1, math.max(mission.waves, 1))
	local phase = run.phase
	if phase == "summary" or phase == "ended" then
		return
	end
	run.forcedNextWave = target
	if phase == "lobby" then
		WaveService.Start()
		return
	end
	clearField()
	run.breatherUntil = 0
	-- Skipping forward is not clearing: without this, jumping from wave 2 to wave 9 would credit
	-- seven waves nobody fought the next time the pool flushed.
	run.clearedThrough = target - 1
	advanceAfterBreather(mission)
end

-- The B and N keys (Studio only, through DebugService): "next" = the wave after this one, "boss"
-- = the next boss wave after this one (nothing when there is none).
function WaveService.Skip(which: string): ()
	local mission = ArenaService.GetMission()
	if mission == nil then
		return
	end
	local current = run.wave
	if which == "next" then
		if current < mission.waves then
			WaveService.ForceWave(current + 1)
		end
		return
	end
	if which ~= "boss" then
		return
	end
	for waveNumber = current + 1, mission.waves do
		if isBossWave(mission, waveNumber) then
			WaveService.ForceWave(waveNumber)
			return
		end
	end
end

-- Debug lever: one extra body of a crowd kind at the next rim point, with the run's scales.
function WaveService.SpawnOne(kind: string): ()
	if ArenaService.GetMission() == nil then
		return
	end
	if CrowdService.Spawn(kind, nextRimPoint(), FIGHT, Vector3.zero) ~= 0 then
		run.spawnedThisGroup += 1
	end
end

-- Debug lever: every living body dies with its normal rewards, credited to nobody.
function WaveService.KillAll(): ()
	CrowdService.KillAll(0)
end

-- The last member left: a reserved server can be reused by a later arrival, and a service still
-- sitting in `summary` would refuse to ever start another run here.
function WaveService.Reset(): ()
	run = freshRun()
	CrowdService.Clear()
	VitalsService.ClearThreats()
	pushRunFields()
end

function WaveService.Init(): ()
	boot.mission = CombatMode.Get() == "mission"
	if not boot.mission then
		-- The range has no run: nothing here is wired, and Boot starts no loop.
		return
	end
	boot.proving = CombatMode.IsProving()
	CrowdService.OnKilled(onCrowdKilled)
	ArenaService.SetShareSource(damageShare)
	ArenaService.SetDownSource(function(userId: number): boolean
		local member = ArenaService.GetMember(userId)
		local player = if member ~= nil then member.player else nil
		return player ~= nil and VitalsService.IsDown(player)
	end)
	ArenaService.SetCharacterHook(WeaponService.PrepareCharacter)
	WeaponService.SetActGate(mayAct)
	ArenaService.SetResetHook(WaveService.Reset)
	-- From the first admit, so a lobby bar is already the gear's; Start re-sets the scales.
	VitalsService.SetMission(missionRules(nil))
end

-- The boot hook, NOT the run start: Start() above is the contract's "the lobby is ready, go".
-- Main wires this one into the ordered Init/Start pass.
function WaveService.Boot(): ()
	if not boot.mission or boot.loop ~= nil then
		return
	end
	boot.loop = RunService.Heartbeat:Connect(function(delta: number)
		tick()
		boot.broadcastAccumulator += delta
		local period = 1 / stateHz()
		if boot.broadcastAccumulator >= period then
			boot.broadcastAccumulator = 0
			broadcast()
		end
	end)
end

return WaveService
