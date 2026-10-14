--!strict
-- The rules of a run through a level (docs/INTERFACES.md "L1 contracts", rulings 1, 2, 9, 10,
-- 13–19, 25, 27, 28 and "A run"). A level is an ordered list of stages, `travel` and `camp`. This
-- module decides everything that is a rule: which stage is next, when a camp triggers, when its
-- gates close, when it is clear, what a checkpoint banks, what ends the run, where a body that
-- must be moved goes, what a Studio skip does, which map node is open and who earns a star.
-- WaveService only executes the actions returned here.
--
-- Pure on purpose (the lesson of the P5 reviews: the run's rules were "checked by reading only"):
-- tables, numbers and Vector3 values; no service, no Instance, no clock of its own (every time is
-- an argument) and no yield, so tools/crowd_harness loads it as it stands and mutate.py mutates
-- it. Of Vector3 it uses only what the harness shim has: new, X/Y/Z, + - * /, Magnitude, Unit.
-- The Types require is for annotations alone.
--
-- State is mutated in place by Advance, Finish and Skip; the caller keeps one per run (Begin).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local LevelGeometry = require(script.Parent:WaitForChild("LevelGeometry"))

-- A floor rectangle: centre and half extents.
export type Rect = { x: number, z: number, hx: number, hz: number }
-- A camp as the run needs it. Points are feet, on the floor.
export type Zone = {
	id: string,
	floorY: number,
	rect: Rect,
	-- The floor inset by levels.closeInset: whoever is not inside it when the gates close is
	-- moved to the entry (MustEnter). Not in the contract's list; added by the lead's ruling on
	-- the close.
	inner: Rect,
	-- The whole fenced rectangle: the floor grown by levels.fenceThickness, so a root on a fence
	-- top triggers the camp as one on its floor does.
	trigger: Rect,
	entry: Vector3,
	exit: Vector3,
	spawns: { Vector3 },
}
export type Stage = {
	-- "travel" | "camp"
	kind: string,
	name: string,
	zone: Zone?,
	waves: number,
	-- boss[wave] = that wave has a boss
	boss: { [number]: boolean },
	-- nil = the director's
	breatherSeconds: number?,
	merge: boolean,
	bankEachWave: boolean,
	targetWaveSeconds: number,
	maxAlive: number,
}
export type Plan = {
	levelId: string,
	difficulty: string,
	start: Vector3,
	killY: number,
	bounds: LevelGeometry.Bounds,
	camps: number,
	stages: { Stage },
}
export type State = {
	stage: number,
	-- "travel" | "armed" | "gate" | "fight" | "breather" | "over"
	step: string,
	wave: number,
	firstWave: number,
	gateAt: number,
	breatherUntil: number,
	-- Camps cleared; the stage index of the last one (0 = none).
	cleared: number,
	lastCleared: number,
	-- The last wave of the live camp whose kills are settled (banked, or skipped over): a `bank`
	-- covers the waves after it. Not in the contract's list; it is what `Action.count` is read from.
	settled: number,
	-- The clock the live camp's gates closed at: the close is judged again for
	-- levels.closeGraceSeconds after it (StillClosing).
	closedAt: number,
	-- Who was fighting when the run's last boundary was decided, before it released those who
	-- waited: the star is theirs (EarnsStar).
	fought: { number },
	ended: string?,
}
export type Input = {
	now: number,
	-- The fighting members' roots.
	roots: { Vector3 },
	-- standing[i]: the body whose root is roots[i] is on its feet (alive and not down). nil =
	-- every one of them is. Only a standing body triggers a camp.
	standing: { boolean }?,
	-- The userIds of the humans in the fight: admitted and not waiting in the lobby camp.
	fighters: { number },
	-- Nothing queued, no boss to place, nothing alive.
	fieldClear: boolean,
	-- Nothing queued and no boss to place.
	spawningDone: boolean,
	mergeOk: boolean,
	-- The director's breather, used by a stage that names none.
	breatherSeconds: number,
	-- "down" | "wipe" | nil
	fallen: string?,
	runCap: boolean,
}
-- kind: "gate" | "rearm" | "close" | "wave" | "clear" | "bank" | "boundary" | "breather" |
-- "open" | "travel" | "drop" | "move" | "end". `stage` is the stage the action is about.
export type Action = {
	kind: string,
	stage: number,
	wave: number?,
	at: number?,
	merged: boolean?,
	count: number?,
	reason: string?,
	-- On `boundary`: whether those who wait in the lobby camp are let into the level now. False
	-- when the same batch ends the run: nobody is brought into a level that is about to go.
	release: boolean?,
}
-- levelId -> difficulty -> cleared
export type Stars = { [string]: { [string]: boolean } }

local KIND_TRAVEL = "travel"
local KIND_CAMP = "camp"
-- Ruling 12: every camp lies within this many studs of the world origin on each axis, so the
-- crowd's wire (i16 at 1/32 stud, +-1024) can always carry it.
local WIRE_REACH = 1000
-- Under this Roblox destroys falling parts before the rescue could see them.
local LOWEST_KILL_Y = -450
-- The arena adapter's one camp (ruling 27).
local ARENA_ZONE = "arena"
-- The numbers a run reads, by where they are kept: Validate names every one that is missing.
local NEEDED = {
	rules = {
		"gateSeconds",
		"triggerBelow",
		"triggerHeight",
		"closeInset",
		"closeGraceSeconds",
		"crowdCeiling",
		"fenceThickness",
		"startSpacing",
		"boxMargin",
	},
	level = { "id", "name", "material" },
	crowd = { "regenShare", "maxAlive", "burst", "burstSpacing" },
	difficulty = { "hpScale", "damageScale", "plateScale", "countMult", "rewardMult" },
	reward = { "cash", "materials" },
	camp = { "x", "y", "z", "sx", "sz" },
	point = { "x", "z" },
	start = { "x", "y", "z" },
}
-- Where the members of a party start, in units of `spacing` round the start point: the first on
-- it, the next eight round it, then the ring again.
local START_OFFSETS = {
	{ 0, 0 },
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
	{ 1, 1 },
	{ -1, 1 },
	{ 1, -1 },
	{ -1, -1 },
}

local StageFlow = {}

-- Levels -------------------------------------------------------------------------------------

-- A level file as a level. One with no `mission` is taken as it stands (nil when it lacks
-- stages, difficulties or a crowd block). One that names a mission (the Raider Arena, ruling 27)
-- borrows that mission's crowd block and becomes one camp of all its waves, with the director's
-- breather, merging, and a bank at every wave clear: the arena as P5 played it. Its one
-- difficulty is `firstDifficulty`, the first of Expeditions.json `difficulties`: the map offers
-- that one for a level that names no others, so the two can never disagree.
function StageFlow.Resolve(
	file: Types.LevelFile,
	mission: Types.MissionConfig?,
	runCapSeconds: number,
	firstDifficulty: string?
): Types.LevelConfig?
	if file.mission == nil then
		local stages = file.stages
		local difficulties = file.difficulties
		local crowd = file.crowd
		if stages == nil or difficulties == nil or crowd == nil then
			return nil
		end
		local ownCap = file.runCapSeconds
		return {
			version = file.version,
			id = file.id,
			name = file.name,
			layout = file.layout,
			mission = nil,
			material = file.material or "",
			targetMinutes = file.targetMinutes or 0,
			-- A level that names no cap of its own runs under the director's.
			runCapSeconds = if ownCap ~= nil and ownCap > 0 then ownCap else runCapSeconds,
			difficulties = difficulties,
			crowd = crowd,
			stages = stages,
		}
	end
	local block = if mission ~= nil then mission.crowd else nil
	if mission == nil or block == nil or firstDifficulty == nil then
		return nil
	end
	local only: Types.LevelDifficulty = {
		hpScale = block.hpScale,
		damageScale = block.damageScale,
		plateScale = block.plateScale,
		countMult = 1,
		rewardMult = 1,
		recommendedTier = file.recommendedTier or 0,
	}
	local camp: Types.LevelStage = {
		kind = KIND_CAMP,
		name = file.name,
		zone = ARENA_ZONE,
		waves = block.waves,
		targetWaveSeconds = mission.targetWaveSeconds,
		breatherSeconds = nil,
		merge = true,
		bankEachWave = true,
		maxAlive = nil,
	}
	return {
		version = file.version,
		id = file.id,
		name = file.name,
		layout = file.layout,
		mission = file.mission,
		material = mission.material,
		targetMinutes = mission.targetMinutes,
		runCapSeconds = runCapSeconds,
		difficulties = { [firstDifficulty] = only },
		crowd = {
			regenShare = block.regenShare,
			maxAlive = block.maxAlive,
			burst = block.burst,
			burstSpacing = block.burstSpacing,
			eliteKind = block.eliteKind,
			rewards = block.rewards,
		},
		stages = { camp },
	}
end

local function campOf(camps: { Types.LevelCamp }, id: string?): Types.LevelCamp?
	if id == nil then
		return nil
	end
	for _, camp in camps do
		if camp.id == id then
			return camp
		end
	end
	return nil
end

-- Is the world point (x, z) on the camp's floor, `inset` studs in from every edge?
local function onFloor(camp: Types.LevelCamp, x: number, z: number, inset: number): boolean
	return math.abs(x - camp.x) <= camp.sx / 2 - inset
		and math.abs(z - camp.z) <= camp.sz / 2 - inset
end

-- A level's files are data somebody typed. What the rules read is looked at here first, so a
-- key that is missing, or holds the wrong kind of value, becomes a line of Validate's answer and
-- never a throw: a throw in the remote's thread leaves the leader's Depart with no answer.

-- Adds `prefix .. key` to `missing` for every key `holder` does not hold as a `kind`.
local function need(
	missing: { string },
	holder: any,
	prefix: string,
	keys: { string },
	kind: string
): ()
	local held = type(holder) == "table"
	for _, key in keys do
		if not held or type(holder[key]) ~= kind then
			table.insert(missing, prefix .. key)
		end
	end
end

-- What the run reads of a layout's camp that the camp does not hold.
local function campLacks(camp: any): { string }
	local missing: { string } = {}
	need(missing, camp, "", NEEDED.camp, "number")
	need(missing, camp.entry, "entry.", NEEDED.point, "number")
	need(missing, camp.exit, "exit.", NEEDED.point, "number")
	local spawns = camp.spawns
	if type(spawns) ~= "table" then
		table.insert(missing, "spawns")
	else
		for index, point in spawns do
			need(missing, point, `spawns[{index}].`, NEEDED.point, "number")
		end
	end
	return missing
end

-- Ruling 6: a cap on living bodies is a whole number of at least 1, wherever it is written. (0
-- would never spawn here, and reads as "none given" where 0 is falsy.)
local function isCap(value: any): boolean
	return type(value) == "number" and value >= 1 and value % 1 == 0
end

-- One line per problem; an empty list is a level that may be played. `kinds` are the crowd kinds
-- of ProvingGrounds.json, `ranks` the place of every difficulty in Expeditions.json and `rules`
-- Combat.json `levels`. Nothing here throws on a file with a key missing: that is a problem too.
function StageFlow.Validate(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	kinds: { [string]: Types.CrowdKindDef },
	ranks: { [string]: number },
	rules: Types.CombatLevelsConfig
): { string }
	local problems: { string } = {}
	local function problem(text: string): ()
		table.insert(problems, `{tostring(level.id)}: {text}`)
	end
	-- One line for everything `where` lacks; true when it lacks something.
	local function lacks(where: string, missing: { string }): boolean
		if #missing > 0 then
			problem(`{where} lacks {table.concat(missing, ", ")}`)
		end
		return #missing > 0
	end

	local missing: { string } = {}
	need(missing, rules, "levels.", NEEDED.rules, "number")
	lacks("Combat.json", missing)

	missing = {}
	need(missing, level, "", NEEDED.level, "string")
	local crowd: any = level.crowd
	need(missing, crowd, "crowd.", NEEDED.crowd, "number")
	local rewards: { [string]: any } = {}
	if type(crowd) == "table" and type(crowd.rewards) == "table" then
		rewards = crowd.rewards
		for kind, reward in rewards do
			need(missing, reward, `crowd.rewards.{tostring(kind)}.`, NEEDED.reward, "number")
		end
	else
		table.insert(missing, "crowd.rewards")
	end
	local difficulties: any = level.difficulties
	if type(difficulties) ~= "table" or next(difficulties) == nil then
		table.insert(missing, "difficulties")
	else
		for name, scales in difficulties do
			need(missing, scales, `difficulties.{tostring(name)}.`, NEEDED.difficulty, "number")
		end
	end
	lacks("the level", missing)
	if type(crowd) == "table" then
		if type(crowd.maxAlive) == "number" and not isCap(crowd.maxAlive) then
			problem(`crowd.maxAlive is {crowd.maxAlive}, not a whole number of at least 1`)
		end
		if type(crowd.burst) == "number" and crowd.burst < 1 then
			problem(`crowd.burst is {crowd.burst}: a burst is at least 1 body`)
		end
	end

	missing = {}
	need(missing, layout, "", { "killY" }, "number")
	need(missing, (layout :: any).start, "start.", NEEDED.start, "number")
	local camps: { Types.LevelCamp } = {}
	if type(layout.camps :: any) == "table" then
		camps = layout.camps
	else
		table.insert(missing, "camps")
	end
	lacks("the layout", missing)
	if type(layout.killY :: any) == "number" and layout.killY < LOWEST_KILL_Y then
		problem(`killY {layout.killY} is under {LOWEST_KILL_Y}`)
	end

	-- A kind that fights must exist and must be priced.
	local function checkKind(where: string, kind: string): Types.CrowdKindDef?
		local def = kinds[kind]
		if def == nil then
			problem(`{where} names the unknown kind "{kind}"`)
		end
		if rewards[kind] == nil then
			problem(`{where} fields "{kind}", which rewards does not price`)
		end
		return def
	end

	local stages: { Types.LevelStage } = if type(level.stages :: any) == "table"
		then level.stages
		else {}
	if #stages == 0 then
		problem("it has no stage")
	end
	for index, stage in stages do
		if stage.kind ~= KIND_TRAVEL and stage.kind ~= KIND_CAMP then
			problem(`stage {index} is a "{tostring(stage.kind)}", neither travel nor camp`)
		end
		if type(stage.name :: any) ~= "string" then
			problem(`stage {index} has no name`)
		end
		local before = stages[index - 1]
		if before ~= nil and before.kind == stage.kind then
			problem(
				`stages {index - 1} and {index} are both {tostring(stage.kind)}: travel and camp take turns`
			)
		end
	end
	local last = stages[#stages]
	if last ~= nil and last.kind ~= KIND_CAMP then
		problem("its last stage is not a camp")
	end

	local barrier: any = layout.barrier
	local walled = type(barrier) == "table"
		and type(barrier.height) == "number"
		and barrier.height > 0
	-- A crowd body may be launched this far over its floor: the wire must carry that too.
	local ceiling: any = rules.crowdCeiling
	if type(ceiling) ~= "number" then
		ceiling = 0
	end
	for index, stage in stages do
		if stage.kind ~= KIND_CAMP then
			continue
		end
		local where = `stage {index} ("{tostring(stage.name)}")`
		local camp = campOf(camps, stage.zone)
		if camp == nil then
			problem(`{where} names the zone "{tostring(stage.zone)}", which the layout lacks`)
		elseif lacks(`{where}: camp {camp.id}`, campLacks(camp)) then
			-- Nothing more can be said of a camp whose numbers are not there.
			camp = nil
		else
			if #camp.spawns == 0 then
				problem(`{where} has no spawn point`)
			end
			if not walled then
				problem(`{where} has no barrier`)
			end
			for spawnIndex, point in camp.spawns do
				if not onFloor(camp, point.x, point.z, 0) then
					problem(`{where}: spawn point {spawnIndex} lies off the floor`)
				end
			end
			if not onFloor(camp, camp.entry.x, camp.entry.z, 0) then
				problem(`{where}: the entry lies off the floor`)
			end
			if not onFloor(camp, camp.exit.x, camp.exit.z, 0) then
				problem(`{where}: the exit lies off the floor`)
			end
			if
				math.abs(camp.x) + camp.sx / 2 > WIRE_REACH
				or math.abs(camp.z) + camp.sz / 2 > WIRE_REACH
				or camp.y < -WIRE_REACH
				or camp.y + ceiling > WIRE_REACH
			then
				problem(`{where} lies beyond {WIRE_REACH} studs of the world origin`)
			end
		end
		local cap: any = stage.maxAlive
		if cap ~= nil and not isCap(cap) then
			problem(`{where}: maxAlive is {tostring(cap)}, not a whole number of at least 1`)
		end
		local pace: any = stage.targetWaveSeconds
		if type(pace) ~= "number" or pace <= 0 then
			problem(`{where} has no targetWaveSeconds`)
		end
		local rest: any = stage.breatherSeconds
		if rest ~= nil and (type(rest) ~= "number" or rest < 0) then
			problem(`{where}: breatherSeconds is {tostring(rest)}, not a time`)
		end
		local waves: any = stage.waves
		if type(waves) ~= "table" or #waves == 0 then
			problem(`{where} has no wave`)
			waves = {}
		end
		for waveIndex, wave in waves :: { Types.MissionCrowdWave } do
			local here = `{where} wave {waveIndex}`
			local groups: any = wave.groups
			if type(groups) ~= "table" then
				problem(`{here} has no groups`)
				groups = {}
			end
			for groupIndex, group: any in groups do
				if type(group.kind) ~= "string" or type(group.count) ~= "number" then
					problem(`{here}: group {groupIndex} lacks its kind or its count`)
					continue
				end
				checkKind(here, group.kind)
				if group.perExtra ~= nil and type(group.perExtra) ~= "number" then
					problem(`{here}: group {groupIndex}'s perExtra is not a number`)
				end
				local needs = group.minDifficulty
				if needs ~= nil and ranks[needs] == nil then
					problem(`{here}: minDifficulty "{tostring(needs)}" is no difficulty`)
				end
			end
			local boss: any = wave.boss
			if boss == nil then
				continue
			end
			local at = boss.at
			if
				type(boss.kind) ~= "string"
				or type(boss.valor) ~= "number"
				or type(at) ~= "table"
				or type(at[1]) ~= "number"
				or type(at[2]) ~= "number"
			then
				problem(`{here}: its boss lacks its kind, its place or its valor`)
				continue
			end
			local def = checkKind(`{here}'s boss`, boss.kind)
			local radius = if def ~= nil then def.radius else 0
			if camp ~= nil and not onFloor(camp, camp.x + at[1], camp.z + at[2], radius) then
				problem(`{here}: the boss's place lies off the floor`)
			end
		end
	end
	local elite: any = if type(crowd) == "table" then crowd.eliteKind else nil
	if elite ~= nil then
		checkKind("eliteKind", elite)
	end
	return problems
end

-- `rect` with every edge moved out by `by` studs (in, when it is negative).
local function grown(rect: Rect, by: number): Rect
	return {
		x = rect.x,
		z = rect.z,
		hx = math.max(rect.hx + by, 0),
		hz = math.max(rect.hz + by, 0),
	}
end

local function inRect(rect: Rect, x: number, z: number): boolean
	return math.abs(x - rect.x) <= rect.hx and math.abs(z - rect.z) <= rect.hz
end

-- The level as the run walks it, at one difficulty. nil, with the reason, for a difficulty the
-- level lacks, a camp stage whose zone the layout lacks, or a camp whose entry lies within
-- levels.closeInset of its floor's edge (the close would move a fighter who stands on the entry
-- back onto it, into a body the gate overlaps). Asked after Validate: it reads the keys Validate
-- answers for.
function StageFlow.Plan(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	difficulty: string,
	rules: Types.CombatLevelsConfig,
	bounds: LevelGeometry.Bounds
): (Plan?, string?)
	if level.difficulties[difficulty] == nil then
		return nil, `{level.id} has no difficulty "{difficulty}"`
	end
	local stages: { Stage } = {}
	local camps = 0
	for _, stage in level.stages do
		if stage.kind ~= KIND_CAMP then
			table.insert(stages, {
				kind = KIND_TRAVEL,
				-- The client's RunState must carry a string (Validate names a stage without one).
				name = stage.name or "",
				zone = nil,
				waves = 0,
				boss = {},
				breatherSeconds = nil,
				merge = false,
				bankEachWave = false,
				targetWaveSeconds = 0,
				maxAlive = 0,
			})
			continue
		end
		local camp = campOf(layout.camps, stage.zone)
		if camp == nil then
			return nil, `{level.id}: the layout has no camp "{tostring(stage.zone)}"`
		end
		local rect: Rect = { x = camp.x, z = camp.z, hx = camp.sx / 2, hz = camp.sz / 2 }
		local inner = grown(rect, -rules.closeInset)
		if not inRect(inner, camp.entry.x, camp.entry.z) then
			return nil,
				`{level.id}: the entry of camp {camp.id} is within closeInset of its floor's edge`
		end
		local spawns: { Vector3 } = {}
		for _, point in camp.spawns do
			table.insert(spawns, Vector3.new(point.x, camp.y, point.z))
		end
		local zone: Zone = {
			id = camp.id,
			floorY = camp.y,
			rect = rect,
			inner = inner,
			trigger = grown(rect, rules.fenceThickness),
			entry = Vector3.new(camp.entry.x, camp.y, camp.entry.z),
			exit = Vector3.new(camp.exit.x, camp.y, camp.exit.z),
			spawns = spawns,
		}
		local waves: { Types.MissionCrowdWave } = stage.waves or {}
		local boss: { [number]: boolean } = {}
		for index, wave in waves do
			if wave.boss ~= nil then
				boss[index] = true
			end
		end
		camps += 1
		table.insert(stages, {
			kind = KIND_CAMP,
			name = stage.name or "",
			zone = zone,
			waves = #waves,
			boss = boss,
			breatherSeconds = stage.breatherSeconds,
			merge = stage.merge == true,
			bankEachWave = stage.bankEachWave == true,
			targetWaveSeconds = stage.targetWaveSeconds or 0,
			maxAlive = stage.maxAlive or level.crowd.maxAlive,
		})
	end
	return {
		levelId = level.id,
		difficulty = difficulty,
		start = Vector3.new(layout.start.x, layout.start.y, layout.start.z),
		killY = layout.killY,
		bounds = bounds,
		camps = camps,
		stages = stages,
	}
end

-- The run ------------------------------------------------------------------------------------

local function stepFor(stage: Stage?): string
	return if stage ~= nil and stage.kind == KIND_CAMP then "armed" else "travel"
end

function StageFlow.Begin(plan: Plan): State
	return {
		stage = 1,
		step = stepFor(plan.stages[1]),
		wave = 0,
		firstWave = 1,
		gateAt = 0,
		breatherUntil = 0,
		cleared = 0,
		lastCleared = 0,
		settled = 0,
		closedAt = 0,
		fought = {},
		ended = nil,
	}
end

-- Ruling 9: a camp triggers when the root of any fighting member is inside its trigger rectangle
-- (the whole fenced rectangle, edges included) and between levels.triggerBelow under and
-- levels.triggerHeight above its floor. A root sits above the feet, so triggerBelow only forgives
-- a body sunk into the floor for a frame. A body that is down does not count: a countdown that
-- ends with nobody on their feet re-arms the camp, and a downed body still inside would trigger
-- it again, and again.
local function triggered(zone: Zone, input: Input, rules: Types.CombatLevelsConfig): boolean
	local standing = input.standing
	for index, root in input.roots do
		local above = root.Y - zone.floorY
		if
			above >= -rules.triggerBelow
			and above <= rules.triggerHeight
			and inRect(zone.trigger, root.X, root.Z)
			and (standing == nil or standing[index] ~= false)
		then
			return true
		end
	end
	return false
end

-- The stage index of the camp that may trigger now (ruling 10: only the next one), or 0.
local function armedCamp(plan: Plan, state: State): number
	local index = if state.step == "armed"
		then state.stage
		elseif state.step == "travel" then state.stage + 1
		else 0
	local stage = plan.stages[index]
	if stage == nil or stage.kind ~= KIND_CAMP then
		return 0
	end
	return index
end

local function over(state: State, reason: string): Action
	state.step = "over"
	state.ended = reason
	return { kind = "end", stage = state.stage, reason = reason }
end

-- Into the countdown of camp `index`.
local function gate(
	state: State,
	index: number,
	now: number,
	rules: Types.CombatLevelsConfig
): Action
	state.stage = index
	state.step = "gate"
	state.gateAt = now + rules.gateSeconds
	return { kind = "gate", stage = index, at = state.gateAt }
end

-- The gates close and the camp's first wave is queued (wave 1 unless a boss skip named another).
local function close(state: State, actions: { Action }, now: number): ()
	local first = math.max(state.firstWave, 1)
	state.firstWave = 1
	state.step = "fight"
	state.wave = first
	state.settled = first - 1
	state.closedAt = now
	table.insert(actions, { kind = "close", stage = state.stage })
	table.insert(actions, { kind = "wave", stage = state.stage, wave = first })
end

-- The live camp is behind the party (cleared, or skipped): on to the next stage, or the end.
-- Appends `open`, then `travel` when a road follows, or `end` `cleared` after the last stage.
local function leaveCamp(plan: Plan, state: State, actions: { Action }): ()
	local index = state.stage
	state.cleared += 1
	state.lastCleared = index
	table.insert(actions, { kind = "open", stage = index })
	local following = plan.stages[index + 1]
	if following == nil then
		table.insert(actions, over(state, "cleared"))
		return
	end
	state.stage = index + 1
	state.step = stepFor(following)
	state.wave = 0
	if following.kind ~= KIND_CAMP then
		table.insert(actions, { kind = "travel", stage = index + 1 })
	end
end

-- One tick of the run: the first row of the contract's table that matches wins. Returns the
-- actions to execute, in order (often none), and moves `state` on.
function StageFlow.Advance(
	plan: Plan,
	state: State,
	input: Input,
	rules: Types.CombatLevelsConfig
): { Action }
	local actions: { Action } = {}
	local step = state.step
	if step == "over" then
		return actions
	end
	if input.runCap then
		table.insert(actions, over(state, "runCap"))
		return actions
	end
	local fallen = input.fallen
	-- A clear field wins (ruling 17): the fallen do not lose a run whose field is clear. The
	-- rows below then run, and a camp that was just beaten clears instead.
	if fallen ~= nil and not input.fieldClear then
		table.insert(actions, over(state, fallen))
		return actions
	end
	local stage = plan.stages[state.stage]

	if step == "travel" or step == "armed" then
		local index = armedCamp(plan, state)
		local camp = plan.stages[index]
		local zone = if camp ~= nil then camp.zone else nil
		if zone ~= nil and triggered(zone, input, rules) then
			table.insert(actions, gate(state, index, input.now, rules))
		end
		return actions
	end

	if step == "gate" then
		-- The countdown cannot be cancelled: nobody has to be inside when it ends.
		if input.now >= state.gateAt then
			if fallen ~= nil then
				-- But somebody has to be able to fight. With no fighter on their feet (a solo
				-- reset during the countdown) the gates would close on a wave nobody can meet and
				-- the run would be lost to it. The camp is armed again instead, and triggers when
				-- somebody walks in. A boss skip's first wave is kept for then.
				state.step = "armed"
				state.gateAt = 0
				table.insert(actions, { kind = "rearm", stage = state.stage })
			else
				close(state, actions, input.now)
			end
		end
		return actions
	end

	if step == "breather" then
		if input.now >= state.breatherUntil then
			state.wave += 1
			state.step = "fight"
			table.insert(actions, { kind = "wave", stage = state.stage, wave = state.wave })
		end
		return actions
	end

	-- step == "fight"
	if stage == nil or not input.spawningDone then
		return actions
	end
	local wave = state.wave
	if not input.fieldClear then
		-- Spawning is over: the director may fold the next wave in on top of this one, in a
		-- stage that merges, and never into or out of a boss wave.
		if
			stage.merge
			and wave < stage.waves
			and not stage.boss[wave]
			and not stage.boss[wave + 1]
			and input.mergeOk
		then
			state.wave = wave + 1
			table.insert(actions, {
				kind = "wave",
				stage = state.stage,
				wave = wave + 1,
				merged = true,
			})
		end
		return actions
	end

	-- The field is clear: the wave (or merged pair) is beaten. Who beat it is noted before the
	-- `boundary` below lets in those who waited: a star is for the last wave's fighters.
	state.fought = table.clone(input.fighters)
	table.insert(actions, { kind = "clear", stage = state.stage, wave = wave })
	local lastWave = wave >= stage.waves
	if lastWave or stage.bankEachWave then
		-- Ruling 15: only a checkpoint pays. A camp's clear is one; so is every wave clear of a
		-- stage that banks each wave.
		table.insert(actions, {
			kind = "bank",
			stage = state.stage,
			wave = wave,
			count = wave - state.settled,
		})
		state.settled = wave
	end
	-- The run ends in this batch when this was the last camp's last wave.
	local ending = lastWave and plan.stages[state.stage + 1] == nil
	table.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })
	if not lastWave then
		state.step = "breather"
		state.breatherUntil = input.now + (stage.breatherSeconds or input.breatherSeconds)
		table.insert(actions, { kind = "breather", stage = state.stage, at = state.breatherUntil })
		return actions
	end
	leaveCamp(plan, state, actions)
	return actions
