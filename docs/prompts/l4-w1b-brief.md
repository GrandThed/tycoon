# L4 W1b — the old mission code goes (brief for the contract drafter)

You draft a contract; you write no code. Work in `C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest`. Edit no
repo file except `docs/prompts/l4-w1b-contract.md` (LF). Do not commit. Kill only your own PIDs. Tools: `py` only;
`export PATH="$HOME/.rokit/bin:$PATH"` for rokit; the Luau CLI is `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
Three other agents work in this worktree now (W1: the lookout in `1_ForestRoad.json` and the gates; the forest kit in
`tools/levels/`; the raider kit in `tools/assets/raider_kit*`); read their files if you need to, never edit them.

## What W1b is

Ben ruled (MISSIONS_DESIGN §26.6) **the Raider Arena is hidden for the publish** (it may come back later as a real
level). With it the old mission layer can go, which L1's contract scheduled for L4 (INTERFACES ~11154-11172: delete
`EnemyService`, `CombatService`, the four old remotes and `RequestReady`, the C1 mission paths in `InputController`,
`CombatHud` and `CombatUIController.boot`, the bot functions, `PartyMember.ready`, `WeaponService.SetArena`,
`director.maxAlive`, `debug.missionAttribute` and `overdriveAttribute`, `Combat.json overdrive`, the era missions
without crowd waves, the old `enemies`, `waveTable` and `bosses` blocks; the arena adapters,
`Layouts/Arenas/Village.luau`, `Config/Missions`; C1 `onSwing` in CombatFxController (L3-53); `Armory.json slots` and
`Types.WeaponTierDef.model` (L3-54)). Two "before any publish" items ride with it: **`OnDash` grants i-frames on the
request alone** (`WeaponService.luau` ~2573-2588: judge the dash against the `PositionRing` at hit time) and **RunState
resends `floors[i].cells` on every send** (`ArenaService.luau` ~649, `WaveService.luau` ~348: send once per run).

Read: `docs/prompts/l4-study-report-publish.md` (§1 the hub today, §4 the carried table with file:line), the L1
contract section of `docs/INTERFACES.md` (`grep -n "^# L1 contracts"`) for rulings 27 and the dead-code list,
`docs/PLAN.md` "L1" to "L3" carried items, `CLAUDE.md` (rules; the 180-locals compile gate in
`tools/check_compile.py`).

## What the contract must settle

1. **Every deletion with its readers.** For each item: grep every reader in `src/`, `tools/` (simulators, gates, the
   crowd harness and its `mutate.py` entries, `check_stage_mirror.py`, `proving_project.py`), the project files
   (`*.project.json`) and docs that are generated from code. An item with a reader that must stay is either rewired
   (say how) or moved out of W1b (say to which wave). In particular: **the hub's Expeditions panel and summary card**
   read `Config/Missions` today (`ExpeditionPanel.luau`, `ExpeditionSummaryCard.luau:274`), and W3 replaces them with
   the city map: decide whether `Config/Missions` leaves in W1b with a stub for the hub, or in W3. The Studio range
   bench (`Combat.json debug.provingBoots "range"`, the range's Colossus and Warlord sets) must keep working; the
   Colossus and Warlord kinds stay for the range.
2. **How the arena is hidden**: the map node, its unlock, any lever or debug key that starts it, the level file
   `0_RaiderArena.json` and `LevelGeometry.FromArena`. Nothing of the arena may be reachable by a client intent.
3. **`OnDash`**: the rule (the dash is judged where the server's ring had the body at hit time, the P4 commit rule),
   the harness tests and mutants that prove it, the simulator's policy if it reads dash i-frames.
4. **RunState cells once**: what is sent once, what every send keeps, how a late joiner gets the cells (L5 is later,
   but a rejoin in solo must work), and the bytes measured before and after.
5. **Owners with disjoint files**: luau-engineer A (server services, shared modules, remotes, `Types.luau`),
   luau-engineer B (the run: `ArenaService`, `WaveService`, `RunState`), ui-engineer (`src/client/**`,
   `src/combat/client/**`), economy-designer (`src/shared/Config/**`, `src/shared/Layouts/**`, simulators, gates,
   harness texts, `docs/BALANCE.md`). No file has two owners; list each owner's files. Say which items need a
   "for the other owner" relay.
6. **Definition of done**: every gate in the repo green (name the commands: `stylua --check`, `selene`, `luau-lsp
   analyze` with `tools/types/globalTypes.d.luau` and `--sourcemap`, `rojo build` for every project file,
   `py tools/check_compile.py`, `check_levels.py`, `check_levels_mutants.py`, `check_stage_mirror.py`, the crowd
   harness, `mutate.py` (filtered by `files:` per changed file, the full run by QA), `sim_range.py --check`,
   `sim_combat.py --check`, `sim_economy.py`); the place files still build; `proving.rbxl` boots into Forest Road; the
   range bench still opens with its switch.
7. **Risks**, and anything you think should NOT be deleted, with the reason.

Keep the contract under about 250 lines, every claim with file:line. End your reply with a ten-line summary and the
contract path.
