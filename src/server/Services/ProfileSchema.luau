--!strict
-- The persisted profile schema, split out of DataService at C0 so both places (hub and
-- Expeditions) provably share one store name, one key prefix, one template and one migration
-- chain: they require the same module from the same Services folder, so a divergence is
-- impossible rather than merely unlikely (docs/INTERFACES.md "Profile schema v5").
--
-- Infrastructure constants, deliberately in code: Config/*.json is for gameplay balance, and a
-- store name or key prefix that could be edited per-place is a data-loss bug, not a tunable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local SCHEMA_VERSION = 8
local STORE_NAME = "PlayerData"
local PROFILE_KEY_PREFIX = "p_"

-- Template = schema v8, the exact PlayerState shape in Types.luau. lastSeen = 0 marks a
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
		abilities = {},
		secrets = {},
		families = {},
		shortcuts = {},
		-- L3-7: no family id here. The starters come from ProvingGrounds.json `loadout` when the
		-- loadout is read (Unlocks.LoadoutOf), so Reconcile can never pin a profile to one.
		tiers = {},
		loadout = { variants = {} },
		stars = {},
	},
}

-- L3-8: a build without Armory.json converts a v7 profile without its refund; said once, not once
-- per profile.
local warnedNoArmory = false

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
	-- L2-1: the dungeon place's unlocks (bought abilities, opened secrets, found families and
	-- shortcuts). Reconcile runs first and usually fills them already; each is added only when
	-- still nil, always as a fresh table (a template table would be shared by every profile).
	-- v6 code that loads a v7 profile keeps them: Reconcile only fills, and runMigrations leaves
	-- a newer profile untouched.
	[6] = function(state: Types.PlayerState): ()
		local combat = state.combat
		if combat.abilities == nil then
			combat.abilities = {}
		end
		if combat.secrets == nil then
			combat.secrets = {}
		end
		if combat.families == nil then
			combat.families = {}
		end
		if combat.shortcuts == nil then
			combat.shortcuts = {}
		end
	end,
	-- L3-7, L3-8: a tier belongs to a weapon family now. The three new fields are added only when
	-- still nil, each a fresh table (Reconcile usually filled them already). Then the slot tiers
	-- bought before v8 are paid back at the FROZEN legacy prices (Armory.LegacyRefund; never the
	-- live `slots`), and `gear` is left as it is: live v7 code still reads it, new code never does.
	-- The starters start at their windows' start because `tiers` holds nothing for them.
	-- Unlike step 6 this one is NOT safe to run twice (it would pay twice): the version stamp is
	-- what runs it once. v7 code that loads a v8 profile keeps all three fields: Reconcile only
	-- fills, and runMigrations leaves a newer profile untouched.
	[7] = function(state: Types.PlayerState): ()
		local combat = state.combat
		if combat.tiers == nil then
			combat.tiers = {}
		end
		local loadout = combat.loadout
		if loadout == nil then
			combat.loadout = { variants = {} }
		elseif type(loadout.variants) ~= "table" then
			loadout.variants = {}
		end
		if combat.stars == nil then
			combat.stars = {}
		end
		local armoryConfig = Catalog.GetArmoryConfig()
		if armoryConfig == nil then
			if not warnedNoArmory then
				warnedNoArmory = true
				warn(
					"[ProfileSchema] no Armory.json: v7 profiles reach v8 without the slot-tier refund"
				)
			end
			return
		end
		for material, amount in Armory.LegacyRefund(armoryConfig, combat.gear) do
			combat.materials[material] = (combat.materials[material] or 0) + amount
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
