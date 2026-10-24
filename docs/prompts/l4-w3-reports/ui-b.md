# L4 W3 — ui-engineer B (combat client + the shared tally card) report

Contract: `docs/prompts/l4-w3-contract.md` §3 "Client", §4.2, §6 row 8, §9 (R, P, `DEBUG_HINT`, the range-boot check),
L4W3-13, L4W3-15. Relays adopted: `relay-a.md` (Types `RunLine` / `RunDepart` / `abilities.upcoming`, `RunLines.Read`);
ui A's `MapScreen.Selected` and `MapScreen.FirstPick`; B's lever names (`fakeDepart`, `cashEra` "next", read in
`DebugService.luau`). My API relay for ui A: `relay-uib.md`. Nothing committed, nothing staged.

## Files

| File | What |
|---|---|
| `src/client/UI/RunTally.luau` (new) | The shared card: API, the words helpers, the show, the layout. |
| `src/combat/client/UI/TallyHost.luau` (new) | The combat host. It builds the View from the summary RunState, ticks "Back to camp in 8s", and turns buttons into Back / Return. |
| `src/combat/client/UI/DepartLine.luau` (new) | `RunState.depart` off the wire (`Read`), the notice words (`Text`), the node of a level (`NodeOf`). |
| `src/combat/client/UI/CombatHud.luau` | `SetDepart(text?)`: the notice line in the lobby, sized to the header's width, medium text, held. |
| `src/combat/client/Controllers/CombatUIController.luau` | The wiring below. It is at 103 top-level locals, two more than before: `TallyHost` and `DepartLine` replace `SummaryCard`, and `DEPART_KEY` was added. |
| `src/combat/client/UI/SummaryCard.luau` | Deleted (§6 row 8). |
| `combat.project.json` | One line: `"RunTally": { "$path": "src/client/UI/RunTally.luau" }` beside `MapScreen` (L4W3-15). |

## What I built

### The card (`RunTally`)

- **Rhythm** (base seconds, each through `Motion.Seconds`):
  1. The card opens: it grows from 0.94 over 0.22 s.
  2. Rows slide in from 14 px and count up from +0 over 0.42 s. One starts every 0.3 s, and all the rows share at most
     2.8 s, so a long run does not drag. Each row lands with a short background flash.
  3. The rows' gains appear at the totals.
  4. 14 coins fly from the rows' cash cells on a bowed path that speeds up into the wallet coin. The coin pulses at
     each landing. The wallet line rolls from `max(0, wallet − run)` to `wallet` between the first and the last landing.
  5. 8 Timber logs fly from the rows' Timber cells. Each lands on its own place in a two-column pile, and the material
     count rolls over the same window.
  6. Valor rolls with its badge swelling.
- **Length:** an 11-row Forest Road card is done in about 4.7 s, and in about 2.3 s on any touch device.
- **Coin sources:** coins leave rows in proportion to each row's cash. The k-th of n leaves the row where the running
  total passes (k − 0.5)/n.
- **Skip and buttons:** a tap on the card outside a button jumps to the end state. That includes a tap (not a drag) on
  the rows. Buttons answer at any moment.
- **Phones:** under `Theme.reducedMotion` (every touch device) every duration is halved and the easing is linear. There
  is no grow, no flash, no pulse and no coin swell, but the flight still runs. The flying-icon count follows
  `Theme.lowEndDevice` only: 5 coins and 4 logs on a low-end device, 14 and 8 otherwise.
- **Fit:**
  - A parent under 440 design px tall that is at least 560 wide gets **two columns**: rows left, totals and buttons
    right.
  - Otherwise it gets **one column**.
  - The rows show what fits and follow the counting row. They scroll by drag or wheel, with a thin thumb. The totals
    never scroll.
- **Words:** rows read "Raiders ×112", "Pickets bonus", "The Camp Chief", "The Lookout", "Castle Key found" (gold, a key
  drawn from Frames, no amounts), "First Hard clear", and "Mentor bonus". An empty list shows one dim row, "Nothing
  earned this time".
- **Next ability:** `RunTally.NextAbility` reads "next: Double Jump · 10 Valor" (the first `Unlocks.Sellable` entry not
  owned). Failing that it reads "next: Glide · with the Castle" (from `abilities.upcoming`). `RunTally.WithText(nodeId)`
  gives the "with the Castle" words.
