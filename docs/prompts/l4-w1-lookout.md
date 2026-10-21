# L4 W1, track D — the lookout moves to the trailhead (brief for the economy-designer)

Work in `C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest`. Bash with Git Bash syntax; `py` only (never
`python`); rokit tools need `export PATH="$HOME/.rokit/bin:$PATH"`; the Luau CLI is
`C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`. Say which Python gave each number (`py -3.12` vs 3.14; R8's
thinnest rows differed between them before: judge on 3.12, the 64-bit one). Convert files you create to LF. Do not
commit. Kill only your own PIDs, never by image name. Two other agents work in this worktree at the same time (the
forest kit lead in `tools/levels/`, `tools/testfit/levelrender.py`, `tools/assets/forest_*`; the raider kit lead in
`tools/assets/raider_kit*`, `tools/testfit/raider*`): do not touch their files. The forest kit lead reads
`1_ForestRoad.json` for its renders, so finish the layout edit first and write one line to
`docs/prompts/l4-w1-reports/layout-ready.md` as soon as the file holds the new lookout.

## The job

Ben's ruling (MISSIONS_DESIGN §26.1): **the lookout moves to the trailhead**, the study's variant V3
(`docs/prompts/l4-study-report-forest.md` §3). The secrets chain is unchanged: buy Double Jump, reach the ledge, the
chest gives the Flamethrower, burn the brambles at the cave. With V3 the ledge is 132 studs from the nearest region
cell, beyond the bow's 110 and `dormantRadius`, so **`SNIPER_KNOWN_LIMIT_L4` (`tools/sim_range.py:7226`) must become
empty for Normal and Hard, and R8 must pass on every spot** (Ben's ruling of 2026-10-16, restated for Hard in L3).

The exact change the study measured is `docs/prompts/l4-w1-reports/perch_v3_study.py` (its docstring says V1; its
numbers are V3): `LookoutLedge` to x −446, y 11, z −33, size 24 × 30 × 14 (top 26 over Road1); the `lookout` secret to
(−446, 28, −33) and its sign to (−447, 0, −2); the `LookoutSignPad` block and its region cell removed. Check that
the result still reads well: the ledge must be reachable with Double Jump from Road1 and not with one jump plus a dash
(L2-18's lift model judges this), and its sign must stand where a player on Road1 sees it.

## You own

- `src/shared/Config/Levels/1_ForestRoad.json` (the layout).
- `tools/check_levels.py` (`EXPECTED`, the pinned sniper lists) and `tools/check_levels_mutants.py`.
- `tools/sim_range.py` (`SNIPER_KNOWN_LIMIT_L4` emptied; keep the name or remove it with every reader, your call,
  say which) and `tools/check_stage_mirror.py` if it pins anything that moves.
- `tools/crowd_harness/tests_*.luau` lines that read the lookout or the sign pad from the layout (the study names
  `tests_l2.luau:721`; grep for `lookout`, `LookoutLedge`, `LookoutSignPad` in every test), and `mutate.py`
  entries whose text you change (re-aim them in the same edit; the full run refuses stale entries).
- `docs/BALANCE.md`: a short "L4 W1 — the lookout at the trailhead" section with the R8 table before and after.

If anything in Luau (`src/`) names the lookout's position or the sign pad (Studio levers, `SecretFlow`, the camera,
`LevelGeometry`), do not edit it: list it in your report with file:line for the lead to route.

## Done when

1. `py -3.12 tools/check_levels.py` passes with the new layout; `py -3.12 tools/check_levels_mutants.py` passes.
2. `py -3.12 tools/sim_range.py --check` passes (about 14 minutes; run it in the background) with
   `SNIPER_KNOWN_LIMIT_L4` empty for Normal and Hard, and R8 green on every spot; report the clock and the R8 rows
   that moved.
3. `py tools/check_stage_mirror.py` passes; the crowd harness passes:
   `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`
   (first argument is the repo root). Run `tools/crowd_harness/mutate.py` filtered to the entries you touched
   (`files:` per changed file); the full run is QA's at the end of the wave.
4. Your report in `docs/prompts/l4-w1-reports/lookout.md`: what changed, every gate's verdict line, the R8 table, the
   Luau references to route, anything that surprised you. **End your turn with that report's summary even if every
   gate passes.**
