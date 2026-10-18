# L2 W2 review: data and tools slice (2026-10-18, l2-w2 at 0f78d30)

**Result: 0 Critical, 1 Major, 4 Minor.**

**Scope.** I reviewed these files:
- ProvingGrounds.json (the flamethrower), Expeditions.json, Combat.json, Levels/1_ForestRoad.json and
  Layouts/Levels/ForestRoad.json;
- check_levels.py, check_levels_mutants.py, sim_range.py and check_stage_mirror.py;
- BALANCE "L2 W2";
- tests_l2w2.luau, tests_l2.luau, mutate.py and run_harness.py.

**How.** I rebuilt the cave by hand from ForestRoad.json. Every block was turned into an x/y/z box and every
seam checked. All tools ran on a `git archive HEAD` copy:

| Tool | Result |
|---|---|
| `check_levels` | PASS, 15 s |
| `sim_range --check` on 64-bit 3.12.10 | PASS. Every L2-39, pair, tunnel and open-spot line matches BALANCE |
| harness | PASS, 2,758 checks |
| `check_stage_mirror` | PASS |

I did not re-run `check_levels_mutants.py` (35 min) or `mutate.py` (about 2 h). I read their new cases instead.

Probes are in the session scratchpad, `dt_w2/probe/roof.py` (lift routes onto the ridge) and `sight.py` (what
R8's sight rule drops).

## Major

**M1. The ridge's roof can be reached with a lifting ability from the lookout ledge. The gate that says nobody
stands on it never models that.**

- **Where:** `src/shared/Layouts/Levels/ForestRoad.json:307, 308-310, 318-319` (CaveWallS2, the alcove walls,
  CaveRoofE and CaveRoofAlcove, all top 64). The gate is `tools/check_levels.py:3744-3750`, which rests on
  `unclimbable` at :476-500.

**What.** "Every wall that faces the sealed air is unclimbable" uses `unclimbable`. Its horizontal model is
`stray_reach`: jump, double jump and dash, 46.6 studs. It has no horizontal ability travel. Contract L2-37 also
asks that "(c) also runs against the tunnel", but `lift_routes` is only called for secrets keyed on a sold
ability (:1055). Nothing runs it against the ridge.

**The route.** This needs a Double Jump owner holding the Greataxe.
1. From the LookoutLedge (top 34), jump and double jump to feet 64. That covers about 15.6 studs of walk in the
   air.
2. Dash 20 studs. The dash holds altitude.
3. Cast Leap Smash. Over the void, `WallClip.CasterFloor` gives 64 − 30 = 34. RoofE's top (64) is exactly
   `Rise` (30) above that, so `TooHigh` allows it.
4. `LeapApex` lifts the arc 10 studs over the target, and the player lands on CaveRoofE.

**Hand trace.**
- Take-off at (−240, 64, −70), 31.3 studs from the ledge's corner (budget 35.6).
- Target (−214, 64, −83.5), 29.3 studs away (castRange 32).
- The path crosses z −82 at x −216.9, 3 studs east of the end of CaveWallS1 and CaveRoofW (the 84-high parts).
- The feet are about 68 there.

**Probe.** `lift_routes` with the double jump's Rise (jumpHeight 30), keys set to RoofE's top: 4 take-offs
with the gate's own conservative jump reach, 8 with the real one. All of them are off the ledge's edge over the
void.

**What it opens.** RoofE, RoofExitLeg and RoofExit are one 64-high deck, and one more jump plus double jump
reaches the 84 parts.
1. **A camp-A bypass without fire:** ledge → roof → drop onto RoadAB5.
2. **A perch R8 never sees:**
   - RoofExit is 0 studs from the RoadAB5 cell in plan and 56 over the floor.
   - Nothing is tall enough to block its sight.
   - It lies over Main Camp's west gate.
   - It is unrated on Hard, where no known limit is allowed.
   - `tall` hides it from `sniper_spots`.

**The Spear does the same.** Its Impale Dash holds altitude for 30 studs in the air
(`MovementController.Lunge`), and no rule models that either.

**Today, and when it goes live.**
- **Not reachable from a W2 save:** the dungeon place only owns starters and written families. It is reachable
  with `DebugGrantFamily`.
- It goes live the day L3 sells the Greataxe or the Spear.
- The contract set `fielded_lifts` = every family for exactly this reason.

**Fix, data.**
- Give every 64-high piece within ledge/chest + 15.6 + 20 + 32 + 1 (about 70 studs) a top of 84.
- That covers CaveWallS2 and CaveRoofE west of about x −195 (split the block), and the three alcove walls with
  CaveRoofAlcove.
- 84 − 38 = 46 is over the most a lift adds (30 + 10 + a 3-stud step up).

**Fix, tools.** In `check_cave`, run `lift_routes` with the double jump's Rise against every wall top in
`shut.boundary()`:
- take-offs at `top + jumpHeight + doubleJumpHeight`;
- the void floor at feet − 30;
- take-off pushes of the real jump-plus-double-jump reach plus the dash.

Add a mutant: today's data must go red. A follow-up: add the longest horizontal ability travel (castRange 32, an
Impale Dash of 30) to the reach `unclimbable` uses for the ability-height part.

