# L4 W3 fix round report: luau-engineer A (shared code and the hub server)

Rulings: `docs/prompts/l4-w3-fix-round.md` F7, F8, F9, F10, F4 support, F13 support. Signatures first in
`docs/prompts/l4-w3-reports/relay-a2.md` (written before the code; unchanged since). Nothing committed.

## 1. What changed

- **F7, `src/shared/RunLines.luau`:** new pure `RunLines.ReadSummary(value: any): Types.RunSummary?`, the one reader of a
  whole run card. `title` a string of 1 to 48 bytes; `wavesCleared`, `kills` (and `bestWave` when present) counts: finite,
  >= 0, whole; `cash`, `valor`, `seconds` (and `mentorValor`, `damageShare` when present) totals: finite, >= 0;
  `materials` a table of at most 16 entries, each key a string of 1 to 48 bytes, each amount a total; `lines` through
  `RunLines.Read`. Any failure answers nil (the whole card dropped). An ABSENT optional field takes its default
  (`bestWave` = `wavesCleared`, `mentorValor` / `damageShare` 0, `died` false, `lines` `{}`); a present and malformed one
  drops the card. The answer is a fresh table with every field filled.
- **F7, `src/server/Services/StudioBridge.luau`:** its own `readSummary` and `numberOr` are gone; `readSummaries` calls
  `RunLines.ReadSummary(entry)`. ui A re-points `UIController.readRunSummary` to the same function.
- **F8, `tools/crowd_harness/tests_l4w3.luau`:** Read's bad lines are now one check each, both halves of every field rule:
  kind (not one of the seven, not a string), id over 48, name not a string and over 48, material not a string and over 48,
  count negative and +inf, cash NaN and negative, materials +inf and negative, valor not a number and negative, id missing;
  plus texts of exactly 48 bytes kept. Slice 4 s2: the shipped-upcoming check now also asserts `#upcoming >= 1`.
- **F9, `src/shared/MapRules.luau`:** new `MapRules.SecretRows(built, sitesOf, opened)`; `ExpeditionService.SendMap`
  calls it (`MapRules.SecretRows(built, sitesOf, state.combat.secrets)`), its inline loop is gone. The cache and pcall stay
  in each caller's `sitesOf` (they read Catalog). luau B re-points `WaveService.secretRows` (relay-a2.md §2).
- **F13 support, `src/shared/MapRules.luau`:** `MapRules.FirstPick(difficulties, state)`, moved verbatim from
  `MapScreen.FirstPick` (same body, `typeof` kept). ui A deletes the MapScreen copy and re-points `HubMap`; ui B
  re-points `CombatUIController`.
- **F4 support:** none needed. `DataService.IsMockMode()` already exists (`DataService.luau:329-334`, read by four callers);
  relay-a2.md §4 explains why it is exact wherever P can act (no profile loads while ProfileStore is `NotReady`). B has
  adopted it (`RunCredit.PayLeverRefusal(mock, admitted)`).
