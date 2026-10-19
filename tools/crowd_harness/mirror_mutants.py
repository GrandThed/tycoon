"""Proves each L1b Wave 2 and Wave 4 comparison of tools/check_stage_mirror.py by a Luau mutant it
catches (INTERFACES "Wave 2 — the long road" and "L1b Wave 4 — no waits, no walls", gate 10). Every mutant is one exact-text change to a copy of a
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
         "Region": "src/shared/Region.luau",
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
    # Re-aimed at Wave 4's text (L1b-W4-28: `inPlay` is `reachable`; TentActive takes `ahead`).
    ("Rouse leaves a homeward group home", "CampBrain", "(group.state == \"home\" and reachable)", "false"),
    ("Rouse lifts a homeward group with nobody reachable", "CampBrain", "(group.state == \"home\" and reachable)",
     "(group.state == \"home\")"),
    ("TentRouse with nobody reachable rouses", "CampBrain",
     "if not reachable then\n\t\treturn false\n\tend\n\treturn CampBrain.Rouse(group, now, reachable)",
     "if false then\n\t\treturn false\n\tend\n\treturn CampBrain.Rouse(group, now, reachable)"),
    ("TentRouse never lifts a homeward group", "CampBrain", "return CampBrain.Rouse(group, now, reachable)",
     "return CampBrain.Rouse(group, now, false)"),
    ("TentActive ignores the dead residents", "CampBrain", "return busy and residentsAlive > 0 and ahead",
     "return busy and ahead"),
    ("TentDue ignores active", "CampBrain", "return active and tent.left > 0 and", "return tent.left > 0 and"),
    ("TentSent does not move nextAt", "CampBrain", "tent.nextAt = now + every", "tent.nextAt = tent.nextAt"),
    ("Posts: a tent faces its centre", "CampBrain", "local turn = if posture == \"fire\" then math.pi else 0",
     "local turn = math.pi"),
    ("Shows: a tent sits", "CampBrain", "return if group.def.posture == \"fire\" then \"rest\" else \"idle\"",
     "return if group.def.posture == \"fire\" or group.def.posture == \"tent\" then \"rest\" else \"idle\""),
    ("Problems: a joinFactor of 0 passes", "CampBrain", "\tjoinFactor = true,\n", "\tjoinFactor = false,\n"),
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
    ("Fielded: a tent body counted twice", "StageFlow", "fielded[kind] = (fielded[kind] or 0) + 1",
     "fielded[kind] = (fielded[kind] or 0) + 2"),
    ("Validate: a share over 1 passes", "StageFlow", "or bonus.share > 1", "or bonus.share > 2"),
    ("Validate: the population leaves the tents out", "StageFlow",
     "local population = populationOf(residents, sumOf(tentStocks), caps, reserve)",
     "local population = populationOf(residents, 0, caps, reserve)"),
    ("Validate: a tent on a boss room passes", "StageFlow",
     "problem(`{here}: camp {camp.id} locks, and a boss room's tent has no stock`)", "local _ = here"),
    ("Advance: a camp clears with a body of its floor alive", "StageFlow", "or byFloor[index] ~= 0 then",
     "or byFloor[index] > 1 then"),
    # Replaces Wave 2's "a campClear with tent stock left" (its input is gone, L1b-W4-29).
    ("Advance: the clear waits for the tent again", "StageFlow", "or byFloor[index] ~= 0 then",
     "or byFloor[index] ~= 0 or zone.tentStock > 0 then"),
    # The fix round (B-2 and B-4, mirrored by the economy-designer).
    ("Validate: the posts at the highest difficulty only", "StageFlow", "for _, rank in levelRanks do",
     "for _, rank in { levelRanks[1] } do"),
    ("Plan: a tent's door on the wall whatever the kind", "StageFlow",
     "local clear = if body ~= nil then body.radius else 0", "local clear = 0"),
    ("TentDoor: no clearance past the wall", "LevelGeometry",
     "local out = math.min(edge + math.max(clear, 0), distance)", "local out = math.min(edge, distance)"),
    # The fix-diff round (m2): TentOwesRouse, compared over all its inputs.
    ("TentOwesRouse: owed while the group is up", "StageFlow", "return owed and campBusy and not groupAwake",
     "return owed and campBusy"),
    ("TentOwesRouse: owed for a quiet camp", "StageFlow", "return owed and campBusy and not groupAwake",
     "return owed and not groupAwake"),
    ("TentOwesRouse: owed from nothing", "StageFlow", "return owed and campBusy and not groupAwake",
     "return campBusy and not groupAwake"),
    # L1b Wave 4: Region.
    ("Region.Clamp ignores the radius", "Region",
     "local limitX = math.max(cell.hx - radius, 0)\n\t\tlocal limitZ = math.max(cell.hz - radius, 0)\n\t\tlocal cx",
     "local limitX = math.max(cell.hx, 0)\n\t\tlocal limitZ = math.max(cell.hz, 0)\n\t\tlocal cx"),
    ("Region.Runway stops at the first cell's edge", "Region", "if t0 <= t1 and t0 <= reach + EPS and t1 > reach then",
     "if t0 <= t1 and t0 <= EPS and t1 > reach then"),
    ("Region.Toward always answers the goal", "Region", "if bestI == 0 or bestI == bestJ then", "if true then"),
    ("Region.Toward ignores the hops (the first pair wins)", "Region", "if hops ~= nil and hops < bestHops",
     "if hops ~= nil and bestHops == math.huge"),
    ("Region.Problems accepts a cycle", "Region", "if joined and pairCount ~= count - 1 then", "if false then"),
    ("Region.Problems checks a door on x only", "Region", "wideX < minDoor - EPS or wideZ < minDoor - EPS",
     "wideX < minDoor - EPS"),
    ("Region.Distance takes the farthest cell", "Region", "if distance < best then",
     "if best == math.huge or distance > best then"),
    ("Region.Inside without its edge", "Region", "return math.abs(x - cell.x) <= limitX + EPS",
     "return math.abs(x - cell.x) < limitX - EPS"),
    # L1b Wave 4: CampBrain (known, reachable, the leash, the stand-down, home, Forget, the pace).
    # Re-aimed at the fix round's text (R14: Melee names `above`).
    ("Melee ignores meleeAbove", "CampBrain", "and above <= rules.meleeAbove", "and true"),
    ("Known ignores the hit memory", "CampBrain", "if group.hitAt[target.userId] ~= nil then", "if false then"),
    ("Known by sight past chaseSight", "CampBrain", "if flatDistance(member.at, root) <= sight then",
     "if flatDistance(member.at, root) <= sight + 1 then"),
    ("The prune keeps old hits", "CampBrain", "if now - at > memory + TIME_EPSILON then", "if false then"),
    ("Struck ignores now", "CampBrain", "group.hitAt[byUserId] = now", "group.hitAt[byUserId] = 0"),
    ("The leash ignores closing", "CampBrain", "if anyReach or input.closing then", "if anyReach then"),
    ("The stand-down never sets", "CampBrain",
     "elseif not group.standDown and now - group.meleeQuietSince >= leash then", "elseif false then"),
    ("Closing does not hold the stand-down", "CampBrain", "elseif not group.standDown and input.closing then",
     "elseif false then"),
    ("StandsDown ignores rusher", "CampBrain",
     "return rusher and not group.held and group.state == \"fight\" and group.standDown",
     "return not group.held and group.state == \"fight\" and group.standDown"),
    ("Home turns back for an unreachable player", "CampBrain", "if not reachable[userId] then", "if false then"),
    ("Forget leaves a fighting group fighting", "CampBrain",
     "if group.held or (group.state ~= \"rise\" and group.state ~= \"fight\") then",
     "if group.held or group.state ~= \"rise\" then"),
    ("Evades again on the way home", "CampBrain", "\treturn group.held\n",
     "\treturn group.held or group.state == \"home\"\n"),
    ("TentClock counts idle time", "CampBrain", "tent.busySeconds += math.max(now - lastAt, 0)",
     "tent.busySeconds += math.max(now - lastAt, 0) + 1"),
    ("Ahead ignores lead", "CampBrain",
     "return killed / residents - busySeconds / pace.seconds >= pace.lead - TIME_EPSILON",
     "return killed / residents - busySeconds / pace.seconds >= -TIME_EPSILON"),
    ("TentActive ignores ahead", "CampBrain", "return busy and residentsAlive > 0 and ahead",
     "return busy and residentsAlive > 0"),
    # L1b Wave 4: StageFlow.
    ("Fielded ignores sent", "StageFlow", "for index = 1, math.min(sent, #tent.kinds) do", "for index = 1, #tent.kinds do"),
    ("Skip: N ignores a reached checkpoint", "StageFlow",
     "for index in state.reached do\n\t\tfrom = math.max(from, index)\n\tend",
     "for index in state.reached do\n\t\tlocal _ = index\n\tend"),
    ("Skip: N ignores approached", "StageFlow", "local from = state.approached", "local from = 0"),
    ("Plan: a zone's region dropped", "StageFlow", "region = graphs[camp.id],", "region = nil,"),
    ("Validate: the lock clearance skipped", "StageFlow", "if gap < needed - 1e-6 then", "if false then"),
    ("Validate: a tent without pace passes", "StageFlow", "problem(`{here}: its tent has no pace`)", "local _ = here"),
    # L1b Wave 4 fix round (docs/prompts/l1b-w4-fix-round.md): one per rule the mirror copies from a
    # module check_stage_mirror runs. R1, R4, R5, R6 and R15 live in CrowdService, CrowdBrain,
    # VitalsService and ThreatField, which it does not run: mutate.py holds those.
    ("R2: home rests with a blow in the air", "CampBrain", "\t\telseif not input.striking then\n\t\t\t-- R2:",
     "\t\telse\n\t\t\t-- R2:"),
    ("R7: the pace measure never starts again at rest", "CampBrain", "\tif rested then\n\t\ttent.busySeconds = 0",
     "\tif false then\n\t\ttent.busySeconds = 0"),
    ("R7: a restart at rest keeps the busy time", "CampBrain", "\tif rested then\n\t\ttent.busySeconds = 0\n",
     "\tif rested then\n"),
    ("R7: a restart at rest keeps the old resident count", "CampBrain", "\t\ttent.residents = residentsAlive\n", ""),
    ("R7: NewTent counts from no resident", "CampBrain", "\t\tresidents = residents,\n", "\t\tresidents = 0,\n"),
    ("R14: Melee has no lower bound", "CampBrain", "\t\tand above >= -rules.meleeBelow\n", ""),
    ("R14: Melee's lower bound is meleeAbove", "CampBrain", "and above >= -rules.meleeBelow",
     "and above >= -rules.meleeAbove"),
    ("R14: Problems does not ask for meleeBelow", "CampBrain", '\t"meleeAbove",\n\t"meleeBelow",\n}',
     '\t"meleeAbove",\n}'),
    ("R16: Melee judges on the live root", "CampBrain", "local above = target.rest - def.floorY",
     "local above = root.Y - def.floorY"),
    ("R12: Fielded prices a refused spawn", "StageFlow", "if refused ~= nil and refused[index] then",
     "if false then"),
    ("R10: SafePoint judges a region zone by busy", "StageFlow",
     "local quiet = zone.region ~= nil or busy == nil or busy[index] ~= true",
     "local quiet = busy == nil or busy[index] ~= true"),
    ("R10: Threatening leaves home out", "StageFlow",
     'return state == "rise" or state == "fight" or state == "home"', 'return state == "rise" or state == "fight"'),
    # The L1c fix round's M3: a camp's own countdown (the Chief's Clearing ships 0).
    ("L1c M3: the countdown ignores the stage's own", "StageFlow", "\t\tthen stage.gateSeconds\n",
     "\t\tthen rules.gateSeconds\n"),
    ("L1c M3: Plan drops a stage's gateSeconds", "StageFlow", "\t\t\tgateSeconds = stage.gateSeconds,\n", ""),
    ("L1c M3: a countdown of 0 waits a tick after the trigger", "StageFlow", '\t\tstep = "gate"\n',
     "\t\treturn actions\n"),
    ("L1c M3: a skip into a countdown of 0 waits a tick", "StageFlow",
     "\tif now >= state.gateAt then\n\t\tclose(state, actions, now)\n", "\tif false then\n\t\tclose(state, actions, now)\n"),
    ("L1c M3: Validate takes any gateSeconds", "StageFlow",
     "\t\t\tproblem(`{where}: gateSeconds is {tostring(countdown)}, not a time`)\n", ""),
    # The L1c second fix round's F1 and F3: a walled camp's band reaches its fence top.
    ("L1c F1: Plan gives every camp triggerHeight", "StageFlow",
     "ceiling = StageFlow.Ceiling(camp, rules.triggerHeight),", "ceiling = rules.triggerHeight,"),
    ("L1c F1: the trigger asks triggerHeight again", "StageFlow", "and above <= zone.ceiling",
     "and above <= rules.triggerHeight"),
    ("L1c F1: Ceiling ignores locks", "StageFlow", "if camp.locks ~= true or fence == nil then",
     "if fence == nil then"),
    ("L1c F1: Ceiling takes a fence under triggerHeight", "StageFlow",
     "if isFinite(top) and top > triggerHeight then", "if isFinite(top) then"),
    # F2 and the third fix round's m3: the close's nudge onto `inner`.
    ("L1c F2: the nudge ignores the ceiling", "StageFlow",
     "if not (above <= zone.ceiling and above >= -rules.triggerBelow) then",
     "if not (above >= -rules.triggerBelow) then"),
    ("L1c m3: the nudge drops the fenced-rectangle test", "StageFlow",
     "if not inRect(zone.trigger, position.X, position.Z) then\n\t\treturn nil", "if false then\n\t\treturn nil"),
    ("L1c m3: the nudge does not hold X to inner", "StageFlow",
     "math.min(math.max(position.X, inner.x - inner.hx), inner.x + inner.hx),", "position.X,"),
    ("L1c m3: the nudge lands on the floor's edge", "StageFlow",
     "local inner = zone.inner\n\treturn Vector3.new(", "local inner = zone.rect\n\treturn Vector3.new("),
    # L2 W3 (L2-52, L2-58): Validate's ice and landing lines.
    ("L2 W3: an ice block may collide", "StageFlow",
     "\t\t\tif block.collide ~= false then\n\t\t\t\tproblem(`{where} is ice and collides`)",
     "\t\t\tif false then\n\t\t\t\tproblem(`{where} is ice and collides`)"),
    ("L2 W3: an ice block may open a shortcut", "StageFlow",
     "\t\t\tif opens ~= nil then\n\t\t\t\tproblem(`{where} is ice and opens",
     "\t\t\tif false then\n\t\t\t\tproblem(`{where} is ice and opens"),
    # Re-aimed by the W3 fix round's Q3: a landing on any block a body falls through.
    ("L2 W3: any block may have a landing", "StageFlow",
     "\t\t\tif block.collide ~= false then\n\t\t\t\tproblem(`{where} has a landing and collides`)",
     "\t\t\tif false then\n\t\t\t\tproblem(`{where} has a landing and collides`)"),
    ("L2 W3: a landing's numbers are not checked", "StageFlow",
     "\t\t\t\t\tif not isFinite(landing[key]) then", "\t\t\t\t\tif false then"),
    ("L2 W3: a landing that is no table passes", "StageFlow",
     "\t\t\tif type(landing) ~= \"table\" then\n\t\t\t\tproblem(`{where}: landing is {tostring(landing)}, not a point`)\n\t\t\telse",
     "\t\t\tif false then\n\t\t\telseif type(landing) == \"table\" then"),
    # The W3 fix round's s-s2: ice footprints may touch but not overlap.
    ("L2 W3 fix s-s2: ice blocks may overlap", "StageFlow",
     "if LevelGeometry.Overlap(other.block, block) then", "if false then"),
    ("L2 W3 fix s-s2: any blocks may overlap", "StageFlow",
     "\t\tif type(block) ~= \"table\" or block.react ~= \"ice\" then\n\t\t\tcontinue\n\t\tend\n\t\tif\n",
     "\t\tif type(block) ~= \"table\" then\n\t\t\tcontinue\n\t\tend\n\t\tif\n"),
    ("L2 W3 fix s-s2: Overlap counts touching", "LevelGeometry",
     "return math.abs(a.x - b.x) < (a.sx + b.sx) / 2 - SEAM", "return math.abs(a.x - b.x) <= (a.sx + b.sx) / 2 + SEAM"),
    # The W3 second fix round's Q6: the ice cells inset from their water's own faces, against
    # sim_range.ice_cells box by box.
    ("L2 W3 fix2 Q6: no inset on the east", "LevelGeometry",
     "local east = cell.x + cell.sx / 2 - (if i == nx then ice.inset else 0)", "local east = cell.x + cell.sx / 2"),
    ("L2 W3 fix2 Q6: every north face inset", "LevelGeometry",
     "local north = cell.z - cell.sz / 2 + (if j == 1 then ice.inset else 0)", "local north = cell.z - cell.sz / 2 + ice.inset"),
    ("L2 W3 fix2 Q6: a cell left no width is built", "LevelGeometry",
     "if not covered and east - west > SEAM and south - north > SEAM then", "if not covered then"),
    ("L2 W3 fix2 Q6: IceOf takes an inset under 0", "LevelGeometry", "\t\tand inset >= 0\n", ""),
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
