# L4 W1b review — slice 3: data, simulators and gates

Reviewer: roblox-reviewer (slice 3). Branch `l4-w1b` at 1ae8bfb (+ d5635a2, the brief). Diff: `git diff
l4-real-forest...l4-w1b` (merge base 1d3b0d2), restricted to the slice-3 files. Read only: every probe ran on a
`git archive 1ae8bfb` copy in my scratch folder, never in the worktree. Python named for every number.

**Count: 0 Critical, 0 Major, 3 Minor, 4 Suggestions.**

## Findings

### Minor 1 — the simulator's dash proof ignores when the proof arrives, so "no run moved" is an artifact

`tools/sim_range.py:2704-2727` (`dash_proven`, `start_dash`), `:2801-2806` (`plan_shielded`), `:2451-2453`
(`shielded`); `docs/BALANCE.md` "L4 W1b: the dash proof in the simulator".

**What the sim does.** It judges a dash at its first frame. If its path will cover `dashProofShare` of the dash speed in
`dashProofSeconds`, it appends the window `(t, t + dashIframes)` at once. A hit is then voided if that window meets
`[impact, decided]`, even when the dash began in the very frame the hit is decided.

**What the game does.**
- VitalsService voids a hit only if the window is already open when it decides (contract §4.4).
- The window opens only when `DashProof.Verdict` proves the claim on a Heartbeat ring sample.
- tests_l4b (a) measures that proof one Heartbeat after the first moving sample at smooth 60 Hz, which is two
  Heartbeats after the server's copy starts to move. At 20 Hz it comes at the first batch, up to 0.05 s in.
- So a dash whose motion starts at or just before the decision cannot dodge.

**Measured** (review probe `dash_late.py`, `py -3.12`, scratch copy; it counts hits voided only by a dash window, and
how long before the decision their dash began):
- **On Forest Road:** 85 such voids. 33 come from a dash that began in the same frame as the decision (margin 0), 66
  from one within 0.05 s. The median margin is 0.033 s.
  - The reacting player gives 26 of the margin-0 voids. The human (0.55 s) gives 32 of those under 0.05 s.
- **In the range sets:** 17 such voids, 2 of them under 0.05 s.

**Modelled** (review probe `dash_delay.py`, a full `py -3.12 sim_range.py --check`). A dash window counts only for a hit
decided at least DELAY after the dash began, both in `shielded` and in `plan_shielded` (the player plans for it). At
DELAY 0 the sim is unchanged. At DELAY 0.0334 (two Heartbeats) and at 0.05 (one 20 Hz batch) the outputs are the same:
- **Gates:** `CHECK: FAIL (1)`, the same known R8 row and nothing else. No gate flips.
- **The R8 row** (Road3, Hard, sword T1 / bow T4) moves from **x1.60 to x1.65**. On seed 11 it is 39,504 / 55.1 against
  23,909 / 36.1 (was 24,703 / 37.2), because the mission player it is compared with changes.
- **69 of the 145 forest gate lines** print other numbers, for example Normal seed 37's clear 5.04 -> 4.70 min.
- **The human-reaction player** takes 1 or 2 more hits per Hard and Brutal run: Hard 10/10/12 -> 11/12/12, Brutal
  9/10/12 -> 10/12/12, still no down.

The range sections print the same numbers as at DELAY 0.

This is related to slice 1's Minor 3, which measures the same late edge in the game itself (the proof's timing against
the decision). This finding is what that latency does to the simulator's numbers and gates.

So the BALANCE text "every simulated dash ... was proven ..., so no run moved: every gate line is byte-identical to
HEAD's" holds only because the mirror treats a same-frame dash as proven. The "R8 x1.60 before and after" the designer
was held to is likewise a property of the mirror. The contract's §4 Simulator text asked only for the distance rule,
so this is a gap in the spec as much as in the code.

**Failure scenario.** Ben rules on the R8 row at x1.60. The sim also reports that L4B-7 cost nothing in every fight.
With the proof's latency, the honest number is x1.65, and the human player is hit more often on Hard and Brutal.
§4.5's "the cost, said plainly" is the one thing the sim was asked to measure, and it reads zero.

