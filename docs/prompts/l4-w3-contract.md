# L4 W3 contract — the city map, the end screen, run cash by era

Brief: `docs/prompts/l4-w3-brief.md` (Part A). Drafted 2026-10-23 on `l4-w3` (cut from `main` at `dce50da`). Rulings are
**L4W3-n**. Every file:line is as read at that commit; owners re-find by text. Sources: MISSIONS_DESIGN §26 items 5-8
and the lead's rulings, §28, §29; `l4-study-report-publish.md` §1, §2, §3, §6 (D1 A, D3 A); PLAN "L4" → "W3 and W4"
and "Carried"; `l4-w1b-contract.md` L4B-1, L4B-2, L4B-5, L4B-9, row 20. Era cash: `docs/prompts/l4-w3-cash-study.md`
§2, §5.4, §6; **Ben picked option (c) at M = 3** (Village 1, Boomtown 670, Metropolis 34,000, Orbital Colony 1,400,000).

## 1. Rulings

- **L4W3-1.** One pure shared module for the node rules, `src/shared/MapRules.luau`: the hub's Depart and the dungeon's
  RequestStartLevel ask the same `MapRules.Startable` (§2.1). **L4W3-2.** The hub pulls its map state
  (`RequestMapState` → `MapState`), so `PartyService` (an M11 file) is untouched (§2.2).
- **L4W3-3.** Ticket, teleport data, Studio record, registry entry and run list carry `levelId` + `difficulty`;
  `missionId`, `overdrive` and the registry's `era` go; an old-shape ticket reads as none (`RunRegistry.luau:182-213`).
- **L4W3-4.** Departing auto-starts once per session, never after a run; a refusal falls back to the lobby with the level
  picked (§3). **L4W3-5.** `RunSummary.lines` is display, merged by source; the totals stay the truth (§4.1).
  **L4W3-6.** One card in both places, `src/client/UI/RunTally.luau`, no sound (§4.2).
- **L4W3-7.** Run cash × the member's own city era, frozen for the visit, at the one cash choke point: ×1 / ×670 /
  ×34,000 / ×1,400,000 (Ben's pick); cash only (§5). **L4W3-8.** No profile change; a bump, if ever needed, is **v10**
  (M11 takes v9).
- **L4W3-9.** L4B-5 (last reader) and L4B-6 (a test goes only with its rule) apply; §6 is the drafter's list, each owner
  proves its rows by grep. **L4W3-10.** Valor's purpose and Brutal's "Castle gear" (§7) exist nowhere yet (`git grep
  -niE 'glide|with the castle|castle gear' -- src` is empty). **L4W3-11.** The better simulated human waits (§8).

## 2. The map in the city

### 2.1 `src/shared/MapRules.luau` (new, pure, requires Types only; luau-engineer A)

Moved verbatim (behaviour unchanged, names kept): from `StageFlow.luau:2860-2982` the map section (`nodeOf`, `hasStar`,
`starCount`, `NodeState`, `MapState`, `Award`) and `export type Stars` (`:217`); from `SecretFlow.luau:16-36, 60-145,
345-360` the chest list (`Reward`, `Site`, `finite`, `whole`, `rewardOf`, `Sites`, `MapRow` renamed `SecretRow`). New:
- `MapRules.Built(levelIds: { string }): { [string]: boolean }` — WaveService's `builtLevels` rule (a node is built when a
  level file names it, ruling 28).
- `MapRules.Startable(map, built, leaderStars, levelId, difficulty, levelDifficulties: { [string]: any }?):
  "ok" | "locked" | "unavailable"` — `locked` when no node names `levelId` or its `NodeState` is not open for the leader;
  `unavailable` when `difficulty` is not in `map.difficulties` or not a key of the level file's `difficulties`.
- `MapRules.MAX_LEVEL_ID_LENGTH = 32`, `MAX_DIFFICULTY_LENGTH = 12` (moved from `CombatRemotes.luau:34-37`): one home
  for both places' validators.

