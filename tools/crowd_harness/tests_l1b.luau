-- Cases for L1b Wave 1, the run (docs/INTERFACES.md "L1b contracts — the living road" → "B —
-- the run"): StageFlow with open camps and one that locks (Validate's new refusals, Plan's zones,
-- groups and population, FieldClear, the checkpoints and open camps' clears in Advance,
-- SafePoint, RescueGrace, the skips), Combat's per-kill reward and its split with a carry, and
-- LevelGeometry's open camps and fire markers. Appended last by run_harness.py, so every local
-- of the earlier files is in scope (vec, check, near, load, L1, L1W). Everything hangs off the
-- L1B table (the 200-local limit), and every group runs behind L1.group, so one that throws
-- fails a check and the bundle goes on to its verdict.

print("L1b: the run (StageFlow, Combat, LevelGeometry)")

local L1B: any = {
	Flow = load("StageFlow"),
	Combat = load("Combat"),
	Geo = load("LevelGeometry"),
	rules = L1.copy(L1.rules),
	ranks = { normal = 1, hard = 2, brutal = 3 },
	-- L1b-W2-5: the colossus here calls 20, so its boss reserve is 21, Wave 1's flat reserve.
	kinds = { fodder = { radius = 1.3 }, slinger = { radius = 1.2 }, armoured = { radius = 1.7 }, brute = { radius = 2.2 }, colossus = { radius = 4, attacks = { { shape = "summon", reach = 60, count = 20, summon = "fodder" } } }, stray = { radius = 1 } },
	crowdMax = 160,
	bounds = { minX = -60, minY = -1, minZ = -20, maxX = 160, maxY = 40, maxZ = 600 },
}

-- A camp whose floor's top centre is (x, y, z), with a fence cut by a north and a south gate,
-- its entry and exit 4 studs inside them. `checkpoint` and `spots` are the case's own.
function L1B.camp(id: string, x: number, y: number, z: number, sx: number, sz: number): any
	return {
		id = id, x = x, y = y, z = z, sx = sx, sz = sz,
		fence = { height = 6 },
		gates = { { side = "north", at = 0, width = 14 }, { side = "south", at = 0, width = 14 } },
		entry = { x = x, z = z - sz / 2 + 4 },
		exit = { x = x, z = z + sz / 2 - 4 },
		spawns = { { x = x - 20, z = z + 10 }, { x = x + 20, z = z + 10 }, { x = x - 20, z = z + 20 }, { x = x + 20, z = z + 20 } },
	}
end

-- One road and three camps: A (Pickets, 60 x 60 at floor 8) and B (Main Camp, 100 x 94 at floor
-- 12) are open, each with its checkpoint on the road beyond its south side; C (the Chief's
-- Clearing, 80 x 80 at floor 4) locks, its checkpoint on its floor.
function L1B.layout(): any
	local a = L1B.camp("A", 0, 8, 100, 60, 60)
	a.checkpoint = { x = 0, z = 140 }
	a.spots = {
		{ id = "fire1", posture = "fire", points = { { x = -10, z = 100 } }, radius = 4 },
		{ id = "gate", posture = "guard", points = { { x = -5, z = 76 }, { x = 5, z = 76 }, { x = 0, z = 78 } }, facing = 0 },
		{ id = "loop", posture = "patrol", points = { { x = -20, z = 85 }, { x = 20, z = 85 }, { x = 20, z = 115 }, { x = -20, z = 115 } } },
	}
	local b = L1B.camp("B", 100, 12, 300, 100, 94)
	b.checkpoint = { x = 100, z = 360 }
	b.spots = {
		{ id = "camp", posture = "fire", points = { { x = 100, z = 300 } }, radius = 5 },
		{ id = "post", posture = "guard", points = { { x = 80, z = 260 }, { x = 120, z = 260 }, { x = 100, z = 262 } }, facing = 0 },
		{ id = "lookout", posture = "guard", points = { { x = 140, z = 330 } }, facing = 90 },
	}
	local c = L1B.camp("C", 0, 4, 520, 80, 80)
	c.locks = true
	c.checkpoint = { x = 30, z = 520 }
	c.spots = {
		{ id = "throne", posture = "guard", points = { { x = 0, z = 540 }, { x = 10, z = 540 }, { x = -10, z = 540 }, { x = 0, z = 545 } }, facing = 180 },
	}
	return {
		version = 1,
		start = { x = 0, y = 8, z = 0 },
		killY = -60,
		barrier = { height = 80, thickness = 8 },
		camps = { a, b, c },
		blocks = {},
		secrets = {},
		route = {},
	}
end

function L1B.level(): any
	local function scales(hp: number, count: number, reward: number): any
		return { hpScale = hp, damageScale = 1.1, plateScale = 1, countMult = count, rewardMult = reward, recommendedTier = 2 }
	end
	return {
		version = 1, id = "road", name = "Road", layout = "Road",
		material = "Timber", targetMinutes = 7, runCapSeconds = 900,
		difficulties = { normal = scales(1.5, 1, 1), hard = scales(5, 1.25, 2), brutal = scales(11, 1.5, 4) },
		crowd = {
			regenShare = 0.07, maxAlive = 40, burst = 8, burstSpacing = 3.5,
			rewards = { fodder = { cash = 100, materials = 0 }, slinger = { cash = 500, materials = 1 }, armoured = { cash = 1200, materials = 2 }, brute = { cash = 2000, materials = 6 }, colossus = { cash = 29000, materials = 70 } },
			clearBonus = { share = 0.1 },
		},
		stages = {
			{ kind = "travel", name = "Follow the road" },
			{ kind = "camp", zone = "C", name = "The Chief's Clearing", targetWaveSeconds = 30, breatherSeconds = 3, maxAlive = 30, waves = {
				{ groups = { { kind = "fodder", count = 6 } } },
				{ groups = {}, boss = { kind = "colossus", at = { 0, 10 }, valor = 10 } },
			} },
		},
		camps = {
			{ id = "A", name = "Pickets", residents = {
				{ spot = "fire1", units = { { kind = "fodder", count = 4 } } },
				{ spot = "gate", units = { { kind = "fodder", count = 2 }, { kind = "slinger", count = 1, minDifficulty = "hard" } } },
				{ spot = "loop", units = { { kind = "fodder", count = 3 } } },
			} },
			{ id = "B", name = "Main Camp", residents = {
				{ spot = "camp", units = { { kind = "fodder", count = 5 }, { kind = "brute", count = 1 } } },
				{ spot = "post", units = { { kind = "slinger", count = 2 }, { kind = "armoured", count = 1, minDifficulty = "hard" } } },
				{ spot = "lookout", units = { { kind = "slinger", count = 1, minDifficulty = "hard" } } },
			} },
			{ id = "C", name = "The Chief's Clearing", residents = {
				{ spot = "throne", units = { { kind = "fodder", count = 3 }, { kind = "armoured", count = 1, minDifficulty = "brutal" } } },
			} },
		},
	}
