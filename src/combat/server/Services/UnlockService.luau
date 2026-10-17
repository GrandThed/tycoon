--!strict
-- L2 W1 (docs/prompts/l2-w1-contract.md, L2-2, L2-8, L2-9, L2-12, L2-19): what a player has
-- unlocked in the dungeon place. It sells abilities (RequestBuyAbility), opens secrets for the
-- run loop, and applies the Studio levers. It is the only writer of the profile's
-- `combat.abilities`, `secrets`, `families` and `shortcuts` (schema v7), and of the
-- `Ability_<id>` Player attributes every client reads.
--
-- The rules are Unlocks' and SecretFlow's (pure, tested by tools/crowd_harness); this file only
-- reads the profile, asks them and writes what they decide. Nothing here yields, so no purchase
-- can be interleaved between its check and its write.
--
-- It requires neither WaveService nor DebugService: the shop's gate is a hook (SetShopGate), so
-- both of those may require this module without a cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local SecretFlow = require(script.Parent:WaitForChild("SecretFlow"))

type Reason = "unavailable" | "invalid" | "owned" | "busy" | "insufficientFunds"

local state = {
	mode = "mission" :: Types.CombatMode,
	-- The sellable entries of Expeditions.json `abilities.list`, read once at Init.
	defs = {} :: { Types.UnlockAbilityDef },
	-- Players AddPlayer has seen this session (the levers' "everyone admitted").
	players = {} :: { [Player]: boolean },
	-- WaveService.MayLeave, wired by Main; nil = the shop is closed.
	gate = nil :: ((Player) -> boolean)?,
}

local UnlockService = {}

-- Spelled out so the literal types survive the trip into the ActionResult (a singleton union
-- that has passed through a `string` reaches it as plain string under the old solver).
local function reasonOf(verdict: string): Reason
	if verdict == "owned" then
		return "owned"
	elseif verdict == "busy" then
		return "busy"
	elseif verdict == "insufficientFunds" then
		return "insufficientFunds"
	elseif verdict == "invalid" then
		return "invalid"
	end
	return "unavailable"
end

local function answer(player: Player, id: string, verdict: string?): ()
	local result: Types.ActionResult = {
		action = "buyAbility",
		slotId = id,
		ok = verdict == nil,
		reason = if verdict ~= nil then reasonOf(verdict) else nil,
	}
	RemoteService.FireClient(player, "ActionResult", result)
end

-- The profile's map by that name, made when a profile lacks it (v6 code may have saved one, and
-- the v7 migration is the usual source). Only this place writes them.
local function abilitiesOf(combat: Types.CombatProfile): { [string]: boolean }
	local existing = combat.abilities
	if existing ~= nil then
		return existing
	end
	local made: { [string]: boolean } = {}
	combat.abilities = made
	return made
end

local function secretsOf(combat: Types.CombatProfile, levelId: string): { [string]: boolean }
	local byLevel: { [string]: { [string]: boolean } }
	local existing = combat.secrets
	if existing ~= nil then
		byLevel = existing
	else
		byLevel = {}
		combat.secrets = byLevel
	end
	local own = byLevel[levelId]
	if own ~= nil then
		return own
	end
	local made: { [string]: boolean } = {}
	byLevel[levelId] = made
	return made
end

local function familiesOf(combat: Types.CombatProfile): { [string]: boolean }
	local existing = combat.families
	if existing ~= nil then
		return existing
	end
	local made: { [string]: boolean } = {}
	combat.families = made
	return made
end

-- Every configured ability's attribute on this player, from the profile (in the range: all on,
-- so the P1 bench plays as it always has).
local function publish(player: Player): ()
	local profile = DataService.GetState(player)
	local abilities = if profile ~= nil then profile.combat.abilities else nil
	for _, def in state.defs do
		local owned = state.mode == "range" or Unlocks.Owns(abilities, def.id)
		player:SetAttribute(Unlocks.Attribute(def.id), owned)
	end
end

local function targets(player: Player?): { Player }
	if player ~= nil then
		return if state.players[player] then { player } else {}
	end
	local list: { Player } = {}
	for other in state.players do
		table.insert(list, other)
	end
	return list
end

function UnlockService.Configure(mode: Types.CombatMode): ()
	state.mode = mode
end

-- Reads and checks Expeditions.json `abilities`: a bad entry is warned and cannot be bought, a
-- missing block sells nothing. Never throws.
function UnlockService.Init(): ()
	table.clear(state.defs)
	local config = Catalog.GetExpeditionsConfig()
	local abilities: any = if config ~= nil then config.abilities else nil
	if abilities == nil then
		return
	end
	local list = if type(abilities) == "table" then abilities.list else nil
	if type(list) ~= "table" then
		warn("[UnlockService] Expeditions.json abilities.list is not a list: nothing is sold")
		return
	end
	local seen: { [string]: boolean } = {}
	for index, def in list do
		local problem = Unlocks.DefProblem(def)
		if problem == nil and seen[def.id] then
			problem = `repeats the id "{def.id}"`
		end
		if problem ~= nil then
			warn(`[UnlockService] abilities.list entry {index} {problem}: it cannot be bought`)
			continue
		end
		seen[def.id] = true
		table.insert(state.defs, def)
	end
end

function UnlockService.Start(): () end

