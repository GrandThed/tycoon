-- Cases for L3 W1, tiers per weapon and the saved loadout (docs/prompts/l3-w1-contract.md): the
-- pure Armory ladder and its windows (L3-1 to L3-6), the upgrade's verdict and write (L3-5,
-- L3-13), the frozen refund and the profile's v8 step (L3-7, L3-8), Unlocks' saved loadout,
-- stars and the Armory levers' shared pieces (L3-9, L3-10, L3-28), then Armory.json as it ships.
-- Appended after tests_l2.luau by run_harness.py, so every local of the earlier files is in scope
-- (check, near, load, modules, L1, L2). Everything hangs off the L3 table (the 200-local limit),
-- and every group runs behind L1.group, so one that throws fails a check and the bundle goes on.
-- The rules are tested on a fixture with the contract's own numbers (L3.fixture), so a data
-- change cannot hide a rule change; the shipped data is pinned against the same numbers last.
-- The fix round (docs/prompts/l3-w1-fix-round.md) adds the band top's trophy (StarHeld, R1), the
-- strike tier (StrikeTier, R3), the saved pair's Power and the hub's profile copy (SavedPower,
-- ProfileCopy, R7), the one migration runner (ProfileSchema.Run, R5), single-rule breaks of every
-- Problems rule (R6), and, read as text (FIXTURES.source.l3), the server lines that apply them.
-- The fix round 2 (docs/prompts/l3-w1-fix2.md) adds the first-clear write both places make
-- (Unlocks.ApplyFirstClear, F2) and, in the text reading, the lines that feed each pinned call,
-- the exits of their bodies and the count-0 rules in any spelling (F1, F3, F5).

print("L3: tiers per weapon, the saved loadout and profile v8 (Armory, Unlocks, ProfileSchema)")

local L3: any = {
	Armory = load("Armory"),
	Unlocks = load("Unlocks"),
	Schema = load("ProfileSchema"),
	-- The fix round (docs/prompts/l3-w1-fix-round.md): the hub's profile copy, made pure (R7).
	Copy = load("ProfileCopy"),
	NAN = 0 / 0,
	-- L3-1: 1.5 x 1.65^(t - 1), to 4 decimals.
	DAMAGE = {
		1.5,
		2.475,
		4.0837,
		6.7382,
		11.118,
		18.3447,
		30.2688,
		49.9435,
		82.4068,
		135.9711,
		224.3524,
		370.1814,
		610.7994,
		1007.819,
		1662.9013,
		2743.7872,
		4527.2488,
		7469.9606,
		12325.435,
		20336.9677,
	},
	-- L3-2: T1-T11 are the old slot tiers 2-12, one for one.
	HP_MELEE = { 35, 50, 80, 120, 170, 250, 350, 480, 700, 950, 1300 },
	HP_RANGED = { 20, 30, 50, 80, 110, 160, 230, 320, 450, 620, 850 },
	-- L3-3, as drawn.
	WINDOWS = {
		broadsword = { 1, 12 },
		longbow = { 1, 12 },
		flamethrower = { 2, 8 },
		warhammer = { 3, 16 },
		frostHammer = { 5, 12 },
		greataxe = { 6, 18 },
		splitbow = { 8, 8 },
		spear = { 9, 20 },
		shotgun = { 9, 16 },
		rifle = { 11, 18 },
		launcher = { 13, 20 },
		smg = { 14, 20 },
		beam = { 16, 20 },
		chaingun = { 17, 20 },
		spinblade = { 20, 20 },
	},
	-- L3-8: today's twelve slot-tier prices, frozen (Armory.json `slots` before v8).
	LEGACY = {
		{ "Timber", 10 },
		{ "Timber", 60 },
		{ "Timber", 180 },
		{ "Steel", 10 },
		{ "Steel", 60 },
		{ "Steel", 180 },
		{ "Circuits", 10 },
		{ "Circuits", 60 },
		{ "Circuits", 180 },
		{ "Alloy", 10 },
		{ "Alloy", 60 },
		{ "Alloy", 180 },
	},
}

-- Armory.json with the contract's ladder, windows and legacy list laid over it. T12-T20 of the HP
-- ladder are the designer's; any rising pair with melee >= ranged serves the rules.
function L3.fixture(): any
	local cfg = L1.copy(ARMORY)
	cfg.baseHp = 100
	cfg.power = { hpWeight = 0.2, tierWeight = 11 }
	local melee = L1.copy(L3.HP_MELEE)
	local ranged = L1.copy(L3.HP_RANGED)
	for t = 12, 20 do
		table.insert(melee, 1300 + 100 * (t - 11))
		table.insert(ranged, 850 + 50 * (t - 11))
	end
	cfg.ladder = {
		damage = L1.copy(L3.DAMAGE),
		hp = { melee = melee, ranged = ranged },
		rangeHp = 130,
		bandSize = 4,
		bands = {
			{ levelId = "forestRoad", material = "Timber" },
			{ levelId = "castle", material = "Iron" },
			{ levelId = "underworld", material = "Ember" },
			{ levelId = "planet", material = "Glowstone" },
			{ levelId = "dream", material = "Crystal" },
		},
		costs = { 100, 100, 250, 500 },
		starDifficulty = "hard",
		-- The fix round's R1: a Brutal clear opens a band top as a Hard one does.
		starAlso = { "brutal" },
	}
	cfg.windows = {}
	for family, pair in L3.WINDOWS do
		cfg.windows[family] = { start = pair[1], top = pair[2] }
	end
	cfg.legacy = { gearCosts = {} }
	for _, pair in L3.LEGACY do
		table.insert(cfg.legacy.gearCosts, { material = pair[1], amount = pair[2] })
	end
	return cfg
end

-- A combat profile slice: what the tier rules read.
function L3.combat(tiers: any, materials: any, stars: any): any
	return {
		materials = materials or {},
		valor = 0,
		gear = { melee = 0, ranged = 0 },
		ascension = { melee = 0, ranged = 0 },
		tiers = tiers,
		stars = stars,
		families = {},
	}
end