## Minor

**m1. `unclimbable` uses 46.6 studs, but the contract and BALANCE promise 49.3.**
- **Where:** `tools/check_levels.py:482` (and 2974 for the walled gate).
- **What:** `unclimbable` uses `stray_reach(move, 0)` = 46.6. The contract (§5) and BALANCE say every ridge
  wall is 46 over every surface "within 49.3", the walk-off grace included. The gate prints "within 46.6".
  `check_route_skips` (:3899) does add the grace. The shipped data holds at 49.3 too (RoofE and S2 sit 52.5 from
  the ledge), but a wall moved into the 46.6–49.3 band would pass.
- **Fix:** add `walkSpeed × coyoteSeconds` in `unclimbable`, as :3896–3899 do.

**m2. L2-47 claims no hop cuts a bend, but its reach leaves out ability travel. The open BC bend can be cut.**
- **Where:** `tools/check_levels.py:3878-3955`.
- **Why the rule misses it:** reach = jump + double jump + dash + grace (about 49). RoadBC2's east edge (x 128)
  to RoadBC4's west edge (x 182) is 54 studs of void with no wall, so the rule calls it safe.
- **The cut:** jump, double jump and dash (35.6 out, feet 38), then Leap Smash onto BC4 (castRange 32). The
  caster's floor over the void is 38 − 30 = 8, so the target is legal. An airborne Impale Dash also works
  (+30). Both cut the bend and save about 75 studs of road, about 4 s.
- **Limits:** no camp is skipped, and it needs the Greataxe or the Spear. The AB bend that Ben asked about is
  physically closed: BendWall meets CaveWallS2 and CaveWallExitLegW, every part is 64 high, and a lift apex from
  the road is at most 48.
- **Fix:** add the longest fielded ability travel to the reach, or record a known limit until L3. A BendWall at
  BC is the data alternative.

**m3. Thin cave walls let a forged shot origin start outside the cave.**
- **Where:** ForestRoad.json, the 2-stud walls CaveWallN1/N2, MouthW/E, the three alcove walls, ExitLegW/E,
  ExitE and ExitS, plus the 4-stud S1/S2. R8's sight rule is `check_levels.py:2160-2168`.
- **What:**
  - `aimAllowed` / `CheckAim` only checks the origin's distance from the head: originPad 6 plus slack, with no
    ray from head to origin.
  - A modified client standing against a wall in the open tunnel can start a shot, or a GroundPoint camera ray
    for Arrow Rain, on the far side.
  - For example, from CaveTunnel through S1 onto Road5 or RoadAB1, about 35 studs away.
  - R8's new sight rule drops CaveTunnel, CaveAlcove and CaveExitLeg (my `sight.py` confirms exactly these four,
    plus Secret_cache) on the assumption that walls stop shots.
- **Limits:** open variant only, modified client only. It is the same as the gatehouse walls today.
- **Fix:** have the server check the head → origin line with a ray (server slice), or make ridge walls thicker
  than originPad + slack.

