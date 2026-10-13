-- Cases for L1's world, the pure LevelGeometry (docs/INTERFACES.md "L1 contracts" → "A — the
-- world"): appended to the bundle by run_harness.py after the earlier test files, so their
-- `load`, `check` and `near` are in scope. Everything hangs off the L1W table (the 200-local
-- limit). LevelService and BarrierGroups are Instance work and cannot be loaded here.

print("L1: the world (LevelGeometry)")

local L1W: any = { Geo = load("LevelGeometry") }

L1W.sizes = { fence = 1, checkpoint = { sx = 2, sy = 10, sz = 2 }, sign = { sx = 6, sy = 4, sz = 6 } }

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
-- entry gate in the middle of the south side and the exit gate off-centre on the north side.
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
	check(#wall == 4 and L1W.is(wall[1], 0, 40, -60, 128, 80, 8) and L1W.is(wall[2], 0, 40, 60, 128, 80, 8) and L1W.is(wall[3], -60, 40, 0, 8, 80, 112) and L1W.is(wall[4], 60, 40, 0, 8, 80, 112), "and the invisible wall is the arena's four (128 x 80 x 8 at z -60 and 60; 8 x 80 x 112 at x -60 and 60)")
	local pieces = Geo.Pieces(fresh, L1W.sizes, 600)
	check(pieces ~= nil and #pieces == 17 and pieces[1].name == "Camp_arena_Floor" and pieces[17].name == "Barrier_arena_4", `the arena is 17 Parts: a floor, 4 fence, 8 cover, 4 wall ({pieces and #pieces})`)
	local bounds = Geo.Bounds(fresh)
	check(bounds.minX == -55 and bounds.maxX == 55 and bounds.minZ == -55 and bounds.maxZ == 55 and bounds.minY == -1 and bounds.maxY == 4, "its bounds are the floor, a stud under it, and the fence's height")
end
L1W.arenaTests()

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
	-- The fence's outer faces: 30 + 1 from the centre in X, 20 + 1 in Z.
	check(near(boxes[1].z + boxes[1].sz / 2, -221) and near(boxes[2].z - boxes[2].sz / 2, -179) and near(boxes[3].x + boxes[3].sx / 2, 269) and near(boxes[4].x - boxes[4].sx / 2, 331), "each inner face is on the fence's outer face (z -221 and -179, x 269 and 331)")
	check(near(boxes[1].sz, 8) and near(boxes[2].sz, 8) and near(boxes[3].sx, 8) and near(boxes[4].sx, 8), "each is barrier.thickness deep, outward")
	check(near(boxes[1].x - boxes[1].sx / 2, 261) and near(boxes[1].x + boxes[1].sx / 2, 339) and near(boxes[3].z - boxes[3].sz / 2, -221) and near(boxes[3].z + boxes[3].sz / 2, -179), "the north and south boxes run past the west and east ones (x 261 to 339); those fill between them (z -221 to -179)")

	-- Walk three rings round the camp, just outside the fence, in the middle of the wall and
	-- just inside its outer face, at three heights: every point is in the wall.
	local holes = 0
	local firstHole = ""
	for _, out in { 0.01, 4, 7.99 } do
		local a = 31 + out
		local b = 21 + out
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
	check(not L1W.inside(boxes, camp.x + 30.99, 52, camp.z) and not L1W.inside(boxes, camp.x, 52, camp.z - 20.99) and not L1W.inside(boxes, camp.x + 30.99, 52, camp.z + 20.99), "and it does not reach inside the fence's outer face")
	check(not L1W.inside(boxes, camp.x + 35, 11.9, camp.z) and not L1W.inside(boxes, camp.x + 35, 92.1, camp.z), "nor under the floor's top, nor above its height")

	local shallow = Geo.BarrierBoxes(camp, 2, { height = 80, thickness = 0.5 })
	check(#shallow == 4 and near(shallow[1].sz, 2) and near(shallow[3].sx, 2) and near(shallow[1].z + shallow[1].sz / 2, -222), "a wall thinner than the fence is made as deep as the fence, and still starts at its outer face")
	check(#Geo.BarrierBoxes(camp, 1, { height = 0, thickness = 8 }) == 0 and #Geo.BarrierBoxes(camp, 0, { height = 80, thickness = 0 }) == 0, "no height, or no depth at all: no wall")
	camp.fence = nil
	camp.gates = {}
	local unfenced = Geo.BarrierBoxes(camp, 1, barrier)
	check(#unfenced == 4 and near(unfenced[4].x - 4, 331), "a camp with no fence: the wall stands where the fence's outer face would be")
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

-- When the gates close the run moves every fighter whose root is outside the camp's floor
-- rectangle (StageFlow's zone.rect: camp.x, camp.z, sx / 2, sz / 2; WaveService's close). That
-- rule and this module must mean the same rectangle: nothing that turns solid at the close may
-- reach inside it, and the gate gaps and the wall's band must lie outside it.
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
		local floor = Geo.FloorBox(camp)
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
	check(#wall == 4 and not inRect(camp.x, wall[1].z + wall[1].sz / 2) and not inRect(wall[4].x - wall[4].sx / 2, camp.z) and L1W.inside(wall, gates[1].x, camp.y + 3, gates[1].z + 1) and L1W.inside(wall, gates[2].x, camp.y + 3, gates[2].z - 1), "so is a root anywhere in the wall's band, which also runs across both gate gaps just outside the gates")
end
L1W.closeTests()

function L1W.boxTests(): ()
	print(" The other boxes, and Bounds")
	local Geo = L1W.Geo
	local camp = L1W.camp()
	local floor = Geo.FloorBox(camp)
	check(L1W.is(floor, 100, 4.5, -50, 60, 1, 60) and near(floor.y + floor.sy / 2, camp.y), "the floor is 1 stud thick with its top at camp.y")
	local cover = Geo.ObstacleBoxes(camp)
	check(#cover == 1 and L1W.is(cover[1], 95, 6.5, -55, 4, 3, 6), "cover stands on the floor")
	check(L1W.is(Geo.CheckpointBox(camp, L1W.sizes.checkpoint), 110, 10, -70, 2, 10, 2), "the checkpoint marker stands on the floor at camp.checkpoint")
	camp.checkpoint = nil
	check(Geo.CheckpointBox(camp, L1W.sizes.checkpoint) == nil, "and a camp with no checkpoint has no marker")
	local secret = { id = "lookout", needs = "doubleJump", x = 40, y = 30, z = -10, sx = 8, sy = 2, sz = 8, sign = { x = 44, y = 5, z = 2, text = "Needs: Double Jump" } }
	check(L1W.is(Geo.SecretBox(secret), 40, 30, -10, 8, 2, 8) and L1W.is(Geo.SignBox(secret, L1W.sizes.sign), 44, 7, 2, 6, 4, 6), "a secret's block is where the layout puts it; its sign rises from the sign's point")

	local layout: any = { version = 1, start = { x = 0, y = 5, z = 0 }, killY = -40, camps = { L1W.camp() }, blocks = {}, secrets = {}, route = {} }
	local bounds = Geo.Bounds(layout)
	check(bounds.minX == 70 and bounds.maxX == 130 and bounds.minZ == -80 and bounds.maxZ == -20 and bounds.minY == 4 and bounds.maxY == 11, "a camp alone: its floor, a stud under the top, and the fence's height above it")
	layout.blocks = { { look = "path", x = 20, y = 4, z = -50, sx = 100, sy = 2, sz = 14 } }
	local wider = Geo.Bounds(layout)
	check(wider.minX == -30 and wider.maxX == 130 and wider.minY == 3 and wider.minZ == -80 and wider.maxZ == -20 and wider.maxY == 11, "a block outside every camp widens it, on that side only")
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
	check(lobbyBounds.maxZ <= -1150 and #lobby.camps == 0, "and it lies over 150 studs clear of every camp (each within 1,000 of the origin)")
end
L1W.boxTests()

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
				{ name = "Road", look = "path", x = 20, y = 4, z = -10, sx = 100, sy = 2, sz = 14 },
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
	check(byName.Road.role == "block" and byName.Road.look == "path" and byName.Road.collide == true and byName.Road.text == nil and L1W.is(byName.Road.box, 20, 4, -10, 100, 2, 14), "a block is its own box in its own look, solid unless it says otherwise")
	check(byName.Block_2.collide == false and byName.Block_2.text == "MAP" and byName.Block_2.look == "sign", "collide = false and text are carried")
	check(byName.Camp_A_Floor.look == "campFloor" and byName.Camp_A_Floor.material == "Slate" and byName.Camp_A_Floor.color[1] == 9 and byName.Camp_A_Floor.camp == "A", "the floor: look campFloor, with the camp's own material and colour on top")
	check(byName.Camp_A_Fence_1.look == "wall" and byName.Camp_A_Fence_1.material == "WoodPlanks" and byName.Camp_A_Fence_1.color == nil, "the fence: look wall, and whichever of material and colour the camp gives")
	check(byName.Gate_A_1.look == "gate" and byName.Gate_A_1.role == "gate" and byName.Gate_A_1.camp == "A" and L1W.is(byName.Gate_A_1.box, 100, 8, -19.5, 12, 6, 1) and L1W.is(byName.Gate_A_2.box, 110, 8, -80.5, 14, 6, 1), "Gate_A_1 is the entry gate's box and Gate_A_2 the exit's, look gate")
	check(byName.Camp_A_Obstacle_1.material == "Slate" and byName.Camp_A_Obstacle_1.color[3] == 3 and byName.Camp_A_Obstacle_1.collide == true, "cover keeps its own material and colour")
	check(byName.Camp_A_Checkpoint.look == "checkpoint" and byName.Camp_A_Checkpoint.collide == false and byName.Camp_A_Checkpoint.camp == "A", "the checkpoint marker: look checkpoint, a marker nobody is stopped by")
	check(byName.Barrier_A_3.role == "barrier" and byName.Barrier_A_3.look == nil and byName.Barrier_A_3.collide == true and byName.Barrier_A_3.camp == "A" and L1W.is(byName.Barrier_A_3.box, 65, 45, -50, 8, 80, 62), `Barrier_A_3 is the west wall, with no look at all ({L1W.show(byName.Barrier_A_3.box)})`)
	check(byName.Secret_lookout.look == "secret" and byName.Secret_lookout.collide == true and byName.Secret_lookout_Sign.look == "sign" and byName.Secret_lookout_Sign.text == "Needs: Double Jump" and byName.Secret_lookout_Sign.collide == false, "a secret is its marked block, solid, and a sign with its text that is walked through")

	local unsized = Geo.Pieces(level(), { fence = 1 }, 600)
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
	check(sparse ~= nil and #sparse == 1 and sparse[1].name == "Block_1", "a lobby file that leaves camps, secrets and route out is its blocks")

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

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
