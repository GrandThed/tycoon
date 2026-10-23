# L4 W2, track P: the asset route for the forest and the raiders (pipeline engineer's report)

Worktree `tycoon-p5`, branch `l4-real-forest`, 2026-10-21. **Not committed. Nothing uploaded, nothing harvested
against Roblox.** `src/shared/Config/Assets.json`, `templates/`, `tools/assets/harvest.luau` and
`docs/ASSET_MANIFEST.md` are untouched (`git diff --stat` empty for all four; Assets.json md5 `aa75f8c6…` before and
after every proof). Every proof ran on scratch copies in my session scratchpad. Python: the repo tools with a
`#!/usr/bin/env python` line ran under 3.12 (64-bit, via `py`), everything else, my proof drivers included, under 3.14.
The runbook is `docs/prompts/l4-w2-asset-run.md`.

## 1. Summary

- **The route is ready and proven offline end to end:** forest build → upload record → `upload_level.py` (new) →
  props uploads → `harvest.py --emit --props` → a stubbed Studio running the real emitted script under `luau.exe` →
  the merge → `gen_templates.py --levels` / `--props` → `--check` → manifest → a Rojo build of the proposed combat tree.
  **82 uploads and one paste of 82 records:** 38 level meshes, 5 level images, 4 forest props, 35 raider stages. The
  raider builder had all seven kinds merged by the final run.
- **The lead's three forest.py items (L4W2-1, -4, -5) landed:**
  - The plan hash is narrowed: a boss rename or a Valor change no longer moves it. Proven by 9 cases.
  - The data file moved to `src/shared/Config/LevelDress/ForestRoad.json`. The old `tools/levels/out/` file is deleted
    and `git grep 'ForestRoad\.dress\.json' -- src tools` is empty.
  - `hide.camps` uses LevelGeometry's role names.
  - The hash changed once: `45565907cbd38bab` → **`5a954ad6ec3b9853`**. Every GLB and the palette are byte-identical.
- **Negative proofs: 32 of 32 mutants caught.** A regression check shows today's `harvest.py` and HEAD's merge the
  Valley and weapon pastes (good and mutated) into identical bytes with identical exit codes.
- **One correction to the contract.** §2.5 says "the hub gets nothing", but the four hub project files need
  `templates/_levels` in `globIgnorePaths`. Without it the hub's `ServerStorage.Assets` takes `_levels` in. Proven by
  sourcemaps (§4).

## 2. Changes per file

