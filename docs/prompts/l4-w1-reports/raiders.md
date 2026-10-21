# L4 W1, track R: the raiders and the Camp Chief, prototypes (raider kit lead's report)

Worktree `tycoon-p5`, branch `l4-real-forest`. Nothing committed, nothing uploaded; no `upload_*`, `harvest.py` or
`gen_templates.py` run. Only my own files were written (list at the end). Every strip below was judged with the Read
tool; `py tools/testfit/raiderpose.py --check` passes for all three; `merge_stages.py --props --era Raiders` reports
0 problems and its triangle counts equal the generator's.

## 1. The prototypes

All in `assets/testfit/out/Raiders/` (raw renders and specs in `_raw/`).

| | Fodder | Brute | Camp Chief, look A |
|---|---|---|---|
| Model | `RaiderFodder` | `RaiderBrute` | `RaiderChief` |
| Pose strip | `RaiderFodder_strip.png` | `RaiderBrute_strip.png` | `RaiderChief_strip.png` |
| Hit shapes it is built on | 5 / r 1.3 / head 0.7 | 7.5 / r 2.2 / head 0.9 | 14 / r 4 / head 1.6 (the Colossus's) |
| Drawn height | 5.0 (feather tip 5.16) | 7.5 at the skull cap (horns to 8.2) | 14.0 at the hood (wolf ears to 14.66) |
| Triangles (budget) | 594 (600) | 1,196 (1,200) | 3,340 (4,000) + the Warhammer 3,142 |
| Per piece (head / torso / arm / legL / legR) | 188 / 174 / 116 / 58 / 58 | 328 / 358 / 330 / 90 / 90 | 834 / 1,830 / 276 / 200 / 200 |
| MeshParts | 11 | 11 | 12 (+ the Warhammer's 1) |
| Rest reach (flat, with gear) | 1.85 (1.43 radii) | 4.02 (1.83 radii) | 4.23 (1.06 radii), hammer not counted |
| Posed reach of the weapon (`--check`) | 2.58 out, 5.58 up | 4.76 out, 8.80 up | 17.08 out, 24.08 up (the hammer) |
| Head rule, worst over the sampled poses | 0.40 hr (112 poses) | 0.40 hr (112) | 0.40 hr (386) |

- **Fodder**: a wiry raider in a sleeveless tunic with a ragged hem (the cloth, red-brown) and cloth leg wraps (the
  leg shade), rawhide belt, bandolier and foot wraps tied with rope, a fur pauldron, a charcoal war-paint band across
  white eyes, a dark mane with an ochre feather, a one-handed club with flint teeth.
- **Brute**: hunched and wide, a bare barrel chest, a rust kilt with a ragged hem, a rust sash and leg wraps, a fur
  mantle with pale tips, a rawhide belt with a bone skull buckle, a fang necklace, fur boots, an aurochs-skull cap
  whose horns are outside the head sphere (misses by design), a black beard, ochre cheek paint; both hands on a log
  club with rope lashings and bone spikes.
- **Camp Chief, look A**: a bear-skull mask with fangs and eye sockets that glow (hot through every windup, ember once
  enraged), a wolf-pelt hood with ears, a dark fur cloak to the knees with pale tips, bone skulls on the shoulders, a
  bare chest with ochre war paint and a fang necklace, a rope-and-bone amulet ring where the client's charging core
  sits, a wine kilt and sash, fur boots; the L3 Warhammer in his right hand (x2.8, attached at runtime).
- **Look A front**: `RaiderChief_front.png`. **Look B front** (war paint on a bare face, beard, rope brow band, an
  antler crown to 17.3 studs, a lighter fur cloak, a log club with bone spikes): `RaiderChiefB_front.png`, built
  into `assets/build/raider-lookb/` only (3,540 triangles, 11 MeshParts), never merged, never a blueprint (its
  authored arm pose dips the club 0.16 under the floor; the carry pose lifts it).
- **Lineup** `_lineup.png`: the three beside a 5-stud R15 at one scale, at rest and at the end of their first windup's
  coil, then the same at a phone's size 50 studs away (Roblox's 70 degree view on a landscape phone 390 points tall:
  16.7 px a stud at 3x density, and at point size). There the cloth colour is what tells them apart and the windup
  heat reads on all three.

Each strip: rest, two walk frames, the windup (the end of the coil) and the blow of the kind's first attack, seated,
spent; the Chief also the sweep's windup and swing and his enraged look. The scored head is the cyan wire circle,
the drawn head's centre the yellow cross, the offset printed under each frame. The Chief's frames use a **stand-in**:
there is no `chief` kind in ProvingGrounds.json yet, so raiderpose takes the Colossus's numbers with the study's sweep
(arc, range 16, 150 degrees, windup 1.0, recover 1.6) in place of the barrage. The strips read the file: rerun them
once the economy-designer adds `chief`.

## 2. The rig (what W2's client must do), with the numbers

**Pieces.** One prop per kind, folder `Raiders`, five rigid pieces, piece k in `Stage<k>`: 0 head, 1 torso (with the
off arm), 2 weapon arm, 3 left leg, 4 right leg. No pipeline change (blueprint pieces with `stage` k and
`untilStage` k). Each piece is authored in place in the body frame (feet at the origin, front -Z, up +Y, right +X,
1 unit = 1 stud, blueprint scale 1.0), so a template's Stage MeshPart CFrames relative to `Base` are the rest pose
(the weapon kit's "template frame = generator frame" holds). For two-handed weapons (the brute's log) piece 2 holds
both arms; it may then only pitch (a yaw or roll tears the shoulders off). The Chief is one-handed for that reason.
Better rig, if wanted: a 6th piece for the off arm costs blueprint.py's `STAGE_COUNT` clamp (5) for props, the
template's stage count, 7 more uploads and one more MeshPart group per body; not needed for the three.

**Per frame** (raiderpose.rig; all numbers in `RaiderModels.json` `rig`):
1. Inputs are today's: feet `F` (with knock, launch and rise offsets, **without** the lunge thrust), heading `yaw`,
   `twist` (= drawnYaw - yaw), the lean vector, squash, seat (eased with smoothstep), airborne; plus the thrust,
   the walk phase and amplitude, and the arm pose from the arm channel.
2. **Head**: centre at `F + (0, height - headRadius - seatDrop - drop, 0)`, rotation = lean x 0.35 (`headNod`) then
   yaw + twist x 0.5 (`headTurn`), about its own centre. `seatDrop` = height x Theme.COMBAT_REST_DROP x seat; the
   scored head is lowered by the same (the planned server fix), so the seat costs nothing against the rule.
3. **Drop** = torsoLen x (1 - cos |lean|) + torsoLen x (1 - squash) + legLen x (1 - cos |legSwing|) x (1 - seat),
   clamped to +-0.4 x headRadius (`headKeep`); torsoLen = neck height - hip height. A squash over 1 (the slam's rise,
   the call's stretch) lifts the body.
4. **Torso**: rotation = lean (+ walk lean 0.06 x amp + seat lean 0.12 x seat) then yaw + twist, about the neck
   joint, which sits at `F + Ry(yaw + twist) (neck.x, 0, neck.z) + (0, neck.y - seatDrop - drop, 0)`.
5. **Arm**: torso x CF(pivot) x fromEulerAnglesYXZ(pitch, yaw, roll) x CF(-pivot).
6. **Legs**: each from its hip joint (where the torso put it), aimed at the floor spot under its rest hip, moved
   forward by 0.4 x thrust for the lead leg (`stepShare`); a spot out of reach slides toward the point under the
   hip; then the walk swing (+-0.42 rad x amp x sin phase, left +, right -), +0.5 rad airborne (`airTuck`); seated
   the legs blend to pitch pi/2 and splay 0.14 rad. Rotation = Ry(yaw) Rx(beta) Rz(gamma).
7. Each MeshPart's CFrame = CF(F) x pieceCFrame x its template rest CFrame; one BulkMoveTo as today.
8. **Reactions keep today's transform**: knockback, launch, the death fling and topple, a summoned body's rise and
   the vanish pose the rest pose rigidly under today's `rootFrame` (they follow a landed hit; the head rule is for
   poses before one).
9. **Walk cycle**: phase advances 2 pi per (2.4 x legLength) studs of flat travel; amp eases toward
   clamp(pace / (kind speed x 0.5), 0, 1) at the lean rate; beyond 140 studs from the camera amp is 0 (`walkNearStuds`,
   the cost guard); the phase and amp join the "pose changed" test so a resting crowd still costs nothing.
10. **Arm channel** (raiderpose.arm_channel): keys `carry`, `seat`, `slump`, and per attack shape `coil`, `strike`,
    `follow`, each (pitch, yaw, roll). Windup: carry to coil with threatPose's build, then coil to strike with the
    snap (lunge, ring); attack: an arc goes coil to follow with the sweep, a lane goes coil to strike over the first
    quarter and holds, the rest strike to follow with u; recover: from follow (a lane's strike) to
    lerp(carry, slump, slump share) with the settle; seat blends to `seat`; plus the walk swing 0.32 rad x
    `armSwingShare` x amp x sin phase. **A key carries the lean of its moment** (the torso leans about the neck, which
    swings a hanging arm the other way). Keys are linear blends of the three angles.

Today's poses all go through it unchanged (the threatPose port reads every constant from Theme.luau and
CrowdRenderer.luau; a missing one is an error). The head rule then holds by construction: the head never moves
sideways and its drop is clamped. `--check` samples 112 poses per kind, 386 for the Chief (idle, walk, seat, stagger, reel, a
strength-3 flinch, every phase of every attack, enraged or not, walking through a recover, a boss's breath) and finds
0.40 hr at worst for all three; nothing of another piece comes within 0.8 hr of the scored head's centre in any strip frame.

## 3. The colour route in practice

- **Four kit folders, one MeshPart each per stage**: `raider-kit` (gear: palette-textured, never painted),
  `raider-cloth`, `raider-skin`, `raider-glow` (painted). merge_stages makes one MeshPart per kit per stage, so the
  role is the MeshPart's name. The brief named one folder; the other three are its siblings, the only way to get
  separate untextured surfaces without a pipeline change.
- **The client** clears `TextureID` on the painted MeshParts once per clone (or W2 has gen_templates leave it out for
  those three kits: no runtime write) and paints Color and Material exactly as `paint` does today:
  `cloth` = the kind's colour (the torso rule), `clothLeg` = the leg shade (base lerp (20, 20, 24) 0.35, the legs
  rule), `skin` = the kind's skin colour with today's head rule (tinted half as far), `glow` = today's visor rule
  ((28, 30, 36) SmoothPlastic, (255, 140, 40) Neon through windup and blow) held at the enrage glow (255, 170, 70)
  Neon once enraged. The hit flash whitens cloth, legs and skin; the blow turns them Neon; enraged, the base moves
  0.4 toward (255, 60, 40) and the skin half that. Gear is never painted.
- **What the palette holds**: wood, bone, rope, leather, flint, ochre, feathers from `weapon_kit_palette.FOREST`; hide
  and fur from the forest track's `forest_palette.HIDE` (it appeared during this run; both imported, never
  redefined); hair and eyes in `RAIDER`; one fallback swatch per painted kit in `PAINT` (cloth a flat light grey, so
  an unpainted template reads "unpainted"). The proposed skin is (196, 148, 112) per kind in config.
