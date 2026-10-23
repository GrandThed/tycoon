# L4 W2 fix round: ui-engineer A (report)

Worktree `tycoon-p5`, branch `l4-w2`. Nothing committed. Rulings K7 (client half), K8, K9 of
`docs/prompts/l4-w2-fix-round.md`; findings slice 2 m1-m4 and s1, slice 1 m3 and s1.

## Files

- `src/combat/client/Controllers/ScenePlan.luau` (new, pure): Key, Decide, Jobs, Show, Mood, Box, InBox, Rgb,
  WallColor. No Instance, no service.
- `src/combat/client/Controllers/LevelScenery.luau`: acts on ScenePlan's answers. Fail path under one pcall,
  grey walls, game.Loaded, K8 mood gate, K9 push.
- `src/combat/client/Controllers/CameraController.luau`: K9. `SetDressed`, and the shoulder camera stays up in
  summary and ended while the level is dressed.
- `tools/crowd_harness/tests_l4w2_scenery.luau` (new): 85 checks. D2 must register it (see below).

## What was built

**K7, the fail path.**
- **One pcall for the build.** `build` runs the whole of `buildSteps` under one pcall: the templates lookup,
  `ScenePlan.Jobs`, every job, the `with` raise and the fires. A throw calls
  `fail("the build stopped (...)")`, but only when the generation is still its own.
- **One pcall for the start.** `start` (the old tail of `evaluate`) puts `syncMood` and `applyView` under
  their own pcall, which ends in `fail`.
- **What a failed client shows.** `fail` warns once, tears down, sets `failed` and applies the view.
  `ScenePlan.Show(dressed, failed, view)` decides every local write:
  - Failed: every `Skinned` Part is shown, and every wall is drawn. A wall is any `Workspace.Level` child
    outside the Default collision group: the dress's tree lines and camp C's `Barrier_C_*`.
  - The walls take the grey level's wall look, `Expeditions.json looks.wall` (84, 86, 92) through
    `ScenePlan.WallColor`, at `Theme.COMBAT_SCENERY_WALL_TRANSPARENCY` (0.55). No wall a player can bump
    into is ever invisible.
  - Later arrivals are painted the same way through `onLevelChildAdded`, which uses the same `showChild`.
  - Studio's Y grey view is now exactly this picture. Its toast reads "Scenery: grey (blocks shown, walls
    drawn: what a failed client sees)".
- **`ScenePlan.Decide(dress, hash, game:IsLoaded(), Catalog.GetLevelDress)`.**
  - "wait" before `game.Loaded`: the file is never looked up, and the answer is not kept. One `awaitLoaded`
    thread waits for `game.Loaded`, then calls `evaluate` again.
  - "none" when there is no Dress.
  - "fail" for Dress without DressHash, a missing file, another plan hash, a frame other than "level", or a
    `meshes`/`props`/`effects` that is not a list.
  - "build" otherwise.
  - **A nil answer is never kept** (no hash, missing file). `state.builtKey` is now `string?`, and nil means
    "read the next word anew".
- **Jobs.** The old `jobsOf` moved unchanged into `ScenePlan.Jobs(dress, lowEnd)`.

**K8, mood B only in the level.**
- The rule: `ScenePlan.Mood(dressed, failed, wanted, inLobby)`. The mood is on only when the level is
  dressed, this client did not fail, O wants it, and the body is not in the lobby camp.
- **Where the body is.** `CameraController.OnPlaced(onPlaced)` gives the server's `Placed` point, or the root
  for a body the camera has just picked up. Until any placement has been heard, the root as it stands.
- **The lobby box.** `Workspace.Lobby`'s BaseParts, as flat footprints that also hold for turned parts,
  grown by `Combat.json levels.boxMargin` (40). That is the server's own margin for "in the lobby" in
  `StageFlow.Rescue`.