| File | Change |
|---|---|
| `tools/assets/assets_config.py` | v6 `levels` block: `ensure_level`, `ensure_level_image`, `ensure_level_mesh`, `level_mesh_image`, `render_level`, `pending_level_images`, `pending_level_meshes`; constants `LEVELS_KEY`, `LEVEL_LOOK_*`, `LEVEL_PALETTE_IMAGE`. A file becomes v6 only once it carries a level. The real Assets.json round-trips byte for byte. |
| `tools/assets/upload_level.py` (new, 363 lines) | The level uploader (the Valley route with a map of images). Input: the upload record `assets/build/levels/<Level>.json`. It refuses, before anything is sent: a sha256 mismatch, the frozen GLB shape, triangles, bounds, a non-opaque image, a wrong-size image, an image over 1024 px, an unknown group (no draw rule), a texture no record lists, an image no mesh wears, a display name over 50 even with `ECT_`, a bad planHash, no palette. `--dry-run` writes nothing. Hash-checked re-uploads clear the harvested ids; stale meshes and images are dropped. `--only` names meshes. |
| `tools/assets/upload_world.py` | `glb_problems` also accepts the `texture` look's UVs; `palette_problems(..., what)` wording. The Valley's behaviour is unchanged. |
| `tools/assets/harvest.py` | New kinds `levelMesh` and `levelTexture` in both modes (emit, the Luau Decal branch, an `image` field, merges, `list_missing`, the next-step hint `--levels`). Level meshes get the Valley's size check against the upload record (`--level-bake-root`): exit 1 and not merged. `merge_world_mesh` is factored into `merge_baked_mesh`, with byte-identical results. **Raiders get the weapons' rotation refusal plus a frame check:** each MeshPart's harvested size and offset must equal its kit's sidecar size and centre through the turn, to 0.01. Otherwise, or with no sidecar, the stage is refused with a `FRAME:` line and exit 1 (`--build-root`). |
| `tools/assets/gen_templates.py` | `--levels` writes `templates/_levels/<Level>/<Mesh>.rbxmx` (the world shape, one MeshPart `Mesh`). TextureID is the image the mesh wears. `LEVEL_GROUP_DRAW` sets RenderFidelity and CastShadow per group (§5). `--check` covers five trees. `_levels` is in `GROUP_DIRNAMES`, so the buildings tree never reads it as an era. Repo `--check`: PASS 569, unchanged. |
| `tools/gen_asset_manifest.py` | A "Levels" table, and one "Props — <Folder>" table per non-era prop folder (Raiders, Forest). Each is absent until Assets.json lists it, so the committed manifest is byte-identical today; `--check` PASS. |
| `tools/levels/forest.py` | Writes the upload record (`upload_record`): files relative to the out-root, sha256 of every GLB and PNG, each GLB's own float32 bounds as size and centre, look, texture, group, planHash. A texture missing at build time is listed unhashed. **L4W2-4:** `stage_geometry` hashes only each stage's `kind`, `zone` and boss `at`s. **L4W2-1:** the data file defaults to `src/shared/Config/LevelDress/<layout>.json`. **L4W2-5:** `hide.camps` roles are `floor`, `fence`, `obstacle`, `fire`, `tent`. `check` output is byte-identical before and after the record change. |
| `src/shared/Config/LevelDress/ForestRoad.json` (new, generated, 35,870 bytes) | The dress data at its contract location. Against the old file only `planHash` and `hide.camps` differ. Rojo makes it `ReplicatedStorage.Shared.Config.LevelDress.ForestRoad`, a ModuleScript; both builds pass. |
| `tools/levels/out/ForestRoad.dress.json` | **Deleted** (L4W2-1). |
| `tools/testfit/levelrender.py` | **Outside my list, routed by the lead's move:** the one `--data` default now points at the new file. `--counts` reproduces forest.md's numbers. |
| `tools/levels/README.md` | **Outside my list:** two lines name the new data file and the upload record. |
| `tools/testfit/blueprints/_props/Forest/{Bramble,Campfire,ChiefTent,SpawnTent}.json` (new) | **Outside my list. The route needs them and nobody owned them.** Each is one forest-kit piece at the origin, scale 1, footprint from the piece's extents. A scratch merge gives 4 of 4 with 0 problems. |
| `docs/prompts/l4-w2-asset-run.md` (new) | The runbook. |

## 3. The proofs (scratch only)

1. **Build.**
   - `forest.py build --out-root <scratch>` is byte-identical to the shared bake: 38 GLBs and the palette. The data
     file was identical to the committed one before L4W2-1/-4/-5; after them, only `planHash` and `hide.camps`
     changed.
   - The real build afterwards rewrote the 39 shared files byte for byte, and `check` PASSES.
   - The scratch and real upload records are equal.
2. **Upload record.**
   - `upload_level.py --dry-run` on the real record: `43 upload(s) pending (5 image(s), 38 mesh(es))`, nothing
     written.
   - The longest display name is `EraCityTycoon_Level_ForestRoad_Image_forestFloor` (48).
3. **Real-run path, network stubbed.**
   - `upload_level.main` sent 5 decals and 38 models.
   - A second run sent 0 (idempotent).
4. **Props.** Pre-listed exactly as `upload_models.upload_props` does: `ensure_prop`, `prefill_parts` from the
   sidecars, a fake id per stage. `upload_models.py` itself was not run. 39 stages, the longest name
   `EraCityTycoon_Prop_Raiders_RaiderArmoured_S0` (44).
