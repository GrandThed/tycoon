# L1b Wave 2 — build report, luau-engineer A (the crowd and the hit shapes)

## Landed (in order)

1. **`src/shared/Types.luau` — the Types block, verbatim** (2026-10-14). `CrowdSpawnInfo` (+ `at`,
   `yaw`, `state`), `CampPosture` (+ `"tent"`), `CampRulesConfig` (+ `tent`, `joinFactor`,
   `dormantRadius`), `LevelCamp.tent: LevelTentBlock?`, `LevelLayout.sneak: { ArenaPoint }?`,
   `LevelTentBlock`, `LevelTentConfig`, `LevelCampConfig` (+ `tent`), `LevelClearBonus`,
   `LevelCrowdConfig.clearBonus: LevelClearBonus?`, `CombatLevelsConfig` loses `populationReserve`,
   `CombatDebugConfig` gains `perfAttribute: string`. Others may build against it now.
2. **`src/shared/HitShapes.luau`** — `RayUpright`, `CrowdRay`, `FlatToRect` with bodies, signatures
   as the contract. `RayUpright` with `high - low <= 0` returns `HitShapes.Ray` itself (exact
   equality for the sphere case). No closure or table per call.
3. **`src/shared/SwingGate.luau`** (new) — `State`, `AIR_MARGIN_STUDS` 0.75, `New`, `IsAir`,
   `Allows`, `Took`, `Landed`. B: add `"SwingGate": "src/shared/SwingGate.luau"` to `SOURCES`
   before `CampBrain` (my test file loads it).
4. **`src/combat/server/Services/CampBrain.luau`** — `TentState`, posture `tent` (Posts: fire's
   circle facing outward; Shows: standing `idle`/`move`), `Problems` (tent rules, `joinFactor` > 0,
   `dormantRadius` > every sight), `InPlay` through `HitShapes.FlatToRect`, and the new `Dormant`,
   `Gap`, `JoinIn`, `Rouse`, `NewTent`, `TentActive`, `TentDue`, `TentSent`. CampBrain now requires
   `HitShapes` (already in the harness `SOURCES`).
5. **Executors** — `CrowdService` (camp step in Flow order, dormancy, `refreshInfo`, `RouseGroup`,
   `GroupAlive`, `GroupedOn`, `SetPerfLog(seconds, attribute?)`), `WeaponService` (`CrowdRay` in
   `rayCandidates`, `SwingGate` air-swing gate in `OnAttack`, `resolveMelee` takes the resolved
   origin, `CONST.AIRBORNE_MARGIN_STUDS = SwingGate.AIR_MARGIN_STUDS`), `Main.server.luau` passes
   `debug.perfAttribute`. Written; harness cases follow.
6. **`tools/crowd_harness/tests_l1b_w2_crowd.luau`** (new, B registered it) — every case the
   contract lists: CrowdRay (a)–(i) for all ten real kinds with Longbow A, RayUpright (200 seeded
   rays against Ray, inside, both axis directions, short of reach, side, both caps, slant),
   FlatToRect, Query's bounding sphere (geometry and the real Query on the real kinds), SwingGate,
   CampBrain (tent Posts/Shows/Problems, Dormant, Gap, JoinIn, Rouse, the tent timeline) and
   CrowdService (dormancy, a lever hit on a dormant body, spawn infos and a late joiner, the
   join-in with one GroupEvent each, RouseGroup, GroupAlive/GroupedOn, the Perf attribute).
7. **`tools/crowd_harness/tests_l1b_crowd.luau`** — only `L1BC.rules()`: it gains `tent`,
   `joinFactor` 2 and `dormantRadius` 1000 (Problems now refuses rules without them; 1000 keeps
   every Wave 1 case, which reads bodies 170+ studs from the player on the wire, free of dormancy).

## State: DONE

Gates on A's files (2026-10-14): stylua --check and selene clean; `luau-lsp analyze` clean on
`src/combat` (combat sourcemap) and on `src/shared src/server src/client` (hub sourcemap);
`py tools/check_compile.py` PASS (155 files); `run_harness.py` **PASS (1,897 checks)** with B's
registration. A's 35 mutations plus the 3 replaced ones run against the bundle by a scratch
runner: every one caught but "the [Perf] attribute set with no name", which stops the bundle in
`tests_p5`'s Perf case (the stub Workspace has no SetAttribute there); `run_harness.py` reports a
stopped bundle as a failing check, so `mutate.py` counts it caught. B may drop it if it prefers a
clean catch. The full `mutate.py` is B's to run once these are in.

## Old cases that pinned the old ray rule

None. `rayCandidates` lives in `WeaponService`, which the harness does not load, and no case in
`tests.luau`, `tests_w2`, `tests_s2`, `tests_s3`, `tests_p5` or `tests_l1b_crowd` tests the ray
against the crowd's body or head. Those files are untouched except `L1BC.rules()` above.

