# L4 W3 fix round — ui-engineer B report (F13, F14, F15)

Rulings: `docs/prompts/l4-w3-fix-round.md` F13 (the pure `TallyRules` and its cases), F14, F15; findings
`docs/prompts/l4-w3-review/3-clients.md` m3, s1, s2, s4. Adopted `relay-a2.md` §1 (`RunLines.ReadSummary`) and §3
(`MapRules.FirstPick`). Relay for ui A updated at the top of `docs/prompts/l4-w3-reports/relay-uib.md`. Nothing
committed, nothing staged.

## Files

| File | What |
|---|---|
| `src/client/UI/TallyRules.luau` (new, pure) | `Rows`, `Totals`, `Owned`, `Wallet`, `WithText`, `NextAbility` (upcoming entries checked, s4), `Flights`, `IsRunResult` (F15), `ReadDepart`, `NodeOf`, `DepartText`, `Depart` (the per-RunState map decision). Requires only `Shared/Types`, `Format`, `Unlocks`; every config is handed in. |
| `combat.project.json` | One entry, `"TallyRules"` beside `RunTally` (made in the same step as the file). |
| `src/client/UI/RunTally.luau` | The rules removed; `Rows`, `Totals`, `Owned`, `NextAbility`, `WithText` keep their signatures as wrappers that hand `TallyRules` the Expeditions config; `RunTally.Wallet` added (additive); types `Row`, `Totals`, `Wallet` re-exported. Flight counts from `TallyRules.Flights(Theme.lowEndDevice, …)`. F14: the Valor badge is a "◆" `TextLabel`, never a turned Frame. |
| `src/combat/client/UI/TallyHost.luau` | Reads the summary with `RunLines.ReadSummary` (its own reader is gone: one reader in all three places); rows, totals, wallet and next line from `TallyRules`; the share line clamps a share above 1. |
| `src/combat/client/Controllers/CombatUIController.luau` | `TallyRules.Depart` decides the lobby's line and map each RunState (memory in `st.depart`); `TallyRules.IsRunResult` replaces the local `isRunResult` (F15); `seedMap` calls `MapRules.FirstPick`. Top-level locals unchanged at 103 (−`isRunResult`, `DepartLine` → `TallyRules`, +`MapRules`). |
| `src/combat/client/UI/DepartLine.luau` | **Deleted** (see deviation 1). |
| `tools/crowd_harness/tests_l4w3_tally.luau` (new) | 120 checks in 11 groups, behind `L4W3T.group`. |

## The rules and their cases

- **`Depart(raw, phase, last, expeditions, memory) -> DepartStep`** (`line`, `holding`, `open`, `close`, `select`,
  `memory`). Read in the lobby only; `holding` = waiting or counting; `open` = (entered the lobby and not holding) or a
  new pick; `close` = the hold began on this RunState; a `picked` selects its node and difficulty once per
  `"<levelId>:<difficulty>"` (a level no node names is no pick, and the last pick is kept); the memory handed in is
  never written. The host carries the answer out in that order: close, select (+ close the Armory), open.
- **`NextAbility(expeditions, owned)`**: first ability on sale not owned in the Armory's order (`order`, then id: the
  old code ignored the id tie-break the Armory's tab uses), else the first upcoming entry that is a table with string
  `id`, `name`, `text` and `with` and is not owned. The tab's "id on sale or repeated" rule is not repeated: by the
  time `upcoming` is read every ability on sale is owned, and a repeated id is owned or not with its first, so it
  could never change the answer (a mutant removing it would be equivalent; the comment says so).
- **`IsRunResult`**: adds `levelId` a string (F15) and makes the camps finite (the subtitle formats them; `Format.Cash`
  never returns on infinity).
- **`Owned` / `Wallet`**: NaN and infinity read as 0 (the same `Format.Cash` hang); `Wallet(cash, combat, material)`
  is what both hosts build.
- **`Flights(lowEnd, totals, counts)`**: low end 5 / 4, else 14 / 8; no cash no coins, no material no logs, never more
  logs than the pile's places. The host passes `Theme.lowEndDevice`; only a pin can hold that argument (p5).

