# L4 W2, track K — the forest's rocks, redone (brief for the rock builder)

You are the **rock builder** for milestone L4 wave 2 of the Roblox project "Era City Tycoon". Work in
`C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest` (its `assets\` is a junction to the main checkout's shared
`assets` folder). Bash with Git Bash syntax. Python is `py` only (`py script.py` with a `#!/usr/bin/env python` first
line runs 3.12 without Pillow; without that line it runs 3.14 with Pillow). Blender (renders):
`"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b ...`. Convert every file you create to LF. Do not
commit. Kill only your own PIDs, never by image name. **Never run `upload_*.py`, `harvest.py` or `gen_templates.py`**
(nothing is uploaded yet, and nothing may be until Ben approves your rocks). A raider kit builder works in this worktree
at the same time (`tools/assets/raider_kit*`, `tools/testfit/raider*`, `tools/testfit/blueprints/_props/Raiders/`,
`tools/assets/out/RaiderModels.json`): do not touch those.

## Why

Ben approved the dressed forest (MISSIONS_DESIGN §27) and then, looking again, said: *"to be honest, the stones leave so
much to offer, it would be great if we could make something more like the images attached"*. His two references:
- `assets/research/2026-10-21-l4/ref_rocks_standing.png`: a line-up of **standing stones and chunky low stones**, each a
  few big flat facets with bevelled (chamfered) edges, upright and slightly leaning, in a warm pale grey-beige, from tall
  monoliths down to small pebbles: sculpted, deliberate shapes, not noise.
- `assets/research/2026-10-21-l4/ref_rocks_cliffs.png`: **cliffs and outcrops built from clustered, stacked blocks**:
  many bevelled, roughly rectangular prisms of different heights packed together, tilted a little, with bigger caps on top,
  reading as one stylised rock mass with strong light tops and darker sides.

Today's rocks (look at `assets/testfit/out/Levels/ForestRoad/campA_A.png`, `gatehouse_A.png`, `clearing_A.png`,
`caveMouth_A.png`): the cliff skins over the tall walls are a noisy triangulated surface, and the boulders are jittered
blobs. Ben wants the reference's language everywhere a rock shows.

## The job

Redo **every rock** of the forest in that language, keeping everything else as approved:
1. **Cliffs and massifs** (the skins over the cave ridge, the gatehouse canyon, the rock massif round the Chief's hollow,
   and any other tall wall skin): built from clustered bevelled prisms (image 2), packed so no gap shows the collision
   wall behind, tops capped, light tops and darker sides from the palette (colour per face by its facing is fine: the
   pipeline is colour-only), slight tilts, varied heights so the skyline is broken but never spiky.
2. **Standing stones, boulders, camp-edge rocks, pond and island rocks, small stones** (image 1): chamfered prisms with a
   few big facets, a family of sizes from monolith to pebble, some leaning, scattered in clusters with small stones at
   their feet.
3. Trees, thicket, ground, tents, the Chief's hall, the camp edges' logs and stakes stay as they are.

## Rules that do not move

- **Collision never changes:** skins cover the layout's walls exactly as before (`hide` list, `forestcheck.py` rules);
  every rock you place is walk-through; nothing standable is added; the 62 invisible walls stay.
  `py tools/levels/forest.py check` must PASS, and every `forestcheck.py` rule still holds (rerun its mutants:
  `tools/levels/README.md` says how). Nothing taller than 4 studs inside a plateau cell; nothing of camp C rises above
  its wall; no coplanar faces between different looks.
- **The plan hash** must not move for an art change (it hashes layout, art numbers it already hashed, and each stage's
  kind, zone and boss position): if your change moves it, say why. The data file is
  `src/shared/Config/LevelDress/ForestRoad.json` (written by `forest.py build`).
- **Budget:** the whole level was 149,761 triangles against about 150k. Bevelled clusters cost more: aim to stay at or
  under 150k by trading (fewer, bigger blocks where the camera is far; cheaper canopy if needed), and never over 175k.
  Report the whole-level count and the worst view's count, before and after.
- **Mesh limits:** each baked mesh under the Open Cloud limits the Valley proved (about 16k triangles, about 1,444 studs);
  `glbtools.roblox_problems` clean.
- Colours from `tools/assets/forest_palette.py` (add rock tones there if needed: a light top, a mid side, a dark base;
  warm pale grey like the references; keep the palette under its cap).

## You own

`tools/assets/forest_kit.py`, `tools/assets/forest_palette.py`, `tools/levels/forest.py`, `tools/levels/forestcheck.py`,
`tools/levels/levelmesh.py`, `tools/levels/README.md`, `tools/testfit/levelrender.py`,
`src/shared/Config/LevelDress/ForestRoad.json` (generated), the renders in `assets/testfit/out/Levels/ForestRoad/`.

## Pictures for Ben

1. `assets/testfit/out/Levels/ForestRoad/_rocks_sheet.png`: your rock family laid out like his first reference (a row of
   standing stones by size, a row of low chunky stones, a row of pebbles) and two or three cliff blocks like his second,
   on a plain ground, from a three-quarter view.
2. Re-render with mood B (the approved mood) the views where rock shows: `campA`, `caveMouth`, `gatehouse`, `clearing`,
   `lookoutLedge`, `pond`, `shrine`, plus `plan_top`; keep the old files' names with a `_rocks` suffix so he can compare
   (`campA_B_rocks.png`, ...).
3. A before/after sheet `_L4_rocks_before_after.png` (old A render left, new right) for camp A, the gatehouse and the
   clearing.

Judge every picture yourself with the Read tool, against Ben's two references, and iterate until the rocks read like them
at the game camera; say honestly if something still falls short.

## Report (end your turn with it even if everything passed)

`docs/prompts/l4-w2-reports/rocks.md`: picture paths, the rock pieces and their triangle counts, the whole-level and
worst-view counts before and after, the plan hash (unchanged or why), `forest.py check` and the mutant verdicts, the
mesh count for the upload (was 38), and anything the pipeline's runbook must change.
