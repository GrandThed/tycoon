# L4 W3 — luau-engineer B (combat place server) report

Contract: `docs/prompts/l4-w3-contract.md`, sections:
- §2.1: the re-pointing, and the move out of StageFlow and SecretFlow.
- §2.3, §3, §5, §7 (`note`), §9 (R and P), and L4W3-12.
- §4.1: the credit sites.
- §6: my rows.

Relays adopted:
- `relay-a.md`: MapRules, RunLines, Types, `CombatCashMult`.
- `ui-b.md`: the client reads `RunState.depart` only in the lobby, plus the R and P keys.
- The lead's relay: `provingAutoStart` becomes true.

Nothing is committed or staged.

## Files

| File | What |
|---|---|
| `src/combat/server/Services/RunCredit.luau` (new, pure) | The §4.1 credit keys; `Credit` and `Mentor` on a card (totals plus `RunLines.Add`); `Empty(title)`; the pay era (`EraOf`, `PayEra`, `NextPayEra`). |
| `src/combat/server/Services/StageFlow.luau` | The map section and `Stars` move out to MapRules. The depart rule moves in: `DepartOpen`, `DepartPair`, `DepartStep`, `DepartAsked`, `DepartRefused`, `DepartView`, `DepartBeat`. Validate gains the `note` line. StageFlow requires nothing new. |
| `src/combat/server/Services/SecretFlow.luau` | `Reward`, `Site`, `whole`, `rewardOf`, `Sites` and `MapRow` move to MapRules. It re-exports `Site` and `Reward` and keeps its own `finite`. |
| `src/combat/server/Services/WaveService.luau` | Points at MapRules. `tickDepart` replaces `tickAutoStart`. Every credit site has a key. The pay era is applied at the choke point. The last wallet goes out after the last credit and before the card. Holds the R and P levers. |
| `src/combat/server/Services/ArenaService.luau` | The session holds `levelId` and `difficulty`. New: `Pick`, `ExpectedIn`, `HostIn`, `FirstArrivalAt`, `RunFields.depart`. `cashEra` is set at the admit. Both cards are written through RunCredit. |
| `src/combat/server/Services/RunRegistry.luau` | The ticket, the mock ticket and the published entry carry `levelId` and `difficulty`. An old-shape ticket reads as none. |
| `src/combat/server/Services/ReturnService.luau` | The zero card is `RunCredit.Empty`. The leave card's name is `summary.title`. |
| `src/combat/server/Services/DebugService.luau` | The `fakeDepart` (R) and `cashEra` (P) levers and their attributes. |
| `src/combat/server/Services/CombatRemotes.luau` | The level-id and difficulty caps come from MapRules. |
| `src/combat/server/Main.server.luau` | The hint is `(levelId, difficulty, hostUserId)`, with `NO_LEVEL` for none. The Snapshot's `gearPower` and the Armory require are gone (row 6). |
| `tools/crowd_harness/tests_l4w3_run.luau` (new) | 216 checks in 13 groups plus the pins group. It is last in TESTS, so it ends with the verdict line. |
| `docs/prompts/l4-w3-reports/luau-b-pins.py` | The pins for `run_harness.py`. **The designer has pasted it.** |
| `docs/prompts/l4-w3-reports/luau-b-mutants.py` | 75 mutants for `mutate.py`. **The designer has pasted it.** |

## Contracts implemented (signatures)

