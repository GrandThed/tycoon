#!/usr/bin/env python
"""Armory-and-expedition simulator for Era City Tycoon (C0 + C1 + C2 + L1 + L3, trimmed in L4 W1b).

Mirrors the pure `src/shared/Armory.luau` and `src/shared/Combat.luau` function for function
(same names, snake_case) and reads the real configs (`Armory.json`, `Combat.json`, `Places.json`).
The greedy tycoon curve is NOT re-derived here: `sim_economy.simulate_era` is imported and run
exactly as `sim_economy.run_full`/`run_packs` do (legacy carried across advances, 1 s resolution),
so both tools always agree on income per second.

What it answers:
  * L3 W1 (docs/prompts/l3-w1-contract.md): the ladder of 20 every weapon family climbs (each
    tier's multiplier, health, band, price and trophy, every family's window), and how many Forest
    Road runs and minutes take both starters from T1 to T4 (assertions 1 and 2);
  * what a Normal clear of Forest Road pays at each era's cash multiplier (Combat.json
    rewards.eraCashMult, L4 W3: MISSIONS_DESIGN 26.8 and 30), against each era's remaining slot cost (4:
    "combat must not replace the tycoon"), against the greedy city run back to back (24: back-to-back
    runs on Normal or Hard never finish an era sooner than building; printed beside it, ungated, the
    best "k runs right after an Advance, then build", which can finish sooner) and in minutes of the
    era's income at its first clear (25: a few minutes at the start);
  * the pure co-op and offline rules (5, 6, 12, 13, 22) and the level gates, pay and population
    (20, 21, 23). The fights themselves are measured by `tools/sim_range.py`, which this file imports.

L4 W1b (docs/prompts/l4-w1b-contract.md) retired the C1 missions' code and its mirrors: the C1 run
model (WaveSpec, EnemyStats, WaveComposition, SpawnInterval, the slot tiers' damage, abilities and
party effects, the director's C1 run), the P5 crowd mission (CrowdWave, CrowdReward, BurstInterval)
and ruling 27's arena adapter, with assertions 3, 7-11 and 14 (the C1 run), 15-18 (the crowd
mission) and 19 (the adapter), and the --era, --power, --party and --overdrive flags. The numbers
of the kept assertions are unchanged.

Usage:
  py tools/sim_combat.py                  # the ladder, Forest Road's pay and the helpers' spot checks
  py tools/sim_combat.py --check          # the thirteen assertions; exit 1 on any
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

# sim_economy lives in this folder and is imported, never copied: it owns every
# tycoon formula and both tools must read the same income curve.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import sim_economy as se  # noqa: E402

# Tool-only constants; nothing in the game reads them. Assertion 4's ceiling, from the contract.
RUN_CASH_CAP_FRACTION = 0.25
# L4 W3 (docs/prompts/l4-w3-contract.md section 5; the cash study's (c) at M = 3, Ben's pick): run cash
# is multiplied by the member's city era (Combat.json rewards.eraCashMult). Assertion 4's second line:
# the first clear after an Advance is at most this share of what the era still owes when it lands.
FIRST_CLEAR_CAP_FRACTION = 0.02
# Assertion 25 ("a few minutes at the start"): that first clear is worth this many minutes of the
# era's income at the second it lands.
FIRST_CLEAR_MINUTES = (1.0, 6.0)
# Assertion 24 (back-to-back runs never finish an era sooner than building) runs these difficulties
# back to back, and its ungated line runs k of them right after the Advance, then builds. Brutal needs
# Castle gear (T5) and a T4 Brutal clear is unmeasured (contract risk 3): re-run it with Brutal then.
NEVER_FASTER_DIFFICULTIES = ("normal", "hard")
# Assertion 5's fixture: a 10:1 damage duo must leave the veteran >= 75 %.
VETERAN_SHARE_FLOOR = 0.75
# Assertions 12 and 13 (C2 "Balance", rewritten pure in L4 W1b): fixture income rates, not game values.
MENTOR_HOST_RATE = 10000.0
MENTOR_RATE_RATIO = 10.0
# targetMinutes (the hub's and the map's promise) must lie this close to the mean measured clear.
CROWD_TARGET_MINUTES_SLACK = 1.5
# director.runCapSeconds ends a run that never finishes. It must leave a player slower than the
# simulator's this many times a level's targetMinutes, or it cuts off runs that are merely slow.
CROWD_RUN_CAP_RATIO = 2.0
# L1 levels (docs/INTERFACES.md "L1 contracts" -> "Balance bands"). L1b Wave 2 ("Balance bands"):
# what a Normal clear pays is REPORTED against the layout draft's arithmetic (152,820 cash, 373
# Timber, 10 Valor); its per-minute band is sim_range's. The Valor stays exact (the boss's x
# rewardMult). How many times Normal a whole clear pays on the harder difficulties is gated
# again (L1's bands back), and the camps' clear bonuses are a small share of a Normal clear.
LEVEL_PAY_TARGETS = {"forestRoad": {"cash": 152820, "materials": 373, "valor": 10}}
LEVEL_PAY_TIMES = {"hard": (2.0, 3.0), "brutal": (4.0, 6.0)}
LEVEL_BONUS_SHARE = (0.05, 0.10)  # L1b-W2-21: the bonuses of a Normal clear, as a share of its cash
# L3 W1 (docs/prompts/l3-w1-contract.md, L3-1..L3-4, L3-8, L3-29), assertions 1 and 2. The ladder:
# 20 tiers, T1 = the 2/2 every band was tuned at, x1.65 a tier; HP T1-T11 = the old slot tiers 2-12;
# five bands of four, one per level in the map's order; Forest Road's T2 / T3 / T4 cost 100 / 250 /
# 500 Timber (Ben, 2026-10-20). The windows are L3-3's table (Ben, as drawn).
LADDER_SIZE = 20
LADDER_FIRST = 1.5
LADDER_STEP = 1.65
# L3-1: ladder HP T1-T11 are the old slot tiers 2-12 (Armory.json `slots` before L4 W1b), pinned here
# since the slots went.
LADDER_HP_T1_T11 = {"melee": [35, 50, 80, 120, 170, 250, 350, 480, 700, 950, 1300],
                    "ranged": [20, 30, 50, 80, 110, 160, 230, 320, 450, 620, 850]}
# L3-8: the twelve slot-tier prices `legacy.gearCosts` freezes for the v8 refund.
LEGACY_GEAR_COSTS = [(material, amount) for material in ("Timber", "Steel", "Circuits", "Alloy")
                     for amount in (10, 60, 180)]
LADDER_MAX_HP = {1: 155, 3: 230, 5: 380}
LADDER_RANGE_HP = 130
LADDER_BANDS = 5
LADDER_BAND_SIZE = 4
LADDER_BAND_LEVELS = ("forestRoad", "castle", "underworld", "planet", "dream")
LADDER_FOREST_COSTS = (100, 250, 500)
LADDER_STAR_ALSO = ("brutal",)  # R1 (L3 W1 fix round): the Hard star or a harder one opens a band top
LADDER_WINDOWS = {"broadsword": (1, 12), "longbow": (1, 12), "flamethrower": (2, 8), "warhammer": (3, 16),
                  "frostHammer": (5, 12), "greataxe": (6, 18), "splitbow": (8, 8), "spear": (9, 20),
                  "shotgun": (9, 16), "rifle": (11, 18), "launcher": (13, 20), "smg": (14, 20), "beam": (16, 20),
                  "chaingun": (17, 20), "spinblade": (20, 20)}
# The climb (L3-29; Ben: "three Forest runs take one weapon from tier 1 to tier 4", both starters
# in about 31 minutes): both starters T1 -> T4 in these many runs and minutes of measured clears; the
# first Normal clear buys T2 for both; Hard pays 20 Valor (10 x 2) and the Brutal first clear 25.
# Lead, 2026-10-20: Ben picked runs (three a weapon); measured clears shorten as the tiers rise, so
# six runs come to about 25 minutes, not the study's 31 (which counted every run at 5 minutes).
CLIMB_RUNS = (5, 7)
CLIMB_MINUTES = (20.0, 40.0)
CLIMB_FIRST_TIMBER = 200
CLIMB_RUN_LIMIT = 12
HARD_VALOR = 20
BRUTAL_FIRST_VALOR = 25
# Assertion 22 (L1b-15): Combat.SplitCarry over a seeded fuzz.
CARRY_FUZZ_SEED = 1407
CARRY_FUZZ_RUNS = 400
CARRY_FUZZ_KILLS = 60
LEVEL_REWARD_MULT = {"normal": 1, "hard": 2, "brutal": 4}  # L3 W1 contract §12.8: Hard stays x2
# What a boss's calls pay per second, as a share of what the whole clear pays per second: under
# this, standing in front of a boss to farm what it calls is always worse than playing on.
LEVEL_STALL_SHARE = 0.5

# --------------------------------------------------------------------------
# Config loading (Catalog.GetArmoryConfig / GetCombatConfig / GetPlacesConfig -- nil is the
# signal, so a missing file returns None and the caller reports "feature absent" instead of failing).
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


def luau_round(value):
    """Luau `math.round` -- half away from zero. Python's round() is banker's
    rounding, which would disagree with the server on exact .5 counts."""
    if value >= 0:
        return math.floor(value + 0.5)
    return -math.floor(-value + 0.5)


# --------------------------------------------------------------------------
# src/shared/Armory.luau mirror
# --------------------------------------------------------------------------


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


# --- L3-5: the ladder (docs/prompts/l3-w1-contract.md). Every number is Armory.json's `ladder`,
# `windows` and `legacy`; the tier belongs to the weapon family, not the slot. Each guard below is
# Armory.luau's own (a decoded value that is not what a rule needs degrades, never errors).


def _finite(value):
    """Armory.luau `finite`: a number that is not NaN and not infinite (a bool is no number)."""
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _whole(value):
    """Armory.luau `whole`."""
    return _finite(value) and float(value).is_integer()


def _lstr(value):
    """Luau's tostring of a decoded value, for the validator's lines."""
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer() and abs(value) < 1e15:
        return str(int(value))
    return str(value)


def _ladder(cfg):
    """Armory.luau `ladderOf`: the ladder when it holds a damage list, else None."""
    ladder = cfg.get("ladder")
    return ladder if isinstance(ladder, dict) and isinstance(ladder.get("damage"), list) else None


def _clamp_tier(tier, size):
    return min(max(tier, 1), size)


def _asc_mult(cfg, asc_level, ability):
    level = ascension_level_def(cfg, asc_level)
    if level is None:
        return 1
    return level["abilityMult"] if ability else level["damageMult"]


def ladder_size(cfg):
    """Armory.LadderSize -- #ladder.damage; 0 without a ladder."""
    ladder = _ladder(cfg)
    return len(ladder["damage"]) if ladder is not None else 0


def window(cfg, family):
    """Armory.Window -- (start, top) held inside 1..LadderSize; None for a family with no window, a
    malformed one (not whole numbers, or a start above its top) or no ladder."""
    size = ladder_size(cfg)
    windows = cfg.get("windows")
    entry = windows.get(family) if isinstance(windows, dict) else None
    if size == 0 or not isinstance(entry, dict) or not _whole(entry.get("start")) or not _whole(entry.get("top")) \
            or entry["start"] > entry["top"]:
        return None
    return _clamp_tier(int(entry["start"]), size), _clamp_tier(int(entry["top"]), size)


def tier_of(cfg, combat, family):
    """Armory.TierOf (L3-3) -- the saved tier held inside the window, else the start (a saved tier
    that is not a whole number reads the start); 1 for a family with no window."""
    span = window(cfg, family)
    if span is None:
        return 1
    start, top = span
    tiers = (combat or {}).get("tiers")
    saved = tiers.get(family) if isinstance(tiers, dict) else None
    if not _whole(saved):
        return start
    return min(max(int(saved), start), top)


def held_tiers(cfg, combat, melee, ranged):
    """The held families' tiers in the slot-shaped record: TierOf of each, what WeaponService.gearOf
    builds with no Studio override. (Its Luau twin, Armory.HeldTiers, went in L4 W3 with Gear Power, its
    last reader; sim_range.py still reads this helper.)"""
    return {"melee": tier_of(cfg, combat, melee), "ranged": tier_of(cfg, combat, ranged)}


def multiplier(cfg, tier):
    """Armory.Multiplier (L3-1) -- ladder.damage[tier held inside the ladder]; 1 without a ladder,
    for a tier that is not a whole number, or for an entry that is not a number above 0."""
    ladder = _ladder(cfg)
    if ladder is None or not ladder["damage"] or not _whole(tier):
        return 1
    value = ladder["damage"][_clamp_tier(int(tier), len(ladder["damage"])) - 1]
    return value if _finite(value) and value > 0 else 1


def damage_scale(cfg, tier, asc_level, ability):
    """Armory.DamageScale (L3-6; P5 ruling 8, by tier) -- Multiplier(tier) x the slot's Ascension
    abilityMult (an ability) or damageMult (an attack), 1 at level 0. The range never asks: its
    scale is 1 (WeaponService.damageScale)."""
    return multiplier(cfg, tier) * _asc_mult(cfg, asc_level, ability)


