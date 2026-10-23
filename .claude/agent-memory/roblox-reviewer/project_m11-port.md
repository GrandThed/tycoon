---
name: m11-port
description: M11 port review (feature unlocks + 6-plot hub ported onto main as profile v9, 2026-10-23) - slice S 0C/0M/4m/3s; fix diff 0C/0M/2m/3s (kick on a bool that also means no-state; pinned read, unpinned write); blanket-rename into the other place's same-named module, order-vs-features silent hide, plotless overflow at 6 plots, FeatureService unharnessed; verified facts and the scratch harness recipe
metadata:
  type: project
---

Slice S of the M11 port (branch `m11-port` in `tycoon-m11`, reviewed at 938cb39, 2026-10-23): 0 Critical, 0 Major, 4 Minor, 3 Suggestions.
The findings are in `docs/prompts/m11-port-review/S.md`. Slice C (the client) is a separate reviewer's.

**Patterns (recheck at any rename or port):**
- **A blanket rename across two places that share a module name.** M11's `UnlockService` became `FeatureService`. The
  replace also rewrote `Types.luau`'s comment about the dungeon's `UnlockService.GrantFirstClear`. Probe: run
  `git diff main...branch | grep '^-.*<OldName>'` and read every removed line. A DoD grep that searches only for old names
  cannot see this.
- **A config with both an `order` list and a `features` map.** Evaluate iterates `order`, while visibility gates every key
  in `features`. An id in the map but missing from `order` is hidden forever, with no warning, and a test that pins the
  order string still passes. Ask for a set-equality check.
- **Shrinking the server is also a capacity rule.** At plotCount 6, a 7th player gets no plot, every buy is refused, and
  `grantIncome` still pays from `slots`. Nothing reads `Players.MaxPlayers`, so the Creator Hub setting is the only guard.
- **Hub services stay unharnessed.** The harness loads only `src/shared` and combat modules. FeatureService, the
  PartyService hook position and Main's join order are under no gate, the same as L2/L3's "service lines unharnessed".

**Verified facts (safe to reuse):**
- The live pair is 2b15570. Its `runMigrations` is `while state.version < 6`, so any newer profile (v7, v8, v9) skips it.
  Reconcile only fills.
- `combat.project.json` maps all of `src/shared`, so `Features.luau` and the `Config/Features.json` module are in the dungeon
  place. ProfileSchema requires them at module scope, so they must stay there.
- The default greedy run of `sim_economy.py` is byte-identical between main and m11-port, because neighbours is pinned
  to 1.
- WorldPlan ring radius at 6 plots is 183.92: adjacent plots are 183.9 apart and the same distance from the hub.

**Recipe:**
- Make a scratch copy with `git archive HEAD src tools $(git ls-files '*.project.json' '*.toml')`.
- Include the project files: one harness check reads `combat.project.json` (CameraMaxZoomDistance) and fails without it.
- Run `run_harness.py <tree> <main>/tools/bin/luau.exe`. It takes about 45 s and reports PASS 4,749 at 938cb39.
- For luau-lsp, write sourcemaps to scratch (`rojo sourcemap ... -o <scratch>`) and run it from the repo root. That works
  without touching the worktree's sourcemap.json.

**Fix diff (fix round 1, 4c5a22d, 2026-10-23): 0C/0M/2m/3s** in `docs/prompts/m11-port-review/fix-diff.md`.
- **A fix that acts on a boolean that conflates two failures.** F4 made Main kick when `ClaimPlot` returns false, but false
  also means "state nil". That happens after a session steal mid-join, or when Depart is re-tapped during a failed-teleport
  rejoin, which releases the profile under the join's pass-refresh yield. Before F4 both were silent no-ops. Probe: for any
  new action on a helper's result, list every branch that returns that value.
- **A pinned read with an unpinned write.** Income now gates on the `PlotIndex` attribute. The pins held `hasPlot`'s read
  but not ClaimPlot's `SetAttribute`, so deleting the write (nobody earns) passed the harness. With string-coupled
  state, pin both ends.
- **Order pins that test "after the guards" but not "before the next block".** The invite hook could move below the
  busy/full returns, against INTERFACES M11 "whether or not the join succeeds".
- **A mutant caught only by a throw.** The harness has no `workspace` global, so a dropped `isStudio` gate on the Workspace
  levers "fails" only because the bundle stops.
- **Recipe:**
  - Review-only mutants go in a second `git archive` copy, with the driver in `scratch\drv\probe.py`.
  - Write files back with `write_bytes`, because Python `write_text` on Windows turns LF into CRLF and stylua then flags
    every touched file. Reading via `read_text` normalises, so harness verdicts were still valid.
  - Stale check over the whole `mutate.py` list without running it: exec the source up to
    "# The unmutated bundle first." (2,182 entries, 0 stale).
  - `rojo sourcemap` fails inside an archive copy (Packages are gitignored), so run it from the worktree with
    `-o <scratch>`.
  - A filtered 40-entry mutate run takes about 15 min, and its log is empty until exit (buffered).

See [[review-workflow]], [[l3-armory]], [[l2-secrets]].
