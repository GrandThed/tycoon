# L4 W3 fix-diff review (36b54c0..3503134, rulings F1-F19)

Reviewer: roblox-reviewer (Opus), 2026-10-23. Read only. The diff is all 44 files of `git diff 36b54c0..3503134` on
`l4-w3`. I read it against `docs/prompts/l4-w3-fix-round.md`, the four review files, the five fix reports, `relay-a2.md`,
contract §13-§14 and `CLAUDE.md`.

How the probes ran:
- On a `git archive 3503134` copy in the scratchpad (`l4-w3-rev5/tree`), never in the worktree.
- Baseline: `HARNESS: PASS (5,402 checks)` in 70 s.
- Each probe applied one edit, ran the copy's own `run_harness.py` with the main checkout's `luau.exe`, then restored
  the file (`py/probe.py`, `py/probe_print.py`). 17 source probes and 1 behaviour probe ran.
- A second copy (`tree2`) ran the static gates:
  - `stylua --check` and `selene` on the 21 changed source files: clean.
  - `check_compile.py`: PASS, 188 files.
  - `check_stage_mirror.py` (3.12, 46 s): PASS, with "F6: a bad note is dropped, the level kept: 8 compared".
  - `mutate.py`'s stale check, by exec up to its first run step: 2,382 entries, 0 stale, every entry's file in `FILES`.
- `luau-lsp analyze`, from the worktree with sourcemaps written to scratch: 0 diagnostics on both trees.
- I did not run `mutate.py` or `mutate_shards.py`.

**Totals: 0 Critical, 0 Major, 4 Minor, 2 Suggestions.**

## Minor

### m1. F1 also takes the pick away from a party whose first-admitted member leaves before the rest land

**Where:** `src/combat/server/Services/StageFlow.luau:2974-2995` (`DepartAdmit`, `DepartForget`), called from
`WaveService.luau:2685` (Reset) and `openDepart`.

**What is wrong.** F1's rule is that a server opens its auto-start once. It closes M1, because the M1 rejoin comes
after a `done` depart. But it also fires when the session ends while the departure is still `waiting`, before the
party has gathered. At that point no run has happened and nothing has been picked.

**Failure scenario (probe R1, real `StageFlow`, a group added to `tests_l4w3_run`):**
1. A party of two departs for Forest Road Hard. One group TeleportAsync sends both to the server.
2. Member B lands first and is admitted. The depart is `waiting`.
3. B disconnects during the host's load. B was the only member, so `resetSession` runs, then `Reset`, then
   `DepartForget`.
4. The host, who departed, lands. A fresh session verifies the same ticket. `DepartAdmit` returns because
   `departOpened` is already set.
5. The probe prints `depart=nil view=nil`.

The host's lobby shows no line and no pick. The map opens on `MapRules.FirstPick`, which for a player with Normal
starred is Forest Road at its first uncleared difficulty, not the Hard the party chose. The host has to pick again.

At 36b54c0 the same arrival got `waiting`. That ran to `picked` at the 30 s cap, because B was never re-admitted, and
the map opened on Forest Road Hard. So the fix turns "the map on the departed level after 30 s" into "the map on
another pick at once". F1's text lists "a late member" among later sessions that are never a new departure, so this
follows the ruling's wording. The group "server" has no case for it ("a session's end before any admit" is a different
case).

