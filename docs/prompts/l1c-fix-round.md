# L1c fix round (lead's rulings, 2026-10-16)

Findings: `docs/prompts/l1c-review/code.md` (C1, M1–M3, m1–m3) and `docs/prompts/l1c-review/data-tools.md`
(C1, m1–m6). Read both in full, then the contract `docs/prompts/l1c-contract.md` and INTERFACES "# L1c
contracts". Branch `l1c-chief-clearing` in `C:\Users\benja\Desktop\tycoon-p5`, build commit 2a58134.

## Rulings

- **C1 (both slices: camera in the open gate's mouth sees the ambush).** Code: the camera clip cuts against
  the walled rectangle grown by a new `Combat.json levels.cameraClear` = 3.5 (covers a brute, the shake and
  the pad). The "root is inside" release stays on the TRUE walled rectangle (code reviewer's reason: a grown
  release would let the boom run through the gate from 3 studs outside), and also needs the root within
  `triggerHeight` of the floor (code m1). Gate: `check_levels` exempts eye points only in the doorway;
  camera points inside the grown rectangle are dropped (the clip keeps them out) unless their eye is inside.
  The gate must go red on 2a58134's client numbers (cameraClear 0.2) and green with 3.5. No baffle wall.
- **M1 (Reset gives the free default camera).** Disable the reset button in the combat client (SetCore with
  retry, like the other SetCore calls if any) and set `StarterPlayer.CameraMaxZoomDistance` in
  `combat.project.json` to the shoulder camera's max zoom (read the value; say it in the report).
- **M2 (BLOCKED ×N over hidden ambushers).** A held resident answers a verdict StrikeTally drops (a new
  `"held"`, or `"gone"` if that is cleaner; say which). Harness case + mutation.
- **M3 (statues for 3 s).** Per-stage `gateSeconds` in the level file, read by `gate()`, mirrored in Python;
  camp C's stage gets 0: stepping in shuts the gate and the ambush wakes in the same step. No countdown text
  when it is 0. Other stages keep today's `levels.gateSeconds`.
- **code m2 (hand-typed GROUND_AIMED).** Add a check that fails when the client list and AbilityService's
  `target = "ground"` set differ (a tool or harness check reading both is fine).
- **code m3 (lever B gives ambush + Colossus together).** Docs only: the playtest reaches the clearing with
  N. The lead routes it to docs-keeper.
- **data m1–m6:** all accepted as proposed (exact extremes and the 1.151 torso factor in the sight margin,
  reworded BALANCE; the mirror's maxAlive case sets C's stage `maxAlive` to 10 instead of adding bodies;
  per-difficulty `lockedResidents` bands, Normal 8–10; Floors rule measures to the nearest tall wall; 15 s
  floor on every ambush band; a committed driver that re-runs the check_levels mutants incl. the C1 and m2
  cases).

## Owners (disjoint)

- **Code agent:** `src/shared/WallClip.luau`, `src/shared/Types.luau`, `src/shared/Config/Combat.json`
  (`levels.cameraClear` only), `src/combat/client/**` (camera, reset, input, UI), `combat.project.json`,
  `src/combat/server/Services/StageFlow.luau` (per-stage gateSeconds read + Validate),
  the crowd/strike files for M2, `tools/crowd_harness/**`, `tools/check_stage_mirror.py`.
- **Data agent:** `src/shared/Config/Levels/1_ForestRoad.json` (C's `gateSeconds: 0`),
  `src/shared/Layouts/Levels/ForestRoad.json` (only if needed), `tools/check_levels.py` (+ the new mutant
  driver), `tools/sim_range.py` (per-stage gateSeconds mirror, m5), `docs/BALANCE.md` (re-measured numbers).
  Read `levels.cameraClear` from Combat.json; never re-type it.

Each agent: `git status`/`git diff` first; commit nothing; kill only your own PIDs; changes needed in the
other's files go in your report. Report to `docs/prompts/l1c-reports/fix-<code|data>.md`.
