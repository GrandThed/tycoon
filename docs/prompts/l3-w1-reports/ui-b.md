# L3 W1 — ui-engineer B (the two hosts): report

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. Nothing committed and nothing staged.
I ran one `git rm --cached` by mistake and undid it with `git reset` straight away; `git diff --cached` is empty.

## Files

Changed:
- `src/combat/client/Controllers/CombatUIController.luau`: wiring only. Still 106 top-level locals: `Format` was
  added, and `BUY_ABILITY_ACTION` + `SET_FAMILY_ACTION` became one `ARMORY_ACTIONS` set.
- `src/combat/client/UI/DebugPanel.luau`
- `src/combat/client/UI/SummaryCard.luau`
- `src/client/UI/MapScreen.luau`
- `src/client/Controllers/UIController.luau`
- `src/client/UI/DebugPanel.luau`

Deleted (from the working tree only):
- `src/combat/client/UI/ArmoryPanel.luau`
- `src/combat/client/UI/ArmoryWeapons.luau`
- `src/combat/client/UI/ArmoryAbilities.luau`
- `src/client/UI/ArmoryPanel.luau`

## What each host does with the screen (`UI/ArmoryScreen`, handle `ArmoryScreen.Handle`)

**The combat place (`bootMission`)**
- **Construction:** `ArmoryScreen.new(screenGui, deps)`.
  - `onUpgrade` fires `RequestUpgradeWeapon(family)`; `onEquip` fires `RequestSetFamily(slot, family, variant)`;
    `onBuyAbility` fires `RequestBuyAbility(id)`.
  - Each returns false when its remote is missing.
  - `toast` wraps `Toast.Show`: seconds default to `Theme.TOAST_SECONDS`, `isError` defaults to false.
  - `keyHint` is "K or Esc closes" on a keyboard, "Y or B closes · LB RB tabs" on a pad. `padToggle = true`.
- **onOpenChanged:** as before. It closes the map, sets `HOLD_ARMORY` on the cursor and hides the DebugPanel.
- **Every RunState:**
  - `SetAvailable(phase == "lobby")`;
  - `SetGate(not live or waiting)`, which is the client's copy of `WaveService.MayLeave`.
  - Both are cheap and idempotent in ui A's file; they are called 4 times a second.
- **Every Snapshot:** `SetState(state.combat)`, when it has `materials` (a table) and `valor` (a number).
- **Every TuneState:** `SetHeld(FeedbackController.GetLoadout())`, when it is not nil. It is also called once at boot.
- **ActionResult:** `upgradeWeapon`, `setFamily` and `buyAbility` go to `OnResult`; everything else is unchanged.
- **Layout:** `SetLayout(scale, size)` in `applyLayout`, with the HUD's own `hudScale` and the ScreenGui's AbsoluteSize.
- **The key names come from `ArmoryScreen`:** `PAD_TOGGLE_NAME` and `PAD_TAB_NAMES`. They feed the pad hint, the air-jump
  hint, SecretFx's family note, the HUD's console button and the summary's first-clear line.

**The hub (`UIController`)**
- **Readiness key (L3-24):** `combatRemotesReady = RequestUpgradeWeapon ~= nil`, in place of `RequestBuyGear`.
  - The Armory key shows when Armory.json and ProvingGrounds.json both exist and the remotes are ready.
  - The Expedition key and the Power readout keep their old rules (`hasArmory = armoryConfig ~= nil`).
  - So the hub hides nothing it showed before. The one exception is the old panel's Ascend rows: they went with the
    deleted panel, as the contract rules (Ascension is unreachable).
- **The screen is built after the dock panels.** It is a full-screen card, not a dock panel, so it is not in `panels`.
  - `onBuyAbility = nil`: the Abilities tab is read-only.
  - `padToggle = false`. The pad hint is "B closes · LB RB tabs".
  - `SetAvailable(true)` and `SetGate(true)` are called once.
- **Opening:**
  - The bottom bar's Armory key goes through `togglePanel("armory")`, which toggles the screen. This only works once a
    model exists and the remotes are ready.
  - Opening the screen closes any dock panel (`closePanels`), marks the bar key active and hides the Studio strip.
  - Opening a dock panel closes the screen first.
