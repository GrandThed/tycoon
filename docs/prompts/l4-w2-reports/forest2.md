# L4 W2 track F2: the mountain dressed and the walls less regular (forest builder's report)

Worktree `tycoon-p5`, branch `l4-real-forest`, 2026-10-21. **Not committed. Nothing uploaded, harvested or templated.**
Numbers come from the system `py` (3.14) unless a line says 3.12. Renders are Blender 5.2 EEVEE.

## Summary

- **The walls are less regular, as Ben chose.** No grid, no course, no long straight joint. Blocks are bigger and of
  uneven sizes, with broken layers and small rubble at the foot under big slabs. Every block's front is faceted.
  - The skin's depth is unchanged: at most `THIN_OUT` 0.12 out and 1.5 back, so the collision promise holds.
  - Boulder piles stand beside the gates where nobody walks.
- **The mountain is dressed in his clustered-block style** (the tower of his second reference).
  - Where a body stands beside a face, the face is thin. Above that reach it carries big bulging blocks, and the blocks
    high on its outer corners wrap round them.
  - The hop faces carry finer blocks.
  - The ledge tops and the summit are paved with light, flat cap stones ("stand here").
  - The summit has a ring of standing stones round the chest, open toward the last hop's landing.
  - The yard has forest floor, scree at the mountain's foot and two firs in its far corners, with boulders and forest
    beyond its walls.
- **The climb's rules are in.**
  - The yard, trail and path walls stand to y 280, except at the mouth.
  - The summit opens no designed drop. Before F2 it opened a 378-stud hole through the forest.
  - There is no tree on a ledge, nothing on a hop's take-off or landing, and a summit-ring rule.
- **Budget:** 163,647 triangles (212,093 at the start of this pass, gate 165,000). The mountain's rock is 7.6k (was
  19.9k).
- **Gates:** every one PASS (verdict lines below). The build is deterministic: two builds into scratch were
  byte-identical and equal to the repo's data file and GLBs.
- **Plan hash `4014c1c8ee959871` → `23851a6f417491c1`.** This is a new layout and new art numbers, and nothing is
  uploaded yet.
- **Upload: 37 baked meshes, 5 images, 4 props.** It was 34 + 5 + 4.

## Pictures (assets/testfit/out/Levels/ForestRoad/)

| File | What |
|---|---|
| `mountain_far_B.png` | The mountain from the trailhead, over the trees (mood B) |
| `mountain_yard_B.png` | The climb from the yard: ledge 7's mass on the left, ledges 1 and 2 stepping up ahead |
| `mountain_ledge_B.png` | On ledge 4, the hop face onto ledge 5 ahead (finer blocks), the core's face on the left, the cap stones underfoot |
| `mountain_summit_B.png` | The summit's flagstones, the chest (stand-in box), the ring of standing stones, the forest below in the haze |
| `plan_top_F2.png` | The plan with the mountain at the top left |
| `_L4_walls_before_after.png` | Four rows: camp A, the gatehouse from the road, **inside the gatehouse (new view)**, and the clearing. Left: the rocks pass. Right: F2. Mood A, as the old sheet. |
| `*_F2.png` | Every standard view again (`campA`, `gatehouse`, `gatehouseWalk`, `clearing` in A and B; `trailhead`, `mainCamp` in A and B; `lookoutLedge`, `caveMouth`, `pond`, `shrine`, `gap` in A) |

**Where the sheet's left column comes from:**
- Rows 1, 2 and 4 use the old sheet's right-column renders (`*_A_rocks.png`).
- Row 3 is new. The old gatehouse view barely shows the canyon walls, so I added a view inside the walk (`gatehouseWalk`
  in `levelrender.VIEWS`).
- Its left picture, `gatehouseWalk_A_rocks.png`, is the generator as it stood before F2, built into scratch on the
  mountain layout. Its wall code is the approved rocks pass's.

## What changed

### The walls (`block_face`, `pack_cells`, `split_cell`, `thin_front`; `ART.cliff`)

