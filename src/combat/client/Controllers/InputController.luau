--!strict
-- Combat input for the Expeditions place (C1 contract, docs/INTERFACES.md "Combat client").
-- The client is an input device: it decides *when* the player swung, drew or cast, and it
-- sends that intent. It never sends damage, never names a hit, and never trusts the enemy
-- ids it collects — they are a hint the server re-resolves against the live wave.
--
-- Stance is the one piece of client state here: melee (key 1) or ranged (key 2), toggled
-- from the HUD on touch and Y on a gamepad. Everything else (gear, phase, ability cooldowns)
-- is pushed in from CombatUIController, which owns the Snapshot and the RunState.
--
-- C2.5 aim: the crosshair is the shoulder camera's centre ray (CameraController.GetAimRay),
-- projected to the point it meets the arena, and the shot leaves the head toward that point.
-- Touch and gamepad add a soft lock inside `camera.touchAimAssistDegrees`; the mouse gets
-- none, because a locked pointer already aims precisely. Gamepad (ruling 1): R2 attack,
-- L1 / R1 abilities, Y stance, through ContextActionService so the stock bindings yield.
--
-- Degradation: a missing Armory config, a missing class, a missing RequestFire remote (an
-- older server build) or a dead character all make the input a silent no-op, never an error.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Armory = require(sharedFolder:WaitForChild("Armory"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))

export type Stance = "melee" | "ranged"
export type SlotTiers = { melee: number, ranged: number }

local ENEMIES_FOLDER = "Enemies"
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local DEAD_ATTRIBUTE = "Dead"
-- Typed as the union so `stance` stays a Stance and not a bare string; both are still
-- ordinary strings wherever a slot name is passed to a shared module.
local MELEE_SLOT: Stance = "melee"
local RANGED_SLOT: Stance = "ranged"
-- Fallbacks used only when Combat.json is missing; the config is the real home of both.
local DEFAULT_HIT_PAD = 3
local DEFAULT_AIM_ASSIST_DEGREES = 20
local DEFAULT_TOUCH_ASSIST_DEGREES = 12
local DEFAULT_MAX_TARGETS = 24
local DEFAULT_COMBO_TOLERANCE = 0.8
local HALF = 0.5
local ACTION_ATTACK = "CombatAttack"
local ACTION_ABILITY_MELEE = "CombatAbilityMelee"
local ACTION_ABILITY_RANGED = "CombatAbilityRanged"
local ACTION_STANCE = "CombatStance"
local ACTIONS = { ACTION_ATTACK, ACTION_ABILITY_MELEE, ACTION_ABILITY_RANGED, ACTION_STANCE }

local InputController = {}

local armoryConfig: Types.ArmoryConfig? = nil
local combatConfig: Types.CombatConfig? = nil

local stance: Stance = MELEE_SLOT
local gear: SlotTiers = { melee = 0, ranged = 0 }
local abilityReadyIn: SlotTiers = { melee = 0, ranged = 0 }
local phase = "lobby"
local onStanceChanged: ((Stance) -> ())? = nil

local requestAttack: RemoteEvent? = nil
local requestFire: RemoteEvent? = nil
local requestAbility: RemoteEvent? = nil
-- C2: the bow's draw start. The server caps a shot's charge by the time since this stamp, so
-- a release with no draw before it is a weak shot however long the button was held.
local requestDraw: RemoteEvent? = nil

local attackSeq = 0
local fireSeq = 0
local comboStep = 0
local lastSwingAt = 0
local lastFireAt = 0
local chargeStartedAt: number? = nil
local holdToken = 0
local attackHeld = false
local connections: { RBXScriptConnection } = {}

local function slotTier(tiers: SlotTiers, slot: string): number
	return if slot == MELEE_SLOT then tiers.melee else tiers.ranged
end

-- (tierDef, classDef) for a slot, or nil when the Armory config or the class is missing.
local function weaponFor(
	slot: string
): ((Types.WeaponTierDef | Types.WeaponStarterDef)?, Types.WeaponClassDef?)
	local cfg = armoryConfig
	if cfg == nil then
		return nil, nil
	end
	local tierDef = Armory.TierDef(cfg, slot, slotTier(gear, slot))
	if tierDef == nil then
		return nil, nil
	end
	return tierDef, Armory.ClassDef(cfg, tierDef.class)
end

