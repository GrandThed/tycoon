# L4 W3 review, slice 1: hub server and shared

Reviewed: `git diff dce50da..93eb8e9` on `l4-w3`, limited to `src/server/` (`Main.server.luau`, `ExpeditionService`,
`HubRemotes`, `StudioBridge`, `EconomyService`, `ArmoryService`), `src/shared/` (`MapRules` and `RunLines`, both new,
plus `Types`, `Combat`, `Catalog`, `Armory`, `Unlocks`) and `tools/crowd_harness/tests_l4w3.luau`. I read the
surrounding code where it mattered: WaveService `startLevel` / `readLevel` / `sendMapState`, PartyService, RunCredit,
ArenaService `publishNow`, and the hub client's `readRunSummary`.

Probes ran on a `git archive 93eb8e9` copy (scratch `l4-w3-rev1/tree`). Baseline: `HARNESS: PASS (4,994 checks)` in 25 s.

**Totals: 0 Critical, 0 Major, 3 Minor, 2 Suggestions.**

## Minor

### m1. The hub half of L4W3-1 sits under no gate; 7 of 7 probes pass

Files: `src/server/Services/ExpeditionService.luau:705-722`, `:882`; `src/server/Services/StudioBridge.luau:226`,
`:353-355`; `src/server/Services/HubRemotes.luau:178`.

**What is wrong.** The pure rule is well tested: `tests_l4w3` covers `Startable`'s every answer and their order, and
`mutate.py` has 8 entries on it. But nothing pins the hub's call to it.
- `run_harness.py` pins only the stamp in `hubHandOff`, `hubDepart` and `hubJoin`.
- StudioBridge, HubRemotes and SendMap are named by no pin and no `mutate.py` entry.
- `tests_l4w3.luau:6` says so itself.

Each of these edits leaves `HARNESS: PASS (4,994 checks)`:
- In Depart, `if verdict ~= "ok"` becomes `if verdict == "locked"`. A difficulty the level file lacks is then ticketed.
- In Depart, `Unlocks.StarsOf(state.combat)` becomes `{}`. A leader holding the Forest star can no longer depart to the
  Castle once it is built.
- In Depart, `file.difficulties` becomes a table that holds every difficulty.
- In SendMap, the leader's stars become the player's own. The map then opens nodes the Depart refuses.
- In readSummary, `RunLines.Read(raw.lines)` becomes `raw.lines`. A forged line list then reaches the card unchecked.
- In ReadArrival, both length caps are dropped.
- In RequestExpedition, `isShortName(args[2], …)` becomes `typeof(args[2]) == "string"`.

**Failure scenario.** A later edit, such as the M11 merge (L4W3-17/18 touch the same files), drops the leader's stars or
the verdict branch. The hub then tickets levels the dungeon refuses, or refuses levels it would start. This is the
contract's "exactly the rule, and the reverse", and every gate stays green. It is the recurring "service lines
unharnessed" gap (L2, L3, M11), now on the one rule the contract makes shared.

**Fix.** Add text pins on the `hubDepart` body with their indentation:
- `\t\tUnlocks.StarsOf(state.combat),\n\t\tlevelId,\n\t\tdifficulty,`
- `\t\tif file ~= nil then file.difficulties else nil\n\t)\n\tif verdict ~= "ok" then`

Add a pin on the SendMap body for `leaderStars = Unlocks.StarsOf(leaderState.combat)`, and file pins for StudioBridge
`lines = RunLines.Read(raw.lines),` and both cap lines, plus the HubRemotes validator lines. Then add the 7 edits above
as `mutate.py` entries.

### m2. `tests_l4w3` proves half of `RunLines.Read`'s field rules; 6 probes pass

Files: `src/shared/RunLines.luau:122-128`; `tools/crowd_harness/tests_l4w3.luau:305-319`.

**What is wrong.** The "every bad field drops its line" list has one bad value per field. So each test proves either a
field's sign or its finiteness, never both, and only `id` has its length tested. Each of these edits leaves
`HARNESS: PASS (4,994)`:
- `materials`, `valor` and `cash` lose `>= 0`, so negative amounts are kept.
- `name` and `material` lose the 48-byte cap.
- `count` loses `finite`, so `+inf` is kept.

`mutate.py`'s `l4w3 RunLines: Read …` entries cover only the halves that are tested.

**Failure scenario.** A refactor of `Read` drops the sign test on `cash`. A forged ReturnData line with
`cash = -1e15`, or a 10 KB `name`, then reaches the hub card. The brief requires "16 lines, 48 bytes, finite ≥ 0"
to be proven, and no gate turns red.

