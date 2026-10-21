--!strict
-- The local player's weapon, on the local character only (C1 contract, docs/INTERFACES.md
-- "Combat client", extended by C2.5 "Combat client"). Four jobs:
--
-- 1. Hold the weapon. Every player's weapons, this one's included, are HeldWeapons' (L3 W2,
--    docs/prompts/l3-w2-contract.md, L3-51 and L3-54): this module starts it and hands it the
--    local stance on the frame of a switch, which the server is never told of.
-- 2. Animate the swing. C2.5 `animations.playerSlash` (steps 1-2) and `playerLunge` (the
--    finisher) play on the Animator when they load; the ids are unverified, so each one is
--    preloaded in a pcall and a failed or 0 id falls back to the procedural Motor6D C0 pose
--    silently (one warn per id). C0 is used, not Transform, so the default Animate script
--    keeps running underneath instead of fighting us. Every pose ends at its rig's rest: the
--    arm hangs, except while a ranged model is in the hand (HeldWeapons.OnHold, on every
--    character): then it is held raised forward at COMBAT_HOLD_RANGED_RAISE_DEGREES, so a gun
--    or a bow points ahead instead of at the ground (contract section 11, ruling 6). A shot's
--    kick and a draw start from that raised arm; a melee swing is unchanged.
-- 3. Trail the strike. A Trail between two hand attachments is lit for the strike leg
--    (`feel.trailSeconds` long), so a swing reads as an arc even with empty hands.
-- 4. Show the instant shot. A hitscan shot the local player fires gets a muzzle flash and a
--    bright bolt that flies from the muzzle (HeldWeapons.Muzzle) to the point the client's own
--    copy of the server's ray reaches, at `feel.arrowSpeed` x COMBAT_BOLT_SPEED_FACTOR.
--    Projectiles and held beams are FeedbackController's, drawn from the server's CombatFxShot.
--
-- Other players' swings (SwingOther: FeedbackController on each of their weapon strikes, L3-53)
-- play the same animation or pose, and the same trail, on THEIR character, locally. Nothing
-- written here replicates, and the owner's client animates its own copy, so the two never
-- fight. Their weapon class is not sent, so a remote swing uses one fixed presentation window.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local Motion = require(uiFolder:WaitForChild("Motion"))
local HeldWeapons = require(script.Parent:WaitForChild("HeldWeapons"))

local MELEE_SLOT = "melee"
local PROJECTILE_NAME = "CombatProjectile"
local MUZZLE_NAME = "CombatMuzzleFlash"
local TRAIL_NAME = "CombatTrail"
local FINISHER_STEP = 3
-- R15 first, R6 second: the placeholder rigs and every real avatar are R15, but a Studio
-- test with an R6 avatar must still pose an arm instead of erroring.
local HAND_NAMES = { "RightHand", "Right Arm" }
local SHOULDER_PARENTS = { "RightUpperArm", "Torso" }
local SHOULDER_NAMES = { "RightShoulder", "Right Shoulder" }
-- Fallbacks for a build with no Combat.json: the feature still renders, just untuned.
local DEFAULT_TRAIL_SECONDS = 0.15
local DEFAULT_ARROW_SPEED = 180

local WeaponController = {}

local combatConfig: Types.CombatConfig? = nil
local stance = MELEE_SLOT

-- One posable shoulder. `token` invalidates the delayed legs of a superseded pose; `track`
-- is the animation playing instead of the procedural pose, when one loaded. `rest` is the
-- angle every pose returns to (degrees from `base`, the hanging arm).
type PoseRig = {
	motor: Motor6D?,
	base: CFrame,
	rest: number,
	tween: Tween?,
	token: number,
	track: AnimationTrack?,
	trackSpeed: number,
	trail: Trail?,
	trailToken: number,
}

local function newPose(motor: Motor6D?): PoseRig
	return {
		motor = motor,
		base = if motor ~= nil then motor.C0 else CFrame.identity,
		rest = 0,
		tween = nil,
		token = 0,
		track = nil,
		trackSpeed = 1,
		trail = nil,
		trailToken = 0,
	}
end