**Fix (the lead's call):**
- Keep F1's guarantee that nothing auto-starts on a later session, and keep the departure's level:
  - `DepartForget` remembers the pair when the depart was still `waiting` or `counting` (it never started and was
    never picked).
  - The next `DepartAdmit` reopens that pair as `picked` (`DepartOpen(..., verified = false, ...)`).
  - A `done` or `picked` depart at Reset leaves nothing, so M1's rejoin and the "map not forced open" case stay as
    they are.
- Add a case for it in group "server".
- Alternatively, take slice 2's other fix: open only on an `"arrival"` join, passing the join's kind through
  `OnAdmitted`.

### m2. The pins still hold lines but not every input: 5 of the fix round's new or moved lines are unguarded

Each probe below passes `HARNESS: PASS (5,402 checks)` unchanged. These are the same "the pins hold the calls, not
their inputs" family the round was ruled to close (slice 2 m2, slice 3 m3).

| # | Where (3503134) | Mutation | Effect if shipped |
|---|---|---|---|
| P1 | `WaveService.luau:2141` (`lateAtZero`) | `userId = member.userId,` → `userId = 0,` | F2 is undone silently. The late set is keyed by 0, so nobody is late, and a run-list stranger still spawning at zero turns the auto-start into `busy`, then `picked` (slice 2 m1 is back). |
| P2 | `WaveService.luau:2139` (`lateAtZero`) | the loop reads `{}` instead of `ArenaService.GetMembers()` | Same as P1. |
| P4 | `WaveService.luau:570` (`secretRows`) | `sitesOf,` → `function(_) return {} end,` | Every chest row disappears from the dungeon's map (an L2-15 regression). The hub's twin is pinned whole (`sendMapArgs`); the dungeon's only pins are `return MapRules.SecretRows(` and the `opened` argument. |
| Q1 | `CombatUIController.luau:1787` (the pick branch) | drop `st.mapSeeded = true` | A `picked` depart followed by the session's first MapState is re-seeded to `FirstPick`. The map opens on another level or difficulty, which defeats the "once per arrival" pick that F13 asked to pin. |
| Q2 | `CombatUIController.luau:1789` | drop `armoryScreen.Close()` | A `picked` depart opens the map over an open Armory (two sheets at once). |

Also passing, lower stakes:
- P3: `continue` dropped after `other.waiting = true` in `startLevel`. This is nearly equivalent, because the body
  still spawns through the placer. But it is a line that `L4W3R.starting` copies and no pin reads, so "a copy cannot
  drift" is not true of it.
- P6: `boot.warnedNotes[levelId] = true` dropped (`:1729`). The note warning then repeats on every `readLevel`.

The caught controls show the probe runner works: P5 (KILL_KINDS without boss, FAIL 1), P7 to P14 (FAIL 1 to 5 each).

**Fix:**
- Pin these lines with their indentation, inside their functions:
  - in `lateAtZero`: `\tfor _, member in ArenaService.GetMembers() do` and `\t\t\tuserId = member.userId,`;
  - in `secretRows`: `\t\tbuilt,\n\t\tsitesOf,\n`;
  - in onRunState, the pick branch whole: `\t\t\tif pick ~= nil then\n\t\t\t\tst.mapSeeded = true\n\t\t\t\tscreen.Select(pick.node, pick.difficulty)\n\t\t\t\tarmoryScreen.Close()`.
- Add each of P1, P2, P4, Q1 and Q2 as a `mutate.py` entry.

### m3. F6/F18: the server, the tools and the map read the note by three rules, and two of them claim what the map does not do

**Where:**
- `StageFlow.luau:1099`: the warning says "dropped, the map shows no note".
- `tools/sim_range.py:5945`: the `check_levels` line says "the game drops it and the map shows no note (F6)".
- `src/client/UI/MapScreen.luau:371`: the map keeps any non-empty string, at any length. The comment at `:63` says "at
  most 24 characters".

**What is wrong.**
- The server's "drop" is only a warning. `readLevel` throws away the kept notes (`local _, dropped`), and nothing on
  the server shows a note.
- The map, in both places, reads the level file itself. It applies its own looser rule: it drops only a non-string or
  an empty note, never a long one.
- So the server and the map do not agree, and two messages promise behaviour that no code has. luau B flagged this as
  "optional" for ui A, and nobody took it.

**Failure scenario.**
- The Castle's designer writes a 30-byte Brutal note. `check_levels` fails, which is correct, and says the map will
  show no note. That is false.
- If the data ships anyway (a hotfix, or the gate skipped), the server warns "dropped" while every map draws the
  30-byte note, cut off in the 66-px button.
- The effect is display only, and `check_levels` keeps shipped data clean. That is why this is Minor.

**Fix:**
- Put one pure rule in `MapRules`, for example `MapRules.Note(scales): string?`: a string of 1 to 24 bytes, else nil.
- `StageFlow.Notes` and `MapScreen`'s difficulty reader both call it, and `sim_range.note_dropped` stays its twin.
- Correct the `:63` comment to say bytes.

### m4. F7: `ReadSummary` drops one card the server really builds, ReturnService's zero card without `Config/Expeditions`

**Where:**
- `src/combat/server/Services/ReturnService.luau:75`: `RunCredit.Empty(if expeditions ~= nil then expeditions.name else "")`.
- `src/shared/RunLines.luau:167`: the title must be 1 to 48 bytes.

**What is wrong.**
- luau A's report §5.1 says so itself. A refused arrival who presses Return while the map config is missing goes home
  with a zeroed card titled "". The hub's `StudioBridge.readSummaries` drops it, so the player sees no card.
- At 36b54c0 the same card showed, with an empty title.
- ArenaService's own session card never has this problem, because its `sessionName()` (`ArenaService.luau:480`)
  falls back to `DEFAULT_SESSION_NAME`.
- The test "What the combat place builds always passes" (`tests_l4w3.luau:617`) checks only `Empty("Forest Road")`.
- The dungeon's own leave card is unaffected: TallyHost falls back to `mapName` when the read fails, as before.

**Failure scenario.** This is a degraded-config path (Combat.json present, Expeditions.json missing) for a refused
arrival. It costs presentation only, but it is exactly the "never drop a card the server built" case the brief names.

**Fix:**
- Export ArenaService's `sessionName()` (or `DEFAULT_SESSION_NAME`) and use it in `buildSummary`.
- Add a case: `ReadSummary(RunCredit.Empty(<that fallback>)) ~= nil`.
- Optionally, TallyHost could warn once when it refuses a RunState summary. That card comes from the server, so a
  refusal there is a bug, and today it shows zero totals and no rows silently.

## Suggestions

### s1. s2's pcall turns a throw after the point of no return into a refusal, and drops the traceback

**Where:** `WaveService.luau:2183-2198`.

**What happens on a throw:**
- `startLevel` is not transactional. A throw after `run.phase` turns live (in its last `broadcast()` or in
  `PublishRun()`) now reads as `"unavailable"`.
  - `DepartRefused` sets `picked`, and the leader gets an "unavailable" toast inside a run that did start.
  - Back in the lobby after that run, the `picked` view goes out, and `TallyRules.Depart` opens the map on it: the map
    is forced open after a run.
- `tostring(problem)` keeps the message but loses the stack, which a Heartbeat error used to print in full.

**Fix:**
- Use `xpcall(..., debug.traceback)` for the warning.
- After a throw, call `DepartRefused` and the toast only while `run.phase == "lobby"`. Otherwise leave the depart
  `done`.

This is hypothetical: no throw source after the phase change is known. Hence a suggestion.

### s2. `resetOpened` and `openedWrites` pin one spelling

**Where:** the pins are regexes for `\bdepartOpened\b` over Reset and `\bboot\.departOpened\s*=` over the file.

A Reset that writes the flag through another key expression passes PASS 5,402 (P15:
`rawset(boot, "depart" .. "Opened", false)`). This is contrived, so it is not a finding. If the lead wants F1 airtight,
make `departOpened` private to the DepartBook functions, for example a field only StageFlow names. The behaviour cases
in group "server" already catch the realistic regressions (P14: FAIL 5).

## Each ruling, checked against its finding

- **F1:**
  - M1's scenario is closed for the solo case and the party case. Arm, run, Reset, then the same verified ticket gives
    no `waiting`, no `counting` and no `picked`. This is proven by the real `StageFlow` in group "server" and by P14
    (FAIL 5).
  - R works after a Reset (`DepartLever` sets the depart whatever the flag) and counts as the server's opening.
  - The cost to a late host is m1.
- **F2:**
  - At zero, `DepartLate` leaves only bodyless non-expected members out. An expected member without a body still
    refuses (busy, then picked).
  - If everyone would be late, nobody is.
  - The leader's own Start passes no `late` (pinned `startOwnNoLate`).
  - A late member keeps `waiting = true`, gets a run summary titled with the level, and is placed by
    `ArenaService`'s CharacterAdded placer (ruling 18: the safe point outside a fight, the lobby camp in one).
  - `startLevel` is still never yielding.
- **F3:**
  - `raiders` and `boss` lines count `kills`; every other kind counts 1.
  - A share-only credit adds a count of 0, which `RunLines.Add` and `Read` both accept. `TallyRules.Rows` prints plain
    "Raiders" for it, and a boss label never shows a count.
  - The `killCounted` fallback still counts 1.
  - In a party, the raiders and boss counts now add up to `summary.kills`.
- **F4:**
  - `IsMockMode()` reads ProfileStore's module field. ProfileStore 1.0.3 sets that field together with its local at
    `:2101-2109`.
  - "Nobody admitted" refuses during the NotReady window. Both entry points (the P key and the `DebugCashEra`
    attribute) go through `nextCashEra`.
  - The "realStore" notice reaches the party, and every other refusal is silent.
  - The Studio-only gates are unchanged.
- **F5:**
  - s1: the comment is fixed.
  - s3: the early return is right. The tick that turns `picked` (at the cap or on a refusal) still broadcasts its beat.
    `done` comes either from the start, which broadcast its own RunState, or from `DepartAsked`, after which
    `OnStartLevel` broadcasts.
  - s2: see s1 above.
- **F6/F18:**
  - Validate no longer names a note.
  - `StageFlow.Notes` equals `sim_range.kept_notes` and `note_problems` on 8 mirror cases.
  - `check_stage_mirror` passes `notes=False` wherever it compares Validate's list.
  - 4 of 4 mirror mutants are caught.
  - The map side is m3.
- **F7:**
  - One reader in all four places: the bridge (live TeleportData and the Studio record, both through `ParseReturnData`
    then `readSummaries`), the hub client, and TallyHost.
  - Every field the combat place writes is whole or finite and non-negative. `damageShare` is guarded at 0/0 by
    `WaveService.damageShare`, `seconds` is floored, and the counters are whole.
  - Run cards always carry the level's name: `SetLevel` comes before `ResetSummaries`, and a mid-run admit takes the
    name.
  - The only server-built card that is dropped is m4's.
- **F8:** both halves of every `Read` field rule have a case. luau A shows the reviewer's six probes at 0 of 6 on HEAD
  and 6 of 6 now. `#upcoming >= 1` is asserted.
- **F9:**
  - `MapRules.SecretRows` is the old loop verbatim, and both places call it.
  - The pcall and the cache stay in each caller's `sitesOf`.
  - `SecretFlow.Site` equals `MapRules.Site`, so the call type-checks.
  - The dungeon's call-site argument is unpinned (m2 P4).
- **F10:** all five comments are corrected. Contract §13.7 now says P is refused on the real store.
- **F11:**
  - TouchHold counts by reason, saves at the first hold, restores at the last release, and ignores a stray release.
  - Its order against ArmoryScreen's R9 toggle is right in every hand-off I traced:
    - the map's open closes the Armory before it holds;
    - the Armory's open (only through `togglePanel`) closes the map first;
    - the report closes both before it holds.
  - Nothing opens the Armory or the map while the report is up: the bar key, K and `togglePanel` are gated, and the
    hub passes `padToggle = false`.
  - Dismiss is the report's only hide.
  - `HubMap.Destroy` releases, and MenuOpened closes the map, which releases.
  - `card.Show` cannot throw after the hold on a card that `ReadSummary` passed: `Format.Cash` and `Format.Duration`
    terminate on any finite number.
  - The combat place maps neither TouchHold nor HubMap.
  - The order lines are pinned as contiguous text.
- **F12:** `star = false`, and `hasFirstClear` is gone.
- **F13:**
  - `TallyRules.Depart` matches the old controller branch for branch:
    - the opening on entering the lobby only when nothing holds;
    - `close` equals the old `startedHolding`;
    - the picked select once per `levelId:difficulty`, a level with no node is no pick, and the memory is not written.
  - The host carries out the answer in the old order.
  - `mapScreen` is built before the RunState listener connects, so updating the memory with no screen changes nothing.
  - The 120 cases catch p1, p2 and P8.
  - `MapRules.FirstPick` is MapScreen's old body verbatim.
- **F14:** the badge is a non-rotated TextLabel. `Montserrat-Bold.ttf`, the face GothamBold uses, has U+25C6 in its
  cmap (checked in Roblox's local `content/fonts`). The only `Rotation =` left is on the flying sprites, outside the
  clipped rows.
- **F15:** `IsRunResult` requires a string `levelId` and finite camps. ReturnService's leave card sends `levelId = ""`,
  which passes.
- **F16:** the key without `Config/Expeditions` toasts on every tap. `Theme.TOAST_ERROR_SECONDS` exists.
- **F17:**
  - Assertion 24's label, its comment and BALANCE say "back-to-back runs on Normal or Hard never finish an era sooner
    than building".
  - `run_pause(stop_after=k)` gives k departures and k landings, and the home flag stops further pauses.
  - The printed table equals slice 4's probe.
- **F19:** the relabel, the docstrings and the blank line are done. The snapshot mutant now returns at run time.

## Checked and clean

- **Server authority:**
  - No remote, validator or rate limit changed (`HubRemotes`, `CombatRemotes` and `ReturnService` are not in the
    diff).
  - P gains a refusal.
  - `RequestStartLevel` reaches `startLevel` exactly as before.
- **`mutate.py`:**
  - 2,382 entries, 0 stale, no entry with old == new, every entry's file in `FILES`.
  - A compile error counts as caught only when the bundle stops, and the new pure-module entries are targeted edits.
  - The pin-caught entries are caught by the text pins they were written for.
  - The re-aimed `l3fix2 F1` entry now returns at run time.
- **Project files:**
  - `combat.project.json` maps `TallyRules` beside `RunTally`.
  - `DepartLine.luau` is deleted, and no `src` or `tools` reader is left (its one `mutate.py` mention is replacement
    text).
  - TouchHold is hub-only.
- **Outside the rulings, all judged fine:**
  - TallyHost now reads with `ReadSummary` (ui B deviation 2).
  - The share is clamped at display.
  - `Flights` gates coins on `totals.cash`, which is equivalent to the old `launch` row sum.
  - `NextAbility` breaks `order` ties by id, as the Armory's tab does.
  - `Wallet` reads NaN and infinity as 0.
  - `bestWave` defaults to `wavesCleared` (luau A deviation 1).
  - `materials` is capped at 16 entries with 1-48-byte keys.
