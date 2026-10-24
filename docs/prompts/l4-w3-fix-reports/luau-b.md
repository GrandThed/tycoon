# L4 W3 fix round — luau-engineer B (combat place server)

Rulings: `docs/prompts/l4-w3-fix-round.md` F1-F6 and the F9 re-pointing. Findings: `docs/prompts/l4-w3-review/2-combat.md`,
`4-data.md` m2. Relay adopted: `docs/prompts/l4-w3-reports/relay-a2.md` (`MapRules.SecretRows`; F4 needs no new
DataService function, `DataService.IsMockMode()` exists). Nothing is committed or staged.

**For the designer, first:** paste two files, as their headers say.
- `docs/prompts/l4-w3-fix-reports/luau-b-pins.py` goes into `run_harness.py`, right after the `L4W3B_ORDER` dict.
  - It re-aims 6 pins: 5 lines, including `resetOpened` → "Reset keeps it" (F1), and 1 order pair.
  - It adds 62 pins and 3 order pairs.
  - The expected counts are already in `tests_l4w3_run.luau`. Until the paste, the worktree harness fails on those pins
    only.
- `docs/prompts/l4-w3-fix-reports/luau-b-mutants.py` goes into `mutate.py`, before `sys.path.insert(0, str(here))`.
  - It re-aims the 2 stale entries.
  - It adds 59 mutants.

## Files

| File | What |
|---|---|
| `src/combat/server/Services/StageFlow.luau` | F1: `DepartBook`, `DepartAdmit`, `DepartForget`, `DepartLever`. F2: `DepartMember`, `DepartLate`. s3: `DepartLive`. F6: `Notes` replaces the local `noteProblems`, and Validate no longer names a note. |
| `src/combat/server/Services/WaveService.luau` | F1: `openDepart`, `FakeDepart` and `Reset` go through the book. F2: `lateAtZero`, and `startLevel(..., late?)`. s2: the start at zero runs in a pcall. s3: the early return. F4: `NextCashEra` refuses. F6: `readLevel` warns about a dropped note once per server. F9: `secretRows` uses `MapRules.SecretRows`. s1: a comment. |
| `src/combat/server/Services/RunCredit.luau` | F3: a kill's line counts kills. F4: `PayLeverRefusal`. |
| `src/combat/server/Services/DebugService.luau` | F4: the P notice "P needs Studio API access off", and the corrected header comment. |
| `tools/crowd_harness/tests_l4w3_run.luau` | New groups: `server` (F1), `live` (s3), `late` (F2), `kills` (F3), `payLever` (F4). `note` is rewritten (F6) and `credit` re-counted (F3). New copy `L4W3R.starting`, which is startLevel's lines. PINS and ORDER updated. |
| `docs/prompts/l4-w3-fix-reports/luau-b-pins.py`, `luau-b-mutants.py` | Paste-ready blocks for the designer. |

## Contracts implemented (signatures)

```lua
-- StageFlow (pure)
export type DepartBook = { depart: Depart?, departOpened: boolean }            -- WaveService's boot is one
export type DepartMember = { userId: number, expected: boolean, body: boolean }
StageFlow.DepartAdmit(book, levelId, difficulty, verified, proving?, since): ()  -- opens only at the server's first admit
StageFlow.DepartForget(book): ()                 -- the session's end: depart = nil, departOpened kept (F1)
StageFlow.DepartLever(book, levelId, difficulty, now): boolean                 -- R; counts as opened
StageFlow.DepartLive(depart?): boolean           -- waiting or counting (s3)
StageFlow.DepartLate(members: { DepartMember }): { [number]: boolean }        -- F2
StageFlow.Notes(level): ({ [string]: string }, { string })   -- kept notes by difficulty, one warn line per dropped (F6)
-- RunCredit (pure)
RunCredit.PayLeverRefusal(mock: boolean, admitted: boolean): string?   -- "realStore" | "nobody" | nil (F4)
-- WaveService
WaveService.NextCashEra(): (number, number, string?)   -- third value: why it did not step ("studio", "realStore", "nobody")
```

## What each ruling does

- **F1 (the Major).** A server opens its auto-start once.
  - `boot.departOpened` is set at the server's first admit (`DepartAdmit`) or by R (`DepartLever`).
  - `Reset` calls `DepartForget(boot)`, which clears `boot.depart` and keeps `departOpened`.
  - So a failed trip home that rejoins with the same verified ticket gets no `waiting`, no `counting` and no `picked`.
  - R still works after that.
  - WaveService no longer writes `boot.depart` or `boot.departOpened` anywhere (pins `departWrites` 0, `openedWrites` 0,
    `resetOpened` 0). Only a new server boot starts with `departOpened` unset (`bootOpened`).
