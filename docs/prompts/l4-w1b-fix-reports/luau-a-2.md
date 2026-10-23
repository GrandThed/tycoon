# L4 W1b fix round 2 — luau-engineer A (G1, G2, s2, G3's lines)

Worktree `tycoon-p5c`, branch `l4-w1b-fix2`, nothing committed. Rulings: `docs/prompts/l4-w1b-fix2.md`; finding M1:
`docs/prompts/l4-w1b-review/4-fix-diff.md`.

## Files changed

- `src/combat/server/Services/VitalsService.luau`: G1.
- `src/combat/server/Services/WeaponService.luau`: G2, s2, and `GrantIframes` takes an optional `from` (G1).
- `tools/crowd_harness/tests_l4b.luau`: the reversed pin, a new group "(g) knocks among held hits (G1)" (16 checks),
  and the claim hook honours `from`.
- `DashProof.luau`: unchanged.

## Contracts (signatures)

- `VitalsService.Hooks.grantIframes: (player: Player, seconds: number, from: number?) -> ()`. `from` defaults to now.
- `WeaponService.GrantIframes(player: Player, seconds: number, from: number?): ()`. It opens
  `[math.min(from or now, now), + seconds)`. Existing callers (AbilityService, WaveService, getUp, StandUp) pass no
  `from` and are unchanged. tests.luau's fake hook ignores `from`, which is right: no decision ever waits there.
- New VitalsService state:
  - `Vitals.waiting: { Pending }`
  - `Hold.at: number`
  - `Pending.queuedAt: number`
  - local `struckBy(other, at)`
  - local `release(config, vitals, now)`
  - `rule(config, vitals, strike, held, voided, position, humanoid, at, now)`
- New WeaponService state: `state.stepErrors`, local `stepRest(now, deltaTime)` and local `stepFailed(problem)`.

## G1 as built (what the simulator mirrors)

1. **Moments.** A decision's moment is `now` of the frame it is first due. For a travelling contact it is `now` of
   the crowd step that found it.
   - A decision that must wait gets `hold = { at = moment, inShape, position, humanoid }`. The shape verdict comes
     from that moment.
   - It moves out of `pending` into its player's `waiting` list, in the order it began to wait. That is (moment,
     queue order).
2. **When a decision waits.**
   - It waits when a pending claim would cover it (F1, unchanged).
   - It also waits when its player's `waiting` list is not empty at its first try, whatever the claim covers. A
     travelling contact waits the same way: it is held, not voided, and the list is not empty or the claim
     covers it.
   - ThreatField hears "dodged".
3. **Each frame, VitalsService.Step.** Get-ups and regen, then `settle`:
   - **Phase A, `release`, per player:** walk `waiting` from the first entry.
     - Refresh `covered` over the entry's whole span, `[strike.at, decideAt]`.
     - Decide it as of `at = hold.at`. It is dropped if the player is gone, down or was down, ruled out, already
       answered by its volley, has no body, or has a new body.
     - Then `if at < knockUntil then covered = true`.
     - If it is not covered and the claim still covers it (`now <= lapse`), stop: it and the rest stay.
     - Otherwise `rule(at, now)`.
   - **Phase B, the queue, as before:** a first-due entry joins `waiting` (step 2) or is decided now.
4. **`rule` at moment `at`** (the effect leaves `now`):
   - `lastHurtAt = max(lastHurtAt, at)`.
   - A down: `downFrom = at`. In the range, `downUntil = at + downSeconds` and
     `upAt = serverNow + downSeconds - (now - at)`.
   - A knock: i-frames `[at, at + knockIframes)` through `grantIframes(..., at)`, and `knockUntil = at + knockIframes`.
     It voids every entry of the player in `pending` or `waiting` that `struckBy(other, at)`: `strike.at <= at` and
     `queuedAt <= at`.
   - `queuedAt` is when the entry joined the queue: the raising step (the throw, for a lob), or the judging step
     for a travelling contact.
5. **Clearing.** `ClearThreats` empties every `waiting` list, `onGone` leaves them alone, and `RemovePlayer` drops
   them with the record.

**Rulings I took inside G1:**

- **Regen and the down run from the moment too, not only rules 6 and 18.** A delay counted from the release would cost
  more than not dashing: regen up to 0.45 s later, a get-up 0.45 s later.
