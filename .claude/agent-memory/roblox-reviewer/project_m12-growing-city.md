---
name: m12-growing-city-review
description: M12 "growing city" reviews (Village waves 1-1c, Boomtown waves 2.0-2.5) — recurring patterns (claim replays as a purchase, plot-frame offsets in rotated layouts, mixed-length lane hold, far wild prefix, turned Parts under a planar texture, a retune that empties a mechanism, gates lowered to pass, a baked mesh wider than the polyline its clearances were tuned on), the scratch probes that settle them without Studio (replay, checker mutation, path GLB reader in plot coordinates), and the numbers found
metadata:
  type: project
---

**M12 wave 1 client review (2026-09-29, worktree `tycoon-m12`, branch `m12-growing-city`, diff vs
495c529; SHIP WITH FIXES: 0 Critical, 2 Majors).** Client-only fabric: pure `CityFabric.Develop`
(+ RectDistance/SegmentDistance/IsCleared), `Fabric.luau` renderer, controller integration gated on
`build.fabric`. Other eras verified unchanged (every new path no-ops without a fabric handle).
Static checks all green; every finding came from reading + scratch simulation.

- **Recurring pattern (highest-value): the controller's `animate` flag cannot tell another
  player's claim from a purchase.** Unclaimed plots publish `EraName = era 1 (Village)`, tier 0
  (`PlotService.publishLobbyAttributes`), so every lobby plot already has a Village build; a Village
  player's claim bulk-restores onto that old build (no era change, no tier drop → no rebuild) with
  `animate = near and build older than lod.refreshSeconds` = true. Any purchase-time effect (reveal
  scaffolds, ripples, dust, and the pre-existing AddSpur path dust) replays for every nearby
  watcher; also for the local plot when data load outlasts `CITY_SNAPSHOT_WAIT_SECONDS`. Recheck
  every new "on purchase" client effect against a neighbour's claim. (Fixed since: a sync that adds
  more than one building resets `createdAt`.)
- **Recurring pattern: plot-frame offsets in a freely rotated (organic) layout.** A contract
  that offsets something from a pad "in the plot frame" lands it inside footprints for slots facing
  ±X (one mid-review layout snapshot put townWall's board inside the owned chapel; the next put 4
  boards inside their own staked lot). Probe per slot, only against what stands while that pad
  shows, and re-run after every layout edit.
- The economy-designer rewrote Village.luau DURING the review (parcel count 48 → 37 between two
  scratch builds): snapshot layout-dependent numbers twice and report the latest.
- **Degradation trap recurred** (wave 2c): only the block's presence is type-checked; sub-keys
  (`pull.*`, `wild.clumps/quarters`) are read raw → a partial config throws in every deferred sync.
- **Probe recipe that quantified everything without Studio:** copy `tools/` + `src/` into the
  scratchpad (never build Fabric JSON in the worktree), run `py tools/fabric.py build Village` there,
  then a ~250-line script porting `Develop` + `buildMask`/`IsCleared` line for line, replaying
  `sim.simulate_era(era, game, legacy, "greedy", city=city).slot_order` with tier = count of
  `tier_times <= t`, pads = unowned slots whose `sim.resolve_requires` parent is owned. Measures
  per-purchase puffs/sites/un-clears, claim totals, instance counts. Walk-lane safety: add parcel
  polys to `streetplan.walk_lanes` + `segment_polygon_distance`.

**Wave 1c client round (2026-09-29, 09460a2..22fa809, 0 Critical / 0 Major / 5 Minor):** rowLag
step 8, town-tree layer, parcelsFar, row-1-only walk solids, treeOak → streetOnly decor. Lessons:
- **A "can never" ruling that removes a safety net must be backed by a check.** Back rows left the
  walk solids on the claim they can't reach a lane; the generator now keeps the walker's whole reach.
