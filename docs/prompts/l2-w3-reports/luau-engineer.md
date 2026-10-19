# L2 W3 — luau-engineer report (2026-10-19)

Branch `l2-w3` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing committed.

## Files changed

- `src/shared/Types.luau`: `LevelBlock.landing`, `ExpeditionsConfig.found`, `CombatReactConfig` = `{ fireHits?, pad?,
  ice: CombatIceConfig? }` (`iceHits` gone), new `CombatIceConfig { cell, lift, thickness, reachDown, ahead }`, the
  `CombatFxReact` comment ("frozen", one per cell).
- `src/shared/WorldReact.luau`: `Strike.arcDegrees`, `Rules = Types.CombatReactConfig`, `IceCell`, `CellGrid`,
  `Cells`, `Chills`, `Freeze`; `Need` is fire's alone.
- `src/combat/server/Services/LevelGeometry.luau`: requires WorldReact; `IceSize`, `Sizes.ice`, role `"ice"`, the
  ice pieces in `Pieces` (after the blocks, before the camps).
- `src/combat/server/Services/LevelService.luau`: `iceOf` (in `sizesOf`), the per-run `ice` list built in
  `construct`, `freeze`, React's ice branch, `Clear` resets it.
- `src/combat/server/Services/StageFlow.luau`: Validate's ice and landing lines, `Plan.waters`, `Water`,
  `Landing`, `FallLanding`.
- `src/combat/server/Services/WaveService.luau`: `rescueFallen` goes to `StageFlow.FallLanding` first.
- `src/combat/server/Services/AbilityService.luau`: `MECHANICS.frostQuake = MECHANICS.earthquake`.
- `WeaponService.luau`: **unchanged** (its `StrikeFx` already carries `arcDegrees`; the listener type fits).
- Harness: new `tools/crowd_harness/tests_l2w3.luau`; `run_harness.py` (the file in TESTS, `source.w3`),
  `tests_l1.luau` (`L1.real.sizes` gains `ice`), three re-aimed cases (`tests_l2.luau`: the shrine now pays 5–9
  Valor + Timber; `tests_l2w2.luau`: `Need` never counts ice, and "ice is a word a block may react to" now means
  deep water); `mutate.py` (+59 `l2w3:` entries, three re-aimed, `WaveService` copied);
  `mirror_mutants.py` (+5 `L2 W3:`); `tools/check_stage_mirror.py` (WorldReact bundled, the L2 W3 accepted/refused
  cases, "a bramble that reacts to ice" moved to the refusals).

## Contracts implemented (signatures)

```lua
-- WorldReact (shared, pure)
export type Strike = { shape, origin, direction, size, arcDegrees: number?, width: number?, endPoint: Vector3? }
export type IceCell = { box: Box, frozen: boolean }
WorldReact.CellGrid(box: Box, cell: number): (number, number)      -- ceil(sx/cell), ceil(sz/cell); 0,0 if bad
WorldReact.Cells(box: Box, cell: number): { Box }                    -- X fastest, then Z; keeps box.y/sy
WorldReact.Chills(fx: Strike, box: Box, reachDown: number, ahead: number): boolean
WorldReact.Freeze(cells: { IceCell }, element: string?, fx: Strike, reachDown: number, ahead: number): { number }
-- LevelGeometry
export type IceSize = { cell: number, lift: number, thickness: number }   -- Sizes.ice: IceSize?
-- StageFlow
export type Water = { rect: Rect, landing: Vector3 }                -- Plan.waters: { Water }
StageFlow.Landing(plan: Plan, position: Vector3, margin: number): Vector3?
StageFlow.FallLanding(plan: Plan, state: State, position: Vector3, margin: number): Vector3?   -- nil in fight/breather
```

`Chills` is exactly the contract's rule: `arc` only; the cell's top (`box.y + box.sy/2`) in
`[origin.Y − reachDown, origin.Y]`; the centre's flat distance ≤ `size + ahead`; angle from the flat direction ≤
`arcDegrees/2` (≥ 360 = all round; a centre right under the origin is in every sector). An arc of 0 or under, no
`arcDegrees`, a direction with no flat part (unless 360+) and any non-finite number: false.

**Validate's lines** (same texts as `sim_range.react_problems` except the last, which only differs in wording; the
mirror compares refused-or-not):
`block X is ice and collides` · `block X is ice and opens <id>` · `block X has a landing and is not ice` ·
`block X: landing.<k> is <v>, not a number` · `block X: landing is <v>, not a point` (sim_range says
`landing is not a point`). A fire block (or a word that is no element) keeps W2's lines unchanged.

**Ice pieces:** for every block with `react = "ice"` (when `Sizes.ice` is given), `Cells(box, ice.cell)`; a cell whose
centre lies in the footprint, **edges included**, of a colliding block or a secret whose top is above the water's
top gets no piece (same rule as `sim_range.ice_cells`). Piece: name `Ice_<block>_<k>` (k = its index in `Cells`'
order, so covered cells leave gaps), role `"ice"`, look `"ice"`, `collide = false`, footprint of the cell, top =
water top + `lift`, `thickness` deep. A grid of more cells than `maxParts` is refused before any cell is made;
the total is then held by the usual Part count. ForestRoad today: **132 cells**; the harness holds `#pieces` equal
to `check_levels.part_count`.

## The WorldReact API for the client (ui-engineer)

