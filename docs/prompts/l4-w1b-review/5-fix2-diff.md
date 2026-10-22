# L4 W1b review, second fix diff (`git diff 0489eef..c01348a`)

Reviewer: roblox-reviewer, 2026-10-22. Branch `l4-w1b-fix2` at c01348a, worktree `tycoon-p5c`. Read only: this
file is the only one written. Every probe ran on a `git archive c01348a` copy in my scratch folder
(`...\scratchpad\l4w1b-fix2\tree`), never in a worktree. The copy's own harness reads `HARNESS: PASS (4,185 checks)`.

**Count: 0 Critical, 0 Major, 3 Minor, 2 Suggestions.**

M1 is fixed. The three probes from the last review each lose the no-claim amount (8) with a claim that never
proves. A fuzz over 1,100 random queues finds no case where the claim changes what is lost, and the simulator
agrees with the Luau course for course.

## Minor

**m1. The simulator's G1 mirror is correct today, but its one gate line cannot tell the moment rules from the
release.**

- Where: `tools/sim_range.py:4686` (`fence_queues`) and `:4810-4827` (the gate line in `check_threat`).
- What is wrong:
  - The fence-dash line is the only gate on the mirror's G1 code (`hold`, `release`, `rule(at=)`, `hurt(at)`,
    `struck_by`). No gated run dashes unproven, and `mirror_mutants.py` covers check_stage_mirror, not ThreatRun.
  - Its three queues release everything in one frame, inside one knock window. On those queues, "from the moment"
    and "from the release" give the same answer.
  - Eight sim-side mutants were run through the gate line's own condition (`dash_fence_probe` plus the `expect`
    test). Seven survive:
    - `knock_until = t + ...`;
    - the knock window from `t`;
    - `rule(..., at=None)` in `release`;
    - `last_hurt = t`;
    - `down_until = t + ...`;
    - the `holds` loop in `hurt` deleted;
    - the release's `at < knock_until` check deleted.
  - Only "no queue behind" is caught.
- Proof that the mirror is right anyway: 300 random queues, run through the real VitalsService (harness) and
  through ThreatRun (`sim_x.py`), each with no claim and with a claim that never proves. The queues are 1 to 7
  arcs that hold the root, 45% of them knocking; knockIframes is 0.41 and a third of the queues start at low
  health.
  - Result: the landed, dodged and down counts agree on all 600 courses.
  - The cross-check is live. Three of the mutants above give 46 to 54 mismatches.
- Failure scenario: a later edit to the mirror dates a released knock from the release. The fence line stays
  green, and the BALANCE note "a dash into the fence loses what no dash loses" stops being true with no gate
  noticing. No balance number moves today, which is why this is Minor.
- Fix: add two queues to `fence_queues`:
  - the harness's fourth case, a knocking lunge at 0 and a plain one at 0.5 (both land with no dash; any "from
    the release" mutant voids the second);
  - one at low hp, where a held hit downs him, so `down_until` and `down_span` count.

  A knockIframes-0 variant would hold the `holds` loop and the release check. Then add the seven mutants to a
  sim mutant list, or prove them once and list them in BALANCE.

**m2. G2's warn handler is pinned nowhere. Flooding, silence and swallowing all pass.**

- Where: `src/combat/server/Services/WeaponService.luau:2148-2155` (`stepFailed`). `L4B_LINES` in
  `tools/crowd_harness/run_harness.py` has no `stepFailed` entry, and neither does `mutate.py`.
- What is wrong: the WeaponService side can only be held by text pins, because WeaponService does not load in the
  harness. G2's "once per message" and "warned at all" have none. Each of these reads `HARNESS: PASS (4,185)` on
  the copy:
  - `state.stepErrors[message] = true` deleted: every frame warns;
  - the guard made `if true then return end`: nothing is ever warned;
  - the `warn(...)` line deleted: errors are swallowed.
- Failure scenario: a refactor drops the note. A per-frame throw in `trackAir` then prints 60 tracebacks a second
  into Studio's Output for the rest of the session. The other direction is worse: a refactor drops the warn, and
  the throw that G2 contains becomes invisible. A dead dash proof or a Vitals half that throws every frame then
  shows no symptom at all, which is the m1 failure the round set out to stop.
- Fix: pin `stepFailed`'s body as one text block:

  ```
  if state.stepErrors[message] then
  	return
  end
  state.stepErrors[message] = true
  warn(debug.traceback(...))
  ```

  Then add the three mutants above to `L4B_FIX2_MUTATIONS`.

