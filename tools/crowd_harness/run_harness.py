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
L1b adds the pure CampBrain (how a camp's resident groups rest, wake, chase and go home) and two
case files: tests_l1b_crowd.luau (CampBrain and CrowdService's floors and groups) and
tests_l1b.luau (StageFlow's open camps, checkpoints and clear field, Combat's per-kill split with
its carry, LevelGeometry's open camps and fire markers).
L1c adds the pure WallClip (the camera boom kept out of a locking camp, the ground point's height
rule) and tests_l1c.luau (it, and the walled Chief's Clearing as it ships).
It proves the logic, not Roblox behaviour. RangeService is not loadable here.

The cases are this folder's, and the sources the first argument's. So it refuses to run (exit 2,
`HARNESS: REFUSED`) when that root holds another copy of this harness: run_harness.py or a case
file that differs from the ones running, or is missing. Run from the main checkout against a
worktree it would otherwise run main's cases on the worktree's sources and could say PASS.

The verdict is always the last line, and names how many checks ran and from which folder, so a
count can be compared with the one its author reported:
  HARNESS: PASS (1,292 checks, <folder>)                  every case ran and passed
  HARNESS: FAIL (n of 1,292 checks, <folder>)             every case ran, n failed
  HARNESS: FAIL (stopped after 96 checks, <folder>)       the bundle stopped part way (a module
                                                          or a case threw): reported as one more
                                                          failing check, `FAIL  the bundle stopped`
  HARNESS: SILENT (no case ran, <folder>)                 no interpreter, or a bundle that does
                                                          not compile
  HARNESS: HUNG (stopped after 150 s, <folder>)
  HARNESS: REFUSED (another checkout's harness, <folder>)
Only PASS exits 0. tools/crowd_harness/mutate.py reads these lines.

Usage: py tools/crowd_harness/run_harness.py [repo root] [luau.exe]
(defaults: this repo, tools/bin/luau.exe, which tools/check_mirror.py fetches).
Importing this file runs nothing: `sources`, `wrap`, `fixtures`, `to_luau` and `prelude` are
there for another tool that wants the same modules under the same wrapper."""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TIMEOUT_SECONDS = 150

# The modules every bundle carries, by the name the cases load them under.
SOURCES = {
    "CrowdCodec": "src/shared/CrowdCodec.luau",
    "HitShapes": "src/shared/HitShapes.luau",
    # L1b Wave 4: the chase region (CrowdBrain, CampBrain, StageFlow and CampAim's renderer need it).
    "Region": "src/shared/Region.luau",
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
    "SwingGate": "src/shared/SwingGate.luau",
    "CampBrain": "src/combat/server/Services/CampBrain.luau",
    "StageFlow": "src/combat/server/Services/StageFlow.luau",
    # L1b Wave 2: the client's pure reading of a spawn info (the lead's routing: tested here).
    "SpawnSeed": "src/combat/client/Controllers/SpawnSeed.luau",
    # The L1b Wave 2 fix round, ui-2: touch auto-target's camp rule (the ui-engineer's).
    "CampAim": "src/combat/client/Controllers/CampAim.luau",
    # L1c: the camera boom's clip and the ground point's height rule (tests_l1c.luau).
    "WallClip": "src/shared/WallClip.luau",
}
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
    "tests_l1b_crowd.luau",
    "tests_l1b.luau",
    "tests_l1b_w2_crowd.luau",
    "tests_l1b_w2.luau",
    # L1b Wave 4: the region, the chase and the pace tent in the crowd (A's), then the run's
    # regions, pace, Fielded and N (B's).
    "tests_l1b_w4_crowd.luau",
    "tests_l1b_w4.luau",
    # L1c: WallClip, then the walled Chief's Clearing as built and planned.
    "tests_l1c.luau",
]
VERDICT = 'print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)'
NUMBERED = r"\d+_"
# A case's line, as tests.luau's `check` prints it.
CHECK_LINE = re.compile(r"^\s+(ok|FAIL)\s")


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


def read(repo: Path, path: str) -> object:
    return json.loads((repo / path).read_text(encoding="utf-8"))


def read_folder(repo: Path, folder: str, numbered: bool = False) -> list:
    """Every JSON file of a folder as (stem, content). `numbered`: only the files Catalog reads
    there, those named <n>_<Name>, in its order: by that number, then by name."""
    def order(path: Path):
        prefix = re.match(r"\d+", path.stem)
        return (int(prefix.group()) if prefix else 0, path.stem)

    paths = sorted((repo / folder).glob("*.json"), key=order)
    if numbered:
        paths = [path for path in paths if re.match(NUMBERED, path.stem)]
    return [(path.stem, read(repo, f"{folder}/{path.name}")) for path in paths]


def gate_reading() -> dict:
    """What tools/check_levels.py makes of the layouts: its Part count for each (its `N Parts`
    lines) and, for a layout that names an arena, the level layout its own adapter reads out of
    that arena. Always this checkout's files (the tool takes no root; a mutant root holds copies
    of the same data). Empty when the tool cannot be imported: the cases that need it then fail."""
    try:
        sys.path.insert(0, str(HERE.parent))
        import check_levels

        layouts = check_levels.load_all()[2]
        return {
            "parts": {name: check_levels.part_count(layout) for name, layout in layouts.items()},
            "arenas": {name: layout for name, layout in layouts.items() if layout.get("arena")},
        }
    except (Exception, SystemExit) as problem:  # the harness still runs, and says so
        print(f"run_harness: tools/check_levels.py could not be read ({problem!r})", file=sys.stderr)
        return {}


def sources(repo: Path) -> dict:
    """SOURCES, plus every arena a level layout names: an arena is a .luau data module, bundled
    like a source and loaded as `Arena_<name>`."""
    found = dict(SOURCES)
    layouts = dict(read_folder(repo, "src/shared/Layouts/Levels"))
    for arena in sorted({layout["arena"] for layout in layouts.values() if layout.get("arena")}):
        if (repo / f"src/shared/Layouts/Arenas/{arena}.luau").exists():
            found[f"Arena_{arena}"] = f"src/shared/Layouts/Arenas/{arena}.luau"
    return found


def fixtures(repo: Path) -> dict:
    """One local for every config a case reads (the bundle is one chunk of at most 200 locals)."""
    layouts = dict(read_folder(repo, "src/shared/Layouts/Levels"))
    bundled = sources(repo)
    arenas = sorted({layout["arena"] for layout in layouts.values() if layout.get("arena")})
    return {
        "village": read(repo, "src/shared/Config/Missions/1_Village.json"),
        "combat": read(repo, "src/shared/Config/Combat.json"),
        # The real files, as they ship (tests_l1.luau "the real files").
        "expeditions": read(repo, "src/shared/Config/Expeditions.json"),
        "proving": read(repo, "src/shared/Config/ProvingGrounds.json"),
        "levels": [content for _, content in read_folder(repo, "src/shared/Config/Levels", True)],
        "missions": [content for _, content in read_folder(repo, "src/shared/Config/Missions", True)],
        # Files of those two folders that Catalog does not read (it takes <n>_<Name> only), while
        # tools/check_levels.py reads every *.json there.
        "unread": sorted(
            f"{folder}/{path.name}"
            for folder in ("Config/Levels", "Config/Missions")
            for path in (repo / "src/shared" / folder).glob("*.json")
            if not re.match(NUMBERED, path.stem)
        ),
        "layouts": layouts,
        "arenas": [arena for arena in arenas if f"Arena_{arena}" in bundled],
        "gate": gate_reading(),
    }


# The interpreter's typeof answers "table" for the cases' Vector3 shim; a module that checks
# `typeof(x) == "Vector3"` (SpawnSeed reads one off the network) must see "Vector3" for it.
TYPEOF = (
    "local typeof = function(value: any): string\n"
    '\tif type(value) == "table" and getmetatable(value) == getmetatable(Vector3.new(0, 0, 0)) then\n'
    '\t\treturn "Vector3"\n'
    "\tend\n"
    "\treturn typeof(value)\n"
    "end\n"
)


def wrap(name: str, text: str) -> str:
    """A module's source as `SOURCES.<name>`: a function of the globals the cases stub."""
    text = re.sub(r"(?m)^export type", "type", text)
    return (
        f"SOURCES.{name} = function(game, script, require, Vector3, os, task, warn, RaycastParams, Enum)\n"
        f"{TYPEOF}{text}\nend\n"
    )


def prelude(repo: Path) -> str:
    """Everything before the cases: ARMORY, FIXTURES and the wrapped modules."""
    parts = [
        f"local ARMORY: any = {to_luau(read(repo, 'src/shared/Config/Armory.json'))}\n",
        f"local FIXTURES: any = {to_luau(fixtures(repo))}\n",
        "local SOURCES = {}\n",
    ]
    for name, rel in sources(repo).items():
        parts.append(wrap(name, (repo / rel).read_text(encoding="utf-8")))
    return "".join(parts)


def bundle(repo: Path) -> str:
    parts = [prelude(repo)]
    for index, name in enumerate(TESTS):
        text = (HERE / name).read_text(encoding="utf-8")
        if index < len(TESTS) - 1:
            text = text.replace(VERDICT, "")
        parts.append(text)
    return "".join(parts)


def differences(repo: Path) -> list:
    """This harness's own files (this script and its case files) that `repo` holds differently
    from the ones running, or not at all."""
    differ = []
    for name in ["run_harness.py", *TESTS]:
        theirs = repo / "tools" / "crowd_harness" / name
        if not theirs.is_file() or theirs.read_bytes() != (HERE / name).read_bytes():
            differ.append(name)
    return differ


def main(argv: list) -> int:
    repo = Path(argv[1]) if len(argv) > 1 else HERE.parents[1]
    luau = argv[2] if len(argv) > 2 else str(HERE.parents[1] / "tools" / "bin" / "luau.exe")
    differ = differences(repo)
    if differ:
        print(
            f"run_harness: {repo} holds another harness than the one running ({HERE}): "
            f"{', '.join(differ)} differ. Run that checkout's own tools/crowd_harness/run_harness.py.",
            file=sys.stderr,
        )
        print(f"HARNESS: REFUSED (another checkout's harness, {HERE})")
        return 2
    path = HERE / "bundle.luau"
    path.write_text(bundle(repo), encoding="utf-8")
    try:
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired as hung:
        out = hung.stdout or b""
        print(out.decode("utf-8", "replace") if isinstance(out, bytes) else out)
        print(f"HARNESS: HUNG (stopped after {TIMEOUT_SECONDS} s, {HERE})")
        return 2
    except OSError as problem:
        print(f"run_harness: {luau} could not be run ({problem})", file=sys.stderr)
        print(f"HARNESS: SILENT (no case ran, {HERE})")
        return 2
    lines = result.stdout.splitlines()
    ran = sum(1 for line in lines if CHECK_LINE.match(line))
    verdicts = [index for index, line in enumerate(lines) if line.startswith("HARNESS: ")]
    if verdicts:
        # The bundle's own verdict, with the count and the folder added.
        last = verdicts[-1]
        passed = lines[last] == "HARNESS: PASS" and result.returncode == 0
        failed = re.match(r"HARNESS: FAIL \((\d+)\)$", lines[last])
        if passed:
            lines[last] = f"HARNESS: PASS ({ran:,} checks, {HERE})"
        elif failed:
            lines[last] = f"HARNESS: FAIL ({failed.group(1)} of {ran:,} checks, {HERE})"
        print("\n".join(lines))
        print(result.stderr, file=sys.stderr)
        return 0 if passed else 1
    print(result.stdout)
    print(result.stderr, file=sys.stderr)
    # No verdict: the bundle did not reach its last line.
    if ran == 0:
        print(f"HARNESS: SILENT (no case ran, {HERE})")
        return 2
    said = (result.stderr.strip().splitlines() or ["no error was printed"])[0]
    print(f"  FAIL  the bundle stopped after {ran} checks, before its verdict: {said}")
    print(f"HARNESS: FAIL (stopped after {ran:,} checks, {HERE})")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
