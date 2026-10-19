# L2 W3 second fix round (one agent, all slices), 2026-10-19

Branch `l2-w3-fix2` in `tycoon-p5b`. Nothing is committed. Rulings: `docs/prompts/l2-w3-fix2.md` (Q5, Q6).

## Files changed

- **Code:**
  - `src/shared/WorldReact.luau`
  - `src/shared/Types.luau`
  - `src/shared/Config/Combat.json`
  - `src/combat/server/Services/LevelGeometry.luau`
  - `src/combat/server/Services/LevelService.luau`
  - `src/combat/server/Services/WeaponService.luau`
  - `src/combat/client/Controllers/ReactFx.luau`
  - `src/combat/client/Controllers/FrostFx.luau`
  - `src/combat/client/Controllers/InputController.luau`
  - `src/combat/client/Controllers/FeedbackController.luau`
- **Tools:**
  - `tools/sim_range.py`
  - `tools/check_levels.py`
  - `tools/check_levels_mutants.py`
  - `tools/check_stage_mirror.py`
  - `tools/crowd_harness/{tests_l2w3.luau, run_harness.py, mutate.py, mirror_mutants.py, stage_mirror.luau}`

## Q5: a lodged body

**Rule.** A swing made in the air freezes nothing, on the server, in the ghost and on the phone. No cell freezes
while a player's body stands in it.

**Pure part, in WorldReact:**
- `Strike.airborne: boolean?`.
- `SwingStrike(variant, step, origin, heading, airborne: boolean)`. The new argument is required, so a caller
  that leaves it out fails luau-lsp.
- `Chills` is false when `fx.airborne == true`.
- `BodyBox(position, right, size, hipHeight): Box`:
  - in plan, the box round the root's footprint turned by `right`;
  - in height, from the feet (`hipHeight + size.Y/2` under the root) to as far again over it.
- `Holds(box, bodies?, sink?): boolean`:
  - the body and the cell overlap in plan, strictly;
  - the feet are more than `sink` under the cell's top;
  - the body's top is over the cell's bottom.
  - A non-finite body or cell holds nothing. With no sink (nil, under 0, or not finite), no body is judged.
- `Freeze(cells, element, fx, reachDown, ahead, bodies?, sink?)` skips a held cell. A later swing freezes it once
  the body has gone.
- `IceSink(ice): number?`.

**Which "airborne".** It is the swing's own SwingGate verdict at its origin: `airSwing` from `SwingGate.Judge` in
`WeaponService.OnAttack`, the one-swing-per-jump question. On the client the same verdict comes from
`AirSwing.Judge`. I did not use `shooter.airborne`: its single centre ray reads airborne when a player stands on the
bank's lip with the root over water, and that would refuse the crossing's first swing.

**Server:**
- `OnAttack` → `resolveMelee(..., airSwing)` → `SwingStrike(..., airSwing)` → `finish{ airborne = swing.airborne }`.
  `airborne` is never broadcast.
- `LevelService.freeze` reads `IceSink`, and hands `Freeze` every player's `BodyBox` (a new local `bodies()`
  that loops over `Players:GetPlayers()`). It warns once and judges no body if the sink is missing.

**Client:**
- `PredictedSwing.airSwing` is set from `swingAirborne`. FrostFx and the early hitbox pass it to `SwingStrike`.
- `ReactFx.PredictFreeze` puts no ghost on a held cell. It reads `ReactFx.Bodies()` lazily, only once a cell has
  chilled.
- `iceOnAuto` (the phone) skips a held cell the same lazy way. Its strike is `SwingStrike(..., false)`, because it
  already returns while airborne (c-m4). This only removes swings.

**Config:** `levels.react.ice.sink` = 0.5. Feet less than 0.5 under the top count as standing on the ice: a
Humanoid's root rides a hair low, and a sink of 0 would hold the cell beside a player on the ice's edge.

**Mirror:** `sim_range.ice_crossing` passes its walker's body (ROOT_FOOTPRINT 2×1 at its widest turn, ROOT_HEIGHT)
to `ice_holds`. check_levels models no swings, so it needs no mirror.

## Q6: edge shimmer

**Rule.** A cell face that lies on its water block's own face is built `inset` inside it. That covers the first
and last column and row of each block, including the faces shared with a touching ice block.

**LevelGeometry:**
- `iceCells` places each cell by its index in the grid.
- The cover test still reads the whole cell.
- A cell the inset leaves with no width is not built. Without that rule, `Pieces` would refuse the whole level over
  a Part of size ≤ 0.
- `IceOf`: `inset` absent = 0; a value that is not a finite number ≥ 0 is refused, and the water then has no cells.

**Config:** `levels.react.ice.inset` = 0.05.

**sim_range.ice_cells** mirrors it. Each cell now carries `box` (as built) and `cell` (its whole place in the grid).

**check_levels:**
- `ice_holes` (the fill line) requires the block shrunk by `inset`, so it allows that rim and nothing more. A
  mutant that insets twice goes red.
