# L1c second fix-diff review (roblox-reviewer, 2026-10-16)

Range `ef6fe6b..l1c-chief-clearing` (71fba13), read against `fix-diff.md` (F1–F4), `l1c-fix2.md`, the lead's
F2 ruling (code option a) and the two fix2 reports.

**Result: 0 Critical, 0 Major, 3 Minor.** F1–F4 are fixed.

## Gates (read-only, two `git archive 71fba13` copies in the scratchpad)

| Gate | Result |
|---|---|
| `run_harness.py <copy> <main>\tools\bin\luau.exe` | PASS, 2,489 checks |
| `mutate.py <copy> <luau> "l1c fix2"` | 20 run, 0 not caught |
| `check_levels.py` | PASS |
| `check_stage_mirror.py --luau ...` | PASS |
| `mirror_mutants.py --only "L1c"` | 12 of 12 caught |
| `check_levels_mutants.py --luau ...` | **FAIL**: one stale mutant (m1 below) |

## Minor

### m1. `tools/check_levels_mutants.py:235`: the gate is red at HEAD

**What.** The mutant "F1: sim_range's trigger asks triggerHeight again" looks for `<= above <= zone["ceiling"]`
exactly once. The code agent's `gate_nudge` (`sim_range.py:5751`) added a second copy beside the trigger
(`:8020`). The two agents worked in parallel, so the data report's "MUTANTS: PASS" came before that merge.
The result is `MUTANTS: FAIL (... the mutant is stale)`.

**Fix.** Anchor the mutant on `self.rules["triggerBelow"] <= above <= zone["ceiling"]`, which occurs only in
`LevelRun`.

### m2. `ForestRoad.json:215` (C `entry` z −23) with `WaveService.luau:1153` (nudge) and `ArenaService.MoveMember` (`SPAWN_CLEARANCE` 4): in co-op, the road player is placed onto the lane player

**Scenario.**
1. A walks through the north gate and triggers C. GateNudge puts A at (x_A, −24).
2. B is on the road in the gatehouse. B is not in a lane, so `MoveMember` pivots B to (313.5, −23) with its
   feet 4 above the floor, zeroes its velocity and writes `Placed`.
3. With A near the lane's centre line, which is where the route walks, B's feet land 1 stud from A, inside
   A's head and shoulders (A's root is at 3). Physics then pushes them apart and shoves A, the body the nudge
   was meant to leave moving.

Before this round both went to (313.5, −16) and stacked exactly, so this is not a regression. But −23 was set
only for the data option ("under 1 stud"), and the lead dropped that option for code (a).

**Fix.** Put C's `entry` back deeper, for example −16 (8 studs past the nudge line), or set it to one side of
the lane. Re-run `check_levels`, `sim_range --levels-only` and the BALANCE ambush rows. Separately, consider
spreading several `MoveMember` targets of one close (pre-existing: two road players still stack on the entry).

### m3. `StageFlow.luau:2432` (`GateNudge`, lanes only within the opening): a diagonal dash through the gate edge is yanked about 10 studs sideways

**Scenario.**
1. The server first sees a dashing root in the trigger rectangle. A dash moves about 2.2 studs a frame, and
   character replication arrives at 20–60 Hz, so a sample can land 3 to 4 studs further on.
2. A dash at 45° from the gatehouse turn's edge (x offset 7) clears the fence's end at x offset 9,
   z ≈ −25.5, and is first sampled in the inset strip beside the opening, at about (323.6, −24.4).
3. That point is outside `inner`, so MustEnter is true. It is outside every lane, so GateNudge returns nil.
4. `MoveMember` sends the root to the entry (313.5, −23), about 10 studs sideways. It zeroes the velocity,
   writes `Placed`, and the client drops its speed.

This is rare, but it is the F2 yank on the path a skilled player takes.

**Fix.** For a root inside the trigger rectangle (the fenced rectangle) and within the band, take the nearest
point of `inner`: clamp X and Z to `inner`, a move of at most 3 studs on one axis or 3√2 at a corner. Keep
`entry` only for roots outside the fenced rectangle. Mirror the change in `gate_nudge`. Add a harness case for
the strip beside the opening, and a mutation that drops the lane's depth test (none exists today, although the
"half a stud out on the road" case would catch it).

## Verified, no finding

