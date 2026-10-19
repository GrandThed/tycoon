# L2 W2 second fix-diff review (brief)

Read-only review of `d98b85d..aca232d` in `C:\Users\benja\Desktop\tycoon-p5b` (branch `l2-w2-fix2`): the second fix
round only. Read `docs/prompts/l2-w2-review.md` (requirements, severity), the findings answered
(`docs/prompts/l2-w2-review/fix-diff.md` m1–m3, s1), the rulings `docs/prompts/l2-w2-fix2.md`, and the report
`docs/prompts/l2-w2-reports/fix2.md`. Accepted beyond the ruling: the led head stops 0.5 short of the first solid;
GatehouseWallE/W shortened 1.5 at their south end.

Check: the 2.5-stud fence does not break L1c (the ambush stays hidden; the trigger, ceiling, close nudge up to
4.5, camera clip, gates, barrier band, the exit; nothing z-fights or leaves a gap at the gatehouse joins; the
route and sneak lengths); every tool reads the same thickness; `AimClear` refuses every forged origin beyond a
wall (including with a forged velocity into or along a wall) and accepts honest fast travel; streams with no
bloom everywhere it matters; the cached params are rebuilt when they must be (respawn, joins); the new origin
chord gate and its mutants are not vacuous. Run tools on a `git archive HEAD` copy in your scratchpad. Findings
(file:line, scenario, fix) to `docs/prompts/l2-w2-review/fix2-diff.md`; end your reply with the list. Edit the
shared reviewer memory only with Edit. Commit nothing; kill only your own PIDs; Python `py` (`py -3.12` for
sim_range); harness: `py tools/crowd_harness/run_harness.py <repo root> C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
