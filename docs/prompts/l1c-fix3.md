# L1c third fix round (lead's rulings, 2026-10-16)

Findings: `docs/prompts/l1c-review/fix2-diff.md` (m1–m3, all Minor). Read it, `docs/prompts/l1c-fix2.md` and
`docs/prompts/l1c-reports/fix2-code.md`, `fix2-data.md`. Work only in `C:\Users\benja\Desktop\tycoon-p5b`
(branch `l1c-fix2`); `tycoon-p5` runs the full mutation suite: never touch it.

- **m1:** re-anchor the stale mutant in `tools/check_levels_mutants.py` as the reviewer proposes.
- **m3:** at the close, ANY root inside the fenced rectangle and inside the height band (−triggerBelow up to
  the ceiling) is nudged to the nearest point of `inner` (height, other coordinate and velocity kept, no
  `Placed`, ForgetMotion as today); only roots outside the fenced rectangle go to `entry`. Mirror in
  `sim_range.gate_nudge` and `check_stage_mirror`; harness case for a diagonal dash seen in the strip beside
  the opening; a mutation that drops the depth test.
- **m2:** put C's `entry` back deeper and off the gate lane's line so a road player placed at the close never
  lands within 3 studs of a nudged lane player (check the whole lane width). Re-check everything that reads
  `entry` (route, sneak, spawns distance, Colossus rise), add a check_levels rule for the 3-stud clearance
  with a mutant case.

Done when: harness green; `mutate.py` filtered to every entry whose text sits in a file you changed (and the
`l1c` entries), 0 uncaught, plus a stale-text count over ALL entries (0 stale); check_levels,
check_levels_mutants (with `--luau`), check_stage_mirror, `mirror_mutants --only L1c`, `sim_range --check`
(full), sim_combat green; check_compile, stylua, selene, luau-lsp clean; BALANCE rows updated if numbers
moved. Commit nothing; kill only your own PIDs; Python `py`; Bash `export PATH="$HOME/.rokit/bin:$PATH"`;
harness luau `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`. Report to
`docs/prompts/l1c-reports/fix3.md` and end your reply with it.
