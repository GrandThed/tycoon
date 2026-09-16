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
  py tools/sim_economy.py --perks auto --laps 6   # Legacy shop: buy perks by
                                                  # policy at every era entry
  py tools/sim_economy.py --perks levelFloor=2 --strategy rusher
                                                  # perks owned from the start
  py tools/sim_economy.py --perks auto --softcap 700 --laps 6
                                                  # explore the softcap knob
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
LEGACY_SHOP_CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "LegacyShop.json"
CITY_DRESSING_CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "CityDressing.json"

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


def slot_income(base_income, level, game, milestone_levels=None):
    """Economy.SlotIncome -- milestone_levels (Extra Milestone) overrides game.milestoneLevels"""
    if milestone_levels is None:
        milestone_levels = game["milestoneLevels"]
    return (
        base_income
        * (1 + game["levelIncomeBonus"] * (level - 1))
        * milestone_mult(level, milestone_levels, game["milestoneMultiplier"])
    )


def level_up_cost(base_cost, target_level, game, discount=None):
    """Economy.LevelUpCost (minBase floor keeps zero-cost starters from free levels).
    The Master Builders discount is applied HERE and nowhere else, so the Build
    panel preview and the server charge can never disagree."""
    level_cost = game["levelCost"]
    return (
        max(base_cost, level_cost["minBase"])
        * level_cost["factor"]
        * level_cost["growth"] ** (target_level - 1)
        * (1 - (discount or 0))
    )


