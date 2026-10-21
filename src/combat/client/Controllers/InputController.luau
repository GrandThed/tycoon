--!strict
-- Combat input for the dungeon place and the Studio range bench. The client is an input
-- device: it decides *when* the player swung, drew or cast, and it sends that intent. It never
-- sends damage and never names a hit; the server resolves every attack against its own crowd.
-- The run phase and the local member's wait are pushed in from CombatUIController, which owns
-- the RunState; the loadout from FeedbackController, which owns the TuneState.
--
-- Everything here is the range path, and it runs only with the range's combat
-- (CameraController.IsCrowdCombat, decided once at boot: the ProvingGrounds config ships). A
-- build without that config has no weapons and every level is refused, so this module then
-- binds nothing (L4 W1b deleted the C1 mission path that used to run there). A missing remote
-- (an older server build) or a dead character makes the input a silent no-op, never an error.
--
-- P1 Proving Grounds (docs/INTERFACES.md "P1 contracts", docs/COMBAT_DESIGN.md section 3):
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
--
-- P3.1 (docs/INTERFACES.md "P3.1 — a swing lands where you stand"), range path only:
--  * A swing is sent from the root position and the flat camera look of its own frame, and
--    the server resolves it there. On that same frame the swing handler (FeedbackController)
--    is handed exactly what was sent, so the hitbox effect appears where the swinger stands
--    instead of a round trip behind them.
--  * The combo step is predicted by the server's rule: per family, back to step 1 after
--    controls.comboResetSeconds without an accepted swing, else the chain's next step. That
--    one step picks the swing pose and the effect's arc. The strike that answers a swing
--    carries the step the server used, which replaces the prediction (ConfirmSwing); a
--    refusal takes back the swing it names, and nothing when it names a shot (RefuseSwing).
--
-- P4 (docs/INTERFACES.md "P4 contracts", ruling 4), range path only: while the player is
-- knocked down (MovementController.IsDown) nothing is sent: no attack, no draw, no cast, no
-- slot switch, and Mag Dump's own shots stop. The server refuses them all anyway. Held
-- inputs are kept, so a held trigger and touch auto-fire pick up on the get-up by themselves.
--
-- P5 (docs/INTERFACES.md "P5 contracts", Client): the range path is the input of every crowd
-- mission too (CameraController.IsCrowdCombat), with the range's remotes. In a mission nothing
-- is sent while the run phase is `lobby`, `summary` or `ended`, or while the player waits on
-- the pad for the next wave, exactly as while knocked down: the server refuses those anyway,
-- and this keeps the client from drawing swings it would take back. That one rule (CanAct)
-- also gates the slot switch and is what the HUD dims its ability tiles and buttons by.
--
-- L1b Wave 2 (docs/INTERFACES.md "Wave 2 — the long road" -> Client):
--  * One swing per jump (L1b-W2-14). Before a melee swing is predicted or sent, AirSwing asks
--    the server's question at the swing's own origin (SwingGate, which AirSwing feeds every
--    frame with the server's own samples: fix round ui-1); the second airborne swing of a jump
--    is dropped (no effect, no send, nothing queued for the landing). A held button or the phone's
--    auto-swing simply swings again at its rate once grounded. Abilities and shots are not gated.
--  * Auto-target's camp rule measures with HitShapes.FlatToRect (L1b-W2-24), and while the run
--    phase is `gate` (the boss room's countdown) it takes no body with a camp floor at all
--    (L1b-W2-25): every one in reach then is a held resident whose hit would read "BLOCKED".
--    Deliberate shots are untouched.
--  * Fix round (ui-2): auto-target never takes a body whose camp group rests (held or dormant
--    too), so a phone can sneak past a camp; it wakes one only by walking into its sight. The
--    whole rule is the pure CampAim.Takes.
--
-- L1b Wave 4 (docs/INTERFACES.md "L1b Wave 4 — no waits, no walls", L1b-W4-32): raiders chase
-- out of their camps and every hit on an awake one lands, so auto-target takes every awake camp
-- body wherever the local root stands; only the countdown and a resting group stay off limits.
-- The root and the engaged flag no longer enter the camp rule, so neither is kept for it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local GroundRule = require(sharedFolder:WaitForChild("GroundRule"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))
local WorldReact = require(sharedFolder:WaitForChild("WorldReact"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))
local CrowdRenderer = require(script.Parent:WaitForChild("CrowdRenderer"))
local RangeTouchButtons = require(script.Parent:WaitForChild("RangeTouchButtons"))
local AirSwing = require(script.Parent:WaitForChild("AirSwing"))
local CampAim = require(script.Parent:WaitForChild("CampAim"))
local ReactFx = require(script.Parent:WaitForChild("ReactFx"))

export type Stance = "melee" | "ranged"
-- P3.1: one melee swing exactly as it was sent to the server (seq, family, the root position
-- and the flat camera look), with the variant it was swung with, the predicted combo step
-- (1-based) that also picked its pose, and whether the swinger was in the air.
export type PredictedSwing = {
	seq: number,
	family: string,
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	heading: Vector3,
	step: number,
	airborne: boolean,
	-- The L2 W3 second fix round's Q5: AirSwing's verdict at the swing's origin, the server's own
	-- SwingGate question (WeaponService.OnAttack): an air swing freezes no water.
	airSwing: boolean,
}

-- L2-29: a shot of a continuous family as it left: family, variant, shot origin, direction.
export type StreamHandler = (
	family: string,
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	direction: Vector3
) -> ()

-- A module's top level is one Luau function, and Studio (debug level 2) gives it 200 local
-- registers, constants included. So related constants and state live in a few tables here and
-- the touch buttons in RangeTouchButtons; tools/check_compile.py is the gate.

-- Typed as the union so the active slot stays a Stance and not a bare string; both are still
-- ordinary strings wherever a slot name is passed to a shared module.
local MELEE_SLOT: Stance = "melee"
local RANGED_SLOT: Stance = "ranged"
local HALF = 0.5
-- ContextActionService action names.
local ACTION = table.freeze({
	RANGE_FIRE = "RangeFire",
	RANGE_ADS = "RangeAds",
	RANGE_SWAP = "RangeSwap",
	RANGE_ABILITY_MELEE = "RangeAbilityMelee",
	RANGE_ABILITY_RANGED = "RangeAbilityRanged",
})

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
local FINISHER_POSE = 3
-- Sustained fire sends one shot a frame, two only when the frame is longer than an interval.
local MAX_SHOTS_PER_FRAME = 2
-- Ruling 4's floor probe, shared with RangeService so both sides land on the same floor.
local GROUND_PROBE_LIFT = HitShapes.GROUND_PROBE_LIFT
local GROUND_PROBE_DEPTH = HitShapes.GROUND_PROBE_DEPTH
-- The abilities the server aims at WeaponService.GroundPoint (AbilityService's `target =
-- "ground"`): L1c §8 refuses each of them on ground too high above the caster's floor.
local GROUND_AIMED: { [string]: true } =
	{ leapSmash = true, bladeStorm = true, arrowRain = true, stormCoil = true }
-- A cast still unanswered after two pings plus this was refused or dropped by the server.
local CAST_ACK_SLACK_SECONDS = 0.3

local InputController = {}

local combatConfig: Types.CombatConfig? = nil

local connections: { RBXScriptConnection } = {}
-- The range's input path (P1-P4), which P5 missions use too. Decided once in Init.
local rangePath = false
-- P5: the run phases of a mission in which nothing is sent (the run has not begun or is over).
local IDLE_PHASES: { [string]: boolean } =
	table.freeze({ lobby = true, summary = true, ended = true })

-- Range-path state (P1-P3): the run phase, the slot and loadout, the held inputs, the draw and
-- the fire pacing.
-- drawing = a still hold that became a bow draw or a held beam (tapFire).
type TapState = { start: Vector2, at: number, moved: number, drawing: boolean }
-- P3.1: a swing the server has not answered yet. `length` is the chain it stepped through and
-- `sentAt` the os.clock it left at, which is all it takes to predict it again.
type PendingSwing = { seq: number, family: string, length: number, sentAt: number }
type RangeState = {
	rangeStarted: boolean,
	-- P5: this range path serves a mission (not the bench), so the run phase gates it, and
	-- so does waiting on the pad for the next wave (the local PartyMember.waiting).
	inMission: boolean,
	-- The run phase of the last RunState (SetPhase); "lobby" until one arrives.
	phase: string,
	waiting: boolean,
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
	-- P3.1 combo prediction. The server's side as last heard: the step each family's chain is
	-- on, and when the last swing it accepted left this client. Then the swings it has not
	-- answered yet, oldest first, and what they make of it: the steps and the clock the next
	-- swing is predicted from.
	confirmedSteps: { [string]: number },
	confirmedAt: number,
	pendingSwings: { PendingSwing },
	swingSteps: { [string]: number },
	lastSwingAt: number,
	onSwing: ((swing: PredictedSwing) -> ())?,
	-- L2-29: told on the frame a shot of a continuous family leaves (FlameFx draws the local
	-- stream from it, not from the server's answer).
	onStream: StreamHandler?,
	-- Sustained-fire accumulator (see dueShots): when the next shot is due, the interval it
	-- was scheduled at, and whether the previous frame wanted to fire (a stream in progress).
	nextShotAt: number,
	scheduledInterval: number,
	firingStream: boolean,
	-- Touch auto-fire: a held beam keeps firing until then after its target leaves the cone.
	beamHoldUntil: number,
	-- Touch auto-fire's line test (R13, R17), refilled every frame so it allocates nothing: the
	-- entries of the takeable bodies on the crosshair line, and (for a shot that bursts) every
	-- refused body sphere as flat triples (along the line, off it, burst reach).
	aimTaken: { number },
	aimRefused: { number },
	-- The last auto test found a takeable target but a refused body held the shot: a bow keeps
	-- its draw and a held beam stops, instead of firing as if the target had left.
	aimHeld: boolean,
	-- worldParams' cache (the L2 W2 second fix round's s1): touch auto-fire and the local flame
	-- each ask it every frame a stream is held. Rebuilt only after a character came or went
	-- (watchPlayer and forgetPlayer, through invalidateWorld), as WeaponService's is.
	worldParams: RaycastParams?,
	worldStale: boolean,
	-- One CharacterAdded watch per player, which is what makes worldParams stale.
	characterConnections: { [Player]: RBXScriptConnection },
}
local rangeState: RangeState = {
	rangeStarted = false,
	inMission = false,
	phase = "lobby",
	waiting = false,
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
	confirmedSteps = {},
	confirmedAt = -math.huge,
	pendingSwings = {},
	swingSteps = {},
	lastSwingAt = -math.huge,
	nextShotAt = -math.huge,
	scheduledInterval = 0,
	firingStream = false,
	beamHoldUntil = 0,
	aimTaken = {},
	aimRefused = {},
	aimHeld = false,
	worldParams = nil,
	worldStale = true,
	characterConnections = {},
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

-- Range path: no attack, draw, cast or slot switch now. Knocked down (P4), or (P5) a mission
-- whose run has not begun or is over, or a member waiting on the pad for the next wave.
local function cannotAct(): boolean
	return MovementController.IsDown()
		or (rangeState.inMission and (IDLE_PHASES[rangeState.phase] == true or rangeState.waiting))
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

-- A character came or went: the cached world query leaves it out or takes it in again.
local function invalidateWorld(): ()
	rangeState.worldStale = true
end

local function watchPlayer(player: Player): ()
	local existing: RBXScriptConnection? = rangeState.characterConnections[player]
	if existing ~= nil then
		existing:Disconnect()
	end
	rangeState.characterConnections[player] = player.CharacterAdded:Connect(invalidateWorld)
	invalidateWorld()
end

local function forgetPlayer(player: Player): ()
	local existing: RBXScriptConnection? = rangeState.characterConnections[player]
	rangeState.characterConnections[player] = nil
	if existing ~= nil then
		existing:Disconnect()
	end
	invalidateWorld()
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
-- melee, for a continuous (stream) family and during Mag Dump, otherwise the bloom with the ADS
-- multiplier. A stream takes no bloom (the L2 W2 second fix round's m3): its capsule then runs
-- along the crosshair line, the line FlameFx draws the local flame on and touch auto-fire tests a
-- bramble with, so the drawn flame and the server's capsule are one.
local function nextSpreadDegrees(cfg: Types.ProvingGroundsConfig): number
	local variant = currentVariant(cfg)
	if
		variant == nil
		or not isRanged(variant)
		or variant.continuous == true
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

-- The same world query RangeService makes: players skipped, collidable geometry only (crowd
-- enemies have no Instances). Cached until a character comes or goes (RangeState.worldStale).
local function worldParams(): RaycastParams
	local cached = rangeState.worldParams
	if cached ~= nil and not rangeState.worldStale then
		return cached
	end
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
	rangeState.worldParams = params
	rangeState.worldStale = false
	return params
end

-- How far a stream's capsule runs from `origin` along the unit `look` before the world stops it,
-- up to `range`: WeaponService's worldReach, with the same query. A colliding bramble stops it on
-- its face, which is how the capsule then touches the bramble (L2-34).
local function streamReach(origin: Vector3, look: Vector3, range: number): number
	if range <= 0 then
		return 0
	end
	local result = Workspace:Raycast(origin, look * range, worldParams())
	if result == nil then
		return range
	end
	return (result.Position - origin).Magnitude
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

-- Whether auto-fire and auto-swing may take this body by themselves (CampAim): a camp's body
-- only while its group is awake and never in the boss room's countdown; a body with no camp
-- floor (the range) always.
local function autoMayTake(id: number): boolean
	local centre, _, resting = CrowdRenderer.CampFloor(id)
	return CampAim.Takes(centre ~= nil, resting, rangeState.phase)
end

-- CrowdRenderer reports the ground point; the body sphere is centred at height/2 and the
-- head sphere sits at the top (INTERFACES P1 decision 1).
-- R13: the trigger is a takeable body in the assist cone, but the shot flies the crosshair line
-- itself and pierces, so it is held while a refused body lies on that line within the shot's hits
-- (HitShapes.CrowdRay, the server's ray shape; CampAim.ShotSpares). A refused body gets the lag
-- pad on top of the variant's: a hold costs a frame, a wrong shot wakes a camp.
-- R17: a shot that bursts where it stops (splashRadius, blastRadius) is also held while a refused
-- body sphere lies within the burst (+ its radius, the variant's pad and the lag pad) of the
-- predicted stop span (CampAim.StopSpan, CampAim.BurstSpares). Auto-fire releases a bow only at a
-- full draw, so a Longbow's full-draw blast always counts.
local function enemyInSights(
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	look: Vector3,
	degrees: number,
	lagPad: number
): boolean
	local range = variant.range
	local width = variant.width or 0
	local limit = math.rad(degrees)
	local found = false
	local refusedEntry: number? = nil
	local burst = variant.splashRadius or variant.blastRadius or 0
	local takenEntries = rangeState.aimTaken
	local refusedSpheres = rangeState.aimRefused
	table.clear(takenEntries)
	table.clear(refusedSpheres)
	CrowdRenderer.ForEach(
		function(id: number, position: Vector3, radius: number, headRadius: number, height: number)
			local taken = autoMayTake(id)
			local pad = if taken then variant.pad else variant.pad + lagPad
			local entry = HitShapes.CrowdRay(
				origin,
				look,
				range,
				width,
				pad,
				position,
				radius,
				height,
				headRadius
			)
			if not taken then
				if entry ~= nil and (refusedEntry == nil or entry < refusedEntry) then
					refusedEntry = entry
				end
				if burst > 0 then
					-- Both spheres, as the line test reads both: the nearer one decides.
					for sphere = 1, 2 do
						local r = if sphere == 1 then radius else headRadius
						local lift = if sphere == 1 then height * HALF else height - headRadius
						local offset = position + Vector3.new(0, lift, 0) - origin
						local along = offset:Dot(look)
						table.insert(refusedSpheres, along)
						table.insert(refusedSpheres, (offset - look * along).Magnitude)
						table.insert(refusedSpheres, burst + r + variant.pad + lagPad)
					end
				end
				return
			end
			if entry ~= nil then
				table.insert(takenEntries, entry)
			end
			if found then
				return
			end
			local body = position + Vector3.new(0, height * HALF, 0)
			local head = position + Vector3.new(0, height - headRadius, 0)
			found = sphereInSights(origin, look, range, limit, body, radius + lagPad)
				or sphereInSights(origin, look, range, limit, head, headRadius + lagPad)
		end
	)
	local spares = found and CampAim.ShotSpares(refusedEntry, takenEntries, variant.pierce)
	if spares and burst > 0 then
		local from, to = CampAim.StopSpan(takenEntries, variant.pierce, range)
		for index = 1, #refusedSpheres, 3 do
			local along, off, reach =
				refusedSpheres[index], refusedSpheres[index + 1], refusedSpheres[index + 2]
			if not CampAim.BurstSpares(from, to, along, off, reach) then
				spares = false
				break
			end
		end
	end
	rangeState.aimHeld = found and not spares
	return spares
end

-- The same shape the server builds for this variant, via the shared HitShapes geometry. A
-- capsule (spear) runs from the root along the flat look for `range`, `width` across.
local function inMeleeShape(
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	forward: Vector3,
	range: number,
	extraPad: number,
	centre: Vector3,
	radius: number
): boolean
	local pad = variant.pad + extraPad
	local shape = variant.shape
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

-- `range` is the variant's, or a stream's reach cut at the first wall (c-m4: the server cuts
-- its capsule there, so a body behind the wall is neither a target nor a hold). Returns whether a
-- takeable body is inside with no refused one, then whether a refused body is inside.
local function enemyInReach(
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	forward: Vector3,
	range: number,
	extraPad: number,
	lagPad: number
): (boolean, boolean)
	local found = false
	local refused = false
	CrowdRenderer.ForEach(
		function(id: number, position: Vector3, radius: number, headRadius: number, height: number)
			if refused then
				return
			end
			-- R13: a swing or a cone hits everything in its shape, so one refused body inside
			-- the padded shape holds it, whatever the trigger was.
			local taken = autoMayTake(id)
			if taken and found then
				return
			end
			local body = position + Vector3.new(0, height * HALF, 0)
			local head = position + Vector3.new(0, height - headRadius, 0)
			local inside = inMeleeShape(
				variant,
				origin,
				forward,
				range,
				extraPad,
				body,
				radius + lagPad
			) or inMeleeShape(
				variant,
				origin,
				forward,
				range,
				extraPad,
				head,
				headRadius + lagPad
			)
			if not inside then
				return
			end
			if taken then
				found = true
			else
				refused = true
			end
		end
	)
	-- A shape hits everything inside it, so any refused body holds it, also once the trigger
	-- has left (a held stream's ride-out never reaches a resting body).
	rangeState.aimHeld = refused
	return found and not refused, refused
end

-- c-M1: a reactive block auto-fire's stream would burn (WorldReact.Wants, on the server's own
-- Touches): its Part's `React` is the held family's element, its `Heat` is under 1, and the
-- capsule from the shot origin, cut at the first wall, touches its box padded by levels.react.pad.
local function reactOnAuto(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	look: Vector3,
	reach: number
): boolean
	local element = Unlocks.ElementOf(cfg.weapons, (activeFamily(cfg)))
	if element == nil then
		return false
	end
	local pad = WorldReact.Pad(if combatConfig ~= nil then combatConfig.levels.react else nil)
	local stream: WorldReact.Strike = {
		shape = variant.shape,
		origin = origin,
		direction = look,
		size = reach,
		width = variant.width,
	}
	local found = false
	ReactFx.ForEachPart(function(part: BasePart, react: any, heat: any)
		if found then
			return
		end
		found = WorldReact.Wants(
			element,
			react,
			heat,
			stream,
			WorldReact.BoxOf(part.Position, part.Size),
			pad
		)
	end)
	return found
end

-- The strike the server builds for an ice swing at `step` (WorldReact.SwingStrike, with the swing's
-- own air verdict `airborne`), its arc cut to touch auto-swing's `cone` (nil = uncut).
local function autoIceStrike(
	variant: Types.RangeWeaponVariant,
	step: number,
	origin: Vector3,
	heading: Vector3,
	cone: number?,
	airborne: boolean
): WorldReact.Strike
	local strike = WorldReact.SwingStrike(variant, step, origin, heading, airborne)
	local arc = strike.arcDegrees
	if arc ~= nil and cone ~= nil then
		strike.arcDegrees = math.min(arc, cone)
	end
	return strike
end

-- L2-55: with no body in the swing's shape, an ice family swings at water it would freeze: an
-- unfrozen ice cell (ReactFx.ForEachIce) that WorldReact.Chills, the server's own rule, names for
-- the strike the server builds from this swing (WorldReact.SwingStrike on the root and the flat
-- camera look: fix round c-m3). The L2 W3 fix round narrows it; each rule can only remove a
-- swing, never add one:
--  * Q1: every step's arc is cut to controls.iceAutoDegrees, so walking along water (Road2's
--    south half beside the creek) does not swing at it; only water ahead does.
--  * The combo step the swing will get is the server's to decide, so a cell triggers only when
--    the strike of every step of the chain chills it.
--  * c-m4: never while airborne. The freeze band was sized for a grounded origin (L2-54), and an
--    air swing would spend the jump's one swing and hang the body (AirSwing, AirHang). The third
--    fix round's fd-s1: "airborne" is the server's own question, AirSwing.Judge at the swing's
--    origin (SwingGate's footprint test, lag 0, no side effect), never the Humanoid's floor
--    sensor, whose width is not the root's footprint: a phone on the bank's very lip would
--    otherwise swing at full rate, freeze nothing and spend the jump's air swing on the first.
--  * The second fix round's Q5: never at a cell a player's body stands in (WorldReact.Holds, the
--    server's rule; the bodies are read only once a cell has passed every other test).
-- A frozen cell never triggers. Far from the water this costs AirSwing's five floor rays and one
-- rectangle test (c-m1).
local function iceOnAuto(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	rig: LocalRig,
	heading: Vector3
): boolean
	if Unlocks.ElementOf(cfg.weapons, (activeFamily(cfg))) ~= "ice" then
		return false
	end
	local reachDown, ahead = ReactFx.IceReach()
	if reachDown == nil or ahead == nil then
		return false
	end
	local origin = rig.root.Position
	local allowed, inAir = AirSwing.Judge(origin, rig.root, rig.humanoid)
	if not allowed or inAir then
		return false
	end
	local coneValue = (cfg.controls :: any).iceAutoDegrees
	local cone: number? = if type(coneValue) == "number" then coneValue else nil
	-- A cell every step chills is one step 1 chills, so step 1's reach picks the cells asked.
	local first = autoIceStrike(variant, 1, origin, heading, cone, inAir)
	local strikes: { WorldReact.Strike }? = nil
	local bodies: { WorldReact.Box }? = nil
	return ReactFx.ForEachIce(
		first.origin,
		first.size + ahead,
		reachDown,
		function(_part: BasePart, box: WorldReact.Box): boolean
			if not WorldReact.Chills(first, box, reachDown, ahead) then
				return false
			end
			-- The other steps' strikes are built only once a cell is within reach.
			local others = strikes
			if others == nil then
				local made: { WorldReact.Strike } = {}
				local chain = variant.chain
				for step = 2, if chain ~= nil then #chain else 1 do
					table.insert(made, autoIceStrike(variant, step, origin, heading, cone, inAir))
				end
				strikes = made
				others = made
			end
			for _, strike in others :: { WorldReact.Strike } do
				if not WorldReact.Chills(strike, box, reachDown, ahead) then
					return false
				end
			end
			local around = bodies
			if around == nil then
				around = ReactFx.Bodies()
				bodies = around
			end
			return not WorldReact.Holds(box, around, ReactFx.IceSink())
		end
	)
end

local function autoFireOn(cfg: Types.ProvingGroundsConfig): boolean
	return rangeState.device == "touch" and cfg.controls.touchMode == "autoFire"
end

local function tapFireOn(cfg: Types.ProvingGroundsConfig): boolean
	return rangeState.device == "touch" and cfg.controls.touchMode == "tapFire"
end

-- Touch auto-fire's "on target": the assist cone for guns and bows, the whole cone for a cone
-- gun (it hits everything inside) and the whole capsule for a stream (L2-48: the short
-- Flamethrower fires only with a body inside its reach), the padded melee shape for melee. A
-- stream's capsule is cut at the first wall (c-m4), and with no body in it the stream also fires
-- at a block it would burn (c-M1: a phone has no trigger), never past a resting body in it. A
-- melee swing likewise, with no body in its shape, swings at water an ice family would freeze
-- (L2-55), never past a resting body in it.
local function targetOnAuto(
	cfg: Types.ProvingGroundsConfig,
	variant: Types.RangeWeaponVariant,
	rig: LocalRig
): boolean
	local controls = cfg.controls
	local lagPad = controls.assistLagPad
	local root = rig.root.Position
	if isRanged(variant) then
		local origin, look = shotRay(rig)
		if variant.shape == "capsule" then
			local reach = streamReach(origin, look, variant.range)
			local onBody, refused = enemyInReach(variant, origin, look, reach, 0, lagPad)
			if onBody or refused then
				return onBody
			end
			return reactOnAuto(cfg, variant, origin, look, reach)
		elseif variant.shape == "cone" then
			return (enemyInReach(variant, origin, look, variant.range, 0, lagPad))
		end
		return enemyInSights(variant, origin, look, controls.autoFireAssistDegrees, lagPad)
	end
	local look = flatCameraLook()
	local onBody, refused =
		enemyInReach(variant, root, look, variant.range, controls.autoSwingPad, lagPad)
	if onBody or refused then
		return onBody
	end
	return iceOnAuto(cfg, variant, rig, look)
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
	-- A held beam rides out a target flickering on the cone's edge instead of stuttering, but
	-- never through a refused body that held it (R13, R17).
	return continuous and not rangeState.aimHeld and os.clock() < rangeState.beamHoldUntil
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

-- P3.1 ruling 6, the server's combo rule for one swing (RangeService.OnAttack and
-- resolveMelee): a family's chain restarts when more than controls.comboResetSeconds passed
-- since the last accepted swing, then moves on one step and wraps after its last. The step is
-- written into `steps` and returned.
local function advanceCombo(
	steps: { [string]: number },
	family: string,
	length: number,
	sinceLast: number,
	resetSeconds: number
): number
	local previous = if sinceLast > resetSeconds then 0 else steps[family] or 0
	local step = previous % length + 1
	steps[family] = step
	return step
end

-- The prediction rebuilt from the server's word: its steps and its clock, then every swing it
-- has not answered yet, in the order they left.
local function replaySwings(): ()
	local resetSeconds = Tuning.Get().controls.comboResetSeconds
	local steps = table.clone(rangeState.confirmedSteps)
	local at = rangeState.confirmedAt
	for _, pending in rangeState.pendingSwings do
		advanceCombo(steps, pending.family, pending.length, pending.sentAt - at, resetSeconds)
		at = pending.sentAt
	end
	rangeState.swingSteps = steps
	rangeState.lastSwingAt = at
end

-- The server answers every swing it takes, with a strike or a refusal. One still unanswered
-- after COMBAT_RANGE_SWING_ANSWER_SECONDS was dropped without a word: it never moved the
-- server's combo, so it leaves the prediction as well.
local function forgetStaleSwings(now: number): ()
	local pending = rangeState.pendingSwings
	local forgot = false
	while #pending > 0 and now - pending[1].sentAt > Theme.COMBAT_RANGE_SWING_ANSWER_SECONDS do
		table.remove(pending, 1)
		forgot = true
	end
	if forgot then
		replaySwings()
	end
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
	-- L1b-W2-14: a swing the server would refuse is never sent. Asked before anything moves (the
	-- seq, the pacing, the combo, a queued tap), so a dropped swing leaves no trace.
	local swingAirborne = false
	if not isRanged(variant) then
		local allowed, inAir = AirSwing.Judge(rig.root.Position, rig.root, rig.humanoid)
		if not allowed then
			rangeState.tapQueuedAt = nil
			return
		end
		swingAirborne = inAir
	end
	local now = os.clock()
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
			WeaponController.Shoot(origin, direction, variant.range)
		end
		local onStream = rangeState.onStream
		if onStream ~= nil and variant.continuous == true then
			onStream(family, variant, origin, direction)
		end
		return
	end
	-- P3.1: the server resolves the swing at this origin along this heading, so it lands where
	-- the swinger's own screen has them.
	local origin = rig.root.Position
	local forward = flatCameraLook()
	remote:FireServer(family, rangeState.rangeSeq, origin, forward, false, charge)
	AirSwing.Took(swingAirborne)
	forgetStaleSwings(now)
	local chain = variant.chain
	local length = if chain ~= nil and #chain > 0 then #chain else 1
	local step = advanceCombo(
		rangeState.swingSteps,
		family,
		length,
		now - rangeState.lastSwingAt,
		cfg.controls.comboResetSeconds
	)
	rangeState.lastSwingAt = now
	table.insert(
		rangeState.pendingSwings,
		{ seq = rangeState.rangeSeq, family = family, length = length, sentAt = now }
	)
	local pose = if length > 1 and step >= length then FINISHER_POSE else math.min(step, 2)
	WeaponController.Swing(pose, interval)
	local airborne = MovementController.IsAirborne()
	local handler = rangeState.onSwing
	if handler ~= nil then
		handler({
			seq = rangeState.rangeSeq,
			family = family,
			variant = variant,
			origin = origin,
			heading = forward,
			step = step,
			airborne = airborne,
			airSwing = swingAirborne,
		})
	end
	if airborne then
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
--    if the target leaves, releases at >= minChargeFraction; below it, or while a refused
--    body holds the shot, the draw waits controls.tapBufferSeconds before it is dropped.
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
		elseif not rangeState.aimHeld and chargeOf(variant) >= (variant.minChargeFraction or 0) then
			-- A target that left releases an under-charged arrow; one a refused body holds does
			-- not, or the hold would loose the very arrow it held (R13, R17).
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
	rangeState.tapQueuedAt = nil
	-- The slot picks the model WeaponController (through HeldWeapons) puts in the hand.
	WeaponController.SetStance(slot)
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
		-- L2-50: Frost Quake is the Earthquake launcher with its own look.
		or id == "frostQuake"
		or id == "leapSmash"
		or id == "impaleDash"
		or id == "overchargedShot"
	then
		return math.max(ability.delaySeconds or 0, 0)
	elseif id == "slugBurst" or id == "dragonBreath" then
		-- L2-29: Dragon's Breath is the Slug Burst launcher with flame cones.
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

local function floorHit(from: Vector3, params: RaycastParams): number?
	local result = Workspace:Raycast(from, Vector3.new(0, -GROUND_PROBE_DEPTH, 0), params)
	return if result ~= nil then result.Position.Y else nil
end

-- The client mirror of RangeService.GroundPoint (P3 ruling 4), step for step, on the RAW
-- camera ray: where an aimed ability lands. The server resolves its own point; this one steers
-- the leap and refuses a ground-aimed cast early, so the two agree wherever both see the same
-- arena.
-- L1c §8: nil = refused, as WeaponService.GroundPoint refuses it, with the same shared rule
-- (WallClip.GroundFloor, through GroundRule.Floor): ground more than the caster's own rise above
-- the caster's floor. Without
-- it a leap aimed over a tall wall lands its probe on the wall's top, a perch that sees into a
-- walled camp. L2-4: the rise is per player, jumpHeight plus doubleJumpHeight only for one who
-- owns the double jump (the Player attribute the server sets; the server reads the same one).
-- Also returns the caster's floor it measured from (GroundFloor's second value): the leap's apex
-- stands on it (L2 W1 F1).
local function groundPoint(
	rig: LocalRig,
	origin: Vector3,
	direction: Vector3,
	castRange: number
): (Vector3?, number)
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
	-- floor under the caster; over a void (L2 W1 F2) that is the feet less the caster's rise.
	-- GroundRule.Floor is the whole step, the same call WeaponService.GroundPoint makes (the fix
	-- round's c4): it reads the movement heights and the double jump itself (the second fix
	-- round's Minor 1), so this side passes only what its rays found and cannot drift.
	local floorY, casterFloor = GroundRule.Floor(
		Players.LocalPlayer,
		floorHit(root, params),
		root.Y - rig.root.Size.Y * HALF - rig.humanoid.HipHeight,
		floorHit(point + Vector3.new(0, GROUND_PROBE_LIFT, 0), params)
	)
	if floorY == nil then
		return nil, casterFloor
	end
	return Vector3.new(point.X, floorY, point.Z), casterFloor
end

-- What the caster's own client does at the cast (every visual is AbilityFx's, from the
-- server's CombatFxCast). Zones, Volley and Cluster Shell need nothing here. `groundTarget`
-- is a ground-aimed ability's point, resolved before the cast was sent.
local function applyCast(
	family: string,
	ability: Types.RangeAbilityDef,
	direction: Vector3,
	castAt: number,
	groundTarget: Vector3?,
	casterFloor: number
): ()
	local id = ability.id
	if id == "whirlwind" then
		MovementController.Channel(ability.durationSeconds or 0, ability.moveSpeedMult or 1)
	elseif id == "leapSmash" then
		if groundTarget ~= nil then
			MovementController.Leap(
				groundTarget,
				ability.delaySeconds or 0,
				ability.height or 0,
				casterFloor
			)
		end
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
	if not rangePath or remote == nil or rig == nil or cannotAct() then
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
	-- Ruling 4: the camera ray exactly as a shot sends it, without spread.
	local origin, direction = shotRay(rig)
	-- L1c §8 (lead's ruling: every ground-aimed ability): a cast the server would refuse
	-- (ground too high above the caster's floor) is not sent, so it costs no cooldown, no token
	-- and no predicted leap.
	local groundTarget: Vector3? = nil
	local casterFloor = 0
	if GROUND_AIMED[ability.id] then
		groundTarget, casterFloor = groundPoint(rig, origin, direction, ability.castRange or 0)
		if groundTarget == nil then
			return
		end
	end
	if not takeCastToken() then
		return
	end
	local clock = os.clock()
	-- Ruling 1: the weapon you see matches the ability.
	setActiveSlot(slot)
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
	applyCast(family, ability, direction, castAt, groundTarget, casterFloor)
end

-- A player's slot change (1 / 2, gamepad Y, the touch slot button): refused while busy (P3
-- ruling 3) and whenever nothing can be done (knocked down, P4; a mission's idle phases and
-- the wait on the pad, P5), which is exactly when the touch slot button is dimmed. A cast
-- switches through setActiveSlot directly.
local function requestSlot(slot: Stance): ()
	if isBusy() or cannotAct() then
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
	-- Knocked down, or a mission phase with no fight in it: the same hold either way.
	local down = cannotAct()
	-- A draw never survives its weapon: a slot switch, a loadout change, death, a busy
	-- ability or being knocked down drops it.
	if
		rangeState.drawStartedAt ~= nil
		and (
			rig == nil
			or variant == nil
			or family ~= rangeState.drawFamily
			or not isCharge(variant)
			or busy
			or down
		)
	then
		cancelDraw()
	end
	local wantAds = rig ~= nil
		and variant ~= nil
		and not down
		and isRanged(variant)
		and (rangeState.adsHeld or rangeState.adsToggled)
	if wantAds ~= rangeState.adsActive then
		rangeState.adsActive = wantAds
		CameraController.SetAds(wantAds)
	end
	MovementController.SetSpeedMult(if rangeState.adsActive then cfg.shooting.adsSpeedMult else 1)
	-- The ability and slot buttons dim while down as they do while busy: neither would act.
	refreshTouch(cfg, variant, busy or down)
	if rig == nil or variant == nil then
		rangeState.firingStream = false
		return
	end
	updateBloom(cfg, rig, deltaTime)
	if down then
		-- P4: nothing is sent while knocked down, Mag Dump's own shots included. Only what
		-- was queued is dropped; a held trigger stays held and touch auto-fire is asked again
		-- every frame, so both attack again on the get-up without another press.
		rangeState.firingStream = false
		rangeState.tapQueuedAt = nil
		return
	end
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
	-- s1: worldParams' cache goes stale whenever a character comes or goes.
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(forgetPlayer))
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
	combatConfig = Catalog.GetCombatConfig()
	rangePath = CameraController.IsCrowdCombat()
	rangeState.inMission = rangePath and not CameraController.IsRange()
	MovementController.Init()
end

-- Without the range's combat there is nothing to fight with, so nothing is bound
-- (CombatUIController says so once).
function InputController.Start(): ()
	if not rangePath then
		return
	end
	-- MovementController is a sub-controller of the range path, started from here so the
	-- client boot list does not change with the mode.
	startRange()
	MovementController.Start()
end

-- P3 range API (docs/INTERFACES.md "P3 contracts" → Client APIs).
-- Casts that slot's family ability, exactly as Q (melee) / E (ranged) do.
function InputController.CastAbility(slot: Stance): ()
	castAbility(slot)
end

-- Swaps the active slot, exactly as 1 / 2, gamepad Y and the touch slot button do; refused
-- while busy.
function InputController.ToggleSlot(): ()
	if rangePath then
		toggleSlot()
	end
end

-- The latest RangeAbility state (server time), with an unanswered cast's predicted cooldown
-- and busy window laid over it; nil before either exists and outside the range. The table is
-- shared and rewritten in place: read it, never keep or write it.
function InputController.GetAbilityState(): Types.RangeAbilityState?
	if not rangePath then
		return nil
	end
	return abilityView(Tuning.Get())
end

-- True while an ability occupies the caster (the server's busyUntil, or the local window of a
-- cast it has not answered yet).
function InputController.IsBusy(): boolean
	return rangePath and isBusy()
end

-- P5: false whenever the range path sends no attack, cast or slot switch: knocked down, or in a
-- mission an idle phase or the wait on the pad. The HUD veils its ability tiles by the same
-- rule the input obeys, so a tile never looks ready while its key does nothing.
function InputController.CanAct(): boolean
	return not cannotAct()
end

-- P1 range API, read every frame by Feedback's Crosshair.
-- Half-angle in degrees of the cone the next shot is drawn from, ADS already applied; 0 for
-- a ready first shot, for melee and during Mag Dump. Crosshair radius in px = tan(rad(b)) /
-- tan(rad(fov) / 2) × viewport height / 2, using the live Camera.FieldOfView (ADS changes it).
function InputController.GetBloomDegrees(): number
	if not rangePath then
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

-- c-M2: the line the local player's shots leave on (the crosshair line from the head's depth,
-- exactly what rangeAttack sends); nil, nil without a living character. FlameFx draws the local
-- flame along it, so the drawn tip is where the server's capsule ends.
function InputController.ShotRay(): (Vector3?, Vector3?)
	local rig = localRig()
	if rig == nil then
		return nil, nil
	end
	return shotRay(rig)
end

-- c-M2: how far a stream runs from `origin` along the unit `look` before the world stops it, up to
-- `range` (the server's worldReach; touch auto-fire cuts its capsule with the same call).
function InputController.StreamReach(origin: Vector3, look: Vector3, range: number): number
	return streamReach(origin, look, range)
end

-- The loadout the server confirmed on TuneState, forwarded by FeedbackController (the one
-- TuneState listener). A family that is unknown or in the wrong slot makes that slot inert;
-- an unknown variant falls back to the family's config default wherever it is read. A draw
-- on a family that left the loadout is dropped on the next frame. P3 ruling 2: a slot whose
-- family changed loses its running ability, so this client's part of it stops at once.
function InputController.SetLoadout(nextLoadout: Types.RangeLoadout): ()
	if not rangePath then
		rangeState.loadout = nextLoadout
		return
	end
	local cfg = Tuning.Get()
	local held = rangeState.loadout
	local meleeBefore = slotFamily(cfg, MELEE_SLOT)
	local rangedBefore = slotFamily(cfg, RANGED_SLOT)
	local variantBefore = if held ~= nil then held.variants[meleeBefore] else nil
	rangeState.loadout = nextLoadout
	local meleeNow = slotFamily(cfg, MELEE_SLOT)
	if meleeNow ~= meleeBefore then
		cancelLocalCast(MELEE_SLOT)
	end
	if slotFamily(cfg, RANGED_SLOT) ~= rangedBefore then
		cancelLocalCast(RANGED_SLOT)
	end
	-- P3.1: the server restarts a family's combo when the family or its variant is picked, so
	-- the prediction does too.
	if meleeNow ~= meleeBefore or nextLoadout.variants[meleeNow] ~= variantBefore then
		rangeState.confirmedSteps[meleeNow] = nil
		replaySwings()
	end
end

-- P3.1 ruling 3: `handler` is called on the frame a melee swing is sent, with exactly what was
-- sent, so the hitbox effect can be drawn at once. FeedbackController registers here because
-- it requires this module and not the other way round. One handler; nil clears it.
function InputController.SetSwingHandler(handler: ((swing: PredictedSwing) -> ())?): ()
	rangeState.onSwing = handler
end

-- L2-29: `handler` is called on the frame a shot of a continuous family is sent, with what was
-- sent (FlameFx registers: it requires this module). One handler; nil clears it.
function InputController.SetStreamHandler(handler: StreamHandler?): ()
	rangeState.onStream = handler
end

-- P3.1 ruling 2: the server's strike for the local swing `seq` of `family`, with the combo
-- step it used. That step is the truth; the swings still unanswered are predicted again on
-- top of it, so a prediction that drifted is right again from the next swing.
function InputController.ConfirmSwing(family: string, seq: number, step: number): ()
	local pending = rangeState.pendingSwings
	-- A swing this client no longer remembers was still accepted about now.
	local acceptedAt = os.clock()
	-- The server answers in order: a swing older than this one, still unanswered, was dropped.
	while #pending > 0 and pending[1].seq <= seq do
		local answered = table.remove(pending, 1) :: PendingSwing
		if answered.seq == seq then
			acceptedAt = answered.sentAt
		end
	end
	rangeState.confirmedSteps[family] = step
	rangeState.confirmedAt = acceptedAt
	replaySwings()
end

-- P3.1 ruling 5: the server refused an attack. `seq` is the one RangeStats.refusedSeq names;
-- swings and shots share one counter, so it names one attack. Exactly the unanswered swing
-- with that seq is taken back, and a refused shot's seq matches none, so no swing is touched.
-- With nil (an older server names nothing) it is the oldest swing still unanswered, since the
-- server answers in order. A refused swing never moved the server's combo, so the prediction
-- steps back with it. Returns the seq of the swing taken back, so the hitbox effect drawn for
-- it can go; nil when none was.
function InputController.RefuseSwing(seq: number?): number?
	local pending = rangeState.pendingSwings
	local index: number? = nil
	if seq ~= nil then
		for at, swing in pending do
			if swing.seq == seq then
				index = at
				break
			end
		end
	else
		forgetStaleSwings(os.clock())
		index = if #pending > 0 then 1 else nil
	end
	if index == nil then
		return nil
	end
	local refused = table.remove(pending, index) :: PendingSwing
	replaySwings()
	return refused.seq
end

-- The slot 1 / 2 / gamepad Y last picked.
function InputController.GetActiveSlot(): Stance
	return rangeState.activeSlot
end

-- The bow's draw progress 0-1 for the crosshair's ring: 0 while nothing is drawn, nil only
-- without the range's combat. Display only: the server caps the real charge from its own draw
-- stamp.
function InputController.GetCharge(): number?
	if not rangePath then
		return nil
	end
	local variant = currentVariant(Tuning.Get())
	return if variant ~= nil then chargeOf(variant) else 0
end

-- Pushed from every RunState: the run phase, and (P5) whether the local member is waiting on
-- the pad for the next wave (nil = not).
function InputController.SetPhase(nextPhase: string, waiting: boolean?): ()
	rangeState.phase = nextPhase
	rangeState.waiting = waiting == true
end

function InputController.Destroy(): ()
	rangeState.rangeStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, action in RANGE_ACTIONS do
		ContextActionService:UnbindAction(action)
	end
	if rangePath then
		RunService:UnbindFromRenderStep(RANGE_BIND)
		CameraController.SetAds(false)
		MovementController.Destroy()
	end
	RangeTouchButtons.Destroy()
	AirSwing.Destroy()
	table.clear(rangeState.rangeTouches)
	table.clear(rangeState.pendingSwings)
	table.clear(rangeState.confirmedSteps)
	table.clear(rangeState.swingSteps)
	rangeState.confirmedAt = -math.huge
	rangeState.lastSwingAt = -math.huge
	table.clear(castState.pendingCasts)
	castState.serverAbility = nil
	castState.magDump = nil
	rangeState.drawStartedAt = nil
	rangeState.drawFamily = ""
	rangeState.rangeHeld = false
	rangeState.adsHeld = false
	rangeState.adsToggled = false
	rangeState.adsActive = false
	for _, connection in rangeState.characterConnections do
		connection:Disconnect()
	end
	table.clear(rangeState.characterConnections)
	rangeState.worldParams = nil
	rangeState.worldStale = true
end

return InputController
