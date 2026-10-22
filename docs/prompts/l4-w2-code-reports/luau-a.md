# L4 W2 code wave: luau-engineer A's report (kept current)

Worktree `tycoon-p5`, branch `l4-w2`. Nothing committed. Started 2026-10-22. Python numbers: harness via its shebang
(3.12 64-bit).

## State

- [x] `Types.luau`: `LevelDress` (+ Mesh, Prop, Effect, Barrier), `AssetsConfig.levels`, `RaiderModelsConfig` (+ Rig,
  KindModel, Piece, Arm, ArmShape, Cue, PosedReach, Hold, `RaiderPartRole` incl. `clothLeg`), `RunState.prewarm`,
  `ProvingGroundsConfig.crowd.restDrop` / `riseBlendSeconds`, `LevelSecretConfig.key`, `ExpeditionsConfig.keys` /
  `moods` (`LevelMood`), `MapSecretState.key`, `CombatFxSecret.key`, `CombatDebugConfig.dressFailAttribute`.
- [x] `Catalog.luau`: `GetLevelDress(layout)`, `GetRaiderModelsConfig()`.
- [x] New pure `LevelDress.luau` (`Accept`, `LeftOut`, `Overlay`, `WALL_ROLE`).
- [x] `LevelService.luau`: Build accepts or refuses the dress, builds the walls armed, hides the skinned pieces, lays
  the looks, sets `Dress` / `DressHash` last; Clear nils them first; `FailNextDress` (the Z lever).
- [x] `DebugService.luau`: lever `dressFail` (RequestDebug and the `dressFailAttribute` number attribute).
- [x] `StageFlow.luau`: `Plan.kinds`; `secretProblems` refuses a bad `key`.
- [x] `WaveService.luau`: Build gets `level.layout`; `run.prewarm = plan.kinds`; the chest's fx carries `key`.
- [x] `ArenaService.luau`: `RunFields.prewarm`, sent with a member's first RunState of a floor set only.
- [x] `CrowdService.luau`: every body's `seat` (stepSeats after the integrate loop; SpawnResident seats a fire's body
  at once; dormant = goal); `Get` returns `seat`.
- [x] `HitShapes.luau`: `SeatDrop`, `SeatStep`, `CrowdRay(..., drop?)`.
- [x] `WeaponService.luau`: `gather` lowers every candidate's head by its drop and hands the drop to `test`;
  `rayCandidates` passes it to `CrowdRay`.
- [x] `SecretFlow.luau` / `Unlocks.luau` (the Castle Key's server side, contract §0): `Reward.key` (a key-only entry is
  a reward entry), `Opening.key`, `MapRow`'s `key`; `Unlocks.HasLevelKey`.
- [x] New `tools/crowd_harness/tests_l4w2.luau`. D2 has landed its SOURCES / TESTS / fixtures lines and mutate.py's
  FILES (LevelDress, Assets.json, the dress files): the real harness is **PASS (4,358 checks)**.
- [ ] waiting on D2: the 2 stale entries (re-aimed texts below, both proven caught) and the 66 new entries and pins.
- [x] `Types.RaiderPartRole` has `clothLeg` (ui B's and D2's note).

## Contracts as built (signatures)

```luau
-- LevelDress (pure; src/combat/server/Services/LevelDress.luau)
export type Accepted = { walls: { LevelGeometry.Piece }, hidden: { [string]: boolean }, looks: { [string]: Types.LevelLook } }
LevelDress.WALL_ROLE = "treeline"
LevelDress.Accept(dress: Types.LevelDress?, uploadedHash: string?, haveMeshes: { [string]: boolean },
	pieces: { LevelGeometry.Piece }, open: { [string]: boolean }?, groupsOk: boolean, maxParts: number,
	layout: string): (Accepted?, string?)
LevelDress.LeftOut(layout: Types.LevelLayout, open: { [string]: boolean }?): { [string]: boolean }
LevelDress.Overlay(base: { [string]: Types.LevelLook }?, over: { [string]: Types.LevelLook }?): { [string]: Types.LevelLook }
-- LevelService
LevelService.Build(layout, expeditions, rules, open: { [string]: boolean }?, layoutName: string?): boolean
LevelService.FailNextDress(): ()
-- Catalog
Catalog.GetLevelDress(layout: string): Types.LevelDress?
Catalog.GetRaiderModelsConfig(): Types.RaiderModelsConfig?
-- HitShapes
HitShapes.SeatDrop(height: number, seat: number, restDrop: number): number      -- height x restDrop x smoothstep(clamp(seat))
HitShapes.SeatStep(seat: number, goal: number, dt: number, blendSeconds: number): number
HitShapes.CrowdRay(origin, direction, reach, width, pad, feet, radius, height, headRadius, drop: number?): (number?, boolean)
-- StageFlow
Plan.kinds: { [string]: number }
-- Unlocks
Unlocks.HasLevelKey(combat: Types.CombatProfile?, key: string,
	levels: { { id: string, secrets: { [string]: Types.LevelSecretConfig }? } }): boolean
-- CrowdService
CrowdService.Get(id).seat: number
```