def weapon_hp(cfg, slot, tier, asc_level):
    """Armory.WeaponHp (L3-2) -- ladder.hp[slot][tier held inside the list] x the Ascension level's
    hpMult; 0 for an unknown slot, no ladder, a tier that is not a whole number, or an entry that is
    not a number of at least 0."""
    ladder = _ladder(cfg)
    hp = ladder.get("hp") if ladder is not None else None
    rows = hp.get(slot) if isinstance(hp, dict) and slot in ("melee", "ranged") else None
    if not isinstance(rows, list) or not rows or not _whole(tier):
        return 0
    value = rows[_clamp_tier(int(tier), len(rows)) - 1]
    if not _finite(value) or value < 0:
        return 0
    level = ascension_level_def(cfg, asc_level)
    return value * (level["hpMult"] if level else 1)


def max_hp(cfg, tiers, ascension):
    """Armory.MaxHp (L3-2) -- baseHp + WeaponHp(melee tier) + WeaponHp(ranged tier)."""
    return (
        cfg["baseHp"]
        + weapon_hp(cfg, "melee", tiers["melee"], ascension["melee"])
        + weapon_hp(cfg, "ranged", tiers["ranged"], ascension["ranged"])
    )


def range_hp(cfg):
    """Armory.RangeHp -- ladder.rangeHp, the range's own body (baseHp without a ladder or a rangeHp
    that is not a number above 0)."""
    ladder = _ladder(cfg)
    value = ladder.get("rangeHp") if ladder is not None else None
    return value if _finite(value) and value > 0 else cfg["baseHp"]


def band_of(cfg, tier):
    """Armory.BandOf (L3-4) -- (ceil(t / bandSize), (t - 1) % bandSize + 1); (0, 0) for a tier
    outside 1..LadderSize or not whole, or a bandSize that is not a whole number above 0."""
    ladder = _ladder(cfg)
    if ladder is None:
        return 0, 0
    size = ladder.get("bandSize")
    if not _whole(size) or size <= 0 or not _whole(tier) or tier < 1 or tier > len(ladder["damage"]):
        return 0, 0
    size, tier = int(size), int(tier)
    return math.ceil(tier / size), (tier - 1) % size + 1


def _band_at(cfg, tier):
    """Armory.luau `bandAt`: (the band entry when it names a level and a material, its position)."""
    band, position = band_of(cfg, tier)
    ladder = _ladder(cfg)
    bands = ladder.get("bands") if ladder is not None else None
    entry = bands[band - 1] if band > 0 and isinstance(bands, list) and band <= len(bands) else None
    if not isinstance(entry, dict) or not isinstance(entry.get("levelId"), str) or entry["levelId"] == "" \
            or not isinstance(entry.get("material"), str) or entry["material"] == "":
        return None, position
    return entry, position


def next_tier(cfg, combat, family):
    """Armory.NextTier -- TierOf + 1 while it stays inside the window; None at the top or without one."""
    span = window(cfg, family)
    if span is None:
        return None
    candidate = tier_of(cfg, combat, family) + 1
    return candidate if candidate <= span[1] else None


def tier_cost(cfg, tier):
    """Armory.TierCost -> (the band's material, costs[position]); ("", 0) for a tier outside the
    ladder, a band entry that is missing or names no level or material, or a cost that is not a
    number of at least 0."""
    entry, position = _band_at(cfg, tier)
    ladder = _ladder(cfg)
    costs = ladder.get("costs") if ladder is not None else None
    cost = costs[position - 1] if entry is not None and isinstance(costs, list) and 1 <= position <= len(costs) else None
    if entry is None or not _finite(cost) or cost < 0:
        return "", 0
    return entry["material"], cost


def preview(cfg, slot, tier, base_damage):
    """Armory.Preview -> (round(baseDamage x Multiplier(tier)), WeaponHp(slot, tier, 0))."""
    return luau_round(base_damage * multiplier(cfg, tier)), weapon_hp(cfg, slot, tier, 0)


def _star_held(combat, level_id, difficulty):
    stars = combat.get("stars")
    row = stars.get(level_id) if isinstance(stars, dict) else None
    return isinstance(difficulty, str) and isinstance(row, dict) and row.get(difficulty) is True


def star_held(cfg, combat, level_id):
    """Armory.StarHeld (R1, review 1-m5) -- the level's ladder.starDifficulty star, or the star of any
    difficulty in ladder.starAlso (a Brutal clear also opens a band top); False without a ladder or a
    profile, and a starAlso that is not a list adds nothing."""
    ladder = _ladder(cfg)
    if ladder is None or combat is None:
        return False
    if _star_held(combat, level_id, ladder.get("starDifficulty")):
        return True
    also = ladder.get("starAlso")
    return isinstance(also, list) and any(_star_held(combat, level_id, d) for d in also)


def upgrade_verdict(cfg, combat, family, owned, gate_open, built):
    """Armory.UpgradeVerdict (L3-5) -- None, or the first refusal in this order: invalid (no window
    or no ladder), locked (not owned), peak (at its top), busy (the gate is shut), notBuilt (the
    next tier's band level has no level file, or the tier has no price), needsStar (a band's top
    position without StarHeld: that level's starDifficulty star or a starAlso one), insufficientFunds
    (the band material is not a number at least the cost)."""
    if window(cfg, family) is None:
        return "invalid"
    if not owned:
        return "locked"
    tier = next_tier(cfg, combat, family)
    if tier is None:
        return "peak"
    if not gate_open:
        return "busy"
    ladder = _ladder(cfg)
    entry, position = _band_at(cfg, tier)
    material, cost = tier_cost(cfg, tier)
    if ladder is None or entry is None or built.get(entry["levelId"]) is not True or material == "":
        return "notBuilt"
    if position == ladder.get("bandSize") and not star_held(cfg, combat, entry["levelId"]):
        return "needsStar"
    have = (combat.get("materials") or {}).get(material)
    if not (_finite(have) and have >= cost):
        return "insufficientFunds"
    return None


def upgrade(cfg, combat, family, owned, gate_open, built):
    """Armory.Upgrade -- UpgradeVerdict, then on None the write in the same call: the tier's cost
    taken from materials (never below 0) and tiers[family] = the next tier (the table made when
    the profile has none)."""
    refusal = upgrade_verdict(cfg, combat, family, owned, gate_open, built)
    if refusal is not None:
        return refusal
    tier = next_tier(cfg, combat, family)
    material, cost = tier_cost(cfg, tier)
    materials = combat["materials"]
    materials[material] = max(0, (materials.get(material) or 0) - cost)
    if combat.get("tiers") is None:
        combat["tiers"] = {}
    combat["tiers"][family] = tier
    return None


def set_tier(cfg, combat, family, tier):
    """Armory.SetTier (L3-28's setTier lever) -- floor(tier) held inside the family's window, written
    (owning it is not required); the tier written, or None and nothing written for a family with no
    window or a tier that is not a finite number."""
    span = window(cfg, family)
    if span is None or not _finite(tier):
        return None
    held = min(max(math.floor(tier), span[0]), span[1])
    if combat.get("tiers") is None:
        combat["tiers"] = {}
    combat["tiers"][family] = held
    return held


def built_bands(cfg, built):
    """Armory.BuiltBands (L3-28) -- ([levels], [materials]) of the ladder's bands whose level is built,
    in band order, each once: the Studio grant pays those materials and grantStar "*" stars those
    levels."""
    levels, materials = [], []
    ladder = _ladder(cfg)
    bands = ladder.get("bands") if ladder is not None else None
    for entry in bands if isinstance(bands, list) else []:
        if isinstance(entry, dict) and isinstance(entry.get("levelId"), str) and isinstance(entry.get("material"), str) \
                and entry["material"] != "" and built.get(entry["levelId"]) is True:
            if entry["levelId"] not in levels:
                levels.append(entry["levelId"])
            if entry["material"] not in materials:
                materials.append(entry["material"])
    return levels, materials


def legacy_refund(cfg, gear):
    """Armory.LegacyRefund (L3-8) -- {material: amount} over both slots, entries 1..min(gear[slot],
    #legacy.gearCosts) at the frozen pre-v8 prices; a slot tier that is not a whole number, an entry
    that names no material or an amount that is not a number of at least 0 adds nothing."""
    legacy = cfg.get("legacy")
    costs = legacy.get("gearCosts") if isinstance(legacy, dict) else None
    refund = {}
    if not isinstance(costs, list) or not isinstance(gear, dict):
        return refund
    for bought in (gear.get("melee"), gear.get("ranged")):
        if not _whole(bought):
            continue
        for entry in costs[:max(min(int(bought), len(costs)), 0)]:
            if isinstance(entry, dict) and isinstance(entry.get("material"), str) and entry["material"] != "" \
                    and _finite(entry.get("amount")) and entry["amount"] >= 0:
                refund[entry["material"]] = refund.get(entry["material"], 0) + entry["amount"]
    return refund


def problems(cfg, families):
    """Armory.Problems (L3-5) -- the Init validator, line for line: the ladder (damage rising numbers
    above 0; each hp row LadderSize numbers of at least 0 that never fall, melee never below ranged;
    rangeHp above 0; bandSize a whole number above 0 with bandSize x #bands = LadderSize; every band
    a level and a material; one cost per position, each at least 0; a starDifficulty; starAlso absent
    or a list of non-empty strings), every family
    a window 1 <= start <= top <= LadderSize, no window for a family that is not one, and the legacy
    list (L4 W3 took the power.tierWeight line with Gear Power). Assertion 1 holds the shipped values to
    L3-1..L3-4 on top."""
    out = []

    def problem(text):
        out.append(f"Armory.json {text}")

    ladder = cfg.get("ladder")
    size = ladder_size(cfg)
    if not isinstance(ladder, dict):
        problem("has no ladder: every weapon fights at T1 and none can be upgraded")
    elif size == 0:
        problem("ladder.damage is not a list of numbers: every weapon fights at T1")
    else:
        damage = ladder["damage"]
        for t in range(1, size + 1):
            value = damage[t - 1]
            before = damage[t - 2] if t > 1 else None
            if not _finite(value) or value <= 0:
                problem(f"ladder.damage[{t}] is {_lstr(value)}, not a number above 0")
            elif t > 1 and _finite(before) and value <= before:
                problem(f"ladder.damage[{t}] ({_lstr(value)}) does not rise above ladder.damage[{t - 1}] ({_lstr(before)})")
        hp = ladder.get("hp")
        for slot in ("melee", "ranged"):
            rows = hp.get(slot) if isinstance(hp, dict) else None
            if not isinstance(rows, list) or len(rows) != size:
                problem(f"ladder.hp.{slot} is not a list of {size} numbers")
                continue
            for t in range(1, size + 1):
                value = rows[t - 1]
                before = rows[t - 2] if t > 1 else None
                if not _finite(value) or value < 0:
                    problem(f"ladder.hp.{slot}[{t}] is {_lstr(value)}, not a number of at least 0")
                elif t > 1 and _finite(before) and value < before:
                    problem(f"ladder.hp.{slot}[{t}] ({_lstr(value)}) falls below ladder.hp.{slot}[{t - 1}] ({_lstr(before)})")
        melee = hp.get("melee") if isinstance(hp, dict) else None
        ranged = hp.get("ranged") if isinstance(hp, dict) else None
        if isinstance(melee, list) and isinstance(ranged, list):
            for t in range(1, size + 1):
                m = melee[t - 1] if t <= len(melee) else None
                r = ranged[t - 1] if t <= len(ranged) else None
                if _finite(m) and _finite(r) and m < r:
                    problem(f"ladder.hp.melee[{t}] ({_lstr(m)}) is below ladder.hp.ranged[{t}] ({_lstr(r)})")
        if not _finite(ladder.get("rangeHp")) or ladder["rangeHp"] <= 0:
            problem(f"ladder.rangeHp is {_lstr(ladder.get('rangeHp'))}, not a number above 0: the range uses baseHp")
        band_size = ladder.get("bandSize")
        bands = ladder.get("bands") if isinstance(ladder.get("bands"), list) else []
        if not _whole(band_size) or band_size <= 0:
            problem(f"ladder.bandSize is {_lstr(band_size)}, not a whole number above 0: nothing can be bought")
        elif band_size * len(bands) != size:
            problem(f"ladder.bands and bandSize do not cover the {size} tiers")
        for index, entry in enumerate(bands, 1):
            if not isinstance(entry, dict) or not isinstance(entry.get("levelId"), str) or entry["levelId"] == "":
                problem(f"ladder.bands[{index}] names no level: its tiers can never be bought")
            elif not isinstance(entry.get("material"), str) or entry["material"] == "":
                problem(f"ladder.bands[{index}] ({entry['levelId']}) names no material: its tiers can never be bought")
        costs = ladder.get("costs")
        if not isinstance(costs, list) or (_whole(band_size) and len(costs) != band_size):
            problem("ladder.costs is not one cost per position in a band")
        else:
            for position, cost in enumerate(costs, 1):
                if not _finite(cost) or cost < 0:
                    problem(f"ladder.costs[{position}] is {_lstr(cost)}, not a number of at least 0")
        if not isinstance(ladder.get("starDifficulty"), str) or ladder["starDifficulty"] == "":
            problem("ladder.starDifficulty names no difficulty: no band top can ever be bought")
        # Armory.luau `namesList`: a list of non-empty strings (an empty one is one). Luau decodes an
        # empty JSON object to the same empty table as [], so {} passes too.
        also = ladder.get("starAlso")
        if also is not None and also != {} and (not isinstance(also, list)
                                                or any(not isinstance(d, str) or d == "" for d in also)):
            problem("ladder.starAlso is not a list of difficulty names")
    windows = cfg.get("windows")
    known = set()
    for family in families:
        known.add(family)
        entry = windows.get(family) if isinstance(windows, dict) else None
        if not isinstance(entry, dict):
            problem(f'windows has no entry for "{family}": it fights at T1 and cannot be upgraded')
        elif (not _whole(entry.get("start")) or not _whole(entry.get("top")) or entry["start"] < 1
              or entry["start"] > entry["top"] or (size > 0 and entry["top"] > size)):
            problem(f"windows.{family} ({_lstr(entry.get('start'))} to {_lstr(entry.get('top'))}) is not "
                    f"1 <= start <= top <= {size}")
    if isinstance(windows, dict):
        for family in sorted(str(f) for f in windows if f not in known):
            problem(f"windows.{family} names no weapon family")
    legacy = cfg.get("legacy")
    gear_costs = legacy.get("gearCosts") if isinstance(legacy, dict) else None
    if not isinstance(gear_costs, list):
        problem("has no legacy.gearCosts: the v8 profile step refunds nothing")
    else:
        for index, entry in enumerate(gear_costs, 1):
            if not isinstance(entry, dict) or not isinstance(entry.get("material"), str) or entry["material"] == "" \
                    or not _finite(entry.get("amount")) or entry["amount"] < 0:
                problem(f"legacy.gearCosts[{index}] is not a material and an amount of at least 0")
    return out


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
    if slot not in ("melee", "ranged") or current is None:
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


