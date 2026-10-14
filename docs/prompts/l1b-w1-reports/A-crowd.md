# L1b Wave 1 — luau-engineer A (the crowd): report

Contract: `docs/INTERFACES.md` "L1b contracts — the living road" -> "A — the crowd", "Types",
"Definition of done (Wave 1)".

## What I built

- **`src/shared/Types.luau`: the whole Types block, landed first.** `CrowdState` gains `rest` and
  `rise`. `CrowdSpawnInfo` gains `floor?`. New: `CrowdFloor`, `CampPosture`, `CampGroupState`,
  `CampPostureRules`, `CampRulesConfig`, `CampRect`, `CampUnit`, `CampGroupDef`, `LevelSpot`,
  `LevelResidentGroup` and `LevelCampConfig`. `LevelCamp` gains `locks?` and `spots?`; `LevelFile`
  gains `camps?`; `LevelConfig` gains `camps`; `LevelCrowdConfig` gains `clearBonus?`.
  `LevelStage` loses `bankEachWave`. `CombatConfig` gains `camps`. `CombatLevelsConfig` gains
  `checkpointReach`, `populationReserve`, `walletSendSeconds` and `fireMarkerSize?`. `RunState`
  loses `floor` and `banked` and gains `floors`. `RunResult` loses `savedAt`. `CombatFxCamp`
  loses `saved` and gains `ids?`. The hub typechecks clean with it.
- **`src/shared/CrowdCodec.luau`:** `STATES` appends `"rest"` (8) and `"rise"` (9). The version
  stays 2 and entries stay 11 bytes.
- **`src/combat/server/Services/CampBrain.luau` (new, pure):** every rule of "A — the crowd",
  with the contract's signatures and exported types (`Post`, `Resident`, `Seen`, `Shooter`,
  `Member`, `StepInput`, `Group`).
- **`src/combat/server/Services/CrowdBrain.luau`:**
  - `SetFloors` replaces `SetArena`.
  - `BeginStep(now, gravity, shotsAlive, fastest)` drops `floorY`.
  - `AddTarget(userId, position, lift, lag)`: `lift` replaces `standY`.
  - `Think(..., free, allowed?)`; `allowed` also reaches an enraged chain's target choice.
  - `Body.floor`. `land` writes `strike.floorY` from the top of the attacker's own floor.
  - `inArena` and `runway` take the body's floor rectangle. `ahead` leads a fall down to the
    attacker's floor + `lift`.
- **`src/combat/server/Services/CrowdService.luau`:**
  - A list of floors. `SetFloors` is refused for an empty list, a non-finite value, or while a
    body is alive; it forgets every group. `SetBounds` = one floor at index 1.
  - Per-body `floor`. Clamp, integrate, spawn lift and summon read the body's own floor. A summon
    takes its summoner's floor and no group. `spawnInfo.floor` is always set.
  - `aliveOn` per floor, kept with `aliveCount` (the `noteGone` helper).
  - Groups: `SetCampRules`, `AddGroup`, `SpawnResident`, `WakeFloor`, `ClearFloor`, `AliveOn`,
    `Awake`, `Busy`, `Engaged`, `DrainGroupEvents`, and the exported `GroupEvent` type.
  - The camp step runs after `gatherTargets` and before `Commit`. Each group's input is built in
    reused tables: a `member` and `shooter` record per resident, a `seen` record per userId.
  - A resident thinks with the brain (with `allowed = inPlay`) only while its group fights.
    Otherwise it walks to `CampBrain.Goal`, shows `CampBrain.Shows`, and faces its post's yaw
    when it stands at rest.
  - The heal (HP, plate, `damageBy` cleared, stagger ended) is applied before `Step`.
  - `Damage` asks `CampBrain.Struck` right after the "gone" and "dead" checks.
  - No yield, no raycast, no per-body allocation in the camp step. Only a change of state
    allocates (one `ids` list).
- **`tools/crowd_harness/tests_l1b_crowd.luau` (new):** every case the contract lists, 165
  checks. The crowd cases swap in their own crowd config and put the old one back. The range
  fixture is a hash of a P4 range set's snapshot bytes over 30 steps. I recorded it on the code
  before L1b (2948329570, 2,400 bytes, deterministic across two runs at different ids and clocks)
  and it still matches.
- **`tools/crowd_harness/tests.luau`:** only the `BeginStep` call site changed (line 358). The
  `AddTarget` call keeps its `3`: it is now a lift, the same number on a floor at y 0.

### New pure functions (file:line)

`src/combat/server/Services/CampBrain.luau`:

