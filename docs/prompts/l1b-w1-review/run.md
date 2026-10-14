# L1b Wave 1 review: slice 2, run

Reviewed: `git diff 8e8990c e2479c3` for `StageFlow.luau`, `WaveService.luau`, `ArenaService.luau`,
`LevelService.luau`, `LevelGeometry.luau`, `ReturnService.luau`, `DebugService.luau` (unchanged),
`src/shared/Combat.luau`, `tests_l1b.luau`, `tests_l1.luau`, `tests_l1_world.luau`, `run_harness.py`
(B's mutation entries in `mutate.py` read for coverage). I read every changed file in full and
checked it against the contract (INTERFACES "L1b contracts", rulings L1b-1 to L1b-24) and the
owners' reports and routing rulings.

How I checked: the harness was run on a scratch copy of `src/` and `tools/crowd_harness/`:
`HARNESS: PASS (1,531 checks)`. One concrete mutation was then applied to that copy (Minor 2) and
both gates were run against it. Nothing in the worktree was edited.

## Critical

None.

## Major

**M1. A downed party member stays down for the whole road.**
Files: `src/combat/server/Services/WaveService.luau:1227-1232` (with `standUpDowned` at 354),
`src/combat/server/Services/StageFlow.luau:1219-1256`, and
`VitalsService.luau:311-314` for context.

- **What the code does.** In a run, a down sets `downUntil = math.huge`: there is no get-up timer.
  The only things that stand a downed member up are `standUpDowned()`, which runs on a `boundary`
  action, and `backToLobby`.
  - In L1 every camp was a stage, so each camp's wave clear emitted a `boundary`.
  - In L1b the open camps have no stage. `progress()` emits only `reach` and `campClear`, neither
    of which stands anyone up. So the first `boundary` of the run is the clear of the boss room's
    first wave.
- **Scenario (two players, Forest Road, Normal).**
  1. Player 1 goes down in camp A while player 2 still stands. `RunLost` is false, so the run
     goes on.
  2. Player 2 walks away. A's group leashes home and rests beside the downed body (`Seen`
     excludes a downed player, so nobody is "in play").
  3. Player 1 cannot act and cannot Leave (`MayLeave` needs `waiting`). They can only Abandon if
     they lead, or reset their character.
  4. This lasts through camp B, the countdown and the whole of the boss room's wave 1.
     `moveFighters` even carries the downed body into the boss room at the close.
- **Why it matters.** In L1 the same down lasted one camp's wave. The contract does not cover
  it: L1b-10 defers resident scaling to L5, but not the downed partner.
- **Suggested fix (the lead must rule).** Two options:
  - give `campClear` a stand-up, as L1's boundary did; or
  - better: in `travel`/`armed`, when `FieldClear` is true (no group awake) and a fighter is
    down, have StageFlow emit a stand-up action that WaveService runs with `standUpDowned()`,
    moving those members to `SafePoint`.

  Either way, add a harness case for it. Party-only, so not on Ben's solo checklist.

## Minor

**m1. A Studio skip pays the clear bonus and writes `stats.wavesCleared`.**
Files: `src/combat/server/Services/WaveService.luau:1233-1237` and 748-762, via
`StageFlow.luau:1424-1428` and 1477-1487.

- **What the code does.** `Skip("stage")` in the boss room's fight (N) emits
  `drop boundary open end`. `Skip("boss")` emits `open` for the camps it passes. `execute`'s
  `open` branch always calls `campCleared(zone)`, which does two things:
  - it pays `crowd.clearBonus` × `rewardMult` through `credit()`;
  - it adds 1 to every fighter's profile `stats.wavesCleared` (`countWaves(0, 1)`).
- **What the contract says.** L1b-22 and L1's fix-round ruling: "a skip pays nothing",
  "nothing skipped is credited".
- **Why it is only Minor now.** `clearBonus` is 0 today, so nothing is paid yet. But the
  checklist asks Ben whether he wants a bonus, and his answer is a config change. Once it is
  above 0, every N in the Chief's Clearing (and in the Raider Arena) pays it.
- **Suggested fix.** Mark the skip's `open` actions (`skipped = true`, set in `Skip`). In
  `execute`, run only the banner and `SetCamp` for them: no `credit` and no `countWaves`. Add a
  harness case.

**m2. "Checkpoints and open camps' clears run in every live step" is pinned by no gate.**
Files: `src/combat/server/Services/StageFlow.luau:1283` and `tools/crowd_harness/tests_l1b.luau`.

- **What the contract says.** Advance steps 4 and 5 must run in `travel`, `armed`, `gate`,
  `fight` and `breather`.
- **The mutation I ran.** I wrapped the `progress(...)` call in
  `if step == "travel" or step == "armed" then ... end`.
- **What the gates said.** Both still passed:
  - `run_harness.py`: `HARNESS: PASS (1,531 checks)`;
  - `check_stage_mirror.py --module StageFlow=<mutant>`: `CHECK: PASS` (20 scripted Advance runs).

  Every `reach` and `campClear` in the cases happens in `travel`.
- **Where it shows in play.**
  - The Studio `killAll` lever during the boss fight empties A and B, but they would never count
    as cleared. The summary would then read "Camps cleared 1 / 3".
  - C's checkpoint (it is on its floor) is reached during the countdown or the fight.
- **Suggested fix.** Add two cases:
  - in C's `fight`, `aliveByFloor = { 0, 8, 0 }` emits `campClear` for zone 1;
  - in `gate`, a root on C's checkpoint emits `reach`.

  Then add the mutation above to `mutate.py`.

## For other slices (not reported here)

- crowd: `Awake`, `Busy` and the leash's `striking` decide `FieldClear` and `SafePoint`. A body
  whose mind stays "striking" (`IsStriking` or `mind.charge` never cleared) would keep its floor
  busy and the road "awake" forever, and then any solo reset ends the run. Worth a case in
  `tests_l1b_crowd.luau`.

Critical 0, Major 1, Minor 2