# --------------------------------------------------------------------------
# src/shared/Combat.luau mirror
# --------------------------------------------------------------------------


def new_combat_profile():
    """The v8 profile template's `combat` field (ProfileSchema.PROFILE_TEMPLATE, L3-7): the v7 maps
    and the three L3 fields; `gear` is frozen (kept, never read by the tier path)."""
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
        "abilities": {},
        "secrets": {},
        "families": {},
        "shortcuts": {},
        "tiers": {},
        "loadout": {"variants": {}},
        "stars": {},
    }


def touch_highest_era(state):
    """Combat.TouchHighestEra"""
    state["combat"]["highestEra"] = max(state["combat"]["highestEra"], state["era"])


def era_cash_mult(rewards, era):
    """Combat.EraCashMult (L4W3-7) -- Combat.json rewards.eraCashMult's entry for the member's city
    era, in Config/Eras order; an era past the list takes the last. 1 when the block, the list or
    that entry is missing or malformed (an entry must be a finite number of at least 1)."""
    mults = rewards.get("eraCashMult") if isinstance(rewards, dict) else None
    if not isinstance(mults, list) or not mults or not _finite(era):
        return 1
    entry = mults[min(max(math.floor(era), 1), len(mults)) - 1]
    if not _finite(entry) or entry < 1:
        return 1
    return entry


def combat_cash_mult(state, game_config, shop_config, rewards=None, era=1):
    """Combat.CombatCashMult -- LegacyMult x PerkIncomeMult x EraCashMult(rewards, era); no pass, no
    Premium, no neighbours (combat cash is not an income stream). L4 W3: the era factor lives here
    and never in level_pay, so every level's base pay (assertions 1, 2, 5, 6, 12, 13, 20, 21, 23
    and sim_range.py) stays as it was."""
    return se.legacy_mult(state["legacy"], game_config) * se.perk_income_mult(
        shop_config, state["legacyShop"]
    ) * era_cash_mult(rewards, era)


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


# --------------------------------------------------------------------------
# src/shared/Combat.luau mirror -- L1 camps (docs/INTERFACES.md "L1 contracts" -> "B -- the
# run"): CampWave, KillReward and BurstSeconds are the rules a run reads (their C1 callers
# CrowdWave, CampReward, CrowdReward and BurstInterval went in L4 W1b). tools/sim_range.py drives
# a whole level through these, so both tools read one copy.
# --------------------------------------------------------------------------


def camp_wave(wave_def, regen_share, scales, rank, ranks, party_size, combat_cfg):
    """Combat.CampWave (L1) -- one wave of a camp, resolved for a difficulty and a party. A group
    is fielded when it names no minDifficulty, or one whose rank is at or under the played `rank`
    (an unknown name fields nothing). count = max(round(count x (1 + (perExtra or
    countPerExtraPlayer) x extras) x countMult), 0); extras = max(party, 1) - 1. `wave` is 0:
    the caller numbers it."""
    extras = max(party_size, 1) - 1
    groups = []
    total = 0
    for group in wave_def["groups"]:
        needs = group.get("minDifficulty")
        if needs is not None and (ranks.get(needs) is None or ranks[needs] > rank):
            continue
        per_extra = group.get("perExtra")
        if per_extra is None:
            per_extra = combat_cfg["coop"]["countPerExtraPlayer"]
        count = max(luau_round(group["count"] * (1 + per_extra * extras) * scales["countMult"]), 0)
        groups.append({"kind": group["kind"], "count": count})
        total += count
    return {
        "wave": 0,
        "groups": groups,
        "total": total,
        "boss": wave_def.get("boss"),
        "bossHpMult": 1 + combat_cfg["coop"]["bossHpPerExtraPlayer"] * extras,
        "hpScale": scales["hpScale"],
        "plateScale": scales["plateScale"],
        "damageScale": scales["damageScale"],
        "regenShare": regen_share,
        "rewardMult": scales["rewardMult"],
    }


def kill_reward(rewards, kind, reward_mult):
    """Combat.KillReward (L1b-15) -- (round(cash x rewardMult), round(materials x rewardMult))
    for one kill of `kind`; a kind with no rewards entry pays (0, 0)."""
    reward = rewards.get(kind)
    if reward is None:
        return 0, 0
    return luau_round(reward["cash"] * reward_mult), luau_round(reward["materials"] * reward_mult)


def clear_bonus(stock, rewards, reward_mult, share):
    """Combat.ClearBonus (L1b-W2-21) -- `share` of what a camp's whole stock {kind: bodies} pays:
    KillReward per kind (an unpriced kind adds nothing), summed, rounded once at the end."""
    cash = materials = 0
    for kind, count in stock.items():
        each, each_materials = kill_reward(rewards, kind, reward_mult)
        cash += count * each
        materials += count * each_materials
    return luau_round(share * cash), luau_round(share * materials)


def wave_stock(stock, spec, elite=None):
    """Combat.WaveStock (L1b-W2-21) -- what a wave queued, added to a locking camp's stock: every
    group of the spec and the director's extra elite. Never the boss or its calls."""
    for group in spec["groups"]:
        stock[group["kind"]] = stock.get(group["kind"], 0) + group["count"]
    if elite is not None:
        stock[elite] = stock.get(elite, 0) + 1


def dead_fraction(spawned, queued_alive):
    """Combat.DeadFraction (L1b-W2-26) -- the merge test's share of the waves' bodies dead:
    `queued_alive` leaves out every body of a group (residents, a tent's)."""
    if spawned <= 0:
        return 0
    return min(max((spawned - max(queued_alive, 0)) / spawned, 0), 1)


def split_carry(pool, shares, carry, cash_mults=None):
    """Combat.SplitCarry (L1b-15) -- one kill's pool split the moment it falls. Each member is
    paid the whole units of (pool x share, cash x their cash multiplier, + their carry), floored
    with a 1e-9 allowance, and keeps the fraction in `carry` (mutated) for their next credit. A
    share that is not a finite number of at least 0 pays nothing and leaves that carry as it
    was; a member not in `shares` keeps theirs."""
    split = {}
    for user, share in shares.items():
        if not (isinstance(share, (int, float)) and share >= 0 and share < math.inf):
            continue
        held = carry.get(user)
        if held is None:
            held = {"cash": 0, "materials": 0, "valor": 0}
            carry[user] = held
        mult = (cash_mults.get(user) if cash_mults is not None else None)
        mult = 1 if mult is None else mult
        paid = {}
        for key, exact in (("cash", pool["cash"] * share * mult + held["cash"]),
                           ("materials", pool["materials"] * share + held["materials"]),
                           ("valor", pool["valor"] * share + held["valor"])):
            whole_units = math.floor(exact + 1e-9)
            paid[key] = whole_units
            held[key] = max(exact - whole_units, 0)
        split[user] = paid
    return split


def burst_seconds(target_wave_seconds, bursts, tempo_value):
    """Combat.BurstSeconds -- targetWaveSeconds / bursts / tempo; targetWaveSeconds when
    bursts <= 0 or tempo <= 0."""
    if bursts <= 0 or tempo_value <= 0:
        return target_wave_seconds
    return target_wave_seconds / bursts / tempo_value


def crowd_bursts(spec, burst):
    """WaveService's queue (ruling 15): each group, in order, as bursts of up to `burst` bodies.
    Returns [(kind, bodies)]."""
    size = max(math.floor(burst), 1)
    out = []
    for group in spec["groups"]:
        left = group["count"]
        while left > 0:
            take = min(size, left)
            out.append((group["kind"], take))
            left -= take
    return out


# --------------------------------------------------------------------------
# Shared fixtures
# --------------------------------------------------------------------------


NO_ASCENSION = {"melee": 0, "ranged": 0}


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
        self.legacy_gained = result.legacy_gained
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


def greedy_curves(game, eras, legacy=0, rebirth_count=0):
    """The default `sim_economy` playthrough: greedy, free, legacy carried. `legacy` and
    `rebirth_count` start a later lap (assertion 22 reads lap 2's Orbital LegacyMult)."""
    curves = []
    offset = 0
    for era in eras:
        result = se.simulate_era(era, game, legacy, "greedy", None, True, rebirth_count)
        curves.append(Curve(era, result, offset, legacy))
        offset += result.seconds
        legacy += result.legacy_gained
    return curves


def run_pause(run_seconds, clear_cash, stop_after=None):
    """sim_economy.simulate_era's pause hook (L4 W3, assertion 24): Forest Road back to back from the
    era's first second. The player buys, then leaves; for the run's seconds he buys nothing while
    the city earns on (offline.expeditionEfficiency 1.0); the clear's cash lands as he returns, he
    buys and leaves again. A copy of the cash study's runner.py ("nonstop"), as a hook. With
    `stop_after` k (the L4 W3 fix round's F17, the review's never_faster.py "stop-after-k"), he
    stays after his k-th return and builds every second to the era's end; trip["runs"] counts the
    departures either way."""
    trip = {"back": 0, "runs": 0, "home": False}

    def pause(second):
        if trip["home"]:
            return False, 0
        if second < trip["back"]:
            return True, 0
        landed = clear_cash if trip["runs"] > 0 else 0
        if stop_after is not None and trip["runs"] >= stop_after:
            trip["home"] = True  # he stays from his k-th return; that clear's cash lands once
            return False, landed
        trip["runs"] += 1
        trip["back"] = second + run_seconds
        return False, landed

    return pause, trip


def era_state(curve):
    """A free player's state at the start of `curve`'s era (legacy carried in, an empty shop)."""
    return {"era": curve.index, "rebirthCount": 0, "legacy": curve.legacy_in,
            "legacyShop": se.empty_shop_state(), "combat": new_combat_profile()}


# --------------------------------------------------------------------------
# Reports
# --------------------------------------------------------------------------


def fmt_rate(value):
    return f"{se.fmt_cash(value)}/s"


def print_ladder(armory, curves):
    """L3-1..L3-4: the ladder of 20, each tier's band, price and trophy, and every family's window.
    The city's income gates nothing since L3 (Ben, 2026-10-20), so the C0 unlock table is gone."""
    proving = _load(CONFIG_DIR / "ProvingGrounds.json")
    ladder = armory.get("ladder") or {}
    print("Armory ladder (L3) -- one ladder of 20 for every weapon family; the tier belongs to the family")
    print(f"  {'tier':>4} {'x range':>10} {'hp melee':>8} {'hp ranged':>9} {'MaxHp t/t':>9} "
          f"{'band':>4} {'level':<11} {'material':<9} {'cost':>5}  trophy")
    for tier in range(1, ladder_size(armory) + 1):
        band, position = band_of(armory, tier)
        entry = (ladder.get("bands") or [])[band - 1]
        material, cost = tier_cost(armory, tier)
        both = {"melee": tier, "ranged": tier}
        trophy = (f"needs the {' or '.join([ladder.get('starDifficulty')] + list(ladder.get('starAlso') or []))} star"
                  if position == ladder.get("bandSize") else "")
        print(f"  {tier:>4} {multiplier(armory, tier):>10,.4f} {weapon_hp(armory, 'melee', tier, 0):>8,.0f} "
              f"{weapon_hp(armory, 'ranged', tier, 0):>9,.0f} {max_hp(armory, both, NO_ASCENSION):>9,.0f} "
              f"{band:>4} {entry['levelId']:<11} {material:<9} "
              f"{cost if tier > 1 else '-':>5}  {trophy}")
    print(f"  the range's own body: {range_hp(armory):g} (scale 1 there)")
    print("  windows (start-top), in shelf order (by start, melee before ranged, then name):")
    weapons = proving["weapons"]
    order = sorted(weapons, key=lambda f: ((window(armory, f) or (99, 99))[0], weapons[f]["slot"] != "melee",
                                          weapons[f]["name"]))
    for family in order:
        span = window(armory, family)
        bar = "".join("#" if span and span[0] <= t <= span[1] else "." for t in range(1, ladder_size(armory) + 1))
        print(f"    {weapons[family]['name']:<15} {weapons[family]['slot']:<6} "
              f"{(f'{span[0]}-{span[1]}' if span else 'none'):>6}  [{bar}]")
    print()
    print("  era income envelope (greedy, legacy carried):")
    for curve in curves:
        print(
            f"    {curve.era['name']:<14} {se.fmt_time(curve.seconds):>8}  "
            f"start {fmt_rate(curve.ips[0]):>11}  median {fmt_rate(curve.median()):>11}  "
            f"peak {fmt_rate(curve.peak):>11}"
        )
    print()


