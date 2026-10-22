# L4 W1b review, fix diff (`git diff a098eaf..f16515a`)

Reviewer: roblox-reviewer, 2026-10-22. Branch `l4-w1b` at f16515a. Read only: this file is the only one written.
Every probe ran on a `git archive f16515a` copy in my scratch folder (never in the worktree, where the full
`mutate.py` run is going). The copy's own harness reads `HARNESS: PASS (4,162 checks)`.

**Count: 0 Critical, 1 Major, 2 Minor, 3 Suggestions.**

## Major

**M1. Held hits that are released together skip rulings 6 and 18. An unproven dash, such as a dash into a fence,
then takes hits that a player who never dashed would not.**

- Where:
  - `src/combat/server/Services/VitalsService.luau:365`: the knock loop skips every held entry (`and other.hold ==
    nil`).
  - `:440`: a held entry is never judged against `knockUntil` again.
  - The mirror copies both. In `tools/sim_range.py:2506-2527`, `release` passes `knock=False`, and `:3118` reads it.
- What is wrong:
  - F1 says "nothing else about a hit changes", and a lapsed claim's hit "lands".
  - The exemption at `:365` was written for one order: a hit held from earlier, then a later knock that is not held.
    In that order the held hit's moment really did come first.
  - It also exempts held hits from a knock that is itself held. All of a claim's held hits are released in the frame
    the claim lapses. The first one lands and knocks. The others are held, so its knock voids none of them, and
    `:440` does not judge them against `knockUntil`. Its knock i-frames open at the lapse, after all of their spans,
    so ruling 6 covers none of them either. Every one of them lands in that frame.
  - Without a claim, the same queue lands one hit and voids the rest (ruling 18: "a knock voids the hits decided with
    it", there "so enemies that wound up in the same step would otherwise land as one hit").
  - The same happens when a held knocking hit is released after an unheld hit that landed while it waited. That hit
    would have been voided by the held hit's knock.
- Measured with the real VitalsService and DashProof.Step, in WeaponService's order. This was a case added to a
  scratch copy of `tests_l4b.luau`, ping 0.05, with no motion. "Lost" is the health taken, 8 a hit:

  | Strikes (time after the claim) | No claim | Claim never proven |
  |---|---|---|
  | knocking hit at 0, plain hit at 0.05 | lost 8: 0.100 landed, 0.150 dodged | **lost 16**: both landed at 0.467 |
  | two knocking hits in one step, at 0 | lost 8: landed, dodged | **lost 16**: both landed at 0.467 |
  | held knocking hit at 0.05, unheld hit at 0.27 | lost 8: 0.150 landed, 0.383 dodged | **lost 16**: 0.383 and 0.467 landed |

  `sim_range`'s own `ThreatRun` does the same for a dash into the fence (the `dash_hold_probe` set-up, with a knocking
  lunge and then a plain one). It lands both at 0.467. Without a dash it lands one and dodges one.
- Who reaches it: an honest player. Contract §4.5 says a dash that a wall stops under about 3.3 studs is never
  proven. At 1ae8bfb such a dash earned nothing, and ruling 18 still held. Before L4 it voided both hits. Now it is
  worse than not dashing.
- Failure scenario: a solo player on Hard backs away from an armoured elite (arc 30, knock 30) and a brute (charge
  28, knock 30), and dashes into a camp fence 2 studs behind. Both hits are held for the claim, and both land at the
  lapse: 58 instead of 30. If the second hit takes the player down, the run ends (a solo down ends the run).
- No gate sees it:
  - The simulator never dashes unproven ("nothing was held to a lapse in a gated run").
  - The harness pins the opposite: "a knock while a hit is held does not void it" (`tests_l4b.luau:719`), and the
    mutant "l4b f1: a knock voids a held hit" enforces it. That case is right for its own order, but no case covers
    a held hit that knocks.
- Fix: judge a held hit's knock rules at its own moment.
  - Record `hold.at = now` at the first try.
  - When a held hit lands with a knock, start its knock window from `hold.at`. Void every other entry of that player
    whose own moment (its `hold.at`, or `now` for one that is not held) falls inside that window. That is the
    condition at `:365`, read against moments instead of `hold == nil`.
  - While a player has a held entry, keep each later decision of that player behind it, bounded by the same lapse.
    Then an unheld hit cannot land in between, and the queue releases in decision order.
  - Mirror it in `release` and `rule(knock=...)`.
  - Add tests_l4b cases for the three rows above. With a claim that never proves, each should land 8 and dodge the
    second hit, as with no claim.

## Minor

**m1. One Heartbeat now runs both modules, with nothing between them to contain an error.**

- Where: `src/combat/server/Services/WeaponService.luau:2124-2133`: `trackAir`, then `VitalsService.Step`, then
  `tickIframes`, `stepProjectiles` and the 2 Hz stats.
