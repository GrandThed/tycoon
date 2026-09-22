M9 wave 2a, "Metropolis streets, highway, subway", decided by Ben 2026-09-18 and shipped 2026-09-22.
Contract: `docs/INTERFACES.md` "Wave 2a — Metropolis streets, highway, subway".

- **Metropolis streets are Kenney city-kit-roads tiles at 7 studs** (= 28 / 4, four per block pitch),
  chosen per cell by visible connectivity (`TileRenderer.luau`). Ben chose 7-stud tiles with cars at
  scale 1.8 (≤ 2.7 wide) over 9.33-stud tiles with the 2.5 cars; Boomtown keeps baked asphalt, Village
  trails. Kit tiles carry only a 0.1-unit kerb, so pavements are plain Parts; the only legal street lines
  in the 4×4 block grid are x,z ∈ {0, ±28} (a 19-stud corridor holds 7 road + 4 + 4 pavement).
- **Three slots changed meaning, not id:** `cityGrid` = "Found City Hall" (kit-only, single stage —
  `unlock` slots export stage 0 only; growing it means changing the slot type and its economics);
  `highwayRamp` and `subwayLine` are `streetOnly` and drive an elevated ring (ring 56, deck 7.07,
  soffit 6.65, 3-cell ramp, 2 deck cars) and up to 5 `MetroEntrance` kiosks.
- **MetroEntrance is custom Blender geometry** (`tools/assets/metro_kit.py`, colour-only materials via
  palette.py like stadium_kit). Kit-only attempts read as a bike rack; the well is deliberately shallow
  (0.78 studs) because anything deeper vanishes at the ~23° tycoon camera — the "M" pylon, blue coping
  and dark mouth carry it.
- **Merged props are ONE MeshPart**, so the client cannot measure a deck slab apart from its rails:
  deck height is config (`highway.deckHeight`), never measured. The prop's 7-wide `HighwaySign` is
  skipped on Metropolis because it would clip a block corner; a narrower prop would appear automatically.
- The layout is a **tree** (loops lose a stretch to the shortest-path tree forever); the x=0 civic axis
  is car-free; `padOffset` is 7.5 (8 hangs block pads over the asphalt).
- Review lesson: a refactor that snapshots a value an earlier wave made mutable (`setVariant` mutates
  `state.material/color`) silently regresses the older eras; tabulate every renderer's Y before judging
  overlaps (spur top 0.2 vs tile top 0.14 floated the footpath).
- Process: agents killed by the monthly spend limit resume cleanly with a `SendMessage` to the same id
  ("run `git status`, continue from where you stopped") — no measured kit facts lost.

**Why:** a fresh session would otherwise re-propose the 9.33 scale, a kit-only subway, a growing City
Hall, or measuring deck height from the prop.

**How to apply:** for any new Metropolis street feature read the Wave 2a contract first; new tiles eras
need `road.tiles` + a lattice-aligned layout + `streetplan.py` green. OrbitalColony (`walkwayNetwork`)
and `cityDetail` are still open. See [[city-dressing-2026-09-16]], [[street-upgrades-2026-09-18]],
[[era-kits-2026-09-16]].