## Decisions the contract did not take

1. **Every body's spawn info is refreshed** (`at`, `yaw`, `state`), the range's too: the A section
   and the Remotes table say "each info ... at every send". The client section's "a spawn info
   without `at` (the range's bodies)" is therefore no longer reached from this server; seeding a
   range body from `at` only draws it one snapshot earlier.
2. **A resident's state at spawn is its group's rest show** (`CampBrain.Shows(brain, false)`: a
   fire seated `rest`, a tent or guard `idle`), so a body that goes dormant before it is ever
   integrated (every far camp at Depart) is announced seated or standing correctly.
3. **On going dormant a body's state becomes its rest show** (a frozen patroller shows `idle`, not
   `move`), for the spawn info a late joiner draws it from. Its last snapshot, sent while it was
   still awake, carried `move`; the client holds that pose (120+ studs away).
4. With **camp rules nil** the camp step clears every body's dormancy (nothing stays frozen).
5. **Gaps** come from `CampBrain.Posts(def, Σ def.units[k].count)`; a def with no units has no
   posts, so its gap to anything is `math.huge` (never joins).
6. **Air swing with no Humanoid:** the standing offset falls back to half the root's height.
7. The **combo reset** now sits inside the melee branch (`variant.kind == "melee"`) instead of
   "not ranged": the only two kinds that ship are `melee` and `ranged`, so nothing changes.
8. The air-swing gate runs **after** the ranged checks and the rate credit and **before** anything
   is spent (no seq, credit or combo step taken on a refusal), as the contract orders.
9. The **late-joiner case** builds a second CrowdService from the same bundled source with its own
   Players/RunService stubs (the shared stub drops `PlayerAdded` handlers); it shares CrowdBrain's
   floors, which `L1BC.leave`'s `SetBounds` puts back.

## For the other owner

**For B (`mutate.py`):**
- Add `SWING = "src/shared/SwingGate.luau"` and put it in `FILES`.
- Add `L1B_W2_CROWD_MUTATIONS` below (`MUTATIONS.update(...)`).
- Replace the three stale Wave 1 mutations with the texts in `L1B_W2_CROWD_REPLACED` (same labels).
- Retire `"l1b crowd: in play has square corners"`: the rectangle distance moved into
  `HitShapes.FlatToRect`; `"l1b w2 crowd: FlatToRect with square corners"` replaces it (and is
  caught by the Wave 1 rounded-corner cases too).