```lua
-- StageFlow (pure; §3)
export type DepartState = "waiting" | "counting" | "picked" | "done"
export type Depart = { levelId: string, difficulty: string, state: DepartState, startsAt: number, waitFrom: number, standIn: boolean }
export type DepartInput = { now: number, expectedIn: boolean, hostIn: boolean, bodies: boolean, waitSeconds: number, countdownSeconds: number }
StageFlow.DepartOpen(levelId, difficulty, verified: boolean, proving: { levelId, difficulty }?, since: number): Depart?
StageFlow.DepartPair(value: any, fallbackLevel: string, fallbackDifficulty: string): (string, string)
StageFlow.DepartStep(depart: Depart, input: DepartInput): "start"?
StageFlow.DepartAsked(depart: Depart?): boolean
StageFlow.DepartRefused(depart: Depart): ()
StageFlow.DepartView(depart: Depart?, now: number, inLobby: boolean, waitSeconds: number): Types.RunDepart?
StageFlow.DepartBeat(view: Types.RunDepart?): string
-- RunCredit (pure; §4.1, §5)
RunCredit.Empty(title: string): Types.RunSummary
RunCredit.Credit(summary, key: Types.RunLineKey, cash, material, materials, valor, kills): ()
RunCredit.Mentor(summary, valor): ()
RunCredit.KillKey(boss: boolean, kind: string, bossName: string?) / CampKey(id, name) / FirstClearKey(levelId, difficulty)
	/ ChestKey(id, name) / KeyKey(key, keys?) / MentorKey(): Types.RunLineKey
RunCredit.EraOf(state: { era: any }?): number      -- the era frozen at the admit (bad or missing -> 1)
RunCredit.PayEra(cashEra: number, override: number?): number
RunCredit.NextPayEra(current: number, eraCount: number): number
-- ArenaService (§2.3, §4.1)
ArenaService.OpenSession(levelId: string, difficulty: string, hostUserId: number, arrivalName: string): ()
ArenaService.Pick(): (string, string, boolean)     -- the hint's pair, and whether a ticket verified it ("" = none)
ArenaService.ExpectedIn(): boolean                 -- every ticket.expected id admitted once (true with no ticket)
ArenaService.HostIn(): boolean
ArenaService.FirstArrivalAt(): number
ArenaService.CreditSummary(userId, key: Types.RunLineKey, cash, material, materials, valor, kills): ()
ArenaService.CreditMentor(userId, valor): ()       -- adds the { "mentor", "mentor", "" } line
-- RunRegistry (§2.3)
RunRegistry.ResolveTicket(hostUserId: number, levelId: string, difficulty: string): Types.RunTicket?
-- WaveService (§9)
WaveService.FakeDepart(levelId: string, difficulty: string): boolean
WaveService.NextCashEra(): (number, number)        -- the era now paid at, and its EraCashMult
```

## Behaviour, briefly

- **The auto-start (§3).**
  - The session's first `OnAdmitted` opens it from `ArenaService.Pick()`:
    - a verified pair waits;
    - a hint the ticket did not verify (no ticket, a mismatch, an old shape) is picked;
    - no hint opens nothing.
  - A proving boot with `debug.provingAutoStart` waits on `provingLevel` / `provingDifficulty`, with the players present
    standing in for the expected list and the host (L4W3-12).
  - `tickDepart` runs every frame in the lobby. It gathers the facts, `StageFlow.DepartStep` decides, and at zero it
    starts the level once, through `startLevel`, for whoever leads at that moment.
  - A refusal leaves the level picked, sends the leader today's `startLevel` ActionResult toast and writes one warn. It
    is never retried.
  - It broadcasts at once whenever `DepartBeat` changes: on a state change, and at each whole second.
  - `backToLobby` never touches it, so **nothing auto-starts after a run**. Only the session's end (`Reset`) clears it.
  - The leader's own `RequestStartLevel` (any level, started or refused) ends it.
- **`provingAutoStart` cannot act on a live server.** WaveService reads it in exactly one place, `openDepart`, behind
  `boot.proving` (which `CombatMode` sets only under `RunService:IsStudio()`) and an explicit `RunService:IsStudio()`
  check. The pin `openStudio` and the mutant "l4w3b pins: proving outside Studio" hold that line. On a live server only
  a verified hub ticket can start anything by itself.
- **The cards (§4.1).**
  - Every credit names its source. Line counts add 1 per credit:
    - raiders: one per body whose reward that member shared (their own kills in a solo run);
    - camp, chest, key, first clear, mentor: one per event.
  - A boss line is the run's boss: the body whose death pays the boss's Valor (`id == run.bossId`), named
    `run.bossName`.
  - **The run's last wallet goes out after its last credit, and before the card.** `sendWallets(…, true)` moved from
    the top of `EndRun` to just before `BroadcastSummary`, after the first-clear grants. A first clear marks its wallet
    dirty.
- **Run cash by era (§5).** `cashEra = RunCredit.EraOf(state)` is set at `ArenaService.Admit`, beside `incomeRate`.
  `credit` pays at `Combat.CombatCashMult(state, gameConfig, shopConfig, combatConfig.rewards, RunCredit.PayEra(member.cashEra, boot.cashEra))`.
  Nothing writes a member's era after the admit. `boot.cashEra` is the P lever's override for the session.
- **`note` (§7).** Validate names a `difficulties.<d>.note` that is not a string of 1 to 24 bytes.
- **Levers (§9).**
  - `RequestDebug("fakeDepart", "<levelId>:<difficulty>")`: anything else uses the proving pair. The attribute is
    `DebugFakeDepart` (string). It works in the lobby only; elsewhere it shows the notice "Depart works in the lobby
    only".
  - `RequestDebug("cashEra", "next")`: the attribute is `DebugCashEra` (any number above 0 is one step, as A's Types
    comment says). The first press steps from the leader's frozen era. Notice: "Pay as <Era displayName>
    (×<Format.Cash(mult)>)", e.g. "Pay as Boomtown (×670)", "Pay as Metropolis (×34K)", "Pay as Orbital Colony
    (×1.4M)", "Pay as Village (×1)".
  - Both are Studio only (DebugService, and again in WaveService) and save nothing.

