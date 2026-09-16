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

**Why:** the next session starts fresh and would otherwise repeat the rejected proposal or
re-derive the kit and upload findings.

**How to apply:** before any asset design, read `docs/ASSET_RESEARCH.md` §2 and §7; prototype one
growing building end to end before writing M7 contracts. Local research files live in
`assets/research/2026-09-15/` (gitignored). See [[environment-2026-09-08]].
