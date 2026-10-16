# L1c second fix round: code agent report (2026-10-16)

Worktree `C:\Users\benja\Desktop\tycoon-p5b`, branch `l1c-fix2`. Nothing is committed, every file is LF, and `tycoon-p5` was not touched. All gates are green. That includes the harness: F2 is now fixed in code, per the lead's ruling (code option a).

## Files changed

**Game code**
- `src/combat/server/Services/StageFlow.luau`:
  - adds `Zone.ceiling`, `Zone.lanes` and the `Lane` type;
  - adds `StageFlow.Ceiling`, `StageFlow.Lanes` and `StageFlow.GateNudge`;
  - `Plan` sets the new fields, and `triggered` reads `zone.ceiling`.
- `src/combat/server/Services/WaveService.luau`:
  - `runFloors` carries `ceiling`;
  - `moveFighters` nudges a fighter who stands in a gate lane at the close.
- `src/shared/Types.luau`: adds `RunFloor.ceiling: number?`.
- `src/shared/WallClip.luau`: adds `Rect.ceiling: number?`; `holds` uses it.
- `CombatUIController.applyFloors` copies and compares `ceiling`; `CameraController.SetFloors` passes it on.
- `src/combat/server/Services/WeaponService.luau` (F4):
  - `strike` returns `(killed, verdict)`;
  - `Strike`, `chainFrom` and the Chain Gun ray now walk their targets through StrikePick.
- **New file:** `src/combat/server/Services/StrikePick.luau`, the pure target loop, so the harness can test it.

**Tools**
- `tools/sim_range.py`, per the lead's routing: new `GATE_SIDES`, `gate_lanes` and `gate_nudge`; plan zones carry `"lanes"`; `on_close` nudges; new `gate_nudges` counter.
- `tools/check_stage_mirror.py`.
- `tools/crowd_harness/`: `tests_l1c.luau`, `tests_l1b_crowd.luau`, `run_harness.py`, `mutate.py`, `mirror_mutants.py`, `stage_mirror.luau`.
- `sourcemap.combat.json` is regenerated.

## F1 + F3 (fix a): a walled camp triggers and holds the camera up to its fence top

`StageFlow.Ceiling(camp, triggerHeight): number` returns:
- `fence.height` for a locking camp whose fence is a finite number taller than `triggerHeight`. Camp C gets 64.
- `triggerHeight` (30) for everything else.

`triggered` now accepts a root with `-triggerBelow <= rootY - floorY <= zone.ceiling`. Checkpoints still use `triggerHeight`.

The client gets the ceiling through `RunFloor.ceiling` into `WallClip.Rect.ceiling`. `holds` uses it, and falls back to `clip.height` when it is nil, NaN or infinite. The Python mirror is `sim_range.trigger_ceiling`.

## F2: the gate-lane nudge (code option a, the lead's ruling)

**`StageFlow.Lanes(camp, inner, fence): { Lane }`**
- One lane per gate of a locking camp.
- A lane is the gate's opening, limited to `inner`'s span. It reaches from the fence's outer face to `inner`'s edge on that side.

**`StageFlow.GateNudge(zone, position, rules): Vector3?`**
- It applies to a root that is in a lane and whose height above the floor is between `-triggerBelow` and the camp's ceiling.
- It returns the nearest point of `inner` along the gate's inward normal. The other coordinate and the height stay the same.
- Otherwise it returns nil, and the fighter goes to `entry` as before.

**`WaveService.moveFighters`**, at the close itself (not in the grace re-move):
- When `GateNudge` returns a point, it shifts the character with `PivotTo(GetPivot() + offset)`, which keeps facing and velocity.
- It writes no `Placed` attribute, because the client drops its speed on `Placed`.
- It calls `WeaponService.ForgetMotion`, the same as `ArenaService`'s moved hook does.
- It marks the fighter `entered`.

**Mirror**
- `sim_range.on_close` nudges the same way.
- `check_stage_mirror` compares:
  - zone rows, which now include `lanes`;
  - `StageFlow.GateNudge` against `sim_range.gate_nudge`, in 300 cases on a grid around both lanes of C (along the opening, across the normal, and six heights).
- `py tools/sim_range.py --levels-only --level forest --check` passes with the nudge in. The data agent may want to re-measure BALANCE: the start of the fight is now 3 studs inside the gate instead of at the entry.

## F4: held residents are skipped

**StrikePick**
- `Seeds<C>(eligible: {C}, cap: number, land: (C) -> boolean): ({C}, number?)`
  - It strikes candidates until `cap` of them have landed. `math.huge` means every one; 0 or NaN means none.
  - It returns the landed candidates and the index where the cap was spent.
- `Next<C>(nearby: {C}, taken: (C) -> boolean, land: (C) -> boolean): C?`

**WeaponService**
- In `Strike` and in the Chain Gun ray, `land` returns `verdict ~= "held"`. Caps are `math.floor`ed, as the old loop bounds were.
- In `chainFrom`, a held body is struck once (which does nothing) and recorded in a local `passed` set. It never goes into `hit`, which is the exclude set a lasting ability keeps across its ticks.
- Plain swings, cones and projectiles still let a held body take a cap slot. They draw no links, so I left them as they were.

## Stale `mutate.py` entries (the lead's extra item)

