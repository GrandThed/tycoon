---
name: build-assets
description: "Author an era's growing-building blueprints with parallel Opus builders, review the strips, then run the merge → upload → harvest → template pipeline. Usage: /build-assets <EraName>"
---

# build-assets — one era of buildings, end to end

You are the lead. This skill turns an era's 24 slots into approved blueprints and committed
templates. Blueprint **authoring is delegated to Opus** (`model: "opus"`): on the Village test it
matched Fable's quality, caught its own mistakes through the render loop, and costs less. Keep
Fable (yourself) for splitting the work, judging the strips, and the pipeline.

Argument: `<EraName>` = `Boomtown` | `Metropolis` | `OrbitalColony` (Village shipped in M7).

## 0. Pre-flight (you, ~2 minutes)

1. Read `docs/INTERFACES.md` from `# M7 contracts` (Blueprints subsection is the contract),
   `docs/ASSET_RESEARCH.md` §4 (kit contents and per-era palette), and `tools/testfit/README.md`
   (blueprint format + measured kit facts). Read `src/shared/Config/Eras/<n>_<EraName>.json`
   for the slot list (id, type, modelName, order = price ramp) and `src/shared/Layouts/<EraName>.luau`
   for where the monument sits.
2. Era palette (from the research; do not mix families that clash):
   - **Boomtown:** `city-kit-suburban` + `city-kit-industrial` for buildings, `city-kit-roads`
     for street props (decided 2026-09-16; retro-urban was rejected). Never `city-kit-commercial`.
   - **Metropolis:** `city-kit-commercial` (skyscrapers included) + `city-kit-roads`. Start from
     the approved-in-style drafts in `tools/testfit/blueprints/_drafts/Metropolis-city-kit-commercial/`
     (authored for Boomtown slot names; re-map to Metropolis slots). Never suburban/industrial
     buildings; suburban `tree-*`, `planter`, `path-*` are allowed as props (no other tree source).
   - All four City Kits share one palette, so Boomtown vs Metropolis must differ by building
     type and scale (homes/workshops/factories vs shops/towers), and each kit belongs to one era.
   - Car-kit vehicles are ≥ 9 studs long at ×4 and never fit a 9×9 slot.
   - **OrbitalColony:** `space-kit` only. Every space-kit GLB is invalid glTF (a `tmpParent`
     root node) — before authoring, run `--dump-bounds space-kit` and confirm `testfit.py` and
     `tools/assets/merge_stages.py` import them; if not, port the `sanitize()` fix from
     `assets/research/2026-09-15/glb-trial/glb_trial.py` into `tools/assets/glbtools.py` first.
     Material-colour kits get a palette texture automatically at merge time.
3. Confirm the kits are unzipped at `assets/kenney3d/<slug>/Models/{GLB,GLTF} format/` and
   Blender runs: `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --version`.
4. Split the 24 slots into **three disjoint sets** by character, in slot order: A = the
   building-type slots that are houses/shops/civic (≈8), B = structures + all `unlock` + the
   `monument` (≈8), C = the cheapest early `building` slots + all `decor` (≈8). Every slot lands
   in exactly one set. Note each set's tallest allowed silhouette: the monument must be the
   tallest thing on the plot, then one civic landmark, then the rest.

## 1. Fan out three Opus builders (parallel, background)

Spawn three `general-purpose` agents in ONE message, each with `model: "opus"` and
`run_in_background: true`. Use the brief below verbatim, filling the placeholders. Do not
shorten it — the measured facts and the "Read the PNG yourself" loop are what make Opus reliable.

```
You are **asset-builder <A|B|C>** for milestone <Mn> of the Roblox project "Era City Tycoon" at
C:\Users\benja\Desktop\tycoon (Windows 11; use the Bash tool with Git Bash syntax and forward
slashes). You start with no memory of prior conversation.

## Environment
- Blender 5.2.1: `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/testfit/testfit.py -- --blueprint <json> --out assets/testfit/out`. Python outside Blender is `py` only.
- Files written by the Write tool come out CRLF; convert every file you create to LF (`sed -i 's/\r$//' <file>`) and verify with `file` before finishing. Never commit.
- Read the PNG renders yourself with the Read tool to judge them. Renders show +X on screen-left; the front (−Z) faces the lower-right.
- Use a scratch filename unique to you (e.g. `gen_<A|B|C>.py`) if you write a generator; the scratchpad is shared with the other builders.

## Read first
1. `docs/INTERFACES.md` — the "Blueprints" subsection under `# M7 contracts` (schema, conventions, budgets).
2. `tools/testfit/README.md` — blueprint format and the measured kit facts; read the whole "kit notes" part.
3. `tools/testfit/blueprints/Village/Tavern.json` and `assets/testfit/out/tavern_strip.png` — the approved prototype; match its conventions and its humble → imposing arc. (For a non-Village era the grid conventions carry over; the kit does not.)
4. `docs/ASSET_RESEARCH.md` §2 and §4.
5. `src/shared/Config/Eras/<n>_<EraName>.json` — slot order is the price ramp.

