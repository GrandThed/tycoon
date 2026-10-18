# L2 W2 review: client slice (2026-10-18, `main..l2-w2` at 0f78d30)

Scope: everything changed under `src/combat/client/` plus `src/client/UI/Theme.luau`. On a `git archive HEAD` copy:
stylua clean, selene 0/0, luau-lsp (combat sourcemap) exit 0, `check_compile` PASS (172 files).

**Totals: 0 Critical, 2 Major, 8 Minor.**

## Major

**M1. On a phone the bramble can never be burnt, so the tunnel, the cache and the shortcut are out of reach on touch.**
`src/combat/client/Controllers/InputController.luau:1297-1298` (`targetOnAuto`, capsule branch), with
`wantsRangeAttack` :1325-1348.
- What: `touchMode` is `"autoFire"` (ProvingGrounds.json :296). On touch, a press only records `rangeTouches`, and
  `tapQueuedAt` is set only in `tapFire` mode (:2234), so `rangeHeld` never goes true on a phone. The stream then
  fires only when `targetOnAuto` finds a crowd body inside the capsule. A bramble is not a body. Dragon's Breath
  cannot burn it either (L2-34: `WorldReact.Touches` is false for cones).
- Scenario: a phone player owns the Flamethrower, equips it and walks to the bramble at Road4's mouth. Nothing fires.
  The bramble lies more than 60 studs from every Pickets group (contract §5), so no raider is ever in the capsule
  beside it. The Raiders' Tunnel, the cache's 4 Valor plus 60 Timber and the shortcut cannot be had on touch. The
  exit bramble on RoadAB5 fails the same way. Brief item (7) and Ben's rule "phones must work from P1" are broken.
  No on-screen attack button is allowed ("criminal").
- Fix: make auto-fire take a reactive Part as a target.
  - Under `Workspace.Level`, find a Part whose `React` attribute equals the held family's element
    (`Unlocks.ElementOf`, which the server reads) and whose `Heat` is still below 1.
  - It counts as a target when the shared pure `WorldReact.Touches` returns true for
    `{ shape = "capsule", origin, direction = look, size = range cut at the first wall, width }` against its box,
    padded by `levels.react.pad`. That is the server's own test. The bramble is itself the wall, so the cut ends on
    its face and the test holds.
  - Keep the existing refused-body hold, so a resting group in the capsule still holds fire.
  - Add a harness check of the client rule, and a PLAYTEST phone step: "burn the bramble in the 667 × 375 emulator".

**M2. The local flame is drawn about 40% of the length the server hits, and shorter still when zoomed out.**
`src/combat/client/Controllers/FlameFx.luau:308-315`.
- What: the local stream casts its wall ray from `CameraController.GetAimRay()`'s origin, which is the camera, for
  `stream.range`. The server's capsule starts at the shot origin, which is the crosshair line at the head's depth
  (`InputController.shotRay` :1082). It runs `range` from there, cut by `worldReach` (WeaponService :427-438).
  - The camera sits about `defaultZoom` 11 studs behind the head along the look (Combat.json :197).
  - So the local tip is camera + 20, about 9 studs past the head and about 8 past the hand.
  - At `maxZoom` 16 the local tip is about 3 studs past the hand. In ADS it grows.
  - Other players' streams use the server's `size` and are drawn at the full 20.
- Scenario: Ben holds fire at a raider 15 studs away. The flame stops at about 8 studs, yet tick numbers keep
  appearing on the raider well beyond the visible tip. A wall 12 studs ahead is never reached by the drawn flame,
  although the server stops there and burns the bramble.
  - PLAYTEST step 3 ("the stream reaches about 20 studs, stops at walls") fails on sight.
  - A partner sees the same player's flame twice as long.
- Fix: start the ray at the shot origin, `aimOrigin + look * math.max((head - aimOrigin):Dot(look), 0)`. Expose
  `InputController.ShotRay()` rather than copying the formula. Cast `look * range` from there; the tip is that start
  plus the hit distance. Then `reach = (tip - from):Dot(look)` from the hand, as now.

## Minor

**m1. `openPivot` pulls the pivot back along a thin ray, so the camera's spherecasts can still start inside a wall.**
`src/combat/client/Controllers/CameraController.luau:438-453`.
- What: the pivot is placed 0.7 studs back along the ray from the head. When the ray meets a surface at an angle θ,
  the pivot ends up 0.7·sin θ from that surface. Below about 45° that is under the spherecast radius of 0.5. A
  `Spherecast` does not report parts it starts inside, so the shoulder and boom casts both ignore the surface.
- Scenario: the pivot trails behind a Leap Smash at the exit leg's inner corner (`CaveWallExitLegE`, 2 studs thick).
  The ray crosses the wall at a shallow angle, and the boom then passes through the wall: the view from outside the
  ridge that the fix was meant to stop. This is rare: it needs flat lag, which only motion abilities make, plus an
  oblique hit.
- Fix: `Workspace:Spherecast(head, COMBAT_CAMERA_COLLISION_RADIUS, offset, params)` with
  `keep = hit.Distance - COMBAT_CAMERA_COLLISION_PAD`. The head has at least 0.5 of clearance wherever a body stands.
- Cost note: the report says "ordinary play costs nothing". In fact `followHeight` lags on every jump, fall and
  slope, so the ray runs on those frames too. That is one raycast a frame, which is negligible. Correct the report,
  not the code.

**m2. A gamepad's selection can be lost after an Equip.** `src/combat/client/UI/ArmoryWeapons.luau:347-348` and
:503-512; `ArmoryPanel.luau` has no re-select.
- What: a pending pick or a held button gets `Selectable = false`. The button just pressed with A becomes "Equipped"
  and stays unselectable. When a family is granted or removed, `rebuild` destroys the selected button outright. The
  panel only re-selects on open and on a tab switch.
