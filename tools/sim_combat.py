#!/usr/bin/env python
"""Armory-and-expedition simulator for Era City Tycoon (C0).

Mirrors `src/shared/Armory.luau` and `src/shared/Combat.luau` function for
function (same names, snake_case) from the contract in `docs/INTERFACES.md`
"C0 contracts -- Expeditions foundation", and reads the four real configs
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
  py tools/sim_combat.py --check          # the six C0 assertions; exit 1 on any
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
    hp_mult = spec["hpMult"] * (boss["hpMult"] if boss else 1)
    damage_mult = spec["damageMult"] * (boss["damageMult"] if boss else 1)
    cash_mult = spec["rewardMult"] * (boss["cashMult"] if boss else 1)
    materials_mult = spec["rewardMult"] * (boss["materialsMult"] if boss else 1)
    return {
        "hp": luau_round(enemy["hp"] * hp_mult),
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
# The C0 DPS model (contract-fixed; not a game formula -- C1 owns the real one)
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
    """The symmetric loadout whose Gear Power is closest to `target_power`
    (ties go to the cheaper tier). Turns "run at 0.6x recommended power" into a
    concrete pair of weapons."""
    best = None
    for gear in symmetric_loadouts(armory):
        power = gear_power(armory, gear, NO_ASCENSION)
        distance = abs(power - target_power)
        if best is None or distance < best[0]:
            best = (distance, gear, power)
    return best[1], best[2]


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


def model_run(mission, armory, combat_cfg, gear, ascension, party, overdrive):
    """Wave-by-wave model of one full mission at a fixed loadout."""
    melee, ranged = loadout_dps(armory, gear, ascension)
    dps = melee + ranged
    rows = []
    totals = {
        "seconds": 0.0,
        "cash": 0.0,
        "materials": 0.0,
        "valor": 0,
        "kills": 0,
        "boss_seconds": 0.0,
    }
    for wave in range(1, mission["waves"] + 1):
        spec = wave_spec(mission, wave, party, overdrive, combat_cfg)
        body = dict(spec)
        body["boss"] = None
        weights = spec["weights"]
        weight_total = sum(weights.values()) or 1
        avg_hp = 0.0
        avg_cash = 0.0
        avg_materials = 0.0
        avg_enemy_dps = 0.0
        for key, weight in weights.items():
            stats = enemy_stats(mission, key, body)
            share = weight / weight_total
            avg_hp += share * stats["hp"]
            avg_cash += share * stats["cash"]
            avg_materials += share * stats["materials"]
            avg_enemy_dps += share * stats["damage"] / mission["enemies"][key]["attackCooldown"]
        ttk = avg_hp / dps if dps > 0 else float("inf")
        seconds = spec["count"] * ttk / party
        cash = spec["count"] * avg_cash
        materials = spec["count"] * avg_materials
        boss_row = None
        if spec["boss"] is not None:
            boss_key = spec["boss"]["enemy"]
            boss_stats = enemy_stats(mission, boss_key, spec, True)
            boss_ttk = boss_stats["hp"] / dps if dps > 0 else float("inf")
            boss_row = {
                "hp": boss_stats["hp"],
                "ttk": boss_ttk,
                "cash": boss_stats["cash"],
                "materials": boss_stats["materials"],
                "valor": boss_valor(mission, wave, overdrive, combat_cfg),
                "dps_in": boss_stats["damage"]
                / mission["enemies"][boss_key]["attackCooldown"],
            }
            seconds += boss_ttk / party
            cash += boss_stats["cash"]
            materials += boss_stats["materials"]
            totals["valor"] += boss_row["valor"]
            totals["boss_seconds"] += boss_ttk / party
        rows.append(
            {
                "wave": wave,
                "count": spec["count"],
                "avg_hp": avg_hp,
                "ttk": ttk,
                "seconds": seconds,
                "cash": cash,
                "materials": materials,
                "boss": boss_row,
                "enemy_dps": avg_enemy_dps,
            }
        )
        totals["seconds"] += seconds
        totals["cash"] += cash
        totals["materials"] += materials
        totals["kills"] += spec["count"] + (1 if boss_row else 0)
    totals["dps"] = dps
    totals["melee_dps"] = melee
    totals["ranged_dps"] = ranged
    totals["max_hp"] = max_hp(armory, gear, ascension)
    totals["power"] = gear_power(armory, gear, ascension)
    totals["breather_seconds"] = combat_cfg["director"]["breatherSeconds"] * (
        mission["waves"] - 1
    )
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


def print_run(mission, armory, combat_cfg, gear, ascension, party, overdrive, label, judge=True):
    rows, totals = model_run(mission, armory, combat_cfg, gear, ascension, party, overdrive)
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
        f"(melee {totals['melee_dps']:.1f} + ranged {totals['ranged_dps']:.1f}), "
        f"party {party}"
    )
    print(
        f"  {'wave':>4} {'count':>6} {'avgHp':>9} {'TTK':>7} {'waveS':>8} "
        f"{'cash':>10} {'mats':>7}  {'boss':<34}"
    )
    ordinary = [r["seconds"] - (r["boss"]["ttk"] / party if r["boss"] else 0) for r in rows]
    for row, plain in zip(rows, ordinary):
        boss = ""
        if row["boss"]:
            boss = (
                f"{row['boss']['hp']:,} hp / {row['boss']['ttk']:.0f}s / "
                f"{row['boss']['valor']} valor"
            )
        # The flag judges the wave body only: a boss wave is meant to run long.
        flag = "*" if plain > 2 * mission["targetWaveSeconds"] else " "
        print(
            f"  {row['wave']:>4} {row['count']:>6} {row['avg_hp']:>9,.0f} "
            f"{row['ttk']:>7.2f} {row['seconds']:>7.1f}{flag} "
            f"{row['cash']:>10,.0f} {row['materials']:>7.1f}  {boss:<34}"
        )
    status = "OK" if low <= totals["seconds"] <= high else "MISS"
    if not judge:
        status += " (informational -- only the recommended-power run is asserted)"
    print(
        f"  total     : {se.fmt_time(totals['seconds'])} combat "
        f"({totals['seconds']:.0f}s) + {totals['breather_seconds']:.0f}s breathers "
        f"= {se.fmt_time(totals['seconds'] + totals['breather_seconds'])} wall clock"
    )
    print(
        f"  target    : {mission['targetMinutes']} min "
        f"({se.fmt_time(low)}-{se.fmt_time(high)} at +-50%): {status}"
    )
    print(
        f"  waves     : ordinary mean {sum(ordinary) / len(ordinary):.1f}s "
        f"(target {mission['targetWaveSeconds']}s), longest {max(ordinary):.1f}s; "
        f"bosses {totals['boss_seconds']:.0f}s "
        f"({100 * totals['boss_seconds'] / totals['seconds']:.0f}% of the run)"
    )
    print(
        f"  rewards   : {totals['cash']:,.0f} cash, {totals['materials']:,.0f} "
        f"{mission['material']}, {totals['valor']} Valor, {totals['kills']} kills"
    )
    wall = totals["seconds"] + totals["breather_seconds"]
    cap = combat_cfg["director"]["runCapSeconds"]
    print(
        f"  run cap   : {cap}s -- "
        + ("fits" if wall <= cap else "OVER, the run would be cut short")
    )
    return rows, totals


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
    """Informational only -- C1 owns the real hit model. Incoming damage is
    modelled as ONE enemy in contact landing `contact` of its attacks."""
    print("Survivability (informational -- no contract assertion until C1)")
    regen = (
        combat_cfg["player"]["breatherRegenPerSecond"] * combat_cfg["director"]["breatherSeconds"]
    )
    healed = regen * (len(rows) - 1)
    for contact in (0.1, 0.25, 0.5):
        taken = sum(r["enemy_dps"] * contact * r["seconds"] for r in rows)
        taken += sum(r["boss"]["dps_in"] * contact * r["boss"]["ttk"] for r in rows if r["boss"])
        deaths = max(taken - healed, 0) / totals["max_hp"]
        print(
            f"  1 enemy in contact, {contact:.0%} of attacks land: "
            f"{taken:,.0f} damage taken - {healed:,.0f} regen = "
            f"{deaths:.1f} deaths at {totals['max_hp']:g} max HP "
            f"({deaths * combat_cfg['player']['respawnSeconds']:.0f}s of respawn)"
        )
    print(
        f"  breather regen   : {regen:g} HP x {len(rows) - 1} breathers "
        f"({100 * regen / totals['max_hp']:.0f}% of max HP each), "
        f"respawn {combat_cfg['player']['respawnSeconds']}s"
    )
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
# --check: the six assertions in docs/INTERFACES.md "tools/sim_combat.py"
# --------------------------------------------------------------------------


class Checks:
    def __init__(self):
        self.failed = 0

    def verdict(self, ok, name, detail):
        if not ok:
            self.failed += 1
        print(f"  {'PASS' if ok else 'FAIL'}  {name}: {detail}")


def run_checks(armory, combat_cfg, places, missions, game, eras):
    checks = Checks()
    print("sim_combat --check (docs/INTERFACES.md 'C0 contracts', six assertions)")
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

    # 3. Modelled run at recommended power inside targetMinutes +-50 %.
    details = []
    ok3 = True
    for curve in curves:
        mission = missions.get(curve.index)
        if mission is None:
            continue
        gear, power = gear_for_power(armory, mission["recommendedPower"])
        _, totals = model_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
        target = mission["targetMinutes"] * 60
        inside = (
            target * (1 - RUN_TIME_TOLERANCE)
            <= totals["seconds"]
            <= target * (1 + RUN_TIME_TOLERANCE)
        )
        ok3 = ok3 and inside
        details.append(
            f"{mission['id']} {se.fmt_time(totals['seconds'])} vs target "
            f"{mission['targetMinutes']} min at power {power}"
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
        _, totals = model_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
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

    print()
    print(
        "CHECK: "
        + (
            "PASS -- all six assertions hold"
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
    parser.add_argument("--check", action="store_true", help="run the six C0 assertions")
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
            )
            print()
            if first is None:
                first = (rows, totals)
        print_cash_ratio(mission, armory, curves, first[1])
        print_survivability(combat_cfg, first[0], first[1])
    print_helpers(armory, combat_cfg, game, shop)
    sys.exit(0)


if __name__ == "__main__":
    main()