**m3. A held blow is erased when the boss room clears, so a dash that never proves can win a boss race that no
dash loses.**

- Where:
  - `src/combat/server/Services/VitalsService.luau:1105`: `ClearThreats` empties every `waiting` list;
  - `src/combat/server/Services/WaveService.luau:1409-1412`: the boss room's `clear` calls it.
  - `onGone` (`VitalsService.luau:820-834`) keeps `waiting` for the stated reason, "its moment came before". The
    `clear` that follows the boss's death then drops those entries anyway.
- What is wrong:
  - A decision in `waiting` is one whose moment has come. With no claim it would already have landed.
  - With a pending claim, anything that resolves the run between the moment and the release judges a player who
    is still standing. That includes the boss's death, the `clear`, and the player's own attacks, which `IsDown`
    only refuses once the down is applied.
  - F1 had this for the hits its claim's window covered. G1 widens it to every later hit queued behind, so every
    impact decided up to the lapse, about 0.45 s after the request.
  - The harness pins the drop as intended ("ClearThreats drops a decision that waits").
- Failure scenario: solo, Hard, the Colossus at a sliver of health.
  - The player dashes into the boss room's wall (never proven) as its slam lands for more than his health. The
    slam is held (moment 0.1 s).
  - His next swing kills the Colossus at 0.3 s. `clear` runs `ClearThreats`, and the down never lands. The run is
    won, and the star is paid.
  - With no dash, he is down at 0.1 s, cannot swing, and the solo run is lost.
  - A request-only forger, a client that only sends dash requests (cooldown 0.64 s, lapse 0.45 s), has a pending
    claim 70% of the time, so every boss race of his gets the same grace.
- Fix, either:
  - (a) Accept it and record it as limit 6 beside luau-a-2's five, and in contract §10 ("effects leave late, and
    the run's state machine reads them late: a blow held at the boss's death is dropped by its clear").
  - (b) Hold the boss room's `clear` while any fighter has a waiting decision. That wait is at most 0.45 s, through
    a `VitalsService.HasWaiting(player)`. The waiting then resolve first: a down lands before the clear, and a
    proven dash still voids.

  Keeping `waiting` through ClearThreats alone is not enough. A down released after the clear meets a run that is
  already won.

## Suggestions

- **s1. A persistent throw inside VitalsService.Step re-lands every earlier decision every frame, silently.**
  - Where: `release` compacts its list only after the loop (`VitalsService.luau:573`). `settle` does the same with
    `pending` (`:609`).
  - A throw in `decide` for entry k leaves entries 1 to k-1 in the list. They have already been ruled. The next
    frame decides them again, and `flush` never runs, so the effects never leave.
  - Probe: three held hits, and the second one's `dashClaim` call throws from the lapse on. 13 frames throw, health
    goes 130 -> 26 (13 x 8), and **0** hurt effects are sent.
  - The class predates G1 in `settle`. G2 now keeps the server running through it, but it does not contain it.
  - Fix: remove an entry before deciding it (in `release`, take the front and put it back on a wait; in `settle`,
    clear each slot as it is read), or `xpcall` per entry.
- **s2. A throw for one player in `trackAir` starves the players after him.**
  - Where: `WeaponService.luau:2036`. G2 wraps the whole loop (`:2162`), not each shooter.
  - One body that throws every frame (for example a raycast on a part the level lacks) stops the ring samples and
    dash proofs of every shooter after it in `pairs` order, and that order is stable.
  - Those players' claims never prove, so every dash of theirs lands its hits at the lapse. Their slam, air-swing
    and slack samples go stale too.
  - Fix: `xpcall` the per-shooter body with the same `stepFailed`, or split the loop body into a local function
    and wrap it.

## Checked and clean

- **M1 really fixed.**
  - The review's knock probe on the copy, with no claim and with a claim that never proves: S1 `ld` / `ld`, S1b
    `ld` / `ld`, S2 `ld` / `ld`. Each loses 8 both ways (was 16).
  - Fuzz 1: 400 queues of arcs, with knocks, low-health downs, ping 0.05 or 0.15, and a second forged claim at
    0.64. Same loss and pattern in 400 of 400.
  - Fuzz 2: 400 queues with rings (crowd steps every 4th frame), knockIframes 0.4, 0, 0.05 and 0.15, and repeated
    claims. A forged claim against no claim matched in 400 of 400, and 250 of them held something. An honest dash
    (proven 0.02-0.15 s late) against the pre-L4 window opened at the request also matched in 400 of 400.
  - Fuzz 2 is live: the mutant "a released knock voids nothing waiting behind it" makes it read 4 worse.
