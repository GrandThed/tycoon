# L4 W3 report: luau-engineer A (shared code and the hub server)

Contract: `docs/prompts/l4-w3-contract.md` §2.1, §2.2, §4.1 (types, RunLines), §5 (types, EraCashMult, CombatCashMult),
§6 rows 1-4, 6, 7, 9, 10 (my parts), §7 (types, never-sold test). The signatures are in `relay-a.md` (written first,
unchanged since except one note in §3 below). Nothing committed.

## 1. What I built

- **`src/shared/MapRules.luau` (new, pure, requires Types only).** Moved verbatim from StageFlow (`nodeOf`, `hasStar`,
  `starCount`, `NodeState`, `MapState`, `Award`, `export type Stars`) and SecretFlow (`Reward`, `Site`, `finite`,
  `whole`, `rewardOf`, `Sites`, `MapRow` renamed `SecretRow`). New: `Built(levelIds)`, `Startable(map, built,
  leaderStars, levelId, difficulty, levelDifficulties?) -> "ok" | "locked" | "unavailable"` (first node naming the level
  is judged; locked before unavailable; a difficulty must be ranked by the map AND be a table in the level file's
  `difficulties`), `MAX_LEVEL_ID_LENGTH = 32`, `MAX_DIFFICULTY_LENGTH = 12`, `export type StartVerdict`.
- **`src/shared/RunLines.luau` (new, pure).** `Add` (merge by kind + id in first-credit order, append only while
  `#lines < MAX`, first name kept, first non-empty material kept, non-finite / negative amounts add 0, id / name /
  material cut to `MAX_TEXT` at a UTF-8 boundary so `Read` never drops a server-built line), `Read` (indices 1..16
  only, holes and junk skipped, every field shape-checked, fresh copies), `MAX = 16`, `MAX_TEXT = 48`.
- **`src/shared/Combat.luau`.** `EraCashMult(rewards?, era)`; `CombatCashMult(state, gameConfig, shopConfig, rewards?,
  era)` = Legacy x Founder's x EraCashMult. Gone: `MissionUnlocked`, `RecommendedPower`, the `MissionConfig` and
  `CombatOverdriveConfig` copies; `CombatRules = { coop }`; `CombatOwner` lost the `rebirthCount` only
  MissionUnlocked read. `TouchHighestEra` stays (§6 "must not go").
- **`src/shared/Types.luau`.** As listed in `relay-a.md` §5: the new `-- L4 W3` block at the end (`RunLineKind`,
  `RunLineKey`, `RunLine`, `RunDepartState`, `RunDepart`, `CombatRewardsConfig`, `UnlockUpcomingDef`); in place:
  Snapshot / Delta `gearPower` out, `ArmoryConfig.power` out, `CombatOverdriveConfig` and `CombatConfig.overdrive` out,
  `CombatConfig.rewards?` in, `CombatDebugConfig.provingStartDelay` out and `fakeDepartAttribute?` /
  `cashEraAttribute?` in, `CombatLevelsConfig.departCountdownSeconds` in, `MissionConfig` out, `RunMember.cashEra`,
  `RunSummary.title` / `lines` (no `missionId`, `overdrive`), `RunState.depart?`, `ActiveRun` / `RunTicket` /
  `RunListEntry` on `levelId` + `difficulty` (no `missionId`, `overdrive`, registry `era`), `LevelDifficulty.note?`,
  `ExpeditionsConfig.abilities.upcoming?`; the SlotTiers comment now names `Armory.StrikeTier`.
- **`src/shared/Catalog.luau`.** `GetMissionConfig`, `GetMissionById` and both caches gone (row 1).
- **`src/shared/Armory.luau`.** `GearPower`, `SavedPower` and `HeldTiers` gone, with `ArmoryConfig.power` and
  Validate's `power.tierWeight` line (row 6 and L4B-5, see §3).
- **`src/shared/Unlocks.luau`.** One comment (it named SavedPower). No rule changed: `Sellable` / `Find` read `list`
  only, so `upcoming` is never sold.
