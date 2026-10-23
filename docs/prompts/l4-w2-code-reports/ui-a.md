# L4 W2 code wave: ui-engineer A (report, kept current)

Worktree `tycoon-p5`, branch `l4-w2`. Nothing committed. Started 2026-10-22.

## State

- [x] `src/combat/client/Controllers/LevelScenery.luau` (new: the dressed forest, mood B, keys Y and O) (contract 2.3, 2.4, 8)
- [x] `src/combat/client/Controllers/DrawClock.luau` (new, tiny: the per-frame draw time CrowdRenderer and LevelScenery add to)
- [x] `src/combat/client/Main.client.luau` (LevelScenery listed, before CombatUIController)
- [x] `src/combat/client/UI/CombatHud.luau` (Studio "Frame N ms" and "Draw N ms" beside "Server N ms") (8)
- [x] `src/combat/client/Controllers/SecretFx.luau` (the chest card's "Castle Key found" line) (0)
- [x] `src/client/UI/MapScreen.luau` (the key glyph on the map's secret row; the row's cells fit four secrets) (0)
- [x] gates on the real tree, now that ui B has landed the Theme block, the toast, DEBUG_HINT and DrawClock (see "Gates")

## What was built

- **LevelScenery** (`Controllers/LevelScenery.luau`, Init/Start, listed in `Main.client.luau` before
  CombatUIController). Watches `Workspace.Level` (found at Start for a late join, or on `Workspace.ChildAdded`; the range
  never has one, so it is inert there). On a change of `Dress`/`DressHash` (read together one `task.defer` later) it
  tears down and, when `Catalog.GetLevelDress(Dress)` exists with `planHash == DressHash` and `frame == "level"`, builds
  `Workspace.LevelScenery` in its own thread, `COMBAT_SCENERY_CLONES_PER_FRAME` jobs a frame: meshes by group (ground,
  skin, camp, rock, canopy, dress, backdrop, others), then props, then fires; a generation counter stops a stale build.
  Meshes are cloned and parented with no move, every BasePart anchored, CanCollide/CanQuery/CanTouch false. Props: Base
  as PrimaryPart, PivotTo(x, y, z, yaw), ScaleTo(scale) when not 1, Base destroyed, sealed; a missing piece = one warn.
  `with` props stand only while `Workspace.Level` has that child (ChildAdded raises them, ChildRemoved drops them).
  Fires: invisible Part + ParticleEmitter + PointLight, none on `Theme.lowEndDevice` (never gated on reducedMotion).
  **Fail path** (no templates folder, a missing mesh, a clone error, a hash or frame mismatch, Dress without DressHash):
  one warn (`[LevelScenery] the level is grey on this client: ...`), folder destroyed, mood restored, every `Skinned`
  child of `Workspace.Level` shown locally at Transparency 0 (also any that arrives later).
- **Mood B**: while dressed, `Expeditions.json moods[dress.level]` (lighting: clockTime, geographicLatitude, brightness,
  ambient, outdoorAmbient, exposureCompensation; atmosphere: density, offset, color, decay, glare, haze). Each property is
  recorded before its first write; an existing Atmosphere is restyled (recorded), else one is made and remembered.
  Restore writes back exactly the recorded properties and destroys only an Atmosphere it made. A bad value: one warn,
  left alone.
- **Keys (Studio only, local, kept for the session and across runs):** Y forest -> grey (scenery folder unparented,
  Skinned Parts shown) -> walls (forest, every `Workspace.Level` child whose CollisionGroup is not "Default" painted
  `COMBAT_SCENERY_WALL_COLOR` at `..._TRANSPARENCY`) -> forest. O mood <-> default light. Every local write on a server
  Part is recorded and put back on each change of view. Same filters as CombatUIController's `onKey` (processed, a
  focused TextBox). A toast says what each press did (`LevelScenery.SetToastHandler`, else `print`). Not dressed: "This
  level is not dressed".
- **Perf** (`CombatHud`): "Server 0.4 ms · Frame 16.7 ms · Draw 1.2 ms" in the one label (Studio, live phases). Frame =
  Heartbeat dt, Draw = `DrawClock.Take()` each frame, both p95 over `debug.perfLogSeconds`, kept in 1 s buckets (rolling).
  The server part still needs its attribute; the client parts show after the first second.