- **Re-checks.** On every placement (under a pcall, because it runs in the camera's render step), on every
  dress change, and on O.
- `applyMood` is idempotent per level. A placement often asks again without any flicker or a new
  Atmosphere.
- **O in the lobby camp** answers "Light: the level's mood (in the level; the lobby keeps its light)".

**K9, the camera through the summary.**
- `LevelScenery.evaluate` calls `CameraController.SetDressed(typeof(name) == "string")` on every change of
  the server's word. `Detach` calls `SetDressed(false)`.
- In `update`, `phaseEndsCamera` gains `and not levelDressed`. So in a dressed level the shoulder camera
  (whose spherecast stops at the hidden Parts) stays up through summary and ended.
- The summary keeps its free cursor through `camera.freeCursorPhases`. The right mouse button, touch drag and
  the right stick still turn the view.
- A dead rig still hands back to the default camera, as before. A downed body has Health above 0, so it keeps
  the shoulder camera.
- In grey levels and in the range nothing changes.

**The relay from luau-engineer A, checked.** `DressHash` is now set before `Dress`, which matches my comments
and `Decide`. `Accept` refuses props and effects that are not lists, and my "server" group proves it (see the
harness section below). On `LevelDress.Present`, I did **not** mirror it on the client:
- the server judges the same replicated template Instances the client clones, and a refusal there means no
  `Dress` word;
- a client copy would add no case;
- a moderated mesh keeps its MeshId, so neither copy would catch that.

## For the other owners

### D2: `tools/crowd_harness/run_harness.py` (yours this round)

SOURCES. Old:
```
    "LevelDress": "src/combat/server/Services/LevelDress.luau",
}
```
New:
```
    "LevelDress": "src/combat/server/Services/LevelDress.luau",
    # The L4 W2 fix round's K7 and K8: what the client's LevelScenery decides, pure
    # (tests_l4w2_scenery.luau).
    "ScenePlan": "src/combat/client/Controllers/ScenePlan.luau",
}
```
TESTS. Old:
```
    "tests_l4w2.luau",
]
```
New:
```
    "tests_l4w2.luau",
    # The L4 W2 fix round: the scenery's decisions on the client (ScenePlan; ui-engineer A's).
    "tests_l4w2_scenery.luau",
]
```
- My file ends with the verdict line, so it must stay last in TESTS, or the verdict is stripped like any
  other file's.
- It adds one top-level local (`L4S`).
- It loads `ScenePlan` and `LevelDress`, and reads `FIXTURES.levelDress`, `levelHashes`, `layouts`,
  `combat` and `expeditions`.

**Pins on LevelScenery.luau**: whole lines with their indentation (tabs), each counted in the function named.
Each comes with a mutant the pin must catch. The text is final.

The four `seal` flags (in `seal`, its nested `flags`; 2 tabs; count 1 each in the file, because `spawnFire`'s
lines have 1 tab):
```
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
```
Mutants: each value flipped (`= false` / `= true`).

The fail path, in `fail`, in this order:
```
	warnOnce(`the level is grey on this client: {reason}`)
	teardown()
	state.failed = true
	applyView()
```
Mutants: delete `state.failed = true` (the view then writes nothing and every hidden Part stays invisible),
`state.failed = false`, delete `applyView()`.

What the failed view writes, in `showChild`:
```
	if show.skinned and isSkinned(child) then
		paint(child :: BasePart, 0, nil)
	if show.walls ~= "none" and isWall(child) then
		local color = if show.walls == "debug" then Theme.COMBAT_SCENERY_WALL_COLOR else greyColor
		paint(child :: BasePart, Theme.COMBAT_SCENERY_WALL_TRANSPARENCY, color)
```
Mutants: `paint(child :: BasePart, 1, nil)`, `if false and isWall(child) then`.

In `applyView` (the Show line also appears once in `onLevelChildAdded`, so it counts 2 in the file):
```
	local show = ScenePlan.Show(state.dress ~= nil, state.failed, state.view)
		folder.Parent = if show.folder then Workspace else nil
		showChild(show, child, greyColor)
```
In `onLevelChildAdded`:
```
	showChild(show, child, if show.walls == "grey" then greyWallColor() else nil)
```
Mutants: `state.failed` replaced by `false` in either Show line; delete either `showChild` line.

The build's pcall, in `build`:
```
	local ok, problem = pcall(function()
		buildSteps(generation, dress, folder)
	if not ok and generation == state.generation then
		fail(`the build stopped ({tostring(problem)})`)
```
In `start`:
```
		fail(`the scenery could not start ({tostring(problem)})`)
	task.spawn(build, state.generation, dress, folder)
```
- Pin `task.spawn(buildSteps` at count 0 in the file.
- Mutants: `if false then` for the `not ok` line, and `task.spawn(buildSteps, state.generation, dress,
  folder)`, which skips the pcall.

The word's decision, in `evaluate`:
```
	CameraController.SetDressed(typeof(name) == "string")
	local decision = ScenePlan.Decide(name, hash, game:IsLoaded(), Catalog.GetLevelDress)
	state.builtKey = if decision.keep then key else nil
	if decision.action == "build" and dress ~= nil then
	elseif decision.action == "fail" then
		fail(decision.reason or "the dress cannot be drawn")
			awaitLoaded()
```
Mutants: `game:IsLoaded()` replaced by `true` (m3 returns), `then key else key`, delete `awaitLoaded()`,
`SetDressed(false)`.

In `awaitLoaded`:
```
		if not game:IsLoaded() then
			game.Loaded:Wait()
		evaluate()
```
In `buildSteps`:
```
	for _, job in ScenePlan.Jobs(dress, Theme.lowEndDevice) do
```
Mutant: `Theme.lowEndDevice` replaced by `false` (fires on low-end devices).

K8. In `syncMood`, in `onPlaced`, in `inLobbyAt` and in `Start`:
```
		and ScenePlan.Mood(dress ~= nil, state.failed, state.moodWanted, bodyInLobby())
	state.inLobby = inLobbyAt(position)
	return ScenePlan.InBox(ScenePlan.Box(feet), point.X, point.Z, boxMargin())
	CameraController.OnPlaced(onPlaced)
```
Mutants: `bodyInLobby()` replaced by `false`; `boxMargin()` replaced by `0`; delete the `OnPlaced` line.

In `Detach`:
```
	CameraController.SetDressed(false)
```

**Pins on CameraController.luau.** In `update` (stylua splits the condition over three lines):
```
	local phaseEndsCamera = not rangeMode
		and DEFAULT_CAMERA_PHASES[phase] == true
		and not levelDressed
```
In `SetDressed`:
```
	levelDressed = dressed
```
Mutants: delete `and not levelDressed`, and `levelDressed = false` in SetDressed.

**mutate.py entries for ScenePlan**, each caught by hand on a scratch copy against my test file, with the
failing check named:
1. `if not loaded then` to `if false then`: "before the place has loaded it waits".
2. The missing file's `keep = false` to `true`: "the nil answer is never kept".
3. The failed Show's `walls = "grey"` to `"none"`: 7 Show checks fail.
4. The grey view's `walls = "grey"` to `"none"`: "Studio's grey view is what a failed client sees".
5. `and not inLobby` dropped: the Mood checks.
6. `if not lowEnd then` to `if true then`: the Jobs low-end check.
7. to 10. Each of the four `margin` terms of `InBox` dropped: "the margin grows every side". This needed
   the test strengthened: the `minX` mutant survived the first version.
11. `if read.planHash ~= hash then` to `if false then`.
12. `if not isList(read[field]) then` to `if false then`.
13. `if read.frame ~= ScenePlan.FRAME then` to `if false then`.
14. `Key` without the hash.
15. `Rgb`'s range check dropped.
16. The group sort reversed (`ra > rb`).
17. The none answer's `keep = true` to `false`.

### ui-engineer B: `src/client/UI/Theme.luau` (optional, comment only)

No new constant is needed. The failed view reuses `COMBAT_SCENERY_WALL_TRANSPARENCY`, and its colour comes
from config (`looks.wall`). If you want the comment to say so, replace:
```
	-- Studio's Y "walls" view: every invisible wall of the level drawn locally in this colour.
	COMBAT_SCENERY_WALL_COLOR = Color3.fromRGB(230, 40, 40),
	COMBAT_SCENERY_WALL_TRANSPARENCY = 0.55,
```
with:
```
	-- Studio's Y "walls" view: every invisible wall of the level drawn locally in this colour.
	COMBAT_SCENERY_WALL_COLOR = Color3.fromRGB(230, 40, 40),
	-- How see-through a drawn invisible wall is: in the Y walls view, and (K7) on a client that
	-- cannot dress the level, which draws every wall in Expeditions.json's wall look.
	COMBAT_SCENERY_WALL_TRANSPARENCY = 0.55,
```
- Your toast already wraps (`TextWrapped`, `AutomaticSize` Y). The two longer lever texts (grey view, O in
  the lobby) need nothing.
- DEBUG_HINT is unchanged ("Y forest/grey/walls · O light" still holds).

### luau-engineer A

Nothing owed. Your `DressHash`-first order, your props/effects refusal and the LevelService comment ("the
shoulder camera") are in, and my tests read them.

### The lead

`ScenePlan.Decide`'s list checks stop at "is a list". The entries are Accept's to refuse, and an entry the
build cannot read throws inside the pcall, which leaves the level grey. The test's "server" group holds Accept
to refusing every non-list. With HEAD's LevelDress those 2 checks fail, which is the review's m1; with A's
change they pass.

## Gates (2026-10-22)

- **stylua `--check`**: clean on all four files.
- **selene**: 0 errors and 0 warnings on the three source files.
  - On the test file it reports 78 `undefined_variable` errors, all for the bundle's shared names (`check`,
    `load`, `FIXTURES`, `failures`). That is the same as every case file: `tests_l4w2.luau` gives 215.
- **luau-lsp**, combat sourcemap (written to my scratch): 0 diagnostics on the whole of
  `src/combat/client`.
  - The hub sourcemap does not map these combat-only files. It gives "unknown require" there, as it already
    did for CameraController on the base.
- **`py tools/check_compile.py`**: PASS, 182 files. Top-level `local` lines: LevelScenery 67, CameraController
  100, ScenePlan 5.
- **`rojo build`** of `combat.project.json` and `default.project.json` into scratch: both built.
- **Line endings**: all four files are LF.
- **Harness** (shebang Python 3.12), run on a scratch copy of the worktree with the two lines above added
  (the worktree's `run_harness.py` is untouched):
  - My file: 85 of 85 ok.
  - Whole bundle: **FAIL 18 of 4,557**. All 18 are `source.l4w2` pins on LevelService (`buildDress`,
    `dressAccept`, `dressThenHash`, ...) that A's finished change moved. Those are D2's to re-aim.
  - With A's files put back to HEAD, only my 2 "server" checks fail.
- **Layouts**: no GUI changed, so 375×667, 667×375 and 1920×1080 are as before. The only text change is two
  Studio-only toast strings, which wrap.

## Assumptions

- "In the level" (K8) means "not in the lobby camp's box". A body never heard of and with no root counts as
  in the level.
- K9 follows the server's word (`Dress` set), not whether this client built the scenery. A failed client
  shows the hidden Parts, so either works; the word also covers the build's first frames.
- The failed view draws camp C's barrier boxes too, because they are walls outside the Default group. Only
  their top shows above the 64-stud fence, and the alternative was to tell them apart from tree lines by name.

## What to check in Studio (keys only)

1. **Depart Forest Road on Normal.** The forest and mood B show, with no `[LevelScenery]` warning.
2. **K9.** End a run in camp C (N to step forward, or Backspace twice to abandon). During the 10 s summary,
   hold the right mouse button and swing the view into the 64-stud wall and the gatehouse. The camera must
   stop at the wall and never show the inside of the meshes or the void. The cursor is free for the summary
   card. In a grey level (after Z) the summary uses Roblox's camera, as before.
3. **K7.** Press Z, then start a new run: grey level, default light. Then trigger a client-side failure:
   - Simplest: in the command bar of the client view, rename `ReplicatedStorage.Assets.Levels.ForestRoad.<any
     mesh>` before departing.
   - Expect one `[LevelScenery] the level is grey on this client: ...` warning.
   - Every block shows. The tree lines and yard walls show as translucent dark-grey slabs where you bump into
     them.
4. **Y.** forest, then grey (the same slabs as step 3, toast "blocks shown, walls drawn"), then walls (red),
   then forest.
5. **K8** (Test, Clients and Servers, 2 players):
   - Player 1 departs.
   - Player 2 joins mid-run and waits in the lobby camp: default light there.
   - At the next camp clear player 2 enters the level: mood B.
   - Back in the lobby after the run: default light for both.
   - O while waiting in the lobby toasts "(in the level; the lobby keeps its light)".
6. **Mobile emulator at 667×375 and 375×667.** No layout changed. During a dressed summary, a drag on the right
   half turns the view and the summary card stays usable.
