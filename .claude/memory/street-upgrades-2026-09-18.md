M9 wave 1e, "street upgrades", decided by Ben on 2026-09-18. Contract: `docs/INTERFACES.md` "Wave 1e — street upgrades".

- Slots named as street improvements now drive the client dressing, keyed off owned `Building_<slotId>` (still no server change). Ben's choices:
  - Village `dirtRoad` = **cobble surface + lanterns** along trails (Village has no lamp slot, so lanterns piggyback on Pave the Road).
  - Boomtown streets are **gravel until `paveMainStreet`**, then the approved asphalt + kerb.
  - **`streetlampRow` gates all Boomtown lamps** (tier-3 junction rule no longer applies there) and places them as a row along streets; `trafficLights` spawns signal props at crossings.
- A surface is a **plot-wide runtime `TextureID` swap** on the baked pieces (planar UVs make every piece take any variant; never mix per piece, the junction seam returns). Variants live in `texture.py` `variants`, `Assets.json paths.<Era>.variants`, `CityDressing.json road.paths.surface/variants`. Metropolis/Orbital slots (`cityGrid`, `walkwayNetwork`, ...) hook up by config only.
- After Ben's Studio looks: these slots are **`streetOnly`** (era JSON) — the server spawns an empty `Building_<id>` marker, no kit model (`dirtRoad`, `paveMainStreet`, `streetlampRow`, `trafficLights`); and every building is raised by `paths.buildingLift` (0.1) so floors/ramps clear the spur that runs under them.
- Ben chose **real cross streets** for Boomtown: 5 polylines, six crossings (cap `signals.maxPerPlot` 6), all 38 pieces re-baked. Design fact: roads-grow-with-buildings draws a **spanning tree**, so any closed block leaves one stretch never drawn — side streets must be dead ends. The storefront band (z −25…36) has no room for a side street; z −42 is the only full cross-street line. A re-bake changes every GLB's bytes, so all pieces re-upload (78 uploads, one harvest paste).
- **Concurrent-session hazard (2026-09-18):** a second Claude session (M8) ran asset tools at the same time and saved a stale `Assets.json` over this wave's entries (props, variants). Recovered from logs + the saved harvest paste. Never run upload/harvest tools in two sessions at once; commit `Assets.json` right after each harvest.
- Review lesson: a capped plan sorted by id **string** let polyline 1 eat the lamp budget; order numerically and thin evenly. `upload_models.py --props --dry-run` **writes Assets.json** — never run it while another agent owns that file.

**Why:** a fresh session would otherwise treat these slots as plain multipliers again, or re-bake meshes for a texture change.

**How to apply:** new "improves the street" slots get a `surface.upgrades` entry, `lamps.requiresSlot` or `signals` in config before any code. See [[city-dressing-2026-09-16]] and [[assets-direction-2026-09-15]].
