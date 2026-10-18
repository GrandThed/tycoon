--!strict
-- L2 W1 (docs/prompts/l2-w1-contract.md, L2-2 and L2-9): what a player has unlocked in the
-- dungeon place, and the rules that read it. Pure: no Instance, no service, no clock, so
-- tools/crowd_harness tests the very functions the server runs. The server (UnlockService)
-- writes the profile and the Player attributes; the clients only read the attribute.
--
-- Keys are checked where a reward is given, from the profile (L2-23): a client that double-jumps
-- without owning it moves further, and gains nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- Structural, like a weapon family's `slot`: the ability the air jump keys on.
local AIR_JUMP = "doubleJump"
-- Infrastructure, like ArenaService's PLACED_ATTRIBUTE: the Player attribute that carries an
-- ability to every client (a Player attribute survives respawn).
local ATTRIBUTE_PREFIX = "Ability_"
-- Structural caps, in bytes (Luau's `#`), with one home here: CombatRemotes' validators,
-- StageFlow.Validate, the Abilities panel and the Python mirrors all read these. An ability id the
-- buy remote carries (L2-7) ...
local MAX_ID_LENGTH = 32
-- ... and a weapon family id (P2's equip and loadout intents, a secret's `family`, L2-13).
local MAX_FAMILY_LENGTH = 24
-- ... and a variant key ("A", "B"), L2-32's third argument.
local MAX_VARIANT_LENGTH = 8
-- L2-29, L2-31: the words a family's `element` (and a secret's key) may say. Anything else is no
-- element: a key that names it is never held.
local ELEMENTS: { [string]: Types.Element } = {}
ELEMENTS.fire = "fire"
ELEMENTS.ice = "ice"
table.freeze(ELEMENTS)

local Unlocks = {}

Unlocks.AIR_JUMP = AIR_JUMP
Unlocks.MAX_ID_LENGTH = MAX_ID_LENGTH
Unlocks.MAX_FAMILY_LENGTH = MAX_FAMILY_LENGTH
Unlocks.MAX_VARIANT_LENGTH = MAX_VARIANT_LENGTH

function Unlocks.Attribute(abilityId: string): string
	return ATTRIBUTE_PREFIX .. abilityId
end

function Unlocks.Owns(abilities: { [string]: boolean }?, id: string): boolean
	return abilities ~= nil and abilities[id] == true
end

-- Why an Expeditions.json `abilities.list` entry cannot be sold; nil = it can. A price that is
-- not a whole number above 0 (NaN, infinite, fractional) would let a purchase write a Valor the
-- profile cannot hold.
function Unlocks.DefProblem(def: any): string?
	if type(def) ~= "table" then
		return "is not a table"
	end
	if type(def.id) ~= "string" or def.id == "" then
		return "has no id"
	end
	-- The buy remote drops a longer id unanswered, so such an entry could never be bought.
	if #def.id > MAX_ID_LENGTH then
		return `has an id longer than {MAX_ID_LENGTH} bytes`
	end
	if type(def.name) ~= "string" or def.name == "" then
		return "has no name"
	end
	if type(def.text) ~= "string" or def.text == "" then
		return "has no text"
	end
	if type(def.order) ~= "number" or def.order ~= def.order then
		return "has no order"
	end
	local price = def.price
	local valor = if type(price) == "table" then price.valor else nil
	if type(valor) ~= "number" or not (valor > 0 and valor < math.huge) or valor % 1 ~= 0 then
		return "has no price.valor that is a whole number above 0"
	end
	return nil
end

-- `abilities.list`, or nil when the config has none that is a table.
local function listOf(config: Types.ExpeditionsConfig?): { any }?
	local abilities: any = if config ~= nil then config.abilities else nil
	local list = if type(abilities) == "table" then abilities.list else nil
	return if type(list) == "table" then list else nil
end

