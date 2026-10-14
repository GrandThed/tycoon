# L1b Wave 1 — luau-engineer B (the run): report

Contract: `docs/INTERFACES.md` "L1b contracts — the living road" → "B — the run", "Flow",
"Types", "Definition of done (Wave 1)". Written by the second B (the continuation of 2026-10-14):
the first B was cut off by the session limit; its work is in `55dcca0` and was reviewed against the
contract here, not redone.

## State found at the start

- `StageFlow`, `Combat`, `LevelGeometry`, `LevelService`, `WaveService`, `ArenaService`,
  `tests_l1b.luau`, the `tests_l1` / `tests_l1_world` updates and `run_harness.py` were complete
  against the contract. `ArenaService.memberEntry` already set `engaged` (routed item 2), through a
  new `ArenaService.SetEngagedSource` hook that `WaveService.Init` wires to
  `isLive(run.phase) and CrowdService.Engaged(userId)`.
- `mutate.py` held A's 36 entries, the 11 stale replacements, the new `FLOOR` / `DIED` constants,
  `CAMP` in `FILES` and B's run mutations, but **did not parse**: the L1 entry "l1: a stage's cap
  is always the level's" had been half-edited with raw newlines inside a string literal. Fixed (its
  text now reaches into the next line, `\n\t\tcaps[zone.id] = cap`, because the old one-line text
  also occurs in `Validate`'s population loop).

## What B built (pure functions, file:line)

`src/combat/server/Services/StageFlow.luau`:

