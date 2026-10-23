# L4 W2 — the asset run, steps 1 to 6 (uploader's report)

Worktree `tycoon-p5`, branch `l4-real-forest` (HEAD 74bf437, one docs commit past f2f7080), 2026-10-22. **Not committed.**
Every upload went through on the first try: **81 of 81 uploaded, no retries, no "Unknown Error"**. Stopped before step 7
(Ben's paste). Not run: the harvest merge, templates, the manifest after the harvest, the project files, the place files.

## Summary

- **The runbook was updated first**, to the F2 numbers (`forest2.md`, last section): plan hash `23851a6f417491c1`,
  81 uploads and 81 records, 37 meshes, the trial on `Dress_5` + `Hills_2`, 40/40 after the trial, 617 templates, the
  manifest line, 56 swatches, "37 models".
  - It also fixes one stale reference: "a repeat (step 12)" now reads step 13.
  - It records the Campfire warning as 0.08 (the old text said 0.05).
- **`tools/assets/harvest.luau` holds exactly 81 records:** 39 `prop`, 5 `levelTexture`, 37 `levelMesh`.
  - Every record has a non-zero id. The 81 ids are distinct.
  - Every id is one of the new Assets.json upload ids.
- **The `Assets.json` diff adds entries only.** The only changed value is `version` 5 → 6.
  - It adds three subtrees: `props.Forest` (4), `props.Raiders` (7 models, 35 stages) and `levels.ForestRoad`. Nothing
    was removed.
  - All 81 upload ids (39 `modelAssetId`, 42 `assetId`) are non-zero.
  - The zeros left are the `meshId`/`imageId` fields that the harvest fills in.
- **One file changed that your check list did not name: `docs/ASSET_MANIFEST.md`.** The runbook's step 5 regenerates it
  after the uploads, and its rules say to commit it together with `Assets.json`, otherwise `gen_asset_manifest.py --check`
  goes red.
  - It gains the "Props — Forest", "Props — Raiders" and "Levels" tables.
  - `--check` reads `CHECK: PASS -- configs valid, manifest up to date`.
  - To keep it out, revert it with `git checkout docs/ASSET_MANIFEST.md`, then regenerate it after the harvest.
- **Changed files:** the runbook, `Assets.json`, `harvest.luau`, `ASSET_MANIFEST.md`, and this report (new).
  - The forest build left `src/shared/Config/LevelDress/ForestRoad.json` byte-identical.
  - Gitignored outputs were rewritten by their tools, as expected: the 37 GLBs, the palettes, 35 raider GLBs and 7
    sidecars, 4 forest-prop GLBs and their sidecars.

## Commands and their key lines

| # | Command | Key output |
|---|---|---|
| 1 | `ls assets/build/levels/ForestRoad/textures/` | camp.png forestFloor.png road.png roadRim.png (none missing; `forest_textures.py` not run) |
| 1 | `py tools/levels/forest.py build` (about 20 s) | `wrote the upload record ...\assets\build\levels\ForestRoad.json`, `wrote 37 meshes + palette ...`, `wrote ...\src\shared\Config\LevelDress\ForestRoad.json`; no `note:` line |
| 1 | `py tools/levels/forest.py check` | `[forest] check: PASS` |
| 1 | `git status --short src/shared/Config/LevelDress/` | empty (byte-identical); `planHash` `23851a6f417491c1` in the data file and in the upload record |
| 2 | `rm -f assets/build/palettes/raider-*.*`, then `blender -b -P tools/assets/merge_stages.py -- --props --era Raiders` | `done: 7 blueprint(s), 0 with problems`, exit 0; 35 GLBs + 7 sidecars in `assets/build/stages/_props/Raiders/`; palettes raider-kit 25 swatches, cloth/skin/glow/plate 1 each |
| 2 | `py tools/testfit/raiderpose.py --check` | exit 0, no FAIL; `head rule PASS` for all seven, `config posedReach matches` for each |
| 2 | `py tools/assets/raider_frames.py --check` | **not run: the file does not exist yet** (the runbook says "once it exists") |
| 3 | `rm -f assets/build/palettes/forest-kit.*`, then `blender ... --props --era Forest` | `done: 4 blueprint(s), 0 with problems`; the three expected warnings: Campfire **0.08** (runbook had 0.05), ChiefTent 0.30, SpawnTent 0.26 studs below ground; palette 56 swatches |
| 4 | `py tools/assets/upload_level.py --level ForestRoad --dry-run` | 42 `would upload` lines; `dry run: 42 upload(s) pending (5 image(s), 37 mesh(es)), nothing sent, nothing written`; no WARNING |
| 4 | `... --only Dress_5 --only Hills_2` (the trial) | `Dress_5: OK -> 99605376274353` (1,673 KB, about 10 s processing), `Hills_2: OK -> 88452613378565`, `uploaded 2/2` |
| 4 | `py tools/assets/upload_level.py --level ForestRoad` | `0 image(s) and 2 mesh(es) already uploaded and unchanged, skipped`, then `ForestRoad: uploaded 40/40` |
| 4 | (check) | `Assets.json` v6, `levels.ForestRoad`: planHash `23851a6f417491c1`, triangles 159046, 5 images, 37 meshes |
| 5 | `py tools/assets/upload_models.py --props --era Forest --dry-run` | `pre-listed: 4 Forest prop(s)`, `dry run: 4 upload(s) prepared, nothing sent` |
| 5 | `py tools/assets/upload_models.py --props --era Forest` | `uploaded 4/4`; the `levels` block survived the save (still v6) |
| 5 | `py tools/assets/upload_models.py --props --era Raiders --dry-run` | `pre-listed: 7 Raiders prop(s)`, `dry run: 35 upload(s) prepared, nothing sent` |
| 5 | `py tools/assets/upload_models.py --props --era Raiders` | `uploaded 35/35` |
| 5 | `py tools/gen_asset_manifest.py` | `wrote docs\ASSET_MANIFEST.md: 4 eras, 96 models`; Forest 4/4 uploaded, Raiders 7/7, `ForestRoad \| 23851a6f417491c1 \| 37 \| 159046 \| 5/5 \| 0/5 \| 37/37 \| 0/37 \| 0/37 \| uploaded, awaiting harvest` |
| 6 | `py tools/assets/harvest.py --emit --props` | `wrote tools\assets\harvest.luau with 81 asset(s) to harvest` |

**Longest display names:**
- `EraCityTycoon_Level_ForestRoad_Image_forestFloor`: 48 characters.
- `EraCityTycoon_Prop_Raiders_RaiderMarksman_S4` and the RaiderArmoured ones: 44 characters.

Both are under the 50 cap.

**Not done on purpose:** the `| clip` half of step 6. Ben's clipboard is untouched. When he says "ready to paste",
copy the script for him with this line, from `tycoon-p5`:

```
cat tools/assets/harvest.luau | clip
```

## What Ben does (runbook step 7)

Open the **local** file `C:\Users\benja\Desktop\tycoon\build\test.rbxl` in Studio, with File (*Archivo*) → Open
(*Abrir*). It exists, dated 2026-10-21 09:24.
- It is **not the published game**.
- **Do not press Play.**
- The script needs only InsertService, so the main checkout's hub file is right. `proving.rbxl` is the wrong file: one
  Play press there starts a run.

Then:
1. Go to View (*Vista*) → **Command Bar** (*Barra de comandos*) and click in it.
2. Press **Ctrl+V**, then Enter.
3. Wait for `[HARVEST-DONE] 81 loaded, 0 failed` in Output (*Salida*). It is slower than the last paste: Dress_5 is
   1.7 MB.
4. In **Output** (*Salida*), right-click → **Select All**, then **Ctrl+C**.
5. Tell Claude **"done"** and nothing else. Do not paste the Output into the chat and do not copy anything else: his
   clipboard holds the result.

If the line does not read 81 loaded and 0 failed, he tells Claude the line as it reads.

**Then step 8 for the lead:**
1. Save the clipboard to a file first.
2. Count with `grep -c '\[HARVEST\] {'`. It must be 81. `[HARVEST-FAIL]` appearing once is normal: it is the echoed
   script.
3. Run `harvest.py --props --file`.

## What surprised me (small)

- **`raider_frames.py` still does not exist.** Step 2 skips it. Step 9 also wants `raider_frames.py --check
  --require-harvest` before any template, so that proof needs D2's tool, or a ruling from the lead, before step 10.
- **The props' palette PNG is not byte-identical to the level's `palette.png`.** Decoded, both hold the same 56 colours
  (128 × 112), in a different arrangement. That fits the runbook's "holds the level palette's swatches", so it is not a
  problem.
- **The Campfire warning reads 0.08 studs**, against the runbook's 0.05. The F2 report says the props have not changed
  since the rocks pass, so the 0.05 was probably measured before that pass. The runbook now says 0.08.
- The raider "stages" are body parts, not growth stages: S3 and S4 are 68 to 90 triangles each. That matches the
  contract's Base + Stage0..4 shape and is noted here so nobody mistakes it for a bad merge.
