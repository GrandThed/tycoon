# L3 W1 review, slice 4: the Armory screen

Reviewed: `l3-armory` at a2628da (W1 build ff7a910, follow-up 64a6b12).

Files:
- the seven `src/client/UI/Armory*.luau`;
- the diff of `src/client/UI/Theme.luau`;
- `tools/crowd_harness/tests_l3_ui.luau`.

I also read the parts of both hosts that drive the screen: `CombatUIController` (construct, RunState, Snapshot,
TuneState, ActionResult, layout) and `UIController` (construct, `pushArmory`, `applyLayout`, `onActionResult`).

Result: **0 Critical, 0 Major, 3 Minor, 7 Suggestions.**

## Minor

### m1. In the hub on a phone, Roblox's touch jump button may draw over the Upgrade button and the shelf

**Where:**
- `src/client/UI/ArmoryScreen.luau:744-773` (`setOpen`);
- `src/client/Controllers/UIController.luau:473-482` (the hub's `EraCityHUD`).

**What is wrong:**
- The hub's ScreenGui has no `DisplayOrder`, so it is 0.
- Roblox's `TouchGui` is also 0. It is made by PlayerModule `ControlModule:CreateTouchGuiContainer`, read from this
  machine's Studio install (`ExtraContent/scripts/PlayerScripts/StarterPlayer/PlayerModule/ControlModule/init.lua:953-970`).
  It is created lazily, once a humanoid exists and the preferred input is touch, so usually after the HUD.
- Two ScreenGuis with the same DisplayOrder have no defined draw order.
- In the combat place this cannot happen: `ExpeditionHUD` is DisplayOrder 1 (`CombatUIController.luau:1331-1337`).

**The overlap, from a Python port of `layout()`:**
- The port reproduces ui-A's table to the pixel.
- The jump button geometry comes from `TouchJump.lua:233-259`.
- Coordinates below are viewport px.

| Screen | Jump button | Upgrade button | Overlap |
|---|---|---|---|
| 640 × 360, classic branch | 70 px at (545..615, 270..340) | (494..622, 237..281) | 70 × 11 |
| 640 × 360, AvatarAbilities branch | 72 px at (504..576, 224..296) | (494..622, 237..281) | covers the middle 72 of its 128 px |

- At 640 × 360 the classic jump button also covers 70 × 54 of the shelf's last visible card.
- At 375 × 667 portrait it covers the bottom-right card of the 5 × 3 grid completely. That card is the Spinblade, and
  the grid does not scroll at 15 cards.

**Failure scenario:** Ben opens the hub's Armory in the phone emulator at 640 × 360 and taps "Upgrade T2" low or in
the middle. If TouchGui draws on top, the tap is a jump, and nothing is bought.

**Fix:**
- In `setOpen`, save `GuiService.TouchControlsEnabled` and set it false while the screen is open. Restore it on close
  and in `teardown`.
- ControlModule listens to that property (`init.lua:170`). It hides the TouchGui and disables touch movement, which a
  modal screen wants in both places anyway.
- The alternative is DisplayOrder ≥ 1 on the hub's ScreenGui (ui-B's file).
- Check in the emulator either way.

### m2. A gamepad user can end up with no selection, and only a repaint gives one back

**Where:**
- `src/client/UI/ArmoryScreen.luau:524-538` (`reselect`, called only from `paint`);
- `:677-694` (`onPadPress`);
- `:762-764` (the open sets a selection only when `padLast()`).

**What is wrong:**
- The screen sets a selection on open only if the last input was a gamepad. After that it restores one only inside
  `paint`, which runs on a Snapshot, a TuneState, a gate change or a press.
- `onPadPress` sinks A and presses nothing when `GuiService.SelectedObject` is nil.
- L3-22 says "the d-pad and the stick move the selection, which cannot leave the screen".

**Failure scenario:**
1. In the lobby, on a PC with a pad connected, press K, or click the HUD button. Nothing is selected.
2. Pick up the pad.
3. A does nothing (it is sunk). The d-pad does nothing. The left stick walks the character behind the scrim.
4. This lasts until some server message repaints the screen. In an idle lobby that may never happen.

The same state follows anything else that clears the selection while the screen is open.
- If Roblox's GUI navigation takes B to deselect before ContextActionService sees it, which is unverified (the A case
  is handled for exactly this doubt), then the first B press only deselects. The stick then walks again.

**Fix:**
- In `onPadPress` Begin, when nothing inside `frame` is selected, set `GuiService.SelectedObject = firstSelection()`
  and press nothing.