Accept's refusals, in order (each names why): no dress; `layout` differs; `frame` is not "level"; nothing uploaded
(`uploadedHash` nil); `planHash` not a string or not the uploaded one; meshes not a list, a mesh with no name, a mesh
with no template; hide not a table / hide.blocks not a list / a name that is no string; a hide.blocks name that is no
block piece and not left out by `open`; hide.camps not a table / a camp id no piece has / a list that is no list / a role
other than floor, fence, obstacle, fire, tent / a role that camp has no piece of; `groupsOk` false; barriers not a list;
a barrier with no name, a non-finite number or a size not above 0; a barrier name already a piece's or an earlier
barrier's; `#pieces + #walls > maxParts`. Accepted: walls (role treeline, no camp, no look, collide true, in file
order), hidden (piece names), looks (the dress's, for Overlay).

## Assumptions and deviations (the lead may overrule)

1. **`LevelDress.Accept` takes an 8th argument, `layout` (the name the level asked for).** The contract's seven arguments
   cannot say which layout the dress must be for ("its `layout` ... differ"); a dress copied under another name is now
   refused.
2. **Accept's `open` is the set of block NAMES a found shortcut left out** (`LevelDress.LeftOut(layout, open)`), not the
   shortcut ids: with ids alone Accept cannot tell which hidden name was left out (L2-36).
3. **`hide.camps` roles are held to the five L4W2-5 names** (floor, fence, obstacle, fire, tent). A gate, a checkpoint
   or a camp's own wall is shown or recoloured by SetCamp, so hiding one would be undone mid-run.
4. **Two refusals beyond the contract:** a barrier whose name is already a piece's (or repeats) is refused (the client's
   prop `with` and the Y lever find Parts by name), and the malformed-file shapes above (meshes / hide / barriers that
   are not tables) are refusals, never a throw.
5. `LevelService.Build` gains a 5th argument `layoutName: string?` (nil = never dressed: the lobby). WaveService passes
   `level.layout`. A refused dress warns `[LevelService] the level is grey: <reason>` once per Build (so every Z press
   shows it), never once per session.
6. **`Unlocks.HasLevelKey(combat, key, levels)`** takes the level files: the contract's two-argument form cannot know which
   secret gives a key without them (mountain.md's own proposal had the third argument). Nothing calls it in W2 but the
   tests.
7. **`Plan.kinds`** counts residents (minDifficulty, never countMult: residents are placed once, L1b-10), every tent's
   stock, and of the locking camps' waves the most any ONE wave fields of a kind: its groups x countMult (rounded, a
   party of one), its boss (+1) and each summon kind's largest call (a call tops up, so calls never add). The contract's
   "residents after countMult" read as the waves' groups (residents never take countMult).
8. **The seat on a missing config key** (`restDrop` / `riseBlendSeconds` nil, negative, NaN): SeatDrop drops nothing and
   SeatStep reaches the goal at once, so a Studio tune or an old config never throws in the crowd's Heartbeat. D1's keys
   are in.
9. The seat steps after the integrate loop (`stepSeats`), from the state that step decided, as the client steps it from
   the wire's state; dead bodies are skipped (only hits read the seat). SpawnResident seats a body shown at rest (a fire's)
   at once, as the client draws a body first seen at rest.
10. `prewarm` rides in `sendRunState` beside the cells (`if cellsWent`), so a rejoin and a latecomer get it too;
    `BuildRunState` never carries it.
11. The hub is untouched (`git diff --stat main -- src/server`: empty). No remote, no project file.

## For the other owners

### ui-engineer A (LevelScenery, MapScreen, SecretFx)

