# L3 Wave 1 QA — the quick gates (brief for qa-runner)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`, at 32d7893 or later. Run every command below from the
worktree root in Bash, in order, and report each one's verdict. **Change no source file** (the sourcemaps and the place
files in `build/` are generated and may be rewritten). Kill only your own PIDs. The two long mutation suites
(`mutate.py`, `check_levels_mutants.py`) are run by the lead in another worktree: do **not** run them, and do not run
`mirror_mutants.py` at the same time as anything else.

```bash
export PATH="$HOME/.rokit/bin:$PATH"
L=C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe
stylua --check src tools/crowd_harness
selene src
rojo sourcemap default.project.json -o sourcemap.json
rojo sourcemap combat.project.json -o sourcemap.combat.json
luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.json src/client src/server src/shared
luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.combat.json src/combat src/shared
py tools/check_compile.py
rojo build -o build/test.rbxl
rojo build combat.project.json -o build/combat.rbxl
py tools/proving_project.py && rojo build .proving.project.json -o build/proving.rbxl
rojo build boomtown.project.json -o build/boomtown.rbxl
rojo build metropolis.project.json -o build/metropolis.rbxl
rojo build orbital.project.json -o build/orbital.rbxl
py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 $L
py tools/check_stage_mirror.py
py tools/crowd_harness/mirror_mutants.py --luau $L
py tools/check_levels.py
py tools/sim_range.py --check
py tools/sim_combat.py --check
py tools/sim_economy.py --check
py tools/assets/gen_templates.py --check
py tools/gen_asset_manifest.py --check
git ls-files --eol | grep -c "w/crlf"
```

- Python is `py` only (64-bit; `sim_range --check` is judged on it). `sim_range --check` takes about 10 minutes; run
  long commands with a generous timeout or in the background and wait for them.
- Known and not a regression: one luau-lsp error at `PlotService.luau:1388` on the combat sourcemap (it predates L3).
- Batch several quick commands into one call to save turns.
- **You MUST end your turn with the report, even if every command passes:** a table of command → PASS / FAIL with the
  check counts each prints (harness checks, PASS lines, assertions), then every failure with file:line and the exact
  message. Never treat a missing verdict as a pass.
