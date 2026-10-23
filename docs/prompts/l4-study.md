# L4 study — the real forest (brief)

Three groundwork study agents run in parallel for milestone L4 of a Roblox project. Work in the worktree
`C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest` (at `main` 443c704). **Write no code and edit no
repo file except your own report.** Scratch files go in your own subfolder of the session scratchpad you are
given. Kill only your own PIDs, never by image name. Tools: `py` (never `python`; `py script.py` honours a
`#!/usr/bin/env python` line and then runs 3.12 without Pillow, `py -c` and scripts without that line run 3.14
with Pillow); rokit tools need `export PATH="$HOME/.rokit/bin:$PATH"`; the Luau CLI is
`C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`; Blender is
`"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"`.

- **Part A (the forest)** writes `docs/prompts/l4-study-report-forest.md`.
- **Part B (the Camp Chief and the raiders' looks)** writes `docs/prompts/l4-study-report-chief.md`.
- **Part C (the hub map, rewards, the end screen and the publish)** writes `docs/prompts/l4-study-report-publish.md`.

Each report: under about 300 lines, plain words, file:line evidence for every claim about the code. Say what you
measured and what you only read. End your reply with a ten-line summary and the report path.

## What L4 is

`docs/MISSIONS_DESIGN.md` §14: **"L4. The real forest: scenery, the Camp Chief, the map in the hub, rewards
balanced. First version that can be published."** Read `CLAUDE.md` (rules), MISSIONS_DESIGN §4, §5, §12.1
(Forest Road as planned), §13 (risks) and §15–§25 (every verdict since; grep `L4` for what was carried), the
`docs/PLAN.md` sections "L1" through "L3" (grep `L4` for carried items and their owners), and the INTERFACES
sections you need (`grep -n "^# " docs/INTERFACES.md`; L1 at line ~9691, L1b ~11370, L1b Wave 4 ~14221, the L1c,
L2 and L3 sections point to `docs/prompts/*-contract.md` files). Forest Road's data is
`src/shared/Config/Levels/1_ForestRoad.json`; the level is built by `src/combat/server/Services/LevelGeometry.luau`
and run by `LevelService` / `StageFlow` / `CampBrain`; the crowd's walkable world is `src/shared/Region.luau`;
the gates are `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/check_stage_mirror.py`,
`tools/crowd_harness/`, `tools/sim_combat.py`, `tools/sim_range.py`.

Ben's standing rulings that bind L4 (do not re-open them):
- Forest Road as merged and closed: the winding road (~1,055 studs), camps A Pickets / B Main Camp / C the Chief's
  Clearing (walled, a bent gatehouse, a flank ambush, then the boss), tents as a pace reserve, the secrets chain
  (lookout ledge by Double Jump, the Flamethrower chest, the Pickets-bypass cave behind brambles, the pond island
  shrine by the Frost Hammer). Raiders follow anywhere on the road and give up when they lose you; an unreachable
  shooter makes them give up. Only the boss room locks.
- **"Natural barriers instead of fenced squares"** (paths that hinder the enemies' passage) were promised for L4.
- **The sniper perches are fixed in L4:** `SNIPER_KNOWN_LIMIT_L4` must be empty (Normal and Hard) and the gate
  green on every spot before L4 ships.
- The boss is **the Camp Chief**: "a giant brute in front of his tent: a charge, a slam, and a call for raiders,
  built from the boss rules that exist (the Colossus's attacks, new numbers, a new model), not a new boss system".
- The end screen (Ben, §17.5): "animating coins entering your inventory, items piling up".
- Combat look: **detailed models** (over chunky low-poly). **No sound in combat.** Phones must work from the start.
- Ben judges from pictures: renders, and ASCII sketches in click questions. He rejects a look that resembles
  another part of the game ("way too similar to metropolis") and has chosen organic every time it was offered.
  He judged L1's camp mechanic within two minutes of play: show behaviour, not only looks, where it matters.
- Lessons that are rules here: coplanar faces shimmer (inset or move); "cannot be seen" means every way of looking
  (camera boom, Reset, AlwaysOnTop markers, the top of a double jump); a ground surface a player sees from the
  game camera was never stacked Parts in the city (baked planar-UV meshes); EditableMesh is not proposed without
  asking Ben; any platform, account or age requirement is stated plainly as a blocker before a design depends on it.
- Publish: both places (the city hub and the Expeditions/dungeon place) publish together at L4, from `main`; the
  hub is live today with players' saves. ProfileSchema is shared (v8 since L3).

## Part A — the forest

1. **Forest Road today, as a player sees it:** what `LevelGeometry` builds (Parts, colours, materials, sizes,
   counts), the road, the floors and heights, the camps' fences, camp C's wall and gatehouse, the cave, the pond and
   ice cells, the chests, the perches, the lobby camp. What collides and what does not. Instance and part counts.
2. **How the enemies see the world:** `Region.luau` (one shared height region, doors, `known`/`reachable`), what a
   fence does for the crowd today, what a "natural barrier" (a rock band, a fallen log line, a thicket, a stream, a
   cliff step) would have to be in data for the crowd to respect it, and what it costs the gates (`check_levels`,
   the sniper gate R8, the walled-camp sight gate, the stage mirror, the harness).
3. **The sniper perches:** each spot in `SNIPER_KNOWN_LIMIT_L4` (Normal and Hard), why it out-earns, and what a
   re-placed perch or a natural cover change would need for the gate to pass on every spot.
4. **Scenery routes, honestly compared:** (a) baked meshes from one generator, like the Valley
   (`tools/world/valley.py`, `upload_world.py`, harvest kinds `worldMesh`, `templates/_world/`, Parts-only
   collision from generated JSON, `planHash`); (b) Roblox Smooth Terrain written by code when the level is built
   (FillBlock/FillWedge/WriteVoxels; materials; Terrain water swims, which breaks the deep-water rule; the cost of
   writing and clearing it per run; how it looks at the game camera); (c) kit props (`nature-kit`, the Village
   trees and rocks already uploaded) placed from data, client-side or server-side. For each: the look, collision,
   the crowd, phones (triangles, draw calls, memory), how many uploads and harvest pastes Ben must do, and how a
   later level (the Castle) would reuse it. Recommend one, or a mix.
5. **Generated pieces** §12.1 names (tents, palisades, the chief's tent) and whatever the forest needs that
   `nature-kit` lacks: the generator pattern (`tools/assets/*_kit.py`, colour-only materials via `palette.py`,
   testfit strips Ben approves before upload), a triangle budget per piece and for the whole level at the game
   camera, and whether the Village/Valley palette fits a forest.
6. **Pictures for Ben:** the cheapest honest way to show him the dressed Forest Road before anything is uploaded
   (a top-down plan plus three or four player-eye views of camp A, Main Camp, the gatehouse and the lookout). Find
   what the Valley mock (`assets/research/2026-10-01-worldmock/`), `plotrender.py` and `tools/world/preview.py` can
   reuse. If one rough proof render is cheap (under ~20 minutes of your time), make it and put it in your scratch
   folder; otherwise describe the route.
7. **Decisions for Ben** (only what truly needs him; 2–4 options each with a recommendation and the cost; looks
   and barrier kinds as ASCII previews of about 40 columns × 16 rows), **risks** in plain words.

## Part B — the Camp Chief and the raiders' looks

1. **What the raiders look like today:** how `CrowdRenderer` (and `CampFx`, `ThreatFx/`) draws bodies (parts,
   rigs, pooling, per-frame cost, how many bodies at once on Forest Road, LOD), what each kind (fodder, slinger,
   brute, lobber, marksman, plated elite, the Colossus, the Warlord and guard) shows, poses and animation, the
   plate bar, the hit shapes (`HitShapes.luau`, the upright capsule from L1b W2) and how a drawn model must agree
   with them (the head shot rule; PLAN's carried "a shot at a seated raider's drawn head").
2. **The Camp Chief:** today's camp C boss (the Colossus: attacks, numbers in `ProvingGrounds.json` / the level
   file, enrage, the summon), what "a charge, a slam, a call for raiders" reuses as-is, what new numbers the
   Chief needs, whether one signature attack or tell would make him read as a different boss at no system cost,
   and every gate and simulator that pins the Colossus's numbers at camp C.
3. **Models:** a route for detailed generated enemy models (no Kenney character kit exists; `people_kit.py` and
   the L3 weapon kit `tools/assets/weapon_kit_*.py` are the precedents), drawn client-side on crowd bodies of 100+
   residents: triangle budget per kind, how a pose or a simple animation is done without Humanoids, how the models
   reach the client (route, uploads, harvest pastes), and scale against an R15 player. Whether the raiders'
   models belong in L4 at all (a forest full of placeholder bodies may not be publishable), and what a minimum set
   would be. Consider the weapons the raiders hold (the L3 weapon models are uploaded).
4. **Decisions for Ben** (options, recommendation, cost; looks as ASCII previews), **risks**.

## Part C — the hub map, rewards, the end screen and the publish

1. **The map in the hub:** `src/client/UI/MapScreen.luau` (PLAN: "the hub mounts it in L4"), how the hub's
   Expeditions panel and Depart work today (`ExpeditionPanel.luau`, the teleport and Studio bridge, the RunTicket,
   party), what "the map in the hub" changes (pick a level and difficulty in the city and land in that level, or
   land in the lobby with it chosen), what the old per-era missions in the hub become, and the Raider Arena node.
2. **Rewards balanced:** the whole lap. What a Forest Road run pays per difficulty (cash, Valor, Timber, chests,
   per kill, camp bonus, boss), against the city's income at the eras a player has when they first go (read
   `tools/sim_economy.py` and `docs/BALANCE.md`); what the city should get from a level and the level from the
   city; Hard and Brutal; the three-runs-a-weapon climb (L3); what `sim_combat.py` and the economy sim can measure.
   Name the numbers that look wrong and propose targets.
3. **The end screen:** today's `SummaryCard` (and the hub's `ExpeditionSummaryCard`), the per-camp clear bonus on
   screen (carried), and what "coins entering your inventory, items piling up" needs (UI motion with no sound,
   phones).
4. **Everything carried into L4:** grep `L4` in `docs/PLAN.md` and `docs/INTERFACES.md` (and the L-contract files
   in `docs/prompts/`); list each item with its owner, what it needs, and whether it blocks the publish. Include
   the dash check (`OnDash` against the PositionRing), RunState's resent cells, sight through walls, deleting the
   old C1/P5 modules and `Armory.json slots`, the Theme round, phone fits, the two-client check, the run cap.
5. **The publish:** what must be true before both places publish (MANUAL_STEPS "L4-0", the R15-only avatar
   setting, "Shut down all servers", place ids in `Places.json`, the live hub's version and what a v8 profile does
   to it, the frozen live Expeditions place, DataStore and teleport safety, the audience-reach state in memory
   notes), what Ben must do in Creator Hub, and what can be checked only on the live pair. A checklist.
6. **Decisions for Ben** (options, recommendation, cost; screens as ASCII previews), **risks**, and a **wave
   split for all of L4** (each wave playable on its own in Studio, the forest look first because it needs Ben's
   pictures and an upload) with owners (`luau-engineer`, `ui-engineer`, `economy-designer`, a kit builder).
