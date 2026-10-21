# L4 W1b — luau-engineer A's report

Status: done for my files. Nothing committed.

Two gates are not finished yet: the full harness verdict and the filtered `mutate.py` run on StageFlow,
LevelGeometry, Combat and VitalsService. Both wait on the designer re-pointing the arena and mission
tests (see "Gates").

## Files

**Deleted:**
- `src/combat/server/Services/EnemyService.luau`
- `src/combat/server/Services/CombatService.luau`

**New:**
- `src/combat/server/Services/DashProof.luau` (L4B-7)
- `src/shared/RunFloors.luau` (L4B-8)
- `tools/crowd_harness/tests_l4b.luau`

**Changed:**
- `CombatRemotes.luau`:
  - Gone: the intents `RequestReady`, `RequestAttack`, `RequestFire`, `RequestDraw`, `RequestAbility`.
  - Gone with them: the `attack` and `ability` buckets, `isTargetList` / `maxTargets` (`director.maxAlive`),
    `DEFAULT_ATTACK_*`, `DEFAULT_ABILITY_*`, `DEFAULT_MAX_TARGETS`.
- `Main.server.luau`: comments only.
- `BarrierGroups.luau`: the `EnemyService` require and its call are gone. The loop is unchanged.
- `RunFx.luau`: the comment changed. `member.player` is now used directly; it is never nil.
- `DebugService.luau`:
  - The bots lever is gone (L4B-4): `warnedBots`, `refuseBots`, the `bots` branch, the `botsAttribute` poll.
  - `setGodMode` uses `member.player` directly.
- `StageFlow.luau`: `Resolve`'s mission branch and `ARENA_ZONE` are gone.
- `LevelGeometry.luau`: `FromArena`, `ARENA_CAMP_ID`, `Pieces`' "names the arena" refusal and `BareLobby`'s
  `arena = nil` are gone.
- `LevelService.luau`: `lobbyLayout` no longer tests `layout.arena`.
- `WeaponService.luau`:
  - `SetArena` is gone.
  - L4B-7: `OnDash` records `shooter.dashClaimAt` instead of opening i-frames.
  - The new local `proveDash` judges the claim in `trackAir`, right after `PositionRing.Record`.
  - `openIframes(shooter, now, from, seconds)` goes through `DashProof.Open`. It sets the attribute only
    while the window is still open now.
  - `resetAir`, and a frame with no root, drop the claim.
  - `GrantIframes` opens from now, as before.
- `PositionRing.luau`: `Motion` gains an optional `flat` argument. Existing callers are unchanged.
- `src/shared/Combat.luau`:
  - Gone: `WaveSpec`, `EnemyStats`, `BossValor`, `WaveComposition` (+`weightsForWave`), `SpawnInterval`,
    `MeleeDamage`, `RangedDamage`, `AbilityDamage`, `AbilityCooldown` (+`gearTier`, `ascensionTier`,
    `slotAbility`), `CrowdWave`, `CrowdReward`, `BurstInterval`.
  - **`CampReward` also goes (L4B-5).** Its only `src` caller was `CrowdReward`. It equals
    `KillReward(rewards, kind, spec.rewardMult)`.
  - Also gone: the `Armory` require, every Armory type copy, `EnemyDef` to `BossDef`, `MissionCrowdConfig`,
    and `director.maxAlive`.
  - `MissionConfig` is narrowed to the stub.
  - The `overdrive` copy stays (L4B-2).
- `src/shared/Armory.luau`:
  - Gone: `TierDef`, `WeaponDamage`, `ClassDef`, `AbilityDef`, `STARTER_TIER`, and the `bands`,
    `classes`, `abilities`, `slots` and `partyEffects` types and fields.
  - `CanAscend` answers "invalid" when `slotValue` is nil (any slot but "melee" and "ranged"). This is the
    same behaviour, and the hub's forge still works.
- `src/shared/Catalog.luau`: `GetArenaLayout` and the `arenas` cache are gone.
- `src/shared/Types.luau`: see "Types" below.
- **`src/combat/server/Services/VitalsService.luau`** (routed to me by the lead): `RunLost` and
  `AllHaveBodies` no longer test `member.bot` or a nil player. Behaviour is unchanged now that there are
  no bots. The "Bots never count" comments are gone.

### Types (L4B-5: no `src` reader left for any of these, proved by grep in the worktree)

