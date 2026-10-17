# L2 W1 fix-diff review (brief)

Read-only review of `a21f153..d6b3777` in `C:\Users\benja\Desktop\tycoon-p5` (the W1 fix round only). Read
`docs/prompts/l2-w1-review.md` (requirements, severity scale), the findings answered
(`docs/prompts/l2-w1-review/server.md`, `client.md`, `data-tools.md`), the rulings
`docs/prompts/l2-w1-fix-round.md`, and the reports `docs/prompts/l2-w1-reports/fix-server.md`, `fix-client.md`,
`fix-data.md`.

Check: each finding really fixed (not only its test); no fix opened a new problem. In particular: players not
colliding with players (anything that relied on it: the lobby, the L1c close and entry, rescue points, bots,
the range); the walk-off grace (can it give an extra jump, chain with the air jump, or reach the lookout?);
the footprint trigger (only the ledge and the chest open the lookout; the cache from beside it); the HUD rows
and the gamepad panel (ButtonY/ButtonB priorities against the run's bindings, A buying without jumping);
`Unlocks.Apply` and `SecretFlow.Open` keeping the no-yield check-then-write; the shared caps; the harness
source-reading check not vacuous. A QA agent runs the full mutation suite in this worktree at the same time:
run your own tools on a `git archive HEAD` copy in your scratchpad, never in the worktree. Findings
(file:line, scenario, fix) to `docs/prompts/l2-w1-review/fix-diff.md`; end your reply with the list. Commit
nothing; kill only your own PIDs; Python `py`; harness luau `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
