# L2 W3 review: data and tools slice (2026-10-19, `l2-w3` at 6db63ae)

Read-only. Tools ran on a `git archive HEAD` copy in the session scratchpad: `py tools/check_levels.py` (PASS),
`py -3.12 tools/sim_range.py --check` (see "Runs" at the end), and two probes (the uncovered ice beside the island;
(g) with the walk-off grace dropped). Q1 to Q4 of the contract's §14 are not re-reported.

**Verdict: 0 Critical, 0 Major, 6 Minor, 3 Suggestions.** The island is out of reach without ice by a wide margin,
it is reached once frozen, the chest triggers from the island only, the water is off the main path, and the frozen
layout opens no perch or route. The hammer's boss rows follow from the config and stay slower than the Broadsword's.

## The geometry, redone from ForestRoad.json

These are hand numbers, not the tool's own. Movement is jump 18 and double jump 12, walk 20, dash 20, coyote
0.12, gravity 196.2, so the jumps' climb takes 0.778 s (15.6 studs).

- **Where things are.** ShrineIsland is x −408..−392, z 120..136, top 0. The chest is 6×4×6 on it (top 4).
  - Every standable top within 150 studs of the island stands at height 0:
    - ShrineSignPad, 102.0 away;
    - CreekUp, Road2, Road1, Road3 and the Trailhead, 112 to 119 away (CreekUp is water, not a top).
  - The first top above 0 is Road5 (8), 180 away. The cave walls (84, unclimbable) are 179 away, and LookoutLedge
    (34) is 197.5 away.
- **The worst reaches from a top at 0:**
  - the jumps, a dash and the grace: 49.3;
  - Leap Smash at the jumps' apex after a dash: 15.6 + 2.4 + 20 + 32 + 1 = 71.0 (74.5 with the 3-stud step-up fall
    the model leaves out, m3);
  - Impale Dash held in the air: 29.6 + 20 + 30 + 1 = 80.6.

  Against 102.0 the margin is +21.5 (+18 at worst with m3). From the higher tops, the reach with the full fall is at
  most about 84 against 180 or more.
- **What the model counts and the game does not give:**
  - An air dash over the deep water does not happen. `MovementController.heightAboveGround` returns GROUND_PROBE
    256 over the void and the non-queryable water, and `canSlam` then turns the dash key into a slam
    (MovementController.luau:409–418, :449). The models count the dash anyway, so they are conservative.
  - A second dash at the low end of a flight is a slam for the same reason.
- **Other means, checked by reading:**
  - Enemy knocks: knockback 30 at friction 75 slides 6 studs, and a launch leaves only the double jump.
  - Players pass through players. Crowd bodies are not Instances.
  - Frost Quake, Earthquake and the slam carry nobody sideways.
  - Melee abilities are one per run: the Greataxe and the Spear are both melee, and a family changes only at
    `MayLeave`.
- **Frozen.** The cells are 3 by 13 in the Creek (6.67 × 6.77) and 11 by 9 in the Pond (6.55 × 6.67), less the 6
  whose centres lie under the island: 132 cells.
  - A swing from Road2's edge at z 7 reaches row 0's centre (z 11.4, 4.4 away) and row 1's (11.15 away), both
    inside 13. The cell top −0.8 is inside the band from the root (3) down to 3 − 6.
  - The middle column x −400 runs straight from the Creek into Pond column 5, so the chain needs no turn. The
    island is reached from row 3 (z 116..122.7), which overlaps it.
- **The trigger.** The chest's footprint grown by `secretReach` is x −405.5..−394.5, z 122.5..133.5, with 2.5
  inside the island on every side. No ice cell or other top puts a root in it.
- **Main path.** Route, sneak and shortcut route samples meet water only over CreekUp, and all of them stand on
  Road2 at 0. The Road1→Road2 gap is over the void, 14 studs short of the first water.
  - The first run is unchanged: one gap of 11.95, check_levels line "at least 1 gap".
  - A fall from the gap gets no landing (the harness proves it).
- **New perches or routes.** The ice lies at −0.8 inside x −436..−364, z 8..156:
  - it touches only Road2, the sign pad and the island;
  - it is 84 studs (in z) from Road1 and the trailhead, so it cannot bypass the gap;
  - it is more than 150 from camp A and the region, so no new sniper spot beyond the frozen Creek (rated 0/0).

  check_levels confirms the 31 walls, the lookout's (a) to (d), R8, the origin chord and killY.