**m4. R8 rates CaveExit with the bow only, but Dragon's Breath reaches RoadAB5 through the exit corridor's
wall.**
- **Where:** `tools/sim_range.py` `cut_snipers` (rates the open spots with the Longbow course only). The
  geometry is ForestRoad.json CaveWallExitS (z −54..−52, 2 thick, 3 studs from the RoadAB5 cell).
- **What:**
  - Dragon's Breath cones ignore walls (L2-29, the Slug Burst launcher). Anyone in the cave owns the
    Flamethrower.
  - Behind ExitS at z ≈ −55, x −116..−86, the cones (range 20, plus pad and radius) reach bodies on RoadAB5.
  - Rushers stop at the cell's edge, 3 studs off, which is over chaseMargin 2.5.
  - Shooters' shots are cut by the wall at fire.
- **Limits:** the pay is bounded. Damage counts only while `CampBrain.InPlay` holds, which needs a living
  keepAway member with him in reach, and camps never refill.
- **Fix:** rate each open spot with the fire family's ability as well, or keep the corridor (except the mouth)
  more than 20 + 0.8 + the widest radius from the cell.

## Verified (what the brief asked)

**Sealed without fire**

By hand:
- Both brambles run floor to roof (W 0..22, E 8..22; every roof's foot is 22) and sit half a stud into the walls.
- The floors run under the brambles.
- Every wall and floor foot is at −4.
- The alcove closes the N1/N2 gap at x −220..−204.
- The ExitLegW/S2 and N2/ExitLegE corners are contiguous.

By gate:
- The Enclosure fill is sound: a gap of any width is its own cell, and fences or the barrier are left out, which
  is conservative.
- The mutants (a 1-stud gap, a 0.2 slit, a short roof) are real.
- Dash, leap and lunge are physics movers (LinearVelocity), so nothing tunnels through a 2-stud part.
- Players do not collide with players.

The only hole in "every means" is M1, and it reaches the roof, not the cave.

**Walkable with one jump**
- The single +8 step at z −86 has 22 of headroom.
- Every leg is 12 wide (width checked between walls), with a 14-stud headroom in the long leg.
- The route is 350 studs, replacing 342 and skipping camp A.
- The main route is still 1,079 (band 900–1,100).
- The sneak margin along the shortcut is +14.0 (B.fire1). Pickets fireN is 60 away (sight 16).

**The cache trigger**
- The footprint grown by 2.5 is x −217.5..−206.5, z −109.5..−98.5, inside the alcove.
- A root on the tunnel floor is at least 3.0 from the footprint.
- The chest's top has 10 studs of headroom.
- The shortcut box is x −86..−74, y 8..20, z −64..−54. It cannot be met while the east bramble stands, unless
  the player is inside.

**The bend.** It is closed as described in m2.

**The new check_levels rules are not vacuous.**
- Sealed and the ridge rule both expect a non-empty set.
- The chain resolves doubleJump → lookout → flamethrower → fire. It has a fixed point, so a cycle never
  resolves. The mutants for "pays nothing" and "no element" go red.
- The sight rule drops only roofed cave floors on today's data. The no-sight mutant goes red.
- The open list differs from the closed one only by CaveMouth and CaveExit (ruling 1).
- `react_problems` mirrors Validate, and the accepted-both and refused-both guards are in check_stage_mirror.

**The Flamethrower's boss numbers follow from the config.**
- Single: 5 × 10 = 50 dps.
- Colossus floor: 4,700 / 50 = 94 s. Measured 110.3 s, or 86.4 s with Dragon's Breath (144 per cast).
- Capsule hits never crit (WeaponService passes `false`). Ticks (5) and cones (36) both stay under heavyHit 40.
- The guard's and the Warlord's plates need the slam (11 of them).
- Against the Broadsword's slowest seed (77.2 s Colossus, 98.1 s Warlord), the margins are +11% and +14% with
  the ability, +43% and +29% without.
- The in-level pair (74.4 s against the Longbow pair's 77.1 s, ×0.96) is the accepted comparison.