- **An aimed miss is never queued** (F1's accepted ruling). A voided contact is answered at once as well, because it
  lands nothing.

## Verification

- **Reviewer's knock probe** (`.../scratchpad/l4w1b-fix/knock_probe.luau`, appended to a scratch copy). With a claim
  that never proves, each queue now loses exactly the no-claim amount:
  - S1 `0.467:landed 0.467:dodged` (was 16).
  - S1b, the same.
  - S2 `0.467:landed 0.467:dodged` (was 16).
- **Harness on this worktree:** `FAIL (4 of 4,177)`. The 4 are the designer's WeaponService text pins: `grantOpens`,
  `stepVitals`, `vitalsStepCalls`, `frameOrder`. With the pin edits below, a scratch copy reads `HARNESS: PASS
  (4,181 checks)`.
- **New G1 checks:**
  - the three review queues;
  - a hit after the released knock's window;
  - a ring contact waiting behind a knock;
  - a late-raised hit at knockIframes 0.05 and at 0.3;
  - three cases at knockIframes 0 (ruling 18's loop, `queuedAt` for queued and for travelling entries);
  - the down's get-up and upAt;
  - StandUp inside a released down;
  - regen from the moment;
  - ClearThreats;
  - an honest late proof (the held knock dodged, the later hit lands at its own moment, as pre-L4).
- **Mutants, on scratch copies of this tree:**
  - all 21 G1 mutants are caught;
  - all 15 VitalsService re-aims below are caught;
  - with the prototype pins, all 10 WeaponService mutants are caught (G2, both of the reviewer's G3 probes, and the
    3 re-aims).
  - Four G1 mutants were equivalent at knockIframes 0.4 until the knockIframes-0 and StandUp cases were added. At
    0.4 the knock's window already voids everything ruling 18's loop would: keep those cases.
- **Static checks:**
  - `stylua --check` and selene on the three Luau files: clean.
  - luau-lsp on both sourcemaps (written to scratch): 0 diagnostics. A planted error was reported, so the run was live.
  - `py tools/check_compile.py`: PASS, 176 files.
  - G2 semantics checked under luau.exe: `xpcall(f, handler, args...)` keeps the order, a throw does not stop the
    later parts, and each message is warned once.

## Known limits (for the lead)

1. **An aimed miss judged while the player's decisions wait is answered against the knock state as it stands.**
   - A held knock that has not been released cannot void it, so the attack stays live for them.
   - With no claim, that knock would have made it a dodge, and the attack would be done with them.
   - A later contact can then land after the knock's window. Narrow: it needs an unproven claim, a held knocking hit,
     and a ring, charge or shot aimed at them that they outrun by about 0.4 s.
   - Closing it means holding aimed misses too, which gives "done" where no claim would leave the attack live. I would
     leave it.
2. **Regen ticks during a hold**, because `lastHurtAt` is the older value until the release. That is up to 0.45 s ×
   regenPerSecond in the player's favour.
3. **A contact queued behind a held one answers "dodged"**, so a shot flies on past them even if it lands from the
   queue. This is the same as F1's accepted ruling for held contacts.
4. **The released knock's push leaves at the release, while its i-frames run from the moment.**
   - The protected air time after the client's throw is shorter by (release − moment).
   - Hits in that span land exactly as they would with no claim.
5. **StandUp (a lever) between a moment and its release.** The released knock's `knockUntil` overwrites StandUp's
   reset. That gives more protection than no claim.

## For the other owners

### Designer: run_harness.py pins (verified on a scratch copy; then PASS, 4,181)

- **stepVitals.**
  - Old: `"stepVitals": (WEAPON_SERVICE, WEAPON_STEP_BODY, "lines", "\tVitalsService.Step(deltaTime)"),`
  - New: `"stepVitals": (WEAPON_SERVICE, WEAPON_STEP_BODY, "lines", "\txpcall(VitalsService.Step, stepFailed, deltaTime)"),`
- **vitalsStepCalls.**
  - Old: `"vitalsStepCalls": (WEAPON_SERVICE, None, "text", "VitalsService.Step("),`
  - New: `"vitalsStepCalls": (WEAPON_SERVICE, None, "text", "VitalsService.Step"),` (once in code).
- **grantOpens.**
  - Old text: `"\tDashProof.Open(shooter, now, seconds)\n\tshowIframes(shooter, now)\n"`
  - New text: `"\tDashProof.Open(shooter, math.min(from or now, now), seconds)\n\tshowIframes(shooter, now)\n"`
- **frameOrder** (L4B_ORDER).
  - Old: `("trackAir(now, deltaTime)", "VitalsService.Step(deltaTime)")`
  - New: `("xpcall(trackAir, stepFailed, now, deltaTime)", "xpcall(VitalsService.Step, stepFailed, deltaTime)")`
- **G3, new L4B_LINES.**
  - `"startConnects": (WEAPON_SERVICE, WEAPON_START_BODY, "lines", "\tRunService.Heartbeat:Connect(step)"),`
  - `"stepHead": (WEAPON_SERVICE, WEAPON_STEP_BODY, "text", "local function step(deltaTime: number): ()\n\tlocal now = os.clock()\n\txpcall(trackAir, stepFailed, now, deltaTime)\n\txpcall(VitalsService.Step, stepFailed, deltaTime)\n"),`
  - `"stepRest": (WEAPON_SERVICE, WEAPON_STEP_BODY, "lines", "\txpcall(stepRest, stepFailed, now, deltaTime)"),`
- **G2, new L4B_ORDER.**
  - `"restLast": (WEAPON_SERVICE, WEAPON_STEP_BODY, "xpcall(VitalsService.Step, stepFailed, deltaTime)", "xpcall(stepRest, stepFailed, now, deltaTime)"),`
- **tests_l3_w2.luau L4BP.**
  - `vitalsStepCalls = { 1, "VitalsService.Step is named once" },`
  - `startConnects = { 1, "Start connects step to the Heartbeat (G3)" },`
  - `stepHead = { 1, "step opens with the clock, then the proofs, then VitalsService (G3)" },`
  - `stepRest = { 1, "step runs the rest under xpcall (G2)" },`
  - In the order table: `restLast = "step: the rest after VitalsService (G2)",`
  - Optional (s2, the guard is behaviourally equivalent): pin `"\tif shooter == nil or shooter.dashClaimAt == nil then"`
    as whole lines in `PENDING_DASH_BODY`. `pendingClaim`'s return line is unchanged.
- **G3's whole lines.** `step` has no comments inside, so the head block is exact. The Start line is unchanged.

```lua
local function step(deltaTime: number): ()
	local now = os.clock()
	xpcall(trackAir, stepFailed, now, deltaTime)
	xpcall(VitalsService.Step, stepFailed, deltaTime)
	xpcall(stepRest, stepFailed, now, deltaTime)
end
```

```lua
	RunService.Heartbeat:Connect(step)
```

### Designer: mutate.py, 17 stale entries (same label, new texts; all checked caught or text-pinned)

| Label | Old | New |
|---|---|---|
| `18: no knock window at the decision` | `'\tif at < vitals.knockUntil then\n\t\tentry.covered = true\n\tend\n'` | `''` |
| `18: hits waiting at the knock not voided` | `'\t\t\tif other.vitals == vitals and struckBy(other, at) then\n\t\t\t\tother.covered = true\n'` | `'\t\t\tif other.vitals == vitals and struckBy(other, at) then\n\t\t\t\tother.covered = other.covered\n'` |
| `lob: a knock voids one still in the air` | `'return other.strike.at <= at and other.queuedAt <= at'` | `'return other.queuedAt <= at'` |
| `boss: decisions still waiting are kept` | `'if not ids[entry.strike.bodyId] then'` | `'if true then'` |
| `l4b f1: decide never holds` | `'\t\tor (not voided and awaitsDash(player, strike.at, entry.decideAt, now))\n'` | `'\t\tor false\n'` |
| `l4b f1: a held hit judged by a later knock` | `'\tif at < vitals.knockUntil then\n'` | `'\tif now < vitals.knockUntil then\n'` |
| `l4b f1: a knock voids a held hit` (the reversed pin: a later decision lands out of turn) | `'\t\t(hold == nil and #vitals.waiting > 0)\n\t\tor (not voided'` | `'\t\tfalse\n\t\tor (not voided'` |
| `l4b f1: a striker's death drops a held hit` | `'\tThreatField.Drop(ids, raise)\n'` | `'\tfor _, vitals in vitalsByPlayer do\n\t\ttable.clear(vitals.waiting)\n\tend\n\tThreatField.Drop(ids, raise)\n'` |
| `l4b f1: an aimed miss is held` | `'\t\theld\n\t\tand not voided\n\t\tand (#vitals.waiting > 0 or awaitsDash('` | `'\t\tnot voided\n\t\tand (#vitals.waiting > 0 or awaitsDash('` |
| `l4b f1: what travels is never held` | `'\t\tand (#vitals.waiting > 0 or awaitsDash(player, impactAt, limit, now))\n'` | `'\t\tand false\n'` |
| `l4b f1: a held shot is stopped on them` | `'\t\ttable.insert(vitals.waiting, entry)\n\t\treturn "dodged"\n'` | `'\t\ttable.insert(vitals.waiting, entry)\n\t\treturn "landed"\n'` |
| `l4b f1: settle drops a held entry` | `'\t\telseif decide(config, entry, now) then\n\t\t\ttable.insert(entry.vitals.waiting, entry)\n'` | `'\t\telse\n\t\t\tdecide(config, entry, now)\n'` |
| `l4b f1: a held entry judged again at the release` | `'\t\theld, position, at = hold.inShape, hold.position, hold.at\n'` | `'\t\theld, position, at = inPlan(strike, position), position, hold.at\n'` |
| `l4b f1: a held hit pushed from the live root` | `'\t\theld, position, at = hold.inShape, hold.position, hold.at\n'` | `'\t\theld, at = hold.inShape, hold.at\n'` |
| `l4b f1: VitalsService decides before the proofs` (WEAPON) | `'\txpcall(trackAir, stepFailed, now, deltaTime)\n\txpcall(VitalsService.Step, stepFailed, deltaTime)\n'` | `'\txpcall(VitalsService.Step, stepFailed, deltaTime)\n\txpcall(trackAir, stepFailed, now, deltaTime)\n'` |
| `l4b f1: VitalsService never stepped` (WEAPON) | `'\txpcall(VitalsService.Step, stepFailed, deltaTime)\n'` | `''` |
| `l4b f1: a grant from the past` (WEAPON) | `'\tDashProof.Open(shooter, math.min(from or now, now), seconds)\n'` | `'\tDashProof.Open(shooter, math.min(from or now, now) - 0.3, seconds)\n'` |

### Designer: mutate.py, 26 new entries (each caught on a scratch copy)

The WEAPON ones are caught with the pins above. Paste-ready in
`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\3f855f00-eb33-4bab-adb5-c937f685030c\scratchpad\a2\new_entries.py.txt`:

```python
    'l4b g1: a released knock voids nothing waiting behind it': (VITALS, '\t\tfor _, other in vitals.waiting do\n\t\t\tif struckBy(other, at) then', '\t\tfor _, other in vitals.waiting do\n\t\t\tif false then'),
    "l4b g1: a released knock's i-frames from the release": (VITALS, 'grantIframes(player, knockIframes, at)', 'grantIframes(player, knockIframes)'),
    "l4b g1: a released knock's window from the release": (VITALS, 'vitals.knockUntil = at + knockIframes', 'vitals.knockUntil = now + knockIframes'),
    'l4b g1: a knock voids what joined the queue after it': (VITALS, 'return other.strike.at <= at and other.queuedAt <= at', 'return other.strike.at <= at'),
    'l4b g1: a waiting decision judged at the release': (VITALS, 'held, position, at = hold.inShape, hold.position, hold.at', 'held, position = hold.inShape, hold.position'),
    'l4b g1: the release asks no window again': (VITALS, '\t\t\tentry.covered = shielded(vitals.player, entry.strike.at, entry.decideAt)\n', ''),
    'l4b g1: the release drops one that still waits': (VITALS, '\t\tif decide(config, entry, now) then\n\t\t\tbreak\n\t\tend\n\t\treleased += 1', '\t\tdecide(config, entry, now)\n\t\treleased += 1'),
    'l4b g1: ClearThreats keeps the waiting': (VITALS, '\t\ttable.clear(vitals.waiting)\n', ''),
    'l4b g1: what travels never waits behind': (VITALS, 'and (#vitals.waiting > 0 or awaitsDash(player, impactAt, limit, now))', 'and awaitsDash(player, impactAt, limit, now)'),
    'l4b g1: the knock window only at the first try': (VITALS, '\tif at < vitals.knockUntil then\n\t\tentry.covered = true', '\tif hold == nil and at < vitals.knockUntil then\n\t\tentry.covered = true'),
    'l4b g1: rule at the release': (VITALS, 'local verdict = rule(config, vitals, strike, held, voided, position, humanoid, at, now)', 'local verdict = rule(config, vitals, strike, held, voided, position, humanoid, now, now)'),
    'l4b g1: regen from the release': (VITALS, 'vitals.lastHurtAt = math.max(vitals.lastHurtAt, at)', 'vitals.lastHurtAt = now'),
    'l4b g1: the down runs from the release': (VITALS, 'vitals.downUntil = at + downSeconds', 'vitals.downUntil = now + downSeconds'),
    'l4b g1: upAt from the release': (VITALS, 'fx.upAt = Workspace:GetServerTimeNow() + downSeconds - (now - at)', 'fx.upAt = Workspace:GetServerTimeNow() + downSeconds'),
    "l4b g1: the hold's moment wrong": (VITALS, 'entry.hold = { at = now, inShape = held', 'entry.hold = { at = now - 0.2, inShape = held'),
    'l4b g1: the waiting never released': (VITALS, '\t\tif #vitals.waiting > 0 then\n\t\t\trelease(config, vitals, now)', '\t\tif false then\n\t\t\trelease(config, vitals, now)'),
    "l4b g1: a travelling wait's moment its impact": (VITALS, '\t\t\t\tat = now,\n', '\t\t\t\tat = impactAt,\n'),
    'l4b g1: a knock voids queued hits raised after it': (VITALS, '\t\t\tif other.vitals == vitals and struckBy(other, at) then', '\t\t\tif other.vitals == vitals and other.strike.at <= at then'),
    'l4b g1: the down starts at the release': (VITALS, '\t\tvitals.downFrom = at\n', '\t\tvitals.downFrom = now\n'),
    'l4b g3: step never connected': (WEAPON, '\tRunService.Heartbeat:Connect(step)\n', '\tRunService.Heartbeat:Connect(function() end)\n'),
    'l4b g3: step returns before the proofs': (WEAPON, '\tlocal now = os.clock()\n\txpcall(trackAir, stepFailed, now, deltaTime)\n', '\tlocal now = os.clock()\n\tif #state.projectiles == 0 then\n\t\treturn\n\tend\n\txpcall(trackAir, stepFailed, now, deltaTime)\n'),
    'l4b g2: the proofs unprotected': (WEAPON, '\txpcall(trackAir, stepFailed, now, deltaTime)\n', '\ttrackAir(now, deltaTime)\n'),
    'l4b g2: VitalsService unprotected': (WEAPON, '\txpcall(VitalsService.Step, stepFailed, deltaTime)\n', '\tVitalsService.Step(deltaTime)\n'),
    'l4b g2: the rest unprotected': (WEAPON, '\txpcall(stepRest, stepFailed, now, deltaTime)\n', '\tstepRest(now, deltaTime)\n'),
    'l4b g2: the rest never runs': (WEAPON, '\txpcall(stepRest, stepFailed, now, deltaTime)\n', ''),
    'l4b g2: the rest before VitalsService': (WEAPON, '\txpcall(VitalsService.Step, stepFailed, deltaTime)\n\txpcall(stepRest, stepFailed, now, deltaTime)\n', '\txpcall(stepRest, stepFailed, now, deltaTime)\n\txpcall(VitalsService.Step, stepFailed, deltaTime)\n'),
```

The scratch tools in the same folder rerun all of this on a fresh copy:
- `probe.py <set.json> [extra.luau]` copies the working tree, applies the edits and runs that copy's harness.
- `mk.py`, `mkr.py` and `mkpins.py` write the sets.
- `stale.py` is mutate.py's stale check alone.

Before my edits, the stale check read 1,764 entries, 17 stale (those above).

### Designer: sim_range.py

Mirror G1 as in "G1 as built" above:
- a per-player wait list;
- release in moment order;
- `at` for the knock windows, the down's clock and `lastHurtAt`;
- `struckBy` with the queue time;
- a contact waits behind as well.

The gate line the lead asked for: a dash into the fence (unproven), with a knocking lunge and then a plain hit, must
give the no-dash outcome (one landed, one dodged).

## What to check in Studio

- Dash into a camp fence while an elite and a brute swing:
  - with no i-frames you take one hit and the second reads DODGED, as with no dash;
  - the effect comes about 0.45 s after the press.
- An honest dash still reads DODGED.
- No `[WeaponService] Heartbeat:` warning in a normal run. One appears only if a part of the frame throws, and once
  per message.