- **Chest card** (`SecretFx`): a gold row "Castle Key found" between the pay rows and the family note when the `found`
  event carries `key`; the name from `Expeditions.json keys[key].name`, else the id with a capital + " Key". The
  mountain's card is 4 rows (title, +4 Valor, +50 Timber, Castle Key found), shorter than the Lookout's (whose family note
  wraps to two lines), so it fits wherever that one already fits (c7 placement unchanged).
- **Map** (`MapScreen`): `MapSecretState.key` read loosely into `keyId`; a key glyph (ring + shaft + bit, Frames) right
  of the icon, gold when found, dim before. Forest Road's four secrets broke the even split (150 / 4 = 37.5 px cut the
  47 px "2x JUMP" word); cells now keep the old 50s when they fit, else each is its TextService-measured key word + 3 (at
  least icon + glyph = 42 for a key secret, at most 50), all scaled together only past the row's room.

## For the other owners

### ui-engineer B: `src/client/UI/Theme.luau` (every name my files read; none exists yet)

Paste as one block (anywhere in the table; I suggest after the `COMBAT_PERF_*` group), and change one value:

```luau
	-- L4 W2 (docs/prompts/l4-w2-contract.md 2.3, 8): LevelScenery, the dressed level on the client.
	-- Clones a frame while a level's scenery is built (meshes, then props, then fires).
	COMBAT_SCENERY_CLONES_PER_FRAME = 8,
	-- The prop kit under ReplicatedStorage.Assets.Props for each dressed layout (a dress `props`
	-- piece is <set>.<piece>); a layout not listed builds without props (one warn).
	COMBAT_SCENERY_PROP_SETS = { ForestRoad = "Forest" } :: { [string]: string },
	-- A dress `effects` fire: an invisible Part this big at the entry's point, with a flame
	-- emitter and a light. Not on a low-end device (the Campfire prop's modelled flames stay).
	COMBAT_SCENERY_FIRE_SIZE = Vector3.new(1.2, 0.4, 1.2),
	COMBAT_SCENERY_FIRE_RATE = 14,
	COMBAT_SCENERY_FIRE_LIFETIME_MIN = 0.5,
	COMBAT_SCENERY_FIRE_LIFETIME_MAX = 0.9,
	COMBAT_SCENERY_FIRE_SPEED_MIN = 2,
	COMBAT_SCENERY_FIRE_SPEED_MAX = 4,
	COMBAT_SCENERY_FIRE_SPREAD = 12, -- degrees off straight up
	COMBAT_SCENERY_FIRE_PARTICLE_SIZE = 0.9, -- studs at birth, shrinking to nothing
	COMBAT_SCENERY_FIRE_COLOR_HOT = Color3.fromRGB(255, 196, 92),
	COMBAT_SCENERY_FIRE_COLOR_COOL = Color3.fromRGB(230, 84, 24),
	COMBAT_SCENERY_FIRE_LIGHT_EMISSION = 1,
	COMBAT_SCENERY_FIRE_LIGHT_COLOR = Color3.fromRGB(255, 160, 72),
	COMBAT_SCENERY_FIRE_LIGHT_RANGE = 14,
	COMBAT_SCENERY_FIRE_LIGHT_BRIGHTNESS = 1.6,
	-- Studio's Y "walls" view: every invisible wall of the level drawn locally in this colour.
	COMBAT_SCENERY_WALL_COLOR = Color3.fromRGB(230, 40, 40),
	COMBAT_SCENERY_WALL_TRANSPARENCY = 0.55,
	-- L4 W2 (8): the perf line's Frame and Draw are p95s over debug.perfLogSeconds, kept in buckets
	-- this long, so the numbers roll once a step instead of jumping once a window.
	COMBAT_PERF_CLIENT_STEP_SECONDS = 1,
	-- L4 W2 (section 0): the level-key glyph beside a map secret's icon (a ring, a shaft and a bit
	-- drawn from Frames), this wide and half as tall. With its gap on both sides a key secret's
	-- cell is at least 16 + 2 x 13 = 42 design px, inside the 50 px cell.
	MAP_SECRET_KEY_GLYPH_WIDTH = 12,
```

