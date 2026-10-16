# L1b Wave 4 fix round — luau-engineer A (the crowd), report

Branch `l1b-wave4` in `tycoon-p5`. Rulings R1–R7 of `docs/prompts/l1b-w4-fix-round.md` (R7: the
`CampBrain` part). Mutation texts, verbatim and importable: `crowd_mutations.py` beside this file.

## Commits

| Ruling | Commit | What |
|---|---|---|
| R1 | `7a76d76` | closing means progress |
| R2 | `2d95152` | the close lets a blow finish |
| R4 | `55728ac` | heal once at the post |
| R6 | `5dd0662` | no hits through a cliff (VitalsService) |
| R7 | `9022272` | the tent's pace starts again after rest (signatures in the message) |
| R3 | `ac71e28` | the engagement check restored |
| R5 | `0544b26` | brutes walk round the U-bend |

B adapted WaveService to R7 in `b05e5a9`.

## Fixes (file : function)

- **R1** `CrowdService.luau` : `integrate`. `Enemy.goalGap` (math.huge at spawn) holds the flat
  distance to the routed goal at the last step that had a goal. It is measured from the step's start
  position, where separation left the body. A thinking resident rusher stamps
  `closing = gap < goalGap − MOVE_THRESHOLD × dt`, then `goalGap = gap`. A step with no goal (windup,
  recover, within stop) stamps false and leaves `goalGap` alone. So a windup at the edge does not
  read as progress when the walk resumes. Every body with a goal updates `goalGap`; only thinking
  rushers stamp.
- **R2** `CrowdService.luau` : `integrate`. A resident whose mind is in windup, attack or a charge is
  never resting, whatever its group's state (stand-down, leash, `Forget`). So it thinks until the
  blow resolves, and only then walks home.
  - **Beyond the ruling's text:** `CampBrain.luau` : `Step`, state `home` now rests only when
    `not input.striking`.
  - Why: a guard striking from its own post at the close would otherwise let its group rest at the
    next step. Far from every player it then goes dormant. A dormant body is never integrated, so
    its windup freezes and still holds its place (Commit runs for dormant bodies).
  - The designer must mirror this.
- **R3** `tests_l1b_crowd.luau` : the leash case. A player on the floor behind the posts is in play
  for the homeward group (no region), outside every cone, so `not Crowd.Engaged(7)`.
- **R4** `CrowdService.luau` : `campStep`.
  - `Enemy.healed` is cleared on any camp step where `CampBrain.StandsDown(brain, rusher)` is false.
  - A stood-down rusher at its post is healed only while `healed` is false, then latched.
  - A homeward group's heal is unchanged (every step at the post until it rests).
