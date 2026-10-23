# L4 W1b fix round 3: economy-designer's report

Worktree `C:\Users\benja\Desktop\tycoon-p5c`, branch `l4-w1b-fix2`, nothing committed.

- Rulings: `docs/prompts/l4-w1b-fix3.md`. Mine are H3, plus pinning H1 and H2.
- Findings: `docs/prompts/l4-w1b-review/5-fix2-diff.md` (m1, m2, m3).
- Engineers' reports: `luau-a-3.md`, `luau-b-3.md`.
  - The lead accepts B's two decisions and both engineers' listed limits; I take them as given.
  - Every text I pasted from either report was checked first: each old text occurs once in its file.

I edited no `src` file and changed no config key. Every number below comes from Python 3.12.10 64-bit (the gate's). That
means `py -3.12`, or `py` on a script with the shebang line; `mutate.py` has none, so `py` runs it on 3.14 32-bit.

## Results

| Gate | Result |
|---|---|
| `run_harness.py C:/Users/benja/Desktop/tycoon-p5c <luau>` (py) | **HARNESS: PASS (4,244 checks)**: A's and B's 4,213 plus my 31 pins (`stepFailedBody`; H2's `trackEach`, `trackOneDefined`, `trackOneNames`; H1's 25 lines and 2 orders) |
| `sim_range.py --check` (3.12, in the worktree) | **CHECK: FAIL (1)**: only the known R8 row, still **x1.60** (seed 11 39,504 / 55.1 against 24,703 / 37.2; 23: 18,374 / 27.6 against 23,330 / 34.8; 37: 2,756 / 0.0 against 21,332 / 31.9); 540 PASS (539 + H1's new line) |
| ... compared whole against c01348a's output (a `git archive c01348a` run on this machine) | **Every line identical except two**: the fence-dash line (now seven queues, health and downs compared, PASS) and the new H1 line (PASS). Every Forest Road line, every DASH PROOF count and the R8 row are unchanged |
| `sim_combat.py --check` (py) | **PASS, all eleven assertions**; its whole output byte-identical to c01348a's (it runs the mirror's LevelRun) |
| `check_stage_mirror.py --luau <luau>` (py) | **CHECK: PASS** |
| `mirror_mutants.py --luau <luau>` (py) | **132 of 132 mutants caught** |
| `check_levels.py` (3.12) | **CHECK: PASS** (it imports `sim_range`) |
| `mutate.py ... "files:VitalsService.luau,WeaponService.luau,WaveService.luau"` (py: 3.14 32-bit, no shebang) | **MUTATIONS: 278 run, 0 not caught** (BASELINE: HARNESS: PASS 4,244), 67 min |
| `mutate.py` stale check over all entries (A's `stale.py`, exec up to its baseline) | **1,830 entries, 0 stale** (was 1,795, 2 stale) |

## Changes, file by file

### `tools/sim_range.py`

**H3, the fence-dash gate (m1).**

`fence_queues` now returns seven queues. Each one has:
- its strikes (`raised` = when a late step queues it);
- an optional starting health and knockIframes;
- its pinned no-dash outcome.

The queues are the review's three plus four new ones:
- the harness's fourth case (knock at 0, plain at 0.5);
- a held hit at 1 health that downs him, with one hit inside the down and one after the get-up;
- two knocks in one step at knockIframes 0;
- a hit struck before the knock that a step raises inside the knock's window.

`dash_fence_probe` changes:
- the player is mortal, and every hit does 1 damage;
- each frame runs `control` (regen, get-up) as well as `resolve`;
- the run lasts regenDelay + 0.6 s;
- each case also returns the trace of (health, down?) on every frame from the one after the release on.

The gate line in `check_threat` passes only when both hold for every queue:
- no dash and the never-proven dash land the same lunges, dodge the same count, and have the same trace;
- the no-dash case matches the pinned outcome.

**The `covered` fix.**
- `ThreatRun.covered` now uses VitalsService's `met`: `b > max(a, start) and a <= until`.
- The old `a <= until and b >= start` let a window of no length (a knock at knockIframes 0) "cover" a hit at its moment.
- That hid the `holds` loop from the knockIframes-0 queue; I proved this with a combined mutant.

**H1, the mirror.**
- `LevelRun.blow_waits` and `held_since` (None where the game uses 0, because a simulated run's clock starts at 0).
- `field_held(given, t, delta)` is fieldHeld line for line.
- `advance(t, delta=FRAME)` asks it before StageFlow decides; a held field sets `spawningDone` False.
- `vitals_step(t)` is resolve, then WaveService.OnDown's advance for a held down (an unheld one is left to the tick, as
  before). `run()` calls it in place of `resolve`.
- The legend's `[advance]` entry now names H1.
- A comment at `tick` says why StandsUp needs no hold in the simulator: a held field means he is standing.

**H1, the gate.**
- `boss_clear_probe` runs Forest Road's boss room through its own countdown, in the last wave, with one body left, solo,
  Normal, at the proving gear.
- `boss_clear_verdict` is the line in `check_forest`. It has four cases: no dash, never proven, honest, and an unheld
  control.
- `from types import SimpleNamespace` gives the probe its last body.

### `tools/crowd_harness/run_harness.py` and `tools/crowd_harness/tests_l3_w2.luau` (L4B_LINES, L4B_ORDER, L4BP)

New bodies:
- `STEP_FAILED_BODY`
- B's `FIELD_HELD_BODY`, `ADVANCE_BODY`, `TICK_BODY`, `BOOT_BODY`, `ON_DOWN_BODY`, `FRESH_RUN_BODY`

Each was checked to find exactly one body and to collide with no existing name.

New pins (31 checks):
- m2: `stepFailedBody`, the whole function as one block (1).
- H2: A's `trackEach`, `trackOneDefined`, `trackOneNames` (expected 1, 1, 2).
- H1:
  - B's 25 lines, verbatim with B's counts (`h1Writes` 3, `h1Calls` 2, `h1AdvanceCalls` 2, all others 1);
  - B's 2 orders, `h1InputThenHold` and `h1HoldThenAdvance`.

VitalsService gets no text pins, because the harness loads it: tests_l4b (g) holds every H2 and HasWaiting mutant of A's.

### `tools/crowd_harness/mutate.py`

Two entries re-aimed to A's H2 text, with the same labels:
- `l4b f1: settle drops a held entry`
- `l4b g1: the release drops one that still waits`

A new block, `L4B_FIX3_MUTATIONS`, holds 35 entries and keeps the label-collision guard:
- A's 14 (5 H2 VitalsService, 4 HasWaiting, 5 H2 WeaponService);
- the review's three m2 probes, as `l4b m2: ...`:
  - the note deleted;
  - the guard always true;
  - the warn deleted;
- B's 18 H1 WaveService entries.

### `docs/BALANCE.md`

New section: "L4 W1b fix round 3: gates that see the rule, and a clear that waits for a held blow". It covers:
- the seven queues;
- the `covered` fix;
- the reviewer's mutants and what catches each;
- H1's mirror, probe and table;
- the result;
- the gates before and after;
- the pins.

## The reviewer's seven sim mutants (m1), each caught

Each one is an exact-text change to `tools/sim_range.py` on a scratch copy, run through the gate line's own condition.

| Mutant | Caught by |
|---|---|
| `knock_until = t + ...` | the plain lunge at 0.5 lands with no dash and is voided under the mutant |
| the knock window from `t` | the same queue |
| `rule(..., at=None)` in `release` | all seven queues (regen, the 0.5 hit, the down) |
| `last_hurt = t` | the review's three, knockIframes 0 and the raised hit: regen begins 0.47 s late, so the health trace differs from 4.0 s |
| `down_until = t + ...` | the low-health queue: up at 2.47, not 2.0, so the 2.2 hit falls in the down and is not dodged |
| the `holds` loop in `hurt` deleted | knockIframes 0: the second knock lands (with the old `covered`, this one survived) |
| the release's `at < knock_until` deleted | the raised hit lands |
| (the eighth, "no queue behind", caught before) | still caught, by three queues |

## The reviewer's three `stepFailed` mutants (m2), each caught

All three are caught by `stepFailedBody`; mutate.py output below:
- "l4b m2: every frame warns (the note deleted)";
- "l4b m2: nothing is ever warned (the guard always true)";
- "l4b m2: a throw is swallowed (the warn deleted)".

## H1 in the simulator

The simulator models the boss room's clear (`LevelRun.on_clear` drops `holds`), so H1 is mirrored; see the changes above.

The new gate line reads, in seconds after the press:

| Case | Ends | The slam | The clear |
|---|---|---|---|
| no dash | down at 0.100 (lost) | lands 0.100 | none |
| never proven | down at 0.467 (lost, as with no dash) | lands 0.467 | none |
| proven at 0.333 | cleared at 0.333 | dodged | at the proof's frame |
| the control, never held (m3) | cleared at 0.200 (won) | never lands | 0.200, at the kill |

Sim-side mutants of the mirror:
- Caught (8):
  - the field never held;
  - the down's advance never asked;
  - the down's advance forgetting the tick's finding;
  - the tick's finding never noted;
  - the cap at nothing;
  - the hold changing nothing;
  - the deferral's start never noted (a crash);
  - the hold asked after the clear is decided.
- Equivalent (1): the cap a frame short. The simulator's one Heartbeat order runs the release and the down's advance
  before that frame's tick. B's harness holds it in both orders.

## For the other owners

Every line a new pin or mutate entry of mine reads. An owner who changes one tells the designer: file, text with its
indentation, `\t` = one tab.

**luau-engineer A, `src/combat/server/Services/WeaponService.luau`:**
- `stepFailed`, whole and unchanged:
  ```
  local function stepFailed(problem: any): ()
  \tlocal message = tostring(problem)
  \tif state.stepErrors[message] then
  \t\treturn
  \tend
  \tstate.stepErrors[message] = true
  \twarn(debug.traceback(`[WeaponService] Heartbeat: {message}`, 2))
  end
  ```
- In `trackAir`:
  - `\tlocal function trackOne(player: Player, shooter: Shooter): ()`;
  - the loop as one block:
    ```
    \tfor player, shooter in state.shooters do
    \t\txpcall(trackOne, stepFailed, player, shooter)
    \tend
    ```
  - `trackOne` is named twice in the file's code.

**luau-engineer A, `VitalsService.luau`:** the texts of A's 14 entries and the two re-aims, as A gave them.

**luau-engineer B, `src/combat/server/Services/WaveService.luau`:** B's 25 pins and 18 entries, as B gave them, in
particular:
- `fieldHeld`'s body as one block;
- the `advance`, `tick`, `OnDown` and `Boot` lines;
- `freshRun`'s two fields;
- the `DashProof` require.

## For the lead

- Nothing is needed in `src/shared/Economy.luau` or any `src` file.
- **The `covered` fix is a mirror change, not only a gate change.**
  - It is now VitalsService's `met`.
  - It moved no line of the full `--check` output; that output was compared whole against c01348a's.
  - Before the fix the mirror and the game disagreed only on a window of no length, or one ending exactly at an impact.
- **The simulator gained an OnDown advance (`vitals_step`) for H1.**
  - It runs only when the hold covers the down, so every existing run is unchanged.
  - Before this round the simulator had no OnDown advance at all.
  - The general order difference stays: an unheld down's advance runs before the tick's spawns in the game and after
    them in the simulator. It is unchanged from before and does not move any gated number.
- **The seven m1 mutants (and the H1 mirror's nine) are proven once, not kept in a list.**
  - There is no sim-side mutant runner in the repo.
  - They are listed in BALANCE and here.
  - The runner and its inputs are in my scratch folder:
    - `...\scratchpad\d3\tools\simmut.py`
    - `fence_gate.py`
    - `clear_gate.py`
    - `...\scratchpad\d3\fence_muts.json`
    - `h1_muts.json`
  - If you want the gate itself guarded against going vacuous again, a permanent `tools/sim_range_mutants.py` (like
    `check_levels_mutants.py`) is the next step. It is not done.
- Not run this round:
  - `check_levels_mutants.py`: `check_levels.py` was run and PASSes; it imports `sim_range` for geometry only.
  - The full `mutate.py`: only the filtered run and the stale check over all entries, as the brief says.

## Summary

**Files changed:**
- `tools/sim_range.py`:
  - H3's seven fence queues and the trace comparison;
  - `covered` now VitalsService's `met`;
  - the H1 mirror (`field_held`, `advance(t, delta)`, `vitals_step`);
  - H1's boss-room probe and gate line.
- `tools/crowd_harness/run_harness.py` and `tests_l3_w2.luau`: 31 pins.
- `tools/crowd_harness/mutate.py`: 2 re-aimed, 35 new in `L4B_FIX3_MUTATIONS`.
- `docs/BALANCE.md`: a new section.
- This report.
- No `src` file and no config key.

**Gates:**

| Gate | Result |
|---|---|
| harness | PASS (4,244 checks) |
| `sim_range.py --check` | FAIL (1), only R8 at x1.60, with the extended fence-dash line and the new H1 line green; every other line identical to c01348a's output |
| the reviewer's seven sim mutants and three `stepFailed` mutants | each caught (tables above) |
| H1 in the simulator | mirrored, with its own gate line and 8 of 9 sim mutants caught (the ninth equivalent in the simulator's one Heartbeat order) |
| `check_stage_mirror.py` | PASS |
| `mirror_mutants.py` | 132 of 132 |
| `sim_combat.py --check` | PASS, identical |
| filtered `mutate.py` | 278 run, 0 not caught |
| stale check | 1,830 entries, 0 stale |

**Constants changed:** none.

**Economy.luau:** no change needed.