**Fix.** Add one bad line per missing half to `bad`: `materials = -1`, `valor = -1`, `cash = -1`,
`name = string.rep("n", 49)`, `material = string.rep("m", 49)`, `count = math.huge`. Add a `mutate.py` entry for each.

### m3. The hub's `readSummary` caps the lines but not the title or the totals

File: `src/server/Services/StudioBridge.luau:198-226`. The client copy, `UIController.readRunSummary:150-184`, is the
same.

**What is wrong.** `title` only has to be a string, with no length cap. The totals `cash`, `valor`, `kills`, `seconds`
and `wavesCleared` only have to be numbers, so NaN, ±inf and negative values pass. The `materials` amounts also pass any
number. Yet every line goes through `RunLines.Read`'s finite-and-≥ 0 rule and its 48-byte rule.
`Main.server.luau:46-48` says live TeleportData is client-forgeable.

**Failure scenario.** A client forges its own ReturnData with a 20 KB `title` and `cash = 0/0`. The hub validates it and
fires it, and RunTally shows a title that overflows and a "nan" cash row. The wallet roll falls back to 0 through
`math.max(0, NaN)`. The effect is self-only and display-only, because rewards already sit in the profile and the card goes
to that player only. That is why this is Minor. Still, it contradicts the brief's "a forged or oversized summary … is
dropped, never shown".

**Fix.**
- In `readSummary`, require `#raw.title <= RunLines.MAX_TEXT`; the title is a level or map name. Alternatively, clip it
  the way `RunLines` clips.
- Read the totals through a finite-and-≥ 0 helper (`RunLines` could export one), dropping the summary otherwise.
- Keep only finite amounts of at least 0 in `materials`.
- Mirror the same rules in `readRunSummary`. That copy is slice 3's, so route it.

## Suggestions

### s1. Comments the §6 deletions left stale (L4B-5)

- `src/shared/Types.luau:180-182`: "locked = the Ascension cap, or a mission era above highestEra". `expedition`'s
  `locked` now means "the node is not open for the leader" (Startable), with `slotId` = the level id. Say so beside the L1
  `startLevel` line.
- `src/shared/Types.luau:976`: "Missions/*.json mirrors"; that folder is gone.
- `src/shared/Types.luau:990-991`: "highestEra … gates mission tiles". Since W3 it is a saved record and gates nothing
  (contract §6 "must not go").
- `src/shared/Catalog.luau:27`: "the hub disables the Expedition tiles". The tiles are gone; the map's Depart answers
  `unavailable`.
- `src/server/Services/ExpeditionService.luau:775-777`: "(the combat place then unlock-checks every arrival, the C1
  rule)". That is not true since L1. Under W3, a missing ticket also costs the auto-start, because the hint alone gives
  `picked`.

### s2. SendMap copies WaveService's secret-row assembly

File: `src/server/Services/ExpeditionService.luau:644-662, 890-897`. This is `WaveService.sitesOf` and `secretRows`
(`:537-572`) line for line: one pcall, a per-level cache, `#sites > 0`, and `SecretRow` on `combat.secrets[levelId]`.
L4W3-1 moved the map rules into one module so both places cannot drift, but this half still lives twice, under two owners.
The hub copy is also ungated (m1).

**Fix.** Add `MapRules.SecretRows(built, sitesOf, opened)`, where `sitesOf` is the caller's cached reader. Have both
places call it, and test it in `tests_l4w3`.

## Checked and clean

- **Depart's rule.** `MapRules.Startable` on the leader's own profile stars (`IsLeader` first; host-gated). Same inputs
  as the dungeon's `startLevel`: `MapRules.Built(Catalog.GetLevelIds())`, `Unlocks.StarsOf` of the same saved profile,
  and the level file's `difficulties`. Both places map the same `Config/Levels` and `Expeditions.json`.
- **Where the two places can still disagree.** The dungeon runs `resolveLevel` after Startable (Validate, CampBrain
  problems, `WeaponService.IsActive`), and at the start it can answer `busy` (phase, cooldown, PartyIn, bodies). Those are
  config faults or runtime states the hub cannot see, and they degrade to `picked`. On the shipped data, hub ok ⇔ dungeon
  ok, in both directions.
- **The moved code.** MapRules matches the old code verbatim: StageFlow `:2863-2982` and SecretFlow `:62-145`, `:345-360`,
  diffed with names normalised; only comments changed.
