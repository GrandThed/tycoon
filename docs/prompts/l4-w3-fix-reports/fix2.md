# L4 W3 fix round 2: one agent across owners (G1-G5)

- Rulings: `docs/prompts/l4-w3-fix2.md`.
- Findings: `docs/prompts/l4-w3-review/5-fix-diff.md` (m1-m4, s1).
- Branch `l4-w3` at `d72cb2f`, worktree `tycoon-p5`. Nothing is committed or staged.

Python versions:
- `run_harness.py`, `mutate.py` and my stale and demo scripts ran on 3.14 32-bit (`py`).
- `check_stage_mirror.py` (it has a shebang), `mirror_mutants.py`'s runs and `check_levels.py` (`py -3.12`) ran on
  3.12 64-bit.

**One required change outside my files.** G3 puts `require(MapRules)` into StageFlow. `check_stage_mirror.py` bundles
only the modules in its `MODULES` tuple, so in the worktree as it stands it stops with "no source for MapRules".
`mirror_mutants.py` has three F6 Notes mutants that aim at text G3 moved into MapRules. Both diffs are in "Required
changes" at the end. I applied them to a scratch copy and the gates passed there; they are not applied in the worktree.

## Files

| File | What |
|---|---|
| `src/combat/server/Services/StageFlow.luau` | G1: `DepartBook.departCarried`, and the carry in `DepartForget`, `DepartAdmit` and `DepartLever`. `DepartLive` moved above `DepartAdmit`, text unchanged. G3: `Notes` asks `MapRules.Note`, and the local `NOTE_MAX_LENGTH` is gone. |
| `src/shared/MapRules.luau` | G3: `MapRules.MAX_NOTE_LENGTH = 24` and `MapRules.Note`. |
| `src/client/UI/MapScreen.luau` | G3: `note = MapRules.Note(def),` (and the require). The header comment now says bytes. |
| `src/combat/server/Services/WaveService.luau` | G1: the boot gains `departCarried`. G5: the start at zero runs under `xpcall(..., debug.traceback)` and refuses only in the lobby. |
| `src/combat/server/Services/ArenaService.luau` | G4: `local function sessionName()` becomes `function ArenaService.SessionName()`. Its two callers are re-pointed. |
| `src/combat/server/Services/ReturnService.luau` | G4: the zero card is `RunCredit.Empty(ArenaService.SessionName())`. |
| `tools/sim_range.py` | G3: the note message, plus the stale comment beside `NOTE_MAX_BYTES` (it named `StageFlow.NOTE_MAX_LENGTH`). |
| `tools/crowd_harness/run_harness.py` | The new family `L4W3FIX2_LINES` with `START_BLOCK`, `SESSION_DEFAULT` and `l4w3fix2_reading` (source key `l4w3fix2`). Re-aimed `departPcall` and `departThrownRefusal`. |
| `tools/crowd_harness/mutate.py` | `FILES += ReturnService, MapScreen`. 11 entries re-aimed by key, and 23 new ones (`L4W3FIX2_MUTATIONS`). |
| `tools/crowd_harness/tests_l4w3_run.luau` | The groups `carry` (G1) and `thrown` (G5). The verbatim copy `L4W3R.startAtZero`. Two pin labels. Header. |
| `tools/crowd_harness/tests_l4w3.luau` | The group `note` (G3, `MapRules.Note`). |
| `tools/crowd_harness/tests_l4w3_pins.luau` | `L4P.FIX2` (21 counts) and `fix2Tests` (G4's title through `ReadSummary`). |

## Contracts (signatures)

```lua
-- StageFlow (pure)
export type DepartBook = { depart: Depart?, departOpened: boolean, departCarried: { levelId: string, difficulty: string }? }
StageFlow.DepartForget(book): ()      -- waiting/counting -> departCarried = its pair; done/picked -> nil
StageFlow.DepartAdmit(book, ...): ()  -- departOpened: a carried pair opens as DepartOpen(pair, verified=false) = picked, spent
StageFlow.DepartLever(book, ...): boolean  -- also clears departCarried
-- MapRules (pure, shared)
MapRules.MAX_NOTE_LENGTH = 24
MapRules.Note(difficulty: Types.LevelDifficulty?): string?   -- a string of 1-24 bytes, else nil
-- ArenaService
ArenaService.SessionName(): string    -- Expeditions.json name, else DEFAULT_SESSION_NAME
```

## What each ruling does

- **G1:**
  - When `DepartForget` (from `WaveService.Reset`) finds the depart `waiting` or `counting`, it stores
    `{ levelId, difficulty }` in `book.departCarried`. After `done` or `picked` it stores nil.
  - The next `DepartAdmit` on the server (`departOpened` already true) spends the carry. It opens
    `DepartOpen(carried.levelId, carried.difficulty, false, nil, since)`, which is `picked`: the map shows the
    departure's own pair, whatever that admit's hint says.
  - Later admits in that session find no carry and open nothing, so the pick is never re-opened after the leader's own
    start.
  - R (`DepartLever`) clears a pending carry, so its own wait stands.
  - F1 is unchanged. After a run (`done`) nothing is carried and the rejoin opens nothing.
- **G2:** the five lines are pinned whole with their indentation, in their own functions:
  - in `lateAtZero`: `\tfor _, member in ArenaService.GetMembers() do` and `\t\t\tuserId = member.userId,`;
  - in `secretRows`: `\t\tbuilt,\n\t\tsitesOf,`;
  - in `onRunState`: `\t\t\t\tst.mapSeeded = true`, the `armoryScreen.Close()` line (a regex, because the code
    reader blanks its trailing comment to spaces), and the whole pick branch in order.
  - P1, P2, P4, Q1 and Q2 are each a `mutate.py` entry.
- **G3:**
  - `MapRules.Note` is the one rule. `MapRules.MAX_NOTE_LENGTH` is the one home of 24.
  - `StageFlow.Notes` keeps exactly what `Note` returns, and warns about any other non-nil note: "…not a string of 1 to
    24 bytes: dropped, and the map does not show it".
  - `MapScreen` shows only `MapRules.Note(def)`.
  - `sim_range` keeps `NOTE_MAX_BYTES = 24`. Its message now reads "…: the note is dropped and the map does not show it
    (F6, MapRules.Note)".
- **G4:**
  - ReturnService's zero card takes `ArenaService.SessionName()`. That is the same function ArenaService's own session
    cards use, so the `DEFAULT_SESSION_NAME` default is shared and the string is not copied.
  - Without `Config/Expeditions` the title is "Expeditions", which `RunLines.ReadSummary` keeps.
- **G5:**
  - The start at zero runs as `xpcall(function() … end, debug.traceback)`, and the warn carries the traceback.
  - A throw while `run.phase == "lobby"` is the `unavailable` refusal: picked, the toast, one warn.
  - A throw after the level went live sets `refusal = nil` and warns once ("…threw after the level went live: <trace>").
    The depart stays `done`, with no pick and no toast.

## Every changed line a pin or entry reads (file: old -> new)

- **StageFlow**
  - `local NOTE_MAX_LENGTH = 24` (and its comment) -> removed.
    - The entry `l4w3b note: one byte longer` is re-aimed to MapRules' `MapRules.MAX_NOTE_LENGTH = 24`.
    - Pin `notesOwnCap` expects 0.
  - In `Notes`: `\t\tif note ~= nil and (type(note) ~= "string" or note == "" or #note > NOTE_MAX_LENGTH) then` …
    `\t\telseif note ~= nil then\n\t\t\tkept[name] = note` -> `\t\tlocal shown = MapRules.Note(scales)` /
    `\t\tif shown ~= nil then` / `\t\t\tkept[name] = shown` / `\t\telseif note ~= nil then` / the warn.
    - Entries `l4w3b note: any length` and `empty passes` are re-aimed to MapRules' condition.
    - Entries `l4w3b-fix F6: a good note dropped` and `a bad note kept` are re-aimed to the `shown` lines.
    - Pins `notesAsk`, `notesKeep` and `notesOwnRule` (0).
    - The `mirror_mutants.py` Notes F6 entries need re-aiming (see "Required changes").
  - The warn: ``… {NOTE_MAX_LENGTH} bytes: dropped, the map shows no note`` ->
    ``… {MapRules.MAX_NOTE_LENGTH} bytes: dropped, and the map does not show it``. The `note` group reads "dropped",
    which is kept.
  - New: `local MapRules = require(sharedFolder:WaitForChild("MapRules"))`. `check_stage_mirror` `MODULES` needs it
    (see "Required changes").
  - `DepartAdmit`: `\tif book.departOpened then\n\t\treturn\n\tend` -> the guard now holds
    `\t\tlocal carried = book.departCarried` / `\t\tbook.departCarried = nil` / `\t\tif carried ~= nil then` /
    `\t\t\tbook.depart =` / `\t\t\t\tStageFlow.DepartOpen(carried.levelId, carried.difficulty, false, nil, since)` /
    `\t\tend` / `\t\treturn`. The entry `l4w3b-fix F1: an admit opens again` is re-aimed to the whole guard.
  - `DepartForget`: `\tbook.depart = nil` alone -> `\tlocal depart = book.depart` /
    `\tbook.departCarried = if depart ~= nil and StageFlow.DepartLive(depart)` /
    `\t\tthen { levelId = depart.levelId, difficulty = depart.difficulty }` / `\t\telse nil` / `\tbook.depart = nil`.
    Entries `l4w3b-fix F1: the session's end reopens` and `keeps the auto-start` are re-aimed to
    `\t\telse nil\n\tbook.depart = nil\n`.
  - `DepartLever`: `\tbook.departOpened = true\n\treturn book.depart ~= nil` -> `\tbook.departOpened = true` /
    `\tbook.departCarried = nil` / `\treturn book.depart ~= nil`. The entry `l4w3b-fix F1: R is not an opening` is
    re-aimed.
  - `DepartLive` moved, text unchanged (the s3 entries' texts are still unique).
- **WaveService**
  - In `tickDepart`: `\t\t\tlocal started, problem = pcall(function()` -> `\t\t\tlocal started, trace = xpcall(function()`.
    - Pin `departPcall` is re-aimed to the new line.
    - Pin `startNoPcall` expects 0.
    - The entry `l4w3b-fix s2: no pcall` is re-aimed.
  - `\t\t\tend)` -> `\t\t\tend, debug.traceback)`. Pin `startTraceback`, entry `l4w3fix2 G5: no traceback`.
  - `\t\t\t\trefusal = "unavailable"` / ``\t\t\t\tthrown = `: {tostring(problem)}` `` ->
    ``\t\t\t\tthrown = `: {tostring(trace)}` `` / `\t\t\t\tif run.phase == "lobby" then` /
    `\t\t\t\t\trefusal = "unavailable"` / `\t\t\t\telse` / `\t\t\t\t\trefusal = nil` / `\t\t\t\t\twarn(` / the live
    warn / `\t\t\t\t\t)` / `\t\t\t\tend`.
    - Pin `departThrownRefusal` is re-aimed to depth 5.
    - Pins `startLobbyOnly` and `startCopy` (the whole block from `local leader` to the toast, verbatim in
      `L4W3R.startAtZero`).
    - The entry `l4w3b-fix s2: a throw is no refusal` is re-aimed to depth 5. Its depth-4 text still occurred once
      inside the deeper line, so the stale check did not list it, but it was mis-aimed.
  - The boot gains `\tdepartCarried = nil :: { levelId: string, difficulty: string }?,`. No pin reads it, and
    `departWrites` / `openedWrites` still read 0.
  - Unchanged lines that are now pinned (G2): `\tfor _, member in ArenaService.GetMembers() do`,
    `\t\t\tuserId = member.userId,`, `\t\tbuilt,\n\t\tsitesOf,`.
- **CombatUIController** (unchanged, now pinned): `\t\t\t\tst.mapSeeded = true`, `\t\t\t\tarmoryScreen.Close() -- one
  sheet at a time`, and the pick branch.
- **MapRules:** new `MapRules.MAX_NOTE_LENGTH = 24`, and in `Note`
  `\tif type(note) ~= "string" or note == "" or #note > MapRules.MAX_NOTE_LENGTH then` and
  `\tlocal note: any = if type(scales) == "table" then scales.note else nil`. Read by the re-aimed `l4w3b note:` entries
  and the G3 entries.
- **MapScreen:** `\t\t\t\tnote = if typeof(def.note) == "string" and def.note ~= "" then def.note else nil,` ->
  `\t\t\t\tnote = MapRules.Note(def),`. Pins `mapNote` and `mapOwnNote` (regex `\bdef\.note\b`, 0).
- **ArenaService:**
  - `local function sessionName(): string` -> `function ArenaService.SessionName(): string`.
  - `emptySummary(sessionName())` x2 -> `emptySummary(ArenaService.SessionName())`.
  - Pins `sessionFallback`, `sessionCards` (2) and `sessionDefaults` (2). `SESSION_DEFAULT` reads
    `local DEFAULT_SESSION_NAME = "Expeditions"`.
- **ReturnService:** `\tlocal expeditions = Catalog.GetExpeditionsConfig()` /
  `\treturn RunCredit.Empty(if expeditions ~= nil then expeditions.name else "")` ->
  `\treturn RunCredit.Empty(ArenaService.SessionName())`. Pins `returnTitle` and `returnEmpties`.
- **sim_range.py:** `f"the game drops it and the map shows no note (F6)")` ->
  `f"the note is dropped and the map does not show it (F6, MapRules.Note)")`. The comment
  `# StageFlow.NOTE_MAX_LENGTH (L4 W3 section 7)` -> `# MapRules.MAX_NOTE_LENGTH (L4 W3 section 7; fix round 2 G3)`.
  No tool reads either line.

## Gates

| Gate | Result |
|---|---|
| stylua (the 6 source files and `tests_l4w3_run.luau`) | clean. `tests_l4w3.luau` and `tests_l4w3_pins.luau` were not stylua-clean at `d72cb2f`, so I did not reformat them; the new code follows their style. |
| selene (the 6 source files) | 0 errors, 0 warnings |
| luau-lsp analyze, hub (`src/client src/server src/shared`) and combat (`src/combat src/shared`), sourcemaps in scratch | 0 diagnostics, both |
| `check_compile.py` | PASS, 188 files; WaveService 105 top-level locals |
| `py -3.12 tools/check_levels.py` | PASS. `note_problems` on a 25-byte note prints the new message. |
| `check_stage_mirror.py`, worktree as is | **FAIL**: "no source for MapRules", until `MODULES` gains it (see "Required changes") |
| `check_stage_mirror.py`, scratch tree with the required diff | **PASS**, with "F6: a bad note is dropped, the level kept (StageFlow.Notes, Validate): 8 compared" |
| `mirror_mutants.py --only F6`, scratch tree with the diff | 7 of 7 caught. The 4 note mutants fail 1, 1, 3 and 6 of 8, as at `3503134`. All 151 mutants are 0 stale. |
| harness (`run_harness.py`) | **PASS, 5,466 checks** (`d72cb2f`: 5,402; +64 = carry 13, thrown 7, Note 17, l4w3fix2 27) |
| `mutate.py` stale check (exec up to the run step) | **2,405 entries, 0 stale**, none with old == new, every file in `FILES` |
| `mutate.py` filtered, 6 private roots (`mutant-fix2a..f`, removed) | **42 run, 0 not caught**: `l4w3fix2` 23, `l4w3b note:` 4, `l4w3b-fix F1:` 9, `l4w3b-fix s2:` 2, `l4w3b-fix F6:` 4 |
| `mutate.py` re-run after the last two edits (a nil guard in `carry`, a MapRules comment) | `l4w3fix2 G1` 7, `l4w3b note:` 4, `l4w3fix2 G3` 4: **15 run, 0 not caught** |

Each baseline read `HARNESS: PASS (5,466 checks)`. I did not run `mutate_shards.py`. I killed only my own PIDs: the
first set of filtered runs, which I stopped to stylua the test file.

## Each fix shown failing without it

I ran these on a scratch copy of the worktree's `src`, `tools` and project files (`scratchpad\l4-w3-fix2\tree2`, script
`nofix.py`). The baseline there was PASS 5,466. Each demo undid one fix and then restored it.

- **G1** (DepartForget carries nothing, which is `d72cb2f`'s behaviour): **FAIL 6**.
  - carry: "a session that ends while it waits … carries its pair (G1)"
  - carry: "the host who lands next gets Forest Road Hard picked on the map (G1)"
  - carry: "the wire shows that pick …"
  - carry: "nothing waits, counts down or starts from it …"
  - carry: "a countdown cut by the session's end is picked …"
  - carry: "once spent, …"
  - The F1 cases (run, Reset, rejoin -> nothing) pass both with and without the fix.
- **G2** (each review probe applied):

  | Probe | Result | Failing pins |
  |---|---|---|
  | P1 `userId = 0,` | FAIL 1 | `lateUserId` 0 ≠ 1 |
  | P2 `for _, member in {} do` | FAIL 1 | `lateMembers` |
  | P4 `sitesOf,` -> `function(_) return {} end,` | FAIL 1 | `secretRowsSites` |
  | Q1 `st.mapSeeded = true` dropped | FAIL 2 | `uiPickSeeded`, `uiPickBranch` |
  | Q2 `armoryScreen.Close()` dropped | FAIL 2 | `uiPickArmory`, `uiPickBranch` |

  The review recorded each of these as PASS 5,402 at `3503134`.
- **G3:**
  - StageFlow with `d72cb2f`'s own cap and rule: **FAIL 4**. `notesAsk` 0, `notesKeep` 0, `notesOwnCap` 3,
    `notesOwnRule` 1.
  - MapScreen's `d72cb2f` reader: **FAIL 2**. `mapNote` 0, `mapOwnNote` 3.
  - Mutants on `MapRules.Note` fail the `note` cases. "Note keeps any non-empty value": 2 checks. "Note reads a
    non-table": 1.
- **G4** (ReturnService's `d72cb2f` zero card): **FAIL 1**, `returnTitle` 0. The case "an untitled card is dropped
  (… m4)" shows what that card was.
- **G5:**
  - WaveService's `d72cb2f` pcall block, the copy untouched: **FAIL 6**. `departPcall`, `departThrownRefusal`,
    `startCopy` 0, `startLobbyOnly`, `startNoPcall` 1, `startTraceback`.
  - The `d72cb2f` block in both WaveService and the copy, so `startCopy` passes and the behaviour judges it: **FAIL 8**.
    It includes "thrown: with one warn carrying the error and its traceback", "thrown: a throw after the level went
    live leaves it done: no pick, no toast (G5)" and "thrown: and only warns, with the error and its traceback".
  - The demo's first run, on a copy that lacked `combat.project.json`, carried one extra standing failure on every
    line (`CameraMaxZoomDistance`). The numbers above have it subtracted. G1 was re-run on a full copy and gave FAIL 6.

## Assumptions

- G1 uses the carried pair, not the next admit's hint. It is "that levelId / difficulty" of the departure, so a
  stranger with no hint who lands first still gets the departure's pick.
- G1's carry is spent at its admit, and R clears it. Both are covered by cases and mutants.
- G3: `Note` takes the difficulty's table (typed `Types.LevelDifficulty?`) and answers nil for anything that is not a
  table.
- G4: I made the existing function public instead of adding a wrapper, so there is still one function. If
  `Expeditions.json`'s own `name` were empty or over 48 bytes, both cards would still be dropped. That is the shipped
  data's concern, and `tests_l4w3` "shipped map" already checks it.
- G5: "Still in the lobby" is read as `run.phase == "lobby"` after the throw. A throw inside `startLevel` before the
  phase line, but after members were moved, still counts as a refusal. That is the ruling's literal criterion.

## Required changes outside my files (exact diffs; applied only in scratch)

`tools/check_stage_mirror.py` (a mirror owner's file). Without this the mirror cannot load StageFlow:

```diff
@@ -189,9 +189,10 @@
 HARNESS = ROOT / "tools" / "crowd_harness"
 DRIVER = HARNESS / "stage_mirror.luau"
 # Unlocks: StageFlow reads the family id cap from it (the L2 W1 fix round's s2). WorldReact (L2 W3):
-# LevelGeometry cuts deep water into ice cells with it, and it reads Unlocks.
+# LevelGeometry cuts deep water into ice cells with it, and it reads Unlocks. MapRules (the L4 W3 fix
+# round 2's G3): StageFlow.Notes keeps what MapRules.Note keeps.
 MODULES = ("Economy", "Armory", "HitShapes", "SwingGate", "Region", "Combat", "Unlocks", "WorldReact",
-           "LevelGeometry", "CampBrain", "StageFlow")  # in load order
+           "LevelGeometry", "CampBrain", "MapRules", "StageFlow")  # in load order
```

`tools/crowd_harness/mirror_mutants.py`. Without this, three mutants read STALE:

```diff
@@ -24,7 +24,7 @@
          "LevelGeometry": "src/combat/server/Services/LevelGeometry.luau",
-         "Armory": "src/shared/Armory.luau"}
+         "Armory": "src/shared/Armory.luau", "MapRules": "src/shared/MapRules.luau"}
@@ -341,12 +341,13 @@
     # Validate keeping a level whose note is bad (check_stage_mirror's "F6: a bad note is dropped" cases).
-    ("Notes F6: a 25-byte note kept", "StageFlow", "or #note > NOTE_MAX_LENGTH) then",
-     "or #note > NOTE_MAX_LENGTH + 1) then"),
-    ("Notes F6: an empty note kept", "StageFlow", "(type(note) ~= \"string\" or note == \"\" or #note",
-     "(type(note) ~= \"string\" or #note"),
-    ("Notes F6: a good note dropped too", "StageFlow", "\t\telseif note ~= nil then\n\t\t\tkept[name] = note\n",
-     "\t\telseif note ~= nil and false then\n\t\t\tkept[name] = note\n"),
+    # Fix round 2's G3 moved the cap and the rule into MapRules.Note, which StageFlow.Notes asks.
+    ("Notes F6: a 25-byte note kept", "MapRules", "or #note > MapRules.MAX_NOTE_LENGTH then",
+     "or #note > MapRules.MAX_NOTE_LENGTH + 1 then"),
+    ("Notes F6: an empty note kept", "MapRules", "if type(note) ~= \"string\" or note == \"\" or #note",
+     "if type(note) ~= \"string\" or #note"),
+    ("Notes F6: a good note dropped too", "StageFlow", "\t\tif shown ~= nil then\n\t\t\tkept[name] = shown\n",
+     "\t\tif shown ~= nil and false then\n\t\t\tkept[name] = shown\n"),
```

A script that applies both diffs and prints them: `scratchpad\l4-w3-fix2\apply_required.py <repo>`. The printed diff
is in `scratchpad\l4-w3-fix2\required.diff`.

## What to check in Studio

1. `build\proving.rbxl`, Play: the countdown, then the level, as before.
2. A forced throw (none is known) would print the traceback in Output. Without one, nothing changes on screen.
3. The bridge, two clients: if the first member leaves before the host lands, the host's lobby opens the map on the
   party's level and difficulty, picked, with no countdown.
