# L4 W2 review, slice 1: server and shared (afdce67)

Reviewer: roblox-reviewer (read only). Diff: `git diff 37ccfe4..afdce67`, restricted to `src/combat/server/Services/`
(LevelDress, LevelService, WaveService, ArenaService, StageFlow, CrowdService, WeaponService, DebugService, SecretFlow),
`src/shared/` (Types, Catalog, HitShapes, Unlocks, Tuning) and `tools/crowd_harness/tests_l4w2.luau`.

**Totals: 0 Critical, 0 Major, 3 Minor, 3 Suggestions.**

How the probes ran: on a `git archive afdce67` copy in my scratch folder, never in a worktree. The baseline harness gave
`HARNESS: PASS (4,412 checks)`. For each probe I applied one source mutation, ran the copy's own `run_harness.py` under
`py -3.12 -I -B` with the main checkout's `luau.exe`, then restored the file. I did not run `mutate.py`.
`luau-lsp analyze` on `src/combat/server` and `src/shared` against the combat sourcemap gives 0 diagnostics.

**Overlaps with the other slices (count each once):**
- **My m1 is slice 4's m2** (`4-data.md`, probes P1-P6). Mine adds two probes that also survive: `return accepted, hash`
  → `return accepted, nil` (the same invisible level as their P1), and the wall branch's `Transparency = 0` (70 grey slabs
  up to 280 studs tall). Route one fix.
- **My s1 is slice 2's m2** (`2-scenery.md`). Slice 2 rates it Minor because its m3 race gives a realistic trigger;
  follow that rating.
- **Slice 2's m1** (Accept never checks `props` / `effects`, so the server accepts a file the client then throws on)
  complements my m2. Both ask that Accept refuse every shape that LevelService or LevelScenery iterates.

## Minor

### m1. The pins hold the dress calls but not the conditions around them: a mutant that hides every skinned Part with no mesh over it passes

**Where:**
- `src/combat/server/Services/LevelService.luau:778`: `if dressed ~= nil and layoutName ~= nil and planHash ~= nil then`
- `LevelService.luau:714`: `return accepted, hash`
- `LevelService.luau:696`: `if state.failNextDress then`
- the wall branch's `part.Transparency = 1` at `LevelService.luau:448`
- `src/combat/server/Services/WeaponService.luau:828`: `local restDrop = config.crowd.restDrop`