- **F10, stale comments:** `Types.luau` ActionResult (`locked` = the Ascension cap; a new `L4 W3 "expedition"` line beside
  the L1 `startLevel` one: locked = `MapRules.Startable`, not open for the hub party leader), the C0 header (no
  `Missions/*.json`), `CombatProfile` (`highestEra` is a saved record that gates nothing since W3); `Catalog.luau:27` (the
  map's Depart answers `unavailable`, no tiles); `ExpeditionService` ticket comment (a missing Studio ticket costs the run
  its run-list entry and the auto-start; the dungeon's own `Startable` still decides what is played).
- **New cases in `tests_l4w3.luau`:**
  - group `secret rows` (7);
  - group `first pick` (10, two of them string star lists);
  - group `summary` (57):
    - a sound card, with fresh copies;
    - a read card reads again unchanged (the server's read, then the client's);
    - defaults when a field is absent;
    - a 48-byte title is kept;
    - a bad line costs one row;
    - 16 materials are kept;
    - 36 dropped cards, one per rule and half;
    - 7 cards each missing a required field;
    - RunCredit's empty and credited cards pass;
  - the 16 per-line Read checks;
  - the shipped titles: every level name and the map's name fit 1 to 48 bytes, so no shipped card is ever dropped;
  - `#upcoming >= 1`.

## 2. Gates

- `stylua --check` and `selene` on my six Luau files: clean (one selene shadowing warning in my first draft, `amount`, fixed
  by renaming the loop variable to `quantity`).
- `luau-lsp analyze` with both sourcemaps (regenerated into my scratch folder at the end of the round): hub
  `src/client src/server src/shared` exit 0, combat `src/combat src/shared` exit 0. Mid-round the combat side was red
  only in luau B's in-flight `WaveService.luau`; nothing ever in `src/shared`.
- `py tools/check_compile.py`: PASS, 188 files.
- Harness on the live tree:
  - First run: `HARNESS: PASS (5,081 checks)`.
  - Mid-round it read red only in B's and the designer's in-flight cases (`credit: ...`, `note: ...`, the `depart*` pins),
    none of mine.
  - Latest, with every owner's work so far: `HARNESS: PASS (5,402 checks)`, 0 failing.
- On `HEAD` plus my files alone: `HARNESS: PASS (5,084 checks)`.
- **Each fix's cases shown failing without the fix** (`scratchpad\l4-w3-fixA\probe.py`, a root of `git archive HEAD` plus
  my six files and my test file, the root's own harness with its own bundle name, so the other owners' in-flight edits stay
  out): see §3.
- Filtered `mutate.py`: see §3.

## 3. Mutation proof

**Each fix's new cases shown failing without the fix.** The runner is `scratchpad\l4-w3-fixA\probe.py` and the probes are
`probes_a.py`. The root is `git archive HEAD` with my six source files and my test file copied over. The root runs its own
harness copy under its own bundle name, so the other owners' in-flight edits stay out. Baseline:
`HARNESS: PASS (5,081 checks)`; with the later cases it is 5,084.

| Fix | Probes | Caught | Before this round |
|---|---|---|---|
| F7 `ReadSummary` | 31: every rule and half (title type, empty, cap; counts whole; totals finite and signed; each required field; each optional field present-but-bad; the materials table, cap, key type, empty key, key cap, amount; lines unread; the three defaults; `died` truthy; materials aliased; not a table) | 31 / 31 | the function did not exist (the old readers had none of these rules) |
| F8 `Read`'s halves | 6: exactly the reviewer's m2 probes (materials, valor and cash sign; name and material cap; count finite) | 6 / 6 | **0 / 6** on HEAD's `tests_l4w3.luau` (`probes_old_f8.txt`, every one `HARNESS: PASS (4,994)`): the finding reproduced |
| F9 `SecretRows` | 4: an empty row for a chestless level, opened ignored, another level's opened chests, no rows | 4 / 4 | new function |
| F13 `FirstPick` | 7: the reviewer's p3 (`#node.stars == 0` → `> 0`), an open flag that is not `true`, the last starred node as fallback, a cleared difficulty picked, all cleared reads no pick, the star-list type check dropped, no open node reads the first | 7 / 7 | new in `src/shared` (MapScreen's copy had no case at all) |

The first full run caught 47 of 48. The miss was "FirstPick: star list unchecked": my "skipped" case put a starless good
node after the broken one, so the broken node never won. Two cases close it. In the first, a `""` star list must not read
as starless. In the second, a `"none"` star list must not become the fallback. The F13 set re-ran 7 / 7.

The hub call lines (Depart's `Startable` arguments and verdict, SendMap's stars and `SecretRows`, the bridge's
`ReadSummary`, `ReadArrival`'s caps, RequestExpedition's validator) cannot run in the harness. They are the designer's text
pins (§5.4); the designer has already added them, with STUDIO_BRIDGE and HUB_REMOTES in `mutate.py`.