end

-- Ends the run for a reason no tick finds by itself ("abandoned"). Nothing once it is over.
function StageFlow.Finish(_plan: Plan, state: State, reason: string): { Action }
	if state.step == "over" then
		return {}
	end
	return { over(state, reason) }
end

-- The first wave with a boss after `after` in `stage`, or 0.
local function bossWaveAfter(stage: Stage?, after: number): number
	if stage == nil then
		return 0
	end
	for wave = after + 1, stage.waves do
		if stage.boss[wave] then
			return wave
		end
	end
	return 0
end

-- Studio only (ruling 33). "stage" finishes this part: on the road the party is moved to the
-- next camp and its countdown starts, a countdown ends now, a live camp is dropped and counts as
-- cleared. "boss" goes to the next wave with a boss, in this camp or a later one (the camps
-- between count as cleared), and does nothing when none is left. No skip banks anything, and
-- nothing skipped is credited. `fighters` is Input.fighters, for a skip that ends at a boundary.
function StageFlow.Skip(
	plan: Plan,
	state: State,
	which: string,
	now: number,
	rules: Types.CombatLevelsConfig,
	fighters: { number }?
): { Action }
	local actions: { Action } = {}
	local step = state.step
	if step == "over" then
		return actions
	end
	local live = step == "fight" or step == "breather"

	if which == "stage" then
		if step == "travel" or step == "armed" then
			local index = armedCamp(plan, state)
			if index ~= 0 then
				table.insert(actions, { kind = "move", stage = index })
				table.insert(actions, gate(state, index, now, rules))
			end
		elseif step == "gate" then
			close(state, actions, now)
		else
			state.fought = if fighters ~= nil then table.clone(fighters) else {}
			local ending = plan.stages[state.stage + 1] == nil
			table.insert(actions, { kind = "drop", stage = state.stage })
			table.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })
			leaveCamp(plan, state, actions)
		end
		return actions
	end
	if which ~= "boss" then
		return actions
	end

	-- In this camp: its countdown, its fight or its breather; or the camp that is armed.
	local here = plan.stages[state.stage]
	local inCamp = live or step == "gate" or step == "armed"
	if inCamp then
		local wave = bossWaveAfter(here, if live then state.wave else 0)
		if wave ~= 0 then
			if live then
				state.step = "fight"
				state.wave = wave
				state.settled = wave - 1
				table.insert(actions, { kind = "drop", stage = state.stage })
				table.insert(actions, { kind = "wave", stage = state.stage, wave = wave })
			elseif step == "gate" then
				state.firstWave = wave
				close(state, actions, now)
			else
				state.firstWave = wave
				table.insert(actions, { kind = "move", stage = state.stage })
				table.insert(actions, gate(state, state.stage, now, rules))
			end
			return actions
		end
	end
	-- In a later camp.
	local target = 0
	local targetWave = 0
	for index = state.stage + 1, #plan.stages do
		local wave = bossWaveAfter(plan.stages[index], 0)
		if wave ~= 0 then
			target = index
			targetWave = wave
			break
		end
	end
	if target == 0 then
		return actions
	end
	if live or step == "gate" then
		table.insert(actions, { kind = "drop", stage = state.stage })
	end
	-- Every camp from here to the boss's is behind the party now.
	for index = state.stage, target - 1 do
		local between = plan.stages[index]
		if between ~= nil and between.kind == KIND_CAMP then
			state.cleared += 1
			state.lastCleared = index
			table.insert(actions, { kind = "open", stage = index })
		end
	end
	state.firstWave = targetWave
	state.wave = 0
	table.insert(actions, { kind = "move", stage = target })
	table.insert(actions, gate(state, target, now, rules))
	return actions