- **`src/server/Services/ExpeditionService.luau`.** `Depart(player, levelId, difficulty, public)`: the mission check is
  `MapRules.Startable(map, MapRules.Built(Catalog.GetLevelIds()), Unlocks.StarsOf(state.combat), levelId, difficulty,
  file.difficulties)` on the leader's own profile; no `Expeditions` config = `unavailable`; refusals on `expedition`
  with `slotId = levelId`. Ticket `{ accessCode, privateServerId, levelId, difficulty, public, expected }`; teleport
  data `{ levelId, difficulty, hostUserId }`; `Handoff`, the bridge hint, `Join`, `asActiveRun` (an old-shape entry
  reads as none), `SendRunList` and the fakeRuns lever (`debug.provingLevel` / `provingDifficulty`;
  `FAKE_MISSION_ID` gone) on the new pair. New `SendMap(player)`: leader = `PartyService.Get(player).leaderUserId`
  else the player; leader stars from their profile (`{}` for a fake leader or one without a profile); own stars; own
  secret rows (`MapRules.Sites` per built level, cached for the server's life behind a no-yield pcall, then
  `SecretRow`); fires `MapState` to that player only; no answer while the player has no profile or Expeditions is
  missing; never yields.
- **`src/server/Services/HubRemotes.luau`.** `RequestExpedition`: `args.n == 3`, `isShortName(levelId, 32)`,
  `isShortName(difficulty, 12)`, `public` boolean, bucket `prompt` (`MAX_MISSION_ID_LENGTH` gone). New
  `RequestMapState` (`args.n == 0`, bucket `calls`); new event `MapState`.
- **`src/server/Main.server.luau`.** The RequestExpedition handler passes `(levelId, difficulty, public)`; one new
  handler `RequestMapState` → `task.spawn(ExpeditionService.SendMap, player)`.
- **`src/server/Services/StudioBridge.luau`.** `TeleportHint = { levelId, difficulty, hostUserId, accessCode? }`;
  `WriteDeparture` writes them; `ReadArrival` requires `levelId` a non-empty string of at most 32 bytes, `difficulty` a
  string of at most 12, `hostUserId` an id (else warn + nil); `readSummary` requires `title: string` (no `missionId`,
  no `overdrive`) and reads `lines` through `RunLines.Read`.
- **`src/server/Services/EconomyService.luau`.** `computeGearPower`, the Delta's and the Snapshot's `gearPower` and the
  Armory require gone (row 6).
- **`src/server/Services/ArmoryService.luau`.** Row 10: the stale DebugBots comment now reads "DebugFakeParty is sticky
  (a count to play under, not an event), so it applies to every player whenever the typed value changes."
- **`tools/crowd_harness/tests_l4w3.luau` (new, 90 checks).** Groups built, startable (every answer and the order),
  map state (the moved rules on a fixture), chests (Sites, SecretRow), shipped map (the caps fit every shipped id and
  difficulty, every first-clear line id fits 48 bytes, the first shipped level is startable on a fresh save), add,
  read (every drop rule), era (every degrade, Ben's pick on the shipped Combat.json, Village exactly 1), cash mult
  (x34,000 on Legacy 2 x Founder's 1.5 = x102,000), upcoming (`RequestBuyAbility("glide")` refused by
  `Unlocks.Apply(state, Unlocks.Find(config, "glide"), true)` = "invalid" with nothing taken; Sellable silent; no key;
  on the shipped file nothing upcoming is sold and each `with` names a map node). Ends with the verdict line.

## 2. Gates (on the worktree as it stood, other owners mid-wave)

- `stylua --check` and `selene` on my 13 Luau files: clean (0 errors, 0 warnings).
- `luau-lsp analyze` with both sourcemaps (regenerated into my scratch folder): hub `src/client src/server src/shared`
  exit 0, combat `src/combat src/shared` exit 0 (both clean at the last run; an earlier run had only B's in-flight
  WaveService lines).
- `py tools/check_compile.py`: PASS, 187 files.
- Harness: `HARNESS: PASS (4,988 checks)` from the real `run_harness.py` (the designer had registered MapRules,
  RunLines and both W3 case files); my file alone 90 checks, 0 failing.
- My own mutation proof (scratch copy of `src`, tests.luau + tests_l4w3.luau only): 36 / 36 proposed mutations of
  MapRules, RunLines and EraCashMult / CombatCashMult caught (`.../scratchpad/l4-w3-luauA/mutants_a.py`, runner
  `mut_run.py`). Two were vacuous at first and got cases: a later material replacing the first, and a non-table list
  (a string list survived because `("x")[1]` is nil).
- `mutate.py` filtered to my files (185 entries: Unlocks 64, Armory 60, Combat 29, MapRules 17, ArmoryService 14,
  EconomyService 1), three slices (`0:878`, `878:1247`, `1247:2192`) with my own `MUTATE_ROOT=mutant_luauA_<k>`:
  every baseline `HARNESS: PASS (4,988 checks)`; **185 run, 0 not caught** (62 + 62 + 61), no stale entry (the
  designer had already retired the 15 listed in §5.3). Logs: `.../scratchpad/l4-w3-luauA/mutate_{0,1,2}.txt`.
- §12 `git grep -nE 'missionId|...|SetPower' -- src`: empty for all of `src` at my last run. `git diff --stat main --
  PartyService ProfileSchema BottomBar`: empty.

## 3. Deviations from the contract, and why

1. **`Armory.HeldTiers`, `ArmoryConfig.power` and Validate's `power.tierWeight` line also went** (row 6 names only
   GearPower / SavedPower). L4B-5: once SavedPower went, HeldTiers had no `src` reader (WeaponService builds its
   tiers with `StrikeTier`), and `power` was read only by GearPower and the line validating it. The designer already
   retired the tool side (Armory.json `power`, check_stage_mirror rows, tests_l3 cases).
