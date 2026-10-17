# L2 W1 — ui-engineer report (2026-10-17)

Branch `l2-secrets` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing committed.

## Files created or changed (all in my contract §8 list)

- `src/combat/client/UI/AbilitiesPanel.luau` (new, 20 top-level locals). Lobby-only sheet over a
  scrim. `AbilitiesPanel.Offers(expeditions)` reads `abilities.list` and filters it with the
  server's own `Unlocks.DefProblem`, sorted by `order`. If an id appears twice, only its first
  entry counts, as in `Unlocks.Find`. Each row shows the name, the text, "10 Valor", and one of
  Owned / Buy / "Need N more Valor". Buy fires the intent, then reads "Buying..." and stays
  quiet until the `buyAbility` ActionResult arrives, or for 3 s at most. On ok: toast
  "Double Jump learned!". Refusals: owned "Already yours", busy "Only in the lobby",
  insufficientFunds "Not enough Valor", anything else "Try again". It closes on K, Esc (also
  when Roblox's menu opens), its X, a tap on the scrim, and when the phase leaves the lobby. It
  makes no sound.
- `src/combat/client/Controllers/SecretFx.luau` (new, 34 locals).
  - It watches `Workspace.Level` for `Secret_<id>` Parts and skips `_Sign`.
  - An unfound chest gets a Neon light column parented under its Part. The column has
    CanCollide, CanQuery and CanTouch set to false.
  - A chest counts as found when the Snapshot's `combat.secrets` has it, or when the `found`
    event names it. A found chest takes the `secretOpen` look (fallback: gold) and loses its
    column. A Studio reset restores the look and the column.
  - `found` for the local player: a burst (skipped when `Theme.lowEndDevice`) and a centre card
    for 3 s: "THE LOOKOUT FOUND", "+3 Valor", "+50 Timber", "Flamethrower is yours: you can
    carry it in a later update". The family name comes from `weapons[family].name`, else the id
    with a capital.
  - `found` for someone else: toast "<DisplayName> found The Lookout".
  - `locked`: toast "Needs DOUBLE JUMP".
- `src/combat/client/Controllers/MovementController.luau`. `onJumpRequest` now refuses the air
  jump unless the player has the `Ability_doubleJump` attribute. The check runs after the
  fresh-press, airborne and `airJumpDelay` checks and before `airJumpUsed` is set, so a refused
  press costs nothing. The first refused press of a session calls
  `MovementController.SetAirJumpHintHandler`'s handler once, never in the range.
- `src/combat/client/Controllers/InputController.luau`: the rise mirror only, plus a
  `require` of Unlocks.
- `src/combat/client/Controllers/CombatUIController.luau` (wiring in `bootMission` only):
  - K opens and closes the Abilities panel. Only one sheet is open at a time: K closes the map,
    and M or the Map button closes the panel.
  - `deps.onAbilities` goes to the HUD.
  - The `buyAbility` ActionResult goes to the panel.
  - The Snapshot feeds the panel (`valor`, `abilities`) and `SecretFx.SetFound(combat.secrets)`.
  - `RunState.levelId` goes to `SecretFx.SetLevel`, and `SetLobby(phase == "lobby")` to the
    panel.
  - CombatFx batches (or a single effect) of kind `secret` go to SecretFx.
  - The air-jump hint toasts "Double Jump: buy it in the lobby (K)", or "(Abilities)" on
    devices without a keyboard.
  - Studio keys: J toggles Double Jump, sending `grantAbility` or `removeAbility` with
    `"doubleJump"` according to the caller's own attribute. H sends `resetSecrets` with value
    `true`. V sends `grantValor` with value 10. `DEBUG_HINT` names all of them.
- `src/combat/client/UI/CombatHud.luau`: an "Abilities" button between Map and Return, shown
  only in the lobby, `deps.onAbilities`, no click sound. The row is now 280 design px wide.
- `src/combat/client/UI/DebugPanel.luau`:
  - New buttons "Double Jump: ON/off (J)" (its caption follows the attribute through
    `SetAirJump`) and "Reset secrets (H)".
  - "+10 Valor" is now "+10 Valor (V)".
  - Both new buttons appear only when `deps.airJump` is passed, so the C1 `boot()` is
    unchanged.
- `src/client/UI/MapScreen.luau`: a secrets row on the card, shown for an open node that has
  secrets. Each secret gets an icon: a filled gold circle with "✓" when found, a gold outline
  with "?" when not. Under each icon is its key ("2× JUMP", "FIRE", "ICE"). The row is read
  loosely from `MapNodeState.secrets`, so a server without the field shows no row. Card
  LayoutOrders were renumbered (secrets 7, Depart 8, Return 9, key line 10).
- `src/client/UI/Theme.luau`: new constants `COMBAT_ABILITIES_BUTTON_WIDTH`, `ABILITIES_*`,
  `AIR_JUMP_HINT_SECONDS`, `MAP_SECRET_*`, `MAP_SECRET_KEY_WORDS`, `SECRET_NEED_WORDS`,
  `SECRET_COLUMN_*`, `SECRET_OPEN_FALLBACK_COLOR`, `SECRET_CARD_*`, `SECRET_BURST_*`,
  `SECRET_TOAST_SECONDS`.
- `sourcemap.json` and `sourcemap.combat.json` were regenerated with rojo.

## The rise expression (L2-4, client)

`InputController.groundPoint`:
```lua
local airJump = Players.LocalPlayer:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)) == true
if WallClip.TooHigh(casterFloor, floorY, WallClip.Rise(Tuning.Get().movement, airJump)) then
```
This matches the luau-engineer's `WeaponService.GroundPoint` exactly, except that the server
reads `player:` where the client reads `Players.LocalPlayer:`. The rise is 18 without the double
jump and 30 with it.

## Remotes and state consumed

- Remotes: `RequestBuyAbility(abilityId)`, sent. `ActionResult` with action `buyAbility`.
  `CombatFx` with kind `secret` (found and locked). `RequestDebug` levers `grantAbility`,
  `removeAbility`, `resetSecrets` and `grantValor`. `MapState` `nodes[].secrets`.
- State: Snapshot `combat.valor`, `combat.abilities`, `combat.secrets`. RunState `levelId` and
  `phase`. The Player attribute `Ability_doubleJump`. Config `Expeditions.json abilities.list`
  and `looks.secretOpen`, and `ProvingGrounds.json weapons[family].name`.

## Gates (run on my files)

- stylua `--check`: clean. selene: 0 errors, 0 warnings.
- luau-lsp with `tools/types/globalTypes.d.luau`:
  - Combat sourcemap, over all of `src/combat/client` plus MapScreen and Theme: exit 0.
  - Default sourcemap, over MapScreen and Theme: exit 0.
- `py tools/check_compile.py`: PASS (164 files). InputController 152, CombatUIController 99,
  MovementController 104.
- `rojo build combat.project.json` into a scratch file: builds.

## Layouts checked mentally

- **Abilities panel, 667x375 landscape** (58 px inset, scale 0.917): the sheet is 312x148 px,
  centred, and Buy and X are 44 px.
- **Abilities panel, 375x667 portrait**: the sheet is 316 px wide. At 1920x1080 it is 527 px.
  The rows scroll if a later wave adds more than fit.
- **HUD button row**: 257 px on a 667 phone and 260 of 375 px in portrait. It sits bottom-left
  and only in the lobby, as Map does.
- **Map card with the 30 px secrets row**: on 667x375 under a 58 px top bar, the card fits with
  Return and no key line. With a keyboard as well, it ends 6 px into the 8 px screen margin.
- **Centre card**: 275 px wide on a 667 phone and 279 of 375 in portrait. It takes no taps.

## For other owners

1. **luau-engineer (or the lead):** luau-lsp with the default sourcemap now fails in
   `src/client/UI/ArmoryPanel.luau:490,569` and `src/client/UI/ExpeditionPanel.luau:816`.
   - Cause: `src/shared/Armory.luau:98` and `src/shared/Combat.luau` (the `CombatProfile` copy
     above line 283) keep exact structural copies of `Types.CombatProfile` ("nested tables must
     match field-for-field"). The new optional fields break that match.
   - Neither file is in anyone's list. Fix it by adding the same four lines to both copies:
     ```lua
     	stats: { kills: number, wavesCleared: number, expeditions: number, cashFromCombat: number },
     +	abilities: { [string]: boolean }?,
     +	secrets: { [string]: { [string]: boolean } }?,
     +	families: { [string]: boolean }?,
     +	shortcuts: { [string]: { [string]: boolean } }?,
     }
     ```
2. **luau-engineer:** the H key and the strip send `RequestDebug("resetSecrets", true)`. Your
   `applyLever` ignores the value, so they match. J sends `grantAbility` / `removeAbility` with
   `"doubleJump"`.
3. **Lead:** the client needs no `Main.client.luau` change. SecretFx and AbilitiesPanel are
   driven from CombatUIController.

## Assumptions

- The secret CombatFx arrives as a batch, as `announceSecret` sends it. A single table with a
  `kind` field is accepted too.
- The Abilities panel and button exist only in the lobby phase. A member waiting in the lobby
  camp during a live run cannot buy, although the server's `MayLeave` gate would allow it.
- The air jump reads the attribute alone. In the range the server sets it true for everyone
  (wiring step 5 in both branches). If that step were missing, the range would lose the double
  jump.
- The refusal toast names "(K)" on a keyboard and "(Abilities)" on touch. The contract wrote
  only "(K)".

## What Ben should check in Studio (`build/proving.rbxl`, Play)

1. Lobby: press K. The Abilities panel opens with Double Jump "Need 10 more Valor". Press V
   (+10 Valor) and the row reads Buy. Click Buy: toast "Double Jump learned!", the row reads
   Owned, and Valor drops by 10. K or Esc closes the panel.
2. Before buying, in a level: a second jump in the air does nothing, and once per session a
   toast says "Double Jump: buy it in the lobby (K)".
3. J toggles Double Jump; the strip's button caption follows. With it on, double jump from
   Road5 onto the lookout ledge. The light column marks the chest. Standing on it shows the
   card "THE LOOKOUT FOUND / +3 Valor / +50 Timber / Flamethrower is yours...", the chest turns
   gold and the column goes. Press H, then start a new run: the column is back.
4. Map card for Forest Road: a "Secrets" row with three icons (2× JUMP, FIRE, ICE). The lookout
   icon is filled after the find.
5. Phone emulator, 667x375 landscape and portrait: the Abilities button sits between Map and
   Return, the panel fits with 44 px buttons, and the card's secrets row does not push Depart or
   Return off the card.
