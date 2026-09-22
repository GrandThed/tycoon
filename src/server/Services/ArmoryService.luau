--!strict
-- The Armory purchase path in the hub (docs/INTERFACES.md "C0 contracts"). Weapons are the only
-- equipment, so this is the whole shop: two intents (RequestBuyGear, RequestAscend), one
-- validation chain each, one atomic mutation. The chain lives in the pure Armory module; this
-- service supplies the server-owned inputs (the profile and the PERSISTED income per second)
-- and writes the result.
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
local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

-- The Studio levers are polled, like EconomyService's GrantCash/GrantLegacy, so the value can be
-- typed into the Properties pane mid-playtest.
local LEVER_INTERVAL_SECONDS = 1

local isStudio = RunService:IsStudio()
local leverAccumulator = 0

local function sendResult(
	player: Player,
	action: "buyGear" | "ascend",
	slot: string,
	ok: boolean,
	reason: ("insufficientFunds" | "locked" | "invalid")?
): ()
	local result: Types.ActionResult = { action = action, slotId = slot, ok = ok, reason = reason }
	RemoteService.FireClient(player, "ActionResult", result)
end

-- Armory.CanBuy/CanAscend answer with one of three literals, but Luau widens a singleton union
-- when it crosses a module boundary, so the refusal is re-narrowed here for the typed
-- ActionResult. An unrecognised value can only mean a drifted Armory module: "invalid" is the
-- honest reply for it.
local function refusalReason(reason: string?): "insufficientFunds" | "locked" | "invalid"
	if reason == "insufficientFunds" then
		return "insufficientFunds"
	end
	if reason == "locked" then
		return "locked"
	end
	return "invalid"
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
	-- Never below zero: Armory.CanBuy has already proved the wallet covers it, and a negative
	-- balance would persist.
	state.combat.materials[material] = math.max(0, owned - amount)
end

-- Frozen chain: state loaded → Armory config present → a next tier exists → the city's
-- persisted income/s reaches its unlockRate → the band material covers its cost. No yields
-- between validation and mutation, so two in-flight requests cannot both pass.
local function tryBuyGear(player: Player, slot: string): ()
	local state = DataService.GetState(player)
	if state == nil then
		sendResult(player, "buyGear", slot, false, "invalid")
		return
	end
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		-- No Armory.json: the panel is hidden client-side, so this is a stale or forged intent.
		sendResult(player, "buyGear", slot, false, "invalid")
		return
	end
	-- Before any check that reads highestEra (PlotService.tryAdvanceEra is frozen this milestone).
	Combat.TouchHighestEra(state)

	local incomePerSecond = EconomyService.GetPersistedIncomePerSecond(player)
	local ok, reason = Armory.CanBuy(armoryConfig, state, slot, incomePerSecond)
	if not ok then
		sendResult(player, "buyGear", slot, false, refusalReason(reason))
		return
	end
	local tier = Armory.NextTier(armoryConfig, state.combat.gear, slot)
	if tier == nil then
		sendResult(player, "buyGear", slot, false, "invalid")
		return
	end
	local material, amount = Armory.TierCost(armoryConfig, slot, tier)

	spendMaterials(state, material, amount)
	setSlotValue(state.combat.gear, slot, tier)
	EconomyService.MarkDirty(player, { combat = true })
	sendResult(player, "buyGear", slot, true, nil)
end

-- Same chain for the Rebirth-gated Ascension forge: the cap comes from rebirthCount, the cost
-- from all four materials plus Valor.
local function tryAscend(player: Player, slot: string): ()
	local state = DataService.GetState(player)
	if state == nil then
		sendResult(player, "ascend", slot, false, "invalid")
		return
	end
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		sendResult(player, "ascend", slot, false, "invalid")
		return
	end
	Combat.TouchHighestEra(state)

	local ok, reason = Armory.CanAscend(armoryConfig, state, slot)
	if not ok then
		sendResult(player, "ascend", slot, false, refusalReason(reason))
		return
	end
	local current = if slot == "melee"
		then state.combat.ascension.melee
		else state.combat.ascension.ranged
	local level = current + 1
	local cost = Armory.AscensionCost(armoryConfig, level)
	if cost == nil then
		sendResult(player, "ascend", slot, false, "locked")
		return
	end

	for material, amount in cost.materials do
		spendMaterials(state, material, amount)
	end
	state.combat.valor = math.max(0, state.combat.valor - cost.valor)
	setSlotValue(state.combat.ascension, slot, level)
	EconomyService.MarkDirty(player, { combat = true })
	sendResult(player, "ascend", slot, true, nil)
end

-- Studio levers (same shape as EconomyService's GrantCash): a positive number on Workspace is
-- consumed once and reset to 0. GrantMaterials pays the material of the band matching the
-- player's CURRENT era, which is the one their Armory tiers are priced in.
local function consumeGrantLever(
	attribute: string,
	apply: (state: Types.PlayerState, value: number) -> ()
): ()
	local value = workspace:GetAttribute(attribute)
	-- NaN/inf are refused too: Studio with API access writes a real profile, and a corrupted
	-- materials or Valor field would survive the session.
	if typeof(value) ~= "number" or value <= 0 or value ~= value or value == math.huge then
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

local function consumeStudioLevers(): ()
	local combatConfig = Catalog.GetCombatConfig()
	local armoryConfig = Catalog.GetArmoryConfig()
	if combatConfig == nil or armoryConfig == nil then
		return
	end
	local debugConfig = combatConfig.debug
	consumeGrantLever(debugConfig.grantMaterialsAttribute, function(state, value)
		local material = Armory.BandMaterial(armoryConfig :: Types.ArmoryConfig, state.era)
		if material == nil then
			return
		end
		state.combat.materials[material] = (state.combat.materials[material] or 0) + value
	end)
	consumeGrantLever(debugConfig.grantValorAttribute, function(state, value)
		state.combat.valor += value
	end)
end

local ArmoryService = {}

function ArmoryService.Init(): ()
	-- Payload types are already validated by RemoteService; the casts narrow the varargs.
	RemoteService.SetHandler("RequestBuyGear", function(player: Player, slot: any)
		tryBuyGear(player, slot :: string)
	end)
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
