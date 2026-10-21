# L3 W2 — pipeline engineer's report (2026-10-21)

Row: **Pipeline engineer** (contract §8; L3-40 to L3-47, L3-45; the lead's ruling 3: icons 256 × 256).
Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-w2`. Nothing committed. Nothing uploaded, no
real harvest, no dry run against the real `Assets.json`; the real `Assets.json`, `templates/` and
`tools/assets/harvest.luau` are byte-identical to `eb1c25c` (guarded by hash in the chain below).

## Done when: all three gates pass

```
py tools/assets/weapon_frames.py --check     CHECK: PASS -- src/shared/Config/WeaponModels.json up to date; turn proof holds
py tools/assets/gen_templates.py --check     CHECK: PASS -- 554 template(s) up to date
py tools/gen_asset_manifest.py --check       CHECK: PASS -- configs valid, manifest up to date
```

## First deliverable: `src/shared/Config/WeaponModels.json`

**Landed 2026-10-20 23:55** (local time), before anything else: 15 families, 63 points, the L3-46 shape
exactly (families and points sorted, every number list on one line, `bounds` as
`{ "min": [...], "max": [...] }` on one line, two-space indent, LF). Every `model` is the family id
with its first letter capitalised (`frostHammer` → `FrostHammer`, `smg` → `Smg`, `rifle` → `Rifle`,
`chaingun` → `Chaingun`). Extras present: `bladeBase` (broadsword, spear, spinblade), `nock`
(longbow, splitbow), `splitUp`/`splitDown` (splitbow), `support` (beam, chaingun, launcher, rifle,
shotgun, smg), `sight` (rifle), `head` (frostHammer, warhammer), `edge` (greataxe), `pilot`
(flamethrower). Unchanged since it landed (the re-merge left the sidecars byte-identical).

## Files (my row only)

| File | What |
|---|---|
| `tools/assets/weapon_frames.py` (new) | writes `WeaponModels.json` (L3-46: every refusal rule), `--check` (diff, or "frame files absent: shape checked only"), the turn proof (L3-47), `--require-harvest` for the post-paste step |
| `src/shared/Config/WeaponModels.json` (new, generated) | the config |
| `tools/assets/fixtures/turn_proof.json` (new) | real Studio data: Boomtown `LampPost` (the contract's) and Village `BushA` (off both axes, so a missing x turn is caught too) |
| `tools/assets/fixtures/harvest_weapons_sample.txt` (new) | 15 `prop` + 15 `icon` records, fake ids (rule in its header), offsets = sidecar centre with x and z negated, sizes = the sidecar's |
| `tools/assets/upload_icons.py` (new) | `--make` (the 256 set from the 512 renders, Pillow LANCZOS, alpha kept), `--dry-run` (writes nothing), the upload; `icon_problems` decodes PNG in plain Python |
| `tools/assets/gen_templates.py` | `template_placement(offset, lift)` pulled out of `harvested_cframe`; `coordinate_frame` takes a rotation matrix (`IDENTITY`, `TEMPLATE_TURN`). Bytes unchanged: `--check` 554 up to date |
| `tools/assets/assets_config.py` | v5 `icons` block: `ensure_icon`, `pending_icons`, `render_icon` (`assetId`, `imageId`, `sha256`; sets and models sorted). The real file still round-trips byte for byte |
| `tools/assets/harvest.py` | kind `icon` in both modes: emit, the Luau Decal branch, `merge_icon` (image 0 = "still in moderation?", warned, skipped), `list_missing` |
| `tools/assets/upload_models.py` | props description: "Era City Tycoon prop '<P>' (<Era>) stage N; kits: weapon-kit." (no Kenney CC0 claim; new uploads only) |
| `tools/gen_asset_manifest.py` | "Weapons" section (when `WeaponModels.json` exists); `mask_volatile` now masks the GLB cell per table header (identical result on the committed manifest: 371 rows masked either way) |
| `docs/ASSET_MANIFEST.md` | regenerated: Weapons table, all "not yet" (15/15 blueprints, GLB 1/1 each) |
| `tools/testfit/README.md` | "In the game (L3 W2)": the config, the frame proof, the models route, the icons route, the palette result |
| `docs/MANUAL_STEPS.md` | "## L3 W2 — the asset run" (before M10), steps 1–12 in the shape of M12 §19 |

## The fresh palette and the re-merge (L3-41): nothing moved

Deleted `assets/build/palettes/weapon-kit.{json,png}` (a copy kept in my scratch), re-merged all 15
(`done: 15 blueprint(s), 0 with problems`, 56 swatches). Result: **the palette PNG, all 15 GLBs and
all 15 sidecars are byte-identical** to the 10:37–11:32 merge; only the palette cache's `sourceFiles`
went 3 → 16. So the cache trap did not bite: `palette-card.glb` kept the old cache whole. The 15
"geometry N studs below ground" warnings are expected (the grip is the origin).

## The 256 px icons (ruling 3)

`py tools/assets/upload_icons.py --set Weapons --make` → 15 files in
`assets/testfit/out/Weapons/icons256/`, 21–46 KB each, 503 KB in all. Every one passes
`icon_problems`; the plain-Python decoder equals Pillow's pixel for pixel on all 30 files (256 and
512), and all five PNG row filters round-trip on a synthetic image. Negative cases caught: RGB,
512 × 512, an opaque corner, an empty image, nothing fully opaque, a palette PNG, not a PNG, a bad CRC.

## L3-44 transcript (scratch only)

Run by `bash <scratch>/chain.sh`; scratch = `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\f6c03e29-23c5-4dc8-ba99-ba7296a3858e\scratchpad\pipeline\chain`.

```
### guard before: the real files
47f0b2ad5235800e24661edaf6132a68c7e8d2f2f1afd801af8b871dc9f3142b *src/shared/Config/Assets.json
c5551ed0895fe3c8b8173e002469e4b7afe9e08796ad128fce5b6e0f4ac88c0e *tools/assets/harvest.luau
ef83a680f014233e916ac74c326ed94129478be9be4326d49469baacbce13d8e *templates/ (all files)

### 1. copy Assets.json to the scratch folder
47f0b2ad5235800e24661edaf6132a68c7e8d2f2f1afd801af8b871dc9f3142b */c/Users/benja/AppData/Local/Temp/claude/c--Users-benja-Desktop-tycoon/f6c03e29-23c5-4dc8-ba99-ba7296a3858e/scratchpad/pipeline/chain/Assets.json

### 2. upload_models.py --props --era Weapons --dry-run --assets-json <scratch>/Assets.json
[upload] Assets.json pre-listed: 15 Weapons prop(s)
[upload] would upload props/Weapons/Beam S0            <- assets\build\stages\_props\Weapons\Beam_S0.glb as EraCityTycoon_Prop_Weapons_Beam_S0
[upload] would upload props/Weapons/Broadsword S0      <- assets\build\stages\_props\Weapons\Broadsword_S0.glb as EraCityTycoon_Prop_Weapons_Broadsword_S0
[upload] would upload props/Weapons/Chaingun S0        <- assets\build\stages\_props\Weapons\Chaingun_S0.glb as EraCityTycoon_Prop_Weapons_Chaingun_S0
[upload] would upload props/Weapons/Flamethrower S0    <- assets\build\stages\_props\Weapons\Flamethrower_S0.glb as EraCityTycoon_Prop_Weapons_Flamethrower_S0
[upload] would upload props/Weapons/FrostHammer S0     <- assets\build\stages\_props\Weapons\FrostHammer_S0.glb as EraCityTycoon_Prop_Weapons_FrostHammer_S0
[upload] would upload props/Weapons/Greataxe S0        <- assets\build\stages\_props\Weapons\Greataxe_S0.glb as EraCityTycoon_Prop_Weapons_Greataxe_S0
[upload] would upload props/Weapons/Launcher S0        <- assets\build\stages\_props\Weapons\Launcher_S0.glb as EraCityTycoon_Prop_Weapons_Launcher_S0
[upload] would upload props/Weapons/Longbow S0         <- assets\build\stages\_props\Weapons\Longbow_S0.glb as EraCityTycoon_Prop_Weapons_Longbow_S0
[upload] would upload props/Weapons/Rifle S0           <- assets\build\stages\_props\Weapons\Rifle_S0.glb as EraCityTycoon_Prop_Weapons_Rifle_S0
[upload] would upload props/Weapons/Shotgun S0         <- assets\build\stages\_props\Weapons\Shotgun_S0.glb as EraCityTycoon_Prop_Weapons_Shotgun_S0
[upload] would upload props/Weapons/Smg S0             <- assets\build\stages\_props\Weapons\Smg_S0.glb as EraCityTycoon_Prop_Weapons_Smg_S0
[upload] would upload props/Weapons/Spear S0           <- assets\build\stages\_props\Weapons\Spear_S0.glb as EraCityTycoon_Prop_Weapons_Spear_S0
[upload] would upload props/Weapons/Spinblade S0       <- assets\build\stages\_props\Weapons\Spinblade_S0.glb as EraCityTycoon_Prop_Weapons_Spinblade_S0
[upload] would upload props/Weapons/Splitbow S0        <- assets\build\stages\_props\Weapons\Splitbow_S0.glb as EraCityTycoon_Prop_Weapons_Splitbow_S0
[upload] would upload props/Weapons/Warhammer S0       <- assets\build\stages\_props\Weapons\Warhammer_S0.glb as EraCityTycoon_Prop_Weapons_Warhammer_S0
[upload] dry run: 15 upload(s) prepared, nothing sent
-- 'would upload' lines: 15
-- longest name: 42 EraCityTycoon_Prop_Weapons_Flamethrower_S0

### 3. upload_icons.py --set Weapons --dry-run --assets-json <scratch>/Assets.json
[icons] would upload decal icon Weapons/Beam <- assets/testfit/out/Weapons/icons256/Beam_icon.png (41 KB) as EraCityTycoon_Icon_Weapons_Beam
[icons] would upload decal icon Weapons/Broadsword <- assets/testfit/out/Weapons/icons256/Broadsword_icon.png (28 KB) as EraCityTycoon_Icon_Weapons_Broadsword
[icons] would upload decal icon Weapons/Chaingun <- assets/testfit/out/Weapons/icons256/Chaingun_icon.png (43 KB) as EraCityTycoon_Icon_Weapons_Chaingun
[icons] would upload decal icon Weapons/Flamethrower <- assets/testfit/out/Weapons/icons256/Flamethrower_icon.png (33 KB) as EraCityTycoon_Icon_Weapons_Flamethrower
[icons] would upload decal icon Weapons/FrostHammer <- assets/testfit/out/Weapons/icons256/FrostHammer_icon.png (26 KB) as EraCityTycoon_Icon_Weapons_FrostHammer
[icons] would upload decal icon Weapons/Greataxe <- assets/testfit/out/Weapons/icons256/Greataxe_icon.png (25 KB) as EraCityTycoon_Icon_Weapons_Greataxe
[icons] would upload decal icon Weapons/Launcher <- assets/testfit/out/Weapons/icons256/Launcher_icon.png (39 KB) as EraCityTycoon_Icon_Weapons_Launcher
[icons] would upload decal icon Weapons/Longbow <- assets/testfit/out/Weapons/icons256/Longbow_icon.png (22 KB) as EraCityTycoon_Icon_Weapons_Longbow
[icons] would upload decal icon Weapons/Rifle <- assets/testfit/out/Weapons/icons256/Rifle_icon.png (29 KB) as EraCityTycoon_Icon_Weapons_Rifle
[icons] would upload decal icon Weapons/Shotgun <- assets/testfit/out/Weapons/icons256/Shotgun_icon.png (24 KB) as EraCityTycoon_Icon_Weapons_Shotgun
[icons] would upload decal icon Weapons/Smg <- assets/testfit/out/Weapons/icons256/Smg_icon.png (46 KB) as EraCityTycoon_Icon_Weapons_Smg
[icons] would upload decal icon Weapons/Spear <- assets/testfit/out/Weapons/icons256/Spear_icon.png (21 KB) as EraCityTycoon_Icon_Weapons_Spear
[icons] would upload decal icon Weapons/Spinblade <- assets/testfit/out/Weapons/icons256/Spinblade_icon.png (25 KB) as EraCityTycoon_Icon_Weapons_Spinblade
[icons] would upload decal icon Weapons/Splitbow <- assets/testfit/out/Weapons/icons256/Splitbow_icon.png (25 KB) as EraCityTycoon_Icon_Weapons_Splitbow
[icons] would upload decal icon Weapons/Warhammer <- assets/testfit/out/Weapons/icons256/Warhammer_icon.png (23 KB) as EraCityTycoon_Icon_Weapons_Warhammer
[icons] dry run: 15 valid icon(s), 15 upload(s) pending, nothing sent, nothing written
-- 'would upload' lines: 15; scratch file unchanged: yes
-- longest name: 39 EraCityTycoon_Icon_Weapons_Flamethrower

### 4. the fixture's fake ids into the scratch file
fake ids written into C:/Users/benja/AppData/Local/Temp/claude/c--Users-benja-Desktop-tycoon/f6c03e29-23c5-4dc8-ba99-ba7296a3858e/scratchpad/pipeline/chain/Assets.json: 15 prop stage(s), 15 icon(s); version 5
-- fixture records: 30 (15 prop, 15 icon)

### 5. harvest.py --emit --props --assets-json <scratch>/Assets.json --luau <scratch>/harvest.luau
[harvest] wrote ..\..\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\f6c03e29-23c5-4dc8-ba99-ba7296a3858e\scratchpad\pipeline\chain\harvest.luau with 30 asset(s) to harvest
-- entries: 30 (15 prop, 15 icon)
93:		if asset.kind == "pathTexture" or asset.kind == "worldTexture" or asset.kind == "icon" then
28:	{ kind = "icon", set = "Weapons", model = "Beam", id = 9320000000001 },
29:	{ kind = "icon", set = "Weapons", model = "Broadsword", id = 9320000000002 },

### 6. harvest.py --props --file <fixture> --assets-json <scratch>/Assets.json
[harvest] props/Weapons/Beam S0: 1 part(s) weapon-kit mesh 9310000000001 image 9319999999999
[harvest] props/Weapons/Broadsword S0: 1 part(s) weapon-kit mesh 9310000000002 image 9319999999999
[harvest] props/Weapons/Chaingun S0: 1 part(s) weapon-kit mesh 9310000000003 image 9319999999999
[harvest] props/Weapons/Flamethrower S0: 1 part(s) weapon-kit mesh 9310000000004 image 9319999999999
[harvest] props/Weapons/FrostHammer S0: 1 part(s) weapon-kit mesh 9310000000005 image 9319999999999
[harvest] props/Weapons/Greataxe S0: 1 part(s) weapon-kit mesh 9310000000006 image 9319999999999
[harvest] props/Weapons/Launcher S0: 1 part(s) weapon-kit mesh 9310000000007 image 9319999999999
[harvest] props/Weapons/Longbow S0: 1 part(s) weapon-kit mesh 9310000000008 image 9319999999999
[harvest] props/Weapons/Rifle S0: 1 part(s) weapon-kit mesh 9310000000009 image 9319999999999
[harvest] props/Weapons/Shotgun S0: 1 part(s) weapon-kit mesh 9310000000010 image 9319999999999
[harvest] props/Weapons/Smg S0: 1 part(s) weapon-kit mesh 9310000000011 image 9319999999999
[harvest] props/Weapons/Spear S0: 1 part(s) weapon-kit mesh 9310000000012 image 9319999999999
[harvest] props/Weapons/Spinblade S0: 1 part(s) weapon-kit mesh 9310000000013 image 9319999999999
[harvest] props/Weapons/Splitbow S0: 1 part(s) weapon-kit mesh 9310000000014 image 9319999999999
[harvest] props/Weapons/Warhammer S0: 1 part(s) weapon-kit mesh 9310000000015 image 9319999999999
[harvest] icon Weapons/Beam: image 9330000000001
[harvest] icon Weapons/Broadsword: image 9330000000002
[harvest] icon Weapons/Chaingun: image 9330000000003
[harvest] icon Weapons/Flamethrower: image 9330000000004
[harvest] icon Weapons/FrostHammer: image 9330000000005
[harvest] icon Weapons/Greataxe: image 9330000000006
[harvest] icon Weapons/Launcher: image 9330000000007
[harvest] icon Weapons/Longbow: image 9330000000008
[harvest] icon Weapons/Rifle: image 9330000000009
[harvest] icon Weapons/Shotgun: image 9330000000010
[harvest] icon Weapons/Smg: image 9330000000011
[harvest] icon Weapons/Spear: image 9330000000012
[harvest] icon Weapons/Spinblade: image 9330000000013
[harvest] icon Weapons/Splitbow: image 9330000000014
[harvest] icon Weapons/Warhammer: image 9330000000015
[harvest] merged 15 prop stage(s) into ..\..\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\f6c03e29-23c5-4dc8-ba99-ba7296a3858e\scratchpad\pipeline\chain\Assets.json
[harvest] merged 15 icon(s)
[harvest] every uploaded asset is harvested; next: py tools/assets/gen_templates.py --props
-- exit 0

### 7. gen_templates.py --props --assets-json <scratch>/Assets.json --out <scratch>/templates
[templates] wrote templates/_props/Weapons/Beam.rbxmx
[templates] wrote templates/_props/Weapons/Broadsword.rbxmx
[templates] wrote templates/_props/Weapons/Chaingun.rbxmx
[templates] wrote templates/_props/Weapons/Flamethrower.rbxmx
[templates] wrote templates/_props/Weapons/FrostHammer.rbxmx
[templates] wrote templates/_props/Weapons/Greataxe.rbxmx
[templates] wrote templates/_props/Weapons/Launcher.rbxmx
[templates] wrote templates/_props/Weapons/Longbow.rbxmx
[templates] wrote templates/_props/Weapons/Rifle.rbxmx
[templates] wrote templates/_props/Weapons/Shotgun.rbxmx
[templates] wrote templates/_props/Weapons/Smg.rbxmx
[templates] wrote templates/_props/Weapons/Spear.rbxmx
[templates] wrote templates/_props/Weapons/Spinblade.rbxmx
[templates] wrote templates/_props/Weapons/Splitbow.rbxmx
[templates] wrote templates/_props/Weapons/Warhammer.rbxmx
[templates] 286 prop template(s): 15 written, 271 unchanged, 0 removed
-- 15 template(s) in _props/Weapons: Beam, Broadsword, Chaingun, Flamethrower, FrostHammer, Greataxe, Launcher, Longbow, Rifle, Shotgun, Smg, Spear, Spinblade, Splitbow, Warhammer
-- each a Model with Base + Stage0 holding one MeshPart 'weapon-kit', CanCollide and CanQuery false: yes
CHECK: PASS -- 569 template(s) up to date

### 8. weapon_frames.py --check --assets-json <scratch>/Assets.json
[weapon-frames] frame files: 15 family(ies) rebuilt from assets/kenney3d/weapon-kit/Models/GLB format
[weapon-frames] fixture: 2 record(s), 16 corner(s) come back; an unturned import fails 2 of 2, an unturned placement 2 of 2
[weapon-frames] weapons (../../AppData/Local/Temp/claude/c--Users-benja-Desktop-tycoon/f6c03e29-23c5-4dc8-ba99-ba7296a3858e/scratchpad/pipeline/chain/Assets.json): 15 of 15 harvested and proven (63 point(s))
CHECK: PASS -- src/shared/Config/WeaponModels.json up to date; turn proof holds
-- exit 0

### the manifest against the scratch harvest (read-only, --out to scratch)
Summary: 15 families: 15/15 blueprints, 15/15 uploaded, 15/15 harvested, 15/15 templated, 15/15 icons uploaded, 15/15 icons harvested
| 2 | `broadsword` | `Broadsword` | yes | 1/1 | 1/1 | 1/1 | yes | bladeBase, grip, holster, tip | yes | yes |

### guard after: the real files unchanged
-- real Assets.json, harvest.luau and templates/ untouched
```

## The turn proof (L3-47)

- **Now, on real Studio data:** the fixture's 2 records, 16 corners, all come back within 0.01.
  The guard: an import with no turn fails 2 of 2, a placement that does not undo the turn fails 2 of
  2, so the proof cannot pass by construction.
- **On the 15 fakes** (chain step 8, `--require-harvest`): 15 of 15 harvested and proven, 63 points.
- **Against the real `Assets.json` now:** 0 of 15 harvested (nothing uploaded), so only the fixture
  runs; `--require-harvest` fails there, as it must until the paste.
- **Every rule can fail** (30 mutants on scratch copies, 30 caught):

```
caught  no frame file                                                  exit 1  (no frame file)
caught  frame names another model                                      exit 1  (names model)
caught  grip off origin                                                exit 1  (is not [0, 0, 0])
caught  tip missing                                                    exit 1  (no `tip` point)
caught  holster missing                                                exit 1  (no `holster` point)
caught  point outside bounds                                           exit 1  (outside its bounds)
caught  point of two numbers                                           exit 1  (not three finite numbers)
caught  blueprint turned                                               exit 1  (not the origin, unturned)
caught  blueprint moved                                                exit 1  (not the origin, unturned)
caught  blueprint scale 4                                              exit 1  (scale is 4.0)
caught  blueprint scale missing                                        exit 1  (scale is 4.0)
caught  blueprint two pieces                                           exit 1  (has 2 pieces)
caught  blueprint missing                                              exit 1  (no blueprint)
caught  extra blueprint                                                exit 1  (is no weapons family)
caught  sidecar bounds off                                             exit 1  (differ from the frame file's)
caught  sidecar triangles off                                          exit 1  (merged triangles)
caught  committed file stale                                           exit 1  (differs from a fresh build)
caught  frames absent: shape only, passes                              exit 0  (frame files absent: shape checked only)
caught  shape: tip missing                                             exit 1  (no `tip` point)
caught  shape: family missing                                          exit 1  (a weapons family with no entry)
caught  shape: extra family                                            exit 1  (names no weapons family)
caught  shape: model mismatch                                          exit 1  (is not 'Smg')
caught  shape: min > max                                               exit 1  (exceeds max)
caught  shape: NaN                                                     exit 1  (not three finite numbers)
caught  proof: offset not turned                                       exit 1  (comes back at)
caught  proof: size off                                                exit 1  (is not the merged size)
caught  proof: two parts                                               exit 1  (not one weapon-kit MeshPart)
caught  fixture on the axis: guard calls it vacuous                    exit 1  (could not catch it)
caught  fixture LampPost unturned: proof fails                         exit 1  (comes back at)
caught  --require-harvest on the real Assets.json (nothing harvested)  exit 1  (15 of 15 weapon(s) are not harvested)
30 of 30 as expected
```

## The lead's commands (also MANUAL_STEPS "L3 W2 — the asset run", steps 3–11)

From `C:\Users\benja\Desktop\tycoon-p5` on `l3-w2` (`upload_icons.py` and the icon harvest exist
only there until the merge; `.env` is there). Announce to any other session first.

```
py tools/assets/upload_models.py --props --era Weapons --dry-run     # 15 "would upload"; WRITES Assets.json (pre-lists 15, ids 0)
py tools/assets/upload_models.py --props --era Weapons               # uploaded 15/15
py tools/assets/upload_icons.py --set Weapons --dry-run              # 15 valid; writes nothing
py tools/assets/upload_icons.py --set Weapons                        # Weapons: uploaded 15/15; Assets.json becomes v5
git commit (Assets.json)
py tools/assets/harvest.py --emit --props && cat tools/assets/harvest.luau | clip    # "... with 30 asset(s) to harvest"
```

Ben: the local `C:\Users\benja\Desktop\tycoon\build\test.rbxl`, Edit mode, View → Command Bar,
Ctrl+V, Enter, wait for `[HARVEST-DONE] 30 loaded, 0 failed`, Output → right-click → Select All →
Ctrl+C, say "done", copy nothing else. Then:

```
powershell -NoProfile -Command "[IO.File]::WriteAllText('<scratch file>', (Get-Clipboard -Raw), (New-Object Text.UTF8Encoding $false))"
grep -c '\[HARVEST\] {' <scratch file>                               # 30
py tools/assets/harvest.py --props --file <scratch file>              # merged 15 prop stage(s), merged 15 icon(s)
git commit (Assets.json)
py tools/assets/weapon_frames.py --check --require-harvest           # 15 of 15 harvested and proven (63 point(s)); a FAIL stops here
py tools/assets/gen_templates.py --props                              # 286 prop template(s): 15 written, 271 unchanged, 0 removed
py tools/assets/gen_templates.py --check                              # 569 template(s) up to date
py tools/gen_asset_manifest.py && py tools/gen_asset_manifest.py --check
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

## What the lead must know before uploading

1. **The `py` launcher runs a different Python for scripts with a `#!` line.** `py -c ...` and
   `py script.py` without one run 3.14 32-bit (Pillow 12.3 installed); `py script.py` whose first line
   is `#!/usr/bin/env python` (most older tools: harvest, upload_models, gen_templates, gen_asset_manifest, weapon_frames) runs `C:\Users\benja\AppData\Local\Programs\Python\Python312\python.exe`,
   **3.12 64-bit, no Pillow**. That is why `upload_icons.py` has no `#!` (said in its docstring and
   the README). It probably also explains the "32- and 64-bit Python" difference noted in memory
   chief-clearing-2026-10-16. Worth a memory note; `upload_models.py`'s VIP swatch (Pillow) would fail
   under 3.12 the same way, though props never build one.
2. The committed `tools/assets/harvest.luau` still has the old Decal branch (no `"icon"`) until the
   lead's `--emit --props` at step 6 rewrites it; it is generated, and no gate compares it. Commit
   the regenerated one with the templates.
3. `upload_icons.py` refuses any 256 px icon older than its 512 render (re-run `--make`); it is
   hash-checked like `upload_paths.py`. `upload_models.py` is not (L3-67).
4. `harvest.list_missing` on the real `Assets.json` is empty in both modes today (checked read-only),
   so the paste holds exactly the 30 W2 records.
5. A Decal still in moderation harvests image 0: `merge_icon` warns and skips it, its card stays text;
   steps 6–8 again later, never the uploaders.
6. The upload description change applies to every future props upload in every era ("…; kits: …").
7. L3-66 stands: an `assets_config.py` older than this one erases `icons` on save (`tycoon-c2`,
   `tycoon-m11`).
8. After the paste, the manifest's Weapons summary should read 15/15 on all six counts; the
   templates go 554 → 569.

## For the other owners

- Everyone: `WeaponModels.json` is final unless a generator moves a point (then `weapon_frames.py`
  rewrites it and `--check` goes red until it does). Holster = bbox centre for the bows and the
  guns, mid-length for blades and hafts (the generators' rule).
- No change needed in anyone else's file. No Theme constant, project file or remote asked for.
