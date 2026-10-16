# L1c second fix round (lead's rulings, 2026-10-16)

Findings: `docs/prompts/l1c-review/fix-diff.md` (F1–F4). Read it in full, then `docs/prompts/l1c-fix-round.md`
and the reports in `docs/prompts/l1c-reports/` (fix-code, fix-data). Work in the worktree
`C:\Users\benja\Desktop\tycoon-p5b` (branch `l1c-fix2`). The other worktree `tycoon-p5` is running the
2-hour mutation suite: never touch it.

## Rulings

- **F1 + F3: fix (a).** A walled camp (one whose fence is the unclimbable wall) triggers, and releases the
  camera clip, for a root anywhere up to its fence's top above the floor, instead of `triggerHeight` 30.
  Other camps keep `triggerHeight`. Needs the fence top on `RunFloor` (or an equivalent per-floor height),
  `StageFlow.triggered`, `WallClip.holds`, mirrored in `sim_range` and `check_levels` (whose doorway
  exemption then rests on a true "one more step triggers" at any reachable height). Fix the harness
  assertion at `tests_l1c.luau:93` to the new rule and add a case: a root at 33–43 above C's floor inside
  the fence keeps the boom (no collapse).
- **F2: data first.** Move camp C's `entry` to just inside the close inset so a player who triggers is not
  moved (or moved under 1 stud). Re-check everything that reads `entry`. Add a harness case: on C's trigger
  tick, a root standing anywhere on the trigger line is moved no more than 1 stud. If data cannot satisfy
  it, say so instead of changing code.
- **F4:** held residents are skipped when building strike seeds and chain links (`WeaponService.Strike`,
  `chainFrom`); harness case + mutation.

## Owners (disjoint)

- **Code agent:** `src/shared/WallClip.luau`, `src/shared/Types.luau`, `src/combat/server/Services/StageFlow.luau`,
  `WaveService.luau` (runFloors field only), `WeaponService.luau` (F4), `src/combat/client/**` if the floor
  hand-off needs the new field, `tools/crowd_harness/**`, `tools/check_stage_mirror.py`.
- **Data agent:** `src/shared/Layouts/Levels/ForestRoad.json` (C's `entry`), `tools/check_levels.py`,
  `tools/check_levels_mutants.py`, `tools/sim_range.py`, `docs/BALANCE.md`.

Each agent: `git status`/`git diff` first; commit nothing; kill only your own PIDs; changes needed in the
other's files go in your report. Report to `docs/prompts/l1c-reports/fix2-<code|data>.md`.
