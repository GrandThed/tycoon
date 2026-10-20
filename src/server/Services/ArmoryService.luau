--!strict
-- The Armory in the hub (docs/INTERFACES.md "C0 contracts", docs/prompts/l3-w1-contract.md L3-12,
-- L3-14, L3-28). Three intents, one validation chain each, one atomic mutation:
-- RequestUpgradeWeapon (a family up one tier of the ladder), RequestSetFamily (the held family of
-- a slot, saved) and RequestAscend (the Rebirth forge, kept and unreachable until L4). The chains
-- live in the pure Armory and Unlocks modules, the same ones the dungeon place's UnlockService
-- calls; this service supplies the profile and writes nothing they did not decide. The hub has no
-- fight, so its gate is always open.
--
-- Materials and Valor are earned in the combat place only; nothing here mints either outside
-- the Studio levers at the bottom.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Combat = require(sharedFolder:WaitForChild("Combat"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local ExpeditionService = require(script.Parent:WaitForChild("ExpeditionService"))
local PartyService = require(script.Parent:WaitForChild("PartyService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

-- The Studio levers are polled, like EconomyService's GrantCash/GrantLegacy, so the value can be
-- typed into the Properties pane mid-playtest.
local LEVER_INTERVAL_SECONDS = 1

type Action = "ascend" | "upgradeWeapon" | "setFamily"

-- The verdicts Armory and Unlocks answer with, as ActionResult reasons: a singleton union that
-- crossed a `string` reaches the typed ActionResult as plain string under the old solver.
local REASONS: { [string]: Types.ActionReason } = {}
REASONS.insufficientFunds = "insufficientFunds"
REASONS.locked = "locked"
REASONS.invalid = "invalid"
REASONS.unavailable = "unavailable"
REASONS.busy = "busy"
REASONS.peak = "peak"
REASONS.notBuilt = "notBuilt"
REASONS.needsStar = "needsStar"
table.freeze(REASONS)

local isStudio = RunService:IsStudio()
local leverAccumulator = 0
-- DebugFakeParty is sticky like DebugBots (a count to play under, not an event), so it applies
-- to every player whenever the typed value changes.
local appliedFakeParty: number? = nil
-- L3-13: the level ids this build has a level file for, read once at Init (a band whose level is
-- not here cannot be bought: notBuilt).
local built: { [string]: boolean } = {}

-- An unknown verdict can only mean a drifted shared module: "invalid" is the honest reply for it.
local function reasonOf(verdict: string?): Types.ActionReason?
	if verdict == nil then
		return nil
	end
	return REASONS[verdict] or "invalid"
end

local function sendResult(player: Player, action: Action, slotId: string, verdict: string?): ()
	local result: Types.ActionResult = {
		action = action,
		slotId = slotId,
		ok = verdict == nil,
		reason = reasonOf(verdict),
	}
	RemoteService.FireClient(player, "ActionResult", result)
end

-- The starters (L2-30) and the weapon families of ProvingGrounds.json, the same config the
-- dungeon place reads. nil without that file: nothing can be owned or equipped then.
local function weaponsConfig(): ({ [string]: Types.RangeWeaponDef }?, { [string]: boolean })
	local config = Catalog.GetProvingGroundsConfig()
	if config == nil then
		return nil, {}
	end
	return config.weapons, Unlocks.Starters(config.loadout)
end

-- L3-14: one family up one tier. Armory.Upgrade decides and writes in one call with no yield, so
-- two requests in flight cannot both pass.
local function tryUpgradeWeapon(player: Player, family: string): ()
	local state = DataService.GetState(player)
	local armoryConfig = Catalog.GetArmoryConfig()
	local weapons, starters = weaponsConfig()
	if state == nil or armoryConfig == nil or weapons == nil then
		sendResult(player, "upgradeWeapon", family, "unavailable")
		return
	end
	local owned = Unlocks.OwnsFamily(state.combat.families, family, starters)
	local verdict = Armory.Upgrade(armoryConfig, state.combat, family, owned, true, built)
	if verdict == nil then
		EconomyService.MarkDirty(player, { combat = true })
	end
	sendResult(player, "upgradeWeapon", family, verdict)
end

-- L3-14: the held family of a slot (and its style), saved to the profile's loadout. The dungeon
-- place reads it at its next admit (Unlocks.LoadoutOf).
local function trySetFamily(player: Player, slot: string, family: string, variant: string): ()
	local state = DataService.GetState(player)
	local weapons, starters = weaponsConfig()
	local verdict = if weapons == nil
		then "unavailable"
		else Unlocks.FamilyVerdict(state, weapons, starters, slot, family, variant, true)
	if verdict == nil and state ~= nil then
		Unlocks.SaveLoadout(state.combat, slot, family, variant)
		EconomyService.MarkDirty(player, { combat = true })
	end
	sendResult(player, "setFamily", family, verdict)
end

-- Both mutations write the same two-field records, and a validated slot is either "melee" or
-- "ranged", so the write is spelled out rather than indexed dynamically.
local function setSlotValue(
	tiers: { melee: number, ranged: number },
	slot: string,
	value: number
): ()
	if slot == "melee" then
		tiers.melee = value
	elseif slot == "ranged" then
		tiers.ranged = value
	end
end

local function spendMaterials(state: Types.PlayerState, material: string, amount: number): ()
	local owned = state.combat.materials[material] or 0
	-- Never below zero: Armory.CanAscend has already proved the wallet covers it, and a negative
	-- balance would persist.
	state.combat.materials[material] = math.max(0, owned - amount)
end

-- The Rebirth-gated Ascension forge: the cap comes from rebirthCount, the cost from all four
-- materials plus Valor.
local function tryAscend(player: Player, slot: string): ()
	local state = DataService.GetState(player)
	local armoryConfig = Catalog.GetArmoryConfig()
	if state == nil or armoryConfig == nil then
		sendResult(player, "ascend", slot, "invalid")
		return
	end
	Combat.TouchHighestEra(state)

	local ok, reason = Armory.CanAscend(armoryConfig, state, slot)
	if not ok then
		sendResult(player, "ascend", slot, reason or "invalid")
		return
	end
	local current = if slot == "melee"
		then state.combat.ascension.melee
		else state.combat.ascension.ranged
	local level = current + 1
	local cost = Armory.AscensionCost(armoryConfig, level)
	if cost == nil then
		sendResult(player, "ascend", slot, "locked")
		return
	end

	for material, amount in cost.materials do
		spendMaterials(state, material, amount)
	end
	state.combat.valor = math.max(0, state.combat.valor - cost.valor)
	setSlotValue(state.combat.ascension, slot, level)
	EconomyService.MarkDirty(player, { combat = true })
	sendResult(player, "ascend", slot, nil)
end

-- ---------------------------------------------------------------------------------------------
-- Studio levers (inert outside Studio: Start polls only there, HandleDebug returns at once)
-- ---------------------------------------------------------------------------------------------

-- L3-28: the grant pays the material of every band whose level has a level file (Timber today),
-- as the dungeon lobby's does; it replaces the C0 rule of the player's era band. Shared by the
-- attribute and the RequestDebug lever.
local function grantMaterialsTo(state: Types.PlayerState, value: number): ()
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		return
	end
	local _, materials = Armory.BuiltBands(armoryConfig, built)
	for _, material in materials do
		state.combat.materials[material] = (state.combat.materials[material] or 0) + value
	end
end

-- L3-28 setTier: "<family>=<tier>", the tier held to the family's window; owning it is not needed.
local function setTierFor(player: Player, state: Types.PlayerState, value: any): ()
	local armoryConfig = Catalog.GetArmoryConfig()
	local family, tier = Unlocks.TierLever(value)
	if armoryConfig == nil or family == nil or tier == nil then
		warn(`[ArmoryService] setTier wants "<family>=<tier>", got {tostring(value)}`)
		return
	end
	local written = Armory.SetTier(armoryConfig, state.combat, family, tier)
	if written == nil then
		warn(`[ArmoryService] setTier: "{family}" has no window on the ladder`)
		return
	end
	EconomyService.MarkDirty(player, { combat = true })
	warn(`[ArmoryService] setTier: {player.Name}'s {family} is T{written}`)
end

-- L3-28 grantStar: the ladder's starDifficulty star of a level that has a level file, or of every
-- built band level for Unlocks.ALL_STARS.
local function grantStarTo(player: Player, state: Types.PlayerState, value: any): ()
	local armoryConfig = Catalog.GetArmoryConfig()
	local ladder = if armoryConfig ~= nil then armoryConfig.ladder else nil
	if armoryConfig == nil or ladder == nil or typeof(value) ~= "string" then
		return
	end
	local levels: { string } = {}
	if value == Unlocks.ALL_STARS then
		levels = (Armory.BuiltBands(armoryConfig, built))
	elseif built[value] == true then
		levels = { value }
	end
	if #levels == 0 then
		warn(`[ArmoryService] grantStar: no built level "{value}"`)
		return
	end
	local stars = Unlocks.StarsOf(state.combat)
	for _, levelId in levels do
		local row = stars[levelId] or {}
		stars[levelId] = row
		row[ladder.starDifficulty] = true
	end
	EconomyService.MarkDirty(player, { combat = true })
	warn(
		`[ArmoryService] grantStar: {player.Name} holds the {ladder.starDifficulty} star of {table.concat(
			levels,
			", "
		)}`
	)
end

-- L3-28 resetArmory: tiers, loadout and stars emptied; materials, Valor, families and secrets stay.
local function resetArmoryFor(player: Player, state: Types.PlayerState): ()
	Unlocks.ResetArmory(state.combat)
	EconomyService.MarkDirty(player, { combat = true })
	warn(`[ArmoryService] resetArmory: {player.Name}'s tiers, loadout and stars are empty`)
end

-- A positive finite number is the only value that pays something out: a corrupted materials,
-- Valor or cash field can never be persisted from a typo in the Properties pane.
local function grantAmount(value: any): number?
	if typeof(value) ~= "number" or value <= 0 or value ~= value or value == math.huge then
		return nil
	end
	return value
end

-- Studio levers (same shape as EconomyService's GrantCash): a positive number on Workspace is
-- consumed once and reset to 0, for every loaded player.
local function consumeGrantLever(
	attribute: string,
	apply: (state: Types.PlayerState, value: number) -> ()
): ()
	-- NaN/inf are refused too: Studio with API access writes a real profile, and a corrupted
	-- materials or Valor field would survive the session.
	local value = grantAmount(workspace:GetAttribute(attribute))
	if value == nil then
		return
	end
	workspace:SetAttribute(attribute, 0)
	local granted = 0
	for _, player in Players:GetPlayers() do
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		apply(state, value)
		EconomyService.MarkDirty(player, { combat = true })
		granted += 1
	end
	warn(
		`[ArmoryService] {attribute} lever: granted {value} to {granted} loaded player(s);`
			.. ` attribute reset to 0`
	)
end

-- L3-28's string levers (setTier, grantStar): a non-empty string is consumed once (reset to "")
-- and applied to every loaded player. nil = the lever is off in Combat.json.
local function consumeStringLever(
	attribute: string?,
	apply: (
		player: Player,
		state: Types.PlayerState,
		value: string
	) -> ()
): ()
	if attribute == nil then
		return
	end
	local value = workspace:GetAttribute(attribute)
	if typeof(value) ~= "string" or value == "" then
		return
	end
	workspace:SetAttribute(attribute, "")
	for _, player in Players:GetPlayers() do
		local state = DataService.GetState(player)
		if state ~= nil then
			apply(player, state, value)
		end
	end
end

-- L3-28's resetArmory attribute: a number above 0, consumed once (reset to 0).
local function consumeResetLever(attribute: string?): ()
	if attribute == nil or grantAmount(workspace:GetAttribute(attribute)) == nil then
		return
	end
	workspace:SetAttribute(attribute, 0)
	for _, player in Players:GetPlayers() do
		local state = DataService.GetState(player)
		if state ~= nil then
			resetArmoryFor(player, state)
		end
	end
end

-- C1: the join list's Studio stand-in. Unlike the grant levers this one is not per player, so
-- it gets its own consumer rather than consumeGrantLever's loop over loaded profiles.
local function consumeFakeRunsLever(attribute: string): ()
	local value = grantAmount(workspace:GetAttribute(attribute))
	if value == nil then
		return
	end
	workspace:SetAttribute(attribute, 0)
	ExpeditionService.PublishFakeRuns(value)
end

-- C2 party levers. fakeParty applies to everyone in the server (the attribute has no owner);
-- fakeInvite is consumed once like the grant levers.
local function consumeFakePartyLever(attribute: string): ()
	local value = workspace:GetAttribute(attribute)
	if typeof(value) ~= "number" or value ~= value or value == appliedFakeParty then
		return
	end
	appliedFakeParty = value
	for _, player in Players:GetPlayers() do
		PartyService.DebugFakeParty(player, value)
	end
end

local function consumeFakeInviteLever(attribute: string): ()
	if workspace:GetAttribute(attribute) ~= true then
		return
	end
	workspace:SetAttribute(attribute, false)
	for _, player in Players:GetPlayers() do
		PartyService.DebugFakeInvite(player)
	end
end

local function consumeStudioLevers(): ()
	local combatConfig = Catalog.GetCombatConfig()
	local armoryConfig = Catalog.GetArmoryConfig()
	if combatConfig == nil or armoryConfig == nil then
		return
	end
	local debugConfig = combatConfig.debug
	consumeGrantLever(debugConfig.grantMaterialsAttribute, grantMaterialsTo)
	consumeGrantLever(debugConfig.grantValorAttribute, function(state, value)
		state.combat.valor += value
	end)
	consumeStringLever(debugConfig.setTierAttribute, setTierFor)
	consumeStringLever(debugConfig.grantStarAttribute, grantStarTo)
	consumeResetLever(debugConfig.resetArmoryAttribute)
	consumeFakeRunsLever(debugConfig.fakeRunsAttribute)
	consumeFakePartyLever(debugConfig.fakePartyAttribute)
	consumeFakeInviteLever(debugConfig.fakeInviteAttribute)
end

local ArmoryService = {}

-- RequestDebug (C1, docs/INTERFACES.md "Studio bridge" → "Hub side"). The same levers as the
-- Workspace attributes, driven by the client DebugPanel's buttons, but for the calling player
-- only. Outside Studio it does nothing at all: the remote exists in every build, the effects do
-- not. Never yields, so the intent handler needs no thread of its own.
function ArmoryService.HandleDebug(player: Player, lever: string, value: any): ()
	if not isStudio then
		return
	end
	if lever == "fakeRuns" then
		-- 0 clears the list, which is why this lever is not routed through grantAmount.
		ExpeditionService.PublishFakeRuns(if typeof(value) == "number" then value else 0)
		return
	end
	if lever == "fakeParty" then
		-- 0 clears the fakes; PartyService clamps to the seats a party has.
		PartyService.DebugFakeParty(player, if typeof(value) == "number" then value else 0)
		return
	end
	if lever == "fakeInvite" then
		if value == true then
			PartyService.DebugFakeInvite(player)
		end
		return
	end
	if lever == "forceTeleportFailure" then
		local combatConfig = Catalog.GetCombatConfig()
		if combatConfig == nil then
			return
		end
		-- The attribute stays the single source of truth (StudioBridge reads it), so the panel
		-- and the Properties pane can never disagree.
		workspace:SetAttribute(combatConfig.debug.forceTeleportFailureAttribute, value == true)
		return
	end
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	-- L3-28: the Armory's levers carry a string or nothing, never an amount.
	if lever == "setTier" then
		setTierFor(player, state, value)
		return
	elseif lever == "grantStar" then
		grantStarTo(player, state, value)
		return
	elseif lever == "resetArmory" then
		resetArmoryFor(player, state)
		return
	end
	local amount = grantAmount(value)
	if amount == nil then
		return
	end
	if lever == "grantCash" then
		state.cash += amount
		-- The attribute the client's leaderstats-style readouts mirror, as in EconomyService's
		-- GrantCash lever; cash itself rides the normal dirty/delta path.
		player:SetAttribute("Cash", state.cash)
		EconomyService.MarkDirty(player, { cash = true })
	elseif lever == "grantMaterials" then
		grantMaterialsTo(state, amount)
		EconomyService.MarkDirty(player, { combat = true })
	elseif lever == "grantValor" then
		state.combat.valor += amount
		EconomyService.MarkDirty(player, { combat = true })
	else
		warn(`[ArmoryService] unknown debug lever "{lever}"`)
	end
end

function ArmoryService.Init(): ()
	for _, levelId in Catalog.GetLevelIds() do
		built[levelId] = true
	end
	-- L3-5: the validator, warned once; the screen and the server both degrade on what it names.
	local armoryConfig = Catalog.GetArmoryConfig()
	local weapons = weaponsConfig()
	if armoryConfig ~= nil then
		local families: { string } = {}
		if weapons ~= nil then
			for family in weapons do
				table.insert(families, family)
			end
		end
		table.sort(families)
		for _, line in Armory.Problems(armoryConfig, families) do
			warn(`[ArmoryService] {line}`)
		end
	end
	-- Payload types are already validated by RemoteService; the casts narrow the varargs.
	RemoteService.SetHandler("RequestUpgradeWeapon", function(player: Player, family: any)
		tryUpgradeWeapon(player, family :: string)
	end)
	RemoteService.SetHandler(
		"RequestSetFamily",
		function(player: Player, slot: any, family: any, variant: any)
			trySetFamily(player, slot :: string, family :: string, variant :: string)
		end
	)
	RemoteService.SetHandler("RequestAscend", function(player: Player, slot: any)
		tryAscend(player, slot :: string)
	end)
end

function ArmoryService.Start(): ()
	if not isStudio then
		return
	end
	RunService.Heartbeat:Connect(function(deltaTime: number)
		leverAccumulator += deltaTime
		if leverAccumulator < LEVER_INTERVAL_SECONDS then
			return
		end
		leverAccumulator = 0
		consumeStudioLevers()
	end)
end

return ArmoryService
