# testfit — offline test-fit renders for modular buildings

Renders a building blueprint (Kenney kit pieces assembled per growth stage) with Blender,
so a building can be judged at every stage before anything is uploaded to Roblox.

## Run

```
blender -b -P tools/testfit/testfit.py -- --blueprint tools/testfit/blueprints/Village/Tavern.json --out assets/testfit/out
blender -b -P tools/testfit/testfit.py -- --blueprint <file.json> --out <dir> --stage 2   # one stage only
blender -b -P tools/testfit/testfit.py -- --dump-bounds fantasy-town-kit                  # measure a kit
```

`blender` is `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"`. Kits are read from
`assets/kenney3d/<kit>/Models/GLB format/` (or `GLTF format/`). Outputs: `<id>_stage0..4.png`
(1280 x 960, EEVEE, fixed front-right three-quarter camera) and `<id>_strip.png` (all five
stages side by side, composed by `strip.py` under the system `py` because Blender's Python has
no Pillow). Stdout lists piece count and bounding box in studs per stage and warns when a piece
leaves the footprint. A missing GLB is a warning, never a crash.

The render shows a light-grey ground, a red footprint frame (9 x 9 studs unless the blueprint
says otherwise) and a blue 5-stud reference "player" box beside it.

## Blueprint format

One JSON file per building under `blueprints/<Era>/<ModelName>.json`. The file name **equals**
the era config's `modelName` (PascalCase) and the blueprint's `id`; `blueprint.py` is the shared
loader/validator used by this renderer and by `tools/assets/merge_stages.py`, so a blueprint that
renders here merges there.

```json
{
  "id": "Tavern", "era": "Village", "scale": 4.0,
  "footprint": [9, 9],
  "pieces": [
    { "kit": "fantasy-town-kit", "model": "wall-door", "pos": [0.5, 0, -0.45], "rotY": 90, "stage": 0 }
  ]
}
```

- `scale`: kit units to studs, applied uniformly to the whole assembly (1 glTF unit = 1 stud
  in Roblox, so kit pieces need roughly 4x to fill a slot). Fixed at 4.0 for every M7 blueprint.
- `footprint`: optional `[x, z]` in studs, default `[9, 9]`; the frame and the out-of-footprint
  warning use it. The monument may go up to `[14, 14]`.
- `pos`: kit units before scaling, X / Y / Z with Y up (glTF and Roblox convention). The
  building's front faces -Z.
- `rotY`: degrees about Y. `+90` turns a piece's +X side to face -Z.
- `stage`: first stage (0 to 4) at which the piece exists. Stages only ever add pieces: a piece
  with stage N is present at every stage >= N. Nothing is ever removed, so a roof that a later
  storey replaces has to be buried inside that storey (see the notes below).

City-dressing props live under `blueprints/_props/<Era>/<PropName>.json` (same schema, usually one
stage) and run through the same tools with `--props`. **Careful: `upload_models.py --props
--dry-run` is not read-only — it pre-lists the prop's entries into `src/shared/Config/Assets.json`
(only the network calls are skipped).** Check `git status` after a dry run rather than assuming the
file is untouched.

## Plot render

`testfit.py` judges one building; `plotrender.py` judges a whole plot. It assembles every slot's
building at its final stage, the streets, pavements, footpaths, pads, the elevated highway, subway
kiosks, plazas, trees and traffic from the same sources the game uses, and renders it from the
tycoon camera -- so an era's dressing can be looked at before anything goes into Studio.

```
py tools/testfit/plotrender.py Metropolis                      # plot_overview.png
py tools/testfit/plotrender.py Metropolis --camera entrance
py tools/testfit/plotrender.py Metropolis --camera ramp
py tools/testfit/plotrender.py Metropolis --camera plaza
py tools/testfit/plotrender.py Metropolis --camera cityhall
py tools/testfit/plotrender.py Metropolis --camera 28,-28      # any plot-local x,z
py tools/testfit/plotrender.py Metropolis --tier 3             # the plot partway through the era
py tools/testfit/plotrender.py Metropolis --owned cityGrid,foodTruck
py tools/testfit/plotrender.py Boomtown --camera overview
py tools/testfit/plotrender.py OrbitalColony --tier 2 --out plot_tier2
```

Output: `assets/testfit/out/<Era>/plot_<camera>.png`, 1600 x 1000 (`--out` renames the stem).
About 60-100 s per render; most of that is importing the kit GLBs.

- The driver runs under the system **`py`** (it imports `tools/streetplan.py`, which needs Pillow)
  and shells out to Blender for `plotscene.py`, handing it the scene as a temp JSON of boxes and
  blueprint placements. `BLENDER=<path>` overrides the Blender executable.
- **Nothing is re-derived.** The layout, era config, `CityDressing.json`, the spurs, the road
  network and the shortest-path visibility all come from `streetplan.Era` / `streetplan.Network`;
  the tile lattice, the 16-entry connectivity table and the zebra rule mirror
  `src/client/City/TileRenderer.luau`; the ring cycle and the ramp mirror `Highway.luau` and the
  INTERFACES "Elevated highway" contract. Change a contract and change this with it.
