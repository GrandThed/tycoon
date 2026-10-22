# L4 W2 review, slice 2: the scenery client

Reviewer: roblox-reviewer, 2026-10-22. Diff `37ccfe4..afdce67`, restricted to `LevelScenery.luau` (new),
`DrawClock.luau` (new), `SecretFx.luau`, `Main.client.luau`, `CombatHud.luau`, `MapScreen.luau`, plus what they
read (`LevelService` Build/Clear/construct, `LevelDress.Accept`, `SecretFlow`, `WaveService.announceSecret`,
`CombatUIController`'s lever wiring, `CameraController`'s collision cast, the dress file, the templates). Read only.

**Count: 0 Critical, 0 Major, 4 Minor, 4 Suggestions.**

## Minor

### m1. A throw in the build thread outside the mesh pcall leaves every hidden Part invisible and solid

`src/combat/client/Controllers/LevelScenery.luau:613-647` (`jobsOf`), `:697-739` (`build`), `:778-784`
(`evaluate`).

- The undo covers one failure only: a mesh that has no template or whose clone errors (`runJob`'s pcall,
  `:657-671`).
- Everything else in the thread runs bare: `jobsOf` iterates `dress.props` and `dress.effects`, and `spawnFire`
  (`:514-548`) is not in a pcall. `evaluate` also runs `syncMood()` and `applyView()` bare after `state.dress` is set
  and before the thread starts.
- `LevelDress.Accept` (`LevelDress.luau:131-296`) checks `meshes`, `hide` and `barriers` but never `props` or
  `effects`. The server therefore accepts a file whose `props` or `effects` is absent, hides 60+ blocks and sets
  `Dress`.
- **Scenario:** a later level's generator writes no `effects` key for a level without fires.
  - On every client `jobsOf` throws "attempt to iterate over a nil value" before the first clone.
  - The thread dies without calling `fail`.
  - `state.dress` stays set and `state.failed` stays false, so nothing shows the `Skinned` Parts.
  - The result: an invisible road, invisible cave walls and invisible gatehouse walls, all solid, no scenery, and only
    the engine's own error in the Output.
  - The brief's rule is "a bad dress: grey level, one warn".
- **Fix:**
  - Run the whole thread body (from `jobsOf` to the `with` raise) under one `pcall` and call `fail(...)` on error, with
    the generation checked first. Do the same for the `syncMood`/`applyView` pair in `evaluate`.
  - Have `Accept` refuse a dress whose `props` or `effects` is not a list (A), so the server and the client degrade
    the same way.

### m2. A client that fails after the server accepted keeps 70 invisible walls standing in the open