def level_up_cost_total(base_cost, from_level, to_level, game, discount=None):
    """Economy.LevelUpCostTotal"""
    return sum(
        level_up_cost(base_cost, target, game, discount)
        for target in range(from_level + 1, to_level + 1)
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
    """Economy.LegacyMult -- linear up to legacy.softcap, then each doubling of
    Legacy adds softcap*ln(2) effective points (continuous and smooth at the
    cap). `softcap` is optional so an older Game.json behaves linearly."""
    softcap = game["legacy"].get("softcap")
    if softcap is not None and legacy > softcap:
        effective = softcap + softcap * math.log(legacy / softcap)
    else:
        effective = legacy
    return 1 + game["legacy"]["incomePerPoint"] * effective


def neighbors_mult(player_count, game, per_player=None, max_bonus=None):
    """Economy.NeighborsMult -- per_player/max_bonus (Good Neighbours) default to game.neighbors"""
    neighbors = game["neighbors"]
    if per_player is None:
        per_player = neighbors["perPlayer"]
    if max_bonus is None:
        max_bonus = neighbors["maxBonus"]
    return 1 + min(per_player * (player_count - 1), max_bonus)


def income_per_second(slots, era, game, mults, milestone_levels=None):
    """Economy.IncomePerSecond -- mults.perk (Founder's Blessing, 1 when none) sits
    beside mults.legacy. milestone_levels is threaded to SlotIncome for the
    owner's Extra Milestone list (see the contract note in docs/BALANCE.md M6)."""
    base = 0.0
    for slot in era["slots"]:
        if slot["id"] in slots and slot["type"] == "building":
            base += slot_income(slot["baseIncome"], slots[slot["id"]], game, milestone_levels)
    return (
        base
        * era_mult(slots, era)
        * mults["legacy"]
        * mults["perk"]
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


def city_growth_score(owned_count, total_levels, owned_weight):
    """CityGrowth.Score"""
    return owned_count * owned_weight + total_levels


def city_growth_tier_for(score, thresholds):
    """CityGrowth.TierFor -- counts thresholds reached, so out-of-order configs stay monotonic"""
    return sum(1 for threshold in thresholds if threshold <= score)


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
# Legacy shop (M6) -- Economy.luau helpers, mirrored 1:1. Every number comes
# from Config/LegacyShop.json; shop_state is the profile's
# legacyShop = { spent, perks = { perkId -> tier } }.
# --------------------------------------------------------------------------

PERK_EFFECTS = (
    "incomeMult",
    "levelCostDiscount",
    "startingSlots",
    "levelFloor",
    "extraMilestone",
    "neighbours",
    "offlineCapSeconds",
    "cosmetic",
)


def empty_shop_state():
    """The v3 profile template's legacyShop field."""
    return {"spent": 0, "perks": {}}


def perk_def(shop, perk_id):
    for perk in shop["perks"]:
        if perk["id"] == perk_id:
            return perk
    return None


def perk_tier(shop_state, perk_id):
    """Economy.PerkTier -- 0 when unowned or the state is nil"""
    if shop_state is None:
        return 0
    return shop_state["perks"].get(perk_id, 0)


def perk_value(shop, shop_state, perk_id):
    """Economy.PerkValue -- the owned tier's TOTAL value, None when unowned or
    the perk is not in the config (a profile perk absent from the config is
    ignored, never an error)."""
    tier = perk_tier(shop_state, perk_id)
    perk = perk_def(shop, perk_id)
    if perk is None or tier <= 0:
        return None
    return perk["tiers"][min(tier, len(perk["tiers"])) - 1]["value"]


def perk_income_mult(shop, shop_state):
    """Economy.PerkIncomeMult -- founders value or 1"""
    value = perk_value(shop, shop_state, "founders")
    return 1 if value is None else value


def level_cost_discount(shop, shop_state):
    """Economy.LevelCostDiscount -- builders value or 0"""
    value = perk_value(shop, shop_state, "builders")
    return 0 if value is None else value


def level_floor(shop, shop_state):
    """Economy.LevelFloor -- levelFloor value or 1"""
    value = perk_value(shop, shop_state, "levelFloor")
    return 1 if value is None else value


def milestone_levels(shop, shop_state, game):
    """Economy.MilestoneLevels -- game list plus the Extra Milestone level, sorted"""
    extra = perk_value(shop, shop_state, "milestone75")
    if extra is None:
        return game["milestoneLevels"]
    return sorted(game["milestoneLevels"] + [extra])


def neighbors_params(shop, shop_state, game):
    """Economy.NeighborsParams -> (perPlayer, maxBonus)"""
    tier = perk_tier(shop_state, "neighbours")
    perk = perk_def(shop, "neighbours")
    if perk is None or tier <= 0:
        return game["neighbors"]["perPlayer"], game["neighbors"]["maxBonus"]
    owned = perk["tiers"][min(tier, len(perk["tiers"])) - 1]
    return owned["value"], owned["maxBonus"]


def offline_cap_seconds(passes, shop_state, shop, game):
    """Economy.OfflineCapSeconds -- the pass cap plus Long Memory, additively"""
    offline = game["offline"]
    cap = offline["capSecondsOfflinePro"] if passes.get("OfflinePro") else offline["capSeconds"]
    extra = perk_value(shop, shop_state, "longMemory")
    return cap + (0 if extra is None else extra)


def inheritance_cash(era, shop, shop_state):
    """Economy.InheritanceCash -- baseCost of the first N slots in ARRAY order
    (cash only; the requires chain is untouched). 0 when unowned."""
    count = perk_value(shop, shop_state, "inheritance")
    if count is None:
        return 0
    return sum(slot["baseCost"] for slot in era["slots"][:count])


def legacy_spendable(state):
    """Economy.LegacySpendable -- legacy never decreases; spent is tracked beside it"""
    return state["legacy"] - state["legacyShop"]["spent"]


def next_perk_tier(shop, shop_state, perk_id):
    """Economy.NextPerkTier -> (tier def, 1-based index) or (None, 0) when maxed/unknown"""
    perk = perk_def(shop, perk_id)
    if perk is None:
        return None, 0
    index = perk_tier(shop_state, perk_id) + 1
    if index > len(perk["tiers"]):
        return None, 0
    return perk["tiers"][index - 1], index


# --perks auto: buy in this order whenever the spendable balance allows,
# re-scanning from the top after every purchase. Ordered by measured pacing
# value per Legacy (docs/LEGACY_SHOP.md section 2), QoL perks after; every
# cosmetic in the config follows in config order. Tool-only policy, not a
# game constant: the real player chooses.
PERK_POLICY = [
    ("inheritance", 1),
    ("founders", 1),
    ("builders", 1),
    ("founders", 2),
    ("levelFloor", 1),
    ("longMemory", 1),
    ("builders", 2),
    ("founders", 3),
    ("inheritance", 2),
    ("milestone75", 1),
    ("levelFloor", 2),
    ("builders", 3),
    ("founders", 4),
    ("longMemory", 2),
    ("inheritance", 3),
    ("founders", 5),
    ("neighbours", 1),
    ("longMemory", 3),
]


def shop_policy(shop):
    return PERK_POLICY + [(perk["id"], 1) for perk in shop["perks"] if perk["cosmetic"]]


def parse_perks(raw, shop):
    """--perks auto | founders=2,builders=1,... (owned from the start, at no cost)"""
    if raw == "auto":
        return "auto"
    perks = {}
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        perk_id, _, tier = token.partition("=")
        tier = int(tier) if tier else 1
        perk = perk_def(shop, perk_id)
        if perk is None or not 0 <= tier <= len(perk["tiers"]):
            print(f"error: unknown perk or tier '{token}'", file=sys.stderr)
            sys.exit(2)
        perks[perk_id] = tier
    return perks


class Shop:
    """One run's legacyShop state plus the auto-buy policy. The passive
    multiplier reads the FULL legacy total (Model C); buying only lowers the
    spendable balance."""

    def __init__(self, config, perks):
        self.config = config
        self.auto = perks == "auto"
        self.state = empty_shop_state()
        if not self.auto:
            self.state["perks"] = {perk_id: tier for perk_id, tier in perks.items() if tier > 0}
        self.log = []  # (lap, era_index, perk_id, tier, cost, spendable_after)

    def spendable(self, legacy):
        return legacy_spendable({"legacy": legacy, "legacyShop": self.state})

    def buy_affordable(self, legacy, lap, era_index):
        """Mirrors RequestBuyPerk's checks: next tier exists, spendable >= cost."""
        if not self.auto:
            return
        bought = True
        while bought:
            bought = False
            for perk_id, tier in shop_policy(self.config):
                next_tier, index = next_perk_tier(self.config, self.state, perk_id)
                if next_tier is None or index != tier:
                    continue
                if self.spendable(legacy) < next_tier["cost"]:
                    continue
                self.state["perks"][perk_id] = index
                self.state["spent"] += next_tier["cost"]
                self.log.append(
                    (lap, era_index, perk_id, index, next_tier["cost"], self.spendable(legacy))
                )
                bought = True
                break

    def owned_label(self):
        bits = [f"{perk_id} {tier}" for perk_id, tier in self.state["perks"].items() if tier > 0]
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


def load_legacy_shop_config():
    """Catalog.GetLegacyShopConfig: the module, or an empty shop when the file
    is missing (the in-game shop then hides). Validates the v1 schema so a
    broken config fails --check instead of silently doing nothing."""
    if not LEGACY_SHOP_CONFIG_PATH.exists():
        return {"version": 1, "perks": []}
    with open(LEGACY_SHOP_CONFIG_PATH, encoding="utf-8") as handle:
        shop = json.load(handle)
    validate_legacy_shop_config(shop)
    return shop


def validate_legacy_shop_config(shop):
    seen = set()
    for perk in shop["perks"]:
        perk_id = perk["id"]
        if perk_id in seen:
            raise ValueError(f"LegacyShop.json: duplicate perk id {perk_id}")
        seen.add(perk_id)
        if perk["effect"] not in PERK_EFFECTS:
            raise ValueError(f"LegacyShop.json: {perk_id} has unknown effect {perk['effect']}")
        if perk["cosmetic"] != (perk["effect"] == "cosmetic"):
            raise ValueError(f"LegacyShop.json: {perk_id} cosmetic flag and effect disagree")
        tiers = perk["tiers"]
        if not tiers:
            raise ValueError(f"LegacyShop.json: {perk_id} has no tiers")
        if perk["cosmetic"] and (len(tiers) != 1 or tiers[0]["value"] != 0):
            raise ValueError(f"LegacyShop.json: cosmetic {perk_id} must have one tier, value 0")
        for tier in tiers:
            if tier["cost"] <= 0:
                raise ValueError(f"LegacyShop.json: {perk_id} has a non-positive cost")
            if perk["effect"] == "neighbours" and "maxBonus" not in tier:
                raise ValueError(f"LegacyShop.json: {perk_id} tier is missing maxBonus")
        if len(perk["description"]) > 90:
            raise ValueError(f"LegacyShop.json: {perk_id} description exceeds 90 characters")


def load_city_dressing_config():
    """None when the file is absent: the game disables dressing then, so the sim
    simply skips the tier timeline."""
    if not CITY_DRESSING_CONFIG_PATH.exists():
        return None
    with open(CITY_DRESSING_CONFIG_PATH, encoding="utf-8") as handle:
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
        self.tier_times = None  # t at which city growth tier i+1 was first reached


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
    shop=None,
    shop_state=None,
    city=None,
):
    """paid = {"pass": x, "premium": y}; None keeps the free-player defaults.
    rebirth_count feeds LegacyGain exactly as the server passes state.rebirthCount.
    shop / shop_state are the LegacyShop config and the player's legacyShop
    state; None means an empty shop (every helper returns its default).
    city is the CityDressing config; when given, result.tier_times records the
    first second each growth tier is reached (the server republishes the tier
    after every buy and level-up, so checking per purchase is exact)."""
    if shop is None:
        shop = {"version": 1, "perks": []}
    if shop_state is None:
        shop_state = empty_shop_state()
    discount = level_cost_discount(shop, shop_state)
    floor = level_floor(shop, shop_state)
    milestones = milestone_levels(shop, shop_state, game)
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
        "perk": perk_income_mult(shop, shop_state),
        "pass": paid["pass"] if paid else 1,
        "premium": paid["premium"] if paid else 1,
        "neighbors": 1,
    }
    if record_ips:
        result.ips_series = []

    owned = {}  # slotId -> level (every slot type gets level 1 on buy)
    frontier = [slot["id"] for slot in era["slots"] if requires[slot["id"]] is None]
    total_slots = len(era["slots"])
    cash = inheritance_cash(era, shop, shop_state)
    ips = 0.0
    t = 0
    last_purchase_t = 0
    if city is not None:
        thresholds = city["tier"]["thresholds"]
        result.tier_times = [None] * len(thresholds)

    def record_wait():
        nonlocal last_purchase_t
        wait = t - last_purchase_t
        result.longest_wait = max(result.longest_wait, wait)
        if t <= EARLY_WINDOW_SECONDS:
            result.longest_wait_early = max(result.longest_wait_early, wait)
        last_purchase_t = t

    def record_tier():
        if city is None:
            return
        score = city_growth_score(len(owned), sum(owned.values()), city["tier"]["ownedWeight"])
        for index in range(city_growth_tier_for(score, thresholds)):
            if result.tier_times[index] is None:
                result.tier_times[index] = t

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
                        cost = level_up_cost(slot["baseCost"], level + 1, game, discount)
                        if best_cost is None or cost < best_cost:
                            best_cost, best_kind, best_id = cost, "level", slot_id
            if best_cost is None or cash < best_cost - 1e-9:
                break
            cash -= best_cost
            record_wait()
            if best_kind == "slot":
                owned[best_id] = floor if by_id[best_id]["type"] == "building" else 1
                result.slot_buys += 1
                frontier.remove(best_id)
                frontier.extend(children.get(best_id, []))
                if by_id[best_id]["type"] == "unlock":
                    result.unlock_beats.append((best_id, t))
                record_tier()
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
                record_tier()
            ips = income_per_second(owned, era, game, mults, milestones)

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
    if result.tier_times is not None:
        print(f"  city growth tiers : {tier_timeline_label(result, band)}")
    if check_band and band is not None:
        return band[0] <= result.seconds <= band[1]
    return True


