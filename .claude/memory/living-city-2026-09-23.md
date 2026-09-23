---
name: living-city-2026-09-23
description: M9 wave 2c "living city" rulings - more lots/greenery/parked/walkers/smoke/birds per GrowthTier; parallel-session worktree workflow
metadata:
  type: project
---

M9 wave 2c, asked for by Ben on 2026-09-23 ("make the cities more alive, with more houses and
trees and vehicles as the cities progress"). Contract: `docs/INTERFACES.md` "Wave 2c — living city".

- **Rulings:** growth stays on `GrowthTier` (no clock); Village/Boomtown/Metropolis only (Orbital was
  wave 2b, built at the same time by another session); all four life kinds ship; no day-night cycle.
- **`Theme.reducedMotion` is true on every touch device**, so it is not an accessibility flag here.
  Particles and ambient life gate on `Theme.lowEndDevice` (graphics quality <= 3, spec section 10);
  gating them on reducedMotion would have hidden them from every phone player.
- No Kenney character kit exists locally: walkers and birds are generated (`tools/assets/people_kit.py`),
  bushes/hedges/beds for the City Kit eras too (`garden_kit.py`). Kenney kit doors are only ~1 stud at
  scale 4, so 1.75-stud walkers are taller than doors on purpose (readable at game distance).
- Village cannot fit more 9x9 lots: new lots are a `"small"` kind (<= 6x6, <= 6.0 tall), sized per
  kind in Scatter. Metropolis lots under the ring must be small (soffit).
- **Walk lanes are clipped at every solid except pads** (lots, kiosks, lamp posts, signals, slot
  footprints); a clip end is a dead end. Pads are walkable - clipping at them cut every Metropolis
  avenue into 14-stud stubs. streetplan mirrors the clip rule exactly.
- A new lateral line (walkers) must be checked against every existing solid on that line: the first
  Boomtown walker offset sat exactly on the row-lamp line. Walkers must also clear car width + lane.
- "Expected yield = count x plantable share" overstates greenery; streetplan now runs the client's
  draw (no redraw, mutual clearance) over 120 seeds and fails if p10 < perTier[5].
- Luau infers an array literal's element type from its first entry: an entry missing an optional
  field (`kind`, `lot`) after one that has it fails luau-lsp. Put a field-less entry first or write
  the field.

**Parallel-session workflow that worked:** own git worktree (`C:\Users\benja\Desktop\tycoon-wave2c`,
branch) with `assets/` as a junction to the main checkout and `.env` copied in; announce every
upload/harvest to the other session and wait for its ack; one harvest paste per session, in turn;
merge main into the branch once the other session's harvest is committed (one Assets.json merge,
which git auto-merged since eras are separate keys). A subagent once ran `taskkill /IM python.exe`,
which can kill the other session's tools - every delegation prompt now says "kill only your own PIDs".

**Why:** a fresh session would otherwise gate ambient life on reducedMotion, clip walkers at pads,
or trust the old yield estimate.

**How to apply:** read the Wave 2c contract before any dressing change; new dressing kinds that
detail-off should drop go in `detailPolicy`. See [[city-dressing-2026-09-16]],
[[metropolis-streets-2026-09-22]], [[street-upgrades-2026-09-18]].
