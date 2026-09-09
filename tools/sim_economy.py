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
  py tools/sim_economy.py --check                  # default greedy run; exit 1
                                                  # if any era misses its band
  py tools/sim_economy.py --passes doublecash,vip --premium
                                                  # fully-paid pacing
  py tools/sim_economy.py --packs                 # cash-pack grants per era
  py tools/sim_economy.py --laps 2                # two laps, rebirth between
  py tools/sim_economy.py --rebirth 1 --era 1     # one era as a reborn player
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
MONETIZATION_CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Monetization.json"

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
        * mults.get("perk", 1)  # prototype only (Founder's Blessing); absent = 1
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


def era_slot_cost_total(era):
    """Economy.EraSlotCostTotal"""
    return sum(slot["baseCost"] for slot in era["slots"])


def pack_grant(minutes, ips, slot_cost_total, cap_fraction):
    """Economy.PackGrant"""
    return max(0.0, min(minutes * 60 * ips, cap_fraction * slot_cost_total))


def pack_cap_fraction(product, monetization):
    """Caller-side rule (INTERFACES.md M4 "Per-pack caps"):
    def.capFraction or cfg.packCapFractionOfEraSlotCost."""
    fraction = product.get("capFraction")
    if fraction is None:
        fraction = monetization["packCapFractionOfEraSlotCost"]
    return fraction


def pass_mult(passes, monetization):
    """Economy.PassMult"""
    multipliers = monetization["multipliers"]
    value = 1.0
    if passes.get("DoubleCash"):
        value *= multipliers["doubleCash"]
    if passes.get("VIP"):
        value *= multipliers["vip"]
    return value


def premium_mult(is_premium, monetization):
    """Economy.PremiumMult"""
    return monetization["multipliers"]["premium"] if is_premium else 1


# --------------------------------------------------------------------------
# Legacy shop PROTOTYPE (docs/LEGACY_SHOP.md, Phase 2 design). Nothing below
# exists in Economy.luau or in any config yet: the perk table is hardcoded on
# purpose until the M6 contracts freeze LegacyShop.json, and it is inert unless
# --shop / --perks is given so the default output stays byte-identical.
# --------------------------------------------------------------------------

# id -> tier costs (Legacy) and the effect per tier. "values" is indexed by
# tier (index 0 = not owned).
PERK_DEFS = {
    "founders": {"name": "Founder's Blessing", "costs": [80, 160, 300, 400, 550]},
    "builders": {"name": "Master Builders", "costs": [200, 400, 650]},
    "inheritance": {"name": "Inheritance", "costs": [40, 90, 180], "values": [0, 3, 5, 8]},
    "levelfloor": {"name": "Level Floor", "costs": [200, 500], "values": [1, 5, 8]},
    "milestone75": {"name": "Extra Milestone", "costs": [350], "values": [None, 75]},
    "neighbours": {"name": "Good Neighbours", "costs": [250], "values": [0.03, 0.04]},
    "longmemory": {"name": "Long Memory", "costs": [80, 160, 320], "values": [0, 2, 4, 6]},
}
FOUNDERS_PER_TIER = 0.05  # +5% income per tier, multiplicative
BUILDERS_PER_TIER = 0.10  # -10% level-up cost per tier

# Pure sinks: no field in the sim reads them; the policy buys them last.
COSMETIC_DEFS = [
    ("signTitle", "Plot-sign title", 250),
    ("nameTagColour", "Name-tag colour", 300),
    ("monumentGlow", "Monument glow", 400),
    ("advanceFireworks", "Advance fireworks", 500),
    ("goldenRoads", "Golden road tint", 600),
]

# --perks auto: buy in this order whenever the balance allows, re-scanning from
# the top after every purchase. Ordered by measured pacing value per Legacy
# (docs/LEGACY_SHOP.md "Perk value"), QoL perks after, cosmetics last.
PERK_POLICY = [
    ("inheritance", 1),
    ("founders", 1),
    ("builders", 1),
    ("founders", 2),
    ("levelfloor", 1),
    ("longmemory", 1),
    ("builders", 2),
    ("founders", 3),
    ("inheritance", 2),
    ("milestone75", 1),
    ("levelfloor", 2),
    ("builders", 3),
    ("founders", 4),
    ("longmemory", 2),
    ("inheritance", 3),
    ("founders", 5),
    ("neighbours", 1),
    ("longmemory", 3),
] + [(cosmetic_id, 1) for cosmetic_id, _, _ in COSMETIC_DEFS]

SHOP_MODELS = ("spend", "invest", "softcap")
DEFAULT_SOFTCAP = 1000


