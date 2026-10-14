# L1b Wave 1 fix round: review of the fix diff

`git diff 9deef26 5ff333b` (branch `l1b-living-road`). This was a read-only review: I edited no
source and ran no harness or mutate.py.

Each fix was checked by building its failure scenario again against the new code:

- **Rounded in-play (crowd Major).**
  - CampBrain, `sim_range.cb_in_play`/`near` and the client's `campInPlay` use one formula:
    `max(|dx| - hx, 0)` and `max(|dz| - hz, 0)`, hypot, `<= chaseMargin`. The client compares
    squares, which is equivalent.
  - All three use the same height band (`floorY - sightBelow` to `floorY + sightAbove`,
    inclusive) and the same rectangle. `RunFloor` and the group `rect` are both `camp.x/z`,
    `sx/2`, `sz/2` and `camp.y`.
  - The gate `reach - sqrt(2) x radius` is the true worst case: 45 degrees maximises
    `|(r, r) + m(cos a, sin a)|`. With fodder (r 1.3, m 2.5) a 30 degree point is 4.30 from the
    clamped body, under the 4.5 reach.
- **Engaged hold (crowd Minor).**
  - `CampBrain.Engaged`, `sim_range.cb_engaged` and the LevelRun stamp/prune have the same edge
    and the same `1e-6` epsilon.
  - `simTime` advances on every crowd step once the crowd is running, so the hold always ends.
  - `forgetGroups` and the rules-nil branch clear the map.
  - The tests can fail. With no hold, the fall case's first read is false. The `home` case is
    more than leashSeconds after the last stamp.
- **Downed member stands up (run Major).**
  - `OnDown` runs after VitalsService's flush, so calling `StandUp` from `advance` does not
    re-enter the down path.
  - `canTarget` drops downed players, so a downed body cannot keep its group awake.
  - `standing` and `standUpOnRoad` filter members the same way (not a bot, has a player,
    `IsFighting`).
  - Nothing yields: `MoveMember` has no wait.
  - A boundary in the same batch leaves `standUpOnRoad` with nobody to stand. That case is
    harmless.
  - A solo down on a field that is already clear (the frame of the last kill) now gets up
    instead of lying down for the rest of the road.
- **Skip pays nothing.**
  - Every `open` a skip creates is marked `skipped`: the stage skip's `leaveCamp(..., true)` and
    the boss skip's passed camps. `campClear` is never emitted for a locking zone, so no clear is
    paid twice.
  - The simulator mirrors both paths, and `check_stage_mirror` compares `skipped`.
- **SafePoint threats.**
  - Crowd ids wrap only at 65,535, so a stale `awakeGroups` id cannot name a new body within a
    run. `threats()` drops dead bodies and ids that are gone.
  - `rescueFallen` runs one tick before `DrainGroupEvents`, so a group that has just woken is
    missed for one frame only. Busy() still covers its own floor.
- **Client.**
  - `CampFx` reconnects in `Alert`.
  - The notice guard only drops "Checkpoint", which is its only caller.
  - "Camps 1 / 3" fits the label.

## Minor

1. **`src/combat/client/Controllers/InputController.luau:1073-1089` (`campInPlay`): on a phone,
   auto-fire and auto-swing refuse a fight that the server accepts.**
   - The gate leaves out the server's keepAway clause (`CampBrain.InPlay`: in play while within
     a living shooter's reach). It also applies to bodies of groups that are already awake,
     where a shot can wake nothing.
   - Scenario on Forest Road:
     1. A phone player with a bow fights camp A, then backs 8 studs down RoadAB.
     2. A's slinger (reach 32, band 18 to 30) keeps him in play and keeps shooting.
     3. The fodder wait, clamped at the floor's edge.
     4. On the server his shots would land (L1b-7, through the shooter's reach). His client
        never draws or fires at any body of camp A until he walks back to within 2.5 studs of
        the floor.
   - So a touch player cannot kite or return fire from range, while a PC player can. Touch has
     no manual attack button.
   - This follows the ruling's text ("only makes this stricter"), but the consequence for awake
     camps was not weighed.
   - Fix: skip the gate while the local `PartyMember.engaged` is true. The phone then answers
     the fight it is in, and still never opens one from range.
2. **`tools/sim_range.py:6660` against `src/combat/server/Services/StageFlow.luau:1128`: the
   simulator's stand-up on a quiet road misses the boss room's countdown.**
   - The simulator stands the player up only when `flow in ("travel", "armed")`.
     `StageFlow.StandsUp` (the rule the server runs) also allows `gate`.
   - `check_stage_mirror.py` does not compare `StandsUp` (it is not in `NEEDED`), so this drift
     is not gated.
   - Scenario: the player is downed in the countdown while the field is clear (the last kill's
     committed blow, ruling 22).
     - Server: he stands up at C's entry and is closed in with the party.
     - Simulator: he stays down until the close, then loses the run "down" in C's fight.
   - Fix: add `"gate"` to the simulator's tuple, and compare `StandsUp` in `check_stage_mirror`
     on the existing `roadDown` variant (with steps travel, armed, gate, fight and breather).

Critical 0, Major 0, Minor 2