| Function | Line |
|---|---|
| `Problems` | 123 |
| `NewGroup` | 162 |
| `Posts` | 179 |
| `Sees` | 257 |
| `InPlay` | 285 |
| `AtPost` | 311 |
| `Step` | 329 |
| `Release` | 393 |
| `Evades` | 404 |
| `Struck` | 411 |
| `Goal` | 421 |
| `Shows` | 458 |

The executor is in `src/combat/server/Services/CrowdService.luau`:
- `heal` 885 and `campStep` 930;
- `SetFloors` 1287, `SetBounds` 1294, `SetCampRules` 1300;
- `AddGroup` 1843, `SpawnResident` 1892, `WakeFloor` 1912, `ClearFloor` 1920;
- `AliveOn` 1943, `Awake` 1948, `Busy` 1960, `Engaged` 1972, `DrainGroupEvents` 1977.

## Gates (A's files)

| Gate | Result |
|---|---|
| `stylua --check` | clean |
| `selene` | 0 errors, 0 warnings |
| `py tools/check_compile.py` | PASS, 152 files; my modules are all under 99 top-level locals |
| luau-lsp, `src/combat` on the combat sourcemap | 0 problems |
| luau-lsp, `src/shared src/server src/client` on the hub sourcemap | 0 problems |
| Harness, real `run_harness.py` (B has registered both new case files) | 1,397 checks, 1 failing |

The failing check is not mine: `ForestRoad: 67 Parts, the number check_levels.py counts (73)`.
That is LevelGeometry against `check_levels.py`, which belong to B and the economy designer and
were mid-edit. All 165 of my checks pass. Before B's registration, my scratch runner ran my file
right after `tests_p5`: 739 checks, PASS.

