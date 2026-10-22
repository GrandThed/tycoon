# L4 W1b fix round 2 (the lead's rulings on the fix-diff review)

Worktree **`C:\Users\benja\Desktop\tycoon-p5c`**, branch `l4-w1b-fix2` (from `l4-w1b`; the lead merges it back). QA's full
`mutate.py` run is going in `tycoon-p5b` on the previous commit: never edit there. Findings:
`docs/prompts/l4-w1b-review/4-fix-diff.md` (0 Critical, 1 Major, 2 Minor, 3 suggestions). Earlier rulings:
`l4-w1b-fix-round.md`, contract §10. Every agent: `git status` and `git diff` first, commit nothing, kill only its own
PIDs, report to `docs/prompts/l4-w1b-fix-reports/<role>-2.md` (luau-a-2.md, designer-2.md) with a "For the other owners"
section (file, old text, new text). Tools as in the contract §8, with this worktree's root
(`C:/Users/benja/Desktop/tycoon-p5c`) and the main checkout's Luau CLI.

## Rulings

**G1. A held hit keeps the knock rules (M1, Major).** A dash that never proves must never cost more than not dashing.
- A held decision records **`hold.at`, the moment it was first due**, and when it is released it is judged against the
  knock windows **as of that moment** (rules 6 and 18 exactly as for an unheld decision decided then).
- **A player's later decisions queue behind a held one**: nothing of that player lands while an earlier decision of his is
  held; on release they resolve in their original order, each with the knock state its predecessors leave.
- Tests (A, `tests_l4b.luau`), each against the real `VitalsService` and `DashProof.Step`: with a claim that never proves,
  (1) a knocking hit then a plain one, (2) two knocking hits in one step, (3) a held knocking hit then an unheld one due
  meanwhile: each loses exactly what the same queue loses with no claim (8 in the reviewer's probe); and the existing
  pin "a knock voids a held hit" is reversed to the rule above.
- The designer mirrors it in `sim_range.py` (release with the knock state at `hold.at`, the queue order) and adds a gate
  line for a dash into the fence (both hits: the no-dash outcome).

**G2. One Heartbeat, contained (m1).** Each half of WeaponService's `step` (the air tracking and dash proofs; the
decisions `VitalsService.Step`; the rest) runs under `xpcall` with a once-per-message warn, in the same order, so a throw
in one never stops the others. Nothing yields. Owner: **A**.

**G3. Pin the wire that gates every enemy hit (m2).** The designer pins `RunService.Heartbeat:Connect(step)` whole in
`WEAPON_START_BODY` and the head of `step` through `VitalsService.Step(deltaTime)` as one block (whatever G2 makes of
it), and adds the reviewer's two probes as mutants (`Connect(function() end)`, an early `return` at the top of `step`).
Owners: A gives the final lines; **designer** pins.

**Suggestions taken:** s1 the designer pins `total += damage` and `if bonus <= 0` in `payMentors` whole (and mutants);
s2 A returns `0, 0, 0` from `pendingDash` before building a rule when there is no claim; s3 the lead closes PLAN's open
dash item with F5's scope at the docs step.

## Order

luau-engineer A first; the designer after A's report. Then a short fix-diff check by the lead's reviewer, then filtered
`mutate.py` on every changed file plus the stale check over all entries (the full run on f16515a covers the rest).
