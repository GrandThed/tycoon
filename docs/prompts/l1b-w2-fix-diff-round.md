# Brief: the fix-diff round (L1b Wave 2)

Fresh luau-engineer. Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave2` (HEAD
cdad4f4 or later); every Bash call starts with `cd /c/Users/benja/Desktop/tycoon-p5 &&`. Every
owner has finished, so you may edit the files named here. Read `docs/prompts/l1b-w2-review/fix-diff.md`
(the findings), `docs/prompts/l1b-w2-reports/fix-A.md` (the landing rule) and
`docs/prompts/l1b-w2-build.md` (rules, verify list). Run `git status` / `git diff` first.

1. **M1 (lead ruling: the reviewer's fix):** in `src/shared/SwingGate.luau` the "landing ahead"
   branch of `Judge` applies only when `lagSeconds > 0` (the server). The client (lag 0) never takes
   it. Fix the false comment (lines ~199-201) and fix-A.md's claim. Harness case at lag 0 in
   `tools/crowd_harness/tests_l1b_w2_crowd.luau`: apex swing allowed, late-fall swing refused,
   touchdown, walk, new jump, apex swing allowed; plus the held-Space hop at swing intervals 0.25 /
   0.35 / 0.5 s over many hops: never two swings in one hop, never a hop with none (client side),
   and no server refusal of a client-allowed swing at the lag the server allows. A mutation that
   deletes the guard, in `tools/crowd_harness/mutate.py`; a mirror mutant in
   `tools/crowd_harness/mirror_mutants.py` only if the rule is mirrored there.
2. **m1 (lead ruling):** the client judges a turn-landing with a stricter window than the server
   (0.05 s against 0.1 s), so a double jump high up never reads as a landing on the client only.
   Put both windows in `SwingGate` as named constants (the client passes its own), the client in
   `src/combat/client/Controllers/AirSwing.luau`; a harness case for the double jump at 6-7 studs
   (client refuses the second swing, the server never refuses a client-allowed one) and a mutation.
3. **m2:** add `TentOwesRouse` to `check_stage_mirror.py`'s `NEEDED` list with a comparison over
   all its inputs; make `sim_range.py`'s `group_up` read the state the server reads (the trailing
   `awakeGroups`, one tick behind), or state in a comment why the difference cannot change a result.

Verify, one after the other: stylua, selene, luau-lsp analyze (both sourcemaps,
`tools/types/globalTypes.d.luau`), `py tools/check_compile.py`, the harness
(`py tools/crowd_harness/run_harness.py . C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`), then
`mutate.py` (same args), `py tools/check_stage_mirror.py`, `py tools/sim_range.py --check`,
`py tools/sim_combat.py --check`, `py tools/check_levels.py`, `py tools/crowd_harness/mirror_mutants.py`.
Re-point any STALE mutant, never delete one. Report to `docs/prompts/l1b-w2-reports/fix-diff-round.md`.
No git writes; kill only your own PIDs.
