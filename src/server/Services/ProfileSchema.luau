--!strict
-- The persisted profile schema, split out of DataService at C0 so both places (hub and
-- Expeditions) provably share one store name, one key prefix, one template and one migration
-- chain: they require the same module from the same Services folder, so a divergence is
-- impossible rather than merely unlikely (docs/INTERFACES.md "Profile schema v5").
--
-- Infrastructure constants, deliberately in code: Config/*.json is for gameplay balance, and a
-- store name or key prefix that could be edited per-place is a data-loss bug, not a tunable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local SCHEMA_VERSION = 6
local STORE_NAME = "PlayerData"
local PROFILE_KEY_PREFIX = "p_"

-- Template = schema v6, the exact PlayerState shape in Types.luau. lastSeen = 0 marks a
-- first-ever join (no offline grant, no welcome-back card).
local PROFILE_TEMPLATE: Types.PlayerState = {
	version = SCHEMA_VERSION,
	cash = 0,
	era = 1,
	rebirthCount = 0,
	legacy = 0,
	slots = {},
	passes = {},
	processedReceipts = {},
	lastSeen = 0,
	incomeAtSave = 0,
	stats = { totalCashAllTime = 0, erasCompleted = 0, playtimeSeconds = 0 },
	settings = { music = true, sfx = true, vipSkins = true, cityDetail = true },
	pendingDoubleOfflineAmount = 0,
	legacyShop = { spent = 0, perks = {} },
	combat = {
		materials = {},
		valor = 0,
		gear = { melee = 0, ranged = 0 },
		ascension = { melee = 0, ranged = 0 },
		missions = {},
		highestEra = 1,
		expeditionSince = 0,
		expeditionSeconds = 0,
		stats = { kills = 0, wavesCleared = 0, expeditions = 0, cashFromCombat = 0 },
	},
}

-- Migrations[n](state) upgrades schema n → n+1; the runner bumps state.version afterwards.
-- Additive and idempotent. Reconcile would also fill the new fields, but the version stamp must
-- advance so an old profile is provably upgraded once rather than reconciled forever.
local Migrations: { [number]: (state: Types.PlayerState) -> () } = {
	[1] = function(state: Types.PlayerState): ()
		if state.pendingDoubleOfflineAmount == nil then
			state.pendingDoubleOfflineAmount = 0
		end
	end,
	-- M6: the Legacy shop state (docs/INTERFACES.md "Profile schema v3").
	[2] = function(state: Types.PlayerState): ()
		if state.legacyShop == nil then
			state.legacyShop = { spent = 0, perks = {} }
		end
	end,
	-- VIP skins toggle (docs/INTERFACES.md "Amendment — VIP skins toggle"): default on, so an
	-- existing VIP owner keeps the look they already had.
	[3] = function(state: Types.PlayerState): ()
		if state.settings.vipSkins == nil then
			state.settings.vipSkins = true
		end
	end,
	-- C0: the Expeditions profile. A fresh table (never PROFILE_TEMPLATE.combat, which every
	-- profile would then alias), and highestEra seeded from the city the player already has so
	-- a veteran does not have to re-reach their era to unlock its mission.
	[4] = function(state: Types.PlayerState): ()
		if state.combat == nil then
			state.combat = {
				materials = {},
				valor = 0,
				gear = { melee = 0, ranged = 0 },
				ascension = { melee = 0, ranged = 0 },
				missions = {},
				highestEra = math.max(1, state.era),
				expeditionSince = 0,
				expeditionSeconds = 0,
				stats = { kills = 0, wavesCleared = 0, expeditions = 0, cashFromCombat = 0 },
			}
			return
		end
		-- ProfileStore reconciles BEFORE the migrations run, so an upgrading profile usually
		-- arrives here with `combat` already filled from the template (highestEra = 1). Seeding
		-- the era on the existing table is what actually unlocks a veteran's missions, and it is
		-- monotonic, so re-running it can never lower the value.
		state.combat.highestEra = math.max(state.combat.highestEra, state.era, 1)
	end,
	-- M9 wave 2b: the cityDetail dressing toggle (docs/INTERFACES.md "Wave 2 — cityDetail
	-- setting"). Default on, so an existing city keeps the full dressing it was designed with.
	[5] = function(state: Types.PlayerState): ()
		if state.settings.cityDetail == nil then
			state.settings.cityDetail = true
		end
	end,
}

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	STORE_NAME = STORE_NAME,
	PROFILE_KEY_PREFIX = PROFILE_KEY_PREFIX,
	PROFILE_TEMPLATE = PROFILE_TEMPLATE,
	Migrations = Migrations,
}
