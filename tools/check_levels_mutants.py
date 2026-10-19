#!/usr/bin/env python
"""The check_levels mutants, committed (the L1c fix round's m6): every rule L1c and its fix round
added to tools/check_levels.py, every rule of L2 Wave 1 (L2-6, L2-11, L2-13, L2-14, L2-18, L2-19)
and of L2 Wave 2 (L2-34, L2-36, L2-37, L2-38, L2-47: the cave behind fire, the shortcut route, the
chain of keys, R8's sight, the bend) and its fix round (d-M1: no carrying ability onto the ridge;
d-m1: the walk-off grace in the ridge's reach; d-m2: the bend's known limit; s-m3: a shortcut's size)
and its second fix round (m1: shooting.originWallChord under every tall piece's thickness, a camp's own
fence.thickness, mirrored by sim_range.fence_thickness; the L1c sight cases calibrated on the 1-stud
wall now run on it through l1c_wall, each with a twin on the shipped 2.5-stud wall), and of L2 Wave 3
(L2-51 to L2-60: deep water, the landing, the island behind ice with the water as built (g) and frozen
(h), the frozen layout's walls, ledge, sniper spots, the found family and the shrine's pay) and its
fix round (s-M1 and Q3: every deep water a body falls into has a landing, the stood test reaches the
edge; s-s2: no two ice blocks overlap; d-m1: the pieces and covers fill every ice block, shown red on
a copy of sim_range with the old centre rule (SWAPPED_SIM); d-m3: Leap Smash's fall; d-m4: the
walk-off grace; d-m6: a frozen sheet as deep as a floor; s1: an alias of a dash; s2: the bend rule,
the cave's closed half and the walled camp on the frozen layout, its sight run on the tops the ice
adds), shown red on a mutated copy of the shipped data, and green again on the data as it ships.

Each case loads the files afresh, changes a copy in memory (a layout block, a level file's units,
a Combat.json number) or turns one of check_levels' switches (SIGHT_ZONES, EXEMPT_CAMERAS,
FLOOR_WALLS, WALLED_CEILING, LIFT_MODEL, TRIGGER_MODEL, SIGHT_WALLS, or `sr`: a copy of
sim_range.py with one line swapped, made when the case runs), runs every gate
(check_levels.run_gates) and expects the named rule red, or green for a control. A rule is named by text its line always carries. Nothing on disk is written,
except for the stage-mirror cases (MIRROR_CASES), which run tools/check_stage_mirror.py with a line
of StageFlow.luau and/or sim_range.py broken, from copies in a temporary folder, and expect it red:
m2 (the "residents under the boss room's maxAlive" rule out of both), the second fix round's F1
(the walled camp's trigger band out of the Python mirror alone) and the third's m3 (gate_nudge's
fenced-rectangle test out of the Python mirror alone); and for the simulator's cases (SIM_CASES),
which run tools/sim_range.py from a copy with one line broken and expect its check red: the L2 W1
fix round's d3 (an air jump back on in the planner turns the one-jump gate red; about five minutes).

Usage:
  py tools/check_levels_mutants.py                       # every case; exit 1 when one is not as expected
  py tools/check_levels_mutants.py --only sight          # the cases whose label holds this text
  py tools/check_levels_mutants.py --luau <luau.exe>     # the interpreter for the stage-mirror cases
                                                          # (default tools/bin/luau.exe; skipped if missing)
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import io
import re
import subprocess
import sys
import tempfile
import types
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import check_levels as cl  # noqa: E402

REPO = TOOLS.parent

# The rules, by text their line always carries.
FENCE = "camp C has a fence, and a root on its top"
BAND = "camp C: nothing a player stands on sits in its invisible wall's band"
SNIPER = "the unreachable sniper spots"
BESIDE = "camp C: nothing stands beside it"
HEIGHT = "camp C (walled): its fence ("
GATEHOUSE = "camp C (walled): every wall block within"
PLATES = "camp C (walled): no resident carries a plate"
FLOORS = "camp C (walled): from every outside surface"
SIGHT = "camp C (walled): from no eye point"
MARGIN = "camp C (walled): every eye's and every camera's sight margin"
CLEAR = "camp C (walled): levels.cameraClear"
READS = "camp C (walled): the sight gate reads"
LOCKED = re.compile(r"camp C: \d+ residents at the highest difficulty")
COUNTDOWN = "(The Chief's Clearing): its own gateSeconds"
PROBLEMS = "forestRoad: maxAlive is an integer of at least 1 wherever"
CEILING = "camp C (walled): it triggers up to"
NUDGE = "camp C: the close's nudge lands clear"
# L2 Wave 1 (docs/prompts/l2-w1-contract.md, L2-6, L2-11, L2-13, L2-18, L2-19).
REACH_A = "the lookout ledge's top is over"
REACH_B = "the lookout needs the double jump: no surface"
REACH_C = "the lookout needs the double jump against every lifting ability"
REACH_D = "the lookout's trigger is met only on its ledge"
# The L2 W1 fix round: (a)'s standable point for every secret (s1 + d2), the one-jump gate (d3).
TRIGGER_CACHE = "the cache's trigger (levels.secretReach"
TRIGGER_LOOKOUT = "the lookout's trigger (levels.secretReach"
ONE_JUMP = "Normal: one jump (L2-20)"
REWARDS = "forestRoad: a secret pays only behind a key"
ABILITIES = "Expeditions.json abilities.list: every entry"
PRICE = "Expeditions.json: Double Jump costs"
SECRET_NUMBERS = "Combat.json levels (L2-11)"
LEVERS = "Combat.json debug (L2-19"
LOOKS = "map: the looks are greys, except"
# L2 Wave 2 (docs/prompts/l2-w2-contract.md, L2-34 to L2-38, L2-47).
SEALED = "behind fire: with every bramble standing"
RIDGE = "behind fire: every wall that faces the sealed air is unclimbable"
CACHE_A = "the cache's trigger (needs fire) is met from its alcove floor"
SHORTCUT = "the shortcut route, with the brambles burnt"
SNEAK_CAVE = "every point of the shortcut route lies farther than its posture's sight"
SNIPER_OPEN = "with the brambles burnt, the unreachable sniper spots"
BEND = "no hop cuts a bend"
# The L2 W2 fix round (docs/prompts/l2-w2-fix-round.md: d-M1, d-m1, d-m2, s-m3).
RIDGE_LIFT = "behind fire: no ability that carries a player with the double jump"
BEND_LIFT = "no hop with an ability that carries"
REACT = "Combat.json levels.react (L2-34)"
# The L2 W2 second fix round (docs/prompts/l2-w2-fix2.md: m1).
CHORD = "ForestRoad: shooting.originWallChord"
THICKNESS = "camp C: its fence.thickness, when it names one"
# L2 Wave 3 (docs/prompts/l2-w3-contract.md, L2-51 to L2-60).
DEEP = "ForestRoad: deep water: every water block is deep"
LANDING = "every water landing stands on solid ground"
ICE_JUMPS = "behind ice, the water as built: no jump"
ICE_LIFT = "behind ice, the water as built: no lifting ability"
ICE_DASH = "behind ice, the water as built: no air dash"
ICE_GAP = "behind ice: the shrine's island lies at least ICE_MARGIN"
ICE_TRIGGER = "the shrine's trigger (needs ice) is met from its island"
ICE_FROZEN = "with the ice frozen, the shrine's island is reached"
ICE_SWING = "with the ice: every ice family's swing"
ICE_CHAIN = "with the ice: the open cells of the ice blocks form one"
ICE_WALLS = "with the ice frozen every unclimbable wall stays"
FROZEN_LEDGE = "forestRoad (frozen): the lookout needs the double jump: no surface"
FROZEN_SNIPER = "with the ice frozen, the unreachable sniper spots"
FROZEN_SNIPER_OPEN = "with the ice frozen and the brambles burnt, the unreachable sniper spots"
FOUND = "map: every family Expeditions.json `found` names"
ICE_CONFIG = "Combat.json levels.react.ice (L2-53)"
# The L2 W3 fix round (docs/prompts/l2-w3-fix-round.md: s-M1, Q3, s-s2, d-m1, d-m3, d-m4, d-m6, s1, s2).
FALLS = "ForestRoad: a fall through deep water comes back to a landing"
OVERLAP = "ForestRoad: no two ice blocks overlap"
FILL = "with the ice: the built pieces and the colliding blocks and secrets over the water fill every ice block"
FROZEN_DEPTH = "with the ice frozen, every block a body lands on"
FROZEN_BEND = "ForestRoad (frozen): no hop cuts a bend"
FROZEN_RIDGE = "forestRoad (frozen): behind fire: every wall that faces the sealed air is unclimbable"
FROZEN_FLOORS = "forestRoad (frozen) camp C (walled): from every outside surface"
FROZEN_SIGHT = re.compile(r"forestRoad \(frozen\) camp C \(walled\): \(the points on .*\) from no eye point")


def layout(data):
    return data["layouts"]["ForestRoad"]


def camp(data, cid="C"):
    return next(c for c in layout(data)["camps"] if c["id"] == cid)


def block(data, name):
    return next(b for b in layout(data)["blocks"] if b.get("name") == name)


def level(data):
    return next(f for f in data["files"] if f["layout"] == "ForestRoad")


def residents(data, spot):
    return next(g for c in level(data)["camps"] if c["id"] == "C" for g in c["residents"] if g["spot"] == spot)


def stage(data):
    return next(s for s in level(data)["stages"] if s.get("zone") == "C")


def spot(data, sid):
    return next(s for s in camp(data)["spots"] if s["id"] == sid)


def top_at(data, name, top):
    """A block's top moved to `top`, its foot kept."""
    b = block(data, name)
    foot = b["y"] - b["sy"] / 2
    b["sy"] = top - foot
    b["y"] = foot + b["sy"] / 2