local character: Model? = nil
local localPose: PoseRig = newPose(nil)
-- Other players' rigs, weak-keyed so a respawned or departed character simply drops out.
local remotePoses: { [Model]: PoseRig } = setmetatable({}, { __mode = "k" }) :: any
-- Characters with a ranged model in the hand (HeldWeapons.OnHold), weak-keyed. Kept apart from
-- the pose records, because the news can come before a character's shoulder is found.
local raisedRigs: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local connections: { RBXScriptConnection } = {}

-- Animation id -> "pending" | "ok" | "failed". Only "ok" ids are ever played.
local animationStatus: { [number]: string } = {}
type RigTracks = { slash: AnimationTrack?, lunge: AnimationTrack? }
local rigTracks: { [Humanoid]: RigTracks } = setmetatable({}, { __mode = "k" }) :: any

-- In-flight shots, stepped by one RenderStepped connection that exists only while any fly.
type Projectile = {
	part: BasePart,
	from: Vector3,
	direction: Vector3,
	length: number,
	speed: number,
	startedAt: number,
}
local projectiles: { Projectile } = {}
local flightConnection: RBXScriptConnection? = nil

local function feel(): Types.CombatFeelConfig?
	local cfg = combatConfig
	return if cfg ~= nil then cfg.feel else nil
end

local function trailSeconds(): number
	local f = feel()
	return if f ~= nil then f.trailSeconds else DEFAULT_TRAIL_SECONDS
end

local function arrowSpeed(): number
	local f = feel()
	return if f ~= nil and f.arrowSpeed > 0 then f.arrowSpeed else DEFAULT_ARROW_SPEED
end

local function findFirst(parent: Instance, names: { string }): Instance?
	for _, name in names do
		local found = parent:FindFirstChild(name)
		if found ~= nil then
			return found
		end
	end
	return nil
end

local function handOf(rig: Model): BasePart?
	local hand = findFirst(rig, HAND_NAMES)
	return if hand ~= nil and hand:IsA("BasePart") then hand else nil
end

-- Animations -------------------------------------------------------------------------

local function animationId(step: number): number
	local cfg = combatConfig
	if cfg == nil then
		return 0
	end
	return if step >= FINISHER_STEP then cfg.animations.playerLunge else cfg.animations.playerSlash
end

local function animationFor(id: number): Animation
	return Create("Animation", { AnimationId = "rbxassetid://" .. tostring(id) }) :: Animation
end

-- Fetch once per id, off the caller's thread. A failure is final for the session and is
-- reported once; the procedural pose covers it.
local function preload(id: number): ()
	if id <= 0 or animationStatus[id] ~= nil then
		return
	end
	animationStatus[id] = "pending"
	task.spawn(function()
		local animation = animationFor(id)
		local ok = pcall(function()
			ContentProvider:PreloadAsync(
				{ animation },
				function(_: string, status: Enum.AssetFetchStatus)
					animationStatus[id] = if status == Enum.AssetFetchStatus.Success
						then "ok"
						else "failed"
				end
			)
		end)
		animation:Destroy()
		if not ok or animationStatus[id] ~= "ok" then
			animationStatus[id] = "failed"
			warn(
				("[WeaponController] animation %d did not load; using the procedural swing"):format(
					id
				)
			)
		end
	end)
end

local function loadTrack(humanoid: Humanoid, id: number): AnimationTrack?
	if animationStatus[id] ~= "ok" then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return nil
	end
	local animation = animationFor(id)
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		animationStatus[id] = "failed"
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	return track
end

-- The track for this combo step, or nil when the id is 0, failed or not fetched yet.
local function trackFor(humanoid: Humanoid?, step: number): AnimationTrack?
	if humanoid == nil then
		return nil
	end
	local id = animationId(step)
	if animationStatus[id] ~= "ok" then
		return nil
	end
	local tracks = rigTracks[humanoid]
	if tracks == nil then
		tracks = { slash = nil, lunge = nil }
		rigTracks[humanoid] = tracks
	end
	local set = tracks :: RigTracks
	local finisher = step >= FINISHER_STEP
	local track = if finisher then set.lunge else set.slash
	if track == nil then
		track = loadTrack(humanoid, id)
		if finisher then
			set.lunge = track
		else
			set.slash = track
		end
	end
	-- Length stays 0 until the asset is really in; until then the pose is the swing.
	if track == nil or track.Length <= 0 then
		return nil
	end
	return track
