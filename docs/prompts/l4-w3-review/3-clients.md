# L4 W3 review, slice 3: the clients

Reviewer: roblox-reviewer (Opus), 2026-10-23. Diff: `git diff dce50da..93eb8e9` on `l4-w3`, restricted to:
- `src/client/UI/`: `HubMap`, `RunTally`, `ExpeditionPanel`, `MapScreen`, `ArmoryAbilityPage`, `TopBar`, `Theme`;
- `src/client/Controllers/UIController.luau`;
- `src/combat/client/`: `TallyHost`, `DepartLine`, `CombatHud`, `CombatUIController`;
- `combat.project.json`.

I read the new files in full and the changed ones around every hunk. Probes ran on a `git archive 93eb8e9` copy in the
scratchpad (`l4-w3-rev3/tree`).

**Result: 0 Critical, 0 Major, 3 Minor, 5 Suggestions.**

All layout numbers are in viewport px. They come from the real Theme sizes and from a Python port of `RunTally.relayout`
and `MapScreen.SetLayout` (`l4-w3-rev3/tally_layout.py`). Both hosts' ScreenGuis start under the 58 px top bar, so
scale = clamp(min(w/375, (h - 58)/667), 0.9167, 1.8).

## Minor

### m1. The two new hub modals sit under Roblox's touch jump button (DisplayOrder 0 against 0)

Where:
- `src/client/UI/HubMap.luau:345` (MapScreen built into the hub's `EraCityHUD`);
- `src/client/Controllers/UIController.luau:882` (`RunTally.new(screenGui, { modal = true, ... })`).

**What is wrong.**
- Both modals live in the hub's `EraCityHUD`, which has DisplayOrder 0. Roblox's `TouchGui` has DisplayOrder 0 too, and
  equal DisplayOrder has no defined draw order.
- TouchGui is created lazily, after the HUD, so in practice it usually draws on top.
- The combat place never had this problem, because its `ExpeditionHUD` is DisplayOrder 1.
- The fix pattern is already in the repo. L3 R9 makes `ArmoryScreen` set `GuiService.TouchControlsEnabled = false` while
  it is open (`ArmoryScreen.luau:814-820`). Neither HubMap nor the hub's RunTally host does this.

**Where the jump button lands.**
- The local PlayerModule places it at `TouchJump.lua:229-235`: 70 px, at (w - 95, h - 90), on screens whose short side is
  at most 500.
- TouchGui uses `DeviceSafeInsets`, so that position is measured on the full viewport.
- What the button covers:

| Viewport | Modal button | Button's viewport rect | Area under the jump button |
|---|---|---|---|
| 640×360 | Map **Depart** | x 429-623, y 252-296 | 70 × 26 px (its right 36%) |
| 640×360 | Map **Party & runs** | x 429-623, y 302-346 | 70 × 38 px |
| 640×360 | Report **Dismiss** (two-column card, totals column) | x 375-591, y 296-340 | 46 × 44 px (its full height) |
| 667×375 | Map **Party & runs** | | 70 × 44 px |
| 667×375 | Map **Depart** | | 70 × 11 px |
| 667×375 | Report **Dismiss** | | 33 × 44 px |

**Failure scenario.** A phone player in the city taps the right side of Depart, Party & runs or the report's Dismiss. The
character jumps behind the scrim and nothing departs. The jump button's art is also drawn over the card.

The report is a regression. The old `ExpeditionSummaryCard` was a 300-wide centred card with its button at the centre
bottom, around x 183-457. The new two-column card moves Dismiss into the bottom-right corner.

**Fix.**
- Use the ArmoryScreen pattern in both modals.
- Better, use one shared helper with a hold count, so that an Armory → map → Armory hand-off cannot restore the wrong
  value.
- Raising `EraCityHUD`'s DisplayOrder would also work, but it reorders every hub surface.

### m2. The city report's star comes from a first-clear line, and a Normal first clear has none (ui A deviation 2 is not correct)

Where: `src/client/Controllers/UIController.luau:187-194` (`hasFirstClear`) and `:924`
(`star = hasFirstClear(summary.lines)`).

**What is wrong.**
- A `firstClear` line exists only when `UnlockService.GrantFirstClear` returns a grant (`WaveService.EndRun`:
  `if given ~= nil then ArenaService.CreditSummary(..., RunCredit.FirstClearKey(...), ...)`). That needs a `firstClear`
  reward on the difficulty.
- `Levels/1_ForestRoad.json` at 93eb8e9 has: `normal` with none, `hard` with `{ family = "warhammer" }`, `brutal` with
  `{ valor = 25 }`.
- So the first star a player earns, Normal, shows ★ on the dungeon card (`result.star`) and no ★ on the city card. Hard and
  Brutal do show it.
- "A first clear only pays with a new star" is true. The rule needs the converse, "every new star pays a first clear", and
  that is false.
- Contract §9 B calls it "the same card over the city".

**Failure scenario.**
- In Ben's §9 B bridge test on a fresh save, he clears Forest Road on Normal. The dungeon card shows ★ and the city card
  shows none.
- A member with no profile also gets no line, so no star.

**Fix (pick one):**
- (a) Pass `star = false` in the hub, as ui B's sketch did. The city card then claims nothing.
- (b) Have the server carry the fact. That is a Types plus server change, so it is slice 1 and 2 territory. Two ways:
  - put a `star` flag or `stars` count on `RunSummary`, set where `MapRules.Award` is true;
  - credit an empty `firstClear` line for every awarded star (`if star then ...`, valor `given and given.valor or 0`). That
    also gives the dungeon card a "First Normal clear" row.

### m3. No gate reads any of W3's client logic: all 6 review probes pass the harness

Where: `CombatUIController.luau:1746-1748` and `:1801-1811` (holding and picked), `MapScreen.luau:230` (`FirstPick`),
`HubMap.luau:262-278`, `RunTally.luau:1398`, `UIController.luau:895-903`.

**What is wrong.**
- `run_harness.py` and `mutate.py` name none of: `HubMap`, `RunTally`, `TallyHost`, `DepartLine`, `MapScreen`,
  `CombatHud`, `ArmoryAbilityPage`, `ExpeditionPanel`.
- The only client pins are the pre-W3 `uiMerge*` and `HUB_UI` ones.
- Each probe below was applied to the archive, and the tree's own harness was run (`l4-w3-rev3/probe.py`,
  `probes.json`). Every one answers `HARNESS: PASS (4,994 checks)`:

| # | Mutation | Effect |
|---|---|---|
| p1 | `if pick ~= st.departPicked and node ~= nil` → `if node ~= nil` | The map reopens on every RunState (4 Hz) while `picked`, so it cannot be closed. |
| p2 | `local holding = ...` → `false` | The map opens over the countdown line. |
| p3 | `FirstPick`'s `#node.stars == 0` → `> 0` | Both hosts open on the wrong node. |
| p4 | HubMap sends `true` for `public` | Every hub run is public. |
| p5 | `local low = Theme.lowEndDevice` → `Theme.reducedMotion` | The exact gate the contract forbids. |
| p6 | The hub wallet's `cash = current.state.cash` → `0` | The roll starts and ends at $0. |

This is the same family as W1b slice 2's "the client half of a protocol sits under no gate". ui B says the new modules
need `game`, so they are not harness material. That is true of the files, not of the rules inside them.

**Fix.**
- Move the pure rules into a pure module the harness loads, give them cases and `mutate.py` entries, and pin each call
  line. The rules:
  - `DepartLine.Read`, `Text`, `NodeOf`;
  - the per-RunState depart decision, as one function `(depart, lastHolding, lastPicked) -> (open?, close?, select?)`;
  - `RunTally.Rows`, `Totals`, `WithText`, `NextAbility`;
  - `MapScreen.FirstPick`.
- At the least, add `mutate.py` text entries for p1, p2 and p5.

## Suggestions

### s1. Check in Studio that RunTally's rotated row badges are clipped

Where: `RunTally.luau:1493` (`newDiamond(frame, ...)`, `Rotation = 45`, inside the clipped `rowsClip` strip).

