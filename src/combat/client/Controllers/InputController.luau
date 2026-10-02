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
--
-- P3 (docs/INTERFACES.md "P3 contracts"), range path only:
--  * Q / E, gamepad L1 / R1 and two touch buttons cast the melee / ranged slot's family
--    ability. A cast needs an ability, no busy lock and a ready cooldown (allowing
--    abilities.earlySeconds). It makes that slot active (ruling 1), sends the unspread camera
--    ray on RequestRangeAbility and predicts the cooldown and the busy window at once. The
--    RangeAbility state the server sends back replaces the prediction; a cast still
--    unanswered after two pings plus slack counts as refused and its local effects stop.
--  * Busy (the ability table's column): no attacks, no slot switch, no other ability. Leap
--    Smash and Impale Dash move the character through MovementController, which also owns
--    the Whirlwind walk multiplier. Mag Dump fires the ranged slot by itself at rate x
--    rateMult with no spread and no bloom, on every device, holding or not.
--  * An aimed ability's ground point mirrors RangeService.GroundPoint step for step, on the
--    raw camera ray (ruling 4).
--  * SMG: bloom per shot x bloomMult. Beam (`continuous`): held fire at `rate`; touch
--    auto-fire keeps it on while a target is in the cone (riding out tapBufferSeconds of
--    flicker) and tapFire's still hold is the beam. Chain Gun is an ordinary hitscan shot.
--  * Touch: the ability buttons (name, a shrinking cooldown disc with whole seconds, dimmed
--    while busy, a ready pulse) and the slot button (the other slot's family, closing the P2
--    known limit) join the right-thumb cluster MovementController.ClusterRect lays out.
--    Still no attack button. RangeTouchButtons builds and draws them; the rules stay here.

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
local RangeTouchButtons = require(script.Parent:WaitForChild("RangeTouchButtons"))

export type Stance = "melee" | "ranged"
export type SlotTiers = { melee: number, ranged: number }

-- A module's top level is one Luau function, and Studio (debug level 2) gives it 200 local
-- registers, constants included. So related constants and state live in a few tables here and
-- the touch buttons in RangeTouchButtons; tools/check_compile.py is the gate.

local ENEMIES_FOLDER = "Enemies"
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local DEAD_ATTRIBUTE = "Dead"
-- Typed as the union so `stance` stays a Stance and not a bare string; both are still
-- ordinary strings wherever a slot name is passed to a shared module.
local MELEE_SLOT: Stance = "melee"
local RANGED_SLOT: Stance = "ranged"
-- Fallbacks used only when Combat.json is missing; the config is the real home of them all.
local DEFAULTS = table.freeze({
	HIT_PAD = 3,
	AIM_ASSIST_DEGREES = 20,
	TOUCH_ASSIST_DEGREES = 12,
	MAX_TARGETS = 24,
	COMBO_TOLERANCE = 0.8,
})
local HALF = 0.5
-- ContextActionService action names: the mission path's four, then the range path's five.
local ACTION = table.freeze({
	ATTACK = "CombatAttack",
	ABILITY_MELEE = "CombatAbilityMelee",
	ABILITY_RANGED = "CombatAbilityRanged",
	STANCE = "CombatStance",
	RANGE_FIRE = "RangeFire",
	RANGE_ADS = "RangeAds",
	RANGE_SWAP = "RangeSwap",
	RANGE_ABILITY_MELEE = "RangeAbilityMelee",
	RANGE_ABILITY_RANGED = "RangeAbilityRanged",
})
local ACTIONS = { ACTION.ATTACK, ACTION.ABILITY_MELEE, ACTION.ABILITY_RANGED, ACTION.STANCE }

-- P1 range path.
type Device = "pc" | "touch" | "pad"
local RANGE_BIND = "RangeInput"
local RANGE_ACTIONS = {
	ACTION.RANGE_FIRE,
	ACTION.RANGE_ADS,
	ACTION.RANGE_SWAP,
	ACTION.RANGE_ABILITY_MELEE,
	ACTION.RANGE_ABILITY_RANGED,
}
local MIN_RATE = 0.05
-- The sword's pose index restarts after this many swing intervals without a swing.
local SWING_RESET_INTERVALS = 2
local FINISHER_POSE = 3
-- Sustained fire sends one shot a frame, two only when the frame is longer than an interval.
local MAX_SHOTS_PER_FRAME = 2
-- Ruling 4's floor probe, shared with RangeService so both sides land on the same floor.
local GROUND_PROBE_LIFT = HitShapes.GROUND_PROBE_LIFT
local GROUND_PROBE_DEPTH = HitShapes.GROUND_PROBE_DEPTH
-- A cast still unanswered after two pings plus this was refused or dropped by the server.
local CAST_ACK_SLACK_SECONDS = 0.3

local InputController = {}

local armoryConfig: Types.ArmoryConfig? = nil
local combatConfig: Types.CombatConfig? = nil

local stance: Stance = MELEE_SLOT
local connections: { RBXScriptConnection } = {}
local rangeMode = false

-- Mission-path state (C1-C2.5).
type MissionState = {
	gear: SlotTiers,
	abilityReadyIn: SlotTiers,
	phase: string,
	onStanceChanged: ((Stance) -> ())?,
	requestAttack: RemoteEvent?,
	requestFire: RemoteEvent?,
	requestAbility: RemoteEvent?,
	-- C2: the bow's draw start. The server caps a shot's charge by the time since this stamp,
	-- so a release with no draw before it is a weak shot however long the button was held.
	requestDraw: RemoteEvent?,
	attackSeq: number,
	fireSeq: number,
	comboStep: number,
	lastSwingAt: number,
	lastFireAt: number,
	chargeStartedAt: number?,
	holdToken: number,
	attackHeld: boolean,
	-- The crosshair ray ignores every player character, as the server's shot ray does. The
	-- list changes only when a character spawns or a player joins or leaves, so it is cached.
	crosshairParams: RaycastParams?,
	characterConnections: { [Player]: RBXScriptConnection },
}
local missionState: MissionState = {
	gear = { melee = 0, ranged = 0 },
	abilityReadyIn = { melee = 0, ranged = 0 },
	phase = "lobby",
	attackSeq = 0,
	fireSeq = 0,
	comboStep = 0,
	lastSwingAt = 0,
	lastFireAt = 0,
	holdToken = 0,
	attackHeld = false,
	characterConnections = {},
}

-- Range-path state (P1-P3): the slot and loadout, the held inputs, the draw and the fire
-- pacing.
-- drawing = a still hold that became a bow draw or a held beam (tapFire).
type TapState = { start: Vector2, at: number, moved: number, drawing: boolean }
type RangeState = {
	rangeStarted: boolean,
	activeSlot: Stance,
	-- nil until FeedbackController pushes the server's loadout: the config's starting loadout.
	loadout: Types.RangeLoadout?,
	device: Device,
	rangeTouches: { [InputObject]: TapState },
	requestRangeAttack: RemoteEvent?,
	requestRangeDraw: RemoteEvent?,
	rangeHeld: boolean,
	adsHeld: boolean,
	adsToggled: boolean,
	adsActive: boolean,
	drawStartedAt: number?,
	drawFamily: string,
	-- autoFire: when the target left the assist cone during an under-charged draw. The draw
	-- survives controls.tapBufferSeconds so a flickering target does not cancel and restart it.
	targetLostAt: number?,
	tapQueuedAt: number?,
	lastRangeAttackAt: number,
	lastShotAt: number,
	bloom: number,
	rangeSeq: number,
	swingStep: number,
	-- Sustained-fire accumulator (see dueShots): when the next shot is due, the interval it
	-- was scheduled at, and whether the previous frame wanted to fire (a stream in progress).
	nextShotAt: number,
	scheduledInterval: number,
	firingStream: boolean,
	-- Touch auto-fire: a held beam keeps firing until then after its target leaves the cone.
	beamHoldUntil: number,
}
local rangeState: RangeState = {
	rangeStarted = false,
	activeSlot = MELEE_SLOT,
	device = "pc",
	rangeTouches = {},
	rangeHeld = false,
	adsHeld = false,
	adsToggled = false,
	adsActive = false,
	drawFamily = "",
	lastRangeAttackAt = -math.huge,
	lastShotAt = -math.huge,
	bloom = 0,
	rangeSeq = 0,
	swingStep = 0,
	nextShotAt = -math.huge,
	scheduledInterval = 0,
	firingStream = false,
	beamHoldUntil = 0,
}

-- P3 ability state. Every time here is workspace:GetServerTimeNow() unless named "clock".
-- A cast the server has not answered yet: its predicted cooldown, floor and busy window, and
-- the os.clock it was sent at (keyed by slot).
type PendingCast = {
	seq: number,
	castAt: number,
	sentClock: number,
	readyAt: number,
	floorAt: number,
	busyUntil: number,
}
-- Mag Dump: the ranged slot fires by itself until `untilAt` at rate x rateMult.
type MagDump = { family: string, untilAt: number, rateMult: number }
type CastState = {
	requestRangeAbility: RemoteEvent?,
	serverAbility: Types.RangeAbilityState?,
	abilitySeq: number,
	-- A mirror of the server's rangeAbility token bucket (RemoteService: capacity = rate), so
	-- a cast the server would drop unanswered is never sent, while Q then E stays one burst.
	castTokens: number,
	castTokensClock: number,
	pendingCasts: { [string]: PendingCast },
	-- What GetAbilityState hands out: the server state with the predictions laid over it.
	abilityViewState: Types.RangeAbilityState,
	magDump: MagDump?,
}
local castState: CastState = {
	abilitySeq = 0,
	castTokens = math.huge,
	castTokensClock = 0,
	pendingCasts = {},
	abilityViewState = {
		melee = { ability = "", readyAt = 0, floorAt = 0 },
		ranged = { ability = "", readyAt = 0, floorAt = 0 },
		busyUntil = 0,
	},
}

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
	local tierDef = Armory.TierDef(cfg, slot, slotTier(missionState.gear, slot))
	if tierDef == nil then
		return nil, nil
	end
	return tierDef, Armory.ClassDef(cfg, tierDef.class)
end

local function hitPad(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.player.hitDistancePad else DEFAULTS.HIT_PAD
end

local function aimAssistDegrees(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.player.aimAssistDegrees else DEFAULTS.AIM_ASSIST_DEGREES
end

local function touchAssistDegrees(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.camera.touchAimAssistDegrees else DEFAULTS.TOUCH_ASSIST_DEGREES
end

-- Touch and gamepad get the soft lock; a locked mouse aims exactly where the crosshair is.
local function assistedInput(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Touch or last.Name:sub(1, 7) == "Gamepad"
end

local function maxTargets(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.director.maxAlive else DEFAULTS.MAX_TARGETS
end

-- The same tolerance CombatService gates a swing and a shot with, read from the same key:
-- anything sent earlier than this is certain to come back as `refused cooldown`.
local function comboTolerance(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.player.comboTimingTolerance else DEFAULTS.COMBO_TOLERANCE
end

-- Only phases where a swing can possibly land. The server refuses the rest anyway; not
-- sending keeps the attack bucket for real swings.
local function inPlay(): boolean
	return missionState.phase == "wave"
		or missionState.phase == "breather"
		or missionState.phase == "boss"
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

local function invalidateCrosshair(): ()
	missionState.crosshairParams = nil
end

local function crosshairParamsFor(): RaycastParams
	local cached = missionState.crosshairParams
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
	missionState.crosshairParams = params
	return params
end

local function watchPlayer(player: Player): ()
	local existing: RBXScriptConnection? = missionState.characterConnections[player]
	if existing ~= nil then
		existing:Disconnect()
	end
	missionState.characterConnections[player] = player.CharacterAdded:Connect(invalidateCrosshair)
	invalidateCrosshair()
end

local function forgetPlayer(player: Player): ()
	local existing: RBXScriptConnection? = missionState.characterConnections[player]
	missionState.characterConnections[player] = nil
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
	local remote = missionState.requestAttack
	local tierDef, class = weaponFor(MELEE_SLOT)
	if remote == nil or tierDef == nil or class == nil then
		return
	end
	local windows: { number } = class.windows or {}
	local reset = class.comboReset or 0
	local now = os.clock()
	-- The server drops a swing that arrives inside the previous window; spending an attack
	-- token on a swing that is certainly refused only starves the next real one.
	local previousWindow = windows[missionState.comboStep] or 0
	if now - missionState.lastSwingAt < previousWindow * comboTolerance() then
		return
	end
	local step = if now - missionState.lastSwingAt > reset
		then 1
		else missionState.comboStep % 3 + 1
	local window = windows[step] or windows[1] or 0
	missionState.comboStep = step
	missionState.lastSwingAt = now

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

	missionState.attackSeq += 1
	remote:FireServer(missionState.attackSeq, ids)
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
	local remote = missionState.requestFire
	local tierDef, class = weaponFor(RANGED_SLOT)
	if remote == nil or tierDef == nil or class == nil then
		return
	end
	local cooldown = class.cooldown or 0
	local now = os.clock()
	if now - missionState.lastFireAt < cooldown * comboTolerance() then
		return
	end
	missionState.lastFireAt = now

	local origin = rig.head.Position
	local direction = withSpread((aim(origin, class.range)), class.spreadDegrees or 0)
	missionState.fireSeq += 1
	remote:FireServer(missionState.fireSeq, origin, direction, math.clamp(charge, 0, 1))
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
		local drawRemote = missionState.requestDraw
		if drawRemote ~= nil and inPlay() and localRig() ~= nil then
			drawRemote:FireServer()
		end
		missionState.chargeStartedAt = os.clock()
		WeaponController.Draw(class.chargeSeconds or 1)
		SoundController.Play("bowDraw")
		return
	end
	if fire == "auto" then
		missionState.holdToken += 1
		local token = missionState.holdToken
		task.spawn(function()
			while missionState.attackHeld and token == missionState.holdToken do
				sendFire(1)
				task.wait(math.max(class.cooldown or 0, 0))
			end
		end)
		return
	end
	sendFire(1)
end

local function endRanged(): ()
	local startedAt = missionState.chargeStartedAt
	missionState.chargeStartedAt = nil
	missionState.holdToken += 1
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
	if missionState.attackHeld then
		return
	end
	missionState.attackHeld = true
	if stance == MELEE_SLOT then
		sendMelee()
	else
		beginRanged()
	end
end

local function attackEnded(): ()
	if not missionState.attackHeld then
		return
	end
	missionState.attackHeld = false
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
	local remote = missionState.requestAbility
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
	if slotTier(missionState.abilityReadyIn, slot) > 0 then
		return
	end
	local ability = Armory.AbilityDef(cfg, tierDef.ability)
	remote:FireServer(slot)
	SoundController.Play("abilityCast")
	if ability ~= nil then
		if slot == MELEE_SLOT then
			missionState.abilityReadyIn.melee = ability.cooldown
		else
			missionState.abilityReadyIn.ranged = ability.cooldown
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
	missionState.comboStep = 0
	missionState.chargeStartedAt = nil
	missionState.holdToken += 1
	WeaponController.SetStance(nextStance)
	local handler = missionState.onStanceChanged
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
	if action == ACTION.ATTACK then
		if began then
			attackBegan()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			attackEnded()
		end
	elseif began and action == ACTION.ABILITY_MELEE then
		sendAbility(MELEE_SLOT)
	elseif began and action == ACTION.ABILITY_RANGED then
		sendAbility(RANGED_SLOT)
	elseif began and action == ACTION.STANCE then
		setStance(if stance == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
	end
	return Enum.ContextActionResult.Sink
end

local function bindGamepad(): ()
	local priority = Enum.ContextActionPriority.High.Value
	local bindings: { { action: string, key: Enum.KeyCode } } = {
		{ action = ACTION.ATTACK, key = Enum.KeyCode.ButtonR2 },
		{ action = ACTION.ABILITY_MELEE, key = Enum.KeyCode.ButtonL1 },
		{ action = ACTION.ABILITY_RANGED, key = Enum.KeyCode.ButtonR1 },
		{ action = ACTION.STANCE, key = Enum.KeyCode.ButtonY },
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

-- Range path (P1, P2 families + bows, P3 abilities) ----------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- The family held in `slot`, and its def when it exists and really fills that slot. Before
-- the server's first loadout arrives, the config's starting loadout.
local function slotFamily(
	cfg: Types.ProvingGroundsConfig,
	slot: Stance
): (string, Types.RangeWeaponDef?)
	local held = rangeState.loadout
	local family
	if slot == MELEE_SLOT then
		family = if held ~= nil then held.melee else cfg.loadout.melee
	else
		family = if held ~= nil then held.ranged else cfg.loadout.ranged
	end
	local def = cfg.weapons[family]
	if def == nil or def.slot ~= slot then
		return family, nil
	end
	return family, def
end

-- The family in the active slot.
local function activeFamily(cfg: Types.ProvingGroundsConfig): (string, Types.RangeWeaponDef?)
	return slotFamily(cfg, rangeState.activeSlot)
end

-- (variant, family id) for the active slot. The loadout's variant choice wins
-- when it names a real variant; otherwise the family's config default.
local function currentVariant(cfg: Types.ProvingGroundsConfig): (Types.RangeWeaponVariant?, string)
	local family, def = activeFamily(cfg)
	if def == nil then
		return nil, family
	end
	local held = rangeState.loadout
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
	local startedAt = rangeState.drawStartedAt
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
	return os.clock() - rangeState.lastShotAt >= cfg.shooting.firstShotSeconds
end

-- Half-angle (degrees) of the cone the next shot is drawn from: 0 for a first shot, for
-- melee and during Mag Dump, otherwise the bloom with the ADS multiplier.
local function nextSpreadDegrees(cfg: Types.ProvingGroundsConfig): number
	local variant = currentVariant(cfg)
	if
		variant == nil
		or not isRanged(variant)
		or castState.magDump ~= nil
		or firstShotReady(cfg)
	then
		return 0
	end
	return rangeState.bloom * (if rangeState.adsActive then cfg.shooting.adsBloomMult else 1)
end

local function updateBloom(cfg: Types.ProvingGroundsConfig, rig: LocalRig, deltaTime: number): ()
	local shooting = cfg.shooting
	local velocity = rig.root.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > shooting.bloomMovingSpeed
		or MovementController.IsAirborne()
	if moving then
		rangeState.bloom += shooting.bloomMovePerSecond * deltaTime
	else
		rangeState.bloom -= shooting.bloomRecoverPerSecond * deltaTime
	end
	local low = shooting.bloomMinDegrees
	rangeState.bloom = math.clamp(rangeState.bloom, low, math.max(shooting.bloomMaxDegrees, low))
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
	return rangeState.device == "touch" and cfg.controls.touchMode == "autoFire"
end

local function tapFireOn(cfg: Types.ProvingGroundsConfig): boolean
	return rangeState.device == "touch" and cfg.controls.touchMode == "tapFire"
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
	local queued = rangeState.tapQueuedAt
	if queued == nil then
		return false
	end
	if os.clock() - queued <= cfg.controls.tapBufferSeconds then
		return true
	end
	rangeState.tapQueuedAt = nil
	return false
end

-- tapFire: a right-half press held still past tapMaxSeconds becomes a draw (bows) or a held
-- beam; the finger may then drag to aim, and lifting it releases.
local function touchDrawHeld(cfg: Types.ProvingGroundsConfig): boolean
	local controls = cfg.controls
	local now = os.clock()
	local held = false
	for _, state in rangeState.rangeTouches do
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
	if rangeState.rangeHeld or tapPending(cfg) then
		return true
	end
	local continuous = variant.continuous == true
	-- tapFire: a still hold is the held beam; a tap is still one tick.
	if continuous and tapFireOn(cfg) and touchDrawHeld(cfg) then
		return true
	end
	if not autoFireOn(cfg) then
		return false
	end
	if targetOnAuto(cfg, variant, rig) then
		rangeState.beamHoldUntil = os.clock() + cfg.controls.tapBufferSeconds
		return true
	end
	-- A held beam rides out a target flickering on the cone's edge instead of stuttering.
	return continuous and os.clock() < rangeState.beamHoldUntil
end

-- How many sustained-fire shots are due this frame. A true accumulator: a shot is due once
-- os.clock() reaches nextShotAt, and each shot moves it on by exactly one interval, so a rate
-- between frame multiples still averages out (36/s at 60 fps alternates one- and two-frame
-- gaps; the server's banked credit, shooting.rateBurstShots, takes the short ones).
--  * Mid-stream, nextShotAt never trails the clock by more than one interval (a hitch costs
--    at most one caught-up shot, never a burst).
--  * A fresh press starts from now, so a pause never banks a double shot.
--  * A new interval (another weapon, Mag Dump starting or ending, a tuned rate) re-paces
--    from the last attack.
local function dueShots(interval: number, frameSeconds: number, fresh: boolean): number
	local now = os.clock()
	if interval ~= rangeState.scheduledInterval then
		rangeState.scheduledInterval = interval
		rangeState.nextShotAt = rangeState.lastRangeAttackAt + interval
	end
	if now < rangeState.nextShotAt then
		return 0
	end
	rangeState.nextShotAt = math.max(rangeState.nextShotAt, if fresh then now else now - interval)
	local limit = if frameSeconds > interval then MAX_SHOTS_PER_FRAME else 1
	local count = 0
	while count < limit and now >= rangeState.nextShotAt do
		count += 1
		rangeState.nextShotAt += interval
	end
	return count
end

-- One attack now. `interval` paces the next one; `steady` = a Mag Dump shot, which leaves
-- along the crosshair with no spread and adds no bloom.
local function rangeAttack(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	family: string,
	rig: LocalRig,
	charge: number,
	interval: number,
	steady: boolean
): ()
	local remote = rangeState.requestRangeAttack
	if remote == nil then
		return
	end
	local now = os.clock()
	local idle = now - rangeState.lastRangeAttackAt > interval * SWING_RESET_INTERVALS
	rangeState.lastRangeAttackAt = now
	rangeState.tapQueuedAt = nil
	rangeState.rangeSeq += 1
	if isRanged(variant) then
		local origin, look = shotRay(rig)
		local direction = if steady then look else spreadDirection(look, nextSpreadDegrees(cfg))
		remote:FireServer(
			family,
			rangeState.rangeSeq,
			origin,
			direction,
			rangeState.adsActive,
			charge
		)
		rangeState.lastShotAt = now
		if not steady then
			-- P3: bloomMult scales what one shot adds (SMG sprays tighter, a beam adds none).
			local shooting = cfg.shooting
			local added = shooting.bloomPerShot * math.max(variant.bloomMult or 1, 0)
			rangeState.bloom = math.min(
				rangeState.bloom + added,
				math.max(shooting.bloomMaxDegrees, rangeState.bloom)
			)
		end
		-- A local muzzle flash and tracer the instant the trigger is pulled; a projectile's
		-- flight is drawn from the server's CombatFxShot, so it gets no instant tracer. A held
		-- beam is FeedbackController's one lasting beam, not a tracer per tick.
		if (variant.projectileSpeed or 0) <= 0 and variant.continuous ~= true then
			WeaponController.Shoot(origin, direction, variant.range, "semi")
		end
		return
	end
	local forward = flatCameraLook()
	remote:FireServer(family, rangeState.rangeSeq, rig.root.Position, forward, false, charge)
	local chain = variant.chain
	local length = if chain ~= nil and #chain > 0 then #chain else 1
	rangeState.swingStep = if idle then 1 else rangeState.swingStep % length + 1
	local pose = if length > 1 and rangeState.swingStep >= length
		then FINISHER_POSE
		else math.min(rangeState.swingStep, 2)
	WeaponController.Swing(pose, interval)
	if MovementController.IsAirborne() then
		MovementController.AirHang(cfg.movement.airAttackHangSeconds)
	end
end

local function startDraw(variant: Types.RangeWeaponVariant, family: string): ()
	rangeState.drawStartedAt = os.clock()
	rangeState.drawFamily = family
	rangeState.targetLostAt = nil
	-- The server's own draw clock starts here and caps whatever charge the release claims.
	local remote = rangeState.requestRangeDraw
	if remote ~= nil then
		remote:FireServer(family)
	end
	WeaponController.Draw(variant.chargeSeconds or 0)
end

local function cancelDraw(): ()
	if rangeState.drawStartedAt == nil then
		return
	end
	rangeState.drawStartedAt = nil
	rangeState.drawFamily = ""
	rangeState.targetLostAt = nil
	WeaponController.Release()
end

local function releaseDraw(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	family: string,
	rig: LocalRig
): ()
	local charge = chargeOf(variant)
	rangeState.drawStartedAt = nil
	rangeState.drawFamily = ""
	rangeState.targetLostAt = nil
	WeaponController.Release()
	rangeAttack(cfg, variant, family, rig, charge, intervalOf(variant), false)
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
	local ready = os.clock() - rangeState.lastRangeAttackAt >= intervalOf(variant)
	local auto = autoFireOn(cfg) and not rangeState.rangeHeld
	local heldDraw = rangeState.rangeHeld or (tapFireOn(cfg) and touchDrawHeld(cfg))
	if rangeState.drawStartedAt == nil then
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
			rangeState.targetLostAt = nil
			release = chargeOf(variant) >= 1
		elseif chargeOf(variant) >= (variant.minChargeFraction or 0) then
			release = true
		else
			local now = os.clock()
			local lostAt = rangeState.targetLostAt or now
			rangeState.targetLostAt = lostAt
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

-- The slot actually changes here: a player's choice (requestSlot) or a cast (ruling 1).
local function setActiveSlot(slot: Stance): ()
	if slot == rangeState.activeSlot then
		return
	end
	rangeState.activeSlot = slot
	cancelDraw()
	rangeState.adsToggled = false
	rangeState.swingStep = 0
	rangeState.tapQueuedAt = nil
	-- The stance drives WeaponController's held model and the HUD's stance glyph.
	setStance(slot)
end

-- P3 abilities -------------------------------------------------------------------------------

-- The "busy" column of the P3 ability table: seconds a cast occupies the caster (no attacks,
-- no slot switch, no other ability; Mag Dump's own shots excepted). 0 = no lock.
local function busySecondsOf(ability: Types.RangeAbilityDef): number
	local id = ability.id
	if id == "whirlwind" or id == "magDump" or id == "overloadSweep" then
		return math.max(ability.durationSeconds or 0, 0)
	elseif
		id == "earthquake"
		or id == "leapSmash"
		or id == "impaleDash"
		or id == "overchargedShot"
	then
		return math.max(ability.delaySeconds or 0, 0)
	elseif id == "slugBurst" then
		return math.max((ability.count or 0) * (ability.tickSeconds or 0), 0)
	end
	return 0
end

local function isSlotState(value: any): boolean
	return typeof(value) == "table"
		and typeof(value.ability) == "string"
		and typeof(value.readyAt) == "number"
		and typeof(value.floorAt) == "number"
end

local function copySlotState(value: any): Types.RangeAbilitySlotState
	return { ability = value.ability, readyAt = value.readyAt, floorAt = value.floorAt }
end

-- Stops what this client started for a cast in `slot`: its prediction, and Mag Dump (ranged)
-- or the leap / lunge / Whirlwind walk (melee).
local function cancelLocalCast(slot: string): ()
	castState.pendingCasts[slot] = nil
	if slot == RANGED_SLOT then
		castState.magDump = nil
	else
		MovementController.CancelAbility()
	end
end

-- RangeAbility: the server's word on both cooldowns and the busy lock (on join, every cast, a
-- refusal, a family change and kill refunds). It replaces every prediction.
local function onAbilityState(payload: any): ()
	if
		typeof(payload) ~= "table"
		or not isSlotState(payload.melee)
		or not isSlotState(payload.ranged)
		or typeof(payload.busyUntil) ~= "number"
	then
		return
	end
	local refusedSeq = payload.refusedSeq
	castState.serverAbility = {
		melee = copySlotState(payload.melee),
		ranged = copySlotState(payload.ranged),
		busyUntil = payload.busyUntil,
		refusedSeq = if typeof(refusedSeq) == "number" then refusedSeq else nil,
	}
	-- The answer to a refused cast names it: everything this client started for it stops now
	-- (the timeout in reconcileCasts stays as the fallback for a lost answer).
	if typeof(refusedSeq) == "number" then
		for slot, pending in castState.pendingCasts do
			if pending.seq == refusedSeq then
				cancelLocalCast(slot)
			end
		end
	end
end

-- A cast answered by the server: the slot's cooldown moved past the cast, or (a busy ability
-- in a range with cooldowns off) the busy lock did. Nothing else moves them past the cast,
-- because a cast is only sent when the slot is ready and nothing is busy.
local function castAcked(
	state: Types.RangeAbilityState,
	slot: string,
	pending: PendingCast,
	early: number
): boolean
	local slotState = if slot == MELEE_SLOT then state.melee else state.ranged
	if slotState.readyAt > pending.castAt + early then
		return true
	end
	return pending.busyUntil > pending.castAt and state.busyUntil > pending.castAt + early
end

-- The server answers every cast it receives with a state, accepted or refused. An answered
-- cast hands over to the server's numbers; one still unanswered after two pings plus slack
-- was refused (or dropped), so its local effects stop; with no server state at all (an older
-- server) the prediction simply runs out.
local function reconcileCasts(cfg: Types.ProvingGroundsConfig): ()
	if next(castState.pendingCasts) == nil then
		return
	end
	local state = castState.serverAbility
	local now = serverNow()
	local early = cfg.abilities.earlySeconds
	local window = 2 * math.max(Players.LocalPlayer:GetNetworkPing(), 0) + CAST_ACK_SLACK_SECONDS
	for slot, pending in castState.pendingCasts do
		local answered = state ~= nil and castAcked(state, slot, pending, early)
		if not answered and state ~= nil and os.clock() - pending.sentClock > window then
			cancelLocalCast(slot)
		elseif answered or now >= math.max(pending.readyAt, pending.busyUntil) then
			castState.pendingCasts[slot] = nil
		end
	end
end

local function fillSlotView(
	target: Types.RangeAbilitySlotState,
	source: Types.RangeAbilitySlotState?,
	pending: PendingCast?,
	fallback: string
): ()
	local readyAt = if source ~= nil then source.readyAt else 0
	local floorAt = if source ~= nil then source.floorAt else 0
	if pending ~= nil then
		readyAt = math.max(readyAt, pending.readyAt)
		floorAt = math.max(floorAt, pending.floorAt)
	end
	target.ability = if source ~= nil then source.ability else fallback
	target.readyAt = readyAt
	target.floorAt = floorAt
end

local function abilityIdOf(cfg: Types.ProvingGroundsConfig, slot: Stance): string
	local _, def = slotFamily(cfg, slot)
	local ability = if def ~= nil then def.ability else nil
	return if ability ~= nil then ability.id else ""
end

-- The server state with any unanswered cast laid over it, so the HUD and the buttons react on
-- the press instead of a ping later. nil until either exists. One table, rewritten in place.
local function abilityView(cfg: Types.ProvingGroundsConfig): Types.RangeAbilityState?
	local state = castState.serverAbility
	local pendingMelee = castState.pendingCasts[MELEE_SLOT]
	local pendingRanged = castState.pendingCasts[RANGED_SLOT]
	if state == nil and pendingMelee == nil and pendingRanged == nil then
		return nil
	end
	fillSlotView(
		castState.abilityViewState.melee,
		if state ~= nil then state.melee else nil,
		pendingMelee,
		abilityIdOf(cfg, MELEE_SLOT)
	)
	fillSlotView(
		castState.abilityViewState.ranged,
		if state ~= nil then state.ranged else nil,
		pendingRanged,
		abilityIdOf(cfg, RANGED_SLOT)
	)
	local busyUntil = if state ~= nil then state.busyUntil else 0
	for _, pending in castState.pendingCasts do
		busyUntil = math.max(busyUntil, pending.busyUntil)
	end
	castState.abilityViewState.busyUntil = busyUntil
	return castState.abilityViewState
end

-- Busy = the server's lock, or the local window of a cast it has not answered yet.
local function isBusy(): boolean
	local now = serverNow()
	local state = castState.serverAbility
	if state ~= nil and now < state.busyUntil then
		return true
	end
	for _, pending in castState.pendingCasts do
		if now < pending.busyUntil then
			return true
		end
	end
	return false
end

-- Ready per the latest state, allowing abilities.earlySeconds as the server does.
local function slotReady(cfg: Types.ProvingGroundsConfig, slot: Stance): boolean
	local current = abilityView(cfg)
	if current == nil then
		return true
	end
	local slotState = if slot == MELEE_SLOT then current.melee else current.ranged
	return serverNow() >= slotState.readyAt - cfg.abilities.earlySeconds
end

-- The same world query RangeService makes: players skipped, collidable geometry only (crowd
-- enemies have no Instances).
local function worldParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignored: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignored, character)
		end
	end
	params.FilterDescendantsInstances = ignored
	return params
end

local function floorHit(from: Vector3, params: RaycastParams): number?
	local result = Workspace:Raycast(from, Vector3.new(0, -GROUND_PROBE_DEPTH, 0), params)
	return if result ~= nil then result.Position.Y else nil
end

-- The client mirror of RangeService.GroundPoint (P3 ruling 4), step for step, on the RAW
-- camera ray: where an aimed ability lands. The server resolves its own point; this one only
-- steers the leap, so the two agree wherever both see the same arena.
local function groundPoint(
	rig: LocalRig,
	origin: Vector3,
	direction: Vector3,
	castRange: number
): Vector3
	local params = worldParams()
	local root = rig.root.Position
	local range = math.max(castRange, 0)
	-- 1-2: the camera ray, long enough to cover castRange from the root, or its end.
	local length = range + (origin - root).Magnitude
	local unit = direction.Unit
	local hit = if length > 0 then Workspace:Raycast(origin, unit * length, params) else nil
	local point = if hit ~= nil then hit.Position else origin + unit * length
	-- 3: pulled back to castRange from the root on the flat, keeping its height.
	local flat = Vector3.new(point.X - root.X, 0, point.Z - root.Z)
	if flat.Magnitude > range then
		local pulled = flat.Unit * range
		point = Vector3.new(root.X + pulled.X, point.Y, root.Z + pulled.Z)
	end
	-- 4: onto the floor under it (probed from GROUND_PROBE_LIFT above), else level with the
	-- floor under the caster, else the caster's own feet.
	local floorY = floorHit(point + Vector3.new(0, GROUND_PROBE_LIFT, 0), params)
		or floorHit(root, params)
		or root.Y - rig.root.Size.Y * HALF - rig.humanoid.HipHeight
	return Vector3.new(point.X, floorY, point.Z)
end

-- What the caster's own client does at the cast (every visual is AbilityFx's, from the
-- server's CombatFxCast). Zones, Volley and Cluster Shell need nothing here.
local function applyCast(
	family: string,
	ability: Types.RangeAbilityDef,
	rig: LocalRig,
	origin: Vector3,
	direction: Vector3,
	castAt: number
): ()
	local id = ability.id
	if id == "whirlwind" then
		MovementController.Channel(ability.durationSeconds or 0, ability.moveSpeedMult or 1)
	elseif id == "leapSmash" then
		local target = groundPoint(rig, origin, direction, ability.castRange or 0)
		MovementController.Leap(target, ability.delaySeconds or 0, ability.height or 0)
	elseif id == "impaleDash" then
		-- The lunge flattens the aim itself; the server's capsule uses the same flat line.
		MovementController.Lunge(direction, ability.range or 0, ability.delaySeconds or 0)
	elseif id == "magDump" then
		castState.magDump = {
			family = family,
			untilAt = castAt + math.max(ability.durationSeconds or 0, 0),
			rateMult = math.max(ability.rateMult or 1, 0),
		}
	end
end

-- Spends one token of the mirrored rangeAbility bucket; false = the server would drop it.
local function takeCastToken(): boolean
	local cfg = combatConfig
	local perSecond = if cfg ~= nil then cfg.remotes.rangeAbilityCallsPerSecond else 0
	if perSecond <= 0 then
		return true
	end
	local clock = os.clock()
	castState.castTokens =
		math.min(perSecond, castState.castTokens + (clock - castState.castTokensClock) * perSecond)
	castState.castTokensClock = clock
	if castState.castTokens < 1 then
		return false
	end
	castState.castTokens -= 1
	return true
end

-- Q / E, gamepad L1 / R1 and the touch buttons all land here (P3 "Client APIs").
local function castAbility(slot: Stance): ()
	local remote = castState.requestRangeAbility
	local rig = localRig()
	if not rangeMode or remote == nil or rig == nil then
		return
	end
	local cfg = Tuning.Get()
	local family, def = slotFamily(cfg, slot)
	local ability = if def ~= nil then def.ability else nil
	if ability == nil then
		return
	end
	reconcileCasts(cfg)
	if isBusy() or not slotReady(cfg, slot) then
		return
	end
	if not takeCastToken() then
		return
	end
	local clock = os.clock()
	-- Ruling 1: the weapon you see matches the ability.
	setActiveSlot(slot)
	-- Ruling 4: the camera ray exactly as a shot sends it, without spread.
	local origin, direction = shotRay(rig)
	castState.abilitySeq += 1
	remote:FireServer(slot, castState.abilitySeq, origin, direction)
	local castAt = serverNow()
	local scale = math.max(cfg.abilities.cooldownScale, 0)
	local busySeconds = busySecondsOf(ability)
	castState.pendingCasts[slot] = {
		seq = castState.abilitySeq,
		castAt = castAt,
		sentClock = clock,
		readyAt = castAt + math.max(ability.cooldownSeconds, 0) * scale,
		floorAt = castAt + math.max(ability.minCooldownSeconds, 0) * scale,
		busyUntil = castAt + busySeconds,
	}
	if busySeconds > 0 then
		cancelDraw()
		rangeState.tapQueuedAt = nil
	end
	applyCast(family, ability, rig, origin, direction, castAt)
end

-- A player's slot change (1 / 2, gamepad Y, the touch slot button): refused while busy (P3
-- ruling 3). A cast switches through setActiveSlot directly.
local function requestSlot(slot: Stance): ()
	if isBusy() then
		return
	end
	setActiveSlot(slot)
end

local function toggleSlot(): ()
	requestSlot(if rangeState.activeSlot == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
end

-- This frame's faces for the touch buttons (RangeTouchButtons draws them and reports the
-- presses): the aim toggle, both ability cooldowns and the family the slot button switches to.
local function refreshTouch(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant?,
	busy: boolean
): ()
	if not RangeTouchButtons.IsBuilt() then
		return
	end
	RangeTouchButtons.SetAim(variant ~= nil and isRanged(variant), rangeState.adsActive)
	local current = abilityView(cfg)
	local now = serverNow()
	local _, meleeDef = slotFamily(cfg, MELEE_SLOT)
	local _, rangedDef = slotFamily(cfg, RANGED_SLOT)
	RangeTouchButtons.SetAbility(
		MELEE_SLOT,
		if meleeDef ~= nil then meleeDef.ability else nil,
		if current ~= nil then current.melee.readyAt - now else 0,
		cfg.abilities,
		busy
	)
	RangeTouchButtons.SetAbility(
		RANGED_SLOT,
		if rangedDef ~= nil then rangedDef.ability else nil,
		if current ~= nil then current.ranged.readyAt - now else 0,
		cfg.abilities,
		busy
	)
	local otherFamily, otherDef =
		slotFamily(cfg, if rangeState.activeSlot == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
	RangeTouchButtons.SetSlot(if otherDef ~= nil then otherDef.name else otherFamily, busy)
end

-- Frame step --------------------------------------------------------------------------------

-- Mag Dump: the ranged slot fires by itself at rate x rateMult along the crosshair.
local function stepMagDump(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	family: string,
	rig: LocalRig,
	dump: MagDump,
	frameSeconds: number
): ()
	local interval = 1 / math.max(variant.rate * dump.rateMult, MIN_RATE)
	for _ = 1, dueShots(interval, frameSeconds, not rangeState.firingStream) do
		rangeAttack(cfg, variant, family, rig, 1, interval, true)
	end
	rangeState.firingStream = true
end

local function rangeStep(deltaTime: number): ()
	local cfg = Tuning.Get()
	local rig = localRig()
	reconcileCasts(cfg)
	local variant, family = currentVariant(cfg)
	local dump = castState.magDump
	if
		dump ~= nil
		and (rig == nil or variant == nil or family ~= dump.family or serverNow() >= dump.untilAt)
	then
		castState.magDump = nil
		dump = nil
	end
	local busy = isBusy()
	-- A draw never survives its weapon: a slot switch, a loadout change, death or a busy
	-- ability drops it.
	if
		rangeState.drawStartedAt ~= nil
		and (
			rig == nil
			or variant == nil
			or family ~= rangeState.drawFamily
			or not isCharge(variant)
			or busy
		)
	then
		cancelDraw()
	end
	local wantAds = rig ~= nil
		and variant ~= nil
		and isRanged(variant)
		and (rangeState.adsHeld or rangeState.adsToggled)
	if wantAds ~= rangeState.adsActive then
		rangeState.adsActive = wantAds
		CameraController.SetAds(wantAds)
	end
	MovementController.SetSpeedMult(if rangeState.adsActive then cfg.shooting.adsSpeedMult else 1)
	refreshTouch(cfg, variant, busy)
	if rig == nil or variant == nil then
		rangeState.firingStream = false
		return
	end
	updateBloom(cfg, rig, deltaTime)
	if dump ~= nil then
		-- Mag Dump's shots are the ability (ruling 3): they run through the busy lock.
		if isRanged(variant) then
			stepMagDump(cfg, variant, family, rig, dump, deltaTime)
		end
		return
	end
	if busy or isCharge(variant) then
		rangeState.firingStream = false
		if busy then
			rangeState.tapQueuedAt = nil
		else
			stepCharge(cfg, variant, family, rig)
		end
		return
	end
	-- Asked every frame (not only when a shot is due) so the accumulator knows whether a
	-- stream is still running or a fresh press starts one.
	local wanted = wantsRangeAttack(cfg, variant, rig)
	if wanted then
		local interval = intervalOf(variant)
		for _ = 1, dueShots(interval, deltaTime, not rangeState.firingStream) do
			rangeAttack(cfg, variant, family, rig, 1, interval, false)
		end
	end
	rangeState.firingStream = wanted
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
		rangeState.device = nextDevice
	end
end

local function onRangeInputBegan(input: InputObject, processed: boolean): ()
	if processed then
		return -- a GUI button (dash, ADS, abilities, the tuning panel) owns this press
	end
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 then
		rangeState.rangeHeld = true
	elseif inputType == Enum.UserInputType.MouseButton2 then
		rangeState.adsHeld = true
	elseif inputType == Enum.UserInputType.Touch then
		local camera = Workspace.CurrentCamera
		local split = if camera ~= nil
			then camera.ViewportSize.X * Theme.COMBAT_CAMERA_TOUCH_SPLIT
			else math.huge
		if input.Position.X >= split then
			local start = Vector2.new(input.Position.X, input.Position.Y)
			rangeState.rangeTouches[input] =
				{ start = start, at = os.clock(), moved = 0, drawing = false }
		end
	elseif inputType == Enum.UserInputType.Keyboard then
		local key = input.KeyCode
		if key == Enum.KeyCode.One then
			requestSlot(MELEE_SLOT)
		elseif key == Enum.KeyCode.Two then
			requestSlot(RANGED_SLOT)
		elseif key == Enum.KeyCode.Q then
			castAbility(MELEE_SLOT)
		elseif key == Enum.KeyCode.E then
			castAbility(RANGED_SLOT)
		end
	end
end

local function onRangeInputChanged(input: InputObject): ()
	local state = rangeState.rangeTouches[input]
	if state ~= nil then
		local position = Vector2.new(input.Position.X, input.Position.Y)
		state.moved = math.max(state.moved, (position - state.start).Magnitude)
	end
end

local function onRangeInputEnded(input: InputObject): ()
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 then
		rangeState.rangeHeld = false
	elseif inputType == Enum.UserInputType.MouseButton2 then
		rangeState.adsHeld = false
	elseif inputType == Enum.UserInputType.Touch then
		local state = rangeState.rangeTouches[input]
		rangeState.rangeTouches[input] = nil
		local controls = Tuning.Get().controls
		if state == nil or state.drawing or controls.touchMode ~= "tapFire" then
			return
		end
		if
			os.clock() - state.at <= controls.tapMaxSeconds
			and state.moved <= controls.tapMaxPixels
		then
			rangeState.tapQueuedAt = os.clock()
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
	if action == ACTION.RANGE_FIRE then
		rangeState.rangeHeld = held
	elseif action == ACTION.RANGE_ADS then
		rangeState.adsHeld = held
	elseif began and action == ACTION.RANGE_SWAP then
		toggleSlot()
	elseif began and action == ACTION.RANGE_ABILITY_MELEE then
		castAbility(MELEE_SLOT)
	elseif began and action == ACTION.RANGE_ABILITY_RANGED then
		castAbility(RANGED_SLOT)
	end
	return Enum.ContextActionResult.Sink
end

local function startRange(): ()
	rangeState.rangeStarted = true
	rangeState.bloom = Tuning.Get().shooting.bloomMinDegrees
	local initial: Device? = deviceOf(UserInputService:GetLastInputType())
	if initial ~= nil then
		rangeState.device = initial
	elseif UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		rangeState.device = "touch"
	end
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local timeout = Theme.COMBAT_REMOTE_WAIT_SECONDS
		rangeState.requestRangeAttack =
			remotes:WaitForChild("RequestRangeAttack", timeout) :: RemoteEvent?
		rangeState.requestRangeDraw =
			remotes:WaitForChild("RequestRangeDraw", timeout) :: RemoteEvent?
		if rangeState.requestRangeAttack == nil then
			warn("[InputController] RequestRangeAttack missing — range attacks are disabled")
		end
	end)
	-- Separate wait, so an older server without abilities never delays the attack remotes.
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local timeout = Theme.COMBAT_REMOTE_WAIT_SECONDS
		local stateEvent = remotes:WaitForChild("RangeAbility", timeout) :: RemoteEvent?
		local castRemote = remotes:WaitForChild("RequestRangeAbility", timeout) :: RemoteEvent?
		if not rangeState.rangeStarted then
			return -- destroyed while waiting
		end
		castState.requestRangeAbility = castRemote
		if stateEvent ~= nil then
			table.insert(connections, stateEvent.OnClientEvent:Connect(onAbilityState))
		end
		if stateEvent == nil or castRemote == nil then
			warn("[InputController] RequestRangeAbility/RangeAbility missing — abilities are off")
		end
	end)
	table.insert(connections, UserInputService.InputBegan:Connect(onRangeInputBegan))
	table.insert(connections, UserInputService.InputChanged:Connect(onRangeInputChanged))
	table.insert(connections, UserInputService.InputEnded:Connect(onRangeInputEnded))
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(onDeviceChanged))
	-- A new body is never mid-ability locally: Mag Dump and the local busy windows end with
	-- the old one (MovementController drops its own motion). The server's lock still counts.
	table.insert(
		connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			castState.magDump = nil
			for _, pending in castState.pendingCasts do
				pending.busyUntil = pending.castAt
			end
		end)
	)
	local priority = Enum.ContextActionPriority.High.Value
	local bindings: { { action: string, key: Enum.KeyCode } } = {
		{ action = ACTION.RANGE_FIRE, key = Enum.KeyCode.ButtonR2 },
		{ action = ACTION.RANGE_ADS, key = Enum.KeyCode.ButtonL2 },
		{ action = ACTION.RANGE_SWAP, key = Enum.KeyCode.ButtonY },
		{ action = ACTION.RANGE_ABILITY_MELEE, key = Enum.KeyCode.ButtonL1 },
		{ action = ACTION.RANGE_ABILITY_RANGED, key = Enum.KeyCode.ButtonR1 },
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
	-- Touch only: the aim toggle, two ability buttons and the slot button. Still no attack
	-- button: attacks stay auto-fire / auto-swing / tap-fire.
	RangeTouchButtons.Build({
		onAim = function()
			rangeState.adsToggled = not rangeState.adsToggled
		end,
		onCast = castAbility,
		onToggleSlot = toggleSlot,
	})
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
		missionState.requestAttack =
			remotes:WaitForChild("RequestAttack", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		missionState.requestAbility =
			remotes:WaitForChild("RequestAbility", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		-- C1 adds RequestFire; an older server build simply leaves ranged fire inert.
		missionState.requestFire =
			remotes:WaitForChild("RequestFire", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if missionState.requestFire == nil then
			warn("[InputController] RequestFire missing — ranged attacks are disabled")
		end
		-- C2 adds RequestDraw; without it a C1 server still takes the client's charge.
		missionState.requestDraw =
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
		rangeState.rangeHeld = true -- the range should not show this button; a stray press still attacks
		return
	end
	attackBegan()
end

function InputController.AttackUp(): ()
	if rangeMode then
		rangeState.rangeHeld = false
		return
	end
	attackEnded()
end

-- Missions: the HUD's ability buttons. In the range the same call is a cast of that slot.
function InputController.UseAbility(slot: string): ()
	if rangeMode then
		if slot == MELEE_SLOT then
			castAbility(MELEE_SLOT)
		elseif slot == RANGED_SLOT then
			castAbility(RANGED_SLOT)
		end
		return
	end
	sendAbility(slot)
end

function InputController.ToggleStance(): ()
	if rangeMode then
		toggleSlot()
		return
	end
	setStance(if stance == MELEE_SLOT then RANGED_SLOT else MELEE_SLOT)
end

-- P3 range API (docs/INTERFACES.md "P3 contracts" → Client APIs).
-- Casts that slot's family ability, exactly as Q (melee) / E (ranged) do.
function InputController.CastAbility(slot: Stance): ()
	castAbility(slot)
end

-- Swaps the active slot, exactly as 1 / 2, gamepad Y and the touch slot button do; refused
-- while busy.
function InputController.ToggleSlot(): ()
	if rangeMode then
		toggleSlot()
	end
end

-- The latest RangeAbility state (server time), with an unanswered cast's predicted cooldown
-- and busy window laid over it; nil before either exists and outside the range. The table is
-- shared and rewritten in place: read it, never keep or write it.
function InputController.GetAbilityState(): Types.RangeAbilityState?
	if not rangeMode then
		return nil
	end
	return abilityView(Tuning.Get())
end

-- True while an ability occupies the caster (the server's busyUntil, or the local window of a
-- cast it has not answered yet).
function InputController.IsBusy(): boolean
	return rangeMode and isBusy()
end

-- P1 range API, read every frame by Feedback's Crosshair.
-- Half-angle in degrees of the cone the next shot is drawn from, ADS already applied; 0 for
-- a ready first shot, for melee and during Mag Dump. Crosshair radius in px = tan(rad(b)) /
-- tan(rad(fov) / 2) × viewport height / 2, using the live Camera.FieldOfView (ADS changes it).
function InputController.GetBloomDegrees(): number
	if not rangeMode then
		return 0
	end
	return nextSpreadDegrees(Tuning.Get())
end

-- True while aiming down sights (range gun only).
function InputController.IsAiming(): boolean
	return rangeState.adsActive
end

-- The crosshair ray: unshaken camera position and unit look direction.
function InputController.GetAimRay(): Ray
	local origin, look = CameraController.GetAimRay()
	return Ray.new(origin, look)
end

-- The loadout the server confirmed on TuneState, forwarded by FeedbackController (the one
-- TuneState listener). A family that is unknown or in the wrong slot makes that slot inert;
-- an unknown variant falls back to the family's config default wherever it is read. A draw
-- on a family that left the loadout is dropped on the next frame. P3 ruling 2: a slot whose
-- family changed loses its running ability, so this client's part of it stops at once.
function InputController.SetLoadout(nextLoadout: Types.RangeLoadout): ()
	if not rangeMode then
		rangeState.loadout = nextLoadout
		return
	end
	local cfg = Tuning.Get()
	local meleeBefore = slotFamily(cfg, MELEE_SLOT)
	local rangedBefore = slotFamily(cfg, RANGED_SLOT)
	rangeState.loadout = nextLoadout
	if slotFamily(cfg, MELEE_SLOT) ~= meleeBefore then
		cancelLocalCast(MELEE_SLOT)
	end
	if slotFamily(cfg, RANGED_SLOT) ~= rangedBefore then
		cancelLocalCast(RANGED_SLOT)
	end
end

-- The slot 1 / 2 / gamepad Y last picked (range only; missions keep GetStance).
function InputController.GetActiveSlot(): Stance
	return rangeState.activeSlot
end

-- The bow's draw progress 0-1 for the HUD ring. In the range it is never nil (0 while
-- nothing is drawn); in missions nil means nothing is drawn, which the mission HUD needs to
-- hide its dots. Display only: the server caps the real charge from its own draw stamp.
function InputController.GetCharge(): number?
	if rangeMode then
		local variant = currentVariant(Tuning.Get())
		return if variant ~= nil then chargeOf(variant) else 0
	end
	local startedAt = missionState.chargeStartedAt
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
	missionState.onStanceChanged = handler
end

-- Pushed from the Snapshot by CombatUIController, which pushes the same gear to
-- WeaponController: which weapons the profile actually holds right now.
function InputController.SetGear(nextGear: SlotTiers): ()
	missionState.gear = nextGear
	missionState.comboStep = 0
end

-- Pushed from RunState: the server's own cooldown clock, which overrides the prediction.
function InputController.SetAbilityReady(readyIn: SlotTiers): ()
	missionState.abilityReadyIn = readyIn
end

function InputController.SetPhase(nextPhase: string): ()
	missionState.phase = nextPhase
	if not inPlay() then
		missionState.attackHeld = false
		missionState.chargeStartedAt = nil
		missionState.holdToken += 1
	end
end

function InputController.Destroy(): ()
	rangeState.rangeStarted = false
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
	RangeTouchButtons.Destroy()
	table.clear(rangeState.rangeTouches)
	table.clear(castState.pendingCasts)
	castState.serverAbility = nil
	castState.magDump = nil
	rangeState.drawStartedAt = nil
	rangeState.drawFamily = ""
	rangeState.rangeHeld = false
	rangeState.adsHeld = false
	rangeState.adsToggled = false
	rangeState.adsActive = false
	for _, connection in missionState.characterConnections do
		connection:Disconnect()
	end
	table.clear(missionState.characterConnections)
	missionState.crosshairParams = nil
	missionState.holdToken += 1
	missionState.attackHeld = false
end

return InputController
