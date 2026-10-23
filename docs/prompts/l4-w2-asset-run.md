# L4 W2 — the asset run (runbook)

**Ben: your one step here is step 7, the harvest paste.** About 3 minutes, any time before your look.

**One run, one paste** (contract `docs/prompts/l4-w2-contract.md` §10 step 3): **81 uploads, one harvest paste of 81
records**, then templates. (Numbers as of the F2 forest, plan hash `23851a6f417491c1`: `l4-w2-reports/forest2.md`.)
- The forest, 46: 37 baked meshes, its palette and 4 ground textures (42, `upload_level.py`), and 4 props (Bramble,
  Campfire, ChiefTent, SpawnTent; `upload_models.py --props --era Forest`).
- The raiders, 35: seven kinds, five stages each (`upload_models.py --props --era Raiders`).

The code wave does not wait for it: with no templates the server keeps the grey level and every kind is a placeholder.
Proved offline on 2026-10-21 (every command below, the network and Studio stubbed): `docs/prompts/l4-w2-reports/pipeline.md`.

**When:** after Ben's OK of `assets/testfit/out/Raiders/_overview.png`, after the lead's project-file lines (step 11 can
also come just before the place files), and with no geometry change pending (below).

**Where:** the worktree `C:\Users\benja\Desktop\tycoon-p5`, on the branch that holds the L4 W2 tools (`upload_level.py`,
the v6 `assets_config.py`). Its `assets\` is the main checkout's (a junction) and `.env` is there. Git Bash. Python is
`py` (the tools with a `#!/usr/bin/env python` line run 3.12, the rest 3.14; none needs Pillow). Rojo needs
`export PATH="$HOME/.rokit/bin:$PATH"`. Blender: `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"`.

## Rules for the lead

- **Announce first.** Tell any other open Claude session before the uploads and before the harvest, and wait for its
  answer.
- **Never run an asset tool in a checkout without this branch's `assets_config.py`** (`tycoon-p5b` until it merges it,
  `main` until L4 W2 merges): an older one writes Assets.json without the new v6 `levels` block, so its next save erases
  the forest's ids (the L3-66 hazard, again).
- `upload_models.py --props --dry-run` **writes `Assets.json`** (it pre-lists the entries, ids 0).
  `upload_level.py --dry-run` writes nothing.
- **Commit `src/shared/Config/Assets.json` and `docs/ASSET_MANIFEST.md` together**, right after the uploads and again
  right after the harvest: the manifest counts both, so `gen_asset_manifest.py --check` is red when they are apart.
- A prop stage whose `modelAssetId` is non-zero is never uploaded again, even when its GLB changed: clear it through
  `assets_config.save_assets` first. Level meshes and images are hash-checked instead: a changed file goes up again by
  itself and its harvested ids are cleared.
- **Geometry is frozen from step 1.** The plan hash (`23851a6f417491c1` since the F2 forest pass, 2026-10-21) moves with the layout,
  `Combat.json levels.fenceThickness`, a stage's `kind`, `zone` or boss point (`at`), the generator's art numbers or a
  forest-kit piece; it no longer moves with a boss's kind, his Valor or any wave number (L4W2-4). If it moves after the
  uploads: steps 1, 4 (only the changed GLBs go up; with none changed, zero uploads and the hash in Assets.json is
  refreshed), then a paste for what went up.
- **Never re-merge the raiders between their upload (step 5) and the paste (step 8).** The harvest checks each raider
  piece against the merge sidecar; a re-merge after the upload makes it refuse those stages (rightly: the uploaded mesh is
  no longer the merged one), and they must then be cleared and uploaded again.
- If a tool or Blender hangs, stop only your own process, by its id. Never by name.

## Steps

