# L1b Wave 2 fix round — economy-designer (the data)

Status: **done** (E-1, E-2, E-3, plus fix-B's request 4, the mirror of B-2 and B-4, which turned
`check_stage_mirror.py` red while B worked). Most of it is in the lead's WIP commit 1f1c735. The
last `docs/BALANCE.md` edit (42 mutants, the B-2/B-4 note) is uncommitted.

## E-1: C's south guards stood in C's tent marker

- `src/shared/Layouts/Levels/ForestRoad.json`: C's tent moves 2 studs north, (353.5, 17, 0) →
  (353.5, 17, −2). Its south wall is now at z 4. C.south's posts stay at z 6.
- C's tent is a marker only (no stock, LR 5), so no ring, population, Part or band number moves.
  The spawn (349.5, −4) stays inside the marker on purpose: it is where C's stage waves come out.
- `tools/check_levels.py` `check_wave2` has a new gate. Every resident post, and every sampled point
  of a patrol's loop, in a camp with a tent block (C included) must clear the marker by its body's
  radius, at every difficulty. Today the tightest is Hard's C.south post 11 (armoured), with +0.30
  to spare.
- Proved on the old layout: with z set back to 0 the gate FAILS, with "normal C.south post 9
  (lobber) stands 1.40 inside camp C's tent marker", and posts 10 and the Hard ones the same.

## E-2: the walk-through line that could not fail

- Dropped. It tested `camp.tent.collide`, a key no layout has.
- The new gate's text says the walk-through build belongs to the harness. The comment names B's
  mutation "l1b w2: the tent marker built colliding" (`mutate.py`) as the guard.
- The PASS count is still 137: one line was removed and one added.

## E-3: the mirror-mutant driver, committed

- New `tools/crowd_harness/mirror_mutants.py` takes `--list`, `--only <label>` and `--luau <exe>`.
  `ROOT` is taken from the file's own path, so it works in the main checkout or a worktree.
- Each mutant is one exact-text change on a temp copy, run through `check_stage_mirror.py
  --module`. It counts as caught only when the tool exits non-zero with a DIFF line.
- A text that no longer occurs exactly once reports STALE and counts as a miss.
- **New:** the driver first runs the mirror unmutated and refuses to judge anything if that run is
  red. During the round B's `doors` DIFF made all five SwingGate mutants look "caught" by the
  standing DIFF.
- Three mutants were added for the fix round (39 → 42):
  - "Validate: the posts at the highest difficulty only";
  - "Plan: a tent's door on the wall whatever the kind";
  - "TentDoor: no clearance past the wall".
- "TentDoor past the post" is equivalent on the shipped data (every door stands short of its
  post), so it is not in the list. The harness's TentDoor cases cover that cap.
- BALANCE "L1b Wave 2" now names the driver, shows 42 of 42 and explains the three new mutants.

## fix-B request 4: the Python mirror of B-2 and B-4

The lead had not routed it yet. All of it is in my files, and the mirror gate was red without it,
so I did it.

- `tools/sim_range.py`:
  - new `tent_door` mirrors `LevelGeometry.TentDoor`;
  - `tents_of(..., crowd_kinds=None)` builds `doors` paired with `posts`, clearing by the kind's
    radius, or 0 without kinds;
  - `plan_level` passes its `kinds`;
  - `level_problems` checks resident posts and tent rings at every distinct rank, highest first,
    and reports a group once (`told`), as B's `campProblems` does.
- `tools/check_stage_mirror.py`:
  - `tent_row` carries `doors`;
  - new refusal "a tent ring post only Normal pushes off its floor": A's tent becomes 2 fodder plus
    1 from Hard, with the marker 9.5 studs inside the south edge. Both sides refuse it (44 refusals
    compared). Run against the pre-B-2 StageFlow (HEAD~1's copy via `--module`), the Luau passes
    it and the mirror reports the DIFF.

## Gates (final state, after A, B and ui landed their code)

| Gate | Result |
|---|---|
| `py tools/check_levels.py` | CHECK PASS, 137 PASS lines; gate 16 still 147 / 157 / 157, Parts 82, route 1,055, sneak 979 |
| `py tools/sim_range.py --check` | CHECK PASS, output identical line for line to the build's `final_range.txt` |
| `py tools/sim_combat.py --check` | CHECK PASS, 23 of 23, identical to the build's output |
| `py tools/check_stage_mirror.py` | CHECK PASS (Plan's doors equal, 44 refusals alike) |
| `py tools/crowd_harness/mirror_mutants.py` | 42 of 42 caught, baseline green |

The harness and `mutate.py` were not run, per the brief.

## For the other owner

- **Lead:** the last `docs/BALANCE.md` hunk is uncommitted. QA's gate 10 command list should
  gain `py tools/crowd_harness/mirror_mutants.py`, which takes about 2.5 minutes. Never run it
  beside `mutate.py`, which rewrites the modules it copies.
- **luau-engineer A / B:** the driver holds exact Luau texts in SwingGate, HitShapes, CampBrain,
  Combat, StageFlow and LevelGeometry. Any edit to one of those lines makes its mutant STALE (a
  red run). Re-aim the text in `MUTANTS` (my file; send me or the lead the new line) rather than
  deleting the mutant.
- **docs-keeper:** none. C's tent move changes nothing a player reads in PLAYTEST. Step 3's tent
  is A's or B's.
