# L1b Wave 2 — review brief (four slices)

Read-only review of `git diff main l1b-wave2` (the base is `main` at 1fc4612; review the branch's
committed head, named in your prompt) in the worktree `C:\Users\benja\Desktop\tycoon-p5` (branch
`l1b-wave2`). Every Bash call starts with `cd /c/Users/benja/Desktop/tycoon-p5 && `. Edit no
source file. Write your findings to `docs/prompts/l1b-w2-review/<slice>.md` as you go.

## Read first

- `CLAUDE.md` (code rules), `docs/MISSIONS_DESIGN.md` §15–§17 (Ben's rulings).
- The contract: `docs/INTERFACES.md` section `## Wave 2 — the long road (2026-10-14)` (grep it,
  about line 12806) to the end, with its "Lead's answers to the draft points". Wave 1's contract
  above it still binds where Wave 2 does not change it. Rulings L1b-W2-1 … 29 are binding.
- `docs/prompts/l1b-w2-reports/lead-routing.md` (Ben's and the lead's rulings after the contract:
  accept them as spec) and the owners' reports `build-A.md`, `build-B.md`, `build-ui.md`,
  `build-econ.md` (each lists the decisions it took that the contract did not: judge them).

## What to look for

Correctness first: a rule the executor gets wrong against the contract; a state that can stick
(a dormant group that never wakes, a tent that never empties so a camp never clears, a chain
wake that loops, a boss room that never clears or never spawns, a run that never ends); a farm
(killing residents or tent bodies from where they cannot hurt you back, a clear bonus paid twice
or paid for a camp nobody cleared); the new ray rule (`HitShapes.CrowdRay`, the upright capsule)
against what the client draws, on every kind, the range sets `fight` / `colossus` / `warlord`
included; the one-swing-per-jump gate (can a client get a second air swing through, can a
grounded player be refused); a yield in a Heartbeat path; a remote without validation or rate
limit; a crash on a nil the wire can deliver; a pure rule the harness or a mutation does not
actually pin (prove a test is vacuous by reasoning about a concrete mutation); a mirror that
disagrees with the module it mirrors; the population cap (147 / 157 / 157 against 160) being
reachable past what the rule counts. Then the code rules of `CLAUDE.md`. Ignore style that
stylua/selene own.

Severity: **Critical** (breaks the playtest or loses/duplicates rewards), **Major** (a real bug
a player can meet, or a gate that cannot catch what it claims), **Minor** (the rest). Every
finding: file:line, a concrete failure scenario, and a suggested fix in one or two sentences.
Verify each against the code before writing it; drop what you cannot make concrete.

## Slices

1. **crowd** — `src/shared/Types.luau` (the Wave 2 block), `src/shared/HitShapes.luau`,
   `src/shared/SwingGate.luau`, `src/combat/server/Services/CampBrain.luau`, `CrowdService.luau`,
   `WeaponService.luau` (the diff), `src/combat/server/Main.server.luau` (the diff),
   `tools/crowd_harness/tests_l1b_w2_crowd.luau`, `tests_l1b_crowd.luau`.
2. **run** — `src/combat/server/Services/StageFlow.luau`, `WaveService.luau`,
   `LevelGeometry.luau`, `src/shared/Combat.luau`, `tools/crowd_harness/tests_l1b_w2.luau`,
   `tests_l1b.luau`, `tests_l1.luau`, `run_harness.py`, `mutate.py`.
3. **client** — everything under `src/combat/client` and `src/client/UI/Theme.luau` in the diff.
   Phones at about 667 × 375 landscape; no attack button; no sound; compile gate ~180 top-level
   locals; the playtest checklist in the contract must be what Ben sees when he presses Play.
4. **data and tests** — `src/shared/Config/*.json`, `src/shared/Layouts/Levels/ForestRoad.json`,
   `tools/sim_range.py`, `tools/sim_combat.py`, `tools/check_levels.py`,
   `tools/check_stage_mirror.py`, `tools/crowd_harness/stage_mirror.luau`, `docs/BALANCE.md`
   "L1b Wave 2". Do the mirrors copy the Luau rules exactly (CrowdRay, tents, join-in, ClearBonus
   rounding); do the gates fail when the thing they guard breaks (sneak path, post spacing,
   population); does the layout make the playtest checklist work (a careful player can sneak past
   Main Camp, the Pickets fight, the tents, the boss room).

Read neighbouring slices' files when a call crosses into them, but report only findings whose
fix lies in your slice (name the other slice for anything else, in one line at the end).

End the file with a one-line count: `Critical n, Major n, Minor n`.
