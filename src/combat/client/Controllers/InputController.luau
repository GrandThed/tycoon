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
--
-- P1 Proving Grounds (docs/INTERFACES.md "P1 contracts", docs/COMBAT_DESIGN.md section 3):
-- when CameraController.IsRange() is true at boot, none of the mission bindings above are
-- made and a separate range path runs instead, so missions keep exactly today's input.
--  * P2: the range holds one melee FAMILY and one ranged family (RangeLoadout, pushed by
--    FeedbackController through SetLoadout). 1 / 2 pick the active slot locally, gamepad Y
--    toggles; every attack names the active family and sends a `charge` (1 when the weapon
--    has no draw).
--  * Bows (variants with chargeSeconds): hold to draw (RequestRangeDraw starts the server's
--    draw clock), release to fire with charge = min(1, held / chargeSeconds). Releases are
--    still 1/rate apart. Touch rules are with stepCharge below.
--  * Gun: Fortnite camera-ray aim. The shot starts on the crosshair line at the head's depth
--    (inside `shooting.originPad` of the head) and leaves along it, so what the crosshair
--    covers is what is hit, around the shoulder too. Bloom grows with moving, being airborne
--    and firing, recovers at rest, is clamped to min/max and multiplied in ADS; the first
--    shot after `firstShotSeconds` without firing has no spread. Spread is drawn here and
--    sent already applied, as the contract asks.
--  * Sword: swings along the flattened camera look; an airborne swing hangs the character.
--  * Both repeat at the variant's `rate` while held: left mouse, gamepad R2.
--  * Touch has no attack button: `autoFire` attacks while an enemy sphere is within
--    `autoFireAssistDegrees` of the crosshair ray (gun) or inside the melee shape padded by
--    `autoSwingPad` (sword); `tapFire` turns a short, still tap on the right half into one
--    attack. A drag on the right half aims in both modes (CameraController).
--  * ADS: right mouse or L2 held, or a touch toggle above the jump button (gun only).
--  * FeedbackController is the only TuneState listener, so no event is ever split between
--    two connections; the loadout reaches this module through SetLoadout.
-- Every number is read through Tuning.Get() each frame, so the tuning panel acts at once.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))
local CrowdRenderer = require(script.Parent:WaitForChild("CrowdRenderer"))

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

-- P1 range path.
type Device = "pc" | "touch" | "pad"
local RANGE_BIND = "RangeInput"
local ACTION_RANGE_FIRE = "RangeFire"
local ACTION_RANGE_ADS = "RangeAds"
local ACTION_RANGE_SWAP = "RangeSwap"
local RANGE_ACTIONS = { ACTION_RANGE_FIRE, ACTION_RANGE_ADS, ACTION_RANGE_SWAP }
local MIN_RATE = 0.05
-- The sword's pose index restarts after this many swing intervals without a swing.
local SWING_RESET_INTERVALS = 2
local FINISHER_POSE = 3
-- ADS touch toggle, above Roblox's jump button (same rule as MovementController's dash).
local ADS_BUTTON_FRACTION = 0.7
local COLOR_ADS_OFF = Color3.fromRGB(70, 74, 84)
local COLOR_ADS_ON = Color3.fromRGB(255, 200, 87)

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

local rangeMode = false
local activeSlot: Stance = MELEE_SLOT
-- nil until FeedbackController pushes the server's loadout: the config's starting loadout.
local loadout: Types.RangeLoadout? = nil
local drawStartedAt: number? = nil
local drawFamily = ""
-- autoFire: when the target left the assist cone during an under-charged draw. The draw
-- survives controls.tapBufferSeconds so a flickering target does not cancel and restart it.
local targetLostAt: number? = nil
local rangeHeld = false
local adsHeld = false
local adsToggled = false
local adsActive = false
local tapQueuedAt: number? = nil
local lastRangeAttackAt = -math.huge
local lastShotAt = -math.huge
local bloom = 0
local rangeSeq = 0
local swingStep = 0
local device: Device = "pc"
-- drawing = a still hold that became a bow draw (tapFire).
type TapState = { start: Vector2, at: number, moved: number, drawing: boolean }
local rangeTouches: { [InputObject]: TapState } = {}
local requestRangeAttack: RemoteEvent? = nil
local requestRangeDraw: RemoteEvent? = nil
local rangeGui: ScreenGui? = nil
local adsButton: TextButton? = nil

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