-- The one rule for a repeated id (the fix round's s4): the first entry of that id that can be
-- sold. A malformed entry is skipped, so a broken first `doubleJump` does not hide a sound one
-- after it; Sellable (UnlockService.Init, the Abilities panel) and Find read the same entry. Also
-- its position, so a list that holds one table twice still sells it once.
local function firstSellable(list: { any }, id: string): (Types.UnlockAbilityDef?, any)
	for index, def in list do
		if type(def) == "table" and def.id == id and Unlocks.DefProblem(def) == nil then
			return def, index
		end
	end
	return nil, nil
end

-- The sellable entry with this id; nil when there is none that can be sold.
function Unlocks.Find(config: Types.ExpeditionsConfig?, id: string): Types.UnlockAbilityDef?
	local list = listOf(config)
	if list == nil then
		return nil
	end
	local def = firstSellable(list, id)
	return def
end

-- Every entry Find can return, in the list's order, and one line per entry that is left out (a
-- malformed one, or a later repeat of an id already sold) for the caller to warn. No
-- `abilities` block sells nothing and says nothing; a block whose `list` is not a list says so.
function Unlocks.Sellable(
	config: Types.ExpeditionsConfig?
): ({ Types.UnlockAbilityDef }, { string })
	local defs: { Types.UnlockAbilityDef } = {}
	local problems: { string } = {}
	local abilities: any = if config ~= nil then config.abilities else nil
	if abilities == nil then
		return defs, problems
	end
	local list = listOf(config)
	if list == nil then
		table.insert(problems, "abilities.list is not a list: nothing is sold")
		return defs, problems
	end
	for index, def in list do
		local problem = Unlocks.DefProblem(def)
		if problem == nil then
			local _, first = firstSellable(list, def.id)
			if first ~= index then
				problem = `repeats the id "{def.id}"`
			end
		end
		if problem ~= nil then
			table.insert(problems, `abilities.list entry {index} {problem}: it cannot be bought`)
		else
			table.insert(defs, def)
		end
	end
	return defs, problems
end

-- The profile's `combat.abilities`, made when a profile lacks it (v6 code may have saved one
-- without it; the v7 step is the usual source).
function Unlocks.AbilitiesOf(combat: Types.CombatProfile): { [string]: boolean }
	local existing = combat.abilities
	if existing ~= nil then
		return existing
	end
	local made: { [string]: boolean } = {}
	combat.abilities = made
	return made
end

-- A secret's key (its layout `needs`), abilities only: an ability id that `abilities.list` sells
-- is held when owned. Anything else (an element, "fire" or "ice", or an unknown word) is false
-- here; HoldsKey adds the elements (L2-31). It fails closed.
function Unlocks.HasKey(
	abilities: { [string]: boolean }?,
	config: Types.ExpeditionsConfig?,
	needs: string
): boolean
	return Unlocks.Find(config, needs) ~= nil and Unlocks.Owns(abilities, needs)
end

-- L2-30: the starter families, a set: the config `loadout`'s values (ProvingGrounds.json), owned
-- by everyone and never written to a profile (L2-1). A slot the loadout leaves out (or names with
-- something that is not a string) adds nothing.
function Unlocks.Starters(loadout: { melee: string, ranged: string }?): { [string]: boolean }
	local starters: { [string]: boolean } = {}
	if type(loadout) ~= "table" then
		return starters
	end
	for _, family in { loadout.melee, loadout.ranged } do
		if type(family) == "string" and family ~= "" then
			starters[family] = true
		end
	end
	return starters
end

-- L2-30: owned = a starter, or a family the profile's `families` holds true for.
function Unlocks.OwnsFamily(
	families: { [string]: boolean }?,
	id: string,
	starters: { [string]: boolean }
): boolean
	return starters[id] == true or (families ~= nil and families[id] == true)
end

-- The element a family carries: its `element` when that is one of the two words, else nil (no
-- such family, no element, or a word that is not an element: it fails closed).
function Unlocks.ElementOf(
	weapons: { [string]: Types.RangeWeaponDef }?,
	family: string
): Types.Element?
	local def = if type(weapons) == "table" then weapons[family] else nil
	local element: any = if type(def) == "table" then def.element else nil
	return if type(element) == "string" then ELEMENTS[element] else nil
