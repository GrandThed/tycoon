--!strict
-- The Legacy shop purchase path (docs/INTERFACES.md "M6 contracts — Legacy shop"). Legacy is
-- earned currency, so there is no Robux anywhere near this file: one intent (RequestBuyPerk),
-- one validation chain, one atomic mutation. Perk EFFECTS live where they apply (Economy
-- helpers read from EconomyService/PlotService); this service only sells tiers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

local function sendFailure(
	player: Player,
	perkId: string,
	reason: "insufficientFunds" | "locked" | "invalid"
): ()
	local result: Types.ActionResult =
		{ action = "buyPerk", slotId = perkId, ok = false, reason = reason }
	RemoteService.FireClient(player, "ActionResult", result)
end

-- Frozen chain: state loaded → perk exists → next tier exists (tiers are bought strictly in
-- order, so a repeat of an owned tier is "locked") → spendable Legacy covers the cost. No
-- yields between validation and mutation, so two in-flight requests cannot both pass.
local function tryBuyPerk(player: Player, perkId: string): ()
	local state = DataService.GetState(player)
	if state == nil then
		sendFailure(player, perkId, "invalid")
		return
	end
	local shopConfig = Catalog.GetLegacyShopConfig()
	if Catalog.GetPerkDef(perkId) == nil then
		sendFailure(player, perkId, "locked")
		return
	end
	local tierDef, tier = Economy.NextPerkTier(shopConfig, state.legacyShop, perkId)
	if tierDef == nil then
		sendFailure(player, perkId, "locked")
		return
	end
	if Economy.LegacySpendable(state) < tierDef.cost then
		sendFailure(player, perkId, "insufficientFunds")
		return
	end

	state.legacyShop.perks[perkId] = tier
	state.legacyShop.spent += tierDef.cost
	-- Founder's/Good Neighbours move the persisted rate too (permanent perks carry offline).
	EconomyService.RefreshPersistedRate(player)
	EconomyService.MarkDirty(player, { income = true, legacyShop = true })
	-- Cosmetics and the world-side effects (golden roads, monument glow, sign, tag) at once.
	PlotService.RefreshCosmetics(player)
	local fx: Types.FxEvent = { kind = "perkBought", perkId = perkId, tier = tier }
	RemoteService.FireClient(player, "FxEvent", fx)
	AnalyticsService.LogLegacySink(
		player,
		tierDef.cost,
		Economy.LegacySpendable(state),
		`perk:{perkId}:{tier}`
	)
end

local LegacyShopService = {}

function LegacyShopService.Init(): ()
	-- Payload type is already validated by RemoteService; the cast narrows the vararg.
	RemoteService.SetHandler("RequestBuyPerk", function(player: Player, perkId: any)
		tryBuyPerk(player, perkId :: string)
	end)
end

function LegacyShopService.Start(): () end

return LegacyShopService