end

-- Trail --------------------------------------------------------------------------------

local function ensureTrail(rig: Model, pose: PoseRig): Trail?
	local existing = pose.trail
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local hand = handOf(rig)
	if hand == nil then
		return nil
	end
	-- A remote rig's pose record is rebuilt when its shoulder is missing; reuse the trail
	-- already on the hand instead of stacking a second one.
	local found = hand:FindFirstChild(TRAIL_NAME)
	if found ~= nil and found:IsA("Trail") then
		pose.trail = found
		return found
	end
	local near = Create("Attachment", {
		Name = TRAIL_NAME .. "Near",
		Position = Vector3.new(0, -Theme.COMBAT_TRAIL_NEAR, 0),
		Parent = hand,
	}) :: Attachment
	local far = Create("Attachment", {
		Name = TRAIL_NAME .. "Far",
		Position = Vector3.new(0, -Theme.COMBAT_TRAIL_FAR, 0),
		Parent = hand,
	}) :: Attachment
	local trail = Create("Trail", {
		Name = TRAIL_NAME,
		Attachment0 = near,
		Attachment1 = far,
		Enabled = false,
		FaceCamera = false,
		Lifetime = trailSeconds(),
		LightEmission = Theme.COMBAT_TRAIL_LIGHT_EMISSION,
		Color = ColorSequence.new(Theme.COLOR_TEXT, Theme.COLOR_HIGHLIGHT),
		Transparency = NumberSequence.new(Theme.COMBAT_TRAIL_TRANSPARENCY, 1),
		Parent = hand,
	}) :: Trail
	pose.trail = trail
	return trail
end

-- Light the trail for the strike leg only, so the ribbon draws the arc and nothing else.
local function flashTrail(pose: PoseRig, delaySeconds: number, seconds: number): ()
	local trail = pose.trail
	if trail == nil then
		return
	end
	pose.trailToken += 1
	local token = pose.trailToken
	task.delay(delaySeconds, function()
		if token ~= pose.trailToken or trail.Parent == nil then
			return
		end
		trail.Enabled = true
		task.delay(math.max(seconds, trailSeconds()), function()
			if token == pose.trailToken then
				trail.Enabled = false
			end
		end)
	end)
end

-- Procedural pose ------------------------------------------------------------------------

local function restOf(rigModel: Model?): number
	return if rigModel ~= nil and raisedRigs[rigModel] == true
		then Theme.COMBAT_HOLD_RANGED_RAISE_DEGREES
		else 0
end

local function restFrame(rig: PoseRig): CFrame
	return rig.base * CFrame.Angles(math.rad(rig.rest), 0, 0)
end

local function cancelRig(rig: PoseRig): ()
	rig.token += 1
	local tween = rig.tween
	rig.tween = nil
	if tween ~= nil then
		tween:Cancel()
	end
	local motor = rig.motor
	if motor ~= nil then
		motor.C0 = restFrame(rig)
	end
end

local function cancelPose(): ()
	cancelRig(localPose)
end

-- One pose leg: tween the shoulder to `degrees` about its own X axis over `seconds`.
local function rigPoseTo(
	rig: PoseRig,
	degrees: number,
	seconds: number,
	style: Enum.EasingStyle
): Tween?
	local motor = rig.motor
	if motor == nil then
		return nil
	end
	local goal = rig.base * CFrame.Angles(math.rad(degrees), 0, 0)
	local tween = TweenService:Create(
		motor,
		Motion.Info(math.max(seconds, 0), style, Enum.EasingDirection.Out),
		{ C0 = goal }
	)
	rig.tween = tween
	tween:Play()
	return tween
end

local function poseTo(degrees: number, seconds: number, style: Enum.EasingStyle): Tween?
	return rigPoseTo(localPose, degrees, seconds, style)
