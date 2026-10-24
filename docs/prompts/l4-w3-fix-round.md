# L4 W3 fix round — the lead's rulings on the four-slice review

Review of `93eb8e9` (`docs/prompts/l4-w3-review/1-hub.md`, `2-combat.md`, `3-clients.md`, `4-data.md`): **0 Critical, 1 Major,
12 Minor, 15 Suggestions.** Every finding below has a ruling and one owner. Read the finding in its slice file before fixing.
Owners as in the contract §10 (luau A: `src/shared/**` minus Config/Layouts, `src/server/**`; luau B: `src/combat/server/**`;
ui A: `src/client/**` except `RunTally.luau` and the new `TallyRules.luau`; ui B: `src/combat/client/**`, `RunTally.luau`,
`TallyRules.luau`; designer: Config, Layouts, simulators, gates, `run_harness.py`, `mutate.py`, `mirror_mutants.py`, existing
`tests_*.luau` except the W3 ones named here, `docs/BALANCE.md`). New test files belong to the owner who creates them.

## Rulings

### Combat server (slice 2) — luau B

- **F1 (M1, Major). A reserved server serves one departure.** `WaveService.Reset` no longer clears `boot.departOpened`; only
  a new server boot starts with it unset. A failed trip home that rejoins the same server (it re-reads the same
  `GetJoinData` and the hub's ticket still verifies) must land in the lobby with nothing auto-starting and the map not forced
  open. Re-aim the pin `resetOpened` to "Reset keeps it" (designer) and add a mutant that clears it in Reset (designer).
  Add a harness case: arm, run, Reset, arrive again with the same verified ticket → no `waiting`, no `counting`.
- **F2 (m1). The auto-start never refuses because of a member who was not expected.** At zero, a member who is not in the
  ticket's expected list and has no body yet is treated as a late arrival (stays in the lobby camp, enters at the next
  boundary, today's `ArenaService.Admit` rule); the start goes ahead for the rest. Expected members still need their bodies
  (they hold the countdown before zero, so they have them). If excluding a member from `startLevel` cannot be done without
  changing the leader's own Start, say so and hold at zero until the bodies stand, never refusing; report which you chose.
- **F3 (m3). Raiders and boss lines count kills**, not bodies damaged, so "Raiders ×n" agrees with the card's kill count in
  a party. Camp, chest, key, first clear and mentor lines keep "1 per credit".
- **F4 (m4). P must never pay into a real save.** The P lever (`cashEra`) is refused, with a toast "P needs Studio API access
  off", whenever the session's profiles are the real store (Studio with API access on); it works only on the mock store.
  Find how `DataService` tells the two apart (`src/server/Services/DataService.luau` around :148, luau A's file: if no reader
  exists, A adds `DataService.IsMock(): boolean` and you call it). Fix DebugService's comment; the lead fixes contract §13.7.
- **F5 (s1, s2, s3).** The stale mentor comment over `onCrowdKilled`; the auto-start's `startLevel` call inside `pcall`, a
  throw → `picked` plus one warn; `tickDepart` returns at once once the state is `done` or `picked`.
- **F6 (slice 4 m2). A bad difficulty `note` is dropped, never refuses the level.** It is display only: `StageFlow.Validate`
  drops a malformed `note` (not a string, or over 24 bytes) with one warn and the level stays valid. (The designer makes
  `check_levels.py` fail on it, so shipped data never carries one.)
- **s4 (a leader's early Depart during `waiting` cancels the auto-start): no change** (the leader's choice; contract-compliant).
- For the designer: every condition line the 19 surviving condition probes in `2-combat.md` m2 touched (file, exact text),
  plus the lines F1-F6 change.

### Hub server and shared (slice 1) — luau A

- **F7 (m3 + slice 3 s3). One summary reader for both readers.** New pure `RunLines.ReadSummary(value): RunSummary?`: `title` a
  string of 1-48 bytes; every total and count finite and ≥ 0 (counts whole); `lines` through `RunLines.Read`; any failure →
  nil (the whole summary is dropped, never shown). `StudioBridge.readSummary` uses it (A); `UIController.readRunSummary` uses
  it (ui A). Cases in `tests_l4w3.luau`, including NaN, infinity, a negative total and a 49-byte title.
- **F8 (m2). Prove both halves of every `RunLines.Read` field rule** in `tests_l4w3.luau`: negative `cash` / `materials` /
  `valor`, a 49-byte `name` and `material`, `count` = +inf. Also slice 4 s2: the shipped-upcoming check asserts
  `#upcoming >= 1`.
- **F9 (s2). One copy of the secret rows.** Move `SendMap`'s copy of WaveService's `sitesOf` / `secretRows` into `MapRules`
  (one function, e.g. `MapRules.SecretRows`); `SendMap` calls it; luau B re-points WaveService to it in this round. Write the
  signature into `docs/prompts/l4-w3-reports/relay-a2.md` first, for B.
- **F10 (s1 + slice 4 s3).** The stale comments: `Types.luau:180-182, :976, :990-991`, `Catalog.luau:27`,
  `ExpeditionService.luau:775-777`.
- **F4 support:** `DataService.IsMock()` if B needs it (relay-a2.md).
- **F13 support:** `MapRules.FirstPick`, moved verbatim from `MapScreen` (relay-a2.md).
- For the designer: the exact lines of the seven hub probes in `1-hub.md` m1 (the `Startable` call's arguments and verdict
  branch in `Depart`, the leader's stars in `SendMap`, `RunLines.Read` in `StudioBridge`, the `ReadArrival` caps, the
  difficulty cap in `HubRemotes`), plus the lines F7-F10 change.

### Clients (slice 3) — ui A and ui B

- **F11 (m1). Touch controls step aside while the city map or the city card is open.** ui A writes a small helper
  `src/client/UI/TouchHold.luau` (`Hold(reason)` / `Release(reason)` with a count; `GuiService.TouchControlsEnabled` false
  while any hold is out, restored to what it was) and uses it in `HubMap` and the hub's RunTally host. `ArmoryScreen` (also
  mapped into the combat place) keeps its own R9 toggle untouched: the map and the Armory already close each other; ui A
  proves the card can never open over the Armory (or closes the Armory first). The combat place is unaffected (its HUD is
  DisplayOrder 1).