end

-- Studio only: the `wave` lever. Forces wave `wave` of the LIVE camp (its fight or its
-- breather), clamped to the camp's waves: the field is dropped and that wave starts at once.
-- The waves before it are settled without being paid, as a skip's are. Nothing elsewhere.
function StageFlow.Force(plan: Plan, state: State, wave: number): { Action }
	local step = state.step
	local stage = plan.stages[state.stage]
	if stage == nil or (step ~= "fight" and step ~= "breather") or stage.waves < 1 then
		return {}
	end
	local target = math.min(math.max(math.floor(wave), 1), stage.waves)
	state.step = "fight"
	state.wave = target
	state.settled = target - 1
	return {
		{ kind = "drop", stage = state.stage },
		{ kind = "wave", stage = state.stage, wave = target },
	}
end

-- What the HUD is told. `bossUp` = a boss is alive or still to place.
function StageFlow.Phase(state: State, bossUp: boolean): Types.RunPhase
	local step = state.step
	if step == "gate" then
		return "gate"
	elseif step == "fight" then
		return if bossUp then "boss" else "wave"
	elseif step == "breather" then
		return "breather"
	elseif step == "over" then
		return "summary"
	end
	return "travel"
end

-- P5 ruling 17, as P5 ran it: the director keeps its tempo for as long as a camp is closed,
-- through its fights AND its breathers. A breather lets the kill window run out, so the wave
-- after a rest is paced (its extra elite, its first bursts) by how the party is doing now, not
-- by the last seconds of the wave before. Never on the road or in a countdown: the close starts
-- the tempo afresh.
function StageFlow.Directs(state: State): boolean
	local step = state.step
	return step == "fight" or step == "breather"
