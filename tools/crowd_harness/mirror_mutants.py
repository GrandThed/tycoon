"""Proves each L1b Wave 2 comparison of tools/check_stage_mirror.py by a Luau mutant it catches
(INTERFACES "Wave 2 — the long road", gate 10). Every mutant is one exact-text change to a copy of a
real module, run through `check_stage_mirror.py --module NAME=<copy>`; the tool must FAIL with a
DIFF line on every one. A mutant whose text no longer occurs exactly once is STALE and counts as
missed: re-aim it at the module's new text, never delete it to go green.

    py tools/crowd_harness/mirror_mutants.py                 # every mutant; exit 1 on a miss
    py tools/crowd_harness/mirror_mutants.py --only Rouse    # the mutants whose label holds it
    py tools/crowd_harness/mirror_mutants.py --list          # the labels, nothing run
    py tools/crowd_harness/mirror_mutants.py --luau <exe>    # passed on to check_stage_mirror

Each run is a whole check_stage_mirror pass on a temporary copy; the repo's files are never
written. Run it beside the harness if you like, never beside mutate.py (both read the modules
mutate.py rewrites)."""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATHS = {"HitShapes": "src/shared/HitShapes.luau", "SwingGate": "src/shared/SwingGate.luau",
         "Combat": "src/shared/Combat.luau", "CampBrain": "src/combat/server/Services/CampBrain.luau",
         "StageFlow": "src/combat/server/Services/StageFlow.luau",
         "LevelGeometry": "src/combat/server/Services/LevelGeometry.luau"}
