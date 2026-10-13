--!strict
-- The run: a level's stages, its camps' waves, the rewards and the end (docs/INTERFACES.md
-- "L1 contracts" → "Flow" and "Server modules" → "B — the run"). One run per server, entirely on
-- the server clock.
--
-- L1 makes this one stage-driven machine for every level (ruling 1). The RULES of a run are not
-- here: which stage is next, when a camp triggers, when it is clear, what a checkpoint banks,
-- what ends the run, where a body belongs, what a skip does, which node is open. They are
-- StageFlow's, a pure module the harness loads and mutates (ruling 2). This file only builds
-- StageFlow's input once a tick and EXECUTES the actions it returns: it moves the crowd's floor,
-- closes and opens gates, queues waves, banks the pool, moves bodies.
--
-- Kept from P5, unchanged in meaning:
-- * Waves are crowd groups arriving in bursts at the camp's spawn points; a kill pays its kind's
--   fixed reward into a pool and books the HP its body lost per player (CrowdKillInfo).
-- * The pacing director only ever changes PACING (burst interval, merges, breather length, the
--   one extra elite), never enemy HP or damage.
-- * This is the only place under src/combat that writes a profile, and it writes nothing but
--   cash, materials, Valor, combat stats and (for a level that names a mission) its record.
-- * Nothing in the tick yields. The level's removal is deferred out of it.
--
-- New with L1: only a checkpoint pays (ruling 15: whatever ends the run drops the pool that was
-- not banked); every run ends in a summary and then the lobby camp, never the city (ruling 20);
-- the leader starts a level with RequestStartLevel (ruling 7); stars are session memory, kept
-- here per userId (ruling 25).

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
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local CrowdService = require(script.Parent:WaitForChild("CrowdService"))
local VitalsService = require(script.Parent:WaitForChild("VitalsService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local RunFx = require(script.Parent:WaitForChild("RunFx"))
local StageFlow = require(script.Parent:WaitForChild("StageFlow"))
local LevelService = require(script.Parent:WaitForChild("LevelService"))
local LevelGeometry = require(script.Parent:WaitForChild("LevelGeometry"))

-- Degrade value: without Combat.json the place never leaves the lobby, but the broadcast loop
-- still needs a legal period.
local DEFAULT_STATE_HZ = 4
local FIGHT = "fight"
-- halfSize.Y handed to CrowdService.SetBounds: the highest a launch may carry a body above a
-- camp's floor. Layouts have no ceiling, so it is generous rather than tuned (P1's value).
local CROWD_CEILING = 200

-- One burst of one group: up to crowd.burst bodies of a kind, arriving together at one spawn
-- point in a grid. `placed` survives a hold (maxAlive, or a refused spawn), so the grid carries on.
type Burst = { kind: string, left: number, placed: number, at: Vector3? }
type Pool = Combat.RewardPool
type StartRefusal = "notLeader" | "busy" | "locked" | "unavailable"

-- Everything a run holds, in one table (Studio's 200-local limit and one place to reset).
type Run = {
	phase: Types.RunPhase,
	-- What is played: nil in the lobby. `flow` is StageFlow's state, moved on by its rules alone.
	level: Types.LevelConfig?,
	plan: StageFlow.Plan?,
	flow: StageFlow.State?,
	scales: Types.LevelDifficulty?,
	-- The played difficulty's place in Expeditions.json `difficulties` (minDifficulty reads it).
	rank: number,
	-- The live camp's wave.
	merged: boolean,
	queue: { Burst },
	-- Bodies the current group's waves queued (the director's elite and lever spawns included; a
	-- boss and what it summons are not), for the merge test's dead fraction.
	spawnedThisGroup: number,
	spec: Combat.CrowdWaveSpec?,
	bossPending: Types.MissionCrowdBoss?,
	bossHpMult: number,
	-- The living boss body's crowd id (0 = none), the Valor its kill pays, and its name.
	bossId: number,
	bossValor: number,
	bossName: string?,
	burstsThisWave: number,
	spawnCursor: number,
	nextBurstAt: number,
	-- Bodies the live camp's later waves will field, for RunState.left.
	laterBodies: number,
	-- os.clock() the live camp's gates closed: the director's warmup counts from it.
	campClosedAt: number,
	-- The crowd's floor from a camp's trigger until it is cleared (ruling 30).
	floor: Types.RunFloor?,
	maxAlive: number,
	runEndsAt: number,
	-- os.clock() the summary ends and the party is back in the lobby; 0 = nothing pending.
	returnAt: number,
	tempo: number,
	pool: Pool,
	killsByUser: { [number]: number },
	bossClearsThisFlush: number,
	killStamps: { number },
	-- The damage split of the current pool, and of the whole run (PartyMember.damageShare and
	-- RunSummary.damageShare read the latter; it is never drained mid-run).
	damageTally: { [number]: number },
	runDamage: { [number]: number },
	runDamageTotal: number,
	-- Checkpoints banked this run, and the stage name of the last one ("" = nothing was banked).
	banked: number,
	savedAt: string,
}

local function emptyPool(): Pool
	return { cash = 0, materials = 0, valor = 0, kills = 0 }
end

local function freshRun(): Run
	return {
		phase = "lobby",
		level = nil,
		plan = nil,
		flow = nil,
		scales = nil,
		rank = 0,
		merged = false,
		queue = {},
		spawnedThisGroup = 0,
		spec = nil,
		bossPending = nil,
		bossHpMult = 1,
		bossId = 0,
		bossValor = 0,
		bossName = nil,
		burstsThisWave = 0,
		spawnCursor = 0,
		nextBurstAt = 0,
		laterBodies = 0,
		campClosedAt = 0,
		floor = nil,
		maxAlive = 0,
		runEndsAt = 0,
		returnAt = 0,
		tempo = 1,
		pool = emptyPool(),
		killsByUser = {},
		bossClearsThisFlush = 0,
		killStamps = {},
		damageTally = {},
		runDamage = {},
		runDamageTotal = 0,
		banked = 0,
		savedAt = "",
	}
end

local run = freshRun()
-- What outlives a run, for the life of the server.
local boot = {
	mission = false,
	proving = false,
	-- Crowd kinds a level named that ProvingGrounds.json does not have, warned once each.
	warnedKinds = {} :: { [string]: boolean },
	warnedNoMap = false,
	-- os.clock() a member was last put back on the ground, by userId.
	rescuedAt = {} :: { [number]: number },
	broadcastAccumulator = 0,
	loop = nil :: RBXScriptConnection?,
	-- Ruling 25: the stars of this session, by userId. Kept when a member leaves and comes back.
	stars = {} :: { [number]: StageFlow.Stars },
	-- The leader the last MapState was computed for: a change sends a new one to everybody.
	mapLeader = 0,
	-- os.clock() of the last return to the lobby (the start cooldown), and of the moment the
	-- lobby first held a human since then (the proving auto-start); 0 = not yet.
	returnedAt = 0,
	lobbySince = 0,
	-- A return to the lobby is deferred out of the tick: this keeps it to one.
	returning = false,
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

local function isLive(phase: Types.RunPhase): boolean
	return phase == "travel"
		or phase == "gate"
		or phase == "wave"
		or phase == "boss"
		or phase == "breather"
end

-- The stage the run is in, as the plan has it (nil in the lobby).
local function currentStage(): StageFlow.Stage?
	local plan = run.plan
	local flow = run.flow
	if plan == nil or flow == nil then
		return nil
	end
	return plan.stages[flow.stage]
end

-- The camp whose floor the crowd stands on: the current stage's zone, in its countdown, its
-- fight and its breathers.
local function liveZone(): (StageFlow.Stage?, StageFlow.Zone?)
	local flow = run.flow
	local stage = currentStage()
	if flow == nil or stage == nil then
		return nil, nil
	end
	local step = flow.step
	if step ~= "gate" and step ~= "fight" and step ~= "breather" then
		return nil, nil
	end
	return stage, stage.zone
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
	local plan = run.plan
	local flow = run.flow
	local stage = currentStage()
	local inCamp = flow ~= nil and (flow.step == "fight" or flow.step == "breather")
	local alive = CrowdService.AliveCount()
	local queued = queuedBodies()
	ArenaService.SetRunFields({
		phase = phase,
		wave = if flow ~= nil and inCamp then flow.wave else 0,
		waves = if stage ~= nil then stage.waves else 0,
		alive = alive,
		remaining = queued,
		tempo = run.tempo,
		merged = run.merged,
		breatherEndsIn = if phase == "breather" and flow ~= nil
			then math.max(0, flow.breatherUntil - now)
			else nil,
		runEndsIn = if run.runEndsAt > 0 then math.max(0, run.runEndsAt - now) else 0,
		inRun = isLive(phase),
		returnIn = if phase == "summary" and run.returnAt > 0
			then math.max(0, run.returnAt - now)
			else nil,
		stage = if flow ~= nil then flow.stage else 0,
		stages = if plan ~= nil then #plan.stages else 0,
		stageKind = if stage ~= nil then stage.kind else "",
		stageName = if stage ~= nil then stage.name else "",
		campsCleared = if flow ~= nil then flow.cleared else 0,
		camps = if plan ~= nil then plan.camps else 0,
		left = if inCamp then alive + queued + run.laterBodies else 0,
		bossName = if run.bossId ~= 0 or run.bossPending ~= nil then run.bossName else nil,
		gateIn = if phase == "gate" and flow ~= nil then math.max(0, flow.gateAt - now) else nil,
		banked = run.banked,
		floor = run.floor,
		maxAlive = run.maxAlive,
	})
end

local function broadcast(): ()
	pushRunFields()
	ArenaService.Broadcast(run.phase)
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

local function rootOf(member: Types.RunMember): BasePart?
	local character = member.character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- P5 ruling 13: in the fight right now (admitted, not waiting, alive). Down is VitalsService's.
local function mayJudge(player: Player): boolean
	local member = ArenaService.GetMemberFor(player)
	return member ~= nil and ArenaService.IsFighting(member)
end

-- L1 ruling 8: a member may act in the five live phases, fighting and standing.
local function mayAct(player: Player): boolean
	return ArenaService.InRun() and mayJudge(player) and not VitalsService.IsDown(player)
end

-- P5 ruling 11: the player's gear decides their bar (WeaponService.GearOf knows which gear).
local function maxHpOf(player: Player): number?
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		return nil
	end
	local gear, ascension = WeaponService.GearOf(player)
	return Armory.MaxHp(armoryConfig, gear, ascension)
end

-- The rules VitalsService fights by. Neutral in the lobby (no enemy there, but the bar must
-- already be the gear's); a run sets its difficulty's damage scale and its level's regen.
local function missionRules(damageScale: number, regenShare: number): VitalsService.MissionRules
	return {
		mayJudge = mayJudge,
		onDown = function(player: Player)
			WaveService.OnDown(player)
		end,
		maxHpOf = maxHpOf,
		damageScale = damageScale,
		regenShare = regenShare,
	}
end

-- P5 ruling 18: every downed member stands up at a boundary (until the L5 revive).
local function standUpDowned(): ()
	for _, player in humanPlayers() do
		if VitalsService.IsDown(player) then
			VitalsService.StandUp(player)
		end
	end
end

-- The map ------------------------------------------------------------------------------------

local function starsOf(userId: number): StageFlow.Stars
	local stars = boot.stars[userId]
	if stars == nil then
		stars = {}
		boot.stars[userId] = stars
	end
	return stars
end

-- Ruling 28: a node is built when a level file with its `level` id exists.
local function builtLevels(): { [string]: boolean }
	local built: { [string]: boolean } = {}
	for _, id in Catalog.GetLevelIds() do
		built[id] = true
	end
	return built
end

-- The place of every difficulty in Expeditions.json (the order is the rank).
local function difficultyRanks(map: Types.ExpeditionsConfig): { [string]: number }
	local ranks: { [string]: number } = {}
	for index, name in map.difficulties do
		ranks[name] = index
	end
	return ranks
end

-- Rulings 25 and 28: each member gets their own stars; which nodes are open is the leader's
-- doing. Sent at every admit, after every run and when the leader changes; `only` = to that one
-- member (a client that asks for its snapshot again cannot ask for the map).
local function sendMapState(only: Player?): ()
	local map = Catalog.GetExpeditionsConfig()
	if map == nil then
		if not boot.warnedNoMap then
			boot.warnedNoMap = true
			warn(
				"[WaveService] Config/Expeditions is missing: no map, the place stays in its lobby"
			)
		end
		return
	end
	local leader = ArenaService.LeaderUserId()
	if only == nil then
		boot.mapLeader = leader
	end
	local built = builtLevels()
	local leaderStars = starsOf(leader)
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if not member.bot and player ~= nil and (only == nil or player == only) then
			RemoteService.FireClient(
				player,
				"MapState",
				StageFlow.MapState(map, built, leaderStars, starsOf(member.userId), leader)
			)
		end
	end
end

-- The director -------------------------------------------------------------------------------

-- Kills inside director.windowSeconds, against the pace the wave was budgeted for. Held at 1.0
-- through the warmup after a camp's gates close, so its first seconds never trigger a merge or
-- an elite (P5 counted the warmup from the run's start, which was its one camp's).
local function updateTempo(combatConfig: Types.CombatConfig, stage: StageFlow.Stage): ()
	local director = combatConfig.director
	local now = os.clock()
	local cutoff = now - director.windowSeconds
	local stamps = run.killStamps
	while #stamps > 0 and stamps[1] < cutoff do
		table.remove(stamps, 1)
	end
	if now - run.campClosedAt < director.tempoWarmupSeconds then
		run.tempo = 1
		return
	end
	local spec = run.spec
	local total = if spec ~= nil then spec.total else 0
	local expected = if stage.targetWaveSeconds > 0 then total / stage.targetWaveSeconds else 0
	run.tempo = Combat.Tempo(#stamps, director.windowSeconds, expected, director)
end

local function knownKind(kind: string): boolean
	if Tuning.Get().crowd.kinds[kind] ~= nil then
		return true
	end
	if not boot.warnedKinds[kind] then
		boot.warnedKinds[kind] = true
		warn(`[WaveService] unknown crowd kind "{kind}" in a level's waves; dropped`)
	end
	return false
end

-- One wave of the live camp, resolved for the run's difficulty and party (Combat.CampWave).
local function waveSpec(
	level: Types.LevelConfig,
	stageIndex: number,
	wave: number,
	combatConfig: Types.CombatConfig
): Combat.CrowdWaveSpec?
	local stageDef = level.stages[stageIndex]
	local waves = if stageDef ~= nil then stageDef.waves else nil
	local waveDef = if waves ~= nil then waves[wave] else nil
	local scales = run.scales
	local map = Catalog.GetExpeditionsConfig()
	if waveDef == nil or scales == nil or map == nil then
		return nil
	end
	local spec = Combat.CampWave(
		waveDef,
		level.crowd.regenShare,
		scales,
		run.rank,
		difficultyRanks(map),
		ArenaService.PartySize(),
		combatConfig
	)
	spec.wave = wave
	return spec
end

-- Queues one wave's groups as bursts, the boss to be placed first. P5 ruling 17: a boss wave
-- takes no extra elite (bosses are judged as whole fights). `merged` = the director folded it in
-- on top of the wave before it.
local function queueWave(stageIndex: number, wave: number, merged: boolean): ()
	local level = run.level
	local combatConfig = config()
	local plan = run.plan
	local stage = if plan ~= nil then plan.stages[stageIndex] else nil
	if level == nil or combatConfig == nil or stage == nil then
		return
	end
	if not merged then
		-- A new wave, not one folded in: the field is this wave's alone.
		run.spawnedThisGroup = 0
		run.bossId = 0
		run.bossPending = nil
		run.queue = {}
	end
	run.merged = merged
	local spec = waveSpec(level, stageIndex, wave, combatConfig)
	run.spec = spec
	if spec == nil then
		warn(`[WaveService] {level.id} stage {stageIndex} has no wave {wave}; nothing spawns`)
		return
	end
	local crowd = level.crowd
	local burstSize = math.max(math.floor(crowd.burst), 1)
	local bursts = 0
	local queued = 0
	-- A kind ProvingGrounds.json does not have is dropped here, with one warn: CrowdService.Spawn
	-- answers 0 for it exactly as for "no room", and a burst that can never spawn would hold the
	-- head of the queue until the run cap.
	local function add(kind: string, count: number): ()
		if not knownKind(kind) then
			return
		end
		local left = count
		while left > 0 do
			local size = math.min(left, burstSize)
			table.insert(run.queue, { kind = kind, left = size, placed = 0, at = nil })
			left -= size
			bursts += 1
		end
		queued += count
	end
	for _, group in spec.groups do
		add(group.kind, group.count)
	end
	local boss = spec.boss
	local elite = crowd.eliteKind
	if boss == nil and elite ~= nil and run.tempo >= combatConfig.director.eliteTempo then
		add(elite, 1)
	end
	if boss ~= nil and knownKind(boss.kind) then
		run.bossPending = boss
		run.bossHpMult = spec.bossHpMult
		-- Ruling 23: the difficulty's rewardMult multiplies the boss's Valor too.
		run.bossValor = math.round(boss.valor * spec.rewardMult)
		local def = Tuning.Get().crowd.kinds[boss.kind]
		run.bossName = if def ~= nil and def.name ~= nil then def.name else boss.kind
	end
	run.burstsThisWave = bursts
	run.spawnedThisGroup += queued
	run.nextBurstAt = os.clock()
	-- What the camp's later waves will still field (RunState.left).
	local later = 0
	for following = wave + 1, stage.waves do
		local followingSpec = waveSpec(level, stageIndex, following, combatConfig)
		if followingSpec ~= nil then
			later += followingSpec.total
		end
	end
	run.laterBodies = later
	if stage.waves > 1 then
		-- A camp of one wave announces itself with its gates; only a camp of several counts waves.
		RunFx.Push({
			kind = "wave",
			wave = wave,
			merged = merged,
			boss = run.bossPending ~= nil,
		})
	end
end

-- Rewards -------------------------------------------------------------------------------------

local function missionRecord(state: Types.PlayerState, missionId: string): Types.MissionRecord
	local record = state.combat.missions[missionId]
	if record == nil then
		record = { bestWave = 0, bossClears = 0, overdriveBest = 0 }
		state.combat.missions[missionId] = record
	end
	return record
end

-- Mentor bonus at a banked boss clear (docs/INTERFACES.md "C2 contracts"): each human is paid
-- Combat.MentorBonus against the rates of the OTHER members present whose raw share of THIS
-- pool reached coop.mentorMinDamageShare, so an idle alt parked in the party earns its main
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
		-- Same floor as a mentee (lead ruling): a mentor waiting in the lobby camp, or one who
		-- let the party carry the boss, earns nothing for "carrying".
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

-- A checkpoint (ruling 15): the pool, split by damage share with a floor and written straight
-- into the profiles. `waveNumber` is the live camp's wave that was just cleared and `waveCount`
-- how many waves this bank covers. Only a checkpoint calls this: nothing that ends a run does.
local function flushPool(waveNumber: number, waveCount: number): ()
	local level = run.level
	local combatConfig = config()
	if level == nil or combatConfig == nil then
		return
	end
	local tally = run.damageTally
	run.damageTally = {}
	if next(tally) == nil then
		-- Nobody damaged anything that died (the killAll lever, or a boss's fight ended by it):
		-- the pot is still theirs. Zero damage each is an even split (ContributionShares).
		for _, member in ArenaService.GetMembers() do
			if not member.waiting then
				tally[member.userId] = 0
			end
		end
	end
	if run.bossClearsThisFlush > 0 then
		-- Before the per-member loop below, whose snapshot then carries the Mentor Valor too.
		payMentors(combatConfig, tally)
	end
	local shares = Combat.ContributionShares(tally, combatConfig.coop.contributionFloor)
	local split = Combat.SplitPool(run.pool, shares)
	local gameConfig = Catalog.GetGameConfig()
	local shopConfig = Catalog.GetLegacyShopConfig()
	local material = level.material
	local missionId = level.mission

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
			if share.materials > 0 and material ~= "" then
				local owned = state.combat.materials[material] or 0
				state.combat.materials[material] = owned + share.materials
			end
			state.combat.stats.cashFromCombat += cash
			ArenaService.CreditSummary(
				member.userId,
				cash,
				material,
				share.materials,
				share.valor,
				kills
			)
		end
		state.combat.stats.kills += kills
		state.combat.stats.wavesCleared += waveCount
		if missionId ~= nil then
			-- Ruling 26: only a level that names a mission writes a mission record (the arena
			-- writes `village`, as before). Forest Road writes none.
			local record = missionRecord(state, missionId)
			record.bestWave = math.max(record.bestWave, waveNumber)
			record.bossClears += run.bossClearsThisFlush
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
	run.laterBodies = 0
	CrowdService.Clear()
	VitalsService.ClearThreats()
	WeaponService.AbandonProjectiles()
end

-- P5 ruling 14: a kill pays its kind's fixed reward into the pool and books the HP its body
-- lost. Runs inside the strike that killed it (CrowdService's callbacks are synchronous threads),
-- so it must not yield.
local function onCrowdKilled(id: number, byUserId: number, info: CrowdService.CrowdKillInfo): ()
	local phase = run.phase
	local level = run.level
	if level == nil or (phase ~= "wave" and phase ~= "boss" and phase ~= "breather") then
		return
	end
	local spec = run.spec
	if spec ~= nil then
		local cash, materials = Combat.CampReward(level.crowd.rewards, info.kind, spec)
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
		RunFx.Push({ kind = "bossDown", name = run.bossName or info.kind, valor = run.bossValor })
	end
end

-- Spawning ------------------------------------------------------------------------------------

local function centreOf(zone: StageFlow.Zone): Vector3
	return Vector3.new(zone.rect.x, zone.floorY, zone.rect.z)
end

-- The camp's next spawn point, round-robin; its centre when it has none.
local function nextSpawnPoint(zone: StageFlow.Zone): Vector3
	local points = zone.spawns
	if #points == 0 then
		return centreOf(zone)
	end
	run.spawnCursor += 1
	return points[(run.spawnCursor - 1) % #points + 1]
end

-- The boss first, at its own spot in the camp, with the party HP factor (P5 ruling 16). A
-- refused spawn stays pending and is tried again next frame.
local function spawnBoss(zone: StageFlow.Zone): ()
	local boss = run.bossPending
	if boss == nil then
		return
	end
	local at = StageFlow.BossPoint(zone, boss.at)
	local id = CrowdService.Spawn(boss.kind, at, FIGHT, centreOf(zone), run.bossHpMult)
	if id ~= 0 then
		run.bossPending = nil
		run.bossId = id
	end
end

-- P5 ruling 15: the next burst, when its time has come and the field has room. A burst held by
-- maxAlive (or a refused spawn) stays at the head of the queue and carries on as room frees.
local function spawnBursts(stage: StageFlow.Stage, zone: StageFlow.Zone): ()
	local level = run.level
	local burst = run.queue[1]
	if level == nil or burst == nil then
		return
	end
	local now = os.clock()
	if burst.placed == 0 and now < run.nextBurstAt then
		return
	end
	local crowd = level.crowd
	local at: Vector3 = burst.at or nextSpawnPoint(zone)
	burst.at = at
	local size = burst.placed + burst.left
	local centre = centreOf(zone)
	while burst.left > 0 and CrowdService.AliveCount() < stage.maxAlive do
		local position = StageFlow.BurstPoint(zone, at, size, burst.placed, crowd.burstSpacing)
		if CrowdService.Spawn(burst.kind, position, FIGHT, centre) == 0 then
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
		+ Combat.BurstSeconds(stage.targetWaveSeconds, run.burstsThisWave, run.tempo)
end

-- Bodies --------------------------------------------------------------------------------------

-- Humans in the fight (waiting members are in the lobby camp and do not count), and how many
-- humans are alive there, waiting.
local function humanCounts(): (number, number)
	local fighters = 0
	local waitingAlive = 0
	for _, member in ArenaService.GetMembers() do
		if member.bot then
			continue
		end
		if not member.waiting then
			fighters += 1
		elseif ArenaService.IsAlive(member) then
			waitingAlive += 1
		end
	end
	return fighters, waitingAlive
end

-- Ruling 18: where a member's body belongs right now, and whether they wait. A character added
-- during `wave` or `boss` waits in the lobby camp until the next boundary; one added in any
-- other live phase goes to the run's safe point; in the lobby and on the summary, the lobby camp.
local function placer(_member: Types.RunMember): (Vector3, boolean)
	local plan = run.plan
	local flow = run.flow
	local phase: Types.RunPhase = run.phase
	if plan == nil or flow == nil or not isLive(phase) then
		return LevelService.LobbyPoint(), false
	end
	if phase == "wave" or phase == "boss" then
		return LevelService.LobbyPoint(), true
	end
	return StageFlow.SafePoint(plan, flow), false
end

-- The lobby's kill height: its layout's, else well under its blocks.
local function lobbyKillY(bounds: LevelGeometry.Bounds, margin: number): number
	local map = Catalog.GetExpeditionsConfig()
	local layout = if map ~= nil then Catalog.GetLevelLayout(map.lobby.layout) else nil
	if layout ~= nil and layout.arena == nil then
		return layout.killY
	end
	return bounds.minY - margin
end

-- Ruling 19: a human whose root is under the kill height or outside the box is put at the safe
-- point with the get-up i-frames. Never a down, no cost, in every phase: falling out is the
-- level's fault. A waiting member, and everyone when no level is live, is judged against the
-- lobby camp and put on a lobby point. A member just rescued is left alone for the length of
-- those i-frames: their client still reports the old place for a frame or two, and a second
-- rescue would only move them again. Without Combat.json player.rescue nobody is rescued.
local function rescueFallen(combatConfig: Types.CombatConfig): ()
	local rescue = combatConfig.player.rescue
	if rescue == nil then
		return
	end
	local rules = combatConfig.levels
	local now = os.clock()
	local iframes = Tuning.Get().player.getUpIframes
	local plan = run.plan
	local flow = run.flow
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		local root = rootOf(member)
		if member.bot or player == nil or root == nil or not ArenaService.IsAlive(member) then
			continue
		end
		local last = boot.rescuedAt[member.userId]
		if last ~= nil and now - last < iframes then
			continue
		end
		local position = root.Position
		local target: Vector3? = nil
		if plan == nil or flow == nil or member.waiting then
			local bounds = LevelService.LobbyBounds()
			local killY = lobbyKillY(bounds, rules.boxMargin)
			if StageFlow.OutOfBox(bounds, killY, position, rules.boxMargin) then
				target = LevelService.LobbyPoint()
			end
		elseif StageFlow.IsOut(plan, flow, position, rescue, rules.boxMargin) then
			target = StageFlow.SafePoint(plan, flow)
		end
		if target ~= nil and ArenaService.MoveMember(member, target) then
			boot.rescuedAt[member.userId] = now
			WeaponService.GrantIframes(player, iframes)
		end
	end
end

-- Every fighting member's body goes to `feet` (a skip's `move`). With `closing`, the camp whose
-- gates are closing, only those StageFlow says must be brought inside (MustEnter).
local function moveFighters(feet: Vector3, closing: StageFlow.Zone?): ()
	for _, member in ArenaService.GetMembers() do
		if member.bot or not ArenaService.IsFighting(member) then
			continue
		end
		if closing ~= nil then
			local root = rootOf(member)
			if root == nil or not StageFlow.MustEnter(closing, root.Position) then
				continue
			end
		end
		ArenaService.MoveMember(member, feet)
	end
end

-- The run's end -------------------------------------------------------------------------------

-- P5's reason rule for a lost run: "down" when a fighter is down, "wipe" when every one of
-- them died outright (a reset). nil while somebody stands. Also returns the fighters.
local function fallenReason(): (string?, { number })
	local members = ArenaService.GetMembers()
	local lost, fallen = VitalsService.RunLost(members, false)
	if not lost then
		return nil, fallen
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
	return reason, fallen
end

-- Ruling 20: every run ends in a summary. What was not banked is dropped (ruling 15: only a
-- checkpoint pays); the field is cleared; a lost run marks its fallen; a cleared one gives the
-- star of its difficulty to every human who was fighting at the end (ruling 25). The level
-- stays built while the card is up.
function WaveService.EndRun(reason: string): ()
	local plan = run.plan
	local flow = run.flow
	local level = run.level
	if plan == nil or flow == nil or level == nil or not isLive(run.phase) then
		return
	end
	-- For a caller that did not come through StageFlow's own `end`.
	StageFlow.Finish(plan, flow, reason)
	run.pool = emptyPool()
	run.killsByUser = {}
	run.damageTally = {}
	run.bossClearsThisFlush = 0
	if reason == "down" or reason == "wipe" then
		local _lost, fallen = fallenReason()
		for _, userId in fallen do
			ArenaService.MarkDied(userId)
		end
	end
	clearField()
	run.spec = nil
	run.floor = nil

	local results: { [number]: Types.RunResult } = {}
	for _, member in ArenaService.GetMembers() do
		if member.bot or member.player == nil then
			continue
		end
		local star = false
		if reason == "cleared" and not member.waiting then
			star = StageFlow.Award(starsOf(member.userId), plan.levelId, plan.difficulty)
		end
		results[member.userId] = {
			levelId = level.id,
			levelName = level.name,
			difficulty = plan.difficulty,
			reason = reason,
			campsCleared = flow.cleared,
			camps = plan.camps,
			savedAt = run.savedAt,
			star = star,
		}
	end
	ArenaService.SetResults(results)

	run.phase = "summary"
	local combatConfig = config()
	run.returnAt = os.clock()
		+ (if combatConfig ~= nil then combatConfig.coop.returnGroupSeconds else 0)
	pushRunFields()
	ArenaService.BroadcastSummary()
	print(`[WaveService] run ended ({reason}): {level.id} {plan.difficulty}, stage {flow.stage}`)
end

-- Ruling 20: after the summary, the lobby. Everyone stands up and is moved to the lobby camp,
-- the level is removed, and the phase is `lobby`. Nobody is sent to the city. Deferred out of
-- the tick (it destroys the level's Instances), or called at once from RequestAbandon.
local function backToLobby(): ()
	boot.returning = false
	if run.phase ~= "summary" then
		return
	end
	standUpDowned()
	for _, member in ArenaService.GetMembers() do
		if member.bot or member.player == nil then
			continue
		end
		member.waiting = false
		ArenaService.MoveMember(member, LevelService.LobbyPoint())
	end
	LevelService.Clear()
	clearField()
	run = freshRun()
	ArenaService.SetLevel(nil)
	VitalsService.SetMission(missionRules(1, 0))
	boot.returnedAt = os.clock()
	boot.lobbySince = 0
	broadcast()
	sendMapState(nil)
	-- Joinable again (ruling 6).
	ArenaService.PublishRun()
end

-- Executing StageFlow's actions ---------------------------------------------------------------

-- Ruling 11: the crowd's floor is set at a camp's trigger, with no body alive.
local function setCrowdFloor(stage: StageFlow.Stage, zone: StageFlow.Zone): ()
	CrowdService.Clear()
	VitalsService.ClearThreats()
	local centre = centreOf(zone)
	local half = Vector3.new(zone.rect.hx, CROWD_CEILING, zone.rect.hz)
	CrowdService.SetBounds(centre, half)
	WeaponService.SetArena(centre, half)
	run.floor = {
		x = zone.rect.x,
		y = zone.floorY,
		z = zone.rect.z,
		hx = zone.rect.hx,
		hz = zone.rect.hz,
	}
	run.maxAlive = stage.maxAlive
end

-- The contract's table "What WaveService does for each action", in the order StageFlow gave.
local function execute(actions: { StageFlow.Action }): ()
	local plan = run.plan
	local flow = run.flow
	if plan == nil or flow == nil or #actions == 0 then
		return
	end
	-- The stage a `bank` of this batch paid for: its `open` then says the progress was saved.
	local bankedStage = 0
	for _, action in actions do
		local stage = plan.stages[action.stage]
		local zone = if stage ~= nil then stage.zone else nil
		local kind = action.kind
		if kind == "gate" then
			if stage ~= nil and zone ~= nil then
				setCrowdFloor(stage, zone)
			end
		elseif kind == "close" then
			if stage ~= nil and zone ~= nil then
				-- Both in this frame, the move first: the wall that turns solid is 8 studs deep
				-- outside the fence line and runs across the gate gaps, so whoever stands off the
				-- floor or against its edge (in a gap, on the road) would be inside a solid Part.
				moveFighters(zone.entry, zone)
				LevelService.SetCamp(zone.id, "closed")
				run.tempo = 1
				run.killStamps = {}
				run.campClosedAt = os.clock()
				RunFx.Push({ kind = "camp", event = "closed", name = stage.name, saved = false })
			end
		elseif kind == "wave" then
			queueWave(action.stage, action.wave or 1, action.merged == true)
		elseif kind == "clear" then
			-- What the dead still had in the air (a lob, a slinger's shot) goes with them:
			-- nothing lands on an empty field.
			VitalsService.ClearThreats()
		elseif kind == "bank" then
			flushPool(action.wave or 0, action.count or 0)
			run.banked += 1
			run.savedAt = if stage ~= nil then stage.name else ""
			bankedStage = action.stage
		elseif kind == "boundary" then
			standUpDowned()
			ArenaService.ReleaseWaiting(StageFlow.SafePoint(plan, flow))
		elseif kind == "open" then
			if stage ~= nil and zone ~= nil then
				LevelService.SetCamp(zone.id, "cleared")
				RunFx.Push({
					kind = "camp",
					event = "cleared",
					name = stage.name,
					saved = bankedStage == action.stage,
				})
			end
			run.floor = nil
			run.spec = nil
		elseif kind == "drop" then
			clearField()
		elseif kind == "move" then
			if zone ~= nil then
				moveFighters(zone.entry, nil)
			end
		elseif kind == "end" then
			WaveService.EndRun(action.reason or "cleared")
		end
		-- `breather` and `travel` change nothing here: StageFlow's state carries the time, and the
		-- broadcast below carries the news.
	end
end

-- What the HUD is told, from StageFlow's step. Once the run is over the phase is EndRun's.
local function syncPhase(): ()
	local flow = run.flow
	if flow == nil or not isLive(run.phase) then
		return
	end
	run.phase = StageFlow.Phase(flow, run.bossId ~= 0 or run.bossPending ~= nil)
end

-- One question to StageFlow, asked by the tick every frame and by OnDown at once: what happens
-- now? Its input is built here, once.
local function advance(combatConfig: Types.CombatConfig): ()
	local plan = run.plan
	local flow = run.flow
	if plan == nil or flow == nil or not isLive(run.phase) then
		return
	end
	local now = os.clock()
	local roots: { Vector3 } = {}
	for _, member in ArenaService.GetMembers() do
		if not member.bot and ArenaService.IsFighting(member) then
			local root = rootOf(member)
			if root ~= nil then
				table.insert(roots, root.Position)
			end
		end
	end
	local alive = CrowdService.AliveCount()
	local spawningDone = #run.queue == 0 and run.bossPending == nil
	local spawned = run.spawnedThisGroup
	local deadFraction = if spawned > 0 then math.max(spawned - alive, 0) / spawned else 0
	local fallen = fallenReason()
	local before = run.phase
	local actions = StageFlow.Advance(plan, flow, {
		now = now,
		roots = roots,
		fieldClear = spawningDone and alive == 0,
		spawningDone = spawningDone,
		mergeOk = Combat.ShouldMerge(run.tempo, deadFraction, combatConfig.director),
		breatherSeconds = Combat.BreatherSeconds(run.tempo, combatConfig.director),
		fallen = fallen,
		runCap = run.runEndsAt > 0 and now >= run.runEndsAt,
	}, combatConfig.levels)
	execute(actions)
	syncPhase()
	-- RunState goes out at once on every action, and on a phase change no action announced (a
	-- boss placed, a boss killed).
	if isLive(run.phase) and (#actions > 0 or run.phase ~= before) then
		broadcast()
	end
end

-- Starting a level ----------------------------------------------------------------------------

-- Spelled out so the literal types survive: a singleton union that has passed through a local
-- reaches the next call as plain `string` under the old solver.
local function refuseStart(player: Player, levelId: string, reason: string): ()
	local result: Types.ActionResult = {
		action = "startLevel",
		slotId = levelId,
		ok = false,
		reason = if reason == "notLeader"
			then "notLeader"
			elseif reason == "busy" then "busy"
			elseif reason == "locked" then "locked"
			else "unavailable",
	}
	RemoteService.FireClient(player, "ActionResult", result)
end

-- The level file, its layout and its difficulty, resolved and validated. nil = `unavailable`
-- (every problem is warned). The Raider Arena comes through the two adapters (ruling 27).
local function resolveLevel(
	levelId: string,
	difficulty: string,
	combatConfig: Types.CombatConfig,
	map: Types.ExpeditionsConfig
): (Types.LevelConfig?, Types.LevelLayout?)
	local file = Catalog.GetLevelFile(levelId)
	if file == nil or not WeaponService.IsActive() then
		return nil, nil
	end
	local missionId = file.mission
	local mission = if missionId ~= nil then Catalog.GetMissionById(missionId) else nil
	local level = StageFlow.Resolve(file, mission, combatConfig.director.runCapSeconds)
	local layout = Catalog.GetLevelLayout(file.layout)
	if level == nil or layout == nil then
		warn(`[WaveService] level {levelId}: its file or its layout {file.layout} is incomplete`)
		return nil, nil
	end
	local arenaName = layout.arena
	if arenaName ~= nil then
		local arena = Catalog.GetArenaLayout(arenaName)
		if arena == nil then
			warn(`[WaveService] level {levelId}: no Layouts/Arenas/{arenaName}`)
			return nil, nil
		end
		-- P5's rescue rule for the arena: the kill height is the floor (0) less rescue.below.
		local rescue = combatConfig.player.rescue
		layout = LevelGeometry.FromArena(arena, -(if rescue ~= nil then rescue.below else 0))
	end
	if level.difficulties[difficulty] == nil then
		return nil, nil
	end
	local problems =
		StageFlow.Validate(level, layout, Tuning.Get().crowd.kinds, difficultyRanks(map))
	for _, problem in problems do
		warn(`[WaveService] {problem}`)
	end
	if #problems > 0 then
		return nil, nil
	end
	return level, layout
end

-- Starts `levelId` at `difficulty` for the leader `player`, or says why not: the contract's
-- checks, in its order. Nothing yields from the first check to the last line.
local function startLevel(player: Player, levelId: string, difficulty: string): StartRefusal?
	local combatConfig = config()
	local member = ArenaService.GetMemberFor(player)
	if not boot.mission or member == nil or member.userId ~= ArenaService.LeaderUserId() then
		return "notLeader"
	end
	if combatConfig == nil then
		return "unavailable"
	end
	local rules = combatConfig.levels
	local now = os.clock()
	if run.phase ~= "lobby" or now - boot.returnedAt < rules.startCooldownSeconds then
		return "busy"
	end
	local map = Catalog.GetExpeditionsConfig()
	if map == nil then
		return "unavailable"
	end
	-- The level's node must be open for the leader (ruling 28).
	local leaderStars = starsOf(member.userId)
	local open = false
	for _, node in map.nodes do
		if node.level == levelId then
			local state = StageFlow.NodeState(map, builtLevels(), leaderStars, leaderStars, node.id)
			open = state ~= nil and state.open
			break
		end
	end
	if not open then
		return "locked"
	end
	local level, layout = resolveLevel(levelId, difficulty, combatConfig, map)
	if level == nil or layout == nil then
		return "unavailable"
	end
	local members = ArenaService.GetMembers()
	if not ArenaService.PartyIn() or not VitalsService.AllHaveBodies(members) then
		-- A character still spawning has no body, and a run reads "no body" as fallen.
		return "busy"
	end
	local scales = level.difficulties[difficulty]
	local plan, problem =
		StageFlow.Plan(level, layout, difficulty, rules, LevelGeometry.Bounds(layout))
	if plan == nil and problem ~= nil then
		warn(`[WaveService] {problem}`)
	end
	if scales == nil or plan == nil or not LevelService.Build(layout, map, rules) then
		return "unavailable"
	end
	local flow = StageFlow.Begin(plan)

	run = freshRun()
	run.level = level
	run.plan = plan
	run.flow = flow
	run.scales = scales
	run.rank = difficultyRanks(map)[difficulty] or 0
	-- The biggest camp's cap until a camp sets its own: the client prewarms its pool with it.
	for _, stage in plan.stages do
		run.maxAlive = math.max(run.maxAlive, stage.maxAlive)
	end
	ArenaService.SetLevel({
		id = level.id,
		name = level.name,
		difficulty = difficulty,
		material = level.material,
		mission = level.mission,
	})
	ArenaService.ResetSummaries()
	clearField()
	CrowdService.SetScales({ hp = scales.hpScale, plate = scales.plateScale })
	VitalsService.SetMission(missionRules(scales.damageScale, level.crowd.regenShare))
	-- Every member starts on their feet, at full health, with the gear's bar, at the trailhead.
	local index = 0
	for _, other in members do
		local otherPlayer = other.player
		if other.bot or otherPlayer == nil then
			continue
		end
		index += 1
		other.waiting = false
		VitalsService.RefreshMaxHp(otherPlayer)
		VitalsService.StandUp(otherPlayer)
		ArenaService.MoveMember(other, StageFlow.StartPoint(plan, index, rules.startSpacing))
	end
	ArenaService.MarkRunStarted()
	run.runEndsAt = if level.runCapSeconds > 0 then now + level.runCapSeconds else 0
	run.phase = StageFlow.Phase(flow, false)
	broadcast()
	-- Closed to joiners until the party is back in the lobby (ruling 6).
	ArenaService.PublishRun()
	return nil
end

-- RequestStartLevel (ruling 7): the leader picks what is played. The remote's own thread. A
-- refusal is answered with an ActionResult; a start needs no answer, the RunState is one.
function WaveService.OnStartLevel(player: Player, levelId: string, difficulty: string): ()
	local refusal = startLevel(player, levelId, difficulty)
	if refusal ~= nil then
		refuseStart(player, levelId, refusal)
	end
end

-- The tick ------------------------------------------------------------------------------------

-- Ruling 32: with debug.provingAutoStart the server starts debug.provingLevel by itself,
-- provingStartDelay after the lobby holds a human, and again after every return.
local function tickAutoStart(combatConfig: Types.CombatConfig): ()
	local debugConfig = combatConfig.debug
	if not boot.proving or not debugConfig.provingAutoStart then
		return
	end
	local leader = ArenaService.GetMember(ArenaService.LeaderUserId())
	local player = if leader ~= nil then leader.player else nil
	if player == nil then
		boot.lobbySince = 0
		return
	end
	local now = os.clock()
	if boot.lobbySince == 0 then
		boot.lobbySince = now
	end
	if now - boot.lobbySince < debugConfig.provingStartDelay then
		return
	end
	-- A refusal (a body still spawning, a level that cannot be built) waits the delay again
	-- rather than asking every frame, and is not sent to the client as a toast.
	boot.lobbySince = now
	local refusal = startLevel(player, debugConfig.provingLevel, debugConfig.provingDifficulty)
	if refusal ~= nil then
		warn(`[WaveService] proving auto-start of {debugConfig.provingLevel} refused: {refusal}`)
	end
end

local function tick(): ()
	local combatConfig = config()
	if combatConfig == nil then
		return
	end
	rescueFallen(combatConfig)
	local phase = run.phase
	if phase == "lobby" then
		tickAutoStart(combatConfig)
		if run.phase == "lobby" and ArenaService.LeaderUserId() ~= boot.mapLeader then
			sendMapState(nil)
		end
		return
	end
	if phase == "summary" then
		if run.returnAt > 0 and os.clock() >= run.returnAt and not boot.returning then
			-- Deferred: the return destroys the level's Instances, which has no place in a tick.
			boot.returning = true
			task.defer(backToLobby)
		end
		return
	end
	if phase == "ended" then
		return
	end

	local stage, zone = liveZone()
	local flow = run.flow
	if stage ~= nil and flow ~= nil and flow.step == FIGHT then
		updateTempo(combatConfig, stage)
	end
	local fighters, waitingAlive = humanCounts()
	local plan = run.plan
	if fighters == 0 and waitingAlive > 0 and plan ~= nil and flow ~= nil then
		-- Every fighter LEFT (nobody fell): those waiting in the lobby camp take over now rather
		-- than watching an unattended run until its cap.
		ArenaService.ReleaseWaiting(StageFlow.SafePoint(plan, flow))
		broadcast()
	end
	if stage ~= nil and zone ~= nil and flow ~= nil and flow.step == FIGHT then
		spawnBoss(zone)
		spawnBursts(stage, zone)
	end
	advance(combatConfig)
end

-- RequestAbandon (ruling 21). In a live run, from any member when the run has one human, else
-- from the leader: the run ends `abandoned` with what was banked. On the summary, from the
-- leader or a solo player: the wait ends and the party is in the lobby at once. Anything else
-- is dropped silently.
function WaveService.OnAbandon(player: Player): ()
	local member = ArenaService.GetMemberFor(player)
	if member == nil then
		return
	end
	local solo = #humanPlayers() <= 1
	if not solo and member.userId ~= ArenaService.LeaderUserId() then
		return
	end
	local plan = run.plan
	local flow = run.flow
	if run.phase == "summary" then
		backToLobby()
	elseif isLive(run.phase) and plan ~= nil and flow ~= nil then
		execute(StageFlow.Finish(plan, flow, "abandoned"))
	end
end

-- Every member gets the map (their own stars, the leader's open nodes): an arrival may have
-- changed who leads.
function WaveService.OnAdmitted(_player: Player): ()
	sendMapState(nil)
end

-- The map again, to one member: a client that booted late or rebuilt its UI asks for its
-- snapshot, and has no intent of its own for the map.
function WaveService.SendMap(player: Player): ()
	if boot.mission and ArenaService.IsAdmitted(player) then
		sendMapState(player)
	end
end

-- Ruling 22: RequestLeave is ignored from a fighting member of a live run (the client shows
-- Abandon there). Everyone else may go home: the lobby, the summary, a member who waits.
function WaveService.MayLeave(player: Player): boolean
	local member = ArenaService.GetMemberFor(player)
	if member == nil or not isLive(run.phase) then
		return true
	end
	return member.waiting
end

function WaveService.GetPhase(): Types.RunPhase
	return run.phase
end

-- P5 ruling 18, the one rule for a down: VitalsService reports it, and this asks StageFlow at
-- once what the tick asks it every frame (the fallen end the run unless the field is clear).
function WaveService.OnDown(_player: Player): ()
	local combatConfig = config()
	if combatConfig ~= nil then
		advance(combatConfig)
	end
end

-- Studio levers -------------------------------------------------------------------------------

-- The N and B keys (ruling 33, through DebugService): "stage" finishes this part of the level,
-- "boss" goes to the next wave with a boss. Nothing is banked and nothing skipped is credited.
function WaveService.Skip(which: string): ()
	local combatConfig = config()
	local plan = run.plan
	local flow = run.flow
	if combatConfig == nil or plan == nil or flow == nil or not isLive(run.phase) then
		return
	end
	local actions = StageFlow.Skip(plan, flow, which, os.clock(), combatConfig.levels)
	if #actions == 0 then
		return
	end
	execute(actions)
	syncPhase()
	if isLive(run.phase) then
		broadcast()
	end
end

-- The `wave` lever: forces a wave of the live camp (its fight or its breather), as P5's did
-- inside its one camp. Elsewhere it does nothing.
function WaveService.ForceWave(wave: number): ()
	local plan = run.plan
	local flow = run.flow
	if plan == nil or flow == nil or not isLive(run.phase) then
		return
	end
	local actions = StageFlow.Force(plan, flow, wave)
	if #actions == 0 then
		return
	end
	execute(actions)
	syncPhase()
	broadcast()
end

-- The `spawn` lever: one extra body of a crowd kind at the live camp's next spawn point, with
-- the run's scales. Only while a camp fights.
function WaveService.SpawnOne(kind: string): ()
	local _stage, zone = liveZone()
	local flow = run.flow
	if zone == nil or flow == nil or flow.step ~= FIGHT then
		return
	end
	if CrowdService.Spawn(kind, nextSpawnPoint(zone), FIGHT, centreOf(zone)) ~= 0 then
		run.spawnedThisGroup += 1
	end
end

-- The `killAll` lever: every living body dies with its normal rewards, credited to nobody.
function WaveService.KillAll(): ()
	CrowdService.KillAll(0)
end

-- The last human left (ArenaService's reset hook): the run and its level go; the stars stay,
-- they are keyed by userId. A reserved server can be reused by a later arrival.
function WaveService.Reset(): ()
	run = freshRun()
	boot.returning = false
	boot.lobbySince = 0
	CrowdService.Clear()
	VitalsService.ClearThreats()
	WeaponService.AbandonProjectiles()
	LevelService.Clear()
	VitalsService.SetMission(missionRules(1, 0))
	table.clear(boot.rescuedAt)
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
	-- A placement, a release or a rescue is not the player's own motion: without this the jump
	-- would read as speed, and buy their next claimed position the full slack.
	ArenaService.SetMovedHook(WeaponService.ForgetMotion)
	ArenaService.SetPlacer(placer)
	WeaponService.SetActGate(mayAct)
	ArenaService.SetResetHook(WaveService.Reset)
	-- From the first admit, so a lobby bar is already the gear's; a run sets its own scales.
	VitalsService.SetMission(missionRules(1, 0))
end

-- The boot hook: Main wires this one into the ordered Init/Start pass.
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
