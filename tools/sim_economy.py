#!/usr/bin/env python
"""Greedy-player economy simulator for Era City Tycoon.

Mirrors src/shared/Economy.luau function-for-function (including the
levelCost.minBase floor in LevelUpCost and the whole-product floor in
LegacyGain) and reads the real config JSONs from the repo root -- it never
duplicates a gameplay constant.

Player model (1-second resolution):
  greedy  -- each second, after income lands, repeatedly buys the cheapest
             affordable purchase. Candidates are (a) any unowned slot whose
             `requires` slot is owned and (b) the next level-up of every owned
             building below maxLevel. Several purchases can land in the same
             second. An era completes when every slot (monument included) is
             owned -- greedy therefore grinds every level-up cheaper than the
             monument before buying it, which makes the monument cost the
             era's pace ceiling.
  rusher  -- buys slots only, never level-ups (the M1 spread metric).

Usage:
  python tools/sim_economy.py                     # default: full playthrough,
                                                  # eras 1..N, legacy carried
  python tools/sim_economy.py --era 2 --legacy 50 # one era in isolation
  python tools/sim_economy.py --strategy rusher   # slots-only player
  python tools/sim_economy.py --check             # default greedy run; exit 1
                                                  # if any era misses its band
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GAME_CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Game.json"
ERAS_DIR = REPO_ROOT / "src" / "shared" / "Config" / "Eras"

# Spec section 4 pacing bands (seconds) for the DEFAULT greedy run with legacy
# carry. Tool-only constants: INTERFACES.md sanctions the bands living here.
ERA_TIME_BANDS = {
    1: (30 * 60, 45 * 60),  # 30-45 min
    2: (int(1.5 * 3600), int(2.5 * 3600)),  # 1.5-2.5 h
    3: (4 * 3600, 6 * 3600),  # 4-6 h
    4: (8 * 3600, 12 * 3600),  # 8-12 h
}

# Reporting window for the "no wait > 90 s in the first ten minutes" pillar.
EARLY_WINDOW_SECONDS = 600
EARLY_WAIT_LIMIT_SECONDS = 90

# Safety valve so a broken config can't loop forever.
TICK_LIMIT = 48 * 3600


# --------------------------------------------------------------------------
# Economy.luau mirror -- keep these in lockstep, function for function.
# --------------------------------------------------------------------------


def milestone_mult(level, milestone_levels, milestone_multiplier):
    """Economy.MilestoneMult"""
    reached = sum(1 for m in milestone_levels if m <= level)
    return milestone_multiplier**reached


def slot_income(base_income, level, game):
    """Economy.SlotIncome"""
    return (
        base_income
        * (1 + game["levelIncomeBonus"] * (level - 1))
        * milestone_mult(level, game["milestoneLevels"], game["milestoneMultiplier"])
    )


def level_up_cost(base_cost, target_level, game):
    """Economy.LevelUpCost (minBase floor keeps zero-cost starters from free levels)"""
    level_cost = game["levelCost"]
    return (
        max(base_cost, level_cost["minBase"])
        * level_cost["factor"]
        * level_cost["growth"] ** (target_level - 1)
    )


def level_up_cost_total(base_cost, from_level, to_level, game):
    """Economy.LevelUpCostTotal"""
    return sum(
        level_up_cost(base_cost, target, game) for target in range(from_level + 1, to_level + 1)
    )


def era_mult(slots, era):
    """Economy.EraMult -- additive bonus over OWNED unlock/decor slots"""
    bonus = 0.0
    for slot in era["slots"]:
        multiplier = slot.get("multiplier")
        if (
            multiplier is not None
            and slot["id"] in slots
            and slot["type"] in ("unlock", "decor")
        ):
            bonus += multiplier
    return 1 + bonus


def legacy_mult(legacy, game):
    """Economy.LegacyMult"""
    return 1 + game["legacy"]["incomePerPoint"] * legacy


def neighbors_mult(player_count, game):
    """Economy.NeighborsMult"""
    neighbors = game["neighbors"]
    return 1 + min(neighbors["perPlayer"] * (player_count - 1), neighbors["maxBonus"])


def income_per_second(slots, era, game, mults):
    """Economy.IncomePerSecond"""
    base = 0.0
    for slot in era["slots"]:
        if slot["id"] in slots and slot["type"] == "building":
            base += slot_income(slot["baseIncome"], slots[slot["id"]], game)
    return (
        base
        * era_mult(slots, era)
        * mults["legacy"]
        * mults["pass"]
        * mults["premium"]
        * mults["neighbors"]
    )


def legacy_gain(era_index, total_levels_this_era, rebirth_count, game):
    """Economy.LegacyGain -- floor wraps the WHOLE product (INTERFACES.md)"""
    cfg = game["legacy"]
    return math.floor(
        cfg["gainBase"]
        * era_index
        * (1 + total_levels_this_era / cfg["gainLevelsDivisor"])
        * (1 + rebirth_count * cfg["gainRebirthBonus"])
    )


def offline_grant(elapsed_seconds, ips, cap_seconds, efficiency):
    """Economy.OfflineGrant"""
    return max(0, min(elapsed_seconds, cap_seconds)) * ips * efficiency


# --------------------------------------------------------------------------
# Config loading
# --------------------------------------------------------------------------


def load_game_config():
    with open(GAME_CONFIG_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def load_eras():
    eras = []
    for path in sorted(ERAS_DIR.glob("*.json")):
        with open(path, encoding="utf-8") as handle:
            eras.append(json.load(handle))
    eras.sort(key=lambda era: era["eraIndex"])
    return eras


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------


class EraResult:
    def __init__(self, era):
        self.era = era
        self.seconds = 0
        self.legacy_in = 0
        self.legacy_gained = 0
        self.total_levels = 0
        self.slot_buys = 0
        self.level_buys = 0
        self.longest_wait = 0
        self.longest_wait_early = 0
        self.unlock_beats = []  # (slotId, t)


def resolve_requires(era):
    """`requires` defaults to the previous slot in the array; first slot has none."""
    requires = {}
    slots = era["slots"]
    for index, slot in enumerate(slots):
        explicit = slot.get("requires")
        if explicit is not None:
            requires[slot["id"]] = explicit
        elif index > 0:
            requires[slot["id"]] = slots[index - 1]["id"]
        else:
            requires[slot["id"]] = None
    return requires


def simulate_era(era, game, legacy, strategy):
    by_id = {slot["id"]: slot for slot in era["slots"]}
    requires = resolve_requires(era)
    children = {}
    for slot_id, req in requires.items():
        if req is not None:
            children.setdefault(req, []).append(slot_id)

    result = EraResult(era)
    result.legacy_in = legacy
    mults = {
        "legacy": legacy_mult(legacy, game),
        "pass": 1,
        "premium": 1,
        "neighbors": 1,
    }

    owned = {}  # slotId -> level (every slot type gets level 1 on buy)
    frontier = [slot["id"] for slot in era["slots"] if requires[slot["id"]] is None]
    total_slots = len(era["slots"])
    cash = 0.0
    ips = 0.0
    t = 0
    last_purchase_t = 0

    def record_wait():
        nonlocal last_purchase_t
        wait = t - last_purchase_t
        result.longest_wait = max(result.longest_wait, wait)
        if t <= EARLY_WINDOW_SECONDS:
            result.longest_wait_early = max(result.longest_wait_early, wait)
        last_purchase_t = t

    while True:
        # Buy the cheapest affordable purchase, repeatedly, before the next tick.
        while True:
            best_cost, best_kind, best_id = None, None, None
            for slot_id in frontier:
                cost = by_id[slot_id]["baseCost"]
                if best_cost is None or cost < best_cost:
                    best_cost, best_kind, best_id = cost, "slot", slot_id
            if strategy == "greedy":
                for slot_id, level in owned.items():
                    slot = by_id[slot_id]
                    if slot["type"] == "building" and level < game["maxLevel"]:
                        cost = level_up_cost(slot["baseCost"], level + 1, game)
                        if best_cost is None or cost < best_cost:
                            best_cost, best_kind, best_id = cost, "level", slot_id
            if best_cost is None or cash < best_cost - 1e-9:
                break
            cash -= best_cost
            record_wait()
            if best_kind == "slot":
                owned[best_id] = 1
                result.slot_buys += 1
                frontier.remove(best_id)
                frontier.extend(children.get(best_id, []))
                if by_id[best_id]["type"] == "unlock":
                    result.unlock_beats.append((best_id, t))
                if len(owned) == total_slots:
                    result.seconds = t
                    result.total_levels = sum(owned.values())
                    result.legacy_gained = legacy_gain(
                        era["eraIndex"], result.total_levels, 0, game
                    )
                    return result
            else:
                owned[best_id] += 1
                result.level_buys += 1
            ips = income_per_second(owned, era, game, mults)

        t += 1
        if t > TICK_LIMIT:
            raise RuntimeError(
                f"era {era['eraIndex']} ({era['name']}) did not complete within "
                f"{TICK_LIMIT} simulated seconds -- config is broken"
            )
        cash += ips


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------


def fmt_time(seconds):
    seconds = int(seconds)
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours > 0:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"


def print_era_result(result, check_band):
    era = result.era
    band = ERA_TIME_BANDS.get(era["eraIndex"])
    print(f"Era {era['eraIndex']}: {era['name']}")
    print(
        f"  legacy carried in : {result.legacy_in}"
        f"  (income mult x{result.legacy_in_mult:.2f})"
    )
    band_note = ""
    if band is not None:
        in_band = band[0] <= result.seconds <= band[1]
        status = "OK" if in_band else "MISS"
        band_note = f"   [band {fmt_time(band[0])}-{fmt_time(band[1])}: {status}]"
    print(f"  completed in      : {fmt_time(result.seconds)}{band_note}")
    early_flag = (
        "  <-- over 90s!" if result.longest_wait_early > EARLY_WAIT_LIMIT_SECONDS else ""
    )
    print(
        f"  longest wait      : {result.longest_wait}s overall, "
        f"{result.longest_wait_early}s in first 10 min{early_flag}"
    )
    print(f"  purchases         : {result.slot_buys} slots + {result.level_buys} level-ups")
    beats = " | ".join(f"{slot_id} @ {fmt_time(t)}" for slot_id, t in result.unlock_beats)
    print(f"  unlock beats      : {beats}")
    print(
        f"  legacy gained     : +{result.legacy_gained}"
        f"  (total levels this era: {result.total_levels})"
    )
    if check_band and band is not None:
        return band[0] <= result.seconds <= band[1]
    return True


def run_full(game, eras, strategy, check):
    print(
        f"Era City Tycoon economy sim -- strategy={strategy}, "
        "full playthrough, legacy carried across advances"
    )
    print()
    legacy = 0
    total_seconds = 0
    all_in_band = True
    for era in eras:
        result = simulate_era(era, game, legacy, strategy)
        result.legacy_in_mult = legacy_mult(legacy, game)
        in_band = print_era_result(result, check)
        all_in_band = all_in_band and in_band
        print()
        legacy += result.legacy_gained
        total_seconds += result.seconds
    print(f"TOTAL playthrough : {fmt_time(total_seconds)}   final legacy: {legacy}")
    return all_in_band


def run_single(game, eras, era_index, legacy, strategy):
    era = next((e for e in eras if e["eraIndex"] == era_index), None)
    if era is None:
        print(f"error: no era config with eraIndex {era_index}", file=sys.stderr)
        return False
    print(
        f"Era City Tycoon economy sim -- strategy={strategy}, "
        f"era {era_index} in isolation, legacy={legacy}"
    )
    print()
    result = simulate_era(era, game, legacy, strategy)
    result.legacy_in_mult = legacy_mult(legacy, game)
    print_era_result(result, False)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--era", type=int, help="run a single era in isolation")
    parser.add_argument(
        "--legacy", type=int, default=0, help="starting legacy for --era runs (default 0)"
    )
    parser.add_argument(
        "--strategy",
        choices=("greedy", "rusher"),
        default="greedy",
        help="greedy = cheapest affordable thing; rusher = slots only",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="run the default greedy playthrough and exit 1 if any era misses its band",
    )
    args = parser.parse_args()

    game = load_game_config()
    eras = load_eras()

    if args.check:
        if args.era is not None or args.strategy != "greedy":
            print("error: --check runs the default greedy playthrough only", file=sys.stderr)
            sys.exit(2)
        ok = run_full(game, eras, "greedy", True)
        print()
        print("CHECK: " + ("PASS -- all eras in band" if ok else "FAIL -- era out of band"))
        sys.exit(0 if ok else 1)

    if args.era is not None:
        ok = run_single(game, eras, args.era, args.legacy, args.strategy)
        sys.exit(0 if ok else 2)

    run_full(game, eras, args.strategy, False)
    sys.exit(0)


if __name__ == "__main__":
    main()
