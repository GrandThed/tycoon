# L3 W2 review, slice 1: pipeline and data

Reviewer: roblox-reviewer, 2026-10-21. Branch `l3-w2` at c79bec5. Diff `main...l3-w2` on this slice's files:
`tools/assets/weapon_frames.py`, `upload_icons.py`, `assets_config.py`, `harvest.py`, `gen_templates.py`,
`upload_models.py`, `tools/assets/fixtures/*`, `tools/assets/harvest.luau`, `tools/gen_asset_manifest.py`,
`src/shared/Config/WeaponModels.json`, `src/shared/Config/Assets.json` (the 15 props, the v5 `icons`),
`docs/MANUAL_STEPS.md` "L3 W2", `tools/testfit/README.md`. Read against the contract (its §11 rulings included) and
`docs/prompts/l3-w2-reports/pipeline.md`.

**0 Critical, 0 Major, 3 Minor, 4 Suggestions.**

Everything ran on scratch copies of `Assets.json` and `templates/`. No upload, no real harvest, no dry run against the
real `Assets.json`. The worktree is unchanged (`git status` clean) apart from this file.

## Minor

**m1. `gen_asset_manifest.py --check` fails on the branch: the manifest was generated before the uploads.**
`docs/ASSET_MANIFEST.md:486` and `:490-504`. The process gap is `docs/MANUAL_STEPS.md:2265` and `:2291`.
- The build commit 8d9119e carries a manifest that reads "0/15 uploaded, 0/15 icons uploaded". It was committed after
  084a14f and d1c2f59, which wrote the 15 `modelAssetId`s and the 15 icon `assetId`s.
- `py tools/gen_asset_manifest.py --check` now prints `CHECK: FAIL -- 1 problem(s)`.
- A fresh render, written to scratch, differs only in the Weapons section:
  - the summary becomes `15/15 uploaded ... 15/15 icons uploaded`;
  - every row gets `1/1 | 0/1 | ... | yes`.
- That file passes `--check`. So staleness is the only problem.
- **Failure:** L3-40 runs QA in parallel with the paste. The QA list in §9 includes this gate, so QA reports red on
  the branch until step 10 of the asset run.
- MANUAL_STEPS commits `Assets.json` after the uploads (step 5) and after the merge (step 8). It regenerates the
  manifest only at step 10. The gate is therefore red between those steps on every future run, too.
- **Fix:**
  - Regenerate and commit the manifest now: `py tools/gen_asset_manifest.py`.
  - Add `py tools/gen_asset_manifest.py` beside both "Commit `Assets.json` now" lines, and commit the two files
    together.

**m2. The turn proof cannot see a rotated MeshPart, and the harvest only warns about one.**
- Where:
  - `tools/assets/harvest.py:354-355` warns and then merges anyway;
  - `tools/assets/weapon_frames.py:399-436` (`weapon_proof`) runs on what is left;
  - `Assets.json` never stores the `rotated` flag.
- L3-47's derivation assumes that the imported MeshPart is unrotated. The contract says that "`harvest.py` warns
  otherwise". The proof then tests only translation: `back == p` reduces to `offset == (-cx, cy, -cz)`, plus a size
  check per axis.
- Suppose an import put the turn into the MeshPart's CFrame instead of the vertices. The offset would still be
  `(-cx, cy, -cz)`, so the proof would pass. `template_placement` would then turn the part a second time, and the
  weapon would point backwards: the tip behind the hand and the muzzle at the pommel.
- **Probe:** I set `"rotated": true` on Broadsword in a copy of the fixture and gave it the real ids.
  - The merge printed one WARNING line among 30 OK lines and exited 0.
  - `weapon_frames.py --check --require-harvest` then printed `15 of 15 harvested and proven` and `CHECK: PASS`.
  - MANUAL_STEPS step 8 (`:2287`) lists the lines to expect, but does not say to look for this warning.
