# L1b Wave 2 fix-diff review (f40509a..cdad4f4)

One reviewer, read-only, brief `docs/prompts/l1b-w2-fix-diff-review.md`. I read every changed
source file in the diff, the fix-round list, the lead's routing and the five fixers' reports, and
the four review files the fixes answer. The probes ran the real `SwingGate.luau` at cdad4f4 under
`tycoon\tools\bin\luau.exe` from the session scratchpad. Nothing was written in the worktree
except this file. The harness and `mutate.py` were not run. Every one of the 619 mutation texts
in `mutate.py` occurs exactly once in its file (counted by exec'ing `mutate.py` up to
`def harness(`).

## Major

### M1. The client takes the "landing ahead" branch too, so one jump gets two swings and the next hop gets none
`src/shared/SwingGate.luau:197-208` (`Judge`), called with `CONST.LAG_SECONDS` 0 from
`src/combat/client/Controllers/AirSwing.luau:41` and `:163-169`.

- **What the code does.** `Judge`'s "ahead" branch has no lag guard. Its test is
  `state.lowest <= state.fallSpeed * (TURN_WINDOW_SECONDS + lag)`. With lag 0 on the client,
  that still allows any airborne second swing in the last `fallSpeed x 0.1` of every fall:
  about 7 studs, or the last ~70 ms, of an 18-stud jump.
- **What it does next.** The branch sets `ahead`. Then the client's own touchdown, a sample
  `land()` reads, consumes `ahead` and does not clear `used`.
- **The comment is wrong.** Lines 199-201 say "an honest client's own gate refuses the second,
  so only the bounce is ever sent". The same claim is in fix-A.md ("Lenient only on the
  server"). The client's gate does not refuse it.
- **Scenario 1, a single jump** (probe on the real module, 60 Hz samples of 240 Hz physics):
  1. Jump. Swing at the apex (t 0.437): allowed.
  2. Swing again at t 0.804, 3.8 studs up, falling at 74 studs/s: **allowed, airborne**. That is
     two swings in one jump.
  3. Land at 0.857 and walk.
  4. Jump at 1.5 and swing at 1.904, at the apex: **refused**. The client drops it, so the swing
     never comes out.

  Without step 2, that last swing is allowed.
- **Scenario 2, the checklist's step 2** ("click as fast as you can, also holding Space"): held
  Space with a melee swing due every 0.25 / 0.35 / 0.5 s, 20 phases, hops 2-9.
  - Two swings: 67 / 49 / 35 of 160 hops.
  - **No swing at all:** 56 / 38 / 30 of 160 hops.

  Those are exactly the step's two "Bug:" lines, "two or three swings in one jump" and "no swing
  at all on a later hop". Ben would report this step as a failure.
- **The server can also disagree.** I simulated the server's copy at 20 Hz trailing the claim
  by an interpolation buffer beyond `lag - one-way`:
  - buffer 0.08 s, one-way 0.03 s, lag 0.08: 30 of 659 client-sent swings refused ("a swing
    that shows and then vanishes");
  - with the fix below: 0 of 644.
- **Why no gate caught it.** `W2A.run` (`tests_l1b_w2_crowd.luau:337`) swings only at the first
  sample past each apex, so no case swings late in a fall with lag 0. The lagged cases (`:450`,
  `:453`) all use lag > 0.
- **Fix.** Let the ahead branch act only on a trailing copy: `if lagSeconds > 0 and airborne and
  state.used and ...`, or have the client skip it. The client's own touchdown then clears `used`
  as an ordinary landing.
  - On the same probes this gives 0 hops without a swing.
  - The server's lenience for a swing sent just after a bounce stays (the 0.15 / 0.3 s cases).

  Add a harness case: lag 0, an apex swing, a swing 4 studs above the band while falling, then a
  touchdown, a walk and a new jump. The late swing must be refused and the new jump's apex swing
  allowed. Pair it with the mutation that deletes the guard. Correct the comment and fix-A.md.

## Minor

### m1. A double jump 6-7 studs up is a landing for the client and not for the server's 20 Hz copy
`src/shared/SwingGate.luau:169-176` (the turn rule, the same `TURN_WINDOW_SECONDS` on both
sides).

- **Why the two sides differ.** The client's lowest sample of a fall is within one 60 Hz frame
  of the true lowest. The server's copy, replicated at 20 Hz, can read up to `v / 20` higher.
  So the same double jump can sit inside the client's reach and outside the server's.
- **Probe:** a double jump into 12 studs, the client's own physics against a 20 Hz copy at 20
  phases.

  | Root height over standing | Client clears | Server clears |
  |---|---|---|
  | 6.0 | 20 | 9 |
  | 6.5 | 20 | 1 |
  | 7.0 | 15 | 0 |

- **Failure.**
  1. Swing in the jump.
  2. Double jump about 6.5 studs up.
  3. Swing again in the double jump's air.

  The client allows and draws the swing. The server's copy has already turned (`falling` is
  false), so `Judge`'s ahead branch does not apply, and the server refuses the swing. Below 5.5
  and above 7.5 both sides agree.