def reference_second(curve):
    """Assertion 4's moment in the greedy era: its middle. Until L3 it was when the city's persisted
    income reached the recommended gear's unlockRate; Ben dropped the income gate (2026-10-20), so a
    run can come at any time, and the middle is the moment C0's fallback already used."""
    return curve.seconds // 2


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
    top = {"melee": 12, "ranged": 12}  # the starters' top (L3-3): where Ascension would be bought
    for level in range(1, len(armory["ascension"]["levels"]) + 1):
        cost = ascension_cost(armory, level)
        materials = " + ".join(f"{amount} {name}" for name, amount in cost["materials"].items())
        hits = damage_scale(armory, top["melee"], level, False)
        print(
            f"  Ascension {level}: {materials}, {cost['valor']} Valor -> top-tier hits "
            f"x{hits:,.2f} (x{hits / damage_scale(armory, top['melee'], 0, False):.2f}), MaxHp "
            f"{max_hp(armory, top, {'melee': level, 'ranged': level}):,.0f}"
        )
    state = {
        "era": 1,
        "rebirthCount": 0,
        "legacy": 0,
        "legacyShop": se.empty_shop_state(),
        "combat": new_combat_profile(),
    }
    rewards = combat_cfg.get("rewards")
    print(f"  CombatCashMult at legacy 0, era 1 -> x{combat_cash_mult(state, game, shop, rewards, 1):,.2f}")
    state["legacy"] = 261
    print(
        f"  CombatCashMult at legacy 261, era 3 (the Metropolis entry) -> x{se.legacy_mult(261, game):.2f} x "
        f"{era_cash_mult(rewards, 3):,} = x{combat_cash_mult(state, game, shop, rewards, 3):,.0f}"
    )
    print(f"  EraCashMult by era 1..5 -> {[era_cash_mult(rewards, era) for era in range(1, 6)]}; with no "
          f"rewards block -> {era_cash_mult(None, 4)}")
    built = {"forestRoad": True}
    combat = state["combat"]
    combat["materials"]["Timber"] = 99
    print(f"  UpgradeVerdict broadsword T1->T2 with 99 Timber -> "
          f"{upgrade_verdict(armory, combat, 'broadsword', True, True, built)}; with 100 -> ", end="")
    combat["materials"]["Timber"] = 100
    print(f"{upgrade_verdict(armory, combat, 'broadsword', True, True, built)}; the gate shut -> "
          f"{upgrade_verdict(armory, combat, 'broadsword', True, False, built)}; unowned -> "
          f"{upgrade_verdict(armory, combat, 'warhammer', False, True, built)}; no window -> "
          f"{upgrade_verdict(armory, combat, 'stick', True, True, built)}")
    combat["tiers"]["broadsword"] = 3
    combat["materials"]["Timber"] = 500
    print(f"  UpgradeVerdict broadsword T3->T4 with 500 Timber, no Hard star -> "
          f"{upgrade_verdict(armory, combat, 'broadsword', True, True, built)}; with it -> ", end="")
    combat["stars"]["forestRoad"] = {"hard": True}
    print(f"{upgrade_verdict(armory, combat, 'broadsword', True, True, built)}; T4->T5 (the Castle, no file) -> ", end="")
    combat["tiers"]["broadsword"] = 4
    print(f"{upgrade_verdict(armory, combat, 'broadsword', True, True, built)}; the Splitbow (8-8) -> "
          f"{upgrade_verdict(armory, combat, 'splitbow', True, True, built)}")
    print(f"  TierOf a saved 30 on the Longbow (1-12) -> {tier_of(armory, {'tiers': {'longbow': 30}}, 'longbow')}; "
          f"the Warhammer unsaved -> {tier_of(armory, {}, 'warhammer')}; LegacyRefund at gear 3/3 -> "
          f"{legacy_refund(armory, {'melee': 3, 'ranged': 3})}")
    print(f"  CanAscend at rebirthCount 0 -> {can_ascend(armory, state, 'melee')}")
    state["era"] = 3
    touch_highest_era(state)
    print(f"  TouchHighestEra at era 3 -> highestEra {state['combat']['highestEra']}")
    # The degrade-quietly guards, mirrored from Armory.luau / Combat.luau.
    print(
        f"  Guards: Tempo window 0s -> {tempo(30, 0, 1.0, director):.2f}; "
        f"AwayEfficiency stamp -60s -> {away_efficiency(3600, -60, base, expedition):.2f}, "
        f"stamp 2h in a 1h absence -> {away_efficiency(3600, 7200, base, expedition):.2f}; "
        f"AscensionCost level 9 -> {ascension_cost(armory, 9)}"
    )
    print()


# --------------------------------------------------------------------------
# --check: the levels' gates and pay, the ladder and the climb
# --------------------------------------------------------------------------


def level_fieldable(level, kinds):
    """Every kind a level can put on the floor at any difficulty: its groups, its bosses, and
    whatever any of those calls, followed to the end."""
    todo = []
    for stage in level["stages"]:
        for wave in stage.get("waves") or []:
            todo += [group["kind"] for group in wave["groups"]]
            if wave.get("boss"):
                todo.append(wave["boss"]["kind"])
    if level["crowd"].get("eliteKind"):
        todo.append(level["crowd"]["eliteKind"])
    found = []
    while todo:
        name = todo.pop(0)
        if name in found:
            continue
        found.append(name)
        for attack in (kinds.get(name) or {}).get("attacks") or []:
            if attack["shape"] == "summon" and attack.get("summon"):
                todo.append(attack["summon"])
    return found


def level_gates(file, level, layout, expeditions, proving, combat_cfg):
    """The contract's gates on one level file (assertion 20); returns the problems found."""
    kinds = proving["crowd"]["kinds"]
    names = expeditions["difficulties"]
    problems = []
    if level is None:
        return [f"{file['id']} does not resolve (no stages, difficulties or crowd block)"]
    for kind in level_fieldable(level, kinds):
        if kind not in level["crowd"]["rewards"]:
            problems.append(f"{kind} can be fielded but has no rewards entry")
        if kind not in kinds:
            problems.append(f"{kind} is no crowd kind")
    for name in level["difficulties"]:
        if name not in names:
            problems.append(f"difficulty {name} is not in Expeditions.json")
    missing = [name for name in names if name not in level["difficulties"]]
    if missing:
        problems.append(f"lacks the difficulties {missing}")
    for name, mult in LEVEL_REWARD_MULT.items():
        if name in level["difficulties"] and level["difficulties"][name]["rewardMult"] != mult:
            problems.append(f"{name} rewardMult {level['difficulties'][name]['rewardMult']} is not {mult}")
    stages = level["stages"]
    for index, stage in enumerate(stages):
        if stage["kind"] not in ("travel", "camp"):
            problems.append(f"stage {index + 1} is a {stage['kind']}")
        if index > 0 and stages[index - 1]["kind"] == stage["kind"]:
            problems.append(f"stages {index} and {index + 1} are both {stage['kind']}")
        for wave in stage.get("waves") or []:
            for group in wave["groups"]:
                needs = group.get("minDifficulty")
                if needs is not None and needs not in names:
                    problems.append(f"minDifficulty {needs} is no difficulty")
    if not stages or stages[-1]["kind"] != "camp":
        problems.append("its last stage is not a camp")
    zones = {camp["id"] for camp in layout["camps"]} if layout is not None else set()
    for stage in stages:
        if stage["kind"] == "camp" and stage.get("zone") not in zones:
            problems.append(f"camp stage {stage['name']} names the zone {stage.get('zone')}, which the layout lacks")
    if level["runCapSeconds"] < CROWD_RUN_CAP_RATIO * level["targetMinutes"] * 60:
        problems.append(f"runCapSeconds {level['runCapSeconds']} is under {CROWD_RUN_CAP_RATIO:g} x targetMinutes")
    return problems


def level_pay(level, difficulty, ranks, combat_cfg, summon_kills, sent=None, refused=None):
    """What a whole solo clear of a level pays at a difficulty (Combat.KillReward per kill, L1b-15):
    every resident of every camp (by minDifficulty, never countMult: L1b-10), the first `sent`
    {camp id: bodies} of each open camp's tent stock in its order (L1b-W4-28: a tent sends only a
    camp cleared ahead of its pace; none by default, the clear at pace), every configured body of
    the boss room's waves, every boss with its Valor, each camp's clear bonus (L1b-W4-30:
    Combat.ClearBonus over what it fielded, StageFlow.Fielded), and `summon_kills` {boss kind:
    {kind: kills}} of what the bosses call. `refused` {camp id: stock indices, 1-based} are tent bodies
    the crowd refused: sent, never fielded, so neither killed nor priced (fix round R12). Returns (totals, per-camp and per-stage rows, kills by
    kind, each camp's bonus {camp id: (cash, materials)})."""
    import sim_range as sr

    scales = level["difficulties"][difficulty]
    rewards = level["crowd"]["rewards"]
    totals = {"cash": 0, "materials": 0, "valor": 0}
    rows = []
    kills = {}
    stocks = {}  # what each camp fielded by kind, the clear bonus's base
    locking = {stage.get("zone") for stage in level["stages"] if stage["kind"] == "camp"}
    for config in level.get("camps") or []:
        cash = materials = bodies = 0
        stock = stocks.setdefault(config["id"], {})
        units = [u for group in config.get("residents") or []
                 for u in sr.fielded_units(group.get("units") or [], ranks[difficulty], ranks)[0]]
        tent = config.get("tent")
        out = (sent or {}).get(config["id"], 0)
        if tent is not None and config["id"] not in locking and out > 0:
            stock_kinds = [u["kind"] for u in sr.fielded_units(tent.get("units") or [], ranks[difficulty], ranks)[0]
                           for _ in range(u["count"])]
            skipped = set((refused or {}).get(config["id"]) or ())
            units += [{"kind": kind, "count": 1} for index, kind in enumerate(stock_kinds[:out], 1)
                      if index not in skipped]
        for unit in units:
            c, m = kill_reward(rewards, unit["kind"], scales["rewardMult"])
            cash += c * unit["count"]
            materials += m * unit["count"]
            bodies += unit["count"]
            kills[unit["kind"]] = kills.get(unit["kind"], 0) + unit["count"]
            stock[unit["kind"]] = stock.get(unit["kind"], 0) + unit["count"]
        rows.append((f"{config['name']} (residents{f', {out} from the tent' if out > 0 else ''})", bodies, cash,
                     materials, 0))
        totals["cash"] += cash
        totals["materials"] += materials
    for stage in level["stages"]:
        if stage["kind"] != "camp":
            continue
        cash = materials = valor = bodies = 0
        stock = stocks.setdefault(stage.get("zone"), {})
        for wave in stage.get("waves") or []:
            spec = camp_wave(wave, level["crowd"]["regenShare"], scales, ranks[difficulty], ranks, 1, combat_cfg)
            wave_stock(stock, spec)
            fielded = [(group["kind"], group["count"]) for group in spec["groups"]]
            boss = spec["boss"]
            if boss is not None:
                fielded.append((boss["kind"], 1))
                fielded += list((summon_kills.get(boss["kind"]) or {}).items())
                valor += luau_round(boss["valor"] * spec["rewardMult"])
            for kind, count in fielded:
                c, m = kill_reward(level["crowd"]["rewards"], kind, spec["rewardMult"])
                cash += c * count
                materials += m * count
                bodies += count
                kills[kind] = kills.get(kind, 0) + count
        rows.append((stage["name"], bodies, cash, materials, valor))
        totals["cash"] += cash
        totals["materials"] += materials
        totals["valor"] += valor
    # The clear bonus (L1b-W2-21), once per camp that clears: every open camp that holds a
    # resident at this difficulty (its `campClear`) and every locking camp (its `open`; a Studio
    # skip pays nothing and never happens in a clear).
    bonus = level["crowd"].get("clearBonus")
    share = bonus.get("share") if isinstance(bonus, dict) else None
    paid = {}
    for camp_id, stock in stocks.items():
        if not share or not stock:
            continue
        c, m = clear_bonus(stock, rewards, scales["rewardMult"], share)
        paid[camp_id] = (c, m)
        totals["cash"] += c
        totals["materials"] += m
    if paid:
        rows.append(("clear bonus (" + ", ".join(f"{k} {c:,}/{m}" for k, (c, m) in paid.items()) + ")", 0,
                     sum(c for c, _m in paid.values()), sum(m for _c, m in paid.values()), 0))
    return totals, rows, kills, paid


def forest_summons(proving, report):
    """{difficulty: {boss kind: {called kind: kills}}} from the reacting player's boss fights at
    each difficulty's gear: what the boss called less what was dismissed with it."""
    import sim_range as sr

    found = {}
    for difficulty, row in report["difficulties"].items():
        boss = row["boss"]
        called = [a.get("summon") for a in proving["crowd"]["kinds"][sr.FOREST_BOSS]["attacks"] if a["shape"] == "summon"]
        found[difficulty] = {sr.FOREST_BOSS: {called[0]: boss["kills"] - 1}} if boss is not None and called else {}
    return found


