-- Cases for L3 W1's Armory screen (docs/prompts/l3-w1-contract.md, L3-18 to L3-21): the pure
-- ArmoryModel the screen paints from. Shelf order, the hints, the pips, the next and cost lines,
-- every button's state and words, the toasts and the wallet, on a small roster built here, then
-- on the files as they ship. Appended by run_harness.py after the earlier case files, so every
-- local of theirs is in scope (check, load, L1, ARMORY, FIXTURES). Everything hangs off the UI3
-- table (the 200-local limit) and every group runs behind L1.group. The screen itself (its
-- Instances, the router, gamepad A) cannot load here: Studio is its test.

print("L3 W1: the Armory screen's model (ArmoryModel)")

local UI3: any = {
	Model = load("ArmoryModel"),
	-- A ladder of 20 like Armory.json's (L3-1, L3-2, L3-4), five bands of four.
	ladder = {
		damage = {
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
		hp = {
			melee = {
				35,
				50,
				80,
				120,
				170,
				250,
				350,
				480,
				700,
				950,
				1300,
				1700,
				2200,
				2800,
				3500,
				4300,
				5200,
				6200,
				7300,
				8500,
			},
			ranged = {
				20,
				30,
				50,
				80,
				110,
				160,
				230,
				320,
				450,
				620,
				850,
				1100,
				1400,
				1750,
				2150,
				2600,
				3100,
				3650,
				4250,
				4900,
			},
		},
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
	},
	windows = {
		broadsword = { start = 1, top = 12 },
		axe = { start = 1, top = 10 },
		longbow = { start = 1, top = 12 },
		flamethrower = { start = 2, top = 8 },
		warhammer = { start = 3, top = 16 },
		splitbow = { start = 8, top = 8 },
		spinblade = { start = 20, top = 20 },
	},
	-- Two starters, a two-style bow, a fire family a secret pays, a melee family nobody starts
	-- with, a relic, a family with no window, one the screen cannot show (no such slot).
	weapons = {
		broadsword = {
			name = "Broadsword",
			slot = "melee",
			default = "A",
			variants = { A = { label = "Wide arc", damage = 24 } },
			ability = { name = "Whirlwind" },
		},
		axe = {
			name = "Axe",
			slot = "melee",
			default = "A",
			variants = { A = { label = "Chop", damage = 30 } },
		},
		longbow = {
			name = "Longbow",
			slot = "ranged",
			default = "A",
			variants = {
				A = { label = "Pierce + blast", damage = 45 },
				B = { label = "Quick shot", damage = 42 },
			},
			ability = { name = "Arrow Rain" },
		},
		flamethrower = {
			name = "Flamethrower",
			slot = "ranged",
			default = "A",
			variants = { A = { label = "Flame stream", damage = 5 } },
			element = "fire",
		},
		warhammer = {
			name = "Warhammer",
			slot = "melee",
			default = "A",
			variants = { A = { label = "Shockwave", damage = 44 } },
		},
		splitbow = {
			name = "Splitbow",
			slot = "ranged",
			default = "A",
			variants = {
				A = { label = "Fan of 7", damage = 26 },
				B = { label = "Wide fan", damage = 42 },
			},
		},
		spinblade = {
			name = "Spinblade",
			slot = "melee",
			default = "A",
			variants = { A = { label = "Spin", damage = 16 } },
		},
		oddity = {
			name = "Oddity",
			slot = "melee",
			default = "A",
			variants = { A = { label = "Odd", damage = 1 } },
		},
		broken = {
			name = "Broken",
			slot = "both",
			default = "A",
			variants = { A = { label = "?", damage = 1 } },
		},
	},
	loadout = { melee = "broadsword", ranged = "longbow" },
	expeditions = {
		difficultyNames = { normal = "Normal", hard = "Hard", brutal = "Brutal" },
		nodes = {
			{
				id = "forestRoad",
				name = "Forest Road",
				theme = "forest",
				kind = "level",
				level = "forestRoad",
			},
			{ id = "castle", name = "Castle", theme = "castle", kind = "level" },
			{ id = "dream", name = "The Dream", theme = "dream", kind = "level" },
		},
		themes = {
			forest = { color = { 70, 182, 101 } },
			castle = { color = { 143, 163, 199 } },
			dream = { color = { 255, 142, 196 } },
		},
		found = {
			warhammer = { node = "forestRoad", text = "First Hard clear of Forest Road" },
			-- A secret pays it too: the secret's line wins.
			flamethrower = { node = "forestRoad", text = "Somewhere else" },
			spinblade = { node = "dream", text = "Hidden in the Dream" },
		},
	},
	levels = {
		forestRoad = {
			id = "forestRoad",
			name = "Forest Road",
			secrets = {
				lookout = { name = "The Lookout", family = "flamethrower" },
				cache = { name = "Cache" },
			},
		},
	},
	built = { forestRoad = true },
}
UI3.armory = {
	version = 1,
	baseHp = 100,
	power = { hpWeight = 0.1, tierWeight = 11 },
	ladder = UI3.ladder,
	windows = UI3.windows,
}

-- A combat profile; `over` replaces fields.
function UI3.combat(over: any?): any
	local combat: any = {
		materials = { Timber = 0 },
		valor = 0,
		families = {},
		tiers = {},
		stars = {},
		loadout = { variants = {} },
		abilities = {},
	}
	for key, value in over or {} do
		combat[key] = value
	end
	return combat
end

-- The model's inputs; `over` replaces fields (`noCombat` = before the first Snapshot).
function UI3.inputs(over: any?): any
	local inputs: any = {
		armory = UI3.armory,
		weapons = UI3.weapons,
		loadout = UI3.loadout,
		expeditions = UI3.expeditions,
		levels = UI3.levels,
		built = UI3.built,
		combat = UI3.combat(),
		held = nil,
		gateOpen = true,
		pending = {},
	}
	for key, value in over or {} do
		inputs[key] = value
	end
	if inputs.noCombat then
		inputs.combat = nil
	end
	return inputs
end

function UI3.detail(over: any?, family: string): any
	return UI3.Model.Detail(UI3.inputs(over), family)
end

function UI3.families(cards: any): string
	local ids = {}
	for _, card in cards do
		table.insert(ids, card.family)
	end
	return table.concat(ids, ",")
end

function UI3.shelfTests(): ()
	print(" The shelf: order, ownership, hints (L3-19, L3-25)")
	local M = UI3.Model
	local cards = M.Shelf(UI3.inputs())
	local order = UI3.families(cards)
	check(
		order == "axe,broadsword,longbow,flamethrower,warhammer,splitbow,spinblade,oddity",
		`by window start, melee before ranged, then name; no window last; a slot that is neither left out ({order})`
	)
	local by: any = {}
	for _, card in cards do
		by[card.family] = card
	end
	check(
		by.broadsword.owned and by.longbow.owned and not by.axe.owned and not by.warhammer.owned,
		"the two starters are owned, the rest are not"
	)
	check(
		by.broadsword.held and by.longbow.held and not by.axe.held,
		"the starters are held before the host says a loadout"
	)
	check(
		by.flamethrower.hint == "Hidden on Forest Road",
		`a family a secret pays reads "Hidden on <level>", over its found entry ({by.flamethrower.hint})`
	)
	check(
		by.warhammer.hint == "First Hard clear of Forest Road"
			and by.spinblade.hint == "Hidden in the Dream",
		"a found entry's text is the hint of a family no secret pays"
	)
	check(
		by.axe.hint == nil and by.broadsword.hint == nil,
		"no hint for a family nothing names, nor for an owned one"
	)
	check(
		by.flamethrower.element == "fire" and by.longbow.element == nil,
		"the element comes from Unlocks.ElementOf"
	)
	check(
		by.longbow.tierText == "T1"
			and by.flamethrower.tierText == "T2"
			and by.spinblade.tierText == "T20",
		"an unbought family stands at its window's start"
	)
	check(
		by.oddity.start == nil and by.oddity.tier == 1,
		"a family with no window has none and stands at T1"
	)
	local saved = M.Shelf(UI3.inputs({
		combat = UI3.combat({
			families = { flamethrower = true },
			tiers = { longbow = 3, flamethrower = 99 },
		}),
	}))
	local savedBy: any = {}
	for _, card in saved do
		savedBy[card.family] = card
	end
	check(
		savedBy.flamethrower.owned and savedBy.flamethrower.hint == nil,
		"a found family is owned and loses its hint"
	)
	check(
		savedBy.longbow.tierText == "T3" and savedBy.flamethrower.tierText == "T8",
		"a saved tier shows, clamped into the window (Armory.TierOf)"
	)
	local early = M.Shelf(UI3.inputs({ noCombat = true }))
	check(
		UI3.families(early) == order and early[1].tierText == "T1",
		"before the first Snapshot the shelf is the same, every family at its start"
	)
	check(
		M.DefaultFamily(UI3.inputs(), cards) == "broadsword",
		"the screen opens on the held melee family"
	)
	check(
		M.DefaultFamily(
			UI3.inputs({ held = { melee = "nothing", ranged = "longbow", variants = {} } }),
			cards
		) == "axe",
		"else on the first card"
	)
	local held = M.Held(UI3.inputs({
		combat = UI3.combat({
			families = { warhammer = true },
			loadout = { melee = "warhammer", variants = { longbow = "B" } },
		}),
	}))
	check(
		held.melee == "warhammer" and held.ranged == "longbow" and held.variants.longbow == "B",
		"with no word from the host the held pair is the saved loadout's reading (Unlocks.LoadoutOf)"
	)
	local unowned = M.Held(
		UI3.inputs({ combat = UI3.combat({ loadout = { melee = "warhammer", variants = {} } }) })
	)
	check(unowned.melee == "broadsword", "a saved family not owned reads as the starter")
end
L1.group("l3ui shelfTests", UI3.shelfTests)

function UI3.pipTests(): ()
	print(" The track: the full ladder of 20 with the window lit (L3-20)")
	local M = UI3.Model
	local longbow = UI3.detail({ combat = UI3.combat({ tiers = { longbow = 3 } }) }, "longbow")
	local pips = longbow.pips
	check(#pips == 20, `twenty pips ({#pips})`)
	local states = {}
	for _, pip in pips do
		table.insert(states, string.sub(pip.state, 1, 1))
	end
	local row = table.concat(states)
	check(row == "lllooooooooodddddddd", `lit to the tier, open to the top, dim past it ({row})`)
	check(
		pips[1].start and pips[12].top and not pips[2].start and not pips[11].top,
		"the start and the top are marked"
	)
	check(
		pips[1].mark == "1" and pips[12].mark == "12" and pips[2].mark == nil,
		"with their numbers"
	)
	check(
		pips[3].current and not pips[2].current and not pips[4].current,
		"the tier it stands at is the current pip"
	)
	check(
		pips[1].band == 1 and pips[4].band == 1 and pips[5].band == 2 and pips[20].band == 5,
		"bands of four"
	)
	local forest = pips[1].color
	check(
		forest ~= nil and forest[1] == 70 and forest[2] == 182 and forest[3] == 101,
		"band 1 in Forest Road's theme colour, through its map node"
	)
	local castle = pips[5].color
	check(
		castle ~= nil and castle[1] == 143,
		"band 2 in the Castle node's colour (a node with no level file)"
	)
	check(pips[9].color == nil, "a band whose level has no node has no colour")
	local relic =
		UI3.detail({ combat = UI3.combat({ families = { spinblade = true } }) }, "spinblade").pips
	local lit, other = 0, 0
	for _, pip in relic do
		if pip.state == "lit" then
			lit += 1
		elseif pip.state ~= "dim" then
			other += 1
		end
	end
	check(
		lit == 1 and other == 0 and relic[20].state == "lit" and relic[20].start and relic[20].top,
		"a relic is one lit pip, at once its start and its top"
	)
	local hidden = UI3.detail(nil, "warhammer").pips
	local open, lights, currents = 0, 0, 0
	for _, pip in hidden do
		if pip.state == "open" then
			open += 1
		elseif pip.state == "lit" then
			lights += 1
		end
		if pip.current then
			currents += 1
		end
	end
	check(
		open == 14 and lights == 0 and currents == 0 and hidden[3].start and hidden[16].top,
		"an unowned family shows its whole window, nothing lit and no current tier"
	)
	local none =
		UI3.detail({ combat = UI3.combat({ families = { oddity = true } }) }, "oddity").pips
	local dim = 0
	for _, pip in none do
		if pip.state == "dim" then
			dim += 1
		end
	end
	check(#none == 20 and dim == 20, "a family with no window: every pip dim")
	check(
		#M.Pips(UI3.inputs({ armory = { version = 1 } }), longbow.card) == 0,
		"no ladder: no pips"
	)
end
L1.group("l3ui pipTests", UI3.pipTests)

function UI3.lineTests(): ()
	print(" The next and cost lines (L3-19)")
	local fresh = UI3.detail(nil, "longbow")
	check(
		fresh.nextLine == "T2: 68 → 111 dmg · HP +20 → +30",
		`the next tier's damage (Armory.Preview of the default style) and HP ({fresh.nextLine})`
	)
	check(
		fresh.costLine == "100 Timber · Forest Road",
		`the cost, its material and the level that drops it ({fresh.costLine})`
	)
	check(fresh.abilityLine == "Ability: Arrow Rain", "the ability")
	local styled = UI3.detail(
		{ held = { melee = "broadsword", ranged = "longbow", variants = { longbow = "B" } } },
		"longbow"
	)
	check(
		styled.nextLine == "T2: 63 → 104 dmg · HP +20 → +30",
		`the held style's damage ({styled.nextLine})`
	)
	local four = UI3.detail({ combat = UI3.combat({ tiers = { longbow = 4 } }) }, "longbow")
	check(
		four.nextLine == "T5: 303 → 500 dmg · HP +80 → +110",
		`the contract's example at T4 ({four.nextLine})`
	)
	check(
		four.costLine == nil,
		"an unbuilt band's cost is hidden (its placeholder material never shows)"
	)
	local three = UI3.detail({ combat = UI3.combat({ tiers = { longbow = 3 } }) }, "longbow")
	check(
		three.costLine == "500 Timber · Forest Road · needs ★ Hard",
		`a band's top names its trophy ({three.costLine})`
	)
	local starred = UI3.detail({
		combat = UI3.combat({
			tiers = { longbow = 3 },
			stars = { forestRoad = { hard = true } },
		}),
	}, "longbow")
	check(starred.costLine == "500 Timber · Forest Road", "and drops it once the star is held")
	local normalStar = UI3.detail({
		combat = UI3.combat({
			tiers = { longbow = 3 },
			stars = { forestRoad = { normal = true } },
		}),
	}, "longbow")
	check(
		normalStar.costLine == "500 Timber · Forest Road · needs ★ Hard",
		"only the ladder's starDifficulty star counts"
	)
	local peak = UI3.detail({ combat = UI3.combat({ tiers = { longbow = 12 } }) }, "longbow")
	check(
		peak.nextLine == "At its peak" and peak.costLine == nil,
		"at the top: At its peak, no cost"
	)
	local relic =
		UI3.detail({ combat = UI3.combat({ families = { splitbow = true } }) }, "splitbow")
	check(relic.nextLine == "At its peak", "a relic is at its peak")
	local hidden = UI3.detail(nil, "warhammer")
	check(
		hidden.nextLine == "Not found yet · First Hard clear of Forest Road"
			and hidden.costLine == nil,
		`an unowned family: the hint in place of both lines ({hidden.nextLine})`
	)
	check(UI3.detail(nil, "axe").nextLine == "Not found yet", "no hint known: Not found yet")
	local odd = UI3.detail({ combat = UI3.combat({ families = { oddity = true } }) }, "oddity")
	check(
		odd.nextLine == "Cannot be upgraded" and odd.costLine == nil,
		"an owned family with no window cannot be upgraded"
	)
	local flame =
		UI3.detail({ combat = UI3.combat({ families = { flamethrower = true } }) }, "flamethrower")
	check(
		flame.costLine == "250 Timber · Forest Road",
		`a window that starts mid-band pays from its start (T3 is position 3: {flame.costLine})`
	)
	check(
		UI3.detail(nil, "broken") == nil and UI3.detail(nil, "nothing") == nil,
		"no detail for a family the shelf cannot show"
	)
end
L1.group("l3ui lineTests", UI3.lineTests)

function UI3.upgradeTests(): ()
	print(" Upgrade: live only on UpgradeVerdict's nil, else its words (L3-21)")
	local function up(over: any?, family: string?): any
		return UI3.detail(over, family or "longbow").upgrade
	end
	local live = up({ combat = UI3.combat({ materials = { Timber = 100 } }) })
	check(
		live.visible and live.live and live.look == "action" and live.text == "Upgrade T2",
		`enough Timber, gate open: live, "Upgrade T2" ({live.text})`
	)
	check(
		UI3.detail({ combat = UI3.combat({ materials = { Timber = 100 } }) }, "longbow").nextTier
			== 2,
		"and the tier it buys is known for the toast"
	)
	local short = up({ combat = UI3.combat({ materials = { Timber = 40 } }) })
	check(
		short.visible
			and not short.live
			and short.look == "off"
			and short.text == "Need 60 more Timber",
		`short: "Need 60 more Timber" ({short.text})`
	)
	local busy = up({ gateOpen = false, combat = UI3.combat({ materials = { Timber = 100 } }) })
	check(not busy.live and busy.text == "Only in the lobby", "the gate shut: Only in the lobby")
	local star =
		up({ combat = UI3.combat({ materials = { Timber = 999 }, tiers = { longbow = 3 } }) })
	check(
		not star.live and star.text == "Needs ★ Hard on Forest Road",
		`a band top without the star ({star.text})`
	)
	local starred = up({
		combat = UI3.combat({
			materials = { Timber = 999 },
			tiers = { longbow = 3 },
			stars = { forestRoad = { hard = true } },
		}),
	})
	check(starred.live and starred.text == "Upgrade T4", "with the star it is live")
	local unbuilt = up({
		combat = UI3.combat({ materials = { Timber = 999, Iron = 999 }, tiers = { longbow = 4 } }),
	})
	check(
		not unbuilt.live and unbuilt.text == "Comes with Castle",
		`an unbuilt band: "Comes with <level>", from the map node ({unbuilt.text})`
	)
	local peak = up({ combat = UI3.combat({ tiers = { longbow = 12 } }) })
	check(peak.visible and not peak.live and peak.text == "At its peak", "at the top: At its peak")
	check(
		up({ gateOpen = false, combat = UI3.combat({ tiers = { longbow = 12 } }) }).text
			== "At its peak",
		"peak is said before busy"
	)
	check(up({
		gateOpen = false,
		combat = UI3.combat({ materials = { Timber = 999 }, tiers = { longbow = 3 } }),
	}).text == "Only in the lobby", "busy before the star")
	check(not up(nil, "warhammer").visible, "an unowned family: hidden")
	check(
		not up({ combat = UI3.combat({ families = { oddity = true } }) }, "oddity").visible,
		"no window: hidden"
	)
	local waiting = up({
		combat = UI3.combat({ materials = { Timber = 999 } }),
		pending = { upgrade = "longbow" },
	})
	check(
		not waiting.live and waiting.look == "pending" and waiting.text == "Upgrading...",
		"a press in flight: Upgrading..."
	)
	local other = up({
		combat = UI3.combat({ materials = { Timber = 999 } }),
		pending = { upgrade = "broadsword" },
	})
	check(
		not other.live and other.look == "action" and other.text == "Upgrade T2",
		"another family's upgrade waits for that answer"
	)
	local early = up({ noCombat = true })
	check(
		early.visible and not early.live and early.text == "Upgrade",
		"before the first Snapshot: shown, not live"
	)
	check(not up({ armory = { version = 1 } }).visible, "no ladder: hidden")
end
L1.group("l3ui upgradeTests", UI3.upgradeTests)

function UI3.equipTests(): ()
	print(" Equip and the styles: live only on FamilyVerdict's nil (L3-21)")
	local owned = UI3.combat({ families = { warhammer = true, splitbow = true } })
	local held = UI3.detail({ combat = owned }, "broadsword")
	check(
		held.equip.visible
			and not held.equip.live
			and held.equip.look == "held"
			and held.equip.text == "Equipped",
		"the held family: Equipped"
	)
	check(#held.styles == 0, "a family of one style has no style buttons")
	local hammer = UI3.detail({ combat = owned }, "warhammer")
	check(
		hammer.equip.live and hammer.equip.text == "Equip" and hammer.equipVariant == "A",
		"another owned family: Equip, with its default style"
	)
	check(
		not UI3.detail({ combat = owned, gateOpen = false }, "warhammer").equip.live
			and UI3.detail({ combat = owned, gateOpen = false }, "warhammer").equip.text
				== "Only in the lobby",
		"the gate shut: Only in the lobby"
	)
	local pending = UI3.detail(
		{ combat = owned, pending = { equipFamily = "warhammer", equipVariant = "A" } },
		"warhammer"
	).equip
	check(
		not pending.live and pending.look == "pending" and pending.text == "Equipping...",
		"a press in flight: Equipping..."
	)
	check(
		not UI3.detail(
			{ combat = owned, pending = { equipFamily = "splitbow", equipVariant = "A" } },
			"warhammer"
		).equip.live,
		"one equip in flight at a time"
	)
	check(
		not UI3.detail(nil, "warhammer").equip.visible and #UI3.detail(nil, "splitbow").styles == 0,
		"an unowned family: no buttons at all"
	)
	check(
		not UI3.detail({ noCombat = true }, "longbow").equip.live,
		"before the first Snapshot nothing is live (FamilyVerdict: unavailable)"
	)

	local bow = UI3.detail({ combat = owned }, "longbow")
	check(
		#bow.styles == 2 and bow.styles[1].variant == "A" and bow.styles[2].variant == "B",
		"a two-style family: one button per style, by key"
	)
	check(
		bow.styles[1].look == "held"
			and not bow.styles[1].live
			and bow.styles[1].text == "A: Pierce + blast",
		`the held family: the held style named and held ({bow.styles[1].text})`
	)
	check(
		bow.styles[2].live
			and bow.styles[2].look == "action"
			and bow.styles[2].text == "B: Quick shot",
		"the other one switches to it"
	)
	local switched = UI3.detail({
		combat = owned,
		held = { melee = "broadsword", ranged = "longbow", variants = { longbow = "B" } },
	}, "longbow")
	check(
		switched.styles[2].look == "held"
			and switched.styles[1].live
			and switched.equipVariant == "B",
		"the held loadout's style is the held one"
	)
	local unknown = UI3.detail({
		combat = owned,
		held = { melee = "broadsword", ranged = "longbow", variants = { longbow = "Z" } },
	}, "longbow")
	check(
		unknown.styles[1].look == "held" and unknown.equipVariant == "A",
		"an unknown saved style reads as the default"
	)
	local split = UI3.detail({ combat = owned }, "splitbow")
	check(
		split.styles[1].text == "Equip A"
			and split.styles[2].text == "Equip B"
			and split.styles[1].live
			and split.styles[2].live,
		"another family's styles read Equip A / Equip B"
	)
	local saved = UI3.detail({
		combat = owned,
		held = { melee = "broadsword", ranged = "longbow", variants = { splitbow = "B" } },
	}, "splitbow")
	check(
		saved.equipVariant == "B" and saved.equip.live,
		"Equip sends the style saved for that family"
	)
	local inFlight = UI3.detail(
		{ combat = owned, pending = { equipFamily = "longbow", equipVariant = "B" } },
		"longbow"
	)
	check(
		inFlight.styles[2].look == "pending"
			and inFlight.styles[2].text == "Equipping..."
			and not inFlight.styles[2].live,
		"a style press in flight: Equipping... on that button"
	)
	check(
		not UI3.detail({ combat = owned, gateOpen = false }, "splitbow").styles[1].live,
		"the gate shut: no style is live"
	)
	local picked = UI3.detail(
		{ combat = owned, held = { melee = "warhammer", ranged = "longbow", variants = {} } },
		"warhammer"
	)
	check(
		picked.card.held and picked.equip.text == "Equipped",
		"the host's loadout decides what is held"
	)
end
L1.group("l3ui equipTests", UI3.equipTests)

function UI3.textTests(): ()
	print(" Toasts and the wallet (L3-21, L3-19)")
	local M = UI3.Model
	local base = UI3.inputs({ combat = UI3.combat({ materials = { Timber = 40 } }) })
	check(
		M.RefusalText(base, "upgradeWeapon", "longbow", "insufficientFunds")
			== "Need 60 more Timber",
		"a refusal toasts the button's own words"
	)
	check(
		M.RefusalText(base, "upgradeWeapon", "longbow", "busy") == "Only in the lobby"
			and M.RefusalText(base, "setFamily", "warhammer", "busy") == "Only in the lobby",
		"busy, for both actions"
	)
	local top = UI3.inputs({ combat = UI3.combat({ tiers = { longbow = 3 } }) })
	check(
		M.RefusalText(top, "upgradeWeapon", "longbow", "needsStar")
			== "Needs ★ Hard on Forest Road",
		"needsStar names the level"
	)
	check(
		M.RefusalText(
			UI3.inputs({ combat = UI3.combat({ tiers = { longbow = 4 } }) }),
			"upgradeWeapon",
			"longbow",
			"notBuilt"
		) == "Comes with Castle",
		"notBuilt names the coming level"
	)
	check(M.RefusalText(base, "upgradeWeapon", "longbow", "peak") == "At its peak", "peak")
	local rich = UI3.inputs({ combat = UI3.combat({ materials = { Timber = 999 } }) })
	check(
		M.RefusalText(rich, "upgradeWeapon", "longbow", "insufficientFunds") == "Not enough Timber",
		"a refusal the state no longer explains still says what is short"
	)
	for _, reason in { "locked", "invalid", "unavailable", "owned" } do
		check(
			M.RefusalText(base, "upgradeWeapon", "longbow", reason) == "Try again",
			`anything else: Try again ({reason})`
		)
	end
	check(
		M.RefusalText(base, "setFamily", "warhammer", "locked") == "Try again"
			and M.RefusalText(base, "upgradeWeapon", "longbow", nil) == "Try again",
		"and no reason at all"
	)
	check(
		M.OkText(base, "upgradeWeapon", "longbow", 2) == "Longbow: T2",
		"an upgrade's toast names the tier"
	)
	check(
		M.OkText(base, "upgradeWeapon", "longbow", nil) == "Longbow upgraded",
		"or not, when the screen did not know it"
	)
	check(
		M.OkText(base, "setFamily", "warhammer", nil) == "Warhammer equipped"
			and M.OkText(base, "setFamily", "nothing", nil) == "Weapon equipped",
		"an equip's toast"
	)
	local wallet = M.Wallet(
		UI3.inputs({ combat = UI3.combat({ materials = { Timber = 1234, Iron = 50 }, valor = 25 }) })
	)
	check(
		wallet == "1.2K Timber · 25 Valor",
		`the wallet: every built band's material, then Valor, through Format ({wallet})`
	)
	check(M.Wallet(UI3.inputs({ noCombat = true })) == "", "nothing before the first Snapshot")
	check(
		M.Wallet(UI3.inputs({ armory = { version = 1 }, combat = UI3.combat({ valor = 3 }) }))
			== "3 Valor",
		"no ladder: Valor alone"
	)
	check(
		M.LevelName(UI3.inputs(), "castle") == "Castle"
			and M.LevelName(UI3.inputs(), "planet") == "planet",
		"a level's name: its file's, its node's, else its id"
	)
	check(
		M.DifficultyName(nil, "brutal") == "Brutal",
		"a difficulty with no name configured is capitalised"
	)
end
L1.group("l3ui textTests", UI3.textTests)

-- The files as they ship: Armory.json, ProvingGrounds.json, Expeditions.json and the level files.
function UI3.realTests(): ()
	print(" The shipped files on a fresh profile")
	local M = UI3.Model
	local levels: any = {}
	local built: any = {}
	for _, file in FIXTURES.levels do
		levels[file.id] = file
		built[file.id] = true
	end
	local inputs = {
		armory = ARMORY,
		weapons = FIXTURES.proving.weapons,
		loadout = FIXTURES.proving.loadout,
		expeditions = FIXTURES.expeditions,
		levels = levels,
		built = built,
		combat = UI3.combat(),
		gateOpen = true,
		pending = {},
	}
	local cards = M.Shelf(inputs)
	local families = 0
	for _ in FIXTURES.proving.weapons do
		families += 1
	end
	check(#cards == families, `one card per family ({#cards} of {families})`)
	check(
		cards[1] and cards[1].family == "broadsword" and cards[2] and cards[2].family == "longbow",
		"the shelf starts with the two starters"
	)
	local rising, hinted = true, true
	for index, card in cards do
		local before = cards[index - 1]
		if before ~= nil and (before.start or math.huge) > (card.start or math.huge) then
			rising = false
		end
		if not card.owned and card.hint == nil then
			hinted = false
			print("   no hint: " .. card.family)
		end
	end
	check(rising, "window starts never fall along the shelf: it reads as the path of levels")
	check(hinted, "every family not owned on a fresh profile has a shelf hint (L3-25)")
	local by: any = {}
	for _, card in cards do
		by[card.family] = card
	end
	check(
		by.flamethrower and by.flamethrower.hint == "Hidden on Forest Road",
		"the Flamethrower is hidden on Forest Road (its secret)"
	)
	check(
		by.warhammer and by.warhammer.hint == "First Hard clear of Forest Road",
		"the Warhammer: First Hard clear of Forest Road"
	)
	local bow = M.Detail(inputs, "longbow")
	check(
		bow ~= nil and bow.nextLine == "T2: 68 → 111 dmg · HP +20 → +30",
		`Longbow's next line on the shipped ladder ({bow and bow.nextLine})`
	)
	check(
		bow ~= nil and bow.costLine == "100 Timber · Forest Road",
		`and its cost ({bow and bow.costLine})`
	)
	check(
		bow ~= nil and not bow.upgrade.live and bow.upgrade.text == "Need 100 more Timber",
		"a fresh profile cannot pay T2"
	)
	local relic = M.Detail(inputs, "spinblade")
	check(
		relic ~= nil and relic.nextLine == "Not found yet · Hidden in the Dream",
		`the relic, unowned ({relic and relic.nextLine})`
	)
	check(
		M.Wallet(inputs) == "0 Timber · 0 Valor",
		"the wallet shows Forest Road's Timber only (the later bands are not built)"
	)
end
L1.group("l3ui realTests", UI3.realTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