| Function | Line |
|---|---|
| `Resolve` (camps = file.camps or {}; the arena: camps {}, no bankEachWave) | 215 |
| `fieldedUnits` (minDifficulty, countMult never read) | 375 |
| `groupsOf` (one CampGroupDef per resident group, shared by Plan and Validate) | 398 |
| `populationOf` (L1b-11's left side) | 446 |
| `campProblems` (Validate's L1b lines) | 466 |
| `Validate` | 703 |
| `Plan` (zones for every camp, groups, population) | 958 |
| `FieldClear` (L1b-19) | 1110 |
| `RescueGrace` (L1b-20) | 1120 |
| `leaveCamp` (sets `done` of the boss room) | 1192 |
| `progress` (checkpoints, open camps' clears) | 1219 |
| `Advance` | 1260 |
| `Skip` / `Force` | 1399 / 1499 |
| `SafePoint` (L1b-18) | 1557 |

`src/shared/Combat.luau`: `whole` 765, `SplitCarry` 770, `KillReward` 852, `CampReward` 865
(= `KillReward` at `spec.rewardMult`). `SplitPool` is gone (no caller left; its Python mirror in
`sim_combat.py` is the economy-designer's to keep or drop).

`src/combat/server/Services/LevelGeometry.luau`: `FireBox` 375, `FromArena` 558 (`locks = true`),
`Pieces` 647 (gates and wall only when `locks`). `LevelService.SetCamp` 540 (`"reached"`; open and
closed change nothing on an open camp).

## The three boss-room blockers, fixed per floor (L1b-14)

`src/combat/server/Services/WaveService.luau`:
1. The `gate` action sets nothing on the crowd: `setCrowdFloor` is removed, and `execute` has no
   `gate` branch (comment at line 1200: "`gate` sets nothing on the crowd (L1b-14: the floors were
   set at the start)").
2. The locking camp's clear counts its own floor only (`advance`, line 1293):
   `local alive = if live ~= nil then CrowdService.AliveOn(live.floor) else 0`
3. A burst is held by the boss room's own floor, residents included (`spawnBursts`, line 917):
   `while burst.left > 0 and CrowdService.AliveOn(zone.floor) < stage.maxAlive do`

## Routed items (docs/prompts/l1b-w1-continue.md, "For B")

1. `mutate.py`: `CAMP` is in `FILES`; A's 36 entries (`L1B_CROWD_MUTATIONS`) and the 11 stale
   replacements (`STALE_REPLACEMENTS`, same labels, a dict update keeps their place) are in; `FLOOR`
   and `DIED` carry A's new texts. Every entry's text occurs exactly once (checked: 0 stale).
2. `PartyMember.engaged`: `ArenaService.memberEntry` sets `engaged = isEngaged(member)`, from the
   hook `ArenaService.SetEngagedSource`, which `WaveService.Init` sets to
   `isLive(run.phase) and CrowdService.Engaged(userId)` (never in the lobby or on the summary,
   where the crowd's last step may still say so; always false for bots). It changes with the
   periodic RunState broadcast (`combatStateHz`), no extra send. The ui-engineer can now hide
   Abandon on touch while the local member's `engaged` is true.
3. A's rulings (Busy / Engaged count only groups with a living member; CampBrain on `simTime`):
   nothing in B's files depends on more than the API, and both hold.

## L1 cases changed (tests_l1.luau, tests_l1_world.luau), and by what

`tests_l1_world.luau`: the fixture camps `L1W.camp()` and `L1W.oblong()` gain `locks = true` (L1's
gate, wall and close cases are about a camp that locks; open camps are tested in `tests_l1b.luau`).
No check changed.

`tests_l1.luau` (the L1 fixture's three camps all lock, so its stage cases hold less the bank;
`L1.input` still takes L1's `fieldClear` and turns it into the L1b Input):
- the arena adapter: "banks at every wave clear" → no `bankEachWave` and `#level.camps == 0`;
  its plan's camp `locks`.
- a camp's fields: `bankEachWave == false` → `== nil`.
- "a level of one camp is legal" → judged with a layout whose other camps are open.
- wave 1 of 2: `clear` carries `count` 1; "clear bank boundary open travel" → "clear boundary open
  travel" (with `count` and `state.done`); a camp of one wave, the last camp's clear, the merged
  pair (`clear.count` 2), "a wave clear counts that wave" (was "with bankEachWave a wave clear
  banks"), "the camp's clear counts only the last one".
- the arena's ten waves: six clears count all ten waves, none banks (was six banks).
- the last wave of the last camp: no `bank` in the batch (was: one).
- "on the road the field is always clear" → "on a quiet road (no group awake) a death costs a
  respawn" (L1b-19).
- the run cap: "nothing is banked" dropped from the text.
- skips: N in the last camp marks it done; B from the first road marks the camps between done;
  killing the boss after a skip "clears" (was "banks") his wave alone.
- the stars and boundary batches: "clear bank boundary open end" → "clear boundary open end".
- the fuzz: `field` = "no gate with a body queued" (was "with a body alive or queued");
  `bank` = "no bank, ever"; `count` = the clears counted every wave exactly once.
- the real files: `plan.camps == #layout.camps` and `#plan.zones` (was the camp stages); an open
  camp has no gate and no invisible wall (was: every camp has both); "each camp's bank" → "each
  with its clear"; banks → clears counted; Raider Arena: its camp locks (was `bankEachWave`).
- the Part count of the real files compares `LevelGeometry.Pieces` with `check_levels.py`'s
  `part_count` (67 for Forest Road: 73 less 6 per open camp, plus one per fire), which agree since
  the economy-designer's update.

## L1 mutations retired, and what holds each rule now

| Retired (L1) | Replaced by |
|---|---|
| l1: a camp clear without bank | l1b: a bank emitted |
| l1: bankEachWave ignored | l1b: a clear does not settle its waves |
| l1: a bank counts one wave whatever it covers | l1b: a clear counts one wave whatever it covers |
| l1: the arena adapter without bankEachWave | l1b: Resolve drops the file's camps |
| l1: CampReward ignores rewardMult | l1b: KillReward ignores rewardMult |
| l1: CampReward floors | l1b: KillReward floors |
| l1: SetBounds accepted with a body alive | A's "l1b crowd: SetFloors accepted with a body alive" |

Changed in place (text only): "l1: a stage's cap is always the level's" now names
`...maxAlive\n\t\tcaps[zone.id] = cap` (the one-line text occurs twice since `Validate` reads the
same cap). A's 11 stale entries are listed in `A-crowd.md`.

`l1b: Resolve drops the file's camps` was **not caught** on the first run (no case resolved a
level file with camps). New cases in `tests_l1b.luau` planTests, "Resolve: a level file's camps
reach the plan" (3 checks): the file's camps are kept, Plan places their groups (6, population 68),
a file with no camps resolves to `{}`. Now caught (2 checks fail).

Added by this B (12, all caught): Validate without the population gate; a locking camp no stage
names passes; Validate takes a checkpointReach of 0 / a negative populationReserve / two camps
entries for one camp / a spot id used twice / a fire of radius 0; a minDifficulty unit joins one
difficulty late; a zone counts no residents; a checkpoint at the world's height; reach twice;
SafePoint in the countdown is a checkpoint.

## Gates (B's files), 2026-10-14

| Gate | Result |
|---|---|
| 1. `stylua --check src`; `selene src` | clean; 0 errors, 1 warning (the old `LegacyPanel` one) |
| 2. both sourcemaps | written |
| 3. luau-lsp, hub (`src/shared src/server src/client`) and combat (`src/combat`) | 0 problems each |
| 4. `py tools/check_compile.py` | PASS, 152 files; none of B's modules is in the top counts (all under 130) |
| 5. `rojo build` test, combat, `.proving.project.json` → proving | all three built |
| 11. `run_harness.py` | **HARNESS: PASS (1,531 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)** |
| 11. `mutate.py` (after, alone) | **MUTATIONS: 495 run, 0 not caught** (baseline 1,531 checks) |
| 12. `git diff --stat main -- src/server src/client` | only `src/client/UI/Theme.luau` |
| 13. ProvingGrounds / Missions / Arenas vs `main` | no diff; `tests_w2`, `tests_s2`, `tests_s3`, `tests_p5` identical; `tests.luau` differs at A's one call site |

## For the other owner

- **economy-designer:** (already on their list, from their own report) `check_levels.py` still
  FAILs 4: its `levels` key list does not know `checkpointReach`, `populationReserve`,
  `walletSendSeconds`; "camp stages name the layout's camps in the route's order" must read only
  locking camps (Forest Road: C); A's and B's checkpoints are checked as "on its floor" (the L1b
  gate is the reverse: outside it). `sim_combat.py` reads `bankEachWave`; `check_stage_mirror.py`
  (line 574) and `stage_mirror.luau` (line 202) still pass `bankEachWave`; `SplitPool` is gone
  from `Combat.luau` (its Python mirror may go too). The harness's Part-count case agrees with
  `check_levels.part_count` now (67).
- **lead (an untouched file):** `ReturnService.luau` line 176 still writes `savedAt = ""` into a
  `Types.RunResult` literal. luau-lsp accepts it, but the field is gone from the type; the exact
  diff is to delete that one line.
- **ui-engineer:** `PartyMember.engaged` is now filled (see "Routed items" 2).

## Contract points

1. **`StageFlow.Plan` takes a sixth argument, `ranks: { [string]: number }?`** (the place of each
   difficulty in Expeditions.json). The contract's signature has five, but `minDifficulty`
   (L1b-10) cannot be judged without the ranks. nil = no `minDifficulty` unit is fielded.
   WaveService passes `difficultyRanks(map)`.
2. **The director's dead fraction in a boss room with residents.** `advance` computes
   `deadFraction` from the live floor's `alive`, which counts the boss room's residents (woken at
   the close) while `spawnedThisGroup` counts only queued bodies: while residents live, a merging
   stage merges later than the bodies killed say. Forest Road's camp C does not merge and the arena
   has no residents, so nothing plays differently in Wave 1; worth a rule before a merging stage
   gets residents (Wave 2).
3. **`KillAll` (A's point 7):** it bypasses `Damage`, so it kills held and homeward residents and
   credits them (an even split, or the body's own damage book). Right for a Studio lever.
