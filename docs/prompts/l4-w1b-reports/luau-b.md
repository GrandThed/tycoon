# L4 W1b — luau-engineer B's report

Status: done for my files (ArenaService, WaveService, tests_l4b_run.luau). Nothing committed.

## What changed

`src/combat/server/Services/ArenaService.luau` (+68 / −235):
- Row 1: the `EnemyService` require and every call into it are gone: the `CombatArena` group stamp
  in `newPart` (parts stay Default, as they always were: the group was never registered since P5),
  and the cover, fence, floor and spawn points handed over in `buildFallbackArena` and
  `buildFromLayout`. The range's arena still builds its floor, fence, barrier, obstacles, pad and
  player spawns as before.
- Rows 8 and 9: the debug bots are gone (`BOT_USER_ID_BASE`, `DEFAULT_BOT_HP`, `applyMaxHp`,
  `placeBot`, `AddBot`, `RemoveBot`, `RespawnBot`, `BotCount`, the bot sweep in `resetSession`,
  every `.bot` test), and so are the C1 member fields: the `Admit` literal writes `userId, name,
  player, character, humanoid, waiting, incomeRate`; `memberEntry` writes no `ready`, `bot`,
  `abilityReadyIn` or `stance`. `NEUTRAL_EMPOWER` is gone. `humanIds`/`humanCount` became
  `table.clone(partyOrder)` / `#partyOrder`; `LeaderUserId` became "the host if in the roster,
  else `partyOrder[1]`, else 0" (the same answer: `partyOrder` and `party` are written together).
  `member.player` is used without a nil test (`MoveMember`'s hook, `watchCharacter`, the sends).
- Row 14: `LevelInfo.mission` is gone. Row 20: `RunState.overdrive` is no longer written.
- L4B-8: `RunFields.floorsSeq`; `BuildRunState` builds its floors with
  `RunFloors.Attach(runFields.floors, runFields.floorsSeq, runFields.floorsSeq)` (never cells) and
  writes `floorsSeq`; the new local `sendRunState(player, userId, runState)` is the one
  `FireClient(..., "RunState", ...)` in the file: `Broadcast` and `sendSummaryTo` go through it.
  It asks `Attach` with `play.cellsSent[userId]`, sends a `table.clone` of the payload carrying
  the cells when they went, and records `play.cellsSent[userId] = seq` after every send.
  `play.cellsSent[...] = nil` at `Admit` (every call, before the member lookup) and at `Remove`.
  ReturnService's leave card (its own `BuildRunState` call) keeps the seq and carries no cells, as
  the contract says.

`src/combat/server/Services/WaveService.luau` (+57 / −127):
- L4B-9: `missionRecord`, `recordBossClear` and the mission half of `countWaves` are gone;
  `countWaves(count)` writes only `stats.wavesCleared` (its `wave` argument went with the record).
- Row 14: `readLevel` calls `StageFlow.Resolve(file, combatConfig.director.runCapSeconds)`; the
  mission lookup, `Catalog.GetArenaLayout` and `LevelGeometry.FromArena` are gone; `sitesOf` and
  `lobbyKillY` no longer test `layout.arena`; `SetLevel` has no `mission`.
- Row 8: every `member.bot` / `player == nil` test is gone (humanPlayers, fightingIds, starsOf,
  sendMapState, payMentors, credit, onCrowdKilled, sendWallets, humanCounts, rescueFallen,
  moveFighters, standUpOnRoad, fallenReason, EndRun, backToLobby, advance, startLevel,
  tickSecrets, SetDownSource). The tests on `member ~= nil` (a userId that is not a member) stay.
- L4B-8: `boot.floorsSeq` (life of the server) and the local `setFloors(floors)`, the only writer
  of `run.floors` and of the seq: called at the start (`setFloors(runFloors)`), on the return to the
  lobby and in `Reset` (`setFloors({})`). `pushRunFields` hands `floorsSeq = boot.floorsSeq`; the
  floors and their seq always travel in the same `SetRunFields` call, and nothing yields between
  `setFloors` and the next push.

`tools/crowd_harness/tests_l4b_run.luau` (new, 37 checks, needs `RunFloors` in `SOURCES`): Attach
(cells on a member's first send of a set, per member, never after, again after the note is cleared,
again on a new set; the run's own floors untouched; every other field kept; BuildRunState's floors
never hold a `cells` key; the lobby's empty set), Merge (keeps held cells on the same set, takes
cells that arrive, replaces them on a new set, nil on a new set sent bare), a scripted session
(start, steady sends, the leave card, a rejoin, the lobby, a second start: after every RunState the
client's merged floors equal the run's), and the shipped Forest Road plan built as `startLevel`
builds it. `L4R.Server` mirrors ArenaService's and WaveService's bookkeeping line for line.
Against 8 scratch mutants of A's `RunFloors.luau` (always/never cells, strip the run's floors, drop
a field, say nothing went, keep across a seq, never keep, prefer held cells) all 8 are caught.

