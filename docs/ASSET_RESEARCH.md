# Asset Research — handoff (2026-09-15)

Pre-milestone research for replacing the placeholder blocks with Kenney art. **Nothing under
`src/` changed and no milestone was started.** Read this before scoping the assets milestone
(proposed "M7 — Assets"); it records what was decided, what was learned, what Ben rejected, and the
direction he wants instead.

## 1. Decisions so far

| Question | Answer (Ben, 2026-09-15) |
|---|---|
| Scope | All four: slot buildings, VIP skins, ground/roads/props, pass & product icons (+ experience icon/thumbnail) |
| Pipeline | **Scripted**: tools prepare Kenney files, upload them through Open Cloud, write asset ids to config; the server loads them at runtime. No hand-importing in Studio. |
| One static model per slot (the first proposal) | **Rejected.** See §2. |
| Scale | **4 studs per kit unit, toy proportions accepted** (a storey is 4 studs, doors shorter than the player). Fits the 9×9 footprint; the tycoon camera hides it. |
| Assembly | **Merged stages.** Each building stage is merged in Blender into one GLB and uploaded as one mesh, so a building is one MeshPart per stage (~480 uploads over four eras). Runtime piece composition rejected for mobile part count. |
| Prototype | Village tavern, 5 stages, 8→54 pieces, approved by Ben 2026-09-15 (`tools/testfit/`). |

- **2026-09-15, after the Studio check:** Ben confirmed the tower renders textured and the hangar
  is plain grey. Decision: building templates are **generated offline** (`.rbxmx` MeshParts
  referencing the uploaded mesh/texture ids, normalised and pre-scaled, built in by Rojo); no
  runtime `InsertService` and no hand-importing. Material-colour kits get a baked palette
  texture at upload time. The test-fit happens in Blender 5.2 (installed) before anything is uploaded.

## 2. Ben's direction — buildings that grow

> "Use the building blocks of the pack to build something more modular that upgrades from basic
> to imposing while the player improves the building and adds to it."

So a slot is not a single Kenney file. It is **assembled from kit pieces** (walls, floors, roofs,
towers, awnings, banners) and **visibly grows** as the player levels it: a humble first stage that
gains storeys, roofs, towers and details until it looks imposing. This matches the kits well —
most of them are modular construction sets, not finished buildings (§4).

### Hooks the game already has

- Levels run 1–`maxLevel` (100); `milestoneLevels` are `[10, 25, 50, 100]` (`Config/Game.json`),
  plus level 75 for owners of the Legacy perk `milestone75`. Four or five milestones are natural
  **growth stages** (e.g. stage 0 on purchase, one new stage per milestone reached).
