# L4 W2 contract — the forest and the raiders in the game

Brief: `docs/prompts/l4-w2-brief.md`. Drafted 2026-10-21. Rulings are **L4W2-n**. Game code was read in `tycoon-p5b`
(branch `l4-w1b`, W1b uncommitted: **W2 starts from it once it merges**); tools, data and reports in `tycoon-p5`
(`l4-real-forest` 03f063f plus the raider builder's and pipeline engineer's work in progress, marked *(p5)*). Line numbers
move with W1b: owners re-find by text. Ben's rulings: MISSIONS_DESIGN §26, §27. Inputs still being written, which this
contract defers to by name: `docs/prompts/l4-w2-reports/raiders.md` (the four new looks, the whirl rule, the plate role,
posed reach) and `docs/prompts/l4-w2-reports/pipeline.md` + `l4-w2-asset-run.md` (the route and the runbook).

## 0. Lead's amendments (2026-10-21, after reading the draft)

- **L4W2-1, -4 and -5 land in track P, before W2 starts:** the pipeline engineer holds `tools/levels/forest.py` this
  wave, so it narrows the plan hash, moves the data file to `src/shared/Config/LevelDress/ForestRoad.json` and renames the
  `hide.camps` roles, then re-runs `build` and `check`. D2 takes `forest.py` over when W2 starts.
- **The boss rename no longer has to precede the bake** (§10 step 1): with the narrowed hash a rename or a Valor change
  does not move it. D1 renames in Wave A like any other change.
- The starting numbers the draft proposed (mood B's `outdoorAmbient` [110, 120, 130], the low-end walk radius 60, 8
  clones a frame) are accepted as starting values; Ben's Studio look tunes the mood.

## 1. Rulings (detail in the section named)

- **L4W2-1.** One dress file per level, generated into Config: `forest.py build` writes
  `src/shared/Config/LevelDress/ForestRoad.json` (the Valley precedent: `valley.py` writes `Config/Valley.json`, read by
  `Catalog.GetValleyPlan`, `Catalog.luau:429`); `tools/levels/out/ForestRoad.dress.json` (forest.py:6, :63 *(p5)*) goes.
- **L4W2-2.** The server decides "dressed", all or nothing, before it hides anything; grey = today's level exactly, one
  warning (§2.2). **L4W2-3.** The client dresses only on the server's word, and undoes it if a mesh fails to clone (§2.3).
- **L4W2-4.** `forest.py plan_hash` (:1984-1994 *(p5)*) hashes the whole `stages` list, so a boss rename or a Valor change
  would cost a re-bake and a paste: it hashes per stage only `kind`, `zone`, `boss.at` from now, **before** the bake (§10).
- **L4W2-5.** `hide.camps` names LevelGeometry's roles (`floor`, `fence`, `obstacle`, `fire`, `tent`;
  `LevelGeometry.luau:937-1029`), not `cover`, `fireMarkers`, `tentMarker` (`hide_list` :1967-1981 *(p5)*). No hash change.
- **L4W2-6.** The dress `looks` overlay `Expeditions.json looks` for the level's Parts only while dressed; the lobby keeps
  today's. **L4W2-7.** Mood B is per client and per level, never set by the server (§2.4); nothing sets Lighting today
  (`grep Lighting src/combat`: no match).
- **L4W2-8.** A kind without a whole model is today's placeholder (one warn); the guard, Warlord, Colossus and the range's
  `boss` stay placeholders. **L4W2-9.** The pose maths, today's `threatPose` maths included, go into one pure module
  mirrored against `raiderpose.py` (§3.3; raiders.md risk 6 *(p5)*); CrowdRenderer is at 154 of 180 top-level locals
  (`grep -c "^local "`; `check_compile.py:41-42`). **L4W2-10.** The client clears `TextureID` on every painted MeshPart
  once per clone, whatever the template holds.
