# L1 fix round (after the review of 2026-10-13)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1-forest-road`. The L1 build was committed
as `fc43816`. Four Opus reviewers read it: **0 Critical, 9 Major, 44 Minor.** This file is the
whole fix list with the lead's rulings, one part per owner. It exists so a fresh engineer can
do its part without the conversation that produced it.

Read first: `CLAUDE.md` ("Code rules"), `docs/MISSIONS_DESIGN.md` (§2, "Where it runs", §5), and
the contract: `docs/INTERFACES.md` from the heading `# L1 contracts — Forest Road in grey` to
the end (the lead's confirmation, "What the code says", the 35 rulings, your own part,
Ownership, Gates). Then `git status` and `git diff` in the worktree: the round was started once
and cut off, so some items are partly done. **Check each item against the code before you
change anything, and list every item in your report as fixed, already done, changed or
declined with the reason.**

Rules for everyone: no git writes; never kill a process by image name; Python is `py`; Bash
toolchain line `export PATH="$HOME/.rokit/bin:$PATH"`; the worktree has no `tools/bin/luau.exe`,
so the harness and `mutate.py` take the worktree root as the first argument and
`C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe` as the second, and are never run at the same
time (both write `tools/crowd_harness/bundle.luau`: wait until it has been idle for 30 s if
another engineer may be using it). Edit only the files you own. If you need a change in a file
you do not own, do the best contract-faithful thing in your own files and report it under "for
the other owner". New rules go in the pure modules (`StageFlow`, `LevelGeometry`) with a harness
case and a mutation each; the services only execute. No constant in code: values live in
Config JSON. `math.clamp` with computed bounds throws on rounding: use
`math.min(math.max(x, lo), hi)`.

## State when the round was cut off

- Done and green before the cut: engineer B's "real files" harness group (uncommitted then, now
  committed with this file): the shipped level files pass `Resolve`, `Validate`, `Plan` and
  `Pieces`; harness 1,072 checks, `mutate.py` 301 mutations with 0 not caught, nine of them
  `real:`. Six of those nine are caught only because Forest Road's Main Camp is not square
  (100 × 94) and one because the start is off the axis (x −260): keep both.
- Begun, state unknown: `src/shared/Types.luau` (new `levels` keys), `Config/Combat.json`,
  `Layouts/Levels/ForestRoad.json`, `Layouts/Levels/Lobby.json`. Treat them as half done.

## Rulings that touch more than one owner

1. **A camp triggers on its whole fenced rectangle:** the floor expanded by the fence's
   thickness (a root on a fence top triggers too), between `levels.triggerBelow` under and
   `levels.triggerHeight` above its floor. `levels.triggerInset` is removed everywhere.
2. **The invisible wall's inner face is the floor's edge,** not the fence's outer face. It is
   still `barrier.thickness` deep outward from there, never thinner than the fence, from the
   camp's own floor to its height, with closed corners and across the gate gaps. In a closed
   camp nobody can stand on a fence, whatever its height.
3. **Cover inside a camp is low.** Every obstacle in a camp is at most 3.5 studs tall (ground
   attacks only reach 4 to 6 studs up, and a taller block is a perch from which the boss
   cannot hit).
4. **New `Combat.json levels` keys:** `triggerBelow` 4, `crowdCeiling` 200, `closeGraceSeconds`
   0.5, `floorThickness` 4. Already there: `closeInset` 2, `checkpointSize`, and
   `Expeditions.json sign.size`.
5. **A skip pays nothing; only a checkpoint pays; everyone is healed on the return to the
   lobby; the star goes to those who were fighting before the last boundary.**
6. **Zero and empty mean the same on both sides.** `maxAlive` is an integer of at least 1
   wherever it appears; a camp with no waves, a `burst` of 0, a `targetWaveSeconds` of 0 and a
   block or obstacle with a size of 0 or less are refused by Luau `Validate` / `Pieces` and by
   `check_levels.py` alike.
