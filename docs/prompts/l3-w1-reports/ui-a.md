# L3 W1 — ui-engineer A (the screen): report

Branch `l3-armory`, worktree `C:\Users\benja\Desktop\tycoon-p5`. Nothing committed. Contract: `docs/prompts/l3-w1-contract.md`
L3-18 to L3-23. Every gate is green on the worktree as it stands with every owner's work in it.

## Files

New, all `--!strict`, LF:

| File | Lines | Top-level locals | What |
|---|---|---|---|
| `src/client/UI/ArmoryScreen.luau` | ~900 | 26 | The shell: scrim, frame, tabs, wallet + key line, close, layout (landscape and portrait), pad bindings, the press router, selection confinement. |
| `src/client/UI/ArmoryStage.luau` | ~150 | 7 | Placeholder stage: slot word, family name, element chip, big tier, lighter gradient behind; dark when unowned. API `new / Show(card?) / SetSize / Destroy`, which W2 keeps for the ViewportFrame. |
| `src/client/UI/ArmoryTrack.luau` | ~150 | 5 | The 20 pips, five bands in theme colours, start/top numbers, gold ring on the current tier. |
| `src/client/UI/ArmoryShelf.luau` | ~240 | 6 | 15 cards: one scrolling row in landscape, 5-column grid in portrait. A tap or gamepad selection selects the card. |
| `src/client/UI/ArmoryDetail.luau` | ~330 | 7 | Name, slot, tier, track, next/cost/ability lines, style buttons, Equip, Upgrade. |
| `src/client/UI/ArmoryAbilityPage.luau` | ~330 | 17 | The lobby panel's Abilities tab moved in. Read-only when `onBuyAbility` is nil ("Bought in the dungeon's lobby"). |
| `src/client/UI/ArmoryModel.luau` | 780 | 36 | **Pure**: shelf cards, pips, next and cost lines, every button's state and words, toasts, wallet. |
| `tools/crowd_harness/tests_l3_ui.luau` | ~800 | 1 | 109 checks on `ArmoryModel`. |

Changed: `src/client/UI/Theme.luau`.
- Added the `ARMORY_SCREEN_*` block (after `SECRET_TOAST_SECONDS`) and `COMBAT_DEBUG_GRANT_TIMBER = 500`.
- Removed the 32 constants on ui-engineer B's list after grepping `src/` and `tools/` for each name (0 readers):
  - the twelve `ABILITIES_*`;
  - eight `ARMORY_*`: chip gap, chip height, chip value Y, header gap, max HP height, next Y, row pad bottom, stat Y;
  - the eleven `LOBBY_ARMORY_*`;
  - `COMBAT_DEBUG_GRANT_MATERIALS`.
- `ARMORY_CHIP_MIN_TEXT` stays (the hub DebugPanel reads it). Its comment now says so.

## The handle as built

`ArmoryScreen.new(parent, deps)` matches L3-18 exactly: the same `Deps` fields, the same members, and
`PAD_TOGGLE_NAME = "Y"`, `PAD_TAB_NAMES = "LB RB"`. Two things the hosts must know (both hosts already do them):

- `SetAvailable` and `SetGate` both **start false**. The hub calls `SetAvailable(true)` and `SetGate(true)` once
  (`UIController.luau:762-763`). The lobby calls them on every RunState (`CombatUIController.luau:2080-2081`).
- One member is extra: `Destroy`. No host needs it. The screen also tears itself down on `root.Destroying`, so
  destroying the ScreenGui cleans up connections, CAS bindings and timers.

The exported type is `ArmoryScreen.Handle`; `ArmoryScreen.Deps` is exported too.

## Remotes and state consumed

The screen never touches a remote. It calls the host's `onUpgrade(family)`, `onEquip(slot, family, variant)` and
`onBuyAbility(id)`.

