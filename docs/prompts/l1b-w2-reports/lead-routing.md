# L1b Wave 2 "the long road" — lead routing

Branch `l1b-wave2` in the worktree `C:\Users\benja\Desktop\tycoon-p5`, made from `main` at 1fc4612
(2026-10-14). Rulings are written here the moment they are taken; agents read this file first.

## Ben's rulings this session

1. **Start (2026-10-14):** "Headshot + layout": two fresh agents in parallel, nothing built, then
   the layout picture and the tent questions before any contract.
2. **Camp clear bonus: a small bonus**, about 10% of what that camp's raiders paid, on top of the
   per-kill pay. A config number. To be fixed in the contract: what "paid" means (the camp's
   stock at full price for the difficulty, not what this party happened to kill, so sneaking
   past nobody is not cheaper), and when it pays (the moment the camp's last body falls, kept
   at once like a kill).
3. **Merge rule (assumed, said once to Ben):** as Wave 1, each step that passes review and QA is
   merged to `main` and the six place files rebuilt.
4. **Layout: the winding road** (`docs/prompts/l1b-w2-layout/winding.level.json` and
   `winding.layout.json`, report `layout.md`): about 1,055 studs west to east, the road along the
   north side of A and B, the sneak path inside the north fence. Asked with the ASCII maps and the
   page `long-road.html` (local, not published).
5. **Tents: 8 bodies, one every 6 s, then they run out**, joining their own camp's fight. Not
   destroyable. (A: 4 fodder, 2 slingers, 2 brutes; B: 2 fodder, 2 slingers, 4 brutes; C's tent is
   where its stage waves come out, no extra stock.)

## Lead rulings