## Gates (final, on the real worktree, 2026-10-23 15:20)

- **stylua / selene** on `src/combat/server`: clean, 0 errors, 0 warnings. My case file is also stylua-formatted.
- **luau-lsp** with the combat sourcemap (`src/combat src/shared`): 0 errors.
- **check_compile.py:** PASS, 187 files. Top-level locals: WaveService 104, ArenaService 67, StageFlow 56, DebugService
  51, Main 49, RunCredit 7.
- **run_harness.py:** `HARNESS: PASS (4,994 checks)` with everyone's code in. `tests_l4w3_run.luau` holds 216 of them:
  145 rule cases, 1 view check, 70 pin checks.
- **check_stage_mirror.py:** PASS. Its `MODULES` list is unchanged, and so is StageFlow's require list.
- **mutate.py filtered to my files:** **480 run, 0 not caught.**
  - The 480 entries include the 75 `l4w3b` ones. They ran in 4 processes of 120, with their own roots
    (`mutant_luauB_<k>`) and bundles. Each log ends `MUTATIONS: 120 run, 0 not caught`, after a baseline
    `HARNESS: PASS (4,988 checks)`.
  - The run finished at 14:15, before the session cut at 14:50. My files last changed at 13:01, before it started, so
    it covers the code as it stands.
  - The harness has gained 6 checks since (4,988 → 4,994). None of those changes is mine, and no entry text changed:
    every one of the 480 occurred exactly once when the run started.
- **§12 git grep:** empty over `src`. The untracked `RunCredit.luau` was grepped directly: empty.
- **Leftovers removed:** `bundle-luauB.luau`, `bundle_luauB_*.luau`. The `mutant_luauB_*` roots were removed by
  mutate.py itself.
- **No pinned line changed after the designer pasted the pins.**

## `debug.provingAutoStart` acts only in a proving Studio boot

`Combat.json` now has it `true`. WaveService reads it in exactly one place, `openDepart`, behind two Studio checks:
- `boot.proving`, which `CombatMode` sets only under `RunService:IsStudio()` with the baked `DebugProving` attribute;
- an explicit `RunService:IsStudio()`.

There it opens `waiting` on `provingLevel` / `provingDifficulty`, with the players present standing in for the expected
list. The pin `openStudio` and the mutant "l4w3b pins: proving outside Studio" (caught) hold that line. A live combat
server cannot auto-start from it: only a hub ticket the server verified opens `waiting` there.

## Deviations, and why

1. **`DepartAsked` ends the auto-start from any state, `picked` included.** The contract says "waiting or counting →
   done". Ending `picked` too means a picked level never outlives the run the leader then plays: after the run the
   depart reads `done`, and nothing is shown again.
2. **"The leader is present" = the session's host is in the roster (`ArenaService.HostIn`).** `LeaderUserId` falls back
   to the first member, so "a leader present" would always be true. A stand-in (a proving boot, R) ignores the host
   check.
3. **The countdown waits for the bodies of the expected members present** (everyone present with a stand-in), not of
   every member. This keeps "a non-expected arrival never holds the countdown". At zero, `startLevel` still checks
   every body.
4. **`startsIn` / `waitIn` are whole seconds,** rounded up on the server and never below 0, so the client shows them as
   they are.
5. **A first-clear line appears for any first clear that gave something.** Its Valor may be 0 when the clear gave only
   a family; the family is in `RunResult.firstClear`.
6. **The mentor bonus is now paid after the boss's own credit,** so a card shows the boss line before the mentor line
   (first-credit order). Only the order of two writes changed; the Valor is the same.
7. **New pure module `RunCredit`.** It is not named in the contract. It lets the harness load the keys and the card
   writes, and it is the one home of the zero card (ArenaService and ReturnService).
8. **The `cashEra` attribute is a step,** not an era number, as A's Types comment says.

Two Studio-only hardenings, not deviations: an explicit `RunService:IsStudio()` on the proving path, and on
`FakeDepart` / `NextCashEra`.

## For the other owners

**economy-designer**
- Already done on your side, and seen working:
  - `RunCredit` is in `run_harness.py` SOURCES and `mutate.py` FILES.
  - `luau-b-pins.py` and `luau-b-mutants.py` are pasted.
  - The row-6 Power pins are removed.
  - The `leverAward` / `leverLevel` re-aims are done.
