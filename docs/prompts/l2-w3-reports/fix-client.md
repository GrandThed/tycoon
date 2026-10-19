# L2 W3 fix round: client agent report

Branch `l2-w3` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing is committed. The work covers the client half of
`docs/prompts/l2-w3-fix-round.md`: Q1, c-m4, Q4, c-s1, c-m1, c-s2, c-m2 and the client side of c-m3. It is
coded against the server agent's `WorldReact.SwingStrike(variant, step, origin, heading)`,
`WorldReact.ICE_ATTRIBUTE` and `WorldReact.IceReach(ice)` as they landed.

## Files changed

- `src/combat/client/Controllers/ReactFx.luau`
- `src/combat/client/Controllers/FrostFx.luau`
- `src/combat/client/Controllers/InputController.luau`
- `src/combat/client/Controllers/FeedbackController.luau` (routing, plus the third SwingStrike copy)
- `src/combat/client/Controllers/AbilityFx/FrostQuake.luau`
- `src/client/UI/Theme.luau`

## Findings

### c-m1 and c-s2: the phone's water test

ReactFx now keeps an `IceCell` record per cell (`ReactFx.luau:213`, `adoptIce`). The record holds:
- the box, frame, size, plan centre and top, all read once when the cell is adopted;
- the cell's index in an unordered open list (`openCell`/`closeCell` :181/:189);
- one `Ice` connection (`iceChanged` :204). A cell set true leaves the list and its ghost goes.

`ReactFx.ForEachIce(origin, reach, reachDown, callback): boolean` (:567) works in three steps:
1. It returns early when the origin is outside the band of the cells' tops, or farther than `reach` from the
   rectangle of their centres (`nearBounds` :535; the bounds are rebuilt only after a cell comes or goes).
2. It hands on only the open cells whose centre is within `reach` in plan and whose top is in the band. These are
   Chills' own distance and band tests, widened by `NEAR_SLACK` 0.01 (:104).
3. It stops when the callback answers true (c-s2).

What changed in the per-frame reads:
- No per-cell engine reads remain. Before: `Parent`, `GetAttribute`, `Position` and `Size` for each of the 132
  cells, which is 528 bridge calls a frame.
- No per-cell table is made. Before: 132 `BoxOf` tables a frame.

The filter is a necessary test of Chills only. A fuzz of 200,000 random swings checked it against plain Chills over
every cell: 114,330 cells named, 0 mismatches. The script is in the scratchpad (`fix-client/bench_full.luau`).

**Per-frame cost of `iceOnAuto`.** This was measured with the real `WorldReact.luau` (Chills, BoxOf, SwingStrike) in
the Luau CLI on the desktop, on the Forest Road grid of 132 cells and the shipped hammer (range 9, 120°, chain of 3,
cone 60). The machine was shared with other agents, so the numbers are ranges over three runs.

| Where the phone player stands | Before | After |
|---|---|---|
| Anywhere away from the water (camp B, 300 studs off) | 270–300 µs, plus 528 engine reads and 132 tables | 0.3 µs: one rectangle |
| On Road2 facing along the bridge (nothing taken) | 290–340 µs | 6–7 µs |
| On the bank facing away from the creek (nothing taken) | 265–360 µs | 10–18 µs |
| On the bank facing the creek (a cell taken) | 20–35 µs | 10–20 µs |
| Out on the pond (a cell taken) | 160–275 µs | 25–38 µs |

The review measured 143 µs for the old pure part on its machine. Mine read about 2× slower in absolute terms, so
compare inside one column.

### c-m2: ghosts follow the swing's answer

- Ghosts are held by the swing's `seq`. `ghostOn(cell, seq)` (:422) keeps one ghost per cell with a set of
  holders. `release(seq)` (:436) drops a ghost once no swing holds it.
- `PredictFreeze(strike, seq)` (:606) records the swing. It releases it after `COMBAT_RANGE_SWING_ANSWER_SECONDS`
  (2 s), the safety cap: the time after which InputController already counts a swing as dropped.