## Minor

**m1. `src/combat/server/Services/LevelGeometry.luau:716`, mirrored by `tools/sim_range.py:5491` (`ice_cells`):
a cell whose centre a cover holds gets no piece, but the cell reaches past the cover. This leaves two strips of
deep water beside the island that never freeze.**
- **The arithmetic.** Pond columns 4 and 6 (x −409.82..−403.27 and −396.73..−390.18) in rows 4 and 5
  (z 122.67..136) have their centres under the island (x −408..−392), so they are not built.
  - Each sticks 1.82 studs out past the island's west and east faces.
- **The probe.** `w3dt_probe/holes.py` fills the Pond with every built piece plus every solid. It finds
  uncovered water at x −409.82..−408 and −392..−390.18, z 122.67..136: about 48 studs² in two slits of
  1.82 × 13.33.
  - The Creek is fully covered.
  - No swing can freeze those strips: `Chills` has no cell there, and `iceOnAuto` has no Part to aim at.
- **Failure.** A player crosses from the north, opens the chest, and walks off the island's west or east face
  onto ice he has frozen there (row 4 and 5 cells at columns 3 and 7 exist).
  - Between the island and that ice lies a 1.82-stud slot. A body facing along x (torso depth about 1) drops
    through it.
  - He is rescued to Road2 at (−385, 0, 2) and walks 130 studs back over his own ice to leave, or simply sees two
    water slits that no swing closes.
- **Why no gate sees it.** `sim_range.frozen_layout` (:5525–5531) freezes each ice block WHOLE. Its docstring
  says "the cells a colliding block or secret covers lie under that solid", which is false at a cover's edge: a
  covered cell may stick out by up to half a cell (3.5).
  - So check_levels' frozen variant and the harness walker (which stands on cell centres) cannot see the slits.
- **Fix.** Skip a cell only when the cover holds the WHOLE cell footprint (edges included), in LevelGeometry
  and in `ice_cells` alike.
  - A cell part-covered by the island is then built. Its top −0.8 lies inside the island's volume where covered,
    so it is invisible there.
  - Forest Road becomes 132 + 4 = 136 pieces (only the two cells of column 5 are fully under the island), Parts
    252 of 600.
  - Re-aim the harness check `tests_l2w3.luau:467` ("none under Road2 or the island" tests the piece CENTRE)
    and the `l2w3: a cover's edge is open` / `nothing covers the water` mutants to the whole-cell rule.
  - Add one (h) line that the union of the frozen pieces and the covers equals each ice block's footprint
    (the probe's test), so `frozen_layout`'s "whole block" stays true.

**m2. `tools/sim_range.py:156`: `FAMILY_TARGETS.frostHammer` still holds the contract's
`{"single": 68, "crowd6": 410}` and its comment "36 x 1.27 x 1.5 = 68".**
- §14 accepted the designer's swing (38 at 1.55, 120°), which measures single 75 (+10.3%) and crowd6 439 (+7.1%).
- So the family gate has 4.7 points of its 15% tolerance left on single, against a target nobody holds any more,
  and the comment states numbers that are not in the data.
- **Failure.** The next small hammer buff (for example rate 1.6, which gives single 77, +13%) passes, and one more
  step fails for a reason that is not real. Meanwhile a nerf that takes it to 60 (−12% of 68) also passes,
  although it is 20% under what Ben will feel.
- **Fix.** Set the targets to the measured rows (single 75, crowd6 439) with the derivation
  "38 × 1.267 × 1.55". Or say in the comment that the targets are the contract's and why they were kept.

**m3. `tools/check_levels.py:4172–4175` (`island_reach`, the lift branch): the span is
`lift_carry + dashDistance + castRange + BODY_RADIUS`, with no drop term.**
- A Leap Smash cast over the void lands at the caster's floor (`WallClip.CasterFloor`: feet − Rise, that is, the
  take-off top). He then falls to the key top − STEP_UP while walking at 20. That fall is not counted:
  - from a top at 0, the 3-stud step-up fall is 0.175 s, or 3.5 studs;
  - from LookoutLedge (34) it is 37 studs of fall, or 12.3 studs.
