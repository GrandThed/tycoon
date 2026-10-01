# Session prompt: M12 wave 2, Growing city for Boomtown

Paste this into a new Claude Code session opened in `C:\Users\benja\Desktop\tycoon`. Run the lead on
Opus, and every subagent on Opus (`model: "opus"`).

---

You are the lead engineer on Era City Tycoon (see `CLAUDE.md`). We are continuing **M12 — Growing
city**: Village shipped, now **Boomtown** gets the same treatment.

Read `CLAUDE.md` and every memory file it imports, especially
`.claude/memory/growing-city-2026-09-28.md`. Then read, in this order:

1. `docs/CITY_GROWTH.md`, the plan of record, in full. §3 "Boomtown" and the §4 kit table are your
   starting point.
2. `docs/INTERFACES.md`, every section from "# M12 contracts — Growing city (wave 1: Village)" to
   the end, including wave 1c, rounds 2 and 3, and every review ruling. The code follows them and is
   era-generic.
3. `docs/PLAN.md`, section "M12 — Growing city": what shipped, the follow-ups, the next waves.
4. `docs/PLAYTEST.md` "M12 — Village growing city" and `docs/MANUAL_STEPS.md` "M12": the pattern
   to repeat.
5. The Village implementation, as the worked example:
   - the layout and its plan: `src/shared/Layouts/Village.luau`, `tools/fabric/Village.plan.json`;
   - the generated data: `src/shared/Config/Fabric/Village.json`;
   - the generator and the checks: `tools/fabric.py`;
   - the Python mirror: `tools/cityfabric.py` (`selftest`, `timeline`);
   - `tools/testfit/plotrender.py` and `tools/streetplan.py`;
   - the `eras.Village.fabric` block in `src/shared/Config/CityDressing.json`.
6. The Village concept mocks and their renders: `assets/research/2026-09-28-growthmock/` and
   `assets/testfit/out/Village/m12e_*.png` (the approved final look).

## Where things stand (2026-10-01)

- **Village is merged to `main`.** Ben: "the village looks amazing". It has:
  - 116 houses growing from building sites around the landmarks;
  - woods that recede;
  - three city-changer slots: Plant Trees, Plant Flowers, Hang Banners.
- **Ask Ben for his playtest numbers** from PLAYTEST step 37: instance count and frame time on a
  full Village with its neighbours. The fabric budgets in `CityDressing.json` get re-cut from them.
- **A known Village regression to fix first** (small; a good warm-up wave):
  - Village lost its wave 2c chimney smoke, parked carts, bushes and hedges. They hung off the old
    `lots`, `greeneryZones` and `parking`, which the fabric replaced.
  - Re-wire the chimney smoke to the fabric house props (per-stage chimney offsets; `Ambient.luau`
    plus config).
  - Bring back a few cart spots.
  - Show Ben a before/after render.
- The `tycoon-m12` worktree and the `m12-growing-city` branch are merged. Remove them at the start
  (`git worktree remove ../tycoon-m12`, `git branch -d m12-growing-city`) after checking that
  `git status` there is clean.

## Ben's rulings that carry over

- **The concept.** "You build the landmarks, the city grows around them." The core gameplay is
  untouched: same slots, order, prices, income and levels. Only positions and client dressing change.