**Why it matters.**
- Older Roblox builds did not clip rotated GuiObjects through `ClipsDescendants`. CanvasGroup is the usual workaround.
- If the current engine still does this, every row scrolled out of the window still draws its Valor diamond above or below
  the window, over the subtitle or the divider.
- On the 640×360 card that is 2 or 3 rows of a 12-row run.

I could not settle this offline. If the badges escape, draw them unrotated: a "◆" glyph, or a square with a UICorner.

### s2. `TallyHost`'s re-show key reads `result.levelId`, which `isRunResult` does not check

Where: `TallyHost.luau:257`; `CombatUIController.luau:376-384`.

**Why it matters.**
- `table.concat` throws on a nil element.
- The server always sends `levelId` today; the leave card sends "".
- A throw would happen late in `onRunState`, and on every RunState. It would skip `st.phase`, `st.wave` and `st.stage`
  below it.

**Fix:** add `typeof(payload.levelId) == "string"` to `isRunResult`.

### s3. The hub reads the summary totals with no finiteness check

Where: `UIController.luau:150-162`, compared with `TallyHost.luau:110-141`.

**Why it matters.**
- The hub's `readRunSummary` accepts any number for `cash`, `valor` and each material.
- `Format.Cash(math.huge)` never returns: `while value >= 1000 do value /= 1000` loops forever.
- The hub server's `StudioBridge.readSummary` (slice 1) does not check finiteness either.
- TeleportData passes through the client, so a forger can hang only their own client. That is self-harm, not an exploit.
- Still, two readers of one shape with two different rules is the drift the brief asks about.

**Fix:** one shared pure `ReadSummary`, beside `RunLines.Read`, that both hosts and the bridge call, with finite ≥ 0
totals.

### s4. `RunTally.NextAbility` trusts the `abilities.upcoming` entries that `ArmoryAbilityPage.Offers` checks

Where: `RunTally.luau:396-403`, compared with `ArmoryAbilityPage.luau:126-152`.

**Why it matters.**
- An entry with no `name` throws on `LOOK.next .. def.name`, inside `TallyHost.show`, from `onRunState`.
- The Armory tab skips the same entry quietly.
- The shipped data is gated only for `with`: `tests_l4w3` "every shipped upcoming ability names a map node" checks that
  field alone.

**Fix:** apply the same four type checks in `NextAbility`, or share one checked list.

### s5. The city's Expedition key stays on screen and does nothing when `Config/Expeditions` is missing

Where: `UIController.luau:467`, `HubMap.luau:332-343`.

**Why it matters.**
- `hasExpeditions` is now `combatConfig ~= nil`, so the key shows.
- A tap warns once in Output and opens nothing.
- That degrades without an error, which is the rule, but a player sees a dead key.

**Fix (either):**
- fold `Catalog.GetExpeditionsConfig() ~= nil` into the key's visibility, re-read in `refreshCombatKeys` the way the
  Armory key's config is;
- or show a toast once.

## The accepted deviations, judged

| Owner | Deviation | Judgement |
|---|---|---|
| ui B | Clipped strip instead of a ScrollingFrame | **Correct.** See the notes below. |
| ui B | `Deps.modal` | **Correct.** See the notes below. |
| ui B | First clear's Valor as its own row | **Correct.** See the notes below. |
| ui A | Brutal's note in place of "T5" | **Correct, and it fits.** See the notes below. |
| ui A | Hub star from a first-clear line | **Not correct for Normal**: see m2. |
| ui A | Depart timeout in Theme | **Fine.** See the notes below. |

- **Clipped strip.**
  - The follow, the coin source points and the drag all stay in design px under the card's UIScale.
  - A tap and a drag are told apart with a 10 px slop.
  - The touch identity check works because Roblox reuses one InputObject per touch.
  - Only s1 is open, and a ScrollingFrame would have it too.
- **`Deps.modal`.**
  - The city's scrim is a TextButton. It takes taps and skips, so a stray tap cannot buy a building behind it.
  - The dungeon's scrim is a non-Active Frame, so the camera drag passes through.
- **The first clear's Valor row.**
  - `WaveService.EndRun` credits `given.valor` through `CreditSummary`. The totals include it, and the row shows the
    server's amount.
  - Note: Hard's row ("First Hard clear") carries no amount at all, because its reward is a family only. It is a label,
    plus the note.
