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
