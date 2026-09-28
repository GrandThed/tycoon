--!strict
-- Range abilities (docs/INTERFACES.md "P3 contracts", docs/WEAPONS.md §2): one per weapon
-- family; Q casts the melee slot's ability and E the ranged slot's. This service owns the cast
-- pipeline, the cooldown clocks and kill refunds, the busy lock and every ability's timeline.
-- RangeService owns the hits (Strike, FireProjectile) and the attack modifiers (buff, lock,
-- i-frames), so an ability hit resolves exactly like a weapon hit.
--
-- Server-authoritative like every range attack: the client sends only the slot, a seq and its
-- camera ray. The server checks the ray's origin, its own cooldowns and busy window, and builds
-- every shape from its own root, ground point and numbers. A cast freezes its ability def, so a
-- slider moved mid-cast applies to the next cast. Every timeline runs on this service's own
-- Heartbeat, and nothing here yields.
--
-- Inert off the range: Start connects nothing unless RangeService.IsActive(), and every entry
-- point returns at once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local CrowdService = require(script.Parent:WaitForChild("CrowdService"))
local RangeService = require(script.Parent:WaitForChild("RangeService"))

type SlotName = "melee" | "ranged"
type AbilityDef = Types.RangeAbilityDef
type StrikeSpec = Types.AbilityStrikeSpec

-- Contract: refund-driven RangeAbility sends are coalesced to at most 4 Hz.
local STATE_INTERVAL_SECONDS = 0.25
-- Lasting abilities a player may have running at once. With cooldowns off (cooldownScale 0) a
-- zone could otherwise be stacked every rate-limit tick; a cast past this is refused.
local MAX_TIMELINES_PER_PLAYER = 8
-- A tuned count past this is clamped: it bounds one cast's strikes (ticks, rings, slugs, slices,
-- bomblets) so a slider can never queue an unbounded timeline.
local MAX_STRIKES_PER_CAST = 120
-- Floor on a lasting ability's tick spacing: a tick tuned to 0 would otherwise mean infinitely
-- many ticks over its duration.
local MIN_TICK_SECONDS = 0.05
-- Float slack in duration / tick, so an exact multiple (2.4 s at 0.3 s) does not gain a ninth
-- tick from rounding.
local TICK_EPSILON = 1e-6
-- A shell always bursts within shooting.projectileMaxSeconds; this covers the frame order between
-- RangeService's step and ours. A shell dropped without a burst (a set reload) ends here.
local IMPACT_WAIT_SLACK_SECONDS = 1
local FULL_CIRCLE_DEGREES = 360
local EPSILON = 1e-4
local UP = Vector3.yAxis
local FORWARD = Vector3.new(0, 0, -1)

-- On os.clock(). readyAt = castable again; floorAt = cast + the cooldown floor, the earliest
-- readyAt kill refunds can reach.
type SlotClock = { readyAt: number, floorAt: number }

-- One cast's scheduled strikes. `times` are offsets from startedAt (ascending); events fire in
-- order as they fall due, and the timeline is dropped once every event has fired and endsAt has
-- passed (endsAt also bounds the lasting visual a cancel has to stop).
type Timeline = {
	slot: SlotName,
	-- The cast broadcast, sent again with cancel = true if the timeline is cut short.
	fx: Types.CombatFxCast,
	startedAt: number,
	times: { number },
	nextIndex: number,
	endsAt: number,
	-- Set when the timeline leaves its list for any reason, so a late projectile hook is inert.
	ended: boolean,
	fire: (index: number) -> (),
}

