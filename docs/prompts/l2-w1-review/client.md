# L2 W1 review: client slice

Reviewed `main..l2-secrets` at 6feb088 (worktree `tycoon-p5`). Read in full: MovementController (jump, Leap,
knock), InputController (groundPoint, applyCast, castAbility), CombatUIController (L2 wiring, keys, CombatFx
routing), SecretFx, AbilitiesPanel, CombatHud, DebugPanel, MapScreen, Theme (L2 block); plus WallClip,
Unlocks, WeaponService.GroundPoint, UnlockService.publish/ResetSecrets, WaveService.announceSecret/ForgetSecrets,
LevelService folders, VitalsHud placement, CombatFxController dispatch.

Gates on a `git archive HEAD` copy: stylua clean, selene 0/0, `check_compile` PASS (164 files), luau-lsp clean
on both trees (combat map: `src/combat/client src/shared`; hub map: `src/client src/shared`).

**Verdict: 0 Critical, 0 Major, 7 Minor.**

## Verified (what the focus asked)

- **Air jump refusal.** `UserInputService.JumpRequest` -> `onJumpRequest` is the only air-jump path. No other
  client file calls `ChangeState(Jumping)` or writes `JumpHeight`/`Jump` (grep over `src/combat/client` and
  `src/client`). Keyboard Space, gamepad A and Roblox's touch jump button all arrive as JumpRequest. The check
  `GetAttribute(Ability_doubleJump) ~= true` runs after the fresh/airborne/`airJumpDelay` guards and before
  `airJumpUsed = true` (MovementController.luau:457-470), so a refused press costs nothing and a mid-air grant
  works on the next press. The ground jump is the stock Humanoid jump; `onJumpRequest` returns before the
  attribute check whenever the player is grounded. The hint fires once per session, never in the range.
- **The rise mirror.** The client (`InputController.luau:1867-1880`) and the server (`WeaponService.luau:2562-2573`)
  compute the same thing:
  - the same `== true` read of the same attribute;
  - the same `WallClip.Rise(Tuning.Get().movement, airJump)`;
  - the same `CasterFloor(probe at the root, root.Y - (HipHeight + Size.Y/2), rise)`;
  - the same target probe (lifted by `GROUND_PROBE_LIFT`, `GROUND_PROBE_DEPTH` 250);
  - the same `TooHigh(casterFloor, floorY, rise)`.

  The only difference is `Players.LocalPlayer` against `player`. The column SecretFx adds is `CanQuery = false`
  (`CanCollide = false` first), so neither ray meets it.
- **The leap with `casterFloor`.**
  - `groundPoint` returns `(nil, floor)` when it refuses, and `castAbility` returns on nil before anything is sent.
  - `Leap` is called only from `applyCast` with a resolved target. The `0` default is never read.
  - `standingOffset` (`HipHeight + Size.Y*0.5`) matches the feet term in `groundPoint`.
  - A cast from the ground gives `floor + standing = from.Y`, so `LeapApex` equals the old `max(from, to) + lift`.
- **Purchase feedback and the 3 s timeout.**
  - Buy re-checks open, lobby, pending, owned and Valor.
  - A failed send toasts "Try again". Otherwise the button reads "Buying..." until the `buyAbility` result.
  - The timeout is tokenised, so an old timer cannot free a newer wait.
  - Ok gives the toast and the row reads Owned through `learned` until the Snapshot. The four refusal texts
    match L2-10.
  - The toast is `ZINDEX_TOAST` 30, above the panel's scrim at 15.
- **Panel layout.**
  - At 667x375 under the inset: scale 0.917, sheet 312 px wide, list room 239 design px against one 68 row,
    Buy and X 44 px.
  - At 375x667 portrait: scale 0.917 (the inset pulls it under 1), 312 of 375 px.
  - At 640x360: fits.
  - The hint line exists only with a keyboard.
- **SecretFx with a reset and a new run.**
  - `Workspace.Level` is one folder that lives all session (`LevelService.Init`). `Secret_<id>` Parts are its
    direct children, so ChildAdded and ChildRemoved see every rebuild.
  - The H lever makes the server send a Snapshot (`UnlockService.ResetSecrets` -> `SendSnapshot`). `SetFound` then
    clears `announced` and repaints, so the column comes back and the tint is undone.
  - A new run of the same level adopts fresh Parts painted from the current found set.
  - `paint`'s early return cannot strand a chest without a column.