- **The queue never hangs, starves or reorders.**
  - Every `waiting` entry has a `hold`.
  - `decide` keeps a held entry only on `not voided and awaitsDash`, which ends at the claim's lapse. One claim at
    a time (cooldown 0.64 > lapse 0.45), and DashProof.Step clears the claim before Vitals decides. So the whole
    list releases in the frame the claim resolves, and a new claim cannot extend it: entries join only while the
    list is non-empty.
  - If `trackAir` throws, `awaitsDash`'s own `now <= lapseAt` still ends the hold.
  - Order: entries join at the frame they fall due. A crowd-step contact appended before or after that frame's
    queue entries carries its own moment, which matches its place in the list. Release walks first to last.
  - Review mutants caught: a lone entry never released, a held entry waiting behind itself, no compaction, no
    refresh at release, a contact or `await` queued at its impact, onGone dropping `waiting`, the humanoid check
    dropped.
  - Equivalent: `lastHurtAt` without `math.max` (StandUp is the only later writer while a list waits, and nothing
    in the game calls it then).
- **Clocks at the moment.**
  - `rule(at, now)` dates `lastHurtAt`, `downFrom`, `downUntil`, `upAt` (`- (now - at)`), the knock's i-frames
    (`grantIframes(..., at)` -> `DashProof.Open(min(from, now))`) and `knockUntil` from `at`.
  - `struckBy` uses the queue time, and released knocks open from the past: DashProof.Open's merge and slot cases
    hold for a `from` before the latest window.
  - The G1 tests prove the down's upAt and get-up, regen, StandUp inside a released down, and both halves of
    ruling 18 at knockIframes 0.
  - My R1-R3 (`now < knockUntil`, `rule(now, now)`, `knockUntil = now + ...`) are caught.
- **No leak.**
  - RemovePlayer drops the record with its list, and `settle` walks `vitalsByPlayer` only.
  - A down drops the rest of the walk (`vitals.down`), and a downed player queues nothing.
  - A respawn drops entries on `hold.humanoid`, in the next frame's release.
  - ClearThreats empties every list, and a level change runs through `clearField`, `backToLobby` or
    `WaveService.Reset`.
  - StandUp is reached in the game only for downed players or right before `clearField`, so StandUp-then-release
    (limit 5) is harness-only.
- **G2.**
  - Three sequential `xpcall`s in the F1 order. Nothing yields: Step's `flush` -> FireClient and `onDown` ->
    `advance` don't, and neither does stepRest.
  - Luau `xpcall` passes the extra arguments.
  - The key is `tostring(problem)`, which in practice is the `file:line: message` string. The only `error(` in the
    combat server and shared code is RunRegistry's constant lever message, so the set stays small.
- **pendingDash s2.** Behaviour-equivalent (Pending answers 0, 0, 0 for a nil claim). A missing-config warning now
  first appears at a dash rather than at the first enemy decision.
- **G3 and s1 pins live:**
  - the review's `Connect(function() end)` (startConnects 0) and early return (stepHead 0);
  - an empty function handed to step's Vitals xpcall (4 pins);
  - `total = math.max(...)` (mentorTotal);
  - the bonus guard deleted (mentorNoBonus, bonusGuardThenPay).

  `WEAPON_STEP_BODY` (`^local function step\(`) does not match `stepRest` or `stepFailed`. A second `local function
  step` before Start passes the pins, but selene warns `shadowing`.
- **mutate.py.** The stale check, exec'd up to its baseline on the copy, reads 1,795 entries, 0 stale.
- **The simulator mirrors G1 as built.**
  - `release`'s order: refresh windows, drop down or volley, `at < knock_until`, break on `awaits`.
  - The walk's hold condition `self.holds or (...)`, with `shielded` already carrying `t < knock_until`, and the
    sweep's three contacts.
  - `hurt(at)`, `struck_by` with field 12, `LevelRun.hurt`'s down span.
  - The 600-course cross-check in m1.
- **Code rules and gates on the copy:**
  - `--!strict` kept; no `wait`, `spawn`, `delay`, `_G` or parent argument; no numeric constant added.
  - stylua `--check` and selene on both Luau files: clean.
  - luau-lsp with the combat sourcemap: 0 diagnostics, and a planted type error is reported, so the run was live.
  - `check_compile.py`: PASS, 176 files, WeaponService 104 top-level locals.