- [ ] 1. **The forest build** (Git Bash):
      ```
      ls assets/build/levels/ForestRoad/textures/      # camp.png forestFloor.png road.png roadRim.png
      "/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/levels/forest_textures.py   # only if one is missing
      py tools/levels/forest.py build
      py tools/levels/forest.py check
      git status --short src/shared/Config/LevelDress/
      ```
      - `build` ends with `wrote the upload record ...\assets\build\levels\ForestRoad.json`, `wrote 37 meshes + palette`,
        `wrote ...\src\shared\Config\LevelDress\ForestRoad.json`; `check` ends `check: PASS`. A `note: ... is missing`
        line means a texture is missing: make it (second line), then build again.
      - `planHash` in `src/shared/Config/LevelDress/ForestRoad.json` and in the upload record: `23851a6f417491c1`,
        unless a geometry input changed since the F2 pass (commit f2f7080). `git status` shows no change to the data file (the build is
        byte-identical); a change there is a geometry change: stop and tell the lead.
- [ ] 2. **The raider merge**, from a fresh palette (the palette cache trap):
      ```
      rm -f assets/build/palettes/raider-*.*
      "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/assets/merge_stages.py -- --props --era Raiders
      py tools/testfit/raiderpose.py --check
      py tools/assets/raider_frames.py --check        # D2's tool (contract §3.1), once it exists
      ```
      - `done: 7 blueprint(s), 0 with problems`; 35 GLBs in `assets/build/stages/_props/Raiders/` (`<Model>_S0` … `_S4`)
        and 7 sidecars beside them.
      - The seven, kind → model (kits per stage from the 2026-10-21 merge): fodder `RaiderFodder`, slinger
        `RaiderSlinger`, marksman `RaiderMarksman`, lobber `RaiderLobber`, brute `RaiderBrute` (raider-kit, -cloth,
        -skin); chief `RaiderChief` (+ raider-glow); armoured `RaiderArmoured` (+ raider-plate).
- [ ] 3. **The forest props merge**, from a fresh palette:
      ```
      rm -f assets/build/palettes/forest-kit.*
      "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/assets/merge_stages.py -- --props --era Forest
      ```
      - `done: 4 blueprint(s), 0 with problems`. Three warnings are expected: `geometry 0.08 / 0.30 / 0.26 studs below
        ground` (0.08 on the 2026-10-22 run) on Campfire, ChiefTent and SpawnTent (the pieces sit a little into the ground, like the baked ones).
      - The palette it builds holds the level palette's 56 swatches exactly (F2 report, 2026-10-21), so the props wear the
        baked forest's colours.
