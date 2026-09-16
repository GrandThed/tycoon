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
