-- Cases for the L4 W3 fix round's F13 and F15 (docs/prompts/l4-w3-fix-round.md; ui-engineer B's):
-- the pure TallyRules the tally card's two hosts and the dungeon lobby act on. The card's rows,
-- totals, wallet and Valor's purpose (with slice 3 s4: a malformed `abilities.upcoming` entry is
-- left out, never thrown on), how many icons fly, which RunState `result` a card may be built from
-- (F15), RunState.depart off the wire, the lobby's notice line, and what each RunState does to the
-- lobby's map (the review's m3 p1 and p2: the `picked` once-per-arrival guard and the hold), on
-- a map written here and on the files as they ship. The hosts (RunTally, TallyHost,
-- CombatUIController) need Instances and cannot load here: run_harness.py reads their call lines
-- as text (the designer's pins). Appended by run_harness.py after the earlier case files, so every
-- local of those is in scope (check, load, FIXTURES). Everything hangs off the L4W3T table (the
-- 200-local limit), and every group runs behind L4W3T.group, so a group that throws fails one
-- check and the bundle goes on.

print("L4 W3 fix round: the tally card's and the lobby's rules (TallyRules)")

local L4W3T: any = {}
function L4W3T.load(name: string): any
	local ok, loaded = pcall(load, name)
	if not ok then
		check(false, `l4w3 tally: run_harness.py SOURCES has no {name} ({tostring(loaded)})`)
		return nil
	end
	return loaded
end
L4W3T = {
	load = L4W3T.load,
	Rules = L4W3T.load("TallyRules"),
	Format = L4W3T.load("Format"),
	NAN = 0 / 0,
	COUNTS = { coins = 14, coinsLowEnd = 5, logs = 8, logsLowEnd = 4 },
	FRESH = { holding = false, picked = "" },
}

function L4W3T.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `l4w3 tally: {name} stopped: {tostring(problem)}`)
	end
end

-- A map written here: every article a node name can start with, a word that only starts like
-- one, two nodes that name one level (the first is the one the map selects), one ability on sale
-- and one coming.
function L4W3T.map(): any
	return {
		version = 1,
		name = "Expeditions",
		difficulties = { "normal", "hard", "brutal" },
		difficultyNames = { normal = "Normal", hard = "Hard", brutal = "Brutal" },
		nodes = {
			{ id = "road", name = "Forest Road", kind = "level", level = "forestRoad" },
			{ id = "castle", name = "Castle", kind = "level" },
			{ id = "planet", name = "Another Planet", kind = "level" },
			{ id = "dream", name = "The Dream", kind = "level" },
			{ id = "inn", name = "An Inn", kind = "bonus" },
			{ id = "pass", name = "A Pass", kind = "bonus" },
			{ id = "theatre", name = "Theatre", kind = "bonus" },
			{ id = "arena", name = "Raider Arena", kind = "bonus", level = "forestRoad" },
		},
		abilities = {
			list = {
				{
					id = "doubleJump",
					name = "Double Jump",
					text = "A second jump in the air.",
					price = { valor = 10 },
					order = 1,
				},
			},
			upcoming = {
				{ id = "glide", name = "Glide", text = "Float down from any height.", with = "castle" },
			},
		},
	}
end

function L4W3T.line(kind: string, id: string, name: string, count: number?): any
	return {
		kind = kind,
		id = id,
		name = name,
		count = count or 1,
		cash = 120,
		material = "Timber",
		materials = 7,
		valor = 2,
	}
end

function L4W3T.result(over: { [string]: any }?): any
	local result: any = {
		levelId = "forestRoad",
		levelName = "Forest Road",
		difficulty = "normal",
		reason = "cleared",
		campsCleared = 3,
		camps = 3,
		star = true,
	}
	for key, value in over or {} do
		result[key] = if value == L4W3T.NONE then nil else value
	end
	return result
end
-- A value that takes a key away in `over` (nil cannot be written into a table).
L4W3T.NONE = {}

function L4W3T.depart(state: string, levelId: string?, difficulty: string?, left: number?): any
	return {
		levelId = levelId or "forestRoad",
		difficulty = difficulty or "normal",
		state = state,
		startsIn = if state == "counting" then left else nil,
		waitIn = if state == "waiting" then left else nil,
	}
