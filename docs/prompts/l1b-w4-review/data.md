# L1b Wave 4 review, slice 4 (data and tests)

Reviewed `git diff main l1b-wave4` at 2ec9da9 (branch head d1363b8). The gates run green:
`check_levels.py` PASS, `check_stage_mirror.py` PASS, refusals checked one by one. All 20 Wave 4
refusals fail in the Python mirror for their own reason. Probes were run from the scratchpad
against `sim_range` and a `git archive` copy, and wrote nothing to the worktree.

## Major

1. **`src/shared/Layouts/Levels/ForestRoad.json:12` (Road5's cell runs to the lip, x −302), `tools/check_levels.py` `check_wave4`, `tools/sim_range.py:6525` (`SNIPER_BACK`).** Rushers at the lip lunge the player who stands at the foot of the climb, through 8 studs of cliff.
   - **The rule.** Think measures reach on the flat (CrowdBrain ruling 21). VitalsService's height test is `above = feet − strike.floorY ≤ height`, and only a lob has a lower bound. Feet at y 0 under a floor at y 8 give −8 ≤ 5, so the lunge hits.
   - **Probe.** In the simulator, which judges the same way, the sniper course was moved from x −324 to the foot of the climb:
     - at x −303.5 or −302.5, every seed takes 2–3 fodder lunges in about 3 s;
     - at x −306, only slinger shots land;
     - at x −324 (the shipped course), nothing lands.
   - **Why it matters.** Step 2 of the checklist says "drop back down the climb and stand below". The player lands right at the foot. While a fodder is striking, the leash waits.
   - **Why no gate saw it.** This is the first time Wave 4's region puts a resting floor's rushers next to a drop with standable ground under it. No gate looks for that, and the simulator's below-the-drop spot is 22 studs off the lip.
   - **Fix (data side).** Two parts:
     - Add a check_levels gate: no standable top below the band may lie within any rusher's ground-shape `range` minus its radius of a cell edge. Road4's east end fails it today.
     - Run one sniper course at the foot of the climb.
   - **Fix (lasting).** For the lead and crowd, in VitalsService, which is on the untouched list: give non-lob ground shapes the lob's lower bound, `above ≥ −height`. Mirror it in sim_range's height rule.
   - **Fallback.** Pull Road5's and LookoutSignPad's west ends back by the armoured's 7.5 − 1.7 = 5.8 studs (to x ≥ −296.2).

2. **`src/shared/Config/Levels/1_ForestRoad.json:129` (A `pace` 15 s, lead 0.2), `tools/sim_range.py:4920` (`TENT_FAST`).** Checklist step 4 promises that at 4/4 "a raider comes out every 6 s". After steps 2 and 3 the Pickets' tent can never send again.
   - **The rule.** `busySeconds` is cumulative for the whole run. `Ahead` needs `killed/30 − busy/15 ≥ 0.2`, and `killed/30` is at most 1, so after 12 s of busy time A is never ahead again.
   - **Probe.** A's clock after one scene:

     | Scene | A's busy time, 0 kills |
     |---|---|
     | Walk-out alone | 9.1 s |
     | Lose (Ben's step 3) | 16.7 s |
     | Archer | 12.5 s |
     | Sniper | 19.3 s |

   - **Why no gate saw it.** The "tent when fast" band is measured only on a fresh camp, so it cannot see the checklist's order.
   - **Fix (data side).** Add a band run in the checklist's order (the lose, then the 4/4 clear). It will fail.
   - **Fix (lead).** Either the rule changes (for example, the clock and the kill baseline reset when every group of the camp is back at rest, in `CampBrain.TentClock`, the crowd slice), or step 4 is moved before steps 2 and 3, with G pressed before Depart.

3. **`tools/sim_range.py:6525-6529` and `:7365-7372` (the sniper course), `:9290` (the band); `docs/BALANCE.md:4812` and `:4851`; INTERFACES `:15598`.** The sniper band passes only because the scripted sniper wastes time below the drop. Going straight to the ledge earns about 1.5 times the mission's pay a minute.
   - **The scripted course.** The sniper fires one arrow from Road5, then shoots from below the drop until 10 s pass with no hit landing (`SNIPER_IDLE_SECONDS`), and only then climbs to the ledge. That is how BALANCE gets "25–27 s, about 70% of the mission's cash a minute". The lead accepted that number and it was told to Ben.
   - **Probe.** With `SNIPER_BELOW_SECONDS = 0` (arrow, then straight to the ledge, which a double jump reaches from Road5), Normal at 2/2, seeds 11/23/37:

     | Course | Pickets cleared in | Hits on him | Cash a minute | Timber a minute |
     |---|---|---|---|---|
     | Ledge directly (probe) | 11–13 s, 31–32 kills | 0 | 42,048 / 38,801 / 35,572 | 57.1 / 51.9 / 47.6 |
     | Mission (whole run) | — | — | 24,134–25,891 | 40.2–43.1 |

     So the ledge clears the Pickets faster than the mission player walks in and fights them.
   - **Fix (data side).** Make the sniper's ledge leg its strongest course (straight up), or rate the ledge leg on its own. The band then fails on Normal.
   - **Fix (lead).** One of three: more or longer-reach shooters in Normal's A (the Longbow's pierce 5 kills the slingers in the first volleys), moving the ledge, or telling Ben the real number.

## Minor

1. **`tools/check_levels.py:1498` (the perch gate skips roots ≤ `meleeAbove`), BALANCE `:4857`, INTERFACES `:15598`.** Ground at floor height that lies farther than `chaseMargin` off the region is in no gate.
   - **RoadBC6.** At x 230–256, top 12, it is up to 58 studs off the region.
     - The lead's reason for accepting it is "B's floor is 127 studs away, past the Longbow's 110". That ignores the lure: a hit wakes B, he backs off shooting, and the hit memory pulls the group to RoadBC4 (x 182–198).
     - From x 240–256, nothing of B reaches him on Normal: the slinger's 32 from x ≤ 196.8 covers up to 228.8, and the lobber's 42 up to 238.6.
     - Meanwhile the Longbow covers RoadBC4 and RoadBC3 east of x 135, the whole walk home. Home ignores an unreachable hitter, so it is free fire for about 13 s per wake.
   - **The LookoutSignPad block.** Its west strip (x −306 … −302) is up to 4 off the region, past `chaseMargin` 2.5.
   - **Fix.** Gate every in-band standable top farther than `chaseMargin` from the region against the shortest keepAway reach. RoadBC6 will fail; the lead rules on it with the right reason.

2. **`tools/check_levels.py:1498`.** The sniper-perch gate drops tops over `sightAbove`. Those are the strongest nests: `CampBrain.Reachable`'s shooter clause needs the band, so no slinger keeps the group fighting.
   - **Secret_lookout.** Top 38, root 33 over the floor (`sightAbove` 30), 4 studs off the region. It collides and stands on the ledge, one jump up.
   - **Probe.** Sniping on Hard at 4/4, ledge raised to 38: seed 37 clears with 36 kills, where at 34 he goes down; seed 11 goes down at both heights.
   - **Fix.** Gate in-reach tops above the band as well. This needs `sightAbove` raised or a lead ruling. The rule's side is the crowd slice's.

3. **`tools/sim_range.py:2886` (and the parallel tests at `:2621`, `:2642`, `:2672`, `:2938`, `:2959`).** The simulator's height rule `self.feet(t) > height` measures from the player's own ground. VitalsService measures `feet − strike.floorY`.
   - On the ledge or the cache block, within a rusher's plan, the simulator says hit and the game says miss.
   - No shipped course stands that close: the ledge sniper is 8.3 flat off a clamped fodder.
   - **Fix.** Compare `ground + feet − crowd floor` with `height`.

4. **`tools/sim_range.py:3296-3303`.** A keepAway retreat in the simulator moves straight to the clamped point. In CrowdService every goal, Think's `inArena` retreat included, goes through `Region.Toward`.
   - At the U-bend the simulator's slinger slides against the void, where the game's walks to the door.
   - **Fix.** Send the retreat through `seek` / `route_goal` as the executor does.

## For other slices

- **Run:** `WaveService.luau:1643-1663` counts a refused tent spawn as `sent`, so `Fielded` pays a bonus on a body never fielded. The simulator copies it on purpose, at `sim_range.py:6822`. It is latent under the population rule.
- **Client / lead:** checklist step 7 says "a bonus for the Pickets only", which Ben cannot check:
  - `SummaryCard` shows no per-camp bonus and the "cleared" banner has none;
  - the Chief's Clearing pays its own bonus (BALANCE: C 4,660).
- **Crowd / lead:** VitalsService's missing lower bound (Major 1) and Reachable's band on the shooter clause (Minor 2).

Critical 0, Major 3, Minor 4
