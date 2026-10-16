--!strict
-- The run: a level's stages, its camps' waves, the rewards and the end (docs/INTERFACES.md
-- "L1 contracts" → "Flow" and "Server modules" → "B — the run"). One run per server, entirely on
-- the server clock.
--
-- L1 makes this one stage-driven machine for every level (ruling 1). The RULES of a run are not
-- here: which stage is next, when the boss room triggers, when a camp is clear, when a
-- checkpoint is reached, what ends the run, where a body belongs, what a skip does, which node is
-- open. They are StageFlow's, a pure module the harness loads and mutates (ruling 2), and the
-- split of a kill's reward is Combat's. This file only builds StageFlow's input once a tick and
-- EXECUTES the actions it returns: it closes and opens gates, queues waves, marks camps, moves
-- bodies.
--
-- Kept from P5, unchanged in meaning:
-- * The boss room's waves are crowd groups arriving in bursts at its spawn points.
-- * The pacing director only ever changes PACING (burst interval, merges, breather length, the
--   one extra elite), never enemy HP or damage.
-- * This is the only place under src/combat that writes a profile, and it writes nothing but
--   cash, materials, Valor, combat stats and (for a level that names a mission) its record.
-- * Nothing in the tick yields. The level's removal is deferred out of it.
--
-- From L1: every run ends in a summary and then the lobby camp, never the city (ruling 20); the
-- leader starts a level with RequestStartLevel (ruling 7); stars are session memory, kept here
-- per userId (ruling 25).
-- New with L1b ("L1b contracts — the living road"): the crowd has one floor per camp, set once at
-- the start; every camp's residents are placed at the start and live on their own; every kill is
-- paid the moment it falls, split by that body's own damage book (L1b-15), and the wallet goes
-- out at most once a second (L1b-16). Nothing is pooled, so nothing is ever dropped.
-- L1b Wave 2 ("the long road"): an open camp's tent sends its stock, CampBrain's rule, executed
-- here; a camp's clear pays a bonus (Combat.ClearBonus); the merge test leaves the residents out
-- (Combat.DeadFraction).
-- L1b Wave 4 ("no waits, no walls"): the open camps' floors share a chase region (the crowd's
-- floors carry its graph, RunState's its cells); a tent is a pace reserve, sending only while its
-- camp is ahead of its own clock and a resident lives; a camp clears when every raider it fielded
-- is dead, and its bonus is priced on what it fielded (StageFlow.Fielded); the boss room's close
-- makes every other camp forget the road (CrowdService.ForgetOthers); N stops at each open camp's
-- approach first.

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
local CampBrain = require(script.Parent:WaitForChild("CampBrain"))

-- Degrade value: without Combat.json the place never leaves the lobby, but the broadcast loop
-- still needs a legal period.
local DEFAULT_STATE_HZ = 4
local FIGHT = "fight"

-- One burst of one group: up to crowd.burst bodies of a kind, arriving together at one spawn
-- point in a grid. `placed` survives a hold (maxAlive, or a refused spawn), so the grid carries on.
type Burst = { kind: string, left: number, placed: number, at: Vector3? }
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
	-- Every camp's floor in floor-index order, set once at the start (L1b-1); {} in the lobby.
	floors: { Types.RunFloor },
	-- The plan's population (L1b-11): the client prewarms its pool with it.
	maxAlive: number,
	runEndsAt: number,
	-- os.clock() the summary ends and the party is back in the lobby; 0 = nothing pending.
	returnAt: number,
	tempo: number,
	killStamps: { number },
	-- The damage of the whole run (PartyMember.damageShare and RunSummary.damageShare read it).
	runDamage: { [number]: number },
	runDamageTotal: number,
	-- L1b-15: each member's fractions not paid yet; L1b-16: whose wallet a credit changed, and
	-- when each was last sent (os.clock()).
	carry: Combat.Carry,
	walletDirty: { [number]: boolean },
	walletSentAt: { [number]: number },
	-- A resident was refused at the start: warned once per run.
	warnedResident: boolean,
	-- Who the live camp's close has brought to its entry, by userId: once each (the close is
	-- judged again for levels.closeGraceSeconds, and a body just moved still reads as outside).
	entered: { [number]: boolean },
	-- The resident groups in rise or fight, by group index (DrainGroupEvents): a tent's rouse is
	-- owed until its group is among them (StageFlow.TentOwesRouse).
	awakeGroups: { [number]: boolean },
	-- The groups StageFlow.Threatening names (rise, fight or home), by group index: their members'
	-- crowd ids at the change, and every tent body sent into them since. SafePoint keeps out of
	-- their reach (R10).
	threatGroups: { [number]: { number } },
	-- L1b-W2-7: one per Plan.tents entry, in its order: its crowd group, the bodies it has sent
	-- (a refused spawn counts, so the next body is the next in its stock), the stock indexes the
	-- crowd refused (never fielded, so never priced: R12) and CampBrain's clock; `owed` = its group
	-- still owes the rouse of a body sent while the camp fought (StageFlow.TentOwesRouse, B-3).
	tents: {
		{
			group: number,
			sent: number,
			refused: { [number]: boolean },
			state: CampBrain.TentState,
			owed: boolean,
		}
	},
	-- A tent's refused spawn: warned once per run.
	warnedTent: boolean,
	-- L1b-W2-21: what the live locking camp's waves queued in this run, by kind (the director's
	-- elites included, the boss and its calls not), for its clear bonus. Emptied at its close.
	waveStock: { [string]: number },
}

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
		floors = {},
		maxAlive = 0,
		runEndsAt = 0,
		returnAt = 0,
		tempo = 1,
		killStamps = {},
		runDamage = {},
		runDamageTotal = 0,
		carry = {},
		walletDirty = {},
		walletSentAt = {},
		warnedResident = false,
		entered = {},
		awakeGroups = {},
		threatGroups = {},
		tents = {},
		warnedTent = false,
		waveStock = {},
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
	-- The lobby camp's kill height, read once (its layout is a file).
	lobbyKillY = nil :: number?,
	-- The living bodies on each floor, refilled by every advance (no table per tick).
	aliveByFloor = {} :: { number },
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
	-- The live boss room's own floor: the residents of the open camps are not its bodies.
	local _liveStage, live = liveZone()
	local alive = if live ~= nil then CrowdService.AliveOn(live.floor) else 0
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
		floors = run.floors,
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