Change: `COMBAT_PERF_WIDTH = 140,` → `COMBAT_PERF_WIDTH = 300,` (the line is now "Server 0.4 ms · Frame 16.7 ms · Draw
1.2 ms", about 275 px at 12 px Gotham; Studio only, a label over the bottom-left stack: 300 design px fits 375 x 667
from the margin and 1920 x 1080).

### ui-engineer B: `src/combat/client/Controllers/CombatUIController.luau`

1. **Toast for Y and O.** Beside `CombatFxController.SetToastHandler(...)` (same handler shape):
   ```luau
   LevelScenery.SetToastHandler(function(text: string)
   	toast.Show(text, Theme.TOAST_ERROR_SECONDS, false)
   end)
   ```
   with `local LevelScenery = require(script.Parent:WaitForChild("LevelScenery"))` at the top. Without it the lever
   lines go to the Output (`print`), nothing breaks.
2. **DEBUG_HINT** gains Y and O (they are bound inside LevelScenery, Studio only, with your `onKey`'s filters:
   `processed` and a focused TextBox). Add after your X and Z text: `" · Y scenery · O light"`.

### ui-engineer B: `src/combat/client/Controllers/CrowdRenderer.luau` (the "Draw N ms" line)

`DrawClock` (`src/combat/client/Controllers/DrawClock.luau`, mine) is a counter: `DrawClock.Add(seconds)` and
`DrawClock.Take()`. CombatHud takes it once a frame. Wrap your Heartbeat step:

```luau
local DrawClock = require(script.Parent:WaitForChild("DrawClock"))
...
-- old: table.insert(connections, RunService.Heartbeat:Connect(step))
table.insert(
	connections,
	RunService.Heartbeat:Connect(function(deltaTime: number)
		local started = os.clock()
		step(deltaTime)
		DrawClock.Add(os.clock() - started)
	end)
)
```

(or put the two `os.clock()` lines inside `step` if it has one exit). LevelScenery adds its build steps itself. If you
already measure your step another way, call `DrawClock.Add` with that number instead.

### luau-engineer A (what I read; matches your Types diff as of 2026-10-22)

- `Workspace.Level` attributes `Dress` (string, the layout) and `DressHash` (string, the plan hash), set **last** in
  Build, both nil **first** in Clear. LevelScenery reads them deferred (one `task.defer` after either changes), so the
  order between the two does not matter; a `Dress` without a `DressHash` is treated as "cannot dress" until the hash
  arrives (the Skinned Parts are shown meanwhile, so no collision is invisible).
- Every hidden piece: attribute `Skinned` = `true` (a boolean; anything else is not read as skinned), a **direct child**
  of `Workspace.Level`.
