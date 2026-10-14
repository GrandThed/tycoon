# L1b Wave 1 — economy-designer (continuation), report

Written section by section as the work goes (a cut-off loses nothing).

## State found (2026-10-14)

- From `55dcca0`: `Combat.json` (`camps`, the four `levels` keys), `Expeditions.json` (`looks.fire`),
  `1_ForestRoad.json` (one travel stage, camp C the only camp stage, residents for A, B, C),
  `ForestRoad.json` (C `locks`, spots, A/B checkpoints moved onto the road), `sim_combat.py`
  (`kill_reward`, `split_carry`) and most of `sim_range.py` (the CampBrain mirror, `LevelRun` with
  floors, groups, per-kill credit and the carry, the `still`, `kite`, `edge` policies, the
  first-strike scenario, the Wave 1 bands in `check_forest`). The routed executor details (stop at
  half `homeTolerance`, the release step, the step clock, heal before `Step`, `Busy`/`Engaged` with
  a living member) are in `LevelRun.before_think`.
- Not started: `check_levels.py`, `check_stage_mirror.py`, `stage_mirror.luau`, sim_combat
  assertions 19–23, BALANCE "L1b".
- First runs: `check_levels.py` 4 FAIL (new `levels` keys unknown to it, the one-camp-stage rule,
  A/B checkpoints "not on the floor"); `sim_combat.py --check` crashed on `bankEachWave`;
  `sim_range.py --check` 4 FAIL (three Normal clears at about 3 min against 5–8, and the still
  player never woke anyone).

## check_levels.py (done)

- `part_count(layout, fire_marker)`: gates and the four barrier boxes only for a camp that
  `locks`; one Part per fire spot when `levels.fireMarkerSize` is given. Forest Road: 67 Parts =
  73 − 6 × 2 open camps + 6 fire markers (a gate of its own). This settles the harness's one red
  check from the cut-off: B's `LevelGeometry` was right against the contract, `check_levels.py`
  still counted L1's 73.
- The stage rule is now "the camp stages name exactly the camps that lock" (Forest Road: C).
  Spawns, a checkpoint on the floor, "nothing beside it" and the wall band are a locking camp's
  gates only.
- New `check_residents`: residents per camp at the highest difficulty (A 12–18, B 30–40, C ≥ 4 and
  under its `maxAlive`, every camp ≤ area / 200); a fire and a guard group in every open camp and a
  patrol in the level, on every difficulty; posts (widest radius + 1 inside the floor and off cover),
  patrol legs, fire spacing (2 radii + 0.5) and its circle, guard points per member, at every
  difficulty; open camps' checkpoints off the floor, on a ground block within 1 stud of the floor's
  height, and seen by no resting member (`cb_sees`, cone included, a patrol anywhere on its loop);
  `chaseMargin` ≤ the smallest reach − radius of the open camps' rushers (fodder 3.2); keepAway bands
  and cover in the open camps; L1b-11 at every difficulty. `sr.level_problems` is called with the
  kinds, so Validate's L1b lines are gated too.
- `check_rules`: the four new `levels` keys (`walletSendSeconds` exactly 1, `populationReserve` ≥ 21)
  and `CampBrain.Problems` on `Combat.json camps`; looks are twelve, `fire` is a colour.
- Proved not vacuous: a scratch probe mutated the data 23 ways (checkpoint on the floor, over the
  void, seen by a wider fire sight or a 360° guard cone, `chaseMargin` 4, 20 residents in A, fire
  radius 2, a patrol leg over cover, a post at the edge, a guard spot a point short, C not locking,
  A locking, no patrol, no guard group, reserve 20, wallet 2, no fire look, a grey fire look,
  `crowd.maxAlive` 100, 30 residents in C, cover 5 tall, a gate missing): 22 caught; the one miss
  was my mutation (it left B at 30, inside the band).
- Result: `py tools/check_levels.py` → **CHECK: PASS**. Populations: Normal 93 (A 14, B 28, C 7),
  Hard and Brutal 103 (A 18, B 34, C 8); `crowd.maxAlive` 160.

## sim_combat.py (done)

- 19: no `bankEachWave` (no stage banks); the arena adapter has no residents.
- 21 amended: Valor exact on every difficulty; `targetMinutes` honest; every cleared run paid,
  kill by kill, exactly what the file pays for its kills (`level_pay` now counts the residents by
  `minDifficulty`, never `countMult`); the stall rule. Normal's pay against L1 (now 88,200 / 155 /
  10) and Hard's and Brutal's multiples are reported, not gated.
- 22 new: `split_carry` over 400 seeded runs of 60 kills (1–4 members, cash × 1–2) never pays over
  the exact shares, never a unit under, every carry in [0, 1); plus the contract's hand cases.
- 23 new: each difficulty's population worked by hand from the files equals `plan_level`'s and is
  ≤ 160.
- `targetMinutes` 7 → **3** (the measured mean Normal clear is 3.1 min; the contract says set it to
  the measured clear). `runCapSeconds` stays 1050.
- Result: **CHECK: PASS — all twenty-three assertions hold** (18 s).

## check_stage_mirror.py and stage_mirror.luau (done)

- `CampBrain` is bundled (load order Economy, Armory, Combat, LevelGeometry, CampBrain, StageFlow);
  the shim's Vector3 gains `Dot`.
