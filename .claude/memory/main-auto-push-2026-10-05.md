---
name: main-auto-push-2026-10-05
description: Commits and merges made in the main checkout reach origin/main within a minute, without anyone running git push
metadata:
  type: project
---

Commits and merges on `main` in the main checkout (`C:\Users\benja\Desktop\tycoon`) are pushed to
`origin/main` (github.com/GrandThed/tycoon) within about a minute, without the lead running `git push`.
Found 2026-10-05: `git reflog show origin/main` reads "update by push" at 11:00:15, a minute after the
Metropolis fast-forward, and the same after the commits of 2026-10-02 and 2026-10-04. Ben's editor (the
VS Code git sync in that folder) is the likely source; worktrees on other branches are not pushed.

**Not guaranteed (same day):** the three commits of 11:02–11:08 (2be638d, 91a66ac, de523bc) were still
local at 11:54. `git ls-remote origin refs/heads/main` answered d0dd894 and `git status -sb` read
"ahead 3". The sync is something Ben's editor does when it does; it is not a rule of the repo.

**Why:** earlier notes and docs say "merged, not pushed" for Boomtown, the Valley and Metropolis. That was
true when written and false minutes later, and the lead told Ben "nothing is pushed" when it already was.

**How to apply:** treat a commit or merge on `main` in the main checkout as published. Do anything that
must not reach GitHub yet on a branch in a worktree, and only merge to `main` after Ben's sign-off. Before
reporting push status, run `git status -sb`; never say "not pushed" from memory. See
[[metropolis-growth-2026-10-02]] and [[boomtown-growth-2026-10-01]].
