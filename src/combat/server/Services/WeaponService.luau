--!strict
-- The player's weapons in either place mode (docs/INTERFACES.md "P5 contracts" → "Wave 1",
-- ruling 6): the per-player loadout, attack resolution against the crowd, bow draws,
-- projectiles, dash i-frames, the ground slam, aim checks, the AbilityService hooks and the
-- attack readouts. Moved here from RangeService (P1–P4) unchanged except for three P5 rulings
-- and two things their review asked for:
--   7  a claimed origin's slack reads the server root's own displacement, not its velocity;
--   8  every hit scales by the Armory tier at the one strike() choke point; heavy, plate and
--      armour are judged on the unscaled tier-1 amount (ruling 9). The scale is 1 in the range.
--      Since L3 (docs/prompts/l3-w1-contract.md, L3-6) the tier is the striking family's own and
--      the bar reads the held pair's; a mission takes up the saved loadout at admit (L3-10);
--   21 in missions an intent is refused unless the act gate (WaveService) lets the player act;
--   -  a pattern seed (pellets, fans, scatters) is a fresh server draw per shot or cast, no
--      longer derived from the client's seq;
--   -  a fresh character starts with its air state and position history cleared (resetAir).
-- RangeService keeps the bench (dummy sets, respawns, tuning, commands) and adds the range-only
-- readout fields through the stats provider.
--
-- P2: weapons are families; each player holds one melee and one ranged family (RangeLoadout).
-- Bows draw (RequestRangeDraw starts the server's clock) and fire real server-stepped arrows with
-- gravity; split arrows fan after splitDistance. Every projectile is announced at fire time
-- (CombatFxShot); its damage arrives as CombatFxStrike.
-- P3: SMG, Beam and Chain Gun ride the hitscan ray path; a Chain Gun hit starts chain lightning.
-- AbilityService drives abilities through the hook API at the bottom; this file never requires
-- it, so the dependency runs one way only.
-- P4: the player's body (health, regen, going down, the commit rule) is VitalsService, which
-- this file starts and hands its i-frame clock to. No attack, draw, dash or slam while down.
--
-- The server resolves every shape itself. Melee builds its shape at the position its client
-- claims, pulled back to what lag explains (P3.1); ranged takes the camera ray only after
-- checking it starts near the head. Every number is read through Tuning.Get() at the moment it
-- is used. Nothing in the Heartbeat step yields.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local GroundRule = require(sharedFolder:WaitForChild("GroundRule"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local SwingGate = require(sharedFolder:WaitForChild("SwingGate"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))
-- L3 W2: the attributes that show a player's weapons to every client (pure; requires only Types).
local WeaponLook = require(sharedFolder:WaitForChild("WeaponLook"))
local WorldReact = require(sharedFolder:WaitForChild("WorldReact"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local CrowdService = require(script.Parent:WaitForChild("CrowdService"))
local PositionRing = require(script.Parent:WaitForChild("PositionRing"))
local StrikePick = require(script.Parent:WaitForChild("StrikePick"))
local StrikeTally = require(script.Parent:WaitForChild("StrikeTally"))
local VitalsService = require(script.Parent:WaitForChild("VitalsService"))

type SlotName = "melee" | "ranged"
type Variant = Types.RangeWeaponVariant
type SlotTiers = Types.SlotTiers

-- Grouped in one table so the module stays far below Studio's 200-locals limit as it grows.
local CONST = {
	-- Contract: DPS is a 5 s window; readouts go out at 2 Hz. (Projectile lifetime is
	-- shooting.projectileMaxSeconds.)
	DPS_WINDOW_SECONDS = 5,
	STATS_INTERVAL_SECONDS = 0.5,
	-- Used when Combat.json is absent: the share of an interval a client may arrive early by
	-- (network jitter), same meaning as Combat.json player.comboTimingTolerance.
	DEFAULT_TIMING_TOLERANCE = 0.8,
	-- Pattern seeds (pellets, split fans, bomblet scatters) are fresh server draws in
	-- [1, ABILITY_SEED_BIT - 2]; an ability's seed adds this bit, so it lands in the upper half
	-- of HitShapes' Park–Miller range [1, 2^31 - 2] and never equals an attack's seed (a Volley
	-- or Cluster Shell never shares a userId:seed flight key with an arrow in flight).
	ABILITY_SEED_BIT = 0x40000000,
	-- Live projectiles (arrows, split children, shells) across every player; a shot past this is
	-- refused rather than let the step grow without bound.
	MAX_PROJECTILES = 256,
	-- Height above standing height before a character counts as airborne (steps and slopes).
	-- L1b-W2-13: SwingGate's, so the client's air-swing gate and this one share one number.
	AIRBORNE_MARGIN_STUDS = SwingGate.AIR_MARGIN_STUDS,
	-- Server-set character attribute while an i-frame window is open (a dash, an ability's leap,
	-- P4: after a knockback and on getting up), so the flag is visible in Studio's Properties
	-- panel and to the client.
	IFRAMES_ATTRIBUTE = "RangeIframes",
	-- Ruling 7: root positions kept per player, one per Heartbeat (2 s at 60 Hz). A slack window
	-- tuned longer than this reads the oldest sample, which only makes the slack smaller.
	HISTORY_CAPACITY = 120,
	-- GearOf's answer in the range, and without Armory.json: tier 1 (L3-1: in a mission that is
	-- the ladder's first step, the 2/2 every level was tuned at; the range scales by 1).
	RANGE_GEAR = table.freeze({ melee = 1, ranged = 1 }),
	NO_ASCENSION = table.freeze({ melee = 0, ranged = 0 }),
}
local DOWN = Vector3.new(0, -1, 0)

-- One shot's shared record: every arrow of a split volley draws on the same cap, never hits an
-- enemy another arrow of the volley already hit, and adds to the same readout totals.
type Volley = { hit: { [number]: boolean }, distinct: number, cap: number, kills: number }
-- An ability's strikes carry its id and add to the readout of cast `cast` instead of the normal
-- attack readout (lastHits / lastKills).
type AbilityTag = { id: string, cast: number }
type Projectile = {
	player: Player,
	weapon: string,
	variantKey: string,
	-- Frozen at the trigger pull: a slider moved mid-flight applies to the next shot.
	variant: Variant,
	shotOrigin: Vector3,
	-- This flight's start (a child's split point) and its velocity there. Positions follow the
	-- exact parabola origin + velocity t + gravity t^2 / 2, which every client can reproduce.
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	position: Vector3,
	-- Seconds since this flight began, and since the shot.
	age: number,
	lifetime: number,
	-- Path length since the shot (range and splitDistance are measured on it).
	travelled: number,
	-- Per hit, charge already applied (tier-1 units).
	damage: number,
	-- Ruling 8: the Armory scale of the shot, frozen at the trigger pull like its variant.
	tierScale: number,
	fullCharge: boolean,
	-- pierce = TOTAL enemies one projectile can hit (review ruling): what this one may still hit.
	hitsLeft: number,
	-- The charge its shot fired at (announced again when a split parent fans).
	charge: number,
	-- A newborn split child's share of the frame its parent split in, flown at once.
	carry: number,
	-- A split parent that has not split yet.
	splitting: boolean,
	volley: Volley,
	-- The pellet/fan seed every strike of this shot carries.
	seed: number,
	-- Set when an ability fired it (FireProjectile): its tag, and the hook that runs where it
	-- detonates or its flight ends.
	ability: AbilityTag?,
	onImpact: ((point: Vector3) -> ())?,
}
type DamageEntry = { at: number, amount: number }
-- SetAttackBuff: until `untilClock`, the slot fires at rate x rateMult and its hitscan rays hit
-- `pierce` enemies.
type AttackBuff = { rateMult: number, pierce: number, untilClock: number }
type Shooter = {
	player: Player,
	loadout: Types.RangeLoadout,
	-- Keyed by slot: switching family never resets the rate credit or the replay guard.
	-- lastAttackAt drives the melee combo reset and the bow's draw clock; the rate check reads
	-- only the credit (shots left after the last attack, nil = full) and when it was taken.
	lastSeq: { [string]: number },
	lastAttackAt: { [string]: number },
	credit: { [string]: number },
	creditAt: { [string]: number },
	-- Keyed by family.
	combo: { [string]: number },
	-- The bow draw clock (RequestRangeDraw); 0 = not drawing.
	drawStartedAt: number,
	drawWeapon: string,
	lastDashAt: number,
	-- The latest i-frame window, [iframesFrom, iframesUntil) on os.clock(). Kept after it
	-- lapses: an enemy's hit is judged a moment after its impact (VitalsService), and the dash
	-- that covered the impact may be over by then. The window before it is kept too
	-- (iframesWas*): a new one may have opened by the time the impact is noticed.
	-- iframesShown = the character attribute is set.
	iframesFrom: number,
	iframesUntil: number,
	iframesWasFrom: number,
	iframesWasUntil: number,
	iframesShown: boolean,
	lastSlamAt: number,
	airborne: boolean,
	peakY: number,
	-- The peak of the airborne phase that ended at landedAt (for a slam request that trails it).
	lastPeakY: number,
	landedAt: number,
	-- L1b-W2-13: one melee swing per jump; set by an airborne swing, cleared by a grounded one
	-- or the landing (a double jump is not one).
	airSwing: SwingGate.State,
	-- Fastest fall the server saw in this airtime (studs/s, downward positive), and in the one
	-- that ended at landedAt.
	diveSpeed: number,
	lastDiveSpeed: number,
	-- Root Y last frame, for the fall speed measured from positions.
	lastY: number?,
	-- The L2 W3 fix round's s-M1: the root where the server last saw this body grounded (its
	-- footprint's floor within the standing band, SwingGate.IsAir); nil after a server move or
	-- for a fresh body. The rescue lands a fall by it (LastGround).
	stood: Vector3?,
	-- The L2 W3 third fix round's fd-m2: how fast this body fell on the last sample (studs/s,
	-- downward positive, at least 0) when that sample found it off its footprint's floor; nil
	-- while it stood, after a server move and for a fresh body. LevelService leads its feet by
	-- it before an ice cell is judged (FallSpeed).
	fall: number?,
	-- Server-only: draws every pattern seed, so a client can neither pick nor predict one.
	seedRandom: Random,
	damageLog: { DamageEntry },
	lastHits: number,
	lastKills: number,
	-- Keyed by slot. Set only by AbilityService (Mag Dump).
	buffs: { [string]: AttackBuff },
	-- SetAbilityLock: normal attacks are refused until lockUntil, except on slot lockAllow.
	lockUntil: number,
	lockAllow: SlotName?,
	-- The ability readout: the latest cast id (0 = none yet) and its running totals.
	abilityId: string?,
	abilityCast: number,
	abilityHits: number,
	abilityKills: number,
	-- Ruling 7: a ring of the server root's positions on os.clock(), one per Heartbeat.
	history: PositionRing.History,
	-- L3-50: the slot in use as others see it, from this player's last accepted attack, draw or
	-- cast (a pure switch tells the server nothing). Shown through the character attributes
	-- (showWeapons) only: no hit ever reads it.
	held: SlotName,
}
-- One enemy the shape touched. `order` sorts nearest-first (distance, or entry along a ray).
type Candidate = { id: number, order: number, body: Vector3, crit: boolean }
-- What one CombatFxStrike draws. tick = a repeat of a lasting effect (held beam, ability tick);
-- links = chain lightning pairs.
type StrikeFx = {
	shape: Types.HitShape,
	origin: Vector3,
	direction: Vector3,
	size: number,
	arcDegrees: number?,
	width: number?,
	endPoint: Vector3?,
	-- A swing's own attack seq (its client pairs the strike with the effect it already drew), or
	-- a shot's server-drawn pattern seed (newSeed), which seeds HitShapes.Pellets and Fan.
	seq: number?,
	-- Weapon swings only: the combo step used.
	step: number?,
	tick: boolean?,
	links: { number }?,
	-- L2-35: the empty end strike of a projectile a set or a run abandoned. Never sent; the
	-- strike listeners skip it (it resolved nothing in the world).
	abandoned: boolean?,
	-- The L2 W3 second fix round's Q5: a melee swing judged airborne at its origin (SwingGate,
	-- OnAttack). Never sent; the strike listeners read it (WorldReact.Chills freezes nothing then).
	airborne: boolean?,
}
-- L2-35: what OnStrikeResolved's listeners are handed: the shape as WorldReact reads it.
type StrikeListener = (
	player: Player,
	weapon: string,
	fx: WorldReact.Strike,
	ability: string?
) -> ()
-- Chain lightning: jumps per hit enemy, the jump radius (body centre to body centre) and the
-- damage multiplier each jump applies to the one before.
type ChainSpec = { count: number, radius: number, falloff: number }

-- Module state, one table (see CONST).
local state = {
	-- Configure's decision. `active` = the weapons run at all (Config/ProvingGrounds present).
	mode = "mission" :: Types.CombatMode,
	active = false,
	started = false,
	shooters = {} :: { [Player]: Shooter },
	projectiles = {} :: { Projectile },
	-- An ability's onImpact hook may fire a new projectile while stepProjectiles walks the list;
	-- it waits in `pending` and joins the list when the step ends.
	stepping = false,
	pending = {} :: { Projectile },
	loadoutListeners = {} :: { (player: Player, slot: SlotName) -> () },
	dealtListeners = {} :: { (player: Player, dealt: number) -> () },
	-- L2-35: told of every resolved strike (LevelService.React, wired by Main); a listener that
	-- throws is warned once and the strike goes on.
	strikeListeners = {} :: { StrikeListener },
	warnedStrikeListener = false,
	-- Fix round d-m3: the players a wall refusal of a shot origin has been warned for (Studio).
	warnedAimWall = {} :: { [Player]: boolean },
	statsAccumulator = 0,
	-- Ruling 21 (nil = every player may act) and the range's readout fields.
	actGate = nil :: ((player: Player) -> boolean)?,
	statsProvider = nil :: ((player: Player, stats: Types.RangeStats) -> ())?,
	-- Run at the 2 Hz readout tick, before the readouts go out.
	readoutListeners = {} :: { () -> () },
	-- worldParams' cache: rebuilt only after a character came or went (Start's connections).
	worldParams = nil :: RaycastParams?,
	worldStale = true,
	characterConnections = {} :: { [Player]: { RBXScriptConnection } },
	-- L1 ruling 34: a Studio-only gear for the session, read before everything but the range's
	-- tier 1. Never written to a profile; always empty outside Studio.
	gearOverride = {} :: { [Player]: { gear: SlotTiers, ascension: SlotTiers } },
}

local WeaponService = {}

local function timingTolerance(): number
	local combatConfig = Catalog.GetCombatConfig()
	return if combatConfig ~= nil
		then combatConfig.player.comboTimingTolerance
		else CONST.DEFAULT_TIMING_TOLERANCE
end

local function familyDef(config: Types.ProvingGroundsConfig, family: string): Types.RangeWeaponDef?
	return config.weapons[family]
end

-- The variant a player holds for a family: their pick while the family still has it, else the
-- family's default, else any variant, so a tuned default can never strand a player.
local function variantFor(
	config: Types.ProvingGroundsConfig,
	shooter: Shooter,
	family: string
): (string, Variant?)
	local def = familyDef(config, family)
	if def == nil then
		return "", nil
	end
	local chosen = shooter.loadout.variants[family]
	if chosen ~= nil and def.variants[chosen] ~= nil then
		return chosen, def.variants[chosen]
	end
	if def.variants[def.default] ~= nil then
		return def.default, def.variants[def.default]
	end
	local key, variant = next(def.variants)
	if key == nil then
		return "", nil
	end
	return key, variant
end

local function slotFamily(shooter: Shooter, slot: SlotName): string
	return if slot == "melee" then shooter.loadout.melee else shooter.loadout.ranged
end

local function slotLocked(shooter: Shooter, slot: SlotName, now: number): boolean
	return now < shooter.lockUntil and shooter.lockAllow ~= slot
end

-- Attack pacing is a per-slot credit in shots: it earns `rate` per second and every attack
-- spends one. The slot's credit at `now` is what its last attack left plus what `rate` has
-- earned since, capped at one shot plus shooting.rateBurstShots however long it idled, so a pair
-- of shots network jitter bunched into adjacent frames still passes while the long-run rate
-- never exceeds `rate`. Earning at the CURRENT rate lets a Mag Dump start or end mid-stream
-- without a stale interval refusing the next shot.
local function shotCredit(
	shooter: Shooter,
	slot: SlotName,
	rate: number,
	now: number,
	shooting: Types.RangeShootingConfig
): number
	local cap = 1 + math.max(shooting.rateBurstShots, 0)
	local held = shooter.credit[slot]
	if held == nil then
		return cap
	end
	return math.min(cap, held + (now - (shooter.creditAt[slot] or now)) * rate)
end

-- The slot's attack buff while it lasts; an expired one is dropped here.
local function activeBuff(shooter: Shooter, slot: SlotName, now: number): AttackBuff?
	local buff = shooter.buffs[slot]
	if buff == nil then
		return nil
	end
	if now >= buff.untilClock then
		shooter.buffs[slot] = nil
		return nil
	end
	return buff
end

-- config.loadout's family for a slot, or the first family (by id) that fills it if the named one
-- is missing or sits in the other slot.
local function startingFamily(config: Types.ProvingGroundsConfig, slot: SlotName): string
	local named = if slot == "melee" then config.loadout.melee else config.loadout.ranged
	local def = familyDef(config, named)
	if def ~= nil and def.slot == slot then
		return named
	end
	local ids: { string } = {}
	for family, other in config.weapons do
		if other.slot == slot then
			table.insert(ids, family)
		end
	end
	table.sort(ids)
	return ids[1] or ""
end

-- TuneState's loadout: both slots plus the variant held for EVERY family, so the panel never
-- guesses a default.
local function loadoutPayload(
	config: Types.ProvingGroundsConfig,
	shooter: Shooter
): Types.RangeLoadout
	local variants: { [string]: string } = {}
	for family in config.weapons do
		local key = variantFor(config, shooter, family)
		variants[family] = key
	end
	return { melee = shooter.loadout.melee, ranged = shooter.loadout.ranged, variants = variants }
end

local function rootOf(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	if character == nil or character.Parent == nil then
		return nil, nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, root, humanoid
end

local function flatten(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-4 then
		return nil
	end
	return flat.Unit
end

-- Crowd dummies have no Instances, so world queries only need to skip the players. One shared
-- RaycastParams, rebuilt only after a character came or went: air tracking asks for it every
-- Heartbeat, in every mission server. Callers never change it. Before Start has connected the
-- character signals nothing marks it stale, so it is built fresh each time.
local function worldParams(): RaycastParams
	local cached = state.worldParams
	if cached ~= nil and state.started and not state.worldStale then
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
	state.worldParams = params
	state.worldStale = false
	return params
end

-- How far a ray travels before world geometry stops it.
local function worldReach(
	origin: Vector3,
	direction: Vector3,
	range: number,
	params: RaycastParams
): number
	local result = workspace:Raycast(origin, direction * range, params)
	if result == nil then
		return range
	end
	return (result.Position - origin).Magnitude
end

-- Root height above the floor when standing: R15's HipHeight is measured to the root's bottom.
local function standingOffset(root: BasePart, humanoid: Humanoid): number
	return humanoid.HipHeight + root.Size.Y / 2
end

local function floorBelow(root: BasePart, params: RaycastParams): number?
	local result = workspace:Raycast(root.Position, DOWN * HitShapes.GROUND_PROBE_DEPTH, params)
	return if result ~= nil then result.Position.Y else nil
end

-- Ruling 4 step 4: the floor under a point, probed from a little above it so a point resting on
-- the floor (or just inside it) still finds that floor.
local function floorUnder(position: Vector3, params: RaycastParams): number?
	local result = workspace:Raycast(
		position + Vector3.new(0, HitShapes.GROUND_PROBE_LIFT, 0),
		DOWN * HitShapes.GROUND_PROBE_DEPTH,
		params
	)
	return if result ~= nil then result.Position.Y else nil
end

-- Fix round A-1: the air-swing gate's floor is the highest one under the root's whole footprint
-- (SwingGate.ProbePoint), probed like floorUnder, so a lip or a cover block under any corner
-- reads grounded. AirSwing on the client casts the same five rays.
local function footprintFloor(position: Vector3, root: BasePart, params: RaycastParams): number?
	local right = root.CFrame.RightVector
	local halfX, halfZ = root.Size.X / 2, root.Size.Z / 2
	local lift = position.Y + HitShapes.GROUND_PROBE_LIFT
	local depth = DOWN * HitShapes.GROUND_PROBE_DEPTH
	local floorY: number? = nil
	for index = 1, SwingGate.PROBE_POINTS do
		local x, z =
			SwingGate.ProbePoint(index, position.X, position.Z, right.X, right.Z, halfX, halfZ)
		local result = workspace:Raycast(Vector3.new(x, lift, z), depth, params)
		floorY = SwingGate.Higher(floorY, if result ~= nil then result.Position.Y else nil)
	end
	return floorY
end

-- How far a position a client claims may sit from the server's copy of its character: a moving
-- character leads the server's view of it by the ping plus a margin. The speed is the server's
-- own measure (ruling 7: the fastest stretch of shooting.originSpeedSeconds inside the last
-- originLagMaxSeconds of its position ring) and the ping the client's word, so neither buys more
-- slack than the fastest legal move over the longest lag the range excuses. Also returns that
-- speed, that lag and the way that stretch went (PositionRing.Motion): the aim rule carries the
-- head by them (WorldReact.LeadHead, second fix round m2, third fix round m1), so its lead stays
-- inside this slack and goes only where the server saw the body go.
local function claimSlack(
	shooter: Shooter,
	root: BasePart,
	pad: number,
	config: Types.ProvingGroundsConfig
): (number, number, number, Vector3)
	local shooting = config.shooting
	local fastest = Tuning.FastestMove(config)
	local window = math.max(shooting.originLagMaxSeconds, 0)
	local speed, motion = PositionRing.Motion(
		shooter.history,
		os.clock(),
		root.Position,
		window,
		shooting.originSpeedSeconds
	)
	-- A NaN speed fails every comparison, math.min included.
	speed = if speed == speed then math.min(speed, fastest) else 0
	local lag = Tuning.CommitLag(shooting, shooter.player:GetNetworkPing())
	return math.max(pad, 0) + speed * lag, speed, lag, motion
end

-- WorldReact.AimClear's world: the first solid between two points, through the parts every world
-- query here uses (characters excluded, RespectCanCollide), as a distance from `from`.
local function worldHit(from: Vector3, to: Vector3): number?
	local result = workspace:Raycast(from, to - from, worldParams())
	return if result ~= nil then result.Distance else nil
end

-- Fortnite aim: the ray starts at the camera, which must sit near this character's head, on the
-- head's side of every wall. Distance alone let a modified client start a shot (or a ground
-- point's camera ray) beyond a 2-stud cave wall (fix round d-m3). A ray from the head to the
-- origin, and back, through the parts every world query here uses, measures the solid between
-- them; WorldReact.OriginClear allows shooting.originWallChord of it, the edge an honest
-- shoulder origin's line cuts at an inner corner (0.36 standing still, 0.97 with the server's
-- head 1 stud behind, 1.25 at 1.5; tests_l2w2 "originTests"). The second fix round's m2: when
-- that line is not clear, the line from the head carried by the lag the distance test excuses
-- along the way the position ring saw the body go (WorldReact.LeadHead, cut short of the first
-- wall by AimClear; the root's replicated velocity only shortens it, third fix round m1) may
-- be, so a dash round a bend is judged from about where the player's own screen had him; a
-- forged origin beyond a wall thicker than the chord is refused either way (check_levels "origin
-- chord" holds every tall piece, walled camps' fences included, over it). In Studio a wall
-- refusal warns once per player.
local function aimAllowed(
	shooter: Shooter,
	root: BasePart,
	origin: Vector3,
	config: Types.ProvingGroundsConfig
): boolean
	local character = shooter.player.Character
	local head = if character ~= nil then character:FindFirstChild("Head") else nil
	local anchor = if head ~= nil and head:IsA("BasePart") then head.Position else root.Position
	local offset = origin - anchor
	local distance = offset.Magnitude
	local slack, speed, lag, motion = claimSlack(shooter, root, config.shooting.originPad, config)
	if distance > slack then
		return false
	end
	local lead = WorldReact.LeadHead(anchor, motion, root.AssemblyLinearVelocity, speed, lag)
	local clear =
		WorldReact.AimClear(anchor, lead, origin, config.shooting.originWallChord, worldHit)
	if not clear and RunService:IsStudio() and not state.warnedAimWall[shooter.player] then
		state.warnedAimWall[shooter.player] = true
		local forward = workspace:Raycast(anchor, offset, worldParams())
		local through = if forward ~= nil then forward.Instance:GetFullName() else "?"
		warn(
			`[WeaponService] {shooter.player.Name}: a shot origin {string.format("%.2f", distance)}`
				.. ` studs from the head lies behind {through} (more than {config.shooting.originWallChord}`
				.. " studs of wall between); refused (fix round d-m3, warned once per player)"
		)
	end
	return clear
end

-- P3.1: a swing lands where the swinger's own screen had them. Swept from the server's copy,
-- the arc sat behind a player running into the crowd. A claim further out than lag explains is
-- pulled back onto that limit, not refused: its only fault is lag, and a refusal would take
-- the swing back.
local function meleeOrigin(
	shooter: Shooter,
	root: BasePart,
	claimed: Vector3,
	config: Types.ProvingGroundsConfig
): Vector3
	local position = root.Position
	local allowed = claimSlack(shooter, root, config.controls.meleeOriginPad, config)
	local offset = claimed - position
	local distance = offset.Magnitude
	if distance <= allowed then
		return claimed
	end
	return position + offset * (allowed / distance)
end

-- Ruling 21: in missions only players the gate admits act (admitted, fighting, not down).
local function mayAct(player: Player): boolean
	local gate = state.actGate
	return gate == nil or gate(player)
end

-- Ruling 12, L3-6: the tiers the bar is read at, one per slot: each held family's
-- Armory.StrikeTier, the call damageScale makes, so the bar and the hits always name one tier
-- (R3). The held families are the shooter's loadout; before admission, the saved one as AddPlayer
-- will read it (L3-10). The Studio session override's tier is held inside each family's window
-- (2-s1: G's T1 fields the Flamethrower at its T2, as the Armory screen shows it), and its
-- Ascension comes before the profile's. A proving build reads the profile like any other (L3-11:
-- a baked gear would hide every tier Ben buys there). Tier 1 and no Ascension in the range and
-- without Armory.json; without a loaded profile the starters, at tier 1. Fresh tables, so no
-- caller can write the profile through them.
local function gearOf(player: Player): (SlotTiers, SlotTiers)
	local armoryConfig = Catalog.GetArmoryConfig()
	if state.mode == "range" or armoryConfig == nil then
		return table.clone(CONST.RANGE_GEAR), table.clone(CONST.NO_ASCENSION)
	end
	local profile = DataService.GetState(player)
	local combat = if profile ~= nil then profile.combat else nil
	local shooter = state.shooters[player]
	local config = Tuning.Get()
	local held = if shooter ~= nil
		then shooter.loadout
		else Unlocks.LoadoutOf(combat, config.weapons, {
			melee = startingFamily(config, "melee"),
			ranged = startingFamily(config, "ranged"),
		})
	local override = state.gearOverride[player]
	local gear = if override ~= nil then override.gear else nil
	local meleeOverride = if gear ~= nil then gear.melee else nil
	local rangedOverride = if gear ~= nil then gear.ranged else nil
	local ascension = if override ~= nil
		then override.ascension
		elseif combat ~= nil then combat.ascension
		else CONST.NO_ASCENSION
	return {
		melee = Armory.StrikeTier(armoryConfig, combat, held.melee, meleeOverride),
		ranged = Armory.StrikeTier(armoryConfig, combat, held.ranged, rangedOverride),
	}, { melee = ascension.melee, ranged = ascension.ranged }
end

-- Ruling 8, L3-6: one number per resolved attack, at the STRIKING family's tier and that slot's
-- Ascension. The tier is Armory.StrikeTier (R3): the Studio override's tier for the slot the family
-- fills, held inside the family's window (2-s1), else Armory.TierOf. An unknown family has no
-- slot, so no override tier and no Ascension. Always 1 in the range, whose numbers are the tier-1
-- ones; without a loaded profile a family's start (tier 1 for a starter).
local function damageScale(player: Player, family: string, ability: boolean): number
	if state.mode == "range" then
		return 1
	end
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		return 1
	end
	local def = familyDef(Tuning.Get(), family)
	local slot = if def ~= nil then def.slot else ""
	local profile = DataService.GetState(player)
	local combat = if profile ~= nil then profile.combat else nil
	local override = state.gearOverride[player]
	local overrideTier: number? = nil
	if override ~= nil then
		local gear = override.gear
		overrideTier = if slot == "melee"
			then gear.melee
			elseif slot == "ranged" then gear.ranged
			else nil
	end
	local ascension = if override ~= nil
		then override.ascension
		elseif combat ~= nil then combat.ascension
		else CONST.NO_ASCENSION
	local level = if slot == "melee"
		then ascension.melee
		elseif slot == "ranged" then ascension.ranged
		else 0
	local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)
	return Armory.DamageScale(armoryConfig, tier, level, ability)
end

local function sendTo(player: Player, remoteName: string, ...: any): ()
	-- TuneState carries two arguments, which RemoteService.FireClient (one payload) cannot.
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = if folder ~= nil then folder:FindFirstChild(remoteName) else nil
	if remote == nil or not remote:IsA("RemoteEvent") or player.Parent == nil then
		return
	end
	remote:FireClient(player, ...)
end

-- Overrides exist only on the bench: a mission always says none.
local function tuneStateFor(shooter: Shooter): ()
	sendTo(
		shooter.player,
		"TuneState",
		if state.mode == "range" then Tuning.GetOverrides() else {},
		loadoutPayload(Tuning.Get(), shooter)
	)
end

-- `refusedSeq`: the attack this answer refuses; nil on an ordinary readout. The attack fields
-- are assembled here; the stats provider (RangeService) adds the bench's fields.
local function statsFor(shooter: Shooter, now: number, refusedSeq: number?): Types.RangeStats
	local log = shooter.damageLog
	local cutoff = now - CONST.DPS_WINDOW_SECONDS
	local firstLive = 1
	while firstLive <= #log and log[firstLive].at < cutoff do
		firstLive += 1
	end
	if firstLive > 1 then
		table.move(log, firstLive, #log, 1)
		for index = #log - firstLive + 2, #log do
			log[index] = nil
		end
	end
	local total = 0
	for _, entry in log do
		total += entry.amount
	end
	local hasAbility = shooter.abilityId ~= nil
	local stats: Types.RangeStats = {
		lastHits = shooter.lastHits,
		lastKills = shooter.lastKills,
		dps = total / CONST.DPS_WINDOW_SECONDS,
		alive = 0,
		serverFrameMs = 0,
		refused = if refusedSeq ~= nil then true else nil,
		refusedSeq = refusedSeq,
		ability = shooter.abilityId,
		abilityHits = if hasAbility then shooter.abilityHits else nil,
		abilityKills = if hasAbility then shooter.abilityKills else nil,
	}
	local provider = state.statsProvider
	if provider ~= nil then
		provider(shooter.player, stats)
	end
	return stats
end

local function sendStats(shooter: Shooter): ()
	RemoteService.FireClient(shooter.player, "RangeStats", statsFor(shooter, os.clock(), nil))
end

-- The attacker's client has already drawn the attack; this tells it to take that one back. It
-- is named by its seq because a swing sent after it may also be waiting for its answer.
local function sendRefused(shooter: Shooter, seq: number): ()
	RemoteService.FireClient(shooter.player, "RangeStats", statsFor(shooter, os.clock(), seq))
end

-- A pattern seed: pellets, a split arrow's fan, an ability's scatter. Strikes, shots and casts
-- carry it as `seq` so every client draws the server's pattern with HitShapes. It is a fresh
-- draw per shot or cast, never derived from the client's seq: a seed derived from it could be
-- inverted from two broadcasts and future seqs chosen for tight fans (P5 review, minor 3).
local function newSeed(shooter: Shooter, ability: boolean): number
	local drawn = shooter.seedRandom:NextInteger(1, CONST.ABILITY_SEED_BIT - 2)
	return if ability then drawn + CONST.ABILITY_SEED_BIT else drawn
end

-- Cast ids only grow, so a lingering tick of an older cast (a zone still running when the next
-- cast lands) never drags the readout back to it.
local function addAbilityReadout(shooter: Shooter, tag: AbilityTag, hits: number, kills: number): ()
	if tag.cast < shooter.abilityCast then
		return
	end
	if tag.cast > shooter.abilityCast or shooter.abilityId == nil then
		shooter.abilityCast = tag.cast
		shooter.abilityHits = 0
		shooter.abilityKills = 0
	end
	shooter.abilityId = tag.id
	shooter.abilityHits += hits
	shooter.abilityKills += kills
end

local function broadcastFx(fx: Types.CombatFx): ()
	local batch: { Types.CombatFx } = { fx }
	for _, player in Players:GetPlayers() do
		RemoteService.FireClient(player, "CombatFx", batch)
	end
end

local function kindDef(config: Types.ProvingGroundsConfig, kind: string): Types.CrowdKindDef?
	return config.crowd.kinds[kind]
end

-- Hits ---------------------------------------------------------------------------------------

-- Every live enemy the broad phase returns, with its body and head spheres, handed to `test`,
-- which returns the ordering distance (nil = miss) and whether it was a crit.
local function gather(
	config: Types.ProvingGroundsConfig,
	center: Vector3,
	radius: number,
	test: (
		body: Vector3,
		bodyRadius: number,
		head: Vector3,
		headRadius: number,
		feet: Vector3,
		height: number
	) -> (number?, boolean)
): { Candidate }
	local found: { Candidate } = {}
	for _, id in CrowdService.Query(center, radius) do
		local enemy = CrowdService.Get(id)
		if enemy == nil or enemy.state == "dead" or enemy.hp <= 0 then
			continue
		end
		local def = kindDef(config, enemy.kind)
		if def == nil then
			continue
		end
		local body = enemy.position + Vector3.new(0, def.height / 2, 0)
		local head = enemy.position + Vector3.new(0, def.height - def.headRadius, 0)
		local order, crit = test(body, def.radius, head, def.headRadius, enemy.position, def.height)
		if order ~= nil then
			table.insert(found, { id = id, order = order, body = body, crit = crit })
		end
	end
	table.sort(found, function(a: Candidate, b: Candidate): boolean
		return a.order < b.order
	end)
	return found
end

local function capOf(variant: Variant, count: number): number
	return if variant.cap > 0 then math.min(variant.cap, count) else count
end

type Tally = StrikeTally.Tally

-- The one choke point of every player hit, in either mode (ruling 6): weapon swings and shots,
-- projectiles, chain jumps, the slam and every ability strike. Every multiplier (chain, finisher,
-- crit) is already in `amount`, which stays in tier-1 units: CrowdService judges heavy hits,
-- plates and armour on it and multiplies only the HP loss by the tally's Armory scale (rulings
-- 8 and 9). StrikeTally builds the StrikeHit: blocked, on the plate, the one that broke it, or
-- plain. Returns whether it killed, and the verdict ("held" = the hit did nothing: StrikePick).
local function strike(
	tally: Tally,
	player: Player,
	id: number,
	amount: number,
	crit: boolean,
	push: Vector3?,
	launch: number
): (boolean, StrikeTally.Verdict?)
	local dealt: number, killed: boolean, verdict: StrikeTally.Verdict? =
		CrowdService.Damage(id, amount, player.UserId, push, launch, tally.scale)
	StrikeTally.Add(tally, id, dealt, crit, killed, verdict)
	return killed, verdict
end

local function finish(
	player: Player,
	weapon: string,
	variantKey: string,
	tally: Tally,
	fx: StrikeFx,
	-- A projectile's readout counts its whole volley, not just this strike.
	totals: { hits: number, kills: number }?,
	-- An ability strike: tagged, and summed into its cast's readout, never the attack readout.
	ability: AbilityTag?
): ()
	local now = os.clock()
	if tally.dealt > 0 then
		-- The range's clear clock starts on the first damage since its set loaded.
		for _, listener in state.dealtListeners do
			listener(player, tally.dealt)
		end
	end
	broadcastFx({
		kind = "strike",
		userId = player.UserId,
		weapon = weapon,
		variant = variantKey,
		shape = fx.shape,
		origin = fx.origin,
		direction = fx.direction,
		size = fx.size,
		arcDegrees = fx.arcDegrees,
		width = fx.width,
		endPoint = fx.endPoint,
		seq = fx.seq,
		step = fx.step,
		hits = tally.hits,
		ability = if ability ~= nil then ability.id else nil,
		tick = fx.tick,
		links = fx.links,
	})
	if not fx.abandoned then
		local abilityId = if ability ~= nil then ability.id else nil
		for _, listener in state.strikeListeners do
			local ok, problem = pcall(function(): any
				listener(player, weapon, fx, abilityId)
				return nil
			end)
			if not ok and not state.warnedStrikeListener then
				state.warnedStrikeListener = true
				warn(`[WeaponService] a strike listener failed: {problem}`)
			end
		end
	end
	local shooter = state.shooters[player]
	if shooter == nil then
		return
	end
	if ability ~= nil then
		addAbilityReadout(shooter, ability, tally.enemies, tally.kills)
	else
		shooter.lastHits = if totals ~= nil then totals.hits else tally.enemies
		shooter.lastKills = if totals ~= nil then totals.kills else tally.kills
	end
	if tally.dealt > 0 then
		table.insert(shooter.damageLog, { at = now, amount = tally.dealt })
	end
	sendStats(shooter)
end

-- Ends every live projectile with an empty end strike (endPoint = where it is now), so clients
-- stop their flights instead of letting arrows fly on through a cleared set.
local function abandonProjectiles(): ()
	for _, projectile in state.projectiles do
		if projectile.player.Parent == nil then
			continue
		end
		finish(
			projectile.player,
			projectile.weapon,
			projectile.variantKey,
			StrikeTally.New(projectile.tierScale),
			{
				shape = "ray",
				origin = projectile.position,
				direction = DOWN,
				size = 0,
				arcDegrees = nil,
				width = nil,
				endPoint = projectile.position,
				seq = projectile.seed,
				abandoned = true,
			},
			{ hits = projectile.volley.distinct, kills = projectile.volley.kills },
			projectile.ability
		)
	end
	state.projectiles = {}
end

local function outward(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	return flatten(to - from) or flatten(fallback) or Vector3.zero
end

-- Everything in a sphere, nearest the centre first (projectile splash, the slam, ranged spheres).
-- What a blast needs beyond its centre and radius. A weapon variant carries these fields; the
-- slam builds its own from movement.*.
type Blast = { pad: number, cap: number, knockback: number, launch: number }

local function sphereCandidates(
	config: Types.ProvingGroundsConfig,
	center: Vector3,
	radius: number,
	pad: number
): { Candidate }
	return gather(
		config,
		center,
		radius + pad,
		function(body: Vector3, r: number): (number?, boolean)
			if HitShapes.Sphere(center, radius, pad, body, r) then
				return (body - center).Magnitude, false
			end
			return nil, false
		end
	)
end

local function explode(
	config: Types.ProvingGroundsConfig,
	player: Player,
	center: Vector3,
	radius: number,
	variant: Blast,
	damage: number,
	heading: Vector3,
	tally: Tally
): ()
	local candidates = sphereCandidates(config, center, radius, variant.pad)
	local limit = if variant.cap > 0 then math.min(variant.cap, #candidates) else #candidates
	for index = 1, limit do
		local candidate = candidates[index]
		local push = outward(center, candidate.body, heading) * variant.knockback
		strike(tally, player, candidate.id, damage, false, push, variant.launch)
	end
end

-- An arc, capsule, cone or thick line from `origin`. Arcs sweep `arcDegrees` (nil = a full
-- circle) in a band reaching `reachDown` below the origin; cones open `arcDegrees` in all (nil =
-- none); a capsule runs origin → tip with radius width / 2.
type Area = {
	shape: Types.HitShape,
	origin: Vector3,
	heading: Vector3,
	range: number,
	tip: Vector3,
	arcDegrees: number?,
	width: number,
	pad: number,
	reachDown: number,
}

-- The enemies an area touches, nearest the origin first.
local function areaCandidates(config: Types.ProvingGroundsConfig, area: Area): { Candidate }
	local shape = area.shape
	local origin = area.origin
	local pad = area.pad
	local halfWidth = area.width / 2
	local test = function(body: Vector3, r: number): (number?, boolean)
		local touched = false
		if shape == "arc" then
			touched = HitShapes.Arc(
				origin,
				area.heading,
				area.range,
				area.arcDegrees or 360,
				pad,
				body,
				r,
				area.reachDown
			)
		elseif shape == "capsule" then
			touched = HitShapes.Capsule(origin, area.tip, halfWidth, pad, body, r)
		elseif shape == "cone" then
			touched = HitShapes.Cone(
				origin,
				area.heading,
				area.range,
				(area.arcDegrees or 0) / 2,
				pad,
				body,
				r
			)
		elseif shape == "ray" then
			touched = HitShapes.Ray(origin, area.heading, area.range, area.width, pad, body, r)
				~= nil
		end
		if touched then
			return (body - origin).Magnitude, false
		end
		return nil, false
	end
	local reach = math.max(area.range, (area.tip - origin).Magnitude)
	return gather(config, origin, reach + pad + halfWidth + area.reachDown, test)
end

-- Chain lightning (P3 ruling 8). Each seed enemy, in order, starts `count` jumps; each jump goes
-- to the nearest living enemy within `radius` of the last one (body centre to body centre) that
-- `hit` does not hold yet, for damage x falloff^jump, pushed along the jump. Jumps never crit and
-- sit outside any cap or pierce. Every seed and jump is added to `hit`, so the shared set also
-- keeps a later chain off an enemy an earlier one already struck. A held resident the jump struck
-- is passed over for the next nearest (StrikePick.Next): no link names it and no jump goes on
-- from it. It stays out of `hit`, the shared set a lasting ability keeps across its ticks, so the
-- ambush takes the next tick once the close has woken it. Returns the links: flat {from, to} id
-- pairs, 0 = the strike origin.
local function chainFrom(
	config: Types.ProvingGroundsConfig,
	player: Player,
	tally: Tally,
	seeds: { Candidate },
	hit: { [number]: boolean },
	chain: ChainSpec,
	damage: number,
	knockback: number,
	launch: number
): { number }
	local links: { number } = {}
	for _, seed in seeds do
		hit[seed.id] = true
	end
	local jumps = math.max(0, math.floor(chain.count))
	local radius = math.max(chain.radius, 0)
	local passed: { [number]: boolean } = {}
	local function taken(candidate: Candidate): boolean
		return hit[candidate.id] == true or passed[candidate.id] == true
	end
	for _, seed in seeds do
		table.insert(links, 0)
		table.insert(links, seed.id)
		local fromId = seed.id
		local fromBody = seed.body
		for jump = 1, jumps do
			local nearby = gather(
				config,
				fromBody,
				radius,
				function(body: Vector3): (number?, boolean)
					local distance = (body - fromBody).Magnitude
					return (if distance <= radius then distance else nil), false
				end
			)
			local from = fromBody
			local target = StrikePick.Next(nearby, taken, function(candidate: Candidate): boolean
				local push = outward(from, candidate.body, candidate.body - from) * knockback
				local _, verdict = strike(
					tally,
					player,
					candidate.id,
					damage * chain.falloff ^ jump,
					false,
					push,
					launch
				)
				if verdict == "held" then
					passed[candidate.id] = true
					return false
				end
				return true
			end)
			if target == nil then
				break
			end
			hit[target.id] = true
			table.insert(links, fromId)
			table.insert(links, target.id)
			fromId = target.id
			fromBody = target.body
		end
	end
	return links
end

local function resolveMelee(
	config: Types.ProvingGroundsConfig,
	shooter: Shooter,
	weapon: string,
	variantKey: string,
	variant: Variant,
	root: BasePart,
	seq: number,
	origin: Vector3,
	direction: Vector3,
	-- The L2 W3 second fix round's Q5: OnAttack's SwingGate verdict for this swing (at its origin).
	airSwing: boolean
): ()
	local heading = flatten(direction) or flatten(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local chain = variant.chain
	local step = shooter.combo[weapon] or 0
	step = if chain ~= nil and #chain > 0 then step % #chain + 1 else 1
	shooter.combo[weapon] = step
	local multiplier = if chain ~= nil and chain[step] ~= nil then chain[step] else 1
	-- The L2 W3 fix round's c-m3: the swing's geometry is WorldReact.SwingStrike's, the one the
	-- client's frost ghost and phone auto-swing build too. Lead ruling: the chain's LAST hit may
	-- sweep a different arc (finisherArcDegrees; 360 = a spin round the root). The second fix
	-- round's Q5: it carries whether the swing was made in the air, so the ice it would freeze
	-- under a falling body stays water.
	local swing = WorldReact.SwingStrike(variant, step, origin, heading, airSwing)
	local arcDegrees = swing.arcDegrees
	local damage = variant.damage * multiplier
	local range = swing.size
	local shape: Types.HitShape = swing.shape
	-- Lead ruling: an airborne swing's arc reaches down to the crowd below (HitShapes.Arc band).
	-- The tracked flag reads the server's copy, which is still on the ground for a frame or two
	-- after a take-off the claim already shows: a claim lifted above that copy is airborne too,
	-- or the lifted arc would pass over the crowd its client drew it through.
	local lifted = origin.Y - root.Position.Y > CONST.AIRBORNE_MARGIN_STUDS
	local reachDown = if shooter.airborne or lifted
		then math.max(config.movement.airSwingReachDown, 0)
		else 0
	local tally = StrikeTally.New(damageScale(shooter.player, weapon, false))

	if shape == "sphere" then
		explode(config, shooter.player, origin, range, variant, damage, heading, tally)
	else
		local candidates = areaCandidates(config, {
			shape = shape,
			origin = origin,
			heading = heading,
			range = range,
			tip = origin + heading * range,
			arcDegrees = arcDegrees,
			width = swing.width or 0,
			pad = variant.pad,
			reachDown = reachDown,
		})
		for index = 1, capOf(variant, #candidates) do
			local candidate = candidates[index]
			-- Lines push along the thrust; sweeps and blasts push away from the swinger.
			local pushDirection = if shape == "capsule" or shape == "ray"
				then heading
				else outward(origin, candidate.body, heading)
			strike(
				tally,
				shooter.player,
				candidate.id,
				damage,
				false,
				pushDirection * variant.knockback,
				variant.launch
			)
		end
	end
	finish(shooter.player, weapon, variantKey, tally, {
		shape = swing.shape,
		origin = swing.origin,
		direction = swing.direction,
		size = swing.size,
		arcDegrees = swing.arcDegrees,
		width = swing.width,
		-- An airborne arc carries the bottom of its band (origin - airSwingReachDown); nil on
		-- the ground, so a client knows which band to draw.
		endPoint = if shape == "arc" and reachDown > 0
			then origin - Vector3.new(0, reachDown, 0)
			else nil,
		seq = seq,
		step = step,
		airborne = swing.airborne,
	})
end

-- One ray against the crowd: the enemies it touches before `reach`, entry order. L1b-W2-15:
-- HitShapes.CrowdRay, the body capsule or the head sphere, both padded; crit when the unpadded
-- ray touches the head (the pad forgives a miss, it does not make a headshot).
local function rayCandidates(
	config: Types.ProvingGroundsConfig,
	origin: Vector3,
	direction: Vector3,
	reach: number,
	width: number,
	pad: number
): { Candidate }
	local center = origin + direction * (reach / 2)
	return gather(
		config,
		center,
		reach / 2 + pad + width / 2,
		function(
			_body: Vector3,
			r: number,
			_head: Vector3,
			headRadius: number,
			feet: Vector3,
			height: number
		): (number?, boolean)
			return HitShapes.CrowdRay(
				origin,
				direction,
				reach,
				width,
				pad,
				feet,
				r,
				height,
				headRadius
			)
		end
	)
end

-- Review ruling: pierce is the TOTAL number of enemies one projectile or ray may hit (0 or
-- missing = 1), for arrows and the rifle alike.
local function pierceOf(variant: Variant): number
	return math.max(1, math.floor(variant.pierce or 0))
end

-- How many projectiles one shot becomes: its split fan (floored, at most HitShapes.MAX_FAN), or 1.
local function volleySize(variant: Variant): number
	if variant.shape ~= "ray" then
		return 1
	end
	return math.max(1, math.clamp(math.floor(variant.splitCount or 0), 0, HitShapes.MAX_FAN))
end

-- Ruling 4: the client's claimed charge is capped by the server's own draw clock (with the same
-- timing tolerance as every other interval here); damage runs from minChargeFraction to 1 of
-- `damage`. A draw only counts if it started after the previous shot of that slot. Returns
-- (charge used, damage scale, full charge). Weapons without chargeSeconds fire at 1.
local function resolveCharge(
	shooter: Shooter,
	weapon: string,
	variant: Variant,
	claimed: number,
	previousShotAt: number,
	now: number
): (number, number, boolean)
	local chargeSeconds = variant.chargeSeconds or 0
	if chargeSeconds <= 0 then
		return 1, 1, false
	end
	local drawAt = shooter.drawStartedAt
	local earned = if shooter.drawWeapon == weapon and drawAt > previousShotAt
		then (now - drawAt) / (chargeSeconds * timingTolerance())
		else 0
	shooter.drawStartedAt = 0
	local charge = math.clamp(math.min(claimed, earned), 0, 1)
	local minFraction = math.clamp(variant.minChargeFraction or 0, 0, 1)
	return charge, minFraction + (1 - minFraction) * charge, charge >= 1
end

-- Live projectiles, counting any an impact hook fired during the current step.
local function projectileCount(): number
	return #state.projectiles + #state.pending
end

-- A projectile weapon's trigger pull: one record (a split parent fans later) and ONE CombatFxShot
-- to everyone, which is all a client needs to fly it: origin, direction, speed, gravity, and the
-- seq that seeds the split fan. An ability's shot carries its tag and impact hook.
local function spawnShot(
	shooter: Shooter,
	weapon: string,
	variantKey: string,
	variant: Variant,
	origin: Vector3,
	direction: Vector3,
	seed: number,
	charge: number,
	-- The charge's share of `damage` (resolveCharge), and the Armory scale (ruling 8).
	chargeScale: number,
	tierScale: number,
	full: boolean,
	ability: AbilityTag?,
	onImpact: ((point: Vector3) -> ())?
): ()
	local frozen = table.clone(variant)
	local speed = frozen.projectileSpeed or 0
	local gravity = math.max(frozen.gravity or 0, 0)
	local splitCount = volleySize(frozen)
	table.insert(if state.stepping then state.pending else state.projectiles, {
		player = shooter.player,
		weapon = weapon,
		variantKey = variantKey,
		variant = frozen,
		shotOrigin = origin,
		origin = origin,
		velocity = direction * speed,
		gravity = gravity,
		position = origin,
		age = 0,
		lifetime = 0,
		travelled = 0,
		damage = frozen.damage * chargeScale,
		tierScale = tierScale,
		fullCharge = full,
		hitsLeft = pierceOf(frozen),
		charge = charge,
		carry = 0,
		splitting = splitCount > 1,
		volley = { hit = {}, distinct = 0, cap = frozen.cap, kills = 0 },
		seed = seed,
		ability = ability,
		onImpact = onImpact,
	})
	broadcastFx({
		kind = "shot",
		userId = shooter.player.UserId,
		weapon = weapon,
		variant = variantKey,
		origin = origin,
		direction = direction,
		speed = speed,
		gravity = gravity,
		charge = charge,
		seq = seed,
		ability = if ability ~= nil then ability.id else nil,
	})
end

local function resolveRanged(
	config: Types.ProvingGroundsConfig,
	shooter: Shooter,
	weapon: string,
	variantKey: string,
	variant: Variant,
	origin: Vector3,
	direction: Vector3,
	charge: number,
	scale: number,
	full: boolean,
	-- An active attack buff's pierce (Mag Dump): hitscan rays then hit this many enemies each.
	buffPierce: number?
): ()
	local unit = direction.Unit
	-- Pellets and fans are seeded (lead ruling): every client draws the same ones.
	local seed = newSeed(shooter, false)
	local tierScale = damageScale(shooter.player, weapon, false)
	if (variant.projectileSpeed or 0) > 0 then
		spawnShot(
			shooter,
			weapon,
			variantKey,
			variant,
			origin,
			unit,
			seed,
			charge,
			scale,
			tierScale,
			full
		)
		return
	end
	local critMult = config.shooting.critMult
	local params = worldParams()
	local player = shooter.player
	local tally = StrikeTally.New(tierScale)
	local pushBase = (flatten(unit) or Vector3.zero) * variant.knockback

	if variant.shape == "cone" then
		-- A true cone: every enemy whose body overlaps it takes `damage` once, nearest first up
		-- to the cap; a crit when the aim ray itself passes the head sphere.
		local halfAngle = (variant.arcDegrees or 0) / 2
		local range = variant.range
		local width = variant.width or 0
		local candidates = gather(
			config,
			origin,
			range + variant.pad,
			function(
				body: Vector3,
				r: number,
				head: Vector3,
				headRadius: number
			): (number?, boolean)
				if not HitShapes.Cone(origin, unit, range, halfAngle, variant.pad, body, r) then
					return nil, false
				end
				local crit = HitShapes.Ray(origin, unit, range, width, 0, head, headRadius) ~= nil
				return (body - origin).Magnitude, crit
			end
		)
		for index = 1, capOf(variant, #candidates) do
			local candidate = candidates[index]
			local amount = if candidate.crit then variant.damage * critMult else variant.damage
			local push = outward(origin, candidate.body, unit) * variant.knockback
			strike(tally, player, candidate.id, amount, candidate.crit, push, variant.launch)
		end
		finish(player, weapon, variantKey, tally, {
			shape = "cone",
			origin = origin,
			direction = unit,
			size = range,
			arcDegrees = variant.arcDegrees,
			width = variant.width,
			endPoint = nil,
			seq = seed,
		})
		return
	end

	local reach = worldReach(origin, unit, variant.range, params)
	if variant.shape == "ray" then
		local candidates =
			rayCandidates(config, origin, unit, reach, variant.width or 0, variant.pad)
		-- A buffed bullet hits its buff's pierce whatever the variant's cap: Mag Dump turns the
		-- one-enemy SMG into a piercing one.
		local limit = if buffPierce ~= nil
			then math.min(#candidates, math.max(1, math.floor(buffPierce)))
			else capOf(variant, math.min(#candidates, pierceOf(variant)))
		local endPoint = origin + unit * reach
		-- The L1c second fix round's F4: pierce counts, and the Chain Gun seeds from, only bodies
		-- the hit landed on; a held resident is passed over (StrikePick).
		local seeds, spent = StrikePick.Seeds(
			candidates,
			math.floor(limit),
			function(candidate: Candidate): boolean
				local amount = if candidate.crit then variant.damage * critMult else variant.damage
				local _, verdict = strike(
					tally,
					player,
					candidate.id,
					amount,
					candidate.crit,
					pushBase,
					variant.launch
				)
				return verdict ~= "held"
			end
		)
		if spent ~= nil and spent < #candidates then
			-- Pierce spent: the beam visibly stops in the last enemy it went through.
			endPoint = origin + unit * candidates[spent].order
		end
		-- Chain Gun: every enemy the ray hit starts a chain from the base damage.
		local links: { number }? = nil
		local chainCount = variant.chainCount or 0
		if chainCount > 0 then
			links = chainFrom(config, player, tally, seeds, {}, {
				count = chainCount,
				radius = variant.chainRadius or 0,
				falloff = variant.chainFalloff or 1,
			}, variant.damage, variant.knockback, variant.launch)
		end
		finish(player, weapon, variantKey, tally, {
			shape = "ray",
			origin = origin,
			direction = unit,
			size = variant.range,
			arcDegrees = nil,
			width = variant.width,
			endPoint = endPoint,
			seq = seed,
			-- Ruling 6: a held beam's shots are ticks of one lasting beam.
			tick = if variant.continuous == true then true else nil,
			links = links,
		})
		return
	end

	if variant.shape == "sphere" then
		-- A hitscan blast lands where the aim ray stops.
		local impact = origin + unit * reach
		local radius = variant.splashRadius or 0
		explode(config, player, impact, radius, variant, variant.damage, unit, tally)
		finish(player, weapon, variantKey, tally, {
			shape = "sphere",
			origin = origin,
			direction = unit,
			size = radius,
			arcDegrees = nil,
			width = nil,
			endPoint = impact,
			seq = seed,
		})
		return
	end

	-- Arc or capsule fired from the camera ray: everything inside, nearest first.
	local shape: Types.HitShape = variant.shape
	local candidates = areaCandidates(config, {
		shape = shape,
		origin = origin,
		heading = unit,
		range = reach,
		tip = origin + unit * reach,
		arcDegrees = variant.arcDegrees,
		width = variant.width or 0,
		pad = variant.pad,
		reachDown = 0,
	})
	for index = 1, capOf(variant, #candidates) do
		strike(tally, player, candidates[index].id, variant.damage, false, pushBase, variant.launch)
	end
	finish(player, weapon, variantKey, tally, {
		shape = shape,
		origin = origin,
		direction = unit,
		size = reach,
		arcDegrees = variant.arcDegrees,
		width = variant.width,
		endPoint = nil,
		seq = seed,
		-- L2-29: a held stream's shots are ticks of one lasting stream, as a held beam's are.
		tick = if variant.continuous == true then true else nil,
	})
end

-- Where a flight is `t` seconds after it began, and how fast it is moving there.
local function flightPoint(projectile: Projectile, t: number): Vector3
	return projectile.origin
		+ projectile.velocity * t
		+ Vector3.new(0, -0.5 * projectile.gravity * t * t, 0)
end

local function flightVelocity(projectile: Projectile, t: number): Vector3
	return projectile.velocity + Vector3.new(0, -projectile.gravity * t, 0)
end

local function markVolley(volley: Volley, id: number): ()
	if not volley.hit[id] then
		volley.hit[id] = true
		volley.distinct += 1
	end
end

-- Every projectile strike reports the whole volley's totals to the shooter's readout (an
-- ability's strikes add to their cast's readout instead).
local function reportShot(projectile: Projectile, tally: Tally, fx: StrikeFx): ()
	local volley = projectile.volley
	for _, hit in tally.hits do
		markVolley(volley, hit.id)
	end
	volley.kills += tally.kills
	finish(
		projectile.player,
		projectile.weapon,
		projectile.variantKey,
		tally,
		fx,
		{ hits = volley.distinct, kills = volley.kills },
		projectile.ability
	)
end

-- An ability projectile's hook, run inside the step. A failing hook is logged and swallowed so
-- one ability bug can never stop every other projectile in flight.
local function runImpact(projectile: Projectile, point: Vector3): ()
	local hook = projectile.onImpact
	if hook == nil then
		return
	end
	local ok, message = pcall(function(): any?
		hook(point)
		return nil
	end)
	if not ok then
		local id = if projectile.ability ~= nil then projectile.ability.id else projectile.weapon
		warn(`[WeaponService] {id} impact hook failed: {message}`)
	end
end

-- A shell bursts at `impact` (splashRadius, capped nearest-first like any blast).
local function detonate(
	config: Types.ProvingGroundsConfig,
	projectile: Projectile,
	direction: Vector3,
	impact: Vector3
): ()
	if projectile.player.Parent == nil then
		return
	end
	local variant = projectile.variant
	local radius = variant.splashRadius or 0
	local tally = StrikeTally.New(projectile.tierScale)
	explode(config, projectile.player, impact, radius, variant, projectile.damage, direction, tally)
	reportShot(projectile, tally, {
		shape = "sphere",
		origin = projectile.shotOrigin,
		direction = direction,
		size = radius,
		arcDegrees = nil,
		width = nil,
		endPoint = impact,
		seq = projectile.seed,
	})
	runImpact(projectile, impact)
end

-- An arrow is done at `stop`. A full charge bursts there (blastRadius, damage x blastDamageMult,
-- no cap); either way the strike carries endPoint = stop, which tells every client where the
-- arrow ends. A strike without endPoint is an arrow still in flight.
local function endArrow(
	config: Types.ProvingGroundsConfig,
	projectile: Projectile,
	from: Vector3,
	direction: Vector3,
	stop: Vector3,
	tally: Tally
): ()
	if projectile.player.Parent == nil then
		return
	end
	local variant = projectile.variant
	local blastRadius = variant.blastRadius or 0
	if projectile.fullCharge and blastRadius > 0 then
		local blast: Blast = {
			pad = variant.pad,
			cap = 0,
			knockback = variant.knockback,
			launch = variant.launch,
		}
		local damage = projectile.damage * math.max(variant.blastDamageMult or 0, 0)
		explode(config, projectile.player, stop, blastRadius, blast, damage, direction, tally)
		reportShot(projectile, tally, {
			shape = "sphere",
			origin = projectile.shotOrigin,
			direction = direction,
			size = blastRadius,
			arcDegrees = nil,
			width = nil,
			endPoint = stop,
			seq = projectile.seed,
		})
	else
		reportShot(projectile, tally, {
			shape = "ray",
			origin = from,
			direction = direction,
			size = (stop - from).Magnitude,
			arcDegrees = nil,
			width = variant.width,
			endPoint = stop,
			seq = projectile.seed,
		})
	end
	runImpact(projectile, stop)
end

-- A split parent becomes its fan at `point`. First a CombatFxShot with split = true tells every
-- client to split its own flight there; then the children start at `point` with the parent's
-- speed along HitShapes.Fan(the parent's velocity there, splitCount, splitArcDegrees, seed,
-- fanJitterShare). They keep its gravity, path length and volley, and `carry` = the rest of this
-- frame, which stepProjectiles flies at once so a child never lags its parent's clock.
local function splitArrow(
	config: Types.ProvingGroundsConfig,
	projectile: Projectile,
	point: Vector3,
	heading: Vector3,
	carry: number,
	spawned: { Projectile }
): ()
	local variant = projectile.variant
	local speed = variant.projectileSpeed or 0
	local direction = if heading.Magnitude > 1e-6 then heading.Unit else DOWN
	broadcastFx({
		kind = "shot",
		userId = projectile.player.UserId,
		weapon = projectile.weapon,
		variant = projectile.variantKey,
		origin = point,
		direction = direction,
		speed = speed,
		gravity = projectile.gravity,
		charge = projectile.charge,
		seq = projectile.seed,
		split = true,
		ability = if projectile.ability ~= nil then projectile.ability.id else nil,
	})
	local arrows = HitShapes.Fan(
		direction,
		volleySize(variant),
		variant.splitArcDegrees or 0,
		projectile.seed,
		config.shooting.fanJitterShare
	)
	for _, arrow in arrows do
		-- OnAttack reserved the whole volley up front; this only guards a tuned-up splitCount.
		if projectileCount() + #spawned >= CONST.MAX_PROJECTILES then
			break
		end
		table.insert(spawned, {
			player = projectile.player,
			weapon = projectile.weapon,
			variantKey = projectile.variantKey,
			variant = variant,
			shotOrigin = projectile.shotOrigin,
			origin = point,
			velocity = arrow * speed,
			gravity = projectile.gravity,
			position = point,
			age = 0,
			-- The carried time is added back when the child flies it.
			lifetime = projectile.lifetime - carry,
			travelled = projectile.travelled,
			damage = projectile.damage,
			tierScale = projectile.tierScale,
			fullCharge = projectile.fullCharge,
			hitsLeft = pierceOf(variant),
			charge = projectile.charge,
			carry = carry,
			splitting = false,
			volley = projectile.volley,
			seed = projectile.seed,
			ability = projectile.ability,
			onImpact = projectile.onImpact,
		})
	end
end

-- One step of one projectile along its parabola. Returns true while it is still flying. Arrows
-- hit every enemy they pass (entry order, one hit per enemy per volley) until hitsLeft or the
-- volley cap is spent, and stop at walls and the ground; shells burst on the first contact.
local function stepProjectile(
	config: Types.ProvingGroundsConfig,
	projectile: Projectile,
	deltaTime: number,
	params: RaycastParams,
	spawned: { Projectile }
): boolean
	local variant = projectile.variant
	local from = projectile.position
	local startAge = projectile.age
	projectile.age += deltaTime
	projectile.lifetime += deltaTime
	local offset = flightPoint(projectile, projectile.age) - from
	local length = offset.Magnitude
	local expired = projectile.lifetime >= config.shooting.projectileMaxSeconds
	if length < 1e-6 then
		if expired then
			endArrow(config, projectile, from, DOWN, from, StrikeTally.New(projectile.tierScale))
		end
		return not expired
	end
	local direction = offset / length
	local budget = math.max(0, variant.range - projectile.travelled)
	local splitAt = if projectile.splitting
		then math.max(0, (variant.splitDistance or 0) - projectile.travelled)
		else math.huge
	local reach = math.min(length, budget, splitAt)
	local wall = if reach > 0 then worldReach(from, direction, reach, params) else 0
	local candidates: { Candidate } = if wall > 0
		then rayCandidates(config, from, direction, wall, variant.width or 0, variant.pad)
		else {}
	local volley = projectile.volley
	-- Out of range or time at the end of this step: whatever did not stop it earlier ends here.
	local spent = reach < length or expired or projectile.travelled + reach >= variant.range

	if variant.shape == "sphere" then
		local first = candidates[1]
		local impact: Vector3? = nil
		if first ~= nil then
			impact = from + direction * first.order
		elseif wall < reach or spent then
			impact = from + direction * wall
		end
		if impact ~= nil then
			detonate(config, projectile, direction, impact)
			return false
		end
		projectile.position = from + direction * reach
		projectile.travelled += reach
		return true
	end

	if projectile.splitting then
		-- The first enemy it meets splits it early, at the contact point; a wall ends it whole.
		local contact: number? = nil
		for _, candidate in candidates do
			if not volley.hit[candidate.id] then
				contact = candidate.order
				break
			end
		end
		if contact == nil and wall < reach then
			endArrow(
				config,
				projectile,
				from,
				direction,
				from + direction * wall,
				StrikeTally.New(projectile.tierScale)
			)
			return false
		end
		if contact == nil and reach >= splitAt then
			contact = splitAt
		end
		if contact ~= nil then
			local used = deltaTime * (contact / length)
			projectile.travelled += contact
			splitArrow(
				config,
				projectile,
				from + direction * contact,
				flightVelocity(projectile, startAge + used),
				deltaTime - used,
				spawned
			)
			return false
		end
		projectile.position = from + direction * reach
		projectile.travelled += reach
		if spent then
			endArrow(
				config,
				projectile,
				from,
				direction,
				projectile.position,
				StrikeTally.New(projectile.tierScale)
			)
			return false
		end
		return true
	end

	-- Its siblings already filled the volley's cap: this arrow ends where it is, no ghost flight.
	if volley.cap > 0 and volley.distinct >= volley.cap then
		endArrow(config, projectile, from, direction, from, StrikeTally.New(projectile.tierScale))
		return false
	end
	local tally = StrikeTally.New(projectile.tierScale)
	local critMult = config.shooting.critMult
	local push = (flatten(direction) or Vector3.zero) * variant.knockback
	local stopAt: number? = nil
	for _, candidate in candidates do
		if volley.hit[candidate.id] then
			continue
		end
		local amount = if candidate.crit then projectile.damage * critMult else projectile.damage
		strike(tally, projectile.player, candidate.id, amount, candidate.crit, push, variant.launch)
		markVolley(volley, candidate.id)
		projectile.hitsLeft -= 1
		-- The hit that spends its pierce or the volley's cap stops the arrow IN that enemy, so the
		-- end strike (and a full-charge burst) lands there.
		if projectile.hitsLeft <= 0 or (volley.cap > 0 and volley.distinct >= volley.cap) then
			stopAt = candidate.order
			break
		end
	end
	if stopAt == nil and wall < reach then
		stopAt = wall
	end
	if stopAt ~= nil then
		endArrow(config, projectile, from, direction, from + direction * stopAt, tally)
		return false
	end
	projectile.position = from + direction * reach
	projectile.travelled += reach
	if spent then
		endArrow(config, projectile, from, direction, projectile.position, tally)
		return false
	end
	if #tally.hits > 0 then
		reportShot(projectile, tally, {
			shape = "ray",
			origin = from,
			direction = direction,
			size = reach,
			arcDegrees = nil,
			width = variant.width,
			endPoint = nil,
			seq = projectile.seed,
		})
	end
	return true
end

local function stepProjectiles(config: Types.ProvingGroundsConfig, deltaTime: number): ()
	if #state.projectiles == 0 then
		return
	end
	local params = worldParams()
	local survivors: { Projectile } = {}
	local spawned: { Projectile } = {}
	state.stepping = true
	for _, projectile in state.projectiles do
		if stepProjectile(config, projectile, deltaTime, params, spawned) then
			table.insert(survivors, projectile)
		end
	end
	-- Newborn split children fly the rest of the frame their parent split in (children never
	-- split again, so nothing new is spawned here).
	local none: { Projectile } = {}
	for _, child in spawned do
		local carry = child.carry
		child.carry = 0
		if carry <= 0 or stepProjectile(config, child, carry, params, none) then
			table.insert(survivors, child)
		end
	end
	state.stepping = false
	-- Shots an impact hook fired this step start flying next frame.
	for _, fired in state.pending do
		table.insert(survivors, fired)
	end
	state.pending = {}
	state.projectiles = survivors
end

-- Air tracking for the slam and air swings: the server's own view of how high each character
-- got and how fast it fell. Fall speed is the larger of the replicated velocity and the
-- position change, so a client that zeroes its reported velocity still shows its real dive.
-- The same pass samples each root for the claim slack (ruling 7).
local function trackAir(now: number, deltaTime: number): ()
	if next(state.shooters) == nil then
		return
	end
	local params = worldParams()
	for player, shooter in state.shooters do
		local _character, root, humanoid = rootOf(player)
		if root == nil or humanoid == nil then
			shooter.airborne = false
			shooter.lastY = nil
			shooter.stood = nil
			shooter.fall = nil
			PositionRing.Clear(shooter.history)
			continue
		end
		local position = root.Position
		PositionRing.Record(shooter.history, now, position)
		-- Fix round A-1: the air-swing gate's own sample, the one AirSwing feeds on the client.
		local footing = footprintFloor(position, root, params)
		local offset = standingOffset(root, humanoid)
		SwingGate.Observe(
			shooter.airSwing,
			position.Y,
			root.AssemblyLinearVelocity.Y,
			footing,
			offset,
			VitalsService.IsDown(player)
		)
		-- The L2 W3 fix round's s-M1: where the body last stood, on the same footprint floor.
		if footing ~= nil and not SwingGate.IsAir(position.Y - footing, offset) then
			shooter.stood = position
		end
		local floorY = floorBelow(root, params)
		local height = if floorY ~= nil then root.Position.Y - floorY else math.huge
		local airborne = height > standingOffset(root, humanoid) + CONST.AIRBORNE_MARGIN_STUDS
		local y = root.Position.Y
		local previousY = shooter.lastY
		local fallSpeed = -root.AssemblyLinearVelocity.Y
		if previousY ~= nil and deltaTime > 0 then
			fallSpeed = math.max(fallSpeed, (previousY - y) / deltaTime)
		end
		shooter.lastY = y
		-- The third fix round's fd-m2: a body this sample did not find standing (where it stood is
		-- not where it is) is falling at the speed measured here, the slam's own.
		shooter.fall = if shooter.stood == position then nil else math.max(fallSpeed, 0)
		if airborne then
			if shooter.airborne then
				shooter.peakY = math.max(shooter.peakY, y)
				shooter.diveSpeed = math.max(shooter.diveSpeed, fallSpeed)
			else
				shooter.peakY = y
				shooter.diveSpeed = math.max(fallSpeed, 0)
			end
		elseif shooter.airborne then
			shooter.lastPeakY = shooter.peakY
			-- The landing frame's own fall counts: the dive ends on it.
			shooter.lastDiveSpeed = math.max(shooter.diveSpeed, fallSpeed)
			shooter.landedAt = now
		end
		shooter.airborne = airborne
	end
end

-- A fresh character starts on the ground with no jump to slam from and no motion behind it: the
-- last body's peak, dive and positions would otherwise buy a slam or slack it never earned.
local function resetAir(shooter: Shooter): ()
	shooter.airborne = false
	shooter.peakY = 0
	shooter.lastPeakY = -math.huge
	shooter.landedAt = 0
	shooter.diveSpeed = 0
	shooter.lastDiveSpeed = 0
	shooter.lastY = nil
	shooter.stood = nil
	shooter.fall = nil
	shooter.airSwing = SwingGate.New()
	PositionRing.Clear(shooter.history)
end

-- Opens an i-frame window of `seconds` from `now`, or lengthens the one still open: it never
-- shortens a longer window (a dash inside an ability's leap).
local function openIframes(shooter: Shooter, now: number, seconds: number): ()
	if now >= shooter.iframesUntil then
		-- The last window had lapsed: it steps back and this one starts now.
		shooter.iframesWasFrom = shooter.iframesFrom
		shooter.iframesWasUntil = shooter.iframesUntil
		shooter.iframesFrom = now
	end
	shooter.iframesUntil = math.max(shooter.iframesUntil, now + math.max(seconds, 0))
	shooter.iframesShown = true
	local character = shooter.player.Character
	if character ~= nil then
		character:SetAttribute(CONST.IFRAMES_ATTRIBUTE, true)
	end
end

local function tickIframes(now: number): ()
	for player, shooter in state.shooters do
		if shooter.iframesShown and now >= shooter.iframesUntil then
			shooter.iframesShown = false
			local character = player.Character
			if character ~= nil then
				character:SetAttribute(CONST.IFRAMES_ATTRIBUTE, nil)
			end
		end
	end
end

local function step(deltaTime: number): ()
	local config = Tuning.Get()
	local now = os.clock()
	trackAir(now, deltaTime)
	tickIframes(now)
	stepProjectiles(config, deltaTime)
	state.statsAccumulator += deltaTime
	if state.statsAccumulator >= CONST.STATS_INTERVAL_SECONDS then
		state.statsAccumulator = 0
		for _, listener in state.readoutListeners do
			listener()
		end
		for _, shooter in state.shooters do
			sendStats(shooter)
		end
	end
end

-- Mode and wiring -----------------------------------------------------------------------------

-- Must be called before Init, with Main's one boot decision (CombatMode.Get). The weapons run in
-- both modes; they stay off only without Config/ProvingGrounds, where every family lives.
function WeaponService.Configure(mode: Types.CombatMode): ()
	state.mode = mode
	state.active = Tuning.IsAvailable()
	if not state.active then
		warn("[WeaponService] Config/ProvingGrounds is missing; the player's weapons are off")
	end
end

function WeaponService.IsActive(): boolean
	return state.active
end

function WeaponService.Mode(): Types.CombatMode
	return state.mode
end

-- Contract stub, deliberately a no-op: every weapon shape is resolved against the world and the
-- crowd, and nothing here needs the floor's bounds. WaveService calls it at a run's start;
-- removing it would break that call (P5 review, minor 4).
function WeaponService.SetArena(_center: Vector3, _halfSize: Vector3): () end

-- Ruling 21: nil = every player may act (the range).
function WeaponService.SetActGate(gate: ((player: Player) -> boolean)?): ()
	state.actGate = gate
end

-- RangeService's readout fields; the provider fills `stats` in place and must not yield.
function WeaponService.SetStatsProvider(
	provider: ((player: Player, stats: Types.RangeStats) -> ())?
): ()
	state.statsProvider = provider
end

-- Runs synchronously inside the strike's frame, whenever an attack dealt damage (plate damage
-- included). Must not yield. RangeService starts its clear clock on it.
function WeaponService.OnDamageDealt(callback: (player: Player, dealt: number) -> ()): ()
	table.insert(state.dealtListeners, callback)
end

-- L2-35: runs synchronously at the end of every resolved strike (an attack, an ability's strike,
-- a projectile's hit), after its CombatFxStrike is queued, with the strike's shape as drawn and
-- the ability id when an ability dealt it. The empty end strikes of abandoned projectiles are
-- skipped. Must not yield; a throw is caught (warned once) so the strike's readout still goes
-- out. The lead wires LevelService.React here.
function WeaponService.OnStrikeResolved(callback: StrikeListener): ()
	table.insert(state.strikeListeners, callback)
end

-- Runs synchronously at every 2 Hz readout tick, just before the readouts go out. Must not
-- yield. RangeService sweeps its lost dummies on it, on the one readout clock.
function WeaponService.OnReadoutTick(callback: () -> ()): ()
	table.insert(state.readoutListeners, callback)
end

-- True when this player may attack, draw, dash, slam or cast at all (ruling 21; down is
-- checked apart, by VitalsService).
function WeaponService.MayAct(player: Player): boolean
	return state.active and state.shooters[player] ~= nil and mayAct(player)
end

-- Players ------------------------------------------------------------------------------------

-- L3-49: the one writer of the three character attributes every client hangs this player's
-- weapons from (WeaponLook.Values: the held melee and ranged families, the slot in use). On
-- `character` when given (a fresh one, before it is the player's Character), else on the live one.
-- Attributes replicate, so no remote carries them; none of them is ever read where a hit is judged.
local function showWeapons(shooter: Shooter, character: Model?): ()
	local target = character or shooter.player.Character
	if target == nil then
		return
	end
	for name, value in WeaponLook.Values(shooter.loadout, shooter.held) do
		target:SetAttribute(name, value)
	end
end

-- L3-50: the slot in use, from an accepted attack, draw or cast. Shown only when it changed.
local function noteHeld(shooter: Shooter, slot: SlotName): ()
	if shooter.held == slot then
		return
	end
	shooter.held = slot
	showWeapons(shooter, nil)
end

-- A loaded player takes up their weapons, then TuneState and a first readout. Idempotent. In the
-- range: the ProvingGrounds.json loadout (Wave 1). In a mission (L3-10): the saved loadout, read
-- by Unlocks.LoadoutOf with each slot's starter as the fallback (a saved family no longer owned,
-- unknown or in the wrong slot falls back; an unknown style falls back to the family's default).
-- The range's RangeService.AddPlayer wraps this and places the body; in a mission ArenaService's
-- character hook prepares it.
function WeaponService.AddPlayer(player: Player): ()
	if not state.active or state.shooters[player] ~= nil or player.Parent == nil then
		return
	end
	local config = Tuning.Get()
	local starters = {
		melee = startingFamily(config, "melee"),
		ranged = startingFamily(config, "ranged"),
	}
	local loadout: Types.RangeLoadout =
		{ melee = starters.melee, ranged = starters.ranged, variants = {} }
	if state.mode == "mission" then
		local profile = DataService.GetState(player)
		local saved = Unlocks.LoadoutOf(
			if profile ~= nil then profile.combat else nil,
			config.weapons,
			starters
		)
		-- A copy: the shooter's loadout changes for the session, the profile's only on a save.
		loadout =
			{ melee = saved.melee, ranged = saved.ranged, variants = table.clone(saved.variants) }
	end
	local shooter: Shooter = {
		player = player,
		loadout = loadout,
		lastSeq = { melee = -1, ranged = -1 },
		lastAttackAt = { melee = 0, ranged = 0 },
		credit = {},
		creditAt = {},
		combo = {},
		drawStartedAt = 0,
		drawWeapon = "",
		lastDashAt = 0,
		iframesFrom = 0,
		iframesUntil = 0,
		iframesWasFrom = 0,
		iframesWasUntil = 0,
		iframesShown = false,
		lastSlamAt = 0,
		airborne = false,
		peakY = 0,
		lastPeakY = -math.huge,
		landedAt = 0,
		airSwing = SwingGate.New(),
		diveSpeed = 0,
		lastDiveSpeed = 0,
		lastY = nil,
		stood = nil,
		fall = nil,
		seedRandom = Random.new(),
		damageLog = {},
		lastHits = 0,
		lastKills = 0,
		buffs = {},
		lockUntil = 0,
		lockAllow = nil,
		abilityId = nil,
		abilityCast = 0,
		abilityHits = 0,
		abilityKills = 0,
		history = PositionRing.New(CONST.HISTORY_CAPACITY),
		-- The client's starting stance.
		held = "melee",
	}
	state.shooters[player] = shooter
	VitalsService.AddPlayer(player)
	if state.mode == "mission" then
		-- The character usually spawned before admission, when ArenaService's hook found no
		-- vitals to prepare: its body is made a fighter's now.
		local character = player.Character
		if character ~= nil then
			WeaponService.PrepareCharacter(player, character)
		end
	end
	tuneStateFor(shooter)
	sendStats(shooter)
end

function WeaponService.RemovePlayer(player: Player): ()
	local shooter = state.shooters[player]
	if shooter == nil then
		return
	end
	state.shooters[player] = nil
	state.gearOverride[player] = nil
	state.warnedAimWall[player] = nil
	VitalsService.RemovePlayer(player)
	local survivors: { Projectile } = {}
	for _, projectile in state.projectiles do
		if projectile.player ~= player then
			table.insert(survivors, projectile)
		end
	end
	state.projectiles = survivors
end

-- A fresh character, already where it should stand: its air state starts over, it shows the
-- held weapons (L3-49, in every mode) and its body (health, regen) is VitalsService's.
function WeaponService.PrepareCharacter(player: Player, character: Model): ()
	if not state.active then
		return
	end
	local shooter = state.shooters[player]
	if shooter ~= nil then
		resetAir(shooter)
		showWeapons(shooter, character)
	end
	VitalsService.PrepareCharacter(player, character)
end

-- Ruling 12, L3-6: (tiers, ascension) per slot. Tier 1 and no Ascension in the range; otherwise
-- each held family's Armory.StrikeTier: the Studio session override's tier (L1 ruling 34) held
-- inside the family's window, else its tier on the profile (tier 1 until it has loaded), in a
-- proving build too (L3-11). Fresh tables.
function WeaponService.GearOf(player: Player): (SlotTiers, SlotTiers)
	return gearOf(player)
end

-- L1 ruling 34: the Studio session override's tiers as a lever set them, before any window holds
-- them (GearOf answers what is fought at); nil when none is set. The G key compares its presets
-- with this: G's T1 fights a held Flamethrower at T2, so GearOf would never match the preset
-- again and every press would set T1. A fresh table.
function WeaponService.GearOverride(player: Player): SlotTiers?
	local override = state.gearOverride[player]
	return if override ~= nil then table.clone(override.gear) else nil
end

-- L1 ruling 34: the tiers this player fights at for the rest of the session, both slots, whatever
-- the profile says (each held inside the held family's window, 2-s1); nil clears it (a successful
-- upgrade, setTier and resetArmory do, L3-28).
-- Studio only: outside Studio it does nothing, and it is never written to a profile. The caller
-- refreshes the body (VitalsService.RefreshMaxHp).
function WeaponService.SetGearOverride(
	player: Player,
	gear: Types.SlotTiers?,
	ascension: Types.SlotTiers?
): ()
	if not RunService:IsStudio() then
		return
	end
	if gear == nil then
		state.gearOverride[player] = nil
		return
	end
	state.gearOverride[player] = {
		gear = { melee = gear.melee, ranged = gear.ranged },
		ascension = if ascension ~= nil
			then { melee = ascension.melee, ranged = ascension.ranged }
			else table.clone(CONST.NO_ASCENSION),
	}
end

-- Ruling 8, L3-6: Armory.DamageScale at the tier of the family that strikes; 1 in the range.
function WeaponService.DamageScale(player: Player, family: string, ability: boolean): number
	return damageScale(player, family, ability)
end

-- The server itself just moved this player's body (a rescue, a release from the lobby pad):
-- the jump is not the player's motion, and left in the position ring it would read as up to
-- originLagMaxSeconds of capped claim slack. Clears that history, and (the L2 W3 fix round's
-- s-M1) where the body last stood, which is not where it now is: a fall before it stands again
-- is judged by where it is; and (the third fix round's fd-m2) its fall speed, until the next
-- sample measures it where it was put. A fresh character needs no call: PrepareCharacter already
-- clears them. No-op for a player without weapons, and so before any player has been added.
function WeaponService.ForgetMotion(player: Player): ()
	local shooter = state.shooters[player]
	if shooter ~= nil then
		PositionRing.Clear(shooter.history)
		shooter.stood = nil
		shooter.fall = nil
	end
end

-- The L2 W3 fix round's s-M1: the root where the server last saw `player`'s body grounded (on
-- the air tracking's footprint floor), for the rescue's landing (StageFlow.FallLanding). nil for a
-- player without weapons, a fresh body that has not stood yet, or one the server just moved.
function WeaponService.LastGround(player: Player): Vector3?
	local shooter = state.shooters[player]
	return if shooter ~= nil then shooter.stood else nil
end

-- The L2 W3 third fix round's fd-m2: how fast `player`'s body was falling when the air tracking
-- last sampled it off its footprint's floor (studs/s, downward positive, at least 0: the larger
-- of its replicated velocity and its position's change, as the slam reads it); nil while it
-- stood, and for a player without weapons, a fresh body or one the server just moved. LevelService
-- leads a falling body's feet by it before it judges an ice cell (WorldReact.FallDrop).
function WeaponService.FallSpeed(player: Player): number?
	local shooter = state.shooters[player]
	return if shooter ~= nil then shooter.fall else nil
end

-- Every live projectile ends where it is (an empty end strike, so clients stop their flights):
-- a set reload, or the end of a run.
function WeaponService.AbandonProjectiles(): ()
	abandonProjectiles()
end

-- A readout now (the range's commands answer with one).
function WeaponService.SendStats(player: Player): ()
	local shooter = state.shooters[player]
	if shooter ~= nil then
		sendStats(shooter)
	end
end

-- True while an i-frame window is open (the character attribute shows the same in Studio).
function WeaponService.IsInvulnerable(player: Player): boolean
	local shooter = state.shooters[player]
	return shooter ~= nil and os.clock() < shooter.iframesUntil
end

-- The player's latest i-frame window on os.clock() and the one before it: (from, until,
-- previous from, previous until), still answered after they have lapsed; 0, 0 = never had
-- one. VitalsService voids an enemy hit whose judging span either of them met.
function WeaponService.IframeWindow(player: Player): (number, number, number, number)
	local shooter = state.shooters[player]
	if shooter == nil then
		return 0, 0, 0, 0
	end
	return shooter.iframesFrom,
		shooter.iframesUntil,
		shooter.iframesWasFrom,
		shooter.iframesWasUntil
end

-- Intents (payload shapes already checked by CombatRemotes) -----------------------------------

-- `weapon` is a family id and must be the family the player holds in that family's slot.
-- `charge` (0-1) matters only for charge weapons and is capped by the server's draw clock.
function WeaponService.OnAttack(
	player: Player,
	weapon: string,
	seq: number,
	origin: Vector3,
	direction: Vector3,
	_ads: boolean,
	charge: number?
): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return
	end
	local config = Tuning.Get()
	local def = familyDef(config, weapon)
	if def == nil then
		return
	end
	local slot: SlotName = if def.slot == "melee" then "melee" else "ranged"
	if slotFamily(shooter, slot) ~= weapon then
		-- The client fired a family it does not hold (a stale switch): take its effects back.
		sendRefused(shooter, seq)
		return
	end
	if seq <= (shooter.lastSeq[slot] or -1) then
		return
	end
	local now = os.clock()
	if slotLocked(shooter, slot, now) or VitalsService.IsDown(player) or not mayAct(player) then
		-- A busy ability owns the caster (ruling 3), a downed player attacks nothing (P4), and in
		-- a mission only a fighting player attacks (P5 ruling 21): the client's early effects are
		-- taken back.
		sendRefused(shooter, seq)
		return
	end
	local _character, root, humanoid = rootOf(player)
	if root == nil then
		return
	end
	local variantKey, variant = variantFor(config, shooter, weapon)
	if variant == nil or variant.rate <= 0 then
		return
	end
	local buff = activeBuff(shooter, slot, now)
	local rate = variant.rate * (if buff ~= nil then buff.rateMult else 1)
	if rate <= 0 then
		return
	end
	local previousAttackAt = shooter.lastAttackAt[slot] or 0
	-- A shot may come timingTolerance of a credit early (the jitter window); it spends a whole
	-- one, so the average stays at `rate`. The same test as nextAllowedAt - interval x (1 -
	-- tolerance), kept in shots so a rate change applies from now on.
	local credit = shotCredit(shooter, slot, rate, now, config.shooting)
	if credit < timingTolerance() then
		sendRefused(shooter, seq)
		return
	end
	if variant.kind == "ranged" then
		if not aimAllowed(shooter, root, origin, config) then
			sendRefused(shooter, seq)
			return
		end
		-- A split shot becomes splitCount arrows: the whole volley must fit, or the shot is refused.
		if
			(variant.projectileSpeed or 0) > 0
			and projectileCount() + volleySize(variant) > CONST.MAX_PROJECTILES
		then
			sendRefused(shooter, seq)
			return
		end
	end
	-- L1b-W2-13: one melee swing per jump, judged at the swing's own origin (the claim, clamped
	-- by the claim slack) against the floor under it, so a swing on the take-off frame is
	-- airborne and one on the landing frame grounded: an honest client is never refused. Fix
	-- round A-1: the floor is the footprint's, and the claim is the newest sample, so a swing
	-- sent just after a bounce the server's copy has not shown yet still finds its landing.
	local swingAt = origin
	local airSwing = false
	if variant.kind == "melee" then
		swingAt = meleeOrigin(shooter, root, origin, config)
		local floorY = footprintFloor(swingAt, root, worldParams())
		local standOffset = if humanoid ~= nil
			then standingOffset(root, humanoid)
			else root.Size.Y / 2
		local lag = Tuning.CommitLag(config.shooting, player:GetNetworkPing())
		local allowed
		allowed, airSwing = SwingGate.Judge(shooter.airSwing, swingAt.Y, floorY, standOffset, lag)
		if not allowed then
			sendRefused(shooter, seq)
			return
		end
		if now - previousAttackAt > config.controls.comboResetSeconds then
			-- A pause breaks the combo: the next swing is step 1 again.
			shooter.combo[weapon] = 0
		end
	end
	shooter.lastSeq[slot] = seq
	noteHeld(shooter, slot)
	shooter.lastAttackAt[slot] = now
	shooter.credit[slot] = credit - 1
	shooter.creditAt[slot] = now
	if variant.kind == "melee" then
		SwingGate.Took(shooter.airSwing, airSwing)
		resolveMelee(
			config,
			shooter,
			weapon,
			variantKey,
			variant,
			root,
			seq,
			swingAt,
			direction,
			airSwing
		)
	else
		local used, scale, full =
			resolveCharge(shooter, weapon, variant, charge or 0, previousAttackAt, now)
		resolveRanged(
			config,
			shooter,
			weapon,
			variantKey,
			variant,
			origin,
			direction,
			used,
			scale,
			full,
			if buff ~= nil then buff.pierce else nil
		)
	end
end

-- The bow's draw start. It carries nothing the server trusts: it stamps its own clock, and
-- OnAttack caps the charge by the time since this stamp. A draw begun while a busy ability locks
-- the slot starts counting only when the lock ends, so no charge is banked during the ability.
function WeaponService.OnDraw(player: Player, weapon: string): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return
	end
	local def = familyDef(Tuning.Get(), weapon)
	if def == nil then
		return
	end
	local slot: SlotName = if def.slot == "melee" then "melee" else "ranged"
	-- A downed player starts no draw (P4 ruling 24c), like their other intents; nor does one
	-- the mission's act gate holds back (P5 ruling 21).
	if
		slotFamily(shooter, slot) ~= weapon
		or VitalsService.IsDown(player)
		or not mayAct(player)
	then
		return
	end
	local now = os.clock()
	shooter.drawStartedAt = if slotLocked(shooter, slot, now) then shooter.lockUntil else now
	shooter.drawWeapon = weapon
	noteHeld(shooter, slot)
end

-- Opens the i-frame window; the dash itself moves the client-owned character.
function WeaponService.OnDash(player: Player, _direction: Vector3): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return
	end
	local character, root = rootOf(player)
	if character == nil or root == nil or VitalsService.IsDown(player) or not mayAct(player) then
		return
	end
	local movement = Tuning.Get().movement
	local now = os.clock()
	if now - shooter.lastDashAt < movement.dashCooldown * timingTolerance() then
		return
	end
	shooter.lastDashAt = now
	openIframes(shooter, now, movement.dashIframes)
end

-- The slam lands where the SERVER sees the character come down, and only after a fall of at
-- least slamMinHeight from the server-tracked peak with a dive of at least slamMinDiveSpeed in
-- that airtime. The client may send it at impact, so a request within slamLandingGrace of the
-- landing still counts that jump.
function WeaponService.OnSlam(player: Player): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return
	end
	local _character, root, humanoid = rootOf(player)
	if root == nil or humanoid == nil or VitalsService.IsDown(player) or not mayAct(player) then
		return
	end
	local config = Tuning.Get()
	local movement = config.movement
	local now = os.clock()
	if now - shooter.lastSlamAt < movement.slamCooldown * timingTolerance() then
		return
	end
	local peak: number
	local dive: number
	if shooter.airborne then
		peak = shooter.peakY
		dive = shooter.diveSpeed
	elseif now - shooter.landedAt <= movement.slamLandingGrace then
		peak = shooter.lastPeakY
		dive = shooter.lastDiveSpeed
	else
		return
	end
	if dive < movement.slamMinDiveSpeed then
		return
	end
	local standY = root.Position.Y
	if shooter.airborne then
		local floorY = floorBelow(root, worldParams())
		if floorY ~= nil then
			standY = floorY + standingOffset(root, humanoid)
		end
	end
	if peak - standY < movement.slamMinHeight then
		return
	end
	shooter.lastSlamAt = now
	-- One peak buys one slam.
	shooter.peakY = standY
	shooter.lastPeakY = -math.huge
	shooter.diveSpeed = 0
	shooter.lastDiveSpeed = 0

	local center = Vector3.new(root.Position.X, standY, root.Position.Z)
	-- Unlimited targets: the slam is the crowd move a big jump buys.
	local blast: Blast = {
		pad = movement.slamPad,
		cap = 0,
		knockback = movement.slamKnockback,
		launch = movement.slamLaunch,
	}
	-- Ruling 8, L3-6: the slam scales with the held melee family.
	local tally = StrikeTally.New(damageScale(player, shooter.loadout.melee, false))
	explode(
		config,
		player,
		center,
		movement.slamRadius,
		blast,
		movement.slamDamage,
		root.CFrame.LookVector,
		tally
	)
	finish(player, "slam", "", tally, {
		shape = "sphere",
		origin = center,
		direction = DOWN,
		size = movement.slamRadius,
		arcDegrees = nil,
		width = nil,
		endPoint = nil,
	})
end

-- Loadout ------------------------------------------------------------------------------------

local function onTuningChanged(): ()
	for _, shooter in state.shooters do
		tuneStateFor(shooter)
	end
end

-- Puts `family` into its own slot (the range's `weapon` command). False for an unknown family
-- or player. Picking the family already held keeps its combo, so the client's predicted step
-- only restarts on a real change; a change drops the slot's buff (it belongs to the family
-- whose ability granted it) and tells the loadout listeners. Every call shows the pair again
-- (L3-49), the lobby's equip and the levers included.
function WeaponService.SetFamily(player: Player, family: string): boolean
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return false
	end
	local def = familyDef(Tuning.Get(), family)
	if def == nil then
		return false
	end
	local slot: SlotName = if def.slot == "melee" then "melee" else "ranged"
	local previous = slotFamily(shooter, slot)
	if slot == "melee" then
		shooter.loadout.melee = family
	else
		shooter.loadout.ranged = family
	end
	shooter.drawStartedAt = 0
	showWeapons(shooter, nil)
	tuneStateFor(shooter)
	if previous ~= family then
		shooter.combo[family] = 0
		shooter.buffs[slot] = nil
		for _, listener in table.clone(state.loadoutListeners) do
			task.spawn(listener, player, slot)
		end
	end
	return true
end

-- Holds variant `key` of `family` (the range's `variant` command). False when either is
-- unknown. A different variant restarts that family's combo.
function WeaponService.SetVariant(player: Player, family: string, key: string): boolean
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return false
	end
	local def = familyDef(Tuning.Get(), family)
	if def == nil or def.variants[key] == nil then
		return false
	end
	if (shooter.loadout.variants[family] or def.default) ~= key then
		shooter.combo[family] = 0
	end
	shooter.loadout.variants[family] = key
	tuneStateFor(shooter)
	return true
end

-- Hooks for AbilityService (INTERFACES "P3 contracts" → "Server APIs"), in either mode. None of
-- them yields, so AbilityService may call them from its own Heartbeat timelines.

-- A fresh copy with the variant held for every family; nil = not a player with weapons.
function WeaponService.LoadoutOf(player: Player): Types.RangeLoadout?
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return nil
	end
	return loadoutPayload(Tuning.Get(), shooter)
end

-- The live root of a weapon player's living character; nil while they are down (P4), so a
-- cast is refused and a channel that follows its caster skips its ticks until they are up.
function WeaponService.RootOf(player: Player): BasePart?
	if not state.active or state.shooters[player] == nil or VitalsService.IsDown(player) then
		return nil
	end
	local _character, root = rootOf(player)
	return root
end

-- The ranged attack's origin test: a cast's camera ray must start near the caster's head.
function WeaponService.CheckAim(player: Player, origin: Vector3): boolean
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return false
	end
	local _character, root = rootOf(player)
	return root ~= nil and aimAllowed(shooter, root, origin, Tuning.Get())
end

-- Ruling 4, which InputController mirrors on the client: where an aimed ability lands. nil =
-- refused, and (L1c §8) so is ground higher above the caster's floor than their own jumps reach
-- (WallClip.GroundFloor, through GroundRule.Floor): a leap aimed over a tall wall would otherwise
-- land on its top. L2-4: the double jump counts only for a player who owns it, read from the
-- attribute UnlockService (this server) sets, never from the client.
function WeaponService.GroundPoint(
	player: Player,
	origin: Vector3,
	direction: Vector3,
	castRange: number
): Vector3?
	if not state.active or state.shooters[player] == nil or direction.Magnitude < 1e-6 then
		return nil
	end
	local _character, root, humanoid = rootOf(player)
	if root == nil or humanoid == nil then
		return nil
	end
	local params = worldParams()
	local rootPosition = root.Position
	local range = math.max(castRange, 0)
	-- 1-2: the camera ray, long enough to cover castRange from the root wherever the camera is.
	local length = range + (origin - rootPosition).Magnitude
	local unit = direction.Unit
	local result = if length > 0 then workspace:Raycast(origin, unit * length, params) else nil
	local point = if result ~= nil then result.Position else origin + unit * length
	-- 3: pulled back to castRange on the flat, keeping its height.
	local flat = Vector3.new(point.X - rootPosition.X, 0, point.Z - rootPosition.Z)
	if flat.Magnitude > range then
		local pulled = flat.Unit * range
		point = Vector3.new(rootPosition.X + pulled.X, point.Y, rootPosition.Z + pulled.Z)
	end
	-- 4: dropped onto the floor there, else level with the floor under the caster. Over a void
	-- (L2 W1 F2) that floor is the caster's feet less his own rise, so a jump off a cliff does
	-- not make ground a jump above the cliff's foot a legal target. GroundRule.Floor is the whole
	-- step, the same call InputController.groundPoint makes, and it reads the movement heights
	-- and this server's attribute itself (the second fix round's Minor 1).
	local floorY = GroundRule.Floor(
		player,
		floorBelow(root, params),
		rootPosition.Y - standingOffset(root, humanoid),
		floorUnder(point, params)
	)
	if floorY == nil then
		return nil
	end
	return Vector3.new(point.X, floorY, point.Z)
end

-- Ruling 4 step 4 alone: the floor point under `position`, or `position` itself over a void.
function WeaponService.FloorBelow(position: Vector3): Vector3
	local floorY = floorUnder(position, worldParams())
	return if floorY ~= nil then Vector3.new(position.X, floorY, position.Z) else position
end

-- L3-50: AbilityService's accepted cast (it alone knows the slot when a cast is accepted).
-- Ignored for a player without weapons and for any other slot word.
function WeaponService.NoteHeld(player: Player, slot: string): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil or (slot ~= "melee" and slot ~= "ranged") then
		return
	end
	noteHeld(shooter, if slot == "melee" then "melee" else "ranged")
end

-- The seed an ability's shots, strikes and scatters carry: a fresh server draw per cast in the
-- ability half of the range (see CONST.ABILITY_SEED_BIT). `seq` no longer enters it; the
-- signature is the P3 hook's. 0 for a player without weapons (AbilityService never casts then).
function WeaponService.SeedFor(player: Player, _seq: number): number
	local shooter = state.shooters[player]
	if shooter == nil then
		return 0
	end
	return newSeed(shooter, true)
end

-- One ability hit (AbilityStrikeSpec in Types.luau): gather → skip `exclude` → cap nearest-first
-- → damage, push, launch → chains → ONE CombatFxStrike → the cast's readout and the DPS log.
-- Returns (distinct enemies hit, chains included; kills).
function WeaponService.Strike(
	player: Player,
	family: string,
	ability: string,
	spec: Types.AbilityStrikeSpec
): (number, number)
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return 0, 0
	end
	local config = Tuning.Get()
	local variantKey = variantFor(config, shooter, family)
	local shape: Types.HitShape = spec.shape
	local origin = spec.origin
	local unit = if spec.direction.Magnitude > 1e-6 then spec.direction.Unit else DOWN
	local fx: StrikeFx = {
		shape = shape,
		origin = origin,
		direction = unit,
		size = spec.size,
		arcDegrees = spec.arcDegrees,
		width = spec.width,
		tick = spec.tick,
	}

	local candidates: { Candidate }
	if shape == "sphere" then
		candidates = sphereCandidates(config, origin, spec.size, spec.pad)
	elseif shape == "ray" then
		local reach = worldReach(origin, unit, math.max(spec.size, 0), worldParams())
		candidates = rayCandidates(config, origin, unit, reach, spec.width or 0, spec.pad)
		fx.endPoint = origin + unit * reach
	else
		-- Arcs sweep flat; a full circle needs no aim, so a vertical direction still spins.
		local heading = if shape == "arc" then flatten(unit) or Vector3.new(0, 0, -1) else unit
		local tip = origin + heading * spec.size
		-- Review round: an arc round the caster's own root (Whirlwind, Overload Sweep) reaches the
		-- crowd below an airborne caster exactly as a melee swing does.
		local reachDown = if shape == "arc"
				and spec.airReach == true
				and shooter.airborne
			then math.max(config.movement.airSwingReachDown, 0)
			else 0
		if shape == "capsule" then
			tip = spec.endPoint or tip
			-- Clients draw a capsule from origin along direction for size: name the real segment.
			local segment = tip - origin
			fx.direction = if segment.Magnitude > 1e-6 then segment.Unit else unit
			fx.size = segment.Magnitude
			fx.endPoint = tip
		else
			fx.direction = heading
			-- As melee arcs: an airborne band carries its bottom, a grounded one has none.
			if reachDown > 0 then
				fx.endPoint = origin - Vector3.new(0, reachDown, 0)
			end
		end
		candidates = areaCandidates(config, {
			shape = shape,
			origin = origin,
			heading = heading,
			range = spec.size,
			tip = tip,
			arcDegrees = spec.arcDegrees,
			width = spec.width or 0,
			pad = spec.pad,
			reachDown = reachDown,
		})
	end

	local exclude = spec.exclude
	local eligible: { Candidate } = {}
	for _, candidate in candidates do
		if exclude == nil or not exclude[candidate.id] then
			table.insert(eligible, candidate)
		end
	end
	local critMult = config.shooting.critMult
	local pull = spec.pull or 0
	-- Ruling 8, L3-6: an ability hit scales by its family's tier at the Ascension's abilityMult.
	local tally = StrikeTally.New(damageScale(player, family, true))
	-- The L1c second fix round's F4: the cap counts, and the chain seeds from, only bodies the hit
	-- landed on; a held resident is passed over (StrikePick).
	local seeds, spent = StrikePick.Seeds(
		eligible,
		if spec.cap > 0 then math.floor(spec.cap) else math.huge,
		function(candidate: Candidate): boolean
			local crit = shape == "ray" and spec.crit == true and candidate.crit
			local push: Vector3
			if pull > 0 then
				push = -outward(origin, candidate.body, unit) * pull
			elseif shape == "capsule" or shape == "ray" then
				push = (flatten(unit) or outward(origin, candidate.body, unit)) * spec.knockback
			else
				push = outward(origin, candidate.body, unit) * spec.knockback
			end
			local amount = if crit then spec.damage * critMult else spec.damage
			local _, verdict = strike(tally, player, candidate.id, amount, crit, push, spec.launch)
			return verdict ~= "held"
		end
	)
	if shape == "ray" and spent ~= nil and spent < #eligible then
		-- Cap spent: the ray visibly stops in the last enemy it went through.
		fx.endPoint = origin + unit * eligible[spent].order
	end
	local chain = spec.chain
	if chain ~= nil then
		fx.links = chainFrom(
			config,
			player,
			tally,
			seeds,
			exclude or {},
			chain,
			spec.damage,
			spec.knockback,
			spec.launch
		)
	end
	if exclude ~= nil then
		for _, hit in tally.hits do
			exclude[hit.id] = true
		end
	end
	finish(player, family, variantKey, tally, fx, nil, { id = ability, cast = spec.cast })
	return tally.enemies, tally.kills
end

-- An ability projectile on the normal projectile path (frozen, announced, stepped). Refused when
-- the projectile budget cannot hold its whole volley, or when it could never move (it would
-- hang until it expired, never detonating).
function WeaponService.FireProjectile(
	player: Player,
	family: string,
	ability: string,
	cast: number,
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	direction: Vector3,
	seed: number,
	onImpact: ((point: Vector3) -> ())?
): boolean
	local shooter = state.shooters[player]
	if not state.active or shooter == nil or direction.Magnitude < 1e-6 then
		return false
	end
	if (variant.projectileSpeed or 0) <= 0 then
		return false
	end
	if projectileCount() + volleySize(variant) > CONST.MAX_PROJECTILES then
		return false
	end
	local config = Tuning.Get()
	local variantKey = variantFor(config, shooter, family)
	spawnShot(
		shooter,
		family,
		variantKey,
		variant,
		origin,
		direction.Unit,
		seed,
		1,
		1,
		damageScale(player, family, true),
		false,
		{ id = ability, cast = cast },
		onImpact
	)
	return true
end

-- nil clears the slot's buff; an expired one lapses on its own.
function WeaponService.SetAttackBuff(
	player: Player,
	slot: "melee" | "ranged",
	buff: { rateMult: number, pierce: number, untilClock: number }?
): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return
	end
	if buff == nil then
		shooter.buffs[slot] = nil
		return
	end
	-- A copy: the caller's table can never change a buff behind the server's back.
	shooter.buffs[slot] =
		{ rateMult = buff.rateMult, pierce = buff.pierce, untilClock = buff.untilClock }
end

-- Replaces any lock; an untilClock already past clears it.
function WeaponService.SetAbilityLock(
	player: Player,
	untilClock: number,
	allow: ("melee" | "ranged")?
): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil then
		return
	end
	shooter.lockUntil = untilClock
	shooter.lockAllow = allow
end

function WeaponService.GrantIframes(player: Player, seconds: number): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil or not (seconds > 0 and seconds < math.huge) then
		return
	end
	openIframes(shooter, os.clock(), seconds)
end

-- Fires (on its own thread) when SetFamily puts a different family in a slot.
function WeaponService.OnLoadoutChanged(
	callback: (player: Player, slot: "melee" | "ranged") -> ()
): ()
	table.insert(state.loadoutListeners, callback)
end

-- worldParams goes stale whenever a character comes or goes.
local function markWorldStale(): ()
	state.worldStale = true
end

local function watchCharacters(player: Player): ()
	if state.characterConnections[player] ~= nil then
		return
	end
	state.characterConnections[player] = {
		player.CharacterAdded:Connect(markWorldStale),
		player.CharacterRemoving:Connect(markWorldStale),
	}
	markWorldStale()
end

local function unwatchCharacters(player: Player): ()
	local connections = state.characterConnections[player]
	if connections ~= nil then
		for _, connection in connections do
			connection:Disconnect()
		end
		state.characterConnections[player] = nil
	end
	markWorldStale()
end

function WeaponService.Init(): () end

-- After Configure, in both modes: VitalsService takes the i-frame clock, and one Heartbeat steps
-- air tracking, i-frames, projectiles and the 2 Hz readouts.
function WeaponService.Start(): ()
	if not state.active or state.started then
		return
	end
	state.started = true
	-- Every player's character is in worldParams' filter, with or without weapons.
	Players.PlayerAdded:Connect(watchCharacters)
	Players.PlayerRemoving:Connect(unwatchCharacters)
	for _, player in Players:GetPlayers() do
		watchCharacters(player)
	end
	Tuning.Changed:Connect(onTuningChanged)
	VitalsService.Start({
		iframeWindow = WeaponService.IframeWindow,
		grantIframes = WeaponService.GrantIframes,
	})
	RunService.Heartbeat:Connect(step)
end

return WeaponService
