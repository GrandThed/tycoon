# L4 study, Part A: the real forest (report)

Study agent, 2026-10-21, worktree `tycoon-p5`, branch `l4-real-forest` (443c704 + the brief). Read-only except
this file. **Measured** = I ran it here (tool and Python named); **read** = taken from code or docs, not run.
Renders and scratch scripts are in the session scratchpad `l4-forest\` folder, not in the repo.

## 1. Forest Road today, as a player sees it

Everything is a plain anchored Part in a flat SmoothPlastic grey, built per run under `Workspace.Level` and
cleared after it: "no mesh, no upload" (`LevelService.luau:4-5`, `:339-453`). The looks are
`Expeditions.json looks` (path 156/158/162, ground 108/110/116, campFloor 134/136/140, wall 84/86/92; colour
only on gate, checkpoint, secret, fire = Neon, tent = Fabric, bramble = LeafyGrass, ice = Ice, water = grey-blue
at transparency 0.2). Nothing in `src/combat` sets Lighting, Atmosphere or a Sky (grep: no match): default
Roblox lighting. The level floats over the void; a fall goes to `killY` −13 and the free rescue
(`Layouts/Levels/ForestRoad.json` `killY`; check_levels "killY -13 is 8-16 studs under").

**Counts (measured, `py tools/check_levels.py`, 3.12, PASS in 28 s):** **252 Parts** of `levels.maxParts` 600
(`Combat.json levels.maxParts`): 62 layout blocks, 136 ice cells, camp A 14 (floor, 6 fence strips: each of the 2
gates cuts its side in two; 3 cover, checkpoint, 2 fire markers, tent marker), camp B 18, camp C 16 (with 2 gates and 4 invisible
barrier boxes), 3 chests + 3 signs. Plus 4 text blocks × 4 faces = 16 SurfaceGuis with a TextLabel each
(`LevelService.luau:287-318`, `CONST.TEXT_FACES :108`). The formula is `check_levels.py:496-523` `part_count`.

| Piece | What it is (ForestRoad.json) | Collides |
|---|---|---|
| Road | 16-stud slabs, look `path`; route 1,079 studs, 826 outside camps; y 0 from the Trailhead to Road4, a +8 climb at Road5 onto the plateau (y 8: A, the AB U-bend, B, the BC U-bend), +4 at RoadBC6 to y 12 (gatehouse, C); one 12-stud gap Road1→Road2 | yes |
| Camps A, B | floors 85×85 and 141×133 at y 8, 4 deep; fence 4 tall × 1 thick (`levels.fenceThickness` 1) cut at 16-stud west/east gates (`LevelGeometry.FenceBoxes :350`); 3 / 5 cover blocks 3.5 tall; markers (checkpoint 2×10×2, fires 3×1×3, tent 10×8×10) | floor, fence, cover yes; markers no (`:1055-1093`) |
| Camp C | floor 115×115 at y 12; fence 64 tall × 2.5 thick; north and east gates (shut at the close); 4 invisible barrier boxes 80 × 8 in the `ArenaBarrier` group, characters only (`BarrierGroups.luau:6-12`, `LevelService.luau:394-404`); gatehouse = 4 wall slabs 76 tall + 2 path floors | gates only while closed; barrier: characters only |
| Lookout | `LookoutLedge` 24×38×14 ground block, top 34 = 26 over Road5; `LookoutSignPad` 10×12×10, top 8 | yes |
| Cave | mouth on Road4 (y 0), tunnel 224 long at y 8, alcove, exit leg, exit; 14 walls 68-88 tall, 7 roofs; 2 `bramble` blocks (react fire; left out when the leader found the tunnel, `LevelGeometry.Pieces :921-933`) | yes |
| Water | CreekUp, Creek, Pond (look `water`, `collide = false` = deep); 136 ice cells 7 × 1.9, hidden and walked through until frozen (`:829-881`); ShrineIsland 16×16 | water no; frozen cells yes |
| Chests, signs | 3 chests 6×4×6 purple; 3 signs + TrailSign, text on 4 faces | chest yes; sign no |
| BendWall | 6×68×74 wall in the AB U-bend | yes |
| Lobby | a separate 48×48 pad at z −340, 3-stud walls, `MAP - press M` sign, SpawnLocation (`Lobby.json`, `LevelService.BuildLobby :515-569`) | yes |

check_levels' own ASCII plan and side view are what the level looks like from above today
(scratch `check_levels.out`, the "PLAN of ForestRoad" block).

## 2. How the enemies see the world

- **The crowd ignores geometry.** "Nothing here yields, raycasts or builds a path: the crowd ignores world
  geometry (ruling 15)" (`CrowdBrain.luau:54`); bodies walk through cover (P4 memory). Sight is distance and cone
  only, through palisade and cover (`CampBrain.Sees :329-355`); `known` = a member within `chaseSight` 40 or a hit
  within 8 s (`:463-490`). Sight through walls is carried "L4 or later" (`PLAN.md:3244`).
- **The world a body may stand in** is its floor's rectangle, or its floor's **region**: a union of flat
  axis-aligned rectangles at one height (`Region.luau:2-6`). Bodies are clamped into it (`Region.Clamp :200`),
  route cell to cell through the overlaps ("doors", `Region.Toward :301`), and a charge or retreat stops at its
  edge (`Region.Runway :267`). The cells must form a **tree** with doors ≥ 2 × widest body + 0.5 = 4.9
  (`Region.Problems :128-173`; check_levels "12 doors for 13 cells"). Forest Road has one region, `plateau`
  (y 8): camp A's and B's whole floor rectangles plus 11 road cells (`sim_range.region_cells :6171-6178`, camp
  floors first). Camp C has no region; its bodies keep to its floor rectangle (the in-play rule).
- **What a fence does for the crowd today: nothing by itself.** The crowd's edge is the floor rectangle; the
  fence Part stands on that edge, and the road cells overlap the floor only inside a gate span, so the doors
  are the gates (check_levels "a cell crosses a camp's fence line only within one of its gate spans"). For
  players the 4-stud fence is a low wall they hop (jump 18) and it stops some arrows.
- **Who can hit whom:** a rusher reaches a player only within `chaseMargin` 2.5 of the region, at most
  `meleeAbove` 7.5 over and `meleeBelow` 1.5 under its floor, judged on the surface last stood on
  (`CampBrain.Melee :420-435`; `Combat.json camps`). A player outside that is unreachable: rushers wait
  `leashSeconds` 3 and walk home, shooters answer within their reach (Ben, §19).

**What a natural barrier must be in data** (rock band, log line, thicket, stream, cliff step):

| Barrier | In the crowd's terms | Code? | What it costs the gates |
|---|---|---|---|
| A. **On a camp's edge**, in place of the fence (rocks, logs, a thicket along the same rectangle, gaps at the gates) | nothing changes: the floor rectangle is still the edge, the gaps are still the doors | none: the collider is today's fence strip (4 × 1), the look is dressing | none beyond a re-run; the fence's height stays ≤ 4 (below) |
| B. **Along the road** (thicket, cliff step, a stream beside it) | the road cells already end there; the barrier only has to stop *players* | small: a block flag that builds an invisible character-only wall (the `ArenaBarrier` group exists) | movement gates must treat it as a wall (hops, lifts, sneak, unclimbable lists); sight is unchanged (rays pass) |
| C. **Inside a camp** (a log line or rock band splitting the clearing, a stepped outline) | the camp's floor becomes several cells; the barrier is a gap between them with one door | **yes**: today a camp floor is ONE cell (`region_cells :6175`, `StageFlow regionCells :679-689`), and InPlay, posts, tent ring, density, bandMin, the floor Part all read that one rectangle | CampBrain, StageFlow, Region users, `sim_range` mirror, `check_levels`, `stage_mirror.luau`, harness tests, new `mutate.py` entries (a full run is about 2 h) |
| D. **An island** (a rock the crowd walks round, a loop path) | two ways round = a cycle | **yes**, and the tree rule refuses it today (`Region.Problems :166-171`) | as C, plus re-proving every door route |
| E. **A stream across the road** | a gap in the region, a bridge = the door; deep water as today | none if the bridge is a cell | a shallow stream a player stands in but bodies cannot enter is a perch (> 2.5 off the region) |

**Two height rules every collidable piece of scenery must keep** (they bind the dressing, not only barriers):
inside an open camp a standable top is ≤ 3.5 (`check_levels.py:181 COVER_MAX`), and `meleeAbove` must lie in
[max(3.5, fence) + 3, brute lane 5 − 0.5 + 3] = [7, 7.5] (check_levels output, scratch `check_levels.out` line 85), so **a fence or
barrier on an open camp's edge is at most 4.5 tall**; anywhere near the region a top is either within a
rusher's reach, or unclimbable (≥ 43 over every surface within 49.3, check_levels "unclimbable wall"), or it is a
new R8 sniper spot that must be rated. **Nothing collidable between about 5 and 43 studs high.** Everything
else must be walk-through dressing (`CanCollide`/`CanQuery`/`CanTouch` false), as in the city (M9 ruling).

**The forest floor itself is the biggest trap.** Today every surface is a listed block over the void, and
every gate (route, sneak, hops, lifts, perches, the walled camp's sight, deep water) proves the layout on that
assumption. If the ground beside the road becomes walkable, every metre of it is an escape the crowd cannot
follow and a candidate perch. So the visible forest floor must be **unreachable**: beyond an invisible
character-only wall at the tree line (barrier kind B), or below a drop to `killY`. The dense trees and
thickets at that line are what sells the wall to the eye.

## 3. The sniper perches

`SNIPER_KNOWN_LIMIT_L4` (`tools/sim_range.py:7226-7229`) = Normal: LookoutLedge, Secret_lookout; Hard:
LookoutLedge, LookoutSignPad, Secret_lookout. The gate is `r8_gate` (`:10882-10904`): every spot must earn less
cash **and** less Timber a minute than the mission player on the same seeds, at the proving gear and with only
the bow at T4 (L3-26). The spot list is `check_levels.sniper_spots` (`:2644-2708`): a standable top no rusher
reaches (`CampBrain.Melee` false), within the longest ownable bow range (110) of a region cell, that sees one.

| Spot | Where | Why it out-earns (read: BALANCE.md :4990-5011, :6313-6333) |
|---|---|---|
| LookoutLedge | top 34, 26 over Road5, **0.0 off the region** (its south face is Road5's north edge) | from 26 up the 4-stud fence hides nothing: he sees camp A's fire circles and watch line at rest and the Longbow's pierce 5 kills 29-31 residents in 11 s with no hit taken (Normal ×1.0-1.4); with the bow at T4, ×3.6 on Hard |
| Secret_lookout | the chest on that ledge, top 38 | the same view, 4 higher: ×1.66 Normal, ×3.6-4.4 Hard (bow T4) |
| LookoutSignPad | top 8, its west 4 studs off the region cell (pad x −306..−296, cell x −302..−296) | 3.0 off the region, so rushers cannot reach him on the plateau's own height; ×1.8 on Hard with the bow at T4 |

The levers already tried were data (moving the watch group, `sightAbove`); none worked, because the ledge sits
on the region's edge: no wall can stand between it and Road5 without blocking the road. **What any re-placed
perch needs for R8 to pass:** be beyond the bow's 110 of every region cell, or have an unclimbable wall (look
`wall`/`bramble`, from under both feet + 3 to over both heads + 6, `check_levels.sight_blockers :2529-2537`)
between it and every cell. A tree canopy or a low rock does nothing in the sight model, and nothing in the game
either unless it is a colliding Part (shots are server raycasts). The bow-T4 rows are structural: "a ×6.74 bow
against a ×1.5 sword out-earns from any perch that sees a camp" (BALANCE :6327-6328).

**Measured on paper** (`perch_variant.py` in scratch: check_levels' own gates on an in-memory copy of the layout,
3.12, nothing written to the repo):

| Variant | Result |
|---|---|
| V1: ledge behind the cave mouth's west wall (x −366..−342, z −80..−66, top 26 over Road4), pad dropped | the three spots are gone (the 88-tall wall hides every cell), **but** 9 FAILs: the "shooters answer high ground" gate (a top within 120 of the region must lie within 32 of it, `check_levels.out` line 88) and L2-18b/c (CaveTunnel is 6 studs away through the wall; the lift model ignores the wall) |
| V2: the same ledge 10 studs nearer the road | the ledge is a sniper spot again (it sees round the wall's south end) |
| **V3: the lookout at the trailhead** (ledge x −458..−434, z −40..−26, top 26 over Road1; chest on it; sign on Road1; LookoutSignPad block and cell dropped) | **every gate passes but the four pinned sniper lists**, which now hold only spots that pass R8 today (Road2-4, RoadBC5-6, the gatehouse, ShrineSignPad; + Creek and the cave mouths in their variants). The ledge is 132 from the region, beyond the bow and `dormantRadius`; L2-18a-d pass ("closest call: Trailhead, 5 studs short") |

So **V3 empties `SNIPER_KNOWN_LIMIT_L4` structurally**, with no code change. Still owed before it ships:
`sim_range.py --check` (about 14 min, 3.12) to re-rate the remaining spots and the clock, the pinned lists in
`check_levels.EXPECTED` and its mutants, and the harness tests that read the lookout from the layout
(`tests_l2.luau:721`). What it costs Ben's picture: the Flamethrower chest is now at the start, and the
cave's bramble mouth is no longer "under the lookout" (his W2 pick); the chain (Double Jump → lookout →
Flamethrower → brambles) is unchanged. That is a decision for him (§7, D2).

**The rule for every new piece of the real forest:** a standable top more than 2.5 off a region cell is a new
spot whatever its height, and is rated; keep scenery near the region walk-through, or the region's edge
walled for players (kind B).

## 4. Scenery routes, compared

Facts that bind every route: the level is rebuilt per run and must look identical to its collision; the
combat place already carries every prop template, Village's woods included (`combat.project.json:14-20`
maps `templates/_props` into `ReplicatedStorage.Assets.Props`), but not `templates/_world`
(`default.project.json:41` has World, the combat project does not); `StreamingEnabled` is false
(`combat.project.json:51`); the client dressing code (`src/client/City/PropFactory.luau`, runtime
`Model:ScaleTo` at `:284-288`) lives in the hub's client tree, not the combat one.

| | (a) Baked meshes, one generator (Valley) | (b) Smooth Terrain written by code | (c) Kit props placed from data |
|---|---|---|---|
| Look | organic and unified; the approved Valley style (generated pine 28 tris, round tree 48, `valleyprops.py:24-33`) | realistic PBR materials (grass, rock, mud): clashes with every Kenney/Valley piece; trees still need props | Kenney low-poly; reads as camps in a forest at the player's eye (renders, §6); **edges stay rectangular** from above |
| Collision | none; today's Parts stay the only collision (the Valley's rule) | terrain collides with players, rays and the camera, and no gate models it | none (walk-through, as the city's M9 rule) |
| The crowd | unaffected | unaffected, but a terrain bump under a camp floor puts feet off the crowd's flat floor | unaffected |
| Water | a translucent sheet over a bed, deep water stays a no-collision Part | Terrain water **swims**: the deep-water rule (fall to `killY`, rescue) and the ice cells break | unaffected |
| Phones | triangles fully controlled; ≤ 20,000 a mesh (`valley.py:56`), coarse culling | unmeasured; terrain LOD, grass decoration; per-run write and replication of the voxels to every client unmeasured | instancing per mesh id; but thousands of client Instances (the proof: 3,019 props; a template is a Model, a Base, a Stage0 and 1-3 MeshParts, so about 12k Instances) |
| Uploads / pastes | every mesh + a palette, **one paste per bake**; any layout move re-bakes (`planHash`) | none | Village woods: 0. New pieces (~25 nature-kit + ~10 generated): ~35 uploads, **one paste** |
| Later levels | the machinery (`wgeom`, `glbtools`, `upload_world.py`, harvest `worldMesh`) is reused; the art code is new each time | code reused, look unsuited to a castle | best: `castle-kit` exists locally; same placement code, new data |

**Terrain is not recommended:** it swims, it collides where no gate looks, it clashes with the style, and the
±1,024-stud wire (`check_levels.py:164`) puts every level near the origin, so it would be written and cleared
per run (cost unmeasured; Studio only).

**Recommended: a mix.** (c) for trees, rocks, logs, tents, fires and camp clutter, placed by a client
controller from a dressing file per level (the M9 pattern: client-side, walk-through, no remote); the mass of
the forest from **generated** low-poly trees (28-48 tris) rather than Kenney's 114-206; (a) only for what a
player stands on and the tall walls: baked planar-UV ground skins for the road and camp floors (the city's
lesson: overlapping textured Parts z-fight, and Forest Road's road blocks **overlap at every corner**, e.g.
Road2 x −424..−340 and Road3 x −356..−340 share z −8..8), and cliff skins over the cave ridge, BendWall, the
gatehouse and camp C's wall. The cheaper alternative for the ground is Roblox materials on the collision
Parts themselves, after cutting the road blocks to abut: zero uploads, but blocky edges.

## 5. Generated pieces and budgets

- **nature-kit has more than expected** (measured, `tris.py` on the GLB JSON): tents (`tent_detailedOpen`
  232 tris, `tent_smallOpen` 224), campfires (112-264), logs and stacks (96-310), stumps, rocks (72-172),
  cliffs (`cliff_large_rock` 32), mushrooms, moss, bridges, tall pines (134-166). **Its colours are a teal and
  orange cartoon palette** (`leafsDark` baseColorFactor 0.169/0.651/0.667, `dirt` 0.886/0.514/0.341), rendered
  teal in `forest_campA_kitcolours.png`. Nothing in `merge_stages.py`/`palette.py` recolours a kit piece, so a
  forest palette means a generated kit or a new recolour feature (and the palette-cache trap, memory
  orbital-dressing). The Valley palette (`Valley.plan.json palette`: pine 44/112/78, trunk 104/78/56, rock
  144/138/132, dirtrim 126/100/72) fits a forest; the renders use it.
- **Missing, to generate** (`tools/assets/<x>_kit.py`, colour-only materials through `palette.py`, testfit
  strips to Ben before upload): the mass-forest pine and round tree, a cliff skin set, palisade stakes (no kit
  has one), the Chief's tent, raider clutter (hide racks, totems, banners); weapon racks can reuse the 15 L3
  weapon templates already in the place.
- **Heights decide where a piece may go** (§2): a palisade on an open camp's edge collides at ≤ 4 and must
  look it; a tall stockade is either walk-through decoration away from the edge or an unclimbable wall (camp
  C's 64). A 64-stud log wall is 12 players tall: cliffs read better for C, with stakes only at the gatehouse
  mouth. The Chief's tent stands inside C, so it is walk-through (cover in C is ≤ 3.5).
- **Budgets (proposed):** mass tree ≤ 50 tris, road-side hero tree ≤ 200, rock ≤ 150, log ≤ 100, tent ≤ 600,
  palisade segment (8 studs) ≤ 250, cliff skin piece ≤ 300, Chief's tent ≤ 4,000. Level: **≤ 150k placed
  triangles, about 60k in a view**. Basis, not a measurement: the Valley's 131,768 for the whole valley was
  accepted in Studio (memory, M13), Metropolis's full near plot is 61,913. The proof scene at Kenney counts is
  **444,824 triangles in 3,019 props** (171k within 30 studs of walkable ground, 124k at 30-60, 150k beyond):
  the generated 28-48-tri tree is what brings it under budget. Phone frame time has never been measured
  anywhere in this project.

## 6. Pictures for Ben

**Made (about 15 minutes):** `tools/testfit/plotscene.py`, unchanged, renders a scene JSON of boxes and
blueprint models; `scene_forest.py` (scratch) builds one from the shipped layout and level files with scratch
blueprints of single nature-kit pieces: the blocks as boxes, the open camps' fences replaced by log and rock
lines on the same rectangles, tents, fires and clutter, raiders as red body-sized boxes at their Normal posts,
a blue player box, and 2,438 trees on a 10-stud grid wherever nobody walks. A scratch copy of plotscene adds
the Valley recolour above. Each view renders in 18-42 s (Blender 5.2, EEVEE). In the scratch folder:
`forest_top.png`, `forest_campA.png`, `forest_mainB.png`, `forest_gatehouse.png`, `forest_lookout.png`,
`forest_campA_kitcolours.png`. What they show honestly: props alone make A and B read as camps in a forest at
the player's eye; from above the road and camps are still rectangles and the U-bends right angles; the tall
walls (cave ridge, gatehouse, C) are bare grey slabs and dominate those views; the lookout view is the sniper
problem (all of camp A at rest below). Ground and cliffs are boxes, so this is a layout proof, not a look.

**For Ben's gate:** commit this as `tools/testfit/levelrender.py` reading the same dressing file the client
reads (the plotrender pattern: a verbatim mirror), plus generated ground and cliff GLBs through plotscene's
`meshes` entry, and the Valley mock's haze post (`assets/research/2026-10-01-worldmock/wm_post.py`). The Valley
`preview.py` is tied to the plot ring's cache and is not reusable here.

## 7. Decisions for Ben, and risks

**Lead's rulings, not Ben's (they follow from §2 and §3):** every scenery piece is walk-through except the
layout's listed blocks; the forest floor beside the road is closed to players by an invisible character-only
wall at the tree line (a block flag built in the existing `ArenaBarrier` group, rays and camera pass), except
at designed drops (the trailhead gap, the creek, the plateau's lip); 80-tall walls in the U-bends' void would
probably also close the "bend hop" known limit (check_levels `lifts bend`; not measured). The layout is frozen (perches, edges, walls)
before anything is baked, because a re-bake costs a paste.

**D1. How the ground and the walls look** (trees, tents and clutter are props in every option)

```
 A  materials on the blocks      B  baked ground and cliffs
 ^^^^^^^^^^^^^^^^^^^             ^^^^^^^^^^^^^^^^^^^
 ^^ +----------+ ^^              ^^ .-~~~~~~~~-. ^^
 ^^ |   road   | ^^              ^^(    road    )^^
 ^^ +---+  +---+ ^^              ^^ `-._    _.-' ^^
 ^^^^^^ |  | ^^^^^               ^^^^^ \  / ^^^^^
 #######|  |  grey slab walls    /\/\/\/  \ rock face
```
- **A** Roblox materials on the collision Parts (road blocks cut to abut first). 0 ground uploads, any layout
  tweak is free; square edges, slab walls wrapped only by props.