local function hitPad(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.player.hitDistancePad else DEFAULT_HIT_PAD
end

local function aimAssistDegrees(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.player.aimAssistDegrees else DEFAULT_AIM_ASSIST_DEGREES
end

local function touchAssistDegrees(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.camera.touchAimAssistDegrees else DEFAULT_TOUCH_ASSIST_DEGREES
end

-- Touch and gamepad get the soft lock; a locked mouse aims exactly where the crosshair is.
local function assistedInput(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Touch or last.Name:sub(1, 7) == "Gamepad"
end

local function maxTargets(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.director.maxAlive else DEFAULT_MAX_TARGETS
end

-- The same tolerance CombatService gates a swing and a shot with, read from the same key:
-- anything sent earlier than this is certain to come back as `refused cooldown`.
local function comboTolerance(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.player.comboTimingTolerance else DEFAULT_COMBO_TOLERANCE
end

-- Only phases where a swing can possibly land. The server refuses the rest anyway; not
-- sending keeps the attack bucket for real swings.
local function inPlay(): boolean
	return phase == "wave" or phase == "breather" or phase == "boss"
end

type LocalRig = { root: BasePart, head: BasePart, humanoid: Humanoid }

local function localRig(): LocalRig?
	local player = Players.LocalPlayer
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	if head == nil or not head:IsA("BasePart") then
		return nil
	end
	return { root = root, head = head, humanoid = humanoid }
end

type EnemyHit = { model: Model, position: Vector3, id: number }

-- Every live enemy the client can see. Workspace/Enemies is built by ArenaService; a model
-- without an EnemyId, or one already flagged Dead, is not a target.
local function visibleEnemies(): { EnemyHit }
	local found: { EnemyHit } = {}
	local folder = Workspace:FindFirstChild(ENEMIES_FOLDER)
	if folder == nil then
		return found
	end
	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local id = child:GetAttribute(ENEMY_ID_ATTRIBUTE)
		if typeof(id) ~= "number" or child:GetAttribute(DEAD_ATTRIBUTE) == true then
			continue
		end
		-- C2.5: `Dead` is stamped only near the end of the ragdoll, so a falling body is
		-- recognised by its Humanoid instead; aim must never lock onto a corpse.
		local humanoid = child:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and humanoid.Health <= 0 then
			continue
		end
		local pivot = child.PrimaryPart
		if pivot == nil then
			pivot = child:FindFirstChildWhichIsA("BasePart")
		end
		if pivot == nil then
			continue
		end
		table.insert(found, { model = child, position = pivot.Position, id = id })
	end
	return found
end

local function angleBetween(a: Vector3, b: Vector3): number
	if a.Magnitude <= 0 or b.Magnitude <= 0 then
		return math.pi
	end
	return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
end

-- Soft-lock: the nearest live enemy inside a cone of `degrees` around `direction`. Used for
-- both touch (cone around the camera) and mouse (cone around the pointer ray), so the assist
-- feels identical on every device.
local function nearestInCone(
	origin: Vector3,
	direction: Vector3,
	degrees: number,
	maxDistance: number
): EnemyHit?
	local limit = math.rad(degrees)
	local best: EnemyHit? = nil
	local bestDistance = maxDistance
	for _, enemy in visibleEnemies() do
		local offset = enemy.position - origin
		local distance = offset.Magnitude
		if distance > bestDistance or distance <= 0 then
			continue
		end
		if angleBetween(offset, direction) > limit then
			continue
		end
		best = enemy
		bestDistance = distance
	end
	return best
end

-- The world point under the crosshair. The camera ray starts level with the muzzle, so a
-- wall or a teammate between the camera and the player can never catch the shot.
local function crosshairPoint(origin: Vector3, range: number): Vector3
	local rayOrigin, look = CameraController.GetAimRay()
	local along = math.max((origin - rayOrigin):Dot(look), 0)
	local start = rayOrigin + look * along
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character ~= nil then { character } else {}
	local result = Workspace:Raycast(start, look * range, params)
	return if result ~= nil then result.Position else start + look * range
end

local function rawAimDirection(origin: Vector3, range: number): Vector3
	local point = crosshairPoint(origin, range)
	local offset = point - origin
	if offset.Magnitude > Theme.COMBAT_AIM_MIN_STUDS then
		return offset.Unit
	end
	local _, look = CameraController.GetAimRay()
	return look
end

-- (direction, lockedEnemy). The lock is what makes a phone or a pad playable: the shot
-- leaves the head toward the enemy nearest the crosshair inside the assist cone.
local function aim(origin: Vector3, range: number): (Vector3, EnemyHit?)
	local direction = rawAimDirection(origin, range)
	if not assistedInput() then
		return direction, nil
	end
	local locked = nearestInCone(origin, direction, touchAssistDegrees(), range)
	if locked ~= nil then
		local offset = locked.position - origin
		if offset.Magnitude > 0 then
			return offset.Unit, locked
		end
	end
	return direction, nil
end

-- A random direction inside the class's spread cone (spreadDegrees is the full width).
-- Spread is client-side by contract; the server casts whatever ray arrives.
local function withSpread(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local tilt = math.rad(degrees * HALF) * math.sqrt(math.random())
	local frame = CFrame.lookAt(Vector3.zero, direction)
		* CFrame.Angles(0, 0, math.random() * 2 * math.pi)
		* CFrame.Angles(tilt, 0, 0)
	return frame.LookVector
end

local function sendMelee(): ()
	local rig = localRig()
	if rig == nil or not inPlay() then
		return
	end
	local remote = requestAttack
	local tierDef, class = weaponFor(MELEE_SLOT)
	if remote == nil or tierDef == nil or class == nil then
		return
	end
	local windows: { number } = class.windows or {}
	local reset = class.comboReset or 0
	local now = os.clock()
	-- The server drops a swing that arrives inside the previous window; spending an attack
	-- token on a swing that is certainly refused only starves the next real one.
	local previousWindow = windows[comboStep] or 0
	if now - lastSwingAt < previousWindow * comboTolerance() then
		return
	end
	local step = if now - lastSwingAt > reset then 1 else comboStep % 3 + 1
	local window = windows[step] or windows[1] or 0
	comboStep = step
	lastSwingAt = now

	-- Melee keeps its wider C1 assist on every device: the cone sits on the camera's look,
	-- and the rig turns to the enemy for the swing (the server measures the arc from it).
	local range = class.range + hitPad()
	local _, viewLook = CameraController.GetAimRay()
	local flatLook = Vector3.new(viewLook.X, 0, viewLook.Z)
	local locked = if flatLook.Magnitude > 0
		then nearestInCone(rig.root.Position, flatLook.Unit, aimAssistDegrees(), range)
		else nil
	if locked ~= nil then
		CameraController.FaceToward(locked.position, window + Theme.COMBAT_SWING_SETTLE_SECONDS)
	end

	local arc = math.rad((class.arcDegrees or 360) * HALF)
	local look = rig.root.CFrame.LookVector
	local ids: { number } = {}
	local limit = maxTargets()
	for _, enemy in visibleEnemies() do
		local offset = enemy.position - rig.root.Position
		if offset.Magnitude > range or angleBetween(offset, look) > arc then
			continue
		end
		table.insert(ids, enemy.id)
		if #ids >= limit then
			break
		end
	end

	attackSeq += 1
	remote:FireServer(attackSeq, ids)
	WeaponController.Swing(step, window)
	SoundController.Play(if step >= 3 then "finisher" else "swing")
end

local function fireSoundKey(class: Types.WeaponClassDef): string
	local fire = class.fire
	if fire == "beam" then
		return "laser"
	elseif fire == "charge" then
		return "bowFire"
	end
	return "gunFire"
end

local function sendFire(charge: number): ()
	local rig = localRig()
	if rig == nil or not inPlay() then
		return
	end
	local remote = requestFire
	local tierDef, class = weaponFor(RANGED_SLOT)
	if remote == nil or tierDef == nil or class == nil then
		return
	end
	local cooldown = class.cooldown or 0
	local now = os.clock()
	if now - lastFireAt < cooldown * comboTolerance() then
		return
	end
	lastFireAt = now

	local origin = rig.head.Position
	local direction = withSpread((aim(origin, class.range)), class.spreadDegrees or 0)
	fireSeq += 1
	remote:FireServer(fireSeq, origin, direction, math.clamp(charge, 0, 1))
	WeaponController.Shoot(origin, direction, class.range, class.fire or "semi")
	SoundController.Play(fireSoundKey(class))
end

-- One held press, resolved per fire kind. `charge` draws while held and fires on release;
-- `auto` repeats at the class cooldown until the press ends; `semi` and `beam` fire once.
local function beginRanged(): ()
	local _, class = weaponFor(RANGED_SLOT)
	if class == nil then
		return
	end
	local fire = class.fire
	if fire == "charge" then
		local drawRemote = requestDraw
		if drawRemote ~= nil and inPlay() and localRig() ~= nil then
			drawRemote:FireServer()
		end
		chargeStartedAt = os.clock()
		WeaponController.Draw(class.chargeSeconds or 1)
		SoundController.Play("bowDraw")
		return
	end
	if fire == "auto" then
		holdToken += 1
		local token = holdToken
		task.spawn(function()
			while attackHeld and token == holdToken do
				sendFire(1)
				task.wait(math.max(class.cooldown or 0, 0))
			end
		end)
		return
	end
	sendFire(1)
end

local function endRanged(): ()
	local startedAt = chargeStartedAt
	chargeStartedAt = nil
	holdToken += 1
	if startedAt == nil then
		return
	end
	local _, class = weaponFor(RANGED_SLOT)
	WeaponController.Release()
	if class == nil then
		return
	end
	local chargeSeconds = class.chargeSeconds or 1
	sendFire(if chargeSeconds > 0 then (os.clock() - startedAt) / chargeSeconds else 1)
end

local function attackBegan(): ()
	if attackHeld then
		return
	end
	attackHeld = true
	if stance == MELEE_SLOT then
		sendMelee()
	else
		beginRanged()
	end
end

local function attackEnded(): ()
	if not attackHeld then
		return
	end
	attackHeld = false
	if stance == RANGED_SLOT then
		endRanged()
	end
end

-- A burst ability with dashStuds moves the player; the server already resolved the damage
-- along that same segment, so this is presentation. A LinearVelocity on the root (which the
-- client owns) beats a CFrame write: it cannot tunnel through the arena walls.
local function dash(studs: number): ()
	local rig = localRig()
	if rig == nil or studs <= 0 or Theme.reducedMotion then
		return
	end
	local attachment = rig.root:FindFirstChild("RootAttachment")
	if attachment == nil or not attachment:IsA("Attachment") then
		return
	end
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "CombatDash"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = Theme.COMBAT_DASH_MAX_FORCE
	velocity.VectorVelocity = rig.root.CFrame.LookVector * (studs / Theme.COMBAT_DASH_SECONDS)
	velocity.Parent = rig.root
	task.delay(Theme.COMBAT_DASH_SECONDS, function()
		velocity:Destroy()
	end)
end

local function sendAbility(slot: string): ()
	if not inPlay() or localRig() == nil then
		return
	end
	local remote = requestAbility
	local tierDef, class = weaponFor(slot)
	local cfg = armoryConfig
	if remote == nil or tierDef == nil or class == nil or cfg == nil then
		return
	end
	if tierDef.ability == "" then
		return -- starter weapons have no ability; the button is hidden, keys still arrive
	end
	-- Predicted only to save the bucket: the authoritative cooldown is the server's, and it
	-- comes back in every RunState as PartyMember.abilityReadyIn.
	if slotTier(abilityReadyIn, slot) > 0 then
		return
	end
	local ability = Armory.AbilityDef(cfg, tierDef.ability)
	remote:FireServer(slot)
	SoundController.Play("abilityCast")
	if ability ~= nil then
		if slot == MELEE_SLOT then
			abilityReadyIn.melee = ability.cooldown
		else
			abilityReadyIn.ranged = ability.cooldown
		end
		if ability.kind == "burst" and ability.dashStuds ~= nil then
			dash(ability.dashStuds)
		end
	end
end

local function setStance(nextStance: Stance): ()
	if nextStance == stance then
		return
	end
	stance = nextStance
	comboStep = 0
	chargeStartedAt = nil
	holdToken += 1
	WeaponController.SetStance(nextStance)
	local handler = onStanceChanged
	if handler ~= nil then
		handler(nextStance)
	end
end

local function onInputBegan(input: InputObject, processed: boolean): ()
	if processed then
		return -- the tap belonged to a HUD button, which calls straight into us instead
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		attackBegan()
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		local key = input.KeyCode
		if key == Enum.KeyCode.One then
			setStance(MELEE_SLOT)
		elseif key == Enum.KeyCode.Two then
			setStance(RANGED_SLOT)
		elseif key == Enum.KeyCode.Q then
			sendAbility(MELEE_SLOT)
		elseif key == Enum.KeyCode.E then
			sendAbility(RANGED_SLOT)
		end
	end
end

local function onInputEnded(input: InputObject): ()
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		attackEnded()
	end
end

-- One handler for every gamepad action. Sinking stops the stock bindings (a Tool's R2, the
-- default camera's shoulder buttons) from also reacting to the press.
local function onGamepadAction(
	action: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	local began = state == Enum.UserInputState.Begin
	if action == ACTION_ATTACK then
		if began then
			attackBegan()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			attackEnded()
		end
	elseif began and action == ACTION_ABILITY_MELEE then
		sendAbility(MELEE_SLOT)
	elseif began and action == ACTION_ABILITY_RANGED then
		sendAbility(RANGED_SLOT)
	elseif began and action == ACTION_STANCE then
		setStance(if stance == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
	end
	return Enum.ContextActionResult.Sink
end

local function bindGamepad(): ()
	local priority = Enum.ContextActionPriority.High.Value
	local bindings: { { action: string, key: Enum.KeyCode } } = {
		{ action = ACTION_ATTACK, key = Enum.KeyCode.ButtonR2 },
		{ action = ACTION_ABILITY_MELEE, key = Enum.KeyCode.ButtonL1 },
		{ action = ACTION_ABILITY_RANGED, key = Enum.KeyCode.ButtonR1 },
		{ action = ACTION_STANCE, key = Enum.KeyCode.ButtonY },
	}
	for _, binding in bindings do
		ContextActionService:BindActionAtPriority(
			binding.action,
			onGamepadAction,
			false,
			priority,
			binding.key
		)
	end
end

function InputController.Init(): ()
	armoryConfig = Catalog.GetArmoryConfig()
	combatConfig = Catalog.GetCombatConfig()
end

function InputController.Start(): ()
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		requestAttack =
			remotes:WaitForChild("RequestAttack", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		requestAbility =
			remotes:WaitForChild("RequestAbility", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		-- C1 adds RequestFire; an older server build simply leaves ranged fire inert.
		requestFire =
			remotes:WaitForChild("RequestFire", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if requestFire == nil then
			warn("[InputController] RequestFire missing — ranged attacks are disabled")
		end
		-- C2 adds RequestDraw; without it a C1 server still takes the client's charge.
		requestDraw =
			remotes:WaitForChild("RequestDraw", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
	end)
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	bindGamepad()
end

-- The HUD's attack button is a press-and-hold control, so it drives the same two entry
-- points the mouse does; touch never reaches InputBegan because the button consumes it.
function InputController.AttackDown(): ()
	attackBegan()
end

function InputController.AttackUp(): ()
	attackEnded()
end

function InputController.UseAbility(slot: string): ()
	sendAbility(slot)
end

function InputController.ToggleStance(): ()
	setStance(if stance == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
end

-- The bow's draw progress 0-1 for the HUD ring, or nil while nothing is drawn. Display
-- only: the server caps the real charge from its own RequestDraw stamp.
function InputController.GetCharge(): number?
	local startedAt = chargeStartedAt
	if startedAt == nil then
		return nil
	end
	local _, class = weaponFor(RANGED_SLOT)
	local chargeSeconds = if class ~= nil then class.chargeSeconds or 1 else 1
	if chargeSeconds <= 0 then
		return 1
	end
	return math.clamp((os.clock() - startedAt) / chargeSeconds, 0, 1)
end

function InputController.GetStance(): Stance
	return stance
end

function InputController.SetStanceChanged(handler: (Stance) -> ()): ()
	onStanceChanged = handler
end

-- Pushed from the Snapshot by CombatUIController, which pushes the same gear to
-- WeaponController: which weapons the profile actually holds right now.
function InputController.SetGear(nextGear: SlotTiers): ()
	gear = nextGear
	comboStep = 0
end

-- Pushed from RunState: the server's own cooldown clock, which overrides the prediction.
function InputController.SetAbilityReady(readyIn: SlotTiers): ()
	abilityReadyIn = readyIn
end

function InputController.SetPhase(nextPhase: string): ()
	phase = nextPhase
	if not inPlay() then
		attackHeld = false
		chargeStartedAt = nil
		holdToken += 1
	end
end

function InputController.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, action in ACTIONS do
		ContextActionService:UnbindAction(action)
	end
	holdToken += 1
	attackHeld = false
end

return InputController
