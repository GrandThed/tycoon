# L4 W3 — ui-engineer A (hub client) report

Contract: `docs/prompts/l4-w3-contract.md` §2.4, §4.2 (hub host), §6 rows 1, 3, 5, 6, 7, 8 (client parts), §7 (ability
rows, difficulty note). Relays adopted: `relay-a.md` (Types, remotes, `RunLines.Read`) and `relay-uib.md` (RunTally API).
Nothing committed.

## What I built

- **`src/client/UI/HubMap.luau` (new)** — the hub host of the shared `MapScreen`:
  - The screen is built on first open, from `Catalog.GetExpeditionsConfig()` as it reads then (the Config folder may still
    be replicating at boot). Without the config it warns once and does not open.
  - It pulls its state: `RequestMapState` fires on open, on every `PartyState` while open, and after a refused Depart.
    `MapState` (connected the first time it exists) goes to `SetState`. The first one seeds the selection through
    `MapScreen.FirstPick`, the same rule the dungeon uses.
  - The `HubParty` (nil = solo) becomes `MapScreen.SetParty`'s list. Solo reads "Solo · A down ends the run"; a member who
    isn't the leader sees "Waiting for <leader>".
  - Depart sends `RequestExpedition(levelId, difficulty, isPublic())`. It stays busy until the `expedition` ActionResult
    (`OnAnswer`) or `Theme.EXPEDITION_DEPART_TIMEOUT_SECONDS` (8, moved out of `ExpeditionPanel`).
  - The footer reads **"Party & runs"** and opens that panel.
  - Keys while open: arrows / d-pad step, Enter / KeypadEnter / A depart, B closes. Escape is watched on `InputBegan`
    whether processed or not, and `GuiService.MenuOpened` closes the map too (the ArmoryScreen pattern). Bindings use
    `ContextActionService` at High+1, and keys already down at open pass through.
  - No sound and no new motion.
- **`MapScreen.luau`** (shared; the combat call site is unchanged):
  - `deps.returnText: string?` (nil = "Return to your city").
  - A difficulty's `note` (`LevelDifficulty.note`) stands on its button's second line in place of the recommended tier,
    so Brutal reads "Castle gear". That line is truncated at the end if a note is ever too long.
  - `Selected(): (string?, string)`, as ui B asked for the Studio R key.
  - `MapScreen.FirstPick(difficulties, state)`, the seed rule as a pure helper.
- **`ExpeditionPanel.luau`** → **"Party & runs"**:
  - What stays: the party strip, "Open to public" and the run list.
  - What went: the mission tiles, the Overdrive toggle, `Refresh`, `deps.missions` and `deps.onDepart`.
  - New: `IsPublic()`.
  - Run rows read "Forest Road · Normal" (node name and `difficultyNames`, with the ids as fallback), then "host · in the
    lobby / in a level · n/max". The registry advertises `wave` 0 only in the lobby.
- **`UIController.luau`** (mounting, wiring and deletions only):
  - The bar's Expedition key toggles `HubMap`. Party & runs opens from the map's footer.
  - One sheet at a time: the map, the Armory and any dock panel close each other. The Studio strip is hidden while the
    map is open.
  - `PartyState` → `hubMap.SetParty`; the `expedition` ActionResult → `hubMap.OnAnswer(ok)`. "Left behind" is read from
    the map's or the panel's in-flight lock.
  - The "locked" refusal now reads "That level is locked". The old text said "advance your city first", and the city no
    longer gates.
  - `readRunSummary` requires `title`, drops `missionId` / `overdrive`, and reads `lines` through `RunLines.Read`.
  - The mission list, `requestExpedition`, the Gear Power model field / reader / Delta field and the dead `refreshAll()`
    in the ChildAdded listener are gone.