What it reads:
- **`SetState(combat)`**: `materials`, `valor`, `families`, `tiers`, `stars`, `loadout` (through `Unlocks.LoadoutOf` when
  the host gives no held loadout), `abilities`.
- **`SetHeld(loadout)`**: the held pair and its `variants`.
- **`OnResult`**: actions `upgradeWeapon`, `setFamily`, `buyAbility`.
- **Configs via `Catalog`**: Armory, ProvingGrounds (`weapons`, `loadout`), Expeditions (`nodes`, `themes`,
  `difficultyNames`, `found`, `abilities`), and the level files and ids. They are re-read at every open, because a
  client may still be receiving the Config folders when the host mounts the screen (`Catalog.GetLevelFile`'s note).
  Without that, an early mount would read Forest Road as "not built".

Shared rules used (A's, all present):
- `Armory`: `Window`, `TierOf`, `NextTier`, `BandOf`, `TierCost`, `Preview`, `UpgradeVerdict`, `LadderSize`,
  `BuiltBands`.
- `Unlocks`: `FamilyVerdict`, `OwnsFamily`, `Starters`, `ElementOf`, `LoadoutOf`, `Sellable`.

## Layout (numbers from a Python mirror of `layout()`)

Design px under one UIScale. The scale is the hosts' formula, `clamp(min(w/375, h/667), 44/48, 1.8)`, taken on the
ScreenGui size below the 58 px top bar, with 8 px margins.

| Screen | Scale | Frame (design / physical) | Layout |
|---|---|---|---|
| 640×360 | 0.917 | 682×313 / 625×287 | header 48; middle 173 (stage 220×173, detail 440); shelf 64 (cards 92×56, scroll); detail content 163 |
| 667×375 | 0.917 | 711×329 | middle 189 (stage 229, detail 460) |
| 375×667 portrait | 0.917 | 393×648 / 360×594 | stage 377×223; detail 377×163; 5×3 grid of 68×56 cards (180) |
| 1920×1080 | 1.53 | 880×420 (max) / 1348×644 | middle 280 (stage 285, detail 573) |
| 1280×720 | 0.99 | 880×420 | as above |
| 768×1024 tablet portrait | 1.45 | 514×651 | stage 498×226, grid of 92×56 cards |

- **Detail column**: title 24, track 28, three 16 px lines and the gaps, then a 48 px button row on the column's foot.
- **Button row**: Upgrade takes 1.5 shares, so its longest refusal ("Needs ★ Hard on Forest Road") stays at two lines.
  - With four buttons: 93/93/93/140 at 640×360, and 79/79/79/119 in portrait.
  - With two buttons: 150/225, or 148/222 in portrait.
- **Pips**: 19 wide at 640×360, 16 in portrait, 25 on a monitor.
- **Taps**: every tap target is ≥ 48 design px, which is 44.0 physical px at the minimum scale.
- **Card names**: a portrait card is 68 wide, so its name scales from 11 down to 8 (the bottom bar's floor) instead of
  truncating "Flamethrower".

## Behaviour and the rulings I took (inside the contract)

**The pure model**
1. **Pips.** Lit = inside the window and at or below the tier. Open = inside the window and above it. Dim = outside.
   - An unowned family shows its whole window as **open**, with nothing lit. That is my reading of "the window lit",
     so the shelf never implies tiers that are not held.
   - A relic is one lit pip: Spinblade owned is pip 20 lit, carrying both the start and top marks.
2. **Shelf.** Every family with a valid def is shown (15 today).
   - Order: by window start, then melee before ranged, then name. A family with no window goes last.
   - Hints: the secret first ("Hidden on Forest Road"), then the `found` text, as L2 W2 did. With L3-25 every
     non-starter has one; the real-data case checks it.
3. **Next line.** It uses `Armory.Preview` with the held, else the saved, else the default style's damage.
   - The shipped Longbow reads "T2: 68 → 111 dmg · HP +20 → +30".
   - Unowned: "Not found yet · <hint>", wrapping into the cost line's room.
   - Owned with no window: "Cannot be upgraded", and Upgrade is hidden.
4. **Cost line.** "100 Timber · Forest Road"; a band's top adds " · needs ★ Hard" while that star is missing.
   - Hidden at the peak, for an unbuilt band (placeholder materials never show) and for an unowned family.
5. **Upgrade button.** Live only on `UpgradeVerdict == nil`, reading "Upgrade T<n>". Otherwise:

   | Verdict | Button |
   |---|---|
   | peak | "At its peak" |
   | notBuilt | "Comes with Castle" (the map node's name, since there is no level file) |
   | needsStar | "Needs ★ Hard on Forest Road" |
   | insufficientFunds | "Need N more Timber" |
   | busy | "Only in the lobby" |
   | locked, invalid | hidden |

   One upgrade in flight at a time.
6. **Equip and styles.** Equip is live on `FamilyVerdict == nil`; the held family reads "Equipped".
   - Style buttons on the held family read "A: Pierce + blast" (the held one is held, the other switches). On another
     family they read "Equip A" / "Equip B".
   - Equip sends the saved style, else the default.
   - One equip in flight at a time.
   - Equip refusals: busy "Only in the lobby", anything else "Try again". The old panel's "Not yours yet" and "Can't
     equip that" are gone, per L3-21's "anything else".

**The screen**
7. **Presses.** A press disables the button until its answer, 3 s at most.
   - An accepted upgrade stays "Upgrading..." until the Snapshot shows the tier, so a stale T2 can never invite a
     second purchase. The 3 s timeout still frees it.
   - An accepted equip shows as held until the host's next `SetHeld`, as L2 W2 did.
   - Toasts: "Longbow: T2", "Warhammer equipped", or the refusal in the button's words.
8. **Gamepad A** (L3-22, unverified in Studio). While open, A is bound at `High + 1` and sunk, which stops the jump.
   One press router handles every case:
   - The action presses `GuiService.SelectedObject` itself.
   - Engine presses are skipped while A is held, and for 0.2 s after release. This covers an engine press on release
     landing on the button the press moved the selection to (a tab's first Buy).
   - The action presses nothing if the engine already pressed within the debounce, in case the engine runs first.
   - Each button also has a 0.2 s debounce. Every action press is gated by its in-flight wait, so a double press can
     never buy twice.
9. **Other inputs.**
   - B closes, LB/RB switch tabs, and Y toggles while available when `padToggle` is set.
   - Esc and `GuiService.MenuOpened` close it, as does a tap on the scrim.
   - The frame is a SelectionGroup with Stop on all four sides.
   - Selection returns to the selected card whenever it lands on nothing.
   - A gamepad selection landing on a card selects that family, so the stage follows the d-pad.
10. **Motion.** The only animation is the stage text popping in on a new selection, gated on `Theme.lowEndDevice`
    (never `reducedMotion`) and timed by `Motion.Info`. There is no sound call anywhere.
11. **Wallet.** It lists the material of every built band (`Armory.BuiltBands`), then Valor: "0 Timber · 0 Valor"
    today.

## Tests and gates

- **`tests_l3_ui.luau`**: 109 checks, covering:
  - shelf order and ties, hints and their precedence, ownership and the held pair;
  - `LoadoutOf`'s fallback, pip states and marks, relic and no-window cases;
  - the next and cost lines (the contract's "T5: 303 → 500 dmg · HP +80 → +110" example included);
  - every Upgrade, Equip and style state, and the verdict order (peak before busy, busy before the star);
  - pending presses, refusal and ok toasts, the wallet;
  - the shipped files on a fresh profile.
- **Harness**: `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`
  gives `HARNESS: PASS (3,537 checks, …)`. A has registered `Format`, `ArmoryModel` and `tests_l3_ui.luau`.
- **Mutants**: 22, all caught, each by 1–8 checks, with a clean baseline of 0 of 109. They were run from a scratch
  runner over the real harness prelude. The entries for A are below.
- **stylua** `--check`: clean on my nine files. It needed two passes: stylua is not idempotent on a few call shapes
  in the case file.
- **selene**: 0/0/0.
- **luau-lsp** (`--definitions=tools/types/globalTypes.d.luau`, both sourcemaps regenerated with rojo into scratch):
  0 diagnostics over `src/client` + `src/shared` on the hub map, and over `src/combat/client` + the mapped hub UI files
  + `src/shared` on the combat map. That includes B's two hosts, coded against `ArmoryScreen.Handle`.
- **Compile gate**: `py tools/check_compile.py` PASS (177 files). My largest top level is 36, against a cap of 180.
- **`rojo build`**: both `default.project.json` and `combat.project.json` build (to scratch).

## For the other owner

**luau-engineer A — `tools/crowd_harness/mutate.py`.**
- FILES already has `Format.luau` and `ArmoryModel.luau`.
- Each text below occurs exactly once in `src/client/UI/ArmoryModel.luau` as it stands.
- Python `"\t"` and `"\n"` are literal tabs and newlines, as in the file.

```python
ARMORY_MODEL = "src/client/UI/ArmoryModel.luau"
L3_UI_MUTATIONS = {
    "l3 ui: the shelf runs against window starts": (ARMORY_MODEL, "\t\t\treturn aStart < bStart\n", "\t\t\treturn aStart > bStart\n"),
    "l3 ui: ranged before melee on one start": (ARMORY_MODEL, "return SLOT_ORDER[a.slot] < SLOT_ORDER[b.slot]", "return SLOT_ORDER[a.slot] > SLOT_ORDER[b.slot]"),
    "l3 ui: a family with no window first": (ARMORY_MODEL, "local NO_WINDOW = math.huge", "local NO_WINDOW = 0"),
    "l3 ui: a found entry beats the secret's hint": (ARMORY_MODEL, "\t\t\t\tand where[family] == nil\n", ""),
    "l3 ui: an owned family keeps its hint": (ARMORY_MODEL, "hint = if owned then nil else hints[family],", "hint = hints[family],"),
    "l3 ui: the held pair ignores the saved loadout": (ARMORY_MODEL, "return Unlocks.LoadoutOf(inputs.combat, inputs.weapons, fallback)", "return { melee = fallback.melee, ranged = fallback.ranged, variants = {} }"),
    "l3 ui: the tier's own pip is not lit": (ARMORY_MODEL, "state = if card.owned and tier <= card.tier then", "state = if card.owned and tier < card.tier then"),
    "l3 ui: an unowned window is lit": (ARMORY_MODEL, "state = if card.owned and tier <= card.tier then", "state = if tier <= card.tier then"),
    "l3 ui: pips lose their band colour": (ARMORY_MODEL, "color = bandColor(inputs, band),", "color = nil,"),
    "l3 ui: the next line ignores the held style": (ARMORY_MODEL, "nextLine = nextLine(inputs, card, equipVariant),", "nextLine = nextLine(inputs, card, card.default),"),
    "l3 ui: the cost line forgets the star": (ARMORY_MODEL, "if bandTop and not hasStar(inputs, levelId) then", "if bandTop then"),
    "l3 ui: an unbuilt band's cost shows": (ARMORY_MODEL, "if levelId == nil or inputs.built[levelId] ~= true or material == \"\" then", "if levelId == nil or material == \"\" then"),
    "l3 ui: Upgrade is live whatever the verdict": (ARMORY_MODEL, "\t)\n\tif verdict == nil then\n\t\tlocal nextTier", "\t)\n\tif true then\n\t\tlocal nextTier"),
    "l3 ui: two upgrades in flight": (ARMORY_MODEL, "return { visible = true, live = pending == nil, text = text, look = \"action\" }, nextTier", "return { visible = true, live = true, text = text, look = \"action\" }, nextTier"),
    "l3 ui: Equip ignores the gate": (ARMORY_MODEL, "\t\tvariant,\n\t\tinputs.gateOpen\n\t)", "\t\tvariant,\n\t\ttrue\n\t)"),
    "l3 ui: the held family is not Equipped": (ARMORY_MODEL, "\tif card.held then\n\t\treturn { visible = true, live = false, text = TEXT.equipped, look = \"held\" }", "\tif false then\n\t\treturn { visible = true, live = false, text = TEXT.equipped, look = \"held\" }"),
    "l3 ui: two equips in flight": (ARMORY_MODEL, "\t\t\tlive = pending.equipFamily == nil,\n", "\t\t\tlive = true,\n"),
    "l3 ui: the held style is not held": (ARMORY_MODEL, "if card.held and heldKey == variant.key then", "if false then"),
    "l3 ui: busy toasts Try again": (ARMORY_MODEL, "\tif reason == \"busy\" then\n\t\treturn TEXT.busy\n\tend\n\tif action", "\tif action"),
    "l3 ui: the shortfall is the whole price": (ARMORY_MODEL, "local short = amount - (combat.materials[material] or 0)", "local short = amount"),
    "l3 ui: the wallet shows unbuilt bands": (ARMORY_MODEL, "Armory.BuiltBands(armory, inputs.built)", "Armory.BuiltBands(armory, { forestRoad = true, castle = true })"),
    "l3 ui: the screen opens on the ranged family": (ARMORY_MODEL, "if card.family == held.melee then", "if card.family == held.ranged then"),
}
MUTATIONS.update(L3_UI_MUTATIONS)
```

**Lead.** Nothing needed: `combat.project.json` already maps the seven files.

**Everyone.** The `Combat.luau` structural-copy type errors and the `ExpeditionPanel.luau:816` error, both seen
mid-wave, were fixed by their owners before I finished.

## What to check in Studio (the mobile emulator included)

1. **The lobby, keyboard.** Boot `proving.rbxl`, press K:
   - it opens on Weapons with the Broadsword selected;
   - the stage reads MELEE / Broadsword / T1;
   - the track shows pips 1–12 open with 1 lit, green for the Forest band;
   - the shelf runs Broadsword, Longbow, Flamethrower, Warhammer, … Spinblade.

   Esc, X and a tap outside each close it.
2. **Buy T2.** Clear Forest Road on Normal (or press T for 500 Timber), open K, select the Longbow, press "Upgrade T2":
   - the button reads "Upgrading...";
   - the toast reads "Longbow: T2";
   - the track lights 2 and the wallet drops 100.
3. **The band top.** At T3 the cost line reads "500 Timber · Forest Road · needs ★ Hard" and the button "Needs ★ Hard on
   Forest Road". After U it reads "Upgrade T4".
4. **Styles.** On the Longbow: "A: Pierce + blast" is held and "B: Quick shot" switches. On the Splitbow (after its
   lever) the buttons read "Equip A" / "Equip B".
5. **The hub.** The same screen opens on K and the bottom bar's Armory key. The Abilities tab is read-only there.
6. **Mobile emulator, 640×360 landscape:**
   - the header, the 173-tall middle and the shelf fit inside the frame;
   - nothing overlaps the stage;
   - the shelf scrolls sideways;
   - every button is at least 44 px.
7. **Mobile emulator, 375×667 portrait** (the hub): stage, then detail, then a 5×3 grid. Check the card names in
   68-wide cards, which scale down to 8 at the smallest.
8. **Gamepad** (L3-36, unverified):
   - Y opens it in the lobby, LB/RB switch tabs, B closes;
   - the d-pad moves within the frame and never leaves it;
   - **A presses a button without jumping, and presses it once** (watch the toasts: one upgrade per press);
   - A on the Abilities tab must not also press the Buy it lands on.
9. **Low graphics (quality ≤ 3).** The stage text no longer pops in on a selection. Nothing else animates.
