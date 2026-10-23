-- Cases for L4 W2, luau-engineer A's (docs/prompts/l4-w2-contract.md §0, §2.2, §3.2, §5): the pure
-- LevelDress (every refusal of Accept, the accept, the walls it arms and the pieces it hides, LeftOut
-- and Overlay, and the shipped forest's dress against its layout and Assets.json), StageFlow.Plan's
-- `kinds` (residents, tents, the waves' most, the boss and its calls; on fixtures and on the shipped
-- Forest Road), the seat (HitShapes.SeatDrop and SeatStep, CrowdRay's `drop`, CrowdService stepping
-- each body's seat as a client does and a dormant body holding its goal, the real config's keys),
-- and the Castle Key (Validate's `key` line, SecretFlow's reward, opening and map row, Unlocks.
-- HasLevelKey). LevelService, which executes Accept's answer, cannot be loaded here: run_harness.py
-- reads its lines as text. Appended by run_harness.py after the earlier case files, so every local
-- of those is in scope (vec, check, near, load, config, Crowd, root, step2, FIXTURES, L1B, L1BC,
-- W2A, W2B). Everything hangs off the L4W table (the 200-local limit), and every group runs behind
-- L4W.group, so a group that throws fails one check and the bundle goes on.

print("L4 W2: the dress, the plan's kinds, the seat and the Castle Key")

local L4W: any = {
	Dress = load("LevelDress"),
	Geo = load("LevelGeometry"),
	Flow = load("StageFlow"),
	Shapes = load("HitShapes"),
	Secrets = load("SecretFlow"),
	Unlocks = load("Unlocks"),
	-- The sizes LevelGeometry builds the fixture with (no sign: the fixture has no secret).
	SIZES = {
		fence = 1,
		floor = 2,
		checkpoint = { sx = 1, sy = 2, sz = 1 },
		fire = { sx = 2, sy = 1, sz = 2 },
	},
	LAYOUT = "Test",
	HASH = "plan-1",
}

function L4W.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `l4w2 group "{name}" threw: {tostring(problem)}`)
	end
end

-- "kind count, kind count", sorted.
function L4W.stock(stock: any): string
	local out = {}
	for kind, count in stock or {} do
		table.insert(out, `{kind} {count}`)
	end
	table.sort(out)
	return table.concat(out, ", ")
end

function L4W.has(text: string?, part: string): boolean
	return type(text) == "string" and string.find(text, part, 1, true) ~= nil
end

-- LevelDress -----------------------------------------------------------------------------------------

-- An open camp A (fence, an obstacle, a checkpoint, a fire, a tent) and the walled boss room C
-- (a gate, its invisible wall), a road, a wall and a bramble that the shortcut "cave" leaves out.
function L4W.layout(): any
	return {
		version = 1,
		start = { x = 0, y = 8, z = 0 },
		killY = -60,
		barrier = { height = 80, thickness = 8 },
		camps = {
			{
				id = "A",
				x = 0,
				y = 8,
				z = 100,
				sx = 40,
				sz = 40,
				fence = { height = 6 },
				gates = {},
				entry = { x = 0, z = 100 },
				exit = { x = 0, z = 100 },
				spawns = {},
				checkpoint = { x = 0, z = 115 },
				obstacles = {
					{
						x = 5,
						z = 100,
						sx = 2,
						sy = 3,
						sz = 2,
						material = "Slate",
						color = { 90, 90, 90 },
					},
				},
				spots = {
					{ id = "fire1", posture = "fire", points = { { x = -5, z = 95 } }, radius = 4 },
				},
				tent = { x = 10, y = 12, z = 110, sx = 4, sy = 8, sz = 4, radius = 5 },
			},
			{
				id = "C",
				x = 0,
				y = 4,
				z = 300,
				sx = 60,
				sz = 60,
				fence = { height = 64 },
				gates = { { side = "north", at = 0, width = 10 } },
				entry = { x = 0, z = 280 },
				exit = { x = 0, z = 300 },
				spawns = {},
				locks = true,
			},
		},
		blocks = {
			{ name = "Road1", look = "path", x = 0, y = 7, z = 50, sx = 10, sy = 2, sz = 60 },
			{ name = "Wall1", look = "wall", x = 20, y = 12, z = 50, sx = 2, sy = 10, sz = 60 },
			{
				name = "Bramble",
				look = "bramble",
				x = -20,
				y = 10,
				z = 50,
				sx = 4,
				sy = 4,
				sz = 4,
				react = "fire",
				opens = "cave",
			},
		},
		secrets = {},
		route = {},
	}
end

function L4W.pieces(open: any?): { any }
	local pieces, problem = L4W.Geo.Pieces(L4W.layout(), L4W.SIZES, 600, open)
	assert(pieces ~= nil, `the fixture builds ({tostring(problem)})`)
	return pieces
end

function L4W.dress(): any
	return {
		version = 1,
		level = "test",
		layout = L4W.LAYOUT,
		planHash = L4W.HASH,
		frame = "level",
		meshes = { { name = "Ground", group = "ground" }, { name = "Trees", group = "canopy" } },
		props = {
			{ piece = "Campfire", x = -5, y = 8, z = 95, yaw = 30, scale = 1 },
			{
				piece = "Bramble",
				x = -20,
				y = 8,
				z = 50,
				yaw = -12.5,
				scale = 1.3,
				with = "Bramble",
			},
		},
		effects = { { kind = "fire", x = -5, y = 8.6, z = 95 } },
		barriers = { { name = "TreeLine1", x = 30, y = 20, z = 50, sx = 4, sy = 40, sz = 60 } },
		hide = {
			blocks = { "Road1", "Wall1" },
			camps = { A = { "floor", "fence", "fire", "tent" }, C = { "floor", "fence" } },
		},
		looks = {
			water = { material = "SmoothPlastic", color = { 52, 80, 82 }, transparency = 0.3 },
		},
	}
end

function L4W.have(): any
	return { Ground = true, Trees = true }
end

-- Accept with the fixture's defaults; `over` replaces any of them by name.
function L4W.accept(over: any?): (any?, string?)
	local args: any = {
		dress = L4W.dress(),
		hash = L4W.HASH,
		have = L4W.have(),
		pieces = L4W.pieces(),
		open = nil,
		groups = true,
		max = 600,
	}
	for key, value in over or {} do
		args[key] = value
	end
	if args.dress == false then
		args.dress = nil
	end
	if args.hash == false then
		args.hash = nil
	end
	return L4W.Dress.Accept(
		args.dress,
		args.hash,
		args.have,
		args.pieces,
		args.open,
		args.groups,
		args.max,
		L4W.LAYOUT
	)
end

-- The fixture's dress with `edit` applied to a fresh copy.
function L4W.edited(edit: (any) -> ()): any
	local dress = L4W.dress()
	edit(dress)
	return dress
end

function L4W.refused(label: string, over: any, part: string): ()
	local accepted, reason = L4W.accept(over)
	check(
		accepted == nil and L4W.has(reason, part),
		`l4w2 dress: {label} is refused, naming why ({tostring(reason)})`
	)
end