- **Surface share**: the cloth (body + legs) and the skin together cover most of each silhouette, so the flash and the
  heat read on the whole figure, as on today's body. The 50-stud phone row shows the cloth colours still separate.

## 4. The proposed config (`tools/assets/out/RaiderModels.json`, written by the generator)

```
{ "version": 1, "folder": "Raiders",
  "rig": { "headKeep": 0.4, "headNod": 0.35, "headTurn": 0.5, "legSwing": 0.42, "armSwing": 0.32, "walkLean": 0.06,
           "strideLegs": 2.4, "walkFullShare": 0.5, "walkNearStuds": 140, "stepShare": 0.4, "seatLean": 0.12,
           "seatSplay": 0.14, "airTuck": 0.5 },
  "kinds": { "<crowd kind>": {
      "model": "RaiderFodder", "height": 5, "radius": 1.3, "headRadius": 0.7,   // the hit shapes it was built on (checked)
      "skin": [196, 148, 112],
      "pieces": [ { "name": "head", "stage": 0, "pivot": [x, y, z],
                    "parts": { "raider-skin": "skin", "raider-kit": "gear" },     // MeshPart name -> role
                    "triangles": 188, "bounds": { "min": [...], "max": [...] } }, ... five ... ],
      "points": { "head", "headTop", "neck", "shoulder" (the arm pivot), "hipL", "hipR", "hand", "tip", "chest",
                  "core" (boss), "handL", "shoulderL" ... },                     // body frame, studs
      "legLength": 2.02, "leadLeg": "legL", "armSwingShare": 1.0,
      "arm": { "carry": [p, y, r], "seat": [...], "slump": [...], "shapes": { "lunge": { "coil", "strike", "follow" } } },
      "headMeshCentre": [...], "bounds": { "min", "max", "size" }, "reach": 1.853, "reachRadii": 1.425,
      "triangles": 594, "meshParts": 11,
      "hold": { "model": "Warhammer", "folder": "Weapons", "scale": 2.8, "piece": "arm", "grip": [...],
                "right": [...], "up": [...] },                                   // Chief: CFrame.fromMatrix(grip, right, up)
      "notes": { "headShift": [...] } } } }
```
The pivots are the joints (`head` centre, `neck`, `shoulder`, `hipL`, `hipR`), so the client never measures a model.
`reach` is the rest pose's flat extent with gear; `--check` prints the posed weapon reach, which check_levels' sight
gate needs in place of the 1.151-radii torso half-diagonal. Each `<Model>.rig.json` beside the gear GLBs is the same
record. W2 decides where the file lives; a `weapon_frames.py`-style copier with a `--check` against the merge
sidecars is the obvious route.

