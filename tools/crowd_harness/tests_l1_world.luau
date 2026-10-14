-- Cases for L1's world, the pure LevelGeometry (docs/INTERFACES.md "L1 contracts" → "A — the
-- world"): appended to the bundle by run_harness.py after the earlier test files, so their
-- `load`, `check` and `near` are in scope. Everything hangs off the L1W table (the 200-local
-- limit). LevelService and BarrierGroups are Instance work and cannot be loaded here.

print("L1: the world (LevelGeometry)")

local L1W: any = { Geo = load("LevelGeometry") }

-- As LevelService.sizesOf reads them: levels.fenceThickness 1, levels.floorThickness 4, levels.checkpointSize,
-- Expeditions.json sign.size.
L1W.sizes = { fence = 1, floor = 4, checkpoint = { sx = 2, sy = 10, sz = 2 }, sign = { sx = 6, sy = 4, sz = 6 } }

-- A box is these six numbers.
function L1W.is(box: any, x: number, y: number, z: number, sx: number, sy: number, sz: number): boolean
	return box ~= nil and near(box.x, x) and near(box.y, y) and near(box.z, z) and near(box.sx, sx) and near(box.sy, sy) and near(box.sz, sz)
end

function L1W.show(box: any): string
	if box == nil then
		return "nil"
	end
	return `({box.x}, {box.y}, {box.z}) size ({box.sx}, {box.sy}, {box.sz})`
end

-- Whether a point lies in one of the boxes, faces included.
function L1W.inside(boxes: { any }, x: number, y: number, z: number): boolean
	for _, box in boxes do
		if math.abs(x - box.x) <= box.sx / 2 + 1e-9 and math.abs(y - box.y) <= box.sy / 2 + 1e-9 and math.abs(z - box.z) <= box.sz / 2 + 1e-9 then
			return true
		end
	end
	return false
end

-- The Village arena's shape (Layouts/Arenas/Village.luau), written out: the harness does not
-- load layout modules.
function L1W.village(): any
	return {
		size = { x = 110, z = 110 },
		floor = { material = "Grass", color = { 106, 127, 63 } },
		wall = { height = 4, material = "WoodPlanks", color = { 112, 84, 56 }, barrierHeight = 80, barrierThickness = 8 },
		lobbyPad = { x = 0, z = 0 },
		playerSpawns = { { x = -12, z = -12 }, { x = 12, z = -12 }, { x = 12, z = 12 }, { x = -12, z = 12 } },
		enemySpawns = {
			{ x = 0, z = -46 },
			{ x = 32.5, z = -32.5 },
			{ x = 46, z = 0 },
			{ x = 32.5, z = 32.5 },
			{ x = 0, z = 46 },
			{ x = -32.5, z = 32.5 },
			{ x = -46, z = 0 },
			{ x = -32.5, z = -32.5 },
		},
		obstacles = {
			{ x = 9.2, z = 22.3, sx = 5, sy = 3.5, sz = 5, material = "Slate", color = { 110, 110, 105 } },
			{ x = 22.3, z = -9.2, sx = 6, sy = 4, sz = 5, material = "Slate", color = { 102, 104, 100 } },
			{ x = -9.2, z = -22.3, sx = 5, sy = 3.5, sz = 6, material = "Slate", color = { 110, 110, 105 } },
			{ x = -22.3, z = 9.2, sx = 5, sy = 3, sz = 5, material = "Slate", color = { 102, 104, 100 } },
			{ x = 12.6, z = -30.4, sx = 12, sy = 2, sz = 3, material = "Wood", color = { 96, 70, 45 } },
			{ x = -30.4, z = -12.6, sx = 3, sy = 2, sz = 12, material = "Wood", color = { 86, 62, 40 } },
			{ x = -12.6, z = 30.4, sx = 12, sy = 2, sz = 3, material = "Wood", color = { 96, 70, 45 } },
			{ x = 30.4, z = 12.6, sx = 3, sy = 2, sz = 12, material = "Wood", color = { 86, 62, 40 } },
		},
	}
end

-- Camp A of the cases below: 60 x 60, its floor's top at (100, 5, -50), a fence 6 high, the
-- entry gate in the middle of the south side and the exit gate off-centre on the north side. It
-- locks (L1b-12): only such a camp has gates and an invisible wall (open camps: tests_l1b.luau).
function L1W.camp(): any
	return {
		id = "A",
		x = 100,
		y = 5,
		z = -50,
		sx = 60,
		sz = 60,
		fence = { height = 6 },
		gates = { { side = "south", at = 0, width = 12 }, { side = "north", at = 10, width = 14 } },
		entry = { x = 100, z = -24 },
		exit = { x = 110, z = -76 },
		checkpoint = { x = 110, z = -70 },
		spawns = { { x = 80, z = -70 }, { x = 120, z = -70 }, { x = 80, z = -40 }, { x = 120, z = -40 } },
		obstacles = { { x = 95, z = -55, sx = 4, sy = 3, sz = 6, material = "Slate", color = { 1, 2, 3 } } },
		locks = true,
	}
end

-- The fence and gate boxes that stand on one side of `camp`, as stretches along that side
-- measured from its middle, in order. A north or south corner post is not a west or east box.
function L1W.stretches(camp: any, thickness: number, name: string, boxes: { any }): { any }
	local found: { any } = {}
	for _, box in boxes do
		if name == "north" or name == "south" then
			local line = camp.z + (if name == "north" then -1 else 1) * (camp.sz / 2 + thickness / 2)
			if near(box.z, line) and near(box.sz, thickness) then
				table.insert(found, { box.x - box.sx / 2 - camp.x, box.x + box.sx / 2 - camp.x })
			end
		else
			local line = camp.x + (if name == "west" then -1 else 1) * (camp.sx / 2 + thickness / 2)
			if near(box.x, line) and near(box.sx, thickness) and math.abs(box.z - camp.z) <= camp.sz / 2 then
				table.insert(found, { box.z - box.sz / 2 - camp.z, box.z + box.sz / 2 - camp.z })
			end
		end
	end
	table.sort(found, function(a: any, b: any): boolean
		return a[1] < b[1]
	end)
	return found
end

-- Fence and gates together cover each side exactly once from end to end: no gap, no overlap.
-- The north and south sides run past the corners by the thickness.
function L1W.covered(camp: any, thickness: number): (boolean, string)
	local Geo = L1W.Geo
	local all: { any } = {}
	for _, box in Geo.FenceBoxes(camp, thickness) do
		table.insert(all, box)
	end
	for _, box in Geo.GateBoxes(camp, thickness) do
		table.insert(all, box)
	end
	for _, name in { "north", "south", "west", "east" } do
		local alongX = name == "north" or name == "south"
		local reach = (if alongX then camp.sx else camp.sz) / 2 + (if alongX then thickness else 0)
		local at = -reach
		for _, stretch in L1W.stretches(camp, thickness, name, all) do
			if not near(stretch[1], at) then
				return false, `{name}: a stretch starts at {stretch[1]}, expected {at}`
			end
			at = stretch[2]
		end
		if not near(at, reach) then
			return false, `{name}: covered up to {at} of {reach}`
		end
	end
	return true, "every side"
end

