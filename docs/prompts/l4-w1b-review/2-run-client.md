# L4 W1b review — slice 2, the run and the client

Reviewer: roblox-reviewer, 2026-10-21. Branch `l4-w1b` at 1ae8bfb (review brief d5635a2). Diff read:
`git diff l4-real-forest...l4-w1b` (base 1d3b0d2) for `ArenaService`, `WaveService`, `tests_l4b_run.luau`,
`InputController`, `CombatUIController`, `CombatFxController`, `CameraController`, `WeaponController`, `CombatHud`,
combat `DebugPanel`, `Main.client`, `MapScreen`, `Theme`, plus the new `src/shared/RunFloors.luau` they call. Read only.
The only file written is this one. Probes ran on a `git archive HEAD` copy in my scratchpad.

**Count: 0 Critical, 0 Major, 2 Minor, 3 Suggestions.**

## Minor

**m1. L4B-8's client half, and the branch in `sendRunState` that swaps the cells in, are under no gate. Seven
review-only mutants survive, each with `HARNESS: PASS (4,075 checks)`.**
- Where:
  - `src/combat/client/Controllers/CombatUIController.luau:1597-1598`: `fresh = RunFloors.Merge(held, st.floorsSeq,
    fresh, seq)` and `st.floorsSeq = seq`.
  - `CombatUIController.luau:1676`: the `applyFloors(run.floors, if typeof(run.floorsSeq) == "number" ...)` call.
  - `src/combat/server/Services/ArenaService.luau:653-654`: `if cellsWent then` / `sent = table.clone(runState)`.
- What is wrong:
  - `run_harness.py` and `mutate.py` name `CombatUIController` nowhere. The client's merge wiring has no pin and no
    mutant.
  - `tests_l4b_run.luau` proves `RunFloors` through a hand copy of the bookkeeping, `L4R.Server` and `L4R.receive`.
    That is the pattern of "the harness tests a copy".
  - The `L4B_LINES` pins on `sendRunState` (`run_harness.py:1461-1464`) count the Attach line, `sent.floors =
    floors` and the note. They do not count the condition that decides whether the cells go.
- Mutants I ran, all surviving:

  | # | Where | Mutant |
  |---|---|---|
  | 1 | client | delete the `fresh = RunFloors.Merge(...)` line |
  | 2 | client | delete `st.floorsSeq = seq` |
  | 3 | client | `applyFloors(run.floors, 0)` |
  | 4 | client | `RunFloors.Merge(fresh, st.floorsSeq, fresh, seq)`, merging against the incoming list |
  | 5 | server | `\tif cellsWent then` becomes `\tif false then` |
  | 6 | server | `sent.floors = runState.floors` added after the swap |
  | 7 | server | `if cellsWent or true then`, so the cells go on every send |

- Failure scenarios:
  - **Mutants 1 to 4.** The client takes the first RunState's cells, then takes the bare floors of the next one. A
    plateau brute's drawn charge then stops at its camp's rectangle (`CrowdRenderer.laneReach`, the `cells == nil`
    branch) while the server's body runs on along the region. That is the L1b-W4-33 mismatch, back with every gate
    green.
  - **Mutants 5 and 6.** No client ever gets a cell.
  - **Mutant 7.** The wave's whole gain, about 0.9 KB per RunState per member on Forest Road, is undone in silence.
- Fix: add whole-line pins with their indentation, and a mutant for each line:
  - in `applyFloors`, the Merge line and the seq line, with the Merge line before the `local same = #fresh == #held`
    line;
  - in `onRunState`, the call line;
  - in `sendRunState`, `\tif cellsWent then` and `\t\tsent = table.clone(runState)`.

  A pin on `CombatUIController` needs a new body regex (`local function applyFloors\(`), because the file has no
  pins yet.

**m2. The one RunState that carries a set's cells is also the one that runs the new-level branch first. One throw there
loses the cells for the whole run.**
- Where: `CombatUIController.luau:1639-1676`.
- What is wrong:
  - `startLevel` sets the new floor set and the new `levelId` together (`WaveService.luau:1885` then `SetLevel`). So
    the first RunState of a seq is also the one where `run.levelId ~= st.levelId`.
  - `onRunState` handles that RunState in this order:
    1. `debugPanel.SetKinds(rewardedKinds(...))`;
    2. `SecretFx.SetLevel` (`:1645`);
    3. `faceFrom(placed)` (`:1652`), which runs `forwardPoint` → `routeForward` over the level JSON's route;
    4. `CrowdRenderer.Prewarm` (`:1669`);
    5. `paintWallet`;
    6. `applyFloors` (`:1676`), last.
  - Before W1b, a throw in any of these on one RunState cost nothing, because the next RunState, 0.25 s later,
    carried the cells again. Now the next one carries no cells, and the server has already noted the set as sent
    (`ArenaService.luau:657`).
