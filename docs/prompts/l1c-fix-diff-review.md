# L1c fix-diff review (brief)

Read-only review of `2a58134..l1c-chief-clearing` in `C:\Users\benja\Desktop\tycoon-p5`: the fix round and the
margin ruling only. Read `docs/prompts/l1c-review.md` (requirements, severity scale), the findings it answers
(`docs/prompts/l1c-review/code.md`, `data-tools.md`), the rulings `docs/prompts/l1c-fix-round.md`, and the
reports `docs/prompts/l1c-reports/fix-code.md`, `fix-data.md` (incl. "Margin ruling", accepted by the lead:
Hard/Brutal extra unit is a fodder, Colossus 42,900 / 76 Timber).

Check: each finding is really fixed (not just its test); no fix opened a new way to see into the clearing
(camera clip release, double-jump, 0 s gate with two players, skips/levers, reset disable timing); the 0 s
gate path in StageFlow cannot loop or skip the ambush; client/server and Luau/Python mirrors still agree;
the new checks are not vacuous. Findings with file:line, failure scenario, fix, to
`docs/prompts/l1c-review/fix-diff.md`, and end your reply with the list. Commit nothing; kill only your own
PIDs; Python is `py`; Bash `export PATH="$HOME/.rokit/bin:$PATH"`; harness luau: pass
`C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe` as run_harness.py's second argument.