def perk_cost(perk_id, tier):
    for cosmetic_id, _, cost in COSMETIC_DEFS:
        if cosmetic_id == perk_id:
            return cost
    return PERK_DEFS[perk_id]["costs"][tier - 1]


def perk_max_tier(perk_id):
    if perk_id in PERK_DEFS:
        return len(PERK_DEFS[perk_id]["costs"])
    return 1


def perk_income_mult(perks):
    """Would become Economy.PerkIncomeMult(perks, shopConfig)."""
    return (1 + FOUNDERS_PER_TIER) ** perks.get("founders", 0)


def perk_level_cost_factor(perks):
    """Would become a discount argument on Economy.LevelUpCost."""
    return 1 - BUILDERS_PER_TIER * perks.get("builders", 0)


def perk_game(game, perks):
    """Extra Milestone: a per-player milestone list, where the sim today reads
    the global one. Returns the config untouched when the perk is not owned."""
    extra = PERK_DEFS["milestone75"]["values"][perks.get("milestone75", 0)]
    if extra is None:
        return game
    patched = dict(game)
    patched["milestoneLevels"] = sorted(game["milestoneLevels"] + [extra])
    return patched


def inheritance_cash(era, perks):
    """Cash, not slots: the requires chain is untouched."""
    count = PERK_DEFS["inheritance"]["values"][perks.get("inheritance", 0)]
    return float(sum(slot["baseCost"] for slot in era["slots"][:count]))


def legacy_mult_model(legacy, game, model, softcap):
    """Model C: linear up to `softcap`, then each doubling of Legacy adds
    softcap*ln(2) effective points. Continuous and smooth at the cap, so
    every lap-1 number (max 887) is untouched."""
    if model == "softcap" and legacy > softcap:
        effective = softcap + softcap * math.log(legacy / softcap)
        return 1 + game["legacy"]["incomePerPoint"] * effective
    return legacy_mult(legacy, game)


def parse_perks(raw):
    """--perks auto | founders=2,builders=1,..."""
    if raw == "auto":
        return "auto"
    perks = {}
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        perk_id, _, tier = token.partition("=")
        tier = int(tier) if tier else 1
        if perk_id not in PERK_DEFS or not 0 <= tier <= perk_max_tier(perk_id):
            print(f"error: unknown perk or tier '{token}'", file=sys.stderr)
            sys.exit(2)
        perks[perk_id] = tier
    return perks


class Shop:
    """Purchase state for one run. `legacy` (the passive source) and
    `spendable` diverge only under the invest/softcap models."""

    def __init__(self, model, perks, softcap):
        self.model = model
        self.softcap = softcap
        self.auto = perks == "auto"
        self.perks = {} if self.auto else dict(perks)
        self.spendable = 0
        self.log = []  # (lap, era_index, perk_id, tier, cost, balance_after)

    def earn(self, amount):
        self.spendable += amount

    def balance(self, legacy):
        return legacy if self.model == "spend" else self.spendable

    def buy_affordable(self, legacy, lap, era_index):
        """Returns the (possibly reduced) legacy after the policy has run."""
        if not self.auto:
            return legacy
        bought = True
        while bought:
            bought = False
            for perk_id, tier in PERK_POLICY:
                if self.perks.get(perk_id, 0) != tier - 1:
                    continue
                cost = perk_cost(perk_id, tier)
                if self.balance(legacy) < cost:
                    continue
                if self.model == "spend":
                    legacy -= cost
                else:
                    self.spendable -= cost
                self.perks[perk_id] = tier
                self.log.append((lap, era_index, perk_id, tier, cost, self.balance(legacy)))
                bought = True
                break
        return legacy

    def owned_label(self):
        bits = [f"{perk_id} {tier}" for perk_id, tier in self.perks.items() if tier > 0]
        return ", ".join(bits) if bits else "nothing"


# --------------------------------------------------------------------------
# Config loading
# --------------------------------------------------------------------------


