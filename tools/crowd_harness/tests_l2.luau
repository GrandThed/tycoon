-- Cases for L2 W1, the bought double jump and the lookout (docs/prompts/l2-w1-contract.md): the
-- profile's v7 step (ProfileSchema, L2-1), the pure Unlocks (L2-2, L2-9), the pure SecretFlow
-- (L2-11 to L2-15), WallClip.Rise per player (L2-4) and the leap's F1 / F2 (§11), StageFlow's
-- secrets lines (L2-13, L2-15), then the shipped files: Forest Road's chests, Expeditions.json's Double Jump and Combat.json's
-- trigger. Appended last by run_harness.py, so every local of the earlier files is in scope (vec,
-- check, near, load, L1, L1C). Everything hangs off the L2 table (the 200-local limit), and every
-- group runs behind L1.group, so one that throws fails a check and the bundle goes on to its
-- verdict. UnlockService and WaveService cannot be loaded here: they execute what these decide.

print("L2: the bought double jump and the lookout (ProfileSchema, Unlocks, SecretFlow)")

local L2: any = {
	Schema = load("ProfileSchema"),
	Unlocks = load("Unlocks"),
	Secret = load("SecretFlow"),
	NAN = 0 / 0,
	-- A config that sells Double Jump at 10 Valor (the contract's L2-6 entry).
	config = {
		abilities = {
			list = {
				{ id = "doubleJump", name = "Double Jump", text = "A second jump in the air.", price = { valor = 10 }, order = 1 },
			},
		},
	},
	-- A trigger band as the contract's starting values: reach 5, 1 below, 9 above.
	rules = { secretReach = 5, secretBelow = 1, secretAbove = 9 },
}

-- A PlayerState as a v6 profile has it, before the v7 step (no abilities, secrets, families,
-- shortcuts in `combat`).
function L2.v6(): any
	return {
		version = 6,
		cash = 0,
		era = 1,
		rebirthCount = 0,
		legacy = 0,
		slots = {},
		passes = {},
		processedReceipts = {},
		lastSeen = 0,
		incomeAtSave = 0,
		stats = { totalCashAllTime = 0, erasCompleted = 0, playtimeSeconds = 0 },
		settings = { music = true, sfx = true, vipSkins = true, cityDetail = true },
		pendingDoubleOfflineAmount = 0,
		legacyShop = { spent = 0, perks = {} },
		combat = {
			materials = { Timber = 12 },
			valor = 7,
			gear = { melee = 2, ranged = 1 },
			ascension = { melee = 0, ranged = 0 },
			missions = {},
			highestEra = 2,
			expeditionSince = 0,
			expeditionSeconds = 0,
			stats = { kills = 4, wavesCleared = 1, expeditions = 1, cashFromCombat = 30 },
		},
	}
end

-- DataService.runMigrations' loop, as it stands there: every step from the profile's version to
-- SCHEMA_VERSION, the version bumped after each.
function L2.migrate(state: any): ()
	local Schema = L2.Schema
	while state.version < Schema.SCHEMA_VERSION do
		local step = Schema.Migrations[state.version]
		if step == nil then
			return
		end
		step(state)
		state.version += 1
	end
end

-- ProfileStore's Reconcile (ProfileStore.luau ReconcileTable): fills each missing string key
-- from the template (a deep copy of a table), recurses into tables both have, removes nothing.
function L2.reconcile(target: any, template: any): ()
	for key, value in template do
		if type(key) == "string" then
			if target[key] == nil then
				target[key] = if type(value) == "table" then L1.copy(value) else value
			elseif type(target[key]) == "table" and type(value) == "table" then
				L2.reconcile(target[key], value)
			end
		end
	end
end

function L2.empty(value: any): boolean
	return type(value) == "table" and next(value) == nil
end

function L2.schemaTests(): ()
	print(" ProfileSchema v7: the dungeon place's unlocks, add-only (L2-1)")
	local Schema = L2.Schema
	local template = Schema.PROFILE_TEMPLATE
	local combat = template.combat
	check(Schema.SCHEMA_VERSION == 7 and template.version == 7, `the schema is v7 and the template says so ({Schema.SCHEMA_VERSION}, {template.version})`)
	check(L2.empty(combat.abilities) and L2.empty(combat.secrets) and L2.empty(combat.families) and L2.empty(combat.shortcuts), "a fresh profile's combat holds the four maps, empty")
	local missing = {}
	for version = 1, Schema.SCHEMA_VERSION - 1 do
		if type(Schema.Migrations[version]) ~= "function" then
			table.insert(missing, tostring(version))
		end
	end
	check(#missing == 0, `every step from v1 to v{Schema.SCHEMA_VERSION} exists (missing: {table.concat(missing, ", ")})`)

	-- A v6 profile that nothing reconciled: the step adds the four maps, fresh, and touches
	-- nothing else.
	local state = L2.v6()
	L2.migrate(state)
	local mine = state.combat
	check(state.version == 7, `a v6 profile reaches v7 ({state.version})`)
	check(L2.empty(mine.abilities) and L2.empty(mine.secrets) and L2.empty(mine.families) and L2.empty(mine.shortcuts), "it gains the four maps, empty")
	check(mine.abilities ~= combat.abilities and mine.secrets ~= combat.secrets and mine.families ~= combat.families and mine.shortcuts ~= combat.shortcuts, "none of them is the template's own table (no aliasing)")
	check(mine.abilities ~= mine.families and mine.secrets ~= mine.shortcuts, "and each is a table of its own")
	check(mine.valor == 7 and mine.materials.Timber == 12 and mine.gear.melee == 2 and mine.highestEra == 2 and mine.stats.kills == 4, "what the profile already held is untouched")
	mine.abilities.doubleJump = true
	check(combat.abilities.doubleJump == nil, "writing the migrated map leaves the template empty")
	local other = L2.v6()
	L2.migrate(other)
	check(other.combat.abilities ~= mine.abilities and other.combat.abilities.doubleJump == nil, "two migrated profiles share nothing")

	-- Reconciled first (ProfileStore's order): Reconcile already put copies in; the step keeps
	-- them, and keeps what is in them.
	local reconciled = L2.v6()
	L2.reconcile(reconciled, template)
	local filled = reconciled.combat.abilities
	check(filled ~= nil and filled ~= combat.abilities, "Reconcile fills the maps from deep copies of the template")
	filled.doubleJump = true
	reconciled.combat.secrets.forestRoad = { lookout = true }
	L2.migrate(reconciled)
	check(reconciled.version == 7 and reconciled.combat.abilities == filled and filled.doubleJump == true and reconciled.combat.secrets.forestRoad.lookout == true, "a reconciled profile keeps the tables it has, and what is in them")

	-- Twice: the step is safe to run again.
	local twice = L2.v6()
	twice.combat.families = { flamethrower = true }
	local step = Schema.Migrations[6]
	step(twice)
	local first = twice.combat.abilities
	first.doubleJump = true
	step(twice)
	check(twice.combat.abilities == first and first.doubleJump == true and twice.combat.families.flamethrower == true, "run twice it changes nothing more (the same tables, the same contents)")
	check(L2.empty(twice.combat.secrets) and L2.empty(twice.combat.shortcuts), "and a map that was there already is kept while the missing ones are added")

	-- v6 code loading a v7 profile: Reconcile with a v6 template removes nothing, and the loop
	-- leaves a newer profile alone.
	local ahead = L2.v6()
	L2.migrate(ahead)
	ahead.combat.abilities.doubleJump = true
	ahead.combat.secrets.forestRoad = { lookout = true }
	local oldTemplate = L2.v6()
	L2.reconcile(ahead, oldTemplate)
	check(ahead.version == 7 and ahead.combat.abilities.doubleJump == true and ahead.combat.secrets.forestRoad.lookout == true, "a v6 template's Reconcile keeps every v7 field (it only fills)")
end
L1.group("l2 schemaTests", L2.schemaTests)

function L2.unlockTests(): ()
	print(" Unlocks: the attribute, ownership, keys and the purchase (L2-2, L2-9)")
	local U = L2.Unlocks
	local config = L2.config
	check(U.AIR_JUMP == "doubleJump", "the air jump keys on doubleJump")
	check(U.Attribute("doubleJump") == "Ability_doubleJump", `the Player attribute is Ability_<id> ({U.Attribute("doubleJump")})`)
	check(U.Owns({ doubleJump = true }, "doubleJump") and not U.Owns({}, "doubleJump") and not U.Owns(nil, "doubleJump") and not U.Owns({ doubleJump = false }, "doubleJump") and not U.Owns({ doubleJump = 1 } :: any, "doubleJump"), "owned only when the map holds true for it (nil, false, 1: not owned)")

	-- HasKey fails closed.
	check(U.HasKey({ doubleJump = true }, config, "doubleJump"), "a sold ability that is owned is the key")
	check(not U.HasKey({}, config, "doubleJump") and not U.HasKey(nil, config, "doubleJump"), "a sold ability not owned is not")
	check(not U.HasKey({ doubleJump = true }, {}, "doubleJump") and not U.HasKey({ doubleJump = true }, nil, "doubleJump"), "an owned ability the config does not sell is not a key")
	local rogue = { doubleJump = true, fire = true, ice = true, glide = true }
	check(not U.HasKey(rogue, config, "fire") and not U.HasKey(rogue, config, "ice") and not U.HasKey(rogue, config, "glide") and not U.HasKey(rogue, config, ""), "fire, ice and any unknown word are false in W1, even with the profile claiming them")
	local broken = { abilities = { list = { { id = "doubleJump", name = "Double Jump", text = "", price = { valor = 0 }, order = 1 } } } }
	check(not U.HasKey({ doubleJump = true }, broken, "doubleJump"), "an entry that cannot be sold is no key either")

	-- DefProblem and Find.
	local good = config.abilities.list[1]
	check(U.DefProblem(good) == nil, "the contract's entry can be sold")
	local function with(field: string, value: any): any
		local copy = L1.copy(good)
		copy[field] = value
		return copy
	end
	local bad = {
		{ "no id", with("id", nil) },
		{ "an empty id", with("id", "") },
		{ "no name", with("name", nil) },
		{ "no text", with("text", nil) },
		{ "no order", with("order", nil) },
		{ "a NaN order", with("order", L2.NAN) },
		{ "no price", with("price", nil) },
		{ "a price of 0", with("price", { valor = 0 }) },
		{ "a negative price", with("price", { valor = -10 }) },
		{ "a price of 2.5", with("price", { valor = 2.5 }) },
		{ "a NaN price", with("price", { valor = L2.NAN }) },
		{ "an infinite price", with("price", { valor = math.huge }) },
		{ "a price that is a string", with("price", { valor = "10" }) },
	}
	local passed = {}
	for _, case in bad do
		if U.DefProblem(case[2]) == nil then
			table.insert(passed, case[1])
		end
	end
	check(#passed == 0 and U.DefProblem(5 :: any) ~= nil, `every malformed entry is refused (passed: {table.concat(passed, ", ")})`)
	check(U.Find(config, "doubleJump") == good and U.Find(config, "glide") == nil and U.Find(nil, "doubleJump") == nil and U.Find({}, "doubleJump") == nil and U.Find({ abilities = {} } :: any, "doubleJump") == nil, "Find: the sold entry by id; nothing for another id, no config, no block or no list")
	local twice = { abilities = { list = { good, with("price", { valor = 99 }) } } }
	check(U.Find(twice, "doubleJump") == good, "a repeated id: the first entry wins")
	local badFirst = { abilities = { list = { with("price", { valor = 0 }), good } } }
	check(U.Find(badFirst, "doubleJump") == nil, "a malformed first entry is not replaced by a later one of the same id")

	-- BuyVerdict: every reason, in order.
	local function profile(valor: number, abilities: any): any
		local state = L2.v6()
		state.combat.valor = valor
		state.combat.abilities = abilities
		return state
	end
	check(U.BuyVerdict(nil, nil, false) == "unavailable" and U.BuyVerdict(nil, good, true) == "unavailable", "no profile: unavailable, before anything else")
	check(U.BuyVerdict(profile(0, { doubleJump = true }), nil, false) == "invalid", "no such ability: invalid, before owned, busy or funds")
	check(U.BuyVerdict(profile(100, {}), with("price", { valor = 0 }), true) == "invalid" and U.BuyVerdict(profile(100, {}), with("name", nil), true) == "invalid", "a malformed entry: invalid")
	check(U.BuyVerdict(profile(0, { doubleJump = true }), good, false) == "owned", "owned: owned, before busy and funds")
	check(U.BuyVerdict(profile(0, {}), good, false) == "busy", "the gate shut (fighting in a live run): busy, before funds")
	check(U.BuyVerdict(profile(9, {}), good, true) == "insufficientFunds", "one Valor short: insufficientFunds")
	check(U.BuyVerdict(profile(L2.NAN, {}), good, true) == "insufficientFunds", "a Valor that is not a number buys nothing")
	check(U.BuyVerdict(profile(10, {}), good, true) == nil and U.BuyVerdict(profile(250, {}), good, true) == nil, "exactly the price, or more: yes")
	check(U.BuyVerdict(profile(10, nil), good, true) == nil and U.BuyVerdict(profile(10, { doubleJump = false }), good, true) == nil, "a profile with no abilities map (v6 code saved it), or a false entry, may buy")
end
L1.group("l2 unlockTests", L2.unlockTests)

-- A chest whose block is centred at (0, 12, 0), 6 x 4 x 6: its bottom (floorY) is 10.
function L2.layout(): any
	return {
		version = 1,
		start = { x = 0, y = 0, z = 0 },
		killY = -40,
		camps = {},
		blocks = {},
		route = {},
		secrets = {
			{ id = "lookout", needs = "doubleJump", x = 0, y = 12, z = 0, sx = 6, sy = 4, sz = 6, sign = { x = 0, y = 0, z = 0, text = "" } },
			{ id = "cache", needs = "fire", x = 40, y = 5, z = 0, sx = 12, sy = 10, sz = 12, sign = { x = 0, y = 0, z = 0, text = "" } },
			{ id = "shrine", needs = "ice", x = -40, y = 0.5, z = 0, sx = 12, sy = 3, sz = 12, sign = { x = 0, y = 0, z = 0, text = "" } },
		},
	}
end

function L2.file(): any
	return {
		secrets = {
			lookout = { name = "The Lookout", valor = 3, materials = 50, family = "flamethrower" },
			cache = { name = "Raiders' Cache" },
			shrine = { name = "Island Shrine" },
		},
	}
end

function L2.secretTests(): ()
	print(" SecretFlow: chests, their trigger, the verdict and the map row (L2-11, L2-15)")
	local S = L2.Secret
	local sites = S.Sites(L2.layout(), L2.file())
	local lookout, cache, shrine = sites[1], sites[2], sites[3]
	check(#sites == 3 and lookout.id == "lookout" and cache.id == "cache" and shrine.id == "shrine", "Sites: every layout secret, in the layout's order")
	check(lookout.x == 0 and lookout.z == 0 and lookout.floorY == 10 and lookout.needs == "doubleJump" and lookout.name == "The Lookout", `a site is the block's centre on the flat, its bottom and its key, named by the level file (floorY {lookout.floorY})`)
	local reward = lookout.reward
	check(reward ~= nil and reward.valor == 3 and reward.materials == 50 and reward.family == "flamethrower", "an entry with valor, materials or family is its reward")
	check(cache.reward == nil and shrine.reward == nil and cache.name == "Raiders' Cache" and cache.floorY == 0 and shrine.floorY == -1, "an entry with a name alone has no reward")
	local partial = S.Sites(L2.layout(), { secrets = { lookout = { name = "L", valor = 2 }, cache = { name = "C", family = "x" } } })
	check(partial[1].reward ~= nil and partial[1].reward.materials == 0 and partial[1].reward.family == nil and partial[2].reward ~= nil and partial[2].reward.valor == 0 and partial[2].reward.family == "x", "a reward entry fills what it leaves out with 0 and no family")
	local nameless = S.Sites(L2.layout(), nil)
	check(#nameless == 3 and nameless[1].name == "lookout" and nameless[1].reward == nil, "with no level file block: named by their ids, paying nothing")
	local brokenLayout = L2.layout()
	brokenLayout.secrets[2].x = L2.NAN
	brokenLayout.secrets[3].needs = nil
	check(#S.Sites(brokenLayout, L2.file()) == 1 and #S.Sites({ secrets = nil } :: any, L2.file()) == 0, "a secret whose numbers or key are missing is skipped; no secrets list = no sites")
	local junk = S.Sites(L2.layout(), { secrets = { lookout = { name = "L", valor = 2.5, materials = -4, family = "" } } })
	check(junk[1].reward ~= nil and junk[1].reward.valor == 0 and junk[1].reward.materials == 0 and junk[1].reward.family == nil, "a malformed amount pays 0 and an empty family is none (Validate refuses such a file first)")

	-- Triggered: the band and the reach, closed at every edge.
	local rules = L2.rules
	local function at(x: number, rise: number, z: number): boolean
		return S.Triggered(lookout, vec(x, 10 + rise, z), rules)
	end
	check(at(0, 3, 0) and at(5, 3, 0) and at(0, 3, -5) and at(3, 3, 4), "within secretReach on the flat (exactly 5, and 3-4-5 on a diagonal): triggered")
	check(not at(5.001, 3, 0) and not at(3.6, 3, 3.6), "a thousandth past the reach, or a diagonal past it: not")
	check(at(4, -1, 0) and not at(4, -1.001, 0), "secretBelow under the chest's bottom is in; a thousandth deeper is out")
	check(at(4, 9, 0) and not at(4, 9.001, 0), "secretAbove over it is in; a thousandth higher is out")
	check(not at(0, -23, 0) and not at(0, -5, 0), "a root on the road 23 under it, or at the top of one jump from there (-5), opens nothing")
	local nan = L2.NAN
	check(not S.Triggered(lookout, vec(0, 13, 0), { secretReach = nan, secretBelow = 1, secretAbove = 9 }) and not S.Triggered(lookout, vec(0, 13, 0), { secretBelow = 1, secretAbove = 9 }) and not S.Triggered(lookout, vec(0, 13, 0), { secretReach = 5, secretBelow = math.huge, secretAbove = 9 }) and not S.Triggered(lookout, vec(0, 13, 0), { secretReach = 5, secretBelow = 1 }), "rules that are missing, NaN or infinite open nothing")

	-- Decide: in order, found, key, reward.
	check(S.Decide(lookout, true, true) == "known" and S.Decide(lookout, false, true) == "known" and S.Decide(cache, false, true) == "known", "already found: known, whatever the key or the reward")
	check(S.Decide(lookout, false, false) == "locked" and S.Decide(cache, false, false) == "locked", "no key: locked, before the reward is looked at")
	check(S.Decide(cache, true, false) == "nothing", "the key and no reward entry: nothing")
	check(S.Decide(lookout, true, false) == "pay", "the key and a reward, not found yet: pay")

	-- MapRow.
	local row = S.MapRow(sites, { lookout = true, shrine = false } :: any)
	check(#row == 3 and row[1].id == "lookout" and row[2].id == "cache" and row[3].id == "shrine", "the row is every chest, in order")
	check(row[1].found and not row[2].found and not row[3].found, "found only where the player's map holds true")
	check(row[1].name == "The Lookout" and row[1].needs == "doubleJump" and row[2].needs == "fire" and row[3].needs == "ice", "each with its name and its key")
	local none = S.MapRow(sites, nil)
	check(#none == 3 and not none[1].found and not none[2].found and not none[3].found and #S.MapRow({}, { lookout = true }) == 0, "no map: nothing found; no sites: no row")
end
L1.group("l2 secretTests", L2.secretTests)

function L2.riseTests(): ()
	print(" WallClip.Rise per player (L2-4)")
	local movement = FIXTURES.proving.movement
	local Clip = L1C.Clip
	check(Clip.Rise(movement, false) == movement.jumpHeight and Clip.Rise(movement, true) == movement.jumpHeight + movement.doubleJumpHeight, "one jump without the double jump; both with it")
	check(Clip.Rise(movement, false) == 18 and Clip.Rise(movement, true) == 30, `as shipped: 18 and 30 ({Clip.Rise(movement, false)}, {Clip.Rise(movement, true)})`)
	-- The lookout ledge is 26 over Road5: refused to a non-owner, allowed to an owner.
	check(Clip.TooHigh(8, 34, Clip.Rise(movement, false)) and not Clip.TooHigh(8, 34, Clip.Rise(movement, true)), "a ground point 26 over the caster's floor: refused without the double jump, allowed with it")
end
L1.group("l2 riseTests", L2.riseTests)

-- L2 W1 §11, the lead's ruling on the leap finding: F2 (the caster's floor over a void) and F1 (the
-- leap's apex), pure in WallClip so WeaponService.GroundPoint, InputController.groundPoint and
-- MovementController.Leap share them. None of the three loads here; the rule they call is this one.
function L2.leapTests(): ()
	print(" WallClip.CasterFloor and LeapApex (L2 W1 F2, F1)")
	local movement = FIXTURES.proving.movement
	local Clip = L1C.Clip
	local rise, owned = Clip.Rise(movement, false), Clip.Rise(movement, true)
	local height = FIXTURES.proving.weapons.greataxe.ability.height
	local standing = 3

	-- F2: a probed floor is the floor, wherever it is; over a void, the feet less the rise.
	check(Clip.CasterFloor(8, 26, rise) == 8 and Clip.CasterFloor(-40, 26, rise) == -40 and Clip.CasterFloor(0, 26, rise) == 0, "a floor under the caster is his floor, whatever the feet and the rise")
	check(Clip.CasterFloor(30, 26, rise) == 30, "even a floor the ray finds above the feet (a root sunk into a step)")
	check(Clip.CasterFloor(nil, 26, rise) == 26 - rise and Clip.CasterFloor(nil, 26, owned) == 26 - owned, `over a void: the feet less the caster's own rise ({Clip.CasterFloor(nil, 26, rise)}, {Clip.CasterFloor(nil, 26, owned)})`)
	-- The lookout (Road5 at 8, the ledge's top at 34): a jump off the road's edge puts the feet at
	-- 8 + one jump over a void. The ledge is then as far out of reach as from the road itself.
	local feet = 8 + movement.jumpHeight
	check(Clip.TooHigh(Clip.CasterFloor(nil, feet, rise), 34, rise), `the ledge (34) from a jump's top over a void off Road5 (feet {feet}): refused without the double jump`)
	-- An owner's rise is both jumps, so over a void his floor is the feet less both: at the top of
	-- his double jump the ledge is in reach as from the road, at one jump's top it is not yet.
	local both = 8 + owned
	check(not Clip.TooHigh(Clip.CasterFloor(nil, both, owned), 34, owned), `an owner at his double jump's top (feet {both}): allowed, as from the road`)
	check(Clip.TooHigh(Clip.CasterFloor(nil, feet, owned), 34, owned), "an owner at one jump's top over the void: refused (his rise counts both jumps)")
	check(not Clip.TooHigh(feet, 34, rise), "(the old rule, the feet as the floor, allowed it: the hole F2 closes)")

	-- F1, ground casts: the root stands on its floor, and the apex is the old one, height over the
	-- higher end, for targets above, level and below, and for any height.
	local same = true
	for _, floor in { -12, 0, 8, 26.5 } do
		for _, target in { -30, floor - 4, floor, floor + 6, floor + rise } do
			for _, h in { 0, 2.5, height, 18 } do
				local from, to = floor + standing, target + standing
				if not near(Clip.LeapApex(from, to, floor, standing, h), math.max(from, to) + h) then
					same = false
				end
			end
		end
	end
	check(same, "cast from the ground: the apex is height over the higher end, as before F1")
	check(Clip.LeapApex(11, 5, 8, standing, height) == 11 + height, "a ground cast down a slope: height over the caster's root, not the target's")
	check(Clip.LeapApex(11, 17, 8, standing, height) == 17 + height, "a ground cast up a step: height over the target's root")

	-- F1, airborne casts: the height goes over the caster's floor, never over the airborne root.
	local root = feet + standing
	check(Clip.LeapApex(root, 8 + standing, 8, standing, height) == root, `at a jump's top over Road5, aimed level: the apex is the root ({root}), not root + height ({root + height})`)
	check(Clip.LeapApex(root, 20 + standing, 8, standing, height) == 20 + standing + height, "aimed at a target that height lifts above the root: height over the target")
	check(Clip.LeapApex(root, 8 + standing, 8, standing, 30) == 8 + standing + 30, "a lift above the jump itself: height over the caster's floor")
	check(Clip.LeapApex(root, 8 + standing, Clip.CasterFloor(nil, feet, rise), standing, height) == root, "over a void (F2's floor): never above the root for a lift under the rise")

	-- A height that is not a positive number lifts nothing.
	check(Clip.LeapApex(11, 5, 8, standing, -6) == 11 and Clip.LeapApex(11, 15, 8, standing, -6) == 15, "a negative height: the higher end, no lift")
	check(Clip.LeapApex(11, 5, 8, standing, L2.NAN) == 11, "a NaN height: no lift")
end
L1.group("l2 leapTests", L2.leapTests)

function L2.flowTests(): ()
	print(" StageFlow: Resolve carries secrets, Validate checks them, the map card's rows (L2-13, L2-15)")
	local Flow = L1.Flow
	local got = L1.real.resolve("forestRoad")
	local level, layout = got.level, got.layout
	if level == nil or layout == nil then
		check(false, "Forest Road resolves (the cases below need it)")
		return
	end
	check(level.secrets == got.file.secrets, "Resolve carries the file's secrets block into the level")
	local ranks = L1.real.ranks()
	local function problems(mutate: (any, any) -> ()): { string }
		local copyLevel, copyLayout = L1.copy(level), L1.copy(layout)
		mutate(copyLevel, copyLayout)
		local found = {}
		for _, line in Flow.Validate(copyLevel, copyLayout, L1.real.kinds, ranks, L1.real.rules, FIXTURES.proving.crowd.maxAlive) do
			if string.find(line, "secret", 1, true) ~= nil then
				table.insert(found, line)
			end
		end
		return found
	end
	check(#problems(function() end) == 0, `the shipped block is accepted ({table.concat(problems(function() end), "; ")})`)
	local refusals = {
		{ "no secrets block", function(l: any, _o: any) l.secrets = nil end },
		{ "a secrets block that is not a table", function(l: any, _o: any) l.secrets = "lookout" end },
		{ "a secrets block that is not a table, on a layout with no secrets", function(l: any, o: any) l.secrets = "lookout" o.secrets = {} end },
		{ "a layout secret with no entry", function(l: any, _o: any) l.secrets.cache = nil end },
		{ "an entry with no name", function(l: any, _o: any) l.secrets.lookout.name = nil end },
		{ "an entry with an empty name", function(l: any, _o: any) l.secrets.lookout.name = "" end },
		{ "a valor of 2.5", function(l: any, _o: any) l.secrets.lookout.valor = 2.5 end },
		{ "a negative valor", function(l: any, _o: any) l.secrets.lookout.valor = -1 end },
		{ "a NaN valor", function(l: any, _o: any) l.secrets.lookout.valor = L2.NAN end },
		{ "materials of -1", function(l: any, _o: any) l.secrets.lookout.materials = -1 end },
		{ "materials that are a string", function(l: any, _o: any) l.secrets.lookout.materials = "50" end },
		{ "a family that is a number", function(l: any, _o: any) l.secrets.lookout.family = 5 end },
		{ "an empty family", function(l: any, _o: any) l.secrets.lookout.family = "" end },
		{ "a family of 25 characters", function(l: any, _o: any) l.secrets.lookout.family = string.rep("f", 25) end },
		{ "a layout secret with no id", function(_l: any, o: any) o.secrets[1].id = nil end },
	}
	local missed = {}
	for _, case in refusals do
		if #problems(case[2]) == 0 then
			table.insert(missed, case[1])
		end
	end
	check(#missed == 0, `each broken secrets line refuses the level (accepted: {table.concat(missed, ", ")})`)
	check(#problems(function(l: any, _o: any) l.secrets.lookout.family = string.rep("f", 24) l.secrets.lookout.valor = 0 l.secrets.lookout.materials = 0 end) == 0, "a family of 24 characters and amounts of 0 are fine")
	check(#problems(function(l: any, o: any) l.secrets = nil o.secrets = {} end) == 0 and #problems(function(l: any, o: any) l.secrets.extra = { name = "x" } o.secrets = {} end) == 0, "a layout with no secrets needs no block (an entry no secret names is not refused)")

	-- The map card's rows ride on each node's state, open or not.
	local map = L1.real.map
	local built = L1.real.built()
	local rows = { forestRoad = { { id = "lookout", name = "The Lookout", needs = "doubleJump", found = true } } }
	local state = Flow.MapState(map, built, {}, {}, 1, rows)
	local forest, other = nil, nil
	for _, node in state.nodes do
		local nodeDef = nil
		for _, candidate in map.nodes do
			if candidate.id == node.id then
				nodeDef = candidate
			end
		end
		if nodeDef ~= nil and nodeDef.level == "forestRoad" then
			forest = node
		elseif nodeDef ~= nil and nodeDef.level ~= "forestRoad" then
			other = node
		end
	end
	check(forest ~= nil and forest.secrets == rows.forestRoad, "MapState puts the receiver's row on the node of that level")
	check(other == nil or other.secrets == nil, "a node whose level has no row carries none")
	local plain = Flow.MapState(map, built, {}, {}, 1)
	local carried = 0
	for _, node in plain.nodes do
		if node.secrets ~= nil then
			carried += 1
		end
	end
	check(carried == 0, "with no rows given, no node carries any (the old callers)")
	local locked = nil
	for _, node in map.nodes do
		if node.level ~= nil and node.requires ~= nil and node.requires.node ~= nil then
			locked = node
			break
		end
	end
	if locked ~= nil then
		local lockedRows = { [locked.level] = { { id = "x", name = "X", needs = "ice", found = false } } }
		local lockedState = Flow.NodeState(map, built, {}, {}, locked.id, lockedRows)
		check(lockedState ~= nil and not lockedState.open and lockedState.secrets == lockedRows[locked.level], "a closed node still shows its row")
	end
end
L1.group("l2 flowTests", L2.flowTests)

-- The shipped files: Forest Road's chests as the layout and the level file have them, the Double
-- Jump Expeditions.json sells, Combat.json's trigger band.
function L2.realTests(): ()
	print(" The real files: the lookout pays behind the Double Jump, the cache and the shrine pay nothing")
	local S, U = L2.Secret, L2.Unlocks
	local file = L1.real.file("forestRoad")
	local layout = file ~= nil and L1.real.layouts[file.layout] or nil
	if file == nil or layout == nil then
		check(false, "Forest Road's file and layout are there")
		return
	end
	local sites = S.Sites(layout, file)
	local byId = {}
	for _, site in sites do
		byId[site.id] = site
	end
	local lookout, cache, shrine = byId.lookout, byId.cache, byId.shrine
	check(#sites == #layout.secrets and lookout ~= nil and cache ~= nil and shrine ~= nil, `every layout secret is a site (lookout, cache, shrine; {#sites} of {#layout.secrets})`)
	if lookout == nil or cache == nil or shrine == nil then
		return
	end
	local config = L1.real.map
	local def = U.Find(config, U.AIR_JUMP)
	check(def ~= nil and def.price.valor == 10, `Expeditions.json sells Double Jump for 10 Valor ({def and def.price.valor})`)
	check(lookout.needs == U.AIR_JUMP and cache.needs == "fire" and shrine.needs == "ice", "the lookout needs the double jump, the cache fire, the shrine ice")
	local reward = lookout.reward
	check(reward ~= nil and reward.valor >= 2 and def ~= nil and reward.valor < def.price.valor and reward.materials > 0 and reward.family == "flamethrower", `the lookout pays: at least 2 Valor and under Double Jump's price, Timber, and the Flamethrower ({reward and reward.valor}, {reward and reward.materials}, {reward and tostring(reward.family)})`)
	check(cache.reward == nil and shrine.reward == nil, "the cache and the shrine have no reward entry in W1 (no secret pays without a key W1 sells)")
	check(S.Decide(lookout, U.HasKey({}, config, lookout.needs), false) == "locked" and S.Decide(lookout, U.HasKey({ doubleJump = true }, config, lookout.needs), false) == "pay", "the lookout: locked without the double jump, pays with it")
	local claims = { doubleJump = true, fire = true, ice = true }
	check(S.Decide(cache, U.HasKey(claims, config, cache.needs), false) == "locked" and S.Decide(shrine, U.HasKey(claims, config, shrine.needs), false) == "locked", "the cache and the shrine stay locked whatever the profile claims")

	-- Combat.json's band on the lookout's geometry: on the ledge beside the chest it opens; from
	-- the road below, at the top of one jump, it does not.
	local rules = L1.real.rules
	local root = L1.real.ROOT
	check(type(rules.secretReach) == "number" and type(rules.secretBelow) == "number" and type(rules.secretAbove) == "number", `Combat.json levels has secretReach, secretBelow and secretAbove ({tostring(rules.secretReach)}, {tostring(rules.secretBelow)}, {tostring(rules.secretAbove)})`)
	local block = nil
	for _, secret in layout.secrets do
		if secret.id == "lookout" then
			block = secret
		end
	end
	local beside = vec(lookout.x + block.sx / 2 + 1, lookout.floorY + root, lookout.z)
	check(S.Triggered(lookout, beside, rules), `a root standing on the ledge against the chest opens it ({beside.X}, {beside.Y}, {beside.Z})`)
	local onTop = vec(lookout.x, lookout.floorY + block.sy + root, lookout.z)
	check(S.Triggered(lookout, onTop, rules), "and so does one standing on the chest")
	local road = 8
	check(not S.Triggered(lookout, vec(lookout.x, road + root, lookout.z), rules) and not S.Triggered(lookout, vec(lookout.x, road + root + FIXTURES.proving.movement.jumpHeight, lookout.z), rules), "from Road5 below, standing or at the top of one jump, it does not")
end
L1.group("l2 realTests", L2.realTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
