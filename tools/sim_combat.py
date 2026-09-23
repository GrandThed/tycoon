#!/usr/bin/env python
"""Armory-and-expedition simulator for Era City Tycoon (C0 + C1 + C2).

Mirrors `src/shared/Armory.luau` and `src/shared/Combat.luau` function for
function (same names, snake_case) from the contracts in `docs/INTERFACES.md`
"C0 contracts -- Expeditions foundation" and "C1 contracts -- Studio bridge +
Village expedition" ("Pure additions") and "C2 contracts -- Co-op" (boss HP
by party size, the Mentor bonus at boss clears, party effects), and reads the four real configs
(`Armory.json`, `Combat.json`, `Places.json`, `Missions/*.json`). The greedy
tycoon curve is NOT re-derived here: `sim_economy.simulate_era` is imported and
run exactly as `sim_economy.run_full`/`run_packs` do (legacy carried across
advances, 1 s resolution), so both tools always agree on income per second.

What it answers:
  * when the greedy player's persisted income/s crosses each weapon tier's
    `unlockRate` (the Armory gate), per band and per era;
  * how long a modelled expedition run takes, wave by wave, at the mission's
    recommended Gear Power and at 2x / 0.6x of it;
  * what a full run pays in cash and materials, and how that compares with the
    era's remaining slot cost (the "combat must not replace the tycoon" rule).

DPS model (fixed by the contract; C1 replaces it with measured hit rates):
  melee  = damage x mean(chain) / mean(windows) x 0.7 hit rate
  ranged = damage / cooldown x 0.5 uptime
  TTK    = hp / DPS;   wave seconds = count x TTK / party
Abilities, kiting, respawns, breathers and the tempo director are NOT in the
model; breather time is reported beside the combat time, never inside it.

Usage:
  py tools/sim_combat.py                  # unlock table + Village run report
  py tools/sim_combat.py --check          # the thirteen C0-C2 assertions; exit 1 on any
  py tools/sim_combat.py --era 1          # only that era's mission
  py tools/sim_combat.py --power 84       # model the run at a given Gear Power
  py tools/sim_combat.py --party 4        # party size for the modelled run
  py tools/sim_combat.py --overdrive      # Overdrive multipliers on
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = REPO_ROOT / "src" / "shared" / "Config"
ARMORY_CONFIG_PATH = CONFIG_DIR / "Armory.json"
COMBAT_CONFIG_PATH = CONFIG_DIR / "Combat.json"
PLACES_CONFIG_PATH = CONFIG_DIR / "Places.json"
MISSIONS_DIR = CONFIG_DIR / "Missions"

# sim_economy lives in this folder and is imported, never copied: it owns every
# tycoon formula and both tools must read the same income curve.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import sim_economy as se  # noqa: E402

# Tool-only constants. The DPS coefficients are the contract's, restated here so
# a reader can see the whole model in one place; nothing in the game reads them.
MELEE_HIT_RATE = 0.7
RANGED_UPTIME = 0.5
# Assertion 3's tolerance and assertion 4's ceiling, both from the contract.
RUN_TIME_TOLERANCE = 0.5
RUN_CASH_CAP_FRACTION = 0.25
# Assertion 5's fixture: a 10:1 damage duo must leave the veteran >= 75 %.
VETERAN_SHARE_FLOOR = 0.75
# C2 fixtures (docs/INTERFACES.md "C2 contracts", Balance). Assertion 11: a boss
# wave at party 2-4, everyone at the recommended power, lasts within +-35 % of
# the solo boss wave. Assertion 12: a 10:1 income duo pays the mentor exactly
# mentorValor at a boss clear. The rates are fixture numbers, not game values.
BOSS_WAVE_TOLERANCE = 0.35
MENTOR_HOST_RATE = 10000.0
MENTOR_RATE_RATIO = 10.0
# Assertion 7/8/10 fixtures: the power multiples the contract names.
STRONG_POWER_MULT = 2.0
WEAK_POWER_MULT = 0.6
WEAK_DEATH_WAVE = 6
WEAK_DEATH_TOLERANCE = 2
OVERDRIVE_POWER_MULT = 3.0
OVERDRIVE_CASH_MULT = 3.0
# Run-simulator resolution and the spatial facts it needs. The arena is 110 x 110
# with eight rim spawns (Layouts/Arenas/Village.luau), so a spawn is ~45 studs
# from a player fighting near the middle; MELEE_CONTACT_SLOTS is how many rigs
# fit shoulder to shoulder on a reach-5 ring around one player (the rest queue
# behind and do not swing). None of these is a game constant -- the server uses
# real positions -- but the run simulator needs them to turn "within reach" into
# a number.
DT = 0.1
SPAWN_DISTANCE = 45.0
MELEE_CONTACT_SLOTS = 4
DASH_TARGETS = 2
# The contract says a merge is decided "once the wave has finished spawning",
# i.e. at that single instant, which is when `deadFraction` still carries
# information (it is then (count - enemies still in flight) / count). The other
# reading -- re-test every tick until the wave clears -- is what WaveService.tick
# ships (lead ruling, C1 review): a merge may fire as kills accelerate after the
# spawner has finished. Every assertion holds under both readings; the one-shot
# variant stays behind the flag so a reviewer can reproduce BALANCE.md "C1"
# either way (the under-geared player dies on wave 6 continuous, wave 5 one-shot).
MERGE_CHECK_CONTINUOUS = True
# The incoming-damage counterpart of MELEE_HIT_RATE / RANGED_UPTIME: the player
# moves, so not every enemy swing lands. A melee enemy lands in proportion to how
# well it can keep up (`speed` against the default R15 WalkSpeed), which makes a
# slow boss genuinely kitable and turns enemy `speed` into a balance lever; a
# ranged enemy shooting from 30 studs lands the same half its shots the player's
# own ranged term assumes.
PLAYER_WALK_SPEED = 16.0
RANGED_ENEMY_LAND_RATE = 0.5


# --------------------------------------------------------------------------
# Config loading (Catalog.GetArmoryConfig / GetCombatConfig / GetPlacesConfig /
# GetMissionConfig -- nil is the signal, so a missing file returns None and the
# caller reports "feature absent" instead of failing).
# --------------------------------------------------------------------------


def _load(path):
    if not path.exists():
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def load_armory_config():
    return _load(ARMORY_CONFIG_PATH)


def load_combat_config():
    return _load(COMBAT_CONFIG_PATH)


def load_places_config():
    """Catalog.GetPlacesConfig -- missing file degrades to "not published"."""
    return _load(PLACES_CONFIG_PATH) or {"version": 1, "hubPlaceId": 0, "combatPlaceId": 0}


def load_missions():
    """Catalog.GetMissionConfig: `Config/Missions/<eraIndex>_<EraName>.json`,
    resolved by numeric prefix exactly like `Config/Eras`. eraIndex -> config."""
    missions = {}
    if not MISSIONS_DIR.exists():
        return missions
    for path in sorted(MISSIONS_DIR.glob("*.json")):
        with open(path, encoding="utf-8") as handle:
            mission = json.load(handle)
        missions[mission["era"]] = mission
    return missions


def luau_round(value):
    """Luau `math.round` -- half away from zero. Python's round() is banker's
    rounding, which would disagree with the server on exact .5 counts."""
    if value >= 0:
        return math.floor(value + 0.5)
    return -math.floor(-value + 0.5)


# --------------------------------------------------------------------------
# src/shared/Armory.luau mirror
# --------------------------------------------------------------------------


def tier_def(cfg, slot, tier):
    """Armory.TierDef -- tier 0 = the starter weapon; None past the last tier."""
    slot_def = cfg["slots"][slot]
    if tier <= 0:
        return slot_def["starter"]
    tiers = slot_def["tiers"]
    if tier > len(tiers):
        return None
    return tiers[tier - 1]


def ascension_level_def(cfg, level):
    """Armory.luau `ascensionLevel` (file-local) -- the level's row, or None at
    level 0 AND past the last row. Deliberately not clamped: a profile ahead of
    the config then reads as "no Ascension" (neutral x1) rather than as the top
    level, which is the same degrade-quietly rule as a missing weapon tier."""
    if level <= 0:
        return None
    levels = cfg["ascension"]["levels"]
    if level > len(levels):
        return None
    return levels[level - 1]


def weapon_damage(cfg, slot, tier, asc_level):
    """Armory.WeaponDamage -- tierDef.damage x ascension damageMult (1 when 0)."""
    definition = tier_def(cfg, slot, tier)
    if definition is None:
        return 0
    level = ascension_level_def(cfg, asc_level)
    return definition["damage"] * (level["damageMult"] if level else 1)


def weapon_hp(cfg, slot, tier, asc_level):
    """Armory.WeaponHp -- tierDef.hp x ascension hpMult (1 when 0)."""
    definition = tier_def(cfg, slot, tier)
    if definition is None:
        return 0
    level = ascension_level_def(cfg, asc_level)
    return definition["hp"] * (level["hpMult"] if level else 1)


def max_hp(cfg, gear, ascension):
    """Armory.MaxHp -- baseHp + WeaponHp(melee) + WeaponHp(ranged)."""
    return (
        cfg["baseHp"]
        + weapon_hp(cfg, "melee", gear["melee"], ascension["melee"])
        + weapon_hp(cfg, "ranged", gear["ranged"], ascension["ranged"])
    )


def gear_power(cfg, gear, ascension):
    """Armory.GearPower -- round(dmg melee + dmg ranged + MaxHp x power.hpWeight)."""
    return luau_round(
        weapon_damage(cfg, "melee", gear["melee"], ascension["melee"])
        + weapon_damage(cfg, "ranged", gear["ranged"], ascension["ranged"])
        + max_hp(cfg, gear, ascension) * cfg["power"]["hpWeight"]
    )


def next_tier(cfg, gear, slot):
    """Armory.NextTier -- gear[slot] + 1, None past the last tier."""
    candidate = gear[slot] + 1
    if candidate > len(cfg["slots"][slot]["tiers"]):
        return None
    return candidate


def band_material(cfg, band):
    for entry in cfg["bands"]:
        if entry["band"] == band:
            return entry["material"]
    return "?"


def tier_cost(cfg, slot, tier):
    """Armory.TierCost -> (material, amount). The material is the band's."""
    definition = tier_def(cfg, slot, tier)
    if definition is None or tier <= 0:
        return None, 0
    return band_material(cfg, definition["band"]), definition["cost"]


def tier_unlock_rate(cfg, slot, tier):
    """Armory.TierUnlockRate -- the persisted income/s the city must be making."""
    definition = tier_def(cfg, slot, tier)
    if definition is None or tier <= 0:
        return 0
    return definition["unlockRate"]


def can_buy(cfg, state, slot, income_per_second):
    """Armory.CanBuy -> (ok, reason). invalid: bad slot / no next tier;
    locked: income below unlockRate; insufficientFunds: materials short."""
    if slot not in cfg["slots"]:
        return False, "invalid"
    combat = state["combat"]
    tier = next_tier(cfg, combat["gear"], slot)
    if tier is None:
        return False, "invalid"
    if income_per_second < tier_unlock_rate(cfg, slot, tier):
        return False, "locked"
    material, amount = tier_cost(cfg, slot, tier)
    if combat["materials"].get(material, 0) < amount:
        return False, "insufficientFunds"
    return True, None


def ascension_cost(cfg, level):
    """Armory.AscensionCost -> {materials, valor} or None past the last level.
    The Luau returns a fresh `table.clone` of the materials so a caller cannot
    mutate Armory.json through it; the copy here serves the same purpose."""
    definition = ascension_level_def(cfg, level)
    if definition is None:
        return None
    return {"materials": dict(definition["materials"]), "valor": definition["valor"]}