- **No sound.** Every presentation constant and every word the card owns is in one `LOOK` table.

### The combat host and the depart flow

- **Card content** (`TallyHost`):
  - Kicker "RUN REPORT" (the trip home: "EXPEDITION REPORT").
  - Title "Forest Road · Normal".
  - Subtitle "Cleared · Camps 3 / 3 · 9m 41s", plus "Your share 42%" in a party. The old card's share line moved into
    the header, as the study's preview has it.
  - Star, and a note naming the first clear's family ("Warhammer is yours: equip it in the Armory (K)").
  - Buttons Back to camp (accent) and Return to your city. There are no buttons on the `leave` card, and no Return in a
    proving build.
  - Countdown "Back to camp in 8s · Enter to go now". The key hint shows only for whoever may end the wait, on a
    keyboard.
- **Data handling:**
  - The summary is checked field by field, and its lines go through `RunLines.Read`.
  - RunState comes four times a second, so the card is shown again only when what it shows changes.
  - Every Snapshot calls `SetWallet` (cash plus `combat`).
- **Depart line:**
  - `waiting` shows "Waiting for your party · 25".
  - `counting` shows "Forest Road · Normal starts in 5" (the node's name and `difficultyNames`).
  - The map does not auto-open on lobby entry while the depart is waiting or counting. A map already open closes when
    the wait or the count begins, which also covers R pressed with the map open (§9 A). The leader may open it again
    with M.
  - `picked` selects that level's node and difficulty and opens the map, once per arrival (keyed `levelId:difficulty`).
- **Seeding:** the first MapState now seeds through `MapScreen.FirstPick`, ui A's copy of the same rule, so both hosts
  agree.

### Studio keys (§9, L4W3-13)

- **R** sends lever `fakeDepart` with `"<levelId>:<difficulty>"`, taken from `mapScreen.Selected()`. It falls back to
  `debug.provingLevel` / `provingDifficulty` when nothing (or a node without a level) is selected.
- **P** sends `cashEra` "next". Its toast is B's server notice ("Pay as Boomtown (×670)"), which reaches the existing
  CombatFx toast handler.
- `DEBUG_HINT` gains " · R depart · P pay era".
- **R and P are free in a mission boot.** I grepped every key binding the combat client mounts:
  - `InputController`: One, Two, Q, E, R2, L2, Y, L1, R1.
  - `MovementController`: LeftShift, C, B, X.
  - `CameraController`: Alt, right stick.
  - `LevelScenery`: Y, O.
  - `ArmoryScreen`: K, L1, R1, B, A, Y, Escape.
  - `CombatUIController`: `DEBUG_KEYS` N B G H V T U L Z, plus J F I X M Backspace, the arrows, Enter and the d-pad.

  No `Enum.KeyCode.R` exists anywhere in `src/combat/client` or `src/client/UI`, and the only `KeyCode.P` is
  `RangePanel`'s toggle. `RangePanel` is mounted only by `bootRange`, and `CombatUIController.Start` runs exactly one
  boot, so the mission's `DEBUG_KEYS` / `onKey` are never connected in a range boot, and the range's P is never bound in
  a mission. No fallback letter was needed.

## Layouts checked by arithmetic

All figures are in design px; the scale is the HUD's `hudScale`.

- **640×360 under a 58 px top bar.** Scale 0.917 (MIN), 329 tall, so this is the two-column card, 620 wide and at most
  313 tall.
  - Header 78.
  - Rows column 334 wide × 221 tall: 9.2 rows show, and an 11- or 12-row run scrolls.
  - Totals column 236 wide: wallet 30 + Timber 24 + Valor 22 + next 16 + a two-line note about 34 + buttons 48, with
    gaps, about 190 ≤ 221.
  - Two buttons of 114 each. "Return to your city" wraps to two lines inside the 48 px button. Tap targets are 48 design
    px = 44 physical.
- **375×667 portrait.** Scale 0.917, about 409 × 609 design, so one column, 372 wide.
  - Header 78, 11 rows 264, divider and totals about 176 with the note.
  - The card is about 548 tall of 600 allowed.
- **1920×1080.** Scale about 1.57, about 1223 × 667 design, so one column. The same 548-tall card (about 860 physical
  px), centred.
- **Depart line.** At 640×360 and on monitors: 352 design wide (the header's width), under the wallet, inside the header
  column the banner keeps clear of (`placeBanner` reads only its bottom). The countdown text is about 270 px at 15 px
  bold.
- **Limit.** A 568×320 phone (about 286 tall) overflows the totals by about 12 px with a two-line note. That is below
  the 640×360 target; if Ben plays on one, the fix is dropping the subtitle on short screens.

## Gates (my files; Bash in `tycoon-p5`, PATH with rokit)

- `stylua --check` and `selene` on my five Luau files: clean (0 errors, 0 warnings, 0 parse errors).
- `luau-lsp analyze`:
  - Hub sourcemap (`src/client src/server src/shared`): **0 errors**.
  - Combat sourcemap (`src/combat src/shared`): **0 errors** (whole tree, at the time of the run).
- `py tools/check_compile.py`: **PASS, 187 files.** `CombatUIController` is at 103 top-level locals, and none of my
  files is in the top ten.
- `rojo build combat.project.json -o build/combat.rbxl`: OK. `py tools/proving_project.py && rojo build
  .proving.project.json -o build/proving.rbxl`: OK, and `.proving.project.json` maps `RunTally`. `rojo build -o
  build/test.rbxl`: OK.
- **Harness:** `HARNESS: FAIL (15 of 4,696 checks)`. None of the 15 is mine; they belong to other owners' edits in
  progress:
  - The hub / dungeon Gear Power pins: `hubPower`, `hubArmory`, `hubPowerExits`, `hubPowerSent`, `hubProving`,
    `hubStarters`, `hubWeapons`, `mainArmory`, `mainPower`, `mainProving`, `mainStarters`, `mainWeapons`. That is row 6
    (A, B); the designer re-points them.
  - The U-lever pins `leverAward` and `leverLevel` (B's `MapRules` re-point).

  The client pins that read `CombatUIController` all pass (`uiMerge`, `uiMergeCalls`, `uiMergeThenSeq`,
  `uiMergeThenSame`).
- **`mutate.py` filtered** (`files:CombatUIController.luau,CombatHud.luau`, `MUTATE_ROOT=mutant-uib`,
  `HARNESS_BUNDLE=bundle-uib.luau`):
  - The stale check passed: no entry is out of date.
  - The baseline then failed on the same other-owner checks (21 of 4,878 by then), so nothing was mutated.
  - My scratch bundle is removed.
- §12 `git grep -nE 'missionId|…|SetPower'` on my files (and a plain grep of the three untracked ones): **empty**.
- **Line endings:** LF everywhere (0 CR bytes in all seven files).
- **Side effect:** running the gates regenerated the tracked `sourcemap.json`, `sourcemap.combat.json` and
  `build/{combat,proving,test}.rbxl`. The lead regenerates these at the merge.

## Deviations, and why

1. **The rows scroll on a clipped strip, not a `ScrollingFrame`.**
   - The follow-the-counting-row scroll and the coins' start points are computed in design px.
   - How `CanvasPosition` reads under a `UIScale` could not be checked outside Studio; a strip moved by `Position`
     inside the card's `UIScale` cannot be wrong that way.
   - Drag, wheel, a scroll thumb and tap-versus-drag (for the skip) are about 60 lines.
2. **The combat host is its own module (`TallyHost`), and the depart words are `DepartLine`.** This follows the size
   gate's advice (new behaviour in new modules); `CombatUIController` only wires them.
3. **API additions beyond the contract's list.** All are additive and in the relay:
   - `Deps.modal` (the city's dim must take taps, the dungeon's must not).
   - `RunTally.Rows`, `Totals`, `Owned`, `NextAbility` and `WithText` as the "helper that builds the lines' words".
   - `Row.glyph` from my first relay was dropped: a key row's icon follows its `kind`.
4. **`NextAbility` names a sellable ability first** ("next: Double Jump · 10 Valor"), then the coming one ("next: Glide ·
   with the Castle"). Contract §7 says "the first one not owned". Reading only `upcoming` would advertise Glide to a
   player who has not bought Double Jump yet; that player's Valor has a nearer purpose.
5. **The first clear's Valor is now its own row** ("First Brutal clear +25"), so the note carries only the weapon family.
   The mentor's Valor is a row too ("Mentor bonus").
6. **The card's buttons make no click.** The old card played `uiClick`; Ben's combat rule is no sound, and the Armory
   screen's buttons are silent too.
7. **Number wording:** the summary countdown keeps the old `Format.Duration` ("Back to camp in 8s"). The depart counts
   are plain whole numbers through `Format.Cash` ("starts in 5", "· 25"), as the contract's examples read.
8. **The depart line uses Theme keys that already exist** (`TOP_BAR_WIDTH`, `TEXT_MEDIUM`, `COLOR_ACCENT_ALT`), so ui A
   needs no Theme change for it.

## What Ben must judge (key-only in `build\proving.rbxl`)

- **The card's motion:** the count-up pace (a row every 0.3 s, 0.42 s each), the coins (14) and the log pile (8), and
  whether about 4.7 s (about 2.3 s on a phone) feels rewarding or long. A tap skips; is that discoverable?
- **The depart line:** where it sits (under the wallet) and whether it reads well enough for a 5 s countdown.
- **Words:** "Pickets bonus" for camp rows, chest rows by the chest's name alone, and "next: Double Jump · 10 Valor" before
  "Glide · with the Castle".
- **The two-column card on a landscape phone:** does scrolling rows read better than grouping them? The contract's
  fallback is one "Camp bonuses" row.

## For the other owners

- **ui A (`UIController`, your hub host):**
  - Pass `modal = true` to `RunTally.new`. The old hub card's scrim was a button "so a stray tap behind the card must not
    buy a building"; without it the hub's scrim takes no input.
  - Optional: `RunTally.WithText(nodeId)` gives the "with the Castle" words if you want `ArmoryAbilityPage` to share
    them. Yours already agree for "Castle".
  - No Theme change is needed from me. You already removed `COMBAT_SUMMARY_WIDTH` / `COMBAT_SUMMARY_LINE_GAP`, whose
    last combat reader was the deleted card.
- **economy-designer:**
  - No harness pin or `mutate.py` entry reads a line I changed: the filtered stale check passed for
    `CombatUIController.luau` and `CombatHud.luau`, and no pin reads `SummaryCard.luau`, `RunTally.luau`,
    `TallyHost.luau` or `DepartLine.luau`. So I have no old/new text pairs for you, and no new `SOURCES` (the new
    modules need `game`, so they are not harness material).
  - **`Combat.json debug.provingAutoStart` is `false`.** L4W3-12 says Play alone in `proving.rbxl` must reach the
    countdown, and WaveService gates that boot path on this flag. Unless the lead decides otherwise, it should be `true`.
- **luau-engineer B:**
  - The client reads `RunState.depart` only in the `lobby` phase.
  - It treats `picked` once per arrival, per `levelId:difficulty`.
  - R sends `fakeDepart` with `"<levelId>:<difficulty>"`, never an empty level id when the config has its proving pair.
    P sends `("cashEra", "next")`.
  - The toasts are your `RunFx` notices; the client adds none.
- **Lead:** `combat.project.json` has the one `RunTally` entry (L4W3-15). No remote or other project change.

## What to check in Studio, including the phone emulator

1. **Play `build\proving.rbxl`** (once `provingAutoStart` is true). The lobby shows "Forest Road · Normal starts in 5"
   under the wallet, with no map over it, and the level starts.
2. **Clear the level** (N to the clearing, never B). The card's rows slide in and count, coins fly into the wallet line,
   logs stack beside the Timber count, and Valor rolls with "next: …" under it. If the run was a first Hard clear,
   check the star and the Warhammer note.
3. **Tap mid-count.** It jumps to the end. Drag the rows on a long run: they scroll and do not skip. Back to camp:
   nothing starts by itself, and the map opens.
4. **Press P twice.** The toast reads "Pay as Metropolis (×34K)". Open the map (M), press Up to select Hard, then R: the
   map closes and "Forest Road · Hard starts in 5" shows. A run then shows bigger cash rows.
5. **Phone emulator at 640×360 and 667×375 (landscape).** The card is two columns, the totals and both buttons are fully
   on screen, the rows scroll, and the motion runs shortened with no grow, flash or pulse.
6. **Phone emulator at 375×667 (portrait).** One column, the whole card visible.
7. **1920×1080.** One centred column.
8. **Trip home** (Return to your city, in `combat.rbxl` via the bridge). The "EXPEDITION REPORT" card has no buttons and
   no countdown.
