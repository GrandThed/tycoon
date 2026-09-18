# Next-session prompt: Orbital Colony on space-kit

Paste everything below the line into a fresh Claude Code session at the repo root. Run the lead on
Opus; all subagents on Opus.

---

/build-assets OrbitalColony

Context from the Metropolis session (2026-09-18). Orbital Colony is the **last content era** — the
other three shipped. Read `docs/ASSET_RESEARCH.md` §2 and §4, `tools/testfit/README.md`, and the
`# M7 contracts` "Blueprints" subsection of `docs/INTERFACES.md` before splitting the slots.

## Pre-flight facts I already checked, so you do not have to

- **space-kit imports fine.** `--dump-bounds space-kit` lists **153 GLBs** from
  `assets/kenney3d/space-kit/Models/GLTF format/` (there is **no "GLB format" folder** for this
  kit — `testfit.py` looks in both, so it just works). Blender reads every one. The old
  "port the `sanitize()` fix" worry in the skill is **moot for authoring**: the `tmpParent` defect
  only broke uploading the *source* GLBs, and since M7 we upload Blender's own merged export.
  `glbtools.roblox_problems` still detects the defect and `merge_stages` checks its output, so you
  will hear about it if it ever resurfaces.
- **The real trap is the origin.** Every space-kit piece carries the `tmpParent` transform baked
  in, so its bounding-box centre is offset from the local origin by roughly **(+2.00, +1.50)** in
  X/Z — and it is *not* perfectly uniform (`alien`/`astronautA` read +1.54 in Z). No other kit does
  this. **Measure every piece with `--dump-bounds` and place from the printed min/max, never from an
  assumed centred origin**, or the whole building drifts ~2 studs off the pad. Put this in all three
  builder briefs; it is the single most likely cause of a wasted wave.
- **space-kit is a material-colour kit** — no `colormap.png`, only `Isometric/*.png` previews.
  `merge_stages.py` routes colour-only materials through `palette.py` into a deterministic palette
  texture automatically (the same path the Metropolis Stadium used). Nothing to configure, but
  expect **one extra texture asset plus a VIP swatch** for the kit in the upload count.
- **The plot is very dark: `baseColor` RGB (56, 53, 60)**, the darkest of the four eras. This
  matters more than anything else about colour. See "Judge against the plot, not the render" below.
- **Slots (24, in price-ramp order):** LandingPad, SolarArray, HabitatPod, HydroponicsDome,
  OxygenGenerator, *WalkwayTube (unlock)*, CrewQuarters, *ColonyFlag (decor)*, ResearchLab,
  RoverBay, CommsArray, *OxygenTanks (unlock)*, MineralExtractor, *RocksLarge (decor)*,
  ObservationDome, FusionReactor, *SatelliteDish (unlock)*, DockingBay, TerraformStation,
  *HoloBeacon (decor)*, MedicalBay, SpaceportTerminal, *TurretBase (unlock)*,
  **LaunchTower (monument)**. The monument sits at (0, 0, −34) facing the hub and must be the
  tallest thing on the plot.

## Judge against the plot, not the render

The Metropolis Stadium cost three attempts and a rejected Studio playtest because the lead approved
it from a testfit strip. testfit renders on a near-white card; the plot is dark. A dark model on a
dark plot has no silhouette, and the render hides that completely.

- Orbital's plot is RGB (56, 53, 60). **Before accepting any contact sheet, ask whether the
  silhouette and the surface detail would still read on near-black.** space-kit's greys and dark
  panels are exactly the risk here — the era needs bright accents (white hulls, lit panels, the
  kit's oranges/blues) to separate from the ground.
- Tell the builders this too, in their brief, so they design for it rather than fixing it later.

## If the kit cannot express a slot, generate the geometry

New capability proved on 2026-09-18 (`tools/assets/stadium_kit.py`): when a kit simply lacks the
piece a subject needs, **model it in Blender** instead of forcing kit parts.

- Kits are pure folder convention (`assets/kenney3d/<kit>/Models/{GLB,GLTF} format/<model>.glb`);
  there is no registry, so a generated folder *is* a kit.
- Give the pieces plain colour factors and `merge_stages` palettes them automatically.
- Sample the colours from the era's own palette so it does not look foreign.
- `/assets/` is gitignored, so **the generator script is the committed artifact** and the GLBs
  regenerate — the pattern used by `tools/pathmock/pathgeom.py` and `stadium_kit.py`.

space-kit is large (153 pieces) and genuinely space-themed, so you will probably not need this. Keep
it for a slot that has no honest answer in the kit rather than shipping a third near-miss — and
raise it with Ben before spending a wave on it.

## Contract points that changed since Boomtown

- `footprint` defaults to `[9, 9]`; the **monument may use up to `[14, 14]`**; and a non-monument
  slot may now go up to **`[12, 12]`**, but only where the kit cannot express the subject at 9×9
  (so far: Metropolis Stadium). Do not spend the exception casually.
- Whatever the footprint, **keep the front (−Z) face within ~4.5 studs of the origin** — the 6×6 buy
  pad sits `padOffset` 8 studs off the front and must stay walkable.
- Clearance for trees and roads is computed from **harvested extents**, not from the 9×9 literal, so
  a wider slot needs no dressing change.
- Write each era's strips to its own folder: `--out assets/testfit/out/OrbitalColony`.

## Known pipeline gap — read before uploading

`upload_models.py` skips any stage whose `modelAssetId` is non-zero. There is **no content hash and
no `--force`**, so if you change a blueprint after uploading it, the re-run prints
"already uploaded, skipped" and you ship the **old** mesh. This nearly shipped the wrong Stadium.

- Either add a sha256 check first (Ben was offered this and it is still open — ask him), or
- clear that stage's `modelAssetId` and `parts` before re-uploading. Do it through
  `assets_config.save_assets`, **never** by hand-editing the JSON: a plain `json.dumps` reformats
  the whole file into a ~7000-line diff.

## Environment

- `export PATH="$HOME/.rokit/bin:$PATH"`; Python is **`py`** only.
- Blender: `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P <script> -- <args>`.
- Files written by the Write tool come out CRLF — `sed -i 's/\r$//'` everything you create.
- Before starting, check whether **another Claude session is working in this repo**. During the
  Metropolis wave a second session was editing `tools/assets/*` and writing the same
  `src/shared/Config/Assets.json`; the tools merge rather than overwrite, so nothing was lost, but
  two asset sessions at once is how an asset ID gets dropped. Also check `git status` for in-flight
  props — they will make `gen_templates --check` and the asset manifest look red through no fault of
  this wave.

## Definition of done

24 blueprints rendering clean, a contact sheet **Ben approves before anything uploads**, then merge →
upload → one Studio harvest paste → `gen_templates.py` (+ `--check`) → `rojo build -o build/test.rbxl`
→ `gen_asset_manifest.py` (+ `--check`) → commit, and a `docs-keeper` pass for the PLAYTEST section.
No Luau is expected to change; if any does, run `roblox-reviewer` and `qa-runner` per CLAUDE.md.

This wave completes M8. M9 wave 2 (Metropolis + Orbital Colony dressing, `cityDetail`) and M10
(icons, thumbnail) are what remain after it.
