# L2 W3 fix round: server agent (luau-engineer), 2026-10-19

Branch `l2-w3` in `tycoon-p5`. Nothing is committed. This report covers the server agent's rulings from
`docs/prompts/l2-w3-fix-round.md`:
- s-M1 with Q3, and Q2;
- c-m3: the server half and the pure function;
- s-m1 and d-m5;
- s-s2 (Validate), s-s3, and d-m1 (code).

It also covers the two client requests the lead relayed: the `iceAutoDegrees` type, and source checks on the
client's three `SwingStrike` calls.

## Files changed

- **`src/shared/WorldReact.luau`.** New and pure: `ICE_ATTRIBUTE`, `Reactive`, `SwingStrike`, `IceReach`, `IceLook`.
- **`src/shared/Types.luau`.**
  - The `LevelBlock.landing` comment now says any non-colliding block may carry one.
  - `RangeControlsConfig.iceAutoDegrees: number?` added (the client's request).
- **`src/combat/server/Services/LevelGeometry.luau`.**
  - `Length`, `IceOf` and `SizesOf` moved here from LevelService. `Overlap` is new.
  - `iceCells` skips a cell only when ONE cover holds the whole cell, edges included, to SEAM (d-m1).
- **`src/combat/server/Services/LevelService.luau`.**
  - `sizesOf` is `LevelGeometry.SizesOf` plus the warn.
  - `showIce` applies `WorldReact.IceLook`, both as built and when frozen.
  - `gripOf` and `CONST.GRIP_LOOK = "ground"` (Q2).
  - `React` counts nothing before it knows the element (s-m1).
  - `freeze` reads `WorldReact.IceReach`.
  - The reactive list is filtered by `WorldReact.Reactive`.
  - The file holds no ice attribute name of its own.
- **`src/combat/server/Services/StageFlow.luau`.**
  - Validate: the landing line is now `block X has a landing and collides`. New ice line:
    `block A and block B are ice and overlap`.
  - `Plan.waters` = every `collide == false` block that has a landing.
  - `Landing` and `FallLanding` take `stood`.
- **`src/combat/server/Services/WaveService.luau`.** `rescueFallen` passes `WeaponService.LastGround(player)`.
- **`src/combat/server/Services/WeaponService.luau`.**
  - `Shooter.stood` is recorded in `trackAir` on the footprint floor's grounded verdict (`SwingGate.IsAir`). It
    reuses the 5 rays the air-swing gate already casts, so no ray is added.
  - It is cleared in `ForgetMotion` (ArenaService's moved hook, so on every server move) and in `resetAir`.
  - `LastGround` is new.
  - `resolveMelee` builds its strike with `WorldReact.SwingStrike`.
- **Harness.**
  - `tests_l2w3.luau`: re-aimed and extended.
  - `tests_l1.luau`: `L1.real.sizes` is now the real `SizesOf`.
  - `run_harness.py`: `source.w3` updated; new `source.w3fix` (the lines that apply the answers, and the client's
    three strikes).
  - `mutate.py`: 10 entries re-aimed, 51 new (`l2w3` grows from 59 to 110), and FrostFx and FeedbackController
    added to the copied files.
  - `mirror_mutants.py`: 1 entry re-aimed, 3 new.
  - `tools/check_stage_mirror.py`: W3 cases.

## Contracts implemented

```lua
WorldReact.ICE_ATTRIBUTE = "Ice"
WorldReact.SwingStrike(variant: Types.RangeWeaponVariant, step: number, origin: Vector3, heading: Vector3): WorldReact.Strike
--   { shape = variant.shape, origin = origin, direction = heading (as given, not flattened),
--     size = variant.range (never + pad), width = variant.width,
--     arcDegrees = variant.finisherArcDegrees when chain ~= nil and step == #chain and it is set, else variant.arcDegrees }
WorldReact.IceReach(ice: any): (number?, number?)          -- levels.react.ice's reachDown, ahead (nil unless a number)
WorldReact.IceLook(frozen: boolean, shown: number): WorldReact.IceLook   -- { transparency, collide, shadow, frozen }
WorldReact.Reactive(react: string?): boolean               -- react ~= nil and react ~= "ice"
LevelGeometry.SizesOf(expeditions: Types.ExpeditionsConfig?, rules: Types.CombatLevelsConfig?): (LevelGeometry.Sizes, boolean)
LevelGeometry.IceOf(react: any): (LevelGeometry.IceSize?, boolean)       -- (size, refused)
LevelGeometry.Length(value: any): number?
LevelGeometry.Overlap(a: LevelGeometry.Box, b: LevelGeometry.Box): boolean   -- area overlap; touching is not
StageFlow.Landing(plan: Plan, position: Vector3, stood: Vector3?, margin: number): Vector3?
StageFlow.FallLanding(plan: Plan, state: State, position: Vector3, stood: Vector3?, margin: number): Vector3?
WeaponService.LastGround(player: Player): Vector3?
```

**The landing rule as built (s-M1 and Q3).** The rescue goes to a water's landing in two cases:
- the root where the server last saw the body grounded (`stood`) lies inside that water's footprint, grown by
  `player.rescue.outside` (4);
- otherwise, the root's position now lies inside it.

Details:
- In both tests the first water in the layout's order wins, and `stood` is tested against every water before the
  position is.
- A water is any `collide == false` block with a `landing`.
- The run's safe point still decides in a closed camp's fight or breather, and whenever neither point lies by any
  water.
- No new config key. A walk-off from the frozen creek lands about 9 studs out, and a dash-off about 29. Both come
  back to the creek's landing because the body stood on the ice. A walk-off Road2's far end, or the Road1 gap,
  goes to the safe point.

**Q2.** Each ice cell's `CustomPhysicalProperties` = `PhysicalProperties.new(<the "ground" look's material>)`. That
material is SmoothPlastic today. The Ice look and material still show.

## Gates (current tree, with the data and client agents' work in it)

| Gate | Result |
|---|---|
| Harness | `HARNESS: PASS (3,064 checks, ...tycoon-p5\tools\crowd_harness)` (was 2,977) |
| `mutate.py` filter `l2w3` | 110 run. The first run missed 1 mutant, `l2w3: a block nothing meets covers`: the 2×2 Mist no longer held a whole cell. Mist is now 7×7, and the re-run of that mutant is caught. 0 not caught. |
| `mutate.py` filter `l2w2` | 93 run, 0 not caught |
| `mutate.py` filter `world:` | 81 run, 0 not caught |
| `mutate.py` filter `fix3` | 16 run, 0 not caught |
| Stale-text count, all 1,106 entries | 0 |
| `mirror_mutants.py`, all | 112 of 112 caught |
| `check_stage_mirror.py` | CHECK: PASS (L2 W3 Validate lines: 18 compared) |
| `check_levels_mutants.py --only "(the mirror alone)"` (the data agent's) | MUTANTS: PASS. Its three W3 mirror cases find my labels. |
| `check_compile.py` | PASS, 174 files |
| stylua, selene | clean (0/0/0) |
| luau-lsp (combat sourcemap regenerated to scratch) | exit 0, no diagnostics, on my 7 files and InputController |
| `rojo build combat.project.json` | builds |

Cell counts on Forest Road:
- 136 ice cells, up from 132: the 4 part-covered cells beside the island are now built.
- 252 Parts, equal to check_levels' count.
- The harness's fill check finds 0 open points in the Creek and in the Pond.
- The harness walker crosses in 16 swings with `SwingStrike`.

## Assumptions

- **The bank margin is `rescue.outside` (4).** Stepping off the far (east) 6 studs of ShrineSignPad, onto
  something that is not water, goes to the checkpoint. A wider bank would need a new key, e.g. `player.rescue.bank`
  (data), plus one argument in WaveService.
- **`stood` is cleared on every server move,** through ForgetMotion. For a frame or two after a Studio lever move,
  the client may still report its old grounded place. A fall in those frames would land at the old water.
- **`React` now always reads `Tuning.Get()` (cached) and `StrikeElement`.** A family with no element returns at once.

## Required changes outside my files

- **Data agent (done, verified).**
  - The sim_range mirror (Q3 landing line, `ice_overlap`, whole-cell `ice_cells`) and CreekUp's landing match my
    rules exactly: check_stage_mirror passes.
  - Their mirror case was aimed at "a pool that collides, with no landing", and I named my case that way.
  - "plain water with a landing" is now an accepted case, "plain deep water with a landing". The new refusal is
    "a plain block that collides, with a landing".
- **Client agent.** `RangeControlsConfig.iceAutoDegrees` is typed now, so the `(cfg.controls :: any)` cast at
  `InputController.luau:1434` can go. That is optional.
- **Lead (INTERFACES).** Record the signatures above, `Plan.waters` (any deep block), and the landing rule.

## Known limits and things for the lead

- **s-s1, recorded as a known limit.** Only colliding blocks and secrets cover water, and they are judged by their
  top alone:
  - camp pieces never cover water;
  - a high bridge leaves the water under it unfrozen, as if it sat on the water.

  Nothing on Forest Road is affected.
- **Ice thickness 4 (d-m6) and shimmer.** At the edge of a water block, a cell's outer side faces lie on the same
  plane as the water block's own side faces.
  - That shared band runs from y −4.8 to −1. It was −1.8 to −1 at thickness 1.
  - Once frozen, the opaque ice face and the 0.2-transparent water face share that plane, which may shimmer.
  - A fix if Studio shows it: inset the outermost cells' outer faces by a hair in LevelGeometry, mirrored in
    `ice_cells` and the fill line's tolerance.
- **The review's Studio note.** A PC swing in the first frames of a fall into open water freezes the cell the body
  is falling through. With thickness 4, that cell (y −4.8 to −0.8) can turn solid around the legs. Phones no
  longer do this (c-m4).

## What to check in Studio

1. **Falls with the hammer (I key).**
   - Walk off the frozen creek's east side at full speed, then dash off it. Each time you should land on Road2 at
     (−385, 0, 2), not at camp A's checkpoint.
   - Fall into CreekUp, north of the bridge. You should land at (−385, 0, −2).
   - Walk off Road2's far east end. You should land at the checkpoint.
2. **Grip.** Run and stop on frozen ice. You should not slide.
3. **The pond's edges and the creek's long sides once frozen.** Look for shimmer on the side faces.
4. **Beside the island.** The cells beside it freeze, no slit of water is left, and no flicker shows where a cell's
   top lies inside the island.
5. **Falling into open water.** Swing while falling in. Does the body pop up onto the cell or get lodged in it?