- **F12 (m2). The city card shows no star** (`star = false`): it is a report of the whole visit, not of one clear. ui A
  withdraws its deviation 2.
- **F13 (m3). The client rules get gates.** ui B moves the pure rules into a new pure module
  `src/client/UI/TallyRules.luau` (mapped beside `RunTally` by ui B in `combat.project.json`): `Rows`, `Totals`, `WithText`,
  `NextAbility` (with slice 3 s4: validate each `upcoming` entry the way `ArmoryAbilityPage` does), `DepartLine`'s wording,
  and the depart decision (when the map opens, holds or closes on a RunState). ui B's cases go in a new
  `tools/crowd_harness/tests_l4w3_tally.luau`. luau A moves `MapScreen.FirstPick` into the shared `MapRules.FirstPick` (both places already load
  `src/shared`, so no project-file change; cases in `tests_l4w3.luau`, signature in `relay-a2.md`) and ui A re-points
  `MapScreen` to it. Both list for the designer the call lines to pin: HubMap's
  Depart arguments (`isPublic()`, never a literal), the city wallet's cash source, the flying-icon gate on
  `Theme.lowEndDevice`, the `picked` once-per-arrival guard.
- **F14 (s1). No rotated element inside the card's clipped rows** (Roblox does not clip rotated descendants): the Valor
  diamond becomes a non-rotated image or glyph (ui B).
- **F15 (s2).** `isRunResult` checks `levelId` is a string before `TallyHost` builds its key (ui B).
- **F16 (s5).** With `Config/Expeditions` missing, the Expedition key answers with a toast "Expeditions are unavailable" (ui A).

### Data and gates (slice 4) — the designer

- **F17 (m1). Say what assertion 24 proves.** Its label and `docs/BALANCE.md:7303, :7334` say "back-to-back runs on Normal or
  Hard never finish an era sooner than building", not "no way of running beats building". Add an ungated printed line per
  era with the best "k runs right after an Advance, then build" result (the reviewer's 2.4 / 1.4 / 0.5%, Village 6.8% at
  today's pay), and one sentence in BALANCE that any multiplier ≥ 1 gives it (the empty wallet after an Advance). The lead
  corrects MISSIONS_DESIGN §30 and has told Ben.
- **F18 (m2 + F6).** `sim_range.level_problems` (read by `check_levels.py`) fails on a malformed `note`; `check_stage_mirror`
  gets one broken-once case for F6's drop rule.
- **F19 (s1, s3, s4).** `tests_l3.luau:960`'s self-comparison relabelled or dropped (the pairs in `loadoutTests` keep the rule);
  the leftover text in `sim_range.py:5731, :5775, :10735, :10786` and the blank line at `check_stage_mirror.py:2443`; the
  "l3fix2 F1" `mutate.py` entry made live (a condition the dungeon can reach, not `incomePerSecond > 0`).
- **Pins and mutants for everyone's lists**: the 7 hub probes (slice 1 m1), the 19 combat condition probes (slice 2 m2),
  the 6 client probes (slice 3 m3) as `mutate.py` entries that each fail the harness; pins on the conditions, not only the
  call lines; the new test files in `run_harness.py` SOURCES / TESTS; `resetOpened` re-aimed (F1). Every entry matches the
  final text (0 stale).

## Order and done

1. luau A writes `relay-a2.md` (F7's `ReadSummary`, F9's `SecretRows`, F4's `IsMock` if needed) first; B, ui A, ui B start at
   once and adopt it. The designer starts with F17-F19, then pins and mutants as the other four report.
2. Every owner: `git status` / `git diff` first (the branch is at the review commit plus the review files); commit nothing;
   kill only your own PIDs; filtered `mutate.py` in your own named mutant folder only; report to
   `docs/prompts/l4-w3-fix-reports/<role>.md` with the gates and counts and "For the other owners".
3. Done = the contract §12 per-owner gates green, the harness green with the new cases, each fix's own new case or mutant
   shown failing without the fix. Then a fix-diff review, then QA (§12, the sharded full run).