- What changed:
  - Before F1, the two modules ran on two Heartbeat connections. Each runs on its own thread, so a throw in one never
    stopped the other.
  - Now an error in `trackAir` (raycasts, SwingGate, DashProof.Step) skips every enemy-hit decision, regen, get-up
    and the CombatFx flush for that frame.
  - An error in `VitalsService.Step` skips `tickIframes`, `stepProjectiles` and the stats.
  - `VitalsService.Step` also runs `rules.onDown`, which is `WaveService.OnDown` and then `advance`: the run's whole
    state machine.
- Failure scenarios:
  - One throw in `advance` on a down costs every player's projectiles that frame's travel, and leaves the
    RangeIframes attribute up one more frame.
  - A persistent throw in `trackAir` makes every player immune and unhealed for the rest of the server's life, with
    no other symptom. One example is a raycast on a body part the level never had.
  - A persistent throw in `settle` freezes every arrow.
- Fix (either works):
  - Run the two halves isolated and in order. `task.spawn(trackAir, now, deltaTime)` then
    `task.spawn(VitalsService.Step, deltaTime)` resumes each at once, keeps the order (neither yields), and reports
    an error without stopping the caller. `xpcall` with a once-only `warn(debug.traceback(...))` does the same.
  - Or move `VitalsService.Step` after `tickIframes` and `stepProjectiles`. Neither reads anything Vitals writes this
    frame. This contains the Vitals-to-Weapon direction at no cost.

**m2. `RunService.Heartbeat:Connect(step)` now gates every enemy hit, and no gate pins it.**

- Where: `WeaponService.luau:3178`, and the `heartbeats` pin at `tools/crowd_harness/run_harness.py:1479`.
- What changed:
  - Before F1, `tests.luau` drove `vitalsBeat = beats[#beats]`, the Heartbeat that VitalsService connected itself.
    A VitalsService that connected nothing failed the harness.
  - Now VitalsService is stepped only from WeaponService's `step`, and WeaponService cannot load in the harness.
  - The pins hold `\tVitalsService.Step(deltaTime)` inside `step` (stepVitals), the order (frameOrder), and the text
    count of `Heartbeat:Connect(` (heartbeats, 1). None of them holds which function is connected, or that `step`
    reaches the two calls.
- Review-only mutants, each `HARNESS: PASS (4,162)`:
  - `\tRunService.Heartbeat:Connect(step)` becomes `...Connect(function() end)`. No enemy hit is ever decided, nobody
    regenerates or gets up, and no dash is proven.
  - An early `if #state.projectiles == 0 then return end` at the top of `step`. The same, whenever nobody has an
    arrow in the air.
- Fix:
  - Pin `\tRunService.Heartbeat:Connect(step)` as a whole line in `WEAPON_START_BODY`.
  - Pin `step`'s head as one text block, from `local config = Tuning.Get()` to `VitalsService.Step(deltaTime)` (comments
    blanked), so nothing can sit between the function's start and the two calls.
  - Add both mutants to `L4B_FIX_MUTATIONS`.

## Suggestions

- **s1. payMentors: pin the inputs as well as the deciding lines.** `WaveService.luau:728` (`total += damage`) and
  `:756` (`if bonus <= 0 then continue`) are unpinned.
  - `total = math.max(total, damage)` survives. Every share is then measured against the top damage dealer, so
    mentors and mentees under the 1% floor pass it.
  - Dropping the `bonus <= 0` guard also survives. A "+0 Valor, 0 mentees" mentor toast then pops for every mentor at
    every boss kill.
  - Both are `HARNESS: PASS (4,162)`. This is the recurring "pin a call, not its inputs" family. Pin both lines whole.
- **s2. `pendingDash` builds a Rule on every decision, claim or none.**
  - `WeaponService.luau` `pendingDash` evaluates `dashRule(config)`, a fresh `DashProof.Rule` table, before `Pending`
    sees that `dashClaimAt` is nil.
  - `awaitsDash` asks it for every enemy decision not already voided, and every frame for each held entry.
  - Return `0, 0, 0` first when `shooter.dashClaimAt == nil`, or cache the Rule per `Tuning.Get()` table. The same
    applies to `proveDash`'s per-frame `dashRule`.
- **s3. F5 is in the contract (§10) but not yet in PLAN.**
  - `docs/PLAN.md:2764` and `:3042` still list "OnDash grants i-frames on the request alone ... judge the dash against
    the position ring" as open, before any publish.
  - Close them with F5's scope: a request-only forger and a wall dash, not a client that moves its own root.
  - Name the held-hit rule while doing so: unproven claims hold up to 0.45 s. That is docs-keeper's pass, but the
    lead owns F5.

## Checked and clean

- **F1, the hold never hangs.**
  - `awaitsDash` ends at `now <= lapseAt`, the same boundary as Verdict's `now > claimAt + lapse`. On the lapse frame,
    WeaponService's Step clears the claim before Vitals decides, so the hold ends in that frame.
  - The case "a hook pending forever" proves the ceiling.
  - A newer claim cannot extend a hold. A held entry's `decideAt` is at most claim + 0.25 + 0.3 = 0.55, which is less
    than the cooldown, 0.8 × 0.8 = 0.64. So a later claim's window never meets its span. The margin is 0.09 s, and the
    shipped numbers hold it.
