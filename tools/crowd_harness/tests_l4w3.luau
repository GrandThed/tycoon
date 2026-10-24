-- Cases for L4 W3, luau-engineer A's (docs/prompts/l4-w3-contract.md §2.1, §4.1, §5, §7): the pure
-- MapRules (Built, every answer of Startable and its order, the caps against the shipped files, and
-- the moved map and chest rules on a fixture), RunLines (Add's merge, order, cap, net and clip; every
-- drop rule of Read), Combat.EraCashMult and CombatCashMult (Ben's pick on the shipped Combat.json,
-- every degrade to 1), and the never-sold upcoming abilities (Unlocks reads `list` only). The W3 fix
-- round adds F7 (RunLines.ReadSummary, the one reader of a whole run card), F8 (both halves of every
-- field rule of Read), F9 (MapRules.SecretRows, the one copy of the secret rows) and F13's
-- MapRules.FirstPick (moved from MapScreen); fix round 2 adds G3 (MapRules.Note, the one note rule
-- StageFlow.Notes and MapScreen ask). The hub's ExpeditionService, which calls Startable,
-- SecretRows and SendMap, and StudioBridge, which calls ReadSummary, cannot be loaded here: their
-- call lines are run_harness.py's text pins. Appended by
-- run_harness.py after the earlier case files, so every local of those is in scope (check, load,
-- FIXTURES). Everything hangs off the L4W3 table (the 200-local limit), and every group runs behind
-- L4W3.group, so a group that throws fails one check and the bundle goes on.

print("L4 W3: MapRules, RunLines, the era's cash factor and the upcoming abilities")

local L4W3: any = {
	Map = load("MapRules"),
	Lines = load("RunLines"),
	Combat = load("Combat"),
	Unlocks = load("Unlocks"),
	-- Ben's pick (docs/prompts/l4-w3-cash-study.md (c) at M = 3), by era.
	PICK = { 1, 670, 34000, 1400000 },
}

function L4W3.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `l4w3 group "{name}" threw: {tostring(problem)}`)
	end
end

-- A map of four nodes: the forest is open, the castle needs the forest's star, the arena two stars
-- in all, the dream names no level; a second forest node (needing the castle) comes after the first.
function L4W3.map(): any
	return {
		difficulties = { "normal", "hard", "brutal" },
		difficultyNames = { normal = "Normal", hard = "Hard", brutal = "Brutal" },
		nodes = {
			{ id = "forest", name = "Forest Road", kind = "level", level = "forestRoad" },
			{
				id = "castle",
				name = "The Castle",
				kind = "level",
				level = "castle",
				requires = { node = "forest" },
			},
			{ id = "arena", name = "Raider Arena", kind = "bonus", level = "arena", requires = { stars = 2 } },
			{ id = "dream", name = "Dream", kind = "level" },
			{
				id = "forestAgain",
				name = "Forest Again",
				kind = "level",
				level = "forestRoad",
				requires = { node = "castle" },
			},
		},
	}
end

-- A level file's difficulties: what Startable reads of it.
L4W3.FILE = { normal = { hpScale = 1 }, hard = { hpScale = 2 } }

-- MapRules --------------------------------------------------------------------------------------------

function L4W3.builtTests(): ()
	local Map = L4W3.Map
	local built = Map.Built({ "forestRoad", "castle" })
	check(built.forestRoad == true and built.castle == true, "Built: every level id is built")
	local count = 0
	for _ in built do
		count += 1
	end
	check(count == 2 and built.arena == nil, `Built: nothing else is ({count} entries)`)
	check(next(Map.Built({})) == nil, "Built: no level file, nothing built")
	check(
		Map.MAX_LEVEL_ID_LENGTH == 32 and Map.MAX_DIFFICULTY_LENGTH == 12,
		`the caps are 32 and 12 bytes ({Map.MAX_LEVEL_ID_LENGTH}, {Map.MAX_DIFFICULTY_LENGTH})`
	)
end

function L4W3.startableTests(): ()
	local Map = L4W3.Map
	local map = L4W3.map()
	local built = Map.Built({ "forestRoad", "castle", "arena" })
	local none = {}
	local function start(stars: any, levelId: string, difficulty: string, file: any?): string
		return Map.Startable(map, built, stars, levelId, difficulty, file)
	end
	check(start(none, "forestRoad", "normal", L4W3.FILE) == "ok", "Startable: an open node at a known difficulty is ok")
	check(start(none, "forestRoad", "hard", L4W3.FILE) == "ok", "and at the other difficulty its file has")
	check(start(none, "nowhere", "normal", L4W3.FILE) == "locked", "Startable: no node names the level: locked")
	check(start(none, "castle", "normal", L4W3.FILE) == "locked", "Startable: a node that needs another's star: locked")
	local forest = { forestRoad = { normal = true } }
	check(start(forest, "castle", "normal", L4W3.FILE) == "ok", "and ok once the leader holds that star")
	check(
		start(forest, "arena", "normal", L4W3.FILE) == "locked",
		"Startable: a node that needs two stars, one held: locked"
	)
	check(
		start({ forestRoad = { normal = true, hard = true } }, "arena", "normal", L4W3.FILE) == "ok",
		"and ok at two"
	)
	check(
		Map.Startable(map, Map.Built({ "forestRoad" }), forest, "castle", "normal", L4W3.FILE) == "locked",
		"Startable: a node whose level has no file is locked, whatever the stars"
	)
	check(
		start(none, "forestRoad", "normal", L4W3.FILE) == "ok",
		"Startable: the FIRST node naming the level is judged (a later one needing the castle does not lock it)"
	)
	check(
		start(none, "forestRoad", "nightmare", { nightmare = {} }) == "unavailable",
		"Startable: a difficulty the map does not rank: unavailable, even when the file has it"
	)
	check(
		start(none, "forestRoad", "brutal", L4W3.FILE) == "unavailable",
		"Startable: a difficulty the level file lacks: unavailable"
	)
	check(start(none, "forestRoad", "normal", nil) == "unavailable", "Startable: no level file: unavailable")
	check(
		start(none, "forestRoad", "normal", { normal = true }) == "unavailable",
		"Startable: a difficulty entry that is not a table: unavailable"
	)
	check(
		start(none, "castle", "nightmare", nil) == "locked",
		"Startable: locked is answered before unavailable"
	)
	-- Only the leader's stars are an argument; the node's open state reads them as the leader's.
	check(
		start({ castle = { normal = true } }, "castle", "normal", L4W3.FILE) == "locked",
		"Startable: a star of the level itself does not open its own node"
	)
