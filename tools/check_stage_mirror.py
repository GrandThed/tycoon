#!/usr/bin/env python
"""Cross-check the rules of a run through a level against their Python mirrors, on the files that ship.

`src/shared/Combat.luau` and `src/combat/server/Services/StageFlow.luau` are pure, so the official
`luau` interpreter can run the very files the game runs. `tools/sim_combat.py` and
`tools/sim_range.py` mirror them by hand, and every balance band is measured on those mirrors: a
mirror that has drifted measures a game nobody plays. This tool gives both sides the same inputs
(every level file Catalog reads, its layout, Combat.json, Expeditions.json, ProvingGrounds.json)
and compares what they answer, value by value. L4 W1b (L4B-6) adds one hand-written level to the
shipped ones, FIELD_LEVEL on FIELD_LAYOUT: one gateless camp that locks, ten waves with bosses at 5
and 10, merging on the director's breather. It is what the Raider Arena resolved to before the arena
went, and the only level whose scripted runs reach Advance's merge and the director's breather:

  * `StageFlow.Resolve` against `sim_range.resolve_level`: every level file as a level;
  * `StageFlow.Validate` against `sim_range.level_problems`: the shipped levels are playable on
    both sides, and (the fix round's ruling 6) a level with a maxAlive of 0 or of 2.5, a burst of
    0, a camp with a targetWaveSeconds of 0 or none, a breatherSeconds or (the L1c fix round's M3)
    a gateSeconds under 0 or not a number, or no wave, and a
    Combat.json that lacks any one of the `levels` numbers a run reads, is refused on both;
  * `StageFlow.Validate`'s secrets lines (L2-13), each broken once in a copy of Forest Road's file or
    layout, refused alike.
  * `StageFlow.Validate`'s react, opens and shortcuts lines (L2-34, L2-36): a copy of Forest Road's
    layout given a test tunnel (a shortcut and a fire bramble that opens it) is accepted alike, and
    each line broken once in it is refused alike (the L2 W2 fix round's s-m3 adds a shortcut size
    of 0 or below). L2 W3 (L2-52, L2-58): the same copy given a test pool of deep water (an ice
    block that does not collide, with a landing) is accepted alike, and each of the ice and
    landing lines broken once in it (it collides, opens a shortcut, a landing on a fire block,
    a landing whose numbers are not finite or that is no point) is refused alike;
    the W2 case "a bramble that reacts to ice" became a refusal (it collides and opens a shortcut).
    The W3 fix round: a landing on plain deep water is accepted (Q3) and one on a block that
    collides refused; a second pool touching the first, or plain deep water overlapping it, is
    accepted, and a second pool overlapping it refused (s-s2), alike.
  * `StageFlow.Validate`'s L1b lines: the residents, the spots, which camps lock, the population
    gate and the three new `levels` numbers, each broken once in a copy of the shipped level, its
    layout or Combat.json, refused alike; and (the L1c fix round's data m2) every broken copy of
    both lists refused, so a rule removed from both sides at once is caught too;
  * `StageFlow.Plan` against `sim_range.plan_level`: every level at every difficulty, and at one
    that does not exist: each stage's numbers; every camp of the layout as a zone (its floor
    index, `locks`, name, checkpoint, residents, floor, `inner` and trigger rectangles, the
    trigger's ceiling (the L1c second fix round's F1: a walled camp's fence top), entry, exit and
    spawn points); every resident group; the population (L1b-11);
  * `StageFlow.Ceiling` against `sim_range.trigger_ceiling`: every shipped camp and the edges;
  * `LevelGeometry.FenceThickness` against `sim_range.fence_thickness` (the L2 W2 second fix round's
    m1): every shipped camp and the edges; every zone row carries its `fence` too;
  * `LevelGeometry.Pieces`' ice pieces against `sim_range.ice_cells`, box by box (the L2 W3 second fix
    round's Q6: the inset from the water's own faces): every shipped level layout, and Forest Road
    with other insets, none written, one under 0, two pools that touch and one too thin for it;
  * `StageFlow.GateNudge` against `sim_range.gate_nudge` on a grid over the fenced rectangle of
    every shipped locking camp (its edges, `inner`'s, the corners, half a stud either side) and
    in height;
  * `StageFlow.BurstPoint` and `BossPoint` against `sim_range.burst_point` and the boss's place;
  * `Combat.CampWave` against `sim_combat.camp_wave`: every wave of every camp of every level, at
    every difficulty, for parties of 1 to coop.maxParty;
  * `Combat.KillReward` against `sim_combat.kill_reward` at each of those specs' rewardMult: every
    priced kind (and one that is not) (until L4 W1b this was Combat.CampReward, which went with the
    C1 missions; the grid of prices that round at halves is KillReward's, below);
  * `Combat.BurstSeconds`, `Tempo`, `ShouldMerge` and `BreatherSeconds` against their mirrors, on
    grids built from those specs (the bursts each wave really has, its expected kills a second)
    and on the thresholds themselves;
  * `StageFlow.Advance` against `sim_range.LevelRun.advance`: for every level and difficulty,
    scripted runs fed tick for tick to both. On the road each open camp's checkpoint is walked
    up to (past its reach, over the band, by a downed root, then on its edge) and its residents
    are killed off (L1b-17), with the boss room's floor empty all along (it never clears as an
    open camp). Each camp that locks is approached from outside its fence (outside the fenced
    rectangle, above its band and under it, a walled camp's band over triggerHeight, on the fence
    line), waits its countdown,
    and plays its waves through: still spawning, the director asking to merge, bodies alive, a
    down on a field that is clear, the clear, the breather. One run of each is a clean clear,
    one ends with a down in a live camp, one with a down on the road while a group is awake
    (L1b-19), one at the run cap, one leaves the open camps standing, and one has nobody on his
    feet when a countdown ends (the camp is armed again). After every tick the actions (kind,
    stage, wave, time, count, zone, reason) and the state (stage, step, wave, firstWave, gateAt,
    breatherUntil, cleared, lastCleared, settled, reached, done, closedAt, fought, ended) of both
    sides are compared, and `StageFlow.FieldClear` (before the tick) and `StageFlow.SafePoint`
    (after it, with no floor busy, every floor busy, the first and the last) too;
  * `StageFlow.Skip` and `StageFlow.Force` against `LevelRun.skip` and `LevelRun.force` (the
    Studio levers; the simulator's own runs never use them): three more runs of each level and
    difficulty in which a stage skip, a boss skip or a forced wave comes at the first tick on
    the road, in a countdown, in a fight and in a breather, compared the same way;
  * on every tick of all those runs, `StageFlow.Directs` against `LevelRun.directs` (does the
    director keep its tempo in this step) and `StageFlow.StillClosing` against
    `LevelRun.still_closing` (is the close still judged again); and at each run's end
    `StageFlow.EarnsStar` against `LevelRun.earns_star`, for a fighter of the last clear, for
    one who was not, and for a stranger;
  * `CampBrain` (L1b) against `sim_range`'s cb_* mirror: `Posts` for every resident group of
    every level at every difficulty and for grid groups (a patrol of 3 and of 4 on a square loop,
    a fire of 1 to 7, guards); `Sees` on rings round a member (the sight's edge, the cone's edge,
    the height band's edges, distance 0); `InPlay` on the grown rectangle's edges, its rounded
    corners and a shooter's reach; `AtPost`, `Goal` (a patrol's legs stepping and wrapping, home
    restoring the leg), `Struck`, `Shows` and `Problems` (how many lines) on every state;
    `Engaged` on the hold's edges; and scripted `Step`
    timelines (rest, rise, fight, the leash held while striking, home, rest; held, released;
    woken by a hit; an empty group), the group compared after every call;
  * `Combat.KillReward` against `sim_combat.kill_reward` on the reward grid, and
    `Combat.SplitCarry` against `sim_combat.split_carry` over seeded sequences of kills, the
    payments and every carry compared after each.
  * L1b Wave 2 ("Wave 2 — the long road", L1b-W2-27): `HitShapes.CrowdRay`, `RayUpright` and
    `FlatToRect` against sim_range's hs_* on grids of kinds, origins, aims and widths; `SwingGate`
    on scripted sequences; `CampBrain.Dormant`, `Gap`, `JoinIn` (the shipped chains from rest and
    grid chains), `Rouse`, the tent rule (`NewTent`, `TentActive`, `TentDue`, `TentSent` on
    scripted timelines), the tent posture's `Posts` and `Shows`, and `Problems`' new lines;
    `Combat.ClearBonus`, `DeadFraction` and `WaveStock`; `StageFlow.StandsUp` on every tick of
    the scripted runs, `BossReserve`, `Plan`'s tents, stocks and population, the new `Validate`
    refusals. The Luau mutants that prove each comparison are in docs/BALANCE.md "L1b Wave 2".
  * L1b Wave 4 ("L1b Wave 4 — no waits, no walls", gate 10): `Region.Build`, `Problems`, `Distance`,
    `Inside`, `Clamp`, `Runway` and `Toward` against sim_range's rg_* on the shipped plateau and on
    hand-built grids (an L, the U-bend of RoadAB1-5, a single cell, a cycle, a gap, narrow doors, a
    bad cell); `CampBrain.Melee`, `Reachable`, `Struck` (every state, by a player and by a lever),
    `StandsDown`, `Forget`, `Goal` and `Shows` while stood down, the pace tent (`NewTent`,
    `TentClock`, `Ahead`, `TentActive`, `TentDue`, `TentSent` on a timeline) and scripted `Step`
    timelines on a region group (known by sight and by the hit memory, the leash held by
    `closing`, the stand-down, home's turn-back); `StageFlow.Plan`'s regions, residents-only
    stocks, approaches and paces, `Fielded`, Validate's Wave 4 refusals, the scripted runs (an
    open camp clears the tick its floor is empty, whatever its tent has not sent), and `Skip` runs
    through both approaches. The Luau mutants are in tools/crowd_harness/mirror_mutants.py.

  * L3 W1 ("L3 W1 contract", L3-27): the new pure `Armory` (LadderSize, Window, TierOf,
    Multiplier, DamageScale, WeaponHp, MaxHp, RangeHp, BandOf, NextTier, TierCost,
    Preview, UpgradeVerdict, LegacyRefund, the levers' SetTier (what it answers and writes) and
    BuiltBands, and whether Problems finds anything) against sim_combat's
    mirror of it, on the shipped Armory.json, one without a ladder and two edge copies (a window
    past the ladder, one narrowed under saved tiers, a malformed window, a band with no material,
    a missing cost, a multiplier of 0, a negative HP entry, a rangeHp of 0, a broken legacy entry),
    over grids of tiers, saved profiles, owned and gate flags and built levels; `Problems` on
    copies broken one rule at a time. `StageFlow.FirstClear` against `sim_range.first_clear` on
    every level at every difficulty and on Forest Road given each first-clear shape, and
    Validate's firstClear lines refused alike (L3-17); every Validate is handed the weapons and the
    starters on both sides, so a first clear's family is checked as a family, not an id only.
    Its fix round adds `StarHeld` (a band top opened by the Hard star or a `starAlso` one: profiles
    holding only a Brutal star, a config without `starAlso` and one whose `starAlso` is a word), and
    breaks that only one Problems rule can name (bandSize 4.5, a band removed, a negative ranged HP
    entry, a `starAlso` that is no list of names). Its second fix round (F4) names the Armory
    functions left without a mirror on purpose, StrikeTier and HeldFamily, with why
    (ARMORY_UNMIRRORED): listed in a note, and the run fails when one is no longer in the Luau. L4 W3
    deleted GearPower, SavedPower and HeldTiers (the Gear Power readout, their last reader) and their rows.

  * L4 W3 (L4W3-7): `Combat.EraCashMult` against `sim_combat.era_cash_mult` (the shipped rewards and
    broken copies: no block, no list, an empty one, a string, an object, a short list, entries under 1,
    a string entry, NaN and infinite entries, fractional ones; at every era, past the list, 0, below,
    fractional and not finite), and the one cash choke point `Combat.CombatCashMult` against
    `sim_combat.combat_cash_mult` (two laps' legacies and one past the softcap, Founder's Blessing off
    and at its top tier, every era, the shipped rewards and none). The mutants are in
    tools/crowd_harness/mirror_mutants.py.

  * L4 W1b fix round (F6, review 3-m3): `Combat.MentorBonus` against `sim_combat.mentor_bonus` on every
    call `sim_combat.mentor_pay` (WaveService.payMentors' mirror) makes on assertions 12 and 13's boss
    kills (`sim_combat.mentor_fixtures`) and on the edges of hostRate x mentorRatio (a rate exactly on
    it, EDGE either side, none, 0) for three host rates; then each of those kills paid by mentor_pay
    on the Luau's answers against its own. payMentors' deciding lines are run_harness.py's L4B_LINES
    pins; the `<` made `<=` mutant is in tools/crowd_harness/mirror_mutants.py.

It fails when either side changes alone. A function of the Luau that the simulators do not
mirror (the rescue, the skips, the map) is listed, not compared: tools/crowd_harness tests those.

The Luau sources are bundled by tools/crowd_harness/run_harness.py's own functions (`to_luau`,
`wrap`, `sources`), imported and never run: nothing here calls its `main`. The bundle is written
to a temporary folder, never to the harness's own bundle.luau, so this tool may run beside it.

    py tools/check_stage_mirror.py                     # every comparison; exit 1 on a difference
    py tools/check_stage_mirror.py --luau <luau.exe>   # another interpreter
    py tools/check_stage_mirror.py --module StageFlow=<file>   # run another copy of a module
    py tools/check_stage_mirror.py --keep <dir>        # leave the bundle and the Luau's answers there
    py tools/check_stage_mirror.py --show 20           # differences listed per kind (default 6)

The interpreter is tools/bin/luau.exe (tools/check_mirror.py fetches it). A git worktree has
none of its own, so the main checkout's is used when this one's is missing.
"""

from __future__ import annotations

import argparse
import ast
import copy
import importlib.util
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import sim_combat as sc  # noqa: E402
import sim_range as sr  # noqa: E402

HARNESS = ROOT / "tools" / "crowd_harness"
DRIVER = HARNESS / "stage_mirror.luau"
# Unlocks: StageFlow reads the family id cap from it (the L2 W1 fix round's s2). WorldReact (L2 W3):
# LevelGeometry cuts deep water into ice cells with it, and it reads Unlocks. MapRules (the L4 W3 fix
# round 2's G3): StageFlow.Notes keeps what MapRules.Note keeps.
MODULES = ("Economy", "Armory", "HitShapes", "SwingGate", "Region", "Combat", "Unlocks", "WorldReact",
           "LevelGeometry", "CampBrain", "MapRules", "StageFlow")  # in load order
# L4B-6: the hand-written field, a copy of tools/crowd_harness's L1.fieldLevel on L1W.field (the old
# Raider Arena as it resolved, the C1 Village mission's crowd block on the Village arena's layout).
# No shipped level merges or takes the director's breather since the arena went; this one does, so
# LevelRun.advance's merge and breather stay held to StageFlow.Advance.
def _field_wave(*pairs):
    return {"groups": [{"kind": kind, "count": count} for kind, count in pairs]}


FIELD_LEVEL = {
    "version": 1, "id": "field", "name": "Field", "layout": "Field", "material": "Timber", "targetMinutes": 12,
    "difficulties": {"normal": {"hpScale": 1.5, "damageScale": 1.12, "plateScale": 1, "countMult": 1, "rewardMult": 1,
                                "recommendedTier": 2}},
    "crowd": {"regenShare": 0.077, "maxAlive": 60, "burst": 10, "burstSpacing": 3.5,
              "rewards": {"fodder": {"cash": 60, "materials": 0}, "slinger": {"cash": 300, "materials": 1},
                          "brute": {"cash": 1200, "materials": 4}, "marksman": {"cash": 350, "materials": 1},
                          "lobber": {"cash": 350, "materials": 1}, "armoured": {"cash": 1500, "materials": 5},
                          "colossus": {"cash": 18000, "materials": 30}, "warlord": {"cash": 30000, "materials": 50}}},
    "stages": [{"kind": "camp", "name": "Field", "zone": "field", "targetWaveSeconds": 45, "merge": True, "waves": [
        _field_wave(("fodder", 48)),
        _field_wave(("fodder", 72)),
        _field_wave(("fodder", 24), ("slinger", 3), ("fodder", 24), ("slinger", 3), ("fodder", 24)),
        _field_wave(("fodder", 24), ("brute", 2), ("slinger", 3), ("fodder", 24), ("brute", 2), ("slinger", 3),
                    ("fodder", 24)),
        {"groups": [], "boss": {"kind": "colossus", "at": [0, 40], "valor": 10}},
        _field_wave(("fodder", 24), ("marksman", 2), ("lobber", 2), ("fodder", 24), ("slinger", 3), ("brute", 2),
                    ("fodder", 24), ("marksman", 2), ("lobber", 2)),
        _field_wave(("fodder", 36), ("marksman", 3), ("lobber", 3), ("slinger", 3), ("fodder", 36), ("brute", 3),
                    ("fodder", 24)),
        _field_wave(("fodder", 24), ("armoured", 3), ("marksman", 2), ("fodder", 24), ("lobber", 3), ("slinger", 3),
                    ("armoured", 3), ("fodder", 24)),
        _field_wave(("fodder", 36), ("armoured", 3), ("marksman", 3), ("lobber", 3), ("fodder", 36), ("brute", 3),
                    ("armoured", 3), ("slinger", 4), ("fodder", 36)),
        {"groups": [], "boss": {"kind": "warlord", "at": [0, 28], "valor": 25}},
    ]}],
}
FIELD_LAYOUT = {
    "version": 1, "start": {"x": 0, "y": 0, "z": 0}, "killY": -8, "barrier": {"height": 80, "thickness": 8},
    "camps": [{
        "id": "field", "x": 0, "y": 0, "z": 0, "sx": 110, "sz": 110,
        "floor": {"material": "Grass", "color": [106, 127, 63]},
        "fence": {"height": 4, "material": "WoodPlanks", "color": [112, 84, 56]},
        "gates": [], "entry": {"x": -12, "z": -12}, "exit": {"x": 0, "z": 0},
        "spawns": [{"x": 0, "z": -46}, {"x": 32.5, "z": -32.5}, {"x": 46, "z": 0}, {"x": 32.5, "z": 32.5},
                   {"x": 0, "z": 46}, {"x": -32.5, "z": 32.5}, {"x": -46, "z": 0}, {"x": -32.5, "z": -32.5}],
        "obstacles": [
            {"x": 9.2, "z": 22.3, "sx": 5, "sy": 3.5, "sz": 5, "material": "Slate", "color": [110, 110, 105]},
            {"x": 22.3, "z": -9.2, "sx": 6, "sy": 4, "sz": 5, "material": "Slate", "color": [102, 104, 100]},
            {"x": -9.2, "z": -22.3, "sx": 5, "sy": 3.5, "sz": 6, "material": "Slate", "color": [110, 110, 105]},
            {"x": -22.3, "z": 9.2, "sx": 5, "sy": 3, "sz": 5, "material": "Slate", "color": [102, 104, 100]},
            {"x": 12.6, "z": -30.4, "sx": 12, "sy": 2, "sz": 3, "material": "Wood", "color": [96, 70, 45]},
            {"x": -30.4, "z": -12.6, "sx": 3, "sy": 2, "sz": 12, "material": "Wood", "color": [86, 62, 40]},
            {"x": -12.6, "z": 30.4, "sx": 12, "sy": 2, "sz": 3, "material": "Wood", "color": [96, 70, 45]},
            {"x": 30.4, "z": 12.6, "sx": 3, "sy": 2, "sz": 12, "material": "Wood", "color": [86, 62, 40]}],
        "locks": True}],
    "blocks": [], "secrets": [], "route": []}

# The functions each comparison needs; one that is missing fails the run by name.
NEEDED = {"Combat": ("CampWave", "KillReward", "SplitCarry", "BurstSeconds", "Tempo", "ShouldMerge",
                     "BreatherSeconds", "ClearBonus", "DeadFraction", "WaveStock", "MentorBonus", "EraCashMult",
                     "CombatCashMult"),
          "StageFlow": ("Resolve", "Validate", "Plan", "Begin", "Advance", "Skip", "Force", "BurstPoint", "BossPoint", "Ceiling",
                        "GateNudge",
                        "Directs", "StillClosing", "EarnsStar", "FieldClear", "SafePoint", "StandsUp", "BossReserve",
                        "TentOwesRouse", "Fielded", "Threatening"),
          "CampBrain": ("Problems", "NewGroup", "Posts", "Sees", "InPlay", "AtPost", "Step", "Release", "Evades",
                        "Struck", "Goal", "Shows", "Engaged", "Dormant", "Gap", "JoinIn", "Rouse", "TentRouse", "NewTent",
                        "TentActive", "TentDue", "TentSent", "Melee", "Reachable", "StandsDown", "Forget", "TentClock",
                        "Ahead"),
          "Region": ("Build", "Problems", "Distance", "Inside", "Clamp", "Runway", "Toward"),
          "HitShapes": ("RayUpright", "CrowdRay", "FlatToRect", "Ray"),
          "SwingGate": ("New", "IsAir", "Allows", "Took", "Landed")}
# L3 W1: each Armory function compared, and its sim_combat mirror. A mirror that is missing fails the
# run by name, as a Luau function that is missing does.
ARMORY_MIRRORS = {"LadderSize": "ladder_size", "Window": "window", "TierOf": "tier_of",
                  "Multiplier": "multiplier", "DamageScale": "damage_scale", "WeaponHp": "weapon_hp",
                  "MaxHp": "max_hp", "RangeHp": "range_hp", "BandOf": "band_of",
                  "NextTier": "next_tier", "TierCost": "tier_cost", "Preview": "preview",
                  "UpgradeVerdict": "upgrade_verdict", "LegacyRefund": "legacy_refund", "Problems": "problems",
                  "SetTier": "set_tier", "BuiltBands": "built_bands", "StarHeld": "star_held"}
