# L4 W2 fix round 2: ui-engineer A (report)

Worktree `tycoon-p5`, branch `l4-w2`. Nothing committed. Ruling L3 of `docs/prompts/l4-w2-fix2.md` (the fix-diff
review's s2), plus my final lines for L4's LevelScenery probes (m1).

## Files

- `src/combat/client/Controllers/ScenePlan.luau`: `RUN_OVER` (the run-over phases) and `Crosshair`, both pure.
- `src/combat/client/Controllers/CameraController.luau`: requires ScenePlan. `DEFAULT_CAMERA_PHASES` is now
  `ScenePlan.RUN_OVER` (the same two phases, one list). New `CameraController.ShowsCrosshair()`.
- `src/combat/client/Controllers/FeedbackController.luau`: one argument and one comment in `updateCrosshair`.
  **For ui-engineer B:** this is the file that shows or hides the crosshair. It is not `CombatUIController.luau`,
  which I did not touch.
- `tools/crowd_harness/tests_l4w2_scenery.luau`: a `crosshair` group with 12 checks, plus one header line.
- Not changed: `LevelScenery.luau` and `Crosshair.luau`. Crosshair stays pure display; its `visible` argument
  already hides the whole reticle.

## What was built (L3)

- **The rule.** `ScenePlan.Crosshair(cameraUp, phase, range)` returns
  `cameraUp and (range or ScenePlan.RUN_OVER[phase] ~= true)`. The crosshair needs the shoulder camera up, and it
  never shows in `summary` or `ended`.
- **Why it works without a dressed flag.** In a grey level the camera is already down in those phases, so the
  answer is the same. In a dressed level, K9 keeps the camera up and the crosshair now hides anyway. The range
  bench has no run phase, so the camera alone decides there, as `phaseEndsCamera` does.
- **What K9 keeps.** `CameraController.ShowsCrosshair()` returns `ScenePlan.Crosshair(active, phase, rangeMode)`.
  `FeedbackController.updateCrosshair` passes it as `marker.Update`'s `visible`, where it used to pass `IsActive()`.
  `IsActive` is unchanged, and so is `phaseEndsCamera`: the shoulder camera still stays up through a dressed
  summary.
- **One list.** The camera's phases and the crosshair's phases are now one table. A mutant on `RUN_OVER` therefore
  fails the pure tests and also moves the camera.
- **The Alt hint.** `CombatHud`'s `altHint` reads `IsActive()` through `SetAiming`, but it is already gated on
  `fighting`. Nothing else draws from `IsActive` in summary.

## For the other owners

### D2: pins (L4) and mutate entries

All text is final. Tabs are real tabs; the counts are for the whole file.

**ScenePlan.luau** (pure, loaded by the harness). These 9 mutate entries were each applied alone on a scratch copy
(src, the harness folder, `tools/*.py`, the project files) whose baseline was `HARNESS: PASS (4,668)`. Every one
was caught; the failing checks are named.

| # | Old | New | Fails |
|---|---|---|---|
| 1 | `\treturn cameraUp and (range or ScenePlan.RUN_OVER[phase] ~= true)` | `\treturn cameraUp` | "Crosshair: none in summary/ended though the dressed level keeps the camera up (K9)" (2) |
| 2 | same | `\treturn cameraUp and (true or ScenePlan.RUN_OVER[phase] ~= true)` | same 2 |
| 3 | same | `\treturn cameraUp and (range and ScenePlan.RUN_OVER[phase] ~= true)` | "shown in every phase before the run is over", "the range bench has no run phase" (3) |
| 4 | same | `\treturn true and (range or ScenePlan.RUN_OVER[phase] ~= true)` | "never without the shoulder camera", the range bench (3) |
| 5 | same | `\treturn cameraUp and (range or ScenePlan.RUN_OVER[phase] == true)` | "shown in every phase…", the K9 pair (3) |
| 6 | same | `\treturn cameraUp and (not range or ScenePlan.RUN_OVER[phase] ~= true)` | the K9 pair, the range pair (4) |
| 7 | `ScenePlan.RUN_OVER = { summary = true, ended = true } :: { [string]: boolean }` | `ScenePlan.RUN_OVER = { summary = true } :: { [string]: boolean }` | "RUN_OVER: the summary and ended, nothing else", "none in ended…" (2) |
| 8 | same | `ScenePlan.RUN_OVER = { ended = true } :: { [string]: boolean }` | "RUN_OVER: the summary and ended…", "none in summary…" (2) |
| 9 | same | `ScenePlan.RUN_OVER = { summary = true, ended = true, wave = true } :: { [string]: boolean }` | `RUN_OVER: "wave" is a run that is over`, "…nothing else", "shown in every phase…" (3) |

**CameraController.luau.** No pure test can reach these lines. Each mutant below passed today's harness on the
copy (`PASS (4,668)`), so each needs a pin:
```
local ScenePlan = require(script.Parent:WaitForChild("ScenePlan"))
local DEFAULT_CAMERA_PHASES: { [string]: boolean } = ScenePlan.RUN_OVER
```
(count 1 each, top level). In `CameraController.ShowsCrosshair`:
```
	return ScenePlan.Crosshair(active, phase, rangeMode)
```
(count 1). Mutants:
- `\treturn ScenePlan.Crosshair(active, phase, rangeMode)` → `\treturn active`: the crosshair under the summary
  again.
- The same line → `\treturn ScenePlan.Crosshair(active, "wave", rangeMode)`.
- `= ScenePlan.RUN_OVER` → `= {}`: the camera's own list. In a grey level the default camera then never returns
  for the summary.

The K9 pins on `phaseEndsCamera` and `levelDressed = dressed` keep their text, so the existing entries stand.

**FeedbackController.luau**, in `updateCrosshair` (the third argument of `marker.Update`):
```
		CameraController.ShowsCrosshair(),
```
(count 1). Also pin `CameraController.IsActive(` at count 0 in this file. Mutants:
- `\t\tCameraController.ShowsCrosshair(),` → `\t\tCameraController.IsActive(),`
- the same line → `\t\ttrue,`

Both passed today's harness.

**LevelScenery.luau: the reviewer's m1 probes.** These are my final lines; nothing in the file changed this round.
Each mutant below passed today's harness on the copy (`PASS (4,668)`).

`isSkinned` (count 1):
```
	return child:IsA("BasePart") and child:GetAttribute(NAMES.skinned) == true
```
Mutant: `\treturn false`. A failed client then leaves every hidden rock and path invisible but solid.

`isWall` (count 1):
```
	return child:IsA("BasePart") and child.CollisionGroup ~= NAMES.defaultGroup
```
Mutants:
- `\treturn false`: no wall is drawn on a failed client.
- `~=` → `==`: the wrong Parts are painted.

`teardown`'s state, in this order (each line count 1):
```
	state.dress = nil
	state.built = false
	state.failed = false
```
- Mutant: delete `\tstate.failed = false`. One failure then greys every later dressed level for the session.
- The state table's initial `\tfailed = false,` is different text, so a count-1 pin on `\tstate.failed = false`
  is exact.
- `\tstate.failed = true` (in `fail`) is also count 1 and is already pinned.

`bodyInLobby`, the whole body (each line count 1, except `\t\treturn false`, which is count 2 in the file: pin it
inside this body only):
```
	local known = state.inLobby
	if known ~= nil then
		return known
	end
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild(NAMES.root) else nil
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	return inLobbyAt(root.Position)
```
Mutants:
- `\t\treturn known` → `\t\treturn false`: mood B in the lobby camp (K8 undone).
- `\treturn inLobbyAt(root.Position)` → `\treturn false`.
- The reviewer's form: the first four lines replaced by `\treturn false`.

The one writer of `state.inLobby` (`\tstate.inLobby = inLobbyAt(position)`, in `onPlaced`) is already pinned.

**Harness.** No SOURCES or TESTS change: `ScenePlan` and `tests_l4w2_scenery.luau` are registered, and the file
still ends with the verdict line. The new group adds no top-level local; it hangs off `L4S`. It reads
`FIXTURES.combat.camera.freeCursorPhases`, which is already in the fixtures.

### ui-engineer B

Nothing owed. I did not touch `CombatUIController.luau`. My FeedbackController edit is two lines in
`updateCrosshair`; if you touch that file, merge around them.

### The lead

The reviewer suggested "gate the crosshair on the phase". The gate is the phase alone, with no dressed flag,
because a grey level's camera is already down in those phases. So the rule needs no word from LevelScenery, and
there is no frame between the summary's RunState and `SetDressed` in which it can be wrong. The RunState that
starts the summary sets the phase, and the crosshair hides on the next render step.

## Gates (2026-10-22)

- **stylua `--check`**: clean on all four files.
- **selene**: 0 errors and 0 warnings on the three source files. The test file gives 87 `undefined_variable`
  errors: the predecessor's 78 bundle names plus my 9 new uses of `check`/`FIXTURES`, the same family as every
  case file.
- **luau-lsp**, sourcemaps written to my scratch:
  - Combat sourcemap: 0 diagnostics on the whole of `src/combat/client`.
  - Hub sourcemap: this place does not map these combat-only files, so they give "unknown require", as at HEAD.
    The counts against a HEAD copy are CameraController 1 → 2 (the new ScenePlan require), FeedbackController
    15 → 15, ScenePlan 0 → 0.
- **`py tools/check_compile.py`** (3.14): PASS, 182 files. CameraController gains one top-level local.
- **`rojo build`**: `combat.project.json` and `default.project.json` both built, into scratch.
- **Harness** (shebang Python 3.12), in the worktree under its own bundle (`HARNESS_BUNDLE=bundle_uia2.luau`,
  deleted after): **PASS, 4,668 checks**. That is the review base's 4,656 plus my 12, with ui B's in-progress
  CampFx and raiderpose edits on disk.
- **`tests_l4w2_scenery.luau`**: all 12 new checks ok. The 9 ScenePlan mutants are each caught on the copy, and
  the copy reads PASS again when restored.
- **Line endings**: all files LF.
- **Layouts**: no GUI geometry changed. Only the crosshair's `Visible` is now false in summary and ended, so at
  375×667, 667×375 and 1920×1080 the summary card has the screen's centre to itself. Everything else is as before.

## Assumptions

- "The run is over" means `summary` and `ended` (Types.RunPhase), the same phases that end the camera in a grey
  level.
- The crosshair still shows in `lobby`, `travel`, `gate`, `wave`, `breather` and `boss`, and while downed, as before.

## What to check in Studio (keys only)

1. **Dressed Forest Road, Normal.** End a run: N to step into camp C, or Backspace twice to abandon.
   - During the 10 s summary, nothing is drawn at the screen's centre.
   - The shoulder camera stays: hold the right mouse button and swing it into the 64-stud wall, and it stops there.
   - The cursor is free for the card.
2. **Return to the lobby camp.** The crosshair is back as soon as the next RunState (lobby) arrives.
3. **Grey level** (press Z, then run again). The summary is as before: Roblox's camera and no crosshair.
4. **Mobile emulator, 667×375 and 375×667, dressed summary.**
   - No crosshair shows under the card.
   - A drag on the right half still turns the view.
   - The card's buttons respond.
