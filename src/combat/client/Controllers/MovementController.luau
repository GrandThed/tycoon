--!strict
-- Proving Grounds movement (P1, docs/COMBAT_DESIGN.md section 2, docs/INTERFACES.md "P1
-- contracts" decision 4). Client-simulated, server-checked, like all Roblox character
-- physics: the jump, double jump, dash and slam run here on the character the client
-- already owns; `RequestDash` only opens the server's i-frame window and `RequestSlam` asks
-- the server to resolve the slam sphere at its own copy of the root. No damage, no cooldown
-- the server trusts, and no position ever leaves this module.
--
-- Everything is inert outside the range (CameraController.IsRange), so missions keep the
-- stock Humanoid movement untouched. Every number is read through Tuning.Get() at the moment
-- it is used, so a slider in the range panel changes the next jump.
--
-- Controls:
--  * Jump is the stock jump on every device (Space, gamepad A, Roblox's touch jump button);
--    a fresh jump press in the air is the double jump. Keeping the stock button means the
--    phone thumb finds it where every Roblox game puts it.
--  * Dash: Left Shift, gamepad B or X, and a small touch button left of the jump button.
--    While airborne at least `slamMinHeight` above the ground the same press is the ground
--    slam (the button relabels itself), as the contract asks. C is a dedicated slam key.
--  * InputController calls AirHang for an airborne sword swing and SetSpeedMult for ADS.
--
-- Movers are one LinearVelocity on the RootAttachment at a time (dash, slam or hang); a new
-- one replaces the old, and a character respawn simply drops it with the old rig. Movement
-- is gameplay, so reduce motion (every touch device) never shortens or skips it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local Create = require(uiFolder:WaitForChild("Create"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))

local MovementController = {}

local ACTION_DASH = "RangeDash"
local ACTION_SLAM = "RangeSlam"
local MOVER_NAME = "RangeMover"
-- A jump request this soon after leaving the ground is the same press still arriving
-- (JumpRequest repeats while the key is held), never a deliberate double jump.
local AIR_JUMP_DELAY = 0.12
-- Two JumpRequests closer than this are one held press, not a fresh one.
local JUMP_PRESS_GAP = 0.06
-- A slam that has not touched down by then (fell off the map) gives up without firing.
local SLAM_MAX_SECONDS = 3
-- Ground probe length below the feet; beyond it the player counts as very high.
local GROUND_PROBE = 256
-- Below this distance to the floor a slam counts as landed even before the Humanoid reports it.
local SLAM_LAND_DISTANCE = 0.75
local MOVE_INPUT_MIN = 0.1
local MOVER_MAX_FORCE = 1e6

-- Touch buttons, mirrored off Roblox's own jump button (PlayerModule TouchJump rule, the
-- same Theme constants CombatHud uses), so they scale exactly as the stock button does.
-- The smallest phone gives a 70 px jump button, so dash = 56 px and ADS = 49 px, both
-- above the 44 px minimum. Purely visual, so named here.
local DASH_BUTTON_FRACTION = 0.8
local BUTTON_GAP_FRACTION = 0.12
local BUTTON_TEXT_FRACTION = 0.3
local BUTTON_TRANSPARENCY = 0.35
local BUTTON_STROKE_TRANSPARENCY = 0.4
local BUTTON_STROKE = 2
local COLOR_DASH = Color3.fromRGB(92, 155, 235)
local COLOR_SLAM = Color3.fromRGB(230, 120, 70)
local COLOR_COOLING = Color3.fromRGB(70, 74, 84)

type Rig = { character: Model, humanoid: Humanoid, root: BasePart, attachment: Attachment }

local started = false
local connections: { RBXScriptConnection } = {}
local requestDash: RemoteEvent? = nil
local requestSlam: RemoteEvent? = nil

local speedMult = 1
local airJumpUsed = false
local leftGroundAt = 0
local lastJumpRequestAt = 0
local wasAirborne = false
local dashReadyAt = 0
local slamReadyAt = 0
local slamming = false
local slamStartedAt = 0
local mover: LinearVelocity? = nil
local moverToken = 0

local screenGui: ScreenGui? = nil
local dashButton: TextButton? = nil
local dashLabel = ""

local function localRig(): Rig?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local attachment = root:FindFirstChild("RootAttachment")
	if attachment == nil or not attachment:IsA("Attachment") then
		return nil
	end
	return { character = character, humanoid = humanoid, root = root, attachment = attachment }
end

local function isAirborne(rig: Rig): boolean
	return rig.humanoid.FloorMaterial == Enum.Material.Air
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- Studs between the feet and the floor straight below; GROUND_PROBE when nothing is there.
local function heightAboveGround(rig: Rig): number
	local feet = rig.root.Position.Y - rig.root.Size.Y * 0.5 - rig.humanoid.HipHeight
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(list, character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	local result = Workspace:Raycast(
		rig.root.Position,
		Vector3.new(0, -(GROUND_PROBE + rig.root.Position.Y - feet), 0),
		groundParams
	)
	if result == nil then
		return GROUND_PROBE
	end
	return math.max(feet - result.Position.Y, 0)
end

local function clearMover(): ()
	moverToken += 1
	local current = mover
	mover = nil
	if current ~= nil then
		current:Destroy()
	end
end

-- One LinearVelocity at a time. `plane` constrains only X/Z (gravity and slopes still act);
-- otherwise the whole vector is held, which is what makes an air dash hold its altitude.
local function setMover(rig: Rig, velocity: Vector3, plane: boolean, seconds: number?): ()
	clearMover()
	local constraint = Instance.new("LinearVelocity")
	constraint.Name = MOVER_NAME
	constraint.Attachment0 = rig.attachment
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	if plane then
		constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		constraint.PrimaryTangentAxis = Vector3.xAxis
		constraint.SecondaryTangentAxis = Vector3.zAxis
		constraint.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	else
		constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		constraint.VectorVelocity = velocity
	end
	constraint.MaxForce = MOVER_MAX_FORCE
	constraint.Parent = rig.root
	mover = constraint
	local lifetime = seconds
	if lifetime ~= nil then
		local token = moverToken
		task.delay(lifetime, function()
			if token == moverToken then
				clearMover()
			end
		end)
	end
end

local function jumpSpeed(height: number): number
	return math.sqrt(2 * Workspace.Gravity * math.max(height, 0))
end

local function flatLook(): Vector3
	local _, look = CameraController.GetAimRay()
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0 then flat.Unit else Vector3.new(0, 0, -1)
end

local function canSlam(rig: Rig): boolean
	local cfg = Tuning.Get().movement
	return isAirborne(rig)
		and not slamming
		and os.clock() >= slamReadyAt
		and heightAboveGround(rig) >= cfg.slamMinHeight
end

local function startSlam(rig: Rig): ()
	local cfg = Tuning.Get().movement
	slamming = true
	slamStartedAt = os.clock()
	setMover(rig, Vector3.new(0, -cfg.slamFallSpeed, 0), false, nil)
end

local function finishSlam(landed: boolean): ()
	slamming = false
	clearMover()
	if not landed then
		return
	end
	slamReadyAt = os.clock() + Tuning.Get().movement.slamCooldown
	local remote = requestSlam
	if remote ~= nil then
		remote:FireServer()
	end
end

local function dashOrSlam(): ()
	local rig = localRig()
	if rig == nil or slamming then
		return
	end
	if canSlam(rig) then
		startSlam(rig)
		return
	end
	local now = os.clock()
	if now < dashReadyAt then
		return
	end
	local cfg = Tuning.Get().movement
	local move = rig.humanoid.MoveDirection
	local flat = Vector3.new(move.X, 0, move.Z)
	local direction = if flat.Magnitude > MOVE_INPUT_MIN then flat.Unit else flatLook()
	local seconds = math.max(cfg.dashSeconds, 1 / 60)
	dashReadyAt = now + cfg.dashCooldown
	-- In the air the dash holds altitude (a readable burst); on the ground only the plane is
	-- driven so steps and slopes still work.
	setMover(rig, direction * (cfg.dashDistance / seconds), not isAirborne(rig), seconds)
	local remote = requestDash
	if remote ~= nil then
		remote:FireServer(direction)
	end
end

local function slamOnly(): ()
	local rig = localRig()
	if rig ~= nil and canSlam(rig) then
		startSlam(rig)
	end
end

local function onJumpRequest(): ()
	local now = os.clock()
	local fresh = now - lastJumpRequestAt >= JUMP_PRESS_GAP
	lastJumpRequestAt = now
	local rig = localRig()
	if rig == nil or not fresh or airJumpUsed or slamming or not isAirborne(rig) then
		return
	end
	if now - leftGroundAt < AIR_JUMP_DELAY then
		return
	end
	airJumpUsed = true
	local height = Tuning.Get().movement.doubleJumpHeight
	-- JumpHeight drives the Jumping state's own impulse; the velocity write makes the double
	-- jump identical whether or not the state machine re-applies it this frame.
	rig.humanoid.JumpHeight = height
	rig.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	local velocity = rig.root.AssemblyLinearVelocity
	rig.root.AssemblyLinearVelocity = Vector3.new(velocity.X, jumpSpeed(height), velocity.Z)
end

local function refreshDashButton(rig: Rig?): ()
	local button = dashButton
	if button == nil then
		return
	end
	local label = "Dash"
	local color = COLOR_DASH
	if slamming or (rig ~= nil and canSlam(rig)) then
		label = "Slam"
		color = COLOR_SLAM
	elseif os.clock() < dashReadyAt then
		color = COLOR_COOLING
	end
	-- Polled every frame, so only a change touches the instance.
	if label ~= dashLabel then
		dashLabel = label
		button.Text = label
	end
	if button.BackgroundColor3 ~= color then
		button.BackgroundColor3 = color
	end
end

local function step(): ()
	local rig = localRig()
	if rig == nil then
		slamming = false
		refreshDashButton(nil)
		return
	end
	local cfg = Tuning.Get().movement
	local humanoid = rig.humanoid
	local airborne = isAirborne(rig)
	if airborne and not wasAirborne then
		leftGroundAt = os.clock()
	end
	wasAirborne = airborne
	humanoid.UseJumpPower = false
	if not airborne then
		airJumpUsed = false
		humanoid.JumpHeight = cfg.jumpHeight
	end
	humanoid.WalkSpeed = cfg.walkSpeed * speedMult

	if slamming then
		if not airborne or heightAboveGround(rig) <= SLAM_LAND_DISTANCE then
			finishSlam(true)
		elseif os.clock() - slamStartedAt > SLAM_MAX_SECONDS then
			finishSlam(false)
		end
	end
	refreshDashButton(rig)
end

local function onAction(
	action: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if action == ACTION_DASH then
		dashOrSlam()
	elseif action == ACTION_SLAM then
		slamOnly()
	end
	return Enum.ContextActionResult.Sink
end

-- Roblox's touch jump button rect for this viewport: (top-left, size) in pixels.
function MovementController.JumpButtonRect(viewport: Vector2): (Vector2, number)
	local small = math.min(viewport.X, viewport.Y) <= Theme.COMBAT_JUMP_SMALL_AXIS
	local size = if small then Theme.COMBAT_JUMP_SMALL_SIZE else Theme.COMBAT_JUMP_LARGE_SIZE
	local fromRight = size * Theme.COMBAT_JUMP_RIGHT_FACTOR - Theme.COMBAT_JUMP_RIGHT_TRIM
	local fromBottom = if small
		then size + Theme.COMBAT_JUMP_SMALL_BOTTOM_PAD
		else size * Theme.COMBAT_JUMP_LARGE_BOTTOM_FACTOR
	return Vector2.new(viewport.X - fromRight, viewport.Y - fromBottom), size
end

-- Round, semi-transparent touch button with a stroke; the caller positions it.
function MovementController.MakeTouchButton(
	name: string,
	text: string,
	parent: Instance
): TextButton
	local button = Create("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLOR_DASH,
		BackgroundTransparency = BUTTON_TRANSPARENCY,
		AutoButtonColor = true,
		Font = Theme.FONT,
		Text = text,
		TextColor3 = Theme.COLOR_TEXT,
		TextScaled = false,
		Parent = parent,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = button })
	Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = button })
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT,
		Transparency = BUTTON_STROKE_TRANSPARENCY,
		Thickness = BUTTON_STROKE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = button,
	})
	return button
