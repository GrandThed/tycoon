# L4 W1 track F: the forest on paper (forest kit lead report)

Worktree `tycoon-p5`, branch `l4-real-forest`, 2026-10-21. **Not committed.** Built on the layout with the lookout at the
trailhead (`layout-ready.md`: LookoutLedge x -458..-434, z -40..-26, top 26; LookoutSignPad gone). Numbers are measured
here with the system `py` (3.14) unless stated; renders are Blender 5.2 EEVEE.

## Summary

- **Generator, kit, gate and pictures exist.** `py tools/levels/forest.py build` turns
  `src/shared/Layouts/Levels/ForestRoad.json` into 38 baked meshes (+ a palette and 4 ground textures), 23 client props,
  62 invisible tree-line walls and one data file in about 12 s, byte-identical on a second run. `check` PASSES; each of its
  rules was proved by a mutant (15/15 caught; scratch script `forestlead/mutants.py`, not in the repo).
- **149,761 triangles for the whole level** (budget about 150k). From the worst spot on the route 111,682 are in view and
  90,928 within 250 studs. Looking down the road from either end puts everything in the frustum (the level is long and
  thin), so phone frame time rests on per-part culling plus Roblox's automatic mesh LODs. Unmeasured on a phone.
- **About 220 new Instances** (62 walls, 38 MeshParts, 23 props, 8 fire effects) on top of today's ~250 Parts. Placing
  the 1,121 baked pieces as props instead would add about 4,500 more Instances.
- **Ben picks the mood** from A (default lighting) and B (darker, hazed) for the trailhead, the Main Camp and the clearing.
- **To route:** the 62 walls are new collision (character-only) that check_levels' movement gates (hops, lifts, sneak,
  unclimbable) do not model yet; LevelService must build them and hide the skinned Parts (W2). No file of another owner
  was edited.

## Pictures (assets/testfit/out/Levels/ForestRoad/)

| File | What it shows |
|---|---|
| `plan_top.png` | The whole level from above, north up: road, camps, creek, pond, the lookout rock, the cave ridge, the Chief's rocky hollow, the canopy all round |
| `plan_barriers.png` | The same plan with the 62 invisible tree-line walls in red: open only at the gap, the lookout gully, water and steps |
| `trailhead_A.png`, `trailhead_B.png` | Start of the road: the lookout rock (chest on top) across its gully, the wooden signs, the bridge ahead; moods A and B |
| `gap_A.png` | The trailhead gap: the road ends at the gully; Road2 and the log bridge beyond |
| `lookoutLedge_A.png` | Standing on the lookout: the gully below, creek and bridge, canopy and backdrop hills; no camp in sight |
| `campA_A.png` | Camp A (Pickets) from Road5: stake and log edges, totem gate posts, fires, raiders at their Normal posts, the ridge's cliff |
| `mainCamp_A.png`, `mainCamp_B.png` | The Main Camp from its west gate: log/thicket/rock edges, log-crib cover, the spawn tipi, tents and a watch platform beyond the edge |
| `caveMouth_A.png` | The bramble mouth on Road4 (the bramble Part keeps its LeafyGrass look, which no render can show) with low brambles at its foot |
| `pond_A.png` | The creek and pond from the log bridge, the shrine chest at the far end |
| `shrine_A.png` | The island shrine from the frozen creek (ice not drawn): a ring of standing stones round the chest |
| `gatehouse_A.png` | The climb to the gatehouse: the rock canyon, the skull lintel across its mouth |
| `clearing_A.png`, `clearing_B.png` | Inside the Chief's Clearing: rock walls, the Chief's hall (his point just inside its porch), log-crib cover, skull poles and banners |
| `kit_sheet.png` | Every forest-kit piece from the front with its triangle count |

Raiders are boxes in each kind's colour and size (ProvingGrounds.json crowd.kinds) at their Normal posts; the player is a
5-stud blocky figure; every eye view is the game's shoulder camera (defaultZoom 11, shoulderOffset, vertical FOV 72).

## Counts

