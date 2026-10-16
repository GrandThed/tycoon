# L1b Wave 4 review, slice 1: crowd

The diff is `main..l1b-wave4` at 2ec9da9, read-only. The harness gives PASS (2,252 checks) on a
`git archive` snapshot. Every probe below ran on the real `CrowdService`, `CrowdBrain`,
`CampBrain` and `Region`. They were bundled by `run_harness.prelude` in the scratchpad, plus a
probe-only `CrowdService._camp = camp`. Nothing was written in the worktree except this file.

## Major

**M1. `src/combat/server/Services/CrowdService.luau:763-767`: two or more rushers pressed against
one clamped edge point never stop "closing".** Because of that, the group never stands down and
never leashes while it knows the player.

- **The cause.** `closing` is stamped from the desired seek speed (`desired.Magnitude >
  MOVE_THRESHOLD`), not from progress.
  - A goal off the region is clamped to one inset point. Every rusher of one kind gets the same
    point.
  - When the player is farther than the brain's stop distance from that point, the stop becomes
    `max(stop − d, 0) = 0`.
  - Only one body can stand on the point. `separate()` pushes the rest off it every step, so they
    seek it at full speed forever.
  - `CampBrain.Step` (`CampBrain.luau:568`, `:578`) then resets both `quietSince` and
    `meleeQuietSince` on every step. So `standDown` never sets, and the leash never fires.
- **Probe 1: a hitter below a road end** (out of the band, known only by his hit memory, hits
  every 4 s, 30 s run):
  - 1 fodder: home at 5.9 s.
  - 2 fodder: never home and never stood down; a closing stamp on 435 of 450 steps.
  - 4 fodder: never home and never stood down; a closing stamp on 449 of 450 steps. The bodies
    show `move` at the edge the whole time.
- **Probe 2: a player 12 over the floor, 4.3 flat past the road's end** (in the band, known by
  sight with no further hit), with 3 fodder and a slinger:
  - `standDown` never set in 30 s, with a closing stamp on 358 of 450 steps.
  - The fodder keep winding up at a player they cannot hit.
  - Over the floor's interior, where the brain's stop of 4.5 lets them settle in a ring, they
    stand down at 3.9 s. So the bug shows only where the goal is clamped.
- **On Forest Road.** A's groups have 4–6 fodder each.
  - Checklist step 2 ("shoot them as they walk home"): every arrow at the crowd waiting at the
    drop's top refreshes `hitMemorySeconds` (8). They stand there for as long as he keeps
    shooting, which is the step's own Bug line.
  - The lookout ledge: a root at 37 is 29 over A's floor, inside `sightAbove` 30, so the player
    is known by sight. The rushers pack under the ledge's edge for good, which is what
    `meleeAbove` was meant to prevent.
  - The sniper's pay and "the rushers stand down" were measured in a simulator that never
    produced this. The lead's ruling records that the stand-down was not visible on Normal, and
    was proved only on Step timelines.
- **Fix.** Stamp `closing` only while the rusher makes progress.
  - Option 1: its flat distance to the routed goal, after the clamp, shrank by more than
    `MOVE_THRESHOLD × dt` since its last step (one number field on `Enemy`, no allocation).
  - Option 2: treat a body whose goal was clamped off the region (`not through` and the goal
    moved) as arrived once it is within about `2 × radius + homeTolerance` of the point.
  - Add a harness case with 4 rushers and a hitter below a drop, and mirror the rule in
    `sim_range`.

## Minor

**m1. `src/combat/server/Services/CrowdService.luau:1078` with `:663`, and `CampBrain.luau:654-665`:
`ForgetOthers` sends a striking group home in the middle of a blow.** The blow then stays frozen
for the rest of the run.

- **Why it freezes.**
  - `Forget` does not wait for `striking`, which the leash does.
  - `integrate` treats any group not in `fight` as resting, with no exemption for a windup or a
    charge. The stand-down has that exemption.
  - So the mind stays in `windup`, or a brute stays in `attack` with its `charge`.
- **Why it matters.**
  - `CrowdBrain.Commit` (`:1227`) counts every striking mind, resting or not. The frozen body
    therefore holds one `perPlayer` place of its kind against that player for good, and a
    slinger's windup also holds one `maxShots` slot.
  - Probe 3: after a frozen fodder, three free fodder on another floor never got more than 1 of
    `perPlayer` 2 strikes on the same player in 10 s.
  - A frozen brute (`perPlayer` 1) would leave the Chief's brutes unable to ever attack that
    player.
  - If the group is woken later, the overdue impact lands at once.