end

-- A new rest, eased to. It changes with the slot in hand, and a switch ends any pose anyway, so
-- a pose still running is superseded.
local function setRest(rig: PoseRig, degrees: number): ()
	if rig.rest == degrees then
		return
	end
	rig.rest = degrees
	if rig.motor == nil then
		return
	end
	rig.token += 1
	local tween = rig.tween
	rig.tween = nil
	if tween ~= nil then
		tween:Cancel()
	end
	rigPoseTo(rig, degrees, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)
end

-- Wind up against the swing, then strike through it, then settle, all inside
-- `windowSeconds` so the pose and the server's combo clock agree. An animation that loaded
-- replaces the pose, stretched to the same window.
local function swingRig(
	rig: PoseRig,
	rigModel: Model?,
	humanoid: Humanoid?,
	step: number,
	windowSeconds: number
): ()
	local total = math.max(windowSeconds, Theme.COMBAT_SWING_SETTLE_SECONDS)
	local windupSeconds = total * Theme.COMBAT_SWING_WINDUP_FRACTION
	if rigModel ~= nil then
		ensureTrail(rigModel, rig)
	end
	flashTrail(rig, windupSeconds, total - windupSeconds)

	local track = trackFor(humanoid, step)
	if track ~= nil then
		cancelRig(rig)
		local speed = math.clamp(
			track.Length / total,
			Theme.COMBAT_ANIMATION_MIN_SPEED,
			Theme.COMBAT_ANIMATION_MAX_SPEED
		)
		rig.track = track
		rig.trackSpeed = speed
		track:Play(Theme.COMBAT_ANIMATION_FADE_SECONDS, 1, speed)
		return
	end
	if rig.motor == nil then
		return
	end
	cancelRig(rig)
	rig.track = nil
	local token = rig.token
	-- The finisher travels further, which is the pose's cue that the combo landed.
	local strike = Theme.COMBAT_SWING_STRIKE_DEGREES
		* (if step >= FINISHER_STEP then Theme.COMBAT_FINISHER_STRIKE_MULT else 1)
	rigPoseTo(rig, Theme.COMBAT_SWING_WINDUP_DEGREES, windupSeconds, Enum.EasingStyle.Quad)
	task.delay(Motion.Seconds(windupSeconds), function()
		if token ~= rig.token then
			return
		end
		local tween = rigPoseTo(rig, strike, total - windupSeconds, Enum.EasingStyle.Back)
		if tween == nil then
			return
		end
		tween.Completed:Once(function()
			if token ~= rig.token then
				return
			end
			rigPoseTo(rig, rig.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)
		end)
	end)
end

-- No yield: a remote character whose arm has not streamed in yet is skipped for this swing
-- and found on the next one.
local function findShoulder(rig: Model): Motor6D?
	local parent = findFirst(rig, SHOULDER_PARENTS)
	if parent == nil then
		return nil
	end
	local motor = findFirst(parent, SHOULDER_NAMES)
	return if motor ~= nil and motor:IsA("Motor6D") then motor else nil
end

-- Another player's posable shoulder. The base C0 is captured the first time a rig is seen (at
-- rest, since nothing posed it yet) and reused, so overlapping poses never drift the arm; a
-- record made while a ranged model is already in that hand starts raised.
local function remotePoseFor(rigModel: Model): PoseRig
	local pose = remotePoses[rigModel]
	local motor = if pose ~= nil then pose.motor else nil
	if pose ~= nil and motor ~= nil and motor.Parent ~= nil then
		return pose
	end
	local fresh = newPose(findShoulder(rigModel))
	remotePoses[rigModel] = fresh
	fresh.rest = restOf(rigModel)
	local freshMotor = fresh.motor
	if freshMotor ~= nil and fresh.rest ~= 0 then
		freshMotor.C0 = restFrame(fresh)
	end
	return fresh
end

-- HeldWeapons.OnHold: a character's hand started or stopped holding a ranged model.
local function onHold(rigModel: Model, isLocal: boolean, raised: boolean): ()
	raisedRigs[rigModel] = raised
	if not isLocal then
		setRest(remotePoseFor(rigModel), restOf(rigModel))
	elseif rigModel == character then
		setRest(localPose, restOf(rigModel))
	end
