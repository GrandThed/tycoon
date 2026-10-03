---
name: m13-valley-review
description: M13 "The Valley" reviews 2026-10-02 — wave 1 (server-built sky/ground/hub/roads from World.json, WorldPlan ring maths) and wave 2 (28 baked meshes, mesh mode, colliders, aprons, client river rule): verdicts, the probes that settled them without Studio, platform facts, what to recheck after the m11/m12 merges
metadata:
  type: project
---

**M13 wave 1 (2026-10-02, worktree `tycoon-m13` branch `m13-valley`, uncommitted on e5df035; SHIP: 0
Critical, 1 Warning, Suggestions).** Server-only: `src/shared/WorldPlan.luau` (pure ring maths moved
out of `PlotService.buildWorld`), `src/server/World/Landscape.luau` (plain module, built once inside
`PlotService.Init`), `Catalog.GetWorldConfig`, `World.json`. Both builds, stylua, selene (only the
old LegacyPanel:200 warning) and luau-lsp on both trees were green; every finding came from reading
and a Python mirror.

**Why:** waves 2 (mountains kit, invisible wall, ground ramps, aprons) and 3 (river, lake, colliding
bridges) extend the same `Landscape.Build` call and the same config file.

**How to apply (recheck at the next wave):**
- **The lead edits the contract and the config while the review runs.** Mid-review `World.json` lost
  its `lighting`/`clouds` blocks and changed every size, and INTERFACES gained a "must" (`roads.lift`
  lower than `hub.surround.height`) that no code checks. Re-read the contract section and the config
  last, and for each new "must" grep for the check that enforces it.
- **A block missing from the committed config is a code path the playtest never runs.**
  `applyLighting` and `applyClouds` execute for the first time when someone adds the block, at server
  boot, before Spawn and the plots exist, with no `pcall`. Ask which blocks the shipped file omits.
- **Engine property names can be checked from the repo:** `tools/types/globalTypes.d.luau` declares
  classes as `declare extern type <Class> extends Instance with`. Grep that exact form and print the
  following lines. Never grep the bare class name: line 1 is a 20 KB metadata line. Value ranges are
  not in it and stay platform knowledge.
- **Boot path rule:** anything inside `PlotService.Init` that throws leaves no Spawn, no plots and
  no remote handlers. Landscape validates every hand-edited value before use (type, range, material
  by scanning `GetEnumItems`, never `Enum.Material[name]`), and nothing in it yields.
- **Combat place:** it mounts `src/server/Services` but not `src/server/World`. The hub services it
  can reach are exactly DataService, ProfileSchema, RemoteService and StudioBridge (a 30-line script
  that walks `WaitForChild("<Service>")` requires from `src/combat` gives the closure). PlotService
  now waits forever on `Server.World` at module scope, so the closure must never grow to include
  PlotService, MonetizationService or LegacyShopService.
- **Merge trial without touching git state:** `git show <base>:<f>` and `git show <branch>:<f>` into
  the scratchpad, copy the working file, then `git merge-file -p cur base theirs`. It works on
  uncommitted changes. Run the same trial for plain `main` first: both INTERFACES.md conflicts with
  `m11-unlocks` exist without M13 (m11's merge base is 07f8908, far behind main).
- **Numbers (plotSize 120x1x120, margin 20, hub 30):** ring radius 277.0217 for 10 plots, 183.9230
  for 6; front edge 217.0217 / 123.9230. Road strips start at the hub wall (30) and end exactly on
  the plot front face. Every era's street 1 starts on plot-local x = 0 (Village z -56.5, Boomtown
  -54.5, Metropolis and Orbital -49), so a radial road lines up with the entrance. Village fabric has
  no skirt entry past the front edge; skirt reaches 16 studs past sides and back. Re-run that probe
  on each new era's fabric: a skirt clump in front of a plot would stand on the road.
- **Flat end against a round wall leaves a sliver:** `r - sqrt(r^2 - (w/2)^2)` (0.15 at hub 30,
  width 6). It is hidden only while the surround covers it.

**M13 wave 2 (2026-10-02, `fef4b1c..2179a21`, the Valley meshes; SHIP: 0 Critical, 2 Warnings).**
28 generated meshes (`tools/world/valley.py` -> `assets/build/world`, `Valley.json`, templates under
`templates/_world/Valley`), server "mesh mode" in `Landscape` (clones + invisible wall / bridge /
stone colliders + era-tinted aprons via `AttachPlot`), client skirt rule in `WorldBlock`. All static
checks and `valley.py check`, `worldplan.py selftest`, `gen_templates --check` were green.

- **A fallback list in a contract is a list of conditions the code will test and nothing more.**
  Mesh mode tested Valley.json, the template folder, plotCount and required meshes, so removing
  World.json (or its `valley` block, or the wall keys) still built the Valley, without its wall.
  Ask of every "degrades to X" rule: which config file is NOT in the condition list?
- **Generated data and uploaded meshes need a hash that meets at runtime or in QA.** `planHash` is in
  Valley.json, the bake record and Assets.json, and no gate compares them: `valley.py check` is data
  vs a fresh build, `gen_templates --check` is templates vs Assets.json. A rebuild without an upload
  stays green. World.json `ground`, `hub`, `roads` and `wall.segments` feed the hash, so tuning them
  means a re-bake and a harvest paste.
- **Probe recipe (no Studio, no Blender):** the worktree has the shared `assets/` junction, so
  `assets/build/world/Valley/*.glb` and the bake record are readable. A 40-line GLB reader (one node,
  one primitive, float32 POSITION, uint32 indices) gives: per-mesh top/bottom, the bridge's principal
  axis (sign of cov(x, z)) against `yaw`, stones inside `Details`, river samples under `Water`
  triangles with a z-mirror control, basin overlap and coverage by a 16-stud grid hash. Templates:
  position == bake centre, rotation R00 = R22 = -1, and Assets.json offset == (-cx, cy, -cz), which
  is Studio's own evidence that the import is a turn and not a mirror.
- **Numbers:** basin top 0.10, aprons 0.16, river bed 0.22, water 0.35 (its edge skirt dips to
  0.06), bridge deck 0.70, stones 0.62; wall 36 slabs 63.50 x 160 x 4 at radius 360.9, inner face
  358.9; Village skirt woods reach radius 359.4; the river rule blocks 3 skirt entries on each of
  plots 1, 6, 7, 10 and none elsewhere; Boomtown's skirt (m12 tip 2827521) comes nowhere near it.
- **WedgePart:** slope rises toward local +Z, the upright face is Back (worked from the two-wedge
  triangle construction). **CanQuery false has no effect while CanCollide is true** (engine docs,
  not checkable in the repo), so "invisible collider that raycasts ignore" does not exist as a
  property combination; the default camera skips fully transparent parts anyway.
- `rojo sourcemap --include-non-scripts` lists every instance: the cheap way to count templates under
  a mapped folder and to prove a `globIgnorePaths` entry leaves nothing stray, for both places.

See [[review-workflow]] and [[m12-growing-city-review]].
