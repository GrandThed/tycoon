# testfit — offline test-fit renders for modular buildings

Renders a building blueprint (Kenney kit pieces assembled per growth stage) with Blender,
so a building can be judged at every stage before anything is uploaded to Roblox.

## Run

```
blender -b -P tools/testfit/testfit.py -- --blueprint tools/testfit/blueprints/Village/tavern.json --out assets/testfit/out
blender -b -P tools/testfit/testfit.py -- --blueprint <file.json> --out <dir> --stage 2   # one stage only
blender -b -P tools/testfit/testfit.py -- --dump-bounds fantasy-town-kit                  # measure a kit
```

`blender` is `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"`. Kits are read from
`assets/kenney3d/<kit>/Models/GLB format/` (or `GLTF format/`). Outputs: `<id>_stage0..4.png`
(1280 x 960, EEVEE, fixed front-right three-quarter camera) and `<id>_strip.png` (all five
stages side by side, composed by `strip.py` under the system `py` because Blender's Python has
no Pillow). Stdout lists piece count and bounding box in studs per stage and warns when a piece
leaves the 9 x 9 stud footprint. A missing GLB is a warning, never a crash.

The render shows a light-grey ground, a red 9 x 9 stud footprint frame and a blue 5-stud
reference "player" box beside it.

## Blueprint format

One JSON file per building under `blueprints/<Era>/`:

```json
{
  "id": "tavern", "era": "Village", "scale": 4.0,
  "pieces": [
    { "kit": "fantasy-town-kit", "model": "wall-door", "pos": [0.5, 0, -0.45], "rotY": 90, "stage": 0 }
  ]
}
```

- `scale`: kit units to studs, applied uniformly to the whole assembly (1 glTF unit = 1 stud
  in Roblox, so kit pieces need roughly 4x to fill a slot).
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