- **No existing entry or pin on my files went stale.** Two of my new lines would have doubled an entry's text, and I
  reworded my code so they don't (no action needed):
  - `l3: the first-clear lines come in the table's order` (`\ttable.sort(names)`): `noteProblems` sorts into `sorted`
    instead.
  - `l3fix R4: the lever pays on a live server` (`if not boot.mission or not RunService:IsStudio() then`): `FakeDepart`
    and `NextCashEra` write `if not RunService:IsStudio() or not boot.mission`.
- Lines I changed that a pin or mutate entry may read (old → new):
  - `WaveService.GrantStars`: `if not StageFlow.Award(stars, levelId, difficulty) then` → `if not MapRules.Award(stars, levelId, difficulty) then`
    (`run_harness.py` `leverAward` / `leverLevel`; `mutate.py` "l3fix R4: an old lever star pays again" and the F3 pair).
    Already re-aimed.
  - `WaveService.startLevel`: the `StageFlow.NodeState(...)` node loop → `MapRules.Startable(map, builtLevels(), starsOf(member.userId), levelId, difficulty, if file ~= nil then file.difficulties else nil)`.
  - `WaveService.EndRun`:
    - `sendWallets(os.clock(), true)` moved from after `local reason = flow.ended or asked` to before `pushRunFields()`.
    - `ArenaService.CreditSummary(member.userId, 0, "", 0, given.valor, 0)` → `ArenaService.CreditSummary(member.userId, key, 0, "", 0, given.valor, 0)`,
      now under `if given ~= nil then`.
  - `WaveService.onCrowdKilled`: `if info.boss and id == run.bossId then` → `local boss = info.boss and id == run.bossId`
    / `if boss then`. `payMentors(combatConfig, tally)` (same text, two tabs) moved after the `credit(...)` line.
  - `WaveService`: `tickAutoStart` → `tickDepart`; `boot.lobbySince` removed; `provingStartDelay` removed.
  - Combat `Main.server.luau`: the `gearPower = …Armory.SavedPower(…)` block and `local armoryConfig` /
    `local provingConfig` are removed (row 6).
- **`Combat.json debug.provingAutoStart: true`** is needed for L4W3-12 (the lead has relayed that you set it).
- Suggested mutants for the depart rule, the lines and the pay era: the 75 in `luau-b-mutants.py`, already in
  `mutate.py`.

**ui-engineer B** (matches `ui-b.md`; nothing more needed)
- **Depart states.** `RunState.depart = { levelId, difficulty, state: "waiting" | "counting" | "picked", startsIn?, waitIn? }`.
  - It is nil when there is none, once done, and outside the lobby.
  - `startsIn` (counting) and `waitIn` (waiting) are whole seconds, already rounded up.
  - A new RunState goes out at every state change and every whole second.
  - An auto-start refusal reaches the leader as `ActionResult { action = "startLevel", slotId = levelId, reason }`, the
    same as a manual refusal.
- **Line order.** Lines come in first-credit order. A typical first Forest Road clear reads:
  1. raiders;
  2. camp bonuses, as each camp clears (a camp line appears only when its bonus pays);
  3. chest, then key, wherever they fall;
  4. boss;
  5. mentor;
  6. firstClear, credited at `EndRun`, so always last on a run card.

  The session card (the hub's) merges by `kind` + `id` across runs. A key line has count 1 and zero amounts.
- **Toasts.** R shows none on success (the countdown line is the answer); outside the lobby it shows "Depart works in
  the lobby only". P shows "Pay as <Era> (×<n>)". Both are server `RunFx` notices.

**luau-engineer A:** nothing required. The ticket I read is `{ accessCode, privateServerId, levelId, difficulty, public, expected }`.
The teleport data and the Studio record I read are `{ levelId, difficulty, hostUserId }`, held to MapRules' caps. Both
match `relay-a.md`.

**Lead:** no remote and no project-file change. I regenerated `sourcemap.combat.json` once early in the session (a
generated file).

## What to check in Studio

1. `build\proving.rbxl` (with `provingAutoStart` true), Play alone.
   - Expected: the lobby shows "Forest Road · Normal starts in 5", counting down, and the level starts.
   - In Output: no "auto-start … refused".
2. N to the clearing (never B), and beat the Chief. On the card:
   - lines appear in the order above (Raiders ×n, the camp bonuses, the Camp Chief, a first clear on a new star);
   - the wallet line ends at the wallet the top bar shows.
3. Back to camp: nothing starts by itself.
4. R: the countdown on the map's selection, and a start.
5. P twice: the notice reads "Pay as Metropolis (×34K)". Then a run's cash rows are about 34,000 × larger than on
   Village (a fresh profile is Village, ×1).
6. R during a run: the notice "Depart works in the lobby only".
7. The bridge (§9 B, API access on):
   - `test.rbxl` Depart, then `combat.rbxl` Play: the countdown, the level, Return.
   - The hub card carries the same lines under "Expeditions".
