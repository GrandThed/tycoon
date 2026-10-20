--!strict
-- The Armory screen's reading of the state (docs/prompts/l3-w1-contract.md, L3-18 to L3-21):
-- the shelf's cards, the track's pips, the next-tier and cost lines and every button's state,
-- from the Armory config, the weapons, the Expeditions config, the level files, the combat
-- profile, the held loadout, the gate and the set of built levels.
--
-- Pure: no Instance, no service, no clock, so tools/crowd_harness/tests_l3_ui.luau runs the very
-- functions the screen paints from. It colours and never decides: a button is live only when
-- the shared rule the server runs (Armory.UpgradeVerdict, Unlocks.FamilyVerdict) says nil, and
-- the server's ActionResult and the next Snapshot are the truth. A colour comes back as the
-- config's { r, g, b } (Color3 is the view's), every number through Format.
--
-- The ladder's bands are JSON and read with care here (a band's level, the trophy's difficulty);
-- everything else about a tier is Armory's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Types = require(sharedFolder:WaitForChild("Types"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

-- What the screen holds, handed in whole on every paint.
export type Inputs = {
	armory: Types.ArmoryConfig?,
	weapons: { [string]: Types.RangeWeaponDef },
	-- ProvingGrounds.json `loadout`: the starters, and the held pair before the host says one.
	loadout: { melee: string, ranged: string }?,
	expeditions: Types.ExpeditionsConfig?,
	-- The level files by id, and the ids that have one (Catalog.GetLevelIds).
	levels: { [string]: Types.LevelFile },
	built: { [string]: boolean },
	-- nil until the first Snapshot.
	combat: Types.CombatProfile?,
	-- nil until the host says it: then the saved loadout's reading (Unlocks.LoadoutOf).
	held: Types.RangeLoadout?,
	gateOpen: boolean,
	pending: Pending,
}

-- The presses waiting for their answer: one upgrade and one equip at most.
export type Pending = {
	upgrade: string?,
	equipFamily: string?,
	equipVariant: string?,
}

export type Variant = { key: string, label: string }

export type Card = {
	family: string,
	name: string,
	slot: string,
	slotWord: string,
	element: Types.Element?,
	owned: boolean,
	held: boolean,
	-- The window; nil = none (it fights at T1 and cannot be upgraded).
	start: number?,
	top: number?,
	tier: number,
	tierText: string,
	-- An unowned family's shelf hint (where it is found); nil when owned or none is known.
	hint: string?,
	variants: { Variant },
	default: string,
	ability: string?,
}

