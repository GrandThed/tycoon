# L4 W1, track R — the raiders and the Camp Chief, prototypes (brief for the raider kit lead)

You are the **raider kit lead** for milestone L4 of the Roblox project "Era City Tycoon". Work in
`C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest` (its `assets\` is a junction to the main checkout's shared
`assets` folder). Bash with Git Bash syntax. Python outside Blender is `py` only (`py script.py` with a
`#!/usr/bin/env python` first line runs 3.12 without Pillow; without that line it runs 3.14 with Pillow). Blender:
`"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b ...`. Convert every file you create to LF. Do not
commit. Kill only your own PIDs, never by image name. **Do not run `upload_models.py`, `upload_paths.py`, `harvest.py`
or `gen_templates.py`, not even with `--dry-run`** (a dry run writes `Assets.json`); `merge_stages.py` is allowed for
measuring (it writes only gitignored build files). After any colour change delete `assets/build/palettes/raider-kit.*`
before the next merge (the cache snaps new colours to old swatches silently).

Two other agents work in this worktree now: the economy-designer (the level file and the gates) and the forest kit lead
(`tools/levels/`, `tools/assets/forest_*`, `tools/testfit/levelrender.py`). Do not edit their files. If
`tools/assets/forest_palette.py` exists when you choose colours, use its swatches for skin, hide, wood and rock;
otherwise use `FOREST` from `tools/assets/weapon_kit_palette.py`; never redefine a colour another module owns.

## The job

Ben chose (MISSIONS_DESIGN §26): **real models for all seven looks in L4** (fodder, slinger, marksman, lobber, brute,
plated elite, the Camp Chief), **detailed** (his 2026-09-23 ruling, over chunky low-poly), drawn on today's crowd
bodies; each kind keeps its colour so the warnings still read; the Chief's own move is a **war-club sweep**. Step 1
(this brief) is a **prototype sheet of three: fodder, brute and the Chief**, for Ben's look before the other four are
built. Everything you leave behind is reused in step 2.

Read first: `docs/prompts/l4-study-report-chief.md` (all of it: today's drawing, the route, the rig, the budget, the
risks); `src/combat/client/Controllers/CrowdRenderer.luau` (the poses and tells you must mirror: the lean, the windup,
the blow, seated, spent, the colours per kind) and `HitShapes.luau` (the scored head and capsule); the L3 weapon kit
(`docs/prompts/l3-kit-brief.md`, `tools/assets/weapon_kit_*.py`, `tools/testfit/weaponview.py`, the "weapon kit"
section of `tools/testfit/README.md`); `tools/assets/people_kit.py`; `tools/testfit/blueprint.py` (`stage`,
`untilStage`); `.claude/skills/build-assets/SKILL.md`; `docs/ASSET_RESEARCH.md` §2 and §7.

## Rulings that bind you

- **Rig: rigid pieces, no Humanoid, no Bones, no uploaded animations.** One prop per kind; the study's "piece k in
  stage k" (head, torso, weapon arm, left leg, right leg) needs no pipeline change; propose better if you find it, and
  say what it costs. Each piece's pivot and the kind's bounds are written to a config file you propose (the
  `WeaponModels.json` pattern): the client never measures a model.
- **Colour route (lead's ruling, no Studio check):** a textured MeshPart may ignore `Color`, so **every surface that
  carries a tell (the kind's cloth colour, the windup heat, the white flash, the dull spent body, the enraged red) is
  its own untextured piece** that the client paints by `Color` and `Material` exactly as today; wood, bone, hide and
  metal may use the palette texture. Design the pieces so the cloth reads at 50 studs on a phone. Say how many
  MeshParts a body becomes.
- **Head rule:** the lean bends the body below the neck; the drawn head stays within half its radius of the scored
  head (`HitShapes`) in every pose before a hit lands. Show it in your pose strips with the scored head drawn as a
  wire circle.
- **Scale** (the hit shapes every band was measured on): fodder and slinger 5, marksman 5.4, plated elite 6.5, brute
  7.5, the Chief at the Colossus's 14. A player is 5 studs.
- **Budget:** fodder 600, slinger / marksman / lobber 800 with gear, plated elite 1,000 with the plate, brute 1,200,
  the Chief 4,000. Raider gear is the raider kit's own (club, sling, heavy crossbow, firepot satchel, log club,
  lashed-plank plates that burst in splinters); **the Chief carries the L3 Warhammer** (`templates/_props/Weapons/
  Warhammer.rbxmx`, scaled at runtime; its generator is `weapon_kit_forest.py`), never re-modelled.
- **Look:** forest raiders: hide, fur, rope, bone, flint, war paint; one tribe, told apart by gear, size and cloth
  colour. Must not read as the city's walkers. The Chief: **look A**, a fur-cloaked chieftain in a skull mask with the
  Warhammer; also render **look B** (war paint, antler crown, log club) as one front view, so Ben can choose.

## You own (new files)

- `tools/assets/raider_kit.py` (+ `raider_kit_*.py` helpers): the Blender generator; GLBs into
  `assets/kenney3d/raider-kit/Models/GLB format/`.
- `tools/testfit/blueprints/_props/Raiders/<Name>.json` (check the 50-character Open Cloud name cap).
- `tools/testfit/raiderview.py`: pose strips (rest, two walk frames, windup, blow, seated, spent; the Chief also the
  sweep's windup and swing) beside a 5-stud R15 silhouette on a dark forest-floor ground, and in the cloth colours the
  client will paint.
- `tools/testfit/raiderpose.py`: a Python port of CrowdRenderer's pose maths (the strips must pose with the client's
  own maths or the pictures will not match the game), plus the walk cycle and weapon-arm channel you propose.
- A proposed config file (written to `tools/assets/out/RaiderModels.json` for now; W2 decides where it lives).
- Strips in `assets/testfit/out/Raiders/`, and a "raider kit" section in `tools/testfit/README.md`.

## Report (end your turn with it even if everything passed)

`docs/prompts/l4-w1-reports/raiders.md`: per prototype the strip paths, triangle and MeshPart counts, heights; the
Chief's look A and B paths; the rig and the pose rules the client must follow in W2 (as numbers); the colour route
in practice; the config format; the upload count for all seven; a proposed split of the other four looks for step 2;
risks, and anything in the tools that fought you. Judge every strip yourself with the Read tool before reporting it.