- `AnswerFreeze(seq)` (:645) shortens the hold to `Theme.COMBAT_FROST_GHOST_GRACE_SECONDS` (0.3, `Theme.luau:1476`).
  The server's `finish` calls `FireClient` with the strike, then runs the freeze in the same frame, so `Ice`
  replicates within a step.
- `RefuseFreeze(seq)` (:656) takes the ghosts at once.
- `COMBAT_FROST_GHOST_SECONDS` is gone.
- Wiring:
  - `FeedbackController.luau:2875` calls `FrostFx.OnAnswered(seq)` in the branch for the local player's own
    answered swing.
  - `FeedbackController.luau:3521` calls `FrostFx.OnRefused(seq)` in `OnRefused`.
  - `FrostFx.luau:147/:152` route both to ReactFx.
- A refused shot's seq holds no ghosts, so nothing happens for it.
- Each delayed release checks that its prediction is still current, so `Destroy`, a refusal or the grace can never
  double-release.

### c-m3, client half: one SwingStrike

All three client copies now build the strike with `WorldReact.SwingStrike`:
- `FrostFx.luau:141`, the ghost and the puff:
  `local strike = WorldReact.SwingStrike(swing.variant, swing.step, swing.origin, swing.heading)`. `arcOf` is deleted.
- `InputController.luau:1398`, the phone, in `autoIceStrike`:
  `local strike = WorldReact.SwingStrike(variant, step, origin, heading)`.
- `FeedbackController.luau:3538`, the early hitbox effect. This is the third copy the review named:
  `local predicted = WorldReact.SwingStrike(variant, swing.step, swing.origin, swing.heading)`.
  - Its shape, origin, direction, size, arc and width come from the predicted strike.
  - The values are the same as before for every family (the client already sends a flat heading).
  - It costs one top-level local: FeedbackController now has 162.
- **For the server agent or the lead:** the harness reads no client file. If client call sites should be gated too,
  the three lines above are exact and unique in their files. A source check with a mutant each (for example, `size`
  replaced by `range + pad` in a local copy) would close the W1 pattern on the client.

### Q1 and c-m4: the phone's auto-swing at water

`iceOnAuto` is at `InputController.luau:1418`. Each rule can only remove swings:
- **c-m4** (:1427): it returns false while `MovementController.IsAirborne()`, so a hop or a walk-off never spends the
  air swing or hangs the body over water.
- **Q1** (:1434): every step's arc is cut to `controls.iceAutoDegrees` (`autoIceStrike` :1391, `math.min`).
- **Combo steps:** the next swing's step is the server's to choose, so a cell triggers only when the strike of every
  step of the chain chills it. A future finisher arc can then never make the phone swing at water that step would
  not freeze. The step-1 strike's reach picks the cells, and the other steps are built only once a cell is within
  reach.
- **Typing:** `controls.iceAutoDegrees` is read through an `any` cast with a number check, because
  `Types.RangeControlsConfig` has no such field yet. A missing value cuts nothing.

**Measured on the real layout** (`WorldReact.Chills` and `SwingStrike`, Road2 x −424..−340, z −8..8, root Y 3,
camera along the road, the creek's 39 cells):

| Cone | Walking along Road2, auto-swings at the creek when the root's z is |
|---|---|
| 120 (before) | ≥ 0.2: the whole south half |
| **60 (shipped data)** | **≥ 5: the outer 2.5 studs a root can reach (to 7.5)** |
| 40 | ≥ 7: the last half stud |
| 34 or less | never |

At every value tested, standing on the sign pad's west edge facing the water still auto-swings (that swing freezes
4 cells). At 34 or less, facing south along the bank from the pad's edge no longer swings, which is right.
**Lead's call:** 60 meets "narrower, only removes swings" but not "the south half does not swing". 34 meets both.

### Q4 and c-s1: Frost Quake

- **Q4:** the visual draws `def.count` rings (`FrostQuake.luau:127`, already reading the configured count), so the
  tuned data (count 1, radius 32) draws one ring at 32.
