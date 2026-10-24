--!strict
-- Pure Armory math (docs/INTERFACES.md "C0 contracts", docs/prompts/l3-w1-contract.md L3-1 to
-- L3-8). No Roblox globals of any kind — tools/sim_combat.py mirrors this file function for
-- function, two aside — so every config value and every profile field arrives as an argument.
-- Those two have no Python mirror, deliberately (the L3 W1 fix round 2's F4), because the
-- simulators need only their parts: StrikeTier is TierOf (mirrored) under a Studio session
-- override no simulator plays; HeldFamily is the saved loadout's slot rule, and every simulated
-- course names the pair it holds (sim_range.held_pair). tools/crowd_harness tests both
-- (tests_l3.luau), and tools/check_stage_mirror.py lists them as unmirrored (ARMORY_UNMIRRORED).
-- L4 W3 deleted GearPower, SavedPower and HeldTiers with the Gear Power readout, their last
-- reader (L4B-5).
--
-- L3: a tier belongs to a weapon FAMILY. Every family climbs one ladder (`ladder`) inside its own
-- window (`windows`); its tier scales its hits (Multiplier) and, for the two held families, the
-- player's health (MaxHp). A tier is paid with what its band's level drops, and a band's top
-- tier also needs that level's Hard star. Nothing here reads or writes cash.
-- The Ascension forge stays for the hub (ArmoryService). The C1 slot ladder (`slots`, `classes`,
-- `abilities`, `bands`, `partyEffects`) went in L4 W1b with its last readers.

-- Structural copies of the shapes in Types.luau: requiring Types would need `script`, which
-- purity forbids. Keep these in lockstep with Types.luau (and Combat.luau's copies) — the old
-- solver compares nested tables invariantly, so every field must match exactly — and callers
-- pass the Types.* tables.
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
type ArmoryLadderBand = { levelId: string, material: string }
type ArmoryLadder = {
	damage: { number },
	hp: { melee: { number }, ranged: { number } },
	rangeHp: number,
	bandSize: number,
	bands: { ArmoryLadderBand },
	costs: { number },
	starDifficulty: string,
	starAlso: { string }?,
}
type ArmoryWindow = { start: number, top: number }
type ArmoryLegacyCost = { material: string, amount: number }
type ArmoryLegacy = { gearCosts: { ArmoryLegacyCost } }
type ArmoryConfig = {
	version: number,
	baseHp: number,
	ascension: AscensionConfig,
	ladder: ArmoryLadder?,
	windows: { [string]: ArmoryWindow }?,
	legacy: ArmoryLegacy?,
}

-- Exact structural copy of Types.MissionRecord/SavedLoadout/CombatProfile (nested tables must
-- match field-for-field under the old solver).
type MissionRecord = { bestWave: number, bossClears: number, overdriveBest: number }
type SavedLoadout = { melee: string?, ranged: string?, variants: { [string]: string } }
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
	abilities: { [string]: boolean }?,
	secrets: { [string]: { [string]: boolean } }?,
	families: { [string]: boolean }?,
	shortcuts: { [string]: { [string]: boolean } }?,
	tiers: { [string]: number }?,
	loadout: SavedLoadout?,
	stars: { [string]: { [string]: boolean } }?,
}
-- The slice of PlayerState the Ascension checks read; callers pass the whole state.
type ArmoryOwner = { rebirthCount: number, combat: CombatProfile }

type SlotTiers = { melee: number, ranged: number }
-- ProvingGrounds.json `loadout`: each slot's starter family.
type StarterPair = { melee: string, ranged: string }
export type Refusal = "insufficientFunds" | "locked" | "invalid"
-- L3-5: why an upgrade is refused, tested in this order (UpgradeVerdict). "unavailable" (no
-- profile, no Armory config) is the caller's.
export type UpgradeRefusal =
	"invalid"
	| "locked"
	| "peak"
	| "busy"
	| "notBuilt"
	| "needsStar"
	| "insufficientFunds"

local NEUTRAL_MULT = 1

local Armory = {}

-- A number that arithmetic can trust: not NaN, not infinite. Config and profiles are decoded
-- data, so every tier rule checks what it reads instead of erroring inside a pure module.
local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function whole(value: any): boolean
	return finite(value) and value % 1 == 0
end

-- The ladder when it holds a damage list; nil degrades every tier rule to "T1, never upgraded".
local function ladderOf(cfg: ArmoryConfig): ArmoryLadder?
	local ladder: any = cfg.ladder
	if type(ladder) ~= "table" or type(ladder.damage) ~= "table" then
		return nil
	end
	return ladder
end

-- A whole tier held inside 1..size (size >= 1). A tier that is not a whole number never gets
-- here: each rule reads one as sim_combat does (the start, x1, 0 HP, nothing back).
local function clampTier(tier: number, size: number): number
	return math.min(math.max(tier, 1), size)
end

local function ascensionLevel(cfg: ArmoryConfig, level: number): AscensionLevelDef?
	if level <= 0 then
		return nil
	end
	return cfg.ascension.levels[level]
end

-- ascLevel's multiplier on an attack (damageMult) or an ability (abilityMult); 1 at level 0.
local function ascensionMult(cfg: ArmoryConfig, ascLevel: number, ability: boolean): number
	local level = ascensionLevel(cfg, ascLevel)
	if level == nil then
		return NEUTRAL_MULT
	end
	return if ability then level.abilityMult else level.damageMult
end

-- ---------------------------------------------------------------------------------------------
-- L3: the ladder and the windows
-- ---------------------------------------------------------------------------------------------

-- How many tiers the ladder has; 0 without a ladder.
function Armory.LadderSize(cfg: ArmoryConfig): number
	local ladder = ladderOf(cfg)
	return if ladder ~= nil then #ladder.damage else 0
end

-- A family's window, its start and top held inside 1..LadderSize. nil, nil for a family with no
-- window, a malformed one (not whole numbers, or a start above its top), or no ladder.
function Armory.Window(cfg: ArmoryConfig, family: string): (number?, number?)
	local size = Armory.LadderSize(cfg)
	local windows: any = cfg.windows
	local window: any = if type(windows) == "table" then windows[family] else nil
	if
		size == 0
		or type(window) ~= "table"
		or not whole(window.start)
		or not whole(window.top)
		or window.start > window.top
	then
		return nil, nil
	end
	return clampTier(window.start, size), clampTier(window.top, size)
end

-- L3-3: the tier a family fights at: its saved tier held inside its window, else its start, so a
-- window changed after a save never strands a profile. A saved tier that is not a whole number
-- reads the start. 1 for a family with no window.
function Armory.TierOf(cfg: ArmoryConfig, combat: CombatProfile?, family: string): number
	local start, top = Armory.Window(cfg, family)
	if start == nil or top == nil then
		return 1
	end
	local tiers: any = if combat ~= nil then combat.tiers else nil
	local saved: any = if type(tiers) == "table" then tiers[family] else nil
	if not whole(saved) then
		return start
	end
	return math.min(math.max(saved, start), top)
end

-- The fix round's R3: the tier a family strikes at, and the tier the bar reads for a held one. A
-- Studio session override's tier for the family's slot is held inside the family's OWN window, so
-- a T1 preset never fields a weapon below its window (2-s1); without an override, TierOf. An
-- override that is not a whole number reads the window's start, as a saved tier does, and a family
-- with no window strikes at T1 whatever the override says.
function Armory.StrikeTier(
	cfg: ArmoryConfig,
	combat: CombatProfile?,
	family: string,
	overrideTier: number?
): number
	if overrideTier == nil then
		return Armory.TierOf(cfg, combat, family)
	end
	local first, last = Armory.Window(cfg, family)
	if first == nil or last == nil then
		return 1
	end
	if not whole(overrideTier) then
		return first
	end
	return math.min(math.max(overrideTier, first), last)
end

-- L3-10's slot rule, in the one place its readers take it from (Unlocks.LoadoutOf): the family
-- the saved loadout holds in `slot` when it is a family of `weapons`, fills that slot and is owned
-- (a starter, or one the profile's `families` holds true for); otherwise the slot's starter.
-- `weapons` is ProvingGrounds.json `weapons`, of which only each entry's `slot` is read, and
-- `starters` its `loadout`. "" for a slot other than "melee" and "ranged".
function Armory.HeldFamily(
	combat: CombatProfile?,
	weapons: any,
	starters: StarterPair,
	slot: string
): string
	local starter = if slot == "melee"
		then starters.melee
		elseif slot == "ranged" then starters.ranged
		else nil
	if starter == nil then
		return ""
	end
	local saved: any = if combat ~= nil then combat.loadout else nil
	local family: any = if type(saved) == "table" then saved[slot] else nil
	local def: any = if type(family) == "string" and type(weapons) == "table"
		then weapons[family]
		else nil
	if type(def) ~= "table" or def.slot ~= slot then
		return starter
	end
	local families: any = if combat ~= nil then combat.families else nil
	local isStarter = family ~= "" and (family == starters.melee or family == starters.ranged)
	local found = type(families) == "table" and families[family] == true
	return if isStarter or found then family else starter
end

-- L3-1: what a tier multiplies the range's tier-1 numbers by (the tier held inside the ladder).
-- 1 without a ladder, for a tier that is not a whole number, or for an entry that is not a number
-- above 0: those degrade to the range's numbers, never to hits that remove no HP.
function Armory.Multiplier(cfg: ArmoryConfig, tier: number): number
	local ladder = ladderOf(cfg)
	if ladder == nil or #ladder.damage == 0 or not whole(tier) then
		return NEUTRAL_MULT
	end
	local value: any = ladder.damage[clampTier(tier, #ladder.damage)]
	return if finite(value) and value > 0 then value else NEUTRAL_MULT
end

-- P5 ruling 8, L3-6: a hit's HP loss scales by the striking family's tier and its slot's
-- Ascension level (abilityMult for an ability, damageMult for an attack). The heavy, plate,
-- interrupt and armour rules read the unscaled amount (CrowdService).
function Armory.DamageScale(
	cfg: ArmoryConfig,
	tier: number,
	ascLevel: number,
	ability: boolean
): number
	return Armory.Multiplier(cfg, tier) * ascensionMult(cfg, ascLevel, ability)
end

-- The health list of a slot; nil for any word but "melee" and "ranged".
local function hpList(ladder: ArmoryLadder, slot: string): { number }?
	local hp: any = ladder.hp
	if type(hp) ~= "table" then
		return nil
	end
	local list: any = if slot == "melee"
		then hp.melee
		elseif slot == "ranged" then hp.ranged
		else nil
	return if type(list) == "table" then list else nil
end

-- L3-2: the health a family of `slot` adds at `tier`, times the slot's Ascension hpMult. 0 for an
-- unknown slot, no ladder, a tier that is not a whole number, or an entry that is not a number of
-- at least 0.
function Armory.WeaponHp(cfg: ArmoryConfig, slot: string, tier: number, ascLevel: number): number
	local ladder = ladderOf(cfg)
	local list = if ladder ~= nil then hpList(ladder, slot) else nil
	if list == nil or #list == 0 or not whole(tier) then
		return 0
	end
	local value: any = list[clampTier(tier, #list)]
	if not finite(value) or value < 0 then
		return 0
	end
	local level = ascensionLevel(cfg, ascLevel)
	return value * (if level ~= nil then level.hpMult else NEUTRAL_MULT)
end

-- Weapons ARE the armour (no armour slots): the two held families plus the config floor are the
-- player's whole health pool, in the hub and in the combat place alike.
function Armory.MaxHp(cfg: ArmoryConfig, tiers: SlotTiers, ascension: SlotTiers): number
	return cfg.baseHp
		+ Armory.WeaponHp(cfg, "melee", tiers.melee, ascension.melee)
		+ Armory.WeaponHp(cfg, "ranged", tiers.ranged, ascension.ranged)
end

-- L3-2: the range's own body, whatever the profile holds (baseHp without a ladder or a sound
-- rangeHp).
function Armory.RangeHp(cfg: ArmoryConfig): number
	local ladder = ladderOf(cfg)
	local value: any = if ladder ~= nil then ladder.rangeHp else nil
	return if finite(value) and value > 0 then value else cfg.baseHp
end

-- L3-4: a tier's band (1 = the first level's) and its position inside the band (1..bandSize).
-- 0, 0 for a tier outside 1..LadderSize or not whole, or a ladder whose bandSize is not a whole
-- number above 0.
function Armory.BandOf(cfg: ArmoryConfig, tier: number): (number, number)
	local ladder = ladderOf(cfg)
	if ladder == nil then
		return 0, 0
	end
	local bandSize: any = ladder.bandSize
	if
		not whole(bandSize)
		or bandSize <= 0
		or not whole(tier)
		or tier < 1
		or tier > #ladder.damage
	then
		return 0, 0
	end
	return math.ceil(tier / bandSize), (tier - 1) % bandSize + 1
end

-- The band entry a tier is paid in, when it names a level and a material; and its position.
local function bandAt(cfg: ArmoryConfig, tier: number): (ArmoryLadderBand?, number)
	local band, position = Armory.BandOf(cfg, tier)
	local ladder = ladderOf(cfg)
	local bands: any = if ladder ~= nil then ladder.bands else nil
	local def: any = if band > 0 and type(bands) == "table" then bands[band] else nil
	if
		type(def) ~= "table"
		or type(def.levelId) ~= "string"
		or def.levelId == ""
		or type(def.material) ~= "string"
		or def.material == ""
	then
		return nil, position
	end
	return def, position
end

-- The tier an upgrade would buy: TierOf + 1 while it stays inside the window; nil at the top or
-- for a family with no window.
function Armory.NextTier(cfg: ArmoryConfig, combat: CombatProfile?, family: string): number?
	local _, top = Armory.Window(cfg, family)
	if top == nil then
		return nil
	end
	local nextTier = Armory.TierOf(cfg, combat, family) + 1
	return if nextTier <= top then nextTier else nil
end

-- L3-4: (the band's material, costs[position]). ("", 0) for a tier outside the ladder, a band
-- entry that is missing or names no level or material, or a cost that is not a number of at
-- least 0: such a tier can never be bought (UpgradeVerdict says notBuilt).
function Armory.TierCost(cfg: ArmoryConfig, tier: number): (string, number)
	local def, position = bandAt(cfg, tier)
	local ladder = ladderOf(cfg)
	local costs: any = if ladder ~= nil then ladder.costs else nil
	local cost: any = if def ~= nil and type(costs) == "table" then costs[position] else nil
	if def == nil or not finite(cost) or cost < 0 then
		return "", 0
	end
	return def.material, cost
end

-- L3-19's next line: a per-hit damage at `tier` (rounded) and the health a family of `slot`
-- adds there (no Ascension).
function Armory.Preview(
	cfg: ArmoryConfig,
	slot: string,
	tier: number,
	baseDamage: number
): (number, number)
	return math.round(baseDamage * Armory.Multiplier(cfg, tier)),
		Armory.WeaponHp(cfg, slot, tier, 0)
end

local function starHeld(combat: CombatProfile, levelId: string, difficulty: any): boolean
	local stars: any = combat.stars
	local row: any = if type(stars) == "table" then stars[levelId] else nil
	return type(difficulty) == "string" and type(row) == "table" and row[difficulty] == true
end

-- The fix round's R1: does the profile hold the trophy a band top of `levelId` needs? That level's
-- `starDifficulty` star, or the star of any difficulty `starAlso` lists: a Brutal clear opens T4 as
-- a Hard one does (the map still stars only the difficulty cleared). False without a ladder or a
-- profile; a `starAlso` that is not a list adds nothing. The server's verdict and the screen's
-- lines both read it.
function Armory.StarHeld(cfg: ArmoryConfig, combat: CombatProfile?, levelId: string): boolean
	local ladder = ladderOf(cfg)
	if ladder == nil or combat == nil then
		return false
	end
	if starHeld(combat, levelId, ladder.starDifficulty) then
		return true
	end
	local also: any = ladder.starAlso
	if type(also) ~= "table" then
		return false
	end
	for index = 1, #also do
		if starHeld(combat, levelId, also[index]) then
			return true
		end
	end
	return false
end

-- L3-5: may this family go up a tier now? nil = yes; otherwise the first refusal that applies,
-- in this order: no window (or no ladder); not owned; at its top; not allowed here (gateOpen =
-- the combat place's MayLeave, true in the hub); the next tier's band level is not built (no
-- level file for it in `built`, or the tier has no price); a band's top position without that
-- level's trophy (StarHeld); the band material short. The buttons colour from this and the
-- server decides with it.
function Armory.UpgradeVerdict(
	cfg: ArmoryConfig,
	combat: CombatProfile,
	family: string,
	owned: boolean,
	gateOpen: boolean,
	built: { [string]: boolean }
): UpgradeRefusal?
	local start = Armory.Window(cfg, family)
	if start == nil then
		return "invalid"
	end
	if not owned then
		return "locked"
	end
	local nextTier = Armory.NextTier(cfg, combat, family)
	if nextTier == nil then
		return "peak"
	end
	if not gateOpen then
		return "busy"
	end
	local ladder = ladderOf(cfg)
	local band, position = bandAt(cfg, nextTier)
	local material, cost = Armory.TierCost(cfg, nextTier)
	if ladder == nil or band == nil or built[band.levelId] ~= true or material == "" then
		return "notBuilt"
	end
	if position == ladder.bandSize and not Armory.StarHeld(cfg, combat, band.levelId) then
		return "needsStar"
	end
	local have: any = combat.materials[material]
	if not (finite(have) and have >= cost) then
		return "insufficientFunds"
	end
	return nil
end

-- L3-13 step 3: the upgrade, decided and written in one call with no yield. nil = bought: the
-- tier's cost is taken from `combat.materials` (never below 0) and `combat.tiers[family]` is the
-- next tier (the table made when the profile has none). Otherwise UpgradeVerdict's refusal, and
-- the profile is untouched.
function Armory.Upgrade(
	cfg: ArmoryConfig,
	combat: CombatProfile,
	family: string,
	owned: boolean,
	gateOpen: boolean,
	built: { [string]: boolean }
): UpgradeRefusal?
	-- Annotated: an unannotated local would widen the refusal to `string`.
	local verdict: UpgradeRefusal? =
		Armory.UpgradeVerdict(cfg, combat, family, owned, gateOpen, built)
	if verdict ~= nil then
		return verdict
	end
	local nextTier = Armory.NextTier(cfg, combat, family)
	if nextTier == nil then
		return "peak"
	end
	local material, cost = Armory.TierCost(cfg, nextTier)
	combat.materials[material] = math.max(0, (combat.materials[material] or 0) - cost)
	local tiers = combat.tiers or {}
	combat.tiers = tiers
	tiers[family] = nextTier
	return nil
end

-- L3-28's setTier lever (Studio only, both places): writes `tier` held inside the family's window
-- (owning it is not required) and answers the tier written. nil, and nothing written, for a
-- family with no window or a tier that is not a finite number.
function Armory.SetTier(
	cfg: ArmoryConfig,
	combat: CombatProfile,
	family: string,
	tier: number
): number?
	local start, top = Armory.Window(cfg, family)
	if start == nil or top == nil or not finite(tier) then
		return nil
	end
	local held = math.min(math.max(math.floor(tier), start), top)
	local tiers = combat.tiers or {}
	combat.tiers = tiers
	tiers[family] = held
	return held
end

-- L3-28: the ladder's bands whose level is built (has a level file), in band order, each level
-- and each material once: the Studio grant pays those materials and grantStar "*" stars those
-- levels. Empty without a ladder.
function Armory.BuiltBands(
	cfg: ArmoryConfig,
	built: { [string]: boolean }
): ({ string }, { string })
	local levels: { string } = {}
	local materials: { string } = {}
	local ladder = ladderOf(cfg)
	local bands: any = if ladder ~= nil then ladder.bands else nil
	if type(bands) ~= "table" then
		return levels, materials
	end
	for _, def: any in bands do
		if
			type(def) == "table"
			and type(def.levelId) == "string"
			and type(def.material) == "string"
			and def.material ~= ""
			and built[def.levelId] == true
		then
			if table.find(levels, def.levelId) == nil then
				table.insert(levels, def.levelId)
			end
			if table.find(materials, def.material) == nil then
				table.insert(materials, def.material)
			end
		end
	end
	return levels, materials
end

-- L3-8: what the v7 -> v8 step gives back for the slot tiers a profile bought before tiers moved
-- to families, at the FROZEN prices in `legacy.gearCosts` (`slots` went in L4 W1b): for
-- each slot, entries 1 .. min(gear[slot], #gearCosts). A fresh table, keyed by material. Empty
-- without a legacy list; a slot tier that is not a whole number, an entry that names no material
-- or an amount that is not a number of at least 0 adds nothing.
function Armory.LegacyRefund(cfg: ArmoryConfig, gear: SlotTiers): { [string]: number }
	local refund: { [string]: number } = {}
	local legacy: any = cfg.legacy
	local list: any = if type(legacy) == "table" then legacy.gearCosts else nil
	if type(list) ~= "table" or type(gear) ~= "table" then
		return refund
	end
	for _, owned: any in { gear.melee, gear.ranged } do
		if not whole(owned) then
			continue
		end
		for t = 1, math.min(owned, #list) do
			local entry: any = list[t]
			if
				type(entry) == "table"
				and type(entry.material) == "string"
				and entry.material ~= ""
				and finite(entry.amount)
				and entry.amount >= 0
			then
				refund[entry.material] = (refund[entry.material] or 0) + entry.amount
			end
		end
	end
	return refund
end

-- A list (keys 1..n, nothing else) of non-empty strings; an empty list is one.
local function namesList(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for _, name in value do
		count += 1
		if type(name) ~= "string" or name == "" then
			return false
		end
	end
	return count == #value
end

-- L3-5: the validator, warned at Init in both places: one line per thing that makes a tier rule
-- degrade. `families` are the weapon family ids (ProvingGrounds.json `weapons`); each needs a
-- window inside the ladder, and every window must name one of them. An empty list = sound.
function Armory.Problems(cfg: ArmoryConfig, families: { string }): { string }
	local problems: { string } = {}
	local function problem(text: string): ()
		table.insert(problems, `Armory.json {text}`)
	end
	local ladder: any = cfg.ladder
	local size = Armory.LadderSize(cfg)
	if type(ladder) ~= "table" then
		problem("has no ladder: every weapon fights at T1 and none can be upgraded")
	elseif size == 0 then
		problem("ladder.damage is not a list of numbers: every weapon fights at T1")
	else
		for t = 1, size do
			local value: any = ladder.damage[t]
			local before: any = ladder.damage[t - 1]
			if not finite(value) or value <= 0 then
				problem(`ladder.damage[{t}] is {tostring(value)}, not a number above 0`)
			elseif t > 1 and finite(before) and value <= before then
				problem(
					`ladder.damage[{t}] ({value}) does not rise above ladder.damage[{t - 1}] ({before})`
				)
			end
		end
		local hp: any = ladder.hp
		for _, slot in { "melee", "ranged" } do
			local list: any = if type(hp) == "table" then hp[slot] else nil
			if type(list) ~= "table" or #list ~= size then
				problem(`ladder.hp.{slot} is not a list of {size} numbers`)
				continue
			end
			for t = 1, size do
				local value: any = list[t]
				local before: any = list[t - 1]
				if not finite(value) or value < 0 then
					problem(
						`ladder.hp.{slot}[{t}] is {tostring(value)}, not a number of at least 0`
					)
				elseif t > 1 and finite(before) and value < before then
					problem(
						`ladder.hp.{slot}[{t}] ({value}) falls below ladder.hp.{slot}[{t - 1}] ({before})`
					)
				end
			end
		end
		local melee: any = if type(hp) == "table" then hp.melee else nil
		local ranged: any = if type(hp) == "table" then hp.ranged else nil
		if type(melee) == "table" and type(ranged) == "table" then
			for t = 1, size do
				if finite(melee[t]) and finite(ranged[t]) and melee[t] < ranged[t] then
					problem(
						`ladder.hp.melee[{t}] ({melee[t]}) is below ladder.hp.ranged[{t}] ({ranged[t]})`
					)
				end
			end
		end
		if not finite(ladder.rangeHp) or ladder.rangeHp <= 0 then
			problem(
				`ladder.rangeHp is {tostring(ladder.rangeHp)}, not a number above 0: the range uses baseHp`
			)
		end
		local bandSize: any = ladder.bandSize
		local bands: any = if type(ladder.bands) == "table" then ladder.bands else {}
		if not whole(bandSize) or bandSize <= 0 then
			problem(
				`ladder.bandSize is {tostring(bandSize)}, not a whole number above 0: nothing can be bought`
			)
		elseif bandSize * #bands ~= size then
			problem(`ladder.bands and bandSize do not cover the {size} tiers`)
		end
		for index, def: any in bands do
			if type(def) ~= "table" or type(def.levelId) ~= "string" or def.levelId == "" then
				problem(`ladder.bands[{index}] names no level: its tiers can never be bought`)
			elseif type(def.material) ~= "string" or def.material == "" then
				problem(
					`ladder.bands[{index}] ({def.levelId}) names no material: its tiers can never be bought`
				)
			end
		end
		local costs: any = ladder.costs
		if type(costs) ~= "table" or (whole(bandSize) and #costs ~= bandSize) then
			problem("ladder.costs is not one cost per position in a band")
		else
			for position, cost: any in costs do
				if not finite(cost) or cost < 0 then
					problem(
						`ladder.costs[{position}] is {tostring(cost)}, not a number of at least 0`
					)
				end
			end
		end
		if type(ladder.starDifficulty) ~= "string" or ladder.starDifficulty == "" then
			problem("ladder.starDifficulty names no difficulty: no band top can ever be bought")
		end
		local also: any = ladder.starAlso
		if also ~= nil and not namesList(also) then
			problem("ladder.starAlso is not a list of difficulty names")
		end
	end
	local windows: any = cfg.windows
	local known: { [string]: boolean } = {}
	for _, family in families do
		known[family] = true
		local window: any = if type(windows) == "table" then windows[family] else nil
		if type(window) ~= "table" then
			problem(`windows has no entry for "{family}": it fights at T1 and cannot be upgraded`)
		elseif
			not whole(window.start)
			or not whole(window.top)
			or window.start < 1
			or window.start > window.top
			or (size > 0 and window.top > size)
		then
			problem(
				`windows.{family} ({tostring(window.start)} to {tostring(window.top)}) is not 1 <= start <= top <= {size}`
			)
		end
	end
	if type(windows) == "table" then
		local names: { string } = {}
		for family in windows do
			if not known[family] then
				table.insert(names, tostring(family))
			end
		end
		table.sort(names)
		for _, family in names do
			problem(`windows.{family} names no weapon family`)
		end
	end
	local legacy: any = cfg.legacy
	local gearCosts: any = if type(legacy) == "table" then legacy.gearCosts else nil
	if type(gearCosts) ~= "table" then
		problem("has no legacy.gearCosts: the v8 profile step refunds nothing")
	else
		for index, entry: any in gearCosts do
			if
				type(entry) ~= "table"
				or type(entry.material) ~= "string"
				or entry.material == ""
				or not finite(entry.amount)
				or entry.amount < 0
			then
				problem(`legacy.gearCosts[{index}] is not a material and an amount of at least 0`)
			end
		end
	end
	return problems
end

-- ---------------------------------------------------------------------------------------------
-- C0: the Ascension forge (the hub's ArmoryService)
-- ---------------------------------------------------------------------------------------------

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

-- "invalid" for any slot but "melee" and "ranged" (slotValue is nil for every other word).
function Armory.CanAscend(cfg: ArmoryConfig, state: ArmoryOwner, slot: string): (boolean, Refusal?)
	local current = slotValue(state.combat.ascension, slot)
	if current == nil then
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

return Armory
