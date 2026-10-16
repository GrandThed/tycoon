#!/usr/bin/env python
"""The check_levels mutants, committed (the L1c fix round's m6): every rule L1c and its fix round
added to tools/check_levels.py, shown red on a mutated copy of the shipped data, and green again
on the data as it ships.

Each case loads the files afresh, changes a copy in memory (a layout block, a level file's units,
a Combat.json number) or turns one of check_levels' switches (SIGHT_ZONES, EXEMPT_CAMERAS,
FLOOR_WALLS), runs every gate (check_levels.run_gates) and expects the named rule red, or green
for a control. A rule is named by text its line always carries. Nothing on disk is written,
except for the stage-mirror case (m2), which runs tools/check_stage_mirror.py with StageFlow.luau
and sim_range.py both missing the "residents under the boss room's maxAlive" rule, from copies in
a temporary folder, and expects it red.

Usage:
  py tools/check_levels_mutants.py                       # every case; exit 1 when one is not as expected
  py tools/check_levels_mutants.py --only sight          # the cases whose label holds this text
  py tools/check_levels_mutants.py --luau <luau.exe>     # the interpreter for the stage-mirror case
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
CLEAR = "camp C (walled): levels.cameraClear"
READS = "camp C (walled): the sight gate reads"
LOCKED = re.compile(r"camp C: \d+ residents at the highest difficulty")
COUNTDOWN = "(The Chief's Clearing): its own gateSeconds"
PROBLEMS = "forestRoad: maxAlive is an integer of at least 1 wherever"


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
    ("m1: ambushE's inner fodder 0.8 off the north wall", lambda d: shift_east(d, 0.8), {}, SIGHT, True),
    ("m1 control: the same on the 2-stud grid, radius only (the build's gate)",
     lambda d: (shift_east(d, 0.8), d["ctx"].__setitem__("renderer", {"TORSO_WIDTH": 2, "TORSO_DEPTH": 0})),
     {"SIGHT_ZONES": False}, SIGHT, False),
    ("m1: CrowdRenderer's torso keys missing", lambda d: d["ctx"].__setitem__("renderer", {}), {}, READS, True),
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


def stage_mirror_case(luau):
    """m2: the "residents under the boss room's maxAlive" rule taken out of both StageFlow.luau and
    sim_range.py (copies in a temporary folder); check_stage_mirror's case for it must fail.
    (ok, what was seen)."""
    flow = REPO / "src" / "combat" / "server" / "Services" / "StageFlow.luau"
    mirror = TOOLS / "sim_range.py"
    luau_rule, py_rule = "if held >= cap then", 'if residents.get(camp["id"], 0) >= cap:'
    flow_text, py_text = flow.read_text(encoding="utf-8"), mirror.read_text(encoding="utf-8")
    if flow_text.count(luau_rule) != 1 or py_text.count(py_rule) != 1:
        return False, "the rule's line is not found exactly once on both sides (the mutant is stale)"
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "StageFlow.luau").write_text(flow_text.replace(luau_rule, "if held >= cap + 999999 then"),
                                             encoding="utf-8", newline="\n")
        (root / "sim_range.py").write_text(py_text.replace(py_rule, 'if residents.get(camp["id"], 0) >= cap + 999999:'),
                                           encoding="utf-8", newline="\n")
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
    named = [line.strip() for line in out.splitlines() if "the boss room's residents at its maxAlive" in line]
    return (done.returncode != 0 and verdict.startswith("CHECK: FAIL") and bool(named),
            verdict + (f"; {named[0]}" if named else "; the case's line is missing"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", default=None, help="run only the cases whose label holds this text")
    parser.add_argument("--luau", default=str(TOOLS / "bin" / "luau.exe"), help="the Luau interpreter (m2's case)")
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
    if not args.only or args.only in "m2: the boss room's maxAlive rule out of both mirrors":
        luau = Path(args.luau)
        if luau.exists():
            good, seen = stage_mirror_case(luau)
            print(f"  {'ok  ' if good else 'NOT '}  m2: the boss room's maxAlive rule out of both mirrors: "
                  f"check_stage_mirror red -> {seen[:220]}")
            if not good:
                wrong.append("m2")
        else:
            print(f"  skip  m2: no Luau interpreter at {luau} (give --luau)")
    print()
    print(f"MUTANTS: {'PASS' if not wrong else 'FAIL (' + ', '.join(wrong) + ')'}")
    sys.exit(0 if not wrong else 1)


if __name__ == "__main__":
    main()