## 5. Uploads for all seven

Five stage uploads per kind: **35** model uploads (each stage GLB holds 2 or 3 meshes and the tiny palette images of
its kits, which Roblox stores once), then **one harvest paste** with 35 stage records, shareable with the forest's
paste. The Warhammer is the L3 template (no upload). Look B is never uploaded. Display names fit the 50-character cap
with the long prefix (`EraCityTycoon_Prop_Raiders_RaiderArmoured_S4` is 44). Sharing leg stages between the 5-stud
kinds would save about 6 uploads at the cost of a per-piece model field in config; not worth it.

Triangles at Normal with every resident drawn: about **81k** (30 fodder x 594, 26 brutes x 1,196, the Chief with his
hammer 6,482, and the four to come at budget: 20 slingers x 800, 8 elites x 1,000, 2 lobbers x 800), plus 14k when
the tents' stock is out. The study estimated 75k.

## 6. Step 2: the other four looks

Three Opus builders with disjoint generator files (`tools/assets/raider_kit_<group>.py` registering into
`raider_kit.MODELS`, as the weapon kit's levels do), each rendering its own strips and the shared lineup:
- **A, the throwers (slinger 800, lobber 800)**, 5 tall, keepAway (they walk through their recover, so the walk cycle
  under a slump matters). Slinger: yellow cloth, a leather sling on cords in the right hand, light kit; the lit orb
  cue stays a client cue at `points.hand`. Lobber (radius 1.4): green cloth, a firepot satchel on the back with
  pots and rope, an overhand throw; the lit round stays a cue at a new `points.pack`. The sling's whirl needs one
  new arm-channel rule (an oscillation key, e.g. `whirl` {hz, yaw}), which belongs in raiderpose: route it through
  the kit lead.
- **B, the marksman (800)**, 5.4 tall: a heavy crossbow held two-handed (pitch-only: raise to aim, hold through the
  line's lock, recoil), a hood and a quiver, purple cloth; the lit tip stays a cue at `points.tip` (rename `muzzle`
  if W2 prefers).
- **C, the plated elite (1,000 with the plate)**, 6.5 tall, steel-blue cloth, an arc attack (keys like the Chief's
  sweep). Its lashed-plank plates must disappear on the break, so they are their own MeshPart: a fifth kit
  `raider-plate`, role `plate`, shown while the wire says plated, glinting white on a turned hit and bursting on the
  break (today's shell rule moved onto the planks; untextured and painted plank-brown so the glint is certain).
  This is the one new client role in step 2.
- **Kit lead**: the shared parts (raiderpose rules, the plate role, the whirl), the lineup of all seven, the sheet.

## 7. Risks, said plainly

1. **Parts per body**: 11-12 MeshParts against today's 4 Parts plus cues, so about 950 MeshParts for Normal's 86
   residents, and a walking body moves all of them every frame. Same-mesh MeshParts instance, but phone frame time
   is unmeasured; only Ben can measure it.
2. **The head rule leans on the server's seated hit shapes** (the PLAN fix): without it the seated drawn head is
   0.35 x height under the scored head, as today.
3. **The boss core cue** (a 2.4-stud ball swelling to 4.2 through a windup, 1.35x enraged) dominates the Chief's
   chest in every frame; the amulet ring is 2.56 across. Recommend a model-sized core from config (about 1.6).
4. **The Chief's hammer reaches 17 studs flat in the sweep and 24 up in the slam's windup.** The stand-in sweep is
   range 16, so the drawn hammer overreaches it by a stud: the economy-designer's numbers and the arm keys should
   agree, and camp C's sight gate must read the posed reach, not the torso.
5. **Feet float** for the 0.16 s of a strength-3 flinch (0.8 / 1.6 / 3.0 studs) and the Chief rises 0.6 in the slam's
   windup (up on his toes, as today's stretch). Both follow from the head rule; neither is aimable.
6. **The pose maths are hand-ported**: the constants are read from the Luau, the logic is not machine-checked.
   CrowdRenderer has 154 of 180 top-level locals: W2 should put the pose and rig maths in a pure Luau module and
   mirror it like check_mirror.
7. **The fodder is plainer than the brute and the Chief** at 594 triangles; if Ben wants it as rich, its budget needs
   about 800 (a hood, a ragged cloak, a second weapon).
8. **Warm colours**: red-brown, rust and wine cloth sit near the skin's hue; they separate by value and saturation.
   The forest palette's fur is close to the forest floor (contrast 1.18-1.30); pale hide tips carry its edge.
9. **The `chief` kind** is not in ProvingGrounds.json yet: the Chief's strips are the stand-in until it is.
10. **Markers**: the plate bar and CampFx's "!" hang on a head part; a model needs a small invisible anchor Part at
    `points.head` riding the head piece (or an Attachment at `headTop`), so both keep working unchanged.

## 8. What fought me

- merge_stages joins a stage into one MeshPart per kit, so a role needs its own kit folder (four folders, not one).
- blueprint.py clamps a stage to 0..4: five pieces at most without a pipeline change.
- weapon_kit_mesh.Mesh checks colours against its module's palette: subclassed (`RMesh`) with a per-kit check.
- The lean turns the torso, so a hanging arm swings the other way: the first arm keys left the fodder's club at his
  hip on the blow and buried the Chief's hammer in the ground. Keys now carry the lean.
- A rigid wrist: a hammer at right angles to the forearm cannot both drag and slam; nearly in line (18 degrees) it
  can. Two arms in one piece can only pitch: the first two-handed Chief could not sweep.
- A skull's bounding box with a nose or a mane in it sat 0.07-0.15 hr off the scored head: `centre_head` moves each
  head piece so the skull is exactly on it.
- The Bash tool rejected heredocs of Python with nested quotes twice; scripts went to the scratchpad instead.
- `tools/assets/forest_palette.py` appeared mid-run: hide and fur were switched to it.

## 9. Files (all new, LF)

- `tools/assets/raider_kit.py`, `tools/assets/raider_kit_mesh.py`, `tools/assets/raider_kit_palette.py`
- `tools/testfit/raiderpose.py`, `tools/testfit/raiderview.py`
- `tools/testfit/blueprints/_props/Raiders/RaiderFodder.json`, `RaiderBrute.json`, `RaiderChief.json` (generated)
- `tools/assets/out/RaiderModels.json` (generated, the proposed config)
- `tools/testfit/README.md`: a "raider kit" section appended
- gitignored: GLBs in `assets/kenney3d/raider-{kit,cloth,skin,glow}/`, merged stages in
  `assets/build/stages/_props/Raiders/`, look B in `assets/build/raider-lookb/`, pictures in
  `assets/testfit/out/Raiders/`.