- Only `building` slots level up (the level-up ProximityPrompt is added only for them,
  `PlotService.luau:505-519`). `unlock`, `decor` and `monument` slots are bought once, so they need
  a different growth trigger (a monument could grow with the era's completion instead) or stay static.
- Server: `tryLevelUp` (`PlotService.luau:333`) and `crossesMilestone` (`:315`) already know when a
  milestone is crossed. `spawnBuilding` (`:450-520`) clones one template and `PivotTo`s it onto the
  slot's anchor Attachment; it does **no scaling or fitting**. `findTemplate` (`:430-446`) looks in
  `ServerStorage.Assets/<Era>_VIP` (VIP owners) then `<Era>`, else a placeholder Part
  (`layout.placeholderSize` 8×8×8). `RefreshCosmetics` (`:1108`) rebuilds the plot mid-session.
- Client: `PlotVisualsController` reveals a model with `Model:ScaleTo` 0.05→1 (`:122-149`) and plays
  level-up float text / highlight flash / particles (`:169-229`, `onLevelUp` `:265`). Levels never
  change the model today.

### Design questions for the next session (not decided)

1. **Where assembly happens.**
   - *Runtime composition (leading option):* upload each unique piece once, describe every
     building as a blueprint in config JSON (piece id, grid offset, rotation, the stage that adds
     it), and let the server place pieces as stages unlock while the client animates additions.
     Pieces are shared across buildings, so uploads stay in the low hundreds.
   - *Offline merge:* a Python tool merges pieces per stage into one GLB and uploads each stage as
     its own model. Fewer parts at runtime, but roughly 96 × stages uploads and no reuse.
2. **Blueprint format and authoring.** Constants must live in `src/shared/Config/*.json`
   (project rule), so blueprints are JSON. There is no way to preview an assembly without Studio
   yet — either a small local renderer or "upload a stage and look in Studio" is needed for
   iteration.
3. **Normalization.** Pieces need a common grid unit → studs scale, base-centre origins and a
   known front direction per kit (see §4 orientation notes). Real footprint budget per slot is about
   **9–10 studs** (the pad sits 8 studs in front of each anchor; closest anchors are 10 studs apart
   in Boomtown). Growth should go **up**, not out.
4. **Part count on mobile.** 24 buildings × several pieces × stages; decide a per-building piece
   budget or merge static lower stages.
5. **Progression ordering.** Slots in file order should still read humble → grand, and each era's
   monument must be the most imposing thing on the plot.
6. **Existing cosmetics break with real models** and need redesign: Golden Roads only tints
   placeholder Parts (`PlotService.luau:484-489`); Monument Glow sets the PrimaryPart to Neon
   (`:202-228`), which would wash out a textured mesh; placeholders are never era-tinted despite the
   docs saying so (`:478-499`).

## 3. Open Cloud pipeline trial — results

Two models were uploaded on 2026-09-15 as `assetType: "Model"`, content type `model/gltf-binary`:

| | Source | Asset id | Result |
|---|---|---|---|
| A | `castle-kit/tower-square-roof.glb` (textured) | `116756725746364` | Approved in ~12 s |
| B | `space-kit/hangar_largeA.glb` (material colours) | `102687532898806` | Approved in ~11 s, after a fix |

Learned:

- **Accepted Model formats:** `.fbx`, `.gltf`, `.glb`, `.rbxm`, `.rbxmx`; 20 MB per file; models are
  uploaded as packages. No monthly cap is documented for models (audio is 100/month on this
  ID-verified account; 13 used in September). `.env` creator type is `user`.
- **Textures are external.** Newer kits' GLBs reference `Textures/colormap.png` by URI. The trial
  script embeds the PNG into the GLB's BIN chunk before upload (21.6 KB after embedding).
- **Every space-kit GLB is invalid glTF**: node 0 `tmpParent` lists the scene root (node 1) as a
  child. Upload returns a *completed* operation with
  `error: "Failed to parse the uploaded file"` (not an HTTP error). Fixed by dropping `tmpParent`,
  renumbering nodes, removing the unused mesh and `KHR_materials_unlit` declaration and adding
  `byteStride`.
- Space-kit origins are off-centre (hangar origin = bottom-centre − (2, 0, 1.5)); castle-kit origins
  are exactly bottom-centre. glTF colour factors are linear and space-kit materials have
  `metallic = 1`, so colours may render dark or shiny.
- **Verified in Studio on 2026-09-15** (command bar, Edit mode; `[TRIAL]` output saved next to the
  snippet as `studio_check_output.txt`):
  - **Scale: 1 glTF unit = 1 stud.** The tower arrives 1 × 2.01 × 1 studs, the hangar 2 × 1 × 3.
    Kit pieces must be scaled roughly 4–5× to fill a 9–10 stud footprint. `Model:ScaleTo` works
    and scales extents correctly, but baking the scale into the GLB before upload is preferable
    (correct collision, no per-spawn work).
  - **Structure: one MeshPart per glTF primitive**, i.e. per material, wrapped three Models deep
    (`Model` → `Trial_<name>` → `<node>` → MeshPart). The textured castle tower is 1 MeshPart; the
    material-coloured hangar is 9 (3 body + 3 per gate × 2). Material-colour kits therefore explode
    the part count.
  - **Textures survive; material colours do not.** The embedded colormap became its own Image
    asset (`rbxassetid://135388297648400`) set as `MeshPart.TextureID`. Every hangar part is default
    grey `(163,162,165)`, `Plastic`, no `SurfaceAppearance` — glTF `baseColorFactor` is dropped.
    Fix for material-colour kits (space-kit): bake a small palette PNG and remap UVs at upload
    time so they become one textured primitive like the castle kit.
  - **`MeshPart.TextureID` is writable at runtime** (set to `rbxassetid://0` and restored, no
    error), so VIP skins can be a texture swap. `SurfaceAppearance.ColorMap` is also writable.
  - **Pivot:** the outer container's pivot is the bbox centre (half the model would sit
    underground after `PivotTo`); the inner `Trial_*` model's pivot is bottom-centre for the
    castle kit and bottom-centre + (2, 0, 1.5) for the space kit, matching the glTF origins.
    Templates must have their pivot normalised to bottom-centre.
  - Parts arrive `Anchored=false`, `CanCollide=true`, `Material=Plastic`. Anchoring is mandatory.
  - Not yet run: `studio_check_server.luau` (Play, Server view) — confirms a server Script can
    `InsertService:LoadAsset` the ids. Moot if templates are generated offline as `.rbxmx`
    MeshParts referencing the uploaded `MeshId`/`TextureID` and built in by Rojo.

