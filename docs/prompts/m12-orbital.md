# Session prompt: M12 wave 4, Growing city for Orbital Colony

Paste this into a new Claude Code session opened in `C:\Users\benja\Desktop\tycoon`. Run the lead on
Opus, and every subagent on Opus (`model: "opus"`).

---

You are the lead engineer on Era City Tycoon (see `CLAUDE.md`). We are finishing **M12 — Growing
city**: Village, Boomtown and Metropolis are merged, and **Orbital Colony** is the last era.

Read `CLAUDE.md` and every memory file it imports, especially:
- `.claude/memory/metropolis-growth-2026-10-02.md`: the era most like this one;
- `.claude/memory/orbital-dressing-2026-09-23.md`: Ben's rulings on Orbital's look;
- `.claude/memory/era-kits-2026-09-16.md`: the space-kit facts and the Orbital models;
- `.claude/memory/main-auto-push-2026-10-05.md`: commits on `main` publish themselves.

Then read, in this order:

1. `docs/CITY_GROWTH.md`, the plan of record, in full. §3 "Orbital Colony" and the §4 kit table are
   your starting point.
2. `docs/INTERFACES.md`:
   - "M12 contracts — Growing city (wave 1: Village)": the base rules;
   - "M12 wave 3 — Metropolis" in full (waves 3.1, 3.1b and 3.2 with every rulings block). Orbital
     reuses almost all of it: tile streets, a ring, lanes drawn as footpaths, `levelStages`,
     `siteVariants`, `swaps`, the ring clearing, the `spots` placer;
   - "Wave 2b — Orbital Colony dressing": the lattice, tubes, monorail and decking you will change;
   - the M13 sections, for the river gate on skirt entries.
3. `docs/PLAN.md` "M12 — Growing city" → "Wave 3 — Metropolis": what shipped, the open follow-ups,
   the routine.
4. `docs/PLAYTEST.md` "M12 wave 3 — Metropolis growing city" and `docs/MANUAL_STEPS.md` M12 §12–§16:
   the pattern to repeat, including the asset run and the harvest paste.
5. The Metropolis implementation, as the worked example:
   - the layout and its plan: `src/shared/Layouts/Metropolis.luau`,
     `tools/fabric/Metropolis.plan.json`;
   - the generated data and config: `src/shared/Config/Fabric/Metropolis.json`, the
     `eras.Metropolis` block of `src/shared/Config/CityDressing.json`;
   - the tools: `tools/fabric.py`, `tools/streetplan.py`, `tools/cityfabric.py` (`selftest`,
     `timeline`, `props`), `tools/check_mirror.py`, `tools/testfit/plotrender.py`,
     `tools/testfit/compare_sheet.py`;
   - the generated kits: `tools/assets/tower_kit.py`, `oldtown_kit.py`, `metro_transit_kit.py`.
6. Renders:
   - the approved Metropolis: `assets/testfit/out/Metropolis/m12m_compare.png`,
     `m12m_changers_final.png`, `m12m_avenues_denser.png`, and the sheets in `m12m_props/`;
   - Orbital today: `assets/testfit/out/OrbitalColony/growth_today_tier2.png`,
     `growth_today_full.png`, `plot_overview.png`, `_contact_OrbitalColony_dark.png`. The two
     `growth_today_*` renders were made before 2026-10-01 and show paler ground than Studio:
     re-render "today" before you compare.

## Where things stand (2026-10-05)

- **Metropolis is merged to `main`** and on GitHub. Ben on his Studio look: "looks good!". It has
  88 lots on an "avenues" plan with four lanes, an old town that is redeveloped, towers that grow
  floor by floor, and two city-changers (Open the Bus Line, Green the Rooftops).
- **Ask Ben for his numbers:** instance count and frame time on a full Village (PLAYTEST M12 step
  37), a full Boomtown (step 59) and a full Metropolis (wave 3 step 49). He has never sent them.
  They decide `budget.parcelsFar` (a far plot draws 60 lots; Village has 116, Boomtown 75,
  Metropolis 88) and `budget.wildFar`.