- **R5** `CrowdBrain.luau` : new local `laneRuns`, asked in `begin` before `admit`. On a floor with a
  region, a `lane` starts only if `Region.Runway(from, snapped(facing), radius)` is at least
  `distance − width`. Otherwise `choose` moves on, or the brute walks. Its goal routes through the
  doors as any goal does. Floors with no region (range, arena, the Chief's Clearing) are unchanged.
- **R6** `VitalsService.luau` : `decide` (the height test). Every ground shape now uses
  `held = above <= height and above >= -height`; before, only a lob had the lower bound.
- **R7** `CampBrain.luau` : `TentState`, `NewTent`, `TentClock`. `CrowdService.luau` : new `Stirred`.

```luau
export type TentState = { left: number, nextAt: number, busySeconds: number, lastAt: number?, residents: number }
CampBrain.NewTent(stock: number, residents: number): TentState      -- residents = the zone's count
CampBrain.TentClock(tent: TentState, busy: boolean, now: number, rested: boolean, residentsAlive: number): ()
	-- rested (every group of the camp at rest): busySeconds = 0, lastAt = nil, residents = residentsAlive;
	-- else as before
CampBrain.Ahead(killed, residents, busySeconds, pace)               -- unchanged; called with
	-- killed = tent.residents - residentsAlive, residents = tent.residents
CrowdService.Stirred(): { [number]: boolean }
	-- floors with an unheld group in rise, fight or home that has a living member (a new table);
	-- rested = Stirred()[floor] ~= true
```

## Cases (all in `tests_l1b_w4_crowd.luau` unless named)

- **R1** "fix round: closing", in two parts:
  - (a) Four fodder against a hitter 5 under the floor and 11.3 past the road's inset end, who hits
    every 4 s. They go home at step 113 (band 75–120), all four at the edge first, and his hits do
    not turn them back.
  - (b) Four fodder and a slinger, with the player 12 over the floor and 5.6 past the end. The four
    rushers stand down and are back at their posts by step 146 (≤ 165). The group stays in fight.
- **R2** "fix round: the blow". A guard winds up at its post, then `ForgetOthers` runs.
  - The group goes home at the next step.
  - It rests only once the blow is done (step 12, ≥ 6).
  - Both free fodder on floor 2 then strike the player at once (perPlayer 2).
- **R3** the leash case in `tests_l1b_crowd.luau`.
- **R4** "fix round: heal once".
  - Healed on arrival.
  - A hit at the post stays for 2 s while the slinger fights.
  - Melee-reachable again, then stood down again: healed again on arrival.
- **R5** "fix round: the U-bend brute".
  - On the 6-wide fixture U, with the player 20.7 away across the void: no lane.
  - The brute reaches the far door (step 46).
  - On the leg's line it charges (10.8).
- **R6** "fix round: cliff". With `arc` and `lunge` from `tests.luau`:
  - feet 8 under the floor: both miss;
  - feet exactly 6 under: the arc hits;
  - feet 5.1 under a height-5 lunge: it misses.
- **R7** "tent pace": restart at rest, kept while homeward, a fast clear ahead again after a restart,
  rested wins. "fix round: stirred": rest, fight, home, rest, held and dead groups.
  `tests_l1b_w2_crowd.luau`'s `NewTent` calls take a resident count, and the NewTent check reads it.

## Mutations

- **Method.** Each mutation was applied alone to a scratch copy of the worktree, with the harness run
  on it.
- **Result.** All 16 new ones, the 4 replaced texts and the old `l1b crowd: a group walking home
  engages` (R3) are caught.
- **Re-run.** All 21 re-proved on the final tree after the last commit (`0544b26`): 21 of 21 caught.
  The one tests_w2 check that pins the old R6 rule was excluded from the verdict.
- **Texts.** Verbatim in `crowd_mutations.py`:
  - `L1B_W4_FIX_CROWD_MUTATIONS` (16);
  - `L1B_W4_FIX_CROWD_REPLACED` (4): `l1b crowd: a resting resident thinks`, `l1b w4 crowd: a
    stood-down rusher keeps thinking`, `l1b w4 crowd: a stood-down rusher is not healed at its post`,
    `1c: the lob reaches under its floor`;
  - `L1B_W4_FIX_CROWD_RETIRED`: `1c: every ground shape has an under side`, whose rule is now the
    code. Its successor is `l1b w4 fix crowd: only a lob has an under side (R6)`.
- **Staleness.** A scan of every `mutate.py` entry against my files found exactly those five stale
  entries, and nothing else. `mirror_mutants.py`'s CampBrain texts are all still present.

## Verify

- `stylua --check src`: clean.
- `selene src`: 0 errors, 1 warning (the old `LegacyPanel.luau` shadowing, not mine).
- `py tools/check_compile.py`: `CHECK: PASS -- 157 files compile with Studio settings (-O1 -g2)`.
  CrowdService has 99 top-level locals.
- Harness: `HARNESS: FAIL (1 of 2,319 checks, …tycoon-p5\tools\crowd_harness)`.
  - The one failure is `tests_w2.luau`'s "an arc still measures from the crowd's floor with its upper
    bound alone (feet 8 under it: hit)". It pins the rule R6 replaces.
  - That file is on the untouched list, so I did not edit it.
  - With the diff below applied in a scratch copy, that check passes and nothing else changes.

## For other owners

- **Lead (`tools/crowd_harness/tests_w2.luau`, R6's pinned check, lines 903 and 909):**
  ```diff
  -	-- Only the lob changed: the other ground shapes lie on the crowd's floor, upper bound alone.
  +	-- L1b Wave 4 fix round R6: every ground shape has the lob's lower bound (a region floor ends at a drop).
  ...
  -	check(humanoid.Health == 100, "an arc still measures from the crowd's floor with its upper bound alone (feet 8 under it: hit)")
  +	check(humanoid.Health == 130, "R6: an arc measures from the crowd's floor with both bounds (feet 8 under it: missed)")
  ```
- **B (`mutate.py`):**
  - Add `L1B_W4_FIX_CROWD_MUTATIONS`.
  - Update with `L1B_W4_FIX_CROWD_REPLACED` after the tables that define those labels.
  - Delete `"1c: every ground shape has an under side"` with a comment naming its successor.
  - The `UNDER` constant (`'(shape ~= "lob" or above >= -height)'`) no longer matches VitalsService.
    Drop it once both 1c entries are handled.
- **B (WaveService, R7):** done in `b05e5a9`.
- **Economy-designer (mirrors):**
  - **R1:** see "Fixes" above for the exact rule. `MOVE_THRESHOLD` is 0.2 studs/s, `dt` the crowd
    step.
  - **R2:** a striking or charging member thinks whatever its group's state. Home rests only when no
    member strikes.
  - **R4:** heal once, latch cleared when the body no longer stands down.
  - **R5:** a lane on a region floor needs `Runway ≥ distance − width`.
  - **R6:** the height rule's lower bound applies to every ground shape.
  - **R7:** `TentClock`'s new arguments, with `rested = not Stirred[floor]`.

## Found, not fixed (outside the rulings)

1. **A blow aimed below the lip still holds the leash.** Think measures reach on the flat (ruling
   21), so rushers at a lip still wind up at a player below them within flat reach. After R6 the
   blow misses. But `striking` holds the leash, and four fodder at perPlayer 2 taking turns could
   keep it held while a hitter stands right under the lip within reach. I did not probe this; the
   R1 case puts its hitter past reach.
   - Candidate fixes: skip `begin` for a target whose feet are more than the attack's `height`
     under the floor, or let the leash ignore such blows.
2. **R7: a resting kill can be absorbed.** If a resident is killed at rest by one shot, a run tick
   can land before the camp step wakes the group. That tick's restart then counts from the
   survivors. At most one tick, and the result reads as a fresh camp.
3. **R5: diagonal charges on narrow cells.** On cells only a little wider than a brute, a diagonal
   lane toward a player near the edge is refused. The brute then stands at its stop distance (the
   6-wide fixture shows it). Forest Road's road cells are 16 wide (inset 11.6), where `width` 5
   leaves room.

## What to check in Studio

- Below the climb, while a sniper hits A's rushers:
  - they leave the lip about 3 s after packing there and walk home;
  - no lunge lands on a player standing at the foot of the climb.
- From the ledge, a stood-down rusher at its post keeps the damage it takes. On Hard, the
  armoured's plate can be broken.
- At the Chief's close with a raider mid-swing on the road: it finishes the swing, walks home, and
  the Chief's fodder still attack in pairs.
- A U-bend brute walks round by AB3 rather than lunging at the void.
- After chasing the Pickets out and losing them, then a fast clear at 4 / 4: the tent sends again.

## R14 — the foot of the climb (added by the lead during the round)

### Changes
- **`CampBrain.Melee`:** a new lower bound, `root.Y − floorY ≥ −camps.meleeBelow`. It is measured
  as `meleeAbove` is: the root against the floor.
  - `meleeBelow` is in `RULE_KEYS`. It must be finite and not negative (0 is allowed).
  - `Types.CampRulesConfig` gains `meleeBelow: number`.
- **`CrowdBrain.begin`:** a new local `reaches`, asked before `laneRuns` and `admit`.
  - It applies to a lunge, an arc, a lane or a ring that has a `height`. These are the ground
    shapes judged from the crowd's floor; a line, a lob and a shot are left alone.
  - Such an attack is not begun unless the target's feet lie within `height` of the floor, above
    or below (R6's band).
  - The feet are those of the surface the target last stood on (`restY − lift`), not the airborne
    root. So ruling 21 holds: a player jumping over the floor is still wound up at. A player on a
    ledge, or at the foot of a drop, is not.
  - It applies on every floor, the range's and arena's included. Bosses will no longer start a slam
    or a charge at a player standing on a block higher than its `height`; `choose` moves to their
    next attack. Before, those blows started and missed. The designer's boss sims should confirm
    this.

### The value
- I used `meleeBelow = 1.5` in the harness rules.
- What it must cover:
  - **At least 0:** a player standing on the floor or the road has a root 3 over it.
  - **At most `lowest rusher ground height − ROOT_HEIGHT − COVER_MARGIN`:** that is 5 − 3 − 0.5 =
    1.5. Then every melee-reachable player can be hit, mirroring the `meleeAbove` gate (7.5).
  - **At most `sightBelow` (4):** past that, the band refuses first.
- With 1.5, a step down off the region's edge of up to 4.5 studs (feet) still counts as reachable.
  The foot of the climb (feet 8 under, root 5 under) does not. With today's `sightBelow` 4, the foot
  of the climb is also out of the band.
- **Combat.json must get `"meleeBelow": 1.5` before this ships.** Without it,
  `CampBrain.Problems` refuses the camp rules: `WaveService` warns, and `SetCampRules` drops them.
  The harness does not see this, because no real-file case runs `Problems` on `Combat.json`.
- Suggested `check_levels` gate: `0 ≤ meleeBelow ≤ min(sightBelow, lowest rusher height −
  ROOT_HEIGHT − COVER_MARGIN)`.

### Cases (`tests_l1b_w4_crowd.luau`, "fix round: the foot of the climb", and the chase tests)
- Problems with `meleeBelow` missing, NaN or negative: one line each. A value of 0 is fine.
- `Melee` at the edge −1.5 is in; −1.51 is out.
- Four fodder at the road's end over a hitter 8 under the floor, 2.3 flat past their inset end:
  - (a) out of the band, known by his hits;
  - (b) with `sightBelow` 6, in the band and seen.
- In both, no blow is begun (0 body-steps in windup or attack), they go home by step 112 and step
  101 (at most 120), and he is never engaged.
- Ruling 21 kept: a fodder still winds up under a player in the air whose feet are 6 to 8 over the
  floor.

### Mutations and verify
- Five new mutations and one replaced text (`l1b w4 crowd: Melee ignores meleeAbove`) are in
  `crowd_mutations.py`. All six were proved caught.
- The `mirror_mutants.py` entry "Melee ignores meleeAbove" is stale too. Its new text is in the
  same file, for the designer.
- Verify:
  - `stylua --check src`: clean.
  - `selene src`: 0 errors (the old `LegacyPanel` warning).
  - `check_compile`: PASS, 157 files.
  - Harness: **`HARNESS: PASS (2,333 checks)`**. This includes the lead's `tests_w2` fix.

### Found
- `ThreatField`'s travelling judges for a charge and a ring test only the upper bound
  (`who.feetY − strike.floorY > height`, `ThreatField.luau:298` and `:346`). R6 gave the lower bound
  only to the queued shapes in VitalsService. A lane cut at the lip, or a ring, could still reach a
  player under the drop. `ThreatField` is on the untouched list.