## 4. Kenney kits — what is actually in them

All 14 kits are downloaded and unzipped at `assets/kenney3d/<slug>/` (gitignored; re-download from
`https://kenney.nl/assets/<slug>`). Layout: `Models/GLB format/*.glb` (newer kits) or
`Models/GLTF format/*.glb` (nature-kit, space-kit), plus FBX/OBJ; previews in `Previews/` or
`Isometric/<name>_<dir>.png` (older kits, 512 px).

| Kit (slug) | Models | Character | Useful as building blocks for |
|---|---|---|---|
| `fantasy-town-kit` | 167 | Wall panels, roofs, stairs, banners; lavender stone, red/teal roofs | Village houses, tavern, windmill |
| `castle-kit` | 76 | Tower and wall sections that stack at whole-unit heights; towers 1 × 2.01 × 1; origins bottom-centre; peach stone, blue roofs | Village keep, watchtower, walls |
| `retro-fantasy-kit` | 105 | Pixel-textured blocks; clashes with the other medieval kits | Avoid |
| `nature-kit` | 329 | Older flat style, bright teal greens; campfire, tents, crops, trees, rocks, flowers | Props, small early slots |
| `retro-urban-kit` | 124 | **Only** closed 1×1×1 blocks with one detailed face (door/window/garage), flat roofs, fronts face −Z; gritty brick/green metal | Boomtown stacks, street pieces |
| `modular-buildings` | 108 | Stackable floor blocks 1.0 × 0.62 × 1.0, roof/window/awning parts, plus 7 complete samples (`building-sample-house-a..c`, `building-sample-tower-a..d`, tower-d 1.1 × 3.76 × 1.1); pastel stucco; fronts face +Z | Boomtown growth (floors stack) |
| `city-kit-commercial` | 41 | Complete shops and skyscrapers (`building-skyscraper-d` 1.28 × 5.47 × 1.39) plus detail parts (awnings, overhangs, parasols) | Metropolis |
| `city-kit-industrial` | 37 | Complete industrial buildings, chimneys | Metropolis |
| `city-kit-suburban` | 40 | Complete houses (`building-type-a..u`), planters | Metropolis / Boomtown alternates |
| `city-kit-roads` | 95 | Road tiles, signs, lights, construction pieces; many tiles ~0.02 tall | Roads, props |
| `car-kit` | 50 | Vehicles, ~2.5 units long (2× a retro-urban block) | Vehicles, props |
| `toy-car-kit` | 157 | Toy racers and track; fits no era | Trees only |
| `space-kit` | 153 | Flat white/orange/slate; hangars (only 7 structure-class), corridors, `structure_detailed` stacks, rocket parts that stack on a shared centre (`rocket_baseA` y0, `rocket_fuelB` y1, `rocket_sidesA` y2, `rocket_topB` y3) | Orbital Colony growth, rocket monument |
| `space-station-kit` | 97 | Mostly interior pieces, lavender cast that clashes with space-kit | Avoid |

Style findings per era (from the mapping pass):

- **Village:** fantasy-town + castle-kit share Kenney's modern soft-shaded look and sit together;
  nature-kit only for small pieces; retro-fantasy avoided.
- **Boomtown:** modular-buildings (pastel) and retro-urban (textured brick) clash on large shapes;
  pick one family for buildings. Car-kit and city-kit-roads share the pastel look.
- **Metropolis:** the four City Kits share one muted purple-grey palette; modular-buildings clashes
  with them.
- **Orbital Colony:** space-kit only; station-kit clashes.

**Era kit decision, 2026-09-16 (M8, Ben).** Two Boomtown attempts were authored and judged on
contact sheets:
1. `retro-urban-kit` (brick): rejected on look. It also has 22 tiling textures per kit, which the
   one-texture-per-kit merge cannot handle. Blueprints are in git history (commits 2b5af60..3293d78).
2. `city-kit-commercial` + `city-kit-roads`: liked, but it is Metropolis's kit, so the two eras
   would overlap. The 24 blueprints moved to
   `tools/testfit/blueprints/_drafts/Metropolis-city-kit-commercial/` as the Metropolis starting point.

