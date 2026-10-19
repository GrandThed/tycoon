# L2 W3 second fix round (lead's rulings, 2026-10-19)

Work only in `C:\Users\benja\Desktop\tycoon-p5b` (branch `l2-w3-fix2`); `tycoon-p5` runs the full QA and mutation
suite: never touch it. Read `docs/prompts/l2-w3-fix-round.md` and the reports `docs/prompts/l2-w3-reports/fix-server.md`
(its "Known limits and risks"), `fix-data.md` and `fix-client.md`. You own every file this round needs, alone.

- **Q5 (lodged body):** a swing made while the swinger is airborne freezes nothing on the server (the phone
  already never auto-swings at water while airborne); and no cell freezes while any player's body overlaps it.
  The client's ghost follows the same rules (no ghost for an airborne swing or a cell holding a body). Pure rule in
  WorldReact where possible; harness cases and mutants; sim_range/check_levels mirrors if they model the crossing.
- **Q6 (edge shimmer):** the outermost ice cells' outer faces are inset by a small constant from the water block's
  faces (config, e.g. `levels.react.ice.inset` 0.05), mirrored in `sim_range.ice_cells` and the check_levels fill
  line (the fill rule must allow that inset and still go red on a real gap).

Done when: harness green (`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5b
C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`); mutate.py filtered to entries in files you changed, 0 uncaught,
plus a stale-text count over all entries; check_levels; check_levels_mutants for the touched cases (`--only`);
check_stage_mirror; `py -3.12 tools/sim_range.py --check`; check_compile; stylua; selene; luau-lsp (both
sourcemaps). Commit nothing; kill only your own PIDs; scratch scripts in your own scratchpad subfolder with
`py -I`; Bash `export PATH="$HOME/.rokit/bin:$PATH"`; LF. Report to `docs/prompts/l2-w3-reports/fix2.md`.
