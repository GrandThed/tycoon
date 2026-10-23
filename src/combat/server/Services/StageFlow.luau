--!strict
-- The rules of a run through a level (docs/INTERFACES.md "L1 contracts", rulings 1, 2, 9, 10,
-- 13–19, 25, 27, 28 and "A run"; "L1b contracts", rulings L1b-1 to L1b-22; L1b Wave 2 "the
-- long road", L1b-W2-5 to -8 and -21: tents, the population rule, the clear bonus; L1b Wave 4 "no
-- waits, no walls", L1b-W4-14 to -16 and -28 to -31: the chase regions, the pace tent's stock, the
-- clear on the fielded raiders, the bonus on what was fielded, N's approaches; L3 W1, L3-17: a
-- difficulty's first-clear reward, FirstClear and its Validate lines). A level is an
-- ordered list of stages, `travel` and `camp`; since L1b only a camp that locks (the boss room)
-- is a stage, and every other camp of the layout is open and inhabited. This module decides
-- everything that is a rule: which stage is next, when the boss room triggers, when its gates
-- close, when a camp is clear, when a checkpoint is reached, what ends the run, where a body that
-- must be moved goes, what a Studio skip does, which map node is open and who earns a star.
-- WaveService only executes the actions returned here.
--
-- Pure on purpose (the lesson of the P5 reviews: the run's rules were "checked by reading only"):
-- tables, numbers and Vector3 values; no service, no Instance, no clock of its own (every time is
-- an argument) and no yield, so tools/crowd_harness loads it as it stands and mutate.py mutates
-- it. Of Vector3 it uses only what the harness shim has: new, X/Y/Z, + - * /, Magnitude, Unit.
-- The Types require is for annotations alone. CampBrain is pure too: Validate asks it where a
-- group's posts stand, so the rule exists once.
--
-- State is mutated in place by Advance, Finish and Skip; the caller keeps one per run (Begin).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Region = require(sharedFolder:WaitForChild("Region"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))
local LevelGeometry = require(script.Parent:WaitForChild("LevelGeometry"))
local CampBrain = require(script.Parent:WaitForChild("CampBrain"))

-- A floor rectangle: centre and half extents.
export type Rect = { x: number, z: number, hx: number, hz: number }
-- A camp as the run needs it: one for every camp of the layout, in its order. Points are feet,
-- on the floor. trigger, inner, entry, exit and spawns are read only of a camp that locks.
export type Zone = {
	id: string,
	-- Its index in Plan.zones, which is its index in the crowd's list of floors (L1b-1).
	floor: number,
	-- The layout camp's `locks`: the boss room (L1b-12).
	locks: boolean,
	-- The level's LevelCampConfig.name; else the name of the stage that names it; else its id.
	name: string,
	-- The layout's checkpoint, feet on the camp's floor height (nil = none).
	checkpoint: Vector3?,
	-- Bodies placed in it at the start, at the played difficulty.
	residents: number,
	-- L1b-W4-30: its residents at the played difficulty, by kind (no tent stock: Fielded adds what
	-- the tent sent; a locking camp's run adds the bodies its waves queue).
	stock: { [string]: number },
	-- L1b-W2-6: its tent's stock at the played difficulty; 0 for none.
	tentStock: number,
	floorY: number,
	rect: Rect,
	-- The floor inset by levels.closeInset: whoever is not inside it when the gates close is
	-- moved to the entry (MustEnter). Not in the contract's list; added by the lead's ruling on
	-- the close.
	inner: Rect,
	-- How thick its fence is built (LevelGeometry.FenceThickness: the layout's own fence.thickness,
	-- else levels.fenceThickness; the L2 W2 second fix round's m1). RunFloor.fence carries it.
	fence: number,
	-- The whole fenced rectangle: the floor grown by `fence`, so a root on a fence top triggers
	-- the camp as one on its floor does.
	trigger: Rect,
	-- How far above floorY a root still triggers it (StageFlow.Ceiling): a walled camp's fence
	-- top, else levels.triggerHeight. The L1c second fix round's F1 and F3: inside a 64-stud wall
	-- a double jump from cover carries a root 43 over the floor, and at 30 the top of one in the
	-- gate left the camp untriggered and cut the boom of a fighter inside (RunFloor.ceiling).
	ceiling: number,
	entry: Vector3,
	exit: Vector3,
	spawns: { Vector3 },
	-- L1b-W4-14: its region's graph, the same table on every zone of that region (nil = none).
	region: Types.RegionGraph?,
	-- L1b-W4-31: where N puts the party before this open camp, feet (nil = none, and always nil on
	-- a locking camp).
	approach: Vector3?,
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
	targetWaveSeconds: number,
	maxAlive: number,
	-- The L1c fix round's M3: the countdown from the trigger to the close (nil = levels.gateSeconds;
	-- 0 = the gates shut in the tick the camp triggers).
	gateSeconds: number?,
}
-- L1b-W2-6: a tent's stock as one group of its camp, posture "tent": kinds[k] stands on posts[k].
export type PlanTent = {
	-- The zone index (= its floor index).
	zone: number,
	def: Types.CampGroupDef,
	-- The stock in file order, filtered by minDifficulty; never scaled by countMult.
	kinds: { string },
	posts: { CampBrain.Post },
	-- The fix round's B-4: where each body steps out of the marker (LevelGeometry.TentDoor, its
	-- kind's radius clear of the wall, on the wall when Plan had no kinds), paired with posts.
	doors: { Vector3 },
	every: number,
	-- L1b-W4-28: the camp's own clock; it sends only while the camp is ahead of it.
	pace: Types.LevelTentPace,
}
export type Plan = {
	levelId: string,
	difficulty: string,
	start: Vector3,
	killY: number,
	bounds: LevelGeometry.Bounds,
	-- #zones: every camp of the layout counts toward "Camps cleared".
	camps: number,
	stages: { Stage },
	zones: { Zone },
	-- Every resident group, in the level file's order (its camps, then their groups).
	groups: { Types.CampGroupDef },
	-- One per open camp with a tent stock, in the layout's order. Their groups follow `groups`
	-- in the crowd's list.
	tents: { PlanTent },
	-- L1b-W2-5's left side at the played difficulty: what the client prewarms its pool with.
	population: number,
	-- L4 W2 (docs/prompts/l4-w2-contract.md §3.2): the bodies of each crowd kind the run may show,
	-- for the client's pool of that kind's model (RunState.prewarm): every resident (minDifficulty
	-- applied, never countMult, as they are placed), every tent's stock, and of the locking camps'
	-- waves the most any one wave fields of the kind: its groups (minDifficulty and countMult
	-- applied, for a party of one), its boss and what the boss's `summon` attacks raise (the most
	-- one call tops up to). A kind with none is absent.
	kinds: { [string]: number },
	-- L2-58: every block a body falls through (`collide` false: deep water, ice or not, the fix
	-- round's Q3) that has a landing, in the layout's order (Landing).
	waters: { Water },
}
-- L2-58: a deep water's footprint and where a body that fell through it is put back (feet).
export type Water = { rect: Rect, landing: Vector3 }
export type State = {
	stage: number,
	-- "travel" | "armed" | "gate" | "fight" | "breather" | "over"
	step: string,
	wave: number,
	firstWave: number,
	gateAt: number,
	breatherUntil: number,
	-- Camps cleared, open ones included; the stage index of the last locking one (0 = none).
	cleared: number,
	lastCleared: number,
	-- The last wave of the live camp counted by a clear or a skip: a `clear` covers the waves
	-- after it (Action.count).
	settled: number,
	-- Zone index -> its checkpoint has been reached (L1b-18); -> that camp is cleared (L1b-17).
	reached: { [number]: boolean },
	done: { [number]: boolean },
	-- The clock the live camp's gates closed at: the close is judged again for
	-- levels.closeGraceSeconds after it (StillClosing).
	closedAt: number,
	-- Who was fighting when the run's last boundary was decided, before it released those who
	-- waited: the star is theirs (EarnsStar).
	fought: { number },
	ended: string?,
	-- L1b-W4-31: the last zone N moved the party to (0 = none): N never goes back before it.
	approached: number,
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
	-- Nothing queued and no boss to place.
	spawningDone: boolean,
	-- Living bodies on the live locking camp's floor; 0 outside one.
	alive: number,
	-- Groups in rise, fight or home with a living member (CrowdService.Awake).
	awake: number,
	-- Living bodies on each zone's floor, by zone index (CrowdService.AliveOn). A body's floor is
	-- its camp's for life, wherever it stands (L1b-W4-29).
	aliveByFloor: { number },
	mergeOk: boolean,
	-- The director's breather, used by a stage that names none.
	breatherSeconds: number,
	-- "down" | "wipe" | nil
	fallen: string?,
	runCap: boolean,
}
-- kind: "gate" | "rearm" | "close" | "wave" | "clear" | "boundary" | "breather" | "open" |
-- "travel" | "drop" | "move" | "reach" | "campClear" | "approach" | "end". `stage` is the stage
-- the action is about (the run's stage for `reach`, `campClear` and `approach`, which name their
-- camp by `zone`).
export type Action = {
	kind: string,
	stage: number,
	wave: number?,
	at: number?,
	merged: boolean?,
	-- On `clear`: the waves it covers.
	count: number?,
	-- On `reach`, `campClear` and `approach`: the zone index.
	zone: number?,
	reason: string?,
	-- On `boundary`: whether those who wait in the lobby camp are let into the level now. False
	-- when the same batch ends the run: nobody is brought into a level that is about to go.
	release: boolean?,
	-- On `open`: a Studio skip passed the camp (L1b-22, "a skip pays nothing"). It still counts
	-- as cleared on the summary, but pays no clear bonus and counts no wave in anyone's stats.
	skipped: boolean?,
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
		"checkpointReach",
		"walletSendSeconds",
		"regionLockMargin",
		"doorSpare",
	},
	level = { "id", "name", "material" },
	crowd = { "regenShare", "maxAlive", "burst", "burstSpacing" },
	difficulty = { "hpScale", "damageScale", "plateScale", "countMult", "rewardMult" },
	reward = { "cash", "materials" },
	camp = { "x", "y", "z", "sx", "sz" },
	point = { "x", "z" },
	start = { "x", "y", "z" },
	tent = { "x", "y", "z", "sx", "sy", "sz", "radius" },
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
-- A spot's posture (L1b-3).
local POSTURES: { [string]: boolean } = { guard = true, patrol = true, fire = true }

local StageFlow = {}

-- Levels -------------------------------------------------------------------------------------

-- A level file as a level, taken as it stands: nil when it lacks stages, difficulties or a crowd
-- block; its `camps` are {} when it names none. (Ruling 27's mission branch went with the Raider
-- Arena in L4 W1b: no level borrows a mission's crowd block.)
function StageFlow.Resolve(file: Types.LevelFile, runCapSeconds: number): Types.LevelConfig?
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
		material = file.material or "",
		targetMinutes = file.targetMinutes or 0,
		-- A level that names no cap of its own runs under the director's.
		runCapSeconds = if ownCap ~= nil and ownCap > 0 then ownCap else runCapSeconds,
		difficulties = difficulties,
		crowd = crowd,
		stages = stages,
		camps = file.camps or {},
		secrets = file.secrets,
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

-- The camp of the layout with this id, and its index in the layout's list (its floor index).
local function campIndex(camps: { Types.LevelCamp }, id: string?): (number, Types.LevelCamp?)
	for index, camp in camps do
		if camp.id == id then
			return index, camp
		end
	end
	return 0, nil
end

local function spotOf(camp: Types.LevelCamp, id: string?): Types.LevelSpot?
	local spots: { Types.LevelSpot } = camp.spots or {}
	for _, spot in spots do
		if spot.id == id then
			return spot
		end
	end
	return nil
end

-- L1b-10: the units of a resident group that are fielded at `rank`, in the file's order, and
-- their bodies in all. A unit that names no minDifficulty is fielded, and one whose
-- minDifficulty ranks at or under `rank` (one that is no difficulty fields nothing, as in
-- Combat.CampWave). countMult and the party's size are never read: residents are placed once.
local function fieldedUnits(
	units: { Types.MissionCrowdGroup },
	rank: number,
	ranks: { [string]: number }?
): ({ Types.CampUnit }, number)
	local fielded: { Types.CampUnit } = {}
	local bodies = 0
	for _, unit in units do
		local needs = unit.minDifficulty
		local needsRank = if needs ~= nil and ranks ~= nil then ranks[needs] else nil
		if needs ~= nil and (needsRank == nil or needsRank > rank) then
			continue
		end
		table.insert(fielded, { kind = unit.kind, count = unit.count })
		bodies += unit.count
	end
	return fielded, bodies
end

-- Adds every unit's count to `stock`, by its kind.
local function addUnits(stock: { [string]: number }, units: { Types.CampUnit }): ()
	for _, unit in units do
		stock[unit.kind] = (stock[unit.kind] or 0) + unit.count
	end
end

-- One CampGroupDef per resident group at `rank`, in the level file's order (its camps, then
-- their groups): what Plan places, and what Validate checks the posts of, so the two can never
-- build a group differently. A camp the layout lacks, a spot its camp lacks and a group whose
-- units all drop are left out. Also returns each layout camp's residents by its id, and its
-- residents by kind (L1b-W2-21's stock). `cells`: each region camp's region cells, by its id
-- (L1b-W4-14), put on its groups; nil = none has a region.
local function groupsOf(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	rank: number,
	ranks: { [string]: number }?,
	cells: { [string]: { Types.CampRect } }?
): ({ Types.CampGroupDef }, { [string]: number }, {
	[string]: { [string]: number },
})
	local groups: { Types.CampGroupDef } = {}
	local residents: { [string]: number } = {}
	local stocks: { [string]: { [string]: number } } = {}
	local configs: { Types.LevelCampConfig } = level.camps or {}
	for _, config in configs do
		local floor, camp = campIndex(layout.camps, config.id)
		if camp == nil then
			continue
		end
		local residentGroups: { Types.LevelResidentGroup } = config.residents or {}
		for _, group in residentGroups do
			local spot = spotOf(camp, group.spot)
			local units, bodies = fieldedUnits(group.units or {}, rank, ranks)
			if spot == nil or #units == 0 then
				continue
			end
			local points: { Vector3 } = {}
			for _, point in spot.points do
				table.insert(points, Vector3.new(point.x, camp.y, point.z))
			end
			table.insert(groups, {
				id = `{camp.id}.{spot.id}`,
				camp = camp.id,
				floor = floor,
				floorY = camp.y,
				rect = { x = camp.x, z = camp.z, hx = camp.sx / 2, hz = camp.sz / 2 },
				posture = spot.posture :: Types.CampPosture,
				points = points,
				yaw = math.rad(spot.facing or 0),
				radius = spot.radius or 0,
				-- L1b-13: a boss room's residents sleep and evade until its close.
				held = camp.locks == true,
				units = units,
				region = if cells ~= nil then cells[camp.id] else nil,
			})
			residents[camp.id] = (residents[camp.id] or 0) + bodies
			local stock = stocks[camp.id] or {}
			stocks[camp.id] = stock
			addUnits(stock, units)
		end
	end
	return groups, residents, stocks
end

-- L1b-W2-6: one PlanTent per open camp of the layout whose camps entry carries a tent stock and
-- whose layout camp carries a `tent` block, in the layout's order, at `rank`: units filtered by
-- minDifficulty as residents are, never scaled by countMult or the party, expanded in file order.
-- A tent whose units all drop is left out; so is a locking camp's (its tent is a marker only:
-- Validate refuses a stock there). Also returns each camp's tent stock by its id. CampBrain.Posts
-- is asked with pcall: Validate reads a throw as a problem, Plan as no posts. `cells` as groupsOf.
local function tentsOf(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	rank: number,
	ranks: { [string]: number }?,
	crowdKinds: { [string]: Types.CrowdKindDef }?,
	cells: { [string]: { Types.CampRect } }?
): ({ PlanTent }, { [string]: number })
	local tents: { PlanTent } = {}
	local stocks: { [string]: number } = {}
	local configs: { Types.LevelCampConfig } = level.camps or {}
	for floor, camp in layout.camps do
		local config: Types.LevelCampConfig? = nil
		for _, entry in configs do
			if entry.id == camp.id then
				config = entry
				break
			end
		end
		local tent = if config ~= nil then config.tent else nil
		local block = camp.tent
		if tent == nil or block == nil or camp.locks == true then
			continue
		end
		local units = fieldedUnits(tent.units or {}, rank, ranks)
		local kinds: { string } = {}
		for _, unit in units do
			for _ = 1, unit.count do
				table.insert(kinds, unit.kind)
			end
		end
		if #kinds == 0 then
			continue
		end
		local def: Types.CampGroupDef = {
			id = `{camp.id}.tent`,
			camp = camp.id,
			floor = floor,
			floorY = camp.y,
			rect = { x = camp.x, z = camp.z, hx = camp.sx / 2, hz = camp.sz / 2 },
			posture = "tent",
			points = { Vector3.new(block.x, camp.y, block.z) },
			yaw = 0,
			radius = block.radius,
			held = false,
			units = units,
			region = if cells ~= nil then cells[camp.id] else nil,
		}
		local placed, posts = pcall(CampBrain.Posts, def, #kinds)
		local ring: { CampBrain.Post } = if placed then posts else {}
		local box = LevelGeometry.TentBox(camp)
		local doors: { Vector3 } = {}
		for index, post in ring do
			local body = if crowdKinds ~= nil then crowdKinds[kinds[index]] else nil
			local clear = if body ~= nil then body.radius else 0
			if box == nil then
				table.insert(doors, post.at)
			else
				local x, z = LevelGeometry.TentDoor(box, post.at.X, post.at.Z, clear)
				table.insert(doors, Vector3.new(x, post.at.Y, z))
			end
		end
		table.insert(tents, {
			zone = floor,
			def = def,
			kinds = kinds,
			posts = ring,
			doors = doors,
			every = tent.every,
			pace = tent.pace,
		})
		stocks[camp.id] = #kinds
	end
	return tents, stocks
end

-- L1b-W2-5: the bodies a boss raises by itself. Over the bosses of the camp stages (only a camp
-- that locks is a stage), the largest 1 + the largest `count` of its kind's "summon" attacks; a
-- kind `kinds` lacks (or no `kinds`) counts 1, the boss alone. 0 when no stage has a boss.
function StageFlow.BossReserve(
	level: Types.LevelConfig,
	kinds: { [string]: Types.CrowdKindDef }?
): number
	local reserve = 0
	local stages: any = level.stages
	if type(stages) ~= "table" then
		return reserve
	end
	for _, stage in stages do
		local waves = if stage.kind == KIND_CAMP then stage.waves else nil
		if type(waves) ~= "table" then
			continue
		end
		for _, wave in waves do
			local boss = wave.boss
			if type(boss) ~= "table" then
				continue
			end
			local def = if kinds ~= nil and type(boss.kind) == "string"
				then kinds[boss.kind]
				else nil
			local calls = 0
			local attacks: { Types.CrowdAttackDef } = if def ~= nil and def.attacks ~= nil
				then def.attacks
				else {}
			for _, attack in attacks do
				if attack.shape == "summon" then
					calls = math.max(calls, attack.count or 0)
				end
			end
			reserve = math.max(reserve, 1 + calls)
		end
	end
	return reserve
end

-- L1b-W2-5's left side: every resident, every tent's stock (`tents`, the sum), the most room a
-- boss room's cap leaves over its own residents (`caps`: each locking stage's cap, by its camp's
-- id), and the boss reserve.
local function populationOf(
	residents: { [string]: number },
	tents: number,
	caps: { [string]: number },
	reserve: number
): number
	local placed = 0
	for _, bodies in residents do
		placed += bodies
	end
	local room = 0
	for id, cap in caps do
		room = math.max(room, cap - (residents[id] or 0))
	end
	return placed + tents + room + reserve
end

-- L4 W2 (§3.2): Plan's `kinds` (its type says what is counted). `residentStocks` is groupsOf's
-- third answer, `tents` tentsOf's first; `countMult` is the played difficulty's.
local function kindsOf(
	level: Types.LevelConfig,
	residentStocks: { [string]: { [string]: number } },
	tents: { PlanTent },
	rank: number,
	ranks: { [string]: number }?,
	countMult: number,
	kinds: { [string]: Types.CrowdKindDef }?
): { [string]: number }
	local counts: { [string]: number } = {}
	for _, stock in residentStocks do
		for kind, count in stock do
			counts[kind] = (counts[kind] or 0) + count
		end
	end
	for _, tent in tents do
		for _, kind in tent.kinds do
			counts[kind] = (counts[kind] or 0) + 1
		end
	end
	-- One wave's bodies at a time: a locking camp's waves follow each other.
	local most: { [string]: number } = {}
	for _, stage in level.stages do
		local waves: { Types.MissionCrowdWave } = if stage.kind == KIND_CAMP
			then stage.waves or {}
			else {}
		for _, wave in waves do
			local here: { [string]: number } = {}
			for _, unit in fieldedUnits(wave.groups or {}, rank, ranks) do
				here[unit.kind] = (here[unit.kind] or 0)
					+ math.max(math.round(unit.count * countMult), 0)
			end
			local boss = wave.boss
			if boss ~= nil and type(boss.kind) == "string" then
				here[boss.kind] = (here[boss.kind] or 0) + 1
				local def = if kinds ~= nil then kinds[boss.kind] else nil
				local attacks: { Types.CrowdAttackDef } = if def ~= nil
						and def.attacks ~= nil
					then def.attacks
					else {}
				-- A call tops its living summons up to its count, so one kind's calls never add up.
				local calls: { [string]: number } = {}
				for _, attack in attacks do
					local raised = attack.summon
					if attack.shape == "summon" and raised ~= nil then
						calls[raised] = math.max(calls[raised] or 0, attack.count or 0)
					end
				end
				for kind, count in calls do
					here[kind] = (here[kind] or 0) + count
				end
			end
			for kind, count in here do
				most[kind] = math.max(most[kind] or 0, count)
			end
		end
	end
	for kind, count in most do
		counts[kind] = (counts[kind] or 0) + count
	end
	for kind, count in counts do
		if count <= 0 then
			counts[kind] = nil
		end
	end
	return counts
end

local function sumOf(byId: { [string]: number }): number
	local total = 0
	for _, value in byId do
		total += value
	end
	return total
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Regions ------------------------------------------------------------------------------------

-- L1b-W4-14: a region's cells, in their order: the floors of its camps in the layout's camp order,
-- then its road cells in file order. Read after Validate (Plan) or once its shapes are checked.
local function regionCells(
	region: Types.LevelRegion,
	camps: { Types.LevelCamp }
): { Types.CampRect }
	local cells: { Types.CampRect } = {}
	for _, camp in camps do
		if table.find(region.camps, camp.id) ~= nil then
			table.insert(cells, { x = camp.x, z = camp.z, hx = camp.sx / 2, hz = camp.sz / 2 })
		end
	end
	local roads: { Types.LevelRegionCell } = region.cells or {}
	for _, cell in roads do
		table.insert(cells, { x = cell.x, z = cell.z, hx = cell.sx / 2, hz = cell.sz / 2 })
	end
	return cells
end

-- L1b-W4-15, -16: the widest body and the longest reach among the kinds the camps `ids` field, as
-- residents or from their tents, at the level's highest difficulty (fielding only grows with the
-- rank, so that is every difficulty's). A kind `kinds` lacks counts 0. Walks data Validate may not
-- have passed yet, so it never throws on a broken entry.
local function regionReach(
	level: Types.LevelConfig,
	ids: { string },
	ranks: { [string]: number }?,
	kinds: { [string]: Types.CrowdKindDef }?
): (number, number)
	local top = 0
	local difficulties: any = level.difficulties
	if ranks ~= nil and type(difficulties) == "table" then
		for name in difficulties do
			top = math.max(top, ranks[name] or 0)
		end
	end
	local widest, longest = 0, 0
	local function take(units: any): ()
		if type(units) ~= "table" then
			return
		end
		for _, unit in units do
			if type(unit) ~= "table" or type(unit.kind) ~= "string" then
				continue
			end
			local needs = unit.minDifficulty
			local needsRank = if needs ~= nil and ranks ~= nil then ranks[needs] else nil
			if needs ~= nil and (needsRank == nil or needsRank > top) then
				continue
			end
			local def = if kinds ~= nil then kinds[unit.kind] else nil
			if def ~= nil then
				widest = math.max(widest, def.radius or 0)
				longest = math.max(longest, StageFlow.LongestReach(def))
			end
		end
	end
	local configs: any = level.camps
	if type(configs) ~= "table" then
		return widest, longest
	end
	for _, config in configs do
		if type(config) ~= "table" or table.find(ids, config.id) == nil then
			continue
		end
		if type(config.residents) == "table" then
			for _, group in config.residents do
				if type(group) == "table" then
					take(group.units)
				end
			end
		end
		if type(config.tent) == "table" then
			take(config.tent.units)
		end
	end
	return widest, longest
end

-- The flat gap between two rectangles: 0 when they touch or overlap.
local function rectGap(a: Types.CampRect, b: Types.CampRect): number
	local dx = math.max(math.abs(a.x - b.x) - a.hx - b.hx, 0)
	local dz = math.max(math.abs(a.z - b.z) - a.hz - b.hz, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- L1b-W4-14 to -16's lines of Validate, into `problem`: the shape of `layout.regions`, its camps
-- and road cells, then (once those are sound) Region.Problems with the door the region's widest
-- body needs, and the lock clearance from every locking floor.
local function regionProblems(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	camps: { Types.LevelCamp },
	kinds: { [string]: Types.CrowdKindDef },
	ranks: { [string]: number },
	rules: Types.CombatLevelsConfig,
	problem: (text: string) -> ()
): ()
	local regions: any = layout.regions
	if regions == nil then
		return
	elseif type(regions) ~= "table" then
		problem("regions is not a list")
		return
	end
	local numbers: any = rules
	local spare = if isFinite(numbers.doorSpare) then numbers.doorSpare else 0
	local margin = if isFinite(numbers.regionLockMargin) then numbers.regionLockMargin else 0
	local ids: { [string]: boolean } = {}
	local regionOf: { [string]: string } = {}
	for index, region in regions do
		local id = if type(region) == "table" then region.id else nil
		local here = `region {index}`
		if type(id) ~= "string" or id == "" then
			problem(`{here} has no id`)
		elseif ids[id] then
			problem(`the region id "{id}" is used twice`)
		else
			ids[id] = true
			here = `region "{id}"`
		end
		if type(region) ~= "table" then
			continue
		end
		local sound = true
		local y = region.y
		if not isFinite(y) then
			problem(`{here}: its y is {tostring(y)}, not a finite height`)
			sound = false
		end
		local members: any = region.camps
		if type(members) ~= "table" or #members == 0 then
			problem(`{here} has no camps`)
			continue
		end
		for _, campId in members do
			local _floor, camp = campIndex(camps, if type(campId) == "string" then campId else nil)
			if camp == nil then
				problem(`{here} names camp "{tostring(campId)}", which the layout lacks`)
				sound = false
				continue
			end
			local other = regionOf[camp.id]
			if other ~= nil then
				problem(`camp {camp.id} is in two regions ({other} and {here})`)
			end
			regionOf[camp.id] = here
			if camp.locks == true then
				problem(`{here}: camp {camp.id} locks, and a boss room is in no region`)
			end
			local shaped = isFinite(camp.x)
				and isFinite(camp.y)
				and isFinite(camp.z)
				and isFinite(camp.sx)
				and isFinite(camp.sz)
				and camp.sx > 0
				and camp.sz > 0
			if not shaped then
				problem(`{here}: camp {camp.id} needs a finite x, y, z and a size above 0`)
				sound = false
			elseif isFinite(y) and math.abs(camp.y - y) > 1e-6 then
				problem(`{here}: camp {camp.id}'s floor is at y {camp.y}, not the region's {y}`)
			end
		end
		local roads: any = region.cells
		if roads == nil then
			roads = {}
		elseif type(roads) ~= "table" then
			problem(`{here}: cells is not a list`)
			continue
		end
		local names: { string } = {}
		for _, camp in camps do
			if table.find(members, camp.id) ~= nil then
				table.insert(names, `camp {camp.id}'s floor`)
			end
		end
		for cellIndex, cell in roads do
			local cellId = if type(cell) == "table" then cell.id else nil
			local at = `{here} cell {cellIndex}`
			if type(cellId) ~= "string" or cellId == "" then
				problem(`{at} has no id`)
			else
				at = `{here} cell "{cellId}"`
			end
			table.insert(names, `cell {tostring(cellId or cellIndex)}`)
			if
				type(cell) ~= "table"
				or not isFinite(cell.x)
				or not isFinite(cell.z)
				or not isFinite(cell.sx)
				or not isFinite(cell.sz)
			then
				problem(`{at} needs a finite x, z, sx and sz`)
				sound = false
			elseif not (cell.sx > 0 and cell.sz > 0) then
				problem(`{at}: its size must be above 0`)
				sound = false
			elseif
				math.abs(cell.x) + cell.sx / 2 > WIRE_REACH
				or math.abs(cell.z) + cell.sz / 2 > WIRE_REACH
			then
				problem(`{at} lies beyond {WIRE_REACH} studs of the world origin`)
			end
		end
		if not sound then
			-- Nothing more can be said of cells whose numbers are not there.
			continue
		end
		local cells = regionCells(region, camps)
		local widest, longest = regionReach(level, members, ranks, kinds)
		for _, line in Region.Problems(cells, 2 * widest + spare) do
			problem(`{here}: {line}`)
		end
		-- L1b-W4-16: no body of the region reaches into a boss room from anywhere it may stand.
		local needed = longest + margin
		for _, camp in camps do
			if camp.locks ~= true or not (isFinite(camp.sx) and isFinite(camp.sz)) then
				continue
			end
			local floor: Types.CampRect =
				{ x = camp.x, z = camp.z, hx = camp.sx / 2, hz = camp.sz / 2 }
			for cellIndex, cell in cells do
				local gap = rectGap(cell, floor)
				if gap < needed - 1e-6 then
					problem(
						`{here}: {names[cellIndex]} is {math.round(gap * 100) / 100} studs from locking camp {camp.id}'s floor, under its longest reach {longest} + regionLockMargin {margin} = {needed}`
					)
				end
			end
		end
	end
end

-- L2-13: the level file's `secrets` block against the layout's secrets. Every layout secret has
-- an entry with a name; an entry's valor and materials, when given, are whole numbers >= 0, and
-- its family and its key (L4 W2) short strings. Which secrets may pay at all (a reward only behind
-- a sold key) is check_levels.py's rule (L2-18e), not a refusal here.
local function secretProblems(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	problem: (string) -> ()
): ()
	local entries: any = level.secrets
	if entries ~= nil and type(entries) ~= "table" then
		problem("secrets is not a table")
		entries = nil
	end
	local list: any = layout.secrets
	if type(list) ~= "table" then
		return
	end
	for index, secret: any in list do
		local id = if type(secret) == "table" then secret.id else nil
		if type(id) ~= "string" then
			problem(`layout secret {index} has no id`)
			continue
		end
		local entry: any = if entries ~= nil then entries[id] else nil
		if type(entry) ~= "table" or type(entry.name) ~= "string" or entry.name == "" then
			problem(`the secret "{id}" has no secrets entry with a name`)
			continue
		end
		for _, key in { "valor", "materials" } do
			local amount = entry[key]
			if amount ~= nil and not (isFinite(amount) and amount >= 0 and amount % 1 == 0) then
				problem(
					`secrets.{id}.{key} is {tostring(amount)}, not a whole number of at least 0`
				)
			end
		end
		-- The family id cap is the remotes' (Unlocks, its one home), counted in bytes; the Python
		-- mirror counts bytes too.
		local family = entry.family
		if
			family ~= nil
			and (type(family) ~= "string" or family == "" or #family > Unlocks.MAX_FAMILY_LENGTH)
		then
			problem(`secrets.{id}.family is {tostring(family)}, not a family id`)
		end
		-- L4 W2 (§0): a key id is held to the family id's cap, in bytes, as the mirror counts.
		local key = entry.key
		if
			key ~= nil and (type(key) ~= "string" or key == "" or #key > Unlocks.MAX_FAMILY_LENGTH)
		then
			problem(`secrets.{id}.key is {tostring(key)}, not a key id`)
		end
	end
end

-- L3-17: each difficulty's `firstClear`, when given, is a table. Its `family` is a family id of at
-- most Unlocks.MAX_FAMILY_LENGTH bytes and, when the weapons are given, one of theirs that is no
-- starter (a starter is everyone's, so the grant would give nothing); its `valor` is a whole
-- number of at least 0. In difficulty-name order, so the lines come out the same every time.
local function firstClearProblems(
	level: Types.LevelConfig,
	weapons: { [string]: Types.RangeWeaponDef }?,
	starters: { [string]: boolean }?,
	problem: (string) -> ()
): ()
	local difficulties: any = level.difficulties
	if type(difficulties) ~= "table" then
		return
	end
	local names: { string } = {}
	for name in difficulties do
		table.insert(names, tostring(name))
	end
	table.sort(names)
	for _, name in names do
		local scales: any = difficulties[name]
		local reward: any = if type(scales) == "table" then scales.firstClear else nil
		if reward == nil then
			continue
		end
		local where = `difficulties.{name}.firstClear`
		if type(reward) ~= "table" then
			problem(`{where} is not a table`)
			continue
		end
		local id = reward.family
		if id ~= nil then
			if type(id) ~= "string" or id == "" or #id > Unlocks.MAX_FAMILY_LENGTH then
				problem(`{where}.family is {tostring(id)}, not a family id`)
			elseif weapons ~= nil and weapons[id] == nil then
				problem(`{where}.family names "{id}", which is no weapons family`)
			elseif starters ~= nil and starters[id] == true then
				problem(`{where}.family names the starter "{id}", which everyone owns`)
			end
		end
		local valor = reward.valor
		if valor ~= nil and not (isFinite(valor) and valor >= 0 and valor % 1 == 0) then
			problem(`{where}.valor is {tostring(valor)}, not a whole number of at least 0`)
		end
	end
end

-- L2-34, L2-36: the layout's reactive blocks and shortcuts. A block's `react` is "fire" or "ice";
-- a fire block collides (a block nothing stops would be burnt by a stream that passes through
-- it), an ice block (L2-52, deep water) does not and opens nothing, and two ice blocks' footprints
-- may touch but not overlap (the fix round's s-s2: their frozen tops would lie at one height on
-- the same ground). Only a block that does not collide (deep water, ice or not: the fix round's
-- Q3) has a `landing`, three finite numbers (L2-58). A block's `opens` names an entry of
-- `layout.shortcuts`. `shortcuts` is a list whose entries have a unique id of at most
-- Unlocks.MAX_ID_LENGTH bytes, finite numbers and sizes above 0.
local function reactProblems(layout: Types.LevelLayout, problem: (string) -> ()): ()
	local ids: { [string]: boolean } = {}
	local shortcuts: any = layout.shortcuts
	if shortcuts ~= nil and type(shortcuts) ~= "table" then
		problem("shortcuts is not a list")
		shortcuts = nil
	end
	for index, entry: any in shortcuts or {} do
		local id = if type(entry) == "table" then entry.id else nil
		if type(id) ~= "string" or id == "" or #id > Unlocks.MAX_ID_LENGTH then
			problem(`shortcut {index} has no id of at most {Unlocks.MAX_ID_LENGTH} bytes`)
			continue
		end
		if ids[id] then
			problem(`the shortcut id "{id}" is used twice`)
		end
		ids[id] = true
		for _, key in { "x", "y", "z", "sx", "sy", "sz" } do
			if not isFinite(entry[key]) then
				problem(`shortcut "{id}": {key} is {tostring(entry[key])}, not a number`)
			end
		end
		-- Fix round s-m3: a box no root can stand in would never be found, and SecretFlow drops a
		-- negative size without a word, so a typo is refused here instead.
		for _, key in { "sx", "sy", "sz" } do
			if isFinite(entry[key]) and entry[key] <= 0 then
				problem(`shortcut "{id}": {key} is {entry[key]}, not a size above 0`)
			end
		end
	end
	local blocks: any = layout.blocks
	if type(blocks) ~= "table" then
		return
	end
	for index, block: any in blocks do
		if type(block) ~= "table" then
			continue
		end
		local where = `block {if type(block.name) == "string" then block.name else index}`
		local react = block.react
		local opens = block.opens
		if react == "ice" then
			-- L2-52: deep water a body falls through until it freezes; it is the way to a key, so
			-- it opens nothing.
			if block.collide ~= false then
				problem(`{where} is ice and collides`)
			end
			if opens ~= nil then
				problem(`{where} is ice and opens {tostring(opens)}`)
			end
		elseif react ~= nil then
			if react ~= "fire" then
				problem(`{where}: react is {tostring(react)}, neither "fire" nor "ice"`)
			end
			if block.collide == false then
				problem(`{where} reacts and does not collide`)
			end
		end
		if opens ~= nil and (type(opens) ~= "string" or not ids[opens]) then
			problem(`{where} opens {tostring(opens)}, which names no shortcut`)
		end
		-- L2-58: a landing is where a fall through deep water comes back to, so only a block a
		-- body falls through has one (the fix round's Q3: CreekUp too), and it is a point.
		local landing = block.landing
		if landing ~= nil then
			if block.collide ~= false then
				problem(`{where} has a landing and collides`)
			end
			if type(landing) ~= "table" then
				problem(`{where}: landing is {tostring(landing)}, not a point`)
			else
				for _, key in { "x", "y", "z" } do
					if not isFinite(landing[key]) then
						problem(`{where}: landing.{key} is {tostring(landing[key])}, not a number`)
					end
				end
			end
		end
	end
	-- The fix round's s-s2: each pair of ice blocks once, in the layout's order; a block whose
	-- footprint is not finite numbers is LevelGeometry's to refuse, not judged here.
	local ice: { { block: any, where: string } } = {}
	for index, block: any in blocks do
		if type(block) ~= "table" or block.react ~= "ice" then
			continue
		end
		if
			not (
				isFinite(block.x)
				and isFinite(block.z)
				and isFinite(block.sx)
				and isFinite(block.sz)
			)
		then
			continue
		end
		local where = `block {if type(block.name) == "string" then block.name else index}`
		for _, other in ice do
			if LevelGeometry.Overlap(other.block, block) then
				problem(`{other.where} and {where} are ice and overlap`)
			end
		end
		table.insert(ice, { block = block, where = where })
	end
end

-- Validate's L1b lines, one per problem, into `problems`: the numbers the run reads, which camps
-- lock and which stage names them, the level's `camps` entries, every spot of every layout camp,
-- every resident group and its units; then, once all of that is sound, every group's posts on
-- its floor, a boss room's residents under its cap, and the population gate at each difficulty.
local function campProblems(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	camps: { Types.LevelCamp },
	stages: { Types.LevelStage },
	kinds: { [string]: Types.CrowdKindDef },
	ranks: { [string]: number },
	rules: Types.CombatLevelsConfig,
	crowdMax: number,
	problems: { string },
	problem: (text: string) -> (),
	checkKind: (where: string, kind: string) -> Types.CrowdKindDef?
): ()
	local numbers: any = rules
	for _, key in { "checkpointReach", "walletSendSeconds" } do
		local value = numbers[key]
		if type(value) == "number" and not (value > 0) then
			problem(`levels.{key} is {value}, not above 0`)
		end
	end
	local crowd: any = level.crowd
	local bonus = if type(crowd) == "table" then crowd.clearBonus else nil
	-- L1b-W2-21: a share of what the camp's whole stock pays.
	if
		bonus ~= nil
		and (
			type(bonus) ~= "table"
			or not isFinite(bonus.share)
			or bonus.share < 0
			or bonus.share > 1
		)
	then
		problem("crowd.clearBonus needs a share from 0 to 1")
	end

	-- L1b-12: a stage names only a camp that locks, and every camp that locks is named once.
	local named: { [string]: number } = {}
	for index, stage in stages do
		local _floor, camp = campIndex(camps, if stage.kind == KIND_CAMP then stage.zone else nil)
		if camp ~= nil then
			named[camp.id] = (named[camp.id] or 0) + 1
			if camp.locks ~= true then
				problem(
					`stage {index} names camp {camp.id}, which does not lock: only a boss room is a stage`
				)
			end
		end
	end
	for _, camp in camps do
		local times = named[camp.id] or 0
		if camp.locks == true and times ~= 1 then
			problem(`camp {camp.id} locks and is named by {times} stages, not one`)
		end
	end

	for _, camp in camps do
		-- L1b-W4-31: N's stop, before an open camp only, where the crowd's wire reaches.
		local approach: any = camp.approach
		if approach ~= nil then
			if
				type(approach) ~= "table"
				or not isFinite(approach.x)
				or not isFinite(approach.y)
				or not isFinite(approach.z)
			then
				problem(`camp {camp.id}: its approach needs a finite x, y and z`)
			elseif
				math.abs(approach.x) > WIRE_REACH
				or math.abs(approach.y) > WIRE_REACH
				or math.abs(approach.z) > WIRE_REACH
			then
				problem(
					`camp {camp.id}: its approach lies beyond {WIRE_REACH} studs of the world origin`
				)
			end
			if camp.locks == true then
				problem(`camp {camp.id} locks, and a boss room has no approach`)
			end
		end
		-- L1b-W2-6: a tent's marker and ring (a boss room's is a marker only, checked the same).
		local block: any = camp.tent
		if block ~= nil then
			local broken = type(block) ~= "table"
			for _, key in NEEDED.tent do
				broken = broken or not isFinite(block[key])
			end
			if broken then
				problem(`camp {camp.id}: its tent needs a finite {table.concat(NEEDED.tent, ", ")}`)
			elseif not (block.sx > 0 and block.sy > 0 and block.sz > 0 and block.radius > 0) then
				problem(`camp {camp.id}: its tent's size and radius must be above 0`)
			elseif not onFloor(camp, block.x, block.z, 0) then
				problem(`camp {camp.id}: its tent's centre lies off the floor`)
			end
		end
		local spots: any = camp.spots
		if spots == nil then
			continue
		elseif type(spots) ~= "table" then
			problem(`camp {camp.id}: spots is not a list`)
			continue
		end
		local seen: { [string]: boolean } = {}
		for index, spot in spots do
			local here = `camp {camp.id} spot {index}`
			local id = spot.id
			if type(id) ~= "string" or id == "" then
				problem(`{here} has no id`)
			elseif seen[id] then
				problem(`camp {camp.id}: the spot id "{id}" is used twice`)
			else
				seen[id] = true
				here = `camp {camp.id} spot "{id}"`
			end
			local posture = spot.posture
			if type(posture) ~= "string" or not POSTURES[posture] then
				problem(`{here}: posture "{tostring(posture)}" is not guard, patrol or fire`)
			end
			local points = spot.points
			if type(points) ~= "table" or #points == 0 then
				problem(`{here} has no points`)
				points = {}
			end
			for pointIndex, point in points do
				local missing: { string } = {}
				need(missing, point, `points[{pointIndex}].`, NEEDED.point, "number")
				if #missing > 0 then
					problem(`{here} lacks {table.concat(missing, ", ")}`)
				end
			end
			if posture == "guard" and type(spot.facing) ~= "number" then
				problem(`{here}: a guard spot has no facing`)
			elseif posture == "patrol" and #points < 2 then
				problem(`{here}: a patrol of {#points} points (it needs 2 or more)`)
			elseif posture == "fire" and #points ~= 1 then
				problem(`{here}: a fire of {#points} points (it has one, its centre)`)
			end
			if posture == "fire" and not (type(spot.radius) == "number" and spot.radius > 0) then
				problem(`{here}: a fire's radius is {tostring(spot.radius)}, not above 0`)
			end
		end
	end

	local configs: any = level.camps
	if configs == nil then
		configs = {}
	elseif type(configs) ~= "table" then
		problem("camps is not a list")
		configs = {}
	end
	-- A resident's or a tent's units, broken in any way a unit can be.
	local function unitProblems(at: string, units: any): ()
		if type(units) ~= "table" or #units == 0 then
			problem(`{at} has no units`)
			return
		end
		for unitIndex, unit in units do
			local which = `{at} unit {unitIndex}`
			if type(unit.kind) ~= "string" then
				problem(`{which} has no kind`)
			else
				checkKind(which, unit.kind)
			end
			if not isCap(unit.count) then
				problem(`{which}: count {tostring(unit.count)} is not a whole number of at least 1`)
			end
			local needs = unit.minDifficulty
			if needs ~= nil and ranks[needs] == nil then
				problem(`{which}: minDifficulty "{tostring(needs)}" is no difficulty`)
			end
		end
	end
	local entries: { [string]: boolean } = {}
	for index, config in configs do
		local id = config.id
		local _floor, camp = campIndex(camps, if type(id) == "string" then id else nil)
		local here = `camps entry {index} ("{tostring(id)}")`
		if camp == nil then
			problem(`{here} names a camp the layout lacks`)
		elseif entries[id] then
			problem(`two camps entries for camp {id}`)
		end
		if type(id) == "string" then
			entries[id] = true
		end
		if type(config.name) ~= "string" or config.name == "" then
			problem(`{here} has no name`)
		end
		-- L1b-W2-6: a tent's stock, on an open camp whose layout camp has a tent block.
		local tent = config.tent
		if tent ~= nil then
			if type(tent) ~= "table" then
				problem(`{here}: its tent is not a table`)
			else
				if not (isFinite(tent.every) and tent.every > 0) then
					problem(
						`{here}: its tent's every is {tostring(tent.every)}, not a time above 0`
					)
				end
				unitProblems(`{here} tent`, tent.units)
				-- L1b-W4-28: the camp's own clock, which decides whether its tent sends at all.
				local pace = tent.pace
				if type(pace) ~= "table" then
					problem(`{here}: its tent has no pace`)
				else
					if not (isFinite(pace.seconds) and pace.seconds > 0) then
						problem(
							`{here}: its tent's pace.seconds is {tostring(pace.seconds)}, not a time above 0`
						)
					end
					if not (isFinite(pace.lead) and pace.lead >= 0 and pace.lead <= 1) then
						problem(
							`{here}: its tent's pace.lead is {tostring(pace.lead)}, not from 0 to 1`
						)
					end
				end
				if camp ~= nil and camp.locks == true then
					problem(`{here}: camp {camp.id} locks, and a boss room's tent has no stock`)
				elseif camp ~= nil and camp.tent == nil then
					problem(`{here} has a tent stock, and camp {camp.id} has no tent block`)
				end
			end
		end
		local residents = config.residents
		if type(residents) ~= "table" then
			problem(`{here} has no residents list`)
			continue
		end
		for groupIndex, group in residents do
			local at = `{here} resident group {groupIndex}`
			if camp ~= nil and spotOf(camp, group.spot) == nil then
				problem(`{at} names the spot "{tostring(group.spot)}", which camp {camp.id} lacks`)
			end
			unitProblems(at, group.units)
		end
	end
	if #problems > 0 then
		-- Nothing more can be said of groups whose spots, units, camps or difficulties are not
		-- there: what follows reads all of them.
		return
	end

	-- The posts at every difficulty the level offers, the highest first: CampBrain.Posts spaces n
	-- posts evenly round a fire's or a tent's ring, so a difficulty that fields fewer bodies stands
	-- them at other bearings than the highest one does (the fix round's B-2). A group is told of
	-- once, at the highest difficulty it fails at.
	local levelRanks: { number } = {}
	for name in level.difficulties do
		local rank = ranks[name] or 0
		if table.find(levelRanks, rank) == nil then
			table.insert(levelRanks, rank)
		end
	end
	table.sort(levelRanks, function(a: number, b: number): boolean
		return a > b
	end)
	local told: { [string]: boolean } = {}
	for _, rank in levelRanks do
		for _, def in (groupsOf(level, layout, rank, ranks)) do
			if told[def.id] then
				continue
			end
			local members = 0
			local widest = 0
			for _, unit in def.units do
				members += unit.count
				local kind = kinds[unit.kind]
				widest = math.max(widest, if kind ~= nil then kind.radius else 0)
			end
			if def.posture == "guard" and members > #def.points then
				told[def.id] = true
				problem(`group {def.id} holds {members} guards and has {#def.points} posts`)
				continue
			end
			local _floor, camp = campIndex(camps, def.camp)
			local placed, posts = pcall(CampBrain.Posts, def, members)
			if not placed then
				told[def.id] = true
				problem(`group {def.id}: its posts could not be placed ({tostring(posts)})`)
				continue
			end
			for index, post in posts :: { CampBrain.Post } do
				if camp ~= nil and not onFloor(camp, post.at.X, post.at.Z, widest) then
					told[def.id] = true
					problem(
						`group {def.id}: post {index} lies off its floor less {widest}, its widest radius`
					)
					break
				end
			end
		end
		for _, tent in (tentsOf(level, layout, rank, ranks)) do
			local id = tent.def.id
			if told[id] then
				continue
			end
			local widest = 0
			for _, kind in tent.kinds do
				local def = kinds[kind]
				widest = math.max(widest, if def ~= nil then def.radius else 0)
			end
			local _floor, camp = campIndex(camps, tent.def.camp)
			if #tent.posts ~= #tent.kinds then
				told[id] = true
				problem(`group {id}: its posts could not be placed`)
				continue
			end
			for index, post in tent.posts do
				if camp ~= nil and not onFloor(camp, post.at.X, post.at.Z, widest) then
					told[id] = true
					problem(
						`group {id}: ring post {index} lies off its floor less {widest}, its widest radius`
					)
					break
				end
			end
		end
	end
	local reserve = StageFlow.BossReserve(level, kinds)

	-- A boss room's own residents, a tent with residents to go with it, and the population gate
	-- (L1b-W2-5), at every difficulty.
	for name in level.difficulties do
		local rank = ranks[name] or 0
		local _groups, residents = groupsOf(level, layout, rank, ranks)
		local _tents, tentStocks = tentsOf(level, layout, rank, ranks)
		for id, stock in tentStocks do
			if stock > 0 and (residents[id] or 0) == 0 then
				problem(`on {name} camp {id} has a tent stock of {stock} and no residents`)
			end
		end
		local caps: { [string]: number } = {}
		for _, stage in stages do
			local _floor, camp =
				campIndex(camps, if stage.kind == KIND_CAMP then stage.zone else nil)
			local cap = stage.maxAlive or level.crowd.maxAlive
			if camp == nil or type(cap) ~= "number" then
				continue
			end
			caps[camp.id] = cap
			local held = residents[camp.id] or 0
			if held >= cap then
				problem(
					`on {name} camp {camp.id} holds {held} residents, not fewer than its stage's maxAlive ({cap})`
				)
			end
		end
		local population = populationOf(residents, sumOf(tentStocks), caps, reserve)
		if population > crowdMax then
			problem(
				`on {name} the population is {population}, over ProvingGrounds.json crowd.maxAlive ({crowdMax})`
			)
		end
	end
end

-- One line per problem; an empty list is a level that may be played. `kinds` are the crowd kinds
-- of ProvingGrounds.json, `ranks` the place of every difficulty in Expeditions.json, `rules`
-- Combat.json `levels` and `crowdMax` ProvingGrounds.json crowd.maxAlive (the population gate).
-- L3-17: `weapons` (ProvingGrounds.json) and `starters` (Unlocks.Starters of its loadout) name
-- the families a first clear may give; a caller that leaves them out has the family checked as an
-- id only. Nothing here throws on a file with a key missing: that is a problem too.
function StageFlow.Validate(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	kinds: { [string]: Types.CrowdKindDef },
	ranks: { [string]: number },
	rules: Types.CombatLevelsConfig,
	crowdMax: number,
	weapons: { [string]: Types.RangeWeaponDef }?,
	starters: { [string]: boolean }?
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
		-- A countdown that is not a number, under 0 or endless would never close the gates.
		local countdown: any = stage.gateSeconds
		if
			countdown ~= nil
			and (type(countdown) ~= "number" or not (countdown >= 0 and countdown < math.huge))
		then
			problem(`{where}: gateSeconds is {tostring(countdown)}, not a time`)
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
	campProblems(
		level,
		layout,
		camps,
		stages,
		kinds,
		ranks,
		rules,
		crowdMax,
		problems,
		problem,
		checkKind
	)
	regionProblems(level, layout, camps, kinds, ranks, rules, problem)
	secretProblems(level, layout, problem)
	firstClearProblems(level, weapons, starters, problem)
	reactProblems(layout, problem)
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

-- Zone.ceiling (the L1c second fix round's F1 and F3): a locking camp's fence top when that is
-- over levels.triggerHeight, else triggerHeight. check_levels holds every other fence under
-- triggerHeight less a root, so whoever stands on it triggers; a fence above that is the
-- unclimbable wall, and nobody reaches its top, so under it the camp holds every root in the
-- opening or over the floor, however high a jump, cover and a leap carry it.
function StageFlow.Ceiling(camp: Types.LevelCamp, triggerHeight: number): number
	local fence = camp.fence
	if camp.locks ~= true or fence == nil then
		return triggerHeight
	end
	local top: any = fence.height
	if isFinite(top) and top > triggerHeight then
		return top
	end
	return triggerHeight
end

-- The L4 W2 fix round's K3 (the lobby fill): the most bodies of each kind any one of `kinds`
-- fields, where each entry is one plan's `kinds` (WaveService hands in every built level's plan at
-- every difficulty, so the lobby's RunState.prewarm covers whichever run the leader starts). A new
-- table; nil when no entry fields a body.
function StageFlow.MostKinds(kinds: { { [string]: number } }): { [string]: number }?
	local most: { [string]: number } = {}
	local any = false
	for _, counts in kinds do
		for kind, count in counts do
			if count > (most[kind] or 0) then
				most[kind] = count
				any = true
			end
		end
	end
	return if any then most else nil
end

-- The level as the run walks it, at one difficulty: a zone for every camp of the layout (its
-- floor index is its place in `layout.camps`), the stages, every resident group, every tent and
-- the population. `ranks` (the place of every difficulty in Expeditions.json) decides which
-- minDifficulty units are fielded; without it none is. `kinds` (ProvingGrounds.json crowd.kinds)
-- gives the boss reserve; without it each boss counts 1. nil, with the reason, for a difficulty
-- the level lacks, a camp stage whose zone the layout lacks, or a stage's camp whose entry lies
-- within levels.closeInset of its floor's edge (the close would move a fighter who stands on the
-- entry back onto it, into a body the gate overlaps), or a region Region.Problems refuses (Validate
-- names it first; with no `kinds` the door asked for is the narrower one). Each layout region is
-- built once (Region.Build) and the same graph hangs on every zone of it, and its cells on every
-- group of it (L1b-W4-14): that shared table is what lets one camp's raiders into the other's
-- floor. Asked after Validate: it reads the keys Validate answers for.
function StageFlow.Plan(
	level: Types.LevelConfig,
	layout: Types.LevelLayout,
	difficulty: string,
	rules: Types.CombatLevelsConfig,
	bounds: LevelGeometry.Bounds,
	ranks: { [string]: number }?,
	kinds: { [string]: Types.CrowdKindDef }?
): (Plan?, string?)
	if level.difficulties[difficulty] == nil then
		return nil, `{level.id} has no difficulty "{difficulty}"`
	end
	local rank = if ranks ~= nil then ranks[difficulty] or 0 else 0
	local graphs: { [string]: Types.RegionGraph } = {}
	local cellsOf: { [string]: { Types.CampRect } } = {}
	local regions: { Types.LevelRegion } = layout.regions or {}
	for _, region in regions do
		local cells = regionCells(region, layout.camps)
		local widest = regionReach(level, region.camps, ranks, kinds)
		local refused = Region.Problems(cells, 2 * widest + rules.doorSpare)
		if #refused > 0 then
			return nil, `{level.id}: region {region.id}: {refused[1]}`
		end
		local graph = Region.Build(cells)
		for _, id in region.camps do
			graphs[id] = graph
			cellsOf[id] = graph.cells
		end
	end
	local groups, residents, residentStocks = groupsOf(level, layout, rank, ranks, cellsOf)
	local tents, tentStocks = tentsOf(level, layout, rank, ranks, kinds, cellsOf)
	-- What a zone is called: its camps entry's name, else the name of the stage that names it.
	local names: { [string]: string } = {}
	for _, stage in level.stages do
		local id = stage.zone
		if stage.kind == KIND_CAMP and id ~= nil and names[id] == nil and stage.name ~= nil then
			names[id] = stage.name
		end
	end
	local configs: { Types.LevelCampConfig } = level.camps or {}
	for _, config in configs do
		if type(config.name) == "string" and config.name ~= "" then
			names[config.id] = config.name
		end
	end

	local zones: { Zone } = {}
	local byId: { [string]: Zone } = {}
	for index, camp in layout.camps do
		local rect: Rect = { x = camp.x, z = camp.z, hx = camp.sx / 2, hz = camp.sz / 2 }
		local inner = grown(rect, -rules.closeInset)
		local centre: Types.ArenaPoint = { x = camp.x, z = camp.z }
		-- An open camp is never entered by a close and may give no entry or exit.
		local entry: Types.ArenaPoint = camp.entry or centre
		local exit: Types.ArenaPoint = camp.exit or centre
		local spawns: { Vector3 } = {}
		local points: { Types.ArenaPoint } = camp.spawns or {}
		for _, point in points do
			table.insert(spawns, Vector3.new(point.x, camp.y, point.z))
		end
		local mark = camp.checkpoint
		local stop = if camp.locks == true then nil else camp.approach
		local fence = LevelGeometry.FenceThickness(camp, rules.fenceThickness)
		local zone: Zone = {
			id = camp.id,
			floor = index,
			locks = camp.locks == true,
			name = names[camp.id] or camp.id,
			checkpoint = if mark ~= nil then Vector3.new(mark.x, camp.y, mark.z) else nil,
			residents = residents[camp.id] or 0,
			stock = table.clone(residentStocks[camp.id] or {}),
			tentStock = tentStocks[camp.id] or 0,
			floorY = camp.y,
			rect = rect,
			inner = inner,
			fence = fence,
			trigger = grown(rect, fence),
			ceiling = StageFlow.Ceiling(camp, rules.triggerHeight),
			entry = Vector3.new(entry.x, camp.y, entry.z),
			exit = Vector3.new(exit.x, camp.y, exit.z),
			spawns = spawns,
			region = graphs[camp.id],
			approach = if stop ~= nil then Vector3.new(stop.x, stop.y, stop.z) else nil,
		}
		table.insert(zones, zone)
		byId[camp.id] = zone
	end

	local waters: { Water } = {}
	local blocks: { Types.LevelBlock } = layout.blocks or {}
	for _, block in blocks do
		local landing = block.landing
		if block.collide == false and landing ~= nil then
			table.insert(waters, {
				rect = { x = block.x, z = block.z, hx = block.sx / 2, hz = block.sz / 2 },
				landing = Vector3.new(landing.x, landing.y, landing.z),
			})
		end
	end

	local stages: { Stage } = {}
	local caps: { [string]: number } = {}
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
				targetWaveSeconds = 0,
				maxAlive = 0,
			})
			continue
		end
		local zone = if stage.zone ~= nil then byId[stage.zone] else nil
		if zone == nil then
			return nil, `{level.id}: the layout has no camp "{tostring(stage.zone)}"`
		end
		if not inRect(zone.inner, zone.entry.X, zone.entry.Z) then
			return nil,
				`{level.id}: the entry of camp {zone.id} is within closeInset of its floor's edge`
		end
		local waves: { Types.MissionCrowdWave } = stage.waves or {}
		local boss: { [number]: boolean } = {}
		for index, wave in waves do
			if wave.boss ~= nil then
				boss[index] = true
			end
		end
		local cap = stage.maxAlive or level.crowd.maxAlive
		caps[zone.id] = cap
		table.insert(stages, {
			kind = KIND_CAMP,
			name = stage.name or "",
			zone = zone,
			waves = #waves,
			boss = boss,
			breatherSeconds = stage.breatherSeconds,
			merge = stage.merge == true,
			targetWaveSeconds = stage.targetWaveSeconds or 0,
			maxAlive = cap,
			gateSeconds = stage.gateSeconds,
		})
	end
	return {
		levelId = level.id,
		difficulty = difficulty,
		start = Vector3.new(layout.start.x, layout.start.y, layout.start.z),
		killY = layout.killY,
		bounds = bounds,
		camps = #zones,
		stages = stages,
		zones = zones,
		groups = groups,
		tents = tents,
		population = populationOf(
			residents,
			sumOf(tentStocks),
			caps,
			StageFlow.BossReserve(level, kinds)
		),
		kinds = kindsOf(
			level,
			residentStocks,
			tents,
			rank,
			ranks,
			level.difficulties[difficulty].countMult,
			kinds
		),
		waters = waters,
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
		reached = {},
		done = {},
		closedAt = 0,
		fought = {},
		ended = nil,
		approached = 0,
	}
end

-- L1b-19: is the field clear, so the fallen do not lose the run? In the boss room's fight and
-- breathers: nothing queued, no boss to place, nothing alive on its floor. Everywhere else:
-- nothing queued and no group anywhere awake (rise, fight or home). So a solo down in a
-- resident fight ends the run, and a death on a quiet road costs a respawn.
function StageFlow.FieldClear(_plan: Plan, state: State, input: Input): boolean
	local step = state.step
	if step == "fight" or step == "breather" then
		return input.spawningDone and input.alive == 0
	end
	return input.spawningDone and input.awake == 0
end

-- The fix round's ruling on a downed party member (the run slice's Major): open camps have no
-- boundary, so a member who went down on the road or in an open camp's fight stands up as soon
-- as the road's field is clear (L1b-19: nothing queued, no group rising, fighting or going home).
-- Only outside the boss room's fight and breathers, where the boundary stands them up (P5 ruling
-- 18). True when somebody in `input.standing` is down and that moment has come. Revive by a
-- teammate is L5's.
function StageFlow.StandsUp(plan: Plan, state: State, input: Input): boolean
	local step = state.step
	if step ~= "travel" and step ~= "armed" and step ~= "gate" then
		return false
	end
	local standing = input.standing
	if standing == nil or not StageFlow.FieldClear(plan, state, input) then
		return false
	end
	for _, up in standing do
		if up == false then
			return true
		end
	end
	return false
end

-- L1b-20: the get-up i-frames a rescued body is given: none while it is engaged (reachable for a
-- group that is rising or fighting), so a fall out of a resident fight is no free escape.
function StageFlow.RescueGrace(engaged: boolean, iframes: number): number
	return if engaged then 0 else iframes
end

-- Ruling 9: a camp triggers when the root of any fighting member is inside its trigger rectangle
-- (the whole fenced rectangle, edges included) and between levels.triggerBelow under and its
-- ceiling (levels.triggerHeight, or a walled camp's fence top) above its floor. A root sits above
-- the feet, so triggerBelow only forgives a body sunk into the floor for a frame. A body that is
-- down does not count: a countdown that ends with nobody on their feet re-arms the camp, and a
-- downed body still inside would trigger it again, and again.
local function triggered(zone: Zone, input: Input, rules: Types.CombatLevelsConfig): boolean
	local standing = input.standing
	for index, root in input.roots do
		local above = root.Y - zone.floorY
		if
			above >= -rules.triggerBelow
			and above <= zone.ceiling
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

-- Into the countdown of camp `index`: its stage's own gateSeconds, else levels.gateSeconds (the
-- L1c fix round's M3). A countdown of 0 ends in the same tick: Advance runs the countdown's row
-- straight after, and a skip closes at once (`entered`).
local function gate(
	plan: Plan,
	state: State,
	index: number,
	now: number,
	rules: Types.CombatLevelsConfig
): Action
	local stage = plan.stages[index]
	local seconds = if stage ~= nil and stage.gateSeconds ~= nil
		then stage.gateSeconds
		else rules.gateSeconds
	state.stage = index
	state.step = "gate"
	state.gateAt = now + seconds
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

-- A skip into camp `index`'s countdown. One of 0 closes in the same batch, as a skip in the
-- countdown closes it at once: no RunState ever goes out in a countdown of 0.
local function entered(
	plan: Plan,
	state: State,
	actions: { Action },
	index: number,
	now: number,
	rules: Types.CombatLevelsConfig
): ()
	table.insert(actions, gate(plan, state, index, now, rules))
	if now >= state.gateAt then
		close(state, actions, now)
	end
end

-- The live camp is behind the party (cleared, or `skipped`): on to the next stage, or the end.
-- Appends `open`, then `travel` when a road follows, or `end` `cleared` after the last stage.
local function leaveCamp(plan: Plan, state: State, actions: { Action }, skipped: boolean): ()
	local index = state.stage
	local left = plan.stages[index]
	local zone = if left ~= nil then left.zone else nil
	if zone ~= nil then
		state.done[zone.floor] = true
	end
	state.cleared += 1
	state.lastCleared = index
	table.insert(actions, { kind = "open", stage = index, skipped = skipped })
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

-- L1b-18 and L1b-17, in every live step before the rows, each zone at most once per run. A
-- checkpoint is reached by a standing root within levels.checkpointReach of it on the flat, in
-- the trigger's height band over its camp's floor. An open camp that had residents is cleared
-- when no body of its floor lives (L1b-W4-29): a body's floor is its camp's for life, so that is
-- every raider it fielded, residents and tent bodies, wherever they stand (out on the road, in
-- another camp). What its tent has not sent is forfeit: nobody waits for a tent. Sneaking past a
-- camp is allowed, so a run never waits for it either.
local function progress(
	plan: Plan,
	state: State,
	input: Input,
	rules: Types.CombatLevelsConfig,
	actions: { Action }
): ()
	local standing = input.standing
	for index, zone in plan.zones do
		local mark = zone.checkpoint
		if mark == nil or state.reached[index] then
			continue
		end
		for rootIndex, root in input.roots do
			local rise = root.Y - zone.floorY
			local flat = Vector3.new(root.X - mark.X, 0, root.Z - mark.Z).Magnitude
			local inBand = rise >= -rules.triggerBelow and rise <= rules.triggerHeight
			if
				flat <= rules.checkpointReach
				and inBand
				and (standing == nil or standing[rootIndex] ~= false)
			then
				state.reached[index] = true
				table.insert(actions, { kind = "reach", stage = state.stage, zone = index })
				break
			end
		end
	end
	local byFloor = input.aliveByFloor or {}
	for index, zone in plan.zones do
		if zone.locks or zone.residents <= 0 or state.done[index] or byFloor[index] ~= 0 then
			continue
		end
		state.done[index] = true
		state.cleared += 1
		table.insert(actions, { kind = "campClear", stage = state.stage, zone = index })
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
	local fieldClear = StageFlow.FieldClear(plan, state, input)
	-- A clear field wins (ruling 17, L1b-19): the fallen do not lose a run whose field is clear.
	-- The rows below then run, and a camp that was just beaten clears instead.
	if fallen ~= nil and not fieldClear then
		table.insert(actions, over(state, fallen))
		return actions
	end
	progress(plan, state, input, rules, actions)
	local stage = plan.stages[state.stage]

	if step == "travel" or step == "armed" then
		local index = armedCamp(plan, state)
		local camp = plan.stages[index]
		local zone = if camp ~= nil then camp.zone else nil
		if zone == nil or not triggered(zone, input, rules) then
			return actions
		end
		table.insert(actions, gate(plan, state, index, input.now, rules))
		-- On into the countdown's row in this same tick: a countdown of 0 (the fix round's M3,
		-- "stepping in shuts the gate") closes now, or arms the camp again with nobody standing.
		step = "gate"
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
	if not fieldClear then
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
	-- `boundary` below lets in those who waited: a star is for the last wave's fighters. Nothing
	-- is paid here (L1b-15: every kill was paid as it fell); the clear counts the waves it covers.
	state.fought = table.clone(input.fighters)
	table.insert(
		actions,
		{ kind = "clear", stage = state.stage, wave = wave, count = wave - state.settled }
	)
	state.settled = wave
	local lastWave = wave >= stage.waves
	-- The run ends in this batch when this was the last camp's last wave.
	local ending = lastWave and plan.stages[state.stage + 1] == nil
	table.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })
	if not lastWave then
		state.step = "breather"
		state.breatherUntil = input.now + (stage.breatherSeconds or input.breatherSeconds)
		table.insert(actions, { kind = "breather", stage = state.stage, at = state.breatherUntil })
		return actions
	end
	leaveCamp(plan, state, actions, false)
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

-- L1b-W4-31 (amended by the lead): the zone N stops at next on the road, or 0: the first in layout
-- order after both the last one it stopped at and the furthest camp whose checkpoint was reached
-- (N never moves a party backwards, even one that walked on without it), that is open, has an
-- approach, is not cleared, whose checkpoint nobody has reached, and that lies before the armed
-- locking camp (stage `armed`; none when 0).
local function nextApproach(plan: Plan, state: State, armed: number): number
	local stage = plan.stages[armed]
	local lock = if stage ~= nil then stage.zone else nil
	if lock == nil then
		return 0
	end
	local from = state.approached
	for index in state.reached do
		from = math.max(from, index)
	end
	-- Every zone from here on lies past each reached checkpoint, so none of them has one reached.
	for index = from + 1, lock.floor - 1 do
		local zone = plan.zones[index]
		if zone ~= nil and not zone.locks and zone.approach ~= nil and not state.done[index] then
			return index
		end
	end
	return 0
end

-- Studio only (ruling 33, L1b-22). "stage" finishes this part: on the road the party is first
-- moved to each open camp's approach in turn (L1b-W4-31: nothing else happens, no clear, no pay),
-- then to the next locking camp and its countdown starts (the open camps passed by are not
-- cleared); a countdown ends now, a live camp is dropped and counts as cleared. "boss" goes to the next
-- wave with a boss, in this camp or a later one (the camps between count as cleared), and does
-- nothing when none is left. A `drop` is the live locking camp's alone, and nothing skipped is
-- credited. `fighters` is Input.fighters, for a skip that ends at a boundary.
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
			local stop = nextApproach(plan, state, index)
			if stop ~= 0 then
				state.approached = stop
				table.insert(actions, { kind = "approach", stage = state.stage, zone = stop })
			elseif index ~= 0 then
				table.insert(actions, { kind = "move", stage = index })
				entered(plan, state, actions, index, now, rules)
			end
		elseif step == "gate" then
			close(state, actions, now)
		else
			state.fought = if fighters ~= nil then table.clone(fighters) else {}
			local ending = plan.stages[state.stage + 1] == nil
			table.insert(actions, { kind = "drop", stage = state.stage })
			table.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })
			leaveCamp(plan, state, actions, true)
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
				entered(plan, state, actions, state.stage, now, rules)
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
		local zone = if between ~= nil then between.zone else nil
		if between ~= nil and between.kind == KIND_CAMP then
			if zone ~= nil then
				state.done[zone.floor] = true
			end
			state.cleared += 1
			state.lastCleared = index
			table.insert(actions, { kind = "open", stage = index, skipped = true })
		end
	end
	state.firstWave = targetWave
	state.wave = 0
	table.insert(actions, { kind = "move", stage = target })
	entered(plan, state, actions, target, now, rules)
	return actions
end

-- Studio only: the `wave` lever. Forces wave `wave` of the LIVE camp (its fight or its
-- breather), clamped to the camp's waves: the field is dropped and that wave starts at once.
-- The waves before it are settled without being counted, as a skip's are. Nothing elsewhere.
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

-- Is `mark` within a threat's reach, on the flat?
local function threatened(mark: Vector3, threats: { CampBrain.Shooter }?): boolean
	if threats == nil then
		return false
	end
	for _, threat in threats do
		if Vector3.new(mark.X - threat.at.X, 0, mark.Z - threat.at.Z).Magnitude <= threat.reach then
			return true
		end
	end
	return false
end

-- The fix round's B-3: whether a tent still owes its group a rouse. A body sent while its camp
-- fights (a group of its floor in rise or fight) is roused, but a tent's rouse acts only while a
-- player is known and reachable for its group (L1b-W4-28), from rest or from the walk home, and
-- never on a held group
-- (CampBrain.TentRouse), so the executor asks again every tick until the group is up, or until
-- the camp has nobody up to join.
function StageFlow.TentOwesRouse(owed: boolean, campBusy: boolean, groupAwake: boolean): boolean
	return owed and campBusy and not groupAwake
end

-- L1b-W4-30: what an open camp fielded, by kind, for its clear bonus: its residents (zone.stock)
-- and the first `sent` bodies of its tent's stock, in the order the tent sends them, less every
-- one the crowd refused (`refused`, by stock index; nil = none): a body that never spawned was
-- never fielded (the fix round's R12). A new table. What the tent never sent is forfeit, so it is
-- never priced.
function StageFlow.Fielded(
	zone: Zone,
	tent: PlanTent?,
	sent: number,
	refused: { [number]: boolean }?
): { [string]: number }
	local fielded = table.clone(zone.stock)
	if tent == nil then
		return fielded
	end
	for index = 1, math.min(sent, #tent.kinds) do
		if refused ~= nil and refused[index] then
			continue
		end
		local kind = tent.kinds[index]
		fielded[kind] = (fielded[kind] or 0) + 1
	end
	return fielded
end

-- The longest reach among a kind's attacks (0 for none, or an unknown kind): what a body of it
-- can strike at from where it stands, on the flat.
function StageFlow.LongestReach(def: Types.CrowdKindDef?): number
	local longest = 0
	local attacks = if def ~= nil then def.attacks else nil
	if attacks == nil then
		return longest
	end
	for _, attack in attacks do
		longest = math.max(longest, attack.reach)
	end
	return longest
end

-- The L1b Wave 4 fix round (R10): a group whose state makes its living members a threat for the
-- safe point. Home counts since L1b-W4-24: a homeward group that sees a reachable player turns
-- straight back to fight, so a body put among it lands in the fight it escaped.
function StageFlow.Threatening(state: Types.CampGroupState): boolean
	return state == "rise" or state == "fight" or state == "home"
end

-- Ruling 18 and L1b-18: the entry of the locking camp that is counting down, live or between
-- waves. Otherwise, from the furthest camp down, the checkpoint of the first one that has been
-- reached, that no threat reaches (the fix round: a shooter clamped at the edge of its own floor
-- still reaches a checkpoint on the road beside it) and, for a zone with no region, whose floor
-- is not `busy` (a group there is rising or fighting, so a body put there would land in that
-- fight); else the exit of the last cleared locking camp; else the level's start. A region's
-- groups chase off their floor and walk home over the road (L1b Wave 4), so a busy flag says
-- nothing about where they stand: a region zone is judged by the threats' positions alone (R10).
-- `busy` is CrowdService.Busy(), by floor index (nil = no floor is); `threats` is every living
-- member of a group StageFlow.Threatening names, at its position, with its kind's LongestReach
-- (nil = none).
function StageFlow.SafePoint(
	plan: Plan,
	state: State,
	busy: { [number]: boolean }?,
	threats: { CampBrain.Shooter }?
): Vector3
	local step = state.step
	if step == "gate" or step == "fight" or step == "breather" then
		local stage = plan.stages[state.stage]
		local zone = if stage ~= nil then stage.zone else nil
		if zone ~= nil then
			return zone.entry
		end
	end
	for index = #plan.zones, 1, -1 do
		local zone = plan.zones[index]
		local mark = zone.checkpoint
		local quiet = zone.region ~= nil or busy == nil or busy[index] ~= true
		if mark ~= nil and threatened(mark, threats) then
			quiet = false
		end
		if mark ~= nil and state.reached[index] and quiet then
			return mark
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

-- The L1c third fix round's m3: where the close puts a fighter MustEnter names whose root is in
-- the zone's fenced rectangle (its trigger), between levels.triggerBelow under and its ceiling
-- over its floor: the nearest point of `inner`, X and Z each held to it and the height kept, a
-- move of at most the zone's fence thickness + closeInset on an axis. WaveService moves the body
-- by that much and leaves its speed alone, so a jump or a dash goes on. With a countdown of 0 the close comes
-- in the tick the camp triggers, wherever in that rectangle the root was first seen: a dash past
-- a gate's edge is first sampled in the strip beside the opening, and held to the opening alone
-- (the second fix round's lanes) it went to the entry, 10 studs sideways. nil = outside the
-- rectangle or the band: the entry, as before.
function StageFlow.GateNudge(
	zone: Zone,
	position: Vector3,
	rules: Types.CombatLevelsConfig
): Vector3?
	local above = position.Y - zone.floorY
	if not (above <= zone.ceiling and above >= -rules.triggerBelow) then
		return nil
	end
	if not inRect(zone.trigger, position.X, position.Z) then
		return nil
	end
	local inner = zone.inner
	return Vector3.new(
		math.min(math.max(position.X, inner.x - inner.hx), inner.x + inner.hx),
		position.Y,
		math.min(math.max(position.Z, inner.z - inner.hz), inner.z + inner.hz)
	)
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

-- The landing of the first of the plan's waters whose footprint, grown by `grow`, holds `point`
-- in plan; nil when none does or there is no point (a point that is not finite is in no
-- rectangle: every comparison with NaN or an endless number fails).
local function waterAt(plan: Plan, point: Vector3?, grow: number): Vector3?
	if point == nil then
		return nil
	end
	for _, water in plan.waters do
		if inRect(grown(water.rect, grow), point.X, point.Z) then
			return water.landing
		end
	end
	return nil
end

-- L2-58: where a body that fell through deep water is put back: a water's landing. The fix
-- round's s-M1 and Q3: judged first by `stood`, where the body last stood (the last root the
-- server saw grounded, WeaponService.LastGround; nil = none known), then by `position`, where it
-- is now. A walk-off carries a body about 9 studs past the edge before it is judged, a dash-off
-- about 29, so the place it went in from decides, not how fast it went: a slip off the side of
-- the ice, the bridge or the bank comes back to that water's landing; a fall that neither stood
-- nor is by any water goes to the safe point. Each test is against the water's footprint grown
-- by `margin` on every side (player.rescue's outside: the bank beside the water, and a slow
-- sidestep's carry), the first water in the layout's order that holds the point. A margin that
-- is not a finite number of at least 0 counts as 0.
function StageFlow.Landing(plan: Plan, position: Vector3, stood: Vector3?, margin: number): Vector3?
	local grow = if isFinite(margin) and margin >= 0 then margin else 0
	return waterAt(plan, stood, grow) or waterAt(plan, position, grow)
end

-- L2-58: where WaveService's rescue puts a body it judged out of the level (Rescue's "level"):
-- Landing, except while a camp is closed (its fight and its breathers), when the run's safe point
-- holds as before (the camp's own entry). nil = the safe point.
function StageFlow.FallLanding(
	plan: Plan,
	state: State,
	position: Vector3,
	stood: Vector3?,
	margin: number
): Vector3?
	local step = state.step
	if step == "fight" or step == "breather" then
		return nil
	end
	return StageFlow.Landing(plan, position, stood, margin)
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
-- node. L2-15: `secrets` = the player's own secret rows by level id (SecretFlow.MapRow); the
-- node's level's row rides on its state whether it is open or not (nil = none).
function StageFlow.NodeState(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leader: Stars,
	own: Stars,
	nodeId: string,
	secrets: { [string]: { Types.MapSecretState } }?
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
		secrets = if secrets ~= nil and levelId ~= nil then secrets[levelId] else nil,
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

-- Every node, in the config's order, for one player (`secrets`: their rows by level id).
function StageFlow.MapState(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leader: Stars,
	own: Stars,
	leaderUserId: number,
	secrets: { [string]: { Types.MapSecretState } }?
): Types.MapState
	local nodes: { Types.MapNodeState } = {}
	for _, node in map.nodes do
		local state = StageFlow.NodeState(map, built, leader, own, node.id, secrets)
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

-- L3-17: what the first clear of `difficulty` gives besides its star, as a fresh table (the level
-- file is never handed out to be written): a family id that is a non-empty string, and a Valor that
-- is a whole number above 0. A key of any other kind is left out (Validate names it before the
-- level is played), and nil when nothing is left, or the difficulty has no `firstClear`. The
-- caller asks only when StageFlow.Award said the star is new.
function StageFlow.FirstClear(level: Types.LevelConfig, difficulty: string): Types.LevelFirstClear?
	local difficulties: any = level.difficulties
	local scales: any = if type(difficulties) == "table" then difficulties[difficulty] else nil
	local reward: any = if type(scales) == "table" then scales.firstClear else nil
	if type(reward) ~= "table" then
		return nil
	end
	local family = reward.family
	local valor = reward.valor
	local given: Types.LevelFirstClear = {
		family = if type(family) == "string" and family ~= "" then family else nil,
		valor = if isFinite(valor) and valor > 0 and valor % 1 == 0 then valor else nil,
	}
	if given.family == nil and given.valor == nil then
		return nil
	end
	return given
end

-- Who earns the star of a run: nobody unless it was cleared, and then those who were fighting
-- before its last boundary (State.fought). The boundary itself lets in everyone who waited in
-- the lobby camp, so "whoever fights at the end" would be everybody.
function StageFlow.EarnsStar(state: State, userId: number): boolean
	return state.ended == "cleared" and table.find(state.fought, userId) ~= nil
end

return StageFlow
