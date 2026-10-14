#!/usr/bin/env python
"""Cross-check the rules of a run through a level against their Python mirrors, on the files that ship.

`src/shared/Combat.luau` and `src/combat/server/Services/StageFlow.luau` are pure, so the official
`luau` interpreter can run the very files the game runs. `tools/sim_combat.py` and
`tools/sim_range.py` mirror them by hand, and every balance band is measured on those mirrors: a
mirror that has drifted measures a game nobody plays. This tool gives both sides the same inputs
(every level file Catalog reads, its layout, Combat.json, Expeditions.json, ProvingGrounds.json)
and compares what they answer, value by value:

  * `StageFlow.Resolve` against `sim_range.resolve_level`: every level file as a level;
  * `StageFlow.Validate` against `sim_range.level_problems`: the shipped levels are playable on
    both sides, and (the fix round's ruling 6) a level with a maxAlive of 0 or of 2.5, a burst of
    0, a camp with a targetWaveSeconds of 0 or none, a breatherSeconds under 0 or no wave, and a
    Combat.json that lacks any one of the `levels` numbers a run reads, is refused on both;
  * `StageFlow.Validate`'s L1b lines: the residents, the spots, which camps lock, the population
    gate and the three new `levels` numbers, each broken once in a copy of the shipped level, its
    layout or Combat.json, refused alike;
  * `StageFlow.Plan` against `sim_range.plan_level`: every level at every difficulty, and at one
    that does not exist: each stage's numbers; every camp of the layout as a zone (its floor
    index, `locks`, name, checkpoint, residents, floor, `inner` and trigger rectangles, entry,
    exit and spawn points); every resident group; the population (L1b-11);
  * `StageFlow.BurstPoint` and `BossPoint` against `sim_range.burst_point` and the boss's place;
  * `Combat.CampWave` against `sim_combat.camp_wave`: every wave of every camp of every level, at
    every difficulty, for parties of 1 to coop.maxParty;
  * `Combat.CampReward` against `sim_combat.camp_reward`: every priced kind (and one that is not)
    under each of those specs, and a grid of prices under reward multipliers that leave halves
    (the shipped prices times 1, 2 and 4 never round);
  * `Combat.BurstSeconds`, `Tempo`, `ShouldMerge` and `BreatherSeconds` against their mirrors, on
    grids built from those specs (the bursts each wave really has, its expected kills a second)
    and on the thresholds themselves;
  * `StageFlow.Advance` against `sim_range.LevelRun.advance`: for every level and difficulty,
    scripted runs fed tick for tick to both. On the road each open camp's checkpoint is walked
    up to (past its reach, over the band, by a downed root, then on its edge) and its residents
    are killed off (L1b-17), with the boss room's floor empty all along (it never clears as an
    open camp). Each camp that locks is approached from outside its fence (outside the fenced
    rectangle, above and under the trigger's height, on the fence line), waits its countdown,
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
    refusals, and scripted runs whose `tentLeft` holds a `campClear`. The Luau mutants that prove
    each comparison are in docs/BALANCE.md "L1b Wave 2".

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
MODULES = ("Economy", "Armory", "HitShapes", "SwingGate", "Combat", "LevelGeometry", "CampBrain",
           "StageFlow")  # in load order
# The functions each comparison needs; one that is missing fails the run by name.
NEEDED = {"Combat": ("CampWave", "CampReward", "KillReward", "SplitCarry", "BurstSeconds", "Tempo", "ShouldMerge",
                     "BreatherSeconds", "ClearBonus", "DeadFraction", "WaveStock"),
          "StageFlow": ("Resolve", "Validate", "Plan", "Begin", "Advance", "Skip", "Force", "BurstPoint", "BossPoint",
                        "Directs", "StillClosing", "EarnsStar", "FieldClear", "SafePoint", "StandsUp", "BossReserve"),
          "CampBrain": ("Problems", "NewGroup", "Posts", "Sees", "InPlay", "AtPost", "Step", "Release", "Evades",
                        "Struck", "Goal", "Shows", "Engaged", "Dormant", "Gap", "JoinIn", "Rouse", "NewTent",
                        "TentActive", "TentDue", "TentSent"),
          "HitShapes": ("RayUpright", "CrowdRay", "FlatToRect", "Ray"),
          "SwingGate": ("New", "IsAir", "Allows", "Took", "Landed")}
# L1b Wave 2's grids.
RAY_ORIGINS = ((0.0, 5.0, 30.0), (3.0, 1.0, -25.0), (0.0, 22.0, 0.5), (-18.0, 9.0, 4.0))
RAY_WIDTHS = ((0.0, 0.0), (0.6, 0.6), (0.2, 1.5))  # (width, pad)
RAY_SEED = 2214
RAY_RANDOM = 160
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
STATE_FIELDS = ("stage", "step", "wave", "firstWave", "gateAt", "breatherUntil", "cleared", "lastCleared", "settled",
                "reached", "done", "closedAt", "fought", "ended")
ACTION_FIELDS = ("kind", "stage", "wave", "at", "merged", "count", "zone", "reason", "skipped")
VARIANTS = ("clear", "down", "roadDown", "cap", "standing", "reset", "skipStage", "skipBoss", "force")
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
)


def first_camp(file):
    return next(stage for stage in file["stages"] if stage["kind"] == "camp")


def layout_camp(layout, cid):
    return next(camp for camp in layout["camps"] if camp["id"] == cid)


def level_camp(file, cid):
    return next(camp for camp in file["camps"] if camp["id"] == cid)


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
    ("the boss room's residents at its maxAlive", lambda f, l, r: next(
        g for g in level_camp(f, "C")["residents"] if g["spot"] == "chiefFire")["units"].append({"kind": "fodder", "count": 40})),
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
)


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
                "aliveByFloor": list(g["aliveByFloor"]), "fallen": g["fallen"],
                "tentLeft": list(g.get("tentLeft") or [])}

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
                 "fought": list(self.fought), "ended": self.end_reason}
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
    tent_left = [0 for _zone in zones]  # L1b-W2-8: a tent's stock not sent yet, per zone
    walked = set()

    def tick(root=None, at=None, fieldClear=True, **given):
        clock[0] = at if at is not None else clock[0] + 0.5
        if root is not None:
            spot[0] = root
        entry = {"op": "tick", "now": clock[0], "roots": [list(spot[0])], "fighters": [1], "spawningDone": True,
                 "alive": 0 if fieldClear else 1, "awake": 0, "aliveByFloor": list(by_floor), "mergeOk": False,
                 "breatherSeconds": BREATHER_INPUT, "fallen": None, "runCap": False, "tentLeft": list(tent_left)}
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
            by_floor[index - 1] = 1
            tick(awake=1)  # one resident left
            if zone["tentStock"] > 0:
                # L1b-W2-8: the last resident falls with the tent's stock still to come out: no
                # clear while any is left, a down on the quiet floor stands up, then the last.
                tent_left[index - 1] = zone["tentStock"]
                by_floor[index - 1] = 0
                tick()  # every body dead, the whole stock left: not cleared
                tick(standing=[False], fallen="down")  # a downed root on a quiet road
                tent_left[index - 1] = 1
                by_floor[index - 1] = 1
                tick(awake=1)  # a tent body out and awake
                by_floor[index - 1] = 0
                tick()  # it falls, one left: still not cleared
                tent_left[index - 1] = 0
            by_floor[index - 1] = 0
            tick()  # the last falls: the camp is cleared
            tick()  # once
        return False

    def lever(where):
        """Presses this run's lever the first time it stands `where`; True when it did."""
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

            floor, fence = zone["floorY"], rules["fenceThickness"]
            root = floor + sr.ROOT_HEIGHT
            x, z = out(fence + 0.5)
            tick((x, root, z))  # outside the fenced rectangle
            x, z = out(fence / 2)
            tick((x, floor + rules["triggerHeight"] + 0.5, z))  # on the fence line, above the trigger
            tick((x, floor - rules["triggerBelow"] - 0.5, z))  # and under it
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
            "floorY": floor, "rect": list(zone["rect"]), "inner": list(zone["inner"]), "trigger": list(zone["trigger"]),
            "entry": [zone["entry"][0], floor, zone["entry"][1]], "exit": [zone["exit"][0], floor, zone["exit"][1]],
            "spawns": [[x, floor, z] for x, z in zone["spawns"]]}


