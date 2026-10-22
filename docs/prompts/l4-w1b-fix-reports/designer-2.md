# L4 W1b fix round 2 — economy-designer's report

Worktree `C:\Users\benja\Desktop\tycoon-p5c`, branch `l4-w1b-fix2`, nothing committed. Rulings: `docs/prompts/l4-w1b-fix2.md`
(mine: G1's simulator mirror and the fence-dash gate line, G3's pins and the review's two probes as mutants, s1's two
`payMentors` pins). A's report: `docs/prompts/l4-w1b-fix-reports/luau-a-2.md`; its G1 as built is what the mirror
follows, and the lead's acceptance of its assumptions and limits is taken as given. No `src/**` file edited; no config
key changed. Python named for every number: "3.12" = `py -3.12` (3.12.10 64-bit, the gate's); "py" = `py` on a script
with a shebang, which runs the same 3.12.

## Results

| Gate | Result |
|---|---|
| `run_harness.py C:/Users/benja/Desktop/tycoon-p5c <luau>` (py) | **HARNESS: PASS (4,185 checks)** (was FAIL 4 of 4,177 on A's code: the four pins below; A's 4,181 + my 4 for s1 and s2) |
| `sim_range.py --check` (3.12, in the worktree) | **CHECK: FAIL (1)**: only the known R8 row, **x1.60** (seed 11 39,504 / 55.1 against 24,703 / 37.2; 23: 18,374 / 27.6 against 23,330 / 34.8; 37: 2,756 / 0.0 against 21,332 / 31.9). 539 PASS (538 + G1's fence dash, green: one landed, one dodged) |
| `check_stage_mirror.py --luau <luau>` (py, in the worktree) | **CHECK: PASS** (`Combat.MentorBonus: 28 compared`, `... mentor_pay: 11 compared`) |
| `mirror_mutants.py --luau <luau>` (py, in the worktree) | **132 of 132 mutants caught** |
| `sim_combat.py --check` (py, in the worktree) | **CHECK: PASS -- all eleven assertions hold**; the whole output byte-identical to f16515a's (run on an export of it beside this one): it imports the mirror's LevelRun |
| `mutate.py ... "files:VitalsService.luau,WeaponService.luau,DashProof.luau,WaveService.luau"` (py, which runs `mutate.py` on 3.14 32-bit: no shebang) | **MUTATIONS: 260 run, 0 not caught** (BASELINE: HARNESS: PASS 4,185). The review's G3 probes are caught by `startConnects` and `stepHead`, s1's by `mentorTotal` and `mentorNoBonus` (+ `bonusGuardThenPay`), s2's by `pendingNoClaim`, A's 19 G1 by tests_l4b (g) |
| `mutate.py` stale check over all entries (scratch exec up to its baseline, A's `stale.py`) | **1,795 entries, 0 stale** (was 1,764, 17 stale) |

**"Identical to f16515a", checked.** The whole `sim_range.py --check` output of the new simulator equals f16515a's
(this worktree's simulator and data before my change, run beside it on the same machine) line for line, but two:
- the `DASH PROOF` header's wording: "F1: decisions held for a pending claim, voided at its proof / judged unvoided at
  its lapse" became "F1 and G1: decisions held (for a pending claim, or behind one), voided / judged unvoided at their
  release" (the old text was wrong for G1: a decision behind a held knock is voided at the lapse);
- one new PASS line, G1's fence dash.

Every Forest Road line, the R8 row (x1.60, the same seed numbers) and every DASH PROOF count are unchanged. Nothing could
move: every simulated dash proves 2 Heartbeats after its press, a decision due in those Heartbeats is covered by the
claim's window itself (impact well under dashIframes 0.25 s after the press), so none waits only behind another, and
the proof voids every held entry without releasing a knock.

## Changes, file by file

### `tools/sim_range.py` (G1's mirror)
- `hold(at, queued, ...)`: a waiting decision keeps its moment `at` (the frame it fell due; for a shot, charge or ring
  contact, the crowd step that found it), its queue time, and whether it was voided by then.
- `resolve`: a decision waits when the claim would cover it (as before) **or whenever another of his waits** (voided or
  not), behind it. The three contacts in `sweep` the same, unless already voided (answered now, as the game does).
- `release(t)`, VitalsService.release: first to last; each asks its whole span of the windows again, is dropped if he
  is or was down or a barrage he answered, is voided by `at < knock_until`, and stops the walk if the pending claim
  still covers it (it and those behind stay); else `rule(..., at=at)`. Released entries leave from the front.
- `rule(..., at=None)`: the knock test moved to the callers (it was redundant for every caller but the release, which
  now folds `at < knock_until` into `voided`, as VitalsService's decide does).
- `hurt(..., at=None)`: the regen delay (`last_hurt = max(last_hurt, at)`), the down (`down_until`, `down_span`) and the
  knock's window, `knock_until` and voids run from `at`; the voids use `struck_by(impact, queued, at)` over the queue,
  the queue being walked and the waiting ones. The log, `downs` and the push stay at `t` (when the effect leaves).
  `LevelRun.hurt` passes `at` on and starts its endless down at `at`.
- Queue entries gain a 12th field, the step that queued them (`land`'s `now`; the throw for a lob).
- `fence_queues`, `dash_fence_probe` and one gate line in `check_threat` (G1): the review's three queues against a dash
  pressed into the fence and against no dash; passes when each loses what no dash loses and the first is one landed,
  one dodged. On f16515a's mirror the same queues reproduce M1's three rows (both hits land); on G1's they read:
  knocking lunge then plain: knock at 0.467 landed, 1 dodged (no dash: knock at 0.000, 1 dodged); two knocks in one
  step: knock at 0.467, 1 dodged (no dash: 0.000, 1); a held knock then a plain one past the claim's window: knock at
  0.467, 1 dodged (no dash: 0.050, 1).
- Comments: `DASH_TALLY`, `DASH_PROOF_FRAMES`, the `holds` state; the DASH PROOF header as above.

### `tools/crowd_harness/run_harness.py` (L4B_LINES / L4B_ORDER) and `tests_l3_w2.luau` (L4BP)
- Re-aimed (A's texts): `stepVitals` (`\txpcall(VitalsService.Step, stepFailed, deltaTime)`), `vitalsStepCalls`
  (`VitalsService.Step`, 1), `grantOpens` (`\tDashProof.Open(shooter, math.min(from or now, now), seconds)\n\tshowIframes(shooter, now)\n`),
  `frameOrder` (the two `xpcall` lines).
- G3: `startConnects` (`\tRunService.Heartbeat:Connect(step)`, whole, in `WEAPON_START_BODY`); `stepHead` (one text block
  in `WEAPON_STEP_BODY` from `local function step(deltaTime: number): ()` through the `xpcall(VitalsService.Step, ...)`
  line, so nothing sits between the start and the two calls).
- G2: `stepRest` (`\txpcall(stepRest, stepFailed, now, deltaTime)`, whole), order `restLast` (after VitalsService).
- s1: `mentorTotal` (`\tlocal total = 0\n\tfor _, damage in tally do\n\t\ttotal += damage\n\tend\n`, one block, so the
  start value is pinned with the sum), `mentorNoBonus` (`\t\tif bonus <= 0 then\n\t\t\tcontinue\n\t\tend\n`, with its
  `continue`), order `bonusGuardThenPay` (the guard before `state.combat.valor += bonus`).
- s2 (A's optional pin): `pendingNoClaim` (`\tif shooter == nil or shooter.dashClaimAt == nil then`, whole, in
  `PENDING_DASH_BODY`).
- Each with its expected count and label in L4BP (counts 1). `tests_l3_w2.luau` is outside the stylua gate (`src`
  only) and already failed `stylua --check` at HEAD; the new lines follow its one-line style.

### `tools/crowd_harness/mutate.py`
- The 17 stale entries re-aimed, same labels, A's new texts (`luau-a-2.md`): 14 VitalsService (the ruling-18, lob, boss
  and F1 entries) and 3 WeaponService ("decides before the proofs", "never stepped", "a grant from the past").
- New block `L4B_FIX2_MUTATIONS` (31 entries, with the label-collision guard): A's 26 verbatim (19 "l4b g1", 2 "l4b g3":
  the review's `Connect(function() end)` and the early return, 5 "l4b g2"), and mine: "l4b s1: the total is the top
  damage" (the review's `math.max`), "the total starts at one", "a bonus of nothing is paid" (the review's guard
  deleted), "the guard on nothing turns nobody back" (its `continue` deleted), "l4b s2: a rule built with no claim".

### `docs/BALANCE.md`
- New section "L4 W1b fix round 2: a held hit keeps the knock rules": the mirror, the result, the three queues before
  and after, the R8 row, what the mirror does not model, the gates before and after, the new gates and mutants.

## For the other owners

Every line a new or re-aimed pin or mutate entry of mine reads, so an owner who changes one tells the designer (file;
text with its indentation; `\t` = one tab):

- **luau-engineer A, `src/combat/server/Services/WeaponService.luau`:**
  - `step` exactly as A gave it (no comment inside; its first four lines are one pin):
    `local function step(deltaTime: number): ()` / `\tlocal now = os.clock()` / `\txpcall(trackAir, stepFailed, now, deltaTime)` /
    `\txpcall(VitalsService.Step, stepFailed, deltaTime)` / `\txpcall(stepRest, stepFailed, now, deltaTime)`.
  - `WeaponService.Start`: `\tRunService.Heartbeat:Connect(step)`.
  - `WeaponService.GrantIframes`: `\tDashProof.Open(shooter, math.min(from or now, now), seconds)` then
    `\tshowIframes(shooter, now)`.
  - `pendingDash`: `\tif shooter == nil or shooter.dashClaimAt == nil then` / `\t\treturn 0, 0, 0`.
  - `VitalsService.Step` named once in the file's code.
- **luau-engineer A, `VitalsService.luau`:** the texts of A's 19 G1 entries and the 14 re-aims, as A gave them.
- **luau-engineer B, `src/combat/server/Services/WaveService.luau` (`payMentors`):** `\tlocal total = 0` /
  `\tfor _, damage in tally do` / `\t\ttotal += damage` / `\tend` (one block); `\t\tif bonus <= 0 then` / `\t\t\tcontinue` /
  `\t\tend` (one block), before `\t\tstate.combat.valor += bonus`.

## For the lead

- Nothing is needed in `src/shared/Economy.luau` or any `src` file.
- The re-aimed "l4b f1: a knock voids a held hit" keeps its label (the stale protocol), though under G1 a knock does void
  a held hit; its mutant now lets a later decision land out of turn (A's reversed pin). Rename it at a quiet moment if
  the label matters; renaming now would break QA's label-by-label comparison with the f16515a run.
- The mirror's one remaining G1 gap: the planner (`plan_hits`) dates an unproven dash's hits at their decision, not at
  the lapse; no gated run dashes unproven. The earlier gap (a held hit released before a decision queued earlier in the
  same frame) is closed, since the game now releases the waiting before walking its queue too. A's limit 1 (an aimed
  miss against a held knock) has no counterpart in the mirror (it models no aimed-miss dodge for what travels); limits
  2 to 4 are mirrored as the game does them.
- Not run this round: `check_levels.py` and `check_levels_mutants.py` (they import `sim_range` for level geometry
  only; none of the methods I changed is theirs). `sim_combat` and `check_stage_mirror`, which run the mirror's
  LevelRun, were run on the new simulator: identical and PASS.

## Summary

- **Files changed:** `tools/sim_range.py` (G1's mirror + the fence-dash gate line), `tools/crowd_harness/run_harness.py`
  and `tests_l3_w2.luau` (G3, G2, s1, s2 pins; four re-aimed), `tools/crowd_harness/mutate.py` (17 re-aimed, 31 new),
  `docs/BALANCE.md` (new section), this report. No `src` file, no config key.
- **Gates:** harness PASS (4,185 checks); `sim_range.py --check` FAIL (1), only R8 at x1.60, the new G1 fence-dash line
  green (one landed, one dodged; the review's other two queues too), every other line identical to f16515a's but the
  DASH PROOF header's wording; `check_stage_mirror.py` PASS; `mirror_mutants.py` 132 of 132; `sim_combat.py --check`
  PASS and identical; filtered `mutate.py` 260 run, 0 not caught; stale check 1,795 entries, 0 stale.
- **Constants changed:** none (the probe's knock of 30 and its `dashIframes + 0.02` are the probe's own).
- **Economy.luau:** no change needed.