- `Workspace.Level` attributes **`Dress`** (string, the layout name) and **`DressHash`** (string, the plan hash): set last in
  Build, after every Part is parented; both set to nil first in Clear (before `ClearAllChildren`), and at Build's start.
  Your reading in ui-a.md matches.
- Hidden pieces: attribute **`Skinned`** = `true`, `Transparency` 1, `CastShadow` false, collision and query as built; direct
  children of `Workspace.Level`.
- Dress walls: Parts named as the dress's barriers (`TreeLine1`...), direct children of `Workspace.Level`, CollisionGroup
  `"ArenaBarrier"`, Transparency 1, CanCollide true, CanTouch false, CastShadow false. Camp C's `Barrier_C_<n>` are in the
  same group (CanCollide only while closed).
- `CombatFxSecret.key` (event "found" only), `MapSecretState.key`, `Types.ExpeditionsConfig.keys` / `.moods`
  (`Types.LevelMood = { lighting: WorldLightingConfig?, atmosphere: WorldAtmosphereConfig? }`).
- The Z lever's server name: `RequestDebug("dressFail", true)` (any value; the attribute path is the number attribute
  `Combat.json debug.dressFailAttribute` "DebugDressFail" > 0). It spends at the next level built.

### ui-engineer B (CrowdRenderer, InputController, CombatUIController, Figures)

- `RunState.prewarm: { [string]: number }?` = StageFlow.Plan's `kinds` (crowd kind -> bodies), only on a member's first
  RunState of a `floorsSeq` (the one that carries the cells), nil afterwards and in the lobby. Forest Road on Normal:
  armoured 8, brute 32, chief 1, fodder 48, lobber 2, slinger 24 (115; cap it at crowd.maxAlive as the contract says).
- `HitShapes.CrowdRay(..., headRadius, drop)`: the 10th argument, nil = 0. `HitShapes.SeatDrop(height, seat, restDrop)`
  with `Tuning.Get().crowd.restDrop`; `HitShapes.SeatStep(seat, goal, dt, Tuning.Get().crowd.riseBlendSeconds)` is the
  server's exact step (toward 1 in `rest`, else 0) if you want one formula on both sides.
- The server seats a body first seen at rest at once (as your `entity.seat = if state == "rest" then 1 else 0`), and a
  dormant body sits at its goal.