type Caster = {
	player: Player,
	melee: SlotClock,
	ranged: SlotClock,
	-- os.clock() until which the caster is locked in an ability (the table's "busy" column).
	busyUntil: number,
	-- The slot whose ability set the latest RangeService lock / attack buff.
	lockSlot: SlotName?,
	buffSlot: SlotName?,
	-- Replay guard: seq must increase per player across both slots.
	lastSeq: number,
	timelines: { Timeline },
	-- A kill refund moved a clock the client has not been told about yet.
	dirty: boolean,
	lastStateAt: number,
}

-- Everything one accepted cast resolved, frozen for its timeline.
type Cast = {
	player: Player,
	caster: Caster,
	slot: SlotName,
	family: string,
	id: string,
	def: AbilityDef,
	config: Types.ProvingGroundsConfig,
	cast: number,
	seed: number,
	now: number,
	rootPosition: Vector3,
	-- The validated camera origin and the unit camera aim; flatAim is its horizontal heading.
	origin: Vector3,
	aim: Vector3,
	flatAim: Vector3,
	-- The ground point (zones, leap), the dash end or the floor under the root (earthquake); the
	-- root position for everything else.
	target: Vector3,
}

-- "ground" = RangeService.GroundPoint at castRange; "dash" = the Impale Dash end; "floor" = the
-- floor under the root, sent so clients centre the Earthquake rings without their own raycast.
type TargetKind = "ground" | "dash" | "floor"
type Mechanic = {
	target: TargetKind?,
	busy: (def: AbilityDef) -> number,
	-- Mag Dump: while busy, the ability's own slot keeps attacking (its bullets are the ability).
	allowOwnSlot: boolean?,
	-- Fills the timeline and starts any side effects. false = FireProjectile refused the shot.
	launch: (cast: Cast, timeline: Timeline) -> boolean,
}

local casters: { [Player]: Caster } = {}
local castersByUserId: { [number]: Caster } = {}
-- Strictly increasing across every player: the `cast` every strike and readout keys on.
local lastCastId = 0
local started = false

local AbilityService = {}

-- Helpers ------------------------------------------------------------------------------------

-- A tuned field, or `fallback` when it is absent or not a finite number.
local function numberOr(value: number?, fallback: number): number
	if value == nil or value ~= value or math.abs(value) == math.huge then
		return fallback
	end
	return value
end

local function nonNegative(value: number?, fallback: number?): number
	return math.max(numberOr(value, fallback or 0), 0)
end

local function countOf(value: number?, minimum: number): number
	return math.clamp(math.floor(nonNegative(value)), minimum, MAX_STRIKES_PER_CAST)
end

local function isFiniteVector(vector: Vector3): boolean
	-- NaN fails every comparison, so these also reject it.
	return math.abs(vector.X) < math.huge
		and math.abs(vector.Y) < math.huge
		and math.abs(vector.Z) < math.huge
end

local function flatten(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < EPSILON then
		return nil
	end
	return flat.Unit
end

-- Mirrors RangeService: crowd dummies have no Instances, so world queries only skip players.
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

-- Impale Dash's end: along the flat aim at chest (root) height for `range`, stopping
-- `clearance` studs short of any wall so the character never ends inside it.
local function dashEnd(from: Vector3, heading: Vector3, range: number, clearance: number): Vector3
	if range <= 0 then
		return from
	end
	local result = workspace:Raycast(from, heading * range, worldParams())
	if result == nil then
		return from + heading * range
	end
	local distance = math.max(0, (result.Position - from).Magnitude - clearance)
	return from + heading * distance
end

local function muzzleOf(player: Player, root: BasePart): Vector3
	local character = player.Character
	local head = if character ~= nil then character:FindFirstChild("Head") else nil
	return if head ~= nil and head:IsA("BasePart") then head.Position else root.Position
end

-- Same delivery as RangeService.broadcastFx: one-entry batches to every player.
local function broadcastFx(fx: Types.CombatFx): ()
	local batch: { Types.CombatFx } = { fx }
	for _, player in Players:GetPlayers() do
		RemoteService.FireClient(player, "CombatFx", batch)
	end
end

local function broadcastCancel(timeline: Timeline): ()
	local fx = table.clone(timeline.fx)
	fx.cancel = true
	broadcastFx(fx)
end

local function clockOf(caster: Caster, slot: SlotName): SlotClock
	return if slot == "melee" then caster.melee else caster.ranged
end

local function familyOf(loadout: Types.RangeLoadout, slot: SlotName): string
	return if slot == "melee" then loadout.melee else loadout.ranged
end

local function abilityOf(config: Types.ProvingGroundsConfig, family: string): AbilityDef?
	local def = config.weapons[family]
	return if def ~= nil then def.ability else nil
end

local function cooldownScaleOf(config: Types.ProvingGroundsConfig): number
	return nonNegative(config.abilities.cooldownScale, 1)
end

-- State ----------------------------------------------------------------------------------------

local function slotStateOf(
	config: Types.ProvingGroundsConfig,
	loadout: Types.RangeLoadout,
	caster: Caster,
	slot: SlotName,
	clockNow: number,
	serverNow: number
): Types.RangeAbilitySlotState
	local def = abilityOf(config, familyOf(loadout, slot))
	local clock = clockOf(caster, slot)
	return {
		ability = if def ~= nil then def.id else "",
		readyAt = serverNow + clock.readyAt - clockNow,
		floorAt = serverNow + clock.floorAt - clockNow,
	}
end

-- The caster's clocks, moved from os.clock() onto workspace:GetServerTimeNow() so the client can
-- compare them with its own synced clock. refusedSeq is set only when answering a refused cast.
local function sendState(caster: Caster, refusedSeq: number?): ()
	local loadout = RangeService.LoadoutOf(caster.player)
	if loadout == nil then
		-- RangeService has not taken the player yet: the Heartbeat retries while dirty.
		caster.dirty = true
		return
	end
	local config = Tuning.Get()
	local clockNow = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local state: Types.RangeAbilityState = {
		melee = slotStateOf(config, loadout, caster, "melee", clockNow, serverNow),
		ranged = slotStateOf(config, loadout, caster, "ranged", clockNow, serverNow),
		busyUntil = serverNow + caster.busyUntil - clockNow,
		refusedSeq = refusedSeq,
	}
	RemoteService.FireClient(caster.player, "RangeAbility", state)
	caster.dirty = false
	caster.lastStateAt = clockNow
end

local function casterFor(player: Player): Caster
	local existing = casters[player]
	if existing ~= nil then
		return existing
	end
	local now = os.clock()
	local caster: Caster = {
		player = player,
		melee = { readyAt = now, floorAt = now },
		ranged = { readyAt = now, floorAt = now },
		busyUntil = now,
		lockSlot = nil,
		buffSlot = nil,
		lastSeq = -1,
		timelines = {},
		dirty = true,
		lastStateAt = -math.huge,
	}
	casters[player] = caster
	castersByUserId[player.UserId] = caster
	return caster
end

local function dropCaster(caster: Caster): ()
	for _, timeline in caster.timelines do
		timeline.ended = true
	end
	caster.timelines = {}
	casters[caster.player] = nil
	if castersByUserId[caster.player.UserId] == caster then
		castersByUserId[caster.player.UserId] = nil
	end
end

-- Strikes ----------------------------------------------------------------------------------------

-- The fields every ability strike takes from its def; callers set the shape-specific rest.
local function newSpec(
	c: Cast,
	shape: Types.HitShape,
	origin: Vector3,
	direction: Vector3,
	size: number
): StrikeSpec
	local def = c.def
	return {
		shape = shape,
		origin = origin,
		direction = direction,
		size = size,
		pad = nonNegative(def.pad),
		cap = math.floor(nonNegative(def.cap)),
		damage = nonNegative(def.damage),
		knockback = nonNegative(def.knockback),
		launch = nonNegative(def.launch),
		cast = c.cast,
	}
end

local function strike(c: Cast, spec: StrikeSpec): ()
	RangeService.Strike(c.player, c.family, c.id, spec)
end

-- A lasting ability's ticks: every `tick` seconds from `start` for `duration` (half-open, so a
-- 2.4 s channel at 0.3 s ticks 8 times), always at least once.
local function repeatTimes(start: number, duration: number, tick: number): { number }
	local interval = math.max(tick, MIN_TICK_SECONDS)
	local count = math.clamp(math.ceil(duration / interval - TICK_EPSILON), 1, MAX_STRIKES_PER_CAST)
	local times: { number } = {}
	for index = 0, count - 1 do
		table.insert(times, start + index * interval)
	end
	return times
end

-- Every timeline's handler until its launch sets one. A timeline with no events (Volley, Mag
-- Dump, a shell still in flight) never calls it.
local function idle(_index: number): () end