def ascension_cap(cfg, rebirth_count):
    """Armory.AscensionCap -- 0 below requiresRebirth, else
    min(#levels, (rebirthCount - requiresRebirth + 1) x levelsPerRebirth)."""
    asc = cfg["ascension"]
    if rebirth_count < asc["requiresRebirth"]:
        return 0
    return min(
        len(asc["levels"]),
        (rebirth_count - asc["requiresRebirth"] + 1) * asc["levelsPerRebirth"],
    )


def can_ascend(cfg, state, slot):
    """Armory.CanAscend -> (ok, reason). invalid: bad slot / no such ascension
    entry; locked: the cap (i.e. rebirthCount) or the end of the level list;
    insufficientFunds: Valor short, then materials short -- the Luau checks
    Valor first, so the sim does too."""
    combat = state["combat"]
    current = combat["ascension"].get(slot)
    if slot not in cfg["slots"] or current is None:
        return False, "invalid"
    level = current + 1
    if level > ascension_cap(cfg, state["rebirthCount"]):
        return False, "locked"
    cost = ascension_cost(cfg, level)
    if cost is None:
        return False, "locked"
    if combat["valor"] < cost["valor"]:
        return False, "insufficientFunds"
    for material, amount in cost["materials"].items():
        if combat["materials"].get(material, 0) < amount:
            return False, "insufficientFunds"
    return True, None


def class_def(cfg, class_name):
    """Armory.ClassDef"""
    return cfg["classes"].get(class_name)


def ability_def(cfg, key):
    """Armory.AbilityDef"""
    return cfg["abilities"].get(key)


# --------------------------------------------------------------------------
# src/shared/Combat.luau mirror
# --------------------------------------------------------------------------


def new_combat_profile():
    """The v5 profile template's `combat` field (ProfileSchema.PROFILE_TEMPLATE)."""
    return {
        "materials": {},
        "valor": 0,
        "gear": {"melee": 0, "ranged": 0},
        "ascension": {"melee": 0, "ranged": 0},
        "missions": {},
        "highestEra": 1,
        "expeditionSince": 0,
        "expeditionSeconds": 0,
        "stats": {"kills": 0, "wavesCleared": 0, "expeditions": 0, "cashFromCombat": 0},
    }


def touch_highest_era(state):
    """Combat.TouchHighestEra"""
    state["combat"]["highestEra"] = max(state["combat"]["highestEra"], state["era"])


def mission_unlocked(state, mission, overdrive, combat_cfg):
    """Combat.MissionUnlocked -- era <= highestEra; Overdrive needs the rebirth."""
    if mission["era"] > state["combat"]["highestEra"]:
        return False
    if overdrive and state["rebirthCount"] < combat_cfg["overdrive"]["requiresRebirth"]:
        return False
    return True


def wave_weights(mission, wave):
    """The composition row in force at `wave` (the last `fromWave` <= wave)."""
    weights = {}
    for row in mission["waveTable"]["composition"]:
        if row["fromWave"] <= wave:
            weights = row["weights"]
    return weights


def wave_spec(mission, wave, party_size, overdrive, combat_cfg):
    """Combat.WaveSpec -- count/hpMult/damageMult/rewardMult/boss/weights."""
    table = mission["waveTable"]
    over = combat_cfg["overdrive"]
    coop = combat_cfg["coop"]
    # math.max(partySize, 1) - 1: a party size of 0 must not shrink the wave.
    extras = max(party_size, 1) - 1
    count = luau_round(
        (table["baseCount"] + table["countPerWave"] * (wave - 1))
        * (1 + coop["countPerExtraPlayer"] * extras)
        * (over["countMult"] if overdrive else 1)
    )
    return {
        "count": count,
        "hpMult": (1 + table["hpGrowth"]) ** (wave - 1) * (over["hpMult"] if overdrive else 1),
        "damageMult": (1 + table["damageGrowth"]) ** (wave - 1)
        * (over["damageMult"] if overdrive else 1),
        "rewardMult": (1 + table["rewardGrowth"]) ** (wave - 1)
        * (over["rewardMult"] if overdrive else 1),
        # C2: the boss is one body whatever the party size, so it scales in HP
        # instead of count. Same `extras` as the count term.
        "bossHpMult": 1 + coop["bossHpPerExtraPlayer"] * extras,
        "boss": mission["bosses"].get(str(wave)),
        "weights": wave_weights(mission, wave),
    }


def enemy_stats(mission, key, spec, is_boss=False):
    """Combat.EnemyStats -- rounded; a boss applies its own mults on top of spec.

    One boss entity per boss wave: the mults need BOTH the caller's `is_boss` and
    a `spec.boss.enemy == key` guard, so an ordinary brute in the Warlord's wave
    stays ordinary and a mismarked spawn cannot borrow another enemy's mults.
    `Combat.EnemyStats(mission, key, spec, isBoss)` gates on the same two
    conditions."""
    enemy = mission["enemies"][key]
    boss = spec["boss"]
    if not (is_boss and boss is not None and boss["enemy"] == key):
        boss = None
    # HP is multiplied left to right exactly as the Luau writes it --
    # round(enemy.hp * spec.hpMult * boss.hpMult * spec.bossHpMult) -- because
    # regrouping the factors can move a product across a .5 by one ulp.
    boss_hp = boss["hpMult"] if boss else 1
    party_hp = spec.get("bossHpMult", 1) if boss else 1
    damage_mult = spec["damageMult"] * (boss["damageMult"] if boss else 1)
    cash_mult = spec["rewardMult"] * (boss["cashMult"] if boss else 1)
    materials_mult = spec["rewardMult"] * (boss["materialsMult"] if boss else 1)
    return {
        "hp": luau_round(enemy["hp"] * spec["hpMult"] * boss_hp * party_hp),
        "damage": luau_round(enemy["damage"] * damage_mult),
        "cash": luau_round(enemy["cash"] * cash_mult),
        "materials": luau_round(enemy["materials"] * materials_mult),
    }


def boss_valor(mission, wave, overdrive, combat_cfg):
    """Combat.BossValor -- the boss row's valor, x Overdrive rewardMult.

    The contract does not say which Overdrive multiplier applies to Valor;
    the sim uses `overdrive.rewardMult` (reported to the lead)."""
    boss = mission["bosses"].get(str(wave))
    if boss is None:
        return 0
    mult = combat_cfg["overdrive"]["rewardMult"] if overdrive else 1
    return luau_round(boss["valor"] * mult)


def recommended_power(mission, overdrive, combat_cfg):
    """Combat.RecommendedPower -- recommendedPower x Overdrive hpMult."""
    mult = combat_cfg["overdrive"]["hpMult"] if overdrive else 1
    return mission["recommendedPower"] * mult


def combat_cash_mult(state, game_config, shop_config):
    """Combat.CombatCashMult -- LegacyMult x PerkIncomeMult; no pass, no
    Premium, no neighbours (combat cash is not an income stream)."""
    return se.legacy_mult(state["legacy"], game_config) * se.perk_income_mult(
        shop_config, state["legacyShop"]
    )


def contribution_shares(damage_by_user, floor):
    """Combat.ContributionShares -- floor + (1 - floor*n) x dmg/total; equal
    split when total damage is 0."""
    count = len(damage_by_user)
    if count == 0:
        return {}
    total = sum(damage_by_user.values())
    if total == 0:
        return {user: 1 / count for user in damage_by_user}
    scale = 1 - floor * count
    return {user: floor + scale * (damage / total) for user, damage in damage_by_user.items()}


def mentor_bonus(combat_cfg, host_rate, party_rates):
    """Combat.MentorBonus -- mentorValor per member under hostRate x mentorRatio."""
    coop = combat_cfg["coop"]
    threshold = host_rate * coop["mentorRatio"]
    return sum(coop["mentorValor"] for rate in party_rates if rate < threshold)


def away_efficiency(elapsed, expedition_seconds, efficiency, expedition_efficiency):
    """Combat.AwayEfficiency -- time-weighted blend of the two efficiencies.
    `expeditionSeconds` is clamped into [0, elapsed], so a stale or negative
    stamp can never pay more (or less) than the absence itself."""
    if elapsed <= 0:
        return efficiency
    away = min(max(expedition_seconds, 0), elapsed)
    rest = elapsed - away
    return (away * expedition_efficiency + rest * efficiency) / elapsed


def tempo(kills_in_window, window_seconds, expected_kills_per_second, director):
    """Combat.Tempo -- clamp(actual/expected, tempoMin, tempoMax); tempoMin when
    either the expected rate or the window is non-positive (no division)."""
    if expected_kills_per_second <= 0 or window_seconds <= 0:
        return director["tempoMin"]
    actual = kills_in_window / window_seconds
    return min(max(actual / expected_kills_per_second, director["tempoMin"]), director["tempoMax"])


# --------------------------------------------------------------------------
# src/shared/Combat.luau mirror -- the C1 "Pure additions"
# --------------------------------------------------------------------------


def wave_composition(count, weights):
    """Combat.WaveComposition -- which enemy key each of the `count` spawns is.

    Largest-remainder apportionment: quota_k = count x w_k / sum(w), n_k =
    floor(quota_k), the leftover picks go to the largest fractions (ties by key
    name ascending). The ORDER is then `count` picks of the key with the
    smallest placed_k / n_k ratio (ties by key name ascending), which interleaves
    the keys -- 0.7/0.3 spawns R A R R A R R, not RRRRR AA. No RNG: the server
    and this sim build the identical list for the identical wave."""
    # Zero-weight keys are dropped before anything else, exactly as the Luau
    # does, so they can never collect a rounding leftover.
    positive = {key: weight for key, weight in weights.items() if weight > 0}
    total = sum(positive.values())
    if count <= 0 or total <= 0 or not positive:
        return []
    quota = {key: count * weight / total for key, weight in positive.items()}
    picked = {key: math.floor(value) for key, value in quota.items()}
    leftover = count - sum(picked.values())
    if leftover > 0:
        by_fraction = sorted(quota, key=lambda key: (-(quota[key] - picked[key]), key))
        for key in by_fraction[:leftover]:
            picked[key] += 1
    placed = {key: 0 for key in picked}
    order = []
    for _ in range(count):
        candidates = [key for key in picked if placed[key] < picked[key]]
        if not candidates:
            break
        key = min(candidates, key=lambda name: (placed[name] / picked[name], name))
        order.append(key)
        placed[key] += 1
    return order


def spawn_interval(mission, spec, tempo_value, overdrive, combat_cfg):
    """Combat.SpawnInterval -- targetWaveSeconds / count / tempo / spawnRateMult.

    The trickle is what actually paces a wave: at tempo 1.0 the whole wave takes
    `targetWaveSeconds` to walk in, however fast the player kills."""
    # tempo is already clamped to [tempoMin, tempoMax] by Combat.Tempo and a
    # count is always >= 1, so the guard never fires in a real run; it mirrors
    # the Luau's own guard (which returns the whole wave window).
    if spec["count"] <= 0 or tempo_value <= 0:
        return mission["targetWaveSeconds"]
    rate = combat_cfg["overdrive"]["spawnRateMult"] if overdrive else 1
    return mission["targetWaveSeconds"] / spec["count"] / tempo_value / rate


def breather_seconds(tempo_value, director):
    """Combat.BreatherSeconds -- breatherSeconds at tempo >= 1, stretching to
    breatherMaxSeconds as tempo falls to tempoMin. A struggling party gets the
    long breather (and its regen); a fast one barely stops."""
    span = director["breatherMaxSeconds"] - director["breatherSeconds"]
    denominator = 1 - director["tempoMin"]
    ratio = 0.0 if denominator == 0 else (1 - tempo_value) / denominator
    return director["breatherSeconds"] + span * min(max(ratio, 0.0), 1.0)


def should_merge(tempo_value, dead_fraction, director):
    """Combat.ShouldMerge -- tempo >= mergeTempo AND deadFraction >= mergeThreshold.
    Only asked once the wave has finished spawning."""
    return tempo_value >= director["mergeTempo"] and dead_fraction >= director["mergeThreshold"]