## Measured (L4B-8; JSON-length proxy, not a gate)

Forest Road as it ships on this branch, Normal (Hard within 2 bytes), one member: 3 floors, 26
cells in all (13 on each plateau floor). Floors alone: 1,166 bytes with cells, 250 without.
**A steady RunState: 1,686 bytes before (cells every send), 784 after; the first send of a set
1,700.** At `remotes.combatStateHz` 4 that is about 3.6 KB/s less per member. Script:
`scratchpad/b/measure.luau` (run after tests.luau under the harness prelude).

## Gates (my files)

- stylua `--check` and selene on both files: clean (0 errors, 0 warnings).
- luau-lsp on the combat sourcemap (`src/combat src/shared`): 0 diagnostics in ArenaService,
  WaveService, RunFloors (the remaining ones were in VitalsService, CameraController and
  InputController, mid-edit by their owners when I last ran it).
- `py tools/check_compile.py`: PASS (178 files).
- `mutate.py` entries on my two files: all 27 still occur exactly once (checked by exec'ing
  mutate.py's list). `run_harness.source_reading`: all 489 readings identical with my two files at
  HEAD and as they are now, so no `run_harness.py` pin moved.
- The worktree's harness is red right now from others' in-flight edits (the bundle stops on a nil
  call after 577 checks), so `mutate.py files:WaveService.luau,ArenaService.luau` was run on a
  scratch root = HEAD (`git archive`) with my two files copied in: baseline PASS (4,031 checks),
  **MUTATIONS: 27 run, 0 not caught**. (Both files are read only as text by the harness, and every
  pinned reading is unchanged, so this holds on the branch once its harness is green again.)
- `tests_l4b_run.luau`: 37 checks pass under the harness prelude (tests.luau first, `RunFloors`
  added to SOURCES), stylua-formatted, LF. selene reports only the bundle's globals (`check`,
  `load`, `FIXTURES`, `failures`), as for every case file.

## For the other owners

### For A (Types)

1. Done by A already: `RunMember.godMode`, `.spawnIndex` (I had flagged them: last readers
   `CombatService.luau:191` and `ArenaService.RespawnBot`, both deleted).
2. **`Types.ArenaLayout.enemySpawns` (now `Types.luau:1309`) goes (L4B-5).** Its two `src/` readers
   were `ArenaService.buildFromLayout` (handed to `EnemyService.SetSpawnPoints`) and
   `LevelGeometry.FromArena`, both gone; nothing else reads it (`grep -rn enemySpawns src`). The
   comment above it ("At least 4 / 8 respectively, both used round-robin") then speaks of
   `playerSpawns` alone.
3. What I write, for the types: `RunMember` = `userId, name, player (Player), character, humanoid,
   waiting, incomeRate`; `PartyMember` = `userId, name, hp, maxHp, alive, host, waiting,
   damageShare, engaged, down`; `RunState` with `floorsSeq`, without `overdrive`.

### For the designer

1. **Register `tests_l4b_run.luau`** in `run_harness.py` `TESTS`, after A's `tests_l4b.luau` (it
   ends with the verdict line, so last is fine). It needs `"RunFloors": "src/shared/RunFloors.luau"`
   in `SOURCES` (A's relay too), `check` and `load` (tests.luau), and `FIXTURES.levels`,
   `.layouts`, `.combat`, `.expeditions`, `.proving`. It does not use `L1`.
2. **No `mutate.py` entry and no `run_harness.py` pin on my files changed** (27 entries, 489
   readings: see Gates). One cosmetic point: "l3w2 fix S2: the admit's handler leaves before the
   hook" still matches (`\t\t\t\tplaceBody(live)\n`) and is still caught by text (its inserted
   lines break the `arenaHook` pin; ArenaService is never run in the harness), but its new text
   names `live.bot`, a field that is gone. If you touch it, `live.waiting` reads the same: new text
   `"\t\t\t\tplaceBody(live)\n\t\t\t\tif live.waiting then\n\t\t\t\t\treturn\n\t\t\t\tend\n"`.
