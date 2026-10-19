# L2 W3 fix-diff review (brief)

Read-only review of `8112ff3..25528b7` in `C:\Users\benja\Desktop\tycoon-p5b` (branch `l2-w3-fix2`): the W3 fix round
and its second round. Read `docs/prompts/l2-w3-review.md` (requirements, severity), the findings answered
(`docs/prompts/l2-w3-review/server.md`, `client.md`, `data-tools.md`, and the contract's §14 Q1–Q4), the rulings
`docs/prompts/l2-w3-fix-round.md` and `docs/prompts/l2-w3-fix2.md` (plus the lead's: `controls.iceAutoDegrees` 34),
and the reports `docs/prompts/l2-w3-reports/fix-server.md`, `fix-client.md`, `fix-data.md`, `fix2.md`.

Check: each finding really fixed (not only its test) and no new problem. In particular: the landing by last
ground (every phase; a dash-off; Studio lever moves; a fall far from water still goes to the checkpoint; any
exploit from claiming a grounded spot), ice grip, the whole-cell cover and the 0.05 inset (no gap a body falls
through, no new slit, the 0.1 creek-to-pond seam), airborne and body rules (the crossing's first swing from the
bank lip still freezes; a teammate in the water is never encased; the sink 0.5), `SwingStrike` shared by server
and all three client copies, the phone water test's caches (frozen state kept in sync, cost), ghosts by seq, the
one-ring Frost Quake with grounded shards, the new tool rules not vacuous. Run tools on a `git archive HEAD`
copy in your scratchpad, never in a worktree (a QA run is live in tycoon-p5). Findings (file:line, scenario,
fix) to `docs/prompts/l2-w3-review/fix-diff.md`; end your reply with the list. Edit the shared reviewer memory
only with Edit. Commit nothing; kill only your own PIDs; Python `py` (`py -3.12` for sim_range; `py -I` for
scratch scripts); harness `py tools/crowd_harness/run_harness.py <repo root> C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
