# L4 W1b fix round 3 (the lead's rulings on the second fix-diff review)

Worktree `C:\Users\benja\Desktop\tycoon-p5c`, branch `l4-w1b-fix2` (review base c01348a). Findings:
`docs/prompts/l4-w1b-review/5-fix2-diff.md` (0 Critical, 0 Major, 3 Minor, 2 suggestions; M1 fixed). Earlier rulings:
`l4-w1b-fix2.md`, `l4-w1b-fix-round.md`, contract §10. Every agent: `git status` and `git diff` first, commit nothing,
kill only its own PIDs, report to `docs/prompts/l4-w1b-fix-reports/<role>-3.md` with a "For the other owners" section
(file, old text, new text). Never touch `tycoon-p5b` (QA's run). Tools as before, with this worktree's root.

## Rulings

**H1. A held blow is never erased by a clear (m3).** The boss room's clear (and any stage clear that calls
`ClearThreats`) **waits while any fighter of the run has a waiting decision**, at most the lapse (0.45 s after the claim);
the waiting decisions resolve first, so a down they cause is judged before the clear and a lost run stays lost. Owners:
**luau-engineer A** gives `VitalsService` a pure-query `HasWaiting(player?)` (and keeps `ClearThreats` as today for the
real clear); **luau-engineer B** defers the clear in `WaveService` (the deferral costs at most one lapse, never yields,
and is judged every frame). Tests: A and B each in their test file (a boss killed while a slam waits behind an unproven
claim: the slam lands first; with an honest claim proven, the clear goes through at the proof).

**H2. Errors cannot replay or starve (s1, s2).** `release` and `settle` take each entry out of their list before deciding
it (a throw drops that entry once, warns once, and never re-lands earlier ones); `trackAir` runs each shooter's body under
its own `xpcall` so one shooter's error stops nobody else's proof. Owner: **A**.

**H3. Gates that see the rule (m1, m2).** The designer adds to `fence_queues` the harness's fourth case (a knocking lunge at
0, a plain one at 0.5), a low-health down queue and a knockIframes-0 variant, so the reviewer's seven surviving sim
mutants are caught (list each); pins `stepFailed`'s body as one block and adds the reviewer's three mutants; mirrors H1 in
the simulator if it models a boss clear (else says why not); pins H1 and H2's deciding lines from A's and B's reports.

## Order

A and B in parallel; the designer after both. Then the lead reads the diff (a short third round), and filtered
`mutate.py` plus the stale check.
