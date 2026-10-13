--!strict
-- Proving Grounds movement (P1, docs/COMBAT_DESIGN.md section 2, docs/INTERFACES.md "P1
-- contracts" decision 4). Client-simulated, server-checked, like all Roblox character
-- physics: the jump, double jump, dash and slam run here on the character the client
-- already owns; `RequestDash` only opens the server's i-frame window and `RequestSlam` asks
-- the server to resolve the slam sphere at its own copy of the root. No damage, no cooldown
-- the server trusts, and no position ever leaves this module.
--
-- Everything is inert unless the range's combat runs (CameraController.IsCrowdCombat: the range
-- and, since P5, every crowd mission), so a build without it keeps the stock Humanoid movement
-- untouched. Every number is read through Tuning.Get() at the moment it is used, so a slider in
-- the range panel changes the next jump.
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
-- P3 abilities (docs/INTERFACES.md "P3 contracts", rulings 3 and 5): Leap Smash and Impale
-- Dash move the character here, as the dash does; the server resolves their damage from its
-- own numbers, so the path is presentation plus the player's real position. Both own the
-- character's motion while they run: jump, double jump, dash, slam and the air hang all wait,
-- and the stock jump is disabled on the Humanoid. Whirlwind only scales the walk (Channel).
-- A respawn or death drops every one of them.
--
-- Movers are one LinearVelocity on the RootAttachment at a time (dash, slam, hang, leap,
-- lunge or knock); a new one replaces the old, and a character respawn simply drops it with
-- the old rig. Movement is gameplay, so reduce motion (every touch device) never shortens or
-- skips it.
--
-- P4 (docs/INTERFACES.md "P4 contracts", rulings 4 and 6): enemies hit back, and the victim's
-- own client moves its character. ApplyKnock carries it off with a hit that knocks back or
-- launches; SetDown lays it on the floor until the server's get-up time. VitalsController
-- decides when (it hears the server's `hurt` effects); the rules of who moves the character
-- stay here: a committed move beats a knock, and being down beats everything.
--
-- The touch cluster (jump, dash, aim, two abilities, slot) is laid out here in one place
-- (ClusterRect) so the six buttons can never be placed against each other by two owners.

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

export type ClusterKey = "dash" | "aim" | "abilityMelee" | "abilityRanged" | "slot"

local ACTION_DASH = "RangeDash"
local ACTION_SLAM = "RangeSlam"
local MOVER_NAME = "RangeMover"
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
-- Ability motion follows a planned path: the mover gets the path's own velocity plus this much
-- per second of the gap to the planned point, capped so a wall in the way is pushed against
-- gently rather than at full mover force.
local MOTION_CORRECTION_GAIN = 12
local MOTION_CORRECTION_MAX = 60
-- A landing leap arrives falling fast; beyond this it would punch through a thin floor.
local MOTION_LAND_SPEED_MAX = 60
-- The lunge's wall probe: about the character's half-width, so it stops where the body would.
local LUNGE_PROBE_RADIUS = 1
local LEAP_FOV_KICK_DEGREES = 8
local LUNGE_FOV_KICK_DEGREES = 4
-- P4 knocked down: the constraint that lays the body flat, how firmly it turns it (the
-- AlignOrientation scale, 0-200), and how far under a lying root the floor is looked for.
local DOWN_ALIGN_NAME = "RangeDown"
local DOWN_RESPONSIVENESS = 60
local DOWN_FLOOR_PROBE = 12

-- Touch buttons, mirrored off Roblox's own jump button (PlayerModule TouchJump rule, the
-- same Theme constants CombatHud uses), so they scale exactly as the stock button does.
-- On the smallest phone (70 px jump): dash 56 px, aim 49, abilities 60, slot 49, every one
-- above the 44 px minimum. Purely visual, so named here.
local DASH_BUTTON_FRACTION = 0.8
local AIM_BUTTON_FRACTION = 0.7
local ABILITY_BUTTON_FRACTION = 0.85
local SLOT_BUTTON_FRACTION = 0.7
local BUTTON_GAP_FRACTION = 0.12
local BUTTON_TEXT_FRACTION = 0.3
local BUTTON_TRANSPARENCY = 0.35
local BUTTON_STROKE_TRANSPARENCY = 0.4
local BUTTON_STROKE = 2
local COLOR_DASH = Color3.fromRGB(92, 155, 235)
local COLOR_SLAM = Color3.fromRGB(230, 120, 70)
local COLOR_COOLING = Color3.fromRGB(70, 74, 84)

