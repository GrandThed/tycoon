# L1c review (brief)

Read-only review of `main..l1c-chief-clearing` (commit 2a58134) in the worktree
`C:\Users\benja\Desktop\tycoon-p5`. Read first: `CLAUDE.md`, `docs/MISSIONS_DESIGN.md` §21 (Ben's decisions),
`docs/prompts/l1c-contract.md` (§8 = lead's rulings) and the INTERFACES "# L1c contracts" section, then the
three reports in `docs/prompts/l1c-reports/`. Known deviations already accepted by the lead: the rule lives
in `WeaponService.GroundPoint` and covers all four ground-aimed abilities; the Normal ambush is 2 fodder +
3 brutes a side; gatehouse walls run y 0–76.

Judge against Ben's three requirements above everything: (1) nothing of the clearing is visible from any
reachable spot outside it (camera at any zoom/pitch, top of a double jump, Leap Smash, the gate opening,
phones); (2) stepping in shuts the gate and the flank groups rush in; nothing pops into view in front of the
player; (3) once the ambush is dead the Colossus comes and the exit opens. Also: server authority, no yields
in run loops, `--!strict`, constants only in config, client/server mirrors identical, tests that can go
vacuous (prove with a mutation if you doubt one), and anything that breaks camps A and B.

Severity: Critical (breaks a requirement or the run), Major (likely seen in play / wrong data), Minor.
Each finding: file:line, what, a concrete failure scenario, a proposed fix. Write findings to
`docs/prompts/l1c-review/<slice>.md` and end your reply with the same list. Commit nothing; kill only your
own PIDs; Python is `py`; in Bash `export PATH="$HOME/.rokit/bin:$PATH"`.
