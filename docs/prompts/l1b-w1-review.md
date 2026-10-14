# L1b Wave 1 — review brief (four slices)

Read-only review of `git diff 8e8990c e2479c3` in the worktree `C:\Users\benja\Desktop\tycoon-p5`
(branch `l1b-living-road`). Every Bash call starts with `cd /c/Users/benja/Desktop/tycoon-p5 && `.
Edit no source file. Write your findings to `docs/prompts/l1b-w1-review/<slice>.md` as you go.

## Read first

- `CLAUDE.md` (code rules), `docs/MISSIONS_DESIGN.md` §15–§16 (Ben's rulings).
- The contract: `docs/INTERFACES.md` from `# L1b contracts — the living road` (line 11369) to the
  end. The contract is the spec. Its rulings L1b-1 … L1b-24 are binding.
- `docs/prompts/l1b-w1-reports/` (each owner's report and the lead's routing list, with the
  rulings taken after the contract: accept them as spec).

## What to look for

Correctness first: a rule the executor gets wrong against the contract; a state that can stick
(a group never returning to rest, a floor busy forever, a boss room that never clears or never
spawns, a run that never ends); a farm (any way to kill residents without being able to be hurt
back, or to be paid twice); a yield in a Heartbeat path; a remote without validation or rate
limit; a crash on a nil the wire can deliver; a pure rule the harness or a mutation does not
actually pin (prove a test is vacuous by reasoning about a concrete mutation); a mirror that
disagrees with the module it mirrors. Then the code rules of `CLAUDE.md`. Ignore style that
stylua/selene own.

Severity: **Critical** (breaks the playtest or loses/duplicates rewards), **Major** (a real bug
a player can meet, or a gate that cannot catch what it claims), **Minor** (the rest). Every
finding: file:line, a concrete failure scenario, and a suggested fix in one or two sentences.
Verify each against the code before writing it; drop what you cannot make concrete.

## Slices

1. **crowd** — `src/shared/CrowdCodec.luau`, `src/shared/Types.luau` (the L1b block),
   `src/combat/server/Services/CampBrain.luau`, `CrowdService.luau`, `CrowdBrain.luau`,
   `tools/crowd_harness/tests_l1b_crowd.luau`, `tests.luau`.
2. **run** — `src/combat/server/Services/StageFlow.luau`, `WaveService.luau`, `ArenaService.luau`,
   `LevelService.luau`, `LevelGeometry.luau`, `ReturnService.luau`, `DebugService.luau`,
   `src/shared/Combat.luau`, `tools/crowd_harness/tests_l1b.luau`, `tests_l1.luau`,
   `tests_l1_world.luau`.
3. **client** — everything under `src/combat/client` and `src/client/UI/Theme.luau` in the diff.
   Phones at about 667 × 375 landscape; no attack button; no sound; compile gate ~180 top-level
   locals; the playtest checklist in the contract must be what Ben sees.
4. **data and tests** — `src/shared/Config/*.json`, `src/shared/Layouts/Levels/ForestRoad.json`,
   `tools/sim_range.py`, `tools/sim_combat.py`, `tools/check_levels.py`,
   `tools/check_stage_mirror.py`, `tools/crowd_harness/stage_mirror.luau`,
   `tools/crowd_harness/run_harness.py`, `mutate.py`, `docs/BALANCE.md` "L1b". Do the mirrors copy
   the Luau rules exactly; do the gates fail when the thing they guard breaks; does the layout
   make the playtest checklist work (sitters, guards, a patrol, checkpoints off the floors and
   out of sight).

Read neighbouring slices' files when a call crosses into them, but report only findings whose
fix lies in your slice (name the other slice for anything else, in one line at the end).

End the file with a one-line count: `Critical n, Major n, Minor n`.
