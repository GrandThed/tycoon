Assets direction and the M7 pipeline; research handoff in `docs/ASSET_RESEARCH.md`, pipeline
commands in `docs/MANUAL_STEPS.md` M7.

- Ben rejected "one Kenney file per slot" (2026-09-15). He wants buildings **assembled from kit
  pieces that grow from basic to imposing** as the player levels them — milestone levels
  `[10, 25, 50, 100]` (+75 via perk) are the natural growth stages.
- Pipeline choice stands: scripted Open Cloud upload + runtime load, no hand-importing in Studio.
- Kenney kits are mostly modular pieces, not finished buildings. Newer kits' GLBs reference an
  external `Textures/colormap.png` that must be embedded before upload; every space-kit GLB is
  invalid glTF (a `tmpParent` node) and fails upload with a completed-operation error, not an HTTP error.
  That defect is fixable (strip the node, renumber; ASSET_RESEARCH §3) and trial B was approved
  after the fix, so the kit is still usable for Orbital Colony.
- Studio check of the two trial uploads ran 2026-09-15 (ASSET_RESEARCH §3): **1 glTF unit = 1
  stud** (pieces need ~4–5× scale), one MeshPart per material, embedded textures survive as a
  separate Image asset, glTF material colours are **lost** (space-kit needs a baked palette
  texture), `MeshPart.TextureID` is writable at runtime so VIP skins can be a texture swap,
  container pivot is bbox-centre and parts arrive unanchored.

- Decided 2026-09-15 after the tavern prototype: **scale 4 (toy proportions)** and **merged stages**
  (one mesh per building stage). M7 = pipeline + Village only; M8 other eras; M9 ground/props/icons.
  Spec §8 and PLAN M7 were rewritten to match; M7 awaits Ben's go, then INTERFACES contracts.

- M7 shipped 2026-09-16 (playtest pending): all 24 Village slots uploaded, harvested and templated
  (`templates/`, generated-only). Rojo-built `.rbxmx` MeshParts load fine; Roblox dedups a kit's
  texture across uploads. The one Studio step per era is the **harvest paste** (`harvest.py --emit`
  → paste `harvest.luau` in the command bar → copy Output → `harvest.py` reads the clipboard).
  Open Cloud model uploads occasionally fail with 'Unknown Error'; the uploader is idempotent, re-run.
  `GrantCash` Workspace attribute is the Studio cash lever. Blueprint authoring works well as three
  parallel general-purpose builders with disjoint slot sets; give each a distinct scratch filename.

- Opus vs Fable blueprint test (2026-09-16, Bakery + Chapel): Opus matched or beat the shipped
  strips and self-corrected via the render loop. **Use `model: "opus"` for blueprint builders**;
  the whole per-era routine is the `/build-assets <Era>` skill (`.claude/skills/build-assets/`).

- **Open Cloud displayName is capped at 50 characters** (2026-09-17): a 51-char
  `EraCityTycoon_Path_Boomtown_Fill_SP_departmentStore` failed with HTTP 400 INVALID_ARGUMENT
  "Asset name length is invalid" — not an "Unknown Error". `upload_paths.py` now falls back to an
  `ECT_…` prefix and hard-caps at 50; any new uploader with long ids needs the same guard.

**Why:** the next session starts fresh and would otherwise repeat the rejected proposal or
re-derive the kit and upload findings.

**How to apply:** before any asset design, read `docs/ASSET_RESEARCH.md` §2 and §7; prototype one
growing building end to end before writing M7 contracts. Local research files live in
`assets/research/2026-09-15/` (gitignored). See [[environment-2026-09-08]].

- **Custom Blender geometry is a supported building source** (2026-09-18, Metropolis Stadium, Ben:
  "looks good!"). When a kit simply lacks a piece the subject needs, generate one. Three
  kit-assembled Stadium attempts failed because **none of the four City Kits has a grass or green
  ground piece** (green is only awnings, planters, signs), and a stadium without a green pitch does
  not read. The fix cost no tool changes:
  - Kits are **pure folder convention** (`assets/kenney3d/<kit>/Models/GLB format/<model>.glb`,
    `testfit.py` KITS_ROOT) — there is no registry to update, so a generated folder *is* a kit.
  - `merge_stages.py` routes **colour-only materials** (no baseColorTexture) through `palette.py`
    into a deterministic palette texture — the space-kit path. So custom pieces just carry plain
    colour factors.
  - Sample those colours from the era kit's own `colormap.png` and the result keeps the era palette.
  - `/assets/` is gitignored, so **the generator script is the committed artifact** and the GLBs
    regenerate — same pattern as `tools/pathmock/pathgeom.py`. See `tools/assets/stadium_kit.py`
    (8 reusable modules: pitch, terrace, tier, roof, floodlight, scoreboard, hoarding, dugout).
  - Judge look against the **plot base colour**, not testfit's near-white card. Metropolis is
    (88, 90, 94); a dark pitch inside white stands vanished on it, and the white-background render
    hid that from the lead through two review rounds.

- **`upload_models.py` skips any stage whose `modelAssetId` is non-zero** — no content hash, no
  `--force` (checked 2026-09-18). Changed geometry is therefore **silently never re-uploaded**; the
  run just prints "already uploaded, skipped". Workaround: clear that stage's `modelAssetId` and
  `parts` via `assets_config.save_assets` (never hand-rewrite Assets.json — `json.dumps` reformats
  the whole file into a 7000-line diff). A sha256 check is still worth adding.
