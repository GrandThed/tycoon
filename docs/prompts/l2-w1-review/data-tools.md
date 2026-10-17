# L2 W1 review: data-tools slice (2026-10-17)

Diff `main..l2-secrets` at 6feb088 (e39215b plus the brief). I read the whole diff of every slice file:
Expeditions.json, Combat.json, Levels/1_ForestRoad.json, check_levels.py, check_levels_mutants.py,
sim_range.py, BALANCE.md "L2 W1", tests_l2.luau, tests_l1c.luau, mutate.py, run_harness.py and
check_stage_mirror.py. I also read the unchanged ForestRoad.json layout in full, SecretFlow.luau,
Unlocks.luau, WallClip.luau, WeaponService.GroundPoint, MovementController's jump, dash, Leap, Lunge,
AirHang and ApplyKnock, BarrierGroups, and the contract with its §10/§11 rulings and the designer's and
leap-fix reports.

Gates, all run on a `git archive HEAD` copy in the scratchpad:
- `check_levels.py`: PASS.
- `check_stage_mirror.py`: PASS. The L2 refusals compare 13 cases.
- Harness: `HARNESS: PASS (2,586 checks)`.
- `py -3.12 sim_range.py --check --levels-only --level forest`: PASS.
- `check_levels_mutants.py`: `MUTANTS: PASS`.
- `mutate.py "l2"`: 53 run, 0 not caught.

**Verdict: 0 Critical, 0 Major, 4 Minor.**

## What holds (redone by hand from ForestRoad.json, not taken from the reports)

### Geometry near the lookout

- **LookoutLedge:** x −295..−271, z −66..−52, top 34.
- **The chest:** x −286..−280, z −62..−56, y 34..38, collidable.
- **Road5:** x −302..−264, z −52..−36, top 8. Road5 runs along the ledge's whole front face.
- **LookoutSignPad:** x −306..−296, z −62..−52, top 8. There is a 1-stud gap to the ledge's west face.
- **Camp A:** floor top 8, x −264..−179, z −58.5..26.5.
  - Its fence is 1 thick and its top is at 12, on the floor's outside edge.
  - The north-west fence corner (x −265..−264, z −59.5..−52) is 6–7 studs from the ledge's east face.
  - Camp A does not lock, so it has no gate Parts and no barrier.
- Everything else near the ledge is lower:
  - Road4 has its top at 0.
  - Camp A's cover tops are at 11.5, 65 or more studs away.
  - The tent and the gatehouse walls are far away.
  - The sign is `collide = false` (`LevelGeometry` 836).

### A solo player without Double Jump does not reach the ledge

**Jump, step up and dash.**
- The highest standable top within reach is the camp A fence at 12. From it: 34 − 12 − 3 = 19 > 18.
- That is 1 stud short, the same closest call `check_levels` prints.
- From Road5 or the sign pad: 34 − 8 − 3 = 23.
- An air dash drives the plane at Y 0 (`setMover(..., not isAirborne)`). It cannot add height.
- AirHang only holds the body in place.
- Impale Dash (`Lunge`) holds altitude in the air.

**The refused air jump.** `onJumpRequest` refuses the press before `airJumpUsed` is set. No other path changes
the vertical velocity upward except `ApplyKnock` and `Leap`.

**Enemy launches** (the client slice asked this slice to rule on them). Closed:
- Every launching shape is a ground shape with a height band of 6 or less over the floor it lands on:
  armoured arc 6, lob 4, brute lane 5. "A jump dodges ground shapes", so a body at a jump's apex (18 over its
  floor) cannot be hit by any of them.
- A launch near the floor sets `velocity.Y = max(v, jumpSpeed(3))`. That adds nothing to a rising jump, and a
  launched body is in Freefall, where a non-owner cannot jump.
- Two stacked launches are also impossible. `player.knockIframes` 0.4 (`VitalsService` 325-331) voids a
  second hit for longer than the 0.175 s a 3-stud launch takes to peak. After 0.4 s the body has fallen about
  5 studs.
- The best case is 18 + 3 = 21 from Road5, which with a step up gives 24 < 26.

**Every lifting ability, with the code's formula.**
- Only Leap Smash lifts its caster. Earthquake, Shockwave, Cluster Shell and Fast Chop launch enemies, not
  the caster.
- No family with a lift can enter a level in W1 (`loadout` is Broadsword and Longbow).
- I checked the worst case anyway against `WallClip.CasterFloor` / `LeapApex` and `GroundPoint`:
  - A non-owner's legal target floor is at most the caster's floor + 18.
  - The apex is at most `max(root, target + 3 + 10, casterFloor + 3 + 10)`.
  - Near the ledge, no top lies between 21 and 26 over Road5, so a leap from Road5 peaks at feet 26 (its own
    jump).
  - From the fence top it peaks at feet 30. Both stay under the 31 a step up needs.
