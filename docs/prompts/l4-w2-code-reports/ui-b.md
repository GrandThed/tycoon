# L4 W2 code wave: ui-engineer B (report, kept current)

Worktree `tycoon-p5`, branch `l4-w2`. Nothing committed. Started 2026-10-22.

## State

- [x] `Controllers/Raiders/RaiderPose.luau` (new, pure: Threat, Rig, Arm, Walk, Paint) (contract 3.3). D2's
  `check_raider_mirror.py`: **CHECK: PASS, 16,806 cases, worst 7.11e-15**. Its mutants: 13 of 14 red, **one STALE**
  (stylua split the line it aims at; the re-aim is below, D2's file).
- [x] `Controllers/Raiders/Figures.luau` (new: pools per kind, the template clone, the anchor `Head`, paint per role,
  the plate role, the Chief's Warhammer, walk and arm per frame, the queue) (3.2)
- [x] `CrowdRenderer.luau` (threatPose on RaiderPose.Threat, figures worn and swapped, the seat through
  `HitShapes.SeatStep` / `SeatDrop` on Tuning's numbers, ForEach's `drop`, `ToggleModels` (X), `Prewarm(counts)`,
  DrawClock)
- [x] `ThreatFx/Cues.luau` (a model kind gets only its lit piece, riding the arm or the torso; the Chief's core sized
  from config; `Cues.QueueRig`)
- [x] `ThreatFx/PlateBar.luau`: **unchanged**. CrowdRenderer now hands it the anchor (`entity.anchor`: the figure's
  invisible `Head`, or the placeholder's head), which is all it needed.
- [x] `InputController.luau` (CrowdRay's `drop`; the head sphere lowered by it in the assist cone, the burst holds and
  the melee reach)
- [x] `CombatUIController.luau` (`RunState.prewarm` to `CrowdRenderer.Prewarm`, X toggles the models with a toast,
  Z sends `dressFail`, Y/O/X/Z in DEBUG_HINT, LevelScenery's toast handler)
- [x] `Theme.luau` (COMBAT_REST_DROP / COMBAT_RISE_BLEND_SECONDS gone; the raider walk / pool numbers and the plate's
  material; ui A's whole block pasted as relayed; COMBAT_PERF_WIDTH 140 -> 300)

## Gates (mine, 2026-10-22)

- `stylua --check` and `selene` on my files: clean (0 errors, 0 warnings).
- `luau-lsp analyze` (`--definitions=tools/types/globalTypes.d.luau`, sourcemaps written to my scratch):
  `src/combat src/shared` on `sourcemap.combat.json` **0 diagnostics**; `src/client src/server src/shared` on
  `sourcemap.json` **0 diagnostics** (with ui A's Theme block in, the whole tree is clean on both).
- `py tools/check_compile.py`: **PASS, 181 files**. CrowdRenderer **164** top-level locals (was 154; budget 180):
  the new behaviour went into `Raiders/Figures` and `Raiders/RaiderPose`.
- `rojo build` of `combat.project.json` and `default.project.json` into scratch: both built.
- Harness (`run_harness.py`, its shebang: Python 3.12 64-bit): **HARNESS: PASS (4,254 checks)**.
- `mutate.py`: not run (D2 owns it). A stale check of its list against my files (a scratch copy of mutate.py's
  entries, nothing run): **21 entries read my files (InputController, CombatUIController), 0 stale**. None reads
  CrowdRenderer, Cues, PlateBar or Theme. **D2: please run `files:InputController.luau,CombatUIController.luau`.**
- `py tools/check_raider_mirror.py --luau <luau> --mutants` (D2's, its shebang: 3.12): CHECK PASS; MUTANTS 13 of 14
  (the stale one; its re-aim below turns the mirror red with 42 differences on a scratch copy).
- `git grep -nE 'COMBAT_REST_DROP|COMBAT_RISE_BLEND|ForestRoad\.dress\.json' -- src tools`: empty.
- LF only (new files checked); nothing committed.

## What was built

- **RaiderPose** (pure; `luau.exe` runs the file the game runs): `Threat` = today's threatPose numbers plus the arm's
  clocks (build, snap, u, sweep, settle, spent, slump); `Rig` = raiderpose.py `rig` (five pieces, the head on the
  scored head, the seat drop from `restDrop`); `Arm` = `arm_channel` with the short-way blend, the throw path, whirl,
  steady and the lock's aim; `Walk` = the new walk step; `Paint` = `paint`. Rotations travel as nine numbers through
  multi-returns, so a frame allocates nothing there; every function writes into an `out` it is handed.
- **The threatPose split**: CrowdRenderer keeps the phase clock, `setThreat`, `setTint` and the ground tell; the numbers
  come from `RaiderPose.Threat` for the placeholder and the models alike. The placeholder's look is unchanged (same
  maths in the same order; the tint is stepped in Threat and again in setTint, which is idempotent).
- **Figures** (its own module, the 180-locals rule): a kind counts when RaiderModels.json names it, its height / radius /
  headRadius equal ProvingGrounds.json's (1e-6), every point, arm key and rig number is there and the template has every
  named MeshPart; otherwise today's placeholder, with one warning for a kind the config names (kinds it does not name,
  the guard, the Warlord, the Colossus, the dummies, say nothing). A figure is the template's clone: every MeshPart of a
  stage keeps its rest frame relative to Base (a stage part the entry does not name is gear), anything else in the
  template is destroyed, an invisible ball `Head` (2 x headRadius, nothing collides, queries or touches) rides at
  `(0, anchorY, 0)`, painted roles have their TextureID cleared once (L4W2-10), only the torso piece casts shadows
  (none on `lowEndDevice`). The Chief's Warhammer is the L3 template's Stage0 scaled once by `hold.scale` about its grip,
  placed at the arm piece x `CFrame.fromMatrix(grip, right, up)`; a missing template draws him without it (one warn).
  One pool per kind, filled from RunState.prewarm (capped at crowd.maxAlive, `COMBAT_RAIDER_PREWARM_PER_FRAME` = 4 a
  frame); an empty pool builds on demand. Today's placeholder pool stays (every body record keeps its four parts).
- **Per frame** (a model body): `Figures.Pose` steps the walk (travel = the drawn feet's flat move) and the arm and says
  whether either moved; that joins the pose-changed test (with the thrust). When drawn, `Figures.Queue` rigs the pose
  (yaw, twist = drawnYaw - yaw, the lean vector split along the facing and the right, the drawn squash, the seat,
  airborne) and writes every MeshPart, the anchor, the lit piece (`Cues.QueueRig`) and the hammer into the one
  BulkMoveTo. The root is the feet plus a launch's tumble. A model's lunge thrust is never a slide (the rig steps the
  leading foot and the arm reaches); knockback, launch and a rise are whole-body offsets as before. A dying or vanishing
  model is its rest pose (seated if it sat) as a whole under today's rootFrame (`Figures.QueueRest`).
- **Paint**: `RaiderPose.Paint` per role (cloth, clothLeg, skin, glow), written only on change; gear keeps its texture.
  **Plate role**: today's shell rule on the planks (plate colour and `COMBAT_RAIDER_PLATE_MATERIAL` SmoothPlastic; a
  turned hit white Neon; warded the ward colour as ForceField x 1.14; the break white Neon growing x (1 + 0.6 x share)
  about each MeshPart's centre with Transparency = share, then hidden for good); the body's fade lays over it.
- **Cues**: a model kind gets only its lit piece at its config point, riding its piece: the slinger's orb (arm /
  pouch), the marksman's tip (arm / tip), the lobber's round (torso / pack), the Chief's core (torso / core, 1.6 swelling
  to 2.6; enraged 2.16 and max(2.6, 2.16)). Sizes otherwise stay today's rules. Fodder, the brute and the elite get no
  cue set (horns, pack, barrel, crown and the shell are the model's).
- **The seat**: `HitShapes.SeatStep(seat, goal, dt, crowd.riseBlendSeconds)` steps it exactly as the server does; the
  placeholder sinks by `HitShapes.SeatDrop(height, seat, crowd.restDrop)`; the rig anchors the head with the same drop;
  ForEach hands that drop to aim assist and auto-fire (InputController passes it to CrowdRay and lowers the head sphere
  of its cone and melee tests).
- **X** (Studio, local): `CrowdRenderer.ToggleModels()` flips Figures on or off and re-dresses every living body (the
  figure swapped, the cues and the plate bar taken again on the new anchor); a toast says which. **Z**: the `dressFail`
  lever through RequestDebug (DebugService's handler is A's, already in).
- **Draw time**: `DrawClock.Add(os.clock() - now)` at the end of CrowdRenderer's step (nothing when no body is drawn).

## For the other owners

### D2: re-aim one mirror mutant (`tools/check_raider_mirror.py` MUTANTS)

stylua laid the line-lock condition in `RaiderPose.Arm` out on several lines, so this entry is STALE:

- old entry: `("Arm: a line aimed by the body's build, not its lock", 'if shape == "line" and attack ~= nil and
  attack.lock > 0 and attack.windup > attack.lock then', "if false then")`
- new entry: `("Arm: a line aimed by the body's build, not its lock", "\t\t\tand attack.windup > attack.lock\n",
  "\t\t\tand false\n")` (the text occurs once; on a scratch copy it turns the mirror red with 42 differences).

The file as it stands now (lines 949-956):
```
		if
			shape == "line"
			and attack ~= nil
			and attack.lock > 0
			and attack.windup > attack.lock
		then
			build = math.min(threat.age / (attack.windup - attack.lock), 1) ^ 2
		end
```
The other 13 mutant texts are unchanged. I will not touch RaiderPose's text again without telling you the new line.

### D2: `RaiderPose.luau`'s API (as your mirror already reads it)

File `src/combat/client/Controllers/Raiders/RaiderPose.luau`; `require("<path>/RaiderPose")` works under `luau.exe`
(no `game`, no Roblox type, no require). Every function writes into an `out` it is given or makes one when given nil.
Tables in, numbers out; colours are `{ r, g, b }` in 0-1; transforms are 12 numbers in `CFrame.new` order
(x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22; R row-major = raiderpose.py `CFrame.r` rows).

- `RaiderPose.Threat(input, consts, out?) -> ThreatOut` = `threat_pose(consts, kind, attack, phase, age, server_now=,
  stride=, unwind=, held=)`. `input = { shape, phase, age, windup, strike, recover, reach, arc, lock, radius, serverNow,
  stride, unwind, held }` where shape/windup/strike/recover/reach/arc/lock are `attack_of(...)`'s fields (`arc` in
  radians) and `radius` is `kind["radius"]`. Out fields, the dataclass's names in camelCase: `phase, age, lean,
  thrust, twist, squash, tint, tintColor, glow, visorHot, charge, build, snap, u, sweep, settle, spent, slump`.
- `RaiderPose.Rig(model, rig, consts, pose, out?) -> RigOut` = `rig(model, rig_numbers, consts, pose)` (seated hit
  shapes on). `model` = the RaiderModels.json kind entry (reads height, headRadius, legLength, leadLeg, points.head /
  neck / hipL / hipR / shoulder). `rig` = the config's `rig` (all 14 keys, no defaults). `pose = { yaw, lean, leanSide,
  twist, squash, thrust, seat, airborne, walkPhase, walkAmp, armPitch, armYaw, armRoll }`. Out: `head, torso, arm,
  legL, legR` (12 numbers each), `anchorY` (= `anchor[1]`; x and z are 0), `headX, headY, headZ` (= `head_world`),
  `headOffset`, `drop`, `footL, footR` (= `foot_float`).
- `RaiderPose.Arm(model, shape, threat, pose, rig, attack) -> (pitch, yaw, roll)` = `arm_channel(...)`. `threat` = a
  ThreatOut or nil (nil = phase "none"); `attack` = any table with `windup` and `lock` (the Threat input), or nil. Reads
  `pose.lean, pose.seat, pose.walkPhase, pose.walkAmp`. The client passes the attack's shape while an attack runs and
  the kind's first attack's shape otherwise (as `sweep_poses`' idle does).
- `RaiderPose.Paint(kindColor, skin, threat, flash, enraged, consts, out?) -> PaintOut` = `paint(...)`. **Both colours
  are 0-255 as the configs write them** (Python's `paint` takes the skin already /255). Out: `cloth, clothLeg, skin,
  glow` (rgb) and `clothNeon, clothLegNeon, skinNeon, glowNeon` (true = "Neon").
- `RaiderPose.Walk(phase, amp, travel, dt, speed, legLength, distance, nearStuds, rig, consts) -> (phase, amp)`:
  ```
  stride = rig.strideLegs * legLength
  if stride > 0: phase = (phase + 2*pi*travel/stride) % (2*pi)
  full = speed * rig.walkFullShare
  goal = clamp((travel/dt)/full, 0, 1) if distance <= nearStuds and dt > 0 and full > 0 else 0
  gap = goal - amp
  amp = goal if abs(gap) < consts.COMBAT_RAIDER_WALK_SETTLE else amp + gap*(1 - exp(-dt*consts.COMBAT_RAIDER_WALK_EASE_RATE))
  ```
  The client passes `nearStuds` = `rig.walkNearStuds`, or `min(rig.walkNearStuds, Theme.COMBAT_RAIDER_WALK_NEAR_LOW)` on
  a low-end device; `travel` = the flat distance the drawn feet moved this frame; `speed` = the kind's.
- Constructors: `NewThreatOut()`, `NewRigOut()`, `NewPaintOut()`, `NewPose()`.
- `consts` keys (colours as `{ r, g, b }`): COMBAT_RANGE_TELL_COLOR, COMBAT_RANGE_TELL_SPENT_COLOR,
  COMBAT_RANGE_TELL_HEAT_SHARE, COMBAT_RANGE_TELL_SPENT_SHARE, COMBAT_RANGE_TELL_TINT_STEPS,
  COMBAT_RANGE_TELL_COIL_SHARE, COMBAT_RANGE_TELL_LEAN_BACK, COMBAT_RANGE_TELL_LEAN_FORWARD,
  COMBAT_RANGE_TELL_PULL_BACK, COMBAT_RANGE_TELL_ARC_TWIST_SHARE, COMBAT_RANGE_TELL_ARC_SWEEP_SHARE,
  COMBAT_RANGE_TELL_SPENT_LEAN, COMBAT_RANGE_TELL_SPENT_SQUASH, COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS,
  COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS, COMBAT_RANGE_RING_SLAM_RISE, COMBAT_RANGE_RING_SLAM_SQUASH,
  COMBAT_RANGE_RING_SLAM_LEAN, COMBAT_RANGE_CALL_LEAN, COMBAT_RANGE_CALL_SHAKE, COMBAT_RANGE_CALL_SHAKE_HZ,
  COMBAT_RANGE_CALL_STRETCH, COMBAT_RANGE_ENRAGE_COLOR, COMBAT_RANGE_ENRAGE_SHARE, COMBAT_RANGE_ENRAGE_GLOW_COLOR,
  COMBAT_RAIDER_WALK_EASE_RATE, COMBAT_RAIDER_WALK_SETTLE (Theme.luau), LEG_SHADE, LEG_SHADE_SHARE, VISOR_COLOR,
  VISOR_HOT_COLOR, FLASH_COLOR (CrowdRenderer.luau, unchanged `local NAME = value` lines), and `restDrop`
  (ProvingGrounds.json `crowd.restDrop`). The client builds this table in `Figures.Configure` from those sources.
- The squash the client hands Rig is `drawn_squash` (hundredths) as today; the lean is decomposed along the body's
  facing and right, so `lean` / `leanSide` are exactly raiderpose.py's.

### D2: Theme names raiderpose.py reads

- **Gone from Theme.luau** (contract 5): `COMBAT_REST_DROP`, `COMBAT_RISE_BLEND_SECONDS` (your raiderpose.py reads
  ProvingGrounds.json `crowd.restDrop` / `crowd.riseBlendSeconds` already).
- **New in Theme.luau** (one line each, `NAME = value,`): `COMBAT_RAIDER_WALK_EASE_RATE = 8`,
  `COMBAT_RAIDER_WALK_SETTLE = 0.01`, `COMBAT_RAIDER_WALK_NEAR_LOW = 60`, `COMBAT_RAIDER_PREWARM_PER_FRAME = 4`,
  `COMBAT_RAIDER_PLATE_MATERIAL = Enum.Material.SmoothPlastic`.
- Every other THEME_NAMES / RENDERER_NAMES entry keeps its name and its one-line form.

### D2: pins and mutate

- No harness pin moved (HARNESS: PASS 4,254 on my tree). 21 mutate entries read InputController and
  CombatUIController, none stale; please run `py tools/crowd_harness/mutate.py C:/Users/benja/Desktop/tycoon-p5 <luau>
  "files:InputController.luau,CombatUIController.luau"` in your turn. No new `SOURCES` asked: none of the harness's
  cases reads RaiderPose, Figures, Cues or CrowdRenderer (the mirror is check_raider_mirror's).

### luau-engineer A

- **Types**: `RaiderPartRole` is `"gear" | "cloth" | "skin" | "glow" | "plate"`, but the config also maps every leg's
  `raider-cloth` to **`clothLeg`** (the legs' shade, D2's raider_frames.py checks it as a sixth role). Suggest
  `export type RaiderPartRole = "gear" | "cloth" | "clothLeg" | "skin" | "glow" | "plate"`. Nothing of mine breaks
  either way: Figures reads the config through `any` and checks every value itself.
- Read and used as your report and diff have them: `HitShapes.SeatDrop(height, seat, restDrop)`,
  `HitShapes.SeatStep(seat, goal, dt, blendSeconds)`, `HitShapes.CrowdRay(..., headRadius, drop?)`,
  `Types.RunState.prewarm: { [string]: number }?`, `Catalog.GetRaiderModelsConfig()`, `Types.ProvingGroundsConfig
  crowd.restDrop / riseBlendSeconds`, the `dressFail` lever (value `true`).

### ui-engineer A

- Your Theme block is in, as relayed (after the `COMBAT_PERF_*` group), and `COMBAT_PERF_WIDTH` is 300.
- `CombatUIController`: `LevelScenery.SetToastHandler(...)` beside CombatFx's (same handler shape), and DEBUG_HINT ends
  `... · L reset Armory · Y scenery · O light · X models · Z grey level`.
- `CrowdRenderer`: `DrawClock.Add(os.clock() - now)` at the end of `step` (its `now` is `os.clock()` at the start; the
  one early exit is "no body", which costs nothing).

### Lead

- No project file, remote or hub file. `Controllers/Raiders/` is a plain folder under the combat client's
  `Controllers` (`$path`), so both place builds pick it up (built: combat and default).

## Remotes and state consumed

CrowdSpawn / CrowdSnapshot / CrowdRemove (unchanged); RunState `maxAlive` and `prewarm`; RequestDebug (`dressFail`,
true; Studio only, as every lever). ReplicatedStorage `Assets.Props.Raiders.<model>` and `Assets.Props.Weapons.Warhammer`;
`Config/RaiderModels.json` via `Catalog.GetRaiderModelsConfig`; ProvingGrounds.json `crowd.restDrop`,
`crowd.riseBlendSeconds`, `crowd.maxAlive`, the kinds.

## Assumptions

- "Reactions after a landed hit keep rootFrame on the rest pose" is read as: knockback, launch (its tumble) and a rise
  stay whole-body transforms under the root while the rig keeps posing the body (the launch's leg tuck is the rig's
  `airborne`); the death fling, topple and a vanish draw the rest pose (`QueueRest`).
- The plate while plated is SmoothPlastic (raiders.md 3); `COMBAT_RAIDER_PLATE_MATERIAL` is the one place to try Wood.
- The walk ease (8 a second, settle 0.01) is mine (the contract says "eased toward" without a rate); D2 mirrors it.
- RunState.prewarm entries for kinds this client's config does not know, or that are not counts >= 1, are left out (a
  pool it misses still builds on demand).
- The marksman's warning line still starts at `COMBAT_RANGE_TELL_LINE_BEAM_HEIGHT` 3 (raiders.md risk 3 says W2 *may*
  move it to `points.tip`; that is ThreatFx/Tells, not in my list, and the tell is unchanged for the placeholder).

## Read, not run (Studio only)

The whole model path: clones of the harvested raider templates, BulkMoveTo of about a dozen MeshParts a body, a
MeshPart's `TextureID = ""` at runtime, Neon and ForceField on untextured MeshParts, `Model:ScaleTo` on the Warhammer
clone, `CFrame.fromMatrix` with the config's (very nearly unit) right / up, a BillboardGui adorned to an invisible
ball that moves by BulkMoveTo, CastShadow on the torso piece only, and the frame cost (only Ben's "Draw N ms" says it).

## What to check in Studio (keys only)

1. Depart Forest Road on Normal. Camp A's raiders are the approved models (`_overview.png`): cloth colours per kind,
   resting ones seated at the fires, walkers swinging legs and arms, no `[Figures]` warning in the Output.
2. Wind-ups: the fodder's club coils and jabs (no whole-body slide), the slinger's orb whirls twice over his shoulder and
   swells red, the marksman raises the crossbow level and its tip glows through the lock, the lobber reaches back to the
   satchel and throws overhand; every windup heats the body red, the blow flashes Neon, the spent body goes dull.
3. A plated elite: the planks are blue while plated, flash white on a turned hit, and burst outward on the break (the
   pauldrons and shield fly with it), then the reel; the plate bar sits over his head and follows him seated or standing.
4. **N** to the clearing (never B): the Chief carries the Warhammer in his right hand; the sweep, the slam, the charge and
   the call read on the model; his core glows pink, swells red through every windup, turns gold and larger when enraged,
   his eyes glow on every windup and stay lit once enraged.
5. Headshots on seated raiders (the head is lower now, on the client as on the server) and on winding-up ones.
6. **X**: every body switches to the placeholder figures and back (a toast says which); nothing jumps or floats.
7. **Z**, then a new run: the level is built grey (A's lever; the raiders are unaffected).
8. "Draw N ms" at the Main Camp's west gate with camp A and B awake (Studio's perf line).
9. Device emulator 667 x 375 and 375 x 667: nothing of mine adds a control or a screen element; the X toast is the
   existing Toast; the key hint is keyboard and Studio only. Raider shadows: none at graphics quality 3 or less.
