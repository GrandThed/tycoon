# L4 W1b fix round — economy-designer's report

Worktree `C:\Users\benja\Desktop\tycoon-p5b`, branch `l4-w1b`. Nothing committed. My rulings in
`docs/prompts/l4-w1b-fix-round.md`: F1's simulator mirror and BALANCE, the pins and mutants of F2, F3 and F6, F6's
MentorBonus mirror, slice 3 S2 (the two real-map checks as rules) and S4 (the hub stub's `waves` 2). No `src/**/*.luau`
edited. Python named for every number: "3.12" = `py -3.12` (3.12.10 64-bit, the gate's); "py" = `py` on a script
with a shebang, which runs the same 3.12 (memory note environment-2026-09-08).

## Results

| Gate | Result |
|---|---|
| `run_harness.py C:/Users/benja/Desktop/tycoon-p5b <luau>` (py) | **HARNESS: PASS (4,162 checks)** (4,133 with A's pins and fixture, FAIL 2 before B's re-aims; +29 of mine) |
| `check_stage_mirror.py --luau <luau>` (py) | **CHECK: PASS**, with `Combat.MentorBonus: 28 compared` and `... through sim_combat.mentor_pay (assertions 12, 13): 11 compared` |
| `mirror_mutants.py --luau <luau>` (py) | **132 of 132 mutants caught** (+3 MentorBonus) |
| `sim_range.py --check` (3.12) | **CHECK: FAIL (1)**: only the known R8 row, **x1.60** (seed 11 39,504 / 55.1 against 24,703 / 37.2; 23: 18,374 / 27.6 against 23,330 / 34.8; 37: 2,756 / 0.0 against 21,332 / 31.9). 538 PASS (537 + the new F1 line) |
| `check_levels.py` (3.12) | **CHECK: PASS** (222 PASS lines) |
| `check_levels_mutants.py --luau <luau>` (3.12) | **MUTANTS: PASS** (274 cases as expected, about 3 h beside the other runs) |
| `sim_combat.py --check` (py) | **CHECK: PASS -- all eleven assertions hold** (12 and 13 print the values BALANCE's W1b section states) |
| `mutate.py ... "files:DashProof.luau,VitalsService.luau,WeaponService.luau,ArenaService.luau,WaveService.luau,CombatUIController.luau,RunFloors.luau"` (py) | **269 run, 0 not caught** (baseline PASS 4,162), filtered to DashProof, VitalsService, WeaponService, ArenaService, WaveService, CombatUIController and RunFloors |
| `mutate.py` stale check over all entries (scratch exec up to its baseline) | 1,764 entries, 0 stale, every target in `FILES` |

**"Byte-identical", re-checked.** With the hold in the mirror, the whole `sim_range.py --check` output (3.12) equals
the output of the same tree before my simulator change, line for line, except (a) the `DASH PROOF` block, whose lines
gain "held voided / unvoided" counts, and (b) one new PASS line (the F1 hold probe). Every Forest Road gate line,
the R8 row included, is unchanged. 33 Forest Road decisions are held for a pending claim and voided at its proof
(the human 1, the reacting player 26 + 1 + 2, the kite 3): these are exactly slice 3 m1's 33 "margin 0" voids, which
the game now dodges too. 0 dashes unproven, so nothing is held to a lapse in a gated run. BALANCE.md says so and
corrects the W1b paragraph (the claim held then only because the mirror was ahead of the game).

## Changes, file by file

### `tools/crowd_harness/tests.luau`
- A's `fixture_change.py`, applied as relayed: `vitalsBeat = Vitals.Step` (VitalsService connects no Heartbeat now)
  and a `dashClaim` hook returning `0, 0, 0` in the fixture's `Vitals.Start`.

### `tools/crowd_harness/run_harness.py` (L4B_LINES / L4B_ORDER) and `tools/crowd_harness/tests_l3_w2.luau` (L4BP)
- A's `draft_pins.py` applied as relayed: `OPEN_IFRAMES_BODY` gone; `PENDING_DASH_BODY`, `WEAPON_STEP_BODY`,
  `WEAPON_START_BODY`, `GRANT_IFRAMES_BODY` new; the 21 WeaponService keys of `pins_lines.py.txt` with
  `pins_expected.luau.txt`'s counts (dashGrantsNothing 0, dashClaim, dashStamp, dashDown, trackRecordThenProve,
  trackNoRootClears, proveStep, proveShows, proveWritesNothing 0, ruleRead, ruleCalls, pendingClaim, hookClaim,
  stepVitals, vitalsStepCalls, heartbeats, grantOpens, openCalls, stepCalls, claimWrites 3, resetDropsClaim);
  `trackOrder` re-aimed to `proveDash(shooter, now, position)`, `frameOrder` new (`trackAir(now, deltaTime)` before
  `VitalsService.Step(deltaTime)`).
- B's server lines (F3, slice 2 s1), all whole lines in `SEND_RUN_STATE_BODY` unless said: `sendSkip`
  (`\tif play.cellsSent[userId] ~= seq then`), `sendAttach` (now a whole line, `\t\tlocal floors, cellsWent = ...`),
  `sendCellsWent` (`\t\tif cellsWent then`), `sendClone` (`\t\t\tsent = table.clone(runState)`), `sendFloors` re-aimed
  (`\t\t\tsent.floors = floors`), `sendFloorsWrites` (regex `\bsent\.floors\s*=(?!=)`, 1), `sendNote` re-aimed
  (`\t\tplay.cellsSent[userId] = seq`), `sendFires` (`\tRemoteService.FireClient(player, "RunState", sent)`).
- The ui-engineer's client lines (F3, F4): `UI_CONTROLLER`, `APPLY_FLOORS_BODY` and `ON_RUN_STATE_BODY` (both one tab
  in); `uiHeld`, `uiMerge`, `uiSeq`, `uiKeep`, `uiCall` (whole lines), `uiApplyCalls` 2, `uiMergeCalls` 1,
  `uiSeqWrites` 1, `uiConnect`; orders `uiMergeThenSeq`, `uiMergeThenSame`, `uiGuardThenFloors`, `uiFloorsFirst` (F4).
  Labels as the ui-engineer suggested.
- B's payMentors lines (F6): `PAY_MENTORS_BODY`; `mentorNone`, `mentorFloor`, `menteeOther`, `menteeFloor`,
  `menteeRate`, `mentorBonusCall`, `mentorValor`, `mentorCard` (whole lines), `mentorBonusCalls` 1 (file text),
  `bossPaysMentors` (whole line, file); order `mentorFloorThenPay`.

### `tools/crowd_harness/mutate.py`
- Re-aimed (A): "18: no knock window at the decision", "lob: a knock voids one still in the air", "boss: decisions
  still waiting are kept" (VitalsService's new lines); "l4b: the window from the proof" now on DashProof
  (`DashProof.Open(claimant, claimAt, seconds)` -> `now`); "l4b: the claim never judged" (`proveDash(shooter, now,
  position)`); "l4b: OnDash opens on the request" is now the review's own mutant (OnDash calls
  `WeaponService.GrantIframes`).