- **The process.**
  - A **mock first**, on renders, before any contracts. Ben judges looks only on renders, so show
    `plotrender`-style renders, never prose.
  - For Village: mock A (fabric on today's layout) looked better but didn't grow; mock B (layout
    relaid for growth) won.
- **Density.** Ben wanted "waaay more houses filling the terrain"; 116 houses was "perfecto". Narrow
  terraced lots with small alleys between them are fine.
- **City-changer slots.** Some slots are not buildings but change the city. The pattern is a
  `streetOnly` slot driving a generic upgrade layer, `fabric.upgrades.<name>`; economy unchanged.
- **Boomtown is "lower, wider"** (era-kits memory). Ordinary slots stay ≤ 13 studs and only Fire
  Station, Radio Station and Clock Tower go tall, so filler stays low too.
- **Each kit belongs to one era:** Boomtown = city-kit-suburban + city-kit-industrial (+ roads,
  car-kit).
- **Generated Blender kits are the normal answer** when a kit lacks a piece.
- **Planning decisions are Ben's; ask before building.** Surface any platform or account requirement
  as a plain blocker before proposing a design that depends on it.

## Boomtown scope (CITY_GROWTH §3 and §4)

- **Wild land:** prairie farmland (crop fields, fences, hay, a barn and silo, telegraph poles) that
  suburbs replace. It needs a **generated farmland kit** in the City Kit palette.
- **Growth.** Main Street's mouth at the entrance is the seed:
  - shops fill the gaps between the storefront landmarks;
  - suburbs spread down dead-end side streets (the plan must stay a tree);
  - industry gathers by the service lanes.
- **Fabric props:**
  - every unused suburban house type is already a landmark or a filler house, and kit houses can't
    grow in place (their roofs leave a lip), so **generate extensions**: porches, garages, extra
    storeys;
  - shops: one storey, then two with signs;
  - industry: shed, then warehouse, then works with a chimney;
  - sites: timber framing, a cement mixer, hoarding;
  - narrow lots if frontage needs them.
- **Questions for Ben, early, with renders:**
  - The street-plan style: Village got an organic plan, but a 1950s Main Street grid is
    period-correct. Show both.
  - City-changer candidates among Boomtown's special slots. `paveMainStreet`, `trafficLights` and
    `streetlampRow` are already street upgrades. Candidates:
    - `fireHydrant` (decor): hydrants along every street;
    - `billboardSign` (decor): billboards by the roads and on rooftops;
    - `neonDistrict` (unlock): neon signs on every shop;
    - `busLine` (unlock): bus stops and buses on the streets.
- **The pipeline:**
  - the Boomtown path re-bake (its layout changes: about 38 pieces);
  - prop merge and upload;
  - **one harvest paste** (`docs/MANUAL_STEPS.md` M12 §1 is the routine);
  - templates, QA, docs, playtest.

## Lessons from Village (don't relearn them)

- **Frontage is the bottleneck, not land.** Get the house count from narrow terraced lots, block
  infill (back rows anywhere in the block, `front` = the nearest earlier row-(k−1) lot) and
  landmark clearance measured from harvested extents, never from declared 9×9 squares.
- **Street trees must not take house frontage.**
- **`tools/fabric.py` reads the pull config.** After any `fabric.pull` change, rebuild the data;
  otherwise `check` fails with "differs from a fresh build".
- **The pacing lever** is `rowLag` / `tierTerm`. Keep building sites visible at every tier (pillar:
  "the frontier always has sites"). The final jump comes from streets that only open with the
  last landmarks, which is a layout matter.
- **The Python mirror must match the client exactly.** Sum pulls in slotId order with an explicit
  loop, use `sqrt`, and default `rowLag` with a None check. `py tools/cityfabric.py selftest` and
  `timeline` are the gates; compare against the generator's own numbers.
- **The code is generic; don't fork it per era.** Era data lives in `Config/Fabric/<Era>.json`,
  `fabric` config blocks and `fabric.upgrades` layers.
- **Phones:** unanimated spawns go through the shared `spawnsPerFrame` budget (40), budgets are
  index prefixes, and far plots draw whole clumps and the first `parcelsFar` parcels only.
- **The harvest paste:** Ben may paste the Studio Output into the chat instead of saying "done".
  The chat truncates it, but his clipboard still holds the full Output, so run `harvest.py --props`
  anyway. A killed `upload_paths.py` / `upload_models.py` resumes cleanly.
- **Concurrency:** if another Claude session is active (`ListAgents`), work in a git worktree with
  `assets/` as a junction, never run uploads or harvests at the same time as another session, and
  commit `Assets.json` right after each upload and harvest.
- **Delegation:** brief agents with the INTERFACES sections, file ownership and a definition of
  done. Resume the same agent with `SendMessage` for follow-ups, which keeps its measured facts.
  Builders render street-context shots with `plotscene.py`; keep asking for those.
