# L1c fix round: code agent report (2026-10-16)

Branch `l1c-chief-clearing` in `tycoon-p5`. Nothing is committed.

## Findings

### C1: the camera clip is grown by `levels.cameraClear`

**Config and types**
- `src/shared/Config/Combat.json:151` adds `levels.cameraClear` 3.5.
- `src/shared/Types.luau:2697` adds `CombatLevelsConfig.cameraClear: number`. The `RunFloor.locks` comment is updated.

**`WallClip.Reach`** (`src/shared/WallClip.luau:106`). The new signature is:

```luau
WallClip.Reach(fromX, fromZ, dx, dz, rects: { Rect }, rootX, rootY, rootZ, clip: Clip): number
-- Rect = { x, y, z, hx, hz }   (y = the floor's top)
-- Clip = { pad, margin, height }
```

- The cut tests each rectangle grown by `clip.margin` (line 122).
- The release test, `holds` at line 56, stays on the true fenced rectangle, as the code reviewer asked.
- A margin that is negative, NaN or infinite counts as no margin, the same as the pad.
- A rectangle whose `y` is not a number is skipped.

**CameraController**
- `src/combat/client/Controllers/CameraController.luau:869-872` reads the clip from config:
  - `pad` is Theme's collision pad;
  - `margin` is `levels.cameraClear`;
  - `height` is `levels.triggerHeight`.
- Before Init the margin is 0 and the height is `math.huge`, so the clip falls back to the first L1c behaviour.
- `campReach` now passes `root.Y` (line 439).
- `SetFloors` now carries `floor.y` (line 943).

**What a player sees.** A root that stands inside the 3.5-stud margin but outside the fence has its boom start inside the grown rectangle. The camera comes in to the pivot, which the reviewer accepted as the head-level doorway glimpse. On Forest Road this is only the last 3.5 studs of leg 2 before the trigger line.

### m1: the release also needs the root within `triggerHeight` of the floor
- The rule is in `WallClip` `holds`: `y - rect.y <= height`. It is a ceiling only, so a root sunk under the floor still counts as inside.
- The client passes `levels.triggerHeight`.

### M1: Reset is turned off, and the default camera's zoom is capped
- `CameraController.luau:881` adds `disableReset`, which calls `StarterGui:SetCore("ResetButtonCallback", false)` inside a `pcall`.
  - It retries 60 times, 0.5 s apart, then warns.
  - It runs from `Start` through `task.spawn` (line 895).
- There were no SetCore calls before this one.
- `combat.project.json` sets `StarterPlayer.$properties.CameraMaxZoomDistance = 16`.
  - That is Combat.json `camera.maxZoom`, which is **16**.
  - A built rbxlx was checked and holds `<float name="CameraMaxZoomDistance">16`.
  - `tools/proving_project.py` copies the tree, so `proving.rbxl` inherits it.
- A harness case keeps the two numbers equal.

### M2: a held resident now answers the new verdict `"held"`
I chose a new `"held"` over reusing `"gone"`, because `"gone"` means the body no longer exists.
- `CrowdService.luau:2054` returns `"held"`. The Verdict type at line 205 has the new member.
- `StrikeTally.luau:55` drops `"held"` just as it drops `"gone"`, so there is no hit entry, no word, no glint and no ×N.
- **Harness.**
  - `tests_l1b_crowd.luau` checks that the verdict is `"held"`, then puts the hit through StrikeTally and expects 0 entries, 0 enemies and 0 dealt.
  - `tests_l1b_w4_crowd.luau` is relabelled.
- **Mutations.** Two: CrowdService answering `"blocked"` again, and StrikeTally booking a hit on a held resident. Both are caught.

### M3: each stage can set its own `gateSeconds`; 0 closes in the trigger's tick
**StageFlow**
- `Types.LevelStage.gateSeconds: number?` and `StageFlow.Stage.gateSeconds` are new.
- Plan copies the value through (`StageFlow.luau:1655`).
- Validate refuses a value that is not a number, under 0, or infinite (line 1428).
- `gate(plan, state, index, now, rules)` at line 1789 uses the stage's value, or `rules.gateSeconds` when the stage has none.
- In Advance (line 1943), the travel/armed row no longer returns after `gate`. It sets `step = "gate"` and continues into the countdown row. With a countdown of 0, the trigger tick therefore gives `gate close wave`, or `gate rearm` when nobody is standing.
- In Skip, all three entries into a countdown go through the new `entered` (line 1820), which closes in the same batch when the countdown is 0.

**No countdown text at 0.** A countdown of 0 is never broadcast as phase `gate`, so CombatHud needed no change.

**Harness**
- New `L1C.gateTests` covers:
  - Validate accepting 0 and 1.5, and refusing −1, `"3"`, NaN and ∞;
  - Plan carrying the value;
  - the trigger tick giving `gate close wave`;
  - `gate rearm` when the fallen lie on a clear field;
  - a stage's own 1.5, and the rules' 3 when a stage has none;
  - N and B into a camp of 0, from the road and from `armed`.
- `planTests` checks that the shipped Chief's Clearing has `gateSeconds` 0.
- Two shipped-data cases were updated for the 0-second clearing:
  - `tests_l1.luau` "every action is one WaveService executes": the expected countdown is now the stage's own.
  - `tests_l1b_w4.luau` "N through the approaches": now `move gate close wave`.

