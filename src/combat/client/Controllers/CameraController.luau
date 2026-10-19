--!strict
-- Over-the-shoulder camera for the Expeditions place (C2.5 ruling 1, docs/INTERFACES.md
-- "C2.5 + C3 contracts — Stop 1", "Combat client"). Client-only presentation: it never
-- touches a remote, and aim stays a direction the server raycasts itself.
--
-- The camera is Scriptable rather than the default module with Humanoid.CameraOffset
-- (deviation reported): the stock PlayerModule has no per-device sensitivity, applies
-- CameraOffset in the root's frame (which is the camera's own yaw here, a feedback loop),
-- and reads its next frame back from Camera.CFrame, so every shake or kick written on top
-- of it drifted the view permanently. Owning yaw/pitch/zoom makes shake an offset that is
-- recomputed from scratch each frame and can never drift.
--
-- Devices (ruling 1):
--  * PC: mouse locked to the centre, the character faces the camera yaw. The cursor is free
--    in `camera.freeCursorPhases`, while any cursor hold is set (debug strip, load card) and
--    after Alt toggles it; with a free cursor the right mouse button still turns the view.
--  * Touch: a drag that starts on the right half of the screen (and not on a button) turns
--    the view, two fingers pinch-zoom, and the finger that holds the attack button also
--    aims (AdoptTouch) the way modern mobile shooters do. The Roblox thumbstick keeps the
--    left half.
--  * Gamepad: right stick aims; the bindings for R2 / L1 / R1 / Y live in InputController.
--
-- The default camera comes back whenever the character is dead or missing and in the
-- summary / ended phases, so a down player watches their own ragdoll and the summary card
-- has the ordinary cursor.
--
-- P1 Proving Grounds (docs/INTERFACES.md "P1 contracts"): this module is the one place the
-- other controllers ask which combat runs, because it is the lowest-level controller and both
-- InputController and MovementController already require it. Aim-down-sights narrows the
-- field of view to `shooting.adsFieldOfView` and scales look sensitivity with it, and the
-- pivot's height follows the character through a clamped lag, so a 16-stud jump or a slam
-- glides instead of yanking the view.
--
-- P5 (docs/INTERFACES.md "P5 contracts", ruling 5): the mode is the shared CombatMode value,
-- decided once at boot with the server's own function. `IsRange` is the range bench only
-- (no run phase, so the phase rules are skipped there). `IsCrowdCombat` is the range's combat
-- (crowd, weapon families, abilities, the player's body), which runs in missions too whenever
-- the ProvingGrounds config ships, as WeaponService does; ADS, the pivot lag and the leap
-- follow belong to it. The phase rules apply in missions only, as before.
--
-- L1 (docs/INTERFACES.md "L1 contracts"): the server moves a body several hundred studs in one
-- frame (the lobby camp to a level and back, a camp's entry, a rescue). The pivot's lag is
-- clamped to movement.cameraMaxLag, so the view never swept across the map, but it would still
-- glide those last studs: a root that jumps more than Theme.COMBAT_CAMERA_SNAP_STUDS in a
-- frame drops every lag, and the camera is simply there. No phase rule changed: `travel` and
-- `gate` are not in camera.freeCursorPhases, so they lock the cursor like a fight.
--
-- L1 fix round (docs/prompts/l1-fix-round.md, part U, items 1 to 3):
--  * A body the server PLACED is announced (OnPlaced). The server says so itself: after every
--    move ArenaService.MoveMember writes two attributes on the character, `Placed` (the feet
--    point it put the body at) and `PlacedSeq` (a count that rises with every move). This
--    module watches them and hands the destination on; nothing is guessed from how far the
--    root travelled, and the snap above is for the camera's own lag and nothing else. A body
--    the camera has only just picked up (a new one, the first frame after the summary) is
--    announced too, as "no word from the server". MovementController drops the speed the body
--    carried, and the mission HUD turns the view along the way forward. A build whose server
--    writes no such attributes simply hears nothing.
--  * LookToward turns the VIEW to a point (the body follows the view's yaw), from the body or
--    from a point the body is about to be at. FaceToward is not that: it turns the body alone
--    for a moment and hands it back to the view.
--  * KeepAltFree: while Abandon waits for its second press, a new phase does not take back the
--    cursor the player freed with Alt to press it; it is taken back when the wait is over.
--
-- P3 (docs/INTERFACES.md "P3 contracts"): during a Leap Smash or an Impale Dash
-- (MovementController.BeginMotion) the pivot's horizontal position trails the character by
-- the same clamped lag the height uses, so a 60-100 stud/s burst reads as speed instead of
-- the world snapping past a locked camera; afterwards the gap closes on its own in a fraction
-- of a second. A leap adds a short field-of-view kick. Neither is shake: shake is Feedback's.
--
-- L1c-5a (docs/prompts/l1c-contract.md): a locking camp is walled so nothing inside shows from
-- outside, but an open gate does not stop the spherecast (open gates are CanQuery false), so a
-- camera swung near the gate looked in along the inner wall. The boom, from the pivot through
-- the shoulder to the camera, never comes within levels.cameraClear of the fenced rectangle
-- (floor + its fence thickness, RunFloor.fence) of a locking camp unless the local root stands inside that
-- rectangle within its trigger band (RunFloor.ceiling: levels.triggerHeight, or a walled camp's
-- fence top, the L1c second fix round's F1); it stops COMBAT_CAMERA_COLLISION_PAD short
-- of the grown edge (WallClip.Reach, pure and tested in the harness). The L1c fix round grew the
-- cut (C1: a boom swung back toward the gate ended in its mouth with the root 13 studs back) and
-- added the height (m1: the top of a double jump in the gate's band freed the camera). The floors
-- are RunState.floors, handed on by CombatUIController (SetFloors). Walls outside a camp keep
-- doing their job through the spherecast.
--
-- The L1c fix round's M1: Reset Character would leave no rig, and with none the default camera
-- takes over (free orbit, StarterPlayer's zoom) for the whole respawn: the menu item is turned
-- off in this place. combat.project.json caps CameraMaxZoomDistance at camera.maxZoom behind it.
--
-- L2 W2 (docs/prompts/l2-w2-contract.md, L2-44), the Raiders' Tunnel (12 wide, 14 high, one step
-- of +8, two bends): its roof and walls are colliding, queried Parts in the Default group, so the
-- spherecasts below stop the boom at the roof as at any wall, with the camera's centre at least
-- the collision radius plus the pad (0.7) under it. What a roof adds is the pivot: its height lags
-- the root by up to movement.cameraMaxLag (3) and, during a leap or lunge, its flat position
-- trails it by as much, so off the step's edge or round a bend it could stand inside the step or
-- a wall, where a spherecast starting inside a part sees nothing of it and the camera ends up
-- behind the rock. The pivot is therefore pulled back toward the head first (openPivot), with
-- the same sphere the boom uses: a thin ray met at a shallow angle would leave it closer to the
-- surface than the sphere's radius. With no lag (level ground, no motion ability) the two are one
-- point and nothing is cast; a jump, a fall or a slope lags the height, one cast a frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local CombatMode = require(sharedFolder:WaitForChild("CombatMode"))
local WallClip = require(sharedFolder:WaitForChild("WallClip"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local BIND_NAME = "CombatShoulderCamera"
-- Range-only presentation constants (purely visual, so they live here, not in config).
local ADS_FOV_RATE = 16 -- per second, toward the ADS / hip field of view
-- After a leap or lunge the horizontal trail closes at this rate per second (~0.3 s).
local MOTION_CATCH_UP_RATE = 8
-- Field-of-view kick: rises toward the kick at RISE per second while the kick itself drains
-- at DECAY per second, so it swells over ~0.1 s and settles within ~0.6 s. Degrees, capped.
local FOV_KICK_RISE = 25
local FOV_KICK_DECAY = 5
local FOV_KICK_MAX = 15
local LAG_EPSILON = 0.01
local ENEMIES_FOLDER = "Enemies"
-- The server's word that it moved a body, on the character model (ArenaService.MoveMember):
-- where it put the feet, and a count that rises by one with every move.
local PLACED_ATTRIBUTE = "Placed"
local PLACED_SEQ_ATTRIBUTE = "PlacedSeq"
-- Phases in which the run is over: the ordinary camera and cursor return for the summary.
local DEFAULT_CAMERA_PHASES: { [string]: boolean } = { summary = true, ended = true }
-- Fallbacks used only when Combat.json is missing; the config is the real home of these.
local FALLBACK_CAMERA: Types.CombatCameraConfig = {
	shoulderOffset = { 1.75, 0.6, 0 },
	fieldOfView = 70,
	defaultZoom = 11,
	minZoom = 7,
	maxZoom = 16,
	touchSensitivity = 1,
	gamepadSensitivity = 1,
	touchAimAssistDegrees = 12,
	freeCursorPhases = { "lobby", "summary", "ended" },
}

local CameraController = {}

type Rig = { character: Model, humanoid: Humanoid, root: BasePart }

local cameraConfig: Types.CombatCameraConfig = FALLBACK_CAMERA
local freePhases: { [string]: boolean } = {}
local shoulderOffset = Vector3.zero

local phase = "lobby"
local active = false
-- Both decided once in Init and never change: the range bench, and the range's combat.
local rangeMode = false
local crowdCombat = false
local adsOn = false
local fieldOfView = FALLBACK_CAMERA.fieldOfView
local pivotHeight: number? = nil
-- P3 ability motion: until when the pivot may trail horizontally, the current trail (pivot
-- minus root, X/Z only), the root's last flat position, and the field-of-view kick.
local motionUntil = 0
local flatLag = Vector3.zero
local lastRootFlat: Vector3? = nil
-- L1: where the root stood last frame. A jump of COMBAT_CAMERA_SNAP_STUDS in a frame drops the
-- camera's lag; it says nothing else (see `placement`).
local lastRoot: Vector3? = nil
-- Told each time the server placed the local body (CameraController.OnPlaced).
local placedHandlers: { (position: Vector3, signalled: boolean, far: boolean) -> () } = {}
-- The server's placement signal, as watched on the local character. `seq` is the last
-- `PlacedSeq` read (nil = none yet on this body); `dirty` = it changed, or the body is new, and
-- both attributes are read on the next frame, when whatever order they arrived in no longer
-- matters. `lookYaw` / `lookAt` hold the last LookToward and when it was asked: a camera that
-- is down, or about to bind a new body, takes it when it picks the body up. `rootSeen` is the
-- root as last seen, camera up or not, and `jumpedAt` when it last jumped further than
-- COMBAT_CAMERA_SNAP_STUDS in a frame: how far a signalled move took the body (see `far`).
local placement = {
	character = nil :: Model?,
	connections = {} :: { RBXScriptConnection },
	seq = nil :: number?,
	dirty = false,
	lookYaw = nil :: number?,
	lookAt = 0,
	rootSeen = nil :: Vector3?,
	jumpedAt = -math.huge,
}
-- L1c-5a: the run's locking camps as fenced rectangles (each floor grown by its RunFloor.fence,
-- else `fence`, read from Combat.json levels.fenceThickness), which the boom stays out of. Empty outside a level. `clip`
-- is how (WallClip.Clip): the pad, levels.cameraClear and levels.triggerHeight. Without them the
-- clip is the first L1c one: nothing grown, a root inside at any height.
-- `resetTries` and `resetWait`: SetCore throws until the CoreScripts have registered the reset
-- callback, so turning Reset Character off is retried this often, this far apart.
local wallClip = {
	rects = {} :: { WallClip.Rect },
	fence = 0,
	clip = { pad = 0, margin = 0, height = math.huge } :: WallClip.Clip,
	resetTries = 60,
	resetWait = 0.5,
}
local fovKick = 0
local fovKickShown = 0
local boundHumanoid: Humanoid? = nil
local savedFieldOfView: number? = nil
local yaw = 0
local pitch = 0
local zoom = FALLBACK_CAMERA.defaultZoom
local targetZoom = FALLBACK_CAMERA.defaultZoom
-- The unshaken camera frame, so aim never inherits a shake or a kick.
local aimFrame: CFrame? = nil

local cursorHolds: { [string]: true } = {}
local altFree = false
-- KeepAltFree: `keep` while a new phase must not take the freed cursor back, `pending` once one
-- tried to (it is taken back when the keep ends).
local altHold = { keep = false, pending = false }
-- Alt is ignored while the window is unfocused, and focus changes reset it, so Alt-Tab
-- never leaves the lock flipped.
local windowFocused = true
local rightMouseHeld = false
local gamepadLook = Vector2.zero
-- Touches that steer the camera: the last seen position and the delta not yet applied.
-- `adopted` = the finger holding the attack button; it always turns and never pinches.
type TouchState = { last: Vector2, pending: Vector2, adopted: boolean }
local cameraTouches: { [InputObject]: TouchState } = {}
local pinchDistance: number? = nil

local faceTarget: Vector3? = nil
local faceUntil = 0

local trauma = 0
local kickPitch = 0
local shakeClock = 0

local connections: { RBXScriptConnection } = {}
-- Camera collision ignores every character and the enemies folder. The list only changes
-- when a character spawns or a player joins or leaves, so it is rebuilt then, not per frame.
local collisionParams: RaycastParams? = nil
local collisionEnemies: Instance? = nil
local characterConnections: { [Player]: RBXScriptConnection } = {}

local function currentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function localRig(): Rig?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return { character = character, humanoid = humanoid, root = root }
end

local function yawOf(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

-- The range has no run phase (no RunState is pushed there), so phase rules never apply.
local function phaseFreesCursor(): boolean
	return not rangeMode and freePhases[phase] == true
end

local function cursorFree(): boolean
	return phaseFreesCursor() or next(cursorHolds) ~= nil or altFree
end

local function targetFieldOfView(): number
	if crowdCombat and adsOn then
		return Tuning.Get().shooting.adsFieldOfView
	end
	return cameraConfig.fieldOfView
end

-- Look sensitivity follows the zoom, so a scoped view does not swing further per pixel.
local function lookScale(): number
	if not crowdCombat then
		return 1
	end
	local hip = math.tan(math.rad(cameraConfig.fieldOfView) * 0.5)
	if hip <= 0 then
		return 1
	end
	return math.tan(math.rad(fieldOfView) * 0.5) / hip
end

local function clearTouches(): ()
	table.clear(cameraTouches)
	pinchDistance = nil
end

local function applyMouse(locked: boolean): ()
	if not UserInputService.MouseEnabled then
		return
	end
	if locked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	elseif rightMouseHeld and active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

local function deactivate(): ()
	if not active then
		return
	end
	active = false
	aimFrame = nil
	clearTouches()
	applyMouse(false)
	local camera = currentCamera()
	local humanoid = boundHumanoid
	boundHumanoid = nil
	if humanoid ~= nil and humanoid.Parent ~= nil then
		humanoid.AutoRotate = true
	end
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid ~= nil and humanoid.Parent ~= nil then
			camera.CameraSubject = humanoid
		end
		local fov = savedFieldOfView
		if fov ~= nil then
			camera.FieldOfView = fov
		end
	end
	savedFieldOfView = nil
	motionUntil = 0
	flatLag = Vector3.zero
	lastRootFlat = nil
	lastRoot = nil
	fovKick = 0
	fovKickShown = 0
end

local function bindHumanoid(rig: Rig): ()
	boundHumanoid = rig.humanoid
	rig.humanoid.AutoRotate = false
	yaw = yawOf(rig.root.CFrame.LookVector)
	-- A new body starts under the camera, never trailing the old one.
	motionUntil = 0
	flatLag = Vector3.zero
	lastRootFlat = nil
	lastRoot = nil
end

local function activate(camera: Camera, rig: Rig): ()
	active = true
	savedFieldOfView = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	-- Pick up where the default camera was looking so the switch does not snap the view.
	local look = camera.CFrame.LookVector
	bindHumanoid(rig)
	if Vector3.new(look.X, 0, look.Z).Magnitude > 0.01 then
		yaw = yawOf(look)
	end
	pitch = math.rad(Theme.COMBAT_CAMERA_START_PITCH_DEGREES)
	targetZoom = math.clamp(cameraConfig.defaultZoom, cameraConfig.minZoom, cameraConfig.maxZoom)
	zoom = targetZoom
	fieldOfView = targetFieldOfView()
	pivotHeight = nil
end

local function invalidateCollision(): ()
	collisionParams = nil
end

local function collisionParamsFor(): RaycastParams
	-- The enemies folder can replicate after the first frame; its arrival forces one rebuild.
	local enemies = Workspace:FindFirstChild(ENEMIES_FOLDER)
	local cached = collisionParams
	if cached ~= nil and enemies == collisionEnemies then
		return cached
	end
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(list, character)
		end
	end
	if enemies ~= nil then
		table.insert(list, enemies)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	collisionParams = params
	collisionEnemies = enemies
	return params
end

local function watchPlayer(player: Player): ()
	local existing: RBXScriptConnection? = characterConnections[player]
	if existing ~= nil then
		existing:Disconnect()
	end
	characterConnections[player] = player.CharacterAdded:Connect(invalidateCollision)
	invalidateCollision()
end

local function forgetPlayer(player: Player): ()
	local existing: RBXScriptConnection? = characterConnections[player]
	characterConnections[player] = nil
	if existing ~= nil then
		existing:Disconnect()
	end
	invalidateCollision()
end

-- How far a sphere can travel from `from` along `offset` before touching the arena; the
-- full length when nothing is in the way.
local function clearDistance(params: RaycastParams, from: Vector3, offset: Vector3): number
	local length = offset.Magnitude
	if length <= 0 then
		return 0
	end
	local result = Workspace:Spherecast(from, Theme.COMBAT_CAMERA_COLLISION_RADIUS, offset, params)
	if result == nil then
		return length
	end
	return math.max(result.Distance - Theme.COMBAT_CAMERA_COLLISION_PAD, 0)
end

-- L2-44: the lagging pivot, pulled back toward the head (root + pivot height, always in the open:
-- the body stands there, so a sphere of the collision radius fits) when a solid lies between them,
-- so every spherecast after it starts in the open (c-m1: a sphere, as clearDistance sweeps it).
local function openPivot(params: RaycastParams, rootPosition: Vector3, pivot: Vector3): Vector3
	local head = rootPosition + Vector3.new(0, Theme.COMBAT_CAMERA_PIVOT_HEIGHT, 0)
	local offset = pivot - head
	if offset.Magnitude < LAG_EPSILON then
		return pivot
	end
	return head + offset.Unit * clearDistance(params, head, offset)
end

-- L1c-5a: how far along `offset` from `from` the camera may go before entering a locking camp
-- whose rectangle does not hold `root`; the full length when no camp is in the way.
local function campReach(from: Vector3, offset: Vector3, root: Vector3): number
	local length = offset.Magnitude
	if length <= 0 or #wallClip.rects == 0 then
		return length
	end
	local share = WallClip.Reach(
		from.X,
		from.Z,
		offset.X,
		offset.Z,
		wallClip.rects,
		root.X,
		root.Y,
		root.Z,
		wallClip.clip
	)
	return length * math.min(math.max(share, 0), 1)
end

local function consumeLookInput(deltaTime: number): ()
	local turn = Vector2.zero
	if UserInputService.MouseEnabled and (not cursorFree() or rightMouseHeld) then
		local delta = UserInputService:GetMouseDelta()
		turn += Vector2.new(delta.X, delta.Y * Theme.COMBAT_CAMERA_PITCH_RATIO) * math.rad(
			Theme.COMBAT_CAMERA_MOUSE_DEGREES_PER_PIXEL
		)
	end

	for input in cameraTouches do
		if
			input.UserInputState == Enum.UserInputState.End
			or input.UserInputState == Enum.UserInputState.Cancel
		then
			cameraTouches[input] = nil
		end
	end
	-- Only free camera fingers pinch. The attack finger (claw grip) always turns, even while
	-- another finger is down, so firing and tracking never zooms by accident.
	local free: { TouchState } = {}
	for _, state in cameraTouches do
		if not state.adopted then
			table.insert(free, state)
		end
	end
	local pinching = #free >= 2
	if pinching then
		local distance = (free[1].last - free[2].last).Magnitude
		local previous = pinchDistance
		if previous ~= nil and distance > 0 then
			targetZoom *= previous / distance
		end
		pinchDistance = distance
	else
		pinchDistance = nil
	end
	local sensitivity = cameraConfig.touchSensitivity
	for _, state in cameraTouches do
		if not pinching or state.adopted then
			turn += Vector2.new(state.pending.X, state.pending.Y * Theme.COMBAT_CAMERA_PITCH_RATIO) * math.rad(
				Theme.COMBAT_CAMERA_TOUCH_DEGREES_PER_PIXEL
			) * sensitivity
		end
		state.pending = Vector2.zero
	end

	if gamepadLook.Magnitude > 0 then
		local rate = math.rad(Theme.COMBAT_CAMERA_GAMEPAD_DEGREES_PER_SECOND)
			* cameraConfig.gamepadSensitivity
			* deltaTime
		-- Stick up looks up, which is the opposite sign of a mouse moving up the screen.
		turn += Vector2.new(gamepadLook.X, -gamepadLook.Y * Theme.COMBAT_CAMERA_PITCH_RATIO) * rate
	end

	turn *= lookScale()
	yaw -= turn.X
	pitch = math.clamp(
		pitch - turn.Y,
		math.rad(Theme.COMBAT_CAMERA_MIN_PITCH_DEGREES),
		math.rad(Theme.COMBAT_CAMERA_MAX_PITCH_DEGREES)
	)
	targetZoom = math.clamp(targetZoom, cameraConfig.minZoom, cameraConfig.maxZoom)
	zoom += (targetZoom - zoom) * (1 - math.exp(-Theme.COMBAT_CAMERA_ZOOM_RATE * deltaTime))
end

local function faceCharacter(rig: Rig): ()
	if rig.humanoid.Sit or rig.humanoid.PlatformStand then
		return
	end
	local facing = yaw
	local target = faceTarget
	if target ~= nil and os.clock() < faceUntil then
		local flat = Vector3.new(target.X - rig.root.Position.X, 0, target.Z - rig.root.Position.Z)
		if flat.Magnitude > 0.01 then
			facing = yawOf(flat.Unit)
		end
	else
		faceTarget = nil
	end
	local position = rig.root.Position
	rig.root.CFrame = CFrame.new(position) * CFrame.Angles(0, facing, 0)
end

local function shakeOffset(deltaTime: number): CFrame
	shakeClock += deltaTime
	local decay = math.exp(-Theme.COMBAT_CAMERA_KICK_DECAY * deltaTime)
	kickPitch *= decay
	if math.abs(kickPitch) < 0.01 then
		kickPitch = 0
	end
	trauma = math.max(trauma - Theme.COMBAT_SHAKE_DECAY_PER_SECOND * deltaTime, 0)
	if trauma <= 0 and kickPitch == 0 then
		return CFrame.identity
	end
	-- Squared trauma: small hits barely move the view, big ones clearly do.
	local amount = trauma * trauma
	local t = shakeClock * Theme.COMBAT_SHAKE_FREQUENCY
	local maxAngle = math.rad(Theme.COMBAT_SHAKE_MAX_DEGREES) * amount
	local maxShift = Theme.COMBAT_SHAKE_MAX_STUDS * amount
	return CFrame.new(math.noise(t, 11.3) * maxShift, math.noise(t, 23.9) * maxShift, 0)
		* CFrame.Angles(
			math.rad(kickPitch) + math.noise(t, 1.7) * maxAngle,
			math.noise(t, 5.1) * maxAngle,
			math.noise(t, 7.9) * maxAngle * Theme.COMBAT_SHAKE_ROLL_RATIO
		)
end

-- The root's height, eased: horizontal follow stays rigid (aim precision), only the
-- vertical trails (movement.cameraFollowRate per second), and never by more than
-- movement.cameraMaxLag, so a 120 stud/s slam keeps the character on screen.
local function followHeight(rootY: number, deltaTime: number): number
	if not crowdCombat then
		return rootY
	end
	local current = pivotHeight
	if current == nil then
		pivotHeight = rootY
		return rootY
	end
	local movement = Tuning.Get().movement
	local maxLag = math.max(movement.cameraMaxLag, 0)
	local eased = current
		+ (rootY - current) * (1 - math.exp(-movement.cameraFollowRate * deltaTime))
	eased = math.clamp(eased, rootY - maxLag, rootY + maxLag)
	pivotHeight = eased
	return eased
end

-- The root's flat position plus the ability-motion trail. While a leap or lunge runs the pivot
-- eases toward the root (movement.cameraFollowRate, never more than movement.cameraMaxLag
-- behind); otherwise the trail only shrinks, so ordinary aiming stays rigid.
local function followFlat(rootPosition: Vector3, deltaTime: number): Vector3
	if not crowdCombat then
		return rootPosition
	end
	local flatRoot = Vector3.new(rootPosition.X, 0, rootPosition.Z)
	local previous = lastRootFlat
	lastRootFlat = flatRoot
	if previous == nil then
		flatLag = Vector3.zero
		return rootPosition
	end
	if os.clock() < motionUntil then
		local movement = Tuning.Get().movement
		local keep = math.exp(-math.max(movement.cameraFollowRate, 0) * deltaTime)
		local lag = (flatLag - (flatRoot - previous)) * keep
		local maxLag = math.max(movement.cameraMaxLag, 0)
		if lag.Magnitude > maxLag then
			lag = if maxLag > 0 then lag.Unit * maxLag else Vector3.zero
		end
		flatLag = lag
	else
		flatLag *= math.exp(-MOTION_CATCH_UP_RATE * deltaTime)
		if flatLag.Magnitude < LAG_EPSILON then
			flatLag = Vector3.zero
		end
	end
	return rootPosition + flatLag
end

-- Degrees added to the field of view this frame by a kick (FovKick).
local function kickedFieldOfView(deltaTime: number): number
	fovKick *= math.exp(-FOV_KICK_DECAY * deltaTime)
	if fovKick < LAG_EPSILON then
		fovKick = 0
	end
	fovKickShown += (fovKick - fovKickShown) * (1 - math.exp(-FOV_KICK_RISE * deltaTime))
	if fovKick == 0 and fovKickShown < LAG_EPSILON then
		fovKickShown = 0
	end
	return fovKickShown
end

-- Watches the server's placement signal on `character` (nil = no body). Whatever the body
-- already carries is read on the next frame: a new body arrives with the attributes of the
-- move that put it where it is, and no change is ever signalled for those.
local function watchPlacement(character: Model?): ()
	for _, connection in placement.connections do
		connection:Disconnect()
	end
	table.clear(placement.connections)
	placement.character = character
	placement.seq = nil
	placement.dirty = character ~= nil
	if character ~= nil then
		table.insert(
			placement.connections,
			character:GetAttributeChangedSignal(PLACED_SEQ_ATTRIBUTE):Connect(function()
				placement.dirty = true
			end)
		)
	end
end

-- Where the local root is, every frame and whether or not the shoulder camera is up, and when
-- it last jumped further than COMBAT_CAMERA_SNAP_STUDS in a frame.
local function trackRoot(): ()
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		placement.rootSeen = nil
		return
	end
	local now = root.Position
	local before = placement.rootSeen
	placement.rootSeen = now
	if before ~= nil and (now - before).Magnitude > Theme.COMBAT_CAMERA_SNAP_STUDS then
		placement.jumpedAt = os.clock()
	end
end

-- Reads the signal once it has changed. A count that is not new, or a destination that is not
-- a point, says nothing; a server that writes neither attribute never gets here with a number,
-- so that build hears nothing and nothing is said about it.
--
-- `far` = the move took the body further than COMBAT_CAMERA_SNAP_STUDS: a level's start, the
-- lobby, a rescue, a skip. A short nudge (a camp's close putting a fighter at its entry, the
-- grace re-move) is not far, and the view the player chose stands through it. Either the body
-- has not moved yet, and the destination is that far from the root, or it moved first, and the
-- root jumped that far a moment ago: the two arrive in either order.
local function readPlacement(): ()
	placement.dirty = false
	local character = placement.character
	if character == nil then
		return
	end
	local seq = character:GetAttribute(PLACED_SEQ_ATTRIBUTE)
	if typeof(seq) ~= "number" or seq == placement.seq then
		return
	end
	placement.seq = seq
	local destination = character:GetAttribute(PLACED_ATTRIBUTE)
	if typeof(destination) ~= "Vector3" then
		return
	end
	local seen = placement.rootSeen
	local far = seen == nil
		or (destination - seen).Magnitude > Theme.COMBAT_CAMERA_SNAP_STUDS
		or os.clock() - placement.jumpedAt <= Theme.COMBAT_PLACED_TIMEOUT_SECONDS
	for _, handler in placedHandlers do
		handler(destination, true, far)
	end
end

local function update(deltaTime: number): ()
	-- First, and whether or not the shoulder camera is up: a body moved during the summary is
	-- placed all the same.
	trackRoot()
	if placement.dirty then
		readPlacement()
	end
	local camera = currentCamera()
	local rig = localRig()
	local phaseEndsCamera = not rangeMode and DEFAULT_CAMERA_PHASES[phase] == true
	if camera == nil or rig == nil or phaseEndsCamera then
		deactivate()
		return
	end
	-- `pickedUp` = a body the camera was not following until this frame: a new one, or the one
	-- it comes back to after the summary. With no word from the server it still counts as placed.
	local pickedUp = false
	if not active then
		activate(camera, rig)
		pickedUp = true
	elseif boundHumanoid ~= rig.humanoid then
		bindHumanoid(rig) -- respawned while the shoulder camera stayed up
		pickedUp = true
	end
	if pickedUp then
		-- Picking a body up takes the view from the old camera or the body's own facing. A look
		-- asked for a moment ago (the server's word came before the body could be followed) is
		-- the one that stands.
		local held = placement.lookYaw
		placement.lookYaw = nil
		if held ~= nil and os.clock() - placement.lookAt <= Theme.COMBAT_PLACED_TIMEOUT_SECONDS then
			yaw = held
		end
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable -- something reset it; take it back
	end
	rig.humanoid.AutoRotate = false
	applyMouse(not cursorFree())

	local rootPosition = rig.root.Position
	local rootBefore = lastRoot
	lastRoot = rootPosition
	if
		rootBefore ~= nil
		and (rootPosition - rootBefore).Magnitude > Theme.COMBAT_CAMERA_SNAP_STUDS
	then
		-- The server moved the body: no lag is carried over the jump. That is all this says:
		-- what else a move means comes from the server's own signal (readPlacement).
		pivotHeight = nil
		motionUntil = 0
		flatLag = Vector3.zero
		lastRootFlat = nil
	end
	if pickedUp then
		-- Before this frame's look and facing, so a view a handler turns is this frame's view.
		for _, handler in placedHandlers do
			handler(rootPosition, false, true)
		end
	end

	consumeLookInput(deltaTime)
	faceCharacter(rig)

	local params = collisionParamsFor()

	local yawFrame = CFrame.Angles(0, yaw, 0)
	local rotation = yawFrame * CFrame.Angles(pitch, 0, 0)
	local flatPivot = followFlat(rootPosition, deltaTime)
	local pivot = openPivot(
		params,
		rootPosition,
		Vector3.new(
			flatPivot.X,
			followHeight(rootPosition.Y, deltaTime) + Theme.COMBAT_CAMERA_PIVOT_HEIGHT,
			flatPivot.Z
		)
	)
	-- The shoulder offset is pulled in against a wall first, so the camera never starts
	-- its boom from inside the wall the player is hugging.
	local shoulder = yawFrame:VectorToWorldSpace(shoulderOffset)
	local shoulderReach =
		math.min(clearDistance(params, pivot, shoulder), campReach(pivot, shoulder, rootPosition))
	local shoulderPoint = if shoulder.Magnitude > 0
		then pivot + shoulder.Unit * shoulderReach
		else pivot
	local boom = rotation:VectorToWorldSpace(Vector3.new(0, 0, zoom))
	local boomReach = math.min(
		clearDistance(params, shoulderPoint, boom),
		campReach(shoulderPoint, boom, rootPosition)
	)
	local position = shoulderPoint + boom.Unit * boomReach

	local frame = CFrame.new(position) * rotation
	aimFrame = frame
	local fovTarget = targetFieldOfView()
	fieldOfView += (fovTarget - fieldOfView) * (1 - math.exp(-ADS_FOV_RATE * deltaTime))
	camera.FieldOfView = fieldOfView + kickedFieldOfView(deltaTime)
	camera.Focus = CFrame.new(shoulderPoint)
	camera.CFrame = frame * shakeOffset(deltaTime)
end

local function isCameraTouch(input: InputObject): boolean
	local camera = currentCamera()
	if camera == nil then
		return false
	end
	return input.Position.X >= camera.ViewportSize.X * Theme.COMBAT_CAMERA_TOUCH_SPLIT
end

local function onInputBegan(input: InputObject, processed: boolean): ()
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.Touch then
		if not processed and active and isCameraTouch(input) then
			local position = Vector2.new(input.Position.X, input.Position.Y)
			cameraTouches[input] = { last = position, pending = Vector2.zero, adopted = false }
		end
	elseif inputType == Enum.UserInputType.MouseButton2 then
		if not processed then
			rightMouseHeld = true
		end
	elseif inputType == Enum.UserInputType.Keyboard then
		local key = input.KeyCode
		if windowFocused and (key == Enum.KeyCode.LeftAlt or key == Enum.KeyCode.RightAlt) then
			altFree = not altFree
			altHold.pending = false -- the player's own press is the newest word on the cursor
		end
	end
end

local function onInputChanged(input: InputObject, processed: boolean): ()
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.Touch then
		-- Not filtered by `processed`: an adopted touch began on the attack button, so every
		-- one of its moves arrives already processed by that button.
		local state = cameraTouches[input]
		if state ~= nil then
			local position = Vector2.new(input.Position.X, input.Position.Y)
			state.pending += position - state.last
			state.last = position
		end
	elseif inputType == Enum.UserInputType.MouseWheel then
		if not processed and active then
			targetZoom -= input.Position.Z * Theme.COMBAT_CAMERA_WHEEL_STEP
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		local stick = Vector2.new(input.Position.X, input.Position.Y)
		gamepadLook = if stick.Magnitude > Theme.COMBAT_CAMERA_GAMEPAD_DEADZONE
			then stick
			else Vector2.zero
	end
end

local function onInputEnded(input: InputObject): ()
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.Touch then
		cameraTouches[input] = nil
	elseif inputType == Enum.UserInputType.MouseButton2 then
		rightMouseHeld = false
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		gamepadLook = Vector2.zero
	end
end

function CameraController.Init(): ()
	local cfg = Catalog.GetCombatConfig()
	if cfg ~= nil and typeof((cfg :: any).camera) == "table" then
		cameraConfig = cfg.camera
	end
	for _, name in cameraConfig.freeCursorPhases do
		freePhases[name] = true
	end
	local offset = cameraConfig.shoulderOffset
	shoulderOffset = Vector3.new(offset[1] or 0, offset[2] or 0, offset[3] or 0)
	targetZoom = cameraConfig.defaultZoom
	zoom = targetZoom
	fieldOfView = cameraConfig.fieldOfView
	local levels = if cfg ~= nil then (cfg :: any).levels else nil
	if typeof(levels) == "table" and typeof(levels.fenceThickness) == "number" then
		wallClip.fence = math.max(levels.fenceThickness, 0)
	end
	wallClip.clip.pad = Theme.COMBAT_CAMERA_COLLISION_PAD
	if typeof(levels) == "table" and typeof(levels.cameraClear) == "number" then
		wallClip.clip.margin = levels.cameraClear
	end
	if typeof(levels) == "table" and typeof(levels.triggerHeight) == "number" then
		wallClip.clip.height = levels.triggerHeight
	end
	-- On a Studio client this waits for game.Loaded (the Workspace lever replicates with it).
	rangeMode = CombatMode.Get() == "range"
	crowdCombat = Tuning.IsAvailable()
end

-- The fix round's M1: Reset Character off, on its own thread (SetCore throws until the
-- CoreScripts are ready, so it is asked again until it takes).
local function disableReset(): ()
	for _ = 1, wallClip.resetTries do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			return
		end
		task.wait(wallClip.resetWait)
	end
	warn("[CameraController] Reset Character could not be turned off")
end

function CameraController.Start(): ()
	task.spawn(disableReset)
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(
		connections,
		UserInputService.WindowFocused:Connect(function()
			windowFocused = true
			altFree = false
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			windowFocused = false
			altFree = false
		end)
	)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(forgetPlayer))
	-- The server's placement signal is on the local character: each new body is watched from
	-- the moment it is there, and a body that goes takes its watch with it.
	local localPlayer = Players.LocalPlayer
	table.insert(connections, localPlayer.CharacterAdded:Connect(watchPlacement))
	table.insert(
		connections,
		localPlayer.CharacterRemoving:Connect(function(removed: Model)
			if placement.character == removed then
				watchPlacement(nil)
			end
		end)
	)
	watchPlacement(localPlayer.Character)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value, update)
end

-- L1c-5a: the run's floors (RunState.floors, `{}` in the lobby). Only a locking camp's floor
-- keeps the boom out; it is grown by its own fence thickness (RunFloor.fence, else
-- levels.fenceThickness), as the server's trigger is (the further levels.cameraClear is
-- WallClip's, for the cut alone), and holds the root up to the floor's own ceiling, the server's
-- trigger band (levels.triggerHeight when it names none).
function CameraController.SetFloors(floors: { Types.RunFloor }): ()
	table.clear(wallClip.rects)
	for _, floor in floors do
		if floor.locks == true then
			local own = floor.fence
			local fence = if own ~= nil
					and own >= 0
					and own < math.huge
				then own
				else wallClip.fence
			table.insert(wallClip.rects, {
				x = floor.x,
				y = floor.y,
				z = floor.z,
				hx = floor.hx + fence,
				hz = floor.hz + fence,
				ceiling = floor.ceiling,
			})
		end
	end
end

-- Pushed from every RunState. A new phase re-locks a cursor the player freed with Alt, so
-- the next wave never starts with the pointer loose. While KeepAltFree holds, the re-lock waits.
function CameraController.SetPhase(nextPhase: string): ()
	if nextPhase ~= phase then
		if altHold.keep then
			altHold.pending = true
		else
			altFree = false
		end
	end
	phase = nextPhase
end

-- L1 fix round, item 1. Abandon asks twice, and a player who freed the cursor with Alt to click
-- it must still have the cursor for the second click when a phase changes in between (the road
-- into a camp's countdown, the countdown into the wave). `keep` = Abandon is armed. When it is
-- armed no longer, a re-lock that a new phase asked for meanwhile is carried out.
function CameraController.KeepAltFree(keep: boolean): ()
	altHold.keep = keep
	if not keep and altHold.pending then
		altHold.pending = false
		altFree = false
	end
end

-- A modal or strip that needs the pointer (debug strip, load card) holds the cursor free
-- under its own name until it releases it.
function CameraController.SetCursorHold(reason: string, held: boolean): ()
	if held then
		cursorHolds[reason] = true
	else
		cursorHolds[reason] = nil
	end
end

function CameraController.IsActive(): boolean
	return active
end

-- True when this client booted into the Proving Grounds bench (CombatMode "range": Studio, the
-- provingAttribute and `debug.provingBoots` "range"). Only the bench's own pieces ask this.
function CameraController.IsRange(): boolean
	return rangeMode
end

-- P5: true when the range's combat runs (the bench and every crowd mission): the crowd, the
-- weapon families, abilities, vitals and movement. False only in a build without the
-- ProvingGrounds config. That config always ships, and since P5 Wave 1 nothing fights without
-- it: the server no longer handles the C1 attack remotes, so the C1 HUD that
-- CombatUIController still falls back to there (with a warning) can show a run but not play
-- one. Wave 3 deletes that path.
function CameraController.IsCrowdCombat(): boolean
	return crowdCombat
end

-- Aim down sights: the view eases to `shooting.adsFieldOfView`, read live.
function CameraController.SetAds(on: boolean): ()
	adsOn = crowdCombat and on
end

-- True while the shoulder camera has the mouse locked to the crosshair.
function CameraController.IsAiming(): boolean
	return active and not cursorFree()
end

-- The crosshair ray: the camera's centre line without shake. Falls back to whatever camera
-- exists when the shoulder camera is down (dead, summary).
function CameraController.GetAimRay(): (Vector3, Vector3)
	local frame = aimFrame
	if frame == nil then
		local camera = currentCamera()
		frame = if camera ~= nil then camera.CFrame else CFrame.identity
	end
	local resolved = frame :: CFrame
	return resolved.Position, resolved.LookVector
end

-- Melee assist: the rig turns to the locked enemy for `seconds`, then back to the camera.
-- The server measures the swing arc from the root's facing, so the turn is what lands it.
function CameraController.FaceToward(position: Vector3, seconds: number): ()
	faceTarget = position
	faceUntil = os.clock() + math.max(seconds, 0)
	local rig = localRig()
	if active and rig ~= nil then
		faceCharacter(rig) -- now, not next frame: the swing intent leaves this frame
	end
end

-- L1 fix round, item 2. Turns the VIEW to a world point; the body turns with it, because the
-- rig faces the view's yaw. The pitch is the player's and stays. `from` is where the look
-- starts: nil = the body as it stands; a point = where the body is about to be (the server's
-- destination, named before the body's new position has arrived). With the shoulder camera up
-- the view turns now; the look is also held for a moment (Theme.COMBAT_PLACED_TIMEOUT_SECONDS),
-- so a camera that is down, or about to bind a new body, takes it when it picks the body up.
-- False when there is nothing to turn to: no body to look from, or the point is over or under
-- where the look starts.
function CameraController.LookToward(position: Vector3, from: Vector3?): boolean
	local origin: Vector3
	if from ~= nil then
		origin = from
	else
		local rig = localRig()
		if rig == nil then
			return false
		end
		origin = rig.root.Position
	end
	local flat = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
	if flat.Magnitude < Theme.COMBAT_LOOK_MIN_STUDS then
		return false
	end
	local wanted = yawOf(flat.Unit)
	placement.lookYaw = wanted
	placement.lookAt = os.clock()
	if active then
		yaw = wanted
		faceTarget = nil -- a melee assist still turning the body would turn it away again
	end
	return true
end

-- L1 fix round, items 2 and 3. `handler` is told each time the server placed the local body.
--  * `signalled` true: the server said so (the character's `Placed` and `PlacedSeq`
--    attributes) and `position` is the feet point it named. The body's new position reaches
--    this client a moment before or after the word does, so the body may not be there yet.
--  * `signalled` false: no word, but the body is one the camera had not followed before this
--    frame (a new body, the first frame after a summary), and `position` is its root now.
--  * `far`: the move took the body more than COMBAT_CAMERA_SNAP_STUDS (see readPlacement);
--    always true for a body only just picked up. A view is turned only for a far move.
-- Called from the camera's render step, before the frame's look and facing. Handlers stay for
-- the session; one registered twice is still told once.
function CameraController.OnPlaced(
	handler: (position: Vector3, signalled: boolean, far: boolean) -> ()
): ()
	if table.find(placedHandlers, handler) == nil then
		table.insert(placedHandlers, handler)
	end
end

-- The finger holding the attack button also steers, so a phone player can fire and track
-- with one thumb. The touch is dropped when it ends.
function CameraController.AdoptTouch(input: InputObject): ()
	if not active or input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	cameraTouches[input] = { last = position, pending = Vector2.zero, adopted = true }
end

-- P3: a leap or lunge runs for `seconds`; the pivot may trail the character horizontally
-- meanwhile (the range's combat only). EndMotion cuts it short when the move ends early.
function CameraController.BeginMotion(seconds: number): ()
	if not crowdCombat then
		return
	end
	motionUntil = math.max(motionUntil, os.clock() + math.max(seconds, 0))
end

function CameraController.EndMotion(): ()
	motionUntil = 0
end

-- A short widening of the view in degrees (the range's combat only), e.g. on a leap. Reduce
-- motion keeps it, at a smaller size, as Shake and Kick do.
function CameraController.FovKick(degrees: number): ()
	if not crowdCombat or degrees <= 0 then
		return
	end
	local scaled = if Theme.reducedMotion then degrees * Theme.REDUCED_MOTION_FACTOR else degrees
	fovKick = math.min(fovKick + scaled, FOV_KICK_MAX)
end

-- Trauma-style shake: `amount` (feel.shakeLight / shakeHeavy) adds to a 0-1 trauma that
-- decays; the view moves by trauma squared. Reduce motion keeps it, at a smaller size.
function CameraController.Shake(amount: number): ()
	if amount <= 0 then
		return
	end
	local scaled = if Theme.reducedMotion then amount * Theme.REDUCED_MOTION_FACTOR else amount
	trauma = math.min(trauma + scaled, 1)
end

-- A short upward kick in degrees (feedback.cameraKickDegrees), decaying on its own.
function CameraController.Kick(degrees: number): ()
	local scaled = if Theme.reducedMotion then degrees * Theme.REDUCED_MOTION_FACTOR else degrees
	kickPitch += scaled
end

function CameraController.Destroy(): ()
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	watchPlacement(nil)
	collisionParams = nil
	table.clear(wallClip.rects)
	deactivate()
end

return CameraController
