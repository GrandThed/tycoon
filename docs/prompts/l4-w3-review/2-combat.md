# L4 W3 review, slice 2: the combat server (93eb8e9)

Reviewer: roblox-reviewer (read only). The diff is `git diff dce50da..93eb8e9`, restricted to:
- `src/combat/server/` (`Main.server.luau`, `ArenaService`, `WaveService`, `RunCredit` new, `RunRegistry`,
  `ReturnService`, `DebugService`, `CombatRemotes`, `StageFlow`, `SecretFlow`);
- `tools/crowd_harness/tests_l4w3_run.luau`.

I also read `MapRules`, `RunLines`, the hub's ticket write and the client's `depart` reader where they matter.

**Totals: 0 Critical, 1 Major, 4 Minor, 4 Suggestions.**

How the probes ran:
- On a `git archive 93eb8e9 src tools *.project.json *.toml` copy in my scratch folder, never in the worktree.
- The baseline harness gave `HARNESS: PASS (4,994 checks)`.
- For each probe I applied one source mutation, ran the copy's own `run_harness.py` with the main checkout's
  `luau.exe`, then restored the file.
- `check_stage_mirror.py` on the copy: `CHECK: PASS`.
- `luau-lsp analyze` on `src/combat/server` and `src/shared` against a combat sourcemap written to scratch: 0 diagnostics.
- stylua and selene on `src/combat/server`: clean.
- I did not run `mutate.py`.

**Overlaps with the other slices (count each once):**
- Slice 3's m2 (`3-clients.md`) is about the city card's star: a Normal first clear has no `firstClear` line.
  - Its fix (b) lands in my slice, in `WaveService.EndRun`.
  - If the lead picks (b), credit the line on `if star then`, not `if given ~= nil then`, with valor
    `if given ~= nil then given.valor else 0`. Keep `run.walletDirty` only when `given ~= nil`.
  - The `endFirstCredit` pin and the `endTail` copy in `tests_l4w3_run.luau` move with it.
- Slice 1's m1 is the hub half of the same "the pins hold the calls, not the conditions" family as my m2.

## Major

### M1. A solo player whose trip home fails is re-admitted into a fresh session that re-arms the auto-start, so the level starts by itself after a run

**Where:**
- `src/combat/server/Services/WaveService.luau:2632`: `WaveService.Reset` runs `boot.departOpened = false`.
- `WaveService.luau:2398-2420`: `openDepart` opens again from `ArenaService.Pick()` at the next session's first admit.
- `tools/crowd_harness/tests_l4w3_run.luau:977`: the pin `resetOpened = { 1, "and lets the next session open its own" }`
  requires it.

**The path, live only:**
1. A solo departure: the ticket's `expected` is `{ host }`.
2. The player clears the level, so `depart` is `done`. In the lobby they press Return.
3. `ReturnService.trySendHome` runs `ArenaService.Remove(player)` (`ReturnService.luau:204`).
   - That was the last member, so `resetSession()` runs (`ArenaService.luau:1386`).
   - It fires the reset hook, `WaveService.Reset`, which sets `departOpened = false`.
   - The ticket is not touched. `RunRegistry.Clear` removes only the `runs` entry (`RunRegistry.luau:325`). The hub
     wrote the `codes` ticket with `registry.ttlSeconds` 7200 (`ExpeditionService.luau:204`, `Combat.json:49`).
4. The teleport fails: `teleportWithRetry` returns false, or `TeleportInitFailed` fires (`ReturnService.luau:401-411`).
   - `abortReturn` calls `rejoin`, which runs `runJoinSequence(player, DataService.LoadAsync, "rejoin")`
     (`Main.server.luau:279`).
   - This is the path whose comment says "a rejoin after a failed trip home opens a fresh lobby"
     (`ArenaService.luau` resetSession).
5. `readHint` reads `player:GetJoinData()` again (`Main.server.luau:212`). That is still the original departure's
   `{ levelId, difficulty, hostUserId }`.
   - `OpenSession` opens a fresh session and `ResolveTicket` finds the same ticket.
   - The level and difficulty match, and so does `privateServerId == game.PrivateServerId`, so the ticket is verified.