7. **Abandon's key is Backspace, pressed twice.**
8. **The Studio gear presets (the G key) are 2/1, 4/4 and 6/6.**

## Part B — the run (luau-engineer)

Owns: `src/shared/Types.luau`, `src/shared/Catalog.luau`, `src/shared/Combat.luau`;
`src/combat/server/Services/` `StageFlow.luau`, `WaveService.luau`, `ArenaService.luau`,
`CrowdService.luau`, `WeaponService.luau` (the Studio gear override only), `DebugService.luau`,
`ReturnService.luau`, `CombatRemotes.luau`; `src/combat/server/Main.server.luau`;
`tools/proving_project.py`; `tools/crowd_harness/run_harness.py`, `mutate.py`, `tests_l1.luau`.

**Types first** (others wait): the `levels` keys of ruling 4 in `CombatLevelsConfig`;
`triggerInset` removed.

Majors:
1. **Summary pull-back** (two reviewers). `WaveService.luau` about :894-902, :843-849, :1383:
   `rescueFallen` judges every non-waiting member against the LEVEL's box while `run.plan` is
   still set, so a body in the lobby during the summary (a respawn after a reset, a member
   admitted on the summary, a rejoin) is moved about 340 studs into the dead level and back two
   seconds later. Once the run is over, every member is judged by the lobby's box. Decide it in
   `StageFlow`, tested.
2. **The trigger** (ruling 1). `StageFlow.luau` about :415, :475-500. Harness: a root in the
   edge strip and one on the fence line trigger; one outside the fence does not.
3. **`maxAlive: 0`** (ruling 6). `StageFlow.luau` about :438 uses `stage.maxAlive or
   level.crowd.maxAlive`, and `WaveService.luau` about :804 then never spawns. `Validate`
   refuses every case of ruling 6, with a test each.
4. **`CampWave`, `CampReward` and `BurstSeconds` are tested only against their own wrappers**
   (`tests_l1.luau` about :228, :237, :238; `Combat.luau` about :861, :882, :893). The mutants
   "CampReward ignores rewardMult", "CampReward floors" and "BurstSeconds ignores tempo" pass
   every check. Add absolute cases (numbers worked by hand from Forest Road's file, each
   difficulty, party sizes 1 and 4) and those three mutations.
5. **A missing required key throws instead of refusing.** `Validate` and `Plan` throw on a camp
   with no `entry`, and `WaveService.resolveLevel` / `startLevel` call them bare: the leader
   gets no answer. `Validate` reports a missing key as a problem; a pcall round both calls is
   the net; the answer is `unavailable` with one warn.

Minors:
6. The lobby never heals (`WaveService.luau` about :1012-1036): `StandUp` for every human in
   `backToLobby`.
7. A `drop` keeps the unbanked pool (about :713-721, :1113-1114): empty `run.pool`,
   `killsByUser`, `damageTally` and `bossClearsThisFlush` on `drop`.
8. A solo reset during the countdown loses the run (`StageFlow.luau` about :588-594): at the
   countdown's end, if no fighter has a living, standing body, the camp does not close. It
   re-arms and triggers again when someone walks in.
9. The star (ruling 5): `boundary` releases everyone before `end`, so "fighting at the end" is
   always true (`WaveService.luau` about :984-986, :1098-1100). Capture the fighting set before
   `boundary`; the rule moves into `StageFlow`.
10. The director's tempo is frozen through a breather (`WaveService.luau` about :1404-1408,
    :532): `updateTempo` runs only in step `fight`, where P5 ran it through the breather.
    Restore P5's behaviour. **Write the rule in one paragraph in your report**: the simulator
    mirrors it, and the arena's merges turn on a single frame.
11. No net if an executor step throws: in `tick`, when `flow.step == "over"` and the phase is
    still live, call `EndRun(flow.ended)`.
12. The close judges the server's lagged copy: re-judge who must be moved to the entry for
    `levels.closeGraceSeconds` after the close.
13. `ArenaService.luau` about :1055-1058 returns before the collision-group join (:1067-1074)
    when the character has no Humanoid yet. Join the group first.