-- Deep equality of plain data (NaN never occurs in it).
function L3.same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not L3.same(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function L3.families(): { string }
	local names = {}
	for family in FIXTURES.proving.weapons do
		table.insert(names, family)
	end
	table.sort(names)
	return names
end

function L3.ladderTests(): ()
	print(" The ladder and the windows (L3-1 to L3-3)")
	local A = L3.Armory
	local cfg = L3.fixture()
	check(A.LadderSize(cfg) == 20, `the ladder has 20 tiers ({A.LadderSize(cfg)})`)
	local bare = L3.fixture()
	bare.ladder = nil
	check(A.LadderSize(bare) == 0, "no ladder: size 0")

	local start, top = A.Window(cfg, "flamethrower")
	check(start == 2 and top == 8, `a window as drawn: flamethrower 2 to 8 ({start}, {top})`)
	check(A.Window(cfg, "nope") == nil, "a family with no window has none")
	check(A.Window(bare, "broadsword") == nil, "and without a ladder no window holds")
	local wide = L3.fixture()
	wide.windows.broadsword = { start = 0, top = 30 }
	start, top = A.Window(wide, "broadsword")
	check(
		start == 1 and top == 20,
		`a window past the ladder is held inside it (0 to 30 reads 1 to 20: {start}, {top})`
	)
	local bad = {
		{ "a start above its top", { start = 5, top = 3 } },
		{ "a fractional start", { start = 2.5, top = 8 } },
		{ "a top that is a string", { start = 2, top = "8" } },
		{ "a NaN top", { start = 2, top = L3.NAN } },
		{ "an infinite top", { start = 2, top = math.huge } },
		{ "no start", { top = 8 } },
	}
	for _, case in bad do
		local broken = L3.fixture()
		broken.windows.flamethrower = case[2]
		check(A.Window(broken, "flamethrower") == nil, `a malformed window is none: {case[1]}`)
	end
	local notTable = L3.fixture()
	notTable.windows.flamethrower = 4
	check(A.Window(notTable, "flamethrower") == nil, "a window that is not a table is none")

	-- TierOf (L3-3).
	check(
		A.TierOf(cfg, L3.combat(nil), "broadsword") == 1,
		"no tiers saved: the window's start (1)"
	)
	check(
		A.TierOf(cfg, L3.combat({}), "flamethrower") == 2,
		"a family starting at 2 fights at 2 with nothing saved"
	)
	check(A.TierOf(cfg, nil, "warhammer") == 3, "no profile at all: the start too")
	check(
		A.TierOf(cfg, L3.combat({ broadsword = 5 }), "broadsword") == 5,
		"a saved tier inside the window is the tier"
	)
	check(
		A.TierOf(cfg, L3.combat({ warhammer = 1 }), "warhammer") == 3,
		"a saved tier below the start reads the start"
	)
	check(
		A.TierOf(cfg, L3.combat({ broadsword = 15 }), "broadsword") == 12,
		"a saved tier above the top reads the top"
	)
	local moved = L3.fixture()
	moved.windows.broadsword = { start = 1, top = 6 }
	check(
		A.TierOf(moved, L3.combat({ broadsword = 9 }), "broadsword") == 6,
		"a window narrowed under a saved 9 holds it at its new top (6): no profile is stranded"
	)
	moved.windows.broadsword = { start = 7, top = 12 }
	check(
		A.TierOf(moved, L3.combat({ broadsword = 4 }), "broadsword") == 7,
		"and one moved up past a saved 4 lifts it to the new start (7)"
	)
	check(
		A.TierOf(cfg, L3.combat({ broadsword = 4.7 }), "broadsword") == 1,
		"a saved tier that is not a whole number reads the start (4.7 -> 1)"
	)
	check(
		A.TierOf(cfg, L3.combat({ broadsword = L3.NAN }), "broadsword") == 1
			and A.TierOf(cfg, L3.combat({ broadsword = "4" }), "broadsword") == 1,
		"a NaN or a string saved reads the start"
	)
	check(
		A.TierOf(cfg, L3.combat({ broadsword = math.huge }), "broadsword") == 1,
		"and so does an infinite one"
	)
	check(
		A.TierOf(cfg, L3.combat({ nope = 9 }), "nope") == 1,
		"a family with no window fights at T1 whatever is saved"
	)
	check(
		A.TierOf(bare, L3.combat({ broadsword = 9 }), "broadsword") == 1,
		"and so does every family without a ladder"
	)
	local held = A.HeldTiers(cfg, L3.combat({ broadsword = 3 }), "broadsword", "flamethrower")
	check(
		held.melee == 3 and held.ranged == 2,
		`HeldTiers reads each held family's tier ({held.melee}, {held.ranged})`
	)

	-- NextTier.
	check(A.NextTier(cfg, L3.combat({}), "broadsword") == 2, "NextTier from T1 is 2")
	check(
		A.NextTier(cfg, L3.combat({ broadsword = 12 }), "broadsword") == nil,
		"and none at the top"
	)
	check(
		A.NextTier(cfg, L3.combat({}), "splitbow") == nil
			and A.NextTier(cfg, L3.combat({}), "spinblade") == nil,
		"a relic (8 to 8, 20 to 20) has no next tier"
	)
	check(A.NextTier(cfg, L3.combat({}), "nope") == nil, "nor a family with no window")
	check(
		A.NextTier(cfg, L3.combat({}), "flamethrower") == 3,
		"a family starting at 2 buys 3 first"
	)
end
L1.group("l3 ladderTests", L3.ladderTests)

function L3.strengthTests(): ()
	print(" Strength and health from the ladder (L3-1, L3-2, L3-6)")
	local A = L3.Armory
	local cfg = L3.fixture()
	local bare = L3.fixture()
	bare.ladder = nil
	check(
		near(A.Multiplier(cfg, 1), 1.5)
			and near(A.Multiplier(cfg, 2), 2.475)
			and near(A.Multiplier(cfg, 20), 20336.9677),
		"Multiplier reads the ladder: T1 1.5, T2 2.475, T20 20336.9677"
	)
	check(
		near(A.Multiplier(cfg, 0), 1.5) and near(A.Multiplier(cfg, 25), 20336.9677),
		"a whole tier outside the ladder is held inside it"
	)
	check(
		A.Multiplier(cfg, 2.9) == 1
			and A.Multiplier(cfg, L3.NAN) == 1
			and A.Multiplier(cfg, math.huge) == 1,
		"a tier that is not a whole number (2.9, NaN, infinite) reads x1"
	)
	check(A.Multiplier(bare, 7) == 1, "no ladder: x1, the range's numbers")
	local zero = L3.fixture()
	zero.ladder.damage[3] = 0
	check(
		A.Multiplier(zero, 3) == 1,
		"an entry of 0 degrades to x1, never to hits that remove no HP"
	)
	-- Ascension level 1 of Armory.json: damageMult 2, abilityMult 1.5, hpMult 1.5.
	local asc = ARMORY.ascension.levels[1]
	check(
		near(A.DamageScale(cfg, 1, 0, false), 1.5) and near(A.DamageScale(cfg, 1, 0, true), 1.5),
		"DamageScale at level 0 is the multiplier, for an attack and an ability"
	)
	check(
		near(A.DamageScale(cfg, 3, 1, false), 4.0837 * asc.damageMult)
			and near(A.DamageScale(cfg, 3, 1, true), 4.0837 * asc.abilityMult),
		"Ascension multiplies it: damageMult for an attack, abilityMult for an ability"
	)
	check(
		A.WeaponHp(cfg, "melee", 1, 0) == 35 and A.WeaponHp(cfg, "ranged", 1, 0) == 20,
		"WeaponHp T1: melee 35, ranged 20"
	)
	check(
		A.WeaponHp(cfg, "melee", 11, 0) == 1300 and A.WeaponHp(cfg, "ranged", 11, 0) == 850,
		"T11: the old slot tier 12 (1300, 850)"
	)
	check(
		A.WeaponHp(cfg, "nope", 1, 0) == 0 and A.WeaponHp(bare, "melee", 1, 0) == 0,
		"0 for an unknown slot, and without a ladder"
	)
	check(
		A.WeaponHp(cfg, "melee", 25, 0) == 1300 + 100 * 9 and A.WeaponHp(cfg, "melee", 0, 0) == 35,
		"a whole tier outside the ladder is held inside it"
	)
	check(
		A.WeaponHp(cfg, "melee", 2.5, 0) == 0 and A.WeaponHp(cfg, "melee", math.huge, 0) == 0,
		"0 for a tier that is not a whole number"
	)
	check(
		near(A.WeaponHp(cfg, "melee", 1, 1), 35 * asc.hpMult),
		"the slot's Ascension hpMult multiplies it"
	)
	check(
		A.MaxHp(cfg, { melee = 1, ranged = 1 }, { melee = 0, ranged = 0 }) == 155,
		"MaxHp (T1, T1) = 155, today's 2 / 2"
	)
	check(
		A.MaxHp(cfg, { melee = 3, ranged = 3 }, { melee = 0, ranged = 0 }) == 230,
		"MaxHp (T3, T3) = 230, today's 4 / 4"
	)
	check(
		A.MaxHp(cfg, { melee = 5, ranged = 5 }, { melee = 0, ranged = 0 }) == 380,
		"MaxHp (T5, T5) = 380, today's 6 / 6"
	)
	check(
		A.MaxHp(cfg, { melee = 4, ranged = 1 }, { melee = 0, ranged = 0 }) == 100 + 120 + 20,
		"each slot reads its own family's tier (melee T4, ranged T1: 240)"
	)
	check(
		near(
			A.MaxHp(cfg, { melee = 1, ranged = 1 }, { melee = 1, ranged = 0 }),
			100 + 35 * asc.hpMult + 20
		),
		"and its own slot's Ascension"
	)
	check(
		A.MaxHp(bare, { melee = 5, ranged = 5 }, { melee = 0, ranged = 0 }) == 100,
		"no ladder: baseHp alone"
	)
	check(A.RangeHp(cfg) == 130, "RangeHp is the range's own 130")
	check(A.RangeHp(bare) == 100, "baseHp without a ladder")
	local noRange = L3.fixture()
	noRange.ladder.rangeHp = 0
	check(A.RangeHp(noRange) == 100, "and with a rangeHp that is not above 0")
	check(
		A.GearPower(cfg, { melee = 1, ranged = 1 }, { melee = 0, ranged = 0 }) == 64,
		`GearPower at T1 / T1 reads 64, today's 2 / 2 ({A.GearPower(
			cfg,
			{ melee = 1, ranged = 1 },
			{ melee = 0, ranged = 0 }
		)})`
	)
	check(
		A.GearPower(cfg, { melee = 3, ranged = 3 }, { melee = 0, ranged = 0 })
			== math.round(4.0837 * 2 * 11 + 230 * 0.2),
		"at T3 / T3: (4.0837 x 2) x tierWeight + 230 x hpWeight, rounded"
	)
	check(
		A.GearPower(cfg, { melee = 1, ranged = 1 }, { melee = 1, ranged = 0 })
			== math.round((1.5 * asc.damageMult + 1.5) * 11 + (100 + 35 * asc.hpMult + 20) * 0.2),
		"the slots' Ascension damageMult and hpMult count"
	)
	local unweighted = L3.fixture()
	unweighted.power.tierWeight = nil
	check(
		A.GearPower(unweighted, { melee = 1, ranged = 1 }, { melee = 0, ranged = 0 }) == 31,
		"no tierWeight: the multipliers weigh 0 (155 x 0.2 = 31)"
	)
	local dmg, hp = A.Preview(cfg, "melee", 5, 24)
	check(
		dmg == math.round(24 * 11.118) and hp == 170,
		`Preview at T5 of a 24-damage hit: {dmg} dmg, HP +{hp}`
	)
	dmg, hp = A.Preview(cfg, "ranged", 1, 45)
	check(dmg == 68 and hp == 20, `a half rounds up (45 x 1.5 = 67.5 -> {dmg}), HP +{hp}`)
end
L1.group("l3 strengthTests", L3.strengthTests)

function L3.costTests(): ()
	print(" Bands and costs (L3-4)")
	local A = L3.Armory
	local cfg = L3.fixture()
	local function band(t: number): string
		local b, p = A.BandOf(cfg, t)
		return `{b}.{p}`
	end
	check(
		band(1) == "1.1"
			and band(4) == "1.4"
			and band(5) == "2.1"
			and band(8) == "2.4"
			and band(20) == "5.4",
		`BandOf: T1 1.1, T4 1.4, T5 2.1, T8 2.4, T20 5.4 ({band(1)}, {band(4)}, {band(5)}, {band(8)}, {band(
			20
		)})`
	)
	check(
		band(0) == "0.0" and band(21) == "0.0" and band(2.5) == "0.0",
		"0, 0 outside the ladder or for a fraction"
	)
	local fractional = L3.fixture()
	fractional.ladder.bandSize = 2.5
	local b = A.BandOf(fractional, 3)
	check(b == 0, "and for a bandSize that is not whole")
	local function cost(t: number): string
		local material, amount = A.TierCost(cfg, t)
		return `{material} {amount}`
	end
	check(
		cost(2) == "Timber 100" and cost(3) == "Timber 250" and cost(4) == "Timber 500",
		`TierCost by position: T2 100, T3 250, T4 500 Timber ({cost(2)}, {cost(3)}, {cost(4)})`
	)
	check(
		cost(1) == "Timber 100",
		"position 1 is priced too (never charged in band 1: no window starts below T1)"
	)
	check(
		cost(5) == "Iron 100" and cost(8) == "Iron 500" and cost(20) == "Crystal 500",
		"a later band charges its own material by the same positions"
	)
	check(cost(0) == " 0" and cost(21) == " 0", '("", 0) outside the ladder')
	local missing = L3.fixture()
	missing.ladder.bands[2] = nil
	local material, amount = A.TierCost(missing, 6)
	check(material == "" and amount == 0, '("", 0) for a band with no entry')
	local short = L3.fixture()
	short.ladder.costs = { 100, 100 }
	material, amount = A.TierCost(short, 3)
	check(material == "" and amount == 0, "and for a position with no cost")
	local negative = L3.fixture()
	negative.ladder.costs[2] = -5
	material = A.TierCost(negative, 2)
	check(material == "", "and for a cost below 0")
end
L1.group("l3 costTests", L3.costTests)

function L3.verdictTests(): ()
	print(" UpgradeVerdict: every reason, in order (L3-5)")
	local A = L3.Armory
	local cfg = L3.fixture()
	local forest = { forestRoad = true }
	local hard = { forestRoad = { hard = true } }
	local function verdict(
		family: string,
		tiers: any,
		materials: any,
		stars: any,
		owned: boolean,
		gate: boolean,
		built: any
	): any
		return A.UpgradeVerdict(
			cfg,
			L3.combat(tiers, materials, stars),
			family,
			owned,
			gate,
			built or forest
		)
	end
	-- Each case lets every LATER reason apply too, so the first in the order must win.
	check(
		verdict("nope", {}, {}, nil, false, false, {}) == "invalid",
		"invalid first: no window (not owned, gate shut, nothing built, no money too)"
	)
	check(
		verdict("broadsword", {}, {}, nil, false, false, {}) == "locked",
		"then locked: not owned"
	)
	check(
		verdict("splitbow", {}, {}, nil, true, false, {}) == "peak",
		"then peak: a relic at its top (8 to 8)"
	)
	check(
		verdict("broadsword", { broadsword = 12 }, {}, nil, true, false, {}) == "peak",
		"and any family at its top"
	)
	check(
		verdict("broadsword", { broadsword = 20 }, {}, nil, true, false, {}) == "peak",
		"and a saved tier above a window that shrank"
	)
	check(
		verdict("broadsword", {}, {}, nil, true, false, {}) == "busy",
		"then busy: the gate is shut"
	)
	check(
		verdict("broadsword", { broadsword = 4 }, {}, nil, true, true, forest) == "notBuilt",
		"then notBuilt: T5 is the Castle's, which has no level file"
	)
	check(
		verdict("broadsword", {}, {}, nil, true, true, {}) == "notBuilt",
		"and T2 when no level file is built at all"
	)
	check(
		verdict("broadsword", { broadsword = 3 }, {}, nil, true, true, forest) == "needsStar",
		"then needsStar: T4 tops its band and needs Forest Road's Hard star"
	)
	check(
		verdict(
			"broadsword",
			{ broadsword = 3 },
			{},
			{ forestRoad = { normal = true } },
			true,
			true,
			forest
		) == "needsStar",
		"a Normal star is not the trophy"
	)
	check(
		verdict(
			"broadsword",
			{ broadsword = 3 },
			{},
			{ forestRoad = { hard = false } },
			true,
			true,
			forest
		) == "needsStar",
		"a star written false is no star"
	)
	check(
		verdict(
			"broadsword",
			{ broadsword = 3 },
			{},
			{ castle = { hard = true } },
			true,
			true,
			forest
		) == "needsStar",
		"another level's Hard star is not this band's"
	)
	-- R1: a Brutal clear opens the band top too (starAlso), with no Hard star written.
	check(
		verdict(
			"broadsword",
			{ broadsword = 3 },
			{ Timber = 500 },
			{ forestRoad = { brutal = true } },
			true,
			true,
			forest
		) == nil,
		"a Brutal star alone opens T4 (starAlso)"
	)
	check(
		verdict(
			"broadsword",
			{ broadsword = 3 },
			{ Timber = 499 },
			{ forestRoad = { brutal = true } },
			true,
			true,
			forest
		) == "insufficientFunds",
		"and the price still applies after it"
	)
	local hardOnly = L3.fixture()
	hardOnly.ladder.starAlso = nil
	check(
		A.UpgradeVerdict(
			hardOnly,
			L3.combat({ broadsword = 3 }, { Timber = 500 }, { forestRoad = { brutal = true } }),
			"broadsword",
			true,
			true,
			forest
		) == "needsStar",
		"without starAlso a Brutal star is not the trophy"
	)
	check(
		A.UpgradeVerdict(
			hardOnly,
			L3.combat({ broadsword = 3 }, { Timber = 500 }, hard),
			"broadsword",
			true,
			true,
			forest
		) == nil,
		"and the Hard star still is"
	)
	check(
		verdict("broadsword", { broadsword = 3 }, { Timber = 499 }, hard, true, true, forest)
			== "insufficientFunds",
		"then insufficientFunds: T4 costs 500 Timber, 499 held"
	)
	check(
		verdict("broadsword", { broadsword = 3 }, { Timber = 500 }, hard, true, true, forest) == nil,
		"500 Timber and the star: T4 may be bought"
	)
	check(
		verdict("broadsword", {}, { Timber = 99 }, nil, true, true, forest) == "insufficientFunds",
		"T2 costs 100: 99 is short"
	)
	check(
		verdict("broadsword", {}, { Timber = 100 }, nil, true, true, forest) == nil,
		"and 100 buys it, no star needed below a band's top"
	)
	check(
		verdict("broadsword", {}, { Timber = L3.NAN }, nil, true, true, forest)
			== "insufficientFunds",
		"a NaN wallet is short"
	)
	check(
		verdict("broadsword", {}, { Iron = 1000 }, nil, true, true, forest) == "insufficientFunds",
		"another material does not pay"
	)
	check(
		verdict("flamethrower", {}, { Timber = 249 }, nil, true, true, forest)
				== "insufficientFunds"
			and verdict("flamethrower", {}, { Timber = 250 }, nil, true, true, forest) == nil,
		"a family starting at 2 pays only from its start: T3, 250"
	)
	check(
		verdict("warhammer", {}, { Timber = 1000 }, nil, true, true, forest) == "needsStar",
		"the Warhammer arrives at T3: its first buy is the band top"
	)
	-- A later band, once its level exists.
	local both = { forestRoad = true, castle = true }
	check(
		verdict("broadsword", { broadsword = 4 }, { Timber = 1000 }, nil, true, true, both)
			== "insufficientFunds",
		"with the Castle built, T5 costs Iron"
	)
	check(
		verdict("broadsword", { broadsword = 4 }, { Iron = 100 }, nil, true, true, both) == nil,
		"100 Iron buys T5: no star below the band top"
	)
	check(
		verdict("broadsword", { broadsword = 7 }, { Iron = 1000 }, hard, true, true, both)
			== "needsStar",
		"T8 needs the CASTLE's Hard star, not the Forest's"
	)
	check(
		verdict(
			"broadsword",
			{ broadsword = 7 },
			{ Iron = 1000 },
			{ castle = { hard = true } },
			true,
			true,
			both
		) == nil,
		"and buys with it"
	)
	-- A tier with no price is never for sale.
	local priceless = L3.fixture()
	priceless.ladder.costs = { 100 }
	check(
		A.UpgradeVerdict(
			priceless,
			L3.combat({}, { Timber = 1e6 }),
			"broadsword",
			true,
			true,
			forest
		) == "notBuilt",
		"a position with no cost reads notBuilt"
	)
	local nameless = L3.fixture()
	nameless.ladder.bands[1].levelId = ""
	check(
		A.UpgradeVerdict(
			nameless,
			L3.combat({}, { Timber = 1e6 }),
			"broadsword",
			true,
			true,
			{ [""] = true }
		) == "notBuilt",
		"and a band that names no level"
	)
	local noDifficulty = L3.fixture()
	noDifficulty.ladder.starDifficulty = nil
	check(
		A.UpgradeVerdict(
			noDifficulty,
			L3.combat({ broadsword = 3 }, { Timber = 1e6 }, { forestRoad = { hard = true } }),
			"broadsword",
			true,
			true,
			forest
		) == "needsStar",
		"no starDifficulty: no band top can be bought (it fails closed)"
	)
	local bare = L3.fixture()
	bare.ladder = nil
	check(
		A.UpgradeVerdict(bare, L3.combat({}, { Timber = 1e6 }), "broadsword", true, true, forest)
			== "invalid",
		"no ladder: invalid"
	)
end
L1.group("l3 verdictTests", L3.verdictTests)

function L3.upgradeTests(): ()
	print(" Upgrade: the verdict, then one write (L3-5, L3-13)")
	local A = L3.Armory
	local cfg = L3.fixture()
	local forest = { forestRoad = true }
	local combat = L3.combat(nil, { Timber = 600, Steel = 4 })
	check(A.Upgrade(cfg, combat, "broadsword", true, true, forest) == nil, "T1 -> T2 is bought")
	check(
		combat.tiers ~= nil and combat.tiers.broadsword == 2 and combat.materials.Timber == 500,
		`it writes the tier once and takes 100 Timber (T{combat.tiers and combat.tiers.broadsword}, {combat.materials.Timber})`
	)
	check(
		combat.materials.Steel == 4 and combat.tiers.longbow == nil,
		"nothing else moves: another material, another family"
	)
	check(
		A.Upgrade(cfg, combat, "broadsword", true, true, forest) == nil
			and combat.tiers.broadsword == 3
			and combat.materials.Timber == 250,
		"T2 -> T3 takes 250"
	)
	local before = L1.copy(combat)
	check(
		A.Upgrade(cfg, combat, "broadsword", true, true, forest) == "needsStar",
		"T3 -> T4 without the Hard star is refused"
	)
	check(L3.same(combat, before), "and the refusal leaves the profile exactly as it was")
	combat.stars = { forestRoad = { hard = true } }
	check(
		A.Upgrade(cfg, combat, "broadsword", true, true, forest) == "insufficientFunds"
			and combat.tiers.broadsword == 3
			and combat.materials.Timber == 250,
		"with the star, 250 Timber does not buy T4 (500): untouched"
	)
	combat.materials.Timber = 500
	check(
		A.Upgrade(cfg, combat, "broadsword", true, true, forest) == nil
			and combat.tiers.broadsword == 4
			and combat.materials.Timber == 0,
		"500 buys T4 and the wallet reads 0, never below"
	)
	check(
		A.Upgrade(cfg, combat, "broadsword", true, true, forest) == "notBuilt"
			and combat.tiers.broadsword == 4,
		"T5 waits for the Castle"
	)
	local shut = L3.combat({}, { Timber = 1000 })
	local copy = L1.copy(shut)
	check(
		A.Upgrade(cfg, shut, "longbow", true, false, forest) == "busy" and L3.same(shut, copy),
		"a shut gate refuses and writes nothing"
	)
	check(
		A.Upgrade(cfg, shut, "longbow", false, true, forest) == "locked" and L3.same(shut, copy),
		"an unowned family too"
	)
	local moved = L3.combat({ longbow = 9 }, { Timber = 100 })
	check(
		A.Upgrade(cfg, moved, "longbow", true, true, forest) == "notBuilt",
		"a saved tier is read through its window (T9 -> T10 is the Underworld's)"
	)
	local lifted = L3.fixture()
	lifted.windows.longbow = { start = 1, top = 3 }
	local stranded = L3.combat({ longbow = 9 }, { Timber = 1000 })
	check(
		A.Upgrade(lifted, stranded, "longbow", true, true, forest) == "peak"
			and stranded.tiers.longbow == 9,
		"a window that shrank under a saved 9: at its top, nothing rewritten"
	)
	local made = L3.combat(nil, { Timber = 250 })
	check(
		A.Upgrade(cfg, made, "flamethrower", true, true, forest) == nil
			and made.tiers.flamethrower == 3
			and made.materials.Timber == 0,
		"a profile with no tiers table gets one; the Flamethrower goes 2 -> 3 for 250"
	)
end
L1.group("l3 upgradeTests", L3.upgradeTests)

function L3.starTests(): ()
	print(" StarHeld: a band top's trophy, Hard or harder (the fix round's R1)")
	local A = L3.Armory
	local cfg = L3.fixture()
	local function holds(stars: any, levelId: string?, config: any?): boolean
		return A.StarHeld(config or cfg, L3.combat(nil, nil, stars), levelId or "forestRoad")
	end
	check(holds({ forestRoad = { hard = true } }), "the Hard star is the trophy")
	check(holds({ forestRoad = { brutal = true } }), "so is the Brutal one (starAlso)")
	check(holds({ forestRoad = { hard = true, brutal = true } }), "and both together")
	check(not holds({ forestRoad = { normal = true } }), "a Normal star is not")
	check(
		not holds({ forestRoad = { hard = false, brutal = false } }),
		"a star written false is no star"
	)
	check(
		not holds({ forestRoad = { hard = 1, brutal = "yes" } } :: any),
		"nor one that is not true"
	)
	check(
		not holds({ castle = { hard = true, brutal = true } }),
		"another level's stars are not this level's"
	)
	check(
		holds({ castle = { brutal = true } }, "castle"),
		"a later band reads its own level's stars"
	)
	check(
		not holds(nil) and not holds({}) and not holds({ forestRoad = 5 } :: any),
		"no stars, none for the level, or a row that is not a table: not held"
	)
	check(not A.StarHeld(cfg, nil, "forestRoad"), "no profile: not held")
	local bare = L3.fixture()
	bare.ladder = nil
	check(not holds({ forestRoad = { hard = true } }, nil, bare), "no ladder: no trophy at all")
	local hardOnly = L3.fixture()
	hardOnly.ladder.starAlso = nil
	check(
		holds({ forestRoad = { hard = true } }, nil, hardOnly)
			and not holds({ forestRoad = { brutal = true } }, nil, hardOnly),
		"without starAlso only the Hard star counts"
	)
	local text = L3.fixture()
	text.ladder.starAlso = "brutal" :: any
	check(
		not holds({ forestRoad = { brutal = true } }, nil, text),
		"a starAlso that is not a list adds nothing"
	)
	local two = L3.fixture()
	two.ladder.starAlso = { "nightmare", "brutal" }
	check(
		holds({ forestRoad = { brutal = true } }, nil, two)
			and holds({ forestRoad = { nightmare = true } }, nil, two),
		"every difficulty starAlso lists counts, in any position"
	)
	local mixed = L3.fixture()
	mixed.ladder.starAlso = { 5, "brutal" } :: any
	check(
		holds({ forestRoad = { brutal = true } }, nil, mixed),
		"an entry that is no name is skipped, the next still read"
	)
	local noHard = L3.fixture()
	noHard.ladder.starDifficulty = nil :: any
	check(
		not holds({ forestRoad = { hard = true } }, nil, noHard)
			and holds({ forestRoad = { brutal = true } }, nil, noHard),
		"no starDifficulty: the Hard star opens nothing, a starAlso one still does (as sim_combat reads it)"
	)
end
L1.group("l3 starTests", L3.starTests)

function L3.strikeTests(): ()
	print(" StrikeTier: the tier a hit and the bar read, a Studio override held in the window (R3)")
	local A = L3.Armory
	local cfg = L3.fixture()
	-- Without an override it IS TierOf, for every family and saved shape the tier rules know.
	local profiles = {
		L3.combat(nil),
		L3.combat({}),
		L3.combat({
			broadsword = 5,
			longbow = 12,
			flamethrower = 1,
			warhammer = 20,
			frostHammer = 7,
			rifle = 4.5,
			smg = "x",
		}),
	}
	local same = true
	for _, combat in profiles do
		for family in L3.WINDOWS do
			same = same and A.StrikeTier(cfg, combat, family, nil) == A.TierOf(cfg, combat, family)
		end
		same = same and A.StrikeTier(cfg, combat, "nope", nil) == 1
	end
	same = same and A.StrikeTier(cfg, nil, "warhammer", nil) == 3
	check(same, "no override: TierOf, for every family, saved tier and no profile at all")
	-- 2-s1: G's T1 preset can never field a weapon below its window, and T5 never above its top.
	local held = true
	for family, pair in L3.WINDOWS do
		held = held and A.StrikeTier(cfg, L3.combat({}), family, 1) == pair[1]
		held = held and A.StrikeTier(cfg, L3.combat({}), family, 20) == pair[2]
		held = held and A.StrikeTier(cfg, L3.combat({}), family, 30) == pair[2]
		held = held and A.StrikeTier(cfg, L3.combat({}), family, 0) == pair[1]
	end
	check(
		held,
		"an override is held inside each family's window: T1 reads its start, T20 and T30 its top, T0 its start"
	)
	check(
		A.StrikeTier(cfg, L3.combat({}), "flamethrower", 1) == 2
			and A.StrikeTier(cfg, L3.combat({}), "frostHammer", 1) == 5,
		"G's T1 fields the Flamethrower at T2 and the Frost Hammer at T5, as the screen shows them"
	)
	check(
		A.StrikeTier(cfg, L3.combat({}), "broadsword", 3) == 3
			and A.StrikeTier(cfg, L3.combat({}), "warhammer", 5) == 5,
		"an override inside the window is the tier"
	)
	check(
		A.StrikeTier(cfg, L3.combat({ broadsword = 9 }), "broadsword", 3) == 3,
		"the override beats the saved tier (it is a session override)"
	)
	check(
		A.StrikeTier(cfg, L3.combat({}), "warhammer", 4.5) == 3
			and A.StrikeTier(cfg, L3.combat({}), "warhammer", L3.NAN) == 3
			and A.StrikeTier(cfg, L3.combat({}), "warhammer", math.huge) == 3,
		"an override that is not a whole number reads the window's start, as a saved one does"
	)
	check(
		A.StrikeTier(cfg, L3.combat({}), "nope", 5) == 1,
		"a family with no window strikes at T1 whatever the override says"
	)
	local bare = L3.fixture()
	bare.ladder = nil
	check(
		A.StrikeTier(bare, L3.combat({}), "broadsword", 5) == 1
			and A.StrikeTier(bare, L3.combat({ broadsword = 4 }), "broadsword", nil) == 1,
		"no ladder: T1, with an override or without"
	)
	check(A.StrikeTier(cfg, nil, "longbow", 4) == 4, "an override needs no profile")
end
L1.group("l3 strikeTests", L3.strikeTests)

function L3.powerTests(): ()
	print(" HeldFamily and SavedPower: the saved pair's Power, the one rule both places read (R7)")
	local A = L3.Armory
	local U = L3.Unlocks
	local weapons = FIXTURES.proving.weapons
	local starters = FIXTURES.proving.loadout
	local fresh = L1.copy(L3.Schema.PROFILE_TEMPLATE.combat)
	check(
		A.SavedPower(ARMORY, fresh, weapons, starters) == 64,
		`a fresh profile reads 64 on the shipped files ({A.SavedPower(
			ARMORY,
			fresh,
			weapons,
			starters
		)})`
	)
	local cfg = L3.fixture()
	check(A.SavedPower(cfg, fresh, weapons, starters) == 64, "and on the contract's fixture")
	check(A.SavedPower(cfg, nil, weapons, starters) == 64, "no profile: T1 / T1, 64")
	check(
		A.SavedPower(cfg, fresh, nil, { melee = "", ranged = "" }) == 64,
		"no ProvingGrounds.json (no family known): T1 / T1, 64"
	)
	local veteran = L1.copy(fresh)
	veteran.gear = { melee = 3, ranged = 3 }
	check(
		A.SavedPower(cfg, veteran, weapons, starters) == 64,
		"the frozen slot gear is never read (3 / 3 there, no tiers saved: still 64)"
	)
	local none = { melee = 0, ranged = 0 }
	local function power(tiers: any, loadout: any, families: any, ascension: any): number
		local combat = L3.combat(tiers)
		combat.loadout = loadout
		combat.families = families
		combat.ascension = ascension or none
		return A.SavedPower(cfg, combat, weapons, starters)
	end
	check(
		power({ broadsword = 3 }, nil, {}) == A.GearPower(cfg, { melee = 3, ranged = 1 }, none),
		"an upgraded starter moves it (Broadsword T3)"
	)
	check(
		power({}, { ranged = "flamethrower", variants = {} }, { flamethrower = true })
			== A.GearPower(cfg, { melee = 1, ranged = 2 }, none),
		"a held Flamethrower reads its window's start, T2"
	)
	check(
		power({}, { ranged = "flamethrower", variants = {} }, {}) == 64,
		"a saved family not owned reads the starter"
	)
	check(
		power({ longbow = 4 }, { ranged = "flamethrower", variants = {} }, {})
			== A.GearPower(cfg, { melee = 1, ranged = 4 }, none),
		"and the starter's own tier"
	)
	check(
		power({}, nil, {}, { melee = 1, ranged = 0 })
			== A.GearPower(cfg, { melee = 1, ranged = 1 }, { melee = 1, ranged = 0 }),
		"the slots' Ascension counts"
	)
	-- The two readings of a saved pair never disagree: the hub's old two lines, and SavedPower.
	local agree = true
	local shapes = 0
	local loadouts = {
		false,
		{ variants = {} },
		{ melee = "warhammer", ranged = "flamethrower", variants = {} },
		{ melee = "longbow", ranged = "broadsword", variants = {} },
		{ melee = "nope", ranged = 5, variants = {} },
		"x",
	}
	local familySets = { {}, { warhammer = true, flamethrower = true }, { warhammer = false } }
	local tierSets = { {}, { broadsword = 4, warhammer = 9, flamethrower = 7, longbow = 2 } }
	for _, loadout in loadouts do
		for _, families in familySets do
			for _, tiers in tierSets do
				local combat = L3.combat(tiers)
				combat.loadout = if loadout == false then nil else loadout
				combat.families = families
				local held = U.LoadoutOf(combat, weapons, starters)
				local expected =
					A.GearPower(cfg, A.HeldTiers(cfg, combat, held.melee, held.ranged), none)
				agree = agree and A.SavedPower(cfg, combat, weapons, starters) == expected
				agree = agree and A.HeldFamily(combat, weapons, starters, "melee") == held.melee
				agree = agree and A.HeldFamily(combat, weapons, starters, "ranged") == held.ranged
				shapes += 1
			end
		end
	end
	check(
		agree and shapes == 36,
		`SavedPower is GearPower at the tiers of LoadoutOf's pair, and HeldFamily is LoadoutOf's slot, over {shapes} saved shapes`
	)
	check(
		A.HeldFamily(fresh, weapons, starters, "nope") == ""
			and A.HeldFamily(fresh, weapons, starters, "melee") == starters.melee,
		"HeldFamily: empty for a slot that is not melee or ranged, the starter for a fresh profile"
	)
end
L1.group("l3 powerTests", L3.powerTests)

-- Every table reached from `value`, by identity.
function L3.tables(value: any, into: any): any
	into = into or {}
	if type(value) == "table" and not into[value] then
		into[value] = true
		for _, item in value do
			L3.tables(item, into)
		end
	end
	return into
end

-- Every key path of `template` (recursively) that `copy` lacks, as "a.b".
function L3.missingPaths(template: any, copy: any, prefix: string, into: any): any
	into = into or {}
	for key, value in template do
		local path = if prefix == "" then tostring(key) else `{prefix}.{key}`
		if type(copy) ~= "table" or copy[key] == nil then
			table.insert(into, path)
		elseif type(value) == "table" then
			L3.missingPaths(value, copy[key], path, into)
		end
	end
	return into
end

function L3.copyTests(): ()
	print(" ProfileCopy: the hub's Delta copy carries every field and shares no table (R7)")
	local Copy = L3.Copy
	local template = L3.Schema.PROFILE_TEMPLATE.combat
	-- The template as a profile holds it, every map with an entry, so a dropped or aliased field at
	-- any depth shows.
	local source = L1.copy(template)
	source.materials.Timber = 40
	source.missions.village = { bestWave = 4, bossClears = 1, overdriveBest = 0 }
	source.abilities.doubleJump = true
	source.secrets.forestRoad = { lookout = true }
	source.families.flamethrower = true
	source.shortcuts.forestRoad = { cave = true }
	source.tiers.broadsword = 3
	source.loadout = { melee = "warhammer", ranged = "flamethrower", variants = { longbow = "B" } }
	source.stars.forestRoad = { hard = true }
	local copy = Copy.Combat(source)
	local missing = L3.missingPaths(template, copy, "")
	check(
		#missing == 0,
		`every key of ProfileSchema's template combat, at every depth, is in the copy (missing: {table.concat(
			missing,
			", "
		)})`
	)
	local deeper = L3.missingPaths(source, copy, "")
	check(
		#deeper == 0 and L3.same(copy, source),
		`and every entry a profile holds, equal (missing: {table.concat(deeper, ", ")})`
	)
	local mine = L3.tables(source)
	local shared = 0
	for item in L3.tables(copy) do
		if mine[item] then
			shared += 1
		end
	end
	check(shared == 0, `the copy shares no table with the profile ({shared} shared)`)
	copy.stars.forestRoad.hard = false
	copy.loadout.variants.longbow = "A"
	copy.materials.Timber = 0
	check(
		source.stars.forestRoad.hard == true
			and source.loadout.variants.longbow == "B"
			and source.materials.Timber == 40,
		"writing the copy changes nothing in the profile"
	)
	local later = L1.copy(source)
	later.relics = { castle = { crown = true } }
	local laterCopy = Copy.Combat(later)
	check(
		laterCopy.relics ~= nil
			and laterCopy.relics ~= later.relics
			and laterCopy.relics.castle.crown == true,
		"a field a later schema adds rides along without an edit (a v9 map)"
	)
	local half = L1.copy(source)
	half.loadout = { melee = "warhammer" }
	local halfCopy = Copy.Combat(half)
	check(
		type(halfCopy.loadout.variants) == "table"
			and halfCopy.loadout.melee == "warhammer"
			and half.loadout.variants == nil,
		"a loadout without its variants is copied with an empty one; the profile is not touched"
	)
	local old = L1.copy(source)
	old.tiers = nil
	old.loadout = nil
	old.stars = nil
	local oldCopy = Copy.Combat(old)
	check(
		oldCopy.tiers == nil
			and oldCopy.loadout == nil
			and oldCopy.stars == nil
			and oldCopy.families.flamethrower == true,
		"a field the profile lacks stays nil (a v7 profile's copy)"
	)
end
L1.group("l3 copyTests", L3.copyTests)

function L3.leverTests(): ()
	print(" The Armory levers' shared pieces (L3-28) and the refund rule (L3-8)")
	local A = L3.Armory
	local U = L3.Unlocks
	local cfg = L3.fixture()
	local combat = L3.combat(nil)
	check(
		A.SetTier(cfg, combat, "broadsword", 15) == 12 and combat.tiers.broadsword == 12,
		"SetTier holds a tier to the window (15 -> 12)"
	)
	check(
		A.SetTier(cfg, combat, "flamethrower", 1) == 2 and combat.tiers.flamethrower == 2,
		"and below its start (1 -> 2)"
	)
	check(A.SetTier(cfg, combat, "warhammer", 5.6) == 5, "a fraction rounds down")
	check(
		A.SetTier(cfg, combat, "nope", 4) == nil and combat.tiers.nope == nil,
		"a family with no window: nothing written"
	)
	check(
		A.SetTier(cfg, combat, "longbow", L3.NAN) == nil
			and A.SetTier(cfg, combat, "longbow", math.huge) == nil
			and combat.tiers.longbow == nil,
		"a NaN or infinite tier: nothing written"
	)
	local levels, materials = A.BuiltBands(cfg, { forestRoad = true })
	check(
		#levels == 1 and levels[1] == "forestRoad" and #materials == 1 and materials[1] == "Timber",
		"BuiltBands with Forest Road built: its level and Timber"
	)
	levels, materials = A.BuiltBands(cfg, { forestRoad = true, castle = true, nope = true })
	check(
		#levels == 2 and levels[2] == "castle" and #materials == 2 and materials[2] == "Iron",
		"the Castle built too: in band order"
	)
	local shared = L3.fixture()
	shared.ladder.bands[2].material = "Timber"
	levels, materials = A.BuiltBands(shared, { forestRoad = true, castle = true })
	check(#levels == 2 and #materials == 1, "a material two bands share is listed once")
	levels, materials = A.BuiltBands(cfg, {})
	check(#levels == 0 and #materials == 0, "nothing built: nothing")
	local bare = L3.fixture()
	bare.ladder = nil
	levels = A.BuiltBands(bare, { forestRoad = true })
	check(#levels == 0, "no ladder: nothing")

	local family, tier = U.TierLever("longbow=4")
	check(family == "longbow" and tier == 4, 'TierLever reads "longbow=4"')
	family, tier = U.TierLever("frostHammer=12")
	check(family == "frostHammer" and tier == 12, "and a camel-cased id")
	local refused = {
		"longbow=",
		"=4",
		"longbow=4.5",
		"longbow=-1",
		"a b=3",
		"longbow:4",
		string.rep("f", 25) .. "=3",
		"",
	}
	local allRefused = true
	for _, value in refused do
		family, tier = U.TierLever(value)
		allRefused = allRefused and family == nil and tier == nil
	end
	family = U.TierLever(7)
	check(
		allRefused and family == nil,
		"anything else reads nothing: no tier, a fraction, a sign, a space, a colon, a 25-byte id, empty, a number"
	)

	-- LegacyRefund (L3-8, the frozen prices).
	local function refund(melee: any, ranged: any): any
		return A.LegacyRefund(cfg, { melee = melee, ranged = ranged })
	end
	check(next(refund(0, 0)) == nil, "0 / 0: nothing back")
	check(
		L3.same(refund(3, 3), { Timber = 500 }),
		"3 / 3 (the most a live profile holds): 500 Timber"
	)
	check(L3.same(refund(2, 1), { Timber = 80 }), "2 / 1: 70 + 10 Timber")
	check(
		L3.same(refund(4, 2), { Timber = 320, Steel = 10 }),
		"4 / 2: 250 + 70 Timber and 10 Steel (L3-38)"
	)
	check(
		L3.same(refund(12, 12), { Timber = 500, Steel = 500, Circuits = 500, Alloy = 500 }),
		"12 / 12: every band back"
	)
	check(
		L3.same(refund(13, 0), { Timber = 250, Steel = 250, Circuits = 250, Alloy = 250 }),
		"a tier past the list is capped at its length"
	)
	check(
		L3.same(refund(-1, 2), { Timber = 70 }) and L3.same(refund(2.5, 1), { Timber = 10 }),
		"a negative tier or a fraction gives nothing for its slot"
	)
	check(
		L3.same(refund(L3.NAN, 1), { Timber = 10 }) and L3.same(refund("3", 1), { Timber = 10 }),
		"a NaN or a string tier gives nothing"
	)
	local noLegacy = L3.fixture()
	noLegacy.legacy = nil
	check(
		next(A.LegacyRefund(noLegacy, { melee = 3, ranged = 3 })) == nil,
		"no legacy list: nothing back"
	)
	local broken = L3.fixture()
	broken.legacy.gearCosts[2] = { material = "", amount = 60 }
	broken.legacy.gearCosts[3] = { material = "Timber", amount = -180 }
	check(
		L3.same(A.LegacyRefund(broken, { melee = 3, ranged = 0 }), { Timber = 10 }),
		"an entry with no material or a negative amount adds nothing"
	)
	local first = refund(3, 3)
	first.Timber = 1
	check(
		refund(3, 3).Timber == 500 and cfg.legacy.gearCosts[1].amount == 10,
		"a fresh table each call: writing it changes nothing in the config"
	)
end
L1.group("l3 leverTests", L3.leverTests)

function L3.problemTests(): ()
	print(" Problems: the validator, each rule named by its own break (L3-5, the fix round's R6)")
	local A = L3.Armory
	local families = L3.families()
	local sound = A.Problems(L3.fixture(), families)
	check(
		#sound == 0,
		`the contract's ladder and windows are sound ({#sound} lines{if #sound > 0
			then ": " .. sound[1]
			else ""})`
	)
	-- Each break names the rule it breaks: the line that rule writes must be among the answers, so
	-- a rule that went quiet cannot hide behind a second rule the same break also trips (R6).
	local breaks = {
		{
			"no ladder",
			function(c)
				c.ladder = nil
			end,
			"has no ladder",
		},
		{
			"a damage list that is not a list",
			function(c)
				c.ladder.damage = 5
			end,
			"ladder.damage is not a list",
		},
		{
			"a damage entry that does not rise",
			function(c)
				c.ladder.damage[5] = c.ladder.damage[4]
			end,
			"ladder.damage[5] (6.7382) does not rise",
		},
		{
			"a damage entry of 0",
			function(c)
				c.ladder.damage[1] = 0
			end,
			"ladder.damage[1] is 0, not a number above 0",
		},
		{
			"a melee HP list one short",
			function(c)
				table.remove(c.ladder.hp.melee)
			end,
			"ladder.hp.melee is not a list of 20 numbers",
		},
		{
			"a ranged HP entry that falls",
			function(c)
				c.ladder.hp.ranged[6] = 1
			end,
			"ladder.hp.ranged[6] (1) falls below ladder.hp.ranged[5] (110)",
		},
		-- 85 at T3 and T4 keeps the ranged list rising, so only the melee rule can name it.
		{
			"ranged above melee at one tier",
			function(c)
				c.ladder.hp.ranged[3] = 85
				c.ladder.hp.ranged[4] = 85
			end,
			"ladder.hp.melee[3] (80) is below ladder.hp.ranged[3] (85)",
		},
		{
			"a negative melee HP entry",
			function(c)
				c.ladder.hp.melee[1] = -1
			end,
			"ladder.hp.melee[1] is -1, not a number of at least 0",
		},
		-- R6 (1-m2): melee stays above it and the list still rises, so only the negative rule names it.
		{
			"a negative ranged HP entry",
			function(c)
				c.ladder.hp.ranged[1] = -1
			end,
			"ladder.hp.ranged[1] is -1, not a number of at least 0",
			true,
		},
		{
			"a rangeHp of 0",
			function(c)
				c.ladder.rangeHp = 0
			end,
			"ladder.rangeHp is 0",
		},
		{
			"bandSize 3",
			function(c)
				c.ladder.bandSize = 3
			end,
			"do not cover the 20 tiers",
		},
		{
			"bandSize 0",
			function(c)
				c.ladder.bandSize = 0
			end,
			"ladder.bandSize is 0, not a whole number above 0",
		},
		-- R6: not whole, so the costs rule is skipped and the cover rule sits behind this one.
		{
			"bandSize 4.5",
			function(c)
				c.ladder.bandSize = 4.5
			end,
			"ladder.bandSize is 4.5, not a whole number above 0",
			true,
		},
		-- R6: four bands of four for 20 tiers; every other rule holds.
		{
			"one band removed",
			function(c)
				table.remove(c.ladder.bands)
			end,
			"ladder.bands and bandSize do not cover the 20 tiers",
			true,
		},
		{
			"a band with no material",
			function(c)
				c.ladder.bands[2].material = ""
			end,
			"ladder.bands[2] (castle) names no material",
		},
		{
			"a band with no level",
			function(c)
				c.ladder.bands[3].levelId = nil
			end,
			"ladder.bands[3] names no level",
		},
		{
			"three costs for four positions",
			function(c)
				table.remove(c.ladder.costs)
			end,
			"ladder.costs is not one cost per position",
		},
		{
			"a negative cost",
			function(c)
				c.ladder.costs[2] = -1
			end,
			"ladder.costs[2] is -1",
		},
		{
			"no starDifficulty",
			function(c)
				c.ladder.starDifficulty = ""
			end,
			"ladder.starDifficulty names no difficulty",
		},
		-- R1: starAlso is a list of difficulty names, or absent.
		{
			"a starAlso that is a word",
			function(c)
				c.ladder.starAlso = "brutal"
			end,
			"ladder.starAlso is not a list of difficulty names",
			true,
		},
		{
			"a starAlso with an empty name",
			function(c)
				c.ladder.starAlso = { "brutal", "" }
			end,
			"ladder.starAlso is not a list of difficulty names",
			true,
		},
		{
			"a starAlso with a number",
			function(c)
				c.ladder.starAlso = { 5 }
			end,
			"ladder.starAlso is not a list of difficulty names",
			true,
		},
		{
			"a starAlso keyed by name",
			function(c)
				c.ladder.starAlso = { brutal = "brutal" }
			end,
			"ladder.starAlso is not a list of difficulty names",
			true,
		},
		{
			"a family without a window",
			function(c)
				c.windows.spear = nil
			end,
			'windows has no entry for "spear"',
		},
		{
			"a window naming no family",
			function(c)
				c.windows.nope = { start = 1, top = 2 }
			end,
			"windows.nope names no weapon family",
		},
		{
			"a window whose start is above its top",
			function(c)
				c.windows.rifle = { start = 18, top = 11 }
			end,
			"windows.rifle (18 to 11)",
		},
		{
			"a window starting at 0",
			function(c)
				c.windows.rifle = { start = 0, top = 11 }
			end,
			"windows.rifle (0 to 11)",
		},
		{
			"a window past the ladder",
			function(c)
				c.windows.rifle = { start = 11, top = 25 }
			end,
			"windows.rifle (11 to 25)",
		},
		{
			"a fractional window",
			function(c)
				c.windows.rifle = { start = 11.5, top = 18 }
			end,
			"windows.rifle (11.5 to 18)",
		},
		{
			"no legacy list",
			function(c)
				c.legacy = nil
			end,
			"has no legacy.gearCosts",
		},
		{
			"a legacy entry with no material",
			function(c)
				c.legacy.gearCosts[4].material = ""
			end,
			"legacy.gearCosts[4] is not a material",
		},
		{
			"a tierWeight that is a string",
			function(c)
				c.power.tierWeight = "11"
			end,
			"power.tierWeight is not a number",
		},
	}
	for _, case in breaks do
		local cfg = L3.fixture()
		case[2](cfg)
		local lines = A.Problems(cfg, families)
		local named = false
		for _, line in lines do
			named = named or string.find(line, case[3], 1, true) ~= nil
		end
		-- The breaks R6 added name exactly one line: no second rule could stand in for theirs.
		local alone = case[4] ~= true or #lines == 1
		check(
			named and alone,
			`{case[1]}: named by its rule ({#lines} line(s){if #lines > 0
				then ": " .. lines[1]
				else ""})`
		)
	end
	local listed = L3.fixture()
	listed.ladder.starAlso = {}
	local none = L3.fixture()
	none.ladder.starAlso = nil
	check(
		#A.Problems(listed, families) == 0 and #A.Problems(none, families) == 0,
		"an empty starAlso, or none, is sound"
	)
end
L1.group("l3 problemTests", L3.problemTests)

function L3.loadoutTests(): ()
	print(" Unlocks: the saved loadout and stars (L3-9, L3-10)")
	local U = L3.Unlocks
	local weapons = FIXTURES.proving.weapons
	local fallback = FIXTURES.proving.loadout
	local function combat(loadout: any, families: any): any
		local made = L3.combat(nil)
		made.loadout = loadout
		made.families = families
		return made
	end
	local function held(c: any): string
		local loadout = U.LoadoutOf(c, weapons, fallback)
		return `{loadout.melee}/{loadout.ranged}`
	end
	check(held(nil) == "broadsword/longbow", "no profile: the starters")
	check(held(combat(nil, {})) == "broadsword/longbow", "nothing saved: the starters")
	check(
		held(combat({ variants = {} }, {})) == "broadsword/longbow",
		"an empty loadout: the starters"
	)
	check(
		held(combat({ melee = "warhammer", variants = {} }, {})) == "broadsword/longbow",
		"a saved family not owned falls back to the slot's starter"
	)
	check(
		held(combat({ melee = "warhammer", variants = {} }, { warhammer = true }))
			== "warhammer/longbow",
		"owned, it is held"
	)
	check(
		held(combat({ melee = "warhammer", variants = {} }, { warhammer = false }))
			== "broadsword/longbow",
		"a family written false is not owned"
	)
	check(
		held(combat({ melee = "longbow", ranged = "broadsword", variants = {} }, {}))
			== "broadsword/longbow",
		"a family in the wrong slot falls back, starter or not"
	)
	check(
		held(combat({ ranged = "nope", variants = {} }, { nope = true })) == "broadsword/longbow",
		"an unknown family falls back, whatever the profile claims"
	)
	check(
		held(combat({ ranged = "flamethrower", variants = {} }, { flamethrower = true }))
			== "broadsword/flamethrower",
		"a found ranged family is held in its slot"
	)
	check(
		held(combat({ melee = 5, ranged = true, variants = {} }, {})) == "broadsword/longbow",
		"a slot that is not a string falls back"
	)
	check(
		held(combat("x", {})) == "broadsword/longbow",
		"a loadout that is not a table falls back whole"
	)
	local loadout = U.LoadoutOf(
		combat({
			melee = "broadsword",
			variants = {
				longbow = "B",
				broadsword = "Z",
				nope = "A",
				spear = "A",
				greataxe = 2,
			},
		}, {}),
		weapons,
		fallback
	)
	check(
		loadout.variants.longbow == "B" and loadout.variants.spear == "A",
		"a saved style whose family and key exist is kept (owning it is not required)"
	)
	check(
		loadout.variants.broadsword == nil
			and loadout.variants.nope == nil
			and loadout.variants.greataxe == nil,
		"an unknown style, an unknown family or a key that is no string is dropped (the family's default plays)"
	)
	local saved = combat({ melee = "broadsword", variants = { longbow = "B" } }, {})
	local read = U.LoadoutOf(saved, weapons, fallback)
	read.variants.longbow = "A"
	read.melee = "warhammer"
	check(
		saved.loadout.variants.longbow == "B" and saved.loadout.melee == "broadsword",
		"a fresh table: writing what LoadoutOf gave changes nothing saved"
	)
	local blind = U.LoadoutOf(
		combat({ melee = "warhammer", variants = { longbow = "B" } }, { warhammer = true }),
		nil,
		fallback
	)
	check(
		blind.melee == "broadsword" and blind.ranged == "longbow" and next(blind.variants) == nil,
		"no weapons config: the fallback, and no styles"
	)

	-- SaveLoadout.
	local fresh = combat(nil, {})
	U.SaveLoadout(fresh, "melee", "warhammer", "A")
	check(
		fresh.loadout ~= nil
			and fresh.loadout.melee == "warhammer"
			and fresh.loadout.ranged == nil
			and fresh.loadout.variants.warhammer == "A",
		"SaveLoadout makes the loadout when there is none and writes the slot and its style"
	)
	U.SaveLoadout(fresh, "ranged", "longbow", "B")
	check(
		fresh.loadout.ranged == "longbow"
			and fresh.loadout.melee == "warhammer"
			and fresh.loadout.variants.longbow == "B",
		"the other slot keeps what it holds"
	)
	local half = combat({ melee = "warhammer" }, {})
	U.SaveLoadout(half, "ranged", "longbow", "A")
	check(
		type(half.loadout.variants) == "table"
			and half.loadout.variants.longbow == "A"
			and half.loadout.melee == "warhammer",
		"a loadout without its variants gets them"
	)
	local untouched = combat(nil, {})
	U.SaveLoadout(untouched, "nope", "warhammer", "A")
	check(untouched.loadout == nil, "a slot other than melee and ranged writes nothing")
	local roundTrip = combat(nil, { warhammer = true })
	U.SaveLoadout(roundTrip, "melee", "warhammer", "A")
	U.SaveLoadout(roundTrip, "ranged", "longbow", "B")
	local back = U.LoadoutOf(roundTrip, weapons, fallback)
	check(
		back.melee == "warhammer" and back.ranged == "longbow" and back.variants.longbow == "B",
		"what is saved is what is read back"
	)

	-- StarsOf, ResetArmory.
	local starless = L3.combat(nil)
	local stars = U.StarsOf(starless)
	check(
		type(stars) == "table" and starless.stars == stars,
		"StarsOf makes the table when there is none"
	)
	stars.forestRoad = { hard = true }
	check(
		U.StarsOf(starless) == stars and U.StarsOf(starless).forestRoad.hard == true,
		"and returns the profile's own after"
	)
	local full = L3.combat({ broadsword = 4 }, { Timber = 30 }, { forestRoad = { hard = true } })
	full.valor = 9
	full.families = { warhammer = true }
	full.secrets = { forestRoad = { lookout = true } }
	full.loadout = { melee = "warhammer", variants = { warhammer = "A" } }
	local oldTiers = full.tiers
	U.ResetArmory(full)
	check(
		next(full.tiers) == nil
			and next(full.stars) == nil
			and full.loadout.melee == nil
			and next(full.loadout.variants) == nil,
		"ResetArmory empties tiers, loadout and stars"
	)
	check(full.tiers ~= oldTiers and oldTiers.broadsword == 4, "with fresh tables")
	check(
		full.materials.Timber == 30
			and full.valor == 9
			and full.families.warhammer == true
			and full.secrets.forestRoad.lookout == true,
		"materials, Valor, families and secrets stay"
	)
end
L1.group("l3 loadoutTests", L3.loadoutTests)

-- The fix round 2's F2: a new star's first-clear reward, written by the one pure rule the dungeon
-- (UnlockService.GrantFirstClear, from EndRun and U) and the hub's star lever both call.
function L3.firstClearTests(): ()
	print(
		" Unlocks.ApplyFirstClear: a new star's first-clear reward, as EndRun, U and the hub's star lever give it (F2)"
	)
	local U = L3.Unlocks
	local Flow = load("StageFlow")
	local weapons = FIXTURES.proving.weapons
	local starters = U.Starters(FIXTURES.proving.loadout)
	local function grant(families: any, reward: any): (any, any)
		local combat = L3.combat(nil)
		combat.valor = 5
		combat.families = families
		return U.ApplyFirstClear(combat, reward, weapons, starters), combat
	end
	local given, combat = grant({}, { family = "warhammer" })
	check(
		given.family == "warhammer"
			and given.valor == 0
			and combat.families.warhammer == true
			and combat.valor == 5,
		"fresh: the family is written to the profile's families, and said given"
	)
	given, combat = grant({}, { family = "warhammer", valor = 20 })
	check(
		given.family == "warhammer"
			and given.valor == 20
			and combat.families.warhammer == true
			and combat.valor == 25,
		"a family and Valor: both given"
	)
	given, combat = grant({ warhammer = true }, { family = "warhammer", valor = 3 })
	check(
		given.family == nil
			and given.valor == 3
			and combat.families.warhammer == true
			and combat.valor == 8,
		"owned: the family is not given again; its Valor still is"
	)
	given, combat = grant({}, { family = "broadsword" })
	check(
		given.family == nil and given.valor == 0 and combat.families.broadsword == nil,
		"a starter is never written (L2-1)"
	)
	given, combat = grant({}, { valor = 25 })
	check(
		given.family == nil
			and given.valor == 25
			and combat.valor == 30
			and next(combat.families) == nil,
		"Valor only: the Valor added, no family"
	)
	given, combat = grant({}, { family = "nope" })
	check(
		given.family == nil and combat.families.nope == nil,
		"a family no weapons config names is not written"
	)
	given, combat = grant(nil, { family = "warhammer" })
	check(
		given.family == "warhammer"
			and type(combat.families) == "table"
			and combat.families.warhammer == true,
		"a profile without families gets them"
	)
	local blind = L3.combat(nil)
	local blindGiven = U.ApplyFirstClear(blind, { family = "warhammer", valor = 2 }, nil, starters)
	check(
		blindGiven.family == nil
			and blindGiven.valor == 2
			and blind.valor == 2
			and next(blind.families) == nil,
		"no weapons config: no family, the Valor still"
	)
	local refused = true
	for _, valor in { 2.5, -1, 0, L3.NAN, math.huge, -math.huge, "25", true } do
		local paid, after = grant({}, { valor = valor })
		refused = refused and paid.valor == 0 and paid.family == nil and after.valor == 5
	end
	check(
		refused,
		"a Valor that is not a whole number above 0 (2.5, -1, 0, NaN, both infinities, a string, a boolean) pays nothing"
	)
	local shapes = true
	for _, family in { "", 5, true, {} } do
		local paid, after = grant({}, { family = family })
		shapes = shapes and paid.family == nil and next(after.families) == nil
	end
	check(
		shapes,
		'a family that is no non-empty string ("", a number, a boolean, a table) is not written'
	)
	local ok, odd = pcall(function()
		return U.ApplyFirstClear(L3.combat(nil), 5 :: any, weapons, starters)
	end)
	check(
		ok and odd.family == nil and odd.valor == 0,
		`a reward that is no table gives nothing and does not throw ({tostring(odd)})`
	)
	-- The hub hands it the level file's raw entry, the dungeon StageFlow.FirstClear's reading of it:
	-- for every shape both give the same, and leave the profile the same.
	local alike = {}
	for _, raw in
		{
			{ family = "warhammer" },
			{ family = "warhammer", valor = 4 },
			{ valor = 25 },
			{ valor = 2.5 },
			{ valor = 0 },
			{ valor = -3 },
			{ valor = "25" },
			{ family = "" },
			{ family = 5, valor = 2 },
			{ family = "broadsword", valor = 1 },
			{ family = "nope" },
			{},
		}
	do
		local level = L1.level()
		level.difficulties.hard.firstClear = L1.copy(raw)
		local read = Flow.FirstClear(level, "hard")
		local hubGiven, hub = grant({}, L1.copy(raw))
		local dungeonGiven, dungeon
		if read ~= nil then
			dungeonGiven, dungeon = grant({}, read)
		else
			-- No reward read: GrantFirstClear is never asked, so the profile is as it was.
			dungeonGiven, dungeon = { valor = 0 }, L3.combat(nil)
			dungeon.valor = 5
		end
		if not (L3.same(hubGiven, dungeonGiven) and L3.same(hub, dungeon)) then
			table.insert(alike, `{tostring(raw.family)}/{tostring(raw.valor)}`)
		end
	end
	check(
		#alike == 0,
		`the level file's raw firstClear gives what StageFlow.FirstClear's reading of it gives ({table.concat(
			alike,
			", "
		)})`
	)
end
L1.group("l3 firstClearTests", L3.firstClearTests)

-- A PlayerState as a v7 profile has it, before the v8 step: the v7 maps, no tiers, loadout or
-- stars, and slot tiers bought before L3.
function L3.v7(melee: number, ranged: number, timber: number): any
	local state = L2.v6()
	state.version = 7
	local combat = state.combat
	combat.abilities = { doubleJump = true }
	combat.secrets = {}
	combat.families = { flamethrower = true }
	combat.shortcuts = {}
	combat.gear = { melee = melee, ranged = ranged }
	combat.materials = { Timber = timber }
	return state
end

-- Runs `fn` with Catalog.GetArmoryConfig answering `cfg`, then puts the stub back.
function L3.withArmory(cfg: any, fn: () -> ()): ()
	local catalog = modules.Catalog
	local real = catalog.GetArmoryConfig
	catalog.GetArmoryConfig = function()
		return cfg
	end
	local ok, problem = pcall(fn)
	catalog.GetArmoryConfig = real
	if not ok then
		error(problem, 0)
	end
end

function L3.schemaTests(): ()
	print(
		" ProfileSchema v8: tiers, the loadout and stars, and the slot tiers refunded once (L3-7, L3-8)"
	)
	local Schema = L3.Schema
	local template = Schema.PROFILE_TEMPLATE
	local combat = template.combat
	check(
		Schema.SCHEMA_VERSION == 8 and template.version == 8,
		`the schema is v8 and the template says so ({Schema.SCHEMA_VERSION}, {template.version})`
	)
	check(type(Schema.Migrations[7]) == "function", "a step from v7 exists")
	check(
		L2.empty(combat.tiers) and L2.empty(combat.stars),
		"a fresh profile's combat holds empty tiers and stars"
	)
	check(
		type(combat.loadout) == "table"
			and combat.loadout.melee == nil
			and combat.loadout.ranged == nil
			and L2.empty(combat.loadout.variants),
		"and a loadout that names no family (the starters come from the config when read)"
	)
	check(
		combat.gear.melee == 0 and combat.gear.ranged == 0,
		"gear stays in the template, frozen at 0 / 0"
	)

	L3.withArmory(L3.fixture(), function()
		-- A v7 profile nothing reconciled, with the most a live profile holds (3 / 3).
		local state = L3.v7(3, 3, 5)
		L2.migrate(state)
		local mine = state.combat
		check(state.version == 8, `a v7 profile reaches v8 ({state.version})`)
		check(
			L2.empty(mine.tiers)
				and L2.empty(mine.stars)
				and type(mine.loadout) == "table"
				and L2.empty(mine.loadout.variants),
			"it gains the three fields, empty: the starters start at their windows' start"
		)
		check(
			mine.tiers ~= combat.tiers
				and mine.stars ~= combat.stars
				and mine.loadout ~= combat.loadout
				and mine.loadout.variants ~= combat.loadout.variants,
			"none of them is the template's own table (no aliasing)"
		)
		check(mine.tiers ~= mine.stars, "and each is a table of its own")
		check(
			mine.materials.Timber == 505,
			`its 3 / 3 slot tiers are paid back: 5 + 500 Timber ({mine.materials.Timber})`
		)
		check(
			mine.gear.melee == 3 and mine.gear.ranged == 3,
			"gear is left as it is (live v7 code still reads it)"
		)
		check(
			mine.abilities.doubleJump == true
				and mine.families.flamethrower == true
				and mine.valor == 7
				and mine.stats.kills == 4,
			"everything else is untouched"
		)
		mine.tiers.broadsword = 2
		check(
			combat.tiers.broadsword == nil,
			"writing the migrated tiers leaves the template empty"
		)

		-- Exactly once through the runner (ProfileSchema.Run, the one DataService calls): the stamp, not
		-- the step, is what stops a second pay.
		check(
			Schema.Run(state) == nil and state.version == 8 and mine.materials.Timber == 505,
			"run through the runner again, it is not paid twice and says nothing"
		)
		local second = L3.v7(3, 3, 5)
		local step = Schema.Migrations[7]
		step(second)
		step(second)
		check(
			second.combat.materials.Timber == 1005,
			"the step alone is NOT safe to run twice (it pays again): only the version stamp guards it"
		)

		-- Reconciled first (ProfileStore's order): Reconcile puts copies in; the step keeps them
		-- and still pays once.
		local reconciled = L3.v7(1, 0, 0)
		L2.reconcile(reconciled, template)
		local filled = reconciled.combat.tiers
		check(
			filled ~= nil and filled ~= combat.tiers and reconciled.combat.loadout ~= combat.loadout,
			"Reconcile fills the three fields from deep copies of the template"
		)
		filled.warhammer = 3
		L2.migrate(reconciled)
		check(
			reconciled.version == 8 and reconciled.combat.tiers == filled and filled.warhammer == 3,
			"a reconciled profile keeps the tables it has, and what is in them"
		)
		check(
			reconciled.combat.materials.Timber == 10,
			`and is paid once for its 1 / 0 (10 Timber: {reconciled.combat.materials.Timber})`
		)

		-- A loadout without its variants (written by hand) gets them; one with them keeps them.
		local half = L3.v7(0, 0, 0)
		half.combat.loadout = { melee = "warhammer" }
		L2.migrate(half)
		check(
			half.combat.loadout.melee == "warhammer"
				and type(half.combat.loadout.variants) == "table",
			"a loadout without its variants gets them, and keeps its family"
		)
		local kept = L3.v7(0, 0, 0)
		kept.combat.loadout = { ranged = "flamethrower", variants = { longbow = "B" } }
		local keptVariants = kept.combat.loadout.variants
		L2.migrate(kept)
		check(
			kept.combat.loadout.variants == keptVariants and keptVariants.longbow == "B",
			"and one that has them keeps the same table"
		)

		-- Above 3 / 3 (old Studio levers, L3-38): the later bands' materials come back too.
		local veteran = L3.v7(4, 2, 0)
		L2.migrate(veteran)
		check(
			veteran.combat.materials.Timber == 320 and veteran.combat.materials.Steel == 10,
			`4 / 2: 320 Timber and 10 Steel ({veteran.combat.materials.Timber}, {veteran.combat.materials.Steel})`
		)
		local none = L3.v7(0, 0, 7)
		L2.migrate(none)
		check(
			none.combat.materials.Timber == 7 and none.combat.materials.Steel == nil,
			"0 / 0: nothing paid, nothing added"
		)

		-- A v8 profile is untouched by the runner.
		local current = L3.v7(2, 2, 3)
		L2.migrate(current)
		current.combat.tiers.longbow = 3
		current.combat.stars.forestRoad = { hard = true }
		local snapshot = L1.copy(current)
		L2.migrate(current)
		check(L3.same(current, snapshot), "a v8 profile goes through the runner unchanged")

		-- v7 code loading a v8 profile: Reconcile with a v7 template removes nothing.
		local oldTemplate = L3.v7(0, 0, 0)
		L2.reconcile(current, oldTemplate)
		check(
			L3.same(current, snapshot),
			"a v7 template's Reconcile keeps every v8 field (it only fills)"
		)

		-- The runner's own answers (R5): what DataService warns on.
		local fresh = L1.copy(template)
		check(
			Schema.Run(fresh) == nil and fresh.version == 8 and L3.same(fresh, template),
			"a fresh v8 profile takes no step and says nothing"
		)
		local stamped = L3.v7(0, 0, 0)
		check(
			Schema.Run(stamped) == nil and stamped.version == 8,
			"a v7 profile is stamped v8 by the runner"
		)
		local oldest = L2.v6()
		oldest.version = 1
		oldest.pendingDoubleOfflineAmount = nil
		oldest.legacyShop = nil
		check(
			Schema.Run(oldest) == nil
				and oldest.version == 8
				and oldest.legacyShop ~= nil
				and oldest.pendingDoubleOfflineAmount == 0,
			"a v1 profile runs every step in order to v8"
		)
		local gap = L3.v7(3, 3, 5)
		gap.version = 0
		local gapBefore = L1.copy(gap)
		check(
			Schema.Run(gap) == "missing" and L3.same(gap, gapBefore),
			'a version with no step is "missing", the profile left as it was'
		)
		local ahead = L3.v7(3, 3, 5)
		ahead.version = 9
		local aheadBefore = L1.copy(ahead)
		check(
			Schema.Run(ahead) == "ahead" and L3.same(ahead, aheadBefore),
			'a profile a newer server wrote is "ahead" and untouched (no refund)'
		)
		local fraction = L3.v7(3, 3, 5)
		fraction.version = 7.5
		check(
			Schema.Run(fraction) == "missing"
				and fraction.version == 7.5
				and fraction.combat.materials.Timber == 5,
			'a version that is not whole is "missing" too, and pays nothing'
		)
	end)

	-- No Armory.json: the maps are added, nothing is paid, and the stamp still moves.
	L3.withArmory(nil, function()
		local blind = L3.v7(3, 3, 5)
		L2.migrate(blind)
		check(
			blind.version == 8
				and blind.combat.materials.Timber == 5
				and L2.empty(blind.combat.tiers),
			"no Armory config: v8 with the three fields and no refund"
		)
	end)
end
L1.group("l3 schemaTests", L3.schemaTests)

-- The fix round's R3, R4, R5, R7 and 3-s2, read as text: the services that apply the pure rules do
-- not load here, so each line they must hold is counted in its own function (run_harness.py
-- L3_LINES); 0 = a line that must be gone. A key the reading drops, or one it adds, fails too. The
-- fix round 2 (F1, F2, F3) adds the lines that feed each pinned call, the bodies' exits (return,
-- continue, break: an early way out cannot hide) and the count-0 rules read by pattern on the code
-- with its comments blanked (L3_PATTERNS), so no other spelling of a gone line passes.
L3.LINES = {
	strikeTierCalls = {
		3,
		"WeaponService calls Armory.StrikeTier three times: the hit and the bar's two slots",
	},
	gearMelee = {
		1,
		"the bar's melee tier is the held melee family's strike tier, with the melee override",
	},
	gearRanged = {
		1,
		"the bar's ranged tier is the held ranged family's, with the ranged override",
	},
	gearMeleeOverride = { 1, "the bar reads the melee override when one is set" },
	gearRangedOverride = { 1, "and the ranged one" },
	gearConfig = { 1, "the bar is the range's T1 only in the range or without Armory.json (F1)" },
	gearProfile = { 1, "the bar reads the player's own profile, and its combat (F1)" },
	gearHeld = {
		1,
		"the bar's families are the shooter's live pair, else the saved loadout over the starters (F1)",
	},
	gearOverrideRead = { 1, "the bar reads the player's own Studio override (F1)" },
	gearAscension = { 1, "the bar's Ascension is the override's, else the profile's (F1)" },
	gearAscensionOut = { 1, "and each slot gets its own Ascension (F1)" },
	gearExits = {
		2,
		"gearOf has two ways out, the range's and the bar's: no early return hides the StrikeTier calls (F1)",
	},
	scaleTier = {
		1,
		"a hit scales by the striking family's strike tier, the override of its slot passed",
	},
	scaleMelee = { 1, "a melee family's hit reads the melee override" },
	scaleRanged = { 1, "a ranged family's hit reads the ranged override" },
	scaleReturn = { 1, "and the hit's scale is DamageScale at that tier and the slot's Ascension" },
	scaleGuards = { 1, "a hit is unscaled only in the range or without Armory.json (F1)" },
	scaleSlot = { 1, "a hit's slot is its family's (F1)" },
	scaleProfile = { 1, "a hit reads the player's own profile, and its combat (F1)" },
	scaleOverrideRead = { 1, "a hit reads the player's own override, by its family's slot (F1)" },
	scaleAscension = { 1, "a hit's Ascension is the override's, else the profile's (F1)" },
	scaleLevel = {
		1,
		"and a melee hit takes the melee slot's Ascension, a ranged hit the ranged one (F1)",
	},
	scaleExits = {
		3,
		"damageScale has three ways out, the range's, no Armory's and the scale: no early return (F1)",
	},
	slamFamily = { 1, 'the slam scales by the held melee FAMILY (not the word "melee")' },
	upgradeGate = { 1, "the dungeon's upgrade passes MayLeave's gate (no upgrade in a fight)" },
	upgradeOwned = { 1, "and owns a family through the starters and the profile's families" },
	grantProfile = { 1, "the dungeon's first clear writes the player's own profile (F2)" },
	grantApply = { 1, "through Unlocks.ApplyFirstClear, with the weapons and the starters (F2)" },
	grantNothing = { 1, "it answers nil only when nothing was given (F2)" },
	grantSent = { 1, "and resends the wallet before it answers what it gave (F2)" },
	grantExits = { 3, "GrantFirstClear has three ways out: no profile, nothing given, given (F2)" },
	endRunReward = { 1, "EndRun reads a NEW star's first-clear reward" },
	endRunGrant = { 1, "and gives it through UnlockService.GrantFirstClear" },
	grantFirstClearCalls = {
		2,
		"WaveService gives first clears in two places only: EndRun and the U lever",
	},
	starsProfile = {
		1,
		"a member's stars are the profile's (Unlocks.StarsOf), so needsStar can open",
	},
	readLevelInputs = { 1, "readLevel hands Validate the weapons and the starters" },
	leverAward = { 1, "U pays only a star that is new" },
	leverInputs = { 1, "U reads the combat config, the map and the player's own stars (F1)" },
	leverLevel = {
		1,
		"U resolves the level at the star's difficulty first: one that does not resolve gets no star (F3)",
	},
	leverReward = { 1, "U reads that difficulty's first-clear reward (R4)" },
	leverGrant = { 1, "and gives it through GrantFirstClear, as EndRun does" },
	leverGrants = { 1, "and keeps every grant for the notice (F1)" },
	leverStudio = { 1, "U pays only in a Studio mission" },
	leverExits = {
		4,
		"GrantStars' ways out: off a Studio mission, a level that does not resolve, an old star, the end (F1, F3)",
	},
	debugAllStars = { 1, "DebugService's grantStar wildcard is Unlocks.ALL_STARS (3-s2)" },
	debugLiteral = { 0, 'and DebugService spells no "*" of its own, in any spelling (F1)' },
	debugNextGear = { 1, "G steps from the override as set, not the clamped bar (2-s1)" },
	debugSetGear = { 1, "setGear keeps an unnamed slot's override as set" },
	debugLadder = { 1, "the star lever reads Armory.json's ladder (F1)" },
	debugLevels = {
		1,
		"its levels are every built band's for the wildcard, else the one level named (F1)",
	},
	debugDifficulty = { 1, "its difficulty is the ladder's starDifficulty, Hard (F1)" },
	debugTargets = { 1, "its players are the caller, else everyone admitted (F1)" },
	debugGrant = { 1, "and it awards and pays through WaveService.GrantStars (F1)" },
	debugStarExits = { 2, "grantStar's ways out: no ladder, no such level (F1)" },
	mainPower = { 1, "the dungeon Snapshot's Power is SavedPower on the profile (R7)" },
	mainArmory = { 1, "the dungeon Snapshot reads Armory.json (F1)" },
	mainProving = { 1, "and ProvingGrounds.json (F1)" },
	mainWeapons = { 1, "and hands SavedPower its weapons (F1)" },
	mainStarters = { 1, "and its starters (F1)" },
	mainSnapshotExits = { 1, "sendSnapshot's one early way out is the load status (F1)" },
	mainGearOf = { 0, "and no longer reads WeaponService.GearOf, in any spelling (F1)" },
	hubPower = { 1, "the hub's Power is SavedPower on the profile (R7)" },
	hubArmory = { 1, "the hub's Power is 0 only without Armory.json (F1)" },
	hubProving = { 1, "the hub's Power reads ProvingGrounds.json (F1)" },
	hubWeapons = { 1, "and hands SavedPower its weapons (F1)" },
	hubStarters = { 1, "and its starters (F1)" },
	hubPowerExits = { 2, "computeGearPower's ways out: no Armory.json, the Power (F1)" },
	hubPowerSent = { 2, "and rides both the Delta and the Snapshot" },
	hubCopy = { 1, "the hub's Delta carries ProfileCopy.Combat (R7)" },
	hubFrozenGear = { 0, "EconomyService reads no frozen slot gear, in any spelling (F1)" },
	runnerCall = {
		1,
		"DataService migrates through ProfileSchema.Run, the runner proved here (R5)",
	},
	runnerSteps = { 0, "and names no step table itself, in any spelling (no loop of its own)" },
	loadMigrates = {
		1,
		"and every load runs the migrations on the profile's data, a statement of attemptLoad's own (F1)",
	},
	loadExits = {
		5,
		"attemptLoad's ways out: the forced failure, no profile, the player gone, the session hook's, the data (F1)",
	},
	hubUpgradeCall = {
		1,
		"the hub's upgrade is Armory.Upgrade with an open gate and the built levels",
	},
	hubUpgradeOwned = { 1, "and owns through the starters and the profile's families" },
	hubAllStars = { 1, "the hub's grantStar wildcard is Unlocks.ALL_STARS (3-s2)" },
	hubLiteral = { 0, 'and the hub spells no "*" of its own, in any spelling (F1)' },
	hubStarLevels = {
		1,
		"the hub's star lever needs the ladder, and its levels are the built bands' or the one built level named (F2)",
	},
	hubStarInputs = {
		1,
		"the hub's star lever reads the ladder's difficulty, the weapons, the starters and the profile's stars (F2)",
	},
	hubStarNew = { 1, "it pays only a star that is new, the reward read from the level file (F2)" },
	hubStarApply = { 1, "through Unlocks.ApplyFirstClear on the profile, as the dungeon does (F2)" },
	hubStarValor = { 1, "and names the Valor it gave (F2)" },
	hubStarDirty = { 1, "and marks the profile for the Delta (F2)" },
	hubStarExits = {
		4,
		"grantStarTo's ways out: no ladder, no level, an old star, a level with no reward (F2)",
	},
	hubFileRead = { 1, "the reward is the level file's difficulty entry, a table or nothing (F2)" },
	hubFileExits = { 1, "and fileFirstClear has one way out (F2)" },
	uiWaiting = { 1, "the hub's client knows when the weapon families come late (F5)" },
	uiReplay = { 1, "and then pushes the model's profile and held pair to the Armory at once (F5)" },
	uiPushWaits = {
		1,
		"a push before the families asks for them and leaves the replay to that (F5)",
	},
}

function L3.sourceTests(): ()
	print(
		" The service lines that apply L3's rules, read as text (the fix rounds' R3, R4, R5, R7, 3-s2, F1, F2, F3)"
	)
	local reading = FIXTURES.source.l3
	local missing = {}
	for name, found in reading.found do
		if not found then
			table.insert(missing, name)
		end
	end
	table.sort(missing)
	check(
		#missing == 0,
		`every function the lines live in is there ({table.concat(missing, ", ")})`
	)
	local unknown = {}
	for key in reading.counts do
		if L3.LINES[key] == nil then
			table.insert(unknown, key)
		end
	end
	table.sort(unknown)
	check(
		#unknown == 0,
		`every line read has an expected count here ({table.concat(unknown, ", ")})`
	)
	local keys = {}
	for key in L3.LINES do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local expected = L3.LINES[key]
		local count = reading.counts[key]
		check(
			count == expected[1],
			`{expected[2]} ({key}: {tostring(count)}, expected {expected[1]})`
		)
	end
end
L1.group("l3 sourceTests", L3.sourceTests)

-- Armory.json, ProvingGrounds.json and the level files as they ship, pinned to the contract.
function L3.shippedTests(): ()
	print(" Armory.json as it ships (L3-1 to L3-8, L3-29)")
	local A = L3.Armory
	local ladder = ARMORY.ladder
	if type(ladder) ~= "table" then
		check(false, "Armory.json has a ladder")
		return
	end
	local damageSame = #ladder.damage == #L3.DAMAGE
	for t, value in L3.DAMAGE do
		damageSame = damageSame and near(ladder.damage[t], value, 1e-9)
	end
	check(
		damageSame,
		"ladder.damage is the contract's 20 multipliers, 1.5 x 1.65^(t - 1) to 4 decimals"
	)
	local hpSame = true
	for t = 1, 11 do
		hpSame = hpSame
			and ladder.hp.melee[t] == L3.HP_MELEE[t]
			and ladder.hp.ranged[t] == L3.HP_RANGED[t]
	end
	check(hpSame, "ladder.hp T1-T11 are the old slot tiers 2-12, one for one")
	check(ladder.rangeHp == 130 and A.RangeHp(ARMORY) == 130, "the range's body is 130")
	check(
		ladder.bandSize == 4
			and #ladder.bands == 5
			and ladder.bands[1].levelId == "forestRoad"
			and ladder.bands[1].material == "Timber",
		"five bands of four, the first Forest Road's, paid in Timber"
	)
	check(
		L3.same(ladder.costs, { 100, 100, 250, 500 }) and ladder.starDifficulty == "hard",
		"costs 100 / 100 / 250 / 500 by position; the Hard star is the trophy"
	)
	check(
		L3.same(ladder.starAlso, { "brutal" }),
		"and a Brutal star opens a band top too (the fix round's R1)"
	)
	check(ARMORY.power.tierWeight == 11 and ARMORY.baseHp == 100, "tierWeight 11 on baseHp 100")
	local none = { melee = 0, ranged = 0 }
	check(
		A.MaxHp(ARMORY, { melee = 1, ranged = 1 }, none) == 155
			and A.MaxHp(ARMORY, { melee = 3, ranged = 3 }, none) == 230
			and A.MaxHp(ARMORY, { melee = 5, ranged = 5 }, none) == 380,
		"MaxHp (1, 1) 155, (3, 3) 230, (5, 5) 380"
	)
	check(
		A.GearPower(ARMORY, { melee = 1, ranged = 1 }, none) == 64,
		`GearPower at T1 / T1 is 64 ({A.GearPower(ARMORY, { melee = 1, ranged = 1 }, none)})`
	)
	local windowsSame = true
	local count = 0
	for family, pair in L3.WINDOWS do
		local window = ARMORY.windows[family]
		windowsSame = windowsSame
			and window ~= nil
			and window.start == pair[1]
			and window.top == pair[2]
	end
	for _ in ARMORY.windows do
		count += 1
	end
	check(windowsSame and count == 15, "the windows are table L3-3, all 15 and nothing else")
	local legacySame = #ARMORY.legacy.gearCosts == #L3.LEGACY
	for index, pair in L3.LEGACY do
		local entry = ARMORY.legacy.gearCosts[index]
		legacySame = legacySame
			and entry ~= nil
			and entry.material == pair[1]
			and entry.amount == pair[2]
	end
	check(
		legacySame,
		"legacy.gearCosts is frozen byte for byte: the twelve prices the slots charged before v8 (L3.LEGACY)"
	)
	local problems = A.Problems(ARMORY, L3.families())
	check(
		#problems == 0,
		`Armory.Problems finds nothing in the shipped files ({#problems}{if #problems > 0
			then ": " .. problems[1]
			else ""})`
	)
	local starters = FIXTURES.proving.loadout
	check(
		A.TierOf(ARMORY, nil, starters.melee) == 1 and A.TierOf(ARMORY, nil, starters.ranged) == 1,
		"both starters' windows start at T1: a fresh profile is T1 / T1"
	)
	local forest = false
	for _, file in FIXTURES.levels do
		forest = forest or file.id == ladder.bands[1].levelId
	end
	check(forest, "the first band's level has a level file, so T2 to T4 can be bought")
end
L1.group("l3 shippedTests", L3.shippedTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
