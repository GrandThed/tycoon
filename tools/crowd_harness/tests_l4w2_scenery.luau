-- Cases for the L4 W2 fix round, ui-engineer A's (docs/prompts/l4-w2-fix-round.md K7, K8; the
-- review's slice 2 s1): the pure ScenePlan that LevelScenery acts on. What the server's word means
-- on a client (Decide: nothing decided before the place has loaded, a nil answer never kept, every
-- refusal named), the build's order (Jobs), the local writes of each view (Show: a client that
-- cannot dress shows every hidden Part and every invisible wall), mood B's rule (Mood: never in the
-- lobby camp), the lobby camp's box (Box, InBox), the colours read from config (Rgb, WallColor);
-- then on the files as they ship (the forest's dress and its uploaded hash, the lobby and the
-- forest's layouts, Combat.json's boxMargin, Expeditions.json's wall look and moods), and against
-- the server's own reading (LevelDress.Accept refuses every file whose lists the client cannot
-- walk). LevelScenery itself (its Instances, the build's thread, the light) cannot load here: its
-- deciding lines are read as text by run_harness.py, and Studio is its test. Appended by
-- run_harness.py after the earlier case files, so every local of theirs is in scope (check, load,
-- FIXTURES). Everything hangs off the L4S table (the 200-local limit), and every group runs behind
-- L4S.group, so a group that throws fails one check and the bundle goes on.

print("L4 W2 fix round: the scenery's decisions (ScenePlan)")

local L4S: any = {
	Plan = load("ScenePlan"),
	Dress = load("LevelDress"),
	HASH = "plan-1",
	LAYOUT = "Test",
	VIEWS = { "forest", "grey", "walls" },
}

function L4S.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `l4w2 scenery group "{name}" threw: {tostring(problem)}`)
	end
end

function L4S.has(text: string?, part: string): boolean
	return type(text) == "string" and string.find(text, part, 1, true) ~= nil
end

-- A dress with its meshes out of group order (two unknown groups among them), three props (one
-- with `with`) and three effects (two fires, one smoke the client does not draw).
function L4S.dress(): any
	return {
		version = 1,
		level = "testLevel",
		layout = L4S.LAYOUT,
		planHash = L4S.HASH,
		frame = "level",
		meshes = {
			{ name = "Backdrop1", group = "backdrop" },
			{ name = "Odd1", group = "odd" },
			{ name = "Rock1", group = "rock" },
			{ name = "Ground1", group = "ground" },
			{ name = "Canopy1", group = "canopy" },
			{ name = "Ground2", group = "ground" },
			{ name = "Skin1", group = "skin" },
			{ name = "Odd2", group = "another" },
			{ name = "Camp1", group = "camp" },
			{ name = "Dress1", group = "dress" },
		},
		props = {
			{ piece = "Campfire", x = 1, y = 0, z = 2, yaw = 90, scale = 1 },
			{ piece = "Bramble", x = 3, y = 0, z = 4, yaw = 0, scale = 1.2, with = "CaveBramble" },
			{ piece = "SpawnTent", x = 5, y = 0, z = 6, yaw = 180, scale = 1 },
		},
		effects = {
			{ kind = "fire", x = 1, y = 1, z = 2 },
			{ kind = "smoke", x = 9, y = 1, z = 9 },
			{ kind = "fire", x = 7, y = 1, z = 8 },
		},
		barriers = {},
		hide = { blocks = {}, camps = {} },
		looks = {},
	}
end

-- A lookup that answers `file` for the dress's layout and counts what it was asked.
function L4S.lookup(file: any): (any, { string })
	local asked: { string } = {}
	return function(name: string): any
		table.insert(asked, name)
		return if file ~= nil and name == file.layout then file else nil
	end,
		asked
end