def equipped(cfg, state, slot):
    """(tierDef, classDef) of the weapon in `slot`; (None, None) when either is
    missing from Armory.json -- the degrade-quietly rule, so a bad config reads
    as 0 damage instead of erroring. Not a contract function: the Luau inlines it."""
    definition = tier_def(cfg, slot, state["combat"]["gear"][slot])
    if definition is None:
        return None, None
    return definition, class_def(cfg, definition["class"])


def melee_damage(cfg, state, step):
    """Combat.MeleeDamage -- WeaponDamage(melee) x class.chain[step]."""
    definition, cls = equipped(cfg, state, "melee")
    if definition is None or cls is None or not cls.get("chain"):
        return 0
    chain = cls["chain"]
    # Out-of-range steps fall back to x1, as the Luau's `chain[step] ~= nil` test
    # does; the server wraps the combo at 3, so this is a guard, not a path.
    step_mult = chain[step - 1] if 1 <= step <= len(chain) else 1
    base = weapon_damage(
        cfg, "melee", state["combat"]["gear"]["melee"], state["combat"]["ascension"]["melee"]
    )
    return base * step_mult


def ranged_damage(cfg, state, charge):
    """Combat.RangedDamage -- WeaponDamage(ranged), scaled by the draw for a
    `charge` class (minDamageFraction at 0, full at 1); every other class fires
    at full damage and ignores `charge`."""
    definition, cls = equipped(cfg, state, "ranged")
    if definition is None or cls is None:
        return 0
    base = weapon_damage(
        cfg, "ranged", state["combat"]["gear"]["ranged"], state["combat"]["ascension"]["ranged"]
    )
    if cls.get("fire") != "charge":
        return base
    fraction = cls.get("minDamageFraction", 0)
    return base * (fraction + (1 - fraction) * min(max(charge, 0.0), 1.0))


def ability_damage(cfg, state, slot):
    """Combat.AbilityDamage -- WeaponDamage(slot) x ability.damageMult x the
    Ascension abilityMult (1 at level 0). 0 when the weapon has no ability."""
    definition, _ = equipped(cfg, state, slot)
    if definition is None:
        return 0
    definition_ability = ability_def(cfg, definition.get("ability", ""))
    if definition_ability is None:
        return 0
    level = ascension_level_def(cfg, state["combat"]["ascension"][slot])
    base = weapon_damage(cfg, slot, state["combat"]["gear"][slot], state["combat"]["ascension"][slot])
    return base * definition_ability["damageMult"] * (level["abilityMult"] if level else 1)


def ability_cooldown(cfg, state, slot):
    """Combat.AbilityCooldown -- the ability's own cooldown (0 when it has none).
    `killCooldownRefundSeconds` is applied by the caller, per kill."""
    definition, _ = equipped(cfg, state, slot)
    if definition is None:
        return 0
    definition_ability = ability_def(cfg, definition.get("ability", ""))
    if definition_ability is None:
        return 0
    return definition_ability["cooldown"]


def split_pool(pool, shares):
    """Combat.SplitPool -- the wave pot cut by contribution share, floored per
    currency (Waves section 6). Flooring every share means the pot never pays out
    more than it holds; the remainder is dropped, not banked."""
    out = {}
    for user, share in shares.items():
        out[user] = {
            "cash": math.floor(pool["cash"] * share),
            "materials": math.floor(pool["materials"] * share),
            "valor": math.floor(pool["valor"] * share),
        }
    return out


# --------------------------------------------------------------------------
# The DPS terms (contract-fixed coefficients, used by the run simulator)
# --------------------------------------------------------------------------


def melee_dps(armory, definition):
    """damage x mean(chain) / mean(windows) x hit rate. The chain average is the
    per-swing damage multiplier and the window average is the per-swing time, so
    the quotient is the sustained swing rate of an uninterrupted combo."""
    cls = class_def(armory, definition["class"])
    if cls is None or cls["kind"] != "melee":
        return 0.0
    chain = sum(cls["chain"]) / len(cls["chain"])
    window = sum(cls["windows"]) / len(cls["windows"])
    return definition["damage"] * chain / window * MELEE_HIT_RATE


def ranged_dps(armory, definition):
    """damage / cooldown x uptime. `chargeSeconds` is deliberately NOT in the
    model (contract); for charge weapons the 0.5 uptime absorbs it."""
    cls = class_def(armory, definition["class"])
    if cls is None or cls["kind"] != "ranged":
        return 0.0
    return definition["damage"] / cls["cooldown"] * RANGED_UPTIME


def loadout_dps(armory, gear, ascension):
    """Modelled (melee, ranged) DPS of a loadout, ascension multipliers included."""
    melee = tier_def(armory, "melee", gear["melee"])
    ranged = tier_def(armory, "ranged", gear["ranged"])
    melee_level = ascension_level_def(armory, ascension["melee"])
    ranged_level = ascension_level_def(armory, ascension["ranged"])
    out_melee = melee_dps(armory, melee) * (melee_level["damageMult"] if melee_level else 1)
    out_ranged = ranged_dps(armory, ranged) * (ranged_level["damageMult"] if ranged_level else 1)
    return out_melee, out_ranged


def symmetric_loadouts(armory):
    """The Armory's two ladders are parallel (same band, cost and unlockRate per
    tier), so a player buys them in step: the sim models tier n / tier n only."""
    count = min(len(armory["slots"]["melee"]["tiers"]), len(armory["slots"]["ranged"]["tiers"]))
    return [{"melee": tier, "ranged": tier} for tier in range(0, count + 1)]


NO_ASCENSION = {"melee": 0, "ranged": 0}


def gear_for_power(armory, target_power):
    """The loadout a player at Gear Power `target_power` is actually carrying:
    the highest tiers whose summed power stays <= target, melee first (C1
    contract). Melee-first matters because melee is ~75 % of modelled DPS, so
    this is the strongest legal loadout at that power, not the symmetric one --
    at 60 it is Iron Sword + Short Bow (57), not tier 2/2 (64, over budget).
    Turns "recommended", "2x" and "0.6x" into one function."""
    gear = {"melee": 0, "ranged": 0}
    while True:
        for slot in ("melee", "ranged"):
            candidate = next_tier(armory, gear, slot)
            if candidate is None:
                continue
            trial = dict(gear)
            trial[slot] = candidate
            if gear_power(armory, trial, NO_ASCENSION) <= target_power:
                gear = trial
                break
        else:
            break
    return gear, gear_power(armory, gear, NO_ASCENSION)


def highest_unlocked_gear(armory, income_per_second):
    """The best symmetric loadout the income gate alone allows (materials aside):
    the highest tier whose unlockRate the city's persisted rate has reached."""
    best = {"melee": 0, "ranged": 0}
    for gear in symmetric_loadouts(armory):
        tier = gear["melee"]
        if tier == 0:
            continue
        rate = max(
            tier_unlock_rate(armory, "melee", tier), tier_unlock_rate(armory, "ranged", tier)
        )
        if income_per_second >= rate:
            best = gear
    return best


# --------------------------------------------------------------------------
# The greedy tycoon curve (sim_economy, not re-derived here)
# --------------------------------------------------------------------------