end

-- L2-31: true when an owned family (a starter or a written one) carries `element`. A word that is
-- not an element is never held, whatever the profile claims.
function Unlocks.HasElement(
	families: { [string]: boolean }?,
	weapons: { [string]: Types.RangeWeaponDef }?,
	starters: { [string]: boolean },
	element: string
): boolean
	if ELEMENTS[element] == nil or type(weapons) ~= "table" then
		return false
	end
	for family in weapons do
		if
			Unlocks.ElementOf(weapons, family) == element
			and Unlocks.OwnsFamily(families, family, starters)
		then
			return true
		end
	end
	return false
end

-- L2-31: a secret's key held by a profile's combat, as UnlockService asks it: a sold ability that
-- is owned, then an element an owned family carries. Every other word fails closed.
function Unlocks.HoldsKey(
	combat: Types.CombatProfile,
	config: Types.ExpeditionsConfig?,
	weapons: { [string]: Types.RangeWeaponDef }?,
	starters: { [string]: boolean },
	needs: string
): boolean
	return Unlocks.HasKey(combat.abilities, config, needs)
		or Unlocks.HasElement(combat.families, weapons, starters, needs)
end

-- L2-32: may this player hold `family` (its variant `variant`) in `slot` now? nil = yes; otherwise
-- the ActionResult's reason, the first that applies in this order: no profile loaded; no such
-- family or variant, or the family fills the other slot; not owned; not allowed here (gateOpen =
-- WaveService.MayLeave: false while fighting in a live run).
function Unlocks.FamilyVerdict(
	state: Types.PlayerState?,
	weapons: { [string]: Types.RangeWeaponDef }?,
	starters: { [string]: boolean },
	slot: string,
	family: string,
	variant: string,
	gateOpen: boolean
): string?
	local def = if type(weapons) == "table" then weapons[family] else nil
	local verdict: string? = nil
	if state == nil then
		verdict = "unavailable"
	elseif
		type(def) ~= "table"
		or def.slot ~= slot
		or type(def.variants) ~= "table"
		or def.variants[variant] == nil
	then
		verdict = "invalid"
	elseif not Unlocks.OwnsFamily(state.combat.families, family, starters) then
		verdict = "locked"
	elseif not gateOpen then
		verdict = "busy"
	end
	return verdict
end

-- L2-9: may this player buy `def` now? nil = yes; otherwise the ActionResult's reason, the
-- first that applies in this order: no profile loaded, no such (or a malformed) ability,
-- already owned, not allowed here (gateOpen = WaveService.MayLeave: false while fighting in a
-- live run), Valor short.
function Unlocks.BuyVerdict(
	state: Types.PlayerState?,
	def: Types.UnlockAbilityDef?,
	gateOpen: boolean
): string?
	if state == nil then
		return "unavailable"
	end
	if def == nil or Unlocks.DefProblem(def) ~= nil then
		return "invalid"
	end
	local combat = state.combat
	if Unlocks.Owns(combat.abilities, def.id) then
		return "owned"
	end
	if not gateOpen then
		return "busy"
	end
	if not (combat.valor >= def.price.valor) then
		return "insufficientFunds"
	end
	return nil
end

-- L2-9 steps 2 and 3 (the fix round's s3): the purchase, decided and written in one call with no
-- yield. nil = sold: the price is taken from `combat.valor` and the ability is owned. Otherwise
-- BuyVerdict's reason, and the profile is untouched. UnlockService only sets the attribute and
-- answers.
function Unlocks.Apply(
	state: Types.PlayerState?,
	def: Types.UnlockAbilityDef?,
	gateOpen: boolean
): string?
	local verdict = Unlocks.BuyVerdict(state, def, gateOpen)
	if verdict ~= nil or state == nil or def == nil then
		return verdict or "invalid"
	end
	local combat = state.combat
	combat.valor -= def.price.valor
	Unlocks.AbilitiesOf(combat)[def.id] = true
	return nil
end

return Unlocks