- `--tier N` on its own owns exactly what `sim_economy`'s greedy player has by tier N, so the
  render shows the half-built plot the client would really draw. With no `--tier` the plot is
  finished. `--owned` takes a comma list of slot ids and wins over `--tier`.
- **Lighting is calibrated, not copied from `testfit.py`:** sun + fill + sky add up to about pi of
  irradiance, so a surface renders near its authored colour. testfit's brighter rig blew the
  Metropolis plot base (88, 90, 94) out to near-white, and the point of this render is to judge
  the era ground colour, not a white card.
- **Camera:** the same (+X, -Z) tycoon quadrant as `testfit.py`, so the plot's hub edge (-Z) faces
  the viewer, but the aim point is recentred on the *projected* bounds and refitted a few times --
  a 120-stud plot seen from a corner puts its near corner far off the view axis, and a
  centre-aimed camera wastes half the frame. `entrance` is a fixed eye at character height just
  outside the ring, looking up the entrance avenue.
- Non-tile eras (Village, Boomtown) draw their spine as plain slabs of `road.width` in
  `road.color` -- deliberately the stand-in, not the baked mesh pieces, which `tools/paths` judges.
- **Park strips** (`road.tiles.parkStrips`) are drawn for every planned cell whose street has not
  grown yet, so `--tier N` is the way to look at them -- a finished plot has none. The kerb and the
  strips share one cut (`cut_against`): each cell in turn subtracts what is already laid, in the
  plan's cell order, so nothing is covered twice. The keep-out set (tiles, kerb, block slabs,
  kiosk rectangles) is sorted on `rect_key` first, because the order the cuts are made in decides
  how many Parts a band takes, and Parts are what the `budget.tileCells` ceiling is spent in. A
  cell swallowed whole by earlier strips still counts as a strip cell, so its planter stays.
  Planters come from `Scatter.parkStripTrees`: each run is stitched into one curve and walked at
  `treeSpacing`, one planter to a lattice cell, blocked by footprints and spurs, ordered
  `(polyline, stretch, step)` and thinned to `maxTrees`; they stand only where a strip is still
  down, at the fixed `treeStage`.