The face is cut in two steps, which replace the old columns, tiers and seams (`joint_grid` now cuts only flat tops and the
massif's plan):
1. **Masses.** Seeds are thrown like a Poisson disc whose radius follows the style's size. Each seed gets its own spread
   (0.5 to 1.7 times), so big masses sit beside small ones. The masses are the seeds' power diagram, stretched taller than
   wide, so mass outlines run every way.
2. **Blocks.** `split_cell` stacks each mass into blocks: near-level and near-upright joints, each tilted its own way and
   placed off-centre. Every joint ends on another (a T), so no course or joint runs across a face.

Other changes:
- A block's relief and tone follow its mass, so a mass reads as one rock split by cracks.
- **Bigger blocks:**

  | Style | Height (was) | Width (was) |
  |---|---|---|
  | thin | 14-32 (10-20) | 8-17 (5-12) |
  | near | 16-36 | 9-19 |
  | far | 24-48 | 13-26 |

- **The foot.** A thin face's blocks are 0.55 the size at its foot, growing to full size over 24 studs: rubble at the foot,
  slabs above, as in the reference cliffs.
- **Faceted fronts.** A thin block's highest corner goes from deep up to the face. Its front leans back from there by up to
  the style's lift, each corner its own share, so even the prominent blocks are no longer flat tiles.
- **No seams between near and far.** A near/far face is now one packing whose sizes blend along it by how near a walker
  stands (`face_reach`). It was stretches with a seam up the face between them.
- **Boulder piles** (`boulder_piles`, `ART.piles`): a big stone, a broad one and pebbles, every footprint off walkable
  ground.
  - Beside each open camp's gates, outside the fence line and the road: camp A's two gates and camp B's two.
  - At the corners where a tall wall's end stands beside a road it is seen from: the gatehouse's mouth (both sides), the
    clearing's east gate, and the lookout's foot.
- **The clearing's corners are walkable floor** (rule 4c), so they got no pile.

### The mountain (`mountain_faces`, `mountain_caps`, `mountain_scree`, `dress_mountain`)

- **One face per plane.** Coplanar sides of different pillars are packed as one face. A block crossing a step in the
  skyline is cut only there, at the real corner.
- **Thin where a body stands, bulging above.** Thin within REACH_ABOVE of the floor in front (the yard 0, or the ledge
  below). Above it, `mountUp` blocks bulge up to 7 studs.
- **Outer corners.** Blocks high on the tower's outer corners wrap round them (`wrap` 4). No front slides past a side's end
  where the next pillar stands. A review of my own first build found one doing that, 0.5 studs over ledge 3; it is fixed.
- **Finer blocks where the player looks.** `mount.fine` (16 studs, 0.3 the size) under every ledge's top, and over a ledge
  in front, so the hop faces read as rock.
- **Honest top edges.** Every ledge's top edge is flush in its last 4 studs, and the bulge fades in below.
- **Cap stones.** Flat flagstones at the top lift over a dark grout, light, with a few lichen ones. They overhang 0.15 only
  where the side drops.
- **Scree.** 24 flat stones on the yard's floor at the foot, nothing over 0.2.
- **The summit ring.**
  - Five standing stones, 2.8-3.7 tall, at radius 10.5 from the chest.
  - The ring is open 100 degrees toward the last hop's landing.
  - The stones are tagged `summit`.
- **The yard's forest.** It is seen from inside the yard and from above, never from a road, so it is lighter:
  - near band at 45%;
  - no middle band;
  - thicket band 2.4 times sparser;
  - canopy from 11 studs.
- **Two firs** stand in the yard's far corners, off every hop line.
- **The walls:** `barriers` raises every stretch along the climb's yard, trail and path to CLIMBS `wallTop` 280. The mouth
  at x -482 stays open by construction.
- **The drop:** `find_drops` skips the climb's secret, and caps any double-jump drop at `DROP_MAX` 50 (the lookout's is
  18).
- **Excluded from the generic code:** the mountain is out of `rock_faces`, `step_faces`, the pillar ribbon skin and
  `dress_pillars` (no `FirHeroB` on its corners).

### Budget levers (all in `ART`)

- The canopy goes to 15-stud cells (was 14), and leaves out the underside of every cell 3 or more cells in from its edge.
  No walker gets under it and the tops are opaque; no hole was visible in any view.
- Ridge and crown firs are 15 studs apart (were 12).
- Bigger blocks for the tunnel, gully and lookout.
- The yard's lighter forest (above).

### The gate (`forestcheck.py`)

- **Rule 3 adds:** no designed drop runs longer than DROP_MAX.
- **New rule 8 (the climb):**
  - every wall on the climb's outline stands to wallTop;
  - no tree on a ledge or the summit;
  - nothing placed on a hop's take-off or landing (6 studs either side of the face it rises over);
  - the summit ring: each stone under 4 studs, on the summit, and outside the chest's trigger (`secretReach` 2.5 plus a 1
    margin).