def print_level(level_id, combat_cfg):
    """A level's camps and what a clear pays at each difficulty, and its measured clears."""
    import sim_range as sr

    proving = sr.load_config(sr.CONFIG_PATH)
    report = sr.forest_report(proving, careless=False, level_id=level_id, human=False, ranged=False, below=False,
                             scenarios=False)
    if report is None:
        return
    level, ctx = report["level"], report["ctx"]
    summons = forest_summons(proving, report)
    names = ctx["expeditions"]["difficultyNames"]
    print(f"{level['name']} ({level['id']}) -- LEVEL, solo; targetMinutes {level['targetMinutes']}, run cap "
          f"{level['runCapSeconds']} s, burst {level['crowd']['burst']}")
    normal = None
    for difficulty, row in report["difficulties"].items():
        pay, rows, kills, _bonus = level_pay(level, difficulty, ctx["ranks"], combat_cfg, summons[difficulty])
        normal = normal or pay
        clears = ", ".join(f"{r['end']} {se.fmt_time(r['at'])}" for r in row["runs"])
        print(f"  {names.get(difficulty, difficulty)} (recommended tier {row['scales']['recommendedTier']}, measured at "
              f"gear {row['gear']['melee']}/{row['gear']['ranged']}): {pay['cash']:,.0f} cash (x{pay['cash'] / normal['cash']:.2f}), "
              f"{pay['materials']:.0f} {level['material']} (x{pay['materials'] / normal['materials']:.2f}), {pay['valor']} Valor; "
              f"clears {clears}")
        for name, bodies, cash, materials, valor in rows:
            print(f"    {name:<22} {bodies:>4.0f} bodies  {cash:>9,.0f} cash  {materials:>5.0f} {level['material']}  {valor:>3} Valor")
        print("    kills: " + ", ".join(f"{kind} {count:.0f}" for kind, count in kills.items()))
    print()


def ladder_problems(armory, proving):
    """Assertion 1 (L3-29): Armory.Problems on the shipped families, then the shipped values against
    L3-1..L3-4 and L3-8. One line per problem."""
    families = sorted(proving["weapons"])
    found = list(problems(armory, families))
    ladder = armory.get("ladder") or {}
    damage = ladder.get("damage") or []
    want = [round(LADDER_FIRST * LADDER_STEP ** (t - 1), 4) for t in range(1, LADDER_SIZE + 1)]
    if damage != want:
        found.append(f"ladder.damage is not the {LADDER_SIZE} values {LADDER_FIRST} x {LADDER_STEP}^(t-1) to 4 decimals")
    hp = ladder.get("hp") or {}
    for slot, old in LADDER_HP_T1_T11.items():
        if (hp.get(slot) or [])[:len(old)] != old:
            found.append(f"ladder.hp.{slot} T1-T{len(old)} are not the old slot tiers 2-12 ({old})")
    for tier, want_hp in LADDER_MAX_HP.items():
        got = max_hp(armory, {"melee": tier, "ranged": tier}, NO_ASCENSION)
        if got != want_hp:
            found.append(f"MaxHp at T{tier}/T{tier} is {got:g}, not {want_hp}")
    if range_hp(armory) != LADDER_RANGE_HP:
        found.append(f"RangeHp is {range_hp(armory):g}, not {LADDER_RANGE_HP}")
    bands = ladder.get("bands") or []
    if len(bands) != LADDER_BANDS or ladder.get("bandSize") != LADDER_BAND_SIZE:
        found.append(f"the ladder is not {LADDER_BANDS} bands of {LADDER_BAND_SIZE}")
    if [b.get("levelId") for b in bands] != list(LADDER_BAND_LEVELS):
        found.append(f"the bands' levels are not {', '.join(LADDER_BAND_LEVELS)} in order")
    elif bands[0].get("material") != "Timber":
        found.append("the first band (Forest Road) is not paid in Timber")
    prices = [tier_cost(armory, t)[1] for t in range(2, LADDER_BAND_SIZE + 1)]
    if prices != list(LADDER_FOREST_COSTS):
        found.append(f"T2..T{LADDER_BAND_SIZE} cost {prices}, not {list(LADDER_FOREST_COSTS)} Timber (Ben)")
    if ladder.get("starDifficulty") != "hard":
        found.append(f"starDifficulty is {ladder.get('starDifficulty')!r}, not hard (the Hard star is the trophy)")
    if ladder.get("starAlso") != list(LADDER_STAR_ALSO):
        found.append(f"starAlso is {ladder.get('starAlso')!r}, not {list(LADDER_STAR_ALSO)} (R1: a harder star "
                     "opens a band top too)")
    windows = {f: window(armory, f) for f in families}
    wrong = [f"{f} {windows[f]} (needs {LADDER_WINDOWS.get(f)})" for f in families if windows[f] != LADDER_WINDOWS.get(f)]
    if wrong or sorted(armory.get("windows") or {}) != families:
        found.append("the windows are not L3-3's for every weapons family: " + ", ".join(wrong[:4]))
    starters = set((proving.get("loadout") or {}).values())
    late = [f for f in starters if (windows.get(f) or (0, 0))[0] != 1]
    if late:
        found.append(f"a starter's window does not start at T1: {late}")
    frozen = [{"material": material, "amount": amount} for material, amount in LEGACY_GEAR_COSTS]
    if (armory.get("legacy") or {}).get("gearCosts") != frozen:
        found.append("legacy.gearCosts is not the twelve slot-tier prices it froze (LEGACY_GEAR_COSTS)")
    return found


def ladder_note(armory, proving):
    """Assertion 1's line when it holds."""
    refund = legacy_refund(armory, {"melee": 3, "ranged": 3})
    return (f"{ladder_size(armory)} tiers x{multiplier(armory, 1):g} .. x{multiplier(armory, ladder_size(armory)):,.0f}; "
            f"MaxHp T1 {max_hp(armory, {'melee': 1, 'ranged': 1}, NO_ASCENSION):g}, T3 "
            f"{max_hp(armory, {'melee': 3, 'ranged': 3}, NO_ASCENSION):g}, T5 "
            f"{max_hp(armory, {'melee': 5, 'ranged': 5}, NO_ASCENSION):g}, T20 "
            f"{max_hp(armory, {'melee': 20, 'ranged': 20}, NO_ASCENSION):,.0f}; RangeHp {range_hp(armory):g}; Forest T2/T3/T4 "
            f"{'/'.join(str(tier_cost(armory, t)[1]) for t in (2, 3, 4))} {tier_cost(armory, 2)[0]}, T4 needs the "
            f"{' or '.join([armory['ladder']['starDifficulty']] + list(armory['ladder'].get('starAlso') or []))} star; "
            f"{len(armory['windows'])} windows as L3-3; the v8 refund of a 3/3 "
            f"profile {refund}; Armory.Problems on {len(proving['weapons'])} families: none")


def climb_runs(proving, report, gear, difficulty, cut, memo, fire=None):
    """sim_range's reacting player (default melee only) through a level with the starters at `gear`
    {melee tier, ranged tier}, on the shortcut layout when `cut`, carrying `fire` (the fire family)
    in the ranged slot when given: his bar is then the Broadsword's and the fire family's at its own
    tier (gearOf's held pair, the L3 W1 fix round's R2); he fights with the sword alone either way.
    Every seed's run, memoised on its key."""
    import sim_range as sr

    key = (difficulty, gear["melee"], gear["ranged"], cut, fire)
    if key not in memo:
        ctx, level = report["ctx"], report["level"]
        layout = report["cut"] if cut else report["layout"]
        scales = level["difficulties"][difficulty]
        held = (proving["loadout"]["melee"], fire) if fire is not None else None
        view, hp = sr.level_view(proving, scales, level["crowd"]["regenShare"], ctx["armory"], gear, held=held)
        policy = sr.THREAT_POLICIES["mission"] if fire is None else dict(sr.THREAT_POLICIES["mission"], holds=(fire,))
        memo[key] = [sr.LevelRun(view, hp, ctx, level, layout, difficulty, policy, seed).run()
                     for seed in sr.MISSION_SEEDS]
    return memo[key]


def starter_climb(proving, armory, report):
    """L3-29: the greedy solo player takes both starters from T1 to T4 on Forest Road (Timber only).
    Each run is measured by sim_range at the gear he holds then (mean of the seeds: Timber, Valor and
    minutes of a clear, the clock from the start point to the boss room's clear). Normal until both
    starters reach Hard's recommendedTier, then Hard. Double Jump is bought with the first Valor that
    covers it; the next run takes the lookout's chest (its Timber, Valor and the fire family); the
    run after carries the fire family in the ranged slot into the tunnel (the cache's chest, and the
    shortcut is found); every later run takes the tunnel. After each run he buys, cheapest first,
    every starter tier Armory.UpgradeVerdict allows. Returns the runs, each with what it paid and
    what was bought after it."""
    import sim_range as sr

    level = report["level"]
    secrets = level.get("secrets") or {}
    expeditions = sr.load_config(sr.EXPEDITIONS_PATH)
    sold = {a["id"]: a for a in (expeditions.get("abilities") or {}).get("list") or []}
    jump_price = ((sold.get("doubleJump") or {}).get("price") or {}).get("valor", 0)
    built = {file["id"]: True for file in sr.load_level_files()}
    melee, ranged = proving["loadout"]["melee"], proving["loadout"]["ranged"]
    flame = report["flame"]
    lookout = next((sid for sid, e in secrets.items() if e.get("family") == flame), None)
    layout_secrets = {s["id"]: s for s in report["layout"].get("secrets") or []}
    cache = next((sid for sid, s in layout_secrets.items() if s.get("needs") == "fire"), None)
    hard_tier = level["difficulties"]["hard"]["recommendedTier"]
    combat = new_combat_profile()
    timber_key = level["material"]
    state = {"jump": False, "lookout": False, "cache": False}
    memo = {}
    runs = []
    while (tier_of(armory, combat, melee) < LADDER_BAND_SIZE or tier_of(armory, combat, ranged) < LADDER_BAND_SIZE) \
            and len(runs) < CLIMB_RUN_LIMIT:
        held = held_tiers(armory, combat, melee, ranged)
        difficulty = "hard" if min(held.values()) >= hard_tier else "normal"
        carry_fire = state["lookout"] and not state["cache"] and cache is not None
        cut = state["cache"] or carry_fire
        gear = dict(held)
        measured = climb_runs(proving, report, gear, difficulty, cut and report["cut"] is not None, memo,
                              fire=flame if carry_fire else None)
        cleared = [r for r in measured if r["end"] == "cleared"]
        timber = sum(r["wallet"]["materials"] for r in measured) / len(measured)
        valor = sum(r["wallet"]["valor"] for r in measured) / len(measured)
        minutes = sum(r["at"] for r in measured) / len(measured) / 60
        chests = []
        if state["jump"] and not state["lookout"] and lookout is not None:
            timber += secrets[lookout].get("materials", 0)
            valor += secrets[lookout].get("valor", 0)
            combat["families"][flame] = True
            state["lookout"] = True
            chests.append(lookout)
        elif carry_fire:
            timber += secrets[cache].get("materials", 0)
            valor += secrets[cache].get("valor", 0)
            state["cache"] = True
            chests.append(cache)
        combat["materials"][timber_key] = combat["materials"].get(timber_key, 0) + timber
        combat["valor"] += valor
        if len(cleared) == len(measured):
            stars = combat["stars"].setdefault(level["id"], {})
            if not stars.get(difficulty):
                stars[difficulty] = True
                first = level["difficulties"][difficulty].get("firstClear") or {}
                if first.get("family"):
                    combat["families"][first["family"]] = True
                combat["valor"] += first.get("valor", 0)
        if not state["jump"] and combat["valor"] >= jump_price:
            combat["valor"] -= jump_price
            state["jump"] = True
        bought = []
        while True:
            options = []
            for family in (melee, ranged):
                owned = family in (melee, ranged) or combat["families"].get(family)
                if upgrade_verdict(armory, combat, family, owned, True, built) is None:
                    options.append((tier_cost(armory, next_tier(armory, combat, family))[1], family))
            if not options:
                break
            _, family = min(options)
            upgrade(armory, combat, family, True, True, built)
            bought.append(f"{proving['weapons'][family]['name']} T{tier_of(armory, combat, family)}")
        runs.append({"difficulty": difficulty, "gear": gear, "cut": cut, "fire": carry_fire, "timber": timber,
                     "valor": valor, "minutes": minutes, "cleared": len(cleared), "seeds": len(measured),
                     "downs": sum(r["downs"] for r in measured), "chests": chests, "bought": bought,
                     "wallet": combat["materials"].get(timber_key, 0)})
    return {"runs": runs, "combat": combat, "done": tier_of(armory, combat, melee) >= LADDER_BAND_SIZE
            and tier_of(armory, combat, ranged) >= LADDER_BAND_SIZE}


