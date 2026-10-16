# L1c fix-diff review (roblox-reviewer, 2026-10-16)

Range `2a58134..l1c-chief-clearing` (ef6fe6b): the fix round (2841862) and the margin ruling (f06458a).
Read against `code.md`, `data-tools.md`, `l1c-fix-round.md` and the two fix reports.

**Result: 0 Critical, 2 Major, 2 Minor.**

## Gates (read-only, on a `git archive HEAD` copy in the scratchpad)

| Gate | Result |
|---|---|
| `run_harness.py <copy> <main>\tools\bin\luau.exe` | PASS, 2,455 checks |
| `check_levels.py` | PASS |
| `check_stage_mirror.py --luau ...` | PASS |
| `mirror_mutants.py --only "L1c M3"` | 5 of 5 caught |
| `check_levels_mutants.py --luau ...` | MUTANTS: PASS (shipped green, 34 cases plus the m2 stage-mirror case as expected) |

## Major

### F1. `src/shared/WallClip.luau:56-61` (`holds`, the m1 height rule) with `CameraController.luau:765-776`: every late double jump inside the Chief's Clearing collapses the camera into the head

**What.** m1's fix counts a root as inside a locking rectangle only when `rootY - floor.y <= levels.triggerHeight` (30).
The rule is not limited to a root outside the camp. It also applies to a player who is fighting inside C.
- A standing root is 3 above the floor.
- After a jump (18) and a double jump (12), the root is at 33.
- From a 3.5-stud cover block it is at 36.5.
- With a Leap Smash cast from a jump, it reaches 31 to 43. `check_levels.camera_top` counts that lift itself.

Above 30 the rectangle does not hold the root, so the boom is cut against the grown rectangle. The pivot stands inside that rectangle,
so `entry` returns 0 for both the shoulder and the boom. The camera is then placed at the pivot, inside the character's head.

**Scenario.** It happens in every run, during the ambush and the Colossus fight:
1. A player double-jumps late in the rise, which is the normal way to jump a slam ring.
2. For about 0.35 s around the apex (about 0.5 s from cover), the view snaps from 11 studs behind to first person, then back.
3. Nothing smooths the boom (`position = shoulderPoint + boom.Unit * boomReach`).

**Why no gate catches it.** `tests_l1c.luau:93` asserts this exact behaviour: "inside on the flat but higher than `height` ... not
inside, cut". The case's own comment pictures only the gate band.

**Fix (pick one).**
- **(a) Recommended. A walled camp triggers, and releases the clip, up to its fence's top instead of `triggerHeight`.**
  - `StageFlow.triggered` uses `max(triggerHeight, fence height)` for a locking zone with a fence.
  - `RunFloor` carries that ceiling, and `WallClip.holds` reads it.
  - Mirror it in `sim_range` and `check_stage_mirror`.
  - `check_levels` asserts that the ceiling is over the highest root inside (33 + cover + ability lift).
  - This also closes F3.
- **(b) Client only.** Latch "held" per rectangle once the root is inside within the height, and keep it while X/Z stay inside.
  The ceiling then only refuses a root that arrives from outside at height.

Either way, replace the `tests_l1c.luau:93` case with one that has a root at 33 and at 43 over C's floor inside the rectangle: held,
nothing cut. Add a mutation for it.

### F2. `1_ForestRoad.json` C `gateSeconds: 0` with `WaveService.luau:1307-1316` (close → `moveFighters(zone.entry, zone)`) and `StageFlow.MustEnter` (`inner` = floor inset by `levels.closeInset` 2): the player who steps in is yanked about 10 studs forward every run

**What.** With a 0 s countdown, the close runs in the tick the server first sees the root inside the trigger rectangle (the floor
grown by the fence, z ≥ −27).
- That root is always in the fence band or the 2-stud inset strip: walking moves it 0.27 studs a frame, a dash 2.2.
- So `MustEnter` is always true for it.
- `MoveMember` then pivots it to `entry` at (313.5, −16), 10 to 11 studs ahead of where the server had it. On the client, which is
  ahead by the lag, the jump is still about 8 to 10 studs.
- `MoveMember` zeroes the velocity.
- The camera jumps with the root: 10 studs is under `COMBAT_CAMERA_SNAP_STUDS` 40, and no lag is armed.

With the 3 s countdown this never happened, because the player had walked 48 studs in before the close.

**Scenario.** Every run, at the reveal: walk through the north gate and you are popped forward 10 studs as the gate shuts and the
flanks rise. This hits requirement 2 ("stepping in shuts the gate") at the moment Ben will judge it.

**Fix (pick one).**
- **Data.** Move C's `entry` to just past the inset in the gate lane, about (313.5, −23.5). Then re-check what reads `entry`: the
  check_levels distances (Colossus 77.5 from the entry, spawns, posts at z −22.8 and 37+ studs aside), N's move, and the safe point.
- **Code.** At the close, move a fighter who stands in a gate's lane to the nearest point of `inner` (straight ahead, at most
  `closeInset + fenceThickness` plus a little), and keep `entry` for fighters elsewhere.

Add a harness case: the triggering root moves no more than about 3.5 studs at a 0 s close.

## Minor

### F3. `WallClip.luau:56-61` and `tools/check_levels.py:184, 2359-2365` (DOORWAY): m1 is only half fixed