def add_block(data, name, look, x0, x1, z0, z1, top, foot=0.0):
    layout(data)["blocks"].append({"name": name, "look": look, "x": (x0 + x1) / 2, "y": (foot + top) / 2,
                                   "z": (z0 + z1) / 2, "sx": x1 - x0, "sy": top - foot, "sz": z1 - z0})


def shift_east(data, by):
    """ambushE's two innermost posts (fodder) `by` studs south, off the north wall toward the line
    a doorway's edge looks along."""
    for point in spot(data, "ambushE")["points"][:2]:
        point["z"] += by


def l1c_wall(data):
    """Camp C as L1c built it, before the L2 W2 second fix round's m1: its fence at the config's 1
    stud and the gatehouse's east and west walls back to z -27, flush with that fence (the sight
    cases calibrated on it keep their meaning; each has a twin on the shipped 2.5-stud wall)."""
    camp(data)["fence"].pop("thickness", None)
    block(data, "GatehouseWallE").update({"z": -40.5, "sz": 27})
    block(data, "GatehouseWallW").update({"z": -31.5, "sz": 9})


def levels(data):
    return data["combat"]["levels"]


def ice(data):
    return data["combat"]["levels"]["react"]["ice"]


def island_at(data, gap):
    """The island and its chest moved north up the creek until the island's flat gap to
    ShrineSignPad (x -390..-380, z 8..18; the island is x -408..-392, 2 studs west of it) is `gap`."""
    centre = 26 + (gap * gap - 4) ** 0.5
    block(data, "ShrineIsland")["z"] = centre
    secret(data, "shrine")["z"] = centre


def water_tops(data, top):
    """Every water block's top moved to `top`, its foot kept."""
    for b in layout(data)["blocks"]:
        if b["look"] == "water":
            top_at(data, b["name"], top)


def ice_block(data, name, x0, x1, z0, z1, top):
    """A deep water block that freezes (no collision, react ice), 4 deep under `top`."""
    add_block(data, name, "water", x0, x1, z0, z1, top, top - 4)
    layout(data)["blocks"][-1].update({"collide": False, "react": "ice"})


def swapped_sim(old, new):
    """A switch value: tools/sim_range.py with `old` swapped for `new`, as a module of its own,
    made (once) when the case that names it runs; a swap whose text is not found exactly once
    raises ValueError (the mutant is stale)."""
    made = {}

    def build():
        if "module" not in made:
            path = TOOLS / "sim_range.py"
            text = path.read_text(encoding="utf-8")
            if text.count(old) != 1:
                raise ValueError(f"the line {old!r} is not found exactly once in sim_range.py (the mutant is stale)")
            module = types.ModuleType("sim_range_swapped")
            module.__file__ = str(path)
            exec(compile(text.replace(old, new), str(path), "exec"), module.__dict__)
            made["module"] = module
        return made["module"]

    build.lazy = True
    return build


def frost_quake_dash(data, alias):
    """The Frost Hammer's Frost Quake given a range of 70 and AbilityService's alias line for it
    pointed at `alias` (the shipped line says earthquake): ctx dashes read again from that text."""
    text = cl.ABILITY_SERVICE_PATH.read_text(encoding="utf-8")
    line = "MECHANICS.frostQuake = MECHANICS.earthquake"
    if text.count(line) != 1:
        raise ValueError(f"the line {line!r} is not found exactly once in AbilityService.luau (the mutant is stale)")
    data["ctx"]["weapons"]["frostHammer"]["ability"]["range"] = 70
    data["ctx"]["dashes"] = cl.dashing_abilities({"weapons": data["ctx"]["weapons"]},
                                                 text.replace(line, f"MECHANICS.frostQuake = MECHANICS.{alias}"))


def secret(data, sid):
    return next(s for s in layout(data)["secrets"] if s["id"] == sid)


def secret_entry(data, sid):
    return level(data)["secrets"][sid]


def air_jump(data):
    return next(a for a in data["expeditions"]["abilities"]["list"] if a["id"] == "doubleJump")


def lift_height(data, height):
    """Every lifting ability's height set to `height` (ctx's copy of ProvingGrounds.json)."""
    data["ctx"]["lifts"] = [(family, dict(ability, height=height)) for family, ability in data["ctx"]["lifts"]]


def lift_fielded(data):
    """The Greataxe (Leap Smash) in the loadout every mission plays with (W2's picker, early)."""
    data["ctx"]["fieldedLifts"] = [family for family, _ability in data["ctx"]["lifts"]]
    data["ctx"]["loadout"] = ["greataxe", "longbow"]


def shift_cave(data, dz):
    """The whole cave `dz` studs south (+z): its blocks, the cache's chest, the shortcut's box and
    the shortcut route off the main road (every point north of the road's edge)."""
    for b in layout(data)["blocks"]:
        if b.get("name", "").startswith("Cave"):
            b["z"] += dz
    secret(data, "cache")["z"] += dz
    for sc in layout(data)["shortcuts"]:
        sc["z"] += dz
    for point in layout(data)["shortcutRoute"]:
        if point["z"] < -52:
            point["z"] += dz


def straight_exit(data):
    """The exit without its turn: the mouth under the exit leg (x -116..-104), the old mouth walled."""
    wall = block(data, "CaveWallExitS")
    wall.update({"x": -88, "sx": 32})  # x -104..-72: over the old mouth
    bramble = block(data, "CaveBrambleE")
    bramble.update({"x": -110, "sx": 13})  # x -116.5..-103.5, flush with RoadAB5's north edge


def ridge_ends(data, x):
    """The 84-high ridge by the lookout (CaveWallS2, CaveRoofE) ends at `x`; the 64-high pieces
    east of it (CaveWallS3, CaveRoofE2) start there."""
    for west, east, x1 in (("CaveWallS2", "CaveWallS3", -118.0), ("CaveRoofE", "CaveRoofE2", -102.0)):
        block(data, west).update({"x": (-221.0 + x) / 2, "sx": x + 221.0})
        block(data, east).update({"x": (x + x1) / 2, "sx": x1 - x})


RIDGE_84 = ("CaveWallS2", "CaveRoofE", "CaveWallAlcoveW", "CaveWallAlcoveE", "CaveWallAlcoveN", "CaveRoofAlcove")


def cliff(data, name, x0, x1, top):
    """A wall block over the lookout ledge's whole depth (z -66..-52), foot -4: the notch's sides."""
    add_block(data, name, "wall", x0, x1, -66, -52, top, -4)