- **F2: I chose the exclude path. The leader's own Start is unchanged.**
  - At zero, `lateAtZero()` collects each member's facts (in the ticket's expected list, standing in a body).
    `StageFlow.DepartLate` returns the late set: members who are not expected and have no body.
  - `startLevel(player, levelId, difficulty, late)` skips the body check for them. It leaves them `waiting = true`, in
    the lobby camp, and does not place them.
  - When their body spawns, `ArenaService`'s placer puts them where any arrival goes (ruling 18): into the level outside
    a fight, the lobby camp during one. The next boundary releases them.
  - The leader's own `OnStartLevel` passes no `late` (pin `startOwnNoLate`), so it is the same code path as before.
  - Expected members still need their bodies: an expected member without one still refuses (busy, then picked).
  - **One edge I ruled:** when every member present would be late, nobody is. A level started with no fighter makes no
    sense, so the start's own body rule answers (busy, then picked). This needs every expected member to leave during
    the 5 s countdown while a stranger with no body is present.
- **F3.** `RunCredit.Credit` gives a `raiders` or `boss` line the credit's `kills` as its count; every other kind counts 1.
  - In a party, "Raiders ×n" now equals the card's kill count. A share without the killing blow still adds its pay to
    the line, with count 0.
  - A killing blow with no share (`credit`'s `killCounted` line) still counts 1.
  - Solo cards are unchanged. The client already shows a count of 0 as plain "Raiders" (`TallyRules` :136).
- **F4.** `NextCashEra` asks `RunCredit.PayLeverRefusal(DataService.IsMockMode(), leader ~= nil)`.
  - With the real store (API access on) it is refused, and DebugService shows the notice "P needs Studio API access off".
  - With nobody admitted it is refused silently.
  - Why the admitted check: `IsMockMode()` also reads true while ProfileStore is still `NotReady`. An override set in
    that window would outlive it and pay into real profiles that load later.
  - Any admitted member has a loaded profile. ProfileStore's `StartSessionAsync` waits for the store to settle, so an
    admitted member means the answer is final.
  - DebugService's comment is corrected. The lead fixes contract §13.7.
- **F5.**
  - s1: the `onCrowdKilled` comment is fixed.
  - s2: the start at zero runs inside `pcall(function() refusal = startLevel(...) end)`. A throw becomes refusal
    `"unavailable"`: the level is picked, it is the same single warn (now naming the error), and the leader gets the
    same toast as for any refusal.
  - s3: `tickDepart` returns at once unless the depart is `waiting` or `counting` (`StageFlow.DepartLive`). The tick in
    which it turns picked still broadcasts its beat.
- **F6.** `StageFlow.Validate` no longer names a note.
  - `StageFlow.Notes(level)` returns the notes kept and one warn line per note dropped (not a string, empty, or over 24
    bytes).
  - `readLevel` warns about the dropped notes once per level per server (`boot.warnedNotes`), and its verdict does not
    read them. The level stays valid.
  - The designer's `check_stage_mirror` F6 cases pass against it: "F6: a bad note is dropped, the level kept", 8 compared.
- **F9.** `WaveService.secretRows` returns `MapRules.SecretRows(built, sitesOf, profile.combat.secrets or nil)`, exactly
  as relay-a2 §2 gives it. WaveService keeps no copy of the row loop (pin `secretRowCopies` 0).

## Gates

- **stylua / selene** on `src/combat/server` and `tests_l4w3_run.luau`: clean (selene 0 errors, 0 warnings).
- **luau-lsp** (combat sourcemap, `src/combat/server src/shared`): 0 diagnostics.
- **check_compile.py:** PASS.
- **check_stage_mirror.py** (worktree, read-only): PASS, including the designer's F6 family.
- **Harness, worktree before the designer's paste:** `HARNESS: FAIL (67 of 5,373)`. All 67 were `pins:` checks for keys
  not yet pasted. No case failed.
- **Harness with my pins pasted** (a scratch copy of the worktree, `scratchpad\l4-w3-fixB\copy`, removed after the mutate run): `HARNESS: PASS (5,400
  checks)`.
- **Each new case fails without its fix** (in the copy, one fix undone at a time, `scratchpad\l4-w3-fixB\nofix.txt`):

| Fix undone | Harness | Failing checks |
|---|---|---|
| F1 (`DepartForget` clears `departOpened`) | FAIL 5 | the 5 `server:` rejoin checks ("a rejoin with the same verified ticket opens nothing: no waiting, no counting (F1)", …) |
| F1 (Reset writes `boot.departOpened = false`, as before) | FAIL 2 | pins `resetOpened` 1≠0, `openedWrites` 1≠0 |
| F2 (nobody late, startLevel checks every body) | FAIL 4 | 3 `late:` checks ("the auto-start goes ahead for the departed party (F2: never refused for the stranger)", …) and pin `startBodies` |
| F3 (every credit counts 1) | FAIL 4 | 2 `credit:` and 2 `kills:` ("in a party Raiders xn is the card's own kills …") |
| F4 (P never refused) | FAIL 5 | 3 `P:` checks, pin `eraRefusal`, order `eraRefusalThenStep` |
| s2 (no pcall) | FAIL 2 | pins `departPcall`, `departStartLevel` |
| s3 (no early return) | FAIL 5 | 3 `live:` checks, pin `departLive`, order `departLiveThenStep` |
| F6 (Validate refuses a bad note) | FAIL 5 | the 5 `note: … never refuses the level (F6 …)` checks |

- **Harness, worktree, after the designer pasted both files** (18:00): `HARNESS: PASS (5,400 checks)`, with my own bundle
  name.
- **Stale check** (`mutate.py` run up to `MUTATE_COUNT`, then every entry's count): 0 stale out of 629 entries on my files.
- **mutate.py, filtered to my files: `MUTATIONS: 539 run, 0 not caught (6 shards)`.**
  - Filter:
    `files:combat/server/Services/WaveService.luau,StageFlow.luau,RunCredit.luau,DebugService.luau,ArenaService.luau,combat/server/Main.server.luau,RunRegistry.luau,ReturnService.luau,SecretFlow.luau,CombatRemotes.luau`.
  - It ran through `mutate_shards.py --shards=6` in the scratch copy, which holds my pinned and mutant blocks; its roots
    and logs were the copy's own, not the worktree's.
  - Per shard: 74 / 120 / 76 / 50 / 85 / 134, every shard 0 not caught, each baseline `HARNESS: PASS (5,400 checks)`.
  - The 539 include my 59 new `l4w3b-fix` entries and the 2 re-aimed ones (61 lines in the logs).
  - These 539 entries equal the worktree's own `mutate.py` entries on those files, compared entry by entry after the
    designer's paste. My source files and test file in the copy are byte-identical to the worktree's.
  - It took 16:31 to 18:40: the machine was shared, about 4 mutants a minute.
  - Logs: `scratchpad\l4-w3-fixB\mutant_logs\shard_*.log`, summary `scratchpad\l4-w3-fixB\mutate_files.txt`.

## For the designer

1. **Paste the two files** (top of this report). `RUN_REGISTRY` is already in `mutate.py` FILES; `luau-b-pins.py`
   defines its own `RUN_REGISTRY` constant for `run_harness.py`.
2. **The 19 surviving condition probes (`2-combat.md` m2): where each line is now.** Every row is a pin key in
   `luau-b-pins.py` and a `l4w3b-fix probe N` mutant in `luau-b-mutants.py`.

| # | File | Function | Exact line(s) (tabs as `\t`) | Pin key(s) |
|---|---|---|---|---|
| 1, 2 | StageFlow | `DepartAdmit` | `\tif book.departOpened then` / `\tbook.departOpened = true` (moved here by F1; real cases in group `server`) | (cases) + `openDepart`, `openedWrites` |
| 3 | WaveService | `tickDepart` | `\t\tif refusal ~= nil then` | `departRefusedIf` |
| 4 | WaveService | `tickDepart` | `\t\tlocal refusal: StartRefusal? = "notLeader"` / `\t\tif player ~= nil then` | `departNotLeader`, `departPlayerGuard` |
| 5 | WaveService | `tickDepart` | `\t\tif run.phase == "lobby" then` / `\t\t\tbroadcast()` | `departBeatLobby`, `departBeatBroadcast` |
| 6 | ArenaService | `ExpectedIn` | `\t\t\t\treturn false` | `expectedMissing` |
| 7 | ArenaService | `ExpectedIn` | `\tif not session.open or session.ticketPending then` | `expectedGuard` |
| 8 | ArenaService | `PartyIn` | `\treturn session.firstArrivalAt > 0` / `\t\tand os.clock() - session.firstArrivalAt >= config.coop.lobbyWaitSeconds` | `partyInFirst`, `partyInCap` |
| 9 | ArenaService | `FirstArrivalAt` | `\treturn session.firstArrivalAt` | `firstArrival`, `openSince` |
| 10 | WaveService | `openDepart` | `\tif since <= 0 then` / `\t\tsince = os.clock()` | `openSinceGuard`, `openSinceClock` |
| 11 | Main (combat) | `hintPair` | `\t\tor levelId == ""` (and `\t\ttypeof(levelId) ~= "string"`, `\t\tor #levelId > MapRules.MAX_LEVEL_ID_LENGTH`) | `hintEmpty`, `hintLevelType`, `hintLevelCap` |
| 12 | Main (combat) | `hintPair` | `\t\tor #difficulty > MapRules.MAX_DIFFICULTY_LENGTH` (and `\t\tor typeof(difficulty) ~= "string"`) | `hintDifficultyCap`, `hintDifficultyType` |
| 13 | RunRegistry | `readTicket` | `\t\tor typeof(entry.levelId) ~= "string"` (and the difficulty twin) | `ticketLevel`, `ticketDifficulty` |
| 14 | RunRegistry | `RunRegistry.ResolveTicket` | `\tif ticket.levelId ~= levelId or ticket.difficulty ~= difficulty then` (and `\tif ticket.privateServerId ~= expectedPrivateServerId() then`) | `resolveMatch`, `resolveServer` |
| 15 | RunRegistry | `RunRegistry.ResolveTicket` (mock) | `\t\t\tlevelId = levelId,` / `\t\t\tdifficulty = difficulty,` | `mockLevel`, `mockDifficulty` |
| 16 | WaveService | `WaveService.OnStartLevel` | `\t\tbroadcast()` | `askedBroadcast` |
| 17 | WaveService | `pushRunFields` | `\t\tdepart = StageFlow.DepartView(boot.depart, now, phase == "lobby", lobbyWaitSeconds()),` | `pushDepart` |
| 18 | ArenaService | `ArenaService.BuildRunState` | `\t\tdepart = if phase == "lobby" then runFields.depart else nil,` | `buildDepart` |
| 19 | WaveService | `WaveService.EndRun` | `\t\tif given ~= nil then` | `endGiven` |
| 20 | WaveService | `tickDepart` | `\t\tlocal leader = ArenaService.GetMember(ArenaService.LeaderUserId())` | `departLeader` |

3. **Every line F1-F6 and F9 changed (file: old → new).**
   - **WaveService**
     - `openDepart`: the guard and write `\tif boot.departOpened then` … `\tboot.departOpened = true` are **removed**.
       `\tboot.depart = StageFlow.DepartOpen(levelId, difficulty, verified, proving, since)` →
       `\tStageFlow.DepartAdmit(boot, levelId, difficulty, verified, proving, since)`.
     - `WaveService.FakeDepart`: `local pair = …` / `boot.depart = StageFlow.DepartOpen(levelId, difficulty, true, pair, os.clock())` /
       `boot.departOpened = true` / `return boot.depart ~= nil` → `\treturn StageFlow.DepartLever(boot, levelId, difficulty, os.clock())`.
     - `WaveService.Reset`: `\tboot.depart = nil` and `\tboot.departOpened = false` → `\tStageFlow.DepartForget(boot)`.
     - `tickDepart`:
       - `\tif depart == nil then` → `\tif depart == nil or not StageFlow.DepartLive(depart) then`.
       - `\t\tlocal refusal: StartRefusal? = if player ~= nil` / `\t\t\tthen startLevel(player, depart.levelId, depart.difficulty)` /
         `\t\t\telse "notLeader"` → `\t\tlocal refusal: StartRefusal? = "notLeader"` / `\t\tlocal thrown = ""` /
         `\t\tif player ~= nil then` / `\t\t\tlocal started, problem = pcall(function()` /
         `\t\t\t\trefusal = startLevel(player, depart.levelId, depart.difficulty, lateAtZero())` / `\t\t\tend)` /
         `\t\t\tif not started then` / `\t\t\t\trefusal = "unavailable"` / ``\t\t\t\tthrown = `: {tostring(problem)}` `` / ends.
       - The warn's `({refusal})` → `({refusal}{thrown})`.
     - New local `lateAtZero` (just above `tickDepart`).
     - `startLevel`:
       - The signature is now multi-line, with `late: { [number]: boolean }?`.
       - `\tif not ArenaService.PartyIn() or not VitalsService.AllHaveBodies(members) then` → the `starting` block plus
         `\tif not ArenaService.PartyIn() or not VitalsService.AllHaveBodies(starting) then`.
       - The placement loop gains `\t\tif late ~= nil and late[other.userId] then` / `\t\t\tother.waiting = true` /
         `\t\t\tcontinue` / `\t\tend`.
     - `WaveService.NextCashEra`:
       - `): (number, number)` → `): (number, number, string?)`.
       - `\t\treturn current, Combat.EraCashMult(rewards, current)` → `…, "studio"`.
       - New `\tlocal refusal = RunCredit.PayLeverRefusal(DataService.IsMockMode(), leader ~= nil)` and its `if`.
       - `\treturn era, Combat.EraCashMult(rewards, era)` → `…, nil`.
     - `readLevel`: new `\tlocal _, dropped = StageFlow.Notes(level)` / `\tif #dropped > 0 and not boot.warnedNotes[levelId] then` /
       `\t\tboot.warnedNotes[levelId] = true` / ``\t\twarn(`[WaveService] {table.concat(dropped, "; ")}`)``.
     - `secretRows`: the row loop → `\treturn MapRules.SecretRows(` / `\t\tbuilt,` / `\t\tsitesOf,` /
       `\t\tif profile ~= nil then profile.combat.secrets else nil` / `\t)`.
     - The `boot` table gains `\twarnedNotes = {} :: { [string]: boolean },`.
     - Comments changed over `boot.depart`, `onCrowdKilled`, `secretRows`, `openDepart`, `OnAdmitted`, `tickDepart`,
       `startLevel` and `NextCashEra`. Pins blank comments, but a `mutate.py` text with a comment in it would see them.
   - **StageFlow**
     - The local `noteProblems(level, problem)` → `function StageFlow.Notes(level)`. The condition line is unchanged:
       `if note ~= nil and (type(note) ~= "string" or note == "" or #note > NOTE_MAX_LENGTH) then`, so "any length",
       "empty passes" and "one byte longer" still match.
     - `\tnoteProblems(level, problem)` is removed from Validate.
     - New: the two types and five functions above.
   - **RunCredit**
     - `\tRunLines.Add(summary.lines, key, CREDIT_COUNT, cash, material, materials, valor)` →
       `\tlocal count = if KILL_KINDS[key.kind] then kills else CREDIT_COUNT` /
       `\tRunLines.Add(summary.lines, key, count, cash, material, materials, valor)`.
     - New `local KILL_KINDS: { [string]: boolean } = { raiders = true, boss = true }` and `RunCredit.PayLeverRefusal`.
   - **DebugService**
     - `nextCashEra`: `\tlocal era, mult = WaveService.NextCashEra()` → `\tlocal era, mult, refusal = WaveService.NextCashEra()`.
     - Plus the `realStore` notice and the silent refusal.
4. **Stale `mutate.py` entries** (2, both re-aimed in `luau-b-mutants.py`):
   - `l4w3b note: never checked`: now inserts the note lines into Validate's problems.
   - `l4w3b credit: no line`: now on `count`.
   - My stale check runs the file up to `MUTATE_COUNT`. Over the 629 entries on my files (570 before, plus my 59) it finds
     0 stale.
5. The run_harness pins I re-aimed were `departStartLevel`, `departWrites` (now 0), `openDepart`, `resetDepart`,
   `resetOpened` (a regex, now 0) and the order pair `departStepThenStart`.

## For the other owners

- **ui A (optional):** `MapScreen` (`:395`) reads a difficulty's `note` straight from the level file. It drops a
  non-string or empty note but shows a 25+ byte one. F6 drops those on the server. The designer's `check_levels` keeps
  shipped data clean, so this is only a degrade question for you.
- **ui B:** nothing needed.
  - F3: a raiders line may now carry pay with count 0 (a party member who landed no killing blow). `TallyRules` :136
    already shows plain "Raiders".
  - A boss line's count is 1 for the killer and 0 for a share.
- **Lead:** contract §13.7, the P sentence (F4). No remote, no project-file change.

## What to check in Studio

1. `build\proving.rbxl`, Play: the countdown, then the level, as before.
2. P with API access off: "Pay as Boomtown (×670)" and so on. With "Enable Studio Access to API Services" on: the notice
   "P needs Studio API access off", and run cash stays at the profile's own era.
3. The bridge (§9 B): after a run, press Return in `combat.rbxl` with API access on. If the trip home fails ("unavailable"),
   you land back in the lobby with no countdown and the map not forced open.