- **L4W2-11.** Seats are stepped on the server as on the client and hit shapes sit with them (§5). **L4W2-12.** The Camp
  Chief is the kind `chief`; the Colossus stays for the range (§4). **L4W2-13.** R8 compares whole runs over 30 seeds
  (§6). **L4W2-14.** The 62 walls only remove moves: "cannot" gates hold without them, "can" gates are re-proved with
  them, every wall top is unclimbable (§7). **L4W2-15.** Phones gate on `Theme.lowEndDevice` (`Theme.luau:1543`) only,
  never `reducedMotion` (:1541, true on every touch device); tells, cues, the plate and the walls are never thinned.

## 2. The forest

### 2.1 The dress file as the game reads it (Types and Catalog: A)

```luau
export type LevelDress = { version: number, level: string, layout: string, planHash: string, frame: string,
	meshes: { LevelDressMesh }, props: { LevelDressProp }, effects: { LevelDressEffect },
	barriers: { LevelDressBarrier }, hide: { blocks: { string }, camps: { [string]: { string } } },
	looks: { [string]: LevelLook } }
export type LevelDressMesh = { name: string, group: string }                        -- the template's name
export type LevelDressProp = { piece: string, x: number, y: number, z: number, yaw: number, scale: number, with: string? }
export type LevelDressEffect = { kind: string, x: number, y: number, z: number }   -- kind "fire"
export type LevelDressBarrier = { name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number }
```

