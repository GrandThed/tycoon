# L4 W2, track P — the asset route for the forest and the raiders (brief for the pipeline engineer)

You are the **pipeline engineer** for milestone L4 wave 2 of the Roblox project "Era City Tycoon". Work in
`C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest` (its `assets\` is a junction to the main checkout's shared
`assets` folder). Bash with Git Bash syntax; `py` only (`py script.py` with a `#!/usr/bin/env python` first line runs
3.12 without Pillow; without it 3.14 with Pillow; say which Python you used). Convert every file you create to LF. Do not
commit. Kill only your own PIDs, never by image name. **No upload, harvest or template run that talks to Roblox or writes
`Assets.json` in this task** (a `--dry-run` of `upload_models.py` writes `Assets.json`: never run it); you make the route
ready and prove it offline. The real run happens after Ben approves the raider overview, from your runbook.

A raider kit builder works in this worktree at the same time (`tools/assets/raider_kit*.py`, `tools/testfit/raider*`,
`tools/testfit/blueprints/_props/Raiders/`, `tools/assets/out/RaiderModels.json`): do not edit those.

## The job

Ben approved the forest and the raider style (MISSIONS_DESIGN §26, §27). W2 uploads, in **one harvest paste**:
- **the forest:** `py tools/levels/forest.py build` writes 38 baked meshes, a palette and 4 ground textures to
  `assets/build/levels/ForestRoad/` and 4 prop models (campfire, spawn tipi, the Chief's hall, bramble); see
  `docs/prompts/l4-w1-reports/forest.md` and `tools/levels/README.md`;
- **the raiders:** seven kinds, five stages each, from four or five kit folders (`raider-kit`, `raider-cloth`,
  `raider-skin`, `raider-glow`, and `raider-plate` coming in step 2) through the props route
  (`merge_stages.py --props --era Raiders`, `upload_models.py --props`); see `docs/prompts/l4-w1-reports/raiders.md`.

**Lead's ruling on where they land:** the client places the forest's meshes and props and the raider models, so both
must reach `ReplicatedStorage` in the combat place. Forest meshes and textures: `templates/_levels/ForestRoad/` mapped to
`ReplicatedStorage.Assets.Levels.ForestRoad` (combat place and the proving build; the hub does not need them). Forest
props and raiders: the props route (`templates/_props/...`, already mapped to `ReplicatedStorage.Assets.Props` in
`combat.project.json`). Propose the exact project-file lines; the lead edits project files.

Precedents: the Valley's world route (`tools/assets/upload_world.py --set`, harvest kinds `worldMesh` / `worldTexture`,
`gen_templates.py --world`, `planHash`, MANUAL_STEPS "M13 wave 2"); the L3 weapons and icons (props route, `--model`
flags so already-uploaded props are never touched, the 50-character Open Cloud name cap with the `ECT_` fallback, the
`upload_models.py` skip-if-nonzero trap in memory note `assets-direction-2026-09-15`, the palette cache trap in
`orbital-dressing-2026-09-23`). Read `docs/ASSET_RESEARCH.md` §2 and §7, `.claude/skills/build-assets/SKILL.md`,
`docs/MANUAL_STEPS.md` "L3 W2 — the asset run".

## You own

`tools/assets/upload_world.py` (or a new `upload_level.py` if cleaner), `tools/assets/harvest.py`,
`tools/assets/gen_templates.py`, `tools/assets/assets_config.py`, `tools/gen_asset_manifest.py`, `tools/levels/forest.py`
only where the route needs an upload manifest or a hash record from it (keep its `check` byte-identical otherwise), and a
new runbook `docs/prompts/l4-w2-asset-run.md`.

## Done when

1. Every tool change has an offline proof: a set loaded from the build folder, records checked (`glb_problems`,
   `palette_problems`), names under the cap, harvest parsing a synthetic Output for the new kinds, `gen_templates` writing
   `templates/_levels/ForestRoad/` from a synthetic `Assets.json` into a scratch copy (never the repo's), the manifest.
2. `Assets.json` untouched (`git diff --stat` shows nothing there).
3. The runbook lists every command of the real run in order (the forest build, the raider merge, uploads with their
   counts, `harvest.py --emit`, Ben's one paste in `build/test.rbxl` or `proving.rbxl` (say which file and why), the
   clipboard saved to a file and the `[HARVEST] {` records counted before `harvest.py` reads it, templates, manifest,
   sourcemaps, place files) and the expected counts (47 forest records plus 35 raider stages, or what you find).
4. Your report `docs/prompts/l4-w2-reports/pipeline.md`: changes per file, the proofs, the proposed project-file lines,
   risks. **End your turn with its summary even if everything passed.**