NEEDED["Armory"] = tuple(ARMORY_MIRRORS)
NEEDED["StageFlow"] += ("FirstClear",)
# The L4 W3 fix round's F6: the notes a level keeps and drops (Validate names none).
NEEDED["StageFlow"] += ("Notes",)
# The L3 W1 fix round 2's F4: the Armory functions deliberately left without a mirror, and why (the
# simulators need only their parts; tools/crowd_harness tests_l3.luau tests each). Listed in a note,
# never compared; one that is no longer in the Luau fails the run, so the list cannot go stale.
ARMORY_UNMIRRORED = {
    "StrikeTier": "TierOf (compared) under a Studio session override no simulator plays",
    "HeldFamily": "the saved loadout's slot rule; every simulated course names the pair it holds (sim_range.held_pair)",
}
# The grids the Armory is asked on (L3 W1).
ARMORY_TIERS = (-1, 0, *range(1, 22), 2.5)
ARMORY_ASCENSION = (0, 1, 2)
ARMORY_BASES = (0, 5, 24, 45, 55.5)
ARMORY_BUILT = ([], ["forestRoad"], ["forestRoad", "castle"], ["forestRoad", "castle", "underworld", "planet", "dream"])
ARMORY_GEAR = ((0, 0), (1, 0), (2, 1), (3, 3), (4, 2), (12, 12), (13, 0), (-1, 2), (2.5, 1))
# Saved profiles (the slice the tier rules read): nothing, wallets either side of each price, tiers
# inside, below and above windows, a band top with and without the Hard star, stars that are not it.
ARMORY_COMBATS = (
    {"materials": {}},
    {"materials": {"Timber": 99}, "tiers": {}},
    {"materials": {"Timber": 100}},
    {"materials": {"Timber": 250}, "tiers": {"broadsword": 2, "flamethrower": 2}},
    {"materials": {"Timber": 500}, "tiers": {"broadsword": 3, "longbow": 3}},
    {"materials": {"Timber": 500}, "tiers": {"broadsword": 3, "longbow": 3}, "stars": {"forestRoad": {"hard": True}}},
    {"materials": {"Timber": 499}, "tiers": {"broadsword": 3}, "stars": {"forestRoad": {"hard": True}}},
    {"materials": {"Timber": 10 ** 6, "Iron": 10 ** 6, "Ember": 10 ** 6, "Glowstone": 10 ** 6, "Crystal": 10 ** 6},
     "tiers": {"broadsword": 4, "longbow": 7, "warhammer": 15, "spear": 12, "greataxe": 8},
     "stars": {"forestRoad": {"hard": True, "normal": True}, "castle": {"hard": True}}},
    {"materials": {"Timber": 1000}, "tiers": {"broadsword": 9, "longbow": 25, "warhammer": 1, "greataxe": 4.5,
                                              "rifle": "x"}},
    {"materials": {"Timber": 1000}, "tiers": {"broadsword": 3}, "stars": {"forestRoad": {"normal": True}}},
    {"materials": {"Timber": 1000}, "tiers": {"broadsword": 3}, "stars": {"forestRoad": {"hard": False}}},
    # The fix round's R1: a Brutal star alone, at a band top with the price held and one short.
    {"materials": {"Timber": 500}, "tiers": {"broadsword": 3, "longbow": 3}, "stars": {"forestRoad": {"brutal": True}}},
    {"materials": {"Timber": 499, "Iron": 10 ** 6}, "tiers": {"broadsword": 3, "longbow": 7},
     "stars": {"forestRoad": {"brutal": True, "normal": True}, "castle": {"brutal": True}}},
)
# Problems on copies broken one rule at a time: (label, change). Both sides must call each unsound.
ARMORY_BREAKS = (
    ("a damage entry that does not rise", lambda c: c["ladder"]["damage"].__setitem__(4, c["ladder"]["damage"][3])),
    ("a melee HP list one short", lambda c: c["ladder"]["hp"]["melee"].pop()),
    ("ranged HP above melee at one tier",  # 85 at T3 and T4: the list still rises
     lambda c: c["ladder"]["hp"]["ranged"].__setitem__(slice(2, 4), [85, 85])),
    ("bandSize 3", lambda c: c["ladder"].__setitem__("bandSize", 3)),
    ("a band with no material", lambda c: c["ladder"]["bands"][1].__setitem__("material", "")),
    ("three costs for four positions", lambda c: c["ladder"]["costs"].pop()),
    ("a rangeHp of 0", lambda c: c["ladder"].__setitem__("rangeHp", 0)),
    ("a family without a window", lambda c: c["windows"].pop("spear")),
    ("a window whose start is above its top", lambda c: c["windows"].__setitem__("rifle", {"start": 18, "top": 11})),
    ("a window past the ladder", lambda c: c["windows"].__setitem__("rifle", {"start": 11, "top": 25})),
    ("a window naming no family", lambda c: c["windows"].__setitem__("nope", {"start": 1, "top": 2})),
    ("no legacy list", lambda c: c.pop("legacy")),
    ("a legacy entry with no material", lambda c: c["legacy"]["gearCosts"][3].__setitem__("material", "")),
    ("no starDifficulty", lambda c: c["ladder"].__setitem__("starDifficulty", "")),
    ("no ladder", lambda c: c.pop("ladder")),
    # The fix round's R6: breaks only one rule can name (bandSize not whole skips the costs and cover
    # rules; four bands of four; melee stays above a negative ranged entry and the list still rises).
    ("bandSize 4.5", lambda c: c["ladder"].__setitem__("bandSize", 4.5)),
    ("one band removed", lambda c: c["ladder"]["bands"].pop()),
    ("a negative ranged HP entry", lambda c: c["ladder"]["hp"]["ranged"].__setitem__(0, -1)),
    # R1: starAlso is a list of difficulty names, or absent.
    ("a starAlso that is a word", lambda c: c["ladder"].__setitem__("starAlso", "brutal")),
    ("a starAlso with an empty name", lambda c: c["ladder"].__setitem__("starAlso", ["brutal", ""])),
)
# L3-17: the first-clear shapes Forest Road is given at Hard (FirstClear and Validate alike).
FIRST_CLEARS = (
    ("the Warhammer", {"family": "warhammer"}),
    ("25 Valor", {"valor": 25}),
    ("a family and Valor", {"family": "greataxe", "valor": 3}),
    ("a Valor of 0", {"valor": 0}),
    ("neither", {}),
    ("an empty family and a Valor of 0", {"family": "", "valor": 0}),
    ("a family that is a number and a Valor of 2.5", {"family": 5, "valor": 2.5}),
    ("a string", "warhammer"),
)
# L1b Wave 2's grids.
RAY_ORIGINS = ((0.0, 5.0, 30.0), (3.0, 1.0, -25.0), (0.0, 22.0, 0.5), (-18.0, 9.0, 4.0))
RAY_WIDTHS = ((0.0, 0.0), (0.6, 0.6), (0.2, 1.5))  # (width, pad)
RAY_SEED = 2214
RAY_RANDOM = 160
SEAT_GRID = (-0.25, 0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0, 1.4)  # L4W2-11: HitShapes.SeatDrop's seats, two outside 0..1 (it clamps)
DORMANT_EDGES = (-1e-6, 0.0, 1e-6)
BONUS_SHARES = (0.0, 0.1, 0.5, 1.0)
TOLERANCE = 1e-9  # relative; the two sides do the same arithmetic on the same doubles
TEMPO_GRID = (-1.0, 0.0, 0.5, 0.7, 1.0, 1.25, 1.6, 2.0)
KILL_GRID = (0, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89)
EDGE = 1e-7  # either side of a threshold
BURST_SIZES = (1, 2, 3, 9, 16)
# Prices and reward multipliers whose products end in halves and thirds: (cash, materials, mult).
REWARD_GRID = tuple((cash, materials, mult) for cash in (1, 3, 5, 7, 100) for materials in (0, 1, 3)
                    for mult in (0.5, 1.5, 2.5, 1 / 3, 4))
# The L4 W1b fix round's F6: the host rates the mentor edges are asked at (each times mentorRatio is
# a whole number, so "exactly at the threshold" is exact on both sides).
MENTOR_HOSTS = (0.0, 8000.0, sc.MENTOR_HOST_RATE)


def mentor_cases(combat):
    """Combat.MentorBonus's cases: (host rate, party rates). First every call sim_combat.mentor_pay
    makes on assertions 12 and 13's boss kills (sim_combat.mentor_fixtures, recorded through its
    `bonus_of`), then the edges: a party of none, a rate exactly at hostRate x mentorRatio, EDGE
    either side of it, 0, a mix. Returns the cases and, per fixture, its members and tally."""
    calls = []

    def record(cfg, host, rates):
        calls.append((host, list(rates)))
        return sc.mentor_bonus(cfg, host, rates)

    fixtures = sc.mentor_fixtures(combat)
    for members, tally in fixtures.values():
        sc.mentor_pay(combat, members, tally, bonus_of=record)
    ratio = combat["coop"]["mentorRatio"]
    for host in MENTOR_HOSTS:
        edge = host * ratio
        calls += [(host, []), (host, [edge]), (host, [edge - EDGE]), (host, [edge + EDGE]), (host, [0.0]),
                  (host, [edge - EDGE, edge, edge + EDGE, 0.0, host, 2 * host])]
    unique = []
    for case in calls:
        if case not in unique:
            unique.append(case)
    return unique, fixtures


# L4 W3 (L4W3-7): run cash x the member's city era. NaN and the infinities cannot travel in DATA's Luau
# literal, so a case names them by these strings and stage_mirror.luau turns them back into numbers.
SPECIAL_NUMBERS = {"__nan": math.nan, "__inf": math.inf, "__ninf": -math.inf}
ERA_CASH_REWARDS = (
    ("no rewards block", None), ("no list", {}), ("an empty list", {"eraCashMult": []}),
    ("a list that is a string", {"eraCashMult": "670"}), ("a list that is an object", {"eraCashMult": {"a": 670}}),
    ("two entries", {"eraCashMult": [1, 670]}),
    ("entries under 1 and a string", {"eraCashMult": [1, 0.5, "34000", 0.999]}),
    ("entries NaN and infinite", {"eraCashMult": ["__nan", "__inf", "__ninf", 1400000]}),
    ("entries 0 and negative", {"eraCashMult": [0, -5, 1, 2]}),
    ("fractional entries", {"eraCashMult": [1.5, 670.25, 34000, 1400000]}),
)
ERA_CASH_ERAS = (1, 2, 3, 4, 5, 9, 0, -1, 1.5, 3.99, "__nan", "__inf", "__ninf")
ERA_CASH_LEGACY = (0, 78, 261, 529, 1680, 9000)


def _special(value):
    if isinstance(value, dict):
        return {key: _special(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_special(item) for item in value]
    return SPECIAL_NUMBERS.get(value, value) if isinstance(value, str) else value


def era_cash_cases(data, expected, combat, game, shop):
    """Combat.EraCashMult against sim_combat.era_cash_mult on the shipped rewards and on broken
    copies, at every era of the game, past the list, under 1, fractional and not finite; then the
    one cash choke point, Combat.CombatCashMult, against sim_combat.combat_cash_mult: the first two
    laps' legacies and one past the softcap, with and without Founder's Blessing, at every era, on
    the shipped rewards and with none."""
    rewards = [("as shipped", combat.get("rewards"))] + list(ERA_CASH_REWARDS)
    for label, block in rewards:
        for era in ERA_CASH_ERAS:
            case = f"eraCash.{len(data['eraCashCases']) + 1}"
            entry = {"id": case, "era": era}
            if block is not None:
                entry["rewards"] = block
            data["eraCashCases"].append(entry)
            expected[case] = ("Combat.EraCashMult (L4W3-7)", f"{label}, era {era}",
                              sc.era_cash_mult(_special(block), _special(era)))
    founders = next((perk for perk in shop.get("perks") or [] if perk.get("id") == "founders"), None)
    shops = [("no perk", sc.se.empty_shop_state())]
    if founders is not None:
        shops.append(("Founder's top tier", {"spent": 0, "perks": {"founders": len(founders["tiers"])}}))
    for legacy in ERA_CASH_LEGACY:
        for shop_label, shop_state in shops:
            for label, block in (("as shipped", combat.get("rewards")), ("no rewards block", None)):
                for era in (1, 2, 3, 4, 7):
                    case = f"eraCash.{len(data['eraCashCases']) + 1}"
                    state = {"legacy": legacy, "legacyShop": shop_state}
                    entry = {"id": case, "era": era, "state": state}
                    if block is not None:
                        entry["rewards"] = block
                    data["eraCashCases"].append(entry)
                    expected[case] = ("Combat.CombatCashMult (L4W3-7: Legacy x Founder's x the era)",
                                      f"legacy {legacy}, {shop_label}, {label}, era {era}",
                                      sc.combat_cash_mult(state, game, shop, block, era))


STATE_FIELDS = ("stage", "step", "wave", "firstWave", "gateAt", "breatherUntil", "cleared", "lastCleared", "settled",
                "approached",
                "reached", "done", "closedAt", "fought", "ended")
ACTION_FIELDS = ("kind", "stage", "wave", "at", "merged", "count", "zone", "reason", "skipped")
VARIANTS = ("clear", "down", "roadDown", "cap", "standing", "reset", "skipStage", "skipBoss", "force", "approach",
            "approachPast")
APPROACH_PRESSES = 4  # the `approach` run presses N this often on the road (each open camp, then the countdown)
# L1b Wave 4's Region grids.
REGION_RADII = (0.0, 1.3, 2.2, 9.0)  # 9: wider than a 16-stud road cell
REGION_STEP = 6.0  # studs between two grid points round a region
REGION_HEADINGS = 16
REGION_SEED = 4417
REGION_TOWARD = 240  # seeded (from, goal) pairs per region
MIN_DOOR = 4.9
# CampBrain's grids (L1b).
CB_ANGLES = tuple(range(0, 360, 10))
CB_SPLIT_SEED = 1407
CB_SPLIT_CALLS = 160
STAR_USERS = (1, 2, 9)  # whom EarnsStar is asked about: the script's two fighters, and a stranger
BREATHER_INPUT = 7.25  # the director's breather a tick is handed (any number: both sides get the same)
# Ruling 6 of the fix round: each of these makes a level that must be refused on both sides.
REFUSALS = (
    ("crowd.maxAlive 0", lambda file: file["crowd"].__setitem__("maxAlive", 0)),
    ("crowd.maxAlive 2.5", lambda file: file["crowd"].__setitem__("maxAlive", 2.5)),
    ("a camp's maxAlive 0", lambda file: first_camp(file).__setitem__("maxAlive", 0)),
    ("crowd.burst 0", lambda file: file["crowd"].__setitem__("burst", 0)),
    ("a camp's targetWaveSeconds 0", lambda file: first_camp(file).__setitem__("targetWaveSeconds", 0)),
    ("a camp with no targetWaveSeconds", lambda file: first_camp(file).pop("targetWaveSeconds", None)),
    ("a camp with no wave", lambda file: first_camp(file).__setitem__("waves", [])),
    ("a camp's breatherSeconds -1", lambda file: first_camp(file).__setitem__("breatherSeconds", -1)),
    # The L1c fix round's M3: a camp's own countdown.
    ("a camp's gateSeconds -1", lambda file: first_camp(file).__setitem__("gateSeconds", -1)),
    ("a camp's gateSeconds \"3\"", lambda file: first_camp(file).__setitem__("gateSeconds", "3")),
)


def first_camp(file):
    return next(stage for stage in file["stages"] if stage["kind"] == "camp")


def layout_camp(layout, cid):
    return next(camp for camp in layout["camps"] if camp["id"] == cid)


def level_camp(file, cid):
    return next(camp for camp in file["camps"] if camp["id"] == cid)


def boss_room_full(file):
    """L1c, as its fix round has it (data m2): the walled boss room's stage maxAlive lowered to the
    residents camp C holds on Normal, the least that Validate's "not fewer than its stage's
    maxAlive" refuses (Hard and Brutal hold more). The residents are left alone, so that rule is the
    only one the copy breaks: adding bodies to a guard spot also broke its posts, and both sides
    refused for that reason with the maxAlive rule removed from both."""
    stage = next(stage for stage in file["stages"] if stage.get("zone") == "C")
    camp = level_camp(file, "C")
    stage["maxAlive"] = sum(unit["count"] for group in camp["residents"] for unit in group["units"]
                            if "minDifficulty" not in unit)


def ring_only_normal_breaks(file, layout):
    """The fix round's B-2: A's tent fields 2 fodder on Normal (posts north and south of the
    marker) and a third from Hard (north, and 120 degrees either side), and the marker sits 10
    studs inside the floor's south edge: Normal's south post hangs over it, Hard's two stand 5
    inside. Validate judging the highest difficulty only would pass it."""
    level_camp(file, "A")["tent"]["units"] = [{"kind": "fodder", "count": 2},
                                              {"kind": "fodder", "count": 1, "minDifficulty": "hard"}]
    camp = layout_camp(layout, "A")
    camp["tent"]["z"] = camp["z"] + camp["sz"] / 2 - camp["tent"]["radius"] + 0.5


# L1b: Validate's new lines, each broken once. (label, change(file, layout, rules)) on copies of
# the shipped level file, its raw layout and Combat.json `levels`; refused alike on both sides.
# Only a level with residents (`camps`) gets them.
L1B_REFUSALS = (
    ("a resident of an unknown kind", lambda f, l, r: level_camp(f, "A")["residents"][0]["units"].append(
        {"kind": "nobody", "count": 1})),
    ("a resident count of 0", lambda f, l, r: level_camp(f, "A")["residents"][0]["units"][0].__setitem__("count", 0)),
    ("a resident count of 2.5", lambda f, l, r: level_camp(f, "A")["residents"][0]["units"][0].__setitem__("count", 2.5)),
    ("a minDifficulty that is no difficulty", lambda f, l, r: level_camp(f, "A")["residents"][0]["units"][0]
     .__setitem__("minDifficulty", "nope")),
    ("a camps entry for a camp the layout lacks", lambda f, l, r: level_camp(f, "A").__setitem__("id", "Z")),
    ("two camps entries for one camp", lambda f, l, r: level_camp(f, "B").__setitem__("id", "A")),
    ("a camps entry with no name", lambda f, l, r: level_camp(f, "A").__setitem__("name", "")),
    ("a resident group on a spot its camp lacks", lambda f, l, r: level_camp(f, "A")["residents"][0]
     .__setitem__("spot", "nowhere")),
    ("a resident group with no units", lambda f, l, r: level_camp(f, "A")["residents"][0].__setitem__("units", [])),
    ("the boss room's residents at its maxAlive", lambda f, l, r: boss_room_full(f)),
    ("a population over crowd.maxAlive", lambda f, l, r: level_camp(f, "B")["residents"][0]["units"].append(
        {"kind": "fodder", "count": 200})),
    ("a negative clearBonus share", lambda f, l, r: f["crowd"].__setitem__("clearBonus", {"share": -0.1})),
    ("a clearBonus share over 1", lambda f, l, r: f["crowd"].__setitem__("clearBonus", {"share": 1.5})),
    ("a clearBonus with no share", lambda f, l, r: f["crowd"].__setitem__("clearBonus", {"cash": 0, "materials": 0})),
    ("a tent with no every", lambda f, l, r: level_camp(f, "A")["tent"].pop("every")),
    ("a tent every of 0", lambda f, l, r: level_camp(f, "A")["tent"].__setitem__("every", 0)),
    ("a tent with no units", lambda f, l, r: level_camp(f, "A")["tent"].__setitem__("units", [])),
    ("a tent unit of an unknown kind", lambda f, l, r: level_camp(f, "A")["tent"]["units"].append(
        {"kind": "nobody", "count": 1})),
    ("a tent unit count of 0", lambda f, l, r: level_camp(f, "A")["tent"]["units"][0].__setitem__("count", 0)),
    ("a tent unit minDifficulty that is none", lambda f, l, r: level_camp(f, "A")["tent"]["units"][0]
     .__setitem__("minDifficulty", "nope")),
    ("a tent stock on the boss room", lambda f, l, r: level_camp(f, "C").__setitem__(
        "tent", copy.deepcopy(level_camp(f, "A")["tent"]))),
    ("a tent stock whose camp has no tent block", lambda f, l, r: layout_camp(l, "A").pop("tent")),
    ("a tent block with no radius", lambda f, l, r: layout_camp(l, "A")["tent"].pop("radius")),
    ("a tent block of size 0", lambda f, l, r: layout_camp(l, "A")["tent"].__setitem__("sx", 0)),
    ("a tent radius of 0", lambda f, l, r: layout_camp(l, "A")["tent"].__setitem__("radius", 0)),
    ("a tent's centre off its floor", lambda f, l, r: layout_camp(l, "A")["tent"].__setitem__(
        "x", layout_camp(l, "A")["x"] + layout_camp(l, "A")["sx"] / 2 + 1)),
    ("a tent ring post off its floor", lambda f, l, r: layout_camp(l, "A")["tent"].__setitem__("radius", 200)),
    ("a tent ring post only Normal pushes off its floor", lambda f, l, r: ring_only_normal_breaks(f, l)),
    ("a tent stock on a camp with no residents", lambda f, l, r: level_camp(f, "A").__setitem__("residents", [])),
    ("a population one body over on Hard", lambda f, l, r: level_camp(f, "A")["tent"]["units"].append(
        {"kind": "fodder", "count": 4})),
    ("a stage naming an open camp", lambda f, l, r: layout_camp(l, "C").pop("locks", None)),
    ("a locking camp no stage names", lambda f, l, r: layout_camp(l, "A").__setitem__("locks", True)),
    ("a spot with no id", lambda f, l, r: layout_camp(l, "A")["spots"][0].pop("id")),
    ("a spot id used twice", lambda f, l, r: layout_camp(l, "A")["spots"][1].__setitem__(
        "id", layout_camp(l, "A")["spots"][0]["id"])),
    ("a posture that is none", lambda f, l, r: layout_camp(l, "A")["spots"][0].__setitem__("posture", "sleep")),
    ("a spot with no points", lambda f, l, r: layout_camp(l, "A")["spots"][0].__setitem__("points", [])),
    ("a guard spot with no facing", lambda f, l, r: next(s for s in layout_camp(l, "A")["spots"]
                                                         if s["posture"] == "guard").pop("facing")),
    ("a guard spot a point short", lambda f, l, r: next(s for s in layout_camp(l, "A")["spots"]
                                                        if s["posture"] == "guard")["points"].__setitem__(slice(1, None), [])),
    ("a patrol of one point", lambda f, l, r: next(s for s in layout_camp(l, "B")["spots"]
                                                   if s["posture"] == "patrol")["points"].__setitem__(slice(1, None), [])),
    ("a fire of two points", lambda f, l, r: next(s for s in layout_camp(l, "A")["spots"]
                                                  if s["posture"] == "fire")["points"].append({"x": 0, "z": 0})),
    ("a fire with a radius of 0", lambda f, l, r: next(s for s in layout_camp(l, "A")["spots"]
                                                       if s["posture"] == "fire").__setitem__("radius", 0)),
    ("a post off its floor", lambda f, l, r: next(s for s in layout_camp(l, "A")["spots"]
                                                  if s["posture"] == "guard")["points"][0].__setitem__(
        "x", layout_camp(l, "A")["x"] + layout_camp(l, "A")["sx"] / 2 - 0.5)),
    ("levels.checkpointReach 0", lambda f, l, r: r.__setitem__("checkpointReach", 0)),
    ("levels.walletSendSeconds 0", lambda f, l, r: r.__setitem__("walletSendSeconds", 0)),
    # L1b Wave 4 (L1b-W4-14 to -16, -28, -31): each line broken once, on a level that has them.
    ("a tent with no pace", lambda f, l, r: level_camp(f, "A")["tent"].pop("pace")),
    ("a tent pace.seconds of 0", lambda f, l, r: level_camp(f, "A")["tent"]["pace"].__setitem__("seconds", 0)),
    ("a tent pace.lead of 1.5", lambda f, l, r: level_camp(f, "B")["tent"]["pace"].__setitem__("lead", 1.5)),
    ("an approach on the boss room", lambda f, l, r: layout_camp(l, "C").__setitem__("approach", {"x": 240, "y": 8, "z": -44})),
    ("an approach with no y", lambda f, l, r: layout_camp(l, "A")["approach"].pop("y")),
    ("regions not a list", lambda f, l, r: l.__setitem__("regions", {"id": "plateau"})),
    ("a region with no id", lambda f, l, r: l["regions"][0].pop("id")),
    ("a region with no camps", lambda f, l, r: l["regions"][0].__setitem__("camps", [])),
    ("a region naming an unknown camp", lambda f, l, r: l["regions"][0]["camps"].append("Z")),
    ("a region holding the boss room", lambda f, l, r: l["regions"][0]["camps"].append("C")),
    ("a camp in two regions", lambda f, l, r: l["regions"].append({"id": "again", "y": 8, "camps": ["B"], "cells": []})),
    ("a region at another height", lambda f, l, r: l["regions"][0].__setitem__("y", 9)),
    ("a road cell of size 0", lambda f, l, r: l["regions"][0]["cells"][0].__setitem__("sx", 0)),
    ("a road cell with no id", lambda f, l, r: l["regions"][0]["cells"][0].pop("id")),
    ("a road cell 1 stud too close to the boss room", lambda f, l, r: region_cell(l, "RoadBC4").__setitem__("x", 193)),
    ("a door of 4.8", lambda f, l, r: region_cell(l, "Road5").update({"x": -280.6, "sx": 42.8})),
    ("a cycle", lambda f, l, r: l["regions"][0]["cells"].append({"id": "Loop", "x": -119, "z": -44, "sx": 38, "sz": 16})),
    ("a road cell joined to nothing", lambda f, l, r: l["regions"][0]["cells"].append({"id": "Far", "x": 0, "z": 300,
                                                                                         "sx": 10, "sz": 10})),
    ("levels.doorSpare missing", lambda f, l, r: r.pop("doorSpare")),
    ("levels.regionLockMargin missing", lambda f, l, r: r.pop("regionLockMargin")),
)


# L2-13: StageFlow.secretProblems' lines, each broken once, on a level whose layout has secrets and
# whose file names them (Forest Road); refused alike on both sides.
def secret_entry(file, sid):
    return file["secrets"][sid]


L2_REFUSALS = (
    ("no secrets block", lambda f, l, r: f.pop("secrets")),
    ("a secrets block that is a string", lambda f, l, r: f.__setitem__("secrets", "lookout")),
    ("a secrets block that is a string, the layout without secrets",
     lambda f, l, r: (f.__setitem__("secrets", "lookout"), l.__setitem__("secrets", []))),
    ("a layout secret with no entry", lambda f, l, r: f["secrets"].pop(l["secrets"][0]["id"])),
    ("a layout secret with no id", lambda f, l, r: l["secrets"][0].pop("id")),
    ("an entry with no name", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).pop("name")),
    ("an entry with an empty name", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("name", "")),
    ("a valor of 2.5", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("valor", 2.5)),
    ("a valor of -1", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("valor", -1)),
    ("materials that are a string", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("materials", "50")),
    ("a family that is a number", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("family", 5)),
    ("an empty family", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("family", "")),
    ("a family of 25 characters", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("family", "f" * 25)),
    # L4 W2 (MISSIONS_DESIGN 28): a secret's key, the Castle Key's line.
    ("a key that is a number", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("key", 5)),
    ("an empty key", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("key", "")),
    ("a key of 25 characters", lambda f, l, r: secret_entry(f, l["secrets"][0]["id"]).__setitem__("key", "k" * 25)),
)


def region_cell(layout, cid):
    return next(cell for region in layout["regions"] for cell in region["cells"] if cell["id"] == cid)