end

-- Size and centre of a satellite button `fraction` of the jump size, placed `side` of it.
function MovementController.SatelliteRect(
	viewport: Vector2,
	fraction: number,
	side: "left" | "above"
): (Vector2, number)
	local jumpTopLeft, jumpSize = MovementController.JumpButtonRect(viewport)
	local size = math.max(math.floor(jumpSize * fraction + 0.5), Theme.TAP_TARGET_MIN)
	local gap = jumpSize * BUTTON_GAP_FRACTION
	local jumpCentre = jumpTopLeft + Vector2.new(jumpSize, jumpSize) * 0.5
	if side == "left" then
		return Vector2.new(jumpTopLeft.X - gap - size * 0.5, jumpCentre.Y), size
	end
	return Vector2.new(jumpCentre.X, jumpTopLeft.Y - gap - size * 0.5), size
end

function MovementController.TextSize(size: number): number
	return math.floor(size * BUTTON_TEXT_FRACTION)
end

local function layoutButtons(): ()
	local button = dashButton
	local camera = Workspace.CurrentCamera
	if button == nil or camera == nil then
		return
	end
	local centre, size =
		MovementController.SatelliteRect(camera.ViewportSize, DASH_BUTTON_FRACTION, "left")
	button.Position = UDim2.fromOffset(centre.X, centre.Y)
	button.Size = UDim2.fromOffset(size, size)
	button.TextSize = MovementController.TextSize(size)