- Failure scenario:
  1. A bad route entry in a new level's layout makes `routeForward` throw on the first RunState of the run.
  2. The handler stops before `applyFloors`, so `st.floors` keeps the lobby's `{}` and `st.floorsSeq` stays at the
     lobby's seq.
  3. The next RunState has the new seq and no cells, and Merge takes it as sent.
  4. The whole run plays with every region floor as its bare rectangle. That is m1's mismatch, from one bug elsewhere.
- Fix (cheap): call `applyFloors` right after `isRunState`, before the level branch. It reads only `st.floors` /
  `st.floorsSeq` and the payload, and nothing above it depends on the floors.
  - Optionally, say in the header comment that the cells are one-shot and must be applied before anything that can
    throw.

## Suggestions

**s1. `sendRunState` builds a bare copy of every floor for every member on every send, and then drops it.**
- Where: `ArenaService.luau:649-659`.
- What happens:
  - `RunFloors.Attach` always allocates `#floors` clones. When `cellsWent` is false, the copy is discarded, and
    `BuildRunState` has already built the bare copy that is actually sent (`:580`).
  - That is 3 clones per member per send at 4 Hz. It is trivial today but grows with L5's parties and longer levels.
- Fix: test `play.cellsSent[userId] ~= seq` before calling Attach.

**s2. The Studio strip's bottom reserve is one hint line short of what CombatHud stacks in Studio.**
- Where: `src/combat/client/UI/DebugPanel.luau:100-104`.
- The numbers:
  - `BOTTOM_BLOCK` is now 12 + 2 × (16 + 8) + 48 + 8 = 116 design px.
  - With a keyboard in Studio and the perf readout on, CombatHud stacks the Alt hint, the key hint and the perf line
    over the button row (`CombatHud.luau:626-632`). The perf line's top sits at 68 + 48 + 16 = 132 px.
  - When `ActionRows` wraps to two rows, everything rises another 56 px.
- Studio only, and no worse than before: the old 110 px reserve overlapped too.
- Fix: reserve three slots, or read `HudEdges`.

**s3. A stale comment in a hub file.**
- Where: `src/server/Services/ArmoryService.luau:50`. The comment still says "sticky like DebugBots", a lever this
  wave deleted.