- Re-aimed (B): "l4b: a member's note is never written" (two tabs), "l4b: a first send drops its cells" (three tabs).
- New block `L4B_FIX_MUTATIONS` (71 entries; `FILES` gains `CombatUIController.luau`; a guard asserts no label
  collides with an existing one): A's 45 new ones (checked: each old text occurs once; A's own scratch run caught
  every DashProof, VitalsService and RunFloors one through tests_l4b; the WeaponService ones by the pins), B's 8 new
  F3 server ones and 9 F6 ones, the ui-engineer's 9 client ones. Labels "l4b f1" to "l4b f6"; run alone with
  `mutate.py <root> <luau> "l4b f"`.
- In-memory pre-check (scratch `premut.py`, run_harness's own `l4b_reading`): all 58 l4b entries on the four
  text-only files move at least one pin.

### Where each review mutant is caught

| Review mutant | mutate.py label | Caught by |
|---|---|---|
| slice 3 m2 / slice 1 m1: `if verdict == "proven"` -> `~= "lapsed"` | "l4b f1: Step opens unless lapsed" (the branch is DashProof.Step's now) | tests_l4b (47 checks in A's run) |
| slice 3 m2: OnDash calls `GrantIframes` | "l4b: OnDash opens on the request" | pin `dashGrantsNothing` |
| slice 3 m2: `elseif verdict == "lapsed"` -> `else` | "l4b f1: Step drops a claim not proven on its first frame" | tests_l4b |
| slice 3 m2 / slice 1 m1: trackAir's no-root clear deleted | "l4b f2: no root keeps the claim" | pins `trackNoRootClears`, `claimWrites` |
| slice 3 m2: `lastDashAt = now` deleted | "l4b f2: OnDash keeps no cooldown" | pin `dashStamp` |
| slice 3 m2: OnDash's `IsDown` refusal dropped | "l4b f2: OnDash while down" | pin `dashDown` |
| slice 1 m1: `if claimAt ~= nil` -> `== nil` (now `shooter.dashClaimAt`) | "l4b f2: judged only without a claim" | pin `trackRecordThenProve` |
| slice 1 m1: the lapse branch keeps the claim | "l4b f1: a lapse keeps the claim" | tests_l4b |
| slice 1 m1: a 1e6 lookback | "l4b f2: a lookback of 1e6" | pin `ruleRead` |
| slice 2 m1, 1: the client never merges | "l4b f3: review 1, the client never merges" | `uiMerge`, `uiMergeCalls`, `uiMergeThenSeq`, `uiMergeThenSame` |
| 2: `st.floorsSeq = seq` deleted | "l4b f3: review 2, ..." | `uiSeq`, `uiSeqWrites`, `uiMergeThenSeq` |
| 3: `applyFloors(run.floors, 0)` | "l4b f3: review 3, ..." | `uiCall` |
| 4: merge against the incoming list | "l4b f3: review 4, ..." | `uiMerge`, `uiMergeThenSeq`, `uiMergeThenSame` |
| 5: `if cellsWent` -> `if false` | "l4b f3: review 5, no cells ever go" | `sendCellsWent` |
| 6: `sent.floors = runState.floors` after the swap | "l4b f3: review 6, ..." | `sendFloorsWrites` |
| 7: `if cellsWent or true` | "l4b f3: review 7, ..." | `sendCellsWent` |
| slice 3 m3, 1: a waiting mentor paid | "l4b f6: review 1, a waiting mentor paid" | `mentorFloor` |
| 2: mentees under the floor | "l4b f6: review 2, mentees under the floor" | `menteeFloor` |
| 3: `Combat.MentorBonus` with `rate <= threshold` | mirror_mutants "MentorBonus F6: a mentee exactly at the ratio carried" | `check_stage_mirror.py`: `Combat.MentorBonus: 6 of 28 differ` |

### `tools/check_stage_mirror.py`, `tools/crowd_harness/stage_mirror.luau`, `tools/crowd_harness/mirror_mutants.py` (F6)
- `MentorBonus` in `NEEDED["Combat"]`. `mentor_cases`: every `Combat.MentorBonus` call `sim_combat.mentor_pay` makes
  on assertions 12 and 13's boss kills (recorded through mentor_pay's new `bonus_of`), plus, for host rates 0, 8,000
  and 10,000: no party, a rate exactly at hostRate x mentorRatio, `EDGE` (1e-7) either side, 0, and a mix (28 unique
  cases). The driver's `grid.mentorBonus` asks the real `Combat.MentorBonus`; the tool compares case by case, then pays
  each of the 11 boss kills with `mentor_pay` on the Luau's answers against `mentor_pay` on its own. The docstring
  lists it.