- **State:** `pushArmory(combat)` runs on the Snapshot and on every Delta whose `combat` passes `isCombatProfile`. It does
  not run in `refreshAll`, which the cash tick also runs.
  - It calls `SetState(combat)` and `SetHeld(Unlocks.LoadoutOf(combat, proving.weapons, proving.loadout))`.
  - It also calls the strip's `SetTiers`.
- **ActionResult:** `upgradeWeapon` and `setFamily`, ok or refused, go to `OnResult`. The hub keeps its
  `insufficientFunds` sound. The `buyGear` and `ascend` toast and flash branch is gone, since nothing sends either intent now.
- **Layout:** `SetLayout(scale, size)` in `applyLayout`, with the same formula as the combat place.
- **K key:** a `UserInputService.InputBegan` handler for K, ignored when `processed` or when a TextBox has focus. The hub
  binds no other key.

## Inputs

- **Lobby:** K, the HUD's Armory button, and gamepad Y (the screen binds it, lobby only). The screen also handles Esc,
  scrim and close, B, LB / RB, d-pad and stick, and the sunk A.
- **Hub:** K and the bottom bar's Armory key. Everything else is the screen's.
- M opens the map and closes the Armory, as before.
- T, U, L and K are bound nowhere else in either client (grepped).

## Studio levers, client side (L3-28)

**Combat keys** (in `DEBUG_KEYS`, Studio only, debounced):
- T sends `grantMaterials` = `Theme.COMBAT_DEBUG_GRANT_TIMBER` (500).
- U sends `grantStar` = `"*"`.
- L sends `resetArmory` = `true`.

`DEBUG_HINT` adds "T +500 Timber · U ★ Hard · L reset Armory". Numbers go through `Format.Cash`, including the existing
Valor one.

**Combat strip:**
- "Melee T<n> +1" and "Ranged T<n> +1" send `setTier "<heldFamily>=<n+1>"`. The tier is
  `Armory.TierOf(armoryConfig, lastSnapshot.combat, loadout.<slot>)`, refreshed on every Snapshot and TuneState.
  - These replace the old slot-override "Melee +1" / "Ranged +1" (`setGear`), which would have been wrong now.
  - The override is still reachable through G's presets and the `DebugSetGear` attribute.
- "+500 Timber (T)" replaces "+25 mat", so the phone emulator can do what T does.
- New buttons: "★ Forest Hard (U)" sends `"*"`, and "Reset Armory (L)".
- The C1 `boot` no longer calls the strip's tier setter: it has no families, and it cannot fight.

**Hub strip:**
- "Grant 500 Timber" (`Theme.COMBAT_DEBUG_GRANT_TIMBER`, was a local 25);
- "Melee T<n> +1" and "Ranged T<n> +1" (`setTier` on the held families, from `pushArmory`);
- "★ Forest Hard" (`grantStar "*"`);
- "Reset Armory" (`resetArmory true`).
- New `SetTiers` and `SetVisible`.
- The strip went from 2 columns to 3. With 2, eleven buttons stand 384 design px tall, which runs off a 667 × 375
  landscape phone. With 3 they keep the old 4 rows.

**Lever values** match both servers as written now:
- `DebugService.applyLever`: setTier and grantStar take a string; resetArmory takes any value.
- `ArmoryService.HandleDebug` routes all three before its amount check.
- Both RequestDebug validators accept a boolean, and accept a string of up to 64 characters.

## Summary card (L3-17) and the map (L3-15)

**SummaryCard:**
- A new `FirstClear` line is hidden unless `result.firstClear` holds a family or Valor > 0. Every field is checked, since
  it comes over the network.
- Family: "<name> is yours: equip it in the Armory (K)". The name comes from `ProvingGrounds.weapons[f].name`, else the
  id. The key comes from `deps.armoryKey` (new, optional): K on a keyboard, Y on a pad, nothing on touch.
- Valor: "+25 Valor, first <difficulty name> clear".
- If both are present they are joined with " · ".

