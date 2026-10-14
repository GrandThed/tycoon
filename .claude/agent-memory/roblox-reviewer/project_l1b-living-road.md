---
name: l1b-living-road-review
description: L1b "the living road" reviews (resident camp groups, open camps, per-kill pay) - wave 1 slice 4 (data and tests) verdict, how to run the gates read-only, and the open-camp geometry patterns to recheck in Wave 2
metadata:
  type: project
---

L1b = residents in open camps (CampBrain groups: guard/patrol/fire, rest/rise/fight/home), only the
boss room locks, every kill pays at once (Combat.SplitCarry). Contract: INTERFACES "# L1b contracts"
(~line 11369) on branch `l1b-living-road`, worktree `C:\Users\benja\Desktop\tycoon-p5`. Reviewed
in four slices from `docs/prompts/l1b-w1-review.md`; findings go to `docs/prompts/l1b-w1-review/<slice>.md`.

**Wave 1 slice 4, data and tests (2026-10-14): 0 Critical, 0 Major, 8 Minor.** All gates green.

**Why:** Wave 2 (the 1,000-stud road, camps twice the size, tents, sneak paths) reuses these gates.
Each pattern below is latent at Wave 1's sizes and becomes real with new terrain.

**How to apply (read-only gate recipe, from the worktree):**
- `py tools/check_levels.py --no-plan | grep -E "PASS|FAIL"` (0.5 s).
- `py tools/check_stage_mirror.py` (2 s; it finds the main checkout's luau.exe itself).
- `py tools/sim_combat.py --check` (about 20 s).
- `py tools/sim_range.py --check --levels-only --level forest` (run it in the background).
- To prove mutate.py's texts without running it: exec its source up to `def harness(` with a
  fake argv, then count each `old` text in its file (495 entries at wave 1).

**Open-camp patterns to recheck:**
- The in-play area is the floor grown on each axis (a rectangle). A clamped rusher's reach is a
  circle. So `chaseMargin` ≤ reach − radius protects edges but not corners, where √2 × (m + r)
  exceeds the reach. Any standable top within the margin is in play up to `sightAbove` 30, and
  melee misses feet above its `height`. The cover gate checks only obstacles on the floor; open
  camps leave the fence top and surrounding ground standable.
- A safe point must also be out of reach of a busy NEIGHBOUR camp's keepAway shooters. A's
  checkpoint on the 44-stud RoadAB sat 44.6 studs from B.fire1's Hard marksman (reach 48).
- A group can only finish `home` if every post is reachable. Overlapping posts (guards, or posts
  of different groups) leave it evading forever and keep `Awake` above 0. Only fire neighbours
  were gated.
- A mirror can pay a bonus on one of the two clear paths only. Check `on_open` against
  `campClear` whenever WaveService has one helper behind both.
- A patrol that mixes kinds walks each body at pace × its own speed, so it bunches.
- After a lead ruling, BALANCE's band rows and flags often stay stale. Compare them with the
  constant in sim_range.

**Several slice reviewers share this file at once. Never Write it whole: re-read it and Edit
only your own section.** On 2026-10-14 it was overwritten twice that way. The run and crowd
sections below were restored from the agents' transcripts.

## Wave 1, run slice (2026-10-14, diff 8e8990c..e2479c3): 0 Critical, 1 Major, 2 Minor
- **Major: a downed party member stays down for the whole road.** A down sets
  `downUntil = math.huge`. Only a `boundary` action (`standUpDowned`) or the return to the lobby
  stands anyone up, and the open camps lost their stages, so they lost their boundaries too.
- **Minor:** a skip's `open` still runs `campCleared`, which pays the bonus and writes stats.
- **Minor:** no gate pins "`progress()` runs in every live step". A mutation passes both the
  harness and `check_stage_mirror`.
- **Pattern: removing a structural event removes everything that rode on it.** When a contract
  deletes an action, stage or phase, grep every handler of it and list what each one did besides
  its headline job.
- **Proving a test vacuous without touching the worktree:**
  1. Copy `src/`, `tools/crowd_harness/` and `tools/check_levels.py` to the scratchpad and mutate
     the copy.
  2. Run `py tools/crowd_harness/run_harness.py <scratch> <main>\tools\bin\luau.exe`. The cases
     come from the worktree and the sources from the scratch copy.
  3. Run `check_stage_mirror.py --luau <exe> --module StageFlow=<scratch file>`.

## Wave 1, crowd slice (2026-10-14, same diff): 0 Critical, 1 Major, 2 Minor
- **Major: the in-play area has square corners** (the margin-at-corner pattern above).
  - Probed on the real CrowdService: a fodder clamped at the corner, 5.94 from the player, never
    winds up, and every hit lands.
  - Suggested fix: rounded in-play (distance to the rectangle) and a gate of
    `reach − √2 × radius` (fodder 2.66).
- **Pattern: a per-step state read at an event that has already left it.** `Engaged` has a height
  band, and the fall rescue fires at killY after several crowd steps out of the band, so "no
  i-frames while engaged" never applies to a fall. Ask of any "while X" rule: is X still true
  when the consumer reads it?
- The tests read `Awake`, `Busy` and `Engaged` in rest, rise and fight, never in `home`.
- What held:
  - CampBrain matches the contract rule for rule.
  - A resident that is not fighting never thinks and holds no turn (`Commit` counts striking
    minds only).
  - No stuck fight (striking always ends); no stuck home on the shipped posts.
  - The fence top (4) is under the lunge's height (5).
- **A probe that writes nothing in the worktree.** `run_harness.py` and `mutate.py` write
  `bundle.luau` and `mutant/` in the worktree's harness folder. Instead:
  1. `import run_harness as R`.
  2. Write `R.prelude(repo)`, the chosen `R.TESTS` (VERDICT stripped) and the probe to the
     scratchpad. The L1BC helpers are in scope after `tests_l1b_crowd.luau`.
  3. Run the main checkout's luau.exe on it.

  Wrap the probe in a pcall: an error otherwise ends the run silently.
- **Old-code fixtures:** `git archive <base> src tools/crowd_harness | tar -x -C <scratch>/old`,
  then build with the old run_harness (`gate_reading` stubbed). This proved that the range hash
  2948329570 (2,400 bytes) really is pre-L1b.

## Wave 1, fix-diff check (2026-10-14, diff 9deef26..5ff333b): 0 Critical, 0 Major, 2 Minor
Findings are in `docs/prompts/l1b-w1-review/fix-diff.md`.

All four fixes held: rounded in-play, the engaged hold, stand-up on a clear road, and the safe
point kept out of a threat's reach.

**Patterns:**
- **A client-side gate that is stricter than the server's rule takes a fight away from touch
  players.** The client's auto-fire in-play test dropped the keepAway-reach clause. A phone
  player can therefore never return fire from where a slinger keeps him in play. Ask of any
  client "only stricter" gate: does it also apply where the action is harmless (an awake group)?
- **A pure query that the mirror does not compare drifts.** `StageFlow.StandsUp` allows `gate`;
  the simulator's own copy allows only travel/armed. Check `check_stage_mirror` `NEEDED` for
  every new pure function.

**Verified and safe to reuse:**
- `OnDown` runs after VitalsService's flush, so a stand-up from `advance` is not re-entrant.
- `canTarget` drops downed players.
- Crowd ids wrap at 65,535, so stale id lists are safe within a run.
- WaveService is covered by no gate. Only the pure rules carry tests.

See [[p5-missions-review]] and [[p4-enemy-roles-review]].
