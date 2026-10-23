# L4 W3 fix round — ui-engineer A (hub client) report

Rulings: F7 (client half), F11, F12, F13 (MapScreen re-pointed, the pin list for HubMap), F16
(`docs/prompts/l4-w3-fix-round.md`). Relays adopted: `relay-a2.md` (`RunLines.ReadSummary`, `MapRules.FirstPick`) and
`relay-uib.md`'s fix-round head (`RunTally.Wallet`). Nothing committed. The ArmoryScreen R9 toggle and every project
file are untouched.

## Files

- **New `src/client/UI/TouchHold.luau`** (F11): `Hold(reason)` / `Release(reason)`, one count for the whole hub. Touch
  controls are off while any hold is out and come back to what the FIRST hold found when the last one goes. A reason
  counts once, so a repeated Hold or Release of one reason changes nothing. It is not mapped into the combat place
  (only `HubMap` and `UIController` require it).
- **New `tools/crowd_harness/tests_l4w3_hub.luau`** (mine, 19 cases). The designer has already put it, and `TouchHold`,
  in `run_harness.py` SOURCES / TESTS. It runs the real module against a fake `GuiService` (tests.luau's `services`).
  It covers the count, idempotence, a stray release, controls already off, and "only the first hold puts a value aside".
  It also runs every hand-off against a stand-in for ArmoryScreen's R9 toggle, in the hub's order, and shows that the
  other order leaves the controls off (this is why the order lines below are pinned).
- **`src/client/UI/HubMap.luau`**:
  - F11: the map takes its hold in `onOpenChanged(true)`, *after* `deps.onOpenChanged(true)`. That is where the host
    closes the Armory, so the R9 toggle has given the value back first. On close, the hold is released first and then
    `deps.onOpenChanged(false)` runs. `Destroy` also releases the hold, because `MapScreen.Destroy` reports no close.
  - F13: the first MapState seeds through `MapRules.FirstPick`.
  - F16: a new `deps.toast`. Pressing the key without `Config/Expeditions` toasts "Expeditions are unavailable" on every
    tap. The Output warning still fires once.
- **`src/client/UI/MapScreen.luau`** (F13): `MapScreen.FirstPick` is deleted, because ui B re-pointed
  `CombatUIController` to `MapRules.FirstPick` in this round. MapScreen now has no copy and no forward of the rule, and
  no longer requires `MapRules`. The header comment says where the rule now lives.
- **`src/client/Controllers/UIController.luau`**:
  - F7: the ExpeditionSummary listener reads through `RunLines.ReadSummary(payload)`. The local `readRunSummary` is gone.
  - F12: `star = false`. `hasFirstClear` and `REPORT.firstClearKind` are gone, and deviation 2 is withdrawn.
  - F11:
    - `runTally` is now declared near `hubMap`, and a new `reportShown()` reads it.
    - The bar's Expedition key and the Armory branch of `togglePanel` both do nothing while the report is up.
    - `togglePanel` closes the map before `screen.Toggle()` when the Armory is about to open.
    - The report closes the Armory and the map, takes its hold (`REPORT.touchHold`) and then calls `card.Show`.
    - Dismiss calls `card.Hide()` and then releases the hold.
  - F16: the map's `toast` dep shows an error toast.
  - Also: `tallyWallet` builds its wallet with `RunTally.Wallet(current.state.cash, current.state.combat,
    tallyMaterial)`, ui B's shared builder. The cash source (review p6) is now one call line to pin. The builder also
    reads NaN and infinity as 0.

## F11 proof

**(1) The card never opens over the Armory.**
- The hub's card is shown in one place: `flushExpeditionSummary`'s `card.Show({` (the other `card.Show(invite)` is the
  invite toast).
- Right before that call, in the same synchronous run, flush calls `armory.Close()`. `ArmoryScreen.setOpen(false)` is
  synchronous: it hides the root, gives back its R9 value, and calls `onOpenChanged(false)`. In the hub that callback
  only sets the bar's active key and shows the strip, so it opens nothing.
- **While the card is up, nothing in the hub can open the Armory:**
  - Its only opener in the hub is `togglePanel("armory")` → `screen.Toggle()`. The K listener and the bar's Armory key
    both route there.
  - The hub passes `padToggle = false`, so `bindPadToggle` returns at once and no pad toggle is bound.
  - Nothing calls `armoryScreen.Open`.
  - That `togglePanel` branch now requires `not reportShown()`.
- The card's visibility (`scrim.Visible`) goes false only through `hide()`: our Dismiss, or `Destroy`, which the hub
  never calls. So "up" lasts from Show to Dismiss, the same span as the hold.
- The map is closed the same way before the card shows, and cannot open under it: the bar's key checks `reportShown()`,
  and `HubMap.Toggle` from that key is the map's only opener. If the map stayed open, its bound arrows and Enter would act
  under the card.

**(2) Touch controls always come back to the value they had before.**
- There are two savers: ArmoryScreen's own R9 toggle and TouchHold's count (holds `hubMap` and `runReport`).
- If both had a value put aside at once, the one that let go second would restore the other's "off". The hub keeps
  them apart by order:
  - **The Armory opens** only through `togglePanel`. With the report up it is refused, so no `runReport` hold is out.
    Otherwise `map.Close()` runs first, which releases `hubMap`. So when the R9 toggle saves, no hold is out.
  - **A `hubMap` hold** is taken after `deps.onOpenChanged(true)`, whose `screen.Close()` has already restored the R9
    value. So when the count saves, the Armory has nothing out.
  - **The `runReport` hold** is taken after flush's `armory.Close()`.
- So at every moment at most one saver holds a value, and each restores what it found. The reviewer's
  Armory → map → Armory hand-off is the case "hand-off Armory -> map -> Armory: on at the end".
- Before this fix the order was the opposite in both directions. ArmoryScreen saved inside `setOpen`, before its own
  `onOpenChanged` closed the map, and HubMap called the host only after it opened. The "wrong order" cases show what
  that would do: controls over the Armory, then off for good.

**(3) The combat place is unaffected.** It maps neither TouchHold nor HubMap nor UIController, and its HUD is
DisplayOrder 1.

## Layout (mental check, nothing moved)

No size or position changed this round. With touch controls off while the map or the report is up, the jump button
(70 px at w − 95, h − 90 on short sides ≤ 500) is gone. So the review's table clears: Depart and Party & runs at
640×360 and 667×375, and Dismiss on the two-column card. At 375×667 and 1920×1080 the button never overlapped (portrait
puts Dismiss at the card's centre bottom; desktop has no TouchGui). Tap targets are unchanged (≥ 48 design px). The F16
toast uses the existing toast lane.

## Gates (2026-10-23, from `tycoon-p5`, everyone's in-flight edits in the tree)

- `stylua --check` on my five files: clean. `selene` on my four source files: 0 errors, 0 warnings.
- `luau-lsp analyze`, with sourcemaps written to my scratch:
  - hub (`src/client src/server src/shared`): 0 diagnostics;
  - combat (`src/combat src/shared`): 0 diagnostics.
- `py tools/check_compile.py`: PASS, 188 files.
- `rojo build -o build/test.rbxl`: built. The combat place also builds (into scratch).
- **Harness** (`HARNESS_BUNDLE=bundle_uiA.luau`, the repo's own `run_harness.py` with the designer's SOURCES / TESTS):
  - all 19 of my cases ok, at both runs;
  - the verdict reads FAIL at both runs, and every failure is a WaveService depart pin from luau B's F1-F5 and the
    designer's re-aim, both in flight at the time:
    - first run, 6 of 5,228: `departStartLevel`, `departWrites`, `openDepart`, `resetDepart`, `resetOpened`,
      `departStepThenStart`;
    - second run: `askedBroadcast`, `bootOpened`, `buildDepart`, `departLive`, `departPcall` and others, all read as nil;
  - none touches a file of mine.
  - Re-run once they land.
- **F11 shown failing without the fix.** Each TouchHold mutant (entries 1-6 below) was run through a scratch copy of the
  tree with my cases added (`scratchpad/l4-w3-fixUiA/hubrun.py`; the copy is deleted). The unmutated copy fails 0 of my
  19 cases, and each mutant fails some of them:

  | # | Mutant | My cases failed |
  |---|---|---|
  | 1 | the Hold guard removed | 7 |
  | 2 | `count == 1` → `>= 1` | 4 |
  | 3 | `= false` → `= true` | 6 |
  | 4 | the Release guard removed | 6 |
  | 5 | `count == 0` → `true` | 1 |
  | 6 | the restore removed | 11 |

  At the first run the whole harness was green (5,100 checks). The order lines in HubMap and UIController are text and
  need the designer's pins (below). The "wrong order" cases show the stand-in failing in exactly the way those pins
  guard against.
- **A filtered `mutate.py` was not run.** The designer had not yet written entries on my files (only `TOUCH_HOLD` in
  FILES), and mutate refuses to start while the baseline harness fails (others' in-flight depart pins, at both of my
  runs). The 23 entries below each match their file exactly once today (counted).
- My earlier wave's leftover `tools/crowd_harness/mutant_uiA/` (gitignored) is deleted. No bundle of mine is left
  behind.

## For the designer (pins and `mutate.py` entries)

The pin texts are exact, and each occurs exactly once at the time of writing (counted). File paths:
`src/client/UI/HubMap.luau` (HUB_MAP), `src/client/Controllers/UIController.luau` (HUB_UI),
`src/client/UI/TouchHold.luau` (TOUCH_HOLD, already in FILES).

**Pins** (text, count 1):

| Label | File | Text |
|---|---|---|
| p4 / F13 call line: Depart sends Party & runs' toggle, never a literal | HUB_MAP | `"\t\trequest:FireServer(levelId, difficulty, deps.isPublic())\n"` |
| F13: the hub seeds through the shared rule | HUB_MAP | `"\t\t\tlocal nodeId, difficulty = MapRules.FirstPick(map.difficulties, state)\n"` |
| F11: host closes (the Armory) before the map's hold | HUB_MAP | `"\t\tif open then\n\t\t\tdeps.onOpenChanged(true)\n\t\t\tTouchHold.Hold(TOUCH_HOLD)\n"` |
| F11: the map's close releases first | HUB_MAP | `"\t\telse\n\t\t\tTouchHold.Release(TOUCH_HOLD)\n\t\t\tdeps.onOpenChanged(false)\n"` |
| F11: Destroy releases | HUB_MAP | `"\t\t\tTouchHold.Release(TOUCH_HOLD)\n\t\t\tfor _, connection in connections do\n"` |
| F16: no config → a toast | HUB_MAP | `"\t\telse\n\t\t\tdeps.toast(UNAVAILABLE_TEXT)\n"` |
| p6: the city wallet's cash is the city's state | HUB_UI | `"\t\treturn RunTally.Wallet(current.state.cash, current.state.combat, tallyMaterial)\n"` |
| F7: one summary reader | HUB_UI | `"\t\t\tlocal summary = RunLines.ReadSummary(payload)\n"` |
| F12: the city card claims no star | HUB_UI | `"\t\t\tstar = false,\n"` |
| F11: what "the report is up" reads | HUB_UI | `"\t\treturn card ~= nil and card.IsVisible()\n"` |
| F11: the map never opens over the report | HUB_UI | `"\t\t\t\tif model ~= nil and combatRemotesReady and not reportShown() then\n\t\t\t\t\tmap.Toggle()\n"` |
| F11: the Armory never opens over the report | HUB_UI | `"\t\t\t\tand combatRemotesReady\n\t\t\t\tand not reportShown()\n\t\t\tthen\n"` |
| F11: the map lets go before the Armory opens | HUB_UI | `"\t\t\t\tif map ~= nil and not screen.IsOpen() then\n\t\t\t\t\tmap.Close()\n\t\t\t\tend\n\t\t\t\tscreen.Toggle()\n"` |
| F11: the map's open closes the Armory (before its hold) | HUB_UI | `"\t\t\t\tif open then\n\t\t\t\t\tclosePanels()\n\t\t\t\t\tlocal screen = armoryScreen\n\t\t\t\t\tif screen ~= nil then\n\t\t\t\t\t\tscreen.Close()\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\t\tbottomBar.SetActive(if open then \"expedition\" else openPanelKey)\n"` |
| F11: the report closes the Armory and the map, then holds, then shows | HUB_UI | `"\t\tlocal armory = armoryScreen\n\t\tif armory ~= nil then\n\t\t\tarmory.Close()\n\t\tend\n\t\tlocal map = hubMap\n\t\tif map ~= nil then\n\t\t\tmap.Close()\n\t\tend\n\t\tTouchHold.Hold(REPORT.touchHold)\n\t\tcard.Show({\n"` |
| F11: Dismiss releases | HUB_UI | `"\t\t\t\t\tcard.Hide()\n\t\t\t\t\tTouchHold.Release(REPORT.touchHold)\n"` |
| F16: the map's toast is an error toast | HUB_UI | `"\t\t\t\ttoast.Show(text, Theme.TOAST_ERROR_SECONDS, true)\n"` |

Counts that should stay as they are (a second call is a new path that needs reading): in HubMap, `TouchHold.Hold(` 1,
`TouchHold.Release(` 2, `deps.isPublic()` 1. In UIController, `TouchHold.Hold(` 1, `TouchHold.Release(` 1,
`screen.Toggle()` 1, `map.Toggle()` 1, `card.Hide()` 1.

**`mutate.py` entries.** Each is (file, old, new). The TouchHold six are already proven caught by my cases. The rest
are caught only once the pins above exist.

TouchHold (caught by `tests_l4w3_hub.luau`):
1. `"\tif holds.reasons[reason] == true then\n\t\treturn\n\tend\n\tholds.reasons[reason] = true\n"` → `"\tholds.reasons[reason] = true\n"`
2. `"\tif holds.count == 1 then\n"` → `"\tif holds.count >= 1 then\n"`
3. `"\t\tGuiService.TouchControlsEnabled = false\n"` → `"\t\tGuiService.TouchControlsEnabled = true\n"`
4. `"\tif holds.reasons[reason] ~= true then\n\t\treturn\n\tend\n\tholds.reasons[reason] = nil\n"` → `"\tholds.reasons[reason] = nil\n"`
5. `"\tif holds.count == 0 then\n"` → `"\tif true then\n"`
6. `"\t\t\tGuiService.TouchControlsEnabled = saved\n"` → `"\t\t\tlocal _ = saved\n"`

HubMap (caught by the pins):

7. p4: `"\t\trequest:FireServer(levelId, difficulty, deps.isPublic())\n"` → `"\t\trequest:FireServer(levelId, difficulty, true)\n"`
8. `"\t\t\tdeps.onOpenChanged(true)\n\t\t\tTouchHold.Hold(TOUCH_HOLD)\n"` → `"\t\t\tTouchHold.Hold(TOUCH_HOLD)\n\t\t\tdeps.onOpenChanged(true)\n"` (the wrong order)
9. `"\t\t\tTouchHold.Release(TOUCH_HOLD)\n\t\t\tdeps.onOpenChanged(false)\n"` → `"\t\t\tdeps.onOpenChanged(false)\n"`
10. `"\t\t\tTouchHold.Release(TOUCH_HOLD)\n\t\t\tfor _, connection in connections do\n"` → `"\t\t\tfor _, connection in connections do\n"`
11. `"\t\t\tlocal nodeId, difficulty = MapRules.FirstPick(map.difficulties, state)\n"` → `"\t\t\tlocal nodeId: string?, difficulty: string? = nil, nil\n"`
12. `"\t\telse\n\t\t\tdeps.toast(UNAVAILABLE_TEXT)\n"` → `""`

UIController (caught by the pins):

13. p6: `"\t\treturn RunTally.Wallet(current.state.cash, current.state.combat, tallyMaterial)\n"` → `"\t\treturn RunTally.Wallet(0, current.state.combat, tallyMaterial)\n"`
14. `"\t\t\tlocal summary = RunLines.ReadSummary(payload)\n"` → `"\t\t\tlocal summary = payload :: Types.RunSummary?\n"`
15. `"\t\t\tstar = false,\n"` → `"\t\t\tstar = #summary.lines > 0,\n"`
16. `"\t\treturn card ~= nil and card.IsVisible()\n"` → `"\t\treturn false\n"`
17. `"if model ~= nil and combatRemotesReady and not reportShown() then"` → `"if model ~= nil and combatRemotesReady then"`
18. `"\t\t\t\tand combatRemotesReady\n\t\t\t\tand not reportShown()\n\t\t\tthen\n"` → `"\t\t\t\tand combatRemotesReady\n\t\t\tthen\n"`
19. `"\t\t\t\tif map ~= nil and not screen.IsOpen() then\n\t\t\t\t\tmap.Close()\n\t\t\t\tend\n\t\t\t\tscreen.Toggle()\n"` → `"\t\t\t\tscreen.Toggle()\n"`
20. `"\t\t\t\t\tclosePanels()\n\t\t\t\t\tlocal screen = armoryScreen\n\t\t\t\t\tif screen ~= nil then\n\t\t\t\t\t\tscreen.Close()\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\t\tbottomBar.SetActive(if open then \"expedition\""` → `"\t\t\t\t\tclosePanels()\n\t\t\t\tend\n\t\t\t\tbottomBar.SetActive(if open then \"expedition\""`
21. `"\t\tlocal armory = armoryScreen\n\t\tif armory ~= nil then\n\t\t\tarmory.Close()\n\t\tend\n"` → `""`
22. `"\t\tTouchHold.Hold(REPORT.touchHold)\n"` → `""`
23. `"\t\t\t\t\tcard.Hide()\n\t\t\t\t\tTouchHold.Release(REPORT.touchHold)\n"` → `"\t\t\t\t\tcard.Hide()\n"`

**Changed lines a pin or `mutate.py` entry reads today:** none.
- I checked `run_harness.py`, `mutate.py` and `tools/*.py` for `MapScreen`, `node.stars == 0`, `readRunSummary`,
  `hasFirstClear`, `tallyWallet` and `current.state.cash`: no matches.
- The `HUB_UI` pins `uiWaiting`, `uiReplay` and `uiPushWaits`, the `uiKeys` / `uiPush` bodies and the three "l3fix2 F5"
  entries read `refreshCombatKeys` and `pushArmory`, which are unchanged.
- The probe p3 (`#node.stars == 0`) now lives in luau A's `MapRules.FirstPick`.

Changed text that a new entry might need (file: old → new):
- HubMap: `MapScreen.FirstPick(map.difficulties, state)` → `MapRules.FirstPick(map.difficulties, state)`.
- HubMap: `deps.onOpenChanged(open)` is gone. It is now the two branch lines above.
- UIController: `star = hasFirstClear(summary.lines),` → `star = false,`.
- UIController: `readRunSummary(payload)` → `RunLines.ReadSummary(payload)`.
- UIController: the `tallyWallet` body is now the single `RunTally.Wallet` line above.
- UIController: `if screen ~= nil and model ~= nil and provingConfig ~= nil and combatRemotesReady then` → the
  multi-line `if` with `and not reportShown()`.
- UIController: `if model ~= nil and combatRemotesReady then` (the bar's Expedition key) → with `and not reportShown()`.
- MapScreen: `function MapScreen.FirstPick(...)` is deleted, body and all.

## For the other owners

- **ui B:**
  - `MapScreen.FirstPick` is deleted. Your `CombatUIController` already calls `MapRules.FirstPick`, so nothing else
    reads it.
  - I adopted `RunTally.Wallet` in the hub.
  - Your F14 glyph and TallyRules move are untouched by me.
- **luau A:** `RunLines.ReadSummary` is now the hub client's only reader of the card. `MapRules.FirstPick` is the hub's
  seed.
- **Lead:**
  - No project-file change: TouchHold is hub-only, in `src/client/UI`.
  - The hub's report no longer claims a star (F12). Ben's §9 B check should expect no ★ on the city card.

## What to check in Studio (and the mobile emulator)

- **Phone emulator at 640×360 (or 667×375) in `build\test.rbxl`:**
  - Open the map: the thumbstick and jump button vanish.
  - Close it (X, Escape or Party & runs): they return.
  - Open the Armory from the map, then the map from the Armory: after each close the controls are back. After
    Armory → map → Armory → close, they must be visible.
- **The bridge report (§9 B):**
  - No touch controls while the card is up, and they are back after Dismiss.
  - K does nothing while the card is up.
  - No ★ beside the title.
- **Without `Config/Expeditions`** (rename it in Studio): the Expedition key toasts "Expeditions are unavailable".
