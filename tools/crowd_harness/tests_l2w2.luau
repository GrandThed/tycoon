-- Cases for L2 W2, fire, the Flamethrower, the cave and the shortcut (docs/prompts/l2-w2-contract.md):
-- Unlocks' owned families, element keys and the set-family verdict (L2-30 to L2-32), the pure
-- WorldReact (L2-34, L2-35), SecretFlow's shortcuts (L2-36), LevelGeometry.Pieces' `open` and its
-- reactive pieces, StageFlow.Validate's react, opens and shortcuts lines, and the element as a
-- structural Tuning path. Appended last by run_harness.py, so every local of the earlier files is
-- in scope (vec, check, load, config, L1, L2). Everything hangs off the W2 table (the 200-local
-- limit) and every group runs behind L1.group. UnlockService, LevelService, WeaponService and
-- WaveService cannot be loaded here: they execute what these decide.

print("L2 W2: fire, the Flamethrower, the cave and the shortcut (Unlocks, WorldReact, SecretFlow)")

local W2: any = {
	Unlocks = load("Unlocks"),
	React = load("WorldReact"),
	Secret = load("SecretFlow"),
	Geo = load("LevelGeometry"),
	NAN = 0 / 0,
	-- A roster: two starters (one carrying ice, to show a starter's element counts), the
	-- Flamethrower (fire, one variant), a family with a word that is no element, and a melee
	-- family nobody starts with.
	weapons = {
		broadsword = { name = "Broadsword", slot = "melee", default = "A", variants = { A = {}, B = {} }, element = "ice" },
		longbow = { name = "Longbow", slot = "ranged", default = "A", variants = { A = {}, B = {} } },
		flamethrower = { name = "Flamethrower", slot = "ranged", default = "A", variants = { A = {} }, element = "fire" },
		lavaGun = { name = "Lava Gun", slot = "ranged", default = "A", variants = { A = {} }, element = "lava" },
		greataxe = { name = "Greataxe", slot = "melee", default = "A", variants = { A = {} } },
	},
	starters = { broadsword = true, longbow = true },
	expeditions = {
		abilities = {
			list = {
				{ id = "doubleJump", name = "Double Jump", text = "A second jump in the air.", price = { valor = 10 }, order = 1 },
			},
		},
	},
}

-- A PlayerState holding what the verdicts read.
function W2.player(families: any?, abilities: any?): any
	return { combat = { valor = 0, materials = {}, families = families, abilities = abilities } }
end

function W2.unlockTests(): ()
	print(" Unlocks: owned families, element keys, the set-family verdict (L2-30 to L2-32)")
	local U = W2.Unlocks
	local weapons, starters = W2.weapons, W2.starters
	check(U.MAX_VARIANT_LENGTH == 8, `a variant key is at most 8 bytes ({U.MAX_VARIANT_LENGTH})`)

	local made = U.Starters({ melee = "broadsword", ranged = "longbow" })
	check(made.broadsword == true and made.longbow == true and next(made, next(made)) ~= nil, "the starters are the loadout's two families")
	local count = 0
	for _ in made do
		count += 1
	end
	check(count == 2, `and nothing else ({count})`)
	check(next(U.Starters(nil)) == nil and next(U.Starters({ melee = 5, ranged = "" } :: any)) == nil, "no loadout, a number or an empty name: no starter")

	check(U.OwnsFamily(nil, "broadsword", starters) and U.OwnsFamily({}, "longbow", starters), "a starter is owned with no families written")
	check(U.OwnsFamily({ flamethrower = true }, "flamethrower", starters), "a written family is owned")
	check(not U.OwnsFamily({ flamethrower = false }, "flamethrower", starters) and not U.OwnsFamily({}, "flamethrower", starters) and not U.OwnsFamily(nil, "flamethrower", starters), "a family the profile does not hold true for is not")
	check(not U.OwnsFamily({ greataxe = 1 } :: any, "greataxe", starters), "a value other than true is not ownership")

	check(U.ElementOf(weapons, "flamethrower") == "fire" and U.ElementOf(weapons, "broadsword") == "ice", "ElementOf reads the family's element")
	check(U.ElementOf(weapons, "longbow") == nil and U.ElementOf(weapons, "nobody") == nil and U.ElementOf(nil, "flamethrower") == nil, "no element, no family, no roster: nil")
	check(U.ElementOf(weapons, "lavaGun") == nil, "a word that is not an element is no element")

	check(U.HasElement({ flamethrower = true }, weapons, starters, "fire"), "an owned fire family holds fire")
	check(not U.HasElement({}, weapons, starters, "fire") and not U.HasElement(nil, weapons, starters, "fire"), "fire not held before the family is found")
	check(U.HasElement(nil, weapons, starters, "ice"), "a starter's element is held (owned by everyone)")
	check(not U.HasElement({ lavaGun = true }, weapons, starters, "lava"), "a word that is not an element is never held, even by a family that says it")
	check(not U.HasElement({ flamethrower = true }, nil, starters, "fire"), "no roster, no element")
	check(not U.HasElement({ flamethrower = true }, weapons, {}, "ice"), "ice is not held when only fire is owned")

	local config = W2.expeditions
	local owner = W2.player({ flamethrower = true }, { doubleJump = true })
	check(U.HoldsKey(owner.combat, config, weapons, {}, "doubleJump"), "HoldsKey: a sold ability that is owned")
	check(U.HoldsKey(owner.combat, config, weapons, {}, "fire"), "HoldsKey: an element an owned family carries")
	check(not U.HoldsKey(owner.combat, config, weapons, {}, "ice") and not U.HoldsKey(owner.combat, config, weapons, {}, "glide") and not U.HoldsKey(owner.combat, config, weapons, {}, ""), "ice (not owned), an unknown word and the empty word: not held")
	local bare = W2.player(nil, nil)
	check(not U.HoldsKey(bare.combat, config, weapons, {}, "fire") and not U.HoldsKey(bare.combat, config, weapons, {}, "doubleJump"), "a bare profile holds no key")
	local claims = W2.player({}, { fire = true })
	check(not U.HoldsKey(claims.combat, config, weapons, {}, "fire"), "an ability map claiming `fire` is no fire key")

	-- FamilyVerdict, every reason in order.
	local function verdict(state: any, slot: string, family: string, variant: string, gate: boolean): string?
		return U.FamilyVerdict(state, weapons, starters, slot, family, variant, gate)
	end
	check(verdict(nil, "ranged", "flamethrower", "A", true) == "unavailable", "no profile: unavailable")
	check(verdict(nil, "melee", "nobody", "Z", false) == "unavailable", "no profile comes before every other reason")
	local plain = W2.player({}, nil)
	check(verdict(plain, "ranged", "nobody", "A", true) == "invalid", "an unknown family: invalid")
	check(verdict(plain, "ranged", "longbow", "C", true) == "invalid", "an unknown variant: invalid")
	check(verdict(plain, "melee", "longbow", "A", true) == "invalid", "a family of the other slot: invalid")
	check(verdict(plain, "ranged", "flamethrower", "B", false) == "invalid", "invalid comes before locked and busy")
	check(verdict(plain, "ranged", "flamethrower", "A", true) == "locked", "a family not owned: locked")
	check(verdict(plain, "ranged", "flamethrower", "A", false) == "locked", "locked comes before busy")
	local found = W2.player({ flamethrower = true }, nil)
	check(verdict(found, "ranged", "flamethrower", "A", false) == "busy", "owned, the gate shut: busy")
	check(verdict(found, "ranged", "flamethrower", "A", true) == nil, "owned, the gate open: held")
	check(verdict(plain, "melee", "broadsword", "B", true) == nil and verdict(plain, "ranged", "longbow", "A", true) == nil, "a starter is held without any family written")
	check(U.FamilyVerdict(plain, nil, starters, "ranged", "longbow", "A", true) == "invalid", "no roster: invalid")
end
L1.group("l2w2 unlockTests", W2.unlockTests)

-- A capsule from `origin` along `direction` for `size` studs.
function W2.capsule(origin: any, direction: any, size: number, width: number?): any
	return { shape = "capsule", origin = origin, direction = direction, size = size, width = width }
end

function W2.reactTests(): ()
	print(" WorldReact: a strike's segment against a reactive block (L2-34, L2-35)")
	local R = W2.React
	local east = vec(1, 0, 0)
	-- A 2-stud block at x 10: its faces at x 9 and 11, y and z -1 to 1.
	local box = { x = 10, y = 0, z = 0, sx = 2, sy = 2, sz = 2 }
	local origin = vec(0, 0, 0)

	local a, b = R.Segment(W2.capsule(origin, east, 8))
	check(a ~= nil and b ~= nil and b.X == 8 and b.Y == 0 and b.Z == 0, "a capsule's segment runs size studs along its direction")
	local _, longer = R.Segment(W2.capsule(origin, vec(2, 0, 0), 8))
	check(longer ~= nil and longer.X == 8, "a direction that is not a unit is made one")
	local _, ended = R.Segment({ shape = "ray", origin = origin, direction = east, size = 40, endPoint = vec(5, 0, 0) })
	check(ended ~= nil and ended.X == 5, "a ray ends at its endPoint")
	local _, open = R.Segment({ shape = "ray", origin = origin, direction = east, size = 40 })
	check(open ~= nil and open.X == 40, "a ray with no endPoint runs its size")
	local none = 0
	for _, shape in { "arc", "cone", "sphere" } do
		if R.Segment({ shape = shape, origin = origin, direction = east, size = 20 }) ~= nil then
			none += 1
		end
	end
	check(none == 0, "an arc, a cone or a sphere sweeps no segment (they burn nothing)")
	check(R.Segment(W2.capsule(origin, vec(0, 0, 0), 8)) == nil, "a capsule with no direction: no segment")
	check(R.Segment(W2.capsule(origin, east, W2.NAN)) == nil and R.Segment(W2.capsule(origin, east, -1)) == nil and R.Segment(W2.capsule(origin, east, math.huge)) == nil, "a size that is NaN, negative or endless: no segment")
	check(R.Segment(W2.capsule(vec(W2.NAN, 0, 0), east, 8)) == nil, "an origin that is not finite: no segment")
	check(R.Segment({ shape = "ray", origin = vec(W2.NAN, 0, 0), direction = east, size = 40, endPoint = vec(5, 0, 0) }) == nil, "nor for a ray that names where it stopped")

	-- The face, the pad and the width.
	check(not R.Touches(W2.capsule(origin, east, 8), box, 0), "a stream that stops a stud short does not touch")
	check(R.Touches(W2.capsule(origin, east, 9), box, 0), "a stream that ends on the face touches (closed)")
	check(R.Touches(W2.capsule(origin, east, 8.5), box, 0.5) and not R.Touches(W2.capsule(origin, east, 8.4), box, 0.5), "the pad grows the block: within it touches, beyond it not")
	check(R.Touches(W2.capsule(origin, east, 8, 2), box, 0) and not R.Touches(W2.capsule(origin, east, 7.9, 2), box, 0), "half the width grows it too")
	check(R.Touches(W2.capsule(origin, east, 7.5, 2), box, 0.5) and not R.Touches(W2.capsule(origin, east, 7.4, 2), box, 0.5), "width / 2 and the pad add")
	check(R.Touches(W2.capsule(vec(0, 0, 1.5), east, 20), box, 0.5) and not R.Touches(W2.capsule(vec(0, 0, 1.6), east, 20), box, 0.5), "beside the block: the grown side face is the edge")
	check(R.Touches(W2.capsule(vec(0, 0, -1.5), east, 20), box, 0.5) and not R.Touches(W2.capsule(vec(0, 0, -1.6), east, 20), box, 0.5), "the other side face too")
	check(R.Touches(W2.capsule(vec(0, 1.5, 0), east, 20), box, 0.5) and not R.Touches(W2.capsule(vec(0, 1.6, 0), east, 20), box, 0.5), "over the block: the grown top")
	check(R.Touches(W2.capsule(vec(0, -1.5, 0), east, 20), box, 0.5) and not R.Touches(W2.capsule(vec(0, -1.6, 0), east, 20), box, 0.5), "under it: the grown bottom")
	check(R.Touches(W2.capsule(vec(20, 0, 0), vec(-1, 0, 0), 9), box, 0) and not R.Touches(W2.capsule(vec(20, 0, 0), vec(-1, 0, 0), 8.9), box, 0), "from the far side: the far face, closed")
	check(not R.Touches(W2.capsule(origin, vec(-1, 0, 0), 30), box, 0.5), "a stream aimed away never touches")
	check(R.Touches(W2.capsule(vec(10, 0, 0), east, 1), box, 0), "a stream that starts inside touches")
	check(R.Touches(W2.capsule(vec(0, 0, 0), vec(10, 0, 1.5), 15), box, 0.5) and not R.Touches(W2.capsule(vec(0, 0, 0), vec(10, 0, 2), 15), box, 0.5), "a slanted stream: through the grown corner or past it")
	check(R.Touches(W2.capsule(vec(0, 0, 10), vec(0, 0, -1), 20, 0), { x = 0, y = 0, z = 0, sx = 2, sy = 2, sz = 2 }, 0), "a stream along an axis with no motion on the others (the zero-delta branch)")
	check(not R.Touches(W2.capsule(vec(3, 0, 10), vec(0, 0, -1), 20, 0), { x = 0, y = 0, z = 0, sx = 2, sy = 2, sz = 2 }, 0), "and one beside it on that branch")
	check(R.Touches(W2.capsule(origin, east, 8.5), box, -3) == false and R.Touches(W2.capsule(origin, east, 9), box, -3), "a negative pad counts as 0")
	check(R.Touches(W2.capsule(origin, east, 8.5, -4), box, 0) == false, "a negative width counts as 0")
	check(R.Touches({ shape = "ray", origin = origin, direction = east, size = 40, endPoint = vec(8, 0, 0) }, box, 0.5) == false and R.Touches({ shape = "ray", origin = origin, direction = east, size = 40, endPoint = vec(9.5, 0, 0) }, box, 0), "a ray is judged up to where it stopped")
	check(not R.Touches({ shape = "cone", origin = origin, direction = east, size = 40, width = 40 }, box, 10), "a cone touches nothing however wide (Dragon's Breath burns no bramble)")
	check(not R.Touches(W2.capsule(origin, east, 20), { x = 10, y = 0, z = 0, sx = 0, sy = 2, sz = 2 }, 0.5), "a block with no size is met by nothing")
	check(not R.Touches(W2.capsule(origin, east, 20), { x = W2.NAN, y = 0, z = 0, sx = 2, sy = 2, sz = 2 }, 0.5), "a block that is not finite is met by nothing")

	-- How many strikes, the pad, the heat.
	local rules = { fireHits = 6, pad = 0.5 }
	check(R.Need(rules, "fire") == 6, "fire takes fireHits")
	check(R.Need(rules, "ice") == nil and R.Need({ iceHits = 3 }, "ice") == 3, "ice takes iceHits, and none without it")
	check(R.Need(nil, "fire") == nil and R.Need(rules, "lava") == nil, "no rules, or a word that is no element: nothing reacts")
	check(R.Need({ fireHits = 0 }, "fire") == nil and R.Need({ fireHits = 2.5 }, "fire") == nil and R.Need({ fireHits = W2.NAN }, "fire") == nil and R.Need({ fireHits = math.huge }, "fire") == nil, "a count of 0, a fraction, NaN or endless: nothing reacts")
	check(R.Need({ fireHits = 1 }, "fire") == 1, "a count of 1 is a count")
	check(R.Pad(rules) == 0.5 and R.Pad(nil) == 0 and R.Pad({ pad = -1 }) == 0 and R.Pad({ pad = W2.NAN }) == 0, "the pad: as given, or 0")
	local heat, done = R.Heat(0, 6)
	check(heat == 1 and not done, "one strike of six")
	heat, done = R.Heat(4, 6)
	check(heat == 5 and not done, "the fifth is not the last")
	heat, done = R.Heat(5, 6)
	check(heat == 6 and done, "the sixth takes it away")
	heat, done = R.Heat(0, 1)
	check(heat == 1 and done, "a count of 1: the first strike")
	heat, done = R.Heat(3, 0)
	check(heat == 3 and not done, "a need of 0 adds nothing and never takes it")
	heat, done = R.Heat(3, 2.5)
	check(heat == 3 and not done, "nor does a fractional need")
	check(R.Share(3, 6) == 0.5 and R.Share(0, 6) == 0 and R.Share(9, 6) == 1 and R.Share(3, 0) == 0, "the share of the way: heat over need, held to 0 to 1")
end
L1.group("l2w2 reactTests", W2.reactTests)

function W2.shortcutTests(): ()
	print(" SecretFlow: shortcuts read, found and recorded (L2-36)")
	local S = W2.Secret
	local layout = {
		shortcuts = {
			{ id = "cave", name = "Raiders' Tunnel", x = 10, y = 4, z = -20, sx = 12, sy = 8, sz = 6 },
			{ id = "bad", name = "x", x = W2.NAN, y = 0, z = 0, sx = 1, sy = 1, sz = 1 },
			{ id = 5, name = "x", x = 0, y = 0, z = 0, sx = 1, sy = 1, sz = 1 },
			{ id = "neg", name = "x", x = 0, y = 0, z = 0, sx = -1, sy = 1, sz = 1 },
			{ id = "nameless", x = 0, y = 0, z = 0, sx = 1, sy = 1, sz = 1 },
		},
	}
	local list = S.Shortcuts(layout)
	check(#list == 2 and list[1].id == "cave" and list[2].id == "nameless", `the sound entries in order; NaN, a number id and a negative size skipped ({#list})`)
	check(list[1].name == "Raiders' Tunnel" and list[2].name == "nameless", "a missing name reads as the id")
	check(#S.Shortcuts({}) == 0 and #S.Shortcuts({ shortcuts = "cave" } :: any) == 0, "no list, or a list that is not one: none")

	local cave = list[1]
	check(S.InShortcut(cave, vec(10, 4, -20)), "the centre is inside")
	check(S.InShortcut(cave, vec(16, 4, -20)) and S.InShortcut(cave, vec(4, 4, -20)) and not S.InShortcut(cave, vec(16.01, 4, -20)) and not S.InShortcut(cave, vec(3.99, 4, -20)), "X: each face inside (closed), a hair past it out")
	check(S.InShortcut(cave, vec(10, 8, -20)) and S.InShortcut(cave, vec(10, 0, -20)) and not S.InShortcut(cave, vec(10, 8.01, -20)) and not S.InShortcut(cave, vec(10, -0.01, -20)), "Y: the same")
	check(S.InShortcut(cave, vec(10, 4, -17)) and S.InShortcut(cave, vec(10, 4, -23)) and not S.InShortcut(cave, vec(10, 4, -16.99)) and not S.InShortcut(cave, vec(10, 4, -23.01)), "Z: the same")

	local combat: any = { valor = 0, materials = {} }
	check(S.RecordShortcut(combat, "forestRoad", "cave") == true, "a first find is new")
	check(combat.shortcuts ~= nil and combat.shortcuts.forestRoad.cave == true, "and is written, the maps made where the profile lacked them")
	check(S.RecordShortcut(combat, "forestRoad", "cave") == false, "a second find is not new")
	check(S.RecordShortcut(combat, "forestRoad", "other") == true and S.RecordShortcut(combat, "castle", "cave") == true, "another id, or the same id on another level, is new")
	check(combat.shortcuts.forestRoad.cave and combat.shortcuts.forestRoad.other and combat.shortcuts.castle.cave, "each find stays")
	local kept: any = { valor = 0, materials = {}, shortcuts = { forestRoad = { old = true } } }
	local mine = kept.shortcuts.forestRoad
	S.RecordShortcut(kept, "forestRoad", "cave")
	check(kept.shortcuts.forestRoad == mine and mine.old == true and mine.cave == true, "a level's map already there is kept, with what is in it")

	local open = S.FoundShortcuts(combat, "forestRoad")
	check(open.cave == true and open.other == true, "FoundShortcuts: the level's finds")
	open.extra = true
	check(combat.shortcuts.forestRoad.extra == nil, "a set of its own: writing it leaves the profile alone")
	check(next(S.FoundShortcuts(nil, "forestRoad")) == nil and next(S.FoundShortcuts(combat, "nowhere")) == nil, "no profile, or a level with no finds: empty")
	check(S.FoundShortcuts({ shortcuts = { forestRoad = { cave = false } } } :: any, "forestRoad").cave == nil, "a value other than true is no find")

	local bare: any = { valor = 0, materials = {} }
	local families = S.FamiliesOf(bare)
	check(type(families) == "table" and bare.families == families and S.FamiliesOf(bare) == families, "FamiliesOf makes the map once and hands back the same one")
end
L1.group("l2w2 shortcutTests", W2.shortcutTests)

function W2.piecesTests(): ()
	print(" LevelGeometry.Pieces: reactive blocks, and the blocks a found shortcut leaves out (L2-34, L2-36)")
	local Geo = W2.Geo
	local function layout(): any
		return {
			version = 1,
			start = { x = 0, y = 0, z = 0 },
			killY = -40,
			camps = {},
			blocks = {
				{ name = "Road", look = "path", x = 0, y = -2, z = 0, sx = 20, sy = 4, sz = 20 },
				{ name = "BrambleMouth", look = "bramble", x = 0, y = 4, z = -12, sx = 12, sy = 8, sz = 2, react = "fire", opens = "cave" },
				{ name = "BrambleExit", look = "bramble", x = 30, y = 4, z = -12, sx = 12, sy = 8, sz = 2, react = "fire", opens = "cave" },
				{ name = "Wall", look = "wall", x = 0, y = 10, z = -20, sx = 40, sy = 20, sz = 2 },
				{ name = "Ice", look = "bramble", x = -30, y = 4, z = -12, sx = 6, sy = 8, sz = 2, react = "ice" },
			},
			secrets = {},
			route = {},
		}
	end
	local sizes = { fence = 1, floor = 4 }
	local function byName(pieces: any): { [string]: any }
		local found = {}
		for _, piece in pieces or {} do
			found[piece.name] = piece
		end
		return found
	end
	local all = byName(Geo.Pieces(layout(), sizes, 600))
	local mouth = all.BrambleMouth
	check(mouth ~= nil and mouth.react == "fire" and mouth.opens == "cave" and mouth.role == "block" and mouth.collide == true, "a reactive block keeps its react and opens on its piece")
	check(all.Wall ~= nil and all.Wall.react == nil and all.Wall.opens == nil, "a plain block has neither")
	check(all.Ice ~= nil and all.Ice.react == "ice" and all.Ice.opens == nil, "a reactive block that opens nothing")

	local source = layout()
	local opened = byName(Geo.Pieces(source, sizes, 600, { cave = true }))
	check(opened.BrambleMouth == nil and opened.BrambleExit == nil, "a found shortcut leaves out every block that opens it")
	check(opened.Wall ~= nil and opened.Road ~= nil and opened.Ice ~= nil, "and nothing else")
	check(#source.blocks == 5 and source.blocks[2].name == "BrambleMouth", "the layout itself still holds the block (a copy is measured)")
	local others = byName(Geo.Pieces(layout(), sizes, 600, { tunnel = true }))
	check(others.BrambleMouth ~= nil and others.BrambleExit ~= nil, "another shortcut's find leaves them standing")
	local empty = byName(Geo.Pieces(layout(), sizes, 600, {}))
	check(empty.BrambleMouth ~= nil, "an empty set leaves them standing")
	local falsy = byName(Geo.Pieces(layout(), sizes, 600, { cave = false } :: any))
	check(falsy.BrambleMouth ~= nil, "a set holding false for it leaves them standing")
	local count = 0
	for _ in opened do
		count += 1
	end
	local before = 0
	for _ in all do
		before += 1
	end
	check(count == before - 2, `exactly two Parts fewer ({before} then {count})`)
	-- The road is ground: measured on the copy, its depth is the same either way.
	check(all.Road.box.sy == opened.Road.box.sy and all.Road.box.y == opened.Road.box.y, "the blocks that stay are built exactly as before")
end
L1.group("l2w2 piecesTests", W2.piecesTests)

function W2.flowTests(): ()
	print(" StageFlow.Validate: react, opens and shortcuts (L2-34, L2-36)")
	local Flow = L1.Flow
	local got = L1.real.resolve("forestRoad")
	local level, layout = got.level, got.layout
	if level == nil or layout == nil then
		check(false, "Forest Road resolves (the cases below need it)")
		return
	end
	local ranks = L1.real.ranks()
	-- A copy of Forest Road with a tunnel of its own (whatever the shipped layout already has),
	-- then `mutate`; only the lines about blocks, react, opens and shortcuts are kept.
	local function problems(mutate: (any) -> ()): { string }
		local copyLevel, copyLayout = L1.copy(level), L1.copy(layout)
		copyLayout.shortcuts = copyLayout.shortcuts or {}
		table.insert(copyLayout.shortcuts, { id = "testTunnel", name = "Test Tunnel", x = 0, y = 400, z = 0, sx = 4, sy = 4, sz = 4 })
		table.insert(copyLayout.blocks, { name = "TestBramble", look = "bramble", x = 0, y = 400, z = 10, sx = 4, sy = 4, sz = 1, react = "fire", opens = "testTunnel" })
		mutate(copyLayout)
		local found = {}
		for _, line in Flow.Validate(copyLevel, copyLayout, L1.real.kinds, ranks, L1.real.rules, FIXTURES.proving.crowd.maxAlive) do
			if string.find(line, "shortcut", 1, true) or string.find(line, "react", 1, true) or string.find(line, "opens", 1, true) then
				table.insert(found, line)
			end
		end
		return found
	end
	local function last(o: any): any
		return o.blocks[#o.blocks]
	end
	local function tunnel(o: any): any
		return o.shortcuts[#o.shortcuts]
	end
	check(#problems(function() end) == 0, `a tunnel and its bramble are accepted ({table.concat(problems(function() end), "; ")})`)
	check(#problems(function(o: any) last(o).react = "ice" end) == 0, "ice is a word a block may react to")
	check(#problems(function(o: any) last(o).react = nil end) == 0, "a block that opens a shortcut and reacts to nothing is not refused")
	check(#problems(function(o: any) last(o).opens = nil end) == 0, "nor one that reacts and opens nothing")
	local refusals = {
		{ "react to lava", function(o: any) last(o).react = "lava" end },
		{ "react that is a number", function(o: any) last(o).react = 5 end },
		{ "a reactive block that does not collide", function(o: any) last(o).collide = false end },
		{ "opens naming no shortcut", function(o: any) last(o).opens = "nowhere" end },
		{ "opens that is a number", function(o: any) last(o).opens = 7 end },
		{ "shortcuts that are not a list", function(o: any) o.shortcuts = "cave" end },
		{ "a shortcut with no id", function(o: any) tunnel(o).id = nil end },
		{ "a shortcut with an empty id", function(o: any) tunnel(o).id = "" end },
		{ "a shortcut id of 33 bytes", function(o: any) tunnel(o).id = string.rep("s", 33) last(o).opens = string.rep("s", 33) end },
		{ "a shortcut id used twice", function(o: any) table.insert(o.shortcuts, L1.copy(tunnel(o))) end },
		{ "a shortcut with a NaN x", function(o: any) tunnel(o).x = W2.NAN end },
		{ "a shortcut with an endless sz", function(o: any) tunnel(o).sz = math.huge end },
		{ "a shortcut with a y that is a string", function(o: any) tunnel(o).y = "4" end },
		{ "a shortcut that is not a table", function(o: any) table.insert(o.shortcuts, "cave") end },
	}
	local missed = {}
	for _, case in refusals do
		if #problems(case[2]) == 0 then
			table.insert(missed, case[1])
		end
	end
	check(#missed == 0, `each broken line refuses the level (accepted: {table.concat(missed, ", ")})`)
	check(#problems(function(o: any) tunnel(o).id = string.rep("s", 32) last(o).opens = string.rep("s", 32) end) == 0, "a shortcut id of 32 bytes is fine")
	local function noOpens(o: any): ()
		o.shortcuts = nil
		for _, block in o.blocks do
			block.opens = nil
		end
	end
	check(#problems(noOpens) == 0, "a layout with no shortcuts (and no block that opens one) needs none")
	check(#problems(function(o: any) noOpens(o) last(o).opens = "testTunnel" end) == 1, "a block that opens something with no shortcuts list at all: one line")
end
L1.group("l2w2 flowTests", W2.flowTests)

function W2.tuningTests(): ()
	print(" Tuning: a family's element is structural (L2-29)")
	local saved = config.weapons
	config.weapons = {
		flamethrower = { name = "Flamethrower", slot = "ranged", era = 1, default = "A", element = "fire", variants = { A = { damage = 5, continuous = true } } },
	}
	local ok, problem = pcall(function()
		local Tune = load("Tuning")
		check(not Tune.Validate("weapons.flamethrower.element", "ice") and not Tune.Validate("weapons.flamethrower.element", "fire"), "the element cannot be tuned, to another word or to itself")
		check(Tune.Validate("weapons.flamethrower.variants.A.damage", 6), "a number of the same family still tunes (the rule is the element's alone)")
	end)
	config.weapons = saved
	check(ok, `the Tuning cases ran ({tostring(problem)})`)
end
L1.group("l2w2 tuningTests", W2.tuningTests)

-- The shipped files (economy-designer's data): the cache pays behind fire, the tunnel's brambles
-- burn and open the shortcut, the Flamethrower carries fire.
function W2.realTests(): ()
	print(" The real files: the Raiders' Cache behind fire, the tunnel's brambles and its shortcut")
	local S, U = W2.Secret, W2.Unlocks
	local file = L1.real.file("forestRoad")
	local layout = file ~= nil and L1.real.layouts[file.layout] or nil
	if file == nil or layout == nil then
		check(false, "Forest Road's file and layout are there")
		return
	end
	local weapons = FIXTURES.proving.weapons
	local starters = U.Starters(FIXTURES.proving.loadout)
	check(U.ElementOf(weapons, "flamethrower") == "fire", "ProvingGrounds.json: the Flamethrower carries fire")
	check(next(starters) ~= nil and not starters.flamethrower, "the Flamethrower is no starter")
	local fireStarters = 0
	for family in starters do
		if U.ElementOf(weapons, family) ~= nil then
			fireStarters += 1
		end
	end
	check(fireStarters == 0, "no starter carries an element (every element is found)")

	local byId = {}
	for _, site in S.Sites(layout, file) do
		byId[site.id] = site
	end
	local cache, shrine = byId.cache, byId.shrine
	if cache == nil or shrine == nil then
		check(false, "the cache and the shrine are sites")
		return
	end
	local reward = cache.reward
	check(cache.needs == "fire" and reward ~= nil and reward.valor >= 2 and reward.valor <= 9 and reward.materials > 0 and reward.family == nil, `the cache needs fire and pays 2 to 9 Valor and Timber, no family ({reward and reward.valor}, {reward and reward.materials})`)
	local config = L1.real.map
	local before = { valor = 0, materials = {}, abilities = { doubleJump = true }, families = {} }
	local after = { valor = 0, materials = {}, abilities = { doubleJump = true }, families = { flamethrower = true } }
	check(S.Decide(cache, U.HoldsKey(before, config, weapons, starters, cache.needs), false) == "locked", "the cache: locked before the lookout has paid the Flamethrower")
	check(S.Decide(cache, U.HoldsKey(after, config, weapons, starters, cache.needs), false) == "pay", "and pays once it has, whatever is carried")
	check(S.Decide(shrine, U.HoldsKey(after, config, weapons, starters, shrine.needs), false) == "locked", "the shrine stays locked with the Flamethrower (ice is W3's)")

	local shortcuts = S.Shortcuts(layout)
	check(#shortcuts == 1 and shortcuts[1].id == "cave", `the layout has one shortcut, the cave ({#shortcuts})`)
	local brambles = {}
	for _, block in layout.blocks do
		if block.opens ~= nil then
			table.insert(brambles, block)
		end
	end
	local sound = #brambles >= 2
	for _, block in brambles do
		sound = sound and block.opens == "cave" and block.react == "fire" and block.collide ~= false
	end
	check(sound, `both mouths are fire brambles that collide and open the cave ({#brambles})`)
	local closed = L1.real.pieces(layout)
	local ok, opened = pcall(L1.Geo.Pieces, layout, L1.real.sizes(), L1.real.rules.maxParts, { cave = true })
	if closed == nil or not ok or opened == nil then
		check(false, "the shipped layout builds closed and open")
		return
	end
	local names = {}
	for _, piece in opened do
		names[piece.name] = true
	end
	local left = 0
	for _, block in brambles do
		if names[block.name] then
			left += 1
		end
	end
	check(left == 0 and #opened == #closed - #brambles, `the open tunnel is built without its brambles and nothing else ({#closed} then {#opened})`)
	local reactive = 0
	for _, piece in closed do
		if piece.react == "fire" then
			reactive += 1
		end
	end
	check(reactive == #brambles, `closed, each bramble is a reactive piece ({reactive})`)
end
L1.group("l2w2 realTests", W2.realTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
