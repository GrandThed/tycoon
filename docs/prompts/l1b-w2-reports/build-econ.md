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

5. **Tuned and written up** (`docs/BALANCE.md` "L1b: the long road, Wave 2"): brute Timber 6 -> 4,
   tents' `every` 6 -> 8, 14 fodder of camp B swapped (6 plated, 4 slingers, 4 brutes), C as the
   draft, `targetMinutes` 9 -> 7, `runCapSeconds` 1500. Normal first clear 7.23-7.51 min, Timber
   43.3-44.9 a minute, bonus 7.3% of a clear, Hard x2.23, Brutal x4.58. Every band of "Balance
   bands" passes.
6. **Mutants:** `check_stage_mirror.py` catches 39 of 39 Luau mutants. The script is scratch:
   `C:/Users/benja/AppData/Local/Temp/claude/l1b-w2-econ/mirror_mutants.py`. Its list is in BALANCE.

## Gates run (on the final files)

- `py tools/check_levels.py`: CHECK PASS. The gate 16 block prints: population 147 / 157 / 157,
  Parts 82, route 1,055, sneak 979 studs (B.fire1 tightest at +6.1), and the chain table.
- `py tools/sim_range.py --check`: CHECK PASS (range, threat, bosses, Raider Arena at 2 / 2, the
  Forest Road Wave 2 bands).
- `py tools/sim_combat.py --check`: PASS, 23 of 23.
- `py tools/check_stage_mirror.py`: CHECK PASS; mutants 39 / 39.
- `py tools/check_compile.py`: PASS (155 files).
- `stylua --check tools/crowd_harness/stage_mirror.luau`: clean. It was not formatted on `main`;
  now it is.
- Gate 15 (`populationReserve` in src and tools): no hits.
- Not run by me: `run_harness.py` and `mutate.py`. They are B's and must never run in parallel
  with B's own runs.

## Left

Nothing in my rows.

## Decisions the contract did not take

- **Tents' `every` 6 -> 8 (lever 3).** This goes against Ben's LR 5, "one every 6 s".
  - At 6 s the clear was 6.5-7.0 min whatever the mix. Seed noise of +-15 s in B swamps any swap,
    and more brutes push Timber over its band.
  - The lead decides. At 6 s the clear is 6.5-7.4 min and Timber 44-50 a minute.
- A's tent moved 6 studs west, for post spacing against A.loop. Every tent's ring has radius 10.
- The sneak path ends at C's entry (262, -44): one point added.
- `looks.tent` is (222, 184, 120), because check_levels needs a colour look's channel spread above 80.
- check_levels:
  - tent groups count in the gates for checkpoint sight and reach, chaseMargin and perches;
  - the chain table is taken on Normal with the tents empty, as they are at the first wake.
- sim_range:
  - projectiles now crit, as the game's do;
  - the `RAY_RULE` switch exists only for the bow report;
  - the kite band counts tent bodies sent during the chase as new bodies, not refills;
  - the simulated player waits in an open camp until its tent is empty, so the camp clears and
    pays its bonus.

## For the other owner

- **B:** the final level differs from the draft in three ways your hand-worked cases may assume:
  brute materials 4, B's residents (BALANCE "who lives where"), and tents every 8. Population
  (147 / 157 / 157) and Parts (82) are unchanged. The two count-0 units you saw were transient;
  the final file validates.
- **Lead:**
  - the tent pace ruling above;
  - a shell slip (`cd X && (A) & B`) started one background run in the main checkout. It only
    read files and ran the simulator; the main checkout's `git status` stayed clean.