end

local function bindCharacter(rig: Model): ()
	cancelPose()
	character = rig
	localPose.motor = nil
	localPose.base = CFrame.identity
	localPose.rest = 0
	localPose.track = nil
	localPose.trail = nil
	task.spawn(function()
		local parent: Instance? = nil
		for _, name in SHOULDER_PARENTS do
			parent = rig:WaitForChild(name, Theme.COMBAT_WEAPON_WAIT_SECONDS)
			if parent ~= nil then
				break
			end
		end
		if parent == nil or character ~= rig then
			return
		end
		local motor = findFirst(parent, SHOULDER_NAMES)
		if motor == nil or not motor:IsA("Motor6D") or character ~= rig then
			return
		end
		localPose.motor = motor
		localPose.base = motor.C0
		localPose.rest = restOf(rig)
		motor.C0 = restFrame(localPose)
		ensureTrail(rig, localPose)
	end)
end

-- Shots --------------------------------------------------------------------------------

local function stopFlights(): ()
	local connection = flightConnection
	flightConnection = nil
	if connection ~= nil then
		connection:Disconnect()
	end
end

local function stepFlights(): ()
	local now = os.clock()
	for index = #projectiles, 1, -1 do
		local shot = projectiles[index]
		local travelled = (now - shot.startedAt) * shot.speed
		if travelled >= shot.length or shot.part.Parent == nil then
			table.remove(projectiles, index)
			shot.part:Destroy()
			continue
		end
		shot.part.CFrame = CFrame.lookAlong(shot.from + shot.direction * travelled, shot.direction)
	end
	if #projectiles == 0 then
		stopFlights()
	end
end

