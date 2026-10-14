# L1b Wave 1 — the lead's routing list

Filled as owners report; routed after A and B finish (both edit Types/run files).

## From the ui-engineer (2026-10-14)
1. **Seated head vs the server's head** (a shot at a sitter's drawn head scores a body hit, aim
   assist pulls to standing height). **Ruling: accepted for Wave 1**, carried to L4 (a hit wakes
   the group, so only the first shot at a sitter is affected).
2. **Abandon under the left thumb on phones during a resident fight** (it hides only in `wave` and
   `boss`). **Ruling: fix in this wave.** RunState gains a per-member `engaged` flag (A: Types;
   B: set it from the crowd's "in play for a group in `rise` or `fight`", the same test L1b-20
   uses; ui: hide Abandon on touch while the local player is engaged). Route after A and B report.
3. "Checkpoint" shows on the HUD notice line instead of Toast: accepted.

## From luau-engineer A (2026-10-14)
- Accepted as built: Busy/Engaged count only groups with a living member; stop at half of
  `homeTolerance`; the held group's release step; CampBrain on `simTime`; `SetCampRules` refuses
  rules `Problems` objects to.
- Relayed to B: register A's 36 mutations, replace 11 stale ones, FILES + FLOOR/DIED constants.
- Relayed to the economy-designer: mirror the stop distance, release step, clock, heal-before-Step.
- **Abandon fix, step 1 done by the lead:** `Types.PartyMember.engaged: boolean?` added. B sets it
  in `ArenaService.memberEntry` from `CrowdService.Engaged` (sent). Step 2 (ui, after B): hide
  Abandon on touch while the local member's `engaged` is true.

## After B (continued) reported (2026-10-14)
- B green: harness 1,531 checks, mutations 495 / 0 not caught. `PartyMember.engaged` filled via
  `ArenaService.SetEngagedSource`, wired in `WaveService.Init`.
- **Abandon fix, step 2 done by the lead:** `CombatHud.luau` hides Abandon on touch while the local
  member is `engaged` (one-file fix; stylua, selene, check_compile pass).
- **Lead fix:** `ReturnService.luau` dropped the stale `savedAt = ""` (RunResult lost it).
- Carried: the director's merge test reads too few dead bodies while a locking camp's residents
  live (no Wave 1 effect: camp C does not merge, the arena has no residents). Owner: B, Wave 2.
- Contract note: `StageFlow.Plan` takes a sixth argument `ranks?` (minDifficulty needs it).

## After the economy-designer reported (2026-10-14)
- **Ruling: Wave 1's Normal clear band is 2.5–4 min** (option c). L1's camp sizes cap the residents,
  so a clear is about 3 min (measured 2.98–3.18); Wave 2's size brings the ~10 min band back.
  `sim_range --check` PASS after the change.
- Noted for Wave 2's balance: a Normal clear pays 60,800 cash / 129 Timber / 10 Valor (L1 88,200 /
  155 / 10) because fewer raiders exist; per-kill pay is unchanged.