-- The names of `jobs`' meshes, props' pieces and effects' kinds, in order, as one line.
function L4S.order(jobs: { any }): string
	local out = {}
	for _, job in jobs do
		if job.kind == "mesh" then
			table.insert(out, job.mesh.name)
		elseif job.kind == "prop" then
			table.insert(out, "prop:" .. job.prop.piece)
		else
			table.insert(out, `{job.kind}:{job.effect.x}`)
		end
	end
	return table.concat(out, " ")
end

-- A layout block's or a camp's flat footprint.
function L4S.footprint(box: any): any
	return { x = box.x, z = box.z, hx = box.sx / 2, hz = box.sz / 2 }
end

-- Decide ------------------------------------------------------------------------------------------

function L4S.keyTests(): ()
	local Plan = L4S.Plan
	check(Plan.Key(nil, nil) == "" and Plan.Key(nil, "h") == "", "Key: no Dress is the empty key")
	check(Plan.Key(5, "h") == "", "Key: a Dress that is not a string is the empty key")
	check(
		Plan.Key("ForestRoad", "h") ~= Plan.Key("ForestRoad", nil),
		"Key: the hash's arrival changes the key (Dress without DressHash is read again)"
	)
	check(
		Plan.Key("ForestRoad", "a") ~= Plan.Key("ForestRoad", "b")
			and Plan.Key("ForestRoad", "a") ~= Plan.Key("Other", "a"),
		"Key: another hash or another layout is another key"
	)
	check(Plan.Key("ForestRoad", "a") == Plan.Key("ForestRoad", "a"), "Key: one word, one key")
end

