#!/usr/bin/env python
"""Armory-and-expedition simulator for Era City Tycoon (C0 + C1 + C2 + C2.5).

C2.5 ("one evolving horde"): the melee ring is `Combat.json ai.maxMeleeAttackers`,
chargers and boss `patterns` are modelled coarsely (see CHARGE_LAND_RATE), every
mission in Config/Missions is simulated and asserted, and fixtures past tier
12/12 add Ascension (`loadout_for_power`).

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
  * L3 W1 (docs/prompts/l3-w1-contract.md): the ladder of 20 every weapon family climbs (each
    tier's multiplier, health, band, price and trophy, every family's window), and how many Forest
    Road runs and minutes take both starters from T1 to T4 (assertions 1 and 2). Since L3 the
    city's income gates no tier (Ben, 2026-10-20): the C0 unlock table and assertions "1 unlock
    ladder" and "2 power at median" are retired, and the C1 run model below keeps the slot tiers'
    own health and power (c1_max_hp, c1_gear_power: the scale Missions/*.json was written on);
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

P5 ("back into the missions", docs/INTERFACES.md "P5 contracts"): a mission with a `crowd`
block plays the range's crowd, not the C1 Humanoid waves. This file mirrors the pure
`Combat.CrowdWave`, `Combat.CrowdReward`, `Combat.BurstInterval` and `Armory.DamageScale`, and
asserts the crowd block (15-18): its gates, what a whole run pays, the reacting player's clear
and the CrowdWave mirror. The fights themselves (both bosses at the mission's scales and the
whole run, wave by wave) are measured by `tools/sim_range.py`, which this file imports for them.
The legacy run assertions (3, 7, 8, 10, 11, 14) skip a crowd mission.

L1 ("Forest Road in grey", docs/INTERFACES.md "L1 contracts"): a mission is a level, and the
Village arena is the level "Raider Arena" behind two adapters. This file mirrors the pure
`Combat.CampWave`, `Combat.CampReward` and `Combat.BurstSeconds` (CrowdWave, CrowdReward and
BurstInterval are now their callers, as in the Luau) and asserts: the adapter gives the
mission's own waves (19), the level gates (20) and what each difficulty of a level pays (21).
The mirrors themselves are held to the real Luau by `tools/check_stage_mirror.py`: 19 is
worked here from the mission file by hand, so it fails when either Python function moves.

Usage:
  py tools/sim_combat.py                  # the ladder + Village run report
  py tools/sim_combat.py --check          # the twenty-three C0-L1b assertions; exit 1 on any
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
# Assertion 7 is only asserted for these missions (C2.5). The C1 director reads
# tempo from the stream it throttles, so tempo parks at a fixed point and a 2x
# player only escapes it through a kill BURST (an AoE clearing a backlog behind
# a boss). Village's 2x loadout carries groundSlam and merges five times; the
# draft missions' 2x loadouts (dashStrike, bladeStorm at the ladder's end)
# merge only in settings where the recommended player dies. The others are
# printed, not asserted, until the director measures lag (BALANCE.md "C2.5").
MERGE_ASSERTED_MISSIONS = {"village"}
# Assertion 14, the C2.5 mission shape ("one evolving horde").
HORDE_KINDS = {"melee", "ranged", "charger"}
RUN_MATERIALS_BAND = (250, 350)
# P5 crowd missions (docs/INTERFACES.md "P5 contracts" -> "Balance bands"). A whole run at the
# recommended power (gear 2/1), solo, no Overdrive, pays what the C1 run of the same mission paid
# (docs/BALANCE.md "C0"/"C1": 142,185 cash and 256 Timber at power 57), within the tolerance, and
# exactly the Valor; a reacting player clears it inside CROWD_CLEAR_SECONDS, breathers included.
# targetMinutes is what the hub's Expedition panel promises, so it must sit inside that band and
# near the modelled clear.
CROWD_RUN_TARGETS = {"village": {"cash": 142185, "materials": 256, "valor": 35}}
CROWD_REWARD_TOLERANCE = 0.10
CROWD_CLEAR_SECONDS = (600.0, 900.0)
CROWD_TARGET_MINUTES_SLACK = 1.5
# director.runCapSeconds ends a run that never finishes. It must leave a player slower than the
# simulator's this many times the mission's targetMinutes (C1 shipped 1200 s against 8 minutes,
# x2.5), or it cuts off runs that are merely slow.
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
LADDER_HP_FROM_SLOTS = 11
LADDER_MAX_HP = {1: 155, 3: 230, 5: 380}
LADDER_RANGE_HP = 130
LADDER_POWER_T1 = 64  # today's 2/2 value, so the hub's Village tile (60) still reads ready
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
# The legacy run model's assertions (3, 7, 8, 10, 11, 14) judge the C1 Humanoid waves. A mission
# with a `crowd` block no longer plays them (P5 ruling 27 and the Wave 1 boot), and its
# targetWaveSeconds is re-tuned for crowds, so they skip it; 15-18 judge its crowd instead.
# Run-simulator resolution and the spatial facts it needs. The arena is 110 x 110
# with eight rim spawns (every Layouts/Arenas/*.luau), so a spawn is ~45 studs
# from a player fighting near the middle. Neither is a game constant -- the
# server uses real positions -- but the run simulator needs them to turn
# "within reach" into a number.
DT = 0.1
SPAWN_DISTANCE = 45.0
DASH_TARGETS = 2
# C2.5: the melee ring is no longer a tool guess. `Combat.json ai.maxMeleeAttackers`
# is the number of slots EnemyService hands out around one target, so the sim
# reads it (per party member) inside simulate_run; the rest hold at holdRadius
# and do not swing.
#
# C2.5 chargers and boss patterns, modelled coarsely (docs/BALANCE.md "C2.5"):
#  * a `charger` walks in until it is within `ai.chargeDistance` of reach, winds
#    up `ai.chargeWindupSeconds` standing still, then dashes at speed x
#    `ai.chargeSpeedMult`; the dash lands `damage` x CHARGE_LAND_RATE once and the
#    charger then fights as an ordinary melee enemy (it needs a ring slot to
#    swing). Recharges from the hold ring are NOT modelled.
#  * a boss cycles its `patterns`, each on its own `cooldown` counted from the
#    boss's spawn: `slam` needs the boss within `radius` and hits EVERY party
#    member; `charge` hits one member and pulls the boss into contact; both land
#    `damage x damageMult x PATTERN_LAND_RATE` after `windupSeconds` (the
#    telegraph is the dodge window, so a telegraphed hit lands half the time,
#    like the player's own RANGED_UPTIME). `summon` adds `count` enemies of key
#    `enemy` to the boss's wave after the windup (capped by maxAlive, normal
#    rewards). A boss that dies inside a windup cancels the pending attack.
CHARGE_LAND_RATE = 0.5
PATTERN_LAND_RATE = 0.5
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
    """Armory.HeldTiers -- the held families' tiers in the slot-shaped record."""
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