Result: **Boomtown = `city-kit-suburban` + `city-kit-industrial`** (+ `city-kit-roads` props);
**Metropolis = `city-kit-commercial`** incl. skyscrapers (+ roads). Each kit belongs to one era.
All three building kits have one `colormap.png`, so the M7 pipeline needs no change. The four City
Kits share one palette, so the eras must differ by building type and height, not colour.
One exception (lead, 2026-09-16): Metropolis may use `city-kit-suburban` `tree-large`, `tree-small`,
`planter` and `path-*` as small props, because no Metropolis kit has trees (ParkTrees,
RooftopGarden). Suburban buildings and fences stay Boomtown's.

The spec/manifest kit column was never checked against the kits: "Retro Medieval Kit" does not
exist (closest is `retro-fantasy-kit`), and many manifest names (BowlingAlley, ClockTower face,
bus, billboard, hydrant, subway entrance, stadium, rocket) have no Kenney model at all.

## 5. Rejected first attempt (kept for reference)

Four agents mapped every slot to one Kenney file (27 good, 62 stand-in, 7 needs-assembly across
the 96 slots) and a review page was published:
<https://claude.ai/artifact/J9nJqwB2hZS9N25agcT52s>. Ben rejected the one-file-per-slot approach
(§2). The per-era JSON mappings are still a useful **catalogue of which pieces exist and roughly how
big they are**: `assets/research/2026-09-15/mapping/<Era>.json`.

VIP skin approach from that round, still applicable to assembled buildings: VIP = the same pieces
with a recoloured kit palette (`colormap.png`, or `baseColorFactor` for space-kit), generated by a
luminance gradient map (`vip_palette.py`). Proposed ramps, dark → light: Village `#24123A #6B3FA0
#D9A935 #FFF1C9` (royal purple and gold), Boomtown `#0F1A2A #2BB5C8 #C9D3DE #FFFFFF` (chrome and
neon teal), Metropolis `#0B0C10 #2A2E36 #B8913A #F3DC9A` (black glass and gold), Orbital Colony
`#1C2A3A #3FB6D9 #DCE6EE #FFFFFF` (white ceramic and cyan). Not yet approved by Ben. If the Studio
check shows `TextureID` is writable at runtime, VIP needs one recoloured palette image per kit and
no extra model uploads.

## 6. Local research files

Everything from the session is in `assets/research/2026-09-15/` (gitignored, this machine only):

| Path | What |
|---|---|
| `glb-trial/glb_trial.py` | GLB texture embedding, space-kit fix-up, Open Cloud Model upload + polling |
| `glb-trial/studio_check*.luau` | The unrun Studio verification snippets |
| `glb-trial/bounds.json`, `upload_results.json`, `out/` | Measured bounds, full operation responses, uploaded files |
| `make_sheets.py`, `sheets/`, `thumbs/`, `kit_index.json` | Labelled contact sheets and 128 px thumbnails for every kit |
| `mapping/*.json`, `boomtown/`, `orb_*.py` | Per-era mapping catalogue and size-measuring scripts |
| `vip_palette.py` | VIP gradient-map recolour |
| `build_review.py`, `review_template.html`, `model-picks.html` | The rejected review page |

Scripts may still contain the old session's scratchpad path; fix the path constant before reusing.
Python needs `py` and Pillow (`py -m pip install --user pillow`, installed 2026-09-15).

## 7. Suggested first steps next session

1. Ben runs the Studio check (§3) and pastes the `[TRIAL]` output — it gates the runtime design.
2. Lead + Ben agree the growth model: stages per milestone, what unlock/decor/monument slots do,
   and runtime composition vs offline merge.
3. Prototype **one** growing building end to end (e.g. a Village house from fantasy-town pieces,
   stage 0 → 4) before writing M7 contracts in `docs/INTERFACES.md`.
4. Only then fan out: blueprint config + tooling, server assembly, client growth animation,
   VIP palettes, props, icons.

## 8. Other open threads from this session

- Doc fixes in `docs/PLAN.md`, `docs/MANUAL_STEPS.md` and `docs/PLAYTEST.md` (stale ambient-loop
  notes, M2/M3/M6 status, a new "Post-M6 — Ambient era loops" playtest section) were made but
  **not committed**. The ambient-loop listen check (MANUAL_STEPS M6 item 22) is still open.
- Recommended Robux prices, given to Ben but not recorded in `docs/BALANCE.md`: Double Cash 399,
  VIP 249, Offline Pro 199; Cash30m 25, Cash2h 55, Cash8h 99 (1 : 2.2 : 3.96, inside the
  "≤ 2.5× / ≤ 5×" ladder); DoubleOffline 25.