- **Shard spacing:** shards are spaced along the ring instead of counted per ring:
  - `LOOK.shardGap` 5.6 studs (:80), matching Earthquake's ten cracks round 9 studs; 11.2 on low-end devices;
  - at least 4 per ring, and at most 40 for all rings together (20 on low-end devices);
  - at radius 32 that is 36 shards (18 on low-end devices);
  - the angle may stray ±0.4 of the gap.
- **Floor test:** each shard casts one ray at build (`footAt` :107, Pool's `worldParams`, built once per cast). The
  ray runs from 3 studs above the ring height to 3 studs below it.
  - With no floor, the shard is dropped. That covers the void, open water (CanQuery false) and drops.
  - With a floor, the shard stands on it (frozen ice counts).
  - Both random draws happen before the test, so every client places the same shards.
- The ring marks and the front still draw whole, because they show the strike's area.

## Gates

| Gate | Result |
|---|---|
| `py -I tools/check_compile.py` | PASS, 174 files. FeedbackController 162 top-level locals, InputController 158. |
| `stylua --check src/combat/client src/client/UI/Theme.luau` | clean |
| `selene` on the same files | 0 errors, 0 warnings |
| `luau-lsp analyze` (definitions `tools/types/globalTypes.d.luau`) | Both sourcemaps were regenerated with rojo and came out identical to the tracked files. Combat sourcemap over `src/combat/client`, `src/shared`, Theme, MapScreen: exit 0. Default sourcemap over `src/client`, `src/shared`: exit 0. No diagnostics. |
| `rojo build combat.project.json` to scratch | builds |

All my files are LF. No UI layout changed in this round, so the W3 Armory numbers at 375×667, 667×375 and
1920×1080 still hold.

## Remotes, state and config consumed

No new remote. The client reads:
- the strike CombatFx `seq` (for the answer);
- `RangeStats.refusedSeq` (for the refusal), through `FeedbackController.OnRefused`;
- the `WorldReact.ICE_ATTRIBUTE` attribute on the cells;
- the config: `ProvingGrounds.json` `controls.iceAutoDegrees` and `Combat.json` `levels.react.ice` (through
  `WorldReact.IceReach`).

## Changes needed in other files

- **`src/shared/Types.luau`** (server agent): type the new key so the read can drop its cast.
  ```diff
   export type RangeControlsConfig = {
   	touchMode: "autoFire" | "tapFire",
   	autoFireAssistDegrees: number,
   	autoSwingPad: number,
  +	-- L2 W3 fix round Q1: the widest arc (degrees) touch auto-swing at water sweeps, cut from the
  +	-- swing's own, so it can only remove swings.
  +	iceAutoDegrees: number?,
  ```
  Then `InputController.luau:1434-1435` can read `cfg.controls.iceAutoDegrees` directly. The current cast is correct
  either way.
- **`ProvingGrounds.json` `controls.iceAutoDegrees`** (data agent, lead's call): 60 still auto-swings on the road's
  outer 2.5 studs beside the creek's head; 34 never does (table above).
- **Harness** (server agent, optional): source checks plus mutants on the three client `SwingStrike` lines quoted
  under c-m3.

## What Ben must check in Studio

1. **Ghosts (PC, hammer by I):**
   - At the sign pad, each swing shows ghosts of ice at once, and the real ice replaces them with a glint and no
     flicker.
   - Swing faster than the rate allows: a refused swing's ghosts vanish at once.
   - With Studio's network simulator at about 300 ms of lag, the ghost holds until the ice arrives (no
     ice, water, ice).
2. **Phone emulator (667×375), hammer equipped:**
   - Standing at the creek's edge facing the water, it swings by itself and freezes the way across.
   - Walking along Road2's south half past the creek's head with the camera along the road, it does not swing,
     except on the very edge strip at cone 60 (see Q1).
   - Hopping at the ice edge toward open water never stops the jump mid-air.
   - Walking off the bank gives no hang over the water.
3. **Frost Quake (Q) on Road2 by the creek:**
   - One ring at 32 studs.
   - Ice shards stand only on the road, the bank and frozen ice, never in the air over the void or open water.
   - Low graphics: about half as many shards.
4. **Frame rate (phone emulator, low graphics, hammer held anywhere in camp B or C):** no frame-time change from
   the water test.
