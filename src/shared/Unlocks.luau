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

local Unlocks = {}

Unlocks.AIR_JUMP = AIR_JUMP

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
	if type(def.name) ~= "string" or def.name == "" then
		return "has no name"
	end
	if type(def.text) ~= "string" then
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

-- The sellable entry with this id; nil when there is none, or when its entry is malformed. The
-- first entry of an id wins, as a repeated id is a typo the Init warning names.
function Unlocks.Find(config: Types.ExpeditionsConfig?, id: string): Types.UnlockAbilityDef?
	local abilities = if config ~= nil then config.abilities else nil
	local list = if abilities ~= nil then abilities.list else nil
	if type(list) ~= "table" then
		return nil
	end
	for _, def in list do
		if type(def) == "table" and def.id == id then
			return if Unlocks.DefProblem(def) == nil then def else nil
		end
	end
	return nil
end

-- A secret's key (its layout `needs`). An ability id that `abilities.list` sells is held when
-- owned. Anything else (an element, "fire" or "ice", or an unknown word) is false in W1: W2 and
-- W3 add the elements. It fails closed.
function Unlocks.HasKey(
	abilities: { [string]: boolean }?,
	config: Types.ExpeditionsConfig?,
	needs: string
): boolean
	return Unlocks.Find(config, needs) ~= nil and Unlocks.Owns(abilities, needs)
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

return Unlocks