6. Admit, then `OnAdmitted`, then `openDepart`. The depart is now `waiting` with `verified = true`.
   - On the next tick `ExpectedIn()` is true (the host was admitted again) and so is `HostIn()`.
   - The character never left the server, so `bodies` is true at once.
   - The depart goes to `counting`, and 5 s later `startLevel` starts the level.

**Failure scenario:**
- The player asked to go to the city and got an "unavailable" toast.
- Then "Forest Road · Normal starts in 5" appears, and the run starts unless they press Return again inside those 5 s.
- Once it starts they must Abandon (Backspace twice) before Return works.
- This breaks L4W3-4 ("Departing auto-starts once per session, never after a run") and the brief's "nor re-arms after
  Reset".
- A solo departure is the commonest case.
- In a party the last member left behind only gets `picked` at the 30 s cap (the others are not admitted in the new
  session), so the map opens by itself.
- Studio cannot show it, so the §9 B bridge test will not catch it:
  - `StudioBridge.ReadArrival` removes the handoff record at the first arrival, so the rejoin's hint is `NO_LEVEL`;
  - mock mode never has a hint.

**The cause is in the contract, not only the code.** §3 says the state is "Cleared only with the session (WaveService.Reset)".
But a reserved server serves exactly one hub departure: `ExpeditionService.Depart` reserves a new server every time. A
later session on the same server is a failed-trip rejoin, a late member, or a stale run-list join, never a new departure.

**Fix:**
- Make the auto-start once per server.
  - `WaveService.Reset` clears `boot.depart` and `departBeat` but leaves `boot.departOpened` true.
  - Re-aim the `resetOpened` pin to count 0, worded "a later session on this server never opens it again".
  - Add a mutant that puts `boot.departOpened = false` back in Reset.
- The R lever still works: `FakeDepart` writes `boot.depart` directly.
- Alternative: open the depart only from an `"arrival"` join (pass `kind` through `OnAdmitted`). The first option is simpler
  and also covers a proving boot after a failed trip.

## Minor

### m1. Deviation 3 keeps a run-list arrival from holding the countdown, but the start at zero still checks every body, so that arrival can turn the auto-start into a refusal

**Where:**
- `WaveService.luau:2112-2160`: `tickDepart` waits only for the holders' bodies (the expected members present).
- `WaveService.luau:1967`: `startLevel` refuses `"busy"` unless `VitalsService.AllHaveBodies(members)` holds for every
  member.

**What is wrong:**
- The session is published at wave 0 while it is `waiting` or `counting`, so a public or friend arrival can be admitted
  during the 5 s countdown.
- If their character is not standing at zero, `startLevel` answers `"busy"`. `DepartRefused` then leaves the level
  `picked`, and the leader gets a refusal toast for a start they never asked for.
- The contract's "a non-expected arrival never holds the countdown" holds. But the arrival does something worse than hold
  it: it cancels it.
- It is rare, because `CharacterAutoLoads` is on and the profile load usually outlasts the spawn, but it can happen.

**Fix (either):**
- Give `DepartStep` a second fact `allBodies` (every member present), and hold `counting` at zero until it is true.
  - Bound the hold by the wait cap counted from zero, then pick.
  - The view then reads "starts in 0" for that moment.
- Or let `startLevel`'s body rule skip a non-expected member admitted less than a second ago, placing them as `waiting`.

### m2. The pins hold the auto-start's call lines but not its conditions: 19 of 20 probes pass `PASS (4,994 checks)`

Every probe below passes the harness unchanged. The services cannot load in the harness, so these lines are guarded only
by the text pins, and the pins count calls, not the conditions around them.