def def_row(defn):
    """A CampGroupDef as plain values (both sides read and print it so)."""
    return plain({"id": defn["id"], "camp": defn["camp"], "floor": defn["floor"], "floorY": defn["floorY"],
                  "rect": dict(defn["rect"]), "posture": defn["posture"], "points": [list(p) for p in defn["points"]],
                  "yaw": defn["yaw"], "radius": defn["radius"], "held": defn["held"],
                  "units": [{"kind": u["kind"], "count": u["count"]} for u in defn["units"]]})


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
    return {"zone": tent["zone"], "def": def_row(tent["def"]), "kinds": list(tent["kinds"]),
            "posts": [post_row(p) for p in tent["posts"]], "doors": [list(d) for d in tent["doors"]],
            "every": tent["every"]}


def wire(value):
    """A Python answer as the Luau's JSON prints it: infinities as the strings it writes."""
    if isinstance(value, float) and math.isinf(value):
        return "inf" if value > 0 else "-inf"
    if isinstance(value, (list, tuple)):
        return [wire(v) for v in value]
    if isinstance(value, dict):
        return {k: wire(v) for k, v in value.items()}
    return value


def ray_cases(data, expected, kinds):
    """HitShapes.CrowdRay, RayUpright and FlatToRect (L1b-W2-15, -16, -24) on grids: every kind,
    origins round it, aims at its shins, its body, its head's base, centre and top and past them,
    beside the capsule, at several widths and pads; RayUpright with low == high against Ray on
    seeded rays; FlatToRect on a rectangle's inside, edges, corners and beyond."""
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
                                      "playerInPlay": in_play})
            expected[case] = ("CampBrain.Rouse", f"{state}{' held' if held else ''}{' in play' if in_play else ''}",
                              {"ret": ret, "group": group_row(group)})
    # The tent rule on timelines: wake at 0 (0, 6, 12), a pause from 13 to 40 (the next at 40),
    # the residents dead with the camp at rest (it keeps sending), the stock spent (never).
    every = 6.0
    ops = [("active", True, 5), ("due", True, 0.0), ("sent", 0.0), ("due", True, 3.0), ("due", True, 6.0 - 1e-7),
           ("sent", 6.0), ("due", True, 12.0), ("sent", 12.0), ("active", False, 5), ("due", False, 18.0),
           ("due", False, 39.0), ("active", True, 5), ("due", True, 40.0), ("sent", 40.0), ("active", False, 0),
           ("active", False, -1), ("due", True, 46.0), ("sent", 46.0), ("sent", 52.0), ("sent", 58.0), ("due", True, 64.0),
           ("sent", 64.0), ("sent", 70.0), ("due", True, 76.0), ("due", True, 1e6)]
    rows = []
    tent = sr.cb_new_tent(8)
    for op in ops:
        if op[0] == "active":
            ret = sr.cb_tent_active(op[1], op[2])
        elif op[0] == "due":
            ret = sr.cb_tent_due(tent, op[1], op[2])
        else:
            sr.cb_tent_sent(tent, op[1], every)
            ret = "nil"
        rows.append({"ret": ret, "left": tent["left"], "nextAt": wire(tent["nextAt"])})
    case = "camp.tent.timeline"
    data["campCases"].append({"id": case, "op": "tent", "stock": 8, "every": every, "ops": [list(op) for op in ops]})
    expected[case] = ("CampBrain: the tent rule on a timeline", f"a stock of 8 every {every:g} s, {len(ops)} calls", rows)


