--!strict
-- The local player's weapon, on the local character only (C1 contract, docs/INTERFACES.md
-- "Combat client"). Two jobs:
--
-- 1. Hold the prop. `ReplicatedStorage/Assets/Props/<band eraName>/<model>` is cloned into
--    the right hand when it exists. No weapon prop has been authored yet, so the shipped
--    default is empty hands — a missing folder, era or model is silent, never an error.
-- 2. Pose the arm. C1 has no animation assets (Combat.json animations.* are all 0), so the
--    swing, the bow draw and the muzzle kick are procedural Motor6D C0 tweens timed to the
--    weapon class's `windows`. C0 is used, not Transform, so the default Animate script
--    keeps running underneath instead of fighting us.
--
-- Other players' swings are not animated in C1 (reported as a follow-up): their weapons are
-- not replicated and the server sends no per-swing fx for them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Armory = require(sharedFolder:WaitForChild("Armory"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local Motion = require(uiFolder:WaitForChild("Motion"))

local MELEE_SLOT = "melee"
local WEAPON_NAME = "CombatWeapon"
local TRACER_NAME = "CombatTracer"
-- R15 first, R6 second: the placeholder rigs and every real avatar are R15, but a Studio
-- test with an R6 avatar must still pose an arm instead of erroring.
local HAND_NAMES = { "RightHand", "Right Arm" }
local SHOULDER_PARENTS = { "RightUpperArm", "Torso" }
local SHOULDER_NAMES = { "RightShoulder", "Right Shoulder" }

export type SlotTiers = { melee: number, ranged: number }

local WeaponController = {}

local armoryConfig: Types.ArmoryConfig? = nil
local gear: SlotTiers = { melee = 0, ranged = 0 }
local stance = MELEE_SLOT

local character: Model? = nil
local shoulder: Motor6D? = nil
local shoulderBase: CFrame = CFrame.identity
local weapon: Instance? = nil
local activeTween: Tween? = nil
local poseToken = 0
local connections: { RBXScriptConnection } = {}

local function slotTier(slot: string): number
	return if slot == MELEE_SLOT then gear.melee else gear.ranged
end

local function tierDefFor(slot: string): (Types.WeaponTierDef | Types.WeaponStarterDef)?
	local cfg = armoryConfig
	if cfg == nil then
		return nil
	end
	return Armory.TierDef(cfg, slot, slotTier(slot))
end

-- The prop folder is per era, and a tier names its band, so the era comes from the band
-- table. A starter weapon has no band and no model: nothing to hold.
local function propFolderFor(tierDef: Types.WeaponTierDef | Types.WeaponStarterDef): Instance?
	local cfg = armoryConfig
	local band = (tierDef :: any).band
	if cfg == nil or typeof(band) ~= "number" then
		return nil
	end
	for _, bandDef in cfg.bands do
		if bandDef.band ~= band then
			continue
		end
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local props = if assets ~= nil then assets:FindFirstChild("Props") else nil
		return if props ~= nil then props:FindFirstChild(bandDef.eraName) else nil
	end
	return nil
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

local function clearWeapon(): ()
	local current = weapon
	weapon = nil
	if current ~= nil then
		current:Destroy()
	end
end

local function gripCFrame(hand: BasePart): CFrame
	return hand.CFrame
		* CFrame.new(0, Theme.COMBAT_GRIP_UP, -Theme.COMBAT_GRIP_FORWARD)
		* CFrame.Angles(math.rad(Theme.COMBAT_GRIP_PITCH_DEGREES), 0, 0)
end

-- Welded, massless and non-collidable: a prop must never push the rig around or catch on
-- the arena walls. Parts are welded to each other first, then the whole thing to the hand.
local function attachTo(hand: BasePart, clone: Instance): ()
	local parts: { BasePart } = {}
	if clone:IsA("BasePart") then
		table.insert(parts, clone)
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	local anchor: BasePart? = parts[1]
	if anchor == nil then
		clone:Destroy()
		return
	end
	local target = gripCFrame(hand)
	if clone:IsA("Model") then
		clone:PivotTo(target)
	else
		anchor.CFrame = target
	end
	for _, part in parts do
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		if part ~= anchor then
			Create("WeldConstraint", { Part0 = anchor, Part1 = part, Parent = anchor })
		end
	end
	Create("WeldConstraint", { Name = "Grip", Part0 = hand, Part1 = anchor, Parent = anchor })
	clone.Name = WEAPON_NAME
	clone.Parent = hand
	weapon = clone
end

local function refreshWeapon(): ()
	clearWeapon()
	local rig = character
	if rig == nil then
		return
	end
	local tierDef = tierDefFor(stance)
	if tierDef == nil or tierDef.model == "" then
		return -- starter weapons and unconfigured tiers are held bare-handed by design
	end
	local folder = propFolderFor(tierDef)
	local template = if folder ~= nil then folder:FindFirstChild(tierDef.model) else nil
	local hand = findFirst(rig, HAND_NAMES)
	if template == nil or hand == nil or not hand:IsA("BasePart") then
		return
	end
	attachTo(hand, template:Clone())
end

local function cancelPose(): ()
	poseToken += 1
	local tween = activeTween
	activeTween = nil
	if tween ~= nil then
		tween:Cancel()
	end
	local motor = shoulder
	if motor ~= nil then
		motor.C0 = shoulderBase
	end
end

-- One pose leg: tween the shoulder to `degrees` about its own X axis over `seconds`.
local function poseTo(degrees: number, seconds: number, style: Enum.EasingStyle): Tween?
	local motor = shoulder
	if motor == nil then
		return nil
	end
	local goal = shoulderBase * CFrame.Angles(math.rad(degrees), 0, 0)
	local tween = TweenService:Create(
		motor,
		Motion.Info(math.max(seconds, 0), style, Enum.EasingDirection.Out),
		{ C0 = goal }
	)
	activeTween = tween
	tween:Play()
	return tween
end

local function bindCharacter(rig: Model): ()
	cancelPose()
	character = rig
	shoulder = nil
	shoulderBase = CFrame.identity
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
		shoulder = motor
		shoulderBase = motor.C0
		refreshWeapon()
	end)
end

function WeaponController.Init(): ()
	armoryConfig = Catalog.GetArmoryConfig()
end

function WeaponController.Start(): ()
	local player = Players.LocalPlayer
	table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
	local rig = player.Character
	if rig ~= nil then
		bindCharacter(rig)
	end
end

function WeaponController.SetGear(nextGear: SlotTiers, _ascension: SlotTiers): ()
	if nextGear.melee == gear.melee and nextGear.ranged == gear.ranged then
		return
	end
	gear = nextGear
	refreshWeapon()
end

function WeaponController.SetStance(nextStance: string): ()
	if nextStance == stance then
		return
	end
	stance = nextStance
	cancelPose()
	refreshWeapon()
end

-- Wind up against the swing, then strike through it. The whole thing takes the class's
-- window for this step, so the pose and the server's combo clock agree.
function WeaponController.Swing(step: number, windowSeconds: number): ()
	if shoulder == nil then
		return
	end
	cancelPose()
	poseToken += 1
	local token = poseToken
	local total = math.max(windowSeconds, Theme.COMBAT_SWING_SETTLE_SECONDS)
	local windupSeconds = total * Theme.COMBAT_SWING_WINDUP_FRACTION
	-- The finisher (step 3) travels further, which is the only cue that the combo landed.
	local strike = Theme.COMBAT_SWING_STRIKE_DEGREES * (if step >= 3 then 1.25 else 1)
	poseTo(Theme.COMBAT_SWING_WINDUP_DEGREES, windupSeconds, Enum.EasingStyle.Quad)
	task.delay(Motion.Seconds(windupSeconds), function()
		if token ~= poseToken then
			return
		end
		local tween = poseTo(strike, total - windupSeconds, Enum.EasingStyle.Back)
		if tween == nil then
			return
		end
		tween.Completed:Once(function()
			if token ~= poseToken then
				return
			end
			poseTo(0, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)
		end)
	end)
end

function WeaponController.Draw(chargeSeconds: number): ()
	if shoulder == nil then
		return
	end
	cancelPose()
	poseTo(Theme.COMBAT_DRAW_DEGREES, chargeSeconds, Enum.EasingStyle.Linear)
end

function WeaponController.Release(): ()
	if shoulder == nil then
		return
	end
	cancelPose()
	poseTo(0, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)
end

-- Purely local: the tracer stops at whatever the client can see, while the server's own
-- raycast decides the hit. A mismatch is cosmetic by design.
local function tracerEnd(origin: Vector3, direction: Vector3, range: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local rig = character
	params.FilterDescendantsInstances = if rig ~= nil then { rig } else {}
	local result = Workspace:Raycast(origin, direction.Unit * range, params)
	return if result ~= nil then result.Position else origin + direction.Unit * range
end

function WeaponController.Shoot(
	origin: Vector3,
	direction: Vector3,
	range: number,
	fireKind: string
): ()
	if shoulder ~= nil then
		cancelPose()
		poseTo(
			Theme.COMBAT_SHOOT_KICK_DEGREES,
			Theme.COMBAT_SHOOT_KICK_SECONDS,
			Enum.EasingStyle.Quad
		)
		task.delay(Motion.Seconds(Theme.COMBAT_SHOOT_KICK_SECONDS), function()
			WeaponController.Release()
		end)
	end
	if Theme.reducedMotion then
		return -- the shot still fires; only the streak is dropped (spec section 10)
	end
	local beam = fireKind == "beam"
	local finish = tracerEnd(origin, direction, range)
	local length = (finish - origin).Magnitude
	if length <= 0 then
		return
	end
	local width = if beam then Theme.COMBAT_BEAM_WIDTH else Theme.COMBAT_TRACER_WIDTH
	local part = Create("Part", {
		Name = TRACER_NAME,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = if beam then Theme.COLOR_ACCENT_ALT else Theme.COLOR_HIGHLIGHT,
		Size = Vector3.new(width, width, length),
		CFrame = CFrame.lookAt(origin:Lerp(finish, 0.5), finish),
		Parent = Workspace,
	}) :: Part
	local seconds = if beam then Theme.COMBAT_BEAM_SECONDS else Theme.COMBAT_TRACER_SECONDS
	local tween = TweenService:Create(part, Motion.Info(seconds), { Transparency = 1 })
	tween.Completed:Once(function()
		part:Destroy()
	end)
	tween:Play()
end

-- Hitstop, C1 form: the swing that just connected stops dead for `seconds` and then
-- finishes. See the CombatFxController header for why the enemy's own rig is not frozen.
function WeaponController.Hitstop(seconds: number): ()
	local tween = activeTween
	if tween == nil or seconds <= 0 or Theme.reducedMotion then
		return
	end
	tween:Pause()
	task.delay(seconds, function()
		if activeTween == tween and tween.PlaybackState == Enum.PlaybackState.Paused then
			tween:Play()
		end
	end)
end

function WeaponController.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	cancelPose()
	clearWeapon()
end

return WeaponController
