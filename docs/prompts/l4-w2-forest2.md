# L4 W2, track F2 — the mountain dressed and the walls less regular (brief for the forest builder)

You are the **forest builder** for milestone L4 wave 2 of the Roblox project "Era City Tycoon". Work in
`C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest` (its `assets\` is a junction to the main checkout's shared
`assets` folder). Bash with Git Bash syntax. Python is `py` only (`py script.py` with a `#!/usr/bin/env python` first
line runs 3.12 without Pillow; without that line it runs 3.14 with Pillow). Blender (renders):
`"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b ...`. Convert every file you create to LF. Do not
commit. Kill only your own PIDs, never by image name. **Never run `upload_*.py`, `harvest.py` or `gen_templates.py`**:
nothing is uploaded until Ben approves your pictures. Nobody else works in this worktree now.

## Why

Two of Ben's rulings meet in this pass (MISSIONS_DESIGN §27 and §28, read both):
1. **The rocks, second look:** the stones and outcrops are right, but the tall walls a player walks beside read as walls
   of stone blocks. Ben chose **less regular walls**: the same depth (the skin may not stand out into walking space),
   **bigger uneven blocks, broken horizontal layers, fewer straight joints, boulder piles in corners and beside gates
   where nobody walks**; no layout change. His references: `assets/research/2026-10-21-l4/ref_rocks_standing.png`,
   `ref_rocks_cliffs.png`. Today: `assets/testfit/out/Levels/ForestRoad/_L4_rocks_before_after.png` (right column).
2. **The mountain climb** is now in the layout (commit cd93c27): seven ledge pillars spiral once round a 28 × 28 core whose
   top is the summit at 200, eight double jumps of 25 studs, a 96 × 96 yard north-west of the trailhead, reached by
   `MountainPath` and `MountainTrail`. Read `docs/prompts/l4-w2-reports/mountain.md` in full: its section "What
   `tools/levels/forest.py` must do" and the pillar table are your work list (the yard's walls to y 280 except the one
   mouth at x -482, z -8..8; `find_drops` must skip the climb's secret; cap stones flush with every ledge top and the
   summit; no fir on a hop end; `check_parkour.CLIMBS` names every piece and may be imported).

Read also `docs/prompts/l4-w2-reports/rocks.md` (how the rocks are built now, the `block_face` sizes, what fell short) and
`tools/levels/README.md`.

## The job

- **The mountain** is the forest's landmark, seen from the whole road: dress the core and the pillars in Ben's clustered,
  bevelled-block style (his second reference is exactly a rock tower), big blocks on the lower and far faces, finer ones
  near the ledge tops where the player stands; the ledge tops read clearly as "stand here" (flat cap stones, lighter);
  the step faces a player jumps along read as rock, not as a staircase of boxes; a summit worth reaching (a cairn or a
  ring of standing stones round the chest, a lookout view). The yard: forest floor, boulders, a few trees off the hop
  lines.
- **The walls:** rework the cliff skin of every tall wall a player walks beside (camp A's cliff, the cave ridge, the
  gatehouse canyon, the Chief's clearing, BendWall) as Ben chose; boulder piles in corners and beside gates outside
  walking space.
- **Rules that do not move:** collision never changes (skins and props walk-through; the yard's new walls are invisible
  barrier data as before); `forestcheck.py` rules all hold, including the two rock rules; nothing standable is added;
  coplanar faces never; `py tools/levels/forest.py check` and `py tools/levels/forest.py mutants` PASS;
  `py -3.12 tools/check_levels.py` and `py -3.12 tools/check_parkour.py` still PASS (you change no layout).
- **Budget:** the mountain dressed with today's rules made the level 212,093 triangles against about 150k. Target **at
  most 165k**, hard cap **175k**: big blocks where only distant players see faces, cheaper far canopy, merge what is never
  seen up close. Report the whole level and the worst views (the old worst spot and the yard looking up) before and after.
- Each baked mesh stays inside the Open Cloud limits the Valley proved (about 16k triangles, about 1,444 studs; Hills_1 at
  1,496 is already the widest); `glbtools.roblox_problems` clean. The plan hash changes (new layout): fine, nothing is
  uploaded.

## You own

`tools/assets/forest_kit.py`, `tools/assets/forest_palette.py`, `tools/levels/forest.py`, `tools/levels/forestcheck.py`,
`tools/levels/levelmesh.py`, `tools/levels/README.md`, `tools/testfit/levelrender.py`,
`src/shared/Config/LevelDress/ForestRoad.json` (generated), renders in `assets/testfit/out/Levels/ForestRoad/`. Not the
layout, not `check_levels.py`, not `check_parkour.py` (read them; if a rule there blocks you, say so in the report).

## Pictures for Ben (mood B, the approved mood)

`mountain_far_B.png` (from the trailhead, the mountain over the trees), `mountain_yard_B.png` (from the yard's mouth,
looking up the spiral), `mountain_ledge_B.png` (from ledge 3 or 4, the next hop ahead), `mountain_summit_B.png` (the
summit and the chest, the forest below), `plan_top_F2.png`, and a before/after sheet `_L4_walls_before_after.png` (the
current right column of `_L4_rocks_before_after.png` on the left, your walls on the right) for camp A, the gatehouse and
the clearing. Judge every picture yourself with the Read tool against Ben's references; iterate; say honestly what still
falls short.

## Report (end your turn with it even if everything passed)

`docs/prompts/l4-w2-reports/forest2.md`: picture paths; what changed for the walls and the mountain; triangle counts before
and after (whole level, worst views, the mountain alone); mesh and prop counts for the upload (was 34 meshes + 5 images + 4
props); the plan hash; every gate's verdict line; anything the pipeline's runbook `docs/prompts/l4-w2-asset-run.md` must
change.
