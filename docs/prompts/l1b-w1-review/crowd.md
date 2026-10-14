# L1b Wave 1 review — slice 1, crowd

Diff `8e8990c..e2479c3`, worktree `tycoon-p5`, branch `l1b-living-road`. Read in full:
`CampBrain.luau`, `CrowdService.luau` (the L1b paths, `integrate`, `separate`, `Damage`, `die`,
`Spawn`, the camp step and every new API), `CrowdBrain.luau` (the diff, `Think`, `begin`, `admit`,
`Commit`, `chain`, `land`), `CrowdCodec.luau`, the Types block, `tests_l1b_crowd.luau` and the
`tests.luau` call site. Calls followed into `WaveService` (start, `placeResidents`, `tick`,
`rescueFallen`, `onGroupEvent`), `StageFlow.Rescue` / `IsOut`, `VitalsService` (the height rule)
and `LevelGeometry` (the fence boxes).

Probes run from a scratch bundle built with `run_harness.prelude` (nothing written in the
worktree; `mutate.py` not run, so it cannot collide with another slice):
- the range fixture: the pre-L1b sources (`git archive 8e8990c`) give hash 2948329570 over 2,400
  bytes, the number `tests_l1b_crowd.luau` pins, so gate 13's "the range is byte for byte" holds;
- a fall out of a fight, and a player off a floor's corner (both below).

## Major

1. **`src/combat/server/Services/CampBrain.luau:297-302` — the in-play area has square corners,
   so off a camp's corner a player can hurt residents that cannot reach them.** L1b-7's promise
   ("every player who can hurt a resident can be hurt back by it") rests on
   `chaseMargin <= reach − radius`, which holds along an edge only. A rusher is clamped `radius`
   inside both edges, so at the corner of the grown rectangle it is `√2 × (margin + radius)` from
   the player: 6.08 for fodder (reach 4.5). Probe on the real `CrowdService`: floor 60 × 60, a
   fodder guard woken by a player at (32.9, 32.9). The fodder runs to the clamp corner
   (28.7, 28.7), 5.94 away, and never winds up in 30 steps. Every hit from the player lands
   (verdict nil, HP 40 → 39). This is unreachable on the shipped Forest Road: no ground block
   lies off any camp corner, and the roads meet the floors inside their Z span. But
   `check_levels.py`'s `chaseMargin` gate cannot catch it, and Wave 2's bigger camps and sneak
   path are new geometry. *Fix:* in `InPlay`, measure the flat distance from the root to the
   floor rectangle and compare it with `chaseMargin` (rounded corners). Tighten the gate in
   slice 4 to `chaseMargin <= reach − √2 × radius` for every resting rusher kind (fodder 2.66, so
   the shipped 3 must drop to 2.5). A `tests_l1b_crowd` case and a mutation should pin a point
   just inside the rounded corner and one just outside it.

## Minor

1. **`src/combat/server/Services/CrowdService.luau:986-990, 1972-1974` — a fall out of a fight
   is never "engaged", so the rescue grants the get-up i-frames L1b-20 forbids.** `Engaged` is
   "in play at the last crowd step", and play has a height band (`sightBelow` 4). In `travel` the
   rescue fires per Heartbeat at `killY` (−13). A player who steps off camp A's floor (top 8)
   leaves the band after about 7 studs (0.27 s) and reaches `killY` after 24 (0.49 s), so three
   or more crowd steps see them out of play first. Probe: a fodder guard fighting the player,
   `Engaged(7)` true; the root 4.5 under the floor, then under `killY`: `Engaged` false both
   times, while `Busy()[1]` stays true. `WaveService.rescueFallen` then calls
   `StageFlow.RescueGrace(false, 1.5)` and grants 1.5 s. The contract's "Definition of done" line
   "a fall from camp A's edge mid-fight … with no get-up i-frames" cannot pass. The effect is
   small: the safe point already skips the busy camp. *Fix (crowd):* keep, per group, the
   userIds in play at any step since it last entered `rise`. `Engaged` becomes "in that set for
   a group still in `rise` or `fight`". The group stays in `fight` for `leashSeconds` after the
   player left play, which covers the fall. Clear the set when the group goes `home`. (The other
   way is for WaveService, slice 2, to latch `engaged` per member.)