- The (h) chain and `sim_range.ice_crossing` join cells and banks by `cell`, because a body walks across the seam.
- New line `Combat.json levels.react.ice's inset and sink`:
  - inset from 0 to `ICE_INSET_MOST` 0.25 (a seam, not a gap);
  - sink over 0 and under `ICE_SINK_MOST` 2, the R15 HipHeight, so the colliding root never lies inside the ice.
- `ICE_KEYS` gains inset and sink.

**New mirror gate.** `check_stage_mirror` now compares `LevelGeometry.Pieces`' ice boxes with `sim_range.ice_cells`
box by box. Until now only the count was compared. It runs on 7 views:
- every shipped level layout (not the arena);
- Forest Road with an inset of 0, 0.5, none written, and −1;
- two touching pools plus one 0.08 wide.

**Unchanged:** `frozen_layout` keeps the whole block (docstring updated). Forest Road still has 136 cells and 252
Parts. The chain is 16 cells. The crossing is 9 swings, 9.0 s for a human and 5.8 s ideal, over 109 studs with 39
cells frozen.

## Gates

| Gate | Result |
|---|---|
| Harness | `HARNESS: PASS (3,127 checks, …tycoon-p5b\tools\crowd_harness)` (was 3,064) |
| `mutate.py "files:WorldReact,LevelGeometry,LevelService,WeaponService,InputController,FrostFx,FeedbackController,ReactFx,Combat.json,Types"` | 308 run, 1 not caught (thin-water skip). Test fixed (now asserts the level still builds), then `mutate.py "l2w3 fix2"`: 45 run, 0 not caught |
| Stale-text count, all 1,151 entries | 0 (12 re-aimed, 45 new) |
| `mirror_mutants.py`, all | 116 of 116 caught (4 new) |
| `check_stage_mirror.py` | CHECK: PASS (ice cells: 7 compared) |
| `check_levels.py` | PASS |
| `check_levels_mutants.py --only "W3 fix2"` (14 cases), `"d-m1"`, `"W3 h"`, `"W3 L2-53"` | MUTANTS: PASS each |
| `py -3.12 tools/sim_range.py --check` | CHECK: PASS (523 PASS lines, 0 FAIL) |
| `check_compile.py` | PASS, 174 files |
| stylua, selene (the 10 Luau files) | clean, 0/0/0 |
| luau-lsp | exit 0 on both runs: combat sourcemap over `src/combat` + `src/shared`, default over `src/client` + `src/shared` |
| `rojo build` (combat and default, to scratch) | both build |

Process notes:
- `check_compile.py` needed `tools/bin/luau-compile.exe`. I copied it from the main checkout; `tools/bin` is
  gitignored.
- `mutate.py` gained a `files:<a>,<b>` filter: the mutations of the files whose path ends with one of those names.
  It is meant for a fix round's filtered run.

## Assumptions

- The body is the root Part's box from the feet up, and an R15's legs count. The sink of 0.5 lets a standing body
  freeze its neighbour.
- A body whose feet are more than 0.5 deep stops the freeze. Shallower than that the legs can end up in ice; I
  expect the Humanoid to stand back up onto it, because R15 limbs do not collide (not verified in Studio).
- The server judges bodies by its replicated copies. The swinger's own copy may trail its fall by the ping. The air
  rule covers that swing on its own.
- Phone: c-m4 (`MovementController.IsAirborne`) is unchanged. The phone strike says grounded.
- The inset also opens a seam of 2 × inset (0.1) where the creek meets the pond. I expect it to be invisible from
  the camera and walked across without a dip; neither is verified in Studio.

## For the lead

- **INTERFACES:** record the new contract items:
  - `SwingStrike`'s fifth argument;
  - `Strike.airborne`;
  - `BodyBox`, `Holds`, `IceSink`, and `Freeze`'s `bodies` and `sink`;
  - `ReactFx.Bodies` and `ReactFx.IceSink`;
  - `PredictedSwing.airSwing`;
  - `levels.react.ice.inset` and `.sink`;
  - `ice_cells`' `cell`;
  - the new check_levels line and the check_stage_mirror comparison.
- **BALANCE:** no number moved. You may want a line noting the two new keys.
- **Known limits:**
  - Bodies are players only. Crowd bodies never reach the water.
  - A downed player's body counts.
  - The ghost judges remote players at their replicated positions, so it can differ from the server for a
    teammate mid-fall. The ghost then drops at the answer's grace.

## What to check in Studio

1. **Hammer (I), jumping at the frozen edge.**
   - Hop and swing over open water: no ghost, no ice, and you fall to the landing.
   - Swing on the ground at the edge: ghosts, then ice.
2. **Falling in with a swing in the first frames** (PC and phone): no ice forms round the body.
3. **A second player** (two clients) falls into the creek while the first swings at it: the cell the faller is in
   stays water, and the cells beside it freeze. Once the faller is rescued, the next swing freezes that cell.
4. **Standing on the ice's edge and swinging forward** across the whole crossing: no cell is ever skipped. If the
   ice ever stops one cell ahead of you, the sink is too small: tell me.
5. **Shimmer** on the creek's long sides, the pond's edges and the creek-to-pond seam, once frozen from one side.
   Also check that the 0.1 seam between the creek and the pond does not read as a crack.