-- The crosshair ray ignores every player character, as the server's shot ray does. The
-- list changes only when a character spawns or a player joins or leaves, so it is cached.
local crosshairParams: RaycastParams? = nil
local characterConnections: { [Player]: RBXScriptConnection } = {}

local function invalidateCrosshair(): ()
	crosshairParams = nil
end

local function crosshairParamsFor(): RaycastParams
	local cached = crosshairParams
	if cached ~= nil then
		return cached
	end
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(list, character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	crosshairParams = params
	return params
end

local function watchPlayer(player: Player): ()
	local existing: RBXScriptConnection? = characterConnections[player]
	if existing ~= nil then
		existing:Disconnect()
	end
	characterConnections[player] = player.CharacterAdded:Connect(invalidateCrosshair)
	invalidateCrosshair()
end

local function forgetPlayer(player: Player): ()
	local existing: RBXScriptConnection? = characterConnections[player]
	characterConnections[player] = nil
	if existing ~= nil then
		existing:Disconnect()
	end
	invalidateCrosshair()
end

-- The world point under the crosshair. The camera ray starts level with the muzzle, so a
-- wall or a teammate between the camera and the player can never catch the shot.
local function crosshairPoint(origin: Vector3, range: number): Vector3
	local rayOrigin, look = CameraController.GetAimRay()
	local along = math.max((origin - rayOrigin):Dot(look), 0)
	local start = rayOrigin + look * along
	local params = crosshairParamsFor()
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

-- Range path (P1, P2 families + bows) ------------------------------------------------------

-- The family in the active slot, and its def when it exists and really fills that slot.
-- Before the server's first loadout arrives, the config's starting loadout.
local function activeFamily(cfg: Types.ProvingGroundsConfig): (string, Types.RangeWeaponDef?)
	local held = loadout
	local melee = if held ~= nil then held.melee else cfg.loadout.melee
	local ranged = if held ~= nil then held.ranged else cfg.loadout.ranged
	local family = if activeSlot == MELEE_SLOT then melee else ranged
	local def = cfg.weapons[family]
	if def == nil or def.slot ~= activeSlot then
		return family, nil
	end
	return family, def
end

-- (variant, family id) for the active slot. The loadout's variant choice wins
-- when it names a real variant; otherwise the family's config default.
local function currentVariant(cfg: Types.ProvingGroundsConfig): (Types.RangeWeaponVariant?, string)
	local family, def = activeFamily(cfg)
	if def == nil then
		return nil, family
	end
	local held = loadout
	local chosen = if held ~= nil then held.variants[family] else nil
	local key = if chosen ~= nil and def.variants[chosen] ~= nil then chosen else def.default
	return def.variants[key], family
end

local function isRanged(variant: Types.RangeWeaponVariant): boolean
	return variant.kind == "ranged"
end

-- Bows: a ranged variant with a draw time is held to draw and released to fire.
local function isCharge(variant: Types.RangeWeaponVariant): boolean
	return isRanged(variant) and (variant.chargeSeconds or 0) > 0
end

local function intervalOf(variant: Types.RangeWeaponVariant): number
	return 1 / math.max(variant.rate, MIN_RATE)
end

-- Draw progress 0-1 of the current draw against the variant's live chargeSeconds.
local function chargeOf(variant: Types.RangeWeaponVariant): number
	local startedAt = drawStartedAt
	if startedAt == nil then
		return 0
	end
	local seconds = variant.chargeSeconds or 0
	if seconds <= 0 then
		return 1
	end
	return math.clamp((os.clock() - startedAt) / seconds, 0, 1)
end

local function firstShotReady(cfg: Types.ProvingGroundsConfig): boolean
	return os.clock() - lastShotAt >= cfg.shooting.firstShotSeconds
end

-- Half-angle (degrees) of the cone the next shot is drawn from: 0 for a first shot and for
-- melee, otherwise the bloom with the ADS multiplier.
local function nextSpreadDegrees(cfg: Types.ProvingGroundsConfig): number
	local variant = currentVariant(cfg)
	if variant == nil or not isRanged(variant) or firstShotReady(cfg) then
		return 0
	end
	return bloom * (if adsActive then cfg.shooting.adsBloomMult else 1)
end

local function updateBloom(cfg: Types.ProvingGroundsConfig, rig: LocalRig, deltaTime: number): ()
	local shooting = cfg.shooting
	local velocity = rig.root.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > shooting.bloomMovingSpeed
		or MovementController.IsAirborne()
	if moving then
		bloom += shooting.bloomMovePerSecond * deltaTime
	else
		bloom -= shooting.bloomRecoverPerSecond * deltaTime
	end
	local low = shooting.bloomMinDegrees
	bloom = math.clamp(bloom, low, math.max(shooting.bloomMaxDegrees, low))
end

-- Uniform over the disc of a cone with this half-angle.
local function spreadDirection(direction: Vector3, halfAngleDegrees: number): Vector3
	if halfAngleDegrees <= 0 then
		return direction
	end
	local tilt = math.rad(halfAngleDegrees) * math.sqrt(math.random())
	local frame = CFrame.lookAt(Vector3.zero, direction)
		* CFrame.Angles(0, 0, math.random() * 2 * math.pi)
		* CFrame.Angles(tilt, 0, 0)
	return frame.LookVector
end

-- The crosshair line, started at the head's depth along it: within a shoulder offset of the
-- head (the server's originPad check) and still exactly the line the crosshair draws.
local function shotRay(rig: LocalRig): (Vector3, Vector3)
	local rayOrigin, look = CameraController.GetAimRay()
	local along = math.max((rig.head.Position - rayOrigin):Dot(look), 0)
	return rayOrigin + look * along, look
end

local function flatCameraLook(): Vector3
	local _, look = CameraController.GetAimRay()
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0 then flat.Unit else Vector3.new(0, 0, -1)
end

-- True when a sphere's edge (not its centre) lies within `limit` radians of the ray, in range.
local function sphereInSights(
	origin: Vector3,
	look: Vector3,
	range: number,
	limit: number,
	centre: Vector3,
	radius: number
): boolean
	local offset = centre - origin
	local distance = offset.Magnitude
	if distance <= radius then
		return true
	end
	if distance - radius > range then
		return false
	end
	local toCentre = math.acos(math.clamp(offset.Unit:Dot(look), -1, 1))
	return toCentre - math.asin(math.clamp(radius / distance, 0, 1)) <= limit
end

-- CrowdRenderer reports the ground point; the body sphere is centred at height/2 and the
-- head sphere sits at the top (INTERFACES P1 decision 1).
local function enemyInSights(
	origin: Vector3,
	look: Vector3,
	range: number,
	degrees: number,
	lagPad: number
): boolean
	local limit = math.rad(degrees)
	local found = false
	CrowdRenderer.ForEach(
		function(_id: number, position: Vector3, radius: number, headRadius: number, height: number)
			if found then
				return
			end
			local body = position + Vector3.new(0, height * HALF, 0)
			local head = position + Vector3.new(0, height - headRadius, 0)
			found = sphereInSights(origin, look, range, limit, body, radius + lagPad)
				or sphereInSights(origin, look, range, limit, head, headRadius + lagPad)
		end
	)
	return found
end

-- The same shape the server builds for this variant, via the shared HitShapes geometry. A
-- capsule (spear) runs from the root along the flat look for `range`, `width` across.
local function inMeleeShape(
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	forward: Vector3,
	extraPad: number,
	centre: Vector3,
	radius: number
): boolean
	local pad = variant.pad + extraPad
	local shape = variant.shape
	local range = variant.range
	if shape == "arc" then
		return HitShapes.Arc(origin, forward, range, variant.arcDegrees or 360, pad, centre, radius)
	elseif shape == "sphere" then
		return HitShapes.Sphere(origin, range, pad, centre, radius)
	elseif shape == "capsule" then
		local tip = origin + forward * range
		return HitShapes.Capsule(origin, tip, (variant.width or 0) * HALF, pad, centre, radius)
	elseif shape == "cone" then
		local halfAngle = (variant.arcDegrees or 0) * HALF
		return HitShapes.Cone(origin, forward, range, halfAngle, pad, centre, radius)
	end
	return HitShapes.Ray(origin, forward, range, variant.width or 0, pad, centre, radius) ~= nil
end

local function enemyInReach(
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	forward: Vector3,
	extraPad: number,
	lagPad: number
): boolean
	local found = false
	CrowdRenderer.ForEach(
		function(_id: number, position: Vector3, radius: number, headRadius: number, height: number)
			if found then
				return
			end
			local body = position + Vector3.new(0, height * HALF, 0)
			local head = position + Vector3.new(0, height - headRadius, 0)
			found = inMeleeShape(variant, origin, forward, extraPad, body, radius + lagPad)
				or inMeleeShape(variant, origin, forward, extraPad, head, headRadius + lagPad)
		end
	)
	return found
end

local function autoFireOn(cfg: Types.ProvingGroundsConfig): boolean
	return device == "touch" and cfg.controls.touchMode == "autoFire"
end

local function tapFireOn(cfg: Types.ProvingGroundsConfig): boolean
	return device == "touch" and cfg.controls.touchMode == "tapFire"
end

-- Touch auto-fire's "on target": the assist cone for guns and bows, the whole cone for a cone
-- gun (it hits everything inside), the padded melee shape for melee.
local function targetOnAuto(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	rig: LocalRig
): boolean
	local controls = cfg.controls
	local lagPad = controls.assistLagPad
	if isRanged(variant) then
		local origin, look = shotRay(rig)
		if variant.shape == "cone" then
			return enemyInReach(variant, origin, look, 0, lagPad)
		end
		return enemyInSights(origin, look, variant.range, controls.autoFireAssistDegrees, lagPad)
	end
	return enemyInReach(variant, rig.root.Position, flatCameraLook(), controls.autoSwingPad, lagPad)
end

-- A queued tap still inside its buffer; an expired one is dropped.
local function tapPending(cfg: Types.ProvingGroundsConfig): boolean
	local queued = tapQueuedAt
	if queued == nil then
		return false
	end
	if os.clock() - queued <= cfg.controls.tapBufferSeconds then
		return true
	end
	tapQueuedAt = nil
	return false
end

-- tapFire: a right-half press held still past tapMaxSeconds becomes a draw; the finger may
-- then drag to aim while the bow stays drawn, and lifting it releases.
local function touchDrawHeld(cfg: Types.ProvingGroundsConfig): boolean
	local controls = cfg.controls
	local now = os.clock()
	local held = false
	for _, state in rangeTouches do
		if
			not state.drawing
			and now - state.at > controls.tapMaxSeconds
			and state.moved <= controls.tapMaxPixels
		then
			state.drawing = true
		end
		held = held or state.drawing
	end
	return held
end

local function wantsRangeAttack(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	rig: LocalRig
): boolean
	if rangeHeld or tapPending(cfg) then
		return true
	end
	return autoFireOn(cfg) and targetOnAuto(cfg, variant, rig)
end

local function rangeAttack(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	family: string,
	rig: LocalRig,
	charge: number
): ()
	local remote = requestRangeAttack
	if remote == nil then
		return
	end
	local now = os.clock()
	local interval = intervalOf(variant)
	local idle = now - lastRangeAttackAt > interval * SWING_RESET_INTERVALS
	lastRangeAttackAt = now
	tapQueuedAt = nil
	rangeSeq += 1
	if isRanged(variant) then
		local origin, look = shotRay(rig)
		local direction = spreadDirection(look, nextSpreadDegrees(cfg))
		remote:FireServer(family, rangeSeq, origin, direction, adsActive, charge)
		lastShotAt = now
		local shooting = cfg.shooting
		bloom = math.min(bloom + shooting.bloomPerShot, math.max(shooting.bloomMaxDegrees, bloom))
		-- A local muzzle flash and tracer the instant the trigger is pulled; a projectile's
		-- flight is drawn from the server's CombatFxShot, so it gets no instant tracer.
		if (variant.projectileSpeed or 0) <= 0 then
			WeaponController.Shoot(origin, direction, variant.range, "semi")
		end
		return
	end
	local forward = flatCameraLook()
	remote:FireServer(family, rangeSeq, rig.root.Position, forward, false, charge)
	local chain = variant.chain
	local length = if chain ~= nil and #chain > 0 then #chain else 1
	swingStep = if idle then 1 else swingStep % length + 1
	local pose = if length > 1 and swingStep >= length
		then FINISHER_POSE
		else math.min(swingStep, 2)
	WeaponController.Swing(pose, interval)
	if MovementController.IsAirborne() then
		MovementController.AirHang(cfg.movement.airAttackHangSeconds)
	end
end

local function startDraw(variant: Types.RangeWeaponVariant, family: string): ()
	drawStartedAt = os.clock()
	drawFamily = family
	targetLostAt = nil
	-- The server's own draw clock starts here and caps whatever charge the release claims.
	local remote = requestRangeDraw
	if remote ~= nil then
		remote:FireServer(family)
	end
	WeaponController.Draw(variant.chargeSeconds or 0)
end

local function cancelDraw(): ()
	if drawStartedAt == nil then
		return
	end
	drawStartedAt = nil
	drawFamily = ""
	targetLostAt = nil
	WeaponController.Release()
end

local function releaseDraw(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	family: string,
	rig: LocalRig
): ()
	local charge = chargeOf(variant)
	drawStartedAt = nil
	drawFamily = ""
	targetLostAt = nil
	WeaponController.Release()
	rangeAttack(cfg, variant, family, rig, charge)
end

-- Bows. The draw may start at any time; a release waits until 1/rate has passed since the
-- previous one (it keeps drawing meanwhile), which is the server's rate rule.
--  * Mouse / R2 / a stray HUD press: hold draws, letting go releases.
--  * Touch autoFire: draws while a target is in the assist cone, releases at a full charge;
--    if the target leaves, releases at >= minChargeFraction; below it the draw waits
--    controls.tapBufferSeconds for the target to come back before it is dropped.
--  * Touch tapFire: a short tap is a minimum-charge arrow; a still hold draws until lifted.
local function stepCharge(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	family: string,
	rig: LocalRig
): ()
	local ready = os.clock() - lastRangeAttackAt >= intervalOf(variant)
	local auto = autoFireOn(cfg) and not rangeHeld
	local heldDraw = rangeHeld or (tapFireOn(cfg) and touchDrawHeld(cfg))
	if drawStartedAt == nil then
		if tapPending(cfg) then
			if ready then
				startDraw(variant, family)
				releaseDraw(cfg, variant, family, rig)
			end
		elseif heldDraw or (auto and targetOnAuto(cfg, variant, rig)) then
			startDraw(variant, family)
		end
		return
	end
	local release = false
	if auto then
		if targetOnAuto(cfg, variant, rig) then
			targetLostAt = nil
			release = chargeOf(variant) >= 1
		elseif chargeOf(variant) >= (variant.minChargeFraction or 0) then
			release = true
		else
			local now = os.clock()
			local lostAt = targetLostAt or now
			targetLostAt = lostAt
			if now - lostAt > cfg.controls.tapBufferSeconds then
				cancelDraw()
			end
			return
		end
	else
		release = not heldDraw
	end
	if release and ready then
		releaseDraw(cfg, variant, family, rig)
	end
end

local function refreshAdsButton(variant: Types.RangeWeaponVariant?): ()
	local button = adsButton
	if button == nil then
		return
	end
	local visible = variant ~= nil and isRanged(variant)
	if button.Visible ~= visible then
		button.Visible = visible
	end
	local color = if adsActive then COLOR_ADS_ON else COLOR_ADS_OFF
	if button.BackgroundColor3 ~= color then
		button.BackgroundColor3 = color
	end
end

local function rangeStep(deltaTime: number): ()
	local cfg = Tuning.Get()
	local rig = localRig()
	local variant, family = currentVariant(cfg)
	-- A draw never survives its weapon: a slot switch, a loadout change or death drops it.
	if
		drawStartedAt ~= nil
		and (rig == nil or variant == nil or family ~= drawFamily or not isCharge(variant))
	then
		cancelDraw()
	end
	local wantAds = rig ~= nil and variant ~= nil and isRanged(variant) and (adsHeld or adsToggled)
	if wantAds ~= adsActive then
		adsActive = wantAds
		CameraController.SetAds(wantAds)
	end
	MovementController.SetSpeedMult(if adsActive then cfg.shooting.adsSpeedMult else 1)
	refreshAdsButton(variant)
	if rig == nil or variant == nil then
		return
	end
	updateBloom(cfg, rig, deltaTime)
	if isCharge(variant) then
		stepCharge(cfg, variant, family, rig)
		return
	end
	if os.clock() - lastRangeAttackAt < intervalOf(variant) then
		return
	end
	if wantsRangeAttack(cfg, variant, rig) then
		rangeAttack(cfg, variant, family, rig, 1)
	end
end

-- 1 / 2 / gamepad Y: the slot is a local choice; the server accepts either slot's family.
local function setActiveSlot(slot: Stance): ()
	if slot == activeSlot then
		return
	end
	activeSlot = slot
	cancelDraw()
	adsToggled = false
	swingStep = 0
	tapQueuedAt = nil
	-- The stance drives WeaponController's held model and the HUD's stance glyph.
	setStance(slot)
end

local function deviceOf(inputType: Enum.UserInputType): Device?
	if inputType == Enum.UserInputType.Touch then
		return "touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "pad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseMovement
	then
		return "pc"
	end
	return nil
end

local function onDeviceChanged(inputType: Enum.UserInputType): ()
	local nextDevice: Device? = deviceOf(inputType)
	if nextDevice ~= nil then
		device = nextDevice
	end
end

local function onRangeInputBegan(input: InputObject, processed: boolean): ()
	if processed then
		return -- a GUI button (dash, ADS, the tuning panel) owns this press
	end
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 then
		rangeHeld = true
	elseif inputType == Enum.UserInputType.MouseButton2 then
		adsHeld = true
	elseif inputType == Enum.UserInputType.Touch then
		local camera = Workspace.CurrentCamera
		local split = if camera ~= nil
			then camera.ViewportSize.X * Theme.COMBAT_CAMERA_TOUCH_SPLIT
			else math.huge
		if input.Position.X >= split then
			local start = Vector2.new(input.Position.X, input.Position.Y)
			rangeTouches[input] = { start = start, at = os.clock(), moved = 0, drawing = false }
		end
	elseif inputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.One then
			setActiveSlot(MELEE_SLOT)
		elseif input.KeyCode == Enum.KeyCode.Two then
			setActiveSlot(RANGED_SLOT)
		end
	end
end

local function onRangeInputChanged(input: InputObject): ()
	local state = rangeTouches[input]
	if state ~= nil then
		local position = Vector2.new(input.Position.X, input.Position.Y)
		state.moved = math.max(state.moved, (position - state.start).Magnitude)
	end
end

local function onRangeInputEnded(input: InputObject): ()
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 then
		rangeHeld = false
	elseif inputType == Enum.UserInputType.MouseButton2 then
		adsHeld = false
	elseif inputType == Enum.UserInputType.Touch then
		local state = rangeTouches[input]
		rangeTouches[input] = nil
		local controls = Tuning.Get().controls
		if state == nil or state.drawing or controls.touchMode ~= "tapFire" then
			return
		end
		if
			os.clock() - state.at <= controls.tapMaxSeconds
			and state.moved <= controls.tapMaxPixels
		then
			tapQueuedAt = os.clock()
		end
	end
end

local function onRangeAction(
	action: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	local began = state == Enum.UserInputState.Begin
	local held = began or state == Enum.UserInputState.Change
	if action == ACTION_RANGE_FIRE then
		rangeHeld = held
	elseif action == ACTION_RANGE_ADS then
		adsHeld = held
	elseif began and action == ACTION_RANGE_SWAP then
		setActiveSlot(if activeSlot == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
	end
	return Enum.ContextActionResult.Sink
end

local function layoutRangeControls(): ()
	local button = adsButton
	local camera = Workspace.CurrentCamera
	if button == nil or camera == nil then
		return
	end
	local centre, size =
		MovementController.SatelliteRect(camera.ViewportSize, ADS_BUTTON_FRACTION, "above")
	button.Position = UDim2.fromOffset(centre.X, centre.Y)
	button.Size = UDim2.fromOffset(size, size)
	button.TextSize = MovementController.TextSize(size)
end

local function buildRangeTouchControls(): ()
	if not UserInputService.TouchEnabled then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Physical-pixel offsets mirrored off Roblox's jump button; no UIScale, by design.
	local gui = Instance.new("ScreenGui")
	gui.Name = "RangeInput"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	rangeGui = gui
	local button = MovementController.MakeTouchButton("Aim", "Aim", gui)
	button.Visible = false
	adsButton = button
	table.insert(
		connections,
		button.MouseButton1Down:Connect(function()
			adsToggled = not adsToggled
		end)
	)
	layoutRangeControls()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		table.insert(
			connections,
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutRangeControls)
		)
	end
end

local function startRange(): ()
	bloom = Tuning.Get().shooting.bloomMinDegrees
	local initial: Device? = deviceOf(UserInputService:GetLastInputType())
	if initial ~= nil then
		device = initial
	elseif UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		device = "touch"
	end
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local timeout = Theme.COMBAT_REMOTE_WAIT_SECONDS
		requestRangeAttack = remotes:WaitForChild("RequestRangeAttack", timeout) :: RemoteEvent?
		requestRangeDraw = remotes:WaitForChild("RequestRangeDraw", timeout) :: RemoteEvent?
		if requestRangeAttack == nil then
			warn("[InputController] RequestRangeAttack missing — range attacks are disabled")
		end
	end)
	table.insert(connections, UserInputService.InputBegan:Connect(onRangeInputBegan))
	table.insert(connections, UserInputService.InputChanged:Connect(onRangeInputChanged))
	table.insert(connections, UserInputService.InputEnded:Connect(onRangeInputEnded))
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(onDeviceChanged))
	local priority = Enum.ContextActionPriority.High.Value
	local bindings: { { action: string, key: Enum.KeyCode } } = {
		{ action = ACTION_RANGE_FIRE, key = Enum.KeyCode.ButtonR2 },
		{ action = ACTION_RANGE_ADS, key = Enum.KeyCode.ButtonL2 },
		{ action = ACTION_RANGE_SWAP, key = Enum.KeyCode.ButtonY },
	}
	for _, binding in bindings do
		ContextActionService:BindActionAtPriority(
			binding.action,
			onRangeAction,
			false,
			priority,
			binding.key
		)
	end
	-- After the camera, so the aim ray and the auto-fire test use this frame's view.
	RunService:BindToRenderStep(RANGE_BIND, Enum.RenderPriority.Camera.Value + 1, rangeStep)
	buildRangeTouchControls()
end

function InputController.Init(): ()
	armoryConfig = Catalog.GetArmoryConfig()
	combatConfig = Catalog.GetCombatConfig()
	rangeMode = CameraController.IsRange()
	MovementController.Init()
end

function InputController.Start(): ()
	if rangeMode then
		-- MovementController is a range-only sub-controller of input, started from here so
		-- the client boot list stays the mission list.
		startRange()
		MovementController.Start()
		return
	end
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
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(forgetPlayer))
	bindGamepad()
