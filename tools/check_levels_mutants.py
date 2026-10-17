#!/usr/bin/env python
"""The check_levels mutants, committed (the L1c fix round's m6): every rule L1c and its fix round
added to tools/check_levels.py, and every rule of L2 Wave 1 (L2-6, L2-11, L2-13, L2-14, L2-18,
L2-19), shown red on a mutated copy of the shipped data, and green again on the data as it ships.

Each case loads the files afresh, changes a copy in memory (a layout block, a level file's units,
a Combat.json number) or turns one of check_levels' switches (SIGHT_ZONES, EXEMPT_CAMERAS,
FLOOR_WALLS, WALLED_CEILING, LIFT_MODEL, LIFT_KNOWN_LIMIT_W2, TRIGGER_MODEL), runs every gate
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
REWARDS = "forestRoad: a secret pays only behind a sold key"
ABILITIES = "Expeditions.json abilities.list: every entry"
PRICE = "Expeditions.json: Double Jump costs"
SECRET_NUMBERS = "Combat.json levels (L2-11)"
LEVERS = "Combat.json debug (L2-19)"
LOOKS = "map: the looks are greys, except"


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


def levels(data):
    return data["combat"]["levels"]


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
    ("C1: levels.cameraClear 2 (over the shake, under a body)", lambda d: levels(d).__setitem__("cameraClear", 2),
     {}, SIGHT, True),
    ("C1: levels.cameraClear 0.2 is under the shake", lambda d: levels(d).__setitem__("cameraClear", 0.2), {},
     CLEAR, True),
    ("C1: levels.cameraClear missing", lambda d: levels(d).pop("cameraClear"), {}, READS, True),
    ("C1 control: cameraClear 0.2 with cameras exempt in the doorway (2a58134's gate)",
     lambda d: levels(d).__setitem__("cameraClear", 0.2), {"EXEMPT_CAMERAS": True}, SIGHT, False),
    # m1: the exact extremes and the drawn body.
    ("m1: ambushE's inner fodder 2.4 off the north wall", lambda d: shift_east(d, 2.4), {}, SIGHT, True),
    ("m1 control: the same on the 2-stud grid, radius only (the build's gate)",
     lambda d: (shift_east(d, 2.4), d["ctx"].__setitem__("renderer", {"TORSO_WIDTH": 2, "TORSO_DEPTH": 0})),
     {"SIGHT_ZONES": False}, SIGHT, False),
    ("m1: CrowdRenderer's torso keys missing", lambda d: d["ctx"].__setitem__("renderer", {}), {}, READS, True),
    # The margin ruling: every margin at least the camp's sightMargin.
    ("margin: ambushE's innermost fodder back on 2a58134's post (345.5, -22.5)",
     lambda d: spot(d, "ambushE")["points"][0].update({"x": 345.5, "z": -22.5}), {}, MARGIN, True),
    ("margin: Hard's extra unit a brute again (L1c's mix: a fourth brute fits no hidden post)",
     lambda d: [unit.__setitem__("kind", "brute") for spot_id in ("ambushW", "ambushE")
                for unit in residents(d, spot_id)["units"] if unit.get("minDifficulty") == "hard"], {}, MARGIN, True),
    ("margin: sightMargin 2", lambda d: camp(d).__setitem__("sightMargin", 2), {}, MARGIN, True),
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
    ("L2-18c: today's Leap Smash, the known limit off", None, {"LIFT_MODEL": "today", "LIFT_KNOWN_LIMIT_W2": False},
     REACH_C, True),
    ("L2-18c: a Greataxe in the loadout (a lift enters a level)", lift_fielded, {"LIFT_MODEL": "today"}, REACH_C, True),
    ("L2-18c control: the floor model, the known limit off", None, {"LIFT_MODEL": "floor", "LIFT_KNOWN_LIMIT_W2": False},
     REACH_C, False),
    ("L2-18c: Leap Smash height 24 under the floor model", lambda d: lift_height(d, 24),
     {"LIFT_MODEL": "floor", "LIFT_KNOWN_LIMIT_W2": False}, REACH_C, True),
    ("L2-18c control: Leap Smash height 18 under the floor model", lambda d: lift_height(d, 18),
     {"LIFT_MODEL": "floor", "LIFT_KNOWN_LIMIT_W2": False}, REACH_C, False),
    # At 20 a target on camp A's fence (top 12) lifts the arc to 12 + 20 = 32, over the 31 a step up
    # needs: the floor model's margin is the fence, not the jump.
    ("L2-18c: Leap Smash height 20 under the floor model (a target on A's fence)", lambda d: lift_height(d, 20),
     {"LIFT_MODEL": "floor", "LIFT_KNOWN_LIMIT_W2": False}, REACH_C, True),
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
    ("s1: the centre rule back (W1 as shipped: from the chest's centre, secretReach 5)",
     lambda d: levels(d).__setitem__("secretReach", 5), {"TRIGGER_MODEL": "centre"}, TRIGGER_CACHE, True),
    ("s1: the centre rule at today's secretReach 2.5", None, {"TRIGGER_MODEL": "centre"}, TRIGGER_CACHE, True),
    ("s1: secretReach 0.9 (under a body's radius: nobody pressed against the cache opens it)",
     lambda d: levels(d).__setitem__("secretReach", 0.9), {}, TRIGGER_CACHE, True),
    ("s1 control: the footprint rule, the cache's trigger from beside it", None, {}, TRIGGER_CACHE, False),
    ("s1 control: the centre rule keeps the lookout (its chest's top is within 2.5 of the centre)", None,
     {"TRIGGER_MODEL": "centre"}, TRIGGER_LOOKOUT, False),
    ("s1: the cache's chest raised 5 off the road (a root beside it is 2 under its foot)",
     lambda d: secret(d, "cache").__setitem__("y", 18), {}, TRIGGER_CACHE, True),
    # L2-18 (e) and L2-13: rewards follow keys.
    ("L2-18e: the cache pays 1 Valor", lambda d: secret_entry(d, "cache").__setitem__("valor", 1), {}, REWARDS, True),
    ("L2-18e: the shrine names a family", lambda d: secret_entry(d, "shrine").__setitem__("family", "frostHammer"), {},
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
            setattr(cl, key, value)
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
        failed, passed = run(base, change, switches)
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