- The likelihood is low. All 554 earlier templates were harvested unrotated, and the template-turn fix (b17718e) was
  verified in Studio. But the gate claims it "can never pass by construction", and this is the one input it cannot
  see.
- **Fix (either one):**
  - in `merge_model`, collect rotated parts like `world_size_problems`: skip the record and exit 1;
  - or keep `rotated: true` on the merged part and let `weapon_proof` fail on it. `render_assets` would have to keep
    the key.

  Then add "no `rotated` warning" to step 8.

**m3. Cross-slice (for slice 3, ui B and ui A): the clients trust the template's `PrimaryPart` reference, which an
earlier lesson says not to do.**
- Where:
  - `src/combat/client/Controllers/HeldWeapons.luau:93` (a template counts only when `template.PrimaryPart ~= nil`)
    and `:138` (`local base = model.PrimaryPart`);
  - `src/client/UI/ArmoryStage.luau:97-101` (no Base check) and `:302` (`model:PivotTo(pose)`).
- "The pivot is the grip" holds because the template's `Base` sits at the identity. `gen_templates.template_xml`
  guarantees the part's **name** "Base", and writes `PrimaryPart` as a Ref. It writes no `WorldPivot`.
- `PlotService.templateBase` (`src/server/Services/PlotService.luau:482-488`) says that the Ref "can arrive nil in a
  live session, and a Model without one pivots about its bounding-box centre". That is the M7 playtest bug.
  `PropFactory.Spawn` (`src/client/City/PropFactory.luau:280-283`) therefore finds `Base` by name and sets
  `clone.PrimaryPart = base`.
- **Failure:** in a session where the Ref is lost (the M7 case, probably `rojo serve`):
  - every hand stays empty with no warning;
  - the stage pivots each weapon about its bbox centre, so the camera aims at `pose * bounds centre` while the mesh
    sits elsewhere. For the Broadsword the mesh is 1.265 studs off along its length, and for the Spear 1.2.
  - Built place files keep the Ref, so Ben's normal path is not affected.
- **Fix:** follow the PropFactory pattern in both clones: `FindFirstChild("Base")`, check `IsA("BasePart")`, then set
  `clone.PrimaryPart = base` before any weld or `PivotTo`.

## Suggestions

- **s1. MANUAL_STEPS is behind the run.**
  - Steps 3 to 6 (`:2246-2270`) are unticked, but the uploads and the emit are committed (084a14f, d1c2f59, 4154715).
  - `:2222` still says "none of the 15 is in `Assets.json`".
  - Step 6's "Not 30: stop" (`:2270`) contradicts step 12 (`:2324`). Repeating steps 6 to 8 for an icon still in
    moderation emits fewer than 30.
  - Step 9 (`:2292-2297`) has no recovery line. After a failed proof, `Assets.json` is already committed with
    harvested stages, and `gen_templates.py --check` stays red until it is resolved. Say: write no templates; send
    the printed weapon and point to the lead; never re-upload.
- **s2. Hash the icon's pixels, not the PNG's bytes** (`tools/assets/upload_icons.py:267`, `sha256(path)`).
  - Suppose `--make` runs under another Pillow, or a 512 render is touched (the mtime rule at `:259` forces a
    `--make`). The same pixels are then re-encoded to new bytes.
  - All 15 Decals then go up again with `imageId` 0, which costs Ben a new paste.
  - `icon_problems` already decodes the rows, so a digest of the decoded RGBA costs nothing.
- **s3. "63 point(s) proven" claims more than the proof does** (`weapon_frames.py:425-427`).
  - Every point of one weapon passes or fails together: it is one translation check plus one size check per weapon.
  - A wrong point (for example a `tip` at the wrong end) is guarded only by the generator and the sidecar bounds
    check.
  - Say "15 weapon(s) proven (offset and size)" so nobody reads it as a check of the points.
- **s4. Hold one stray thought for L4:** `upload_models.prop_description` now changes the description of every future
  props upload in every era. That is intended, but it means a re-upload of an old Kenney prop no longer says CC0.
  Check whether the Kenney licence wants that credit kept: CC0 does not require it.