- [ ] 4. **Lead: announce, then the level uploads:**
      ```
      py tools/assets/upload_level.py --level ForestRoad --dry-run
      py tools/assets/upload_level.py --level ForestRoad --only Dress_5 --only Hills_2
      py tools/assets/upload_level.py --level ForestRoad
      ```
      - Dry run: 42 `would upload` lines, then `dry run: 42 upload(s) pending (5 image(s), 37 mesh(es)), nothing sent,
        nothing written`. Any `WARNING` line: nothing was uploaded; fix what it names (usually: re-run step 1).
      - The trial, 2 uploads: `Dress_5` has the most triangles (15,854, 1.71 MB, under the Valley's proven 16,037) and
        `Hills_2` the widest box (1,320.6 studs, under the Valley's proven 1,444). An error other than "Unknown Error"
        here: stop and tell the lead.
      - The real run: `ForestRoad: 0 image(s) and 2 mesh(es) already uploaded and unchanged, skipped`, then
        `ForestRoad: uploaded 40/40`. On "Unknown Error", run the same line again: finished uploads are skipped.
      - `Assets.json` becomes v6 (a new top-level `levels` block).
- [ ] 5. **Lead: the props uploads**, then the manifest:
      ```
      py tools/assets/upload_models.py --props --era Forest --dry-run
      py tools/assets/upload_models.py --props --era Forest
      py tools/assets/upload_models.py --props --era Raiders --dry-run
      py tools/assets/upload_models.py --props --era Raiders
      py tools/gen_asset_manifest.py
      ```
      - `dry run: 4 upload(s) prepared, nothing sent`, `uploaded 4/4`; `dry run: 35 upload(s) prepared, nothing sent`,
        `uploaded 35/35`. On "Unknown Error", run the same line again.
      - Longest display names: `EraCityTycoon_Prop_Raiders_RaiderArmoured_S0` (44) and
        `EraCityTycoon_Level_ForestRoad_Image_forestFloor` (48), under Open Cloud's 50.
      - **Commit `Assets.json` and `docs/ASSET_MANIFEST.md` together now.** The manifest gains "Props — Forest",
        "Props — Raiders" and "Levels" tables (absent until these uploads).
- [ ] 6. **Lead: the harvest script**, then put it on the clipboard for Ben:
      ```
      py tools/assets/harvest.py --emit --props && cat tools/assets/harvest.luau | clip
      ```
      - `wrote tools\assets\harvest.luau with 81 asset(s) to harvest`: 39 `prop`, 5 `levelTexture`, 37 `levelMesh`.
        Nothing else was pending on 2026-10-21, so any other count: stop and tell the lead.
      - Commit `harvest.luau`. **Copy it again when Ben says "ready to paste"** (`cat tools/assets/harvest.luau | clip`).
      - A repeat (step 13) emits only the records still missing: fewer than 81 is right then.
- [ ] 7. **Ben: the one harvest paste.** Open the **local** file `C:\Users\benja\Desktop\tycoon\build\test.rbxl` in
      Studio, with File (*Archivo*) → Open (*Abrir*). **Not the published game. Do not press Play.**
      - Why this file: it is a local, unpublished place, and in Edit mode nothing in it runs. The script needs only
        Studio's InsertService, which every place has, so the dungeon files give nothing more. `proving.rbxl` is the
        file you play in: one Play press there would start a run.
      1. View (*Vista*) → **Command Bar** (*Barra de comandos*) → click in it → **Ctrl+V** → Enter → wait for
         `[HARVEST-DONE] 81 loaded, 0 failed` in Output (*Salida*). It takes longer than the last paste: some meshes
         are 1.7 MB.
      2. **Output** (*Salida*) → right-click → **Select All** → **Ctrl+C**.
      3. Tell Claude **"done"**, and nothing else. **Do not paste the Output into the chat, and do not copy anything
         else** before Claude answers: your clipboard holds the result.
      - If the number is not 81 or "failed" is not 0: tell Claude the line as it reads.
- [ ] 8. **Lead: save the clipboard to a file first, count, then merge from the file.**
      ```
      powershell -NoProfile -Command "[IO.File]::WriteAllText('<a scratch file>', (Get-Clipboard -Raw), (New-Object Text.UTF8Encoding $false))"
      grep -c '\[HARVEST\] {' <that scratch file>
      py tools/assets/harvest.py --props --file <that scratch file>
      py tools/gen_asset_manifest.py
      ```
      - The count must be step 6's: 81 the first time. `[HARVEST-FAIL]` appears once in a good Output (the echoed
        script).
      - The merge prints `merged 39 prop stage(s)`, `merged 5 level image(s) and 37 level mesh(es)`, then `every
        uploaded asset is harvested; next: py tools/assets/gen_templates.py --props, then py tools/assets/gen_templates.py
        --levels`, and exits 0.
      - **No `SIZE CHECK:`, `FRAME:` or `ROTATED:` line.** Each refuses what it names, merges the rest and exits 1:
        - `SIZE CHECK: level ForestRoad <Mesh>`: Studio's size is not the baked one, so the importer rescaled it;
        - `FRAME: props/Raiders/<Model> S<n>`: a raider piece is not where the merge put it (or its sidecar is gone);
        - `ROTATED: props/Raiders/...` (or `Weapons`): a MeshPart came in rotated.
        Any of them: stop the run here, write no templates, send the lead the printed lines, never re-upload.
      - A texture still in moderation prints `level ForestRoad image <name>: no Decal Texture ... (still in
        moderation?)`. The meshes that wear it get no template, so **the whole forest stays grey** (the server's rule is
        all or nothing). Repeat steps 6 to 8 later for it; never the uploaders.
      - **Commit `Assets.json` and `docs/ASSET_MANIFEST.md` together now.**
- [ ] 9. **Lead: the proofs on the real harvest, before any template:**
      ```
      py tools/assets/raider_frames.py --check --require-harvest      # D2's tool (contract §3.1)
      py tools/assets/weapon_frames.py --check --require-harvest      # unchanged: 15 of 15
      ```
      - The harvest already refused any raider piece off its merged frame (step 8); `raider_frames.py` proves the
        config's points through the same turn.
- [ ] 10. **Lead: templates and manifest.**
      ```
      py tools/assets/gen_templates.py --props
      py tools/assets/gen_templates.py --levels
      py tools/assets/gen_templates.py --check
      py tools/gen_asset_manifest.py
      py tools/gen_asset_manifest.py --check
      ```
      - `297 prop template(s): 11 written, 286 unchanged, 0 removed`, `37 level template(s): 37 written, 0 unchanged,
        0 removed`, then `CHECK: PASS -- 617 template(s) up to date` (569 before).
      - New: `templates/_props/Forest/<Piece>.rbxmx` (4), `templates/_props/Raiders/<Model>.rbxmx` (7: Base and
        Stage0..Stage4, one MeshPart per kit), `templates/_levels/ForestRoad/<Mesh>.rbxmx` (37: a Model holding one
        MeshPart `Mesh`, already in the level frame).
      - The manifest reads 4/4 for Forest and 7/7 for Raiders on every column, and `ForestRoad | 23851a6f417491c1 | 37
        | 159046 | 5/5 | 5/5 | 37/37 | 37/37 | 37/37 | in game` (159,046 = the meshes' triangles; with the props the
        level is 163,647).
- [ ] 11. **Lead: the project files**, if not done yet (proved with a scratch Rojo build, pipeline report §4):
      - `combat.project.json`: `"templates/_levels"` appended to `globIgnorePaths`, and under
        `ReplicatedStorage.Assets`, beside `Props`:
        ```
        "Levels": {
            "$className": "Folder",
            "$path": { "optional": "templates/_levels" }
        }
        ```
        (`.proving.project.json` is generated from it by `tools/proving_project.py`.)
      - `default.project.json`, `orbital.project.json`, `boomtown.project.json`, `metropolis.project.json`:
        `"templates/_levels"` appended to `globIgnorePaths`, nothing else. Without it the hub's
        `ServerStorage.Assets` (`$path: templates`) takes `_levels` in as a folder of 37 models.
- [ ] 12. **Lead: sourcemaps and the six place files** (Git Bash, in `tycoon-p5`):
      ```
      export PATH="$HOME/.rokit/bin:$PATH"
      rojo sourcemap default.project.json -o sourcemap.json
      rojo sourcemap combat.project.json -o sourcemap.combat.json
      rojo build -o build/test.rbxl
      rojo build combat.project.json -o build/combat.rbxl
      py tools/proving_project.py && rojo build .proving.project.json -o build/proving.rbxl
      rojo build boomtown.project.json -o build/boomtown.rbxl
      rojo build metropolis.project.json -o build/metropolis.rbxl
      rojo build orbital.project.json -o build/orbital.rbxl
      ```
      Commit the templates, the manifest, `harvest.luau`, the sourcemaps and the place files.
- 13. **If a record goes missing later:** repeat steps 6 to 10 only. Do **not** re-run the uploaders.

## What the templates are (for the reviewers)

- **Level meshes** (`gen_templates.level_template_xml`): sealed (Anchored; CanCollide, CanQuery, CanTouch false),
  SmoothPlastic, white, TextureID = the level's palette or the ground texture the mesh names; `RenderFidelity` and
  `CastShadow` by the mesh's group (`LEVEL_GROUP_DRAW`): ground and skin Precise, no shadow; camp Precise, shadow; rock,
  dress and canopy Automatic, shadow; backdrop Automatic, no shadow. RenderFidelity cannot be set by a game script;
  CastShadow can. The CFrame is the harvested offset through the importer's turn, so a clone sits where the generator
  baked it.
- **Props** (Forest, Raiders): the usual prop shape (Base, Stage0..4, one MeshPart per kit, CanCollide/CanQuery false).
  The raiders' painted MeshParts keep the kits' one-swatch palette as TextureID; the client clears it per clone (L4W2-10).