`LevelScenery.luau:605-610` (`fail`) and `:279-284` (`applyView`'s failed branch).

- The client-side undo shows the `Skinned` Parts only (contract §2.3 says exactly that).
- But the server accepted, so the dress's 70 `treeline` walls stand: Transparency 1, collidable for characters
  (`LevelService.luau:444-451`).
- The server's own grey fallback has no walls at all. So the "grey on this client" level is not the grey level. It is
  the grey blocks plus invisible tree lines and yard walls, where the player sees open ground and no trees.
- **Scenario:** a late arrival hits m3's race and fails. That client then plays the whole run fenced by walls it
  cannot see: along the road edges, at the trailhead gap, and at the lookout gully.
- **Fix:**
  - In the failed branch, also give every `isWall` child a visible look: the walls view's `paint`, or a softer
    Theme colour. `paint` and `restorePainted` already record and restore that look.
  - Or record it in the contract as accepted.

### m3. The dress and mood lookups run before `game.Loaded`, so a client that starts early is grey for the whole run

`LevelScenery.luau:765` (`Catalog.GetLevelDress`), `:834` (`evaluate()` from `attachLevel`), `:887-890` (`Start`).

- `build` waits for `game.Loaded` because "the templates are replicated with the place" (`:698-700`).
- `evaluate`, however, reads `Catalog.GetLevelDress(name)` at once: from `Start` when `Workspace.Level` already
  carries `Dress`, or from the first `ChildAdded`.
- `Catalog.GetLevelDress` is a `FindFirstChild` (`Catalog.luau:577-590`) that answers nil until the module has
  replicated.
- On nil, `evaluate` calls `fail("Config/LevelDress/... is missing")` and stores `builtKey`. The same key never
  evaluates again, so that client is grey (with m2's walls) until the next run's Clear.
- **Who meets it:**
  - Anyone whose client boots while a level stands: a party member whose teleport lands after the leader departed
    (a waiting member), or a rejoin.
  - Possibly proving.rbxl, whose server auto-starts the level as the player arrives.
  - `Main.client.luau` starts every controller without waiting for `game.Loaded`.
- I did not prove that the ordering happens. The point is that the module already guards the same race for the
  templates and not for the config.
- **Fix:** in `evaluate`, when `not game:IsLoaded()`, set no `builtKey`. Instead `task.spawn` a
  `game.Loaded:Wait()` then `evaluate()`, behind a generation check. Or move the Catalog reads into the build thread
  after its wait.

### m4. Mood B applies to members waiting in the lobby camp

`LevelScenery.luau:439-446` (`syncMood`).

- The mood follows `Dress` alone ("applied while dressed", contract §2.4). The brief asks for it "never in the
  lobby".
- During a run, `ArenaService.placeBody` (`:995-1003`) puts a late or respawned body in the lobby camp as `waiting`
  until the next boundary. A camp clear can be minutes away.
- That player's Lighting carries the forest's brightness, ambient and haze over the lobby camp the whole time.
- After `backToLobby` the mood goes, because Clear drops `Dress`. That part is right.
- **Fix:** a lead ruling. Either accept it and write "the lobby keeps its light when no level stands" into the
  contract, or gate the mood on the local root being outside the lobby box (`Workspace.Lobby`'s bounds, as
  `StageFlow.OutOfBox` reads them) and re-sync it on the existing `Placed` attribute.

## Suggestions

- **s1. The client half of the dress protocol has no gate.**
  - Only the server half is pinned: `run_harness.py:1715-1734` (`buildDressHash`, `clearNilDress`, ...).
  - No harness test, pin or mutate entry reads `LevelScenery`, `DrawClock`, `SecretFx`, `CombatHud` or `MapScreen`
    (grep of `tools/`).
  - So each of these passes every gate: `evaluate` building without the hash compare, `fail` not showing the
    `Skinned` Parts, `seal` leaving `CanCollide` on, a missing generation check after `task.wait()`.
  - This is the same gap W1b's CombatUIController had.
  - Suggest a pure `ScenePlan`, a decision `(dressAttr, hashAttr, dress) -> "none" | "build" | reason` plus the job
    order, tested under the harness, with line pins on `fail`'s `showSkinned` path and `seal`'s four flags.
- **s2. `LevelService.Build` sets `Dress` before `DressHash` (`LevelService.luau:778-781`).**
  - A client that evaluates between the two (`evaluate` defers one frame, but the order of resumption against
    replication is the engine's) warns "Dress ... but no DressHash" and shows the grey blocks for a frame, then
    rebuilds.
  - That warning is exactly what ui-a's Studio step 1 asks Ben to look for.
  - Setting `DressHash` first makes the transient impossible on the build path. Clear's order (Dress nil first) is
    already right.
- **s3. The text arithmetic on phones is tighter than the comments say.**
  - Roblox's local fonts have no GothamSSm family: `GothamBold` renders as Montserrat Bold. Measured with Pillow at
    em = TextSize:
    - "MOUNTAIN SUMMIT FOUND" at 20 is 292.6 px, against the card's 276 inner width;
    - "2× JUMP" at 11 is 49.2 px (`MapScreen.luau:54` says about 47).
  - If TextSize is the em, two things follow.
    - The map's four cells sum to about 151 of 150 and all scale down, leaving "2× JUMP" 0.47 px of room before
      `TextTruncate` cuts it.
    - The mountain title wraps, which makes its card 139 design px against the Lookout's 128. At 667×375 with a
      36 px inset it clamps at the top margin, and its bottom meets the reticle's top tick.
  - If TextSize is the line height (Montserrat's ascent plus descent is 1.23 em), both fit easily.
  - ui-a's emulator step 8 settles it. For slack whatever the model:
    - in `secretWidths`, shrink cells toward their own word widths before scaling words;
    - fit the card title (`TextScaled` with a max of `SECRET_CARD_TITLE_TEXT`).
- **s4. The prop set per layout lives in Theme (`COMBAT_SCENERY_PROP_SETS`).**
  - So a second dressed level needs a client Theme edit, or it silently draws no props (one warn).
  - ui-a flagged it already. A `propSet` field in the dress file (D2's generator, A's type) keeps the level's data in
    one file.
  - Related: the key glyph is 12 × 6 design px (about 11 × 5.5 at MIN_SCALE). Worth a look on a real phone before it
    is called readable.

## Checked and clean

- **The server's word:**
  - The dress is built only when `Dress` is a string, `DressHash` a string, `Catalog.GetLevelDress(Dress)` exists, its
    `planHash` equals `DressHash` and its `frame` is "level" (`:742-777`).
  - `Dress` nil tears everything down and restores the mood.
  - `Workspace.Level` is one persistent Folder (`LevelService` clears children only), so `attachLevel` runs once.
- **Clear then Build in one server frame, same key:**
  - `evaluate` returns early and the local scenery stays, which is correct: it depends on no server Part.
  - Bramble props are dropped or kept by `dropWith`'s "another child of that name" check, correct under both signal
    modes and with the cave shortcut found in between.
  - Painted entries for destroyed Parts are cleared by `ChildRemoved`.
- **Generation counter:**
  - Checked after `game.Loaded:Wait()` and after every `task.wait()`. No yield sits between a check and `fail`,
    `built = true` or the `with` raise.
  - `Detach` and each new key bump it.
- **Per-frame budget:**
  - `COMBAT_SCENERY_CLONES_PER_FRAME` 8 jobs a frame (37 meshes + 23 props + 8 fires = 9 frames), in the contract's
    group order (ground, skin, camp, rock first; stable within a group).
  - Nothing of LevelScenery runs per frame after the build. The `with` raise (12 brambles) is unbudgeted and trivial.
- **Scenery flags:**
  - `seal` sets Anchored, and CanCollide, CanQuery and CanTouch false on every BasePart of meshes and props.
  - The templates already ship `CollisionFidelity` Box and no collision.
  - The combat camera's `Spherecast` (Exclude characters, Default group) still hits the hidden blocks. Transparency
    does not matter to it, so the walled-camp sight rules hold with the blocks invisible.
- **Undo on a mesh failure:**
  - The folder is destroyed and every `Skinned` direct child is painted Transparency 0. Later arrivals are painted too
    (`onLevelChildAdded`).
  - The server sets `Skinned` before parenting (`LevelService.luau:497-503`), so `ChildAdded` sees it.
  - The props over hidden pieces (Campfire, SpawnTent over `fire`/`tent` markers) cover only `collide = false`
    markers (`LevelGeometry.luau:1001-1030`), so a missing prop hides no collision. The bramble block is in
    `hide.keep`.
- **Props:**
  - Base as PrimaryPart, `PivotTo` then `ScaleTo` about the Base, Base destroyed, all in a pcall with one warn.
  - The templates have a single `Stage0` and an identity Base (turn compensated in the mesh), which matches
    PropFactory's convention.
- **Bramble `with`:**
  - Block names are the layout names (`LevelGeometry.luau:874`).
  - A burn destroys the Part (`LevelService.luau:954`), so `ChildRemoved` drops the shrubs.
  - A found shortcut never builds the block, so no shrubs stand.
- **Fires:** none on `Theme.lowEndDevice`, never gated on `reducedMotion`. `StreamingEnabled` is false in the combat
  place, so no stream-out ChildRemoved churn.
- **Mood B:**
  - Each Lighting or Atmosphere property is saved before its first write and written back exactly.
  - An existing Atmosphere is restyled and restored; only a made one is destroyed.
  - It is restored on Clear, on a fail and by O.
  - Nothing else in `src/combat` touches Lighting. LevelScenery is not in any hub tree (`StarterPlayerScripts` of
    the combat project only), so it never runs in the hub.
- **Levers:**
  - Y and O are bound only under `RunService:IsStudio()` with the `processed`/focused-TextBox filters.
  - Every local write (Transparency, Color, Material) is recorded once and restored on each view change and on
    teardown.
  - Y and O collide with no DEBUG_KEYS entry. Z is in CombatUIController's Studio-only `DEBUG_KEYS` path.
  - CollisionGroup replicates, so the walls view finds the `treeline` walls and camp C's barrier.
- **Castle Key client side:**
  - `CombatFxSecret.key` flows from `SecretFlow.Open` through `announceSecret` to `SecretFx.OnFx`. A key-only chest
    pays (`rewardOf`).
  - The card's key row is read loosely and hidden on the shortcut card. `MapSecretState.key` comes from
    `SecretFlow.MapRow`.
  - The glyph's visibility and colours are reset per mark on reused cells. It sits inside a 42+ px cell beside the icon
    and clear of the word.
- **Perf line:**
  - Studio only, and only with `debug.perfLogSeconds`.
  - One HUD, so `DrawClock.Take` has one taker. A 10 s window sorts about 600 samples twice a second.
  - The p95 index is clamped. `DrawClock.Add` drops NaN and negatives.
  - Outside Studio the sum only grows, never read.
- **Code rules:**
  - `--!strict` in all six files.
  - No `wait`/`spawn`/`delay` (`task.*`, `game.Loaded:Wait()`).
  - No parent argument in `Instance.new`.
  - Tunables are in Theme. Infrastructure names are local, as in SecretFx.
- **Gates run on afdce67:**
  - `stylua --check` clean.
  - `selene`: 0 errors, 0 warnings.
  - `luau-lsp analyze` on the six files against a fresh combat sourcemap: 0 diagnostics.
  - ui-a's `check_compile` counts: LevelScenery 58, CombatHud 36, SecretFx 47, MapScreen 48.