# L2-34, L2-36: StageFlow.reactProblems' lines. Every case first gives the layout a test tunnel of
# its own (whatever the shipped layout already has), so the cases hold before and after the cave's
# data lands; the first case is the tunnel alone, which both sides must accept.
def with_tunnel(layout):
    layout.setdefault("shortcuts", []).append(
        {"id": "testTunnel", "name": "Test Tunnel", "x": 0, "y": 400, "z": 0, "sx": 4, "sy": 4, "sz": 4})
    layout["blocks"].append({"name": "TestBramble", "look": "bramble", "x": 0, "y": 400, "z": 10, "sx": 4, "sy": 4,
                             "sz": 1, "react": "fire", "opens": "testTunnel"})
    return layout["blocks"][-1], layout["shortcuts"][-1]


def tunnel_change(change):
    def apply(f, l, r):
        bramble, shortcut = with_tunnel(l)
        change(l, bramble, shortcut)
    return apply


L2W2_ACCEPTED = (
    ("a test tunnel and its bramble", tunnel_change(lambda l, b, s: None)),
    ("a block that opens a shortcut and reacts to nothing", tunnel_change(lambda l, b, s: b.pop("react"))),
    ("a shortcut id of 32 characters",
     tunnel_change(lambda l, b, s: (s.__setitem__("id", "s" * 32), b.__setitem__("opens", "s" * 32)))),
    ("a shortcut a hundredth of a stud wide", tunnel_change(lambda l, b, s: s.__setitem__("sx", 0.01))),
)
L2W2_REFUSALS = (
    # Re-aimed by L2 W3 (L2-52): an ice block is deep water, so a bramble that reacts to ice (it
    # collides and opens the tunnel) is refused.
    ("a bramble that reacts to ice", tunnel_change(lambda l, b, s: b.__setitem__("react", "ice"))),
    ("a bramble that reacts to lava", tunnel_change(lambda l, b, s: b.__setitem__("react", "lava"))),
    ("a react that is a number", tunnel_change(lambda l, b, s: b.__setitem__("react", 5))),
    ("a reactive block that does not collide", tunnel_change(lambda l, b, s: b.__setitem__("collide", False))),
    ("opens naming no shortcut", tunnel_change(lambda l, b, s: b.__setitem__("opens", "nowhere"))),
    ("opens that is a number", tunnel_change(lambda l, b, s: b.__setitem__("opens", 7))),
    ("shortcuts that are a string", tunnel_change(lambda l, b, s: l.__setitem__("shortcuts", "cave"))),
    ("a shortcut with no id", tunnel_change(lambda l, b, s: s.pop("id"))),
    ("a shortcut with an empty id", tunnel_change(lambda l, b, s: s.__setitem__("id", ""))),
    ("a shortcut id of 33 characters",
     tunnel_change(lambda l, b, s: (s.__setitem__("id", "s" * 33), b.__setitem__("opens", "s" * 33)))),
    ("a shortcut id used twice", tunnel_change(lambda l, b, s: l["shortcuts"].append(copy.deepcopy(s)))),
    ("a shortcut whose y is a string", tunnel_change(lambda l, b, s: s.__setitem__("y", "4"))),
    ("a shortcut with no sz", tunnel_change(lambda l, b, s: s.pop("sz"))),
    ("a shortcut that is a string", tunnel_change(lambda l, b, s: l["shortcuts"].append("cave"))),
    # The L2 W2 fix round's s-m3: a box no root can stand in.
    ("a shortcut with an sz of 0", tunnel_change(lambda l, b, s: s.__setitem__("sz", 0))),
    ("a shortcut with a negative sx", tunnel_change(lambda l, b, s: s.__setitem__("sx", -4))),
    ("a shortcut with a negative sy", tunnel_change(lambda l, b, s: s.__setitem__("sy", -0.5))),
)


# L2-52, L2-58: StageFlow.reactProblems' ice and landing lines. Every case first gives the layout a
# test tunnel (whose shortcut an ice block may try to open) and a test pool of deep water of its
# own; the first case is the pool alone, which both sides must accept.
def with_pool(layout):
    bramble, shortcut = with_tunnel(layout)
    layout["blocks"].append({"name": "TestPool", "look": "water", "x": 0, "y": 400, "z": 30, "sx": 14, "sy": 2,
                             "sz": 14, "collide": False, "react": "ice", "landing": {"x": 0, "y": 401, "z": 10}})
    return layout["blocks"][-1], shortcut


def pool_change(change):
    def apply(f, l, r):
        pool, shortcut = with_pool(l)
        change(l, pool, shortcut)
    return apply


def second_pool(dx, dz, react="ice"):
    """The W3 fix round's s-s2: a second test pool of the first's size, `dx`, `dz` from its centre,
    reacting to `react` (None = plain deep water)."""
    def change(l, p, s):
        extra = {"name": "TestPool2", "look": "water", "x": p["x"] + dx, "y": 400, "z": p["z"] + dz, "sx": 14,
                 "sy": 2, "sz": 14, "collide": False}
        if react is not None:
            extra["react"] = react
        l["blocks"].append(extra)
    return pool_change(change)


L2W3_ACCEPTED = (
    ("a test pool of deep water with a landing", pool_change(lambda l, p, s: None)),
    ("a pool with no landing", pool_change(lambda l, p, s: p.pop("landing"))),
    ("deep water that reacts to nothing", pool_change(lambda l, p, s: (p.pop("react"), p.pop("landing")))),
    # The W3 fix round's Q3: any block a body falls through may carry a landing (CreekUp's).
    ("plain deep water with a landing", pool_change(lambda l, p, s: p.pop("react"))),
    # s-s2: ice footprints may touch; only ice builds a frozen top.
    ("a second pool touching the first along an edge", second_pool(14, 0)),
    ("a second pool touching the first at a corner", second_pool(14, 14)),
    ("plain deep water overlapping a pool", second_pool(7, 0, None)),
)
L2W3_REFUSALS = (
    # No landing on these two: since the W3 fix round's Q3 a landing on a colliding block is a line of
    # its own, and with one each case would be refused without the "is ice and collides" line.
    ("a pool that collides, with no landing", pool_change(lambda l, p, s: (p.pop("collide"), p.pop("landing")))),
    ("a pool with collide true, with no landing",
     pool_change(lambda l, p, s: (p.__setitem__("collide", True), p.pop("landing")))),
    ("a pool that opens a shortcut", pool_change(lambda l, p, s: p.__setitem__("opens", s["id"]))),
    ("a fire block with a landing", pool_change(lambda l, p, s: (p.__setitem__("react", "fire"),
                                                                 p.__setitem__("collide", True)))),
    # The W3 fix round's Q3: a landing on a block that collides (no body falls through it).
    ("a plain block that collides, with a landing", pool_change(lambda l, p, s: (p.pop("react"), p.pop("collide")))),
    ("a landing whose y is null", pool_change(lambda l, p, s: p["landing"].__setitem__("y", None))),
    ("a landing with no z", pool_change(lambda l, p, s: p["landing"].pop("z"))),
    ("a landing whose x is a string", pool_change(lambda l, p, s: p["landing"].__setitem__("x", "0"))),
    ("a landing that is a string", pool_change(lambda l, p, s: p.__setitem__("landing", "Road2"))),
    # s-s2: two ice blocks whose footprints overlap.
    ("a second pool overlapping the first", second_pool(13, 0)),
    ("a second pool on the first's footprint", second_pool(0, 0)),
)


def ice_rows(layout, ice):
    """sim_range.ice_cells as LevelGeometry.Pieces lists its ice pieces: in the blocks' order, then
    WorldReact.Cells' (X fastest), each [name, west, east, north, south, top, bottom]."""
    cells = sr.ice_cells(layout, ice)
    if not cells:
        return []
    order, across = {}, {}
    for index, block in enumerate(layout["blocks"]):
        if block.get("react") == "ice":
            name = block.get("name") or block["look"]
            order[name] = index
            across[name] = max(math.ceil(block["sx"] / ice["cell"]), 1)
    rows = []
    for cell in sorted(cells, key=lambda c: (order[c["block"]], c["k"] * across[c["block"]] + c["i"])):
        number = cell["k"] * across[cell["block"]] + cell["i"] + 1
        rows.append([f"Ice_{cell['block']}_{number}", *cell["box"], cell["top"], cell["top"] - ice["thickness"]])
    return rows


def ice_cases(data, expected, raw_layouts, rules):
    """The W3 second fix round's Q6: LevelGeometry.Pieces' ice pieces (built with LevelGeometry.SizesOf
    of Combat.json `levels`) against sim_range.ice_cells, box by box: every shipped level layout with
    the shipped levels.react.ice, and Forest Road with an inset of 0, a wider one (0.5), none written,
    one under 0 (no cells on either side), and with two pools that touch beside a pool too thin for
    its inset (its cells left no width). The third fix round's fd-s2 (a side another ice block meets
    whole is not inset): the touching pools at a wider inset, and pools that meet another only in
    part, at another top, and at a corner."""
    ice = (rules.get("react") or {}).get("ice")
    views = [(name, layout, ice) for name, layout in raw_layouts.items()]
    forest = raw_layouts.get("ForestRoad")
    if forest is not None and isinstance(ice, dict):
        views += [("ForestRoad, inset 0", forest, {**ice, "inset": 0}),
                  ("ForestRoad, inset 0.5", forest, {**ice, "inset": 0.5}),
                  ("ForestRoad, no inset written", forest, {k: v for k, v in ice.items() if k != "inset"}),
                  ("ForestRoad, inset -1", forest, {**ice, "inset": -1})]
        pools = copy.deepcopy(forest)
        for name, x, z, sx in (("TestPool", 0, 30, 14), ("TestPool2", 14, 30, 14), ("TestThin", 40, 30, 0.08)):
            pools["blocks"].append({"name": name, "look": "water", "x": x, "y": 400, "z": z, "sx": sx, "sy": 2,
                                    "sz": 14, "collide": False, "react": "ice"})
        views.append(("ForestRoad with two pools that touch and one 0.08 wide", pools, ice))
        views.append(("ForestRoad with two pools that touch and one 0.08 wide, inset 0.5", pools, {**ice, "inset": 0.5}))
        # fd-s2: Wide's west side meets Narrow (14 deep) only in part; Low meets Wide's east side
        # whole but 1 stud lower; Corner touches Wide's south-east corner only.
        apart = copy.deepcopy(forest)
        for name, x, z, sx, sz, y in (("TestWide", 0, 60, 21, 28, 400), ("TestNarrow", -17.5, 60, 14, 14, 400),
                                      ("TestLow", 17.5, 60, 14, 28, 399), ("TestCorner", 17.5, 81, 14, 14, 400)):
            apart["blocks"].append({"name": name, "look": "water", "x": x, "y": y, "z": z, "sx": sx, "sy": 2,
                                    "sz": sz, "collide": False, "react": "ice"})
        views.append(("ForestRoad with pools that meet in part, at another top and at a corner", apart,
                      {**ice, "inset": 0.5}))
    for index, (label, layout, case_ice) in enumerate(views, 1):
        case = f"ice.{index}"
        levels = {**rules, "react": {**(rules.get("react") or {}), "ice": case_ice}}
        data["iceCases"].append({"id": case, "layout": layout, "levels": levels})
        expected[case] = ("LevelGeometry.Pieces: the ice cells (the W3 second fix round's Q6 inset)", label,
                          ice_rows(layout, case_ice))


# ---------------------------------------------------------------------------------------------
# The harness's bundling, read and not run
# ---------------------------------------------------------------------------------------------


def harness_tools():
    """(to_luau, wrap, {module name: its path in the repo}) from tools/crowd_harness/run_harness.py,
    read-only. The file is imported when importing it runs nothing (its harness is behind a
    `__main__` guard); an older copy that runs the whole harness at import has its two
    definitions compiled out of its text instead, and is wrapped by wrap_source below."""
    path = HARNESS / "run_harness.py"
    tree = ast.parse(path.read_text(encoding="utf-8"))
    guarded = any(isinstance(node, ast.If) and "__main__" in ast.unparse(node.test) for node in tree.body)
    defined = {node.name for node in tree.body if isinstance(node, ast.FunctionDef)}
    if guarded and {"to_luau", "wrap", "sources"} <= defined:
        spec = importlib.util.spec_from_file_location("run_harness", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.to_luau, module.wrap, module.sources(ROOT)
    body = [node for node in tree.body
            if (isinstance(node, ast.FunctionDef) and node.name == "to_luau")
            or (isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "SOURCES" for t in node.targets))]
    names = {getattr(node, "name", None) or "SOURCES" for node in body}
    if names != {"to_luau", "SOURCES"}:
        raise SystemExit(f"check_stage_mirror: {path} no longer defines to_luau and SOURCES at its top level "
                         f"(found {sorted(names)})")
    scope = {"json": json, "re": re, "Path": Path}
    exec(compile(ast.Module(body=body, type_ignores=[]), str(path), "exec"), scope)
    return scope["to_luau"], wrap_source, scope["SOURCES"]


def wrap_source(name, text):
    """One module as run_harness.py's `wrap` bundles it (used only with a copy of that file that
    has no `wrap`): its body inside a function that is handed the Roblox globals it names,
    `export type` made a plain `type`."""
    text = re.sub(r"(?m)^export type", "type", text)
    return f"SOURCES.{name} = function(game, script, require, Vector3, os, task, warn, RaycastParams, Enum)\n{text}\nend\n"


def find_luau(given):
    if given:
        return Path(given)
    name = "luau.exe" if sys.platform.startswith("win") else "luau"
    here = ROOT / "tools" / "bin" / name
    if here.exists():
        return here
    link = ROOT / ".git"
    if link.is_file():  # a worktree: `gitdir: <main checkout>/.git/worktrees/<name>`
        found = re.match(r"gitdir:\s*(.+)", link.read_text(encoding="utf-8").strip())
        if found:
            main = Path(found.group(1)).parents[2] / "tools" / "bin" / name
            if main.exists():
                return main
    raise SystemExit(f"check_stage_mirror: no Luau interpreter at {here}. Run `py tools/check_mirror.py` once (it "
                     f"fetches one), or pass --luau <path>.")


# ---------------------------------------------------------------------------------------------
# Comparing
# ---------------------------------------------------------------------------------------------


def plain(value):
    """A Python value as the Luau's JSON would carry it: no None in a table (a nil is an absent
    key), tuples as lists."""
    if isinstance(value, dict):
        return {str(key): plain(item) for key, item in value.items() if item is not None}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    return value


def same(a, b):
    """Equal, value by value. An empty table is an empty table, whichever side made it a list."""
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b or abs(a - b) <= TOLERANCE * max(abs(a), abs(b), 1.0)
    if isinstance(a, (dict, list)) and isinstance(b, (dict, list)) and not a and not b:
        return True
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[key], b[key]) for key in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b


def where(a, b, path=""):
    """The first place two values differ, as text."""
    if isinstance(a, dict) and isinstance(b, dict) and (a or b):
        for key in sorted(set(a) | set(b)):
            if key not in a or key not in b:
                return f"{path}.{key}: {'absent' if key not in a else short(a[key])} / {'absent' if key not in b else short(b[key])}"
            if not same(a[key], b[key]):
                return where(a[key], b[key], f"{path}.{key}")
    if isinstance(a, list) and isinstance(b, list) and (a or b):
        if len(a) != len(b):
            return f"{path}: {len(a)} entries / {len(b)}"
        for index, (x, y) in enumerate(zip(a, b), 1):
            if not same(x, y):
                return where(x, y, f"{path}[{index}]")
    return f"{path or 'value'}: {short(a)} / {short(b)}"


def short(value, limit=140):
    text = json.dumps(value, sort_keys=True) if not isinstance(value, str) else value
    return text if len(text) <= limit else text[:limit - 3] + "..."


class Report:
    def __init__(self, show):
        self.show = show
        self.kinds = {}  # kind -> [compared, [difference]]
        self.order = []

    def compare(self, kind, label, luau, python):
        """One comparison. Differences read `Luau / Python`."""
        entry = self.kinds.setdefault(kind, [0, []])
        if kind not in self.order:
            self.order.append(kind)
        entry[0] += 1
        if isinstance(luau, dict) and "threw" in luau:
            entry[1].append(f"{label}: the Luau threw: {luau['threw']}")
        elif not same(luau, python):
            entry[1].append(f"{label}: {where(luau, python)}")

    def differ(self, kind, text):
        entry = self.kinds.setdefault(kind, [0, []])
        if kind not in self.order:
            self.order.append(kind)
        entry[0] += 1
        entry[1].append(text)

    def print(self):
        failed = 0
        for kind in self.order:
            compared, found = self.kinds[kind]
            if not found:
                print(f"  ok    {kind}: {compared} compared")
                continue
            failed += len(found)
            print(f"  DIFF  {kind}: {len(found)} of {compared} differ (Luau / Python)")
            for text in found[:self.show]:
                print(f"          {text}")
            if len(found) > self.show:
                print(f"          ... and {len(found) - self.show} more")
        return failed


# ---------------------------------------------------------------------------------------------
# LevelRun.advance on a script
# ---------------------------------------------------------------------------------------------


class Scripted(sr.LevelRun):
    """The simulator's own `advance`, fed a script instead of a fight: what it reads of the
    world (the root, the field, the queue, the fallen, the cap, the director's two answers) is
    the tick's; everything it does to the world is left out. Its decisions are untouched."""

    def __init__(self, cfg, ctx, level, layout, difficulty):
        super().__init__(cfg, 100.0, ctx, dict(level), layout, difficulty, sr.THREAT_POLICIES["stand"], 1)
        self.given = {"mergeOk": False, "breatherSeconds": 0.0}
        run = self

        class Director:  # what advance() asks of sim_combat
            @staticmethod
            def should_merge(_tempo, _dead, _director):
                return run.given["mergeOk"]

            @staticmethod
            def breather_seconds(_tempo, _director):
                return run.given["breatherSeconds"]

            dead_fraction = staticmethod(sc.dead_fraction)

        self.sc = Director
        self.spawned = 1

    def flow_input(self, t):
        """StageFlow.Input: the tick's own (L1b), never the world's."""
        g = self.given
        return {"roots": [tuple(root) for root in g["roots"]], "standing": g.get("standing"),
                "fighters": list(g["fighters"]) if g.get("fighters") is not None else [],
                "spawningDone": g["spawningDone"], "alive": g["alive"], "awake": g["awake"],
                "aliveByFloor": list(g["aliveByFloor"]), "fallen": g["fallen"]}

    def on_gate(self, index, t):
        pass

    def on_close(self, t):
        pass

    def on_wave(self, wave, merged, t):
        pass

    def on_clear(self, t):
        pass

    def on_reach(self, floor, t):
        pass

    def on_camp_clear(self, floor, t):
        pass

    def on_open(self, t, index=None, skipped=False):
        pass

    def on_rearm(self, t):
        pass

    def on_drop(self, t):
        pass

    def on_move(self, index, t):
        pass

    def on_approach(self, floor, t):
        pass

    def stand_up(self, t):
        pass

    def armed_zone(self):
        index = self.armed_index()
        return self.plan["stages"][index - 1]["zone"] if index else None

    def play(self, tick):
        """One tick, or one press of a Studio lever: (the actions decided, the state after them,
        directs(), still_closing())."""
        self.given = tick
        x, y, z = tick["roots"][0]
        self.x, self.z = x, z
        zone = self.armed_zone()
        self.above = y - zone["floorY"] if zone is not None else sr.ROOT_HEIGHT
        self.queue = [] if tick["spawningDone"] else [["fodder", 1, 0, None]]
        self.boss_pending = None
        self.down_until = math.inf if tick.get("fallen") else None
        self.downs = [tick["now"]] if tick.get("fallen") else []
        self.level["runCapSeconds"] = tick["now"] if tick["runCap"] else 0
        self.fighters_now = list(tick["fighters"]) if tick.get("fighters") is not None else []
        before = len(self.actions)
        clear = self.field_clear(self.flow_input(tick["now"]))
        up = self.stands_up(self.flow_input(tick["now"]))
        if tick["op"] == "skip":
            self.skip(tick["which"], tick["now"], tick.get("fighters"))
        elif tick["op"] == "force":
            self.force(tick["wave"], tick["now"])
        else:
            self.advance(tick["now"])
        actions = [dict(fields, kind=kind) for kind, fields in self.actions[before:]]
        state = {"stage": self.stage, "step": self.flow, "wave": self.wave, "firstWave": self.first_wave,
                 "gateAt": self.gate_at, "breatherUntil": self.breather_until, "cleared": self.cleared,
                 "lastCleared": self.last_cleared, "settled": self.settled,
                 "reached": sorted(k for k, v in self.reached.items() if v),
                 "done": sorted(k for k, v in self.done.items() if v), "closedAt": self.closed_at,
                 "fought": list(self.fought), "ended": self.end_reason, "approached": self.approached}
        safe = [list(self.safe_point(busy_of(case, len(self.zones)), threats_of(case, self.zones))) for case in BUSY_CASES]
        return actions, state, self.directs(), self.still_closing(tick["now"]), clear, safe, up


# SafePoint's `busy`, per tick: none, every floor, the first, the last (as lists of floor indices);
# and its `threats` (the fix round): a threat 5 studs off every checkpoint (3, 4 on the flat) whose
# reach is exactly 5 (it reaches: the edge is included) or a hair under it (it does not).
BUSY_CASES = ("none", "all", "first", "last", "threatAll", "threatShort")
THREAT_REACH = {"threatAll": 5.0, "threatShort": 5.0 - 1e-6}


def threats_of(case, zones):
    reach = THREAT_REACH.get(case)
    if reach is None:
        return None
    return [{"at": (z["checkpoint"][0] + 3.0, z["floorY"] + 7.0, z["checkpoint"][1] + 4.0), "reach": reach}
            for z in zones if z["checkpoint"] is not None]


def busy_of(case, zones):
    if case not in ("all", "first", "last") or zones == 0:
        return None
    return {"all": {i: True for i in range(1, zones + 1)}, "first": {1: True}, "last": {zones: True}}[case]