- Compared now, besides L1's: `Validate` with `crowdMax` (shipped files playable) and 27 new L1b
  refusals (residents, spots, `locks`, the boss room's residents at its cap, the population, the
  `clearBonus`, the three new `levels` numbers), each broken once in a copy of the level, its raw
  layout or `levels`; `Plan` with zones (floor, `locks`, name, checkpoint, residents, rectangles,
  points), groups and population (stages name their zone by id; `bankEachWave` gone); `FieldClear`
  before every tick and `SafePoint` after it with four `busy` cases; `reached` / `done` in the
  state and `zone` in the actions. The scripts walk each open camp's checkpoint (past reach, over
  and under the band, a downed root, on the edge) and kill its residents, with the boss room's floor
  at 0 throughout; variants `roadDown` (a down while a group is awake ends the run) and `standing`
  (open camps left alive) are new.
- CampBrain against the cb_* mirror: `Posts` (every shipped group at every difficulty, grid
  patrols, fires of 1–7, guards), `Sees` (rings at the sight, cone and band edges), `InPlay`
  (grown-rectangle and shooter-reach edges), `AtPost`, `Goal` (1,710 cases), `Struck`, `Shows`,
  `Problems` (line count), and three scripted `Step` timelines. `KillReward` on the reward grid and
  `SplitCarry` over four seeded sequences of 160 kills (payments and every carry after each call).
- Result: **CHECK: PASS** (1.7 s; Luau = the main checkout's `tools/bin/luau.exe`, found on its own).
- Proved: 25 hand-made Luau mutants of CampBrain, StageFlow and Combat (the cone, the band, the
  margin, the shooters, the rise, the leash while striking, the patrol wrap, home's leg, a hit from
  out of play, arc spacing, the fire's first seat, Shows, Release, campClear for the locking zone or
  twice, reach's band and a downed root, SafePoint's busy and reached, FieldClear on the road and in
  the camp, SplitCarry's carry, multiplier and rounding, KillReward's rounding), plus three on
  Plan (minDifficulty, the reserve, the room): **28 / 28 caught**.

## sim_range.py (done, one band red)

- Checked the routed executor details against `LevelRun.before_think`: the stop at half
  `homeTolerance`, the release step (stepped held, then released, no transition), the step clock,
  the heal before `Step`, `Busy` / `Engaged` / `Awake` only for groups with a living member. All
  in, as the previous agent wrote them; nothing changed there.
- Fixed: the `still` policy switched to "clear" at the camp's in-play edge and then stood there
  unseen, so nobody ever woke ("woke at -"). It now walks on across each open camp, entry to
  exit, until a group wakes (`LevelRun.crossing`). Result: woken by A's fire1 at 11.7-11.8 s,
  down 9.7-9.8 s later (band 6-12).
- `py tools/sim_range.py --levels-only --check`: every band passes except **the Normal first
  clear, 2.98-3.18 min against 5-8 min** (three FAIL lines). The arena's L1 bands all pass.

## docs/BALANCE.md "L1b" (done)

Values (and why), who lives where, residents and population per difficulty, the Part count, the
results table, the four scenarios, what a clear pays against L1, the bands, the Raider Arena's
note, flags. Appended after "L1: flags for the owner".

## Numbers against the bands

| Band | Now |
|---|---|
| Normal first clear 5-8 min | **2.98-3.18 min: FAIL** (contract issue 1) |
| The Colossus 64-90 s | alone 75.0-77.6 s; in the run 73.7-75.6 s |
| No hit over 25% (Normal) | 24.8% (the Colossus's lane) |
| Still in camp A, down 6-12 s from the wake | 9.7-9.8 s |
| First strike, every fire group, every seed | 15 / 15 |
| Leash (`kite`) | 3 / 3 whole, the dead dead, paid only for kills |
| Edge (`edge`) | 0 paid, 152 hits blocked |
| Every kill paid once, at once; Valor 10 | exact in every run |
| Normal pay (reported) | 60,800 cash, 129 Timber, 10 Valor (L1: 88,200 / 155 / 10) |
| Hard / Brutal `rewardMult` 2 / 4 (exact) | Valor 20 / 40; pay x2.43 / x5.11 cash (reported) |
| Population | Normal 93, Hard 103, Brutal 103 (<= 160); residents A 14/18/18, B 28/34/34, C 7/8/8 |
| Parts | 67 (= 73 - 12 + 6 fires) |

## Contract issues

1. **The 5-8 min first clear is out of reach at Wave 1's size** without breaking "the waves and
   the Colossus follow as in L1". The arithmetic and the measured alternative (three of L1's B
   waves added to C: 4.96-5.35 min, C then four minutes long) are in BALANCE "L1b: flags".
   Recommended: report the band in Wave 1 (it returns at Wave 2's size); one line in
   `sim_range.py` once the lead rules. Until then `sim_range.py --check` is red on exactly those
   three lines.
2. `StageFlow.Plan` takes `ranks` as an optional sixth argument (the contract's signature has
   five); without it no `minDifficulty` resident is fielded. B's choice, mirrored exactly by
   `sim_range.plan_level(..., ranks)`; the mirror passes `data.ranks`. Worth a line in the
   contract.
3. `targetMinutes` is now 3 (the measured clear, as the contract says). If the lead takes option
   (b), it becomes 5.

## For the other owner

- **Lead:** the ruling on contract issue 1.
- **luau-engineer B (harness):** the Forest Road Part-count case should now pass:
  `check_levels.part_count(layout)` returns 67 (it reads `levels.fireMarkerSize` from Combat.json
  when no size is passed). I did not run `run_harness.py` / `mutate.py` (B owns them and they must
  not run in parallel). B's `StageFlow`, `Combat` and A's `CampBrain` agree with every mirror as
  the working tree stood when this was written (`check_stage_mirror.py` PASS).
- Nothing for the ui-engineer.
