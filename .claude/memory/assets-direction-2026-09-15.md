Assets work (pre-M7) is research only so far; the full handoff is `docs/ASSET_RESEARCH.md`.

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

**Why:** the next session starts fresh and would otherwise repeat the rejected proposal or
re-derive the kit and upload findings.

**How to apply:** before any asset design, read `docs/ASSET_RESEARCH.md` §2 and §7; prototype one
growing building end to end before writing M7 contracts. Local research files live in
`assets/research/2026-09-15/` (gitignored). See [[environment-2026-09-08]].
