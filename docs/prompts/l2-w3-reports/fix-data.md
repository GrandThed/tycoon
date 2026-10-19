# L2 W3 fix round: data agent (economy-designer), 2026-10-19

Branch `l2-w3` in `tycoon-p5`; nothing committed. Rulings from `docs/prompts/l2-w3-fix-round.md` (the data
agent's list), plus the lead's relayed Q1 figure. Full numbers and tables: `docs/BALANCE.md` "L2 W3 fix round".

## Files changed

- `src/shared/Config/ProvingGrounds.json`: `controls.iceAutoDegrees` **34**. This is the lead's relayed figure
  from the client's Q1 measurement: at 60, a phone on Road2's outer 2.5 studs still swings at the creek.
- `src/shared/Config/Combat.json`: `levels.react.ice.thickness` 1 → **4** (d-m6).
- `src/shared/Config/Levels/1_ForestRoad.json`: `secrets.shrine.materials` 63 → **60** (s3).
- `src/shared/Layouts/Levels/ForestRoad.json`: `CreekUp.landing` **(−385, 0, −2)** on Road2 by the creek (Q3).
- `tools/sim_range.py`:
  - mirrors of the server's rules:
    - `ice_cells`: a cell is skipped only when ONE cover holds it whole, to `GEOMETRY_SEAM` 1e-6.
    - `react_problems`: `"<where> has a landing and collides"`, and the ice overlap line
      `"<a> and <b> are ice and overlap"` (`ice_overlap` = `LevelGeometry.Overlap`).
  - `FAMILY_TARGETS.frostHammer` 75 / 439 (d-m2).
  - `frozen_layout`'s docstring.
- `tools/check_levels.py`:
  - **s-M1 and Q3, the fall line** in `check_deep_water`. It runs on the water as built and frozen:
    - every deep water a top lies within a dash-off's carry of (dash + walk over the fall to killY + a body's
      radius) has a landing;
    - `rescue.outside` ≥ one server frame of the dash (2.22) where a top meets the water.
    - `ctx["rescue"]` is new for this line.
  - **s-s2:** the overlap line.
  - **d-m1:** the fill line (`ice_holes`, exact).
  - **d-m3:** Leap Smash's fall term in `island_reach`.
  - **s1:** `dashing_abilities` follows `MECHANICS.x = MECHANICS.y` aliases, and takes an optional text.
  - **d-m6:** `ice` is in `GROUND_LOOKS`.
  - **s2:** `check_ice` also runs `check_route_skips`, `check_cave` and `check_walled` on the frozen layout.
    - Bend: sheets count as walked ground, joined to the road they touch. Only pairs with a sheet are judged.
    - Cave: the closed half only.
    - Walled: whole, except the sight lines judge only the eye points on tops the ice adds. This is exact given the
      dry run.
- `tools/check_levels_mutants.py`:
  - 20 new cases and 3 re-aimed ones. The re-aims are a landing on Road2, the ice-collides case without its
    landing, and the dam across the creek.
  - 1 new mirror case (overlap) and 2 re-aimed mirror cases.
  - an `sr` switch (`swapped_sim`: a copy of sim_range with one line swapped);
  - `frost_quake_dash`.
- `docs/BALANCE.md`: the section "L2 W3 fix round".

## Gates (final tree, with the server's and the client's changes in)

- `py tools/check_levels.py`: **PASS**, about 42 s (was 34).
- `py tools/check_levels_mutants.py --luau …/luau.exe`: the one full run was 205 of 206 as expected.
  - The one miss was the old dam case. d-m1 made it green: a 4-stud dam holds no 6.77-stud row whole.
  - I re-aimed it to a 50-high dam holding row 6 whole and added a control (the old dam, green). Both were then run
    alone: red and green.
  - All 9 stage-mirror cases are red as required, and the simulator case is red.
- `py -3.12 tools/sim_range.py --check`: **PASS**, 524 checks, exit 0.
- `py -3.12 tools/sim_combat.py --check`: **PASS**, 23 of 23.
- `py tools/check_stage_mirror.py --luau …`: **PASS**.

## Measured

- **Ice pieces:** 132 → **136**; Parts **252** of 600 (equal to the server's Pieces).
  - The two slits beside the island (48.5 studs²) are closed.
- **Crossing:** 9 swings, 9.0 s human / 5.8 s ideal, 109 studs, 39 cells frozen.
- **Island reach:** the worst is still Impale Dash held in the air, 80.6. Leap Smash with its fall is 74.5. The margin
  is **+21.5**.
- **Shrine chest:** 6 Valor + 60 Timber, which is 28% of 211.
- **Frost Hammer:** single 75, crowd6 439, inside bands 64–86 and 373–505. Boss rows are unchanged: Colossus
  83.2–84.9 s, Warlord 102.9–107.1 s, all L2-39 margins as before.
- **Frost Hammer + Longbow pair:** 4.46 / 4.69 / 4.43 min, ×0.95 cash.
- **Frozen bend:** the most any hop from the ice saves is 20 (rule 60).
- **Frozen walled run:** the tops the ice adds lie outside every gate's half-plane, so there is no eye.
- **Landings:** CreekUp, Creek and Pond all land on Road2 by the creek. Road1, 26 studs from CreekUp, is covered by
  the position test.

## For the lead

- **Cost of s2:** each check_levels run is about +8 s, and the full mutant driver went from about 1.5 h to about
  2 h 10 min (196 data cases).
  - Judging every eye again on the frozen layout would have cost 11 s more a run. That is why the sight lines are
    incremental.
- **Thickness 4 (d-m6):** the server's report flags two Studio-only risks.
  - Side faces may shimmer where an outer cell's sides share the water block's planes, now from −4.8 to −1.
  - A PC swing early in a fall can turn a 4-deep cell solid around the legs.
  - If Studio shows either, the server proposes a hair inset of the outer cells. That inset would need the same
    inset in `ice_cells` and the fill line.
- **s-s1 (known limit):** recorded in BALANCE. Cover is judged by a block's top only, and camp pieces never cover.
  Nothing on Forest Road is affected.
- **Q3 scope:** the fall line does not promise one case. A dash-off from a top that does not meet the water, crosses
  only a footprint's corner and is more than 4 past it when judged still goes to the safe point. Nothing on Forest
  Road is shaped that way.

## For other owners

- **Server agent:** none outstanding. Its stage-mirror case "a pool that collides, with no landing" is the one my
  ice-collides mirror case names, and it is in.
- **Economy.luau:** no formula change needed.
