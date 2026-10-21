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
  (`ArenaBarrier`), from killY - 2 to 80 over the highest walkable top within 20 studs, 1 to 8
  studs deep, outside the walkable whole (walkable blocks, open camps' floors with their fence
  strip, water, the designed drops), cut where a tall layout wall already closes the edge.
- Designed drops are found from the layout: a route leg marked `via: gap`, and the void between
  a double-jump secret's ledge and the walkable block across from it. Water and steps between
  walkable blocks stay open by construction.
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
  No kit stone stands on walkable ground or water, the island shrine's ring aside.
- No two looks share a face: lifts over a collision top are floor 0.00, rims 0.03, camp 0.06,
  cave floors 0.075, road 0.09, a pillar's top 0.06; the shore line 0.06 over the water's top;
  rock flush with a visible Part (a bramble) is cut back from it; a kit piece's own floor 0.14.
- Meshes: at most 20,000 triangles, sides at most 1,500 studs, names `[A-Za-z0-9_]` up to 24,
  slivers under 1,500 triangles folded into a neighbour; budget 150,000 (gate at +10%).

## The rocks (Ben's references, 2026-10-21)

Every stone follows `assets/research/2026-10-21-l4/ref_rocks_*.png`: sculpted chamfered prisms with a
few big facets, light tops, darker sides (`forest_kit.rock_paint` picks the swatch by facing).

- **Cliffs** (`rock_faces`, `block_face`): every exposed face of a tall solid is a cliff of stacked
  chamfered blocks (`forest_kit.block_poly`) over one dark backing quad (no crevice ever shows the
  hidden wall or the sky). Columns of varied width with leaning joints, each stacked to its own
  heights with tilted joints (`joint_grid`); a tall face is cut into tiers per stretch with slanted
  seams; a free top's columns stand over it, rising and falling in groups. Styles in `ART.cliff`:
  `thin` (over walkers; its tiers above reach take `near` sizes), `tunnel`, `step`, `near` and
  `far` (by how near a walker in front stands, a tall wall in between hiding him), `pillar` (the
  lookout), `gully`. Tops get caps round their rim and a flat mossy floor in a wide top's middle
  (`block_caps`).
- **Columns on the ground**: the massif round the walled camp (`massif_columns`, stacked with
  ledges; the heightfield under a column is dropped, `Ground.mask_quads`) and the plateau's lips
  (`lip_columns`); the gully's walls are cliff faces (`gully_faces`).
- **Stones** (kit pieces, role `rock`): StoneMonolith, StoneTall, StandingStone, StoneSlim,
  StoneLean, StoneBroad, RockB, RockA, RockFlat, RockSmall, Pebbles; EdgeRocks and the campfire's
  ring are built from them. Placed in clusters along the walled road (`scatter_stones`), on the
  creek and pond banks, at the feet of cliffs (`foot_boulders`), on the gully's rims and in the
  island shrine's ring.
- Budget at the redo: 149.8k triangles; the canopy went from 10- to 14-stud cells to pay for it.

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