- **Hub RunTally host** (in `UIController`, replacing `ExpeditionSummaryCard`):
  - `RunTally.new(screenGui, { modal = true, ... })`: the dim behind the card takes every tap, as the old report's
    scrim did, so a stray tap cannot buy a building (ui B's relay, via the lead).
  - Same chaining: the report is parked and flushed after the first snapshot and after the welcome-back card closes.
  - The view: kicker "EXPEDITION REPORT", `summary.title`, and subtitle "12m 5s · 112 kills".
  - `star` is true when a `firstClear` line is present. ui B's sketch passes false; a first clear only pays with a new
    star, so this is honest.
  - Rows come from `RunTally.Rows`, totals from `RunTally.Totals`, and the wallet from the HUD model (`cash`, `Owned` of the
    main material, `combat.valor`). The wallet is retargeted by `SetWallet` on every `refreshAll` while the card is
    visible.
  - The note "You fell — the rewards you earned are yours" shows when `died`. `nextAbility` comes from
    `RunTally.NextAbility(combat.abilities)`: an ability on sale first ("next: Double Jump · 10 Valor"), then the coming
    one. The first clear's Valor is its own row (`RunTally.Rows`).
  - One Dismiss button.
- **`ArmoryAbilityPage.luau`**: `Offers()` appends `abilities.upcoming` (config order; an entry missing a string field, or
  one whose id is already on sale, is skipped). Each upcoming row is a shade darker, with no price and no button. Where
  Buy would be it reads "With the Castle": `RunTally.WithText(with)` with a capital first letter, so this row and the
  report's "next:" line use the same words.
  It is never buyable (`buy` and `HasLiveBuy` skip it) and is the same in both places.
- **`TopBar.luau`**: the Gear Power chip and `SetPower` are gone.
- **`Theme.luau`**:
  - Deleted: `TOP_POWER_WIDTH`, `TOP_POWER_GAP`, `TOP_INCOME_WIDTH_POWER`, `TOP_LEGACY_WIDTH_POWER`, `TOP_POWER_MIN_TEXT`,
    `EXPEDITION_POWER_Y`, `EXPEDITION_TILE_PAD_BOTTOM`, `POWER_READY_RATIO`, `POWER_RISKY_RATIO`. Each had no other reader
    (grep).
  - Also deleted, once ui B removed `SummaryCard.luau`: `COMBAT_SUMMARY_WIDTH` and `COMBAT_SUMMARY_LINE_GAP`. The two old
    cards' Theme keys were checked one by one, and these were the only orphans.
  - Added, in one block: `EXPEDITION_DEPART_TIMEOUT_SECONDS = 8`.
  - None of `ExpeditionSummaryCard`'s Theme constants were its alone (`DIALOG_*`, `ERA_*`, `INFO_LINE_*` all have other
    readers).
- **`ExpeditionSummaryCard.luau`**: deleted.

## Gates (final run 2026-10-23 after the 15:16 reset, from `tycoon-p5`, everyone's code in)

- `stylua --check`: my seven files clean, and all of `src` clean.
- `selene`: my seven files 0 errors / 0 warnings. All of `src`: 0 errors, 1 warning (M11's `LegacyPanel` shadowing,
  which predates this wave).
- `luau-lsp` with the hub sourcemap (`src/client src/server src/shared`): 0 diagnostics. With the combat sourcemap
  (`src/combat src/shared`): 0 diagnostics. Both sourcemaps were generated into my scratch folder; the tracked ones are
  the lead's.
- `py tools/check_compile.py`: PASS, 187 files.
- `rojo build -o build/test.rbxl`: built. The combat place also builds (into scratch).
- Harness: **PASS, 4,994 checks.** The three `HUB_UI` pins (`uiWaiting`, `uiReplay`, `uiPushWaits`) are among them.
- `mutate.py "files:UIController.luau,ArmoryAbilityPage.luau,MapScreen.luau,HubMap.luau,ExpeditionPanel.luau,TopBar.luau,
  Theme.luau"` with `MUTATE_ROOT=mutant_uiA`: **14 run, 0 not caught.** The "UIController.luau" ending also matches
  ui B's `CombatUIController`. This ran before the reset, on the tree of about 13:00. No line it reads has changed in my
  files since.
- §12 `git grep -nE 'missionId|…|SetPower' -- src/client`: empty. `git diff --stat main` on PartyService, ProfileSchema,
  BottomBar, DebugPanel and LegacyPanel: empty.