- **"Castle gear" in place of "T5".**
  - Measured with Pillow at 11 px Montserrat Medium (the local face for GothamMedium): 62.7 px if TextSize is the em,
    about 51 px if it is the line height.
  - A button is (212 - 12)/3 = 66.7 design px wide.
  - The line truncates if a longer note ever comes.
- **The depart timeout in Theme.**
  - Theme is the sanctioned home for presentation timings.
  - One constant now serves both the map's Depart and Party & runs' Join.
  - Its comment says why it is longer than the dungeon's 6 s.

## Checked and clean

### The RunTally card

- **The tally.**
  - Rows count up in turn and share at most 2.8 s. Every duration goes through `Motion.Seconds`.
  - Coins and logs leave the rows in proportion to cash and Timber.
- **The wallet roll.**
  - It runs from `max(0, wallet - run)` to the wallet.
  - `SetWallet` retargets it on every combat Snapshot, and on every hub `refreshAll` while the card is visible.
  - It also retargets after the finish: `paintTotals(live.clock = done)` gives roll 1.
- **Skip and buttons.**
  - A tap on the card, or on the hub's scrim, calls `finish()`. So does a tap on the rows that is not a drag.
  - The buttons sit at z(3), under a fly layer that is not Active, so they answer at any moment.
- **Phones.**
  - The flying-icon count reads only `Theme.lowEndDevice`: 14 coins and 8 logs, or 5 and 4 on low end.
  - Under `reducedMotion` there is no grow, flash or pulse, but the flight still runs.
- **Leaks.**
  - The Heartbeat stepper stops at finish, hide and Destroy.
  - Sprites are cleared on every `plan`, `hide` and `Destroy`.
  - Buttons and their connections are rebuilt on every Show.
  - Both ScreenGuis are `ResetOnSpawn = false`.
  - A second Show stops the first stepper first.
- **Fit** (from the port: 12 rows, both hosts, the note at one and at two lines).

| Viewport | Layout | Design px | Viewport px | Notes |
|---|---|---|---|---|
| 640×360 | Two columns | 620 × 313.5 | 568 × 287 | 9.2 rows shown. Totals need 156-190 of a 221.5 column, and the buttons are pinned to its bottom. |
| 667×375 | Two columns | | | 9.9 rows shown. |
| 375×667 | One column | 553-572 tall | | The limit is 600 (664 available). Every row shows. |
| 1920×1080 | One column | | 570 × 872 | Scale 1.53. |
| 1280×720 | One column | | | |
| 568×320 | Two columns | | | The two-line note pushes the combat buttons 6-12 design px into the 14 px bottom padding, still inside the card. This is ui B's stated limit. |

- **Words.** Every measured string fits its box in Montserrat Bold or Medium:
  - kicker plus countdown: 288 of 344 px;
  - the subtitle: 286 of 344 px;
  - "Return to your city": wraps to two lines in a 114 × 48 button;
  - "next: Double Jump · 10 Valor": 173 of 196 px.
- **Rules.** There is no sound. Every presentation constant is in `LOOK`. The words are either server names or the card's
  own.

### The hub

- **The report.**
  - It still chains behind the welcome-back card. The event parks it in `pendingSummary`, and it is flushed at the end of
    every snapshot and when the welcome card hides.
  - The new `current ~= nil` guard only matches what `showExpeditionSummary` already required.
  - The view has the kicker, `summary.title`, one Dismiss, the wallet from the HUD model, the died note and
    `nextAbility`.
  - `readRunSummary` requires `title` and reads `lines` through `RunLines.Read`.
- **HubMap.**
  - Depart fires only `RequestExpedition(levelId, difficulty, deps.isPublic())`.
  - `SetBusy(false)` comes from `OnAnswer`, on the `expedition` ActionResult, or from an 8 s token timeout. A newer Depart
    voids an older timer.
  - `RequestMapState` fires on open, on each PartyState while open, and after a refusal while open. The MapState listener
    is connected before the first request.
  - The arrows, d-pad, Enter, KeypadEnter, A and B are bound through CAS at High+1, and only while the map is open.
  - Every MapScreen close path runs `setOpen`, then `onOpenChanged(false)`, which unbinds them. Keys already held when the
    map opens are passed through.
  - Escape and `MenuOpened` close the map.
  - One sheet at a time: the map, the Armory and the dock panels close each other. I traced the Studio strip's visibility
    in both orders, and it ends hidden while either sheet is open.
