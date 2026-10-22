# L4 W1b — economy-designer's report

Status: done. Every §8 gate I can run is green except the one named R8 row (x1.60 before and after). Nothing
committed.
Worktree `C:\Users\benja\Desktop\tycoon-p5b`, branch `l4-w1b`. Python named for every number.

## Files changed

Data (`src/shared/`):
- `Config/Missions/1_Village.json`: the L4B-1 stub (`version`, `id` "village", `era` 1, `eraName`, `name` "Forest
  Road", `material` "Timber", `waves` 3, `targetMinutes` 5, `recommendedPower` 64). `2_Boomtown`, `3_Metropolis`,
  `4_OrbitalColony.json` deleted.
- `Config/Levels/0_RaiderArena.json`, `Layouts/Levels/RaiderArena.json`,
  `Layouts/Arenas/{Village,Boomtown,Metropolis,OrbitalColony}.luau` deleted.
- `Config/Expeditions.json`: the `raiderArena` node and the `bonus` theme gone (§3; the `bonus` kind stays).
- `Config/Combat.json` (rows 8, 11, 12, 18 and the ui / A relays): `enemy`, `ai`, `crowdSkeleton`;
  `player.hitDistancePad`, `aimAssistDegrees`, `corpseSeconds`, `breatherRegenPerSecond`, `killCooldownRefundSeconds`,
  `dashHitRadius`, `burstConeDegrees`; `remotes.attackCallsPerSecond`, `abilityCallsPerSecond`; `director.maxAlive`;
  `animations.enemyIdle/Walk/Attack/Death/Run/Hit`; `debug.missionAttribute`, `overdriveAttribute`, `botsAttribute`,
  `botHp`, `botDamagePerSecond`, `botIncomeRate`; `camera.touchAimAssistDegrees`; `feel.shakeLight`, `shakeHeavy`,
  `hitMarkerSeconds`, `ragdollImpulse`, `ragdollSeconds`, `hitSparkCount`; `feedback.hitstopSeconds`,
  `cameraKickDegrees`, `lowHpFraction`. Each grep'd: no `src` reader outside Types. Kept: `overdrive` (L4B-2),
  `player.respawnSeconds`, `comboTimingTolerance`, `rescue`, `animations.playerSlash/playerLunge`,
  `feel.trailSeconds/arrowSpeed`, `feedback.damageNumberSeconds/bannerSeconds`, `debug.provingGear` (tools-only
  before this wave too).
- `Config/Armory.json`: `slots`, `classes`, `abilities`, top-level `bands`, `partyEffects` gone (row 17).
- `Config/Sounds.json`: the 15 keys the lead routed (`swing`, `finisher`, `bowFire`, `laser`, `gunFire`, `bowDraw`,
  `abilityCast`, `enemyHit`, `enemyDeath`, `playerHit`, `playerDown`, `partyRally`, `partyWarcry`, `lowHp`,
  `waveClear`). `abilityCast`'s 3 `src` hits are WeaponService's `shooter.abilityCast` field, not the sound.
- `Config/ProvingGrounds.json`: `movement.dashProofShare` 0.5, `movement.dashProofSeconds` 0.05 (the names A typed).
- `Layouts/Arenas/ProvingGrounds.luau`: `enemySpawns` gone (B's A-2), and two comments that named the Village arena
  and the mission AI.

Tools and docs:
- `tools/audio_map.json`: the same 15 sound keys (see "For the lead").
- `tools/sim_combat.py`, `tools/sim_range.py`, `tools/check_levels.py`, `tools/check_stage_mirror.py`,
  `tools/crowd_harness/{run_harness.py, mutate.py, stage_mirror.luau}`,
  `tools/crowd_harness/tests_{l1,l1_world,l1b,l3,l3_run,l3_w2,p5}.luau`.
- `docs/BALANCE.md`: "L4 W1b: the old mission code goes".
- `tools/check_levels_mutants.py`: 0 stale (13 MIRROR_CASES, 10 SIM_CASES, 4 swapped sims); 5 new cases for
  `check_adapters_gone` (a level file naming a mission, a layout naming an arena, a proving level with no node, a
  second node naming it: red; the shipped data: green), run alone: `MUTANTS: PASS` (3 min 2 s, 3.12).
- Checked, not changed: `tools/crowd_harness/mirror_mutants.py` (129 mutants, 0 stale).

## Gates (verdict lines)

| Gate | Python | Verdict |
|---|---|---|
| `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5b <luau>` | 3.14 (no shebang) | `HARNESS: PASS (4,075 checks, C:\Users\benja\Desktop\tycoon-p5b\tools\crowd_harness)` |
| `py -3.12 tools/check_levels.py` | 3.12.10 | `CHECK: PASS` (every line HEAD's but the arena's and the map's node lists; 2 new) |
| `py -3.12 tools/sim_range.py --check` | 3.12.10 64-bit | `CHECK: FAIL (1)`, the named R8 row only, 14 min 51 s (HEAD copy: the same FAIL (1), 14 min 55 s) |
| `py tools/sim_combat.py --check` | 3.12 (shebang) | `CHECK: PASS -- all eleven assertions hold`, 4 min 41 s |
| `py tools/sim_combat.py` (the report) | 3.12 | see "Long runs" |
| `py tools/sim_economy.py --check` | 3.12 | `CHECK: PASS -- all eras in band` |
| `py tools/check_stage_mirror.py --luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe` | 3.12 | `CHECK: PASS` |
| stylua --check src; selene (my .luau); luau-lsp, both sourcemaps (built to scratch); `py tools/check_compile.py`; rojo build default + combat (to scratch) | | clean; 0 diagnostics; `CHECK: PASS -- 176 files`; both built |
| §8's `git grep` tripwire on `src tools` | | **empty** |
| `git ls-files --eol \| grep -c w/crlf` | | 0 |

**The worktree has no `tools/bin/luau.exe`:** `check_stage_mirror.py` (and check_levels_mutants' MIRROR_CASES) must
be given `--luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`; §8's bare `py tools/check_stage_mirror.py`
stops with "no Luau interpreter".

### The R8 row, before and after (the one open row)

`forest, Hard at gear 1/4 (only the bow upgraded, L3-26): the sniper from Road3 ...`: **x1.60 before (HEAD copy) and
x1.60 after**, every seed byte-identical: seed 11 39,504 / 55.1 against 24,703 / 37.2; seed 23 18,374 / 27.6
against 23,330 / 34.8; seed 37 2,756 / 0.0 against 21,332 / 31.9.

### sim_range, line by line against HEAD

537 PASS (HEAD 548): the 12 `arena:` gate lines retired, one new (`dash: L4B-7, a forged still dash is invulnerable 0%
of the time; a walk (1.00 studs in 0.05 s) never proves one, a real dash (6.67) does`); every other PASS line
byte-identical. `DASH PROOF`: 118 dashes over every policy, 0 unproven (the human 54, the reacting player 37 + 2 +
1 + 2, stands-to-half 16, the kite 6), so no run moved.

### Long runs

- `py tools/crowd_harness/mutate.py C:/Users/benja/Desktop/tycoon-p5b <luau> "files:StageFlow.luau,LevelGeometry.luau,Combat.luau,VitalsService.luau,DashProof.luau,PositionRing.luau,RunFloors.luau,WeaponService.luau,ArenaService.luau,WaveService.luau"`
  (3.14; every file this wave's engineers changed that has entries, so every entry my re-pointed cases must still
  catch, plus the 32 new): `BASELINE: HARNESS: PASS (4,075 checks, ...)`, **`MUTATIONS: 619 run, 0 not caught`**,
  2 h 27 min. The full run (all 1,693) is QA's.
- `py tools/crowd_harness/mirror_mutants.py --luau <luau>` (3.12): **129 of 129 mutants caught**, 25 min 40 s.
- `py -3.12 tools/check_levels_mutants.py --luau <luau>` (3.12.10): **`MUTANTS: PASS`**, 269 ok, 3 h 19 min (it loaded
  the file before the 5 new L4 W1b cases were added; those ran alone: `MUTANTS: PASS`, so 274 in all). Its FAIL counts
  include the shipped R8 row, as track D's did.
- `py -3.12 tools/sim_range.py --bow` (the bow report, not a gate): runs, the range's bosses only.
- `py tools/sim_combat.py` (the report, not a gate): runs (ladder, Forest Road's pay, the spot checks).

## Retired and re-pointed (L4B-6), one line each

Harness cases retired (their rule is deleted):
- tests_l1 resolveTests: the 8 "Raider Arena is a level of one camp (ruling 27)" checks (Resolve's mission branch).
- tests_l1 resolveTests: the 4 "CampWave on the adapter is CrowdWave on the mission" checks (CrowdWave, CrowdReward,
  BurstInterval, CampReward gone; CampWave and BurstSeconds keep their worked-by-hand cases in campNumberTests).
- tests_l1: "the arena's one difficulty is the map's first" (2 checks; firstDifficulty went with the branch).
- tests_l1 realWorldTests: the adapters compared per arena, and "check_levels.py read every layout that names an
  arena" (replaced by "no shipped layout names an arena").
- tests_l1 realRunTests: the 2 `raiderArena` checks (one camp of ten waves; locks, merges, breather): now the field's.
- tests_l1_world arenaTests: the 13 FromArena checks (spawns from enemySpawns, cover copied, barrier from the wall,
  fence and floor kept, no gates, entry / exit / start / killY, nothing else, new tables, no player spawn, no wall,
  no barrierHeight).
- tests_l1_world pieceTests: "FromArena: size.x is the width" and "a layout that still names its arena is refused".
- tests_l1b rewardTests: "KillReward answers what CampReward answers" (KillReward by hand kept).
- tests_p5 lostTests / reviewTests: the bot halves ("bots alone", "bots never hold a start"; L4B-4); the `bot` members
  dropped from every list, the "nobody" halves kept.
- tests_l3: the half of "legacy.gearCosts is frozen" that read `Armory.json slots` / `bands`; pinned to `L3.LEGACY`.

Harness cases re-pointed to the hand-written fixtures `L1W.field()` (tests_l1_world) and `L1.fieldLevel()` /
`L1.field()` (tests_l1), what the arena resolved to:
- tests_l1 planTests (validate, plan, begins armed, no Hard), waveTests (ten waves, merges 1+2 3+4 6+7 8+9, six
  clears), skipTests (B arms wave 5, Force), resolveTests (the field's one merging camp).
- tests_l1 mapTests: the side node `raiderArena` renamed `outpost` (its kind kept; §8's tripwire).
- tests_l1 campNumberTests: the hand-worked pays through `Combat.KillReward(rewards, kind, mult)`.
- tests_l1 "a level keeps its file's id": a Road file renamed `roadNorth`.
- tests_l1_world closeTests and fieldTests (barrier thickness 0, the fence's 4 boxes, the wall, 17 Parts, the
  floor's depth, the bounds); tests_l1b worldTests ("a gateless camp that locks keeps its invisible wall").
- tests_l3_run: "a difficulty that names no firstClear gives nothing", on the field.
- Resolve called with two arguments everywhere (tests_l1, tests_l1b, stage_mirror.luau).

Harness additions:
- tests_l1 realMapTests: §3's "RequestStartLevel ... locked" on the real map, mirrored from WaveService's loop
  (`L1.real.startable`): forestRoad starts, a level no node names is locked, every level file is an open node's; and
  no `bonus` node or theme ships. The id used is `noSuchLevel`: §8's tripwire forbids spelling the old one in `tools`.
- tests_l3_w2 `L4BP` (`source.l4b`, 30 checks): A's item-6 lines (OnDash, trackAir, proveDash, openIframes, resetAir)
  and B's ArenaService and WaveService pins, counted on code with comments blanked, plus two order pins.
- run_harness.py: `DashProof`, `RunFloors` in SOURCES; `tests_l4b.luau`, `tests_l4b_run.luau` in TESTS; the
  village / missions / arenas fixtures and the arena bundling gone; `l4b_reading`.

sim_combat assertions:
- Retired: 3 (run length), 7 (merge at 2x), 8 (under-geared), 9 (WaveComposition), 10 (Overdrive cash), 11 (party
  boss waves), 14 (horde shape): the C1 run model. 15-18 (crowd gates, rewards, clear, spec): the crowd mission. 19
  (the adapter). The flags `--era`, `--power`, `--party`, `--overdrive`, and every mirror only those used (tier_def,
  weapon_damage, class_def, ability_def, c1_*, mission_unlocked, wave_*, enemy_stats, boss_valor, recommended_power,
  spawn_interval, crowd_wave, crowd_reward, burst_interval, camp_reward, the slot-tier damage and ability functions,
  simulate_run and its reports).
- Kept: 1 (HP T1-T11 and `legacy` pinned as literals), 2, 5, 6, 20-23, byte-identical where unchanged. 4 re-pointed
  (Forest Road Normal 131,733 = 0.92% of Village's 14,280,000). 12 and 13 rewritten as pure checks of `mentor_pay`, a
  mirror of `WaveService.payMentors` over `mentor_bonus`, on fixture rates and shares.
- `can_ascend` reads `("melee", "ranged")`, as Armory.CanAscend now does.

sim_range: the arena report (`mission_report`, `print_mission`, `check_mission`: 12 gate lines), `arena_view` and the
bow report's arena rows, `arena_as_layout`, `load_arena_points`, `load_rim`, `print_run_rows`, `MISSIONS_DIR`,
`MISSION_FILE`, `MISSION_BOSS_SECONDS`, `MISSION_CLEAR_SECONDS`, `MISSION_STAND_DOWN_SECONDS`, `--mission`, the
`--mission-only` alias and `--level arena`. `resolve_level(file, run_cap)` and `load_level_layout(name)` lost their
mission and arena halves. Added: the dash proof (§4 "Simulator").

check_levels: `check_arena_layout` (5 lines), "a level that names a mission names an arena layout" and the arena cover
note; the file-level `recommendedTier` in the presets line. Added: `check_adapters_gone` (2 lines).

check_stage_mirror / stage_mirror.luau: `Combat.CampReward` per wave (64) re-pointed to `Combat.KillReward` at the
spec's rewardMult; the CampReward grid (75) retired (KillReward's own grid stays); the missions and arenas in the data
and the bundle gone. The arena's Resolve, Plan, scripted runs (merge, breather), Skip and Force re-pointed to
`FIELD_LEVEL` on `FIELD_LAYOUT`: every count matches HEAD's (Resolve 2, Plan 8, scripted runs 20, Skip 8, Force 4),
and "ruling 6: refused alike" grows 24 -> 48 (the field takes the refusal copies the arena skipped).

mutate.py (stale check: 0 of 1,693):
- Deleted (rule gone): "l1b: FromArena not locking", "world: the arena's camp is as wide as the arena is deep",
  "world: the arena's entry is its pad", "world: the level shares the arena's obstacle tables", "l1: the arena adapter
  without merging", "l1: the arena is always played on normal", "real: the arena's level takes its mission's id".
- Re-aimed: "l2: Resolve drops the secrets", "real: a level file's id dropped for its layout's" (one indent less),
  "p5 lost: a member on the pad still fights" (the waiting skip, whole lines), "p5: a start does not wait for bodies"
  (`bodyOf(member.player)`), "l3w2 fix S2: the admit's handler leaves before the hook" (`live.waiting`, B's note).
- New (32, `L4B_MUTATIONS`): DashProof 5 and PositionRing 1 (A's), WeaponService 4 (A's), RunFloors 8 (B's scratch
  list, written from the code), ArenaService 9 and WaveService 5 (B's). `FILES` += DashProof, RunFloors; the explicit
  `Missions/1_Village.json` line dropped (the folder glob still copies it).

## For the lead

- `tools/audio_map.json` is not in §6's list: I dropped the same 15 sound keys there, because `upload_audio.py`
  treats a mapped key with no Sounds.json entry as id 0 and would upload it, then fail in `set_sound_id` with the
  quota slot spent. Revert both files together if you disagree.
- QA needs `--luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe` on `check_stage_mirror.py` in this worktree.
- No remote, project file or hub file touched. No `Economy.luau` formula change is needed.

## For luau-engineer A / B / ui

- Nothing asked. A's and B's relays are applied as written (A's "p5 lost" re-aim uses whole lines instead of the bare
  `if member.waiting then`; the same rule).