def combat_cases(data, expected, files, raw_layouts, rules, ranks, crowd_kinds, below):
    """Combat.ClearBonus, DeadFraction and WaveStock (L1b-W2-21, -26): every camp's stock of every
    level at every difficulty under several shares (the boss room's with what its waves queue), a
    grid of prices that round at halves and an unpriced kind; DeadFraction on a grid; WaveStock on
    every wave with and without an elite."""
    rows, mine = [], []
    for file in files:
        level = sr.resolve_level(file, None, 0, "normal") if not file.get("mission") else None
        if level is None or not level.get("camps"):
            continue
        layout = sr.load_level_layout(file["layout"], below)
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
            "hit": group["hit"], "inPlay": sorted(k for k, v in group["inPlay"].items() if v)}


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
    for state, held in states:
        for k, post in enumerate(posts[:3], 1):
            legs = range(0, len(points) + 2) if defn["posture"] == "patrol" else [post["leg"]]
            places = [post["at"], (post["at"][0] + 30.0, floor, post["at"][2])]
            if defn["posture"] == "patrol":
                places += [(p[0] + tol / 2, floor, p[2]) for p in points]
            for leg in legs:
                for at in places:
                    group = sr.cb_new_group(defn, 0.0)
                    group["state"], group["held"] = state, held
                    resident = {"group": 1, "post": post, "leg": leg}
                    goal, pace = sr.cb_goal(group, resident, at, rules)
                    case = f"camp.goal.{len(data['campCases'])}"
                    data["campCases"].append({"id": case, "op": "goal", "def": row, "state": state, "held": held,
                                              "post": post_row(post), "leg": leg, "at": list(at)})
                    expected[case] = ("CampBrain.Goal", f"{label} {state}{' held' if held else ''}, post {k}, leg {leg}, "
                                      f"at ({at[0]:g}, {at[2]:g})",
                                      plain([list(goal) if goal is not None else "nil", pace, resident["leg"]]))
        for in_play in ([], [1]):
            for by in (0, 1, 2):
                group = sr.cb_new_group(defn, 0.0)
                group["state"], group["held"] = state, held
                for user in in_play:
                    group["inPlay"][user] = True
                landed = sr.cb_struck(group, by)
                case = f"camp.struck.{len(data['campCases'])}"
                data["campCases"].append({"id": case, "op": "struck", "def": row, "state": state, "held": held,
                                          "inPlay": in_play, "by": by})
                expected[case] = ("CampBrain.Struck", f"{label} {state}{' held' if held else ''}, in play {in_play}, by {by}",
                                  [landed, group["hit"], sr.cb_evades(group)])
        for moving in (False, True):
            group = sr.cb_new_group(defn, 0.0)
            group["state"], group["held"] = state, held
            case = f"camp.shows.{len(data['campCases'])}"
            data["campCases"].append({"id": case, "op": "shows", "def": row, "state": state, "held": held,
                                      "moving": moving})
            shown = sr.cb_shows(group, moving)
            expected[case] = ("CampBrain.Shows", f"{label} {state}{' held' if held else ''}, moving {moving}",
                              shown if shown is not None else "nil")


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
                    "targets": [{"userId": t["userId"], "root": tuple(t["root"])} for t in op["targets"]],
                    "shooters": [{"at": tuple(s["at"]), "reach": s["reach"]} for s in op["shooters"]],
                    "striking": op["striking"]}
            ret = sr.cb_step(group, step, rules)
        elif op["kind"] == "release":
            sr.cb_release(group, op["now"])
            ret = None
        else:
            ret = sr.cb_struck(group, op["by"])
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
    far = {"userId": 1, "root": [5.0, 11.0, -5.0 - 4.0 - sight - 1.0]}
    near = {"userId": 1, "root": [5.0, 11.0, -5.0 - 4.0 - sight + 1.0]}
    out = {"userId": 1, "root": [0.0, 11.0, -30.0 - rules["chaseMargin"] - 5.0]}

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
    timeline(data, expected, "fire: sight, rise, fight, the leash held while striking, home, rest, a hit wakes", fire,
             rules, ops)
    held = grids[4]
    hposts = sr.cb_posts(held, 1)
    hmembers = [{"at": list(p["at"]), "post": post_row(p)} for p in hposts]
    hnear = {"userId": 1, "root": [0.0, 11.0, 24.0]}
    ops = [step(0.0, hmembers, [hnear]), {"kind": "struck", "by": 1}, step(0.5, hmembers, [hnear]),
           {"kind": "release", "now": 0.75}, step(0.75, hmembers, [hnear]), step(1.0, hmembers, [hnear]),
           {"kind": "release", "now": 1.25}, step(1.25, hmembers, [hnear])]
    timeline(data, expected, "guard held: ignores sight and hits, released, rise 0", held, rules, ops)
    patrol = grids[0]
    pposts = sr.cb_posts(patrol, 3)
    pmembers = [{"at": list(p["at"]), "post": post_row(p)} for p in pposts]
    sights = [{"userId": 2, "root": [0.0, 11.0, 0.0]}, {"userId": 5, "root": [0.0, 11.0, 90.0]}]
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
              ("a dormantRadius under the fire's sight", lambda r: r.__setitem__("dormantRadius", r["fire"]["sight"] - 1))]
    for label, change in broken:
        changed = copy.deepcopy(rules)
        change(changed)
        case = f"camp.problems.{len(data['campCases'])}"
        data["campCases"].append({"id": case, "op": "problems", "rules": changed})
        expected[case] = ("CampBrain.Problems: how many lines", label, len(sr.cb_problems(changed)))


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
    files = sr.load_level_files()
    missions = [sr.load_config(path) for path in sorted(sr.MISSIONS_DIR.glob("*.json")) if sr.is_catalog_name(path.stem)]
    by_mission = {mission["id"]: mission for mission in missions}
    raw_layouts = {path.stem: sr.load_config(path) for path in sorted(sr.LEVEL_LAYOUT_DIR.glob("*.json"))}
    first = expeditions["difficulties"][0]
    below = combat["player"]["rescue"]["below"]
    plan_difficulties = list(expeditions["difficulties"]) + ["nope"]
    parties = range(1, combat["coop"]["maxParty"] + 1)

    def resolved(file):
        return sr.resolve_level(file, by_mission.get(file.get("mission")), director["runCapSeconds"], first)

    # The cases, and the Python's own answers to them.
    report = Report(args.show)
    expected = {}  # id -> (kind, label, the Python's answer)
    data = {"combat": combat, "expeditions": expeditions, "proving": cfg, "levels": files, "missions": missions,
            "layouts": raw_layouts, "ranks": ranks, "planDifficulties": plan_difficulties, "pointCases": [],
            "waveCases": [], "refusalCases": [], "traces": [], "busyCases": list(BUSY_CASES),
            "campRules": combat["camps"], "campCases": [], "splitCases": [], "rayCases": [], "swingCases": [],
            "combatCases": [], "reserveCases": []}
    shipped_plans = []  # (label, plan) of every level with residents at every difficulty: Wave 2's camp cases
    bursts, tempos = {}, {}
    scripted = {}  # trace id -> (label, the Python's ticks)
    stars = {}  # trace id -> the Python's earns_star for STAR_USERS, at the run's end
    for number, file in enumerate(files, 1):
        name = file["id"]
        level = resolved(file)
        layout = sr.load_level_layout(file["layout"], below)
        expected[f"level.{number}.resolve"] = ("StageFlow.Resolve", name, plain(level))
        if level is None:
            continue
        expected[f"level.{number}.validate"] = ("StageFlow.Validate: the shipped level is playable", name,
                                                sr.level_problems(level, layout, rules, crowd_kinds, ranks, crowd_max))
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
                        expected[case + ".rewards"] = ("Combat.CampReward", label, {
                            kind: list(sc.camp_reward(level["crowd"]["rewards"], kind, spec)) for kind in kinds})
                        target = stage["targetWaveSeconds"] if stage.get("targetWaveSeconds") is not None else 0
                        count = len(sc.crowd_bursts(spec, level["crowd"]["burst"]))
                        for tempo in TEMPO_GRID:
                            bursts[(target, count, tempo)] = None
                        rate = spec["total"] / target if target > 0 else 0
                        for kills in KILL_GRID:
                            tempos[(kills, director["windowSeconds"], rate)] = None
        if not file.get("mission"):
            for label, change in (("as shipped", lambda _file: None),) + REFUSALS:
                changed = copy.deepcopy(file)
                change(changed)
                case = f"refusal.{number}.{len(data['refusalCases'])}"
                data["refusalCases"].append({"id": case, "file": changed, "rules": rules})
                level_changed = resolved(changed)
                refused = level_changed is None or bool(sr.level_problems(level_changed, layout, rules, crowd_kinds, ranks,
                                                                          crowd_max))
                expected[case] = ("ruling 6: refused alike", f"{name}, {label}", refused)
            # And Combat.json without one of the numbers a run reads: unavailable on both sides.
            for key in sr.LEVEL_RULES_NEEDED:
                short_rules = {name_: value for name_, value in rules.items() if name_ != key}
                case = f"refusal.{number}.{len(data['refusalCases'])}"
                data["refusalCases"].append({"id": case, "file": file, "rules": short_rules})
                expected[case] = ("ruling 6: refused alike", f"{name}, Combat.json without levels.{key}",
                                  bool(sr.level_problems(level, layout, short_rules, crowd_kinds, ranks, crowd_max)))
            # L1b: each of Validate's new lines, broken once.
            if file.get("camps"):
                for label, change in L1B_REFUSALS:
                    changed, raw, short_rules = copy.deepcopy(file), copy.deepcopy(raw_layouts[file["layout"]]), dict(rules)
                    change(changed, raw, short_rules)
                    case = f"refusal.{number}.{len(data['refusalCases'])}"
                    data["refusalCases"].append({"id": case, "file": changed, "rules": short_rules, "layout": raw})
                    level_changed = resolved(changed)
                    refused = level_changed is None or bool(sr.level_problems(level_changed, raw, short_rules, crowd_kinds,
                                                                              ranks, crowd_max))
                    expected[case] = ("L1b: Validate's new lines refuse alike", f"{name}, {label}", refused)
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
    ray_cases(data, expected, crowd_kinds)
    swing_cases(data, expected)
    combat_cases(data, expected, files, raw_layouts, rules, ranks, crowd_kinds, below)
    data["burstCases"] = [list(key) for key in bursts]
    data["tempoCases"] = [list(key) for key in tempos]
    data["mergeCases"] = [list(key) for key in merges]
    data["breatherCases"] = breathers
    data["rewardCases"] = [list(case) for case in REWARD_GRID]

    # The bundle: the data, the real sources, the driver. In a folder of its own.
    parts = [f"local DATA: any = {to_luau(data)}\n", "local SOURCES = {}\n"]
    arenas = sorted({layout["arena"] for layout in raw_layouts.values() if layout.get("arena")})
    for name in MODULES:
        path = Path(swapped[name]) if name in swapped else ROOT / sources[name]
        parts.append(wrap(name, path.read_text(encoding="utf-8")))
    for arena in arenas:
        path = ROOT / "src" / "shared" / "Layouts" / "Arenas" / f"{arena}.luau"
        if path.exists():
            parts.append(wrap(f"Arena_{arena}", path.read_text(encoding="utf-8")))
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
        if kind.startswith("ruling 6") or kind.startswith("L1b: Validate"):
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

    grid("Combat.CampReward", "grid.campReward", data["rewardCases"],
         lambda cash, materials, mult: list(sc.camp_reward({"probe": {"cash": cash, "materials": materials}}, "probe",
                                                            {"rewardMult": mult})))
    grid("Combat.KillReward", "grid.killReward", data["rewardCases"],
         lambda cash, materials, mult: list(sc.kill_reward({"probe": {"cash": cash, "materials": materials}}, "probe",
                                                            mult)) + list(sc.kill_reward({}, "probe", mult)))
    grid("Combat.BurstSeconds", "grid.burstSeconds", data["burstCases"], sc.burst_seconds)
    grid("Combat.Tempo", "grid.tempo", data["tempoCases"], lambda kills, window, rate: sc.tempo(kills, window, rate, director))
    grid("Combat.ShouldMerge", "grid.shouldMerge", data["mergeCases"], lambda tempo, dead: sc.should_merge(tempo, dead, director))
    grid("Combat.BreatherSeconds", "grid.breatherSeconds", [(tempo,) for tempo in breathers],
         lambda tempo: sc.breather_seconds(tempo, director))

    # The scripted runs: the first tick at which the two sides part, per run.
    extra_state = set()
    kinds = {"reset": "StageFlow.Advance: nobody on his feet as a countdown ends", "skipStage": "StageFlow.Skip",
             "skipBoss": "StageFlow.Skip", "force": "StageFlow.Force"}
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