- The jumps branch carries this drop (`stray_reach(move, o.top − kr[4] + sag)`), and so does the dash branch
  (`air_carry(move, need)` with a negative need).
- Today's margin does not move (Impale Dash, 80.6, stays the worst; the Leap is 74.5). But a later island beside a
  ledge would be under-measured by up to the full fall.
- **Fix.** Add `move["walkSpeed"] * sqrt(2 * max(o.top - (kr[4] - STEP_UP), 0) / GRAVITY)` to the span. Add one
  mutant with the island next to a higher top that is red only with that term.

**m4. `tools/check_levels.py:4228` and `tools/check_levels_mutants.py:575–576`: nothing proves the walk-off grace
in (g)'s jump rule (`reachable_solids(..., grace=True)`).**
- The cases put the island at 45 (red) and 52 (green). The jumps reach 46.6 without the grace and 49.3 with it,
  and both cases fall outside that window.
- **Probe:** on a scratch copy with the island at 48, the shipped rule reads "reached ShrineIsland" (FAIL). With
  `grace=False` the same line PASSes, and only the ICE_MARGIN line stays red.
- The margin line covers the case today. But the jumps line's own grace term is unproven, which is the d-m1
  lesson of W2.
- **Fix.** Add the case "the island 48 from the sign pad (inside the grace, 46.6 < 48 < 49.3)", red on
  ICE_JUMPS.

**m5. `src/combat/server/Services/LevelService.luau:672–673`: `reachDown` and `ahead` are read from `rules.ice`
on lines that no test or mutant covers.**
- The text check `freezeCall` (run_harness.py W3_LINES) matches the call
  `WorldReact.Freeze(cells, element, fx, reachDown, ahead)` by name only.
- Swapping the two reads (`frost.ahead` into reachDown) keeps every gate green:
  - reachDown becomes 4, which still covers the bank's 3.8 down to the ice;
  - the reach becomes 9 + 6 = 15, so every swing freezes about 2 studs further than the config and the client's
    `iceOnAuto` say.
- This is the W1/W2 pattern again: "one shared call" whose arguments are copies.
- **Fix.** Add mutate.py entries that swap the two reads and that read `frost.lift` for one of them. Give the
  harness a check that the two locals come from `frost.reachDown` and `frost.ahead`, or have `freeze` pass
  `rules.ice` whole into a pure `WorldReact.FreezeWith(cells, element, fx, ice)` that the harness loads.

**m6. `tools/check_levels.py:4344` with `GROUND_LOOKS` at :172: the frozen sheet is never held to the "a landing
holds" depth rule.**
- `frozen_layout` gives the frozen blocks look `"ice"` and `thickness` 1. `check_kill_height`'s depth rule only
  judges looks ground, path, lobby and water.
- So the rule's own line "with the ice frozen, every block a body lands on … is at least levels.floorThickness 4
  deep" passes by not looking at the only new floor.
- The sheet is 1 stud thick and is the floor under a slam (140 studs/s, 0.58 studs a step at 240 Hz) and under a
  fall from the jumps' apex (about 110 studs/s). A 1-stud floor is exactly what E5's 4-stud rule was written to
  avoid, and only Studio can say whether it holds.
- **Fix.** Put `"ice"` in GROUND_LOOKS for the frozen check, and either set `levels.react.ice.thickness` to
  `floorThickness`, or record the lead's ruling that 1 is enough. The first is config only, because the piece
  hangs inside the 4-deep water block.

## Suggestions

**s1. `tools/check_levels.py:880` (`dashing_abilities`) finds dashes by the regex
`^\s*(\w+)\s*=\s*\{\s*target\s*=\s*"dash"` on AbilityService.**
- W3 adds the alias pattern `MECHANICS.frostQuake = MECHANICS.earthquake` (W2 already had `dragonBreath`).
- A later element family whose ability aliases `impaleDash` would carry players sideways and be invisible to (g),
  the cave's carry rule and the bend rule. Resolve `MECHANICS.<id> = MECHANICS.<other>` lines in the same reader.

