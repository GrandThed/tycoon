# L2 W3 review (brief)

Read-only review of `main..l2-w3` (HEAD) in `C:\Users\benja\Desktop\tycoon-p5`. Read first: `CLAUDE.md`,
`docs/MISSIONS_DESIGN.md` §22 (its W3 paragraph), `docs/prompts/l2-w3-contract.md` (rulings from L2-48, §13 Ben's
answers and lead rulings, §14 accepted changes and the four QUEUED fixes Q1–Q4 — do not re-report those), the
reports in `docs/prompts/l2-w3-reports/`.

Judge against what Ben must get: (1) the Frost Hammer is owned only through the Studio lever (I) until the Castle,
shows locked "Found in the Castle" in the Armory, and never kills a boss faster than the Broadsword; (2) each swing
freezes a patch of water ahead (server-owned, reset per run, abilities never freeze), the ice lasts the run, and
about 9 swings reach the island; (3) the island shrine is out of reach without ice by every means (jumps 18/30,
dash, walk-off grace, every lifting arc incl. Impale Dash held in the air, wall tops), and pays once only to an
owner of the ice key; (4) the water is deep and a fall comes back to the road by the creek; the main path and a
one-jump first run never need ice; (5) phones can freeze (auto-swing at water with the server's own rule) and
the panel/card fit; (6) the frozen layout opens no new perch or route; (7) nothing broken in L1/L1b/L1c/L2 W1–W2
(brambles, tunnel, shortcut, origin rule, camera clip). Also: --!strict, constants only in config, client/server
and Luau/Python mirrors identical, non-vacuous tests, part budget, per-frame costs.

Severity: Critical, Major, Minor. Each finding: file:line, what, a concrete failure scenario, a fix. Run tools on a
`git archive HEAD` copy in your scratchpad, never in the worktree. Write findings to
`docs/prompts/l2-w3-review/<slice>.md` and end your reply with the list. Edit the shared reviewer memory only with
Edit. Commit nothing; kill only your own PIDs; Python `py` (`py -3.12` for sim_range; `py -I` for scratch
scripts); harness `py tools/crowd_harness/run_harness.py <repo root> C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
