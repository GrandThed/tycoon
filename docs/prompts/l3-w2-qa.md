# L3 Wave 2 QA — the quick gates (brief for qa-runner)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-w2`, at 31b1947 or later. Run every command below from the
worktree root in Bash, in order, and report each one's verdict. **Change no source file** (the sourcemaps and the place
files in `build/` are generated and may be rewritten). Kill only your own PIDs. **Never run `mutate.py`,
`check_levels_mutants.py`, an uploader, `harvest.py` without `--emit`, or any `--dry-run`**; never touch
`C:\Users\benja\Desktop\tycoon-p5b`. Do not run `mirror_mutants.py` beside anything else.

```bash
export PATH="$HOME/.rokit/bin:$PATH"
L=C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe
stylua --check src
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
py tools/assets/weapon_frames.py --check
py tools/assets/gen_templates.py --check
py tools/gen_asset_manifest.py --check
git diff --exit-code main -- src/combat/client/Controllers/InputController.luau src/shared/Config/Armory.json src/shared/Config/Combat.json src/shared/Config/ProvingGrounds.json src/shared/Config/Levels src/shared/Layouts && echo "UNTOUCHED: PASS"
git ls-files --eol | grep -c "w/crlf"
```

- Known and not a regression: selene's one warning in `src/client/UI/LegacyPanel.luau:200` (shadowing; it predates L3).
- Batch several quick commands into one call to save turns; `mirror_mutants` takes about 35 minutes.
- **You MUST end your turn with the report, even if every command passes:** a table of command → PASS / FAIL with the
  counts each prints, then every failure with file:line and the exact message. Never treat a missing verdict as a pass.