- It is comment-only and in a hub file (lead's routing: no hub edits planned). Fix it with W3's hub pass.

## Checked and found clean

- **Cells once, server side:**
  - Every RunState goes through `sendRunState` (`ArenaService.luau:658` is the only `"RunState"` FireClient there).
    ReturnService's leave card (`ReturnService.luau:181`) is the only other sender: same seq, no cells, no note.
  - The note is cleared at `Admit` (`:1142`, after the `session.open` early return only) and at `Remove` (`:1338`),
    so a failed trip home, a rejoin and a fresh join each get the cells.
  - RunState is a reliable RemoteEvent with one client listener (`CombatUIController.luau:1966`), so the queue
    before the connection drains into the right handler.
- **Seq bookkeeping:**
  - `setFloors` (`WaveService.luau:363`) is the only writer of `run.floors` and of `boot.floorsSeq`. All three
    `run = freshRun()` sites (`:1358`, `:1879`, `:2350`) are followed by `setFloors` with no yield between.
  - `pushRunFields` hands `floors` and `floorsSeq` over in one table, so `ArenaService.runFields` always holds a
    matched pair.
  - Nothing mutates `run.floors` or its entries in place. `CrowdService.SetFloors` gets a separate list.
  - `boot.floorsSeq` never goes back for the life of the server, and `runFields.floorsSeq` 0 with `{}` matches the
    boot state.
- **Merge by index is safe:**
  - Within one seq the list's length and order never change.
  - `ReadCells(nil)` returns nil, not `{}`, so a bare floor really reads as "no cells sent".
  - The `same` early return in `applyFloors` keeps the old held list. That list equals the merged one by value, so
    the next Merge keeps the right cells (I checked the case of a new seq with value-identical floors).
  - The missing-seq fallback of 0 cannot keep another level's cells: the lobby's `{}` always empties `held` between
    levels.
- **Nothing else reads raw RunState floors:**
  - Every reader of `cells` gets the merged list: `CrowdRenderer.laneReach` through `SetFloors`, and
    `CameraController.SetFloors`.
  - `CombatHud.SetRunState` never reads `floors`, and `CampFloor` / `CampAim` read only the rectangle.
- **Bots and `ready` removed, with `player` never nil:**
  - All of these keep their answer for every human member: `humanPlayers`, `fightingIds`, `starsOf`,
    `sendMapState`, `payMentors`, `credit`, `onCrowdKilled`, `sendWallets`, `humanCounts`, `rescueFallen`,
    `moveFighters`, `standUpOnRoad`, `fallenReason`, `EndRun`, `backToLobby`, `advance`, `startLevel`,
    `tickSecrets`, the down source, `isDown` / `isEngaged`, `LeaderUserId`, `publishNow`'s `memberIds`, `Remove`'s
    and `ResetIfEmpty`'s empty test, and `watchCharacter`.
  - `OnAbandon`'s `#humanPlayers() <= 1` agrees with the HUD's `shown <= 1` (`CombatHud.luau:959`) and with the
    card's `members <= 1`.
  - `grep -i bot` over `src` finds only comments.
- **Collision groups:** the range arena's parts left the `CombatArena` group for Default. luau-b's report says that
  group "was never registered since P5", which is wrong: the old `newPart` called
  `EnemyService.ArenaCollisionGroup()`, which registers it. No behaviour moves anyway:
  - a fresh group collides with every group;
  - `BarrierGroups` copies Default's rule into `ArenaPlayers`;
  - nothing in `src` names `CombatArena` or `CombatRagdoll` now.
- **The range bench:** `ProvingGrounds.json` names only the `ProvingGrounds` arena (the only layout left). The
  crowd's own folder is `CrowdBodies`, with CanQuery false, so the camera's lost `Enemies` exclusion changes nothing.
- **CombatFx:** no server code sends any of the nine retired kinds, and no client branch waits for one. The new
  `CombatFxController` keeps `wave`, `bossDown`, `mentor`, `camp` and `notice`, and connects as early as before (the
  old `watchEnemies` ran on its own thread).
- **Input, on PC, touch and gamepad:**
  - The range path's binds (R2, L2, Y, L1, R1), the touch buttons and auto-fire are unchanged.
  - The C1 binds (R2, L1, R1, Y and `InputBegan`) were never bound with the range's combat, so nothing is left
    stray.
  - `cannotAct` and `autoMayTake` read `rangeState.phase`, with the same "lobby" default.
  - `setActiveSlot` calls `WeaponController.SetStance`, and both are idempotent, exactly as through the old
    `setStance`.
  - No caller is left for any removed API: `AttackDown/Up`, `UseAbility`, `ToggleStance`, `GetStance`,
    `SetStanceChanged`, `SetGear`, `SetAbilityReady`, `FaceToward`, `AdoptTouch`, `ArrivalDelay`, `Hitstop`, and the
    fx `SetMaterial/SetParty/SetHealth/SetHitMarkerHandler/SetBannerHandler`.
- **The HUD:**
  - The removed action layer was hidden in every mission (`actions = false`). The button row's base, `rowState.base`
    and every remaining tap target are unchanged.
  - `Shoot` without `fireKind` draws what the range's one `"semi"` call drew before.
- **The map:**
  - `Expeditions.json` has no `raiderArena` node or `bonus` theme, so the map shows no arena.
  - `difficultiesOf` is right for every shipped level. `recommendedTier` is required in `Types.LevelDifficulty` and
    read for every difficulty by `check_levels.py:5195`.
- **Theme:** all 81 deleted keys have no reader in `src` or `tools`; I grepped each one. All 996 keys left have a
  reader. `MIN_SCALE`'s list never held a combat size.
- **Code rules:**
  - Every file in the slice starts with `--!strict`.
  - No `wait`, `spawn`, `delay` or `_G`, and no parent argument in `Instance.new`, in any added line.
  - No CRLF in the repo.
- **Gates, in the worktree or scratch:**
  - stylua and selene on the slice: 0 errors, 0 warnings.
  - luau-lsp on both sourcemaps, written to scratch: 0 diagnostics.
  - `check_compile.py`: PASS, 176 files. InputController is at 117 top-level locals.
  - `rojo build` of the hub and the combat place: OK.
  - The harness on a `git archive` copy: PASS, 4,075 checks.
  - The git-grep tripwire from the contract §8: empty.
- **`tests_l4b_run.luau`:** its own rules are real. It loads the real `RunFloors`, and `regions >= 2` keeps the
  shipped case from passing empty. Its gap is m1: it cannot see the two services or the client.