-- The shop's gate (L2-9 step 2): true where a purchase is allowed.
function UnlockService.SetShopGate(gate: (Player) -> boolean): ()
	state.gate = gate
end

-- At admit (and in the range at the join): the attributes in.
function UnlockService.AddPlayer(player: Player): ()
	if player.Parent == nil then
		return
	end
	state.players[player] = true
	publish(player)
end

-- At release: the session's state out (the attributes leave with the Player).
function UnlockService.RemovePlayer(player: Player): ()
	state.players[player] = nil
end

-- RequestBuyAbility (L2-9). An id, never an amount: the price is the config's.
function UnlockService.OnBuyAbility(player: Player, id: string): ()
	if state.mode == "range" then
		return
	end
	local profile = if state.players[player] then DataService.GetState(player) else nil
	local def = Unlocks.Find(Catalog.GetExpeditionsConfig(), id)
	local gate = state.gate
	local verdict = Unlocks.BuyVerdict(profile, def, gate ~= nil and gate(player))
	if verdict ~= nil or profile == nil or def == nil then
		answer(player, id, verdict or "invalid")
		return
	end
	local combat = profile.combat
	combat.valor -= def.price.valor
	abilitiesOf(combat)[def.id] = true
	player:SetAttribute(Unlocks.Attribute(def.id), true)
	answer(player, id, nil)
	ArenaService.SendSnapshot(player)
end

-- True when the player's profile holds the key a secret needs (never the attribute).
function UnlockService.HoldsKey(player: Player, needs: string): boolean
	local profile = DataService.GetState(player)
	return profile ~= nil
		and Unlocks.HasKey(profile.combat.abilities, Catalog.GetExpeditionsConfig(), needs)
end

-- L2-12: a standing fighter reached `site` in the run on `levelId`. The key is read from the
-- profile, never from the attribute. On "pay" the chest's reward is credited and the secret
-- recorded; the caller credits the summary, marks the wallet and tells the clients. `material`
-- is the level's ("" = its materials go nowhere and are reported as 0).
function UnlockService.OpenSecret(
	player: Player,
	levelId: string,
	site: SecretFlow.Site,
	material: string
): SecretFlow.Opening
	local profile = DataService.GetState(player)
	if profile == nil then
		return { verdict = "nothing", valor = 0, materials = 0, family = nil }
	end
	local combat = profile.combat
	local byLevel = combat.secrets
	local opened = if byLevel ~= nil then byLevel[levelId] else nil
	local found = opened ~= nil and opened[site.id] == true
	local hasKey = Unlocks.HasKey(combat.abilities, Catalog.GetExpeditionsConfig(), site.needs)
	local verdict = SecretFlow.Decide(site, hasKey, found)
	local reward = site.reward
	if verdict ~= "pay" or reward == nil then
		return { verdict = verdict :: SecretFlow.Verdict, valor = 0, materials = 0, family = nil }
	end
	combat.valor += reward.valor
	local materials = if material ~= "" then reward.materials else 0
	if materials > 0 then
		combat.materials[material] = (combat.materials[material] or 0) + materials
	end
	local family = reward.family
	if family ~= nil then
		familiesOf(combat)[family] = true
	end
	secretsOf(combat, levelId)[site.id] = true
	return { verdict = "pay", valor = reward.valor, materials = materials, family = family }
end

-- The `grantAbility` lever: owned, its attribute on, the wallet resent. False when the id is not
-- a sellable ability or the player has no profile.
function UnlockService.GrantAbility(player: Player, id: string): boolean
	local profile = DataService.GetState(player)
	if profile == nil or Unlocks.Find(Catalog.GetExpeditionsConfig(), id) == nil then
		return false
	end
	abilitiesOf(profile.combat)[id] = true
	player:SetAttribute(Unlocks.Attribute(id), true)
	ArenaService.SendSnapshot(player)
	return true
end

-- The `removeAbility` lever: no longer owned, its attribute off, the wallet resent.
function UnlockService.RemoveAbility(player: Player, id: string): boolean
	local profile = DataService.GetState(player)
	if profile == nil or Unlocks.Find(Catalog.GetExpeditionsConfig(), id) == nil then
		return false
	end
	abilitiesOf(profile.combat)[id] = nil
	player:SetAttribute(Unlocks.Attribute(id), false)
	ArenaService.SendSnapshot(player)
	return true
end

-- The `resetSecrets` lever: every opened secret and found shortcut of `player` (nil = everyone
-- admitted) is forgotten; the families found stay. The run's own once-per-run memory is
-- WaveService's (WaveService.ForgetSecrets).
function UnlockService.ResetSecrets(player: Player?): ()
	for _, target in targets(player) do
		local profile = DataService.GetState(target)
		if profile ~= nil then
			profile.combat.secrets = {}
			profile.combat.shortcuts = {}
			ArenaService.SendSnapshot(target)
		end
	end
end

-- Everyone admitted this session (the attribute levers act on all of them).
function UnlockService.Admitted(): { Player }
	return targets(nil)
end

-- The ability's display name, for the levers' notices (the id when it is not sold).
function UnlockService.NameOf(id: string): string
	local def = Unlocks.Find(Catalog.GetExpeditionsConfig(), id)
	return if def ~= nil then def.name else id
end

return UnlockService