3. **Config with no reader left after my deletions (row 8):** `Combat.json debug.botHp`
   (`applyMaxHp`), `debug.botIncomeRate` (`AddBot`), `enemy.botColor` (`AddBot`, `RespawnBot`).
   `Layouts/Arenas/ProvingGrounds.luau:163` `enemySpawns` goes with item A-2 (`sim_range.py:5203`'s
   reader is the arena report's).
4. **Pins and mutants for L4B-8** (every old text below occurs exactly once today; the pins are
   counts on `luau_code`, whole lines in the named body):

   ArenaService (`src/combat/server/Services/ArenaService.luau`)
   - pin `"RunState"` spelled once in the code (sendRunState's `FireClient`); `sendRunState(` 3
     (its definition, `sendSummaryTo`, `Broadcast`); `RunFloors.Attach(` 2.
   - pin in `sendRunState`: `local floors, cellsWent = RunFloors.Attach(runFields.floors, seq, play.cellsSent[userId])`,
     `\t\tsent.floors = floors\n`, `\tplay.cellsSent[userId] = seq\n` (1 each), and the Attach line
     before the note.
   - pin in `ArenaService.BuildRunState`: `local floors = RunFloors.Attach(runFields.floors, runFields.floorsSeq, runFields.floorsSeq)`,
     `\t\tfloors = floors,\n`, `\t\tfloorsSeq = runFields.floorsSeq,\n` (1 each).
   - pin in `ArenaService.Admit`: `\tplay.cellsSent[player.UserId] = nil\n`; in
     `ArenaService.Remove`: `\tplay.cellsSent[member.userId] = nil\n`; `play.cellsSent[...] =`
     written 3 times in the file.
   - mutants (file, old, new):
     - "l4b: a member's note is never written": `\tplay.cellsSent[userId] = seq\n` → ``
     - "l4b: the one payload carries the cells": `RunFloors.Attach(runFields.floors, runFields.floorsSeq, runFields.floorsSeq)` → `RunFloors.Attach(runFields.floors, runFields.floorsSeq, nil)`
     - "l4b: a first send drops its cells": `\t\tsent.floors = floors\n` → ``
     - "l4b: a send asks Attach with the set": `RunFloors.Attach(runFields.floors, seq, play.cellsSent[userId])` → `RunFloors.Attach(runFields.floors, seq, seq)`
     - "l4b: an admit keeps the note": `\tplay.cellsSent[player.UserId] = nil\n` → ``
     - "l4b: a removal keeps the note": `\tplay.cellsSent[member.userId] = nil\n` → ``
     - "l4b: the summary card skips the attach": `sendRunState(player, userId, ArenaService.BuildRunState("summary", summary, result))` → `RemoteService.FireClient(player, "RunState", ArenaService.BuildRunState("summary", summary, result))`
     - "l4b: the broadcast skips the attach": `\t\t\tsendRunState(member.player, userId, runState)\n` → `\t\t\tRemoteService.FireClient(member.player, "RunState", runState)\n`
     - "l4b: RunState names no set": `\t\tfloorsSeq = runFields.floorsSeq,\n` → `\t\tfloorsSeq = 0,\n`

   WaveService (`src/combat/server/Services/WaveService.luau`)
   - pin: `run.floors =` once in the file (in `setFloors`); `boot.floorsSeq` written once
     (`\tboot.floorsSeq += 1\n`, in `setFloors`); `setFloors(` 4 (definition, `startLevel`'s
     `\tsetFloors(runFloors)\n`, `backToLobby`'s and `WaveService.Reset`'s `\tsetFloors({})\n`);
     in `pushRunFields` `\t\tfloorsSeq = boot.floorsSeq,\n`.
   - mutants:
     - "l4b: the number never moves": `\tboot.floorsSeq += 1\n` → ``
     - "l4b: a start's floors are no new set": `\tsetFloors(runFloors)\n` → `\trun.floors = runFloors\n`
     - "l4b: the lobby's empty list is no new set": `\trun = freshRun()\n\tsetFloors({})\n\tArenaService.SetLevel(nil)\n` → `\trun = freshRun()\n\tArenaService.SetLevel(nil)\n`
     - "l4b: a session reset's empty list is no new set": `\trun = freshRun()\n\tsetFloors({})\n\tboot.returning = false\n` → `\trun = freshRun()\n\tboot.returning = false\n`
     - "l4b: RunFields carry a stale number": `\t\tfloorsSeq = boot.floorsSeq,\n` → `\t\tfloorsSeq = 1,\n`
   - The `RunFloors` mutants themselves are A's file's; my cases catch the 8 listed above.

### For the ui-engineer

- Every RunState now carries `floorsSeq`; a floor's `cells` is present only on a member's first
  RunState of that seq (`RunFloors.Merge(held, heldSeq, incoming, seq)`, A's). `PartyMember` has no
  `ready`, `bot`, `abilityReadyIn`, `stance`; `RunState` has no `overdrive`.

### For the lead

- Nothing: no remote, project file or hub file.
