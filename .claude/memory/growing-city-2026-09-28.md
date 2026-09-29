---
name: growing-city-2026-09-28
description: M12 "Growing city" (approved) — landmarks + growing fabric + wild land; mocks showed layouts must be relaid for growth; plotrender pad bug fixed
metadata:
  type: project
---

Ben asked on 2026-09-28 for the city to "feel alive and like a growing city, not a grid being filled".
New models are fine; the core gameplay stays. The plan of record is `docs/CITY_GROWTH.md`.
Ben approved it on 2026-09-29: growth layouts (mock B), with an organic street plan for Village.
It is milestone **M12**, because M11 is the unmerged feature-unlocks milestone (6-player hub).
M12 is built in the worktree `C:/Users/benja/Desktop/tycoon-m12`, branch `m12-growing-city`.

**Concept.** The 24 slots are the landmarks. Around them the client draws a fabric of parcels:
- Levels: 0 wild, 1 building site, 2–4 buildings.
- Each parcel is pulled up by nearby owned landmarks and their stages, with districts per slot.
- Also in the concept: wild land that recedes, a landscape band past the plot edge, and a
  construction ripple after each purchase.

**Mock A** kept today's Village layout and added the fabric. It looked better but did not grow:
- only 9% of street-side spots fit a 6×6 lot;
- growth started as two patches.

**Mock B** relaid Village for growth. It grew as one village, and it is the recommended option.
- Heart at the entrance; slot k sits roughly k-th along the streets.
- Frontage lots sit between landmarks.
- Pull is measured along the drawn streets; parcels develop only next to already-developed land.
- A filler building is never taller than its landmark's current stage.
- A parcel's level is at most tier + 1.

Mock code and its scratch layout: `assets/research/2026-09-28-growthmock/` (gitignored). Rebuild
with `py gmb_all.py && py gmb_sheets.py`.

**Facts found:**
- Any client can read a building's stage from the single `Stage<n>` child of `Building_<slotId>`,
  so stage-based pull needs no server change.
- The world between plots is a default-grey Ground Part, 1 stud below the plot tops. Each plot has
  ≥ 58 studs free behind it and 10–47 studs at the sides.
- The buy pad is an unstyled default-grey Part.
- Moving Village or Boomtown slots forces a full path re-bake, because the spur ids are part of the
  path layout hash.
- Until 2026-09-28, `plotrender.build_pads` drew pads for OWNED slots, the inverse of
  `PlotService.refreshPads`. Older plot renders show pale pads that the game never had.

**Why:** a fresh session would otherwise repeat mock A (dressing the current layout) or trust the
pads in old renders.

**How to apply:**
- Read `docs/CITY_GROWTH.md` and the INTERFACES "M12 contracts" before any M12 work.
- M12 goes one era per wave, Village first.
- Each era gets its own growth-layout mock before contracts.

See [[living-city-2026-09-23]], [[city-dressing-2026-09-16]], [[metropolis-streets-2026-09-22]].