def tier_timeline_label(result, band):
    """Each tier's first minute, as % of this run's completion and of the band
    midpoint (the era's target duration); INTERFACES M9 targets tier 1 on the
    first purchase, tier 3 by ~40 % and tier 5 by ~80 %."""
    target = (band[0] + band[1]) / 2 if band is not None else None
    bits = []
    for index, reached in enumerate(result.tier_times):
        if reached is None:
            bits.append(f"T{index + 1} never")
            continue
        run_pct = 100 * reached / result.seconds if result.seconds > 0 else 0
        target_note = f"/{100 * reached / target:.0f}%tgt" if target else ""
        bits.append(f"T{index + 1} {fmt_time(reached)} ({run_pct:.0f}%run{target_note})")
    return " | ".join(bits)


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


def shop_label(shop, game):
    if shop is None:
        return ""
    softcap = game["legacy"].get("softcap")
    perks = "auto policy" if shop.auto else shop.owned_label()
    return f"legacy shop softcap {softcap} ({perks}), "


def run_full(
    game, eras, strategy, check, paid=None, rebirth=0, laps=1, shop=None, city=None
):
    """laps > 1 rebirths between laps (era -> 1, rebirthCount += 1, legacy kept),
    mirroring the RequestRebirth handler. The band check judges lap 1 only: the
    spec bands describe a first playthrough. Lap headers are printed only when
    the run is not the plain single lap so the default output never moves.
    shop runs the purchase policy at every era entry, i.e. the only moments
    Legacy changes."""
    print(
        f"Era City Tycoon economy sim -- strategy={strategy}, "
        f"{paid_label(paid)}{shop_label(shop, game)}"
        "full playthrough, legacy carried across advances"
    )
    print()
    multi = laps > 1 or rebirth > 0
    legacy = 0
    rebirth_count = rebirth
    grand_seconds = 0
    all_in_band = True
    for lap in range(1, laps + 1):
        if multi:
            print(
                f"=== Lap {lap} (rebirthCount {rebirth_count}, legacy in {legacy}, "
                f"income mult x{legacy_mult(legacy, game):.2f}) ==="
            )
            print()
        total_seconds = 0
        for era in eras:
            if shop is not None:
                shop.buy_affordable(legacy, lap, era["eraIndex"])
            result = simulate_era(
                era,
                game,
                legacy,
                strategy,
                paid,
                False,
                rebirth_count,
                shop.config if shop else None,
                shop.state if shop else None,
                city,
            )
            result.legacy_in_mult = legacy_mult(legacy, game)
            in_band = print_era_result(result, check and lap == 1)
            if shop is not None:
                bought = [
                    f"{perk_id} {tier} ({cost})"
                    for entry_lap, entry_era, perk_id, tier, cost, _ in shop.log
                    if entry_lap == lap and entry_era == era["eraIndex"]
                ]
                print(
                    f"  legacy shop       : owns {shop.owned_label()} | "
                    f"spendable {shop.spendable(legacy)}"
                    + (f" | bought at entry: {', '.join(bought)}" if bought else "")
                )
            all_in_band = all_in_band and in_band
            print()
            legacy += result.legacy_gained
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
        print(
            f"SHOP: {len(shop.log)} purchases, {shop.state['spent']} Legacy spent, "
            f"spendable {shop.spendable(legacy)}, passive mult "
            f"x{legacy_mult(legacy, game):.2f}"
        )
    return all_in_band