end

-- Plan with the fixture's ranks; `ranks` false = Plan given none.
function L1B.plan(level: any?, layout: any?, difficulty: string?, ranks: any?): any
	local given = if ranks == false then nil else ranks or L1B.ranks
	return L1B.Flow.Plan(level or L1B.level(), layout or L1B.layout(), difficulty or "normal", L1B.rules, L1B.bounds, given, L1B.kinds)
end

function L1B.problems(level: any?, layout: any?, rules: any?, crowdMax: number?): { string }
	local ok, problems = pcall(L1B.Flow.Validate, level or L1B.level(), layout or L1B.layout(), L1B.kinds, L1B.ranks, rules or L1B.rules, crowdMax or L1B.crowdMax)
	if not ok then
		return { "Validate threw: " .. tostring(problems) }
	end
	return problems
end

-- An L1b Input: nobody anywhere, nothing queued, every camp inhabited, nobody awake.
function L1B.input(over: any?): any
	local input: any = { now = 0, roots = {}, fighters = { 1 }, spawningDone = true, mergeOk = false, breatherSeconds = 6, fallen = nil, runCap = false, alive = 0, awake = 0, aliveByFloor = { 9, 8, 3 } }
	for key, value in over or {} do
		input[key] = value
	end
	return input
end

function L1B.advance(plan: any, state: any, over: any?): { any }
	return L1B.Flow.Advance(plan, state, L1B.input(over), L1B.rules)
end

-- A standing root `above` studs (3 by default) over a zone's floor at (x, z).
function L1B.root(zone: any, x: number, z: number, above: number?): any
	return vec(x, zone.floorY + (above or 3), z)
end

-- The units of a group as "kind count, kind count".
function L1B.units(def: any): string
	local out = {}
	for _, unit in (if def ~= nil then def.units else {}) do
		table.insert(out, `{unit.kind} {unit.count}`)
	end
	return table.concat(out, ", ")
end

function L1B.byId(groups: { any }): { [string]: any }
	local out = {}
	for _, def in groups do
		out[def.id] = def
	end
	return out
end

-- Validate's refusals ------------------------------------------------------------------------