**Triangles by group** (whole level 149,761): forest pieces baked into `Dress_*` 78,718; rock faces, boulders and the
firs on the ridge 20,642; canopy 19,556; ground heightfield (floor, slopes, gully, banks, the massif) 12,880; road, rim,
camp and cave skins 8,112; cover cribs, bridge deck, lintel 3,980; backdrop hills 768; props 5,377.

**In view** (`py tools/testfit/levelrender.py --counts`; a MeshPart draws all or nothing; "within 250" keeps only parts
whose box lies within 250 studs of the camera, a stand-in for LOD):

| View | In view | Within 250 |
|---|---|---|
| trailhead | 149,761 | 71,465 |
| lookoutLedge | 149,761 | 71,741 |
| campA | 136,220 | 75,358 |
| mainCamp | 99,686 | 63,668 |
| caveMouth | 89,130 | 53,570 |
| pond | 55,089 | 54,738 |
| shrine | 29,063 | 28,712 |
| gap | 149,761 | 71,949 |
| gatehouse | 50,926 | 50,926 |
| clearing | 56,497 | 56,080 |
| worst spot on the route | 111,682 | 90,928 (feet -12, 8, -44, facing 135 degrees: the Main Camp's west gate) |

**Instances** (estimate; W2 decides the tree): 62 wall Parts + 38 MeshParts + 23 props x ~4 (Model, Base, Stage0,
MeshPart) + 8 fires x ~3 (Attachment, emitter, light) = about 220 new. `levels.maxParts` 600: 252 + 62 walls = 314 if the
walls count as Parts.

## Pieces made (tools/assets/forest_kit.py, triangles)

| Role | Pieces |
|---|---|
| tree (mass) | FirMassA 38, FirMassB 40, SnagA 47, SnagB 47 |
| hero (near the road) | FirHeroA 120, FirHeroB 104, Broadleaf 186 |
| under | Thicket 78, Bush 60, BushLarge 60, Bramble 112, Fern 28, Mushrooms 54, Stump 55, StumpMossy 75 |
| rock | RockA 20, RockB 40, RockSmall 20, StandingStone 13 |
| edge (<= 4.0 tall) | EdgeLogs 132, EdgeStakes 116, EdgeRocks 100, EdgeThicket 78 |
| clutter (<= 4.0 tall) | Campfire 276, HideRack 110, WeaponRack 106, Firewood 108, Sacks 90, BonePile 160, SkullPole 54, LeanTo 62, Bedroll 40, LogSeat 20 |
| outside (beyond the walls) | HideTent 102, GatePost 130, Banner 56, Watchtower 356 |
| tent (inside its 10 x 8 x 10 marker) | SpawnTent 208 (a hide tipi, door toward the camp, quarter turns only) |
| chief (walk-through) | ChiefTent 1,137 (placed at 1.25: a striped hide hall, tusk arch, red banners, skull lintel, fur seat) |

Generated in the level, not kit pieces: cover cribs sized to each cover box (top at 3.5), the log bridge deck over the
creek, the gatehouse lintel, faceted rock over every tall wall, the canopy, the backdrop hills. No nature-kit piece is used
(its teal-and-orange palette cannot be recoloured, and the Village wears it). Colours are `tools/assets/forest_palette.py`
(ground, foliage, bark, rock, hide); the camp's wood, bone, rope, flint and ochre are the weapon kit's `FOREST`, the flames
its `FIRE`, by reference.

## The data file (proposed W2 contract): tools/levels/out/ForestRoad.dress.json

Generated, never hand-edited (`check` fails if it differs from a fresh build). 36 KB. W2 decides where the game reads it
(proposal: `src/shared/Config/LevelDress/ForestRoad.json`, which Rojo makes a ModuleScript).

- **Frame:** `"frame": "level"`: Roblox world studs exactly as the layout writes them, Y up. A baked GLB is in that frame
  (1 glTF unit = 1 stud), so its template is placed with its harvested offset and nothing else (the Valley's world route).
- `version`, `level` (`forestRoad`), `layout` (`ForestRoad`), `planHash` (16 hex: sha256 of the layout JSON, the fence
  thickness, the level's stages, the generator's art numbers and version, and every kit piece's GLB bytes; today
  `45565907cbd38bab`), `triangles`.
- `palette` (`palette.png`: 16-px swatches, 8 a row) and `paletteSwatches` (name, sRGB, uv of each); `textures`:
  `{name: {file, tileStuds}}` for `road` (12), `roadRim` (12), `camp` (14), `forestFloor` (16).
- `meshes[]`: `name` (the GLB and template name, at most 24 chars), `look` (`palette`: per-face UVs on the palette;
  `texture`: world-planar UVs u = x / tileStuds, v = z / tileStuds), `texture` (for `texture`), `group` (ground, skin,
  rock, camp, canopy, backdrop, dress), `triangles`, `min`/`max` (world studs). Each is one MeshPart: Anchored,
  CanCollide/CanQuery/CanTouch false, TextureID = the palette or the named texture.
- `props[]`: `piece` (a forest-kit name), `x, y, z` (the piece's bottom centre, studs), `yaw` (degrees about +Y, the
  `CFrame.Angles(0, rad(yaw), 0)` way, in the blueprint frame: front -Z), `scale` (uniform, `Model:ScaleTo`), and tags:
  `camp`, `effect` (`fire`), `marker` (`tent`), `boss` (the boss point the hall stands behind), `with` (a layout block:
  the prop leaves when that block is destroyed; the 12 brambles go with `CaveBrambleW` / `CaveBrambleE`).
  `propPieces`: the four pieces placed as props (Bramble, Campfire, ChiefTent, SpawnTent).
- `effects[]`: `{kind: "fire", x, y, z, camp}`: where W2 attaches a fire (flame particles and a warm PointLight).
- `barriers[]`: `{name, x, y, z, sx, sy, sz, group: "ArenaBarrier", side, edge: [line, from, to]}`: box centre and size in
  world studs; `side` is the walkable edge it closes (north = -Z), `edge` that stretch.
- `hide`: `blocks` (every path, ground and wall block: Transparency 1, collision kept), `camps` (per camp: floor, fence,
  cover, fire markers, tent marker), `keep` (water, ice, bramble, chests, signs, checkpoints, camp C's gates).
- `looks`: proposed Expeditions.json looks for what stays visible: sign Wood (124, 88, 56), bramble LeafyGrass (62, 84,
  34), water (52, 80, 82) at transparency 0.3, gate Wood (104, 74, 50). The renders use them.
- `bakedPieces`: the count of each piece baked into `Dress_*` (a record; nothing to place).

Lifts over a collision top (a skin lies on its hidden Part): forest floor 0.00, rims 0.03, camp floor 0.06, cave floor
0.075, road 0.09, a pillar's top 0.06; the shore 0.06 over the water's top; a kit piece's own floor 0.14.

## The new invisible blocks (barriers)

62 boxes, all character-only (`ArenaBarrier`: rays, shots and the camera pass), from killY - 2 (-15) to 80 over the highest
walkable top within 20 studs, at most `barrier.thickness` (8) deep and cut 0.5 short of any other walkable ground, run on
past their ends by their depth so outer corners close. They stand on every stretch of the walkable whole's outline that no
layout wall already closes (a wall at least 43 over the ground it faces closes it). The walkable whole: path and ground
blocks (the lookout rock too), open camps' floors grown by their fence (a player may still stand on the 4-stud fence),
camp C's floor (closed by its own fence and barrier), water, and the **designed drops** the generator finds in the
layout: the trailhead gap (x -436..-424, z -8..8, the route's `via: gap`) and the lookout gully (x -458..-436, z -26..-8,
the void between the double-jump ledge and Road1). Open by construction: Road4/Road5 (the climb onto the plateau),
RoadBC5/RoadBC6, every camp gate, the creek and pond (falling in is the deep-water rule; frozen cells are walked on),
Road2 over the creek. `plan_barriers.png` draws them. Coordinates (world studs, x / z / y ranges):

| Name | Closes the | x | z | y |
|---|---|---|---|---|
| TreeLine1 | east edge | -458.0..-450.0 | 8.0..20.0 | -15..80 |
| TreeLine2 | east edge | -436.0..-428.0 | -26.0..-8.0 | -15..106 |
| TreeLine3 | east edge | -434.0..-426.0 | -48.0..-18.0 | -15..106 |
| TreeLine4 | east edge | -390.0..-382.0 | -38.0..-8.0 | -15..80 |
| TreeLine5 | east edge | -390.0..-382.0 | 18.0..96.0 | -15..80 |
| TreeLine6 | east edge | -380.0..-372.0 | 8.0..26.0 | -15..80 |
| TreeLine7 | east edge | -364.0..-356.0 | 88.0..164.0 | -15..80 |
| TreeLine8 | east edge | -340.0..-332.0 | -36.0..16.0 | -15..80 |
| TreeLine9 | east edge | -178.0..-170.0 | -67.5..-52.0 | -15..88 |
| TreeLine10 | east edge | -178.0..-170.0 | -36.0..35.5 | -15..88 |
| TreeLine11 | east edge | -100.0..-92.0 | -36.0..16.0 | -15..88 |
| TreeLine12 | east edge | 72.0..80.0 | -73.5..-52.0 | -15..88 |
| TreeLine13 | east edge | 72.0..80.0 | -36.0..77.5 | -15..88 |
| TreeLine14 | east edge | 128.0..136.0 | -60.0..-8.0 | -15..88 |
| TreeLine15 | east edge | 198.0..206.0 | -36.0..16.0 | -15..88 |
| TreeLine16 | east edge | 387.0..395.0 | -26.0..6.0 | -15..92 |
| TreeLine17 | north edge | -74.0..80.0 | -73.5..-65.5 | -15..88 |
| TreeLine18 | north edge | -273.0..-170.0 | -67.5..-59.5 | -15..88 |
| TreeLine19 | north edge | -364.0..-340.0 | -60.0..-52.0 | -15..80 |
| TreeLine20 | north edge | -328.0..-265.0 | -60.0..-52.0 | -15..88 |
| TreeLine21 | north edge | -178.0..-116.0 | -60.0..-52.0 | -15..88 |
| TreeLine22 | north edge | -74.0..-71.0 | -60.0..-52.0 | -15..88 |
| TreeLine23 | north edge | 72.0..136.0 | -60.0..-52.0 | -15..88 |
| TreeLine24 | north edge | 174.0..264.0 | -60.0..-52.0 | -15..92 |
| TreeLine25 | north edge | -466.0..-426.0 | -48.0..-40.0 | -15..106 |
| TreeLine26 | north edge | -418.0..-382.0 | -38.0..-30.0 | -15..80 |
| TreeLine27 | north edge | 371.0..395.0 | -26.0..-18.0 | -15..92 |
| TreeLine28 | north edge | -490.0..-458.0 | -20.0..-12.0 | -15..106 |
| TreeLine29 | north edge | -436.0..-410.0 | -16.0..-8.0 | -15..106 |
| TreeLine30 | north edge | -390.0..-356.0 | -16.0..-8.0 | -15..80 |
| TreeLine31 | north edge | 128.0..182.0 | -16.0..-8.0 | -15..88 |
| TreeLine32 | north edge | -444.0..-410.0 | 88.0..96.0 | -15..80 |
| TreeLine33 | north edge | -390.0..-356.0 | 88.0..96.0 | -15..80 |
| TreeLine34 | south edge | -340.0..-265.0 | -36.0..-28.0 | -15..88 |
| TreeLine35 | south edge | -178.0..-138.0 | -36.0..-28.0 | -15..88 |
| TreeLine36 | south edge | -100.0..-71.0 | -36.0..-28.0 | -15..88 |
| TreeLine37 | south edge | 72.0..112.0 | -36.0..-28.0 | -15..88 |
| TreeLine38 | south edge | 198.0..264.0 | -36.0..-28.0 | -15..92 |
| TreeLine39 | south edge | -436.0..-426.0 | -26.0..-18.0 | -15..106 |
| TreeLine40 | south edge | 371.0..395.0 | -2.0..6.0 | -15..92 |
| TreeLine41 | south edge | -458.0..-410.0 | 8.0..16.0 | -15..80 |
| TreeLine42 | south edge | -380.0..-332.0 | 8.0..16.0 | -15..80 |
| TreeLine43 | south edge | -146.0..-92.0 | 8.0..16.0 | -15..88 |
| TreeLine44 | south edge | 104.0..206.0 | 8.0..16.0 | -15..88 |
| TreeLine45 | south edge | -490.0..-450.0 | 12.0..20.0 | -15..80 |
| TreeLine46 | south edge | -390.0..-372.0 | 18.0..26.0 | -15..80 |
| TreeLine47 | south edge | -273.0..-170.0 | 27.5..35.5 | -15..88 |
| TreeLine48 | south edge | -79.0..80.0 | 69.5..77.5 | -15..88 |
| TreeLine49 | south edge | -444.0..-356.0 | 156.0..164.0 | -15..80 |
| TreeLine50 | west edge | -490.0..-482.0 | -20.0..20.0 | -15..80 |
| TreeLine51 | west edge | -466.0..-458.0 | -48.0..-12.0 | -15..106 |
| TreeLine52 | west edge | -444.0..-436.0 | 88.0..164.0 | -15..80 |
| TreeLine53 | west edge | -418.0..-410.0 | -38.0..-8.0 | -15..80 |
| TreeLine54 | west edge | -418.0..-410.0 | 8.0..96.0 | -15..80 |
| TreeLine55 | west edge | -364.0..-356.0 | -60.0..-8.0 | -15..80 |
| TreeLine56 | west edge | -273.0..-265.0 | -67.5..-52.0 | -15..88 |
| TreeLine57 | west edge | -273.0..-265.0 | -36.0..35.5 | -15..88 |
| TreeLine58 | west edge | -146.0..-138.0 | -36.0..16.0 | -15..88 |
| TreeLine59 | west edge | -73.5..-71.0 | -68.0..-52.0 | -15..88 |
| TreeLine60 | west edge | -79.0..-71.0 | -36.0..77.5 | -15..88 |
| TreeLine61 | west edge | 104.0..112.0 | -36.0..16.0 | -15..88 |
| TreeLine62 | west edge | 174.0..182.0 | -60.0..-8.0 | -15..88 |

## What W2's game code must do

- **Server, when LevelService builds a run's level** (the walls are collision, so the server owns them):
  build `barriers[]` as anchored, invisible Parts in the `ArenaBarrier` collision group (characters only: the
  `BarrierGroups.luau` group camp C's barrier already uses), and set Transparency 1 on every Part `hide` names (blocks,
  and per camp its floor, fence strips, cover, fire markers, tent marker), collision unchanged. Apply `looks` through
  Expeditions.json. Check `planHash` against the uploaded record (Assets.json, the Valley's pattern); on a mismatch or a
  missing template keep today's grey level (nothing hidden, no dressing) with one warning. The walls count toward
  `levels.maxParts` (252 + 62 = 314 of 600) if LevelService counts them.
- **Client, the same moment** (a LevelDress controller in the combat client; the M9 dressing pattern, no remote): when
  `Workspace.Level` appears, clone each baked mesh template (`meshes[]`, world frame, placed by its harvested offset) and
  each prop (`props[]`: pivot at the bottom centre, `CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)`,
  `ScaleTo(scale)`) into a client folder, everything Anchored and CanCollide/CanQuery/CanTouch false, spread over a few
  frames (38 meshes + 23 props is small; spreading guards the run start). Attach a fire at each `effects[]` entry. Remove
  a prop tagged `with` when its block leaves `Workspace.Level` (the bramble burns). Clear the folder when the level goes.
  Gate nothing on `lowEndDevice` yet: phone numbers first.
- **Mood:** the dungeon place only, config (not code): mood A = today's default Lighting; mood B = an Atmosphere about
  Density 0.38, Offset 0, Haze 1.6, Color (110, 124, 120), Decay (92, 106, 100), Glare 0, with Lighting Brightness about
  1.6 and a cooler OutdoorAmbient. The B renders approximate it with a depth haze; judge it in Studio.
- **Gates (route to the economy designer / check_levels' owner):** the walls must enter check_levels' movement model
  (hops, lifts, the sneak, the unclimbable list) as character-only walls; rays pass, so sight, R8 and the walled-camp
  gate are unaffected. The lookout's double-jump corridor is exactly Road1's span (x -458..-436) between walls at
  x -458 and x -436; the L2-18 lift model should be re-run with them.
- **The props route for the four prop pieces:** one-piece blueprints `_props/Forest/<Piece>.json` (scale 1, the kit is
  in studs), `merge_stages.py --props`, upload, harvest, `gen_templates.py` (which applies the template turn). The baked
  meshes go the Valley's world route (an `upload_levels` copy of `upload_world.py`, harvest kind `worldMesh`, templates
  under `ServerStorage` or `ReplicatedStorage.Assets.Levels.ForestRoad`; the client clones them, so ReplicatedStorage).

## Uploads and the paste

- 38 baked meshes (`assets/build/levels/ForestRoad/*.glb`, 15.7 MB in all, the largest `Dress_4` 1.5 MB, all pass
  `glbtools.roblox_problems`), 1 palette image, 4 ground textures, 4 prop models (Bramble, Campfire, ChiefTent,
  SpawnTent): **47 uploads**. Everything can share the raider track's **one harvest paste**.
- Any later change to the layout, the art numbers or a kit piece changes `planHash`: a re-bake, the changed uploads and
  a paste. The layout is frozen from here.

## Textures needed

Four, 1024 x 1024, opaque RGB, seamless both ways, planar-mapped (`tools/levels/forest_textures.py`, Blender's Python):
`road.png` (packed dark earth, small stones, needles; tile 12), `roadRim.png` (its darker shoulder; also the cave floor),
`camp.png` (trampled earth, straw, wet patches; tile 14), `forestFloor.png` (needles over moss; tile 16). Plus
`palette.png` (the 55 forest swatches, 128 x 112) for every palette mesh. The kit's own palette is built by `palette.py` at
merge time for the four props.

## Risks and what fought me

1. **Draw count:** the whole level is in the frustum from either end of the road (149,761). Smaller chunks help only
   sideways views; Roblox's automatic mesh LODs are the real lever and cannot be measured offline. Ben's phone pass is the
   only test. If it is too heavy: drop the backdrop to a ring of cards, coarsen the canopy (10-stud cells today), make
   the near band's heroes mass firs past 300 studs of the route.
2. **New collision:** 62 walls. They should also close the bend hop (not measured) and every fall into the void beside the road; every movement
   gate must learn them before W2 merges.
3. **Hidden Parts:** a skin that fails to load leaves invisible collision. W2 must hide nothing unless every baked mesh
   of the set loaded (all-or-nothing, back to grey).
4. **What renders cannot show:** Roblox materials (the bramble's LeafyGrass, ice), real lighting and shadows, the haze of
   a real Atmosphere. The cave tunnel's inside (thin rock skins) was not rendered.
5. **Walk-through foliage** at the edge: the shoulder camera passes through bushes and trunks when the player backs into
   the tree line; the trees keep their reach off the walkable ground, so nothing hangs over the road.
6. **Ice:** frozen cells (top at the water's top + 0.2) are not in the coplanar gate; my shore sits at water top + 0.06,
   so they cannot share a plane today.
7. **The spawn tents' door** faces the camp's middle; LevelGeometry.TentDoor sends bodies out toward their posts, not
   always through the door.
8. **The lobby** (z -340) is not dressed; from it the forest's north edge and canopy are about 120 studs away.
9. **Tools:** nature-kit cannot be recoloured, so everything is generated; plotscene's camera clips at 600 studs (the
   renderer overrides it); the first pass at 268k triangles needed a canopy blanket in place of the far trees and a
   faceted cliff skin in place of stacked slabs (which read as masonry); bash heredocs carrying Python with triple quotes
   failed twice, so patches went through scratch files; the level's lookout gap had to be found from the layout (no
   field names it), as did the "designed drops".

## Files (all new, LF)

`tools/assets/forest_palette.py`, `tools/assets/forest_kit.py`, `tools/levels/forest.py`, `tools/levels/forestcheck.py`,
`tools/levels/levelmesh.py`, `tools/levels/forest_textures.py`, `tools/levels/README.md`,
`tools/levels/out/ForestRoad.dress.json`, `tools/testfit/levelrender.py`. Generated, gitignored: the kit GLBs in
`assets/kenney3d/forest-kit/Models/GLB format/`, the bake in `assets/build/levels/ForestRoad/`, the renders.