| # | Mutation | Effect if shipped |
|---|---|---|
| 1 | `openDepart`: drop `if boot.departOpened then return end` | Every admit re-opens it: a late arrival or a rejoin after a run re-arms the auto-start |
| 2 | `openDepart`: drop `boot.departOpened = true` | Same |
| 3 | `tickDepart`: `if refusal ~= nil` → `== nil` | Every successful start is followed by `DepartRefused` (picked after the run) and a toast with no reason |
| 4 | `tickDepart`: no player at zero → `nil` instead of `"notLeader"` | No fallback: the depart stays `done` silently |
| 5 | `tickDepart`: the beat's `broadcast()` never runs | The countdown reaches clients only at `stateHz` |
| 6 | `ExpectedIn`: the inner `return false` → `continue` | The countdown starts with the party still travelling; late members land in a live run as `waiting` |
| 7 | `ExpectedIn`: drop the `session.open` / `ticketPending` guard | Answers during the ticket read |
| 8 | `PartyIn`: the cap → `return false` | A party missing a member can never start, not even by hand |
| 9 | `FirstArrivalAt` → 0 | The wait counts from the admit's tick instead (masked by openDepart's fallback) |
| 10 | `openDepart`: `since = 0` | `waiting` turns into `picked` on the first tick (os.clock() is far past 30) |
| 11-12 | Main `hintPair`: drop `levelId == ""` or the difficulty cap | Shape rules unread |
| 13 | `readTicket`: drop the `levelId` type check | Old-shape tickets reach the match |
| 14 | `ResolveTicket`: drop `ticket.difficulty ~= difficulty` | A ticket for Hard verifies a Normal hint |
| 15 | The mock ticket names `""` instead of the hint | Studio's mock verification is never exercised |
| 16 | `OnStartLevel`: drop the `broadcast()` after `DepartAsked` | A refused manual start leaves the countdown line up until the next `stateHz` broadcast |
| 17 | `pushRunFields`: `depart = nil` | No client ever sees the countdown or the pick, but the level still starts by itself |
| 18 | `BuildRunState`: drop `depart` | Same |
| 19 | `EndRun`: `if given ~= nil` → `and given.valor > 0` | Deviation 5's "a line for a family-only first clear" is undone |
| 20 | The start at zero by `GetHostUserId()` instead of `LeaderUserId()` | "Whoever leads at zero" is undone |

The one probe that failed was `admitEra`. The `resetOpened` pin is the one that enforces M1.

**Fix:**
- Move the per-tick decision into StageFlow as a pure function: the members, the expected set, the host and the bodies in,
  the holders and the facts out, so the harness drives it.