# (label, change(data), {switch: value}, the rule, red?). Controls (red False) show a rule's reach:
# the same data a step inside the line stays green, or the old gate passes what the new one fails.
CASES = (
    # L1c-3 and the walled gate (the 12 cases BALANCE "L1c" lists).
    ("L1c: C's fence 40 (climbable)", lambda d: camp(d)["fence"].__setitem__("height", 40), {}, FENCE, True),
    ("L1c: GatehouseWallW top 50 (climbable)", lambda d: top_at(d, "GatehouseWallW", 50), {}, BAND, True),
    ("L1c: GatehouseWallN top 50 (climbable)", lambda d: top_at(d, "GatehouseWallN", 50), {}, SNIPER, True),
    ("L1c: a ledge 9 studs east of the floor, off the gates",
     lambda d: add_block(d, "MutantLedge", "ground", 380, 390, 40, 60, 12, 8), {}, BESIDE, True),
    ("L1c control: the same ledge 58 studs off",
     lambda d: add_block(d, "MutantLedge", "ground", 429, 439, 40, 60, 12, 8), {}, BESIDE, False),
    ("L1c: TrailEnd off the east gate's lane", lambda d: block(d, "TrailEnd").__setitem__("z", 10), {}, BESIDE, True),
    ("L1c: C's fence 60 (still unclimbable)", lambda d: camp(d)["fence"].__setitem__("height", 60), {}, HEIGHT, True),
    ("L1c: GatehouseWallS top 70 (still unclimbable)", lambda d: top_at(d, "GatehouseWallS", 70), {}, GATEHOUSE,
     True),
    ("L1c: a 40-high tower 53 studs north of the fence",
     lambda d: add_block(d, "MutantTower", "ground", 300, 310, -84, -80, 40), {}, FLOORS, True),
    ("L1c: GatehouseWallE removed",
     lambda d: layout(d)["blocks"].remove(block(d, "GatehouseWallE")), {}, SIGHT, True),
    ("L1c: the innermost east fodder 16 off the centreline",
     lambda d: spot(d, "ambushE")["points"][0].__setitem__("x", 329.5), {}, SIGHT, True),
    ("L1c: an armoured in ambushW on Hard",
     lambda d: residents(d, "ambushW")["units"].append({"kind": "armoured", "count": 1, "minDifficulty": "hard"}),
     {}, PLATES, True),
    ("L1c: 3 more fodder in ambushW on Hard (15)",
     lambda d: residents(d, "ambushW")["units"].append({"kind": "fodder", "count": 3, "minDifficulty": "hard"}),
     {}, LOCKED, True),
    # C1: the camera clip.
    ("C1: levels.cameraClear 0.2 (2a58134's client)", lambda d: levels(d).__setitem__("cameraClear", 0.2), {}, SIGHT,
     True),
    ("C1: levels.cameraClear 2 (over the shake, under a body), on L1c's 1-stud wall",
     lambda d: (l1c_wall(d), levels(d).__setitem__("cameraClear", 2)), {}, SIGHT, True),
    ("C1: levels.cameraClear 0.5 (over the shake 0.35), on the shipped 2.5-stud wall",
     lambda d: levels(d).__setitem__("cameraClear", 0.5), {}, SIGHT, True),
    ("C1: levels.cameraClear 0.2 is under the shake", lambda d: levels(d).__setitem__("cameraClear", 0.2), {},
     CLEAR, True),
    ("C1: levels.cameraClear missing", lambda d: levels(d).pop("cameraClear"), {}, READS, True),
    ("C1 control: cameraClear 0.2 with cameras exempt in the doorway (2a58134's gate)",
     lambda d: levels(d).__setitem__("cameraClear", 0.2), {"EXEMPT_CAMERAS": True}, SIGHT, False),
    # m1: the exact extremes and the drawn body.
    ("m1: ambushE's inner fodder 2.4 off the north wall, on L1c's 1-stud wall",
     lambda d: (l1c_wall(d), shift_east(d, 2.4)), {}, SIGHT, True),
    ("m1 control: the same on the 2-stud grid, radius only (the build's gate), on L1c's 1-stud wall",
     lambda d: (l1c_wall(d), shift_east(d, 2.4),
                d["ctx"].__setitem__("renderer", {"TORSO_WIDTH": 2, "TORSO_DEPTH": 0})),
     {"SIGHT_ZONES": False}, SIGHT, False),
    ("m1: ambushE's inner fodder 4.5 off the north wall, on the shipped 2.5-stud wall", lambda d: shift_east(d, 4.5),
     {}, SIGHT, True),
    ("m1 control: the same on the 2-stud grid, radius only (the build's gate), on the shipped wall",
     lambda d: (shift_east(d, 4.5), d["ctx"].__setitem__("renderer", {"TORSO_WIDTH": 2, "TORSO_DEPTH": 0})),
     {"SIGHT_ZONES": False}, SIGHT, False),
    ("m1: CrowdRenderer's torso keys missing", lambda d: d["ctx"].__setitem__("renderer", {}), {}, READS, True),
    # The margin ruling: every margin at least the camp's sightMargin.
    ("margin: ambushE's innermost fodder back on 2a58134's post (345.5, -22.5), on L1c's 1-stud wall",
     lambda d: (l1c_wall(d), spot(d, "ambushE")["points"][0].update({"x": 345.5, "z": -22.5})), {}, MARGIN, True),
    ("margin: Hard's extra unit a brute again (L1c's mix: a fourth brute fits no hidden post), on L1c's 1-stud wall",
     lambda d: (l1c_wall(d), [unit.__setitem__("kind", "brute") for spot_id in ("ambushW", "ambushE")
                              for unit in residents(d, spot_id)["units"] if unit.get("minDifficulty") == "hard"]),
     {}, MARGIN, True),
    ("margin: sightMargin 2, on L1c's 1-stud wall (+1.57)",
     lambda d: (l1c_wall(d), camp(d).__setitem__("sightMargin", 2)), {}, MARGIN, True),
    ("margin: ambushE's inner fodder 3.5 off the north wall (+0.75, seen from nowhere), on the shipped wall",
     lambda d: shift_east(d, 3.5), {}, MARGIN, True),
    ("margin: sightMargin 4.5, over the shipped wall's +4.09", lambda d: camp(d).__setitem__("sightMargin", 4.5), {},
     MARGIN, True),
    ("margin: sightMargin missing", lambda d: camp(d).pop("sightMargin"), {}, MARGIN, True),
    ("margin control: sightMargin 1.5 with ambushE's inner fodder 0.05 off the wall",
     lambda d: shift_east(d, 0.05), {}, MARGIN, False),
    # m3: the boss room's ambush per difficulty.
    ("m3: 11 on Normal (one more fodder in ambushW)",
     lambda d: residents(d, "ambushW")["units"].append({"kind": "fodder", "count": 1}), {}, LOCKED, True),
    # m4: Floors measured to the nearest tall wall.
    ("m4: a ledge (top 20) 4 studs north of GatehouseWallN",
     lambda d: add_block(d, "MutantPerch", "ground", 290, 300, -62, -58, 20), {}, FLOORS, True),
    ("m4 control: the same ledge measured to the fence alone (the build's rule)",
     lambda d: add_block(d, "MutantPerch", "ground", 290, 300, -62, -58, 20), {"FLOOR_WALLS": False}, FLOORS, False),
    # M3: a camp's own countdown.
    ("M3: gateSeconds 0 on a first wave that brings bodies",
     lambda d: stage(d)["waves"][0].__setitem__("groups", [{"kind": "fodder", "count": 4}]), {}, COUNTDOWN, True),
    ("M3: gateSeconds -1", lambda d: stage(d).__setitem__("gateSeconds", -1), {}, COUNTDOWN, True),
    ("M3: gateSeconds -1 is refused as Validate refuses it", lambda d: stage(d).__setitem__("gateSeconds", -1), {},
     PROBLEMS, True),
    ("M3 control: gateSeconds 0.5 on the shipped (empty) first wave",
     lambda d: stage(d).__setitem__("gateSeconds", 0.5), {}, COUNTDOWN, False),
    # The second fix round's F1 and F3: the walled camp triggers up to its fence's top, over the
    # highest root a player gets in it (cover 3.5 + jump + double jump + Leap Smash + root = 46.5).
    ("F1: C judged at levels.triggerHeight 30 (the first fix round's rule)", None, {"WALLED_CEILING": False},
     CEILING, True),
    # Over 21 the cover is also a step onto the walls (64 = 21 + the 43 a player climbs), so the
    # highest root comes from GatehouseWallN's top: the rule is red either way.
    ("F1: C's first cover 22 high (a root 65 over the floor; the walls turn climbable with it)",
     lambda d: camp(d)["obstacles"][0].__setitem__("sy", 22), {}, CEILING, True),
    ("F1 control: C's first cover 21 high (a root 64, at the fence's top)",
     lambda d: camp(d)["obstacles"][0].__setitem__("sy", 21), {}, CEILING, False),
    # The third fix round's m2 and m3: every nudge lands on the inset rectangle's edge (z -24 along
    # the north side), so the entry and the cover stand 3 studs inside it.
    ("m2: C's entry back at the second round's (313.5, -23), 1 inside the edge",
     lambda d: camp(d)["entry"].update({"x": 313.5, "z": -23}), {}, NUDGE, True),
    ("m2: C's entry at (309.5, -22), 2 inside the edge",
     lambda d: camp(d)["entry"].__setitem__("z", -22), {}, NUDGE, True),
    ("m2 control: C's entry at (309.5, -21), exactly 3 inside the edge",
     lambda d: camp(d)["entry"].__setitem__("z", -21), {}, NUDGE, False),
    ("m3: C's first cover 2 off the inset rectangle's east edge (x 358)",
     lambda d: camp(d)["obstacles"][0].__setitem__("x", 358), {}, NUDGE, True),
    ("m3 control: C's first cover 3 off it (x 357)",
     lambda d: camp(d)["obstacles"][0].__setitem__("x", 357), {}, NUDGE, False),
    # L2-18 (c): today's Leap Smash reaches the ledge from hundreds of take-offs (off a void edge,
    # the caster's floor is his feet; at a jump's top the lift adds its height); the "floor" model
    # (the formula change the designer's report asks for) closes every one, on the same layout.
    # L2-37: every family can enter a level now (W1's known limit is gone).
    ("L2-18c: today's Leap Smash", None, {"LIFT_MODEL": "today"}, REACH_C, True),
    ("L2-18c: today's Leap Smash, the Greataxe in the loadout as well", lift_fielded, {"LIFT_MODEL": "today"}, REACH_C,
     True),
    ("L2-18c control: the floor model", None, {"LIFT_MODEL": "floor"}, REACH_C, False),
    ("L2-18c: Leap Smash height 24 under the floor model", lambda d: lift_height(d, 24),
     {"LIFT_MODEL": "floor"}, REACH_C, True),
    ("L2-18c control: Leap Smash height 18 under the floor model", lambda d: lift_height(d, 18),
     {"LIFT_MODEL": "floor"}, REACH_C, False),
    # At 20 a target on camp A's fence (top 12) lifts the arc to 12 + 20 = 32, over the 31 a step up
    # needs: the floor model's margin is the fence, not the jump.
    ("L2-18c: Leap Smash height 20 under the floor model (a target on A's fence)", lambda d: lift_height(d, 20),
     {"LIFT_MODEL": "floor"}, REACH_C, True),
    # L2-18 (b): one jump, a step up and a dash, unclimbable walls left out.
    ("L2-18b: a ledge (top 14) west of the sign pad", lambda d: add_block(d, "MutantStep", "ground", -310, -306, -62, -56,
                                                                           14, 8), {}, REACH_B, True),
    ("L2-18b control: an unclimbable wall (top 84) on the ledge's east side",
     lambda d: cliff(d, "LookoutCliffE", -275, -271, 84), {}, REACH_B, False),
    ("L2-18b: the same wall 60 high (climbable)", lambda d: cliff(d, "LookoutCliffE", -275, -271, 60), {}, REACH_B, True),
    # L2-18 (a): the owner's band.
    ("L2-18a: the ledge 6 higher (over jump + double jump less 4)",
     lambda d: (top_at(d, "LookoutLedge", 40), secret(d, "lookout").__setitem__("y", 42)), {}, REACH_A, True),
    # L2-18 (d): the trigger met only on the ledge.
    ("L2-18d: the chest at the ledge's front edge (z -54)", lambda d: secret(d, "lookout").__setitem__("z", -54), {},
     REACH_D, True),
    ("L2-18d: secretBelow 25 and secretReach 8 (a root on Road5)",
     lambda d: (levels(d).__setitem__("secretBelow", 25), levels(d).__setitem__("secretReach", 8)), {}, REACH_D, True),
    # Measured from the footprint (the fix round's s1), the ground within secretReach 2.5 of the
    # chest's back face reaches the ledge's back edge (z -66) at z -60.5 and passes it at -61.
    ("L2-18d control: the chest 1.5 further back (z -60.5)", lambda d: secret(d, "lookout").__setitem__("z", -60.5),
     {}, REACH_D, False),
    ("L2-18d: the chest 2 further back (z -61), the trigger over the void behind",
     lambda d: secret(d, "lookout").__setitem__("z", -61), {}, REACH_D, True),
    # The fix round's s1 + d2: (a)'s standable point runs for every secret, its key sold or not.
    # L2 W2: the cache is a 6 x 6 chest in the alcove, and its top has room for a body, so the
    # general (a) always holds through the top; these cases judge the cave's own (a), which asks
    # for a root on the alcove floor beside the chest (L2-37 a).
    ("s1 control: the centre rule at secretReach 5 opens the 6-wide chest from its floor (4 off its centre)",
     lambda d: levels(d).__setitem__("secretReach", 5), {"TRIGGER_MODEL": "centre"}, CACHE_A, False),
    ("s1: the centre rule at today's secretReach 2.5 (a root beside the chest is 4 off its centre)", None,
     {"TRIGGER_MODEL": "centre"}, CACHE_A, True),
    ("s1: secretReach 0.9 (under a body's radius: nobody pressed against the cache opens it)",
     lambda d: levels(d).__setitem__("secretReach", 0.9), {}, CACHE_A, True),
    ("s1 control: the footprint rule, the cache's trigger from beside it", None, {}, TRIGGER_CACHE, False),
    ("s1 control: the centre rule keeps the lookout (its chest's top is within 2.5 of the centre)", None,
     {"TRIGGER_MODEL": "centre"}, TRIGGER_LOOKOUT, False),
    # L2 W2: the chest stands in the alcove (floor 8, roof 22): raised 8, a root beside it is 6 under its
    # foot, and its top has 2 studs under the roof, no room for a body.
    ("s1: the cache's chest raised 8 off its alcove floor",
     lambda d: secret(d, "cache").__setitem__("y", 18), {}, TRIGGER_CACHE, True),
    # L2-18 (e) and L2-13: rewards follow keys.
    ("L2-18e: the cache pays 1 Valor", lambda d: secret_entry(d, "cache").__setitem__("valor", 1), {}, REWARDS, True),
    ("L2-18e: the shrine names a family and no map node gives the Frost Hammer (W3: ice in a cycle)",
     lambda d: (secret_entry(d, "shrine").__setitem__("family", "frostHammer"), d["expeditions"].pop("found")), {},
     REWARDS, True),
    ("L2-13: the lookout pays 10 Valor (its key's price)", lambda d: secret_entry(d, "lookout").__setitem__("valor", 10),
     {}, REWARDS, True),
    ("L2-13 control: the lookout pays 2 Valor", lambda d: secret_entry(d, "lookout").__setitem__("valor", 2), {}, REWARDS,
     False),
    # L2-6, L2-11, L2-14, L2-19: the config.
    ("L2-6: Double Jump's price 0", lambda d: air_jump(d)["price"].__setitem__("valor", 0), {}, ABILITIES, True),
    ("L2-6: Double Jump's price 10.5", lambda d: air_jump(d)["price"].__setitem__("valor", 10.5), {}, ABILITIES, True),
    ("L2-6: Double Jump's price 11 (over one Normal clear)", lambda d: air_jump(d)["price"].__setitem__("valor", 11), {},
     PRICE, True),
    ("L2-6: no doubleJump in the list", lambda d: air_jump(d).__setitem__("id", "glide"), {}, ABILITIES, True),
    ("L2-11: levels.secretReach missing", lambda d: levels(d).pop("secretReach"), {}, SECRET_NUMBERS, True),
    ("L2-11: levels.secretBelow -1", lambda d: levels(d).__setitem__("secretBelow", -1), {}, SECRET_NUMBERS, True),
    ("L2-19: resetSecretsAttribute is GrantValor's name",
     lambda d: d["combat"]["debug"].__setitem__("resetSecretsAttribute", "GrantValor"), {}, LEVERS, True),
    ("L2-14: secretOpen grey", lambda d: d["expeditions"]["looks"]["secretOpen"].__setitem__("color", [150, 150, 150]),
     {}, LOOKS, True),
    # L2-37 (f), closed: the brambles, walls and roof seal the cave at any width.
    ("L2-37f: a 1-stud gap beside the west bramble (x -340..-339)",
     lambda d: block(d, "CaveBrambleW").update({"x": -333.25, "sx": 11.5}), {}, SEALED, True),
    ("L2-37f control: the west bramble flush with the wall's face (x -340..-327.5), no overlap",
     lambda d: block(d, "CaveBrambleW").update({"x": -333.75, "sx": 12.5}), {}, SEALED, False),
    ("L2-37f: a 0.2-stud slit under the east bramble (its foot at 8.2)",
     lambda d: block(d, "CaveBrambleE").update({"y": 15.1, "sy": 13.8}), {}, SEALED, True),
    ("L2-37f: the long leg's roof 3 studs short of the alcove wall (x -342..-224)",
     lambda d: block(d, "CaveRoofW").update({"x": -283, "sx": 118}), {}, SEALED, True),
    ("L2-37f: the ridge 60 high by the ledge (CaveWallS1)", lambda d: top_at(d, "CaveWallS1", 60), {}, RIDGE, True),
    ("L2-37f control: CaveWallS1 81 high (43 over the lookout chest's top, 38)", lambda d: top_at(d, "CaveWallS1", 81),
     {}, RIDGE, False),
    # L2-37 (a): the cache's trigger, met from the alcove only; a roof with no room over it.
    ("L2-37a: the alcove's roof down to 13 (5 over its floor: no room for a body)",
     lambda d: block(d, "CaveRoofAlcove").update({"y": 38.5, "sy": 51}), {}, CACHE_A, True),
    # L2-37 (f), open: the shortcut route.
    ("L2-37f: the long leg's north wall 1 stud in (z -99..-97: 11 wide)",
     lambda d: [block(d, n).update({"z": -98, "sz": 2}) for n in ("CaveWallN1", "CaveWallN2")], {}, SHORTCUT, True),
    ("L2-37f: the step 11 high (the cave's floor at 0 then 11)",
     lambda d: [block(d, n).update({"y": 3.5, "sy": 15}) for n in ("CaveTunnel", "CaveAlcove", "CaveExitLeg", "CaveExit")]
     + [p.__setitem__("y", 11) for p in layout(d)["shortcutRoute"][2:7]], {}, SHORTCUT, True),
    ("L2-37f: the tunnel 14 from fireN's fire (the cave moved 52 south)", lambda d: shift_cave(d, 52), {}, SNEAK_CAVE,
     True),
    ("L2-37f control: the cave 30 south (its long leg 36 from fireN's fire)", lambda d: shift_cave(d, 30), {},
     SNEAK_CAVE, False),
    # R8 with L2-37's sight.
    ("L2-37 R8: the exit without its turn (the mouth under the exit leg)", straight_exit, {}, SNIPER_OPEN, True),
    ("L2-37 R8: no sight rule (W1's: every unreachable top within the Longbow's range)", None, {"SIGHT_WALLS": False},
     SNIPER, True),
    # L2-37 (e) and the chain.
    ("L2-37e: the cache pays 10 Valor (its chain's Double Jump price)",
     lambda d: secret_entry(d, "cache").__setitem__("valor", 10), {}, REWARDS, True),
    ("L2-37e control: the cache pays 9 Valor", lambda d: secret_entry(d, "cache").__setitem__("valor", 9), {}, REWARDS,
     False),
    ("L2-37e: the cache pays 70 Timber (32% of the Normal stock)",
     lambda d: secret_entry(d, "cache").__setitem__("materials", 70), {}, REWARDS, True),
    ("L2-37e: the lookout pays nothing (no Flamethrower: fire never resolves)",
     lambda d: level(d)["secrets"].__setitem__("lookout", {"name": "The Lookout"}), {}, REWARDS, True),
    ("L2-37e: the Flamethrower carries no element", lambda d: d["ctx"]["weapons"]["flamethrower"].pop("element"), {},
     REWARDS, True),
    ("L2-37e control: the lookout pays 2 Valor and the Flamethrower only",
     lambda d: level(d)["secrets"].__setitem__("lookout", {"name": "The Lookout", "valor": 2, "family": "flamethrower"}),
     {}, REWARDS, False),
    # L2-34 and L2-36: Validate's new lines.
    ("L2-34: a bramble opens a shortcut that does not exist", lambda d: block(d, "CaveBrambleE").__setitem__("opens", "tunnel"),
     {}, PROBLEMS, True),
    ("L2-34: a bramble that reacts to water", lambda d: block(d, "CaveBrambleW").__setitem__("react", "water"), {},
     PROBLEMS, True),
    ("L2-34: a bramble that does not collide", lambda d: block(d, "CaveBrambleW").__setitem__("collide", False), {},
     PROBLEMS, True),
    ("L2-36: the shortcut id twice", lambda d: layout(d)["shortcuts"].append(dict(layout(d)["shortcuts"][0])), {},
     PROBLEMS, True),
    ("L2-34: levels.react.fireHits 0", lambda d: levels(d)["react"].__setitem__("fireHits", 0), {}, REACT, True),
    ("L2-38: grantFamilyAttribute is DebugGrantAbility's name",
     lambda d: d["combat"]["debug"].__setitem__("grantFamilyAttribute", "DebugGrantAbility"), {}, LEVERS, True),
    ("L2-34: the bramble look grey", lambda d: d["expeditions"]["looks"]["bramble"].__setitem__("color", [110, 112, 104]),
     {}, LOOKS, True),
    # The fix round's d-M1: no lift or air dash of a Double Jump owner ends on the ridge.
    ("d-M1: the ridge by the ledge back at 64 (W2's data: CaveWallS2, CaveRoofE and the alcove)",
     lambda d: [top_at(d, n, 64) for n in RIDGE_84], {}, RIDGE_LIFT, True),
    ("d-M1: the 84 ridge ends at x -205 (the Spear's air dash onto CaveWallS3)", lambda d: ridge_ends(d, -205), {},
     RIDGE_LIFT, True),
    ("d-M1 control: the 84 ridge ends at x -195", lambda d: ridge_ends(d, -195), {}, RIDGE_LIFT, False),
    ("d-M1: no air dash, the 84 ridge ends at x -210 (Leap Smash onto CaveWallS3)",
     lambda d: (d["ctx"].__setitem__("dashes", []), ridge_ends(d, -210)), {}, RIDGE_LIFT, True),
    ("d-M1 control: no air dash, the 84 ridge ends at x -205",
     lambda d: (d["ctx"].__setitem__("dashes", []), ridge_ends(d, -205)), {}, RIDGE_LIFT, False),
    # The fix round's d-m1: the ridge's reach includes the walk-off grace (46.6 -> 49.3).
    ("d-m1: a perch at 34, 48 studs off CaveWallS3 (inside the grace's 49.3, outside 46.6)",
     lambda d: add_block(d, "MutantPerch", "ground", -180, -176, -34, -30, 34, 30), {}, RIDGE, True),
    ("d-m1 control: the same perch 50 studs off", lambda d: add_block(d, "MutantPerch", "ground", -180, -176, -32, -28, 34, 30),
     {}, RIDGE, False),
    # The fix round's d-m2: the bend cut with an ability's travel is a known limit only while no
    # family that carries can be owned without a lever.
    ("d-m2: the cache pays the Spear (a family that carries, owned without a lever)",
     lambda d: secret_entry(d, "cache").__setitem__("family", "spear"), {}, BEND_LIFT, True),
    ("d-m2 control: the cache pays the Longbow (a family that does not carry)",
     lambda d: secret_entry(d, "cache").__setitem__("family", "longbow"), {}, BEND_LIFT, False),
    # The fix round's s-m3: Validate refuses a shortcut size of 0 or below (the mirror's line).
    ("s-m3: the shortcut's sz 0", lambda d: layout(d)["shortcuts"][0].__setitem__("sz", 0), {}, PROBLEMS, True),
    ("s-m3: the shortcut's sx -12", lambda d: layout(d)["shortcuts"][0].__setitem__("sx", -12), {}, PROBLEMS, True),
    ("s-m3 control: the shortcut's sy 0.01", lambda d: layout(d)["shortcuts"][0].__setitem__("sy", 0.01), {}, PROBLEMS,
     False),
    # The second fix round's m1: shooting.originWallChord is under the thickness of every tall
    # colliding piece, camp C's generated wall included (its own fence.thickness 2.5).
    ("fix2 m1: camp C's fence at the config's 1 (no thickness of its own: today's 1-stud wall)",
     lambda d: camp(d)["fence"].pop("thickness"), {}, CHORD, True),
    ("fix2 m1: originWallChord 2.5 (as thick as camp C's wall)", lambda d: d["ctx"].__setitem__("originWallChord", 2.5),
     {}, CHORD, True),
    ("fix2 m1: originWallChord 6 (shooting.originPad's number)", lambda d: d["ctx"].__setitem__("originWallChord", 6),
     {}, CHORD, True),
    ("fix2 m1 control: originWallChord 1.9 (under the 2-stud walls and brambles)",
     lambda d: d["ctx"].__setitem__("originWallChord", 1.9), {}, CHORD, False),
    ("fix2 m1: a 1-stud wall 6 over the road beside Road2",
     lambda d: add_block(d, "MutantWall", "wall", -370, -350, 8, 9, 6, -4), {}, CHORD, True),
    ("fix2 m1 control: the same 1-stud rail 4 over the road (a standing head clears it)",
     lambda d: add_block(d, "MutantWall", "wall", -370, -350, 8, 9, 4, -4), {}, CHORD, False),
    ("fix2 m1: camp C's fence.thickness 0", lambda d: camp(d)["fence"].__setitem__("thickness", 0), {}, THICKNESS, True),
    ("fix2 m1: camp C's fence.thickness \"2.5\"", lambda d: camp(d)["fence"].__setitem__("thickness", "2.5"), {},
     THICKNESS, True),
    # L2-47: the AB bend.
    ("L2-47: the bend wall removed", lambda d: layout(d)["blocks"].remove(block(d, "BendWall")), {}, BEND, True),
    ("L2-47: the bend wall only between the roads (z -52..-8: a hop round its north end)",
     lambda d: block(d, "BendWall").update({"z": -30, "sz": 44}), {}, BEND, True),
    ("L2-47 control: the bend wall 4 short of the ridge (z -78..-8: the way round is 58)",
     lambda d: block(d, "BendWall").update({"z": -43, "sz": 70}), {}, BEND, False),
    # L2 W3: deep water (L2-52, L2-57, L2-60) and Validate's ice and landing lines (the mirror's).
    ("W3 deep: the Creek solid again", lambda d: block(d, "Creek").pop("collide"), {}, DEEP, True),
    ("W3 deep: the Pond reacts to nothing", lambda d: block(d, "Pond").pop("react"), {}, DEEP, True),
    ("W3 deep: the water's tops at -0.25 (0.25 under the bridge)", lambda d: water_tops(d, -0.25), {}, DEEP, True),
    ("W3 deep control: the water's tops at -0.5 (0.5 under the bridge)", lambda d: water_tops(d, -0.5), {}, DEEP, False),
    ("W3 deep: the pond's top 1 under the creek's", lambda d: top_at(d, "Pond", -2), {}, DEEP, True),
    # With its landing gone too: since the fix round's Q3 a landing on a block that collides is
    # refused on its own line, which would keep this case red without the ice line.
    ("W3 L2-52: an ice block that collides (no landing)",
     lambda d: (block(d, "Creek").pop("collide"), block(d, "Creek").pop("landing")), {}, PROBLEMS, True),
    ("W3 L2-52: an ice block that opens the cave", lambda d: block(d, "Creek").__setitem__("opens", "cave"), {}, PROBLEMS,
     True),
    # The W3 fix round's Q3: any deep water may carry a landing (CreekUp does); a block that collides may not.
    ("W3 L2-58: a landing on a block that collides (Road2)",
     lambda d: block(d, "Road2").__setitem__("landing", {"x": -385, "y": 0, "z": 2}), {}, PROBLEMS, True),
    ("W3 L2-58: a landing whose y is a string", lambda d: block(d, "Pond")["landing"].__setitem__("y", "0"), {}, PROBLEMS,
     True),
    ("W3 L2-58: the Creek's landing over the void (-385, 0, 30)",
     lambda d: block(d, "Creek")["landing"].__setitem__("z", 30), {}, LANDING, True),
    ("W3 L2-58: the Pond's landing a stud over Road2", lambda d: block(d, "Pond")["landing"].__setitem__("y", 1), {},
     LANDING, True),
    ("W3 L2-58: the Creek's landing on camp A's floor",
     lambda d: block(d, "Creek").__setitem__("landing", {"x": -221.5, "y": 8, "z": -16}), {}, LANDING, True),
    ("W3 L2-58 control: the landing on ShrineSignPad (-385, 0, 13)",
     lambda d: block(d, "Creek")["landing"].__setitem__("z", 13), {}, LANDING, False),
    # L2-60 (g): the island behind ice with the water as built. The reaches (ForestRoad, today's
    # movement): the jumps 49.3, Leap Smash after the jumps and a dash 71.0, Impale Dash held in the
    # air 80.6; the gap must be that and ICE_MARGIN 15 more (95.6); today it is 102.
    ("W3 g: the island 45 from the sign pad (the jumps)", lambda d: island_at(d, 45), {}, ICE_JUMPS, True),
    ("W3 g control: the island 52 from the sign pad (beyond the jumps' 49.3)", lambda d: island_at(d, 52), {}, ICE_JUMPS,
     False),
    ("W3 g: no air dash, the island 65 from the sign pad (Leap Smash after the jumps and a dash)",
     lambda d: (d["ctx"].__setitem__("dashes", []), island_at(d, 65)), {}, ICE_LIFT, True),
    ("W3 g control: no air dash, the island 75 from the sign pad",
     lambda d: (d["ctx"].__setitem__("dashes", []), island_at(d, 75)), {}, ICE_LIFT, False),
    ("W3 g: the island 75 from the sign pad (the Spear's Impale Dash held in the air)", lambda d: island_at(d, 75), {},
     ICE_DASH, True),
    ("W3 g control: the island 85 from the sign pad (beyond the air dash's 80.6)", lambda d: island_at(d, 85), {},
     ICE_DASH, False),
    ("W3 g: the island 85 from the sign pad (inside the air dash + ICE_MARGIN)", lambda d: island_at(d, 85), {}, ICE_GAP,
     True),
    ("W3 g control: the island 96 from the sign pad", lambda d: island_at(d, 96), {}, ICE_GAP, False),
    ("W3 a/d: the chest 6 east on the island (its trigger reaches off it)",
     lambda d: secret(d, "shrine").__setitem__("x", -394), {}, ICE_TRIGGER, True),
    ("W3 a/d control: the chest 1.5 east (its trigger's edge 0.5 inside the island's)",
     lambda d: secret(d, "shrine").__setitem__("x", -398.5), {}, ICE_TRIGGER, False),
    # L2-60 (h): frozen, the swing and the chain.
    ("W3 h: ice.cell 12 (one swing no longer freezes 1.5 rows)", lambda d: ice(d).__setitem__("cell", 12), {}, ICE_SWING,
     True),
    ("W3 h control: ice.cell 8 ((9 + 4 - 1) / 1.5)", lambda d: ice(d).__setitem__("cell", 8), {}, ICE_SWING, False),
    ("W3 h: ice.reachDown 3.5 (under Road2's root over the water, 4)", lambda d: ice(d).__setitem__("reachDown", 3.5), {},
     ICE_SWING, True),
    ("W3 h control: ice.reachDown 4", lambda d: ice(d).__setitem__("reachDown", 4), {}, ICE_SWING, False),
    ("W3 h: the Frost Hammer carries no element (no family freezes)",
     lambda d: d["ctx"]["weapons"]["frostHammer"].pop("element"), {}, ICE_SWING, True),
    ("W3 h: a gap in the cell chain (the creek ends at z 80, 16 short of the pond)",
     lambda d: block(d, "Creek").update({"z": 44, "sz": 72}), {}, ICE_CHAIN, True),
    # The fix round's d-m1: a cover skips only the cells it holds whole, so the dam holds row 6
    # (z 48.62..55.38) whole; the first dam (z 50..54) left every cell built under it. It is 50
    # high, unclimbable: a low dam that whole row lies beside is a bank the chain starts from again.
    ("W3 h: a wall across the creek covers a row of cells whole (z 48..56, top 50)",
     lambda d: add_block(d, "MutantDam", "wall", -412, -388, 48, 56, 50, -1.5), {}, ICE_CHAIN, True),
    ("W3 fix d-m1 control: the first dam, z 50..54, holds no cell whole (every cell built, the chain whole)",
     lambda d: add_block(d, "MutantDam", "wall", -412, -388, 50, 54, 0.5, -1.5), {}, ICE_CHAIN, False),
    ("W3 h: the island 66 south of the pond (no ice reaches it)",
     lambda d: (block(d, "ShrineIsland").__setitem__("z", 230), secret(d, "shrine").__setitem__("z", 230)), {}, ICE_FROZEN,
     True),
    # The W2 lessons on the frozen layout: no new ledge route, wall or sniper spot.
    ("W3 frozen: a pond 17 high beside the lookout ledge (one jump onto it once frozen)",
     lambda d: ice_block(d, "MutantIce", -295, -271, -80, -68, 17), {}, FROZEN_LEDGE, True),
    ("W3 frozen control: the same pond 6 high", lambda d: ice_block(d, "MutantIce", -295, -271, -80, -68, 6), {},
     FROZEN_LEDGE, False),
    ("W3 frozen: a pond 42 high 4 off CaveWallS1 (the ridge climbable once frozen)",
     lambda d: ice_block(d, "MutantIce", -255, -245, -78, -70, 42), {}, ICE_WALLS, True),
    ("W3 frozen: a pond south of Road4 (a new sniper spot once frozen)",
     lambda d: ice_block(d, "MutantPond", -330, -310, -30, -12, -1), {}, FROZEN_SNIPER, True),
    ("W3 frozen: the same pond, the brambles burnt",
     lambda d: ice_block(d, "MutantPond", -330, -310, -30, -12, -1), {}, FROZEN_SNIPER_OPEN, True),
    # L2-51: the family found on a map node; L2-59: the shrine's pay under the chain's cap.
    ("W3 L2-51: found names no node", lambda d: d["expeditions"]["found"]["frostHammer"].__setitem__("node", "volcano"),
     {}, FOUND, True),
    ("W3 L2-51: found's text 41 characters",
     lambda d: d["expeditions"]["found"]["frostHammer"].__setitem__("text", "x" * 41), {}, FOUND, True),
    ("W3 L2-51 control: found's text 40 characters",
     lambda d: d["expeditions"]["found"]["frostHammer"].__setitem__("text", "x" * 40), {}, FOUND, False),
    ("W3 L2-51: the Broadsword found (a starter)",
     lambda d: d["expeditions"]["found"].__setitem__("broadsword", {"node": "castle", "text": "Found in the Castle"}), {},
     FOUND, True),
    ("W3 L2-51: found names a family no weapon has",
     lambda d: d["expeditions"]["found"].__setitem__("iceBow", {"node": "castle", "text": "Found in the Castle"}), {},
     FOUND, True),
    ("W3 L2-51: the cache also pays the Frost Hammer",
     lambda d: secret_entry(d, "cache").__setitem__("family", "frostHammer"), {}, FOUND, True),
    ("W3 L2-59: the shrine pays 10 Valor (the dearest sold ability's price)",
     lambda d: secret_entry(d, "shrine").__setitem__("valor", 10), {}, REWARDS, True),
    ("W3 L2-59 control: the shrine pays 9 Valor", lambda d: secret_entry(d, "shrine").__setitem__("valor", 9), {}, REWARDS,
     False),
    ("W3 L2-59: the shrine pays 67 Timber (over 30% of the Normal stock 220)",
     lambda d: secret_entry(d, "shrine").__setitem__("materials", 67), {}, REWARDS, True),
    ("W3 L2-51: no found entry, the shrine pays (nothing holds ice)", lambda d: d["expeditions"].pop("found"), {}, REWARDS,
     True),
    # L2-53: the ice config.
    ("W3 L2-53: levels.react.ice.cell 0", lambda d: ice(d).__setitem__("cell", 0), {}, ICE_CONFIG, True),
    ("W3 L2-53: levels.react.ice missing", lambda d: levels(d)["react"].pop("ice"), {}, ICE_CONFIG, True),
    ("W3 L2-53: iceHits back in levels.react", lambda d: levels(d)["react"].__setitem__("iceHits", 6), {}, ICE_CONFIG,
     True),
    # The W3 fix round (docs/prompts/l2-w3-fix-round.md). s-M1 and Q3: a fall comes back to a landing.
    ("W3 fix Q3: CreekUp has no landing (Road2's north edge falls into it)",
     lambda d: block(d, "CreekUp").pop("landing"), {}, FALLS, True),
    ("W3 fix Q3: CreekUp's landing over the void (-400, 0, -20)",
     lambda d: block(d, "CreekUp")["landing"].__setitem__("z", -20), {}, LANDING, True),
    ("W3 fix s-M1: player.rescue.outside 2 (under one server frame of the dash, 2.22)",
     lambda d: d["ctx"]["rescue"].__setitem__("outside", 2), {}, FALLS, True),
    ("W3 fix s-M1 control: player.rescue.outside 2.5",
     lambda d: d["ctx"]["rescue"].__setitem__("outside", 2.5), {}, FALLS, False),
    # s-s2: ice footprints touch, never overlap (Validate's mirror and check_levels' own line).
    ("W3 fix s-s2: the Pond 1 stud into the Creek (z 95..156)",
     lambda d: block(d, "Pond").update({"z": 125.5, "sz": 61}), {}, OVERLAP, True),
    ("W3 fix s-s2: the same overlap, Validate's mirror", lambda d: block(d, "Pond").update({"z": 125.5, "sz": 61}), {},
     PROBLEMS, True),
    ("W3 fix s-s2 control: the Pond 1 stud short of the Creek (z 97..156)",
     lambda d: block(d, "Pond").update({"z": 126.5, "sz": 59}), {}, OVERLAP, False),
    # d-m1: a cell is left out only where one cover holds it whole; the old centre rule leaves two
    # slits beside the island (48.5 studs² of the Pond) that the fill line sees.
    ("W3 fix d-m1: sim_range.ice_cells back on the centre rule (the island's two slits)", None,
     {"sr": swapped_sim(
         "if any(c[4] > water and abs(cx - c[0]) + wx / 2 <= c[2] / 2 + GEOMETRY_SEAM\n"
         "                       and abs(cz - c[1]) + wz / 2 <= c[3] / 2 + GEOMETRY_SEAM for c in covers):",
         "if any(c[4] > water and abs(cx - c[0]) <= c[2] / 2\n"
         "                       and abs(cz - c[1]) <= c[3] / 2 for c in covers):")},
     FILL, True),
    # d-m3: Leap Smash's fall from a high top. With no air dash, a 34-high tower 92 south of the
    # island: the Leap reaches 71.0 and its fall 12.3 more (83.2 + 15 > 92); without the fall term
    # the margin would read +21.0.
    ("W3 fix d-m3: no air dash, a 34-high tower 92 south of the island (Leap Smash and its fall)",
     lambda d: (d["ctx"].__setitem__("dashes", []), add_block(d, "MutantTower", "ground", -404, -396, 228, 236, 34, 30)),
     {}, ICE_GAP, True),
    ("W3 fix d-m3 control: the same tower 99 south (83.2 + 15 < 99)",
     lambda d: (d["ctx"].__setitem__("dashes", []), add_block(d, "MutantTower", "ground", -404, -396, 235, 243, 34, 30)),
     {}, ICE_GAP, False),
    # d-m4: the walk-off grace in the jumps' rule: 46.6 without it, 49.3 with it.
    ("W3 fix d-m4: the island 48 from the sign pad (inside the walk-off grace: 46.6 < 48 < 49.3)",
     lambda d: island_at(d, 48), {}, ICE_JUMPS, True),
    # d-m6: a frozen sheet is a floor, levels.floorThickness deep.
    ("W3 fix d-m6: ice.thickness 1 (a frozen sheet thinner than levels.floorThickness 4)",
     lambda d: ice(d).__setitem__("thickness", 1), {}, FROZEN_DEPTH, True),
    # s1: an ability whose MECHANICS line aliases a dash's is a dash.
    ("W3 fix s1: Frost Quake (range 70) aliased to Impale Dash: an air dash onto the island",
     lambda d: frost_quake_dash(d, "impaleDash"), {}, ICE_DASH, True),
    ("W3 fix s1 control: the same range on the Earthquake alias it ships with (no dash)",
     lambda d: frost_quake_dash(d, "earthquake"), {}, ICE_DASH, False),
    # s2: the bend rule, the cave's closed half and the walled camp on the frozen layout.
    ("W3 fix s2: a frozen bay south of Road1 to Road3 (x -436..-356, z -60..-52): a hop from it cuts the gap",
     lambda d: ice_block(d, "MutantBay", -436, -356, -60, -52, -1), {}, FROZEN_BEND, True),
    ("W3 fix s2: a pond 42 high 4 off CaveWallS1 (the ridge climbable once frozen), the cave's frozen run",
     lambda d: ice_block(d, "MutantIce", -255, -245, -78, -70, 42), {}, FROZEN_RIDGE, True),
    ("W3 fix s2: a pond 40 high 26 north of the gatehouse (a camera over it once frozen)",
     lambda d: ice_block(d, "MutantPond", 300, 310, -84, -80, 40), {}, FROZEN_FLOORS, True),
    ("W3 fix s2: TrailEnd off the east gate's lane, reached over a frozen sheet only (its eyes see in)",
     lambda d: (block(d, "TrailEnd").__setitem__("z", 10), ice_block(d, "MutantSheet", 325, 360, -50, -30, 12)), {},
     FROZEN_SIGHT, True),
    ("W3 fix s2 control: TrailEnd off the lane with no sheet (nobody reaches it, frozen or not)",
     lambda d: block(d, "TrailEnd").__setitem__("z", 10), {}, FROZEN_SIGHT, False),
)