**s2. `tools/check_levels.py:4202` (`check_ice`) re-runs the walls, the lookout, R8, the chord and killY on the
frozen layout, but not L2-47's bend rule (`check_route_skips`), check_cave's sealed air or the walled-camp gate.**
- On Forest Road the ice is 150 studs from all three, so nothing changes.
- A later level with ice near a bend or a cave would be judged dry only. Run the three on `frozen` too. It is cheap
  next to sim_range.

**s3. The shrine chest's material share sits at the band's top.** 63 Timber against `CHEST_MATERIAL_SHARE`'s 30%
of each cleared human run's Timber needs every run to earn at least 210. BALANCE reports a mean of 211, so the
gate has about 0.5% of slack. Any Timber change (a kill reward, a tent's stock, the clear bonus) turns
`check_first_run` red on the chest rather than on what moved. 60 (28.4% of 211, 27% of the stock) keeps "the
biggest chest" (it still beats the cache's 60 on Valor, 6 against 4). Or the lead accepts that the band's top is
the target.

## Checked and sound

- (g) jumps, lift, air dash and margin; (a)/(d) on the island; (h) reached, swing and chain; deep water; landing;
  `found`; the chain price from a map node; the ice config line. Each new check_levels rule has a red mutant
  and a green control where one is meaningful.
  - The re-aimed W2 case "the shrine names a family" still exercises the cycle: with `found` popped, ice resolves
    only through the shrine's own family, so broken cycle handling would turn it green.
- `ice_cells` matches `LevelGeometry.iceCells`:
  - the same `ceil(side / cell)` grid;
  - the same centre-under-cover rule, edges included, with tops strictly over the water's top;
  - covers are colliding blocks and secrets.

  Only the order differs: Python runs Z fastest, Luau runs X fastest, and only the names carry the order. The
  harness holds the count equal (132).
- The ICE_ROWS rule ((range + ahead − 1) / 1.5 = 8 ≥ 7) and the reachDown rule (Road2's root over the water, 4 ≤ 6;
  the ice top makes it 3.8) are conservative and correct for the chain's straight column.
- check_stage_mirror's L2 W3 cases accept the pool and refuse each broken line on both sides. mirror_mutants'
  five W3 entries target the Luau lines, and check_levels_mutants' two MIRROR_CASES target the Python lines.
- L2-39 pairs like with like: hammer with Frost Quake against Broadsword with Whirlwind. The Broadsword's
  "with ability" rows equal its "without" rows: the reacting player never casts Whirlwind on a boss.

## Runs (scratch `git archive HEAD` copy)

- `py tools/check_levels.py`: CHECK: PASS (about 35 s). The tightest (g) line reads "ShrineSignPad to ShrineIsland
  102.0 against 80.6 (spear's Impale Dash held in the air): +21.5". The chain is 16 cells, with 132 cells and 248
  Parts.
- `py -3.12 tools/sim_range.py --check`: CHECK: PASS, EXIT 0. A duplicate second run was stopped by its own PID.
- **Hammer rows:** single 75 in [58, 78] and crowd6 439 in [348, 471] (the band is built on the stale 68/410, m2).
- **Boss rows**, the hammer's fastest seed against the Broadsword's slowest (L2-39, all PASS, no boss hit landing):

  | Boss | Frost Hammer | With Frost Quake | Broadsword's slowest |
  |---|---|---|---|
  | Colossus | 83.2 s | 83.7 s | 77.2 s |
  | Warlord | 102.9 s | 101.0 s | 98.1 s |

  These follow from the data (38 × [1, 1, 1.8] at 1.55; Frost Quake one 30-damage ring). The finisher, 68.4, is the
  only heavy hit (38 < `heavyHit` 40), and the plate breaks in 6 hits.
- **Frost Hammer + Longbow on Forest Road**, Normal 2/2:
  - clears in 4.46, 4.69 and 4.43 min with no down;
  - earns 29,178 a minute against the Broadsword pair's 30,859 (×0.95);
  - kills the Colossus in the run in 82.1 s against 76.4 s.
- **The crossing:** 9 swings and 109 studs; 9.0 s for a human, 5.8 s ideal.
- **The chests:** the shrine is 63 Timber = 30% / 30% / 30% of 211 / 211 / 211 (s3); the cache is 28% and the lookout
  24%.
- **Probes** (session scratchpad):
  - `w3dt_probe/holes.py` (m1);
  - the island at 48 with the shipped (g) and with `grace=False` (m4).