**What remains.** At the top of a double jump the root is 30 to 33 above the floor, so nothing triggers: the server's `triggered` and
the client's `holds` both refuse it.
- The boom is now cut, but the camera then sits at the head.
- The head stands in the opening: in the 1-stud fence band, or a stud past the floor's edge.
- From there the eye sees both flanks along the inner wall. The posts at z −22.8 are about 3 studs in and fully in line.

**Scenario.** Jump, then double-jump at the line. At the apex, step 2 studs south and 2 back. Air control is instant, and the window
above 30 is about 0.35 s. The player lands outside, the camp is untriggered, and it can be repeated.

**Why no gate catches it.** `check_levels` exempts every eye in the doorway, including eyes inside the fenced rectangle, on "one more
step triggers". That is untrue above `triggerHeight`.

**Fix.** F1 (a). With the ceiling at the fence's top, any root in the band triggers and the exemption's premise holds at every height.

### F4. `WeaponService.luau:2634-2675` (`Strike`) and `:953-1003` (`chainFrom`): held residents still take the cap and seed chains

**What.** M2 drops the hit entry, so there is no BLOCKED, glint or ×N. But in `Strike`:
- every held candidate still uses a slot of `spec.cap`;
- it is still added to `seeds`, which makes `chainFrom` link to it and jump on from it;
- `fx.links` therefore names the hidden posts.

**Scenario.**
1. Cast Storm Coil (`targets` 2, chain 3) over GatehouseWallS onto the west posts.
2. For 4 s, the caster's client draws bolts and sparks from the coil to the held ambushers (`FeedbackController.drawAbilityLinks`).

Today the 64-stud walls hide the bolts from an outside eye, so this is not a visible leak. It is a hidden body taking part in a strike,
and the first fx change that draws over the walls would reveal it.

**Fix.** Pick one:
- Have `strike` return the verdict, and skip `seeds` and links for `"held"`.
- Drop held residents when gathering, through a `CrowdService` held query, so the cap goes to real bodies.

Add a harness case: a coil spec over held bodies produces no links.

## Verified, no finding

**C1.**
- The cut uses `rect.hx/hz + clip.margin`.
- `holds` keeps the true fenced rectangle.
- Shoulder and boom both go through `campReach`.
- The shake (0.35) is inside the 3.5 margin.
- `marginTests` would go red on a grown release or on a missing margin, because its "worst" scan compares against `min(back, clear)`.
- `check_levels` models the clip the same way: grown = fenced + `cameraClear`, eyes inside grown are their own camera, keep-outs are
  `cameraClear` − shake, and only doorway eyes are exempt.

**M1.**
- `SetCore("ResetButtonCallback", false)` is retried 60 × 0.5 s from `Start`, on its own thread.
- `CameraMaxZoomDistance` 16 equals `camera.maxZoom`, and a harness check holds them equal.
- The default camera now also gets the cap in `summary` and `ended`, where the field is already cleared.

**M2.**
- `"held"` is returned only for a held group.
- `StrikeTally` drops it as it drops `"gone"`.
- `WeaponService.strike` is the only consumer of the verdict, and the readout counts `tally.enemies`.

**M3: no loop, no skipped ambush.**
- `gate rearm` in the trigger tick needs a standing root (the trigger) and `fallen` at once, and `fallen` comes only from `RunLost`
  (everyone down), so it cannot repeat every frame.
- The trigger tick returns after the gate row. The next tick's fight row counts `AliveOn(C)` (the residents `WakeFloor` just woke), so
  the empty wave 1 holds until the ambush is dead.
- All three Skip entries go through `entered`.
- The phase broadcast comes after the batch, so no RunState carries a 0 s countdown.

**Mirrors.**
- Python's `to_gate`, the fall-through and `skip_into` match the Luau.
- `level_problems` refuses NaN, ∞, a negative value and a string, as Validate does.
- `check_stage_mirror` now requires every broken copy to be refused (`must_refuse`), and the two-sided maxAlive mutant is red.

**Data.**
- The margin ruling's posts, spacing, Normal 10 and Hard/Brutal 12 hold.
- The `lockedResidents` bands are per difficulty.
- The ambush bands have a 15 s floor.
- BALANCE records the Normal pay change from the Colossus raise (132,033).

## The list

- **Major F1** `WallClip.luau:56-61` (+ `tests_l1c.luau:93`): the m1 height rule also cuts for fighters inside C, so every late double
  jump or jump plus Leap Smash (root 33 to 43 over the floor) snaps the camera into the head for about 0.35 to 0.5 s, all through the
  Colossus fight. Fix: a walled camp triggers and releases up to its fence's top (StageFlow, RunFloor, WallClip, sim_range,
  check_levels), or a client latch once inside.
- **Major F2** C `gateSeconds 0` + `WaveService` close `moveFighters` + `MustEnter` (`closeInset` 2): the stepping-in root is always
  outside `inner`, so it is pivoted to `entry` (313.5, −16), about 10 studs ahead with its velocity zeroed, every run at the reveal.
  Fix: put C's entry just inside the inset (about z −23.5) or move gate-lane fighters to the nearest point of `inner`, plus a harness
  case.
- **Minor F3** `WallClip`/`check_levels` DOORWAY: at the double jump's apex (root over 30) the head stands in the opening, sees both
  flanks and triggers nothing. The exemption's "one more step triggers" is false up there. Fix: F1 (a).
- **Minor F4** `WeaponService.Strike`/`chainFrom`: held residents still take `cap` slots and seed chain links, so Storm Coil over the
  wall draws bolts to the hidden posts (hidden by the walls today). Fix: skip held in seeds/links, or drop them when gathering.
