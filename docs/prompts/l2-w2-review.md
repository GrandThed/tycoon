# L2 W2 review (brief)

Read-only review of `main..l2-w2` (HEAD) in `C:\Users\benja\Desktop\tycoon-p5`. Read first: `CLAUDE.md`,
`docs/MISSIONS_DESIGN.md` §22 and its W2 paragraph, `docs/prompts/l2-w2-contract.md` (rulings L2-29..47, §10
Ben's answers, §11 the lead's rulings), the reports in `docs/prompts/l2-w2-reports/`. Accepted deviations: stream
20 × 7, Dragon's Breath 36 / refund 0.5, the pair comparison and the 4.0–5.75 band, CaveMouth/CaveExit sniper
spots, shortcut found from either end, unowned families shown locked only when a secret pays them.

Judge against what Ben must get: (1) the Flamethrower equips from the lobby Armory only once owned (W1's
lookout chest), never mid-fight, server-validated and rate-limited, and never kills a boss faster than the
Broadsword; (2) a fire family burns the brambles (and nothing else does), server-owned, reset every run; (3) the
tunnel is sealed without fire by every means (jumps, dash, every ability, roof gaps, wall tops, the cache
alcove), walkable with one jump once burnt, and the cache pays once only to an owner of the fire key; (4) the
shortcut is saved for the finder and the leader's save opens it for the party on later runs; (5) the bend gap is
closed; (6) the camera never shows outside the ridge in the tunnel; (7) phones and gamepad for the Armory panel
and the stream's auto-fire; (8) levers inert outside Studio and in the range. Also: --!strict, constants only in
config, client/server and Luau/Python mirrors identical, non-vacuous tests, nothing broken in L1/L1b/L1c/L2 W1.

Severity: Critical, Major, Minor. Each finding: file:line, what, a concrete failure scenario, a fix. Run tools on
a `git archive HEAD` copy in your scratchpad, never in the worktree. Write findings to
`docs/prompts/l2-w2-review/<slice>.md` and end your reply with the list. Edit the shared reviewer memory only
with Edit, never Write. Commit nothing; kill only your own PIDs; Python `py` (`py -3.12` for sim_range); Bash
`export PATH="$HOME/.rokit/bin:$PATH"`; harness: `py tools/crowd_harness/run_harness.py <repo root> C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
