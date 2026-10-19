# L2 W3 review: server slice (2026-10-19, `l2-w3` at 6db63ae)

Scope: `src/shared/Types.luau`, `src/shared/WorldReact.luau`; `src/combat/server/Services/LevelGeometry.luau`,
`LevelService.luau`, `StageFlow.luau`, `WaveService.luau`, `AbilityService.luau`; WeaponService's `finish()`
listener path as it drives freezing. The queued fixes Q1 to Q4 are not re-reported.

Result: **0 Critical, 1 Major, 1 Minor, 3 Suggestions.**

## Major

**M1. `StageFlow.luau:2620-2625` and `WaveService.luau:1187`: the landing rect is grown by `rescue.outside` (4).
A walk-off carries a body about 9 studs past the edge. So a slip off the frozen creek's side lands at the
checkpoint, not on Road2.**
- **What.** `Landing` grows each water's footprint by `player.rescue.outside`, 4 studs. The comment says why:
  "a fall carries a body past the edge it went in at". The rescue runs every Heartbeat and judges the root
  once it is under `killY` (−13).
  - From a frozen cell (top −0.8, root 2.2) the root falls 15.2 studs, which takes 0.394 s. At `walkSpeed` 20
    that carries it 7.9 studs, plus `BODY_RADIUS` 1 before it tips. So it lands about **8.9** past the edge.
  - From Road2 it lands about 9.1 past. A dash off the edge carries about 29.
- **Where it bites.** One swing (radius 13, 120°) freezes all three columns of the 20-wide creek. The frozen
  lane is therefore exactly the creek, with void on both long sides for 88 studs (nothing stands beside it in
  `ForestRoad.json`).
- **Failure scenario.** After camp A, the player comes back with the hammer and freezes his way south. He
  steers a little and walks off the east side of the ice at full speed. The root goes under −13 at
  x ≈ −381, outside the grown rect (x ≤ −386).
  - `FallLanding` returns nil, and `SafePoint` puts him at camp A's checkpoint, 267 studs away (519 after B,
    716 after C). Ben's rule (4), "a fall comes back to the road by the creek", fails on the crossing's
    commonest slip.
  - A slow sidestep off the same edge lands on Road2. So the answer depends on speed, not place.
  - Falls off the frozen front into open water stay inside the creek's 88-stud length, so they work.
- **Fix.** Use a fall-carry margin instead of the camp margin.
  - Add `player.rescue.waterCarry` (10) in Combat.json and pass it in WaveService. The bound is
    `walkSpeed × √(2·(waterTop + ROOT_HEIGHT − killY)/g) + BODY_RADIUS` = 8.9 today. Add a check_levels line
    that holds the key at or above that bound.
  - Add a harness case: a root 8.9 off the creek's side lands; one 11 off does not.
  - A grown creek of 10 only adds Road2's south edge at x −420..−380, where the landing is right beside it,
    which is better than today.
  - If dash-offs should land too, record each member's last grounded root position (FloorMaterial ≠ Air,
    sampled on the tick) and ask `Landing` about that point instead.
  - Q3 touches the same rule (landings on non-ice water), so fold this into it.

## Minor

**m1. The service lines that apply the ice are unharnessed. Five review-only mutants survive the full harness
(2,977 checks, PASS each time).** Run on a second `git archive` copy with `mutate.py <copy> luau "probe:"`:

| Probe | Line | What breaks in the game |
|---|---|---|
| `sizesOf builds no ice` | `LevelService.luau:247` `ice = iceOf(...)` → `ice = nil` | There are no ice cells anywhere, so the shrine is unreachable for everyone, and every gate stays green. The harness and `check_levels.part_count` pass their own `sizes`. |
| `React's guard forgets the ice` | `LevelService.luau:716` `#reactive == 0 and #state.ice == 0` → `#reactive == 0` | Freezing stops whenever no fire block stands. Both brambles carry `opens: "cave"`, so that happens on every run after the leader has found the cave shortcut, and in any run once both brambles burn. |
| `a cell is built with no Ice attribute` | `LevelService.luau:436` | The server still freezes. But `ReactFx.luau:138` finds cells by `typeof(Ice) == "boolean"`, so phones never auto-swing at water and no ghost or burst is drawn. |
| `a frozen cell stays invisible` | `LevelService.luau:688` | An invisible floor. |
| `ice blocks are reactive` | `LevelService.luau:446` `react ~= "ice"` dropped | The water gets `React`/`Heat` attributes, and ReactFx and `reactOnAuto` see it as a reactive block. |

The W2 pattern holds again: the pure parts are mutated, the lines that apply them are not. The `source.w3`
reading counts React's ice branch, freeze's three floor lines and the rescue call, but none of the five above.
- **Fix.** Add the five texts to `W3_LINES`/`FREEZE_FLOOR` in `run_harness.py`, with the guard read from
  React's body and the attribute and transparency from construct's `piece.role == "ice"` branch. Better, move
  `iceOf` and `sizesOf` into a pure helper that the harness loads with the shipped Combat.json and checks
  `sizes.ice ~= nil`. Then add the five as `l2w3:` entries in `mutate.py`.

