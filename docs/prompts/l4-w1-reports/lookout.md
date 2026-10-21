# L4 W1 track D: the lookout at the trailhead (economy-designer report)

Worktree `tycoon-p5`, branch `l4-real-forest` (HEAD 59a2279 when measured), 2026-10-21. Nothing committed.

## Summary

- The lookout is at the trailhead (V3). The chain is unchanged. check_levels, the crowd harness, check_stage_mirror
  mutate.py (`files:`) and check_levels_mutants (all 269 cases) pass.
- `SNIPER_KNOWN_LIMIT_L4` is **removed** with its reader and `r8_gate`'s exemption branch (my call: an empty dict
  would be dead code). On **Normal** every remaining spot is now green on all 30 seeds I ran, at both gears.
- **`sim_range.py --check`: FAIL (1)**, one row: Hard, sword T1 / bow T4, the sniper from **Road3**, seed 11,
  x1.60 the mission's cash a minute. The cause is removing the LookoutSignPad *region cell*. But the row was
  already red on 12 of 30 seeds at HEAD, and Road2 on 10 of 30; HEAD's three gate seeds just missed it. No honest
  data fix exists in my files. **The lead must pick an option** (below). I did not apply the one that only
  restores the gate seeds' luck.

## Layout change (done first; `layout-ready.md` written)

File: `src/shared/Layouts/Levels/ForestRoad.json`. The brief named `Config/Levels/1_ForestRoad.json`, but that file
holds the level's rewards and stages and names no position; it is unchanged.

- `LookoutLedge`: (-283, 15, -59) 24x38x14 -> **(-446, 11, -33) 24x30x14** (x -458..-434, z -40..-26, top 26 over
  Road1, foot -4); same place in the block list.
- `lookout` chest: (-283, 36, -59) -> **(-446, 28, -33)**.
- Its sign: (-301, 8, -57) -> **(-447, 0, -5)**. This is my one departure from the study's (-447, 0, -2).
  LevelGeometry builds a 6 x 4 x 6 walk-through block there ("a sign is read, never stood on: it must not narrow
  the road", `LevelGeometry.luau:1117`). At z -2 its foot (z -5..1) stood across the walking line 23 studs from
  the spawn. At z -5 the foot (z -8..-2) sits flush with Road1's north edge, on the ledge's side, as the cache sign
  sits on Road4's. check_levels: "169 of 169 samples, 5 studs from the route".
- `LookoutSignPad` block and its `plateau` region cell removed (the cell was a leaf, so the region stays a tree).
- Reads: the ledge stands 18 studs north of Road1 across open void. Double Jump reaches it. One jump, a step up and a
  dash fall short: "the closest call: Trailhead, 5 studs short". No lifting ability's arc lands on it (L2-18c; the
  margin over the shipped Leap Smash is 13 studs, measured). **For the forest kit lead:** the tree-line wall along
  Road1's north side must leave that gap open (x -458..-434), or nobody can reach the chest.

## Gates (verdict lines; Python named)

| Gate | Verdict |
|---|---|
| `py -3.12 tools/check_levels.py` (3.12.10) | `CHECK: PASS` (21.7 s) |
| `py -3.12 tools/check_levels_mutants.py` (3.12.10; run as its CASES+MIRROR part and its ten SIM_CASES in parallel, the same cases) | `MUTANTS: PASS` for every part: CASES+MIRROR 259 ok, 0 NOT (shipped data, 245 cases, 13 mirror cases; 13:09-15:01 under load); SIM_CASES 10 of 10 ok (d3, L3-29, the new L3-26 band, R2 x5, F6 x2). Their FAIL counts include the shipped Road3 row; each named line is its own |
| `py -3.12 tools/sim_range.py --check` (3.12.10 64-bit, "the gate's") | **`CHECK: FAIL (1)`**, 11 min 46 s; clean HEAD copy: `CHECK: PASS`, 12 min 27 s |
| `py tools/check_stage_mirror.py` (shebang: 3.12) | `CHECK: PASS` |
| `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 .../luau.exe` (no shebang: 3.14; verdict from luau) | `HARNESS: PASS (4,032 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)` |
| `py tools/crowd_harness/mutate.py <repo> <luau> "files:ForestRoad.json,tests_l2.luau,check_levels.py,check_levels_mutants.py,sim_range.py"` | `BASELINE: HARNESS: PASS (4,032 checks, ...)`, `MUTATIONS: 0 run, 0 not caught` (no entry mutates these files: data and tests are never mutated) |

