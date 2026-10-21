# L4 W1, track F — the forest on paper (brief for the forest kit lead)

You are the **forest kit lead** for milestone L4 of the Roblox project "Era City Tycoon". Work in
`C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest` (its `assets\` is a junction to the main checkout's shared
`assets` folder). Bash with Git Bash syntax. Python outside Blender is `py` only (`py script.py` with a
`#!/usr/bin/env python` first line runs 3.12 without Pillow; without that line it runs 3.14 with Pillow). Blender:
`"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b ...`. Convert every file you create to LF. Do not
commit. Kill only your own PIDs, never by image name. **Do not run `upload_models.py`, `upload_paths.py`,
`upload_world.py`, `harvest.py` or `gen_templates.py`, not even with `--dry-run`** (a dry run writes `Assets.json`);
merges and bakes that write only gitignored build files are allowed. Never write into another tool's output folder.

Two other agents work in this worktree now: the economy-designer is moving the lookout in
`src/shared/Config/Levels/1_ForestRoad.json` (it writes `docs/prompts/l4-w1-reports/layout-ready.md` when done: read
the layout again after that, before your final renders), and the raider kit lead (`tools/assets/raider_kit*`,
`tools/testfit/raider*`). Do not edit their files.

## The job

Ben's L4 decisions are MISSIONS_DESIGN §26 (read it). This track makes **the dressed Forest Road on paper**: the
generator that will dress the level in the game, the generated pieces, and pictures for Ben's look. **No game code and
no uploads in this wave**; W2 puts it in the game from your generator's output under a contract written from your report.

Read first: `docs/prompts/l4-study-report-forest.md` (all of it: it is your groundwork, with the measured counts, the
three layout variants, the routes and the risks), MISSIONS_DESIGN §12.1, §21, §22, §26; `tools/world/valley.py` and
its INTERFACES section "Wave 2 — the Valley meshes" (one generator is the source of truth, Parts-only collision from
generated JSON, `planHash`); `tools/paths/` and `tools/pathtest/planar.py` (baked planar-UV ground with rims, the
recipe in memory note `city-dressing-2026-09-16`); `tools/testfit/plotscene.py` and `plotrender.py` (the render route);
`tools/assets/weapon_kit_palette.py` class `FOREST` (the Forest swatches the weapons already use); the study's scratch
scene builder `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\3f855f00-eb33-4bab-adb5-c937f685030c\scratchpad\l4-forest\scene_forest.py`
and `plotscene_scratch.py` (a starting point, not a design); the proof renders are in
`assets/research/2026-10-21-l4/`.

## Rulings that bind you

- **Ben (§26):** the lookout at the trailhead; **camp edges are natural on today's outlines** (logs, rocks, thicket,
  at most 4 studs, gaps where the gates are; the enemies behave as now); real raider models come from the other track;
  the Chief's tent stands in camp C behind where the Chief appears.
- **Lead:** the ground and the tall walls get **baked planar-UV skins** (irregular edges, rims; the city's route) over
  the collision the layout already has; **dressing never changes collision**: every collidable piece is a layout block
  (today's, or a new invisible one your generator writes for W2), everything you add is walk-through; the forest floor
  beside the road is closed to players by an **invisible wall at the tree line** (character-only, rays and camera
  pass), except at designed drops (the trailhead gap, the creek, the plateau's lip): emit those walls as data. A
  standable top more than 2.5 studs off a region cell is a new sniper spot: none may appear. The camp C rules hold
  (nothing of the clearing visible from outside, the tent ≤ 3.5 studs where standable or walk-through, no AlwaysOnTop
  marker). Coplanar faces shimmer: inset or move. Organic: Ben has chosen organic every time; it must not read as the
  Village or the Valley re-used (a raider forest: darker, denser, camps of hide, rope and logs).
- **Budget:** about 150k triangles for the whole level at the game camera, and Instance counts a phone can carry
  (measure and report both; propose merged tree clusters for the far forest and single props only near the road if
  the counts demand it). The study's proof scene was 445k at Kenney's counts.
- **Moods:** render the key views in two moods: A the palette under default Roblox lighting (every look Ben approved
  so far was judged under it), B darker with Atmosphere-style haze (dungeon place only, config). Ben picks.

## You own (new files)

- `tools/levels/forest.py` (and helpers `tools/levels/*.py`): the deterministic generator. It reads
  `1_ForestRoad.json`, writes the GLBs into `assets/build/levels/ForestRoad/` and one generated data file proposed for
  the game (placements of props and baked pieces, the new invisible blocks, a plan hash), written for now to
  `tools/levels/out/ForestRoad.dress.json` (W2's contract decides where the game reads it). A `check` mode that
  fails on: a standable new top, a collidable dressing piece, a piece inside the region's walking space taller than
  4 studs, an overlap of coplanar faces, a broken plan hash.
- `tools/assets/forest_kit.py`: generated pieces (trees that are not the Village's, thicket, log and rock edge pieces,
  hide tents, the Chief's tent, campfires, racks, cliff and ground skins as needed), colour-only materials via
  `palette.py`; `tools/assets/forest_palette.py` (ground, foliage, bark, rock, hide; reuse `FOREST` from
  `weapon_kit_palette.py`, never redefine it). GLBs into `assets/kenney3d/forest-kit/Models/GLB format/`. A nature-kit
  piece may be used only if it reads right without a recolour (the pipeline cannot recolour a kit piece).
- `tools/testfit/levelrender.py`: renders the level from the generator's data file (a verbatim mirror of what the game
  will place, the plotrender pattern), with a top-down plan and player-eye views at the game's shoulder camera.
- Renders in `assets/testfit/out/Levels/ForestRoad/` (new folder) and a contact sheet of the generated pieces.
- `tools/levels/README.md`: how to generate, check and render, the kit facts (the raider lead owns the testfit README this wave).

## Pictures Ben needs

A top-down plan; player-eye views of the trailhead with the new lookout, camp A (Pickets), Main Camp, the cave mouth,
the pond and island shrine, the gatehouse from the road, the Chief's clearing from inside (his tent), and one view from
the lookout ledge; two moods for the trailhead, Main Camp and the clearing. Raiders as simple coloured stand-ins at
their Normal posts (the raider track makes the models), a 5-stud player figure for scale. Judge every picture yourself
with the Read tool before reporting it; fix what looks wrong rather than describing it.

## Report (end your turn with it even if everything passed)

`docs/prompts/l4-w1-reports/forest.md`: the picture paths with one line each; triangle and Instance counts (whole
level, and in view from the worst spot); the pieces made with triangle counts; the data file's format (fields, units,
frames; it becomes W2's contract); the invisible walls and new blocks you propose, with their coordinates; what W2's
game code must do (who places what, client or server, when in the run); uploads and the paste count W2 will need;
textures needed; risks and anything in the tools that fought you.