**`check_stage_mirror.py`**
- The stage rows carry `gateSeconds`, in both the Python and `stage_mirror.luau`.
- Two new REFUSALS: a camp's gateSeconds of −1, and of `"3"`.
- **`mirror_mutants.py`**: five new "L1c M3" mutants, all caught. All 96 anchors are still unique.

### code m2: a check that `GROUND_AIMED` matches the server's ground abilities
- `run_harness.py` adds `source_reading()`, which reads two lists from source text into `FIXTURES.source`:
  - InputController's `GROUND_AIMED`;
  - every AbilityService mechanic with `target = "ground"`.
- It also reads the project's zoom cap.
- `L1C.sourceTests` requires both lists to be non-empty and equal. Today both are `arrowRain, bladeStorm, leapSmash, stormCoil`.
- The zoom cap must equal `camera.maxZoom`.
- `mutate.py` copies InputController, AbilityService and `combat.project.json` into each mutant root. Three mutants cover these checks, and all are caught.

### code m3
This is for docs only, and the lead routes it to docs-keeper. I made no code change.

### data m2: the mirror's maxAlive case
- `boss_room_full` (`check_stage_mirror.py:207`) no longer adds bodies. It sets C's stage `maxAlive` to Normal's resident count, which is 10 today.
- The comparison also gained a rule (line 1818, `must_refuse`): every broken copy in REFUSALS and L1B_REFUSALS must be refused, not just refused the same way on both sides.
  - Without it, a two-sided mutant can never go red, because "alike" compares only the two booleans.
- **Two-sided mutant, run on a scratch copy.** I disabled the maxAlive rule in both `StageFlow.luau:1238` and `sim_range.py:5644` (`>= cap + 999999`). Result: `CHECK: FAIL (1)`, "forestRoad, the boss room's residents at its maxAlive: accepted on both sides".
- The unmutated scratch copy passes, and all 24 + 64 refusal cases are refused.

## Gates

| Gate | Result |
|---|---|
| Harness (worktree, main's `luau.exe`) | `HARNESS: PASS (2,455 checks)`, on the data agent's `gateSeconds: 0` |
| `mutate.py ... "l1c"` | Baseline PASS; **33 run, 0 not caught**: the 16 original l1c entries, re-aimed at the new text, plus 17 "l1c fix" entries |
| `mirror_mutants.py --only "L1c M3"` (scratch copy) | 5 of 5 caught |
| `check_stage_mirror.py` on a scratch copy with sim_range's name clash renamed (see below) | `CHECK: PASS` |
| `check_stage_mirror.py` in the worktree | **Crashes in sim_range** (data agent's file, see below) |
| `py tools/check_compile.py` | PASS, 158 files |
| `stylua --check` and `selene` on the six changed sources | clean |
| `luau-lsp analyze` over `src/combat` and `src/shared` | clean |
| `rojo sourcemap` / `rojo build combat.project.json -o <scratch>` | OK |

`luau-lsp` ran with `--definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.combat.json`, and the sourcemap was regenerated first.

## For the data agent (`tools/sim_range.py`)

1. **Blocking: `LevelRun.entered` is two things.**
   - The new method `def entered(self, index, t)` is at line 7968.
   - The attribute `self.entered = False/True` is at lines 6754, 7754, 7757 and 8275 (the close-grace mirror of WaveService's `run.entered`).
   - The attribute shadows the method. Every skip into a countdown then fails with `TypeError: 'bool' object is not callable` at line 8213, and `check_stage_mirror.py` crashes.
   - Fix: rename the method, for example to `skip_into`, at its `def` and its three call sites (8154, 8187, 8213). With that rename on a scratch copy, the mirror passes.
2. The `LevelWorld` docstring at line 6667 still says a held group answers `"blocked"`. It is now `"held"`. This is wording only; sim_range returns no verdict.
3. The rest of the sim_range mirror already matches the Luau:
   - per-stage `gateSeconds` in `plan_level` and `level_problems`;
   - the Advance fall-through;
   - the skip closing at once.

## For the lead

**A theoretical per-frame loop.** In a camp with a 0-second countdown, Advance could emit `gate rearm` on every tick. That needs both:
- `fallen` set while the field is clear, and
- a standing root on the trigger at the same time.

`RunLost` requires every fighter to be down, so I believe this cannot happen, and it is the same rule as with 3 seconds, just faster.

**Reset is off in the combat place only.** The hub's PLAYTEST step "Esc → Reset Character" (`docs/PLAYTEST.md:7179`) is in the hub and is unaffected.

## What to check in Studio (`proving.rbxl`)

1. Esc menu: Reset Character is greyed out.
2. Walk down leg 2 toward the north gate and turn the camera back and across. No ambusher should be visible through the opening. In the last 3.5 studs before the gate, the camera comes in to the head; check that this is not jarring.
3. Step through the gate. It should shut at once, with no "Gates close in" text, and the flanks should rush in the same moment.
4. Stand in the gatehouse walk and cast Arrow Rain or Storm Coil over the south wall onto the posts. No "BLOCKED" should appear.
5. Double-jump into the gate's opening and dash back out. The camera should not open up over the clearing.