- **F1, a leaving player or a replaced body leaks nothing.**
  - `decide` drops a held entry on `vitalsByPlayer[player] ~= vitals` (RemovePlayer), on down or was-down, on
    `not judged` (waiting), on no living root, and on `hold.humanoid ~= humanoid` (respawn).
  - `IframeWindow` and `pendingDash` answer 0 for a removed shooter.
  - `ClearThreats` (a camp's `clear`, `drop`, the run's end, a set load) takes held entries too.
  - `onGone` keeps them, which is right: a held entry's moment came before the death. A non-dasher's hit decided at
    the same moment had already landed.
- **F1, held travelling contacts.**
  - `judgeTravelling` holds only a contact that the shape held, not voided, under a covering claim.
  - It clones the strike with `at = impactAt` and keeps the root found then.
  - It answers "dodged", so `done` is set and an aimed miss is never asked. The shot flies on (A's ruling, accepted).
  - Its `covered` re-check uses the same span as the immediate path.
- **F1, the knock rule at the decision** holds for a single held hit. A knock already running at the first try voids
  it (`hold == nil and now < knockUntil`), and a later knock that is not held does not void it. M1 is the case of
  several held hits.
- **F1, one frame order.**
  - `step` runs `trackAir` (ring sample, then `DashProof.Step`), then `VitalsService.Step`.
  - VitalsService connects no Heartbeat (tests_l4b (g) counts `beats`, and the mutant "connects its own Heartbeat" is
    caught).
  - CrowdService's handler order no longer matters for travelling verdicts: a pending claim holds them either way.
- **Nothing in the new Heartbeat yields.** VitalsService.Step, `flush`'s FireClient, and `onDown` then `advance`
  don't. The registry calls go through ArenaService's worker mailbox, and `DataService.GetState` is a read. There is
  no `task.wait` or `:Wait()` in WaveService or ArenaService.
- **DashProof.Step and Pending** match the code they replaced, branch for branch.
  - Step clears the claim on proof, lapse and no rule, and opens from `claimAt`.
  - The edge cases are real tests: exactly 64 studs/s proves and a hair under stays pending (on binary-exact numbers),
    a proof on the lapse frame wins, and a negative lookback gives no rule.
  - My probe "Pending lapses 0.2 s later" is caught.
- **The simulator's hold** matches the Luau in every respect but two:
  - the release order the designer states (holds first, then the frame's new decisions);
  - M1, which it mirrors faithfully.

  `awaits` is `met`, `settle_claim` runs before anything is decided, a down or a barrage already answered drops a held
  entry, and `clear_threats` empties `holds`.
- **Review mutants of slices 1-3** are all `mutate.py` entries, and their texts are present: the `mutate.py` stale
  check, exec'd up to its baseline on the copy, reads 1,764 entries, 0 stale.
  - The ones that are now real behaviour (the Step branches, the lapse, the hold) are tests_l4b's.
  - The text pins are whole lines with their indentation, in their bodies. Every count-0 pin shares its body with a
    count-1 pin, and a missing body is reported, so none can pass on a body regex that stopped matching.
- **F3/F4.**
  - `sendRunState` skips Attach for a member already noted, and the note is written in the same branch.
  - `onRunState` applies the floors right after the guard. `applyFloors` reads only `st` and the payload, and
    CrowdRenderer and CameraController's `SetFloors` read no level state.
  - The seven slice 2 mutants map to pins (uiMerge, uiSeq, uiCall, sendCellsWent, sendFloorsWrites).
- **F6.** `check_stage_mirror` really runs the Luau `Combat.MentorBonus`:
  - on the copy: `PASS`, 28 cases plus 11 replays;
  - `rate <= threshold`: `FAIL (7)`, 6 of 28 cases differ and 1 of 11 kills;
  - `return 0`: `FAIL (16)`.
- **The hub stub's `waves` 2.**
  - Its readers are ExpeditionPanel's tile ("2 waves"), ExpeditionSummaryCard's "n / 2", the Depart and fakeRuns
    paths (`id` and `era`), and ArenaService's registry `era`. None does arithmetic on it.
  - No tool reads the stub.
- **Slice 3 S2.**
  - "Every level file is played by a map node" holds today (1) and is not vacuous (`#played > 0`).
  - "Every side node hangs off a level node with a map theme" holds over 0 nodes today. It is a rule for later, and
    `MapNode.from` is the real field.
- **Slice 2 s2.** `BOTTOM_BLOCK` = 140 design px, which is above the 132 px perf line top. `Theme.COMBAT_PERF_HEIGHT`
  exists (16).
- **Code rules.**
  - `--!strict` kept.
  - No `wait`, `spawn`, `delay`, `_G` or parent argument in added lines.
  - No numeric constant added in Luau. `DASH_PROOF_FRAMES` is the simulator's own.
- **Gates on the copy:**
  - stylua `--check` and selene on the six changed Luau files: clean.
  - luau-lsp, `combat.project.json` sourcemap, on the changed files: 0 diagnostics. A planted type error is reported,
    so the run was live.
  - `check_compile.py`: PASS, 176 files, WeaponService 102 top-level locals.
