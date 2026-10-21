# L3 W1 fix round — ui-engineer: report

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. Nothing committed or staged. My rulings: R1 (ArmoryModel),
R8, R9, R10, R11 (the case), 3-s1, 3-s2 (captions, the constant), 3-s3, 4-s1, 4-s2, 4-s3, 4-s5, 4-s7. All done, except
R8: it needs one token in `PartyInviteToast.luau`, which is outside my row (diff below).

A' had already landed `Armory.StarHeld(cfg, combat: CombatProfile?, levelId)` and `Unlocks.ALL_STARS`. I checked
`git diff src/shared/` at the end: A' only added functions (`StrikeTier`, `HeldFamily`, `SavedPower`, `StarHeld`,
`ALL_STARS`) and changed no signature my files use. The designer's `starAlso: ["brutal"]` is in `Armory.json`.

## Files changed

- `src/client/UI/ArmoryModel.luau`
- `src/client/UI/ArmoryScreen.luau`
- `src/client/UI/ArmoryShelf.luau`
- `src/client/UI/ArmoryDetail.luau`
- `src/client/UI/ArmoryAbilityPage.luau`
- `src/client/UI/Theme.luau`
- `tools/crowd_harness/tests_l3_ui.luau`
- `src/client/Controllers/UIController.luau`
- `src/client/UI/DebugPanel.luau` (hub)
- `src/combat/client/Controllers/CombatUIController.luau`
- `src/combat/client/UI/DebugPanel.luau`

`ArmoryStage` and `ArmoryTrack` are unchanged.

## What each fix does

**R1 + 4-s4 (ArmoryModel).**
- The private star check is gone. `hasStar` is now a nil guard around `Armory.StarHeld`, so the cost line and the
  button follow the server's verdict, `starAlso` included. A Brutal star opens T4, and the screen still names
  "★ Hard". I kept the name `hasStar`, so the existing mutant "the cost line forgets the star" still matches its text.
- `starDifficulty()` returns nil when the ladder names no difficulty. It no longer falls back to `"hard"`.
  - The cost line then names no star.
  - A `needsStar` button reads "Needs a star on Forest Road".
  - The server fails closed there, so the button is right to say a star is missing.

**R8 (Theme).** `Theme.ZINDEX_INVITE = 17` sits between `ZINDEX_CARD` (15) and `ZINDEX_DIALOG` (20). The card needs
the one-line change below, which I cannot make.

**R9 (ArmoryScreen.setOpen).**
- On open it saves `GuiService.TouchControlsEnabled` and sets it to false.
- Close restores the saved value. So do `SetAvailable(false)` and teardown, because both go through `setOpen(false)`.
- It covers both places, since both hosts mount the same screen. Nothing else in `src` writes that property.

**R10 (ArmoryScreen).**
- **A with nothing selected.** If nothing inside the frame is selected, A only sets
  `GuiService.SelectedObject = firstSelection()` and presses nothing. It is still sunk, and `padHeld` covers the engine's
  press on release.
- **While open.** `LastInputTypeChanged` runs `reselect()`. A `SelectedObject` change runs `task.defer(reselect)`. Both
  connections live in `openConnections` and are disconnected in `bindOpenKeys(false)`.
- **No loop.** `reselect()` only acts while open with the pad as the last input. It stops once the selection is
  selectable and inside the frame.

**R11 (tests_l3_ui).** One case: a Warhammer equip is pending.
- On the held Longbow, neither style button is live, and "B: Quick shot" keeps the `action` look.
- On the Splitbow, neither Equip A nor Equip B is live.
- Mutant below.

**3-s1 (UIController).**
- **The screen is built whenever `Armory.json` exists.** The screen already re-reads the weapon families at every open.
- **The bar key and K follow one rule:** screen, `provingConfig` and remotes. `refreshCombatKeys` reads
  `provingConfig` again while it is nil. It runs after the screen is built, on every remote `ChildAdded`, and from
  `pushArmory` while the config is missing. So a late ProvingGrounds shows the key at the next Snapshot or Delta.
