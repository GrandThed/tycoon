# L2 W3 third fix round (one agent, every file), 2026-10-19

Branch `l2-w3-fix2` in `tycoon-p5b`. Nothing is committed. Rulings: `docs/prompts/l2-w3-fix3.md`; findings:
`docs/prompts/l2-w3-review/fix-diff.md` (fd-m1, fd-m2, fd-s1, fd-s2). Numbers: `docs/BALANCE.md` "L2 W3 third fix
round".

## Files changed

- **Code:**
  - `src/shared/WorldReact.luau`
  - `src/combat/server/Services/LevelService.luau`
  - `src/combat/server/Services/WeaponService.luau`
  - `src/combat/server/Services/LevelGeometry.luau`
  - `src/combat/client/Controllers/InputController.luau`
- **Data:**
  - `src/shared/Config/Combat.json`
  - `src/shared/Layouts/Levels/ForestRoad.json`
- **Tools:**
  - `tools/check_levels.py`
  - `tools/check_levels_mutants.py`
  - `tools/check_stage_mirror.py`
  - `tools/sim_range.py`
  - `tools/crowd_harness/{tests_l2w3.luau, run_harness.py, mutate.py, mirror_mutants.py}`
- **Docs:** `docs/BALANCE.md` (new section), this report.

## fd-m1: the island off the pond's grid

**Data.** `ShrineIsland` moves from z 128 to **z 128.5** (z 120.5..136.5). The chest stays at z 128.
- Both z faces are now mid-row: z 120.5 in row 3 (116..122.67) and z 136.5 in row 6 (136..142.67).
- The x faces (−408, −392) were already mid-column: column 4 is −409.82..−403.27, column 6 is −396.73..−390.18.
- Column 5's rows 4 and 5 still lie wholly under the island. Rows 3 and 6 are part-covered and built. So there are
  still 136 pieces and 252 Parts.

**Gate.** New check_levels line in `check_ice`, `ice_coplanar`: no face of a built ice piece lies within
`levels.react.ice.inset` of a face of the same facing on a solid.
- The piece is taken as frozen, `thickness` deep under its top.
- The solids are every colliding block, camp piece and secret.
- A face on the very plane always counts.
- I took the inset (0.05) as the threshold because it is the seam Q6 judged enough against the shimmer. A bare
  "coplanar to 1e-6" would pass a face 0.01 off, which still z-fights at range.