def matches(rule, text):
    return bool(rule.search(text)) if isinstance(rule, re.Pattern) else rule in text


def run(base, change=None, switches=None):
    """Every gate on a copy of `base` after `change`: (failed lines, passed lines)."""
    data = copy.deepcopy(base)
    if change is not None:
        change(data)
    failed, passed = [], []

    def expect(ok, text):
        (passed if ok else failed).append(text)

    saved = {key: getattr(cl, key) for key in (switches or {})}
    try:
        for key, value in (switches or {}).items():
            setattr(cl, key, value() if getattr(value, "lazy", False) else value)
        with contextlib.redirect_stdout(io.StringIO()):
            cl.run_gates(data["combat"], data["expeditions"], data["layouts"], data["files"], data["ctx"], expect)
    finally:
        for key, value in saved.items():
            setattr(cl, key, value)
    return failed, passed


def load():
    combat, expeditions, layouts, files, ctx = cl.load_all()
    return {"combat": combat, "expeditions": expeditions, "layouts": layouts, "files": files, "ctx": ctx}


# The stage-mirror cases: (label, StageFlow.luau's line -> its broken copy (None = untouched),
# sim_range.py's line -> its broken copy, text check_stage_mirror's failing line must carry).
MIRROR_CASES = (
    # m2: the "residents under the boss room's maxAlive" rule taken out of BOTH sides at once.
    ("m2: the boss room's maxAlive rule out of both mirrors",
     ("if held >= cap then", "if held >= cap + 999999 then"),
     ('if residents.get(camp["id"], 0) >= cap:', 'if residents.get(camp["id"], 0) >= cap + 999999:'),
     "the boss room's residents at its maxAlive"),
    # The second fix round's F1: the walled camp's band taken out of the Python mirror alone (the
    # Luau side's mutants are tools/crowd_harness/mirror_mutants.py's).
    ("F1: sim_range's trigger asks triggerHeight again (the mirror alone)", None,
     ('self.rules["triggerBelow"] <= above <= zone["ceiling"]',
      'self.rules["triggerBelow"] <= above <= self.rules["triggerHeight"]'), "StageFlow.Advance: scripted runs"),
    ("F1: sim_range's trigger_ceiling ignores the fence (the mirror alone)", None,
     ("return top if finite(top) and top > trigger_height else trigger_height", "return trigger_height"),
     "StageFlow.Ceiling"),
    # The third fix round's m3: gate_nudge without its fenced-rectangle test (the mirror alone): a
    # root out on the road would be nudged, not sent to the entry.
    ("m3: sim_range's gate_nudge drops the fenced-rectangle test (the mirror alone)", None,
     ("    if not (abs(x - tx) <= thx and abs(z - tz) <= thz):\n        return None\n", ""),
     "StageFlow.GateNudge"),
    # The L2 W2 fix round's s-m3: the shortcut size rule out of the Python mirror alone (the Luau
    # side's mutant is tools/crowd_harness/mutate.py's).
    ("s-m3: sim_range's react_problems takes a shortcut size of 0 (the mirror alone)", None,
     ("            if finite(entry.get(key)) and entry[key] <= 0:", "            if False:"),
     "a shortcut with an sz of 0"),
    # The L2 W2 second fix round's m1: a camp's own fence.thickness out of the Python mirror alone
    # (the Luau side's mutants are tools/crowd_harness/mutate.py's).
    ("fix2 m1: sim_range's fence_thickness ignores the camp's own (the mirror alone)", None,
     ("        return own\n", "        return default\n"), "LevelGeometry.FenceThickness"),
    # L2 W3 (L2-52): an ice block that collides, accepted by the Python mirror alone (the Luau side's
    # mutants are tools/crowd_harness/mutate.py's). The mirror's refusal case carries this label; it
    # has no landing, since the fix round's Q3 refuses a landing on a block that collides on its own.
    ("W3 L2-52: sim_range's react_problems takes an ice block that collides (the mirror alone)", None,
     ('                if block.get("collide") is not False:\n                    problem(f"{where} is ice and collides")',
      '                if False:\n                    problem(f"{where} is ice and collides")'),
     "a pool that collides, with no landing"),
    # The W3 fix round's Q3: a landing on any block that does not collide; s-s2: ice footprints
    # that overlap. Each out of the Python mirror alone (the Luau side's are mutate.py's).
    ("W3 fix Q3: sim_range's react_problems takes a landing on a block that collides (the mirror alone)", None,
     ('            if block.get("collide") is not False:\n                problem(f"{where} has a landing and collides")',
      '            if False:\n                problem(f"{where} has a landing and collides")'),
     "a plain block that collides, with a landing"),
    ("W3 fix s-s2: sim_range's react_problems takes two ice blocks that overlap (the mirror alone)", None,
     ("            if ice_overlap(other, block):", "            if False:"),
     "a second pool overlapping the first"),
)


