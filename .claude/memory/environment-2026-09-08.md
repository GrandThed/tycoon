Environment drift found at the start of the M3 session (2026-09-08) — PLAN §1 was written for
the old machine/profile and is stale on this one:

- Repo now lives at `C:\Users\benja\Desktop\tycoon` and IS a git repo (one "init commit").
- `~/.rokit` did not exist; rokit 1.2.0 was self-installed from GitHub releases and
  `rokit install --no-trust-check` restored rojo 7.7.0 / wally 0.3.2 / stylua 2.5.2 /
  selene 0.31.0 / luau-lsp 1.69.0. Nothing puts `~/.rokit/bin` on PATH automatically —
  PowerShell: `$env:PATH = "$HOME\.rokit\bin;$env:PATH"`; Bash: `export PATH="$HOME/.rokit/bin:$PATH"`.
- Python: only `py` (3.14.7) works. `python` and `python3` are Windows Store stubs that print
  "Python was not found". Every doc/tool/agent command must say `py tools/...`.
- Git had `core.autocrlf=true`, so the checkout was CRLF and `stylua --check` failed on every
  file. Fixed with `.gitattributes` (`* text=auto eol=lf`) + a CRLF→LF pass + `git add
  --renormalize .`. New files written by the Write tool come out CRLF — convert to LF after.
- `.claude/agents/ui-engineer.md` and `docs-keeper.md` failed to register as agent types
  because their YAML `description:` contained an unquoted colon; descriptions are now quoted.
  Until the session restarts, run those roles through `general-purpose` with the persona
  text pasted in.

**How to apply:** at session start, verify `py -V`, `Test-Path ~/.rokit/bin/rojo.exe`, and
`git ls-files --eol | grep -c w/crlf` before delegating QA; put the PATH line and `py` in
every subagent prompt. See [[qa-runner-silent-finish]].