- **The map's secrets row fits the card.** The open card holds:
  - with Return: 10 + 20 + 6 + 24 + 6 + 52 + 6 + 16 + 6 + 16 + 6 + 30 + 6 + 48 + 6 + 48 + 10 = 316 design px;
  - the card's room at 667x375 under a 58 px inset is 329.7, and 337 with a 36 px inset;
  - the key line only with a keyboard: 336, which ends 6 px into the margin (the engineer's figure; cosmetic);
  - three cells of 50 fill the 150 px icon column exactly.
- **Studio keys.** J, H and V are behind `studio` and `requestDebug`, and K, H, J and V are bound nowhere else.
  The key handler drops chat input (`processed` or a focused TextBox). The range boot gets neither the keys nor
  the strip buttons.
- **CombatFx routing.** The second `OnClientEvent` connection passes only `kind == "secret"` to SecretFx
  (`OnFx` re-checks it). `CombatFxController.applyFx` ignores unknown kinds, so `secret` is harmless there.

## Minor

**m1. The wider button row now overlaps two things on phones** (`CombatHud.luau:499-505`, `547-550`; `Theme.luau`
`COMBAT_ABILITIES_BUTTON_WIDTH`).
- What: Map 72 + Abilities 88 + Return 104 + two gaps = 280 design px, from 184. Return moves 88 design px right.
- Landscape 667x375 (scale 0.917):
  - Return spans x 168.7–264.0, y 320–364.
  - The health bar (`VitalsHud.luau:327-348`, the inset-free `rangeGui`, shown in the lobby) spans x
    241.8–425.2, y 349.3–365.8.
  - Return (ExpeditionHUD, DisplayOrder 1) therefore covers the left 22 px of the bar, its low-health end, on
    every phone in the lobby. Before L2 the gap between them was 66 px.
- Portrait 375x667:
  - Return spans x 168.7–264, y 612–656.
  - MovementController's always-shown Dash button spans x 215.6–271.6, y 584–640.
  - Return is drawn above it, so a dash tap on the left 48 px of the Dash button in the lobby fires
    `RequestLeave`, which has no confirm, and sends the player to the city.
  - Today StarterGui keeps Roblox's default LandscapeSensor (nothing in the project files sets
    ScreenOrientation), so this case appears only in the emulator or after an orientation change.
- **`proving.rbxl` hides Return (`runButtons = not proving`), so Ben's emulator look in PLAYTEST step 5 cannot
  show either overlap.** The ui report's checklist line "the Abilities button sits between Map and Return" also
  cannot be seen there.
- Fix: give the row a right limit. Either put Abilities on a second row above Map (the stack already has slots
  above it), or cap the row at `min(vitals left, clusterLeft) - gap` and shrink to two buttons per row past it.
  Then re-check at 667x375 with Return visible (a non-proving build).

**m2. A gamepad has no way into the panel except Roblox's own UI navigation** (`CombatUIController.luau`
`toggleAbilities` and the K key; `AbilitiesPanel.luau:403-430`).
- What:
  - The only entry points are K and the HUD button. A gamepad reaches the button only through the Select-button
    selection mode.
  - Nothing sets `GuiService.SelectedObject` to Buy or X when the panel opens.
  - ButtonB is the dash (bound at High priority by MovementController), so B does not close the panel.
  - The map, open by default in the lobby, binds the d-pad and A while it is open.
- Scenario: a console player cannot buy Double Jump without discovering the Select button, then backing out of
  the map, then navigating to "Abilities".
- Fix:
  - Add a lobby-only gamepad binding to toggle the panel (for example ButtonY in the lobby phase only, or a
    d-pad key the map frees once it is closed).
  - On open with the last input a gamepad, select the first live Buy, else X.
  - While the panel is open, bind ButtonB to close it above the dash's priority.

**m3. A jump pressed late after walking off an edge is now lost, and it fires a misleading hint** (`MovementController.luau:455-469`).
- What:
  - Roblox has no coyote time.
  - Before L2, a press more than `airJumpDelay` (0.12 s) after leaving a floor without jumping became the air
    jump (12 studs), which forgave a late press.
  - Now a non-owner gets nothing, and the first such press of the session toasts "Double Jump: buy it in the
    lobby (K)".