def run_single(game, eras, era_index, legacy, strategy, paid=None, rebirth=0, city=None):
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
    result = simulate_era(era, game, legacy, strategy, paid, False, rebirth, city=city)
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
        "--perks",
        help="Legacy shop: 'auto' (buy by policy at every era entry) or a fixed set "
        "owned from the start at no cost, e.g. founders=2,builders=1",
    )
    parser.add_argument(
        "--softcap",
        type=int,
        help="override Game.json legacy.softcap for exploration (0 = no softcap)",
    )
    args = parser.parse_args()
    if args.rebirth < 0 or args.laps < 1:
        print("error: --rebirth must be >= 0 and --laps >= 1", file=sys.stderr)
        sys.exit(2)

    game = load_game_config()
    eras = load_eras()
    monetization = load_monetization_config()
    legacy_shop = load_legacy_shop_config()
    city = load_city_dressing_config()

    if args.softcap is not None:
        game["legacy"]["softcap"] = args.softcap if args.softcap > 0 else None

    shop = None
    if args.perks is not None:
        if args.era is not None or args.packs:
            print("error: --perks applies to full playthroughs only", file=sys.stderr)
            sys.exit(2)
        if not legacy_shop["perks"]:
            print("error: --perks needs src/shared/Config/LegacyShop.json", file=sys.stderr)
            sys.exit(2)
        shop = Shop(legacy_shop, parse_perks(args.perks, legacy_shop))

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
            or args.softcap is not None
        ):
            print("error: --check runs the default greedy playthrough only", file=sys.stderr)
            sys.exit(2)
        ok = run_full(game, eras, "greedy", True, None, 0, args.laps, None, city)
        print()
        print("CHECK: " + ("PASS -- all eras in band" if ok else "FAIL -- era out of band"))
        sys.exit(0 if ok else 1)

    if args.era is not None:
        ok = run_single(
            game, eras, args.era, args.legacy, args.strategy, paid, args.rebirth, city
        )
        sys.exit(0 if ok else 2)

    run_full(game, eras, args.strategy, False, paid, args.rebirth, args.laps, shop, city)
    sys.exit(0)


if __name__ == "__main__":
    main()