Mutants:
- red: the island back at z 128 (today's island: the 2 pairs the probe found);
- red: the island at x −401.818 (its west face on a column line: "check x too");
- green control: z 128.05 (the faces the inset off the line).

**Island rules re-checked (all PASS):**

| Rule | Before | Now |
|---|---|---|
| ICE_MARGIN | ShrineSignPad 102.0 away, +21.5 | **102.5 away, +22.0** (the worst reach is still Impale Dash held in the air, 80.6) |
| The chest's trigger (a, d) | 2.5 to spare each side | z 122.5..133.5 on z 120.5..136.5: **2.0 north, 3.0 south**; x unchanged, 2.5 |
| The chain (h) | 16 cells | 16 cells (4 by a bank, 10 by the island), 136 pieces |
| The crossing | 9 swings, 9.0 s / 5.8 s, 108.7 studs, 39 cells | unchanged |

d-m3's two tower mutants moved 0.5 south with the island, so their labels (92 and 99 south) stay true.

## fd-m2: a sheet thinner than a root, and the falling body led

**Config.** `levels.react.ice.thickness` 4 → **1.9**.

**The ruling, in check_levels.** The floor-depth line no longer judges the frozen sheets: `check_kill_height`
gains `sheets_apart`. It still judges every other block of the frozen layout. A new sheet line in `check_ice` holds
`least < thickness < ROOT_TALL`:
- `least` is the fastest fall onto a sheet, moved in one physics step (`PHYSICS_HZ` 240). That fall is the faster of:
  - the slam's dive, 140;
  - a free fall from the jumps' apex over the highest top reached on the frozen layout to the lowest sheet: 68.8 studs,
    164.3 studs/s.

  So the bound is **0.685**.
- `ROOT_TALL` is 2, the R15 root. Below it, a root never lies wholly inside a sheet.

Mutants: 0.6 red / 0.7 green; 2 red; 4 red (d-m6's value); `slamFallSpeed` 480 red. The old d-m6 case is re-aimed:
Road2 2 deep with nothing under it is red, and `ice.thickness` 1 is now a green control on the floor line.

**Server lead.**
- `WorldReact.FallDrop(fallSpeed, lag, gravity, fastest): number`
  - Returns fall × lag + g × lag² / 2.
  - The fall is clamped to [0, fastest].
  - Gravity under 0 counts as 0.
  - A lag ≤ 0 or any number that is not finite gives 0.
- `WorldReact.BodyBox(position, right, size, hipHeight, drop: number?)`: `drop` lowers the feet and keeps the top. The
  box then spans the body from where the server sees it down to where its own screen will have it.
- `WeaponService.FallSpeed(player): number?`
  - `trackAir` sets it on every sample: nil when that sample found the body standing (`stood == position`, the same
    footprint verdict as `stood`), else the measured fall (max of replicated and positional, ≥ 0).
  - It is cleared with no root, by `resetAir` and by `ForgetMotion`.
- `LevelService` `bodies()`:
  - `drop = FallDrop(WeaponService.FallSpeed(p), Tuning.CommitLag(shooting, p:GetNetworkPing()), Workspace.Gravity,
    Tuning.FastestMove(config))`, or 0 while standing;
  - it hands the drop to `BodyBox`.
  - `LevelService` now requires `WeaponService`. There is no cycle: nothing `WeaponService` requires reaches
    `LevelService`.

**Harness** (`fix3Tests`, `fix3WiringTests`):
- FallDrop's terms, cap, signs and non-finite inputs; BodyBox's drop.
- The review's case: feet −1.0 at 19.8 with a lag of 0.1 holds (led 2.96); unled it does not.
- A teammate walking off the bank, judged on the shipped sheet, sink and commit lag at a 0.15 s round trip:
  - led: **0** of his root is in the cell when it turns solid on his screen;
  - unled: **1.9**.
- Off the bank or the frozen edge, any round trip up to 0.3 s, led or not: the root is never wholly inside.
- Off the frozen edge at 0.15 s: at most **0.21**, his last standing frame, which no lead reaches.
- The applying lines are read as text.

## fd-s1: the phone asks the server's question

`iceOnAuto(cfg, variant, rig, heading)`:
- It asks `AirSwing.Judge(origin, rig.root, rig.humanoid)` (lag 0, the server's footprint question) and returns false
  on `not allowed or inAir`.
- Both `autoIceStrike` calls hand on `inAir` (`autoIceStrike` gained an `airborne` argument).
- `MovementController.IsAirborne` is no longer asked there.
- The judge runs before the water walk. That costs the AirSwing probe's five short rays a frame, while a phone holds an
  ice family with no body in reach.

## fd-s2: no seam where two ice blocks meet

`LevelGeometry.meetsIce` decides whether a cell's side on its water's face meets another ice block over its whole
length:
- that block's opposite side lies on the same plane (to SEAM);
- its top is the same;
- its span along the face covers the side.

Such a side is not inset. `Pieces` passes `iceCells` every ice block as built.
- A block never meets itself unless it is too thin for a cell to be built, so the block is not excluded.
- Mirrored in `sim_range.ice_meets` / `ice_cells`.
- Forest Road: the Creek's 3 last south sides and the Pond's first-row north sides in columns 4 to 6 are now whole.
- Columns 3 and 7 meet the Creek over 0.18 studs only, so they keep the inset.

**Fill line.** It now allows a rim only along the inset sides. check_levels has its own statement of the rule,
`ice_side_met`, so a mirror that insets a met side leaves a hole: mutant red. The control (the Pond 0.5 lower, the two
no longer meeting) is green.

**Stage mirror.** Two new views:
- the touching pools at inset 0.5;
- pools that meet in part, at another top and at a corner.

That makes 9 views box by box. Two Python-alone mirror mutants (ignore the top; a side met in part) are red, and three
Luau mirror mutants are caught.

**Harness:**
- insetTests: touching pools meet with no seam. A neighbour met only in part keeps the inset, one meeting a row whole
  frees just that cell, and one at another top keeps the inset.
- realTests: 72 sides by the faces, 6 of them met; the creek's mouth is checked by name.

## Gates

| Gate | Result |
|---|---|
| Harness | `HARNESS: PASS (3,154 checks, tycoon-p5b/tools/crowd_harness)` (was 3,127) |
| `mutate.py "files:WorldReact.luau,LevelGeometry.luau,LevelService.luau,WeaponService.luau,InputController.luau,Combat.json,ForestRoad.json"` | baseline PASS (3,154); **337 run, 0 not caught** (38 of them new) |
| Stale-text count, all entries | 0 of 1,189 (9 re-aimed, 38 new) |
| `mirror_mutants.py` | 119 of 119 caught (3 new, 2 re-aimed) |
| `check_stage_mirror.py` | CHECK: PASS (ice cells: 9 views) |
| `check_levels.py` | PASS |
| `check_levels_mutants.py --only "W3"` | MUTANTS: PASS: 92 data cases (67 red, 25 green) and 7 stage-mirror cases, the shipped data green |
| `py -3.12 tools/sim_range.py --check` | CHECK: PASS, 523 PASS lines, 0 FAIL, Python 3.12.10 64-bit (crossing 9 swings, 9.0 s / 5.8 s) |
| `check_compile.py` | PASS, 174 files |
| `rojo build` (combat and default, to scratch) | both build |
| stylua (the 5 src files), selene | clean; 0 / 0 / 0 |
| luau-lsp | exit 0: the combat sourcemap over `src/combat` + `src/shared`, the default one over `src/client` + `src/shared` |

## For the lead

- **INTERFACES:** record these items.
  - `WorldReact.FallDrop`, and `BodyBox`'s fifth argument `drop`.
  - `WeaponService.FallSpeed`.
  - `LevelService` → `WeaponService`, the new require.
  - `iceOnAuto`'s rig argument and `autoIceStrike`'s `airborne`.
  - `LevelGeometry.meetsIce`, and `sim_range.ice_meets`.
  - check_levels: the coplanar and sheet lines, `sheets_apart`, `PHYSICS_HZ`, `ROOT_TALL` and the fill line's rim rule.
  - `thickness` 1.9.
  - The island at z 128.5.
- **Known limits:**
  - The frost ghost (ReactFx) still judges teammates unled. For a teammate mid-fall it can show ice the server holds;
    it drops at the answer's grace.
  - A body's last standing frame cannot be led. Off the frozen edge at a 0.15 s round trip that frame can leave 0.21
    of a root inside a fresh sheet. The 1.9 thickness keeps it from being whole.
  - The sheet bound assumes 240 Hz physics.
  - fd-s2's rule needs the two sides to meet over a whole cell side. A neighbour that covers part of a side (Pond
    columns 3 and 7, 0.18 studs) leaves a 0.05 notch there, as Q6 did everywhere.

## What to check in Studio

1. **Network simulator (Studio's Network settings, 150 to 250 ms):**
   - Swing at the frozen edge and keep walking onto your own ghost: you stand on the new ice or fall through to the
     landing, never stick.
   - With two clients, B walks off the bank into the creek while A swings at it: the cell B falls through stays
     water, and B is never held in the ice.
2. **The island's south side, frozen from the pond:** with the cells beside the island frozen, look back north from
   over the pond. There is no flicker where the ice meets the island's grey face.
3. **The creek's mouth:** freeze across the creek-to-pond line. There is no grey seam across the crossing, and no
   shimmer is visible through the water there.
4. **A slam onto the 1.9 sheet** from the jumps' apex: you land on it, never through it. Also check the place's
   `Workspace.PhysicsSteppingMethod`: the bound assumes a falling character steps at 240 Hz.
5. **Phone on the bank's very lip**, Frost Hammer, auto-fire: no swing at the water while the footprint is off the
   bank, and the first swing from the lip freezes.