type Rig = { character: Model, humanoid: Humanoid, root: BasePart, attachment: Attachment }

-- A leap or a lunge in flight. The root runs from `from` to `to` in `seconds`: straight and
-- level for a lunge, along a vertical parabola (launch speed `rise`, gravity `gravity`) for a
-- leap. `plane` = a grounded lunge, which drives only X/Z so slopes and steps still work.
type Motion = {
	humanoid: Humanoid,
	startedAt: number,
	seconds: number,
	from: Vector3,
	to: Vector3,
	rise: number,
	gravity: number,
	plane: boolean,
}

local started = false
local connections: { RBXScriptConnection } = {}
local requestDash: RemoteEvent? = nil
local requestSlam: RemoteEvent? = nil

local speedMult = 1
local channelMult = 1
local channelUntil = 0
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
local motion: Motion? = nil
-- os.clock() until which the last dash's mover runs: a dash in progress is a committed move.
local dashUntil = 0
-- P4. knock = the horizontal speed a hit gave the character that has not bled off yet (zero =
-- none); knockToken = the moverToken of its mover, so any move that takes the mover ends it.
local knock = Vector3.zero
local knockToken = 0
local knockedDown = false
local downAlign: AlignOrientation? = nil

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

-- Root height above the floor when standing, the same measure RangeService uses: R15's
-- HipHeight runs from the floor to the bottom of the root.
local function standingOffset(rig: Rig): number
	return rig.humanoid.HipHeight + rig.root.Size.Y * 0.5
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- World queries skip every player character; crowd enemies have no Instances at all.
local function refreshGroundParams(): RaycastParams
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(list, character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	return groundParams
end

-- Studs between the feet and the floor straight below; GROUND_PROBE when nothing is there.
local function heightAboveGround(rig: Rig): number
	local feet = rig.root.Position.Y - rig.root.Size.Y * 0.5 - rig.humanoid.HipHeight
	local result = Workspace:Raycast(
		rig.root.Position,
		Vector3.new(0, -(GROUND_PROBE + rig.root.Position.Y - feet), 0),
		refreshGroundParams()
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

-- Ability motion ---------------------------------------------------------------------------

-- The planned root position and velocity `t` seconds into a motion.
local function motionAt(current: Motion, t: number): (Vector3, Vector3)
	local seconds = current.seconds
	local share = math.clamp(t / seconds, 0, 1)
	local span = current.to - current.from
	local flatVelocity = Vector3.new(span.X, 0, span.Z) / seconds
	local y = current.from.Y + current.rise * t - current.gravity * t * t * 0.5
	local position =
		Vector3.new(current.from.X + span.X * share, y, current.from.Z + span.Z * share)
	return position, flatVelocity + Vector3.new(0, current.rise - current.gravity * t, 0)
end

-- Ends the running leap or lunge. `arrived` = it ran its full time, so the character keeps
-- only its fall (never the path's horizontal speed, which would slide it past the target).
-- An interrupted motion (death, respawn, a cancel) just lets go.
local function endMotion(arrived: boolean): ()
	local current = motion
	if current == nil then
		return
	end
	motion = nil
	clearMover()
	CameraController.EndMotion()
	local humanoid = current.humanoid
	if humanoid.Parent == nil then
		return
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	if not arrived then
		return
	end
	local rig = localRig()
	if rig ~= nil and rig.humanoid == humanoid then
		local velocity = rig.root.AssemblyLinearVelocity
		rig.root.AssemblyLinearVelocity =
			Vector3.new(0, math.max(math.min(velocity.Y, 0), -MOTION_LAND_SPEED_MAX), 0)
	end
end

local function beginMotion(rig: Rig, current: Motion, fovKick: number): ()
	-- A leap or lunge takes the character from any dash, hang or slam in progress; the slam
	-- simply never fires (no RequestSlam), so the server sees nothing to resolve.
	endMotion(false)
	slamming = false
	motion = current
	rig.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	local _, velocity = motionAt(current, 0)
	setMover(rig, velocity, current.plane, nil)
	CameraController.BeginMotion(current.seconds)
	CameraController.FovKick(fovKick)
end

-- Drives the mover along the planned path: the path's own velocity plus a capped pull back
-- onto it, so a bump or a frame hitch never leaves the character off course.
local function stepMotion(rig: Rig?): ()
	local current = motion
	if current == nil then
		return
	end
	if rig == nil or rig.humanoid ~= current.humanoid then
		endMotion(false)
		return
	end
	local t = os.clock() - current.startedAt
	if t >= current.seconds then
		endMotion(true)
		return
	end
	local wanted, velocity = motionAt(current, t)
	local gap = wanted - rig.root.Position
	if current.plane then
		gap = Vector3.new(gap.X, 0, gap.Z)
	end
	local correction = gap * MOTION_CORRECTION_GAIN
	if correction.Magnitude > MOTION_CORRECTION_MAX then
		correction = correction.Unit * MOTION_CORRECTION_MAX
	end
	local drive = velocity + correction
	local constraint = mover
	if constraint == nil then
		setMover(rig, drive, current.plane, nil)
	elseif current.plane then
		constraint.PlaneVelocity = Vector2.new(drive.X, drive.Z)
	else
		constraint.VectorVelocity = drive
	end
end

-- Movement ---------------------------------------------------------------------------------

local function canSlam(rig: Rig): boolean
	local cfg = Tuning.Get().movement
	return isAirborne(rig)
		and not slamming
		and not knockedDown
		and motion == nil
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
	-- A leap or lunge owns the character's motion (P3 ruling 3); a downed body has no moves
	-- (P4: the server refuses the dash too, so none is sent).
	if rig == nil or slamming or motion ~= nil or knockedDown then
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
	dashUntil = now + seconds
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
	if
		rig == nil
		or not fresh
		or airJumpUsed
		or slamming
		or knockedDown
		or motion ~= nil
		or not isAirborne(rig)
	then
		return
	end
	-- A request this soon after leaving the ground is the same press still arriving
	-- (JumpRequest repeats while the key is held), never a deliberate double jump.
	if now - leftGroundAt < Tuning.Get().movement.airJumpDelay then
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
	elseif knockedDown or motion ~= nil or os.clock() < dashReadyAt then
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

local function resetAbilityState(): ()
	endMotion(false)
	channelUntil = 0
	channelMult = 1
end

-- P4 knock and down ------------------------------------------------------------------------

-- Bleeds the knock off at player.knockFriction, in the air as on the ground, so
-- knockback / knockFriction is how long a hit carries the player. A dash, slam, leap, lunge
-- or hang that took the mover since has already ended it.
local function stepKnock(rig: Rig?, deltaTime: number): ()
	if knock == Vector3.zero then
		return
	end
	local constraint = mover
	if rig == nil or constraint == nil or knockToken ~= moverToken then
		knock = Vector3.zero
		return
	end
	local speed = knock.Magnitude
	local friction = math.max(Tuning.Get().player.knockFriction, 0)
	-- No friction would be a slide that never ends: the knock stops instead.
	local slowed = if friction > 0 then speed - friction * deltaTime else 0
	if slowed <= 0 then
		knock = Vector3.zero
		clearMover()
		return
	end
	knock *= slowed / speed
	constraint.PlaneVelocity = Vector2.new(knock.X, knock.Z)
end

-- Lays the body on its back with its head toward `away` (the way the blow was travelling).
-- PlatformStand stops the Humanoid balancing and CameraController turning the root; the align
-- does the rest, so the pose is the same every time instead of wherever physics drops it.
local function layDown(rig: Rig, away: Vector3?): ()
	local flat = if away ~= nil then Vector3.new(away.X, 0, away.Z) else Vector3.zero
	local back = if flat.Magnitude > MOVE_INPUT_MIN then flat.Unit else -flatLook()
	local align = Instance.new("AlignOrientation")
	align.Name = DOWN_ALIGN_NAME
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = rig.attachment
	-- Facing the blow, then tipped a quarter turn about its own right axis: face up, head
	-- along `back`.
	align.CFrame = CFrame.lookAt(Vector3.zero, -back) * CFrame.Angles(math.pi / 2, 0, 0)
	align.MaxTorque = MOVER_MAX_FORCE
	align.Responsiveness = DOWN_RESPONSIVENESS
	align.Parent = rig.root
	downAlign = align
	rig.humanoid.PlatformStand = true
end

-- Stands the body up where it lies: upright over the floor under it, facing the camera's way,
-- with nothing left of the fall. From this frame CameraController turns the root again.
local function standUp(rig: Rig?): ()
	local align = downAlign
	downAlign = nil
	if align ~= nil then
		align:Destroy()
	end
	if rig == nil then
		return
	end
	local root = rig.root
	local position = root.Position
	local floor =
		Workspace:Raycast(position, Vector3.new(0, -DOWN_FLOOR_PROBE, 0), refreshGroundParams())
	-- A lying root is lower than a standing one; left there, the legs would start in the floor.
	local standing = if floor ~= nil
		then Vector3.new(position.X, floor.Position.Y + standingOffset(rig), position.Z)
		else position
	rig.humanoid.PlatformStand = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(standing, standing + flatLook())
	rig.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

local function step(deltaTime: number): ()
	local rig = localRig()
	stepMotion(rig)
	stepKnock(rig, deltaTime)
	if rig == nil then
		slamming = false
		channelUntil = 0
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
	if knockedDown then
		-- No walk and no jump, and the pose is put back if anything stood the Humanoid up.
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		if not humanoid.PlatformStand then
			humanoid.PlatformStand = true
		end
		refreshDashButton(rig)
		return
	end
	if not airborne then
		airJumpUsed = false
		humanoid.JumpHeight = cfg.jumpHeight
	end
	local channel = if os.clock() < channelUntil then channelMult else 1
	humanoid.WalkSpeed = cfg.walkSpeed * speedMult * channel

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

-- The right-thumb cluster around Roblox's jump button, two rows:
--   top:     [melee ability] [ranged ability] [aim]
--   bottom:  [slot]          [dash]           [jump]
-- Q sits left of E as on a keyboard. Every neighbour is at least one gap (12% of the jump
-- size) apart, and the top row stays below one jump size above the jump button, the band the
-- range panel already reserves. (centre, size) in pixels.
function MovementController.ClusterRect(viewport: Vector2, key: ClusterKey): (Vector2, number)
	local _, jumpSize = MovementController.JumpButtonRect(viewport)
	local gap = jumpSize * BUTTON_GAP_FRACTION
	local dashCentre, dashSize =
		MovementController.SatelliteRect(viewport, DASH_BUTTON_FRACTION, "left")
	if key == "dash" then
		return dashCentre, dashSize
	end
	local aimCentre, aimSize =
		MovementController.SatelliteRect(viewport, AIM_BUTTON_FRACTION, "above")
	if key == "aim" then
		return aimCentre, aimSize
	end
	if key == "slot" then
		local size =
			math.max(math.floor(jumpSize * SLOT_BUTTON_FRACTION + 0.5), Theme.TAP_TARGET_MIN)
		return Vector2.new(dashCentre.X - dashSize * 0.5 - gap - size * 0.5, dashCentre.Y), size
	end
	local size =
		math.max(math.floor(jumpSize * ABILITY_BUTTON_FRACTION + 0.5), Theme.TAP_TARGET_MIN)
	local rangedX = aimCentre.X - aimSize * 0.5 - gap - size * 0.5
	if key == "abilityRanged" then
		return Vector2.new(rangedX, aimCentre.Y), size
	end
	return Vector2.new(rangedX - size - gap, aimCentre.Y), size
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
	local centre, size = MovementController.ClusterRect(camera.ViewportSize, "dash")
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
	if started or not CameraController.IsCrowdCombat() then
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
			resetAbilityState()
			clearMover()
			slamming = false
			airJumpUsed = false
			wasAirborne = false
			-- A new body stands, unshoved: the align went with the old rig.
			dashUntil = 0
			knock = Vector3.zero
			knockedDown = false
			downAlign = nil
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
-- hang). A dash, slam, leap, lunge or knock in progress wins: the hang never cancels a
-- committed move, and never holds a body a hit is carrying off.
function MovementController.AirHang(seconds: number): ()
	local rig = localRig()
	if
		rig == nil
		or slamming
		or knockedDown
		or motion ~= nil
		or seconds <= 0
		or not isAirborne(rig)
	then
		return
	end
	if mover ~= nil then
		return
	end
	setMover(rig, Vector3.zero, false, seconds)
end

-- Leap Smash: an arc from the root to stand on `ground` (a floor point, InputController's
-- ruling-4 mirror) in `seconds`, the apex `height` above the higher end. Returns false when
-- there is no character or no time to leap in.
function MovementController.Leap(ground: Vector3, seconds: number, height: number): boolean
	local rig = localRig()
	if not started or rig == nil or knockedDown or seconds <= 0 then
		return false
	end
	local from = rig.root.Position
	local to = ground + Vector3.new(0, standingOffset(rig), 0)
	local apex = math.max(from.Y, to.Y) + math.max(height, 0)
	-- Rise to the apex and fall from it in `seconds` total under one constant gravity:
	-- T = sqrt(2/g) (sqrt(up) + sqrt(down)), so g = 2 (sqrt(up) + sqrt(down))^2 / T^2.
	local up = math.sqrt(math.max(apex - from.Y, 0))
	local down = math.sqrt(math.max(apex - to.Y, 0))
	local gravity = 2 * (up + down) ^ 2 / (seconds * seconds)
	beginMotion(rig, {
		humanoid = rig.humanoid,
		startedAt = os.clock(),
		seconds = seconds,
		from = from,
		to = to,
		rise = math.sqrt(2 * gravity * math.max(apex - from.Y, 0)),
		gravity = gravity,
		plane = false,
	}, LEAP_FOV_KICK_DEGREES)
	return true
end

-- Impale Dash: `distance` studs along the flattened `direction` in `seconds`, stopped short
-- of the first wall. On the ground only X/Z are driven (slopes and steps still act); in the
-- air it holds its altitude, as the air dash does.
function MovementController.Lunge(direction: Vector3, distance: number, seconds: number): boolean
	local rig = localRig()
	if not started or rig == nil or knockedDown or seconds <= 0 then
		return false
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local unit = if flat.Magnitude > MOVE_INPUT_MIN then flat.Unit else flatLook()
	local from = rig.root.Position
	local reach = math.max(distance, 0)
	if reach > 0 then
		local hit =
			Workspace:Spherecast(from, LUNGE_PROBE_RADIUS, unit * reach, refreshGroundParams())
		if hit ~= nil then
			reach = math.max(hit.Distance, 0)
		end
	end
	beginMotion(rig, {
		humanoid = rig.humanoid,
		startedAt = os.clock(),
		seconds = seconds,
		from = from,
		to = from + unit * reach,
		rise = 0,
		gravity = 0,
		plane = not isAirborne(rig),
	}, LUNGE_FOV_KICK_DEGREES)
	return true
end

-- Whirlwind: the walk runs at `mult` for `seconds`, on top of any ADS slow-down.
function MovementController.Channel(seconds: number, mult: number): ()
	channelUntil = os.clock() + math.max(seconds, 0)
	channelMult = math.max(mult, 0)
end

-- Drops a running leap, lunge or channel (the server refused the cast or the family changed).
function MovementController.CancelAbility(): ()
	resetAbilityState()
end

-- True while a leap or lunge owns the character's motion.
function MovementController.IsAbilityMoving(): boolean
	return motion ~= nil
end

function MovementController.IsAirborne(): boolean
	local rig = localRig()
	return rig ~= nil and isAirborne(rig)
end

function MovementController.IsSlamming(): boolean
	return slamming
end

-- P4 ruling 6: a hit that knocks back or launches moves its victim, on the victim's own
-- client. `push` is a horizontal velocity change in studs/s (its Y is ignored) and `launch`
-- an apex height in studs: the units CrowdService.Damage gives the same numbers on an enemy.
-- The push is capped at crowd.knockMax and bleeds off at player.knockFriction (stepKnock).
--
-- Who wins: a committed move does. While a dash, a slam, a leap or a lunge runs, the knock is
-- dropped whole (the hit still shows and still costs health); an air hang gives way to it. A
-- knock drives X and Z only, so a double jump still lifts through it, and the next dash,
-- slam, leap or lunge takes the character over from it. A body being knocked down takes the
-- knock regardless: SetDown has just ended its moves.
function MovementController.ApplyKnock(push: Vector3, launch: number): ()
	local rig = localRig()
	if not started or rig == nil then
		return
	end
	if not knockedDown and (motion ~= nil or slamming or os.clock() < dashUntil) then
		return
	end
	local config = Tuning.Get()
	local friction = config.player.knockFriction
	local flat = Vector3.new(push.X, 0, push.Z)
	local speed = flat.Magnitude
	local cap = math.max(config.crowd.knockMax, 0)
	-- A NaN speed fails the first test; without friction the slide would never end.
	if not (speed > 0 and speed < math.huge) or friction <= 0 then
		flat = Vector3.zero
	elseif speed > cap then
		flat = if cap > 0 then flat.Unit * cap else Vector3.zero
	end
	local lift = if launch > 0 and launch < math.huge then jumpSpeed(launch) else 0
	if flat == Vector3.zero and lift <= 0 then
		return
	end
	-- Only a hang or an older knock can still hold the mover here, and both give way.
	clearMover()
	knock = Vector3.zero
	if lift > 0 then
		if not knockedDown then
			-- Off the Humanoid's floor hold first: on the ground it would swallow the lift.
			rig.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		local velocity = rig.root.AssemblyLinearVelocity
		rig.root.AssemblyLinearVelocity =
			Vector3.new(velocity.X, math.max(velocity.Y, lift), velocity.Z)
	end
	if flat ~= Vector3.zero then
		knock = flat
		setMover(rig, flat, true, nil)
		knockToken = moverToken
		-- The camera trails the slide, as it does a lunge, instead of the world snapping past.
		CameraController.BeginMotion(flat.Magnitude / friction)
	end
end

-- P4 ruling 4: knocked down until the caller stands the body up again. Health never reaches
-- 0 in the range, so this is not a death and nothing respawns. Going down ends every move in
-- progress (dash, slam, leap, lunge, hang, knock, the Whirlwind walk) and none starts while
-- down: no walk, jump, double jump, dash or slam. `away` = the way the blow was travelling;
-- the body lands on its back with its head that way. The knock that came with the same blow
-- is applied after this call.
function MovementController.SetDown(isDown: boolean, away: Vector3?): ()
	if not started or isDown == knockedDown then
		return
	end
	knockedDown = isDown
	local rig = localRig()
	if not isDown then
		standUp(rig)
		return
	end
	resetAbilityState()
	slamming = false
	knock = Vector3.zero
	clearMover()
	if rig ~= nil then
		layDown(rig, away)
	end
end

-- True while knocked down: InputController sends no attack, cast or slot switch meanwhile.
function MovementController.IsDown(): boolean
	return knockedDown
end

function MovementController.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	ContextActionService:UnbindAction(ACTION_DASH)
	ContextActionService:UnbindAction(ACTION_SLAM)
	resetAbilityState()
	clearMover()
	knock = Vector3.zero
	if knockedDown then
		knockedDown = false
		standUp(localRig())
	end
	local gui = screenGui
	screenGui = nil
	dashButton = nil
	if gui ~= nil then
		gui:Destroy()
	end
	started = false
end

return MovementController