def script_run(run, variant, rules, start_y):
    """Plays one scripted run on the Python side and returns its ticks: [(input, actions, state,
    directs, still closing)]. The script is written as it goes, from where the Python mirror
    stands; the Luau is then handed the same inputs, so either side going its own way shows at
    that tick. `variant` says what the run is for: a clean clear, a down, the run cap, a
    countdown that ends with nobody on his feet, or a Studio lever pressed the first time the
    run is on the road, in a countdown, in a fight and in a breather."""
    ticks = []
    clock = [0.0]
    stages = run.plan["stages"]
    zones = run.plan["zones"]
    camps = [index for index, stage in enumerate(stages, 1) if stage["kind"] == "camp"]
    start = run.plan["start"]
    spot = [(start[0], start_y + sr.ROOT_HEIGHT, start[1])]
    reset = [variant == "reset"]
    pressed = set()
    # Living bodies per floor: the open camps' residents, and nothing on a locking camp's floor
    # (so a locking camp would clear as an open one if a side forgot `locks`).
    by_floor = [0 if zone["locks"] else zone["residents"] for zone in zones]
    walked = set()

    def tick(root=None, at=None, fieldClear=True, **given):
        clock[0] = at if at is not None else clock[0] + 0.5
        if root is not None:
            spot[0] = root
        entry = {"op": "tick", "now": clock[0], "roots": [list(spot[0])], "fighters": [1], "spawningDone": True,
                 "alive": 0 if fieldClear else 1, "awake": 0, "aliveByFloor": list(by_floor), "mergeOk": False,
                 "breatherSeconds": BREATHER_INPUT, "fallen": None, "runCap": False}
        entry.update(given)
        ticks.append((entry,) + run.play(entry))

    def open_camps():
        """L1b-17 and L1b-18 on the road: each open camp's checkpoint walked up to, then its
        residents killed off. True when the run ended on the way (roadDown)."""
        for index, zone in enumerate(zones, 1):
            if zone["locks"] or index in walked:
                continue
            walked.add(index)
            mark = zone["checkpoint"]
            floor = zone["floorY"]
            root = floor + sr.ROOT_HEIGHT
            if mark is not None:
                reach = rules["checkpointReach"]
                tick((mark[0] + reach + 0.5, root, mark[1]))  # past its reach
                tick((mark[0], floor + rules["triggerHeight"] + 0.5, mark[1]))  # over the band
                tick((mark[0], floor - rules["triggerBelow"] - 0.5, mark[1]))  # under it
                tick((mark[0], root, mark[1]), standing=[False], fallen="down")  # a downed root, a quiet road
                tick((mark[0] + reach, root, mark[1]))  # on its edge: reached
                tick((mark[0], root, mark[1]))  # again: nothing more
            tick(awake=1)  # a group awake, nobody down: nothing
            if variant == "roadDown":
                tick(awake=1, fallen="down")  # down while a group is awake: the run is lost
                return True
            if variant == "standing":
                continue  # the open camps are left standing
            by_floor[index - 1] = 2
            tick(awake=1)  # two left: its last resident and a body its tent sent, out on the road
            by_floor[index - 1] = 1
            tick(awake=1)  # one left: not cleared
            by_floor[index - 1] = 0
            tick()  # the last falls (L1b-W4-29: whatever its tent has not sent, the camp is cleared)
            tick()  # once
        return False

    def lever(where):
        """Presses this run's lever the first time it stands `where`; True when it did. The
        `approach` run presses N on the road APPROACH_PRESSES times (L1b-W4-31)."""
        if variant in ("approach", "approachPast") and where == "road":
            presses = sum(1 for p in pressed if isinstance(p, int))
            if presses >= APPROACH_PRESSES:
                return False
            pressed.add(presses)
            first = next((z for z in zones if not z["locks"] and z.get("approach") and z["checkpoint"]), None)
            if variant == "approachPast" and presses == 0 and first is not None:
                # The first open camp's checkpoint reached first: N passes over that camp.
                mark = first["checkpoint"]
                tick((mark[0], first["floorY"] + sr.ROOT_HEIGHT, mark[1]))
            tick(op="skip", which="stage", fighters=[1])
            return True
        if variant not in ("skipStage", "skipBoss", "force") or where in pressed:
            return False
        pressed.add(where)
        if variant == "skipStage":
            tick(op="skip", which="stage", fighters=[1, 2])
        elif variant == "skipBoss":
            tick(op="skip", which="boss", fighters=None)  # no fighters handed: StageFlow takes none
        else:
            # A wave past the camp's last, one under its first, and one with a fraction.
            tick(op="force", wave={"road": 1, "gate": 2, "fight": 99, "breather": 0}[where])
            if where == "fight":
                tick(op="force", wave=2.7)
        return True

    tick()  # the first tick, standing on the start point
    for _guard in range(600):
        flow = run.flow
        if flow == "over":
            break
        if flow in ("travel", "armed"):
            if lever("road"):
                continue
            if open_camps():
                continue
            zone = run.armed_zone()
            if zone is None:
                break
            cx, cz, hx, hz = zone["rect"]
            ex, ez = zone["entry"]
            # The side of the floor its entry point is nearest to, and the way out through it.
            gaps = {"west": ex - (cx - hx), "east": (cx + hx) - ex, "north": ez - (cz - hz), "south": (cz + hz) - ez}
            side = min(gaps, key=gaps.get)
            ox, oz = {"west": (-1, 0), "east": (1, 0), "north": (0, -1), "south": (0, 1)}[side]

            def out(studs, gap=gaps[side], ex=ex, ez=ez, ox=ox, oz=oz):
                """The point `studs` outside the floor's edge, in line with the entry."""
                return ex + ox * (gap + studs), ez + oz * (gap + studs)

            floor, fence = zone["floorY"], zone["fence"]
            root = floor + sr.ROOT_HEIGHT
            x, z = out(fence + 0.5)
            tick((x, root, z))  # outside the fenced rectangle
            x, z = out(fence / 2)
            tick((x, floor + zone["ceiling"] + 0.5, z))  # on the fence line, above its band
            tick((x, floor - rules["triggerBelow"] - 0.5, z))  # and under it
            if zone["ceiling"] > rules["triggerHeight"]:
                # A walled camp (the L1c second fix round's F1, F3): over triggerHeight, inside its
                # band up to the wall's top, a root at the top of a jump in the opening triggers.
                tick((x, floor + rules["triggerHeight"] + 0.5, z))
            tick((x, root, z))  # on the fence line: the camp triggers
            if run.flow in ("travel", "armed"):
                x, z = out(-(rules["closeInset"] + 1))
                tick((x, root, z))  # well inside the floor
            if run.flow in ("travel", "armed"):
                break  # the mirror would never trigger: the comparison has said why
            continue
        if flow == "gate":
            tick(at=(clock[0] + run.gate_at) / 2)  # the countdown runs
            tick(at=(clock[0] + run.gate_at) / 2, standing=[False])  # a down in it stands up (StandsUp)
            if lever("gate"):
                continue
            if reset[0]:
                reset[0] = False
                tick(at=run.gate_at, fallen="down")  # nobody on his feet as the countdown ends
                continue
            tick(at=run.gate_at)  # the gates close; the first wave
            tick(at=run.gate_at + rules["closeGraceSeconds"] / 2, spawningDone=False, fieldClear=False)  # in the grace
            tick(at=run.gate_at + rules["closeGraceSeconds"], spawningDone=False, fieldClear=False)  # and at its end
            continue
        if flow == "breather":
            tick(at=(clock[0] + run.breather_until) / 2)
            if lever("breather"):
                continue
            tick(at=run.breather_until)
            continue
        # flow == "fight"
        wave = run.wave
        camp = camps.index(run.stage) + 1
        tick(spawningDone=False, fieldClear=False)  # still spawning
        if lever("fight"):
            continue
        tick(fieldClear=False, mergeOk=True)  # the director asks to merge
        if run.wave != wave:
            continue  # it merged: the next wave's bodies are on their way
        tick(fieldClear=False)  # bodies alive, nothing to decide
        if variant == "down" and camp == min(2, len(camps)) and wave == min(2, stages[run.stage - 1]["waves"]):
            tick(fieldClear=False, fallen="down")  # down with bodies alive: the run is lost
            continue
        if variant == "cap" and camp == len(camps) and wave == 1:
            tick(fieldClear=False, runCap=True)
            continue
        if wave == 1:
            tick(fallen="down", fighters=[2])  # down, but the field is clear: the clear wins
        else:
            # The field is clear. Who fights changes from clear to clear, so the star's rule (those
            # of the LAST clear) is told from "whoever fought at some point".
            tick(fighters=[1] if wave % 2 == 0 else [1, 2])
    return ticks


def action_row(action):
    row = {field: action.get(field) for field in ACTION_FIELDS}
    row["merged"] = bool(row["merged"])
    row["skipped"] = bool(row["skipped"])
    return plain(row)


def tick_text(entry):
    if entry["op"] == "skip":
        return f"now {entry['now']:g}, Skip \"{entry['which']}\""
    if entry["op"] == "force":
        return f"now {entry['now']:g}, Force {entry['wave']:g}"
    odd = [f"{key} {entry[key]}" for key in ("alive", "awake", "spawningDone", "mergeOk", "fallen", "runCap")
           if entry[key] not in ({"alive": 0, "awake": 0, "spawningDone": True, "mergeOk": False, "fallen": None,
                                  "runCap": False}[key],)]
    if entry.get("standing") is not None:
        odd.append(f"standing {entry['standing']}")
    root = entry["roots"][0]
    return (f"now {entry['now']:g}, root ({root[0]:g}, {root[1]:g}, {root[2]:g}), aliveByFloor {entry['aliveByFloor']}"
            + (", " + ", ".join(odd) if odd else ""))


# ---------------------------------------------------------------------------------------------
# L1b: the plan's zones and groups as rows, CampBrain's cases, SplitCarry's sequences
# ---------------------------------------------------------------------------------------------


def zone_row(zone):
    """A Plan zone as the Luau's stage_mirror.luau prints it: points on the floor as [x, y, z]."""
    floor = zone["floorY"]
    mark = zone["checkpoint"]
    return {"id": zone["id"], "floor": zone["floor"], "locks": zone["locks"], "name": zone["name"],
            "checkpoint": None if mark is None else [mark[0], floor, mark[1]], "residents": zone["residents"],
            "stock": dict(zone["stock"]), "tentStock": zone["tentStock"],
            "floorY": floor, "rect": list(zone["rect"]), "inner": list(zone["inner"]), "fence": zone["fence"],
            "trigger": list(zone["trigger"]),
            "ceiling": zone["ceiling"],
            "entry": [zone["entry"][0], floor, zone["entry"][1]], "exit": [zone["exit"][0], floor, zone["exit"][1]],
            "spawns": [[x, floor, z] for x, z in zone["spawns"]],
            "region": graph_row(zone["region"]) if zone.get("region") is not None else None,
            "approach": list(zone["approach"]) if zone.get("approach") is not None else None}


def graph_row(graph):
    """A RegionGraph as plain values, as stage_mirror.luau's L.graph prints it: cells as
    [x, z, hx, hz], next and hops as rows (inf as "inf"), doors as sorted [i, j, x, z]."""
    n = len(graph["cells"])
    return {"cells": [[c["x"], c["z"], c["hx"], c["hz"]] for c in graph["cells"]],
            "next": [[graph["next"][i][j] for j in range(1, n + 1)] for i in range(1, n + 1)],
            "hops": [[wire(graph["hops"][i][j]) for j in range(1, n + 1)] for i in range(1, n + 1)],
            "doors": [[i, j, graph["doors"][i][j][0], graph["doors"][i][j][1]]
                      for i in range(1, n + 1) for j in sorted(graph["doors"][i])]}


def def_row(defn):
    """A CampGroupDef as plain values (both sides read and print it so)."""
    return plain({"id": defn["id"], "camp": defn["camp"], "floor": defn["floor"], "floorY": defn["floorY"],
                  "rect": dict(defn["rect"]), "posture": defn["posture"], "points": [list(p) for p in defn["points"]],
                  "yaw": defn["yaw"], "radius": defn["radius"], "held": defn["held"],
                  "units": [{"kind": u["kind"], "count": u["count"]} for u in defn["units"]],
                  "region": [dict(c) for c in defn["region"]] if defn.get("region") is not None else None})


def as_def(row):
    """A def row back as the mirror's def (points as tuples)."""
    defn = dict(row)
    defn["points"] = [tuple(p) for p in row["points"]]
    defn.setdefault("radius", 0)
    return defn


def post_row(post):
    return {"at": list(post["at"]), "yaw": post["yaw"], "leg": post["leg"]}


def tent_row(tent):
    """A PlanTent as plain values."""
    return plain({"zone": tent["zone"], "def": def_row(tent["def"]), "kinds": list(tent["kinds"]),
                  "posts": [post_row(p) for p in tent["posts"]], "doors": [list(d) for d in tent["doors"]],
                  "every": tent["every"], "pace": tent.get("pace")})


def wire(value):
    """A Python answer as the Luau's JSON prints it: infinities as the strings it writes."""
    if isinstance(value, float) and math.isinf(value):
        return "inf" if value > 0 else "-inf"
    if isinstance(value, (list, tuple)):
        return [wire(v) for v in value]
    if isinstance(value, dict):
        return {k: wire(v) for k, v in value.items()}
    return value


def ray_cases(data, expected, kinds, rest_drop, rise_blend):
    """HitShapes.CrowdRay, RayUpright and FlatToRect (L1b-W2-15, -16, -24) on grids: every kind,
    origins round it, aims at its shins, its body, its head's base, centre and top and past them,
    beside the capsule, at several widths and pads; RayUpright with low == high against Ray on
    seeded rays; FlatToRect on a rectangle's inside, edges, corners and beyond. L4 W2 (L4W2-11):
    HitShapes.SeatDrop on a grid of seats, and CrowdRay with a seated body's drop (half and fully
    seated at crowd.restDrop), aimed at the lowered head and capsule top and at the standing head;
    HitShapes.SeatStep (the W2 review's m4) on a grid of seats, goals, steps and paces, crowd's
    riseBlendSeconds among them."""
    import random

    rows, mine = [], []
    for name, kind in sorted(kinds.items()):
        r, h, hr = kind["radius"], kind["height"], kind["headRadius"]
        feet = (2.0, 1.0, -3.0)
        top = max(h - 2 * hr, h / 2 + r)
        aims = [(0.0, 0.5, 0.0), (0.0, h / 2, 0.0), (0.0, top, 0.0), (0.0, h - hr, 0.0),
                (0.0, h - 0.25 * hr, 0.0), (0.0, h + 0.05, 0.0), (0.0, h + hr + 0.3, 0.0),
                (r + 0.4, h / 2, 0.0), (r + 1.2, 0.2, 0.0), (0.0, h + 3.0, 0.0)]
        for origin in RAY_ORIGINS:
            o = (feet[0] + origin[0], feet[1] + origin[1], feet[2] + origin[2])
            for aim in aims:
                target = (feet[0] + aim[0], feet[1] + aim[1], feet[2] + aim[2])
                direction = sr.v_sub(target, o)
                for width, pad in RAY_WIDTHS:
                    for reach in (60.0, 10.0):
                        rows.append([list(o), list(direction), reach, width, pad, list(feet), r, h, hr])
                        entry, crit = sr.hs_crowd_ray(o, direction, reach, width, pad, feet, r, h, hr)
                        mine.append(["nil" if entry is None else entry, crit])
    case = "ray.crowdRay"
    data["rayCases"].append({"id": case, "op": "crowdRay", "rows": rows})
    expected[case] = ("HitShapes.CrowdRay", f"{len(rows)} rays over {len(kinds)} kinds", mine)
    # A restDrop under 0 and a height of 0 drop nothing (SeatDrop's guard).
    rows = [[h, seat, drop] for h in (5.0, 6.5, 7.5, 14.0, 0.0) for seat in SEAT_GRID for drop in (rest_drop, 0.0, 0.5, -0.1)]
    case = "ray.seatDrop"
    data["rayCases"].append({"id": case, "op": "seatDrop", "rows": rows})
    expected[case] = ("HitShapes.SeatDrop", f"{len(rows)} seats", [sr.hs_seat_drop(*row) for row in rows])
    # SeatStep: goals outside 0..1 (it clamps the goal, not the seat), a step of 0, a backward step and
    # one past the goal, and paces of 0 and under 0 (the guard: the goal at once).
    rows = [[seat, goal, dt, blend] for seat in SEAT_GRID for goal in (0.0, 1.0, 0.5, -1.0, 2.0)
            for dt in (0.0, 1 / 30, 0.1, 0.45, -0.1, 10.0) for blend in (rise_blend, 0.5, 0.2, 0.0, -1.0)]
    case = "ray.seatStep"
    data["rayCases"].append({"id": case, "op": "seatStep", "rows": rows})
    expected[case] = ("HitShapes.SeatStep", f"{len(rows)} steps", [sr.hs_seat_step(*row) for row in rows])
    rows, mine = [], []
    for name, kind in sorted(kinds.items()):
        r, h, hr = kind["radius"], kind["height"], kind["headRadius"]
        feet = (2.0, 1.0, -3.0)
        top = max(h - 2 * hr, h / 2 + r)
        for seat in (0.5, 1.0):
            drop = sr.hs_seat_drop(h, seat, rest_drop)
            aims = [(0.0, 0.5, 0.0), (0.0, h / 2 - drop, 0.0), (0.0, top - drop, 0.0), (0.0, h - hr - drop, 0.0),
                    (0.0, h - hr, 0.0), (0.0, top, 0.0), (r + 0.4, h / 2 - drop, 0.0)]
            for origin in RAY_ORIGINS:
                o = (feet[0] + origin[0], feet[1] + origin[1], feet[2] + origin[2])
                for aim in aims:
                    target = (feet[0] + aim[0], feet[1] + aim[1], feet[2] + aim[2])
                    direction = sr.v_sub(target, o)
                    for width, pad in RAY_WIDTHS:
                        rows.append([list(o), list(direction), 60.0, width, pad, list(feet), r, h, hr, drop])
                        entry, crit = sr.hs_crowd_ray(o, direction, 60.0, width, pad, feet, r, h, hr, drop)
                        mine.append(["nil" if entry is None else entry, crit])
    case = "ray.crowdRaySeated"
    data["rayCases"].append({"id": case, "op": "crowdRay", "rows": rows})
    expected[case] = ("HitShapes.CrowdRay", f"{len(rows)} rays at seated bodies over {len(kinds)} kinds (drop)", mine)
    rng = random.Random(RAY_SEED)
    rows, mine = [], []
    for _ in range(RAY_RANDOM):
        o = (rng.uniform(-20, 20), rng.uniform(-5, 25), rng.uniform(-20, 20))
        direction = (rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))
        feet = (rng.uniform(-4, 4), rng.uniform(-2, 2), rng.uniform(-4, 4))
        width, pad = rng.choice(RAY_WIDTHS)
        radius = rng.uniform(0.5, 4)
        low = rng.uniform(0, 3)
        high = low if rng.random() < 0.3 else low + rng.uniform(0, 8)
        reach = rng.choice((5.0, 30.0, 80.0))
        rows.append([list(o), list(direction), reach, width, pad, list(feet), low, high, radius])
        got = sr.hs_ray_upright(o, direction, reach, width, pad, feet, low, high, radius)
        mine.append("nil" if got is None else got)
    # A ray down the axis, a ray starting inside, one stopping short, one along a cap.
    for o, direction, reach in (((0.0, 20.0, 0.0), (0.0, -1.0, 0.0), 40.0), ((0.0, 2.0, 0.0), (1.0, 0.0, 0.0), 10.0),
                                ((-30.0, 2.0, 0.0), (1.0, 0.0, 0.0), 20.0), ((-30.0, 7.9, 0.0), (1.0, 0.0, 0.0), 60.0)):
        rows.append([list(o), list(direction), reach, 0.0, 0.0, [0.0, 0.0, 0.0], 1.0, 6.0, 1.0])
        got = sr.hs_ray_upright(o, direction, reach, 0.0, 0.0, (0.0, 0.0, 0.0), 1.0, 6.0, 1.0)
        mine.append("nil" if got is None else got)
    case = "ray.rayUpright"
    data["rayCases"].append({"id": case, "op": "rayUpright", "rows": rows})
    expected[case] = ("HitShapes.RayUpright", f"{len(rows)} rays (a third with low == high)", mine)
    rows = [[x, z, 1.0, -2.0, 4.0, 3.0] for x in (-8.0, -3.0, -3.0 - 1e-7, 0.0, 1.0, 5.0, 5.0 + 1e-7, 9.0)
            for z in (-9.0, -5.0, -5.0 - 1e-7, 0.0, 1.0, 1.0 + 1e-7, 4.0)]
    case = "ray.flatToRect"
    data["rayCases"].append({"id": case, "op": "flatToRect", "rows": rows})
    expected[case] = ("HitShapes.FlatToRect", f"{len(rows)} points round a 8 x 6 rectangle",
                      [sr.hs_flat_to_rect(*row) for row in rows])


def swing_cases(data, expected):
    """SwingGate (L1b-W2-13): IsAir at the margin and past it and with no floor; the contract's
    sequence of swings and landings, the state after every call."""
    margin = sr.SG_AIR_MARGIN_STUDS
    stand = 3.0
    heights = ["nil", 0.0, stand, stand + margin - 1e-7, stand + margin, stand + margin + 1e-7, stand + 5.0, -1.0]
    case = "swing.isAir"
    data["swingCases"].append({"id": case, "op": "isAir", "heights": heights, "stand": stand})
    expected[case] = ("SwingGate.IsAir", f"{len(heights)} heights over a stand of {stand:g}",
                      [sr.sg_is_air(None if h == "nil" else h, stand) for h in heights])
    ops = [("allows", False), ("took", False), ("allows", True), ("took", True), ("allows", True), ("allows", False),
           ("landed", None), ("allows", True), ("took", True), ("took", False), ("allows", True), ("took", True),
           ("took", True), ("allows", True)]
    state = sr.sg_new()
    rows = []
    for op, airborne in ops:
        ret = None
        if op == "allows":
            ret = sr.sg_allows(state, airborne)
        elif op == "took":
            sr.sg_took(state, airborne)
        else:
            sr.sg_landed(state)
        rows.append({"ret": "nil" if ret is None else ret, "used": state["used"]})
    case = "swing.sequence"
    data["swingCases"].append({"id": case, "op": "sequence", "ops": [[op, airborne] for op, airborne in ops]})
    expected[case] = ("SwingGate: a sequence of swings and landings", f"{len(ops)} calls", rows)
    case = "swing.margin"
    data["swingCases"].append({"id": case, "op": "margin"})
    expected[case] = ("SwingGate.AIR_MARGIN_STUDS", "the margin the mirror uses", margin)


def tent_owes_cases(data, expected):
    """StageFlow.TentOwesRouse (the fix round's B-3): every combination of its three inputs (the
    debt so far, the camp busy, the group up), against sim_range.tent_owes_rouse."""
    rows = [[owed, busy, awake] for owed in (False, True) for busy in (False, True) for awake in (False, True)]
    case = "flow.tentOwesRouse"
    data["tentOwesCases"].append({"id": case, "rows": rows})
    expected[case] = ("StageFlow.TentOwesRouse", f"all {len(rows)} combinations of owed, busy and awake",
                      [sr.tent_owes_rouse(*row) for row in rows])
    # The Wave 4 fix round's R10: which group states are a threat for the safe point.
    states = ["rest", "rise", "fight", "home"]  # Types.CampGroupState
    case = "flow.threatening"
    data["tentOwesCases"].append({"id": case, "op": "threatening", "rows": states})
    expected[case] = ("StageFlow.Threatening", f"every group state: {', '.join(states)}",
                      [sr.threatening(state) for state in states])