- While the screen is open, connect `UserInputService.LastInputTypeChanged` and
  `GuiService:GetPropertyChangedSignal("SelectedObject")` to `reselect()`. Disconnect them in `bindOpenKeys(false)`.
- Add "B with a selection closes on the first press" to the Studio gamepad check (L3-36).

### m3. The style buttons' "one equip in flight" branch is under no check

**Where:**
- `src/client/UI/ArmoryModel.luau:679-682`;
- `tools/crowd_harness/tests_l3_ui.luau:722-731`.

**What is wrong:**
- `styleButtons` makes a style live only while no equip is pending (`live = pending.equipFamily == nil`).
- No case looks at a style button of one family while an equip of another family is pending. The case at :722 only
  checks the pressed button.

**Proof:** a review-only mutant, `live = true` on line 681, in a second archive copy, run through `mutate.py`.
- Result: `HARNESS: PASS (3,539 checks)`, not caught.
- The other two probes that survived are equivalent mutants, so no case is needed for them:
  - `held = owned and ...` with `owned` dropped;
  - the band-top test fixed at 4.

**Failure scenario:**
1. Equip the Warhammer.
2. While it waits, select the Longbow.
3. Its "B: Quick shot" paints live and selectable, but a press does nothing, because `onEquip` returns on
   `view.equip ~= nil` (`ArmoryScreen.luau:470`).

So the model's documented rule is broken in a way no gate sees. Today the only harm is a button that looks live and
is dead. A later change to the guard would turn that into two equips in flight.

**Fix:**
- Add a case: `pending = { equipFamily = "warhammer", equipVariant = "A" }` on the Longbow. Both style buttons must not
  be live.
- Add the mutant `"l3 ui: a style is live during another equip"` to `mutate.py`.

## Suggestions

1. **Card text in portrait** (`src/client/UI/ArmoryShelf.luau:135-155`, `Theme.luau:1455`).
   - A portrait card is 68 wide, so the tier label spans 58 px.
   - "Not found" at 11 px GothamBold is about 55 px wide. On the two element families' cards (Flamethrower,
     Frost Hammer), the faded element dot (x 55..63) sits on its last letters.
   - The card names' floor `CARD_NAME_MIN_TEXT` 8 is 7.3 physical px at MIN_SCALE ("Flamethrower" reaches it). That
     copies the bottom bar's floor, but it is small for the screen's main list.
   - Move the dot above the tier, or shorten the text to "?".
2. **Pad selection after a press** (`ArmoryDetail.luau:76`, `ArmoryScreen.luau:625`).
   - A pending button turns unselectable, so `reselect` sends the pad's selection back to the shelf card.
   - Buying T2 and then T3 on a pad means navigating back to Upgrade each time.
   - Keep pending buttons selectable (their handlers already re-check `live`), or reselect the same button once it is
     live again.
3. **The Abilities offers are frozen at construction** (`ArmoryScreen.luau:494-502`).
   - The offers are read from the construction-time `configs.expeditions`.
   - The comment at :124-126 says configs are re-read at every open, because a client may still be receiving the
     Config folders.
   - If Expeditions arrives late, the tab reads "Nothing to learn yet" for the session, while the shelf's hints
     (re-read) are fine.
   - Both hosts read Expeditions before mounting today, so this is latent. Rebuild the page's rows on open when the
     offers changed, or say in the comment that the hosts guarantee it.
4. **A duplicate of a config value** (`ArmoryModel.luau:175-179`).
   - `starDifficulty()` falls back to `"hard"` when `ladder.starDifficulty` is missing.
   - The server's `Armory.UpgradeVerdict` treats a missing value as "no star counts" (`Armory.luau:414-418, 454-457`).
   - With a broken config, a player who has the Hard star would see the cost line drop "needs ★ Hard" while the button
     still says "Needs ★ Hard". The validator warns about the missing value (`Armory.luau:674-675`).
   - Return nil and let the cost line say nothing about a star, as the server does.
5. **The toast for a style switch** (`ArmoryModel.luau:771-779`).
   - Switching the held Longbow from A to B toasts "Longbow equipped". L3-21 lists only family equips.
   - "Longbow: Quick shot" says what changed.
6. **Short landscape screens** (`ArmoryScreen.luau:581`).
   - `middle` never drops under `ArmoryDetail.Height()` (163). At 568 × 320 (iPhone SE, 1st generation) the content
     is 34 design px taller than the frame.
   - The shelf hangs below the panel, and its cards are cut by about 9 px at the screen edge. This is outside
     L3-23's sizes.
   - Let the detail's three lines shrink first, or scroll the page.