end

-- The HUD's attack button is a press-and-hold control, so it drives the same two entry
-- points the mouse does; touch never reaches InputBegan because the button consumes it.
function InputController.AttackDown(): ()
	if rangeMode then
		rangeHeld = true -- the range should not show this button; a stray press still attacks
		return
	end
	attackBegan()
end

function InputController.AttackUp(): ()
	if rangeMode then
		rangeHeld = false
		return
	end
	attackEnded()
end

function InputController.UseAbility(slot: string): ()
	sendAbility(slot)
end

function InputController.ToggleStance(): ()
	if rangeMode then
		setActiveSlot(if activeSlot == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
		return
	end
	setStance(if stance == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
end

-- P1 range API, read every frame by Feedback's Crosshair.
-- Half-angle in degrees of the cone the next shot is drawn from, ADS already applied; 0 for
-- a ready first shot and for melee. Crosshair radius in px = tan(rad(b)) / tan(rad(fov) / 2)
-- × viewport height / 2, using the live Camera.FieldOfView (ADS changes it).
function InputController.GetBloomDegrees(): number
	if not rangeMode then
		return 0
	end
	return nextSpreadDegrees(Tuning.Get())
end

-- True while aiming down sights (range gun only).
function InputController.IsAiming(): boolean
	return adsActive
end

-- The crosshair ray: unshaken camera position and unit look direction.
function InputController.GetAimRay(): Ray
	local origin, look = CameraController.GetAimRay()
	return Ray.new(origin, look)
end

-- The loadout the server confirmed on TuneState, forwarded by FeedbackController (the one
-- TuneState listener). A family that is unknown or in the wrong slot makes that slot inert;
-- an unknown variant falls back to the family's config default wherever it is read. A draw
-- on a family that left the loadout is dropped on the next frame.
function InputController.SetLoadout(nextLoadout: Types.RangeLoadout): ()
	loadout = nextLoadout
end

-- The slot 1 / 2 / gamepad Y last picked (range only; missions keep GetStance).
function InputController.GetActiveSlot(): Stance
	return activeSlot
end

-- The bow's draw progress 0-1 for the HUD ring. In the range it is never nil (0 while
-- nothing is drawn); in missions nil means nothing is drawn, which the mission HUD needs to
-- hide its dots. Display only: the server caps the real charge from its own draw stamp.
function InputController.GetCharge(): number?
	if rangeMode then
		local variant = currentVariant(Tuning.Get())
		return if variant ~= nil then chargeOf(variant) else 0
	end
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
	for _, action in RANGE_ACTIONS do
		ContextActionService:UnbindAction(action)
	end
	if rangeMode then
		RunService:UnbindFromRenderStep(RANGE_BIND)
		CameraController.SetAds(false)
		MovementController.Destroy()
	end
	local gui = rangeGui
	rangeGui = nil
	adsButton = nil
	if gui ~= nil then
		gui:Destroy()
	end
	table.clear(rangeTouches)
	drawStartedAt = nil
	drawFamily = ""
	rangeHeld = false
	adsHeld = false
	adsToggled = false
	adsActive = false
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	crosshairParams = nil
	holdToken += 1
	attackHeld = false
end

return InputController