The clock is unchanged: Hard 5.22 min (+0.1% of 5.21), Brutal 5.24 min (+1.0% of 5.19), byte-identical lines.
Every sim_range gate line other than the lookout spots, Road3, Road4 and CaveMouth is byte-identical to HEAD's.

## R8, before and after (gate seeds 11 / 23 / 37; best ratio to the mission's cash a minute)

| Table | Spot | HEAD | Now |
|---|---|---|---|
| Normal T1/T1 | Secret_lookout / LookoutLedge / LookoutSignPad | x1.59 / x1.35 / x0.54 (known limit) | gone |
| Normal sword T1 / bow T4 | the same three | x1.66 / x1.37 / x0.54 (known limit) | gone |
| Hard T1/T1 | LookoutLedge / LookoutSignPad / Secret_lookout | x1.30 / x0.93 / x0.62 (known limit) | gone |
| Hard sword T1 / bow T4 | Secret_lookout / LookoutLedge / LookoutSignPad | x4.44 / x4.13 / x2.09 (known limit) | gone |
| Hard T1/T1 | Road3 | x0.87 (seed 11: 20,288) | x0.87 (seed 11: 14,082) |
| **Hard sword T1 / bow T4** | **Road3** | x0.79 (seed 11: 8 kills / 13 s) | **x1.60 RED** (seed 11: 16 kills / 13 s: 39,504 / 55.1 against 24,703 / 37.2) |
| Hard, tunnel open | CaveMouth | seed 11: 0 | seed 11: 19,164 (x0.78); its "nearest point" rows gone (one point now) |
| all tables | Road4 | x0.06 / x0.15 | 1-4 cash lower (timing) |
| all tables | Road2, the gatehouse, RoadBC5/6, ShrineSignPad, Creek, CaveExit | | byte-identical |

## The finding: Road3 (and Road2) on Hard with only the bow at T4

**Cause, isolated.** I probed sim_range's own `LevelRun` and `sniper_spots_of` on in-memory variants of HEAD's
layout. Dropping only the LookoutSignPad **region cell** reproduces the new Road3 rows exactly. Dropping the block as
well adds nothing, and moving only the ledge changes nothing. The cell was one of the sim's sight blockers
(`scene_walls`: every region cell blocks a line under its top) and a place chasing bodies stood. Without it, on
seed 11 camp A's fireN group reaches the plateau's west edge in Road3's view inside the 13 s window, beside fireW.

**It was red before, hidden by the seeds.** The same course over seeds 1-30. A seed counts when its cash or Timber a
minute beats the lowest of the three gate-seed mission rates (Normal 24,986 / 40.1, Hard 21,332 / 31.9):

| Course | HEAD | Now |
|---|---|---|
| Hard, bow T4, Road3 | 12 of 30, worst 67,179 (26 kills in 13 s, x3.1) | 13 of 30 (seed 11 added) |
| Hard, bow T4, Road2 | not run | 10 of 30, worst 47,489 (x2.2) |
| Hard, T1/T1, Road3 | not run | 7 of 30, worst 21,352 (x1.00, marginal) |
| every other spot on Hard, both gears | not run | 0 of 30 |
| **every spot on Normal, both gears** | not run | **0 of 30** |

The mechanism: from Road3's corner (-340, 0, -51), 38 off and 8 below the plateau (and from Road2), the straight
course pulls camp A's west groups to the plateau's edge. With the x6.74 bow it kills one, two or three groups in
13 s, and then nothing lands for 10 s. That pays 4-14K once (camps never refill), but as a rate it is x0.8-x3 the
sword-T1 mission player's. It is L3's structural point (BALANCE "L3 W1: R8") at a spot that is not a perch. No wall
can stand between the low road and the plateau's edge without standing on Road4, and a body stopped at the region's
edge is always in view from below.