- **When it can happen.** A body must be striking a player at the very step of the close, and
  `moveFighters` must pull that player into the room. In practice that means a party member left
  fighting on the road, or a solo player who walked back out during the countdown.
- **Fix.** Either let `Forget` answer "home" only once no member is striking (pass `striking` in,
  and retry at the next step), or keep a striking or charging member thinking in `integrate`, as
  the stand-down already does.

**m2. `tools/crowd_harness/tests_l1b_crowd.luau:742-753` (the leash case): the deleted check "a
player in play for a group walking home is not engaged" leaves mutation `l1b crowd: a group
walking home engages` alive.**

- I applied that mutation's exact text to a snapshot. The harness answered `HARNESS: PASS (2,252
  checks)`.
- `mutate.py` will report it as not caught.
- **Fix.** Restore the check in Wave 4 terms. Put a player who is reachable for a homeward group,
  but outside every member's cone (so home does not turn back), and assert `not
  Crowd.Engaged(7)`.

**m3. `src/combat/server/Services/CrowdService.luau:1107-1112`: a stood-down rusher at its post is
fully healed on every camp step for as long as its shooters keep the group in `fight`.**

- Each heal restores the plate and clears `damageBy`.
- So from the ledge, any hit short of a one-shot lands, shows its number and is erased within
  1/15 s.
- On Hard, the armoured at A's posts cannot lose its plate while a slinger of its group lives.
  That is "BLOCKED" in all but name, against ruling 6.
- A homeward group heals the same way, but it reaches `rest` within seconds, so it never showed.
- **Fix.** Heal a stood-down rusher once, when it arrives at its post (a per-body latch cleared
  when `standDown` clears), not on every step.

**m4. `src/combat/server/Services/CrowdBrain.luau:936` (`begin`): a brute starts its lane whenever
the target is within flat reach (22), even when the region's runway toward it is a few studs.**

- On the U-bend, RoadAB2's and RoadAB4's centres are 22 apart across a 6-stud void.
- Probe 4, a brute in AB2 with the player in AB4 18 flat away:
  - 3 lanes in 10 s, the longest 5.3 studs;
  - the brute stayed at the void's edge (x −124.2);
  - it never walked round by AB3.
- Before Wave 4 every floor was convex, so this could not happen.
- **Fix.** In `begin`, or in `choose`, skip a lane whose `runway` along the facing is shorter than
  the flat distance to the target less the lane's width. The brute then walks the routed way.

## Verified, holds

- `Region` matches the contract function by function:
  - `Build`: BFS in index order, `next` by the first hop.
  - `Problems`: doors on both axes, the tree, and joined to cell 1.
  - `Clamp`: the first strictly nearer cell wins.
  - `Runway`: one cell equals the old runway.
  - `Toward`: fewest hops, ties to the lowest cell, the door at the body's Y.
- Every door centre lies inside both inset cells, so a straight walk from a door to the next door
  stays in the union.
- `CampBrain.Step` follows the contract's order:
  - the prune with the edge kept;
  - held fills both sets by `InPlay`;
  - known: hit memory with no band, then sight in the band;
  - the leash before the stand-down;
  - home turns straight to `fight`;
  - `struckBy` is cleared.
- `Struck` is held-only. `Forget` touches nothing on the kept floor.
- `TentClock`, `Ahead` and `TentActive` match L1b-W4-28 exactly.
- The executor's beyond-contract points 1–3 are implemented as reported:
  - finish the blow before standing down;
  - stop distance on a clamped goal;
  - a charging step stamps false.
- The Types block matches the contract verbatim.
- `SetFloors` keeps a region by reference and drops a malformed one with a warn. `AddGroup`
  refuses an empty or non-finite region.
- Nothing in the routing, the clamp, `ForgetOthers` or the camp step yields, raycasts or
  allocates per body. `CrowdService` has 99 top-level locals.
- Gate 18 (`\.inPlay\b` in `src/combat`) is clean.

## For other slices (one line each)

- **data:** `sim_range`'s pass on the sniper and ledge bands does not reproduce M1. Its
  stand-down was proved only on Step timelines. Re-measure both bands after the M1 fix.
- **data:** no `check_levels` gate covers standable ground at the region's own height that lies
  more than `chaseMargin` outside it. LookoutSignPad's block runs to x −306, but its cell stops at
  −302, which leaves a strip no rusher can reach. The perch gate only covers tops over
  `meleeAbove`.

Critical 0, Major 1, Minor 4
