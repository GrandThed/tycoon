"""Regression harness for the crowd combat server (P4): bundles the real CrowdCodec, HitShapes,
Armory, Tuning, CrowdBrain, ThreatField, StrikeTally, CrowdService and VitalsService sources
with stubbed Roblox globals and runs the tests_*.luau cases under the plain luau interpreter.
P5 adds tests_p5.luau: the mission scales, kill info, KillAll and VitalsService.SetMission.
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
    "Armory": "src/shared/Armory.luau",
    "Tuning": "src/shared/Tuning.luau",
    "CrowdBrain": "src/combat/server/Services/CrowdBrain.luau",
    "ThreatField": "src/combat/server/Services/ThreatField.luau",
    "StrikeTally": "src/combat/server/Services/StrikeTally.luau",
    "CrowdService": "src/combat/server/Services/CrowdService.luau",
    "VitalsService": "src/combat/server/Services/VitalsService.luau",
}


def to_luau(value) -> str:
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{json.dumps(key)}] = {to_luau(item)}" for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ", ".join(to_luau(item) for item in value) + "}"
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    return json.dumps(value)


armory = json.loads((repo / "src/shared/Config/Armory.json").read_text(encoding="utf-8"))
parts = [f"local ARMORY: any = {to_luau(armory)}\n", "local SOURCES = {}\n"]
for name, rel in SOURCES.items():
    text = (repo / rel).read_text(encoding="utf-8")
    text = re.sub(r"(?m)^export type", "type", text)
    parts.append(f"SOURCES.{name} = function(game, script, require, Vector3, os, task, warn, RaycastParams, Enum)\n{text}\nend\n")
# One bundle, in this order: each file sees every local of the files before it. Only the last
# file's verdict line is kept, so the bundle prints one HARNESS line, after every case has run.
TESTS = ["tests.luau", "tests_w2.luau", "tests_s2.luau", "tests_s3.luau", "tests_p5.luau"]
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