end

-- Ruling 9, the close, judged again. The server decides who is inside from its own copy of each
-- body, which trails what the player sees: someone it saw inside may have been in the gate gap.
-- So for levels.closeGraceSeconds after the gates close, the question stays open, and a fighter
-- found outside (MustEnter) is still brought to the entry.
function StageFlow.StillClosing(state: State, now: number, rules: Types.CombatLevelsConfig): boolean
	local step = state.step
	return (step == "fight" or step == "breather")
		and now - state.closedAt < rules.closeGraceSeconds
end

-- Where a body goes --------------------------------------------------------------------------

-- Ruling 18: the entry of the camp that is counting down, live or between waves; else the exit
-- of the last cleared camp; else the level's start.
function StageFlow.SafePoint(plan: Plan, state: State): Vector3
	local step = state.step
	if step == "gate" or step == "fight" or step == "breather" then
		local stage = plan.stages[state.stage]
		local zone = if stage ~= nil then stage.zone else nil
		if zone ~= nil then
			return zone.entry
		end
	end
	local cleared = plan.stages[state.lastCleared]
	local zone = if cleared ~= nil then cleared.zone else nil
	if zone ~= nil then
		return zone.exit
	end
	return plan.start
end

-- Ruling 9, the close (and the lead's ruling on its edge): when a camp's gates close, must the
-- body at `position` be moved to the camp's entry? Yes unless its root is inside the floor by
-- at least levels.closeInset on every side: the gates and the invisible wall turn solid on the
-- floor's edge, and a body standing in a gate gap or against it would be inside a solid Part.
function StageFlow.MustEnter(zone: Zone, position: Vector3): boolean
	return not inRect(zone.inner, position.X, position.Z)
end

-- The close judged again, in its grace (StillClosing): a body is brought to the entry only when
-- it is off the floor rectangle itself. That rectangle's edge is the invisible wall's inner face,
-- so a fighter who was inside at the close cannot cross it, and one the close missed (it read a
-- lagged copy of them) is outside it. The close's own margin (closeInset) is for the moment the
-- wall turns solid; used here it would take a fighter who dashed at a gate back to the entry.
function StageFlow.Strayed(zone: Zone, position: Vector3): boolean
	return not inRect(zone.rect, position.X, position.Z)
end

-- Is `position` under `killY`, or more than `margin` outside the box on X or Z? (The lobby is
-- judged with this too.)
function StageFlow.OutOfBox(
	bounds: LevelGeometry.Bounds,
	killY: number,
	position: Vector3,
	margin: number
): boolean
	return position.Y < killY
		or position.X < bounds.minX - margin
		or position.X > bounds.maxX + margin
		or position.Z < bounds.minZ - margin
		or position.Z > bounds.maxZ + margin
end

-- Ruling 19: has a body left the place it may be in? While a camp is closed (its fight and its
-- breathers) that place is the camp: its floor plus `rescue.outside`, down to its floor less
-- `rescue.below`. Otherwise it is the level: its bounds plus `boxMargin`, down to killY.
function StageFlow.IsOut(
	plan: Plan,
	state: State,
	position: Vector3,
	rescue: { below: number, outside: number },
	boxMargin: number
): boolean
	local step = state.step
	if step == "fight" or step == "breather" then
		local stage = plan.stages[state.stage]
		local zone = if stage ~= nil then stage.zone else nil
		if zone ~= nil then
			local rect = zone.rect
			return position.Y < zone.floorY - rescue.below
				or math.abs(position.X - rect.x) > rect.hx + rescue.outside
				or math.abs(position.Z - rect.z) > rect.hz + rescue.outside
		end
	end
	return StageFlow.OutOfBox(plan.bounds, plan.killY, position, boxMargin)
end

-- Ruling 19, whole: must the body at `position` be put back on the ground, and where? "level" =
-- the run's safe point, "lobby" = a point of the lobby camp, nil = it stays where it is.
-- `plan` and `state` are nil when no level is played; `waiting` = the member waits in the lobby
-- camp for the next boundary; `lobby` and `lobbyKillY` are the lobby camp's box.
-- * No run, or a member who waits: judged by the lobby's box, put on a lobby point.
-- * A run that is over (its summary is up and its level is about to go): nobody is put INTO the
--   level any more. A body in the lobby camp stays there (a respawn after a reset, a member
--   admitted on the summary, a rejoin), one still inside the level's box stays where the end
--   left it until the return, and one that is in neither (a fall) goes to the lobby camp.
-- * A live run: IsOut, and the safe point.
function StageFlow.Rescue(
	plan: Plan?,
	state: State?,
	waiting: boolean,
	position: Vector3,
	rescue: { below: number, outside: number },
	boxMargin: number,
	lobby: LevelGeometry.Bounds,
	lobbyKillY: number
): string?
	local inLobby = not StageFlow.OutOfBox(lobby, lobbyKillY, position, boxMargin)
	if plan == nil or state == nil or waiting then
		return if inLobby then nil else "lobby"
	end
	local out = StageFlow.IsOut(plan, state, position, rescue, boxMargin)
	if state.step == "over" then
		return if inLobby or not out then nil else "lobby"
	end
	return if out then "level" else nil
end

-- Where the `index`-th member of a party (1-based) stands at the start: round the start point,
-- `spacing` apart, so nobody is placed inside anybody.
function StageFlow.StartPoint(plan: Plan, index: number, spacing: number): Vector3
	local offset = START_OFFSETS[(math.max(index, 1) - 1) % #START_OFFSETS + 1]
	local start = plan.start
	return Vector3.new(start.X + offset[1] * spacing, start.Y, start.Z + offset[2] * spacing)
end

-- Ruling 13: the `index`-th body (0-based) of a burst of `size` at spawn point `at`: a grid of
-- pitch `spacing`, centred across, its rows stepping toward the camp's centre, so a burst at the
-- fence arrives as a block inside the camp. On the camp's floor.
function StageFlow.BurstPoint(
	zone: Zone,
	at: Vector3,
	size: number,
	index: number,
	spacing: number
): Vector3
	local inward = Vector3.new(zone.rect.x - at.X, 0, zone.rect.z - at.Z)
	inward = if inward.Magnitude > 1e-3 then inward.Unit else Vector3.new(0, 0, 1)
	local across = Vector3.new(-inward.Z, 0, inward.X)
	local columns = math.max(math.ceil(math.sqrt(size)), 1)
	local row = index // columns
	local column = index % columns
	local offset = across * ((column - (columns - 1) / 2) * spacing) + inward * (row * spacing)
	return Vector3.new(at.X + offset.X, zone.floorY, at.Z + offset.Z)
end

-- Ruling 13: `boss.at` is { x, z } from the camp's centre.
function StageFlow.BossPoint(zone: Zone, at: { number }): Vector3
	return Vector3.new(zone.rect.x + (at[1] or 0), zone.floorY, zone.rect.z + (at[2] or 0))
end

-- The map ------------------------------------------------------------------------------------

local function nodeOf(map: Types.ExpeditionsConfig, id: string?): Types.MapNode?
	if id == nil then
		return nil
	end
	for _, node in map.nodes do
		if node.id == id then
			return node
		end
	end
	return nil
end

local function hasStar(stars: Stars, levelId: string?): boolean
	local own = if levelId ~= nil then stars[levelId] else nil
	return own ~= nil and next(own) ~= nil
end

local function starCount(stars: Stars): number
	local count = 0
	for _, difficulties in stars do
		for _ in difficulties do
			count += 1
		end
	end
	return count
end

-- One node for one player (rulings 25 and 28). Whether it is open is the LEADER's doing; the
-- stars shown are the player's own. "notBuilt" wins over every other reason. nil for no such
-- node.
function StageFlow.NodeState(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leader: Stars,
	own: Stars,
	nodeId: string
): Types.MapNodeState?
	local node = nodeOf(map, nodeId)
	if node == nil then
		return nil
	end
	local levelId = node.level
	local stars: { string } = {}
	local earned = if levelId ~= nil then own[levelId] else nil
	if earned ~= nil then
		for _, difficulty in map.difficulties do
			if earned[difficulty] then
				table.insert(stars, difficulty)
			end
		end
	end
	local state: Types.MapNodeState = {
		id = node.id,
		open = false,
		reason = nil,
		needs = nil,
		stars = stars,
	}
	if levelId == nil or built[levelId] ~= true then
		state.reason = "notBuilt"
		return state
	end
	local requires = node.requires
	local needsNode = if requires ~= nil then requires.node else nil
	if needsNode ~= nil then
		local required = nodeOf(map, needsNode)
		if not hasStar(leader, if required ~= nil then required.level else nil) then
			state.reason = "needsNode"
			state.needs = if required ~= nil then required.name else needsNode
			return state
		end
	end
	local needsStars = if requires ~= nil then requires.stars else nil
	if needsStars ~= nil and starCount(leader) < needsStars then
		state.reason = "needsStars"
		state.needs = tostring(needsStars)
		return state
	end
	state.open = true
	return state
end

-- Every node, in the config's order, for one player.
function StageFlow.MapState(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leader: Stars,
	own: Stars,
	leaderUserId: number
): Types.MapState
	local nodes: { Types.MapNodeState } = {}
	for _, node in map.nodes do
		local state = StageFlow.NodeState(map, built, leader, own, node.id)
		if state ~= nil then
			table.insert(nodes, state)
		end
	end
	return { kind = "map", leaderUserId = leaderUserId, nodes = nodes }
end

-- The star of one difficulty of one level, for the run that was just cleared at it. True when
-- it is new.
function StageFlow.Award(stars: Stars, levelId: string, difficulty: string): boolean
	local own = stars[levelId]
	if own == nil then
		own = {}
		stars[levelId] = own
	end
	if own[difficulty] then
		return false
	end
	own[difficulty] = true
	return true
end

-- Who earns the star of a run: nobody unless it was cleared, and then those who were fighting
-- before its last boundary (State.fought). The boundary itself lets in everyone who waited in
-- the lobby camp, so "whoever fights at the end" would be everybody.
function StageFlow.EarnsStar(state: State, userId: number): boolean
	return state.ended == "cleared" and table.find(state.fought, userId) ~= nil
end

return StageFlow