def climb_verdict(climb, report, armory):
    """Assertion 2's verdict and line."""
    import sim_range as sr

    level = report["level"]
    runs = climb["runs"]
    minutes = sum(r["minutes"] for r in runs)
    first = runs[0]["timber"] if runs else 0
    hard = level["difficulties"]["hard"]
    brutal = level["difficulties"]["brutal"]
    boss_valor = report["difficulties"]["normal"]["runs"][0]["wallet"]["valor"]
    hard_valor = luau_round(boss_valor * hard["rewardMult"])
    brutal_first = (brutal.get("firstClear") or {}).get("valor")
    family = (hard.get("firstClear") or {}).get("family")
    arrives = (window(armory, family) or (None,))[0] if family else None
    # R2 (the L3 W1 fix round): sim_range rates the fire family's pair at the gear he holds on the run
    # whose chest pays it (PAIR_FLAME_GEAR); the climb is where that gear comes from.
    lookout = next((sid for sid, e in (level.get("secrets") or {}).items() if e.get("family") == report["flame"]), None)
    fire_gear = next((r["gear"] for r in runs if lookout in r["chests"]), None)
    lo_r, hi_r = CLIMB_RUNS
    lo_m, hi_m = CLIMB_MINUTES
    good = (climb["done"] and lo_r <= len(runs) <= hi_r and lo_m <= minutes <= hi_m and first >= CLIMB_FIRST_TIMBER
            and all(r["cleared"] == r["seeds"] for r in runs) and hard_valor == HARD_VALOR
            and brutal_first == BRUTAL_FIRST_VALOR and arrives == hard["recommendedTier"]
            and fire_gear == sr.PAIR_FLAME_GEAR)
    steps = "; ".join(
        f"run {i} {r['difficulty']} at T{r['gear']['melee']}/T{r['gear']['ranged']}"
        + (" with the fire family" if r["fire"] else "") + (" (tunnel)" if r["cut"] else "")
        + f" {r['minutes']:.2f} min, {r['timber']:.0f} Timber" + (f" + {', '.join(r['chests'])}" if r["chests"] else "")
        + f" -> {', '.join(r['bought']) or 'nothing bought'} ({r['wallet']:.0f} left)"
        + ("" if r["cleared"] == r["seeds"] else f", {r['seeds'] - r['cleared']} of {r['seeds']} seeds not cleared")
        for i, r in enumerate(runs, 1))
    return good, (f"both starters T1 -> T{LADDER_BAND_SIZE}{'' if climb['done'] else ' NOT reached'} in {len(runs)} runs "
                  f"(needs {lo_r}-{hi_r}), {minutes:.1f} min of clears (needs {lo_m:g}-{hi_m:g}); the first Normal clear "
                  f"{first:.0f} Timber (needs >= {CLIMB_FIRST_TIMBER}); a Hard clear {hard_valor} Valor (needs "
                  f"{HARD_VALOR}), the Brutal first clear {brutal_first} (needs {BRUTAL_FIRST_VALOR}); Hard's first clear "
                  f"gives {family} at T{arrives} (Hard's recommendedTier {hard['recommendedTier']}); the {report['flame']} "
                  f"comes at "
                  + (f"T{fire_gear['melee']}/T{fire_gear['ranged']}" if fire_gear is not None else "no run")
                  + f" (sim_range PAIR_FLAME_GEAR T{sr.PAIR_FLAME_GEAR['melee']}/T{sr.PAIR_FLAME_GEAR['ranged']}) | {steps}")


class Checks:
    def __init__(self):
        self.failed = 0

    def verdict(self, ok, name, detail):
        if not ok:
            self.failed += 1
        print(f"  {'PASS' if ok else 'FAIL'}  {name}: {detail}")


def mentor_pay(combat_cfg, members, tally, bonus_of=None):
    """WaveService.payMentors (C2, L1b-15) at a boss's kill, pure: `members` [(userId, incomeRate,
    waiting)], `tally` {userId: damage on the boss}. A mentor who is not waiting and whose share of the
    damage reached coop.mentorMinDamageShare is paid Combat.MentorBonus against the rates of the OTHER
    members whose share reached it too. Returns {userId: Valor} of everyone paid (none when nobody hit).
    `bonus_of` stands in for mentor_bonus (L4 W1b fix round F6: check_stage_mirror.py records the calls
    this makes, then replays them with the real Combat.MentorBonus's answers)."""
    bonus_of = bonus_of or mentor_bonus
    total = sum(tally.values())
    if total <= 0:
        return {}
    floor = combat_cfg["coop"]["mentorMinDamageShare"]
    paid = {}
    for user, rate, waiting in members:
        if waiting or tally.get(user, 0) / total < floor:
            continue
        rates = [other_rate for other, other_rate, _w in members
                 if other != user and tally.get(other, 0) / total >= floor]
        bonus = bonus_of(combat_cfg, rate, rates)
        if bonus > 0:
            paid[user] = bonus
    return paid


def mentor_fixtures(combat_cfg):
    """Assertions 12 and 13's boss kills, {name: (members, tally)} for mentor_pay. One list, read by
    those assertions and by tools/check_stage_mirror.py (F6), which replays every Combat.MentorBonus
    call these make against the real Luau: a 10:1-rate duo, an equal duo, a mentee exactly at and one
    stud/s under hostRate x mentorRatio, one mentor carrying two; an idle mentee, one at half the damage
    floor, a small-share newbie beside three veterans, an idle mentor, a waiting mentor, nobody hit."""
    coop = combat_cfg["coop"]
    host = MENTOR_HOST_RATE
    low = MENTOR_HOST_RATE / MENTOR_RATE_RATIO
    edge = MENTOR_HOST_RATE * coop["mentorRatio"]
    floor = coop["mentorMinDamageShare"]
    even = {1: 60.0, 2: 40.0}
    duo = [(1, host, False), (2, low, False)]
    return {
        "wide": (duo, even),
        "equal": ([(1, host, False), (2, host, False)], even),
        "atEdge": ([(1, host, False), (2, edge, False)], even),
        "under": ([(1, host, False), (2, edge - 1, False)], even),
        "two": ([(1, host, False), (2, low, False), (3, low, False)], {1: 50.0, 2: 25.0, 3: 25.0}),
        "idle": (duo, {1: 100.0, 2: 0.0}),
        "shy": (duo, {1: 100.0 * (1 - floor / 2), 2: 100.0 * floor / 2}),
        "mixed": ([(1, host, False), (2, host, False), (3, host, False), (4, low, False)],
                  {1: 32.0, 2: 32.0, 3: 31.0, 4: 5.0}),
        "idleHost": (duo, {1: 0.0, 2: 100.0}),
        "waiting": ([(1, host, True), (2, low, False)], even),
        "nobody": (duo, {}),
    }


def forest_clears(report, ranks, combat_cfg, proving_cfg):
    """{difficulty: (cash, seconds)} for assertions 4, 24 and 25: what a whole Forest Road clear pays in
    cash before any multiplier (level_pay, summons included) and its mean measured clear, rounded to
    a whole second (Normal at the proving gear, Hard at its recommendedTier's preset)."""
    summons = forest_summons(proving_cfg, report)
    out = {}
    for difficulty in NEVER_FASTER_DIFFICULTIES:
        row = report["difficulties"].get(difficulty) or {}
        clears = [r["at"] for r in row.get("runs") or [] if r["end"] == "cleared"]
        cash = level_pay(report["level"], difficulty, ranks, combat_cfg, summons[difficulty])[0]["cash"]
        out[difficulty] = (cash, round(sum(clears) / len(clears)) if clears else None)
    return out


