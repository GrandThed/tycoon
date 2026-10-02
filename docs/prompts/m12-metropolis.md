You are the lead engineer on Era City Tycoon (see `CLAUDE.md`). We are continuing **M12 — Growing
city**: Village and Boomtown are merged, now **Metropolis** gets the same treatment.

Read `CLAUDE.md` and every memory file it imports, especially
`.claude/memory/growing-city-2026-09-28.md` and `.claude/memory/boomtown-growth-2026-10-01.md`.
Then read, in this order:

1. `docs/CITY_GROWTH.md`, the plan of record, in full. §3 "Metropolis" and the §4 kit table are
   your starting point.
2. `docs/INTERFACES.md`: "M12 contracts — Growing city (wave 1: Village)" and "M12 wave 2 —
   Boomtown" (waves 2.0 to 2.5 with every rulings block), then "Wave 2a — Metropolis streets,
   highway, subway" (the lattice you are about to change) and the M13 sections (the river gate on
   skirt entries).
3. `docs/PLAN.md` "M12 — Growing city": what shipped, the open follow-ups, the next waves.
4. `docs/PLAYTEST.md` "M12 wave 2 — Boomtown growing city" and `docs/MANUAL_STEPS.md` "M12": the
   pattern to repeat, including the asset run and the harvest paste.
5. The Boomtown implementation, as the worked example:
   - the layout and its plan: `src/shared/Layouts/Boomtown.luau`, `tools/fabric/Boomtown.plan.json`;
   - the generated data: `src/shared/Config/Fabric/Boomtown.json`;
   - the generator and its checks: `tools/fabric.py` (lanes, plan-laid layers and placers, field
     pattern);
   - the mirror: `tools/cityfabric.py` (`selftest`, `timeline`), `tools/testfit/plotrender.py`,
     `tools/streetplan.py`, `tools/paths/` (baked pieces, `bake.py --list` exit codes);
   - the `eras.Boomtown.fabric` block in `src/shared/Config/CityDressing.json`.
6. The approved Boomtown renders: `assets/testfit/out/Boomtown/m12e_full.png`, `m12e_block.png`,
   `m12d_compare.png`, `m12c_changers_after.png`, and the prop strips in `strips/`.

## Where things stand (2026-10-02)

- **Boomtown is merged to `main`** (86d1d99). Ben: "looks really good! lets send it". It has 75
  lots, every house on a baked back lane, farmland that recedes, four city-changer slots
  (hydrants, billboards, neon, bus line) and 3-stud driveways.
- **Ask Ben for his numbers** (PLAYTEST step 37 for Village, and the same on a full Boomtown):
  instance count and frame time. Three things wait on them: the far-plot wild budget (`wildFar`
  draws 45 of Boomtown's 85 fields), `parcelsFar`, and the caps in general.
- **Open follow-ups from Boomtown** (PLAN lists them): the civic greens never draw; the Parts
  fallback for lanes sits too close to the street meshes; two Boomtown street polylines meet end
  to end without joining at (22.0, 24.9); lane clearances are measured on the data polyline, not
  the baked width. Small; a good warm-up wave if Ben wants them first.
- Start in a new worktree with `assets/` as a junction, on a new branch, as before. Remove the
  junction before removing any worktree.

## Ben's rulings that carry over

- **The concept.** "You build the landmarks, the city grows around them." Slots, order, prices,
  income and levels are untouched; only positions and client dressing change.
- **The process.** A mock on renders first, before contracts. Two real candidate layouts through
  the real generator worked well for Boomtown: the pick became the layout with nothing thrown
  away. Ben judges looks only on renders, then in Studio.
- **Every house on a road.** Ben chose lanes over density (102 lots became 75). Plan the lanes in
  from the first mock; do not add them afterwards.
- **Density still matters.** "Waaay more houses filling the terrain." Say the lot count next to
  every render.
- **City-changer slots.** A slot that "stops being a sole building" is `streetOnly` and drives an
  upgrade layer. Metropolis candidates: `highwayRamp` and `subwayLine` are already street
  upgrades; look at its `unlock` and `decor` slots and ask Ben, with a render of what each would do.
- **Ground is baked.** Anything the player sees from the tycoon camera as a surface is a baked
  planar-UV mesh or a kit tile, never stacked Parts with textures.
- **Each kit belongs to one era:** Metropolis = city-kit-commercial (+ roads, car-kit). Generated
  Blender kits are the normal answer when a kit lacks a piece.
- **Planning decisions are Ben's; ask before building.** Surface any platform or account
  requirement as a plain blocker first.

## Metropolis scope (CITY_GROWTH §3 and §4)

- **The geometry problem comes first.** Every lattice block holds exactly one landmark, and a
  7-stud tile street leaves 2 studs of verge, so there is no room for lots beside the streets.
  The fabric has to live in the 19-stud corridors that carry no street and in the band inside the
  elevated ring (low, under the deck), or the blocks get bigger. This needs its own layout study
  and mock before anything else. The 16 block slots were fixed by the wave 2a contract; that rule
  gives way.
- **Wild land:** the old town (surface car parks, fenced vacant lots, old low brick buildings,
  billboards), redeveloped block by block. It may not borrow Boomtown's kits.
- **Fabric:** generated modular towers that grow floor by floor (base, floors, crown) in the
  commercial palette; tower cranes on the skyline as the building sites.
- **Keep:** the tiles, the highway ring, the subway kiosks, Ben's park strips in undrawn street
  cells, City Hall.
- **Growth order** changes from front-row-first to outward from the entrance crossroads.

## Lessons from Boomtown (don't relearn them)

- **Measure heights against the era's landmarks** before briefing builders. A City Kit storey is
  1.6 studs at scale 4; Village's height bands made the first Boomtown shops tower over landmarks.
- **Frontage is the bottleneck.** What got Boomtown past 90 lots: narrower roads, small lots at a
  reduced kit scale, terraces, landmarks at both ends of every cross street, whole-lot gaps.
- **Prove every `check` rule by mutation.** Two generator rules turned out to be vacuous.
- **The mirror must equal the client.** Running the client's pure Luau under the Luau CLI against
  the Python mirror found drift that reading did not.
- **The plot renderer shows true colours since 2026-10-01** and follows the live street surface.
- **`upload_models.py` and `upload_paths.py --dry-run` write `Assets.json`.** A non-zero id is
  never re-uploaded: clear it through `assets_config.save_assets` first. Commit `Assets.json`
  after every upload and harvest.
- **The harvest paste:** Ben may paste the Output into the chat; his clipboard still holds it, so
  run `harvest.py` anyway. With other sessions open, sequence the pastes: one clipboard.
- **Concurrency:** check `ListAgents`; announce every upload and harvest and wait for an ack;
  never stash or overwrite another session's uncommitted work in the main checkout; give each
  subagent its own scratch folder; resume agents with `SendMessage` (it also revives ones the
  session limit killed).
- **Studio levers Ben can use without menus:** a project file with Workspace attributes baked in
  (`boomtown.project.json`: `DebugStartEra`, `GrantCash`). Make one for Metropolis.