-- Mechanics (one per row of the INTERFACES ability table) -----------------------------------------

local function launchWhirlwind(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local duration = nonNegative(def.durationSeconds)
	local range = nonNegative(def.range)
	timeline.times = repeatTimes(0, duration, nonNegative(def.tickSeconds))
	timeline.endsAt = c.now + duration
	timeline.fire = function(_index: number)
		-- The channel follows the caster: every tick spins around the root where it is now.
		local root = RangeService.RootOf(c.player)
		if root == nil then
			return
		end
		local spec = newSpec(c, "arc", root.Position, c.flatAim, range)
		spec.arcDegrees = FULL_CIRCLE_DEGREES
		spec.tick = true
		-- Spun in the air, it reaches the crowd below like a melee swing.
		spec.airReach = true
		strike(c, spec)
	end
	return true
end

local function launchEarthquake(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local center = c.target
	local delay = nonNegative(def.delaySeconds)
	local tick = nonNegative(def.tickSeconds)
	local radius = nonNegative(def.radius)
	local spacing = numberOr(def.spacing, 0)
	local falloff = nonNegative(def.falloff, 1)
	local count = countOf(def.count, 0)
	for ring = 1, count do
		table.insert(timeline.times, delay + (ring - 1) * tick)
	end
	timeline.endsAt = c.now + delay + math.max(count - 1, 0) * tick
	timeline.fire = function(ring: number)
		-- Rings share no exclude: an enemy near the centre is inside every ring and takes each.
		local spec =
			newSpec(c, "sphere", center, c.flatAim, math.max(radius + (ring - 1) * spacing, 0))
		spec.damage *= falloff ^ (ring - 1)
		strike(c, spec)
	end
	return true
end

-- Blade Storm and Arrow Rain: a vertical capsule from the ground point up `radius` studs with
-- radius `radius` (ruling 7), ticking from delaySeconds for durationSeconds.
local function launchZone(c: Cast, timeline: Timeline, pull: number?): boolean
	local def = c.def
	local radius = nonNegative(def.radius)
	local delay = nonNegative(def.delaySeconds)
	local duration = nonNegative(def.durationSeconds)
	local ground = c.target
	local top = ground + UP * radius
	timeline.times = repeatTimes(delay, duration, nonNegative(def.tickSeconds))
	timeline.endsAt = c.now + delay + duration
	timeline.fire = function(_index: number)
		local spec = newSpec(c, "capsule", ground, UP, radius)
		spec.endPoint = top
		spec.width = radius * 2
		spec.tick = true
		-- A pulling zone draws the crowd in; with pull 0 it knocks back like any other.
		if pull ~= nil and pull > 0 then
			spec.pull = pull
			spec.knockback = 0
		end
		strike(c, spec)
	end
	return true
end

local function launchBladeStorm(c: Cast, timeline: Timeline): boolean
	return launchZone(c, timeline, nonNegative(c.def.pull))
end

local function launchArrowRain(c: Cast, timeline: Timeline): boolean
	return launchZone(c, timeline, nil)
end

-- Ruling 5: the client flies the leap; the landing hits where the SERVER resolved the ground.
local function launchLeapSmash(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local delay = nonNegative(def.delaySeconds)
	local radius = nonNegative(def.radius)
	RangeService.GrantIframes(c.player, delay)
	timeline.times = { delay }
	timeline.endsAt = c.now + delay
	timeline.fire = function(_index: number)
		strike(c, newSpec(c, "sphere", c.target, c.flatAim, radius))
	end
	return true
end

-- Ruling 5: the capsule runs from the server root at the cast to the server's dash end, at once;
-- the timeline lasts the dash so a family switch can still cancel its visual.
local function launchImpaleDash(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local delay = nonNegative(def.delaySeconds)
	local width = nonNegative(def.width)
	local from = c.rootPosition
	local to = c.target
	RangeService.GrantIframes(c.player, delay)
	timeline.times = { 0 }
	timeline.endsAt = c.now + delay
	timeline.fire = function(_index: number)
		local spec = newSpec(c, "capsule", from, c.flatAim, (to - from).Magnitude)
		spec.endPoint = to
		spec.width = width
		strike(c, spec)
	end
	return true
end

-- One split arrow on the normal projectile path, so it shares the P2 volley rules (one cap, no
-- double hits, pierce = total per arrow).
local function launchVolley(c: Cast, _timeline: Timeline): boolean
	local def = c.def
	local variant: Types.RangeWeaponVariant = {
		label = def.name,
		kind = "ranged",
		shape = "ray",
		range = nonNegative(def.range),
		width = nonNegative(def.width),
		pad = nonNegative(def.pad),
		cap = math.floor(nonNegative(def.cap)),
		damage = nonNegative(def.damage),
		-- The projectile path never reads rate; the type requires one.
		rate = 1,
		knockback = nonNegative(def.knockback),
		launch = nonNegative(def.launch),
		pierce = nonNegative(def.pierce),
		projectileSpeed = nonNegative(def.speed),
		gravity = nonNegative(def.gravity),
		splitCount = math.clamp(math.floor(nonNegative(def.count)), 1, HitShapes.MAX_FAN),
		splitDistance = nonNegative(def.spacing),
		splitArcDegrees = nonNegative(def.arcDegrees),
	}
	return RangeService.FireProjectile(
		c.player,
		c.family,
		c.id,
		c.cast,
		variant,
		c.origin,
		c.aim,
		c.seed,
		nil
	)
end

local function launchSlugBurst(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local count = countOf(def.count, 0)
	local tick = nonNegative(def.tickSeconds)
	local range = nonNegative(def.range)
	local arcDegrees = nonNegative(def.arcDegrees)
	for slug = 1, count do
		table.insert(timeline.times, (slug - 1) * tick)
	end
	timeline.endsAt = c.now + count * tick
	timeline.fire = function(_index: number)
		-- Each slug leaves the head where it is now, but keeps the aim of the cast.
		local root = RangeService.RootOf(c.player)
		if root == nil then
			return
		end
		local spec = newSpec(c, "cone", muzzleOf(c.player, root), c.aim, range)
		spec.arcDegrees = arcDegrees
		strike(c, spec)
	end
	return true
end

local function launchOverchargedShot(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local delay = nonNegative(def.delaySeconds)
	local range = nonNegative(def.range)
	local width = nonNegative(def.width)
	timeline.times = { delay }
	timeline.endsAt = c.now + delay
	timeline.fire = function(_index: number)
		-- From where the camera was at the cast; Strike stops the ray at the first wall.
		local spec = newSpec(c, "ray", c.origin, c.aim, range)
		spec.width = width
		-- Pierce is the def's cap (0 = everything in the line); a head in the line crits
		-- (shooting.critMult).
		spec.crit = true
		strike(c, spec)
	end
	return true
end

local function launchMagDump(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local duration = nonNegative(def.durationSeconds)
	RangeService.SetAttackBuff(c.player, c.slot, {
		rateMult = nonNegative(def.rateMult, 1),
		pierce = nonNegative(def.pierce, 1),
		untilClock = c.now + duration,
	})
	c.caster.buffSlot = c.slot
	timeline.endsAt = c.now + duration
	return true
end

-- The shell bursts through RangeService (radius, damage); its hook scatters the bomblets, which
-- this timeline detonates delaySeconds later. Until the hook runs the timeline waits with no
-- events, so a family switch can still cancel the bomblets.
local function launchClusterShell(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local delay = nonNegative(def.delaySeconds)
	local count = countOf(def.count, 0)
	local spacing = nonNegative(def.spacing)
	local blastRadius = nonNegative(def.blastRadius)
	local blastDamage = nonNegative(def.damage) * nonNegative(def.blastDamageMult)
	local variant: Types.RangeWeaponVariant = {
		label = def.name,
		kind = "ranged",
		shape = "sphere",
		range = nonNegative(def.range),
		pad = nonNegative(def.pad),
		cap = math.floor(nonNegative(def.cap)),
		damage = nonNegative(def.damage),
		-- The projectile path never reads rate; the type requires one.
		rate = 1,
		knockback = nonNegative(def.knockback),
		launch = nonNegative(def.launch),
		projectileSpeed = nonNegative(def.speed),
		gravity = nonNegative(def.gravity),
		splashRadius = nonNegative(def.radius),
	}
	local bomblets: { Vector3 } = {}
	timeline.endsAt = c.now
		+ nonNegative(c.config.shooting.projectileMaxSeconds)
		+ IMPACT_WAIT_SLACK_SECONDS
	timeline.fire = function(_index: number)
		for _, point in bomblets do
			local spec = newSpec(c, "sphere", point, c.aim, blastRadius)
			spec.damage = blastDamage
			strike(c, spec)
		end
	end
	-- Runs inside RangeService's step: it only records the burst, never strikes or yields.
	local function onImpact(point: Vector3): ()
		if timeline.ended or #timeline.times > 0 then
			return
		end
		-- Same pattern every client draws from CombatFxCast.seq.
		bomblets = HitShapes.Scatter(point, count, spacing, c.seed)
		local offset = os.clock() - c.now + delay
		timeline.times = { offset }
		timeline.endsAt = c.now + offset
	end
	return RangeService.FireProjectile(
		c.player,
		c.family,
		c.id,
		c.cast,
		variant,
		c.origin,
		c.aim,
		c.seed,
		onImpact
	)
end

-- Slices sweep left to right across arcDegrees centred on the flat aim, each from the root where
-- it is now; one exclude set spans the sweep, so each enemy is hit once.
local function launchOverloadSweep(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local duration = nonNegative(def.durationSeconds)
	local count = countOf(def.count, 1)
	local arcDegrees = nonNegative(def.arcDegrees)
	local range = nonNegative(def.range)
	local slice = arcDegrees / count
	local exclude: { [number]: boolean } = {}
	for index = 1, count do
		table.insert(timeline.times, (index - 1) * duration / count)
	end
	timeline.endsAt = c.now + duration
	timeline.fire = function(index: number)
		local root = RangeService.RootOf(c.player)
		if root == nil then
			return
		end
		-- A positive turn about +Y swings -Z toward -X, the caster's left: start there.
		local turn = math.rad(arcDegrees / 2 - (index - 0.5) * slice)
		local forward = CFrame.Angles(0, turn, 0):VectorToWorldSpace(c.flatAim)
		local spec = newSpec(c, "arc", root.Position, forward, range)
		spec.arcDegrees = slice
		spec.exclude = exclude
		spec.tick = true
		spec.airReach = true
		strike(c, spec)
	end
	return true
end

local function launchStormCoil(c: Cast, timeline: Timeline): boolean
	local def = c.def
	local delay = nonNegative(def.delaySeconds)
	local duration = nonNegative(def.durationSeconds)
	local radius = nonNegative(def.radius)
	local coil = c.target
	local chain = {
		count = math.floor(nonNegative(def.count)),
		radius = nonNegative(def.spacing),
		falloff = nonNegative(def.falloff, 1),
	}
	-- At least one zap per tick: 0 would read as "no cap" and zap the whole zone.
	local targets = math.max(math.floor(nonNegative(def.targets)), 1)
	timeline.times = repeatTimes(delay, duration, nonNegative(def.tickSeconds))
	timeline.endsAt = c.now + delay + duration
	timeline.fire = function(_index: number)
		-- The `targets` nearest enemies are zapped, and each starts its own chain.
		local spec = newSpec(c, "sphere", coil, c.flatAim, radius)
		spec.cap = targets
		spec.chain = chain
		spec.tick = true
		strike(c, spec)
	end
	return true
end

local function noBusy(_def: AbilityDef): number
	return 0
end

local function busyForDuration(def: AbilityDef): number
	return nonNegative(def.durationSeconds)
end

local function busyForDelay(def: AbilityDef): number
	return nonNegative(def.delaySeconds)
end

local function busyForBurst(def: AbilityDef): number
	return countOf(def.count, 0) * nonNegative(def.tickSeconds)
end

-- Keyed by RangeAbilityDef.id (structural, so tuning can never point a family at a missing row).
local MECHANICS: { [string]: Mechanic } = {
	whirlwind = { busy = busyForDuration, launch = launchWhirlwind },
	earthquake = { target = "floor", busy = busyForDelay, launch = launchEarthquake },
	bladeStorm = { target = "ground", busy = noBusy, launch = launchBladeStorm },
	leapSmash = { target = "ground", busy = busyForDelay, launch = launchLeapSmash },
	impaleDash = { target = "dash", busy = busyForDelay, launch = launchImpaleDash },
	arrowRain = { target = "ground", busy = noBusy, launch = launchArrowRain },
	volley = { busy = noBusy, launch = launchVolley },
	slugBurst = { busy = busyForBurst, launch = launchSlugBurst },
	overchargedShot = { busy = busyForDelay, launch = launchOverchargedShot },
	magDump = { busy = busyForDuration, allowOwnSlot = true, launch = launchMagDump },
	clusterShell = { busy = noBusy, launch = launchClusterShell },
	overloadSweep = { busy = busyForDuration, launch = launchOverloadSweep },
	stormCoil = { target = "ground", busy = noBusy, launch = launchStormCoil },
}

-- Timelines ----------------------------------------------------------------------------------------

-- Fires every event of `timeline` due by `now`, in order; false once it has nothing left to do
-- or an event failed.
local function advance(timeline: Timeline, now: number): boolean
	while true do
		local offset = timeline.times[timeline.nextIndex]
		if offset == nil or timeline.startedAt + offset > now then
			break
		end
		local index = timeline.nextIndex
		timeline.nextIndex += 1
		-- One broken ability must not stop every other caster's timelines this frame: log it,
		-- drop it, and stop its lasting visual.
		-- The wrapper's return slot carries the error message on failure (typed for the solver).
		local ok, message = pcall(function(): any?
			timeline.fire(index)
			return nil
		end)
		if not ok then
			warn(`[AbilityService] {timeline.fx.ability} timeline failed: {message}`)
			timeline.ended = true
			broadcastCancel(timeline)
			return false
		end
	end
	return timeline.nextIndex <= #timeline.times or now < timeline.endsAt
end

local function step(): ()
	local now = os.clock()
	for player, caster in casters do
		if player.Parent == nil then
			dropCaster(caster)
			continue
		end
		if #caster.timelines > 0 then
			local running: { Timeline } = {}
			for _, timeline in caster.timelines do
				if advance(timeline, now) then
					table.insert(running, timeline)
				else
					timeline.ended = true
				end
			end
			caster.timelines = running
		end
		if caster.dirty and now - caster.lastStateAt >= STATE_INTERVAL_SECONDS then
			sendState(caster)
		end
	end
end

-- One slot's share of a kill: the CURRENT ability's killRefundSeconds off its remaining cooldown,
-- never below the slot's floor.
local function refundSlot(
	caster: Caster,
	config: Types.ProvingGroundsConfig,
	loadout: Types.RangeLoadout,
	slot: SlotName,
	now: number
): ()
	local def = abilityOf(config, familyOf(loadout, slot))
	local clock = clockOf(caster, slot)
	if def == nil or clock.readyAt <= now then
		return
	end
	local refund = nonNegative(def.killRefundSeconds) * cooldownScaleOf(config)
	local refunded = math.max(clock.floorAt, clock.readyAt - refund)
	if refunded < clock.readyAt then
		clock.readyAt = refunded
		caster.dirty = true
	end
end

-- Ruling 2: every kill by the caster, from any source including abilities, refunds BOTH slots.
-- The state goes out coalesced from the Heartbeat.
local function onKilled(_id: number, byUserId: number): ()
	local caster = castersByUserId[byUserId]
	if caster == nil then
		return
	end
	local loadout = RangeService.LoadoutOf(caster.player)
	if loadout == nil then
		return
	end
	local config = Tuning.Get()
	local now = os.clock()
	refundSlot(caster, config, loadout, "melee", now)
	refundSlot(caster, config, loadout, "ranged", now)
end

-- Ruling 2: a new family in a slot cancels that slot's running ability (and any lock or buff it
-- holds) and makes the new ability ready at once.
local function onLoadoutChanged(player: Player, slot: SlotName): ()
	local caster = casters[player]
	if caster == nil then
		return
	end
	local now = os.clock()
	local kept: { Timeline } = {}
	for _, timeline in caster.timelines do
		if timeline.slot == slot then
			timeline.ended = true
			broadcastCancel(timeline)
		else
			table.insert(kept, timeline)
		end
	end
	caster.timelines = kept
	if caster.lockSlot == slot then
		caster.lockSlot = nil
		caster.busyUntil = math.min(caster.busyUntil, now)
		-- An expired lock is a no-op: this clears it.
		RangeService.SetAbilityLock(player, 0, nil)
	end
	if caster.buffSlot == slot then
		caster.buffSlot = nil
		RangeService.SetAttackBuff(player, slot, nil)
	end
	local clock = clockOf(caster, slot)
	clock.readyAt = now
	clock.floorAt = now
	sendState(caster)
end

-- Public -------------------------------------------------------------------------------------------

function AbilityService.Init(): () end

-- After RangeService.Start. Only when the range booted.
function AbilityService.Start(): ()
	if started or not RangeService.IsActive() then
		return
	end
	started = true
	CrowdService.OnKilled(onKilled)
	RangeService.OnLoadoutChanged(onLoadoutChanged)
	RunService.Heartbeat:Connect(step)
end

-- Sends the first RangeAbility state (or, if RangeService has not taken the player yet, the
-- Heartbeat sends it as soon as it has).
function AbilityService.AddPlayer(player: Player): ()
	if not RangeService.IsActive() or player.Parent == nil then
		return
	end
	sendState(casterFor(player))
end

-- Drops the player's timelines without any fx.
function AbilityService.RemovePlayer(player: Player): ()
	local caster = casters[player]
	if caster ~= nil then
		dropCaster(caster)
	end
end

-- RequestRangeAbility. Checks in contract order: range player and slot, seq, ability, busy,
-- ready, aim and root. Any refusal resends the caster's state so the buttons resync.
function AbilityService.OnCast(
	player: Player,
	slot: string,
	seq: number,
	origin: Vector3,
	direction: Vector3
): ()
	if not RangeService.IsActive() or player.Parent == nil then
		return
	end
	local loadout = RangeService.LoadoutOf(player)
	if loadout == nil then
		return
	end
	local caster = casterFor(player)
	-- The seq a refusal names, so the client cancels that cast's local effects at once. A replayed
	-- or malformed seq names nothing: it could match a cast the server already accepted.
	local refused: number? = if typeof(seq) == "number"
			and seq == math.floor(seq)
			and math.abs(seq) < math.huge
			and seq > caster.lastSeq
		then seq
		else nil
	if slot ~= "melee" and slot ~= "ranged" then
		sendState(caster, refused)
		return
	end
	local slotName: SlotName = if slot == "melee" then "melee" else "ranged"
	-- CombatRemotes checked the payload's types; a NaN or infinite value would still poison every
	-- shape and seed downstream. A refusal never moves the replay guard.
	local validPayload = refused ~= nil
		and isFiniteVector(origin)
		and isFiniteVector(direction)
		and direction.Magnitude > EPSILON
	if not validPayload then
		sendState(caster, refused)
		return
	end
	local config = Tuning.Get()
	local family = familyOf(loadout, slotName)
	local base = abilityOf(config, family)
	local mechanic = if base ~= nil then MECHANICS[base.id] else nil
	if base == nil or mechanic == nil then
		if base ~= nil then
			warn(`[AbilityService] {family}: no mechanic for ability "{base.id}"`)
		end
		sendState(caster, refused)
		return
	end
	local now = os.clock()
	local clock = clockOf(caster, slotName)
	if
		-- busyEarlySeconds: the client mirrors busyUntil through GetServerTimeNow, whose sync
		-- error is a few tens of milliseconds.
		now < caster.busyUntil - nonNegative(config.abilities.busyEarlySeconds)
		or now < clock.readyAt - nonNegative(config.abilities.earlySeconds)
	then
		sendState(caster, refused)
		return
	end
	local root = RangeService.RootOf(player)
	if
		root == nil
		or not RangeService.CheckAim(player, origin)
		or #caster.timelines >= MAX_TIMELINES_PER_PLAYER
	then
		sendState(caster, refused)
		return
	end

	local def = table.clone(base)
	local aim = direction.Unit
	local flatAim = flatten(aim) or flatten(root.CFrame.LookVector) or FORWARD
	local rootPosition = root.Position
	local target = rootPosition
	if mechanic.target == "ground" then
		local ground = RangeService.GroundPoint(player, origin, aim, nonNegative(def.castRange))
		if ground == nil then
			sendState(caster, refused)
			return
		end
		target = ground
	elseif mechanic.target == "dash" then
		target = dashEnd(
			rootPosition,
			flatAim,
			nonNegative(def.range),
			nonNegative(config.abilities.dashWallClearance)
		)
	elseif mechanic.target == "floor" then
		target = RangeService.FloorBelow(rootPosition)
	end

	-- Accepted: the cooldown starts now, so kills from this very cast already refund it.
	local scale = cooldownScaleOf(config)
	local cooldown = nonNegative(def.cooldownSeconds) * scale
	local previous = table.clone(clock)
	clock.readyAt = now + cooldown
	clock.floorAt = now + math.min(nonNegative(def.minCooldownSeconds) * scale, cooldown)
	lastCastId += 1
	local seed = RangeService.SeedFor(player, seq)
	local fx: Types.CombatFxCast = {
		kind = "cast",
		userId = player.UserId,
		weapon = family,
		ability = def.id,
		origin = rootPosition,
		direction = if slotName == "melee" then flatAim else aim,
		target = if mechanic.target ~= nil then target else nil,
		startsAt = workspace:GetServerTimeNow(),
		seq = seed,
	}
	broadcastFx(fx)
	local timeline: Timeline = {
		slot = slotName,
		fx = fx,
		startedAt = now,
		times = {},
		nextIndex = 1,
		endsAt = now,
		ended = false,
		fire = idle,
	}
	local cast: Cast = {
		player = player,
		caster = caster,
		slot = slotName,
		family = family,
		id = def.id,
		def = def,
		config = config,
		cast = lastCastId,
		seed = seed,
		now = now,
		rootPosition = rootPosition,
		origin = origin,
		aim = aim,
		flatAim = flatAim,
		target = target,
	}
	if not mechanic.launch(cast, timeline) then
		-- Only the projectile abilities can be refused here (RangeService's projectile budget, or
		-- a speed tuned to 0), and neither is busy: give the cooldown back, take the visuals back.
		clock.readyAt = previous.readyAt
		clock.floorAt = previous.floorAt
		timeline.ended = true
		broadcastCancel(timeline)
		sendState(caster, refused)
		return
	end
	caster.lastSeq = seq
	local busy = mechanic.busy(def)
	if busy > 0 then
		caster.busyUntil = now + busy
		caster.lockSlot = slotName
		RangeService.SetAbilityLock(
			player,
			caster.busyUntil,
			if mechanic.allowOwnSlot then slotName else nil
		)
	end
	if advance(timeline, now) then
		table.insert(caster.timelines, timeline)
	else
		timeline.ended = true
	end
	sendState(caster)
end

return AbilityService