- **Orbital Colony (wave 2b)** reuses every tiles-era pass: tube props are the tiles (no
  `pavement`, no `parkStrips`, so both passes draw nothing), `blocks` are the decking with
  `treeSpacing` 0 (no edge trees), and the `highway` is drawn in **loop mode** when the layout has
  no `ramp`: deck and corner props only, no junction, ramp or sign, exactly as `Highway.luau`
  masks it. Deck vehicles come from `highway.vehicleProps` (default: the era's street vehicles);
  in loop mode they ride the centreline (the client's lane offset is 0 there), spaced evenly from
  the middle of the -Z leg at `deckHeight`.
- **Trees by tier:** with `--tier N` each tree shows `Scatter.TreeStage` at that tier (zone trees'
  birth tiers spread evenly, street trees born at 1; zone candidates are thinned evenly to the cap
  like the client, not truncated). Without `--tier` every tree is at its final stage.
- **Placeholders:** a prop whose blueprint is missing, unusable or places no kit piece (GLBs not
  generated yet) is drawn as grey-box stand-ins in the colour it is meant to be -- tube cells as a
  hub plus open arms, ring cells as a beam under `deckHeight` on a pier -- and the driver prints a
  `MISSING blueprints` line (Blender logs the no-GLB ones). A render with placeholders is a layout
  check, not a look check.
- **Colour, as the game shows it:** colour-only kit materials render with metallic 0 (the palette
  bake drops it), and `space-kit`'s factors are decoded from sRGB once on import (palette.py
  `SRGB_FACTOR_KITS`, restated in `plotscene.py`), so its orange and dark slate match the game
  rather than washing out as they do in the single-building `testfit.py` strips.
- **Known deviation from the shipped client:** the ramp prop is placed with its highest cell one
  whole cell inward of the ring junction, which is what the contract describes and what
  `streetplan.py` checks (its three cells are `junction + direction * k`, k = 1..3, and its toe
  lands on the street's end cell). `Highway.luau` places it at the junction cell's *inner edge*,
  half a cell further out. The render follows the contract.

## fantasy-town-kit notes (measured with `--dump-bounds`)

- Wall panels (`wall*`, `wall-wood*`) are 1 x 1 x 0.1, bottom-origin, and occupy the +X face of
  a unit cell (x 0.4..0.5); the detailed side faces +X. Place the holder at the cell centre and
  rotate: `rotY` 0 = right (+X), 90 = front (-Z), 180 = left (-X), 270 = back (+Z). Each panel
  has posts at both ends, so corner posts overlap by design.
- `roof` / `roof-high` are shed halves: ridge on the +X edge (0.63 / 1.14 tall), eave overhangs
  0.07 on -X, closed triangular ends. Two per row, mirrored, make a gable.
- `roof-gable*` / `roof-high-gable*` are full one-cell gables with the ridge along X
  (1.1 wide, eaves overhang 0.04..0.07 in Z). `roof-gable-top` (0.376 tall) and `roof-flat`
  (0.126), `planks` (0.06) are exactly 1 x 1 with no overhang.
- `roof-corner` / `roof-high-corner` are hip quarters with the peak at the +X/-Z corner; four of
  them with `rotY` 0/90/180/270 at cells (-,+)/(+,+)/(+,-)/(-,-) make a 2 x 2 pyramid.
- `roof-point` / `roof-high-point` are 1.1-wide pyramids, 0.5 / 1.0 tall.
- `chimney-base`, `chimney`, `chimney-top` stack on the same cross-section just inside the +X face
  (x 0.25..0.43); a cap alone, sunk into a roof, is enough for a small building.
- `banner-*` hang at x 0.38..0.43, so offset the holder +0.62 from a wall cell centre (or -0.38 for
  a wall on x = 0) to hang them 0.02 outside the panel.
- `lantern` is **not** wall-hung: it is a free-standing lamp post, 0.216 x 1.556 x 0.224 units,
  **bottom-centre origin** and radially symmetric, so `rotY` does not matter. At scale 4 it is
  6.22 studs; the Village `Lantern` prop uses scale 3.2 → **4.98 studs** (measured 2026-09-18,
  wave 1e).
- Burying an old roof inside a new storey works only if the buried piece has no outward-facing
  vertical face on the cell boundary (hips and flat slabs are fine; `roof-gable-top` end triangles
  z-fight with the wall in front of them).

## More kit notes from the Village authoring (four builders, 2026-09-15/16)

Render orientation: the blue player box sits at +X/−Z and appears at screen-LEFT; +X is to the
lower-left of the frame, the −Z front of a piece shows on its right-hand side.

fantasy-town-kit:
- Every gable roof (`roof-gable*`, `roof-high-gable*`, `*-top`, `*-end`, `*-detail`) is an OPEN
  shell at both ends: anything buried under it shows through. A roof can be buried inside a storey,
  never inside a taller roof. `roof-point`/`roof-high-point` and hips are closed. Burying a
  `roof-point` under a later storey leaves a thin coloured lip at the storey line that reads as a
  deliberate string course.
- Colours: teal = `roof-gable*`, `roof-gable-top`, `roof`, `roof-corner`, `roof-point`, `roof-flat`;
  red = every `roof-high-*`. Previews in `assets/kenney3d/<kit>/Previews` are 64 px and mislead on
  colour; a testfit render is the reliable check.
- `roof-gable-top` pairs at x = ±0.45 overlap 0.1 in the middle and put their closed ends at ±0.95,
  inside the later storey's wall panels — clean burial. `roof-high-gable` reaches 0.567 in its short
  axis, so the Tavern grid (x ±0.5, z −0.45/+0.55) is the widest usable one.
- `wall-wood-window-small`, `wall-wood-window-round`, `wall-wood-doorway-square-wide`,
  `wall-wood-arch-top` are lavender stone with wooden details; only `wall-wood`, `wall-wood-door`,
  `wall-wood-window-shutters`, `wall-wood-detail-*` read as timber.
- Exterior chimneys do not fit: an 8-stud building fills the footprint. Put chimneys INSIDE the cell
  resting on `planks` (which span the full cell) with only the cap showing. `chimney-top` is 0.04
  wider than `chimney`, so a cap can never be buried inside a later chimney segment.
- `overhang` is inboard (x 0.14..0.42, behind the wall panel); push the holder 0.23 past the wall
  to make it an awning. `fence` (x 0.42..0.5) z-fights when buried under a later wall panel — inset
  it 0.02. The `roof` shed's tall side is a vertical face; sink it 0.01 into the wall behind.
- Banner in front of a wall whose outer face is at z = f: holder z = f − 0.38 (rotY 90).
- `windmill` is ONE mesh 3.11 units across with "+" blades; only a 45° diagonal fits 9×9, and its
  tips still overhang 0.5 studs (accepted for Village). `blade` is a single vertical sail. `cart`
  and `cart-high` shafts point −Z. No `well`, no crate models (stacked `stall-stool` stands in).
  `road-curb` renders flat at scale 4; `road-edge` has a readable curb band. The fountain water
  node is colour-only and is remapped to the colormap's blue at merge time.

castle-kit:
- All wall pieces are 1.31 tall, bottom-centre origins; `wall`, `wall-corner`, `wall-half`,
  `wall-pillar` are full 1×1 blocks. Walls run along Z with battlements on the ±X faces; rotY 90
  runs them along X. `wall-narrow`/`wall-doorway` are 0.5 thick (local x −0.5..0); `gate` is a
  0.15 × 0.91 × 0.66 leaf facing ±X. `wall-corner-half-tower` is 1.5×1.5 with the tower at +X+Z.
- Tower ladder is 1.01 per storey: `tower-square-base` 1.0 wide (door on +X), `tower-square-mid*`
  0.93 wide so they nest inside the 1.0-wide `tower-square-top` ring (0.3 tall, stays as a string
  course). `tower-square-top-roof-high` 1.35 (ring + spire), `tower-square-roof` 2.01,
  `tower-slant-roof` 1.17 × 2.14. `tower-square-mid-open` renders as bare timber framing;
  `tower-hexagon-top-wood` is a 0.86 deck cap.
- `flag`/`flag-pennant` 0.87 tall, cloth points −Z (rotate 180 near a −Z edge).
  `flag-banner-long` hangs 2.17 tall at local x 0..0.04 (hang on a +X face; rotY 90 for the front).
- At a one-cell footprint the tower pieces always read as a keep (peach stone vs the town kit's
  lavender): right for CastleKeep/Watchtower, wrong for a church tower. A castle
  `tower-square-top-roof-high` does sit cleanly on a fantasy-town 1×1 storey as a spire.

nature-kit (material colours; the merge tool bakes a palette texture):
- GLBs live under `Models/GLTF format/`; testfit finds them. Every piece is centre-origin in XZ and
  extends 0.05 below y = 0 (stage bounds report −0.2 studs; harmless, it sinks into the plot base).
- Pieces are small at ×4: tents 2.2 studs tall, campfire rings ~2 across with no flame geometry,
  flowers ~0.8. `fence_simple`/`fence_gate` span x −0.5..0.5 with the rail at z −0.50..−0.43.
- Foliage is bright teal-green and wood orange-tan, lighter than fantasy-town; reads as props next
  to it. `rock_*` are pale grey; `stone_*` render cyan — avoid them.

## retro-urban-kit notes from the Boomtown authoring (three builders, 2026-09-16)

Textures: **no single colormap.** GLBs reference 22 separate 64 px textures in
`Models/GLB format/Textures/` (wall, windows, doors, concrete, metal, roof, signs, …), and the UVs
tile far outside 0..1 (u −46..32), so they cannot be atlased. A Boomtown building uses 3–11 of
them per stage. `wall-a-detail`, `wall-a-detail-painted`, `wall-b-detail-painted` also carry a
2-triangle colour-only `_defaultMat`.

Blocks:
- `wall-a*` / `wall-b*` are closed 1×1×1 cubes, bottom-centre origin, concrete slab top, white
  plinth and trim band. The detail (door/window/garage) is on **−Z**; the other faces are plain, so
  plain cubes stack with no z-fight and a buried flat roof is invisible. The plinth reads as a
  storey line. Detail to +X: `rotY` 270; to −X: 90; to +Z: 180.
- `wall-a` = red brick with white pilasters; `-painted` = slate-blue upper band (shop/sign band).
  `wall-b` = **green corrugated metal**, not brick; it lacks `-painted`, `-detail`, `-flat-painted`.
- `-low` half-height cube; `-open` four corner posts + slab (canopies, shopfronts); `-corner` L-cube;
  `-diagonal` triangular prism; `-column` 0.25 pier; `-detail` 0.6 × 1 × 0.2 pilaster.
- Garage doors are recessed: keep anything buried in a later garage cell ≥ 0.35 behind the face.
- Shopfront: `wall-a-open` + `wall-type-a` sill + `window-wide-type-*` at y +0.3, both at cell
  centre −0.46 in Z.

Roofs: `wall-*-roof` are 0.5-tall gables, exactly 1×1, closed brick ends; `-detailed` overhangs to
1.137 and clashes with a neighbour (use plain ones side by side); `-roof-slant` is a shed.
`roof-metal-type-a/b` are the same gable with **open ends** — seen end-on it is a clean 45° "^"
chevron (NeonSign's arrowhead). `roof-metal-poles` four 0.7 posts; `scaffolding-poles` four 1.0
posts; `scaffolding-structure` a stackable 1×1×1 lattice (RadioStation mast); `scaffolding-floor`
a 0.07 grate.

Flats and decals:
- `wall-a-flat`, `wall-a-flat-painted`, `wall-b-flat` are **zero-thickness single-sided quads**;
  use a back-to-back pair (second copy `rotY` 180, 0.01 behind) for any sign seen from both sides.
  `*-flat-window` / `*-flat-garage` are 0.1 thick (z 0..0.1). `wall-c-flat*` are black iron grilles.
- `door-type-a` (red, panic bar), `door-type-b` (brown), `window-*` are 0.05 decals; 0.52 from the
  cell centre puts them on a face. Window types: `wide-a` light blue barred, `wide-b` light two-pane,
  `wide-c` dark cross grid, `wide-d` dark green.

Props:
- `detail-awning-small/wide` dark corrugated, 0.3 deep, slope down to −Z, attach on +Z edge; centre
  0.6 in front of the cell centre. No striped or coloured awning exists.
- `balcony-type-a` black railing, front rail on −Z: 0.61 in front of cell centre on a facade, 0.36 as
  a roof parapet.
- `detail-light-single` 0.96 tall (3.84 studs), arm −Z (rotY 180 near the front edge);
  `-double` is a T; `detail-light-traffic` 1.04 tall, arm −Z, no visible lamps.
- `detail-beam` 0.25 × 0.25 × 1 along Z; sunk to 0.02 above asphalt it is the only road marking.
- `road-asphalt-center`/`-pavement` are 0-height; `-straight` is 1 × 2 with raised pavement at both
  Z ends; no tile has a painted line.
- `truck-*` 0.83 × 1.0 × 1.64, cab −Z, fit a 9×9 slot (`truck-green` carries a smiley logo).
  `detail-dumpster-closed` (green) makes a food cart; `detail-cables-type-a` a pennant string;
  `detail-barrier-type-a/b` (yellow/black) are the only sign-like boards.
- Only bright colours: red doors, yellow/black barriers, green `wall-b`, orange trees. No tyres,
  crates, produce, letters, emissive pieces.

car-kit: every vehicle is 2.2–3.45 units long (≥ 9 studs at ×4) and pastel; none fits a 9×9 slot and
all clash with retro-urban. `debris-tire` is centre-origin and reads as an oversized black blob.

## city-kit-commercial and city-kit-roads notes (authored as a Boomtown redo 2026-09-16; the kit now belongs to Metropolis)

Both kits use one `colormap.png`. Palette: off-white walls, slate trim, dark ground floors, pale-blue
windows; accents only green (awnings, planters, parasols, `building-m` roof, `sign-highway` faces,
dumpster) and yellow (`g`/`i`/`k` shopfronts, traffic-light housings); orange/white construction
pieces; red only on `road-sign-object-stop`. No brick, no emissive, no bus, no bench, no hydrant.
Skyscrapers and `low-detail-building-*` are reserved for Metropolis (ClockTower's shaft excepted).

city-kit-commercial:
- Every `building-*` is a finished building, bottom-centre origin, **front −Z** at rotY 0. Sizes at
  ×4 are small: a 2-storey building is 3.6 studs, shorter than the player. `-n` (2.32 wide) does not
  fit 9×9.
- Characters: `a` 3 storeys curved corner; `b` like `a` plus rear fire escape; `c` 2 storeys; `d` roof
  terrace with tree; `e` wide, one-storey −X half and two-storey +X half; `f` 4 storeys green awning;
  `g` 4 storeys yellow awning; `h` 3 storeys dark; `i` 4 storeys yellow shopfront; `j` 4-storey
  apartments with balconies; `k` wide 3 storeys, twin yellow shopfronts, water tower (0.94 deep —
  nothing nests inside it); `l` 5 storeys; `m` 7-storey tower with green pyramid roof and spike
  (distinctive: use it in one slot per era only).
- Roof decks sit below the bbox top (which is a parapet or rooftop box): `c` 0.80, `d` 0.80 front /
  1.20 back, `e` 0.40 / 0.80, `h` and `k` 1.20, `f`/`g`/`i` 1.60, `l` 2.00, `m` 2.40 (hip 2.79, spike
  3.15), `skyscraper-d` 5.20, `skyscraper-b` 4.40. Props placed at bbox top float.
- **Growth by swallowing:** outer walls sit flush with their bbox, so a later building at the same
  centre hides an earlier one with ≥ 0.01 margin. Clean: `a`,`b`,`c`,`d`,`h` in `i`; `c`,`f`,`g`,`h`
  in `l`; `a`,`d`,`g` in `m`; `e`,`f` in `j`; `c`+`d` together in `j`; `d` in `g`. Fails: `i` in `l`
  (yellow awning shows). The camera sees only −Z and +X; check the back with a rotated copy
  (positions (−x, y, −z), rotY + 180) in a scratch blueprint.
- `detail-awning*` (green) and `detail-overhang*` (white trough) are free-standing canopies on legs,
  0.4 tall, wall side at local z +0.10 / +0.05, legs toward +Z: for a −Z wall at z = f use rotY 180,
  holder z = f + 0.10 (awning) / f + 0.05 (overhang). A back-to-back pair makes a two-legged stall
  canopy. `detail-parasol-a/b` are identical umbrella tables, 1.8 studs.

city-kit-roads:
- Road tiles are 1×1 (4 studs); asphalt top y 0.010, curb strips (|z| > 0.4) 0.020. `road-crossing`
  has zebra stripes; `road-square` reads as a parking bay. `tile-low` is a 0.02 lavender slab — as a
  sidewalk under a road edge place it at y −0.015 (−0.005 covers the asphalt, −0.025 vanishes under
  testfit's ground at −0.001). `tile-high` is a 1-stud lavender plinth.
- `sign-highway*` gantries: green face on local −X only (grey/slate back) — rotY 270 faces −Z, 180
  faces +X. 0.7 tall, posts at z ±0.45; stacking at +0.60 makes a pylon, every 0.2 with a 0.03 step
  makes a solid panel. `road-sign-object-stop` red face also on −X.
- `bridge-pillar` 2-stud column; `bridge-pillar-wide` 0.5 tall, 0.088 body, stacks every 0.5 (packed
  0.088 apart the bodies form solid bands); `construction-fence` 0.375 rail fits between pillars 0.5
  apart; `electricity-pole` (orange wood) stacks every 0.525; `construction-light` 0.234 (0.94 studs,
  orange/white striped — a barber pole / beacon) sits on a pillar cap; `construction-cone` 0.38
  studs; `dumpster` green 0.28×0.21×0.37 along Z; `light-curved` 2.7 studs (arm −Z), `light-square`
  2.4 (arm −Z: rotY 90 → −X, 270 → +X); `road-sign-empty-hanging` reads as a bare lamp post.
- `traffic-light` and `traffic-light-object-vertical`: the **lens faces local −X** (so `rotY` 270
  points it at −Z, 90 at +Z, 180 at +X); the plain back is on +X. `traffic-light` is **0.515 tall**
  (2.06 studs at ×4; the Boomtown `TrafficLight` prop uses scale 9 → 4.63 studs), and a second head
  at **y 0.30, x +0.03** sits flush against the first (measured 2026-09-18, wave 1e).

Measured during the Metropolis Stadium authoring (2026-09-17), when the kit was pushed at a
subject it has no pieces for:

- **Grid arithmetic.** A 9x9 footprint at scale 4.0 is 2.25 kit units, and every `tile-*` / `road-*`
  piece is 1x1 unit, so a ring of tiles around an inner court always leaves a 0.25-unit (1-stud)
  hole. A 12x12 footprint is exactly 3.0 units and tiles evenly -- prefer 12x12 (contract: allowed
  up to [12, 12] for a non-monument slot where the kit cannot express the subject at 9x9) over
  fighting the remainder.
- **Plain mass is only `low-detail-building-n`, `-d`, `-k`** (white boxes with a small dark roof
  recess). `low-detail-building-a` and the `-wide-a/b` variants carry a large dark glazed panel on
  their long faces and read unmistakably as office blocks -- they cannot serve as stands, terraces or
  plain walls. Everything else thin in this kit (`detail-overhang*`, `detail-awning*`, `sign-highway*`,
  `bridge-pillar*`, `construction-fence`) is an open/legged prop with no mass.
- **`road-straight-half` (0.5 x 0.02 x 1.0) is the only flat plate that exactly matches a 0.5-deep
  wall band** -- the cheap way to cap a run of `low-detail-building-*` so it reads as one wall
  instead of a row of boxes with roof recesses.
- **Stacked canopies read as scaffolding.** Tiers built from `detail-overhang-wide` alone look like
  bleacher scaffolding; canopies only work as a single roof course resting on solid blocks.
- **`light-square-cross` reads as a TV antenna** (straight arms); `light-curved-cross` reads as a
  lamp cluster and is the better floodlight. Free-standing masts on open ground read as an antenna
  farm -- mount lights on a roof or parapet.
- **`road-bend` tiling** gives a pinwheel at rotY 0/90/180/270 and four quarter-annuli around a
  4-pointed star at 0/270/180/90. Neither makes a clean oval, so an athletics track is not available.
- **Slant rise directions:** `tile-slant` / `tile-slantHigh` / `road-slant*` rise toward **+X at
  rotY 0, -Z at 90, -X at 180, +Z at 270**. Wedges cannot rise diagonally, so where two perpendicular
  runs meet there is always a cliff -- put it at a corner where it reads as a corner gap.
- **Ground surfaces:** `road-straight` at rotY 0 is the best marked-field surface in the kit (dark
  asphalt, pale raised kerb bands across the tile ends, thin white centre line); the same tile at
  rotY 90 reads as a road, because the bands then run lengthwise. `road-split` reads as a junction
  and `road-crossing` as a zebra crossing, so neither works as a field; `road-square` over a
  `tile-low` apron reads as a pale platform with a dark inset. Overlapping coplanar road tiles need
  ~0.005 units of y separation to kill z-fighting, which is invisible at 4x.
- **The testfit camera sits in the (+X, -Z) quadrant at ~30 degrees elevation** -- +Z at screen
  upper-left, +X lower-left, -X upper-right, -Z lower-right. A wall of height h hides roughly 1.73h
  of ground behind it, so a model whose interior must stay visible (a stadium bowl, a courtyard) has
  to keep **both** the +X and the -Z sides low, not just the front.

## city-kit-suburban and city-kit-industrial notes (Boomtown authoring, five builders, 2026-09-16)

Both kits use one `colormap.png`, the same palette as the other City Kits (green suburban roofs,
slate industrial walls, orange doors/bands). Storey grid is 0.4 units (1.6 studs) in both kits.

Height at ×4 is the constraint: houses are 3–5 studs, industrial buildings ≤ 7.7, `water-tower` 8.6.
Stacking flat industrial blocks gets taller but reads as a Metropolis office tower; Ben chose
"lower, wider" (ordinary slots ≤ 13 studs, growing by width and clutter; only landmarks tall).

city-kit-suburban:
- `building-type-*` doors: `a g h i j m` on −Z; `r` has a door on every side. `h`, `j` have solar
  roofs; `j` has its own chimney at +X. `h` and `j` are both 0.916 deep (neither swallows the other).
- **Houses cannot be stacked or swallowed**: every roof overhang pokes out as a diagonal lip. A house
  sits cleanly on a flat industrial deck (`type-c` on `building-c` at (+0.1, 0.5, 0) buries its vents;
  `type-e` on `building-a`'s parapet at +1.28, rot 0 or 90). `p`/`q` stack flush at 0.85.

city-kit-industrial:
- Many GLBs are off-centre on their origin (`c d e f h i j l n o q`, `detail-tank-large`): place from
  `--dump-bounds` min/max.
- Parapet / deck: `a` 1.28 / 1.20; `o` 0.88 / 0.80; `q` 0.58 / 0.50 (box 0.88); `p` 0.715 / ~0.66;
  `g` block 1.28; `t` box 0.88; `l` 0.88; `d` 1.28 / 1.20 (rear porch canopy z −0.80..−0.65 to y 0.40);
  `b` main 1.20 (x −0.15..1.04), annex 0.50 with rim 0.58; `e` front 0.50, rear block 0.90;
  `f` low 0.50, high block 0.90; `h` ridge 0.72 along Z, lean-to 0.40.
- Clean stacks: `a` on `a`, `o` on `o`, `s` on `s` at +0.5; `q` on `q` needs a (+0.04, +0.04)
  offset; `l` on `q` at q + (0.23, 0.39, −0.10) buries l's annex. Two `g` at rot 0 / 180 offset
  (+0.01, 0, +0.44) merge into one 1.68 × 0.84 × 1.28 block. `l` stacked on itself leaves a floating gap.
- `building-a` at rot 180 has a blank front; its back shows garage doors. `building-j` (quonset)
  has a garage door on −Z and a side door. `building-m`'s three orange-tipped stacks read as pins.
- Props: `chimney-basic` white with orange band, open top, stacks leave a band per joint (a
  `construction-light` hides inside the next segment); `chimney-small` on the `l` chimney at
  l + (−0.295, 1.925, +0.935). `shipping-container-a/b/c` orange/green/blue, stack 0.348, pack 0.373.
  `water-tower` feet (±0.35, ±0.33), tank y 1.27–2.14. `detail-tank` reads as a hot-dog cart.

city-kit-roads (additions):
- `sign-highway*` board is 0.23 tall (y 0.48–0.71), posts at local z ±0.45 run 0.48 below to foot pads;
  `sign-highway` is two boards with a centre gap, `-wide` one board, `-detailed` two boards with orange
  underlines. Put a board's holder ~0.03 behind the posts. Stacked `-wide` every 0.2 reads as separate
  bars; a solid face needs rows ~0.21 apart with alternating 0.012 offsets, and a back-to-back layer.
- `road-bridge` is a 1×1 road deck on 4 columns, deck top 0.51, 0.43 clearance (fits a container),
  stacks every 0.52. `electricity-pole` is an H-frame; two crossed (rotY 0/90) per 0.525 make a lattice
  mast. `road-sign-empty` stacks every 0.475 with a knob per joint. `road-sign-street` blades read as
  pennants. `road-sign-object-warning` is an orange diamond (0.134, centre origin). A chain of
  `road-sign-object-stop` discs at 0.125 pitch reads as a continuous red neon tube (one-sided).
  `road-side` is a road tile with a wider kerb strip on local −Z. `tile-high` is 1×1×0.25 lavender;
  overlapping coplanar tiles show no z-fight. `construction-barrier`/`-fence` render grey.
- testfit's footprint warning tolerance is 0.01 kit units.

## space-kit and orbital-kit notes (Orbital Colony authoring, three builders, 2026-09-18)

**Origins are offset.** Every space-kit piece carries a baked `tmpParent` transform: its bbox centre
sits about **(+2.00, +1.50)** in X/Z from the local origin, and not uniformly (`corridor_end` Z +1.75,
`corridor_wall` X +2.45, `pipe_corner*` (+1.92, +1.42), `terrain_road*` (+2.5, +1.0), `rail*` Z +1.98,
`pipe_ramp*` Z +2.0, `astronaut*` Z +1.54). `pos` places the origin and `rotY` rotates about it, so
the offset rotates too: to centre a piece with offset (ox, oz) at (cx, cz), use
`pos.x = cx - (ox cos t + oz sin t)`, `pos.z = cz - (-ox sin t + oz cos t)`. For (2.0, 1.5): rotY 0 →
(cx−2.0, cz−1.5); 90 → (cx−1.5, cz+2.0); 180 → (cx+2.0, cz+1.5); 270 → (cx+1.5, cz−2.0). Every
builder wrote a helper that places by bbox centre from `--dump-bounds`; do the same. Non-90° `rotY`
inflates the AABB the footprint check uses.

**Colour.** Material-colour kit, all `metallic 1`. Kenney wrote **sRGB values straight into the
factors**, so `palette.py` lists it in `SRGB_FACTOR_KITS` and writes swatches unconverted (orange
255,160,52; dark 70,76,87; hull 215,222,232; rock 232,132,99; crystal 47,224,151). Decoded as linear
it washes out to pale amber and mid-grey. White/orange pieces: `platform_*`, `hangar_*`, `corridor_end`,
`pipe_*`, `structure_closed` (white panels, orange frame, open top), `supports_*`, `stairs`, barrels.
Orange open frames: `structure`, `structure_detailed`, `structure_diagonal` (gantry pieces). Salmon:
`terrain_*`, `rock*`, `meteor*`, `crater`; `rock_crystals*` carry bright green nubs. Dark: the roof
panel of every `corridor*` tube, the upper slope of `hangar_round*`, a wide roof band on
`hangar_largeB` (`hangar_largeA` is the same hall, plain white), `machine_wireless`. The Orbital plot
base is RGB (56, 53, 60): never let a dark surface be the outline or the largest face — cap it
(orbital-kit `drum_large` seats on a hex hangar's plateau; a `corridor_end` pair is a white-topped
closed 1×1×1 module). No lamp, solar panel, flag, glass or green exists in space-kit.

**Sizes at ×4.** 9 studs = 2.25 units. `hangar_small*` 2×1×2 (8×8 studs, open bay / door on −Z);
`hangar_large*` 2×1×3 and `hangar_round*` 3.27×1.5–1.8×2.83 fit no 9×9 slot — three landmarks use
**scale 3.6, footprint [12, 12]** (INTERFACES Blueprints). `hangar_round*` are hexagons with flat
facets on ±Z and corners on ±X, closed shells (anything inside is hidden). Crafts: only `craft_racer`
(4.8 × 8.1 studs, nose −Z) and `craft_speederA/B` (8 × 8.4) fit. `rover` is 1.2 × 1.5 × 1.4 studs.
`astronautA` 3.2 studs, good free "life".

**Assembly.**
- Rocket: `rocket_baseA` at y 0 (1.6 tall, 1.8 wide), then the 1.0 grid from y 1.0: `fuelB`/`sidesA`/
  `sidesB` 1.0 tall (`sidesB` 1.3 wide, stacks on itself), `fuelA` a 0.5 band, `rocket_topB` 1.1.
- `platform_high` is an open table (deck + four legs); a 3×3 array is a launch pad. A plate resting
  exactly on a roof z-fights — raise it 0.02; stacked storeys sink 0.01. Two `platform_long` side by
  side show a double rim seam; use `platform_large`.
- Corridors butt-join end to end cleanly; two parallel tubes z-fight on the shared wall. A short run
  capped with `corridor_end` at both ends reads as a blob — leave tube ends open. `corridor_window`
  at rotY 90 runs along X.
- `gate_simple` / `gate_complex` are free-standing hexagonal hoops on a base (airlock collar when
  sunk ~0.25 into a wall). `rail_middle` sits on the +Z edge of its cell at rotY 0. `stairs` rises
  toward +Z and must abut what it climbs.
- `supports_high` stacks into a lattice mast with a collar per joint, and a `machine_barrelLarge`
  fits between its legs. `pipe_supportHigh/Low` share the 0.4 × 0.4 section of `chimney*`, so a flue
  grows in 1.0 / 0.5 steps and takes the tapered `chimney` as its cap. `pipe_supportHigh` alone reads
  as a blocky pylon, not a mast. `pipe_ringHigh` reads as a plant vent wheel.
- Speckle on a platform top is EEVEE shadow dithering, not z-fighting.

**orbital-kit** (`tools/assets/orbital_kit.py`, generated; 21 pieces, all bottom-centre origin, no
offset): `dome_small/medium/large` nest strictly (a growing dome is the next size at the same spot),
`dome_small` also nests in `dome_slit`; two stacked `drum_medium` bury a `dome_small`, so a cupola
climbs a tower by adding two drums and a fresh dome. Drums already carry lit window bands. Dome on a
drum: y +0.40. `dome_slit` shutter and `telescope` lens face −Z at rotY 0 (the telescope foreshortens
aimed at the camera; use rotY 90/270). `solar_panel`/`solar_tracker` face −Z, high edge +Z.
`light_panel` lit face −Z, holder 0.015 clear of the wall. `mast_segment` stacks every 1.0; `mast_tip`
is 0.6 wide. `flag` pole at local x −0.275, cloth toward +X. `pad_marking` has a dark disc: only on a
white deck. `planter_tray` is the only green in the era.