- **MapScreen.**
  - `canDepart` needs a leader id. For a solo player, HubMap sets it to the player before the first paint.
  - The hub never touches `Rest` or the held press.
  - The combat call to `MapScreen.new` is unchanged.
  - Combat's `seedMap` now uses `FirstPick`, which matches, line for line, the rule it replaced.
- **ExpeditionPanel.**
  - The tiles, Overdrive and `Refresh` are gone.
  - Run rows read "Level · Difficulty" and "host · in the lobby / in a level". That matches the `wave` that `publishNow`
    sends: 0 in the lobby, `joinUntilWave + 1` in a level.
  - The Join lock and its timeout still use their token.
- **TopBar.** The income and Legacy labels are built at the widths without the Power chip, so removing it leaves no gap.
- **ArmoryAbilityPage.**
  - Upcoming rows are never buyable: `buy`, `HasLiveBuy` and `FirstSelection` all skip them.
  - "With the Castle" is 94 px, inside a note width of 104 or 132.
  - `RunTally.WithText` gives "with the Castle", "with another Planet" and "with the Dream" for the shipped node names.
- **Theme.** A scan of all 1,012 keys finds none unread at 93eb8e9. A stricter scan, with comments stripped, of the 209
  keys that the deleted or changed files read finds none left without a code reader.

### The combat client

- **The depart line.**
  - It is read only in the `lobby` phase, and `CombatHud.paintDepart` hides it in any other phase.
  - A checkpoint notice cannot show in the lobby: `ShowNotice` returns outside the live phases.
  - The tick no longer hides a depart line.
  - The longest texts fit the 352-wide line at 15 px: "Forest Road · Normal starts in 5" is 245 px and "Another Planet ·
    Brutal starts in 5" is 261 px.
- **The map around the depart.**
  - The map does not open on entering the lobby while the depart is `waiting` or `counting`.
  - It closes when either state begins, which also covers R pressed with the map open.
  - `picked` selects the node and difficulty and opens the map once per `levelId:difficulty` per arrival.
  - `picked` also sets `mapSeeded`, so a later first MapState cannot move the pick, and it closes the Armory.
  - The summary-card branch runs after the picked branch and closes the map, so a leave card in the lobby wins.
- **The keys.**
  - R (`fakeDepart`, from `MapScreen.Selected()`, else the proving pair) and P (`cashEra` `"next"`) sit behind
    `if not studio ... return`.
  - No other `KeyCode.R` exists in the combat client or in the hub UI mapped into it.
  - The only `KeyCode.P` is `RangePanel`'s, which only `bootRange` mounts.
  - `DEBUG_HINT` gains " · R depart · P pay era".
- **TallyHost.**
  - The summary is checked field by field, totals included, and its lines go through `RunLines.Read`.
  - The card is shown again only when what it shows changes, and the countdown ticks locally between RunStates.
  - The leave card has no buttons and no countdown. A proving build has no Return.
  - Every Snapshot calls `SetWallet`.

### Tooling

- `combat.project.json` maps `RunTally` beside `MapScreen`. Both places build into scratch, and the combat sourcemap
  resolves `RunTally`, `TallyHost`, `DepartLine` and `ArmoryAbilityPage`.
- stylua and selene are clean on all 12 files in this slice.
- luau-lsp reports 0 diagnostics on `src/client` with the hub sourcemap and on `src/combat/client` with the combat
  sourcemap. Both sourcemaps were written to scratch.
- The harness passes 4,994 checks on the archive.
- `git grep` over `src` and `tools` finds no remaining reader of `SummaryCard`, `ExpeditionSummaryCard`, `SetPower`,
  `gearPower`, `RecommendedPower`, `MissionUnlocked` or `missionId`. The one hit is a `tests_l4w3_run` assertion that the
  old fields are nil.