1. **Headshot (report `headshot.md`, 2026-10-14):** the cause is the hit rule, not the drawing: a
   ray must first touch the body sphere (top at `height/2 + radius`), so on tall kinds the upper
   head is a total miss (Colossus 63% of head aims miss). Wave 2 adopts the report's fix as a pure
   rule `HitShapes.CrowdRay` (body OR head, padded; crit on the unpadded head), called from
   `WeaponService.rayCandidates`, mirrored in `sim_range.py`, with the report's harness cases and
   three mutations. **The body also becomes a vertical capsule** (ground to the head's base), so
   the Colossus's legs are hittable: the same complaint ("what I see does not get hit"). INTERFACES
   P1 decision 1 is amended in the Wave 2 contract. Boss times will drop with bows and rifles;
   the economy-designer re-reads them with no weapon-number change, and the Colossus / Warlord
   bands are re-checked at 2 / 2. Phone auto-fire then agrees with the server on heads.
   Carried as Minor for ui-engineer: a crit on a plate shows in the plate colour (make it crit
   yellow). Not in Wave 2: rewinding enemies for shots; the lean of the drawn head in a windup.
2. **The layout report's 19 assumptions (`layout.md` "Assumptions the lead must confirm"):**
   all confirmed as written, with these readings:
   - (1) The join rule chains: a group woken by a neighbour wakes, in turn, its own resting
     neighbours within 2 × its own sight. Judged once per wake, from resting places, in a pure
     `CampBrain` function with harness cases and a mutation.
   - (4) Population rule: residents + Σ tent stock + the boss room's room + 13 ≤ 160, replacing
     the flat reserve of 21. `Validate` enforces it per difficulty.
   - (5) Clear bonus as ruling 2: `crowd.clearBonus.share` 0.1 of the camp's whole stock at the
     difficulty's price (residents, its tent's stock, C's waves, not the boss), paid and kept the
     moment the camp clears.
   - (6) A tent sends only while a group of its camp is awake, and pauses (stock kept) while the
     camp rests. **Once every resident of the camp is dead, the tent empties its remaining stock
     at its pace whatever the camp's state,** so a camp can always be cleared. A camp clears when
     its residents and every tent body are dead and the stock is spent.
   - (10) The 38 brutes stay as the draft. The economy-designer re-measures after the headshot rule
     (brutes now take head crits) and may swap brutes for fodder to hit the band. Timber per
     minute must land within ±10% of Wave 1's 42: `rewards.brute.materials` 6 → 4 is the
     designer's lever.
   - (14) Band: simulator first Normal clear 7–8 min at 2 / 2 (Ben about 9–10.5); Hard and Brutal
     gated again by the human-reaction player as L1; pay bands back.
   - (16) Post spacing becomes a real `check_levels` gate (every difficulty).

## Agents

| Task | Brief | Report |
|---|---|---|
| Headshot on big bodies (read-only) | `docs/prompts/l1b-w2-headshot.md` | `docs/prompts/l1b-w2-reports/headshot.md` |
| Long-road layout plan + arithmetic | `docs/prompts/l1b-w2-layout.md` | `docs/prompts/l1b-w2-reports/layout.md` |

## Build routing

- **ui done (build-ui.md).** Its three own decisions are confirmed: seed only calm poses (idle,
  move, rest, rise), landing from `StateChanged` → `Landed` only, perf text with one tenths digit.
- ui → A (relayed): `info.at` is feet in world coordinates in the snapshot's frame; `yaw` in
  radians; the perf attribute in milliseconds; a resting tent group arrives as `idle`.
- ui → B: **taken** (pure rules are tested): B adds the `SpawnSeed` harness cases and two
  mutations from build-ui.md, with the `typeof` stub for the Vector3 shim.
- QA runs `proving_project.py` (it writes a shared file at the root): never an owner.
- **A done (build-A.md), harness 1,897 PASS.** Its own decisions confirmed. Ruling on the one
  difference from the client section: **range bodies also carry `at`** (refreshed at every send,
  per the Remotes table); accepted, since the client seeds only calm poses. The reviewers check the
  range (`fight`, `colossus`, `warlord` sets) looks as before.
- A → B (relayed): `mutate.py` gains `SWING` in `FILES`, `L1B_W2_CROWD_MUTATIONS`, three stale
  Wave 1 mutations replaced, "in play has square corners" retired; B's own stale StageFlow
  mutations fixed. The "[Perf] attribute set with no name" mutation: keep it if `mutate.py` counts
  a stopped bundle as caught, else drop it.
- A → econ (relayed): `stage_mirror.luau`'s `Brain.Problems` count expects the new lines; the
  `RayUpright` / `CrowdRay` rules and the tent yaw are in build-A.md for `sim_range`.
- **B done (build-B.md):** harness 1,896 PASS, `mutate.py` 572 run / 0 not caught (on a snapshot
  without econ's two count-0 units, which Validate rightly refused). Its open decisions confirmed.
- B → econ (relayed): `check_levels.py` 1814 / 1816 still name `populationReserve` (gate 15);
  `stage_mirror.luau` passes `kinds` as Plan's 7th argument; Luau `math.round` rounds .5 away from
  zero (not Python's `round`); `sim_combat.py` may mirror `Combat.WaveStock`.
- **Flaky timing case** "a giant standing far away costs the packed crowd nothing" (A's) fails at
  random under load and can turn the mutate baseline red. Goes to the fix round for A: make it
  deterministic (count work, not time) or widen its margin with a stated reason.
- **econ done (build-econ.md):** every gate in its rows green. **Ruling on the tent pace:** the
  designer moved `every` 6 → 8 to reach the 7–8 min band, against Ben's ruling 5. **Ben's 6 s
  stands** (the band was the lead's, his was "about 10 minutes"; at 8 the player waits ~32 s for
  the last tent bodies in A). The Normal clear band becomes **6.5–8 min** for the simulator's
  reacting player (Ben about 9–10.5 at his ×1.36). Timber per minute must still land in
  37.8–46.2: the designer re-tunes with the mix or brute / tent-body Timber, never the pace.
  Brute Timber 6 → 4, camp B's mix and `targetMinutes` 7 are confirmed.
- **econ re-tune at 6 s (build-econ.md):** Normal clear 7.02–7.25 min (band 6.5–8), Timber
  38.9–40.2 a minute, bonus 7.3% of a clear; brute Timber 3 on Forest Road, camp A's watch 2 fodder
  → 2 slingers. Confirmed. Population 147 / 157 / 157 and Parts 82 unchanged.

## Fix-round routing

- **ui fix done (fix-ui.md):** ui-1 on A's `SwingGate.Observe` / `Judge` / `Took`; ui-2 as the
  pure `CampAim.Takes`. Its decisions confirmed (sampling starts at the first Judge, the skip list
  rebuilt every 0.25 s, a resting body refused even while engaged).
- ui → A (routed, part of ui-2's ruling): `resting` on `CrowdSpawnInfo`, set in `refreshInfo`,
  re-announced on rest changes through a queue of its own (not `pendingSpawnSet`), with five cases
  and three mutations. ui → B: `CampAim` in `SOURCES`, 12 cases, `CAMP_AIM` with 6 mutations.
- **A fix done (fix-A.md), harness 1,969 PASS.** Confirmed, including the addition beyond the
  review: `OnAttack` judges with `Tuning.CommitLag` so a swing sent just after a bounce is not
  refused while the server's copy is still falling (lenient on the server only; a cheater gains at
  most one swing at the very end of a fall). Dormant bodies count as resting. Its two dropped
  mutations (equivalent to the code) are accepted, the guard case kept. `TURN_WINDOW_SECONDS` stays
  a module constant (not a tunable for Ben).
- **Contract amendments to write at the merge (lead):** the new `SwingGate` exports (`Observe`,
  `Judge`, `ProbePoint`, `Higher`, `TURN_WINDOW_SECONDS`, `STILL_SPEED`, `FOOTPRINT`,
  `PROBE_POINTS`; `Landed` a full reset), `CrowdService.SeparationCells`, `CrowdSpawnInfo.resting`
  with re-announces on rest changes, `CampAim.Takes`, tent bodies rising (B-4).
- **econ fix done (fix-econ.md):** E-1 to E-3, plus the mirror of B-2 / B-4 (doors, rings at every
  difficulty) taken unrouted in its own files: confirmed. `py tools/crowd_harness/mirror_mutants.py`
  (42 of 42) joins gate 10; never beside `mutate.py`.
