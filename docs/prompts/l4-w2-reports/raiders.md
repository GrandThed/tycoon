# L4 W2, track R2: the other four raiders (raider kit builder's report)

Worktree `tycoon-p5`, branch `l4-real-forest`. Nothing committed, nothing uploaded; no `upload_*`, `harvest.py` or
`gen_templates.py` run (not even `--dry-run`); `merge_stages.py --props --era Raiders` run for measuring only, with the
`raider-*` palette caches deleted before every merge. Only my own files were written (list in section 9). Every picture
below was judged with the Read tool and fixed where it looked wrong (section 8 says what that changed).

**Verdicts.** `py tools/testfit/raiderpose.py --check` exits 0: head rule PASS for all seven (worst 0.400 head radii, the
reel), the new in-head rule PASS for all seven, and the config's `posedReach` matches a fresh measure on the exported GLBs
for all seven. `merge_stages.py --props --era Raiders` (all seven): `done: 7 blueprint(s), 0 with problems`; per-stage
triangle sums equal the generator's. Look B still builds (3,540 triangles, never merged).

## 1. Per kind

All pictures in `assets/testfit/out/Raiders/`. Triangles include gear (and the plate); the Chief's Warhammer (3,142) is
attached at runtime and not counted. Posed reach = every vertex of every piece (and the Chief's hammer) over every sampled
pose before a hit (113 poses, the Chief 387), studs from the body's axis and up from its feet.

| Kind (model) | Strip | Tris (budget) | MeshParts | Drawn height | Posed reach out / up | With its lit cue |
|---|---|---|---|---|---|---|
| fodder (`RaiderFodder`) | `RaiderFodder_strip.png` | 792 (800, was 594) | 11 | 5.16 (feather) | 2.66 / 5.58 | - |
| slinger (`RaiderSlinger`) | `RaiderSlinger_strip.png` | 778 (800) | 12 | 4.99 | 3.21 / 5.46 | 4.51 / 6.77 |
| marksman (`RaiderMarksman`) | `RaiderMarksman_strip.png` | 784 (800) | 13 | 5.41 | 2.60 / 5.41 | 3.18 / 5.41 |
| lobber (`RaiderLobber`) | `RaiderLobber_strip.png` | 794 (800) | 12 | 4.99 | 2.13 / 4.99 | 2.34 / 5.32 |
| plated elite (`RaiderArmoured`, kind `armoured`) | `RaiderArmoured_strip.png`, `RaiderArmoured_plate.png` | 998 (1,000) | 13 | 6.68 (crest) | 5.41 / 6.68 | - |
| brute (`RaiderBrute`, unchanged) | `RaiderBrute_strip.png` | 1,196 (1,200) | 11 | 8.2 (horns) | 4.77 / 8.91 | - |
| Camp Chief (`RaiderChief`) | `RaiderChief_strip.png`, `RaiderChief_front.png` | 3,340 (4,000) | 12 (+1 hammer) | 14.66 (ears) | 17.10 / 24.13 | 17.10 / 24.13 |

Per piece (head / torso / arm / legL / legR): fodder 200 / 304 / 152 / 68 / 68; slinger 212 / 286 / 144 / 68 / 68;
marksman 216 / 202 / 230 / 68 / 68; lobber 202 / 378 / 78 / 68 / 68; elite 196 / 518 (plate included) / 132 / 76 / 76.

- **Slinger** (yellow): sleeveless tunic and a head wrap with tails in the kind's cloth, a leather sling on two sinew
  cords, a stone bag on the left hip, a bandolier of pouches. The orb rides the sling's pouch: by his knee at rest,
  whirled twice over his right shoulder through the windup, released up and out to his right (beside his head, never in
  front of his face). Strip: rest, walk x2, windup 40 / 80 / 95 % (the whirl), the release, follow-through, seated, spent.
- **Marksman** (purple, the tallest 5-stud raider): a long hooded coat, a quiver of bolts across his back, a heavy
  crossbow (carved stock, rope-lashed prod, drawn string, flint bolt) in both hands. Held across his chest at rest,
  raised level by the moment his line locks, held there through the lock, a kick at the shot. The lit tip rides the bolt
  head. Strip: rest, walk x2, raising (20 %), aimed at the lock, held on the lock (95 %), the shot, follow, seated, spent.
- **Lobber** (green, stocky): a green scarf over nose and mouth and a hide cap with ear flaps, a leather apron below the
  belt, a hide satchel on his back with two fired-clay firepots, the lit round in the satchel's mouth. He reaches back
  over his shoulder to it and hurls overhand. Strip: rest, walk x2, reaching back, the throw, follow-through, seated, spent.
- **Plated elite** (steel blue, 6.5): steel-blue tunic, kilt and sleeves, a hair crest (outside the head sphere: a miss
  by design, as the brute's horns), war paint, fur boots, a long-hafted flint axe swung one-handed (arc keys like the
  Chief's sweep). The plate is lashed planks: chest and back planks, two lashings, plank pauldrons, a plank shield on
  the left forearm. Strip: the usual frames plus the plate glinting, bursting, the reel after it, bare at rest and in
  windup. **Before and after the break**: `RaiderArmoured_plate.png` (front: plated, glint, burst, reel, bare).
- **Fodder to 792** without moving the silhouette Ben approved: a short fur cape on the back, a fang necklace, a bone
  knife in a sheath on the left hip, a second feather, a rope-bound grip and two more flint teeth on the club, a forearm
  wrap, rope at the knees.
- **Chief**: the core at model size (section 4); his carry, charge and slump keys lifted (section 8). Geometry unchanged.

**The overview**: `assets/testfit/out/Raiders/_overview.png`: all seven beside the 5-stud player at rest and in each
kind's own windup (the sling whirling, the crossbow held on the lock, the firepot reached for, the axe, club and hammer
coiled), labelled, then both rows 50 studs away on a phone (16.7 px a stud at 3x, and at point size). At 50 studs the
cloth colours still separate all seven (red, yellow, purple, green, blue, rust, wine) and every windup heats; the lit
cues are drawn as the client will draw them. `_lineup.png` (step 1's three) was re-rendered on the new build.

## 2. New arm rules (numbers the client must follow)

All in `tools/testfit/raiderpose.py` `arm_channel` (the mirror W2's client must equal); `throwShare` is in config `rig`.
1. **Shortest-way blending.** Every key blend goes angle by angle the short way round:
   `a + ((b - a + pi) mod 2pi - pi) * t`. No step-1 key is more than pi from the key it blends with, so their poses are
   unchanged; the lobber needs it (coil pitch -2.8 to strike 2.35 blends over the top through pi).
2. **The throw path** (attack shapes `shot`, `lob`, `line`): in the attack phase, `u < throwShare` (0.35):
   `lerp(coil, strike, u / 0.35)`, else `lerp(strike, follow, (u - 0.35) / 0.65)` (u = the strike's share run).
   Before this, those shapes jumped from coil to strike in one frame.
3. **`whirl`** (the slinger, key set `shapes.shot.whirl = {turns 2, sin [0.45, 0, 0], cos [0, 0, 0.25]}`): in the windup
   the arm adds `build * (sin(t) * sin + (cos(t) - 1) * cos)` per angle, `t = 2pi * turns * u`, `u = age / windupSeconds`,
   `build` = threatPose's (min(u / 0.8, 1) squared). It circles twice and is exactly on its coil at the release.
4. **`steady`** (the marksman, `shapes.line.steady = true`): the keys are world pitches: the final pitch adds the body's
   lean along its facing (`pose.lean`, + forward, in every phase), so the aim stays level while the windup leans him back.
5. **A `line` with a lock is aimed by the lock**: in the windup the arm's build is `min(age / (windup - lockSeconds), 1)`
   squared (the marksman: aimed 0.45 s in, 0.55 s before the hit), not the body's own build.
6. **Cue anchors** (`cue` per kind): the lit piece rides `points[cue.point]` carried by piece `cue.piece`
   (slinger: arm / `pouch`; marksman: arm / `tip`; lobber: torso / `pack`; the Chief: torso / `core`): its CFrame is
   the body's CFrame x that piece's posed CFrame x CFrame.new(point). Sizes stay today's Cues rules except the Chief's.
7. Two-handed pieces (brute, marksman) only pitch; the marksman's piece turns about the middle of the shoulder line.

## 3. The plate role (numbers the client must follow)

- Kit `raider-plate`, role `plate`: one untextured MeshPart, in the plated elite's torso stage (`Stage1`, MeshPart name
  `raider-plate`); clear its TextureID like the other painted roles.
- **Today's shell rule moved onto it** (Cues.Paint's `shell` branch, Theme numbers): while the wire says plated:
  Color `COMBAT_RANGE_PLATE_COLOR` (120, 175, 240), the colour of its bar and its damage numbers, Material
  **SmoothPlastic** (today's shell is Metal: planks; Wood is the Studio alternative to try); a turned hit: WHITE, Neon,
  for `COMBAT_RANGE_CUE_GLINT_SECONDS` (0.1); warded (its guard lives): `COMBAT_RANGE_WARD_COLOR`, ForceField, Size x
  `COMBAT_RANGE_WARD_SHELL_SCALE` (1.14); the break: WHITE, Neon, Size x (1 + `COMBAT_RANGE_CUE_BREAK_GROW` (0.6) x share)
  over `COMBAT_RANGE_CUE_BREAK_SECONDS` (0.3), Transparency = share, then hidden (Transparency 1) for good. "Size" is
  the template MeshPart's own size; Roblox scales a MeshPart about its own centre, so the pauldrons and the shield fly
  out with the burst (the strip shows it).
- It never takes the windup heat or the hit flash (as today's shell); the harness and belt under it are gear and stay.
- The elite gets no other cue (the plain shell part goes, as every plain cue does for a kind with a model).

## 4. The Chief's core at model size

`cue = {"piece": "torso", "point": "core", "size": 1.6, "charged": 2.6}` (today 2.4 swelling to 4.2). 1.6 sits inside the
amulet ring (2.24 across inside); charged to 2.6 it covers the ring. Enraged, the rest size still grows by
`COMBAT_RANGE_ENRAGE_CORE_SCALE` (1.35 -> 2.16) and the charged size is max(2.6, rest). Shown in `RaiderChief_strip.png`
(rest pink, the windup red filling the ring, enraged gold) and in the overview. The client change is W2's ui work.

## 5. Config format changes (`tools/assets/out/RaiderModels.json`, now `version` 2)

- `rig.throwShare` 0.35 (new).
- Per kind: `cue` {piece, point[, size, charged]} (new; absent = no lit piece: fodder, brute, elite); `posedReach`
  {out, outRadii, up, outPose, upPose[, withCue {out, up}]} (new: **camp C's sight gate reads `out` / `up`, or `outRadii`
  in place of the 1.151-radii torso half-diagonal**; `withCue` = the same with the lit piece at its largest: the
  slinger's orb stands 6.77 up); `notes.inHead` (the in-head margin, head radii).
- `arm.shapes.<shape>` may carry `whirl` {turns, sin, cos} and `steady` true.
- `pieces[].parts` may map `raider-plate` -> `plate`. New points: `pouch` (slinger), `pack` (lobber), `tip` on the
  marksman (the bolt head) and the elite (the axe's edge).
- Raider Chief values: carry 0.62 (was 0.48), slump 0.9 (0.75), lane coil 1.1 (0.25), lane strike 1.9 (1.7),
  `armSwingShare` 0 (0.45).
- `raiderpose.py --check` now also reads the GLBs: it fails a stale `posedReach` and anything but the head within 0.75 head
  radii of the scored head (the flinch left out). `--no-extent` runs the head rule alone.

## 6. The final upload list (all seven, one harvest paste)

Seven props, folder `Raiders`, five stages each: **35 stage uploads** (`assets/build/stages/_props/Raiders/<Model>_S0..S4.glb`
from `merge_stages.py --props --era Raiders`, blueprints in `tools/testfit/blueprints/_props/Raiders/`), then one paste
with 35 stage records. Display names `EraCityTycoon_Prop_Raiders_<Model>_S<k>`: longest 44 characters
(`...RaiderArmoured_S4`, `...RaiderMarksman_S4`), all under the 50 cap with the long prefix.
Models: RaiderFodder, RaiderSlinger, RaiderMarksman, RaiderLobber, RaiderArmoured, RaiderBrute, RaiderChief.
**Five kit folders**: `raider-kit` (gear, palette-textured, 25 swatches with the new CLAY), `raider-cloth`, `raider-skin`,
`raider-glow` (the Chief's S0 only), `raider-plate` (RaiderArmoured S1 only); the last four are painted: their TextureID
is cleared (or never written by gen_templates). **For the pipeline engineer (route via the lead)**: `raider-plate` is the
fifth kit; nothing else changed in the route. The Warhammer is the L3 template (no upload); look B is never uploaded.
Run the merge with the `raider-*` palettes deleted first (`raider_kit.py --merge` does it).

## 7. Risks, said plainly

1. **Parts and triangles per camp.** Normal's residents: about 86k triangles (30 fodder x 792, 26 brutes x 1,196, 20
   slingers x 778, 8 elites x 998, 2 lobbers x 794, the Chief with his hammer 6,482), 101k with the tents' stock; Hard
   about 97k residents. About **1,000 MeshParts** for Normal's residents (11-13 a body), every one moved when a body
   walks. Phone frame time is unmeasured: only Ben can measure it.
2. **Four new client code paths** (throw path, whirl, steady, aim by the lock) plus shortest-way blending: hand-ported
   numbers, no machine check yet. The W2 mirror check must cover them.
3. **The marksman's line** is drawn at `COMBAT_RANGE_TELL_LINE_BEAM_HEIGHT` 3 from his centre; his bolt stands about 3.65
   up and 2.2 forward when aimed. W2 may start the beam at `points.tip`. His crossbow cannot be lowered past about 0.45
   rad (a pitch-only piece swings the elbows behind his back), so he carries it across his chest.
4. **While plated, the planks cover the elite's chest**: the windup heat shows on his kilt, sleeves, legs and face, not
   his chest (today's shell does the same). The arc's ground wedge is still his tell. Glint, ward (ForceField) and the
   burst on a MeshPart are unverified in Studio.
5. **The slinger's orb at full size reaches 6.77 up** over his head: any sight gate for a walled camp with slingers must
   read `withCue` (camp C has none).
6. **The Chief is still on the stand-in** (no `chief` kind in ProvingGrounds.json): his posed reach (hammer 17.1 out in
   the sweep, 24.1 up in the slam's windup) is against a sweep of range 16; re-run the generator and the strips once the
   kind exists, then `--check` confirms `posedReach`. The slam still buries the hammer's head about 1.9 studs at impact
   (intended); seated legs dip 0.35-0.54 under the floor and the marksman's coat 0.5 (step 1's seat rule).
7. **The fodder's additions** (cape, knife, necklace) are new to Ben; the silhouette is the one he approved.
8. The Warlord's `guard` kind (range only) has the elite's body (1.7 / 0.8 / 6.5) and a plate: it could reuse
   `RaiderArmoured` with its own cloth colour through a config alias. Not done; not needed for the Forest.
9. A foot still floats up to 1.18 (elite), 1.55 (brute), 2.98 (the Chief) for the 0.16 s of a strength-3 flinch (step 1).

## 8. What fought me (and what the pictures changed)

- The check's idle poses (walk, seat, stagger, reel, flinch, breath) had carried an unposed arm (0, 0, 0) instead of
  the arm channel: the marksman "walked" aimed and the Chief's seat was never really checked. Fixed in `sweep_poses`.
- Measuring every vertex found the Chief's dragged hammer sinking 1.7 to 4.6 studs into the ground walking (its walk
  swing), charging (leaning 0.5 into a hanging hammer) and slumping: keys lifted, walk swing off (section 5).
- `steady` was first written with the wrong sign (the crossbow pitched up twice the lean); the strip showed it.
- Shouldered at the cheek, the marksman's lit tip (1.6 across) hid his face for the whole windup: he aims from the chest.
- The slinger's release first put the pouch in front of his face; it now goes up and out to his right.
- The lobber's first coil threw his arm out sideways, not back over his shoulder; the apron covered his green chest.
- The elite's harness showed through the gaps between planks until it followed the torso's curve under them; the
  shield faced sideways (edge-on from the front) until turned toward the front.
- Every new kind came in 5-15 % over budget first; firepots, the crossbow's binding and the planks' tops were trimmed.
- The Bash tool rejects heredocs of Python with nested quotes: edits went through scratchpad scripts.

## 9. Files

New (LF): `tools/assets/raider_kit_throwers.py` (slinger, lobber, the shared `face` and `legs`),
`tools/assets/raider_kit_marksman.py`, `tools/assets/raider_kit_elite.py`; generated
`tools/testfit/blueprints/_props/Raiders/RaiderSlinger.json`, `RaiderMarksman.json`, `RaiderLobber.json`,
`RaiderArmoured.json`; this report.
Changed: `tools/assets/raider_kit.py` (fodder detail, Chief keys and cue, registration, posed reach),
`tools/assets/raider_kit_mesh.py` (plate role, cue, budgets, shared helpers, config v2),
`tools/assets/raider_kit_palette.py` (`raider-plate`, `PAINT.PLATE`, `RAIDER.CLAY`), `tools/testfit/raiderpose.py` (arm
rules, cue sizes, posed extent, in-head gate, frames, idle arm fix), `tools/testfit/raiderview.py` (cues, plate role,
`--pick`, the overview), `tools/testfit/README.md` ("raider kit" section), `tools/assets/out/RaiderModels.json`
(regenerated; the step-1 blueprints came out byte-identical). Gitignored: `assets/kenney3d/raider-{kit,cloth,skin,glow,plate}/`,
`assets/build/stages/_props/Raiders/`, `assets/build/palettes/raider-*`, `assets/testfit/out/Raiders/`.