- Scenario: the first jump task of Forest Road is the 12-stud gap Road1 -> Road2 (x −436..−424, void below,
  `route` leg "gap"), 34 studs from the start.
  - A first-run player who presses late falls, is rescued to the start, and is told to buy Double Jump.
  - That message says the main path needs it, which L2-5 rules it never does.
  - Presses under 0.12 s late were already dropped in L1 by the `airJumpDelay` guard, so this changes only the
    later ones.
- Fix:
  - Either add a small walk-off window (`movement.coyoteSeconds`, config): a press within it, when the body
    left the floor in Freefall without a Jumping state, is the ground jump (`jumpHeight`), not an air jump.
  - Or at least suppress the hint for presses within that window, or within N s of a walk-off.
  - Either way, worth one line to Ben at the one-jump look (L2-21).

**m4. The client half of the ground rule is a copy that no gate compares** (`InputController.luau:1867-1880`
against `WeaponService.luau:2562-2573`).
- What: the two step-4 blocks are identical today, but only `WallClip.Rise`/`CasterFloor`/`TooHigh` are under the
  harness. A drift in the client copy passes every gate (harness, `check_stage_mirror`, `check_levels`). Examples:
  - `~= false` for `== true`;
  - dropping `CasterFloor` for the old `or feet`;
  - passing `rise` 30.

  The only symptom would be a predicted leap that the server refuses (no ability, a client-only move) or a
  refused cast that the server would allow. This is the "pure query the mirror does not compare" pattern from L1b.
- Fix: one pure `WallClip.GroundFloor(probedCaster: number?, feetY, probedTarget: number?, movement, airJump)
  -> (floorY?, casterFloor)` called by both sides, with a harness case and a mutation.

**m5. The ability id cap is duplicated** (`AbilitiesPanel.luau:74` `MAX_ID_LENGTH = 32` against `CombatRemotes.luau:46`
`MAX_ABILITY_ID_LENGTH = 32`).
- What: the same structural limit lives in two places. If the server's limit drops, the panel offers an id the
  validator then silently drops: no ActionResult, a 3 s "Buying..." and nothing else.
- Fix: one home, `Unlocks.MAX_ID_LENGTH`, read by both.

**m6. Map key words and the panel hint are too small on phones** (`Theme.luau:1354` `MAP_SECRET_KEY_TEXT = 9`,
`1341` `ABILITIES_HINT_TEXT = 10`).
- What:
  - At `MIN_SCALE` the keys under the secret icons ("2× JUMP", "FIRE", "ICE") render at 8.25 px.
  - Those words are the only place the map tells a player what to bring.
  - The hint line exists only with a keyboard, so it is PC-only and that one is fine.
- Fix: 11 or more (one line in a 30 px row still fits: 16 icon + 11 + 3).

**m7. Two smaller notes** (record only; no action unless the owners disagree).
- **The centre card covers the crosshair.** `SecretFx.luau:245` puts the 3 s found card (about 275x110 px on a
  667 phone) over the crosshair, during a live run, on the chase region by camp A, where Wave 4 raiders follow a
  player anywhere on the road.
  - The contract says "centre card", so this is not a defect.
  - Lifting it into the band above the crosshair (the boss bar's band when no boss is up) would keep aim clear.
- **An enemy launch re-lifts a body in the air** (`MovementController.luau:1051-1065`).
  - `velocity.Y = max(velocity.Y, jumpSpeed(launch))` with every launch at 3 studs (`ProvingGrounds.json`).
  - At a jump's apex, one launch gives 18 + 3 = 21, under the ledge's 26 even with `STEP_UP` 3. Two launches
    about 0.2–0.35 s apart give 24 + 3 = 27.
  - L2-18(b)/(c) model jumps, dash and abilities, not enemy launches.
  - It is contrived (two hits at the apex, at the ledge face, far from A's edge) and a cheat gains nothing that a
    hit costs less than. For the data slice to rule on, not a client change.

## Not findings (checked)

- The Abilities panel is lobby-phase only, while the server's `MayLeave` also allows a member waiting in the
  lobby camp during a live run. This matches L2-10 ("lobby only, like Map"); the ui report states it.
- A stale "Buying..." after a dropped request (token bucket) clears in 3 s, and a second Buy then answers
  "Already yours" if the first did land. Cosmetic.
- The new sizes (48 px Buy, 48 px X) equal `ROW_BUTTON_HEIGHT`, so `MIN_SCALE`'s derived minimum is unchanged
  without adding them to its list.