-- The humans in the fight, by userId: admitted and not waiting in the lobby camp. StageFlow notes
-- them at every clear, before the boundary lets the waiting in (the star is theirs).
local function fightingIds(): { number }
	local ids: { number } = {}
	for _, member in ArenaService.GetMembers() do
		if not member.bot and member.player ~= nil and not member.waiting then
			table.insert(ids, member.userId)
		end
	end
	return ids
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
	local tookElite = boss == nil and elite ~= nil and run.tempo >= combatConfig.director.eliteTempo
	if tookElite and elite ~= nil then
		add(elite, 1)
	end
	Combat.WaveStock(run.waveStock, spec, if tookElite then elite else nil)
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

-- Mentor bonus at the boss's kill (docs/INTERFACES.md "C2 contracts", L1b-15): each human is
-- paid Combat.MentorBonus against the rates of the OTHER members present whose raw share of the
-- boss's damage book reached coop.mentorMinDamageShare, so an idle alt parked in the party earns
-- its main nothing. Bots report debug.botIncomeRate and are never mentors.
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
		run.walletDirty[mentor.userId] = true
		RunFx.Push({
			kind = "mentor",
			userId = mentor.userId,
			valor = bonus,
			-- MentorBonus pays mentorValor per carried member, so this recovers the head count.
			mentees = if coop.mentorValor > 0 then math.round(bonus / coop.mentorValor) else 0,
		})
	end
end

-- The humans in the fight, each at 0 damage: ContributionShares splits a reward evenly over it.
local function evenTally(): { [number]: number }
	local tally: { [number]: number } = {}
	for _, userId in fightingIds() do
		tally[userId] = 0
	end
	return tally
end

-- L1b-15: one reward (a kill's, or a camp clear's bonus) split over `tally` with the floor share
-- (Combat.ContributionShares) and paid in whole units with each member's carry
-- (Combat.SplitCarry, each member's CombatCashMult inside it), written into the profile and both
-- summaries; each wallet it changed is marked dirty (L1b-16). `killer` (0 = none) is credited
-- the kill. Never yields: it runs inside the strike that killed the body.
local function credit(pool: Combat.RewardPool, tally: { [number]: number }, killer: number): ()
	local level = run.level
	local combatConfig = config()
	if level == nil or combatConfig == nil then
		return
	end
	local gameConfig = Catalog.GetGameConfig()
	local shopConfig = Catalog.GetLegacyShopConfig()
	local states: { [number]: Types.PlayerState } = {}
	local mults: { [number]: number } = {}
	for userId in tally do
		local member = ArenaService.GetMember(userId)
		local player = if member ~= nil and not member.bot then member.player else nil
		local state = if player ~= nil then DataService.GetState(player) else nil
		if state ~= nil then
			states[userId] = state
			mults[userId] = Combat.CombatCashMult(state, gameConfig, shopConfig)
		end
	end
	local shares = Combat.ContributionShares(tally, combatConfig.coop.contributionFloor)
	local split = Combat.SplitCarry(pool, shares, run.carry, mults)
	local material = level.material
	local killCounted = false
	for userId, share in split do
		local state = states[userId]
		if state == nil then
			continue
		end
		state.cash += share.cash
		state.combat.valor += share.valor
		if share.materials > 0 and material ~= "" then
			local owned = state.combat.materials[material] or 0
			state.combat.materials[material] = owned + share.materials
		end
		state.combat.stats.cashFromCombat += share.cash
		local kills = if userId == killer then 1 else 0
		killCounted = killCounted or kills > 0
		ArenaService.CreditSummary(
			userId,
			share.cash,
			material,
			share.materials,
			share.valor,
			kills
		)
		run.walletDirty[userId] = true
	end
	if killer == 0 then
		return
	end
	local member = ArenaService.GetMember(killer)
	local player = if member ~= nil and not member.bot then member.player else nil
	local state = if player ~= nil then DataService.GetState(player) else nil
	if state ~= nil then
		state.combat.stats.kills += 1
		if not killCounted then
			-- The killing blow's owner took no share (a profile that loaded late): the card still
			-- counts the kill.
			ArenaService.CreditSummary(killer, 0, material, 0, 0, 1)
		end
	end
end

-- The waves a clear covers, in every fighting human's stats and (for a level that names a
-- mission, ruling 26: the arena writes `village`) their mission record's best wave.
local function countWaves(wave: number, count: number): ()
	local missionId = if run.level ~= nil then run.level.mission else nil
	for _, userId in fightingIds() do
		local member = ArenaService.GetMember(userId)
		local player = if member ~= nil then member.player else nil
		local state = if player ~= nil then DataService.GetState(player) else nil
		if state == nil then
			continue
		end
		state.combat.stats.wavesCleared += count
		if missionId ~= nil then
			local record = missionRecord(state, missionId)
			record.bestWave = math.max(record.bestWave, wave)
		end
	end
end