14. `WaveService.luau` about :1046 ignores `SetBounds`' result: if false, warn and end the run.
15. A stage with no `name` freezes the client (its `isRunState` requires a string): `stage.name
    or ""` in `Plan`, and a `Validate` line.
16. The arena's single difficulty has two sources (`StageFlow.luau` about :120,
    `ARENA_DIFFICULTY = "normal"`; the client uses `map.difficulties[1]`): use the map's first.
17. Code rules: the dead branch at `WaveService.luau` about :1400-1402; exports with no caller
    (`WaveService.GetPhase`, `ArenaService.GetPhase`); `TRIGGER_BELOW` and the two copies of the
    crowd ceiling to the config keys; `Validate`'s height bound includes the crowd ceiling; the
    stale comment at `Main.server.luau` about :62-65; the "has no verified ticket" warn in a
    proving build (`ArenaService.luau` about :864-874) says what is true or stays quiet.
18. Missing tests: `Validate`'s wire check on X and on Y; barrier height 0; "it has no stage";
    the order "cap before the fallen" (`tests_l1.luau` about :573 sets `fieldClear` true, so the
    fallen row cannot fire); a boss skip from a non-boss camp's countdown; the full-chunk
    `CrowdCodec.Encode` at `CrowdService.luau` about :853. Guard the bare `L1.find(...).reason`
    at `tests_l1.luau` about :437, :562, :689 so a mutant fails a check instead of stopping the
    bundle.
19. A seeded fuzz of 2,000 runs in `tests_l1.luau` mixing `Advance`, `Skip`, `Force` and
    `Finish`, with these invariants: no gate with a body alive or queued; no bank in a losing
    batch; `end` always last; every run ends; `cleared` equals the camp count without skips.
20. `mutate.py` about :1180-1181 counts a silent harness as a catch: require the verdict line
    or a failing check, and run the unmutated bundle first.
21. `tools/proving_project.py` about :27 replaces Workspace `$attributes`: merge instead.
22. Add a fixture case for any `real:` mutation that only the shipped layout's shape catches.
23. Register engineer A's updated world tests and mutations from its handover file (part A).

Carried, do not implement: leadership follows the first arrival's unverified hint (L5); the
merged arena waves banking once and the arena's 12-seed clear time (L4).

## Part A — the world (luau-engineer)

Owns: `src/combat/server/Services/LevelService.luau`, `LevelGeometry.luau`,
`BarrierGroups.luau`; `tools/crowd_harness/tests_l1_world.luau`.