def stage_mirror_case(luau, flow_swap, py_swap, want):
    """Run tools/check_stage_mirror.py against copies of StageFlow.luau and sim_range.py with one
    line of each swapped (in a temporary folder; nothing in the repo is touched); its run must fail
    with a FAIL line carrying `want`. (ok, what was seen)."""
    flow = REPO / "src" / "combat" / "server" / "Services" / "StageFlow.luau"
    mirror = TOOLS / "sim_range.py"
    flow_text, py_text = flow.read_text(encoding="utf-8"), mirror.read_text(encoding="utf-8")
    for text, swap in ((flow_text, flow_swap), (py_text, py_swap)):
        if swap is not None and text.count(swap[0]) != 1:
            return False, f"the line {swap[0]!r} is not found exactly once (the mutant is stale)"
    if flow_swap is not None:
        flow_text = flow_text.replace(*flow_swap)
    py_text = py_text.replace(*py_swap)
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "StageFlow.luau").write_text(flow_text, encoding="utf-8", newline="\n")
        (root / "sim_range.py").write_text(py_text, encoding="utf-8", newline="\n")
        # The broken mirror runs as tools/sim_range.py itself (its paths are its file's), then the
        # stage mirror imports it from sys.modules.
        boot = ("import sys, types, runpy; sys.path.insert(0, sys.argv[3]); "
                "m = types.ModuleType('sim_range'); m.__file__ = sys.argv[2]; sys.modules['sim_range'] = m; "
                "exec(compile(open(sys.argv[1], encoding='utf-8').read(), sys.argv[2], 'exec'), m.__dict__); "
                "sys.argv = [sys.argv[4]] + sys.argv[5:]; runpy.run_path(sys.argv[0], run_name='__main__')")
        done = subprocess.run([sys.executable, "-c", boot, str(root / "sim_range.py"), str(mirror), str(TOOLS),
                               str(TOOLS / "check_stage_mirror.py"), "--luau", str(luau),
                               "--module", f"StageFlow={root / 'StageFlow.luau'}"],
                              capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = done.stdout + done.stderr
    verdict = next((line.strip() for line in out.splitlines() if line.startswith("CHECK:")), "no CHECK line")
    named = [line.strip() for line in out.splitlines()
             if want in line and not line.lstrip().startswith(("ok", "note", "CHECK"))]
    return (done.returncode != 0 and verdict.startswith("CHECK: FAIL") and bool(named),
            verdict + (f"; {named[0]}" if named else f"; no failing line carries {want!r}"))


# The simulator's cases: (label, sim_range.py's line -> its broken copy, sim_range's arguments, text
# its failing line must carry). The fix round's d3: the planner offers a jump in the air again (its
# can_jump guard gone), so a timed jump leaves while he is airborne; the forest check's one-jump
# gate must count it and go red (it could not before the fix: the timed press dropped it unseen).
# About five minutes: the whole forest check runs.
SIM_CASES = (
    ("d3: the planner may jump in the air (can_jump always true)",
     ("can_jump = self.jump is None and (self.lift is None or t >= self.lift[1])", "can_jump = True"),
     ("--check", "--levels-only", "--level", "forest"), ONE_JUMP),
)


def sim_case(swap, arguments, want):
    """Run tools/sim_range.py from a copy with one line swapped (in a temporary folder, run as the
    real file so its paths hold, and registered as `sim_range` so its importers see the copy); it
    must exit 1 with a FAIL line carrying `want`. (ok, what was seen)."""
    mirror = TOOLS / "sim_range.py"
    text = mirror.read_text(encoding="utf-8")
    if text.count(swap[0]) != 1:
        return False, f"the line {swap[0]!r} is not found exactly once (the mutant is stale)"
    with tempfile.TemporaryDirectory() as folder:
        copy_path = Path(folder) / "sim_range.py"
        copy_path.write_text(text.replace(*swap), encoding="utf-8", newline="\n")
        boot = ("import sys, types; sys.path.insert(0, sys.argv[3]); "
                "m = types.ModuleType('sim_range'); m.__file__ = sys.argv[2]; sys.modules['sim_range'] = m; "
                "code = compile(open(sys.argv[1], encoding='utf-8').read(), sys.argv[2], 'exec'); "
                "sys.argv = [sys.argv[2]] + sys.argv[4:]; m.__dict__['__name__'] = '__main__'; exec(code, m.__dict__)")
        done = subprocess.run([sys.executable, "-c", boot, str(copy_path), str(mirror), str(TOOLS), *arguments],
                              capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = done.stdout + done.stderr
    verdict = next((line.strip() for line in out.splitlines() if line.startswith("CHECK")), "no CHECK line")
    named = [line.strip() for line in out.splitlines() if want in line and line.lstrip().startswith("FAIL")]
    return (done.returncode != 0 and bool(named),
            verdict + (f"; {named[0]}" if named else f"; no FAIL line carries {want!r}"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", default=None, help="run only the cases whose label holds this text")
    parser.add_argument("--luau", default=str(TOOLS / "bin" / "luau.exe"), help="the Luau interpreter (the stage-mirror cases)")
    args = parser.parse_args()
    base = load()
    wrong = []
    failed, _passed = run(base)
    ok = not failed
    print(f"  {'ok  ' if ok else 'NOT '}  the shipped data: every gate green"
          + ("" if ok else ": " + "; ".join(failed[:3])))
    if not ok:
        wrong.append("the shipped data")
    for label, change, switches, rule, red in CASES:
        if args.only and args.only not in label:
            continue
        try:
            failed, passed = run(base, change, switches)
        except ValueError as stale:
            print(f"  NOT   {label}: {stale}")
            wrong.append(label)
            continue
        hit = [text for text in failed if matches(rule, text)]
        seen = [text for text in passed if matches(rule, text)]
        good = bool(hit) if red else (not hit and bool(seen))
        want = "red" if red else "green"
        line = hit[0] if hit else (seen[0] if seen else "the rule did not run")
        print(f"  {'ok  ' if good else 'NOT '}  {label}: {want} -> {line[:220]}")
        if not good:
            wrong.append(label)
    luau = Path(args.luau)
    for label, flow_swap, py_swap, want in MIRROR_CASES:
        if args.only and args.only not in label:
            continue
        if not luau.exists():
            print(f"  skip  {label}: no Luau interpreter at {luau} (give --luau)")
            continue
        good, seen = stage_mirror_case(luau, flow_swap, py_swap, want)
        print(f"  {'ok  ' if good else 'NOT '}  {label}: check_stage_mirror red -> {seen[:220]}")
        if not good:
            wrong.append(label)
    for label, swap, arguments, want in SIM_CASES:
        if args.only and args.only not in label:
            continue
        good, seen = sim_case(swap, arguments, want)
        print(f"  {'ok  ' if good else 'NOT '}  {label}: sim_range red -> {seen[:220]}")
        if not good:
            wrong.append(label)
    print()
    print(f"MUTANTS: {'PASS' if not wrong else 'FAIL (' + ', '.join(wrong) + ')'}")
    sys.exit(0 if not wrong else 1)


if __name__ == "__main__":
    main()