**Options for the lead** (all measured, none applied):

1. **Plateau nub**: add the block `{"name": "PlateauNub", "look": "ground", "x": -299, "y": 2, "z": -57, "sx": 6,
   "sy": 12, "sz": 10}` and the plateau cell `{"id": "PlateauNub", "x": -299, "z": -54, "sx": 6, "sz": 16}`. Measured
   in memory: check_levels PASS with the same pinned lists (it is no perch), and Road3's gate seeds are back to
   HEAD's 8 / 8 / 3 kills, so `--check` would pass. It **only restores the gate seeds' luck**: Road2 and Road3 still
   out-earn on about a third of seeds. It also adds a purposeless bump the forest kit lead must dress.
2. **Ben rules** on the Hard bow-T4 burst from the low road (a one-off 4-14K in 13 s). This is a known limit again,
   against "empty before L4 ships", so it is his call.
3. **R8 measures a burst differently** (`sim_range.py`, my file, but it changes the gate's meaning): more seeds,
   or pay against what the mission player earns from the same residents. Needs the lead's and Ben's OK.
4. **Camp A's design** in the real forest (26.2's natural edges, the west fires' posts), so one pull from the road
   wakes one group, not three. This is forest-wave work, with every camp gate re-run.

## Other changes

- `tools/check_levels.py`: the four pinned sniper lists without LookoutLedge, LookoutSignPad and Secret_lookout, plus a
  comment saying why. One docstring (`island_reach`) no longer calls 34 "LookoutLedge's".
- `tools/sim_range.py`: `SNIPER_KNOWN_LIMIT_L4` and its exemption removed; the comment above it now records the
  ruling; the stale `sniper` policy label ("then from the lookout ledge") and its comment now describe R8's course;
  `BREATH_OUT_OF_REACH`'s CaveMouth note re-measured (26.6 studs, one point now).
- `tools/check_levels_mutants.py`: L2-18a/b/c/d, the ridge (CaveWallS1 54 red / 55 control, plus 80 with L2's
  lookout put back), the frozen pond, the d-M1 ridge cases (`l2_lookout` puts L2's ledge back: they were measured
  from it), and SIM_CASE L3-26 (now a band at half the mission's pay; Road3's Normal bow-T4 row, x0.72, must go
  red). The table is in BALANCE.
- `tools/crowd_harness/tests_l2.luau`: realTests' "from the road below" case reads the road from the layout's route
  point nearest the chest instead of the literal 8 (with the old 8 under the new ledge it fails: proven red, then
  green). The three pure WallClip tests keep their numbers (rise 26 still holds); only their comments changed.
- `docs/BALANCE.md`: "L4 W1: the lookout at the trailhead".

## Luau references to route

None name a position. The lookout appears only in comments: `src/combat/server/Services/LevelGeometry.luau:898`,
`UnlockService.luau:259`, `WaveService.luau:39`. Nothing in `src/` names `LookoutLedge`, `LookoutSignPad` or the old
coordinates. No `Economy.luau` formula change is needed.

## Surprises

- The d-M1 ridge at 84 (CaveWallS2, CaveRoofE, the alcove) was raised only against lifts from the old ledge. On
  today's data its own rule is green with the ridge back at 64. Whether another gate needs 84 was not checked.
- The R8 seed sensitivity above: three seeds decide a row whose outcome changes on a third of the seeds.

## Docs for the docs-keeper (not mine)

`docs/PLAYTEST.md` still describes the old place: :5203 ("Just before the first camp, left of the road, a tall ..."),
:5215 ("walk (or **N** once) to the lookout": it is at the start now, no N), :5287 and :5342 ("the bramble under the
lookout": the cave mouth on Road4 is no longer under it), :4766 / :4770 ("the climb by the lookout", "the step by the
lookout": the sign pad step is gone).