2. **`RunLine` is written flat**, not as `RunLineKey & {...}`: the same eight fields; the old solver checks a table
   literal against an intersection part by part.
3. **Extra names:** `Types.RunDepartState` (the three states, named once), `MapRules.StartVerdict`,
   `RunLines.MAX_TEXT` (the 48-byte cap, read by my test and useful to the client).
4. **`Startable` wants the difficulty's entry to be a table** (the contract says "a key of"): a non-table entry would be
   refused by the dungeon's `resolveLevel` anyway, so the hub refuses it first.
5. **`EraCashMult` has no explicit empty-list check**: an empty list indexes 0, reads nil and returns 1 (the relay's
   table still says "empty list -> 1", which the Python mirror must handle explicitly).
6. **`RunLines.Add` cleans its inputs** (amounts, text length): not in the contract; it means a line the server built
   can never be dropped by `Read` on the other side.
7. **`SendMap` answers nothing** while the player has no profile or `Config/Expeditions` is missing.
8. **Types optionality:** `fakeDepartAttribute` / `cashEraAttribute` are `string?` (nil = lever off, as every lever
   added since L2); `departCountdownSeconds` is a required number (the designer ships it).

## 4. The M11 relay: every departure still stamps (`stampDeparture`)

Confirmed, no W3 path skips it, and W3 adds no departure path:
- `ExpeditionService.luau:476` `stampDeparture(state)` runs for every member inside `handOff` (`:462`), **before** the
  Studio bridge branch (`:482 if StudioBridge.IsActive() then`) and the live teleport.
- Both departures go through `handOff`: `Depart` at `:785` (`handOff(keepPartyMembers(player, members), {`) and `Join`
  at `:852` (`handOff({ player }, {`).
- The only `ok = true` answers are inside `handOff` (`:512` bridge, `:537` live). A member whose bridge record fails
  is unstamped (`:499`, `:507`) because that member did not depart; `abortDeparture` hands the stat back after a failed
  teleport (C0 behaviour, unchanged).
