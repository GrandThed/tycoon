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