- The `X`/`Z` keys: `Z` fires `RequestDebug("dressFail", true)`.
- `Types.RaiderModelsConfig` (`Catalog.GetRaiderModelsConfig()`): roles include `clothLeg` (D2's note). "An entry counts
  only when its height, radius, headRadius equal ProvingGrounds.json's" is yours to apply in Figures (no shared helper).

### economy-designer D1 (sim_range.py, check_stage_mirror.py)

- CrowdRay with a drop, word for word: `top = max(height - 2*headRadius, height/2 + radius) - drop`,
  `head = feet + (0, height - headRadius - drop, 0)`; the capsule is RayUpright(feet, low = radius, high = top - radius,
  radius) as before (high <= low = the sphere at its foot). `drop = height * restDrop * u*u*(3 - 2u)`, `u = clamp(seat,
  0, 1)`; a restDrop that is not a finite number >= 0, a height not finite and > 0, or a NaN seat gives 0.
- Seat stepping: `SeatStep(seat, goal, dt, blend)` = goal (clamped 0..1) at once when blend is not a finite number > 0
  or seat is NaN; else step = max(dt, 0) / blend, up `min(seat + step, goal)`, down `max(seat - step, goal)`. The crowd
  steps it once per crowd step after the bodies move (goal 1 while the state is `rest`), dormant = goal, dead skipped;
  SpawnResident sets 1 when the body is first shown `rest`. Your report says the sim mirrors this: matches.
- `secretProblems`' key line: `key ~= nil and (type(key) ~= "string" or key == "" or #key > 24)` ->
  `secrets.<id>.key is <tostring(key)>, not a key id`. Matches your mirror.

### economy-designer D2 (run_harness.py, mutate.py, tests)

**1. run_harness.py** (exact lines; my scratch copy with exactly these runs PASS 4,358 checks):
- `SOURCES`: after `"RunFloors": "src/shared/RunFloors.luau",` add
  `    "LevelDress": "src/combat/server/Services/LevelDress.luau",`
- `TESTS`: after `"tests_l4b_run.luau",` add `    "tests_l4w2.luau",` (last: it carries the VERDICT line).
- `fixtures()`: after `"layouts": layouts,` add
  ```python
          # L4 W2: the level dress files and the uploaded plan hashes (tests_l4w2.luau).
          "levelDress": dict(read_folder(repo, "src/shared/Config/LevelDress")),
          "levelHashes": {name: entry.get("planHash") for name, entry in (read(repo, "src/shared/Config/Assets.json").get("levels") or {}).items()},
  ```
- **mutate.py FILES** must then also copy `src/shared/Config/Assets.json` and `src/shared/Config/LevelDress/*.json` (the
  baseline reads them through the fixtures), and `src/combat/server/Services/LevelDress.luau`, `SecretFlow.luau`,
  `src/shared/Unlocks.luau` if FILES lacks them (check: my entries below name them).

**2. Two mutate.py entries my edits made stale** (same labels, new texts):
- `"l1b w2 crowd: CrowdRay's head at half height"` (HITSHAPES):
  old `"local head = feet + Vector3.new(0, height - headRadius - lower, 0)\n\tlocal bodyEntry"`,
  new `"local head = feet + Vector3.new(0, height / 2 - lower, 0)\n\tlocal bodyEntry"`.
- `"l2: a name alone is a reward entry"` (SECRET_FLOW):
  old `"\tif\n\t\tentry == nil\n\t\tor (\n\t\t\tentry.valor == nil\n\t\t\tand entry.materials == nil\n\t\t\tand entry.family == nil\n\t\t\tand entry.key == nil\n\t\t)\n\tthen\n"`,
  new `"\tif entry == nil then\n"`.
- Both re-aimed entries, run in my scratch copy of the harness: caught (54 and 3 checks fail).
- (`"l1b w2 crowd: CrowdRay's body back to a sphere"` and the `local top = math.max(...)` entry still match once; the
  latter now leaves `- lower` after its replacement, which is still the mutation it was.)
- Every other of the 1,830 entries still reads its text exactly once (my scratch scan of the whole list).

**3. New mutate.py entries** (66; each caught in my scratch run, see Gates): the dict `L4W2_A_MUTATIONS` at the end of
this report, constants `LEVEL_DRESS`, `FLOW`, `HITSHAPES`, `CROWD`, `SECRET_FLOW`, `UNLOCKS` as named there.

**4. Text pins I propose** (`source.l4w2`, the L3 pattern; LevelService, WeaponService, WaveService, ArenaService and
DebugService cannot load). Each counted in the function named (whole lines):
- `local function construct(` body: `local isWall = piece.role == LevelDress.WALL_ROLE` (1);
  `if (isBarrier or isWall) and not walls then` (1); `part.CollisionGroup = BarrierGroups.BARRIER` (2: the camp's wall
  and the dress wall); `part.CanCollide = true` (1, in the `elseif isWall then` branch); `if hidden ~= nil and
  hidden[piece.name] then` (1) followed by `part.Transparency = 1`, `part.CastShadow = false`,
  `part:SetAttribute(CONST.SKINNED_ATTRIBUTE, true)`, and before `part.Parent = folder`.
- `function LevelService.Build(` body: `accepted, planHash = dressOf(layout, layoutName, pieces, open, rules.maxParts)`;
  `looks = LevelDress.Overlay(expeditions.looks, accepted.looks),`; `table.move(accepted.walls, 1, #accepted.walls,
  #built + 1, built)`; `local camps, problem = place(folder, built, expeditions, reactive, ice, dressed)`;
  `state.looks = if dressed ~= nil then dressed.looks else expeditions.looks`; and `folder:SetAttribute(CONST.DRESS_ATTRIBUTE,
  layoutName)` / `folder:SetAttribute(CONST.DRESS_HASH_ATTRIBUTE, planHash)` after `state.built = true`.
- `local function dressOf(` body: `LevelDress.LeftOut(layout, open),` and `BarrierGroups.Ensure(),` and
  `hash = CONST.FAILED_HASH` after `state.failNextDress = false`.
- `function LevelService.Clear(` body: the two `folder:SetAttribute(CONST.DRESS..., nil)` lines before
  `folder:ClearAllChildren()`.
- WeaponService `local function gather(`: `local drop = HitShapes.SeatDrop(def.height, enemy.seat, restDrop)`,
  `local head = enemy.position + Vector3.new(0, def.height - def.headRadius - drop, 0)`,
  `test(body, def.radius, head, def.headRadius, enemy.position, def.height, drop)`; `local function rayCandidates(`:
  `\t\t\t\theadRadius,\n\t\t\t\tdrop\n\t\t\t)` (CrowdRay's last two).
- WaveService: `run.prewarm = plan.kinds`; `prewarm = run.prewarm,` (pushRunFields); `level.layout` as Build's 5th
  argument; `key = opening.key,` (announceSecret).
- ArenaService `local function sendRunState(`: `sent.prewarm = runFields.prewarm` inside `if cellsWent then`.
- DebugService: `elseif lever == "dressFail" then\n\t\tLevelService.FailNextDress()`.

**5. My tests read** `L1B`, `L1BC`, `W2A`, `W2B` (tests_l1b*, tests_l1b_w2*), `step2`, `root`, `config`, `Crowd`, `check`,
`near`, `vec`, `load`, `FIXTURES`: keep tests_l4w2.luau after those in TESTS.

### Lead

- No project file, remote or hub change.
- Optional (Tuning.luau has no W2 owner): add `"^crowd%.restDrop$"` and `"^crowd%.riseBlendSeconds$"` to Tuning's
  `NON_NEGATIVE_PATHS`, so the Studio tune panel refuses a negative seat. Not needed for safety (HitShapes guards both).

## Gates (2026-10-22)

- `stylua --check` and `selene` on my 13 files and the test file: clean (0 errors, 0 warnings).
- `luau-lsp analyze` on both sourcemaps (written to my scratch folder): 0 diagnostics in `src/combat/server` and
  `src/shared`; the client diagnostics listed are other owners' work in progress (Theme keys, Figures).
- `py tools/check_compile.py`: PASS, 181 files.
- Harness in the worktree (D2's run_harness.py lines in): **PASS (4,358 checks)**, tests_l4w2.luau's checks all green.
  Before D2's lines my edits broke no existing pin or case.
- Mutants (my own scratch runner on a copy of the tree, never `mutate.py`, never this worktree's `mutant/`): the 66
  proposed entries below, **66 caught**. The first pass missed one ("a camp no piece has is taken": two refusal texts
  shared "no piece of"); the case now names the camp's own reason, and the entry is caught on a fresh copy.
- The 2 re-aimed stale entries: both caught (54 and 3 checks fail). All 68 texts read exactly once in the worktree.
- mutate.py's other 1,828 entries still read their texts once (a scan of the whole list).

## Appendix: the proposed mutate.py entries (D2 pastes them; constants are the repo paths)

```python
# luau-engineer A's proposed mutate.py entries for L4 W2 (each must be caught by tests_l4w2.luau).
LEVEL_DRESS = "src/combat/server/Services/LevelDress.luau"
FLOW = "src/combat/server/Services/StageFlow.luau"
HITSHAPES = "src/shared/HitShapes.luau"
CROWD = "src/combat/server/Services/CrowdService.luau"
SECRET_FLOW = "src/combat/server/Services/SecretFlow.luau"
UNLOCKS = "src/shared/Unlocks.luau"

L4W2_A_MUTATIONS = {
    # LevelDress.Accept
    "l4w2 dress: a dress of another layout is taken": (LEVEL_DRESS, "\tif file.layout ~= layout then\n", "\tif false then\n"),
    "l4w2 dress: any frame is taken": (LEVEL_DRESS, "\tif file.frame ~= LEVEL_FRAME then\n", "\tif false then\n"),
    "l4w2 dress: nothing uploaded is not named": (LEVEL_DRESS, "\tif uploadedHash == nil then\n", "\tif false then\n"),
    "l4w2 dress: another plan's hash is taken": (LEVEL_DRESS, 'if type(file.planHash) ~= "string" or file.planHash ~= uploadedHash then', 'if type(file.planHash) ~= "string" then'),
    "l4w2 dress: a mesh with no template is taken": (LEVEL_DRESS, "\t\tif haveMeshes[name] ~= true then\n", "\t\tif false then\n"),
    "l4w2 dress: a mesh with no name is taken": (LEVEL_DRESS, "\t\tif type(name) ~= \"string\" then\n\t\t\treturn nil, `mesh {index} has no name`\n", "\t\tif false then\n\t\t\treturn nil, `mesh {index} has no name`\n"),
    "l4w2 dress: a hidden block no block is is taken": (LEVEL_DRESS, "\t\telseif open == nil or open[name] ~= true then\n", "\t\telseif false then\n"),
    "l4w2 dress: a left-out block is refused": (LEVEL_DRESS, "\t\telseif open == nil or open[name] ~= true then\n", "\t\telse\n"),
    "l4w2 dress: a named block is not hidden": (LEVEL_DRESS, "\t\tif blocks[name] then\n\t\t\thidden[name] = true\n", "\t\tif blocks[name] then\n\t\t\thidden[name] = nil\n"),
    "l4w2 dress: a camp-piece name counts as a block": (LEVEL_DRESS, '\t\tif piece.role == "block" then\n\t\t\tblocks[piece.name] = true\n', "\t\tdo\n\t\t\tblocks[piece.name] = true\n"),
    "l4w2 dress: a camp no piece has is taken": (LEVEL_DRESS, "\t\tif own == nil then\n\t\t\treturn nil, `hide.camps names the camp", "\t\tif own == nil then\n\t\t\town = {}\n\t\tend\n\t\tif false then\n\t\t\treturn nil, `hide.camps names the camp"),
    "l4w2 dress: any role may be hidden": (LEVEL_DRESS, 'if type(role) ~= "string" or HIDEABLE[role] ~= true then', 'if type(role) ~= "string" then'),
    "l4w2 dress: a role no piece of the camp has is taken": (LEVEL_DRESS, "\t\t\tif own[role] ~= true then\n", "\t\t\tif false then\n"),
    "l4w2 dress: the camp roles hide nothing": (LEVEL_DRESS, "\t\tif wanted ~= nil and wanted[piece.role] then\n", "\t\tif false then\n"),
    "l4w2 dress: the walls' groups are not asked": (LEVEL_DRESS, "\tif not groupsOk then\n", "\tif false then\n"),
    "l4w2 dress: a barrier with no name is taken": (LEVEL_DRESS, 'if type(name) ~= "string" or name == "" or box == nil then', "if box == nil then"),
    "l4w2 dress: a barrier's numbers are not checked": (LEVEL_DRESS, 'if type(name) ~= "string" or name == "" or box == nil then', 'if type(name) ~= "string" or name == "" then'),
    "l4w2 dress: a NaN barrier is sound": (LEVEL_DRESS, "\t\tnot (finite(x) and finite(y) and finite(z) and finite(sx) and finite(sy) and finite(sz))\n", "\t\tfalse\n"),
    "l4w2 dress: a flat barrier is sound": (LEVEL_DRESS, "\t\tor sx <= 0\n\t\tor sy <= 0\n\t\tor sz <= 0\n", ""),
    "l4w2 dress: a barrier's name may be taken": (LEVEL_DRESS, "\t\tif named[name] then\n", "\t\tif false then\n"),
    "l4w2 dress: the walls do not count": (LEVEL_DRESS, "\tlocal count = #pieces + #walls\n", "\tlocal count = #pieces\n"),
    "l4w2 dress: maxParts one short": (LEVEL_DRESS, "\tif count > maxParts then\n", "\tif count >= maxParts then\n"),
    "l4w2 dress: a wall is not armed": (LEVEL_DRESS, "\t\t\tcollide = true,\n", "\t\t\tcollide = false,\n"),
    "l4w2 dress: a wall is a camp's barrier": (LEVEL_DRESS, "\t\t\trole = WALL_ROLE,\n", '\t\t\trole = "barrier",\n'),
    "l4w2 dress: the dress's looks dropped": (LEVEL_DRESS, '\t\tlooks = if type(looks) == "table" then looks else {},\n', "\t\tlooks = {},\n"),
    "l4w2 dress: Overlay writes the base": (LEVEL_DRESS, "= if base ~= nil then table.clone(base) else {}", "= if base ~= nil then base else {}"),
    "l4w2 dress: Overlay keeps the base's look": (LEVEL_DRESS, "\t\t\tlooks[name] = look\n", "\t\t\tlooks[name] = looks[name] or look\n"),
    "l4w2 dress: LeftOut leaves nothing out": (LEVEL_DRESS, "\t\t\tleft[block.name] = true\n", "\t\t\tleft[block.name] = nil\n"),
    "l4w2 dress: LeftOut leaves out every opening block": (LEVEL_DRESS, "\t\t\tand open[block.opens] == true\n", ""),
    # StageFlow.Plan's kinds
    "l4w2 kinds: residents not counted": (FLOW, "\t\tfor kind, count in stock do\n\t\t\tcounts[kind] = (counts[kind] or 0) + count\n", "\t\tfor kind, count in stock do\n\t\t\tcounts[kind] = (counts[kind] or 0) + 0 * count\n"),
    "l4w2 kinds: tents not counted": (FLOW, "\t\tfor _, kind in tent.kinds do\n\t\t\tcounts[kind] = (counts[kind] or 0) + 1\n", "\t\tfor _, kind in tent.kinds do\n\t\t\tcounts[kind] = (counts[kind] or 0) + 0\n"),
    "l4w2 kinds: the waves summed, not the most": (FLOW, "\t\t\t\tmost[kind] = math.max(most[kind] or 0, count)\n", "\t\t\t\tmost[kind] = (most[kind] or 0) + count\n"),
    "l4w2 kinds: countMult not applied": (FLOW, "\t\t\t\t\t+ math.max(math.round(unit.count * countMult), 0)\n", "\t\t\t\t\t+ unit.count\n"),
    "l4w2 kinds: a wave's minDifficulty ignored": (FLOW, "\t\t\tfor _, unit in fieldedUnits(wave.groups or {}, rank, ranks) do\n", "\t\t\tfor _, unit in wave.groups or {} do\n"),
    "l4w2 kinds: the boss not counted": (FLOW, "\t\t\t\there[boss.kind] = (here[boss.kind] or 0) + 1\n", "\t\t\t\there[boss.kind] = (here[boss.kind] or 0) + 0\n"),
    "l4w2 kinds: a boss's calls added up": (FLOW, "\t\t\t\t\t\tcalls[raised] = math.max(calls[raised] or 0, attack.count or 0)\n", "\t\t\t\t\t\tcalls[raised] = (calls[raised] or 0) + (attack.count or 0)\n"),
    "l4w2 kinds: a boss's calls not counted": (FLOW, "\t\t\t\t\there[kind] = (here[kind] or 0) + count\n\t\t\t\tend\n\t\t\tend\n\t\t\tfor kind, count in here do\n", "\t\t\t\t\there[kind] = (here[kind] or 0) + 0 * count\n\t\t\t\tend\n\t\t\tend\n\t\t\tfor kind, count in here do\n"),
    "l4w2 kinds: an empty kind kept": (FLOW, "\t\tif count <= 0 then\n\t\t\tcounts[kind] = nil\n", "\t\tif count < 0 then\n\t\t\tcounts[kind] = nil\n"),
    "l4w2 kinds: Plan reads no countMult": (FLOW, "\t\t\tlevel.difficulties[difficulty].countMult,\n", "\t\t\t1,\n"),
    # The seat
    "l4w2 seat: SeatDrop not eased": (HITSHAPES, "\treturn height * restDrop * u * u * (3 - 2 * u)\n", "\treturn height * restDrop * u\n"),
    "l4w2 seat: SeatDrop not clamped": (HITSHAPES, "\tlocal u = math.min(math.max(seat, 0), 1)\n", "\tlocal u = seat\n"),
    "l4w2 seat: SeatDrop takes a negative restDrop": (HITSHAPES, "\t\tor not (restDrop >= 0 and restDrop < math.huge)\n", "\t\tor not (restDrop < math.huge)\n"),
    "l4w2 seat: SeatStep overshoots up": (HITSHAPES, "\t\treturn math.min(seat + step, target)\n", "\t\treturn seat + step\n"),
    "l4w2 seat: SeatStep overshoots down": (HITSHAPES, "\treturn math.max(seat - step, target)\n", "\treturn seat - step\n"),
    "l4w2 seat: SeatStep at twice the pace": (HITSHAPES, "\tlocal step = math.max(dt, 0) / blendSeconds\n", "\tlocal step = 2 * math.max(dt, 0) / blendSeconds\n"),
    "l4w2 seat: SeatStep with no pace never moves": (HITSHAPES, "\t\treturn target\n\tend\n\tlocal step", "\t\treturn seat\n\tend\n\tlocal step"),
    "l4w2 seat: CrowdRay's head not lowered": (HITSHAPES, "\tlocal head = feet + Vector3.new(0, height - headRadius - lower, 0)\n", "\tlocal head = feet + Vector3.new(0, height - headRadius, 0)\n"),
    "l4w2 seat: CrowdRay's capsule top not lowered": (HITSHAPES, "\tlocal top = math.max(height - 2 * headRadius, height / 2 + radius) - lower\n", "\tlocal top = math.max(height - 2 * headRadius, height / 2 + radius)\n"),
    "l4w2 seat: CrowdRay ignores its drop": (HITSHAPES, "\tlocal lower = drop or 0\n", "\tlocal lower = 0\n"),
    "l4w2 seat: the crowd never steps a seat": (CROWD, "\tstepSeats(dt, crowd.riseBlendSeconds)\n", ""),
    "l4w2 seat: a dormant body steps its seat": (CROWD, "\t\tenemy.seat = if enemy.dormant\n\t\t\tthen goal\n\t\t\telse HitShapes.SeatStep(enemy.seat, goal, dt, riseBlendSeconds)\n", "\t\tenemy.seat = HitShapes.SeatStep(enemy.seat, goal, dt, riseBlendSeconds)\n"),
    "l4w2 seat: a dormant body stands": (CROWD, "\t\t\tthen goal\n\t\t\telse HitShapes.SeatStep(", "\t\t\tthen 0\n\t\t\telse HitShapes.SeatStep("),
    "l4w2 seat: nobody's goal is the seat": (CROWD, '\t\tlocal goal = if enemy.state == "rest" then 1 else 0\n', "\t\tlocal goal = 0\n"),
    "l4w2 seat: a resident placed at a fire stands": (CROWD, '\tenemy.seat = if shown == "rest" then 1 else 0\n', "\tenemy.seat = 0\n"),
    "l4w2 seat: Get hides the seat": (CROWD, "\t\tseat = enemy.seat,\n", "\t\tseat = 0,\n"),
    # The Castle Key
    "l4w2 key: Validate takes any key": (FLOW, '\t\t\tkey ~= nil and (type(key) ~= "string" or key == "" or #key > Unlocks.MAX_FAMILY_LENGTH)\n', "\t\t\tfalse\n"),
    "l4w2 key: Validate takes a long key": (FLOW, '(type(key) ~= "string" or key == "" or #key > Unlocks.MAX_FAMILY_LENGTH)', '(type(key) ~= "string" or key == "")'),
    "l4w2 key: Validate takes an empty key": (FLOW, '(type(key) ~= "string" or key == "" or #key > Unlocks.MAX_FAMILY_LENGTH)', '(type(key) ~= "string" or #key > Unlocks.MAX_FAMILY_LENGTH)'),
    "l4w2 key: a key is no reward field": (SECRET_FLOW, "\t\t\tand entry.key == nil\n", ""),
    "l4w2 key: the reward drops its key": (SECRET_FLOW, '\t\tkey = if type(key) == "string" and key ~= "" then key else nil,\n', "\t\tkey = nil,\n"),
    "l4w2 key: the opening drops its key": (SECRET_FLOW, "\t\tkey = reward.key,\n", "\t\tkey = nil,\n"),
    "l4w2 key: the map row drops its key": (SECRET_FLOW, "\t\t\tkey = if reward ~= nil then reward.key else nil,\n", "\t\t\tkey = nil,\n"),
    "l4w2 key: HasLevelKey needs no opening": (UNLOCKS, 'if type(entry) == "table" and entry.key == key and own[secretId] == true then', 'if type(entry) == "table" and entry.key == key then'),
    "l4w2 key: HasLevelKey takes any key": (UNLOCKS, 'if type(entry) == "table" and entry.key == key and own[secretId] == true then', 'if type(entry) == "table" and own[secretId] == true then'),
    "l4w2 key: HasLevelKey reads any level": (UNLOCKS, "\t\tlocal own: any = opened[level.id]\n", "\t\tlocal own: any = opened.otherLevel or opened[level.id]\n"),
    "l4w2 key: HasLevelKey never held": (UNLOCKS, "\t\t\t\treturn true\n\t\t\tend\n\t\tend\n\tend\n\treturn false\nend\n", "\t\t\t\treturn false\n\t\t\tend\n\t\tend\n\tend\n\treturn false\nend\n"),
}
```