end

L4W3T.group("rows", function()
	print(" Rows: the words of each kind of line")
	local Rules = L4W3T.Rules
	local map = L4W3T.map()
	local function label(line: any, expeditions: any?): string
		local rows = Rules.Rows({ line }, if expeditions == false then nil else expeditions or map)
		return rows[1].label
	end
	check(label(L4W3T.line("raiders", "raiders", "", 112)) == "Raiders ×112", "raiders: \"Raiders ×112\"")
	check(label(L4W3T.line("raiders", "raiders", "", 1500)) == "Raiders ×1.5K", "raiders: the count through Format.Cash")
	check(label(L4W3T.line("raiders", "raiders", "", 0)) == "Raiders", "raiders with no count: no ×")
	check(label(L4W3T.line("raiders", "raiders", "Bandits", 3)) == "Bandits ×3", "raiders: a name the server sends is kept")
	check(label(L4W3T.line("camp", "pickets", "Pickets")) == "Pickets bonus", "camp: \"Pickets bonus\"")
	check(label(L4W3T.line("camp", "pickets", "")) == "Camp bonus", "camp with no name: \"Camp bonus\"")
	check(label(L4W3T.line("boss", "chief", "The Camp Chief")) == "The Camp Chief", "boss: its name")
	check(label(L4W3T.line("boss", "chief", "")) == "The boss", "boss with no name: \"The boss\"")
	check(label(L4W3T.line("chest", "lookout", "The Lookout")) == "The Lookout", "chest: its name")
	check(label(L4W3T.line("chest", "lookout", "")) == "A chest", "chest with no name: \"A chest\"")
	check(label(L4W3T.line("key", "castle", "Castle Key")) == "Castle Key found", "key: \"Castle Key found\"")
	check(label(L4W3T.line("key", "castle", "")) == "A key found", "key with no name: \"A key found\"")
	check(label(L4W3T.line("firstClear", "forestRoad:hard", "")) == "First Hard clear", "first clear: the map's difficulty name")
	check(label(L4W3T.line("firstClear", "forestRoad:odd", "")) == "First odd clear", "first clear of a difficulty the map does not name: its id")
	check(label(L4W3T.line("firstClear", "forestRoad:hard", ""), false) == "First hard clear", "first clear with no Expeditions config: the id")
	check(label(L4W3T.line("mentor", "mentor", "anything")) == "Mentor bonus", "mentor: always \"Mentor bonus\"")
	check(label(L4W3T.line("odd" :: any, "x", "")) == "odd" and label(L4W3T.line("odd" :: any, "x", "Named")) == "Named", "an unknown kind: its name, else the kind (never a throw)")
	local rows = Rules.Rows({
		L4W3T.line("camp", "pickets", "Pickets"),
		L4W3T.line("raiders", "raiders", "", 9),
	}, map)
	local first = rows[1]
	check(
		#rows == 2
			and first.kind == "camp"
			and rows[2].kind == "raiders"
			and first.cash == 120
			and first.material == "Timber"
			and first.materials == 7
			and first.valor == 2,
		"rows keep the lines' order and their amounts as they came"
	)
	check(#Rules.Rows(nil, map) == 0 and #Rules.Rows({}, map) == 0, "no lines: no rows")
end)

L4W3T.group("totals", function()
	print(" Totals, Owned, Wallet: the card's numbers")
	local Rules = L4W3T.Rules
	local function summary(materials: any): any
		return { cash = 900, valor = 4, materials = materials }
	end
	local main = Rules.Totals(summary({ Timber = 40, Steel = 60 }))
	check(main.material == "Steel" and main.materials == 60 and main.cash == 900 and main.valor == 4, "the main material is the largest amount; cash and Valor are the summary's")
	local tied = Rules.Totals(summary({ Steel = 5, Alloy = 5, Timber = 5 }))
	check(tied.material == "Alloy" and tied.materials == 5, "a tie goes to the first name, whatever the table's order")
	local none = Rules.Totals(summary({ Timber = 0, Steel = -3, Alloy = L4W3T.NAN, Circuits = math.huge }))
	check(none.material == "" and none.materials == 0, "no amount above 0 that is finite: no main material")
	check(Rules.Totals(summary({})).material == "", "an empty material map: none")

	check(Rules.Owned({ Timber = 12 }, "Timber") == 12, "Owned: the profile's amount")
	check(Rules.Owned(nil, "Timber") == 0 and Rules.Owned({ Timber = 12 }, "") == 0, "Owned: no map, or no material, is 0")
	check(Rules.Owned({ Timber = "12" }, "Timber") == 0 and Rules.Owned({ Timber = -1 }, "Timber") == 0, "Owned: a string or a negative is 0")
	check(Rules.Owned({ Timber = L4W3T.NAN }, "Timber") == 0 and Rules.Owned({ Timber = math.huge }, "Timber") == 0, "Owned: NaN and infinity are 0 (Format.Cash never returns on infinity)")

	local wallet = Rules.Wallet(1500, { materials = { Timber = 9, Steel = 2 }, valor = 3 }, "Timber")
	check(wallet.cash == 1500 and wallet.materials == 9 and wallet.valor == 3, "Wallet: the cash handed in, the material's count and Valor from `combat`")
	local bare = Rules.Wallet(70, nil, "Timber")
	check(bare.cash == 70 and bare.materials == 0 and bare.valor == 0, "Wallet with no `combat` yet: cash only")
	local odd = Rules.Wallet(70, { materials = "Timber", valor = "3" }, "Timber")
	check(odd.materials == 0 and odd.valor == 0, "Wallet: materials that are not a map and Valor that is not a number are 0")
	check(Rules.Wallet(70, "combat", "Timber").valor == 0, "Wallet: a `combat` that is not a table is none")
	check(
		Rules.Wallet(math.huge, nil, "").cash == 0
			and Rules.Wallet(L4W3T.NAN, nil, "").cash == 0
			and Rules.Wallet(-5, nil, "").cash == 0
			and Rules.Wallet(70, { valor = math.huge }, "").valor == 0,
		"Wallet: an infinite, NaN or negative count is 0"
	)
end)

L4W3T.group("with", function()
	print(" WithText: the words for a later map node")
	local Rules = L4W3T.Rules
	local map = L4W3T.map()
	check(Rules.WithText(map, "castle") == "with the Castle", "\"with the Castle\"")
	check(Rules.WithText(map, "planet") == "with another Planet", "a name starting \"Another\": \"with another Planet\"")
	check(Rules.WithText(map, "dream") == "with the Dream", "a name starting \"The\": \"with the Dream\", never \"the The\"")
	check(Rules.WithText(map, "inn") == "with an Inn" and Rules.WithText(map, "pass") == "with a Pass", "\"An\" and \"A\" keep their own article")
	check(Rules.WithText(map, "theatre") == "with the Theatre", "a name that only starts like \"The\" takes \"the\"")
	check(Rules.WithText(map, "moon") == "with the moon" and Rules.WithText(nil, "castle") == "with the castle", "an unknown node, or no map: its id")
end)

L4W3T.group("next", function()
	print(" NextAbility: Valor's purpose (slice 3 s4: upcoming entries checked)")
	local Rules = L4W3T.Rules
	local map = L4W3T.map()
	check(Rules.NextAbility(map, {}) == "next: Double Jump · 10 Valor", "nothing owned: the ability on sale, with its price")
	check(Rules.NextAbility(map, nil) == "next: Double Jump · 10 Valor", "no ability map yet: the same")
	check(Rules.NextAbility(map, { doubleJump = true }) == "next: Glide · with the Castle", "everything on sale owned: the coming one, with its node")
	check(Rules.NextAbility(map, { doubleJump = true, glide = true }) == nil, "everything owned: no line")
	check(Rules.NextAbility(nil, {}) == nil, "no Expeditions config: no line")
	local ordered = L4W3T.map()
	ordered.abilities.list = {
		{ id = "dash", name = "Air Dash", text = "t", price = { valor = 30 }, order = 2 },
		{ id = "wallRun", name = "Wall Run", text = "t", price = { valor = 20 }, order = 1 },
	}
	check(Rules.NextAbility(ordered, {}) == "next: Wall Run · 20 Valor", "the lowest `order` first, wherever it stands in the list")
	check(Rules.NextAbility(ordered, { wallRun = true }) == "next: Air Dash · 30 Valor", "then the next one not owned")
	local tied = L4W3T.map()
	tied.abilities.list = {
		{ id = "zip", name = "Zip", text = "t", price = { valor = 5 }, order = 1 },
		{ id = "hop", name = "Hop", text = "t", price = { valor = 6 }, order = 1 },
	}
	check(Rules.NextAbility(tied, {}) == "next: Hop · 6 Valor", "an `order` tie goes to the id the Armory lists first")
	local unsold = L4W3T.map()
	unsold.abilities.list[1].price.valor = 2.5
	check(Rules.NextAbility(unsold, {}) == "next: Glide · with the Castle", "an entry the server cannot sell is never named for Valor")

	local broken = L4W3T.map()
	broken.abilities.upcoming = {
		5,
		{ id = "noName", text = "t", with = "castle" },
		{ id = "noWith", name = "No With", text = "t" },
		{ id = "noText", name = "No Text", with = "castle" },
		{ name = "No Id", text = "t", with = "castle" },
		{ id = "badName", name = 7, text = "t", with = "castle" },
		{ id = "fly", name = "Fly", text = "t", with = "dream" },
	}
	check(
		Rules.NextAbility(broken, { doubleJump = true }) == "next: Fly · with the Dream",
		"an upcoming entry missing its id, name, text or `with`, or not a table, is left out, never thrown on"
	)
	local notList = L4W3T.map()
	notList.abilities.upcoming = "glide"
	check(Rules.NextAbility(notList, { doubleJump = true }) == nil, "an `upcoming` that is not a table: no line")
	local noUpcoming = L4W3T.map()
	noUpcoming.abilities.upcoming = nil
	check(Rules.NextAbility(noUpcoming, { doubleJump = true }) == nil, "no `upcoming`: no line once all is owned")
	local noAbilities = L4W3T.map()
	noAbilities.abilities = nil
	check(Rules.NextAbility(noAbilities, {}) == nil, "no `abilities` block: no line")
end)

L4W3T.group("flights", function()
	print(" Flights: how many coins and logs fly (Theme.lowEndDevice, handed in)")
	local Rules = L4W3T.Rules
	local counts = L4W3T.COUNTS
	local paid = { cash = 900, material = "Timber", materials = 40, valor = 2 }
	local coins, logs = Rules.Flights(false, paid, counts)
	check(coins == 14 and logs == 8, "not low end: every coin and log")
	coins, logs = Rules.Flights(true, paid, counts)
	check(coins == 5 and logs == 4, "low end: fewer")
	coins, logs = Rules.Flights(false, { cash = 0, material = "Timber", materials = 40, valor = 0 }, counts)
	check(coins == 0 and logs == 8, "no cash: no coins")
	coins, logs = Rules.Flights(false, { cash = 900, material = "", materials = 0, valor = 0 }, counts)
	check(coins == 14 and logs == 0, "no main material: no logs")
	coins, logs = Rules.Flights(false, { cash = 900, material = "Timber", materials = 0, valor = 0 }, counts)
	check(logs == 0, "a main material of 0: no logs")
	local _, many = Rules.Flights(true, paid, { coins = 14, coinsLowEnd = 5, logs = 8, logsLowEnd = 12 })
	check(many == 8, "never more logs than the pile has places")
end)

L4W3T.group("result", function()
	print(" IsRunResult: the result a card may be built from (F15)")
	local Rules = L4W3T.Rules
	check(Rules.IsRunResult(L4W3T.result()) == true, "a whole result is a card's")
	check(Rules.IsRunResult(L4W3T.result({ levelId = L4W3T.NONE })) == false, "F15: no level id, no card (the show key joins it)")
	check(Rules.IsRunResult(L4W3T.result({ levelId = 3 })) == false, "F15: a level id that is not a string, no card")
	check(Rules.IsRunResult(L4W3T.result({ levelId = "" })) == true, "the leave card's empty level id is a string")
	for _, key in { "levelName", "difficulty", "reason", "campsCleared", "camps", "star" } do
		check(Rules.IsRunResult(L4W3T.result({ [key] = L4W3T.NONE })) == false, `no {key}, no card`)
	end
	check(Rules.IsRunResult(L4W3T.result({ star = "true" })) == false, "a star that is not a boolean, no card")
	check(Rules.IsRunResult(L4W3T.result({ campsCleared = "3" })) == false, "camps that are not numbers, no card")
	check(
		Rules.IsRunResult(L4W3T.result({ camps = math.huge })) == false
			and Rules.IsRunResult(L4W3T.result({ campsCleared = L4W3T.NAN })) == false,
		"camps that are not finite, no card (the subtitle formats them)"
	)
	check(Rules.IsRunResult(nil) == false and Rules.IsRunResult("cleared") == false, "nil or a string, no card")
end)

L4W3T.group("read", function()
	print(" ReadDepart and NodeOf: RunState.depart off the wire")
	local Rules = L4W3T.Rules
	local waiting = Rules.ReadDepart(L4W3T.depart("waiting", nil, nil, 25))
	check(
		waiting ~= nil
			and waiting.state == "waiting"
			and waiting.levelId == "forestRoad"
			and waiting.difficulty == "normal"
			and waiting.waitIn == 25
			and waiting.startsIn == nil,
		"a waiting depart, its wait kept"
	)
	local counting = Rules.ReadDepart(L4W3T.depart("counting", nil, "hard", 4.2))
	check(counting ~= nil and counting.state == "counting" and counting.startsIn == 4.2 and counting.difficulty == "hard", "a counting depart, its count kept")
	check(Rules.ReadDepart(L4W3T.depart("picked")) ~= nil, "a picked depart")
	check(Rules.ReadDepart(L4W3T.depart("done")) == nil, "a state the client does not know: none (`done` is never sent)")
	check(Rules.ReadDepart(L4W3T.depart(5 :: any)) == nil, "a state that is not a string: none")
	local noLevel = L4W3T.depart("waiting")
	noLevel.levelId = 3
	local noDifficulty = L4W3T.depart("waiting")
	noDifficulty.difficulty = nil
	check(Rules.ReadDepart(noLevel) == nil and Rules.ReadDepart(noDifficulty) == nil, "no level or no difficulty: none")
	check(Rules.ReadDepart(nil) == nil and Rules.ReadDepart("waiting") == nil, "not a table: none")
	local function wait(value: any): any
		local raw = L4W3T.depart("waiting")
		raw.waitIn = value
		return (Rules.ReadDepart(raw) :: any).waitIn
	end
	check(wait(-1) == nil and wait(L4W3T.NAN) == nil and wait(math.huge) == nil and wait("5") == nil, "a wait that is negative, NaN, infinite or a string is left out")
	check(wait(0) == 0, "a wait of 0 is kept")

	local map = L4W3T.map()
	local node = Rules.NodeOf(map, "forestRoad")
	check(node ~= nil and node.id == "road", "NodeOf: the first node that names the level")
	check(Rules.NodeOf(map, "castleKeep") == nil and Rules.NodeOf(nil, "forestRoad") == nil, "NodeOf: a level no node names, or no map: none")
end)

L4W3T.group("text", function()
	print(" DepartText: the lobby's notice line")
	local Rules = L4W3T.Rules
	local map = L4W3T.map()
	local function text(state: string, levelId: string?, difficulty: string?, left: number?, expeditions: any?): string?
		local depart = Rules.ReadDepart(L4W3T.depart(state, levelId, difficulty, left))
		return Rules.DepartText(depart, if expeditions == false then nil else expeditions or map)
	end
	check(text("waiting", nil, nil, 25) == "Waiting for your party · 25", "waiting: \"Waiting for your party · 25\"")
	check(text("waiting", nil, nil, 24.2) == "Waiting for your party · 25", "waiting: the seconds rounded up")
	check(text("waiting") == "Waiting for your party", "waiting with no count: the words alone")
	check(text("counting", nil, nil, 5) == "Forest Road · Normal starts in 5", "counting: \"Forest Road · Normal starts in 5\"")
	check(text("counting", nil, "hard", 0.3) == "Forest Road · Hard starts in 1", "counting: the map's difficulty name, the seconds rounded up")
	check(text("counting", "lostLevel", "odd", 5) == "lostLevel · odd starts in 5", "counting a level and difficulty the map does not name: their ids")
	check(text("counting", nil, nil, 5, false) == "forestRoad · normal starts in 5", "counting with no map: the ids")
	check(text("picked") == nil, "picked: no line (the map shows it)")
end)

L4W3T.group("depart", function()
	print(" Depart: what each RunState does to the lobby's map (m3 p1, p2)")
	local Rules = L4W3T.Rules
	local map = L4W3T.map()
	local fresh = L4W3T.FRESH
	local function step(raw: any, phase: string, last: string, memory: any?): any
		return Rules.Depart(raw, phase, last, map, memory or fresh)
	end

	local entry = step(nil, "lobby", "")
	check(entry.open == true and entry.close == false and entry.holding == false and entry.select == nil and entry.line == nil, "entering the lobby with no depart: the map opens, no line")
	local back = step(nil, "lobby", "summary")
	check(back.open == true, "back in the lobby after a run: the map opens")
	local stay = step(nil, "lobby", "lobby")
	check(stay.open == false and stay.close == false, "staying in the lobby: the map is left as it is")

	-- p2: the hold.
	local held = step(L4W3T.depart("waiting", nil, nil, 30), "lobby", "")
	check(held.holding == true and held.open == false, "p2: entering the lobby while the party is awaited: the map does not open over the line")
	check(held.line == "Waiting for your party · 30", "p2: the wait's line shows")
	check(held.close == true and held.memory.holding == true, "p2: the hold began on this RunState: an open map closes")
	local counted = step(L4W3T.depart("counting", nil, nil, 5), "lobby", "", fresh)
	check(counted.holding == true and counted.open == false, "p2: entering the lobby while the count runs: the map does not open")
	local still = step(L4W3T.depart("counting", nil, nil, 4), "lobby", "lobby", held.memory)
	check(still.close == false and still.open == false and still.holding == true, "p2: the hold goes on: nothing closes again (the leader may open the map by hand)")
	local pressed = step(L4W3T.depart("waiting", nil, nil, 30), "lobby", "lobby", stay.memory)
	check(pressed.close == true and pressed.open == false, "p2: R pressed with the map open (a hold that begins mid-lobby): it closes")
	local started = step(nil, "lobby", "lobby", still.memory)
	check(started.holding == false and started.open == false and started.close == false and started.line == nil and started.memory.holding == false, "the count ended (the start): nothing opens by itself, the line goes")

	-- p1: once per arrival.
	local picked = step(L4W3T.depart("picked", nil, "hard"), "lobby", "lobby")
	check(picked.select ~= nil and picked.select.node == "road" and picked.select.difficulty == "hard" and picked.open == true, "p1: a picked depart selects its level's node and difficulty and opens the map")
	check(picked.memory.picked == "forestRoad:hard" and picked.line == nil and picked.holding == false and picked.close == false, "p1: the pick is kept, with no line and no hold")
	local again = step(L4W3T.depart("picked", nil, "hard"), "lobby", "lobby", picked.memory)
	check(again.select == nil and again.open == false, "p1: the same pick on every later RunState opens nothing (the map can be closed)")
	check(again.memory.picked == "forestRoad:hard", "p1: and stays kept")
	local other = step(L4W3T.depart("picked", nil, "normal"), "lobby", "lobby", again.memory)
	check(other.select ~= nil and other.select.difficulty == "normal" and other.open == true, "p1: a different pick opens the map on it")
	local lost = step(L4W3T.depart("picked", "castleKeep", "normal"), "lobby", "lobby", other.memory)
	check(lost.select == nil and lost.open == false and lost.memory.picked == "forestRoad:normal", "p1: a level no node names is no pick, and the last pick is kept")
	local enteredPicked = step(L4W3T.depart("picked"), "lobby", "", fresh)
	check(enteredPicked.open == true and enteredPicked.select ~= nil, "entering the lobby on a pick: the map opens on it")

	-- The lobby only.
	local outside = step(L4W3T.depart("waiting", nil, nil, 30), "wave", "lobby", held.memory)
	check(
		outside.line == nil
			and outside.holding == false
			and outside.close == false
			and outside.open == false
			and outside.memory.holding == false,
		"a depart outside the lobby is not read: no line, no hold"
	)
	local outsidePick = step(L4W3T.depart("picked"), "summary", "wave", fresh)
	check(outsidePick.select == nil and outsidePick.memory.picked == "", "a pick outside the lobby opens nothing and is not kept")

	local memory = { holding = false, picked = "" }
	Rules.Depart(L4W3T.depart("picked"), "lobby", "", map, memory)
	check(memory.holding == false and memory.picked == "", "the memory handed in is never written (the answer carries the next one)")
	check(Rules.Depart(L4W3T.depart("picked"), "lobby", "lobby", nil, fresh).select == nil, "no map: a pick selects nothing")
end)

L4W3T.group("arrival", function()
	print(" Depart: one arrival from the city's map, RunState by RunState")
	local Rules = L4W3T.Rules
	local map = L4W3T.map()
	local memory: any = L4W3T.FRESH
	local trail: { string } = {}
	local function run(raw: any, phase: string, last: string): any
		local answer = Rules.Depart(raw, phase, last, map, memory)
		memory = answer.memory
		table.insert(trail, (if answer.open then "o" else "-") .. (if answer.close then "c" else "-"))
		return answer
	end
	run(L4W3T.depart("waiting", nil, nil, 30), "lobby", "")
	run(L4W3T.depart("waiting", nil, nil, 29), "lobby", "lobby")
	local count = run(L4W3T.depart("counting", nil, nil, 5), "lobby", "lobby")
	run(nil, "lobby", "lobby")
	run(nil, "stage", "lobby")
	run(nil, "summary", "stage")
	local home = run(nil, "lobby", "summary")
	check(count.line == "Forest Road · Normal starts in 5", "the count's line names the level and difficulty")
	check(table.concat(trail, " ") == "-c -- -- -- -- -- o-", "wait, count, start, run, card, back: the map closes once at the wait and opens only back in the lobby")
	check(home.holding == false and home.line == nil, "nothing auto-starts after a run: back in the lobby there is no line")
end)

L4W3T.group("shipped", function()
	print(" The files as they ship (Expeditions.json, Config/Levels)")
	local Rules = L4W3T.Rules
	local expeditions = FIXTURES.expeditions
	local list = expeditions.abilities.list
	local first = list[1]
	for _, def in list do
		if def.order < first.order or (def.order == first.order and def.id < first.id) then
			first = def
		end
	end
	check(
		Rules.NextAbility(expeditions, {}) == `next: {first.name} · {L4W3T.Format.Cash(first.price.valor)} Valor`,
		`a fresh profile's card names the first ability on sale ({Rules.NextAbility(expeditions, {})})`
	)
	local owned = {}
	for _, def in list do
		owned[def.id] = true
	end
	local coming = expeditions.abilities.upcoming[1]
	local words = Rules.WithText(expeditions, coming.with)
	check(words ~= `with the {coming.with}`, `the first coming ability's \`with\` names a map node ({words})`)
	check(
		Rules.NextAbility(expeditions, owned) == `next: {coming.name} · {words}`,
		`once all on sale is owned the card names the first coming one ({Rules.NextAbility(expeditions, owned)})`
	)
	local named = 0
	for _, level in FIXTURES.levels do
		local node = Rules.NodeOf(expeditions, level.id)
		check(node ~= nil, `the shipped level {level.id} has a map node, so a \`picked\` depart can open the map on it`)
		named += 1
		local line = Rules.DepartText(
			{ levelId = level.id, difficulty = expeditions.difficulties[1], state = "counting", startsIn = 5 },
			expeditions
		)
		local difficulty = expeditions.difficultyNames[expeditions.difficulties[1]]
		check(
			node ~= nil and line == `{node.name} · {difficulty} starts in 5`,
			`the count for {level.id} names its node and the map's difficulty ({line})`
		)
	end
	check(named >= 1, "at least one level ships")
end)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