5. **Harvest emit.** `harvest.py --emit --props` emitted 82 records: 39 prop, 5 levelTexture, 38 levelMesh.
6. **Stubbed Studio.**
   - A Luau prelude stood in for InsertService, HttpService and Vector3. It returned one asset per id, built from
     known importer behaviour: Size = the bounds, offset = the centre with x and z negated, identity rotation, a
     Decal's Texture = its image.
   - It ran the emitted script under `luau.exe`: `[HARVEST-DONE] 82 loaded, 0 failed`.
   - The saved Output holds 82 `[HARVEST] {` lines.
7. **Merge.** `harvest.py --props --file`: `merged 39 prop stage(s)`, `merged 5 level image(s) and 38 level
   mesh(es)`, `every uploaded asset is harvested`, exit 0. The scratch Assets.json equals the real one plus `levels`
   and `props.Forest` / `props.Raiders`, nothing else.
8. **Templates.**
   - `--levels`: 38 written. `--props`: 11 written, 286 unchanged. `--check`: PASS 618.
   - The Floor template's CFrame is (−48, 34.0468, 20), the baked centre, with R00 = R22 = −1.
9. **Rojo.** A scratch copy of `combat.project.json` with the proposed lines builds. Its sourcemap holds
   `ReplicatedStorage.Assets.Levels.ForestRoad` (38 Models, each with one MeshPart `Mesh`), `Props.Forest` (4) and
   `Props.Raiders` (7, Base and Stage0..4). The hub builds with the new Config file.
10. **Manifest.** Forest 4/4, Raiders 7/7, ForestRoad `5a954ad6ec3b9853 | 38 | 144656 | 5/5 | 5/5 | 38/38 | 38/38 |
    38/38 | in game`. `--check` PASS on the scratch state and on the repo.
11. **Mutants, 32 of 32 caught.**
    - U1–U16, the uploader: a changed GLB, size, centre, triangles, unknown group, unhashed texture, unworn image,
      a `flat` look, an unlisted texture, alpha, wrong size, 2048 px, a 52-character name, a bad hash, no palette,
      a missing GLB. Plus: the dry runs wrote nothing.
    - R1–R2, the real run: a changed mesh and image go up again with their ids cleared; stale entries are dropped.
    - H1–H9, the harvest: a 1% rescale; a raider piece 0.05 off; a rotated raider; no sidecars (35 of 35 refused); a
      texture in moderation (warned, and its mesh gets no template); a stale paste; a rotated forest prop (a warning
      only); a level rebuilt since the upload; two MeshParts.
    - G1–G2, the templates: a stale and a stray level template; an unknown group.
    - M1, the manifest: "awaiting harvest".
12. **Regression.** Valley and weapon pastes built from disk, good and mutated, through HEAD's `harvest.py` and
    today's, plain and `--props`: identical Assets.json bytes and exit codes in all 6 runs. Emit on the real
    Assets.json (`--all`, both modes) differs from HEAD's only in the Luau template lines.
13. **Hash narrowing.** These keep `5a954ad6ec3b9853`: the boss renamed to `chief`, Valor 10 → 25, camp C's pacing, a
    group added to a wave, the level's name and targetMinutes. These move it: the boss point, a zone, a stage kind,
    an added stage.
14. **Forest props merge.** A scratch Blender merge: 4 of 4, 0 problems. The forest-kit palette it built has exactly
    the level palette's 55 sRGB swatches.

## 4. Proposed project-file lines (the lead edits them)

- `combat.project.json` (`.proving.project.json` follows through `proving_project.py`):
  ```
  "globIgnorePaths": ["templates/_props", "templates/_paths", "templates/_enemies", "templates/_world", "templates/_levels"],
  ...
  "Assets": {
      "$className": "Folder",
      "Props": { "$className": "Folder", "$path": { "optional": "templates/_props" } },
      "Levels": { "$className": "Folder", "$path": { "optional": "templates/_levels" } }
  }
  ```
- `default.project.json`, `orbital.project.json`, `boomtown.project.json`, `metropolis.project.json`: append
  `"templates/_levels"` to `globIgnorePaths`, nothing else.
  - Proven with two scratch hub sourcemaps: without the line `ServerStorage.Assets` holds `_levels`; with it, it does
    not.
  - This corrects the contract's §2.5 "the hub gets nothing".