MUTANTS = [
    ("CrowdRay: the head term dropped", "HitShapes", "local entry = earlier(bodyEntry, headEntry)", "local entry = bodyEntry"),
    ("CrowdRay: the crit padded", "HitShapes",
     "return entry, HitShapes.Ray(origin, direction, reach, width, 0, head, headRadius) ~= nil",
     "return entry, HitShapes.Ray(origin, direction, reach, width, pad, head, headRadius) ~= nil"),
    ("CrowdRay: the body back to a sphere", "HitShapes", "\t\tradius,\n\t\ttop - radius,\n\t\tradius\n",
     "\t\theight / 2,\n\t\theight / 2,\n\t\tradius\n"),
    ("CrowdRay: top without the max", "HitShapes", "local top = math.max(height - 2 * headRadius, height / 2 + radius)",
     "local top = height - 2 * headRadius"),
    ("RayUpright: drops its top cap", "HitShapes", "firstIn(highEnter, highExit, reach)", "nil"),
    ("FlatToRect: square corners", "HitShapes", "\treturn math.sqrt(dx * dx + dz * dz)\nend\n\n-- The cosmetic",
     "\treturn math.max(dx, dz)\nend\n\n-- The cosmetic"),
    ("SwingGate.IsAir with >=", "SwingGate", "return height > standOffset + SwingGate.AIR_MARGIN_STUDS",
     "return height >= standOffset + SwingGate.AIR_MARGIN_STUDS"),
    ("SwingGate.Took ignores airborne", "SwingGate", "state.used = airborne", "state.used = true"),
    ("SwingGate.Landed does nothing", "SwingGate", "function SwingGate.Landed(state: State)\n\tstate.used = false",
     "function SwingGate.Landed(state: State)\n\tlocal _ = state"),
    ("SwingGate.Allows ignores used", "SwingGate", "return not (airborne and state.used)", "return true"),
    ("SwingGate: another margin", "SwingGate", "SwingGate.AIR_MARGIN_STUDS = 0.75", "SwingGate.AIR_MARGIN_STUDS = 0.5"),
    ("Dormant: true while home", "CampBrain", "\tif group.state ~= \"rest\" then\n\t\treturn false\n\tend\n\tlocal rect",
     "\tif group.state ~= \"rest\" and group.state ~= \"home\" then\n\t\treturn false\n\tend\n\tlocal rect"),
    ("Dormant: ignores dormantRadius", "CampBrain",
     "if HitShapes.FlatToRect(root.X, root.Z, rect.x, rect.z, rect.hx, rect.hz) <= radius then",
     "if HitShapes.FlatToRect(root.X, root.Z, rect.x, rect.z, rect.hx, rect.hz) <= 0 then"),
    ("Gap: the largest distance", "CampBrain", "if distance < best then", "if best == math.huge or distance > best then"),
    ("JoinIn: does not chain", "CampBrain", "\t\t\t\ttable.insert(answer, other)\n\t\t\t\ttable.insert(queue, other)",
     "\t\t\t\ttable.insert(answer, other)"),
    ("JoinIn: the first waker's sight for the chain", "CampBrain",
     "local reach = rules.joinFactor * postureRules(group.def, rules).sight",
     "local reach = rules.joinFactor * postureRules(groups[woke[1]].def, rules).sight"),
    ("JoinIn: joins a held group", "CampBrain", "\t\t\t\tand not candidate.held\n", "\t\t\t\tand true\n"),
    ("JoinIn: the factor's edge excluded", "CampBrain", "and gap <= reach", "and gap < reach"),
    ("Rouse wakes a held group", "CampBrain",
     "if group.held then\n\t\treturn false\n\tend\n\tif group.state ~= \"rest\" and not",
     "if false then\n\t\treturn false\n\tend\n\tif group.state ~= \"rest\" and not"),
    ("Rouse leaves a homeward group home", "CampBrain", "(group.state == \"home\" and inPlay)", "false"),
    ("Rouse lifts a homeward group with nobody in play", "CampBrain", "(group.state == \"home\" and inPlay)",
     "(group.state == \"home\")"),
    ("TentActive ignores the dead residents", "CampBrain", "return busy or residentsAlive <= 0", "return busy"),
    ("TentDue ignores active", "CampBrain", "return active and tent.left > 0 and", "return tent.left > 0 and"),
    ("TentSent does not move nextAt", "CampBrain", "tent.nextAt = now + every", "tent.nextAt = tent.nextAt"),
    ("Posts: a tent faces its centre", "CampBrain", "local turn = if posture == \"fire\" then math.pi else 0",
     "local turn = math.pi"),
    ("Shows: a tent sits", "CampBrain", "return if group.def.posture == \"fire\" then \"rest\" else \"idle\"",
     "return if group.def.posture == \"fire\" or group.def.posture == \"tent\" then \"rest\" else \"idle\""),
    ("Problems: a joinFactor of 0 passes", "CampBrain", "(key == \"homeTolerance\" or key == \"joinFactor\") and value <= 0",
     "key == \"homeTolerance\" and value <= 0"),
    ("Problems: dormantRadius at a sight passes", "CampBrain", "dormantRadius <= sight then", "dormantRadius < sight then"),
    ("ClearBonus floors", "Combat", "return math.round(share * cash), math.round(share * materials)",
     "return math.floor(share * cash), math.floor(share * materials)"),
    ("ClearBonus ignores rewardMult", "Combat", "local each, eachMaterials = Combat.KillReward(rewards, kind, rewardMult)",
     "local each, eachMaterials = Combat.KillReward(rewards, kind, 1)"),
    ("DeadFraction not clamped at 0", "Combat", "return math.min(math.max((spawned - math.max(queuedAlive, 0)) / spawned, 0), 1)",
     "return math.min((spawned - math.max(queuedAlive, 0)) / spawned, 1)"),
    ("WaveStock ignores the elite", "Combat", "stock[elite] = (stock[elite] or 0) + 1", "stock[elite] = stock[elite]"),
    ("StandsUp outside the countdown", "StageFlow", "if step ~= \"travel\" and step ~= \"armed\" and step ~= \"gate\" then",
     "if step ~= \"travel\" and step ~= \"armed\" then"),
    ("BossReserve without the boss", "StageFlow", "reserve = math.max(reserve, 1 + calls)", "reserve = math.max(reserve, calls)"),
    ("Plan: the tents left out of the population", "StageFlow", "\t\t\tsumOf(tentStocks),\n", "\t\t\t0,\n"),
    ("Plan: a tent's ring one post more", "StageFlow", "pcall(CampBrain.Posts, def, #kinds)", "pcall(CampBrain.Posts, def, #kinds + 1)"),
    ("Plan: a tent body counted twice in the stock", "StageFlow", "stock[kind] = (stock[kind] or 0) + 1",
     "stock[kind] = (stock[kind] or 0) + 2"),
    ("Validate: a share over 1 passes", "StageFlow", "or bonus.share > 1", "or bonus.share > 2"),
    ("Validate: the population leaves the tents out", "StageFlow",
     "local population = populationOf(residents, sumOf(tentStocks), caps, reserve)",
     "local population = populationOf(residents, 0, caps, reserve)"),
    ("Validate: a tent on a boss room passes", "StageFlow",
     "problem(`{here}: camp {camp.id} locks, and a boss room's tent has no stock`)", "local _ = here"),
    ("Advance: a campClear with tent stock left", "StageFlow", "or (tentLeft[index] or 0) ~= 0", "or false"),
    # The fix round (B-2 and B-4, mirrored by the economy-designer).
    ("Validate: the posts at the highest difficulty only", "StageFlow", "for _, rank in levelRanks do",
     "for _, rank in { levelRanks[1] } do"),
    ("Plan: a tent's door on the wall whatever the kind", "StageFlow",
     "local clear = if body ~= nil then body.radius else 0", "local clear = 0"),
    ("TentDoor: no clearance past the wall", "LevelGeometry",
     "local out = math.min(edge + math.max(clear, 0), distance)", "local out = math.min(edge, distance)"),
]


