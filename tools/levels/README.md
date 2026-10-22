# tools/levels: dressing a level (L4, the Forest Road)

One deterministic generator turns a level's layout into its real scenery, on paper: baked meshes in
the level frame, a few props the client places, the invisible tree-line walls, and one data file the
game reads. Nothing here changes collision: every collidable piece is a layout block or a new
character-only wall this generator writes.

## Commands

All with the system `py` (3.14, no shebang needed); Blender only for the textures and the renders.

```
py tools/assets/forest_kit.py                   # the kit: 46 pieces + a palette card + pieces.json into assets/kenney3d/forest-kit/
"/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/levels/forest_textures.py
                                                # 4 ground textures into assets/build/levels/ForestRoad/textures/
py tools/levels/forest.py build                 # meshes + palette into assets/build/levels/ForestRoad/,
                                                # data into src/shared/Config/LevelDress/ForestRoad.json, the upload
                                                # record assets/build/levels/ForestRoad.json, then the gate
py tools/levels/forest.py check                 # the QA gate (writes nothing): PASS or one line per failure
py tools/levels/forest.py mutants               # breaks each rule of the gate once: every line must read CAUGHT
py tools/levels/forest.py stats                 # triangles by group and by piece
py tools/testfit/levelrender.py                 # every view (both moods where asked) into assets/testfit/out/Levels/ForestRoad/
py tools/testfit/levelrender.py --views top,campA --moods A
py tools/testfit/levelrender.py --sheet         # the kit's contact sheet
py tools/testfit/levelrender.py --rocks         # the stone family and three cliff masses (_rocks_sheet.png)
py tools/testfit/levelrender.py --views top,campA --moods B --suffix _rocks   # beside the old pictures
py tools/testfit/levelrender.py --views mountain_far,mountain_yard,mountain_ledge,mountain_summit   # the climb (mood B)
py tools/testfit/levelrender.py --barriers      # the plan with the invisible walls in red
py tools/testfit/levelrender.py --counts        # triangles drawn from each view and the worst spot on the route
```

Order after a kit change: kit, then `forest.py build`, then renders. After a palette change, delete
`assets/build/palettes/forest-kit.*` before any `merge_stages` run (the palette cache trap).
A build is about 12 s; a render 20-60 s a view; the full set about 8 minutes.

## Files