Both entries now point at the current code, with the same intent:
- **"review: a removed body is booked as a hit of 0"** (TALLY): replaces `if verdict == "gone" or verdict == "held" then` with `if verdict == "held" then`.
- **"l1: the countdown is not gateSeconds"** (FLOW): replaces `\t\telse rules.gateSeconds\n` with `\t\telse 1\n`, so it breaks the `levels.gateSeconds` fallback.

**Stale-text check over every entry.** I ran `mutate.py`'s definitions without its runner and counted each entry's text in its file:
- **788 entries, 0 stale, 0 missing files.** A full run can start.
- Two of my new texts had first matched twice. I reworded `Lanes`' guard and `GateNudge`'s height test so that every entry's text occurs exactly once.

## Gates

| Gate | Result |
|---|---|
| `run_harness.py <p5b> <main>\tools\bin\luau.exe` | **PASS, 2,489 checks** |
| `mutate.py` in this worktree (mutant root `tycoon-p5b\tools\crowd_harness\mutant`), `review: a removed body is booked` | 1 run, 0 not caught |
| same, `l1: the countdown is not gateSeconds` | 1 run, 0 not caught |
| same, `l1: the trigger` | 4 run, 0 not caught |
| same, `l1b: reach ignores` | 1 run, 0 not caught |
| same, `l1c` (16 old, 17 fix, 20 fix2) | **53 run, 0 not caught** |
| `check_stage_mirror.py --luau ...` | CHECK: PASS (Ceiling 12 compared, GateNudge 300 compared, Plan 8 compared) |
| `mirror_mutants.py --only "L1c"` | 12 of 12 caught (M3 ×5, F1 ×4, F2 ×3); all 103 entries' texts unique |
| `sim_range.py --levels-only --level forest --check` | PASS |
| `check_levels.py` | CHECK: PASS |
| `check_compile.py` | PASS, 159 files |
| `stylua --check` on the 8 changed sources and `stage_mirror.luau` | clean |
| `selene` on the 8 changed sources | clean (`stage_mirror.luau`'s 2 injected-global errors were already there) |
| `luau-lsp analyze` (definitions file, regenerated `sourcemap.combat.json`) over `src/combat` and `src/shared` | clean |
| `rojo build combat.project.json -o <scratch>` | OK |

## Harness cases (`tests_l1c.luau` unless noted)

**`marginTests`.** The line-93 case is replaced by:
- a walled rectangle (ceiling 64) holds a root at 33 and at 43;
- exactly 64 is inside, and 64.01 is cut;
- a rectangle with no ceiling uses `height`;
- a NaN or infinite ceiling counts as none;
- the ceiling is measured from the rectangle's own floor.

**`ceilingTests`**
- The edge cases of `Ceiling`.
- Shipped C's ceiling is 64, and every other camp's is 30.
- A root in the north gate's opening, at 30.5 to 64 above the floor, triggers C. One above 64 does not.
- The requested case: a root 33 to 43 above C's floor, inside the fence, keeps the whole boom on 36 headings.

**`entryTests` (F2, the new rule)**
- A root anywhere on C's north trigger line, at 3, 33 or 43 above the floor, closes the gate in that tick.
- The close moves it only along the inward normal, by at most `fenceThickness + closeInset` (3.0) + 0.05. X and Y stay the same, and the root ends inside `inner`.
- These go to the entry or are not nudged:
  - a root in the fence band beside the opening;
  - a root above the ceiling or below `triggerBelow`;
  - a root half a stud out on the road.
- A root in the inset strip in front of the gate is nudged onto `inner`'s edge.
- The east gate nudges along −X, keeping Z and height.
- An open camp has no lanes.
- `Lanes` limits a too-wide gate to `inner`'s span, and skips an unknown side or a NaN width.

**`pickTests` (F4)**
- `Seeds` and `Next` over mixes of held and taken bodies.
- A cap of 0 or NaN.
- The index where the cap is spent.
- The reviewer's Storm Coil over held bodies makes no links.
- In `tests_l1b_crowd.luau`, the same is checked against the real `CrowdService.Damage`.

## New mutations (`L1C_FIX2_MUTATIONS`, 20, all caught)

- **F1, 7:** Plan, the trigger, the locks, low and finite checks in `Ceiling`, and WallClip ignoring or misreading the ceiling.
- **F4, 6:** the cap, seeds, jumps, taken bodies, cap 0, and the spent index.
- **F2, 7:**
  - the root is put on the fence's face;
  - an east gate moves Z;
  - the height band is ignored;
  - the lane runs the whole side;
  - the lane starts at the floor's edge;
  - the lane is not limited to `inner`;
  - `Plan` gives no lanes.

## What to check in Studio (`proving.rbxl`, press N to reach the clearing)

1. Inside the Chief's Clearing, do a late double jump from the floor and from a 3.5-stud cover block, and cast Leap Smash from a jump. The camera must never snap into the head.
2. Double-jump in the north gate's opening, right at the line. At the top of the jump the camp shuts, and you get no glimpse of the flanks from outside.
3. Walk, run and jump through the north gate. You should be nudged at most 3 studs straight in as it shuts, with no sideways jump. A jump should keep its arc, and the view should not turn.
4. Before the close, cast Storm Coil over GatehouseWallS from the gatehouse walk. No bolts should be drawn to the hidden ambushers.