- Ice cell Parts live in `Workspace.Level`, named `Ice_<block>_<k>`, attribute **`Ice`** (`false` as built, `true`
  once frozen). Unfrozen: Transparency 1, CanCollide/CanQuery/CanTouch false, CastShadow false. Frozen: the look's
  transparency (the `ice` look has none, so 0), CanCollide + CanQuery true, CastShadow true (CanTouch stays false).
- `ReactFx.ForEachIce` / `iceOnAuto` / the ghost: `WorldReact.Chills(fx, WorldReact.BoxOf(part.Position, part.Size),
  ice.reachDown, ice.ahead)` with `ice = Combat.json levels.react.ice`. Build `fx` as the server does
  (`WeaponService.resolveMelee`): `{ shape = "arc", origin = <root position>, direction = <flat heading>, size =
  variant.range, arcDegrees = variant.arcDegrees }` (a family with `finisherArcDegrees` uses it on the chain's last
  step; the Frost Hammer has none). The server's origin is the clamped claim (the client's root sample).
- `"frozen"` CombatFx `react` events come **one per cell**, `name` = the cell Part's name, the box = the cell's piece
  box. `Freeze` with any element but `"ice"` (and every ability, through `StrikeElement`) freezes nothing.

## Confirmations

- **A swing on the road reaches `finish()`:** `WeaponService.OnAttack` → `mayAct` (WaveService: `ArenaService.InRun()`
  = the five live phases incl. `travel`, the member fighting, not down; no camp or in-play rule) → `SwingGate.Judge`
  (a grounded swing on Road2 or on frozen ice is allowed: `footprintFloor` casts with `RespectCanCollide`, so it sees
  frozen cells and not unfrozen ones) → `resolveMelee`, which calls `finish()` unconditionally at its end, and
  `finish()` calls every strike listener (`LevelService.React`, wired in Main) whenever `fx.abandoned` is not set
  (only a projectile's empty end strike sets it). So a frost swing at the creek's edge outside every camp freezes.
- **No require cycle:** LevelGeometry → WorldReact → {Types, Unlocks}; Unlocks → Types. No shared module requires a
  server module; StageFlow → LevelGeometry, LevelService → {LevelGeometry, WorldReact}. `check_compile` and the
  harness (which loads LevelGeometry through WorldReact) pass.
- **Frozen sheets are floor, not walls, for the shot-origin chord gate:** frozen cells are 1 stud thick and lie
  under the feet (top = water − 1 + 0.2); `aimAllowed`'s line runs from the head to an origin at shoulder height,
  so it never crosses a sheet the shooter stands on. Unfrozen cells are invisible to every world ray
  (`RespectCanCollide`, CanCollide false).
- No `Main.server.luau` change, no remote, no server lever.

## Gates (all on the designer's data as it stands at the end of my run)

- Harness: `HARNESS: PASS (2,977 checks, ...tycoon-p5\tools\crowd_harness)`.
- `mutate.py` filtered `l2w3`: **59 run, 0 not caught** (the first run left `360 is not all round` uncaught; a
  case "all round needs no heading" now catches it); `l2w2`: 93 run, 0 not caught; the re-aimed
  `world: Pieces builds the ground as the layout writes it`: 1 run, 0 not caught. Stale-text count over all
  **1,055** entries: **0** (scratch script that executes mutate.py's table and counts each text in its file).
- `mirror_mutants.py` (all): **109 of 109 caught** (the 5 new `L2 W3:` ones included).
- `check_stage_mirror.py`: CHECK: PASS (L2 W3 Validate lines: 12 compared; L2 W2: 21).
- `py tools/check_compile.py`: PASS (174 files).
- stylua --check, selene (0/0/0), luau-lsp analyze (committed definitions, combat sourcemap regenerated with rojo
  into my scratch folder) clean on my files and WeaponService.

## Assumptions

- `StageFlow.FallLanding` is an addition: the closed-camp rule ("only outside a closed camp's fight/breather") is
  pure there so the harness and mutate hold it; WaveService only calls it.
- `WorldReact.CellGrid` is an addition (Pieces counts a grid before making it).
- `iceOf` requires a positive finite cell and thickness and a finite lift, else no cells (one warn). sim_range's
  `ice_cells` reads only the cell (lift `or 0`): they differ only on a broken config.
- An ice block is not in the W2 `reactive` list even though its piece keeps `react = "ice"`.
- `Landing`'s margin is `player.rescue.outside` (4); a non-finite or negative margin counts as 0.

## For other owners

- **economy-designer (sim_range):** optional: `landing is not a point` → `landing is <v>, not a point` to match the
  Luau text (the mirror compares refusals only, so it is not a failure). `ice_cells` iterates i outer (Z fastest);
  the Luau names count X fastest. Counts agree; only matters if a tool ever matches cell names.
- **lead (INTERFACES):** record `StageFlow.FallLanding`, `WorldReact.CellGrid`, `Types.CombatIceConfig`,
  `LevelGeometry.IceSize`/`Sizes.ice`, `Plan.waters`/`StageFlow.Water`. `sourcemap.combat.json` in the worktree is
  modified by someone else's rojo run (not mine).

## What to check in Studio

- A frost swing from Road2's south edge over the creek: ~6 cells appear (two rows), stand on them, keep swinging to
  the island (the harness's greedy walker standing on cell centres needs 16 swings; from the cell's far edge it is
  fewer). Ice material feel (slide?) under a Humanoid; camera and shots meet frozen ice as ground.
- Fall into unfrozen creek or pond (after camp A's checkpoint): back on Road2 at (−385, 0, 2) in a second, not at A.
- A swing at the top of a jump over the water freezes nothing; Frost Quake freezes nothing.