-- L1b-17: a camp is cleared (an open one when the last raider it fielded falls, wherever it stands,
-- L1b-W4-29; the boss room when its last wave does): the banner, its checkpoint marked done, one
-- more wave cleared in every fighting human's stats, and its clear bonus, crowd.clearBonus.share
-- of what `stock` pays at the difficulty's price (L1b-W4-30: what the camp fielded; the boss room:
-- its residents and its waves), split evenly among them and kept at once. A
-- camp a Studio skip passed (`skipped`) gets the banner and the mark only: a skip pays nothing
-- (L1b-22).
local function campCleared(zone: StageFlow.Zone, skipped: boolean, stock: { [string]: number }): ()
	LevelService.SetCamp(zone.id, "cleared")
	RunFx.Push({ kind = "camp", event = "cleared", name = zone.name })
	if skipped then
		return
	end
	countWaves(0, 1)
	local level = run.level
	local scales = run.scales
	local bonus = if level ~= nil then level.crowd.clearBonus else nil
	if level == nil or bonus == nil or scales == nil then
		return
	end
	local cash, materials =
		Combat.ClearBonus(stock, level.crowd.rewards, scales.rewardMult, bonus.share)
	if cash > 0 or materials > 0 then
		credit({ cash = cash, materials = materials, valor = 0, kills = 0 }, evenTally(), 0)
	end
end

-- The boss fell: every human's mission record counts the clear (a level that names a mission).
local function recordBossClear(): ()
	local missionId = if run.level ~= nil then run.level.mission else nil
	if missionId == nil then
		return
	end
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		local state = if not member.bot and player ~= nil then DataService.GetState(player) else nil
		if state ~= nil then
			missionRecord(state, missionId).bossClears += 1
		end
	end
end

-- L1b-6 to L1b-22's executor: a group that wakes (rest to rise, a close's release included)
-- puts a "!" over each of its living bodies on every member's screen (L1b-21).
local function onGroupEvent(event: CrowdService.GroupEvent): ()
	if event.to == "rise" or event.to == "fight" then
		run.awakeGroups[event.group] = true
	else
		run.awakeGroups[event.group] = nil
	end
	if StageFlow.Threatening(event.to) then
		run.threatGroups[event.group] = table.clone(event.ids)
	else
		run.threatGroups[event.group] = nil
	end
	local plan = run.plan
	if plan == nil or not isLive(run.phase) then
		return
	end
	if event.from == "rest" and event.to == "rise" then
		local zone = plan.zones[event.floor]
		RunFx.Push({
			kind = "camp",
			event = "alert",
			name = if zone ~= nil then zone.name else "",
			ids = table.clone(event.ids),
		})
	end
end

-- The crowd and everything it had in the air go, and the players' shots with them. No body is
-- credited (CrowdService.Clear fires no kill).
local function clearField(): ()
	run.queue = {}
	run.bossPending = nil
	run.bossId = 0
	run.laterBodies = 0
	CrowdService.Clear()
	VitalsService.ClearThreats()
	WeaponService.AbandonProjectiles()
end