- **streetOnly still has a harvested-extents solid on the client** (`Scatter.solidsFor` keeps every
  slot footprint: lamp drop rule, tree spots, the fabric clearing mask), while streetplan's
  `planner_solids` skips streetOnly. Walk solids were fixed (`Scatter.WalkSolids` skips them); the
  mask still clears the invisible rect on purpose and cityfabric.py mirrors that. Recheck whenever a
  slot becomes streetOnly (probe: mirror lamps inside a streetOnly slot's harvested rect).
- Growth steps timed from one sync all fire in the same frame after stageSeconds.
- The coordinator restarted the round mid-review: re-check HEAD, the diffstat and cited line numbers,
  then report from the existing analysis instead of re-reading.

**Wave 1c rounds 2–3 (2026-09-30, 8992174..158cc96, 0 Critical / 0 Major / 3 Minor):** narrow lots,
town trees generalised into name-sorted upgrade layers, flowerBed/bannerPole streetOnly. Lessons:
- **Run tool gates on `git archive HEAD tools src | tar -x` in the scratchpad**, not on a cp of the
  worktree: other agents had uncommitted Assets.json/mirror edits mid-review.
- `py tools/cityfabric.py selftest|timeline <Era>` is the mirror gate; read what the timeline prints
  (a mirror can have the rule and not wire it).
- A pause/rejection of a tool call was a session pause, not a preference: re-check HEAD and rerun.

**Spawn-queue round (2026-09-30, 2ac6839..b364117, 0 Critical / 0 Major / 1 Minor):** per-plot queue
for unanimated spawns; every Sync and Destroy clear it; only syncs enqueue. Lesson: **a per-plot cap
is not a per-frame bound** (fixed since: one shared budget per frame, nearest plot first).

**Wave 2.0 (2026-10-01, branch `m12-boomtown`, e5df035..80bfb78, 0 Critical / 1 Major / 5 Minor):**
Village chimney smoke on fabric houses, carts as a fourth layer. Lessons:
- **The Major was a config value the offline bake hashes** (`eras.Boomtown.road.width` 8 -> 6 with no
  re-bake). Whenever `road.width`, `spurWidth` or a meander key changes, run the bake gate.
- **The bake gate is vacuous in a bare `git archive` scratch tree** (no `assets/`): copy
  `assets/build/paths/<Era>.json` from the worktree into the scratch tree first. Never run it in
  the worktree.
- Per-stage metadata keyed on the WANTED stage vs `PropFactory.Spawn`'s pickStage fallback (fixed:
  `refreshPlume` reads `PropFactory.ChosenStage`).
- `fabric.py check` enforces a layer's `require` minimum and the config budget only; a contract
  range has no upper-bound check.

**Wave 2.2 (2026-10-01, branch `m12-boomtown`, 5bd4227..6183c44, SHIP WITH FIXES: 0 Critical /
1 Major / Minors):** Boomtown organic layout with fabric ON, four more streetOnly slots (decor and
unlock, server untouched), five plan-laid layers, `road.paths.spurWidth` driveways,
`vehicles.unlocks` + `Traffic.Swap`. All gates green in scratch (stylua, selene [LegacyPanel:200
only], luau-lsp on the changed files, rojo build, fabric check x2, cityfabric selftest/timeline,
streetplan x2, bake --list Village 0 / Boomtown 2). Village, Metropolis and Orbital proven unchanged
by diffing `streetplan.py <Era>` text and the Village `bake.py --list` piece table between an
archive of the base commit and HEAD.