def wave2_camp_cases(data, expected, rules, plans):
    """CampBrain's Wave 2 rules (L1b-W2-6, -7, -10, -12): Dormant on the edge of dormantRadius in
    every state, Gap and JoinIn on the shipped camps (every group alone, from rest, and with
    states mixed) and on a grid chain, Rouse in every state, and the tent rule on timelines."""
    radius = rules["dormantRadius"]
    # Dormant: a 20 x 10 floor round (5, -3); roots on the flat edge of dormantRadius.
    defn = {"id": "grid.dormant", "camp": "G", "floor": 1, "floorY": 8.0, "rect": {"x": 5.0, "z": -3.0, "hx": 10.0,
            "hz": 5.0}, "posture": "patrol", "points": [(0.0, 8.0, 0.0), (6.0, 8.0, 0.0)], "yaw": 0.0, "radius": 0.0,
            "held": False, "units": [{"kind": "fodder", "count": 2}]}
    corner = radius / math.sqrt(2)
    places = ([[15.0 + radius + d, 11.0, -3.0] for d in DORMANT_EDGES] + [[5.0, 11.0, -8.0 - radius + d] for d in DORMANT_EDGES]
              + [[15.0 + corner + d, 11.0, 2.0 + corner + d] for d in DORMANT_EDGES] + [[5.0, 400.0, -3.0]])
    root_sets = [[]] + [[p] for p in places] + [[places[2], places[-1]]]
    for state, held in (("rest", False), ("rest", True), ("rise", False), ("fight", False), ("home", False)):
        group = sr.cb_new_group(defn, 0.0)
        group["state"], group["held"] = state, held
        case = f"camp.dormant.{state}.{held}"
        data["campCases"].append({"id": case, "op": "dormant", "def": def_row(defn), "state": state, "held": held,
                                  "rootSets": root_sets})
        expected[case] = ("CampBrain.Dormant", f"{state}{' held' if held else ''}, {len(root_sets)} sets of roots",
                          [sr.cb_dormant(group, [tuple(r) for r in roots], rules) for roots in root_sets])
    # Gap and JoinIn on the shipped plans.
    for label, plan in plans:
        defs = plan["groups"] + [tent["def"] for tent in plan["tents"]]
        posts = [[post_row(p) for p in sr.group_posts(d)] for d in defs]
        pairs = [(i, j) for i in range(1, len(defs) + 1) for j in range(1, len(defs) + 1)
                 if i != j and defs[i - 1]["camp"] == defs[j - 1]["camp"]]
        case = f"camp.gap.{label}"
        data["campCases"].append({"id": case, "op": "gap", "posts": posts, "pairs": [list(p) for p in pairs] + [[1, 0]]})
        gaps = {}
        found = []
        for i, j in pairs:
            gap = sr.cb_gap(sr.group_posts(defs[i - 1]), sr.group_posts(defs[j - 1]))
            gaps.setdefault(i, {})[j] = gap
            found.append(gap)
        found.append(sr.cb_gap(sr.group_posts(defs[0]), []))
        expected[case] = ("CampBrain.Gap", f"{label}: {len(pairs)} pairs of one camp, and one with no posts", wire(found))
        triples = [[i, j, gaps[i][j]] for i, j in pairs]
        scenarios = []
        living_full = {i: sum(u["count"] for u in d["units"]) for i, d in enumerate(defs, 1)}
        for i in range(1, len(defs) + 1):
            scenarios.append(("alone", [i], {}, living_full))
        # States mixed: every third group held, every fourth at home, every fifth dead, two wakers.
        mixed = {i: ("home" if i % 4 == 0 else "fight" if i % 7 == 0 else "rest", i % 3 == 0) for i in range(1, len(defs) + 1)}
        living_mixed = {i: (0 if i % 5 == 0 else n) for i, n in living_full.items()}
        scenarios.append(("mixed", [1, len(defs)], mixed, living_mixed))
        scenarios.append(("mixed, a tent empty", [2], mixed, {i: (0 if defs[i - 1]["posture"] == "tent" else n)
                                                             for i, n in living_full.items()}))
        for name, woke, states, living in scenarios:
            groups = [sr.cb_new_group(d, 0.0) for d in defs]
            for i, (state, held) in states.items():
                groups[i - 1]["state"], groups[i - 1]["held"] = state, held
            case = f"camp.joinIn.{label}.{len(data['campCases'])}"
            data["campCases"].append({"id": case, "op": "joinIn", "defs": [def_row(d) for d in defs],
                                      "states": [[i, s, h] for i, (s, h) in states.items()],
                                      "living": [[i, n] for i, n in living.items()], "gaps": triples, "woke": woke})
            expected[case] = ("CampBrain.JoinIn", f"{label} {name}, woke {woke}",
                              sr.cb_join_in(groups, living, gaps, woke, rules))
    # A grid chain: guard (sight 30) -> fire (16) -> fire, directed; the factor's edge.
    sight_guard, sight_fire = rules["guard"]["sight"], rules["fire"]["sight"]
    factor = rules["joinFactor"]
    guard = grid_def("guard", [(0.0, 0.0)], yaw=0.0)
    fire_a = grid_def("fire", [(0.0, factor * sight_guard)], radius=0.0, units=(("fodder", 1),))
    fire_b = grid_def("fire", [(0.0, factor * sight_guard + factor * sight_fire)], radius=0.0, units=(("fodder", 1),))
    fire_c = grid_def("fire", [(0.0, factor * sight_guard + 2 * factor * sight_fire + 1e-6)], radius=0.0,
                      units=(("fodder", 1),))
    defs = [guard, fire_a, fire_b, fire_c]
    gaps = {}
    for i, a in enumerate(defs, 1):
        for j, b in enumerate(defs, 1):
            if i != j:
                gaps.setdefault(i, {})[j] = sr.cb_gap(sr.group_posts(a), sr.group_posts(b))
    triples = [[i, j, g] for i, row in gaps.items() for j, g in row.items()]
    living = {1: 1, 2: 1, 3: 1, 4: 1}
    for woke in ([1], [2], [3], [4], [3, 1]):
        groups = [sr.cb_new_group(d, 0.0) for d in defs]
        case = f"camp.joinIn.grid.{len(data['campCases'])}"
        data["campCases"].append({"id": case, "op": "joinIn", "defs": [def_row(d) for d in defs], "states": [],
                                  "living": [[i, n] for i, n in living.items()], "gaps": triples, "woke": woke})
        expected[case] = ("CampBrain.JoinIn", f"grid chain guard -> fire -> fire -> fire (just past), woke {woke}",
                          sr.cb_join_in(groups, living, gaps, woke, rules))
    # Rouse in every state, with and without a player in play (the fix round's B-3: a homeward
    # group rises only with one).
    for state, held in (("rest", False), ("rest", True), ("rise", False), ("fight", False), ("home", False)):
        for in_play in (False, True):
            group = sr.cb_new_group(guard, 0.0)
            group["state"], group["held"], group["hit"] = state, held, True
            ret = sr.cb_rouse(group, 4.5, in_play)
            case = f"camp.rouse.{state}.{held}.{in_play}"
            data["campCases"].append({"id": case, "op": "rouse", "def": def_row(guard), "state": state, "held": held,
                                      "reachable": in_play})
            expected[case] = ("CampBrain.Rouse", f"{state}{' held' if held else ''}{' in play' if in_play else ''}",
                              {"ret": ret, "group": group_row(group)})
            # A tent's rouse (the lead's ruling (i)): only with a player in play, then as Rouse.
            group = sr.cb_new_group(guard, 0.0)
            group["state"], group["held"], group["hit"] = state, held, True
            ret = sr.cb_tent_rouse(group, 4.5, in_play)
            case = f"camp.tentRouse.{state}.{held}.{in_play}"
            data["campCases"].append({"id": case, "op": "tentRouse", "def": def_row(guard), "state": state,
                                      "held": held, "reachable": in_play})
            expected[case] = ("CampBrain.TentRouse", f"{state}{' held' if held else ''}{' in play' if in_play else ''}",
                              {"ret": ret, "group": group_row(group)})
    # The tent rule on timelines: wake at 0 (0, 6, 12), a pause from 13 to 40 (the next at 40),
    # the residents dead with the camp at rest (it keeps sending), the stock spent (never).
    every = 6.0
    # L1b-W4-28: the pace clock (busy time only, a gap not counted), Ahead at its edge, and
    # TentActive's truth table, with the clock and the stock carried through.
    # The fix round's R7: a clock call names `rested` and the residents alive; while rested the
    # measure starts afresh (busy 0, counted from those alive), and `aheadTent` is WaveService's
    # call, Ahead(tent.residents - alive, tent.residents, busySeconds, pace).
    pace = {"seconds": 20.0, "lead": 0.25}
    ops = [("clock", False, 0.0, False, 10), ("clock", True, 1.0, False, 10), ("clock", True, 3.5, False, 10),
           ("ahead", 3, 10, pace),
           ("ahead", 4, 10, pace), ("clock", False, 4.0, False, 10), ("clock", False, 30.0, False, 10),
           ("clock", True, 31.0, False, 10),
           ("clock", True, 32.0, False, 9), ("ahead", 4, 10, pace), ("aheadTent", 6, pace), ("aheadTent", 7, pace),
           ("clock", True, 40.0, False, 8), ("clock", False, 41.0, True, 6), ("aheadTent", 6, pace),
           ("clock", True, 42.0, False, 6), ("clock", True, 45.0, False, 4), ("aheadTent", 4, pace),
           ("aheadTent", 3, pace), ("clock", True, 46.0, True, 3), ("aheadTent", 2, pace),
           ("clock", True, 47.0, False, 2), ("clock", True, 47.5, False, 2), ("aheadTent", 0, pace), ("ahead", 4, 10, {"seconds": 0, "lead": 0.1}),
           ("ahead", 0, 0, pace), ("ahead", 5, 10, {"seconds": 14.0, "lead": 0.25}),
           ("ahead", 5, 10, {"seconds": 14.0 + 1e-3, "lead": 0.25}),
           ("active", True, 5, True), ("due", True, 0.0), ("sent", 0.0), ("due", True, 3.0), ("due", True, 6.0 - 1e-7),
           ("sent", 6.0), ("active", True, 5, False), ("active", False, 5, True), ("active", True, 0, True),
           ("active", True, -1, True), ("active", False, 0, False), ("due", False, 12.0), ("due", True, 12.0),
           ("sent", 12.0), ("sent", 18.0), ("sent", 24.0), ("sent", 30.0), ("sent", 36.0), ("sent", 42.0), ("due", True, 48.0),
           ("sent", 48.0), ("due", True, 1e6), ("clock", True, 50.0, False, 2), ("clock", True, 49.0, False, 2)]
    rows = []
    tent = sr.cb_new_tent(8, 10)
    for op in ops:
        if op[0] == "active":
            ret = sr.cb_tent_active(op[1], op[2], op[3])
        elif op[0] == "due":
            ret = sr.cb_tent_due(tent, op[1], op[2])
        elif op[0] == "clock":
            sr.cb_tent_clock(tent, op[1], op[2], op[3], op[4])
            ret = "nil"
        elif op[0] == "ahead":
            ret = sr.cb_ahead(op[1], op[2], tent["busySeconds"], op[3])
        elif op[0] == "aheadTent":
            ret = sr.cb_ahead(tent["residents"] - op[1], tent["residents"], tent["busySeconds"], op[2])
        else:
            sr.cb_tent_sent(tent, op[1], every)
            ret = "nil"
        rows.append({"ret": ret, "left": tent["left"], "nextAt": wire(tent["nextAt"]), "busySeconds": tent["busySeconds"],
                     "lastAt": "nil" if tent["lastAt"] is None else tent["lastAt"], "residents": tent["residents"]})
    case = "camp.tent.timeline"
    data["campCases"].append({"id": case, "op": "tent", "stock": 8, "residents": 10, "every": every,
                              "ops": [list(op) for op in ops]})
    expected[case] = ("CampBrain: the pace tent on a timeline (L1b-W4-28, R7's restart at rest)", f"a stock of 8 every {every:g} s, "
                      f"{len(ops)} calls", rows)


def combat_cases(data, expected, files, raw_layouts, rules, ranks, crowd_kinds):
    """Combat.ClearBonus, DeadFraction and WaveStock (L1b-W2-21, -26): every camp's stock of every
    level at every difficulty under several shares (the boss room's with what its waves queue), a
    grid of prices that round at halves and an unpriced kind; DeadFraction on a grid; WaveStock on
    every wave with and without an elite."""
    rows, mine = [], []
    for file in files:
        level = sr.resolve_level(file, 0)
        if level is None or not level.get("camps"):
            continue
        layout = sr.load_level_layout(file["layout"])
        for difficulty, scales in level["difficulties"].items():
            plan = sr.plan_level(level, layout, difficulty, rules, ranks, crowd_kinds)
            if plan is None:
                continue
            for zone in plan["zones"]:
                stock = dict(zone["stock"])
                if zone["locks"]:
                    for stage in level["stages"]:
                        if stage.get("zone") == zone["id"]:
                            for wave in stage.get("waves") or []:
                                spec = sc.camp_wave(wave, level["crowd"]["regenShare"], scales, ranks[difficulty], ranks,
                                                    1, data["combat"])
                                sc.wave_stock(stock, spec)
                for share in BONUS_SHARES:
                    rows.append([stock, level["crowd"]["rewards"], scales["rewardMult"], share])
                    mine.append(list(sc.clear_bonus(stock, level["crowd"]["rewards"], scales["rewardMult"], share)))
    for cash, materials, mult in REWARD_GRID:
        for share in (0.5, 0.1, 1 / 3):
            stock = {"probe": 3, "nobody": 2}
            prices = {"probe": {"cash": cash, "materials": materials}}
            rows.append([stock, prices, mult, share])
            mine.append(list(sc.clear_bonus(stock, prices, mult, share)))
    rows.append([{}, {"probe": {"cash": 5, "materials": 1}}, 1, 0.1])
    mine.append(list(sc.clear_bonus({}, {"probe": {"cash": 5, "materials": 1}}, 1, 0.1)))
    case = "combat.clearBonus"
    data["combatCases"].append({"id": case, "op": "clearBonus", "rows": rows})
    expected[case] = ("Combat.ClearBonus", f"{len(rows)} stocks, shares and prices", mine)
    rows = [[spawned, alive] for spawned in (-1, 0, 1, 10, 40) for alive in (-5, 0, 1, 9, 10, 11, 50)]
    case = "combat.deadFraction"
    data["combatCases"].append({"id": case, "op": "deadFraction", "rows": rows})
    expected[case] = ("Combat.DeadFraction", f"{len(rows)} pairs", [sc.dead_fraction(s, a) for s, a in rows])
    rows, mine = [], []
    for case_ in data["waveCases"][:60]:
        spec = expected[case_["id"]][2]
        for elite in (None, "armoured"):
            stock = {"fodder": 2}
            sc.wave_stock(stock, spec, elite)
            rows.append([case_["id"], elite or "nil"])
            mine.append(stock)
    case = "combat.waveStock"
    data["combatCases"].append({"id": case, "op": "waveStock", "rows": rows})
    expected[case] = ("Combat.WaveStock", f"{len(rows)} waves, with and without an elite", mine)


def group_row(group):
    """A CampBrain Group after a call: its state, as both sides print it."""
    return {"state": group["state"], "held": group["held"], "since": group["since"], "quietSince": group["quietSince"],
            "hit": group["hit"], "known": sorted(k for k, v in group["known"].items() if v),
            "reachable": sorted(k for k, v in group["reachable"].items() if v),
            "hitAt": [[u, at] for u, at in sorted(group["hitAt"].items())],
            "struckBy": sorted(k for k, v in group["struckBy"].items() if v),
            "meleeQuietSince": group["meleeQuietSince"], "standDown": group["standDown"]}


def ring(centre, yaw, distances, angles, heights):
    """Targets round a point: at each distance, turned each angle (degrees) from the facing `yaw`,
    at each height: [{userId, root}]."""
    found = []
    for d in distances:
        for a in angles:
            turn = yaw + math.radians(a)
            x, z = centre[0] - math.sin(turn) * d, centre[2] - math.cos(turn) * d
            for y in heights:
                found.append({"userId": 1, "root": [x, y, z]})
    return found


def camp_cases(data, expected, label, defn, rules):
    """Sees, InPlay, AtPost, Goal, Struck and Shows on one group (L1b), on grids built round its
    posts, its floor's rectangle and its posture's numbers."""
    row = def_row(defn)
    posture = sr.cb_posture(defn, rules)
    sight, cone = posture["sight"], posture["cone"]
    floor = defn["floorY"]
    count = sum(unit["count"] for unit in defn["units"])
    posts = sr.cb_posts(defn, count)
    heights = [floor - rules["sightBelow"] - EDGE, floor - rules["sightBelow"], floor + sr.ROOT_HEIGHT,
               floor + rules["sightAbove"], floor + rules["sightAbove"] + EDGE]
    half = cone / 2
    angles = list(CB_ANGLES) + [half, -half, half + 1e-4, -half - 1e-4, half - 1e-4, -half + 1e-4]
    distances = [0.0, 0.0005, sight / 2, sight - EDGE, sight, sight + EDGE]
    for which, post in (("first", posts[0]), ("last", posts[-1])):
        member = {"at": post["at"], "post": post}
        targets = ring(post["at"], post["yaw"], distances, angles, heights)
        case = f"camp.sees.{defn['id']}.{which}.{len(data['campCases'])}"
        data["campCases"].append({"id": case, "op": "sees", "def": row,
                                  "member": {"at": list(post["at"]), "post": post_row(post)}, "targets": targets})
        expected[case] = ("CampBrain.Sees", f"{label}, from its {which} post, {len(targets)} targets",
                          [sr.cb_sees(defn, member, {"userId": 1, "root": tuple(t["root"])}, rules) for t in targets])
    # InPlay: the grown rectangle's edges, the band's, and a shooter's reach.
    rect, margin = defn["rect"], rules["chaseMargin"]
    xs = [rect["x"] - rect["hx"] - margin - EDGE, rect["x"] - rect["hx"] - margin, rect["x"],
          rect["x"] + rect["hx"] + margin, rect["x"] + rect["hx"] + margin + EDGE]
    zs = [rect["z"] - rect["hz"] - margin - EDGE, rect["z"] - rect["hz"] - margin, rect["z"],
          rect["z"] + rect["hz"] + margin, rect["z"] + rect["hz"] + margin + EDGE]
    band = [floor - rules["sightBelow"], floor + sr.ROOT_HEIGHT, floor + rules["sightAbove"] + EDGE]
    targets = [{"userId": 1, "root": [x, y, z]} for x in xs for z in zs for y in band]
    # The rounded corners (fix round, crowd Major 1): off each corner of the floor, just inside and
    # just outside chaseMargin on the diagonal and at 30 degrees; the grid's square corners above
    # are out of play now.
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = rect["x"] + sx * rect["hx"], rect["z"] + sz * rect["hz"]
            for degrees in (45, 30):
                a = math.radians(degrees)
                for d in (margin - EDGE, margin + EDGE, margin / 2):
                    targets.append({"userId": 1, "root": [cx + sx * d * math.cos(a), floor + sr.ROOT_HEIGHT,
                                                          cz + sz * d * math.sin(a)]})
    shooter = {"at": list(posts[0]["at"]), "reach": 32.0}
    targets += ring(posts[0]["at"], 0.0, [32.0 - EDGE, 32.0, 32.0 + EDGE], list(CB_ANGLES), [floor + sr.ROOT_HEIGHT])
    for shooters in ([], [shooter]):
        case = f"camp.inPlay.{defn['id']}.{len(shooters)}.{len(data['campCases'])}"
        data["campCases"].append({"id": case, "op": "inPlay", "def": row, "targets": targets, "shooters": shooters})
        theirs = [{"at": tuple(s["at"]), "reach": s["reach"]} for s in shooters]
        expected[case] = ("CampBrain.InPlay", f"{label}, {len(shooters)} shooter(s), {len(targets)} targets",
                          [sr.cb_in_play(defn, {"userId": 1, "root": tuple(t["root"])}, theirs, rules) for t in targets])
    # AtPost round the first post.
    tol = rules["homeTolerance"]
    ats = [p["root"] for p in ring(posts[0]["at"], 0.0, [0.0, tol - EDGE, tol, tol + EDGE], [0, 90, 180, 270, 45],
                                   [floor])]
    case = f"camp.atPost.{defn['id']}.{len(data['campCases'])}"
    data["campCases"].append({"id": case, "op": "atPost", "post": post_row(posts[0]), "ats": ats})
    expected[case] = ("CampBrain.AtPost", f"{label}, {len(ats)} places",
                      [sr.cb_at_post(posts[0], tuple(at), rules) for at in ats])
    # Goal, Struck and Shows on every state.
    points = defn["points"]
    states = (("rest", False), ("rest", True), ("rise", False), ("fight", False), ("home", False))
    for state, held in states + (("fight", "down"),):
        down = held == "down"
        held = False if down else held
        for k, post in enumerate(posts[:3], 1):
            legs = range(0, len(points) + 2) if defn["posture"] == "patrol" else [post["leg"]]
            places = [post["at"], (post["at"][0] + 30.0, floor, post["at"][2])]
            if defn["posture"] == "patrol":
                places += [(p[0] + tol / 2, floor, p[2]) for p in points]
            for leg in legs:
                for at in places:
                    group = sr.cb_new_group(defn, 0.0)
                    group["state"], group["held"], group["standDown"] = state, held, down
                    resident = {"group": 1, "post": post, "leg": leg}
                    goal, pace = sr.cb_goal(group, resident, at, rules)
                    case = f"camp.goal.{len(data['campCases'])}"
                    data["campCases"].append({"id": case, "op": "goal", "def": row, "state": state, "held": held,
                                              "standDown": down, "post": post_row(post), "leg": leg, "at": list(at)})
                    expected[case] = ("CampBrain.Goal", f"{label} {state}{' held' if held else ''}"
                                      f"{' stood down' if down else ''}, post {k}, leg {leg}, "
                                      f"at ({at[0]:g}, {at[2]:g})",
                                      plain([list(goal) if goal is not None else "nil", pace, resident["leg"]]))
        for by in (0, 1, 2):
            # L1b-W4-25: a player's hit (1, 2) and a lever's (0), twice, the second later.
            group = sr.cb_new_group(defn, 0.0)
            group["state"], group["held"], group["standDown"] = state, held, down
            rows = []
            for now in (4.25, 7.5):
                landed = sr.cb_struck(group, by, now)
                rows.append([landed, group["hit"], sr.cb_evades(group), group_row(group)])
            case = f"camp.struck.{len(data['campCases'])}"
            data["campCases"].append({"id": case, "op": "struck", "def": row, "state": state, "held": held,
                                      "standDown": down, "by": by})
            expected[case] = ("CampBrain.Struck", f"{label} {state}{' held' if held else ''}{' stood down' if down else ''}"
                              f", by {by}", rows)
        for moving in (False, True):
            group = sr.cb_new_group(defn, 0.0)
            group["state"], group["held"], group["standDown"] = state, held, down
            case = f"camp.shows.{len(data['campCases'])}"
            data["campCases"].append({"id": case, "op": "shows", "def": row, "state": state, "held": held,
                                      "standDown": down, "moving": moving})
            shown = sr.cb_shows(group, moving)
            expected[case] = ("CampBrain.Shows", f"{label} {state}{' held' if held else ''}{' stood down' if down else ''}"
                              f", moving {moving}", shown if shown is not None else "nil")


def grid_def(posture, points, *, yaw=0.0, radius=0.0, held=False, units=(("fodder", 3),)):
    """A group on a 60 x 60 floor at y 8 centred (0, 0), for the grids."""
    return {"id": f"grid.{posture}", "camp": "G", "floor": 1, "floorY": 8.0,
            "rect": {"x": 0.0, "z": 0.0, "hx": 30.0, "hz": 30.0}, "posture": posture,
            "points": [(x, 8.0, z) for x, z in points], "yaw": yaw, "radius": radius, "held": held,
            "units": [{"kind": kind, "count": count} for kind, count in units]}


def timeline(data, expected, label, defn, rules, ops):
    """One scripted run of CampBrain on both sides: the group after every call."""
    group = sr.cb_new_group(defn, 0.0)
    rows = []
    for op in ops:
        if op["kind"] == "step":
            step = {"now": op["now"], "members": [{"at": tuple(m["at"]), "post": dict(m["post"], at=tuple(m["post"]["at"]))}
                                                  for m in op["members"]],
                    "targets": [{"userId": t["userId"], "root": tuple(t["root"]), "rest": t["rest"]}
                                for t in op["targets"]],
                    "shooters": [{"at": tuple(s["at"]), "reach": s["reach"]} for s in op["shooters"]],
                    "striking": op["striking"], "closing": op.get("closing") is True}
            ret = sr.cb_step(group, step, rules)
        elif op["kind"] == "release":
            sr.cb_release(group, op["now"])
            ret = None
        elif op["kind"] == "forget":
            ret = sr.cb_forget(group, op["now"])
        else:
            ret = sr.cb_struck(group, op["by"], op["now"])
        rows.append({"ret": ret if ret is not None else "nil", "group": group_row(group)})
    case = f"camp.timeline.{len(data['campCases'])}"
    data["campCases"].append({"id": case, "op": "timeline", "def": def_row(defn), "ops": ops})
    expected[case] = ("CampBrain.Step: scripted timelines", label, plain(rows))