| File | What |
|---|---|
| `forest.py` | the Forest Road's dresser: layout model, walls, heightfield ground, skins, rock, camps, trees, canopy, backdrop, data |
| `forestcheck.py` | the gate's rules (see its docstring); `forest.py check` runs it |
| `levelmesh.py` | baked-mesh writer (the Valley's GLB shape), level palette, rectangle maths, noise |
| `forest_textures.py` | road, road rim, camp earth, forest floor: 1024 px, opaque, two-way seamless (Blender's numpy) |
| `src/shared/Config/LevelDress/ForestRoad.json` | the generated data file the game reads (never hand-edit; `check` compares it with a fresh build) |
| `../assets/forest_palette.py` | every forest colour (reuses the weapon kit's `FOREST` and `FIRE`) |
| `../assets/forest_kit.py` | the generated pieces, pure Python; the generator bakes the same triangles it exports |
| `../testfit/levelrender.py` | the renders, a mirror of what the data file places |

## Rules the generator keeps (and `check` proves)

- Dressing never collides. The only new collidables are the `TreeLine<n>` walls: character-only
  (`ArenaBarrier`), from killY - 2 to 80 over the highest walkable top within 20 studs (along a
  climb's yard, trail and path: to the climb's `wallTop`, 280 for the mountain), 1 to 8 studs
  deep, outside the walkable whole (walkable blocks, open camps' floors with their fence strip,
  water, the designed drops), cut where a tall layout wall already closes the edge.
- Designed drops are found from the layout: a route leg marked `via: gap`, and the void between
  a double-jump secret's ledge and the walkable block across from it (at most `DROP_MAX`, 50;
  a climb's summit has none: its falls land on its ledges or the walled yard). Water and steps
  between walkable blocks stay open by construction.
- Inside a region cell, nothing stands more than 4 studs over the floor up to 36 studs (a double
  jump and a head), except a spawn tent inside its own layout marker. Trees keep their reach off
  every walkable block; the thicket band at the edge stays under 3.9.
- Camp edges (open camps) are kit edge pieces at most 4.0 tall, inner face on the floor's edge,
  reaching outward; gaps at the gates; totem posts outside the gates.
- A walled camp: nothing over its wall's top inside its floor; placed pieces under the top less
  `sightMargin`.
- Rock never reaches into walking space (`forestcheck.walking_space_rule`): over walkable ground,
  from its floor up to 36 studs, every rock vertex lies within 0.3 of a collision solid. A face
  that looks onto walkers ("thin") keeps its blocks at most `THIN_OUT` (0.12) out of the wall; they
  sit back instead for relief, as deep as the wall's thickness allows (`ART.cliff.thinBack` 1.5).
  No kit stone stands on walkable ground or water, the island shrine's ring and the summit's aside.
- The climb (`forestcheck` rule 8, `check_parkour.CLIMBS`): every wall along its yard, trail and
  path stands to `wallTop`; no tree on a ledge or the summit; nothing placed on a hop's take-off
  or landing (6 studs either side of the face it rises over); the summit's ring of standing
  stones under 4 studs, on the summit, and outside the chest's trigger (`secretReach` + 1).
- No two looks share a face: lifts over a collision top are floor 0.00, rims 0.03, camp 0.06,
  cave floors 0.075, road 0.09, a pillar's top 0.06; the shore line 0.06 over the water's top;
  rock flush with a visible Part (a bramble) is cut back from it; a kit piece's own floor 0.14.
- Meshes: at most 20,000 triangles, sides at most 1,500 studs, names `[A-Za-z0-9_]` up to 24,
  slivers under 1,500 triangles folded into a neighbour; budget 150,000 (gate at +10%). The
  canopy leaves out the underside of every cell `blanket.deep` cells in from its edge (nobody
  gets under it, the tops above are opaque).

## The rocks (Ben's references, 2026-10-21)

Every stone follows `assets/research/2026-10-21-l4/ref_rocks_*.png`: sculpted chamfered prisms with a
few big facets, light tops, darker sides (`forest_kit.rock_paint` picks the swatch by facing).

- **Cliffs** (`rock_faces`, `block_face`): every exposed face of a tall solid is a cliff of
  clustered chamfered blocks (`forest_kit.block_poly`) over one dark backing quad (no crevice ever
  shows the hidden wall or the sky). Ben's second look (same day) asked for **less regular walls**
  (bigger uneven blocks, broken layers, fewer straight joints), so `pack_cells` cuts a face in two
  steps: masses (a Poisson disc of seeds whose size follows the style, spread big and small,
  their power diagram, so mass outlines run every way), then each mass stacked into blocks by
  `split_cell` (near-level and near-upright joints, tilted, off-centre, each ending on another:
  no course or joint runs across a face). A block's relief and tone follow its mass, so a mass
  reads as one rock split by cracks. Sizes blend along a face from `near` to `far` by how near a
  walker stands (`face_reach`), never in stretches with a seam between. Styles in `ART.cliff`:
  `thin` (over walkers: at most `THIN_OUT` out, the relief is in how deep a block sits and its
  faceted front; above reach the `near` blocks bulge), `tunnel`, `step`, `near`, `far`, `pillar`
  (the lookout), `gully`, `mount` and `mountUp` (the mountain). Tops get caps round their rim and
  a flat mossy floor in a wide top's middle (`block_caps`).
- **Boulder piles** (`boulder_piles`, `ART.piles`): a heap (a big stone, a broad one, pebbles)
  beside each open camp's gates outside the fence line and the road, and at the corners where a
  tall wall's end stands beside a road it is seen from (the gatehouse's mouth, the clearing's east
  gate), every footprint off walkable ground.
- **Columns on the ground**: the massif round the walled camp (`massif_columns`, stacked with
  ledges; the heightfield under a column is dropped, `Ground.mask_quads`) and the plateau's lips
  (`lip_columns`); the gully's walls are cliff faces (`gully_faces`).
- **Stones** (kit pieces, role `rock`): StoneMonolith, StoneTall, StandingStone, StoneSlim,
  StoneLean, StoneBroad, RockB, RockA, RockFlat, RockSmall, Pebbles; EdgeRocks and the campfire's
  ring are built from them. Placed in clusters along the walled road (`scatter_stones`), on the
  creek and pond banks, at the feet of cliffs (`foot_boulders`), on the gully's rims and in the
  island shrine's ring.
- Budget at the redo: 149.8k triangles; the canopy went from 10- to 14-stud cells to pay for it.

## The mountain (MISSIONS_DESIGN 28, the climb)

The layout's climb (`check_parkour.CLIMBS`: a yard, seven ledge pillars spiralling round a core
whose top is the summit at 200) is dressed by its own functions, not the generic pillar style:

- `mountain_faces`: every side of the ledges and the core, coplanar sides of different pillars
  packed as one face (no seam where one runs on into the next; a block crossing a step in the
  skyline is cut at the real corner). Thin (`THIN_OUT`) up to `REACH_ABOVE` over the floor in
  front (the yard, or the ledge below), the big `mountUp` blocks bulging above that, the ones high
  on an outer corner wrapping round it; finer blocks (`mount.fine`) under every ledge's top and
  over a ledge in front (the hop faces); a ledge's top edge flush in its last 4 studs, and no
  block's front slides past a side's end where the next pillar stands.
- `mountain_caps`: every ledge top and the summit paved with flat light cap stones at the top
  lift over a dark grout: "stand here". `mountain_scree`: flat stones on the yard's floor at the
  foot (nothing stands over 0.2 in walking space).
- `dress_mountain`: the summit's ring of standing stones round the chest (under 4 studs, open
  toward the last hop's landing) and a fir in each of the yard's far corners. Round the yard the
  forest is lighter (`trees.yardNear`, `yardEdge`, `blanket.yardStart`): it is seen from inside the
  yard and from above, never along a road.
- Budget at F2: about 9k rock triangles for the whole mountain (faces, caps, scree); the level
  under the gate's 165k (the canopy went to 15-stud cells and drops the undersides nobody sees).

## Kit facts

- 1 glTF unit = 1 stud, Y up, front -Z, origin at the bottom centre; yaw turns like
  `CFrame.Angles(0, yaw, 0)`. Colour-only materials (one primitive per swatch), so `palette.py`
  bakes them for the props route; `palette-card.glb` carries every swatch.
- Roles and caps: `tree` <= 50 triangles, `hero` <= 200, `under` <= 160, `rock` <= 150, `edge`
  <= 250 and <= 4.0 tall, `clutter` <= 300 and <= 4.0 tall, `outside` <= 600 (beyond the walls
  only), `tent` <= 800 and inside an 8-tall marker, `chief` <= 4000 (walk-through).
- Thin panels (hides, banners, fern blades) are written once per side, the inside darker.
- The Chief's hall is placed at scale 1.25 (33 wide, 19 tall) with its door toward the clearing's
  entry and the boss point just inside its porch.
