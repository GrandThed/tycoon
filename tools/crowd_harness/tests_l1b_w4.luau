-- Cases for L1b Wave 4, the run (docs/INTERFACES.md "L1b Wave 4 — no waits, no walls" → "B —
-- StageFlow", "B — tests_l1b_w4.luau"): the chase region in Validate and Plan (L1b-W4-14 to -16),
-- the pace on a tent (L1b-W4-28), the clear on the fielded raiders (L1b-W4-29), the bonus on what
-- was fielded (Fielded, L1b-W4-30) and N's approaches (L1b-W4-31), on a fixture and on the shipped
-- Forest Road. Appended after tests_l1b_w2.luau and A's tests_l1b_w4_crowd.luau, so every local
-- of the earlier files is in scope (vec, check, near, load, L1, L1B, W2B). Everything hangs off
-- the W4B table (the 200-local limit), and every group runs behind L1.group, so one that throws
-- fails a check and the bundle goes on to its verdict.

print("L1b Wave 4: the run (regions, the pace tent's clear, Fielded, N's approaches)")

local W4B: any = {
	Flow = load("StageFlow"),
	Combat = load("Combat"),
}

-- L1B's kinds with two reaches: B's slingers shoot 32 and its armoured (Hard and up) 48. So the
-- region's longest reach at the level's highest difficulty is 48 and the lock clearance 48 + 8 =
-- 56. The brute (A's tent) is the widest body, 2.2: a door is 2 x 2.2 + 0.5 = 4.9.
function W4B.kinds(): any
	local kinds = L1.copy(L1B.kinds)
	kinds.slinger.attacks = { { shape = "shot", reach = 32 } }
	kinds.armoured.attacks = { { shape = "line", reach = 48 }, { shape = "lunge", reach = 6 } }
	return kinds
end

-- W2B's road with B brought to A's height (8) and one region, "plateau", over A and B: A's floor
-- (x -30..30, z 70..130), B's (x 50..150, z 253..347), then three road cells: R1 south out of A
-- (a door of 16 x 5 into it), R2 across to x 108 (16 x 13 with R1), R3 south into B (16 x 8 with
-- R2, 16 x 7 with B). A tree of five cells and four doors. Each open camp has an approach.
function W4B.layout(): any
	local layout = W2B.layout()
	layout.camps[2].y = 8
	layout.camps[1].approach = { x = 0, y = 8, z = 40 }
	layout.camps[2].approach = { x = 100, y = 8, z = 230 }
	layout.regions = {
		{
			id = "plateau",
			y = 8,
			camps = { "A", "B" },
			cells = {
				{ id = "R1", x = 0, z = 150, sx = 16, sz = 50 },
				{ id = "R2", x = 50, z = 170, sx = 116, sz = 16 },
				{ id = "R3", x = 100, z = 215, sx = 16, sz = 90 },
			},
		},
	}
	return layout
end

function W4B.problems(level: any?, layout: any?, rules: any?): { string }
	local ok, problems = pcall(W4B.Flow.Validate, level or W2B.level(), layout or W4B.layout(), W4B.kinds(), L1B.ranks, rules or L1B.rules, L1B.crowdMax)
	if not ok then
		return { "Validate threw: " .. tostring(problems) }
	end
	return problems
end

function W4B.plan(level: any?, layout: any?, difficulty: string?): (any, string?)
	return W4B.Flow.Plan(level or W2B.level(), layout or W4B.layout(), difficulty or "normal", L1B.rules, L1B.bounds, L1B.ranks, W4B.kinds())
end

-- Validate ------------------------------------------------------------------------------------

function W4B.validateTests(): ()
	print(" Validate: the region, the lock clearance, approaches and the tent's pace (L1b-W4-14 to -16, -28, -31)")
	local has = L1.has
	local good = W4B.problems()
	check(#good == 0, `the fixture (a region over A and B, two approaches, two paced tents) has no problem ({good[1] or "none"})`)
	local function names(what: string, text: string, edit: (level: any, layout: any, rules: any) -> ()): ()
		local level, layout, rules = W2B.level(), W4B.layout(), L1.copy(L1B.rules)
		edit(level, layout, rules)
		local list = W4B.problems(level, layout, rules)
		check(not has(list, "Validate threw") and has(list, text), `{what}: "{text}" ({list[1] or "no problem"})`)
	end
	local function clean(what: string, text: string, edit: (level: any, layout: any, rules: any) -> ()): ()
		local level, layout, rules = W2B.level(), W4B.layout(), L1.copy(L1B.rules)
		edit(level, layout, rules)
		local list = W4B.problems(level, layout, rules)
		check(not has(list, "Validate threw") and not has(list, text), `({what}: no "{text}") ({list[1] or "no problem"})`)
	end
	local region = 'region "plateau"'

	names("regionLockMargin missing from Combat.json", "Combat.json lacks levels.regionLockMargin", function(_level, _layout, rules)
		rules.regionLockMargin = nil
	end)
	names("doorSpare missing from Combat.json", "Combat.json lacks levels.doorSpare", function(_level, _layout, rules)
		rules.doorSpare = nil
	end)
	names("regions that are not a list", "regions is not a list", function(_level, layout)
		layout.regions = "plateau"
	end)
	names("a region with no id", "region 1 has no id", function(_level, layout)
		layout.regions[1].id = nil
	end)
	names("two regions of one id", 'the region id "plateau" is used twice', function(_level, layout)
		table.insert(layout.regions, { id = "plateau", y = 8, camps = { "B" }, cells = {} })
	end)
	names("a region with a NaN y", `{region}: its y is nan, not a finite height`, function(_level, layout)
		layout.regions[1].y = 0 / 0
	end)
	names("a region with no camps", `{region} has no camps`, function(_level, layout)
		layout.regions[1].camps = {}
	end)
	names("a region camp the layout lacks", `{region} names camp "Q", which the layout lacks`, function(_level, layout)
		table.insert(layout.regions[1].camps, "Q")
	end)
	names("a locking camp in a region", `{region}: camp C locks, and a boss room is in no region`, function(_level, layout)
		table.insert(layout.regions[1].camps, "C")
	end)
	names("a camp in two regions", "camp B is in two regions", function(_level, layout)
		table.insert(layout.regions, { id = "east", y = 8, camps = { "B" }, cells = {} })
	end)
	names("a region camp off the region's height", `{region}: camp B's floor is at y 12, not the region's 8`, function(_level, layout)
		layout.camps[2].y = 12
	end)
	names("road cells that are not a list", `{region}: cells is not a list`, function(_level, layout)
		layout.regions[1].cells = 5
	end)
	names("a road cell with no id", `{region} cell 2 has no id`, function(_level, layout)
		layout.regions[1].cells[2].id = nil
	end)
	names("a road cell at NaN", `{region} cell "R2" needs a finite x, z, sx and sz`, function(_level, layout)
		layout.regions[1].cells[2].x = 0 / 0
	end)
	names("a road cell with no size", `{region} cell "R1" needs a finite x, z, sx and sz`, function(_level, layout)
		layout.regions[1].cells[1].sz = nil
	end)
	names("a road cell of width 0", `{region} cell "R3": its size must be above 0`, function(_level, layout)
		layout.regions[1].cells[3].sx = 0
	end)
	names("a road cell past the wire", `{region} cell "R1" lies beyond 1000 studs of the world origin`, function(_level, layout)
		layout.regions[1].cells[1].x = 993
	end)
	-- Region.Problems, each with its region named: a door under 2 x 2.2 + 0.5 = 4.9, a gap, a cycle.
	names("a door of 4.8 (A's floor into R1, R1 moved 0.2 south)", `{region}: region cells 1 and 3: a door of`, function(_level, layout)
		layout.regions[1].cells[1].z = 150.2
	end)
	names("doorSpare counts: a spare of 0.7 makes the 5-stud door too narrow", "a door of 16 x 5 studs, under 5.1", function(_level, _layout, rules)
		rules.doorSpare = 0.7
	end)
	names("a cycle (R4 overlaps R1 and R2)", `{region}: region: the cells form a cycle`, function(_level, layout)
		table.insert(layout.regions[1].cells, { id = "R4", x = 4, z = 168, sx = 16, sz = 16 })
	end)
	names("a cell joined to nothing", "not joined to cell 1", function(_level, layout)
		table.insert(layout.regions[1].cells, { id = "far", x = -300, z = 0, sx = 10, sz = 10 })
	end)
	-- The lock clearance: B's armoured's 48 + 8 = 56 from C's floor (80 x 80). C moved under B
	-- (x 100): its floor 56 studs past B's south edge (z 347) is legal, 55 is not.
	clean("C's floor 56 studs from B's", "studs from locking camp C's floor", function(_level, layout)
		layout.camps[3].x = 100
		layout.camps[3].z = 347 + 56 + 40
	end)
	names("a cell 1 stud too close to C", `{region}: camp B's floor is 55 studs from locking camp C's floor, under its longest reach 48 + regionLockMargin 8 = 56`, function(_level, layout)
		layout.camps[3].x = 100
		layout.camps[3].z = 347 + 55 + 40
	end)
	-- C at (-100, 170): its floor x -140..-60, z 130..210. R2 (x -8..108, z 162..178) is 52 from
	-- it on the flat; A's floor (x -30..30, z 70..130) touches its z band, 30 off on x.
	names("a road cell too close to C", `{region}: cell R2 is 52 studs from locking camp C's floor`, function(_level, layout)
		layout.camps[3].x = -100
		layout.camps[3].z = 170
	end)
	names("and a camp's floor too", `{region}: camp A's floor is 30 studs from locking camp C's floor`, function(_level, layout)
		layout.camps[3].x = -100
		layout.camps[3].z = 170
	end)
	-- Measured rectangle to rectangle on the diagonal: B's corner (150, 347) to C's (166, 389) is
	-- 16 x 42 = 44.9, under 56; to C's centre it would be 56 x 82.
	names("a gap on the diagonal", `{region}: camp B's floor is 44.94 studs`, function(_level, layout)
		layout.camps[3].x = 206
		layout.camps[3].z = 429
	end)
	clean("a level that offers Normal alone: B's armoured never fields, the reach is the slinger's 32 (40)", "studs from locking camp C's floor", function(level, layout)
		level.difficulties.hard = nil
		level.difficulties.brutal = nil
		layout.camps[3].x = 100
		layout.camps[3].z = 347 + 41 + 40
	end)
	names("(and at 39 it is refused, naming 32)", "under its longest reach 32 + regionLockMargin 8 = 40", function(level, layout)
		level.difficulties.hard = nil
		level.difficulties.brutal = nil
		layout.camps[3].x = 100
		layout.camps[3].z = 347 + 39 + 40
	end)
	names("regionLockMargin counts: 20 makes it 68", "+ regionLockMargin 20 = 68", function(_level, layout, rules)
		rules.regionLockMargin = 20
		layout.camps[3].x = 100
		layout.camps[3].z = 347 + 60 + 40
	end)
	-- Approaches.
	names("an approach at NaN", "camp A: its approach needs a finite x, y and z", function(_level, layout)
		layout.camps[1].approach.y = 0 / 0
	end)
	names("an approach with no z", "camp B: its approach needs a finite x, y and z", function(_level, layout)
		layout.camps[2].approach.z = nil
	end)
	names("an approach on the boss room", "camp C locks, and a boss room has no approach", function(_level, layout)
		layout.camps[3].approach = { x = 0, y = 4, z = 470 }
	end)
	names("an approach past the wire", "camp A: its approach lies beyond 1000 studs of the world origin", function(_level, layout)
		layout.camps[1].approach.z = -1001
	end)
	-- The tent's pace.
	names("a tent without pace", `camps entry 1 ("A"): its tent has no pace`, function(level)
		level.camps[1].tent.pace = nil
	end)
	names("a pace of 0 seconds", "its tent's pace.seconds is 0, not a time above 0", function(level)
		level.camps[2].tent.pace.seconds = 0
	end)
	names("a pace of infinite seconds", "its tent's pace.seconds is inf, not a time above 0", function(level)
		level.camps[2].tent.pace.seconds = math.huge
	end)
	names("a lead over 1", "its tent's pace.lead is 1.5, not from 0 to 1", function(level)
		level.camps[1].tent.pace.lead = 1.5
	end)
	names("a lead under 0", "its tent's pace.lead is -0.1, not from 0 to 1", function(level)
		level.camps[1].tent.pace.lead = -0.1
	end)
	names("a lead of NaN", "not from 0 to 1", function(level)
		level.camps[1].tent.pace.lead = 0 / 0
	end)
	for _, lead in { 0, 1 } do
		clean(`a lead of {lead}`, "pace.lead", function(level)
			level.camps[1].tent.pace.lead = lead
		end)
	end
	-- A layout with no regions is Wave 2's: legal.
	clean("no regions at all", "region", function(_level, layout)
		layout.regions = nil
	end)
end
L1.group("l1b w4 validateTests", W4B.validateTests)

-- Plan ----------------------------------------------------------------------------------------

function W4B.planTests(): ()
	print(" Plan: one shared graph per region, its cells on every def, stock, approach and pace (L1b-W4-14, -28, -30, -31)")
	local plan, why = W4B.plan()
	if plan == nil then
		check(false, `the fixture plans ({tostring(why)})`)
		return
	end
	local zones = plan.zones
	local graph = zones[1].region
	check(graph ~= nil and zones[2].region == graph and zones[3].region == nil, "A's and B's zones share ONE RegionGraph table; the boss room's has none")
	local cells = if graph ~= nil then graph.cells else {}
	local function cellIs(cell: any, x: number, z: number, hx: number, hz: number): boolean
		return cell ~= nil and near(cell.x, x) and near(cell.z, z) and near(cell.hx, hx) and near(cell.hz, hz)
	end
	check(#cells == 5 and cellIs(cells[1], 0, 100, 30, 30) and cellIs(cells[2], 100, 300, 50, 47) and cellIs(cells[3], 0, 150, 8, 25) and cellIs(cells[4], 50, 170, 58, 8) and cellIs(cells[5], 100, 215, 8, 45), "its cells: A's floor, B's floor, then R1, R2, R3 as centre and half size")
	local swapped = W4B.layout()
	swapped.regions[1].camps = { "B", "A" }
	local other = W4B.plan(nil, swapped)
	local first = if other ~= nil and other.zones[1].region ~= nil then other.zones[1].region.cells[1] else nil
	check(cellIs(first, 0, 100, 30, 30), "the camps' floors come in the layout's camp order, whatever order the region names them in")
	check(graph ~= nil and graph.next[3][5] == 4 and graph.hops[1][2] == 4, "the graph is built: from R1 to R3 by R2, four doors from A to B")
	local carried = true
	local count = 0
	for _, def in plan.groups do
		if def.camp == "C" then
			carried = carried and def.region == nil
		else
			count += 1
			carried = carried and graph ~= nil and def.region == graph.cells
		end
	end
	for _, tent in plan.tents do
		count += 1
		carried = carried and graph ~= nil and tent.def.region == graph.cells
	end
	check(carried and count == 7, `every A and B def on Normal, five resident groups and two tents (7), carries the region's cells, the same list; C's none ({count})`)
	check(W2B.stock(zones[1].stock) == "fodder 9" and W2B.stock(zones[2].stock) == "brute 1, fodder 5, slinger 2", `zone.stock is its residents only ({W2B.stock(zones[1].stock)}; {W2B.stock(zones[2].stock)})`)
	check(zones[1].approach ~= nil and L1.same(zones[1].approach, vec(0, 8, 40)) and zones[2].approach ~= nil and L1.same(zones[2].approach, vec(100, 8, 230)) and zones[3].approach == nil, "zone.approach: the layout's feet as given; none on the boss room")
	local locked = W4B.layout()
	locked.camps[3].approach = { x = 0, y = 4, z = 470 }
	local lockedPlan = W4B.plan(nil, locked)
	check(lockedPlan ~= nil and lockedPlan.zones[3].approach == nil, "(a boss room's approach, which Validate refuses, is never planned)")
	check(plan.tents[1].pace.seconds == 25 and plan.tents[1].pace.lead == 0.15 and plan.tents[2].pace.seconds == 130, "PlanTent.pace is the level's")
	check(plan.population == W2B.plan().population, "the population is unchanged by the region (the tent stock still counted as an upper bound)")
	local plain = W2B.plan()
	check(plain.zones[1].region == nil and plain.groups[1].region == nil and plain.zones[1].approach == nil, "a layout with no region plans none (Wave 2's floors)")
	local narrow = W4B.layout()
	narrow.regions[1].cells[1].z = 151
	local refused, said = W4B.plan(nil, narrow)
	check(refused == nil and type(said) == "string" and string.find(said, "region plateau", 1, true) ~= nil, `a region Region.Problems refuses is not planned, by name ({tostring(said)})`)
end
L1.group("l1b w4 planTests", W4B.planTests)

-- Fielded and the clear -----------------------------------------------------------------------

function W4B.fieldedTests(): ()
	print(" Fielded (L1b-W4-30) and the clear on the fielded raiders (L1b-W4-29)")
	local Flow = W4B.Flow
	local plan = W4B.plan()
	local a = plan.zones[1]
	local tent = plan.tents[1]
	check(table.concat(tent.kinds, " ") == "fodder fodder brute", "(A's tent on Normal: fodder, fodder, brute)")
	local none = Flow.Fielded(a, tent, 0)
	check(W2B.stock(none) == "fodder 9" and none ~= a.stock, `sent 0: its residents, a new table ({W2B.stock(none)})`)
	local two = Flow.Fielded(a, tent, 2)
	check(W2B.stock(two) == "fodder 11", `sent 2: the first two of the stock ({W2B.stock(two)})`)
	local three = Flow.Fielded(a, tent, 3)
	check(W2B.stock(three) == "brute 1, fodder 11", `sent 3: the whole stock ({W2B.stock(three)})`)
	check(W2B.stock(Flow.Fielded(a, tent, 9)) == "brute 1, fodder 11", "sent past the stock: the stock, no more")
	check(W2B.stock(Flow.Fielded(a, nil, 3)) == "fodder 9" and W2B.stock(Flow.Fielded(a, tent, -1)) == "fodder 9", "no tent, or sent below 0: the residents")
	check(W2B.stock(a.stock) == "fodder 9", "and zone.stock itself is never changed")
	local rewards = W2B.level().crowd.rewards
	local cash = W4B.Combat.ClearBonus(Flow.Fielded(a, tent, 0), rewards, 1, 0.1)
	local sent = W4B.Combat.ClearBonus(Flow.Fielded(a, tent, 3), rewards, 1, 0.1)
	check(cash == 90 and sent == 310, `the bonus by hand: 9 fodder x 100 x 0.1 = 90; with the tent's 2 fodder and its brute 310 ({cash}, {sent})`)

	local state = Flow.Begin(plan)
	local function said(over: any): string
		return L1.names(L1B.advance(plan, state, over))
	end
	check(said({ aliveByFloor = { 3, 8, 3 } }) == "", "A with 3 of its raiders alive (on its floor or out on the road): no clear")
	local actions = L1B.advance(plan, state, { aliveByFloor = { 0, 8, 3 } })
	check(L1.names(actions) == "campClear" and L1.get(actions, "campClear").zone == 1 and state.done[1] == true, "A at 0 with its tent's whole stock unsent: campClear at once, nothing waited for")
	check(said({ aliveByFloor = { 0, 8, 3 } }) == "" and said({ aliveByFloor = { 0, 8, 3 } }) == "", "never twice")
	local quiet = W2B.level()
	for _, group in quiet.camps[1].residents do
		for _, unit in group.units do
			unit.minDifficulty = "brutal"
		end
	end
	local empty = W4B.plan(quiet)
	local emptyState = Flow.Begin(empty)
	check(empty.zones[1].residents == 0 and L1.names(L1B.advance(empty, emptyState, { aliveByFloor = { 0, 8, 3 } })) == "", "a camp with no residents never clears")
	local skip = Flow.Begin(plan)
	Flow.Skip(plan, skip, "stage", 0, L1B.rules, { 1 })
	Flow.Skip(plan, skip, "stage", 1, L1B.rules, { 1 })
	local road = Flow.Skip(plan, skip, "stage", 2, L1B.rules, { 1 })
	local gate = Flow.Skip(plan, skip, "stage", 3, L1B.rules, { 1 })
	local drop = Flow.Skip(plan, skip, "stage", 4, L1B.rules, { 1 })
	check(L1.names(road) == "move gate" and L1.names(gate) == "close wave" and L1.get(drop, "open").skipped == true and L1.find(drop, "campClear") == nil, `a skip still pays nothing: the boss room's open is marked skipped, and no open camp clears ({L1.names(drop)})`)
end
L1.group("l1b w4 fieldedTests", W4B.fieldedTests)

-- Skip: N's approaches --------------------------------------------------------------------------

function W4B.skipTests(): ()
	print(" Skip: N stops at each open camp's approach before the boss room (L1b-W4-31)")
	local Flow = W4B.Flow
	local plan = W4B.plan()
	local rules = L1B.rules
	local function n(state: any, now: number): { any }
		return Flow.Skip(plan, state, "stage", now, rules, { 1 })
	end
	local state = Flow.Begin(plan)
	check(state.approached == 0, "Begin: nothing approached")
	local first = n(state, 0)
	check(L1.names(first) == "approach" and L1.at(first, 1).zone == 1 and L1.at(first, 1).stage == 1 and state.approached == 1 and state.step == "travel", "from the start: approach A (zone 1), on the road; nothing else (no clear, no pay, no countdown)")
	local second = n(state, 1)
	check(L1.names(second) == "approach" and L1.at(second, 1).zone == 2 and state.approached == 2, "then approach B")
	local third = n(state, 2)
	check(L1.names(third) == "move gate" and L1.at(third, 1).stage == 2 and state.step == "gate", "then the boss room: move and gate, as Wave 2's N")
	check(state.done[1] == nil and state.done[2] == nil and state.cleared == 0, "no approach clears or counts a camp")

	local done = Flow.Begin(plan)
	done.done[1] = true
	local skipA = n(done, 0)
	check(L1.names(skipA) == "approach" and L1.at(skipA, 1).zone == 2, "with A cleared: approach B first")
	local reached = Flow.Begin(plan)
	reached.approached = 1
	reached.reached[2] = true
	check(L1.names(n(reached, 0)) == "move gate", "with A passed and B's checkpoint reached: straight to the boss room")
	local passed = Flow.Begin(plan)
	passed.reached[1] = true
	local skipReached = n(passed, 0)
	check(L1.names(skipReached) == "approach" and L1.at(skipReached, 1).zone == 2, "a camp whose checkpoint was reached is passed over")
	local back = Flow.Begin(plan)
	back.approached = 2
	check(L1.names(n(back, 0)) == "move gate", "N never goes back before its last stop (approached 2: A is not offered again)")
	local bare = W4B.layout()
	bare.camps[1].approach = nil
	local barePlan = W4B.plan(nil, bare)
	local bareState = Flow.Begin(barePlan)
	local bareFirst = Flow.Skip(barePlan, bareState, "stage", 0, rules, { 1 })
	check(L1.names(bareFirst) == "approach" and L1.at(bareFirst, 1).zone == 2, "a camp with no approach is passed over")
	local wave2 = W2B.plan()
	check(L1.names(Flow.Skip(wave2, Flow.Begin(wave2), "stage", 0, rules, { 1 })) == "move gate", "with no approach anywhere, N is Wave 2's")

	-- In the countdown, the fight and the breather: as before.
	local gate = Flow.Begin(plan)
	gate.approached = 2
	n(gate, 0)
	check(gate.step == "gate" and L1.names(n(gate, 1)) == "close wave", "in the countdown: the gates close")
	check(L1.names(n(gate, 2)) == "drop boundary open end", "in the fight: drop, boundary, open, end")
	local boss = Flow.Begin(plan)
	local bossActions = Flow.Skip(plan, boss, "boss", 0, rules, { 1 })
	check(L1.names(bossActions) == "move gate" and boss.firstWave == 2 and boss.approached == 0, "B on the road ignores the approaches: the boss room's countdown, to open on the boss")
end
L1.group("l1b w4 skipTests", W4B.skipTests)

-- The shipped Forest Road ------------------------------------------------------------------------

function W4B.realTests(): ()
	print(" the shipped Forest Road: the plateau region, the approaches, the pace, N")
	local resolved = L1.real.resolve("forestRoad")
	local level = resolved.level
	local layout = resolved.layout
	if level == nil or layout == nil then
		check(false, "the shipped Forest Road resolves")
		return
	end
	local ok, problems = pcall(W4B.Flow.Validate, level, layout, L1.real.kinds, L1.real.ranks(), L1.real.rules, FIXTURES.proving.crowd.maxAlive)
	check(ok and #problems == 0, `Validate finds nothing, its region and approaches included ({if ok then problems[1] or "none" else tostring(problems)})`)
	local regions = layout.regions or {}
	check(#regions == 1 and regions[1].id == "plateau" and table.concat(regions[1].camps, " ") == "A B", "one region, the plateau, over A and B")
	for _, difficulty in L1.real.map.difficulties do
		local plan, why = L1.real.plan(level, layout, difficulty, L1.real.bounds(layout))
		if plan == nil then
			check(false, `{difficulty}: Forest Road plans ({tostring(why)})`)
			continue
		end
		local zones = plan.zones
		local graph = zones[1].region
		local cells = if graph ~= nil then #graph.cells else 0
		check(graph ~= nil and zones[2].region == graph and zones[3].region == nil and cells == 2 + #regions[1].cells, `{difficulty}: A and B share the plateau's graph ({cells} cells), the Chief's Clearing has none`)
		local carried = true
		for _, def in plan.groups do
			carried = carried and (def.camp == "C") == (def.region == nil)
		end
		for _, tent in plan.tents do
			carried = carried and graph ~= nil and tent.def.region == graph.cells
		end
		check(carried, `{difficulty}: every A and B def carries the plateau's cells, no C def does`)
		check(zones[1].approach ~= nil and zones[2].approach ~= nil and zones[3].approach == nil, `{difficulty}: approaches before the Pickets and Main Camp, none at the Chief's`)
		check(#plan.tents == 2 and plan.tents[1].pace ~= nil and plan.tents[2].pace ~= nil, `{difficulty}: both tents carry a pace`)
		local stock = 0
		for _, count in zones[1].stock do
			stock += count
		end
		check(stock == zones[1].residents, `{difficulty}: the Pickets' stock is its {zones[1].residents} residents, no tent body`)
		if difficulty ~= "normal" then
			continue
		end
		-- N from the trailhead: approach A, approach B, then the Chief's countdown.
		local state = W4B.Flow.Begin(plan)
		local steps = {}
		for now = 0, 2 do
			local actions = W4B.Flow.Skip(plan, state, "stage", now, L1.real.rules, { 1 })
			local first = actions[1]
			table.insert(steps, L1.names(actions) .. (if first ~= nil and first.zone ~= nil then ` {first.zone}` else ""))
		end
		local line = table.concat(steps, "; ")
		print(`   N from the trailhead: {line}`)
		check(line == "approach 1; approach 2; move gate", `N from the trailhead: approach A, approach B, then move and gate to the Chief's Clearing ({line})`)
		local a = zones[1].approach
		print(`   A's approach ({a.X}, {a.Y}, {a.Z}), B's ({zones[2].approach.X}, {zones[2].approach.Y}, {zones[2].approach.Z})`)
		local done = W4B.Flow.Begin(plan)
		done.done[1] = true
		local skipped = W4B.Flow.Skip(plan, done, "stage", 0, L1.real.rules, { 1 })
		check(L1.names(skipped) == "approach" and L1.at(skipped, 1).zone == 2, "with the Pickets cleared: Main Camp's approach first")
	end
end
L1.group("l1b w4 realTests", W4B.realTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