## You own
Only these new files in `tools/testfit/blueprints/<EraName>/`: <list ModelName.json files with type and one-line design intent each>.
`building` slots: five additive stages (0 buy, 1 L10, 2 L25, 3 L50, 4 L100), humble → imposing, growing UP inside a 9×9 stud footprint at scale 4.0 (the monument may use `"footprint": [14, 14]`). `unlock`/`decor`/`monument` slots: single stage, every piece `"stage": 0`.
Kits for this era: <palette from pre-flight>. Do not edit `testfit.py` or any other file; if the tool has a bug, work around it and report it. Two other builders own the rest of the era; do not touch their files.

## Design rules
- Each building must read as its name at every stage. Earlier slots in the era config must read humbler than later ones at the same stage. <tallest-silhouette note for this set>.
- Measure with `--dump-bounds <kit>` before placing anything; no floating or clipping pieces; no footprint warning (the warning prints only at the stage a piece first appears, so check a full 5-stage run). ≤ 60 pieces at stage 4 (≤ 80 for the monument); aim lower.
- Additive stages: a piece never disappears, so anything buried by a later storey must have no outward face on a cell boundary (see README: hips/points/slabs bury cleanly, open-ended gables do not; chimneys go inside the cell with only the cap showing).

## Process
For each building: draft the JSON, render, Read the strip, fix, repeat until every stage looks intentional. Do them in slot order. Keep the JSON tidy (one piece per line, grouped by stage 0→4).

## Definition of done and report
All blueprints render clean with the exact command and are LF. **End your turn with a report even if all passed**: per building the strip PNG path, pieces per stage, stage-4 height in studs, one line per stage on what it adds, how many render iterations it took; kit facts you learned that are not in the README; any tool or contract problems.
```

While they run, do nothing that touches `tools/testfit/` or `assets/testfit/out/`.

## 2. Review the strips (you)

1. Commit each builder's files as its report arrives (protects against interruptions):
   `git add tools/testfit/blueprints/<EraName>/<files> && git commit`.
2. Build one contact sheet of every strip and **look at it yourself**:
   ```
   py - <<'EOF'
   from PIL import Image, ImageDraw; import glob, os
   paths = sorted(glob.glob("assets/testfit/out/*_strip.png"))
   rows = []
   for p in paths:
       im = Image.open(p).convert("RGB"); im = im.resize((1600, int(im.height*1600/im.width)))
       bar = Image.new("RGB", (1600, 30), "white"); ImageDraw.Draw(bar).text((10, 8), os.path.basename(p), fill="black")
       rows += [bar, im]
   out = Image.new("RGB", (1600, sum(r.height for r in rows)), "white"); y = 0
   for r in rows: out.paste(r, (0, y)); y += r.height
   out.save("assets/testfit/out/_contact_<EraName>.png"); print(out.size)
   EOF
   ```
   Check: price ramp reads humble → grand in slot order; the monument is the tallest; the era's
   palette is consistent; nothing looks like a floating post or an unfinished roof; stage jumps
   are spread across the five stages, not all at stage 2.
3. Route fixes back with `SendMessage` to the owning builder (it resumes with context). Accept
   small by-design overhangs only when the layout has room (Village windmill precedent: 0.5 stud).
4. Fold any new kit facts from the reports into `tools/testfit/README.md`.
5. **Ben approves the contact sheet before anything is uploaded.** Show him the path.

## 3. Pipeline (you; commands from `docs/MANUAL_STEPS.md` M7)

```
export PATH="$HOME/.rokit/bin:$PATH"
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/assets/merge_stages.py -- --era <EraName>
py tools/assets/upload_models.py --era <EraName> --dry-run      # expect ~85 uploads, 0 problems
py tools/assets/upload_models.py --era <EraName>                 # run in the background; ~12 s each
py tools/assets/upload_models.py --era <EraName> --model <Name>  # retry any "Unknown Error" (idempotent)
py tools/assets/harvest.py --emit && cat tools/assets/harvest.luau | clip
```
Ben pastes the clipboard into the Studio command bar (Edit mode), waits for `[HARVEST-DONE]`,
copies Output (right-click → Select All → Ctrl+C). Then:
```
py tools/assets/harvest.py                     # reads the clipboard; or --file <path>
py tools/assets/gen_templates.py && py tools/assets/gen_templates.py --check
rojo build -o build/test.rbxl
py tools/gen_asset_manifest.py && py tools/gen_asset_manifest.py --check
git add templates src/shared/Config/Assets.json docs/ASSET_MANIFEST.md && git commit
```
No code changes are expected for a content era. If any Luau changed, run `roblox-reviewer`,
`qa-runner`, and `docs-keeper` per CLAUDE.md; otherwise `docs-keeper` only needs a PLAYTEST
section for the era ("buy every slot, walk the plot, level one building 0→100 with `GrantCash`").

## 4. Report to Ben

Blueprint count and the contact sheet path; uploads done / retried; harvest paste done; templates
count; what to check in Studio (the PLAYTEST section); and the era's tallest silhouettes.
