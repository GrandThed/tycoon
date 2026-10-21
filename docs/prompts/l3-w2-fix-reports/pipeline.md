# L3 W2 fix round — pipeline engineer's report (2026-10-21)

Rulings P1–P6 of `docs/prompts/l3-w2-fix-round.md`. Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-w2`.

- Nothing is committed.
- Nothing was uploaded. There was no real harvest and no dry run against the real `Assets.json`; every merge,
  dry run and template run used a scratch copy.
- `tools/assets/harvest.luau` and `templates/` are byte-identical to the start of the round:
  - `harvest.luau` sha256 is `f4865eb1…`, and it still holds 30 records;
  - the hash over all files in `templates/` is `ef83a680…`.

## Files (my row only)

| File | Change |
|---|---|
| `tools/assets/harvest.py` | P2: a rotated weapon MeshPart is refused, not merged; exit 1, named |
| `tools/assets/upload_icons.py` | P4: `pixel_sha256` (decoded RGBA) replaces the file-byte hash |
| `src/shared/Config/Assets.json` | P4: the 15 `icons.Weapons.*.sha256` values migrated; nothing else |
| `tools/assets/weapon_frames.py` | P5: the proof's line says what it proves |
| `tools/assets/upload_models.py` | P6: Kenney CC0 credit only when every kit is Kenney's; generated kits named so |
| `docs/ASSET_MANIFEST.md` | P1: regenerated |
| `docs/MANUAL_STEPS.md` "L3 W2" | P1, P2, P3, P4, P5 |

## Rulings

**P1 (1-m1): the manifest is regenerated.**
- I ran `py tools/gen_asset_manifest.py`. The diff (16 + 16 lines) is the Weapons section only:
  - the summary now reads `15/15 uploaded ... 15/15 icons uploaded`;
  - every row reads `1/1 | 0/1 | — | … | yes | —`.
- This is the reviewer's fresh render. `--check` passes.
- In MANUAL_STEPS:
  - the "Rules for the lead" commit line now says to regenerate the manifest beside every `Assets.json` commit,
    and why;
  - steps 5 and 8 run `py tools/gen_asset_manifest.py` and commit `Assets.json` and `docs/ASSET_MANIFEST.md`
    together.

**P2 (1-m2): the merge refuses a rotated weapon.**
- In `merge_model`, a `props` record whose era is the weapons folder and that has any part with `rotated` set is
  collected the way `world_size_problems` is:
  - the merge warns `…; NOT merged` and skips the record;
  - it saves everything else;
  - it ends with one `ROTATED: <label>: MeshPart <name> is rotated …` line per weapon and a stop line;
  - it returns 1.
- The weapons folder comes from `weapon_frames.FOLDER` (`from weapon_frames import FOLDER as WEAPONS_FOLDER`), the
  constant that writes `WeaponModels.json` `folder`. That import adds no cycle.
- `--force` does not bypass the refusal. Other props and buildings keep the old warning.
- The emitted Luau is unchanged, so `harvest.luau` was **not** regenerated. An emit from a scratch copy to a scratch
  path is byte-identical to the committed file, with 30 records.
- MANUAL_STEPS step 8 now says "No `rotated` warning". A `ROTATED:` line means stop, as for a failed proof.
- Proof on scratch: the fixture rewritten to the 30 real asset ids, merged into scratch copies.

| Case | Result |
|---|---|
| clean paste | `merged 15 prop stage(s)`, `merged 15 icon(s)`, exit 0; then `--require-harvest` PASS |
| Broadsword `rotated: true` (the reviewer's probe) | `NOT merged`, `merged 14`, `ROTATED: props/Weapons/Broadsword S0 …`, exit 1; then `--require-harvest` FAIL `1 of 15 … not harvested: Broadsword` |
| the same with `--force` | refused, exit 1 |
| Spear and Smg rotated | both named, `2 weapon(s) refused`, exit 1 |
| a rotated Boomtown prop (`Bend`) | the old warning, merged, exit 0 |
| a rotated Village building (`Campfire`) | the old warning, merged, exit 0 |

**P3 (1-s1): MANUAL_STEPS "L3 W2" catches up.**
- Steps 3–6 are ticked:
  - step 3: done before 084a14f;
  - step 4: 084a14f, 00:13;
  - step 5: d1c2f59, 00:14;
  - step 6: 4154715, 00:14, 30 records.
- The line "none of the 15 is in `Assets.json`" is corrected. It now says they were not there before the uploads,
  and that since 084a14f and d1c2f59 all 15 models and 15 icons are there, uploaded and not yet harvested.
- Step 6's "Not 30: stop" is replaced:
  - the first time, 30;
  - a repeat (step 12) emits only the records still missing, so fewer than 30 is right, one per name in the last
    merge's `still missing harvest data:` line;
  - any other count: stop and tell the lead.
- Steps 7 and 8 now count against what step 6 emitted, which is 30 the first time.
- Step 9 has a failure path. If the proof fails, or step 8 printed `ROTATED:`, stop:
  - write and commit no templates;
  - note that `gen_templates.py --check` stays red until the lead resolves it, because `Assets.json` is already
    committed with the harvested stages;
  - send the lead the printed lines;
  - never re-upload.

**P4 (1-s2): icons are hashed on their pixels, and the 15 hashes are migrated.**
- `upload_icons.py`:
  - `decode_rgba` is factored out of `icon_problems`, which behaves as before;
  - `pixel_sha256(data)` is the sha256 of `"RGBA8 <w>x<h>\n"` followed by the decoded rows, all four channels.
    A transparent pixel's colour can still reach the edge under texture filtering, so it counts;
  - `plan` compares that digest, and the log reads "pixels changed since upload";
  - the docstring says why. The `sha256` import from `upload_paths` is gone.
- Checks on the 15 real icons:
  - `pixel_sha256` equals a digest of Pillow's decode on all 15;
  - re-encoding at compress level 0 and at level 9 with `optimize` gives other bytes 30 of 30 times and the same
    digest 30 of 30 times;
  - one channel of one pixel moved changes the digest 15 of 15 times.
- **The migration** was a scratch one-off,
  `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\f6c03e29-23c5-4dc8-ba99-ba7296a3858e\scratchpad\pipefix\migrate_icon_hashes.py`:
  - it runs through `assets_config.load_assets` and `save_assets`;
  - it refuses unless each file's bytes still hash to the recorded value (15 of 15 did: these are the uploaded
    files) and each file passes `icon_problems`;
  - it ran first on a scratch copy, then on the real file. The real result equals the scratch result byte for byte.
- **Before and after differ only in the `sha256` values.**
  - `git diff -- src/shared/Config/Assets.json` is 15 insertions and 15 deletions.
  - Changed lines that are not `"sha256": "<64 hex>"`: **0**.
  - Every `assetId` and `imageId` is unchanged. The file is still v5 and LF.
  - Assets.json sha256 went `98aba8b0…` → `9055d1c2…`.
- Idempotency, on scratch copies:
  - `upload_icons.py --set Weapons --dry-run` gives 15 times `already uploaded … skipped`, then
    `every icon is already uploaded (15)`, and the copy is unchanged;
  - the same against a re-encoded icon set (`--icons-dir`, 15 of 15 with other bytes) also skips all 15;
  - against the old byte hashes it would have planned 15 uploads. That is why the migration was needed.

**P5 (1-s3): the proof's line says what it proves.** The line in `weapon_frames.py` now reads:

```
weapons (<Assets.json>): 15 of 15 harvested and proven (per weapon one offset check and one size check; that offset carries their 63 point(s))
```

- The point count now counts only proven weapons.
- The docstring says that the points of a weapon pass or fail together. Where a point sits on the mesh is the
  generator's and the sidecar bounds check's, not the proof's.
- MANUAL_STEPS step 9 quotes the new line.

**P6 (1-s4): the props description.** `upload_models.py` has a new `kenney_kit(kit)`:
- it is true when `assets/kenney3d/<kit>/License.txt` names Kenney and CC0;
- `KITS_ROOT` is imported from `palette.py`, so it is not copied;
- all 14 Kenney kits have that file. None of the generated kits does, `tower-kit` included (it is generated by
  `tower_kit.py`).

`prop_description` gives these results. Only future uploads change.

| Kits | Description |
|---|---|
| a weapon | `Era City Tycoon prop 'Broadsword' (Weapons) stage 0; kits: weapon-kit (generated).` |
| Kenney kits only | `… stage 0; kits: city-kit-roads, city-kit-suburban. Kenney kit pieces, CC0.` |
| mixed | `…; kits: city-kit-roads, farmland-kit (generated).` (no CC0 claim) |

A props dry run on a scratch copy with the Weapons ids cleared runs it inside the job build: 15 `would upload`. As
is, the copy prints `nothing to upload` and stays byte-identical.

## Gates

```
py tools/assets/weapon_frames.py --check     CHECK: PASS -- src/shared/Config/WeaponModels.json up to date; turn proof holds
py tools/assets/gen_templates.py --check     CHECK: PASS -- 554 template(s) up to date
py tools/gen_asset_manifest.py --check       CHECK: PASS -- configs valid, manifest up to date   (was FAIL: stale)
```

- **The post-paste chain on scratch**, with the real ids, the new code and the clean paste:
  - the merge exits 0;
  - `gen_templates.py --props` gives `286 prop template(s): 15 written, 271 unchanged, 0 removed`, then
    `569 … up to date`;
  - `--require-harvest` passes with the new line;
  - the manifest's summary reads 15/15 on all six counts.
- **Python:** the four tools compile under 3.12 and 3.14.
- **The shared gates**, run while the other owners were mid-edit, so they describe the tree at that moment:
  - stylua `--check src`: clean;
  - selene: 0 errors, 1 warning. It is old: `src/client/UI/LegacyPanel.luau:200`, shadowing `header`, a file
    nobody touched this round;
  - luau-lsp, both trees, sourcemaps regenerated in scratch: no diagnostics;
  - `check_compile`: 180 files PASS;
  - harness: `HARNESS: PASS (3,971 checks)`.
- **Line endings:** all seven files are LF (`git ls-files --eol` reads `w/lf`, and no file contains CRLF).

## For the lead

- **`tools/testfit/README.md` is not in my row this round.** Two of its lines now lag, so route them:
  - `:669` "names the kit ("…; kits: weapon-kit.") instead of Kenney CC0" should be "…; kits: weapon-kit
    (generated)."; Kenney-only props keep "Kenney kit pieces, CC0.";
  - `:674` "hash-checked, so a changed file goes up again" should be "hash-checked on the decoded pixels, so a
    changed image goes up again and a re-encode does not".
- **When you commit,** commit `Assets.json` (hash migration) and `docs/ASSET_MANIFEST.md` together, as the new rule
  says.
- **Moving the icon sha256s is safe, now and later:**
  - no client reads `sha256`. `WeaponLook.IconId` reads `imageId` only;
  - the harvest emits by `assetId`/`imageId`, so the pending paste is unaffected.
- **No change is needed in anyone else's file.**