2. **`tools/crowd_harness/tests_l1b_crowd.luau:621, 638, 764, 772` — no case reads `Awake`,
   `Busy` or `Engaged` while a group is `home`, so the home half of each rule is unpinned.**
   Concrete survivors:
   - `Awake`'s `state ~= "rest"` → `(state == "rise" or state == "fight")` (`CrowdService.luau:1952`).
     L1b-19 needs `home` counted, or a solo down while a group walks home reads as a clear field
     and costs only a respawn.
   - `Busy`'s `(state == "rise" or state == "fight")` → `state ~= "rest"` (`:1964`). The safe point
     would then skip a camp whose group is only walking home.
   - The camp step's engaged union read with `state ~= "rest"` (`:986`).

   StageFlow's own cases feed `awake` as a number, so no other file pins these. *Fix:* in
   `leashTests`, once the group has gone home, check `Awake() == 1`, `Busy()[1] == nil` and,
   with the root walked back into play during the walk home, `not Engaged(7)`. Add the three
   mutations above to `mutate.py` (slice 2 owns the file).

## What held (no finding)

- `CampBrain` matches every rule of "A — the crowd" exactly:
  - `Posts`: arc spacing, vertex rule, fire bearings and the yaw wrap;
  - `Sees`: band, distance, cone edge and the distance-0 case;
  - `InPlay`, apart from the corners above;
  - `Step`: one transition, the order, the held branch rebuilding `inPlay`, the leash clock and
    `striking`, home to rest only with every member at its post, the empty group;
  - `Release`, `Struck`, `Evades`, `Goal`, `AtPost`, `Shows`, `Problems`.
- A's four recorded deviations are as reported and safe:
  - the release step steps first, then releases, so a rise of 0 still shows;
  - the stop at half `homeTolerance`;
  - the `simTime` clock;
  - `table.clear` for the damage book.
- No stuck states:
  - **`fight`**: the leash can always fire. `striking` is only windup or attack (both end on the
    brain's clock), plus a charge, which `Carried` clears in the step its attack ends.
  - **`home`**: always reaches every post in the shipped layout. Posts of different groups are at
    least the sum of radii apart (eastGate 5.66, southWatch 5.66, fire chords ≥ 5.5). An idle
    fighter standing on a homeward post is pushed off for good, because it seeks nothing.
  - **Empty groups**: neither awake nor busy.
- No yield, raycast or per-body allocation in the camp step. Only a change of state allocates
  (`queueEvent`).
- `Damage` asks `Struck` after the gone and dead checks and before the guarded, plate and
  amount tests. An evading or out-of-play hit returns before any knock, stagger or book.
- No farm in Wave 1:
  - The **fence top** (4) is under the fodder lunge's `height` (5), the armoured arc's (6) and
    the brute lane's (5).
  - **Cover** is 3.5.
  - No ground lies off a corner, and no perch near camp A or B is inside both the band and the
    margin (`LookoutLedge` is 11 studs west of A's in-play rectangle).
  - Repeated first strikes in the rise window cost residents for good (no refills), so they pay
    nothing extra.
- `CrowdBrain`:
  - a resident in `home`, `rise` or `rest` never thinks;
  - `Commit` counts only striking minds, so a resident leaving the fight holds no turn;
  - `allowed` also reaches `chain`;
  - `land`, `ahead`, `inArena` and `runway` read the body's own floor.
- Floors and the codec:
  - `SetFloors` is refused with a body alive. WaveService's `clearField` runs `Clear()` first.
  - `aliveOn` moves only in `Spawn` and `noteGone`.
  - `ClearFloor` recalls the floor's impacts and leaves the other floors alone.
  - The codec appends `rest` 8 and `rise` 9 within 4 bits.
  - `tests.luau` differs only at the `BeginStep` call site.
- Every one of A's 36 mutations is registered in `mutate.py` and reads as caught by a named
  check (each traced by hand).

## For other slices (one line each)

- Slice 4 (data): `check_levels.py`'s `chaseMargin` gate must use `reach − √2 × radius` (Major 1).
  The shipped `chaseMargin` 3 then fails it for fodder (limit 2.66).
- Slice 2 (run): `rescueFallen` reads `Engaged` after the player has fallen out of the band
  (Minor 1); `mutate.py` takes Minor 2's three mutations.

Critical 0, Major 1, Minor 2
