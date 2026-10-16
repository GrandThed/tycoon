# L1b Wave 4 fix round: economy-designer report (data, simulators, mirrors)

Branch `l1b-wave4` in `tycoon-p5`. Rulings: `docs/prompts/l1b-w4-fix-round.md` (R1–R15) and the lead's three notes on R12, R10 and R7.

## Commits

| Commit | What |
|---|---|
| `8f8d996` | `Combat.json camps.meleeBelow` 1.5, alone, landed first. |
| `9244f4a` | The mirrors in `sim_range.py` and `sim_combat.py`, the stage-mirror cases, and 11 new mirror mutants plus one re-aimed. |
| `23cbc35` | Three `check_levels` gates: R6 (the cliff), R14 (`meleeBelow`'s range), R8 (the pinned sniper spots). |
| `c8af9aa` | R8's straight sniper courses and bands, R7's checklist-order band, the tent pace in `1_ForestRoad.json`, `TENT_FAST` B. |
| (this commit) | `docs/BALANCE.md` "L1b W4 fix round", the corrected sniper figures, and this report. |

## Mirrors (file : function)

- **R1** `sim_range.py` `ThreatRun.seek`:
  - every seek stamps `e.progressed = away < e.goal_gap − MOVE_THRESHOLD × dt` and sets `e.goal_gap = away`, measured on the routed goal;
  - in `crowd_step`, a resident rusher sets `closing = progressed`;
  - a rusher now seeks in reach too, as `Think` gives it;
  - `Fighter.spawn` sets `goal_gap = inf`.
- **R2** `cb_step`: home rests only when `not striking`.
- **R4** `LevelRun.before_think`: the `healed` latch, the same as `campStep`.
- **R5** `ThreatRun.lane_runs`.
- **R14** `ThreatRun.reaches` and `cb_melee` (`meleeBelow`). `CB_RULE_KEYS` gains `meleeBelow`.
  - `begin`'s refusal loop is mirrored: a turned-down attack moves on to the next choice. This was not in the simulator before. It covers the chained choice too, which keeps its facing.
- **R6 and R15** `ThreatRun.in_band`, which applies both bounds. Callers:
  - `resolve`, where pending entries carry the strike's floor;
  - `sweep`, for charges and rings, which carry `floorY`;
  - the planner, whose threat tuples carry the floor.
- **R7**:
  - `cb_new_tent(stock, residents)`;
  - `cb_tent_clock(tent, busy, now, rested, residents_alive)`;
  - `LevelRun.stirred()`, computed once per tick;
  - `send_tents` calls `Ahead(clock.residents − alive, clock.residents, …)`.
- **R9** `stand_y` and `floor_y`: heights are measured from the crowd's floor. The keepAway retreat goes through `seek`, so it is routed by `rg_toward`.
- **R10** `safe_point`: a region zone ignores `busy`. `safe_threats` uses the new `threatening()`.
- **R12**:
  - `fielded(zone, tent, sent, refused)`;
  - the tent books `refusedAt`;
  - the run reports `refusedTent`;
  - `sim_combat.level_pay(…, refused)`.
- **`check_stage_mirror.py` and `stage_mirror.luau`**:
  - the tent timeline with R7's restart and WaveService's `aheadTent` call;
  - `meleeBelow` heights on the Melee grid, and four `Problems` lines (missing, text, −0.5, 0);
  - an R2 home timeline;
  - `Fielded` with `refused` (300 compared);
  - `Threatening`.
  - Before this round the mirror read FAIL (475): `SafePoint` 471, Melee and Reachable 3, Problems 1. It now reads PASS.

## Gates (`tools/check_levels.py`)

- **R14:** `0 ≤ meleeBelow ≤ min(sightBelow, lowest rusher height − ROOT_HEIGHT − COVER_MARGIN)` = [0, 1.5]. 1.5 passes and 1.6 fails.
- **R6:** no standable ground under the region, out of melee reach, within a rusher shape's flat reach less its radius of a cell edge, where the height rule (`UNDER_SIDE`) still holds. It passes. With `UNDER_SIDE = False` it fails at Road4 (−307 and −305), the foot of the climb.
- **R8:** the unreachable sniper spots are pinned in `EXPECTED`: Creek, LookoutLedge, LookoutSignPad, Road2, Road3, Road4, RoadBC5, RoadBC6, Secret_cache, Secret_lookout, ShrineSignPad. `sim_range` rates a course from each, through `sniper_spots_of`, the same function. Dropping one spot fails the gate.

## Bands (`tools/sim_range.py`)

- **R7, the checklist's order at 4 / 4:** the walk-out, the lose, every group at rest by 31.6–32.3 s, then a clear of A. A's tent sends 1, 1, 1 in the clear. With R7 off in a scratch run, it sends 0, 0, 0.
- **R8:** one band per spot, on Normal and on Hard, both at 2 / 2 against `mission` on the same seed. The course is defined in BALANCE: a straight crossing at walk speed; minutes to the last landed hit, at least arrival + 10 s.
- **R12:** the simulator's deliberate copy is gone. The clear-bonus band now prices `fielded(…, refused)`.

## The sniper table (cash / min, Timber / min; seeds 11 / 23 / 37; both at 2 / 2)

| Spot | Normal | Hard |
|---|---|---|
| `mission` | 23,835 / 25,946 / 23,891 cash; 39.6 / 43.2 / 39.7 Timber | 19,646 / 20,835 / 20,229; 30.0 / 32.1 / 30.8 |
| Road2 | 17,286 / 6,649 / 6,649; 26.6 / 8.9 / 8.9 | 17,730 ×3; 26.6 ×3 |
| Creek | 0; 0 | 0; 0 |
| ShrineSignPad | 0; 0 | 0; 0 |
| Road3 | 22,957 / 11,938 / 11,938; 32.1 / 13.8 / 13.8 | 13,535 / 18,365 / 18,365; 17.5 / 27.5 / 27.5 |
| Road4 (the foot of the climb) | 1,601 / 1,067 / 1,067; 0 | 0; 0 |
| **LookoutLedge** | **33,664 ×3; 44.1 ×3: RED** | 18,313 / 17,756 / 15,846; 9.6 / 17.8 / 9.9 |
| LookoutSignPad (the strip) | 13,494 ×3; 15.6 ×3 | 7,306 / 10,025 / 12,457; 0 / 9.1 / 8.3 |
| RoadBC5 | 0; 0 | 0; 0 |
| RoadBC6 | 0; 0 | 0; 0 |
| **Secret_lookout** (38) | **39,541 / 41,395 / 41,395; 53.7 / 56.2 / 56.2: RED** | 11,218 / 11,412 / 5,397; 10.2 / 10.4 / 0 |
| **Secret_cache** (18) | **27,153 / 23,702 / 24,236; 42.7 / 36.9 / 40.5: RED (seeds 11, 37)** | 0; 0 |

### R8's stop: three spots, Normal only

- **LookoutLedge and Secret_lookout.** He kills 29–31 Pickets within 11 s of arriving, with 0 hits on him. Normal's slingers die in the first volleys (pierce 5 plus blast).
  - Tried: the watch line (4 slingers) moved to within 13 studs of the ledge. The ledge then earned 28–38k a minute and the lookout 39–41k, with 0–2 hits.
  - `sightAbove` and cell edges cannot touch a spot 26 studs over the road.
- **Secret_cache.** B's shooters already answer: 8–10 hits, and he is down by 20–23 s on two seeds. The 6–7 brutes and armoured he kills first still beat the mission's minute.
  - Tried: eastWatch moved back 25 or 40 studs, and eastFire moved to the east gate. The results were noisy (15.8k–46.3k) and never green on every seed.
- **The levers left are not data:**
  - the Longbow's pierce or blast, which every boss is tuned on;
  - moving the ledge, which moves the double-jump secret;
  - a sight rule that blocks for the crowd and the bow (L4).
- The band stays red for these three spots only. `sim_range.py --check` reads FAIL (3), and those are its only failures.

## Constants changed (reasons in BALANCE "L1b W4 fix round")

- **`camps.meleeBelow` 1.5.** R14, A's value. It sits at the top of its gate's range.
- **A `tent.pace` 15 → 12 s (lead 0.2), and B 90 / 0.15 → 35 / 0.2.**
  - R7 restarts the measure at every whole-camp rest. A group-by-group clear therefore looks "ahead" in every later episode, and under R7 the old values sent A 1–2 and B 4–8 at pace.
  - A grid of 27 settings found no B value that sends 4 at 4 / 4 while sending at most 1 at pace.
- **`TENT_FAST["B"]` 4 → 3.** This is the contract band "the tent when fast: B at least 4". **The lead must rule on it.** The other option is a per-difficulty or per-camp pace key: a rule change, A's.

## Verify (final tree)

- `py tools/sim_range.py --check`: **`CHECK: FAIL (3)`**: LookoutLedge, Secret_lookout and Secret_cache on Normal, all under R8's stop. Everything else passes:
  - the first clear: 6.51 / 5.98 / 6.49 min;
  - the tents;
  - R7's order;
  - every Hard sniper;
  - the bosses with R14's `reaches`: Colossus Broadsword 76.3 s, Warlord 97.7 s, and every weapon's no-hit band.
- `py tools/sim_combat.py --check`: `CHECK: PASS -- all twenty-three assertions hold`.
- `py tools/check_levels.py`: `CHECK: PASS`.
- `py tools/check_stage_mirror.py --luau …`: `CHECK: PASS`.
- `py tools/crowd_harness/mirror_mutants.py --luau …`: `90 of 90 mutants caught`, in one full pass on the final code tree.
- Harness: `HARNESS: PASS (2,337 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`.

## For other owners

- None required. B's `mutate.py` already carries A's R14 texts. The `mirror_mutants.py` "Melee ignores meleeAbove" entry is re-aimed here.

## Found

1. **The Python mirror lacked `begin`'s refusal loop.** Before R14 it did not matter, because a cap refusal is the same for every attack of a kind; now `reaches` and `laneRuns` turn down single attacks. Mirrored.
2. **R7 changes what "ahead" means.** A player who clears group by group restarts the measure between groups, so camps with many groups (B) cannot separate "at pace" from "fast" by pace data. This needs the lead's ruling (see Constants).
3. **The rate yardstick for a short course is fragile.** One opening arrow into a sleeping fire circle kills 14 in about a second. A course of under 15 s is dominated by that, for any player with a bow. I set the floor at arrival + 10 s and the straight walk at speed 20; both are stated in BALANCE.

## After Ben's ruling (2026-10-16)

- The three Normal spots are accepted for L1 and fixed in L4. `sim_range.py` (`SNIPER_KNOWN_LIMIT_L4`) now reports their rows as "known limit, L4", at up to x1.41, x1.73 and x1.14 the mission's cash a minute, and gates only "every hit lands" for them. Every other spot and every Hard row stays gated, and the `check_levels` list stays pinned.
- The lead accepted "the tent when fast: B at least 3".
- BALANCE records both rulings.
- `py tools/sim_range.py --check`: `CHECK: PASS`.