- **Armory:** `BandDef`, `WeaponClassDef`, `AbilityDef`, `WeaponStarterDef`, `WeaponTierDef`,
  `ArmorySlotDef`, `PartyEffectDef`. `ArmoryConfig` loses `bands`, `classes`, `abilities`, `slots`,
  `partyEffects`.
- **`CombatPlayerConfig`:** `hitDistancePad`, `breatherRegenPerSecond`, `killCooldownRefundSeconds`,
  `aimAssistDegrees`, `corpseSeconds`, `dashHitRadius`, `burstConeDegrees`.
- **`CombatRemotesConfig`:** `attackCallsPerSecond`, `abilityCallsPerSecond`.
- **`CombatDirectorConfig`:** `maxAlive`.
- **`CombatAnimationsConfig`:** `enemyIdle`, `enemyWalk`, `enemyAttack`, `enemyDeath`, `enemyRun`, `enemyHit`.
- **`CombatCameraConfig`:** `touchAimAssistDegrees` (ui's A-1).
- **`CombatFeelConfig`:** `shakeLight`, `shakeHeavy`, `hitMarkerSeconds`, `ragdollImpulse`,
  `ragdollSeconds`, `hitSparkCount` (ui's A-2). `trailSeconds` and `arrowSpeed` stay (WeaponController).
- **`CombatFeedbackConfig`:** `hitstopSeconds`, `cameraKickDegrees`, `lowHpFraction` (ui's A-3).
  `damageNumberSeconds` and `bannerSeconds` stay. FeedbackController's `hitstopSeconds` is a local, not
  this key.
- **`CombatDebugConfig`:** `missionAttribute`, `overdriveAttribute`, `botsAttribute`, `botHp`,
  `botDamagePerSecond`, `botIncomeRate`.
- **`CombatConfig`:** `enemy`, `ai`, `crowdSkeleton`, along with the types `CombatAiConfig`,
  `CombatEnemyConfig` and `CrowdSkeletonWave`.
- **Missions:**
  - Gone: `EnemyDef`, `CompositionDef`, `WaveTableDef`, `BossPatternDef`, `BossDef`, `EnemyStats`,
    `MissionCrowdConfig`.
  - `MissionConfig` is narrowed to `version, id, era, eraName, name, material, waves, recommendedPower,
    targetMinutes`.
  - `MissionCrowdGroup`, `Boss`, `Wave` and `Reward` stay.
- **Arena and enemy:** `ArenaLayout.enemySpawns` (B's A-2), `EnemyState`.
- **`PartyMember`:** `ready`, `bot`, `abilityReadyIn`, `stance`.
- **`RunMember`:**
  - Gone: `bot`, `ready`, `stance`, `abilityReadyAt`, `respawnAt`, `drawStartedAt`, `empoweredUntil`,
    `empowerMult`, `godMode`, `spawnIndex`.
  - `player` is now `Player` (was `Player?`).
  - What is left: `userId, name, player, character, humanoid, waiting, incomeRate`.
- **`RunState`:** `overdrive` goes. `floorsSeq: number` is added. `RunFloor.cells`' comment now says when
  it is present.
- **CombatFx:** `Hit`, `Kill`, `PlayerHit`, `Ability`, `PlayerDown`, `Refused`, `Swing`, `PartyEffect`,
  `Telegraph`, and their union members.
- **Levels:** `LevelFile.mission`, `LevelFile.recommendedTier`, `LevelConfig.mission`, `LevelLayout.arena`.
- **Added:** `RangeMovementConfig.dashProofShare: number` and `dashProofSeconds: number`.

**Kept on purpose:**
- `CombatOverdriveConfig` and Combat.luau's copy, whole. Its `countMult`, `damageMult`, `spawnRateMult` and
  `rewardMult` have no reader now, but L4B-2 keeps the block until W3 deletes it whole.
- `MissionRecord`, `gear`, `Armory.json legacy` (L4B-9).
- `debug.provingGear` (tools-only, as before this wave).

## Contracts implemented

```lua
StageFlow.Resolve(file: Types.LevelFile, runCapSeconds: number): Types.LevelConfig?
PositionRing.Motion(history, now, position, window, span, flat: boolean?): (number, Vector3)
DashProof.Rule(movement: Types.RangeMovementConfig, shooting: Types.RangeShootingConfig): DashProof.Rule?
  -- { speed = share * dashDistance / dashSeconds, span = dashProofSeconds,
  --   lookback = originLagMaxSeconds, lapse = dashSeconds + lookback }; nil if a number is missing/bad
DashProof.Verdict(history: PositionRing.History, now: number, position: Vector3, claimAt: number,
  rule: DashProof.Rule): "proven" | "lapsed" | "pending"
DashProof.Open(windows: DashProof.Windows, from: number, seconds: number): ()
  -- Windows = { iframesFrom, iframesUntil, iframesWasFrom, iframesWasUntil } (WeaponService's Shooter)
RunFloors.Attach(floors: { Types.RunFloor }, seq: number, sentSeq: number?): ({ Types.RunFloor }, boolean)
RunFloors.Merge(held: { Types.RunFloor }, heldSeq: number?, incoming: { Types.RunFloor }, seq: number): { Types.RunFloor }
```

**Verdict:**
- "proven" when the fastest flat stretch of `span`, among those ending at or after `claimAt - lookback`,
  reaches `speed`. A proof beats a lapse judged in the same frame.
- "lapsed" once `now > claimAt + lapse` and it is still unproven.
- A proven window opens from the request: `openIframes(shooter, now, claimAt, dashIframes)`.

**Open:**
- A window that lapsed before `from` steps back.
- One that meets the new window merges with it, and may reach back to `from`.
- A dash proven late, whose window ended before a later grant began, takes the earlier slot.

## Assumptions

1. There are no fallback numbers in code for the two dash keys; the contract allows none. If a build
   lacks `ProvingGrounds.json movement.dashProofShare` or `dashProofSeconds`, `DashProof.Rule` is nil,
   every claim lapses, and a dash earns no i-frames (one warn). The designer has now added both keys.
2. A frame with no living root drops a pending claim: there is no body to prove it or to shield.
3. The i-frame attribute is set only while the opened window is still open now, so a late proof of a past
   window shows nothing.

## Gates

**Passed:**
- stylua `--check` and selene on all my `src` files: clean, 0 errors, 0 warnings.
- luau-lsp on both sourcemaps: **0 diagnostics** after the VitalsService fix (hub `src/client src/server
  src/shared`; combat `src/combat src/shared`).
- `py tools/check_compile.py`: PASS, 180 files.
- §8 `git grep` in `src`: only the designer's `Config/Expeditions.json:28` and
  `Config/Levels/0_RaiderArena.json` remain.

**`tests_l4b.luau`** (scratch bundle of tests.luau + tests_l4b, with DashProof and RunFloors
registered): **PASS, 175 checks**. This was rerun after the designer added `dashProofShare` 0.5 and
`dashProofSeconds` 0.05 to ProvingGrounds.json, so (h) passes too.

My scratch mutants on DashProof all fail the tests: flat off (d), lookback 0 (e), no lapse (b), share 0
(Rule and (b)), Open never reaching back (Open).

**Full harness:**
- In the worktree the bundle stops after 577 checks, at `tests_l1_world`'s `FromArena`.
- I ran a scratch copy of the worktree with the dead groups skipped and the four new files registered:
  **3,868 checks, 10 FAIL**. Every one is a dead-rule case the designer retires: the "names its arena"
  refusal; the arena "on easy"; "a level keeps its file's id" (a 4-argument Resolve); realLevel /
  realWorld / realRun / l3 firstClear (through L1's layoutOf → `FromArena` on the shipped RaiderArena);
  l1b rewardTests (`CampReward`); l1b worldTests (`FromArena`); and (h). No kept rule failed.
- `run_harness.source_reading`, whole worktree against HEAD: 0 readings differ, so no pin moved.

**`mutate.py`:**
- Run on a scratch HEAD root with my WeaponService, LevelService, DebugService, Main.server, PositionRing,
  Armory, Types, Catalog, DashProof and RunFloors copied in. Baseline PASS (4,031 checks).
  `files:WeaponService.luau,LevelService.luau,DebugService.luau,Main.server.luau,PositionRing.luau,Armory.luau`:
  **215 run, 0 not caught** (exit 0).
- StageFlow, LevelGeometry, Combat and VitalsService cannot be mutated until their tests are re-pointed:
  every mutation needs a passing baseline. After the designer's round, run
  `files:StageFlow.luau,LevelGeometry.luau,Combat.luau,VitalsService.luau,DashProof.luau,PositionRing.luau`.

## For the other owners

### For the lead

- No remote added; no project file or hub file touched.
- A RequestDebug `"bots"` from an old client is ignored.

### For the economy-designer

1. **Register in `run_harness.py`:**
   - `SOURCES`: `"DashProof": "src/combat/server/Services/DashProof.luau"` and
     `"RunFloors": "src/shared/RunFloors.luau"`.
   - `TESTS`: `"tests_l4b.luau"`, before B's `tests_l4b_run.luau`. Both end with the verdict line.
   - `tests_l4b` reads these locals from tests.luau: `check`, `near`, `load`, `vec`, `config`, `FIXTURES`,
     `fakeNow`, `Vitals`, `player`, `character`, `root`, `humanoid`, `iframes`, `clearIframes`, `hooks`,
     `lunge`, `advance`, `vitalsBeat`, `drain`.
   - Add both files to `mutate.py` `FILES`.
2. **`ProvingGrounds.json movement`:** `"dashProofShare": 0.5`, `"dashProofSeconds": 0.05`. These are the
   names typed in `Types.RangeMovementConfig`.
3. **JSON with no `src` reader left after my deletions.**

   `Combat.json`:
   - `remotes.attackCallsPerSecond`, `abilityCallsPerSecond`
   - `director.maxAlive`
   - `debug.missionAttribute`, `overdriveAttribute`, `botsAttribute`, `botHp`, `botDamagePerSecond`,
     `botIncomeRate`
   - `enemy`, `ai`, `crowdSkeleton`
   - `animations.enemyIdle/Walk/Attack/Death/Run/Hit`
   - `player.hitDistancePad`, `aimAssistDegrees`, `corpseSeconds`, `breatherRegenPerSecond`,
     `killCooldownRefundSeconds`, `dashHitRadius`, `burstConeDegrees`
   - `camera.touchAimAssistDegrees`
   - `feel.shakeLight`, `shakeHeavy`, `hitMarkerSeconds`, `ragdollImpulse`, `ragdollSeconds`,
     `hitSparkCount`
   - `feedback.hitstopSeconds`, `cameraKickDegrees`, `lowHpFraction`
   - **Keep:** `overdrive` (L4B-2), `feel.trailSeconds`, `feel.arrowSpeed`,
     `feedback.damageNumberSeconds`, `feedback.bannerSeconds`.

   Elsewhere:
   - `Armory.json`: `slots`, `classes`, `abilities`, the top-level `bands`, `partyEffects`.
   - `Missions/1_Village.json`: keep exactly the stub keys `Types.MissionConfig` lists.
   - `Layouts/Arenas/ProvingGrounds.luau`: `enemySpawns`.
4. **`mutate.py` entries stale on my files: 11 (retire 7, re-aim 4).**

   Retire:
   - "l1: the arena adapter without merging"
   - "l1: the arena is always played on normal"
   - "real: the arena's level takes its mission's id"
   - "world: the arena's entry is its pad"
   - "world: the level shares the arena's obstacle tables"
   - "world: the arena's camp is as wide as the arena is deep"
   - "l1b: FromArena not locking"

   Re-aim (each new old text occurs once):
   - "real: a level file's id dropped for its layout's" (FLOW):
     - old: `"\t\tversion = file.version,\n\t\tid = file.id,\n"`
     - new: `"\t\tversion = file.version,\n\t\tid = file.layout,\n"`
   - "l2: Resolve drops the secrets" (FLOW):
     - old: `"\t\tsecrets = file.secrets,\n\t}\nend"`
     - new: `"\t}\nend"`
   - "p5 lost: a member on the pad still fights" (VITALS):
     - old: `"if member.waiting then"`
     - new: `"if false then"`
   - "p5: a start does not wait for bodies" (VITALS):
     - old: `"if bodyOf(member.player) == nil then"`
     - new: `"if false then"`

   Not stale:
   - "l2w3 fix3 fd-m2: no root keeps the fall" still matches: the claim drop sits after
     `PositionRing.Clear`.
   - `mirror_mutants.py` (129) and `check_levels_mutants.py` MIRROR_CASES (13): 0 stale.
5. **New `mutate.py` entries.**

   On DashProof (DASH = `src/combat/server/Services/DashProof.luau`), caught by `tests_l4b`:
   - "l4b: the proof not flat": `"rule.span, true)"` → `"rule.span, false)"`
   - "l4b: no lookback": `"local window = now - claimAt + rule.lookback"` → `"local window = now - claimAt"`
   - "l4b: a claim never lapses": `"if now > claimAt + rule.lapse then"` → `"if false then"`
   - "l4b: the share at 0": `"speed = share * distance / seconds,"` → `"speed = 0,"`
   - "l4b: Open never reaches back": `"windows.iframesFrom = math.min(windows.iframesFrom, from)"` →
     `"windows.iframesFrom = windows.iframesFrom"`

   On RING:
   - "l4b: Motion's flat ignored": `"\t\tif flat == true then\n"` → `"\t\tif false then\n"`, caught by (d).

   On WEAPON (caught only by the pins in item 6):
   - "l4b: OnDash opens on the request": `"\tshooter.dashClaimAt = now\nend"` →
     `"\tshooter.dashClaimAt = now\n\topenIframes(shooter, now, now, movement.dashIframes)\nend"`
   - "l4b: the window from the proof": `"openIframes(shooter, now, claimAt, config.movement.dashIframes)"` →
     `"openIframes(shooter, now, now, config.movement.dashIframes)"`
   - "l4b: the claim never judged": `"\t\t\tproveDash(shooter, now, position, claimAt)\n"` → `""`
   - "l4b: resetAir keeps the claim": `"\t-- The last body's dash is not this one's.\n\tshooter.dashClaimAt = nil\n"` → `""`
6. **Pins for `run_harness.py`.** These read WeaponService's code with comments blanked, and each text
   occurs once today:
   - `WeaponService.OnDash` holds no `openIframes(`, and holds `shooter.dashClaimAt = now`.
   - `trackAir` holds
     `\t\tPositionRing.Record(shooter.history, now, position)\n\t\tlocal claimAt = shooter.dashClaimAt\n`
     and then `proveDash(shooter, now, position, claimAt)`.
   - `proveDash` holds `DashProof.Verdict(shooter.history, now, position, claimAt, rule)` and
     `openIframes(shooter, now, claimAt, config.movement.dashIframes)`.
   - `openIframes(` appears 3 times in the file: the definition, `proveDash`, and `GrantIframes`'s
     `openIframes(shooter, now, now, seconds)`.
   - `openIframes` holds `DashProof.Open(shooter, from, seconds)`.
   - `resetAir` holds `shooter.dashClaimAt = nil`.
7. **Tests to retire or re-point (L4B-6) because of my deletions.**
   - `tests_l1.luau`:
     - `Flow.Resolve(file, mission, cap, difficulty)` becomes `Flow.Resolve(file, cap)` at :232-259, :417,
       :541, :777 and :1110-1117. `Resolve(own, nil, 1800)` becomes `Resolve(own, 1800)`. The mission and
       arena cases retire.
     - layoutOf (:1657-1671) uses `FromArena`, which is gone.
     - :262-292 and :893-948 use CrowdWave, CrowdReward, BurstInterval and CampReward. Use
       `Combat.KillReward(rewards, kind, spec.rewardMult)` in place of CampReward.
     - :2375-2417 (the adapters) retire.
   - `tests_l1_world.luau`: :142-186, :357, :519-520 (`FromArena`) and :763 (the refusal) retire.
   - `tests_l1b.luau`: :369-374 (Resolve takes 2 arguments); :537-549 retire (CampReward); :628-629 retire
     (`FromArena`).
   - `stage_mirror.luau`: :185 (`FromArena`) goes; :198 becomes `Flow.Resolve(file, runCap)`; at :403 and
     :416, CampReward becomes `KillReward(…, spec.rewardMult)`.
   - `tests_p5.luau:314-365`: drop the `bot` members (`player = nil`). RunLost and AllHaveBodies now call
     `bodyOf(member.player)` on every non-waiting member.
   - The sims: add `CampReward` to the mirrors retired by rows 13 and 16. The sim_range dash change is as
     §4 says: the window starts at the request, and the proof uses `PositionRing.Motion` semantics (the
     anchor is the newest sample at least `dashProofSeconds` older).

### For luau-engineer B

- Done as B wrote. No change asked.

### For the ui-engineer

- **CombatFx kinds gone:** `hit`, `telegraph`, `kill`, `playerHit`, `ability`, `playerDown`, `swing`,
  `partyEffect`, `refused`.
- **Functions gone:** `Armory.TierDef`, `WeaponDamage`, `ClassDef`, `AbilityDef`, the Combat functions
  above, and `Catalog.GetArenaLayout`.
- **`RunFloors.Merge`:** on the same seq, a floor that arrives without cells keeps the held cells of the
  same index; a new seq takes the floors as sent. Every floor is a fresh table.
- A-1 to A-3 are done as you asked.
