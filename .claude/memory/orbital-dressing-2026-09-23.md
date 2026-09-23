M9 wave 2b, "Orbital Colony dressing + cityDetail", decided by Ben 2026-09-23 and committed e0821e6.
Contract: `docs/INTERFACES.md` "Wave 2b — Orbital Colony dressing".

- Ben's choices: **enclosed corridor tubes** as the walkways (rejected: decking paths, monorail-only
  paths), **only the monorail train moves** (no rovers/speeders), **decking pads under module clusters
  + rocks/craters on bare regolith**. He approved the full-plot render with three tweaks: decking only
  under clusters (not to the plot edge — that was the Metropolis rule and it buried the rocks), rocks
  ≥ 3 studs from footprints, the monorail pier moved off the entrance axis (pier at x +2.5 in the cell).
- **Orbital was relaid on the Metropolis 7-stud lattice** (positions are not persisted, so a relayout
  is free); the old radial layout could not host axis-aligned tiles. Everything reuses wave 2a
  machinery: TileRenderer with generated `tube-kit` props (no pavement, no park strips — a capped
  airlock end reads fine), Highway in **loop mode** (`layout.highway.ramp` nil → closed ring; lanes must
  follow the corner ARC or a long train swings off the beam), paved blocks as decking, tree zones
  with a 4-stage `Rocks` prop. `walkwayNetwork` keeps its id, is `streetOnly`, named "Build the Monorail".
- Generated kits are the default answer for missing pieces: `tube_kit.py`, `monorail_kit.py`
  (space-kit's own monorail pieces are not pitch-7). Orbital-kit/tube-kit colours are raw space-kit
  factors ×255 exported linear — never add them to `SRGB_FACTOR_KITS`.
- `cityDetail`: schema **v6** (combat took v5); policy in ONE function
  `CityDressingController.detailPolicy` (another session, wave 2c "living city", extends it) —
  trees + park planters to `detail.treeShare`, no lamps, street/deck vehicles local-only, live via
  a normal sync, never a rebuild.
- Concurrency (2026-09-23): a second session works in a git **worktree** (`tycoon-wave2c`, branch
  `m9-wave2c-living-city`); we announce + ack before any `upload_models.py`/`harvest.py`, keep
  Ben's pastes separate, second-to-merge rebases, Assets.json conflicts keep both eras. One of its
  subagents ran `taskkill /F /IM py.exe` — never kill by image name; it kills every session's tools.

**Why:** a fresh session would re-propose rovers, a radial layout, decking to the plot edge, or a
client-side arc-less loop lane.

**How to apply:** read the Wave 2b contract before touching Orbital dressing; `py tools/streetplan.py`
and `py tools/testfit/plotrender.py OrbitalColony` are the gates. See [[metropolis-streets-2026-09-22]],
[[template-turn-2026-09-22]], [[era-kits-2026-09-16]].
