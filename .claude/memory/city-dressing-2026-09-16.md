Decided by Ben on 2026-09-16 when M9 ("city dressing": roads, trees, filler houses, squares,
vehicles) was scoped. Contracts: `docs/INTERFACES.md` "M9 contracts"; plan: `docs/PLAN.md` M9.

- **Client-side only.** The server publishes `EraName` and `GrowthTier` (0–5) attributes on each
  plot folder and nothing else; every client derives identical dressing from
  `(era, tier, owned slots, plot seed)`. Ben chose this over server-spawned props.
- **No collisions on any connective part** (Ben's explicit rule): `CanCollide`, `CanQuery`,
  `CanTouch` all false, `Anchored` true, for roads, trees, houses, plazas, lamps and vehicles.
- **car-kit belongs to Boomtown and Metropolis** (vehicles at blueprint `scale 2.5`). Village
  uses nature-kit carts; Orbital gets a rover only if space-kit has one.
- Roads are plain material Parts (hybrid: kit pieces only at junctions, bends, lamps). Ben
  accepted the recommendation without asking for the full-tile comparison.
- Icons and the experience thumbnail moved from M9 to M10.
- Props need templates the **client** can clone, so they map to `ReplicatedStorage/Assets/Props`
  (`templates/_props/`), unlike buildings in ServerStorage.

**Wave 1b, Ben's first Studio look (same day):** the tier-revealed, straight 5-stud Village roads
"don't line up with anything, way too wide and straight". Ben chose: **roads grow with buildings**
(visible spine = shortest paths from the plot entrance to each owned building's join, all eras);
**spurs start under the building** (slot anchor); Village is a **3-stud meandering Pebble trail**
(seeded arc-length noise, tapered at nodes, straight on far plots). Boomtown keeps its straight
asphalt grid. Contract: INTERFACES "Wave 1b — natural paths".

**Wave 1c, Ben's second Studio look (2026-09-17):** part-based trails still glitch (coplanar
overlaps z-fight, Pebble material seams per piece, curves read as angled rectangles). Ben chose an
**EditableMesh ribbon** (arc-length-sampled centripetal Catmull-Rom, uploaded procedural tiling
path texture with soft alpha edges) with **Beams as automatic fallback**, a **grow-along-the-path**
animation, and an **offline Blender mock first** (`tools/pathmock/`). Gate: EditableMesh/Image in
*published* games need the owner 13+ **ID verified** and "Enable Mesh / Image APIs" on in the
Creator Dashboard; Studio does not enforce it, so a Studio playtest can't prove it works live.
Ben says he is/will be verified. Buildings and trees are fine; only paths glitched.

**Why:** a fresh session would otherwise propose server-spawned dressing, collidable props, or
mix car-kit into Village, and would re-open the M9 scope.

**How to apply:** before any M9 work read the M9 contracts section; keep every dressing tunable
in `src/shared/Config/CityDressing.json`; never add a remote for dressing. See
[[era-kits-2026-09-16]] and [[assets-direction-2026-09-15]].

**Session prompt:** `docs/prompts/m9-city-dressing.md` (run the lead on Opus; prop-builders on Opus).