- `mirror_mutants.py`: three MentorBonus mutants (`<` made `<=`, the ratio ignored, one mentorValor whatever the head
  count), each caught.

### `tools/sim_combat.py`
- `mentor_pay(combat_cfg, members, tally, bonus_of=None)`: `bonus_of` stands in for `mentor_bonus` (the mirror's
  replay); default unchanged.
- `mentor_fixtures(combat_cfg)`: assertions 12 and 13's eleven boss kills in one list, read by those assertions and by
  check_stage_mirror (no hand copy); same kills, same verdict lines.

### `tools/sim_range.py` (F1)
- `DASH_PROOF_FRAMES` 2 (new constant, beside `DASH_TALLY`, documented against tests_l4b (a)).
- The claim and the hold: `start_dash` records a claim (window from the request, a proof time if its clamped path
  proves it, its lapse = `dashSeconds + shooting.originLagMaxSeconds`; none when the rule cannot be built) and opens
  nothing; `settle_claim` (first in `resolve`) opens the window from the request at the proof, or ends an unproven claim
  past its lapse; `awaits` is VitalsService's `awaitsDash` with its `met`; `hold` keeps a decision with what was found
  at its moment; `release` judges it once the claim is over (windows only, no knock, not if down, a barrage answered).
  `resolve` holds instant decisions (hit or miss) and `sweep` holds shot, charge and ring contacts (a held shot flies
  on). `rule` gains `knock=True`; `covered` is the windows half of `shielded`; `clear_threats` empties the holds; a
  boss's death keeps them.