-- "lit" = in the window at or below the tier; "open" = in the window above it (an unowned
-- family's whole window); "dim" = outside the window.
export type PipState = "lit" | "open" | "dim"

export type Pip = {
	tier: number,
	band: number,
	state: PipState,
	start: boolean,
	top: boolean,
	-- The tier the family stands at (owned only).
	current: boolean,
	-- The number under a start or top pip ("1", "12"); nil elsewhere.
	mark: string?,
	-- The band's level's theme colour, { r, g, b }; nil = none known.
	color: { number }?,
}

-- "action" = live; "held" = what is in hand; "pending" = waiting for its answer; "off" = a
-- refusal shown in its words.
export type Look = "action" | "held" | "pending" | "off"

export type ButtonState = { visible: boolean, live: boolean, text: string, look: Look }

export type StyleButton = {
	variant: string,
	visible: boolean,
	live: boolean,
	text: string,
	look: Look,
}

export type Detail = {
	card: Card,
	pips: { Pip },
	nextLine: string,
	-- nil = no cost line (owned at its peak, an unbuilt band, unowned).
	costLine: string?,
	abilityLine: string?,
	styles: { StyleButton },
	equip: ButtonState,
	upgrade: ButtonState,
	-- What Equip sends: the held style, else the saved one, else the default.
	equipVariant: string,
	-- The tier a live Upgrade buys (the ok toast names it); nil when there is none.
	nextTier: number?,
}

local SLOT_ORDER: { [string]: number } = { melee = 1, ranged = 2 }
local SLOT_WORDS: { [string]: string } = { melee = "Melee", ranged = "Ranged" }
local NO_WINDOW = math.huge

local TEXT = {
	peak = "At its peak",
	busy = "Only in the lobby",
	retry = "Try again",
	upgrade = "Upgrade",
	upgrading = "Upgrading...",
	equip = "Equip",
	equipped = "Equipped",
	equipping = "Equipping...",
	notFound = "Not found yet",
	noUpgrades = "Cannot be upgraded",
	hiddenOn = "Hidden on ",
	comesWith = "Comes with ",
	ability = "Ability: ",
	upgraded = " upgraded",
	equippedToast = " equipped",
	valor = "Valor",
	separator = " · ",
	arrow = " → ",
	star = "★ ",
	-- A band's top when the ladder names no difficulty to show (the validator warns about it).
	needsAStar = "Needs a star on ",
	noStar = "★ ?",
	noLevel = "none",
}

local ArmoryModel = {}

ArmoryModel.TEXT = TEXT

local function readTable(value: any): any
	return if type(value) == "table" then value else nil
end

-- Armory.json's `ladder`; nil without one.
local function ladderOf(armory: Types.ArmoryConfig?): Types.ArmoryLadder?
	local ladder = if armory ~= nil then armory.ladder else nil
	return if type(ladder) == "table" then ladder else nil
end

-- A band's level id (`ladder.bands[band].levelId`); nil when the band names none.
local function bandLevel(armory: Types.ArmoryConfig?, band: number): string?
	local ladder = ladderOf(armory)
	local bands = if ladder ~= nil and type(ladder.bands) == "table" then ladder.bands else nil
	local entry = if bands ~= nil then bands[band] else nil
	local id = if type(entry) == "table" then entry.levelId else nil
	return if type(id) == "string" and id ~= "" then id else nil
end

local function bandSize(armory: Types.ArmoryConfig?): number
	local ladder = ladderOf(armory)
	local size = if ladder ~= nil then ladder.bandSize else nil
	return if type(size) == "number" and size >= 1 then size else 0
end

-- The difficulty whose star the screen names at a band's top (`ladder.starDifficulty`, the one
-- the U lever grants). nil when the ladder names none: then no line names a star, and only the
-- verdict (the server's rule) says one is missing.
local function starDifficulty(armory: Types.ArmoryConfig?): string?
	local ladder = ladderOf(armory)
	local key = if ladder ~= nil then ladder.starDifficulty else nil
	return if type(key) == "string" and key ~= "" then key else nil
end

-- The map node for a level id: the node that plays it, else the node of that id.
local function nodeOf(expeditions: Types.ExpeditionsConfig?, levelId: string): Types.MapNode?
	local nodes = if expeditions ~= nil then readTable(expeditions.nodes) else nil
	if nodes == nil then
		return nil
	end
	local named: Types.MapNode? = nil
	for _, node in nodes do
		if type(node) ~= "table" then
			continue
		end
		if node.level == levelId then
			return node
		end
		if node.id == levelId and named == nil then
			named = node
		end
	end
	return named
end

-- A level's name: its file's, else its map node's, else its id.
function ArmoryModel.LevelName(inputs: Inputs, levelId: string): string
	local file = inputs.levels[levelId]
	if file ~= nil and type(file.name) == "string" and file.name ~= "" then
		return file.name
	end
	local node = nodeOf(inputs.expeditions, levelId)
	if node ~= nil and type(node.name) == "string" and node.name ~= "" then
		return node.name
	end
	return levelId
end

-- A difficulty's name as the map shows it ("Hard").
function ArmoryModel.DifficultyName(expeditions: Types.ExpeditionsConfig?, key: string): string
	local names = if expeditions ~= nil then readTable(expeditions.difficultyNames) else nil
	local name = if names ~= nil then names[key] else nil
	if type(name) == "string" and name ~= "" then
		return name
	end
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

-- The star a band's top names, "★ Hard"; nil when the ladder names no difficulty.
local function starWords(inputs: Inputs): string?
	local key = starDifficulty(inputs.armory)
	return if key ~= nil
		then TEXT.star .. ArmoryModel.DifficultyName(inputs.expeditions, key)
		else nil
end

-- A band's colour: its level's map node's theme ({ r, g, b }); nil when none is known.
local function bandColor(inputs: Inputs, band: number): { number }?
	local levelId = bandLevel(inputs.armory, band)
	local expeditions = inputs.expeditions
	if levelId == nil or expeditions == nil then
		return nil
	end
	local node = nodeOf(expeditions, levelId)
	local themes = readTable(expeditions.themes)
	local theme = if node ~= nil and themes ~= nil then readTable(themes[node.theme]) else nil
	local color = if theme ~= nil then readTable(theme.color) else nil
	if color == nil or type(color[1]) ~= "number" then
		return nil
	end
	return color
end

-- Where each unowned family is found, as its card says it: every family a level's secret pays,
-- "Hidden on <level>" (the first level in id order that pays it), then every family
-- Expeditions.json `found` names that no secret pays, the entry's own text (L3-25).
function ArmoryModel.Hints(inputs: Inputs): { [string]: string }
	local where: { [string]: string } = {}
	local ids: { string } = {}
	for id in inputs.levels do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local file = inputs.levels[id]
		local secrets = if file ~= nil then readTable(file.secrets) else nil
		if secrets == nil then
			continue
		end
		local secretIds: { string } = {}
		for secretId in secrets do
			table.insert(secretIds, secretId)
		end
		table.sort(secretIds)
		for _, secretId in secretIds do
			local secret = readTable(secrets[secretId])
			local family = if secret ~= nil then secret.family else nil
			if type(family) == "string" and family ~= "" and where[family] == nil then
				where[family] = TEXT.hiddenOn .. ArmoryModel.LevelName(inputs, id)
			end
		end
	end
	local expeditions = inputs.expeditions
	local found = if expeditions ~= nil then readTable(expeditions.found) else nil
	if found ~= nil then
		for family, entry in found do
			if
				type(family) == "string"
				and where[family] == nil
				and type(entry) == "table"
				and type(entry.text) == "string"
				and entry.text ~= ""
			then
				where[family] = entry.text
			end
		end
	end
	return where
end

-- The held pair: the host's word, else the saved loadout's reading, else the starters.
function ArmoryModel.Held(inputs: Inputs): Types.RangeLoadout
	local held = inputs.held
	if held ~= nil then
		return held
	end
	local fallback = inputs.loadout or { melee = "", ranged = "" }
	return Unlocks.LoadoutOf(inputs.combat, inputs.weapons, fallback)
end

local function starters(inputs: Inputs): { [string]: boolean }
	return Unlocks.Starters(inputs.loadout)
end

local function familiesOf(inputs: Inputs): { [string]: boolean }?
	local combat = inputs.combat
	return if combat ~= nil then combat.families else nil
end

local function heldFamily(held: Types.RangeLoadout, slot: string): string
	return if slot == "melee" then held.melee else held.ranged
end

-- The family's window, or nil, nil.
local function windowOf(inputs: Inputs, family: string): (number?, number?)
	local armory = inputs.armory
	if armory == nil then
		return nil, nil
	end
	local start, top = Armory.Window(armory, family)
	if type(start) ~= "number" or type(top) ~= "number" then
		return nil, nil
	end
	return start, top
end

-- Before the first Snapshot every family stands at its start (Armory.TierOf with no profile).
local function tierOf(inputs: Inputs, family: string): number
	local armory = inputs.armory
	return if armory ~= nil then Armory.TierOf(armory, inputs.combat, family) else 1
end

function ArmoryModel.TierText(tier: number): string
	return "T" .. Format.Cash(tier)
end

local function variantsOf(def: Types.RangeWeaponDef): { Variant }
	local variants: { Variant } = {}
	for key, variant in def.variants do
		if type(key) ~= "string" or type(variant) ~= "table" then
			continue
		end
		local label = variant.label
		table.insert(variants, {
			key = key,
			label = if type(label) == "string" and label ~= "" then label else key,
		})
	end
	table.sort(variants, function(a: Variant, b: Variant): boolean
		return a.key < b.key
	end)
	return variants
end

-- One family's card; nil for a def the screen cannot show (no variants, a slot that is neither).
local function cardOf(
	inputs: Inputs,
	family: string,
	held: Types.RangeLoadout,
	owners: { [string]: boolean },
	hints: { [string]: string }
): Card?
	local def = inputs.weapons[family]
	if type(def) ~= "table" or type(def.variants) ~= "table" then
		return nil
	end
	local slot = def.slot
	if SLOT_ORDER[slot] == nil then
		return nil
	end
	local variants = variantsOf(def)
	if #variants == 0 then
		return nil
	end
	local start, top = windowOf(inputs, family)
	local owned = Unlocks.OwnsFamily(familiesOf(inputs), family, owners)
	local tier = tierOf(inputs, family)
	local ability = def.ability
	local abilityName = if type(ability) == "table" then ability.name else nil
	return {
		family = family,
		name = if type(def.name) == "string" and def.name ~= "" then def.name else family,
		slot = slot,
		slotWord = SLOT_WORDS[slot],
		element = Unlocks.ElementOf(inputs.weapons, family),
		owned = owned,
		held = owned and heldFamily(held, slot) == family,
		start = start,
		top = top,
		tier = tier,
		tierText = ArmoryModel.TierText(tier),
		hint = if owned then nil else hints[family],
		variants = variants,
		default = if def.variants[def.default] ~= nil then def.default else variants[1].key,
		ability = if type(abilityName) == "string" and abilityName ~= "" then abilityName else nil,
	}
end

-- Every family the screen can show, in shelf order (L3-19): by window start (a family with no
-- window last), then melee before ranged, then name. The shelf reads as the path of levels.
function ArmoryModel.Shelf(inputs: Inputs): { Card }
	local held = ArmoryModel.Held(inputs)
	local owners = starters(inputs)
	local hints = ArmoryModel.Hints(inputs)
	local cards: { Card } = {}
	for family in inputs.weapons do
		if type(family) ~= "string" then
			continue
		end
		local card = cardOf(inputs, family, held, owners, hints)
		if card ~= nil then
			table.insert(cards, card)
		end
	end
	table.sort(cards, function(a: Card, b: Card): boolean
		local aStart = a.start or NO_WINDOW
		local bStart = b.start or NO_WINDOW
		if aStart ~= bStart then
			return aStart < bStart
		end
		if a.slot ~= b.slot then
			return SLOT_ORDER[a.slot] < SLOT_ORDER[b.slot]
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.family < b.family
	end)
	return cards
end

-- The track (L3-20): every tier of the ladder, in its band's colour.
function ArmoryModel.Pips(inputs: Inputs, card: Card): { Pip }
	local pips: { Pip } = {}
	local armory = inputs.armory
	if armory == nil then
		return pips
	end
	local start, top = card.start, card.top
	for tier = 1, Armory.LadderSize(armory) do
		local band = Armory.BandOf(armory, tier)
		local inside = start ~= nil and top ~= nil and tier >= start and tier <= top
		local state: PipState = "dim"
		if inside then
			state = if card.owned and tier <= card.tier then "lit" else "open"
		end
		table.insert(pips, {
			tier = tier,
			band = band,
			state = state,
			start = tier == start,
			top = tier == top,
			current = card.owned and inside and tier == card.tier,
			mark = if tier == start or tier == top then Format.Cash(tier) else nil,
			color = bandColor(inputs, band),
		})
	end
	return pips
end

-- R1 of the fix round: the server's own reading of a band top's star (starDifficulty, or a
-- harder one in `starAlso`), so the cost line never disagrees with UpgradeVerdict.
local function hasStar(inputs: Inputs, levelId: string): boolean
	local armory = inputs.armory
	local combat = inputs.combat
	return armory ~= nil and combat ~= nil and Armory.StarHeld(armory, combat, levelId)
end

-- The next tier's band level, its material and price, and whether it is a band's top.
local function nextFacts(inputs: Inputs, tier: number): (string?, string, number, boolean)
	local armory = inputs.armory
	if armory == nil then
		return nil, "", 0, false
	end
	local band, position = Armory.BandOf(armory, tier)
	local material, amount = Armory.TierCost(armory, tier)
	local size = bandSize(armory)
	return bandLevel(armory, band), material, amount, size > 0 and position == size
end

-- The words of an upgrade refusal, on the button and in the toast (L3-21); nil = no words
-- (the button hides: not owned, no window, or the screen has nothing to read).
local function upgradeWords(inputs: Inputs, card: Card, reason: string): string?
	if reason == "peak" then
		return TEXT.peak
	elseif reason == "busy" then
		return TEXT.busy
	end
	local armory = inputs.armory
	local combat = inputs.combat
	if armory == nil or combat == nil then
		return nil
	end
	local nextTier = Armory.NextTier(armory, combat, card.family)
	if nextTier == nil then
		return nil
	end
	local levelId, material, amount = nextFacts(inputs, nextTier)
	local levelName = if levelId ~= nil
		then ArmoryModel.LevelName(inputs, levelId)
		else "a later level"
	if reason == "notBuilt" then
		return TEXT.comesWith .. levelName
	elseif reason == "needsStar" then
		local star = starWords(inputs)
		return if star ~= nil
			then "Needs " .. star .. " on " .. levelName
			else TEXT.needsAStar .. levelName
	elseif reason == "insufficientFunds" then
		local short = amount - (combat.materials[material] or 0)
		return if short > 0
			then "Need " .. Format.Cash(short) .. " more " .. material
			else "Not enough " .. material
	end
	return nil
end

-- The next line (L3-19): "T5: 303 → 500 dmg · HP +120 → +170", "At its peak", or for an
-- unowned family where it is found.
local function nextLine(inputs: Inputs, card: Card, styleKey: string): string
	if not card.owned then
		local hint = card.hint
		return if hint ~= nil then TEXT.notFound .. TEXT.separator .. hint else TEXT.notFound
	end
	local armory = inputs.armory
	local top = card.top
	if armory == nil or top == nil then
		return TEXT.noUpgrades
	end
	if card.tier >= top then
		return TEXT.peak
	end
	local nextTier = card.tier + 1
	local def = inputs.weapons[card.family]
	local variant = if def ~= nil then def.variants[styleKey] else nil
	local base = if variant ~= nil and type(variant.damage) == "number" then variant.damage else 0
	local damageNow, hpNow = Armory.Preview(armory, card.slot, card.tier, base)
	local damageNext, hpNext = Armory.Preview(armory, card.slot, nextTier, base)
	return ArmoryModel.TierText(nextTier)
		.. ": "
		.. Format.Cash(damageNow)
		.. TEXT.arrow
		.. Format.Cash(damageNext)
		.. " dmg"
		.. TEXT.separator
		.. "HP +"
		.. Format.Cash(hpNow)
		.. TEXT.arrow
		.. "+"
		.. Format.Cash(hpNext)
end

-- The cost line (L3-19): "500 Timber · Forest Road · needs ★ Hard"; nil at the peak, for an
-- unbuilt band (its placeholder material never shows) and for an unowned family.
local function costLine(inputs: Inputs, card: Card): string?
	local armory = inputs.armory
	local top = card.top
	if not card.owned or armory == nil or top == nil or card.tier >= top then
		return nil
	end
	local levelId, material, amount, bandTop = nextFacts(inputs, card.tier + 1)
	if levelId == nil or inputs.built[levelId] ~= true or material == "" then
		return nil
	end
	local line = Format.Cash(amount)
		.. " "
		.. material
		.. TEXT.separator
		.. ArmoryModel.LevelName(inputs, levelId)
	if bandTop and not hasStar(inputs, levelId) then
		local star = starWords(inputs)
		if star ~= nil then
			line ..= TEXT.separator .. "needs " .. star
		end
	end
	return line
end

local function hidden(): ButtonState
	return { visible = false, live = false, text = "", look = "off" }
end

local function upgradeButton(inputs: Inputs, card: Card): (ButtonState, number?)
	local armory = inputs.armory
	local combat = inputs.combat
	if not card.owned or armory == nil or card.top == nil then
		return hidden(), nil
	end
	if combat == nil then
		return { visible = true, live = false, text = TEXT.upgrade, look = "off" }, nil
	end
	local pending = inputs.pending.upgrade
	if pending == card.family then
		return { visible = true, live = false, text = TEXT.upgrading, look = "pending" }, nil
	end
	local verdict: string? = Armory.UpgradeVerdict(
		armory,
		combat,
		card.family,
		card.owned,
		inputs.gateOpen,
		inputs.built
	)
	if verdict == nil then
		local nextTier = Armory.NextTier(armory, combat, card.family)
		local text = if nextTier ~= nil
			then TEXT.upgrade .. " " .. ArmoryModel.TierText(nextTier)
			else TEXT.upgrade
		-- One upgrade in flight at a time: another family's waits for that answer.
		return { visible = true, live = pending == nil, text = text, look = "action" }, nextTier
	end
	local words = upgradeWords(inputs, card, verdict)
	if words == nil then
		return hidden(), nil
	end
	return { visible = true, live = false, text = words, look = "off" }, nil
end

local function equipVerdict(inputs: Inputs, card: Card, variant: string): string?
	local combat = inputs.combat
	-- FamilyVerdict reads only `state.combat`; nil = no profile yet ("unavailable").
	local state: any = if combat ~= nil then { combat = combat } else nil
	return Unlocks.FamilyVerdict(
		state,
		inputs.weapons,
		starters(inputs),
		card.slot,
		card.family,
		variant,
		inputs.gateOpen
	)
end

local function equipButton(inputs: Inputs, card: Card, variant: string): ButtonState
	if not card.owned then
		return hidden()
	end
	if card.held then
		return { visible = true, live = false, text = TEXT.equipped, look = "held" }
	end
	local pending = inputs.pending
	if pending.equipFamily == card.family then
		return { visible = true, live = false, text = TEXT.equipping, look = "pending" }
	end
	local verdict = equipVerdict(inputs, card, variant)
	if verdict == nil then
		return {
			visible = true,
			live = pending.equipFamily == nil,
			text = TEXT.equip,
			look = "action",
		}
	end
	return {
		visible = true,
		live = false,
		text = if verdict == "busy" then TEXT.busy else TEXT.equip,
		look = "off",
	}
end

-- The style buttons (L3-21): on the held family each names its style and the other one switches
-- to it; on another family they read "Equip A" / "Equip B". None for a family of one style.
local function styleButtons(inputs: Inputs, card: Card, heldKey: string?): { StyleButton }
	local buttons: { StyleButton } = {}
	if not card.owned or #card.variants < 2 then
		return buttons
	end
	local pending = inputs.pending
	for _, variant in card.variants do
		local text = if card.held
			then variant.key .. ": " .. variant.label
			else TEXT.equip .. " " .. variant.key
		local look: Look = "off"
		local live = false
		if card.held and heldKey == variant.key then
			look = "held"
		elseif pending.equipFamily == card.family and pending.equipVariant == variant.key then
			look = "pending"
			text = TEXT.equipping
		elseif equipVerdict(inputs, card, variant.key) == nil then
			look = "action"
			live = pending.equipFamily == nil
		end
		table.insert(buttons, {
			variant = variant.key,
			visible = true,
			live = live,
			text = text,
			look = look,
		})
	end
	return buttons
end

-- The selected family's whole right side (L3-19 to L3-21); nil when the screen cannot show it.
function ArmoryModel.Detail(inputs: Inputs, family: string): Detail?
	local held = ArmoryModel.Held(inputs)
	local card = cardOf(inputs, family, held, starters(inputs), ArmoryModel.Hints(inputs))
	if card == nil then
		return nil
	end
	local saved = held.variants[family]
	local savedKey = if type(saved) == "string"
			and inputs.weapons[family].variants[saved] ~= nil
		then saved
		else nil
	local heldKey = if card.held then savedKey or card.default else nil
	local equipVariant = savedKey or card.default
	local upgrade, nextTier = upgradeButton(inputs, card)
	local ability = card.ability
	return {
		card = card,
		pips = ArmoryModel.Pips(inputs, card),
		nextLine = nextLine(inputs, card, equipVariant),
		costLine = costLine(inputs, card),
		abilityLine = if ability ~= nil then TEXT.ability .. ability else nil,
		styles = styleButtons(inputs, card, heldKey),
		equip = equipButton(inputs, card, equipVariant),
		upgrade = upgrade,
		equipVariant = equipVariant,
		nextTier = nextTier,
	}
end

-- Where the screen opens the first time: the held melee family, else the first card.
function ArmoryModel.DefaultFamily(inputs: Inputs, cards: { Card }): string?
	local held = ArmoryModel.Held(inputs)
	for _, card in cards do
		if card.family == held.melee then
			return card.family
		end
	end
	local first = cards[1]
	return if first ~= nil then first.family else nil
end

local function familyName(inputs: Inputs, family: string): string
	local def = inputs.weapons[family]
	if def ~= nil and type(def.name) == "string" and def.name ~= "" then
		return def.name
	end
	return "Weapon"
end

-- The toast for a refused press (L3-21): the button's own words, anything else "Try again".
-- `action` is the ActionResult's ("upgradeWeapon" | "setFamily").
function ArmoryModel.RefusalText(
	inputs: Inputs,
	action: string,
	family: string,
	reason: string?
): string
	if type(reason) ~= "string" then
		return TEXT.retry
	end
	if reason == "busy" then
		return TEXT.busy
	end
	if action == "upgradeWeapon" then
		local held = ArmoryModel.Held(inputs)
		local card = cardOf(inputs, family, held, starters(inputs), {})
		local words = if card ~= nil then upgradeWords(inputs, card, reason) else nil
		if words ~= nil then
			return words
		end
	end
	return TEXT.retry
end

-- The toast for an accepted press: "Longbow: T2", "Warhammer equipped", and for a style switched
-- on the held family what changed, "Longbow: B · Quick shot". `tier` is the tier the press
-- bought, when the screen knows it; `style` the key a switch on the held family sent (nil for an
-- equip of another family, which is what changed there).
function ArmoryModel.OkText(
	inputs: Inputs,
	action: string,
	family: string,
	tier: number?,
	style: string?
): string
	local name = familyName(inputs, family)
	if action == "upgradeWeapon" then
		return if tier ~= nil
			then name .. ": " .. ArmoryModel.TierText(tier)
			else name .. TEXT.upgraded
	end
	if style ~= nil then
		local def = inputs.weapons[family]
		local variant = if def ~= nil and type(def.variants) == "table"
			then def.variants[style]
			else nil
		local label = if type(variant) == "table" then variant.label else nil
		return name
			.. ": "
			.. style
			.. (if type(label) == "string" and label ~= "" then TEXT.separator .. label else "")
	end
	return name .. TEXT.equippedToast
end

-- The Studio star lever's caption (L3-28, Unlocks.ALL_STARS): the star it grants and every level
-- it grants it on, "★ Hard: Forest Road", from the ladder's built bands, so a band whose level
-- gets built renames the button with no edit (3-s2). "★ Hard: none" while no band level is built.
function ArmoryModel.StarLeverText(inputs: Inputs): string
	local armory = inputs.armory
	local names: { string } = {}
	if armory ~= nil then
		local built = inputs.built
		local levelIds = Armory.BuiltBands(armory, built)
		for _, levelId in levelIds do
			table.insert(names, ArmoryModel.LevelName(inputs, levelId))
		end
	end
	return (starWords(inputs) or TEXT.noStar)
		.. ": "
		.. (if #names > 0 then table.concat(names, ", ") else TEXT.noLevel)
end

-- The header's wallet (L3-19): the material of every band whose level is built, in band order
-- (Armory.BuiltBands, the grant lever's own list), then Valor ("1.2K Timber · 25 Valor"); ""
-- before the first Snapshot.
function ArmoryModel.Wallet(inputs: Inputs): string
	local combat = inputs.combat
	if combat == nil then
		return ""
	end
	local parts: { string } = {}
	local armory = inputs.armory
	if armory ~= nil then
		local _, materials = Armory.BuiltBands(armory, inputs.built)
		for _, material in materials do
			table.insert(parts, Format.Cash(combat.materials[material] or 0) .. " " .. material)
		end
	end
	table.insert(parts, Format.Cash(combat.valor) .. " " .. TEXT.valor)
	return table.concat(parts, TEXT.separator)
end

return ArmoryModel