**MapScreen:** the recommended tier reads "T3" (`TIER_PREFIX .. Format.Cash(tier)`); it used to read "tier 4+". The rewards
line is unchanged ("×2.5 cash and drops" comes from the data).

## Layout, checked by arithmetic

**375 × 667 portrait** (scale about 0.92):
- The summary card is 320 design px wide. The first-clear line is one or two 12 px lines.
- The hub strip is 333 × 0.92 ≈ 306 px wide, inside 375.
- "T3" is shorter than "tier 4+".

**667 × 375 and 640 × 360 landscape:**
- A party's summary card with a wrapped family line is about 326 of the 329 design px available. It fits, but only just.
- The hub strip, expanded, is about 253 px plus the 70 px bottom margin, against about 339 available.

**1920 × 1080** (scale about 1.6): nothing crowds. The strip is about 533 × 442 px, collapsed by default.

The screen's own fit (L3-23) belongs to ui A.

## Gate results

- **stylua `--check`:** clean on my six files. **selene:** 0 errors and 0 warnings.
- **LF:** 0 CR bytes in my six files.
- **`py tools/check_compile.py --counts`:** PASS on 177 files. CombatUIController is at 106.
  - One run read FAIL while another owner was mid-write; the next two runs passed.
- **luau-lsp** (committed definitions, both sourcemaps generated into my scratchpad so the lead's tracked ones were not
  touched): **0 errors in my files** in both trees. The errors that remain are in other owners' in-progress files:
  - `src/shared/Combat.luau`, `ExpeditionPanel.luau:816` and `ExpeditionService.luau:659/674`: the root cause is below.
  - `Armory.luau:457`, `ArmoryModel`, `ArmoryScreen`, `ArmoryDetail`, `ArmoryService`, `CombatService`, `UnlockService`
    and combat `Main.server.luau`.
- **`rojo build`:** default and combat both build (into the scratchpad).

## For the other owners

**ui-engineer A: Theme constants nothing reads any more.** These were read only by the deleted panels, or (the last
one) by the combat strip's old "+25 mat" button. None of the new `Armory*` files read them; grepped over `src` and `tools`.
- `ABILITIES_BUTTON_HEIGHT`, `ABILITIES_BUTTON_WIDTH`, `ABILITIES_HEADER_HEIGHT`, `ABILITIES_HINT_HEIGHT`,
  `ABILITIES_HINT_TEXT`, `ABILITIES_NAME_TEXT`, `ABILITIES_PADDING`, `ABILITIES_RESULT_TIMEOUT_SECONDS`,
  `ABILITIES_ROW_GAP`, `ABILITIES_ROW_HEIGHT`, `ABILITIES_TOAST_SECONDS`, `ABILITIES_WIDTH`
- `ARMORY_CHIP_GAP`, `ARMORY_CHIP_HEIGHT`, `ARMORY_CHIP_VALUE_Y`, `ARMORY_HEADER_GAP`, `ARMORY_MAX_HP_HEIGHT`,
  `ARMORY_NEXT_Y`, `ARMORY_ROW_PAD_BOTTOM`, `ARMORY_STAT_Y`
- `LOBBY_ARMORY_CARD_NAME_HEIGHT`, `LOBBY_ARMORY_CARD_NAME_TEXT`, `LOBBY_ARMORY_CARD_PAD`, `LOBBY_ARMORY_CHIP_HEIGHT`,
  `LOBBY_ARMORY_CHIP_PAD`, `LOBBY_ARMORY_CHIP_TEXT`, `LOBBY_ARMORY_COLUMN_GAP`, `LOBBY_ARMORY_COLUMN_TITLE_HEIGHT`,
  `LOBBY_ARMORY_ELEMENT_COLORS`, `LOBBY_ARMORY_TAB_WIDTH`, `LOBBY_ARMORY_VALOR_ROW_HEIGHT`
- `COMBAT_DEBUG_GRANT_MATERIALS`

These must stay: `ARMORY_CHIP_MIN_TEXT` (the hub strip), plus `SECRET_NEED_WORDS` and the shared colours and sizes, which
other files read. The Theme comments at about lines 1328 and 1392 name `UI/ArmoryPanel`.