- LF line endings on every file I wrote. My scratch `tools/crowd_harness/bundle_uiA.luau` and `mutant_uiA` are deleted.

## Layout (checked by arithmetic)

- **640×360 under the 58 px bar:** ScreenGui 640×302, scale 0.917 (MIN_SCALE), so 329.5 design px, the panel 682×313.5,
  and the map 442 wide.
  - The open Forest Road card on a phone (no key line, with "Party & runs" and the secrets row) is 316 design px. It runs
    2.5 px into the card's own bottom padding: the button stays inside the card and on screen.
  - With a keyboard at that size only the key line's bottom 4.5 px leave the screen. The dungeon's map has always had the
    same 2.5 px (Theme's secrets-row note).
- **667×375:** fits with 14 px to spare.
- **1920×1080:** scale 1.53, the panel capped at 960×540.
- **375×667 portrait:** the map column is 153 px and the nodes crowd it. MapScreen has never been laid out for portrait
  (carried from P5).
- **Tap targets:** every one is ≥ 48 design px (44 physical at MIN_SCALE). The upcoming row has no tap target.

## Deviations, and why

1. **Brutal's note replaces "T5" on the button's second line.** The contract says "on the difficulty's line". The button
   has three lines (name, tier, ×reward) in 52 px, and "T5 · Castle gear" (~100 px) doesn't fit a 66 px button. The tier
   line is the one that says what gear a difficulty asks for, so the note stands there.
2. **The hub card's `star` comes from a `firstClear` line**, not a constant false.
3. **`EXPEDITION_DEPART_TIMEOUT_SECONDS` moved to Theme**, so the map's Depart and the panel's Join share one constant
   (it was a local in ExpeditionPanel).
4. **The map's key hint repeats the dungeon's text** ("← → level · ↑ ↓ difficulty · Enter depart") rather than adding
   "Esc close": the extra words would be truncated in the 212 px card.

## What Ben must judge

- The city map itself: the Expedition key opens it, and "Party & runs" sits in its footer. Is that where party and runs
  belong?
- "Castle gear" in place of Brutal's "T5".
- The locked "Glide — With the Castle" row on the Armory's Abilities tab.
- The report card in the city after a bridge run (§9 B): rows, coins, wallet roll, the star, the Dismiss button.
- On a phone emulator at 640×360: the map card's bottom edge (2.5 px inside its padding).

## For the other owners

- **ui-engineer B:**
  - `MapScreen.Selected()` is in, with the signature you asked for.
  - `MapScreen.FirstPick(map.difficulties, state)` is available if you want combat's `seedMap` to share one rule
    (optional; the combat call site is untouched).
  - I ran `stylua src/client` once before narrowing it to my files, so it may have formatted `RunTally.luau` (idempotent).
  - Theme `COMBAT_SUMMARY_WIDTH` and `COMBAT_SUMMARY_LINE_GAP` are deleted (you asked me to check them); nothing else
    only the old cards read.
- **economy-designer:** no pin or `mutate.py` entry reads a line I changed.
  - The four `HUB_UI` texts (`run_harness.py` `uiWaiting`, `uiReplay`, `uiPushWaits`; `mutate.py` "l3fix2 F5" ×3) each
    still match exactly once.
  - No tool reads TopBar, ExpeditionPanel, MapScreen, HubMap, ArmoryAbilityPage or the Theme keys I removed.
  - `check_levels.py`'s THEME_KEYS are untouched.
- **luau-engineer A:**
  - HubMap fires `RequestMapState()` with no arguments and listens on `MapState`.
  - It sends `RequestExpedition(levelId, difficulty, public)` and reads `ActionResult` `action = "expedition"`
    (`locked` / `unavailable` / `notLeader` / `busy`).
  - The run list reads `levelId`, `difficulty`, `wave`, `partySize` and `relation`.
- **Lead:**
  - No project-file change is needed: `HubMap` lives in `src/client/UI` and the combat place doesn't need it.
  - Sourcemaps and place files are yours to regenerate.
  - For M11's merge: the Expedition key's routing is the `BottomBar.new` `onTap` closure in `UIController` (search
    "the Expedition key is the map's"). Put M11's unlock gate there.