**What is wrong:** `source.l4w2` (run_harness.py `L4W2_LINES` / `L4W2_ORDER`) counts the `SetAttribute(CONST.DRESS...)` lines,
their order, and the `SeatDrop(...)` call. It does not count the guard that decides whether those lines run, nor the
inputs the calls read. This is the same family as the W1b findings ("the pins held the calls, not the condition between
them").

**Proof (each probe survives with `HARNESS: PASS (4,412 checks)`):**
- `:778` → `if false then`. The server hides all 66 blocks and the camps' floors, fences, obstacles and markers
  (Transparency 1, collision and query kept), but never says `Dress`. So no client ever draws a mesh, and the whole road,
  the cave and camp C's 64-stud wall become invisible solid ground and walls. This is exactly the brief's "a hidden Part
  with no mesh over it".
- `:714` → `return accepted, nil`. Same outcome: `planHash` is nil, so the word is never set.
- `:448` → `part.Transparency = 0`. The 70 tree-line walls, up to 280 studs tall and 8 thick, are drawn as grey slabs.
- `:828` → `local restDrop = 0`. L4W2-11 is undone on the server: every seated head is judged at its standing height
  while the client draws it 1.75 to 2.62 studs lower. The headshot complaint from L1b W2 returns on resting raiders.
- `:696` → `if true then`. Every level is built grey, in the live game too.
- `Build`'s `if layoutName ~= nil then` → `if false then`. The level is never dressed.
- `construct`'s `if dressed ~= nil then dressed.looks` → `if false`. The dress's looks are never laid.

No `mutate.py` entry names any of these lines. I grepped for each text and found 0 matches.

**Fix:** add whole-line pins (count 1, in the function named) for:
- the `:778` condition;
- `return accepted, hash` in `dressOf`;
- `if state.failNextDress then`;
- `if layoutName ~= nil then` in `Build`;
- `local restDrop = config.crowd.restDrop` in `gather`;
- a text pin of the `elseif isWall then` block through `part.CanCollide = true` (as `constructSkinnedWrites` does for the
  hidden branch).

Add matching `mutate.py` entries, each proven caught. Better still for `:778`: have `dressOf` return one value that
carries the hash (`accepted.planHash`), so "dressed but no hash" cannot be written.

### m2. A malformed dress throws out of `Build` instead of building grey: three of Accept's "never throws" guards are untested, and `dressOf` has no pcall

**Where:**
- `src/combat/server/Services/LevelDress.luau:198`: `type(hideBlocks) ~= "table"`
- `LevelDress.luau:212`: `type(hideCamps) ~= "table"`
- `LevelDress.luau:231`: `type(list) ~= "table"`
- `LevelService.luau:700`: `LevelDress.Accept(...)`, called bare from `Build`

**What is wrong:** L4W2-2 says any problem with the dress gives today's grey level with one warn. Accept is written to
refuse rather than throw, but each of those three guards survives `→ if false then` (`PASS 4,412`): no refusal case
supplies a `hide.blocks`, a `hide.camps` or a camp's role list that is not a table. The guards for `meshes`, `hide` and
`barriers` are covered: their probes throw inside the "refusals" group.

`dressOf` and `Build` call Accept outside any pcall. `place`'s pcall covers `construct` only.

**Failure scenario:** a generator change writes `"hide": {"blocks": null, ...}`, which reaches Luau as nil. With any one
of those guards dropped by a later edit, `for _, name in hideBlocks` throws inside `LevelService.Build`. `startLevel` has
already cleared the old level, so the start throws in the remote's thread. Forest Road cannot be started at all, the
leader gets no ActionResult, and nothing falls back to grey.

**Fix:**
1. Add the three cases to `L4W.refusalTests`:
   - `hide = { blocks = 5, camps = {} }`;
   - `hide = { blocks = {}, camps = "x" }`;
   - `hide = { blocks = {}, camps = { A = 5 } }`.
2. In `dressOf`, wrap the call: `local ok, accepted, reason = pcall(LevelDress.Accept, ...)`. Treat `not ok` as a refusal
   whose reason is the error, so "grey, one warn" holds by construction.

### m3. Hidden pieces no longer stop Roblox's default camera, which takes over for the 10 s summary in the level

**Where:**
- `LevelService.luau:497-501` (hidden piece: Transparency 1) and its comment "It still stops bodies, rays and the camera
  as built";
- `src/combat/client/Controllers/CameraController.luau:128` (`DEFAULT_CAMERA_PHASES = { summary = true, ended = true }`)
  and `:695-697` (deactivate in those phases and when Health ≤ 0).

**What is wrong:** the shoulder camera's spherecast hits a Transparency-1 Part, so in play the comment holds. In
`summary`, though, CameraController hands back to `CameraType.Custom`, and Poppercam treats a part as an occluder only
when `getTotalTransparency(part) < 0.25`. I read this in the installed PlayerModule:
`version-7aaa6838d36c4448/.../ZoomController/Popper.lua:197-208`. The mesh skins are CanCollide and CanQuery false, so
they never occlude either.

**Failure scenario:** the party stays in the level for `coop.returnGroupSeconds` (10 s) after a run ends, most often in
camp C after the Chief. The summary card is only 320 wide, so the world stays visible. Orbiting at zoom 16, the camera
now passes through camp C's 64-stud wall, the gatehouse, the cave roof and any skinned rock face, and shows the inside of
the meshes and the void behind. In the grey level these were opaque, collidable Parts that Poppercam stopped at. No
gameplay effect: the run is over.

**Fix (CameraController is in no W2 owner's list, so the lead routes it):** keep the shoulder camera's collision during
`summary` in a level that has `Dress` set. For example, stay Scriptable with the aim disabled, or run the same
`clearDistance` clip. Alternatively, cap `CameraMaxZoomDistance` near the minimum zoom in those phases. Correct the
LevelService comment to "the shoulder camera".

## Suggestions

### s1. A client whose scenery fails keeps 70 invisible tree-line walls with no trees in front of them

**Where:** `LevelService.luau:444-451` (walls armed from the build) and `src/combat/client/Controllers/LevelScenery.luau:279-283`
(the failed view shows only `Skinned` Parts).

The contract's undo (§2.3) restores the hidden Parts but not the walls. The server has accepted the dress, so the walls
hold, and on that client the grey level has invisible collision along every tree line and none of the trees. The
realistic trigger is rare: the server already checked that the templates exist, and a `Model:Clone()` does not fail. So
this is a suggestion.

**Fix:** in the failed branch of `applyView`, also `showWall` every child, so nothing collidable is invisible (ui A).

### s2. `templatesOf` counts a template as present by its Model's name alone

**Where:** `LevelService.luau:670-683`.

The template rbxmx ships its MeshParts with `MeshContent`. If an uploaded mesh asset is later moderated or fails to
load, the Model and its clone still exist: the server accepts, every client "builds", and that mesh's hidden Parts are
invisible solid with no undo. That is the one way a missing asset does not degrade to grey.

**Fix (cheap and partial):** require each template Model to hold at least one `MeshPart` with a non-empty mesh.
**Fix (fuller):** a one-time `ContentProvider:PreloadAsync` status check at server Start, whose failures feed
`haveMeshes`.

### s3. For areas, cones and blasts the body sphere stays standing while the head and the ray capsule sit

**Where:** `WeaponService.luau:839`, `gather`'s `body`.

L4W2-11 says "hit shapes sit with them". §5 lowers only the head and the capsule's top, and that is what was built. The
consequence: a cone, capsule, arc or blast still meets a seated brute up to 5.95 studs up, 1.07 studs above its drawn
seated head (4.88). For fodder the figures are 3.80 against 3.25. The cone's crit already uses the lowered head. This is
forgiving, not exploitable.

If Ben finds sprays "hitting over" sitting raiders, lower `body` by `drop / 2`, and lower the broad-phase pad with it.

## Checked and clean

- **Accept and the all-or-nothing fallback.**
  - The refusals come in the documented order and each names its reason.
  - `planHash` is held to `Assets.json levels.<layout>.planHash` (`23851a6f417491c1` in both).
  - Grey builds `pieces` alone: no walls, nothing hidden, no `Dress`. A dress is never accepted without the groups, so
    `construct`'s `not walls` skip can never drop a dress wall.
  - With the shipped data: 70 barriers, 0 name clashes with blocks, 252 + 70 Parts of 600.
  - Every hidden piece's role is block, floor, fence, obstacle, fire or tent, and none is reactive. Secrets, signs, ice,
    gates and checkpoints are separate roles that cannot be hidden. Camp piece names carry the camp id.
- **Walls collide for characters only.** They sit in `ArenaBarrier`, which collides only with `ArenaPlayers`.
  - Every server ray runs in the Default group and passes through them: `worldParams` in WeaponService and
    AbilityService, ThreatField, the floor probes, `aimAllowed`, and `dashEnd`.
  - The shoulder camera's spherecast and every client probe pass too.
  - No `OverlapParams` query exists in `src`.
  - Wall tops are 80-280 studs high.
- **`Dress` / `DressHash`.**
  - Both are set only after `state.built = true`, and only when accepted with a hash. `Build` and `Clear` nil both
    first.
  - `place`'s pcall leaves no hidden Part behind on a throw. `StreamingEnabled` is false in the combat place, so every
    client has every Part.
  - The client defers `evaluate`, so the two-attribute order is safe.
  - `startLevel`'s later failures call `Clear`.
- **The seat.**
  - `HitShapes.SeatStep` and `SeatDrop` are the same functions the client calls (`CrowdRenderer.luau:2336, :1994`).
  - The goal comes from the same `enemy.state` the wire and spawn info carry. Guards and patrols show `idle`, so they
    never sit.
  - `SpawnResident` seats a body first shown at rest. A dormant body holds its goal. Dead bodies are skipped.
  - Every hit path that reads a head goes through `gather`: ray and projectile via `rayCandidates`, the cone's crit, and
    abilities through `Strike` / `FireProjectile`.
  - The server's seat leads the drawn one by the snapshot delay, as positions do. Not a new gap.
- **`Plan.kinds` and `prewarm`.**
  - Counted as documented: residents by minDifficulty, every tent body, the largest single wave with countMult, the
    boss, and the boss's largest call (the Chief: `fodder` 12).
  - Set before `broadcast()` with no yield after `setFloors`, so the first RunState of the set carries it.
  - It rides only `if cellsWent`. `BuildRunState` never carries it, and the lobby gets nil.
- **The Castle Key.**
  - A key-only entry is a reward entry and pays (Valor 0, Timber 0, key).
  - The opened secret is the key, and nothing else is written.
  - `HasLevelKey` reads the level files and is held per level id.
  - `Validate` caps the key at `MAX_FAMILY_LENGTH`. Non-pay openings carry no key. `MapRow` names the key of the chest
    that gives it.
- **The `dressFail` lever.**
  - Both entry points are Studio-only: `OnRequest` and `Start` both return outside Studio.
  - It is spent by the first build that asks for a dress, and pinned (`dressFailSpent`, `failThenAccept`).
  - `RequestDebug` takes any short lever name.
- **Strictness and constants.** `--!strict` everywhere. No `wait`, `spawn`, `delay`, `_G` or parent argument in the diff.
  The new CONST names are infrastructure, and the numbers live in `ProvingGrounds.json` and `Combat.json`. Tuning refuses
  a negative `restDrop` or `riseBlendSeconds`.
- **Requires and boot.** No require cycle: DebugService → LevelService → WeaponService, and none of them requires
  DebugService. `Main.server.luau` boots an explicit list, so the pure `LevelDress` is never `Init`ed. Top-level locals
  are well under 180: LevelService about 49, WeaponService about 148.
- **Tests that bite.** Proven by scratch mutants that the harness catches (FAIL):
  - the Z lever not spent;
  - the hidden piece's shadow or query;
  - `state.looks` ignoring the dress;
  - prewarm on every RunState;
  - a wall given a camp;
  - walls hidden;
  - groupsOk ignored;
  - a piece-name clash;
  - `LeftOut` not passed;
  - tents counted per tent;
  - `idle` taken as a seat goal;
  - SeatDrop's easing.
- **Harmless survivors.** These probes also pass, but none changes behaviour on the shipped data: camp ids unsorted, a
  non-camp stage's waves, any attack with a `summon` field, dead bodies stepped, the seat stepped one crowd step early,
  an empty key, and the map row naming a key only once found.