def grid_camp_cases(data, expected, rules):
    """CampBrain on grid groups: Posts for many counts, the rules on each posture, Step's
    timelines and Problems."""
    square = [(-20.0, -20.0), (20.0, -20.0), (20.0, 20.0), (-20.0, 20.0)]
    grids = [grid_def("patrol", square), grid_def("patrol", [(-10.0, 0.0), (10.0, 0.0)]),
             grid_def("fire", [(5.0, -5.0)], radius=4.0), grid_def("guard", [(0.0, -25.0), (6.0, -25.0)], yaw=math.pi / 2),
             grid_def("guard", [(0.0, 25.0)], yaw=-2.5, held=True), grid_def("tent", [(-6.0, 4.0)], radius=8.0)]
    for defn in grids:
        for count in range(1, 8):
            case = f"camp.posts.grid.{defn['posture']}.{len(data['campCases'])}"
            data["campCases"].append({"id": case, "op": "posts", "def": def_row(defn), "count": count})
            expected[case] = ("CampBrain.Posts", f"grid {defn['posture']} of {len(defn['points'])} points, {count}",
                              plain(sr.cb_posts(defn, count)))
        camp_cases(data, expected, f"grid {defn['posture']}", defn, rules)
    # Step timelines.
    fire = grids[2]
    posts = sr.cb_posts(fire, 3)
    home = [{"at": list(p["at"]), "post": post_row(p)} for p in posts]
    away = [{"at": [p["at"][0] + 5.0, 8.0, p["at"][2]], "post": post_row(p)} for p in posts]
    sight = sr.cb_posture(fire, rules)["sight"]
    rise = sr.cb_posture(fire, rules)["rise"]
    leash = rules["leashSeconds"]
    far = {"userId": 1, "root": [5.0, 11.0, -5.0 - 4.0 - sight - 1.0], "rest": 11.0}
    near = {"userId": 1, "root": [5.0, 11.0, -5.0 - 4.0 - sight + 1.0], "rest": 11.0}
    out = {"userId": 1, "root": [0.0, 11.0, -30.0 - rules["chaseMargin"] - 5.0], "rest": 11.0}

    def step(now, members, targets, striking=False):
        return {"kind": "step", "now": now, "members": members, "targets": targets, "shooters": [],
                "striking": striking}

    t = 0.0
    ops = [step(0.0, home, [far]), step(0.25, home, [near]), step(0.5, home, [near]), step(rise, home, [near]),
           step(0.25 + rise, home, [near]), step(0.25 + rise + 1e-7, home, [near]), step(2.0 + rise, home, [near]),
           step(2.0 + rise + leash - 1e-3, home, [out]), step(2.5 + rise, away, [out]),
           step(2.5 + rise + leash, away, [out], striking=True), step(2.6 + rise + leash, away, [out]),
           {"kind": "struck", "by": 1}, step(3.0 + rise + leash, away, [near]), step(3.5 + rise + leash, home, [near]),
           step(4.0 + rise + leash, home, [far]), {"kind": "struck", "by": 2}, step(4.5 + rise + leash, home, [far]),
           step(4.5 + rise + leash, [], [near])]
    for op in ops:
        if op["kind"] == "struck":
            op["now"] = ops[ops.index(op) - 1]["now"]
    timeline(data, expected, "fire: sight, rise, fight, the leash held while striking, home, rest, a hit wakes", fire,
             rules, ops)
    held = grids[4]
    hposts = sr.cb_posts(held, 1)
    hmembers = [{"at": list(p["at"]), "post": post_row(p)} for p in hposts]
    hnear = {"userId": 1, "root": [0.0, 11.0, 24.0], "rest": 11.0}
    ops = [step(0.0, hmembers, [hnear]), {"kind": "struck", "by": 1, "now": 0.25}, step(0.5, hmembers, [hnear]),
           {"kind": "release", "now": 0.75}, step(0.75, hmembers, [hnear]), step(1.0, hmembers, [hnear]),
           {"kind": "release", "now": 1.25}, step(1.25, hmembers, [hnear])]
    timeline(data, expected, "guard held: ignores sight and hits, released, rise 0", held, rules, ops)
    patrol = grids[0]
    pposts = sr.cb_posts(patrol, 3)
    pmembers = [{"at": list(p["at"]), "post": post_row(p)} for p in pposts]
    sights = [{"userId": 2, "root": [0.0, 11.0, 0.0], "rest": 11.0}, {"userId": 5, "root": [0.0, 11.0, 90.0], "rest": 11.0}]
    ops = [step(0.0, pmembers, [sights[1]]), step(0.5, pmembers, sights), step(0.5, pmembers, sights),
           step(1.0, pmembers, [sights[1]]), step(1.0 + leash, pmembers, [sights[1]]),
           step(1.0 + leash, pmembers, [sights[1]])]
    timeline(data, expected, "patrol: two targets, one out of play; one transition a call", patrol, rules, ops)
    # Engaged: the hold (fix round, crowd Minor 1), its edge either side, never, and a hold of 0.
    hold = rules["engagedHoldSeconds"]
    rows = [{"lastAt": "nil", "now": 5.0}] + [{"lastAt": 4.0, "now": 4.0 + d} for d in
                                              (0.0, 0.5, hold - EDGE, hold, hold + 1e-6 - EDGE, hold + 1e-6 + EDGE,
                                               hold + 0.25, 60.0)]
    case = f"camp.engaged.{len(data['campCases'])}"
    data["campCases"].append({"id": case, "op": "engaged", "rows": rows})
    expected[case] = ("CampBrain.Engaged", f"hold {hold:g} s, {len(rows)} rows",
                      [sr.cb_engaged(None if r["lastAt"] == "nil" else r["lastAt"], r["now"], rules) for r in rows])
    # Problems: how many lines, on rules broken one key at a time.
    broken = [("as shipped", lambda r: None), ("no camps", lambda r: r.clear()), ("no guard", lambda r: r.pop("guard")),
              ("a sight of 0", lambda r: r["fire"].__setitem__("sight", 0)),
              ("a cone of 0", lambda r: r["guard"].__setitem__("cone", 0)),
              ("a cone of 361", lambda r: r["guard"].__setitem__("cone", 361)),
              ("a rise of -1", lambda r: r["fire"].__setitem__("rise", -1)),
              ("a homeTolerance of 0", lambda r: r.__setitem__("homeTolerance", 0)),
              ("a leash that is text", lambda r: r.__setitem__("leashSeconds", "3")),
              ("no sightAbove", lambda r: r.pop("sightAbove")),
              ("no engagedHoldSeconds", lambda r: r.pop("engagedHoldSeconds")),
              ("an engagedHoldSeconds of -1", lambda r: r.__setitem__("engagedHoldSeconds", -1)),
              ("no tent", lambda r: r.pop("tent")), ("a tent sight of 0", lambda r: r["tent"].__setitem__("sight", 0)),
              ("a joinFactor of 0", lambda r: r.__setitem__("joinFactor", 0)), ("no joinFactor", lambda r: r.pop("joinFactor")),
              ("no dormantRadius", lambda r: r.pop("dormantRadius")),
              ("a dormantRadius at the guard's sight", lambda r: r.__setitem__("dormantRadius", r["guard"]["sight"])),
              ("a dormantRadius just above every sight",
               lambda r: r.__setitem__("dormantRadius", max(r[p]["sight"] for p in sr.CB_POSTURES) + 1e-6)),
              ("a dormantRadius under the fire's sight", lambda r: r.__setitem__("dormantRadius", r["fire"]["sight"] - 1)),
              ("no chaseSight", lambda r: r.pop("chaseSight")), ("a chaseSight of 0", lambda r: r.__setitem__("chaseSight", 0)),
              ("a hitMemorySeconds of -1", lambda r: r.__setitem__("hitMemorySeconds", -1)),
              ("a hitMemorySeconds of 0", lambda r: r.__setitem__("hitMemorySeconds", 0)),
              ("a meleeAbove of 0", lambda r: r.__setitem__("meleeAbove", 0)), ("no meleeAbove", lambda r: r.pop("meleeAbove")),
              # The fix round's R14: meleeBelow must be a finite number, not negative; 0 is allowed.
              ("no meleeBelow", lambda r: r.pop("meleeBelow")),
              ("a meleeBelow that is text", lambda r: r.__setitem__("meleeBelow", "1.5")),
              ("a meleeBelow of -0.5", lambda r: r.__setitem__("meleeBelow", -0.5)),
              ("a meleeBelow of 0", lambda r: r.__setitem__("meleeBelow", 0))]
    for label, change in broken:
        changed = copy.deepcopy(rules)
        change(changed)
        case = f"camp.problems.{len(data['campCases'])}"
        data["campCases"].append({"id": case, "op": "problems", "rules": changed})
        expected[case] = ("CampBrain.Problems: how many lines", label, len(sr.cb_problems(changed)))


# ---------------------------------------------------------------------------------------------
# L1b Wave 4: Region, the region group's rules, Fielded
# ---------------------------------------------------------------------------------------------


def rect(x0, x1, z0, z1):
    return {"x": (x0 + x1) / 2, "z": (z0 + z1) / 2, "hx": (x1 - x0) / 2, "hz": (z1 - z0) / 2}


def region_sets(raw_layouts):
    """The shipped regions and the hand-built grids: [(label, cells, well formed?)]."""
    found = []
    for name, layout in sorted(raw_layouts.items()):
        for region in layout.get("regions") or []:
            found.append((f"{name} {region['id']}", sr.region_cells(layout, region), True))
    u_bend = [rect(-179, -122, -52, -36), rect(-138, -122, -52, 8), rect(-138, -100, -8, 8), rect(-116, -100, -52, 8),
              rect(-116, -70, -52, -36)]
    found += [("an L of two cells", [rect(0, 40, 0, 16), rect(24, 40, 0, 50)], True),
              ("the U-bend of RoadAB1-5 (as the blocks stand)", u_bend, True),
              ("a single cell", [rect(-20, 30, -8, 8)], True),
              ("a cycle of three", [rect(0, 30, 0, 10), rect(20, 30, 0, 30), rect(0, 30, 20, 30)], False),
              ("a gap", [rect(0, 20, 0, 10), rect(25, 45, 0, 10)], False),
              ("a door 4.8 on x", [rect(0, 20, 0, 16), rect(15.2, 40, 0, 16)], False),
              ("a door 4.8 on z", [rect(0, 20, 0, 16), rect(0, 20, 11.2, 30)], False),
              ("touching cells", [rect(0, 20, 0, 16), rect(20, 40, 0, 16)], False),
              ("a bad cell", [rect(0, 20, 0, 16), {"x": 30.0, "z": 8.0, "hx": 0.0, "hz": 8.0}, rect(10, 30, 0, 16)], False),
              ("no cells", [], False)]
    return found


def region_points(cells, step=REGION_STEP, margin=12.0):
    if not cells:
        return [(0.0, 0.0)]
    good = [c for c in cells if sr.rg_cell_ok(c)]
    x0 = min(c["x"] - c["hx"] for c in good) - margin
    x1 = max(c["x"] + c["hx"] for c in good) + margin
    z0 = min(c["z"] - c["hz"] for c in good) - margin
    z1 = max(c["z"] + c["hz"] for c in good) + margin
    points = [(x0 + step * i, z0 + step * k) for i in range(int((x1 - x0) / step) + 1)
              for k in range(int((z1 - z0) / step) + 1)]
    # Every cell's corners and edges, a hair either side, and every door's centre.
    for c in good:
        for sx in (-1, 1):
            for sz in (-1, 1):
                for d in (-1e-7, 0.0, 1e-7):
                    points.append((c["x"] + sx * (c["hx"] + d), c["z"] + sz * (c["hz"] + d)))
    return points


def region_cases(data, expected, raw_layouts):
    """Region (L1b-W4-14 to -17) on the shipped regions and the grids: Build, Problems, and on the
    well-formed ones Distance, Inside and Clamp on a point grid at several radii, Runway on rays
    from inside in REGION_HEADINGS directions, Toward on seeded pairs and every door."""
    import random

    rng = random.Random(REGION_SEED)
    for label, cells, good in region_sets(raw_layouts):
        rows = [[c.get("x"), c.get("z"), c.get("hx"), c.get("hz")] for c in cells]
        case = f"region.build.{len(data['regionCases'])}"
        data["regionCases"].append({"id": case, "op": "build", "cells": rows})
        expected[case] = ("Region.Build", label, graph_row(sr.rg_build(cells)))
        case = f"region.problems.{len(data['regionCases'])}"
        data["regionCases"].append({"id": case, "op": "problems", "cells": rows, "minDoor": MIN_DOOR})
        expected[case] = ("Region.Problems: how many lines", f"{label} (door {MIN_DOOR:g})",
                          len(sr.rg_problems(cells, MIN_DOOR)))
        if not good:
            continue
        points = region_points(cells)
        case = f"region.distance.{len(data['regionCases'])}"
        data["regionCases"].append({"id": case, "op": "distance", "cells": rows, "points": [list(p) for p in points]})
        expected[case] = ("Region.Distance", f"{label}, {len(points)} points", [sr.rg_distance(cells, x, z) for x, z in points])
        triples = [[x, 8.0, z, r] for x, z in points for r in REGION_RADII]
        case = f"region.inside.{len(data['regionCases'])}"
        data["regionCases"].append({"id": case, "op": "inside", "cells": rows, "rows": triples})
        expected[case] = ("Region.Inside", f"{label}, {len(triples)} points and radii",
                          [sr.rg_inside(cells, (x, y, z), r) for x, y, z, r in triples])
        case = f"region.clamp.{len(data['regionCases'])}"
        data["regionCases"].append({"id": case, "op": "clamp", "cells": rows, "rows": triples})
        expected[case] = ("Region.Clamp", f"{label}, {len(triples)} points and radii",
                          [list(sr.rg_clamp(cells, (x, y, z), r)) for x, y, z, r in triples])
        rays = []
        inside = [p for p in points if sr.rg_inside(cells, (p[0], 0.0, p[1]), 0.0)][::3] + [(c["x"], c["z"]) for c in cells]
        for x, z in inside:
            for k in range(REGION_HEADINGS):
                a = 2 * math.pi * k / REGION_HEADINGS
                for r in (0.0, 1.3, 2.2):
                    rays.append([x, 8.0, z, math.cos(a), math.sin(a), r])
            rays.append([x, 8.0, z, 0.0, 0.0, 1.3])
        case = f"region.runway.{len(data['regionCases'])}"
        data["regionCases"].append({"id": case, "op": "runway", "cells": rows, "rows": rays})
        expected[case] = ("Region.Runway", f"{label}, {len(rays)} rays",
                          [sr.rg_runway(cells, (x, y, z), (hx, hz), r) for x, y, z, hx, hz, r in rays])
        graph = sr.rg_build(cells)
        pairs = []
        for _ in range(REGION_TOWARD):
            f, g = rng.choice(points), rng.choice(points)
            pairs.append([f[0], 8.0, f[1], g[0], 3.0, g[1], rng.choice((0.0, 1.3, 2.2))])
        for i, row in graph["doors"].items():
            for j, (dx, dz) in row.items():
                c = cells[j - 1]
                pairs.append([dx, 8.0, dz, c["x"], 8.0, c["z"], 1.3])  # standing in a door: on to the next
        case = f"region.toward.{len(data['regionCases'])}"
        data["regionCases"].append({"id": case, "op": "toward", "cells": rows, "rows": pairs})
        found = []
        for fx, fy, fz, gx, gy, gz, r in pairs:
            point, through = sr.rg_toward(graph, (fx, fy, fz), (gx, gy, gz), r)
            found.append([list(point), through])
        expected[case] = ("Region.Toward", f"{label}, {len(pairs)} (from, goal) pairs", found)


def region_def(units=(("fodder", 3), ("slinger", 1))):
    """A guard group on the L's first cell (y 8), its region the L."""
    cells = [rect(0, 40, 0, 16), rect(24, 40, 0, 50)]
    defn = {"id": "grid.region", "camp": "G", "floor": 1, "floorY": 8.0, "rect": dict(cells[0]), "posture": "guard",
            "points": [(10.0, 8.0, 8.0), (14.0, 8.0, 8.0), (18.0, 8.0, 8.0), (22.0, 8.0, 8.0)], "yaw": 0.0,
            "radius": 0.0, "held": False, "units": [{"kind": k, "count": n} for k, n in units], "region": cells}
    return defn


def wave4_camp_cases(data, expected, rules, raw_layouts):
    """CampBrain's Wave 4 rules (L1b-W4-18 to -28) on a region group (the L) and on the shipped
    groups: Melee and Reachable on grids round the region's edges, corners and the height band,
    StandsDown's truth table, Forget in every state, and Step timelines."""
    defn = region_def()
    row = def_row(defn)
    margin, above = rules["chaseMargin"], rules["meleeAbove"]
    below = rules["meleeBelow"]  # the fix round's R14: Melee's lower bound, either side of its edge
    heights = [8.0 - rules["sightBelow"] - EDGE, 8.0 - rules["sightBelow"], 8.0 - below - EDGE, 8.0 - below,
               8.0 - below + EDGE, 8.0, 11.0, 8.0 + above - EDGE, 8.0 + above,
               8.0 + above + EDGE, 8.0 + rules["sightAbove"], 8.0 + rules["sightAbove"] + EDGE]
    xs = [-margin - EDGE, -margin, 0.0, 12.0, 24.0, 32.0, 40.0, 40.0 + margin, 40.0 + margin + EDGE]
    zs = [-margin - EDGE, -margin, 8.0, 16.0, 16.0 + margin, 16.0 + margin + EDGE, 30.0, 50.0 + margin, 50.0 + margin + EDGE]
    targets = [{"userId": 1, "root": [x, y, z]} for x in xs for z in zs for y in heights]
    # The rounded corner off the L's inner and outer corners, either side of chaseMargin.
    for cx, cz, sx, sz in ((40.0, 0.0, 1, -1), (0.0, 16.0, -1, 1), (24.0, 50.0, -1, 1), (40.0, 50.0, 1, 1)):
        for d in (margin - EDGE, margin + EDGE):
            targets.append({"userId": 1, "root": [cx + sx * d / math.sqrt(2), 11.0, cz + sz * d / math.sqrt(2)]})
    shooter = {"at": [30.0, 8.0, 30.0], "reach": 32.0}
    targets += ring((30.0, 8.0, 30.0), 0.0, [32.0 - EDGE, 32.0, 32.0 + EDGE], list(CB_ANGLES), [11.0, 8.0 + above + 5])
    for t in targets:  # R16: a standing player rests where his root is
        t["rest"] = t["root"][1]
    # R16: Melee judges height on the surface last stood on, not the live root: mid-hop from 5
    # under the floor (root 10, rest 3) is not melee; mid-jump from the floor (root 21, rest 11)
    # is; and the reverse of each, on the same spots.
    targets += [{"userId": 1, "root": [12.0, 10.0, 8.0], "rest": 3.0},
                {"userId": 1, "root": [12.0, 21.0, 8.0], "rest": 11.0},
                {"userId": 1, "root": [12.0, 3.0, 8.0], "rest": 10.0},
                {"userId": 1, "root": [12.0, 11.0, 8.0], "rest": 21.0}]
    for op in ("melee", "reachable"):
        for shooters in ([], [shooter]):
            if op == "melee" and shooters:
                continue
            case = f"camp.{op}.{len(data['campCases'])}"
            data["campCases"].append({"id": case, "op": op, "def": row, "targets": targets, "shooters": shooters})
            theirs = [{"at": tuple(s["at"]), "reach": s["reach"]} for s in shooters]
            answer = [sr.cb_melee(defn, {"userId": 1, "root": tuple(t["root"]), "rest": t["rest"]}, rules)
                      if op == "melee" else
                      sr.cb_reachable(defn, {"userId": 1, "root": tuple(t["root"]), "rest": t["rest"]}, theirs, rules)
                      for t in targets]
            expected[case] = (f"CampBrain.{op.capitalize()}", f"the L's guard, {len(shooters)} shooter(s), "
                              f"{len(targets)} targets", answer)
    # Melee and Reachable on a shipped region group too (the plateau), at the perches' heights.
    for name, layout in sorted(raw_layouts.items()):
        for region in layout.get("regions") or []:
            cells = sr.region_cells(layout, region)
            shipped = dict(region_def(), region=cells, floorY=region["y"])
            spots = [(-283.0, 37.0, -59.0), (-283.0, 11.0, -44.0), (-324.0, 3.0, -44.0), (100.0, 21.0, -4.0),
                     (200.0, 11.0, -44.0), (200.5 + margin, 11.0, -44.0), (-130.0, 11.0, -22.0), (-119.0, 11.0, -22.0)]
            case = f"camp.melee.{name}.{len(data['campCases'])}"
            tg = [{"userId": 1, "root": list(p), "rest": p[1]} for p in spots]
            data["campCases"].append({"id": case, "op": "melee", "def": def_row(shipped), "targets": tg, "shooters": []})
            expected[case] = ("CampBrain.Melee", f"{name} {region['id']}: the ledge, the road, below the drop, the "
                              f"cache, the east end, the U-bend's void",
                              [sr.cb_melee(shipped, {"userId": 1, "root": p, "rest": p[1]}, rules) for p in spots])
    # StandsDown's truth table.
    rows = []
    found = []
    for state in ("rest", "rise", "fight", "home"):
        for held in (False, True):
            for down in (False, True):
                for rusher in (False, True):
                    group = sr.cb_new_group(defn, 0.0)
                    group["state"], group["held"], group["standDown"] = state, held, down
                    rows.append([state, held, down, rusher])
                    found.append(sr.cb_stands_down(group, rusher))
    case = f"camp.standsDown.{len(data['campCases'])}"
    data["campCases"].append({"id": case, "op": "standsDown", "def": row, "rows": rows})
    expected[case] = ("CampBrain.StandsDown", f"{len(rows)} combinations", found)
    # Forget in every state, its sets full.
    for state, held in (("rest", False), ("rest", True), ("rise", False), ("fight", False), ("home", False),
                        ("fight", True)):
        group = sr.cb_new_group(defn, 0.0)
        group["state"], group["held"], group["standDown"] = state, held, True
        group["known"][1] = group["reachable"][1] = group["struckBy"][2] = True
        group["hitAt"][2] = 1.5
        ret = sr.cb_forget(group, 3.25)
        case = f"camp.forget.{len(data['campCases'])}"
        data["campCases"].append({"id": case, "op": "forget", "def": row, "state": state, "held": held})
        expected[case] = ("CampBrain.Forget", f"{state}{' held' if held else ''}",
                          {"ret": ret if ret is not None else "nil", "group": group_row(group)})
    # Step timelines on the region group.
    posts = sr.cb_posts(defn, 4)
    home = [{"at": list(p["at"]), "post": post_row(p)} for p in posts]
    out_east = [{"at": [p["at"][0] + 18.0, 8.0, p["at"][2]], "post": post_row(p)} for p in posts]
    sight, leash, memory = rules["chaseSight"], rules["leashSeconds"], rules["hitMemorySeconds"]
    rise = sr.cb_posture(defn, rules)["rise"]

    def step(now, members, targets, striking=False, closing=False, shooters=()):
        return {"kind": "step", "now": now, "members": members, "targets": targets, "shooters": list(shooters),
                "striking": striking, "closing": closing}

    def at(x, y, z, user=1, rest=None):
        return {"userId": user, "root": [x, y, z], "rest": y if rest is None else rest}

    edge = posts[3]["at"][0] + sight  # the last post's chaseSight, east along z 8
    t = 0.0
    ops = [step(t, home, [at(10.0, 11.0, 8.0)]), step(t + rise + 0.05, home, [at(10.0, 11.0, 8.0)])]
    # Known by sight to the edge and past it; the leash held by closing, then let go; home.
    t = 2.0
    ops += [step(t, home, [at(edge, 11.0, 8.0)]), step(t + 0.5, home, [at(edge + EDGE, 11.0, 8.0)], closing=True),
            step(t + 0.5 + leash, home, [at(edge + EDGE, 11.0, 8.0)], closing=True),
            step(t + 1.0 + leash, home, [at(edge + EDGE, 11.0, 8.0)]),
            step(t + 1.0 + 2 * leash - 1e-3, out_east, [at(edge + EDGE, 11.0, 8.0)]),
            step(t + 1.0 + 2 * leash, out_east, [at(edge + EDGE, 11.0, 8.0)], striking=True),
            step(t + 1.1 + 2 * leash, out_east, [at(edge + EDGE, 11.0, 8.0)])]
    # Home, away from its posts: a hit from an unreachable player (below the drop) lands and does not
    # turn it back; a reachable one does; then known by the hit memory to its edge and past it.
    t = t + 2.0 + 2 * leash
    ops += [{"kind": "struck", "by": 3, "now": t}, step(t, out_east, [at(-10.0, 3.0, 8.0, 3)]),
            step(t + 0.1, out_east, [at(-10.0, 3.0, 8.0, 3), at(44.0, 11.0, 47.0, 2)]),
            {"kind": "struck", "by": 1, "now": t + 0.25}, step(t + 0.25, out_east, [at(30.0, 11.0, 40.0)]),
            step(t + 0.25 + memory, home, [at(30.0, 11.0, 70.0)]),
            step(t + 0.25 + memory + 2e-6, home, [at(30.0, 11.0, 70.0)])]
    # The stand-down: a player on a perch only the slinger reaches; closing holds it, then leashSeconds.
    t = t + 1.0 + memory
    perch = at(30.0, 8.0 + above + 6.0, 20.0)
    gun = [{"at": [30.0, 8.0, 14.0], "reach": 32.0}]
    ops += [{"kind": "struck", "by": 1, "now": t}, step(t, out_east, [perch], shooters=gun),
            step(t + 0.5, out_east, [perch], closing=True, shooters=gun),
            step(t + 0.5 + leash - 1e-3, out_east, [perch], shooters=gun),
            step(t + 0.5 + leash, out_east, [perch], shooters=gun), step(t + 0.6 + leash, out_east, [perch], shooters=gun),
            step(t + 0.7 + leash, out_east, [at(30.0, 11.0, 14.0)], shooters=gun),
            step(t + 0.8 + leash, out_east, [perch], shooters=gun),
            step(t + 0.8 + 2 * leash, out_east, [perch], shooters=gun),
            step(t + 0.9 + 2 * leash, out_east, [perch]),
            step(t + 0.9 + 3 * leash, out_east, [perch]),
            step(t + 1.0 + 3 * leash, home, [at(30.0, 11.0, 70.0)]),
            {"kind": "struck", "by": 0, "now": t + 1.1 + 3 * leash}, step(t + 1.1 + 3 * leash, home, [at(30.0, 11.0, 70.0)]),
            {"kind": "forget", "now": t + 1.2 + 3 * leash}, step(t + 1.3 + 3 * leash, [], [])]
    timeline(data, expected, "region guard: known by sight and by memory, the leash held by closing, home's "
             "turn-back, the stand-down, a lever's hit, Forget", defn, rules, ops)
    # The fix round's R2: sent home by Forget with a blow in the air, all at their posts, the group
    # rests only once no member strikes.
    ops = [step(0.0, home, [at(10.0, 11.0, 8.0)]), step(rise + 0.05, home, [at(10.0, 11.0, 8.0)]),
           {"kind": "forget", "now": 1.0}, step(1.1, home, [], striking=True), step(1.2, out_east, [], striking=True),
           step(1.3, home, [], striking=True), step(1.4, home, [])]
    timeline(data, expected, "region guard: home rests only when no member strikes (R2)", defn, rules, ops)
    # The fix round's R16: Melee and Reachable on the rest sample in a step: mid-jump from the floor
    # (root 21, rest 11) and mid-hop from under it (root 10, rest 3), on the same spot.
    ops = [step(0.0, home, [at(10.0, 11.0, 8.0)]), step(rise + 0.05, home, [at(10.0, 11.0, 8.0)]),
           step(rise + 0.1, home, [at(12.0, 21.0, 8.0, rest=11.0)]), step(rise + 0.2, home, [at(12.0, 10.0, 8.0, rest=3.0)]),
           {"kind": "struck", "by": 1, "now": rise + 0.3}, step(rise + 0.3, out_east, [at(12.0, 10.0, 8.0, rest=3.0)]),
           step(rise + 0.4, out_east, [at(12.0, 21.0, 8.0, rest=11.0)]),
           step(rise + 0.5, out_east, [at(12.0, 10.0, 8.0, rest=3.0)], shooters=gun)]
    timeline(data, expected, "region guard: Melee on the surface last stood on (R16)", defn, rules, ops)