def arg(name):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None


def main():
    only = arg("--only")
    luau = arg("--luau")
    chosen = [m for m in MUTANTS if not only or only in m[0]]
    if "--list" in sys.argv:
        for label, module, _old, _new in chosen:
            print(f"{module:10} {label}")
        print(f"\n{len(chosen)} mutants")
        return
    if not chosen:
        raise SystemExit(f"mirror_mutants: no mutant label holds {only!r}")
    tool = [sys.executable, str(ROOT / "tools" / "check_stage_mirror.py")] + (["--luau", luau] if luau else [])
    # A mirror already red would "catch" every mutant by its standing DIFF: refuse to count then.
    baseline = subprocess.run(tool, capture_output=True, text=True, timeout=600)
    if baseline.returncode != 0:
        tail = (baseline.stdout + baseline.stderr).strip().splitlines()[-3:]
        raise SystemExit(f"mirror_mutants: check_stage_mirror.py fails unmutated (exit {baseline.returncode}), so no "
                         f"mutant can be judged; make it pass first. {tail}")
    caught = missed = 0
    with tempfile.TemporaryDirectory() as scratch:
        for label, module, old, new in chosen:
            text = (ROOT / PATHS[module]).read_text(encoding="utf-8")
            if text.count(old) != 1:
                print(f"STALE   {label}: the text occurs {text.count(old)} times in {module}")
                missed += 1
                continue
            copy = Path(scratch) / f"{module}.luau"
            copy.write_text(text.replace(old, new), encoding="utf-8")
            result = subprocess.run(tool + ["--module", f"{module}={copy}", "--show", "1"], capture_output=True, text=True,
                                    timeout=600)
            diffs = [line.strip() for line in result.stdout.splitlines() if line.strip().startswith("DIFF")]
            if result.returncode != 0 and diffs:
                caught += 1
                print(f"caught  {label}: {diffs[0][:150]}")
            else:
                missed += 1
                tail = (result.stdout + result.stderr).strip().splitlines()[-2:]
                print(f"MISSED  {label} (exit {result.returncode}) {tail}")
    print(f"\n{caught} of {caught + missed} mutants caught")
    sys.exit(0 if missed == 0 else 1)


if __name__ == "__main__":
    main()
