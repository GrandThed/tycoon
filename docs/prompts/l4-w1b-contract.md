# L4 W1b contract — the old mission code goes

Brief: `docs/prompts/l4-w1b-brief.md`. Drafted 2026-10-21 on `l4-real-forest` (59a2279, plus W1's uncommitted work).
Rulings are **L4B-n**. Every file:line is as read at that commit; owners re-find by text. Sources: Ben's MISSIONS_DESIGN
§26.6 (the Raider Arena hidden for the publish); INTERFACES `# L1 contracts`, ruling 27 and "Open for later" → L4
(`INTERFACES.md:11154-11172`); PLAN L1 / L1b / L3 "Carried"; `l4-study-report-publish.md` §1 and §4.

## 1. Rulings

- **L4B-1. `Config/Missions` shrinks to a hub stub now and goes in W3.** Its live readers are the hub's, all of
  which W3's city map replaces: `UIController.luau:409-416` (the tile list), `ExpeditionPanel.luau:587-699, 802-873`
  (tiles, lock, Overdrive), `ExpeditionSummaryCard.luau:274`, `ExpeditionService.luau:673-674, 903` (Depart's check,
  the fakeRuns lever); in the dungeon only `ArenaService.luau:902-904` (the registry entry's `era`). Deleting it now
  leaves the hub with no Depart for two waves and makes W1b edit five files W3 rewrites. So `2_Boomtown`,
  `3_Metropolis` and `4_OrbitalColony.json` are deleted (no crowd block: refused since P5), and `1_Village.json` keeps
  only what those readers take: `version`, `id` "village" (the ticket's key), `era` 1, `eraName`, `name` "Forest
  Road", `material` "Timber", `waves` 3, `targetMinutes` 5, `recommendedPower` 64 (T1/T1, sim_combat 1). `arena`,
  `bossWaves`, `targetWaveSeconds`, `enemies`, `waveTable`, `bosses` and `crowd` go.
- **L4B-2. `Combat.json overdrive` stays until W3** (moved out of W1b). After this wave its only readers are the
  hub's `Combat.MissionUnlocked` (`Combat.luau:374-387`) and `Combat.RecommendedPower` (`:492-501`), read at
  `ExpeditionPanel.luau:815-816, 847, 869` and `ExpeditionService.luau:674`. W3 deletes it with the Overdrive toggle,
  both functions, `highestEra` as a gate, and the ticket's and hint's `missionId` / `overdrive` (wire shapes shared
  with the hub: `RunRegistry.luau:236-286`, `StudioBridge.luau:37`, `Main.server.luau:133-180`).
- **L4B-3. The arena is hidden by deleting its data, not by a flag** (§3). The `bonus` node kind stays.
- **L4B-4. Debug bots are deleted.** They are Humanoid rigs the crowd never targets: the lever only warns
  (`DebugService.luau:389-393, 450-451, 585-588`) and nothing calls `ArenaService.AddBot`, `RemoveBot`, `RespawnBot`
  or `BotCount` (`:1302-1490`). L5 builds crowd-target bots if it wants them; nothing of today's carries over.
- **L4B-5. The last-reader rule.** A config key, Types field or type, Theme constant or function whose last `src/`
  reader goes in this wave goes with it, deleted by the owner of the file that holds it. §2 is what the drafter found;
  each owner proves its rows by grep in its report and adds what else it finds. A reader in `tools/` keeps nothing
  alive: the designer retires it under L4B-6.
- **L4B-6. A test goes only with its rule.** A harness case, sim assertion or gate whose rule is deleted is retired
  with one line in the designer's report. One that used the arena or a mission only as a fixture for a rule that
  stays (a stage's `merge`, the director's breather, a gateless locking camp behind a barrier) is re-pointed to a
  hand-written level fixture. Every `mutate.py`, `mirror_mutants.py` and `check_levels_mutants.py` entry whose text
  is gone is deleted or re-aimed in the same round: the full run refuses stale entries.
- **L4B-7. A dash's i-frames count only once the server's ring has seen the dash** (§4).
- **L4B-8. RunState carries each floor's `cells` once per member per floor set** (§5).
- **L4B-9. Saved data is untouched.** `combat.missions` (`ProfileSchema.luau:43, 97`, `Types.MissionRecord`),
  `combat.gear` and `Armory.json legacy` stay for v8 and the live code. Only the dying writers go
  (`WaveService.luau:708-715, 853-866, 898-906`, the arena's mission record).

## 2. Every deletion and its readers

| # | Deleted | Readers (file:line) and how each ends | Owner |
|---|---|---|---|
| 1 | `EnemyService.luau` (2,264 lines) | `ArenaService.luau:37` require; `:236-241` stamps its `CombatArena` group on arena parts (collides as Default: parts stay Default; the ragdoll group dies with the rigs); `:300-301, 394, 414` hand it cover, fence, floor, spawns (go); `:1417, 1481` bot rigs (L4B-4); `BarrierGroups.luau:20, 42-43` require and call (go; its loop copies Default's rule for every registered group, unchanged). Comments: `CombatFxController.luau:563`, `Types.luau:1379, 1568`, `Main.server.luau:16`. | A deletes; B ArenaService; A BarrierGroups |
| 2 | `CombatService.luau` (745) | No `src` caller. Its mirrors in `sim_combat.py` go with row 16. | A |
| 3 | `RequestReady`, `RequestAttack`, `RequestFire`, `RequestDraw`, `RequestAbility` | `CombatRemotes.luau:124-129, 180-223` (no handler since P5 / L1: `Main.server.luau:349-351, 380-384`); buckets `attack`, `ability` `:348-353` with `Combat.json remotes.attackCallsPerSecond`, `abilityCallsPerSecond` (`:17-18`); `maxTargets` `:52-55` (`director.maxAlive`), `isTargetList` `:59-73`, `DEFAULT_ATTACK_*`, `DEFAULT_ABILITY_*`, `DEFAULT_MAX_TARGETS` `:20-21, 28`; the client's waits `InputController.luau:2588-2600`. | A, ui, designer |
| 4 | InputController's C1 path | `missionState` `:236-282` (keep `phase`, `crosshairParams`, `characterConnections` in a renamed table: the range path reads them at `:470-484, 583-630, 1176, 2867-2916`); `:413-905` (`slotTier`, `Armory.TierDef` `:425-429`, `hitPad`, `aimAssistDegrees`, `maxTargets` `:453-455`, the C1 swing, fire, draw, ability); `ACTION.ATTACK/ABILITY_*/STANCE`, `ACTIONS` `:185-197` and their binds; `DEFAULTS.HIT_PAD/AIM_ASSIST_DEGREES/MAX_TARGETS`; `AttackDown`, `AttackUp`, `UseAbility`, `ToggleStance` `:2614-2650`; `GetStance`, `SetStanceChanged`, `SetGear`, `SetAbilityReady` `:2844-2865`. Callers: `CombatUIController.luau:1028-1037, 1109, 1256, 1274` (in `boot`), `:1719-1722` (bootMission's HUD deps). `comboTolerance` stays only if the range path reads it. | ui |
| 5 | `CombatUIController.boot` `:959-1294` | Its Start fallback `:2407-2414` keeps one warn and boots no HUD (with no `ProvingGrounds.json` there are no weapons and every level is refused, `WaveService.luau:1631`); `rewardedKinds`' mission branch `:345-350`; the arena forward rule `:719-731` (`Catalog.GetArenaLayout`). | ui |
| 6 | CombatHud's C1 action layer | Deps `onStance`, `onAttackDown`, `onAttackUp`, `onAbility`, `onAttackInput`, `actions` `:129-136` and the buttons they drive; the arena's examples in comments `:34, 65`; bot rows `:1282, 1295`. | ui |
| 7 | CombatFx kinds `hit`, `telegraph`, `kill`, `playerHit`, `ability`, `playerDown`, `swing`, `partyEffect`, `refused` | Sent only by rows 1-2. `CombatFxController.luau:1298-1321` branches and what only they reach: rig watching `:500-597`, telegraphs `:724-948`, `presentHit`, `onHit`, `presentKill`, `onKill`, `onPlayerHit`, `onAbility` (`:949-1069`), `onPlayerDown` (`:1098-`), `onSwing` `:1126` (L3-53), the party ring (`:1206` reads `Armory.json partyEffects`), `chargeDistance` `:177-180` (`Combat.json ai`), `corpseSeconds` `:167-170`. `wave`, `bossDown`, `mentor`, `camp`, `notice`, banners and vignette stay. Types: `CombatFxHit`, `Kill`, `PlayerHit`, `Ability`, `PlayerDown`, `Refused`, `Swing`, `PartyEffect`, `Telegraph` (`:1656-1716`, beside the kept `Wave`, `BossDown`, `Mentor`) and their union members (`:1737-1747`). | ui; A (Types) |
| 8 | Debug bots (L4B-4) | ArenaService `:49-50, 479-488, 555-590, 971-975, 1302-1310, 1394-1490`; WaveService `:367-376, 450, 720`; DebugService `:75, 389-393, 450-451, 585-588`; combat `DebugPanel.luau:121, 287-294`; `CombatUIController.luau:2067`; Types `PartyMember.bot :1551`, `RunMember.bot :1575` (`player: Player?` becomes `Player`), `CombatDebugConfig` `:1333-1342`, `CombatEnemyConfig.botColor`; `Combat.json debug` `:107, 113-115`. | B, A, ui, designer |
| 9 | `PartyMember.ready`, `RunMember.ready` and C1-only member fields | Types `:1549, 1576`; ArenaService writes `:588, 1209, 1424`. Also `RunMember.stance`, `abilityReadyAt`, `respawnAt`, `drawStartedAt`, `empoweredUntil`, `empowerMult` (written at `:1212-1222, 1427-1436, 1487`, `NEUTRAL_EMPOWER :55`, read only by rows 1-2) and `PartyMember.abilityReadyIn`, `stance` (`:591-595`, read only by rows 4-6). | A (Types), B |
| 10 | `WeaponService.SetArena` `:2103-2106` | No caller (the call its comment names is gone). | A |
| 11 | `Combat.json director.maxAlive` `:33` | `CombatRemotes.luau:54`, `InputController.luau:455`, `sim_combat.py:1857, 2035` (C1 run model). Every other `maxAlive` is the crowd's. | designer, A, ui |
| 12 | `debug.missionAttribute` `:97`, `overdriveAttribute` `:99` | `Types.luau:1322, 1325` only. | designer, A |
| 13 | Missions 2-4 and Village's dungeon blocks (L4B-1) | `sim_combat.py` `load_missions :256-266`; the C1 run model and its mirrors (`c1_* :789-829`, `mission_unlocked :858`, `wave_weights`, `wave_spec`, `enemy_stats`, `boss_valor`, `recommended_power :867-948`, `wave_composition :1002`, `spawn_interval :1036`, `crowd_wave`, `crowd_reward`, `burst_interval :1185-1221`, `simulate_run :1546-2270`); the mirrors of kept rules stay (`combat_cash_mult :949`, `contribution_shares :957`, `mentor_bonus :970`, `away_efficiency :977`, `tempo :988`, `breather_seconds :1050`, `should_merge :1060`, `camp_wave` to `burst_seconds` `:1075-1184`); assertions 3, 7-19 (see §6); `sim_range.py` `:5096-5111, 7118-7120, 9354-9368, 9371-9430, 9431-, 9853, 9915-9958, 10996-11011, 11041`; `check_levels.py:5080, 5298`; `check_stage_mirror.py:2351-2362, 2372`; `run_harness.py:1583, 1592, 1597`; `mutate.py:44, 59`; `FIXTURES.village` users in `tests_l1.luau` (14), `tests_l1_world.luau` (8), `tests_l1b.luau` (1). Types `MissionConfig :1468-1487` narrows to the stub (and `Combat.luau`'s copy `:100-117`); `MissionCrowdConfig :2611` goes; `MissionCrowdGroup/Boss/Wave/Reward` stay (levels use them; names unchanged). | designer; A (types) |
| 14 | Both adapters (ruling 27) | `StageFlow.Resolve`'s mission branch `:305-345`, `ARENA_ZONE :220`: the signature becomes `Resolve(file, runCapSeconds)`; `LevelGeometry.FromArena :697-765`, `ARENA_CAMP_ID :79-80`, the "names the arena" refusal `:913-916`; `LevelService.luau:507`; WaveService `:491, 1146, 1633-1653, 1956`; `Catalog.GetArenaLayout :555-570` and `arenas` `:451`; Types `LevelFile.mission`, `.recommendedTier` (`:2678-2679`), `LevelConfig.mission :2696`, `LevelLayout.arena :2796`; `ArenaService` `LevelInfo.mission :72`; MapScreen `:334-345`; CombatUIController `:719-731`. Mirrors and tests: `sim_range.py resolve_level :5339-5370`, `arena_as_layout :5207`; `check_levels.py:58-59, 1944-1960, 2058-2067, 5308-5309, 5370`; `check_stage_mirror.py:1468, 2052, 2551, 2648-2655`; `stage_mirror.luau:185, 198`; `run_harness.py sources() :1567-1575`; `tests_l1.luau:226-255, 416, 541, 777, 808-847, 1109-1117, 2252, 2560-2602`; `tests_l1_world.luau:36-38, 142-186, 357, 517-520, 763`; `tests_l1b.luau:369-374, 628-629`; `tests_l3_run.luau:151-159`; `mutate.py:1145-1147, 1586-1592, 1822-1825, 1847-1851, 2314`. | A, B, ui, designer |
| 15 | `Layouts/Arenas/Village`, `Boomtown`, `Metropolis`, `OrbitalColony.luau` | Only `Catalog.GetArenaLayout` and the tools of rows 13-14 (`sim_combat.py:181-183`); `mutate.py:61` globs the folder (safe). `ProvingGrounds.luau` stays: the range builds it (`ArenaService.luau:246-264`, `CrowdRenderer.SetArena :2721`). | designer |
| 16 | Dead `Combat.luau` functions | `WaveSpec :410`, `EnemyStats :447`, `BossValor :475`, `WaveComposition :599` (`weightsForWave :392`), `SpawnInterval :674`, `MeleeDamage :723`, `RangedDamage :737`, `AbilityDamage :762`, `AbilityCooldown :775` (`gearTier`, `ascensionTier`, `slotAbility` `:707-760`), `CrowdWave :948`, `CrowdReward :976`, `BurstInterval :989`, and the copied types only they use. Readers: rows 1-2, sim_combat mirrors, `tests_l1.luau`. | A; designer (tools) |
| 17 | `Armory.json slots :86`, `classes :63`, `abilities :76`, top-level `bands :57`, `partyEffects :131` (L3-54) | `Armory.TierDef :879-891`, `WeaponDamage :894-905`, `ClassDef`, `AbilityDef :957-965` (read only by rows 1, 4, 5, 16: go). `Armory.CanAscend :935` reads `cfg.slots[slot]`: becomes `slot ~= "melee" and slot ~= "ranged"` (the hub forge, `ArmoryService.luau:150`, stays). Types `:1030-1090` (`BandDef`, `WeaponClassDef`, `AbilityDef`, `WeaponStarterDef`, `WeaponTierDef` with `model`, `ArmorySlotDef`, `PartyEffectDef`), `ArmoryConfig :1142-1149`, copies in `Armory.luau:24-120`, `Combat.luau:244-301`. Tools: `sim_combat.py:283-284, 755, 820, 1378, 1534-1543, 2670, 3113, 3149-3151`; assertion 1 and `tests_l3.luau:2403` pin ladder HP to the slot tiers 2-12: pin the literal list instead. | A; designer |
| 18 | Other dead `Combat.json` keys (L4B-5) | `enemy :79-96`; `ai :212-`; `animations.enemyIdle/Walk/Attack/Death/Run/Hit :69-75` (`playerSlash`, `playerLunge` stay: `WeaponController.luau:162`); `player.hitDistancePad`, `aimAssistDegrees`, `corpseSeconds`, `breatherRegenPerSecond`, `killCooldownRefundSeconds`, `dashHitRadius`, `burstConeDegrees` `:6-14` (`respawnSeconds` stays, `ArenaService.luau:1549`; `comboTimingTolerance` stays, `WeaponService.luau:296`; `rescue` stays); `crowdSkeleton :189` (read by sim_combat 15 only); the `feel` / `feedback` keys row 7 leaves unread (ui lists them). Types `:1160, 1241, 1266, 1380, 1398-1420, 2626`. | designer; A |
| 19 | `combat.project.json` `ServerStorage.Enemies` `:43-46` | EnemyService's templates (`templates/_enemies` does not exist). The `globIgnorePaths` entries stay: W2 decides where raider models live. | lead (+ `py tools/proving_project.py`) |
| 20 | `RunState.overdrive` (`ArenaService.luau:624`, `Types.luau:1613`) | No client reads it. `RunSummary.overdrive` and `missionId` ride to the hub: W3. | B, A |

`proving_project.py` reads none of this (it bakes `provingBoots` only); no generated doc reads it.

## 3. How the arena is hidden

- **Data:** the `raiderArena` node (`Expeditions.json:28`) and the `bonus` theme (`:36`) go;
  `Config/Levels/0_RaiderArena.json`, `Layouts/Levels/RaiderArena.json` and the four arena layouts are deleted.
- **Unlock:** it had no `requires`, so `StageFlow.NodeState` opened it from the first visit; it goes with the node.
- **Intents:** `RequestStartLevel("raiderArena", d)` finds no node and answers `locked` before any file is read
  (`WaveService.luau:1851-1862`); a harness case on the real map pins it. The map keys walk `MapState`'s nodes, so no
  key reaches it. No lever names a level; `debug.provingLevel` is config: `check_levels.py` asserts it names a map
  node with a level file, that no level file names `mission` and no layout names `arena` (tripwires for row 14).
- **Kept:** the `bonus` kind (`MapScreen.luau:166`, `Types.luau:2824`, `check_levels.py:4876`): side nodes are in
  the design (secrets' second exits, the arena's return as a real level). A saved `stars.raiderArena` is ignored (no
  node) and kept (L4B-9). The hub changes nothing (L4B-1).

## 4. `OnDash` against the ring (L4B-7)

**Today** `WeaponService.luau:2573-2589` opens i-frames on the request (cooldown only), and VitalsService voids every
hit those windows meet (`VitalsService.luau` `shielded :182-189`, asked each frame until the decision, `:439-444`).
A client that never moves holds 0.25 s of every 0.64 s (39%, `sim_range.py:3887`).

1. `OnDash` keeps its refusals (`:2575-2586`) and stamps `lastDashAt`; instead of `openIframes` it records
   `dashClaimAt = now` (one per shooter; a newer accepted dash replaces an unproven claim; `resetAir :2022-2034` drops it).
2. Each Heartbeat, right after the ring sample (`trackAir :1973`), a pending claim gets
   `DashProof.Verdict(history, now, position, claimAt, rule)`, a new pure module (A):
   - "proven" when `PositionRing.Motion` (new optional `flat` argument: horizontal displacement only; existing callers
     unchanged), over the stretches ending since `claimAt - lookback`, span `movement.dashProofSeconds` (0.05), reaches
     `movement.dashProofShare` (0.5) × `dashDistance / dashSeconds`, i.e. 66.7 studs/s (a dash is 133, the walk 20);
   - "lapsed" once `now > claimAt + dashSeconds + lookback` (0.45 s) unproven; else "pending".
   - `lookback` = `shooting.originLagMaxSeconds` (0.3): a dash's motion may replicate before its remote does.
3. Proven → `openIframes(shooter, claimAt, dashIframes)`: the window starts at the request, not the proof
   (`openIframes` gains `from`; an open window is lengthened and a lapsed one steps back, as `:2039-2045` do).
   Lapsed → nothing, no attribute.
4. VitalsService is unchanged: a hit decided after the proof is voided as today, one decided before it lands.
   `GrantIframes` (knock, get-up, abilities, the grace: `:3051-3057`, `AbilityService.luau:444, 461`,
   `WaveService.luau:1217`) is server-granted and unchanged.
5. **The cost, said plainly:** the old rule forgave a dash pressed up to ping/2 + `originLagSeconds` after the impact
   on the player's screen; now the server's copy must have moved for about `dashProofSeconds` before the decision.
   Under the commit rule (decided at T + lag where the screen had the body at T), a dash pressed on screen at T or
   earlier still dodges. A dash into a wall (under 3.3 studs in 0.05 s) earns no i-frames. If Ben finds dodging
   harder, the follow-up is to hold a decision that only a pending claim could cover until it resolves
   (`VitalsService.luau:431-455`), never to loosen the proof.

**Tests (A, new `tools/crowd_harness/tests_l4b.luau`):** (a) 20 studs in 0.15 s sampled at 60 Hz and at 20 Hz, two
updates bunched in a frame: proven within 0.05 s of the first moving sample; (b) a still body, any claim time: never,
lapses at 0.45 s; (c) walking at 20 studs/s, bunched: never; (d) falling 120 studs/s: never (flat); (e) motion ended
more than `lookback` before the claim: never; within it: proven; (f) stopped by a wall after 2 studs: never;
(g) VitalsService with fake hooks: an impact between the claim and the proof, decided after the proof, is dodged; decided
before, it lands; (h) the real `ProvingGrounds.json`: the proof speed is at least 2 × `walkSpeed` and at most 0.8 of a
dash's. **Pins and mutants** (the designer writes them from A's report): `OnDash` holds no `openIframes(`; the
Heartbeat call passes `claimAt`; mutants: open on the request, the window from the proof, `flat` off, `lookback` 0, no
lapse, the share at 0. **Simulator** (designer): `start_dash` (`sim_range.py:2677-2684`) appends its window only when
its own clamped path covers the share in its first `dashProofSeconds`; `plan_shielded` (`:2755-2758`) applies the
same; the facts (`:3887-3889`, `:4332`) report a forged still dash at 0 uptime. Every PASS stays PASS; the report counts
unproven dashes per policy (expected 0 on open ground; one against a fence is listed, not failed).

## 5. RunState cells once (L4B-8)

**Today** `WaveService.luau:1909-1946` builds `run.floors` once per run, but every RunState carries them whole
(`:348` → `ArenaService.luau:649`): Forest Road's plateau region holds 12 cells (2 open camps + 10 road cells,
`Layouts/Levels/ForestRoad.json regions`) on each of its 2 floors, at `remotes.combatStateHz` 4 per member, and the
client compares them all every time (`CombatUIController.luau:1938-1990`).

1. WaveService owns `floorsSeq`, a session counter bumped exactly where `run.floors` is assigned (`:1946`, and the
   lobby's empty list on return), handed over in `SetRunFields`.
2. Every RunState carries `floorsSeq`, and every floor its `x, y, z, hx, hz, locks, ceiling, fence`. `cells` rides
   only on a member's first RunState of that seq. `BuildRunState` (`:606-653`) builds floors without cells; the new
   pure `src/shared/RunFloors.luau` (A) has `Attach(floors, seq, sentSeq)` (the floors to send, and whether cells went)
   and `Merge(held, heldSeq, incoming, seq)`. ArenaService's sends (`Broadcast :709-722`, `sendSummaryTo :688-696`) call
   Attach and record `cellsSent[userId] = seq`. ReturnService's leave card (`:178-181`) stays: same seq, no cells.
3. `cellsSent[userId]` is cleared at Admit and Remove, so every arrival (a solo rejoin after a failed trip home,
   `Main.server.luau:224-238`, a fresh join, L5's latecomer) gets cells on its first RunState. Remote sends are ordered
   and queue until the client listens.
4. Client (ui): `applyFloors` merges through `RunFloors.Merge`: the same seq keeps each floor's held cells (a region
   never changes inside a seq); a new seq takes them as sent (nil = the rectangle alone, as today).
5. Types (A): `RunState.floorsSeq`; `RunFloor.cells` says when it is present.

**Measured (B, in its report, not a gate):** a JSON-length proxy on Forest Road's real plan: a steady RunState's bytes
before (cells every send) and after (none), and the first send. **Tests (B, new `tests_l4b_run.luau`):** cells on the
first Attach per seq per member and never after; again after a clear; Merge keeps held cells on the same seq and
replaces them on a new one; a steady send's floors hold no `cells` key.

## 6. Owners (disjoint files; "for the other owner" relays at the end)

- **luau-engineer A — server services, shared modules, remotes, Types.** Deletes `EnemyService.luau` and
  `CombatService.luau`. Owns `CombatRemotes.luau`, combat `Main.server.luau` (comments `:14-17, 349-351, 380-384`),
  `BarrierGroups`, `StageFlow`, `LevelGeometry`, `LevelService`, `WeaponService`, `PositionRing`, `DebugService`,
  `RunFx` (a comment, `:3`), new `DashProof.luau` (all in `src/combat/server/Services/`); `src/shared/Combat.luau`,
  `Armory.luau`, `Catalog.luau`, `Types.luau`, new `src/shared/RunFloors.luau`; new `tools/crowd_harness/tests_l4b.luau`.
- **luau-engineer B — the run.** `ArenaService.luau`, `WaveService.luau`; new `tools/crowd_harness/tests_l4b_run.luau`.
- **ui-engineer.** `InputController`, `CombatUIController`, `CombatFxController` (`src/combat/client/Controllers/`),
  `CombatHud`, combat `DebugPanel` (`src/combat/client/UI/`), `src/client/UI/MapScreen.luau`, `Theme.luau` (constants
  only C1 read), and any other client file a deletion reaches (named in its report).
- **economy-designer.** `Config/Combat.json`, `Armory.json`, `Expeditions.json`, `ProvingGrounds.json` (`movement`
  `dashProofShare`, `dashProofSeconds`), `Missions/*`, `Levels/0_RaiderArena.json`; `Layouts/Levels/RaiderArena.json`,
  `Layouts/Arenas/{Village,Boomtown,Metropolis,OrbitalColony}.luau`; `sim_combat.py`, `sim_range.py`, `check_levels.py`,
  `check_levels_mutants.py`, `check_stage_mirror.py`; in `tools/crowd_harness/`: `run_harness.py`, `mutate.py`,
  `mirror_mutants.py`, `stage_mirror.luau` and every existing `tests_*.luau`; `docs/BALANCE.md`.
  - sim_combat after W1b keeps 1 (literal HP pin), 2, 5, 6, 20-23; re-points 4 to Forest Road Normal's pay against
    Village's remaining slot cost (W3 reworks it for §26.8's era multiplier); rewrites 12 and 13 as pure checks of the
    `MentorBonus` mirror with fixture rates and shares (the only guard on `WaveService.luau:720-770`'s mentor pay);
    retires 3, 7-11, 14 (C1 run model), 15-18 (the crowd mission), 19 (the adapter) and the `--era`, `--power`,
    `--party`, `--overdrive` flags. `sim_range.py` loses the arena report, `--mission` and `--level arena`.
- **Lead.** `combat.project.json` (row 19), `.proving.project.json` (`py tools/proving_project.py`), the sourcemaps,
  and an INTERFACES pointer `# L4 W1b contracts`.
- **Relays.** A → B: `Resolve`'s signature, the member and RunState types, `RunFloors`. A → ui: the CombatFx kinds
  gone, `RunFloors.Merge`, the Armory and Combat functions gone. A, B, ui → designer: every changed line a
  `run_harness.py` pin or `mutate.py` entry reads (file, old text, new text), the new tests and modules to register in
  `SOURCES`, and the mutants for `DashProof`, `RunFloors` and the `OnDash` pins. Designer → A: the two `movement` key
  names. ui → designer: the `feel`, `feedback` and Theme keys left unread. Anyone → lead: a remote, a project file, or
  any hub file (none is planned: L4B-1, L4B-2).

## 7. Order beside W1 (lead's amendment: a second worktree)

**W1b runs in its own worktree, `C:\Users\benja\Desktop\tycoon-p5b`, branch `l4-w1b`** (from `l4-real-forest` at the
commit that holds this contract), so W1's gates never run against half-edited `src/`. Every path and command in this
contract is read against that root (the harness's first argument is `C:/Users/benja/Desktop/tycoon-p5b`). The Luau CLI is
the main checkout's `C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`. The worktree has no `assets\` junction: W1b needs
none.

A, B and ui start at once. **The designer starts with Config and Layouts only** and touches the four tools files W1 track D
owns (`check_levels.py`, `check_levels_mutants.py`, `sim_range.py`, `tests_l2.luau`) and `mutate.py` only after the lead has
merged W1-D's commit into `l4-w1b` and written `docs/prompts/l4-w1b-reports/go-designer.md`. Every agent: `git status` and
`git diff` first, commit nothing, kill only its own PIDs, report to `docs/prompts/l4-w1b-reports/<role>.md`.

## 8. Definition of done

Each owner, before reporting: stylua, selene, luau-lsp on both sourcemaps, `py tools/check_compile.py`, the harness,
and `mutate.py` filtered to its own files. QA, from the worktree root in Bash:

```bash
export PATH="$HOME/.rokit/bin:$PATH"; L=C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe
stylua --check src && selene src
rojo sourcemap default.project.json -o sourcemap.json && rojo sourcemap combat.project.json -o sourcemap.combat.json
luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.json src/client src/server src/shared
luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.combat.json src/combat src/shared
py tools/check_compile.py
rojo build -o build/test.rbxl && rojo build combat.project.json -o build/combat.rbxl
py tools/proving_project.py && rojo build .proving.project.json -o build/proving.rbxl
for p in boomtown metropolis orbital; do rojo build $p.project.json -o build/$p.rbxl; done
py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5b $L
py tools/check_stage_mirror.py && py tools/crowd_harness/mirror_mutants.py --luau $L
py -3.12 tools/check_levels.py && py -3.12 tools/sim_range.py --check
py tools/sim_combat.py --check && py tools/sim_economy.py --check
py -3.12 tools/check_levels_mutants.py        # background, about 2 h
py tools/crowd_harness/mutate.py C:/Users/benja/Desktop/tycoon-p5b $L ""   # full run, 2 h+, alone in its worktree
git grep -nE 'EnemyService|CombatService|FromArena|GetArenaLayout|RequestReady|RequestAttack|RequestFire|RequestDraw|RequestAbility|raiderArena|AddBot|WeaponService\.SetArena|Missions/[234]_' -- src tools   # empty
git ls-files --eol | grep -c w/crlf           # 0
```

All green, every count named (the `git grep` is empty: a fixture that keeps a side node gives it another id). Then
Ben's "still plays" look (docs-keeper writes it): `proving.rbxl` → Play → the lobby, the map shows Forest Road and no
Raider Arena, a Normal run plays and a dash still reads DODGED; `provingBoots` "range" and a rebuild → the bench opens,
the Colossus and Warlord sets load; `build/test.rbxl` → one Forest Road tile whose Depart (Studio API access on) lands
in the lobby.

## 9. Risks, and what must not be deleted

**Risks.**
1. Text drift: about 1,700 `mutate.py` entries and 150 `run_harness.py` pins read the files this wave cuts; one stale
   entry blocks the full run. The relays in §6 exist for this; the designer re-aims in the same round.
2. Four tools files are shared with W1 track D (§7). A merge of two designers' edits to `sim_range.py` is the likeliest
   conflict; sequence, never edit in parallel.
3. The dash change is a feel change only Ben can judge (§4.5); ask in the look whether dodging feels the same.
4. Coverage: the arena was the only level that played `merge`, the director's breather and a gateless locking camp.
   L4B-6 keeps those rules tested, but no shipped level plays them; BALANCE says so.
5. The hub stub: one tile with Forest Road's numbers and the key "village" until W3; still a live-visible oddity if
   anything published before W3 (the freeze holds).
6. `RunMember.player` loses its nil (row 8): every `member.player` nil check in B's files is either kept harmlessly or
   removed with care; behaviour must not move.
7. Ben's Studio profile may hold `stars.raiderArena` and `missions.village`: ignored, kept.

**Not deleted, and why.**
- `combat.missions`, `combat.gear`, `Armory.json legacy`, `Types.MissionRecord`: saved data (L4B-9).
- `Config/Missions/1_Village.json` (stub), `Combat.json overdrive`, `Combat.MissionUnlocked`, `RecommendedPower`,
  `TouchHighestEra`, `highestEra`, the ticket's and hint's `missionId` / `overdrive`, `RunSummary.missionId`, `overdrive`:
  the hub's, W3 (L4B-1, L4B-2).
- `Armory.json ascension` and `Armory.AscensionCap`, `AscensionCost`, `CanAscend`: the hub's forge handler is live
  (`ArmoryService.luau:150`), even with no screen; Ascension is a later decision.
- The director (`windowSeconds`, tempo, merge, breather, `eliteTempo`, `runCapSeconds`): Forest Road's locking camp
  and the level schema's `merge` read it (`WaveService.luau:564-578, 670, 1582-1583`).
- The `bonus` node kind (§3); the Colossus and Warlord kinds and the range's sets (`ProvingGrounds.json`); the range
  arena builder, `Layouts/Arenas/ProvingGrounds.luau`, `Types.ArenaLayout`.
- `CombatMode`'s mode name "mission" and `VitalsService.SetMission`: they name the dungeon mode, not Config/Missions.
- The hub's `fakeParty` / `fakeInvite` levers and the fakeRuns lever (live party UI; W3 for fakeRuns).
- `MissionCrowdGroup`, `MissionCrowdBoss`, `MissionCrowdWave`, `MissionCrowdReward`: levels use them; a rename is churn.
- `Combat.json animations.playerSlash` / `playerLunge`, `player.respawnSeconds`, `comboTimingTolerance`, `rescue`.

## 10. Lead's rulings after the review (2026-10-21; detail in `l4-w1b-fix-round.md`)

- **The dash keeps today's feel (F1):** a hit decided while a dash claim is pending, which that claim would cover, is held
  until the claim is proven (voided) or lapses (lands); pending claims are proven before hits are decided, in one fixed
  order per frame. This replaces §4.5's "the server's copy must have moved before the decision".
- **What L4B-7 stops (F5):** a request-only forger (a dash claimed with no movement) and a dash into a wall. It does not
  stop a modified client that moves its own root: the game has no movement anti-cheat, and such a client can already step
  out of any shape. Leap Smash and Impale Dash keep their server-granted i-frames at the cast.