**Filtered `mutate.py` on my files:**
- **The live worktree, with the designer's entries as they stand:**
  - Filter: `files:RunLines.luau,MapRules.luau,ExpeditionService.luau,StudioBridge.luau,HubRemotes.luau`.
  - The 103 matching entries break down as RunLines 54, MapRules 36, ExpeditionService 9, StudioBridge 3, HubRemotes 1.
  - Run in four slices (`0:2199`, `2199:2230`, `2230:2256`, `2256:2282`), each with its own `MUTATE_ROOT=mutant_fixA_<k>`
    and `HARNESS_BUNDLE=bundle_fixA_<k>.luau`.
  - Every baseline: `HARNESS: PASS (5,402 checks)`.
  - Result: **103 run, 0 not caught** (25 + 26 + 26 + 26), none stale. This includes the designer's copies of my 48 probes,
    the nine hub entries of §5.4 and the M11 stamp entries.
- **The committed entries on `HEAD` plus my files** (that root's own `mutate.py`, root `mutant_fixA`): baseline
  `HARNESS: PASS (5,082)`, **45 run, 0 not caught**. My edits left every committed entry on these files live and caught.
- Logs: `scratchpad\l4-w3-fixA\mutate_live_{1,2,3,4}.txt`, `mutate_mine.txt`. My mutant roots and bundle files were removed
  (mutate.py removes its roots; I deleted the five `bundle_fixA*.luau`).

## 4. Deviations, and why

1. **`bestWave`'s default is `wavesCleared`**, the hub client's old fallback; the bridge's old default was 0. Only a card
   without `bestWave` sees it, and every combat build since C1 sends one (a card old enough to omit it also has no `title`
   and reads as none), so nothing changes in practice; the card's documented fallback wins.
2. **A present but malformed optional field drops the card**, where the old readers took the default. The ruling's "any
   failure → nil"; only absence is an older build.
3. **`materials` is capped at 16 entries** (RunLines.MAX), each key 1 to 48 bytes, and any bad entry drops the card. The
   ruling names finite >= 0 amounts; the cap and the key rule answer the brief's "oversized" (four era materials today).
4. **The pcall and cache stay out of `SecretRows`** (each caller's `sitesOf` keeps them), as the reviewer's s2 drew it:
   MapRules stays pure and the two callers' warns keep naming their service.
5. **No `DataService.IsMock`**: the reader exists (`IsMockMode`).

## 5. For the other owners

### 5.1 luau B (`src/combat/server/**`)
- `WaveService.secretRows` → `return MapRules.SecretRows(built, sitesOf, if profile ~= nil then profile.combat.secrets else nil)`
  (relay-a2.md §2); keep `sitesOf` and its cache.
- F4: `DataService.IsMockMode()` (already adopted).
- `ReturnService.buildSummary`'s zero card carries `title = ""` when `Config/Expeditions` is missing; `ReadSummary` drops a
  card with an empty title, so that (zeroed, never-admitted) card is not shown in the hub. Harmless; if you want it shown,
  give it `ArenaService`'s `DEFAULT_SESSION_NAME` fallback. Your call.

### 5.2 ui A (`src/client/**`)
- `readRunSummary(payload)` → `RunLines.ReadSummary(payload)` (the answer has every field, including `mentorValor` and
  `damageShare`; `bestWave` defaults to `wavesCleared` as yours did).
- `MapScreen.FirstPick` → `MapRules.FirstPick` (`ReplicatedStorage.Shared.MapRules`, both places).

### 5.3 ui B (`src/combat/client/**`)
- `CombatUIController.luau:1558` → `MapRules.FirstPick(expeditions.difficulties, state)`.

### 5.4 The designer: pins and `mutate.py` entries

Every text below was checked to occur exactly as stated on the worktree (`scratchpad\l4-w3-fixA\pins_check.py`, 23 of
23 ok). Written in `run_harness.py`'s own form, `name: (file, body, text)`, with `\t` for a tab and `\n` for a newline.
**`StudioBridge.luau` and `HubRemotes.luau` are in neither `mutate.py` FILES nor any pin today: add both to FILES, or a pin
on them reads a missing file in every mutant root.** No line here can run in the harness (the hub services need `game`):
these are text pins, and the pins catch the mutants.

New bodies (`hubDepart` already exists):
- `hubSendMap`: `(HUB_EXPEDITION, r"(?ms)^function ExpeditionService\.SendMap\(.*?^end$")`
- `bridgeArrival`: `("src/server/Services/StudioBridge.luau", r"(?ms)^function StudioBridge\.ReadArrival\(.*?^end$")`
- `bridgeSummaries`: `("src/server/Services/StudioBridge.luau", r"(?ms)^local function readSummaries\(.*?^end$")`

The seven hub probes of `1-hub.md` m1, as pins (count 1 each unless said):
1. `departStars` (hubDepart): `"\tlocal verdict = MapRules.Startable(\n\t\tmap,\n\t\tMapRules.Built(Catalog.GetLevelIds()),\n\t\tUnlocks.StarsOf(state.combat),\n\t\tlevelId,\n\t\tdifficulty,\n"`
   (these are the leader's own stars: Depart only gets this far past `PartyService.IsLeader(player)`, so `state` is the leader's).
2. `departVerdict` (hubDepart): `"\t\tif file ~= nil then file.difficulties else nil\n\t)\n\tif verdict ~= \"ok\" then\n"` (the level
   file's difficulties and the verdict branch, together).
3. `departReason` (hubDepart): `"\t\t\tif verdict == \"locked\" then \"locked\" else \"unavailable\"\n"`.
4. `sendMapLeader` (hubSendMap): `"\t\t\tleaderStars = Unlocks.StarsOf(leaderState.combat)\n"`; `sendMapSolo` (hubSendMap):
   `"\t\tleaderStars = Unlocks.StarsOf(state.combat)\n"`; `sendMapArgs` (hubSendMap):
   `"\t\tMapRules.MapState(\n\t\t\tmap,\n\t\t\tbuilt,\n\t\t\tleaderStars,\n\t\t\tUnlocks.StarsOf(state.combat),\n\t\t\tleaderUserId,\n\t\t\tMapRules.SecretRows(built, sitesOf, state.combat.secrets)\n\t\t)\n"`
   (F9's call is the last argument).
5. `bridgeReads` (bridgeSummaries): `"\t\t\tlocal summary = RunLines.ReadSummary(entry)\n"`; `bridgeNoOwnReader` (the whole
   StudioBridge file): `"local function readSummary("` **0 times**. The reviewer's probe 5 (`RunLines.Read(raw.lines)` →
   `raw.lines`) now lives in `RunLines.ReadSummary`, and my cases catch it (§3, "lines unread").
6. `arrivalCaps` (bridgeArrival): `"\t\tor record.levelId == \"\"\n\t\tor #record.levelId > MapRules.MAX_LEVEL_ID_LENGTH\n\t\tor typeof(record.difficulty) ~= \"string\"\n\t\tor #record.difficulty > MapRules.MAX_DIFFICULTY_LENGTH\n"`.
7. `expeditionArgs` (the whole HubRemotes file): `"\t\t\t\treturn args.n == 3\n\t\t\t\t\tand isShortName(args[1], MapRules.MAX_LEVEL_ID_LENGTH)\n\t\t\t\t\tand isShortName(args[2], MapRules.MAX_DIFFICULTY_LENGTH)\n\t\t\t\t\tand typeof(args[3]) == \"boolean\"\n"`;
   `shortName` (the whole HubRemotes file): `"\treturn typeof(value) == \"string\" and #(value :: string) > 0 and #(value :: string) <= maxLength\n"`.

`mutate.py` entries for them. Each is (label, file, old → new), and each `old` occurs once in its file:
- `l4w3fix hub: Depart tickets an unavailable difficulty`, HUB_EXPEDITION, `"\tif verdict ~= \"ok\" then\n\t\tsendResult("` → `"\tif verdict == \"locked\" then\n\t\tsendResult("`
- `l4w3fix hub: Depart reads no stars`, HUB_EXPEDITION, `"\t\tUnlocks.StarsOf(state.combat),\n\t\tlevelId,\n\t\tdifficulty,\n"` → `"\t\t{},\n\t\tlevelId,\n\t\tdifficulty,\n"`
- `l4w3fix hub: Depart passes every difficulty`, HUB_EXPEDITION, `"\t\tif file ~= nil then file.difficulties else nil\n\t)\n"` → `"\t\tif file ~= nil then { normal = {}, hard = {}, brutal = {} } else nil\n\t)\n"`
- `l4w3fix hub: SendMap opens nodes by the player's own stars`, HUB_EXPEDITION, `"\t\t\tleaderStars = Unlocks.StarsOf(leaderState.combat)\n"` → `"\t\t\tleaderStars = Unlocks.StarsOf(state.combat)\n"`
- `l4w3fix hub: the bridge forwards a card unread`, StudioBridge, `"\t\t\tlocal summary = RunLines.ReadSummary(entry)\n"` → `"\t\t\tlocal summary = entry\n"`
- `l4w3fix hub: ReadArrival drops the level id cap`, StudioBridge, `"\t\tor #record.levelId > MapRules.MAX_LEVEL_ID_LENGTH\n"` → `""`
- `l4w3fix hub: ReadArrival drops the difficulty cap`, StudioBridge, `"\t\tor #record.difficulty > MapRules.MAX_DIFFICULTY_LENGTH\n"` → `""`
- `l4w3fix hub: RequestExpedition's difficulty uncapped`, HubRemotes, `"\t\t\t\t\tand isShortName(args[2], MapRules.MAX_DIFFICULTY_LENGTH)\n"` → `"\t\t\t\t\tand typeof(args[2]) == \"string\"\n"`
- `l4w3fix F9: SendMap sends no secret rows`, HUB_EXPEDITION, `"MapRules.SecretRows(built, sitesOf, state.combat.secrets)"` → `"MapRules.SecretRows(built, sitesOf, nil)"`

The pure rules F7, F8, F9 and F13 change, for `mutate.py` (RUN_LINES and MAP_RULES are already in FILES):
- The entries of §3 are all in
  `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\259ecf10-ad47-49f7-9d11-55e5c7db6b5a\scratchpad\l4-w3-fixA\probes_a.py`,
  label for label.
- The file holds the lists `F7`, `F8`, `F9` and `F13`, each of `(label, [(file, old, new)])` with one edit apiece.
- The file uses `quantity` where my first snapshot had `amount`; that matches the source now.
- The harness catches every one (§3). The six F8 entries are exactly the reviewer's m2 probes. Prefix the labels
  `l4w3fix` as you like.

Text that F7 to F10 changed, which a pin or entry might read. By grep of `run_harness.py`, `mutate.py` and
`mirror_mutants.py`, none does today.
- StudioBridge: `numberOr` and `readSummary` are gone.
- ExpeditionService:
  - SendMap's `local opened = state.combat.secrets` and its row loop are gone.
  - The `sitesOf` comment and the ticket comment were rewritten.
- `Types.luau`: four comments. `Catalog.luau`: one comment.
- `RunLines.luau`: the header comment names ReadSummary, and the new locals `total` and `count` sit after `Read`. `Read`
  itself is unchanged.
- `MapRules.luau`: `FirstPick` sits after `Startable` and `SecretRows` at the end. Nothing else moved.

From the other owners (theirs to report; listed so the set is complete):
- ui A: `readRunSummary` → `RunLines.ReadSummary`, and `HubMap`'s `MapRules.FirstPick`.
- ui B: `CombatUIController`'s `MapRules.FirstPick`.
- luau B: `WaveService.secretRows` → `MapRules.SecretRows(built, sitesOf, ...)`.

### 5.5 Lead
No remote, config key or project-file change. M11: my edits to `Types.luau` (four comments) and `Catalog.luau` (one
comment) are comment-only; `ExpeditionService`, `StudioBridge`, `RunLines`, `MapRules` are not M11 files.