- **His sign-offs were looks, not checklists.** Phone, low graphics and two players are unreported
  for Boomtown and Metropolis. The Metropolis fabric is the heaviest so far and is unmeasured.
- **A leftover folder:** `C:\Users\benja\Desktop\tycoon-m12m` is no longer a git worktree and has no
  `assets` junction. Studio had a file open in it. Ask Ben whether Studio is closed, then delete it.
- **Open follow-ups from Metropolis** (PLAN lists them): the far-plot budgets; the lane pairs stop
  half a stud apart; one subway kiosk stands on a pavement; Metropolis's old `houses`, `plazas`,
  `greenery`, `parked` and `road.tiles.blocks` config blocks place nothing and can be retired;
  `src/client/City/Fabric.luau` has 170 top-level locals against the compile gate's 180, so group
  or split it before adding to it.
- **Start in a new worktree** (`C:\Users\benja\Desktop\tycoon-m12o`, branch `m12-orbital`) with
  `assets\` as a junction and `.env` copied in. **Never commit unfinished work on `main`:** a
  commit in the main checkout reaches GitHub within a minute. Remove a junction before removing
  its worktree.

## Ben's rulings that carry over

- **The concept.** "You build the landmarks, the city grows around them." Slots, order, prices,
  income and levels are untouched; only positions and client dressing change.
- **The process.** A mock on renders first, before contracts: two real candidate layouts through
  the real generator, each in its own worktree. Ben judges looks on renders, then in Studio. He
  answers in a few words ("lovely", "looks good!"), so say back how you read his answer.
- **Density and no empty ground.** He picked the less dense Metropolis candidate for its look, then
  asked for "more density … adding 4 lanes and removing some empty space, specially what looks like
  sidewalk". Expect the same taste: narrow hard surfaces, lanes, nothing bare. Say the lot count
  next to every render.
- **Every building on a road.** In Orbital that means on a tube, or on a lane off a tube.
- **City-changer slots.** A slot that "stops being a sole building" is `streetOnly` and drives an
  upgrade layer or a prop swap. Show Ben a before-and-after render for each candidate.
- **Ground.** No stacked textured Parts. Flat, untextured footpath Parts in the tiles `spur` look
  were accepted in Studio for Metropolis's lanes.
- **Each kit belongs to one era.** Orbital is `space-kit` plus the generated `orbital-kit`,
  `tube-kit` and `monorail-kit`. Generated Blender kits are the normal answer for a missing piece.
- **Final props go to Ben as strips before any upload.** Planning decisions are Ben's; surface any
  platform or account requirement as a plain blocker first.
- **Orbital's own rulings (wave 2b, 2026-09-23):** the walkways are enclosed tubes, white
  half-pipes with grey support rings, 1.9 studs tall; **only the monorail train moves** (no rovers,
  no walkers); decking stands under module clusters only, with rocks and craters on bare regolith;
  rocks keep 3 studs from footprints; the monorail pier stays off the entrance axis.

## Orbital scope (CITY_GROWTH §3 and §4)

- **Do the density arithmetic before setting any target.** Metropolis's first target (110 lots)
  was geometrically impossible and cost a round. Facts to start from, and to verify:
  - Plot 120, fixed. The monorail runs in loop mode on ring 56: its band is 52.5 to 59.5 on every
    side, with piers, and there is no ramp. Ground inside it is 105 × 105.
  - Tubes are tile streets on the 7-stud lattice. A tube takes one 7-stud cell and has **no
    pavement**; the walkway inside it is 3 wide. So a street band is 7 studs, against Metropolis's
    11, and a block is the pitch minus 7 deep: 21 at pitch 28, 14 at pitch 21.
  - Landmarks are 9 × 9, except Fusion Reactor, Terraform Station and Spaceport Terminal
    (12 × 12, at scale 3.6) and Rover Bay (12 × 9). The Launch Tower is the monument, 42.8 tall;
    the Terraform Station reaches 23.0, the Comms Array 21.2; the others end between 6 and 17.
  - The monorail appears at purchase 6 (`walkwayNetwork`, "Build the Monorail"), far earlier than
    Metropolis's highway at 17, so whatever stands under the ring clears early.
- **Wild land:** raw regolith: craters, boulders, dust, survey beacons. Today's `Rocks` zones (a
  four-stage prop) are the seed. The plot base is (56, 53, 60): judge every prop on that colour.
- **Fabric:** pods, then pod clusters, then domes that nest small → medium → large, from space-kit
  corridors and hangars plus generated pieces. `untilStage` lets a small dome leave when the larger
  one covers it. Districts: habitat, industry, science, port.
- **Decking under development:** today's `blocks` deck a whole cluster at its first purchase, as
  Metropolis's slabs did. Each fabric prop carries its own deck plate instead.
- **Sites:** robot gantries, cargo crates, a lander.
- **Keep:** the tubes, the monorail loop and its train, the 7-stud lattice.
- **Replace:** the layout's `lots` (the small domes `HouseA/B`), `treeZones` (`Rocks`), `blocks`
  and `PlazaA`; check where the junction lamps fall on the new layout (on Metropolis 14 of 20
  landed inside landmarks).
- **Growth order:** the Landing Pad by the entrance is the seed, and the colony spreads outward.
- **City-changer candidates** (`walkwayNetwork` already is one): the decor slots `colonyFlag` (8),
  `rockGarden` (14) and `holoBeacon` (20), and the unlocks `lifeSupport` (12), `orbitalUplink` (17)
  and `planetaryDefense` (23).
- **Probably no skirt:** the ring is the colony's edge, as on Metropolis, and the Valley lies
  outside it. Decide at the mock.
- **Studio lever:** an `orbital.project.json` with `DebugStartEra` 4 and enough `GrantCash` to max
  every building. Compute the amount from `tools/sim_economy.py`; Metropolis's first guess was a
  factor of six short.

## Lessons from Metropolis (don't relearn them)

- **Renders cannot show everything; the review and the docs pass did.** The reviewer found five
  landmark footpaths lying on the road and a purchase that shrank eight standing towers. The
  docs-keeper found that 55 uploads would have been refused. Keep all three passes.
- **The gates that exist now:** `streetplan.py` (no footpath on a tile or pavement band; landmark
  extents 0.25 apart), `cityfabric.py timeline` (no purchase shrinks or re-skins a standing
  building; no FRAGILE pull), `check_mirror.py --strict` (the real `CityFabric.luau` against the
  Python mirror), `cityfabric.py props <Era>` (what any lot can show; upload nothing else),
  `check_compile.py`. Prove every new rule by mutation.
- **A low landmark must not govern lots.** Give decor and other low slots no `district`, or they
  hold their neighbours at one storey and can shrink buildings that are already standing.
- **Put new pure rules in `src/shared/CityFabric.luau`**, so the cross-check covers them. The
  mirror may implement a rule first; the client then copies it.
- **Check the client's assumptions on a different tiles era.** Orbital has no pavement, no walkers
  and no street vehicles, its walkway is narrower than its cell, and its ring has no ramp.
- **Merge and upload only the new props** with `--model` flags; a non-zero `modelAssetId` is never
  re-uploaded; `upload_models.py --dry-run` writes `Assets.json`. Asset names over 50 characters
  shorten to an `ECT_` prefix by themselves. Delete a kit's cached palette in
  `assets/build/palettes/` before a merge that follows a colour change.
- **space-kit:** its colour factors are sRGB (`SRGB_FACTOR_KITS`), and its origins are offset, so
  builders place by bounding box. Colours of the generated Orbital kits are raw space-kit factors
  exported linear: never add those kits to `SRGB_FACTOR_KITS`.
- **Prop rules that held up:** parallel faces at least 0.05 apart, no member thinner than 0.1,
  stage 0 at or under `heightFloor`, and a paved or decked plate under every lot.
- **The harvest paste:** Ben may paste the Output into the chat; his clipboard still holds it, so
  run `harvest.py --props` anyway.
- **Agents survive a session limit or a restart.** Resume each by id with `SendMessage` ("run
  `git status` and continue"); nothing is lost. Give each agent its own scratch folder, and a
  worktree of its own when two would edit the same files.
- **Check `ListAgents` before any upload or harvest,** and announce it if another session is open.
