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
  * `StageFlow.Plan` against `sim_range.plan_level`: every level at every difficulty, and at one
    that does not exist: each stage's numbers and each camp's floor, `inner` and trigger
    rectangles, entry, exit and spawn points;
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
    scripted runs fed tick for tick to both. Each camp is approached from outside its fence
    (outside the fenced rectangle, above and under the trigger's height, on the fence line),
    waits its countdown, and plays its waves through: still spawning, the director asking to
    merge, bodies alive, a down on a field that is clear, the clear, the breather. One run of
    each is a clean clear, one ends with a down in a live camp, one at the run cap, and one has
    nobody on his feet when a countdown ends (the camp is armed again). After every tick the
    actions (kind, stage, wave, time, count, reason) and the state (stage, step, wave,
    firstWave, gateAt, breatherUntil, cleared, lastCleared, settled, closedAt, fought, ended) of
    both sides are compared;
  * `StageFlow.Skip` and `StageFlow.Force` against `LevelRun.skip` and `LevelRun.force` (the
    Studio levers; the simulator's own runs never use them): three more runs of each level and
    difficulty in which a stage skip, a boss skip or a forced wave comes at the first tick on
    the road, in a countdown, in a fight and in a breather, compared the same way;
  * on every tick of all those runs, `StageFlow.Directs` against `LevelRun.directs` (does the
    director keep its tempo in this step) and `StageFlow.StillClosing` against
    `LevelRun.still_closing` (is the close still judged again); and at each run's end
    `StageFlow.EarnsStar` against `LevelRun.earns_star`, for a fighter of the last clear, for
    one who was not, and for a stranger.

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
MODULES = ("Economy", "Armory", "Combat", "LevelGeometry", "StageFlow")  # in load order
# The functions each comparison needs; one that is missing fails the run by name.
NEEDED = {"Combat": ("CampWave", "CampReward", "BurstSeconds", "Tempo", "ShouldMerge", "BreatherSeconds"),
          "StageFlow": ("Resolve", "Validate", "Plan", "Begin", "Advance", "Skip", "Force", "BurstPoint", "BossPoint",
                        "Directs", "StillClosing", "EarnsStar")}
TOLERANCE = 1e-9  # relative; the two sides do the same arithmetic on the same doubles
TEMPO_GRID = (-1.0, 0.0, 0.5, 0.7, 1.0, 1.25, 1.6, 2.0)
KILL_GRID = (0, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89)
EDGE = 1e-7  # either side of a threshold
BURST_SIZES = (1, 2, 3, 9, 16)
# Prices and reward multipliers whose products end in halves and thirds: (cash, materials, mult).
REWARD_GRID = tuple((cash, materials, mult) for cash in (1, 3, 5, 7, 100) for materials in (0, 1, 3)
                    for mult in (0.5, 1.5, 2.5, 1 / 3, 4))
STATE_FIELDS = ("stage", "step", "wave", "firstWave", "gateAt", "breatherUntil", "cleared", "lastCleared", "settled",
                "closedAt", "fought", "ended")
ACTION_FIELDS = ("kind", "stage", "wave", "at", "merged", "count", "reason")
VARIANTS = ("clear", "down", "cap", "reset", "skipStage", "skipBoss", "force")
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
        self.given = {"fieldClear": True, "mergeOk": False, "breatherSeconds": 0.0}
        run = self

        class Director:  # what advance() asks of sim_combat
            @staticmethod
            def should_merge(_tempo, _dead, _director):
                return run.given["mergeOk"]

            @staticmethod
            def breather_seconds(_tempo, _director):
                return run.given["breatherSeconds"]

        self.sc = Director
        self.spawned = 1

    def field_clear(self):
        return self.given["fieldClear"]

    def alive(self):
        return 0 if self.given["fieldClear"] else 1

    def on_gate(self, index, t):
        pass

    def on_close(self, t):
        pass

    def on_wave(self, wave, merged, t):
        pass

    def on_clear(self, t):
        pass

    def on_bank(self, t):
        pass

    def on_open(self, t, index=None):
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
        if tick["op"] == "skip":
            self.skip(tick["which"], tick["now"], tick.get("fighters"))
        elif tick["op"] == "force":
            self.force(tick["wave"], tick["now"])
        else:
            self.advance(tick["now"])
        actions = [dict(fields, kind=kind) for kind, fields in self.actions[before:]]
        state = {"stage": self.stage, "step": self.flow, "wave": self.wave, "firstWave": self.first_wave,
                 "gateAt": self.gate_at, "breatherUntil": self.breather_until, "cleared": self.cleared,
                 "lastCleared": self.last_cleared, "settled": self.settled, "closedAt": self.closed_at,
                 "fought": list(self.fought), "ended": self.end_reason}
        return actions, state, self.directs(), self.still_closing(tick["now"])


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
    camps = [index for index, stage in enumerate(stages, 1) if stage["kind"] == "camp"]
    start = run.plan["start"]
    spot = [(start[0], start_y + sr.ROOT_HEIGHT, start[1])]
    reset = [variant == "reset"]
    pressed = set()

    def tick(root=None, at=None, **given):
        clock[0] = at if at is not None else clock[0] + 0.5
        if root is not None:
            spot[0] = root
        entry = {"op": "tick", "now": clock[0], "roots": [list(spot[0])], "fighters": [1], "fieldClear": True,
                 "spawningDone": True, "mergeOk": False, "breatherSeconds": BREATHER_INPUT, "fallen": None,
                 "runCap": False}
        entry.update(given)
        ticks.append((entry,) + run.play(entry))

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
            zone = run.armed_zone()
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
    return plain(row)


def tick_text(entry):
    if entry["op"] == "skip":
        return f"now {entry['now']:g}, Skip \"{entry['which']}\""
    if entry["op"] == "force":
        return f"now {entry['now']:g}, Force {entry['wave']:g}"
    odd = [f"{key} {entry[key]}" for key in ("fieldClear", "spawningDone", "mergeOk", "fallen", "runCap")
           if entry[key] not in ({"fieldClear": True, "spawningDone": True, "mergeOk": False, "fallen": None,
                                  "runCap": False}[key],)]
    root = entry["roots"][0]
    return f"now {entry['now']:g}, root ({root[0]:g}, {root[1]:g}, {root[2]:g})" + (", " + ", ".join(odd) if odd else "")


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
            "waveCases": [], "refusalCases": [], "traces": []}
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
                                                sr.level_problems(level, layout, rules))
        for difficulty in plan_difficulties:
            plan = sr.plan_level(level, layout, difficulty, rules)
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
                    "bankEachWave": stage["bankEachWave"], "targetWaveSeconds": stage["targetWaveSeconds"],
                    "maxAlive": stage["maxAlive"],
                    "zone": None if zone is None else {
                        "id": zone["id"], "floorY": floor, "rect": zone["rect"], "inner": zone["inner"],
                        "trigger": zone["trigger"], "entry": (zone["entry"][0], floor, zone["entry"][1]),
                        "exit": (zone["exit"][0], floor, zone["exit"][1]),
                        "spawns": [(x, floor, z) for x, z in zone["spawns"]]}})
            start = layout["start"]
            expected[key] = ("StageFlow.Plan", f"{name} {difficulty}", plain({"plan": {
                "levelId": plan["levelId"], "difficulty": plan["difficulty"], "start": (start["x"], start["y"], start["z"]),
                "killY": plan["killY"], "camps": plan["camps"], "stages": stages}}))
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
                refused = level_changed is None or bool(sr.level_problems(level_changed, layout, rules))
                expected[case] = ("ruling 6: refused alike", f"{name}, {label}", refused)
            # And Combat.json without one of the numbers a run reads: unavailable on both sides.
            for key in sr.LEVEL_RULES_NEEDED:
                short_rules = {name_: value for name_, value in rules.items() if name_ != key}
                case = f"refusal.{number}.{len(data['refusalCases'])}"
                data["refusalCases"].append({"id": case, "file": file, "rules": short_rules})
                expected[case] = ("ruling 6: refused alike", f"{name}, Combat.json without levels.{key}",
                                  bool(sr.level_problems(level, layout, short_rules)))
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
        if kind.startswith("ruling 6"):
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
        for index, (entry, actions, state, directs, closing) in enumerate(ticks):
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
        if parted is None:
            report.compare(kind, f"{label} ({len(ticks)} ticks, ended {ticks[-1][2]['ended']})", True, True)
            report.compare("StageFlow.EarnsStar: a fighter of the last clear, one who was not, a stranger",
                           f"{label} (ended {ticks[-1][2]['ended']}, fought {ticks[-1][2]['fought']})",
                           got.get("stars"), stars[trace])
        else:
            report.differ(kind, parted)

    failed = report.print()
    mirrored = {"Combat": NEEDED["Combat"], "StageFlow": NEEDED["StageFlow"]}
    loose = [name for name in exports.get("StageFlow") or [] if name not in mirrored["StageFlow"]]
    print(f"  note  StageFlow functions the simulators do not mirror (tools/crowd_harness tests them): "
          f"{', '.join(loose) or 'none'}")
    if extra_state:
        print(f"  note  State fields the simulator's run does not carry: {', '.join(sorted(extra_state))}")
    print()
    print(f"CHECK: {'PASS' if failed == 0 else f'FAIL ({failed})'}")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