- **The intents are looked up at send time.** `onUpgrade` and `onEquip` call `resolveCombatRemotes()` when their remote
  is nil, so a late `RequestSetFamily` no longer toasts "Try again" for the whole session.
- **The hub hides nothing it showed before.** Without ProvingGrounds, the key stays hidden, as it did before.

**3-s2.**
- **The wildcard.** The combat `DEBUG_KEYS` U entry and both strips send `Unlocks.ALL_STARS`. No `"*"` literal is left
  in my files.
- **The caption.** It comes from the new pure `ArmoryModel.StarLeverText(inputs)`: "★ Hard: Forest Road" (the server
  notice's wording). It reads `Armory.BuiltBands` and the level names, gives "★ Hard: Forest Road, Castle" once the
  Castle is built, and "★ Hard: none" with no built band level.
- **Where the strips get it.** Through `ArmoryScreen.StarLeverText()`, which reads the configs fresh each time. Both
  strips call it again each time they expand. The combat strip adds " (U)".
- **Left alone.** The lobby's `DEBUG_HINT` "U ★ Hard" names no level, so it stays true and I did not change it.

**3-s3.**
- **New exports.** `ArmoryScreen.KEY = Enum.KeyCode.K` and `ArmoryScreen.KEY_HINT = KEY.Name .. " or Esc closes"`.
- **The hosts.** Both drop their own `ARMORY_KEY` and `ARMORY_KEY_HINT`.
- **The air-jump hint** ("… Armory (K)") is built from `KEY.Name` too.
- **CombatUIController** goes from 106 to 104 top-level locals. It is wiring only.

**4-s1 (ArmoryShelf, Theme).**
- **The tier line yields to the dot.** On a card with an element dot, the line ends `CARD_DOT + CARD_DOT_GAP` (8 + 3)
  before the dot. It is `TextScaled`, with a `UITextSizeConstraint`: the maximum is 14 owned and 11 unowned, the minimum
  is the 8 floor.
- **Portrait.** "Not found" shrinks to about 9 px in the 47 px it has beside the dot.
- **Names.** Still full width, still floored at 8.
- **The floor in Theme.** It is one hoisted local, `LABEL_MIN_TEXT`. `BOTTOM_BAR_LABEL_MIN_TEXT` and
  `ARMORY_SCREEN_CARD_NAME_MIN_TEXT` both read it, so they cannot drift apart.

**4-s2.**
- **Detail buttons.** A button in the `pending` look stays `Selectable`, so a pad's selection stays on "Upgrading..."
  until it reads "Upgrade T3". Every handler still acts only while its button is live.
- **The Abilities Buy.** It does the same while its purchase is pending.

**4-s3 (ArmoryAbilityPage).** A new `SetOffers(offers)` rebuilds the rows only when their signature changes (id,
name, text, price). The screen calls it at every open with `ArmoryAbilityPage.Offers(configs.expeditions)`. The
signature check comes before `HasLiveBuy` picks the first tab.

**4-s5.**
- **The model.** `ArmoryModel.OkText` takes an optional `style`: "Longbow: B · Quick shot", or "Longbow: Z" for a style
  with no label.
- **The screen.** It decides at the press whether an equip is a restyle: the family is the one held in its slot. It
  stores that as `Waiting.restyle`.
- **Why at the press.** In the dungeon the TuneState can arrive before the answer, and from then on every equipped
  family reads as held.

**4-s7 (Theme).** `ARMORY_SCREEN_HEADER_HEIGHT` (48), `ARMORY_SCREEN_BUTTON_HEIGHT` (48) and
`ARMORY_SCREEN_CARD_HEIGHT` (56) are hoisted and added to the `MIN_SCALE` list. `MIN_SCALE` is unchanged at 44 / 48.

## Remotes and state fields consumed

- **No new remote, and the screen still sends none itself.**
  - The hub sends `RequestUpgradeWeapon(family)` and `RequestSetFamily(slot, family, variant)`, now resolved at send time.
  - Both strips send `RequestDebug("grantStar", Unlocks.ALL_STARS)`.
- **State, as before:** `combat.materials`, `valor`, `families`, `tiers`, `stars`, `loadout`, `abilities`, and the held
  loadout.
- **Config:** `ladder.starAlso`, read only through `Armory.StarHeld`.

## Assumptions

- **R8.** I did it as a Theme constant plus the diff below, not by finding the card by name from `UIController`. On a
  gamepad, the invite still cannot be selected while the Armory is open, because the frame's SelectionGroup stops
  movement on all sides. B closes the screen first. The ruling asked for z only.
- **New words** (inside L3-21's "anything else"):
  - "Needs a star on <level>" on a ladder with no `starDifficulty`;
  - "★ ?: …" for the caption in that case.
- **4-s1.** The text scales rather than shortening "Not found" to "?". It still reads, and it never goes below the
  floor.

## Required changes outside my files

**1. R8, for the lead** (`src/client/UI/PartyInviteToast.luau`, at 0362634):

```diff
@@ -65,7 +65,9 @@ function PartyInviteToast.new(parent: Instance, deps: Deps): PartyInviteToastHandle
 		BackgroundTransparency = Theme.BG_TRANSPARENCY,
 		BorderSizePixel = 0,
 		Visible = false,
-		ZIndex = Theme.ZINDEX_CARD,
+		-- Above the hub's full-screen Armory, a later ZINDEX_CARD sibling that would cover it and
+		-- take its taps on the scrim (L3 W1 fix round R8).
+		ZIndex = Theme.ZINDEX_INVITE,
 		Parent = parent,
 	}) :: Frame
```

**2. `mutate.py` entries, for the lead.**
- All seven were run on a private scratch copy, never the shared `mutant/` root, with
  `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\f6c03e29-23c5-4dc8-ba99-ba7296a3858e\scratchpad\ui_mutants.py`.
  The baseline passed 3,654 checks, and all seven were caught, by 1 or 2 checks each.
- Each text occurs exactly once in `ArmoryModel.luau` as it stands.
- The 22 existing `l3 ui:` entries were re-checked: none is stale. "two equips in flight" is equipButton's line, the one
  with a comma. The R11 entry is styleButtons' line, without one.

```python
# L3 W1 fix round, from the ui-engineer (tests_l3_ui.luau): R1, R11, 4-s4, 4-s5, 3-s2.
L3_UI_FIX_MUTATIONS = {
    "l3 ui: a style is live during another equip": (ARMORY_MODEL, "\t\t\tlive = pending.equipFamily == nil\n", "\t\t\tlive = true\n"),
    "l3 ui: the cost line reads only the Hard star": (ARMORY_MODEL, "\treturn armory ~= nil and combat ~= nil and Armory.StarHeld(armory, combat, levelId)\n", "\treturn combat ~= nil and type(combat.stars) == \"table\" and type(combat.stars[levelId]) == \"table\" and combat.stars[levelId].hard == true\n"),
    "l3 ui: an unnamed star reads as Hard": (ARMORY_MODEL, "\treturn if type(key) == \"string\" and key ~= \"\" then key else nil\n", "\treturn if type(key) == \"string\" and key ~= \"\" then key else \"hard\"\n"),
    "l3 ui: an unnamed star's button names Hard": (ARMORY_MODEL, "\t\t\telse TEXT.needsAStar .. levelName\n", "\t\t\telse \"Needs \u2605 Hard on \" .. levelName\n"),
    "l3 ui: a style switch toasts a plain equip": (ARMORY_MODEL, "\tif style ~= nil then\n", "\tif false then\n"),
    "l3 ui: the star lever names the first level only": (ARMORY_MODEL, "table.concat(names, \", \")", "names[1]"),
    "l3 ui: the star lever ignores what is built": (ARMORY_MODEL, "\t\tlocal levelIds = Armory.BuiltBands(armory, built)\n", "\t\tlocal levelIds = { \"forestRoad\" }\n"),
}
MUTATIONS.update(L3_UI_FIX_MUTATIONS)
```

**3. Harness `FILES`.** No change: every mutant is in `ArmoryModel.luau`, which is already listed.

## Gates (worktree as it stands, every owner's work in it)

- **stylua `--check`:** clean on my 13 files.
- **selene:** 0 errors, 0 warnings on the 12 `src` files. On `tests_l3_ui.luau` it reports undefined `check`, `L1`,
  `FIXTURES` and `ARMORY`. Those are the harness bundle's globals, as in W1.
- **luau-lsp** (`tools/types/globalTypes.d.luau`, fresh sourcemaps of both projects in my scratchpad): no diagnostics on
  the hub tree or the combat tree, including the mapped `Armory*` files and `Theme`.
- **`py tools/check_compile.py`:** PASS, 178 files.
- **`rojo build`:** both `default.project.json` and `combat.project.json` build (into my scratchpad).
- **Harness:** `HARNESS: PASS (3,654 checks)`. There are 13 new checks of mine, all `ok`: R1 synthetic and shipped, 4-s4,
  R11, 4-s5, 3-s2.
- **LF:** 0 CR bytes and 0 NUL bytes in my files.

## Layout, checked by arithmetic

None of the screen's geometry changed except the shelf's tier line.

- **375 × 667 portrait** (scale 0.917, frame 393 × 648 design):
  - cards are 68 × 56, the name 58 wide;
  - the tier line is 58 wide, or 47 beside a dot, so "Not found" is about 9 px on the Flamethrower and Frost Hammer cards
    and 11 elsewhere;
  - every tap target is still ≥ 48 design px, which is 44 physical.
- **640 × 360 and 1920 × 1080 landscape** (scale 0.917 and 1.53, frames 682 × 313 and 880 × 420): cards are 92 wide, and
  the tier line is 82, or 71 beside a dot, so "Not found" fits at 11 and nothing shrinks.
- `MIN_SCALE` is unchanged.

## What to check in Studio (mobile emulator included)

1. **R9, phone emulator, 640 × 360 and 375 × 667.**
   - In the hub and in the lobby, opening the Armory removes Roblox's thumbstick and jump button, and closing it brings
     them back.
   - Tapping low or in the middle of "Upgrade T2" buys, and never jumps.
   - Starting a run while the screen is open (lobby) brings the controls back.
2. **R10, gamepad.**
   - Open with K or a click, then press A on the pad: the shelf's selected card gets the selection and nothing is
     pressed. The next A presses.
   - Wiggle the mouse, then touch the stick: the selection comes back.
   - With a selection, B closes on the first press (add this to L3-36).
3. **4-s2.** On a pad, A on "Upgrade T2": the selection stays on "Upgrading...", then on "Upgrade T3". A again buys T3.
4. **4-s5.** On the held Longbow, press "B: Quick shot": the toast reads "Longbow: B · Quick shot". Equipping the Warhammer
   still reads "Warhammer equipped".
5. **R8, after the diff.** In the hub, open the Armory, then press the strip's "Fake invite".
   - The invite card draws above the screen.
   - Accept and Decline take the tap, and the Armory stays open.
6. **3-s2.** The hub strip reads "★ Hard: Forest Road" and the lobby strip "★ Hard: Forest Road (U)". U and the button
   still open T4.
7. **4-s1, portrait.**
   - "Not found" on the Flamethrower and Frost Hammer cards clears the fire and ice dots, at about 9 px.
   - Check that `TextScaled` under the `UIScale` really stays at or above the 8 floor.
   - Check that "Flamethrower" never breaks mid-word in the name line. That was not touched, but it is worth one look
     with `TextWrapped`.
8. **4-s3.** The Abilities tab lists Double Jump in the lobby. In the hub it reads "Bought in the dungeon's lobby".
9. **Low graphics.** Nothing new animates. The stage's text pop is still the only animation, still gated on
   `Theme.lowEndDevice`. There is no sound call.