**luau-engineer A (or the lead; `src/shared/Combat.luau` is in no owner's list): Combat.luau's structural copies lag the
v8 types.** The old solver compares these copies field for field, so each one must match `Types` / `Armory.luau`
exactly. Exact diff:

```diff
 type MissionRecord = { bestWave: number, bossClears: number, overdriveBest: number }
+type SavedLoadout = { melee: string?, ranged: string?, variants: { [string]: string } }
 type CombatProfile = {
 	...
 	shortcuts: { [string]: { [string]: boolean } }?,
+	tiers: { [string]: number }?,
+	loadout: SavedLoadout?,
+	stars: { [string]: { [string]: boolean } }?,
 }
 ...
+type ArmoryLadderBand = { levelId: string, material: string }
+type ArmoryLadder = {
+	damage: { number },
+	hp: { melee: { number }, ranged: { number } },
+	rangeHp: number,
+	bandSize: number,
+	bands: { ArmoryLadderBand },
+	costs: { number },
+	starDifficulty: string,
+}
+type ArmoryWindow = { start: number, top: number }
+type ArmoryLegacyCost = { material: string, amount: number }
+type ArmoryLegacy = { gearCosts: { ArmoryLegacyCost } }
 type ArmoryConfig = {
 	version: number,
 	baseHp: number,
-	power: { hpWeight: number },
+	power: { hpWeight: number, tierWeight: number? },
 	...
 	partyEffects: { [string]: PartyEffectDef },
+	ladder: ArmoryLadder?,
+	windows: { [string]: ArmoryWindow }?,
+	legacy: ArmoryLegacy?,
 }
```

**Lead:** no remote or project-file change is needed from me.
- My code waits for `RequestUpgradeWeapon` with a timeout in the combat place, and `FindFirstChild`s it and
  `RequestSetFamily` in the hub. Both remotes are already in your diffs.
- The sourcemaps are not touched.

## Assumptions

- "★ Forest Hard" sends `"*"` (every built band level). That equals Forest Road until the Castle is built. A comment in
  both strips says so; the caption must change when a second band level exists.
- `SetGate` in the lobby mirrors `MayLeave` from the RunState: not a live phase, or this member is `waiting`.
- The hub strip's tier buttons, and the screen's held pair, read the saved loadout through `Unlocks.LoadoutOf`. In the
  combat place they read the TuneState's loadout, which is the server's word on what is held.

## What to check in Studio

1. **Lobby (`proving.rbxl`):**
   - K, the HUD's Armory button and pad Y each open the screen, and it closes the map.
   - M closes it and opens the map.
   - The debug strip is hidden while the screen is open.
   - Upgrade toasts "Longbow: T2". After the Snapshot, the strip's "Ranged T2 +1" updates.
   - Equip toasts "<name> equipped".
2. **Studio keys:**
   - T gives +500 Timber in the wallet.
   - U, then the T4 of a band top: Upgrade is no longer "Needs ★ Hard".
   - L resets: tiers go back to T1 and the held families go back to the starters.
   - The strip has the same three as buttons, and the tier buttons step the held families.
3. **Summary:**
   - A first Hard clear shows "Warhammer is yours: equip it in the Armory (K)".
   - The map's difficulty buttons read T1 / T3 / T5.
4. **Hub (`test.rbxl`):**
   - The Armory key and the Power readout are visible.
   - K and the bar key toggle the screen. Opening it closes an open dock panel, and opening Build closes the Armory.
   - Its Abilities tab is read-only.
   - Upgrade and Equip work, and a refusal for funds plays the insufficientFunds sound.
   - The strip's "Grant 500 Timber", tier, star and reset buttons work. The strip hides while the screen is open.
5. **Mobile emulator:**
   - At 667 × 375 and 640 × 360 landscape, a party's summary card with the family line fits under the top bar.
   - The hub strip, expanded, stays on screen in 3 columns.
   - At 375 × 667 portrait the hub strip fits the width.
   - The screen's own fit is ui A's L3-23.
6. **Gamepad:** check that A on Equip does not jump (L3-36, the screen's job), and that pad Y does nothing in the hub.