def fielded_cases(data, expected, files, rules, ranks, crowd_kinds):
    """StageFlow.Fielded (L1b-W4-30) on every open camp of the shipped plans: no tent, nothing sent,
    some, the whole stock and past it."""
    for number, file in enumerate(files, 1):
        level = sr.resolve_level(file, 0)
        if level is None or not level.get("camps"):
            continue
        layout = sr.load_level_layout(file["layout"])
        for difficulty in level["difficulties"]:
            plan = sr.plan_level(level, layout, difficulty, rules, ranks, crowd_kinds)
            if plan is None:
                continue
            for zone in plan["zones"]:
                t = next((k for k, tent in enumerate(plan["tents"], 1) if tent["zone"] == zone["floor"]), None)
                # The fix round's R12: `refused` (stock indices the crowd refused) is never priced.
                for sent in (0, 3, 99, -1):
                    for with_tent in ((True, False) if t is not None else (False,)):
                        for refused in (None, [1], [2, 3], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], [99]):
                            tent = plan["tents"][t - 1] if with_tent else None
                            case = f"flow.fielded.{len(data['fieldedCases'])}"
                            data["fieldedCases"].append({"id": case, "level": number, "difficulty": difficulty,
                                                         "zone": zone["floor"], "tent": t if with_tent else 0,
                                                         "sent": sent, "refused": refused})
                            expected[case] = ("StageFlow.Fielded", f"{file['id']} {difficulty} {zone['id']}"
                                              f"{' with its tent' if with_tent else ''}, sent {sent}, refused {refused}",
                                              sr.fielded(zone, tent, sent, set(refused) if refused else None))


def split_cases(data, expected):
    """Combat.SplitCarry over seeded sequences of kills: the payments and every carry after each."""
    import random

    rng = random.Random(CB_SPLIT_SEED)
    for run in range(4):
        members = list(range(1, run + 2))
        mults = [[u, rng.choice((1, 1.5, 2, 1.25))] for u in members] if run % 2 == 1 else None
        carry = {}
        calls, rows = [], []
        for _call in range(CB_SPLIT_CALLS):
            pool = {"cash": rng.choice((0, 100, 500, 700, 1200, 2000, 29000)) * rng.choice((1, 2, 4)),
                    "materials": rng.choice((0, 1, 2, 4, 6, 70)), "valor": rng.choice((0, 0, 10, 40))}
            weights = {u: rng.random() for u in members if rng.random() < 0.8}
            total = sum(weights.values())
            shares = {u: w / total for u, w in weights.items()} if total > 0 else {}
            if rng.random() < 0.05 and members:
                shares[members[-1]] = -0.5  # a bad share: pays nothing, the carry stays
            paid = sc.split_carry(pool, shares, carry, dict(mults) if mults is not None else None)
            calls.append({"pool": pool, "shares": [[u, v] for u, v in shares.items()], "mults": mults})
            rows.append({"paid": [[u, p["cash"], p["materials"], p["valor"]] for u, p in sorted(paid.items())],
                         "carry": [[u, c["cash"], c["materials"], c["valor"]] for u, c in sorted(carry.items())]})
        case = f"split.{run}"
        data["splitCases"].append({"id": case, "calls": calls})
        expected[case] = ("Combat.SplitCarry: seeded kills, the carry after each", f"{len(members)} member(s)"
                          + (", cash multipliers" if mults else ""), rows)


# ---------------------------------------------------------------------------------------------
# L3 W1: the Armory's tier rules and the first clear
# ---------------------------------------------------------------------------------------------


def starters_of(proving):
    """Unlocks.Starters: the config loadout's two family ids, a set."""
    loadout = proving.get("loadout") or {}
    return {family for family in (loadout.get("melee"), loadout.get("ranged")) if isinstance(family, str) and family}


# Forest Road's Hard first clear changed, for Validate's lines (L3-17). Accepted ones first.
def first_clear_change(reward):
    def apply(f, l, r):
        f["difficulties"]["hard"]["firstClear"] = copy.deepcopy(reward)
    return apply


L3_ACCEPTED = (
    ("a first clear of the Warhammer", first_clear_change({"family": "warhammer"})),
    ("a first clear of a family and Valor", first_clear_change({"family": "greataxe", "valor": 3})),
    ("a first clear of 0 Valor", first_clear_change({"valor": 0})),
    ("a first clear that gives nothing", first_clear_change({})),
)
L3_REFUSALS = (
    ("a first clear that is a string", first_clear_change("warhammer")),
    ("a first-clear family that is a number", first_clear_change({"family": 5})),
    ("an empty first-clear family", first_clear_change({"family": ""})),
    ("a first-clear family of 25 characters", first_clear_change({"family": "f" * 25})),
    ("a first-clear family that is no weapons family", first_clear_change({"family": "nope"})),
    ("a first clear of a starter", first_clear_change({"family": "broadsword"})),
    ("a first-clear Valor of 2.5", first_clear_change({"valor": 2.5})),
    ("a first-clear Valor of -1", first_clear_change({"valor": -1})),
    ("a first-clear Valor that is a string", first_clear_change({"valor": "25"})),
)


# The L4 W3 fix round's F6 and F18: a difficulty's `note` is display only. A bad one is dropped (one
# warn) and the level stays playable: Validate accepts each copy on both sides, StageFlow.Notes keeps
# exactly sim_range.kept_notes and drops as many as sim_range.note_problems names. (label, the notes
# set on a copy of the shipped level file, the number the Python must drop: a case that drops none
# where one is broken would prove nothing about a rule removed from both.)
NOTE_CASES = (
    ("as shipped", {}, 0),
    ("a note of 24 bytes", {"brutal": "n" * 24}, 0),
    ("a note of 25 bytes", {"brutal": "n" * 25}, 1),
    ("an empty note", {"brutal": ""}, 1),
    ("a note that is a number", {"brutal": 5}, 1),
    ("a note that is true", {"brutal": True}, 1),
    ("a note that is a table", {"brutal": {"text": "Castle gear"}}, 1),
    ("a kept note beside a dropped one", {"normal": "Start here", "hard": "h" * 30}, 1),
)
NOTE_DIFFICULTIES = ("normal", "hard", "brutal")
NOTE_KIND = "F6: a bad note is dropped, the level kept (StageFlow.Notes, Validate)"


def armory_python(op, cfg, row, families):
    """sim_combat's answer to one row, in the shape the Luau driver prints ("none" for a nil)."""
    combats = ARMORY_COMBATS
    if op == "ladderSize":
        return sc.ladder_size(cfg)
    if op == "window":
        found = sc.window(cfg, row[0])
        return "none" if found is None else list(found)
    if op == "tierOf":
        return sc.tier_of(cfg, combats[row[0] - 1], row[1])
    if op == "multiplier":
        return sc.multiplier(cfg, row[0])
    if op == "damageScale":
        return sc.damage_scale(cfg, row[0], row[1], row[2])
    if op == "weaponHp":
        return sc.weapon_hp(cfg, row[0], row[1], row[2])
    if op == "maxHp":
        return sc.max_hp(cfg, {"melee": row[0], "ranged": row[1]}, {"melee": row[2], "ranged": row[3]})
    if op == "rangeHp":
        return sc.range_hp(cfg)
    if op == "bandOf":
        return list(sc.band_of(cfg, row[0]))
    if op == "nextTier":
        found = sc.next_tier(cfg, combats[row[0] - 1], row[1])
        return "none" if found is None else found
    if op == "tierCost":
        return list(sc.tier_cost(cfg, row[0]))
    if op == "preview":
        return list(sc.preview(cfg, row[0], row[1], row[2]))
    if op == "upgradeVerdict":
        built = {level: True for level in ARMORY_BUILT[row[4] - 1]}
        found = sc.upgrade_verdict(cfg, copy.deepcopy(combats[row[0] - 1]), row[1], row[2], row[3], built)
        return "none" if found is None else found
    if op == "legacyRefund":
        return sc.legacy_refund(cfg, {"melee": row[0], "ranged": row[1]})
    if op == "problems":
        return bool(sc.problems(cfg, families))
    if op == "setTier":
        combat = copy.deepcopy(combats[row[0] - 1])
        written = sc.set_tier(cfg, combat, row[1], row[2])
        return ["none" if written is None else written, combat.get("tiers") or {}]
    if op == "builtBands":
        levels, materials = sc.built_bands(cfg, {level: True for level in ARMORY_BUILT[row[0] - 1]})
        return [levels, materials]
    if op == "starHeld":
        return sc.star_held(cfg, combats[row[0] - 1], row[1])
    raise ValueError(op)


def armory_cases(data, expected, report, proving):
    """The new pure Armory (L3-27) against sim_combat's mirror, op by op: the shipped Armory.json, one
    without a ladder and two edge copies, over the grids above; Problems on ARMORY_BREAKS."""
    armory = sc.load_armory_config()
    if armory is None:
        report.differ("Armory: the tier rules (L3-1 to L3-8)", "Armory.json is missing")
        return
    families = sorted(proving["weapons"])
    asked = families + ["nope"]
    bare = copy.deepcopy(armory)
    bare.pop("ladder", None)
    narrow = copy.deepcopy(armory)
    narrow["windows"]["broadsword"] = {"start": 1, "top": 6}
    narrow["windows"]["longbow"] = {"start": 7, "top": 12}
    edges = copy.deepcopy(armory)
    windows, ladder = edges["windows"], edges["ladder"]
    windows["rifle"] = {"start": 0, "top": 30}
    windows["smg"] = {"start": 5, "top": 3}
    windows["beam"] = {"start": 2.5, "top": 8}
    windows["chaingun"] = {"start": "3", "top": 8}
    windows.pop("spinblade", None)
    ladder["costs"] = ladder["costs"][:3]
    ladder["bands"][2]["material"] = ""
    ladder["damage"][6] = 0
    ladder["hp"]["ranged"][4] = -5
    ladder["rangeHp"] = 0
    edges["legacy"]["gearCosts"][1] = {"material": "", "amount": 60}
    edges["legacy"]["gearCosts"][2] = {"material": "Timber", "amount": -180}
    ladder["starAlso"] = "brutal"  # a word, not a list: it opens nothing (R1)
    hard_only = copy.deepcopy(armory)
    hard_only["ladder"].pop("starAlso", None)
    configs = [("shipped", armory), ("no ladder", bare), ("narrowed windows", narrow), ("edges", edges),
               ("no starAlso", hard_only)]
    combats = range(1, len(ARMORY_COMBATS) + 1)
    built = range(1, len(ARMORY_BUILT) + 1)
    grids = {
        "ladderSize": [[]],
        "window": [[family] for family in asked],
        "tierOf": [[c, family] for c in combats for family in asked],
        "multiplier": [[tier] for tier in ARMORY_TIERS],
        "damageScale": [[tier, asc, ability] for tier in ARMORY_TIERS for asc in ARMORY_ASCENSION
                        for ability in (False, True)],
        "weaponHp": [[slot, tier, asc] for slot in ("melee", "ranged", "nope") for tier in ARMORY_TIERS
                     for asc in ARMORY_ASCENSION],
        "maxHp": [[tm, tr, am, ar] for tm in (1, 3, 5, 12, 20) for tr in (1, 3, 5, 12, 20) for am in (0, 1)
                  for ar in (0, 2)],
        "rangeHp": [[]],
        "bandOf": [[tier] for tier in ARMORY_TIERS],
        "nextTier": [[c, family] for c in combats for family in asked],
        "tierCost": [[tier] for tier in ARMORY_TIERS],
        "preview": [[slot, tier, base] for slot in ("melee", "ranged", "nope") for tier in (1, 2, 5, 20)
                    for base in ARMORY_BASES],
        "upgradeVerdict": [[c, family, owned, gate, b] for c in combats for family in asked
                           for owned in (False, True) for gate in (False, True) for b in built],
        "legacyRefund": [list(gear) for gear in ARMORY_GEAR],
        "problems": [[]],
        "setTier": [[c, family, tier] for c in (1, 4, 9) for family in asked
                    for tier in (-1, 0, 1, 2, 7, 12, 25, 2.5, 5.6)],
        "builtBands": [[b] for b in built],
        "starHeld": [[c, level] for c in combats for level in ("forestRoad", "castle", "nope")],
    }
    luau_names = {"ladderSize": "LadderSize", "window": "Window", "tierOf": "TierOf",
                  "multiplier": "Multiplier", "damageScale": "DamageScale", "weaponHp": "WeaponHp", "maxHp": "MaxHp",
                  "rangeHp": "RangeHp", "bandOf": "BandOf", "nextTier": "NextTier",
                  "tierCost": "TierCost", "preview": "Preview", "upgradeVerdict": "UpgradeVerdict",
                  "legacyRefund": "LegacyRefund", "problems": "Problems", "setTier": "SetTier",
                  "builtBands": "BuiltBands", "starHeld": "StarHeld"}
    breaks = []
    for label, change in ARMORY_BREAKS:
        broken = copy.deepcopy(armory)
        change(broken)
        breaks.append((f"broken: {label}", broken))
    for index, (name, cfg) in enumerate(configs + breaks, 1):
        data["armoryConfigs"].append(cfg)
        ops = ["problems"] if name.startswith("broken: ") else list(grids)
        for op in ops:
            if not callable(getattr(sc, ARMORY_MIRRORS[luau_names[op]], None)):
                continue
            case = f"armory.{index}.{op}"
            rows = grids[op]
            data["armoryCases"].append({"id": case, "config": index, "op": op, "rows": rows, "families": families})
            answers = []
            for row in rows:
                try:
                    answers.append(plain(armory_python(op, cfg, row, families)))
                except Exception as problem:  # a mirror that throws is a difference, not the end of the run
                    answers.append({"threw": f"{type(problem).__name__}: {problem}"})
            kind = ("Armory.Problems: a broken Armory.json is named alike (L3-5)" if op == "problems"
                    else f"Armory.{luau_names[op]} (L3-1 to L3-8)")
            expected[case] = (kind, f"{name}, {len(rows)} row(s)", answers)


def first_clear_cases(data, expected, report, files, resolved, difficulties):
    """StageFlow.FirstClear against sim_range.first_clear (L3-17): every level at every difficulty
    (and one that does not exist), and Forest Road given each of FIRST_CLEARS at Hard."""
    mirror = getattr(sr, "first_clear", None)
    if not callable(mirror):
        return
    cases = [(file["id"], file) for file in files]
    forest = next((file for file in files if file["id"] == "forestRoad"), None)
    if forest is not None:
        for label, reward in FIRST_CLEARS:
            changed = copy.deepcopy(forest)
            changed["difficulties"]["hard"]["firstClear"] = copy.deepcopy(reward)
            cases.append((f"forestRoad, {label} at Hard", changed))
    for index, (label, file) in enumerate(cases, 1):
        case = f"firstClear.{index}"
        level = resolved(file)
        data["firstClearCases"].append({"id": case, "file": file, "difficulties": list(difficulties)})
        if level is None:
            expected[case] = ("StageFlow.FirstClear (L3-17)", label, "unresolved")
            continue
        answers = []
        for difficulty in difficulties:
            try:
                given = mirror(level, difficulty)
                answers.append("none" if given is None else {
                    "family": given.get("family") if given.get("family") is not None else "none",
                    "valor": given.get("valor") if given.get("valor") is not None else "none"})
            except Exception as problem:
                answers.append({"threw": f"{type(problem).__name__}: {problem}"})
        expected[case] = ("StageFlow.FirstClear (L3-17)", label, answers)