end

local function buildTouchControls(): ()
	if not UserInputService.TouchEnabled then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Offsets are already physical pixels mirrored off the stock jump button, which no
	-- UIScale touches; a UIScale here would pull the dash button off its neighbour.
	local gui = Create("ScreenGui", {
		Name = "RangeMovement",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	screenGui = gui
	local button = MovementController.MakeTouchButton("Dash", "Dash", gui)
	dashButton = button
	dashLabel = "Dash"
	-- Press, not release: a dodge that waits for the finger to lift is a late dodge.
	table.insert(connections, button.MouseButton1Down:Connect(dashOrSlam))
	layoutButtons()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		table.insert(
			connections,
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutButtons)
		)
	end
end

function MovementController.Init(): () end

function MovementController.Start(): ()
	if started or not CameraController.IsRange() then
		return
	end
	started = true
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		requestDash =
			remotes:WaitForChild("RequestDash", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		requestSlam =
			remotes:WaitForChild("RequestSlam", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if requestDash == nil or requestSlam == nil then
			warn("[MovementController] RequestDash/RequestSlam missing — moves stay local only")
		end
	end)
	table.insert(connections, RunService.Heartbeat:Connect(step))
	table.insert(connections, UserInputService.JumpRequest:Connect(onJumpRequest))
	table.insert(
		connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			clearMover()
			slamming = false
			airJumpUsed = false
			wasAirborne = false
		end)
	)
	-- Above the stock bindings, so Left Shift dashes instead of toggling shift-lock.
	local priority = Enum.ContextActionPriority.High.Value
	ContextActionService:BindActionAtPriority(
		ACTION_DASH,
		onAction,
		false,
		priority,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:BindActionAtPriority(
		ACTION_SLAM,
		onAction,
		false,
		priority,
		Enum.KeyCode.C
	)
	buildTouchControls()
end

-- ADS slows the walk; InputController owns the ADS state and pushes the multiplier.
function MovementController.SetSpeedMult(mult: number): ()
	speedMult = math.max(mult, 0)
end

-- An airborne sword swing holds the character in place for `seconds` (the "air attack"
-- hang). A dash or slam in progress wins: the hang never cancels a committed move.
function MovementController.AirHang(seconds: number): ()
	local rig = localRig()
	if rig == nil or slamming or seconds <= 0 or not isAirborne(rig) then
		return
	end
	if mover ~= nil then
		return
	end
	setMover(rig, Vector3.zero, false, seconds)
end

function MovementController.IsAirborne(): boolean
	local rig = localRig()
	return rig ~= nil and isAirborne(rig)
end

function MovementController.IsSlamming(): boolean
	return slamming
end

function MovementController.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	ContextActionService:UnbindAction(ACTION_DASH)
	ContextActionService:UnbindAction(ACTION_SLAM)
	clearMover()
	local gui = screenGui
	screenGui = nil
	dashButton = nil
	if gui ~= nil then
		gui:Destroy()
	end
	started = false
end

return MovementController
