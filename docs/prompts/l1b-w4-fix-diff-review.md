# L1b Wave 4 — fix-diff review brief (one reviewer)

Read-only review of `git diff 2ec9da9 e428e85` (the fix round on top of the reviewed build) in the
worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave4`. Every Bash call starts with
`cd /c/Users/benja/Desktop/tycoon-p5 && `. Edit no source file; write findings to
`docs/prompts/l1b-w4-review/fix-diff.md` (if the Write tool refuses, put them in your final message).
Do not run `mutate.py`. Python is `py`; the harness needs `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.

Read: `docs/prompts/l1b-w4-fix-round.md` (rulings R1–R15 and the rulings after it: binding), the four
slice findings in `docs/prompts/l1b-w4-review/`, and the fix reports in `docs/prompts/l1b-w4-fix-reports/`.

Check:
1. Each finding the round fixes is actually fixed, and each fix has a case or gate that fails without
   it (prove one or two by reasoning about the mutation).
2. A fix that broke something it touches: the leash and stand-down after R1 (`goalGap`), home → rest
   only when no member strikes (R2: can a group now never rest?), the heal latch (R4), the lane runway
   (R5) on the range and arena floors, R6/R14/R15's lower bounds on bosses and the range sets, the
   tent pace restart (R7) and the stirred set, the safe point (R10) built from group events, `refused`
   (R12), CampAim's `ShotSpares` and the auto-fire wiring (R13).
3. A mirror that disagrees with the module it mirrors after the round; `mirror_mutants.py` and
   `mutate.py` entries that no longer match their code.
4. `Combat.json` carries `meleeBelow` 1.5 and `CampBrain.Problems` accepts the shipped rules (no
   harness case runs Problems on the real file: check by reading or a scratch run).
5. Yields in Heartbeat paths, allocations per body per step, the compile gate (~180 top-level locals),
   the CLAUDE.md code rules.

Severity Critical / Major / Minor with file:line, a concrete failure scenario and a suggested fix.
End with `Critical n, Major n, Minor n`.