StageFlow keeps `FirstClear` and `EarnsStar` (run rules) and requires nothing new, so `check_stage_mirror.py`'s `MODULES`
(`:184-185`) is unchanged and it must pass unchanged. SecretFlow keeps `Triggered`, `Decide`, `Open`, the shortcuts, and
re-exports `export type Site = MapRules.Site` (`UnlockService.luau:313` unchanged). B re-points `WaveService` (`starsOf
:481`, `builtLevels`, `sitesOf`, `secretRows`, `sendMapState :555-592`, `startLevel`'s node loop `:1899-1911` →
`Startable`, `endRun`'s `Award :1323`, `grantStars`); `startLevel` still runs `resolveLevel` after it. The designer
re-points every harness call and pin (`tests_l1`, `tests_l2`, `tests_l3_run`, `tests_l4w2`; `run_harness.py:582, 589`;
`mutate.py:4437-4440, 6618, 6746-6752`) and adds `MapRules` and `RunLines` (§4.1) to `run_harness.py` `SOURCES` (`:101-`).

### 2.2 Hub server (luau-engineer A)

- `HubRemotes.luau:172-182`: `RequestExpedition(levelId, difficulty, public)`: `args.n == 3`, `isShortName(levelId,
  MapRules.MAX_LEVEL_ID_LENGTH)`, `isShortName(difficulty, MapRules.MAX_DIFFICULTY_LENGTH)`, `typeof(public) ==
  "boolean"`; bucket `prompt` as today. New `RequestMapState`: `args.n == 0`, bucket `calls`. New event `MapState`
  in `events` (`:234-243`). Hub `Main.server.luau:243-257` passes the new arguments; one new handler line spawns
  `ExpeditionService.SendMap`.
- `ExpeditionService.Depart` (`:643-750`): the mission check (`:673-677`) becomes `MapRules.Startable(map,
  MapRules.Built(Catalog.GetLevelIds()), Unlocks.StarsOf(state.combat), levelId, difficulty, file.difficulties)` on the
  leader's own profile (host-gated, C2 ruling 4); `locked` / `unavailable` answers on action `expedition` with `slotId =
  levelId`. Ticket (`:722-729`): `{ accessCode, privateServerId, levelId, difficulty, public, expected }`. Teleport data
  (`:550-556`): `{ levelId, difficulty, hostUserId }`. `Handoff` (`:84-91`) and the bridge hint (`:481-486`) likewise.
- `ExpeditionService.SendMap(player)` (new): leader = `PartyService.Get(player)`'s `leaderUserId`, else the player; the
  leader's stars from their profile (a Studio fake leader or a leader without a profile: `{}`); own stars and own secret
  rows (`MapRules.Sites` of each built level, cached per level for the server's life, then `SecretRow` with
  `combat.secrets[levelId]`); answers `MapState` to that player only. Never yields.
- `Join` (`:752-816`) carries the entry's `levelId` / `difficulty`; `asActiveRun` (`:210-250`) checks them in place of
  `missionId` / `era` / `overdrive`; `SendRunList` (`:860-870`) sends them. The fakeRuns lever (`:893-924`) uses
  `debug.provingLevel` / `provingDifficulty`; `FAKE_MISSION_ID` (`:56`) goes.
- `StudioBridge.luau`: `TeleportHint` (`:35-40`) = `{ levelId, difficulty, hostUserId, accessCode? }`; `WriteDeparture`
  (`:308-321`) writes them; `ReadArrival` (`:333-360`) requires `levelId` a non-empty string within the cap and
  `difficulty` a string within the cap; `readSummary` (`:184-225`) per §4.1.

### 2.3 Combat place (luau-engineer B)

- `Main.server.luau:132-179`: `readHint` answers `(levelId, difficulty, hostUserId)`; `NO_MISSION` (`:68-70`) becomes
  `NO_LEVEL = ""`; `:206-214` hands them to `OpenSession`. The hint still chooses nothing by itself (ruling 4): only a
  verified ticket arms the auto-start (§3).
- `ArenaService`: `session.levelId` / `difficulty` replace `missionId` / `overdrive` (`:85-107`, `:933-960`);
  `OpenSession(levelId, difficulty, hostUserId, name)` (`:1074-1112`) → `RunRegistry.ResolveTicket(hostUserId, levelId,
  difficulty)`; `publishNow` (`:842-882`) publishes `levelId` / `difficulty` and reads no Catalog. New
  `ArenaService.Pick(): (string, string, boolean)` = the hint's level and difficulty and whether a ticket verified them;
  `ArenaService.ExpectedIn(): boolean` = every `ticket.expected` id admitted at least once (`PartyIn`'s loop without
  the cap, `:1213-1228`).
- `RunRegistry`: `readTicket` (`:182-213`), `ResolveTicket` (`:235-286`, the mock ticket carries the hint's pair) and
  `Publish` (`:291-317`) on the new fields.
- `CombatRemotes.luau:34-37, 95-102` take the caps from `MapRules`.

### 2.4 Hub client (ui-engineer A)

- New `src/client/UI/HubMap.luau`, the host: mounts the shared `MapScreen` in the hub's ScreenGui, feeds it `MapState`
  (fires `RequestMapState` on open and on each PartyState while open, and after an `expedition` refusal), converts the
  `HubParty` to `MapScreen.SetParty`'s list, binds the arrows and Enter while open (Escape closes), and turns Depart into
  `RequestExpedition(levelId, difficulty, isPublic())`. `SetBusy` clears on the `expedition` ActionResult or after the
  panel's `DEPART_TIMEOUT_SECONDS` (`ExpeditionPanel.luau:105`).
- `MapScreen.luau` gains `deps.returnText: string?` (nil = today's "Return to your city", `:78, :890-895`); the hub passes
  "Party & runs" with `onReturn` opening `ExpeditionPanel`. The combat call site (`CombatUIController.luau:1350`) is
  unchanged.
- `ExpeditionPanel.luau` keeps the party strip, "Open to public" and the run list; its tiles (`:587-699, 802-861`) and the
  Overdrive toggle (`:123, 575-583, 866-873, 1038-1039`) go; it gains `IsPublic()`; run rows (`:900-950`) name the level
  from `Expeditions.json` nodes and the difficulty from `difficultyNames`.
- `UIController.luau`: the mission list (`:405-416`) and the tiles' wiring (`:793-806`) go; the Expeditions key opens
  `HubMap`; `readRunSummary` (`:142-170`) validates through `RunLines.Read` (§4.1). Keep the diff to mounting and
  wiring (M11, §10).

## 3. The auto-start (luau-engineer B; client ui-engineer B)

- **Config (designer):** `Combat.json levels.departCountdownSeconds` (5 proposed; Ben judges). The wait cap is the existing
  `coop.lobbyWaitSeconds` (30, `Combat.json:39`, `Types.luau:1135`).
- **State** in WaveService's `boot`: `depart = { levelId, difficulty, state: "waiting" | "counting" | "picked" | "done",
  startsAt }`, set at the session's first `OnAdmitted` (`:2301`) from `ArenaService.Pick()`: verified → `waiting`; hint
  only (no ticket, a mismatch, an old shape) → `picked`; no hint → none. A proving boot with `debug.provingAutoStart`
  stands in `waiting` on `provingLevel` / `provingDifficulty` (`Combat.json:86`). Cleared only with the session
  (`WaveService.Reset :2472`, the reset hook). The rule is a pure function B writes (e.g. `StageFlow.DepartStep`) so the
  harness drives it; WaveService only executes.
- **The tick** replaces `tickAutoStart` (`:2052-2079`), from the lobby branch (`:2221-2226`):
  - `waiting` → `counting` (`startsAt = now + departCountdownSeconds`) once `ExpectedIn()`, the leader is present and
    `VitalsService.AllHaveBodies(members)`; → `picked` once `now − firstArrivalAt ≥ lobbyWaitSeconds` without that (a
    member missing at the cap).
  - `counting` → `done` at `startsAt`, then `startLevel(leader, levelId, difficulty)` once; a refusal → `picked`, the
    leader gets today's `refuseStart` toast (`:1627`) and Output a warn. No retry.
  - Any start the leader asks (`RequestStartLevel`, any level, during `waiting` or `counting`) → `done`.
  - `backToLobby` (`:1357-1388`) never touches `depart`: **nothing auto-starts after a run** (the L1 rule); with
    `provingAutoStart` this withdraws ruling 32's "again after every return". `debug.provingStartDelay` (`:87`) goes.
- **Who:** solo counts down once its body stands. A member arriving after `done` waits in the lobby camp and enters at
  the next boundary (today's `ArenaService.Admit` rule). Leaving during `counting` stops nothing; a new leader's stars
  decide at zero (`locked` → `picked`). A non-expected arrival (the run list) never holds the countdown.
- **Wire:** `RunState.depart: RunDepart?` (Types, A) = `{ levelId, difficulty, state: "waiting" | "counting" |
  "picked", startsIn: number?, waitIn: number? }`, built by `BuildRunState` (`:569-`) from `SetRunFields`, nil once
  `done` and outside the lobby; broadcast on every state change and at each whole second of `startsIn` / `waitIn`.
- **Client (ui B, `CombatUIController`):** `waiting` → the notice line "Waiting for your party · 25"; `counting` →
  "Forest Road · Normal starts in 5" (names from the map config); `picked` → `mapScreen.Select(<node of levelId>,
  difficulty)` and `Open()`, once per arrival. The leader may still open the map and depart something else.

## 4. The end screen

### 4.1 `RunSummary.lines` (Types and `src/shared/RunLines.luau`: A; credit sites: B)

- Types: `RunLineKind = "raiders" | "camp" | "boss" | "chest" | "key" | "firstClear" | "mentor"`; `RunLineKey = { kind,
  id: string, name: string }`; `RunLine = RunLineKey & { count, cash, material: string, materials, valor: number }`.
  `RunSummary` (`:1355-1368`): `title: string` replaces `missionId` (the level's name for a run, the map's for a
  session), `overdrive` goes, `lines: { RunLine }` added.
- New pure `RunLines.luau`: `Add(lines, key, count, cash, material, materials, valor)` merges into the line of the same
  `kind` + `id` (first-credit order), appending only below `RunLines.MAX = 16` (a wire cap; past it the totals still
  count); `Read(value): { RunLine }` validates a line list off the wire (at most `MAX`; `kind` in the set; `id`, `name`,
  `material` strings ≤ 48; numbers finite and ≥ 0; a bad line is dropped, a missing list is `{}`). Used by
  `ArenaService` (Add), `StudioBridge.readSummary` (Read; `title` required in place of `missionId`) and
  `UIController.readRunSummary` (Read).
- `ArenaService.CreditSummary(userId, key, cash, material, materials, valor, kills)` (`:1288-1305`) adds to both
  summaries' totals as today and `RunLines.Add`s the line; `CreditMentor` (`:1307-1312`) adds `{ "mentor", "mentor", "" }`;
  `emptySummary` (`:468-490`) and ReturnService's zero card (`:66-90`) build `title` and `lines = {}`.
- Credit sites (WaveService): `credit` (`:805-866`) takes the key and passes it to every share;
  `onCrowdKilled` (`:956-981`) → boss: `{ "boss", info.kind, run.bossName or info.kind }`, else `{ "raiders",
  "raiders", "" }`; `campCleared` (`:888-905`) → `{ "camp", zone.id, zone.name }`; the first clear (`:1328-1330`) →
  `{ "firstClear", levelId .. ":" .. difficulty, "" }`; a chest (`:2115`) → `{ "chest", site.id, site.name }` and, when
  `opening.key`, a zero line `{ "key", key, Expeditions keys[key].name or key }`. Names come from config; the client
  owns the words for the empty ones ("Raiders ×112", "First Hard clear", "Mentor").
- The run's last wallet Snapshot goes after every credit of its end (the first clear's Valor included) and before
  `BroadcastSummary` (today `sendWallets(…, true)` at `:1309` runs before the grants at `:1323-1331`).
- Home: unchanged route (`ReturnService` → `ReturnData.summaries`, hub `Main.server.luau:67-96` →
  `ExpeditionSummary`). A full party's four summaries of 16 lines stay a few KB of teleport data.

### 4.2 `src/client/UI/RunTally.luau` (new, shared; ui-engineer B; mapped into combat by the lead)

- `RunTally.new(parent, deps: { onButton: (id: string) -> () })` → `Show(view)`, `SetWallet(wallet)`,
  `SetCountdown(text?)`, `Skip()`, `Hide()`, `IsVisible()`, `SetLayout(scale, viewportSize)`, `Destroy()`. `View` =
  `{ kicker, title, subtitle?, star, lines, totals = { cash, material, materials, valor }, wallet = { cash, materials,
  valor }, note?, nextAbility?, buttons = { { id, text } } }`. A helper builds `lines`' words so both hosts agree.
- Behaviour: one row per line counting up in turn; then coins fly from the rows into the card's own wallet line, which
  rolls from `max(0, wallet.cash − totals.cash)` to `wallet.cash` (`SetWallet` retargets it when a later Snapshot
  lands); Timber logs stack beside the material count; Valor beside it with the next ability (§7). The key row is a
  glyph and its name, no amounts. Every number is the server's.
- Phones: every tween through `Motion.Info` / `Motion.Seconds` (shortened under `Theme.reducedMotion`, true on every touch
  device, `Theme.luau:1589`; `Motion.luau:10-27`); the flying icon count is gated on `Theme.lowEndDevice` (`:1591`), never
  on `reducedMotion`; a tap on the card outside a button jumps to the end state; buttons answer at any moment. Fits
  640×360 under the 58 px top bar (329 design px): the rows area shows what fits and scrolls to the counting row (a
  first full Forest Road run is up to 11 lines, 12 in a party). Presentation constants live in the module (one table).
- Hosts: **combat** (`CombatUIController`, ui B): from the summary RunState — title "Forest Road · Normal", subtitle how
  it ended and camps n / 3, star, the first clear's family text (RunResult), buttons Back to camp / Return (none on the
  `leave` card), countdown "Back to camp in 8", wallet from the latest Snapshot. **Hub** (`UIController`, ui A): from
  `ExpeditionSummary` — kicker "EXPEDITION REPORT", `summary.title`, one Dismiss button, wallet from the hub state
  (`cash`, `combat.materials`, `combat.valor`); keeps today's chaining behind the welcome-back card (`:835-850, 1450,
  1511, 1605`).

## 5. Run cash by era (Ben's pick: the cash study's (c) at M = 3)

- **Config (designer):** `Combat.json rewards.eraCashMult = [1, 670, 34000, 1400000]`: one number per era in
  `Config/Eras` order, each finite and ≥ 1 (Village exactly 1: a new save keeps today's pay; its first clear stays 4.3
  minutes of income, and the first clear after each Advance is worth 3.0 / 2.3 / 1.7 minutes of the new era's, study
  §6). An absent block reads ×1 everywhere (degrade, never an error). Types (A): `CombatRewardsConfig = { eraCashMult:
  { number } }`, `CombatConfig.rewards: CombatRewardsConfig?` (`:1244-1262`).
- **Pure (A):** `Combat.EraCashMult(rewards, era): number` = the entry for `era` (an era past the list takes the last; a
  malformed list or entry → 1). **The choke point:** `Combat.CombatCashMult(state, gameConfig, shopConfig)`
  (`Combat.luau:220-230`) becomes `(state, gameConfig, shopConfig, rewards, era)` and returns Legacy × Founder's ×
  `EraCashMult(rewards, era)`. Its one caller, `WaveService.credit` (`:822`), passes `combatConfig.rewards` and the
  member's `cashEra`. `SplitCarry` applies it to cash only (`:341-370`): Timber and Valor are unchanged; chests and first
  clears pay no cash.
- **The era:** `RunMember.cashEra` (Types `:1345-1354`, A) = the member's own profile `era` at `ArenaService.Admit`,
  beside `incomeRate` (`:1165`, B); nothing here changes `era` (Advance, Rebirth are hub-only). Read per member in
  `mults[userId]` (`WaveService.luau:822-826`), so a party mixes eras; Legacy and Founder's stay on top (study §2).
- **Mirrors (designer).** `sim_combat.py` mirrors the factor in `combat_cash_mult` (`:657-661`, now `(state, game, shop,
  rewards, era)`) with `era_cash_mult` for `EraCashMult`, **never in `level_pay`** (so 1, 2, 5, 6, 12, 13, 20, 21, 23 and
  `sim_range.py` stay unchanged: their cash is base pay, and R8 compares two runs at one multiplier).
  `check_stage_mirror.py` adds `Combat.EraCashMult` cases against `era_cash_mult` (Combat is already a module there).
  The assertion changes (study §5.4, values for (c) M = 3, `RUN_CASH_CAP_FRACTION` 0.25 at `:51`):
  - **4 "cash vs era cost"** (`:1588-1608`) covers every era: a Normal clear × E × the lap's LegacyMult is at most 25% of
    what the era still owes at its middle (0.92 / 1.36 / 0.27 / 0.05%); and the first clear after an Advance is at most
    2% of what the era still owes when it lands (0.88 / 1.23 / 0.25 / 0.05%).
  - **New "never faster than building":** back-to-back Normal and Hard runs never finish an era before the greedy city
    (Normal +28.8 / +8.1 / +3.9 / +2.3%, Hard +22.7 / +3.4 / +1.2 / +0.8%; Village / Boomtown / Metropolis / Orbital).
  - **New "a few minutes at the start":** Village's E is exactly 1, and the first clear after each Advance is worth 1-6
    minutes of that era's income (4.3 / 3.0 / 2.3 / 1.7).
  - **22 split carry** (`:1798-`): the fuzz's cash multipliers widen from ×1-×2 to era scale, up to 1.4M × 16.19 (lap 2
    Orbital's LegacyMult, about ×2.3e7), so the whole-unit carry is proven at the sizes it will meet.
  - The spot check "CombatCashMult at legacy 261 (era 3 entry)" (`:1028-1032`) sets era 3: ×3.61 × 34,000 = ×122,740.
  - The "never faster" check needs an **optional pause hook on `sim_economy.simulate_era`** (`sim_economy.py:546`): one
    additive keyword argument defaulting to none, with `py tools/sim_economy.py`'s output byte-identical to `main`'s. It is
    the only `sim_economy.py` edit in W3 (relay to M11 in §10).

## 6. Deletions (L4W3-9) and what must not go

| # | Deleted | Readers (file:line) and how each ends | Owner |
|---|---|---|---|
| 1 | `Config/Missions/1_Village.json` | `Catalog.GetMissionConfig` / `GetMissionById` and caches (`:47-48, 316-360`) go; `UIController :405-416`, `ExpeditionPanel`, `ExpeditionSummaryCard :274`, `ExpeditionService :673, 903`, `ArenaService :866`; `run_harness.py:2267`, `tests_l1.luau:2182` keep only `Config/Levels`; `mutate.py:60`'s glob (drop it) | designer; A, B, ui A |
| 2 | `Types.MissionConfig` (`:1264-1275`), Combat.luau's copy (`:45-55`) | rows 1 and 3 | A |
| 3 | `Combat.MissionUnlocked` (`:194-209`), `RecommendedPower` (`:211-218`) | `ExpeditionPanel :815-816, 844-847`, `ExpeditionService :674` | A, ui A |
| 4 | `Combat.json overdrive`; `CombatOverdriveConfig`, `CombatConfig.overdrive`, Combat.luau's slice | row 3 only; `check_levels_mutants.py:968-971` use "overdrive" as a difficulty name and stay | designer, A |
| 5 | The Overdrive toggle and the era tiles | `ExpeditionPanel` (§2.4), the Theme constants only they read (ui A proves each) | ui A |
| 6 | TopBar's Gear Power chip | `TopBar.luau:21-23, 181`, `UIController :954`; then the Snapshot/Delta `gearPower` (Types `:110-112, 131`; `EconomyService :95, 301, 346`; combat `Main.server.luau:110`; `UIController :83-85, 133-136, 1005, 1105-1108`); `Armory.GearPower` / `SavedPower` only if A finds no other `src` reader (then their `check_stage_mirror` rows go) | ui A, A, B, designer |
| 7 | `missionId` / `overdrive` / `era` on the ticket, hint, record, registry, run list, `RunSummary` | §2.2, §2.3, §4.1; `RunState.overdrive` already went (W1b row 20) | A, B, ui A |
| 8 | `SummaryCard.luau` (combat), `ExpeditionSummaryCard.luau` (hub) | `CombatUIController`, `UIController :61, 835-850` → RunTally | ui B, ui A |
| 9 | `debug.provingStartDelay`; `Types :1212` | `WaveService :2069`; `tests_l1.luau:2268` | designer, A, B |
| 10 | The stale DebugBots comment | `ArmoryService.luau:50` (one line; M11 file) | A |

**Must not go:** `combat.missions`, `Types.MissionRecord` (its `overdriveBest`), `combat.gear`, `Armory.json legacy`
(saved, L4B-9); `combat.highestEra` and `Combat.TouchHighestEra` with its three callers (a saved record, no longer a
gate; `ArmoryService.luau:148` is M11's); the run list, `RequestJoinRun`, the party strip and the `fakeParty` /
`fakeInvite` / `fakeRuns` levers; `coop.lobbyWaitSeconds`; `MissionCrowd*` types; `CombatMode`'s "mission".

## 7. Valor's purpose, Brutal's note

- `Expeditions.json abilities.upcoming: [{ "id": "glide", "name": "Glide", "text": "Float down from any height.",
  "with": "castle" }]` (designer; `with` names a map node). Types `UnlockUpcomingDef` and `abilities.upcoming?` (A,
  `:2694`). Never sold: `Unlocks.Sellable` reads `list` only (A's test: `RequestBuyAbility("glide")` is refused).
  `ArmoryAbilityPage` (ui A) shows each as a locked row "With the Castle" (the node's name), no button; RunTally's Valor
  line names the first one not owned ("next: Glide · with the Castle").
- `Levels/1_ForestRoad.json difficulties.brutal.note: "Castle gear"` (designer); `LevelDifficulty.note: string?` (A,
  `:2429-2437`); `StageFlow.Validate` accepts an optional string ≤ 24 (B); `MapScreen` shows it on the difficulty's line
  (`:354`, ui A).

## 8. The better simulated human waits for W4

W3 moves no combat number (era cash is a common factor; R8 and the bands are ratios), so nothing it would re-measure
moves; its gate re-runs the slow tools (R8 about 54 min) beside W3's sharded run; and it belongs with W4's phone and
difficulty pass. Owner: economy-designer, W4 contract.

## 9. Studio levers and Ben's test (key-only)

- **R** (combat, mission lobby, Studio only): lever `fakeDepart`, value `"<levelId>:<difficulty>"` from the map's
  current selection (default `provingLevel:provingDifficulty`); twin attribute `debug.fakeDepartAttribute`
  ("DebugFakeDepart", a string, consumed). DebugService (B) → `WaveService.FakeDepart`: in the lobby only, `depart` =
  `waiting` on that pair with the members present standing in for the expected list, then the real tick runs.
- **P** (combat, mission only, Studio only): lever `cashEra` "next" cycles the pay era 1 → 4 → 1 for every member of the
  session (overrides `cashEra`, session only, nothing saved); toast "Pay as Boomtown (×n)". Twin `debug.cashEraAttribute`
  ("DebugCashEra", a number, consumed). The range keeps P for its panel (`RangePanel.luau:114-118`); ui B confirms the
  mission's `DEBUG_KEYS` (`CombatUIController.luau:205-215`) are not bound in a range boot. `DEBUG_HINT` (`:226-231`)
  gains "R depart · P pay era".
- **A. `build\proving.rbxl`, no API access needed:** Play → lobby → **R** → "Forest Road · Normal starts in 5" → the level
  starts; **N** to the clearing (never B), beat the Chief → the tally card counts up, coins fly, Timber piles; tap to
  skip; Back to camp → nothing starts by itself. **P** twice → "Pay as Metropolis"; Up on the map, **R** → a Hard
  countdown; a run → bigger cash rows. On a phone emulator the motion runs shortened.
- **B. The bridge, needs "Enable Studio Access to API Services" on in both files** (the StudioHandoff DataStore and the
  ticket's MemoryStore; it plays on Ben's real save, as every bridge test since C1): `build\test.rbxl` → Play →
  Expeditions → the map → Forest Road, Normal → Depart → kicked "Handoff saved" → Stop → `build\combat.rbxl` → Play →
  the countdown → the level → Return to your city → kicked → `build\test.rbxl` → Play → the same card over the city.
  With API access off, Depart answers "unavailable" and nothing is released (C1).

## 10. Owners (disjoint files), relays, and the merge with M11

- **luau-engineer A:** `src/shared/**` but Config and Layouts (new `MapRules`, `RunLines`; `Types`, `Catalog`,
  `Combat`), `src/server/**` (`ExpeditionService`, `HubRemotes`, `Main.server.luau`, `StudioBridge`, `EconomyService`,
  `ArmoryService`); new `tools/crowd_harness/tests_l4w3.luau` (MapRules, RunLines, EraCashMult, glide never sold).
- **luau-engineer B:** `src/combat/server/**`: `Main.server.luau`, `ArenaService`, `WaveService`, `RunRegistry`,
  `ReturnService`, `DebugService`, `CombatRemotes`, `StageFlow`, `SecretFlow`; new `tools/crowd_harness/tests_l4w3_run.luau`
  (the depart rule's every edge, lines at each credit site, `cashEra` frozen at the admit, the wallet before the card).
- **ui-engineer A:** `src/client/**` except `RunTally.luau`: new `HubMap.luau`; `UIController`, `ExpeditionPanel`,
  `TopBar`, `MapScreen`, `ArmoryAbilityPage`, `Theme` (deletions; additions only for HubMap, in one block); deletes
  `ExpeditionSummaryCard.luau`.
- **ui-engineer B:** `src/combat/client/**` and new `src/client/UI/RunTally.luau`; deletes `SummaryCard.luau`.
- **economy-designer:** `Config/Combat.json` (`rewards`, `levels.departCountdownSeconds`, the two debug attributes; out:
  `overdrive`, `provingStartDelay`), `Missions/` (deleted), `Expeditions.json`, `Levels/1_ForestRoad.json`; `sim_combat.py`,
  `check_stage_mirror.py`, `run_harness.py`, `mutate.py`, `mirror_mutants.py`, every existing `tests_*.luau`,
  `docs/BALANCE.md`; in `sim_economy.py` only the optional pause hook (§5).
- **Lead:** `combat.project.json` (map `RunTally` beside `MapScreen`, `:71`), `py tools/proving_project.py`, sourcemaps,
  an INTERFACES pointer `# L4 W3 contracts`.
- **Relays:** A → B: the MapRules / RunLines APIs, the Types (`RunLine*`, `RunSummary`, `RunTicket`, `ActiveRun`,
  `RunState.depart`, `RunMember.cashEra`, `LevelDifficulty.note`), `TeleportHint`, `CombatCashMult`. A → ui A: `MapState`,
  `RequestMapState`, `RequestExpedition`, `RunListEntry`, `gearPower` gone, `RunLines.Read`. B → ui B: the depart states,
  the line order, the levers' toasts. ui B → ui A: RunTally's API. Designer → A, B: Config key names. A, B, ui →
  designer: every changed line a pin or `mutate.py` entry reads (file, old, new), new `SOURCES`, mutants for MapRules,
  RunLines, the depart rule, EraCashMult. Anyone → lead: a remote, a project file.
- **Merge with M11** (`tycoon-m11`, branch `m11-port`; do not read or edit it). W3 touches these M11 files, each locally:
  `UIController.luau` (mount HubMap and RunTally, tiles, chip, summary parse), `TopBar.luau` (`SetPower` out),
  `Theme.luau` (deletions, one HubMap block), `EconomyService.luau` (`gearPower` out), `ArmoryService.luau` (one
  comment), `HubRemotes.luau` (two validators, one event), hub `Main.server.luau` (two handlers), `Types.luau` (§2-§5
  shapes, appended in one `-- L4 W3` block where new), `Catalog.luau` (the mission getters out), and
  `tools/sim_economy.py` (one additive optional argument on `simulate_era`, default output byte-identical; M11 owns edits
  to that file now, so **whoever merges second resolves the hook**). W3 does not touch `PartyService`, `ProfileSchema`
  (no bump; v10 if ever), `BottomBar`, `DebugPanel`, `LegacyPanel`, `Game.json`, `LegacyShop.json`, `CityDressing.json`.
  **Whoever merges second wires the Expedition bottom-bar key to `HubMap`'s open under M11's unlock gate.** The lead
  sends both relays to the M11 session when W3's designer reports the hook.

## 11. Order

A writes `docs/prompts/l4-w3-reports/relay-a.md` (the MapRules / RunLines / Types signatures) first; B, ui A and ui B
start at once against this contract and adopt that file when it lands. The designer starts with Config, then tools once
A's and B's reports list their pin changes; `rewards` carries Ben's pick from the start. Every agent:
`git status` and `git diff` first, commits nothing, kills only its own PIDs, reports to
`docs/prompts/l4-w3-reports/<role>.md`.

## 12. Definition of done

Each owner before reporting: stylua, selene, luau-lsp on both sourcemaps, `check_compile.py`, the harness, `mutate.py`
filtered to its files. QA from `tycoon-p5` in Bash:

```bash
export PATH="$HOME/.rokit/bin:$PATH"; L=C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe; R=C:/Users/benja/Desktop/tycoon-p5
stylua --check src && selene src
rojo sourcemap default.project.json -o sourcemap.json && rojo sourcemap combat.project.json -o sourcemap.combat.json
luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.json src/client src/server src/shared
luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.combat.json src/combat src/shared
py tools/check_compile.py
rojo build -o build/test.rbxl && rojo build combat.project.json -o build/combat.rbxl
py tools/proving_project.py && rojo build .proving.project.json -o build/proving.rbxl
for p in boomtown metropolis orbital; do rojo build $p.project.json -o build/$p.rbxl; done
py tools/crowd_harness/run_harness.py $R $L
py tools/check_stage_mirror.py && py tools/crowd_harness/mirror_mutants.py --luau $L
py tools/levels/forest.py check && py tools/testfit/raiderpose.py --check && py tools/check_raider_mirror.py --luau $L
py -3.12 tools/check_parkour.py
py tools/assets/raider_frames.py --check --require-harvest && py tools/assets/weapon_frames.py --check --require-harvest
py tools/assets/gen_templates.py --check && py tools/gen_asset_manifest.py --check   # where assets\ is
py -3.12 tools/check_levels.py && py -3.12 tools/sim_range.py --check
py -3.12 tools/sim_range.py --r8 --check                      # about 54 min
py tools/sim_combat.py --check && py tools/sim_economy.py --check
py -3.12 tools/check_levels_mutants.py                         # background, about 2 h
py tools/crowd_harness/mutate_shards.py $R $L "" --shards=10   # full run, about 2 h, alone in its checkout
git grep -nE 'missionId|MissionUnlocked|RecommendedPower|GetMission|\boverdrive\b|SummaryCard|provingStartDelay|gearPower|SetPower' -- src   # empty
git diff --stat main -- src/server/Services/PartyService.luau src/server/Services/ProfileSchema.luau src/client/UI/BottomBar.luau   # empty
S=C:/Users/benja/AppData/Local/Temp/claude/c--Users-benja-Desktop-tycoon/259ecf10-ad47-49f7-9d11-55e5c7db6b5a/scratchpad/l4-w3-qa
mkdir -p $S && py tools/sim_economy.py > $S/econ_w3.txt   # the main checkout is on main; W3 edits no config it reads
py C:/Users/benja/Desktop/tycoon/tools/sim_economy.py > $S/econ_main.txt && cmp $S/econ_main.txt $S/econ_w3.txt   # identical
git ls-files --eol | grep -c w/crlf                            # 0
```

Done: every line green with its counts named (`mutate_shards` 0 not caught; the saved `overdriveBest` is not matched by
`\boverdrive\b`). Then Ben's look (docs-keeper writes it, keys only): §9 A, then §9 B.

## 13. Risks, and what Ben must judge

1. **Only the live pair proves** `ReserveServer` + group `TeleportAsync` with `levelId`, the real `...Codes` ticket, a party
   arriving seconds apart against the countdown and the 30 s cap, `ReturnData` with lines, `TeleportInitFailed` (study
   §5). W4's staging publish (D4 A) is where to see them first.
2. **Ben judges** the card's motion (count-up pace, the coins, the pile; shortened on phones), the countdown's length
   (5 s proposed, solo included), and "Party & runs" in the map's footer. The era anchor is his ((c), M = 3); the honest
   cost he was shown: a clear fades to seconds of income a quarter into each era (study §6).
3. **Brutal under (c):** back-to-back Brutal runs would beat the city by 1.8 / 2.9 / 1.3% (Boomtown / Metropolis /
   Orbital; study §6). Brutal needs Castle gear (T5) by Ben's ruling and a T4 Brutal clear is unmeasured, so the "never
   faster" check gates Normal and Hard only; re-run it with Brutal when T5 exists (economy-designer, the Castle).
4. **M11 merge:** eleven shared files (§10), local edits; the second merger adds the Expedition key wiring and resolves
   the `simulate_era` hook.
5. **Text drift:** the MapRules move re-aims harness calls, pins and `mutate.py` entries in one round; a stale entry blocks
   the sharded run.
6. **The card's height:** a party's first full run can reach 12 lines; the rows scroll, the totals never do. If Ben finds
   scrolling worse than grouping, the fallback is one "Camp bonuses" row (a client change only).
7. **A bridge test plays on Ben's real save** (API access on), as since C1; R and P never write the profile.
8. **Publish freeze:** both places publish together at W4 (the ticket shape changed on both sides).

## 14. Lead's rulings on the draft (2026-10-23)

- **L4W3-12. Play opens on the thing to judge.** In `build\proving.rbxl`, Play alone must reach the countdown and start
  Forest Road: a proving boot with `debug.provingAutoStart` enters `waiting` (§3) on `provingLevel` / `provingDifficulty`
  with the players present as the expected list. **R** is for doing it again after a run, never the first step of Ben's look.
- **L4W3-13. Keys.** ui-engineer B proves R and P are unbound in a mission boot (`InputController`, `CombatUIController`
  `DEBUG_KEYS`, ability and slot keys, gamepad maps); if either is taken, take the next free letter, use it in the toast and
  `DEBUG_HINT`, and say it in the report so the docs use it.
- **L4W3-14. The `sim_economy` comparison has a fixed baseline.** Before editing `sim_economy.py`, the designer saves
  `py tools/sim_economy.py` stdout to the scratchpad's `l4-w3-qa/econ_base.txt`; QA compares against that file, not
  against the main checkout (M11 may merge to `main` first and move it). §12's last `cmp` reads `econ_base.txt`.
- **L4W3-15. `combat.project.json`'s `RunTally` entry is ui-engineer B's** (one entry beside `MapScreen`, added in the same
  step that creates the file, so the combat build never points at a missing file). Every other project-file change stays
  the lead's.
- **L4W3-16. Process.** Every owner is a fresh Opus agent started from this file; reports and relays go to
  `docs/prompts/l4-w3-reports/`; a resumed agent is only for a short follow-up on what it just did.
