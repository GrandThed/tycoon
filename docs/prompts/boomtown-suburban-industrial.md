# Next-session prompt: Boomtown on city-kit-suburban + city-kit-industrial

Paste everything below the line into a fresh Claude Code session at the repo root.

---

/build-assets Boomtown, use city-kit-suburban + city-kit-industrial for buildings and city-kit-roads for street props

Context from the previous session (2026-09-16). The decision is in `docs/ASSET_RESEARCH.md` §4
("Era kit decision"), and the kit facts are in `tools/testfit/README.md`. Read both before splitting
the slots.

- **Two earlier Boomtown attempts are closed. Do not reuse their pieces:**
  - The retro-urban brick version was rejected.
  - The city-kit-commercial version became Metropolis's starting point
    (`tools/testfit/blueprints/_drafts/Metropolis-city-kit-commercial/`).
  - `tools/testfit/blueprints/Boomtown/` is currently empty.
- **Kit ownership is strict.** Boomtown uses only `city-kit-suburban`, `city-kit-industrial`, and
  `city-kit-roads` (props, roads, signs, lights).
  - Never `city-kit-commercial`, skyscrapers, or `low-detail-building-*` (Metropolis).
  - Never `retro-urban-kit`, `modular-buildings`, or `car-kit` (vehicles are ≥ 9 studs at ×4 and
    never fit a 9×9 slot).
  - All four City Kits share one white/slate palette, so Boomtown must read as a different era
    by **building type and scale**: houses, porches, fences, workshops, warehouses, chimneys,
    water towers, tanks and containers, lower and homelier than Metropolis's shops and towers.
- **Pipeline:** both kits use one `colormap.png`, so the M7 pipeline needs no changes. Confirm at
  pre-flight that each kit has a single texture image.
- **Brief each builder with the proven facts** (they are in the README; copy the relevant ones):
  - These City Kits are finished buildings, not wall panels. At scale 4 a two-storey building is
    only about 3.6 studs, shorter than the 5-stud player, so plan heights from `--dump-bounds`.
    Don't copy the old retro-urban caps.
  - **Growth by swallowing works:** a later, larger building at the same centre hides an earlier
    smaller one when the outer walls are flush with its bounding box. Verify each pair from the back
    with a rotated scratch copy, because the testfit camera only sees −Z and +X.
  - The bounding-box top is a parapet or rooftop box, not the roof deck. Probe roof heights before
    placing roof props.
  - `city-kit-roads` `sign-highway*` faces are green only on local −X, so use rotY 270 to face −Z.
    `detail-*`-style canopies attach on +Z faces.
  - Early cheap slots should start as props and stalls, and only add a small building at a later stage.
- **Review lessons from the last contact sheet:**
  - No two slots may share a distinctive stage-4 silhouette (Bank, Fire Station and Department Store
    all ended on the same spired tower). Assign distinctive pieces to one slot each when splitting.
  - Avoid identical stage-0 buildings across slots.
  - Keep heights rising along the price order, except for a deliberate low hall.
  - The Clock Tower monument must be the tallest silhouette, and the Radio Station the second.
- **Height targets (adjust after measuring):**
  - Boomtown should read taller and denser than Village (Village tops out at 10–23 studs).
  - Metropolis will later go well above that with skyscrapers, so leave headroom. A monument around
    22–26 studs is a reasonable ceiling.
  - If the kits are too small for that at scale 4, stop and ask Ben before changing the scale
    contract.
- **Missing models:** no kit has a bus, hydrant, bowling pin, barber pole or neon piece.
  - Last time a `construction-light` read as a barber pole or beacon, and a `road-sign-object-stop`
    read as red hose caps or a clock dial.
  - Tell Ben which slots are approximations.
  - The era config's `kit` column still says "Retro Urban Kit". Route that text change to
    economy-designer; it is display/manifest text, not a blocker.
- **Housekeeping:**
  - Renders land in `assets/testfit/out/`. Copy each Boomtown strip into `assets/testfit/out/Boomtown/`
    as reports arrive, and write the contact sheet there. Ben asked for a separate folder per era.
  - Commit each builder's blueprints as its report arrives.
  - Ben approves the contact sheet before any merge or upload.
