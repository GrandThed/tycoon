# L3 weapon kit — step 1: the shared pieces and a two-weapon prototype (brief)

You are the **weapon-kit lead** for milestone L3 of the Roblox project "Era City Tycoon". Work in
`C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory` (its `assets\` is a junction to the main checkout's shared
`assets` folder). Use Bash with Git Bash syntax. Python outside Blender is `py` only. Blender:
`"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b ...`. Convert every file you create to LF
(`sed -i 's/\r$//'`). Do not commit. Kill only your own PIDs, never by image name.
**Do not run `upload_models.py`, `upload_paths.py`, `harvest.py` or `gen_templates.py`, not even with `--dry-run`**
(a dry run writes `Assets.json`). `merge_stages.py` is allowed for measuring (it writes only gitignored build files).

## The job

Ben chose (MISSIONS_DESIGN §24): **all 15 weapon families get a model, one look each, detailed** (his 2026-09-23
ruling, over chunky low-poly), **dressed by the level where each is found**: Forest wood, bone, rope, flint; Castle
steel, crests, gold; Underworld black iron, embers; Planet alloy, glow strips; Dream crystal, pastels. Fire weapons read
fire, ice weapons read ice. No Kenney weapon kit exists: the geometry is generated in Blender, like
`tools/assets/people_kit.py` (one-piece props) and `tools/assets/stadium_kit.py` (modules with colour-only materials).

Step 1 (this brief) makes the shared pieces and **two Forest weapons, the Broadsword and the Longbow**, so Ben can judge
the style on two strips before three builders do the other thirteen. Step 2 reuses everything you leave behind.

## Read first

1. `docs/prompts/l3-study-report-screen.md` §4 and §5 (frame, scale, budget, route) and §3 (the screen's dark panel).
2. `.claude/skills/build-assets/SKILL.md` and `tools/testfit/README.md` (blueprint format, the render loop).
3. `docs/ASSET_RESEARCH.md` §2 and §7; `tools/assets/palette.py`; `tools/assets/people_kit.py`; `tools/testfit/testfit.py`.
4. `docs/WEAPONS.md` (what each family is and does) and `src/shared/Config/ProvingGrounds.json` `weapons` (ids:
   broadsword, warhammer, spinblade, greataxe, spear, frostHammer, longbow, splitbow, flamethrower, shotgun, rifle,
   launcher, smg, beam, chaingun).

## You own (new files unless said)

- `tools/assets/weapon_kit_palette.py`: the shared swatches per level (and fire/ice accents), sampled so they read on
  the screen's panel colour (30, 41, 70) and in daylight. Builders in step 2 import it; nobody redefines a colour.
- `tools/assets/weapon_kit_forest.py`: Blender generator for the Forest-dressed weapons (Broadsword, Longbow now; step 2
  adds Flamethrower and Warhammer to it). GLBs into `assets/kenney3d/weapon-kit/Models/GLB format/` (the folder is the
  kit's registration).
- `tools/testfit/blueprints/_props/Weapons/<ModelName>.json`: one-stage, one-piece blueprints. Propose the model names
  (PascalCase, must equal the template name later; check the 50-character Open Cloud name cap with the `_props` naming
  in `upload_models.py`).
- A small `testfit.py` option for weapons (you are the only one editing `testfit.py` now): a side view and a
  three-quarter view, a 5-stud R15 silhouette for scale, and the screen's panel colour with a lighter radial behind.
  Default renders of every other blueprint must not change (check one existing strip renders identically).
- An icon render per weapon (PNG with alpha, square, readable at 64 px on (24, 24, 28) and on the panel colour), for the
  shelf. Rendering only; the upload route comes later.
- A "weapon kit" section in `tools/testfit/README.md`: the frame contract, scale, budgets, how to render, kit facts.
- Strips and icons in `assets/testfit/out/Weapons/`.

## Rules

- **Frame contract:** 1 glTF unit = 1 stud. Grip centre at the origin, blade tip or muzzle along −Z, top +Y. Record per
  weapon the grip, the tip or muzzle point, and the back-holster point as numbers in your report: a merged prop is one
  MeshPart, so the client will read those from config, never measure them.
- **Scale** against a 5-stud R15 body: sword 3.6–4.0, bow 3.6–4.0 tall (the report §5 has the rest).
- **Budget:** 1,500–3,500 triangles per weapon, never over 5,000 (measure with `merge_stages.py`). Detail from shape
  (bevels, wraps, fletching, rivets, lashings): the palette is flat, there is no sheen.
- Colour-only materials through `palette.py`. After any colour change delete `assets/build/palettes/weapon-kit.*`
  before the next merge (the cache snaps new colours to old swatches silently).
- Judge every strip yourself with the Read tool, on the panel colour and beside the silhouette. The two must look like
  one family of objects and like the Forest (a raider's camp: wood, bone, rope, flint), and the Broadsword must still
  read as a broadsword at icon size.

## Report (end your turn with it even if everything passed)

Per weapon: strip and icon paths, triangle count, length, the grip / tip / holster numbers, render iterations. The
shared pieces you made and how step 2 should use them. Anything in the tools that fought you. A proposed split of the
other thirteen into three builders (disjoint, by level dress) with one line of design intent each.
