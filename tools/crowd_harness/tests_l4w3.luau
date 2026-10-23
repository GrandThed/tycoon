-- Cases for L4 W3, luau-engineer A's (docs/prompts/l4-w3-contract.md §2.1, §4.1, §5, §7): the pure
-- MapRules (Built, every answer of Startable and its order, the caps against the shipped files, and
-- the moved map and chest rules on a fixture), RunLines (Add's merge, order, cap, net and clip; every
-- drop rule of Read), Combat.EraCashMult and CombatCashMult (Ben's pick on the shipped Combat.json,
-- every degrade to 1), and the never-sold upcoming abilities (Unlocks reads `list` only). The hub's
-- ExpeditionService, which calls Startable and SendMap, cannot be loaded here. Appended by
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
	local bad = {
		L4W3.line({ kind = "loot" }),
		L4W3.line({ kind = 3 }),
		L4W3.line({ id = string.rep("i", 49) }),
		L4W3.line({ name = false }),
		L4W3.line({ material = 5 }),
		L4W3.line({ count = -1 }),
		L4W3.line({ cash = 0 / 0 }),
		L4W3.line({ materials = math.huge }),
		L4W3.line({ valor = "9" }),
	}
	local missing = L4W3.line()
	missing.id = nil
	table.insert(bad, missing)
	check(#Lines.Read(bad) == 0, `Read: every bad field drops its line ({#Lines.Read(bad)} kept of {#bad})`)
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
	check(named, "every shipped upcoming ability names a map node")
end

L4W3.group("built", L4W3.builtTests)
L4W3.group("startable", L4W3.startableTests)
L4W3.group("map state", L4W3.mapStateTests)
L4W3.group("chests", L4W3.chestTests)
L4W3.group("shipped map", L4W3.shippedTests)
L4W3.group("add", L4W3.addTests)
L4W3.group("read", L4W3.readTests)
L4W3.group("era", L4W3.eraTests)
L4W3.group("cash mult", L4W3.cashMultTests)
L4W3.group("upcoming", L4W3.upcomingTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
