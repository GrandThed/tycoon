--!strict
-- Pure Armory math (docs/INTERFACES.md "C0 contracts" → "src/shared/Armory.luau"). No Roblox
-- globals of any kind — tools/sim_combat.py mirrors this file function for function — so every
-- config value and every profile field arrives as an argument.
--
-- Weapons are the only equipment: two permanent slots (melee, ranged), tier 0 = the starter
-- weapon, and the two equipped weapons together decide max HP. Tiers cost the band material and
-- unlock on the city's persisted income per second; nothing here reads or writes cash.

-- Structural copies of the shapes in Types.luau: requiring Types would need `script`, which
-- purity forbids. Keep these in lockstep with Types.luau — the old solver compares nested
-- tables invariantly, so every field must match exactly — and callers pass the Types.* tables.
type BandDef = { band: number, eraName: string, material: string }
type WeaponClassDef = {
	kind: string,
	range: number,
	arcDegrees: number?,
	chain: { number }?,
	windows: { number }?,
	comboReset: number?,
	finisherKnockback: number?,
	fire: string?,
	cooldown: number?,
	chargeSeconds: number?,
	minDamageFraction: number?,
	spreadDegrees: number?,
	pierce: number?,
}
type AbilityDef = {
	kind: string,
	cooldown: number,
	damageMult: number,
	radius: number?,
	shots: number?,
	knockback: number?,
	stunSeconds: number?,
	dashStuds: number?,
	dotSeconds: number?,
	dotTicks: number?,
	pierce: number?,
}
type WeaponStarterDef = {
	name: string,
	class: string,
	damage: number,
	hp: number,
	ability: string,
	model: string,
}
type WeaponTierDef = {
	tier: number,
	band: number,
	cost: number,
	unlockRate: number,
	name: string,
	class: string,
	damage: number,
	hp: number,
	ability: string,
	model: string,
}
type ArmorySlotDef = { starter: WeaponStarterDef, tiers: { WeaponTierDef } }
type AscensionLevelDef = {
	level: number,
	materials: { [string]: number },
	valor: number,
	damageMult: number,
	hpMult: number,
	abilityMult: number,
}
type AscensionConfig = {
	requiresRebirth: number,
	levelsPerRebirth: number,
	levels: { AscensionLevelDef },
}
type ArmoryConfig = {
	version: number,
	baseHp: number,
	power: { hpWeight: number },
	bands: { BandDef },
	classes: { [string]: WeaponClassDef },
	abilities: { [string]: AbilityDef },
	slots: { [string]: ArmorySlotDef },
	ascension: AscensionConfig,
}

-- Exact structural copy of Types.MissionRecord/CombatProfile (nested tables must match
-- field-for-field under the old solver).
type MissionRecord = { bestWave: number, bossClears: number, overdriveBest: number }
type CombatProfile = {
	materials: { [string]: number },
	valor: number,
	gear: { melee: number, ranged: number },
	ascension: { melee: number, ranged: number },
	missions: { [string]: MissionRecord },
	highestEra: number,
	expeditionSince: number,
	expeditionSeconds: number,
	stats: { kills: number, wavesCleared: number, expeditions: number, cashFromCombat: number },
}
-- The slice of PlayerState the purchase checks read; callers pass the whole state.
type ArmoryOwner = { rebirthCount: number, combat: CombatProfile }

type SlotTiers = { melee: number, ranged: number }
export type Refusal = "insufficientFunds" | "locked" | "invalid"

local NEUTRAL_MULT = 1
-- Tier 0 is the starter weapon in every slot: owned from the first join, never bought.
local STARTER_TIER = 0

local Armory = {}