# ---------------------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--luau", default=None, help="the Luau interpreter (default: tools/bin/luau.exe)")
    parser.add_argument("--module", action="append", default=[], metavar="NAME=FILE",
                        help="run another copy of a Luau module (a deliberately broken one)")
    parser.add_argument("--keep", default=None, help="leave the bundle and the Luau's answers in this folder")
    parser.add_argument("--show", type=int, default=6, help="differences listed per kind")
    args = parser.parse_args()

    to_luau, wrap, sources = harness_tools()
    swapped = dict(item.split("=", 1) for item in args.module)
    unknown = [name for name in swapped if name not in MODULES]
    if unknown:
        raise SystemExit(f"check_stage_mirror: --module names {unknown}; the modules are {', '.join(MODULES)}")
    luau = find_luau(args.luau)

    # The files, as they ship.
    cfg = sr.load_config(sr.CONFIG_PATH)
    ctx = sr.level_context()
    combat, expeditions, ranks = ctx["combat"], ctx["expeditions"], ctx["ranks"]
    rules, director = combat["levels"], combat["director"]
    crowd_kinds, crowd_max = cfg["crowd"]["kinds"], cfg["crowd"]["maxAlive"]
    files = sr.load_level_files() + [copy.deepcopy(FIELD_LEVEL)]
    shipped_count = len(files) - 1  # every file but the field's test level
    noted = set()  # the shipped levels NOTE_CASES ran on
    raw_layouts = {path.stem: sr.load_config(path) for path in sorted(sr.LEVEL_LAYOUT_DIR.glob("*.json"))}
    raw_layouts[FIELD_LEVEL["layout"]] = copy.deepcopy(FIELD_LAYOUT)
    plan_difficulties = list(expeditions["difficulties"]) + ["nope"]
    parties = range(1, combat["coop"]["maxParty"] + 1)
    # L3-17: the families a first clear may give, and the starters it may not (Unlocks.Starters).
    # notes=False (the L4 W3 fix round's F6): Validate drops a bad note and keeps the level, so its
    # list and verdict are compared without sim_range's note lines; NOTE_CASES hold the drop itself.
    vet = {"weapons": cfg["weapons"], "starters": starters_of(cfg), "notes": False}

    def resolved(file):
        return sr.resolve_level(file, director["runCapSeconds"])

    # The cases, and the Python's own answers to them.
    report = Report(args.show)
    expected = {}  # id -> (kind, label, the Python's answer)
    # The L1c fix round's data m2: the refusal cases a copy is broken for (all but "as shipped"). Two
    # sides that agree prove nothing about a rule removed from both: each of these must be refused.
    must_refuse = set()
    # L2 W2: cases both sides must ACCEPT (a refusal of a sound tunnel on both sides is a drift too).
    must_accept = set()
    data = {"combat": combat, "expeditions": expeditions, "proving": cfg, "levels": files,
            "layouts": raw_layouts, "ranks": ranks, "planDifficulties": plan_difficulties, "pointCases": [],
            "waveCases": [], "refusalCases": [], "traces": [], "busyCases": list(BUSY_CASES),
            "campRules": combat["camps"], "campCases": [], "splitCases": [], "rayCases": [], "swingCases": [],
            "combatCases": [], "reserveCases": [], "tentOwesCases": [], "regionCases": [], "fieldedCases": [],
            "ceilingCases": [], "fenceCases": [], "iceCases": [], "armoryConfigs": [], "armoryCases": [],
            "armoryCombats": [dict(combat_) for combat_ in ARMORY_COMBATS], "armoryBuilt": [list(b) for b in ARMORY_BUILT],
            "firstClearCases": [], "eraCashCases": [], "noteCases": [], "gameConfig": sc.se.load_game_config(),
            "legacyShopConfig": sc.se.load_legacy_shop_config()}
    # The L1c second fix round's F1: StageFlow.Ceiling against sim_range.trigger_ceiling, on every
    # shipped camp and on the edges: a low fence, one at triggerHeight, an open camp's tall one,
    # none, a height that is a string or absent.
    edges = [{"locks": True, "fence": {"height": 64}}, {"locks": True, "fence": {"height": 4}},
             {"locks": True, "fence": {"height": rules["triggerHeight"]}},
             {"locks": True, "fence": {"height": rules["triggerHeight"] + 0.5}},
             {"locks": False, "fence": {"height": 64}}, {"fence": {"height": 64}}, {"locks": True},
             {"locks": True, "fence": {"height": "64"}}, {"locks": True, "fence": {"material": "Wood"}}]
    shipped_camps = [(f"{name} camp {camp['id']}", camp) for name, layout in raw_layouts.items()
                     for camp in layout.get("camps") or []]
    for index, (label, camp) in enumerate([(f"edge {i}", c) for i, c in enumerate(edges, 1)] + shipped_camps, 1):
        case = f"ceiling.{index}"
        data["ceilingCases"].append({"id": case, "camp": camp, "height": rules["triggerHeight"]})
        expected[case] = ("StageFlow.Ceiling: a camp's trigger band (the L1c second fix round's F1)", label,
                          sr.trigger_ceiling(camp, rules["triggerHeight"]))
    # The L2 W2 second fix round's m1: LevelGeometry.FenceThickness against sim_range.fence_thickness,
    # on every shipped camp and on the edges: none, the camp's own, 0, below 0, a string, no fence.
    fence_edges = [{"fence": {"height": 4}}, {"fence": {"height": 64, "thickness": 2.5}},
                   {"fence": {"height": 4, "thickness": 0}}, {"fence": {"height": 4, "thickness": -1}},
                   {"fence": {"height": 4, "thickness": "2.5"}}, {}]
    for index, (label, camp) in enumerate([(f"edge {i}", c) for i, c in enumerate(fence_edges, 1)] + shipped_camps, 1):
        case = f"fence.{index}"
        data["fenceCases"].append({"id": case, "camp": camp, "default": rules["fenceThickness"]})
        expected[case] = ("LevelGeometry.FenceThickness: a camp's own fence depth (the L2 W2 second fix round's m1)",
                          label, sr.fence_thickness(camp, rules["fenceThickness"]))
    ice_cases(data, expected, raw_layouts, rules)
    shipped_plans = []  # (label, plan) of every level with residents at every difficulty: Wave 2's camp cases
    bursts, tempos = {}, {}
    scripted = {}  # trace id -> (label, the Python's ticks)
    stars = {}  # trace id -> the Python's earns_star for STAR_USERS, at the run's end
    for number, file in enumerate(files, 1):
        name = file["id"]
        level = resolved(file)
        # Catalog.GetLevelLayout's answer (a fresh copy; the field's is FIELD_LAYOUT).
        layout = copy.deepcopy(raw_layouts[file["layout"]])
        expected[f"level.{number}.resolve"] = ("StageFlow.Resolve", name, plain(level))
        if level is None:
            continue
        expected[f"level.{number}.validate"] = ("StageFlow.Validate: the shipped level is playable", name,
                                                sr.level_problems(level, layout, rules, crowd_kinds, ranks, crowd_max, **vet))
        reserve_case = f"level.{number}.bossReserve"
        data["reserveCases"].append({"id": reserve_case, "level": number})
        expected[reserve_case] = ("StageFlow.BossReserve", f"{name}: with the kinds, and with none",
                                  [sr.boss_reserve(level, crowd_kinds), sr.boss_reserve(level, None)])
        for difficulty in plan_difficulties:
            plan = sr.plan_level(level, layout, difficulty, rules, ranks, crowd_kinds)
            key = f"level.{number}.plan.{difficulty}"
            if plan is None:
                expected[key] = ("StageFlow.Plan", f"{name} {difficulty}", None)
                continue
            stages = []
            for stage in plan["stages"]:
                zone = stage["zone"]
                floor = zone["floorY"] if zone else 0
                stages.append({
                    "kind": stage["kind"], "name": stage["name"], "waves": stage["waves"],
                    "boss": sorted(stage["boss"]), "breatherSeconds": stage["breatherSeconds"], "merge": stage["merge"],
                    "targetWaveSeconds": stage["targetWaveSeconds"], "maxAlive": stage["maxAlive"],
                    "gateSeconds": stage.get("gateSeconds"),
                    "zone": None if zone is None else zone["id"]})
            start = layout["start"]
            expected[key] = ("StageFlow.Plan", f"{name} {difficulty}", plain({"plan": {
                "levelId": plan["levelId"], "difficulty": plan["difficulty"], "start": (start["x"], start["y"], start["z"]),
                "killY": plan["killY"], "camps": plan["camps"], "stages": stages,
                "zones": [zone_row(zone) for zone in plan["zones"]],
                "groups": [def_row(defn) for defn in plan["groups"]], "tents": [tent_row(t) for t in plan["tents"]],
                "population": plan["population"]}}))
            if plan["groups"]:
                shipped_plans.append((f"{name} {difficulty}", plan))
            # CampBrain.Posts on every tent's ring (the tent posture, L1b-W2-6).
            for t, tent in enumerate(plan["tents"], 1):
                case = f"camp.posts.{number}.{difficulty}.tent.{t}"
                data["campCases"].append({"id": case, "op": "posts", "def": def_row(tent["def"]), "count": len(tent["kinds"])})
                expected[case] = ("CampBrain.Posts", f"{name} {difficulty} {tent['def']['id']} ({len(tent['kinds'])})",
                                  plain(sr.cb_posts(tent["def"], len(tent["kinds"]))))
            # CampBrain.Posts on every resident group of the plan.
            for g, defn in enumerate(plan["groups"], 1):
                count = sum(unit["count"] for unit in defn["units"])
                case = f"camp.posts.{number}.{difficulty}.{g}"
                data["campCases"].append({"id": case, "op": "posts", "def": def_row(defn), "count": count})
                expected[case] = ("CampBrain.Posts", f"{name} {difficulty} {defn['id']} ({count})",
                                  plain(sr.cb_posts(defn, count)))
            # Spawn grids and the boss's place: geometry, so once a level (its first difficulty).
            if difficulty == next(d for d in plan_difficulties if d in level["difficulties"]):
                spacing = level["crowd"]["burstSpacing"]
                for index, stage in enumerate(plan["stages"], 1):
                    zone = stage["zone"]
                    if zone is None:
                        continue
                    cx, cz = zone["rect"][:2]
                    for spawn, (sx, sz) in enumerate(zone["spawns"], 1):
                        for size in BURST_SIZES:
                            for body in range(size):
                                case = f"point.{number}.{index}.{spawn}.{size}.{body}"
                                data["pointCases"].append({"id": case, "level": number, "difficulty": difficulty,
                                                           "stage": index, "spawn": spawn, "size": size, "index": body,
                                                           "spacing": spacing})
                                x, z = sr.burst_point((sx - cx, sz - cz), size, body, spacing)
                                expected[case] = ("StageFlow.BurstPoint",
                                                  f"{name} camp {zone['id']} spawn {spawn}, body {body + 1} of {size}",
                                                  [x + cx, zone["floorY"], z + cz])
                    # The L1c fix rounds' F2 and m3: the close's nudge onto `inner`, on a grid
                    # over the fenced rectangle (its edges, inner's, the centre, half a stud either
                    # side of each edge) and in height.
                    nudges = 0
                    floor = zone["floorY"]
                    rises = (-rules["triggerBelow"] - 0.5, -rules["triggerBelow"], sr.ROOT_HEIGHT,
                             rules["triggerHeight"] + 0.5, zone["ceiling"], zone["ceiling"] + 0.5)
                    axes = []
                    for centre, half_in, half_out in ((zone["trigger"][0], zone["inner"][2], zone["trigger"][2]),
                                                      (zone["trigger"][1], zone["inner"][3], zone["trigger"][3])):
                        marks = [centre]
                        for sign in (-1, 1):
                            near, far = centre + sign * half_in, centre + sign * half_out
                            marks += [near - sign * 0.5, near, near + sign * 0.5, (near + far) / 2,
                                     far - sign * 0.5, far, far + sign * 0.5]
                        axes.append(marks)
                    for x in axes[0]:
                        for z in axes[1]:
                            for rise in rises:
                                nudges += 1
                                case = f"point.{number}.{index}.nudge.{nudges}"
                                at = (x, floor + rise, z)
                                data["pointCases"].append({"id": case, "level": number, "difficulty": difficulty,
                                                           "stage": index, "nudge": list(at)})
                                moved = sr.gate_nudge(zone, at, rules)
                                expected[case] = ("StageFlow.GateNudge: the close's nudge onto inner (F2, m3)",
                                                  f"{name} camp {zone['id']} at {at}",
                                                  list(moved) if moved is not None else None)
                    for wave, wave_def in enumerate(stage["defs"], 1):
                        if wave_def.get("boss"):
                            at = wave_def["boss"]["at"]
                            case = f"point.{number}.{index}.boss.{wave}"
                            data["pointCases"].append({"id": case, "level": number, "difficulty": difficulty,
                                                       "stage": index, "boss": at})
                            expected[case] = ("StageFlow.BossPoint", f"{name} camp {zone['id']} wave {wave}",
                                              [cx + at[0], zone["floorY"], cz + at[1]])
            # The scripted runs.
            for variant in VARIANTS:
                trace = f"trace.{number}.{difficulty}.{variant}"
                run = Scripted(cfg, ctx, level, layout, difficulty)
                ticks = script_run(run, variant, rules, layout["start"]["y"])
                data["traces"].append({"id": trace, "level": number, "difficulty": difficulty,
                                       "ticks": [tick[0] for tick in ticks], "users": list(STAR_USERS)})
                stars[trace] = [run.earns_star(user) for user in STAR_USERS]
                scripted[trace] = (f"{name} {difficulty}, {variant}", ticks)
            # CampBrain's rules on the shipped groups (once, at the highest difficulty).
            if difficulty == max((d for d in plan_difficulties if d in level["difficulties"]), key=lambda d: ranks[d]):
                for defn in plan["groups"]:
                    camp_cases(data, expected, f"{name} {defn['id']}", defn, combat["camps"])
        # Combat, on every wave.
        kinds = sorted(level["crowd"]["rewards"]) + ["nobody"]
        for difficulty, scales in level["difficulties"].items():
            for index, stage in enumerate(level["stages"], 1):
                for wave, wave_def in enumerate(stage.get("waves") or [], 1):
                    for party in parties:
                        case = f"wave.{number}.{difficulty}.{index}.{wave}.{party}"
                        label = f"{name} {difficulty}, {stage['name']} wave {wave}, party {party}"
                        spec = sc.camp_wave(wave_def, level["crowd"]["regenShare"], scales, ranks[difficulty], ranks,
                                            party, combat)
                        data["waveCases"].append({"id": case, "level": number, "difficulty": difficulty, "stage": index,
                                                  "wave": wave, "party": party, "kinds": kinds})
                        expected[case] = ("Combat.CampWave", label, plain(spec))
                        expected[case + ".rewards"] = ("Combat.KillReward", label, {
                            kind: list(sc.kill_reward(level["crowd"]["rewards"], kind, spec["rewardMult"]))
                            for kind in kinds})
                        target = stage["targetWaveSeconds"] if stage.get("targetWaveSeconds") is not None else 0
                        count = len(sc.crowd_bursts(spec, level["crowd"]["burst"]))
                        for tempo in TEMPO_GRID:
                            bursts[(target, count, tempo)] = None
                        rate = spec["total"] / target if target > 0 else 0
                        for kills in KILL_GRID:
                            tempos[(kills, director["windowSeconds"], rate)] = None
        for label, change in (("as shipped", lambda _file: None),) + REFUSALS:
            changed = copy.deepcopy(file)
            change(changed)
            case = f"refusal.{number}.{len(data['refusalCases'])}"
            data["refusalCases"].append({"id": case, "file": changed, "rules": rules})
            level_changed = resolved(changed)
            refused = level_changed is None or bool(sr.level_problems(level_changed, layout, rules, crowd_kinds, ranks,
                                                                      crowd_max, **vet))
            expected[case] = ("ruling 6: refused alike", f"{name}, {label}", refused)
            if label != "as shipped":
                must_refuse.add(case)
        # And Combat.json without one of the numbers a run reads: unavailable on both sides.
        for key in sr.LEVEL_RULES_NEEDED:
            short_rules = {name_: value for name_, value in rules.items() if name_ != key}
            case = f"refusal.{number}.{len(data['refusalCases'])}"
            data["refusalCases"].append({"id": case, "file": file, "rules": short_rules})
            expected[case] = ("ruling 6: refused alike", f"{name}, Combat.json without levels.{key}",
                              bool(sr.level_problems(level, layout, short_rules, crowd_kinds, ranks, crowd_max, **vet)))
        # L1b: each of Validate's new lines, broken once.
        if file.get("camps"):
            for label, change in L1B_REFUSALS:
                changed, raw, short_rules = copy.deepcopy(file), copy.deepcopy(raw_layouts[file["layout"]]), dict(rules)
                change(changed, raw, short_rules)
                case = f"refusal.{number}.{len(data['refusalCases'])}"
                data["refusalCases"].append({"id": case, "file": changed, "rules": short_rules, "layout": raw})
                level_changed = resolved(changed)
                refused = level_changed is None or bool(sr.level_problems(level_changed, raw, short_rules, crowd_kinds,
                                                                          ranks, crowd_max, **vet))
                expected[case] = ("L1b: Validate's new lines refuse alike", f"{name}, {label}", refused)
                must_refuse.add(case)
        # L2-13: each of Validate's secrets lines, broken once.
        if file.get("secrets") and raw_layouts[file["layout"]].get("secrets"):
            for label, change in L2_REFUSALS:
                changed, raw, short_rules = copy.deepcopy(file), copy.deepcopy(raw_layouts[file["layout"]]), dict(rules)
                change(changed, raw, short_rules)
                case = f"refusal.{number}.{len(data['refusalCases'])}"
                data["refusalCases"].append({"id": case, "file": changed, "rules": short_rules, "layout": raw})
                level_changed = resolved(changed)
                refused = level_changed is None or bool(sr.level_problems(level_changed, raw, short_rules, crowd_kinds,
                                                                          ranks, crowd_max, **vet))
                expected[case] = ("L2: Validate's secrets lines refuse alike", f"{name}, {label}", refused)
                must_refuse.add(case)
        # L2-34, L2-36: the react, opens and shortcuts lines, on a test tunnel of their own; L2-52,
        # L2-58: the ice and landing lines, on a test pool.
        if raw_layouts[file["layout"]].get("blocks"):
            w2 = "L2 W2: Validate's react, opens and shortcuts lines refuse alike"
            w3 = "L2 W3: Validate's ice and landing lines refuse alike"
            l3 = "L3: Validate's firstClear lines refuse alike"
            for cases, verdict, title in ((L2W2_ACCEPTED, False, w2), (L2W2_REFUSALS, True, w2),
                                          (L2W3_ACCEPTED, False, w3), (L2W3_REFUSALS, True, w3),
                                          (L3_ACCEPTED, False, l3), (L3_REFUSALS, True, l3)):
                for label, change in cases:
                    changed, raw, short_rules = copy.deepcopy(file), copy.deepcopy(raw_layouts[file["layout"]]), dict(rules)
                    change(changed, raw, short_rules)
                    case = f"refusal.{number}.{len(data['refusalCases'])}"
                    data["refusalCases"].append({"id": case, "file": changed, "rules": short_rules, "layout": raw})
                    level_changed = resolved(changed)
                    refused = level_changed is None or bool(sr.level_problems(level_changed, raw, short_rules,
                                                                              crowd_kinds, ranks, crowd_max, **vet))
                    expected[case] = (title, f"{name}, {label}", refused)
                    if verdict:
                        must_refuse.add(case)
                    else:
                        must_accept.add(case)
        # The L4 W3 fix round's F6: each bad note dropped, the level kept (NOTE_CASES).
        if number <= shipped_count and all(d in (file.get("difficulties") or {}) for d in NOTE_DIFFICULTIES):
            for label, notes, drops in NOTE_CASES:
                changed = copy.deepcopy(file)
                for difficulty, note in notes.items():
                    changed["difficulties"][difficulty]["note"] = copy.deepcopy(note)
                case = f"note.{number}.{len(data['noteCases'])}"
                data["noteCases"].append({"id": case, "file": changed})
                level_changed = resolved(changed)
                dropped = []
                if level_changed is not None:
                    sr.note_problems(level_changed, dropped.append)
                if len(dropped) != drops:
                    report.differ(NOTE_KIND, f"{name}, {label}: the Python drops {len(dropped)} notes, not {drops}")
                expected[case] = (NOTE_KIND, f"{name}, {label}", None if level_changed is None else {
                    "refused": bool(sr.level_problems(level_changed, layout, rules, crowd_kinds, ranks, crowd_max,
                                                      **vet)),
                    "kept": sorted([key, note] for key, note in sr.kept_notes(level_changed).items()),
                    "dropped": len(dropped)})
                noted.add(name)
    if not noted:
        report.differ(NOTE_KIND, f"no shipped level file has {', '.join(NOTE_DIFFICULTIES)} to break a note on")
    for target in sorted({key[0] for key in bursts}):
        for count in (0, -1):
            bursts[(target, count, 1.0)] = None
    for kills in KILL_GRID:
        tempos[(kills, 0, 1.0)] = None
        tempos[(kills, director["windowSeconds"], 0)] = None
    merges = [(tempo, dead) for tempo in (0.5, director["tempoMin"], 1.0, director["mergeTempo"] - EDGE,
                                         director["mergeTempo"], director["mergeTempo"] + EDGE, director["tempoMax"])
              for dead in (0.0, 0.5, director["mergeThreshold"] - EDGE, director["mergeThreshold"],
                           director["mergeThreshold"] + EDGE, 1.0)]
    breathers = [0.0, director["tempoMin"] / 2, director["tempoMin"], (1 + director["tempoMin"]) / 2, 1.0 - EDGE, 1.0,
                 director["mergeTempo"], director["tempoMax"]]
    grid_camp_cases(data, expected, combat["camps"])
    wave2_camp_cases(data, expected, combat["camps"], shipped_plans[:2])
    split_cases(data, expected)
    ray_cases(data, expected, crowd_kinds, cfg["crowd"].get("restDrop") or 0.0,
              cfg["crowd"].get("riseBlendSeconds") or 0.0)
    swing_cases(data, expected)
    tent_owes_cases(data, expected)
    combat_cases(data, expected, files, raw_layouts, rules, ranks, crowd_kinds)
    region_cases(data, expected, raw_layouts)
    wave4_camp_cases(data, expected, combat["camps"], raw_layouts)
    fielded_cases(data, expected, files, rules, ranks, crowd_kinds)
    armory_cases(data, expected, report, cfg)
    first_clear_cases(data, expected, report, files, resolved, plan_difficulties)
    data["burstCases"] = [list(key) for key in bursts]
    data["tempoCases"] = [list(key) for key in tempos]
    data["mergeCases"] = [list(key) for key in merges]
    data["breatherCases"] = breathers
    data["rewardCases"] = [list(case) for case in REWARD_GRID]
    mentors, mentor_fixtures = mentor_cases(combat)
    data["mentorCases"] = [[host, rates] for host, rates in mentors]
    era_cash_cases(data, expected, combat, data["gameConfig"], data["legacyShopConfig"])

    # The bundle: the data, the real sources, the driver. In a folder of its own.
    parts = [f"local DATA: any = {to_luau(data)}\n", "local SOURCES = {}\n"]
    for name in MODULES:
        path = Path(swapped[name]) if name in swapped else ROOT / sources[name]
        parts.append(wrap(name, path.read_text(encoding="utf-8")))
    parts.append(DRIVER.read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory() as scratch:
        work = Path(args.keep) if args.keep else Path(scratch)
        work.mkdir(parents=True, exist_ok=True)
        bundle = work / "stage_mirror_bundle.luau"
        bundle.write_text("".join(parts), encoding="utf-8")
        try:
            result = subprocess.run([str(luau), str(bundle)], capture_output=True, text=True, timeout=300)
        except subprocess.TimeoutExpired:
            raise SystemExit("check_stage_mirror: the Luau did not finish in 300 s")
        if args.keep:
            (work / "stage_mirror_out.txt").write_text(result.stdout + "\n" + result.stderr, encoding="utf-8")
    answers = {}
    for line in result.stdout.splitlines():
        if line.startswith("OUT\t"):
            _tag, key, text = line.split("\t", 2)
            answers[key] = json.loads(text)
    if "DONE" not in result.stdout.splitlines() or result.returncode != 0:
        tail = "\n".join((result.stdout.splitlines()[-3:] if result.stdout else []) + result.stderr.splitlines()[-6:])
        raise SystemExit(f"check_stage_mirror: the Luau run did not finish (exit {result.returncode}):\n{tail}")

    print(f"check_stage_mirror: {len(files)} level files ({', '.join(file['id'] for file in files)}), the real "
          f"{', '.join(name + ('*' if name in swapped else '') for name in MODULES if name not in ('Economy', 'Armory'))} "
          f"under {luau.name}, against tools/sim_combat.py and tools/sim_range.py"
          + (" (* = the copy --module named)" if swapped else ""))

    # What the Luau exports.
    exports = answers.get("exports") or {}
    missing = [f"{module}.{name}" for module, names in NEEDED.items() for name in names
               if name not in (exports.get(module) or [])]
    for name in missing:
        report.differ("the functions compared exist", f"{name} is not in the Luau")
    lacking = [f"sim_combat.{name}" for name in ARMORY_MIRRORS.values() if not callable(getattr(sc, name, None))]
    lacking += [] if callable(getattr(sr, "first_clear", None)) else ["sim_range.first_clear"]
    for name in lacking:
        report.differ("the functions compared exist", f"{name} is not in the Python")
    missing += lacking
    # F4: a deliberately unmirrored Armory function that is gone (or renamed) leaves a stale list.
    stale = [f"Armory.{name}" for name in ARMORY_UNMIRRORED if name not in (exports.get("Armory") or [])]
    for name in stale:
        report.differ("the functions compared exist", f"{name} is listed as deliberately unmirrored but is not in the Luau")
    missing += stale
    if not missing:
        report.compare("the functions compared exist", "exports", True, True)

    # The answers, one by one.
    for key, (kind, label, python) in expected.items():
        luau_answer = answers.get(key)
        if kind == "StageFlow.Plan" and python is None:
            # A refusal on both sides: the Luau's reason is its own.
            refused = isinstance(luau_answer, dict) and "refused" in luau_answer
            report.compare(kind, label + " (refused)", refused, True)
            continue
        if kind.startswith("StageFlow.Validate"):
            report.compare(kind, label, luau_answer if isinstance(luau_answer, dict) else list(luau_answer or []), python)
            continue
        if (kind.startswith("ruling 6") or kind.startswith("L1b: Validate") or kind.startswith("L2: Validate")
                or kind.startswith("L2 W2: Validate") or kind.startswith("L2 W3: Validate")
                or kind.startswith("L3: Validate")):
            if key in must_refuse and not python and not luau_answer:
                report.differ(kind, f"{label}: accepted on both sides (the rule it breaks is gone from both)")
                continue
            if key in must_accept and python and luau_answer:
                report.differ(kind, f"{label}: refused on both sides (a sound tunnel must be playable)")
                continue
            if isinstance(luau_answer, dict) and "threw" in luau_answer:
                report.compare(kind, label, luau_answer, python)
            else:
                report.compare(kind, label + (" (must be refused)" if python else " (must be accepted)"),
                               bool(luau_answer), python)
            continue
        if key not in answers:
            report.differ(kind, f"{label}: the Luau gave no answer (an earlier step of it failed)")
            continue
        report.compare(kind, label, luau_answer, python)

    def grid(kind, key, cases, mirror):
        got = answers.get(key)
        if isinstance(got, dict) and "threw" in got:
            report.compare(kind, key, got, None)
            return
        got = got or []
        for index, case in enumerate(cases):
            report.compare(kind, f"({', '.join(f'{v:g}' for v in case)})", got[index] if index < len(got) else None,
                           mirror(*case))

    grid("Combat.KillReward", "grid.killReward", data["rewardCases"],
         lambda cash, materials, mult: list(sc.kill_reward({"probe": {"cash": cash, "materials": materials}}, "probe",
                                                            mult)) + list(sc.kill_reward({}, "probe", mult)))
    grid("Combat.BurstSeconds", "grid.burstSeconds", data["burstCases"], sc.burst_seconds)
    grid("Combat.Tempo", "grid.tempo", data["tempoCases"], lambda kills, window, rate: sc.tempo(kills, window, rate, director))
    grid("Combat.ShouldMerge", "grid.shouldMerge", data["mergeCases"], lambda tempo, dead: sc.should_merge(tempo, dead, director))
    grid("Combat.BreatherSeconds", "grid.breatherSeconds", [(tempo,) for tempo in breathers],
         lambda tempo: sc.breather_seconds(tempo, director))

    # F6: Combat.MentorBonus case by case, then each of assertions 12 and 13's boss kills paid by
    # sim_combat.mentor_pay twice, once on its own mentor_bonus and once on the Luau's answers.
    got = answers.get("grid.mentorBonus")
    if isinstance(got, dict) and "threw" in got:
        report.compare("Combat.MentorBonus", "grid.mentorBonus", got, None)
    else:
        got = got or []
        luau_bonus = {}
        for index, (host, rates) in enumerate(mentors):
            theirs = got[index] if index < len(got) else None
            luau_bonus[(host, tuple(rates))] = theirs
            report.compare("Combat.MentorBonus", f"host {host:g}/s, party [{', '.join(f'{r:g}' for r in rates)}]",
                           theirs, sc.mentor_bonus(combat, host, rates))
        for name, (members, tally) in mentor_fixtures.items():
            replayed = sc.mentor_pay(combat, members, tally,
                                     bonus_of=lambda _cfg, host, rates: luau_bonus.get((host, tuple(rates))) or 0)
            report.compare("Combat.MentorBonus through sim_combat.mentor_pay (assertions 12, 13)", name,
                           {str(user): valor for user, valor in replayed.items()},
                           {str(user): valor for user, valor in sc.mentor_pay(combat, members, tally).items()})

    # The scripted runs: the first tick at which the two sides part, per run.
    extra_state = set()
    kinds = {"reset": "StageFlow.Advance: nobody on his feet as a countdown ends", "skipStage": "StageFlow.Skip",
             "skipBoss": "StageFlow.Skip", "force": "StageFlow.Force", "approach": "StageFlow.Skip: N through the approaches",
             "approachPast": "StageFlow.Skip: N through the approaches"}
    for trace, (label, ticks) in scripted.items():
        kind = kinds.get(trace.rsplit(".", 1)[1], "StageFlow.Advance: scripted runs")
        got = answers.get(trace)
        if not isinstance(got, dict) or "ticks" not in got:
            report.compare(kind, label, got if isinstance(got, dict) else {"threw": "no answer"}, None)
            continue
        parted = None
        for index, (entry, actions, state, directs, closing, clear, safe, up) in enumerate(ticks):
            theirs = got["ticks"][index] if index < len(got["ticks"]) else {}
            their_state = theirs.get("state") or {}
            extra_state |= set(their_state) - set(STATE_FIELDS)
            ours = {"actions": [action_row(action) for action in actions], "state": plain(state)}
            luau_side = {"actions": [action_row(action) for action in theirs.get("actions") or []],
                         "state": {field: their_state[field] for field in STATE_FIELDS if field in their_state}}
            if parted is None and not same(luau_side, ours):
                parted = (f"{label}: tick {index + 1} of {len(ticks)} ({tick_text(entry)}): "
                          f"{where(luau_side, ours)}; actions {short([a['kind'] for a in luau_side['actions']])} / "
                          f"{short([a['kind'] for a in ours['actions']])}")
            if parted is None:
                here = f"{label}: tick {index + 1}, step {state['step']}"
                report.compare("StageFlow.Directs: does the director keep its tempo in this step", here,
                               theirs.get("directs"), directs)
                report.compare("StageFlow.StillClosing: is the close still judged again", here,
                               theirs.get("closing"), closing)
                report.compare("StageFlow.FieldClear: may the fallen lose (L1b-19)", here, theirs.get("clear"), clear)
                report.compare("StageFlow.SafePoint: no floor busy, every floor, the first, the last (L1b-18)", here,
                               theirs.get("safe"), safe)
                report.compare("StageFlow.StandsUp: a down on the quiet road stands up (L1b-W2-27)", here,
                               theirs.get("standsUp"), up)
        if parted is None:
            report.compare(kind, f"{label} ({len(ticks)} ticks, ended {ticks[-1][2]['ended']})", True, True)
            report.compare("StageFlow.EarnsStar: a fighter of the last clear, one who was not, a stranger",
                           f"{label} (ended {ticks[-1][2]['ended']}, fought {ticks[-1][2]['fought']})",
                           got.get("stars"), stars[trace])
        else:
            report.differ(kind, parted)

    failed = report.print()
    mirrored = dict(NEEDED)
    loose = [name for name in exports.get("StageFlow") or [] if name not in mirrored["StageFlow"]]
    print(f"  note  StageFlow functions the simulators do not mirror (tools/crowd_harness tests them): "
          f"{', '.join(loose) or 'none'}")
    print("  note  Armory functions deliberately not mirrored (F4; tools/crowd_harness tests them): "
          + "; ".join(f"{name}: {why}" for name, why in ARMORY_UNMIRRORED.items()))
    loose = [name for name in exports.get("Armory") or [] if name not in ARMORY_MIRRORS and name not in ARMORY_UNMIRRORED]
    if loose:
        print(f"  note  Armory functions not compared here: {', '.join(loose)}")
    loose = [name for name in exports.get("CampBrain") or [] if name not in mirrored["CampBrain"]]
    if loose:
        print(f"  note  CampBrain functions not compared: {', '.join(loose)}")
    if extra_state:
        print(f"  note  State fields the simulator's run does not carry: {', '.join(sorted(extra_state))}")
    print()
    print(f"CHECK: {'PASS' if failed == 0 else f'FAIL ({failed})'}")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