1. **Major: the wall's inner face** (ruling 2). Update `LevelGeometry.BarrierBoxes`, its tests
   and its mutations ("the inner face is on the fence's outer face" becomes "on the floor's
   edge"; keep the walk-round-three-rings check).
2. Floors are 1-stud slabs over a void, and a rescued faller arrives fast. Camp floors, and
   every ground block with nothing under it, are `levels.floorThickness` deep downward (the
   top does not move). Drop the `FLOOR_THICKNESS` constant.
3. `LevelService.luau` about :423: `construct` is not behind a pcall. A look with a bad colour
   or material throws half way, Parts stay in `Workspace.Level`, and the next `Build` stacks a
   second copy. pcall it; on failure clear what was built and return false with one warn.
4. Tests are square on the axes tested: "halfRun always sx" survives. Add non-square cases (a
   camp 100 × 94, off the origin, at height 8) for `FloorBox`, `FenceBoxes`, `GateBoxes` on
   each side, `BarrierBoxes` and `Bounds`, with a mutation per axis mix-up.
5. Confirm `Pieces` refusing a size of 0 or less has a test.
6. Hand the harness entries to B as a FILE: rewrite
   `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\280e17fe-0802-4197-b5bc-432410880310\scratchpad\l1\world_handover.py`
   (create the folders if they are gone) with the exact `SOURCES` and `TESTS` lines for
   `run_harness.py` and the full list of `world:` mutation entries for `mutate.py`. Verify every
   `old` occurs exactly once in `LevelGeometry.luau` as it stands at the end and that each
   mutant fails a check without stopping the bundle. If B has already finished, say so and the
   lead routes it.

Run your tests in a scratch bundle of your own, never B's `bundle.luau`. Build the three real
layouts on stand-in Instances from the files as they stand when you finish.

## Part U — the client (ui-engineer)

Owns: `src/client/UI/MapScreen.luau`, `src/client/UI/Theme.luau` (add only);
`src/combat/client/Controllers/` `CombatUIController.luau`, `CrowdRenderer.luau`,
`InputController.luau`, `CombatFxController.luau`, `CameraController.luau`,
`MovementController.luau` (items 2 and 3 only), `VitalsController.luau` (only if needed);
`src/combat/client/UI/` `CombatHud.luau`, `SummaryCard.luau`, `DebugPanel.luau`, `BossBar.luau`;
`combat.project.json`.

1. **Major: Abandon on a PC** (ruling 7). In every live phase the cursor is locked at the
   centre and hidden (`CameraController.luau` about :181-187, :541, :696-700), so the
   bottom-left button is unreachable, and `SetPhase` clears `altFree` on every phase change.
   Backspace arms Abandon and shows "Press again to abandon" for the same 3 s; a second press
   sends `RequestAbandon`. The label names the key on keyboard devices. It works in every live
   phase for whoever may abandon, never while typing in chat. Keep `altFree` while Abandon is
   armed. On touch it stays hidden while the local player fights in `wave` or `boss`.
2. You arrive facing across the road (`CameraController.luau` about :416-432, :548-562). On
   every server move that the snap detects, face the camera along the way forward: toward the
   next point of the level's route from where you stand (the layout through `Catalog`); in the
   lobby toward its centre. Use `CameraController.FaceToward`.
3. On that same detected move, zero the local character's root velocity: the client owns the
   body, so a rescued faller keeps its fall speed.
4. Depart does nothing, silently, for `startCooldownSeconds` after a return
   (`CombatUIController.luau` about :1442-1452; `MapScreen.luau` about :952-957). Hold a
   Confirm made during the cooldown and send it when the cooldown ends.
5. Three messages land in one band on a landscape phone at a camp's clear: one message per
   event (the camp banner and the "Progress saved" pill, no toast), and the banner scaled to
   its frame.
6. The header title may truncate ("Raider Arena · Normal"): the difficulty goes on its own
   small line or chip.
7. An arrow key held while the map opens can leave the character walking: do not sink a key
   that was already down when the binding was made.
8. Studio's debug tab draws over the map in the phone emulator: the map goes above it, or the
   tab hides while the map is open.
9. With no `MapState` the client never asks again: after a couple of seconds send
   `RequestSnapshot`, with a repeat limit.
10. Nits: the `:: any` casts at `CombatUIController.luau` about :1207-1208, :1443; the stale
    header lines at :49-50; hide the material chip in the lobby (it reads a bare "0").
11. `levels.triggerInset` is gone (ruling 1): remove any client read of it.

Carried: on touch there is no way out of a boss fight but going down; a gamepad has no key for
the map or Abandon; the map at 568 × 320 and in portrait. The click sounds stay.

## Part E — data, layout and simulators (economy-designer)

Owns: `src/shared/Config/Combat.json`, `Config/Expeditions.json`, `Config/Levels/*.json`;
`src/shared/Layouts/Levels/*.json`; `tools/sim_range.py`, `tools/sim_combat.py`,
`tools/check_levels.py`, new `tools/check_stage_mirror.py` and its Luau driver under
`tools/crowd_harness/`; `docs/BALANCE.md` "L1".

**E1, first (others read these files):**
1. The keys of ruling 4; `triggerInset` removed; in `check_levels.py` drop the gate
   `closeInset <= triggerInset`.
2. **Major: low cover** (ruling 3), and a `check_levels` gate: every standable top inside a
   camp is at most the lowest ground-shape `height` that camp fields, less a margin (heights
   from `ProvingGrounds.json`). Fences may stay at 5. The "wall band" in the checker starts at
   the floor's edge now (ruling 2): say whether the cache spur is still clear of it.
3. The lookout's top goes from 32 to 34, and every "must need the double jump" test gets a
   step-up allowance of 3 studs (a body steps up about 2, and the air dash holds altitude).
4. The three secret signs float beside the road over the void: put solid ground under each.
5. `killY` −40 gives a long, fast fall: raise it to about 12 under the lowest ground, and
   assert it is at least 8 under every standable surface.
6. Ruling 6 in `check_levels.py`, with the same reading in `sim_range.py` (no `or` on a
   number).
7. Ruling 8, and one ranged row per difficulty in the report (the Longbow against a camp's
   basic mix and the boss), for information.
8. `check_levels` refuses a file in `Config/Levels` whose name `Catalog` would not read
   (`<n>_<Name>.json`), a map node whose `level` names no such file unless it is meant to be
   unbuilt, and `eliteKind` in a level file (the simulator does not mirror the director's
   elite).

**E2, the bands must be real (Major):** the reacting player takes no hit because its planner
tries every step, jump and dash against the server's exact shapes with every threat known. At
gear 2/1 it clears Hard in 16.0 minutes with 0 hits inside the cap, and no clear band can see
`damageScale` (0.01, 1.8 and 1.95 give the identical run).
9. Gate a third player with a human reaction (about 0.55 s, or one that does not read shots):
   it clears at the recommended gear without going down, and goes down or passes the cap one
   preset below, for Hard and Brutal. Report what it takes on Normal.
10. Assert the never-dodger at 2/1 on Brutal too, and give Brutal's `damageScale` a band that
    fails when it is too low.
11. Say in BALANCE that the ideal player clears Hard at 2/1 in 16 minutes with no hit: skill
    beats gear, and the human gate is the one that matters. Fix the pay band Brutal breaks at
    4/3 (×6.10), or say why it is fine.
12. Assertions that cannot fail: `sim_range.py` about :5754-5760, `sim_combat.py` about :3203
    and :3288. Make each able to fail, or remove it and say so.
13. `py tools/sim_range.py` follows the shebang to Python 3.12 while imports run on 3.14, and
    the same seed differs by up to 0.08 min: state which Python the gate is and correct
    `BALANCE.md` about :3390.

**E3, the cross-check (a new gate):**
14. `tools/check_stage_mirror.py`, in the style of `tools/check_mirror.py`: run the real pure
    Luau under `luau.exe` on the shipped files and compare, value by value, with the Python:
    `Combat.CampWave`, `CampReward`, `BurstSeconds`, `Tempo`, `ShouldMerge`, `BreatherSeconds`
    for every wave of every level at every difficulty and party sizes 1 to 4;
    `StageFlow.Resolve` and `Plan`; one scripted `Advance` trace per level and difficulty
    against `LevelRun`'s events. Import `run_harness.py`'s bundling functions read-only. It
    must fail when either side changes alone.

**E4, only after part B has landed** (read `StageFlow.luau` and `WaveService.luau` as they then
stand, and B's paragraph on the tempo): mirror the trigger rectangle, the tempo through a
breather, the re-arm at an empty countdown, the grace re-judge, the dropped pool on a skip, and
the star rule; re-run every band; report what moved.

Carried: the arena's 12-seed clear time and merged-wave bank (L4); Hard's and Brutal's rewards
are placeholders until the Armory step.

## After the fixes (lead)

One reviewer checks the fix diff; QA runs every gate; docs-keeper updates the contract (it
does not list `closeInset`, `checkpointSize`, `sign.size`, `Zone.inner`, `State.settled`,
`Force`, `MustEnter`, `OutOfBox`, `Pieces`, and ruling 9 still says "outside the floor
rectangle"), PLAN, PLAYTEST (the Abandon key, facing, the checks only Studio can make) and
MANUAL_STEPS; then the merge to `main` and the rebuild of the six place files.