-- The client's copy of the server's ray from the same origin: the server's own cast decides
-- the hit, so a mismatch is cosmetic by design.
local function shotEnd(origin: Vector3, direction: Vector3, range: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local rig = player.Character
		if rig ~= nil then
			table.insert(ignored, rig)
		end
	end
	params.FilterDescendantsInstances = ignored
	local result = Workspace:Raycast(origin, direction.Unit * range, params)
	if result == nil then
		return origin + direction.Unit * range
	end
	return result.Position
end

local function muzzlePoint(fallback: Vector3): Vector3
	return HeldWeapons.Muzzle(Players.LocalPlayer.UserId) or fallback
end

local function muzzleFlash(position: Vector3, color: Color3): ()
	local size = Theme.COMBAT_MUZZLE_FLASH_SIZE
	local flash = Create("Part", {
		Name = MUZZLE_NAME,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = Theme.COMBAT_MUZZLE_FLASH_TRANSPARENCY,
		Size = Vector3.one * size,
		CFrame = CFrame.new(position),
		Parent = Workspace,
	}) :: Part
	if not Theme.lowEndDevice then
		Create("PointLight", {
			Color = color,
			Brightness = Theme.COMBAT_MUZZLE_LIGHT_BRIGHTNESS,
			Range = Theme.COMBAT_MUZZLE_LIGHT_RANGE,
			Parent = flash,
		})
	end
	-- Fixed, not Motion: a flash is already a few frames long and must not shrink further.
	local tween = TweenService:Create(
		flash,
		TweenInfo.new(Theme.COMBAT_MUZZLE_FLASH_SECONDS),
		{ Size = Vector3.one * size * Theme.COMBAT_MUZZLE_FLASH_GROWTH, Transparency = 1 }
	)
	tween.Completed:Once(function()
		flash:Destroy()
	end)
	tween:Play()
end

local function launch(from: Vector3, finish: Vector3): ()
	local offset = finish - from
	local length = offset.Magnitude
	if length <= 0 then
		return
	end
	local direction = offset.Unit
	local part: BasePart = Create("Part", {
		Name = PROJECTILE_NAME,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = Theme.COLOR_HIGHLIGHT,
		Size = Vector3.new(
			Theme.COMBAT_BOLT_THICKNESS,
			Theme.COMBAT_BOLT_THICKNESS,
			Theme.COMBAT_BOLT_LENGTH
		),
		CFrame = CFrame.lookAlong(from, direction),
		Parent = Workspace,
	}) :: BasePart
	table.insert(projectiles, {
		part = part,
		from = from,
		direction = direction,
		length = length,
		speed = arrowSpeed() * Theme.COMBAT_BOLT_SPEED_FACTOR,
		startedAt = os.clock(),
	})
	if flightConnection == nil then
		flightConnection = RunService.RenderStepped:Connect(stepFlights)
	end
end

-- Public -------------------------------------------------------------------------------

function WeaponController.Init(): ()
	combatConfig = Catalog.GetCombatConfig()
end

function WeaponController.Start(): ()
	-- Both ids start fetching at boot so the first swing of the run can already use them.
	preload(animationId(1))
	preload(animationId(FINISHER_STEP))
	HeldWeapons.OnHold(onHold)
	HeldWeapons.Start()
	local player = Players.LocalPlayer
	table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
	local rig = player.Character
	if rig ~= nil then
		bindCharacter(rig)
	end
end

function WeaponController.SetStance(nextStance: string): ()
	if nextStance == stance then
		return
	end
	stance = nextStance
	cancelPose()
	HeldWeapons.SetLocalStance(nextStance)
end

-- The local swing, timed by the equipped class's window for this step.
function WeaponController.Swing(step: number, windowSeconds: number): ()
	local rig = character
	local humanoid = if rig ~= nil then rig:FindFirstChildOfClass("Humanoid") else nil
	swingRig(localPose, rig, humanoid, step, windowSeconds)
end

-- Another player's validated swing, on their rig's shoulder record (remotePoseFor).
function WeaponController.SwingOther(userId: number, step: number): ()
	local player = Players:GetPlayerByUserId(userId)
	if player == nil or player == Players.LocalPlayer then
		return -- a departed player has nothing to pose; our own swing is local
	end
	local rig = player.Character
	if rig == nil then
		return
	end
	swingRig(
		remotePoseFor(rig),
		rig,
		rig:FindFirstChildOfClass("Humanoid"),
		step,
		Theme.COMBAT_REMOTE_SWING_SECONDS
	)
end

-- The draw angle is from the hanging arm, like the raise: a bow held raised is already at it,
-- and the draw starts from there (adding it to the raise would point the arm at the sky).
function WeaponController.Draw(chargeSeconds: number): ()
	if localPose.motor == nil then
		return
	end
	cancelPose()
	poseTo(Theme.COMBAT_DRAW_DEGREES, chargeSeconds, Enum.EasingStyle.Linear)
end

function WeaponController.Release(): ()
	if localPose.motor == nil then
		return
	end
	cancelPose()
	poseTo(localPose.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)
end

-- Every shot is visible on every device: seeing your own shot is information, not
-- decoration. Only the muzzle light drops on low-end devices.
function WeaponController.Shoot(origin: Vector3, direction: Vector3, range: number): ()
	if localPose.motor ~= nil then
		cancelPose()
		poseTo(
			localPose.rest + Theme.COMBAT_SHOOT_KICK_DEGREES,
			Theme.COMBAT_SHOOT_KICK_SECONDS,
			Enum.EasingStyle.Quad
		)
		task.delay(Motion.Seconds(Theme.COMBAT_SHOOT_KICK_SECONDS), function()
			WeaponController.Release()
		end)
	end
	local finish = shotEnd(origin, direction, range)
	local from = muzzlePoint(origin)
	muzzleFlash(from, Theme.COLOR_HIGHLIGHT)
	launch(from, finish)
end

function WeaponController.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	stopFlights()
	for _, shot in projectiles do
		shot.part:Destroy()
	end
	table.clear(projectiles)
	-- Every arm goes back to hanging: nothing will raise it again.
	HeldWeapons.Destroy()
	table.clear(raisedRigs)
	localPose.rest = 0
	cancelPose()
	for _, pose in remotePoses do
		pose.rest = 0
		cancelRig(pose)
	end
	table.clear(remotePoses)
end

return WeaponController