function L1B.validateTests(): ()
	print(" Validate: which camps lock, the camps entries, the spots, the residents")
	local problems = L1B.problems
	local has = L1.has
	local good = problems()
	check(#good == 0, `the fixture (two open camps, a boss room) has no problem ({good[1] or "none"})`)
	-- `edit` changes a fresh level, layout or rules; the answer must name `text` and not throw.
	local function names(what: string, text: string, edit: (level: any, layout: any, rules: any) -> (), crowdMax: number?): ()
		local level, layout, rules = L1B.level(), L1B.layout(), L1.copy(L1B.rules)
		edit(level, layout, rules)
		local list = problems(level, layout, rules, crowdMax)
		check(not has(list, "Validate threw") and has(list, text), `{what}: "{text}" ({list[1] or "no problem"})`)
	end
	names("a stage that names an open camp", "names camp A, which does not lock", function(level)
		level.stages[2].zone = "A"
	end)
	names("a camp that locks and no stage names", "camp B locks and is named by 0 stages", function(_level, layout)
		layout.camps[2].locks = true
	end)
	names("a boss room two stages name", "camp C locks and is named by 2 stages", function(level)
		table.insert(level.stages, { kind = "travel", name = "Again" })
		table.insert(level.stages, L1.copy(level.stages[2]))
	end)
	names("a camps entry for a camp the layout lacks", 'camps entry 2 ("Z") names a camp the layout lacks', function(level)
		level.camps[2].id = "Z"
	end)
	names("two camps entries for one camp", "two camps entries for camp A", function(level)
		level.camps[2].id = "A"
	end)
	names("a camps entry with no name", 'camps entry 1 ("A") has no name', function(level)
		level.camps[1].name = nil
	end)
	names("a camps entry with an empty name", 'camps entry 3 ("C") has no name', function(level)
		level.camps[3].name = ""
	end)
	names("a resident group on a spot the camp lacks", 'names the spot "well", which camp A lacks', function(level)
		level.camps[1].residents[2].spot = "well"
	end)
	names("a resident group with no units", "resident group 1 has no units", function(level)
		level.camps[2].residents[1].units = {}
	end)
	names("a unit with no kind", "unit 1 has no kind", function(level)
		level.camps[1].residents[1].units[1].kind = nil
	end)
	names("a unit of a kind ProvingGrounds.json lacks", 'names the unknown kind "ghost"', function(level)
		level.camps[1].residents[1].units[1].kind = "ghost"
	end)
	names("a unit of a kind the rewards do not price", 'fields "stray", which rewards does not price', function(level)
		level.camps[1].residents[1].units[1].kind = "stray"
	end)
	names("a count of 0", "count 0 is not a whole number of at least 1", function(level)
		level.camps[1].residents[1].units[1].count = 0
	end)
	names("a count of 1.5", "count 1.5 is not a whole number of at least 1", function(level)
		level.camps[1].residents[1].units[1].count = 1.5
	end)
	names("a minDifficulty that is no difficulty", 'minDifficulty "nightmare" is no difficulty', function(level)
		level.camps[1].residents[2].units[2].minDifficulty = "nightmare"
	end)
	names("a spot with no id", "camp A spot 2 has no id", function(_level, layout)
		layout.camps[1].spots[2].id = nil
	end)
	names("a spot id used twice", 'camp B: the spot id "camp" is used twice', function(_level, layout)
		layout.camps[2].spots[2].id = "camp"
	end)
	names("a posture that is none of the three", 'posture "sleep" is not guard, patrol or fire', function(_level, layout)
		layout.camps[1].spots[1].posture = "sleep"
	end)
	names("a spot with no points", 'camp A spot "loop" has no points', function(_level, layout)
		layout.camps[1].spots[3].points = {}
	end)
	names("a point with no z", 'camp A spot "gate" lacks points[2].z', function(_level, layout)
		layout.camps[1].spots[2].points[2] = { x = 5 }
	end)
	names("a guard spot with no facing", 'camp B spot "post": a guard spot has no facing', function(_level, layout)
		layout.camps[2].spots[2].facing = nil
	end)
	names("a patrol of one point", 'camp A spot "loop": a patrol of 1 points', function(_level, layout)
		layout.camps[1].spots[3].points = { { x = 0, z = 100 } }
	end)
	names("a fire of two points", 'camp B spot "camp": a fire of 2 points', function(_level, layout)
		table.insert(layout.camps[2].spots[1].points, { x = 90, z = 300 })
	end)
	names("a fire of radius 0", 'camp A spot "fire1": a fire\'s radius is 0, not above 0', function(_level, layout)
		layout.camps[1].spots[1].radius = 0
	end)
	names("a fire with no radius", "a fire's radius is nil, not above 0", function(_level, layout)
		layout.camps[1].spots[1].radius = nil
	end)
	-- The gate holds 2 fodder on every difficulty and a slinger from Hard: 3 at the highest.
	names("a guard spot with more members at the highest difficulty than posts", "group A.gate holds 3 guards and has 2 posts", function(_level, layout)
		table.remove(layout.camps[1].spots[2].points)
	end)
	local level = L1B.level()
	level.difficulties.hard = nil
	level.difficulties.brutal = nil
	local layout = L1B.layout()
	table.remove(layout.camps[1].spots[2].points)
	check(#problems(level, layout) == 0, `(a level that offers Normal alone needs posts for Normal's members only) ({problems(level, layout)[1] or "none"})`)
	-- A post the fodder's radius (1.3) would hang over the edge from: camp A's floor ends at x 30.
	names("a guard post nearer the edge than its widest kind", "group A.gate: post 2 lies off its floor less 1.3", function(_level, given)
		given.camps[1].spots[2].points[2] = { x = 29, z = 76 }
	end)
	layout = L1B.layout()
	layout.camps[1].spots[2].points[2] = { x = 28.7, z = 76 }
	check(#problems(nil, layout) == 0, "(1.3 inside the edge is on it)")
	names("a fire circle that reaches past the floor", "group A.fire1: post", function(_level, given)
		given.camps[1].spots[1].points[1] = { x = -26, z = 100 }
	end)
	names("a boss room as full of residents as its cap", "on normal camp C holds 30 residents, not fewer than its stage's maxAlive (30)", function(level, given)
		level.camps[3].residents[1].units[1].count = 30
		for k = 5, 30 do
			table.insert(given.camps[3].spots[1].points, { x = -26 + k, z = 510 })
		end
	end)

	print(" Validate: the population gate (L1b-W2-5), at each difficulty, worked by hand")
	-- Normal: A 4 + 2 + 3, B 6 + 2, C 3 = 20; the boss room's cap leaves 30 - 3 = 27; the boss
	-- reserve 1 + the colossus's 20 calls = 21: 68. No tent here.
	-- Hard: A 4 + 3 + 3, B 6 + 3 + 1, C 3 = 23; 30 - 3 = 27; 21: 71.
	-- Brutal: Hard and C's armoured: 24; 30 - 4 = 26; 21: 71.
	names("a crowd cap of 70", "on hard the population is 71, over ProvingGrounds.json crowd.maxAlive (70)", function() end, 70)
	names("a crowd cap of 70, Brutal", "on brutal the population is 71", function() end, 70)
	check(not L1.has(problems(nil, nil, nil, 70), "on normal"), "(Normal's 68 is under 70)")
	check(#problems(nil, nil, nil, 71) == 0, "a crowd cap of 71 holds every difficulty")
	local quiet = L1.copy(L1B.kinds)
	quiet.colossus = { radius = 4 }
	local function quietProblems(crowdMax: number): { string }
		local ok, list = pcall(L1B.Flow.Validate, L1B.level(), L1B.layout(), quiet, L1B.ranks, L1B.rules, crowdMax)
		return if ok then list else { "Validate threw: " .. tostring(list) }
	end
	check(#quietProblems(51) == 0 and L1.has(quietProblems(50), "the population is 51"), "a colossus that calls nobody reserves 1, itself: Hard's left side is 51")

	print(" Validate: the numbers the run reads")
	for _, key in { "checkpointReach", "walletSendSeconds" } do
		names(`Combat.json levels without {key}`, `Combat.json lacks levels.{key}`, function(_level, _layout, given)
			given[key] = nil
		end)
	end
	names("a checkpointReach of 0", "levels.checkpointReach is 0, not above 0", function(_level, _layout, given)
		given.checkpointReach = 0
	end)
	names("a walletSendSeconds of -1", "levels.walletSendSeconds is -1, not above 0", function(_level, _layout, given)
		given.walletSendSeconds = -1
	end)
	names("a clear bonus share of -0.1", "crowd.clearBonus needs a share from 0 to 1", function(given)
		given.crowd.clearBonus = { share = -0.1 }
	end)
	names("a clear bonus of Wave 1's shape (cash and materials, no share)", "crowd.clearBonus needs a share from 0 to 1", function(given)
		given.crowd.clearBonus = { cash = 5, materials = 0 }
	end)
	level = L1B.level()
	level.crowd.clearBonus = nil
	level.camps = nil
	layout = L1B.layout()
	for _, camp in layout.camps do
		camp.spots = nil
	end
	check(#problems(level, layout) == 0, "(no clear bonus, no camps entries and no spots: legal, an empty road)")
end
L1.group("l1b validateTests", L1B.validateTests)

-- Plan ---------------------------------------------------------------------------------------

function L1B.planTests(): ()
	print(" Plan: a zone for every camp, the resident groups, the population")
	local plan = L1B.plan()
	local zones = plan.zones
	check(#zones == 3 and plan.camps == 3 and #plan.stages == 2, "three zones (every camp of the layout), two stages (the road and the boss room): Camps cleared counts all three")
	local a, b, c = zones[1], zones[2], zones[3]
	check(a.id == "A" and a.floor == 1 and b.id == "B" and b.floor == 2 and c.id == "C" and c.floor == 3, "in the layout's order, each zone's floor index its place in it")
	check(not a.locks and not b.locks and c.locks, "only C locks")
	check(a.name == "Pickets" and b.name == "Main Camp" and c.name == "The Chief's Clearing", "each named by its camps entry")
	local noNames = L1B.level()
	noNames.camps = nil
	local unnamed = L1B.plan(noNames)
	check(unnamed.zones[1].name == "A" and unnamed.zones[3].name == "The Chief's Clearing", "with no camps entry: the locking stage's name, else the id")
	check(L1.same(a.checkpoint, vec(0, 8, 140)) and L1.same(b.checkpoint, vec(100, 12, 360)) and L1.same(c.checkpoint, vec(30, 4, 520)), "each checkpoint is feet at its camp's floor height")
	check(a.residents == 9 and b.residents == 8 and c.residents == 3, `Normal places 9, 8 and 3 residents ({a.residents}, {b.residents}, {c.residents})`)
	check(plan.stages[2].zone == c and plan.stages[2].maxAlive == 30, "the boss room's stage is zone C itself, with its cap")
	check(plan.population == 68, `Normal's population by hand: 20 residents + 27 the boss room's room + 21 reserve = 68 ({plan.population})`)

	local normal = L1B.byId(plan.groups)
	local ids = {}
	for _, def in plan.groups do
		table.insert(ids, def.id)
	end
	check(table.concat(ids, " ") == "A.fire1 A.gate A.loop B.camp B.post C.throne", `the groups in the file's order, a group whose units all drop left out (B.lookout on Normal) ({table.concat(ids, " ")})`)
	local hardPlan = L1B.plan(nil, nil, "hard")
	local hard = L1B.byId(hardPlan.groups)
	check(L1B.units(normal["A.gate"]) == "fodder 2" and L1B.units(hard["A.gate"]) == "fodder 2, slinger 1", `minDifficulty units join on Hard (A.gate: {L1B.units(hard["A.gate"])})`)
	check(L1B.units(hard["A.fire1"]) == "fodder 4" and L1B.units(hard["B.camp"]) == "fodder 5, brute 1" and L1B.units(hard["A.loop"]) == "fodder 3", "and countMult (Hard's 1.25) never scales residents: fodder 4 stays 4")
	check(hard["B.lookout"] ~= nil and L1B.units(hard["B.lookout"]) == "slinger 1" and #hardPlan.groups == 7, "a group of Hard units alone appears from Hard")
	local brutalPlan = L1B.plan(nil, nil, "brutal")
	check(hardPlan.population == 71 and brutalPlan.population == 71 and brutalPlan.zones[3].residents == 4, `Hard 71, Brutal 71 (C holds 4 there), by hand ({hardPlan.population}, {brutalPlan.population})`)
	local noRanks = L1B.plan(nil, nil, "hard", false)
	check(L1B.units(L1B.byId(noRanks.groups)["A.gate"]) == "fodder 2" and #noRanks.groups == 6, "without the ranks no minDifficulty unit is fielded")

	local fire, gate, throne = normal["A.fire1"], normal["A.gate"], normal["C.throne"]
	check(fire.camp == "A" and fire.floor == 1 and fire.floorY == 8 and fire.posture == "fire" and fire.radius == 4 and #fire.points == 1 and L1.same(fire.points[1], vec(-10, 8, 100)), "a fire group: its camp, floor, height, radius and centre on the floor")
	check(fire.rect.x == 0 and fire.rect.z == 100 and fire.rect.hx == 30 and fire.rect.hz == 30, "its rect is its camp's floor")
	check(near(gate.yaw, 0) and near(throne.yaw, math.pi) and normal["B.post"].radius == 0 and near(hard["B.lookout"].yaw, math.pi / 2), "facing in degrees becomes yaw in radians (0, 180, 90); a spot that is no fire has radius 0")
	check(not fire.held and not gate.held and throne.held, "only the boss room's groups are held (L1b-13)")
	check(gate.points[3].Y == 8 and throne.points[1].Y == 4, "every point at its floor's height")

	print(" Resolve: a level file's camps reach the plan")
	local file = L1B.level()
	local resolved = L1B.Flow.Resolve(file, nil, 1200, "normal")
	check(resolved ~= nil and resolved.camps == file.camps and #resolved.camps == 3, "a level file's resident camps are kept as they stand")
	local fromFile = if resolved ~= nil then L1B.plan(resolved) else nil
	check(fromFile ~= nil and #fromFile.groups == 6 and fromFile.population == 68, "and Plan places their groups (6 on Normal, population 68)")
	file.camps = nil
	local bare = L1B.Flow.Resolve(file, nil, 1200, "normal")
	check(bare ~= nil and type(bare.camps) == "table" and #bare.camps == 0, "a file with no camps resolves to none ({}), never nil")
end
L1.group("l1b planTests", L1B.planTests)

-- FieldClear, RescueGrace -------------------------------------------------------------------

function L1B.fieldTests(): ()
	print(" FieldClear (L1b-19) and RescueGrace (L1b-20)")
	local Flow = L1B.Flow
	local plan = L1B.plan()
	local road = Flow.Begin(plan)
	local function clear(state: any, over: any): boolean
		return Flow.FieldClear(plan, state, L1B.input(over))
	end
	check(road.step == "travel" and clear(road, { awake = 0 }) and not clear(road, { awake = 1 }), "on the road the field is clear when no group is awake")
	check(clear(road, { awake = 0, alive = 5, aliveByFloor = { 9, 8, 3 } }), "residents at rest do not make it busy")
	check(not clear(road, { awake = 0, spawningDone = false }), "nor is it clear with a body queued")
	local fight = Flow.Begin(plan)
	L1B.advance(plan, fight, { now = 0, roots = { L1B.root(plan.zones[3], 0, 520) } })
	check(fight.step == "gate" and clear(fight, { awake = 0 }) and not clear(fight, { awake = 1 }), "in the countdown it asks the groups, as on the road")
	L1B.advance(plan, fight, { now = 3 })
	check(fight.step == "fight" and clear(fight, { alive = 0, awake = 2 }) and not clear(fight, { alive = 1, awake = 0 }), "in the boss room's fight: its own floor's bodies, whatever is awake elsewhere")
	check(clear(fight, { alive = 0, aliveByFloor = { 9, 8, 0 } }) and not clear(fight, { alive = 0, spawningDone = false }), "the open camps' residents do not keep the boss room's wave alive; a body queued does")
	check(Flow.RescueGrace(true, 1.5) == 0 and Flow.RescueGrace(false, 1.5) == 1.5, "RescueGrace: none while engaged, the get-up i-frames otherwise")
end
L1.group("l1b fieldTests", L1B.fieldTests)

-- Advance: checkpoints and open camps -----------------------------------------------------

function L1B.progressTests(): ()
	print(" Advance: a checkpoint is reached once (L1b-18)")
	local Flow = L1B.Flow
	local plan = L1B.plan()
	local a = plan.zones[1]
	local function reach(root: any, standing: any?): string
		local state = Flow.Begin(plan)
		return L1.names(L1B.advance(plan, state, { roots = { root }, standing = standing }))
	end
	check(reach(vec(0, 11, 140)) == "reach" and reach(vec(8, 11, 140)) == "reach" and reach(vec(0, 11, 148)) == "reach", "a root on the checkpoint, or 8 studs from it on the flat (checkpointReach), reaches it")
	check(reach(vec(8.1, 11, 140)) == "" and reach(vec(6, 11, 146)) == "", "8.1 studs away does not (6 and 6 is 8.49)")
	check(reach(vec(0, 38, 140)) == "reach" and reach(vec(0, 38.5, 140)) == "" and reach(vec(0, 4, 140)) == "reach" and reach(vec(0, 3.5, 140)) == "", "between triggerBelow (4) under and triggerHeight (30) over the camp's floor (8), edges included")
	check(reach(vec(0, 11, 140), { false }) == "" and reach(vec(0, 11, 140), { true }) == "reach", "only a root on its feet")
	local state = Flow.Begin(plan)
	local actions = L1B.advance(plan, state, { roots = { vec(0, 11, 140) } })
	local first = L1.get(actions, "reach")
	check(first.zone == 1 and first.stage == 1 and state.reached[1] == true and not state.reached[2], "it names the zone (1) and the run's stage")
	check(#L1B.advance(plan, state, { roots = { vec(0, 11, 140) } }) == 0, "and is not reached again")
	actions = L1B.advance(plan, state, { roots = { vec(0, 11, 140), vec(100, 15, 360) } })
	check(L1.names(actions) == "reach" and L1.get(actions, "reach").zone == 2, "a second root on B's: B is reached, A says nothing")

	print(" Advance: an open camp is cleared once its residents are dead (L1b-17)")
	state = Flow.Begin(plan)
	check(#L1B.advance(plan, state, { aliveByFloor = { 9, 8, 3 } }) == 0, "every camp inhabited: nothing")
	actions = L1B.advance(plan, state, { aliveByFloor = { 0, 8, 0 } })
	check(L1.names(actions) == "campClear" and L1.get(actions, "campClear").zone == 1 and state.done[1] and state.cleared == 1, "A's last resident falls: `campClear` for zone 1, A done, one camp cleared; C (it locks) is not, though its floor is empty")
	check(#L1B.advance(plan, state, { aliveByFloor = { 0, 8, 0 } }) == 0, "and A is not cleared again")
	actions = L1B.advance(plan, state, { aliveByFloor = { 0, 0, 3 } })
	check(L1.names(actions) == "campClear" and L1.get(actions, "campClear").zone == 2 and state.cleared == 2, "then B")
	local level = L1B.level()
	level.camps[2].residents = {}
	local emptyPlan = L1B.plan(level)
	local quiet = Flow.Begin(emptyPlan)
	check(emptyPlan.zones[2].residents == 0 and L1.names(L1B.advance(emptyPlan, quiet, { aliveByFloor = { 0, 0, 0 } })) == "campClear" and not quiet.done[2], "a camp that had no residents is never cleared")
	state = Flow.Begin(plan)
	check(#L1B.advance(plan, state, { aliveByFloor = {} }) == 0, "(a floor the tick did not count is not empty)")
	state = Flow.Begin(plan)
	actions = L1B.advance(plan, state, { roots = { L1B.root(plan.zones[3], 30, 520) }, aliveByFloor = { 0, 8, 3 } })
	check(L1.names(actions) == "reach campClear gate", `checkpoints, then open camps, then the rows, in one batch ({L1.names(actions)})`)

	print(" Advance: only the boss room triggers; a solo down on the road")
	state = Flow.Begin(plan)
	check(#L1B.advance(plan, state, { roots = { L1B.root(a, 0, 100) } }) == 0 and #L1B.advance(plan, state, { roots = { L1B.root(plan.zones[2], 100, 300) } }) == 0, "walking into A or B triggers nothing: they never close")
	check(L1.names(L1B.advance(plan, state, { roots = { L1B.root(plan.zones[3], 0, 490) } })) == "gate" and state.stage == 2, "walking into C starts its countdown")
	state = Flow.Begin(plan)
	actions = L1B.advance(plan, state, { now = 5, fallen = "down", awake = 1 })
	check(L1.names(actions) == "end" and state.ended == "down", "a solo down on the road while a group is awake ends the run (Ben's rule)")
	state = Flow.Begin(plan)
	check(#L1B.advance(plan, state, { now = 5, fallen = "wipe", awake = 0 }) == 0 and state.step == "travel", "on a quiet road it costs a respawn")
end
L1.group("l1b progressTests", L1B.progressTests)

-- One road and one boss room, walked through ----------------------------------------------

function L1B.walkTests(): ()
	print(" a walk-through: one road, two open camps, one boss room")
	local plan = L1B.plan()
	local c = plan.zones[3]
	local state = L1B.Flow.Begin(plan)
	local log = {}
	local banks = 0
	local function ask(over: any): { any }
		local actions = L1B.advance(plan, state, over)
		for _, action in actions do
			table.insert(log, action.kind)
			if action.kind == "bank" then
				banks += 1
			end
		end
		return actions
	end
	ask({ now = 1, roots = { vec(0, 11, 140) } })
	ask({ now = 2, aliveByFloor = { 0, 8, 3 } })
	ask({ now = 3, roots = { vec(100, 15, 360) }, aliveByFloor = { 0, 8, 3 } })
	ask({ now = 4, roots = { L1B.root(c, 0, 490) }, aliveByFloor = { 0, 8, 3 } })
	ask({ now = 7, aliveByFloor = { 0, 8, 3 }, alive = 3 })
	check(state.step == "fight" and state.wave == 1, "the countdown ends and C fights its first wave")
	local actions = ask({ now = 20, aliveByFloor = { 0, 8, 0 }, alive = 0 })
	check(L1.get(actions, "clear").count == 1 and L1.get(actions, "clear").wave == 1, "its first wave's clear counts one wave")
	ask({ now = state.breatherUntil, aliveByFloor = { 0, 8, 0 } })
	actions = ask({ now = 60, aliveByFloor = { 0, 8, 0 }, alive = 0 })
	check(L1.names(actions) == "clear boundary open end" and L1.get(actions, "end").reason == "cleared", "its last clears it and ends the run: clear, boundary, open, end")
	check(L1.get(actions, "open").skipped ~= true, "a camp beaten in play is not marked skipped: its clear pays")
	check(table.concat(log, " ") == "reach campClear reach gate close wave clear boundary breather wave clear boundary open end", `the whole run (B was sneaked past: never cleared) ({table.concat(log, " ")})`)
	check(banks == 0 and state.cleared == 2 and state.done[1] and not state.done[2] and state.done[3], "no bank, ever; two camps of three cleared (A and C)")
end
L1.group("l1b walkTests", L1B.walkTests)

-- SafePoint and the skips ------------------------------------------------------------------

function L1B.safeTests(): ()
	print(" SafePoint (L1b-18)")
	local Flow = L1B.Flow
	local plan = L1B.plan()
	local a, b, c = plan.zones[1], plan.zones[2], plan.zones[3]
	local state = Flow.Begin(plan)
	check(L1.same(Flow.SafePoint(plan, state), plan.start), "nothing reached: the start")
	L1B.advance(plan, state, { roots = { vec(0, 11, 140) } })
	check(L1.same(Flow.SafePoint(plan, state), a.checkpoint) and L1.same(Flow.SafePoint(plan, state, {}), a.checkpoint), "A's checkpoint reached: there")
	L1B.advance(plan, state, { roots = { vec(100, 15, 360) } })
	check(L1.same(Flow.SafePoint(plan, state), b.checkpoint), "B's too: the furthest, B's")
	check(L1.same(Flow.SafePoint(plan, state, { [2] = true }), a.checkpoint), "B's floor busy (a group rising or fighting): the next one down, A's")
	check(L1.same(Flow.SafePoint(plan, state, { [1] = true, [2] = true }), plan.start), "both busy: the start")
	local skipped = Flow.Begin(plan)
	L1B.advance(plan, skipped, { roots = { vec(100, 15, 360) } })
	check(L1.same(Flow.SafePoint(plan, skipped), b.checkpoint) and L1.same(Flow.SafePoint(plan, skipped, { [2] = true }), plan.start), "B's reached without A's: B's; B busy: the start, never A's unreached checkpoint")
	L1B.advance(plan, state, { now = 0, roots = { L1B.root(c, 0, 490) } })
	check(state.step == "gate" and L1.same(Flow.SafePoint(plan, state, { [3] = true }), c.entry), "in the boss room's countdown: its entry, busy or not")
	L1B.advance(plan, state, { now = 3 })
	check(state.step == "fight" and L1.same(Flow.SafePoint(plan, state), c.entry), "in its fight: its entry")

	print(" Skip and Force (L1b-22)")
	state = Flow.Begin(plan)
	local actions = Flow.Skip(plan, state, "stage", 5, L1B.rules)
	check(L1.names(actions) == "move gate" and L1.at(actions, 1).stage == 2 and state.stage == 2 and state.step == "gate", "N on the road: the party goes to the boss room and its countdown starts")
	check(not state.done[1] and not state.done[2] and state.cleared == 0, "the open camps passed by are not cleared")
	Flow.Skip(plan, state, "stage", 6, L1B.rules)
	actions = Flow.Skip(plan, state, "stage", 7, L1B.rules)
	local drop = L1.get(actions, "drop")
	check(L1.names(actions) == "drop boundary open end" and drop.stage == 2 and plan.stages[2].zone.floor == 3 and state.done[3] and not state.done[1], "N in its fight drops it (a drop of the boss room's stage: floor 3 alone) and counts it cleared")
	check(L1.get(actions, "open").skipped == true and state.cleared == 1, "its `open` is marked skipped (a skip pays nothing: no clear bonus, no wave in the stats), yet the summary counts it")
	state = Flow.Begin(plan)
	actions = Flow.Skip(plan, state, "boss", 5, L1B.rules)
	check(L1.names(actions) == "move gate" and state.firstWave == 2, "B on the road: the boss room's countdown, to open on the boss")
	L1B.advance(plan, state, { now = 8 })
	actions = Flow.Force(plan, state, 1)
	check(L1.names(actions) == "drop wave" and L1.at(actions, 2).wave == 1 and L1.at(actions, 1).stage == 2, "Force in the boss room: its floor is dropped and that wave starts")
end
L1.group("l1b safeTests", L1B.safeTests)

-- Combat: KillReward and SplitCarry -------------------------------------------------------

function L1B.rewardTests(): ()
	print(" Combat: KillReward is CampReward; SplitCarry pays whole units and carries the rest")
	local Combat = L1B.Combat
	local rewards = L1B.level().crowd.rewards
	rewards.lobber = { cash = 700, materials = 4 }
	local same = true
	for kind in rewards do
		for _, mult in { 1, 2, 4, 1.3, 1.5 } do
			local cash, materials = Combat.KillReward(rewards, kind, mult)
			local campCash, campMaterials = Combat.CampReward(rewards, kind, { rewardMult = mult })
			same = same and cash == campCash and materials == campMaterials
		end
	end
	check(same, "on every kind and every multiplier KillReward answers what CampReward answers")
	local function pay(kind: string, mult: number): string
		local cash, materials = Combat.KillReward(rewards, kind, mult)
		return `{cash}/{materials}`
	end
	check(pay("brute", 1) == "2000/6" and pay("brute", 2) == "4000/12" and pay("colossus", 4) == "116000/280", "by hand: a brute on Normal 2000 and 6, on Hard 4000 and 12; the Colossus on Brutal 116000 and 280")
	check(pay("slinger", 1.5) == "750/2" and pay("lobber", 1.3) == "910/5" and pay("nobody", 4) == "0/0", "rounded to the nearest (1 x 1.5 -> 2, 4 x 1.3 = 5.2 -> 5); an unpriced kind pays nothing")

	local carry = {}
	local solo = Combat.SplitCarry({ cash = 1234, materials = 7, valor = 10, kills = 1 }, { [1] = 1 }, carry)
	check(solo[1].cash == 1234 and solo[1].materials == 7 and solo[1].valor == 10 and carry[1].cash == 0 and carry[1].materials == 0 and carry[1].valor == 0, "solo: the whole pool, nothing carried")

	-- Two members at 0.9 and 0.1, ten kills of 1 Timber each.
	carry = {}
	local paidA, paidB, held = 0, 0, true
	local overpaid = false
	for kill = 1, 10 do
		local split = Combat.SplitCarry({ cash = 0, materials = 1, valor = 0, kills = 1 }, { [1] = 0.9, [2] = 0.1 }, carry)
		paidA += split[1].materials
		paidB += split[2].materials
		overpaid = overpaid or paidA + paidB > kill
		held = held and carry[1].materials < 1 and carry[2].materials < 1 and carry[1].materials >= 0 and carry[2].materials >= 0
	end
	check(paidA == 9 and paidB == 1, `ten 1-Timber kills at 0.9 / 0.1 pay 9 and 1 in all ({paidA}, {paidB})`)
	check(not overpaid and held, "never more than the pools held, and every carry stays under 1")
	carry = {}
	local first = Combat.SplitCarry({ cash = 0, materials = 1, valor = 0, kills = 1 }, { [1] = 0.95 }, carry)
	local second = Combat.SplitCarry({ cash = 0, materials = 1, valor = 0, kills = 1 }, { [1] = 0.95 }, carry)
	check(first[1].materials == 0 and near(carry[1].materials, 0.9) and second[1].materials == 1, "a fraction is never rounded up: 0.95 pays 0 and carries it; the next 0.95 makes 1.9, pays 1, carries 0.9")

	carry = {}
	local mult = Combat.SplitCarry({ cash = 3, materials = 0, valor = 0, kills = 1 }, { [1] = 1, [2] = 1 }, carry, { [1] = 1.5 })
	check(mult[1].cash == 4 and near(carry[1].cash, 0.5) and mult[2].cash == 3, "the cash multiplier is inside the carry: 3 x 1.5 = 4.5 pays 4 and carries 0.5; a member with none is at 1")
	mult = Combat.SplitCarry({ cash = 3, materials = 0, valor = 0, kills = 1 }, { [1] = 1 }, carry, { [1] = 1.5 })
	check(mult[1].cash == 5 and near(carry[1].cash, 0), "the next 4.5 and the 0.5 carried pay 5")

	carry = { [7] = { cash = 0.5, materials = 0.25, valor = 0.75 } }
	local absent = Combat.SplitCarry({ cash = 10, materials = 1, valor = 1, kills = 1 }, { [1] = 1 }, carry)
	check(absent[7] == nil and carry[7].cash == 0.5 and carry[7].materials == 0.25 and carry[7].valor == 0.75 and carry[1] ~= nil, "a member not in the shares keeps their carry, and one without a carry gets one")
	local nan = 0 / 0
	local bad = Combat.SplitCarry({ cash = 10, materials = 1, valor = 1, kills = 1 }, { [7] = nan, [8] = -0.1, [9] = math.huge }, carry)
	check(bad[7] == nil and bad[8] == nil and bad[9] == nil and carry[7].cash == 0.5 and carry[8] == nil and carry[9] == nil, "a share that is not a finite number of at least 0 pays nothing and leaves that carry as it was")
	carry = { [1] = { cash = 0.6, materials = 0, valor = 0 } }
	local withCarry = Combat.SplitCarry({ cash = 100, materials = 0, valor = 0, kills = 1 }, { [1] = 0.5, [2] = 0.5 }, carry)
	check(withCarry[1].cash == 50 and near(carry[1].cash, 0.6) and withCarry[2].cash == 50, "(a whole share leaves the carry where it was)")
end
L1.group("l1b rewardTests", L1B.rewardTests)

-- LevelGeometry: open camps and fire markers ------------------------------------------------

function L1B.worldTests(): ()
	print(" LevelGeometry: an open camp, fire markers, the arena locks")
	local Geo = L1B.Geo
	local sizes = L1.copy(L1W.sizes)
	sizes.fire = { sx = 3, sy = 1, sz = 3 }
	local layout = L1B.layout()
	local pieces = Geo.Pieces(layout, sizes, 600)
	local by: { [string]: any } = {}
	local roles: { [string]: { [string]: number } } = {}
	for _, piece in pieces or {} do
		by[piece.name] = piece
		local camp = piece.camp or "-"
		roles[camp] = roles[camp] or {}
		roles[camp][piece.role] = (roles[camp][piece.role] or 0) + 1
	end
	local a, b, c = roles.A or {}, roles.B or {}, roles.C or {}
	check(pieces ~= nil and a.gate == nil and a.barrier == nil and b.gate == nil and b.barrier == nil, "an open camp builds no gate and no invisible wall")
	check(a.fence == 6 and c.fence == 6 and c.gate == 2 and c.barrier == 4, `its fence is still cut at its gates (6 stretches, as the boss room's); the boss room has its 2 gates and 4 wall boxes ({a.fence}, {c.gate}, {c.barrier})`)
	local fire = by.Camp_A_Fire_fire1
	check(fire ~= nil and fire.role == "fire" and fire.look == "fire" and fire.collide == false and fire.camp == "A" and L1W.is(fire.box, -10, 8.5, 100, 3, 1, 3), `one fire marker per fire spot, centred on its point, its bottom on the floor's top, walked through ({fire and L1W.show(fire.box)})`)
	check(a.fire == 1 and b.fire == 1 and c.fire == nil and by.Camp_B_Fire_camp ~= nil, "none for a guard or a patrol spot")
	local noFire = Geo.Pieces(layout, L1W.sizes, 600)
	check(noFire ~= nil and pieces ~= nil and #noFire == #pieces - 2, "without levels.fireMarkerSize no marker is built")
	local locked = L1B.layout()
	for _, camp in locked.camps do
		camp.locks = true
	end
	local all = Geo.Pieces(locked, L1W.sizes, 600)
	check(all ~= nil and noFire ~= nil and #all == #noFire + 12, "every camp locking is 6 Parts more per open camp: 2 gates and 4 wall boxes")
	local arena = Geo.FromArena(L1W.village(), -8)
	check(arena.camps[1].locks == true, "FromArena: the arena's one camp locks")
	local walls = 0
	for _, piece in Geo.Pieces(arena, L1W.sizes, 600) or {} do
		if piece.role == "barrier" then
			walls += 1
		end
	end
	check(walls == 4, "so it keeps its invisible wall")

	print(" the shipped Forest Road: its Parts")
	local real = L1.real.layouts.ForestRoad
	if real == nil then
		check(false, "Layouts/Levels/ForestRoad.json is there")
		return
	end
	local realSizes = L1.real.sizes()
	local shipped = Geo.Pieces(real, realSizes, 10000)
	local asL1 = L1.copy(real)
	local open, opened, fires = 0, 0, 0
	for _, camp in asL1.camps do
		if camp.locks ~= true then
			open += 1
			opened += #(camp.gates or {}) + 4
			camp.locks = true
		end
		for _, spot in camp.spots or {} do
			if spot.posture == "fire" and realSizes.fire ~= nil then
				fires += 1
			end
		end
	end
	local every = Geo.Pieces(asL1, realSizes, 10000)
	local markers = 0
	for _, piece in shipped or {} do
		if piece.role == "fire" then
			markers += 1
		end
	end
	local count = if shipped ~= nil then #shipped else -1
	check(every ~= nil and count == #every - opened and markers == fires, `Forest Road: as if every camp locked, less each open camp's gates and 4 wall boxes; one marker per fire spot ({count} Parts, {markers} fires)`)
	-- L1b-W2-2: L1's formula ("73 less 6 per open camp plus one per fire") is dropped with L1's
	-- road; the cap is levels.maxParts, and check_levels.py's own count is held to Pieces' in
	-- tests_l1.luau's real-files cases.
	check(open == 2 and count > 0 and count <= L1.combat.levels.maxParts, `and at most levels.maxParts, with its two open camps ({count} Parts, {open} open)`)
end
L1.group("l1b worldTests", L1B.worldTests)

-- The fix round (docs/prompts/l1b-w1-fix-round.md, "B") ------------------------------------

-- A Road whose camp B locks too, with a fight of its own before C's: a boss skip from the road
-- passes B by.
function L1B.twoLocks(): any
	local level = L1B.level()
	local layout = L1B.layout()
	layout.camps[2].locks = true
	level.stages = {
		level.stages[1],
		{ kind = "camp", zone = "B", name = "Main Camp", targetWaveSeconds = 30, breatherSeconds = 3, maxAlive = 30, waves = { { groups = { { kind = "fodder", count = 6 } } } } },
		{ kind = "travel", name = "On to the Clearing" },
		level.stages[2],
	}
	return L1B.plan(level, layout)
end

function L1B.fixTests(): ()
	local Flow = L1B.Flow
	local plan = L1B.plan()
	local a, b, c = plan.zones[1], plan.zones[2], plan.zones[3]

	print(" StandsUp: a downed member stands up once the road's field is clear (the run slice's Major)")
	local down = { roots = { vec(0, 11, 60) }, standing = { false } }
	local function stands(state: any, over: any): boolean
		local input = L1B.input(down)
		for key, value in over or {} do
			input[key] = value
		end
		return Flow.StandsUp(plan, state, input)
	end
	local road = Flow.Begin(plan)
	check(road.step == "travel" and stands(road, {}), "on a quiet road (no group awake, nothing queued): yes")
	check(not stands(road, { awake = 1 }), "while a group anywhere is rising, fighting or going home: no (L1b-19)")
	check(not stands(road, { spawningDone = false }), "with a body queued: no")
	local nobodyDown = L1B.input({ roots = { vec(0, 11, 60) } })
	check(not stands(road, { standing = { true } }) and not stands(road, { standing = { true, true } }) and not Flow.StandsUp(plan, road, nobodyDown), "with nobody down (or no standing list): no")
	check(stands(road, { roots = { vec(0, 11, 60), vec(0, 11, 61) }, standing = { true, false } }), "one down among two: yes")
	local gate = Flow.Begin(plan)
	L1B.advance(plan, gate, { now = 0, roots = { L1B.root(c, 0, 490) } })
	check(gate.step == "gate" and stands(gate, {}) and not stands(gate, { awake = 1 }), "in the boss room's countdown: as on the road")
	L1B.advance(plan, gate, { now = 3 })
	check(gate.step == "fight" and not stands(gate, { alive = 0 }), "in the boss room's fight: no, its boundary does it (P5 ruling 18)")
	L1B.advance(plan, gate, { now = 4, alive = 0 })
	check(gate.step == "breather" and not stands(gate, { alive = 0 }), "in its breather: no")

	print(" Advance: checkpoints and open camps' clears in every live step (the run slice's Minor 2)")
	local live = Flow.Begin(plan)
	L1B.advance(plan, live, { now = 0, roots = { L1B.root(c, 0, 490) } })
	local actions = L1B.advance(plan, live, { now = 1, roots = { L1B.root(c, 30, 520) } })
	check(live.step == "gate" and L1.names(actions) == "reach" and L1.get(actions, "reach").zone == 3, `in the countdown, a root on C's checkpoint reaches it ({L1.names(actions)})`)
	L1B.advance(plan, live, { now = 3 })
	actions = L1B.advance(plan, live, { now = 3.5, alive = 2, aliveByFloor = { 0, 8, 2 } })
	check(live.step == "fight" and L1.names(actions) == "campClear" and L1.get(actions, "campClear").zone == 1, `in the fight, A's last resident falls: campClear for zone 1 ({L1.names(actions)})`)
	L1B.advance(plan, live, { now = 4, alive = 0, aliveByFloor = { 0, 8, 0 } })
	actions = L1B.advance(plan, live, { now = 4.5, aliveByFloor = { 0, 0, 0 } })
	check(live.step == "breather" and L1.names(actions) == "campClear" and L1.get(actions, "campClear").zone == 2, `in the breather, B's: campClear for zone 2 ({L1.names(actions)})`)

	print(" SafePoint: never in a threat's reach (the data slice's Minor 1)")
	local state = Flow.Begin(plan)
	L1B.advance(plan, state, { roots = { vec(0, 11, 140) } })
	L1B.advance(plan, state, { roots = { vec(100, 15, 360) } })
	local function threat(x: number, y: number, z: number, reach: number): any
		return { at = vec(x, y, z), reach = reach }
	end
	check(L1.same(Flow.SafePoint(plan, state, nil, nil), b.checkpoint) and L1.same(Flow.SafePoint(plan, state, nil, {}), b.checkpoint), "no threat: B's, the furthest")
	check(L1.same(Flow.SafePoint(plan, state, nil, { threat(110, 12, 360, 10) }), a.checkpoint), "a member 10 studs from B's checkpoint with a reach of 10 (the edge counts): the next one down, A's")
	check(L1.same(Flow.SafePoint(plan, state, nil, { threat(110, 12, 360, 9.99) }), b.checkpoint), "with a reach of 9.99: B's")
	check(L1.same(Flow.SafePoint(plan, state, nil, { threat(106, 62, 360, 10) }), a.checkpoint), "judged on the flat: a member 50 studs above, 6 along, still reaches it")
	check(L1.same(Flow.SafePoint(plan, state, nil, { threat(0, 8, 150, 12), threat(100, 12, 330, 48) }), plan.start), "both checkpoints in reach: the start")
	check(L1.same(Flow.SafePoint(plan, state, { [1] = true }, { threat(0, 8, 150, 12) }), b.checkpoint), "a threat by A and A busy leave B's alone")
	check(L1.same(Flow.SafePoint(plan, state, { [2] = true }, { threat(0, 8, 150, 12) }), plan.start), "B busy and A in reach: the start")
	L1B.advance(plan, state, { now = 0, roots = { L1B.root(c, 0, 490) } })
	check(state.step == "gate" and L1.same(Flow.SafePoint(plan, state, nil, { threat(c.entry.X, c.floorY, c.entry.Z, 50) }), c.entry), "in the boss room's countdown: its entry, threats or not")
	local reach = Flow.LongestReach
	check(reach({ attacks = { { reach = 32 }, { reach = 4.5 } } }) == 32 and reach({ attacks = { { reach = 4.5 }, { reach = 48 } } }) == 48, "LongestReach: the longest of a kind's attacks, wherever it stands")
	check(reach(nil) == 0 and reach({}) == 0 and reach({ attacks = {} }) == 0, "an unknown kind, or one with no attack: 0")

	print(" Skip: a boss skip's passed camps are marked skipped (the run slice's Minor 1)")
	local two = L1B.twoLocks()
	state = Flow.Begin(two)
	actions = Flow.Skip(two, state, "boss", 5, L1B.rules)
	local open = L1.get(actions, "open")
	check(L1.names(actions) == "open move gate" and open.stage == 2 and open.skipped == true and state.cleared == 1, `B on the road with a camp between: it opens, marked skipped, and counts on the summary ({L1.names(actions)})`)
end
L1.group("l1b fixTests", L1B.fixTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