- **Rule 4c's exception** now covers the summit's ring, as it does the shrine's. **This is the one rule I widened.** The
  brief asked for a ring of standing stones round the chest, and the summit is walkable ground. Rule 8 holds the ring.
- **Mutants: 29, all caught.** Six are new:
  - a 378-stud drop through the forest;
  - the mountain's thin face pushed out over the yard;
  - a climb wall lowered under 280;
  - a fir on a hop's take-off;
  - a summit stone over 4 studs;
  - a summit stone in the chest's trigger.

### Other files

- `levelrender.py`:
  - five views: `mountain_far`, `mountain_yard`, `mountain_ledge`, `mountain_summit` (mood B) and `gatehouseWalk`;
  - a `zoom` per view (the game's camera pulls in off the ground when looking steeply up).
- `README.md`: the rules, the rocks section and a mountain section.
- The kit and palette are unchanged: `forest_kit.py`, `forest_palette.py` and `levelmesh.py` are untouched, so no kit
  regeneration is needed and there are still 56 swatches.

## Triangles

| | Start of F2 (mountain in today's rules) | After F2 |
|---|---|---|
| Whole level | 212,093 | **163,647** (gate 165,000) |
| Mountain's rock (faces, caps, scree) | 19,923 | 7,572 (6,421 + 794 + 357) |
| Everything west of x -480 (mountain, yard, trail, path, their forest) | 50,141 | 24,640 |

By group after F2:

| Group | Triangles |
|---|---|
| dress | 95,243 |
| rock | 29,679 |
| canopy | 10,604 |
| ground | 9,844 |
| skin | 8,928 |
| camp | 3,980 |
| backdrop | 768 |
| props | 4,601 |

Rock by part:

| Part | Triangles |
|---|---|
| thin | 3,771 |
| near | 3,243 |
| caps | 1,682 |
| crown firs | 1,600 |
| tunnel | 1,424 |
| gully | 1,005 |
| ridge firs | 972 |
| far | 954 |
| lookout | 588 |
| steps | 388 |
| massif and lips | about 6.5k (unchanged) |

Views (`levelrender.py --counts`), in view / within 250:

| View | Start of F2 | After F2 |
|---|---|---|
| trailhead | 180,350 / 105,340 | 150,029 / 77,898 |
| campA | 145,523 / 89,599 | 129,844 / 77,473 |
| gatehouse | 49,145 / 49,145 | 44,430 / 44,430 |
| clearing | 53,367 / 53,134 | 49,429 / 49,196 |
| mountain_far | 90,717 / 90,717 | 54,250 / 54,250 |
| **mountain_yard (the yard looking up)** | 212,093 / 92,989 | 163,647 / 54,590 |
| mountain_ledge | 49,877 / 49,877 | 18,881 / 18,881 |
| mountain_summit | 210,558 / 89,182 | 163,647 / 50,684 |

**Worst spots:**
- **The old worst spot** (feet (-185, 8, -44) facing 90, camp A's east gate): 96,652 after the rocks pass, 104,192 at the
  start of F2, **98,469 now**. It is again the worst spot on the route.
- **The start of F2's worst spot** (feet (-399, 0, 0) facing 270, the bridge looking at the mountain): 130,746 within
  250, **86,714 now**.

## Meshes and limits

**37 meshes:**

| Group | Meshes |
|---|---|
| dress | 11 |
| rock | 6 |
| skin | 5 |
| ground | 4 |
| canopy | 4 |
| backdrop | 4 |
| camp | 3 |

- The mesh triangles total 159,046. The GLBs total 17.2 MB (was 15.7).
- **Most triangles:** Dress_5, with 15,854 triangles and 1.71 MB. That is under the Valley's proven 16,037.
- **Widest:** Hills_2, at 1,320.6 studs. The hills are now cut in four because the domain grew west to x -752. No mesh is
  past the Valley's proven 1,444 any more; Hills_1 at 1,496 is gone.
- All 37 GLBs pass `glbtools.roblox_problems` with no problem.
- **Props:** 23 placed, of 4 pieces (Bramble, Campfire, ChiefTent, SpawnTent). They are unchanged since the rocks pass.
- **Barriers:** 70.

## Gate verdict lines (final build, plan hash 23851a6f417491c1)

| Gate | Verdict |
|---|---|
| `py tools/levels/forest.py check` | `[forest] check: PASS` |
| `py tools/levels/forest.py mutants` | `[forest] mutants: 29/29 caught` |
| `py -3.12 tools/check_levels.py` | `CHECK: PASS` |
| `py -3.12 tools/check_parkour.py` | `PARKOUR: PASS` |
| Determinism | two builds into scratch byte-identical (41 files), equal to the repo's data file and GLBs |
| `glbtools.roblox_problems` | 37 of 37 clean |

## What the runbook (`docs/prompts/l4-w2-asset-run.md`) must change

- **Plan hash:** `23851a6f417491c1`. It was `5a954ad6ec3b9853` in the runbook, and `4014c1c8ee959871` after the rocks.
- **Step 1:** `build` prints `wrote 37 meshes + palette`.
- **Step 3:** the forest-kit palette still holds **56** swatches, and the props are unchanged since the rocks pass.
- **Step 4:**
  - The dry run reads `42 upload(s) pending (5 image(s), 37 mesh(es))`.
  - **The trial meshes change:**
    - `--only Dress_5`: the most triangles, 15,854, 1.71 MB.
    - `--only Hills_2`: the widest box, 1,320.6 studs.
  - The real run reads `uploaded 40/40` after the trial's 2.
- **Totals:** the forest is **46** uploads (37 meshes, 5 images, 4 props), and the run is **81 uploads**.
- **Step 6:** `harvest.luau` holds **81** records: 39 `prop`, 5 `levelTexture`, 37 `levelMesh`.
- **Step 7:** `[HARVEST-DONE] 81 loaded, 0 failed`.
- **Step 8:** `merged 5 level image(s) and 37 level mesh(es)`.
- **Step 10:**
  - `37 level template(s)`.
  - `CHECK: PASS -- 617 template(s) up to date`.
  - The manifest line reads `ForestRoad | 23851a6f417491c1 | 37 | 159046 | 5/5 | 5/5 | 37/37 | 37/37 | 37/37 | in game`.
    The 159046 is the meshes' triangles; with the props the level is 163,647.
- **Step 11:** "a folder of 38 models" → 37.

## Honest shortfalls

1. **The walls still have only about 1.6 studs of relief where players walk**, as Ben chose ("the same depth").
   - They read as big layered slabs with rubble at the foot, no longer as a block wall.
   - They are not the reference's deep, overlapping masses.
   - Seen edge-on (inside the gatehouse canyon) the near walls are still large plain planes.
   - The massif columns' plain faces at the gatehouse approach (a rocks-pass shortfall) were not reworked.
2. **The mountain's lowest 36 studs are thin.** They face the yard, which is walking space all round, so they read as tall
   basalt-like slabs. The chunky bulging blocks begin above a double jump's reach.
3. **The silhouette is still a stepped tower with a square top**, seen from the trailhead. The tops must stay flat and
   honest; the corners' wrapped blocks and bulges break its sides, not its top.
4. **There are no boulders inside the yard.** The whole yard is walkable, and rule 4c keeps every kit stone off walkable
   ground.
   - The yard has flat scree (baked, under 0.2) and two firs in its far corners.
   - Its boulders are the stone clusters just beyond its invisible wall.
   - This differs from the brief's "boulders"; moving them inside would need the lead to widen 4c again.
5. **The summit-ring exception to rule 4c is mine** (above). The ring is small next to a 200-stud tower: it reads on the
   summit, not from the road.
6. **The canopy is a little coarser** (15-stud cells). Its deep undersides are left out; that was checked in nine views,
   but not from every low camera beside the plateau lip.
7. **The lookout ledge now uses the new packing too**, with smaller masses. It looks more fractured than the approved
   tower; Ben has not seen it.
8. **Offline only.** Roblox lighting, the real Atmosphere and the automatic LODs were not seen.

## Files changed (all LF)

- `tools/levels/forest.py`
- `tools/levels/forestcheck.py`
- `tools/levels/README.md`
- `tools/testfit/levelrender.py`
- `src/shared/Config/LevelDress/ForestRoad.json` (generated)
- the renders above, in the gitignored `assets/testfit/out/Levels/ForestRoad/`

Generated and gitignored: `assets/build/levels/ForestRoad/` (37 GLBs, the palette, `bake.json`) and the upload record
`assets/build/levels/ForestRoad.json`.

Scratch, in the session scratchpad (`f2/`):
- the sheet script `walls_sheet.py`;
- the before-build and its renderer `render_before.py`;
- the measurement scripts.
