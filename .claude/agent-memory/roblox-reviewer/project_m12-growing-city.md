---
name: m12-growing-city-review
description: M12 "growing city" reviews (Village waves 1-1c, Boomtown waves 2.0-2.2) — recurring patterns (claim replays as a purchase, plot-frame offsets in rotated layouts, mixed-length lane hold, far wild prefix), the scratch probes that settle them without Studio, and the numbers found
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

**How to apply:** at the next era wave, re-run the scratch replay against the final layout and the
mirror (`tools/cityfabric.py`); check the claim fix and that the far prefix reaches the plot's own
wild land; run the bake gate with the recorded bake copied in; mutate the checker; run the traffic
port if vehicle classes change. See [[review-workflow]].