The game ignores the file's other fields (`units`, `triangles`, `palette*`, `textures`, `bakedPieces`, `propPieces`,
prop tags but `with`, `hide.keep`); `frame` must be "level" (world studs, forest.md:96-97 *(p5)*).
`Catalog.GetLevelDress(layout)` is nil when the module is absent. The uploaded record is `Assets.json
levels.<layout>.planHash` (the pipeline's v6 block, `assets_config.ensure_level` *(p5)*), typed
`AssetsConfig.levels: { [string]: { planHash: string } }?`.

### 2.2 Server (A): new pure `src/combat/server/Services/LevelDress.luau`, and LevelService

`LevelDress.Accept(dress, uploadedHash, haveMeshes, pieces, open, groupsOk, maxParts) -> (Accepted?, string?)`, with
`haveMeshes` the Models found under `ReplicatedStorage.Assets.Levels.<layout>` and `pieces` LevelGeometry.Pieces'
answer. It refuses, naming why, when there is no dress or its `layout` or `frame` differ; `planHash ~= uploadedHash`
(the Valley's rule, `Landscape.luau:736-744`); a mesh has no template; a `hide.blocks` name matches no `block` piece and
was not left out by `open` (L2-36), or a `hide.camps` entry names a camp or role no piece has; `groupsOk` is false
(without the group a wall stops rays and the camera, `LevelService.luau:348-359`); a barrier box is unsound; or
`#pieces + #barriers > maxParts` (252 + 62 = 314 of 600, forest.md:68-69 *(p5)*). On success: `{ walls, hidden, looks }`,
each wall a Piece of role `treeline`, no camp, collide true.

**LevelService.Build** (`:599-631`) calls Accept after `piecesOf`; on nil it warns once (`[LevelService] the level is
grey: <reason>`) and builds as today. On accept `construct` also: builds each `treeline` Part in
`BarrierGroups.BARRIER` (`BarrierGroups.luau:21, 31`), Transparency 1, CanTouch and CastShadow false, **collidable from
the build** (camp C's `barrier` starts off, `:394-404`); gives every hidden piece Transparency 1, CastShadow false and
attribute `Skinned`, collision and query unchanged; lays the overlay looks into `state.looks` so SetCamp's checkpoint and
gate looks follow them (`:805-840`); and last sets `Workspace.Level` attributes `Dress` (layout name) and `DressHash`
(planHash). Clear (`:633-643`) sets both to nil first. The lever `dressFail` (§8) makes Build pass a wrong hash once.

### 2.3 Client (ui A): new controller `LevelScenery.luau`, listed in `Main.client.luau`

The M9 pattern: client-side, walk-through, no remote. When `Dress` is set (also at Start, for a late join) and
`Catalog.GetLevelDress(Dress).planHash == DressHash`, it builds into `Workspace.LevelScenery`,
`Theme.COMBAT_SCENERY_CLONES_PER_FRAME` (8) clones a frame: first the groups that cover hidden collision (`ground`, `skin`,
`camp`, `rock`), then `canopy`, `dress`, `backdrop`, the props, the fires. A generation counter stops a build the level
outlived.
- **Meshes:** parent a clone of `ReplicatedStorage.Assets.Levels.<layout>.<name>` with no move ("the client only parents
  a clone", pipeline `level_template_xml` *(p5)*), every BasePart Anchored and CanCollide, CanQuery, CanTouch false
  (`Landscape.luau:482-495`). A missing or failing clone (pcall): warn once, destroy the folder and set every `Skinned`
  Part's Transparency to 0 locally, so no collision is left invisible.
- **Props:** clone `ReplicatedStorage.Assets.Props.Forest.<piece>` (pivot = its Base, the bottom centre),
  `PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0))`, then `ScaleTo(scale)` when not 1
  (`PropFactory.luau:284-288`). A missing piece is left out with one warn, never a refusal. A prop with `with` stands
  only while `Workspace.Level` has a child of that name and leaves on its `ChildRemoved` (the bramble burns; a found
  shortcut never builds it, `LevelGeometry.luau:860-866`).
- **Fires:** per `effects[]` entry an invisible anchored Part with a ParticleEmitter and a PointLight
  (`Theme.COMBAT_SCENERY_FIRE_*`); neither on `lowEndDevice` (the Campfire prop's flames stay).
- **Clear:** on `Dress` nil, destroy the folder and restore the mood.

### 2.4 Mood B (ui A applies it; D1 owns the numbers)

`Expeditions.json moods.<levelId> = { lighting: WorldLightingConfig?, atmosphere: WorldAtmosphereConfig? }`, reusing
`Types.luau:1953-1967` (A adds `ExpeditionsConfig.moods`). Start values (forest.md:218-220 *(p5)*, tuned from Ben's
screenshots): lighting `brightness` 1.6, `outdoorAmbient` [110, 120, 130]; atmosphere `density` 0.38, `offset` 0,
`color` [110, 124, 120], `decay` [92, 106, 100], `glare` 0, `haze` 1.6. Applied while dressed; the client records each
Lighting property it writes, and whether it made the Atmosphere, and restores exactly that.

### 2.5 Project files (lead)

`combat.project.json`: `ReplicatedStorage.Assets.Levels` = `{ "$className": "Folder", "$path": { "optional":
"templates/_levels" } }`, `templates/_levels` in `globIgnorePaths` (as `_props`, :3, :14-19), and `ServerStorage.Enemies`
(:43-46) gone if W1b row 19 left it; `proving_project.py` carries both. The hub gets nothing. Exact lines: pipeline report.

## 3. The raiders' models

### 3.1 Config (D2) and Types (A)

`src/shared/Config/RaiderModels.json` is written by a new `tools/assets/raider_frames.py` on `weapon_frames.py`'s route
(:1-40): it copies `tools/assets/out/RaiderModels.json`, `--check`s it against the merge sidecars plus the turn proof,
and has `--require-harvest` for after the paste. Keys are crowd kind names (`fodder`, `slinger`, `marksman`, `lobber`,
`brute`, `armoured`, `chief`). `Types.RaiderModelsConfig` types raiders.md §4 *(p5)* plus the step-2 report: `folder`,
`rig`, and per kind `model`, `height`, `radius`, `headRadius`, `skin`, `pieces[k] = { name, stage, pivot, parts =
{ [meshPartName]: role } }`, `points`, `legLength`, `leadLeg`, `armSwingShare`, `arm`, `hold?`, the core size, the posed
reach. Roles: `gear` (never painted), `cloth`, `skin`, `glow`, `plate`. Reader `Catalog.GetRaiderModelsConfig()` (as
`Catalog.luau:173`). An entry counts only when its `height`, `radius`, `headRadius` equal ProvingGrounds.json's.

### 3.2 Pools, figure, gear (ui B): new `Controllers/Raiders/Figures.luau`

- **Template** `ReplicatedStorage.Assets.Props.Raiders.<model>`: Base plus `Stage0..Stage4` (head, torso, arm, legL,
  legR), each MeshPart at its rest pose relative to Base (raiders.md §2 *(p5)*); any named MeshPart missing → placeholder.
- **Pools per kind:** CrowdRenderer's one template and pool (`buildTemplate` :561-576, `table.remove(pool) or
  newEntity()` :1123, `prewarm` :2589-2600) become one pool per model kind plus today's. `StageFlow.Plan` gains `kinds`
  (residents after `countMult` and `minDifficulty`, tent stocks, the boss, each summon's `count` of its kind);
  `RunState.prewarm: { [string]: number }?` (A) carries it where RunFloors.Attach sends `cells` (L4B-8), and WaveService
  sends that RunState before the crowd announces a resident. CombatUIController (:1667-1670) hands it to
  `CrowdRenderer.Prewarm(counts)`, total capped at `crowd.maxAlive` (:2739-2747). An empty pool still builds on demand.
- **Anchor:** each model body keeps an invisible Part `Head` (2 × headRadius, nothing collides or queries) at the scored
  head's centre, so `GetHead` (:2837), `PlateBar.Take` (`PlateBar.luau:89`) and CampFx's "!" (`CampFx.luau:177`) work.
- **Cues:** for a model kind `Cues.Attach` (`Cues.luau:123`) adds only the lit pieces riding the arm or torso (the orb at
  `points.hand`, the marksman's tip, the lobber's round at `points.pack`, the Chief's core at `points.core` sized from
  config, lead-notes.md:11 *(p5)*, not 2.4 → 4.2); horns, pack, barrel, shoulders and crown are the model's.
- **Plate:** `plate` MeshParts show while plated, glint white on a turned hit, hide with today's burst on the break.
- **Warhammer:** `hold` clones the L3 template `Assets.Props.Weapons.Warhammer` (pivot = grip), `ScaleTo(hold.scale)` once
  at pool fill, placed at arm × `CFrame.fromMatrix(grip, right, up)`; missing → the Chief without it, one warn. Gear is
  never painted and fades with the body.
- **Moving:** one BulkMoveTo as today (:2573-2575); `Figures.Queue` writes every MeshPart, the anchor, the lit pieces and
  the hammer; the pose-changed test (:2455-2483) adds the walk phase, its amplitude and the arm. **Shadows:** only the
  torso piece's; none on `lowEndDevice`.

### 3.3 Pose (ui B): new pure `Controllers/Raiders/RaiderPose.luau`

No `game`, no Roblox type, no require: constants and the kind's entry come in as tables, each transform goes out as 12
numbers in `CFrame.new` order, so `luau.exe` runs the file the game runs.
- `Threat(input, consts)`: today's `threatPose` numbers (:2049-2183: lean, thrust, twist, squash, tint, charge) plus the
  arm's clocks (`build`, `snap`, `sweep`, `u`, `slump`, `settle`). CrowdRenderer keeps `setThreat`, `setTint`, `drawTell`;
  the placeholder draws from the same numbers.
- `Rig` = raiderpose.py `rig` (:548-636 *(p5)*); `Arm` = `arm_channel` (:639-677) plus the builder's whirl rule.
- `Walk`: phase += 2π per `rig.strideLegs` × legLength of flat travel; amplitude eased toward clamp(pace / (speed ×
  `rig.walkFullShare`), 0, 1), and 0 past `rig.walkNearStuds` from the camera (`Theme.COMBAT_RAIDER_WALK_NEAR_LOW` 60 on
  `lowEndDevice`). `Paint`: per role the RGB and Neon or not (raiders.md §3 *(p5)*).
- Reactions after a landed hit keep `rootFrame` (:1905-1923) on the rest pose.

### 3.4 The mirror (D2): new `tools/check_raider_mirror.py`

Runs `RaiderPose.luau` under `tycoon\tools\bin\luau.exe` and `raiderpose.py` on the same inputs, every number within
1e-6: every pose `--check` samples (112 a kind, 386 the Chief, raiders.md:97 *(p5)*), a `Threat` grid (shape × phase × age
× enraged), walk steps, every `Paint` state. Its mutants (the `mirror_mutants.py` pattern) must each fail it: a lean sign
flipped, the head clamp removed, the snap skipped, the leg shade dropped. raiderpose.py reads `restDrop` and
`riseBlendSeconds` from config and the real `chief` (its stand-in goes, raiders.md:47-50 *(p5)*), and `--check` adds: a
drawn weapon's flat reach at an attack's impact ≤ its `range` or `reach` + 0.5.

## 4. The Camp Chief (D1)

`ProvingGrounds.json crowd.kinds.chief` starts as the Colossus: 14 / 4 / 1.6, speed 9, hp 4,700, knockback 0, rush, boss,
its colour, enrage at 0.5 (×0.8, ×0.7, chain 2); `name` "Camp Chief". Attacks: the Colossus's `ring` and `lane`; a
`summon` of 10-12 `fodder` (≤ 15, the boss reserve, chief study :122-124 *(p5)*); and **the war-club sweep**, an `arc` in
place of the barrage (the Warlord's arc keys, `range` ≥ the hammer's posed sweep reach − 0.5, about 150°, height 6, base
damage ≤ 33 so `FOREST_HIT_SHARE` holds, :108-109); at most 7 attacks (`CrowdCodec.luau:36, :99`).
`Levels/1_ForestRoad.json`: stage C's boss `chief` (:70), reward `chief` 42,900 / 76 replacing `colossus` (:55), Valor
10. **Moves to `chief`:** `sim_range.py FOREST_BOSS` (:5168) and every band on it (re-measured: tune the Chief, not the
bands), `tests_l1c.luau:314, :374`, any mutate or mirror entry quoting this boss. Hand-written Colossus fixtures stay
(`tests_l1.luau:95`, `tests_l1b.luau:90`).

## 5. Seated hit shapes (A; mirrors D1)

- `ProvingGrounds.json crowd.restDrop` 0.35 and `crowd.riseBlendSeconds` 0.5 (A types them); ui deletes
  `Theme.COMBAT_REST_DROP`, `COMBAT_RISE_BLEND_SECONDS` (:1207-1208) and reads Tuning (`COMBAT_REST_HIP_SHARE` stays).
- CrowdService steps each body's `seat` as the client does (`CrowdRenderer.luau:2276-2285`): toward 1 in `rest`
  (`CrowdCodec.luau:41`), else 0, at 1 / `riseBlendSeconds` a second; a dormant body holds its goal. Pure
  `HitShapes.SeatDrop(height, seat, restDrop)` = height × restDrop × smoothstep(seat).
- `HitShapes.CrowdRay` (:336-366) takes an optional `drop` lowering the head and the capsule top; `WeaponService.gather`
  (:803-837) lowers `head` for every candidate; `CrowdRenderer.ForEach` passes the drop to aim assist and auto-fire
  (`InputController.luau:633`); the rig anchors the head with it.
- Mirrors (D1): `sim_range.py` CrowdRay (:588-600) and the `check_stage_mirror.py` grid (:1261-1287) get drop cases.
  Tests (A, new `tools/crowd_harness/tests_l4w2.luau`): the seat steps, the dormant rule, a ray at a seated head crits and
  one at the old height does not, the real config carries both keys.

## 6. R8 judged fairly (D1, `sim_range.py`)

- **Rule** (§27.5): per spot, policy `sniperFight` = R8's course as today (`sniper_runs` :9554-9564, `SNIPER_*`
  :7183-7190), then `mission` from where he stands to the level's end, against the `mission` player at the same gear,
  difficulty and seed over `R8_SEEDS = 1..30`. A run's rate is its whole pay over its whole minutes (a down: to the down,
  as `sniper_rate` :9941-9946). **A spot fails when its mean cash a minute or mean Timber a minute is above the mission
  player's.** `r8_gate` (:10640-10655) gates it and names the seeds that out-earn; the burst table is printed, ungated.
- **Scope:** all four R8 tables (L3-26) and the ice and tunnel spots. If `--check` then takes over 25 minutes on the gate's
  Python, the fair R8 moves to `--r8`, its own gate line.
- **Mutants** (`check_levels_mutants.py` SIM_CASES; D1 writes them, D2 holds the file): one that counts only the
  sniper's own minutes, one that drops the fight half; each must turn a named row red.
- **Road3 Hard, sword T1 / bow T4** (lookout.md:52-89 *(p5)*): green → closed in BALANCE. **Red → W2 does not merge**;
  Ben gets the 30-seed numbers and lookout.md's options (option 4, camp A's groups, changes no hash).

## 7. The walls in the movement gates (D2, `check_levels.py`)

- Read `barriers[]` from `Config/LevelDress/<layout>.json` (none without the file). A new `Solid` kind `barrier`
  (`Solid` :358-372, `solids_of` :423-447): never ground, never standable, never a sight blocker (`sight_blockers`
  :2489-2497 unchanged), counted in `part_count` (:497-523).
- **Unclimbable:** `is_tall` (:576-578) takes `barrier`; a new expect puts every wall in `unclimbable` (:581-), so a new
  standable top fails by name.
- **"Can" claims are re-proved with a blocking test** (a flat move fails where it crosses a wall's footprint below its
  top): the route (`walk_route` :661), the owners' secret reach (`check_secret_reach` :1165, L2-18a), the sneak
  (`check_sneak` :3758), the ice crossing (:4253, :4280), both designed drops. **"Cannot" claims** (:4684, perches,
  L2-18b-d) hold by L4W2-14; a pinned list that shrinks (the bend hop's known limit) is re-pinned with a BALANCE line.
- **Camp C's sight gate** reads each model kind's posed reach from `RaiderModels.json` in place of `body_reach`
  (:3125-3132, `RENDERER_KEYS` :346).
- **Mutants (CASES)**, each red: a wall across the double-jump gap (x -458..-434, z -26..-8) against the owners' reach; a
  wall top at 20 over its ground against the unclimbable rule; a wall across Road2 against the route; one across the
  sneak against the sneak; `barrier` taken out of `is_tall`.

## 8. Studio levers and phones

Keys only, Studio only (`RunService:IsStudio()`), listed in DEBUG_HINT (`CombatUIController.luau:217-222`). Free: Y, O,
X, Z (taken: N B G H V T U L J F I M K Q E C P).
- **Y** (ui A, local): forest → grey (scenery hidden, `Skinned` Parts shown) → walls (forest plus every `treeline` and
  camp C barrier in red) → forest. **O** (ui A, local): mood B ↔ default lighting. **X** (ui B, local): models ↔
  placeholders, live bodies re-dressed.
- **Z**: lever `dressFail` (`Combat.json debug.dressFailAttribute` "DebugDressFail", both entry points; A, D1, ui B): the
  next level is built grey through the real fallback (memory playtest-repro-methods).
- **Perf** (ui A, `CombatHud.luau`): beside "Server N ms" (:55-61), "Frame N ms" (Heartbeat dt) and "Draw N ms"
  (CrowdRenderer plus LevelScenery), each a p95 over `debug.perfLogSeconds`.

**Phones** (L4W2-15): on `lowEndDevice` no fire particles or lights, no raider shadows, the walk cycle within 60. LOD and
shadows per mesh group are gen_templates' (`LEVEL_GROUP_DRAW` *(p5)*); CastShadow off on `dress`/`canopy` only if Ben's
phone look asks for it.

## 9. Owners (disjoint files) and relays

- **luau-engineer A:** `LevelService`, new `LevelDress`, `WaveService`, `ArenaService`, `StageFlow`, `CrowdService`,
  `WeaponService`, `DebugService`; `HitShapes`, `Catalog`, `Types`; new `tests_l4w2.luau` (every Accept refusal and the
  accept, walls armed, the hidden flags, `Plan.kinds`, the seat).
- **ui-engineer A:** new `LevelScenery.luau`, `src/combat/client/Main.client.luau`, `CombatHud.luau`.
- **ui-engineer B:** `CrowdRenderer`, `ThreatFx/Cues`, `ThreatFx/PlateBar`, new `Raiders/Figures` and `Raiders/RaiderPose`,
  `CombatUIController`, `InputController`, `src/client/UI/Theme.luau` (every Theme change, ui A's constants included).
- **economy-designer D1:** `ProvingGrounds.json`, `Levels/1_ForestRoad.json`, `Combat.json`, `Expeditions.json`,
  `sim_range.py`, `check_stage_mirror.py`, `tests_l1c.luau`, `docs/BALANCE.md`.
- **economy-designer D2:** `forest.py`, `forestcheck.py`, `Config/LevelDress/`, new `raider_frames.py`,
  `Config/RaiderModels.json`, `raiderpose.py`, new `check_raider_mirror.py`, `check_levels.py`, `check_levels_mutants.py`,
  `run_harness.py`, `mutate.py`, `mirror_mutants.py`, `stage_mirror.luau`, every other `tests_*.luau`. (One designer may
  hold both lists, in this order.)
- **Lead:** project files, sourcemaps, the asset run, `Assets.json` (only through the pipeline's tools), the INTERFACES
  pointer `# L4 W2 contracts`.
- **Relays:** D1 → D2 first: the boss rename, committed before the bake. A → ui: the attribute names, `Skinned`,
  `RunState.prewarm`, CrowdRay's `drop`, `SeatDrop`. ui B → D2: RaiderPose's API, the Theme names raiderpose.py reads.
  D2 → ui B: the builder's final config. D1 → A: the new config keys. Everyone → D2: each line a harness pin or a mutate
  entry reads (file, old, new) and new `SOURCES`. Anyone → lead: a project file, a remote or a hub file (none planned).

## 10. Order

0. **Start** once `l4-w1b` is merged and both track reports exist: branch `l4-w2` in `tycoon-p5` (it has the `assets\`
   junction); the full `mutate.py` runs in `tycoon-p5b`.
1. **Before the bake:** D1 renames the boss (§4) and D2 lands L4W2-1, -4, -5; both committed.
2. **Wave A, in parallel:** all the code, every part gated with placeholders (no templates: Accept answers grey, every kind
   is a placeholder).
3. **The asset run** (lead, `l4-w2-asset-run.md`), after Ben's OK of `assets/testfit/out/Raiders/_overview.png`: forest
   build, raider merge, 47 + 35 uploads, **one harvest paste**, `--levels` and `--props` templates, `raider_frames.py`,
   manifest, sourcemaps, place files.
4. **After the paste:** `raider_frames.py --require-harvest`; a four-slice review (server; scenery; raiders and pose; data
   and gates); a fix round from a file and a fix-diff review; QA; docs; Ben's look.

## 11. Definition of done

Each owner before reporting: stylua, selene, luau-lsp on both sourcemaps, `check_compile.py`, the harness, `mutate.py`
filtered to its files. QA from `tycoon-p5` in Bash:

```bash
export PATH="$HOME/.rokit/bin:$PATH"; L=C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe; R=C:/Users/benja/Desktop/tycoon-p5
stylua --check src && selene src
rojo sourcemap default.project.json -o sourcemap.json && rojo sourcemap combat.project.json -o sourcemap.combat.json
luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.json src/client src/server src/shared
luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.combat.json src/combat src/shared
py tools/check_compile.py
rojo build -o build/test.rbxl && rojo build combat.project.json -o build/combat.rbxl
py tools/proving_project.py && rojo build .proving.project.json -o build/proving.rbxl
for p in boomtown metropolis orbital; do rojo build $p.project.json -o build/$p.rbxl; done
py tools/crowd_harness/run_harness.py $R $L
py tools/check_stage_mirror.py && py tools/crowd_harness/mirror_mutants.py --luau $L
py tools/levels/forest.py check && py tools/testfit/raiderpose.py --check
py tools/check_raider_mirror.py --luau $L           # and its mutants
py tools/assets/raider_frames.py --check --require-harvest && py tools/assets/weapon_frames.py --check --require-harvest
py tools/assets/gen_templates.py --check && py tools/gen_asset_manifest.py --check
py -3.12 tools/check_levels.py && py -3.12 tools/sim_range.py --check   # plus --r8 if split (§6)
py tools/sim_combat.py --check && py tools/sim_economy.py --check
py -3.12 tools/check_levels_mutants.py                  # background, about 2 h
py tools/crowd_harness/mutate.py C:/Users/benja/Desktop/tycoon-p5b $L ""   # full run, alone in its worktree
git grep -nE 'COMBAT_REST_DROP|COMBAT_RISE_BLEND|ForestRoad\.dress\.json' -- src tools   # empty
git grep -n '"colossus"' -- src/shared/Config/Levels tools/crowd_harness/tests_l1c.luau  # empty
git diff --stat main -- src/server                      # empty: the hub is untouched
git ls-files --eol | grep -c w/crlf                     # 0
```

Done: every line green with its counts named, and Road3 green (§6). Then Ben's look (docs-keeper writes it, keys only):
depart Forest Road on Normal and see mood B; **Y** at the trailhead gap and the lookout gully, **O** for default light;
camp A's raiders resting, walking, winding up and seated, a plated elite's break; **N** to the clearing (never B), the
Chief's sweep, call and hammer; **X** for placeholders; **Z** then a new run for the grey level; Frame and Draw at the
Main Camp's west gate.

## 12. Risks, and what Ben must judge

1. **Phone frame time is unmeasurable before W4's staging publish** (Studio's device view is not a phone): until then only
   his desktop Frame and Draw, for about 150k forest triangles (forest.md:13-15 *(p5)*) and 81k of raiders
   (raiders.md:158-160) in about 950 moving MeshParts.
2. **Run-start hitch:** pool fills (about 11 MeshParts a body) and 61 scenery clones land together.
3. **A skin off its hidden Part** (a turn or offset bug) shows ground where there is none; the turn proof is offline only,
   **Y** is Ben's check.
4. **The bands move** with the seated drop and the sweep; re-measured. The hammer's 17 studs against a 16 sweep
   (raiders.md:191-193) must be reconciled (§3.4).
5. **R8 at 30 seeds** costs about ten times today's runs; Road3's outcome is unknown until run.
6. **The threatPose split touches every tell**, placeholders included: its own review slice.
7. **Read, not run:** Neon on untextured MeshParts, local Transparency writes, a client-made Atmosphere, Automatic LOD.
8. **Text drift:** about 1,700 mutate entries and 150 pins read this code; one stale entry blocks the full run.
9. **Only Ben can judge** the forest in real light, mood B against A, whether invisible edges feel fair (the camera passes
   trunks, forest.md:258-259), the walk, whether tells read on models, headshots on seated and winding bodies, the Chief
   in motion, and **whether dodging still feels the same after W1b's dash proof** (L4B-7, W1b §4.5).