- Scenario: on a pad, A on Flamethrower "Equip" leaves the selection on a dead button or on nothing. The left stick
  then walks the character behind the scrim. The only way back is B and Y.
- Fix: when the panel is open and the last input was a gamepad, re-select `firstSelection()` after `OnResult`,
  `SetLoadout` and `refresh` if `GuiService.SelectedObject` is nil, unselectable or outside the sheet. Check in
  Studio: does the engine drop a selection whose `Selectable` turns false? This is the same open question as W1's
  "does A on Buy also jump".

**m3. Any `setFamily` answer clears whatever pick is pending.** `ArmoryWeapons.luau:568-570`.
- What: a late answer to a pick that timed out after 3 s also clears a newer pick's wait. The newer pick's buttons go
  live while its own request is still in flight.
- Scenario: a second tap sends a second `RequestSetFamily`. The server stays authoritative, so this costs two toasts
  and a rate-bucket token.
- Fix: clear `pending` only when `payload.slotId == pending.family`.

**m4. The phone auto-fire capsule is not cut at walls; the server's is.** `InputController.luau:1297` uses the full
`variant.range`.
- What: an awake raider within 20 studs behind a wall or fence starts the stream into the wall. Likewise a resting
  body behind a wall holds fire on an awake one in front.
- Fix: cut `range` with the same `RespectCanCollide` wall ray before the capsule test. M1's fix needs that cut anyway.

**m5. The bramble's collapse and the flame's flicker are gated on `Theme.reducedMotion`, which is true on every
touch device** (`Theme.luau:1486`).
- Where: `ReactFx.luau:177`; `FlameFx.luau:258`.
- What: phones only ever see the bramble fade, never shrink. The living-city ruling gates effects on `lowEndDevice`
  for exactly this reason.
- Fix: gate on `lowEndDevice`, or keep the 0.7 s shrink everywhere. It is a one-off cue that the way is open, not
  ambient motion.

**m6. The local flame lingers for a round trip after the trigger is released.** `FlameFx.luau:328-348`.
- What: the local player's own server strikes refresh `lastAt`. The local stream therefore stays for the RTT plus
  0.25 s after the last shot, and keeps swinging with the live camera although no shot is being sent.
- Scenario: at 150 ms ping, the flame visibly follows a turn for 0.4 s after letting go.
- Fix: for the local userId, let `OnStrike` correct only `width`. Local shots alone keep the stream alive.

**m7. One rule, two constants.** `Theme.luau:1413` `LOBBY_ARMORY_RESULT_TIMEOUT_SECONDS = 3` duplicates :1343
`ABILITIES_RESULT_TIMEOUT_SECONDS = 3`. Both tabs answer to the same "3 s at most". Fix: keep one.

**m8. Stale comments.** `CombatHud.luau:78-79` still name `deps.onAbilities`, `deps.abilitiesKey` and the Abilities
panel. `CombatUIController.luau:107-112` still says K opens "the Abilities panel".

## Verified (no finding)

- **Panel sizes.** `hudScale` reads 0.9167 on all three phones. Without a hint row (touch), the sheet's fixed part is
  74 design px and the Weapons page is 190 (two ranged cards).
  - 667 × 375: the sheet is 264 design px = 242 px of the 317 below the top bar.
  - 640 × 360: 242 of 302.
  - 375 × 667: 312 px wide.
  - Tap targets: tabs 99 × 44, close 44 × 44, Equip 135 × 44, variant buttons 65 × 44 px.
  - "Flamethrower" plus the FIRE chip fits the 147-wide card. "Hidden on Forest Road" wraps inside 48.
- **Gamepad.** Y (lobby), B and LB/RB are bound at `High + 1`. The run binds R1/L1/Y at `High`
  (InputController :2318-2334) and the dash on B/X at `High` (MovementController :937-946), so the panel wins.
  Everything is unbound on close and on `SetLobby(false)`. ButtonX still dashes under an open panel, as in W1.
- **3 s timeout.** The token-guarded `task.delay` in both tabs frees the buttons. A rate-limited call that never
  answers is covered.
- **TuneState.** In a mission the only `SetTuneStateHandler` is the Armory's (the range sets its own in `bootRange`).
  It is seeded once at boot.
- **F lever.** It sits behind the `studio` check in `onKey`, after K. It exists in `bootMission` only (not the range).
  It reads the family from config, not a constant.
- **ReactFx.**
  - `Workspace.Level` is made in `LevelService.Init`. `React` and `Heat` are set before the Part is parented, so the
    first `ChildAdded` sees them.
  - `Clear` → `ClearAllChildren` → `forget`, so every run starts from a fresh Part with its own colour.
  - Burn effects are anchored, with CanCollide, CanQuery and CanTouch off, gone within 1.6 s.
  - Burn effects are ignored by FlameFx's `RespectCanCollide` ray.
- **The camera in the tunnel.** Walls, roof and brambles are colliding, queried Parts. Interior: mouth leg 22 high,
  tunnel 14, walls 2 to 4 thick. The spherecasts stop the boom 0.7 inside them. The default zoom only meets the roof
  when the camera is pitched about 53° or more.
- **W1 not regressed.**
  - MovementController is untouched; only the hint text changed.
  - Chest cards keep the measured `fitRow` heights. The 50-character family note wraps and is measured.
  - The shortcut card uses the same path. Its CombatFx carries every field `SecretFx.OnFx` checks (WaveService
    :2035-2047).
- **Dragon's Breath.** Its strikes skip the stream path (`beamWeapon` requires `ability == nil`), so Feedback still
  draws each cone. `busySecondsOf` aliases it. No other client code chooses by `slugBurst`.
