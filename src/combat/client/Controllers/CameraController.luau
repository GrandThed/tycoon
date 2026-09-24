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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local BIND_NAME = "CombatShoulderCamera"
local ENEMIES_FOLDER = "Enemies"
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

local function cursorFree(): boolean
	return freePhases[phase] == true or next(cursorHolds) ~= nil or altFree
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
end

local function bindHumanoid(rig: Rig): ()
	boundHumanoid = rig.humanoid
	rig.humanoid.AutoRotate = false
	yaw = yawOf(rig.root.CFrame.LookVector)
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

local function update(deltaTime: number): ()
	local camera = currentCamera()
	local rig = localRig()
	if camera == nil or rig == nil or DEFAULT_CAMERA_PHASES[phase] then
		deactivate()
		return
	end
	if not active then
		activate(camera, rig)
	elseif boundHumanoid ~= rig.humanoid then
		bindHumanoid(rig) -- respawned while the shoulder camera stayed up
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable -- something reset it; take it back
	end
	rig.humanoid.AutoRotate = false
	applyMouse(not cursorFree())

	consumeLookInput(deltaTime)
	faceCharacter(rig)

	local params = collisionParamsFor()

	local yawFrame = CFrame.Angles(0, yaw, 0)
	local rotation = yawFrame * CFrame.Angles(pitch, 0, 0)
	local pivot = rig.root.Position + Vector3.new(0, Theme.COMBAT_CAMERA_PIVOT_HEIGHT, 0)
	-- The shoulder offset is pulled in against a wall first, so the camera never starts
	-- its boom from inside the wall the player is hugging.
	local shoulder = yawFrame:VectorToWorldSpace(shoulderOffset)
	local shoulderReach = clearDistance(params, pivot, shoulder)
	local shoulderPoint = if shoulder.Magnitude > 0
		then pivot + shoulder.Unit * shoulderReach
		else pivot
	local boom = rotation:VectorToWorldSpace(Vector3.new(0, 0, zoom))
	local boomReach = clearDistance(params, shoulderPoint, boom)
	local position = shoulderPoint + boom.Unit * boomReach

	local frame = CFrame.new(position) * rotation
	aimFrame = frame
	camera.FieldOfView = cameraConfig.fieldOfView
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
end

function CameraController.Start(): ()
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
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value, update)
end

-- Pushed from every RunState. A new phase re-locks a cursor the player freed with Alt, so
-- the next wave never starts with the pointer loose.
function CameraController.SetPhase(nextPhase: string): ()
	if nextPhase ~= phase then
		altFree = false
	end
	phase = nextPhase
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

-- The finger holding the attack button also steers, so a phone player can fire and track
-- with one thumb. The touch is dropped when it ends.
function CameraController.AdoptTouch(input: InputObject): ()
	if not active or input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	cameraTouches[input] = { last = position, pending = Vector2.zero, adopted = true }
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
	collisionParams = nil
	deactivate()
end

return CameraController