def run_checks(armory, combat_cfg, places, game, eras, shop=None):
    checks = Checks()
    print("sim_combat --check (docs/INTERFACES.md C0 + C2 + L1 + L1b contracts, L3 and L4 W3, thirteen assertions; "
          "3, 7-11 and 14-19 retired with the C1 missions in L4 W1b)")
    curves = greedy_curves(game, eras)
    shop = shop if shop is not None else se.load_legacy_shop_config()
    rewards = combat_cfg.get("rewards")

    # The level reports, measured once by sim_range (assertions 2, 4 and 21 read them).
    import sim_range as sr

    proving_cfg = sr.load_config(sr.CONFIG_PATH)
    level_reports = {level_id: sr.forest_report(proving_cfg, careless=False, level_id=level_id, human=False,
                                                ranged=False, below=False, scenarios=False)
                     for level_id in LEVEL_PAY_TARGETS}
    expeditions = sr.load_config(sr.EXPEDITIONS_PATH)
    ranks = sr.difficulty_ranks(expeditions)
    level_files = sr.load_level_files()

    # 1. L3-1..L3-4 and L3-29: the ladder as Armory.Problems reads it (nothing for the shipped
    #    families), and the shipped numbers held to the contract: 20 tiers rising 1.5 x 1.65^(t-1),
    #    HP T1-T11 = the old slot tiers 2-12 (LADDER_HP_T1_T11, literal since L4 W1b deleted the
    #    slots), MaxHp 155 / 230 / 380 at T1 / T3 / T5, RangeHp 130 (Gear Power went in L4 W3), five bands
    #    of four (the first Forest Road's Timber), costs by position (T2 / T3 / T4 = 100 / 250 / 500),
    #    the Hard star the trophy, L3-3's windows for every family, and `legacy` equal to the twelve
    #    prices it freezes (LEGACY_GEAR_COSTS). (Was "1 unlock ladder": the city's income gates no tier
    #    since L3, Ben 2026-10-20.)
    found = ladder_problems(armory, proving_cfg)
    checks.verdict(not found, "1 ladder           ", "; ".join(found[:5]) if found else ladder_note(armory, proving_cfg))

    # 2. L3-29, solo: one Normal clear pays at least CLIMB_FIRST_TIMBER (T2 for both starters at
    #    once); the greedy climb takes both starters T1 -> T4 in CLIMB_RUNS runs and CLIMB_MINUTES
    #    minutes of measured clears (Normal until both reach Hard's recommendedTier, then Hard; the
    #    lookout once Double Jump is bought, then the cache through the tunnel carrying the fire
    #    family, the tunnel ever after; the Hard star opens T4); a Hard clear pays HARD_VALOR Valor
    #    and the Brutal first clear BRUTAL_FIRST_VALOR; Hard's first clear gives a family whose
    #    window starts at Hard's recommendedTier. (Was "2 power at median": retired with the gate.)
    climb = starter_climb(proving_cfg, armory, level_reports["forestRoad"])
    good, text = climb_verdict(climb, level_reports["forestRoad"], armory)
    checks.verdict(good, "2 forest climb     ", text)

    # 4. What a Normal clear of Forest Road pays (sim_range's measured runs, summons included) times
    #    Combat.CombatCashMult (the lap's LegacyMult x the era's rewards.eraCashMult, L4 W3) is at most
    #    RUN_CASH_CAP_FRACTION of what each era's greedy player still owes its slots at the era's
    #    middle (reference_second); and the first clear after an Advance (it lands one mean measured
    #    Normal clear into the era) is at most FIRST_CLEAR_CAP_FRACTION of what the era still owes
    #    when it lands. L4 W1b re-pointed it from the C1 missions' runs; W3 took it to every era for
    #    MISSIONS_DESIGN 26.8's era multiplier (the cash study's (c) at M = 3, Ben's pick).
    details = []
    ok4 = True
    report = level_reports.get("forestRoad")
    forest_pay = forest_clears(report, ranks, combat_cfg, proving_cfg) if report is not None else {}
    normal_cash, first_second = forest_pay.get("normal", (None, None))
    if len(curves) != len(eras) or report is None or first_second is None:
        ok4 = False
        details.append("no greedy curve for every era, no Forest Road level or no cleared Normal run")
    else:
        for curve in curves:
            mult = combat_cash_mult(era_state(curve), game, shop, rewards, curve.index)
            clear = normal_cash * mult
            middle = reference_second(curve)
            owed_mid = curve.remaining_slot_cost(middle)
            owed_first = curve.remaining_slot_cost(first_second)
            mid_ratio = clear / owed_mid if owed_mid > 0 else math.inf
            first_ratio = clear / owed_first if owed_first > 0 else math.inf
            ok4 = ok4 and mid_ratio <= RUN_CASH_CAP_FRACTION and first_ratio <= FIRST_CLEAR_CAP_FRACTION
            details.append(f"{curve.era['name']} x{mult:,.2f} (x{se.legacy_mult(curve.legacy_in, game):.2f} x "
                           f"{era_cash_mult(rewards, curve.index):,}): {se.fmt_cash(clear)} = {100 * mid_ratio:.2f}% "
                           f"of {se.fmt_cash(owed_mid)} still owed at {se.fmt_time(middle)}, the first clear "
                           f"{100 * first_ratio:.2f}% of {se.fmt_cash(owed_first)} at {se.fmt_time(first_second)}")
        details.append(f"forestRoad Normal {normal_cash:,.0f} cash before the multiplier (needs <= "
                       f"{RUN_CASH_CAP_FRACTION:.0%} at the middle, <= {FIRST_CLEAR_CAP_FRACTION:.0%} at the first clear)")
    checks.verdict(ok4, "4 cash vs era cost ", "; ".join(details))

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

    # 12. Combat.MentorBonus through WaveService.payMentors (mentor_pay), on fixture rates and shares:
    #     a 10:1-rate duo pays the mentor exactly mentorValor at a boss's kill and the mentee nothing;
    #     an equal-rate duo pays nobody; the ratio is strict (a rate exactly hostRate x mentorRatio is
    #     not carried); one mentor carrying two pays twice. (Was a C1 run's boss clear: rewritten pure
    #     in L4 W1b, the only guard on the mentor pay.)
    coop = combat_cfg["coop"]
    valor = coop["mentorValor"]
    edge = MENTOR_HOST_RATE * coop["mentorRatio"]
    pays = {name: mentor_pay(combat_cfg, members, tally)
            for name, (members, tally) in mentor_fixtures(combat_cfg).items()}
    wide, equal, at_edge, under, two = (pays[name] for name in ("wide", "equal", "atEdge", "under", "two"))
    ok12 = (wide == {1: valor} and equal == {} and at_edge == {} and under == {1: valor}
            and two == {1: 2 * valor} and valor > 0)
    checks.verdict(ok12, "12 mentor duo      ",
                   f"10:1 duo pays {wide} (mentorValor {valor}); equal duo {equal}; a mentee at exactly "
                   f"{edge:g}/s (mentorRatio {coop['mentorRatio']}) {at_edge}, at {edge - 1:g}/s {under}; one mentor "
                   f"carrying two {two}")

    # 13. The floors (mentorMinDamageShare): a mentee under it (an idle alt) earns its mentor nothing;
    #     a starter-gear newbie with a small but real share beside three veterans still earns each of them
    #     the bonus; an idle high-income member beside a fighting newbie earns nothing; a mentor
    #     waiting in the lobby camp earns nothing; a boss nobody hit pays nobody.
    floor = coop["mentorMinDamageShare"]
    idle, shy, mixed, idle_host, waiting, nobody = (
        pays[name] for name in ("idle", "shy", "mixed", "idleHost", "waiting", "nobody"))
    newbie = mentor_fixtures(combat_cfg)["mixed"][1]
    newbie_share = newbie[4] / sum(newbie.values())
    ok13 = (idle == {} and shy == {} and mixed == {1: valor, 2: valor, 3: valor} and idle_host == {}
            and waiting == {} and nobody == {} and newbie_share >= floor and floor > 0)
    checks.verdict(ok13, "13 mentee floor    ",
                   f"idle mentee (0%) -> {idle}; a mentee at half the floor -> {shy}; a {newbie_share:.0%} newbie "
                   f"beside three veterans -> {mixed}; an idle mentor beside a fighting mentee -> {idle_host}; a "
                   f"waiting mentor -> {waiting}; nobody hit -> {nobody} (mentorMinDamageShare {floor:.0%})")

    # 20. The level gates: every kind a level fields (summons included) is priced; every
    #     difficulty and minDifficulty is one of Expeditions.json's, all three present, with
    #     rewardMult 1, 2 and 4 (§12.8); stages are travel and camp in turn and end in a camp; every
    #     camp stage names a camp of the layout; runCapSeconds is at least twice targetMinutes;
    #     every map node with a level names a level file and every from / requires.node a node;
    #     levels.gateSeconds is at least 1.
    problems = []
    notes = []
    levels = {}
    for file in level_files:
        level = sr.resolve_level(file, combat_cfg["director"]["runCapSeconds"])
        try:
            layout = sr.load_level_layout(file["layout"])
        except FileNotFoundError:
            layout = None
            problems.append(f"{file['id']}: no layout {file['layout']}")
        levels[file["id"]] = (file, level, layout)
        found = level_gates(file, level, layout, expeditions, sr.load_config(sr.CONFIG_PATH), combat_cfg)
        if level is not None and layout is not None:
            # The fix round's ruling 6 (zero and empty), and the numbers a run reads of Combat.json.
            found += sr.level_problems(level, layout, combat_cfg["levels"])
        problems += [f"{file['id']}: {text}" for text in found]
        if level is not None:
            notes.append(f"{file['id']} {len(level['stages'])} stage(s), "
                         f"{'/'.join(level['difficulties'])}, cap {level['runCapSeconds']} s")
    node_ids = [node["id"] for node in expeditions["nodes"]]
    for node in expeditions["nodes"]:
        if node.get("level") and node["level"] not in levels:
            problems.append(f"map node {node['id']} names the level {node['level']}, which has no file")
        for other in (node.get("from"), (node.get("requires") or {}).get("node")):
            if other is not None and other not in node_ids:
                problems.append(f"map node {node['id']} names the node {other}, which is not on the map")
    if combat_cfg["levels"]["gateSeconds"] < 1:
        problems.append(f"levels.gateSeconds {combat_cfg['levels']['gateSeconds']} is under 1")
    checks.verdict(not problems, "20 level gates     ", "; ".join(problems[:6]) if problems else "; ".join(notes)
                   + f"; {len(node_ids)} map nodes; gateSeconds {combat_cfg['levels']['gateSeconds']:g}")

    # 21. What each difficulty of a level pays (L1b Wave 1, amended). Gated: the Valor is
    #     exactly the boss's x rewardMult on every difficulty (Normal 10); targetMinutes lies
    #     within CROWD_TARGET_MINUTES_SLACK of the mean measured clear on Normal; every cleared run
    #     of the reacting player was paid, kill by kill, exactly what the level file pays for its
    #     kills (every resident, the boss room's bodies, the boss, the fodder that run's boss
    #     called: L1b-15, no checkpoint pays); stalling never beats playing (what a boss's calls
    #     pay per second is under LEVEL_STALL_SHARE of what the clear pays per second).
    #     Reported, not gated (the contract's "Balance bands"): Normal's pay against L1's
    #     LEVEL_PAY_TARGETS, and Hard's and Brutal's pay as times Normal's.
    details = []
    ok21 = True
    for level_id, target in LEVEL_PAY_TARGETS.items():
        report = level_reports[level_id]
        if report is None:
            ok21 = False
            details.append(f"{level_id} has no level file")
            continue
        level = report["level"]
        summons = forest_summons(proving_cfg, report)
        full = {d: level_pay(level, d, ranks, combat_cfg, summons[d]) for d in report["difficulties"]}
        pays = {d: entry[0] for d, entry in full.items()}
        normal = pays["normal"]
        good = normal["valor"] == target["valor"]
        parts = [f"{level_id} Normal {normal['cash']:,.0f} cash ({100 * (normal['cash'] / target['cash'] - 1):+.1f}% of "
                 f"the draft's {target['cash']:,}, reported), {normal['materials']:.0f} {level['material']} "
                 f"({100 * (normal['materials'] / target['materials'] - 1):+.1f}% of the draft's {target['materials']}, "
                 f"reported), {normal['valor']} Valor (needs {target['valor']})"]
        # The clear bonus is a small part of a Normal clear (L1b-W2-21's band).
        bonus_cash = sum(c for c, _m in full["normal"][3].values())
        lo_b, hi_b = LEVEL_BONUS_SHARE
        bonus_share = bonus_cash / normal["cash"] if normal["cash"] else 0
        good = good and lo_b <= bonus_share <= hi_b
        parts.append(f"the camp bonuses pay {bonus_cash:,} cash = {bonus_share:.1%} of a Normal clear "
                     f"({lo_b:.0%}-{hi_b:.0%})")
        for difficulty, (lo, hi) in LEVEL_PAY_TIMES.items():
            pay = pays.get(difficulty)
            if pay is None:
                good = False
                parts.append(f"{difficulty} missing")
                continue
            cash_times = pay["cash"] / normal["cash"]
            mat_times = pay["materials"] / normal["materials"]
            valor = normal["valor"] * LEVEL_REWARD_MULT[difficulty]
            good = good and pay["valor"] == valor and lo <= cash_times <= hi and lo <= mat_times <= hi
            parts.append(f"{difficulty} {pay['cash']:,.0f} cash (x{cash_times:.2f}), {pay['materials']:.0f} "
                         f"{level['material']} (x{mat_times:.2f}; band x{lo:g}-x{hi:g}), {pay['valor']} "
                         f"Valor (needs {valor})")
        runs = report["difficulties"]["normal"]["runs"]
        clears = [r["at"] for r in runs if r["end"] == "cleared"]
        mean = sum(clears) / len(clears) / 60 if clears else math.inf
        honest = abs(level["targetMinutes"] - mean) <= CROWD_TARGET_MINUTES_SLACK
        good = good and honest
        parts.append(f"targetMinutes {level['targetMinutes']} against a mean clear of {mean:.1f} min")
        # What the measured runs were paid, against the level file: the configured kills of the
        # difficulty and the fodder that very run's boss called, priced by level_pay.
        boss_kind = sr.FOREST_BOSS
        called = next((a.get("summon") for a in proving_cfg["crowd"]["kinds"][boss_kind]["attacks"]
                       if a["shape"] == "summon"), None)
        cleared = 0
        unpaid = []
        for difficulty, row in report["difficulties"].items():
            for r in row["runs"]:
                if r["end"] != "cleared":
                    continue
                cleared += 1
                written = level_pay(level, difficulty, ranks, combat_cfg, {}, r["fielded"], r.get("refusedTent"))[2]
                extra = r["killed"].get(called, 0) - written.get(called, 0) if called else 0
                owed, _rows, kills, bonuses = level_pay(level, difficulty, ranks, combat_cfg,
                                                        {boss_kind: {called: extra}}, r["fielded"], r.get("refusedTent"))
                if r["wallet"] != owed or r["killed"] != kills:
                    unpaid.append(f"{difficulty}: paid {r['wallet']['cash']:,}/{r['wallet']['materials']}/"
                                  f"{r['wallet']['valor']}, the file pays {owed['cash']:,}/{owed['materials']}/"
                                  f"{owed['valor']} for its kills")
                # Each camp's bonus as the run paid it equals Combat.ClearBonus on what it fielded by hand.
                if {k: tuple(v) for k, v in r["bonuses"].items() if tuple(v) != (0, 0)} != bonuses:
                    unpaid.append(f"{difficulty}: the run's bonuses {r['bonuses']} are not ClearBonus by hand {bonuses}")
        good = good and cleared > 0 and not unpaid
        parts.append(f"{cleared} cleared runs each paid exactly what the file pays for its kills" if not unpaid
                     else "paid is not what the file pays: " + "; ".join(unpaid[:3]))
        # A stalled clear: standing in front of a boss for what it calls.
        calls = next((a for a in proving_cfg["crowd"]["kinds"][boss_kind]["attacks"] if a["shape"] == "summon"), None)
        for difficulty in report["difficulties"]:
            row = report["difficulties"].get(difficulty)
            if row is None or calls is None:
                continue
            spec = {"rewardMult": row["scales"]["rewardMult"]}
            stall = kill_reward(level["crowd"]["rewards"], called, spec["rewardMult"])[0] * calls["count"] / calls["cooldown"]
            rate = pays[difficulty]["cash"] / (sum(r["at"] for r in row["runs"]) / len(row["runs"]))
            good = good and stall <= LEVEL_STALL_SHARE * rate
            parts.append(f"{difficulty}: the boss's calls pay {stall:,.0f} cash/s against the clear's {rate:,.0f} "
                         f"(at most {LEVEL_STALL_SHARE:.0%} of it)")
        ok21 = ok21 and good
        details.append("; ".join(parts))
    checks.verdict(ok21, "21 level pay       ", " | ".join(details))

    # 22. L1b-15: Combat.SplitCarry over a seeded fuzz never pays any member more than the sum of
    #     its exact shares (pool x share x cash multiplier), never a whole unit less, and every
    #     carry stays in [0, 1). The contract's cases by hand: solo equals each pool exactly; two
    #     members at 0.9 and 0.1 over ten 1-Timber kills are paid 9 and 1; a cash multiplier of
    #     1.5; a member absent from the shares keeps their carry; a bad share pays nothing.
    #     L4 W3: the fuzz's cash multipliers reach era scale, every CombatCashMult the first two laps meet
    #     (each era's LegacyMult x its eraCashMult; lap 2's Orbital Colony x16.19 x 1,400,000, about
    #     x2.3e7), beside the small ones. At those sizes a double's last place is worth more than 1e-6,
    #     so the exact sum is math.fsum of the same products and the allowance adds one unit in the
    #     last place of each credit's (product + carry), the most its rounding can move a whole unit.
    problems = []
    lap_two = greedy_curves(game, eras, curves[-1].legacy_in + curves[-1].legacy_gained, 1) if curves else []
    era_scale = sorted({combat_cash_mult(era_state(curve), game, shop, rewards, curve.index)
                        for curve in curves + lap_two})
    choices = (1, 1, 1.5, 2, 1.25) + tuple(era_scale)
    rng = __import__("random").Random(CARRY_FUZZ_SEED)
    for _run in range(CARRY_FUZZ_RUNS):
        members = list(range(1, rng.randint(1, 4) + 1))
        mults = {u: rng.choice(choices) for u in members}
        carry = {}
        paid = {u: {"cash": 0, "materials": 0, "valor": 0} for u in members}
        terms = {u: {"cash": [], "materials": [], "valor": []} for u in members}
        for _kill in range(CARRY_FUZZ_KILLS):
            pool = {"cash": rng.choice((0, 100, 500, 700, 1200, 2000, 29000)) * rng.choice((1, 2, 4)),
                    "materials": rng.choice((0, 1, 2, 4, 6, 70)), "valor": rng.choice((0, 0, 0, 10, 40))}
            weights = {u: rng.random() for u in members if rng.random() < 0.8}
            total = sum(weights.values())
            shares = {u: w / total for u, w in weights.items()} if total > 0 else {}
            for u, money in split_carry(pool, shares, carry, mults).items():
                for key in paid[u]:
                    paid[u][key] += money[key]
                    terms[u][key].append(pool[key] * shares[u] * (mults[u] if key == "cash" else 1))
            for u, held in carry.items():
                for key, value in held.items():
                    if not 0 <= value < 1:
                        problems.append(f"carry {key} {value} of member {u} is not in [0, 1)")
        for u in members:
            for key in paid[u]:
                exact = math.fsum(terms[u][key])
                slack = 1e-6 + sum(math.ulp(term + 1) for term in terms[u][key])
                if paid[u][key] > exact + slack or paid[u][key] < exact - 1 - slack:
                    problems.append(f"member {u} (x{mults[u]:,.2f}) was paid {paid[u][key]:,} {key} against an "
                                    f"exact {exact:,.4f}")
    carry = {}
    solo = [split_carry({"cash": c, "materials": m, "valor": v}, {7: 1.0}, carry)[7]
            for c, m, v in ((100, 0, 0), (2000, 6, 0), (29000, 70, 10))]
    if solo != [{"cash": 100, "materials": 0, "valor": 0}, {"cash": 2000, "materials": 6, "valor": 0},
                {"cash": 29000, "materials": 70, "valor": 10}] or any(v != 0 for v in carry[7].values()):
        problems.append(f"solo is not each pool exactly: {solo}, carry {carry}")
    carry = {}
    duo = {1: 0, 2: 0}
    for _kill in range(10):
        for u, money in split_carry({"cash": 0, "materials": 1, "valor": 0}, {1: 0.9, 2: 0.1}, carry).items():
            duo[u] += money["materials"]
    if duo != {1: 9, 2: 1}:
        problems.append(f"0.9 / 0.1 over ten 1-Timber kills paid {duo}, not 9 and 1")
    carry = {}
    if split_carry({"cash": 101, "materials": 0, "valor": 0}, {1: 1.0}, carry, {1: 1.5})[1]["cash"] != 151 \
            or abs(carry[1]["cash"] - 0.5) > 1e-9:
        problems.append("a cash multiplier of 1.5 on 101 does not pay 151 and carry 0.5")
    carry = {3: {"cash": 0.75, "materials": 0.5, "valor": 0.25}}
    split_carry({"cash": 100, "materials": 1, "valor": 0}, {1: 1.0}, carry)
    if carry[3] != {"cash": 0.75, "materials": 0.5, "valor": 0.25}:
        problems.append("a member absent from the shares lost their carry")
    carry = {4: {"cash": 0.5, "materials": 0, "valor": 0}}
    bad = split_carry({"cash": 100, "materials": 1, "valor": 0}, {4: float("nan"), 5: -1, 6: math.inf}, carry)
    if bad or carry[4] != {"cash": 0.5, "materials": 0, "valor": 0} or len(carry) != 1:
        problems.append(f"a bad share paid {bad} or touched a carry: {carry}")
    checks.verdict(not problems, "22 split carry     ", "; ".join(problems[:4]) if problems else
                   f"{CARRY_FUZZ_RUNS} fuzzed runs of {CARRY_FUZZ_KILLS} kills (1-4 members, cash x1-x2 and at era scale "
                   f"x{era_scale[0]:,.2f} .. x{era_scale[-1]:,.0f}): never over the exact shares, never a unit under, "
                   f"every carry in [0, 1); solo exact, 0.9/0.1 pays 9 and 1, x1.5, an absent member's carry kept, a bad "
                   f"share pays nothing")

    # 23. L1b-W2-5: the population of every difficulty of every level with residents, worked by
    #     hand from the files (residents and every tent's stock by minDifficulty, never countMult;
    #     the most room a boss room's maxAlive leaves over its own residents; the boss reserve,
    #     1 + the largest summon count of a camp stage's boss kind in ProvingGrounds.json), equals
    #     StageFlow.Plan's (sim_range.plan_level, held to the Luau by tools/check_stage_mirror.py)
    #     and is at most ProvingGrounds.json crowd.maxAlive.
    problems = []
    notes = []
    proving_kinds = sr.load_config(sr.CONFIG_PATH)["crowd"]["kinds"]
    crowd_max = sr.load_config(sr.CONFIG_PATH)["crowd"]["maxAlive"]
    for level_id, (file, level, layout) in levels.items():
        if level is None or layout is None or not level.get("camps"):
            continue
        locking = {stage.get("zone") for stage in level["stages"] if stage["kind"] == "camp"}
        open_tents = {camp["id"] for camp in layout["camps"] if camp.get("tent") and camp["id"] not in locking}
        reserve = 0
        for stage in level["stages"]:
            for wave in stage.get("waves") or [] if stage["kind"] == "camp" else []:
                if wave.get("boss"):
                    kind = proving_kinds.get(wave["boss"]["kind"]) or {}
                    calls = max([0] + [a["count"] for a in kind.get("attacks") or [] if a["shape"] == "summon"])
                    reserve = max(reserve, 1 + calls)
        row = []
        for difficulty in level["difficulties"]:
            rank = ranks[difficulty]
            by_camp = {}
            tents = 0
            for config in level["camps"]:
                units = [u for group in config["residents"] for u in group["units"]]
                stock = (config.get("tent") or {}).get("units") or [] if config["id"] in open_tents else []
                for unit in units:
                    needs = unit.get("minDifficulty")
                    if needs is None or ranks[needs] <= rank:
                        by_camp[config["id"]] = by_camp.get(config["id"], 0) + unit["count"]
                for unit in stock:
                    needs = unit.get("minDifficulty")
                    if needs is None or ranks[needs] <= rank:
                        tents += unit["count"]
            room = 0
            for stage in level["stages"]:
                if stage["kind"] == "camp":
                    cap = stage["maxAlive"] if stage.get("maxAlive") is not None else level["crowd"]["maxAlive"]
                    room = max(room, cap - by_camp.get(stage["zone"], 0))
            by_hand = sum(by_camp.values()) + tents + room + reserve
            plan = sr.plan_level(level, layout, difficulty, combat_cfg["levels"], ranks, proving_kinds)
            if plan is None or plan["population"] != by_hand:
                problems.append(f"{level_id} {difficulty}: by hand {by_hand}, Plan "
                                f"{plan['population'] if plan else 'refused'}")
            if by_hand > crowd_max:
                problems.append(f"{level_id} {difficulty}: {by_hand} is over crowd.maxAlive {crowd_max}")
            row.append(f"{difficulty} {by_hand} (" + ", ".join(f"{k} {v}" for k, v in by_camp.items())
                       + f"; tents {tents}; room {room}; boss reserve {reserve})")
        notes.append(f"{level_id}: " + "; ".join(row))
    checks.verdict(not problems and bool(notes), "23 population      ",
                   "; ".join(problems[:4]) if problems else " | ".join(notes) + f" (crowd.maxAlive {crowd_max})")

    # 24. L4 W3 (the cash study's constraint 2, MISSIONS_DESIGN 30): back-to-back runs on Normal or Hard
    #     never finish an era sooner than building. Forest Road run back to back on each of
    #     NEVER_FASTER_DIFFICULTIES, from each era's first second, never finishes the era before the
    #     greedy city. The runner buys only between runs (sim_economy.simulate_era's pause hook,
    #     run_pause: the city earns on during a run, offline.expeditionEfficiency 1.0) and each clear
    #     pays its cash x Combat.CombatCashMult at the era's entry (forest_clears' measured mean clear
    #     long). Brutal is left out until T5 exists (contract risk 3).
    #     It gates that one course, not every way of running: the fix round's F17 prints, ungated, the
    #     best "k runs right after the Advance, then build every second" (run_pause's stop_after, min
    #     over k), which can finish sooner at any eraCashMult entry of at least 1 (at the shipped ones it
    #     does on Hard in every era), because the wallet is empty after an Advance: a run then costs
    #     almost no purchases while the city earns on.
    problems = []
    notes = []
    then_build = []
    efficiency = combat_cfg["offline"]["expeditionEfficiency"]
    if efficiency != 1:
        problems.append(f"offline.expeditionEfficiency is {efficiency:g}: run_pause models a city earning at 1.0")
    for curve in curves if report is not None else []:
        mult = combat_cash_mult(era_state(curve), game, shop, rewards, curve.index)
        row = []
        then = []
        for difficulty in NEVER_FASTER_DIFFICULTIES:
            cash, seconds = forest_pay.get(difficulty, (None, None))
            if seconds is None:
                problems.append(f"no cleared {difficulty} run of Forest Road to time")
                continue
            pause, trip = run_pause(seconds, cash * mult)
            lap = se.simulate_era(curve.era, game, curve.legacy_in, "greedy", pause=pause)
            if lap.seconds < curve.seconds:
                problems.append(f"{curve.era['name']}: {difficulty} back to back finishes in {se.fmt_time(lap.seconds)}, "
                                f"before the city's {se.fmt_time(curve.seconds)}")
            row.append(f"{difficulty} {100 * (lap.seconds - curve.seconds) / curve.seconds:+.1f}% "
                       f"({trip['runs']} runs of {seconds} s)")
            best = None
            for k in range(1, trip["runs"] + 1):
                stop, _trip = run_pause(seconds, cash * mult, stop_after=k)
                done = se.simulate_era(curve.era, game, curve.legacy_in, "greedy", pause=stop).seconds
                if best is None or done < best[0]:
                    best = (done, k)
            if best is not None:
                then.append(f"{difficulty} {se.fmt_time(best[0])} {100 * (best[0] - curve.seconds) / curve.seconds:+.1f}% "
                            f"(k = {best[1]})")
        notes.append(f"{curve.era['name']} x{mult:,.2f}: " + ", ".join(row))
        then_build.append(f"{curve.era['name']} x{mult:,.2f} (city {se.fmt_time(curve.seconds)}): " + ", ".join(then))
    checks.verdict(not problems and bool(notes), "24 back to back    ",
                   "; ".join(problems[:4]) if problems else
                   "back-to-back runs on Normal or Hard never finish an era sooner than building: " + "; ".join(notes)
                   + " against the greedy city (needs >= +0.0%; Brutal waits for T5)")
    if then_build:
        print("  note  24 runs, then build: ungated, and negative is sooner than the city: k runs right after the "
              "Advance, then building every second, the best k. The wallet is empty after an Advance, so those runs "
              "cost almost no purchases while the city earns on; any eraCashMult entry of at least 1 keeps that "
              "(Village does it at x1, today's pay). Only the back-to-back course above is gated.")
    for line in then_build:
        print(f"  note  24 runs, then build: {line}")

    # 25. L4 W3, "a few minutes at the start": rewards.eraCashMult holds one finite number of at least 1
    #     per era of Config/Eras, Village's exactly 1 (a new save keeps today's pay); with no rewards block
    #     every era pays x1 (degrade, never an error); and the first clear after each Advance (Village's
    #     is a new save's first) is worth FIRST_CLEAR_MINUTES of that era's income at the second it lands.
    problems = []
    notes = []
    listed = rewards.get("eraCashMult") if isinstance(rewards, dict) else None
    if not isinstance(listed, list) or len(listed) != len(eras):
        problems.append(f"rewards.eraCashMult is {listed!r}, not one number per era ({len(eras)})")
    else:
        bad = [f"{era['name']} {entry!r}" for era, entry in zip(eras, listed) if not _finite(entry) or entry < 1]
        if bad:
            problems.append("an entry that is not a finite number of at least 1: " + ", ".join(bad))
        if not (_finite(listed[0]) and listed[0] == 1):
            problems.append(f"Village's entry is {listed[0]!r}, not exactly 1")
    absent = [era_cash_mult(None, curve.index) for curve in curves] + [era_cash_mult({}, curve.index) for curve in curves]
    if any(value != 1 for value in absent):
        problems.append(f"with no rewards block the eras pay {absent}, not x1")
    lo, hi = FIRST_CLEAR_MINUTES
    for curve in curves if first_second is not None else []:
        clear = normal_cash * combat_cash_mult(era_state(curve), game, shop, rewards, curve.index)
        minutes = clear / (60 * curve.ips[first_second]) if curve.ips[first_second] > 0 else math.inf
        if not lo <= minutes <= hi:
            problems.append(f"{curve.era['name']}'s first clear is {minutes:.2f} minutes of its income")
        notes.append(f"{curve.era['name']} {se.fmt_cash(clear)} = {minutes:.1f} min of {se.fmt_cash(curve.ips[first_second])}/s")
    if first_second is None:
        problems.append("no cleared Normal run to time the first clear")
    checks.verdict(not problems, "25 a few minutes   ",
                   "; ".join(problems[:4]) if problems else
                   f"rewards.eraCashMult {listed} (Village 1; none -> x1); the first clear at "
                   f"{se.fmt_time(first_second)} into each era: " + ", ".join(notes) + f" (needs {lo:g}-{hi:g} min)")

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
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="run the thirteen assertions")
    args = parser.parse_args()

    armory = load_armory_config()
    combat_cfg = load_combat_config()
    places = load_places_config()
    game = se.load_game_config()
    eras = se.load_eras()
    shop = se.load_legacy_shop_config()

    if armory is None or combat_cfg is None:
        print("Armory.json / Combat.json missing -- Expeditions are disabled, nothing to balance.")
        sys.exit(0)

    if args.check:
        sys.exit(1 if run_checks(armory, combat_cfg, places, game, eras, shop) else 0)

    print("Era City Tycoon combat sim -- the Armory ladder, the levels' pay and the shared helpers")
    print("greedy income curve from sim_economy (default playthrough, legacy carried)")
    print()
    curves = greedy_curves(game, eras)
    print_ladder(armory, curves)
    import sim_range as sr

    for file in sr.load_level_files():
        print_level(file["id"], combat_cfg)
    print_helpers(armory, combat_cfg, game, shop)
    sys.exit(0)


if __name__ == "__main__":
    main()