- `DASH_TALLY` per policy is now [dashes, unproven, held then voided, held then judged unvoided]; the report says so.
- `dash_hold_probe` and one gate line in `check_threat`: a lunge decided in the frame of the press is dodged once the
  dash is proven (2 Heartbeats later), lands 0.467 s after the press when it is never proven (the lapse is 0.45 s),
  and at once with no dash. The review's suggested line "a dash begun in the decision's frame does not dodge" is
  the opposite of F1's rule and was not added.

### `tools/crowd_harness/tests_l1.luau` (slice 3 S2)
- realLevelTests: `table.concat(played, " ") == "forestRoad"` became "every level file is played by a map node, and
  was checked here" (1 today).
- realMapTests: `#bonus == 0 and map.themes.bonus == nil` became "every side node hangs off a level node and has a
  map theme" (0 today).
- No mutate entry depended on either (both read fixture data only; the one data-file entry is `combat.project.json`).

### `src/shared/Config/Missions/1_Village.json` (slice 3 S4)
- `waves` 3 -> 2: what a Forest Road clear counts (the Chief's Clearing's two waves). The hub card then reads
  "Waves cleared 2 / 2" after a clear, the tile "2 waves". W3 replaces the stub; the publish freeze holds.

### `docs/BALANCE.md`
- The W1b section's dash paragraph gains a correction; a new section "L4 W1b fix round: the dash held for its proof,
  and the gates it needed" with the changed keys, the mirror, the DASH PROOF table, the R8 row, the gates before and
  after, and every new gate and its mutants.

## For the other owners

Every line a new pin or mutate entry of mine reads, so an owner who changes one tells the designer (file; text, with
its indentation; `\t` = one tab):

- **luau-engineer A, `src/combat/server/Services/WeaponService.luau`:** as A relayed (`pins_lines.py.txt`,
  `mutate_entries.py.txt`), unchanged by me; plus `local function step(` / `function WeaponService.Start(` /
  `function WeaponService.GrantIframes(` / `local function pendingDash(` as body heads.
- **luau-engineer A, `src/combat/server/Services/DashProof.luau`, `VitalsService.luau`, `src/shared/RunFloors.luau`:**
  as A relayed; `src/shared/Combat.luau`: `\t\tif rate < threshold then`, `local threshold = hostRate *
  coop.mentorRatio`, `return mentored * coop.mentorValor` (mirror_mutants).
- **luau-engineer B, `src/combat/server/Services/ArenaService.luau` (`sendRunState`):** the eight lines above, as B
  gave them. **`WaveService.luau` (`payMentors`):** B's nine lines as given, plus `\t\tpayMentors(combatConfig,
  tally)` in `onCrowdKilled`.
- **ui-engineer, `src/combat/client/Controllers/CombatUIController.luau`:** `\tlocal function applyFloors(` and
  `\tlocal function onRunState(` (one tab, ending `\tend`), the nine lines and four orders above, and the moved_down
  anchor `\t\t\tpaintWallet()\n\t\tend\n` after the call.

## For the lead

- Nothing is needed in `src/shared/Economy.luau` or any `src` file.
- Slice 3 S4 changes what the hub shows: one tile now reads "2 waves" and the card "Waves cleared 2 / 2". The value is
  the contract's (L4B-1); I set it as the fix round said.
- Found, not changed (not in the round): realMapTests' `table.concat(open, " ") == "forestRoad"` ("forestRoad alone is
  open") pins today's map the same way. With a Castle level file, the Castle (requires forestRoad) is locked
  "needsNode" for a leader with no star, falls into `other`, and both that check and the next go red. A rule would be:
  a node with a level file and no `requires` is open, one with `requires` is locked by it.
- The simulator's two known gaps under F1 (BALANCE "What the mirror does not model"): the planner dates an unproven
  dash's hits at their decision, and a held hit released at a lapse goes before a decision queued earlier in the same
  frame. Neither can move a gated number while no simulated dash goes unproven.