- The text check is already in run_harness.py (the designer's): `hubHandOff` body with `stampThenBridge`, `stampOnce`,
  `okInHandOff`, `departHandsOff` (my filtered mutate run saw them catch the Depart-without-handOff mutant).

## 5. For the other owners

### 5.1 luau-engineer B (`src/combat/server/**`)
Already adopted on the branch at my last look (combat analyze clean). For the record: StageFlow loses the map section
and `Stars`; SecretFlow loses `Reward`, `Site`, `whole`, `rewardOf`, `Sites`, `MapRow` (keeps a local `finite` for
`Triggered` / `Shortcuts`) and re-exports `export type Site = MapRules.Site`; `startLevel`'s node loop →
`MapRules.Startable`; `CombatCashMult(state, game, shop, combatConfig.rewards, member.cashEra)`; `RunMember.cashEra`,
`RunSummary.title` / `lines`, `RunState.depart`, `ActiveRun` / `RunTicket` on `levelId` + `difficulty`;
`StudioBridge.TeleportHint` on `levelId` + `difficulty`; `CombatRemotes` caps from `MapRules`; combat
`Main.server.luau`'s Snapshot drops `gearPower` (`Armory.SavedPower` no longer exists).

### 5.2 ui-engineer A (`src/client/**`)
`MapState` event (Types.MapState, unchanged shape) answers `RequestMapState()` (no arguments) to the asker only;
`RequestExpedition(levelId, difficulty, isPublic)` (1..32 and 1..12 bytes); refusals on `expedition` with `slotId =
levelId`, reasons `locked` / `unavailable` / `notLeader` / `busy`; `RunListEntry` = `{ hostUserId, hostName, levelId,
difficulty, wave, partySize, relation }`; Snapshot / Delta carry no `gearPower`; `RunLines.Read(value)` for
`readRunSummary`; `Types.UnlockUpcomingDef` and `LevelDifficulty.note`.

### 5.3 economy-designer: changed lines a pin or `mutate.py` entry may read
The stale check over my files (before the designer's retirements) named 15 entries, all of rules that went
(L4B-6): `l3: HeldTiers reads the melee family for both`, `l3: GearPower weighs the tiers at 1`, `l3: GearPower drops
health`, `l3fix R7: SavedPower reads the melee family for both slots`, `... ignores Ascension`, `... reads the frozen
gear`, `l3fix R7: the hub's Power reads a fresh profile`, `l3fix R7: the hub's Delta drops the Power`, `l3fix R7: the
hub's Power reads the frozen gear`, `l3fix2 F1: the hub's Power with no weapons`, `... is always 0`, `... reads no
ProvingGrounds.json`, `... with no starters`, `... is 0 once a family is found`, `l3fix2 F1: EconomyService reads the
frozen gear by key`; and the run_harness pins `hubPower` (body) with `hubArmory`, `hubProving`, `hubWeapons`,
`hubStarters`, `hubPowerSent`, `hubPowerExits`. Other text I changed (file, old → new):
- `src/shared/Combat.luau` CombatCashMult's return: `return Economy.LegacyMult(state.legacy, gameConfig)\n\t\t*
  Economy.PerkIncomeMult(shopConfig, state.legacyShop)\nend` → the same two lines plus `\t\t* Combat.EraCashMult(rewards,
  era)\n` before `end` (your CASH_TAIL already reads it).
- `src/shared/Combat.luau`: `type CombatOwner = { era: number, rebirthCount: number, combat: CombatProfile }` →
  `type CombatOwner = { era: number, combat: CombatProfile }`; `type CombatRules = { coop: CombatCoopConfig, overdrive:
  CombatOverdriveConfig }` → `type CombatRules = { coop: CombatCoopConfig }`.
- `src/shared/Unlocks.luau` comment: `-- Armory.HeldFamily, which Armory.SavedPower reads too. variants keeps the saved
  styles whose family` (and the two lines after) → `-- Armory.HeldFamily. variants keeps the saved styles whose family
  and key both exist, so an` / `-- unknown style falls back to the family's default. Fresh tables: the profile's own are
  never` / `-- handed out.`
- `src/shared/Armory.luau` header (lines 3-11) and the HeldFamily comment rewrapped; `src/server/Services/
  EconomyService.luau` Delta comment `-- Whole profile by contract (C0), deep-copied with every field (R7), and the
  Power\n\t\t\t-- readout alongside it so the two can never disagree on the client.` → `-- Whole profile by contract
  (C0), deep-copied with every field (R7).` (the `hubCopy` pin's line `delta.combat = ProfileCopy.Combat(state.combat)`
  is unchanged).

### 5.4 economy-designer: proposed checks
- **The stamp (M11's relay)**: already added by the designer (`stampThenBridge`, `stampOnce`, `okInHandOff`,
  `departHandsOff`); my original proposal, for comparison, on `src/server/Services/ExpeditionService.luau`:
  body `handOff` = `(?ms)^local function handOff\(.*?^end$` holds `"\t\t\tstampDeparture(state)\n"` once, and its index is
  below that of `"\tif StudioBridge.IsActive() then\n"`; the body holds `sendResult(member, departure.action,
  departure.slotId, true, nil)` twice and the whole file twice (no ok answer outside handOff); body `Depart` =
  `(?ms)^function ExpeditionService\.Depart\(.*?^end$` holds `handOff(keepPartyMembers(player, members), {` once;
  body `Join` = `(?ms)^function ExpeditionService\.Join\(.*?^end$` holds `handOff({ player }, {` once. Mutants: drop
  the stamp line; move it under the bridge branch; Depart without handOff.
- **Mutations for my modules**, 36 proven entries (label, file, old, new) in
  `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\259ecf10-ad47-49f7-9d11-55e5c7db6b5a\scratchpad\l4-w3-luauA\mutants_a.py`;
  take the ones your `l4w3` MapRules / cash entries do not already cover. `mutate.py` has **no RunLines entry** yet
  (`RUN_LINES` is only in FILES): the 17 `l4w3 RunLines:` entries there are proven.
- **The Python mirror of EraCashMult** is in `relay-a.md` §3 (an empty list must read 1 explicitly in Python).

### 5.5 Lead
No remote or project change beyond the contract (`RequestMapState`, `MapState` are §2.2's).

## 6. Note on a scratch run

At about 13:06 one filtered `mutate.py` of mine started with the default root `mutant/` and was stopped by its timeout
during its baseline; no running mutate process used `mutant/` (all have named roots), and I removed the leftover
folder. Every later run of mine used `mutant_luauA_<k>` / `bundle_luauA_<k>.luau`.