class Curve:
    """One era of the default greedy playthrough: its per-second income series,
    its purchase order and its offset on the whole-run clock."""

    def __init__(self, era, result, offset, legacy_in):
        self.era = era
        self.ips = result.ips_series
        self.seconds = result.seconds
        self.slot_order = result.slot_order
        self.offset = offset
        self.legacy_in = legacy_in
        self.total_slot_cost = se.era_slot_cost_total(era)
        self.cost_by_id = {slot["id"]: slot["baseCost"] for slot in era["slots"]}

    @property
    def index(self):
        return self.era["eraIndex"]

    @property
    def peak(self):
        return max(self.ips)

    def median(self):
        """Income is monotonic inside an era, so the median value is the value
        at the median second."""
        return sorted(self.ips)[len(self.ips) // 2]

    def crossing(self, rate):
        """First second at which the persisted rate reaches `rate`, or None."""
        for second, value in enumerate(self.ips):
            if value >= rate:
                return second
        return None

    def remaining_slot_cost(self, second):
        """Slots still unbought at `second`, priced at baseCost -- the cash the
        greedy player still owes this era."""
        return sum(
            self.cost_by_id[slot_id]
            for slot_id, bought_at in self.slot_order
            if bought_at > second
        )


def greedy_curves(game, eras):
    """The default `sim_economy` playthrough: greedy, free, legacy carried."""
    curves = []
    legacy = 0
    offset = 0
    for era in eras:
        result = se.simulate_era(era, game, legacy, "greedy", None, True)
        curves.append(Curve(era, result, offset, legacy))
        offset += result.seconds
        legacy += result.legacy_gained
    return curves


def first_crossing(curves, rate):
    """(curve, second in era) of the first moment the greedy player's persisted
    rate reaches `rate`. Income DROPS at every era advance (a new plot starts
    empty), so this scans eras in order instead of assuming monotonicity."""
    for curve in curves:
        second = curve.crossing(rate)
        if second is not None:
            return curve, second
    return None, None


# --------------------------------------------------------------------------
# The modelled run
# --------------------------------------------------------------------------


def player_model(armory, gear, ascension):
    """The player as the run simulator sees them: two sustained DPS terms and
    the abilities, all built from the C1 pure functions."""
    state = {"combat": {"gear": dict(gear), "ascension": dict(ascension)}}
    melee_def, melee_cls = equipped(armory, state, "melee")
    ranged_def, ranged_cls = equipped(armory, state, "ranged")
    chain_damage = 0.0
    chain_seconds = 0.0
    if melee_cls is not None and melee_cls.get("chain"):
        for step in range(1, len(melee_cls["chain"]) + 1):
            chain_damage += melee_damage(armory, state, step)
            chain_seconds += melee_cls["windows"][step - 1]
    melee = chain_damage / chain_seconds * MELEE_HIT_RATE if chain_seconds > 0 else 0.0
    ranged = 0.0
    if ranged_cls is not None and ranged_cls.get("cooldown"):
        # charge 1.0: the model assumes a full draw, so the charge term is the
        # class's full damage and RANGED_UPTIME absorbs the draw time.
        ranged = ranged_damage(armory, state, 1.0) / ranged_cls["cooldown"] * RANGED_UPTIME
    abilities = []
    for slot, definition in (("melee", melee_def), ("ranged", ranged_def)):
        if definition is None:
            continue
        entry = ability_def(armory, definition.get("ability", ""))
        if entry is None:
            continue
        abilities.append(
            {
                "slot": slot,
                "key": definition["ability"],
                "def": entry,
                "damage": ability_damage(armory, state, slot),
                "cooldown": ability_cooldown(armory, state, slot),
            }
        )
    return {
        "state": state,
        "melee_dps": melee,
        "ranged_dps": ranged,
        "dps": melee + ranged,
        "melee_range": melee_cls["range"] if melee_cls else 0,
        "abilities": abilities,
    }


def ability_targets(ability, alive):
    """Who one cast reaches. Positions are not simulated, so an `aoe` is taken to
    cover the fight (its radius, 10-16 studs, is the whole melee scrum) capped by
    `shots` when the ability has one, and a dash `burst` hits the DASH_TARGETS
    enemies on the line. Documented as the model's most generous assumption."""
    entry = ability["def"]
    if entry["kind"] == "aoe":
        limit = entry.get("shots") or len(alive)
    elif entry.get("dashStuds"):
        limit = DASH_TARGETS
    else:
        limit = entry.get("shots") or 1
    return alive[:limit]


IDLE_MODEL = {"melee_dps": 0.0, "ranged_dps": 0.0, "dps": 0.0, "melee_range": 0, "abilities": []}


def party_members(gear, ascension, party, rate=0.0):
    """`party` identical humans at one loadout and income rate -- the C1 party."""
    return [
        {"gear": dict(gear), "ascension": dict(ascension), "rate": rate, "bot": False}
        for _ in range(max(int(party), 1))
    ]


def member_party_effect(armory, member):
    """The Armory.json partyEffects row this member's melee tier carries, or None.
    A member dict may force one with `party_effect` (the proxy runs that measure
    an effect's size at Village scale, where no band-4 blade exists)."""
    key = member.get("party_effect")
    if key is None:
        definition = tier_def(armory, "melee", member["gear"]["melee"])
        key = definition.get("partyEffect") if definition else None
    if not key:
        return None
    return armory.get("partyEffects", {}).get(key)


def simulate_run(
    mission, armory, combat_cfg, gear, ascension, party, overdrive, cash_mult=1.0, members=None
):
    """One full run, played second by second by the C1 director.

    Deterministic: no RNG anywhere. The loop advances DT at a time and runs the
    contract's lifecycle -- trickle spawns at `SpawnInterval`, `maxAlive`, tempo
    from the kills in the last `windowSeconds` (pinned to 1.0 for
    `tempoWarmupSeconds`), `ShouldMerge` once a wave has finished spawning,
    `BreatherSeconds` with regen between waves, the boss prepended to its wave,
    the elite rule at `eliteTempo`, reward pools flushed through `SplitPool` at
    every wave clear, and the run ending on wave 10, `runCapSeconds` or death.

    C2: the party is a list of `members` ({gear, ascension, rate, bot}); without
    one it is `party` copies of `gear`. Each member has its own DPS, abilities
    and cooldowns; every point of damage is credited to whoever dealt it, into a
    run-wide map and a per-flush tally that is drained at every group clear
    (CombatService.TakeDamageTally). The pot is split by the tally's
    ContributionShares (bots' shares discarded), a kill refunds the KILLER's
    cooldowns only, and at the flush of a group that held a boss every human
    earns MentorBonus over the members whose raw tally share is at least
    `coop.mentorMinDamageShare`. HP stays one pooled bar at the members' mean
    max HP taking `incoming / party` (the C1 model); a rally therefore heals
    (n - 1) / n of its healFraction into that bar.

    Returns (rows, totals): one row per wave (start, end, count, merged, boss,
    HP left) and the run aggregate."""
    director = combat_cfg["director"]
    player_cfg = combat_cfg["player"]
    enemy_cfg = combat_cfg["enemy"]
    coop = combat_cfg["coop"]
    if members is None:
        members = party_members(gear, ascension, party)
    party = len(members)
    # An `idle` member is present (it scales the waves and takes its share of
    # the hits) but deals no damage: the AFK alt the Mentor floor exists for.
    models = [
        IDLE_MODEL if m.get("idle") else player_model(armory, m["gear"], m["ascension"])
        for m in members
    ]
    effects = [member_party_effect(armory, m) for m in members]
    hp_max = sum(max_hp(armory, m["gear"], m["ascension"]) for m in members) / party
    hp = float(hp_max)
    pad = player_cfg["hitDistancePad"]
    engages = [model["melee_range"] + pad for model in models]
    window = director["windowSeconds"]
    warmup = director["tempoWarmupSeconds"]
    refund = player_cfg["killCooldownRefundSeconds"]
    floor_share = coop["contributionFloor"]
    min_mentee_share = coop["mentorMinDamageShare"]
    counts = {
        wave: wave_spec(mission, wave, party, overdrive, combat_cfg)["count"]
        for wave in range(1, mission["waves"] + 1)
    }

    t = 0.0
    seq = 0
    hp_floor = float(hp_max)
    alive = []
    groups = []
    rows = []
    kill_times = []
    kills_by_key = {}
    ready_at = [{"melee": 0.0, "ranged": 0.0} for _ in members]
    empowered_until = [0.0] * party
    empower_mult = [1.0] * party
    run_damage = [0.0] * party
    tally = [0.0] * party
    earned = [{"cash": 0, "materials": 0, "valor": 0, "mentor": 0} for _ in members]
    effect_casts = {"rally": 0, "warcry": 0}
    rally_healed = 0.0
    payout = {"cash": 0, "materials": 0, "valor": 0, "kills": 0}
    next_wave = 1
    tempo_value = 1.0
    breather_end = None
    breather_total = 0.0
    boss_seconds = 0.0
    boss_seconds_by_wave = {}
    ability_damage_total = 0.0
    damage_taken = 0.0
    merges = 0
    end_reason = None
    died_wave = None
    mentor_events = []

    def start_wave(wave, merged):
        nonlocal next_wave
        spec = wave_spec(mission, wave, party, overdrive, combat_cfg)
        order = wave_composition(spec["count"], spec["weights"])
        # The elite rule: one extra elite when the party is running hot and the
        # composition has an elite key at all (Village: brute, from wave 7).
        if tempo_value >= director["eliteTempo"]:
            elites = sorted(
                key
                for key, weight in spec["weights"].items()
                if weight > 0 and mission["enemies"][key]["elite"]
            )
            if elites:
                order.append(elites[0])
        queue = [(key, False) for key in order]
        if spec["boss"] is not None:
            queue.insert(0, (spec["boss"]["enemy"], True))
        groups.append(
            {
                "wave": wave,
                "spec": spec,
                "queue": queue,
                "count": len(queue),
                "spawned": 0,
                "dead": 0,
                "merged": merged,
                "boss": spec["boss"] is not None,
                "pool": {"cash": 0, "materials": 0, "valor": 0, "kills": 0},
                "start": t,
                "next_spawn": t,
                "merge_done": False,
                "taken_at_start": damage_taken,
                "tempo_sum": 0.0,
                "ticks": 0,
                "dead_at_spawn_end": None,
                "tempo_at_spawn_end": 0.0,
                "boss_hp": None,
            }
        )
        next_wave = wave + 1

    def spawn(group):
        nonlocal seq
        key, is_boss = group["queue"][group["spawned"]]
        stats = enemy_stats(mission, key, group["spec"], is_boss)
        definition = mission["enemies"][key]
        seq += 1
        if is_boss:
            group["boss_hp"] = stats["hp"]
        alive.append(
            {
                "key": key,
                "hp": float(stats["hp"]),
                "max_hp": stats["hp"],
                "damage": stats["damage"],
                "cash": stats["cash"],
                "materials": stats["materials"],
                "boss": is_boss,
                "kind": definition["kind"],
                "reach": definition["reach"],
                "speed": definition["speed"],
                "cooldown": definition["attackCooldown"],
                "dist": SPAWN_DISTANCE,
                "next_attack": None,
                "seq": seq,
                "group": group,
                "land": (
                    RANGED_ENEMY_LAND_RATE
                    if definition["kind"] == "ranged"
                    else min(definition["speed"] / PLAYER_WALK_SPEED, 1.0)
                ),
            }
        )
        group["spawned"] += 1

    def hit(enemy, credits):
        """Apply {member index: damage} to one enemy; credit what actually
        landed (overkill is not damage) pro rata; the killer is the member with
        the largest part of the killing blow."""
        if enemy["hp"] <= 0:
            return 0.0
        total = sum(credits.values())
        if total <= 0:
            return 0.0
        dealt = min(total, enemy["hp"])
        for index, amount in credits.items():
            part = dealt * amount / total
            run_damage[index] += part
            tally[index] += part
        enemy["hp"] -= total
        if enemy["hp"] > 0:
            return dealt
        group = enemy["group"]
        group["dead"] += 1
        group["pool"]["cash"] += enemy["cash"]
        group["pool"]["materials"] += enemy["materials"]
        group["pool"]["kills"] += 1
        if enemy["boss"]:
            group["pool"]["valor"] += boss_valor(mission, group["wave"], overdrive, combat_cfg)
        kills_by_key[enemy["key"]] = kills_by_key.get(enemy["key"], 0) + 1
        kill_times.append(t)
        # A kill shortens the killer's two cooldowns (CombatService.onEnemyKilled).
        killer = max(credits, key=lambda index: (credits[index], -index))
        for slot in ready_at[killer]:
            ready_at[killer][slot] -= refund
        alive.remove(enemy)
        return dealt

    def mult(index):
        return empower_mult[index] if t < empowered_until[index] else 1.0

    def cast_party_effect(caster):
        nonlocal hp, rally_healed
        effect = effects[caster]
        if effect is None or party < 2:
            return
        effect_casts[effect["kind"]] = effect_casts.get(effect["kind"], 0) + 1
        if effect["kind"] == "rally":
            # Every other member heals healFraction of max HP; in the pooled bar
            # that is (n - 1) / n of it. The radius is assumed to cover the scrum.
            before = hp
            hp = min(float(hp_max), hp + effect["healFraction"] * hp_max * (party - 1) / party)
            rally_healed += hp - before
        elif effect["kind"] == "warcry":
            for index in range(party):
                if index != caster:
                    empowered_until[index] = t + effect["seconds"]
                    empower_mult[index] = effect["damageMult"]

    def flush(group):
        total = sum(tally)
        by_user = {i: tally[i] for i in range(party)}
        shares = contribution_shares(by_user, floor_share)
        for index, share in split_pool(group["pool"], shares).items():
            if members[index]["bot"]:
                continue  # bots' shares are discarded
            # Double floor, exactly as Waves section 6 credits it: SplitPool
            # floors pool.cash x share, then the caller floors that share
            # again against CombatCashMult. `cash_mult` is 1.0 for every run
            # the tool reports (legacy 0, no Founder's Blessing).
            cash = math.floor(share["cash"] * cash_mult)
            earned[index]["cash"] += cash
            earned[index]["materials"] += share["materials"]
            earned[index]["valor"] += share["valor"]
            payout["cash"] += cash
            payout["materials"] += share["materials"]
            payout["valor"] += share["valor"]
        if group["boss"] and total > 0:
            for host in range(party):
                if members[host]["bot"]:
                    continue  # bots are never mentors
                if tally[host] / total < min_mentee_share:
                    # Lead ruling (C2 review): a mentor must have fought too --
                    # an idle high-income player in the run earns nothing. The
                    # sim has no `waiting` state; a waiting member deals 0 and
                    # fails this same test.
                    mentor_events.append(
                        {
                            "wave": group["wave"],
                            "host": host,
                            "bonus": 0,
                            "shares": [tally[j] / total for j in range(party)],
                        }
                    )
                    continue
                mentee_rates = [
                    members[j]["rate"]
                    for j in range(party)
                    if j != host and tally[j] / total >= min_mentee_share
                ]
                bonus = mentor_bonus(combat_cfg, members[host]["rate"], mentee_rates)
                if bonus > 0:
                    earned[host]["mentor"] += bonus
                    earned[host]["valor"] += bonus
                    payout["valor"] += bonus
                mentor_events.append(
                    {
                        "wave": group["wave"],
                        "host": host,
                        "bonus": bonus,
                        "shares": [tally[j] / total for j in range(party)],
                    }
                )
        for index in range(party):
            tally[index] = 0.0

    start_wave(1, False)
    while end_reason is None:
        # Tempo: kills inside the rolling window against the wave's expected pace.
        while kill_times and kill_times[0] <= t - window:
            kill_times.pop(0)
        reference = (
            groups[-1]["spec"]["count"]
            if groups
            else counts.get(min(next_wave, mission["waves"]), 1)
        )
        expected = reference / mission["targetWaveSeconds"]
        tempo_value = (
            1.0 if t < warmup else tempo(len(kill_times), window, expected, director)
        )

        if breather_end is not None:
            hp = min(float(hp_max), hp + player_cfg["breatherRegenPerSecond"] * DT)
            breather_total += DT
            if t >= breather_end:
                breather_end = None
                start_wave(next_wave, False)
        else:
            for group in groups:
                group["tempo_sum"] += tempo_value
                group["ticks"] += 1
                while (
                    group["spawned"] < group["count"]
                    and t >= group["next_spawn"]
                    and len(alive) < director["maxAlive"]
                ):
                    spawn(group)
                    group["next_spawn"] = t + spawn_interval(
                        mission, group["spec"], tempo_value, overdrive, combat_cfg
                    )
                if group["spawned"] >= group["count"] and group["dead_at_spawn_end"] is None:
                    group["dead_at_spawn_end"] = group["dead"] / max(group["count"], 1)
                    group["tempo_at_spawn_end"] = tempo_value

            # The merge is decided ONCE, at the instant the wave finishes
            # spawning ("once the wave has finished spawning" in the contract).
            # That single reading is what makes it a skill test: the deadFraction
            # at that instant is (count - enemies still in flight) / count, so a
            # party that is one enemy behind reads ~0.86 and a party that is
            # three behind reads ~0.6. Re-checking every tick afterwards would
            # instead let every wave drift up to 1.0 and merge unconditionally.
            newest = groups[-1] if groups else None
            if (
                newest is not None
                and not newest["merge_done"]
                and newest["dead_at_spawn_end"] is not None
            ):
                if MERGE_CHECK_CONTINUOUS:
                    fraction = newest["dead"] / max(newest["count"], 1)
                    if should_merge(tempo_value, fraction, director):
                        newest["merge_done"] = True
                        if next_wave <= mission["waves"]:
                            merges += 1
                            start_wave(next_wave, True)
                else:
                    newest["merge_done"] = True
                    if next_wave <= mission["waves"] and should_merge(
                        tempo_value, newest["dead_at_spawn_end"], director
                    ):
                        merges += 1
                        start_wave(next_wave, True)

            # Target priority, the greedy player's: ordinary enemies before the
            # boss, the squishiest first (archers, then raiders, then brutes),
            # oldest to break ties. The melee term only lands once that target is
            # inside the weapon's reach; the ranged term always applies. The whole
            # party focuses the same target (the pooled-position model).
            if alive:
                target = min(alive, key=lambda e: (e["boss"], e["max_hp"], e["seq"]))
                credits = {}
                for index, model in enumerate(models):
                    amount = model["ranged_dps"] * DT
                    if target["dist"] <= engages[index]:
                        amount += model["melee_dps"] * DT
                    if amount > 0:
                        credits[index] = amount * mult(index)
                hit(target, credits)
            for index, model in enumerate(models):
                for ability in model["abilities"]:
                    if alive and t >= ready_at[index][ability["slot"]]:
                        damage = ability["damage"] * mult(index)
                        for enemy in ability_targets(ability, list(alive)):
                            ability_damage_total += hit(enemy, {index: damage})
                        ready_at[index][ability["slot"]] = t + ability["cooldown"]
                        if ability["slot"] == "melee":
                            cast_party_effect(index)

            if any(enemy["boss"] for enemy in alive):
                boss_seconds += DT
                for enemy in alive:
                    if enemy["boss"]:
                        wave = enemy["group"]["wave"]
                        boss_seconds_by_wave[wave] = boss_seconds_by_wave.get(wave, 0.0) + DT
            incoming = 0.0
            melee_slots = MELEE_CONTACT_SLOTS * party
            melee_used = 0
            # Bosses take a ring slot first, then the oldest arrivals.
            for enemy in sorted(alive, key=lambda e: (not e["boss"], e["seq"])):
                if enemy["dist"] > enemy["reach"]:
                    enemy["dist"] = max(enemy["reach"], enemy["dist"] - enemy["speed"] * DT)
                    if enemy["dist"] <= enemy["reach"]:
                        enemy["next_attack"] = t + enemy_cfg["attackWindupSeconds"]
                if enemy["dist"] > enemy["reach"] or enemy["next_attack"] is None:
                    continue
                if enemy["kind"] == "melee":
                    if melee_used >= melee_slots:
                        # Queued outside the ring: it cannot reach the player yet.
                        enemy["next_attack"] += DT
                        continue
                    melee_used += 1
                if t >= enemy["next_attack"]:
                    incoming += enemy["damage"] * enemy["land"]
                    enemy["next_attack"] += enemy["cooldown"]
            hp -= incoming / party
            hp_floor = min(hp_floor, hp)
            damage_taken += incoming / party

            for group in list(groups):
                if group["spawned"] < group["count"]:
                    continue
                if any(enemy["group"] is group for enemy in alive):
                    continue
                flush(group)
                payout["kills"] += group["pool"]["kills"]
                rows.append(
                    {
                        "wave": group["wave"],
                        "start": group["start"],
                        "end": t,
                        "count": group["count"],
                        "merged": group["merged"],
                        "boss": group["boss"],
                        "boss_hp": group["boss_hp"],
                        "hp": hp,
                        "cash": group["pool"]["cash"],
                        "materials": group["pool"]["materials"],
                        "valor": group["pool"]["valor"],
                        "kills": group["pool"]["kills"],
                        "taken": damage_taken - group["taken_at_start"],
                        "tempo": group["tempo_sum"] / max(group["ticks"], 1),
                        "dead_at_spawn_end": group["dead_at_spawn_end"],
                        "tempo_at_spawn_end": group["tempo_at_spawn_end"],
                        "cleared": True,
                    }
                )
                groups.remove(group)

            if hp <= 0:
                end_reason = "died"
                died_wave = max(
                    (g["wave"] for g in groups),
                    default=(rows[-1]["wave"] if rows else 1),
                )
            elif not groups:
                if next_wave > mission["waves"]:
                    end_reason = "cleared"
                else:
                    breather_end = t + breather_seconds(tempo_value, director)

        t += DT
        if end_reason is None and t >= director["runCapSeconds"]:
            end_reason = "cap"

    for group in groups:
        rows.append(
            {
                "wave": group["wave"],
                "start": group["start"],
                "end": t,
                "count": group["count"],
                "merged": group["merged"],
                "boss": group["boss"],
                "boss_hp": group["boss_hp"],
                "hp": hp,
                "cash": group["pool"]["cash"],
                "materials": group["pool"]["materials"],
                "valor": group["pool"]["valor"],
                "kills": group["pool"]["kills"],
                "taken": damage_taken - group["taken_at_start"],
                "tempo": group["tempo_sum"] / max(group["ticks"], 1),
                "dead_at_spawn_end": group["dead_at_spawn_end"],
                "tempo_at_spawn_end": group["tempo_at_spawn_end"],
                "cleared": False,
            }
        )
    rows.sort(key=lambda row: (row["wave"], row["start"]))
    total_damage = sum(run_damage)
    totals = {
        "seconds": t,
        "cash": payout["cash"],
        "materials": payout["materials"],
        "valor": payout["valor"],
        "kills": payout["kills"],
        "kills_by_key": kills_by_key,
        "dps": sum(model["dps"] for model in models) / party,
        "melee_dps": sum(model["melee_dps"] for model in models) / party,
        "ranged_dps": sum(model["ranged_dps"] for model in models) / party,
        "ability_damage": ability_damage_total,
        "max_hp": hp_max,
        "power": gear_power(armory, members[0]["gear"], members[0]["ascension"]),
        "hp_left": hp,
        "hp_floor": hp_floor,
        "damage_taken": damage_taken,
        "breather_seconds": breather_total,
        "boss_seconds": boss_seconds,
        "boss_seconds_by_wave": boss_seconds_by_wave,
        "merges": merges,
        "waves_cleared": sum(1 for row in rows if row["cleared"]),
        "died": end_reason == "died",
        "died_wave": died_wave,
        "end_reason": end_reason,
        "party": party,
        "members": [
            dict(
                earned[i],
                damage_share=(run_damage[i] / total_damage if total_damage > 0 else 0.0),
                rate=members[i]["rate"],
                bot=members[i]["bot"],
            )
            for i in range(party)
        ],
        "mentor_events": mentor_events,
        "effect_casts": effect_casts,
        "rally_healed": rally_healed,
    }
    return rows, totals


# --------------------------------------------------------------------------
# Reports
# --------------------------------------------------------------------------


def fmt_rate(value):
    return f"{se.fmt_cash(value)}/s"


def run_clock(curve, second):
    return se.fmt_time(curve.offset + second)


def print_unlock_table(armory, curves, missions):
    print("Armory unlock ladder -- when the greedy player's persisted rate opens each tier")
    print("(melee and ranged ladders are identical per tier; unlockRate is income per second)")
    print(
        f"  {'tier':>4} {'band':>4} {'material':<9} {'cost':>5} {'unlockRate':>11} "
        f"{'crossed in':<14} {'at':>8} {'run clock':>10} {'power':>6} {'dps':>8}"
    )
    for gear in symmetric_loadouts(armory):
        tier = gear["melee"]
        if tier == 0:
            continue
        definition = tier_def(armory, "melee", tier)
        rate = tier_unlock_rate(armory, "melee", tier)
        material, cost = tier_cost(armory, "melee", tier)
        curve, second = first_crossing(curves, rate)
        where = curve.era["name"] if curve else "never"
        at = se.fmt_time(second) if curve else "-"
        clock = run_clock(curve, second) if curve else "-"
        melee, ranged = loadout_dps(armory, gear, NO_ASCENSION)
        print(
            f"  {tier:>4} {definition['band']:>4} {material:<9} {cost:>5} "
            f"{se.fmt_cash(rate):>11} {where:<14} {at:>8} {clock:>10} "
            f"{gear_power(armory, gear, NO_ASCENSION):>6} {melee + ranged:>8.1f}"
        )
    print()
    print("  band entry tiers (the pacing beats) and the era they land in:")
    for entry in armory["bands"]:
        band = entry["band"]
        tiers = [t["tier"] for t in armory["slots"]["melee"]["tiers"] if t["band"] == band]
        if not tiers:
            continue
        first = min(tiers)
        rate = tier_unlock_rate(armory, "melee", first)
        curve, second = first_crossing(curves, rate)
        note = "never reached"
        if curve is not None:
            note = f"{100 * second / curve.seconds:.0f}% into {curve.era['name']}"
            if curve.era["name"] != entry["eraName"]:
                note += f"  <-- expected {entry['eraName']}"
        print(
            f"    band {band} ({entry['eraName']}, {entry['material']}): tier {first} "
            f"at {fmt_rate(rate)} -> {note}"
        )
    print()
    print("  era income envelope (greedy, legacy carried):")
    for curve in curves:
        print(
            f"    {curve.era['name']:<14} {se.fmt_time(curve.seconds):>8}  "
            f"start {fmt_rate(curve.ips[0]):>11}  median {fmt_rate(curve.median()):>11}  "
            f"peak {fmt_rate(curve.peak):>11}"
        )
    missing = [c.index for c in curves if c.index not in missions]
    if missing:
        print(f"  note: no mission config for era(s) {missing} yet (C1/C3 add them).")
    print()


def print_run(
    mission, armory, combat_cfg, gear, ascension, party, overdrive, label, judge=True, trace=False
):
    rows, totals = simulate_run(mission, armory, combat_cfg, gear, ascension, party, overdrive)
    melee_name = tier_def(armory, "melee", gear["melee"])["name"]
    ranged_name = tier_def(armory, "ranged", gear["ranged"])["name"]
    target = mission["targetMinutes"] * 60
    low = target * (1 - RUN_TIME_TOLERANCE)
    high = target * (1 + RUN_TIME_TOLERANCE)
    print(
        f"{mission['name']} ({mission['id']}, era {mission['era']}) -- {label}"
        f"{'  OVERDRIVE' if overdrive else ''}"
    )
    print(
        f"  loadout   : tier {gear['melee']}/{gear['ranged']} "
        f"{melee_name} + {ranged_name}, power {totals['power']} "
        f"(recommended {recommended_power(mission, overdrive, combat_cfg):g}), "
        f"max HP {totals['max_hp']:g}"
    )
    print(
        f"  DPS       : {totals['dps']:.1f} "
        f"(melee {totals['melee_dps']:.1f} + ranged {totals['ranged_dps']:.1f}) "
        f"+ abilities, party {party}"
    )
    print(
        f"  {'wave':>4} {'start':>7} {'end':>7} {'len':>6} {'n':>4} {'flags':<10} "
        f"{'tempo':>6} {'dmg in':>7} {'cash':>10} {'mats':>6} {'HP left':>9}"
    )
    for row in rows:
        flags = []
        if row["merged"]:
            flags.append("merged")
        if row["boss"]:
            flags.append("BOSS")
        if not row["cleared"]:
            flags.append(totals["end_reason"] or "-")
        length = row["end"] - row["start"]
        print(
            f"  {row['wave']:>4} {row['start']:>7.1f} {row['end']:>7.1f} "
            f"{length:>6.1f} {row['count']:>4} {'+'.join(flags):<10} "
            f"{row['tempo']:>6.2f} {row['taken']:>7.0f} "
            f"{row['cash']:>10,} {row['materials']:>6,} "
            f"{row['hp']:>8.0f}/{totals['max_hp']:g}"
        )
    status = "OK" if low <= totals["seconds"] <= high else "MISS"
    if not judge:
        status += " (informational -- only the recommended-power run is asserted)"
    ended = {
        "cleared": f"cleared all {mission['waves']} waves",
        "died": f"DIED on wave {totals['died_wave']}",
        "cap": f"hit the {combat_cfg['director']['runCapSeconds']}s run cap",
    }[totals["end_reason"]]
    print(
        f"  total     : {se.fmt_time(totals['seconds'])} wall clock "
        f"({totals['seconds']:.0f}s, {totals['breather_seconds']:.0f}s of it breathers), "
        f"{ended}"
    )
    print(
        f"  target    : {mission['targetMinutes']} min "
        f"({se.fmt_time(low)}-{se.fmt_time(high)} at +-50%): {status}"
    )
    cleared = [r for r in rows if r["cleared"]]
    lengths = [r["end"] - r["start"] for r in cleared] or [0]
    print(
        f"  waves     : {totals['waves_cleared']} cleared, mean "
        f"{sum(lengths) / len(lengths):.1f}s (target {mission['targetWaveSeconds']}s), "
        f"longest {max(lengths):.1f}s; {totals['merges']} merge(s); bosses "
        f"{totals['boss_seconds']:.0f}s ({100 * totals['boss_seconds'] / totals['seconds']:.0f}% "
        f"of the run)"
    )
    print(
        f"  health    : took {totals['damage_taken']:,.0f} damage, floor "
        f"{totals['hp_floor']:.0f}/{totals['max_hp']:g} "
        f"({100 * totals['hp_floor'] / totals['max_hp']:.0f}%), ended at "
        f"{totals['hp_left']:.0f}"
    )
    by_key = ", ".join(f"{key} {n}" for key, n in sorted(totals["kills_by_key"].items()))
    print(
        f"  rewards   : {totals['cash']:,} cash, {totals['materials']:,} "
        f"{mission['material']}, {totals['valor']} Valor, {totals['kills']} kills ({by_key})"
    )
    print(
        f"  abilities : {totals['ability_damage']:,.0f} damage "
        f"({100 * totals['ability_damage'] / max(sum_enemy_hp(rows, totals), 1):.0f}% of the "
        f"HP destroyed)"
    )
    cap = combat_cfg["director"]["runCapSeconds"]
    print(
        f"  run cap   : {cap}s -- "
        + ("fits" if totals["seconds"] <= cap else "OVER, the run would be cut short")
    )
    if trace:
        print(
            "  trace     : wave / start s / count / merged? / boss? / end s / HP left "
            "(the table above is that trace)"
        )
    return rows, totals


def sum_enemy_hp(rows, totals):
    """Total enemy HP destroyed, inferred from the run's damage accounting: the
    player's sustained DPS is not tracked per enemy, so the ability share is
    reported against the HP the run actually removed."""
    return totals["dps"] * (totals["seconds"] - totals["breather_seconds"]) + totals[
        "ability_damage"
    ]


def print_cash_ratio(mission, armory, curves, totals):
    """Combat cash must stay a garnish on the tycoon, never a shortcut."""
    curve = next((c for c in curves if c.index == mission["era"]), None)
    if curve is None:
        print("Cash vs era cost -- no greedy curve for this era")
        print()
        return None
    gear, _ = gear_for_power(armory, mission["recommendedPower"])
    rate = max(
        tier_unlock_rate(armory, "melee", gear["melee"]),
        tier_unlock_rate(armory, "ranged", gear["ranged"]),
    )
    second = curve.crossing(rate)
    if second is None:
        second = curve.seconds // 2
    remaining = curve.remaining_slot_cost(second)
    mid_remaining = curve.remaining_slot_cost(curve.seconds // 2)
    ratio = totals["cash"] / remaining if remaining > 0 else float("inf")
    print(f"Cash vs era cost -- {curve.era['name']}")
    print(
        f"  reference moment : {se.fmt_time(second)} "
        f"(the greedy rate reaches {fmt_rate(rate)}, the recommended loadout's gate)"
    )
    print(
        f"  era slot cost    : {totals['cash']:,.0f} run cash vs "
        f"{remaining:,.0f} remaining of {curve.total_slot_cost:,.0f}"
    )
    print(
        f"  ratio            : {100 * ratio:.2f}% of remaining "
        f"(cap {100 * RUN_CASH_CAP_FRACTION:.0f}%), "
        f"{100 * totals['cash'] / curve.total_slot_cost:.2f}% of the era total"
    )
    print(
        f"  mid-era          : {100 * totals['cash'] / mid_remaining:.2f}% of the "
        f"{mid_remaining:,.0f} still owed at {se.fmt_time(curve.seconds // 2)}"
    )
    print(
        f"  in income terms  : {totals['cash'] / curve.median():.0f}s of the era's "
        f"median rate {fmt_rate(curve.median())}"
    )
    print()
    return ratio


def print_survivability(combat_cfg, rows, totals):
    """Measured, not modelled: the run simulator tracks HP tick by tick, so this
    is the actual damage taken with the actual regen, per wave."""
    player_cfg = combat_cfg["player"]
    print("Survivability (measured by the run simulator, standing player = upper bound)")
    print(
        f"  damage taken     : {totals['damage_taken']:,.0f} over "
        f"{se.fmt_time(totals['seconds'])} at {totals['max_hp']:g} max HP "
        f"({totals['damage_taken'] / totals['max_hp']:.1f} full health bars)"
    )
    print(
        f"  regen            : {player_cfg['breatherRegenPerSecond']:g} HP/s x "
        f"{totals['breather_seconds']:.0f}s of breathers = "
        f"{player_cfg['breatherRegenPerSecond'] * totals['breather_seconds']:,.0f} HP "
        f"(capped at max HP each time)"
    )
    print(
        f"  lowest HP        : {totals['hp_floor']:.0f} "
        f"({100 * totals['hp_floor'] / totals['max_hp']:.0f}% of max; the "
        f"feedback.lowHpFraction vignette trips at "
        f"{100 * combat_cfg['feedback']['lowHpFraction']:.0f}%)"
    )
    worst = min(rows, key=lambda row: row["hp"])
    print(
        f"  tightest wave    : wave {worst['wave']} ended at {worst['hp']:.0f} HP"
        + (f"; ran out on wave {totals['died_wave']}" if totals["died"] else "")
    )
    print()


def print_coop(mission, armory, combat_cfg, overdrive):
    """C2: the party table (equal members at the recommended power) and the
    Mentor Valor a mixed-rate party earns per run. Everything is per player."""
    coop = combat_cfg["coop"]
    gear, _ = gear_for_power(armory, recommended_power(mission, overdrive, combat_cfg))
    print(
        f"Co-op -- {mission['name']}, everyone at the recommended power "
        f"(bossHpPerExtraPlayer {coop['bossHpPerExtraPlayer']}, "
        f"countPerExtraPlayer {coop['countPerExtraPlayer']})"
    )
    print(
        f"  {'party':>5} {'result':<8} {'run':>6} {'boss5':>6} {'boss10':>7} {'boss HP':>13} "
        f"{'cash/p':>9} {'mats/p':>7} {'valor/p':>8} {'HP floor':>9}"
    )
    for party in range(1, coop["maxParty"] + 1):
        rows, totals = simulate_run(
            mission, armory, combat_cfg, gear, NO_ASCENSION, party, overdrive
        )
        boss_hp = "/".join(str(row["boss_hp"]) for row in rows if row["boss"])
        by_wave = totals["boss_seconds_by_wave"]
        waves = sorted(int(w) for w in mission["bosses"])
        print(
            f"  {party:>5} {totals['end_reason']:<8} {se.fmt_time(totals['seconds']):>6} "
            f"{by_wave.get(waves[0], 0):>5.1f}s {by_wave.get(waves[-1], 0):>6.1f}s "
            f"{boss_hp:>13} {totals['cash'] // party:>9,} {totals['materials'] // party:>7,} "
            f"{totals['valor'] / party:>8.1f} {100 * totals['hp_floor'] / totals['max_hp']:>8.0f}%"
        )
    strong, _ = gear_for_power(armory, STRONG_POWER_MULT * mission["recommendedPower"])
    starter = {"melee": 0, "ranged": 0}
    host = MENTOR_HOST_RATE
    newbie = host / MENTOR_RATE_RATIO
    scenarios = [
        ("veteran + starter-gear newbie", [(gear, host, False), (starter, newbie, False)]),
        ("veteran + equal-rate friend", [(gear, host, False), (gear, host, False)]),
        ("2x veteran + three newbies", [(strong, host, False)] + [(starter, newbie, False)] * 3),
        (
            "three 2x veterans + one newbie",
            [(strong, host, False)] * 3 + [(starter, newbie, False)],
        ),
        ("veteran + idle alt", [(gear, host, False), (gear, newbie, True)]),
        ("idle veteran + newbie", [(gear, host, True), (starter, newbie, False)]),
    ]
    print(
        f"  Mentor Valor per run (mentorValor {coop['mentorValor']} per mentee per boss clear, "
        f"mentee rate < {coop['mentorRatio']} x host, mentor and mentee shares >= "
        f"{coop['mentorMinDamageShare']:.0%} of the boss flush; host {se.fmt_cash(host)}/s, "
        f"newbie {se.fmt_cash(newbie)}/s)"
    )
    for label, specs in scenarios:
        members = [
            {"gear": dict(g), "ascension": dict(NO_ASCENSION), "rate": r, "bot": False, "idle": i}
            for g, r, i in specs
        ]
        _, totals = simulate_run(
            mission, armory, combat_cfg, None, None, len(members), overdrive, members=members
        )
        parts = ", ".join(
            f"{'idle' if specs[i][2] else 'm' + str(i + 1)} {m['damage_share']:.0%} dmg "
            f"{m['valor']} Valor ({m['mentor']} Mentor)"
            for i, m in enumerate(totals["members"])
        )
        print(f"    {label:<32} {parts}")
    print()


def print_helpers(armory, combat_cfg, game, shop):
    """Spot checks of the shared helpers that have no pacing table of their own."""
    print("Shared-module spot checks")
    floor = combat_cfg["coop"]["contributionFloor"]
    shares = contribution_shares({1: 10.0, 2: 1.0}, floor)
    print(
        f"  ContributionShares 10:1 duo -> veteran {shares[1]:.1%}, "
        f"rookie {shares[2]:.1%} (floor {floor})"
    )
    equal = contribution_shares({1: 0.0, 2: 0.0, 3: 0.0}, floor)
    print(f"  ContributionShares zero-damage trio -> {equal[1]:.1%} each")
    base = game["offline"]["efficiency"]
    expedition = combat_cfg["offline"]["expeditionEfficiency"]
    print(
        f"  AwayEfficiency 1 h away: 0 s expedition -> "
        f"{away_efficiency(3600, 0, base, expedition):.2f}, 1 h expedition -> "
        f"{away_efficiency(3600, 3600, base, expedition):.2f}, 30 min -> "
        f"{away_efficiency(3600, 1800, base, expedition):.2f}"
    )
    print(
        f"  MentorBonus host 50K/s, party 1K/s + 40K/s -> "
        f"{mentor_bonus(combat_cfg, 50000, [1000, 40000])} Valor "
        f"(ratio {combat_cfg['coop']['mentorRatio']})"
    )
    director = combat_cfg["director"]
    print(
        f"  Tempo 30 kills / {director['windowSeconds']}s vs 1.0 expected -> "
        f"{tempo(30, director['windowSeconds'], 1.0, director):.2f}; "
        f"0 expected -> {tempo(0, director['windowSeconds'], 0, director):.2f}"
    )
    print(f"  AscensionCap by rebirthCount 0..4 -> {[ascension_cap(armory, r) for r in range(5)]}")
    top = symmetric_loadouts(armory)[-1]
    for level in range(1, len(armory["ascension"]["levels"]) + 1):
        cost = ascension_cost(armory, level)
        materials = " + ".join(f"{amount} {name}" for name, amount in cost["materials"].items())
        power = gear_power(armory, top, {"melee": level, "ranged": level})
        print(
            f"  Ascension {level}: {materials}, {cost['valor']} Valor -> top-tier power "
            f"{power} (x{power / gear_power(armory, top, NO_ASCENSION):.2f})"
        )
    state = {
        "era": 1,
        "rebirthCount": 0,
        "legacy": 0,
        "legacyShop": se.empty_shop_state(),
        "combat": new_combat_profile(),
    }
    print(f"  CombatCashMult at legacy 0 -> x{combat_cash_mult(state, game, shop):.2f}")
    state["legacy"] = 261
    print(
        f"  CombatCashMult at legacy 261 (era 3 entry) -> "
        f"x{combat_cash_mult(state, game, shop):.2f}"
    )
    state["combat"]["materials"]["Timber"] = 10
    print(f"  CanBuy melee tier 1 with 10 Timber at 0/s -> {can_buy(armory, state, 'melee', 0)}")
    state["combat"]["gear"]["melee"] = 1
    print(f"  CanBuy melee tier 2 at 0/s -> {can_buy(armory, state, 'melee', 0)}")
    print(f"  CanAscend at rebirthCount 0 -> {can_ascend(armory, state, 'melee')}")
    state["era"] = 3
    touch_highest_era(state)
    print(f"  TouchHighestEra at era 3 -> highestEra {state['combat']['highestEra']}")
    for mission in sorted(load_missions().values(), key=lambda m: m["era"]):
        print(
            f"  MissionUnlocked {mission['id']} at highestEra "
            f"{state['combat']['highestEra']}, rebirth {state['rebirthCount']}: plain "
            f"{mission_unlocked(state, mission, False, combat_cfg)}, overdrive "
            f"{mission_unlocked(state, mission, True, combat_cfg)}"
        )
    # The degrade-quietly guards, mirrored from Armory.luau / Combat.luau.
    missions = load_missions()
    village = missions.get(1)
    party_note = ""
    if village is not None:
        party_note = (
            f"; WaveSpec party 0 vs party 1 count "
            f"{wave_spec(village, 1, 0, False, combat_cfg)['count']}"
            f"/{wave_spec(village, 1, 1, False, combat_cfg)['count']}"
        )
    print(
        f"  Guards: Tempo window 0s -> {tempo(30, 0, 1.0, director):.2f}; "
        f"AwayEfficiency stamp -60s -> {away_efficiency(3600, -60, base, expedition):.2f}, "
        f"stamp 2h in a 1h absence -> {away_efficiency(3600, 7200, base, expedition):.2f}; "
        f"WeaponDamage melee tier 2 at ascension 9 -> "
        f"{weapon_damage(armory, 'melee', 2, 9):g} (neutral x1, not clamped to level 3); "
        f"AscensionCost level 9 -> {ascension_cost(armory, 9)}{party_note}"
    )
    starter_ability = armory["slots"]["melee"]["tiers"][0]["ability"]
    definition = ability_def(armory, starter_ability)
    print(
        f"  AbilityDef {starter_ability} -> {definition['kind']}, "
        f"x{definition['damageMult']} on a {definition['cooldown']}s cooldown "
        f"(not in the DPS model)"
    )
    print()


# --------------------------------------------------------------------------
# --check: the C0 + C1 + C2 assertions in docs/INTERFACES.md
# --------------------------------------------------------------------------


def boss_wave_lengths(mission, armory, combat_cfg, gear, party):
    """{boss wave: seconds from its start to its clear} for an equal party."""
    rows, _ = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, party, False)
    return {
        row["wave"]: row["end"] - row["start"] for row in rows if row["boss"] and row["cleared"]
    }


def mentor_run(mission, armory, combat_cfg, specs):
    """The Mentor events of one run; `specs` = [(gear, incomeRate, idle)]."""
    members = [
        {"gear": dict(g), "ascension": dict(NO_ASCENSION), "rate": rate, "bot": False, "idle": idle}
        for g, rate, idle in specs
    ]
    _, totals = simulate_run(
        mission, armory, combat_cfg, None, None, len(members), False, members=members
    )
    return totals["mentor_events"]


def first_boss_flush(events):
    return min((e["wave"] for e in events), default=None)


class Checks:
    def __init__(self):
        self.failed = 0

    def verdict(self, ok, name, detail):
        if not ok:
            self.failed += 1
        print(f"  {'PASS' if ok else 'FAIL'}  {name}: {detail}")


def run_checks(armory, combat_cfg, places, missions, game, eras):
    checks = Checks()
    print("sim_combat --check (docs/INTERFACES.md C0 + C1 + C2 contracts, thirteen assertions)")
    curves = greedy_curves(game, eras)

    # 1. unlockRate non-decreasing per slot; each band's entry tier unlocks inside its era.
    problems = []
    for slot in ("melee", "ranged"):
        previous = -1
        for definition in armory["slots"][slot]["tiers"]:
            rate = definition["unlockRate"]
            if rate < previous:
                problems.append(f"{slot} tier {definition['tier']} rate drops to {rate}")
            previous = rate
    band_notes = []
    for entry in armory["bands"]:
        tiers = [t for t in armory["slots"]["melee"]["tiers"] if t["band"] == entry["band"]]
        if not tiers:
            continue
        first = min(tiers, key=lambda t: t["tier"])
        curve, second = first_crossing(curves, first["unlockRate"])
        if curve is None:
            problems.append(
                f"band {entry['band']} tier {first['tier']} rate "
                f"{se.fmt_cash(first['unlockRate'])}/s is never reached"
            )
            continue
        if curve.era["name"] != entry["eraName"]:
            problems.append(
                f"band {entry['band']} tier {first['tier']} unlocks in "
                f"{curve.era['name']}, not {entry['eraName']}"
            )
        band_notes.append(
            f"b{entry['band']}t{first['tier']} {curve.era['name']} "
            f"{se.fmt_time(second)} ({100 * second / curve.seconds:.0f}%)"
        )
    checks.verdict(
        not problems,
        "1 unlock ladder    ",
        "; ".join(problems)
        if problems
        else "monotonic, every band entry inside its era -- " + ", ".join(band_notes),
    )

    # 2. At each era's median greedy rate, the unlocked gear meets recommendedPower.
    details = []
    ok2 = True
    for curve in curves:
        mission = missions.get(curve.index)
        if mission is None:
            details.append(f"{curve.era['name']} no mission (skipped)")
            continue
        gear = highest_unlocked_gear(armory, curve.median())
        power = gear_power(armory, gear, NO_ASCENSION)
        needed = recommended_power(mission, False, combat_cfg)
        if power < needed:
            ok2 = False
        details.append(
            f"{curve.era['name']} median {fmt_rate(curve.median())} -> tier "
            f"{gear['melee']}/{gear['ranged']} power {power} vs recommended {needed:g}"
        )
    checks.verdict(ok2, "2 power at median  ", "; ".join(details))

    # 3. Simulated run at recommended power clears every wave inside targetMinutes +-50 %.
    details = []
    ok3 = True
    baselines = {}
    for curve in curves:
        mission = missions.get(curve.index)
        if mission is None:
            continue
        gear, power = gear_for_power(armory, mission["recommendedPower"])
        _, totals = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
        baselines[mission["id"]] = totals
        target = mission["targetMinutes"] * 60
        inside = (
            target * (1 - RUN_TIME_TOLERANCE)
            <= totals["seconds"]
            <= target * (1 + RUN_TIME_TOLERANCE)
        )
        cleared = totals["waves_cleared"] >= mission["waves"]
        ok3 = ok3 and inside and cleared
        details.append(
            f"{mission['id']} {totals['waves_cleared']}/{mission['waves']} waves in "
            f"{se.fmt_time(totals['seconds'])} vs target {mission['targetMinutes']} min "
            f"at power {power} ({totals['end_reason']}, HP floor "
            f"{100 * totals['hp_floor'] / totals['max_hp']:.0f}%)"
        )
    checks.verdict(ok3, "3 run length       ", "; ".join(details) or "no missions to model")

    # 4. Run cash <= 25 % of the era's remaining slot cost at that point in the greedy run.
    details = []
    ok4 = True
    for curve in curves:
        mission = missions.get(curve.index)
        if mission is None:
            continue
        gear, _ = gear_for_power(armory, mission["recommendedPower"])
        totals = baselines.get(mission["id"])
        if totals is None:
            _, totals = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
        rate = max(
            tier_unlock_rate(armory, "melee", gear["melee"]),
            tier_unlock_rate(armory, "ranged", gear["ranged"]),
        )
        second = curve.crossing(rate)
        second = curve.seconds // 2 if second is None else second
        remaining = curve.remaining_slot_cost(second)
        ratio = totals["cash"] / remaining if remaining > 0 else float("inf")
        ok4 = ok4 and ratio <= RUN_CASH_CAP_FRACTION
        details.append(
            f"{mission['id']} {totals['cash']:,.0f} cash = {100 * ratio:.2f}% of "
            f"{remaining:,.0f} remaining at {se.fmt_time(second)}"
        )
    checks.verdict(ok4, "4 cash vs era cost ", "; ".join(details) or "no missions to model")

    # 5. ContributionShares, 10:1 duo, veteran >= 75 %.
    floor = combat_cfg["coop"]["contributionFloor"]
    shares = contribution_shares({1: 10.0, 2: 1.0}, floor)
    checks.verdict(
        shares[1] >= VETERAN_SHARE_FLOOR,
        "5 contribution     ",
        f"veteran {shares[1]:.1%} of a 10:1 duo "
        f"(floor {floor}, needs >= {VETERAN_SHARE_FLOOR:.0%})",
    )

    # 6. AwayEfficiency endpoints.
    base = game["offline"]["efficiency"]
    expedition = combat_cfg["offline"]["expeditionEfficiency"]
    none_away = away_efficiency(3600, 0, base, expedition)
    all_away = away_efficiency(3600, 3600, base, expedition)
    checks.verdict(
        abs(none_away - base) < 1e-9 and abs(all_away - expedition) < 1e-9,
        "6 away efficiency  ",
        f"0 s expedition -> {none_away:.2f} (base {base}), whole absence -> "
        f"{all_away:.2f} (expedition {expedition})",
    )

    # 7. Twice the recommended power makes the director merge at least one wave.
    details = []
    ok7 = True
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        gear, power = gear_for_power(armory, STRONG_POWER_MULT * mission["recommendedPower"])
        _, totals = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
        ok7 = ok7 and totals["merges"] >= 1
        details.append(
            f"{mission['id']} power {power} -> {totals['merges']} merge(s), "
            f"{se.fmt_time(totals['seconds'])}"
        )
    checks.verdict(ok7, "7 merge at 2x      ", "; ".join(details) or "no missions to model")

    # 8. Under-geared (0.6x) the run ends in death around wave 6.
    details = []
    ok8 = True
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        gear, power = gear_for_power(armory, WEAK_POWER_MULT * mission["recommendedPower"])
        _, totals = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
        wave = totals["died_wave"]
        good = totals["died"] and abs(wave - WEAK_DEATH_WAVE) <= WEAK_DEATH_TOLERANCE
        ok8 = ok8 and good
        details.append(
            f"{mission['id']} power {power} -> "
            + (f"died wave {wave}" if totals["died"] else f"survived ({totals['end_reason']})")
            + f" at {se.fmt_time(totals['seconds'])}"
        )
    checks.verdict(
        ok8,
        "8 under-geared     ",
        "; ".join(details)
        + f" (needs death on wave {WEAK_DEATH_WAVE} +-{WEAK_DEATH_TOLERANCE})",
    )

    # 9. WaveComposition returns exactly `count` keys, each within 1 of its share.
    problems = []
    checked = 0
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        for party in range(1, combat_cfg["coop"]["maxParty"] + 1):
            for wave in range(1, mission["waves"] + 1):
                for overdrive in (False, True):
                    spec = wave_spec(mission, wave, party, overdrive, combat_cfg)
                    order = wave_composition(spec["count"], spec["weights"])
                    checked += 1
                    if len(order) != spec["count"]:
                        problems.append(
                            f"{mission['id']} w{wave} p{party}: {len(order)} keys for "
                            f"count {spec['count']}"
                        )
                        continue
                    total_weight = sum(spec["weights"].values())
                    for key, weight in spec["weights"].items():
                        share = spec["count"] * weight / total_weight
                        actual = order.count(key)
                        if abs(actual - share) >= 1:
                            problems.append(
                                f"{mission['id']} w{wave} p{party} {key}: {actual} vs "
                                f"share {share:.2f}"
                            )
    checks.verdict(
        not problems,
        "9 composition      ",
        "; ".join(problems[:4])
        if problems
        else f"{checked} wave/party/overdrive combinations, exact count and every key "
        f"within 1 of its weight share",
    )

    # 10. Overdrive at 3x recommended power pays at least 3x the normal run.
    details = []
    ok10 = True
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        base = baselines.get(mission["id"])
        if base is None:
            gear, _ = gear_for_power(armory, mission["recommendedPower"])
            _, base = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
        # "recommended" here is Combat.RecommendedPower under Overdrive (the
        # mission's number x overdrive.hpMult), which is the figure the
        # Expedition panel shows for an Overdrive run -- so the fixture is three
        # times THAT, not three times the normal-mode number.
        gear, power = gear_for_power(
            armory, OVERDRIVE_POWER_MULT * recommended_power(mission, True, combat_cfg)
        )
        _, totals = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, True)
        ratio = totals["cash"] / base["cash"] if base["cash"] > 0 else 0
        ok10 = ok10 and ratio >= OVERDRIVE_CASH_MULT
        details.append(
            f"{mission['id']} {totals['cash']:,} vs {base['cash']:,} = x{ratio:.2f} "
            f"at power {power} ({totals['waves_cleared']}/{mission['waves']} waves, "
            f"{totals['end_reason']})"
        )
    checks.verdict(
        ok10,
        "10 overdrive cash  ",
        "; ".join(details) + f" (needs >= x{OVERDRIVE_CASH_MULT:g})",
    )


    # 11. Boss waves at party 2-4 (equal per-player recommended power) last
    #     within +-35 % of the solo boss wave: bossHpPerExtraPlayer keeps the
    #     boss a fight however many players bring their DPS to it.
    details = []
    ok11 = True
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        gear, _ = gear_for_power(armory, mission["recommendedPower"])
        solo = boss_wave_lengths(mission, armory, combat_cfg, gear, 1)
        for party in range(2, combat_cfg["coop"]["maxParty"] + 1):
            lengths = boss_wave_lengths(mission, armory, combat_cfg, gear, party)
            parts = []
            for wave, seconds in sorted(solo.items()):
                party_seconds = lengths.get(wave)
                ratio = party_seconds / seconds if party_seconds and seconds > 0 else 0.0
                ok11 = ok11 and abs(ratio - 1) <= BOSS_WAVE_TOLERANCE
                parts.append(f"w{wave} {party_seconds or 0:.1f}s x{ratio:.2f}")
            details.append(f"p{party} " + ", ".join(parts))
        details.insert(
            0,
            f"{mission['id']} solo "
            + ", ".join(f"w{w} {s:.1f}s" for w, s in sorted(solo.items())),
        )
    checks.verdict(
        ok11,
        "11 party boss waves",
        "; ".join(details) + f" (bossHpPerExtraPlayer "
        f"{combat_cfg['coop']['bossHpPerExtraPlayer']}, needs x{1 - BOSS_WAVE_TOLERANCE:.2f}"
        f"-x{1 + BOSS_WAVE_TOLERANCE:.2f})",
    )

    # 12. A 10:1-rate duo pays the mentor exactly mentorValor at a boss clear;
    #     an equal-rate duo pays nobody.
    details = []
    ok12 = True
    valor = combat_cfg["coop"]["mentorValor"]
    low_rate = MENTOR_HOST_RATE / MENTOR_RATE_RATIO
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        gear, _ = gear_for_power(armory, mission["recommendedPower"])
        wide = mentor_run(
            mission, armory, combat_cfg, [(gear, MENTOR_HOST_RATE, False), (gear, low_rate, False)]
        )
        first = first_boss_flush(wide)
        paid = {e["host"]: e["bonus"] for e in wide if e["wave"] == first}
        ok12 = ok12 and first is not None and paid.get(0) == valor and paid.get(1) == 0
        pair = [(gear, MENTOR_HOST_RATE, False), (gear, MENTOR_HOST_RATE, False)]
        equal = mentor_run(mission, armory, combat_cfg, pair)
        equal_paid = sum(e["bonus"] for e in equal)
        ok12 = ok12 and equal_paid == 0
        details.append(
            f"{mission['id']} 10:1 duo at the wave-{first} boss clear: mentor {paid.get(0)}, "
            f"mentee {paid.get(1)} (mentorValor {valor}); equal duo pays {equal_paid} all run"
        )
    checks.verdict(ok12, "12 mentor duo      ", "; ".join(details) or "no missions to model")

    # 13. The mentee floor: a member under mentorMinDamageShare (an idle alt)
    #     earns its mentor nothing, while a genuine starter-gear newbie in the
    #     strongest party the fixtures build still clears it.
    details = []
    ok13 = True
    floor = combat_cfg["coop"]["mentorMinDamageShare"]
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        gear, _ = gear_for_power(armory, mission["recommendedPower"])
        idle = mentor_run(
            mission, armory, combat_cfg, [(gear, MENTOR_HOST_RATE, False), (gear, low_rate, True)]
        )
        idle_paid = sum(e["bonus"] for e in idle if e["host"] == 0)
        idle_share = max((e["shares"][1] for e in idle), default=0.0)
        strong, _ = gear_for_power(armory, STRONG_POWER_MULT * mission["recommendedPower"])
        starter = {"melee": 0, "ranged": 0}
        mixed = mentor_run(
            mission,
            armory,
            combat_cfg,
            [(strong, MENTOR_HOST_RATE, False)] * 3 + [(starter, low_rate, False)],
        )
        newbie_share = min((e["shares"][3] for e in mixed), default=0.0)
        mixed_paid = sum(e["bonus"] for e in mixed if e["host"] == 0)
        # The mentor floor: an idle high-income member beside a fighting,
        # qualifying newbie earns nothing either.
        idle_host = mentor_run(
            mission, armory, combat_cfg, [(gear, MENTOR_HOST_RATE, True), (gear, low_rate, False)]
        )
        idle_host_paid = sum(e["bonus"] for e in idle_host if e["host"] == 0)
        blocked = idle_paid == 0 and idle_share < floor and idle_host_paid == 0
        counted = newbie_share >= floor and mixed_paid > 0
        ok13 = ok13 and blocked and counted
        details.append(
            f"{mission['id']} idle mentee share {idle_share:.1%} -> mentor paid {idle_paid}; "
            f"starter-gear newbie beside three 2x veterans, lowest boss-flush share "
            f"{newbie_share:.1%} -> each veteran paid {mixed_paid}; idle mentor beside a "
            f"fighting 1:10 mentee -> paid {idle_host_paid}"
        )
    checks.verdict(
        ok13,
        "13 mentee floor    ",
        "; ".join(details) + f" (mentorMinDamageShare {floor:.0%})",
    )

    print()
    print(
        "CHECK: "
        + (
            "PASS -- all thirteen assertions hold"
            if checks.failed == 0
            else f"FAIL -- {checks.failed} assertion(s)"
        )
    )
    if places["combatPlaceId"] == 0:
        print("note: Places.json combatPlaceId is 0 -- expedition tiles are disabled in game.")
    return checks.failed


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="run the thirteen C0-C2 assertions")
    parser.add_argument(
        "--trace", action="store_true", help="print the wave timeline of the simulated run"
    )
    parser.add_argument("--era", type=int, help="report only this era's mission")
    parser.add_argument("--power", type=float, help="model the run at this Gear Power")
    parser.add_argument("--party", type=int, default=1, help="party size (default 1)")
    parser.add_argument("--overdrive", action="store_true", help="apply Overdrive multipliers")
    args = parser.parse_args()
    if args.party < 1:
        print("error: --party must be >= 1", file=sys.stderr)
        sys.exit(2)

    armory = load_armory_config()
    combat_cfg = load_combat_config()
    places = load_places_config()
    missions = load_missions()
    game = se.load_game_config()
    eras = se.load_eras()
    shop = se.load_legacy_shop_config()

    if armory is None or combat_cfg is None:
        print("Armory.json / Combat.json missing -- Expeditions are disabled, nothing to balance.")
        sys.exit(0)

    if args.check:
        sys.exit(1 if run_checks(armory, combat_cfg, places, missions, game, eras) else 0)

    print("Era City Tycoon combat sim -- Armory unlocks and modelled expeditions")
    print(
        "greedy income curve from sim_economy (default playthrough, legacy carried); "
        "DPS model per docs/INTERFACES.md C0"
    )
    print()
    curves = greedy_curves(game, eras)
    print_unlock_table(armory, curves, missions)

    selected = [m for index, m in sorted(missions.items()) if args.era in (None, index)]
    if not selected:
        print(f"no mission config for era {args.era}")
        sys.exit(2)
    for mission in selected:
        # Overdrive triples enemy HP, so its recommended power is the scaled one
        # (Combat.RecommendedPower) -- the modelled loadout must follow it.
        baseline = recommended_power(mission, args.overdrive, combat_cfg)
        if args.power is not None:
            variants = [(f"power {args.power:g}", args.power)]
        else:
            variants = [
                ("recommended power", baseline),
                ("2x recommended power", 2 * baseline),
                ("0.6x recommended power", 0.6 * baseline),
            ]
        first = None
        for label, target in variants:
            gear, _ = gear_for_power(armory, target)
            rows, totals = print_run(
                mission,
                armory,
                combat_cfg,
                gear,
                NO_ASCENSION,
                args.party,
                args.overdrive,
                label,
                judge=first is None,
                trace=args.trace,
            )
            print()
            if first is None:
                first = (rows, totals)
        print_cash_ratio(mission, armory, curves, first[1])
        print_survivability(combat_cfg, first[0], first[1])
        print_coop(mission, armory, combat_cfg, args.overdrive)
    print_helpers(armory, combat_cfg, game, shop)
    sys.exit(0)


if __name__ == "__main__":
    main()