## 5. Decisions taken here (the lead may overrule)

- **The `levels` block.** `levels.<layout> = { planHash, triangles, images: { <name>: { assetId, imageId, sha256 } },
  meshes: { <name>: { assetId, meshId, size, offset, sha256, triangles, look, texture?, group } } }`. The palette is
  the image named `palette`. This matches the contract's `AssetsConfig.levels[layout].planHash`.
- **Template drawing per group (`LEVEL_GROUP_DRAW`).**
  - ground and skin: Precise, no shadow. The skins lie 0.03–0.09 over the floor, and two decimated layers would
    flicker into each other.
  - camp: Precise, shadow.
  - rock, dress and canopy: Automatic, so mesh LODs carry about 120k triangles; with shadow.
  - backdrop: Automatic, no shadow.
  - RenderFidelity is not scriptable, so it must be right in the template. CastShadow the client may turn off.
- **The first level upload is a trial** of `Dress_4` (14,201 triangles, the most) and `Hills_1` (1,496 studs, past the
  Valley's proven 1,444 and under Roblox's 2,048 part limit).
- **The paste goes in `C:\Users\benja\Desktop\tycoon\build\test.rbxl`, Edit mode.** It is local and unpublished,
  nothing in it runs in Edit mode, and it is the file of the L3 paste. The script needs only InsertService.
  `proving.rbxl` is where Ben plays: one Play press there starts a run.
- **Painted raider parts keep their one-swatch TextureID in the template.** L4W2-10 has the client clear it.

## 6. Risks

1. **Moderation can turn the forest grey.** A ground texture held in moderation leaves its meshes without templates,
   so the all-or-nothing server keeps the whole level grey until a repeat paste (steps 6–8).
2. **Automatic LOD on 192-stud dress chunks is unmeasured.** If LOD is chosen by distance to a big part's centre,
   near trees inside a far-centred chunk could decimate. This is a Studio judgement; a one-line `LEVEL_GROUP_DRAW`
   change makes a group Precise (a template regeneration, no upload).
3. **Size tolerance is loose on big meshes.** The shared size tolerance is `max(0.01, 0.1%)` per axis (the Valley's),
   so on the 1,056-stud floor it catches a real rescale but not a sub-stud error. Placement uses the harvested offset,
   which is only warned about, as for the Valley.
4. **A raider re-merge between upload and paste** makes the harvest refuse those stages (rightly). They then need their
   `modelAssetId` cleared and a re-upload; the runbook forbids it.
5. **An older `assets_config.py` erases `levels`.** Any checkout with an older one, `tycoon-p5b` and `main` until they
   merge this, drops the new block on its next save.
6. **The plan hash still moves with the layout, the fence thickness, a stage's kind, zone or boss point, the art
   numbers and the kit.** If one changes after the uploads: rebuild, then `upload_level.py`. It sends only the changed
   GLBs, or none and refreshes the hash, followed by a paste for what went up.
7. **Never run in Studio.** The real Studio import of 1.5 MB / 14k-triangle meshes, Decal moderation, and the raider
   frame check against real importer offsets. The stubbed Studio encodes the known importer behaviour, not a fresh
   observation.
8. **Not mine, still open.**
   - `raider_frames.py` (D2) does not exist yet; the runbook names it where it belongs.
   - `forestcheck.py`'s "stale" text still says "re-bake, re-upload, one paste", which is right.
   - D2 takes `forest.py` over at W2 start.

## 7. Scratch tools (session-temporary, not in the repo)

The scratch folder is
`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\3f855f00-eb33-4bab-adb5-c937f685030c\scratchpad\p\`.

In `prove\`:
- `chain.py`: the forward chain.
- `stubs.luau`: the stubbed Studio.
- `mutants.py`: the 32 mutants.
- `regress.py`: HEAD against today.
- `hash_narrow.py`: the hash cases.
- `projects.py`: the scratch Rojo projects.

Run any of them as `py <script> C:\Users\benja\Desktop\tycoon-p5 <scratch>`, after a scratch `forest.py build
--out-root <scratch>\levels` and a copy of the raider sidecars into `<scratch>\build`.