def load_game_config():
    with open(GAME_CONFIG_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def load_monetization_config():
    with open(MONETIZATION_CONFIG_PATH, encoding="utf-8") as handle:
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


def simulate_era(
    era,
    game,
    legacy,
    strategy,
    paid=None,
    record_ips=False,
    rebirth_count=0,
    perks=None,
    legacy_mult_value=None,
):
    """paid = {"pass": x, "premium": y}; None keeps the free-player defaults.
    rebirth_count feeds LegacyGain exactly as the server passes state.rebirthCount.
    perks / legacy_mult_value are the Legacy-shop prototype (None = today's game)."""
    perks = perks or {}
    game = perk_game(game, perks)
    level_cost_factor = perk_level_cost_factor(perks)
    level_floor = PERK_DEFS["levelfloor"]["values"][perks.get("levelfloor", 0)]
    by_id = {slot["id"]: slot for slot in era["slots"]}
    requires = resolve_requires(era)
    children = {}
    for slot_id, req in requires.items():
        if req is not None:
            children.setdefault(req, []).append(slot_id)

    result = EraResult(era)
    result.legacy_in = legacy
    mults = {
        "legacy": legacy_mult(legacy, game) if legacy_mult_value is None else legacy_mult_value,
        "pass": paid["pass"] if paid else 1,
        "premium": paid["premium"] if paid else 1,
        "neighbors": 1,
    }
    if perks:
        mults["perk"] = perk_income_mult(perks)
    if record_ips:
        result.ips_series = []

    owned = {}  # slotId -> level (every slot type gets level 1 on buy)
    frontier = [slot["id"] for slot in era["slots"] if requires[slot["id"]] is None]
    total_slots = len(era["slots"])
    cash = inheritance_cash(era, perks)
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
                        cost = level_up_cost(slot["baseCost"], level + 1, game) * level_cost_factor
                        if best_cost is None or cost < best_cost:
                            best_cost, best_kind, best_id = cost, "level", slot_id
            if best_cost is None or cash < best_cost - 1e-9:
                break
            cash -= best_cost
            record_wait()
            if best_kind == "slot":
                owned[best_id] = level_floor if by_id[best_id]["type"] == "building" else 1
                result.slot_buys += 1
                frontier.remove(best_id)
                frontier.extend(children.get(best_id, []))
                if by_id[best_id]["type"] == "unlock":
                    result.unlock_beats.append((best_id, t))
                if len(owned) == total_slots:
                    result.seconds = t
                    result.total_levels = sum(owned.values())
                    result.legacy_gained = legacy_gain(
                        era["eraIndex"], result.total_levels, rebirth_count, game
                    )
                    return result
            else:
                owned[best_id] += 1
                result.level_buys += 1
            ips = income_per_second(owned, era, game, mults)

        if record_ips:
            result.ips_series.append(ips)
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


def paid_label(paid):
    """Header fragment; empty for the free player so default output never moves."""
    if paid is None:
        return ""
    bits = []
    if paid["passes"].get("DoubleCash"):
        bits.append("DoubleCash")
    if paid["passes"].get("VIP"):
        bits.append("VIP")
    if paid["premium"] > 1:
        bits.append("Premium")
    joined = "+".join(bits) if bits else "none"
    return (
        f"paid {joined} (pass x{paid['pass']:.2f}, "
        f"premium x{paid['premium']:.2f}), "
    )


def shop_label(shop):
    if shop is None:
        return ""
    softcap = f" softcap {shop.softcap}" if shop.model == "softcap" else ""
    perks = "auto policy" if shop.auto else shop.owned_label()
    return f"legacy shop {shop.model}{softcap} ({perks}), "


def run_full(game, eras, strategy, check, paid=None, rebirth=0, laps=1, shop=None):
    """laps > 1 rebirths between laps (era -> 1, rebirthCount += 1, legacy kept),
    mirroring the RequestRebirth handler. The band check judges lap 1 only: the
    spec bands describe a first playthrough. Lap headers are printed only when
    the run is not the plain single lap so the default output never moves.
    shop (prototype) runs the purchase policy at every era entry, i.e. the only
    moments Legacy changes."""
    print(
        f"Era City Tycoon economy sim -- strategy={strategy}, "
        f"{paid_label(paid)}{shop_label(shop)}"
        "full playthrough, legacy carried across advances"
    )
    print()
    multi = laps > 1 or rebirth > 0
    legacy = 0
    rebirth_count = rebirth
    grand_seconds = 0
    all_in_band = True
    model = shop.model if shop else None
    softcap = shop.softcap if shop else 0
    for lap in range(1, laps + 1):
        if multi:
            print(
                f"=== Lap {lap} (rebirthCount {rebirth_count}, legacy in {legacy}, "
                f"income mult x{legacy_mult_model(legacy, game, model, softcap):.2f}) ==="
            )
            print()
        total_seconds = 0
        for era in eras:
            if shop is not None:
                legacy = shop.buy_affordable(legacy, lap, era["eraIndex"])
            mult_value = legacy_mult_model(legacy, game, model, softcap)
            result = simulate_era(
                era,
                game,
                legacy,
                strategy,
                paid,
                False,
                rebirth_count,
                shop.perks if shop else None,
                mult_value if shop else None,
            )
            result.legacy_in_mult = mult_value
            in_band = print_era_result(result, check and lap == 1)
            if shop is not None:
                bought = [
                    f"{perk_id} {tier} ({cost})"
                    for entry_lap, entry_era, perk_id, tier, cost, _ in shop.log
                    if entry_lap == lap and entry_era == era["eraIndex"]
                ]
                print(
                    f"  legacy shop       : owns {shop.owned_label()} | "
                    f"balance {shop.balance(legacy)}"
                    + (f" | bought at entry: {', '.join(bought)}" if bought else "")
                )
            all_in_band = all_in_band and in_band
            print()
            legacy += result.legacy_gained
            if shop is not None:
                shop.earn(result.legacy_gained)
            total_seconds += result.seconds
        grand_seconds += total_seconds
        if multi:
            print(f"Lap {lap} total   : {fmt_time(total_seconds)}   legacy after lap: {legacy}")
            print()
        else:
            print(f"TOTAL playthrough : {fmt_time(total_seconds)}   final legacy: {legacy}")
        rebirth_count += 1
    if multi:
        print(
            f"TOTAL {laps} lap(s)  : {fmt_time(grand_seconds)}   final legacy: {legacy}"
            f"   rebirthCount: {rebirth_count}"
        )
    if shop is not None and shop.auto:
        spent = sum(cost for _, _, _, _, cost, _ in shop.log)
        print(
            f"SHOP: {len(shop.log)} purchases, {spent} Legacy spent, "
            f"balance {shop.balance(legacy)}, passive mult "
            f"x{legacy_mult_model(legacy, game, model, softcap):.2f}"
        )
    return all_in_band


def run_single(game, eras, era_index, legacy, strategy, paid=None, rebirth=0):
    era = next((e for e in eras if e["eraIndex"] == era_index), None)
    if era is None:
        print(f"error: no era config with eraIndex {era_index}", file=sys.stderr)
        return False
    print(
        f"Era City Tycoon economy sim -- strategy={strategy}, "
        f"{paid_label(paid)}"
        f"era {era_index} in isolation, legacy={legacy}"
        f"{f', rebirthCount={rebirth}' if rebirth else ''}"
    )
    print()
    result = simulate_era(era, game, legacy, strategy, paid, False, rebirth)
    result.legacy_in_mult = legacy_mult(legacy, game)
    print_era_result(result, False)
    return True


def fmt_cash(value):
    """Compact magnitude for the packs table (report-only; UI uses Format.luau)."""
    for suffix, scale in (("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(value) >= scale:
            return f"{value / scale:.2f}{suffix}"
    return f"{value:.2f}"


def run_packs(game, eras, monetization):
    """Evidence for spec section 6 rule 6: what a pack actually delivers.

    Mid-era income is the free greedy player's income at the halfway point (in
    time) of the default run, legacy carried -- i.e. the moment a player is
    most likely to consider a pack.
    """
    default_fraction = monetization["packCapFractionOfEraSlotCost"]
    packs = [p for p in monetization["products"] if p.get("minutes") is not None]
    print(
        "Era City Tycoon pack report -- grants at mid-era income of the default "
        "greedy run"
    )
    print(
        "cap = the pack's own capFraction (default "
        f"packCapFractionOfEraSlotCost {default_fraction:g}) x era total slot cost"
    )
    print()
    legacy = 0
    for era in eras:
        result = simulate_era(era, game, legacy, "greedy", None, True)
        result.legacy_in_mult = legacy_mult(legacy, game)
        total_cost = era_slot_cost_total(era)
        mid_index = min(result.seconds // 2, len(result.ips_series) - 1)
        mid_ips = result.ips_series[mid_index]
        print(f"Era {era['eraIndex']}: {era['name']}")
        print(
            f"  era length {fmt_time(result.seconds)}, total slot cost "
            f"{fmt_cash(total_cost)}"
        )
        print(
            f"  mid-era ({fmt_time(mid_index)}) income {fmt_cash(mid_ips)}/s"
        )
        print(
            f"  {'pack':<10}{'capFrac':>9}{'uncapped':>12}{'cap':>12}"
            f"{'granted':>12}{'% era cost':>12}{'capped?':>9}{'real mins':>11}"
        )
        for pack in packs:
            minutes = pack["minutes"]
            fraction = pack_cap_fraction(pack, monetization)
            cap = fraction * total_cost
            uncapped = minutes * 60 * mid_ips
            granted = pack_grant(minutes, mid_ips, total_cost, fraction)
            real_minutes = granted / mid_ips / 60 if mid_ips > 0 else 0
            print(
                f"  {pack['key']:<10}{fraction:>9.2f}"
                f"{fmt_cash(uncapped):>12}{fmt_cash(cap):>12}"
                f"{fmt_cash(granted):>12}{100 * granted / total_cost:>11.1f}%"
                f"{('yes' if granted < uncapped - 1e-6 else 'no'):>9}"
                f"{real_minutes:>11.1f}"
            )
        print()
        legacy += result.legacy_gained


def parse_passes(raw):
    """--passes doublecash,vip -> the Economy.PassMult `passes` map."""
    known = {"doublecash": "DoubleCash", "vip": "VIP", "offlinepro": "OfflinePro"}
    passes = {}
    for token in raw.split(","):
        token = token.strip().lower()
        if not token:
            continue
        if token not in known:
            print(f"error: unknown pass '{token}'", file=sys.stderr)
            sys.exit(2)
        passes[known[token]] = True
    return passes


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
        "--passes",
        default="",
        help="comma-separated passes to own, e.g. doublecash,vip (default none)",
    )
    parser.add_argument(
        "--premium",
        action="store_true",
        help="simulate a Roblox Premium member",
    )
    parser.add_argument(
        "--packs",
        action="store_true",
        help="report cash-pack grants per era (uncapped value, cap, delivered)",
    )
    parser.add_argument(
        "--rebirth",
        type=int,
        default=0,
        help="starting rebirthCount (feeds LegacyGain like the server; default 0)",
    )
    parser.add_argument(
        "--laps",
        type=int,
        default=1,
        help="consecutive laps of eras 1..N, rebirthing between laps (default 1)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="run the default greedy playthrough and exit 1 if any era misses its band",
    )
    parser.add_argument(
        "--shop",
        choices=SHOP_MODELS,
        help="PROTOTYPE legacy shop model (docs/LEGACY_SHOP.md); implies --perks auto",
    )
    parser.add_argument(
        "--perks",
        help="PROTOTYPE: 'auto' (buy by policy at era entry) or a fixed set owned from "
        "the start at no cost, e.g. founders=2,builders=1",
    )
    parser.add_argument(
        "--softcap",
        type=int,
        default=DEFAULT_SOFTCAP,
        help=f"PROTOTYPE: legacy softcap for --shop softcap (default {DEFAULT_SOFTCAP})",
    )
    args = parser.parse_args()
    if args.rebirth < 0 or args.laps < 1:
        print("error: --rebirth must be >= 0 and --laps >= 1", file=sys.stderr)
        sys.exit(2)

    shop = None
    if args.shop is not None or args.perks is not None:
        if args.era is not None or args.packs:
            print("error: --shop/--perks apply to full playthroughs only", file=sys.stderr)
            sys.exit(2)
        perks = parse_perks(args.perks) if args.perks is not None else "auto"
        if perks == "auto" and args.shop is None:
            print("error: --perks auto needs --shop <model>", file=sys.stderr)
            sys.exit(2)
        shop = Shop(args.shop or "invest", perks, args.softcap)

    game = load_game_config()
    eras = load_eras()
    monetization = load_monetization_config()

    paid = None
    passes = parse_passes(args.passes)
    if passes or args.premium:
        paid = {
            "passes": passes,
            "pass": pass_mult(passes, monetization),
            "premium": premium_mult(args.premium, monetization),
        }

    if args.packs:
        if paid is not None:
            print(
                "error: --packs reports the free player's mid-era income only",
                file=sys.stderr,
            )
            sys.exit(2)
        run_packs(game, eras, monetization)
        sys.exit(0)

    if args.check:
        if (
            args.era is not None
            or args.strategy != "greedy"
            or paid is not None
            or args.rebirth != 0
            or shop is not None
        ):
            print("error: --check runs the default greedy playthrough only", file=sys.stderr)
            sys.exit(2)
        ok = run_full(game, eras, "greedy", True, None, 0, args.laps)
        print()
        print("CHECK: " + ("PASS -- all eras in band" if ok else "FAIL -- era out of band"))
        sys.exit(0 if ok else 1)

    if args.era is not None:
        ok = run_single(game, eras, args.era, args.legacy, args.strategy, paid, args.rebirth)
        sys.exit(0 if ok else 2)

    run_full(game, eras, args.strategy, False, paid, args.rebirth, args.laps, shop)
    sys.exit(0)


if __name__ == "__main__":
    main()
