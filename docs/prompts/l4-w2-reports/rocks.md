# L4 W2 track K: the forest's rocks, redone (rock builder's report)

Worktree `tycoon-p5`, branch `l4-real-forest`, 2026-10-21. **Not committed. Nothing uploaded, harvested or templated.**
Numbers come from the system `py` (3.14). Renders are Blender 5.2 EEVEE.

## Summary

- **Every rock now follows Ben's two references.**
  - The cliffs are stacked chamfered blocks, with a dark crevice behind them, light tops and darker sides.
  - The massif round the Chief's hollow and the plateau's lips are columns standing on the ground.
  - The gully walls are block cliffs.
  - Out in the forest there is a family of stones, from a monolith down to pebbles: clusters along the road, low stones
    on the banks, boulders at the cliffs' feet, the shrine's ring with one of each standing stone, and the camps'
    stone edges.
  - Trees, thicket, ground, tents, the hall, logs and stakes are untouched.
- **Collision is unchanged.** The data file's `barriers` (62), `hide`, `looks`, `effects` and `props` (23) are
  byte-equal to the approved build. Only `meshes`, the palette, `bakedPieces`, `triangles` and `planHash` differ.
- **Gates:**
  - `py tools/levels/forest.py check`: **PASS**.
  - `py tools/levels/forest.py mutants`: **23/23 caught**.
  - The build is deterministic: a second build into scratch was byte-identical (data file, 34 GLBs, palette).
  - All 34 level GLBs and all 47 kit GLBs pass `glbtools.roblox_problems`. The kit's only remark is the expected one
    about colour-only materials, which merge_stages bakes.
- **Budget:** 149,645 triangles for the whole level (was 149,761).
  - The rocks went from 20.6k to 30.0k triangles. The kit stones baked in the dress went from 2.6k to 10.4k.
  - It was paid for by:
    - a coarser canopy (10 to 14 stud cells: 19.6k to 11.1k);
    - dropping the ground under the rock columns (12.9k to 9.6k);
    - bigger blocks where only distant players see them;
    - caps only round the rim of a wide top;
    - fewer firs on the ridge and round the clearing.
  - The worst spot on the route: 96,652 triangles within 250 studs (was 90,928).
- **Plan hash `5a954ad6ec3b9853` → `4014c1c8ee959871`.** The hash covers every kit piece's GLB bytes and the art
  numbers by design, so a new rock language is a new bake. Its scope was not widened. Nothing is uploaded yet, so this
  costs nothing.
- **Upload: 34 baked meshes (was 38).**

## Pictures (assets/testfit/out/Levels/ForestRoad/)