function L4S.decideTests(): ()
	local Plan = L4S.Plan
	local file = L4S.dress()

	local lookup, asked = L4S.lookup(file)
	local none = Plan.Decide(nil, nil, true, lookup)
	check(none.action == "none" and none.keep == true, "Decide: no Dress is not dressed, kept")
	local loadingNone = Plan.Decide(nil, L4S.HASH, false, lookup)
	check(
		loadingNone.action == "none" and loadingNone.keep == true,
		"Decide: no Dress while loading is not dressed (nothing to wait for)"
	)
	check(#asked == 0, "Decide: no Dress asks for no dress file")

	-- The review's m3: a client that starts before the place has loaded must not judge the files.
	lookup, asked = L4S.lookup(file)
	local wait = Plan.Decide(L4S.LAYOUT, L4S.HASH, false, lookup)
	check(
		wait.action == "wait" and wait.keep == false,
		"Decide: before the place has loaded it waits, and the answer is not kept"
	)
	check(#asked == 0, "Decide: before the place has loaded the dress file is never looked up")
	local waitNoHash = Plan.Decide(L4S.LAYOUT, nil, false, lookup)
	check(waitNoHash.action == "wait", "Decide: before loading even a missing hash waits")

	lookup, asked = L4S.lookup(file)
	local noHash = Plan.Decide(L4S.LAYOUT, nil, true, lookup)
	check(
		noHash.action == "fail" and noHash.keep == false and L4S.has(noHash.reason, "DressHash"),
		"Decide: Dress without DressHash fails (nothing stays invisible), not kept"
	)
	check(#asked == 0, "Decide: without a hash the file is not looked up")
	local numberHash = Plan.Decide(L4S.LAYOUT, 5, true, lookup)
	check(numberHash.action == "fail", "Decide: a DressHash that is not a string fails")

	lookup, asked = L4S.lookup(nil)
	local missing = Plan.Decide(L4S.LAYOUT, L4S.HASH, true, lookup)
	check(
		missing.action == "fail"
			and missing.keep == false
			and L4S.has(missing.reason, "missing")
			and missing.dress == nil,
		"Decide: a missing dress file fails and the nil answer is never kept"
	)
	check(#asked == 1 and asked[1] == L4S.LAYOUT, "Decide: the file is looked up by the Dress name")

	lookup = L4S.lookup(file)
	local otherHash = Plan.Decide(L4S.LAYOUT, "plan-2", true, lookup)
	check(
		otherHash.action == "fail"
			and otherHash.keep == true
			and L4S.has(otherHash.reason, "plan-1")
			and L4S.has(otherHash.reason, "plan-2"),
		"Decide: another plan hash fails, kept, naming both hashes"
	)

	local turned = L4S.dress()
	turned.frame = "kit"
	local otherFrame = Plan.Decide(L4S.LAYOUT, L4S.HASH, true, L4S.lookup(turned))
	check(
		otherFrame.action == "fail"
			and otherFrame.keep == true
			and L4S.has(otherFrame.reason, "kit"),
		'Decide: a frame other than "level" fails, kept'
	)
	local both = L4S.dress()
	both.frame = "kit"
	both.planHash = "plan-9"
	local bothWrong = Plan.Decide(L4S.LAYOUT, L4S.HASH, true, L4S.lookup(both))
	check(L4S.has(bothWrong.reason, "plan-9"), "Decide: the hash is judged before the frame")

	for _, field in { "meshes", "props", "effects" } do
		for _, bad in { 5, "x", false } do
			local broken = L4S.dress()
			broken[field] = bad
			local answer = Plan.Decide(L4S.LAYOUT, L4S.HASH, true, L4S.lookup(broken))
			check(
				answer.action == "fail" and answer.keep == true and L4S.has(answer.reason, field),
				`Decide: {field} = {tostring(bad)} fails, naming {field}`
			)
		end
		local absent = L4S.dress()
		absent[field] = nil
		local answer = Plan.Decide(L4S.LAYOUT, L4S.HASH, true, L4S.lookup(absent))
		check(answer.action == "fail", `Decide: a dress with no {field} fails (the review's m1)`)
	end

	local build = Plan.Decide(L4S.LAYOUT, L4S.HASH, true, L4S.lookup(file))
	check(
		build.action == "build"
			and build.keep == true
			and build.dress == file
			and build.reason == nil,
		"Decide: the right hash, frame and lists build the client's own file, kept"
	)
	local empty = L4S.dress()
	empty.props = {}
	empty.effects = {}
	check(
		Plan.Decide(L4S.LAYOUT, L4S.HASH, true, L4S.lookup(empty)).action == "build",
		"Decide: empty props and effects lists still build"
	)
end

-- Jobs --------------------------------------------------------------------------------------------

function L4S.jobsTests(): ()
	local Plan = L4S.Plan
	check(
		table.concat(Plan.GROUP_ORDER, " ") == "ground skin camp rock canopy dress backdrop",
		"Jobs: the groups over hidden collision (ground, skin, camp, rock) come first"
	)
	local file = L4S.dress()
	local before = {}
	for _, mesh in file.meshes do
		table.insert(before, mesh.name)
	end
	local jobs = Plan.Jobs(file, false)
	check(
		L4S.order(jobs)
			== "Ground1 Ground2 Skin1 Camp1 Rock1 Canopy1 Dress1 Backdrop1 Odd1 Odd2 prop:Campfire prop:Bramble prop:SpawnTent fire:1 fire:7",
		"Jobs: meshes by group (the file's order inside a group, unknown groups last), props, fires"
	)
	local after = {}
	for _, mesh in file.meshes do
		table.insert(after, mesh.name)
	end
	check(
		table.concat(before, " ") == table.concat(after, " "),
		"Jobs: the dress's own list is not reordered"
	)
	local kinds = { mesh = 0, prop = 0, fire = 0 }
	for _, job in jobs do
		kinds[job.kind] += 1
	end
	check(
		kinds.mesh == 10 and kinds.prop == 3 and kinds.fire == 2,
		"Jobs: every mesh and prop, only the fires"
	)
	local low = Plan.Jobs(file, true)
	check(
		L4S.order(low)
			== "Ground1 Ground2 Skin1 Camp1 Rock1 Canopy1 Dress1 Backdrop1 Odd1 Odd2 prop:Campfire prop:Bramble prop:SpawnTent",
		"Jobs: a low-end device builds every mesh and prop and no fire (L4W2-15)"
	)
	local bare = L4S.dress()
	bare.props = {}
	bare.effects = {}
	check(#Plan.Jobs(bare, false) == 10, "Jobs: a dress without props or effects builds its meshes")
end

-- Show --------------------------------------------------------------------------------------------

function L4S.showTests(): ()
	local Plan = L4S.Plan
	for _, view in L4S.VIEWS do
		for _, dressed in { true, false } do
			local show = Plan.Show(dressed, true, view)
			check(
				show.folder == false and show.skinned == true and show.walls == "grey",
				`Show: a failed client (dressed {dressed}, view {view}) shows the hidden Parts and draws the walls grey, no scenery`
			)
			local plain = Plan.Show(false, false, view)
			check(
				plain.folder == false and plain.skinned == false and plain.walls == "none",
				`Show: not dressed (view {view}) writes nothing on the server's Parts`
			)
		end
	end
	local forest = Plan.Show(true, false, "forest")
	check(
		forest.folder and not forest.skinned and forest.walls == "none",
		"Show: the forest view shows the scenery and nothing else"
	)
	local grey = Plan.Show(true, false, "grey")
	check(
		not grey.folder and grey.skinned and grey.walls == "grey",
		"Show: Studio's grey view is what a failed client sees (blocks shown, walls drawn grey)"
	)
	local walls = Plan.Show(true, false, "walls")
	check(
		walls.folder and not walls.skinned and walls.walls == "debug",
		"Show: the walls view shows the scenery and the walls in red"
	)
	-- K7's rule in one line: whenever the server's hidden Parts are not covered by the scenery,
	-- they are shown, and so is every invisible wall.
	local holds = true
	for _, view in L4S.VIEWS do
		for _, dressed in { true, false } do
			for _, failed in { true, false } do
				local show = Plan.Show(dressed, failed, view)
				if (dressed or failed) and not show.folder then
					holds = holds and show.skinned and show.walls ~= "none"
				end
			end
		end
	end
	check(holds, "Show: no view hides the scenery and leaves a hidden Part or a wall invisible")
end

-- Mood --------------------------------------------------------------------------------------------

function L4S.moodTests(): ()
	local Plan = L4S.Plan
	local on = 0
	for _, dressed in { true, false } do
		for _, failed in { true, false } do
			for _, wanted in { true, false } do
				for _, inLobby in { true, false } do
					if Plan.Mood(dressed, failed, wanted, inLobby) then
						on += 1
					end
				end
			end
		end
	end
	check(
		on == 1 and Plan.Mood(true, false, true, false),
		"Mood: on only when dressed, not failed, wanted and not in the lobby camp"
	)
	check(
		not Plan.Mood(true, false, true, true),
		"Mood: a member waiting in the lobby camp during a run keeps the lobby's light (K8)"
	)
	check(not Plan.Mood(true, true, true, false), "Mood: a failed client keeps the default light")
	check(not Plan.Mood(true, false, false, false), "Mood: Studio's O turns it off")
end

-- Box and InBox -----------------------------------------------------------------------------------

function L4S.boxTests(): ()
	local Plan = L4S.Plan
	check(Plan.Box({}) == nil, "Box: no Parts, no box")
	check(not Plan.InBox(nil, 0, 0, 1000), "InBox: no box holds nothing, whatever the margin")
	local box = Plan.Box({
		{ x = 0, z = 0, hx = 2, hz = 3 },
		{ x = 10, z = -5, hx = 1, hz = 1 },
	})
	check(
		box ~= nil and box.minX == -2 and box.maxX == 11 and box.minZ == -6 and box.maxZ == 3,
		"Box: the flat box round every footprint"
	)
	check(Plan.InBox(box, 0, 0, 0) and Plan.InBox(box, 11, 3, 0), "InBox: inside and on the edge")
	check(
		not Plan.InBox(box, 11.01, 0, 0) and not Plan.InBox(box, 0, -6.01, 0),
		"InBox: just past an edge is out"
	)
	-- The box is x -2..11, z -6..3; a margin of 4 makes it x -6..15, z -10..7, each side alone.
	local sides = {
		{ x = -6, z = 0, out = -6.01, axis = "x" },
		{ x = 15, z = 0, out = 15.01, axis = "x" },
		{ x = 0, z = -10, out = -10.01, axis = "z" },
		{ x = 0, z = 7, out = 7.01, axis = "z" },
	}
	local grows = true
	for _, side in sides do
		local outX = if side.axis == "x" then side.out else side.x
		local outZ = if side.axis == "z" then side.out else side.z
		grows = grows and Plan.InBox(box, side.x, side.z, 4) and not Plan.InBox(box, outX, outZ, 4)
	end
	check(grows, "InBox: the margin grows every side")
end

-- Rgb and WallColor --------------------------------------------------------------------------------

function L4S.colorTests(): ()
	local Plan = L4S.Plan
	local source = { 84, 86, 92 }
	local rgb = Plan.Rgb(source)
	check(
		rgb ~= nil and rgb ~= source and rgb[1] == 84 and rgb[2] == 86 and rgb[3] == 92,
		"Rgb: a triple 0-255 is read (a copy)"
	)
	check(Plan.Rgb({ 0, 255, 0 }) ~= nil, "Rgb: 0 and 255 are colours")
	local bad = {
		{ 1, 2 },
		{ 1, 2, 3, 4 },
		{ 1, "2", 3 },
		{ 0 / 0, 1, 2 },
		{ -1, 0, 0 },
		{ 0, 256, 0 },
		"x",
		5,
	}
	local refused = 0
	for _, value in bad do
		if Plan.Rgb(value) == nil then
			refused += 1
		end
	end
	check(refused == #bad, "Rgb: a short, long, non-number, NaN or out-of-range triple is refused")
	local wall = Plan.WallColor({ wall = { material = "SmoothPlastic", color = { 84, 86, 92 } } })
	check(wall ~= nil and wall[3] == 92, "WallColor: the grey level's wall look")
	check(
		Plan.WallColor({ ground = { color = { 1, 2, 3 } } }) == nil
			and Plan.WallColor(nil) == nil
			and Plan.WallColor({ wall = { color = { 1, 2 } } }) == nil,
		"WallColor: no wall look (or a bad one) leaves the wall its own colour"
	)
end

-- Against the server ------------------------------------------------------------------------------

-- K7, the review's "the server and the client degrade the same way": every file whose lists the
-- client cannot walk is one the server refuses, so no client fails a word the server gave on that
-- ground; and the file both read as good is accepted and built.
function L4S.serverTests(): ()
	local Plan = L4S.Plan
	local function accepts(file: any): boolean
		local have = {}
		for _, mesh in if type(file.meshes) == "table" then file.meshes else {} do
			if type(mesh) == "table" and type(mesh.name) == "string" then
				have[mesh.name] = true
			end
		end
		local accepted = L4S.Dress.Accept(file, L4S.HASH, have, {}, nil, true, 600, L4S.LAYOUT)
		return accepted ~= nil
	end
	local good = L4S.dress()
	check(
		accepts(good)
			and Plan.Decide(L4S.LAYOUT, L4S.HASH, true, L4S.lookup(good)).action == "build",
		"server: the file the server accepts the client builds"
	)
	for _, field in { "meshes", "props", "effects" } do
		local broken = L4S.dress()
		broken[field] = 5
		check(
			not accepts(broken)
				and Plan.Decide(L4S.LAYOUT, L4S.HASH, true, L4S.lookup(broken)).action == "fail",
			`server: {field} that is not a list is refused on both sides`
		)
	end
end

-- The files as they ship --------------------------------------------------------------------------

function L4S.shippedTests(): ()
	local Plan = L4S.Plan
	local dresses = FIXTURES.levelDress or {}
	local count = 0
	for name, file in dresses do
		count += 1
		local hash = FIXTURES.levelHashes[name]
		check(type(hash) == "string", `shipped {name}: Assets.json records its plan hash`)
		local answer = Plan.Decide(name, hash, true, function(asked: string): any
			return dresses[asked]
		end)
		check(
			answer.action == "build" and answer.dress == file,
			`shipped {name}: the server's word builds it`
		)
		local refused = Plan.Decide(name, "0000000000000000", true, function(asked: string): any
			return dresses[asked]
		end)
		check(refused.action == "fail", `shipped {name}: another plan hash is grey`)
		local fires = 0
		for _, effect in file.effects do
			if effect.kind == Plan.FIRE then
				fires += 1
			end
		end
		local jobs = Plan.Jobs(file, false)
		check(
			#jobs == #file.meshes + #file.props + fires
				and #Plan.Jobs(file, true) == #file.meshes + #file.props,
			`shipped {name}: {#file.meshes} meshes, {#file.props} props and {fires} fires ({fires} fewer on a low-end device)`
		)
		local firstGroup = jobs[1] and jobs[1].mesh and jobs[1].mesh.group
		check(firstGroup == Plan.GROUP_ORDER[1], `shipped {name}: the build starts with its ground`)
		local moods = FIXTURES.expeditions.moods or {}
		check(
			type(moods[file.level]) == "table",
			`shipped {name}: Expeditions.json has a mood for its level "{file.level}"`
		)

		-- K8 on the shipped places: the lobby camp's box, grown by the server's margin, holds every
		-- lobby point and nothing of the level (its blocks, camps, walls and props).
		local lobbyLayout = FIXTURES.layouts[FIXTURES.expeditions.lobby.layout]
		local levelLayout = FIXTURES.layouts[file.layout]
		local margin = FIXTURES.combat.levels.boxMargin
		local feet = {}
		for _, block in lobbyLayout.blocks do
			table.insert(feet, L4S.footprint(block))
		end
		local box = Plan.Box(feet)
		local lobbyPoints = { lobbyLayout.start }
		for _, point in lobbyLayout.spawns or {} do
			table.insert(lobbyPoints, point)
		end
		local inside = box ~= nil
		for _, point in lobbyPoints do
			inside = inside and Plan.InBox(box, point.x, point.z, margin)
		end
		check(
			inside,
			`shipped {name}: every lobby point is in the lobby camp's box (the mood is off there)`
		)
		local outside = Plan.InBox(box, levelLayout.start.x, levelLayout.start.z, margin) == false
		local function clear(item: any): ()
			local hx, hz = (item.sx or 0) / 2, (item.sz or 0) / 2
			for _, corner in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
				if Plan.InBox(box, item.x + corner[1] * hx, item.z + corner[2] * hz, margin) then
					outside = false
				end
			end
		end
		for _, block in levelLayout.blocks do
			clear(block)
		end
		for _, camp in levelLayout.camps or {} do
			clear(camp)
		end
		for _, wall in file.barriers do
			clear(wall)
		end
		for _, prop in file.props do
			clear(prop)
		end
		check(
			outside,
			`shipped {name}: nothing of the level stands in the lobby camp's box (the mood is on there)`
		)
	end
	check(count >= 1, "shipped: at least one level is dressed")
	local wall = Plan.WallColor(FIXTURES.expeditions.looks)
	local look = FIXTURES.expeditions.looks.wall
	check(
		wall ~= nil
			and wall[1] == look.color[1]
			and wall[2] == look.color[2]
			and wall[3] == look.color[3],
		"shipped: a failed client draws the walls in Expeditions.json's wall look"
	)
	check(
		type(FIXTURES.combat.levels.boxMargin) == "number",
		"shipped: Combat.json levels.boxMargin is a number"
	)
end

L4S.group("key", L4S.keyTests)
L4S.group("decide", L4S.decideTests)
L4S.group("jobs", L4S.jobsTests)
L4S.group("show", L4S.showTests)
L4S.group("mood", L4S.moodTests)
L4S.group("box", L4S.boxTests)
L4S.group("color", L4S.colorTests)
L4S.group("server", L4S.serverTests)
L4S.group("shipped", L4S.shippedTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