function L1W.arenaTests(): ()
	print(" FromArena: the Village arena as a level (ruling 27)")
	local Geo = L1W.Geo
	local arena = L1W.village()
	local layout = Geo.FromArena(arena, -8)
	local camp = layout.camps[1]
	check(#layout.camps == 1 and camp.id == "arena" and camp.x == 0 and camp.y == 0 and camp.z == 0 and camp.sx == 110 and camp.sz == 110, "one camp, \"arena\", 110 x 110, its floor's top at the world origin")
	local spawnsMatch = #camp.spawns == 8
	for index, point in arena.enemySpawns do
		spawnsMatch = spawnsMatch and camp.spawns[index] ~= nil and camp.spawns[index].x == point.x and camp.spawns[index].z == point.z
	end
	check(spawnsMatch, "its eight spawn points are the arena's enemy spawns, in order")
	local coverMatch = #camp.obstacles == 8
	for index, obstacle in arena.obstacles do
		local copy = camp.obstacles[index]
		coverMatch = coverMatch and copy ~= nil and copy.x == obstacle.x and copy.z == obstacle.z and copy.sx == obstacle.sx and copy.sy == obstacle.sy and copy.sz == obstacle.sz and copy.material == obstacle.material
	end
	check(coverMatch, "its cover is the arena's eight obstacles")
	check(layout.barrier ~= nil and layout.barrier.height == 80 and layout.barrier.thickness == 8, "the invisible wall is the arena's: 80 high, 8 deep")
	check(camp.fence ~= nil and camp.fence.height == 4 and camp.fence.material == "WoodPlanks" and camp.fence.color[1] == 112 and camp.floor.material == "Grass" and camp.floor.color[2] == 127, "fence and floor keep the arena's height, material and colour")
	check(#camp.gates == 0 and camp.checkpoint == nil, "no gates and no checkpoint")
	check(camp.entry.x == -12 and camp.entry.z == -12 and camp.exit.x == 0 and camp.exit.z == 0, "the party enters at the first player spawn and leaves at the pad")
	check(layout.start.x == 0 and layout.start.y == 0 and layout.start.z == 0 and layout.killY == -8, "the start is the pad on the floor; killY is the argument")
	check(layout.arena == nil and #layout.blocks == 0 and #layout.secrets == 0 and #layout.route == 0 and layout.spawns == nil, "nothing else: no blocks, secrets or route, and no arena name left")
	camp.spawns[1].x = 999
	camp.obstacles[1].sy = 999
	camp.fence.color[1] = 0
	check(arena.enemySpawns[1].x == 0 and arena.obstacles[1].sy == 3.5 and arena.wall.color[1] == 112, "every table is new: changing the level leaves the arena's module untouched")

	local bare = L1W.village()
	bare.playerSpawns = {}
	bare.lobbyPad = { x = 3, z = -4 }
	bare.wall = nil
	local plain = Geo.FromArena(bare, -20)
	check(plain.camps[1].entry.x == 3 and plain.camps[1].entry.z == -4 and plain.start.x == 3 and plain.start.z == -4, "no player spawn: the entry is the pad, wherever the pad is")
	check(plain.camps[1].fence == nil and plain.barrier == nil, "no wall: no fence and no invisible wall")
	local low = L1W.village()
	low.wall.barrierHeight = nil
	check(Geo.FromArena(low, -8).barrier == nil and Geo.FromArena(low, -8).camps[1].fence ~= nil, "a wall without barrierHeight: the fence, and no invisible wall")
	local thin = L1W.village()
	thin.wall.barrierThickness = nil
	local thinLayout = Geo.FromArena(thin, -8)
	local thinWall = Geo.BarrierBoxes(thinLayout.camps[1], 1, thinLayout.barrier)
	check(thinLayout.barrier.thickness == 0 and #thinWall == 4 and near(thinWall[1].sz, 1), "no barrierThickness: the wall is as deep as the fence")

	local fresh = Geo.FromArena(L1W.village(), -8)
	local fence = Geo.FenceBoxes(fresh.camps[1], 1)
	check(#fence == 4 and L1W.is(fence[1], 0, 2, -55.5, 112, 4, 1) and L1W.is(fence[2], 0, 2, 55.5, 112, 4, 1) and L1W.is(fence[3], -55.5, 2, 0, 1, 4, 110) and L1W.is(fence[4], 55.5, 2, 0, 1, 4, 110), "with no gate the fence is the C1 arena's four boxes (112 x 4 x 1 at z -55.5 and 55.5; 1 x 4 x 110 at x -55.5 and 55.5)")
	local wall = Geo.BarrierBoxes(fresh.camps[1], 1, fresh.barrier)
	check(#wall == 4 and L1W.is(wall[1], 0, 40, -59, 126, 80, 8) and L1W.is(wall[2], 0, 40, 59, 126, 80, 8) and L1W.is(wall[3], -59, 40, 0, 8, 80, 110) and L1W.is(wall[4], 59, 40, 0, 8, 80, 110), "and the invisible wall starts at the floor's edge, the fence inside it (126 x 80 x 8 at z -59 and 59; 8 x 80 x 110 at x -59 and 59)")
	local pieces = Geo.Pieces(fresh, L1W.sizes, 600)
	check(pieces ~= nil and #pieces == 17 and pieces[1].name == "Camp_arena_Floor" and pieces[17].name == "Barrier_arena_4", `the arena is 17 Parts: a floor, 4 fence, 8 cover, 4 wall ({pieces and #pieces})`)
	check(pieces ~= nil and L1W.is(pieces[1].box, 0, -2, 0, 110, 4, 110), `its floor is levels.floorThickness deep like any camp's (4), its top still at 0 ({pieces and L1W.show(pieces[1].box)})`)
	local bounds = Geo.Bounds(fresh, 4)
	check(bounds.minX == -55 and bounds.maxX == 55 and bounds.minZ == -55 and bounds.maxZ == 55 and bounds.minY == -4 and bounds.maxY == 4, "its bounds are the floor, its depth under it, and the fence's height")
end
L1W.arenaTests()

-- How many points on top of `camp`'s fence and gates are NOT in `wall`: per box its middle and
-- its four corners (a hair inside), a hair above its top and at a standing root's height.
function L1W.perches(camp: any, thickness: number, wall: { any }): (number, string)
	local Geo = L1W.Geo
	local open = 0
	local first = ""
	for _, list in { Geo.FenceBoxes(camp, thickness), Geo.GateBoxes(camp, thickness) } do
		for _, box in list do
			local top = box.y + box.sy / 2
			local hx, hz = box.sx / 2 - 0.001, box.sz / 2 - 0.001
			for _, at in { { 0, 0 }, { -hx, -hz }, { hx, -hz }, { -hx, hz }, { hx, hz } } do
				for _, height in { top + 0.01, top + 3 } do
					if not L1W.inside(wall, box.x + at[1], height, box.z + at[2]) then
						open += 1
						if first == "" then
							first = `({box.x + at[1]}, {height}, {box.z + at[2]})`
						end
					end
				end
			end
		end
	end
	return open, first
end

function L1W.barrierTests(): ()
	print(" BarrierBoxes: the invisible wall")
	local Geo = L1W.Geo
	local camp = L1W.camp()
	camp.sz = 40
	camp.x, camp.y, camp.z = 300, 12, -200
	local barrier = { height = 80, thickness = 8 }
	local boxes = Geo.BarrierBoxes(camp, 1, barrier)
	check(#boxes == 4, "four boxes: north, south, west, east")
	local grounded = true
	for _, box in boxes do
		grounded = grounded and near(box.y - box.sy / 2, 12) and near(box.y + box.sy / 2, 92)
	end
	check(grounded, "each stands from the floor's top (12) up to barrier.height above it (92)")
	-- The floor's edges: 30 from the centre in X, 20 in Z. Not the fence's outer face, a
	-- thickness further out: the fence stands inside the wall.
	check(near(boxes[1].z + boxes[1].sz / 2, -220) and near(boxes[2].z - boxes[2].sz / 2, -180) and near(boxes[3].x + boxes[3].sx / 2, 270) and near(boxes[4].x - boxes[4].sx / 2, 330), "each inner face is on the floor's edge (z -220 and -180, x 270 and 330)")
	check(near(boxes[1].sz, 8) and near(boxes[2].sz, 8) and near(boxes[3].sx, 8) and near(boxes[4].sx, 8), "each is barrier.thickness deep, outward")
	check(near(boxes[1].x - boxes[1].sx / 2, 262) and near(boxes[1].x + boxes[1].sx / 2, 338) and near(boxes[3].z - boxes[3].sz / 2, -220) and near(boxes[3].z + boxes[3].sz / 2, -180), "the north and south boxes run past the west and east ones (x 262 to 338); those fill between them (z -220 to -180)")

	-- Walk three rings round the camp, just outside the floor's edge, in the middle of the wall
	-- and just inside its outer face, at three heights: every point is in the wall.
	local holes = 0
	local firstHole = ""
	for _, out in { 0.01, 4, 7.99 } do
		local a = 30 + out
		local b = 20 + out
		for _, height in { 12.01, 52, 91.99 } do
			local function probe(dx: number, dz: number): ()
				if not L1W.inside(boxes, camp.x + dx, height, camp.z + dz) then
					holes += 1
					if firstHole == "" then
						firstHole = `({dx}, {dz}) at height {height}`
					end
				end
			end
			for step = 0, a * 4 do
				local dx = math.min(-a + step * 0.5, a)
				probe(dx, -b)
				probe(dx, b)
			end
			for step = 0, b * 4 do
				local dz = math.min(-b + step * 0.5, b)
				probe(-a, dz)
				probe(a, dz)
			end
			probe(a, b)
			probe(-a, b)
			probe(a, -b)
			probe(-a, -b)
		end
	end
	check(holes == 0, `the wall is closed all the way round, corners included ({holes} holes{if holes > 0 then ", first at " .. firstHole else ""})`)
	check(not L1W.inside(boxes, camp.x + 29.99, 52, camp.z) and not L1W.inside(boxes, camp.x - 29.99, 52, camp.z) and not L1W.inside(boxes, camp.x, 52, camp.z - 19.99) and not L1W.inside(boxes, camp.x + 29.99, 52, camp.z + 19.99), "and it does not reach inside the floor's edge")
	check(not L1W.inside(boxes, camp.x + 35, 11.9, camp.z) and not L1W.inside(boxes, camp.x + 35, 92.1, camp.z), "nor under the floor's top, nor above its height")

	-- Ruling 2 of the fix round: closed, nobody stands on a fence or in a gate gap.
	local open, where = L1W.perches(camp, 1, boxes)
	check(open == 0, `the fence and the gates stand inside the wall: no point on top of them is free ({open} are{if open > 0 then ", first " .. where else ""})`)
	local tall = L1W.camp()
	tall.fence = { height = 30 }
	open, where = L1W.perches(tall, 1, Geo.BarrierBoxes(tall, 1, barrier))
	check(open == 0, `whatever the fence's height (30 here) ({open} free{if open > 0 then ", first " .. where else ""})`)

	local shallow = Geo.BarrierBoxes(camp, 2, { height = 80, thickness = 0.5 })
	check(#shallow == 4 and near(shallow[1].sz, 2) and near(shallow[3].sx, 2) and near(shallow[1].z + shallow[1].sz / 2, -220) and near(shallow[4].x - shallow[4].sx / 2, 330), "a wall thinner than the fence is made as deep as the fence, from the floor's edge")
	open, where = L1W.perches(camp, 2, shallow)
	check(open == 0, `so it still holds the whole fence line ({open} points free{if open > 0 then ", first " .. where else ""})`)
	check(#Geo.BarrierBoxes(camp, 1, { height = 0, thickness = 8 }) == 0 and #Geo.BarrierBoxes(camp, 0, { height = 80, thickness = 0 }) == 0, "no height, or no depth at all: no wall")
	camp.fence = nil
	camp.gates = {}
	local unfenced = Geo.BarrierBoxes(camp, 1, barrier)
	check(#unfenced == 4 and near(unfenced[4].x - 4, 330) and near(unfenced[1].z + 4, -220) and near(unfenced[4].sx, 8), "a camp with no fence has the same wall, from the floor's edge")
end
L1W.barrierTests()

function L1W.fenceTests(): ()
	print(" FenceBoxes and GateBoxes: the fence is cut where a gate stands")
	local Geo = L1W.Geo
	local camp = L1W.camp()
	local fence = Geo.FenceBoxes(camp, 1)
	local gates = Geo.GateBoxes(camp, 1)
	check(#fence == 6, `north and south are each cut in two, west and east are whole: six boxes ({#fence})`)
	check(L1W.is(fence[1], 86, 8, -80.5, 34, 6, 1) and L1W.is(fence[2], 124, 8, -80.5, 14, 6, 1), `north: x 69 to 103, then 117 to 131 ({L1W.show(fence[1])}; {L1W.show(fence[2])})`)
	check(L1W.is(fence[3], 81.5, 8, -19.5, 25, 6, 1) and L1W.is(fence[4], 118.5, 8, -19.5, 25, 6, 1), "south: x 69 to 94, then 106 to 131")
	check(L1W.is(fence[5], 69.5, 8, -50, 1, 6, 60) and L1W.is(fence[6], 130.5, 8, -50, 1, 6, 60), "west and east: the floor's whole side, a thickness outside its edge")
	check(#gates == 2 and L1W.is(gates[1], 100, 8, -19.5, 12, 6, 1) and L1W.is(gates[2], 110, 8, -80.5, 14, 6, 1), `one box per gate, in the camp's order, as tall and as deep as the fence ({L1W.show(gates[1])}; {L1W.show(gates[2])})`)
	local ok, why = L1W.covered(camp, 1)
	check(ok, `fence and gates cover every side once, end to end: the gate fills the cut ({why})`)

	local ends = L1W.camp()
	ends.gates = { { side = "east", at = 28, width = 12 }, { side = "west", at = 0, width = 100 } }
	local endFence = Geo.FenceBoxes(ends, 1)
	local endGates = Geo.GateBoxes(ends, 1)
	check(#endGates == 2 and L1W.is(endGates[1], 130.5, 8, -24, 1, 6, 8) and L1W.is(endGates[2], 69.5, 8, -50, 1, 6, 60), "a gate past the end of its side is held to the floor's edge (east: z -28 to -20); one wider than its side is the whole side")
	check(#endFence == 3 and L1W.is(endFence[3], 130.5, 8, -54, 1, 6, 52), `the east fence stops where that gate starts, and the west side has no fence left ({#endFence} boxes)`)
	ok, why = L1W.covered(ends, 1)
	check(ok, `still covered once, end to end ({why})`)

	local pair = L1W.camp()
	pair.gates = { { side = "north", at = 15, width = 10 }, { side = "north", at = -15, width = 10 } }
	local pairFence = Geo.FenceBoxes(pair, 1)
	check(#pairFence == 6 and L1W.is(pairFence[1], 74.5, 8, -80.5, 11, 6, 1) and L1W.is(pairFence[2], 100, 8, -80.5, 20, 6, 1) and L1W.is(pairFence[3], 125.5, 8, -80.5, 11, 6, 1), "two gates on one side, in any order: three stretches of fence between and beside them")
	ok, why = L1W.covered(pair, 1)
	check(ok, `and the side is covered once ({why})`)

	local nested = L1W.camp()
	nested.gates = { { side = "north", at = -2.5, width = 15 }, { side = "north", at = -1.5, width = 7 } }
	local nestedFence = Geo.FenceBoxes(nested, 1)
	check(#nestedFence == 5 and L1W.is(nestedFence[1], 79.5, 8, -80.5, 21, 6, 1) and L1W.is(nestedFence[2], 118, 8, -80.5, 26, 6, 1), "a gate inside a wider one: the fence stays cut for the whole of the wider gate (x 69 to 90, then 105 to 131)")

	local odd = L1W.camp()
	odd.gates = { { side = "up", at = 0, width = 12 }, { side = "north", at = 0, width = 0 }, { side = "south", at = 0, width = 0 / 0 } }
	check(#Geo.FenceBoxes(odd, 1) == 4 and #Geo.GateBoxes(odd, 1) == 0, "a gate on an unknown side, or with no width, or a width that is not a number, cuts nothing and has no box")
	local none = L1W.camp()
	none.fence = nil
	check(#Geo.FenceBoxes(none, 1) == 0 and #Geo.GateBoxes(none, 1) == 0, "no fence: no fence boxes and no gate boxes")
	check(#Geo.FenceBoxes(camp, 0) == 0 and #Geo.GateBoxes(camp, 0) == 0, "a fence of no thickness is no fence")
	local wide = Geo.FenceBoxes(L1W.camp(), 2)
	check(#wide == 6 and near(wide[1].x - wide[1].sx / 2, 68) and near(wide[6].x, 131) and near(wide[6].sx, 2), "a thicker fence stands further out and its corners still close (north runs from x 68)")
end
L1W.fenceTests()

-- When the gates close the run moves every fighter whose root is not inside the camp's floor
-- rectangle (StageFlow's zone.rect: camp.x, camp.z, sx / 2, sz / 2, less levels.closeInset;
-- WaveService's close). That rule and this module must mean the same rectangle: nothing that
-- turns solid at the close may reach inside it, and the wall's band starts exactly on its edge.
function L1W.closeTests(): ()
	print(" At the close: what turns solid lies outside the floor rectangle")
	local Geo = L1W.Geo
	local barrier = { height = 80, thickness = 8 }
	local ends = L1W.camp()
	ends.gates = { { side = "east", at = 28, width = 12 }, { side = "west", at = 0, width = 100 }, { side = "north", at = -29, width = 6 } }
	local arena = Geo.FromArena(L1W.village(), -8).camps[1]
	local reaching = 0
	local first = ""
	local floors = true
	for _, camp in { L1W.camp(), ends, arena } do
		local hx, hz = camp.sx / 2, camp.sz / 2
		local floor = Geo.FloorBox(camp, 4)
		floors = floors and near(floor.x, camp.x) and near(floor.z, camp.z) and near(floor.sx / 2, hx) and near(floor.sz / 2, hz)
		local solids: { any } = {}
		for _, list in { Geo.FenceBoxes(camp, 1), Geo.GateBoxes(camp, 1), Geo.BarrierBoxes(camp, 1, barrier) } do
			for _, box in list do
				table.insert(solids, box)
			end
		end
		for _, box in solids do
			-- Clear of the rectangle: wholly on or beyond one of its four edges.
			local clear = box.x - box.sx / 2 >= camp.x + hx - 1e-9 or box.x + box.sx / 2 <= camp.x - hx + 1e-9 or box.z - box.sz / 2 >= camp.z + hz - 1e-9 or box.z + box.sz / 2 <= camp.z - hz + 1e-9
			if not clear then
				reaching += 1
				if first == "" then
					first = L1W.show(box)
				end
			end
		end
	end
	check(floors, "the floor's box is that rectangle: the camp's centre, half its size each way")
	check(reaching == 0, `no fence, gate or wall box reaches inside it, in three camps ({reaching} do{if reaching > 0 then ", first " .. first else ""})`)
	local camp = L1W.camp()
	local gates = Geo.GateBoxes(camp, 1)
	local wall = Geo.BarrierBoxes(camp, 1, barrier)
	local function inRect(x: number, z: number): boolean
		return math.abs(x - camp.x) <= camp.sx / 2 and math.abs(z - camp.z) <= camp.sz / 2
	end
	check(#gates == 2 and not inRect(gates[1].x, gates[1].z) and not inRect(gates[2].x, gates[2].z) and near(gates[1].z - gates[1].sz / 2, camp.z + 30) and near(gates[2].z + gates[2].sz / 2, camp.z - 30), "a root in a gate gap is outside the rectangle: each gate's inner face is the floor's edge")
	check(#wall == 4 and near(wall[1].z + wall[1].sz / 2, camp.z - 30) and near(wall[2].z - wall[2].sz / 2, camp.z + 30) and near(wall[3].x + wall[3].sx / 2, camp.x - 30) and near(wall[4].x - wall[4].sx / 2, camp.x + 30), "the wall's band starts on the rectangle's edge on all four sides: a root is inside the rectangle or in the wall, with nothing between")
	check(not inRect(camp.x, wall[1].z + wall[1].sz / 2 - 0.01) and not inRect(wall[4].x - wall[4].sx / 2 + 0.01, camp.z) and L1W.inside(wall, gates[1].x, camp.y + 3, gates[1].z) and L1W.inside(wall, gates[2].x, camp.y + 3, gates[2].z) and L1W.inside(wall, gates[1].x, camp.y + 3, gates[1].z + 1) and L1W.inside(wall, gates[2].x, camp.y + 3, gates[2].z - 1), "so a root anywhere in the band is outside the rectangle, and the band holds both gate gaps: the gates' own depth and the ground just outside them")
end
L1W.closeTests()

function L1W.boxTests(): ()
	print(" The other boxes, and Bounds")
	local Geo = L1W.Geo
	local camp = L1W.camp()
	local floor = Geo.FloorBox(camp, 4)
	check(L1W.is(floor, 100, 3, -50, 60, 4, 60) and near(floor.y + floor.sy / 2, camp.y), `the floor is as deep as it is told (4), downward: its top is camp.y ({L1W.show(floor)})`)
	check(L1W.is(Geo.FloorBox(camp, 1), 100, 4.5, -50, 60, 1, 60) and L1W.is(Geo.FloorBox(camp, 6.5), 100, 1.75, -50, 60, 6.5, 60), "at any depth (1, 6.5) the top is camp.y")
	local cover = Geo.ObstacleBoxes(camp)
	check(#cover == 1 and L1W.is(cover[1], 95, 6.5, -55, 4, 3, 6), "cover stands on the floor")
	check(L1W.is(Geo.CheckpointBox(camp, L1W.sizes.checkpoint), 110, 10, -70, 2, 10, 2), "the checkpoint marker stands on the floor at camp.checkpoint")
	camp.checkpoint = nil
	check(Geo.CheckpointBox(camp, L1W.sizes.checkpoint) == nil, "and a camp with no checkpoint has no marker")
	local secret = { id = "lookout", needs = "doubleJump", x = 40, y = 30, z = -10, sx = 8, sy = 2, sz = 8, sign = { x = 44, y = 5, z = 2, text = "Needs: Double Jump" } }
	check(L1W.is(Geo.SecretBox(secret), 40, 30, -10, 8, 2, 8) and L1W.is(Geo.SignBox(secret, L1W.sizes.sign), 44, 7, 2, 6, 4, 6), "a secret's block is where the layout puts it; its sign rises from the sign's point")

	local layout: any = { version = 1, start = { x = 0, y = 5, z = 0 }, killY = -40, camps = { L1W.camp() }, blocks = {}, secrets = {}, route = {} }
	local bounds = Geo.Bounds(layout, 4)
	check(bounds.minX == 70 and bounds.maxX == 130 and bounds.minZ == -80 and bounds.maxZ == -20 and bounds.minY == 1 and bounds.maxY == 11, "a camp alone: its floor, the floor's depth under the top, and the fence's height above it")
	layout.blocks = { { look = "path", x = 20, y = 2, z = -50, sx = 100, sy = 4, sz = 14 } }
	local wider = Geo.Bounds(layout, 4)
	check(wider.minX == -30 and wider.maxX == 130 and wider.minY == 0 and wider.minZ == -80 and wider.maxZ == -20 and wider.maxY == 11, "a block outside every camp widens it, on the sides it reaches past")
	layout.secrets = { secret }
	layout.camps[1].obstacles[1].sy = 9
	local full = Geo.Bounds(layout)
	check(full.maxY == 31 and full.maxZ == -6 and Geo.Bounds({ version = 1, start = { x = 0, y = 5, z = 0 }, killY = -40, camps = { layout.camps[1] }, blocks = {}, secrets = {}, route = {} } :: any).maxY == 14, "a secret widens it too, and cover taller than the fence raises it")
	local empty = Geo.Bounds({ version = 1, start = { x = 7, y = 8, z = 9 }, killY = -40 } :: any)
	check(empty.minX == 7 and empty.maxX == 7 and empty.minY == 8 and empty.maxY == 8 and empty.minZ == 9 and empty.maxZ == 9, "a layout with nothing in it (its lists absent) is its start point")

	local lobby = Geo.BareLobby()
	local lobbyBounds = Geo.Bounds(lobby)
	local onPad = #lobby.spawns >= 4
	for _, point in lobby.spawns do
		onPad = onPad and point.x > lobbyBounds.minX and point.x < lobbyBounds.maxX and point.z > lobbyBounds.minZ and point.z < lobbyBounds.maxZ and point.y == lobbyBounds.maxY
	end
	check(onPad and lobby.start.y == lobbyBounds.maxY and lobby.killY < lobbyBounds.minY, "the stand-in lobby: four points and the start on its pad, killY under it")
	local pad = Geo.Pieces(lobby, { fence = 0 }, 600)
	check(pad ~= nil and #pad == 1 and pad[1].box.sy >= 4 and lobbyBounds.maxY - lobby.killY <= 12, `with no config at all its pad is a deep block ({pad and pad[1].box.sy}), and the fall from it to killY is short ({lobbyBounds.maxY - lobby.killY})`)
	check(lobbyBounds.maxZ <= -1150 and #lobby.camps == 0, "and it lies over 150 studs clear of every camp (each within 1,000 of the origin)")
end
L1W.boxTests()

-- Every case above is square on the axis it tests, so a rule that reads the camp's width where
-- it means its depth passed them all. This camp is Forest Road's Main Camp in shape: 100 x 94,
-- off the origin on both axes (and not by the same amount), its floor at height 8, with a gate
-- on each side, none of them in the middle.
function L1W.oblong(): any
	return {
		id = "B",
		x = 88,
		y = 8,
		z = -36,
		sx = 100,
		sz = 94,
		fence = { height = 4 },
		gates = {
			{ side = "west", at = -10, width = 16 },
			{ side = "east", at = 12, width = 16 },
			{ side = "north", at = -20, width = 12 },
			{ side = "south", at = 30, width = 10 },
		},
		entry = { x = 44, z = -46 },
		exit = { x = 132, z = -24 },
		checkpoint = { x = 134, z = -47 },
		spawns = { { x = 60, z = -70 }, { x = 120, z = -70 }, { x = 60, z = 0 }, { x = 120, z = 0 } },
		obstacles = { { x = 60, z = -66, sx = 10, sy = 3.5, sz = 8, material = "Slate", color = { 1, 2, 3 } } },
		locks = true,
	}
end

function L1W.oblongTests(): ()
	print(" An oblong camp off the origin: no rule reads the width for the depth")
	local Geo = L1W.Geo
	local camp = L1W.oblong()
	local floor = Geo.FloorBox(camp, 4)
	check(L1W.is(floor, 88, 6, -36, 100, 4, 94), `the floor: 100 along X and 94 along Z round (88, -36), from 4 up to its top at 8 ({L1W.show(floor)})`)

	local fence = Geo.FenceBoxes(camp, 1)
	check(#fence == 8, `each side is cut in two by its gate: eight fence boxes ({#fence})`)
	check(L1W.is(fence[1], 49.5, 10, -83.5, 25, 4, 1) and L1W.is(fence[2], 106.5, 10, -83.5, 65, 4, 1), `north, on z -83.5 (47 from the centre, not 50): x 37 to 62, then 74 to 139 ({L1W.show(fence[1])}; {L1W.show(fence[2])})`)
	check(L1W.is(fence[3], 75, 10, 11.5, 76, 4, 1) and L1W.is(fence[4], 131, 10, 11.5, 16, 4, 1), `south, on z 11.5: x 37 to 113, then 123 to 139 ({L1W.show(fence[3])}; {L1W.show(fence[4])})`)
	check(L1W.is(fence[5], 37.5, 10, -68.5, 1, 4, 29) and L1W.is(fence[6], 37.5, 10, -13.5, 1, 4, 49), `west, on x 37.5 (50 from the centre, not 47): z -83 to -54, then -38 to 11 ({L1W.show(fence[5])}; {L1W.show(fence[6])})`)
	check(L1W.is(fence[7], 138.5, 10, -57.5, 1, 4, 51) and L1W.is(fence[8], 138.5, 10, -2.5, 1, 4, 27), `east, on x 138.5: z -83 to -32, then -16 to 11 ({L1W.show(fence[7])}; {L1W.show(fence[8])})`)

	local gates = Geo.GateBoxes(camp, 1)
	check(#gates == 4 and L1W.is(gates[1], 37.5, 10, -46, 1, 4, 16), `the west gate: on x 37.5, z -54 to -38 ({L1W.show(gates[1])})`)
	check(L1W.is(gates[2], 138.5, 10, -24, 1, 4, 16), `the east gate: on x 138.5, z -32 to -16 ({L1W.show(gates[2])})`)
	check(L1W.is(gates[3], 68, 10, -83.5, 12, 4, 1), `the north gate: on z -83.5, x 62 to 74 ({L1W.show(gates[3])})`)
	check(L1W.is(gates[4], 118, 10, 11.5, 10, 4, 1), `the south gate: on z 11.5, x 113 to 123 ({L1W.show(gates[4])})`)
	local ok, why = L1W.covered(camp, 1)
	check(ok, `fence and gates cover all four sides once, end to end ({why})`)

	-- A side's end is half the camp's own length along THAT side: 47 for west and east, 50 for
	-- north and south.
	local ends = L1W.oblong()
	ends.gates = { { side = "west", at = 45, width = 10 }, { side = "north", at = 48, width = 10 }, { side = "east", at = -45, width = 10 }, { side = "south", at = -48, width = 10 } }
	local endGates = Geo.GateBoxes(ends, 1)
	check(#endGates == 4 and L1W.is(endGates[1], 37.5, 10, 7.5, 1, 4, 7) and L1W.is(endGates[3], 138.5, 10, -79.5, 1, 4, 7), `a west or east gate past its side's end stops 47 from the middle (z 4 to 11; z -83 to -76) ({L1W.show(endGates[1])}; {L1W.show(endGates[3])})`)
	check(L1W.is(endGates[2], 134.5, 10, -83.5, 7, 4, 1) and L1W.is(endGates[4], 41.5, 10, 11.5, 7, 4, 1), `a north or south gate past its side's end stops 50 from the middle (x 131 to 138; x 38 to 45) ({L1W.show(endGates[2])}; {L1W.show(endGates[4])})`)
	ok, why = L1W.covered(ends, 1)
	check(ok, `and each side is still covered once ({why})`)

	local barrier = { height = 80, thickness = 8 }
	local wall = Geo.BarrierBoxes(camp, 1, barrier)
	check(#wall == 4 and L1W.is(wall[1], 88, 48, -87, 116, 80, 8) and L1W.is(wall[2], 88, 48, 15, 116, 80, 8), `the wall, north and south: 116 long, from z -83 and from z 11 outward ({L1W.show(wall[1])}; {L1W.show(wall[2])})`)
	check(L1W.is(wall[3], 34, 48, -36, 8, 80, 94) and L1W.is(wall[4], 142, 48, -36, 8, 80, 94), `the wall, west and east: 94 long, from x 38 and from x 138 outward ({L1W.show(wall[3])}; {L1W.show(wall[4])})`)
	local open, where = L1W.perches(camp, 1, wall)
	check(open == 0, `and the fence and all four gates stand inside it ({open} points free{if open > 0 then ", first " .. where else ""})`)

	local cover = Geo.ObstacleBoxes(camp)
	check(#cover == 1 and L1W.is(cover[1], 60, 9.75, -66, 10, 3.5, 8), `cover: its own x and z, its own width and depth ({L1W.show(cover[1])})`)
	check(L1W.is(Geo.CheckpointBox(camp, { sx = 2, sy = 10, sz = 3 }), 134, 13, -47, 2, 10, 3), "the checkpoint marker: the point's x and z, the size's width and depth")
	local secret = { id = "cache", needs = "fire", x = 154, y = 9, z = 4, sx = 12, sy = 10, sz = 6, sign = { x = 164, y = 8, z = -12, text = "needs FIRE" } }
	check(L1W.is(Geo.SecretBox(secret), 154, 9, 4, 12, 10, 6) and L1W.is(Geo.SignBox(secret, { sx = 6, sy = 4, sz = 2 }), 164, 10, -12, 6, 4, 2), "a secret and its sign: each its own x and z, width and depth")

	local layout: any = { version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40, camps = { camp }, blocks = {}, secrets = {}, route = {} }
	local bounds = Geo.Bounds(layout, 4)
	check(bounds.minX == 38 and bounds.maxX == 138 and bounds.minZ == -83 and bounds.maxZ == 11 and bounds.minY == 4 and bounds.maxY == 12, `Bounds: x 38 to 138, z -83 to 11, from the floor's underside at 4 up to the fence's top at 12 (x {bounds.minX} to {bounds.maxX}, z {bounds.minZ} to {bounds.maxZ}, y {bounds.minY} to {bounds.maxY})`)
	layout.blocks = { { look = "path", x = 16, y = 6, z = -36, sx = 44, sy = 4, sz = 16 }, { look = "ground", x = 100, y = 20, z = 40, sx = 6, sy = 30, sz = 20 } }
	local wider = Geo.Bounds(layout, 4)
	check(wider.minX == -6 and wider.maxX == 138 and wider.minZ == -83 and wider.maxZ == 50 and wider.minY == 4 and wider.maxY == 35, `and with two blocks: each widens it by its own width along X and its own depth along Z (x {wider.minX} to {wider.maxX}, z {wider.minZ} to {wider.maxZ}, y {wider.minY} to {wider.maxY})`)

	local arena = L1W.village()
	arena.size = { x = 110, z = 90 }
	local oblongArena = Geo.FromArena(arena, -8).camps[1]
	check(oblongArena.sx == 110 and oblongArena.sz == 90, "FromArena: the arena's size.x is the camp's width and its size.z the depth")

	local pieces = Geo.Pieces({ version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40, barrier = barrier, camps = { L1W.oblong() }, blocks = {}, secrets = {}, route = {} } :: any, L1W.sizes, 600)
	local byName: { [string]: any } = {}
	for _, piece in pieces or {} do
		byName[piece.name] = piece
	end
	check(pieces ~= nil and #pieces == 19 and byName.Camp_B_Fence_8 ~= nil and L1W.is(byName.Camp_B_Fence_5.box, 37.5, 10, -68.5, 1, 4, 29) and L1W.is(byName.Gate_B_3.box, 68, 10, -83.5, 12, 4, 1) and L1W.is(byName.Barrier_B_4.box, 142, 48, -36, 8, 80, 94) and L1W.is(byName.Camp_B_Obstacle_1.box, 60, 9.75, -66, 10, 3.5, 8), `Pieces builds the same boxes: 19 Parts (a floor, 8 fence, 4 gates, 1 cover, 1 marker, 4 wall) ({pieces and #pieces})`)
end
L1W.oblongTests()

-- The ground's depth (the fix round's item 2). A camp's floor and every block of ground that
-- hangs over the void are levels.floorThickness deep, downward: a body the rescue puts back
-- still has its fall's speed, and passes through a slab of one stud. Ground is a solid block of
-- look ground, path, lobby or water (tools/check_levels.py GROUND_LOOKS). The cases stand on
-- one layout, every support oblong so that no rule can read a width for a depth unseen.
function L1W.ground(): any
	return {
		version = 1,
		start = { x = 0, y = 0, z = 0 },
		killY = -40,
		camps = {},
		blocks = {
			-- Over the void, one stud deep: a plank 20 x 10 with its top at 0.
			{ name = "Deck", look = "path", x = 10, y = -0.5, z = 0, sx = 20, sy = 1, sz = 10 },
			-- Deep already (6), 20 x 10, its top at 0: x 30 to 50, z -5 to 5.
			{ name = "Thick", look = "ground", x = 40, y = -3, z = 0, sx = 20, sy = 6, sz = 10 },
			-- Exactly as deep as the rule asks.
			{ name = "Exact", look = "path", x = 70, y = -2, z = 0, sx = 8, sy = 4, sz = 6 },
			-- A thin step lying wholly on Thick, near its west end (x 31 to 35).
			{ name = "Step", look = "path", x = 33, y = 0.5, z = 0, sx = 4, sy = 1, sz = 4 },
			-- A thin shelf whose middle is over Thick and whose east end hangs out (x 44 to 54).
			{ name = "Shelf", look = "path", x = 49, y = 0.5, z = 0, sx = 10, sy = 1, sz = 4 },
			-- The same along Z: its middle over Thick, its south end out (z 0 to 8).
			{ name = "Lip", look = "path", x = 40, y = 0.5, z = 4, sx = 4, sy = 1, sz = 8 },
			-- Two piers side by side, and a thin deck across the seam between them.
			{ name = "PierWest", look = "ground", x = 105, y = -4, z = 0, sx = 10, sy = 8, sz = 6 },
			{ name = "PierEast", look = "ground", x = 115, y = -4, z = 0, sx = 10, sy = 8, sz = 6 },
			{ name = "Span", look = "path", x = 110, y = 0.5, z = 0, sx = 12, sy = 1, sz = 4 },
			-- A thin plank high above Thick: air under it, and ground only further down.
			{ name = "Plank", look = "path", x = 40, y = 20.5, z = -2, sx = 6, sy = 1, sz = 2 },
			-- Nobody stands on a sign, and a wall is not ground.
			{ name = "Sign", look = "sign", x = 150, y = 0.5, z = 0, sx = 6, sy = 1, sz = 6, collide = false },
			{ name = "Rail", look = "wall", x = 170, y = 0.5, z = 0, sx = 10, sy = 1, sz = 1 },
			-- Water nothing collides with is not ground either.
			{ name = "Mist", look = "water", x = 150, y = 0.5, z = 20, sx = 6, sy = 1, sz = 6, collide = false },
			-- Water and a lobby's floor are ground like a road.
			{ name = "Pool", look = "water", x = 230, y = -0.5, z = 0, sx = 8, sy = 1, sz = 6 },
			{ name = "Mat", look = "lobby", x = 250, y = -0.5, z = 0, sx = 6, sy = 1, sz = 6 },
			-- A thin slab lying wholly inside Deck's footprint at Deck's own depth: nothing under.
			{ name = "Inlay", look = "path", x = 10, y = -0.5, z = 0, sx = 6, sy = 1, sz = 4 },
			-- A thin slab wholly over a block nothing collides with: a ghost holds nothing up.
			{ name = "Ghost", look = "ground", x = 200, y = -4, z = 0, sx = 20, sy = 8, sz = 20, collide = false },
			{ name = "OnGhost", look = "path", x = 200, y = 0.5, z = 0, sx = 4, sy = 1, sz = 4 },
		},
		secrets = {},
		route = {},
	}
end

function L1W.groundTests(): ()
	print(" BlockBoxes: ground over the void is as deep as a camp's floor")
	local Geo = L1W.Geo
	local layout = L1W.ground()
	local boxes = Geo.BlockBoxes(layout, 4)
	local by: { [string]: any } = {}
	for index, block in layout.blocks do
		by[block.name] = boxes[index]
	end
	check(#boxes == #layout.blocks, `one box per block, in the layout's order ({#boxes} of {#layout.blocks})`)
	check(L1W.is(by.Deck, 10, -2, 0, 20, 4, 10), `a thin block over the void is made levels.floorThickness deep, downward: 20 x 4 x 10, its top still at 0 ({L1W.show(by.Deck)})`)
	check(L1W.is(by.Thick, 40, -3, 0, 20, 6, 10) and L1W.is(by.Exact, 70, -2, 0, 8, 4, 6), "a block deeper than that, or exactly that deep, is the box the layout writes")
	check(L1W.is(by.Step, 33, 0.5, 0, 4, 1, 4), `a thin block that rests wholly on another stays as written ({L1W.show(by.Step)})`)
	check(L1W.is(by.Shelf, 49, -1, 0, 10, 4, 4), `one whose middle rests on another and whose end hangs over the void is deepened: the end is what a body falls through ({L1W.show(by.Shelf)})`)
	check(L1W.is(by.Lip, 40, -1, 4, 4, 4, 8), `the same along Z ({L1W.show(by.Lip)})`)
	check(L1W.is(by.Span, 110, 0.5, 0, 12, 1, 4), `two blocks side by side hold up a deck that crosses the seam between them ({L1W.show(by.Span)})`)
	check(L1W.is(by.Plank, 40, 19, -2, 6, 4, 2), `a plank with air under it is deepened too, whatever lies further down: only what a block rests on holds it up ({L1W.show(by.Plank)})`)
	check(L1W.is(by.Sign, 150, 0.5, 0, 6, 1, 6) and L1W.is(by.Mist, 150, 0.5, 20, 6, 1, 6), `a block nothing collides with is not ground: as written, whatever its look ({L1W.show(by.Mist)})`)
	check(L1W.is(by.Rail, 170, 0.5, 0, 10, 1, 1), `nor is a solid block of a look nobody lands on (a wall): as written ({L1W.show(by.Rail)})`)
	check(L1W.is(by.Pool, 230, -2, 0, 8, 4, 6) and L1W.is(by.Mat, 250, -2, 0, 6, 4, 6), `water and a lobby's floor are ground: deepened like a road ({L1W.show(by.Pool)}; {L1W.show(by.Mat)})`)
	check(L1W.is(by.Inlay, 10, -2, 0, 6, 4, 4), `a block at its neighbour's own depth is held by nothing: the void is under both ({L1W.show(by.Inlay)})`)
	check(L1W.is(by.Ghost, 200, -4, 0, 20, 8, 20) and L1W.is(by.OnGhost, 200, -1, 0, 4, 4, 4), `and a block nothing collides with holds nothing up, though the slab lies right on it ({L1W.show(by.OnGhost)})`)
	-- The shelf and the lip again, each alone with its support: in the crowded layout above an
	-- edge of some other block may cut the footprint in the right place by chance.
	local function alone(name: string): any
		local pair: any = { version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40, blocks = {} }
		for _, block in layout.blocks do
			if block.name == "Thick" or block.name == name then
				table.insert(pair.blocks, block)
			end
		end
		return Geo.BlockBoxes(pair, 4)[2]
	end
	check(L1W.is(alone("Shelf"), 49, -1, 0, 10, 4, 4) and L1W.is(alone("Step"), 33, 0.5, 0, 4, 1, 4), `alone with its support along X: the shelf is deepened, the step is not ({L1W.show(alone("Shelf"))})`)
	check(L1W.is(alone("Lip"), 40, -1, 4, 4, 4, 8), `alone with its support along Z: the lip is deepened ({L1W.show(alone("Lip"))})`)
	local moved = 0
	for index, block in layout.blocks do
		if not near(boxes[index].y + boxes[index].sy / 2, block.y + block.sy / 2) or not near(boxes[index].x, block.x) or not near(boxes[index].z, block.z) then
			moved += 1
		end
	end
	check(moved == 0, `no block's top moves, and none moves sideways ({moved} did)`)

	-- The answer is read from the layout as written: it does not turn on the blocks' order.
	local reversed = L1W.ground()
	local count = #reversed.blocks
	for index = 1, count // 2 do
		reversed.blocks[index], reversed.blocks[count + 1 - index] = reversed.blocks[count + 1 - index], reversed.blocks[index]
	end
	local same = true
	for index, box in Geo.BlockBoxes(reversed, 4) do
		local other = by[reversed.blocks[index].name]
		same = same and L1W.is(box, other.x, other.y, other.z, other.sx, other.sy, other.sz)
	end
	check(same, "the blocks in the opposite order: the same boxes")
	local stack: any = { version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40, blocks = {
		{ name = "Upper", look = "path", x = 0, y = 1.5, z = 0, sx = 4, sy = 1, sz = 4 },
		{ name = "Lower", look = "path", x = 0, y = 0.5, z = 0, sx = 8, sy = 1, sz = 8 },
	} }
	local stacked = Geo.BlockBoxes(stack, 4)
	check(L1W.is(stacked[1], 0, 1.5, 0, 4, 1, 4) and L1W.is(stacked[2], 0, -1, 0, 8, 4, 8), "a thin block on a thin block: the lower one is deepened, the upper one rests on it")

	-- A camp's floor and a secret hold a block up as a block does.
	local camped: any = { version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40, camps = { L1W.oblong() }, blocks = {
		{ name = "Rug", look = "path", x = 60, y = 8.25, z = -30, sx = 10, sy = 0.5, sz = 6 },
		{ name = "Road", look = "path", x = 30, y = 7.5, z = -46, sx = 16, sy = 1, sz = 16 },
		{ name = "Cap", look = "path", x = 154, y = 14.5, z = 4, sx = 4, sy = 1, sz = 4 },
	}, secrets = { { id = "cache", needs = "fire", x = 154, y = 9, z = 4, sx = 12, sy = 10, sz = 6, sign = { x = 164, y = 8, z = -12, text = "needs FIRE" } } }, route = {} }
	local onCamp = Geo.BlockBoxes(camped, 4)
	check(L1W.is(onCamp[1], 60, 8.25, -30, 10, 0.5, 6), `a thin block lying on a camp's floor is held by it ({L1W.show(onCamp[1])})`)
	check(L1W.is(onCamp[2], 30, 6, -46, 16, 4, 16), `the road that ends at the camp's edge is not: it is deepened, to the floor's own depth ({L1W.show(onCamp[2])})`)
	check(L1W.is(onCamp[3], 154, 14.5, 4, 4, 1, 4), `a thin block lying on a secret's block is held by it ({L1W.show(onCamp[3])})`)

	-- No depth given: the layout as written.
	local untouched = true
	for _, depth in { 0, -4, 0 / 0, math.huge } do
		for index, box in Geo.BlockBoxes(layout, depth) do
			local block = layout.blocks[index]
			untouched = untouched and L1W.is(box, block.x, block.y, block.z, block.sx, block.sy, block.sz)
		end
	end
	for index, box in Geo.BlockBoxes(layout) do
		local block = layout.blocks[index]
		untouched = untouched and L1W.is(box, block.x, block.y, block.z, block.sx, block.sy, block.sz)
	end
	check(untouched, "without a depth (none, 0, a negative one, one that is not a number or not finite) every block is the box the layout writes")
	check(#Geo.BlockBoxes({ version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40 } :: any, 4) == 0, "a layout with no blocks has none")

	-- A block with no size is not ground: it is left for Pieces to refuse, never deepened into one.
	local broken = L1W.ground()
	broken.blocks[1].sy = 0
	broken.blocks[4].sy = -1
	broken.blocks[5].sx = 0
	local brokenBoxes = Geo.BlockBoxes(broken, 4)
	check(brokenBoxes[1].sy == 0 and brokenBoxes[4].sy == -1 and brokenBoxes[5].sx == 0 and near(brokenBoxes[5].sy, 1), "a block with a size of 0 or less is left exactly as written")

	-- Bounds holds what is built.
	local bounds = Geo.Bounds(layout, 4)
	local written = Geo.Bounds(layout)
	check(bounds.minY == -8 and written.minY == -8 and bounds.maxY == 21, "Bounds: the lowest blocks here are 8 deep already, down to -8, and the plank's top is at 21")
	local low: any = { version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40, camps = { L1W.oblong() }, blocks = { { name = "Deck", look = "path", x = 10, y = -0.5, z = 0, sx = 20, sy = 1, sz = 10 } }, secrets = {}, route = {} }
	local built = Geo.Bounds(low, 4)
	local asWritten = Geo.Bounds(low)
	check(built.minY == -4 and asWritten.minY == -1, `Bounds with levels.floorThickness holds the deepened block (down to -4); without it, the block as written (-1) ({built.minY}; {asWritten.minY})`)
	low.blocks = {}
	check(Geo.Bounds(low, 4).minY == 4 and Geo.Bounds(low).minY == 8 and Geo.Bounds(low, 0 / 0).minY == 8, "and a camp's floor down to its depth (8 - 4); without a depth the floor counts as its top face")
end
L1W.groundTests()

function L1W.pieceTests(): ()
	print(" Pieces: every Part of a layout")
	local Geo = L1W.Geo
	local function level(): any
		local camp = L1W.camp()
		camp.floor = { material = "Slate", color = { 9, 9, 9 } }
		camp.fence = { height = 6, material = "WoodPlanks" }
		return {
			version = 1,
			start = { x = 0, y = 5, z = 0 },
			killY = -40,
			barrier = { height = 80, thickness = 8 },
			camps = { camp },
			blocks = {
				{ name = "Road", look = "path", x = 20, y = 3, z = -10, sx = 100, sy = 4, sz = 14 },
				{ look = "sign", x = 5, y = 7, z = -2, sx = 6, sy = 4, sz = 1, collide = false, text = "MAP" },
			},
			secrets = { { id = "lookout", needs = "doubleJump", x = 40, y = 30, z = -10, sx = 8, sy = 2, sz = 8, sign = { x = 44, y = 5, z = 2, text = "Needs: Double Jump" } } },
			route = {},
		}
	end
	local pieces, problem = Geo.Pieces(level(), L1W.sizes, 600)
	local names: { string } = {}
	local byName: { [string]: any } = {}
	for _, piece in pieces or {} do
		table.insert(names, piece.name)
		byName[piece.name] = piece
	end
	local expected = "Road Block_2 Camp_A_Floor Camp_A_Fence_1 Camp_A_Fence_2 Camp_A_Fence_3 Camp_A_Fence_4 Camp_A_Fence_5 Camp_A_Fence_6 Gate_A_1 Gate_A_2 Camp_A_Obstacle_1 Camp_A_Checkpoint Barrier_A_1 Barrier_A_2 Barrier_A_3 Barrier_A_4 Secret_lookout Secret_lookout_Sign"
	check(problem == nil and table.concat(names, " ") == expected, `the blocks, then each camp (floor, fence, gates, cover, checkpoint, wall), then the secrets, named for Studio ({table.concat(names, " ")})`)
	if pieces == nil then
		return
	end
	check(byName.Road.role == "block" and byName.Road.look == "path" and byName.Road.collide == true and byName.Road.text == nil and L1W.is(byName.Road.box, 20, 3, -10, 100, 4, 14), "a block is its own box in its own look, solid unless it says otherwise")
	check(byName.Block_2.collide == false and byName.Block_2.text == "MAP" and byName.Block_2.look == "sign", "collide = false and text are carried")
	check(byName.Camp_A_Floor.look == "campFloor" and byName.Camp_A_Floor.material == "Slate" and byName.Camp_A_Floor.color[1] == 9 and byName.Camp_A_Floor.camp == "A", "the floor: look campFloor, with the camp's own material and colour on top")
	check(L1W.is(byName.Camp_A_Floor.box, 100, 3, -50, 60, 4, 60) and L1W.is(byName.Block_2.box, 5, 7, -2, 6, 4, 1), `and it is sizes.floor deep (4), its top at the camp's y; the walked-through sign beside it is as written ({L1W.show(byName.Camp_A_Floor.box)})`)
	check(byName.Camp_A_Fence_1.look == "wall" and byName.Camp_A_Fence_1.material == "WoodPlanks" and byName.Camp_A_Fence_1.color == nil, "the fence: look wall, and whichever of material and colour the camp gives")
	check(byName.Gate_A_1.look == "gate" and byName.Gate_A_1.role == "gate" and byName.Gate_A_1.camp == "A" and L1W.is(byName.Gate_A_1.box, 100, 8, -19.5, 12, 6, 1) and L1W.is(byName.Gate_A_2.box, 110, 8, -80.5, 14, 6, 1), "Gate_A_1 is the entry gate's box and Gate_A_2 the exit's, look gate")
	check(byName.Camp_A_Obstacle_1.material == "Slate" and byName.Camp_A_Obstacle_1.color[3] == 3 and byName.Camp_A_Obstacle_1.collide == true, "cover keeps its own material and colour")
	check(byName.Camp_A_Checkpoint.look == "checkpoint" and byName.Camp_A_Checkpoint.collide == false and byName.Camp_A_Checkpoint.camp == "A", "the checkpoint marker: look checkpoint, a marker nobody is stopped by")
	check(byName.Barrier_A_3.role == "barrier" and byName.Barrier_A_3.look == nil and byName.Barrier_A_3.collide == true and byName.Barrier_A_3.camp == "A" and L1W.is(byName.Barrier_A_3.box, 66, 45, -50, 8, 80, 60), `Barrier_A_3 is the west wall, from the floor's edge, with no look at all ({L1W.show(byName.Barrier_A_3.box)})`)
	check(byName.Secret_lookout.look == "secret" and byName.Secret_lookout.collide == true and byName.Secret_lookout_Sign.look == "sign" and byName.Secret_lookout_Sign.text == "Needs: Double Jump" and byName.Secret_lookout_Sign.collide == false, "a secret is its marked block, solid, and a sign with its text that is walked through")

	local unsized = Geo.Pieces(level(), { fence = 1, floor = 4 }, 600)
	local unsizedNames: { [string]: boolean } = {}
	for _, piece in unsized or {} do
		unsizedNames[piece.name] = true
	end
	check(unsized ~= nil and #unsized == 17 and unsizedNames.Camp_A_Checkpoint == nil and unsizedNames.Secret_lookout_Sign == nil and unsizedNames.Secret_lookout == true and unsizedNames.Gate_A_2 == true, "sizes the config does not give: no checkpoint marker and no sign are built, and everything else is")

	local open = level()
	open.barrier = nil
	local unwalled = Geo.Pieces(open, L1W.sizes, 600)
	check(unwalled ~= nil and #unwalled == 15, "a layout with no barrier has no wall Parts")
	local sparse = Geo.Pieces({ version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40, blocks = { { look = "lobby", x = 0, y = -0.5, z = 0, sx = 40, sy = 1, sz = 40 } } } :: any, L1W.sizes, 600)
	check(sparse ~= nil and #sparse == 1 and sparse[1].name == "Block_1" and L1W.is(sparse[1].box, 0, -2, 0, 40, 4, 40), `a lobby file that leaves camps, secrets and route out is its blocks, and its thin floor is made as deep as a camp's ({sparse and L1W.show(sparse[1].box)})`)

	local exact, exactProblem = Geo.Pieces(level(), L1W.sizes, 19)
	local over, overProblem = Geo.Pieces(level(), L1W.sizes, 18)
	check(exact ~= nil and exactProblem == nil and over == nil and overProblem ~= nil and string.find(overProblem, "19", 1, true) ~= nil, `at most maxParts Parts: 19 of 19 builds, 19 of 18 does not ({overProblem})`)
	local gated = level()
	gated.camps[1].fence = nil
	local refused, why = Geo.Pieces(gated, L1W.sizes, 600)
	check(refused == nil and why ~= nil and string.find(why, "camp A", 1, true) ~= nil, `a camp with gates and no fence is refused, by name ({why})`)
	gated.camps[1].gates = {}
	check(Geo.Pieces(gated, L1W.sizes, 600) ~= nil, "with no gates either it builds: a camp with open edges")
	local flat = level()
	flat.blocks[1].sy = 0
	local nan = level()
	nan.blocks[2].x = 0 / 0
	local flatPieces, flatWhy = Geo.Pieces(flat, L1W.sizes, 600)
	check(flatPieces == nil and flatWhy ~= nil and string.find(flatWhy, "Road", 1, true) ~= nil and Geo.Pieces(nan, L1W.sizes, 600) == nil, `a block with no height, or a position that is not a number, is refused by name ({flatWhy})`)
	local unresolved, unresolvedWhy = Geo.Pieces({ version = 1, arena = "Village" } :: any, L1W.sizes, 600)
	check(unresolved == nil and unresolvedWhy ~= nil and string.find(unresolvedWhy, "Village", 1, true) ~= nil, "a layout that still names its arena is refused: it goes through FromArena first")
end
L1W.pieceTests()

-- What Pieces refuses (the fix round's ruling 6: zero and empty mean the same on both sides; a
-- block or a piece of cover with a size of 0 or less is refused here and by check_levels.py
-- alike). Each case is one change to a layout that builds. Pieces is called behind a pcall, as
-- LevelService calls it: a rule that throws where it should refuse fails its check instead of
-- stopping the bundle.
function L1W.refused(layout: any, sizes: any, word: string): (boolean, string)
	local ok, pieces, why = pcall(L1W.Geo.Pieces, layout, sizes, 600)
	if not ok then
		return false, `it threw: {tostring(pieces)}`
	end
	if pieces ~= nil then
		return false, `it was built, {#pieces} Parts`
	end
	if type(why) ~= "string" or string.find(why, word, 1, true) == nil then
		return false, `refused without naming "{word}": {tostring(why)}`
	end
	return true, why
end

function L1W.refuseTests(): ()
	print(" Pieces: a size of 0 or less, and a camp with no floor depth, are refused")
	local Geo = L1W.Geo
	local function level(): any
		return {
			version = 1,
			start = { x = 0, y = 5, z = 0 },
			killY = -40,
			barrier = { height = 80, thickness = 8 },
			camps = { L1W.camp() },
			blocks = {
				{ name = "Road", look = "path", x = 20, y = 3, z = -10, sx = 100, sy = 4, sz = 14 },
				{ name = "Plank", look = "path", x = 20, y = 4.5, z = 20, sx = 10, sy = 1, sz = 4 },
				{ name = "Notice", look = "sign", x = 5, y = 7, z = -2, sx = 6, sy = 4, sz = 1, collide = false, text = "MAP" },
			},
			secrets = { { id = "lookout", needs = "doubleJump", x = 40, y = 30, z = -10, sx = 8, sy = 2, sz = 8, sign = { x = 44, y = 5, z = 2, text = "Needs: Double Jump" } } },
			route = {},
		}
	end
	local good, goodWhy = Geo.Pieces(level(), L1W.sizes, 600)
	check(good ~= nil and goodWhy == nil and #good == 20, `the layout these cases change builds as it stands: 20 Parts ({good and #good}{if goodWhy ~= nil then ", " .. goodWhy else ""})`)

	-- A block: each axis, at 0 and under it. Thin ground is deepened, so a block with no height
	-- must be refused BEFORE that rule could make it one with a height.
	local unsound = 0
	local first = ""
	local cases = 0
	for _, name in { "Road", "Plank", "Notice" } do
		for _, axis in { "sx", "sy", "sz" } do
			for _, size in { 0, -3 } do
				local layout = level()
				for _, block in layout.blocks do
					if block.name == name then
						block[axis] = size
					end
				end
				cases += 1
				local ok, why = L1W.refused(layout, L1W.sizes, name)
				if not ok then
					unsound += 1
					if first == "" then
						first = `{name}.{axis} = {size}: {why}`
					end
				end
			end
		end
	end
	check(unsound == 0, `a block with a size of 0 or less on any axis is refused by name: a thick one, a thin one over the void, a walked-through one ({cases} cases, {unsound} wrong{if first ~= "" then ", first " .. first else ""})`)

	-- A piece of cover.
	unsound, first, cases = 0, "", 0
	for _, axis in { "sx", "sy", "sz" } do
		for _, size in { 0, -2 } do
			local layout = level()
			layout.camps[1].obstacles[1][axis] = size
			cases += 1
			local ok, why = L1W.refused(layout, L1W.sizes, "Camp_A_Obstacle_1")
			if not ok then
				unsound += 1
				if first == "" then
					first = `{axis} = {size}: {why}`
				end
			end
		end
	end
	check(unsound == 0, `a piece of cover with a size of 0 or less on any axis is refused by name ({cases} cases, {unsound} wrong{if first ~= "" then ", first " .. first else ""})`)

	-- A camp, a secret, and the sizes the config gives.
	local flatCamp = level()
	flatCamp.camps[1].sx = 0
	local thinCamp = level()
	thinCamp.camps[1].sz = -60
	local okA, whyA = L1W.refused(flatCamp, L1W.sizes, "Camp_A_Floor")
	local okB, whyB = L1W.refused(thinCamp, L1W.sizes, "Camp_A_")
	check(okA and okB, `a camp with no width, or a depth under 0, is refused ({whyA}; {whyB})`)
	local noSecret = level()
	noSecret.secrets[1].sy = 0
	local okC, whyC = L1W.refused(noSecret, L1W.sizes, "Secret_lookout")
	check(okC, `a secret with no height is refused by name ({whyC})`)
	local okD, whyD = L1W.refused(level(), { fence = 1, floor = 4, checkpoint = { sx = 2, sy = 0, sz = 2 } }, "Camp_A_Checkpoint")
	local okE, whyE = L1W.refused(level(), { fence = 1, floor = 4, sign = { sx = 6, sy = 4, sz = -6 } }, "Secret_lookout_Sign")
	check(okD and okE, `a marker or a sign size of 0 or less, if one is ever handed in, is refused too ({whyD}; {whyE})`)
	local okF, whyF = L1W.refused({ version = 1, start = { x = 0, y = 0, z = 0 }, killY = -40, blocks = { { name = "Speck", look = "lobby", x = 0, y = 0, z = 0, sx = 40, sy = 0, sz = 40 } } } :: any, L1W.sizes, "Speck")
	check(okF, `in a lobby file as in a level ({whyF})`)
	local wide = level()
	wide.blocks[1].sx = math.huge
	local okG, whyG = L1W.refused(wide, L1W.sizes, "Road")
	check(okG, `and a size that is not finite ({whyG})`)

	-- The floor's depth is the config's: without one a camp has no floor.
	unsound, first, cases = 0, "", 0
	for _, floor in { false, 0, -4, 0 / 0, math.huge } do
		local sizes: any = { fence = 1, checkpoint = L1W.sizes.checkpoint, sign = L1W.sizes.sign }
		if floor ~= false then
			sizes.floor = floor
		end
		cases += 1
		local ok, why = L1W.refused(level(), sizes, "levels.floorThickness")
		local named = ok and string.find(why, "camp A", 1, true) ~= nil
		if not named then
			unsound += 1
			if first == "" then
				first = `floor = {tostring(floor)}: {why}`
			end
		end
	end
	check(unsound == 0, `a camp and no floor depth (none, 0, under 0, not a number, not finite): refused, naming the camp and levels.floorThickness ({cases} cases, {unsound} wrong{if first ~= "" then ", first " .. first else ""})`)
	local campless = level()
	campless.camps = {}
	local ok, lobby, why = pcall(Geo.Pieces, campless, { fence = 1, sign = L1W.sizes.sign }, 600)
	local plank = nil
	for _, piece in if ok and lobby ~= nil then lobby else {} do
		if piece.name == "Plank" then
			plank = piece.box
		end
	end
	check(ok and lobby ~= nil and why == nil and #lobby == 5 and L1W.is(plank, 20, 4.5, 20, 10, 1, 4), `a layout with no camp builds without one, its blocks as the layout writes them ({if ok then tostring(why) else tostring(lobby)})`)
	local deep = Geo.Pieces(level(), { fence = 1, floor = 6.5 }, 600)
	local floorBox, plankBox, roadBox = nil, nil, nil
	for _, piece in deep or {} do
		if piece.name == "Camp_A_Floor" then
			floorBox = piece.box
		elseif piece.name == "Plank" then
			plankBox = piece.box
		elseif piece.name == "Road" then
			roadBox = piece.box
		end
	end
	check(L1W.is(floorBox, 100, 1.75, -50, 60, 6.5, 60) and L1W.is(plankBox, 20, 1.75, 20, 10, 6.5, 4) and L1W.is(roadBox, 20, 1.75, -10, 100, 6.5, 14), `the depth is whatever the config says: at 6.5 the floor, the plank and the 4-deep road are all 6.5 deep, tops unmoved ({L1W.show(floorBox)}; {L1W.show(plankBox)}; {L1W.show(roadBox)})`)
end
L1W.refuseTests()

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
