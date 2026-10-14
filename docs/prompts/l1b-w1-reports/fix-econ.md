# L1b Wave 1 fix round — economy-designer

Brief: `docs/prompts/l1b-w1-fix-round.md` "economy-designer". Base e2479c3. Filled as I go.

## Status
- DONE, every gate green (below). Nothing of this section was done before the round.

## 1. chaseMargin gate, rounded corners, perches (done)
- `Combat.json camps.chaseMargin` 3 -> 2.5 (limit: fodder lunge 4.5 - sqrt(2) x 1.3 = 2.66).
- `sim_range.cb_in_play` + `LevelRun.near`: flat distance to the floor rectangle <= chaseMargin
  (`cb_rect_distance`, same arithmetic as A's `CampBrain.InPlay`).
- `check_stage_mirror.py` InPlay grid: rounded-corner targets (45 and 30 degrees, margin -+1e-7,
  margin/2) at all four corners. Proof: a CampBrain copy with square corners -> 32 of 32 InPlay differ.
- `check_levels.py`: the chaseMargin gate is reach - sqrt(2) x radius for every rusher resident in
  an open camp at every difficulty; NEW perch gate: every standable top (blocks, fences, obstacles,
  secrets, other floors) within chaseMargin of an open camp's floor whose standing root is in the
  height band stands at most (lowest rusher ground-shape height - 0.5) over the floor (A and B: 4.5;
  the fence is 4). Proved in memory: margin 2.7 fails, 2.66 passes; a 5-tall block 1 off A fails,
  4.5 tall passes, 3 off passes; a block 2.12 off A's corner fails, 2.83 off passes.

## 2. engagedHoldSeconds (done)
- `Combat.json camps.engagedHoldSeconds` 1.5. `CB_RULE_KEYS` gains it; `cb_engaged` mirrors
  `CampBrain.Engaged`; LevelRun holds `engaged` with it. Mirror: an `engaged` case (nil, the edge
  either side, 60 s) + Problems rows (missing, -1). Proof: a no-hold CampBrain copy -> 1 of 1 differ.

## 3. Checkpoints out of shooters' reach (done; data moved, not the checkpoint)
- New `check_levels.py` gate: every open camp's checkpoint is farther than every resident keepAway
  member's longest reach from its post (a patrol: its loop), every difficulty. Before the data change
  it failed for A (Hard B.fire1 marksman 44.6 from (16,-42)) AND B (B.fire2 lobber 37.0 on Normal,
  marksman 33.8 on Hard, from (150,-42)).
- A's checkpoint could not move: RoadAB is 44 long, A.fire2's slinger (32) and B.fire1's marksman (48)
  leave no point on it. B's cannot move far enough east (RoadBC1 ends at x 164). So the shooters moved
  inward (`1_ForestRoad.json` B residents, layout spots):
  - B.fire1: Hard marksman -> Hard armoured (taken from `loop`); `loop` is 5 fodder (data Minor 6:
    one pace, no conga line).
  - B.fire2: lobber and Hard marksman leave (fodder 4 + slinger stays).
  - B.southWatch: + 2 Hard marksmen; two guard points added at (96,-2) and (80,-2).
  - B.fire3: + the lobber; radius 5.5 -> 6 and centre (100,-64) -> (100,-64.5) (7 on Hard need
    2 x 2.2 + 0.5 of chord; the loop leg at z -54 stays 4.5 clear as before).
  - Totals unchanged: B 28 Normal / 34 Hard; 3 marksmen and 1 lobber on Hard as before.
  - Nearest now: A's checkpoint 40.0 from A.fire2's slinger (32); B's 34.1 from B.fire2's slinger (32).
- For the lead (docs): PLAYTEST/INTERFACES lines naming "B.fire1's marksman" or a lobber at fire2 are stale.

## 4. clearBonus mirrored fully (done)
- `sim_range`: `pay_clear_bonus()` paid on `campClear` and on a locking camp's `open` unless
  `skipped`; `leave_camp(t, skipped)`, skip paths emit `skipped=True` (B's `Action.skipped`).
- `check_stage_mirror.py`: `skipped` is an action field compared (bool). Proof: B's stage-skip
  `leaveCamp(..., true)` -> false gives Skip 4 of 8 differ. (The boss skip's passed-camp `open` cannot
  occur on Forest Road: its only camp stage is the boss room.)
- `sim_combat.level_pay`: + clearBonus x rewardMult per open camp holding a resident at that
  difficulty and per locking camp.

## B's SafePoint threats mirrored (needed for the mirror to stay a gate)
- `sim_range.safe_point(busy, threats)`, `LevelRun.threats()` (living members of rise/fight groups,
  `longest_reach`), the road-down placer passes them. Mirror: busy cases `threatAll` (a threat 5 off
  every checkpoint, reach 5) and `threatShort` (reach 5 - 1e-6). Proof: `<` for `<=` and threats off
  -> 366 of 1067 SafePoint differ each. `StandsUp` is not mirrored (listed by the tool).
- `1_ForestRoad.json` now writes `"clearBonus": { "cash": 0, "materials": 0 }`.
- Scratch proof (in memory, bonus 1,000 cash / 5 Timber): `sim_combat --check` 23/23, assertion 21
  Normal 63,800 = 60,800 + 3 clears x 1,000; every cleared run paid exactly the file's sum.

## 5. BALANCE "L1b" and the sims' label (done)
- Bands: Normal first clear 2.5-4 min (the lead's ruling, option c): 3.00-3.13 min PASS; the stale
  "5-8: FAILS" rows and the "lead must choose" flag replaced; `sim_range` label prints `:g` (2.5-4).
- Hard patrol pace: solved in data (the loop is 5 fodder; the plated elite went to B.fire1).
- Flag for Ben: Normal pays ~42 Timber/min against L1's ~24 (+~75%), cash +46%/min.
- Values table: chaseMargin 3 -> 2.5, engagedHoldSeconds 1.5, clearBonus; who-lives-where updated.

## 6. Carried to Wave 2 (in BALANCE "L1b: open, carried to Wave 2")
- Post spacing gated beyond fires (data.md Minor 7); a per-minute pay band.

## 7. Gates (after A's and B's edits as of the end of my run), all with the worktree as it stood
- `py tools/check_levels.py`: CHECK PASS.
- `py tools/check_stage_mirror.py`: CHECK PASS (SafePoint 1,067 compared incl. threats; Engaged; InPlay corners).
- `python tools/sim_range.py --check` (3.12): CHECK PASS. Forest Normal clear 3.00/3.08/3.13 min,
  0 downs; Colossus alone 76.3 s; edge 228 blocked, 0 paid; pay unchanged 60,800 / 129 / 10.
- `python tools/sim_combat.py --check`: 23/23. `python tools/sim_economy.py --check`: PASS.
- Not run (as told): the crowd harness, mutate.py. B: the harness reads the real Forest Road data, and
  B's residents moved (no test pins them, checked by grep); please confirm in your harness run.

## For the lead
- Docs naming "B.fire1's marksman", a lobber at B.fire2, or A/B checkpoints' nearest shooter are stale
  (PLAYTEST / INTERFACES layout text). The checkpoints themselves did not move.
- No `Economy.luau` change needed.