**Fix.**
- In `start_dash`, record the dash's proof time: `t + PROOF_LATENCY`, where the latency is the ring's two Heartbeats
  (or `dashProofSeconds`, the contract's 20 Hz bound). Name it as a constant beside `FRAME`, documented against tests_l4b
  (a).
- In `shielded(start, until, t)`, count a dash window only when its proof time is at or before `t`.
- In `plan_shielded`, apply the same rule (`t0 + latency <= until`).
- Re-run, and give the lead and BALANCE the moved R8 number (x1.65 here) and the human's extra hits.
- Add a gate line in the sim: a dash begun in the decision's frame does not dodge.

### Minor 2 — the branch that makes L4B-7 work is not pinned: "a pending claim opens" survives every gate

`tools/crowd_harness/run_harness.py:1445-1455` (`L4B_LINES`, the WeaponService half),
`tools/crowd_harness/mutate.py:8024-8056` (`L4B_MUTATIONS`, WeaponService).

**What the pins cover.** The pins count call text:
- in `proveDash`: `proveVerdict` and `proveOpen`;
- file-wide: the `openIframes(` count;
- in `OnDash`: `dashNoOpen`, the literal `openIframes(`.

**What they miss.** They do not pin the two branch lines that decide what a verdict does: `WeaponService.luau:1995`
(`if verdict == "proven" then`) and `:1998` (`elseif verdict == "lapsed" then`). Nor does any pin catch a helper that
opens a window.

**Probes.** Review-only mutants on the scratch copy, each alone, `HARNESS: PASS (4,075 checks)`:
- **`if verdict == "proven" then` -> `if verdict ~= "lapsed" then`.** Every claim opens its window, from the request,
  on the first Heartbeat after it, moved or not. A still client holds 0.25 s of every 0.64 s again (39%): this is the
  exploit L4B-7 closes. `openIframes(` is still spelled three times, and `proveOpen` still once.
- **`OnDash` adds `WeaponService.GrantIframes(player, movement.dashIframes)`.** This also opens on the request alone.
  `dashNoOpen` counts only the literal `openIframes(`. `DashProof.Open(` called from OnDash would pass the same way.
- **`elseif verdict == "lapsed" then` -> `else`.** A claim not proven on its first frame is dropped. A dash whose motion
  replicates a frame after its remote, the 20 Hz bunched case tests_l4b (a) measures, never earns its window.
- **trackAir's no-root `shooter.dashClaimAt = nil` (`WeaponService.luau:2022`) deleted.** The brief lists "claims
  cleared on ... death", but only `resetAir`'s clear is pinned (`resetDropsClaim`).
- **Also surviving, on lines that predate this wave:** OnDash's `shooter.lastDashAt = now` deleted (no cooldown, so a
  claim per request); OnDash's `VitalsService.IsDown(player)` refusal dropped.

**Overlap.** Slice 1's Minor 1 reports the same branch line from the server side, so count it once. This entry adds the
`GrantIframes` path and the `lastDashAt` survivor. It also puts the fix where it lives: `run_harness.py` and
`mutate.py`, the designer's files.

The contract's "open on the request" mutant is a literal `openIframes` in OnDash. A one-word change in proveDash's
branch, or a helper call, reopens the same hole unseen. This is the recurring pattern from the L3 reviews: pins hold
call text, not the branch around the call or a helper that does the same.

**Failure scenario.** §4.5 warns that Ben may find dodging harder. A later "feel" edit opens on pending, or grants from
OnDash. The anti-cheat is gone, and the harness, mutate and check_compile all stay green.

**Fix.**
- Add these to `L4B_LINES` as whole lines with their indentation, each counted 1:
  - in `PROVE_DASH_BODY`: `\tif verdict == "proven" then` and `\telseif verdict == "lapsed" then`;
  - in `TRACK_AIR_BODY`: `\t\t\tshooter.dashClaimAt = nil`;
  - in `ON_DASH_BODY`: `\tshooter.lastDashAt = now`.
- Count 0 of each of these in `ON_DASH_BODY`: `GrantIframes(`, `DashProof.Open(`, and an `iframesUntil` write.
- Put the first three probes above into `L4B_MUTATIONS`.

### Minor 3 — mentor pay: assertions 12 and 13 guard a Python copy that nothing ties to the Luau

`tools/sim_combat.py:1496-1514` (`mentor_pay`), `:1600-1643` (assertions 12, 13); `tools/check_stage_mirror.py:236`
(`NEEDED["Combat"]` has no MentorBonus).

The contract calls 12 and 13 "the only guard on `WaveService.luau:720-770`'s mentor pay". But `mentor_pay` and
`mentor_bonus` are hand copies, and nothing holds them to `WaveService.payMentors` or to the Luau `Combat.MentorBonus`.
No harness case or pin reads either, and check_stage_mirror does not compare MentorBonus.

Review-only mutants, each `HARNESS: PASS`. `sim_combat.py` never loads Luau, so it cannot see them either:
- payMentors pays a waiting mentor (the `mentor.waiting or` dropped);
- payMentors counts mentees under the damage floor;
- `Combat.MentorBonus` with `rate <= threshold`. This breaks the strict ratio that assertion 12's "a mentee at exactly
  1250/s is not carried" pins, but only in Python.

The gap is older than this wave: the old 12 and 13 ran a Python run model too. But this wave rewrote them as pure checks
and named them the guard, and the cheap tie is right here.