def gear_power(cfg, tiers, ascension):
    """Armory.GearPower (L3-6) -- round((DamageScale(tm) + DamageScale(tr), attacks) x
    power.tierWeight + MaxHp x power.hpWeight); a tierWeight that is not a number weighs 0."""
    weight = cfg["power"].get("tierWeight")
    weight = weight if _finite(weight) else 0
    damage = damage_scale(cfg, tiers["melee"], ascension["melee"], False) + damage_scale(
        cfg, tiers["ranged"], ascension["ranged"], False)
    return luau_round(damage * weight + max_hp(cfg, tiers, ascension) * cfg["power"]["hpWeight"])


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
    a window 1 <= start <= top <= LadderSize, no window for a family that is not one, the legacy
    list, and a numeric power.tierWeight. Assertion 1 holds the shipped values to L3-1..L3-4 on top."""
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
    if not _finite(cfg["power"].get("tierWeight")):
        problem("power.tierWeight is not a number: Gear Power weighs the tiers at 0")
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
# The C1 Humanoid missions' own power arithmetic. Since L3 the game sizes health and Gear Power
# from the ladder (max_hp, gear_power above); the C1 run model below still measures the retired
# Missions/*.json waves by their slot tiers (Armory.json `slots`, kept for the C1 readers until
# L4), so its numbers stay what C1 balanced. No Luau counterpart: nothing in the game reads these.
# --------------------------------------------------------------------------


def c1_weapon_hp(cfg, slot, tier, asc_level):
    """The pre-L3 Armory.WeaponHp: the slot tier's hp x the Ascension level's hpMult."""
    definition = tier_def(cfg, slot, tier)
    if definition is None:
        return 0
    level = ascension_level_def(cfg, asc_level)
    return definition["hp"] * (level["hpMult"] if level else 1)


def c1_max_hp(cfg, gear, ascension):
    """The pre-L3 Armory.MaxHp: baseHp + c1_weapon_hp(melee) + c1_weapon_hp(ranged)."""
    return (
        cfg["baseHp"]
        + c1_weapon_hp(cfg, "melee", gear["melee"], ascension["melee"])
        + c1_weapon_hp(cfg, "ranged", gear["ranged"], ascension["ranged"])
    )


def c1_gear_power(cfg, gear, ascension):
    """The pre-L3 Armory.GearPower, the scale Missions/*.json recommendedPower was written on:
    round(WeaponDamage melee + WeaponDamage ranged + c1_max_hp x power.hpWeight)."""
    return luau_round(
        weapon_damage(cfg, "melee", gear["melee"], ascension["melee"])
        + weapon_damage(cfg, "ranged", gear["ranged"], ascension["ranged"])
        + c1_max_hp(cfg, gear, ascension) * cfg["power"]["hpWeight"]
    )


def c1_next_tier(cfg, gear, slot):
    """The pre-L3 Armory.NextTier: gear[slot] + 1, None past the slot's last tier."""
    candidate = gear[slot] + 1
    if candidate > len(cfg["slots"][slot]["tiers"]):
        return None
    return candidate


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


# --------------------------------------------------------------------------
# src/shared/Combat.luau mirror -- P5 crowd missions and L1 camps (docs/INTERFACES.md
# "P5 contracts" -> "Server modules", B, and "L1 contracts" -> "B -- the run").
# CampWave, CampReward and BurstSeconds are the rules a run reads; CrowdWave,
# CrowdReward and BurstInterval are their mission-shaped callers, as in the Luau.
# tools/sim_range.py drives a whole level through these, so both tools read one copy.
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


def camp_reward(rewards, kind, spec):
    """Combat.CampReward -- KillReward at the spec's rewardMult."""
    return kill_reward(rewards, kind, spec["rewardMult"])


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


def crowd_wave(mission, wave, party_size, overdrive, combat_cfg):
    """Combat.CrowdWave -- CampWave on a mission's `crowd` block (None when the mission has none
    or no such wave), with no difficulty rank. hpScale and damageScale take Overdrive's hpMult
    and damageMult, counts its countMult, rewards its rewardMult; plateScale and regenShare do
    not change."""
    crowd = mission.get("crowd")
    if crowd is None or not 1 <= wave <= len(crowd["waves"]):
        return None
    od = combat_cfg["overdrive"]
    spec = camp_wave(crowd["waves"][wave - 1], crowd["regenShare"], {
        "hpScale": crowd["hpScale"] * (od["hpMult"] if overdrive else 1),
        "damageScale": crowd["damageScale"] * (od["damageMult"] if overdrive else 1),
        "plateScale": crowd["plateScale"],
        "countMult": od["countMult"] if overdrive else 1,
        "rewardMult": od["rewardMult"] if overdrive else 1,
    }, 0, {}, party_size, combat_cfg)
    spec["wave"] = wave
    return spec


def crowd_reward(mission, kind, spec):
    """Combat.CrowdReward -- CampReward on the mission's rewards; (0, 0) with no crowd block."""
    crowd = mission.get("crowd")
    if crowd is None:
        return 0, 0
    return camp_reward(crowd["rewards"], kind, spec)


def burst_interval(mission, bursts, tempo_value, overdrive, combat_cfg):
    """Combat.BurstInterval -- BurstSeconds, divided by spawnRateMult under Overdrive."""
    seconds = burst_seconds(mission["targetWaveSeconds"], bursts, tempo_value)
    if bursts <= 0 or tempo_value <= 0:
        return seconds
    rate = combat_cfg["overdrive"]["spawnRateMult"] if overdrive else 1
    return seconds / rate


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
            candidate = c1_next_tier(armory, gear, slot)
            if candidate is None:
                continue
            trial = dict(gear)
            trial[slot] = candidate
            if c1_gear_power(armory, trial, NO_ASCENSION) <= target_power:
                gear = trial
                break
        else:
            break
    return gear, c1_gear_power(armory, gear, NO_ASCENSION)


def loadout_for_power(armory, target_power):
    """`gear_for_power`, then Ascension once BOTH slots are at the top tier
    (melee first, one level at a time, while the power stays <= target).
    Returns (gear, ascension, power). Only the top of the ladder needs it: the
    Orbital 2x and every band-3/4 Overdrive fixture ask for more power than
    tier 12/12 carries, and a player that strong has, by definition, rebirthed
    and ascended. Below the top tier this is exactly `gear_for_power`."""
    gear, power = gear_for_power(armory, target_power)
    ascension = dict(NO_ASCENSION)
    top = {slot: len(armory["slots"][slot]["tiers"]) for slot in ("melee", "ranged")}
    if any(gear[slot] < top[slot] for slot in top):
        return gear, ascension, power
    levels = len(armory["ascension"]["levels"])
    while True:
        for slot in ("melee", "ranged"):
            if ascension[slot] >= levels:
                continue
            trial = dict(ascension)
            trial[slot] += 1
            if c1_gear_power(armory, gear, trial) <= target_power:
                ascension = trial
                break
        else:
            break
    return gear, ascension, c1_gear_power(armory, gear, ascension)


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
    coop = combat_cfg["coop"]
    ai = combat_cfg["ai"]
    # The charge window every charger and every boss `charge` pattern uses:
    # target inside [reach, chargeDistance x chargeTriggerFraction] (LOS assumed).
    charge_trigger = ai["chargeDistance"] * ai["chargeTriggerFraction"]
    summon_queue = []
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
    hp_max = sum(c1_max_hp(armory, m["gear"], m["ascension"]) for m in members) / party
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
                "queue_index": 0,
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

    def spawn(group, summoned_key=None):
        nonlocal seq
        if summoned_key is None:
            key, is_boss = group["queue"][group["queue_index"]]
            group["queue_index"] += 1
        else:
            # A boss `summon` goes through the normal spawn path: ordinary stats
            # for the boss wave's spec, normal rewards, counted in the group.
            key, is_boss = summoned_key, False
            group["count"] += 1
        stats = enemy_stats(mission, key, group["spec"], is_boss)
        definition = mission["enemies"][key]
        seq += 1
        patterns = []
        if is_boss:
            group["boss_hp"] = stats["hp"]
            for pattern in (group["spec"]["boss"] or {}).get("patterns") or []:
                patterns.append({"def": pattern, "ready_at": t + pattern["cooldown"]})
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
                # Chargers ("free" / "windup" / "dash" / "strike") live outside
                # the melee ring for their whole life. A boss built from a
                # charger key uses its `charge` PATTERN instead, so it walks in
                # like a melee enemy ("done").
                "charge": "free" if definition["kind"] == "charger" and not is_boss else "done",
                "charge_until": 0.0,
                "next_attack_at": t,
                "recovering": False,
                "struck": True,
                "dash_from": 0.0,
                "dash_run": 0.0,
                "patterns": patterns,
                "cursor": -1,
                "pending": [],
                "boss_dash": False,
                "post_until": 0.0,
                "stunned_until": 0.0,
                "land": (
                    RANGED_ENEMY_LAND_RATE
                    if definition["kind"] == "ranged"
                    else min(definition["speed"] / PLAYER_WALK_SPEED, 1.0)
                ),
            }
        )
        group["spawned"] += 1

    def dash_step(enemy):
        """Advance a dash (charger or boss `charge` pattern) one tick along the
        1-D lane; True on the tick it crosses the target. A dash that started
        at `dash_from` ends `chargeDistance` later, |dash_from - chargeDistance|
        past the target."""
        before = enemy["dash_run"]
        enemy["dash_run"] = min(
            ai["chargeDistance"], before + enemy["speed"] * ai["chargeSpeedMult"] * DT
        )
        enemy["dist"] = abs(enemy["dash_from"] - enemy["dash_run"])
        return before < enemy["dash_from"] <= enemy["dash_run"]

    def charger_step(enemy):
        """One tick of a non-boss charger (EnemyService, C2.5 review), never in
        the melee ring. Ready when t >= next_attack_at; charges when the target
        is in [reach, charge_trigger]; winds up `chargeWindupSeconds`; dashes
        `chargeDistance` (the target is hit once, `damage` x CHARGE_LAND_RATE);
        next_attack_at = dash end + attackCooldown while it circles at
        `holdRadius`; at recovery end, if the target is in reach and it has not
        struck since the last charge, one telegraphed strike, which leaves the
        charge ready at once. Returns the damage landed this tick."""
        state = enemy["charge"]
        if state == "windup":
            if t >= enemy["charge_until"]:
                enemy["charge"] = "dash"
                enemy["dash_from"] = enemy["dist"]
                enemy["dash_run"] = 0.0
            return 0.0
        if state == "dash":
            landed = enemy["damage"] * CHARGE_LAND_RATE if dash_step(enemy) else 0.0
            if enemy["dash_run"] >= ai["chargeDistance"]:
                enemy["charge"] = "free"
                enemy["next_attack_at"] = t + enemy["cooldown"]
                enemy["recovering"] = True
                enemy["struck"] = False
            return landed
        if state == "strike":
            if t < enemy["charge_until"]:
                return 0.0
            enemy["charge"] = "free"
            enemy["next_attack_at"] = t
            return enemy["damage"] * enemy["land"]
        # "free"
        if t < enemy["next_attack_at"]:
            # Recovering: circle at holdRadius.
            step = enemy["speed"] * DT
            gap = ai["holdRadius"] - enemy["dist"]
            enemy["dist"] += max(-step, min(step, gap))
            return 0.0
        if enemy["recovering"]:
            enemy["recovering"] = False
            if enemy["dist"] <= enemy["reach"] and not enemy["struck"]:
                enemy["struck"] = True
                enemy["charge"] = "strike"
                enemy["charge_until"] = t + ai["telegraphSeconds"]
                return 0.0
        if enemy["reach"] <= enemy["dist"] <= charge_trigger:
            enemy["charge"] = "windup"
            enemy["charge_until"] = t + ai["chargeWindupSeconds"]
        elif enemy["dist"] > charge_trigger:
            enemy["dist"] = max(charge_trigger, enemy["dist"] - enemy["speed"] * DT)
        else:
            enemy["dist"] = min(enemy["reach"], enemy["dist"] + enemy["speed"] * DT)
        return 0.0

    def stun(enemy, seconds):
        """A stun freezes the enemy and cancels what it is doing. A boss pattern
        still in its windup is cancelled with `stunPatternRefundFraction` of its
        cooldown refunded; a boss mid-dash just stops (no refund). A charger in
        windup, dash or strike is cancelled: next_attack_at = max(next_attack_at,
        now + attackCooldown x cancelCooldownFraction)."""
        enemy["stunned_until"] = max(enemy["stunned_until"], t + seconds)
        for event in enemy["pending"]:
            pattern = event["pattern"]
            pattern["ready_at"] -= pattern["def"]["cooldown"] * ai["stunPatternRefundFraction"]
        enemy["pending"].clear()
        if enemy["boss_dash"]:
            enemy["boss_dash"] = False
        if enemy["charge"] in ("windup", "dash", "strike"):
            enemy["charge"] = "free"
            enemy["next_attack_at"] = max(
                enemy["next_attack_at"], t + enemy["cooldown"] * ai["cancelCooldownFraction"]
            )
            enemy["recovering"] = True

    def pattern_viable(enemy, definition):
        kind = definition["kind"]
        if kind == "slam":
            radius = definition.get("radius") or ai["defaultSlamRadius"]
            return enemy["dist"] <= radius + ai["slamTriggerMargin"]
        if kind == "charge":
            return enemy["reach"] <= enemy["dist"] <= charge_trigger
        return definition.get("enemy") in mission["enemies"]

    def boss_patterns(enemy):
        """A boss's patterns (WaveService/EnemyService, C2.5 review). One action
        at a time; round-robin from after the last one used, the first ready and
        viable pattern fires and sets ready_at = now + windup + cooldown. On
        landing the plain swing waits `postPatternAttackDelay`. Slam hits members
        within radius + memberRadius; the charge pattern is a real dash (the
        target is hit once as it is crossed); summon queues its bodies for the
        next tick. Returns damage into the pooled `incoming`."""
        landed = 0.0
        if enemy["boss_dash"]:
            if dash_step(enemy):
                landed += enemy["dash_damage"]
            if enemy["dash_run"] >= ai["chargeDistance"]:
                enemy["boss_dash"] = False
            return landed
        for event in list(enemy["pending"]):
            if t < event["at"]:
                continue
            enemy["pending"].remove(event)
            definition = event["pattern"]["def"]
            enemy["post_until"] = t + ai["postPatternAttackDelay"]
            if enemy["next_attack"] is not None:
                enemy["next_attack"] = max(enemy["next_attack"], enemy["post_until"])
            if event["kind"] == "summon":
                queued = len(summon_queue)
                accepted = max(0, min(event["count"], director["maxAlive"] - len(alive) - queued))
                summon_queue.extend([(enemy["group"], definition["enemy"])] * accepted)
            elif event["kind"] == "slam":
                radius = definition.get("radius") or ai["defaultSlamRadius"]
                if enemy["dist"] <= radius + ai["memberRadius"]:
                    landed += event["damage"]
            else:
                enemy["boss_dash"] = True
                enemy["dash_from"] = enemy["dist"]
                enemy["dash_run"] = 0.0
                enemy["dash_damage"] = event["damage"]
        if enemy["pending"] or enemy["boss_dash"]:
            return landed
        count = len(enemy["patterns"])
        for step in range(1, count + 1):
            index = (enemy["cursor"] + step) % count
            pattern = enemy["patterns"][index]
            definition = pattern["def"]
            if t < pattern["ready_at"] or not pattern_viable(enemy, definition):
                continue
            kind = definition["kind"]
            event = {"at": t + definition["windupSeconds"], "kind": kind, "pattern": pattern}
            per_hit = enemy["damage"] * definition.get("damageMult", 1) * PATTERN_LAND_RATE
            if kind == "slam":
                event["damage"] = per_hit * party  # an AoE hits every member
            elif kind == "charge":
                event["damage"] = per_hit
            else:
                event["count"] = definition.get("count") or ai["defaultSummonCount"]
            enemy["pending"].append(event)
            pattern["ready_at"] = t + definition["windupSeconds"] + definition["cooldown"]
            enemy["cursor"] = index
            break
        return landed

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
            # Summons accepted last tick spawn now (counted into their group).
            for group, key in summon_queue:
                spawn(group, key)
            summon_queue.clear()
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
                        stun_seconds = ability["def"].get("stunSeconds", 0)
                        for enemy in ability_targets(ability, list(alive)):
                            ability_damage_total += hit(enemy, {index: damage})
                            # The damage side keeps the C1 "an AoE covers the
                            # fight" assumption, but a stun only lands inside the
                            # radius around the (standing) player: freezing a rig
                            # at the rim would park it outside melee for good.
                            radius = ability["def"].get("radius", 0)
                            if stun_seconds > 0 and enemy["hp"] > 0 and enemy["dist"] <= radius:
                                stun(enemy, stun_seconds)
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
            melee_slots = ai["maxMeleeAttackers"] * party
            melee_used = 0
            # Bosses take a ring slot first, then the oldest arrivals.
            for enemy in sorted(alive, key=lambda e: (not e["boss"], e["seq"])):
                if enemy["hp"] <= 0:
                    continue
                if t < enemy["stunned_until"]:
                    # Frozen: no movement or windup progress; the ring swing
                    # timer is held (a charger's next_attack_at is absolute).
                    if enemy["next_attack"] is not None:
                        enemy["next_attack"] += DT
                    continue
                incoming += boss_patterns(enemy)
                if enemy["boss_dash"]:
                    continue  # the dash owns the boss's position this tick
                if enemy["charge"] != "done":
                    incoming += charger_step(enemy)
                    continue
                if enemy["dist"] > enemy["reach"]:
                    enemy["dist"] = max(enemy["reach"], enemy["dist"] - enemy["speed"] * DT)
                    if enemy["dist"] <= enemy["reach"]:
                        # Every swing is telegraphed ai.telegraphSeconds first
                        # (and waits out postPatternAttackDelay after a pattern).
                        enemy["next_attack"] = max(
                            t + ai["telegraphSeconds"], enemy["post_until"]
                        )
                if enemy["dist"] > enemy["reach"] or enemy["next_attack"] is None:
                    continue
                if enemy["kind"] != "ranged":
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
        "power": c1_gear_power(armory, members[0]["gear"], members[0]["ascension"]),
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


def print_ladder(armory, curves, missions):
    """L3-1..L3-4: the ladder of 20, each tier's band, price and trophy, and every family's window.
    The city's income gates nothing since L3 (Ben, 2026-10-20), so the C0 unlock table is gone."""
    proving = _load(CONFIG_DIR / "ProvingGrounds.json")
    ladder = armory.get("ladder") or {}
    print("Armory ladder (L3) -- one ladder of 20 for every weapon family; the tier belongs to the family")
    print(f"  {'tier':>4} {'x range':>10} {'hp melee':>8} {'hp ranged':>9} {'MaxHp t/t':>9} {'power t/t':>9} "
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
              f"{gear_power(armory, both, NO_ASCENSION):>9,} {band:>4} {entry['levelId']:<11} {material:<9} "
              f"{cost if tier > 1 else '-':>5}  {trophy}")
    print(f"  the range's own body: {range_hp(armory):g} (scale 1 there); Gear Power at T1/T1 "
          f"{gear_power(armory, {'melee': 1, 'ranged': 1}, NO_ASCENSION)} (tierWeight "
          f"{armory['power'].get('tierWeight')}, hpWeight {armory['power']['hpWeight']})")
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


def reference_second(curve):
    """Assertion 4's moment in the greedy era: its middle. Until L3 it was when the city's persisted
    income reached the recommended gear's unlockRate; Ben dropped the income gate (2026-10-20), so a
    run can come at any time, and the middle is the moment C0's fallback already used."""
    return curve.seconds // 2


def print_cash_ratio(mission, armory, curves, totals):
    """Combat cash must stay a garnish on the tycoon, never a shortcut."""
    curve = next((c for c in curves if c.index == mission["era"]), None)
    if curve is None:
        print("Cash vs era cost -- no greedy curve for this era")
        print()
        return None
    second = reference_second(curve)
    remaining = curve.remaining_slot_cost(second)
    mid_remaining = curve.remaining_slot_cost(curve.seconds // 2)
    ratio = totals["cash"] / remaining if remaining > 0 else float("inf")
    print(f"Cash vs era cost -- {curve.era['name']}")
    print(
        f"  reference moment : {se.fmt_time(second)} "
        f"(mid-era: since L3 no weapon tier waits for the city's income, so a run can come at any time)"
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
    top = {"melee": 12, "ranged": 12}  # the starters' top (L3-3): where Ascension would be bought
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


# --------------------------------------------------------------------------
# P5 crowd missions: gates, rewards and the clear (assertions 15-18)
# --------------------------------------------------------------------------


def crowd_mission(mission):
    return mission is not None and mission.get("crowd") is not None


def crowd_fieldable(mission, kinds):
    """Every kind a crowd wave can put on the floor: its groups, its bosses, and whatever any of
    those calls (a ProvingGrounds.json attack of shape `summon`), followed to the end."""
    todo = []
    for wave in mission["crowd"]["waves"]:
        todo += [group["kind"] for group in wave["groups"]]
        if wave.get("boss"):
            todo.append(wave["boss"]["kind"])
    elite = mission["crowd"].get("eliteKind")
    if elite:
        todo.append(elite)
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


def crowd_gates(mission, combat_cfg, proving, arena):
    """The contract's gates on a crowd block; returns the problems found (none = pass)."""
    crowd = mission["crowd"]
    kinds = proving["crowd"]["kinds"]
    waves = crowd["waves"]
    skeleton = combat_cfg.get("crowdSkeleton") or []
    problems = []
    if len(waves) != mission["waves"]:
        problems.append(f"{len(waves)} crowd waves for waves {mission['waves']}")
    if len(skeleton) != len(waves):
        problems.append(f"crowdSkeleton has {len(skeleton)} waves, the crowd {len(waves)}")
    boss_waves = [i for i, wave in enumerate(waves, 1) if wave.get("boss")]
    if boss_waves != mission["bossWaves"]:
        problems.append(f"bossWaves {mission['bossWaves']} but bosses on {boss_waves}")
    introduced = set()
    for i, wave in enumerate(waves, 1):
        beat = skeleton[i - 1] if i <= len(skeleton) else {"introduces": [], "boss": None}
        introduced |= set(beat["introduces"])
        present = {group["kind"] for group in wave["groups"]}
        if present - introduced:
            problems.append(f"w{i} fields {sorted(present - introduced)} before the skeleton introduces them")
        if set(beat["introduces"]) - present:
            problems.append(f"w{i} lacks {sorted(set(beat['introduces']) - present)}, which it introduces")
        boss = wave.get("boss")
        if (boss["kind"] if boss else None) != beat.get("boss"):
            problems.append(f"w{i} boss {boss['kind'] if boss else None}, skeleton {beat.get('boss')}")
        for group in wave["groups"]:
            kind = kinds.get(group["kind"])
            if kind is None or not kind.get("brain") or not kind.get("attacks") or kind.get("boss"):
                problems.append(f"w{i} group {group['kind']} is not a fighting crowd kind")
            if group["count"] <= 0:
                problems.append(f"w{i} group {group['kind']} count {group['count']}")
        if boss:
            kind = kinds.get(boss["kind"])
            if kind is None or not kind.get("boss"):
                problems.append(f"w{i} boss {boss['kind']} is not a boss kind")
            else:
                half_x, half_z = arena["half"]
                x, z = boss["at"]
                if abs(x) > half_x - kind["radius"] or abs(z) > half_z - kind["radius"]:
                    problems.append(f"w{i} boss.at {boss['at']} outside the floor less its radius")
    for name in crowd_fieldable(mission, kinds):
        if name not in crowd["rewards"]:
            problems.append(f"{name} can be fielded but has no rewards entry")
    for name, reward in crowd["rewards"].items():
        if name not in kinds:
            problems.append(f"rewards names {name}, which is no crowd kind")
        if reward["cash"] < 0 or reward["materials"] < 0:
            problems.append(f"{name} rewards are negative")
    elite = crowd.get("eliteKind")
    if elite is not None and (elite not in kinds or kinds[elite].get("boss")):
        problems.append(f"eliteKind {elite} is not an ordinary crowd kind")
    if not 0 < crowd["maxAlive"] <= proving["crowd"]["maxAlive"]:
        problems.append(f"maxAlive {crowd['maxAlive']} not in 1..{proving['crowd']['maxAlive']}")
    if crowd["burst"] < 1 or crowd["burstSpacing"] <= 0:
        problems.append(f"burst {crowd['burst']}, burstSpacing {crowd['burstSpacing']}")
    for key in ("hpScale", "plateScale", "damageScale", "regenShare"):
        if crowd[key] <= 0:
            problems.append(f"{key} {crowd[key]}")
    return problems


def crowd_run_pay(mission, combat_cfg, summon_kills):
    """What a whole solo run pays (Combat.CrowdReward per kill, rewardMult 1): every configured
    body, every boss, and `summon_kills` {kind: kills} of what the bosses call. Per wave too:
    [(wave, cash, materials, valor)], summons booked to their boss's wave."""
    rows = []
    totals = {"cash": 0, "materials": 0, "valor": 0}
    for i in range(1, len(mission["crowd"]["waves"]) + 1):
        spec = crowd_wave(mission, i, 1, False, combat_cfg)
        cash = materials = valor = 0
        for group in spec["groups"]:
            c, m = crowd_reward(mission, group["kind"], spec)
            cash += c * group["count"]
            materials += m * group["count"]
        boss = spec["boss"]
        if boss is not None:
            c, m = crowd_reward(mission, boss["kind"], spec)
            cash += c
            materials += m
            valor += luau_round(boss["valor"] * spec["rewardMult"])
            for kind, kills in (summon_kills.get(boss["kind"]) or {}).items():
                c, m = crowd_reward(mission, kind, spec)
                cash += c * kills
                materials += m * kills
        rows.append((i, cash, materials, valor))
        totals["cash"] += cash
        totals["materials"] += materials
        totals["valor"] += valor
    return totals, rows


def crowd_report(mission):
    """sim_range's mission report: the bosses fought at the mission's scales and the reacting
    player's whole run (sim_range imports this file for the Combat mirrors, so it is imported
    here only when a crowd mission is checked)."""
    import sim_range as sr

    proving = sr.load_config(sr.CONFIG_PATH)
    return proving, sr.mission_report(proving, mission=mission, careless=False)


def crowd_summon_kills(proving, report):
    """{boss kind: {called kind: kills}} from the reacting player's boss fights: what the boss
    called less what was dismissed with it (a dismissed body pays nothing, ruling 14)."""
    found = {}
    for name, row in report["bosses"].items():
        called = [a.get("summon") for a in proving["crowd"]["kinds"][name]["attacks"] if a["shape"] == "summon"]
        if called and called[0]:
            found[name] = {called[0]: row["kills"] - 1}  # the fight's kills less the boss
    return found


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
        return [f"{file['id']} does not resolve (no stages, difficulties or crowd block, or no such mission)"]
    for kind in level_fieldable(level, kinds):
        if kind not in level["crowd"]["rewards"]:
            problems.append(f"{kind} can be fielded but has no rewards entry")
        if kind not in kinds:
            problems.append(f"{kind} is no crowd kind")
    for name in level["difficulties"]:
        if name not in names:
            problems.append(f"difficulty {name} is not in Expeditions.json")
    if not file.get("mission"):
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
                c, m = camp_reward(level["crowd"]["rewards"], kind, spec)
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


def print_crowd(mission, armory, combat_cfg, curves):
    """The crowd run of a mission: what each wave holds and pays, where the summons come from,
    and the reacting player's measured clear (sim_range)."""
    proving, report = crowd_report(mission)
    summons = crowd_summon_kills(proving, report)
    pay, rows = crowd_run_pay(mission, combat_cfg, summons)
    block = mission["crowd"]
    print(f"{mission['name']} ({mission['id']}) -- CROWD run, solo, gear {report['gear']['melee']}/"
          f"{report['gear']['ranged']} (health {report['hp']:.0f}), targetWaveSeconds "
          f"{mission['targetWaveSeconds']}, burst {block['burst']}, maxAlive {block['maxAlive']}")
    print(f"  wave  bodies  bursts  {'holds':<70} {'cash':>9}  {mission['material']:>8}  valor")
    for wave, cash, materials, valor in rows:
        spec = crowd_wave(mission, wave, 1, False, combat_cfg)
        holds = {}
        for group in spec["groups"]:
            holds[group["kind"]] = holds.get(group["kind"], 0) + group["count"]
        text = ", ".join(f"{n} {k}" for k, n in holds.items())
        if spec["boss"] is not None:
            called = summons.get(spec["boss"]["kind"]) or {}
            text = f"the {spec['boss']['kind']}" + "".join(f" (+{n:.0f} {k} called)" for k, n in called.items())
        bodies = spec["total"] + (1 if spec["boss"] else 0)
        print(f"  {wave:>4}  {bodies:>6}  {len(crowd_bursts(spec, block['burst'])):>6}  {text:<70} "
              f"{cash:>9,.0f}  {materials:>8.0f}  {valor:>5}")
    target = CROWD_RUN_TARGETS.get(mission["id"], {})
    print(f"  run   {pay['cash']:,.0f} cash, {pay['materials']:.0f} {mission['material']}, {pay['valor']} Valor"
          + (f"  (targets {target['cash']:,} / {target['materials']} / {target['valor']}, "
             f"+-{CROWD_REWARD_TOLERANCE:.0%})" if target else ""))
    share = {}
    for wave_def in block["waves"]:
        for group in wave_def["groups"]:
            share[group["kind"]] = share.get(group["kind"], 0) + group["count"]
        if wave_def.get("boss"):
            kind = wave_def["boss"]["kind"]
            share[kind] = share.get(kind, 0) + 1
            for called, kills in (summons.get(kind) or {}).items():
                share[called] = share.get(called, 0) + kills
    print("  cash by kind: " + ", ".join(
        f"{kind} {n:.0f} x {block['rewards'][kind]['cash']:,} = "
        f"{100 * n * block['rewards'][kind]['cash'] / pay['cash']:.0f}%" for kind, n in share.items()))
    runs = report["runs"]
    print("  measured clear (sim_range, reacting player, default melee): "
          + ", ".join(f"{r['end']} {se.fmt_time(r['at'])}" for r in runs)
          + f"; targetMinutes {mission['targetMinutes']}")
    for curve in curves:
        if curve.era["name"] == mission["eraName"]:
            second = reference_second(curve)
            remaining = curve.remaining_slot_cost(second)
            print(f"  vs the tycoon: {pay['cash']:,.0f} = {100 * pay['cash'] / remaining:.2f}% of the "
                  f"{remaining:,.0f} the era still costs at {se.fmt_time(second)}")
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
    for slot in ("melee", "ranged"):
        old = [t["hp"] for t in armory["slots"][slot]["tiers"]][1:LADDER_HP_FROM_SLOTS + 1]
        if (hp.get(slot) or [])[:LADDER_HP_FROM_SLOTS] != old:
            found.append(f"ladder.hp.{slot} T1-T{LADDER_HP_FROM_SLOTS} are not the old slot tiers 2-12 ({old})")
    for tier, want_hp in LADDER_MAX_HP.items():
        got = max_hp(armory, {"melee": tier, "ranged": tier}, NO_ASCENSION)
        if got != want_hp:
            found.append(f"MaxHp at T{tier}/T{tier} is {got:g}, not {want_hp}")
    if range_hp(armory) != LADDER_RANGE_HP:
        found.append(f"RangeHp is {range_hp(armory):g}, not {LADDER_RANGE_HP}")
    power = gear_power(armory, {"melee": 1, "ranged": 1}, NO_ASCENSION)
    if power != LADDER_POWER_T1:
        found.append(f"Gear Power at T1/T1 is {power}, not {LADDER_POWER_T1} (power.tierWeight)")
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
    frozen = [{"material": (armory["bands"][t["band"] - 1]["material"]), "amount": t["cost"]}
              for t in armory["slots"]["melee"]["tiers"]]
    ranged = [{"material": (armory["bands"][t["band"] - 1]["material"]), "amount": t["cost"]}
              for t in armory["slots"]["ranged"]["tiers"]]
    if (armory.get("legacy") or {}).get("gearCosts") != frozen or frozen != ranged:
        found.append("legacy.gearCosts is not the slot tiers' prices (both slots)")
    return found


def ladder_note(armory, proving):
    """Assertion 1's line when it holds."""
    refund = legacy_refund(armory, {"melee": 3, "ranged": 3})
    return (f"{ladder_size(armory)} tiers x{multiplier(armory, 1):g} .. x{multiplier(armory, ladder_size(armory)):,.0f}; "
            f"MaxHp T1 {max_hp(armory, {'melee': 1, 'ranged': 1}, NO_ASCENSION):g}, T3 "
            f"{max_hp(armory, {'melee': 3, 'ranged': 3}, NO_ASCENSION):g}, T5 "
            f"{max_hp(armory, {'melee': 5, 'ranged': 5}, NO_ASCENSION):g}, T20 "
            f"{max_hp(armory, {'melee': 20, 'ranged': 20}, NO_ASCENSION):,.0f}; RangeHp {range_hp(armory):g}; power T1/T1 "
            f"{gear_power(armory, {'melee': 1, 'ranged': 1}, NO_ASCENSION)}; Forest T2/T3/T4 "
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


def run_checks(armory, combat_cfg, places, missions, game, eras):
    checks = Checks()
    print("sim_combat --check (docs/INTERFACES.md C0 + C1 + C2 + C2.5 + P5 + L1 + L1b contracts, twenty-three assertions)")
    curves = greedy_curves(game, eras)
    # P5: the crowd missions are measured once, by sim_range (bosses and the whole run).
    crowd = {}
    for mission in missions.values():
        if crowd_mission(mission):
            proving, report = crowd_report(mission)
            summons = crowd_summon_kills(proving, report)
            pay, per_wave = crowd_run_pay(mission, combat_cfg, summons)
            crowd[mission["id"]] = {"proving": proving, "report": report, "summons": summons, "pay": pay,
                                    "perWave": per_wave}
    retired = " (crowd mission: see 15-18)"

    # The level reports, measured once by sim_range (assertions 2 and 21 read them).
    import sim_range as sr

    proving_cfg = sr.load_config(sr.CONFIG_PATH)
    level_reports = {level_id: sr.forest_report(proving_cfg, careless=False, level_id=level_id, human=False,
                                                ranged=False, below=False, scenarios=False)
                     for level_id in LEVEL_PAY_TARGETS}

    # 1. L3-1..L3-4 and L3-29: the ladder as Armory.Problems reads it (nothing for the shipped
    #    families), and the shipped numbers held to the contract: 20 tiers rising 1.5 x 1.65^(t-1),
    #    HP T1-T11 = the old slot tiers 2-12 with melee >= ranged and never falling, MaxHp 155 / 230
    #    / 380 at T1 / T3 / T5, RangeHp 130, Gear Power 64 at T1/T1, five bands of four (the first
    #    Forest Road's Timber), costs by position (T2 / T3 / T4 = 100 / 250 / 500), the Hard star the
    #    trophy, L3-3's windows for every family, and `legacy` equal to the slot prices it freezes.
    #    (Was "1 unlock ladder": the city's income gates no tier since L3, Ben 2026-10-20.)
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

    # 3. Simulated run at recommended power clears every wave inside targetMinutes +-50 %.
    details = []
    ok3 = True
    baselines = {}
    for curve in curves:
        mission = missions.get(curve.index)
        if mission is None:
            continue
        if crowd_mission(mission):
            details.append(mission["id"] + retired)
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
        if crowd_mission(mission):
            totals = crowd[mission["id"]]["pay"]  # the crowd run's cash, summons included
        elif totals is None:
            _, totals = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
        second = reference_second(curve)
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

    # 7. Twice the recommended power makes the director merge at least one wave
    #    (asserted for MERGE_ASSERTED_MISSIONS; the drafts are reported).
    details = []
    ok7 = True
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        if crowd_mission(mission):
            details.append(mission["id"] + retired)
            continue
        gear, ascension, power = loadout_for_power(
            armory, STRONG_POWER_MULT * mission["recommendedPower"]
        )
        _, totals = simulate_run(mission, armory, combat_cfg, gear, ascension, 1, False)
        asserted = mission["id"] in MERGE_ASSERTED_MISSIONS
        if asserted:
            ok7 = ok7 and totals["merges"] >= 1
        details.append(
            f"{mission['id']} power {power} -> {totals['merges']} merge(s), "
            f"{se.fmt_time(totals['seconds'])}" + ("" if asserted else " (draft, reported)")
        )
    checks.verdict(ok7, "7 merge at 2x      ", "; ".join(details) or "no missions to model")

    # 8. Under-geared (0.6x) the run ends in death around wave 6.
    details = []
    ok8 = True
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        if crowd_mission(mission):
            details.append(mission["id"] + retired)
            continue
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
        if crowd_mission(mission):
            details.append(mission["id"] + retired)
            continue
        base = baselines.get(mission["id"])
        if base is None:
            gear, _ = gear_for_power(armory, mission["recommendedPower"])
            _, base = simulate_run(mission, armory, combat_cfg, gear, NO_ASCENSION, 1, False)
        # "recommended" here is Combat.RecommendedPower under Overdrive (the
        # mission's number x overdrive.hpMult), which is the figure the
        # Expedition panel shows for an Overdrive run -- so the fixture is three
        # times THAT, not three times the normal-mode number.
        gear, ascension, power = loadout_for_power(
            armory, OVERDRIVE_POWER_MULT * recommended_power(mission, True, combat_cfg)
        )
        _, totals = simulate_run(mission, armory, combat_cfg, gear, ascension, 1, True)
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
        if crowd_mission(mission):
            details.append(mission["id"] + retired)
            continue
        gear, _ = gear_for_power(armory, mission["recommendedPower"])
        solo = boss_wave_lengths(mission, armory, combat_cfg, gear, 1)
        details.append(
            f"{mission['id']} solo "
            + ", ".join(f"w{w} {s:.1f}s" for w, s in sorted(solo.items()))
        )
        for party in range(2, combat_cfg["coop"]["maxParty"] + 1):
            lengths = boss_wave_lengths(mission, armory, combat_cfg, gear, party)
            parts = []
            for wave, seconds in sorted(solo.items()):
                party_seconds = lengths.get(wave)
                ratio = party_seconds / seconds if party_seconds and seconds > 0 else 0.0
                ok11 = ok11 and abs(ratio - 1) <= BOSS_WAVE_TOLERANCE
                parts.append(f"w{wave} {party_seconds or 0:.1f}s x{ratio:.2f}")
            details.append(f"p{party} " + ", ".join(parts))
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
        # The newbie is the under-geared fixture (assertion 8's 0.6x loadout):
        # Stick + Sling in Village, the previous band's gear in missions 2-4.
        # A starter weapon in an Orbital run deals ~0.1 % -- spectating, which
        # C2 already ruled no floor should pay for.
        newbie, _ = gear_for_power(armory, WEAK_POWER_MULT * mission["recommendedPower"])
        mixed = mentor_run(
            mission,
            armory,
            combat_cfg,
            [(strong, MENTOR_HOST_RATE, False)] * 3 + [(newbie, low_rate, False)],
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
            f"0.6x newbie (tier {newbie['melee']}/{newbie['ranged']}) beside three 2x veterans, "
            f"lowest boss-flush share "
            f"{newbie_share:.1%} -> each veteran paid {mixed_paid}; idle mentor beside a "
            f"fighting 1:10 mentee -> paid {idle_host_paid}"
        )
    checks.verdict(
        ok13,
        "13 mentee floor    ",
        "; ".join(details) + f" (mentorMinDamageShare {floor:.0%})",
    )

    # 14. C2.5 "one evolving horde": every mission has exactly one melee, one
    #     ranged and one charger key (the elite), bosses on [5, 10] built from
    #     the charger key, every summon names a mission key and sits on the LAST
    #     boss wave (a summon's kills feed the tempo window; on an earlier boss
    #     wave they merge the next wave in while the boss lives), and a full run
    #     at recommended power yields RUN_MATERIALS_BAND of the era material.
    problems = []
    notes = []
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        if crowd_mission(mission):
            notes.append(mission["id"] + retired)
            continue
        kinds = sorted(e["kind"] for e in mission["enemies"].values())
        if kinds != sorted(HORDE_KINDS) or set(kinds) - HORDE_KINDS:
            problems.append(f"{mission['id']} kinds {kinds}")
        charger = [k for k, e in mission["enemies"].items() if e["kind"] == "charger"]
        if charger and not mission["enemies"][charger[0]]["elite"]:
            problems.append(f"{mission['id']} charger {charger[0]} is not elite")
        if mission["bossWaves"] != [5, 10] or sorted(mission["bosses"]) != ["10", "5"]:
            problems.append(f"{mission['id']} boss waves {mission['bossWaves']}")
        last = str(max(mission["bossWaves"]))
        for wave, boss in mission["bosses"].items():
            if charger and boss["enemy"] != charger[0]:
                problems.append(f"{mission['id']} w{wave} boss built from {boss['enemy']}")
            patterns = boss.get("patterns") or []
            if not 2 <= len(patterns) <= 3:
                problems.append(f"{mission['id']} w{wave} has {len(patterns)} patterns")
            for pattern in patterns:
                if pattern["kind"] == "summon" and (
                    wave != last or pattern.get("enemy") not in mission["enemies"]
                ):
                    problems.append(f"{mission['id']} w{wave} summon {pattern.get('enemy')}")
        totals = baselines.get(mission["id"])
        if totals is not None:
            low, high = RUN_MATERIALS_BAND
            if not low <= totals["materials"] <= high:
                problems.append(f"{mission['id']} {totals['materials']} {mission['material']}")
            notes.append(f"{mission['id']} {totals['materials']} {mission['material']}")
    checks.verdict(
        not problems,
        "14 horde shape     ",
        "; ".join(problems)
        if problems
        else "grunt/shooter/charger + 2 bosses with 2-3 patterns, summons on the last boss "
        f"only; materials per run {', '.join(notes)} (band {RUN_MATERIALS_BAND})",
    )

    # 15. P5 crowd gates: every wave matches Combat.json crowdSkeleton, #waves and bossWaves
    #     agree with the bosses, every kind a wave can field (summons included) has a rewards
    #     entry, boss.at lies inside the floor less the kind's radius, maxAlive <= the crowd's.
    import sim_range as sr

    problems = []
    notes = []
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        if not crowd_mission(mission):
            notes.append(f"{mission['id']} no crowd block (refused in game until Wave 3)")
            continue
        data = crowd[mission["id"]]
        arena = sr.load_arena(mission["arena"])
        problems += [f"{mission['id']} {p}" for p in crowd_gates(mission, combat_cfg, data["proving"], arena)]
        kinds = crowd_fieldable(mission, data["proving"]["crowd"]["kinds"])
        notes.append(f"{mission['id']} {len(mission['crowd']['waves'])} waves on the skeleton, fields "
                     f"{', '.join(kinds)}")
    checks.verdict(not problems, "15 crowd gates     ", "; ".join(problems) if problems else "; ".join(notes))

    # 16. A whole solo crowd run at recommended power pays the C1 run's cash and materials within
    #     CROWD_REWARD_TOLERANCE, and exactly its Valor (summons at the counts sim_range reports
    #     for the reacting player's boss fights).
    details = []
    ok16 = True
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        if not crowd_mission(mission):
            continue
        data = crowd[mission["id"]]
        pay = data["pay"]
        target = CROWD_RUN_TARGETS.get(mission["id"])
        if target is None:
            ok16 = False
            details.append(f"{mission['id']} has no CROWD_RUN_TARGETS entry")
            continue
        cash_ok = abs(pay["cash"] / target["cash"] - 1) <= CROWD_REWARD_TOLERANCE
        mat_ok = abs(pay["materials"] / target["materials"] - 1) <= CROWD_REWARD_TOLERANCE
        valor_ok = pay["valor"] == target["valor"]
        ok16 = ok16 and cash_ok and mat_ok and valor_ok
        summons = ", ".join(f"{kills:.1f} {kind} from the {boss}" for boss, called in data["summons"].items()
                            for kind, kills in called.items())
        details.append(
            f"{mission['id']} {pay['cash']:,.0f} cash ({100 * (pay['cash'] / target['cash'] - 1):+.1f}% of "
            f"{target['cash']:,}), {pay['materials']:.0f} {mission['material']} "
            f"({100 * (pay['materials'] / target['materials'] - 1):+.1f}% of {target['materials']}), "
            f"{pay['valor']} Valor (needs {target['valor']}); summons {summons}"
        )
    checks.verdict(ok16, "16 crowd rewards   ", "; ".join(details) + f" (tolerance {CROWD_REWARD_TOLERANCE:.0%})")

    # 17. The reacting player (sim_range's whole run, every seed) clears every wave inside
    #     CROWD_CLEAR_SECONDS, breathers included; targetMinutes (the hub panel's promise) lies
    #     in that band and within CROWD_TARGET_MINUTES_SLACK of the mean clear; and the run cap
    #     leaves at least CROWD_RUN_CAP_RATIO times targetMinutes.
    details = []
    ok17 = True
    lo, hi = CROWD_CLEAR_SECONDS
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        if not crowd_mission(mission):
            continue
        runs = crowd[mission["id"]]["report"]["runs"]
        clears = [r["at"] for r in runs if r["end"] == "cleared"]
        every = len(clears) == len(runs) and all(lo <= s <= hi for s in clears)
        mean = sum(clears) / len(clears) if clears else math.inf
        promise = mission["targetMinutes"]
        honest = lo / 60 <= promise <= hi / 60 and abs(promise - mean / 60) <= CROWD_TARGET_MINUTES_SLACK
        cap = combat_cfg["director"]["runCapSeconds"]
        roomy = cap >= CROWD_RUN_CAP_RATIO * promise * 60
        ok17 = ok17 and every and honest and roomy
        details.append(
            f"{mission['id']} " + ", ".join(f"{r['end']} {se.fmt_time(r['at'])}" for r in runs)
            + f" (mean {mean / 60:.1f} min; targetMinutes {promise}; targetWaveSeconds "
            f"{mission['targetWaveSeconds']}; run cap {cap} s = x{cap / (promise * 60):.2f} of the target, "
            f"needs >= x{CROWD_RUN_CAP_RATIO:g})"
        )
    checks.verdict(ok17, "17 crowd clear     ", "; ".join(details) + f" (needs {lo / 60:.0f}-{hi / 60:.0f} min)")

    # 18. The Combat.CrowdWave mirror against the config: solo and no Overdrive is the config as
    #     written; counts never fall with party size; Overdrive raises counts, HP and damage and
    #     leaves plates and regen; the burst queue holds exactly `total` bodies; BurstInterval
    #     spreads the bursts over targetWaveSeconds at tempo 1.
    problems = []
    checked = 0
    for mission in sorted(missions.values(), key=lambda m: m["era"]):
        if not crowd_mission(mission):
            continue
        block = mission["crowd"]
        od = combat_cfg["overdrive"]
        for wave in range(1, len(block["waves"]) + 1):
            solo = crowd_wave(mission, wave, 1, False, combat_cfg)
            written = [(g["kind"], g["count"]) for g in block["waves"][wave - 1]["groups"]]
            if [(g["kind"], g["count"]) for g in solo["groups"]] != written:
                problems.append(f"{mission['id']} w{wave} solo counts differ from the config")
            if solo["bossHpMult"] != 1 or solo["rewardMult"] != 1 or solo["hpScale"] != block["hpScale"]:
                problems.append(f"{mission['id']} w{wave} solo multipliers are not neutral")
            previous = solo["total"]
            for party in range(1, combat_cfg["coop"]["maxParty"] + 1):
                for overdrive in (False, True):
                    spec = crowd_wave(mission, wave, party, overdrive, combat_cfg)
                    checked += 1
                    bursts = crowd_bursts(spec, block["burst"])
                    if sum(n for _k, n in bursts) != spec["total"]:
                        problems.append(f"{mission['id']} w{wave} p{party}: bursts hold the wrong count")
                    if bursts and abs(burst_interval(mission, len(bursts), 1.0, False, combat_cfg) * len(bursts)
                                      - mission["targetWaveSeconds"]) > 1e-9:
                        problems.append(f"{mission['id']} w{wave} p{party}: bursts not spread over the wave")
                    if overdrive:
                        if (spec["hpScale"] != block["hpScale"] * od["hpMult"]
                                or spec["damageScale"] != block["damageScale"] * od["damageMult"]
                                or spec["plateScale"] != block["plateScale"]
                                or spec["regenShare"] != block["regenShare"]):
                            problems.append(f"{mission['id']} w{wave} p{party}: Overdrive scales")
                    elif spec["total"] < previous:
                        problems.append(f"{mission['id']} w{wave} p{party}: fewer bodies than a smaller party")
                    else:
                        previous = spec["total"]
    checks.verdict(
        not problems,
        "18 crowd spec      ",
        "; ".join(problems[:4]) if problems
        else f"{checked} wave/party/overdrive combinations: the config as written solo, counts rise with the "
        f"party, Overdrive scales HP and damage only, bursts hold every body over targetWaveSeconds",
    )

    # 19. L1 ruling 27: the Raider Arena is its mission behind an adapter. For every wave and
    #     party size, Combat.CampWave on the resolved level equals Combat.CrowdWave on the
    #     mission; the level is one camp "arena" that merges and takes the director's breather,
    #     with no residents; its rewards, regen and density are the mission's own. (L1b-15: no
    #     stage banks any more, every kill is paid as it falls; sim_range holds the runs to it.)
    expeditions = sr.load_config(sr.EXPEDITIONS_PATH)
    ranks = sr.difficulty_ranks(expeditions)
    level_files = sr.load_level_files()
    by_mission = {m["id"]: m for m in missions.values()}
    below = combat_cfg["player"]["rescue"]["below"]
    problems = []
    notes = []
    for file in level_files:
        if not file.get("mission"):
            continue
        mission = by_mission.get(file["mission"])
        level = sr.resolve_level(file, mission, combat_cfg["director"]["runCapSeconds"])
        if mission is None or level is None:
            problems.append(f"{file['id']} names the mission {file['mission']}, which has no crowd block")
            continue
        stage = level["stages"][0]
        block = mission["crowd"]
        if (len(level["stages"]) != 1 or stage["kind"] != "camp" or stage["zone"] != "arena" or not stage["merge"]
                or "bankEachWave" in stage or stage["breatherSeconds"] is not None or level.get("camps")
                or stage["targetWaveSeconds"] != mission["targetWaveSeconds"]):
            problems.append(f"{file['id']} is not one merging camp on the director's breather with no residents")
        if (level["crowd"]["rewards"] is not block["rewards"] or level["crowd"]["regenShare"] != block["regenShare"]
                or level["crowd"]["maxAlive"] != block["maxAlive"] or level["crowd"]["burst"] != block["burst"]
                or level["material"] != mission["material"]
                or level["runCapSeconds"] != combat_cfg["director"]["runCapSeconds"]):
            problems.append(f"{file['id']} does not carry the mission's rewards, regen, density, material and cap")
        compared = 0
        coop = combat_cfg["coop"]
        for wave in range(1, len(block["waves"]) + 1):
            written = block["waves"][wave - 1]
            for party in range(1, coop["maxParty"] + 1):
                ours = camp_wave(stage["waves"][wave - 1], level["crowd"]["regenShare"], level["difficulties"]["normal"],
                                 ranks["normal"], ranks, party, combat_cfg)
                ours["wave"] = wave
                compared += 1
                # Worked by hand from the mission file, through neither function: the config's own
                # counts grown by the party (round half away from zero), the boss's HP by the
                # party, the block's three scales and its regen, rewards x1.
                groups = []
                for group in written["groups"]:
                    grow = group["perExtra"] if group.get("perExtra") is not None else coop["countPerExtraPlayer"]
                    groups.append({"kind": group["kind"],
                                   "count": max(math.floor(group["count"] * (1 + grow * (party - 1)) + 0.5), 0)})
                by_hand = {"wave": wave, "groups": groups, "total": sum(g["count"] for g in groups),
                           "boss": written.get("boss"), "bossHpMult": 1 + coop["bossHpPerExtraPlayer"] * (party - 1),
                           "hpScale": block["hpScale"], "plateScale": block["plateScale"],
                           "damageScale": block["damageScale"], "regenShare": block["regenShare"], "rewardMult": 1}
                if ours != by_hand:
                    problems.append(f"{file['id']} wave {wave} party {party}: CampWave on the adapter is not the "
                                    f"mission's wave worked by hand")
                if crowd_wave(mission, wave, party, False, combat_cfg) != by_hand:
                    problems.append(f"{file['id']} wave {wave} party {party}: CrowdWave is not the mission's wave "
                                    f"worked by hand")
        notes.append(f"{file['id']} = {mission['id']}: {compared} wave/party specs, each equal to the mission's wave "
                     f"worked by hand through CampWave on the adapter and through CrowdWave; one camp of "
                     f"{len(stage['waves'])} waves")
    checks.verdict(not problems, "19 arena adapter   ", "; ".join(problems[:4]) if problems else "; ".join(notes))

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
        mission = by_mission.get(file.get("mission")) if file.get("mission") else None
        level = sr.resolve_level(file, mission, combat_cfg["director"]["runCapSeconds"])
        try:
            layout = sr.load_level_layout(file["layout"], below)
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
            stall = camp_reward(level["crowd"]["rewards"], called, spec)[0] * calls["count"] / calls["cooldown"]
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
    problems = []
    rng = __import__("random").Random(CARRY_FUZZ_SEED)
    for _run in range(CARRY_FUZZ_RUNS):
        members = list(range(1, rng.randint(1, 4) + 1))
        mults = {u: rng.choice((1, 1, 1.5, 2, 1.25)) for u in members}
        carry = {}
        paid = {u: {"cash": 0, "materials": 0, "valor": 0} for u in members}
        exact = {u: {"cash": 0.0, "materials": 0.0, "valor": 0.0} for u in members}
        for _kill in range(CARRY_FUZZ_KILLS):
            pool = {"cash": rng.choice((0, 100, 500, 700, 1200, 2000, 29000)) * rng.choice((1, 2, 4)),
                    "materials": rng.choice((0, 1, 2, 4, 6, 70)), "valor": rng.choice((0, 0, 0, 10, 40))}
            weights = {u: rng.random() for u in members if rng.random() < 0.8}
            total = sum(weights.values())
            shares = {u: w / total for u, w in weights.items()} if total > 0 else {}
            for u, money in split_carry(pool, shares, carry, mults).items():
                for key in paid[u]:
                    paid[u][key] += money[key]
                    exact[u][key] += pool[key] * shares[u] * (mults[u] if key == "cash" else 1)
            for u, held in carry.items():
                for key, value in held.items():
                    if not 0 <= value < 1:
                        problems.append(f"carry {key} {value} of member {u} is not in [0, 1)")
        for u in members:
            for key in paid[u]:
                if paid[u][key] > exact[u][key] + 1e-6 or paid[u][key] < exact[u][key] - 1 - 1e-6:
                    problems.append(f"member {u} was paid {paid[u][key]} {key} against an exact {exact[u][key]:.4f}")
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
                   f"{CARRY_FUZZ_RUNS} fuzzed runs of {CARRY_FUZZ_KILLS} kills (1-4 members, cash x1-x2): never over the "
                   f"exact shares, never a unit under, every carry in [0, 1); solo exact, 0.9/0.1 pays 9 and 1, x1.5, an "
                   f"absent member's carry kept, a bad share pays nothing")

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

    print()
    print(
        "CHECK: "
        + (
            "PASS -- all twenty-three assertions hold"
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
    parser.add_argument("--check", action="store_true", help="run the twenty-three C0-L1b assertions")
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
    print_ladder(armory, curves, missions)

    selected = [m for index, m in sorted(missions.items()) if args.era in (None, index)]
    if not selected:
        print(f"no mission config for era {args.era}")
        sys.exit(2)
    for mission in selected:
        if crowd_mission(mission):
            print_crowd(mission, armory, combat_cfg, curves)
            continue
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
            gear, ascension, _ = loadout_for_power(armory, target)
            rows, totals = print_run(
                mission,
                armory,
                combat_cfg,
                gear,
                ascension,
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
    if args.era is None:
        import sim_range as sr

        for file in sr.load_level_files():
            if not file.get("mission"):
                print_level(file["id"], combat_cfg)
    print_helpers(armory, combat_cfg, game, shop)
    sys.exit(0)


if __name__ == "__main__":
    main()
