# L4 W2 review, slice 4: data, simulators and gates

Reviewer: roblox-reviewer (Opus), 2026-10-22. Diff `37ccfe4..afdce67`, restricted to slice 4 (the brief's table: Config,
`sim_range.py`, `check_stage_mirror.py`, `check_levels.py`, `check_levels_mutants.py`, `raider_frames.py`, `tools/levels/*`,
the harness files, `docs/BALANCE.md`). Read only. Every probe ran on a `git archive afdce67` copy in the reviewer's
scratch folder (`scratchpad/l4w2s4/tree`; `assets` linked read-only to the main checkout's for the GLB readers). Python
numbers are from `py -3.12` (3.12.10, 64-bit, the gate's) unless said otherwise.

**Count: 0 Critical, 1 Major, 4 Minor, 3 Suggestions.**

## Major

### M1. R8's gate holds a sword-only fight half to a sword-and-bow player, so its verdict is the weapon gap, not the spot

`tools/sim_range.py:11292` (`R8_FIGHT = "sword"`), used at :11465 and :11476 (`like = ...`) and gated by `r8_check`
(:11527); `docs/BALANCE.md` "R8 judged fairly"; the two SIM_CASES in `tools/check_levels_mutants.py` (L4W2-13).

**What is wrong.** The lead's ruling moved the reference to the pair player ("the same gear": sword and bow). The
sniper's own run still fights everything but the spot with the sword alone (`R8_FIGHT` "sword", the contract's
first "then `mission`"). The gated ratio is therefore the sword-to-pair ratio plus whatever the spot adds:

| Table | sword alone / pair (BALANCE) | gated spots that shoot nothing | gated best spot | the spot must add, to go red |
|---|---|---|---|---|
| Hard, sword T1 / bow T4 | 24,019 / 39,183 = 0.613 | x0.574-0.595 | Road3 x0.621 | +61% over a whole run |
| Normal, sword T1 / bow T4 | 26,543 / 40,226 = 0.660 | | x0.637 | +57% |
| Hard, T1/T1 | 24,019 / 29,615 = 0.811 | | Road2 x0.803 | +25% |
| Normal, T1/T1 | 26,543 / 30,729 = 0.864 | | x0.842 | +19% |

The faithful reading of Ben's words ("shoot what you can from it, then fight the rest" against "fighting it all with
the same gear": both runs alike but the spot) is `--r8-fight pair`, and it is not gated. It passes on all four tables
(`--r8 --check --r8-table <t> --r8-fight pair --jobs 6`, seeds 1-30, CHECK (R8): PASS each):

| Table | Tightest spots under the faithful reading | Its margin | The gate's margin |
|---|---|---|---|
| Hard, T1/T1 (my probe, 16 min) | Road3 **x0.987** (10 seeds out-earn), Road2 **x0.985** (14), CaveMouth x0.973 (11) | 1.3% | 25% |
| Hard, sword T1 / bow T4 (D1's run) | Road3 **x0.982** (13), Road2 x0.977, Road4 x0.975 | 1.8% | 61% |
| Normal, T1/T1 (my probe, 6.5 min) | CaveExit x0.968 (7), Road4 x0.959 (4), Road3 x0.953 (3) | 3.2% | 19% |
| Normal, sword T1 / bow T4 (my probe, 4 min) | Road4 x0.943 (1), Road2 x0.928, Road3 x0.927 | 5.7% | 57% |

The spots that shoot nothing read x0.81-0.96 under the faithful reading: the cost of the walk to the spot and back.
The two SIM_CASES move the rate by x18.7 and x7.43 (the clock). Neither shows that the gate can see a spot that earns
a little more.

**Failure scenario.** Road3 on Hard at sword T1 / bow T4 was red before L4 on 12 of 30 seeds and is the row the
contract made a merge blocker. Any later change that lets the spot pay a few percent more (a Longbow damage or pierce
tweak, a camp A post moved so one more west group comes to the plateau's edge, a shorter `SNIPER_IDLE_SECONDS`) takes
the faithful row over x1.0 while `--r8 --check` stays green at about x0.63. By arithmetic, any change that multiplies
the sniper's whole-run pay by up to 1.6 is green on that table. This is the "gate passes for the wrong reason" family
that was Major in L3 W1 (the pair gates scaled by the slot's gear).

**Fix.** Make the gate the faithful reading: `R8_FIGHT = "pair"` (the same runtime; `_r8_task` already gives the
pre-snipe course and the fight half the pair when `policy["pair"]` is set). It passes today on all four tables
(above), so the switch costs no data change. Keep the sword-fight runs printed if wanted. If the lead ruled the sword
half deliberately, gate the faithful reading as a second line beside it. Add a sensitivity SIM_CASE sized to the
faithful margin: for example the sniper's whole-run cash raised 3% (`r8_rate`'s numerator) on Hard Road3 T1/T1 must
turn red. The two clock cases stay.

## Minor

### m1. The Chief's sweep `range` 17 was reconciled against a hammer point behind his shoulder, outside the wedge

`src/shared/Config/ProvingGrounds.json:71`; `tools/testfit/raiderpose.py:916-954` (`IMPACT_SLACK`, `impact_reach`);
BALANCE row "the Chief's sweep (attack 4)".

**What is wrong.** raiderpose's weapon rule takes the hammer's farthest flat reach anywhere during the strike (17.10)
and checks only `reach <= range + 0.5`. My probe (raiderpose's own rig and the Chief's GLB vertices, 51 samples over
the strike and the recover, angle 0 = his front -Z, + = his right): the 17.10 is at u 0.2 at 105-180 degrees, behind
his right shoulder. Inside the 150-degree wedge (+-75) the farthest hammer reach is:

| sector (deg) | -75..-45 | -45..-15 | -15..15 | 15..45 | 45..75 | 75..105 (outside) | 105..180 (outside) |
|---|---|---|---|---|---|---|---|
| farthest flat reach | never swept | 14.43 | 14.51 | 15.08 | 16.35 | 17.05 | 17.10 |

The follow-through ends at about -30 degrees, so the hammer never enters the wedge's left 45-75 degrees.

**Failure scenario.** A player 15-17 studs straight in front of the Chief, or anywhere 45-75 degrees to his left within
17, takes the 30-damage sweep (knockback 30) while the drawn hammer stops 2.5 studs short of him or never comes his
way. The ground wedge is the true tell (it draws the hit shape), which is why this is Minor. But contract risk 4
("reconcile the hammer against the sweep") was met with a sample outside the wedge, and raising 16 to 17 widened the
in-wedge gap. (Slice 3's M1 asks `impact_reach` for a lower bound on shapes with no ground tell, the lunge; the arc
has its wedge, so this one is about where the upper bound is measured.)

**Fix.** In `impact_reach`, measure only weapon points within the attack's arc (|angle| <= arcDegrees / 2), and add
the other direction: every 15-degree sector of the wedge is swept within `range - slack` during the strike. Then either
carry the sweep's follow-through to about -75 degrees (the Chief's `arm.shapes.arc.follow` in `raider_kit.py`, one
regenerated config and no re-upload, since the pose is config) or narrow the hit to what is swept (range about 16.4).
Re-measure the Chief's bands after.

### m2. LevelService's dress decisions and gather's seat input are unpinned: six probes pass the harness

`tools/crowd_harness/run_harness.py:1689-1780` (`L4W2_LINES`, `L4W2_ORDER`), held by `tests_l3_w2.luau` `L4BP.W2`; the
code at `LevelService.luau:696, 710, 751, 756, 778` and `WeaponService.luau:828`.

**What is wrong.** The pins count the lines that act (the SetAttribute calls, the SeatDrop call, the warn), not the
branch that decides whether they run. Each probe below was applied to the archive and the harness re-run:
**`HARNESS: PASS (4,412 checks)`** every time.

| Probe | Edit | What ships |
|---|---|---|
| P1 | `:778` `if dressed ~= nil and layoutName ~= nil and planHash ~= nil then` -> `if false then` | the server hides every skinned piece (Transparency 1) and arms the 70 walls, but never sets `Dress`: no client draws the forest, so the ground and the walls are invisible everywhere (the state L4W2-2/-3 exist to prevent) |
| P2 | `:696` `if state.failNextDress then` -> `if true then` | every level grey forever (the Z lever latched on) |
| P3 | `:751` `if layoutName ~= nil then` -> `if false then` | no level is ever dressed |
| P4 | `WeaponService.luau:828` `local restDrop = config.crowd.restDrop` -> `= 0` | L4W2-11 undone: seated heads judged standing, the SeatDrop call line still counted |
| P5 | `:756` `if accepted ~= nil then` -> `if false then` | the accepted dress ignored |
| P6 | `:710` `if accepted == nil then` -> `if false then` | a refusal returns the hash and skips the warn |

This is the W1b family again (slice 1's verdict condition, slice 2's `if cellsWent then`).

**Fix.** Put the decisions in the pure, tested module: for example `LevelDress.Announce(accepted, layoutName, planHash)
-> (string?, string?)` used by Build, and the lever's hash as a pure `LevelDress.HashFor(uploaded, fail)`. Pin what stays
in LevelService whole with its indentation (`\tif dressed ~= nil and layoutName ~= nil and planHash ~= nil then`,
`\tif state.failNextDress then`, `\tif layoutName ~= nil then`, `\tif accepted ~= nil then`, `\tif accepted == nil then`,
`\tlocal restDrop = config.crowd.restDrop`), and add a mutate entry for each of P1-P6.

### m3. Camp C's sight gate keeps the widest kind per post, then draws that kind's model

`tools/check_levels.py:3353` (`walled_bodies`) and `:3690` (`drawn`).

**What is wrong.** A post used by several difficulties keeps the kind with the largest `radius`, and the sight gate
then reads that kind's `posedReach`. The two orders differ:
- slinger: radius 1.2, drawn 4.51 with its orb;
- fodder: radius 1.3, drawn 2.66;
- armoured: radius 1.7, drawn 5.41;
- brute: radius 2.2, drawn 4.77.

**Failure scenario.** A walled camp (later levels reuse this gate) with fodder at a post on Normal and a slinger there
on Hard keeps the fodder. Its drawn body is under-measured by 1.85 studs, more than `sightMargin` 1.5, so the gate
passes while the slinger's raised orb shows through the gate. The shipped camp C holds fodder and brutes only, and the
brute wins both orders, so nothing ships wrong today.

**Fix.** Keep per post the largest `drawn_body(ctx, kind, factor)[0]` (with its label), not the largest radius. Add a
CASES mutant: a slinger on one difficulty at a fodder post goes MARGIN red.

### m4. The simulator's seat is two hand copies with no mirror

`tools/sim_range.py:8101-8109` (`LevelRun.seat_goal`) and `:2470-2488` (`step_seats`).

**What is wrong.**
- `seat_goal` re-derives CampBrain.Shows' `rest` branch: resident, held or resting group, not moving, `fire` posture.
  The mirrored `cb_shows` (:7357) is not called.
- `step_seats` re-implements HitShapes.SeatStep, with `max(blend, 1e-3)` in place of SeatStep's "no pace: at once".
- check_stage_mirror compares SeatDrop and CrowdRay's drop only. No SeatStep op, no seat timeline.

They agree today (read, not run).

**Failure scenario.** A later Shows change (a patrol shown `rest` at its stop) or a SeatStep pace change moves the
server's seated heads. The sim keeps the old ones, so the bands' headshot counts drift with every gate green.

**Fix.**
- `seat_goal` returns `1.0 if cb_shows(group, e.moving) == "rest" else 0.0`.
- Add an `hs_seat_step` that `step_seats` calls, and a `seatStep` op in `stage_mirror.luau` against HitShapes.SeatStep,
  with its rows in check_stage_mirror.
- Add two mirror mutants: SeatStep's pace doubled, and no pace = never moves.

## Suggestions

- **s1. R8's tunnel spots are judged at the proving gear only** (`sim_range.py:11449`, `r8_courses(report, cfg, not
  bow)`). A player who found the cave can bring the bow at T4 on a later run. The scope is unchanged from L3 W1 (not
  a regression).
  - My probe (a copy with `r8_courses(report, cfg, True)`, Hard sword T1 / bow T4, CaveMouth): **x0.964** of the pair
    under the faithful reading (7 seeds out-earn), x0.605 under the gate's sword half, x1.573 of the sword alone.
  - It passes, but it is the same family of spot as Road3. Add the open tunnel to the two bow tables (CaveMouth and
    CaveExit without the Breath, which the bow kit cannot cast).
- **s2. The walls' "can" checks are mostly implied by the ground rule.** Every route, sneak and shortcut leg runs on
  ground, so a wall that crosses one also fails "no dress wall reaches into ground" (the Road2 mutant names both Road2
  and CreekUp). The checks that stand on their own are the gap leg and the lookout's flight. Worth one line in
  check_walls' docstring, so nobody later removes the ground rule thinking the path checks cover it.
- **s3. `path_blocked` judges a leg at `max(feet(a), feet(b))`.** On a leg that drops, a wall whose top lies between
  the two heights is not counted as blocking, which is lenient for a "can" claim. The shipped legs are flat (every
  route point is at y 0), so nothing changes today; use the lower foot, or both.

## Checked and clean

- **The Chief's data** (`ProvingGrounds.json chief`) matches the contract's §4:
  - the Colossus's 14 / 4 / 1.6, speed 9, hp 4,700, no knockback, rush, boss;
  - enrage 0.5 / x0.8 / x0.7 / chain 2;
  - `ring` and `lane` as the Colossus's, `summon` of 12 fodder (reserve 13, harness pinned);
  - the arc with base damage 30 (at most 33), 4 attacks (at most 7).
- **His model** is built for 14 / 4 / 1.6. `raider_frames.py` and `raiderpose.py --check` both refuse a mismatch.
- **The level file:** `Levels/1_ForestRoad.json` has boss `chief` with reward 42,900 / 76 and Valor 10. Contract §11's
  greps are empty. The hand-written Colossus fixtures stay (`check_stage_mirror.py:202, 209`).
- **The other config keys:**
  - `crowd.restDrop` 0.35 and `riseBlendSeconds` 0.5, in Tuning's non-negative list with their mutants;
  - `Combat.json debug.dressFailAttribute`;
  - `Expeditions.json keys.castle` and `moods.forestRoad`, keyed by the level id `forestRoad` (the contract's start
    values exactly).
- **The Castle Key data:**
  - `secrets.mountain.key` "castle";
  - the key line (1-24 bytes) mirrored in `sim_range.secret_problems`, with three refusals in check_stage_mirror;
  - the client's key name falls back to "<Id> Key" without an entry, and a harness case holds the shipped entry.
- **`raider_frames.py --check --require-harvest`: PASS**, rerun with `-B`.
  - 7 of 7 models proven; 84 MeshParts placed by `gen_templates.template_placement`, inside and filling their piece's
    bounds; 672 sidecar corners come back through `weapon_frames.prove`.
  - The guard: 35 of 35 stages fail unturned.
  - The template's Base sits at the origin, feet at 0. The proof is real: it would catch a lost turn and a mirrored arm.
- **`check_raider_mirror.py --mutants`** (rerun on the archive):
  - CHECK: PASS, 16,806 cases, real `RaiderPose.luau` under luau.exe;
  - MUTANTS: PASS, 14 of 14 red;
  - Rig smoothsteps the seat before the drop, as SeatDrop does.
- **check_stage_mirror's seat rows and mirror mutants:**
  - SeatDrop is compared on seats -0.25 to 1.4 with the guard rows, and CrowdRay at half and full seats;
  - `mirror_mutants.py --only SeatDrop` gave 2 of 2 caught (rerun).
- **check_levels' walls** (`check_levels_mutants.py --only "L4W2-14"`, rerun, 5.5 min): MUTANTS: PASS, all nine as
  expected.
  - `barrier` Solids appear only in check_walls; every "cannot" gate runs on the grey level.
  - Walls are in `is_tall`, the Parts count (334 of 600) and the unclimbable rule (tightest TreeLine2, 50 over).
- **The mountain climb is untouched by the walls.**
  - The yard walls (TreeLine1, 18, 37, 55, 56, all top 280) stand on the yard's edges.
  - Any wall inside the yard or over a ledge fails the ground rule, because the generator's walls start at y -15.
  - check_parkour's `wallTop` is forest.py's own constant (CLIMBS).
- **R8 wiring:**
  - `r8_rate` and `pay_rate` are the same whole-pay-over-whole-minutes;
  - "never turned to the spot" and "every hit from the spot lands" are gated;
  - `--r8` runs without `--check`'s R8 and keeps F6 and R2 there;
  - workers run only from the file (`r8_poolable`).
- **The hub is untouched in behaviour.**
  - No `src/server` or `default.project.json` change.
  - The Theme changes are new `COMBAT_*` / `MAP_*` keys plus `COMBAT_PERF_WIDTH` (combat only).
  - `MapScreen` is required only by the combat place's CombatUIController.
- **`combat.project.json`:** only `ServerStorage.Enemies` goes (W1b row 19). `templates/_enemies` stays in
  `globIgnorePaths`, which is harmless.
- **Changed tests are text only:** `tests_l1b_w2`, `tests_l1c`, the `tests_s2` tuning cases (lending the keys and
  restoring them), and `tests_l3_w2`'s `L4BP.W2`.

## Probes (reviewer's scratch, `scratchpad/l4w2s4/`)

- `r8_hard_pair.txt`, `r8_normal_pair.txt`, `r8_normalbow_pair.txt`: `--r8 --check --r8-table <t> --r8-fight pair
  --jobs 6` on the archive, `py -3.12 -B` (not `-I`: sim_range imports `check_levels` from `tools`).
- `r8_hardbow_cave_{pair,sword}.txt`: the same on a second copy whose bow tables include the open tunnel.
- `hammer_sector.py`: the Chief's hammer per sector over the strike and the recover (raiderpose's `rig`,
  `model_points`, `hold_frame`).
- `probe.py` + `mk1.py`: the six harness probes of m2 (27 s for the base run, 2.5 min for all six).
- `check_levels_mutants.py --only "L4W2-14"`, `check_raider_mirror.py --mutants`, `mirror_mutants.py --only SeatDrop`,
  `raider_frames.py --check --require-harvest`: rerun, results as listed under "Checked and clean".