- Every other existing mutation on CrowdService, CampBrain and HitShapes still matches exactly once
  (checked against `mutate.py` as it stood at 2026-10-14; B's own StageFlow ones were stale then
  too, B's to fix).

```python
SWING = "src/shared/SwingGate.luau"
CROWD = "src/combat/server/Services/CrowdService.luau"
CAMP = "src/combat/server/Services/CampBrain.luau"
HITSHAPES = "src/shared/HitShapes.luau"

L1B_W2_CROWD_MUTATIONS = {
    # HitShapes.CrowdRay / RayUpright / FlatToRect
    "l1b w2 crowd: CrowdRay without the head term": (
        HITSHAPES,
        "local entry = earlier(bodyEntry, headEntry)",
        "local entry = bodyEntry",
    ),
    "l1b w2 crowd: CrowdRay's crit test padded": (
        HITSHAPES,
        "return entry, HitShapes.Ray(origin, direction, reach, width, 0, head, headRadius) ~= nil",
        "return entry, HitShapes.Ray(origin, direction, reach, width, pad, head, headRadius) ~= nil",
    ),
    "l1b w2 crowd: CrowdRay's head at half height": (
        HITSHAPES,
        "local head = feet + Vector3.new(0, height - headRadius, 0)\n\tlocal bodyEntry",
        "local head = feet + Vector3.new(0, height / 2, 0)\n\tlocal bodyEntry",
    ),
    "l1b w2 crowd: CrowdRay's body back to a sphere": (
        HITSHAPES,
        "\t\tfeet,\n\t\tradius,\n\t\ttop - radius,\n\t\tradius\n\t)",
        "\t\tfeet,\n\t\theight / 2,\n\t\theight / 2,\n\t\tradius\n\t)",
    ),
    "l1b w2 crowd: CrowdRay's entry always the head's": (
        HITSHAPES,
        "local entry = earlier(bodyEntry, headEntry)",
        "local entry = if headEntry ~= nil then headEntry else bodyEntry",
    ),
    "l1b w2 crowd: CrowdRay's top without the max": (
        HITSHAPES,
        "local top = math.max(height - 2 * headRadius, height / 2 + radius)",
        "local top = height - 2 * headRadius",
    ),
    "l1b w2 crowd: RayUpright drops a cap": (
        HITSHAPES,
        "local best = earlier(firstIn(lowEnter, lowExit, reach), firstIn(highEnter, highExit, reach))",
        "local best = firstIn(lowEnter, lowExit, reach)",
    ),
    "l1b w2 crowd: FlatToRect with square corners": (
        HITSHAPES,
        "local dz = math.max(math.abs(z - cz) - hz, 0)\n\treturn math.sqrt(dx * dx + dz * dz)",
        "local dz = math.max(math.abs(z - cz) - hz, 0)\n\treturn math.max(dx, dz)",
    ),
    # SwingGate
    "l1b w2 crowd: SwingGate.Took ignores airborne": (SWING, "state.used = airborne", "state.used = true"),
    "l1b w2 crowd: SwingGate.Landed does nothing": (
        SWING,
        "function SwingGate.Landed(state: State)\n\tstate.used = false",
        "function SwingGate.Landed(state: State)\n\tlocal _ = state",
    ),
    "l1b w2 crowd: SwingGate.Allows ignores used": (SWING, "return not (airborne and state.used)", "return true"),
    "l1b w2 crowd: SwingGate.IsAir with >=": (
        SWING,
        "return height > standOffset + SwingGate.AIR_MARGIN_STUDS",
        "return height >= standOffset + SwingGate.AIR_MARGIN_STUDS",
    ),
    # CampBrain
    "l1b w2 crowd: a tent's ring faces inward": (
        CAMP,
        'local turn = if posture == "fire" then math.pi else 0',
        "local turn = math.pi",
    ),
    "l1b w2 crowd: a tent sits at rest": (
        CAMP,
        'return if group.def.posture == "fire" then "rest" else "idle"',
        'return if group.def.posture == "fire" or group.def.posture == "tent" then "rest" else "idle"',
    ),
    "l1b w2 crowd: Problems skips the tent posture": (
        CAMP,
        'local POSTURES: { Types.CampPosture } = { "guard", "patrol", "fire", "tent" }',
        'local POSTURES: { Types.CampPosture } = { "guard", "patrol", "fire" }',
    ),
    "l1b w2 crowd: Problems lets dormantRadius equal a sight": (
        CAMP,
        "if isFinite(sight) and dormantRadius <= sight then",
        "if isFinite(sight) and dormantRadius < sight then",
    ),
    "l1b w2 crowd: Dormant while in home": (
        CAMP,
        'function CampBrain.Dormant(group: Group, roots: { Vector3 }, rules: Types.CampRulesConfig): boolean\n\tif group.state ~= "rest" then',
        'function CampBrain.Dormant(group: Group, roots: { Vector3 }, rules: Types.CampRulesConfig): boolean\n\tif group.state ~= "rest" and group.state ~= "home" then',
    ),
    "l1b w2 crowd: Dormant ignores dormantRadius": (
        CAMP,
        "local radius = rules.dormantRadius",
        "local radius = 0",
    ),
    "l1b w2 crowd: JoinIn does not chain": (
        CAMP,
        "\t\t\t\ttable.insert(answer, other)\n\t\t\t\ttable.insert(queue, other)",
        "\t\t\t\ttable.insert(answer, other)",
    ),
    "l1b w2 crowd: JoinIn uses the first waker's sight for the whole chain": (
        CAMP,
        "local reach = rules.joinFactor * postureRules(group.def, rules).sight",
        "local reach = rules.joinFactor * postureRules(groups[woke[1]].def, rules).sight",
    ),
    "l1b w2 crowd: JoinIn joins a held group": (
        CAMP,
        '\t\t\t\tcandidate.state == "rest"\n\t\t\t\tand not candidate.held\n',
        '\t\t\t\tcandidate.state == "rest"\n',
    ),
    "l1b w2 crowd: gaps written across camps": (
        CROWD,
        "if earlier.brain.def.camp == def.camp then",
        "if true then",
    ),
    "l1b w2 crowd: Rouse wakes a held group": (
        CAMP,
        'if group.held or group.state ~= "rest" then\n\t\treturn false\n\tend\n\tgroup.state = "rise"',
        'if group.state ~= "rest" then\n\t\treturn false\n\tend\n\tgroup.state = "rise"',
    ),
    "l1b w2 crowd: TentActive ignores the dead residents": (
        CAMP,
        "return busy or residentsAlive <= 0",
        "return busy",
    ),
    "l1b w2 crowd: TentDue ignores active": (
        CAMP,
        "return active and tent.left > 0 and now >= tent.nextAt - TIME_EPSILON",
        "return tent.left > 0 and now >= tent.nextAt - TIME_EPSILON",
    ),
    "l1b w2 crowd: TentSent does not move nextAt": (
        CAMP,
        "tent.nextAt = now + every",
        "tent.nextAt = tent.nextAt",
    ),
    # CrowdService
    "l1b w2 crowd: a dormant body is integrated": (
        CROWD,
        "\t\tif enemy.dormant then\n\t\t\t-- L1b-W2-10: not integrated",
        "\t\tif false then\n\t\t\t-- L1b-W2-10: not integrated",
    ),
    "l1b w2 crowd: a dormant body is sent": (
        CROWD,
        "\t\tif enemy.dormant then\n\t\t\t-- L1b-W2-10: far from every player",
        "\t\tif false then\n\t\t\t-- L1b-W2-10: far from every player",
    ),
    "l1b w2 crowd: the flush skips the info refresh": (
        CROWD,
        "pendingSpawnSet[id] = nil\n\t\t\t\ttable.insert(batch, refreshInfo(enemy))",
        "pendingSpawnSet[id] = nil\n\t\t\t\ttable.insert(batch, enemy.spawnInfo)",
    ),
    "l1b w2 crowd: a late joiner's batch skips the info refresh": (
        CROWD,
        "if not pendingSpawnSet[enemy.id] then\n\t\t\ttable.insert(batch, refreshInfo(enemy))",
        "if not pendingSpawnSet[enemy.id] then\n\t\t\ttable.insert(batch, enemy.spawnInfo)",
    ),
    "l1b w2 crowd: the join-in never runs": (CROWD, "\tif #woke > 0 then\n", "\tif false then\n"),
    "l1b w2 crowd: a rouse is never executed": (
        CROWD,
        "if rouse[index] and CampBrain.Rouse(brain, simTime) then",
        "if false then",
    ),
    "l1b w2 crowd: GroupedOn not taken down at a death": (
        CROWD,
        "grouped[enemy.floor] = math.max((grouped[enemy.floor] or 0) - 1, 0)",
        "grouped[enemy.floor] = grouped[enemy.floor] or 0",
    ),
    "l1b w2 crowd: the [Perf] attribute never set": (
        CROWD,
        "Workspace:SetAttribute(attribute, p95)",
        "Workspace:SetAttribute(attribute, nil)",
    ),
    "l1b w2 crowd: the [Perf] attribute set with no name": (
        CROWD,
        'perf.attribute = if typeof(attribute) == "string" and attribute ~= "" then attribute else nil',
        'perf.attribute = if typeof(attribute) == "string" and attribute ~= "" then attribute else "CrowdPerfMs"',
    ),
}

# Stale Wave 1 mutations whose text A's edits changed: label -> (file, new old-text, new new-text).
L1B_W2_CROWD_REPLACED = {
    "l1b crowd: in play ignores chaseMargin": (
        CAMP,
        "HitShapes.FlatToRect(root.X, root.Z, rect.x, rect.z, rect.hx, rect.hz) <= rules.chaseMargin",
        "HitShapes.FlatToRect(root.X, root.Z, rect.x, rect.z, rect.hx, rect.hz) <= 0",
    ),
    "l1b crowd: a fire's sitters face away from it": (
        CAMP,
        'local turn = if posture == "fire" then math.pi else 0',
        "local turn = 0",
    ),
    "l1b crowd: a group walking home engages": (
        CROWD,
        'if #group.bodies > 0 and (brain.state == "rise" or brain.state == "fight") then',
        'if #group.bodies > 0 and brain.state ~= "rest" then',
    ),
}
# "l1b crowd: in play has square corners" is retired: the rectangle distance moved into
# HitShapes.FlatToRect, whose own mutation "l1b w2 crowd: FlatToRect with square corners" replaces it.
```

**For the economy-designer (mirrors):**
- `CampBrain.Problems` now also writes a line for a missing/broken `camps.tent` (as the other
  postures), for `joinFactor` missing, not finite, negative or 0, for `dormantRadius` missing or not
  finite, and one line per posture whose `sight` is >= `dormantRadius`. `stage_mirror.luau`'s
  `Brain.Problems` count comparison must expect those.
- `HitShapes.RayUpright` with `high - low <= 0` returns `HitShapes.Ray` itself; otherwise the
  entry is the earliest of the two end spheres' and the finite cylinder's first contact, clamped to
  0, nil past `reach`. `CrowdRay` = `RayUpright(feet, radius, top - radius, radius)` and the padded
  head `Ray`, entry the smaller; crit = the head `Ray` with pad 0.
- Tent posts: the fire's circle (`centre - (sin θ, cos θ) × radius`), yaw = θ wrapped into
  (−π, π] (fire: θ + π).

**For the ui-engineer (lead relay, checked):** a spawn info's `at` is the body's feet in world
coordinates (`enemy.position`, the same frame as the snapshot decode against `WIRE_ORIGIN` 0),
`yaw` in radians (the snapshot's convention), `state` a `CrowdState`; a tent group at rest arrives
`idle`; the attribute is the `[Perf]` line's p95 in milliseconds (a number). All match. One
difference from the client section: range bodies carry `at` too (decision 1).