- Every invisible wall Part (the dress `treeline`s, camp C's `barrier`) is in `BarrierGroups.BARRIER`'s collision group.
  The Y "walls" view finds walls as direct children of `Workspace.Level` whose `CollisionGroup` is not `"Default"` (the
  client cannot require BarrierGroups); a wall built outside the group would not turn red there.
- `CombatFxSecret.key` (the key id) on the chest's `found` event; `MapSecretState.key` (the key id) in MapState.
  The client reads both loosely (a server without them shows no key line and no glyph).
- `Types.ExpeditionsConfig.keys[id].name` (SecretFx) and `.moods[levelId]` (`LevelMood`), keyed by the dress's `level`
  ("forestRoad"), as your Types diff has them.
- `Types.LevelDress`, `LevelDressMesh`, `LevelDressProp` (`with`), `LevelDressEffect`; `Catalog.GetLevelDress(layout)`.

### economy-designer D1

- `Expeditions.json keys.castle.name` is what the card prints ("Castle Key" + " found"); without it the card prints
  "Castle Key found" anyway (the id with a capital and " Key").
- `Expeditions.json moods.forestRoad` (the dress's `level`, not the layout name) with `lighting` and `atmosphere` blocks;
  each key optional. Colours are RGB 0-255 triples; a bad value is warned once and left alone.

### economy-designer D2 (pins, mutate entries)

- None of my files (`LevelScenery`, `DrawClock`, `Main.client`, `CombatHud`, `SecretFx`, `MapScreen`) is read by a
  harness pin or a `mutate.py` entry today (`grep` of `tools/` for each name: no match). No `SOURCES` change asked.
- The dress file fields LevelScenery reads: `level`, `layout`, `planHash`, `frame`, `meshes[].name/group`,
  `props[].piece/x/y/z/yaw/scale/with`, `effects[].kind/x/y/z`. Group build order: ground, skin, camp, rock, canopy,
  dress, backdrop, then any other group.

## Gates (mine, 2026-10-22)

- `stylua --check` and `selene` on my six files: clean (0 errors, 0 warnings).
- `luau-lsp analyze` on my six files against `sourcemap.combat.json`, and MapScreen against `sourcemap.json`, on the
  real tree after ui B's Theme block landed: **0 diagnostics** on both.
- `py tools/check_compile.py`: PASS, 181 files (top-level `local` lines: LevelScenery 58, CombatHud 36, SecretFx 47,
  MapScreen 48).
- The relays have landed in ui B's files: `LevelScenery.SetToastHandler` is wired (CombatUIController :1992),
  DEBUG_HINT has "Y forest/grey/walls · O light", and CrowdRenderer adds its step to `DrawClock` (:2681).
- `rojo build` of `combat.project.json` and `default.project.json` (into scratch): both built.
- Harness (`run_harness.py`; the shebang runs 3.12 64-bit): **FAIL 1 of 4,254**, "then the Colossus alone"
  (`tests_l1c.luau`, the boss rename in progress: D1's). The harness reads none of my files.
- `mutate.py`: no entry reads my files, so nothing to run filtered.

## Assumptions

- The client cannot require `BarrierGroups` (server), so the walls view treats a non-"Default" CollisionGroup in
  `Workspace.Level` as a wall; true today (BarrierGroups.BARRIER is the only other group a Level Part is ever put in).
- The prop set per layout is a Theme map (`COMBAT_SCENERY_PROP_SETS = { ForestRoad = "Forest" }`): nothing in config
  names it. A `propSet` field in the dress file (D2's generator, A's type) would be the cleaner home; the lead's call.
- The mood is keyed by the dress's `level` ("forestRoad"), as the contract's `moods.<levelId>`.
- The Y and O views persist for the session (a new run keeps grey, or the default light), so Ben can compare runs.
- The fire numbers are starting values: Ben's look tunes them.

## Read, not run (Studio only)

Local Transparency/Colour writes on replicated Parts; a client-made Atmosphere and client Lighting writes; the
ParticleEmitter and PointLight look; ScaleTo on the ChiefTent (1.25) and the Brambles (1.2-1.45); the clone pacing (68
jobs: 37 meshes + 23 props + 8 fires at 8 a frame = 9 frames); the key glyph's look at its size; TextService widths of
the map's key words.

## What to check in Studio (keys only)

1. Depart Forest Road on Normal: the forest appears within a few frames of the level, mood B (greyer, hazed), no
   `[LevelScenery]` warning in the Output, campfires burning in camps A, B and C (none at graphics quality 3 or less).
2. **Y** at the trailhead gap and in the lookout gully: forest -> grey (toast "Scenery: grey (the collision blocks)"; the
   blocks stand exactly where the meshes were) -> walls (red tree lines and yard walls, camp C's barrier) -> forest.
3. **O**: default light <-> the mood; the toast names which.
4. **F** (Flamethrower) on the cave's bramble: the bramble shrubs leave with the block. After a run that found the
   shortcut, the next run shows no bramble shrubs (H resets it).
5. **Z** then a new run: the level is grey (no scenery, default light), no client warning.
6. The mountain summit chest: the card reads "MOUNTAIN SUMMIT FOUND", "+4 Valor", "+50 Timber", "Castle Key found"
   (gold), above the crosshair. **M** in the lobby, Forest Road: four secret icons, the mountain's with a small key beside
   it, every word whole ("2x JUMP" not cut).
7. The perf line bottom-left in a fight: "Server ... · Frame ... · Draw ..."; read it at the Main Camp's west gate.
8. Device emulator 667 x 375 and 375 x 667: the map card's secrets row (four cells inside the card), the chest card clear
   of the screen edges, the perf line inside the screen; 1920 x 1080 the same, scaled.
