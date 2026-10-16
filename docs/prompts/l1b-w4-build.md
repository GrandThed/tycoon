# L1b Wave 4 build — common brief for the four owners

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave4`. Never edit the main checkout
`C:\Users\benja\Desktop\tycoon` (only run its `tools\bin\luau.exe`).

## Read

1. `docs/INTERFACES.md` "# L1b Wave 4 — no waits, no walls" to the end of the file: the lead's
   rulings L1b-W4-1…13, the contract (rulings 14–33 and every subsection), and "Lead's answers to the
   draft points". The answers win over the body, and the body wins over the study.
2. Your own subsection(s) in full: Server modules (A, B), Client (ui-engineer), Config and Balance
   bands (economy-designer), and for everyone Types, Ownership, Gates, Definition of done.
3. `docs/prompts/l1b-w4-study-report.md` only where the contract points to it.
4. `docs/SPEC.md` only if you need context. `docs/MISSIONS_DESIGN.md` §19 has Ben's words.

## Rules

- Own only the files the Ownership table gives you. A change in someone else's file: write it under
  "For other owners" in your report (file, function, exact change) and carry on; the lead routes it.
- Order: A lands the Types block first (commit it alone and say so in the report); the designer
  lands `Combat.json` first. If you need a type or a key that is not there yet, check `git log` and
  wait briefly rather than invent it.
- One worktree, four agents: commit only your own paths (`git commit -m "..." -- <paths>`, after
  `git add <paths>`), retry if `index.lock` is held. Never `git add -A`, `git stash`, `git reset`,
  `git checkout -- <others' files>`. Messages one line, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Luau: `--!strict`; PascalCase modules, camelCase locals, UPPER_SNAKE constants; no `wait`,
  `spawn`, `delay`, `_G`, no parent argument in `Instance.new`; constants only in
  `src/shared/Config/*.json`; pure modules stay pure; no yields in the run loop; keep every module
  within about 180 top-level locals (`py tools/check_compile.py --counts`). Comments say why, not what.
- Environment: Bash `export PATH="$HOME/.rokit/bin:$PATH"`; Python is `py`; files LF. The harness:
  `py tools/crowd_harness/run_harness.py C:\Users\benja\Desktop\tycoon-p5
  C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`. Do NOT run `mutate.py` (QA runs it; two hours).
  Kill only your own processes, never by image name.

## Verify before you report (your part)

- Luau owners: `stylua --check src`, `selene src`, `py tools/check_compile.py`, the harness (once the
  other owners' parts it needs are in; if it fails on another owner's missing part, say which).
- Designer: `py tools/sim_range.py --check`, `py tools/sim_combat.py --check`,
  `py tools/check_levels.py`, `py tools/check_stage_mirror.py --luau C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`,
  `py tools/crowd_harness/mirror_mutants.py` if the contract names it.

## Report

Write it to `docs/prompts/l1b-w4-reports/<owner>.md` (commit it with your work) and repeat it as your
final message: what you built (file, function), the commits, each verify command's verdict line,
"For other owners", and anything in the contract you found wrong. You MUST end with the report.
