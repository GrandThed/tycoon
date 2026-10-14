# L1b Wave 1 review: slice 4, data and tests

Reviewer: roblox-reviewer, 2026-10-14. The diff is `8e8990c..e2479c3` on `l1b-living-road`.

**What was read.** `Config/Combat.json`, `Expeditions.json`, `Levels/1_ForestRoad.json`,
`Layouts/Levels/ForestRoad.json`; the diffs of `sim_combat.py`, `check_levels.py`,
`check_stage_mirror.py`, `stage_mirror.luau`, `run_harness.py` and `mutate.py`. In `sim_range.py`:
the `cb_*` mirror, `level_problems`/`camp_level_problems`, `groups_of`/`population_of`,
`LevelWorld`, and `LevelRun` (`before_think`, `steer`, the kite, `fall`/`credit`,
`on_camp_clear`/`on_open`). Also BALANCE "L1b", and `CampBrain.luau` plus `CrowdService`'s camp
step to compare against the mirror.

**What was run (all green):**
- `check_levels.py`: CHECK PASS.
- `check_stage_mirror.py`: CHECK PASS, every L1b comparison equal.
- `sim_combat.py --check`: 23/23.
- `sim_range.py --check --levels-only --level forest`: PASS.
- A static check of `mutate.py`: 495 mutations, each text found exactly once, none a no-op. The
  harness was not run.
- A script over every post at Normal and Hard: the closest pair in one camp is still 1.4 studs
  clear of touching (fires).

**What holds:**
- The `cb_*` mirror copies `CampBrain` rule for rule.
- `SplitCarry` and `KillReward` match `Combat.luau`.
- The executor details in `before_think` match `campStep` and `integrate`: heal before Step, the
  release step, a stop at half the tolerance, engaged only with a living member.
- Every mutation the contract lists is present.
- The layout serves the checklist:
  - fire1 wakes as he crosses A's west gate, and the east-gate guards about 11 studs later;
  - fire1 and fire2 each carry a slinger;
  - B has the patrol;
  - the checkpoints are on RoadAB and RoadBC1, behind the guards' 140-degree cones.

## Critical

None.

## Major

None.

## Minor

1. **`src/shared/Layouts/Levels/ForestRoad.json:21` — A's checkpoint is inside camp B's
   shooters' reach, so the "safe point" beside a fight in B is not safe.**
   - On Hard, B.fire1's marksman sits at its post at about (59.5, -52). That is 44.6 studs from
     (16, -42), inside its 48-stud reach. On Normal the slinger's 32 covers RoadAB once it has
     moved toward B's west edge (clamped at x 39.2).
   - Scenario (Hard): he fights B.fire1, jumps or falls over B's fence (open camps have no wall
     now), and the rescue puts him at A's checkpoint (B is busy and A is reached). He is in play
     for B.fire1 there and gets no i-frames. The marksman keeps the group in `fight` and keeps
     shooting him (44 a line on Hard). The group never leashes until he walks about 10 studs
     west.
   - This breaks L1b-20's "the group then leashes and goes home behind them".
   - The 44-stud RoadAB cannot hold a point out of reach of a marksman clamped at B's edge.
   - Fix:
     - add a `check_levels.py` gate: an open camp's checkpoint lies farther than every other open
       camp's keepAway reach from that camp's floor less the shooter's radius (it fails today on
       Hard);
     - either take Hard's marksman out of B.fire1 for Wave 1, or route the real fix to slice 2
       (see the end).
2. **`tools/check_levels.py:1183-1197` — the `chaseMargin` gate checks only straight edges, but
   L1b-7's "no farm" rests on it, and its rationale is printed as if it covered everything.**
   - The in-play area is the floor grown on each axis (a rectangle with square corners). A clamped
     rusher reaches a circle.
   - At a corner, a root at (+3, +3) outside is √2 × (3 + 1.3) = 6.08 studs from the nearest
     clamped fodder (reach 4.5). He is in play there and can hit, but nothing can reach him.
   - Up to `sightAbove` 30 over the floor, any standable top inside the margin is in play too, and
     melee and ground shapes miss feet above their `height` (fodder 5).
   - The cover gate covers only obstacles on the floor. Outside it, an open camp now leaves
     standable:
     - the fence top (4 studs; fine today, 1 under the lunge);
     - any block or ground diagonal to a corner.
   - Forest Road has none, so no player can meet it now. Wave 2's bigger camps and sneak paths
     can, and nothing would go red.
   - Fix: add a gate.
     - Every standable top whose footprint meets an open camp's grown rectangle, the fence
       included, stands at most min(3.5, the lowest rusher `height` − 0.5) over the floor.
     - No standable surface lies in a corner square of the grown rectangle (outside both edges).
       Alternatively, hold `chaseMargin` ≤ reach/√2 − radius (1.88 for fodder).
