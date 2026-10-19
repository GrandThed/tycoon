# L2 W3 third fix round (lead's rulings, 2026-10-19)

Findings: `docs/prompts/l2-w3-review/fix-diff.md` (fd-m1, fd-m2, fd-s1, fd-s2). Work only in
`C:\Users\benja\Desktop\tycoon-p5b` (branch `l2-w3-fix2`); never touch `tycoon-p5` (QA is live there). You own every
file this round needs, alone. Read `docs/prompts/l2-w3-reports/fix2.md` and `fix-data.md` first.

- **fd-m1:** move the island so none of its faces lies on a pond row/column line (e.g. z 128.5; check x too); add
  a check_levels line "no frozen-cell face is coplanar with another solid's face of the same facing" with a red
  mutant (today's island) and a green control. Re-check every island rule (reach margin ≥ 15, the chest trigger,
  the chain of 16, the crossing's swings) and update BALANCE if a number moves.
- **fd-m2:** ice `thickness` back to 1.9 (`Combat.json`), and the check_levels floor-depth rule records the ruling
  for ice: frozen sheets need only be thicker than a slam can tunnel (state the bound and gate it), not the 4-stud
  camp floor; and server-side, `Holds` leads a falling body's feet by its fall over the commit lag (the same lag
  `claimSlack` uses) before judging. Harness cases (a teammate stepping in at 0.15 s round trip is not encased)
  and mutants.
- **fd-s1:** the phone's airborne test in `iceOnAuto` asks `AirSwing.Judge` (lag 0) — the server's question.
- **fd-s2:** inset only the cell faces that meet open air or a non-ice block; faces shared by two ice blocks
  (creek-to-pond) are not inset. Mirror in `sim_range.ice_cells`, the fill line and check_stage_mirror's box
  comparison.

Done when: harness green (`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5b
C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`); mutate.py filtered to entries in files you changed, 0 uncaught,
plus a stale-text count over all entries; check_levels; check_levels_mutants for the touched cases (`--only`);
check_stage_mirror; `py -3.12 tools/sim_range.py --check`; check_compile; stylua; selene; luau-lsp. Commit nothing;
kill only your own PIDs; scratch in your own scratchpad subfolder with `py -I`; Bash
`export PATH="$HOME/.rokit/bin:$PATH"`; LF. Report to `docs/prompts/l2-w3-reports/fix3.md`.
