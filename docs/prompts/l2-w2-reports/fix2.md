# L2 W2 second fix round: report (2026-10-18)

Brief: `docs/prompts/l2-w2-fix2.md` (m1, m2, m3, s1). One agent, branch `l2-w2-fix2` in `tycoon-p5b`.
Nothing is committed.

## Files changed

- `src/shared/Types.luau`: `LevelCamp.fence.thickness?`, `RunFloor.fence?`, the `originWallChord` comment.
- `src/shared/WorldReact.luau`: `LeadHead`, `AimClear`, the `Cast` type, and `LEAD_STANDOFF` (0.5).
- `src/combat/server/Services/LevelGeometry.luau`:
  - new `FenceThickness`;
  - `Pieces` builds the fence, gates and barrier band from each camp's own thickness;
  - `Pieces` refuses a `fence.thickness` that is not a size above 0.
- `src/combat/server/Services/StageFlow.luau`: `Zone.fence`, and the trigger grows by it.
- `src/combat/server/Services/WaveService.luau`: `RunFloor.fence` is sent.
- `src/combat/server/Services/WeaponService.luau`:
  - `claimSlack` now also returns its speed and lag;
  - new `worldHit`;
  - `aimAllowed` calls `WorldReact.AimClear`.
- `src/combat/client/Controllers/CombatUIController.luau`: reads and compares `RunFloor.fence`.
- `src/combat/client/Controllers/CameraController.luau`: `SetFloors` grows each locking floor by its own fence.
- `src/combat/client/Controllers/InputController.luau`:
  - m3: streams take no bloom;
  - s1: the `worldParams` cache is kept in `rangeState`, and the range path watches players.
- `src/shared/Layouts/Levels/ForestRoad.json`:
  - camp C has `fence.thickness` 2.5;
  - GatehouseWallE and GatehouseWallW are 1.5 shorter at their south end, so they stay flush with the fence's new
    outer face.
- `tools/check_levels.py`:
  - `fence_thickness`, which delegates to `sim_range.fence_thickness`;
  - every fence, gate, barrier, fenced-rectangle and camera keep-out rule is now per camp;
  - new gate `check_origin_chord`;
  - camps are refused a `fence.thickness` that is not a size above 0.
- `tools/sim_range.py`: `fence_thickness`. Zones carry `fence`, and the trigger and scene walls use it.
- `tools/check_stage_mirror.py` and `tools/crowd_harness/stage_mirror.luau`:
  - new `fenceCases`, comparing `LevelGeometry.FenceThickness` with the Python (9 cases);
  - zone rows carry `fence`.
- `tools/check_levels_mutants.py`:
  - 8 data cases and 1 mirror case for m1;
  - five L1c sight cases re-aimed (see below).
- Harness:
  - `run_harness.py`: the aim source check reads the new lines, including the chord argument, plus `worldHit`'s
    body;
  - `tests_l1.luau` and `tests_l1c.luau`: per-camp thickness in the zone, piece and nudge checks;
  - `tests_l1_world.luau`: new group `fenceThicknessTests`;
  - `tests_l2w2.luau`: new group `leadTests` and a wiring check.
- `tools/crowd_harness/mutate.py`:
  - 5 stale entries re-aimed: the two trigger entries, "an open camp builds gates", and the two aim-ray entries
    (now on `lineClear`);
  - 13 new entries in `L2W2_FIX2_MUTATIONS`.

## m1: camp C's wall is 2.5 thick

- `LevelGeometry.FenceThickness(camp, default): number` returns the layout's `fence.thickness` when it is a positive
  finite number, else `levels.fenceThickness`.
- These all read it:
  - `Pieces`: the fence, the gates, and the barrier band (`max(barrier.thickness, fence)`, still 8 at C);
  - `StageFlow.Plan`: `Zone.fence` and the trigger;
  - `RunFloor.fence`, which the camera clip reads;
  - check_levels, sim_range and check_stage_mirror.

**What changes at camp C:**
- The fenced rectangle grows 1.5 outward on every side. The trigger, the camera clip and `GateNudge`'s reach all follow
  it.
  - The clip now keeps the boom 2.5 + 3.5 = 6 studs off the floor's edge.
  - The close's nudge now moves a root at most 2.5 + 2 = 4.5 on an axis (was 3).
- Both gates are 2.5 deep.
- `inner` (closeInset), the ceiling (64) and the barrier are unchanged.
- The gatehouse's east and west walls now end at z −28.5, flush with the fence's outer face. Left at z −27, they would
  have overlapped the fence and shared its gate-side face. That would z-fight.
- The part count is unchanged (114). TrailEnd still runs under the east gate.

**Re-check of L1c (check_levels, all green):**

| | Before | After |
|---|---|---|
| Sight margin, eyes | +1.57 | **+4.09** (305.51, −31.01) to brutal ambushE fodder |
| Sight margin, cameras | +2.73 | **+5.20** |
| Doorway (exempt eyes) | −2.53 | −0.87 |

- The close's nudge lands clear.
- The fence stands 64 against the highest camera of 60.49 + 3.
- The ceiling is 64 against the highest root of 46.5.
- Every gatehouse wall within 49.3 stands at 76.
- No outside camera sees in.

**New gate (check_levels "origin chord"):**
- `shooting.originWallChord` must be under the smallest size of every tall colliding piece. That covers blocks, every
  camp's generated fence strips at its own thickness, cover and secrets.
- "Tall" means the piece's top is over a standing head (root 3 + 1.5) on ground beside it: a floor, secret, cover or
  ground-look block within 1 stud of it, between 6 below its foot and its top.