- **Startable's order.** It judges the first node that names the level, and answers locked before unavailable. The old
  dungeon loop also judged the first node. A non-table difficulty entry is refused (luau-a's deviation 4, accepted).
- **The shape on the wire.** The ticket, the teleport data, the Handoff, the bridge hint, `WriteDeparture`, `Join` and
  `SendRunList` carry only `levelId` and `difficulty`. `asActiveRun` reads an old-shape entry (no `levelId` or
  `difficulty` string) as none. `ReadArrival` requires a non-empty levelId of at most 32 bytes and a difficulty of at most
  12. `FAKE_MISSION_ID` is gone; fake runs use `debug.provingLevel` / `provingDifficulty`.
- **Old servers after the publish.** In each direction an old shape reads as none: tickets, teleport data, registry
  entries and summaries without `title`. It degrades and never errors (publish freeze L4W3-8 / §13.8).
- **`RequestExpedition`.** `args.n == 3`, `isShortName` with the MapRules caps (empty is now refused), `public` boolean,
  bucket `prompt`. The `departing` in-flight guard is unchanged.
- **`RequestMapState`.** `args.n == 0`, bucket `calls` (10/s); `SendMap` never yields.
  - Cost per call: one `GetLevelIds` scan (cached requires), one MapState and one FireClient, to the asker only.
  - It answers nothing without a profile or without Expeditions (deviation 7, accepted).
  - The leader comes from the asker's own party (invite + accept), so the only thing it reveals is which nodes are open
    for that leader, as in the dungeon. A fake or absent leader counts no stars.
- **L4W3-17(a).** `stampDeparture` runs for every member inside `handOff`, before the bridge branch. Depart (`:785`) and
  Join (`:852`) both go through `handOff`; the only ok answers are there; a failed bridge record and `abortDeparture` hand
  the stat back as before. Pinned by `stampThenBridge` / `stampOnce` / `okInHandOff` / `departHandsOff` with 3 mutants.
- **Hub join.** `Main.server.luau`'s join coroutine is untouched. Removing `computeGearPower` adds no yield; it only drops
  a call. The two hub handlers are spawned.
- **`Combat.EraCashMult`.**
  - It returns 1 for no block, a list that is not a table, an empty list, a non-finite era, or an entry that is not a
    finite number of at least 1.
  - An era past the list takes the last entry; one under 1 takes the first.
  - It returns ×1 for Village on the shipped `[1, 670, 34000, 1400000]`.
- **`CombatCashMult`.** Legacy × Founder's × EraCashMult. Its one caller is `WaveService.credit`. The era is the caller's
  argument and is never read off the state.
- **`RunLines.Add`.**
  - It merges by kind + id in first-credit order, appends only while below 16, keeps the first name and the first
    non-empty material, and adds 0 for a non-finite or negative amount.
  - It clips id, name and material at a UTF-8 boundary. What it builds always passes `Read`.
  - Its typed callers always pass strings: zone, site and key names all fall back to ids.
- **`RunLines.Read`.** It reads indices 1..16 only, skips holes, returns fresh copies, and turns a non-list into `{}`.
- **The deletions.** `git grep` over `src` finds none of `missionId`, `MissionUnlocked`, `RecommendedPower`,
  `GetMission`, `\boverdrive\b`, `SummaryCard`, `provingStartDelay`, `gearPower`, `SetPower`, `GearPower`, `SavedPower`,
  `HeldTiers`, `MissionConfig`, `tierWeight` or `hpWeight`.
- **The "must not go" list.** `highestEra`, `TouchHighestEra` with its callers, `MissionRecord.overdriveBest`,
  `combat.missions`, `MissionCrowd*`, the run list and `RequestJoinRun` are all still there.
- **`Types`.** The shapes match `relay-a.md` §5. `RunLine` is written flat (deviation 2); `RunDepart` has no `done`;
  `LevelDifficulty.note?`; `abilities.upcoming?`.
- **`tests_l4w3`.** `upcoming` is not vacuous: the shipped Expeditions.json carries `glide`, which names the `castle`
  node. In the era and cash tests, the `raised` list makes "first entry" and "1" differ.
- **Gates.** stylua and selene are clean on the 13 slice files. `luau-lsp` is clean on both trees (sourcemaps written to
  scratch). `check_compile.py` passes: 187 files.

## Probe recipe

- Runner: `scratch/l4-w3-rev1/scripts/probe.py <tree> <luau> <probes.json>`. Each probe is
  `[label, [[file, old, new], ...]]`; the runner checks that each edit applies exactly once, runs the tree's harness, and
  restores the files. A probe takes about 25 s.
- Builders: `mkprobes1.py` makes the m1 probes and `mkprobes2.py` the m2 probes.
- Controls: two probes in `probes2.json` are caught, which shows the runner works: "Add: merge ignores count" (FAIL 6)
  and "EraCashMult: entry under 1 kept when > 0" (FAIL 1).