- Pin the remaining conditions with their indentation (#1, #3, #6, #17, #18 at least), and add mutants for them in
  `mutate.py`.
- RunRegistry and Main are under no gate at all. A pure `TicketMatches(ticket, levelId, difficulty, serverId)` in
  RunRegistry or MapRules would make #13-#14 testable.

### m3. Deviation 4: in a party, the raiders line counts bodies shared, while the same city card prints kills

**Where:**
- `src/combat/server/Services/RunCredit.luau:61` adds `CREDIT_COUNT` (1) on every credit.
- `WaveService.luau` `credit` credits every member in the body's damage tally, with `kills` set to 1 only for the killer.
- `src/client/UI/RunTally.luau:319-320` shows the count only on the raiders row ("Raiders ×n").
- `src/client/Controllers/UIController.luau:920-923` puts "· n kills" from `summary.kills` in the city card's subtitle.

**What is wrong:**
- In a solo run the count equals the kills (112 raiders, plus the Chief on his own line).
- In a party a member's count is every body they damaged. Example: one city card reads "9:40 · 25 kills" and "Raiders ×60".
- For every other kind, one per event is right: a camp, a chest, a key, a first clear, a mentor payment.

**Failure scenario:** a party of two splits Forest Road. Each city card shows a raiders count about twice its kill count,
and nothing on the card says which is which.

**Fix (either):**
- For kill keys (`raiders`, `boss`), count by the credit's `kills` (1 for the killer, 0 for a share-only credit), and keep 1
  per event for the other kinds. Solo cards stay identical, and `RunTally` already drops "×0".
- Or drop "· n kills" from the city card's subtitle (slice 3).

### m4. P's pay era is written into the profile by every later run; "neither writes the profile" is not what happens with API access on

**Where:**
- `src/combat/server/Services/DebugService.luau:57` says "Neither writes the profile."
- The contract §13.7 says "R and P never write the profile".
- `WaveService.luau` `credit` pays `state.cash += share.cash` at `RunCredit.PayEra(member.cashEra, boot.cashEra)`.

**What is wrong:**
- P writes only `boot.cashEra`, but every kill and camp bonus after it pays real cash at that era into the loaded profile:
  ×670, ×34,000 or ×1,400,000, times Legacy.
- In `build\proving.rbxl` the profile is the mock, so nothing persists.
- But P is bound in every Studio mission boot, `combat.rbxl` included, and `DEBUG_HINT` advertises it there.
- The §9 B bridge test plays on Ben's real save with API access on. One P-boosted Forest Road clear there writes a clear's
  cash × 1.4M into his city.

**Fix (either):**
- Make P inert unless `DataService.IsMockMode()` or `boot.proving`.
- Or correct the comment and §13.7, and have the docs-keeper put the GrantLegacy-style "This is real, not sandboxed" line
  beside P in PLAYTEST.

## Suggestions

### s1. A stale comment over `onCrowdKilled`

`WaveService.luau:985` still says "The boss pays the Mentor bonus first, from its own book". Since deviation 5 it pays it
after the boss's own credit.

### s2. A throw inside the auto-start's `startLevel` leaves it `done` with no fallback

**Where:** `WaveService.luau:2136-2149`. `DepartStep` has already set `done` when `startLevel` runs from the Heartbeat.

**What happens on a throw:**
- The pcall guards only the Plan inside `startLevel`.
- So a throw elsewhere (a Build, a placement) loses the rest of that tick.
- It also never reaches `DepartRefused`. The party sees nothing, not even the pick, and Output shows only the error.

**Fix:** wrap the call: `local ok, refusal = pcall(startLevel, ...)`, and treat `not ok` as `"unavailable"` with the same
warn and toast.

### s3. Per-frame work after the depart is over

**What it does:**
- `tickDepart` runs on every lobby Heartbeat for the rest of the session.
- Each frame it refills the holders, loops `ExpectedIn` and `AllHaveBodies`, and calls `DepartView` and `DepartBeat`.
- While the depart is `picked` that allocates a view table and a string every frame, until the leader starts a run.

**Fix:** return early when `depart.state == "done"` once `boot.departBeat == ""`. For `picked`, compute the beat only on a
state change. The cost is negligible on a server, so this is tidiness only.

### s4. A leader's premature tap cancels the auto-start the party is waiting for

**What happens:**
- During `waiting`, a leader who opens the map and presses Depart gets `"busy"`, because `PartyIn` is false while members
  travel.
- Deviation 1 then ends the depart.
- When the party arrives nothing starts and nothing is shown.

This follows the contract's "any start the leader asks → done". Consider ending it only on an accepted start, or on a refusal
other than `"busy"`. It is Ben's call.

## The accepted deviations, judged

1. **The leader's own Start ends the auto-start in any state: correct.**
   - Ending `picked` costs nothing visible: the client opened the map once per pick already.
   - After any run the depart reads `done`.
   - `"notLeader"` (the first check in `startLevel`) never ends it.
   - See s4 for the refused-ask edge.
2. **"Leader present" = the session host in the roster: correct.**
   - `LeaderUserId` falls back to `partyOrder[1]`, so it is always somebody.
   - The hub's `expected` list always holds the departing leader, and the ticket is keyed by that leader.
   - So `ExpectedIn and HostIn` reads "everyone came at least once, and the one who departed is here now".
3. **Only expected members' bodies hold the countdown: correct for the hold, incomplete at zero** (m1).
4. **Each credit adds 1: coherent for camp, chest, key, first clear, mentor and boss, but not for raiders in a party** (m3).
5. **Mentor paid after the boss line: correct.**
   - `payMentors` reads only the tally, `waiting`, `incomeRate` and the profile it adds Valor to, none of which `credit` writes.
     So the Valor is identical.
   - The effects now go `bossDown` then `mentor`, the better order.
   - Only a stale comment is left (s1).

## Checked and clean

- **Only a verified ticket arms `waiting`.**
  - `Pick` requires `session.ticket ~= nil` and a non-empty level.
  - The mock ticket of a Studio mock session carries the empty hint of a standalone boot, so `combat.rbxl` or `proving.rbxl`
    alone opens nothing without the proving switch or R.
  - A hint alone gives `picked`. No hint gives nothing.
  - An old-shape hint (`missionId`) reads as `NO_LEVEL` in `hintPair`, and an old-shape ticket reads as none in `readTicket`.
- **Nothing auto-starts after a run inside one session.**
  - `backToLobby` never touches `depart` (pinned).
  - The only ways into a run are `OnStartLevel`, which runs `DepartAsked` and ends it, and the tick's own start, which ends
    at `done`.
  - So every return to the lobby finds it `done`. M1 is the one way round this, across sessions.
- **The wait cap, a missing member, the leader leaving, a new leader without the stars, a late arrival after `done`, solo:**
  - each follows §3 through `DepartStep` (cases in "step", "session" and "asked");
  - the start at zero is `startLevel` for `LeaderUserId()` at that moment;
  - a refusal leaves the level `picked` with a warn and the leader's toast;
  - `CheckAdmission` still sends an expected late arrival to the lobby as `waiting` and refuses a non-expected one during a
    live phase.
- **`provingAutoStart` is Studio-only twice:** through `boot.proving` (CombatMode) and an explicit `RunService:IsStudio()`
  in `openDepart`. The live place cannot reach it.
- **R and P are Studio-only.** The gates are `DebugService.OnRequest`'s `isStudio`, `pollAttributes` only from a Studio
  Heartbeat, and the explicit checks in `FakeDepart` and `NextCashEra`.
  - `RequestDebug`'s 64-byte value cap holds the longest pair (32 + 1 + 12).
  - `DepartPair` falls back to the proving pair on anything malformed.
- **`cashEra` is frozen at the admit.**
  - `ArenaService.Admit` is its only writer (pinned).
  - `runJoinSequence` returns before any admit when the profile is nil, so `EraOf` reads a real profile.
  - A rejoin goes through `Remove` first, so it gets a fresh member from the reloaded profile.
  - It is read per member at the one choke point, with Legacy and Founder's on top.
- **Every credit site writes its line.**
  - The five `CreditSummary` calls plus `CreditMentor` carry a key.
  - The boss key applies only to the body whose death pays the boss's Valor.
  - The totals still count past `RunLines.MAX`, and the lines add up to the totals in the "sites" case.
- **The last wallet goes after the last credit and before the card.**
  - `sendWallets(os.clock(), true)` follows the first-clear credits and their `walletDirty`, and precedes `pushRunFields` and
    `BroadcastSummary`.
  - No credit can follow the card: kills and chests run only in live phases, and the mentor pays on the boss's kill.
  - The "open" action (the boss room's bonus) runs before "end" in the same batch.
- **The MapRules move changed no behaviour.**
  - `Startable`'s `locked` is the old node loop.
  - Its two `unavailable` rules were already `resolveLevel`'s answer.
  - `check_stage_mirror.py` passes with its StageFlow `NEEDED` list unchanged.
  - SecretFlow keeps `finite` for `Triggered` and re-exports `Site` and `Reward`.
- **Starting from the Heartbeat is safe.** `startLevel` does not yield: `LevelService.Build` and `Clear` never yield.
- **The leave card carries no depart.** ReturnService builds it with phase `"summary"`.
- **The Studio ticket ids agree.** The hub's `STUDIO_ACCESS_CODE` and RunRegistry's `STUDIO_PRIVATE_SERVER_ID` are both
  `"studio"`.
- **`StageFlow.Validate`'s `note` rule** names a non-string, an empty string and anything over 24 bytes, once each.
- **§6 deletions:** `git grep` of the §12 names over `src/combat/server` is empty, and `PartyIn` keeps its one reader.

## Probe recipe

- `py/probe.py <tree> <luau> <probes.json>`, in the scratchpad's `l4-w3-rev2/` folder. Each probe is
  `[label, [[file, old, new], ...]]`.
- It runs the tree's own harness and restores the files, in about 25 s a probe.
- `py/mk1.py` and `py/mk2.py` write the JSON.
- For luau-lsp, write the sourcemap to scratch with `rojo sourcemap combat.project.json -o <scratch>`, run from the worktree.
  The archive's `Packages` are incomplete, so the copy cannot build one.