- `check_levels`' arc samples are the same constant-gravity parabola that `motionAt` flies. The `share`
  term is √up / (√up + √down), so the samples are exact.
- One difference is conservative. `GroundPoint` can return a lower floor than check_levels' "highest top
  under the target": a pulled-back point inside the ledge block probes from inside it, misses it and falls to
  the caster's floor. Under F1 a lower floor only lowers the apex.

**Voids.** F2 makes the caster's floor over a void the feet minus 18. For every take-off a non-owner can
reach, that is the top he jumped from. `GROUND_PROBE_DEPTH` is 250, so a short probe never mistakes ground
for a void.

### With Double Jump

- From Road5 against the face, the double jump pressed near the first jump's top gives feet 8 + 30 = 38.
- The step up needs 31, so any second press at 11 or more over the road works. That is a 0.54 s window,
  0.16–0.70 s after take-off.
- Standing on the ledge puts the root 3 over the chest's foot; standing on the chest puts it 7 over. Both are
  inside [−1, 9] and within 5 on the flat (a root against the chest's face is 4 from the centre, and one at a
  corner is about 4.95).

### The trigger is met only on the ledge (for a standing root)

- My own scan of every standable top at 0.5-stud spacing finds roots in the lookout's trigger only on
  LookoutLedge and Secret_lookout.
- The 5-stud circle lies wholly inside the ledge's footprint (z −64..−54, x −288..−278).
- A root on Road5 is 7 or more from the centre on the flat, and at most 29 high, against the band's floor
  of 33.

### Rewards

The cache and the shrine cannot pay anything in W1. Three independent barriers each prevent it:
1. They have no reward entry, so `Decide` returns "nothing" even with a key.
2. `HasKey` fails closed for `fire` and `ice`, even when a profile claims them. `tests_l2` realTests 498
   covers this.
3. `check_levels` (e) goes red on any reward behind an unsold key. The cache and shrine mutants are red.

### The check_levels rules

- (a), (b), (d) and (e) each have a red mutant and, where it matters, a green control a step inside the line.
- (c) is red under the "today" model (937 routes, as reported) and green under "floor". Its height mutants
  (18 green, 20 and 24 red) bracket the fence margin exactly: 12 + 20 = 32 ≥ 31.
- I broke `secretProblems` on both sides at once (StageFlow and `sim_range.secret_problems`).
  `check_stage_mirror` then went `FAIL (13)`: all 13 L2 refusals turned into "accepted on both sides".
  So no case is refused by some other rule (the L1c m2 trap does not apply here).

### The one-jump sim numbers follow

- **First run.** I re-ran the human and the reacting player on Normal at 2 / 2 on the 3.12 gate interpreter,
  seeds 11 / 23 / 37:
  - human: 4.23 / 4.25 / 4.31 min, 0 downs, taking 9 / 9 / 10 jumps;
  - reacting player: 5.26 / 4.69 / 5.04 min.
  - These are BALANCE.md's numbers to the hundredth.
- **Pay.** 211 Timber and 10 Valor per clear. The chest's 50 Timber is 24%.
- **Forest gate.** The forest `--check` passes, including the first-run band, "one clear buys Double Jump"
  and the chest share.
- **No double jump in the sim.** The simulator never modelled a double jump. Its dodges use `jumpHeight`
  alone, so "no number moved" is true by construction. (Minor 3 is about the gate meant to prove it.)

## Minor

### 1. The lookout is reachable without Double Jump in a party, by standing on a partner's head

- **Where:**
  - `BarrierGroups.luau:61-65`: players collide with players, a copy of Default/Default, which is true.
  - `tools/check_levels.py:902-920`: (b) models one body.
  - `tools/sim_range.py:6757, 9379, 9768`: the "owners of doubleJump only" labels.
- **What:** characters are solid to each other in the dungeon place, so B can stand on A's head.
  - A stands on Road5 against the ledge face. B's feet are then at about 8 + 5 to 6 = 13 to 14.
  - (b)'s own rule, 34 − 13 − 3 = 18 ≤ 18, already lets B up.
  - If A jumps while carrying B and B jumps at A's apex, B's feet reach about 31 + 18 = 49.
  - On A's fence corner (top 12) it is easier still.
- **Scenario:** a duo in which only one player owns Double Jump. The other stands on the ledge, gets "Needs
  DOUBLE JUMP", and snipes camp A from the known-limit perch (×1.34 / ×1.59 the mission's cash a minute on
  Normal).
  - No reward leaks: `OpenSecret` reads the key from the profile (L2-23).
  - What breaks is the design claim "out of reach by every means" and the "owners only" label on two sniper
    rows.