Groups: rows (19), totals/owned/wallet (13), with (6), next (13), flights (6), result (14), read (11), text (8),
depart (21), arrival (3: a whole arrival RunState by RunState, `-c -- -- -- -- -- o-`), shipped (6: the shipped
Expeditions.json's next lines and every shipped level's node and count line). 120 in all.

## Gates (Bash in `tycoon-p5`, PATH with rokit; my files unless named)

- `stylua --check`, `selene` on the five Luau files: clean (0 errors, 0 warnings).
- `luau-lsp analyze`, sourcemaps written to scratch (the tracked ones untouched): hub (`src/client src/server
  src/shared`) **0 diagnostics**; combat (`src/combat src/shared`) **0 diagnostics** (whole trees, with every owner's
  edits at the time).
- `py tools/check_compile.py`: **PASS, 188 files** (+TallyRules, +ui A's TouchHold, −DepartLine).
- `rojo build combat.project.json`, `py tools/proving_project.py && rojo build .proving.project.json` (it maps
  `TallyRules`), `rojo build` (hub): all OK, built into the scratchpad (`build/*.rbxl` untouched).
- **Harness** (the worktree's own `run_harness.py`, which the designer had already wired with `TallyRules` and my file
  last): `HARNESS: FAIL (13 of 5,221 checks)`. All 13 are in `tests_l4w3_run` (luau B's F1/F3/F6 cases and the
  depart pins, mid-edit by B). **All 120 of mine pass.** Before the designer's wiring landed I ran the same cases
  through a scratch copy of `run_harness.py` (SOURCES + TESTS added, the other-checkout check off): same result.
- **`mutate.py` filtered** (`files:CombatUIController.luau,RunTally.luau,TallyHost.luau,TallyRules.luau`,
  `MUTATE_ROOT=mutant-uib`, `HARNESS_BUNDLE=bundle-uibmut.luau`): the stale check passed (no existing entry on my files
  is out of date); the baseline then stopped on luau B's in-progress pins (`FAIL (6 of 5,267)`), so nothing was
  mutated. No entry for `TALLY_RULES` exists yet (the designer's, from the list below). My mutant folder and bundles
  are removed.
- Line endings: LF in every file I wrote (0 CR bytes, counted in Python).

## Probes (each applied to a scratch copy of the tree, the harness run on it; new failures beyond the baseline's 13)

Script `…/scratchpad/l4-w3-fixUiB/probe.py` with `probes.json`, log `probe_run1.txt`. Baseline `FAIL (13 of 5,220)`
(luau B's in-progress cases).

### The review's six m3 probes, against the new code

| # | Review's mutation | Where it lives now | Result |
|---|---|---|---|
| p1 | `if pick ~= st.departPicked and node ~= nil` → `if node ~= nil` | `TallyRules.Depart`: `if pick ~= picked and node ~= nil then` → `if node ~= nil then` | **Caught** by my cases (1 new: "the same pick on every later RunState opens nothing"). Host half (`st.depart = departStep.memory` dropped, so every RunState is a first): **pin only**, `uiDepartKept` / `uiDepartWrites` below (probe ui1: not caught by cases, as expected). |
| p2 | `local holding = ...` → `false` | `TallyRules.Depart`: the same line → `local holding = false` | **Caught** (6 new: the hold's open, close and line cases). Host half (`if departStep.open then` → always): **pin only**, `uiDepartOpen` / `uiOneOpen`. |
| p3 | `FirstPick`'s `#node.stars == 0` → `> 0` | `MapRules.FirstPick` (luau A's, moved verbatim) | **Caught** by luau A's `tests_l4w3` cases (5 new). The combat host's call is pin `uiFirstPick` (mine); the city's is ui A's. |
| p4 | HubMap sends `true` for `public` | ui A's `HubMap.luau`, untouched by me | ui A's pin (Depart's `deps.isPublic()` argument). |
| p5 | `local low = Theme.lowEndDevice` → `Theme.reducedMotion` | `RunTally.plan`: `TallyRules.Flights(Theme.lowEndDevice, view.totals, LOOK.flights)` → `Theme.reducedMotion` | **Pin only** (Theme cannot load in the harness): `tallyFlights`, `tallyLowEnd`, `tallyNoReduced` (probe p5: not caught by cases, as expected). The rule inside `Flights` is caught (p5b, p5c below). |
| p6 | the hub wallet's `cash = current.state.cash` → `0` | ui A's `UIController.luau` | ui A's pin; `RunTally.Wallet` is offered so it becomes one call line. |

### Further mutants on the rules (all caught by `tests_l4w3_tally`)

| Probe | Mutation | New failures |
|---|---|---|
| p5b | `coins = if lowEnd then counts.coinsLowEnd else counts.coins` → `counts.coins` | 1 ("low end: fewer") |
| p5c | the logs' `math.min(…, counts.logs)` cap removed | 1 |
| c1 | `close = holding and not memory.holding` → `holding` | 2 |
| c2 | `open = (entered and not holding) or select ~= nil` → `entered or select ~= nil` | 3 |
| c3 | `memory.picked` never updated | 4 |
| c4 | the depart read in every phase, not only the lobby | 2 |
| F15 | `typeof(payload.levelId) == "string"` removed from `IsRunResult` | 2 |
| s4 | `upcomingEntry(def)` → `typeof(def) == "table"` | 1 (the group throws on the entry with no name, as the old code did) |
| n1 | the `order` tie-break by id removed | 1 |
| w1 | coins fly with no cash | 1 |

## Deviations

1. **`DepartLine.luau` is deleted, not kept as a caller of `TallyRules`.** All three of its functions (`Read`,
   `NodeOf`, `Text`) were pure and moved whole; nothing impure was left for it to do, and a module of one-line
   forwards would be dead weight. `CombatUIController` calls `TallyRules` directly. No pin or `mutate.py` entry read
   it.
2. **`TallyHost` uses `RunLines.ReadSummary`** (F7 names only the bridge and the city; slice 3 s3 asked for "both hosts
   and the bridge"). A summary it refuses (e.g. an empty title) shows the card with no rows and zero totals, as a
   malformed one did before; the run card's title is the level's name, so a real run always passes.
3. **`TallyRules.Wallet` / `RunTally.Wallet` are additions** beyond the ruling's list, so the two hosts build the wallet
   line one way and its NaN/infinity rule is tested.
4. **F14 also turns the totals' Valor badge into the glyph** (that one is not inside the clipped rows); one look for
   both badges.
5. `BossBar`'s guard pips (`src/combat/client/UI/BossBar.luau:289`, `Rotation = 45` inside a `ClipsDescendants` track)
   are the same pattern, but they never scroll and sit wholly inside the track, so an unclipped draw changes nothing.
   Left as they are.

## For the designer (pins and `mutate.py` entries)

All texts are code as it stands (comments blanked as `luau_code` does). Bodies: `ON_RUN_STATE_BODY` exists
(`^\tlocal function onRunState\(.*?^\tend$`); new ones suggested: `^\tlocal function seedMap\(.*?^\tend$` (CUI),
`^\tlocal function plan\(.*?^\tend$` (RunTally), `^local function newDiamond\(.*?^end$` (RunTally),
`^\tlocal function show\(.*?^\tend$` and `^\tlocal function wallet\(.*?^\tend$` (TallyHost).

### Pins (file, body, kind, text → count)

| Key (suggested) | File | Body | Kind | Text | Count |
|---|---|---|---|---|---|
| uiDepartStep | CUI | onRunState | lines | `\t\tlocal departStep = TallyRules.Depart(run.depart, phase, last, expeditions, st.depart)` | 1 |
| uiDepartKept (the `picked` once-per-arrival guard's memory) | CUI | onRunState | lines | `\t\tst.depart = departStep.memory` | 1 |
| uiDepartWrites | CUI | whole file | regex | `\bst\.depart\s*=(?!=)` | 1 |
| uiDepartCalls | CUI | whole file | text | `TallyRules.Depart(` | 1 |
| uiDepartLine | CUI | onRunState | lines | `\t\thud.SetDepart(departStep.line)` | 1 |
| uiDepartClose (the holding rule's close) | CUI | onRunState | lines | `\t\t\tif departStep.close and screen.IsOpen() then` | 1 |
| uiDepartPick | CUI | onRunState | lines | `\t\t\tlocal pick = departStep.select` | 1 |
| uiDepartSelect | CUI | onRunState | lines | `\t\t\t\tscreen.Select(pick.node, pick.difficulty)` | 1 |
| uiDepartOpen (the holding rule's open) | CUI | onRunState | text | `\t\t\tif departStep.open then\n\t\t\t\tscreen.Open()\n\t\t\tend\n` | 1 |
| uiOneOpen (no other open path in a RunState) | CUI | onRunState | text | `screen.Open()` | 1 |
| uiResult (F15) | CUI | onRunState | lines | `\t\t\tTallyRules.IsRunResult(result)` | 1 |
| uiNoLocalResult | CUI | whole file | regex | `\bisRunResult\b` | 0 |
| uiFirstPick (p3, combat half) | CUI | seedMap | lines | `\t\tlocal nodeId, difficulty = MapRules.FirstPick(expeditions.difficulties, state)` | 1 |
| uiWallet | CUI | whole file | lines | `\t\tsummaryCard.SetWallet(wallet.cash, st.combat)` | 1 |
| tallyFlights (p5: the flying-icon gate on `Theme.lowEndDevice`) | RunTally | plan | text | `TallyRules.Flights(Theme.lowEndDevice, view.totals, LOOK.flights)` | 1 |
| tallyLowEnd | RunTally | whole file | regex | `\blowEndDevice\b` | 1 |
| tallyNoReduced | RunTally | plan | regex | `\breducedMotion\b` | 0 |
| tallyCoins | RunTally | plan | lines | `\t\tlocal coinFirst, coinLast, coins = launch(true, coinCount, 0)` | 1 |
| tallyLogs | RunTally | plan | lines | `\t\tlocal logFirst, logLast, made = launch(false, logCount, seconds(LOOK.logDelaySeconds))` | 1 |
| tallyPile | RunTally | whole file | lines | `\tfor index = 1, LOOK.flights.logs do` | 1 |
| tallyGlyph (F14) | RunTally | newDiamond | text | `Create("TextLabel", {` | 1 |
| tallyNoTurn (F14) | RunTally | newDiamond | regex | `\bRotation\b` | 0 |
| tallyOneTurn (F14: only the flights turn) | RunTally | whole file | regex | `\bRotation\s*=` | 1 |
| hostSummary (one reader) | TallyHost | show | lines | `\t\tlocal summary = RunLines.ReadSummary(raw)` | 1 |
| hostNoReader | TallyHost | whole file | regex | `local function readSummary\b` | 0 |
| hostWallet | TallyHost | wallet | lines | `\t\treturn TallyRules.Wallet(state.cash, state.combat, state.material)` | 1 |

Order pins (onRunState): `local departStep = TallyRules.Depart(` before `st.depart = departStep.memory` before
`if departStep.close and screen.IsOpen() then` before `local pick = departStep.select` before `if departStep.open then`
before `TallyRules.IsRunResult(result)` (the summary branch runs after the map's and closes it, so a leave card in the
lobby wins).

### `mutate.py` entries (file, old → new; each fails the harness, see Probes for the ones run)

TALLY_RULES (caught by `tests_l4w3_tally`):
- p1 `"\t\tif pick ~= picked and node ~= nil then\n"` → `"\t\tif node ~= nil then\n"`
- p2 `"\tlocal holding = depart ~= nil and (depart.state == \"waiting\" or depart.state == \"counting\")\n"` → `"\tlocal holding = false\n"`
- `"\t\tclose = holding and not memory.holding,\n"` → `"\t\tclose = holding,\n"`
- `"\t\topen = (entered and not holding) or select ~= nil,\n"` → `"\t\topen = entered or select ~= nil,\n"`
- `"\t\tmemory = { holding = holding, picked = picked },\n"` → `"\t\tmemory = { holding = holding, picked = memory.picked },\n"`
- `"\tlocal depart = if phase == LOBBY then TallyRules.ReadDepart(raw) else nil\n"` → `"\tlocal depart = TallyRules.ReadDepart(raw)\n"`
- F15 `"\t\tand typeof(payload.levelId) == \"string\"\n"` → `""`
- s4 `"\t\tif upcomingEntry(def) and not Unlocks.Owns(owned, def.id) then\n"` → `"\t\tif typeof(def) == \"table\" and not Unlocks.Owns(owned, def.id) then\n"`
- `"\t\t\t\tor (def.order == best.order and def.id < best.id)\n"` → `""`
- p5 rule `"\t\tcoins = if lowEnd then counts.coinsLowEnd else counts.coins\n"` → `"\t\tcoins = counts.coins\n"`
- `"\t\tlogs = math.min(if lowEnd then counts.logsLowEnd else counts.logs, counts.logs)\n"` → `"\t\tlogs = if lowEnd then counts.logsLowEnd else counts.logs\n"`
- `"\tif totals.cash > 0 then\n"` → `"\tif true then\n"`

Pin-caught (need the pins above):
- RunTally p5 `"TallyRules.Flights(Theme.lowEndDevice, view.totals, LOOK.flights)"` → `"TallyRules.Flights(Theme.reducedMotion, view.totals, LOOK.flights)"`
- CUI p1 host half `"\t\tst.depart = departStep.memory\n"` → `""`
- CUI p2 host half `"\t\t\tif departStep.open then\n"` → `"\t\t\tif true then\n"`
- CUI F15 `"\t\t\tTallyRules.IsRunResult(result)\n"` → `"\t\t\ttrue\n"`
- CUI p3 `"MapRules.FirstPick(expeditions.difficulties, state)"` → `"MapScreen.FirstPick(expeditions.difficulties, state)"` (or any other call)
- TallyHost `"\t\tlocal summary = RunLines.ReadSummary(raw)\n"` → `"\t\tlocal summary = raw\n"`

### Lines that existing pins or entries read

None changed. The `l4b` floor pins and the `fix2 pins` prewarm lines in `CombatUIController` are untouched, and the
onRunState order pins (`if not isRunState(payload) then` → `applyFloors(run.floors, ` → `if run.levelId ~= st.levelId
then`) still hold. `run_harness.py` already lists `TallyRules` in SOURCES and `tests_l4w3_tally.luau` last in TESTS
(the file ends with the verdict line); `mutate.py` already copies `TALLY_RULES` into the mutant root.

## For the other owners

- **ui A:** nothing you call changed (relay-uib.md, top). Optional: `RunTally.Wallet(current.state.cash,
  current.state.combat, tallyMaterial)` would make the review's p6 one call line to pin. p4 (HubMap's
  `deps.isPublic()`) and p6 (the hub wallet's cash source) are in your files: pins only.
- **luau A:** nothing. `MapRules.FirstPick` and `RunLines.ReadSummary` adopted as written in relay-a2.md.
- **Lead:** `combat.project.json` has the one `TallyRules` entry (L4W3-15's pattern). No remote, no other project file.

## What to check in Studio (`build\proving.rbxl`), including the phone emulator

1. Play: the lobby shows "Forest Road · Normal starts in 5" with no map over it, and the level starts (`TallyRules.Depart`
   now decides this; the behaviour is meant to be unchanged).
2. Clear a run (N to the clearing): the card's Valor badges, in the rows and in the totals, are a gold "◆"; scroll a
   long card on a 640×360 emulator and check no "◆" draws above or below the rows window (F14).
3. Back to camp: the map opens and nothing starts. Open the map, press R: the map closes and the count shows.
4. A `picked` depart (bridge with a refused start): the map opens once on that level; close it, it stays closed.
5. Phone emulator 640×360 / 667×375 landscape, 375×667 portrait, and 1920×1080: the layout is untouched by this round
   (only the badge changed, in the same box), so the W3 fits stand.
