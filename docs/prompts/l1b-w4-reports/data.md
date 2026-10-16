# L1b Wave 4 — economy-designer report (data, simulators, mirrors)

## What I built

- `src/shared/Config/Combat.json` (landed first, alone, 0546e24): `camps.chaseSight` 40,
  `camps.hitMemorySeconds` 8, `camps.meleeAbove` 7.5, `levels.regionLockMargin` 8, `levels.doorSpare` 0.5.
- `src/shared/Layouts/Levels/ForestRoad.json` (d4f3c06): one region `plateau` (y 8, camps A and B, 13 road
  cells: Road5, LookoutSignPad, RoadAB1–5, RoadBC1, CacheSpur, CacheSignPad, RoadBC2–4; east end x 198);
  `approach` on A (−322, 0, −44) and B (−108, 8, −44).
- `src/shared/Config/Levels/1_ForestRoad.json` (d4f3c06, 6b607fe): tent `pace` A 15 s / lead 0.2, B 90 s /
  lead 0.15; `targetMinutes` 7 → 6.
- `tools/sim_range.py`:
  - Region mirror `rg_build`, `rg_problems`, `rg_distance`, `rg_inside`, `rg_clamp`, `rg_runway`, `rg_toward`.
  - CampBrain mirror rewritten for Wave 4: `cb_step`, `cb_struck(group, by, now)`, `cb_melee`, `cb_reachable`,
    `cb_known`, `cb_stands_down`, `cb_forget`, `cb_goal`/`cb_shows` while stood down, `cb_new_tent`,
    `cb_tent_clock`, `cb_ahead`, `cb_tent_active(busy, alive, ahead)`, `cb_rouse`/`cb_tent_rouse(reachable)`.
  - StageFlow mirror: `plan_level` (regions shared per region, defs carry cells, zone `stock` residents
    only, `approach`, tent `pace`, refused on `Region.Problems`), `region_problems` (Validate's Wave 4
    lines), `fielded`, `LevelRun.skip` (N's approaches), `progress` without `tentLeft`.
  - `LevelRun`: region clamp/route/runway hooks (`clamp_body`, `route_goal`, `seek`, `runway`), `closing`
    stamps, stood-down rushers walk home and heal, pace tent, clear on an empty floor, fielded bonus,
    `ForgetOthers` at the close, no BLOCKED but held. A's "Beyond the contract" 1–4 are mirrored.
  - New policies `archer`, `walkout`, `lose`, `sniper` (scene code, with the simulator's one line of
    sight: fences less gates and the plateau's lip, used only by the bow scenes); the `edge` scenario,
    `tentAlone`, `IN_PLAY_STEP` and `tent_left` are gone; `FOREST_CLEAR_SECONDS` (345, 420); new bands
    (tent at pace / fast / Hard / Brutal, nobody waits, the fielded bonus, walk-out, lose, archer,
    sniper), the kite band without the tent clause.
- `tools/sim_combat.py`: `level_pay(..., sent)` pays the bonus on the fielded stock; 21 prices each run
  with its own tent bodies.
- `tools/check_levels.py`: `check_wave4` (region data, standable cells on a 2-stud grid, doors and tree,
  fences crossed only at gates, lock clearance, `meleeAbove` range, sniper perches, approaches, tent pace);
  the perch-round-the-floor gate skips region camps; `check_rules` pins regionLockMargin 8 and doorSpare
  0.5; gate 16 prints the cell and door table, the tightest lock clearance, the perches and N's stops.
- `tools/check_stage_mirror.py` + `tools/crowd_harness/stage_mirror.luau`: Region bundled before CampBrain;
  comparisons for Region (Build, Problems, Distance, Inside, Clamp, Runway, Toward on the plateau and 10
  grids), Melee, Reachable, Struck, StandsDown, Forget, Goal/Shows stood down, the pace tent timeline, a
  region Step timeline, Plan's regions/approach/pace, Fielded, 20 new Validate refusals, N through both
  approaches (`approach`, `approachPast`); the tentLeft runs are gone.
- `tools/crowd_harness/mirror_mutants.py`: Region path; 31 new mutants (one is B's "the clear waits for the tent again", replacing Wave 2's tent-stock mutant), 8 re-aimed, none deleted. N's two mutants follow B's amended L1b-W4-31 (99d2dd6), mirrored in `LevelRun.skip`.
- `docs/BALANCE.md` "L1b Wave 4".

## Verify

- `py tools/sim_range.py --check`: `CHECK: PASS` (7 min 16 s).
- `py tools/sim_combat.py --check`: `CHECK: PASS -- all twenty-three assertions hold`.
- `py tools/check_levels.py`: `CHECK: PASS`.
- `py tools/check_stage_mirror.py --luau C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`: `CHECK: PASS`.
- `py tools/crowd_harness/mirror_mutants.py`: 79 of 79 caught (a full run of 78, then the three changed ones alone after B's 99d2dd6 and the tent replacement).
- Harness (not mine, run as a smoke test): `HARNESS: PASS (2,248 checks)`.

## Numbers

- Normal first clear at 2 / 2: 6.37 / 6.42 / 5.99 min (mean 6.26, inside the stop rule 360–405 s).
- Tents: 2 / 2 sends 0 everywhere; 4 / 4 sends A 2, B 7–8; Hard and Brutal 0.
- Lose: the group turns at 108–109 studs past A's edge (U-bend), home healed 12.1 s later.
- Walk-out: 2.40–2.70 s. Sniper: 16.2–17.6k cash/min, 22–24 Timber/min against the mission's 24.1–25.9k
  and 40–43. Bonus 7.1% of a Normal clear.

## For other owners

- None required. (B's `WaveService` counts a refused tent spawn as sent; my mirror does the same, so the
  fielded bonus agrees.)

## Found in the contract

1. **The sniper-perch gate, read literally, fails on the boss room's own fence tops and a cover block**
   (57–86 studs off the region, in the band, over `meleeAbove`, beyond every slinger). I excluded a
  locking camp's floor/fence/cover from the gate and list them; they are "Open for later: shooting out of
   the boss room". Lead's ruling.
2. **The archer's "groups leave A's floor" and the sniper's "rushers stand down" cannot be met on Normal**:
   the Longbow (pierce 5) kills A's fodder in the gate's funnel or before they can stand down. I gate
   "every hit lands" and the sniper's pay, and report the rest. The ledge sniper clears the Pickets in
   about 25 s at ~70% of the mission's cash a minute.
3. **RoadBC5/BC6 lie outside the region** (the lock clearance stops it at x 198): a ground-level spot no
   raider of B can reach and no slinger can answer. Not covered by any gate (the perch gate is for tops
   over `meleeAbove`).
4. **The lose band's top (110) is tight** (108–109): the turn always comes at the U-bend, because flat
   all-round sight crosses the 22-stud void between RoadAB2 and RoadAB4. `chaseSight` under 38 makes the
   walk-out fail instead.
5. The draft's tent pace (A 25 s, B 130 s) would send 3 bodies from A at 2 / 2; tuned to A 15 / 0.2,
   B 90 / 0.15.