- ForestRoad: 30 pieces, the thinnest CaveBrambleE at 2. On today's data, with fence 1, it reads "not: Camp_C_Fence_*
  1".
- The lobby rail (3 high) and the 4-high fences are low, so the gate exempts them.

**Mutants and source check:**
- `mutate.py` "fix2 m1: aimAllowed's chord is originPad" is caught by run_harness's source check. The check now reads
  `WorldReact.AimClear(anchor, lead, origin, config.shooting.originWallChord, worldHit)`.
- `check_levels_mutants` cases:
  - red: fence back at 1, chord 2.5, chord 6, a 1-stud wall 6 high, thickness 0, thickness "2.5", and sim_range's
    `fence_thickness` ignoring the camp's own value (the mirror case);
  - green controls: chord 1.9, and a 1-stud rail 4 high.

**Five L1c sight mutants were re-aimed.** The thicker wall widened their margins: "cameraClear 2", "inner fodder 2.4
off", "the 2a58134 post", "a brute again" and "sightMargin 2".
- Each now runs on L1c's own geometry through a new helper, `l1c_wall`, which puts back fence 1 and the old wall
  lengths. On it, check_levels reproduces +1.57 / +2.73 exactly.
- Each also has a twin on the shipped wall: cameraClear 0.5; fodder 4.5 off, with its coarse-grid control; fodder 3.5
  off (+0.75, under 1.5, seen from nowhere); and sightMargin 4.5.

## m2: honest origins on fast travel

- `WorldReact.LeadHead(head, velocity, speed, lag): Vector3` returns `head + velocity × lag`.
  - The velocity's magnitude is capped at `speed`, which is claimSlack's ring speed (itself capped at
    `Tuning.FastestMove`).
  - `lag` is `Tuning.CommitLag`.
  - So the lead never lies further from the head than the slack the distance test grants.
  - A velocity that is not finite, or not above 0, leads nowhere.
- `WorldReact.AimClear(head, lead, origin, tolerance, cast): boolean`:
  - First, `OriginClear` on the line from the head.
  - Otherwise, the same test from the carried head: the lead cut back `LEAD_STANDOFF` (0.5) short of the first solid
    on the way from the head.
  - **Assumption, beyond the ruling:** the cut-back keeps the carried head on the head's side of every wall. So a
    velocity claimed through a wall cannot be used to forge an origin beyond it. Without the cut, a modified client
    moving along a wall at walk speed could claim a velocity into the wall and buy up to speed × lag of reach through
    it.
- `aimAllowed` makes one `claimSlack` call for the distance test and the lead, then `AimClear`. The Studio warn (once
  per player) casts its own ray to name the wall.
- Harness (`leadTests`, 11 checks):
  - the lead's length and cap, and the not-finite, zero and endless cases;
  - the bend's honest origin from a head 6.5 behind: refused by the head's line alone, allowed by AimClear;
  - forged cases, all refused: a velocity through a 2.5 wall with the origin beyond it, the origin inside the wall, a
    lead claimed inside the wall, and a lead along the wall with the origin beyond it.

## m3 and s1 (client only, no harness reach)

- m3: `nextSpreadDegrees` returns 0 for `variant.continuous`. The capsule, the drawn flame (FlameFx) and the phone
  burn test (`reactOnAuto`) now share one line. The crosshair shows no bloom for streams. No server check assumes
  bloom (the server takes the sent direction), and neither simulator models it.
- s1: `worldParams` is cached in `rangeState.worldParams` and `worldStale`.
  - `invalidateCrosshair` marks it stale.
  - The range path now hooks `watchPlayer` and `forgetPlayer` (CharacterAdded, PlayerAdded, PlayerRemoving), as the
    mission path does.
  - `Destroy` already disconnects them.

## Gates (final code)

| Gate | Result |
|---|---|
| Harness | PASS, 2,835 checks (was 2,809) |
| `mutate.py`, filtered to entries in changed files | 387 run (StageFlow 221, LevelGeometry 104, WorldReact 50, WeaponService 9, InputController 3). The first run missed one, "an endless velocity leads": the test counted a NaN lead as "unmoved". The test now needs exact equality, and a rerun of the 50 WorldReact entries caught all 50. |
| Stale-text count, all 985 entries | 0 |
| `check_levels` | PASS |
| `check_levels_mutants --only` | PASS on fix2/m1, C1, margin, L1c, F1, M3, m2, m3, m4, s1, L2-37, d-M1 and L2-47: 119 cases ok, the fenceThickness mirror case included |
| `check_stage_mirror` | PASS (FenceThickness: 9 compared) |
| `py -3.12 tools/sim_range.py --check` (3.12.10) | PASS, 499 lines |
| `check_compile` | PASS, 172 files |
| stylua (sources) | clean |
| selene | 0 / 0 / 0 |
| luau-lsp, both sourcemaps | exit 0 |
| `rojo build combat.project.json` | builds |
| Line endings | LF |

- The harness `.luau` test files were not stylua-clean before this round either, so I left their format alone.
- No `mutate.py` entry covers the client's `RunFloor.fence` read (CameraController and CombatUIController are not
  loaded by the harness). I checked it by reading.

## For the lead

- **Contract additions:**
  - the layout key `fence.thickness`, which the brief named;
  - **`RunFloor.fence`** (number?), a new field on RunState's floors, needed so the camera clip grows camp C by 2.5.
  INTERFACES should list both.
- **PLAYTEST notes:**
  - At C's north gate the passage is 1.5 deeper. The close's nudge can move a root up to 4.5 studs.
  - A cast mid-dash at a bend should no longer be refused.
- `l1c-contract.md`'s gatehouse coordinates (WallE z −54..−27, WallW z −36..−27) are now −28.5 at the south end.
