--!strict
-- L2 W1 (docs/prompts/l2-w1-contract.md, L2-2, L2-8, L2-9, L2-12, L2-19): what a player has
-- unlocked in the dungeon place. It sells abilities (RequestBuyAbility), opens secrets for the
-- run loop, and applies the Studio levers. Only it (through Unlocks.Apply and SecretFlow.Open,
-- which it calls) writes the profile's `combat.abilities`, `secrets`, `families` and `shortcuts`
-- (schema v7), and the `Ability_<id>` Player attributes every client reads.
--
-- The rules and the writes they decide are Unlocks' and SecretFlow's (pure, tested by
-- tools/crowd_harness); this file only hands them the profile and acts on the verdict. Nothing
-- here yields, so no purchase can be interleaved between its check and its write.
--
-- It requires neither WaveService nor DebugService: the shop's gate is a hook (SetShopGate), so
-- both of those may require this module without a cycle.
--
-- L2 W2 (docs/prompts/l2-w2-contract.md, L2-30 to L2-32, L2-36, L2-38): it also answers
-- RequestSetFamily (Unlocks.FamilyVerdict, then WeaponService holds the family for the session:
-- no save, L2-33), records found shortcuts, and keys a secret on an element an owned family
-- carries. WeaponService requires none of the place's services that require this one, so the
-- new require adds no cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local SecretFlow = require(script.Parent:WaitForChild("SecretFlow"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

type Reason = "unavailable" | "invalid" | "owned" | "busy" | "insufficientFunds" | "locked"
type Action = "buyAbility" | "setFamily"

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
	elseif verdict == "locked" then
		return "locked"
	end
	return "unavailable"
end

local function answer(player: Player, id: string, verdict: string?, action: Action?): ()
	local result: Types.ActionResult = {
		action = action or "buyAbility",
		slotId = id,
		ok = verdict == nil,
		reason = if verdict ~= nil then reasonOf(verdict) else nil,
	}
	RemoteService.FireClient(player, "ActionResult", result)
end

-- The weapon families and the starters (L2-30), from the weapons' config as Tuning reads it.
local function weapons(): { [string]: Types.RangeWeaponDef }?
	local config: any = Tuning.Get()
	return if type(config.weapons) == "table" then config.weapons else nil
end

local function starters(): { [string]: boolean }
	local config: any = Tuning.Get()
	return Unlocks.Starters(config.loadout)
end

-- L2-31: the key a secret needs, held by this profile's combat (abilities, then elements).
local function holds(combat: Types.CombatProfile, needs: string): boolean
	return Unlocks.HoldsKey(combat, Catalog.GetExpeditionsConfig(), weapons(), starters(), needs)
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
-- missing block sells nothing. Unlocks.Sellable is the rule Find uses, so the attribute published
-- for an id and the entry a purchase prices are always the same entry. Never throws.
function UnlockService.Init(): ()
	local defs, problems = Unlocks.Sellable(Catalog.GetExpeditionsConfig())
	state.defs = defs
	for _, problem in problems do
		warn(`[UnlockService] Expeditions.json {problem}`)
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
	local gate = state.gate
	local verdict = Unlocks.Apply(
		profile,
		Unlocks.Find(Catalog.GetExpeditionsConfig(), id),
		gate ~= nil and gate(player)
	)
	if verdict ~= nil then
		answer(player, id, verdict)
		return
	end
	player:SetAttribute(Unlocks.Attribute(id), true)
	answer(player, id, nil)
	ArenaService.SendSnapshot(player)
end

-- True when the player's profile holds the key a secret needs (never the attribute): a sold
-- ability that is owned, then an element an owned family carries (L2-31). So `fire` is held once
-- the lookout has paid the Flamethrower, whatever the player carries in this run.
function UnlockService.HoldsKey(player: Player, needs: string): boolean
	local profile = DataService.GetState(player)
	return profile ~= nil and holds(profile.combat, needs)
end

-- RequestSetFamily (L2-32), in a mission: the verdict in order (unavailable, invalid, locked,
-- busy), then WeaponService holds the variant and the family; its TuneState carries the loadout
-- back to the client. Answered with an ActionResult either way. The range has its own commands.
function UnlockService.OnSetFamily(
	player: Player,
	slot: string,
	family: string,
	variant: string
): ()
	if state.mode == "range" then
		return
	end
	local profile = if state.players[player] then DataService.GetState(player) else nil
	local gate = state.gate
	local verdict = Unlocks.FamilyVerdict(
		profile,
		weapons(),
		starters(),
		slot,
		family,
		variant,
		gate ~= nil and gate(player)
	)
	if verdict == nil then
		-- The variant first, so the family's own TuneState (the last one sent) carries both.
		local held = WeaponService.SetVariant(player, family, variant)
			and WeaponService.SetFamily(player, family)
		verdict = if held then nil else "unavailable"
	end
	answer(player, family, verdict, "setFamily")
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
	return SecretFlow.Open(combat, levelId, site, holds(combat, site.needs), material)
end

-- L2-36: a standing fighter is inside the shortcut `id` of `levelId`. Recorded in their own
-- profile; true when it is new (the caller shows the card). False without a profile.
function UnlockService.FindShortcut(player: Player, levelId: string, id: string): boolean
	local profile = DataService.GetState(player)
	if profile == nil then
		return false
	end
	local new = SecretFlow.RecordShortcut(profile.combat, levelId, id)
	if new then
		ArenaService.SendSnapshot(player)
	end
	return new
end

-- L2-36: the shortcuts of `levelId` this player has found, a set of its own (the leader's opens
-- the level a run builds). Empty without a profile.
function UnlockService.FoundShortcuts(player: Player, levelId: string): { [string]: boolean }
	local profile = DataService.GetState(player)
	return SecretFlow.FoundShortcuts(if profile ~= nil then profile.combat else nil, levelId)
end

-- The `grantFamily` lever (L2-38): written to the profile's families, the wallet resent. False
-- when the id is no family, is a starter (owned by everyone, never written: L2-30) or the player
-- has no profile.
function UnlockService.GrantFamily(player: Player, id: string): boolean
	local profile = DataService.GetState(player)
	local roster = weapons()
	if profile == nil or roster == nil or roster[id] == nil or starters()[id] then
		return false
	end
	SecretFlow.FamiliesOf(profile.combat)[id] = true
	ArenaService.SendSnapshot(player)
	return true
end

-- The `removeFamily` lever (L2-38): cleared from the profile's families; a slot holding it goes
-- back to its starter. False for a starter, an id that is no family, or no profile.
function UnlockService.RemoveFamily(player: Player, id: string): boolean
	local profile = DataService.GetState(player)
	local roster = weapons()
	local def = if roster ~= nil then roster[id] else nil
	if profile == nil or def == nil or starters()[id] then
		return false
	end
	SecretFlow.FamiliesOf(profile.combat)[id] = nil
	local loadout = WeaponService.LoadoutOf(player)
	local held = if loadout == nil
		then nil
		elseif def.slot == "melee" then loadout.melee
		else loadout.ranged
	if held == id then
		local config: any = Tuning.Get()
		local starter = if type(config.loadout) == "table" then config.loadout[def.slot] else nil
		if type(starter) == "string" then
			WeaponService.SetFamily(player, starter)
		end
	end
	ArenaService.SendSnapshot(player)
	return true
end

-- A family's display name, for the levers' notices (the id when there is no such family).
function UnlockService.FamilyName(id: string): string
	local roster = weapons()
	local def = if roster ~= nil then roster[id] else nil
	return if def ~= nil and type(def.name) == "string" then def.name else id
end

-- The `grantAbility` lever: owned, its attribute on, the wallet resent. False when the id is not
-- a sellable ability or the player has no profile.
function UnlockService.GrantAbility(player: Player, id: string): boolean
	local profile = DataService.GetState(player)
	if profile == nil or Unlocks.Find(Catalog.GetExpeditionsConfig(), id) == nil then
		return false
	end
	Unlocks.AbilitiesOf(profile.combat)[id] = true
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
	Unlocks.AbilitiesOf(profile.combat)[id] = nil
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
