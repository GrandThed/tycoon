# Brief: the fix round's tail (B-3 at once, B-4 rising tent bodies)

Fresh luau-engineer. Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave2`; every Bash
call starts with `cd /c/Users/benja/Desktop/tycoon-p5 &&`. Every other owner has finished, so you
may edit the four files below (and only these, plus the harness files named):

Read `docs/prompts/l1b-w2-fix-round.md` (B-3, B-4 and their rulings), then
`docs/prompts/l1b-w2-reports/fix-B.md` "For the other owner" (the exact diffs), and
`docs/prompts/l1b-w2-build.md` (rules, verify list). Run `git status` / `git diff` first.

1. `src/shared/Types.luau`: `rises: boolean?` on `CrowdSpawnInfo`.
2. `src/combat/server/Services/CrowdService.luau`: `SpawnResident(kind, group, post, from: Vector3?)`:
   spawn at `from or post.at`, keep `post.at` as the anchor, set `spawnInfo.rises = true` when
   `from` is given (as fix-B.md request 1). Clear `rises` from the info once the body has stood up,
   so a late joiner does not see a rise replayed.
3. `src/combat/server/Services/CampBrain.luau` (lead ruling: **taken**, B-3 says "roused at once"):
   `Rouse` also rouses from `home`; in `campStep` the rouse event carries the state it left
   (fix-B.md request 3).
4. `src/combat/server/Services/WaveService.luau`: B's line becomes
   `CrowdService.SpawnResident(kind, tent.group, post, planned.doors[following])`.
5. `src/combat/client/Controllers/CrowdRenderer.luau`: `entity.rises` from `info.rises == true`, and
   `if entity.summonerId ~= 0 or entity.rises then` (fix-B.md request 2).
6. Harness cases in `tools/crowd_harness/tests_l1b_w2_crowd.luau` (a tent body spawns at its door,
   anchored at its post, rises; a group walking home is roused by a tent's owed rouse) and a
   mutation for each in `tools/crowd_harness/mutate.py`. If `tools/crowd_harness/mirror_mutants.py`
   or `sim_range.py` mirror `Rouse`, keep them equal (a STALE mutant must be re-pointed, never
   deleted).

Verify: stylua, selene, luau-lsp analyze (both sourcemaps, `tools/types/globalTypes.d.luau`),
`py tools/check_compile.py`, then `py tools/crowd_harness/run_harness.py . C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`,
**then** `py tools/crowd_harness/mutate.py` (same args), then `py tools/check_stage_mirror.py`,
`py tools/sim_range.py --check`, then `py tools/crowd_harness/mirror_mutants.py`. Never two of the
harness / mutate / mirror_mutants at once. Report to `docs/prompts/l1b-w2-reports/fix-tail.md`. No
git writes; kill only your own PIDs.