**F1 / F3**
- `Ceiling` is 64 for C and 30 for every other camp. The trigger, `RunFloor.ceiling`, `CombatUIController`
  (copied and compared), `CameraController.SetFloors` and `WallClip.holds` all read the same band.
- The rectangle (floor plus `fenceThickness`) is the same on the client and the server.
- **No outside trigger.** The trigger rectangle outside the floor is the fence band. Its only open parts are
  the openings: north x 305.5–321.5, flanked by GatehouseWallW and GatehouseWallE (y 0–76), and east (TrailEnd,
  unreachable). Nobody stands on a wall top: a root there would be 67 over the floor, over the ceiling of 64.
- **No hole.** The highest reachable root in the fenced rectangle is 46.5 (cover 3.5 + 18 + 12 + 10 + 3,
  `check_levels`), 17.5 under 64. Enemy `launch` is 3. So every reachable root in the opening triggers, and
  the doorway exemption's "one more step triggers" holds at every height.
- The client releases the clip one lag window before the server's close. That is unchanged from the
  ground-level case already accepted.
- Checkpoints keep `triggerHeight`, which is intended.

**F2: nudge, PivotTo, no `Placed`, ForgetMotion**
- **Target.** The target is `inner`'s edge inside the opening's span, so it is never in the fence, the closed
  gate or the barrier (inner face at the floor edge). It is never off the floor.
- **No obstacle at the target.** The nearest solids are C's cover blocks at (340.5, 20) and (285.5, 34), and the
  posts are 37+ studs aside.
- **Height.** Height is kept, so a 43-high root falls inside.
- **Lag.** The client, ahead by lag, gets the server's absolute pivot. The snap is 3 studs minus the lead, and
  its stale X and Y are a lag's worth: the same class as `MoveMember`.
- **Swing slack.** ForgetMotion empties the ring, so the slack falls to the pad until 0.1 s of history exists.
  The claim is pulled back, never refused. `entered` stops the grace re-move even if a stale client packet
  briefly reverts the server's root into the band.
- **Two players.** A lane player and a road player are handled one by one (see m2). Two players in the lane
  are both nudged on their own X.

**F4: StrikePick against `ef6fe6b`, no held bodies**
- `Strike`:
  - The cap expression gives the same set for a cap of 0, NaN, ∞ or a fractional value. AbilityService already
    floors caps.
  - Crit, push, amount and order are unchanged.
  - The ray's `endPoint` condition is equivalent.
  - A `"gone"` or nil verdict still counts as landed and seeds, as before.
- Chain Gun (`resolveRanged`):
  - The limit and the `endPoint` are identical. Every hitscan pierce now passes over a held body, not only the
    Chain Gun's.
  - Held bodies are behind walls that `worldReach` stops, so this is moot in practice.
- `chainFrom`:
  - The first non-taken candidate is struck and linked, with the same push, damage and falloff.
  - Seeds are still added to `hit`. Held bodies stay out of `hit`, which is the cross-tick exclude set.

**Mirrors and checks.**
- `trigger_ceiling`, `gate_lanes` and `gate_nudge` match the Luau line for line.
- `check_stage_mirror` compares 12 Ceiling cases, 300 GateNudge cases (alongs, depths and rises including the
  edges) and the zone rows with `ceiling` and `lanes`.
- Every one of the 20 fix2 mutations is caught by a named check. The new mirror mutants are caught.

## The list

- **Minor m1** `tools/check_levels_mutants.py:235`: the stale mutant text matches twice (`sim_range.py:5751`
  and `:8020`), so `check_levels_mutants` is red at HEAD. Fix: anchor it on
  `self.rules["triggerBelow"] <= above <= zone["ceiling"]`.
- **Minor m2** `ForestRoad.json:215` with `WaveService.luau:1153` and `MoveMember`: in co-op the road player is
  placed at (313.5, −23), feet +4, 1 stud from where the lane player was nudged (x, −24), and shoves them.
  Fix: put the entry back deeper (for example −16) now that the data option is dropped, or off the lane's line.
- **Minor m3** `StageFlow.luau:2432` (`GateNudge`): a diagonal dash first sampled in the inset strip beside the
  opening is in no lane, so it is sent to the entry about 10 studs sideways with its velocity zeroed. Fix: clamp
  any root inside the fenced rectangle to `inner`, keep the entry for roots outside it, and mirror the change
  with a case and a mutation.