- **Other routes outside every model, for the same Studio look:**
  - The solo margin against the fence is 1 stud on a modelled `STEP_UP` of 3. A tall Rthro body (HipHeight
    over 3) eats into it.
  - The engine's camera-flick wall hop against the 26-stud face is outside every model, and the
    over-the-shoulder camera turns the body.
- **Fix (lead's call):**
  - Either make `ArenaPlayers` not collide with itself in the dungeon place. One line in
    `BarrierGroups.Ensure`. It also ends co-op body-blocking in camps and gates.
  - Or accept stacking as a known limit and say so in `check_secret_reach`'s docstring and the sniper label
    ("owners, or a stacked party").
  - Either way, add a PLAYTEST step: without Double Jump, try the fence corner and a wall hop at the ledge
    face.

### 2. No rule checks the trigger of a secret whose key is not sold, and the Raiders' Cache can never trigger

- **Where:** `tools/check_levels.py:874` (`if needs not in sold: continue`).
- This is the same defect as server.md Minor 1, seen from the gate's side.
- **What:** the cache's chest is a collidable 12 × 12 × 10 block, and the trigger is 5 / 1 / 9 from its
  centre and foot.
  - Every root within 5 of the centre is inside the block.
  - A root on its top is 13 over the foot.
  - My scan finds no standable point that meets the cache's trigger. The shrine's is met on its top.
  - Because (a) and (d) run only for sold keys, nothing would have caught it, and nothing will catch the same
    thing for any W2/W3 chest until its key is sold.
- **Also in W1:** the Island Shrine is walkable today, because the Pond is solid water, like the Creek
  `check_levels` requires. When ice becomes a key in W3, nothing yet says the shrine must be out of reach
  without it.
- **Fix:**
  - Run (a)'s "the trigger holds a standable point" for every secret, whatever its key.
  - Either measure `Triggered`'s reach from the chest's footprint (server.md's fix, and the Python mirror with
    it), or shrink the cache to the lookout's 6 × 4 × 6.
  - Note in PLAN, for W3, that the shrine needs a "without ice" reach rule and a pond that is not solid.

### 3. The L2-20 "one jump" gate cannot fail

- **Where:**
  - `tools/sim_range.py:2347-2353` (`take_off`)
  - `tools/sim_range.py:2395` (timed jump)
  - `tools/sim_range.py:2795` (`can_jump`)
  - `tools/sim_range.py:9504-9507` (the gate)
- **What:** the planner offers a jump only when `can_jump` is true, which means not airborne and not
  launched. The timed and hop paths drop an air jump silently, before `take_off` can count it. So
  `airAsked` is 0 by construction.
- **The mutation that shows it:** I set `can_jump = True`, so the planner may jump in the air. The human's
  Normal seed 11 still reports `airAsked 0`, cleared at 4.23 min, and the gate stays green.
- **Scenario:** a future planner change that relies on an air jump through `jump_at` passes the gate unseen.
  L2-20 asked for "confirm it by a check, not by reading".
- **Fix:**
  - Count the two silent drops in `air_asked`: the timed jump firing while `jump` is set or while lifted, and
    the hop.
  - Or replace the gate with a statement that the sim has no air-jump state at all, plus a mutant in
    `check_levels_mutants`' style that re-enables an air re-take-off and expects the gate red.

### 4. Small mirror and documentation drifts

- **`Unlocks.DefProblem` (`Unlocks.luau:44-46`) accepts an empty `text`, but `check_levels.check_abilities`
  requires a non-empty one.** The tool is stricter, so the shipped data is safe. Say which one is the rule,
  or align them.
- **`secret_problems`' family length counts code points (`len`), while StageFlow's `#family` counts bytes.**
  These agree for ASCII ids only. Note it next to `SECRET_FAMILY_MAX`.
- **BALANCE.md "L2 W1" says the Leap route's two holes are "neither closed by geometry".** True. But the
  "today" row (937) is no longer the code: it describes main before e39215b. Label the table "before F1 + F2"
  so a later reader does not take 937 as a live risk.

## Gates on the snapshot

- `check_levels_mutants.py --luau <main luau>`: `MUTANTS: PASS`. Every L2 case behaves as labelled: red, or
  green for a control.
- `mutate.py <snapshot> <luau> "l2"`: `MUTATIONS: 53 run, 0 not caught`.
- Both sides' `secretProblems` disabled together: `check_stage_mirror` `FAIL (13)`. None of the L2 refusals is
  vacuous.
- `can_jump = True` in the sim: the gate stays green (Minor 3).