**Fix.**
- Add `MentorBonus` to check_stage_mirror's `NEEDED["Combat"]` and compare it on assertion 12/13's fixture rates plus
  the `hostRate x mentorRatio` edge. The tool already loads Combat.
- In `run_harness.py`, pin payMentors' two floor lines and its `Combat.MentorBonus(` call as whole lines, the way
  `L4B_LINES` does.

## Suggestions

- **S1 — DashProof's edges are unpinned** (`DashProof.luau:50-73, 82-98`). Each of these survives the harness:
  - `speed >= rule.speed` -> `>`: no case sits exactly on the 66.7 studs/s line;
  - `Rule` accepting a negative `lookback`;
  - the comment's "a proof wins over a lapse judged in the same frame", rewritten so that the lapse wins.

  Add one tests_l4b case for each: a stretch exactly at the threshold; `originLagMaxSeconds` -1 gives no rule; a claim
  first proven on the frame it lapses.
- **S2 — two real-data checks pin today's map shape, not a rule** (`tests_l1.luau` realLevelTests
  `table.concat(played, " ") == "forestRoad"`, realMapTests `#bonus == 0 and map.themes.bonus == nil`).
  - The first fails as soon as the Castle gets a level file.
  - The second fails on the first side node (a secret's second exit), a kind §3 keeps on purpose.
  - The rule §3 asks for, "a level no node names is locked", is already held by `L1.real.startable`.

  Prefer "every built node's level is played" and drop the bonus-absence half.
- **S3 — the field fixture has three hand copies** (`tests_l1.luau` `L1.fieldLevel`, `tests_l1_world.luau`
  `L1W.field`, `check_stage_mirror.py:187-232` `FIELD_LEVEL` / `FIELD_LAYOUT`).
  - They agree with each other.
  - Against the old Village crowd block they agree on the scales, waves, targets and crowd numbers. They drop one
    price: `guard` (the Warlord's guard, 2,000 / 5), so the field's wave-10 summons are unpriced. This is harmless to
    merge, breather and barrier.
  - One JSON fixture under `tools/crowd_harness/fixtures/`, read by both the harness and the mirror, would stop the
    copies drifting.
- **S4 — the hub stub's `waves` 3 is not what a Forest Road clear counts** (`Config/Missions/1_Village.json:7`). For
  the lead, since the value is the contract's (L4B-1).
  - `ArenaService.MarkWaveCleared` counts StageFlow `clear` actions. Only the locking boss room emits them (2 waves);
    open camps emit `campClear`.
  - So after a full clear the hub card reads "Waves cleared 2 / 3", and the tile says "3 waves".
  - It was "2 / 10" before. W3 replaces both, and the publish freeze holds. Set it to 2, or note it in W3's list.

## Checked and clean

- **The R8 row is unchanged.** `py -3.12 sim_range.py --check --levels-only --level forest` on the copy gives
  `CHECK (levels only): FAIL (1)`, the one named row: seed 11 39,504 / 55.1 against 24,703 / 37.2 (x1.60), seed 23
  18,374 / 27.6 against 23,330 / 34.8, seed 37 2,756 / 0.0 against 21,332 / 31.9. This is the designer's number exactly
  (but see Minor 1 for what a latency-aware mirror makes of it).
- **Removed keys have no live reader.** Grepped every removed key in `src` and `tools`.
  - **`Combat.json`** (`enemy`, `ai`, `crowdSkeleton`, the seven `player` keys, `remotes.attack/abilityCallsPerSecond`,
    `director.maxAlive`, `animations.enemy*`, the six debug keys, `camera.touchAimAssistDegrees`, the `feel` /
    `feedback` keys): 0 readers outside Types. The two `hitstopSeconds` hits are a FeedbackController local, not the
    key.
  - **`Armory.json`** (`slots`, `classes`, `abilities`, top-level `bands`, `partyEffects`): 0 readers in `src`. In
    `tools`, only `ladder.bands` is read, the ladder's own key.
  - **`ProvingGrounds.luau enemySpawns`:** 0 readers, and `Types.ArenaLayout` no longer declares it.
  - **Kept keys.** I listed every kept `Combat.json` key with at most 2 readers. Only `overdrive.spawnRateMult` is now
    type-only, which L4B-2 sanctions (the block stays until W3). `debug.provingGear` was already reader-less at the
    base.
- **Sounds.** `Sounds.json` and `tools/audio_map.json` hold the same key set (computed, both differences empty).
  - None of the 15 removed keys appears as a string anywhere in `src` or `tools`.
  - At the base their only players were the deleted C1 paths (CombatFxController, CombatUIController's `waveClear`,
    InputController's `swing` / `finisher` / `abilityCast`).
  - Every kept combat key is still played (`waveStart`, `bossStart`, `bossDown`, `runEnd`, `mentor`).
  - Neither `gen_asset_manifest.py` nor `ASSET_MANIFEST.md` lists sounds.
- **The hub stub `Missions/1_Village.json`** serves every hub reader:
  - `UIController`'s tile list (`GetMissionConfig` by era; eras 2-4 return nil silently);
  - `ExpeditionPanel`: `id`, `name`, `era`, `waves`, `targetMinutes`, `material`, `RecommendedPower`, `MissionUnlocked`;
  - `ExpeditionService`: Depart (`GetMissionById`, then `MissionUnlocked`) and the fakeRuns lever's `era`;
  - `ExpeditionSummaryCard`: `name` and `waves`;
  - the dungeon's `ArenaService:856` registry `era`.

  None of them reads `arena`, `enemies`, `waveTable`, `bosses` or `crowd`.
- **Every retired test's rule is gone from `src`:** Resolve's mission branch, `firstDifficulty`, FromArena and the
  "names the arena" refusal, `CampReward`, `CrowdWave`, `CrowdReward`, `BurstInterval`, `RunMember.bot`, and Armory
  `slots` / `bands`.
  - sim_combat 3, 7-11 and 14 used the C1 run model. At the base, Village was already reported "retired" in them as a
    crowd mission. 15-18 were the crowd mission, and 19 was the adapter.
  - The kept rules they touched are guarded elsewhere: `bossHpPerExtraPlayer` in tests_l1 campNumberTests and by mutate's
    `bossHpMult = 1`; the BurstSeconds edges (no burst, no tempo) in campNumberTests:954.
- **Assertion 1's literals.** `LADDER_HP_T1_T11` and `LEGACY_GEAR_COSTS` equal the deleted slot tiers 2-12's HP and
  prices exactly. The diff of the old and new `ladder_problems` is only those two blocks. tests_l3's `L3.LEGACY` is the
  same twelve prices.
- **The re-pointed fixtures still exercise their rules.** Review-only mutants, each CAUGHT:
  - **Harness:** never merge (5 checks fail); merge into a boss wave (2); no director's breather (2); the barrier only on
    a camp with gates (2: "the camp is 17 Parts", "a gateless camp that locks keeps its invisible wall").
  - **check_stage_mirror alone, the three StageFlow mutants:** each `CHECK: FAIL (9)`. The field's scripted runs differ
    in 5 of 20, Skip in 2 of 8, Force in 1 of 4.
  - check_stage_mirror's baseline PASSes under both 3.12 and 3.14.
- **`sim_combat.mentor_pay`** matches `WaveService.payMentors` line by line: the waiting and floor skip, mentees as
  other members over the floor, nobody paid when the total is 0.
- **`check_adapters_gone` and its five check_levels_mutants cases.** `nodes[0]` is `forestRoad`, so "a second node"
  really duplicates the proving level's node. `py -3.12 tools/check_levels.py --no-plan` on the copy: `CHECK: PASS`
  (29 s).
- **`py tools/sim_combat.py --check` on the copy** (3.12, shebang): `CHECK: PASS -- all eleven assertions hold` (4 min).
  Assertion 4: 131,733 = 0.92%.
- **`mutate.py`'s stale check**, exec'd up to its baseline: 1,693 entries, 0 stale.
  - `FILES` holds DashProof and RunFloors. It still holds `Missions/1_Village.json` through the folder glob, which is
    harmless.
  - The deleted entries (FromArena, the adapter's merge, normal-only, the mission's id) all target deleted rules. The
    re-aimed ones keep their rule.
- **The DashProof mutants are caught** (each run alone): Open's third branch dropped (2 checks); span = the whole window
  (15); lapse without lookback (6).
- **No tool names a deleted file or function:** `mirror_mutants.py` names none, and none of `arena_as_layout`,
  `MISSIONS_DIR`, `simulate_run`, `camp_reward`, `crowd_wave`, `EnemyService`, `CombatService` or the deleted layout
  paths appears in `tools`.
- **The contract's tripwire grep** on `src tools` is empty, and `git ls-files --eol | grep -c w/crlf` is 0.
- **`resolve_level(file, run_cap)` matches `StageFlow.Resolve(file, runCapSeconds)`** field for field, now that
  `mission` is gone from both. The one difference predates this wave: Python treats an empty `stages` list as missing,
  Luau only nil. Both refuse such a file, so ruling 6 holds.

## Probe files (session scratch, not in the repo)

These are all under
`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\3f855f00-eb33-4bab-adb5-c937f685030c\scratchpad\l4w1b3\`:
- `probe.py` and the `p_*.json` mutant lists;
- `dash_late.py` and `dash_late.out`;
- `dash_delay.py` and `delay033.out` / `delay050.out`;
- `sim_range_forest.out`.