-- Per-slot numbers live in a two-field record (the contract's profile shape), so a validated
-- slot string is resolved here once instead of being indexed dynamically everywhere.
local function slotValue(tiers: SlotTiers, slot: string): number?
	if slot == "melee" then
		return tiers.melee
	elseif slot == "ranged" then
		return tiers.ranged
	end
	return nil
end

local function ascensionLevel(cfg: ArmoryConfig, level: number): AscensionLevelDef?
	if level <= 0 then
		return nil
	end
	return cfg.ascension.levels[level]
end

-- tier 0 = the slot's starter weapon; any tier outside 0..#tiers is nil (no such weapon).
-- Optional return (the contract writes it non-optional): an unvalidated slot string and a tier
-- past the last one both have to be answerable without erroring inside a pure module.
function Armory.TierDef(
	cfg: ArmoryConfig,
	slot: string,
	tier: number
): (WeaponTierDef | WeaponStarterDef)?
	local slotDef = cfg.slots[slot]
	if slotDef == nil then
		return nil
	end
	if tier <= STARTER_TIER then
		return slotDef.starter
	end
	return slotDef.tiers[tier]
end

-- Ascension multiplies the equipped weapon rather than replacing it, so level 0 is a plain 1.
function Armory.WeaponDamage(
	cfg: ArmoryConfig,
	slot: string,
	tier: number,
	ascLevel: number
): number
	local def = Armory.TierDef(cfg, slot, tier)
	if def == nil then
		return 0
	end
	local level = ascensionLevel(cfg, ascLevel)
	return def.damage * (if level ~= nil then level.damageMult else NEUTRAL_MULT)
end

function Armory.WeaponHp(cfg: ArmoryConfig, slot: string, tier: number, ascLevel: number): number
	local def = Armory.TierDef(cfg, slot, tier)
	if def == nil then
		return 0
	end
	local level = ascensionLevel(cfg, ascLevel)
	return def.hp * (if level ~= nil then level.hpMult else NEUTRAL_MULT)
end

-- Weapons ARE the armour (no armour slots): the two equipped weapons plus the config floor are
-- the player's whole health pool, in the hub and in the combat place alike.
function Armory.MaxHp(cfg: ArmoryConfig, gear: SlotTiers, ascension: SlotTiers): number
	return cfg.baseHp
		+ Armory.WeaponHp(cfg, "melee", gear.melee, ascension.melee)
		+ Armory.WeaponHp(cfg, "ranged", gear.ranged, ascension.ranged)
end

-- One number for the whole loadout, compared against a mission's recommendedPower.
function Armory.GearPower(cfg: ArmoryConfig, gear: SlotTiers, ascension: SlotTiers): number
	local damage = Armory.WeaponDamage(cfg, "melee", gear.melee, ascension.melee)
		+ Armory.WeaponDamage(cfg, "ranged", gear.ranged, ascension.ranged)
	local hp = Armory.MaxHp(cfg, gear, ascension)
	return math.round(damage + hp * cfg.power.hpWeight)
end

-- The tier a RequestBuyGear would buy; nil past the last tier or for an unknown slot.
function Armory.NextTier(cfg: ArmoryConfig, gear: SlotTiers, slot: string): number?
	local slotDef = cfg.slots[slot]
	local current = slotValue(gear, slot)
	if slotDef == nil or current == nil then
		return nil
	end
	local nextTier = current + 1
	if nextTier > #slotDef.tiers then
		return nil
	end
	return nextTier
end

-- Which material a band charges in. Bands are era-indexed in Armory.json, so this also answers
-- "the material of the era the player is in" for the Studio grant lever.
function Armory.BandMaterial(cfg: ArmoryConfig, band: number): string?
	for _, bandDef in cfg.bands do
		if bandDef.band == band then
			return bandDef.material
		end
	end
	return nil
end

-- ("", 0) for a tier that does not exist: callers gate on NextTier first, and a pure module
-- must not error.
function Armory.TierCost(cfg: ArmoryConfig, slot: string, tier: number): (string, number)
	local slotDef = cfg.slots[slot]
	if slotDef == nil then
		return "", 0
	end
	local tierDef = slotDef.tiers[tier]
	if tierDef == nil then
		return "", 0
	end
	return Armory.BandMaterial(cfg, tierDef.band) or "", tierDef.cost
end

function Armory.TierUnlockRate(cfg: ArmoryConfig, slot: string, tier: number): number
	local slotDef = cfg.slots[slot]
	if slotDef == nil then
		return 0
	end
	local tierDef = slotDef.tiers[tier]
	if tierDef == nil then
		return 0
	end
	return tierDef.unlockRate
end

-- Frozen chain, mirrored by the server handler: slot exists → a next tier exists → the city
-- earns enough per second → the materials are in the wallet. incomePerSecond is the PERSISTED
-- rate (EconomyService.GetPersistedIncomePerSecond), never a client-supplied number.
function Armory.CanBuy(
	cfg: ArmoryConfig,
	state: ArmoryOwner,
	slot: string,
	incomePerSecond: number
): (boolean, Refusal?)
	local tier = Armory.NextTier(cfg, state.combat.gear, slot)
	if tier == nil then
		return false, "invalid"
	end
	if incomePerSecond < Armory.TierUnlockRate(cfg, slot, tier) then
		return false, "locked"
	end
	local material, amount = Armory.TierCost(cfg, slot, tier)
	if (state.combat.materials[material] or 0) < amount then
		return false, "insufficientFunds"
	end
	return true, nil
end

-- A fresh table per call: callers subtract from the profile with it and must never be able to
-- mutate Armory.json through the returned materials map.
function Armory.AscensionCost(
	cfg: ArmoryConfig,
	level: number
): { materials: { [string]: number }, valor: number }?
	local levelDef = ascensionLevel(cfg, level)
	if levelDef == nil then
		return nil
	end
	return { materials = table.clone(levelDef.materials), valor = levelDef.valor }
end

-- Ascension is the Rebirth spike: nothing below requiresRebirth, then levelsPerRebirth more
-- levels per lap, never past the configured list.
function Armory.AscensionCap(cfg: ArmoryConfig, rebirthCount: number): number
	local ascension = cfg.ascension
	if rebirthCount < ascension.requiresRebirth then
		return 0
	end
	local laps = rebirthCount - ascension.requiresRebirth + 1
	return math.min(#ascension.levels, laps * ascension.levelsPerRebirth)
end

function Armory.CanAscend(cfg: ArmoryConfig, state: ArmoryOwner, slot: string): (boolean, Refusal?)
	local current = slotValue(state.combat.ascension, slot)
	if cfg.slots[slot] == nil or current == nil then
		return false, "invalid"
	end
	local level = current + 1
	if level > Armory.AscensionCap(cfg, state.rebirthCount) then
		return false, "locked"
	end
	local cost = Armory.AscensionCost(cfg, level)
	if cost == nil then
		return false, "locked"
	end
	if state.combat.valor < cost.valor then
		return false, "insufficientFunds"
	end
	for name, amount in cost.materials do
		if (state.combat.materials[name] or 0) < amount then
			return false, "insufficientFunds"
		end
	end
	return true, nil
end

-- nil for an unknown key so a missing class/ability degrades to "no weapon behaviour" instead
-- of erroring (spec: missing content is a placeholder, never an error).
function Armory.ClassDef(cfg: ArmoryConfig, class: string): WeaponClassDef?
	return cfg.classes[class]
end

function Armory.AbilityDef(cfg: ArmoryConfig, key: string): AbilityDef?
	return cfg.abilities[key]
end

return Armory