- **Recurring pattern (new): a headway rule written for equal-length vehicles breaks when one
  class is longer.** `Traffic` frees a lane when the LEADER has moved its own length + gap; a 6.1-stud
  bus entering behind a 3.2-stud car needs (leader/2 + follower/2), so its nose rides 0.6-0.85 studs
  inside the car until they diverge. A ~150-line Python port of nextLane/claim over
  `fabric.Site('Boomtown').network` (0.6-stud lanes, 24 vehicles, 300 s, 8 seeds) measured it:
  moving pairs overlap in 4.7% of samples cars-only (the accepted wave 2d baseline: transient
  catch-ups while a car waits at a node), 16.5% with the bus share, 5.6% with a follower-aware hold
  (claim = (own half-length + gap)/speed, entry test adds the asker's half-length). Re-run that
  probe whenever a vehicle class, scale or followGap changes.
- **Recurring pattern (new): a far-budget prefix sized for one era starves the next.** `wildFar` 45
  covered Village (37 on-plot clumps); Boomtown has 73 on-plot fields, the prefix is 12 skirt + the
  33 farthest from the entrance, so a tier-0 far Boomtown plot leaves its front 40 cells bare.
  Check every shared `budget.*Far` against each new era's data.
- **A placer that lays nothing is silent.** `billboards` met `require` 8 from three placers while
  `backs` (BillboardC, behind the shop rows) laid 0, so the prop is never used and the slot's
  description is half true. For plan-laid layers, print per-placer and per-variant counts.
- **Mutation testing a checker is cheap and settles "is the rule vacuous":** load the committed
  `Fabric/<Era>.json`, deepcopy, move/turn/re-anchor one entry, call
  `fabric.check_document(era, doc, compare_committed=False)`. 14 mutations all fired (walker reach,
  parcel/marker margin, lot-front lean at +0.3, stretchFacing, minStreets, cleared land, spacing,
  require, budget, variant).
- `fabric.py prop_shapes` uses the plan's `footprints` only until a prop has harvested extents:
  after an upload + harvest the generator's and checker's inputs change, so expect a rebuild.
- Config running ahead of uploads: Village smoke `fabricProps` now lists stage-0/1 chimneys the
  uploaded narrow homes lack (plumes start at y 4.06 over roofs 3.44-4.10 tall: 2 at tier 2-3, 9 at
  tier 4, 15 of 16 at full). Boomtown has no fabric template at all except ParkedA-C, so parked
  cars stand beside invisible houses and nothing smokes.
- Things still sized by road width on a 3-stud driveway (all Minor): the path dust
  (`PathRenderer` Dust.Create), the row-lamp drop rule and tree/greenery keep-outs in Scatter, and
  the `state.width` sample spacing of spur centrelines (fillet radius is now 2 x spurWidth).
- Layout facts: 8 row lamps and 2 signals at full build (was 24 / 6); 104 parcels, 106 wild, layers
  22/25/8/4/14; near full build ~288 clones (202 fabric), far ~107.
- HEAD moved during the review (a manifest + builds commit): `git log <start>..HEAD` before
  reporting, then cite the new hash.

**Wave 2.4 (2026-10-02, branch `m12-boomtown`, 37ab7da..4e4253f, SHIP TO PLAYTEST: 0 Critical /
2 Major / Minors):** back lanes (pure `LaneReach`, lane distance in `Develop`, lane Parts in
`Fabric.luau`), the `DebugStartEra` Studio lever + `boomtown.project.json`, the asset harvest. All
gates green in scratch (stylua, selene, luau-lsp, three rojo builds byte-size equal to the committed
ones, fabric check x2, cityfabric selftest/timeline, streetplan, bake --list 0/0, gen_templates
--check 373). Lever proven inert (IsStudio first, fresh = era/rebirthCount/slots vs the template,
write before `profiles[player]`; `erasCompleted` is write-only, `highestEra` is raised lazily).

- **Recurring pattern (new): Parts wearing a baked-mesh texture lose the planar-UV recipe.** Lane
  slabs are turned Parts (`CFrame.lookAt` along the leg), so only legs heading +Z share the
  streets' plot-planar tiling (3 of 17); every other leg carries a rotated copy and each bend/tip
  disc cuts the pattern. Fix shape: lay axis-aligned legs as UN-rotated Parts (swap Size X/Z,
  offsets from the min corner). Three Roblox conventions the author could not verify (Top-face UV
  axes, the tiling's anchor corner, `OffsetStuds` sign, plus Cylinder-cap mapping) decide whether
  even the discs line up: say what a wrong one looks like instead of guessing.
- **Offsets under the proven clearance are a z-fight risk worth naming:** street rim top is 0.025
  over the plot, fill 0.07-0.075; lane rims sit at 0.005-0.01 and lane pieces 0.0025-0.005 apart.
- **A retune can make a contract mechanism vacuous.** radius 30 -> 120 (sum of pulls over 7-17
  landmarks) lets every lane lot pass threshold 1 as soon as its front develops, so each of the 8
  lanes goes 0 -> full length in ONE purchase; partial reach never happens in the greedy order.
  Probe: per-purchase `snapshot()['laneReaches']` over `greedy_history`.
- **A gate lowered to pass is a finding:** contract targets 95 lots (floor 90); the generator
  shipped 75 and cut `require.parcels` 90 -> 74, `medium` 4 -> 3, `busStops.minStreets` 3 -> 2
  with no ruling in INTERFACES. Diff the plan's `require` block every wave.
- **District props nobody governs:** no lot's nearest landmark is the clock tower or fire station,
  so `FabricCivicSmall/Medium` (5 uploaded stages) never draw (true since wave 2.2). The checker's
  unused-prop rule covers layers only. Probe: Counter of `look['prop']` at full build.
- Probes that settled things offline: a GLB triangle reader over `assets/build/stages/_props/<Era>/
  <Prop>_S<n>.glb` (bbox equals harvested extents with x/z negated, so the files are what was
  uploaded) gives the mesh height under each `fabricProps` chimney point (hollow pots read 0.2-0.4
  low at the centre: compare the top within 0.45 studs); the same reader measures arch clearance
  (NeonArch opening 4.86 over the road, posts at |x| 4.25-4.75; bus 2.15 tall at scale 0.5).
  Template check = regex over `.rbxmx` (Stage<n> count, MeshPart X/Z = -offset, R00 = R22 = -1).
  11 lane mutations of `check_document` all fired. Traffic port with the harvested bus (5.4 studs):
  5.5% any-pair vs the 4.7% cars-only baseline, so the 2.2 Major is fixed.
- Numbers: 75 lots (28 row 1, 47 on lanes), 8 lanes / 330 studs, 68 lane Parts + 68 Textures on a
  full near plot, far 0; houses 4/31/46/65/75; no level drop or prop flip over 63 replay states;
  farthest governor 55 studs by network (lot 49, lane 2).

**Wave 2.5 (2026-10-02, branch `m12-boomtown`, 120216d..ccc9dc9, SHIP TO PLAYTEST: 0 Critical /
0 Major / Minors):** the wave 2.4 lane Parts z-fought in Ben's Studio look, so lanes became baked
`LN_<k>` path pieces (RoadGraph.SetLanes, PathRenderer.Has, fabric sync moved before the Flush), with
flat single-layer Parts as the fallback; `GrantCash` baked into `boomtown.project.json`. All gates
green in scratch, three rojo builds byte-identical to the committed ones, 92 GLB sha256 = Assets.json.

- **Recurring pattern (new): a baked piece is wider and longer than the polyline the generator,
  the checker and the clearing mask measure.** Mesh half-width = 1.2 x width / 2 +- 0.35 edge noise,
  rim +0.4 +- 0.2; a free end runs 2.4 (fill) / 2.85 (rim) past its last point, a join 0.45 road
  widths past the host centreline with a +40% flare, bends are filleted. `fabric.py` still judges a
  lane as `width / 2 + rim` (1.9) on the raw polyline, and `clear.lane` 2.0 was tuned for 3-wide
  Parts. Measured: fill never on a lot (tightest 0.01), rim up to 0.28 into lot rects, rim 0.15 from
  the plot edge (LN_6), standing field quarters 0.27-0.38 over a lane's rim in mid-game. Whenever a
  Part-drawn thing becomes a baked piece, re-measure every clearance against the MESH.
- **Probe: the path GLBs are in plot coordinates.** `assets/build/paths/<Era>/{Fill,Rim}_<id>.glb`
  vertices are plot-local (x, z), UV = (x, z) / tileStuds, crowned (edges y 0, centreline 0.005);
  template X/Z = GLB bbox centre = -harvest offset, R00 = R22 = -1, Rim Y 0.0225, Fill Y 0.0725 for
  all 93 templates. A 40-line GLB reader + barycentric samples against `fabric.Site('<Era>')` polys
  (lots via `fabric.rect`, `landmark_polys`, `pad_polys`, `layer_outlines`) and point-in-triangle
  coverage between pieces answers "what lies on what" without Studio; PIL is installed (numpy,
  shapely, matplotlib are not), so a top-down PNG of rims-then-fills is cheap. The folder keeps
  retired pieces' GLBs: filter by the ids in `<Era>.json`.
- **The bake gate now needs the mesh folders**, not only `<Era>.json`: copy
  `assets/build/paths/<Era>/` and `<Era>.json` into the scratch tree or it exits 2 "missing".
- **Two same-layer polylines that meet end to end each get a plain round cap**, so the street pinches
  to nothing at the shared node (Boomtown L3_4/L4_1 at (22.0, 24.9), in the uploaded meshes since
  wave 2.2). Only the LN_6/LN_8 crossing laid on that node hides it. Print `ext`, `join_*`,
  `round_*` for every chain of `network.Bake(era, city)` when a layout's polylines change.
- **Ground heights that exist on a Boomtown plot:** plot 0, path rims 0.02-0.025, fabric yard slabs
  0.05 (garden paths 0.08), path fills 0.07-0.075, field soil 0.10, Parts streets 0.20. A new flat
  Part at 0.05 is coplanar with every yard; the lane fallback only misses them because it is narrow.
- The Parts fallback still has exactly coplanar overlaps (slab / slab / disc at each bend, tip disc
  on the last slab) and in a baked plot sits 0.02 under the street fill: unreachable with all eight
  templates present (pathSpare is 82), so Minor.
- Sync-order rule: anything that asks RoadGraph for pieces (SetLanes) only marks dirty, so it must
  run before `RoadGraph.Flush` or it waits a whole sync. FabricNetwork reads `visible` / `spurs`
  only, so the fabric sees a current network before the flush.
- A lever that resets itself once ANY player is loaded pays only that player: in a 2-player Local
  Server the second profile to load gets nothing. Check baked levers against two players.
- Replay facts (greedy): lanes appear at slot purchases 7 (LN_3), 9 (LN_4), 13 (LN_1, 2, 5),
  15 (LN_6, 8 together with L3_4 + L4_1), 16 (LN_7); a reach is never partial; triangles per near
  plot 31,520 -> 43,888.

**How to apply:** at the next era wave, re-run the scratch replay against the final layout and the
mirror (`tools/cityfabric.py`); check the claim fix and that the far prefix reaches the plot's own
wild land; run the bake gate with the recorded bake copied in; mutate the checker; run the traffic
port if vehicle classes change. See [[review-workflow]].
