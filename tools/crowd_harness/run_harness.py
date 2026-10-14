"""Regression harness for the crowd combat server (P4): bundles the real CrowdCodec, HitShapes,
Armory, Tuning, CrowdBrain, ThreatField, StrikeTally, CrowdService and VitalsService sources
with stubbed Roblox globals and runs the tests_*.luau cases under the plain luau interpreter.
P5 adds tests_p5.luau: the mission scales, kill info, KillAll, VitalsService.SetMission and
the pure PositionRing (the server's own reading of a player's speed).
L1 adds the pure rules of a run through a level: StageFlow (tests_l1.luau, with Combat and
Economy, which it is checked against) and LevelGeometry (tests_l1_world.luau). The Village
mission and Combat.json are injected as FIXTURES, the way Armory.json is.
"The real files" (tests_l1.luau) runs those same rules on the data that ships: every level
file, layout, mission and the map are injected as they stand, the arena layouts a level names
are bundled as modules, and tools/check_levels.py is asked for its Part counts and its own
reading of each arena, so the Luau rules and the Python gate are held to one answer.
It proves the logic, not Roblox behaviour. RangeService is not loadable here.
Usage: py tools/crowd_harness/run_harness.py [repo root] [luau.exe]
(defaults: this repo, tools/bin/luau.exe, which tools/check_mirror.py fetches)."""
import json
import re
import subprocess
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = Path(sys.argv[1]) if len(sys.argv) > 1 else here.parents[1]
luau = sys.argv[2] if len(sys.argv) > 2 else str(here.parents[1] / "tools" / "bin" / "luau.exe")

SOURCES = {
    "CrowdCodec": "src/shared/CrowdCodec.luau",
    "HitShapes": "src/shared/HitShapes.luau",
    "Economy": "src/shared/Economy.luau",
    "Armory": "src/shared/Armory.luau",
    "Combat": "src/shared/Combat.luau",
    "Tuning": "src/shared/Tuning.luau",
    "CrowdBrain": "src/combat/server/Services/CrowdBrain.luau",
    "ThreatField": "src/combat/server/Services/ThreatField.luau",
    "StrikeTally": "src/combat/server/Services/StrikeTally.luau",
    "PositionRing": "src/combat/server/Services/PositionRing.luau",
    "CrowdService": "src/combat/server/Services/CrowdService.luau",
    "VitalsService": "src/combat/server/Services/VitalsService.luau",
    "LevelGeometry": "src/combat/server/Services/LevelGeometry.luau",
    "StageFlow": "src/combat/server/Services/StageFlow.luau",
}


def to_luau(value) -> str:
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{json.dumps(key)}] = {to_luau(item)}" for key, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(to_luau(item) for item in value) + "}"
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    return json.dumps(value)


def read(path) -> object:
    return json.loads((repo / path).read_text(encoding="utf-8"))


NUMBERED = r"\d+_"


def read_folder(folder: str, numbered: bool = False) -> list:
    """Every JSON file of a folder as (stem, content). `numbered`: only the files Catalog reads
    there, those named <n>_<Name>, in its order: by that number, then by name."""
    def order(path: Path):
        prefix = re.match(r"\d+", path.stem)
        return (int(prefix.group()) if prefix else 0, path.stem)

    paths = sorted((repo / folder).glob("*.json"), key=order)
    if numbered:
        paths = [path for path in paths if re.match(NUMBERED, path.stem)]
    return [(path.stem, read(path)) for path in paths]


def gate_reading() -> dict:
    """What tools/check_levels.py makes of the layouts: its Part count for each (its `N Parts`
    lines) and, for a layout that names an arena, the level layout its own adapter reads out of
    that arena. Always this checkout's files (the tool takes no root; a mutant root holds copies
    of the same data). Empty when the tool cannot be imported: the cases that need it then fail."""
    try:
        sys.path.insert(0, str(here.parent))
        import check_levels

        layouts = check_levels.load_all()[2]
        return {
            "parts": {name: check_levels.part_count(layout) for name, layout in layouts.items()},
            "arenas": {name: layout for name, layout in layouts.items() if layout.get("arena")},
        }
    except (Exception, SystemExit) as problem:  # the harness still runs, and says so
        print(f"run_harness: tools/check_levels.py could not be read ({problem!r})", file=sys.stderr)
        return {}


armory = read("src/shared/Config/Armory.json")
layouts = dict(read_folder("src/shared/Layouts/Levels"))
# An arena a layout names is a .luau data module: bundled like a source, loaded by its name.
arenas = sorted({layout["arena"] for layout in layouts.values() if layout.get("arena")})
for arena in arenas:
    if (repo / f"src/shared/Layouts/Arenas/{arena}.luau").exists():
        SOURCES[f"Arena_{arena}"] = f"src/shared/Layouts/Arenas/{arena}.luau"
# One local for every other config a test reads (the bundle is one chunk of at most 200 locals).
fixtures = {
    "village": read("src/shared/Config/Missions/1_Village.json"),
    "combat": read("src/shared/Config/Combat.json"),
    # The real files, as they ship (tests_l1.luau "the real files").
    "expeditions": read("src/shared/Config/Expeditions.json"),
    "proving": read("src/shared/Config/ProvingGrounds.json"),
    "levels": [content for _, content in read_folder("src/shared/Config/Levels", True)],
    "missions": [content for _, content in read_folder("src/shared/Config/Missions", True)],
    # Files of those two folders that Catalog does not read (it takes <n>_<Name> only), while
    # tools/check_levels.py reads every *.json there.
    "unread": sorted(
        f"{folder}/{path.name}"
        for folder in ("Config/Levels", "Config/Missions")
        for path in (repo / "src/shared" / folder).glob("*.json")
        if not re.match(NUMBERED, path.stem)
    ),
    "layouts": layouts,
    "arenas": [arena for arena in arenas if f"Arena_{arena}" in SOURCES],
    "gate": gate_reading(),
}
parts = [
    f"local ARMORY: any = {to_luau(armory)}\n",
    f"local FIXTURES: any = {to_luau(fixtures)}\n",
    "local SOURCES = {}\n",
]
for name, rel in SOURCES.items():
    text = (repo / rel).read_text(encoding="utf-8")
    text = re.sub(r"(?m)^export type", "type", text)
    parts.append(f"SOURCES.{name} = function(game, script, require, Vector3, os, task, warn, RaycastParams, Enum)\n{text}\nend\n")
# One bundle, in this order: each file sees every local of the files before it. Only the last
# file's verdict line is kept, so the bundle prints one HARNESS line, after every case has run.
TESTS = [
    "tests.luau",
    "tests_w2.luau",
    "tests_s2.luau",
    "tests_s3.luau",
    "tests_p5.luau",
    "tests_l1_world.luau",
    "tests_l1.luau",
]
VERDICT = 'print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)'
for index, name in enumerate(TESTS):
    text = (here / name).read_text(encoding="utf-8")
    if index < len(TESTS) - 1:
        text = text.replace(VERDICT, "")
    parts.append(text)
bundle = here / "bundle.luau"
bundle.write_text("".join(parts), encoding="utf-8")
try:
    result = subprocess.run([luau, str(bundle)], capture_output=True, text=True, timeout=150)
except subprocess.TimeoutExpired as hung:
    out = hung.stdout or b""
    print(out.decode("utf-8", "replace") if isinstance(out, bytes) else out)
    print("HARNESS: HUNG (stopped after 150 s)")
    sys.exit(2)
print(result.stdout)
print(result.stderr, file=sys.stderr)
sys.exit(result.returncode)