## Suggestions

**s1. `LevelGeometry.luau:708-716, 803-811`: the cover rule does not see everything that could cover water.**
- It reads colliding blocks and secrets only. Camp floors, fences, cover, markers and signs never cover.
- It judges only a cover's top, never its bottom: a high bridge (bottom 30 above the water) leaves the water
  under it unfrozen, as if the bridge sat on the water.
- Nothing on Forest Road is affected today. Before a later level puts a camp or a high bridge by water, judge a
  cover on its bottom lying at most a step (or `lift` + `ROOT_HEIGHT`) above the water's top, and include the
  camp pieces. Mirror the change in `sim_range.ice_cells`.

**s2. Overlapping ice blocks freeze into coplanar tops.**
- Two ice blocks whose footprints overlap both build cells at `waterTop + lift`. Because every water top lies at
  one height (check_deep_water), the frozen tops would z-fight (the M9 lesson).
- Creek and Pond abut exactly at z 96 today. Add a Validate or check_levels line that ice footprints may
  touch but not overlap.

**s3. `ICE_ATTRIBUTE = "Ice"` is written twice** (`LevelService` CONST and `ReactFx.luau:64`), as `React`/`Heat`
were in W2. The client finds cells by this name alone. One export in `WorldReact` (shared, pure) would let a
rename on one side fail to compile instead of silently hiding every cell.

**Note for Studio (not a finding).** `Chills` judges the band from the root. A swing in the first ~0.15 s of a
fall into open water (root still 0.2 to 5.2) freezes the cell the body is falling through, and the Humanoid
should pop up onto it, as a self-catch. Worth one look in Studio, so that no body ends up lodged in a cell.

## Verified (safe to rely on)

- **Abilities never freeze.** Two guards apply.
  - Every ability strike reaches `finish()` tagged: `Strike` :2803, `reportShot` via `projectile.ability`.
    `StrikeElement` then returns nil.
  - `Chills` takes arcs only. Frost Quake is a sphere (`launchEarthquake`), and the movement slam is weapon
    `"slam"`, which has no element.
- **Only ice families freeze.** frostHammer is the only `element: "ice"` family. `OnAttack` refuses a family
  the slot does not hold, and the lever is the only way to own it.
- **A swing anywhere reaches `finish()`.** `resolveMelee` calls it unconditionally. The ranged arc path
  (:1488) uses the shot origin, but no ice family has a ranged variant.
- **Chills and Freeze.** The band runs from the top of `[origin.Y − reachDown, origin.Y]` down. The radius
  is `size + ahead`. The sector uses the cosine of `sweep/2`; 360 or more means every direction; a centre at
  distance 0 counts as inside. Any non-finite number gives false, as does a missing `arcDegrees` or a heading
  with no flat part. Freeze answers in ascending order and skips frozen cells. Each edge has a mutant in
  `mutate.py`.
- **Cells.** The creek has 3 × 13 = 39 cells. The pond has 11 × 9 = 99, minus 6 under the island and the
  chest, so 93. That is 132 in all, matching the engineer, inside `maxParts` 600. The `nx*nz` guard runs
  before any list is built. The creek's row 1 abuts Road2 (z 8). Row 4 of the pond runs 2.67 studs under the
  island, but its top (−0.8) sits inside the island, so no faces are coplanar.
- **Per-run reset.** `Build` refuses while a level is built and makes a fresh `ice` list. `Clear` empties it
  and destroys the Parts. `raise` clears the list when `construct` throws.
- **Flags.** Unfrozen cells have CanCollide, CanQuery and CanTouch false, Transparency 1 and no shadow. Frozen
  cells have the look's transparency, CanCollide and CanQuery true, a shadow, and CanTouch false. They are in
  the Default group, so `ArenaPlayers` stand on them and the barrier group is untouched.
  `SwingGate.footprintFloor` (RespectCanCollide) sees frozen cells and nothing else.
- **FallLanding by phase.**
  - travel, armed and gate: Landing.
  - fight and breather: nil, then SafePoint, which is the camp's entry. This matches `IsOut`'s camp box.
  - over: never asked, because Rescue answers "lobby".
  - In a resident fight on the road (engaged), it lands with no grace i-frames, as L1b-20 says.
- **The shrine pays once, and only to an ice owner.** `tickSecrets` opens through `OpenSecret`, which holds
  the profile's opened set. A "locked" visit is re-asked only once `HoldsKey(player, "ice")` holds.
  `HoldsKey` = `HasElement(families)` for frostHammer, which only the lever writes today.
- **No yields.** `freeze` runs in the strike's frame. `RunFx.Push` queues the six or so "frozen" events of a
  swing. `rescueFallen` adds one rect test per water, and only for a body already judged out.
- **No require cycle:** LevelGeometry → WorldReact → {Types, Unlocks}.
- **Gates on a `git archive HEAD` copy:**
  - harness PASS (2,977);
  - `check_compile` PASS (174 files);
  - luau-lsp on the seven slice files, 0 errors;
  - selene 0/0/0 and stylua clean on `src/shared` and `src/combat/server`.
