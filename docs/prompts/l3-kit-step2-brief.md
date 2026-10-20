# L3 weapon kit — step 2: the other thirteen (brief for three builders)

Ben approved the step 1 prototypes on 2026-10-20 ("Yes, build the other 13"): the Broadsword and the Longbow in
`assets/testfit/out/Weapons/_contact.png` are the style, the frame contract and the quality bar. You are one of three
builders working at the same time on disjoint weapons.

## Environment

- Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory` (`assets\` is a junction to the main checkout's
  shared folder). Bash with Git Bash syntax. Python outside Blender is `py` only. Blender:
  `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"`.
- Convert every file you create to LF (`sed -i 's/\r$//'`). Commit nothing. Kill only your own PIDs, never by image
  name.
- **Never run `upload_models.py`, `upload_paths.py`, `harvest.py` or `gen_templates.py`, not even `--dry-run`.**
  `merge_stages.py --props --era Weapons` is allowed for measuring triangles.
- Other agents edit `src/`, `docs/` and the simulators on this branch at the same time: touch nothing outside the files
  you own. Two builders generating or merging at the same moment can hit a file being written; re-run.

## Read first

1. `tools/testfit/README.md`, the "weapon kit" section at the end (frame contract, names, scale, budgets, colour rules,
   the shape helpers, the lessons from the strips).
2. `tools/assets/weapon_kit_forest.py` (the pattern to copy), `tools/assets/weapon_kit_mesh.py` and
   `tools/assets/weapon_kit_palette.py` (read only: **frozen**; a new colour or helper is a request to the lead, in
   your report).
3. `tools/testfit/blueprints/_props/Weapons/Broadsword.json` (copy it for each blueprint).
4. `docs/WEAPONS.md` (what each family is and does) and `docs/MISSIONS_DESIGN.md` §24 (each weapon is dressed by the
   level where it is found: Forest wood, bone, rope, flint; Castle steel, crests, gold; Underworld black iron, embers;
   Planet alloy, glow strips; Dream crystal, pastels).
5. Look at `assets/testfit/out/Weapons/_contact.png`, `Broadsword_icon_check.png` and `Longbow_icon_check.png` with
   the Read tool.

## The split

| Builder | Owns (generators) | Weapons (model name: design intent) |
|---|---|---|
| **A** Forest + Castle | `weapon_kit_forest.py` (add two), new `weapon_kit_castle.py` | **Flamethrower** (Forest, fire): a raider's bellows sprayer of wood and bone, a hide fuel gourd lashed under it, an ember-glow nozzle mouth as geometry (the flame is an effect). **Warhammer** (Forest): a river-stone maul head lashed to a thick wooden haft, rope, bone spikes, ochre bands. **FrostHammer** (Castle, ice): a steel war hammer whose head grows clear ice crystals, gold trim, rime on the haft. **Greataxe** (Castle): a crescent steel axe on an oak haft, gold rivets, a crest-blue ribbon. **Splitbow** (Castle relic): a steel-and-oak recurve with a gold three-way arrow guide and a crest at the riser; the most ornate of the Castle. |
| **B** Underworld | new `weapon_kit_underworld.py` | **Spear**: a black-iron barbed leaf blade with glowing ember cracks, chain and ash-bone on the haft, 6–7 studs. **Shotgun**: a black-iron blunderbuss with an ember-lit flared bell and a bone stock. **Rifle** (the Piercing Rifle): a long black-iron barrel with ember vents along it and an obsidian sight. Black iron is an "inner" colour: every dark mass needs a light edge swatch (README colour rules). |
| **C** Planet + Dream | new `weapon_kit_planet.py`, `weapon_kit_dream.py` | **Launcher** (Planet): a white alloy tube, cyan glow strips, a hazard-orange shell band. **Smg** (Planet): a compact alloy body, a green glow magazine, rubber grips. **Beam** (Planet): a projector with a cyan emitter ring and cooling fins. **Chaingun** (Dream): a pearl body, a crystal coil and pastel conductor rings reading as chain lightning. **Spinblade** (Dream relic): a curved crystal blade with a pearl and pastel-gold grip; the most ornate model of all. |

Each builder also owns its weapons' blueprints `tools/testfit/blueprints/_props/Weapons/<Model>.json` and their renders
in `assets/testfit/out/Weapons/`. Only the lead builds the contact sheet.

## Rules (from step 1; the README has the detail)

- **Frame contract:** 1 glTF unit = 1 stud; grip centre at the origin, tip or muzzle along −Z, top +Y. Every weapon sets
  `grip`, `tip` and `holster` in `Mesh.frame` (add `nock` / `bladeBase`-style extras where they help the client).
- **Scale** against the 5-stud R15: hammer and axe hafts 3.8–4.5, spear 6–7, guns 2.4–3.4, launcher about 3.6,
  flamethrower about 3.2 plus its gourd. Two-handers are held by the right hand alone in L3: put the grip where the
  right hand goes.
- **Budget:** 1,500–3,500 triangles per weapon, never over 5,000, measured with the merge.
- **Detail from shape** (bevels, wraps, bindings, rivets, fins, crystals): the palette is flat, there is no sheen.
  Glows are geometry in a bright swatch (a ViewportFrame draws no lights or particles).
- Each weapon must read as its family at 64 px on every ground in the icon check, and the set must read as one family of
  objects with the two prototypes. A weapon of a later level should look more advanced than an earlier one; a relic is
  the most ornate of its level.
- Judge every strip and icon check yourself with the Read tool. Iterate until each looks intentional.

## Report (end your turn with it even if everything passed)

Per weapon: strip and icon paths, triangles, size, the frame points, render iterations, one line on what makes it read
as its family. Requests to the lead (colours, helpers, README lines). Anything in the tools that fought you.
