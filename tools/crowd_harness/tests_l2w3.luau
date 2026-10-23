-- Cases for L2 W3, ice, the frost hammer, deep water and the island shrine
-- (docs/prompts/l2-w3-contract.md): the pure WorldReact's Cells, Chills and Freeze (L2-53, L2-54),
-- LevelGeometry.Pieces' ice pieces, StageFlow.Validate's ice and landing lines (L2-52, L2-58),
-- Plan's waters with Landing and FallLanding (L2-58), the shipped Forest Road (a crossing frozen
-- swing by swing to the island, the shrine behind ice) and the lines that act on these, read as
-- text (LevelService.React's ice branch, the rescue's landing, Frost Quake's launcher). The fix
-- round (docs/prompts/l2-w3-fix-round.md) adds LevelGeometry.SizesOf and Overlap, WorldReact's
-- SwingStrike, IceReach, IceLook, Reactive and ICE_ATTRIBUTE, the whole-cell cover rule, the
-- landing judged by where the body last stood, and the lines that apply all of them. Appended
-- last by run_harness.py, so every local of the earlier files is in scope (vec, check, load, L1,
-- W2). Everything hangs off the W3 table (the 200-local limit) and every group runs behind
-- L1.group. LevelService, WaveService and WeaponService cannot be loaded here: they execute what
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
	-- The second fix round's Q5: an R15 character's root Part (2 x 2 x 1) and HipHeight (2).
	R15 = { size = vec(2, 2, 1), hip = 2 },
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

-- Does `cover`'s footprint hold all of `box`'s (edges included, to 1e-6)?
function W3.holds(cover: any, box: any): boolean
	return math.abs(box.x - cover.x) + box.sx / 2 <= cover.sx / 2 + 1e-6 and math.abs(box.z - cover.z) + box.sz / 2 <= cover.sz / 2 + 1e-6
end

-- The third fix round's fd-s2, the harness's own statement: does the part `low` to `high` of
-- `water`'s `side` face ("west", "east", "north" or "south") lie against another of `waters` over
-- its whole length (that block's opposite side on the same plane, the same top)? Those sides are
-- built whole; every other side on a water's face is inset.
function W3.meetsWhole(waters: { any }, water: any, side: string, low: number, high: number): boolean
	local top = water.y + water.sy / 2
	for _, other in waters do
		if other == water or math.abs(other.y + other.sy / 2 - top) > 1e-6 then
			continue
		end
		local mine, theirs, lo, hi
		if side == "west" or side == "east" then
			mine = if side == "west" then water.x - water.sx / 2 else water.x + water.sx / 2
			theirs = if side == "west" then other.x + other.sx / 2 else other.x - other.sx / 2
			lo, hi = other.z - other.sz / 2, other.z + other.sz / 2
		else
			mine = if side == "north" then water.z - water.sz / 2 else water.z + water.sz / 2
			theirs = if side == "north" then other.z + other.sz / 2 else other.z - other.sz / 2
			lo, hi = other.x - other.sx / 2, other.x + other.sx / 2
		end
		if math.abs(mine - theirs) <= 1e-6 and lo <= low + 1e-6 and hi >= high - 1e-6 then
			return true
		end
	end
	return false
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
-- (top 0), a sunk block under its east column (top -2: below the water's top), a chest (a secret)
-- exactly over the middle of its second row, a fire bramble, Mist (walked through, over the
-- water's top) holding the first row's middle cell whole, and Pool, deep water with no react.
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
			{ name = "Mist", look = "water", x = 0, y = 2, z = -3.5, sx = 7, sy = 2, sz = 7, collide = false },
		},
		secrets = {
			{ id = "chest", needs = "ice", x = 0, y = 1, z = 3.5, sx = 7, sy = 2, sz = 7, sign = { x = 0, y = 0, z = -20, text = "" } },
		},
		route = {},
	}
end

-- The names of the ice pieces Pieces builds of `layout` (nil when it refuses).
function W3.iceNames(layout: any, sizes: any): any
	local pieces = W3.Geo.Pieces(layout, sizes, 600)
	if pieces == nil then
		return nil
	end
	local names = {}
	for _, piece in pieces do
		if piece.role == "ice" then
			names[piece.name] = true
		end
	end
	return names
end

function W3.piecesTests(): ()
	print(" LevelGeometry.Pieces: an ice block's cells (L2-53; the fix round's d-m1: a whole cell covered)")
	local Geo = W3.Geo
	local sizes = { fence = 1, floor = 4, ice = { cell = 7, lift = 0.2, thickness = 1, inset = 0 } }
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
	-- 3 x 2 cells: column 1 under the bridge (top 0 > -1, exactly its footprint), column 3 over the
	-- sunk block (top -2), row 2's middle cell exactly under the chest (top 2).
	check(#ice == 3, `six cells, three covered: three pieces ({#ice})`)
	check(byName.Ice_Water_1 == nil and byName.Ice_Water_4 == nil, "no cell under the bridge (a colliding block over the water's top, holding each cell whole, its edges included)")
	check(byName.Ice_Water_3 ~= nil and byName.Ice_Water_6 ~= nil, "a block below the water's top covers nothing")
	check(byName.Ice_Water_5 == nil and byName.Ice_Water_2 ~= nil, "a secret over the water's top that holds a whole cell covers it")
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

	-- d-m1: a cover that holds a cell's centre but not all of it leaves the cell built (a slit of
	-- water no swing could close otherwise); a cover exactly the cell's footprint, or short of it by
	-- less than a seam, covers it; one short by a thousandth of a stud does not.
	local function bridged(x: number, sx: number): any
		local layout = W3.layout()
		layout.blocks[3].x = x
		layout.blocks[3].sx = sx
		return W3.iceNames(layout, sizes) or {}
	end
	local strip = bridged(-7.25, 0.5)
	check(strip.Ice_Water_1 and strip.Ice_Water_4, "a cover holding only the cell's centre covers nothing: the cell is built")
	local exact = bridged(-7, 7)
	check(not exact.Ice_Water_1 and not exact.Ice_Water_4, "a cover exactly the cell's footprint covers it (its edges included)")
	local seam = bridged(-7 + 5e-8, 7 - 1e-7)
	check(not seam.Ice_Water_1, "a cover short of the cell by less than a seam (1e-6) covers it")
	local short = bridged(-7 + 0.0005, 7 - 0.001)
	check(short.Ice_Water_1 and short.Ice_Water_4, "a cover a thousandth of a stud short of the cell's west edge covers nothing")
	local wide = bridged(-7, 9)
	check(not wide.Ice_Water_1 and not wide.Ice_Water_4 and wide.Ice_Water_2, "a cover wider than the cell covers it, and not the next cell it only reaches into")
	local shallow = W3.layout()
	shallow.secrets[1].sz = 6.99
	local shallowNames = W3.iceNames(shallow, sizes) or {}
	check(shallowNames.Ice_Water_5, "a cover that holds the cell across X but not along Z covers nothing (Z judged whole too)")

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
	local tiny, said = Geo.Pieces(W3.layout(), { fence = 1, floor = 4, ice = { cell = 0.001, lift = 0.2, thickness = 1, inset = 0 } }, 600)
	check(tiny == nil and said ~= nil and string.find(said, "Water", 1, true) ~= nil and string.find(said, "maxParts", 1, true) ~= nil, `a cell far under the water's size is refused before a cell is made, by name ({tostring(said)})`)
end
L1.group("l2w3 piecesTests", W3.piecesTests)

-- The fix round's s-m1: the sizes a level is built with, LevelGeometry.SizesOf (LevelService asks
-- it and warns on its second answer).
function W3.sizesTests(): ()
	print(" LevelGeometry.SizesOf: the sizes a level is built with (the fix round's s-m1)")
	local Geo = W3.Geo
	local expeditions = { sign = { size = { 6, 2, 0.5 } } }
	local function rules(ice: any): any
		return { fenceThickness = 1, floorThickness = 4, checkpointSize = { 2, 6, 2 }, fireMarkerSize = { 3, 1, 3 }, react = { fireHits = 6, pad = 0.5, ice = ice } }
	end
	local sizes, refused = Geo.SizesOf(expeditions, rules({ cell = 7, lift = 0.2, thickness = 4, reachDown = 6, ahead = 4 }))
	local ice = sizes.ice
	check(ice ~= nil and ice.cell == 7 and ice.lift == 0.2 and ice.thickness == 4 and refused == false, "levels.react.ice: its cell, lift and thickness; nothing refused")
	check(sizes.fence == 1 and sizes.floor == 4 and sizes.checkpoint ~= nil and sizes.checkpoint.sy == 6 and sizes.fire ~= nil and sizes.fire.sx == 3 and sizes.sign ~= nil and sizes.sign.sz == 0.5, "the fence, the floor, the markers and the sign, from the config")
	local zeroLift = Geo.SizesOf(expeditions, rules({ cell = 7, lift = 0, thickness = 1 }))
	local belowLift = Geo.SizesOf(expeditions, rules({ cell = 7, lift = -0.5, thickness = 1 }))
	check(zeroLift.ice ~= nil and zeroLift.ice.lift == 0 and belowLift.ice ~= nil and belowLift.ice.lift == -0.5, "a lift of 0 or under 0 (finite) is a lift")
	local bad = {
		{ "a cell of 0", { cell = 0, lift = 0.2, thickness = 1 } },
		{ "an endless cell", { cell = math.huge, lift = 0.2, thickness = 1 } },
		{ "no thickness", { cell = 7, lift = 0.2 } },
		{ "a thickness under 0", { cell = 7, lift = 0.2, thickness = -1 } },
		{ "a NaN lift", { cell = 7, lift = W3.NAN, thickness = 1 } },
		{ "an endless lift", { cell = 7, lift = math.huge, thickness = 1 } },
		{ "a lift that is a word", { cell = 7, lift = "0.2", thickness = 1 } },
		{ "ice that is a word", "ice" },
	}
	for _, case in bad do
		local got, said = Geo.SizesOf(expeditions, rules(case[2]))
		check(got.ice == nil and said == true, `{case[1]}: no cells, and refused (LevelService says so once)`)
	end
	local absent, quiet = Geo.SizesOf(expeditions, rules(nil))
	check(absent.ice == nil and quiet == false, "no levels.react.ice: no cells, nothing refused")
	local noReact, still = Geo.SizesOf(expeditions, { floorThickness = 4 })
	check(noReact.ice == nil and still == false and noReact.fence == 0 and noReact.floor == 4 and noReact.checkpoint == nil, "no react: no cells; no fenceThickness: 0; no checkpointSize: none")
	local bare, said = Geo.SizesOf(nil, nil)
	check(bare.fence == 0 and bare.floor == nil and bare.sign == nil and bare.ice == nil and said == false, "no config at all: nothing sized, nothing refused")
	local words = Geo.SizesOf({ sign = { size = { 6, "2", 0.5 } } }, { floorThickness = W3.NAN, checkpointSize = { 2, 0, 2 } })
	check(words.sign == nil and words.floor == nil and words.checkpoint == nil, "a size with a word, a NaN or a 0 in it: none")
	check(Geo.Length(4) == 4 and Geo.Length(0) == nil and Geo.Length(-1) == nil and Geo.Length(W3.NAN) == nil and Geo.Length(math.huge) == nil and Geo.Length("4") == nil, "Length: a positive finite number, else none")
	local real = Geo.SizesOf(L1.real.map, L1.real.rules)
	local frost = L1.real.rules.react ~= nil and L1.real.rules.react.ice or nil
	check(real.ice ~= nil and frost ~= nil and real.ice.cell == frost.cell and real.ice.lift == frost.lift and real.ice.thickness == frost.thickness, "the shipped Combat.json: its ice sizes as written")
end
L1.group("l2w3 sizesTests", W3.sizesTests)

-- The fix round's c-m3, d-m5, s-m1 and s-s3: the pure answers the server and the client share.
function W3.sharedTests(): ()
	print(" WorldReact: SwingStrike, IceReach, IceLook, Reactive, ICE_ATTRIBUTE (the fix round)")
	local R = W3.React
	check(R.ICE_ATTRIBUTE == "Ice", `the ice cell attribute is "Ice" ({tostring(R.ICE_ATTRIBUTE)})`)
	-- SwingStrike (c-m3).
	local variant = { label = "Test", kind = "melee", shape = "arc", range = 9, arcDegrees = 120, pad = 1.5, width = 2, cap = 8, damage = 38, rate = 1.5, knockback = 22, launch = 6, chain = { 1, 1, 1.8 }, finisherArcDegrees = 360 }
	local origin, heading = vec(1, 3, 2), vec(0, 0, -1)
	for step = 1, 3 do
		local strike = R.SwingStrike(variant, step, origin, heading)
		local arc = if step == 3 then 360 else 120
		check(strike.shape == "arc" and L1.same(strike.origin, origin) and L1.same(strike.direction, heading) and strike.size == 9 and strike.width == 2 and strike.arcDegrees == arc, `step {step}: an arc at the origin along the heading, size = range (not range + pad), width, {arc} degrees`)
	end
	local plain = table.clone(variant)
	plain.finisherArcDegrees = nil
	check(R.SwingStrike(plain, 3, origin, heading).arcDegrees == 120, "no finisherArcDegrees: the chain's last step sweeps the arc too")
	local single = table.clone(variant)
	single.chain = nil
	check(R.SwingStrike(single, 1, origin, heading).arcDegrees == 120, "no chain: never the finisher (step 1 is not the last of none)")
	local empty = table.clone(variant)
	empty.chain = {}
	check(R.SwingStrike(empty, 1, origin, heading).arcDegrees == 120, "an empty chain: never the finisher")
	local spear = { label = "Test", kind = "melee", shape = "capsule", range = 12, width = 3, pad = 1, cap = 4, damage = 30, rate = 1, knockback = 10, launch = 2 }
	local thrust = R.SwingStrike(spear, 1, origin, heading)
	check(thrust.shape == "capsule" and thrust.size == 12 and thrust.width == 3 and thrust.arcDegrees == nil, "a capsule swing: its shape, range and width, no arc")
	local hammer = FIXTURES.proving.weapons.frostHammer.variants.A
	local frost = R.SwingStrike(hammer, 1, origin, heading)
	check(frost.shape == "arc" and frost.size == hammer.range and frost.arcDegrees == hammer.arcDegrees, "the shipped Frost Hammer's first swing: its range and its arc")
	local spin = FIXTURES.proving.weapons.spinblade
	local spinA = spin ~= nil and spin.variants.A or nil
	if spinA ~= nil and spinA.finisherArcDegrees ~= nil and spinA.chain ~= nil then
		check(R.SwingStrike(spinA, #spinA.chain, origin, heading).arcDegrees == spinA.finisherArcDegrees and R.SwingStrike(spinA, 1, origin, heading).arcDegrees == spinA.arcDegrees, "the shipped Spinblade: its finisher's spin on the last step only")
	end
	-- IceReach (d-m5).
	local reachDown, ahead = R.IceReach({ cell = 7, lift = 0.2, thickness = 4, reachDown = 6, ahead = 4 })
	check(reachDown == 6 and ahead == 4, `reachDown then ahead, read from their own keys ({tostring(reachDown)}, {tostring(ahead)})`)
	local onlyDown, noAhead = R.IceReach({ reachDown = 6, lift = 0.2 })
	check(onlyDown == 6 and noAhead == nil, "no ahead: none (not lift or another key)")
	local wordDown, stillAhead = R.IceReach({ reachDown = "6", ahead = 4 })
	check(wordDown == nil and stillAhead == 4, "a reachDown that is a word: none")
	local a, b = R.IceReach(nil)
	local c, d = R.IceReach("ice")
	check(a == nil and b == nil and c == nil and d == nil, "no table: none")
	local shipped = L1.real.rules.react ~= nil and L1.real.rules.react.ice or nil
	local realDown, realAhead = R.IceReach(shipped)
	check(shipped ~= nil and realDown == shipped.reachDown and realAhead == shipped.ahead, "the shipped Combat.json: its reachDown and ahead")
	-- IceLook (s-m1).
	local water = R.IceLook(false, 0.3)
	check(water.transparency == 1 and water.collide == false and water.shadow == false and water.frozen == false, "water: hidden, met by nothing, no shadow, Ice false")
	local floor = R.IceLook(true, 0.3)
	check(floor.transparency == 0.3 and floor.collide == true and floor.shadow == true and floor.frozen == true, "frozen: its look's transparency, met by bodies, rays and the camera, a shadow, Ice true")
	check(R.IceLook(true, 0).transparency == 0, "an opaque look stays opaque once frozen")
	-- Reactive (s-m1).
	check(R.Reactive("fire") and not R.Reactive("ice") and not R.Reactive(nil), "fire is reactive; ice (water whose cells freeze) and no react are not")
	check(R.Reactive("lava"), "another word is listed as before (Validate refuses it; Need gives it no count)")
end
L1.group("l2w3 sharedTests", W3.sharedTests)

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

-- The fix round's s-s2: two footprints overlap over an area, never by touching.
function W3.overlapTests(): ()
	print(" LevelGeometry.Overlap: footprints that touch do not overlap (the fix round's s-s2)")
	local Geo = W3.Geo
	local a = { x = 0, y = 0, z = 0, sx = 10, sy = 1, sz = 10 }
	local function box(x: number, z: number, sx: number?, sz: number?): any
		return { x = x, y = 5, z = z, sx = sx or 10, sy = 1, sz = sz or 10 }
	end
	check(not Geo.Overlap(a, box(10, 0)) and not Geo.Overlap(a, box(0, -10)), "touching along an edge: no")
	check(not Geo.Overlap(a, box(10, 10)), "touching at a corner: no")
	check(Geo.Overlap(a, box(9.99, 0)) and Geo.Overlap(box(9.99, 0), a), "a hundredth of a stud over: yes, either way round")
	check(not Geo.Overlap(a, box(10 - 1e-7, 0)), "less than a seam over: no (rounding)")
	check(Geo.Overlap(a, box(0, 0, 2, 2)) and Geo.Overlap(a, box(3, 4)), "one inside the other, or crossing: yes")
	check(not Geo.Overlap(a, box(4, 10.5)) and not Geo.Overlap(a, box(11, 4)), "apart on one axis: no")
	check(Geo.Overlap(a, { x = 4, y = -50, z = 4, sx = 4, sy = 1, sz = 4 }), "heights are not judged (a footprint is in plan)")
end
L1.group("l2w3 overlapTests", W3.overlapTests)

-- Validate's lines on a copy of Forest Road with one test block of its own at the end: every line
-- that names it.
function W3.validateTests(): ()
	print(" StageFlow.Validate: ice, landing and overlap lines (L2-52, L2-58; the fix round's Q3, s-s2)")
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
		{ "deep water with no react and a landing (the fix round's Q3: CreekUp)", water({ react = W3.NONE }) },
		{ "an ice block with collide false written", water({ collide = false }) },
	}
	for _, case in accepted do
		local found = lines(case[2])
		check(#found == 0, `{case[1]}: accepted ({said(found)})`)
	end
	local refused = {
		{ "an ice block that collides (collide left out)", water({ collide = W3.NONE, landing = W3.NONE }), { "block TestWater is ice and collides" } },
		{ "an ice block with collide true", water({ collide = true, landing = W3.NONE }), { "block TestWater is ice and collides" } },
		{ "an ice block that opens a shortcut", water({ opens = "testHole" }), { "block TestWater is ice and opens testHole" } },
		{ "a fire block with a landing", water({ react = "fire", collide = true }), { "block TestWater has a landing and collides" } },
		{ "a plain block that collides, with a landing", water({ react = W3.NONE, collide = W3.NONE }), { "block TestWater has a landing and collides" } },
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
	local both = lines(water({ collide = true, opens = "testHole", landing = W3.NONE }))
	check(#both == 2, `an ice block that collides and opens a shortcut: both lines ({said(both)})`)
	local landed = lines(water({ collide = true }))
	check(#landed == 2, `an ice block that collides, with a landing: both lines ({said(landed)})`)
	local fireLanding = lines(water({ react = "fire" }))
	check(says(fireLanding, "block TestWater reacts and does not collide"), `a fire block that does not collide, with a landing: one line, the landing is a deep block's ({said(fireLanding)})`)

	-- s-s2: a second ice block beside the test water. Overlapping by a stud: one line naming both;
	-- touching along an edge or at a corner, or deep water with no react overlapping: none.
	local function beside(x: number, z: number, react: string?): { string }
		return lines(water(), function(copyLayout: any)
			table.insert(copyLayout.blocks, { name = "TestWater2", look = "water", x = x, y = 400, z = z, sx = 14, sy = 2, sz = 14, collide = false, react = react })
		end)
	end
	check(says(beside(13, 20, "ice"), "block TestWater and block TestWater2 are ice and overlap"), `two ice blocks overlapping by a stud: one line ({said(beside(13, 20, "ice"))})`)
	check(says(beside(0, 20, "ice"), "are ice and overlap"), "two ice blocks on one footprint: one line")
	check(#beside(14, 20, "ice") == 0 and #beside(0, 34, "ice") == 0, "two ice blocks touching along an edge (the creek into the pond): accepted")
	check(#beside(14, 34, "ice") == 0, "touching at a corner: accepted")
	check(#beside(13, 20, nil) == 0, "deep water with no react overlapping an ice block: accepted (only ice builds a frozen top)")
end
L1.group("l2w3 validateTests", W3.validateTests)

function W3.landingTests(): ()
	print(" StageFlow: Plan's waters, Landing and FallLanding (L2-58; the fix round's s-M1: where the body stood)")
	local Flow = W3.Flow
	local plan: any = {
		waters = {
			{ rect = { x = 0, z = 0, hx = 10, hz = 5 }, landing = vec(0, 0, -30) },
			{ rect = { x = 5, z = 0, hx = 10, hz = 5 }, landing = vec(99, 0, 99) },
			{ rect = { x = 100, z = 100, hx = 2, hz = 2 }, landing = vec(100, 1, 90) },
		},
	}
	local function at(x: number, z: number, margin: number?): any
		return Flow.Landing(plan, vec(x, -20, z), nil, margin or 4)
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
	check(Flow.Landing(plan, vec(W3.NAN, -20, 0), nil, 4) == nil and Flow.Landing(plan, vec(0, -20, math.huge), nil, 4) == nil, "a position that is not finite: none")
	check(at(50, 50) == nil, "over no water: none (the safe point)")
	check(Flow.Landing({ waters = {} }, vec(0, -20, 0), vec(0, 3, 0), 4) == nil, "a plan with no waters: none")

	-- s-M1: judged by where the body last stood, then by where it is.
	local function from(stood: any, x: number, z: number): any
		return Flow.Landing(plan, vec(x, -20, z), stood, 4)
	end
	local onIce = vec(100, 3, 101.5)
	local walked = from(onIce, 100, 101.5 + 9)
	check(walked ~= nil and walked.Z == 90 and from(nil, 100, 101.5 + 9) == nil, "a walk-off 9 studs past the edge: the landing of the water it stood on (by its position alone: none)")
	local dashed = from(onIce, 129, 101.5)
	check(dashed ~= nil and dashed.Z == 90, "a dash-off 29 studs out: that landing")
	local bank = from(vec(103.5, 3, 100), 130, 100)
	check(bank ~= nil and bank.Z == 90, "a dash off the bank (within the margin of the water): that landing")
	check(from(vec(106.5, 3, 100), 130, 100) == nil, "off ground further from the water than the margin, falling far from it: none")
	check(from(vec(50, 3, 50), 50, 60) == nil, "a fall far from any water: none (the safe point)")
	local stoodFirst = from(onIce, 0, 0)
	check(stoodFirst ~= nil and stoodFirst.Z == 90, "it stood by one water and fell into another: where it stood decides")
	local byPosition = from(vec(50, 3, 50), 0, 0)
	check(byPosition ~= nil and byPosition.Z == -30, "it stood far from any water and fell into one: that water's")
	local nanStood = from(vec(W3.NAN, 3, 0), 0, 0)
	check(nanStood ~= nil and nanStood.Z == -30 and from(vec(0, 3, math.huge), 50, 50) == nil, "a stood point that is not finite: judged by the position alone")
	check(Flow.Landing(plan, vec(W3.NAN, -20, 0), onIce, 4) ~= nil, "a position that is not finite, from where it stood: that landing")

	for _, step in { "fight", "breather" } do
		check(Flow.FallLanding(plan, { step = step }, vec(0, -20, 0), onIce, 4) == nil, `FallLanding in a closed camp's {step}: none, wherever it stood (its entry, as before)`)
	end
	for _, step in { "travel", "armed", "gate", "over" } do
		local landed = Flow.FallLanding(plan, { step = step }, vec(0, -20, 0), nil, 4)
		check(landed ~= nil and landed.Z == -30, `FallLanding in "{step}": the landing`)
	end
	local stoodLanding = Flow.FallLanding(plan, { step = "travel" }, vec(50, -20, 60), onIce, 4)
	check(stoodLanding ~= nil and stoodLanding.Z == 90, "FallLanding hands where it stood through")

	-- Plan on the fixture layout: every block a body falls through with a landing is a water.
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
	local deep = L1.copy(extra.blocks[6])
	deep.name = "DeepLanding"
	deep.landing = { x = 40, y = 0, z = -30 }
	table.insert(layout.blocks, deep)
	local made = L1.plan(level, layout, "normal")
	local waters = made ~= nil and made.waters or {}
	check(#waters == 2, `two waters: the ice block and the deep block with a landing (not one without, not a fire block with one) ({#waters})`)
	local one, two = waters[1], waters[2]
	if one ~= nil then
		check(one.rect.x == 0 and one.rect.z == 0 and one.rect.hx == 10.5 and one.rect.hz == 7, "its rect is the block's footprint")
		check(one.landing.X == 0 and one.landing.Y == 0 and one.landing.Z == -30, "its landing is the block's")
	end
	check(two ~= nil and two.rect.x == 40 and two.landing.X == 40, "deep water with no react and a landing is a water too (the fix round's Q3), in the layout's order")
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
	check(sizes.ice ~= nil, "the level is built with its cells (LevelGeometry.SizesOf, as LevelService asks it)")
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
	-- Every cell lies in its water, at the ice's height; none wholly under the bridge or the island
	-- (the fix round's d-m1: a cell they hold in part is built).
	local cells, covered, misplaced, byBlock = {}, {}, {}, {}
	for _, piece in pieces do
		if piece.role ~= "ice" then
			continue
		end
		local name = string.match(piece.name, "^Ice_(.-)_%d+$")
		local water = blocks[name or ""]
		local box = piece.box
		if water == nil or math.abs(box.x - water.x) > water.sx / 2 or math.abs(box.z - water.z) > water.sz / 2 or not near(box.y + box.sy / 2, water.y + water.sy / 2 + frost.lift) or not near(box.sy, frost.thickness) then
			table.insert(misplaced, piece.name)
		end
		for _, cover in { blocks.Road2, island } do
			if cover ~= nil and W3.holds(cover, box) then
				table.insert(covered, piece.name)
			end
		end
		table.insert(cells, { box = box, frozen = false })
		if name ~= nil then
			byBlock[name] = byBlock[name] or {}
			table.insert(byBlock[name], box)
		end
	end
	check(#cells > 0 and #misplaced == 0, `{#cells} ice cells, each in its water at the ice's height and thickness{L1.real.list(misplaced)}`)
	check(#covered == 0, `none wholly under Road2 or the island{L1.real.list(covered)}`)

	-- d-m1: the ice pieces and the covers (colliding blocks and secrets over the water's top) fill
	-- each ice block's footprint: sampled every half stud, no point of open water is left that no
	-- swing could freeze.
	local covers = {}
	for _, block in layout.blocks do
		if block.collide ~= false then
			table.insert(covers, block)
		end
	end
	for _, secret in layout.secrets or {} do
		table.insert(covers, secret)
	end
	for _, water in ice do
		local top = water.y + water.sy / 2
		local own = byBlock[water.name] or {}
		local over: { any } = {}
		for _, cover in covers do
			if cover.y + cover.sy / 2 > top and W3.Geo.Overlap(cover, water) then
				table.insert(over, cover)
			end
		end
		local holes, first = 0, nil
		local x0, z0 = water.x - water.sx / 2, water.z - water.sz / 2
		for i = 0, math.floor(water.sx / 0.5) - 1 do
			for j = 0, math.floor(water.sz / 0.5) - 1 do
				local x, z = x0 + 0.25 + i * 0.5, z0 + 0.25 + j * 0.5
				local filled = false
				for _, box in own do
					if math.abs(x - box.x) <= box.sx / 2 and math.abs(z - box.z) <= box.sz / 2 then
						filled = true
						break
					end
				end
				if not filled then
					for _, cover in over do
						if math.abs(x - cover.x) <= cover.sx / 2 and math.abs(z - cover.z) <= cover.sz / 2 then
							filled = true
							break
						end
					end
				end
				if not filled then
					holes += 1
					first = first or `({x}, {z})`
				end
			end
		end
		check(holes == 0, `{water.name}: its cells and covers fill it ({holes} open points{if first ~= nil then ", the first at " .. first else ""})`)
	end
	-- The second fix round's Q6: no cell's side lies on its water's own face (the frozen side and
	-- the water's shared a plane and shimmered); every side within a stud of that face lies exactly
	-- the shipped inset inside it, and every other side is a cell's or a cover's. The third fix
	-- round's fd-s2: but a side another ice block meets whole (the creek's mouth into the pond) lies
	-- on the face, so the sheets meet with no seam.
	local inset = frost.inset
	check(type(inset) == "number" and inset > 0 and inset < 1, `Combat.json levels.react.ice has an inset under a stud ({tostring(inset)})`)
	local onFace, inner, met = {}, 0, 0
	local names = { "west", "east", "north", "south" }
	for _, water in ice do
		local faces = { water.x - water.sx / 2, water.x + water.sx / 2, water.z - water.sz / 2, water.z + water.sz / 2 }
		for _, box in byBlock[water.name] or {} do
			local sides = { box.x - box.sx / 2, box.x + box.sx / 2, box.z - box.sz / 2, box.z + box.sz / 2 }
			for side = 1, 4 do
				local away = math.abs(sides[side] - faces[side])
				if away < 1 then
					inner += 1
					-- The side's span along the face, as built (a corner the other face insets is a
					-- hair shorter than the cell's place; nothing shipped meets a span that close).
					local low, high = if side <= 2 then sides[3] else sides[1], if side <= 2 then sides[4] else sides[2]
					local whole = W3.meetsWhole(ice, water, names[side], low, high)
					local want = if whole then 0 else (inset or 0)
					met += if whole then 1 else 0
					if math.abs(away - want) > 1e-9 then
						table.insert(onFace, `{water.name} ({box.x}, {box.z}) {names[side]} {away} (wanted {want})`)
					end
				end
			end
		end
	end
	check(inner > 0 and #onFace == 0, `{inner} cell sides by their water's faces, each the inset inside it but where another ice block meets it whole ({met}){L1.real.list(onFace)}`)
	check(met == 6, `the creek's mouth into the pond: its 3 last cells' south sides and the pond's 3 cells under it meet with no seam ({met} sides)`)

	-- The crossing: from Road2's south edge above the creek, swing toward the island, step onto
	-- the frozen cell nearest it, swing again; the ice must reach the island's edge.
	local root = L1.real.ROOT
	local hammer = FIXTURES.proving.weapons.frostHammer.variants.A
	local goal = vec(island.x, 0, island.z)
	local feet = vec(blocks.Creek.x, blocks.Road2.y + blocks.Road2.sy / 2, blocks.Road2.z + blocks.Road2.sz / 2)
	local swings, reached, firstSwing = 0, false, 0
	local function touchesIsland(box: any): boolean
		return math.abs(box.x - island.x) <= island.sx / 2 + box.sx / 2 + 1e-6 and math.abs(box.z - island.z) <= island.sz / 2 + box.sz / 2 + 1e-6
	end
	local reachDown, ahead = R.IceReach(frost)
	-- The second fix round's Q5: the walker's own body goes to Freeze with the shipped sink, as
	-- LevelService hands it every body; on the bank or on the ice it holds no cell it swings at.
	local sink = R.IceSink(frost)
	check(sink ~= nil, `Combat.json levels.react.ice has a sink ({tostring(frost.sink)})`)
	local bodies = {}
	for _ = 1, 40 do
		local origin = feet + vec(0, root, 0)
		local way = goal - feet
		bodies[1] = R.BodyBox(origin, vec(-way.Z, 0, way.X), W3.R15.size, W3.R15.hip)
		-- The swing the server builds (WorldReact.SwingStrike), its first step, on the ground.
		local frozen = R.Freeze(cells, "ice", R.SwingStrike(hammer, 1, origin, vec(way.X, 0, way.Z), false), reachDown, ahead, bodies, sink)
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
	local below = layout.killY - 1
	local function same(point: any, landing: any): boolean
		return point ~= nil and landing ~= nil and point.X == landing.x and point.Y == landing.y and point.Z == landing.z
	end
	local pond, creek, up = blocks.Pond, blocks.Creek, blocks.CreekUp
	check(same(Flow.Landing(plan, vec(pond.x + pond.sx / 2 - 1, below, pond.z), nil, margin), pond.landing), "a fall into the pond comes back to its landing")
	check(same(Flow.Landing(plan, vec(creek.x, below, creek.z), nil, margin), creek.landing), "and one into the creek to the creek's")
	check(up ~= nil and up.landing ~= nil and same(Flow.Landing(plan, vec(up.x, below, up.z - up.sz / 2 + 4), nil, margin), up.landing), "and one into CreekUp, under the bridge, to Road2 by the creek (the fix round's Q3)")
	check(Flow.Landing(plan, vec(-447, below, 0), nil, margin) == nil and Flow.Landing(plan, vec(-447, below, 12), vec(-436.5, 3, 0), margin) == nil, "a fall from Road1's gap (the void) goes to the safe point, wherever on Road1 it stood")
	-- s-M1 on the shipped creek: off the frozen creek's east side at walking and at dashing speed.
	local iceTop = creek.y + creek.sy / 2 + frost.lift
	local onIce = vec(creek.x + creek.sx / 2 - 0.5, iceTop + root, 50)
	check(Flow.Landing(plan, vec(creek.x + creek.sx / 2 + 9, below, 50), nil, margin) == nil, `a walk-off 9 studs past the creek's side is outside its margin ({margin}) by its position alone`)
	check(same(Flow.Landing(plan, vec(creek.x + creek.sx / 2 + 9, below, 50), onIce, margin), creek.landing), "so where it stood on the ice brings it back to the creek's landing")
	check(same(Flow.Landing(plan, vec(creek.x + creek.sx / 2 + 29, below, 50), onIce, margin), creek.landing), "and a dash-off 29 studs out too")
	local bridge = vec(up.x, blocks.Road2.y + blocks.Road2.sy / 2 + root, blocks.Road2.z - blocks.Road2.sz / 2 + 0.5)
	check(same(Flow.Landing(plan, vec(up.x, below, bridge.Z - 29), bridge, margin), up.landing), "a dash off the bridge, north over CreekUp and past it: CreekUp's landing")
	local farRoad = vec(blocks.Road2.x + blocks.Road2.sx / 2 - 3, blocks.Road2.y + blocks.Road2.sy / 2 + root, 7)
	check(Flow.Landing(plan, vec(farRoad.X, below, 16), farRoad, margin) == nil, "a walk-off Road2's far end, by no water: the safe point")
	local footing = pond.landing ~= nil and L1.real.footing(pieces, vec(pond.landing.x, pond.landing.y, pond.landing.z)) or nil
	check(footing ~= nil, `the landing stands on a solid top ({footing and footing.name})`)

	-- The shrine pays behind ice; the Frost Hammer is found later.
	local S, U = W3.Secret, W3.Unlocks
	local shrine = nil
	for _, site in L1.Map.Sites(layout, file) do
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
-- run_harness.py (FIXTURES.source.w3 and .w3fix).
function W3.wiringTests(): ()
	print(" The lines that act on Freeze, FallLanding and Frost Quake, read as text")
	local w = FIXTURES.source.w3
	if w == nil then
		check(false, "the source reading has a w3 entry")
		return
	end
	check(w.reactIce == 1 and w.reactFreeze == 1, `LevelService.React sends a strike of ice to freeze, once ({w.reactIce}, {w.reactFreeze})`)
	check(w.freezeFound and w.freezeCall == 1 and w.freezeReach == 1, `freeze reads reachDown and ahead with WorldReact.IceReach and hands them to WorldReact.Freeze in that order ({w.freezeFound}, {w.freezeCall}, {w.freezeReach})`)
	check(w.freezeShow == 1 and w.freezeTold == 1, `each frozen cell shows as IceLook's floor, and the listeners are told ({w.freezeShow}, {w.freezeTold})`)
	check(w.rescueFound and w.rescueStood == 1 and w.rescueLanding == 1 and w.rescueTarget == 1, `the rescue asks StageFlow.FallLanding with where the body stood and player.rescue's outside, and goes there ({w.rescueFound}, {w.rescueStood}, {w.rescueLanding}, {w.rescueTarget})`)
	check(w.quakeAlias == 1, `Frost Quake is the Earthquake launcher's entry ({w.quakeAlias})`)

	print(" The fix round's lines that apply WorldReact's and LevelGeometry's answers, read as text")
	local f = FIXTURES.source.w3fix
	if f == nil then
		check(false, "the source reading has a w3fix entry")
		return
	end
	check(f.reactCounted == 0 and f.reactFound, `React counts nothing before it knows the element, so no guard can stop the ice (s-m1) ({f.reactCounted})`)
	check(f.showFound and f.showLines == 1 and f.showLinesMost == 1, `showIce sets the transparency, CanCollide, CanQuery, the shadow and the Ice attribute from IceLook, once each ({f.showLines}, {f.showLinesMost})`)
	check(f.showCalls == 2 and f.constructWater == 1 and f.freezeShow == 1, `showIce is called as built (water) and on a freeze (floor), and nowhere else ({f.showCalls}, {f.constructWater}, {f.freezeShow})`)
	check(f.attributeOwn == 0, `LevelService names no ice attribute of its own: WorldReact.ICE_ATTRIBUTE (s-s3) ({f.attributeOwn})`)
	check(f.constructReactive == 1, `a block is listed as reactive by WorldReact.Reactive ({f.constructReactive})`)
	check(f.constructGripAsk == 1 and f.constructGrip == 1 and f.gripLook == 1 and f.gripReturn == 1 and f.gripConst == 1, `a frozen cell grips like the ground look's material, not the Ice material (Q2) ({f.constructGripAsk}, {f.constructGrip}, {f.gripLook}, {f.gripReturn}, {f.gripConst})`)
	check(f.sizesCall == 1 and f.sizesReturn == 1 and f.sizesUsed == 2, `LevelService builds the lobby and the level with LevelGeometry.SizesOf's sizes ({f.sizesCall}, {f.sizesReturn}, {f.sizesUsed})`)
	check(f.trackStood == 1 and f.forgetStood == 1 and f.resetStood == 1 and f.lastGround == 1, `WeaponService records where a body stood on its footprint floor, forgets it on a server move and a fresh body, and answers it (s-M1) ({f.trackStood}, {f.forgetStood}, {f.resetStood}, {f.lastGround})`)
	check(f.meleeSwing == 1 and f.meleeFx == 1 and f.meleeFxMost == 1, `resolveMelee's strike is WorldReact.SwingStrike's, sent to finish() as built (c-m3) ({f.meleeSwing}, {f.meleeFx}, {f.meleeFxMost})`)
	-- c-m3's client half: the three client copies.
	local said = {
		frost = "FrostFx.OnSwing: the frost ghost and puff",
		phone = "InputController.autoIceStrike: the phone's auto-swing at water (only its arc cut to iceAutoDegrees)",
		hitbox = "FeedbackController.PredictSwing: the early hitbox effect",
	}
	for name, label in said do
		local c = f.client ~= nil and f.client[name] or nil
		check(c ~= nil and c.found and c.call == 1 and c.calls == 1 and c.uses >= 1, `{label} builds its strike with WorldReact.SwingStrike, the file's only one, and hands it on as built ({c and c.found}, {c and c.call}, {c and c.calls}, {c and c.uses})`)
	end
end
L1.group("l2w3 wiringTests", W3.wiringTests)

-- The second fix round (docs/prompts/l2-w3-fix2.md), Q5: a swing in the air freezes nothing, and no
-- cell freezes while a player's body stands in it (WorldReact.SwingStrike's `airborne`, Chills,
-- BodyBox, Holds, Freeze's bodies and sink, IceSink).
function W3.bodyTests(): ()
	print(" WorldReact: air swings, BodyBox, Holds and Freeze's bodies (the second fix round's Q5)")
	local R = W3.React
	local hammer = FIXTURES.proving.weapons.frostHammer.variants.A
	local origin, east = vec(0, 3, 0), vec(1, 0, 0)
	-- SwingStrike carries the verdict; Chills refuses an air swing whatever else it reaches.
	check(R.SwingStrike(hammer, 1, origin, east, true).airborne == true and R.SwingStrike(hammer, 1, origin, east, false).airborne == false, "SwingStrike carries whether the swing was made in the air")
	local cell = W3.cell(5, 0, -0.8)
	check(R.Chills(R.SwingStrike(hammer, 1, origin, east, false), cell, 6, 4), "a grounded swing chills the cell ahead")
	check(not R.Chills(R.SwingStrike(hammer, 1, origin, east, true), cell, 6, 4), "the same swing made in the air chills nothing")
	local spin = W3.arc(origin, east, 9, 360)
	spin.airborne = true
	check(not R.Chills(spin, W3.cell(0, 0, -0.8), 6, 4), "not even a spin over the cell under it")
	spin.airborne = nil
	check(R.Chills(spin, W3.cell(0, 0, -0.8), 6, 4), "a strike that says nothing of the air (nil) is judged as before")

	-- BodyBox: an R15 at (0, 3, 0), its feet on y 0.
	local size, hip = W3.R15.size, W3.R15.hip
	local facing = R.BodyBox(vec(0, 3, 0), vec(1, 0, 0), size, hip)
	check(near(facing.sx, 2) and near(facing.sz, 1) and near(facing.y - facing.sy / 2, 0) and near(facing.y + facing.sy / 2, 6) and facing.x == 0 and facing.z == 0, `facing -Z: 2 across X, 1 along Z, feet at 0, up to 6 ({facing.sx}, {facing.sz}, {facing.y}, {facing.sy})`)
	local turned = R.BodyBox(vec(0, 3, 0), vec(0, 0, 1), size, hip)
	check(near(turned.sx, 1) and near(turned.sz, 2), "turned a quarter: 1 across X, 2 along Z")
	local half = math.sqrt(0.5)
	local slant = R.BodyBox(vec(0, 3, 0), vec(half, 0, -half), size, hip)
	check(near(slant.sx, 3 * half) and near(slant.sz, 3 * half), `turned an eighth: the box round the turned footprint ({slant.sx}, {slant.sz})`)
	local long = R.BodyBox(vec(0, 3, 0), vec(5, 0, 0), size, hip)
	check(near(long.sx, 2) and near(long.sz, 1), "a right vector that is not a unit reads as its direction")
	local tipped = R.BodyBox(vec(0, 3, 0), vec(0, 1, 0), size, hip)
	check(near(tipped.sx, 2) and near(tipped.sz, 1), "a right vector with no flat part reads as facing +X")
	local tall = R.BodyBox(vec(0, 10, 0), vec(1, 0, 0), vec(2, 4, 1), 3)
	check(near(tall.y - tall.sy / 2, 5) and near(tall.y + tall.sy / 2, 15), "the feet are hipHeight and half the root under it")

	-- Holds: a cell 7 x 7 x 4 whose top is -0.8, and a sink of 0.5.
	local box = { x = 0, y = -2.8, z = 0, sx = 7, sy = 4, sz = 7 }
	local function at(x: number, feet: number, z: number?): any
		return R.BodyBox(vec(x, feet + 3, z or 0), vec(1, 0, 0), size, hip)
	end
	check(not R.Holds(box, { at(0, -0.8) }, 0.5), "feet on the cell's top: standing on it, not in it")
	check(not R.Holds(box, { at(0, -1.29) }, 0.5) and R.Holds(box, { at(0, -1.31) }, 0.5), "feet 0.49 under the top: on it; 0.51 under: in it")
	check(R.Holds(box, { at(0, -6) }, 0.5), "a body falling through the cell is in it")
	check(not R.Holds(box, { at(0, -10.8) }, 0.5) and R.Holds(box, { at(0, -10.79) }, 0.5), "a body whose top is the cell's bottom is under it; a hair higher, in it")
	check(not R.Holds(box, { at(0, 0) }, 0.5), "a body on the bank over the cell holds nothing")
	check(not R.Holds(box, { at(4.5, -3) }, 0.5) and R.Holds(box, { at(4.49, -3) }, 0.5), "beside it in plan (touching): not in it; 0.01 over: in it")
	check(not R.Holds(box, { at(0, -3, 4) }, 0.5) and R.Holds(box, { at(0, -3, 3.99) }, 0.5), "and along Z")
	check(not R.Holds(box, { at(0, -3) }, nil) and not R.Holds(box, { at(0, -3) }, -1) and not R.Holds(box, { at(0, -3) }, W3.NAN) and not R.Holds(box, { at(0, -3) }, math.huge), "no sink, or one under 0 or not finite: no body is judged")
	check(R.Holds(box, { at(0, -0.81) }, 0) and not R.Holds(box, { at(0, -0.8) }, 0), "a sink of 0: any depth under the top is in it")
	check(not R.Holds(box, nil, 0.5) and not R.Holds(box, {}, 0.5), "no bodies: none")
	local nan = { x = W3.NAN, y = -3, z = 0, sx = 2, sy = 6, sz = 1 }
	check(not R.Holds(box, { nan }, 0.5) and R.Holds(box, { nan, at(0, -3) }, 0.5), "a body that is not finite is no body; any other one in the cell holds it")
	check(not R.Holds(box, { { x = 0, y = -3, z = 0, sx = 2, sy = math.huge, sz = 1 } }, 0.5), "a body of endless height is no body")
	check(not R.Holds({ x = W3.NAN, y = -2.8, z = 0, sx = 7, sy = 4, sz = 7 }, { at(0, -3) }, 0.5) and not R.Holds({ x = 0, y = -2.8, z = 0, sx = 7, sy = math.huge, sz = 7 }, { at(0, -3) }, 0.5), "a cell that is not finite is held by nothing")

	-- Freeze with bodies: the fixture's cells (tops -0.8, 1 deep) and a swing east from (0, 3, 0).
	local function cells(): any
		return {
			{ box = W3.cell(4, 0, -0.8), frozen = false },
			{ box = W3.cell(-4, 0, -0.8), frozen = false },
			{ box = W3.cell(11, 3, -0.8), frozen = false },
		}
	end
	local swing = W3.arc(vec(0, 3, 0), east)
	local list = cells()
	local frozen = R.Freeze(list, "ice", swing, 6, 4, { at(4, -1.5) }, 0.5)
	check(#frozen == 1 and frozen[1] == 3 and not list[1].frozen, `a body in the first cell keeps it water; the other cell ahead freezes ({table.concat(frozen, ", ")})`)
	local later = R.Freeze(list, "ice", swing, 6, 4, {}, 0.5)
	check(#later == 1 and later[1] == 1 and list[1].frozen, "once the body has gone the next swing freezes it")
	list = cells()
	check(#R.Freeze(list, "ice", swing, 6, 4, { at(4, -1.5) }, 1) == 2, "the sink is handed through (1: feet 0.7 under the top stand on it)")
	list = cells()
	check(#R.Freeze(list, "ice", swing, 6, 4, { at(4, -1.5) }, nil) == 2, "with no sink no body is judged")
	list = cells()
	check(#R.Freeze(list, "ice", swing, 6, 4, { at(0, 0) }, 0.5) == 2, "the swinger's own body on the bank holds nothing")
	list = cells()
	local air = W3.arc(vec(0, 3, 0), east)
	air.airborne = true
	check(#R.Freeze(list, "ice", air, 6, 4, {}, 0.5) == 0 and not list[1].frozen, "a swing made in the air freezes nothing")

	-- IceSink.
	check(R.IceSink({ sink = 0.5 }) == 0.5 and R.IceSink({ sink = 0 }) == 0, "IceSink: a finite number of at least 0")
	check(R.IceSink({ sink = -0.1 }) == nil and R.IceSink({ sink = W3.NAN }) == nil and R.IceSink({ sink = math.huge }) == nil and R.IceSink({ sink = "0.5" }) == nil and R.IceSink({}) == nil and R.IceSink(nil) == nil and R.IceSink("ice") == nil, "under 0, not finite, a word, absent or no table: none")
	local shipped = L1.real.rules.react ~= nil and L1.real.rules.react.ice or nil
	check(shipped ~= nil and R.IceSink(shipped) == shipped.sink and type(shipped.sink) == "number", "the shipped Combat.json: its sink")
end
L1.group("l2w3 bodyTests", W3.bodyTests)

-- The second fix round, Q6: the cells' faces on the water block's own faces are built inset.
function W3.insetTests(): ()
	print(" LevelGeometry: the ice cells inset from their water's faces (the second fix round's Q6)")
	local Geo = W3.Geo
	local function names(inset: any, layout: any?): any
		local found = {}
		local pieces = Geo.Pieces(layout or W3.layout(), { fence = 1, floor = 4, ice = { cell = 7, lift = 0.2, thickness = 1, inset = inset } }, 600)
		for _, piece in pieces or {} do
			if piece.role == "ice" then
				found[piece.name] = piece.box
			end
		end
		return found
	end
	-- The fixture's Water: x -10.5..10.5, z -7..7, cells 2, 3 and 6 built.
	local plain, set = names(0), names(0.5)
	local two, three, six = set.Ice_Water_2, set.Ice_Water_3, set.Ice_Water_6
	check(two ~= nil and three ~= nil and six ~= nil and set.Ice_Water_1 == nil and set.Ice_Water_5 == nil, "the same cells are built (the cover test reads the whole cell)")
	if two ~= nil and three ~= nil and six ~= nil then
		local function edges(b: any): (number, number, number, number)
			return b.x - b.sx / 2, b.x + b.sx / 2, b.z - b.sz / 2, b.z + b.sz / 2
		end
		local w2, e2, n2, s2 = edges(two)
		local w3, e3, n3, s3 = edges(three)
		local w6, e6, n6, s6 = edges(six)
		check(near(n2, -6.5) and near(s2, 0) and near(w2, -3.5) and near(e2, 3.5), `the middle cell of the first row: its north face inset, its sides and south face whole ({w2}, {e2}, {n2}, {s2})`)
		check(near(e3, 10) and near(n3, -6.5) and near(w3, 3.5) and near(s3, 0), `the north-east cell: its east and north faces inset ({w3}, {e3}, {n3}, {s3})`)
		check(near(e6, 10) and near(s6, 6.5) and near(n6, 0) and near(w6, 3.5), `the south-east cell: its east and south faces inset ({w6}, {e6}, {n6}, {s6})`)
		check(near(e2, w3, 1e-12) and near(s3, n6, 1e-12), "the faces between two cells are not inset: neighbours still touch")
		check(near(two.y + two.sy / 2, -0.8) and near(two.sy, 1), "the top and the thickness are untouched")
	end
	local zero = plain.Ice_Water_3
	check(zero ~= nil and near(zero.x, 7, 1e-12) and near(zero.sx, 7, 1e-12) and near(zero.z, -3.5, 1e-12) and near(zero.sz, 7, 1e-12), "an inset of 0: the whole cell, as before")
	-- A water narrower than twice the inset: its one column is left no width, and no cell is built
	-- (a Part of no width would have the whole level refused: Pieces judges every box it lists).
	local thin = W3.layout()
	table.insert(thin.blocks, { name = "Thin", look = "water", x = 60, y = -3, z = 0, sx = 0.8, sy = 4, sz = 14, collide = false, react = "ice" })
	local thinBuilt, thinWhy = Geo.Pieces(thin, { fence = 1, floor = 4, ice = { cell = 7, lift = 0.2, thickness = 1, inset = 0.5 } }, 600)
	check(thinBuilt ~= nil, `a water 0.8 wide with an inset of 0.5: the level still builds ({tostring(thinWhy)})`)
	local thinNames = names(0.5, thin)
	local thinOnes = 0
	for name in thinNames do
		if string.find(name, "^Ice_Thin_") then
			thinOnes += 1
		end
	end
	check(thinOnes == 0 and thinNames.Ice_Water_2 ~= nil, `and that water has no cell, the others theirs ({thinOnes})`)
	local thinZero = names(0, thin)
	check(thinZero.Ice_Thin_1 ~= nil and thinZero.Ice_Thin_2 ~= nil, "with an inset of 0 it has its cells")
	-- The third fix round's fd-s2: two ice blocks touching whole at one top meet with no seam; a side
	-- met only in part, or by a block whose top differs, keeps its inset.
	local pair = W3.layout()
	table.insert(pair.blocks, { name = "Next", look = "water", x = 0, y = -3, z = 14, sx = 21, sy = 4, sz = 14, collide = false, react = "ice" })
	local paired = names(0.25, pair)
	local south, north = paired.Ice_Water_6, paired.Ice_Next_3
	check(south ~= nil and north ~= nil and near(north.z - north.sz / 2, 7, 1e-12) and near(south.z + south.sz / 2, 7, 1e-12), "two ice blocks touching whole at one top: their cells meet on the shared plane, no seam")
	check(south ~= nil and near(south.x + south.sx / 2, 10.25), "and the side of that cell on open air keeps its inset")
	local function eastOf(z: number, sz: number, y: number): any
		local layout = W3.layout()
		table.insert(layout.blocks, { name = "East", look = "water", x = 17.5, y = y, z = z, sx = 14, sy = 4, sz = sz, collide = false, react = "ice" })
		return names(0.25, layout)
	end
	local whole = eastOf(0, 14, -3)
	check(whole.Ice_Water_3 ~= nil and whole.Ice_Water_6 ~= nil and near(whole.Ice_Water_3.x + whole.Ice_Water_3.sx / 2, 10.5, 1e-12) and near(whole.Ice_Water_6.x + whole.Ice_Water_6.sx / 2, 10.5, 1e-12), "an ice block east of the water over its whole depth: the east cells reach the face")
	local part = eastOf(0, 7, -3)
	check(part.Ice_Water_3 ~= nil and part.Ice_Water_6 ~= nil and near(part.Ice_Water_3.x + part.Ice_Water_3.sx / 2, 10.25) and near(part.Ice_Water_6.x + part.Ice_Water_6.sx / 2, 10.25), "one that meets each east cell's side only in part (z -3.5..3.5): both keep the inset")
	local row = eastOf(-3.5, 7, -3)
	check(row.Ice_Water_3 ~= nil and row.Ice_Water_6 ~= nil and near(row.Ice_Water_3.x + row.Ice_Water_3.sx / 2, 10.5, 1e-12) and near(row.Ice_Water_6.x + row.Ice_Water_6.sx / 2, 10.25), "one that meets the first row's side whole (z -7..0): that cell reaches the face, the next keeps its inset")
	local lower = eastOf(0, 14, -3.5)
	check(lower.Ice_Water_3 ~= nil and near(lower.Ice_Water_3.x + lower.Ice_Water_3.sx / 2, 10.25), "one whose top is half a stud lower: the inset stays (their sheets do not meet)")
	local beyond = whole
	check(beyond.Ice_East_1 ~= nil and near(beyond.Ice_East_1.x - beyond.Ice_East_1.sx / 2, 10.5, 1e-12) and near(beyond.Ice_East_2.x + beyond.Ice_East_2.sx / 2, 24.25), "and the neighbour's own cells: whole on the shared side, inset on its open one")
	-- IceOf.
	local react = { ice = { cell = 7, lift = 0.2, thickness = 4 } }
	local got, refused = Geo.IceOf(react)
	check(got ~= nil and got.inset == 0 and refused == false, "no inset: 0")
	react.ice.inset = 0.05
	got, refused = Geo.IceOf(react)
	check(got ~= nil and got.inset == 0.05 and refused == false, "an inset of 0.05: kept")
	for _, bad in { -0.01, W3.NAN, math.huge, "0.05" } do
		react.ice.inset = bad
		got, refused = Geo.IceOf(react)
		check(got == nil and refused == true, `an inset of {tostring(bad)}: refused (deep water with no cells, said once)`)
	end
	local real = Geo.SizesOf(L1.real.map, L1.real.rules)
	local frost = L1.real.rules.react ~= nil and L1.real.rules.react.ice or nil
	check(real.ice ~= nil and frost ~= nil and real.ice.inset == frost.inset and type(frost.inset) == "number", "the shipped Combat.json: its inset as written")
end
L1.group("l2w3 insetTests", W3.insetTests)

-- The second fix round's lines that apply Q5, read as text (FIXTURES.source.w3fix2): the server
-- passes the swing's air verdict and every body to the freeze, the client its ghost and phone.
function W3.fix2WiringTests(): ()
	print(" The second fix round's lines that apply the air swing and the bodies, read as text")
	local f = FIXTURES.source.w3fix2
	if f == nil then
		check(false, "the source reading has a w3fix2 entry")
		return
	end
	check(f.attackJudge == 1 and f.attackPass == 1, `OnAttack hands resolveMelee SwingGate's own verdict for the swing ({f.attackJudge}, {f.attackPass})`)
	check(f.meleeAir == 1 and f.finishAir == 1, `resolveMelee builds its strike with that verdict and sends it to finish() as built ({f.meleeAir}, {f.finishAir})`)
	check(f.freezeSink == 1 and f.freezeHeld == 1 and f.freezeCall == 1, `freeze reads the sink with WorldReact.IceSink and hands every body and it to WorldReact.Freeze ({f.freezeSink}, {f.freezeHeld}, {f.freezeCall})`)
	for name, label in { server = "LevelService's bodies", client = "ReactFx.Bodies" } do
		local b = f.bodies ~= nil and f.bodies[name] or nil
		check(b ~= nil and b.found and b.players == 1 and b.box == 1, `{label}: every player's character as WorldReact.BodyBox of its root and Humanoid ({b and b.found}, {b and b.players}, {b and b.box})`)
	end
	check(f.ghostSink == 1 and f.ghostHolds == 1, `the frost ghost skips a cell a body stands in, with the server's sink ({f.ghostSink}, {f.ghostHolds})`)
	check(f.phoneHolds == 1 and f.phoneGround == 1, `the phone's auto-swing at water skips a cell a body stands in, and builds its strike with the swing's air verdict ({f.phoneHolds}, {f.phoneGround})`)
	check(f.predictedAir == 1 and f.frostAir == 1 and f.hitboxAir == 1, `the predicted swing carries AirSwing's verdict, and the ghost and the early hitbox build their strike with it ({f.predictedAir}, {f.frostAir}, {f.hitboxAir})`)
	check(f.sinkReader == 1, `ReactFx reads the sink with the server's reader ({f.sinkReader})`)
end
L1.group("l2w3 fix2WiringTests", W3.fix2WiringTests)

-- The third fix round (docs/prompts/l2-w3-fix3.md), fd-m2: the server's copy of a falling body
-- trails that player's own screen, where a cell frozen now turns solid a round trip later; the
-- server leads its feet by its fall over the commit lag (WorldReact.FallDrop, BodyBox's `drop`),
-- and the shipped sheet (1.9) is thinner than the root, so a root never lies wholly inside it.
function W3.fix3Tests(): ()
	print(" WorldReact: a falling body's feet led over the commit lag (the third fix round's fd-m2)")
	local R = W3.React
	local Tune = load("Tuning")
	local g = 196.2
	-- FallDrop: speed x lag + g lag^2 / 2, the speed at 0 or more and at most the fastest move.
	check(near(R.FallDrop(19.8, 0.1, g, 140), 1.98 + 0.981), `19.8 studs/s over 0.1 s: 1.98 + 0.981 ({R.FallDrop(19.8, 0.1, g, 140)})`)
	check(near(R.FallDrop(-10, 0.1, g, 140), 0.981) and near(R.FallDrop(0, 0.2, g, 140), 3.924), "a body not yet falling (or rising) still has gravity's part")
	check(near(R.FallDrop(1000, 0.1, g, 140), 14 + 0.981), "a speed over the fastest move is capped at it (the client's word)")
	check(R.FallDrop(20, 0, g, 140) == 0 and R.FallDrop(20, -0.1, g, 140) == 0, "no lag, or one under 0: no drop")
	check(near(R.FallDrop(20, 0.1, 0, 140), 2) and near(R.FallDrop(20, 0.1, -50, 140), 2), "no gravity (or under 0): the speed's part alone")
	check(near(R.FallDrop(20, 0.1, g, -5), 0.981), "a fastest move under 0 leaves gravity's part")
	local bad = 0
	for _, args in { { W3.NAN, 0.1, g, 140 }, { 20, W3.NAN, g, 140 }, { 20, 0.1, W3.NAN, 140 }, { 20, 0.1, g, W3.NAN }, { math.huge, 0.1, g, 140 }, { 20, math.huge, g, 140 }, { 20, 0.1, math.huge, 140 }, { 20, 0.1, g, math.huge } } do
		bad += if R.FallDrop(args[1], args[2], args[3], args[4]) == 0 then 0 else 1
	end
	check(bad == 0, `any number not finite: no drop ({bad} did)`)
	-- BodyBox's drop lowers the feet and keeps the top.
	local size, hip = W3.R15.size, W3.R15.hip
	local led = R.BodyBox(vec(0, 3, 0), vec(1, 0, 0), size, hip, 2.5)
	check(near(led.y - led.sy / 2, -2.5) and near(led.y + led.sy / 2, 6) and near(led.sx, 2) and near(led.sz, 1), `a drop of 2.5: feet at -2.5, the top still 6, the plan unchanged ({led.y}, {led.sy})`)
	local plain = R.BodyBox(vec(0, 3, 0), vec(1, 0, 0), size, hip)
	local same = true
	for _, drop in { 0, -1, W3.NAN, math.huge } do
		local box = R.BodyBox(vec(0, 3, 0), vec(1, 0, 0), size, hip, drop)
		same = same and box.y == plain.y and box.sy == plain.sy
	end
	check(same, "a drop of 0, under 0 or not finite: the body as it stands")
	-- The review's case: a cell whose top is -0.8, the sink 0.5; feet at -1.0 falling at 19.8.
	local cell = { x = 0, y = -1.75, z = 0, sx = 7, sy = 1.9, sz = 7 }
	local function body(feet: number, drop: number?): any
		return R.BodyBox(vec(0, feet + hip + size.Y / 2, 0), vec(1, 0, 0), size, hip, drop)
	end
	check(not R.Holds(cell, { body(-1.0) }, 0.5), "feet at -1.0, 0.2 under the top, unled: standing on it by the sink, the cell would freeze")
	check(R.Holds(cell, { body(-1.0, R.FallDrop(19.8, 0.1, g, 140)) }, 0.5), "led by its fall over a 0.1 s lag (2.96): in it, the cell stays water")

	-- A teammate walks off the bank (top 0) into the creek while another swings at that cell. The
	-- server judges the freeze on its copy of him at server time ts (feet -g ts^2 / 2, falling at
	-- g ts; at ts 0 he still stands, unled); the cell turns solid on his own screen a round trip
	-- later. The shipped sheet, sink and commit lag (his ping is the round trip).
	local frost = L1.real.rules.react ~= nil and L1.real.rules.react.ice or nil
	local proving = FIXTURES.proving
	if type(frost) ~= "table" or proving == nil then
		check(false, "the shipped Combat.json levels.react.ice and ProvingGrounds.json are there")
		return
	end
	local top = -1 + frost.lift
	local shipped = { x = 0, y = top - frost.thickness / 2, z = 0, sx = 7, sy = frost.thickness, sz = 7 }
	local fastest = Tune.FastestMove(proving)
	-- How much of his root (2 tall, its foot hipHeight over his feet) the cell holds when it turns
	-- solid on his screen, at the worst ts it froze; and whether it was ever wholly inside.
	local function walkOff(start: number, trip: number, lead: boolean): (number, boolean)
		local lag = Tune.CommitLag(proving.shooting, trip)
		local worst, whole = 0, false
		for step = 0, 120 do
			local ts = step / 240
			local feet = start - g * ts * ts / 2
			local drop = if lead and step > 0 then R.FallDrop(g * ts, lag, g, fastest) else 0
			if not R.Holds(shipped, { body(feet, drop) }, frost.sink) then
				local later = ts + trip
				local seen = start - g * later * later / 2
				local low, high = seen + hip, seen + hip + size.Y
				local inside = math.max(math.min(high, top) - math.max(low, top - frost.thickness), 0)
				worst = math.max(worst, inside)
				whole = whole or (low >= top - frost.thickness - 1e-9 and high <= top + 1e-9)
			end
		end
		return worst, whole
	end
	local ledIn = walkOff(0, 0.15, true)
	check(ledIn == 0, `off the bank, a 0.15 s round trip, led: no part of his root is in the cell when it turns solid on his screen ({ledIn})`)
	local unledIn = walkOff(0, 0.15, false)
	check(unledIn > 1, `unled, the same walk-off: the cell turns solid round {unledIn} of his root (the lead is what keeps him out)`)
	local everWhole = false
	for _, start in { 0, top } do
		for _, trip in { 0.05, 0.1, 0.15, 0.2, 0.25, 0.3 } do
			for _, lead in { true, false } do
				local _, whole = walkOff(start, trip, lead)
				everWhole = everWhole or whole
			end
		end
	end
	check(not everWhole and frost.thickness < size.Y, `off the bank or the frozen edge, any round trip to 0.3 s, led or not: the sheet ({frost.thickness}) is thinner than his root ({size.Y}), never wholly round it`)
	local edgeIn = walkOff(top, 0.15, true)
	check(edgeIn < 0.25, `off the frozen edge at 0.15 s (his last standing frame cannot be led): at most {edgeIn} of his root, under a quarter stud`)
end
L1.group("l2w3 fix3Tests", W3.fix3Tests)

-- The third fix round's lines that apply fd-m2 and fd-s1, read as text (FIXTURES.source.w3fix3).
function W3.fix3WiringTests(): ()
	print(" The third fix round's lines: the led bodies and the phone's air verdict, read as text")
	local f = FIXTURES.source.w3fix3
	if f == nil then
		check(false, "the source reading has a w3fix3 entry")
		return
	end
	local b = f.bodies or {}
	check(f.bodiesFound and b.bodiesFastest == 1 and b.bodiesFall == 1 and b.bodiesLag == 1 and b.bodiesDrop == 1 and b.bodiesStands == 1, `LevelService's bodies lead a falling body by WeaponService.FallSpeed over Tuning.CommitLag with the player's ping, Workspace.Gravity and Tuning.FastestMove, and a standing one by 0 ({b.bodiesFastest}, {b.bodiesFall}, {b.bodiesLag}, {b.bodiesDrop}, {b.bodiesStands})`)
	local server = FIXTURES.source.w3fix2 and FIXTURES.source.w3fix2.bodies and FIXTURES.source.w3fix2.bodies.server
	check(server ~= nil and server.box == 1, "and hand that drop to WorldReact.BodyBox")
	check(f.trackFall == 1 and f.trackCleared == 1, `trackAir measures the fall of a body it did not find standing, and clears it with no root ({f.trackFall}, {f.trackCleared})`)
	check(f.resetCleared == 1 and f.forgetCleared == 1 and f.fallAnswer == 1, `a fresh body and a server move clear it; FallSpeed answers it ({f.resetCleared}, {f.forgetCleared}, {f.fallAnswer})`)
	check(f.phoneFound and f.phoneJudge == 1 and f.phoneRefuse == 1 and f.phoneCarry == 2 and f.phoneHumanoid == 0, `the phone's ice auto-swing asks AirSwing.Judge, refuses an air swing, carries the verdict into both strikes and never asks the Humanoid ({f.phoneJudge}, {f.phoneRefuse}, {f.phoneCarry}, {f.phoneHumanoid})`)
end
L1.group("l2w3 fix3WiringTests", W3.fix3WiringTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