- **Fix.** Make the client's window stricter than the server's by the server's sampling step:
  pass the window into `Observe` (client 0.05 s, server 0.1 s). A held-Space bounce still clears
  on the client, because its lowest sample is within `v / 60`.

### m2. `StageFlow.TentOwesRouse` is a new pure rule the mirror does not compare
`tools/check_stage_mirror.py:120` (`NEEDED`), against `src/combat/server/Services/StageFlow.luau:1877`
and `tools/sim_range.py:5923-5930`.

- **What is missing.** `TentOwesRouse` is mirrored by `sim_range.tent_owes_rouse`, but it is not
  in `NEEDED`. No `check_stage_mirror` case compares the two.
- **A second divergence.** The sim's `group_up` reads the live brain state. The server reads
  `run.awakeGroups`, which is the last drained GroupEvent. `campStep` writes the event and
  `tickTents` reads `awakeGroups` a tick later, so the two can disagree for one tick after a
  rise.
- **Today it is harmless:** a one-line rule, with its own harness cases and two mutations. This is
  the "pure query the mirror does not compare drifts" pattern from Wave 1.
- **Fix.** Add `TentOwesRouse` to `NEEDED` with its four answers as cases. Note in `group_up`'s
  docstring that the server's answer trails by the drain.

## Checked and holding

- **A-1, the bunny hop, the lip and the get-up.**
  - Every Heartbeat, the server (`trackAir`) and the client (`AirSwing.sample`) feed `Observe`
    the same quantities: the root's Y, its vertical velocity, the 5-ray footprint and the down
    state. Both use the same `ProbePoint`, lift, depth, `Exclude` of every character and
    `RespectCanCollide`.
  - The client's `MovementController.IsDown` is the server's down, as relayed by
    `VitalsController`, not a knock. It is set late, and both sides still clear.
  - The `StateChanged` → `Landed` clear is gone.
  - Apex-only swings are never refused: 0 refused at copy delays of 0.03 to 0.2 s, 20 Hz
    replication, and every swing rate.
  - A down clears on both sides.
  - A new character resets: `resetAir` on the server, `localRig` → `Landed` on the client.
- **A-2.** The patroller now walks before it freezes, and the case reads `idle` from the live
  body. The reviewer's mutation is in `mutate.py` and matches once.
- **A-3.** `SeparationCells` counts work, not time, so the case is deterministic.
- **The `resting` re-announce.**
  - It is queued in `queueEvent` only on a change to or from `rest`, and never through
    `pendingSpawnSet`.
  - The flush skips removed, dead (`deadAt`) and still-pending ids, and sends removes first.
  - A body removed in the step is not re-announced, and keeps its `CrowdRemove`.
  - **A dead body cannot come back on a client.** The only client-side deaths are the server's
    `dead` state and strike reactions, both after `deadAt` is set. The flush follows the
    simulate in the same Heartbeat, with no remote handler in between.
  - On the client, the re-announce of a drawn body keeps its motion: `spawnEntity`'s alive
    branch returns early, and `resting` is written afterwards.
  - Dormant groups read resting. A late joiner's sync calls `refreshInfo`, so it carries
    `resting`.
- **Rising tent bodies.**
  - The door is on the line from the marker to the post, the body's radius past the wall, never
    past the post. `check_levels` keeps ring posts clear of the marker.
  - `rises` is set only with `from`, and cleared after the first `fireAll`, which serializes at
    the call. The test copies values at the time, so it avoids the by-reference stub trap.
  - The rise is drawn only at the first sample, so a late joiner and a re-announce show the body
    standing.
  - It can be hit while rising (a 0.45 s cosmetic rise), exactly as a boss's summons.
- **The rouse rules.**
  - `TentRouse` needs the group's in-play set from this step's `Step`. That is current, because
    a tent body is added to `group.bodies` before the step, so `Step` does not take its
    empty-group early return.
  - From `home`, the event names the state it left: no re-announce, no "!", and `awakeGroups`
    is set.
  - JoinIn never returns a homeward group, so its hard-coded `"rest"` is right.
  - **No camp gets stuck.** With the residents dead and nobody in play, tent bodies still come
    out (`TentActive`), walk to their posts and rest, and sight wakes them when the player
    returns.
  - The owed debt ends when the group is up or the camp is quiet.
  - B-1 appends to the cloned `awakeGroups` list.
- **B-2 and E-1 to E-3.**
  - Every difficulty is checked, told once, highest rank first, the same in Luau and Python.
  - The new "only Normal pushes off" refusal is refused by both sides.
  - The C tent's move is gated over every resident post and patrol loop.
  - `mirror_mutants.py` runs on a temporary copy and reports STALE texts.
- **The range sets and the boss room.**
  - Range bodies carry no camp floor, so `CampAim` takes them.
  - `CrowdSpawnInfo.resting` and `rises` are nil there.
  - The boss room's held group reads resting and is re-announced at its release. The `gate`
    phase refuses first in `CampAim`.

Critical 0, Major 1, Minor 2
