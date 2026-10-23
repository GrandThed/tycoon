-- Cases for L3 W1's run rules (docs/prompts/l3-w1-contract.md, L3-17): a difficulty's first-clear
-- reward as the pure StageFlow reads it (FirstClear) and refuses it (Validate's firstClear lines,
-- with and without the weapons), and the shipped Forest Road's two rewards. Appended by
-- run_harness.py after tests_l1.luau, so every local of the earlier files is in scope (check, load,
-- L1, FIXTURES). Everything hangs off the L3R table (the 200-local limit) and every group runs
-- behind L1.group. WaveService (which asks FirstClear when StageFlow.Award says a star is new) and
-- UnlockService (which gives it) cannot be loaded here.

print("L3 W1: the first clear (StageFlow.FirstClear, Validate's firstClear lines)")

local L3R: any = {
	Flow = load("StageFlow"),
	Unlocks = load("Unlocks"),
	NAN = 0 / 0,
	-- A value that takes a key away in `over` (nil cannot be written into a table).
	NONE = {},
}

-- The fixture level (L1.level) with `hard.firstClear` set to `reward` (L3R.NONE: no key).
function L3R.level(reward: any): any
	local level = L1.level()
	if reward ~= L3R.NONE then
		level.difficulties.hard.firstClear = reward
	end
	return level
end

-- Validate's lines that name a firstClear, on the fixture level and layout; `weapons` and
-- `starters` go to Validate as given (nil = left out, the 6-argument call).
function L3R.lines(level: any, weapons: any?, starters: any?): { string }
	local found = {}
	local ok, problems = pcall(
		L3R.Flow.Validate,
		level,
		L1.layout(),
		L1.kinds,
		L1.ranks,
		L1.rules,
		L1.crowdMax,
		weapons,
		starters
	)
	if not ok then
		return { "Validate threw: " .. tostring(problems) }
	end
	for _, line in problems do
		if string.find(line, "firstClear", 1, true) ~= nil then
			table.insert(found, line)
		end
	end
	return found
end

-- The weapons and the starter set WaveService.readLevel hands Validate.
function L3R.roster(): (any, any)
	return FIXTURES.proving.weapons, L3R.Unlocks.Starters(FIXTURES.proving.loadout)
end

-- Exactly one line, holding every text of `...`.
function L3R.says(found: { string }, ...: string): boolean
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

function L3R.firstClearTests(): ()
	print(" StageFlow.FirstClear: what a new star gives besides itself (L3-17)")
	local Flow = L3R.Flow
	check(
		Flow.FirstClear(L3R.level(L3R.NONE), "hard") == nil,
		"a difficulty with no firstClear gives nothing"
	)
	check(
		Flow.FirstClear(L3R.level({ family = "warhammer" }), "normal") == nil,
		"nor does another difficulty of the same level"
	)
	check(
		Flow.FirstClear(L3R.level({ family = "warhammer" }), "nightmare") == nil,
		"nor a difficulty the level lacks"
	)
	local family = Flow.FirstClear(L3R.level({ family = "warhammer" }), "hard")
	check(
		family ~= nil and family.family == "warhammer" and family.valor == nil,
		"a family alone: the family, no Valor"
	)
	local valor = Flow.FirstClear(L3R.level({ valor = 25 }), "hard")
	check(
		valor ~= nil and valor.family == nil and valor.valor == 25,
		"a Valor alone: the Valor, no family"
	)
	local both = Flow.FirstClear(L3R.level({ family = "warhammer", valor = 3 }), "hard")
	check(both ~= nil and both.family == "warhammer" and both.valor == 3, "both together")
	local zero = Flow.FirstClear(L3R.level({ family = "warhammer", valor = 0 }), "hard")
	check(
		zero ~= nil and zero.family == "warhammer" and zero.valor == nil,
		"a Valor of 0 is no Valor"
	)
	check(
		Flow.FirstClear(L3R.level({ valor = 0 }), "hard") == nil,
		"and with nothing else, nothing"
	)
	check(Flow.FirstClear(L3R.level({}), "hard") == nil, "an empty firstClear gives nothing")
	check(
		Flow.FirstClear(L3R.level(5), "hard") == nil
			and Flow.FirstClear(L3R.level("warhammer"), "hard") == nil,
		"a firstClear that is not a table gives nothing"
	)
	local cases = {
		{ "an empty family", { family = "", valor = 2 } },
		{ "a family that is a number", { family = 7, valor = 2 } },
		{ "a family that is a table", { family = { "warhammer" }, valor = 2 } },
	}
	for _, case in cases do
		local got = Flow.FirstClear(L3R.level(case[2]), "hard")
		check(
			got ~= nil and got.family == nil and got.valor == 2,
			`{case[1]} is left out, the Valor kept`
		)
	end
	local valors = {
		{ "fractional", 2.5 },
		{ "negative", -1 },
		{ "NaN", L3R.NAN },
		{ "endless", math.huge },
		{ "a string", "5" },
	}
	for _, case in valors do
		local got = Flow.FirstClear(L3R.level({ family = "warhammer", valor = case[2] }), "hard")
		check(
			got ~= nil and got.family == "warhammer" and got.valor == nil,
			`a {case[1]} Valor is left out, the family kept`
		)
	end
	local level = L3R.level({ family = "warhammer", valor = 4 })
	local given = Flow.FirstClear(level, "hard")
	given.family = "spear"
	given.valor = 99
	local again = Flow.FirstClear(level, "hard")
	check(
		again.family == "warhammer"
			and again.valor == 4
			and level.difficulties.hard.firstClear.family == "warhammer",
		"a fresh table each time: writing the answer leaves the level file as it was"
	)
	local field = L1.field()
	check(
		field ~= nil and Flow.FirstClear(field, "normal") == nil,
		"a difficulty that names no firstClear gives nothing (the hand-written field's one, L4B-6)"
	)