My mutations were run with my own scratch mutator (`mutate.py` is B's): 36 new ones and 11 stale
replacements, **47 run, 0 not caught**. B should still confirm them with `mutate.py`.

## Mutations for B to register

Add `src/combat/server/Services/CampBrain.luau` to `FILES` in `mutate.py`.

These are Python entries, ready to paste. `CROWD`, `BRAIN` and `CODEC` are mutate.py's own
constants; `CAMP` is new. `L1B_CROWD_MUTATIONS` is the 36 new entries. `STALE_REPLACEMENTS`
replaces existing entries under the same labels.

```python
CAMP = "src/combat/server/Services/CampBrain.luau"
CROWD = "src/combat/server/Services/CrowdService.luau"
BRAIN = "src/combat/server/Services/CrowdBrain.luau"
CODEC = "src/shared/CrowdCodec.luau"

# L1b Wave 1, luau-engineer A: new mutations (labels prefixed "l1b crowd:").
L1B_CROWD_MUTATIONS = {
    "l1b crowd: sight ignores the height band": (
        CAMP,
        "\tif not inBand(def, root, rules) then\n\t\treturn false\n\tend\n\tlocal posture = postureRules(def, rules)",
        "\tlocal posture = postureRules(def, rules)",
    ),
    "l1b crowd: the cone is ignored": (
        CAMP,
        "if posture.cone >= 360 or distance < CONE_NEAR then",
        "if true then",
    ),
    "l1b crowd: the cone uses the full angle": (
        CAMP,
        "return angle <= posture.cone / 2 + CONE_EPSILON_DEGREES",
        "return angle <= posture.cone + CONE_EPSILON_DEGREES",
    ),
    "l1b crowd: in play ignores chaseMargin": (
        CAMP,
        "local margin = rules.chaseMargin",
        "local margin = 0",
    ),
    "l1b crowd: in play ignores the shooters' reach": (
        CAMP,
        "if flatDistance(shooter.at, root) <= shooter.reach then",
        "if false then",
    ),
    "l1b crowd: rise skips its seconds": (
        CAMP,
        "if now - group.since >= postureRules(group.def, rules).rise - TIME_EPSILON then",
        "if true then",
    ),
    "l1b crowd: two transitions in one call": (
        CAMP,
        '\t\t\tchanged = "rise"\n\t\tend\n\telseif state == "rise" then',
        '\t\t\tchanged = "rise"\n\t\tend\n\tend\n\tif state == "rise" or changed == "rise" then',
    ),
    "l1b crowd: the leash fires while striking": (
        CAMP,
        "now - group.quietSince >= rules.leashSeconds - TIME_EPSILON and not input.striking",
        "now - group.quietSince >= rules.leashSeconds - TIME_EPSILON",
    ),
    "l1b crowd: the leash is not reset by a target back in play": (
        CAMP,
        "\t\tif anyInPlay then\n\t\t\tgroup.quietSince = now",
        "\t\tif anyInPlay then\n\t\t\tgroup.quietSince = group.quietSince",
    ),
    "l1b crowd: home takes damage": (
        CAMP,
        'return group.held or group.state == "home"',
        "return group.held",
    ),
    "l1b crowd: home wakes on a hit": (
        CAMP,
        '\telseif state == "home" then\n\t\tlocal home = true',
        '\telseif state == "home" then\n\t\tif group.hit then\n\t\t\tchanged = "rise"\n\t\tend\n\t\tlocal home = changed == nil',
    ),
    "l1b crowd: a hit from out of play lands": (
        CAMP,
        "return byUserId == 0 or group.inPlay[byUserId] == true",
        "return true",
    ),
    "l1b crowd: a held group wakes on sight": (
        CAMP,
        "\tif group.held then\n\t\t-- Held until the close: neither sight nor a hit wakes it (ruling L1b-13).\n\t\tgroup.hit = false",
        "\tif group.held and not anySeen(group, input, rules) then\n\t\tgroup.hit = false",
    ),
    "l1b crowd: Release frees a group that was not held": (
        CAMP,
        "\tif not group.held then\n\t\treturn\n\tend\n\tgroup.held = false",
        "\tgroup.held = false",
    ),
    "l1b crowd: patrol posts not spaced by arc length": (
        CAMP,
        "local s = total * (k - 1) / count",
        "local s = total * ((k - 1) % n) / n",
    ),
    "l1b crowd: a fire's sitters face away from it": (
        CAMP,
        "local yaw = theta + math.pi",
        "local yaw = theta",
    ),
    "l1b crowd: a patrol's leg does not wrap": (
        CAMP,
        "resident.leg = resident.leg % n + 1",
        "resident.leg = resident.leg + 1",
    ),
    "l1b crowd: home does not restore the post's leg": (
        CAMP,
        "\t\t\tresident.leg = post.leg",
        "\t\t\tresident.leg = resident.leg",
    ),
    "l1b crowd: a sitter shows idle": (
        CAMP,
        'return if group.def.posture == "fire" then "rest" else "idle"',
        'return "idle"',
    ),
    "l1b crowd: the heal leaves the plate broken": (
        CROWD,
        "\tenemy.hp = enemy.maxHp\n\tenemy.plate = enemy.plateMax\n",
        "\tenemy.hp = enemy.maxHp\n",
    ),
    "l1b crowd: the heal keeps the damage book": (
        CROWD,
        "\ttable.clear(enemy.damageBy)\n\tenemy.staggerUntil = 0",
        "\tenemy.staggerUntil = 0",
    ),
    "l1b crowd: a summon on floor 1": (
        CROWD,
        'local risen = enemies[CrowdService.Spawn(kind, spot, "fight", nil, nil, summoner.floor)]',
        'local risen = enemies[CrowdService.Spawn(kind, spot, "fight", nil, nil, 1)]',
    ),
    "l1b crowd: a strike's floorY from floor 1": (
        BRAIN,
        "floorY = floor.centre.Y,",
        "floorY = (floors[1] or DEFAULT_FLOOR).centre.Y,",
    ),
    "l1b crowd: the clamp on floor 1": (
        CROWD,
        "local floor = floorOf(enemy)\n\tlocal boundsCenter = floor.centre",
        "local floor = floors[1]\n\tlocal boundsCenter = floor.centre",
    ),
    "l1b crowd: AliveOn counts every floor": (
        CROWD,
        "return aliveOn[floor] or 0",
        "return aliveCount",
    ),
    "l1b crowd: ClearFloor clears every floor": (
        CROWD,
        "if enemy ~= nil and enemy.floor == floor then",
        "if enemy ~= nil then",
    ),
    "l1b crowd: Think ignores allowed": (
        BRAIN,
        "if allowed ~= nil and not allowed[target.userId] then",
        "if false then",
    ),
    "l1b crowd: SetFloors accepted with a body alive": (
        CROWD,
        "\tif aliveCount > 0 then\n\t\tif not warnedBoundsAlive then",
        "\tif false then\n\t\tif not warnedBoundsAlive then",
    ),
    "l1b crowd: the codec's new states swapped": (
        CODEC,
        '"attack", "recover", "rest", "rise" }',
        '"attack", "recover", "rise", "rest" }',
    ),
    "l1b crowd: an unknown floor index is not refused": (
        CROWD,
        "local stand = if isFinite(floorIndex) then floors[floorIndex] else nil",
        "local stand = if isFinite(floorIndex) then floors[floorIndex] or floors[1] else nil",
    ),
    "l1b crowd: AddGroup takes an unknown floor": (
        CROWD,
        'if typeof(def) ~= "table" or floors[def.floor] == nil then',
        'if typeof(def) ~= "table" then',
    ),
    "l1b crowd: a resting resident thinks": (
        CROWD,
        'local resting = brain ~= nil and (brain.held or brain.state ~= "fight")',
        "local resting = false",
    ),
    "l1b crowd: a released group fights in the step that releases it": (
        CROWD,
        "\t\t\tCampBrain.Step(brain, input, rules)\n\t\t\tCampBrain.Release(brain, simTime)",
        "\t\t\tCampBrain.Release(brain, simTime)\n\t\t\tCampBrain.Step(brain, input, rules)",
    ),
    "l1b crowd: a group with no living member is busy": (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and (state == "rise" or state == "fight") then',
        'if not group.brain.held and (state == "rise" or state == "fight") then',
    ),
    "l1b crowd: a group with no living member is awake": (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and state ~= "rest" then',
        'if not group.brain.held and state ~= "rest" then',
    ),
    "l1b crowd: Damage never asks the group": (
        CROWD,
        "if group ~= nil and not CampBrain.Struck(group.brain, byUserId) then",
        "if false then",
    ),
}

# Existing mutations in mutate.py whose text L1b's crowd edits changed: label -> the new entry.
STALE_REPLACEMENTS = {
    "a retreat ignores the arena's edge": (
        BRAIN,
        "return inArena(\n\t\t\tbody.position - mind.facing * (bandMin - distance),\n\t\t\tdef.radius,\n\t\t\tfloorOf(body)\n\t\t),\n\t\t\t0",
        "return body.position - mind.facing * (bandMin - distance),\n\t\t\t0",
    ),
    "shot: no lead": (
        BRAIN,
        "aim = here + (ahead(here, target, flight + target.lag, floorY) - here) * lead",
        "aim = here + (ahead(here, target, flight + target.lag, floorY) - here) * 0",
    ),
    "shot: aimed along the locked facing, not at T": (
        BRAIN,
        "strike.aim = if target ~= nil\n\t\t\t\t\tthen ledAim(origin, here, target, attack, floor.centre.Y)\n\t\t\t\t\telse here",
        "strike.aim = origin + mind.facing",
    ),
    "lane: the charge ignores the arena's edge": (
        BRAIN,
        "then math.min(range, runway(body.position, mind.facing, def.radius, floor))",
        "then range",
    ),
    "1a: the wave 2 rule (in the air = above the standing height, down to the crowd's floor)": (
        BRAIN,
        "\tif not target.resting then\n\t\tlocal floor = if y >= target.restY then target.restY else floorY + target.lift",
        "\tif y - (floorY + target.lift) > 0.75 then\n\t\tlocal floor = floorY + target.lift",
    ),
    "1a: a jump off a block is led down to the crowd's floor": (
        BRAIN,
        "local floor = if y >= target.restY then target.restY else floorY + target.lift",
        "local floor = floorY + target.lift",
    ),
    "1a: a fall off a block stops at the block's height": (
        BRAIN,
        "local floor = if y >= target.restY then target.restY else floorY + target.lift",
        "local floor = target.restY",
    ),
    "lag: a shot is led over its flight alone": (
        BRAIN,
        "ahead(here, target, flight + target.lag, floorY)",
        "ahead(here, target, flight, floorY)",
    ),
    "summon: they stand idle": (
        CROWD,
        'local risen = enemies[CrowdService.Spawn(kind, spot, "fight", nil, nil, summoner.floor)]',
        'local risen = enemies[CrowdService.Spawn(kind, spot, "idle", nil, nil, summoner.floor)]',
    ),
    "boss: its queued impact is still handed over": (
        CROWD,
        "\t\tend\n\tend\n\tCrowdBrain.Recall(ids)\n",
        "\t\tend\n\tend\n",
    ),
    "guarded: a guard in its dead state still guards": (
        CROWD,
        'enemy.state = "dead"\n\tnoteGone(enemy)\n\tlocal summoner = enemy.summoner\n\tif summoner ~= nil then\n\t\tsummoner.guard = math.max(summoner.guard - 1, 0)',
        'enemy.state = "dead"\n\tnoteGone(enemy)\n\tlocal summoner = enemy.summoner\n\tif summoner ~= nil then\n\t\tsummoner.guard = math.max(summoner.guard, 0)',
    ),
}
```

### The stale list

These are existing `mutate.py` entries whose text my edits changed. Each needs its entry replaced
by the one in `STALE_REPLACEMENTS` above, under the same label. B can update the constants instead
for these:
- **`FLOOR`** becomes `"local floor = if y >= target.restY then target.restY else floorY + target.lift"`.
  It feeds two labels: "1a: a jump off a block is led down to the crowd's floor" and "1a: a fall
  off a block stops at the block's height".
- **"1a: the wave 2 rule (in the air = above the standing height, down to the crowd's floor)"**:
  the old text becomes `"\tif not target.resting then\n\t\t" + FLOOR` with the new FLOOR. The new
  text is `"\tif y - (floorY + target.lift) > 0.75 then\n\t\tlocal floor = floorY + target.lift"`.
- **`DIED`** becomes `'enemy.state = "dead"\n\tnoteGone(enemy)\n\tlocal summoner = enemy.summoner\n\tif summoner ~= nil then\n\t\tsummoner.guard = math.max(summoner.guard - 1, 0)'`.
  It feeds "guarded: a guard in its dead state still guards".

The full stale list, in my files:

| File | Labels |
|---|---|
| CrowdBrain | "a retreat ignores the arena's edge", "shot: no lead", "shot: aimed along the locked facing, not at T", "lane: the charge ignores the arena's edge", the three "1a: ..." entries, "lag: a shot is led over its flight alone" |
| CrowdService | "summon: they stand idle", "boss: its queued impact is still handed over" (`\tCrowdBrain.Recall(ids)\n` now occurs twice: `ClearFloor` recalls too), "guarded: a guard in its dead state still guards" |

The StageFlow, Combat and LevelGeometry entries that were stale on 2026-10-14 are B's own.

## For the other owner

- **B (`mutate.py`):** add `CampBrain.luau` to `FILES`, add the 36 entries above, and replace the
  11 stale ones.
- **B (`WaveService`):**
  - `CrowdService.SetCampRules(rules)` refuses rules that `CampBrain.Problems` finds a problem
    with: it warns and stores nil. Still check `Problems` first and answer `unavailable`, as the
    contract says.
  - `GroupEvent.ids` is a new table for each event, so it is safe to put straight into the
    `alert` CombatFx.
  - `CrowdService.Clear()` forgets every group and its pending events.
- **economy-designer (`sim_range.py` and the `stage_mirror` comparisons):** the executor details
  the mirror must copy are items 2, 3 and 4 below, plus one more: the heal is applied before
  `Step` in each camp step.
- **ui-engineer:**
  - Every `CrowdSpawn` info now carries `floor` (1 in the range).
  - States 8 and 9 (`rest`, `rise`) can appear on the wire.
  - A resting resident's `attack` byte is always 0.

## Contract points I found wrong or open

1. **`Busy` and `Engaged` with a dead group.** `Step` never changes an empty group, so a group
   whose members all die while it fights would stay in `fight` forever. Read literally, its floor
   would be `Busy` and its last in-play players `Engaged` for the rest of the run: no i-frames,
   and that camp's checkpoint never a safe point. I count only groups with a living member for
   `Busy` and `Engaged`, as the contract already says for `Awake`. Suggested wording: add "with a
   living member" to both.
2. **The executor's stop distance.** A body that seeks its goal with a stop distance of exactly
   `homeTolerance` ends a rounding error either side of it. Then `AtPost` can fail for good, and
   a patrol can stall at a loop point. The executor stops at `homeTolerance × 0.5`
   (`HOME_STOP_SHARE`, engine plumbing). `CampBrain.AtPost` and `Goal` are exactly as written.
   The sim mirror must use the same stop.
3. **The release step.** Calling `Release` and then `Step` in one step would turn a guard's rise
   of 0 straight into `fight` (`now - since = 0`), so "a rise of 0 still lasts one crowd step"
   would fail. On a release step the camp step instead:
   - steps the held group first, which changes nothing but its in-play set, so `Engaged` is
     current;
   - then releases it;
   - and makes no `Step` transition that step.
4. **The clock.** The camp step passes CampBrain the crowd's `simTime` (the sum of step
   intervals, so deterministic), not `os.clock()`. `NewGroup` and `Release` use the same clock.
   The contract does not name one.
5. **The heal's `damageBy = {}`** is done as `table.clear(enemy.damageBy)`. The meaning is the
   same, and it does not allocate on every step a member waits at its post.
6. **`SetCampRules` validates** with `Problems` (one warn; bad rules become nil). This goes
   beyond the contract, as a defence against a Heartbeat that throws.
7. **Residents and `KillAll`.** `KillAll` bypasses `Damage`, so it also kills held and homeward
   residents. That is right for a Studio lever, but it is not stated anywhere.
