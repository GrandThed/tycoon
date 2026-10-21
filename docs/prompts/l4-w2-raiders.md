# L4 W2, track R2 — the other four raiders (brief for the raider kit builder)

You are the **raider kit builder** for milestone L4 wave 2 of the Roblox project "Era City Tycoon". Work in
`C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest` (its `assets\` is a junction to the main checkout's shared
`assets` folder). Bash with Git Bash syntax. Python outside Blender is `py` only (`py script.py` with a
`#!/usr/bin/env python` first line runs 3.12 without Pillow; without that line it runs 3.14 with Pillow). Blender:
`"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b ...`. Convert every file you create to LF. Do not
commit. Kill only your own PIDs, never by image name. **Do not run `upload_models.py`, `upload_paths.py`,
`upload_world.py`, `harvest.py` or `gen_templates.py`, not even with `--dry-run`**; `merge_stages.py` is allowed for
measuring. After any colour change delete `assets/build/palettes/raider-*.*` before the next merge.

A pipeline engineer works in this worktree at the same time on the upload, harvest and template tools
(`tools/assets/upload_*.py`, `harvest.py`, `gen_templates.py`, `assets_config.py`, `gen_asset_manifest.py`,
`tools/levels/`): do not edit those. Nothing else runs here.

## The job

Ben approved the prototype style (MISSIONS_DESIGN §27.4; read §26 and §27) and the Chief's **look A**. Build **the
other four looks: slinger, marksman, lobber, plated elite**, in the same kit, with the same rig and colour route, so all
seven are ready for one upload. Also, from the lead's notes (`docs/prompts/l4-w1-reports/lead-notes.md`, "Raider kit"):
- bring the fodder up to about 800 triangles so it matches the others' detail;
- propose the Chief's chest core at model size (today's client draws a 2.4-stud ball that swells to 4.2): a number for
  config, shown in the Chief's strip (the client change is W2's ui work, not yours);
- measure the posed reach of every kind (bounds over all poses, the Chief's hammer in the sweep and the slam windup) and
  write it to the config: camp C's sight gate will read it.

Read first: your predecessor's report `docs/prompts/l4-w1-reports/raiders.md` (rig, colour route, config format, the
step-2 split and its notes: the sling's whirl needs one new arm rule, the marksman's crossbow is two-handed, the plated
elite's planks vanish on the break and need a fifth kit `raider-plate` and a new client role); the code it left
(`tools/assets/raider_kit*.py`, `tools/testfit/raiderview.py`, `raiderpose.py`, the "raider kit" section of
`tools/testfit/README.md`); `src/combat/client/Controllers/CrowdRenderer.luau` (the poses, tells and per-kind colours,
the shooters' attack shapes `shot` / `line` / `lob`, the plate) and `src/shared/HitShapes.luau`; the kinds in
`src/shared/Config/ProvingGrounds.json` (heights: slinger 5, marksman 5.4, plated elite 6.5).

## Rules (unchanged from step 1)

Rigid pieces, no Humanoid, no Bones; piece k in stage k; pivots and bounds to the config (the client never measures).
Every tell surface is its own untextured piece the client paints. The drawn head stays within half its radius of the
scored head in every pose before a hit lands (`raiderpose.py --check` covers all seven). Budgets: slinger, marksman,
lobber 800 with gear; plated elite 1,000 with the plate. One tribe, told apart by gear, size and cloth colour; must read
at 50 studs on a phone. Raider gear is the raider kit's own (sling, heavy crossbow, firepot satchel, lashed-plank plates).

## You own

`tools/assets/raider_kit*.py`, `tools/testfit/raiderview.py`, `tools/testfit/raiderpose.py`,
`tools/testfit/blueprints/_props/Raiders/`, `tools/assets/out/RaiderModels.json`, the "raider kit" section of
`tools/testfit/README.md`, `assets/kenney3d/raider-*/`, `assets/testfit/out/Raiders/`.

## Pictures for Ben

A strip per new kind (the same poses as step 1, plus each shooter's own attack), the plated elite before and after the
break, and **one overview of all seven** at rest and in windup beside the 5-stud player, also at 50 studs on a phone
(`assets/testfit/out/Raiders/_overview.png`). Judge every picture yourself with the Read tool and fix what looks wrong.

## Report (end your turn with it even if everything passed)

`docs/prompts/l4-w2-reports/raiders.md`: per kind the strip path, triangles, MeshParts, height, posed reach; the
overview path; the new arm rules and the plate role as numbers the client must follow; the config format changes; the
final upload list for all seven (kits, stages, names under the 50-character cap); `raiderpose.py --check` and
`merge_stages.py --props --era Raiders` verdicts; risks.
