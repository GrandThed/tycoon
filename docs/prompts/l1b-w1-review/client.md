# L1b Wave 1 review — slice 3, client

Read-only review of `git diff 8e8990c e2479c3` for `src/combat/client/**` and
`src/client/UI/Theme.luau`, against INTERFACES "L1b contracts" (Client, rulings L1b-1 … 24) and
the routing list's rulings (Abandon hidden on touch while `engaged`; seated head accepted;
"Checkpoint" on the HUD notice line accepted). I also read `InputController` (unchanged, but it
reads the crowd through `CrowdRenderer.ForEach`) and the server's `CampBrain.Shows` and
`WaveService.onGroupEvent` to check what the wire says. `py tools/check_compile.py --counts`:
PASS. The largest client files are CrowdRenderer 152, InputController 146 and
CombatFxController 126.

## Major

1. **`src/combat/client/Controllers/InputController.luau:1151-1167` (`targetOnAuto`, through
   `CrowdRenderer.ForEach`, `CrowdRenderer.luau:2732`). Touch auto-fire shoots residents the
   player cannot hurt, and every shot wakes their group.**
   - The cause:
     - `controls.touchMode` is `"autoFire"` (`ProvingGrounds.json:288`), so on every phone a
       gun or bow fires by itself, or a bow draws, whenever any living, drawn crowd body is
       within 5° of the reticle and inside the weapon's range.
     - `ForEach` reports every body except the dead: resting sitters, guards, patrols, groups
       walking `home`, and the boss room's `held` residents.
     - L1b-7 answers any hit from a player out of play with "blocked", and L1b-4 says that hit
       still wakes a resting group.
   - The scenario: a phone player walks the road toward camp A with a Longbow and the camp
     ahead in the crosshair, well past `chaseMargin` (3).
     - The bow draws and looses on its own. "BLOCKED" shows, and the group gets a "!" and
       rises before the player chose to engage. That is the first strike L1b-5 and checklist
       step 2 promise, gone.
     - With no target in play the group leashes after 3 s and goes home. It is back at rest at
       once, because it never left its posts. The next auto-arrow wakes it again.
     - This repeats for as long as the reticle rests on the camp: an endless "!" and "BLOCKED"
       loop.
     - The same thing happens at camp C: auto-fire at the held residents through the gate (and
       inside it during the countdown) shows a stream of "BLOCKED".
   - Ben's "sneaking is allowed" (§16, L1b-5 of the rulings) cannot hold for a phone player in
     Wave 2 either.
   - Fix (client only): let auto-fire and auto-swing consider only bodies the local player is in
     play for. Either:
     - have `CrowdRenderer` expose each body's `floorIndex` (or add a `ForEachInPlay(root)`), and
       have `targetOnAuto` skip a body whose known floor rectangle, grown by
       `Combat.json camps.chaseMargin`, does not hold the local root. This is L1b-6's first
       clause; leaving out the keepAway reach clause only makes it more conservative. Or:
     - at least skip wire states `rest` and `rise`.

     A body on an unknown floor, and the range, keep today's rule.

2. **`src/combat/client/UI/CombatHud.luau:1025` (`campText`), drawn in `aliveLabel` (`:331`,
   `headerRight`, 74 × 16 design px, `TEXT_SMALL` 12, GothamMedium, `TextTruncate.AtEnd`, not
   `TextScaled`). The contract's dim line "Camps cleared 1 / 3" cannot fit its label on any
   screen.**
   - The 19 characters need about 110–120 px at 12 px Gotham. At most 74 px is possible: that
     would be 3.9 px a character.
   - L1's "Camp 2 / 3" was about 63 px. The header's UIScale scales the box and the text
     together, so every device truncates the same way.
   - The scenario: Ben departs for Forest Road and the header's right reads "Camps cle…" for
     the whole run. The only on-screen count of the level's progress has lost its number.
   - Fix: use a text that fits the 74 px box, such as "Cleared 1 / 3" (about 75 px, tight) or
     "Camps 1 / 3" (about 70 px). Or, in a level of several camps, widen `aliveLabel` and narrow
     the objective line by the same amount. Check it at 667 × 375.

## Minor

3. **`src/combat/client/UI/CombatHud.luau:1181-1184` (`underThumb`). Abandon comes back under
   the left thumb the instant `engaged` drops, and a fight at a camp's edge toggles it.**
   - The server's `engaged` is "in play for a group in `rise` or `fight` *at the last step*".
     A player who steps 3 studs past the margin, which is checklist step 3 and the natural way
     to kite on a phone, is no longer engaged.
   - So at 4 Hz the button appears and disappears under a thumb that is working the move
     stick, while the group is still in `fight` for `leashSeconds` and shooters may still be
     in reach.
   - The hazard the fix round removed for `wave` and `boss`, a re-landed thumb pressing the
     button twice, is back at every camp edge.
   - Fix: keep the button hidden for `Combat.json camps.leashSeconds` (plus a beat) after the
     local member was last `engaged`, with the stamp held in `objective`.

4. **`src/combat/client/Controllers/CampFx.luau:162-164`. The Heartbeat connection is made on
   the first alert and never released.**
   - Nothing calls `CombatFxController.Destroy` (`Main.client.luau` only runs Init and Start),
     so `CampFx.Destroy` never runs either.
   - The cost is one empty Heartbeat callback per frame for the session. It is harmless, but it
     goes against "no leaked connections".
   - Fix: disconnect in `step` when `#marks == 0`. `Alert` already reconnects on demand.

5. **`src/combat/client/UI/CombatHud.luau:1317-1321` (`ShowNotice`). The notice line ignores
   the run layer's visibility.**
   - A checkpoint reached less than 2 s before the run ends, or before the map opens, leaves
     "✓ Checkpoint" over the summary scrim or the map for the rest of its 2 s.
   - Fix: hide `noticeFrame` (and zero `noticeUntil`) in `setRunState` when the phase is not
     live.

Not mine, for the other slices:
- run: for finding 1, the server could also leave a resting group asleep after a blocked hit
  from a player outside `sightBelow`/`sightAbove`/`sight`. This would be a contract change to
  L1b-4 and is for the lead.

Critical 0, Major 2, Minor 3