3. **`tools/sim_range.py:6219` (`on_open`) and `tools/sim_combat.py:2529` (`level_pay`) —
   `clearBonus` is mirrored only half, so "a config change" would turn two gates red.**
   - `WaveService.campCleared` pays `crowd.clearBonus` × `rewardMult` on the locking camp's
     `open` as well as on `campClear` (L1b-17: "A clear … pays"). `sim_range` pays it only in
     `on_camp_clear`.
   - `sim_combat` assertion 21 compares each cleared run's wallet with `level_pay`, which prices
     kills only.
   - So if Ben answers "yes, a bonus" (the contract says that is a config change), two things
     break:
     - the simulator underpays one bonus a run against the server;
     - assertion 21 fails on every cleared run.
   - Fix:
     - `on_open` pays the bonus as `on_camp_clear` does;
     - `level_pay` adds (open camps with residents + locking camps) × bonus × `rewardMult`;
     - write `"clearBonus": { "cash": 0, "materials": 0 }` into `1_ForestRoad.json`. BALANCE's
       values table (line 4099) already claims it is there; it is absent.
4. **`docs/BALANCE.md:4140, 4189, 4214-4224` — the "L1b" bands and flags are stale against the
   lead's ruling.**
   - The results and bands tables still read "5–8 min: FAILS", and the flags still ask "the lead
     must choose".
   - `sim_range.py:4770` already holds the ruled (150, 240). Its label at `sim_range.py:7301`
     prints the band as "2-4 min" because `:.0f` rounds 2.5 to 2.
   - Fix: rewrite the band row to "2.5–4 min (lead's ruling, option c): 2.98–3.18 PASS", replace
     the flag with the ruling, and format the label with `:g`.
5. **`src/shared/Layouts/Levels/ForestRoad.json:21` — there is no checkpoint before camp A, so a
   fall in A's first fight goes back to the trailhead.**
   - L1b-18 falls back to the level's start, at (-260, 0, 0). That is about 250 studs back, over
     the gap and the climb. A's own checkpoint is beyond its exit and is not reached until he has
     crossed A.
   - The contract's done list says a fall from A's edge mid-fight lands "on the road at the last
     checkpoint reached". On a first pass that is the trailhead. Ben will read it as a bug.
   - Fix: reword the done item for A. Or give the layout a road checkpoint short of A's west gate
     (a contract change: today a checkpoint belongs to a camp).
6. **`src/shared/Config/Levels/1_ForestRoad.json:52` — on Hard, B's patrol mixes speeds, so it
   bunches into a conga line.**
   - At `patrolPace` 0.5, a fodder walks 6 studs/s and the plated elite 4.5.
   - On a 136-stud loop with 22.7-stud spacing, the fodder behind the elite closes the gap in
     about 15 s. Within about 90 s all five trail it nose to tail, pushed by separation.
   - Fix (data): move the Hard elite out of `loop`, for example into `B.fire1`. Alternatively,
     slice 1 could pace a patrol at its slowest member.
7. **`tools/check_levels.py:1108-1146` — no gate keeps posts apart except round a fire.**
   - Guard points, patrol posts, and posts of different groups in one camp are never held at
     least r_a + r_b apart.
   - If two guard points sit within about 1 stud, separation keeps both bodies more than
     `homeTolerance` off their posts. The group then never leaves `home`, which means:
     - it evades every hit forever;
     - `Awake()` stays above 0, so a solo down on a quiet road ends the run;
     - the open camp can never be cleared.
   - Today's data is clear: the closest pair, measured, is 1.4 studs clear.
   - Fix: extend the spacing gate to every pair of posts of a camp at every difficulty
     (r_a + r_b + 0.5).
8. **`docs/BALANCE.md:4166-4183` — a Normal clear now pays about 75% more Timber a minute than L1
   (42 against 24) and 46% more cash a minute.** This makes Forest Road Normal the fastest Timber
   for the Armory. It is reported but not raised as a risk.
   - Fix: add one line to BALANCE's flags for Ben's look ("replaying Forest Road Normal roughly
     doubles Timber per minute until Wave 2"). Wave 2 should carry a per-minute pay band.

## For other slices (one line each)

- **Slice 2 (run):** `StageFlow.SafePoint` / `WaveService.rescueFallen` should treat a
  checkpoint within a busy floor's keepAway reach as busy. That is the real fix for Minor 1.
- **Lead / docs:**
  - Checklist step 3 should say how far to run: out of the slinger's 32 studs, or the group never
    walks home.
  - Step 5's "N takes you … Step in" conflicts with L1b-22: N moves him to C's entry, inside the
    floor, and starts the countdown.

Critical 0, Major 0, Minor 8