- **B (recommended)** generated planar-UV ground skins (irregular edges, rims) and cliff skins over the tall
  walls, the city's and the Valley's route. About 20-40 meshes, one paste with the props; a layout change after
  it costs a re-bake and a paste.
- **C** one baked landscape like the Valley (trees merged too): fewest Instances; every tweak is a paste.

**D2. Where the lookout goes** (Ben: perches fixed in L4; measured on paper, §3)

```
 a) at the trailhead              b) behind the cave's west wall
       [L] ledge 26 up                 ######## ridge 88
 S==== | ===~gap~===road=====          #[L]#### cave
 trailhead      creek  climb=[A]   ====road=|mouth|==climb==[A]
```
- **a (recommended)** every gate passes but the pinned lists; the Flamethrower chest is found first, the
  bramble mouth is no longer under the lookout. Data only, then `sim_range --check`.
- **b** the lookout stays by the cave; the wall hides camp A, but two gates fail (high-ground reach, the
  tunnel beside it): a `check_levels` rule change and more placement work.

**D3. The camps' edges ("natural barriers instead of fenced squares")**

```
 a) natural edge, same rectangle   b) organic outline, inner barrier
   oo==logs==oo~~rocks~~oo           .-~~rocks~~-.__
 ==    camp        thicket ==      ==(   camp  log  `-.
   oo~~rocks~~oo==logs==oo           `-.__ line  __.-'==
   gaps at the gates = the doors     cells in the crowd's region
```
- **a (recommended for L4)** logs, rocks and thicket on today's rectangles, ≤ 4 studs, gaps where the gates
  are (the renders). No crowd code; reads square from above.