function L4W.acceptTests(): ()
	local Dress = L4W.Dress
	print(" LevelDress.Accept: the accept")
	local pieces = L4W.pieces()
	local accepted, reason = L4W.accept({ pieces = pieces })
	check(
		accepted ~= nil and reason == nil,
		`l4w2 dress: the fixture's dress is accepted ({tostring(reason)})`
	)
	if accepted == nil then
		return
	end
	local wall = accepted.walls[1]
	check(
		#accepted.walls == 1 and wall.name == "TreeLine1",
		"l4w2 dress: one wall per barrier, named as the barrier"
	)
	check(
		Dress.WALL_ROLE == "treeline"
			and wall.role == "treeline"
			and wall.camp == nil
			and wall.look == nil
			and wall.collide == true,
		"l4w2 dress: a wall is a piece of role treeline, no camp, no look, armed (collide true)"
	)
	check(
		wall.box.x == 30
			and wall.box.y == 20
			and wall.box.z == 50
			and wall.box.sx == 4
			and wall.box.sy == 40
			and wall.box.sz == 60,
		"l4w2 dress: its box is the barrier's centre and size"
	)
	local hidesBlock = { Road1 = true, Wall1 = true }
	local hidesRole = {
		A = { floor = true, fence = true, fire = true, tent = true },
		C = { floor = true, fence = true },
	}
	local exact, counted, wanted = true, 0, 0
	for _, piece in pieces do
		local want = (piece.role == "block" and hidesBlock[piece.name] == true)
			or (
				piece.camp ~= nil
				and hidesRole[piece.camp] ~= nil
				and hidesRole[piece.camp][piece.role] == true
			)
		if want then
			wanted += 1
		end
		exact = exact and (accepted.hidden[piece.name] == true) == want
	end
	for _ in accepted.hidden do
		counted += 1
	end
	check(
		exact and counted == wanted and wanted >= 12,
		`l4w2 dress: exactly the named blocks and camp roles are hidden ({counted} of {#pieces})`
	)
	check(
		accepted.hidden.Camp_A_Obstacle_1 == nil
			and accepted.hidden.Camp_A_Checkpoint == nil
			and accepted.hidden.Bramble == nil
			and accepted.hidden.Gate_C_1 == nil
			and accepted.hidden.Barrier_C_1 == nil,
		"l4w2 dress: an obstacle, a checkpoint, a reactive block, a gate and a camp's wall it does not name stay as built"
	)
	check(
		accepted.looks.water ~= nil and accepted.looks.water.transparency == 0.3,
		"l4w2 dress: the dress's looks come back to be laid over"
	)
	check(
		type(accepted.word) == "table"
			and accepted.word.layout == L4W.LAYOUT
			and accepted.word.planHash == L4W.HASH,
		"l4w2 dress: the answer carries the word, the layout asked for and the uploaded hash (K7)"
	)
	local _, tight = L4W.accept({ pieces = pieces, max = #pieces })
	local fits = L4W.accept({ pieces = pieces, max = #pieces + 1 })
	check(
		L4W.has(tight, "over levels.maxParts") and fits ~= nil,
		"l4w2 dress: the pieces and the walls together must fit levels.maxParts (one under refuses, exactly fits)"
	)
	-- L2-36: a block the found shortcut left out may be named, and is not hidden (it is not built).
	local open = Dress.LeftOut(L4W.layout(), { cave = true })
	local withCave = L4W.pieces({ cave = true })
	local named = L4W.edited(function(dress)
		table.insert(dress.hide.blocks, "Bramble")
	end)
	local left, leftWhy = L4W.accept({ dress = named, pieces = withCave, open = open })
	check(
		left ~= nil and left.hidden.Bramble == nil,
		`l4w2 dress: a hidden block a found shortcut left out is accepted ({tostring(leftWhy)})`
	)
	local _, notLeft = L4W.accept({ dress = named, pieces = withCave, open = nil })
	check(
		L4W.has(notLeft, "no block of the level"),
		"l4w2 dress: the same name with nothing left out is refused"
	)
	local built = L4W.accept({ dress = named, pieces = pieces, open = nil })
	check(
		built ~= nil and built.hidden.Bramble == true,
		"l4w2 dress: built (no shortcut found), the bramble is hidden like any block named"
	)
end
L4W.group("accept", L4W.acceptTests)

function L4W.refusalTests(): ()
	print(" LevelDress.Accept: every refusal names why")
	L4W.refused("no dress", { dress = false }, "no dress file")
	L4W.refused("a dress of another layout", {
		dress = L4W.edited(function(dress)
			dress.layout = "Other"
		end),
	}, "is for the layout")
	L4W.refused("a frame other than level", {
		dress = L4W.edited(function(dress)
			dress.frame = "plot"
		end),
	}, "frame")
	L4W.refused("nothing uploaded", { hash = false }, "no meshes are uploaded")
	L4W.refused("another plan's hash", { hash = "plan-2" }, "plan hash")
	L4W.refused("a hash that is no string", {
		dress = L4W.edited(function(dress)
			dress.planHash = 5
		end),
		hash = "5",
	}, "plan hash")
	L4W.refused(
		"a mesh with no template",
		{ have = { Ground = true } },
		'the mesh "Trees" has no template'
	)
	L4W.refused("a mesh with no name", {
		dress = L4W.edited(function(dress)
			table.insert(dress.meshes, { group = "dress" })
		end),
	}, "has no name")
	L4W.refused("meshes that are no list", {
		dress = L4W.edited(function(dress)
			dress.meshes = "all"
		end),
	}, "meshes are not a list")
	L4W.refused("a hidden block no block is", {
		dress = L4W.edited(function(dress)
			table.insert(dress.hide.blocks, "Nowhere")
		end),
	}, "no block of the level")
	L4W.refused("a hidden name of a camp piece in hide.blocks", {
		dress = L4W.edited(function(dress)
			table.insert(dress.hide.blocks, "Camp_A_Floor")
		end),
	}, "no block of the level")
	L4W.refused("a hide.camps camp with no piece", {
		dress = L4W.edited(function(dress)
			dress.hide.camps.Z = { "floor" }
		end),
	}, 'the camp "Z", which the level has no piece of')
	L4W.refused("a hide.camps role a dress may not hide (a gate)", {
		dress = L4W.edited(function(dress)
			dress.hide.camps.C = { "floor", "gate" }
		end),
	}, "may not hide")
	L4W.refused("a hide.camps role a dress may not hide (a checkpoint)", {
		dress = L4W.edited(function(dress)
			dress.hide.camps.A = { "checkpoint" }
		end),
	}, "may not hide")
	L4W.refused("a hide.camps role the camp has no piece of", {
		dress = L4W.edited(function(dress)
			dress.hide.camps.C = { "obstacle" }
		end),
	}, "no piece of that camp has")
	L4W.refused("no hide block", {
		dress = L4W.edited(function(dress)
			dress.hide = nil
		end),
	}, "hide block")
	L4W.refused("the walls' groups refused", { groups = false }, "collision groups")
	for _, case in
		{
			{ "a barrier with no size", "sx", 0 },
			{ "a barrier of a negative height", "sy", -1 },
			{ "a barrier at NaN", "x", 0 / 0 },
			{ "a barrier at infinity", "z", math.huge },
			{ "a barrier with no name", "name", nil },
			{ "a barrier with an empty name", "name", "" },
		}
	do
		L4W.refused(case[1], {
			dress = L4W.edited(function(dress)
				dress.barriers[1][case[2]] = case[3]
			end),
		}, "barrier 1")
	end
	L4W.refused("a barrier named as a piece", {
		dress = L4W.edited(function(dress)
			dress.barriers[1].name = "Road1"
		end),
	}, "already a Part's")
	L4W.refused("two barriers of one name", {
		dress = L4W.edited(function(dress)
			table.insert(
				dress.barriers,
				{ name = "TreeLine1", x = 0, y = 1, z = 0, sx = 1, sy = 1, sz = 1 }
			)
		end),
	}, "already a Part's")
	L4W.refused("barriers that are no list", {
		dress = L4W.edited(function(dress)
			dress.barriers = 3
		end),
	}, "barriers are not a list")
end
L4W.group("refusals", L4W.refusalTests)

-- K7 (slice 1 m2, slice 2 m1): every shape LevelService, LevelScenery or Accept itself iterates is
-- refused when it is not one, never thrown on.
function L4W.shapeTests(): ()
	print(" LevelDress.Accept: every malformed shape is a refusal (K7)")
	L4W.refused("hide.blocks that is no list", {
		dress = L4W.edited(function(dress)
			dress.hide.blocks = 5
		end),
	}, "hide.blocks is not a list")
	L4W.refused("hide.blocks holding a number", {
		dress = L4W.edited(function(dress)
			table.insert(dress.hide.blocks, 7)
		end),
	}, "not a block's name")
	L4W.refused("hide.camps that is no table", {
		dress = L4W.edited(function(dress)
			dress.hide.camps = "x"
		end),
	}, "hide.camps is not a table")
	L4W.refused("a camp's role list that is no list", {
		dress = L4W.edited(function(dress)
			dress.hide.camps.A = 5
		end),
	}, "hide.camps.A is not a list of roles")
	L4W.refused("a hide.camps key that is no camp id", {
		dress = L4W.edited(function(dress)
			dress.hide.camps[1] = { "floor" }
		end),
	}, "not a camp id")
	L4W.refused("no props", {
		dress = L4W.edited(function(dress)
			dress.props = nil
		end),
	}, "props are not a list")
	L4W.refused("props that are no list", {
		dress = L4W.edited(function(dress)
			dress.props = "trees"
		end),
	}, "props are not a list")
	for _, case in
		{
			{ "a prop that is no table", nil, 4, "prop 2 is not a table" },
			{ "a prop naming no piece", "piece", nil, "prop 2 names no piece" },
			{ "a prop naming an empty piece", "piece", "", "prop 2 names no piece" },
			{ "a prop at NaN", "x", 0 / 0, "prop 2 has a place or a turn" },
			{ "a prop with no height", "y", nil, "prop 2 has a place or a turn" },
			{ "a prop at infinity", "z", -math.huge, "prop 2 has a place or a turn" },
			{ "a prop with no turn", "yaw", nil, "prop 2 has a place or a turn" },
			{ "a prop of scale 0", "scale", 0, "prop 2 has a scale" },
			{ "a prop of a negative scale", "scale", -1, "prop 2 has a scale" },
			{ "a prop with no scale", "scale", nil, "prop 2 has a scale" },
			{ "a prop of a NaN scale", "scale", 0 / 0, "prop 2 has a scale" },
			{ "a prop with an empty with", "with", "", "prop 2 stands with something" },
			{ "a prop with a number for with", "with", 3, "prop 2 stands with something" },
		}
	do
		L4W.refused(case[1], {
			dress = L4W.edited(function(dress)
				if case[2] == nil then
					dress.props[2] = case[3]
				else
					dress.props[2][case[2]] = case[3]
				end
			end),
		}, case[4])
	end
	L4W.refused("no effects", {
		dress = L4W.edited(function(dress)
			dress.effects = nil
		end),
	}, "effects are not a list")
	L4W.refused("effects that are no list", {
		dress = L4W.edited(function(dress)
			dress.effects = true
		end),
	}, "effects are not a list")
	for _, case in
		{
			{ "an effect that is no table", nil, "fire", "effect 1 is not a table" },
			{ "an effect with no kind", "kind", nil, "effect 1 has no kind" },
			{ "an effect of an empty kind", "kind", "", "effect 1 has no kind" },
			{ "an effect at NaN", "y", 0 / 0, "effect 1 has a place" },
			{ "an effect with no x", "x", nil, "effect 1 has a place" },
			{ "an effect at infinity", "z", math.huge, "effect 1 has a place" },
		}
	do
		L4W.refused(case[1], {
			dress = L4W.edited(function(dress)
				if case[2] == nil then
					dress.effects[1] = case[3]
				else
					dress.effects[1][case[2]] = case[3]
				end
			end),
		}, case[4])
	end
	local quiet, quietWhy = L4W.accept({
		dress = L4W.edited(function(dress)
			dress.props = {}
			dress.effects = {}
		end),
	})
	check(
		quiet ~= nil,
		`l4w2 dress: empty props and effects are lists, and accepted ({tostring(quietWhy)})`
	)
	local other, otherWhy = L4W.accept({
		dress = L4W.edited(function(dress)
			dress.effects[1].kind = "smoke"
			dress.props[1].with = nil
		end),
	})
	check(
		other ~= nil,
		`l4w2 dress: an effect of another kind and a prop with no with are sound ({tostring(
			otherWhy
		)})`
	)
end
L4W.group("shapes", L4W.shapeTests)

-- K7: the Ask Decide judges, as LevelService.dressOf gathers it; `over` replaces any field by name
-- (false stands for nil).
function L4W.ask(over: any?): any
	local ask: any = {
		dress = L4W.dress(),
		uploadedHash = L4W.HASH,
		failLever = false,
		templates = { Ground = { "rbxassetid://11" }, Trees = { "rbxassetid://12" } },
		layout = L4W.layout(),
		pieces = L4W.pieces(),
		found = nil,
		groupsOk = true,
		maxParts = 600,
		layoutName = L4W.LAYOUT,
	}
	for key, value in over or {} do
		ask[key] = if value == false
				and key ~= "failLever"
				and key ~= "groupsOk"
			then nil
			else value
	end
	return ask
end

function L4W.decideTests(): ()
	local Dress = L4W.Dress
	print(" LevelDress.Decide, Present, Lay: the build's one decision (K7)")
	local accepted, reason = Dress.Decide(L4W.ask())
	check(
		accepted ~= nil and reason == nil,
		`l4w2 decide: the fixture is dressed ({tostring(reason)})`
	)
	if accepted == nil then
		return
	end
	check(
		accepted.word.layout == L4W.LAYOUT and accepted.word.planHash == L4W.HASH,
		"l4w2 decide: the answer carries the word (Dress = the layout, DressHash = the uploaded hash)"
	)
	local direct = L4W.accept()
	local same = direct ~= nil and #direct.walls == #accepted.walls
	if direct ~= nil then
		for name in direct.hidden do
			same = same and accepted.hidden[name] == true
		end
		for name in accepted.hidden do
			same = same and direct.hidden[name] == true
		end
	end
	check(same, "l4w2 decide: and is Accept's answer, the same walls and hidden pieces")

	-- The Z lever.
	local levered, leverWhy = Dress.Decide(L4W.ask({ failLever = true }))
	check(
		levered == nil and L4W.has(leverWhy, "plan hash") and L4W.has(leverWhy, Dress.FAILED_HASH),
		`l4w2 decide: the Z lever hands Accept its own hash, refused as another plan's ({tostring(
			leverWhy
		)})`
	)
	check(
		type(Dress.FAILED_HASH) == "string"
			and Dress.FAILED_HASH ~= L4W.HASH
			and string.match(Dress.FAILED_HASH, "^%x+$") == nil,
		"l4w2 decide: the lever's hash can never be an uploaded one (a plan hash is hex)"
	)
	local _, noUpload = Dress.Decide(L4W.ask({ uploadedHash = false }))
	check(
		L4W.has(noUpload, "no meshes are uploaded"),
		`l4w2 decide: no uploaded hash is refused ({tostring(noUpload)})`
	)

	-- Templates: present only with a mesh.
	for _, case in
		{
			{ "a template holding no MeshPart", {} },
			{ "a template whose MeshId is empty", { "" } },
			{ "a template whose MeshId is the never-uploaded 0", { "rbxassetid://0" } },
		}
	do
		local _, why = Dress.Decide(L4W.ask({
			templates = { Ground = { "rbxassetid://11" }, Trees = case[2] },
		}))
		check(
			L4W.has(why, 'the mesh "Trees" has no template'),
			`l4w2 decide: {case[1]} is no template ({tostring(why)})`
		)
	end
	local _, missing = Dress.Decide(L4W.ask({ templates = { Ground = { "rbxassetid://11" } } }))
	check(
		L4W.has(missing, 'the mesh "Trees" has no template'),
		`l4w2 decide: a mesh with no Model is refused ({tostring(missing)})`
	)
	local mixed, mixedWhy = Dress.Decide(L4W.ask({
		templates = { Ground = { "rbxassetid://11" }, Trees = { "", "rbxassetid://12" } },
	}))
	check(mixed ~= nil, `l4w2 decide: one MeshPart with a mesh is enough ({tostring(mixedWhy)})`)
	local present = Dress.Present({
		A = { "rbxassetid://5" },
		B = {},
		C = { "" },
		D = { "rbxassetid://0" },
		E = { "", "rbxassetid://7" },
		F = { 5 :: any },
	})
	check(
		L4W.stock(present) == "A true, E true",
		`l4w2 decide: Present names the Models holding a mesh ({L4W.stock(present)})`
	)

	-- A throw is a refusal (slice 1 m2): a piece with no name, a dress that errors when read.
	local thrown, thrownWhy = Dress.Decide(L4W.ask({ pieces = { { role = "block" } } }))
	check(
		thrown == nil and L4W.has(thrownWhy, "could not be read"),
		`l4w2 decide: Accept throwing is a refusal, not a throw ({tostring(thrownWhy)})`
	)
	local cursed = setmetatable({}, {
		__index = function(): any
			error("cursed dress")
		end,
	})
	local _, cursedWhy = Dress.Decide(L4W.ask({ dress = cursed }))
	check(
		L4W.has(cursedWhy, "could not be read") and L4W.has(cursedWhy, "cursed dress"),
		`l4w2 decide: and names the error ({tostring(cursedWhy)})`
	)

	-- The found shortcuts become the names left out (L2-36).
	local named = L4W.edited(function(dress)
		table.insert(dress.hide.blocks, "Bramble")
	end)
	local withCave = L4W.pieces({ cave = true })
	local left, leftWhy =
		Dress.Decide(L4W.ask({ dress = named, pieces = withCave, found = { cave = true } }))
	check(
		left ~= nil and left.hidden.Bramble == nil,
		`l4w2 decide: a found shortcut leaves its block's name out ({tostring(leftWhy)})`
	)
	local _, notFound = Dress.Decide(L4W.ask({ dress = named, pieces = withCave }))
	check(
		L4W.has(notFound, "no block of the level"),
		`l4w2 decide: with nothing found the same name is refused ({tostring(notFound)})`
	)

	-- The rest of the ask reaches Accept.
	local _, noGroups = Dress.Decide(L4W.ask({ groupsOk = false }))
	check(L4W.has(noGroups, "collision groups"), "l4w2 decide: the groups are asked")
	local _, tooMany = Dress.Decide(L4W.ask({ maxParts = 3 }))
	check(L4W.has(tooMany, "over levels.maxParts"), "l4w2 decide: maxParts is asked")
	local _, otherName = Dress.Decide(L4W.ask({ layoutName = "Other" }))
	check(L4W.has(otherName, "is for the layout"), "l4w2 decide: the layout's own name is asked")
	local _, noDress = Dress.Decide(L4W.ask({ dress = false }))
	check(L4W.has(noDress, "no dress file"), "l4w2 decide: no dress file is refused")
end
L4W.group("decide", L4W.decideTests)

function L4W.layTests(): ()
	local Dress = L4W.Dress
	print(" LevelDress.Lay: what is built")
	local pieces = L4W.pieces()
	local count = #pieces
	local base = {
		water = { material = "Glass", color = { 1, 2, 3 } },
		ground = { material = "Grass", color = { 4, 5, 6 } },
	}
	local grey = Dress.Lay(pieces, base, nil)
	check(
		grey.pieces == pieces
			and next(grey.hidden) == nil
			and grey.looks == base
			and grey.word == nil,
		"l4w2 lay: grey is the pieces themselves, nothing hidden, the base looks and no word"
	)
	check(Dress.Lay(pieces, nil, nil).looks == nil, "l4w2 lay: grey with no base has no looks")
	local accepted = Dress.Decide(L4W.ask({ pieces = pieces }))
	if accepted == nil then
		check(false, "l4w2 lay: the fixture is dressed")
		return
	end
	local laid = Dress.Lay(pieces, base, accepted)
	local walls = accepted.walls
	local order = #laid.pieces == count + #walls and #walls >= 1
	for index = 1, count do
		order = order and laid.pieces[index] == pieces[index]
	end
	for index, wall in walls do
		order = order and laid.pieces[count + index] == wall
	end
	check(order, "l4w2 lay: dressed, the pieces then the walls, in order")
	check(
		laid.pieces ~= pieces and #pieces == count,
		"l4w2 lay: in a new list (the layout's pieces are not changed)"
	)
	check(laid.hidden == accepted.hidden, "l4w2 lay: the pieces a mesh draws over are hidden")
	check(
		laid.looks ~= nil
			and laid.looks.water == accepted.looks.water
			and laid.looks.ground == base.ground
			and base.water.material == "Glass",
		"l4w2 lay: the dress's looks laid over the base, the base unchanged"
	)
	check(
		laid.word ~= nil and laid.word.layout == L4W.LAYOUT and laid.word.planHash == L4W.HASH,
		"l4w2 lay: and the word to set"
	)
end
L4W.group("lay", L4W.layTests)

function L4W.helperTests(): ()
	local Dress = L4W.Dress
	print(" LevelDress.LeftOut, Overlay")
	local layout = L4W.layout()
	check(
		L4W.stock(Dress.LeftOut(layout, { cave = true })) == "Bramble true",
		"l4w2 dress: LeftOut names the block a found shortcut opens"
	)
	check(
		next(Dress.LeftOut(layout, nil)) == nil
			and next(Dress.LeftOut(layout, { other = true })) == nil,
		"l4w2 dress: and nothing for no shortcut, or another"
	)
	local base = {
		water = { material = "Glass", color = { 1, 2, 3 } },
		ground = { material = "Grass", color = { 4, 5, 6 } },
	}
	local over = {
		water = { material = "SmoothPlastic", color = { 7, 8, 9 } },
		gate = { material = "Wood", color = { 1, 1, 1 } },
	}
	local looks = Dress.Overlay(base, over)
	check(
		looks.water == over.water and looks.gate == over.gate and looks.ground == base.ground,
		"l4w2 dress: Overlay takes the dress's look of a name and keeps every other"
	)
	check(
		base.water.material == "Glass" and base.gate == nil and looks ~= base,
		"l4w2 dress: and changes neither table"
	)
	check(
		next(Dress.Overlay(nil, nil)) == nil and Dress.Overlay(base, nil).ground == base.ground,
		"l4w2 dress: nil on either side reads as empty"
	)
end
L4W.group("helpers", L4W.helperTests)

-- The shipped forest: its dress accepted against its layout as WaveService builds it (the leader
-- with no shortcut, and with the cave found), its plan hash the uploaded one (Assets.json). The
-- templates are gen_templates.py's gate (`--check`): here the dress's own mesh names stand for them.
function L4W.shippedTests(): ()
	local Dress, Geo = L4W.Dress, L4W.Geo
	print(" The shipped forest's dress")
	local name = "ForestRoad"
	local dresses = FIXTURES.levelDress
	local dress = if dresses ~= nil then dresses[name] else nil
	local hashes = FIXTURES.levelHashes
	local hash = if hashes ~= nil then hashes[name] else nil
	check(
		dress ~= nil and hash ~= nil,
		"l4w2 shipped: the dress file and Assets.json's levels.ForestRoad are fixtures (run_harness.py)"
	)
	if dress == nil then
		return
	end
	local layout = FIXTURES.layouts[name]
	local rules = FIXTURES.combat.levels
	local sizes = Geo.SizesOf(FIXTURES.expeditions, rules)
	local have = {}
	local templates = {}
	for index, mesh in dress.meshes do
		have[mesh.name] = true
		templates[mesh.name] = { `rbxassetid://{index}` }
	end
	for _, open in { {}, { cave = true } } do
		local pieces = Geo.Pieces(layout, sizes, rules.maxParts, open)
		local accepted, reason = Dress.Accept(
			dress,
			hash,
			have,
			pieces,
			Dress.LeftOut(layout, open),
			true,
			rules.maxParts,
			name
		)
		local label = if next(open) ~= nil then "with the cave found" else "with no shortcut"
		check(
			accepted ~= nil,
			`l4w2 shipped: Forest Road's dress is accepted {label} ({tostring(reason)})`
		)
		if accepted == nil then
			continue
		end
		check(
			#accepted.walls == #dress.barriers and #pieces + #accepted.walls <= rules.maxParts,
			`l4w2 shipped: {#accepted.walls} walls, {#pieces + #accepted.walls} Parts of {rules.maxParts} ({label})`
		)
		local hiddenRight = true
		for _, piece in pieces do
			if accepted.hidden[piece.name] then
				hiddenRight = hiddenRight
					and (piece.role == "block" or piece.role == "floor" or piece.role == "fence" or piece.role == "obstacle" or piece.role == "fire" or piece.role == "tent")
					and piece.react == nil
			end
		end
		check(
			hiddenRight,
			`l4w2 shipped: nothing hidden is a gate, a checkpoint, a wall, a secret, a sign, ice or a reactive block ({label})`
		)
		-- K7: as LevelService.dressOf asks it (the found shortcut's id, every template with a mesh).
		local decided, decidedWhy = Dress.Decide({
			dress = dress,
			uploadedHash = hash,
			failLever = false,
			templates = templates,
			layout = layout,
			pieces = pieces,
			found = open,
			groupsOk = true,
			maxParts = rules.maxParts,
			layoutName = name,
		})
		local laid = if decided ~= nil
			then Dress.Lay(pieces, FIXTURES.expeditions.looks, decided)
			else nil
		check(
			laid ~= nil
				and laid.word ~= nil
				and laid.word.layout == name
				and laid.word.planHash == hash
				and #laid.pieces == #pieces + #dress.barriers,
			`l4w2 shipped: Decide dresses it and Lay builds the pieces and the walls, word "{name}" ({label}, {tostring(
				decidedWhy
			)})`
		)
	end
	check(
		hash == dress.planHash,
		`l4w2 shipped: the dress's plan hash is the uploaded one ({tostring(dress.planHash)} / {tostring(
			hash
		)})`
	)
end
L4W.group("shipped dress", L4W.shippedTests)

-- StageFlow.Plan's kinds -----------------------------------------------------------------------------

function L4W.kindsTests(): ()
	local Flow = L4W.Flow
	print(" StageFlow.Plan: kinds")
	-- L1B's road (no tent): residents A 9 fodder (+1 slinger from Hard), B 5 fodder, a brute, 2
	-- slingers (+1 armoured, +1 slinger from Hard), C 3 fodder (+1 armoured from Brutal); C's waves
	-- 6 fodder (x countMult), then the colossus, who calls 20 fodder.
	local function kindsOf(difficulty: string, kinds: any?, level: any?): string
		local plan = Flow.Plan(
			level or L1B.level(),
			L1B.layout(),
			difficulty,
			L1B.rules,
			L1B.bounds,
			L1B.ranks,
			kinds
		)
		return if plan ~= nil then L4W.stock(plan.kinds) else "(no plan)"
	end
	check(
		kindsOf("normal", L1B.kinds) == "brute 1, colossus 1, fodder 37, slinger 2",
		`l4w2 kinds: Normal: residents, then the boss and his call outnumber the first wave ({kindsOf(
			"normal",
			L1B.kinds
		)})`
	)
	check(
		kindsOf("hard", L1B.kinds) == "armoured 1, brute 1, colossus 1, fodder 37, slinger 4",
		`l4w2 kinds: Hard adds its minDifficulty residents ({kindsOf("hard", L1B.kinds)})`
	)
	check(
		kindsOf("brutal", L1B.kinds) == "armoured 2, brute 1, colossus 1, fodder 37, slinger 4",
		`l4w2 kinds: Brutal adds its own ({kindsOf("brutal", L1B.kinds)})`
	)
	-- A colossus that calls 5: the first wave (6 x countMult, rounded) is now the most fodder.
	local small = {
		colossus = {
			radius = 4,
			attacks = {
				{ shape = "summon", reach = 60, count = 5, summon = "fodder" },
				{ shape = "summon", reach = 60, count = 3, summon = "fodder" },
			},
		},
	}
	check(
		kindsOf("normal", small) == "brute 1, colossus 1, fodder 23, slinger 2",
		`l4w2 kinds: a wave's count when it is the most (6 over a call of 5) ({kindsOf(
			"normal",
			small
		)})`
	)
	check(
		kindsOf("hard", small) == "armoured 1, brute 1, colossus 1, fodder 25, slinger 4",
		`l4w2 kinds: a wave's count takes countMult, rounded (6 x 1.25 = 8) ({kindsOf("hard", small)})`
	)
	check(
		kindsOf("brutal", small) == "armoured 2, brute 1, colossus 1, fodder 26, slinger 4",
		`l4w2 kinds: (6 x 1.5 = 9) ({kindsOf("brutal", small)})`
	)
	check(
		kindsOf("normal", nil) == "brute 1, colossus 1, fodder 23, slinger 2",
		`l4w2 kinds: without the crowd kinds a boss counts itself alone ({kindsOf("normal", nil)})`
	)
	-- A minDifficulty group in a wave, and a kind only a wave fields.
	local withLobbers = L1B.level()
	table.insert(
		withLobbers.stages[2].waves[1].groups,
		{ kind = "lobber", count = 2, minDifficulty = "hard" }
	)
	check(
		not L4W.has(kindsOf("normal", L1B.kinds, withLobbers), "lobber"),
		"l4w2 kinds: a wave's minDifficulty group is not fielded under it"
	)
	check(
		L4W.has(kindsOf("hard", L1B.kinds, withLobbers), "lobber 3"),
		`l4w2 kinds: and is at it, x countMult (2 x 1.25 = 3) ({kindsOf(
			"hard",
			L1B.kinds,
			withLobbers
		)})`
	)
	-- W2B's tents: A's 2 fodder, a brute and a Hard slinger; B's 3 fodder.
	local tented = W2B.plan(nil, nil, "normal")
	local tentedHard = W2B.plan(nil, nil, "hard")
	check(
		tented ~= nil and L4W.stock(tented.kinds) == "brute 2, colossus 1, fodder 42, slinger 2",
		`l4w2 kinds: every tent's stock counts ({if tented ~= nil
			then L4W.stock(tented.kinds)
			else "no plan"})`
	)
	check(
		tentedHard ~= nil
			and L4W.stock(tentedHard.kinds)
				== "armoured 1, brute 2, colossus 1, fodder 42, slinger 5",
		`l4w2 kinds: a tent's minDifficulty unit at its difficulty ({if tentedHard ~= nil
			then L4W.stock(tentedHard.kinds)
			else "no plan"})`
	)
	-- A wave group of none, and a call of none: a kind with no body is absent.
	local none = L1B.level()
	table.insert(none.stages[2].waves[1].groups, { kind = "pawn", count = 0 })
	local quiet = {
		colossus = {
			radius = 4,
			attacks = { { shape = "summon", reach = 60, count = 0, summon = "caller" } },
		},
	}
	local plan = Flow.Plan(none, L1B.layout(), "normal", L1B.rules, L1B.bounds, L1B.ranks, quiet)
	local positive = plan ~= nil
	for _, count in (if plan ~= nil then plan.kinds else {}) do
		positive = positive and count > 0 and count % 1 == 0
	end
	check(
		positive and plan.kinds.pawn == nil and plan.kinds.caller == nil,
		`l4w2 kinds: every count is a whole number above 0, a kind with none absent ({if plan
				~= nil
			then L4W.stock(plan.kinds)
			else "no plan"})`
	)
end
L4W.group("kinds", L4W.kindsTests)

-- The shipped Forest Road, its kinds counted here from its file the way the contract words them.
function L4W.shippedKindsTests(): ()
	local Flow, Geo = L4W.Flow, L4W.Geo
	print(" StageFlow.Plan: the shipped Forest Road's kinds")
	local file = nil
	for _, candidate in FIXTURES.levels do
		if candidate.id == "forestRoad" then
			file = candidate
		end
	end
	if file == nil then
		check(false, "l4w2 kinds: Forest Road's level file is there")
		return
	end
	local rules = FIXTURES.combat.levels
	local layout = FIXTURES.layouts[file.layout]
	local level = Flow.Resolve(file, FIXTURES.combat.director.runCapSeconds)
	local ranks = {}
	for index, name in FIXTURES.expeditions.difficulties do
		ranks[name] = index
	end
	local crowdKinds = FIXTURES.proving.crowd.kinds
	local bounds = Geo.Bounds(layout, rules.floorThickness)
	for difficulty, scales in file.difficulties do
		local rank = ranks[difficulty]
		local function fielded(unit: any): boolean
			return unit.minDifficulty == nil
				or (ranks[unit.minDifficulty] ~= nil and ranks[unit.minDifficulty] <= rank)
		end
		local want = {}
		local function add(kind: string, count: number): ()
			want[kind] = (want[kind] or 0) + count
		end
		for _, camp in file.camps do
			for _, group in camp.residents or {} do
				for _, unit in group.units do
					if fielded(unit) then
						add(unit.kind, unit.count)
					end
				end
			end
			if camp.tent ~= nil then
				for _, unit in camp.tent.units do
					if fielded(unit) then
						add(unit.kind, unit.count)
					end
				end
			end
		end
		local most = {}
		for _, stage in file.stages do
			for _, wave in stage.waves or {} do
				local here = {}
				for _, unit in wave.groups or {} do
					if fielded(unit) then
						here[unit.kind] = (here[unit.kind] or 0)
							+ math.round(unit.count * scales.countMult)
					end
				end
				if wave.boss ~= nil then
					here[wave.boss.kind] = (here[wave.boss.kind] or 0) + 1
					local calls = {}
					for _, attack in (crowdKinds[wave.boss.kind] or {}).attacks or {} do
						if attack.shape == "summon" then
							calls[attack.summon] = math.max(calls[attack.summon] or 0, attack.count)
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
			add(kind, count)
		end
		local plan, why = Flow.Plan(level, layout, difficulty, rules, bounds, ranks, crowdKinds)
		local got = if plan ~= nil then L4W.stock(plan.kinds) else `(no plan: {tostring(why)})`
		check(got == L4W.stock(want), `l4w2 kinds: Forest Road on {difficulty}: {got}`)
		local known = plan ~= nil
		for kind in (if plan ~= nil then plan.kinds else {}) do
			known = known and crowdKinds[kind] ~= nil
		end
		check(
			known,
			`l4w2 kinds: every kind Forest Road fields on {difficulty} is a ProvingGrounds.json kind`
		)
	end
end
L4W.group("shipped kinds", L4W.shippedKindsTests)

-- K3 (the lobby fill): the lobby's RunState.prewarm is StageFlow.MostKinds over every built level's
-- plan at every difficulty (WaveService.refreshLobbyKinds; its loop is run_harness.py's pins).
function L4W.lobbyKindsTests(): ()
	local Flow, Geo = L4W.Flow, L4W.Geo
	print(" StageFlow.MostKinds: the lobby's prewarm (K3)")
	local a = { fodder = 3, brute = 1 }
	local b = { fodder = 2, slinger = 4 }
	local most = Flow.MostKinds({ a, b, {} })
	check(
		L4W.stock(most) == "brute 1, fodder 3, slinger 4",
		`l4w2 lobby: each kind's most over the plans, every kind kept ({L4W.stock(most)})`
	)
	check(
		most ~= a
			and most ~= b
			and L4W.stock(a) == "brute 1, fodder 3"
			and L4W.stock(b) == "fodder 2, slinger 4",
		"l4w2 lobby: a new table, the plans' own kinds unchanged"
	)
	check(
		L4W.stock(Flow.MostKinds({ b, a })) == "brute 1, fodder 3, slinger 4",
		"l4w2 lobby: whatever the order of the plans"
	)
	check(
		Flow.MostKinds({}) == nil and Flow.MostKinds({ {}, { fodder = 0 } }) == nil,
		"l4w2 lobby: no plan, or none fielding a body, sends nothing"
	)
	-- The shipped levels, every difficulty, planned as WaveService plans them.
	local rules = FIXTURES.combat.levels
	local ranks = {}
	for index, name in FIXTURES.expeditions.difficulties do
		ranks[name] = index
	end
	local crowdKinds = FIXTURES.proving.crowd.kinds
	local found, want, plans = {}, {}, 0
	for _, file in FIXTURES.levels do
		local layout = FIXTURES.layouts[file.layout]
		local level = Flow.Resolve(file, FIXTURES.combat.director.runCapSeconds)
		if layout == nil or level == nil then
			continue
		end
		local bounds = Geo.Bounds(layout, rules.floorThickness)
		for _, difficulty in FIXTURES.expeditions.difficulties do
			if level.difficulties[difficulty] == nil then
				continue
			end
			local plan = Flow.Plan(level, layout, difficulty, rules, bounds, ranks, crowdKinds)
			if plan ~= nil then
				plans += 1
				table.insert(found, plan.kinds)
				for kind, count in plan.kinds do
					want[kind] = math.max(want[kind] or 0, count)
				end
			end
		end
	end
	local lobby = Flow.MostKinds(found)
	check(
		plans >= 3 and lobby ~= nil and L4W.stock(lobby) == L4W.stock(want),
		`l4w2 lobby: the shipped lobby prewarms {L4W.stock(lobby)} ({plans} plans)`
	)
	local covers = lobby ~= nil
	for _, kinds in found do
		for kind, count in kinds do
			covers = covers and lobby ~= nil and (lobby[kind] or 0) >= count
		end
	end
	check(covers, "l4w2 lobby: at least every plan's own count of every kind")
end
L4W.group("lobby kinds", L4W.lobbyKindsTests)

-- The seat -------------------------------------------------------------------------------------------

function L4W.seatShapeTests(): ()
	local Shapes = L4W.Shapes
	print(" HitShapes.SeatDrop, SeatStep, CrowdRay's drop")
	check(
		Shapes.SeatDrop(5, 0, 0.35) == 0 and near(Shapes.SeatDrop(5, 1, 0.35), 1.75, 1e-12),
		"l4w2 seat: standing drops nothing, seated height x restDrop"
	)
	check(
		near(Shapes.SeatDrop(5, 0.5, 0.35), 0.875, 1e-12)
			and near(Shapes.SeatDrop(5, 0.25, 0.35), 1.75 * 0.15625, 1e-12),
		"l4w2 seat: eased by smoothstep (0.5 at half, 0.15625 at a quarter)"
	)
	check(
		near(Shapes.SeatDrop(5, 2, 0.35), 1.75, 1e-12) and Shapes.SeatDrop(5, -1, 0.35) == 0,
		"l4w2 seat: the seat is clamped to 0..1"
	)
	local any: any = nil
	check(
		Shapes.SeatDrop(5, 1, any) == 0
			and Shapes.SeatDrop(5, 1, -0.1) == 0
			and Shapes.SeatDrop(5, 1, 0 / 0) == 0
			and Shapes.SeatDrop(5, 1, math.huge) == 0
			and Shapes.SeatDrop(0, 1, 0.35) == 0
			and Shapes.SeatDrop(5, 0 / 0, 0.35) == 0,
		"l4w2 seat: a restDrop missing, negative, NaN or infinite, a height of 0 or a NaN seat drops nothing"
	)
	check(
		near(Shapes.SeatStep(0, 1, 0.1, 0.5), 0.2, 1e-12)
			and near(Shapes.SeatStep(1, 0, 0.1, 0.5), 0.8, 1e-12),
		"l4w2 seat: a step moves dt / riseBlendSeconds, both ways"
	)
	check(
		Shapes.SeatStep(0.9, 1, 0.1, 0.5) == 1 and Shapes.SeatStep(0.1, 0, 0.1, 0.5) == 0,
		"l4w2 seat: never past the goal"
	)
	check(
		Shapes.SeatStep(0.3, 1, 0.1, 0) == 1
			and Shapes.SeatStep(0.3, 0, 0.1, any) == 0
			and Shapes.SeatStep(0.3, 1, 0.1, 0 / 0) == 1,
		"l4w2 seat: a pace of 0, missing or NaN reaches the goal at once"
	)
	check(
		Shapes.SeatStep(0.5, 0.5, 0.1, 0.5) == 0.5 and Shapes.SeatStep(0.4, 2, 10, 0.5) == 1,
		"l4w2 seat: at the goal it stays, and a goal past 1 is 1"
	)
	local restDrop = FIXTURES.proving.crowd.restDrop
	local feet = vec(0, 0, 0)
	local names = {}
	for name in FIXTURES.proving.crowd.kinds do
		table.insert(names, name)
	end
	table.sort(names)
	local held = true
	local failed = ""
	for _, name in names do
		local def = FIXTURES.proving.crowd.kinds[name]
		local h, r, hr = def.height, def.radius, def.headRadius
		local drop = Shapes.SeatDrop(h, 1, restDrop)
		local function ray(y: number, lower: number?): (number?, boolean)
			return Shapes.CrowdRay(vec(0, y, 40), vec(0, 0, -1), 100, 0, 0, feet, r, h, hr, lower)
		end
		local seated, seatedCrit = ray(h - hr - drop, drop)
		local _, oldCrit = ray(h - hr, drop)
		local standing, standingCrit = ray(h - hr, nil)
		local zero, zeroCrit = ray(h - hr, 0)
		local ok = seated ~= nil
			and seatedCrit
			and not oldCrit
			and standing ~= nil
			and standingCrit
			and zero == standing
			and zeroCrit
		if not ok then
			failed ..= ` {name}`
		end
		held = held and ok
	end
	check(
		held and restDrop ~= nil,
		`l4w2 seat: for every kind seated, a ray at the lowered head crits and one at the standing head does not; nil drop = 0 (failed:{failed})`
	)
	-- The fodder (5 tall, radius 1.3, head 0.7): standing, its capsule's cylinder runs 1.3 to 2.5 up;
	-- seated (drop 1.75) the capsule is the sphere at its foot (1.3 round 1.3 up) and the head's
	-- centre is 2.55 up. A ray at 2.0 up, 1.2 beside the axis, touches the standing cylinder and
	-- passes 1.39 from the foot sphere and 1.32 from the lowered head: the top came down too.
	local fodder = FIXTURES.proving.crowd.kinds.fodder
	local drop = Shapes.SeatDrop(fodder.height, 1, restDrop)
	local function beside(lower: number?): number?
		return (
			Shapes.CrowdRay(
				vec(1.2, 2, 40),
				vec(0, 0, -1),
				100,
				0,
				0,
				feet,
				fodder.radius,
				fodder.height,
				fodder.headRadius,
				lower
			)
		)
	end
	check(
		fodder.height == 5
			and fodder.radius == 1.3
			and fodder.headRadius == 0.7
			and beside(drop) == nil
			and beside(nil) ~= nil,
		"l4w2 seat: the seated fodder's capsule top comes down with its head (a ray beside its middle hits it standing, misses it seated)"
	)
end
L4W.group("seat shapes", L4W.seatShapeTests)

function L4W.realSeatKeysTests(): ()
	print(" ProvingGrounds.json: the seat's keys")
	local crowd = FIXTURES.proving.crowd
	check(
		type(crowd.restDrop) == "number" and crowd.restDrop >= 0 and crowd.restDrop < 1,
		`l4w2 seat: crowd.restDrop is a share of the height ({tostring(crowd.restDrop)})`
	)
	check(
		type(crowd.riseBlendSeconds) == "number"
			and crowd.riseBlendSeconds > 0
			and crowd.riseBlendSeconds < math.huge,
		`l4w2 seat: crowd.riseBlendSeconds is a pace above 0 ({tostring(crowd.riseBlendSeconds)})`
	)
end
L4W.group("seat keys", L4W.realSeatKeysTests)

-- CrowdService: each body's seat, stepped from its state as a client steps it from the wire.
function L4W.crowdSeatTests(): ()
	print(" CrowdService: the seat")
	config.crowd.restDrop = 0.35
	config.crowd.riseBlendSeconds = 0.5
	L1BC.campFloors()
	-- Wave 2's dormancy (120 studs from the floor), so the group below can go dormant.
	Crowd.SetCampRules(W2A.rules())
	-- 30 studs past the floor's south edge: not in play, outside the fire's sight (16) and well
	-- inside dormantRadius, so a woken group knows nobody and walks home.
	root.Position = vec(0, 11, 60)
	local fire = L1BC.def(
		"fire",
		{ vec(0, 8, 0) },
		{ radius = 4, units = { { kind = "fodder", count = 2 } } }
	)
	local _, ids = L1BC.place(fire, { "fodder", "fodder" })
	check(
		Crowd.Get(ids[1]).seat == 1 and Crowd.Get(ids[2]).seat == 1,
		"l4w2 seat: a body placed at a fire is seated before its first step"
	)
	local guard = L1BC.def(
		"guard",
		{ vec(10, 8, -20) },
		{ id = "A.guard", units = { { kind = "fodder", count = 1 } } }
	)
	local _, guards = L1BC.place(guard, { "fodder" })
	check(Crowd.Get(guards[1]).seat == 0, "l4w2 seat: a guard at rest stands (seat 0)")
	step2(6)
	check(
		Crowd.Get(ids[1]).seat == 1 and Crowd.Get(ids[1]).state == "rest",
		"l4w2 seat: resting, it stays seated"
	)
	Crowd.Damage(ids[1], 1, 0, nil, nil)
	local seats = {}
	for _ = 1, 12 do
		step2()
		table.insert(seats, Crowd.Get(ids[1]).seat)
	end
	local falling, steps, biggest = true, 0, 0
	local before = 1
	for _, seat in seats do
		falling = falling and seat <= before and seat >= 0
		biggest = math.max(biggest, before - seat)
		if seat > 0 then
			steps += 1
		end
		before = seat
	end
	local pace = (1 / 15) / 0.5
	check(
		falling and seats[#seats] == 0 and near(biggest, pace, 1e-6) and steps >= 6 and steps <= 8,
		`l4w2 seat: woken, it stands up at 1 / riseBlendSeconds a second (a step of {biggest}, {steps} steps above 0)`
	)
	L1BC.events()
	-- Home again with nobody near enough to keep it awake: a dormant body holds its goal at once.
	-- With the pace slowed to 1000 s a step moves it by a 15000th; a rest it reaches near the player
	-- (not dormant) barely moves it, and the step it goes dormant seats it whole.
	config.crowd.riseBlendSeconds = 1000
	local rested = false
	for _ = 1, 1200 do
		step2()
		if Crowd.Get(ids[1]).state == "rest" then
			rested = true
			break
		end
	end
	local nearSeat = Crowd.Get(ids[1]).seat
	check(
		rested and nearSeat < 0.01,
		`l4w2 seat: back at rest with a player within dormantRadius, it sits down at the pace (seat {nearSeat})`
	)
	root.Position = vec(0, 11, 400)
	step2()
	check(
		Crowd.Get(ids[1]).seat == 1,
		`l4w2 seat: the step it goes dormant (nobody within 120) it is seated whole ({Crowd.Get(
			ids[1]
		).seat})`
	)
	check(Crowd.Get(guards[1]).seat == 0, "l4w2 seat: a dormant guard stands")
	config.crowd.riseBlendSeconds = 0.5
end
L1BC.crowdGroup("l4w2 crowd seat", L4W.crowdSeatTests)

-- The Castle Key ----------------------------------------------------------------------------------------

function L4W.forestFile(): any?
	for _, candidate in FIXTURES.levels do
		if candidate.id == "forestRoad" then
			return candidate
		end
	end
	return nil
end

function L4W.keyValidateTests(): ()
	local Flow = L4W.Flow
	print(" StageFlow.Validate: a secret's key")
	local file = L4W.forestFile()
	if file == nil then
		check(false, "l4w2 key: Forest Road's level file is there")
		return
	end
	local layout = FIXTURES.layouts[file.layout]
	local ranks = {}
	for index, name in FIXTURES.expeditions.difficulties do
		ranks[name] = index
	end
	local function keyLines(key: any): number
		local level = Flow.Resolve(file, FIXTURES.combat.director.runCapSeconds)
		local secrets = table.clone(level.secrets)
		local entry = table.clone(secrets.mountain or { name = "Mountain Summit" })
		entry.key = key
		secrets.mountain = entry
		level.secrets = secrets
		local count = 0
		for _, problem in
			Flow.Validate(
				level,
				layout,
				FIXTURES.proving.crowd.kinds,
				ranks,
				FIXTURES.combat.levels,
				FIXTURES.proving.crowd.maxAlive
			)
		do
			if L4W.has(problem, "secrets.mountain.key") then
				count += 1
			end
		end
		return count
	end
	check(
		keyLines("castle") == 0 and keyLines(nil) == 0,
		"l4w2 key: a short key id, or none, is no problem"
	)
	check(
		keyLines("") == 1 and keyLines(5) == 1 and keyLines(true) == 1,
		"l4w2 key: an empty key, a number or a flag is one line each"
	)
	check(
		keyLines(string.rep("k", 24)) == 0 and keyLines(string.rep("k", 25)) == 1,
		"l4w2 key: held to the family id's cap (24 bytes fit, 25 do not)"
	)
	check(
		file.secrets ~= nil
			and file.secrets.mountain ~= nil
			and file.secrets.mountain.key == "castle",
		"l4w2 key: the shipped mountain gives the Castle Key"
	)
	local keys = FIXTURES.expeditions.keys
	check(
		keys ~= nil
			and keys.castle ~= nil
			and type(keys.castle.name) == "string"
			and keys.castle.name ~= "",
		"l4w2 key: Expeditions.json names it"
	)
end
L4W.group("key validate", L4W.keyValidateTests)

function L4W.keyFlowTests(): ()
	local Secrets, Unlocks = L4W.Secrets, L4W.Unlocks
	print(" SecretFlow and Unlocks: the Castle Key")
	local file = L4W.forestFile()
	if file == nil then
		check(false, "l4w2 key: Forest Road's level file is there")
		return
	end
	local layout = FIXTURES.layouts[file.layout]
	local sites = L1.Map.Sites(layout, file)
	local mountain, lookout = nil, nil
	for _, site in sites do
		if site.id == "mountain" then
			mountain = site
		elseif site.id == "lookout" then
			lookout = site
		end
	end
	check(
		mountain ~= nil and mountain.reward ~= nil and mountain.reward.key == "castle",
		"l4w2 key: the mountain's chest carries its key in its reward"
	)
	check(
		lookout ~= nil and lookout.reward ~= nil and lookout.reward.key == nil,
		"l4w2 key: a chest that gives none carries none"
	)
	if mountain == nil then
		return
	end
	local combat: any = { valor = 0, materials = {}, secrets = {}, families = {} }
	check(
		not Unlocks.HasLevelKey(combat, "castle", FIXTURES.levels),
		"l4w2 key: not held before the chest is opened"
	)
	local opening = Secrets.Open(combat, "forestRoad", mountain, true, "Timber")
	check(
		opening.verdict == "pay"
			and opening.key == "castle"
			and opening.valor == file.secrets.mountain.valor,
		`l4w2 key: opening it pays and names the key ({opening.verdict}, {tostring(opening.key)})`
	)
	check(
		Unlocks.HasLevelKey(combat, "castle", FIXTURES.levels),
		"l4w2 key: held once the secret is opened (nothing else written)"
	)
	local again = Secrets.Open(combat, "forestRoad", mountain, true, "Timber")
	check(
		again.verdict == "known" and again.key == nil,
		"l4w2 key: a second opening is known and gives nothing"
	)
	check(
		not Unlocks.HasLevelKey(combat, "crypt", FIXTURES.levels)
			and not Unlocks.HasLevelKey(combat, "", FIXTURES.levels)
			and not Unlocks.HasLevelKey(nil, "castle", FIXTURES.levels)
			and not Unlocks.HasLevelKey(combat, "castle", {}),
		"l4w2 key: a key no secret gives, an empty one, no profile, or no level files: not held"
	)
	local elsewhere: any = { secrets = { otherLevel = { mountain = true } } }
	check(
		not Unlocks.HasLevelKey(elsewhere, "castle", FIXTURES.levels),
		"l4w2 key: the same secret id opened in another level does not hold it"
	)
	local reset: any = { secrets = { forestRoad = { mountain = false } } }
	check(
		not Unlocks.HasLevelKey(reset, "castle", FIXTURES.levels),
		"l4w2 key: a secret recorded false does not hold it"
	)
	local found = L1.Map.SecretRow(sites, { mountain = true })
	local row, other = nil, nil
	for _, entry in found do
		if entry.id == "mountain" then
			row = entry
		elseif entry.id == "lookout" then
			other = entry
		end
	end
	check(
		row ~= nil and row.key == "castle" and row.found and other ~= nil and other.key == nil,
		"l4w2 key: the map row names the key of the chest that gives it"
	)
	-- A key-only chest still pays (L4 W2: `key` is a reward field).
	local keyOnly = { secrets = { mountain = { name = "Summit", key = "castle" } } }
	local only = nil
	for _, site in L1.Map.Sites(layout, keyOnly) do
		if site.id == "mountain" then
			only = site
		end
	end
	check(
		only ~= nil
			and only.reward ~= nil
			and only.reward.valor == 0
			and only.reward.materials == 0
			and only.reward.key == "castle"
			and Secrets.Decide(only, true, false) == "pay",
		"l4w2 key: a chest whose entry gives only a key is a reward entry and pays"
	)
end
L4W.group("key flow", L4W.keyFlowTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
