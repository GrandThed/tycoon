-- Cases for L1b Wave 4, the crowd (docs/INTERFACES.md "L1b Wave 4 — no waits, no walls" -> "A —
-- tests_l1b_w4_crowd.luau"): the pure Region, CampBrain's chase (known, reachable, melee, the
-- leash with closing, the stand-down, home's turn-back, Forget, the pace tent), and CrowdService
-- with a region floor. Appended after tests_l1b_w2.luau by run_harness.py, so every local of the
-- earlier files is in scope (vec, check, near, load, Crowd, root, step2, seen, fresh, struck, L1BC,
-- W2A...). Everything hangs off the W4C table (the bundle's 200-local limit), and every group runs
-- behind L1BC.group or L1BC.crowdGroup, so one that throws fails a check and the bundle goes on.

print("L1b Wave 4: the crowd (Region, the chase, the pace tent)")

local W4C: any = {
	Region = load("Region"),
	CB = load("CampBrain"),
}

function W4C.rect(x: number, z: number, sx: number, sz: number): any
	return { x = x, z = z, hx = sx / 2, hz = sz / 2 }
end

-- Forest Road's RoadAB1-5 footprints as the layout's blocks stand (the U-bend round the void).
function W4C.uBend(): { any }
	return {
		W4C.rect(-150.5, -44, 57, 16),
		W4C.rect(-130, -22, 16, 60),
		W4C.rect(-119, 0, 38, 16),
		W4C.rect(-108, -22, 16, 60),
		W4C.rect(-93, -44, 46, 16),
	}
end

-- An L of two cells: (-10..10, -4..4) and (2..10, 0..20); their door is (2..10, 0..4).
function W4C.ell(): { any }
	return { { x = 0, z = 0, hx = 10, hz = 4 }, { x = 6, z = 10, hx = 4, hz = 10 } }
end

-- Region ------------------------------------------------------------------------------------------
function W4C.buildTests(): ()
	local Region = W4C.Region
	print(" Region.Build")
	local u = Region.Build(W4C.uBend())
	local d = u.doors
	check(
		d[1][2] ~= nil and d[2][3] ~= nil and d[3][4] ~= nil and d[4][5] ~= nil and d[1][3] == nil and d[2][4] == nil and d[1][5] == nil and d[2][5] == nil,
		"the U-bend: AB1-AB2, AB2-AB3, AB3-AB4, AB4-AB5 are neighbours, and nothing else (the void between the arms)"
	)
	check(d[1][2] == d[2][1], "doors[i][j] and doors[j][i] are one door")
	check(
		near(d[1][2].x, -130) and near(d[1][2].z, -44) and near(d[2][3].x, -130) and near(d[2][3].z, 0)
			and near(d[3][4].x, -108) and near(d[3][4].z, 0) and near(d[4][5].x, -108) and near(d[4][5].z, -44),
		"each door is its overlap's centre: (-130, -44), (-130, 0), (-108, 0), (-108, -44)"
	)
	check(u.next[1][5] == 2 and u.hops[1][5] == 4 and u.next[5][1] == 4 and u.hops[5][1] == 4, "AB1 to AB5: 4 hops, by AB2; back by AB4")
	check(u.next[2][4] == 3 and u.hops[2][4] == 2 and u.next[4][2] == 3, "AB2 to AB4: 2 hops, by AB3")
	check(u.next[3][3] == 3 and u.hops[3][3] == 0, "a cell to itself: itself, 0 hops")
	local ell = Region.Build(W4C.ell())
	check(ell.doors[1][2] ~= nil and near(ell.doors[1][2].x, 6) and near(ell.doors[1][2].z, 2) and ell.next[1][2] == 2 and ell.hops[2][1] == 1, "the L: one door at (6, 2), one hop")
	local touching = Region.Build({ { x = 0, z = 0, hx = 5, hz = 5 }, { x = 10, z = 0, hx = 5, hz = 5 } })
	check(touching.doors[1][2] == nil and touching.next[1][2] == 0 and touching.hops[1][2] == math.huge, "two cells that only share an edge are not neighbours: next 0, hops math.huge")
	local single = Region.Build({ { x = 0, z = 0, hx = 5, hz = 5 } })
	check(#single.cells == 1 and single.next[1][1] == 1 and single.hops[1][1] == 0, "a single cell")
	local bad = Region.Build({ { x = 0, z = 0, hx = 5, hz = 5 }, { x = 0 / 0, z = 0, hx = 5, hz = 5 } })
	check(bad.doors[1][2] == nil and bad.hops[1][2] == math.huge, "a non-finite cell never throws and has no neighbour")

	print(" Region.Problems")
	local minDoor = 4.9
	check(#Region.Problems(W4C.uBend(), minDoor) == 0, "the U-bend: no problem")
	check(#Region.Problems({}, minDoor) == 1, "no cells: one line")
	local cycle = { W4C.rect(0, 0, 20, 20), W4C.rect(15, 0, 20, 20), W4C.rect(7.5, 12, 20, 20) }
	local cycleLines = Region.Problems(cycle, minDoor)
	check(#cycleLines == 1 and string.find(cycleLines[1], "cycle") ~= nil, `a cycle of three: one line, the cycle ({cycleLines[1]})`)
	local gap = Region.Problems({ W4C.rect(0, 0, 10, 10), W4C.rect(30, 0, 10, 10) }, minDoor)
	check(#gap == 1 and string.find(gap[1], "not joined") ~= nil, "a gap: the cell not joined to cell 1")
	local thinX = Region.Problems({ W4C.rect(0, 0, 10, 10), W4C.rect(5.2, 0, 10, 10) }, minDoor)
	check(#thinX == 1 and string.find(thinX[1], "door") ~= nil, "a door of 4.8 on x: one line")
	local thinZ = Region.Problems({ W4C.rect(0, 0, 10, 10), W4C.rect(0, 5.2, 10, 10) }, minDoor)
	check(#thinZ == 1 and string.find(thinZ[1], "door") ~= nil, "a door of 4.8 on z: one line")
	check(#Region.Problems({ W4C.rect(0, 0, 10, 10), W4C.rect(9.5, 0, 10, 10) }, 0.5) == 0, "a door of 0.5 against a minDoor of 0.5: fine")
	local badCell = Region.Problems({ W4C.rect(0, 0, 10, 10), { x = 0, z = 0, hx = 0, hz = 5 } }, minDoor)
	check(#badCell >= 1 and string.find(badCell[1], "cell 2") ~= nil, "a cell with a half size of 0 is named")
	-- The shipped plateau: its camps' floors in layout order, then its road cells in file order.
	local layout = FIXTURES.layouts.ForestRoad
	local region = if layout.regions ~= nil then layout.regions[1] else nil
	if region == nil then
		check(false, "ForestRoad.json has a region (the economy-designer's)")
	else
		local cells = {}
		for _, campId in region.camps do
			for _, campDef in layout.camps do
				if campDef.id == campId then
					table.insert(cells, W4C.rect(campDef.x, campDef.z, campDef.sx, campDef.sz))
				end
			end
		end
		for _, cell in region.cells do
			table.insert(cells, W4C.rect(cell.x, cell.z, cell.sx, cell.sz))
		end
		local lines = Region.Problems(cells, 2 * 2.2 + FIXTURES.combat.levels.doorSpare)
		check(#lines == 0, `the shipped plateau ({#cells} cells): no problem ({table.concat(lines, "; ")})`)
	end

	print(" Region.Distance, Inside, Clamp")
	local one = { { x = 0, z = 0, hx = 10, hz = 10 } }
	check(Region.Distance(one, 3, -4) == 0 and Region.Distance(one, 10, 2) == 0, "Distance: 0 inside and on an edge")
	check(near(Region.Distance(one, 13, 14), 5), "a 3-4-5 corner: 5")
	check(Region.Distance({}, 0, 0) == math.huge, "no cells: math.huge")
	check(near(Region.Distance(W4C.uBend(), -119, -30), 3), "the U's void: 3 from the nearer arm")
	check(Region.Inside(one, vec(8 + 0.5e-6, 0, 0), 2) and not Region.Inside(one, vec(8 + 2e-6, 0, 0), 2), "Inside: the inset edge + EPS is in, past it is not")
	check(Region.Inside(one, vec(0, 0, -8), 2) and not Region.Inside(one, vec(0, 0, -8.01), 2), "on z too")
	local inside = vec(3, 7, -2)
	check(Region.Clamp(one, inside, 2) == inside, "Clamp: a point inside is answered as it is (Y kept)")
	local out = Region.Clamp(one, vec(20, 5, 3), 2)
	check(near(out.X, 8) and near(out.Z, 3) and out.Y == 5, "outside: the nearest inset point, Y kept")
	local tie = Region.Clamp({ { x = -10, z = 0, hx = 2, hz = 2 }, { x = 10, z = 0, hx = 2, hz = 2 } }, vec(0, 0, 0), 0)
	check(near(tie.X, -8) and near(tie.Z, 0), "a tie goes to the lowest index")
	local narrow = Region.Clamp({ { x = 0, z = 0, hx = 1, hz = 1 } }, vec(5, 2, 5), 3)
	check(near(narrow.X, 0) and near(narrow.Z, 0) and Region.Inside({ { x = 0, z = 0, hx = 1, hz = 1 } }, vec(0, 0, 0), 3), "a radius wider than the cell: its centre line (the inset is a point)")
	check(Region.Clamp({}, inside, 1) == inside, "no cells: the point")
end
L1BC.group("region build", W4C.buildTests)

-- CrowdBrain's floor runway before Wave 4, as the reference for one cell.
function W4C.oldRunway(from: any, heading: any, radius: number, cell: any): number
	local limitX = math.max(cell.hx - radius, 0)
	local limitZ = math.max(cell.hz - radius, 0)
	local room = math.huge
	if heading.X > 0 then
		room = math.min(room, (cell.x + limitX - from.X) / heading.X)
	elseif heading.X < 0 then
		room = math.min(room, (cell.x - limitX - from.X) / heading.X)
	end
	if heading.Z > 0 then
		room = math.min(room, (cell.z + limitZ - from.Z) / heading.Z)
	elseif heading.Z < 0 then
		room = math.min(room, (cell.z - limitZ - from.Z) / heading.Z)
	end
	return math.max(room, 0)
end

function W4C.routeTests(): ()
	local Region = W4C.Region
	print(" Region.Runway")
	local cell = { x = 3, z = -5, hx = 20, hz = 12 }
	local draw = W2A.stream(4242)
	local same = true
	local worst = 0
	for _ = 1, 200 do
		local radius = draw() * 3
		local fromX = cell.x + (draw() * 2 - 1) * (cell.hx - radius)
		local fromZ = cell.z + (draw() * 2 - 1) * (cell.hz - radius)
		local angle = draw() * 2 * math.pi
		local from = vec(fromX, 8, fromZ)
		local heading = vec(math.sin(angle), 0, math.cos(angle))
		local new = Region.Runway({ cell }, from, heading, radius)
		local old = W4C.oldRunway(from, heading, radius, cell)
		worst = math.max(worst, math.abs(new - old))
		same = same and near(new, old, 1e-9)
	end
	check(same, `one cell: equal to the old floor runway on 200 seeded rays (worst {worst})`)
	local ell = W4C.ell()
	check(near(Region.Runway(ell, vec(6, 0, 0), vec(0, 0, 1), 1), 19), "through the L's door: from (6, 0) north, radius 1, to the second cell's inset end, 19")
	check(near(Region.Runway(ell, vec(-5, 0, 0), vec(0, 0, 1), 1), 3), "west of the door the first cell's edge stops it, 3")
	local u = W4C.uBend()
	check(near(Region.Runway(u, vec(-130, 0, -44), vec(1, 0, 0), 1), 7), "the U-bend: east from AB2's foot stops at the void (7), never jumping to AB4 beyond it")
	check(near(Region.Runway(u, vec(-130, 0, 0), vec(1, 0, 0), 1), 29), "along AB3 across both arms' tops: 29")
	check(Region.Runway(u, vec(0, 0, 100), vec(1, 0, 0), 1) == 0, "from outside: 0")
	check(Region.Runway(u, vec(-130, 0, 0), vec(0, 0, 0), 1) == 0, "no heading: 0")

	print(" Region.Toward")
	local ellGraph = Region.Build(W4C.ell())
	local goal = vec(-5, 3, 1)
	local point, through = Region.Toward(ellGraph, vec(0, 0, 0), goal, 1)
	check(not through and point.X == -5 and point.Z == 1 and point.Y == 3, "same cell: the goal itself, false")
	local uGraph = Region.Build(W4C.uBend())
	local door, viaDoor = Region.Toward(uGraph, vec(-130, 5, -20), vec(-108, 0, -20), 1)
	check(viaDoor and near(door.X, -130) and near(door.Z, 0) and door.Y == 5, "AB2 to AB4: the AB2/AB3 door at the body's height")
	local onward, viaNext = Region.Toward(uGraph, vec(-130, 5, 0), vec(-108, 0, -20), 1)
	check(viaNext and near(onward.X, -108) and near(onward.Z, 0), "standing in the AB2/AB3 door: the next door (AB3/AB4)")
	local edge, viaEdge = Region.Toward(uGraph, vec(-130, 8, -20), vec(-130, 0, -70), 1)
	check(not viaEdge and near(edge.X, -130) and near(edge.Z, -51), "a goal below the drop: its clamped point on the region's edge, false")
	local apart = Region.Build({ { x = 0, z = 0, hx = 5, hz = 5 }, { x = 10, z = 0, hx = 5, hz = 5 } })
	local alone, viaAlone = Region.Toward(apart, vec(-2, 0, 0), vec(12, 0, 0), 1)
	check(not viaAlone and near(alone.X, 12) and near(alone.Z, 0), "disconnected: the clamped goal, false")
end
L1BC.group("region routes", W4C.routeTests)

-- CampBrain ---------------------------------------------------------------------------------------
-- A floor 60 x 60 round the origin at y 8, and a road cell (25..75, -5..5) through its east edge.
function W4C.regionDef(posture: string, points: { any }, over: any?): any
	local options: any = { region = { { x = 0, z = 0, hx = 30, hz = 30 }, { x = 50, z = 0, hx = 25, hz = 5 } } }
	for key, value in over or {} do
		options[key] = value
	end
	return L1BC.def(posture, points, options)
end

function W4C.input(now: number, members: { any }, targets: { any }?, shooters: { any }?, striking: boolean?, closing: boolean?): any
	return {
		now = now,
		members = members,
		targets = targets or {},
		shooters = shooters or {},
		striking = striking == true,
		closing = closing == true,
	}
end

-- A guard pair on the region floor at (0, -10) and (4, -10) facing -Z; fighting at `at` with a
-- player in front of them on the floor.
function W4C.guards(held: boolean?): (any, { any })
	local def = W4C.regionDef("guard", { vec(0, 8, -10), vec(4, 8, -10) }, { held = held == true })
	return W4C.CB.NewGroup(def, 0), { L1BC.member(vec(0, 8, -10), 0), L1BC.member(vec(4, 8, -10), 0) }
end

function W4C.fighting(at: number): (any, { any })
	local CB = W4C.CB
	local R = W2A.rules()
	local group, members = W4C.guards()
	local sighted = { L1BC.seen(7, 0, 10, -25) }
	CB.Step(group, W4C.input(at - 0.2, members, sighted), R)
	CB.Step(group, W4C.input(at - 0.1, members, sighted), R)
	CB.Step(group, W4C.input(at, members, sighted), R)
	return group, members
end

function W4C.chaseTests(): ()
	local CB = W4C.CB
	local R = W2A.rules()
	print(" CampBrain.Problems (Wave 4 keys)")
	check(#CB.Problems(R) == 0, "the rules with chaseSight, hitMemorySeconds and meleeAbove: no problem")
	local each = true
	for _, key in { "chaseSight", "hitMemorySeconds", "meleeAbove", "meleeBelow" } do
		each = each and #CB.Problems(W2A.rules({ [key] = 0 / 0 })) == 1 and #CB.Problems(W2A.rules({ [key] = -1 })) == 1
		local missing = W2A.rules()
		missing[key] = nil
		each = each and #CB.Problems(missing) == 1
	end
	check(each, "each new key: missing, NaN or negative is one line")
	check(#CB.Problems(W2A.rules({ chaseSight = 0 })) == 1 and #CB.Problems(W2A.rules({ meleeAbove = 0 })) == 1, "a chaseSight or a meleeAbove of 0 is a problem")
	check(#CB.Problems(W2A.rules({ hitMemorySeconds = 0 })) == 0, "a hitMemorySeconds of 0 is not (no memory)")
	check(#CB.Problems(W2A.rules({ meleeBelow = 0 })) == 0, "R14: a meleeBelow of 0 is not (the floor itself)")

	print(" CampBrain.Struck (Wave 4)")
	for _, state in { "rest", "rise", "fight", "home" } do
		local group = W4C.guards()
		group.state = state
		local landed = CB.Struck(group, 7, 12)
		check(landed and group.hit and group.hitAt[7] == 12 and group.struckBy[7] == true, `{state}: lands (true), hit, hitAt and struckBy recorded`)
	end
	local held = W4C.guards(true)
	check(CB.Struck(held, 7, 12) == false and not held.hit and held.hitAt[7] == nil and held.struckBy[7] == nil, "held: false, nothing recorded")
	local lever = W4C.guards()
	check(CB.Struck(lever, 0, 12) == true and lever.hit and next(lever.hitAt) == nil and next(lever.struckBy) == nil, "a lever's hit (byUserId 0) lands and wakes, and remembers nobody")
	check(CB.Evades(W4C.guards()) == false and CB.Evades(held) == true, "Evades: held only")

	print(" known")
	local members = { L1BC.member(vec(0, 8, 0), 0) }
	local function knowsAt(x: number, y: number, z: number): boolean
		local group = W4C.CB.NewGroup(W4C.regionDef("guard", { vec(0, 8, 0) }), 0)
		CB.Step(group, W4C.input(1, members, { L1BC.seen(7, x, y, z) }), R)
		return group.known[7] == true
	end
	check(knowsAt(40, 10, 0) and knowsAt(0, 10, -40), "chaseSight (40) from a member, all round: at the edge, known")
	check(not knowsAt(40.01, 10, 0) and not knowsAt(28.3, 10, 28.3), "past it: not")
	check(not knowsAt(10, 38.01, 0) and not knowsAt(10, 3.99, 0), "out of the band: not")
	local memory = W4C.CB.NewGroup(W4C.regionDef("guard", { vec(0, 8, 0) }), 0)
	local far = { L1BC.seen(7, 500, 10, 0) }
	CB.Struck(memory, 7, 10)
	CB.Step(memory, W4C.input(18, members, far), R)
	check(memory.known[7] == true and memory.hitAt[7] == 10, "a hit hitMemorySeconds (8) ago exactly: known")
	CB.Step(memory, W4C.input(18.01, members, far), R)
	check(memory.known[7] == nil and memory.hitAt[7] == nil, "past it: not known, and the hit is pruned")
	CB.Struck(memory, 0, 20)
	CB.Step(memory, W4C.input(20.1, members, far), R)
	check(memory.known[7] == nil and next(memory.hitAt) == nil, "a lever's hit makes nobody known")

	print(" CampBrain.Melee, Reachable")
	local def = W4C.regionDef("guard", { vec(0, 8, 0) })
	local function melee(x: number, y: number, z: number): boolean
		return CB.Melee(def, L1BC.seen(7, x, y, z), R)
	end
	check(melee(0, 15.5, 0) and not melee(0, 15.51, 0), "meleeAbove (7.5) over the floor: at the edge yes, past it no")
	check(melee(70, 10, 0) and melee(33, 10, 20), "on the road cell, and within chaseMargin (3) of the floor")
	check(melee(77.12, 10, 7.12) and not melee(77.2, 10, 7.2), "off the road cell's far corner: rounded (2.998 yes, 3.11 no)")
	check(not melee(0, 3.99, 0), "under the band: no")
	check(melee(0, 6.5, 0) and not melee(0, 6.49, 0), "R14: meleeBelow (1.5) under the floor: at the edge yes, past it no (in the band, sightBelow 4)")
	local shooters = { { at = vec(70, 8, 0), reach = 32 } }
	local function reachable(x: number, y: number, z: number, list: { any }?): boolean
		return CB.Reachable(def, L1BC.seen(7, x, y, z), list or {}, R)
	end
	check(reachable(100, 10, 0, shooters) and not reachable(100, 10, 0), "25 off the region: reachable only by the shooter's clause (30 from it, reach 32)")
	check(not reachable(100, 50, 0, { { at = vec(70, 8, 0), reach = 100 } }), "out of the band: not, whatever the reach")
	check(reachable(0, 20, 0, shooters) == false and reachable(0, 20, 0, { { at = vec(0, 8, 10), reach = 32 } }), "on a ledge over meleeAbove: only a shooter in reach")

	print(" a group with no region")
	local roomDef = L1BC.def("guard", { vec(-25, 8, -25) })
	local room = CB.NewGroup(roomDef, 0)
	CB.Step(room, W4C.input(1, { L1BC.member(vec(-25, 8, -25), 0) }, { L1BC.seen(7, 25, 10, 25) }), R)
	check(room.known[7] == true and room.reachable[7] == true, "known = reachable = in play: a player 70 from every member, in the room, stays known")
	check(CB.Melee(roomDef, L1BC.seen(7, 25, 30, 25), R) == CB.InPlay(roomDef, L1BC.seen(7, 25, 30, 25), {}, R), "Melee is InPlay (no meleeAbove cap without a region)")

	print(" the leash (Wave 4)")
	local nobody: { any } = {}
	local reach, reachList = W4C.fighting(20)
	check(reach.state == "fight" and reach.quietSince == 20 and reach.meleeQuietSince == 20 and reach.standDown == false, "(fighting at 20; both clocks at 20, not stood down)")
	CB.Struck(reach, 7, 20.5)
	CB.Step(reach, W4C.input(22, reachList, { L1BC.seen(7, 70, 10, 0) }), R)
	check(reach.quietSince == 22 and reach.reachable[7] == true, "known by its hit, on the road cell 70 away: reachable, the leash resets")
	local lost, lostList = W4C.fighting(20)
	local beyond = { L1BC.seen(7, 0, 10, -40) }
	check(CB.Step(lost, W4C.input(22.9, lostList, beyond), R) == nil and lost.known[7] == true and lost.reachable[7] == nil, "known (30 from a member) but 10 past the floor's edge: not reachable")
	check(CB.Step(lost, W4C.input(23, lostList, beyond), R) == "home" and lost.standDown == false, "known but unreachable: home at leashSeconds")
	local closing, closingList = W4C.fighting(20)
	CB.Step(closing, W4C.input(22, closingList, beyond, nil, false, true), R)
	CB.Step(closing, W4C.input(24, closingList, beyond, nil, false, true), R)
	check(closing.state == "fight" and closing.quietSince == 24 and closing.meleeQuietSince == 24 and not closing.standDown, "a rusher closing holds both clocks (fighting at 24, 4 s on)")
	check(CB.Step(closing, W4C.input(26.9, closingList, beyond), R) == nil and CB.Step(closing, W4C.input(27, closingList, beyond), R) == "home", "and the leash runs from the last closing step: home at 27")
	local striking, strikingList = W4C.fighting(20)
	check(CB.Step(striking, W4C.input(23, strikingList, beyond, nil, true), R) == nil and striking.state == "fight", "striking holds it")
	check(CB.Step(striking, W4C.input(23.1, strikingList, beyond), R) == "home", "and home once nobody strikes")

	print(" the stand-down")
	local ledge = { L1BC.seen(7, 0, 20, -12) }
	local ledgeShooters = { { at = vec(4, 8, -10), reach = 32 } }
	local stand, standList = W4C.fighting(20)
	CB.Step(stand, W4C.input(21, standList, ledge, ledgeShooters, false, true), R)
	check(stand.state == "fight" and stand.meleeQuietSince == 21 and not stand.standDown, "a player on a ledge the shooter reaches: still fighting; closing holds the melee clock")
	check(CB.Step(stand, W4C.input(23.9, standList, ledge, ledgeShooters), R) == nil and not stand.standDown, "2.9 s after the last closing: not yet")
	check(CB.Step(stand, W4C.input(24, standList, ledge, ledgeShooters), R) == nil and stand.standDown and stand.state == "fight", "at leashSeconds the rushers stand down; the group still fights (no event)")
	check(CB.StandsDown(stand, true) and not CB.StandsDown(stand, false), "StandsDown: a rusher yes, a shooter no")
	local post = { at = vec(0, 8, -10), yaw = 0, leg = 0 }
	local resident = { group = 1, post = post, leg = 0 }
	local walk, pace = CB.Goal(stand, resident, vec(0, 8, -20), R)
	check(walk == post.at and pace == R.homePace, "Goal while stood down: its post at homePace")
	check(CB.Shows(stand, false) == "idle" and CB.Shows(stand, true) == "move", "Shows while stood down: idle or move")
	CB.Step(stand, W4C.input(25, standList, ledge, ledgeShooters, false, true), R)
	check(stand.standDown, "closing does not clear a stand-down")
	CB.Step(stand, W4C.input(26, standList, { L1BC.seen(7, 0, 10, -25) }, ledgeShooters), R)
	check(not stand.standDown and stand.meleeQuietSince == 26, "a known player who becomes melee-reachable clears it at once")
	CB.Step(stand, W4C.input(26.5, standList, ledge, ledgeShooters), R)
	CB.Step(stand, W4C.input(29.5, standList, ledge, ledgeShooters), R)
	check(stand.standDown and stand.state == "fight", "(stood down again 3 s on)")
	check(CB.Step(stand, W4C.input(32.4, standList, ledge, nil), R) == nil and CB.Step(stand, W4C.input(32.5, standList, ledge, nil), R) == "home" and not stand.standDown, "when the shooters lose him too, the leash sends the whole group home")
	local unheld = W4C.guards(true)
	unheld.state = "fight"
	unheld.standDown = true
	check(not CB.StandsDown(unheld, true), "a held group never stands down")

	print(" home (Wave 4)")
	local function homeward(): (any, { any })
		local group, list = W4C.fighting(40)
		CB.Step(group, W4C.input(43, list, nobody), R)
		return group, list
	end
	local hitBack, hitList = homeward()
	check(hitBack.state == "home", "(walking home at 43)")
	local behind = { L1BC.seen(7, 0, 10, 20) }
	CB.Struck(hitBack, 7, 43.5)
	check(CB.Step(hitBack, W4C.input(44, hitList, behind), R) == "fight" and hitBack.quietSince == 44 and hitBack.meleeQuietSince == 44 and not hitBack.standDown, "a reachable player's hit (behind the guards, unseen) turns it straight back to fight")
	local seenBack, seenList = homeward()
	check(CB.Step(seenBack, W4C.input(44, seenList, { L1BC.seen(7, 0, 10, -25) }), R) == "fight", "a reachable player seen by a member: straight back to fight (never a rise)")
	local walkOn, walkList = homeward()
	local away = { walkList[1], { at = vec(4, 8, -20), post = walkList[2].post } }
	CB.Struck(walkOn, 7, 43.5)
	check(CB.Step(walkOn, W4C.input(44, away, { L1BC.seen(7, 0, 10, -60) }), R) == nil and walkOn.state == "home" and walkOn.hitAt[7] == 43.5, "an unreachable player's hit lands and is remembered, but does not turn it back")
	check(CB.Step(walkOn, W4C.input(45, walkList, nobody), R) == "rest", "every member at its post, nobody reachable: rest")

	print(" CampBrain.Forget")
	local rising, risingList = W4C.guards()
	CB.Step(rising, W4C.input(1, risingList, { L1BC.seen(7, 0, 10, -25) }), W2A.rules({ guard = { sight = 30, cone = 140, rise = 5 } }))
	check(rising.state == "rise", "(a group rising)")
	CB.Struck(rising, 7, 1)
	check(CB.Forget(rising, 2) == "home" and rising.state == "home" and rising.since == 2 and next(rising.hitAt) == nil and next(rising.known) == nil and next(rising.reachable) == nil, "rise: home, since now, every set and memory cleared")
	local fight = W4C.fighting(10)
	fight.standDown = true
	check(CB.Forget(fight, 11) == "home" and fight.state == "home" and fight.standDown == false, "fight: home, not stood down")
	local homeGroup = homeward()
	CB.Struck(homeGroup, 7, 44)
	check(CB.Forget(homeGroup, 45) == nil and homeGroup.state == "home" and next(homeGroup.hitAt) == nil and next(homeGroup.struckBy) == nil, "home: only forgets")
	local resting = W4C.guards()
	check(CB.Forget(resting, 1) == nil and resting.state == "rest", "rest: only forgets")
	local heldGroup = W4C.guards(true)
	check(CB.Forget(heldGroup, 1) == nil and heldGroup.state == "rest" and heldGroup.held, "held: nothing")

	print(" Rouse and TentRouse (the reachable argument)")
	local roused = W4C.guards()
	check(CB.Rouse(roused, 3, false) and roused.state == "rise", "Rouse from rest: whatever the argument")
	local tentHome = homeward()
	check(not CB.TentRouse(tentHome, 50, false) and CB.TentRouse(tentHome, 50, true) and tentHome.state == "rise", "TentRouse from home: only with a reachable player")
end
L1BC.group("chase", W4C.chaseTests)

function W4C.tentTests(): ()
	local CB = W4C.CB
	print(" CampBrain.TentClock, Ahead, TentActive")
	local tent = CB.NewTent(4, 10)
	check(tent.busySeconds == 0 and tent.lastAt == nil and tent.residents == 10, "NewTent: the pace clock at 0, stopped, counting from the zone's residents")
	CB.TentClock(tent, true, 10, false, 10)
	check(tent.busySeconds == 0 and tent.lastAt == 10, "the first busy tick starts it, adding nothing")
	CB.TentClock(tent, true, 10.5, false, 10)
	check(near(tent.busySeconds, 0.5) and tent.lastAt == 10.5, "busy to busy: the time between")
	CB.TentClock(tent, false, 11, false, 10)
	check(near(tent.busySeconds, 0.5) and tent.lastAt == nil, "a quiet tick adds nothing and stops it")
	CB.TentClock(tent, false, 20, false, 10)
	CB.TentClock(tent, true, 30, false, 10)
	check(near(tent.busySeconds, 0.5) and tent.lastAt == 30, "the gap with a group walking home is never counted, nor restarted")
	CB.TentClock(tent, true, 31, false, 10)
	check(near(tent.busySeconds, 1.5) and tent.residents == 10, "busy again: counted from the first busy tick")

	-- R7: the measure starts afresh whenever every group of the camp is back at rest.
	local chased = CB.NewTent(8, 10)
	for t = 0, 20 do
		CB.TentClock(chased, true, t, false, 10)
	end
	local fifteen = { seconds = 15, lead = 0.2 }
	check(near(chased.busySeconds, 20) and not CB.Ahead(chased.residents - 6, chased.residents, chased.busySeconds, fifteen), "(R7: 20 s chased out and lost with no kill: four kills of ten no longer put the camp ahead)")
	CB.TentClock(chased, false, 21, false, 10)
	check(near(chased.busySeconds, 20), "R7: walking home (not at rest) keeps the measure")
	CB.TentClock(chased, false, 30, true, 9)
	check(chased.busySeconds == 0 and chased.lastAt == nil and chased.residents == 9, `R7: every group back at rest: busy time 0, counted from the 9 residents alive (busy {chased.busySeconds}, residents {chased.residents})`)
	CB.TentClock(chased, true, 40, false, 9)
	CB.TentClock(chased, true, 42, false, 5)
	check(near(chased.busySeconds, 2) and CB.Ahead(chased.residents - 5, chased.residents, chased.busySeconds, fifteen), "R7: then a fast clear (four of nine in 2 s) is ahead again, as in a fresh camp")
	check(not CB.Ahead(chased.residents - 7, chased.residents, chased.busySeconds, fifteen), "(two of nine in 2 s is not: 0.22 - 0.13 < 0.2)")
	CB.TentClock(chased, true, 43, true, 5)
	check(chased.busySeconds == 0 and chased.residents == 5, "R7: rested wins over a busy flag (the caller's sets cannot both hold, the rule is still one)")
	local pace = { seconds = 25, lead = 0.15 }
	check(CB.Ahead(5, 10, 8.75, pace) and not CB.Ahead(5, 10, 8.76, pace), "Ahead at lead exactly (0.5 - 8.75/25 = 0.15): yes; a hair behind: no")
	check(not CB.Ahead(0, 0, 0, pace) and not CB.Ahead(1, 0, 0, pace), "no residents: never ahead (a stray kill does not divide by 0)")
	check(not CB.Ahead(5, 10, 0, { seconds = 0, lead = 0 }), "pace.seconds 0: never ahead")
	check(CB.Ahead(0, 10, 0, { seconds = 25, lead = 0 }) and not CB.Ahead(0, 10, 0.01, { seconds = 25, lead = 0 }), "lead 0: ahead only before any busy time with no kill")
	local table8 = ""
	for _, busy in { false, true } do
		for _, alive in { 0, 3 } do
			for _, ahead in { false, true } do
				table8 ..= if CB.TentActive(busy, alive, ahead) then "1" else "0"
			end
		end
	end
	check(table8 == "00000001", `TentActive's truth table: only busy, a resident alive and ahead ({table8})`)
end
L1BC.group("tent pace", W4C.tentTests)

-- CrowdService with a region floor ----------------------------------------------------------------
-- Floor 1 at y 8, 20 x 20 round the origin, with a U-shaped region round a void: the floor, a road
-- east (5..30, -3..3), a leg north (24..30, -3..27) and a leg back west (14..30, 21..27). Floor 2 at
-- y 12 round (200, 0), 60 x 60, with no region.
function W4C.uCells(): { any }
	return {
		{ x = 0, z = 0, hx = 10, hz = 10 },
		{ x = 17.5, z = 0, hx = 12.5, hz = 3 },
		{ x = 27, z = 12, hx = 3, hz = 15 },
		{ x = 22, z = 24, hx = 8, hz = 3 },
	}
end

function W4C.enter(): any
	local graph = W4C.Region.Build(W4C.uCells())
	check(
		Crowd.SetFloors({
			{ centre = vec(0, 8, 0), half = vec(10, 200, 10), region = graph },
			{ centre = vec(200, 12, 0), half = vec(30, 200, 30) },
		}) == true,
		"(a region floor and a plain one)"
	)
	Crowd.SetCampRules(W2A.rules())
	return graph
end

-- A group of `kinds` on floor 1 with the region's cells on its def (posts at `points`).
function W4C.place(posture: string, points: { any }, kinds: { string }, over: any?): (number, { number }, any)
	local options: any = { rect = { x = 0, z = 0, hx = 10, hz = 10 }, region = W4C.uCells() }
	for key, value in over or {} do
		options[key] = value
	end
	return W2A.place(posture, points, kinds, options)
end

function W4C.flat(id: number, x: number, z: number): number
	local body = Crowd.Get(id)
	if body == nil then
		return math.huge
	end
	return math.sqrt((body.position.X - x) ^ 2 + (body.position.Z - z) ^ 2)
end

function W4C.untilEvent(group: number, to: string, limit: number): number?
	for count = 1, limit do
		step2()
		for _, event in L1BC.events() do
			if event.group == group and event.to == to then
				return count
			end
		end
	end
	return nil
end

function W4C.crowdTests(): ()
	print(" CrowdService: a region floor")
	local graph = W4C.enter()
	local cells = graph.cells
	-- Off its floor onto the road, and not pulled back.
	root.Position = vec(26, 11, 0)
	local group, ids = W4C.place("guard", { vec(5, 8, 0) }, { "fodder" }, { yaw = -math.pi / 2 })
	step2(45)
	local body = Crowd.Get(ids[1])
	check(body ~= nil and body.position.X > 15 and W4C.Region.Distance(cells, body.position.X, body.position.Z) == 0, `a fighting fodder follows its player off the floor onto the road cell (x {if body then body.position.X else "?"})`)
	step2(15)
	check(Crowd.Get(ids[1]).position.X > 15, "and is not pulled back to its floor's rectangle")
	local _ = group

	-- Across the void: the straight line leaves the region; the route goes round through the doors.
	fresh()
	graph = W4C.enter()
	cells = graph.cells
	root.Position = vec(17, 11, 24)
	local _, round = W4C.place("guard", { vec(5, 8, 8) }, { "fodder" }, { yaw = math.pi })
	local onUnion = true
	local arrived = nil
	for count = 1, 150 do
		step2()
		local now = Crowd.Get(round[1])
		if now == nil then
			break
		end
		onUnion = onUnion and W4C.Region.Distance(cells, now.position.X, now.position.Z) == 0
		if arrived == nil and W4C.flat(round[1], 17, 24) <= 5.5 then
			arrived = count
		end
	end
	check(arrived ~= nil, `a fodder whose player is across a void walks round through the doors and arrives (step {arrived})`)
	check(onUnion, "and never leaves the region on the way")

	-- A floor with no region keeps its rectangle.
	local plain = Crowd.Spawn("pawn", vec(260, 12, 0), "idle", nil, nil, 2)
	local inRegion = Crowd.Spawn("pawn", vec(20, 8, 0), "idle", nil, nil, 1)
	step2()
	check(near(Crowd.Get(plain).position.X, 228.7) and near(Crowd.Get(inRegion).position.X, 20), "a body of the plain floor is clamped to its rectangle (228.7); one of the region floor stands on the road (20)")

	-- Damage from a player out of play lands and wakes; a held group still says blocked.
	fresh()
	W4C.enter()
	root.Position = vec(0, 11, -300)
	local open, openIds = W4C.place("guard", { vec(-5, 8, -5) }, { "fodder" })
	local _, heldIds = W4C.place("guard", { vec(5, 8, -5) }, { "fodder" }, { held = true })
	step2(2)
	local dealt, _, verdict = Crowd.Damage(openIds[1], 10, 7, nil, nil)
	check(dealt == 10 and verdict == nil and Crowd.Get(openIds[1]).hp == 30, "a hit from a player 300 away, out of play, lands")
	step2()
	local woke = L1BC.events()
	check(#woke >= 1 and woke[1].group == open and woke[1].to == "rise", "and wakes the group")
	local heldDealt, _, heldVerdict = Crowd.Damage(heldIds[1], 10, 7, nil, nil)
	check(heldDealt == 0 and heldVerdict == "blocked" and Crowd.Get(heldIds[1]).hp == 40, "a held group still answers blocked")
end
L1BC.crowdGroup("region floor", W4C.crowdTests)

function W4C.standDownTests(): ()
	print(" CrowdService: the stand-down, closing")
	W4C.enter()
	-- A player on a ledge over the floor: 12 over it (meleeAbove 7.5), in the band.
	root.Position = vec(0, 20, -4)
	local group, ids = W4C.place("guard", { vec(-6, 8, 6), vec(6, 8, 6) }, { "fodder", "slinger" })
	step2(2)
	Crowd.Damage(ids[1], 10, 7, nil, nil)
	local fought = W4C.untilEvent(group, "fight", 10)
	check(fought ~= nil and Crowd.Get(ids[1]).hp == 30, "(the pair wakes on the hit and fights; the fodder is hurt)")
	-- The fodder walks under the ledge, finds it cannot reach and stands down; the slinger fights.
	local slingerWound = false
	local fodderHome = false
	local healed = false
	local stateEvents = 0
	for _ = 1, 200 do
		step2()
		stateEvents += #L1BC.events()
		local state = seen(ids[2]).state
		slingerWound = slingerWound or state == "windup"
		local fodder = Crowd.Get(ids[1])
		if fodder ~= nil and W4C.flat(ids[1], -6, 6) <= 1 then
			fodderHome = true
			healed = healed or fodder.hp == 40
		end
	end
	check(fodderHome, "while stood down the rusher walks back to its post")
	check(healed, "and is healed there")
	check(slingerWound, "while its slinger keeps shooting at the player on the ledge")
	check(stateEvents == 0 and Crowd.Busy()[1] == true, "the group stays in fight: no event, its floor busy")
	check(Crowd.Engaged(7), "the player the slinger reaches is engaged")

	-- closing: a rusher still walking toward the region's edge holds the leash; a shooter does not.
	fresh()
	W4C.enter()
	root.Position = vec(75, 11, 0)
	local rush, rushIds = W4C.place("guard", { vec(-5, 8, 0) }, { "fodder" }, { yaw = -math.pi / 2 })
	step2(2)
	Crowd.Damage(rushIds[1], 1, 7, nil, nil)
	local toFight = W4C.untilEvent(rush, "fight", 10) or 0
	step2()
	check(not Crowd.Engaged(7), "a player the group knows (by his hit) but cannot reach is not engaged")
	local toHome = W4C.untilEvent(rush, "home", 300)
	toHome = if toHome ~= nil then toHome + 1 else nil
	check(toHome ~= nil and toHome * (1 / 15) >= 4.5, `a rusher walking to the edge (34 studs) holds the leash: home {if toHome then string.format("%.2f", toHome / 15) else "never"} s after the fight began (3 s without closing)`)
	check(W4C.flat(rushIds[1], 28.7, 0) <= 1.5 or toHome == nil, "(it had reached the road's end nearest its player)")
	local _ = toFight
	fresh()
	W4C.enter()
	root.Position = vec(75, 11, 0)
	local shoot, shootIds = W4C.place("guard", { vec(-5, 8, 0) }, { "slinger" }, { yaw = -math.pi / 2 })
	step2(2)
	Crowd.Damage(shootIds[1], 1, 7, nil, nil)
	W4C.untilEvent(shoot, "fight", 10)
	local shooterHome = W4C.untilEvent(shoot, "home", 300)
	check(shooterHome ~= nil and shooterHome <= 46 and shooterHome >= 44, `a shooter walking toward the player sets no closing stamp: home at leashSeconds ({shooterHome} steps)`)
end
L1BC.crowdGroup("stand-down", W4C.standDownTests)

function W4C.forgetTests(): ()
	print(" CrowdService: ForgetOthers, SetFloors' region, a lane through a door")
	W4C.enter()
	-- Out of every group's sight and reach: each is woken and kept knowing him by a hit alone.
	root.Position = vec(0, 11, -60)
	local west, westIds = W4C.place("guard", { vec(-5, 8, 5) }, { "fodder" })
	local east, eastIds = W2A.place("guard", { vec(200, 12, 5) }, { "fodder" }, { floor = 2, floorY = 12, rect = { x = 200, z = 0, hx = 30, hz = 30 } })
	step2(2)
	Crowd.Damage(westIds[1], 1, 7, nil, nil)
	Crowd.Damage(eastIds[1], 1, 7, nil, nil)
	step2(3)
	L1BC.events()
	Crowd.ForgetOthers(2)
	step2()
	local events = L1BC.events()
	local westHome = 0
	local eastChanged = 0
	for _, event in events do
		if event.group == west and event.to == "home" and event.from == "fight" then
			westHome += 1
		elseif event.group == east then
			eastChanged += 1
		end
	end
	check(westHome == 1, `ForgetOthers(2): the other floor's fighting group goes home at the next step with one event ({#events} events)`)
	check(eastChanged == 0 and Crowd.Busy()[2] == true, "and its own floor's group is left fighting")
	step2(5)
	local turned = false
	for _, event in L1BC.events() do
		turned = turned or (event.group == west and (event.to == "fight" or event.to == "rise"))
	end
	check(not turned, "the forgotten group walks on home: its hit memory is gone")

	fresh()
	local graph = W4C.Region.Build(W4C.uCells())
	check(Crowd.SetFloors({ { centre = vec(0, 8, 0), half = vec(10, 200, 10), region = graph } }) == true, "SetFloors keeps a region")
	local onRoad = Crowd.Spawn("pawn", vec(20, 8, 0), "idle")
	step2()
	check(near(Crowd.Get(onRoad).position.X, 20), "(a body on the road stays there)")
	fresh()
	check(Crowd.SetFloors({ { centre = vec(0, 8, 0), half = vec(10, 200, 10), region = { cells = {}, next = {}, hops = {}, doors = {} } } }) == true, "a malformed region does not refuse the floor")
	local clamped = Crowd.Spawn("pawn", vec(20, 8, 0), "idle")
	step2()
	check(near(Crowd.Get(clamped).position.X, 8.7), "but is dropped (warned): the floor keeps its rectangle (8.7)")
	fresh()
	check(Crowd.SetFloors({ { centre = vec(0, 8, 0), half = vec(10, 200, 10), region = { cells = { { x = 0 / 0, z = 0, hx = 1, hz = 1 } }, next = {}, hops = {}, doors = {} } } }) == true, "(a non-finite cell)")
	local clampedToo = Crowd.Spawn("pawn", vec(20, 8, 0), "idle")
	step2()
	check(near(Crowd.Get(clampedToo).position.X, 8.7), "is dropped too")

	-- A shooter backing away on the road keeps to the region, not to its floor's rectangle.
	fresh()
	W4C.enter()
	root.Position = vec(12, 11, 0)
	local backer = Crowd.Spawn("slinger", vec(20, 8, 0), "fight", nil, nil, 1)
	step2(15)
	check(Crowd.Get(backer).position.X > 24, `a slinger too close to its player backs away down the road (x {Crowd.Get(backer).position.X}), not toward the floor`)
	check(Crowd.AddGroup(L1BC.def("guard", { vec(0, 8, 0) }, { region = {} })) == 0 and Crowd.AddGroup(L1BC.def("guard", { vec(0, 8, 0) }, { region = { { x = 0 / 0, z = 0, hx = 1, hz = 1 } } })) == 0, "AddGroup refuses an empty or non-finite region")

	-- A brute's charge from the floor runs on through the door down the road.
	fresh()
	W4C.enter()
	table.clear(struck)
	root.Position = vec(25, 11, 0)
	local brute = Crowd.Spawn("brute", vec(-4, 8, 0), "fight", nil, nil, 1)
	local lane = nil
	for _ = 1, 120 do
		step2()
		for _, strike in struck do
			if strike.bodyId == brute and strike.length ~= nil then
				lane = strike
			end
		end
		if lane ~= nil then
			break
		end
	end
	local feetX = if lane ~= nil and lane.feet ~= nil then lane.feet.X else 0
	check(lane ~= nil and lane.length > 7.8 - feetX + 1 and near(lane.length, math.min(30, 27.8 - feetX), 1e-6), `its lane runway crosses the door to the road's inset end (27.8): length {if lane then lane.length else "none"} from x {feetX}`)
	local _ = east
end
L1BC.crowdGroup("forget, floors, lane", W4C.forgetTests)

-- The fix round (docs/prompts/l1b-w4-fix-round.md) -----------------------------------------------
-- Four fodder at their posts, two each side of the floor's centre line, facing the road east.
function W4C.fourPosts(): { any }
	return { vec(-6, 8, -6), vec(-6, 8, 6), vec(6, 8, -6), vec(6, 8, 6) }
end

-- Steps until `group` sends an event to `to` (the step count) or `limit` steps pass (nil); every
-- `every` steps the player hits `id` for 1 (by userId 7), as a sniper keeping himself known.
function W4C.hittingUntil(group: number, to: string, limit: number, id: number, every: number): number?
	for count = 1, limit do
		if count % every == 0 and Crowd.Get(id) ~= nil then
			Crowd.Damage(id, 1, 7, nil, nil)
		end
		step2()
		for _, event in L1BC.events() do
			if event.group == group and event.to == to then
				return count
			end
		end
	end
	return nil
end

-- R1: closing is progress. Four rushers pressed on one clamped point at the road's end seek it at
-- full speed for ever; only progress, not the wish to move, holds the leash and the stand-down.
function W4C.closingTests(): ()
	print(" fix round R1: closing means progress")
	W4C.enter()
	-- (a) A hitter below the road's end: 5 under the floor (out of the band), 11.3 flat past the
	-- inset end (28.7), past a fodder's reach. Known by his hits alone, every 4 s.
	root.Position = vec(40, 3, 0)
	local group, ids = W4C.place("guard", W4C.fourPosts(), { "fodder", "fodder", "fodder", "fodder" }, { yaw = -math.pi / 2 })
	step2(2)
	Crowd.Damage(ids[1], 1, 7, nil, nil)
	check(W4C.untilEvent(group, "fight", 10) ~= nil, "(R1 a: four fodder woken by the hitter's hit)")
	local home = W4C.hittingUntil(group, "home", 225, ids[1], 60)
	-- About 2.9 s to walk the 35 studs to the road's end, then leashSeconds (3) without progress.
	check(home ~= nil and home >= 75 and home <= 120, `R1 a: four rushers pressed at the road's end above a hitter they cannot reach go home within leash + a margin (step {home or "never"}, 75 to 120)`)
	local packed = 0
	for _, id in ids do
		if W4C.flat(id, 28.7, 0) <= 4 then
			packed += 1
		end
	end
	check(home == nil or packed == 4, `(they had all reached the road's end first: {packed} of 4)`)
	check(W4C.hittingUntil(group, "fight", 45, ids[1], 15) == nil, "and his hits do not turn the homeward group back")

	-- (b) A player 12 over the floor (meleeAbove 7.5), 5.6 flat past the inset end, whom the slinger
	-- reaches: the group fights on, and the rushers stand down and walk to their posts.
	fresh()
	W4C.enter()
	root.Position = vec(34.3, 20, 0)
	local points = W4C.fourPosts()
	table.insert(points, vec(0, 8, 0))
	local mixed, mixedIds = W4C.place("guard", points, { "fodder", "fodder", "fodder", "fodder", "slinger" }, { yaw = -math.pi / 2 })
	step2(2)
	Crowd.Damage(mixedIds[1], 1, 7, nil, nil)
	check(W4C.untilEvent(mixed, "fight", 10) ~= nil, "(R1 b: the group woken)")
	local posts = L1BC.CB.Posts(L1BC.def("guard", points, { yaw = -math.pi / 2 }), 5)
	local reachedEdge = false
	local backAt: number? = nil
	local left = false
	for count = 1, 240 do
		step2()
		for _, event in L1BC.events() do
			left = left or (event.group == mixed and event.to == "home")
		end
		local atEdge = 0
		local atPost = 0
		for k = 1, 4 do
			if W4C.flat(mixedIds[k], 28.7, 0) <= 4 then
				atEdge += 1
			end
			if W4C.flat(mixedIds[k], posts[k].at.X, posts[k].at.Z) <= 1 then
				atPost += 1
			end
		end
		reachedEdge = reachedEdge or atEdge == 4
		if reachedEdge and atPost == 4 then
			backAt = count
			break
		end
	end
	-- About 2.9 s out, 3 s without progress, 2.9 s back at homePace 1.
	check(reachedEdge and backAt ~= nil and backAt <= 165, `R1 b: four rushers pressed at the edge under a player they cannot reach stand down and are back at their posts within leash + a margin (step {backAt or "never"}, at most 165)`)
	check(not left, "while the slinger reaches him the group stays in fight")
end
L1BC.crowdGroup("fix round: closing", W4C.closingTests)

-- R2: the close lets a blow finish. A guard winding up at its post when ForgetOthers sends its
-- group home finishes the blow, rests only after it, and holds no fodder place against the player.
function W4C.blowTests(): ()
	print(" fix round R2: the close lets a blow finish")
	W4C.enter()
	-- Two free fodder on floor 2, past their spawn grace before the player comes to them.
	local free = { Crowd.Spawn("fodder", vec(190, 12, -3), "fight", nil, nil, 2), Crowd.Spawn("fodder", vec(190, 12, 3), "fight", nil, nil, 2) }
	root.Position = vec(-1, 11, 0)
	local group, ids = W4C.place("guard", { vec(-5, 8, 0) }, { "fodder" }, { yaw = -math.pi / 2 })
	local windup = false
	for _ = 1, 60 do
		step2()
		if seen(ids[1]).state == "windup" then
			windup = true
			break
		end
	end
	check(windup, "(R2: the guard winds up at its post at a player in front of it)")
	L1BC.events()
	Crowd.ForgetOthers(2)
	root.Position = vec(200, 15, 0)
	local homeAt: number? = nil
	local restAt: number? = nil
	local both = 0
	for count = 1, 150 do
		step2()
		for _, event in L1BC.events() do
			if event.group == group and event.to == "home" then
				homeAt = homeAt or count
			elseif event.group == group and event.to == "rest" then
				restAt = restAt or count
			end
		end
		local striking = 0
		for _, id in free do
			local state = seen(id).state
			if state == "windup" or state == "attack" then
				striking += 1
			end
		end
		both = math.max(both, striking)
	end
	check(homeAt == 1, `the close sends the striking group home at the next step (step {homeAt or "never"})`)
	-- windup 0.5 and strikeSeconds 0.2 from its start: about 10 steps.
	check(restAt ~= nil and restAt >= 6, `R2: it rests only once the blow is done, though the guard stood at its post (step {restAt or "never"}, at least 6)`)
	check(both == 2, `R2: no frozen mind holds a fodder place: both free fodder strike the player at once (at most {both} of perPlayer 2)`)
end
L1BC.crowdGroup("fix round: the blow", W4C.blowTests)

-- Steps until the body `id` stands within 1 of (x, z) with `hp` (the step count), or nil.
function W4C.untilAt(id: number, x: number, z: number, hp: number, limit: number): number?
	for count = 1, limit do
		step2()
		local body = Crowd.Get(id)
		if body ~= nil and W4C.flat(id, x, z) <= 1 and body.hp == hp then
			return count
		end
	end
	return nil
end

-- R4: a stood-down rusher is healed once at its post; a hit after that stays, and the latch is
-- cleared only when the stand-down is.
function W4C.healOnceTests(): ()
	print(" fix round R4: heal once at the post")
	W4C.enter()
	root.Position = vec(0, 20, -4)
	local group, ids = W4C.place("guard", { vec(-6, 8, 6), vec(6, 8, 6) }, { "fodder", "slinger" })
	step2(2)
	Crowd.Damage(ids[1], 10, 7, nil, nil)
	check(W4C.untilEvent(group, "fight", 10) ~= nil, "(R4: the pair fights the player on the ledge)")
	local first = W4C.untilAt(ids[1], -6, 6, 40, 200)
	check(first ~= nil, "(the fodder stands down, walks to its post and is healed there)")
	Crowd.Damage(ids[1], 10, 7, nil, nil)
	step2(30)
	local left = false
	for _, event in L1BC.events() do
		left = left or event.group == group
	end
	check(Crowd.Get(ids[1]).hp == 30 and W4C.flat(ids[1], -6, 6) <= 1 and not left, `R4: a hit on it at its post while its slinger fights stays for 2 s (hp {Crowd.Get(ids[1]).hp}, 30): healed once, not every step`)
	-- Melee-reachable again (on the floor beside it): the stand-down clears, and with it the latch.
	root.Position = vec(-6, 11, 1)
	step2(20)
	root.Position = vec(0, 20, -4)
	local second = W4C.untilAt(ids[1], -6, 6, 40, 200)
	check(second ~= nil, `R4: stood down again, it is healed again on arriving at its post (step {second or "never"})`)
end
L1BC.crowdGroup("fix round: heal once", W4C.healOnceTests)

-- R6: no hit through a cliff. Every ground shape has the lob's lower bound: feet more than its
-- height under the crowd's floor (a player at the foot of a drop below a region's lip) are missed.
-- tests.luau's arc and lunge stand on floorY 0, the root 3 over the feet.
function W4C.cliffTests(): ()
	print(" fix round R6: no hit through a cliff")
	fresh()
	root.Position = vec(0, 3 - 8, 0)
	hooks.impact(arc(fakeNow))
	advance(0.25)
	check(humanoid.Health == 130, `R6: an arc misses feet 8 under the crowd's floor, inside its plan (health {humanoid.Health})`)
	hooks.impact(lunge(fakeNow))
	advance(0.25)
	check(humanoid.Health == 130, `R6: so does a lunge (feet 8 under, height 5) (health {humanoid.Health})`)
	root.Position = vec(0, 3 - 6, 0)
	hooks.impact(arc(fakeNow))
	advance(0.25)
	check(humanoid.Health == 100, `R6: feet exactly the arc's height (6) under its floor are still hit (health {humanoid.Health}, 100)`)
	root.Position = vec(0, 3 - 5.1, 0)
	advance(1)
	hooks.impact(lunge(fakeNow))
	advance(0.25)
	check(humanoid.Health == 100, `R6: feet 5.1 under a height-5 lunge's floor: missed (health {humanoid.Health})`)
	fresh()
end
L1BC.group("fix round: cliff", W4C.cliffTests)

-- R7: CrowdService.Stirred, the floors whose camp is not wholly at rest (TentClock's `rested` is
-- its absence): a group in rise, fight or home with a living member, never a held one.
function W4C.stirredTests(): ()
	print(" fix round R7: Stirred")
	W4C.enter()
	root.Position = vec(40, 3, 0)
	local group, ids = W4C.place("guard", { vec(-5, 8, 0) }, { "fodder" }, { yaw = -math.pi / 2 })
	W2A.place("guard", { vec(200, 12, 5) }, { "fodder" }, { floor = 2, floorY = 12, rect = { x = 200, z = 0, hx = 30, hz = 30 }, held = true })
	step2(2)
	check(Crowd.Stirred()[1] == nil and Crowd.Stirred()[2] == nil, "R7: every group at rest (one held): no floor is stirred")
	Crowd.Damage(ids[1], 1, 7, nil, nil)
	W4C.untilEvent(group, "fight", 10)
	check(Crowd.Stirred()[1] == true and Crowd.Busy()[1] == true and Crowd.Stirred()[2] == nil, "a fighting group stirs its floor; the held one does not")
	local home = W4C.untilEvent(group, "home", 200)
	check(home ~= nil and Crowd.Stirred()[1] == true and Crowd.Busy()[1] == nil, "R7: walking home it is not busy, but still stirred (its camp is not back at rest)")
	local rested = W4C.untilEvent(group, "rest", 200)
	check(rested ~= nil and Crowd.Stirred()[1] == nil, "back at rest: not stirred")
	Crowd.Damage(ids[1], 1, 7, nil, nil)
	W4C.untilEvent(group, "fight", 10)
	Crowd.Damage(ids[1], 100000, 7, nil, nil)
	step2(2)
	check(Crowd.Stirred()[1] == nil, "a group with no living member stirs nothing")
end
L1BC.crowdGroup("fix round: stirred", W4C.stirredTests)

-- R5: a brute walks round the U-bend. On the road east (inset z -0.8..0.8 for its 2.2) with its
-- player 20.7 away on the leg west across the void, its lane would run 0.8: it does not start
-- one, walks round by the doors (27, 0) and (27, 24), and charges once the region gives it the run.
function W4C.uBendBruteTests(): ()
	print(" fix round R5: a brute walks round the U-bend")
	W4C.enter()
	table.clear(struck)
	root.Position = vec(18, 11, 21.5)
	local brute = Crowd.Spawn("brute", vec(18, 8, 0.8), "fight", nil, nil, 1)
	local shortLane: any = nil
	local round: number? = nil
	for count = 1, 120 do
		step2()
		for _, strike in struck do
			if strike.bodyId == brute and strike.length ~= nil and shortLane == nil then
				shortLane = strike
			end
		end
		table.clear(struck)
		if round == nil and W4C.flat(brute, 27, 24) <= 2 then
			round = count
		end
	end
	check(shortLane == nil, `R5: across the void it starts no lane (one of {if shortLane then string.format("%.1f", shortLane.length) else "-"} studs from z {if shortLane and shortLane.feet then string.format("%.1f", shortLane.feet.Z) else "-"})`)
	check(round ~= nil, `R5: it walks round by the doors to the leg west's door (step {round or "never"})`)
	-- On the leg west's line, 9 away: the region gives the lane its run (10.8 to the inset end).
	root.Position = vec(18, 11, 24)
	local lane: any = nil
	for _ = 1, 60 do
		step2()
		for _, strike in struck do
			if strike.bodyId == brute and strike.length ~= nil then
				lane = strike
			end
		end
		if lane ~= nil then
			break
		end
	end
	check(lane ~= nil and lane.length >= 9 - 5, `R5: with the run there, it charges (length {if lane then string.format("%.1f", lane.length) else "none"})`)
end
L1BC.crowdGroup("fix round: the U-bend brute", W4C.uBendBruteTests)

-- R14: a player at the foot of a drop below the lip. Four fodder at the road's end over a hitter
-- 8 under the floor (root 5 under), 2.3 flat past their inset end, within a lunge's flat reach:
-- no blow is begun at him (the lunge could not hit feet 8 under, R6), so nothing holds the leash.
-- (a) He is out of the band (sightBelow 4), known by his hits. (b) With sightBelow 6 he is in the
-- band and seen, and meleeBelow (1.5) keeps him out of the rushers' reach.
function W4C.footTests(): ()
	print(" fix round R14: the foot of the climb")
	for _, part in { "a", "b" } do
		fresh()
		W4C.enter()
		if part == "b" then
			Crowd.SetCampRules(W2A.rules({ sightBelow = 6 }))
		end
		root.Position = vec(31, 3, 0)
		local group, ids = W4C.place("guard", W4C.fourPosts(), { "fodder", "fodder", "fodder", "fodder" }, { yaw = -math.pi / 2 })
		step2(2)
		if part == "a" then
			Crowd.Damage(ids[1], 1, 7, nil, nil)
		end
		local fought = W4C.untilEvent(group, "fight", 10)
		local wound = 0
		local engaged = false
		local home: number? = nil
		for count = 1, 150 do
			if part == "a" and count % 60 == 0 then
				Crowd.Damage(ids[1], 1, 7, nil, nil)
			end
			step2()
			for _, id in ids do
				local state = seen(id).state
				if state == "windup" or state == "attack" then
					wound += 1
				end
			end
			engaged = engaged or Crowd.Engaged(7)
			for _, event in L1BC.events() do
				if event.group == group and event.to == "home" then
					home = home or count
				end
			end
			if home ~= nil then
				break
			end
		end
		local packed = 0
		for _, id in ids do
			if W4C.flat(id, 28.7, 0) <= 4.5 then
				packed += 1
			end
		end
		check(fought ~= nil and packed >= 1, `(R14 {part}: the four wake and reach the lip over him: {packed} near the end)`)
		check(wound == 0, `R14 {part}: no blow is begun at a player 8 under the floor ({wound} body-steps in windup or attack)`)
		check(home ~= nil and home <= 120, `R14 {part}: they go home within leash + a margin (step {home or "never"}, at most 120)`)
		check(not engaged, `R14 {part}: he is never engaged`)
	end

	-- Ruling 21 kept: a player in the air over the floor, feet 6 to 8 over it (past the lunge's
	-- height 5), is still wound up at, the band being judged on the surface he last stood on.
	fresh()
	W4C.enter()
	root.Position = vec(200, 15, 0)
	step2(2)
	local jumper = Crowd.Spawn("fodder", vec(206, 12, 0), "fight", nil, nil, 2)
	local woundUp = false
	for count = 1, 45 do
		root.Position = vec(200, if count % 2 == 0 then 21 else 23, 0)
		step2()
		woundUp = woundUp or seen(jumper).state == "windup"
	end
	root.Position = vec(200, 15, 0)
	check(woundUp, "R14: a fodder still winds up under a player in the air over its floor (ruling 21)")
end
L1BC.crowdGroup("fix round: the foot of the climb", W4C.footTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
