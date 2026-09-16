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
  a wall on x = 0) to hang them 0.02 outside the panel. `lantern` has a 0.22-wide base.
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
  2.4 (arm −Z: rotY 90 → −X, 270 → +X); `traffic-light*` ~2 studs; `road-sign-empty-hanging` reads as
  a bare lamp post.