7. **MIN_SCALE's list** (`Theme.luau:41-49`).
   - The M1 rule derives MIN_SCALE from the smallest interactive size. The new 48 and 56 px targets
     (`ARMORY_SCREEN_HEADER_HEIGHT`, `BUTTON_HEIGHT`, `CARD_HEIGHT`) are not in the list.
   - This has no effect today, because all are ≥ 48. A later edit to 40 would silently give 37 physical px.
   - Hoist them like `ROW_BUTTON_HEIGHT`.

## Checked and found clean

- **Contract shape.** The handle matches L3-18 (plus `Destroy`), and so do `PAD_TOGGLE_NAME` and `PAD_TAB_NAMES`.
  Layout A matches L3-19: header, stage left, detail right, shelf, shelf order, the unowned card with no buttons.
- **The track (L3-20).** Twenty pips, five bands in the theme colours through each band's map node, lit / open / dim,
  start and top marks, a relic as one lit pip. Contrast: lit (70, 182, 101), open blends to (46, 97, 82), dim to
  (48, 60, 91).
- **Buttons never decide.**
  - Upgrade is live only on `Armory.UpgradeVerdict == nil`, with the same `owned`, `Starters(loadout)` and `built`
    the servers use. Equip and the styles are live only on `Unlocks.FamilyVerdict == nil`.
  - `onUpgrade` re-derives the detail before sending. The client sends a family, a slot and a style key, never a tier
    or an amount.
  - No client code writes to the profile copy.
- **Words.** The refusal words and their order match L3-21 and `UpgradeVerdict`: peak, busy, notBuilt, needsStar,
  insufficientFunds. "Not enough" covers a stale shortfall. Everything else reads "Try again".
- **Pending presses.**
  - One upgrade and one equip in flight. A 3 s timer, keyed on the entry.
  - "Upgrading..." holds until the state shows the tier, in either message order: combat sends the answer, then the
    Snapshot; the hub sends the answer, then the Delta at 4 Hz.
  - The `picked` overlay is harmless with the combat order (TuneState, then answer).
- **Fit at the contract's sizes.**
  - 640 × 360: 682 × 313 design, middle 173, detail content 163.
  - 667 × 375: 711 × 329.
  - 375 × 667: 393 × 648, stage 223, 5 × 3 grid of 68 × 56.
  - The track fits: 434 of 440, and 374 of 377.
  - Every tap target is ≥ 48 design px, which is 44.0 physical: tabs, close, cards, the detail buttons (79 to 140 wide),
    Buy.
  - The hosts' scale formula is identical in both places.
- **Gamepad.**
  - A, B, LB and RB bound at High+1 only while the screen is open. Y bound only while it is available, with
    `padToggle`.
  - The press router dedupes the engine's press and the action's press in either order, including a release-time
    press on a moved selection.
  - The SelectionGroup stops on all four sides.
- **Motion and sound.** No sound call anywhere. The only animation is gated on `Theme.lowEndDevice` and timed by
  `Motion.Info` (shorter, still visible on touch).
- **Cleanup.** Close unbinds every action and clears a selection inside the screen. `teardown` (on `Destroying`, which
  fires for descendants) disconnects all four connections and every button binding, and destroys the parts. Late
  timers are inert after destroy. Both hosts' ScreenGuis are `ResetOnSpawn = false`.
- **Requires.** Only Shared (Armory, Catalog, Types, Unlocks, Format) and the siblings Create, Motion, Theme and the
  Armory* files. All are mapped in `combat.project.json` and present in the hub tree. There is no Panel, PanelDock,
  SoundController or controller require.
- **Gates.**
  - `--!strict` everywhere. No `wait`, `spawn` or `delay`, and no `Instance.new`.
  - Compile cap: the largest top level is 36 of 180. `check_compile` PASS, 177 files.
  - stylua clean, selene 0/0 on the seven files and Theme, luau-lsp clean on both trees with fresh sourcemaps.
  - Harness `HARNESS: PASS (3,539 checks)`. `mutate.py "l3 ui:"`: 22 run, 0 not caught.
- **Theme.** The 32 constants removed have no reader in `src` or `tools`.
- **The real data.** Every family not owned on a fresh profile has a hint (L3-25). The Flamethrower reads "Hidden on
  Forest Road". "Comes with Castle" is said by the map node's name.
- **Note, not a finding.** The contract's L3-19 example "T5: 303 → 500 dmg · HP +120 → +170" pairs the Longbow's damage
  with melee HP. The model's "HP +80 → +110" (the ranged list) is the correct reading. ui-A's report quotes the
  contract with the corrected numbers.