end
L1.group("l3 firstClearTests", L3R.firstClearTests)

function L3R.validateTests(): ()
	print(" StageFlow.Validate: the firstClear lines (L3-17)")
	local weapons, starters = L3R.roster()
	local function said(found: { string }): string
		return table.concat(found, "; ")
	end
	local accepted = {
		{ "no firstClear", L3R.NONE },
		{ "a family that is no starter", { family = "warhammer" } },
		{ "a Valor", { valor = 25 } },
		{ "a Valor of 0", { valor = 0 } },
		{ "both", { family = "frostHammer", valor = 6 } },
		{ "an empty firstClear", {} },
	}
	for _, case in accepted do
		local found = L3R.lines(L3R.level(case[2]), weapons, starters)
		check(#found == 0, `{case[1]}: accepted ({said(found)})`)
	end
	local long = string.rep("w", L3R.Unlocks.MAX_FAMILY_LENGTH + 1)
	local exact = string.rep("w", L3R.Unlocks.MAX_FAMILY_LENGTH)
	local refused = {
		{ "a firstClear that is a number", 5, { "difficulties.hard.firstClear is not a table" } },
		{
			"a firstClear that is a string",
			"warhammer",
			{ "difficulties.hard.firstClear is not a table" },
		},
		{
			"an empty family",
			{ family = "" },
			{ "difficulties.hard.firstClear.family is , not a family id" },
		},
		{
			"a family that is a number",
			{ family = 7 },
			{ "difficulties.hard.firstClear.family is 7, not a family id" },
		},
		{
			"a family one byte over the cap",
			{ family = long },
			{ `difficulties.hard.firstClear.family is {long}, not a family id` },
		},
		{
			"a family no weapon has",
			{ family = "nosuch" },
			{ 'difficulties.hard.firstClear.family names "nosuch", which is no weapons family' },
		},
		{
			"a family at the cap no weapon has",
			{ family = exact },
			{ `names "{exact}", which is no weapons family` },
		},
		{
			"the melee starter",
			{ family = "broadsword" },
			{
				'difficulties.hard.firstClear.family names the starter "broadsword", which everyone owns',
			},
		},
		{ "the ranged starter", { family = "longbow" }, { 'names the starter "longbow"' } },
		{
			"a fractional Valor",
			{ valor = 2.5 },
			{ "difficulties.hard.firstClear.valor is 2.5, not a whole number of at least 0" },
		},
		{
			"a negative Valor",
			{ valor = -1 },
			{ "difficulties.hard.firstClear.valor is -1, not a whole number of at least 0" },
		},
		{
			"a NaN Valor",
			{ valor = L3R.NAN },
			{ "difficulties.hard.firstClear.valor is ", ", not a whole number of at least 0" },
		},
		{
			"an endless Valor",
			{ valor = math.huge },
			{ "difficulties.hard.firstClear.valor is inf, not a whole number of at least 0" },
		},
		{
			"a Valor that is a string",
			{ valor = "25" },
			{ "difficulties.hard.firstClear.valor is 25, not a whole number" },
		},
	}
	for _, case in refused do
		local found = L3R.lines(L3R.level(case[2]), weapons, starters)
		check(
			L3R.says(found, table.unpack(case[3])),
			`{case[1]}: refused, one line ({said(found)})`
		)
	end
	local twice = L3R.lines(L3R.level({ family = "nosuch", valor = -2 }), weapons, starters)
	check(
		#twice == 2 and L1.has(twice, 'names "nosuch"') and L1.has(twice, "valor is -2"),
		`a bad family and a bad Valor: a line each ({said(twice)})`
	)

	-- Left out of the call, the weapons do not judge the family: an id is all that is checked.
	local function bare(reward: any): { string }
		return L3R.lines(L3R.level(reward), nil, nil)
	end
	check(
		#bare({ family = "nosuch" }) == 0 and #bare({ family = "broadsword" }) == 0,
		"without the weapons, an unknown family and a starter pass (the 6-argument call)"
	)
	check(
		L3R.says(bare({ family = "" }), "not a family id")
			and L3R.says(bare({ family = long }), "not a family id"),
		"but an empty or overlong id is still refused"
	)
	check(L3R.says(bare({ valor = 1.5 }), "valor is 1.5"), "and so is a bad Valor")
	local onlyWeapons = L3R.lines(L3R.level({ family = "broadsword" }), weapons, nil)
	check(
		#onlyWeapons == 0,
		`the weapons without the starters judge the family's existence only ({said(onlyWeapons)})`
	)

	-- Seven difficulties at once: the lines in difficulty-name order, whatever order the table
	-- iterates in (seven keys, so a table's own order matching by luck is out of the question).
	local level = L3R.level({ valor = -1 })
	local names = { "normal", "zeal", "apex", "brutal", "easy", "mythic", "hard" }
	for _, name in names do
		local scales = level.difficulties[name] or L1.copy(level.difficulties.normal)
		scales.firstClear = { valor = -1 }
		level.difficulties[name] = scales
	end
	local ordered = L3R.lines(level, weapons, starters)
	local sorted = table.clone(names)
	table.sort(sorted)
	local inOrder = #ordered == #sorted
	for index, name in sorted do
		inOrder = inOrder
			and ordered[index] ~= nil
			and string.find(ordered[index], `difficulties.{name}.firstClear`, 1, true) ~= nil
	end
	check(inOrder, `seven difficulties: one line each, in name order ({said(ordered)})`)
end
L1.group("l3 validateTests", L3R.validateTests)

function L3R.shippedTests(): ()
	print(" The shipped Forest Road: its first clears (L3-17)")
	local got = L1.real.resolve("forestRoad")
	local level, layout = got.level, got.layout
	if level == nil or layout == nil then
		check(false, "Forest Road resolves (the cases below need it)")
		return
	end
	local weapons, starters = L3R.roster()
	local problems = L3R.Flow.Validate(
		level,
		layout,
		L1.real.kinds,
		L1.real.ranks(),
		L1.real.rules,
		FIXTURES.proving.crowd.maxAlive,
		weapons,
		starters
	)
	check(
		#problems == 0,
		`Validate with the weapons, as WaveService.readLevel calls it: playable ({table.concat(
			problems,
			"; "
		)})`
	)
	local Flow = L3R.Flow
	check(Flow.FirstClear(level, "normal") == nil, "a first Normal clear gives its star only")
	local hard = Flow.FirstClear(level, "hard")
	check(
		hard ~= nil and hard.family == "warhammer",
		`a first Hard clear gives the Warhammer ({if hard ~= nil
			then tostring(hard.family)
			else "nothing"})`
	)
	check(
		hard ~= nil and weapons[hard.family or ""] ~= nil and not starters[hard.family or ""],
		"a family of the weapons that is no starter"
	)
	local brutal = Flow.FirstClear(level, "brutal")
	check(
		brutal ~= nil
			and brutal.family == nil
			and type(brutal.valor) == "number"
			and brutal.valor > 0,
		`a first Brutal clear gives Valor and no family ({if brutal ~= nil
			then tostring(brutal.valor)
			else "nothing"})`
	)
end
L1.group("l3 shippedTests", L3R.shippedTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