-- L1b-15: a kill is paid the moment it falls, in every live phase, its kind's fixed reward x the
-- difficulty's rewardMult (and the boss's Valor), split by that body's own damage book kept to
-- the humans of the session (nobody's damage, a Studio lever's kill: an even split among the
-- fighting humans). The boss pays the Mentor bonus first, from its own book. Runs inside the
-- strike that killed it (CrowdService's callbacks are synchronous threads): it must not yield.
local function onCrowdKilled(id: number, byUserId: number, info: CrowdService.CrowdKillInfo): ()
	local level = run.level
	local scales = run.scales
	local combatConfig = config()
	if level == nil or scales == nil or combatConfig == nil or not isLive(run.phase) then
		return
	end
	local tally: { [number]: number } = {}
	for userId, damage in info.damageBy do
		run.runDamage[userId] = (run.runDamage[userId] or 0) + damage
		run.runDamageTotal += damage
		local member = ArenaService.GetMember(userId)
		if member ~= nil and not member.bot and member.player ~= nil then
			tally[userId] = damage
		end
	end
	if next(tally) == nil then
		tally = evenTally()
	end
	table.insert(run.killStamps, os.clock())
	local cash, materials = Combat.KillReward(level.crowd.rewards, info.kind, scales.rewardMult)
	local valor = 0
	if info.boss and id == run.bossId then
		run.bossId = 0
		valor = run.bossValor
		payMentors(combatConfig, tally)
		RunFx.Push({ kind = "bossDown", name = run.bossName or info.kind, valor = run.bossValor })
		recordBossClear()
	end
	credit({ cash = cash, materials = materials, valor = valor, kills = 1 }, tally, byUserId)
end

-- L1b-16: each wallet a credit changed goes out at most once every levels.walletSendSeconds
-- (the wallet is the whole PlayerState, and a fight kills several bodies a second); `all` sends
-- every dirty one now (the run's end).
local function sendWallets(now: number, all: boolean): ()
	local combatConfig = config()
	local every = if combatConfig ~= nil then combatConfig.levels.walletSendSeconds else 0
	for userId in run.walletDirty do
		local sentAt = run.walletSentAt[userId]
		if not all and sentAt ~= nil and now - sentAt < every then
			continue
		end
		run.walletDirty[userId] = nil
		run.walletSentAt[userId] = now
		local member = ArenaService.GetMember(userId)
		local player = if member ~= nil then member.player else nil
		if player ~= nil then
			-- The wallet strip is fed by Snapshots in this place (EconomyService is hub-only).
			ArenaService.SendSnapshot(player)
		end
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
	local id = CrowdService.Spawn(boss.kind, at, FIGHT, centreOf(zone), run.bossHpMult, zone.floor)
	if id ~= 0 then
		run.bossPending = nil
		run.bossId = id
	end
end

-- P5 ruling 15: the next burst, when its time has come and the field has room. A burst held by
-- maxAlive (or a refused spawn) stays at the head of the queue and carries on as room frees.
-- L1b-14: the room is the boss room's own floor, its residents included.
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
	while burst.left > 0 and CrowdService.AliveOn(zone.floor) < stage.maxAlive do
		local position = StageFlow.BurstPoint(zone, at, size, burst.placed, crowd.burstSpacing)
		if CrowdService.Spawn(burst.kind, position, FIGHT, centre, nil, zone.floor) == 0 then
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

-- Every living member of a resident group in rise, fight or home (StageFlow.Threatening), where it
-- stands, with its kind's longest reach: SafePoint keeps a body out of them (the fix round's ruling
-- on the data slice's Minor 1; L1b Wave 4's R10 adds home, which turns back on sight). Asked only
-- when a body is put into the level, so CrowdService.Get's table is fine.
local function threats(): { CampBrain.Shooter }
	local list: { CampBrain.Shooter } = {}
	local kinds = Tuning.Get().crowd.kinds
	for _, ids in run.threatGroups do
		for _, id in ids do
			local view = CrowdService.Get(id)
			if view ~= nil and view.state ~= "dead" and view.hp > 0 then
				table.insert(
					list,
					{ at = view.position, reach = StageFlow.LongestReach(kinds[view.kind]) }
				)
			end
		end
	end
	return list
end

-- L1b-18: the run's safe point, from the crowd as it is now.
local function safePoint(plan: StageFlow.Plan, flow: StageFlow.State): Vector3
	return StageFlow.SafePoint(plan, flow, CrowdService.Busy(), threats())
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
	return safePoint(plan, flow), false
end

-- The lobby's kill height: its layout's. With no layout file LevelService stands the party on
-- LevelGeometry's bare pad, and the height is that stand-in's: a short fall, as a layout's is.
local function lobbyKillY(): number
	local known = boot.lobbyKillY
	if known ~= nil then
		return known
	end
	local map = Catalog.GetExpeditionsConfig()
	local layout = if map ~= nil then Catalog.GetLevelLayout(map.lobby.layout) else nil
	local killY = if layout ~= nil and layout.arena == nil
		then layout.killY
		else LevelGeometry.BareLobby().killY
	boot.lobbyKillY = killY
	return killY
end

-- Ruling 19: a human whose root is under the kill height or outside the box is put back on the
-- ground with the get-up i-frames, none while they are engaged in a resident fight (L1b-20).
-- Never a down, no cost, in every phase: falling out is the level's fault. Which box judges them, and whether they go to the run's safe point or to the
-- lobby camp, is StageFlow.Rescue's (once a run is over nobody is put into its level). A member
-- just rescued is left alone for the length of those i-frames: their client still reports the
-- old place for a frame or two, and a second rescue would only move them again. Without
-- Combat.json player.rescue nobody is rescued.
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
	local lobby = LevelService.LobbyBounds()
	local lobbyFloor = lobbyKillY()
	-- Asked only when somebody is put back into the level (it builds new tables).
	local safe: Vector3? = nil
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
		local verdict = StageFlow.Rescue(
			plan,
			flow,
			member.waiting,
			root.Position,
			rescue,
			rules.boxMargin,
			lobby,
			lobbyFloor
		)
		local target: Vector3? = nil
		if verdict == "lobby" then
			target = LevelService.LobbyPoint()
		elseif verdict == "level" and plan ~= nil and flow ~= nil then
			safe = safe or safePoint(plan, flow)
			target = safe
		end
		if target ~= nil and ArenaService.MoveMember(member, target) then
			boot.rescuedAt[member.userId] = now
			local grace = StageFlow.RescueGrace(CrowdService.Engaged(member.userId), iframes)
			if grace > 0 then
				WeaponService.GrantIframes(player, grace)
			end
		end
	end
end

-- Every fighting member's body goes to `feet` (a skip's `move`). With `closing`, the camp whose
-- gates are closing, only those StageFlow says must be brought inside, and each of them once per
-- close: at the close itself by MustEnter, in its grace (`late`) by Strayed.
local function moveFighters(feet: Vector3, closing: StageFlow.Zone?, late: boolean?): ()
	for _, member in ArenaService.GetMembers() do
		if member.bot or not ArenaService.IsFighting(member) then
			continue
		end
		if closing ~= nil then
			local root = rootOf(member)
			local outside = root ~= nil
				and (
					if late
						then StageFlow.Strayed(closing, root.Position)
						else StageFlow.MustEnter(closing, root.Position)
				)
			if run.entered[member.userId] or not outside then
				continue
			end
		end
		if ArenaService.MoveMember(member, feet) and closing ~= nil then
			run.entered[member.userId] = true
		end
	end
end

