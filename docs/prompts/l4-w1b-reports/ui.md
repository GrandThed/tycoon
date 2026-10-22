# L4 W1b — ui-engineer's report

Status: done for my files (rows 4 to 8 and 14 on the client, L4B-8 on the client). luau-lsp is clean on
both sourcemaps for `src/client`, `src/combat/client` and `src/shared` (A has since dropped
`touchAimAssistDegrees` from Types, A-1). Not mine and still red: `VitalsService.luau:885, 903` (see Lead).

## Files changed

All under `C:\Users\benja\Desktop\tycoon-p5b\`:

- `src/combat/client/Controllers/InputController.luau` (row 4): the whole C1 path is gone (`missionState`,
  the C1 swing, fire, draw, ability, dash, stance, the four C1 actions and their gamepad binds, `AttackDown`,
  `AttackUp`, `UseAbility`, `ToggleStance`, `GetStance`, `SetStanceChanged`, `SetGear`, `SetAbilityReady`,
  `SlotTiers`, the `Armory` and `SoundController` requires). `phase` and `characterConnections` moved into
  `rangeState` (no new top-level local). `crosshairParams` was NOT kept: the contract thought the range
  path read it, but only the C1 `crosshairPoint` did; the range path's world query is `worldParams`, so the
  watch now only marks that stale (`invalidateWorld`). `comboTolerance` goes (the range path never read it).
  `Start` binds nothing without the range's combat. `GetCharge` keeps `number?` (nil only without the
  range's combat; FeedbackController reads `or 0`). 2,919 -> 2,241 lines.
- `src/combat/client/Controllers/CombatUIController.luau` (rows 5, 8, 14, L4B-8): `boot` is gone; `Start`'s
  fallback warns once and boots no HUD; `rewardedKinds` lost its mission branch, `forwardPoint` its arena
  branch; the mission HUD's C1 deps (`onStance`, `onAttackDown`, `onAttackUp`, `onAbility`, `actions`) are
  gone; the party count no longer reads `member.bot` (it counts members); `CombatFxController.SetMaterial`
  and `SetParty` calls are gone (their readers went, below). `applyFloors(list, seq)` merges through
  `RunFloors.Merge` with `st.floorsSeq`; a RunState with no `floorsSeq` reads as 0 (a server that sends none
  sends the cells every time, which Merge takes as they come). `sameCells` short-cuts on the same list.
- `src/combat/client/Controllers/CombatFxController.luau` (row 7): rewritten to what stays: `wave`,
  `bossDown`, `mentor`, `camp`, `notice`, the banner and its layout, the toast handler. Gone: every C1 kind,
  the rig watching (`Workspace.Enemies`), telegraphs, hits, kills, sparks, nudges, the party ring, the
  waiting toast, `SetMaterial`, `SetParty`, `SetHitMarkerHandler`, `SetBannerHandler`, `SetHealth` and the
  low-HP vignette with the hurt flash. **Deviation from row 7, by L4B-5:** the contract keeps the vignette,
  but its only driver was C1's `boot` (`CombatFxController.SetHealth`, `CombatUIController.luau:1226` at
  HEAD); `bootMission` never called it, so it could not show in any run, and the range's VitalsHud has its
  own hurt edge. No behaviour moves. `floatText` lost its `large` flag (the Mentor line is its one caller).
  1,606 -> 400 lines.
- `src/combat/client/UI/CombatHud.luau` (rows 6, 8, 9): the C1 action layer is gone (HP bar, Attack /
  stance / ability cluster, reticle, hit marker, charge dots; `SetHealth`, `SetStance`, `SetAbilities`,
  `SetCharge`, `ShowHitMarker`; `AbilityInfo`, `AbilitySet`; the `actions` dep; the `WAITING_TEXT` export,
  read only by CombatFxController's waiting toast). The party rows no longer read `bot` (" · BOT" suffix
  gone) or `abilityReadyIn`; Abandon's "only member, else the leader" counts the rows shown. The arena's
  examples in comments are gone. `SetAiming` keeps only the Alt hint. 1,724 -> 1,191 lines.
- `src/combat/client/UI/DebugPanel.luau` (row 8): the two bot levers are gone. Its `BOTTOM_BLOCK` mirrored
  the C1 HP bar (`COMBAT_HP_LABEL_HEIGHT` + `COMBAT_HP_BAR_HEIGHT`, deleted); it now reserves the two hint
  lines CombatHud really draws over the run's buttons (116 design px against 110: 6 px more room kept).
- `src/client/UI/MapScreen.luau` (row 14): `difficultiesOf` lost the `file.mission` branch; with
  `recommendedTier` required on `LevelDifficulty`, `Difficulty.tier` is now `number` and the card's nil
  branch went.
- `src/client/UI/Theme.luau` (L4B-5): 81 constants deleted, 77 whose last reader went in this wave and 4
  that had none before it (`COMBAT_BOSS_WIDTH`, `COMBAT_DEBUG_MAX_SPAWN_KEYS`, `COMBAT_HP_BUTTONS_GAP`,
  `COMBAT_WALLET_MIN_TEXT`: C1 HUD leftovers). Comments that named dead config keys fixed.
  `COMBAT_HP_BAR_WIDTH` stays (CombatHud's Alt and key hints are that wide; its comment says so).
- Client files the deletions reached (contract §6 "any other client file"):
  - `src/combat/client/Controllers/CameraController.luau`: `FaceToward` (only the C1 swing called it) and
    `AdoptTouch` (only `boot`'s attack button) with their state (`faceTarget`, `faceUntil`, the `adopted`
    touch flag); the `Workspace.Enemies` exclusion in the collision query (EnemyService made that folder;
    nothing does now); `touchAimAssistDegrees` in `FALLBACK_CAMERA` (its only reader was the C1 `aim`).
  - `src/combat/client/Controllers/WeaponController.luau`: `ArrivalDelay` and `Hitstop` (only
    CombatFxController's C1 hits called them); `Shoot` lost `fireKind`: its one caller left (the range path,
    `"semi"`) never sends `beam` or `charge`, so `beam()`, the arrow look, the stuck arrow and
    `fadeAndDestroy` went with them, and `shotEnd` no longer asks the enemies folder. SwingOther's
    comment no longer names bots.
  - `src/combat/client/Main.client.luau`: one comment.

## Proof by grep (L4B-5), in the worktree after my edits

- `git grep -nE 'EnemyService|CombatService|FromArena|GetArenaLayout|RequestReady|RequestAttack|RequestFire|RequestDraw|RequestAbility|raiderArena|AddBot|WeaponService\.SetArena|Missions/[234]_' -- src/client src/combat/client`: empty.
- No client reads `member.bot`, `.ready`, `abilityReadyIn`, `PartyMember.stance`, `LevelFile.mission`,
  `recommendedTier` on a file, `layout.arena`, `Catalog.GetArenaLayout`, `Catalog.GetMissionById` (in the
  combat client), `Armory.TierDef` / `ClassDef` / `AbilityDef`, `Types.WeaponTierDef` / `WeaponStarterDef` /
  `WeaponClassDef`, `cfg.partyEffects`, `player.hitDistancePad` / `aimAssistDegrees` / `corpseSeconds`,
  `director.maxAlive`, `camera.touchAimAssistDegrees`, `ai.*`, `Workspace.Enemies`, or any C1 CombatFx kind.
  The hub's `ExpeditionPanel` and `ExpeditionSummaryCard` are untouched (L4B-1, L4B-2).
- Theme: a scan of every `src/**/*.luau` outside Theme.luau finds a reader for every key left (0 unread).
  No tool reads a deleted key (`check_levels.py` THEME_KEYS and the harness's Theme pins are untouched).

## Gates run on my files (re-run in full after the session-limit cut-off, same results)

- `stylua --check`, `selene` on all ten files: clean.
- `luau-lsp analyze` (both sourcemaps, built into my scratchpad, not the repo's): no error in `src/client`,
  `src/combat/client` or `src/shared`. The only errors left are server ones (VitalsService, see Lead).
- `py tools/check_compile.py`: PASS, 180 files.
- Harness: none of my files is bundled. `run_harness.source_reading` on HEAD against HEAD plus only my ten
  files: 489 readings, 0 differ (every text pin on InputController, WeaponController, Theme holds).
  `mutate.py`'s stale check for every entry on my files: 31 entries, 0 stale. The full harness stopped at
  577 checks on `FromArena` (A's deletion; the designer re-points those tests), so it gives no verdict yet.

## For the other owners

### luau-engineer A (Types, shared)

- A-1 (done by A already): `Types.CombatCameraConfig.touchAimAssistDegrees` had no reader left (the C1
  `aim` in InputController was the last); CameraController's `FALLBACK_CAMERA` no longer sets it.
- A-2: `Types.CombatFeelConfig`: the client reads only `trailSeconds` and `arrowSpeed` now
  (WeaponController). `shakeLight`, `shakeHeavy`, `hitMarkerSeconds`, `hitSparkCount` lost their last
  client readers; `ragdollImpulse`, `ragdollSeconds` were EnemyService's. Delete any your server grep
  finds no reader for.
- A-3: `Types.CombatFeedbackConfig`: the client reads only `damageNumberSeconds` and `bannerSeconds`
  (CombatFxController). `hitstopSeconds`, `cameraKickDegrees`, `lowHpFraction` lost their last readers
  (FeedbackController's `hitstopSeconds` is a local of its own, not this key).
- A-4: nothing in the client reads `PartyMember.bot`, `ready`, `abilityReadyIn`, `stance` any more, nor
  `MissionConfig.crowd`, `LevelFile.mission`, `LevelFile.recommendedTier`, `LevelLayout.arena`.
  `Catalog.GetMissionById` keeps one reader, the hub's `ExpeditionSummaryCard.luau:274` (W3).
- A-5: I read `RunState.floorsSeq` and `RunFloors.Merge` exactly as written; no change asked.

### luau-engineer B (the run)

- B-1: the client merges floors by `RunState.floorsSeq` (missing reads as 0) and keeps a floor's cells by
  index inside one seq. A new seq must come with the floor list it names, as §5 says.
- B-2: the party list and Abandon no longer read `bot`; they read `userId`, `name`, `host`, `hp`, `maxHp`,
  `alive`, `down`, `waiting`, `engaged`, `damageShare`.

### economy-designer (Config, tools)

- D-1, `Config/Combat.json` keys the client stopped reading (delete each whose server grep is empty too):
  `camera.touchAimAssistDegrees`; `feel.shakeLight`, `feel.shakeHeavy`, `feel.hitMarkerSeconds`,
  `feel.hitSparkCount` (plus `feel.ragdollImpulse`, `feel.ragdollSeconds`, EnemyService's);
  `feedback.hitstopSeconds`, `feedback.cameraKickDegrees`, `feedback.lowHpFraction`. Already in §2:
  `player.hitDistancePad`, `aimAssistDegrees`, `corpseSeconds`, `ai.*`, `director.maxAlive`. Still read:
  `feel.trailSeconds`, `feel.arrowSpeed`, `feedback.damageNumberSeconds`, `feedback.bannerSeconds`,
  `player.comboTimingTolerance` (server).
- D-2, `Config/Sounds.json` keys with no `SoundController.Play` left anywhere in `src`: `swing`,
  `finisher`, `bowFire`, `laser`, `gunFire`, `bowDraw`, `abilityCast`, `enemyHit`, `enemyDeath`,
  `playerHit`, `playerDown`, `partyRally`, `partyWarcry`, `lowHp`, `waveClear` (all ids 0). Still played:
  `waveStart`, `bossStart`, `bossDown`, `mentor`, `runEnd` (the hub's summary card), `uiClick` and the hub's.
  Sounds.json is not in §6's file list: the lead routes it.
- D-3, Theme keys: 81 deleted (list below); no tool reads any of them.
- D-4, harness: no `run_harness.py` pin or `mutate.py` entry text changed (see "Gates"); nothing to re-aim
  or register for my files. No client test is new (RunFloors.Merge is tested in B's `tests_l4b_run.luau`).

### Lead

- No remote, project file or hub file was touched.
- `src/combat/server/Services/VitalsService.luau:885` (`RunLost`) and `:903` (`AllHaveBodies`) still read
  `member.bot` and compare `member.player` with nil, so luau-lsp fails there now that `RunMember.bot` is gone
  and `player` is `Player` (row 8, risk 6). §6 names no owner for VitalsService; it is a server file, so A's
  or B's to route. The fix is `if player == nil or member.waiting` -> `if member.waiting` and
  `if not member.bot and player ~= nil and ...` -> `if bodyOf(player) == nil`, with the comments' "Bots never
  count" dropped; VitalsService's text is pinned by `mutate.py` (VITALS) and the harness, so check both.

### The 81 Theme keys deleted

COMBAT_ABILITY_BUTTON_SIZE, COMBAT_ABILITY_KEY_HEIGHT, COMBAT_ABILITY_NAME_HEIGHT,
COMBAT_ABILITY_RING_HEIGHT, COMBAT_ABILITY_RING_SECONDS, COMBAT_ABILITY_RING_TRANSPARENCY,
COMBAT_AIM_MIN_STUDS, COMBAT_ARENA_WAIT_SECONDS, COMBAT_ARROW_COLOR, COMBAT_ARROW_LENGTH,
COMBAT_ARROW_STICK_SECONDS, COMBAT_ARROW_THICKNESS, COMBAT_ARROW_TRAIL_SECONDS, COMBAT_ARROW_TRAIL_WIDTH,
COMBAT_ATTACK_BUTTON_SIZE, COMBAT_BEAM_SECONDS, COMBAT_BEAM_WIDTH, COMBAT_BOSS_WIDTH,
COMBAT_CHARGE_DOT_IDLE_TRANSPARENCY, COMBAT_CHARGE_DOT_SIZE, COMBAT_CHARGE_RING_DOTS,
COMBAT_CHARGE_RING_RADIUS, COMBAT_CLUSTER_GAP, COMBAT_CLUSTER_STROKE_TRANSPARENCY, COMBAT_CROSSHAIR_GAP,
COMBAT_CROSSHAIR_LENGTH, COMBAT_CROSSHAIR_THICKNESS, COMBAT_DAMAGE_TEXT_SIZE, COMBAT_DASH_MAX_FORCE,
COMBAT_DASH_SECONDS, COMBAT_DEBUG_MAX_SPAWN_KEYS, COMBAT_FINISHER_KICK_MULT, COMBAT_HIT_DELAY_MAX_SECONDS,
COMBAT_HIT_HIGHLIGHT_FILL, COMBAT_HIT_HIGHLIGHT_SECONDS, COMBAT_HIT_MARKER_LENGTH, COMBAT_HIT_MARKER_OFFSET,
COMBAT_HP_BAR_HEIGHT, COMBAT_HP_BUTTONS_GAP, COMBAT_HP_LABEL_HEIGHT, COMBAT_HURT_FLASH_SECONDS,
COMBAT_HURT_FLASH_TRANSPARENCY, COMBAT_KILL_PARTICLES, COMBAT_KILL_POP_END, COMBAT_KILL_POP_SECONDS,
COMBAT_KILL_POP_START, COMBAT_KILL_POP_TRANSPARENCY, COMBAT_KNOCKBACK_SECONDS, COMBAT_KNOCKBACK_STUDS,
COMBAT_PARTY_PULSE_FILL, COMBAT_PARTY_PULSE_SECONDS, COMBAT_PARTY_RING_SECONDS,
COMBAT_PARTY_RING_TRANSPARENCY, COMBAT_PROJECTILE_CLAIM_RADIUS, COMBAT_PROJECTILE_FADE_SECONDS,
COMBAT_RETICLE_SIZE, COMBAT_SPARK_SURFACE_OFFSET, COMBAT_STANCE_GLYPH_TEXT, COMBAT_STANCE_SIZE,
COMBAT_TELEGRAPH_AREA_TRANSPARENCY, COMBAT_TELEGRAPH_COLOR, COMBAT_TELEGRAPH_DEFAULT_HALF_WIDTH,
COMBAT_TELEGRAPH_DEFAULT_RADIUS, COMBAT_TELEGRAPH_FILL_TRANSPARENCY, COMBAT_TELEGRAPH_FLOOR_Y,
COMBAT_TELEGRAPH_GROUND_PROBE, COMBAT_TELEGRAPH_HIGHLIGHT_FILL, COMBAT_TELEGRAPH_LIFT,
COMBAT_TELEGRAPH_LINGER_SECONDS, COMBAT_TELEGRAPH_MARK_RISE, COMBAT_TELEGRAPH_MARK_SIZE,
COMBAT_TELEGRAPH_MIN_SIZE, COMBAT_TELEGRAPH_SUMMON_COLOR, COMBAT_TELEGRAPH_SUMMON_RADIUS,
COMBAT_TELEGRAPH_THICKNESS, COMBAT_TELL_HIGHLIGHT_FILL, COMBAT_VIGNETTE_PULSE_SECONDS,
COMBAT_VIGNETTE_THICKNESS, COMBAT_VIGNETTE_TRANSPARENCY, COMBAT_WAITING_TOAST_COOLDOWN,
COMBAT_WALLET_MIN_TEXT.

## Layout checked by reading (375 x 667 and 1920 x 1080)

Nothing the mission HUD shows moved: its run layer already ran with `actions = false`, so the HP bar's
height was 0 and the buttons already sat at `PADDING` from the bottom; header, wallet, notice, party list,
boss bar, banner and the waiting card keep their code. The range HUD (crosshair, health bar, AbilityBar,
touch buttons) is untouched. No control was added; every remaining tap target is the one it was (Map,
Armory, Return, Abandon at `ROW_BUTTON_HEIGHT` 48 design px = 44 physical px at MIN_SCALE). The Studio
strip's band is 6 design px shorter (it scrolls). Reduced motion: nothing new animates.

## What to check in Studio (for docs-keeper's "still plays" look)

- `proving.rbxl` -> Play: the lobby shows the run layer (Map, Armory, Return hidden in proving), the map
  opens on Forest Road, a Normal run plays; wave banners, "Camp cleared", the Checkpoint notice and the
  Mentor line still show; Abandon (Backspace twice) works.
- On the phone emulator (667 x 375 landscape and 375 x 667 portrait): the thumb cluster, health bar and
  Abandon rule as before; no stray Attack / stance buttons; one drag turns the camera, two pinch-zoom.
- A gun (hitscan family) still flashes at the muzzle and draws its bolt; bows and the Beam are drawn by
  FeedbackController as before.
- Output: no `[CombatUIController]` "booting the C1 mission HUD" line; a build without ProvingGrounds.json
  prints "Config/ProvingGrounds is missing: no weapons, so no HUD" once.
- The crowd's floors: walking from camp to camp the drawn charges still stop at the region's cells (the
  cells now come once per floor set); after a run and a return to the lobby the floors are empty.
