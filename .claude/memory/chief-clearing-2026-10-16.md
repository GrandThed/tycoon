---
name: chief-clearing-2026-10-16
description: L1c — the Chief's Clearing redone before L2 (walled boss camp, bent gatehouse, flank ambush, then the Colossus); rulings, numbers, lessons
metadata:
  type: project
---

Before starting L2, Ben said the boss camp "feels wrong": he wanted an entrance where no enemy shows, a small
group ganking him once inside, and nothing of the camp visible from outside. Click questions (2026-10-16), the
lead's recommendation each time: **ambush then boss** (the two waves of ~35 and every resident group gone),
**ambushers from both flanks**, **a bent passage** (one turn). Record: MISSIONS_DESIGN §21, contract
`docs/prompts/l1c-contract.md` (+ §8 lead rulings) and the three fix-round files `l1c-fix-round.md`,
`l1c-fix2.md`, `l1c-fix3.md`. **Merged to `main` 2026-10-16 (8e6540b), the six place files rebuilt; waiting on
Ben's Studio look** (PLAYTEST "L1c — the Chief's Clearing"; reach it with N, never B, which brings the ambush
and the Colossus at once).

What shipped: camp C moved south, its own fence raised to 64 (the wall), a gatehouse of six blocks into a north
gate, held flank `guard` groups (Normal 2 fodder + 3 brutes a side, Hard/Brutal one more fodder; no plated kinds
in a walled camp because the plate bar draws AlwaysOnTop), waves [empty, Colossus], Colossus 42,900 cash / 76
Timber, `targetMinutes` 5 (Normal clear ~5.0 min, ambush ~20 s). A 0 s per-stage `gateSeconds` (stepping in
shuts it), a walled camp triggers up to its fence top (`StageFlow.Ceiling`), the close nudges any root inside
the fenced rectangle to `inner` (velocity kept, no `Placed`), held residents answer `"held"` (no BLOCKED, skipped
by strikes and chains), the camera clip (`WallClip.Reach`, fenced rect grown by `levels.cameraClear` 3.5),
Reset Character off in the combat place, `CameraMaxZoomDistance` 16, and **every ground-aimed ability refuses
a point more than jumpHeight + doubleJumpHeight (30) above the caster's floor** (`WeaponService.GroundPoint`,
mirrored in `InputController.castAbility`). `check_levels` has a walled-camp gate with `sightMargin` 1.5 (eye
+1.57, camera +2.73) and `tools/check_levels_mutants.py` re-runs its mutants.

**Lessons:**
- **"Can't be seen" needs every way of looking checked, not only the eye:** the camera boom resting in an open
  gate's mouth, the default camera after Reset, AlwaysOnTop markers (plate bar, BLOCKED text), a jump's apex
  above the trigger height. The first build's own gate exempted the doorway for camera points and was blind
  to the main leak; two independent reviewers found it.
- **Every fix round needs its own fix-diff review:** round 1's fixes introduced two Majors (a 30-stud trigger
  height collapsing the camera mid-fight; the close yanking the player 10 studs), round 2's three Minors.
- **A sight margin of a quarter stud is not a margin**: ask for ≥ 1.5 against animation and weapons. Getting
  there cost a brute (fodder in its place) and a pay move to keep the R8 sniper gate green.
- **R8's Hard LookoutLedge row (+1.6%) is the thinnest gate** and moves with any route change near C; it also
  differed between 32- and 64-bit Python. Judge on the 64-bit run.
- A long mutate run in one worktree plus fixers in a second (`tycoon-p5b`) kept both moving; the full run
  refuses to start while any entry's text is stale, so re-aim entries in the same round as the edit.

**Why:** a fresh session would otherwise re-open the clearing's shape or re-add residents/waves to camp C.
**How to apply:** read §21 and the contract before touching camp C or any future walled camp (later levels
will reuse the walled-camp gate). See [[missions-replan-2026-10-13]], [[agent-context-cost-2026-10-13]].
