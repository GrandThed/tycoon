---
name: metropolis-growth-2026-10-02
description: M12 wave 3 (Metropolis growing city) — density ceiling, two candidates at Ben's gate, tiles-era alleys, prop swaps, site variants
metadata:
  type: project
---

M12 wave 3, Metropolis, started 2026-10-02 from `docs/prompts/m12-metropolis.md`. Contract: `docs/INTERFACES.md`
"M12 wave 3 — Metropolis" → "Wave 3.1" (a gate for Ben, not yet a contract). Base worktree
`C:\Users\benja\Desktop\tycoon-m12m` (branch `m12-metropolis`); candidates `tycoon-m12m-avenues` and
`tycoon-m12m-boulevard` (branches `m12-metropolis-<c>`), all with `assets\` junctions.

**The density ceiling is geometric.** A tile street costs a 15-stud band (7 road + 4 + 4 pavement), the
ring deck leaves 105 × 105 inside, and only three street lines with a row each side fit across. Rows of
lots on streets top out around 50–70; even the whole square tiled with rows holds ~136 narrow lots, ~93
after 22 landmarks. The contract's first target (110) was set from Village/Boomtown without that
arithmetic; both designers proved it impossible in step 1. Narrow lots became 4 × 8 (+25%).

**Candidates at the gate:** "avenues" (cross-town street + three avenues, lots on streets only, 67 lots)
and "boulevard" (axis to the Skyscraper, two cross streets, four pedestrian alleys, 75 lots: 13 street +
62 alley). Boulevard is denser but reads as uniform terrace superblocks (two narrow props per district);
the 3-stud alleys barely show from the tycoon camera. Sheet: `assets/testfit/out/Metropolis/m12m_compare.png`.

**Ben picked avenues (2026-10-03):** "i love avenues … but … more density … adding 4 lanes and removing some
empty space, specially what looks like sidewalk". Wave 3.1b: pavements 4 → 2 (walkers 4.5; a street band
is now 11, so pitch-28 blocks hold two 8-deep rows), four tiles-era lanes where they add lots, landmarks
brought to the street line, subway kiosks beside the (too narrow) pavement. Boulevard stays as a record.

**Rulings taken by the lead for the mock** (Ben has not judged them yet):
- Block slabs dropped (a slab paved a whole block at its first purchase: a socket); every fabric prop
  carries its own paved forecourt. Street trees went with them → the `cityPark` changer proposal.
- Old town (generated `oldtown-kit`) is the wild: 13 × 13 clumps on a 14 grid, ≤ 3.6 tall; it may stand
  under the future highway and clears when `highwayRamp` is owned (mask adds the ring rects). No skirt.
- Tiles-era alleys = wave 2.4 lanes drawn exactly like a Metropolis spur footpath (flat Concrete Part,
  0.01 under the kerb, clipped at the pavement edge): the footpath look Ben approved in wave 2a, no bake.
- Mirror-first rules the client must copy in wave 3.2: `levelStages` [1, 3, 4] (five-stage towers grow
  floor by floor under the height cap), `siteVariants` (cranes on narrow/small sites), `swaps`
  (prop twins `…Green` / `…Crown`), the ring-rect mask, tiles-era alley drawing, `kerbside` layers.
- `LANDMARK_GAP` 0.25 (Boomtown's shipped carDealership/bank stand 0.30 apart).

**City-changer proposals** (renders `m12m_changers.png`, on avenues): busStop → Bus Line (no lot cost),
cityPark → Street Trees (−10 lots on avenues: the park governs a whole row), rooftopGarden → Green the
Rooftops (prop swap), financeDistrict → Finance crowns (prop swap, subtle) or stays OfficeTowerB.

**Why:** a fresh session would otherwise re-set a 100+ lot target for Metropolis or Orbital (same
lattice), re-litigate the slabs, or try to bake alleys in a tiles era.

**How to apply:** check `m12m_compare.png`, ask Ben for his pick and the four changer answers, then write
wave 3.2 contracts (client follows the mirror-first rules above; final props with strips; no uploads
until Ben approves). Orbital (wave 4) has the same 7-lattice and ring: run the density arithmetic first.
See [[growing-city-2026-09-28]], [[boomtown-growth-2026-10-01]], [[metropolis-streets-2026-09-22]].
