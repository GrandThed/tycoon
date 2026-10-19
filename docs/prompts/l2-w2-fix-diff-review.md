# L2 W2 fix-diff review (brief)

Read-only review of `e14fb78..78463a0` in `C:\Users\benja\Desktop\tycoon-p5` (the W2 fix round only). Read
`docs/prompts/l2-w2-review.md` (requirements, severity), the findings answered
(`docs/prompts/l2-w2-review/server.md`, `client.md`, `data-tools.md`), the rulings `docs/prompts/l2-w2-fix-round.md`
(plus the lead's corner ruling: the origin check refuses only an origin truly beyond a wall, with a Studio warn;
and the lead moved the tolerance to `ProvingGrounds.json shooting.originWallChord`), and the reports
`docs/prompts/l2-w2-reports/fix-server.md`, `fix-client.md`, `fix-data.md`. Accepted: the AB and BC ability-arc
hops (~3–4 s, no camp skipped) are a known limit until L3.

Check: each finding really fixed (not only its test) and no new problem. In particular: the origin wall rule
(legitimate shots refused anywhere else — doorways, the gatehouse, the lookout ledge, ADS, phones; forged origins
still refused; cost per shot), phone auto-fire at brambles (never at a resting body, never through a wall, stops
when burnt; cost per frame of scanning Parts), the flame drawn from ShotRay (identical to the server's capsule),
`WorldReact.Apply` keeping every old behaviour, the 84-high pieces (no gap at the 64/84 seams, camera and
tunnel look unaffected), the new check_levels rules not vacuous. A QA agent runs the full mutation suite in
this worktree at the same time: run your tools on a `git archive HEAD` copy in your scratchpad. Findings
(file:line, scenario, fix) to `docs/prompts/l2-w2-review/fix-diff.md`; end your reply with the list. Edit the
shared reviewer memory only with Edit. Commit nothing; kill only your own PIDs; Python `py`; harness:
`py tools/crowd_harness/run_harness.py <repo root> C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
