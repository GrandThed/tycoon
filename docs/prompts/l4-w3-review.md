# L4 W3 review — four slices (brief for four reviewers)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l4-w3`. The diff under review is `git diff dce50da..<the wave's
commit, named in your prompt>` (dce50da is the branch base, `main` with all of W1, W1b and W2), restricted to your slice.
**Read only: change no file except your own findings file.** Kill only your own PIDs; scratch work in your own scratch
folder (a `git archive` copy for probes); never run `mutate.py`, `mutate_shards.py` or an asset tool in the worktree. Tools:
`py` (`py -3.12` for `sim_range.py` and `check_levels*`); `export PATH="$HOME/.rokit/bin:$PATH"`; Luau CLI
`C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`; the harness `py tools/crowd_harness/run_harness.py <root> <luau>`.

## Read first

- `docs/prompts/l4-w3-contract.md`: rulings L4W3-1..18; **§14 is the lead's and overrides the draft**.
- `docs/MISSIONS_DESIGN.md` §26 (items 5-8), §30 (era cash, option C); `docs/prompts/l4-w3-cash-study.md` §2 and §6.
- The owners' reports in `docs/prompts/l4-w3-reports/` for your slice (`luau-a.md`, `relay-a.md`, `luau-b.md`, `ui-a.md`,
  `ui-b.md`, `relay-uib.md`, `designer.md`). The lead accepted luau-a's deviations 1-7, ui-b's deviations (clipped strip
  instead of a ScrollingFrame, `Deps.modal`, the first clear's Valor as its own row), and the designer's deletion of
  `Armory.json power`.
- `CLAUDE.md` (code rules; the 180-locals compile gate).

## Every slice looks for

Correctness against the contract; **server authority** (the client sends intents, never amounts; nothing a client sends
picks a level it may not start, a difficulty it does not have, a pay era, or a reward); every remote validated by type and
length and rate-limited; **missing data degrades, never errors** (no `rewards` block → ×1, no Expeditions config → no map,
a bad summary line dropped); leaks (connections, tweens, flying icons, the card on respawn, leave, a second summary);
per-frame cost on a phone (`Theme.lowEndDevice`, never `reducedMotion`, which is true on every touch device); `--!strict`,
no `wait`/`spawn`/`delay`, no parent argument in `Instance.new`, constants in config or one presentation table; tests and
pins that pass for the wrong reason (vacuous: prove a few with a scratch mutant); mirrors that drift; dead code the §6
deletions left behind (a reader of something deleted, a Theme constant nothing reads).

## The slices

| Slice | Files | Focus |
|---|---|---|
| **1 Hub server and shared** | `src/server/` (`Main.server.luau`, `ExpeditionService`, `HubRemotes`, `StudioBridge`, `EconomyService`, `ArmoryService`), `src/shared/` (`MapRules` new, `RunLines` new, `Types`, `Combat`, `Catalog`, `Armory`, `Unlocks`), `tools/crowd_harness/tests_l4w3.luau` | `Depart` judged by `MapRules.Startable` on the **leader's** saved stars, exactly the rule the dungeon's `RequestStartLevel` uses (no level the dungeon would refuse can be ticketed, and the reverse); the ticket, teleport data, bridge record and registry carry only `levelId` / `difficulty` and an old-shape ticket reads as none; `RequestMapState` cannot be used to read another player's save or to flood (bucket, never yields); `stampDeparture` on every successful departure (L4W3-17, M11's Armory unlock); `EraCashMult` (past the list → last, malformed → 1, Village 1) and `CombatCashMult` = Legacy × Founder's × era, cash only; `RunLines.Add` / `Read` caps (16 lines, 48 bytes, finite ≥ 0), so a forged or oversized summary off the teleport data is dropped, never shown; `gearPower` gone from every Snapshot/Delta reader |
| **2 Combat server** | `src/combat/server/` (`Main.server.luau`, `ArenaService`, `WaveService`, `RunCredit` new, `RunRegistry`, `ReturnService`, `DebugService`, `CombatRemotes`, `StageFlow`, `SecretFlow`), `tools/crowd_harness/tests_l4w3_run.luau` | The depart rule (§3): only a **verified** ticket arms `waiting`; a hint alone gives `picked`; nothing auto-starts after a run (L1 rule) nor re-arms after Reset; the wait cap, a member missing, the leader leaving, a new leader without the stars, a late arrival after `done`, solo; `provingAutoStart` acts only in a proving Studio boot (L4W3-12) and never on the live place; the R / P levers Studio-only and P saves nothing; `cashEra` taken from each member's own profile at admit and frozen; every credit site writes its line (raiders, camp, boss, chest, key, first clear, mentor) and the totals stay the truth; the last wallet Snapshot leaves after every credit of the run's end and before the summary; the MapRules move changed no behaviour (`check_stage_mirror.py` unchanged) |
| **3 The clients** | `src/client/UI/` (`HubMap` new, `RunTally` new, `ExpeditionPanel`, `MapScreen`, `ArmoryAbilityPage`, `TopBar`, `Theme`), `src/client/Controllers/UIController.luau`, `src/combat/client/` (`TallyHost` new, `DepartLine` new, `CombatHud`, `CombatUIController`), `combat.project.json` | The card: rows count up in turn, coins and logs fly, the wallet rolls from (wallet − run) to wallet and retargets on a later Snapshot, a tap skips, buttons answer at any moment, `modal` in the hub; motion through `Motion` (shortened under `reducedMotion`), icon count gated on `lowEndDevice`; fits 640×360 under the 58 px top bar, 667×375 and 375×667 (check the arithmetic against the real Theme sizes); the hub card still chains behind the welcome-back card; the hub map: Depart sends only `(levelId, difficulty, public)`, `SetBusy` clears on the answer or the timeout, the arrows / Enter / Escape bound only while open and released on close, refusals re-request the map; MapScreen's combat call site unchanged; the depart line only in the lobby, `picked` opens the map once per arrival; R and P unbound elsewhere in a mission boot (L4W3-13) |
| **4 Data, simulators and gates** | `src/shared/Config/` (`Combat.json`, `Armory.json`, `Expeditions.json`, `Levels/1_ForestRoad.json`, `Missions/` deleted), `tools/sim_combat.py`, `tools/sim_economy.py`, `tools/check_stage_mirror.py`, `tools/crowd_harness/` (`run_harness.py`, `mutate.py`, `mirror_mutants.py`, `stage_mirror.luau`, every changed `tests_*.luau`), `docs/BALANCE.md` | The era multipliers equal Ben's pick and `sim_combat.py` mirrors them in `combat_cash_mult`, never `level_pay`; assertions 4, 22, 24, 25 hold at the study's values and each fails when broken (prove one yourself); assertion 24's "never faster than building" compares like with like (the same buying rule, the same overheads) and does not pass by construction; `sim_economy.py`'s default output byte-identical (`econ_base.txt` in the scratchpad's `l4-w3-qa\`); the MapRules re-pointing kept every old check's meaning (no test silently dropped: compare check names before and after); `mutate.py` entries match the final text and none is vacuous; the deletions in §6 complete (`git grep` the old names across `src` and `tools`) and the "must not go" list intact (`combat.missions`, `highestEra`, `MissionRecord`, the run list, the fake levers) |

## Output

Write `docs/prompts/l4-w3-review/<slice>.md` (`1-hub.md`, `2-combat.md`, `3-clients.md`, `4-data.md`), LF. Each finding:
**Critical / Major / Minor**, file:line, what is wrong, a concrete failure scenario, and the suggested fix. One line each
for what you checked and found clean. End your reply with the count by severity and the file path.