| File | What it shows |
|---|---|
| `_rocks_sheet.png` | Ben's first reference laid out with the kit: a row of standing stones by size, a row of low chunky stones (and the camp edge), a row of pebbles. Behind them, three masses built by the level's own generator like his second reference: a cliff wall, an outcrop and a tower (the lookout's style). Each label gives the triangle count. |
| `campA_B_rocks.png`, `caveMouth_B_rocks.png`, `gatehouse_B_rocks.png`, `clearing_B_rocks.png`, `lookoutLedge_B_rocks.png`, `pond_B_rocks.png`, `shrine_B_rocks.png`, `plan_top_rocks.png` | The views where rock shows, in mood B (the approved mood), beside the old files. |
| `campA_A_rocks.png`, `gatehouse_A_rocks.png`, `clearing_A_rocks.png` | The same three views in mood A, for a like-for-like comparison. |
| `_L4_rocks_before_after.png` | Old A render on the left, new A render on the right, for camp A, the gatehouse and the clearing. |

## How each kind of rock is built

**The palette (`forest_palette.ROCK`).** The four rock swatches are now one warm pale grey family:

| Swatch | sRGB | Used for |
|---|---|---|
| ROCK_LIGHT | 168, 160, 144 | tops |
| ROCK | 130, 124, 113 | faces |
| ROCK_DARK | 95, 91, 85 | sides in shade and undersides |
| ROCK_SHADE (new) | 62, 60, 56 | crevices |

- Each step is at least 1.57 in luminance.
- LICHEN stays.
- There are now 56 swatches, which fills the 8 x 7 grid, so `palette.png` stays 128 x 112.
- `forest_kit.rock_paint` gives every face its swatch by how it faces.

**Kit builders (`tools/assets/forest_kit.py`):**
- `stone`: an irregular prism with a kink or a shoulder and a bevelled, obliquely cut top.
- `pebble`.
- `block_poly`: a chamfered block on any convex outline, with sliding fronts and per-corner lifts. Its chamfer can be
  shallower than 45 degrees (the references' worn edges). It is open at the back.
- `loft`, `inset_poly`, `poly_ccw`, `poly_span`.

**Kit pieces (role `rock`, cap 150 triangles), triangles each:**

| Piece | Triangles |
|---|---|
| StoneMonolith (9 tall) | 40 |
| StoneTall | 40 |
| StandingStone | 33 |
| StoneSlim | 33 |
| StoneLean | 40 |
| StoneBroad | 47 |
| RockB (chunky, with a companion stone and a pebble) | 86 |
| RockA | 66 |
| RockFlat | 40 |
| RockSmall | 33 |
| Pebbles (5) | 65 |

- **EdgeRocks** (edge role, 3.46 tall): 158 triangles (was 100).
- **Campfire**: its ring is now 9 pebbles. The piece is 213 triangles (was 276). It is a prop, so its merge and upload
  use the new GLB.

**The level (`tools/levels/forest.py`). Cliffs on every exposed face (`rock_faces`, `block_face`, `joint_grid`):**
- Each face carries one dark backing quad, so no crevice shows the hidden wall or the sky.
- Columns vary in width and their joints lean. Each column is stacked to its own heights with tilted joints.
- A tall face is cut into tiers per stretch, with slanted seams, so no joint or course runs across a wall.
- A free top's columns stand over the edge, rising and falling in groups.
- The styles (`ART.cliff`):
  - `thin`: faces over walking ground. Blocks stand at most 0.12 out of the wall (`THIN_OUT`) and sit back up to 1.2
    for relief. They bulge above a double jump's reach, where they take `near` sizes.
  - `tunnel`, `step`.
  - `near` and `far`: chosen by how near a walker stands in front, counting a tall wall in between as a screen. Their
    foot bulges like a talus, but always stops 1.5 short of any walkable rectangle or drop (`room_ahead`).
  - `pillar`: the lookout. Its top 4 studs stay flush, for an honest double-jump edge.
  - `gully`.
- Tops get chamfered caps round their rim, plus a flat mossy floor in a wide top's middle that nobody sees.

**Columns on the ground:**
- The massif (`massif_columns`) is stacked with ledges. The heightfield cells under a column are dropped
  (`Ground.mask_quads`).
- The plateau's lips (`lip_columns`) are also masked.
- The gully's walls are block cliffs (`gully_faces`).
- Steep ground that still shows is shaded dark rock. The old three-tone noise is gone.

**Stones placed (`scatter_stones`, `foot_boulders`):**
- Clusters stand about every 38 studs along the walled road, 5 to 9 studs out. Each is an anchor stone, 0 to 1
  companions, and sometimes pebbles.
- Bank stones line the creek and the pond. Boulders sit at the foot of the cliffs nobody stands at.
- The gully's rim stones and the shrine's ring use the family.
- The stones go down before the trees. Trees keep off each stone's footprint plus 0.6, so they stand beside stones,
  never in them.

**Rock triangles by part (30.0k in all):**

| Part | Triangles |
|---|---|
| Thin faces | 6,418 |
| Near faces | 4,626 |
| Far faces | 2,022 |
| Tunnel | 1,254 |
| Lookout | 912 |
| Steps | 314 |
| Caps | 2,744 |
| Massif | 5,058 |
| Lips | 1,458 |
| Gully | 2,306 |
| Ridge firs | 1,204 |
| Crown firs | 1,680 |

## Counts, before and after

| Group | Before | After |
|---|---|---|
| dress (baked placements) | 78,718 | 81,456 |
| rock | 20,642 | 29,996 |
| canopy | 19,556 | 11,096 |
| ground | 12,880 | 9,636 |
| skin | 8,112 | 8,112 |
| camp | 3,980 | 3,980 |
| backdrop | 768 | 768 |
| props | 5,105 | 4,601 |
| **whole level** | **149,761** | **149,645** |

Views (`levelrender.py --counts`), triangles in view / within 250 studs:

| View | Before | After |
|---|---|---|
| trailhead | 149,761 / 71,465 | 149,645 / 76,200 |
| lookoutLedge | 149,761 / 71,741 | 149,645 / 76,413 |
| campA | 136,220 / 75,358 | 135,213 / 79,978 |
| mainCamp | 99,686 / 63,668 | 96,220 / 61,362 |
| caveMouth | 89,130 / 53,570 | 96,643 / 59,455 |
| pond | 55,089 / 54,738 | 61,634 / 61,283 |
| shrine | 29,063 / 28,712 | 28,283 / 27,932 |
| gap | 149,761 / 71,949 | 149,645 / 76,621 |
| gatehouse | 50,926 / 50,926 | 50,046 / 50,046 |
| clearing | 56,497 / 56,080 | 55,590 / 55,173 |

**The worst spot on the route (most within 250):**
- Before: 90,928 within, 111,682 in view, at feet (-12, 8, -44) facing 135 degrees. That spot now counts 96,455 within
  and 114,366 in view.
- After: 96,652 within and in view, at feet (-185, 8, -44) facing 90 degrees (camp A's east gate, looking along the
  plateau).

**Meshes (34, every one under the limits).** The largest is Dress_4 with 14,986 triangles and 1.6 MB (was 14,201).
The rock meshes are 3.2k to 7.4k each. The widest is still Hills_1 at 1,496 studs, as before; no rock mesh is over
257 studs. All 34 GLBs total 15.7 MB.

## The gate: check and mutants

New rules in `forestcheck.py`. Both are in its docstring and in the README.
- **4b, rock in walking space.** Over any walkable ground, from its floor up to REACH_ABOVE, every vertex of the rock
  meshes must lie within 0.3 of a collision solid. This makes the thin-face promise checkable everywhere. Before, only
  the plateau cells were checked.
  - On its first run it caught three real faults, all fixed:
    1. A sheared block at the cave mouth over Road3.
    2. A gatehouse block over RoadBC6.
    3. An old crown fir's branches over the gatehouse walk. This one dates from W1. Crown firs now keep their reach
       off walkable ground.
- **4c, stones off the paths and water.** No kit stone stands on walkable ground or water; the island shrine's ring is
  the one exception. On its first run it caught bank stones whose footprints reached the pond. Every stone is now
  placed only if its footprint stays clear.

**`py tools/levels/forest.py mutants`** (new; it lives in `forestcheck.mutants`) breaks each rule once. All 23 are
caught:
- **The 15 from W1** (they were a scratch script before; now committed):
  - collidable prop;
  - barrier not character-only;
  - barrier top within reach;
  - barrier into walkable ground;
  - barrier under a stud thick;
  - tall piece in a region cell;
  - spawn tent past its marker;
  - baked mesh in a region cell;
  - clearing piece over the wall;
  - clearing mesh over the wall;
  - coplanar overlap;
  - stale plan hash;
  - hand-edited data;
  - edge piece over 4 studs;
  - mesh over 20k.
- **8 new:**
  - a monolith in a region cell;
  - a thin block standing out of BendWall;
  - a column on the gatehouse walk;
  - a block hanging into the tunnel;
  - the generator's own BendWall face with THIN_OUT raised;
  - a stone on the road;
  - a stone in the pond;
  - a stone over the rock budget.

Other rules, still holding:
- Nothing over 4 studs inside a plateau cell (rule 4).
- Nothing of camp C over its wall inside its floor (rule 5).
  - The inner faces' tops are capped at the wall.
  - The fence-top caps keep 0.45 off the floor.
  - The massif columns stand outside the fenced rectangle.
- No coplanar faces between looks (rule 6).

## Honest shortfalls

1. **Walls players walk beside cannot stand out.** These are the clearing's walls, the gatehouse canyon and BendWall.
   Collision allows them no relief outward, so they read as stacked-block walls with up to 1.3 studs of recess. The
   reference's deep boulder masses are only possible where nobody stands: the ridge's outer faces, the massif, the
   lookout, and every face above a double jump's reach. On the clearing's back wall, a tier seam can still read as a
   course.
2. **The ridge is still a long flat-topped box from afar** (camp A, the Main Camp). Its skyline is broken by groups of
   columns, caps and firs, but its mass stays a straight wall.
3. **Some massif columns show large plain faces** from the gatehouse approach. They are stacked, with ledges, but a
   column on the steepest part is tall.
4. **The canopy is coarser** (14-stud cells), which is the trade for the budget. From the lookout the far forest's top
   is a little blockier. The dark underside slab beside the creek in the pond view is the canopy's own look from W1,
   slightly larger now.
5. **Offline only.** Roblox lighting, the real Atmosphere and the automatic mesh LODs on these meshes were not seen.
   The pale rock under mood B's haze needs his Studio look.

## For the pipeline and the lead

**What the runbook (`docs/prompts/l4-w2-asset-run.md`) must change:**
- **Plan hash:** `4014c1c8ee959871`.
- **Step 1:** `build` now prints `wrote 34 meshes + palette`.
- **Step 3:** the forest-kit palette now holds **56** swatches. The cache `assets/build/palettes/forest-kit.*` from
  17:20 is stale, and step 3 already deletes it. The Campfire prop changed (its stone ring).
- **Step 4:** the dry run now reads `39 upload(s) pending (5 image(s), 34 mesh(es))`. Dress_4 is still the trial mesh
  with the most triangles (14,986, 1.6 MB), and Hills_1 is still the widest box.
- **Totals:** the forest is **43 uploads** (was 47). The run is **78 uploads and one paste of 78 records**: 39 prop,
  5 levelTexture, 34 levelMesh.

**The mountain track (M) is coming.** `docs/prompts/l4-w2-reports/mountain.md` plans ledge pillars up to 200 studs
tall. My generator will dress them on its own with the `pillar` style, which keeps an honest top edge for the double
jumps. But that style is dense (about 41 triangles per 100 studs squared). A 200-stud mountain would add roughly 20k
or more. Before that bake, a tall pillar's faces below their top band should take the `near`/`far` sizes. That is one
`sz` choice in `block_face`, the way thin faces already switch above reach. The plan hash moves again with that layout.

**Run order after a kit or palette change** (as before):
1. `py tools/assets/forest_kit.py`
2. `py tools/levels/forest.py build`
3. `check` and `mutants`
4. The renders.

New in `levelrender.py`: `--rocks` and `--suffix`.

## Files changed (all LF)

- `tools/assets/forest_palette.py`
- `tools/assets/forest_kit.py`
- `tools/levels/forest.py`
- `tools/levels/forestcheck.py`
- `tools/levels/README.md`
- `tools/testfit/levelrender.py`
- `src/shared/Config/LevelDress/ForestRoad.json` (generated)
- the renders listed above

`levelmesh.py` and `forest_textures.py` are unchanged. Generated and gitignored: the kit GLBs and
`assets/build/levels/ForestRoad/` (34 GLBs, palette, upload record). The before/after sheet came from a scratch Pillow
script (`<session scratchpad>/rocks/before_after.py`); the old A renders are copied in `rocks/before/`.