## Review rulings (2026-10-14)
### Client slice (0 Critical, 2 Major, 3 Minor; docs/prompts/l1b-w1-review/client.md)
- Major 1 (phone auto-fire wakes camps from range, BLOCKED loop): **fix on the client**, L1b-4
  stands (a deliberate far shot that wakes a camp is the player's choice; auto-fire is not).
  Auto-target picks a camp body only when the local player stands in that body's floor rectangle
  grown by `camps.chaseMargin` (in-play), never a `rest`/`rise` body otherwise.
- Major 2 (header cut off): text becomes "Camps 1 / 3".
- Minors: fix all three (Abandon flicker at the edge: a short hold before it reappears; release
  CampFx's Heartbeat connection; clear the Checkpoint notice on summary/lobby).
### Run slice (0 Critical, 1 Major, 2 Minor; docs/prompts/l1b-w1-review/run.md)
- Major (a downed party member stays down the whole road): **a downed member stands up when the
  road's field is clear** (L1b-19's definition: no group in `rise`/`fight`/`home`, nothing queued),
  outside the locking camp's fight; pure rule in StageFlow with a harness case and a mutation.
  Revive by a teammate stays L5.
- Minor (a skip runs `campCleared`): fix: a Studio skip's `open` neither pays the clear bonus nor
  adds to `stats.wavesCleared` ("a skip pays nothing").
- Minor (no gate pins progress in every live phase): add the harness case + mutation that limiting
  `progress()` to travel/armed is caught.
- Passed to the crowd slice: a group whose mind stays "striking" could keep a floor busy for good.
### Data and tests slice (0 Critical, 0 Major, 8 Minor; docs/prompts/l1b-w1-review/data.md)
- Minor 1 (A's checkpoint 44.6 studs from B.fire1's Hard marksman): **B:** `StageFlow.SafePoint`
  skips a checkpoint within the longest attack reach of a living member of any group in
  `rise`/`fight` (harness case + mutation). **economy-designer:** a `check_levels.py` gate that
  every checkpoint lies outside every resident shooter's reach from its post, at every difficulty.
- Minor 2 (chaseMargin gate edges only): fix now, corners included (reach − radius measured on
  the diagonal); perches inside the margin gated too.
- Minor 3 (clearBonus mirrored half): mirror it fully in `sim_range.on_open` and
  `sim_combat.level_pay`; prove it with clearBonus > 0 in a scratch run.
- BALANCE "L1b": show the 2.5–4 min band as the lead's ruling and PASS.
- Hard patrol mixing speeds: walk a patrol at its slowest member's pace (economy-designer: data or
  report to B if the executor needs it).
- No checkpoint before camp A: accepted (the start is the safe point).
- Post spacing gated only round fires: carried to Wave 2 (economy-designer).
- Timber per minute up ~75% on L1: told to Ben at the stop.
- Checklist steps 3 and 5: the lead edits INTERFACES (step 3: run well past a slinger's 32 studs;
  step 5: N puts you inside the Chief's Clearing with the countdown running).

## Fix round, ui reported (2026-10-14)
- All five client items done (fix-ui.md). Carried to Wave 2 (ui + A): during the boss room's
  3-second countdown a phone's auto-fire can target held residents (cosmetic "BLOCKED"; the wire's
  `rest` state could exclude them on the locking floor); a shared pure flat-distance-to-rectangle
  helper so CampBrain and InputController use one tested function.

## Fix round finished (2026-10-14)
- A (fix-A.md), B (fix-B.md), ui (fix-ui.md), economy-designer (fix-econ.md) all green.
- Lead confirms B's choice: a downed member stands up at the safe point, not where they fell.
- docs-keeper: INTERFACES L1b text gains `SafePoint(..., busy?, threats?)`, `StageFlow.StandsUp`,
  `StageFlow.LongestReach`, `Action.skipped`, `CampBrain.Engaged`, `camps.engagedHoldSeconds`,
  `chaseMargin` 2.5 with the rounded in-play test; B's residents moved (Hard marksmen to
  southWatch, the lobber to fire3, the patrol's Hard plated elite to fire1).

## Fix-diff review and QA (2026-10-14)
- Fix-diff review: Critical 0, Major 0, Minor 2 (fix-diff.md). QA (qa-runner): ALL GREEN, harness
  1,571 checks, mutations 513 / 0 not caught.
- Lead fixed both Minors: phone auto-fire also picks camp bodies while the local member is
  `engaged` (a slinger's reach counts), via `InputController.SetPhase(phase, waiting, engaged)`;
  `sim_range` stands a downed player up in `gate` too, as `StageFlow.StandsUp` does. Re-ran stylua,
  selene, check_compile, luau-lsp (combat), check_stage_mirror, sim_range --check: all PASS.
- Carried to Wave 2 (economy-designer): `check_stage_mirror` compares `StandsUp` (today it compares
  `FieldClear`, which `StandsUp` composes).