-- StageFlow.StandsUp said so (the road's field is clear): every fighting member who is down
-- stands up at the safe point. Not where they fell: that is beside the group that downed them,
-- which would see them at once and wake again. Whether anybody stood up.
local function standUpOnRoad(plan: StageFlow.Plan, flow: StageFlow.State): boolean
	local feet: Vector3? = nil
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if member.bot or player == nil or not ArenaService.IsFighting(member) then
			continue
		end
		if VitalsService.IsDown(player) then
			VitalsService.StandUp(player)
			local at = feet or safePoint(plan, flow)
			feet = at
			ArenaService.MoveMember(member, at)
		end
	end
	return feet ~= nil
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

-- Ruling 20: every run ends in a summary. Nothing is dropped and nothing more is paid (L1b-15:
-- every kill was paid as it fell; the carry, under 1 of each, goes with the run); every wallet a
-- credit changed is sent now (L1b-16); the field is cleared; a lost run marks its fallen; a
-- cleared one gives the star of its difficulty to every human StageFlow says earned it (those
-- fighting before the last boundary). The level stays built while the card is up.
function WaveService.EndRun(asked: string): ()
	local plan = run.plan
	local flow = run.flow
	local level = run.level
	if plan == nil or flow == nil or level == nil or not isLive(run.phase) then
		return
	end
	-- For a caller that did not come through StageFlow's own `end`. The reason on the card is
	-- the one StageFlow ended the run for.
	StageFlow.Finish(plan, flow, asked)
	local reason = flow.ended or asked
	sendWallets(os.clock(), true)
	if reason == "down" or reason == "wipe" then
		local _lost, fallen = fallenReason()
		for _, userId in fallen do
			ArenaService.MarkDied(userId)
		end
	end
	clearField()
	run.spec = nil

	local results: { [number]: Types.RunResult } = {}
	for _, member in ArenaService.GetMembers() do
		if member.bot or member.player == nil then
			continue
		end
		local star = StageFlow.EarnsStar(flow, member.userId)
			and StageFlow.Award(starsOf(member.userId), plan.levelId, plan.difficulty)
		results[member.userId] = {
			levelId = level.id,
			levelName = level.name,
			difficulty = plan.difficulty,
			reason = reason,
			campsCleared = flow.cleared,
			camps = plan.camps,
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

-- Ruling 20: after the summary, the lobby. Everyone is healed (the downed stand up, the hurt
-- are whole again) and whoever is still in the level is moved to the lobby camp; the level is
-- removed, and the phase is `lobby`. Nobody is sent to the city. Deferred out of the tick (it
-- destroys the level's Instances), or called at once from RequestAbandon.
local function backToLobby(): ()
	boot.returning = false
	if run.phase ~= "summary" then
		return
	end
	local combatConfig = config()
	local lobby = LevelService.LobbyBounds()
	local margin = if combatConfig ~= nil then combatConfig.levels.boxMargin else 0
	local lobbyFloor = lobbyKillY()
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if member.bot or player == nil then
			continue
		end
		member.waiting = false
		VitalsService.StandUp(player)
		-- A body already in the lobby camp (a respawn during the summary) stays where it stands.
		local root = rootOf(member)
		if root == nil or StageFlow.OutOfBox(lobby, lobbyFloor, root.Position, margin) then
			ArenaService.MoveMember(member, LevelService.LobbyPoint())
		end
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

-- The contract's table "What WaveService does for each action" (L1b "Flow"), in the order
-- StageFlow gave. `reach` and `campClear` name their camp by zone index; the others by stage.
local function execute(actions: { StageFlow.Action }): ()
	local plan = run.plan
	local flow = run.flow
	if plan == nil or flow == nil or #actions == 0 then
		return
	end
	for _, action in actions do
		local stage = plan.stages[action.stage]
		local zone = if stage ~= nil then stage.zone else nil
		local kind = action.kind
		-- `gate` sets nothing on the crowd (L1b-14: the floors were set at the start), and `rearm`
		-- and `breather` and `travel` change nothing here: StageFlow's state carries the time,
		-- and the broadcast after the batch carries the news.
		if kind == "close" then
			if stage ~= nil and zone ~= nil then
				-- Both in this frame, the move first: the wall that turns solid is 8 studs deep
				-- from the floor's edge outward and runs across the gate gaps, so whoever stands
				-- off the floor or against its edge (in a gap, on the road) would be inside a
				-- solid Part. The tick asks again for levels.closeGraceSeconds.
				run.entered = {}
				-- L1b-W2-21: this camp's waves begin; its clear bonus counts what they queue.
				run.waveStock = {}
				moveFighters(zone.entry, zone)
				LevelService.SetCamp(zone.id, "closed")
				run.tempo = 1
				run.killStamps = {}
				run.campClosedAt = os.clock()
				RunFx.Push({ kind = "camp", event = "closed", name = stage.name })
				-- L1b-13: the boss room's residents, held until now, wake with its first wave.
				CrowdService.WakeFloor(zone.floor)
				-- L1b-W4-26: and every other camp's groups forget the road and walk home.
				CrowdService.ForgetOthers(zone.floor)
			end
		elseif kind == "wave" then
			queueWave(action.stage, action.wave or 1, action.merged == true)
		elseif kind == "clear" then
			-- What the dead still had in the air (a lob, a slinger's shot) goes with them:
			-- nothing lands on an empty field.
			VitalsService.ClearThreats()
			ArenaService.MarkWaveCleared(action.wave or 0, action.count or 0)
			countWaves(action.wave or 0, action.count or 0)
		elseif kind == "boundary" then
			standUpDowned()
			-- Not when the same batch ends the run: nobody is brought into a level about to go.
			if action.release == true then
				ArenaService.ReleaseWaiting(safePoint(plan, flow))
			end
		elseif kind == "open" then
			if zone ~= nil then
				-- The boss room's whole stock: its residents and every body its waves queued.
				local stock = table.clone(zone.stock)
				for queuedKind, count in run.waveStock do
					stock[queuedKind] = (stock[queuedKind] or 0) + count
				end
				campCleared(zone, action.skipped == true, stock)
			end
			run.spec = nil
		elseif kind == "campClear" then
			local cleared = plan.zones[action.zone or 0]
			if cleared ~= nil then
				-- L1b-W4-30: priced on what it fielded, its residents and what its tent sent
				-- and the crowd took (R12).
				local tent: StageFlow.PlanTent? = nil
				local sent = 0
				local refused: { [number]: boolean }? = nil
				for index, planned in plan.tents do
					if planned.zone == cleared.floor then
						local record = run.tents[index]
						tent = planned
						sent = if record ~= nil then record.sent else 0
						refused = if record ~= nil then record.refused else nil
						break
					end
				end
				campCleared(cleared, false, StageFlow.Fielded(cleared, tent, sent, refused))
			end
		elseif kind == "reach" then
			local reached = plan.zones[action.zone or 0]
			if reached ~= nil then
				LevelService.SetCamp(reached.id, "reached")
				RunFx.Push({ kind = "camp", event = "checkpoint", name = reached.name })
			end
		elseif kind == "drop" then
			-- L1b-22: a skip pays nothing. Only the live boss room's floor goes (its queue, its
			-- bodies, its residents), without a kill; the open camps behind keep theirs.
			run.queue = {}
			run.bossPending = nil
			run.bossId = 0
			run.laterBodies = 0
			if zone ~= nil then
				CrowdService.ClearFloor(zone.floor)
			end
			VitalsService.ClearThreats()
		elseif kind == "move" then
			if zone ~= nil then
				moveFighters(zone.entry, nil)
			end
		elseif kind == "approach" then
			-- L1b-W4-31: N's stop before an open camp; nothing else happens.
			local before = plan.zones[action.zone or 0]
			local feet = if before ~= nil then before.approach else nil
			if feet ~= nil then
				moveFighters(feet, nil)
			end
		elseif kind == "end" then
			WaveService.EndRun(action.reason or "cleared")
			return
		end
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
	local standing: { boolean } = {}
	-- L1b-14 and L1b-19: the live boss room counts its own floor only; the road asks the groups.
	local _stage, live = liveZone()
	local alive = if live ~= nil then CrowdService.AliveOn(live.floor) else 0
	local byFloor = boot.aliveByFloor
	table.clear(byFloor)
	for index = 1, #plan.zones do
		byFloor[index] = CrowdService.AliveOn(index)
	end
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if not member.bot and player ~= nil and ArenaService.IsFighting(member) then
			local root = rootOf(member)
			if root ~= nil then
				table.insert(roots, root.Position)
				table.insert(standing, not VitalsService.IsDown(player))
			end
		end
	end
	local spawningDone = #run.queue == 0 and run.bossPending == nil
	-- L1b-W2-26: the residents (and tent bodies) of the boss room are not the waves' bodies.
	local queuedAlive = if live ~= nil then alive - CrowdService.GroupedOn(live.floor) else 0
	local deadFraction = Combat.DeadFraction(run.spawnedThisGroup, queuedAlive)
	local fallen = fallenReason()
	local before = run.phase
	local input: StageFlow.Input = {
		now = now,
		roots = roots,
		standing = standing,
		fighters = fightingIds(),
		spawningDone = spawningDone,
		alive = alive,
		awake = CrowdService.Awake(),
		aliveByFloor = byFloor,
		mergeOk = Combat.ShouldMerge(run.tempo, deadFraction, combatConfig.director),
		breatherSeconds = Combat.BreatherSeconds(run.tempo, combatConfig.director),
		fallen = fallen,
		runCap = run.runEndsAt > 0 and now >= run.runEndsAt,
	}
	local actions = StageFlow.Advance(plan, flow, input, combatConfig.levels)
	execute(actions)
	-- Open camps have no boundary: a member down on a road whose field is clear stands up now.
	local stood = run.flow == flow
		and isLive(run.phase)
		and StageFlow.StandsUp(plan, flow, input)
		and standUpOnRoad(plan, flow)
	syncPhase()
	-- RunState goes out at once on every action, on a stand-up, and on a phase change no action
	-- announced (a boss placed, a boss killed).
	if isLive(run.phase) and (#actions > 0 or stood or run.phase ~= before) then
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

-- The level file, its layout and its difficulty, resolved and validated; every problem is
-- warned. The Raider Arena comes through the two adapters (ruling 27). May throw: these are
-- files somebody typed, and resolveLevel is the net.
local function readLevel(
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
	-- The arena's one difficulty is the map's first, which is the one the map screen offers.
	local level =
		StageFlow.Resolve(file, mission, combatConfig.director.runCapSeconds, map.difficulties[1])
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
	local crowd = Tuning.Get().crowd
	local problems = StageFlow.Validate(
		level,
		layout,
		crowd.kinds,
		difficultyRanks(map),
		combatConfig.levels,
		crowd.maxAlive
	)
	-- How the residents rest, wake and go home is the same for every level (Combat.json camps).
	for _, problem in CampBrain.Problems(combatConfig.camps) do
		table.insert(problems, `Combat.json camps: {problem}`)
	end
	for _, problem in problems do
		warn(`[WaveService] {problem}`)
	end
	if #problems > 0 or level.difficulties[difficulty] == nil then
		return nil, nil
	end
	return level, layout
end

-- readLevel behind a pcall. nil = `unavailable`. Validate answers for a key that is missing; a
-- file that still makes a rule throw is one more warned problem, and the leader's Depart is
-- answered either way.
local function resolveLevel(
	levelId: string,
	difficulty: string,
	combatConfig: Types.CombatConfig,
	map: Types.ExpeditionsConfig
): (Types.LevelConfig?, Types.LevelLayout?)
	local read, level, layout = pcall(readLevel, levelId, difficulty, combatConfig, map)
	if not read then
		warn(`[WaveService] level {levelId}: its files could not be read ({tostring(level)})`)
		return nil, nil
	end
	return level, layout
end

-- L1b "Flow" → "Start" step 5: every resident group of the plan joins the crowd in its order,
-- and its members are placed on the posts CampBrain gives it, kinds in the order of its units.
-- A refused spawn is warned once per run and not retried: the population gate makes it a bug.
local function placeResidents(plan: StageFlow.Plan): ()
	for index, def in plan.groups do
		local group = CrowdService.AddGroup(def)
		if group ~= index then
			warn(`[WaveService] the crowd took group {def.id} as {group}, not {index}`)
		end
		if group == 0 then
			continue
		end
		local members = 0
		for _, unit in def.units do
			members += unit.count
		end
		local posts = CampBrain.Posts(def, members)
		local placed = 0
		for _, unit in def.units do
			for _ = 1, unit.count do
				placed += 1
				local post = posts[placed]
				local id = if post ~= nil
					then CrowdService.SpawnResident(unit.kind, group, post)
					else 0
				if id == 0 and not run.warnedResident then
					run.warnedResident = true
					warn(
						`[WaveService] a {unit.kind} of {def.id} was not placed (more refusals stay quiet)`
					)
				end
			end
		end
	end
end

-- L1b-W2 "Flow" → "Start": every tent of the plan joins the crowd after the resident groups, as
-- one group of its camp, with nobody placed: its stock comes out in the run (tickTents). A group
-- the crowd refused leaves its tent with nothing to send, so its camp can still clear.
local function placeTents(plan: StageFlow.Plan): ()
	for index, tent in plan.tents do
		local group = CrowdService.AddGroup(tent.def)
		local wanted = #plan.groups + index
		if group ~= wanted then
			warn(`[WaveService] the crowd took group {tent.def.id} as {group}, not {wanted}`)
		end
		local stock = if group ~= 0 then #tent.kinds else 0
		table.insert(run.tents, {
			group = group,
			sent = 0,
			refused = {},
			state = CampBrain.NewTent(stock),
			owed = false,
		})
	end
end

-- L1b-W2-7's executor, before advance, with L1b-W4-28's pace: each tent's camp clock runs while
-- the camp is up (a group of its floor in rise or fight), and the tent is active only while the
-- camp is up, one of its residents lives and it is ahead of its clock (the killed share of its
-- residents less busy time over pace.seconds, at least pace.lead). An active tent sends its next
-- body when CampBrain says it is due, rising at its door (B-4) and walking to its own ring post,
-- and rouses its group so the body joins the fight. One body per tent per tick. A refused spawn
-- warns once per run and counts as sent, so the tent moves on, but is booked as refused and never
-- priced in the clear bonus (R12): the population rule makes it a bug. Never yields.
-- The fix round: a body that joins a group already up is a threat for the safe point at once
-- (B-1: its group's state does not change, so no event lists it), and a body sent while its camp
-- fights keeps its group roused until the group is up (B-3). Every rouse a tent asks for acts only
-- while a player is known and reachable for its group (CampBrain.TentRouse): a tent never wakes a
-- group to fight nobody.
local function tickTents(): ()
	local plan = run.plan
	if plan == nil or #run.tents == 0 then
		return
	end
	local busy = CrowdService.Busy()
	local now = os.clock()
	for index, tent in run.tents do
		local planned = plan.tents[index]
		if planned == nil or tent.group == 0 then
			continue
		end
		local floor = planned.zone
		local campBusy = busy[floor] == true
		tent.owed =
			StageFlow.TentOwesRouse(tent.owed, campBusy, run.awakeGroups[tent.group] == true)
		if tent.owed then
			CrowdService.RouseGroup(tent.group)
		end
		CampBrain.TentClock(tent.state, campBusy, now)
		local residentsAlive = CrowdService.AliveOn(floor) - CrowdService.GroupAlive(tent.group)
		local zone = plan.zones[floor]
		local residents = if zone ~= nil then zone.residents else 0
		local ahead = CampBrain.Ahead(
			residents - residentsAlive,
			residents,
			tent.state.busySeconds,
			planned.pace
		)
		local active = CampBrain.TentActive(campBusy, residentsAlive, ahead)
		if not CampBrain.TentDue(tent.state, active, now) then
			continue
		end
		local following = tent.sent + 1
		local kind = planned.kinds[following]
		local post = planned.posts[following]
		local id = if kind ~= nil and post ~= nil
			then CrowdService.SpawnResident(kind, tent.group, post, planned.doors[following])
			else 0
		if id ~= 0 then
			CrowdService.RouseGroup(tent.group)
			local listed = run.threatGroups[tent.group]
			if listed ~= nil then
				table.insert(listed, id)
			end
			tent.owed = StageFlow.TentOwesRouse(true, campBusy, run.awakeGroups[tent.group] == true)
		else
			-- Sent, so the tent moves on to its next body, but never fielded, so never priced.
			tent.refused[following] = true
			if not run.warnedTent then
				run.warnedTent = true
				warn(
					`[WaveService] a body of {planned.def.id} was not placed; skipped and not priced (more refusals stay quiet)`
				)
			end
		end
		CampBrain.TentSent(tent.state, now, planned.every)
		tent.sent = following
	end
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
	local ranks = difficultyRanks(map)
	local planned, plan, problem = pcall(function(): (StageFlow.Plan?, string?)
		-- The box as it is built: the floors as deep as LevelService makes them.
		local bounds = LevelGeometry.Bounds(layout, rules.floorThickness)
		return StageFlow.Plan(
			level,
			layout,
			difficulty,
			rules,
			bounds,
			ranks,
			Tuning.Get().crowd.kinds
		)
	end)
	if not planned then
		warn(`[WaveService] level {levelId}: no plan could be made of it ({tostring(plan)})`)
		return "unavailable"
	end
	if plan == nil and problem ~= nil then
		warn(`[WaveService] {problem}`)
	end
	if scales == nil or plan == nil then
		return "unavailable"
	end
	-- A start that threw after an earlier Build (between it and the run's own fields) left that
	-- level standing in the lobby, and Build refuses a second one: what is not played goes first.
	LevelService.Clear()
	if not LevelService.Build(layout, map, rules) then
		return "unavailable"
	end
	-- L1b "Flow" → "Start": the field is cleared, then one crowd floor per camp is set, once for
	-- the whole run (L1b-1), with nobody alive.
	clearField()
	local floors: { Types.CrowdFloor } = {}
	local runFloors: { Types.RunFloor } = {}
	for _, zone in plan.zones do
		local rect = zone.rect
		-- L1b-W4-14, -33: a region floor carries its graph to the crowd and its cells to the client.
		local region = zone.region
		table.insert(floors, {
			centre = Vector3.new(rect.x, zone.floorY, rect.z),
			half = Vector3.new(rect.hx, rules.crowdCeiling, rect.hz),
			region = region,
		})
		table.insert(runFloors, {
			x = rect.x,
			y = zone.floorY,
			z = rect.z,
			hx = rect.hx,
			hz = rect.hz,
			cells = if region ~= nil then region.cells else nil,
		})
	end
	if not CrowdService.SetFloors(floors) then
		warn(`[WaveService] level {levelId}: the crowd took no floors; it cannot be played`)
		LevelService.Clear()
		return "unavailable"
	end
	CrowdService.SetCampRules(combatConfig.camps)
	local flow = StageFlow.Begin(plan)

	run = freshRun()
	run.level = level
	run.plan = plan
	run.flow = flow
	run.scales = scales
	run.rank = ranks[difficulty] or 0
	run.floors = runFloors
	run.maxAlive = plan.population
	ArenaService.SetLevel({
		id = level.id,
		name = level.name,
		difficulty = difficulty,
		material = level.material,
		mission = level.mission,
	})
	ArenaService.ResetSummaries()
	-- Before any spawn, so the residents take the difficulty's HP and plate.
	CrowdService.SetScales({ hp = scales.hpScale, plate = scales.plateScale })
	VitalsService.SetMission(missionRules(scales.damageScale, level.crowd.regenShare))
	placeResidents(plan)
	placeTents(plan)
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
	-- Before advance (L1b "A run"): a group that woke since the last tick shows its "!".
	CrowdService.DrainGroupEvents(onGroupEvent)
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

	local flow = run.flow
	if flow ~= nil and flow.step == "over" then
		-- The net under `execute`: StageFlow has ended the run, and a step of that batch threw
		-- before the summary was up. Without this the run would stand in a live phase for good,
		-- since StageFlow answers nothing once a run is over.
		WaveService.EndRun(flow.ended or "abandoned")
		return
	end
	local stage, zone = liveZone()
	if stage ~= nil and flow ~= nil and StageFlow.Directs(flow) then
		-- Through the camp's fights and its breathers, as P5 ran it: before this tick's spawns
		-- and before StageFlow is asked, so its merge and its breather read this tick's tempo.
		updateTempo(combatConfig, stage)
	end
	local fighters, waitingAlive = humanCounts()
	local plan = run.plan
	if fighters == 0 and waitingAlive > 0 and plan ~= nil and flow ~= nil then
		-- Every fighter LEFT (nobody fell): those waiting in the lobby camp take over now rather
		-- than watching an unattended run until its cap.
		ArenaService.ReleaseWaiting(safePoint(plan, flow))
		broadcast()
	end
	if stage ~= nil and zone ~= nil and flow ~= nil and flow.step == FIGHT then
		spawnBoss(zone)
		spawnBursts(stage, zone)
	end
	if
		zone ~= nil
		and flow ~= nil
		and StageFlow.StillClosing(flow, os.clock(), combatConfig.levels)
	then
		-- The close judged the server's copy of each body, which trails the player's own screen.
		moveFighters(zone.entry, zone, true)
	end
	tickTents()
	advance(combatConfig)
	sendWallets(os.clock(), false)
end

-- RequestAbandon (ruling 21). In a live run, from any member when the run has one human, else
-- from the leader: the run ends `abandoned`, every kill already paid. On the summary, from the
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

-- P5 ruling 18, the one rule for a down: VitalsService reports it, and this asks StageFlow at
-- once what the tick asks it every frame (the fallen end the run unless the field is clear).
function WaveService.OnDown(_player: Player): ()
	local combatConfig = config()
	if combatConfig ~= nil then
		advance(combatConfig)
	end
end

-- Studio levers -------------------------------------------------------------------------------

-- The N and B keys (ruling 33, L1b-22, through DebugService): "stage" finishes this part of the
-- level, "boss" goes to the next wave with a boss. Nothing skipped is credited.
function WaveService.Skip(which: string): ()
	local combatConfig = config()
	local plan = run.plan
	local flow = run.flow
	if combatConfig == nil or plan == nil or flow == nil or not isLive(run.phase) then
		return
	end
	local actions =
		StageFlow.Skip(plan, flow, which, os.clock(), combatConfig.levels, fightingIds())
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

-- The `spawn` lever: one extra body of a crowd kind at the live camp's next spawn point, on its
-- floor, with the run's scales. Only while the boss room fights; elsewhere it says so.
function WaveService.SpawnOne(kind: string): ()
	local _stage, zone = liveZone()
	local flow = run.flow
	if zone == nil or flow == nil or flow.step ~= FIGHT then
		RunFx.Push({ kind = "notice", text = "No camp to spawn in" })
		return
	end
	if
		CrowdService.Spawn(kind, nextSpawnPoint(zone), FIGHT, centreOf(zone), nil, zone.floor) ~= 0
	then
		run.spawnedThisGroup += 1
	end
end

-- The `killAll` lever: every living body, on every floor, dies and is paid as any kill is
-- (L1b-15), credited to nobody: an even split unless somebody had hurt it.
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
	-- L1b-20's test (L1b-W4-27): reachable for a camp group that is rising or fighting.
	-- Never in the lobby or on the summary (CrowdService's last step may still say so).
	ArenaService.SetEngagedSource(function(userId: number): boolean
		return isLive(run.phase) and CrowdService.Engaged(userId)
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