end

function L4W3.mapStateTests(): ()
	local Map = L4W3.Map
	local map = L4W3.map()
	local built = Map.Built({ "forestRoad", "castle", "arena" })
	local own = { forestRoad = { hard = true, normal = true } }
	local rows = { castle = { { id = "chest", name = "Chest", needs = "fire", found = false } } }
	local state = Map.MapState(map, built, {}, own, 42, rows)
	check(state.kind == "map" and state.leaderUserId == 42, "MapState: kind map, the leader named")
	check(#state.nodes == 5 and state.nodes[1].id == "forest" and state.nodes[5].id == "forestAgain", "MapState: every node in the config's order")
	local forest, castle, arena, dream = state.nodes[1], state.nodes[2], state.nodes[3], state.nodes[4]
	check(forest.open and forest.reason == nil, "NodeState: the forest is open")
	check(
		#forest.stars == 2 and forest.stars[1] == "normal" and forest.stars[2] == "hard",
		"NodeState: the player's own stars, in the map's difficulty order"
	)
	check(
		not castle.open and castle.reason == "needsNode" and castle.needs == "Forest Road",
		`NodeState: the castle needs the forest by name, on the LEADER's stars ({castle.reason}, {castle.needs})`
	)
	check(castle.secrets ~= nil and castle.secrets[1].id == "chest", "NodeState: a locked node still carries its secret row")
	check(
		not arena.open and arena.reason == "needsStars" and arena.needs == "2",
		`NodeState: the arena needs 2 stars ({arena.reason}, {arena.needs})`
	)
	check(not dream.open and dream.reason == "notBuilt", "NodeState: a node with no level is notBuilt")
	check(Map.NodeState(map, built, {}, own, "nowhere") == nil, "NodeState: no such node is nil")
	local stars = {}
	check(Map.Award(stars, "forestRoad", "hard") == true, "Award: a new star is new")
	check(Map.Award(stars, "forestRoad", "hard") == false, "and the same star again is not")
	check(stars.forestRoad.hard == true, "Award: written into the stars")
end

function L4W3.chestTests(): ()
	local Map = L4W3.Map
	local layout = {
		secrets = {
			{ id = "lookout", needs = "doubleJump", x = 1, y = 10, z = 2, sx = 4, sy = 2, sz = 6 },
			{ id = "broken", needs = "fire", x = 0 / 0, y = 0, z = 0, sx = 1, sy = 1, sz = 1 },
			{ id = "summit", needs = "doubleJump", x = 5, y = 40, z = 5, sx = 2, sy = 2, sz = 2 },
		},
	}
	local file = {
		secrets = {
			lookout = { name = "The Lookout", valor = 5, materials = 20, family = "flamethrower" },
			summit = { key = "castle" },
		},
	}
	local sites = Map.Sites(layout, file)
	check(#sites == 2 and sites[1].id == "lookout" and sites[2].id == "summit", "Sites: in layout order, a broken one skipped")
	check(sites[1].floorY == 9 and sites[1].name == "The Lookout", "Sites: the floor is the block's bottom, the name the file's")
	check(
		sites[1].reward ~= nil and sites[1].reward.valor == 5 and sites[1].reward.family == "flamethrower",
		"Sites: the reward as the file has it"
	)
	check(sites[2].reward ~= nil and sites[2].reward.key == "castle" and sites[2].name == "summit", "Sites: a key-only chest pays, named by its id")
	local row = Map.SecretRow(sites, { summit = true })
	check(
		#row == 2 and row[1].found == false and row[2].found == true and row[2].key == "castle" and row[1].key == nil,
		"SecretRow: found from the player's own secrets, the key glyph named"
	)
	check(#Map.SecretRow(sites, nil)[1].name > 0, "SecretRow: no secrets found yet reads every chest unfound")
end

-- F9: SecretRows is SendMap's and WaveService's row assembly, through the caller's cached reader.
function L4W3.secretRowsTests(): ()
	local Map = L4W3.Map
	local forest = {
		{ id = "lookout", needs = "doubleJump", x = 0, z = 0, sx = 1, sz = 1, floorY = 0, name = "The Lookout" },
		{
			id = "summit",
			needs = "doubleJump",
			x = 0,
			z = 0,
			sx = 1,
			sz = 1,
			floorY = 0,
			name = "Summit",
			reward = { valor = 0, materials = 0, key = "castle" },
		},
	}
	local asked: { [string]: number } = {}
	local function sitesOf(levelId: string): any
		asked[levelId] = (asked[levelId] or 0) + 1
		return if levelId == "forestRoad" then forest else {}
	end
	local built = { forestRoad = true, castle = true }
	local rows = Map.SecretRows(built, sitesOf, { forestRoad = { summit = true }, castle = { gate = true } })
	local row = rows.forestRoad
	check(
		row ~= nil and #row == 2 and row[1].found == false and row[2].found == true and row[2].key == "castle",
		"SecretRows: a level's row is SecretRow of its sites against the player's own opened chests"
	)
	check(rows.castle == nil, "SecretRows: a built level with no chests carries no row (nil, not {})")
	local keys = 0
	for _ in rows do
		keys += 1
	end
	check(keys == 1, `SecretRows: only levels with chests have rows ({keys})`)
	check(
		asked.forestRoad == 1 and asked.castle == 1 and asked.arena == nil,
		"SecretRows: the caller's reader is asked once for each built level, and for nothing else"
	)
	local fresh = Map.SecretRows(built, sitesOf, nil)
	check(
		fresh.forestRoad ~= nil and fresh.forestRoad[1].found == false and fresh.forestRoad[2].found == false,
		"SecretRows: nothing opened yet reads every chest unfound"
	)
	local other = Map.SecretRows(built, sitesOf, { castle = { lookout = true } })
	check(
		other.forestRoad ~= nil and other.forestRoad[1].found == false,
		"SecretRows: a chest opened in another level is not this level's"
	)
	check(next(Map.SecretRows({}, sitesOf, nil)) == nil, "SecretRows: nothing built, no rows")
end

-- F13: FirstPick, moved verbatim from MapScreen (both hosts open the map on it).
function L4W3.pickNode(id: string, open: any, stars: any): any
	return { id = id, open = open, stars = stars }
end

function L4W3.firstPick(nodes: { any }): (string?, string?)
	return L4W3.Map.FirstPick({ "normal", "hard", "brutal" }, { kind = "map", leaderUserId = 1, nodes = nodes })
end

function L4W3.firstPickTests(): ()
	local node = L4W3.pickNode
	local id, difficulty = L4W3.firstPick({ node("forest", true, {}), node("castle", true, {}) })
	check(id == "forest" and difficulty == nil, "FirstPick: the first open node with no star, at no difficulty")
	id, difficulty = L4W3.firstPick({ node("forest", true, { "normal" }), node("castle", true, {}) })
	check(
		id == "castle" and difficulty == nil,
		`FirstPick: a later starless node beats an earlier starred one ({tostring(id)})`
	)
	id, difficulty = L4W3.firstPick({ node("closed", false, {}), node("forest", true, { "normal" }) })
	check(id == "forest" and difficulty == "hard", "FirstPick: a closed node is never picked; else the lowest uncleared")
	id, difficulty = L4W3.firstPick({ node("forest", true, { "hard" }), node("castle", true, { "normal" }) })
	check(
		id == "forest" and difficulty == "normal",
		`FirstPick: the first open node, at its lowest difficulty without a star ({tostring(difficulty)})`
	)
	id, difficulty = L4W3.firstPick({ node("forest", true, { "brutal", "normal", "hard" }) })
	check(id == "forest" and difficulty == nil, "FirstPick: every difficulty cleared reads the node at none")
	id, difficulty = L4W3.firstPick({ node("a", false, {}), node("b", false, { "normal" }) })
	check(id == nil and difficulty == nil, "FirstPick: no open node, no pick")
	id, difficulty = L4W3.firstPick({})
	check(id == nil and difficulty == nil, "FirstPick: no node at all, no pick")
	id, difficulty =
		L4W3.firstPick({ "junk", node("broken", true, "none"), node("half", "yes", {}), node("forest", true, {}) })
	check(
		id == "forest" and difficulty == nil,
		"FirstPick: a node that is not a table, or has no star list or a true open flag, is skipped"
	)
	-- A star list that is a string has a length: "" would read as starless, "none" as the fallback.
	id, difficulty = L4W3.firstPick({ node("blank", true, ""), node("forest", true, {}) })
	check(id == "forest" and difficulty == nil, "FirstPick: a string star list never reads as starless")
	id, difficulty = L4W3.firstPick({ node("broken", true, "none"), node("forest", true, { "normal" }) })
	check(id == "forest" and difficulty == "hard", "FirstPick: a string star list is never the fallback")
end

function L4W3.shippedTests(): ()
	local Map = L4W3.Map
	local expeditions = FIXTURES.expeditions
	local fits = true
	for _, difficulty in expeditions.difficulties do
		fits = fits and #difficulty > 0 and #difficulty <= Map.MAX_DIFFICULTY_LENGTH
	end
	check(fits, "every shipped difficulty fits RequestExpedition's cap")
	local idsFit, linesFit = true, true
	for _, level in FIXTURES.levels do
		idsFit = idsFit and #level.id > 0 and #level.id <= Map.MAX_LEVEL_ID_LENGTH
		for _, difficulty in expeditions.difficulties do
			linesFit = linesFit and #(level.id .. ":" .. difficulty) <= L4W3.Lines.MAX_TEXT
		end
	end
	check(idsFit, "every shipped level id fits RequestExpedition's cap")
	-- F7: a card's title is its level's name (a run) or the map's (the session), and ReadSummary drops
	-- a card whose title is not 1 to MAX_TEXT bytes, so no shipped name may fall outside that.
	local function titleFits(name: any): boolean
		return type(name) == "string" and #name > 0 and #name <= L4W3.Lines.MAX_TEXT
	end
	local titlesFit = titleFits(expeditions.name)
	for _, level in FIXTURES.levels do
		titlesFit = titlesFit and titleFits(level.name)
	end
	check(titlesFit, "every shipped level name and the map's name fit ReadSummary's title (1 to 48 bytes)")
	check(linesFit, "every first-clear line id (level:difficulty) fits RunLines.MAX_TEXT")
	-- The shipped map: Forest Road at Normal is startable on a fresh save, as the hub's Depart asks.
	local ids = {}
	for _, level in FIXTURES.levels do
		table.insert(ids, level.id)
	end
	local first = FIXTURES.levels[1]
	check(
		first ~= nil
			and Map.Startable(expeditions, Map.Built(ids), {}, first.id, expeditions.difficulties[1], first.difficulties)
				== "ok",
		"the shipped first level is startable at the first difficulty with no stars"
	)
end

-- Fix round 2's G3: the one note rule. A difficulty's note is shown only as a string of 1 to
-- MapRules.MAX_NOTE_LENGTH bytes (bytes, not characters); StageFlow.Notes and MapScreen both ask it.
function L4W3.noteTests(): ()
	local Map = L4W3.Map
	check(Map.MAX_NOTE_LENGTH == 24, "Note: the cap is 24 bytes, its one home MapRules.MAX_NOTE_LENGTH")
	check(Map.Note({ note = "Castle gear" }) == "Castle gear", "Note: a short note is shown as it is")
	local full = string.rep("x", 24)
	check(Map.Note({ note = full }) == full, "Note: 24 bytes is shown")
	check(Map.Note({ note = string.rep("x", 25) }) == nil, "Note: 25 bytes is dropped")
	-- "é" is two bytes in UTF-8: twelve of them fill the cap, thirteen (13 characters) do not fit.
	local twelve = string.rep("é", 12)
	check(#twelve == 24 and Map.Note({ note = twelve }) == twelve, "Note: 24 bytes of 12 characters is shown")
	check(Map.Note({ note = string.rep("é", 13) }) == nil, "Note: 26 bytes of 13 characters is dropped (bytes, m3)")
	for _, bad in { "", 7, true, {}, false } do
		check(Map.Note({ note = bad }) == nil, `Note: a {type(bad)} note "{tostring(bad)}" is dropped`)
	end
	check(Map.Note({ hpScale = 1 }) == nil, "Note: a difficulty with no note has none")
	check(Map.Note(nil) == nil, "Note: no difficulty has none")
	for _, odd in { "Castle gear", 3, true } do
		check(Map.Note(odd :: any) == nil, `Note: a {type(odd)} in place of the difficulty's table has none`)
	end
	-- The shipped Forest Road: every difficulty's note is one the map shows (check_levels refuses others).
	for _, level in FIXTURES.levels do
		for name, scales in level.difficulties do
			if type(scales) == "table" and scales.note ~= nil then
				check(
					Map.Note(scales) == scales.note,
					`Note: the shipped {level.id} {name} note "{tostring(scales.note)}" is shown`
				)
			end
		end
	end
end

-- RunLines --------------------------------------------------------------------------------------------

function L4W3.addTests(): ()
	local Lines = L4W3.Lines
	check(Lines.MAX == 16 and Lines.MAX_TEXT == 48, `the caps are 16 lines and 48 bytes ({Lines.MAX}, {Lines.MAX_TEXT})`)
	local lines = {}
	local raiders = { kind = "raiders", id = "raiders", name = "" }
	Lines.Add(lines, raiders, 1, 30, "Timber", 1, 0)
	Lines.Add(lines, { kind = "camp", id = "A", name = "Pickets" }, 1, 200, "Timber", 5, 0)
	Lines.Add(lines, raiders, 2, 60, "Timber", 2, 0)
	check(#lines == 2, `Add: a second credit of a source merges into its line ({#lines} lines)`)
	local first = lines[1]
	check(
		first.kind == "raiders" and first.count == 3 and first.cash == 90 and first.materials == 3 and first.valor == 0,
		`Add: the amounts add (count {first.count}, cash {first.cash}, materials {first.materials})`
	)
	check(lines[2].kind == "camp" and lines[2].name == "Pickets", "Add: lines keep first-credit order")
	Lines.Add(lines, { kind = "boss", id = "A", name = "Chief" }, 1, 500, "Timber", 10, 5)
	check(#lines == 3 and lines[3].kind == "boss", "Add: the same id under another kind is its own line")
	Lines.Add(lines, { kind = "camp", id = "A", name = "Renamed" }, 1, 1, "", 0, 0)
	check(lines[2].name == "Pickets" and lines[2].material == "Timber", "Add: a line keeps its first name and material")
	local keyed = {}
	Lines.Add(keyed, { kind = "key", id = "castle", name = "Castle Key" }, 0, 0, "", 0, 0)
	Lines.Add(keyed, { kind = "key", id = "castle", name = "Castle Key" }, 0, 0, "Timber", 0, 0)
	check(keyed[1].material == "Timber" and keyed[1].count == 0, "Add: an empty material takes the first non-empty one")
	Lines.Add(keyed, { kind = "key", id = "castle", name = "Castle Key" }, 0, 0, "Steel", 0, 0)
	check(keyed[1].material == "Timber", "Add: and a later material never replaces it")
	local net = {}
	Lines.Add(net, raiders, 0 / 0, -5, "Timber", math.huge, -math.huge)
	check(
		#net == 1 and net[1].count == 0 and net[1].cash == 0 and net[1].materials == 0 and net[1].valor == 0,
		"Add: an amount that is not finite and >= 0 adds 0"
	)
	local full = {}
	for index = 1, 20 do
		Lines.Add(full, { kind = "chest", id = `c{index}`, name = "" }, 1, index, "", 0, 0)
	end
	check(#full == 16 and full[16].id == "c16", `Add: no line past MAX ({#full})`)
	Lines.Add(full, { kind = "chest", id = "c3", name = "" }, 1, 100, "", 0, 0)
	check(full[3].cash == 103 and full[3].count == 2, "Add: a full list still merges into its lines")
	local long = {}
	local name = string.rep("n", 60)
	Lines.Add(long, { kind = "camp", id = string.rep("i", 50), name = name }, 1, 0, string.rep("m", 49), 0, 0)
	check(
		#long[1].id == 48 and #long[1].name == 48 and #long[1].material == 48,
		"Add: id, name and material are cut to MAX_TEXT bytes"
	)
	local accent = string.rep("a", 47) .. "\195\169" -- 47 ASCII bytes, then a two-byte character
	local cut = {}
	Lines.Add(cut, { kind = "camp", id = "x", name = accent }, 1, 0, "", 0, 0)
	check(cut[1].name == string.rep("a", 47), `Add: a cut never splits a character ({#cut[1].name} bytes)`)
	check(#Lines.Read(long) == 1 and #Lines.Read(cut) == 1, "Add: what it builds always passes Read")
end

function L4W3.line(overrides: any?): any
	local line: any = {
		kind = "camp",
		id = "A",
		name = "Pickets",
		count = 1,
		cash = 200,
		material = "Timber",
		materials = 5,
		valor = 0,
	}
	for key, value in overrides or {} do
		line[key] = value
	end
	return line
end

function L4W3.readTests(): ()
	local Lines = L4W3.Lines
	check(#Lines.Read(nil) == 0 and #Lines.Read("lines") == 0 and #Lines.Read(7) == 0, "Read: not a table reads as no lines")
	local good = L4W3.line()
	local read = Lines.Read({ good })
	check(#read == 1 and read[1].cash == 200 and read[1].name == "Pickets", "Read: a good line is kept")
	read[1].cash = 1
	check(good.cash == 200, "Read: a kept line is a copy, never the sender's table")
	-- F8: both halves of every field rule, one check each: the kind, each text's type and its
	-- 48-byte cap, and each amount's finiteness and its sign.
	local bad = {
		{ "kind not one of the seven", L4W3.line({ kind = "loot" }) },
		{ "kind not a string", L4W3.line({ kind = 3 }) },
		{ "id over 48 bytes", L4W3.line({ id = string.rep("i", 49) }) },
		{ "name not a string", L4W3.line({ name = false }) },
		{ "name over 48 bytes", L4W3.line({ name = string.rep("n", 49) }) },
		{ "material not a string", L4W3.line({ material = 5 }) },
		{ "material over 48 bytes", L4W3.line({ material = string.rep("m", 49) }) },
		{ "count negative", L4W3.line({ count = -1 }) },
		{ "count +inf", L4W3.line({ count = math.huge }) },
		{ "cash NaN", L4W3.line({ cash = 0 / 0 }) },
		{ "cash negative", L4W3.line({ cash = -1 }) },
		{ "materials +inf", L4W3.line({ materials = math.huge }) },
		{ "materials negative", L4W3.line({ materials = -1 }) },
		{ "valor not a number", L4W3.line({ valor = "9" }) },
		{ "valor negative", L4W3.line({ valor = -1 }) },
	}
	local missing = L4W3.line()
	missing.id = nil
	table.insert(bad, { "id missing", missing })
	for _, case in bad do
		check(#Lines.Read({ case[2] }) == 0, `Read: a line with its {case[1]} is dropped`)
	end
	local edge = L4W3.line({ id = string.rep("i", 48), name = string.rep("n", 48), material = string.rep("m", 48) })
	check(#Lines.Read({ edge }) == 1, "Read: texts of exactly 48 bytes are kept")
	check(
		#Lines.Read({ L4W3.line({ name = "", material = "", count = 0, cash = 0, materials = 0, valor = 0 }) }) == 1,
		"Read: empty names and zero amounts are lines"
	)
	local mixed = Lines.Read({ L4W3.line({ id = "A" }), "junk", L4W3.line({ kind = "loot" }), L4W3.line({ id = "C" }) })
	check(#mixed == 2 and mixed[1].id == "A" and mixed[2].id == "C", "Read: a bad entry is dropped, the rest kept in order")
	local holes: any = {}
	holes[1] = L4W3.line({ id = "A" })
	holes[3] = L4W3.line({ id = "C" })
	check(#Lines.Read(holes) == 2, "Read: a hole in the list skips nothing after it")
	local many = {}
	for index = 1, 20 do
		table.insert(many, L4W3.line({ id = `c{index}` }))
	end
	local capped = Lines.Read(many)
	check(#capped == 16 and capped[16].id == "c16", `Read: at most MAX lines, the first ones ({#capped})`)
	check(#Lines.Read({ a = L4W3.line() }) == 0, "Read: a keyed table is not a list")
	local kinds = { "raiders", "camp", "boss", "chest", "key", "firstClear", "mentor" }
	local all = {}
	for _, kind in kinds do
		table.insert(all, L4W3.line({ kind = kind, id = kind }))
	end
	check(#Lines.Read(all) == 7, "Read: all seven kinds are lines")
end

-- F7: a whole card as the combat place sends it (RunCredit.Empty's fields, a run's numbers).
function L4W3.summary(overrides: any?): any
	local summary: any = {
		title = "Forest Road",
		wavesCleared = 3,
		bestWave = 3,
		died = false,
		cash = 1250,
		materials = { Timber = 40 },
		valor = 12,
		kills = 57,
		seconds = 301,
		mentorValor = 2,
		damageShare = 0.5,
		lines = { L4W3.line() },
	}
	for key, value in overrides or {} do
		summary[key] = value
	end
	return summary
end

function L4W3.summaryTests(): ()
	local Lines = L4W3.Lines
	local sent = L4W3.summary()
	local read = Lines.ReadSummary(sent)
	check(
		read ~= nil
			and read.title == "Forest Road"
			and read.wavesCleared == 3
			and read.bestWave == 3
			and read.cash == 1250
			and read.valor == 12
			and read.kills == 57
			and read.seconds == 301
			and read.mentorValor == 2
			and read.damageShare == 0.5
			and read.died == false
			and read.materials.Timber == 40
			and #read.lines == 1,
		"ReadSummary: a sound card is read field for field"
	)
	-- The hub server reads a card, forwards it, and its client reads it again.
	local again = if read ~= nil then Lines.ReadSummary(read) else nil
	local same = again ~= nil and read ~= nil
	if again ~= nil and read ~= nil then
		for key, value in read do
			same = same and (type(value) == "table" or again[key] == value)
		end
		same = same and again.materials.Timber == 40 and #again.lines == 1 and again.lines[1].cash == 200
	end
	check(same, "ReadSummary: a card it answered reads again unchanged (the server's read, then the client's)")
	if read ~= nil then
		read.materials.Timber = 1
		read.lines[1].cash = 1
	end
	check(
		sent.materials.Timber == 40 and sent.lines[1].cash == 200,
		"ReadSummary: the materials and lines it answers are fresh copies"
	)
	check(
		Lines.ReadSummary(nil) == nil and Lines.ReadSummary("card") == nil and Lines.ReadSummary(5) == nil,
		"ReadSummary: not a table reads as none"
	)
	local died = Lines.ReadSummary(L4W3.summary({ died = true }))
	check(died ~= nil and died.died == true, "ReadSummary: died true is kept")
	local odd = Lines.ReadSummary(L4W3.summary({ died = "yes" }))
	check(odd ~= nil and odd.died == false, "ReadSummary: died that is not true reads false")
	-- An older combat build omits bestWave (C1), mentorValor and damageShare (C2), and lines (W3).
	local old = L4W3.summary()
	old.bestWave = nil
	old.mentorValor = nil
	old.damageShare = nil
	old.died = nil
	old.lines = nil
	local lenient = Lines.ReadSummary(old)
	check(
		lenient ~= nil
			and lenient.bestWave == 3
			and lenient.mentorValor == 0
			and lenient.damageShare == 0
			and lenient.died == false
			and #lenient.lines == 0,
		"ReadSummary: an absent optional field takes its default (bestWave = wavesCleared, 0, false, no lines)"
	)
	check(
		Lines.ReadSummary(L4W3.summary({ title = string.rep("t", 48) })) ~= nil,
		"ReadSummary: a title of exactly 48 bytes is kept"
	)
	local mixed = Lines.ReadSummary(L4W3.summary({ lines = { L4W3.line({ cash = -5 }), L4W3.line({ id = "B" }) } }))
	check(
		mixed ~= nil and #mixed.lines == 1 and mixed.lines[1].id == "B",
		"ReadSummary: a bad line costs that row only, through Read"
	)
	local cap = {}
	for index = 1, 16 do
		cap[`m{index}`] = index
	end
	check(Lines.ReadSummary(L4W3.summary({ materials = cap })) ~= nil, "ReadSummary: 16 kinds of material are kept")
	check(Lines.ReadSummary(L4W3.summary({ materials = {} })) ~= nil, "ReadSummary: no materials is a card")
	-- Any failure drops the whole card: one check per rule and half.
	local over = table.clone(cap)
	over.m17 = 17
	local nan, inf = 0 / 0, math.huge
	local dropped: { { any } } = {
		{ "title missing", { title = false } },
		{ "title not a string", { title = 7 } },
		{ "title empty", { title = "" } },
		{ "title of 49 bytes", { title = string.rep("t", 49) } },
		{ "wavesCleared NaN", { wavesCleared = nan } },
		{ "wavesCleared negative", { wavesCleared = -1 } },
		{ "wavesCleared fractional", { wavesCleared = 2.5 } },
		{ "wavesCleared a string", { wavesCleared = "3" } },
		{ "kills +inf", { kills = inf } },
		{ "kills negative", { kills = -1 } },
		{ "kills fractional", { kills = 0.5 } },
		{ "cash NaN", { cash = nan } },
		{ "cash +inf", { cash = inf } },
		{ "cash -inf", { cash = -inf } },
		{ "cash negative", { cash = -1 } },
		{ "valor NaN", { valor = nan } },
		{ "valor negative", { valor = -1 } },
		{ "valor +inf", { valor = inf } },
		{ "seconds +inf", { seconds = inf } },
		{ "seconds negative", { seconds = -1 } },
		{ "bestWave negative", { bestWave = -1 } },
		{ "bestWave fractional", { bestWave = 1.5 } },
		{ "bestWave NaN", { bestWave = nan } },
		{ "mentorValor negative", { mentorValor = -1 } },
		{ "mentorValor +inf", { mentorValor = inf } },
		{ "damageShare NaN", { damageShare = nan } },
		{ "damageShare negative", { damageShare = -0.5 } },
		{ "materials not a table", { materials = 40 } },
		{ "a material amount NaN", { materials = { Timber = nan } } },
		{ "a material amount negative", { materials = { Timber = -1 } } },
		{ "a material amount +inf", { materials = { Timber = inf } } },
		{ "a material amount a string", { materials = { Timber = "40" } } },
		{ "a material keyed by a number", { materials = { [1] = 40 } } },
		{ "a material named by an empty string", { materials = { [""] = 40 } } },
		{ "a material named in 49 bytes", { materials = { [string.rep("m", 49)] = 40 } } },
		{ "17 kinds of material", { materials = over } },
	}
	for _, case in dropped do
		check(Lines.ReadSummary(L4W3.summary(case[2])) == nil, `ReadSummary: a card with {case[1]} is dropped`)
	end
	for _, field in { "title", "wavesCleared", "kills", "cash", "valor", "seconds", "materials" } do
		local without = L4W3.summary()
		without[field] = nil
		check(Lines.ReadSummary(without) == nil, `ReadSummary: a card without {field} is dropped`)
	end
	-- What the combat place builds always passes: RunCredit's empty card and one credit on it.
	local Credit = load("RunCredit")
	local card = Credit.Empty("Forest Road")
	check(Lines.ReadSummary(card) ~= nil, "ReadSummary: the combat place's empty card passes")
	Credit.Credit(card, { kind = "camp", id = "A", name = "Pickets" }, 200, "Timber", 5, 1, 0)
	local credited = Lines.ReadSummary(card)
	check(
		credited ~= nil and credited.cash == 200 and credited.materials.Timber == 5 and #credited.lines == 1,
		"ReadSummary: and so does a credited one"
	)
end

-- Run cash by era -------------------------------------------------------------------------------------

function L4W3.eraTests(): ()
	local Combat = L4W3.Combat
	local rewards = { eraCashMult = L4W3.PICK }
	local exact = true
	for era, mult in L4W3.PICK do
		exact = exact and Combat.EraCashMult(rewards, era) == mult
	end
	check(exact, "EraCashMult: each era reads its own entry")
	check(Combat.EraCashMult(rewards, 5) == 1400000, "EraCashMult: an era past the list takes the last entry")
	check(Combat.EraCashMult(rewards, 2.7) == 670, "EraCashMult: a fractional era is floored")
	-- A list whose first entry is not 1, so "the first" and "1" differ.
	local raised = { eraCashMult = { 5, 9 } }
	check(
		Combat.EraCashMult(raised, 0) == 5 and Combat.EraCashMult(raised, -3) == 5,
		"EraCashMult: an era under 1 takes the first entry"
	)
	check(
		Combat.EraCashMult(raised, 0 / 0) == 1
			and Combat.EraCashMult(raised, math.huge) == 1
			and Combat.EraCashMult(raised, -math.huge) == 1,
		"EraCashMult: an era that is not a finite number reads 1, not an entry"
	)
	check(Combat.EraCashMult(nil, 3) == 1, "EraCashMult: no rewards block reads 1")
	check(Combat.EraCashMult({ eraCashMult = {} }, 3) == 1, "EraCashMult: an empty list reads 1")
	check(
		Combat.EraCashMult({ eraCashMult = "x" } :: any, 3) == 1
			and Combat.EraCashMult({ eraCashMult = 670 } :: any, 2) == 1
			and Combat.EraCashMult({ eraCashMult = true } :: any, 2) == 1,
		"EraCashMult: a list that is not a table reads 1"
	)
	check(Combat.EraCashMult({} :: any, 3) == 1, "EraCashMult: a block without the list reads 1")
	check(
		Combat.EraCashMult(rewards, 0 / 0) == 1 and Combat.EraCashMult(rewards, math.huge) == 1,
		"EraCashMult: an era that is not a finite number reads 1"
	)
	local function entry(value: any): number
		return Combat.EraCashMult({ eraCashMult = { 1, value, 9 } } :: any, 2)
	end
	check(
		entry(0.5) == 1 and entry(0 / 0) == 1 and entry(math.huge) == 1 and entry("670") == 1 and entry(-4) == 1,
		"EraCashMult: an entry that is not a finite number >= 1 reads 1"
	)
	check(entry(1) == 1 and entry(2.5) == 2.5, "EraCashMult: a sound entry is read as it is")
	check(Combat.EraCashMult({ eraCashMult = { 1, 0.5, 9 } } :: any, 3) == 9, "and a bad entry costs only its own era")
	-- The shipped Combat.json carries Ben's pick, and Village is exactly 1 (a new save keeps today's pay).
	local shipped = FIXTURES.combat.rewards
	local list = if shipped ~= nil then shipped.eraCashMult else nil
	local same = type(list) == "table" and #list == #L4W3.PICK
	if same then
		for era, mult in L4W3.PICK do
			same = same and list[era] == mult
		end
	end
	check(same, "the shipped rewards.eraCashMult is Ben's pick: 1, 670, 34,000, 1,400,000")
	check(Combat.EraCashMult(shipped, 1) == 1, "Village's factor is exactly 1 on the shipped file")
end

function L4W3.cashMultTests(): ()
	local Combat = L4W3.Combat
	local gameConfig = { legacy = { incomePerPoint = 0.01 } }
	local shop = { version = 1, perks = { { id = "founders", tiers = { { cost = 1, value = 1.5 } } } } }
	local owner = { legacy = 100, legacyShop = { spent = 1, perks = { founders = 1 } } }
	local rewards = { eraCashMult = L4W3.PICK }
	local base = Combat.CombatCashMult(owner, gameConfig, shop, nil, 3)
	check(math.abs(base - 3) < 1e-9, `CombatCashMult: Legacy x Founder's with no rewards block (x{base})`)
	local metro = Combat.CombatCashMult(owner, gameConfig, shop, rewards, 3)
	check(math.abs(metro - 102000) < 1e-6, `CombatCashMult: times the era's factor, Metropolis x34,000 (x{metro})`)
	check(
		math.abs(Combat.CombatCashMult(owner, gameConfig, shop, rewards, 1) - 3) < 1e-9,
		"CombatCashMult: Village pays as before"
	)
	-- The era is the caller's (the member's frozen cashEra), never read off the owner.
	local reborn: any = { legacy = 100, legacyShop = owner.legacyShop, era = 1 }
	check(
		math.abs(Combat.CombatCashMult(reborn, gameConfig, shop, rewards, 4) - 4200000) < 1e-3,
		"CombatCashMult: the era argument decides, not a field of the state"
	)
end

-- The upcoming abilities ------------------------------------------------------------------------------

function L4W3.upcomingTests(): ()
	local Unlocks = L4W3.Unlocks
	local config: any = {
		abilities = {
			list = {
				{ id = "doubleJump", name = "Double Jump", text = "Jump again.", price = { valor = 10 }, order = 1 },
			},
			upcoming = {
				{ id = "glide", name = "Glide", text = "Float down from any height.", with = "castle" },
			},
		},
	}
	check(Unlocks.Find(config, "glide") == nil, "an upcoming ability is never found to sell")
	local state: any = { combat = { valor = 100, abilities = {} } }
	local verdict = Unlocks.Apply(state, Unlocks.Find(config, "glide"), true)
	check(
		verdict == "invalid" and state.combat.valor == 100 and state.combat.abilities.glide == nil,
		`RequestBuyAbility("glide") is refused and takes nothing ({tostring(verdict)})`
	)
	local sold, problems = Unlocks.Sellable(config)
	check(#sold == 1 and sold[1].id == "doubleJump" and #problems == 0, "Sellable lists the list only, and says nothing of upcoming")
	check(
		Unlocks.HasKey({ glide = true }, config, "glide") == false,
		"an upcoming ability opens no secret, even written into a profile"
	)
	-- The shipped Expeditions.json: nothing upcoming is sold, each names a map node.
	local shipped = FIXTURES.expeditions
	local block = shipped.abilities
	local upcoming = if block ~= nil then block.upcoming else nil
	local nodes = {}
	for _, node in shipped.nodes do
		nodes[node.id] = true
	end
	local neverSold, named = true, true
	for _, def in upcoming or {} do
		neverSold = neverSold and Unlocks.Find(shipped, def.id) == nil
		named = named and nodes[def.with] == true
	end
	check(neverSold, "no shipped upcoming ability can be bought")
	check(
		named and upcoming ~= nil and #upcoming >= 1,
		"every shipped upcoming ability names a map node, and there is at least one (Glide, the card's next line)"
	)
end

L4W3.group("built", L4W3.builtTests)
L4W3.group("startable", L4W3.startableTests)
L4W3.group("map state", L4W3.mapStateTests)
L4W3.group("chests", L4W3.chestTests)
L4W3.group("secret rows", L4W3.secretRowsTests)
L4W3.group("first pick", L4W3.firstPickTests)
L4W3.group("shipped map", L4W3.shippedTests)
L4W3.group("note", L4W3.noteTests)
L4W3.group("add", L4W3.addTests)
L4W3.group("read", L4W3.readTests)
L4W3.group("summary", L4W3.summaryTests)
L4W3.group("era", L4W3.eraTests)
L4W3.group("cash mult", L4W3.cashMultTests)
L4W3.group("upcoming", L4W3.upcomingTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
