# L1b Wave 2 build — economy-designer report

Written as the work goes. A fresh agent continues from "Left".

## Done

1. **Config keys landed (first edit):**
   - `src/shared/Config/Combat.json`: `camps.tent` `{ sight 24, cone 360, rise 0 }`,
     `camps.joinFactor` 2, `camps.dormantRadius` 120; `debug.provingGear` 2 / 2,
     `debug.gearPresets` `2 / 2`, `4 / 4`, `6 / 6`; `debug.perfAttribute` `"CrowdPerfMs"`;
     `levels.populationReserve` **removed** (B's `StageFlow` reader and my `check_levels.py`
     reader go with it).
   - `src/shared/Config/Expeditions.json`: `looks.tent` `{ material "Fabric", color [222, 184, 120] }`
     (a canvas tan; not the fire's orange; channel spread 102, so check_levels reads it as a colour look).

2. **Level and layout adopted** from `docs/prompts/l1b-w2-layout/winding.*.json`:
   `Config/Levels/1_ForestRoad.json` (`clearBonus` = `{ "share": 0.1 }`) and
   `Layouts/Levels/ForestRoad.json` (each `tent` block gains `radius` 10). **Camp A's tent moved 6
   studs west** (x -201.5 -> -207.5) so its ring clears A.loop's patrol (lead's answer: the
   designer's choice; the patrol and the picture are unchanged). Numbers still the draft's until the
   tuning step.

3. **Mirrors and gates written** (all four tools, first pass, 2026-10-14):
   - `tools/sim_range.py`: `hs_ray_upright` / `hs_crowd_ray` / `hs_flat_to_rect` (the `"ray"` shape
     and every projectile path go through `hs_crowd_ray`; projectiles now crit as the game's do);
     `RAY_RULE` switch ("capsule" / "sphere") used only by the bow report; the CampBrain mirrors
     (`cb_dormant`, `cb_gap`, `cb_join_in`, `cb_rouse`, the tent rule, the tent posture in
     `cb_posts`, `cb_posture`, `cb_problems`); `sg_*` (SwingGate); StageFlow mirrors `tents_of`,
     `boss_reserve`, `population_of` (new rule), Validate's new lines, `plan_level` tents / stock /
     tentStock; `LevelRun`: tents (groups after the residents, sent in `tick` before Advance,
     roused at the next camp step), the join-in, dormancy (bodies not integrated, separated or
     clamped), the clear bonus by `ClearBonus` on the camp's stock (+ C's `waveStock`), `tentLeft`
     in `progress`, `DeadFraction` in the merge test, `stands_up`; policies `sneak` and `cross`
     (the careless road); the forest bands of "Balance bands" (see `check_forest`).
   - `tools/sim_combat.py`: `clear_bonus`, `wave_stock`, `dead_fraction`; 21 pays each camp's bonus
     and gates the bonus share (5-10%) and Hard / Brutal pay x2-x3 / x4-x6 again; 23 is L1b-W2-5.
   - `tools/check_levels.py`: the Wave 2 table (sizes, route, residents, sneak, post spacing,
     population, tents, markers, looks 13, dormantRadius, joinFactor, chain table, checkpoints with
     tent groups) and gate 16's printed block. `partsL1` dropped; `part_count` counts tent markers.
   - `tools/check_stage_mirror.py` + `stage_mirror.luau`: everything "Simulators and mirrors" lists;
     **CHECK: PASS** on the first full run against A's and B's Luau.
4. **Layout:** the sneak path gained its last point, C's entry (262, -44) (the gate needs it to end
   there; the draft stopped at (250, -44)).

## Left

## Decisions the contract did not take

## For the other owner
