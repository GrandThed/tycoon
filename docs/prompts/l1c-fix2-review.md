# L1c second fix-diff review (brief)

Read-only review of `ef6fe6b..l1c-chief-clearing` (HEAD 71fba13) in `C:\Users\benja\Desktop\tycoon-p5`: the
second fix round only. Read `docs/prompts/l1c-review.md` (requirements, severity scale), the findings it
answers (`docs/prompts/l1c-review/fix-diff.md`, F1–F4), the rulings `docs/prompts/l1c-fix2.md` plus the
lead's F2 ruling (code option a: a fighter in a gate's lane is nudged only along the inward normal to
`inner`, other coordinate, height and velocity kept; others still go to `entry`), and the reports
`docs/prompts/l1c-reports/fix2-code.md`, `fix2-data.md`.

Check: F1–F4 really fixed; the trigger ceiling cannot let a player trigger C from outside the wall or from
a spot above it, nor leave a non-triggering hole; the nudge (PivotTo, no `Placed`, ForgetMotion) cannot
push a player into the fence, out of the floor, or desync the client's claimed position / swing slack; two
players, one in the lane and one on the road; the new `StrikePick` keeps every non-held behaviour of
`Strike`, the Chain Gun ray and `chainFrom` identical (compare against `ef6fe6b`); Luau/Python mirrors agree;
new checks are not vacuous. A QA agent runs the full mutation suite in this worktree at the same time: run
your own tools on a `git archive HEAD` copy in your scratchpad, never in the worktree. Findings (file:line,
scenario, fix) to `docs/prompts/l1c-review/fix2-diff.md`; end your reply with the list. Commit nothing; kill
only your own PIDs; Python `py`; harness luau `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