## Checked and clean

- **L3-47 against the code as written.** The importer turns the model 180° about Y; `harvest.luau` records the
  position minus the inner model's pivot; `template_placement` puts the part at (−x, y, −z), turned. Together these
  give the identity, with `Base` (a 1 × 0.2 × 1 part at the origin, the PrimaryPart) on the grip. The inner pivot is
  the glTF origin on all three axes:
  - LampPost: z −0.788 → +0.7875;
  - Village BushA has min y −0.2, and its harvested y 0.5208 equals the centre y 0.521, where the bottom would give
    0.721;
  - Valley Clouds_1 has offset y 350.9 against size/2 94.8.
- **`template_placement` changes no bytes.** `gen_templates.py --check` gives 554 PASS, and no caller passes the old
  `turned=` keyword.
- **The turn proof catches a bad translation.** With Broadsword's harvested z sign flipped on scratch, it fails at
  2.53 studs off. The fixture `turn_proof.json` equals the real sidecars and the harvested `Assets.json` values for
  LampPost and BushA.
- **`Assets.json`.**
  - Load then `render_assets` gives back the same 516,994 bytes.
  - All six writers (`upload_models`, `upload_paths`, `upload_world`, `upload_icons`, `harvest`, `assets_config`) go
    through `cfg.save_assets`. `render_assets` keeps `icons`, and every version bump is a `max()`.
  - The older copies are in `tycoon-c2` and `tycoon-m11` only (L3-66).
- **Idempotency.**
  - The props dry run on a scratch copy reports 15 "already uploaded, skipped", and the copy stays byte-identical.
  - The icons dry run skips all 15 by hash and writes nothing.
  - The GLBs were merged before the upload commit (23:56 against 00:13).
- **`harvest.luau`.**
  - A fresh `--emit --props` from the committed `Assets.json` is byte-identical to it: 30 records, 15 prop and 15
    icon.
  - It is ASCII only (safe through `clip`) and compiles with `luau-compile -O1 -g2`.
  - A stubbed run under `luau.exe` printed a `prop` record and an `icon` record (`set`, `model`, `imageId` from the
    Decal's Texture), and `harvest.py` parses both.
- **The post-paste chain on scratch with the real asset ids** (the fixture with its ids rewritten):
  - merged 15 prop stages and 15 icons;
  - `--require-harvest` gave 15 of 15 (63);
  - templates: `286 ... 15 written, 271 unchanged, 0 removed`, then `569 ... up to date`.

  These match MANUAL_STEPS steps 8 to 10 word for word.
- **Names.** The longest are 42 (`..._Flamethrower_S0`) and 39 (`EraCityTycoon_Icon_Weapons_Flamethrower`), with the
  `ECT_` fallback and the 50-character cap.
- **The manifest's new mask.** It equals the old mask on main's manifest (371 rows each, 0 differing lines), and on
  the Weapons table it masks the GLB column. The old mask would have masked the Template column there.
- **Nothing else reads the new data.**
  - No client reads `Assets.json` `offset` for weapons; only the shelf reads `icons`.
  - No Luau code or tool walks every props era: all are keyed by era name, so `props.Weapons` is inert for the city.
  - Every project file maps `templates/_props` into `ReplicatedStorage.Assets.Props`.
- **`WeaponModels.json`** uses LF, parses, round-trips through `render`, and passes `--check`. Its shape-only path
  (an empty frames dir) passes and still runs both proofs.
- **MANUAL_STEPS flags.**
  - Every flag exists in its tool, and the Blender 5.2 path exists.
  - `build/*.rbxl` and both sourcemaps are tracked.
  - The proving line matches the "Build proving" task.
- **Python.** `upload_icons.py` has no shebang on purpose: confirmed, `py` with `#!/usr/bin/env python` runs 3.12
  64-bit with no Pillow, and without it runs 3.14 32-bit. The other tools in the run need no Pillow.