- **b** camp floors become several region cells: code in CampBrain, StageFlow, the Region users, the
  simulators and the gates, plus a `mutate.py` round (about 2 h): a wave of its own, after L4 if he wants it.

**D4. The forest's mood:** A the Valley palette in default light (`forest_campA.png`); **B (recommended)** the
same palette darker with Atmosphere haze, set by code in the dungeon place only (config, judged in Studio);
C Kenney's own teal and orange (`forest_campA_kitcolours.png`). Lighting is default today; every look Ben
approved was judged under it, so B is his call.

**Risks, plainly:**
1. Any collidable piece near the region is a new perch or escape; R8 rates it, and only walk-through dressing
   is free.
2. Phone frame time is unmeasured for the Valley, the cities and the crowd; a forest adds 100-450k triangles
   and thousands of client Instances. Ben's phone pass is the only test.
3. Baked ground locks the layout: freeze it first, or each change is a paste.
4. Textured overlapping blocks z-fight (the city lesson); de-overlap or bake.
5. A forest from the Village's kit family may read "too similar" to the Village or the Valley.
6. Dressing a level at each run start can hitch the client (thousands of clones); spread over frames.
7. Non-colliding trees do not stop the shoulder camera: it passes through trunks at the tree line.
8. One harvest paste for all of L4 (forest, the Chief, raiders) needs Parts A and B planned together.
9. nature-kit recoloured through the pipeline hits the palette-cache trap and has no recolour feature yet.
