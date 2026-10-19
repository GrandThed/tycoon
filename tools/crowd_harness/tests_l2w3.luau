-- Cases for L2 W3, ice, the frost hammer, deep water and the island shrine
-- (docs/prompts/l2-w3-contract.md): the pure WorldReact's Cells, Chills and Freeze (L2-53, L2-54),
-- LevelGeometry.Pieces' ice pieces, StageFlow.Validate's ice and landing lines (L2-52, L2-58),
-- Plan's waters with Landing and FallLanding (L2-58), the shipped Forest Road (a crossing frozen
-- swing by swing to the island, the shrine behind ice) and the lines that act on these, read as
-- text (LevelService.React's ice branch, the rescue's landing, Frost Quake's launcher). Appended
-- last by run_harness.py, so every local of the earlier files is in scope (vec, check, load, L1,
-- W2). Everything hangs off the W3 table (the 200-local limit) and every group runs behind
-- L1.group. LevelService, WaveService and AbilityService cannot be loaded here: they execute what
-- these decide.

print("L2 W3: ice, the frost hammer, deep water and the island shrine (WorldReact, Pieces, Landing)")

local W3: any = {
	React = load("WorldReact"),
	Geo = load("LevelGeometry"),
	Flow = load("StageFlow"),
	Secret = load("SecretFlow"),
	Unlocks = load("Unlocks"),
	NAN = 0 / 0,
	-- A value that takes a key away in a test block's `over` (nil cannot be written into a table).
	NONE = {},
	-- The contract's numbers: cell 7, lift 0.2, thickness 1, reachDown 6, ahead 4.
	ice = { cell = 7, lift = 0.2, thickness = 1, reachDown = 6, ahead = 4 },
}

-- A frost swing as WeaponService.resolveMelee hands it to the listeners: an arc at `origin` along
-- `direction`, `size` studs (the variant's range), `arc` degrees.
function W3.arc(origin: any, direction: any, size: number?, arc: number?): any
	return { shape = "arc", origin = origin, direction = direction, size = size or 9, arcDegrees = arc or 140 }
end

-- An ice cell's piece box whose centre is (x, z) and whose top is `top`, 1 deep.
function W3.cell(x: number, z: number, top: number): any
	return { x = x, y = top - 0.5, z = z, sx = 6, sy = 1, sz = 6 }
end

function W3.cellsTests(): ()
	print(" WorldReact.Cells: a footprint cut into even cells (L2-53)")
	local R = W3.React
	local creek = { x = -400, y = -3, z = 52, sx = 20, sy = 4, sz = 88 }
	local nx, nz = R.CellGrid(creek, 7)
	check(nx == 3 and nz == 13, `20 x 88 at 7: 3 across, 13 along ({nx}, {nz})`)
	local cells = R.Cells(creek, 7)
	check(#cells == 39, `39 cells ({#cells})`)
	local first, second, fourth, last = cells[1], cells[2], cells[4], cells[39]
	check(near(first.x, -410 + 10 / 3) and near(first.z, 8 + 88 / 26) and near(first.sx, 20 / 3) and near(first.sz, 88 / 13), "the first cell is the north-west one, even widths")
	check(near(second.x, -400) and near(second.z, first.z), "X runs fastest")
	check(near(fourth.x, first.x) and near(fourth.z, 8 + 3 * 88 / 26), "then Z")
	check(near(last.x, -390 - 10 / 3) and near(last.z, 96 - 88 / 26), "the last is the south-east one")
	check(first.y == -3 and first.sy == 4, "each keeps the block's y and sy")
	local total = 0
	for _, cell in cells do
		total += cell.sx * cell.sz
	end
	check(near(total, 20 * 88, 1e-6), "the cells cover the footprint exactly")
	nx, nz = R.CellGrid({ x = 0, y = 0, z = 0, sx = 21, sy = 1, sz = 14 }, 7)
	check(nx == 3 and nz == 2, `an exact multiple is not one more (21 x 14 at 7: {nx}, {nz})`)
	nx, nz = R.CellGrid({ x = 0, y = 0, z = 0, sx = 3, sy = 1, sz = 21.5 }, 7)
	check(nx == 1 and nz == 4, `a side under a cell is one cell, a little over is one more ({nx}, {nz})`)
	local bad = { 0, -7, W3.NAN, math.huge }
	local empty = true
	for _, cell in bad do
		local a, b = R.CellGrid(creek, cell)
		empty = empty and a == 0 and b == 0 and #R.Cells(creek, cell) == 0
	end
	check(empty, "a cell of 0, under 0, NaN or endless: no cells")
	check(#R.Cells({ x = 0, y = 0, z = 0, sx = 0, sy = 1, sz = 10 }, 7) == 0 and #R.Cells({ x = 0, y = 0, z = 0, sx = 10, sy = 1, sz = -2 }, 7) == 0, "a footprint with no size: no cells")
	check(#R.Cells({ x = W3.NAN, y = 0, z = 0, sx = 10, sy = 1, sz = 10 }, 7) == 0 and #R.Cells({ x = 0, y = 0, z = 0, sx = math.huge, sy = 1, sz = 10 }, 7) == 0, "a centre or a size that is not finite: no cells")
end
L1.group("l2w3 cellsTests", W3.cellsTests)

-- A layout with deep water: Water (react ice) 21 x 14 at top -1, a bridge over its west column
-- (top 0), a sunk block under its east column (top -2: below the water's top), a secret on the
-- middle of its second row, a fire bramble, Mist (walked through, over the water's top) on the
-- first row's middle, and Pool, deep water with no react.
function W3.layout(): any
	return {
		version = 1,
		start = { x = 0, y = 0, z = -30 },
		killY = -40,
		camps = {},
		blocks = {
			{ name = "Road", look = "path", x = 0, y = -2, z = -30, sx = 30, sy = 4, sz = 20 },
			{ name = "Water", look = "water", x = 0, y = -3, z = 0, sx = 21, sy = 4, sz = 14, collide = false, react = "ice", landing = { x = 0, y = 0, z = -30 } },
			{ name = "Bridge", look = "path", x = -7, y = -2, z = 0, sx = 7, sy = 4, sz = 14 },
			{ name = "Sunk", look = "ground", x = 7, y = -4, z = 0, sx = 7, sy = 4, sz = 14 },
			{ name = "Bramble", look = "bramble", x = 0, y = 4, z = -12, sx = 12, sy = 8, sz = 2, react = "fire" },
			{ name = "Pool", look = "water", x = 40, y = -3, z = 0, sx = 14, sy = 4, sz = 14, collide = false },
			{ name = "Mist", look = "water", x = 0, y = 2, z = -3.5, sx = 2, sy = 2, sz = 2, collide = false },
		},
		secrets = {
			{ id = "chest", needs = "ice", x = 0, y = 1, z = 3.5, sx = 2, sy = 2, sz = 2, sign = { x = 0, y = 0, z = -20, text = "" } },
		},
		route = {},
	}
end

function W3.piecesTests(): ()
	print(" LevelGeometry.Pieces: an ice block's cells (L2-53)")
	local Geo = W3.Geo
	local sizes = { fence = 1, floor = 4, ice = { cell = 7, lift = 0.2, thickness = 1 } }
	local pieces, refusal = Geo.Pieces(W3.layout(), sizes, 600)
	check(pieces ~= nil and refusal == nil, `the layout builds ({tostring(refusal)})`)
	if pieces == nil then
		return
	end
	local ice, byName, lastBlock, firstIce = {}, {}, 0, 0
	for index, piece in pieces do
		byName[piece.name] = piece
		if piece.role == "block" then
			lastBlock = index
		elseif piece.role == "ice" then
			table.insert(ice, piece)
			if firstIce == 0 then
				firstIce = index
			end
		end
	end
	-- 3 x 2 cells: column 1 under the bridge (top 0 > -1), column 3 over the sunk block (top -2),
	-- row 2's middle cell under the chest (top 2).
	check(#ice == 3, `six cells, three covered: three pieces ({#ice})`)
	check(byName.Ice_Water_1 == nil and byName.Ice_Water_4 == nil, "no cell under the bridge (a colliding block over the water's top)")
	check(byName.Ice_Water_3 ~= nil and byName.Ice_Water_6 ~= nil, "a block below the water's top covers nothing")
	check(byName.Ice_Water_5 == nil and byName.Ice_Water_2 ~= nil, "a secret over the water's top covers its cell")
	check(byName.Ice_Water_2 ~= nil, "a block nothing meets (Mist) covers nothing, however high")
	local piece = byName.Ice_Water_2
	if piece ~= nil then
		local box = piece.box
		check(piece.role == "ice" and piece.look == "ice" and piece.collide == false and piece.camp == nil and piece.react == nil, "an ice piece: role ice, look ice, walked through, no camp, no react")
		check(near(box.x, 0) and near(box.z, -3.5) and near(box.sx, 7) and near(box.sz, 7), `its footprint is the cell's ({box.x}, {box.z}, {box.sx}, {box.sz})`)
		check(near(box.y + box.sy / 2, -0.8) and near(box.sy, 1), `its top is lift over the water's top, thickness deep ({box.y}, {box.sy})`)
	end
	check(firstIce == lastBlock + 1, "the ice pieces follow the blocks")
	local others = 0
	for _, each in ice do
		if not string.find(each.name, "^Ice_Water_") then
			others += 1
		end
	end
	check(others == 0, "only the ice block has cells (not Pool's deep water, not the fire bramble)")
	check(byName.Water ~= nil and byName.Water.collide == false and byName.Water.react == "ice", "the water itself is a block that does not collide and keeps its react")

	-- The bridge's edge holds a centre on it (edges included, as sim_range.ice_cells).
	local edge = W3.layout()
	edge.blocks[3].sx = 0.5
	edge.blocks[3].x = -3.5 - 0.25 - 3.5
	local onEdge = Geo.Pieces(edge, sizes, 600)
	local edgeNames = {}
	for _, each in onEdge or {} do
		edgeNames[each.name] = true
	end
	check(onEdge ~= nil and edgeNames.Ice_Water_1 == nil, "a cell centre on a cover's edge is covered")

	local plain = Geo.Pieces(W3.layout(), { fence = 1, floor = 4 }, 600)
	local none = 0
	for _, each in plain or {} do
		if each.role == "ice" then
			none += 1
		end
	end
	check(plain ~= nil and none == 0 and #plain == #pieces - 3, "without levels.react.ice: no cells, the water only deep")
	local tight = Geo.Pieces(W3.layout(), sizes, #pieces)
	check(tight ~= nil, "exactly maxParts Parts builds")
	local over, why = Geo.Pieces(W3.layout(), sizes, #pieces - 1)
	check(over == nil and why ~= nil, `one Part over refuses ({tostring(why)})`)
	local tiny, said = Geo.Pieces(W3.layout(), { fence = 1, floor = 4, ice = { cell = 0.001, lift = 0.2, thickness = 1 } }, 600)
	check(tiny == nil and said ~= nil and string.find(said, "Water", 1, true) ~= nil and string.find(said, "maxParts", 1, true) ~= nil, `a cell far under the water's size is refused before a cell is made, by name ({tostring(said)})`)
end
L1.group("l2w3 piecesTests", W3.piecesTests)

function W3.chillsTests(): ()
	print(" WorldReact.Chills: which ice cell a swing freezes (L2-54)")
	local R = W3.React
	local east = vec(1, 0, 0)
	local origin = vec(0, 3, 0)
	local swing = W3.arc(origin, east)
	local function chills(fx: any, box: any, reachDown: number?, ahead: number?): boolean
		return R.Chills(fx, box, reachDown or 6, ahead or 4)
	end
	-- Radius: size 9 + ahead 4 = 13.
	check(chills(swing, W3.cell(12.99, 0, -0.8)), "a centre 12.99 ahead: frozen")
	check(chills(swing, W3.cell(13, 0, -0.8)), "13 ahead (range + ahead): frozen, the edge included")
	check(not chills(swing, W3.cell(13.01, 0, -0.8)), "13.01: not")
	check(not chills(swing, W3.cell(9.5, 0, -0.8), 6, 0) and chills(swing, W3.cell(9, 0, -0.8), 6, 0), "ahead counts: with 0 the reach is the range")
	-- Angle: 140 degrees = 70 each side.
	local function at(degrees: number, distance: number): any
		local radians = math.rad(degrees)
		return W3.cell(distance * math.cos(radians), distance * math.sin(radians), -0.8)
	end
	check(chills(swing, at(69.9, 8)) and chills(swing, at(-69.9, 8)), "69.9 degrees either side: frozen")
	check(not chills(swing, at(70.1, 8)) and not chills(swing, at(-70.1, 8)), "70.1: not")
	check(not chills(swing, at(180, 3)), "behind: not")
	check(chills(W3.arc(origin, east, 9, 360), at(180, 3)) and chills(W3.arc(origin, east, 9, 400), at(120, 12)), "360 or more: all round")
	check(chills(W3.arc(origin, vec(0, 1, 0), 9, 360), at(90, 6)), "all round needs no heading (a spin)")
	check(not chills(W3.arc(origin, east, 9, 0), at(0, 3)) and not chills(W3.arc(origin, east, 9, -90), at(0, 3)), "an arc of 0 or under: nothing")
	check(not chills({ shape = "arc", origin = origin, direction = east, size = 9 }, at(0, 3)), "an arc with no arcDegrees: nothing")
	check(chills(W3.arc(origin, vec(1, 5, 0)), at(0, 8)) and chills(W3.arc(origin, vec(1, 5, 0)), at(60, 8)), "the direction is judged flat")
	check(chills(W3.arc(origin, vec(0, 1, 0)), W3.cell(0, 0, -0.8)), "a centre right under the origin is in every sector")
	check(not chills(W3.arc(origin, vec(0, 1, 0)), at(0, 3)), "a direction with no flat part freezes nothing else")
	-- The band: the top from the origin down to reachDown under it.
	check(chills(swing, W3.cell(5, 0, 3)) and not chills(swing, W3.cell(5, 0, 3.01)), "a top level with the origin: frozen; above it: not")
	check(chills(swing, W3.cell(5, 0, -3)) and not chills(swing, W3.cell(5, 0, -3.01)), "a top reachDown under: frozen; lower: not")
	check(not chills(swing, W3.cell(5, 0, -0.8), -1), "a reachDown under 0 reaches nothing")
	check(not chills(W3.arc(vec(0, 3 + 18, 0), east), W3.cell(5, 0, -0.8)), "a swing at the top of a jump freezes nothing")
	-- Shapes.
	local shapes = { "capsule", "sphere", "ray", "cone", "lunge" }
	local any = false
	for _, shape in shapes do
		any = any or chills({ shape = shape, origin = origin, direction = east, size = 9, arcDegrees = 360, width = 4 }, at(0, 3))
	end
	check(not any, "a capsule, sphere, ray or any other shape freezes nothing")
	-- Numbers that are not finite.
	local nan = W3.NAN
	check(not chills(W3.arc(vec(nan, 3, 0), east), at(0, 3)) and not chills(W3.arc(vec(0, 3, 0), vec(nan, 0, 0)), at(0, 3)), "an origin or a direction that is not finite: nothing")
	check(not chills(W3.arc(origin, east, nan), at(0, 3)) and not chills(W3.arc(origin, east, 9, nan), at(0, 3)) and not chills(W3.arc(origin, east, math.huge), at(0, 3)), "a size or an arc that is not finite: nothing")
	check(not chills(swing, at(0, 3), nan) and not chills(swing, at(0, 3), 6, math.huge) and not chills(swing, at(0, 3), math.huge), "a reachDown or an ahead that is not finite: nothing")
	check(not chills(swing, { x = nan, y = -1.3, z = 0, sx = 6, sy = 1, sz = 6 }) and not chills(swing, { x = 3, y = -1.3, z = 0, sx = 6, sy = nan, sz = 6 }) and not chills(swing, { x = 3, y = math.huge, z = 0, sx = 6, sy = 1, sz = 6 }), "a cell that is not finite: nothing")
end
L1.group("l2w3 chillsTests", W3.chillsTests)

function W3.freezeTests(): ()
	print(" WorldReact.Freeze: one strike of ice on the cells (L2-54)")
	local R = W3.React
	local east = vec(1, 0, 0)
	local function cells(): any
		return {
			{ box = W3.cell(4, 0, -0.8), frozen = false },
			{ box = W3.cell(-4, 0, -0.8), frozen = false },
			{ box = W3.cell(10, 0, -0.8), frozen = true },
			{ box = W3.cell(11, 3, -0.8), frozen = false },
			{ box = W3.cell(30, 0, -0.8), frozen = false },
		}
	end
	local swing = W3.arc(vec(0, 3, 0), east)
	local list = cells()
	local frozen = R.Freeze(list, "ice", swing, 6, 4)
	check(#frozen == 2 and frozen[1] == 1 and frozen[2] == 4, `the unfrozen cells ahead freeze, ascending ({table.concat(frozen, ", ")})`)
	check(list[1].frozen and list[4].frozen and not list[2].frozen and not list[5].frozen and list[3].frozen, "written back; behind and too far stay water; the frozen stays frozen")
	local again = R.Freeze(list, "ice", swing, 6, 4)
	check(#again == 0, "the same swing again freezes nothing new (a frozen cell is skipped)")
	for _, element in { "fire", "lava", "" } do
		list = cells()
		check(#R.Freeze(list, element, swing, 6, 4) == 0 and not list[1].frozen, `"{element}" freezes nothing`)
	end
	list = cells()
	check(#R.Freeze(list, nil, swing, 6, 4) == 0 and not list[1].frozen, "no element (a Longbow arrow, an ability): nothing")
	-- An ability's strike: StrikeElement gives it none, so Frost Quake freezes nothing.
	local weapons = FIXTURES.proving.weapons
	local quake = weapons.frostHammer ~= nil and weapons.frostHammer.ability ~= nil and weapons.frostHammer.ability.id or "frostQuake"
	local element = R.StrikeElement(weapons, "frostHammer", quake)
	list = cells()
	check(element == nil and #R.Freeze(list, element, W3.arc(vec(0, 3, 0), east, 9, 360), 6, 4) == 0, "Frost Quake's strike carries no element and freezes nothing")
	check(R.StrikeElement(weapons, "frostHammer", nil) == "ice", "the Frost Hammer's swing carries ice (ProvingGrounds.json)")
	list = cells()
	check(#R.Freeze(list, "ice", { shape = "capsule", origin = vec(0, 3, 0), direction = east, size = 20, width = 4 }, 6, 4) == 0, "a capsule of ice freezes nothing")
	list = cells()
	check(#R.Freeze(list, "ice", swing, 6, 0) == 1 and list[1].frozen and not list[4].frozen, "ahead is handed through")
	list = cells()
	check(#R.Freeze(list, "ice", W3.arc(vec(0, 3, 0), east), 3, 4) == 0, "and reachDown")
	check(R.Need({ fireHits = 6, pad = 0.5 }, "ice") == nil, "ice has no strike count (fire alone has one)")
end
L1.group("l2w3 freezeTests", W3.freezeTests)

-- Validate's lines on a copy of Forest Road with one test block of its own at the end: every line
-- that names it.
function W3.validateTests(): ()
	print(" StageFlow.Validate: ice and landing lines (L2-52, L2-58)")
	local got = L1.real.resolve("forestRoad")
	local level, layout = got.level, got.layout
	if level == nil or layout == nil then
		check(false, "Forest Road resolves (the cases below need it)")
		return
	end
	local ranks = L1.real.ranks()
	local function lines(block: any, more: ((any) -> ())?): { string }
		local copyLayout = L1.copy(layout)
		copyLayout.shortcuts = copyLayout.shortcuts or {}
		table.insert(copyLayout.shortcuts, { id = "testHole", name = "Test Hole", x = 0, y = 400, z = 40, sx = 4, sy = 4, sz = 4 })
		table.insert(copyLayout.blocks, block)
		if more ~= nil then
			more(copyLayout)
		end
		local found = {}
		for _, line in W3.Flow.Validate(L1.copy(level), copyLayout, L1.real.kinds, ranks, L1.real.rules, FIXTURES.proving.crowd.maxAlive) do
			if string.find(line, "TestWater", 1, true) then
				table.insert(found, line)
			end
		end
		return found
	end
	-- `over` replaces keys of the test water; W3.NONE takes a key away.
	local function water(over: any?): any
		local block = { name = "TestWater", look = "water", x = 0, y = 400, z = 20, sx = 14, sy = 2, sz = 14, collide = false, react = "ice", landing = { x = 0, y = 401, z = 0 } }
		for key, value in over or {} do
			block[key] = if value == W3.NONE then nil else value
		end
		return block
	end
	local function said(found: { string }): string
		return table.concat(found, "; ")
	end
	-- Exactly one line, holding every text of `texts`.
	local function says(found: { string }, ...: string): boolean
		if #found ~= 1 then
			return false
		end
		for _, text in { ... } do
			if string.find(found[1], text, 1, true) == nil then
				return false
			end
		end
		return true
	end
	local accepted = {
		{ "an ice block that does not collide, with a landing", water() },
		{ "an ice block with no landing (its falls go to the safe point)", water({ landing = W3.NONE }) },
		{ "deep water with no react (decorative)", water({ react = W3.NONE, landing = W3.NONE }) },
		{ "an ice block with collide false written", water({ collide = false }) },
	}
	for _, case in accepted do
		local found = lines(case[2])
		check(#found == 0, `{case[1]}: accepted ({said(found)})`)
	end
	local refused = {
		{ "an ice block that collides (collide left out)", water({ collide = W3.NONE }), { "block TestWater is ice and collides" } },
		{ "an ice block with collide true", water({ collide = true }), { "block TestWater is ice and collides" } },
		{ "an ice block that opens a shortcut", water({ opens = "testHole" }), { "block TestWater is ice and opens testHole" } },
		{ "a fire block with a landing", water({ react = "fire", collide = true }), { "block TestWater has a landing and is not ice" } },
		{ "deep water with no react and a landing", water({ react = W3.NONE }), { "block TestWater has a landing and is not ice" } },
		{ "a fire block that does not collide (W2's line, unchanged)", water({ react = "fire", landing = W3.NONE }), { "block TestWater reacts and does not collide" } },
		{ "a word that is no element (W2's line)", water({ react = "lava", collide = true, landing = W3.NONE }), { 'block TestWater: react is lava, neither "fire" nor "ice"' } },
		{ "a landing with a NaN y", water({ landing = { x = 0, y = W3.NAN, z = 0 } }), { "block TestWater: landing.y is ", ", not a number" } },
		{ "a landing with no z", water({ landing = { x = 0, y = 1 } }), { "block TestWater: landing.z is nil, not a number" } },
		{ "a landing with an endless x", water({ landing = { x = math.huge, y = 1, z = 0 } }), { "block TestWater: landing.x is ", ", not a number" } },
		{ "a landing with a y that is a word", water({ landing = { x = 0, y = "1", z = 0 } }), { "block TestWater: landing.y is 1, not a number" } },
		{ "a landing that is a word", water({ landing = "Road2" }), { "block TestWater: landing is Road2, not a point" } },
	}
	for _, case in refused do
		local found = lines(case[2])
		check(says(found, table.unpack(case[3])), `{case[1]}: one line ({said(found)})`)
	end
	local both = lines(water({ collide = true, opens = "testHole" }))
	check(#both == 2, `an ice block that collides and opens a shortcut: both lines ({said(both)})`)
	local fireBoth = lines(water({ react = "fire" }))
	check(#fireBoth == 2, `a fire block that does not collide, with a landing: both lines ({said(fireBoth)})`)
end
L1.group("l2w3 validateTests", W3.validateTests)

function W3.landingTests(): ()
	print(" StageFlow: Plan's waters, Landing and FallLanding (L2-58)")
	local Flow = W3.Flow
	local plan: any = {
		waters = {
			{ rect = { x = 0, z = 0, hx = 10, hz = 5 }, landing = vec(0, 0, -30) },
			{ rect = { x = 5, z = 0, hx = 10, hz = 5 }, landing = vec(99, 0, 99) },
			{ rect = { x = 100, z = 100, hx = 2, hz = 2 }, landing = vec(100, 1, 90) },
		},
	}
	local function at(x: number, z: number, margin: number?): any
		return Flow.Landing(plan, vec(x, -20, z), margin or 4)
	end
	local inside = at(0, 0)
	check(inside ~= nil and inside.X == 0 and inside.Z == -30, "a fall inside the footprint: its landing")
	local first = at(6, 0)
	check(first ~= nil and first.X == 0, "two waters hold it: the first in the layout's order")
	local last = at(100, 103.5)
	check(last ~= nil and last.Y == 1 and last.Z == 90, "within the margin outside: its landing")
	check(at(100, 106.01) == nil and at(100, 106) ~= nil, "the margin's edge holds; past it, none")
	check(at(100, 102.5, -3) == nil and at(100, 102, -3) ~= nil, "a margin under 0 counts as 0")
	check(at(100, 102.5, W3.NAN) == nil and at(100, 102.5, math.huge) == nil and at(100, 102, W3.NAN) ~= nil, "a margin that is not finite counts as 0")
	check(Flow.Landing(plan, vec(W3.NAN, -20, 0), 4) == nil and Flow.Landing(plan, vec(0, -20, math.huge), 4) == nil, "a position that is not finite: none")
	check(at(50, 50) == nil, "over no water: none (the safe point)")
	check(Flow.Landing({ waters = {} }, vec(0, -20, 0), 4) == nil, "a plan with no waters: none")
	for _, step in { "fight", "breather" } do
		check(Flow.FallLanding(plan, { step = step }, vec(0, -20, 0), 4) == nil, `FallLanding in a closed camp's {step}: none (its entry, as before)`)
	end
	for _, step in { "travel", "armed", "gate", "over" } do
		local landed = Flow.FallLanding(plan, { step = step }, vec(0, -20, 0), 4)
		check(landed ~= nil and landed.Z == -30, `FallLanding in "{step}": the landing`)
	end

	-- Plan on the fixture layout: the ice block with a landing is a water, nothing else is.
	local level = L1.level()
	local layout = L1.layout()
	local extra = W3.layout()
	for _, block in extra.blocks do
		table.insert(layout.blocks, block)
	end
	local noLanding = L1.copy(extra.blocks[2])
	noLanding.name = "Dry"
	noLanding.landing = nil
	table.insert(layout.blocks, noLanding)
	local fireLanding = L1.copy(extra.blocks[5])
	fireLanding.landing = { x = 1, y = 2, z = 3 }
	table.insert(layout.blocks, fireLanding)
	local made = L1.plan(level, layout, "normal")
	local waters = made ~= nil and made.waters or {}
	check(#waters == 1, `one water: the ice block with a landing (not one without, not a fire block with one) ({#waters})`)
	local one = waters[1]
	if one ~= nil then
		check(one.rect.x == 0 and one.rect.z == 0 and one.rect.hx == 10.5 and one.rect.hz == 7, "its rect is the block's footprint")
		check(one.landing.X == 0 and one.landing.Y == 0 and one.landing.Z == -30, "its landing is the block's")
	end
	local bare = L1.plan(L1.level(), L1.layout(), "normal")
	check(bare ~= nil and bare.waters ~= nil and #bare.waters == 0, "a layout with no water: an empty list")
end
L1.group("l2w3 landingTests", W3.landingTests)

-- The shipped files (economy-designer's data): Forest Road's creek and pond freeze, a crossing
-- frozen swing by swing reaches the island, a fall comes back to the landing, the shrine pays
-- behind ice and the Frost Hammer is found later.
function W3.realTests(): ()
	print(" The real files: the frozen creek, the crossing, the landing, the shrine behind ice")
	local R, Flow = W3.React, W3.Flow
	local file = L1.real.file("forestRoad")
	local layout = file ~= nil and L1.real.layouts[file.layout] or nil
	if file == nil or layout == nil then
		check(false, "Forest Road's file and layout are there")
		return
	end
	local frost = L1.real.rules.react and L1.real.rules.react.ice
	check(type(frost) == "table" and type(frost.reachDown) == "number" and type(frost.ahead) == "number", "Combat.json levels.react.ice has cell, lift, thickness, reachDown and ahead")
	check(L1.real.rules.react.iceHits == nil, "and no iceHits (L2-54)")
	local sizes = L1.real.sizes()
	check(sizes.ice ~= nil, "LevelService builds its cells (sizesOf)")
	if type(frost) ~= "table" or sizes.ice == nil then
		return
	end
	local blocks, ice, island = {}, {}, nil
	for _, block in layout.blocks do
		blocks[block.name or ""] = block
		if block.react == "ice" then
			table.insert(ice, block)
		end
		if block.name == "ShrineIsland" then
			island = block
		end
	end
	check(#ice == 2 and blocks.Creek ~= nil and blocks.Creek.react == "ice" and blocks.Pond ~= nil and blocks.Pond.react == "ice", `the creek and the pond freeze ({#ice} ice blocks)`)
	check(island ~= nil, "the island is there")
	local pieces = L1.real.pieces(layout)
	if pieces == nil or island == nil or #ice == 0 then
		check(false, "the shipped layout builds")
		return
	end
	-- Every cell lies in its water, at the ice's height; none under the bridge or the island.
	local cells, covered, misplaced = {}, {}, {}
	for _, piece in pieces do
		if piece.role ~= "ice" then
			continue
		end
		local name = string.match(piece.name, "^Ice_(.-)_%d+$")
		local water = blocks[name or ""]
		local box = piece.box
		if water == nil or math.abs(box.x - water.x) > water.sx / 2 or math.abs(box.z - water.z) > water.sz / 2 or not near(box.y + box.sy / 2, water.y + water.sy / 2 + frost.lift) then
			table.insert(misplaced, piece.name)
		end
		for _, cover in { blocks.Road2, island } do
			if cover ~= nil and math.abs(box.x - cover.x) <= cover.sx / 2 and math.abs(box.z - cover.z) <= cover.sz / 2 then
				table.insert(covered, piece.name)
			end
		end
		table.insert(cells, { box = box, frozen = false })
	end
	check(#cells > 0 and #misplaced == 0, `{#cells} ice cells, each in its water at the ice's height{L1.real.list(misplaced)}`)
	check(#covered == 0, `none under Road2 or the island{L1.real.list(covered)}`)

	-- The crossing: from Road2's south edge above the creek, swing toward the island, step onto
	-- the frozen cell nearest it, swing again; the ice must reach the island's edge.
	local root = L1.real.ROOT
	local range = FIXTURES.proving.weapons.frostHammer.variants.A.range
	local arc = FIXTURES.proving.weapons.frostHammer.variants.A.arcDegrees
	local goal = vec(island.x, 0, island.z)
	local feet = vec(blocks.Creek.x, blocks.Road2.y + blocks.Road2.sy / 2, blocks.Road2.z + blocks.Road2.sz / 2)
	local swings, reached, firstSwing = 0, false, 0
	local function touchesIsland(box: any): boolean
		return math.abs(box.x - island.x) <= island.sx / 2 + box.sx / 2 + 1e-6 and math.abs(box.z - island.z) <= island.sz / 2 + box.sz / 2 + 1e-6
	end
	for _ = 1, 40 do
		local origin = feet + vec(0, root, 0)
		local way = goal - feet
		local frozen = R.Freeze(cells, "ice", W3.arc(origin, vec(way.X, 0, way.Z), range, arc), frost.reachDown, frost.ahead)
		swings += 1
		if swings == 1 then
			firstSwing = #frozen
		end
		local best, bestDistance = nil, (vec(feet.X, 0, feet.Z) - goal).Magnitude
		for _, cell in cells do
			if cell.frozen then
				local distance = (vec(cell.box.x, 0, cell.box.z) - goal).Magnitude
				if touchesIsland(cell.box) then
					reached = true
				end
				if distance < bestDistance - 1e-6 then
					best, bestDistance = cell, distance
				end
			end
		end
		if reached or best == nil then
			break
		end
		feet = vec(best.box.x, best.box.y + best.box.sy / 2, best.box.z)
	end
	check(firstSwing >= 3, `a swing from the bank freezes a patch ahead ({firstSwing} cells)`)
	check(reached, `swing by swing, the ice reaches the island ({swings} swings)`)
	check(swings >= 5, `and it takes a crossing, not one swing ({swings})`)

	-- A fall through the water comes back to its landing.
	local real = L1.real.resolve("forestRoad")
	local plan = real.level ~= nil and L1.real.plan(real.level, real.layout, "normal", L1.real.bounds(real.layout)) or nil
	if plan == nil then
		check(false, "Forest Road plans")
		return
	end
	local margin = L1.real.rescue.outside
	local pond = blocks.Pond
	local landing = pond.landing
	local back = Flow.Landing(plan, vec(pond.x + pond.sx / 2 - 1, layout.killY - 1, pond.z), margin)
	check(landing ~= nil and back ~= nil and back.X == landing.x and back.Y == landing.y and back.Z == landing.z, "a fall into the pond comes back to its landing")
	local creekFall = Flow.Landing(plan, vec(blocks.Creek.x, layout.killY - 1, blocks.Creek.z), margin)
	check(creekFall ~= nil and blocks.Creek.landing ~= nil and creekFall.Z == blocks.Creek.landing.z, "and one into the creek to the creek's")
	check(Flow.Landing(plan, vec(-447, layout.killY - 1, 0), margin) == nil, "a fall from Road1's gap (the void) goes to the safe point")
	local footing = landing ~= nil and L1.real.footing(pieces, vec(landing.x, landing.y, landing.z)) or nil
	check(footing ~= nil, `the landing stands on a solid top ({footing and footing.name})`)

	-- The shrine pays behind ice; the Frost Hammer is found later.
	local S, U = W3.Secret, W3.Unlocks
	local shrine = nil
	for _, site in S.Sites(layout, file) do
		if site.id == "shrine" then
			shrine = site
		end
	end
	local weapons = FIXTURES.proving.weapons
	local starters = U.Starters(FIXTURES.proving.loadout)
	local config = L1.real.map
	local without = { valor = 0, materials = {}, abilities = { doubleJump = true }, families = { flamethrower = true } }
	local with = { valor = 0, materials = {}, abilities = { doubleJump = true }, families = { flamethrower = true, frostHammer = true } }
	check(shrine ~= nil and shrine.needs == "ice" and shrine.reward ~= nil and shrine.reward.family == nil, "the shrine needs ice and pays, no family")
	if shrine ~= nil then
		check(S.Decide(shrine, U.HoldsKey(without, config, weapons, starters, shrine.needs), false) == "locked", "the shrine: locked with fire alone")
		check(S.Decide(shrine, U.HoldsKey(with, config, weapons, starters, shrine.needs), false) == "pay", "and pays once the Frost Hammer is owned")
	end
	check(not starters.frostHammer and U.ElementOf(weapons, "frostHammer") == "ice", "the Frost Hammer carries ice and is no starter")
	local found = config.found
	local entry = found ~= nil and found.frostHammer or nil
	check(entry ~= nil and type(entry.node) == "string" and type(entry.text) == "string" and #entry.text >= 1 and #entry.text <= 40, "Expeditions.json `found` names the Frost Hammer, its node and a hint of 1 to 40 characters")
	local paid = false
	for _, reward in file.secrets or {} do
		paid = paid or reward.family == "frostHammer"
	end
	check(not paid, "no secret pays it (found later, by the lever until the Castle)")
end
L1.group("l2w3 realTests", W3.realTests)

-- The lines that act on these verdicts (none of their files loads here), read as text by
-- run_harness.py (FIXTURES.source.w3).
function W3.wiringTests(): ()
	print(" The lines that act on Freeze, FallLanding and Frost Quake, read as text")
	local w = FIXTURES.source.w3
	if w == nil then
		check(false, "the source reading has a w3 entry")
		return
	end
	check(w.reactIce == 1 and w.reactFreeze == 1, `LevelService.React sends a strike of ice to freeze, once ({w.reactIce}, {w.reactFreeze})`)
	check(w.freezeFound and w.freezeCall == 1, `freeze hands the cells to WorldReact.Freeze with levels.react.ice's reachDown and ahead ({w.freezeFound}, {w.freezeCall})`)
	check(w.freezeFloor == 3 and w.freezeTold == 1, `each frozen cell collides, is met by rays and says Ice, and the listeners are told ({w.freezeFloor}, {w.freezeTold})`)
	check(w.rescueFound and w.rescueLanding == 1 and w.rescueTarget == 1, `the rescue asks StageFlow.FallLanding with player.rescue's outside and goes there ({w.rescueFound}, {w.rescueLanding}, {w.rescueTarget})`)
	check(w.quakeAlias == 1, `Frost Quake is the Earthquake launcher's entry ({w.quakeAlias})`)
end
L1.group("l2w3 wiringTests", W3.wiringTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
