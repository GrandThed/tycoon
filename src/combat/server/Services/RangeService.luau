--!strict
-- The Proving Grounds server (docs/INTERFACES.md "P1 contracts", docs/COMBAT_DESIGN.md §8):
-- dummy sets and respawns, the per-player weapon and variant, attack resolution against the
-- crowd, dash i-frames, the ground slam, live tuning and the readouts.
--
-- P2 (INTERFACES "P2 contracts"): weapons are families; each player holds one melee and one
-- ranged family (RangeLoadout). Bows draw (RequestRangeDraw starts the server's clock) and fire
-- real server-stepped arrows with gravity; split arrows fan after splitDistance. Every projectile
-- is announced at fire time (CombatFxShot); its damage arrives as CombatFxStrike.
--
-- Studio only and opt-in: Main calls Configure(true) when the DebugProving attribute is set at
-- boot. Otherwise every entry point here returns at once, so missions never touch this file.
--
-- The server resolves every shape itself (decision 2). Melee builds its shape from the
-- server-side root; ranged takes the camera ray only after checking it starts near the head.
-- Every number is read through Tuning.Get() at the moment it is used, so a slider applies to the
-- very next swing. Nothing in the Heartbeat step yields.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local CrowdService = require(script.Parent:WaitForChild("CrowdService"))

type SlotName = "melee" | "ranged"
type Variant = Types.RangeWeaponVariant

-- Contract: DPS is a 5 s window; readouts go out at 2 Hz. (Projectile lifetime is
-- shooting.projectileMaxSeconds.)
local DPS_WINDOW_SECONDS = 5
local STATS_INTERVAL_SECONDS = 0.5
-- Lead ruling: a group of up to this many is one row along x; larger groups are a square grid.
local ROW_MAX_COUNT = 10
-- Used when Combat.json is absent: the share of an interval a client may arrive early by
-- (network jitter), same meaning as Combat.json player.comboTimingTolerance.
local DEFAULT_TIMING_TOLERANCE = 0.8
-- A slot the crowd refuses this many times in a row (crowd.maxAlive lowered mid-set) is dropped
-- from the set instead of being retried forever.
local MAX_SPAWN_ATTEMPTS = 3
-- Pellet seeds: Park–Miller step over (seq xor a per-player salt), exact in doubles.
local SEED_MODULUS = 2147483647
local SEED_MULTIPLIER = 48271
local UINT32 = 4294967296
-- Live projectiles (arrows, split children, shells) across every player; a shot past this is
-- refused rather than let the step grow without bound.
local MAX_PROJECTILES = 256
-- How far below the root the floor probe looks (air tracking and the slam's landing point).
local GROUND_PROBE_STUDS = 250
-- Height above standing height before a character counts as airborne (steps and slopes).
local AIRBORNE_MARGIN_STUDS = 0.75
-- Server-set character attribute while dash i-frames are open, so the flag is visible in
-- Studio's Properties panel and to the client.
local IFRAMES_ATTRIBUTE = "RangeIframes"
local DOWN = Vector3.new(0, -1, 0)

type Slot = {
	kind: string,
	behaviour: string,
	position: Vector3,
	respawnSeconds: number,
	cleared: boolean,
	-- Consecutive refusals by CrowdService.Spawn.
	refusals: number,
}
type Respawn = { at: number, slot: Slot }
-- One shot's shared record: every arrow of a split volley draws on the same cap, never hits an
-- enemy another arrow of the volley already hit, and adds to the same readout totals.
type Volley = { hit: { [number]: boolean }, distinct: number, cap: number, kills: number }
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
	-- Per hit, charge already applied.
	damage: number,
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
}
type DamageEntry = { at: number, amount: number }
type Shooter = {
	player: Player,
	loadout: Types.RangeLoadout,
	-- Keyed by slot: switching family never resets the rate clock or the replay guard.
	lastSeq: { [string]: number },
	lastAttackAt: { [string]: number },
	-- Keyed by family.
	combo: { [string]: number },
	-- The bow draw clock (RequestRangeDraw); 0 = not drawing.
	drawStartedAt: number,
	drawWeapon: string,
	lastDashAt: number,
	iframesUntil: number,
	lastSlamAt: number,
	airborne: boolean,
	peakY: number,
	-- The peak of the airborne phase that ended at landedAt (for a slam request that trails it).
	lastPeakY: number,
	landedAt: number,
	-- Fastest fall the server saw in this airtime (studs/s, downward positive), and in the one
	-- that ended at landedAt.
	diveSpeed: number,
	lastDiveSpeed: number,
	-- Root Y last frame, for the fall speed measured from positions.
	lastY: number?,
	-- Server-only: mixed into every pellet seed so a client never picks its own pattern.
	salt: number,
	damageLog: { DamageEntry },
	lastHits: number,
	lastKills: number,
	connections: { RBXScriptConnection },
}
-- One enemy the shape touched. `order` sorts nearest-first (distance, or entry along a ray).
type Candidate = { id: number, order: number, body: Vector3, crit: boolean }

local isStudio = RunService:IsStudio()
local active = false
local started = false
local shooters: { [Player]: Shooter } = {}
local projectiles: { Projectile } = {}
local slotById: { [number]: Slot } = {}
local setSlots: { Slot } = {}
local respawns: { Respawn } = {}
local currentSet = ""
-- os.clock() of the first damage since the set loaded; 0 = nobody has hit it yet.
local clearStartedAt = 0
local clearSeconds: number? = nil
local statsAccumulator = 0
-- The floor's half-size (X, Z) from the arena build, so dummies stay on it.
local floorHalfSize = Vector3.zero

local RangeService = {}

local function timingTolerance(): number
	local combatConfig = Catalog.GetCombatConfig()
	return if combatConfig ~= nil
		then combatConfig.player.comboTimingTolerance
		else DEFAULT_TIMING_TOLERANCE
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

-- Crowd dummies have no Instances, so world queries only need to skip the players.
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
	local result = workspace:Raycast(root.Position, DOWN * GROUND_PROBE_STUDS, params)
	return if result ~= nil then result.Position.Y else nil
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

local function tuneStateFor(shooter: Shooter): ()
	sendTo(
		shooter.player,
		"TuneState",
		Tuning.GetOverrides(),
		loadoutPayload(Tuning.Get(), shooter)
	)
end

local function statsFor(shooter: Shooter, now: number, refused: boolean?): Types.RangeStats
	local log = shooter.damageLog
	local cutoff = now - DPS_WINDOW_SECONDS
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
	return {
		lastHits = shooter.lastHits,
		lastKills = shooter.lastKills,
		dps = total / DPS_WINDOW_SECONDS,
		clearSeconds = clearSeconds,
		alive = CrowdService.AliveCount(),
		serverFrameMs = CrowdService.StepMs(),
		refused = refused,
	}
end

local function sendStats(shooter: Shooter): ()
	RemoteService.FireClient(shooter.player, "RangeStats", statsFor(shooter, os.clock(), nil))
end

-- The attacker's client has already drawn the shot; this tells it to take it back.
local function sendRefused(shooter: Shooter): ()
	RemoteService.FireClient(shooter.player, "RangeStats", statsFor(shooter, os.clock(), true))
end

-- The seed of a gun strike's cosmetic pellets. Deterministic per (seq, salt), so the strike
-- can carry it and every client draws the same pattern with HitShapes.Pellets.
local function pelletSeed(shooter: Shooter, seq: number): number
	local mixed = bit32.bxor(math.floor(seq % UINT32), shooter.salt)
	return (mixed % (SEED_MODULUS - 1) + 1) * SEED_MULTIPLIER % SEED_MODULUS
end

local function broadcastFx(fx: Types.CombatFx): ()
	local batch: { Types.CombatFx } = { fx }
	for _, player in Players:GetPlayers() do
		RemoteService.FireClient(player, "CombatFx", batch)
	end
end

-- Dummy sets ---------------------------------------------------------------------------------

local function kindDef(config: Types.ProvingGroundsConfig, kind: string): Types.CrowdKindDef?
	return config.crowd.kinds[kind]
end

local function spawnSlot(slot: Slot): ()
	local id = CrowdService.Spawn(slot.kind, slot.position, slot.behaviour, slot.position)
	if id ~= 0 then
		slot.refusals = 0
		slotById[id] = slot
		return
	end
	-- Refused (crowd.maxAlive reached): a few retries after the group's respawn delay, then the
	-- slot leaves the set so the clear clock and the respawn queue never wait on it.
	slot.refusals += 1
	if slot.refusals >= MAX_SPAWN_ATTEMPTS then
		local index = table.find(setSlots, slot)
		if index ~= nil then
			table.remove(setSlots, index)
		end
		warn(
			`[RangeService] dropped a {slot.kind} dummy: the crowd refused it {slot.refusals} times`
		)
		return
	end
	table.insert(respawns, { at = os.clock() + math.max(slot.respawnSeconds, 1), slot = slot })
end

-- `at` is an absolute arena point (lead ruling). A small group is one row along x; a larger one
-- a packed square grid; both centred on `at` and clamped inside the floor.
local function groupPositions(
	group: Types.DummyGroupDef,
	count: number,
	radius: number
): { Vector3 }
	local positions: { Vector3 } = {}
	local limitX = math.max(0, floorHalfSize.X - radius)
	local limitZ = math.max(0, floorHalfSize.Z - radius)
	local centerX = group.at[1] or 0
	local centerZ = group.at[2] or 0
	local columns = if count <= ROW_MAX_COUNT then count else math.ceil(math.sqrt(count))
	local rows = math.ceil(count / math.max(columns, 1))
	for index = 0, count - 1 do
		local column = index % columns
		local row = index // columns
		local x = centerX + (column - (columns - 1) / 2) * group.spacing
		local z = centerZ + (row - (rows - 1) / 2) * group.spacing
		table.insert(
			positions,
			Vector3.new(math.clamp(x, -limitX, limitX), 0, math.clamp(z, -limitZ, limitZ))
		)
	end
	return positions
end

-- The first death of every slot since the set loaded ends the clear clock.
local function markCleared(slot: Slot): ()
	if slot.cleared then
		return
	end
	slot.cleared = true
	if clearSeconds ~= nil or clearStartedAt == 0 then
		return
	end
	for _, other in setSlots do
		if not other.cleared then
			return
		end
	end
	clearSeconds = os.clock() - clearStartedAt
end

local function slotGone(id: number): ()
	local slot = slotById[id]
	if slot == nil then
		return
	end
	slotById[id] = nil
	markCleared(slot)
	table.insert(respawns, { at = os.clock() + slot.respawnSeconds, slot = slot })
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
		headRadius: number
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
		local order, crit = test(body, def.radius, head, def.headRadius)
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

type Tally = { hits: { Types.StrikeHit }, kills: number, dealt: number }

local function newTally(): Tally
	return { hits = {}, kills = 0, dealt = 0 }
end

-- Every multiplier (chain, finisher, crit) is already in `amount`: CrowdService takes its flat
-- armour cut from the final number (lead ruling).
local function strike(
	tally: Tally,
	player: Player,
	id: number,
	amount: number,
	crit: boolean,
	push: Vector3?,
	launch: number
): boolean
	local dealt, killed = CrowdService.Damage(id, amount, player.UserId, push, launch)
	tally.dealt += dealt
	local existing: Types.StrikeHit? = nil
	for _, hit in tally.hits do
		if hit.id == id then
			existing = hit
			break
		end
	end
	if existing ~= nil then
		existing.amount += dealt
		existing.crit = existing.crit or crit
		existing.killed = existing.killed or killed
	else
		table.insert(tally.hits, { id = id, amount = dealt, crit = crit, killed = killed })
	end
	if killed then
		tally.kills += 1
	end
	return killed
end

local function finish(
	player: Player,
	weapon: string,
	variantKey: string,
	tally: Tally,
	fx: {
		shape: Types.HitShape,
		origin: Vector3,
		direction: Vector3,
		size: number,
		arcDegrees: number?,
		width: number?,
		endPoint: Vector3?,
		-- Gun strikes only: the attack's seq, which seeded HitShapes.Pellets.
		seq: number?,
	},
	-- A projectile's readout counts its whole volley, not just this strike.
	totals: { hits: number, kills: number }?
): ()
	local now = os.clock()
	if tally.dealt > 0 and clearStartedAt == 0 then
		clearStartedAt = now
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
		hits = tally.hits,
	})
	local shooter = shooters[player]
	if shooter == nil then
		return
	end
	shooter.lastHits = if totals ~= nil then totals.hits else #tally.hits
	shooter.lastKills = if totals ~= nil then totals.kills else tally.kills
	if tally.dealt > 0 then
		table.insert(shooter.damageLog, { at = now, amount = tally.dealt })
	end
	sendStats(shooter)
end

-- Ends every live projectile with an empty end strike (endPoint = where it is now), so clients
-- stop their flights instead of letting arrows fly on through a cleared set.
local function abandonProjectiles(): ()
	for _, projectile in projectiles do
		if projectile.player.Parent == nil then
			continue
		end
		finish(projectile.player, projectile.weapon, projectile.variantKey, newTally(), {
			shape = "ray",
			origin = projectile.position,
			direction = DOWN,
			size = 0,
			arcDegrees = nil,
			width = nil,
			endPoint = projectile.position,
			seq = projectile.seed,
		}, { hits = projectile.volley.distinct, kills = projectile.volley.kills })
	end
	projectiles = {}
end

-- `countOverride` replaces the first group's count (the stress command's crowd.stressCount).
local function loadSet(name: string, countOverride: number?): ()
	local config = Tuning.Get()
	local groups = config.dummySets[name]
	if groups == nil then
		warn(`[RangeService] no dummy set "{name}"`)
		return
	end
	CrowdService.Clear()
	slotById = {}
	setSlots = {}
	respawns = {}
	abandonProjectiles()
	currentSet = name
	clearStartedAt = 0
	clearSeconds = nil
	-- Never ask for more dummies than the crowd will hold; later groups get what is left.
	local budget = math.max(0, math.floor(config.crowd.maxAlive))
	for groupIndex, group in groups do
		local def = kindDef(config, group.kind)
		if def == nil then
			warn(`[RangeService] set {name}: unknown crowd kind "{group.kind}"`)
			continue
		end
		local count = if groupIndex == 1 and countOverride ~= nil
			then countOverride
			else group.count
		count = math.clamp(math.floor(count), 0, budget)
		budget -= count
		for _, position in groupPositions(group, count, def.radius) do
			local slot: Slot = {
				kind = group.kind,
				behaviour = group.behaviour,
				position = position,
				respawnSeconds = group.respawnSeconds,
				cleared = false,
				refusals = 0,
			}
			table.insert(setSlots, slot)
			spawnSlot(slot)
		end
	end
	print(`[RangeService] loaded set "{name}" ({#setSlots} dummies)`)
end

local function outward(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	return flatten(to - from) or flatten(fallback) or Vector3.zero
end

-- Everything in a sphere, nearest the centre first (projectile splash, the slam, ranged spheres).
-- What a blast needs beyond its centre and radius. A weapon variant carries these fields; the
-- slam builds its own from movement.*.
type Blast = { pad: number, cap: number, knockback: number, launch: number }

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
	local candidates = gather(
		config,
		center,
		radius + variant.pad,
		function(body: Vector3, r: number): (number?, boolean)
			if HitShapes.Sphere(center, radius, variant.pad, body, r) then
				return (body - center).Magnitude, false
			end
			return nil, false
		end
	)
	local limit = if variant.cap > 0 then math.min(variant.cap, #candidates) else #candidates
	for index = 1, limit do
		local candidate = candidates[index]
		local push = outward(center, candidate.body, heading) * variant.knockback
		strike(tally, player, candidate.id, damage, false, push, variant.launch)
	end
end

local function resolveMelee(
	config: Types.ProvingGroundsConfig,
	shooter: Shooter,
	weapon: string,
	variantKey: string,
	variant: Variant,
	root: BasePart,
	direction: Vector3
): ()
	local origin = root.Position
	local heading = flatten(direction) or flatten(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local chain = variant.chain
	local step = shooter.combo[weapon] or 0
	step = if chain ~= nil and #chain > 0 then step % #chain + 1 else 1
	shooter.combo[weapon] = step
	local multiplier = if chain ~= nil and chain[step] ~= nil then chain[step] else 1
	-- Lead ruling: the chain's LAST hit may sweep a different arc (360 = a spin round the root).
	local arcDegrees = variant.arcDegrees
	if chain ~= nil and step == #chain and variant.finisherArcDegrees ~= nil then
		arcDegrees = variant.finisherArcDegrees
	end
	local damage = variant.damage * multiplier
	local range = variant.range
	local pad = variant.pad
	local shape: Types.HitShape = variant.shape
	local halfWidth = (variant.width or 0) / 2
	-- Lead ruling: an airborne swing's arc reaches down to the crowd below (HitShapes.Arc band).
	local reachDown = if shooter.airborne then math.max(config.movement.airSwingReachDown, 0) else 0
	local tally = newTally()

	if shape == "sphere" then
		explode(config, shooter.player, origin, range, variant, damage, heading, tally)
	else
		local tip = origin + heading * range
		local test = function(body: Vector3, r: number): (number?, boolean)
			local touched = false
			if shape == "arc" then
				touched = HitShapes.Arc(
					origin,
					heading,
					range,
					arcDegrees or 360,
					pad,
					body,
					r,
					reachDown
				)
			elseif shape == "capsule" then
				touched = HitShapes.Capsule(origin, tip, halfWidth, pad, body, r)
			elseif shape == "cone" then
				touched =
					HitShapes.Cone(origin, heading, range, (arcDegrees or 0) / 2, pad, body, r)
			elseif shape == "ray" then
				touched = HitShapes.Ray(origin, heading, range, variant.width or 0, pad, body, r)
					~= nil
			end
			if touched then
				return (body - origin).Magnitude, false
			end
			return nil, false
		end
		local candidates = gather(config, origin, range + pad + halfWidth + reachDown, test)
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
		shape = shape,
		origin = origin,
		direction = heading,
		size = range,
		arcDegrees = arcDegrees,
		width = variant.width,
		-- An airborne arc carries the bottom of its band (origin - airSwingReachDown); nil on
		-- the ground, so a client knows which band to draw.
		endPoint = if shape == "arc" and reachDown > 0
			then origin - Vector3.new(0, reachDown, 0)
			else nil,
	})
end

-- One ray against the crowd: the enemies it touches before `reach`, entry order, crit when it
-- also passes the head sphere (unpadded: the pad forgives a miss, it does not make a headshot).
local function rayCandidates(
	config: Types.ProvingGroundsConfig,
	origin: Vector3,
	direction: Vector3,
	reach: number,
	variant: Variant
): { Candidate }
	local width = variant.width or 0
	local pad = variant.pad
	local center = origin + direction * (reach / 2)
	return gather(
		config,
		center,
		reach / 2 + pad + width / 2,
		function(body: Vector3, r: number, head: Vector3, headRadius: number): (number?, boolean)
			local entry = HitShapes.Ray(origin, direction, reach, width, pad, body, r)
			if entry == nil then
				return nil, false
			end
			return entry, HitShapes.Ray(origin, direction, reach, width, 0, head, headRadius) ~= nil
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

-- A projectile weapon's trigger pull: one record (a split parent fans later) and ONE CombatFxShot
-- to everyone, which is all a client needs to fly it: origin, direction, speed, gravity, and the
-- seq that seeds the split fan.
local function spawnShot(
	shooter: Shooter,
	weapon: string,
	variantKey: string,
	variant: Variant,
	origin: Vector3,
	direction: Vector3,
	seed: number,
	charge: number,
	scale: number,
	full: boolean
): ()
	local frozen = table.clone(variant)
	local speed = frozen.projectileSpeed or 0
	local gravity = math.max(frozen.gravity or 0, 0)
	local splitCount = volleySize(frozen)
	table.insert(projectiles, {
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
		damage = frozen.damage * scale,
		fullCharge = full,
		hitsLeft = pierceOf(frozen),
		charge = charge,
		carry = 0,
		splitting = splitCount > 1,
		volley = { hit = {}, distinct = 0, cap = frozen.cap, kills = 0 },
		seed = seed,
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
	})
end

local function resolveRanged(
	config: Types.ProvingGroundsConfig,
	shooter: Shooter,
	weapon: string,
	variantKey: string,
	variant: Variant,
	seq: number,
	origin: Vector3,
	direction: Vector3,
	charge: number,
	scale: number,
	full: boolean
): ()
	local unit = direction.Unit
	-- Pellets and fans are cosmetic seeds (lead ruling): every client draws the same ones.
	local seed = pelletSeed(shooter, seq)
	if (variant.projectileSpeed or 0) > 0 then
		spawnShot(shooter, weapon, variantKey, variant, origin, unit, seed, charge, scale, full)
		return
	end
	local critMult = config.shooting.critMult
	local params = worldParams()
	local player = shooter.player
	local tally = newTally()
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
		local candidates = rayCandidates(config, origin, unit, reach, variant)
		local limit = capOf(variant, math.min(#candidates, pierceOf(variant)))
		local endPoint = origin + unit * reach
		for index = 1, limit do
			local candidate = candidates[index]
			local amount = if candidate.crit then variant.damage * critMult else variant.damage
			strike(tally, player, candidate.id, amount, candidate.crit, pushBase, variant.launch)
			if index == limit and limit < #candidates then
				-- Pierce spent: the beam visibly stops in the last enemy it went through.
				endPoint = origin + unit * candidate.order
			end
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
	local halfWidth = (variant.width or 0) / 2
	local tip = origin + unit * reach
	local candidates = gather(
		config,
		origin,
		reach + variant.pad + halfWidth,
		function(body: Vector3, r: number): (number?, boolean)
			local touched = false
			if shape == "arc" then
				touched = HitShapes.Arc(
					origin,
					unit,
					reach,
					variant.arcDegrees or 360,
					variant.pad,
					body,
					r
				)
			elseif shape == "capsule" then
				touched = HitShapes.Capsule(origin, tip, halfWidth, variant.pad, body, r)
			end
			return (if touched then (body - origin).Magnitude else nil), false
		end
	)
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

-- Every projectile strike reports the whole volley's totals to the shooter's readout.
local function reportShot(
	projectile: Projectile,
	tally: Tally,
	fx: {
		shape: Types.HitShape,
		origin: Vector3,
		direction: Vector3,
		size: number,
		arcDegrees: number?,
		width: number?,
		endPoint: Vector3?,
		seq: number?,
	}
): ()
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
		{ hits = volley.distinct, kills = volley.kills }
	)
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
	local tally = newTally()
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
		return
	end
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
		if #projectiles + #spawned >= MAX_PROJECTILES then
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
			fullCharge = projectile.fullCharge,
			hitsLeft = pierceOf(variant),
			charge = projectile.charge,
			carry = carry,
			splitting = false,
			volley = projectile.volley,
			seed = projectile.seed,
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
			endArrow(config, projectile, from, DOWN, from, newTally())
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
		then rayCandidates(config, from, direction, wall, variant)
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
			endArrow(config, projectile, from, direction, from + direction * wall, newTally())
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
			endArrow(config, projectile, from, direction, projectile.position, newTally())
			return false
		end
		return true
	end

	-- Its siblings already filled the volley's cap: this arrow ends where it is, no ghost flight.
	if volley.cap > 0 and volley.distinct >= volley.cap then
		endArrow(config, projectile, from, direction, from, newTally())
		return false
	end
	local tally = newTally()
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
	if #projectiles == 0 then
		return
	end
	local params = worldParams()
	local survivors: { Projectile } = {}
	local spawned: { Projectile } = {}
	for _, projectile in projectiles do
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
	projectiles = survivors
end

-- Air tracking for the slam and air swings: the server's own view of how high each character
-- got and how fast it fell. Fall speed is the larger of the replicated velocity and the
-- position change, so a client that zeroes its reported velocity still shows its real dive.
local function trackAir(now: number, deltaTime: number): ()
	if next(shooters) == nil then
		return
	end
	local params = worldParams()
	for player, shooter in shooters do
		local _character, root, humanoid = rootOf(player)
		if root == nil or humanoid == nil then
			shooter.airborne = false
			shooter.lastY = nil
			continue
		end
		local floorY = floorBelow(root, params)
		local height = if floorY ~= nil then root.Position.Y - floorY else math.huge
		local airborne = height > standingOffset(root, humanoid) + AIRBORNE_MARGIN_STUDS
		local y = root.Position.Y
		local previousY = shooter.lastY
		local fallSpeed = -root.AssemblyLinearVelocity.Y
		if previousY ~= nil and deltaTime > 0 then
			fallSpeed = math.max(fallSpeed, (previousY - y) / deltaTime)
		end
		shooter.lastY = y
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

local function tickIframes(now: number): ()
	for player, shooter in shooters do
		if shooter.iframesUntil > 0 and now >= shooter.iframesUntil then
			shooter.iframesUntil = 0
			local character = player.Character
			if character ~= nil then
				character:SetAttribute(IFRAMES_ATTRIBUTE, nil)
			end
		end
	end
end

-- Kills arrive through OnKilled; this catches any enemy CrowdService dropped another way.
local function sweepSlots(): ()
	for id in table.clone(slotById) do
		if CrowdService.Get(id) == nil then
			slotGone(id)
		end
	end
end

local function tickRespawns(now: number): ()
	if #respawns == 0 then
		return
	end
	local due: { Slot } = {}
	local waiting: { Respawn } = {}
	for _, entry in respawns do
		if now >= entry.at then
			table.insert(due, entry.slot)
		else
			table.insert(waiting, entry)
		end
	end
	respawns = waiting
	for _, slot in due do
		spawnSlot(slot)
	end
end

local function step(deltaTime: number): ()
	local config = Tuning.Get()
	local now = os.clock()
	trackAir(now, deltaTime)
	tickIframes(now)
	stepProjectiles(config, deltaTime)
	tickRespawns(now)
	statsAccumulator += deltaTime
	if statsAccumulator >= STATS_INTERVAL_SECONDS then
		statsAccumulator = 0
		sweepSlots()
		for _, shooter in shooters do
			sendStats(shooter)
		end
	end
end

-- Players ------------------------------------------------------------------------------------

-- Full HP from the profile and an invisible ForceField: nothing in P1 may hurt a player.
local function prepareCharacter(player: Player, character: Model): ()
	local spawnLocation, spawnCFrame = ArenaService.ProvingSpawn()
	if spawnLocation ~= nil then
		player.RespawnLocation = spawnLocation
	end
	character:PivotTo(spawnCFrame)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		local maxHp = ArenaService.ProfileMaxHp(player)
		if maxHp ~= nil then
			humanoid.MaxHealth = maxHp
		end
		humanoid.Health = humanoid.MaxHealth
	end
	if character:FindFirstChildOfClass("ForceField") == nil then
		local shield = Instance.new("ForceField")
		shield.Visible = false
		shield.Parent = character
	end
end

-- Must be called before Init. `proving` is Main's boot decision; the range also needs Studio and
-- Config/ProvingGrounds, and stays off without either.
function RangeService.Configure(proving: boolean): ()
	if not proving then
		active = false
		return
	end
	if not isStudio then
		return
	end
	if not Tuning.IsAvailable() then
		warn(
			"[RangeService] DebugProving is set but Config/ProvingGrounds is missing; booting missions"
		)
		return
	end
	active = true
end

function RangeService.IsActive(): boolean
	return active
end

-- A loaded player enters the range: default weapon and variants, placed at a spawn, told the
-- current tuning. Idempotent.
function RangeService.AddPlayer(player: Player): ()
	if not active or shooters[player] ~= nil or player.Parent == nil then
		return
	end
	local config = Tuning.Get()
	local shooter: Shooter = {
		player = player,
		loadout = {
			melee = startingFamily(config, "melee"),
			ranged = startingFamily(config, "ranged"),
			variants = {},
		},
		lastSeq = { melee = -1, ranged = -1 },
		lastAttackAt = { melee = 0, ranged = 0 },
		combo = {},
		drawStartedAt = 0,
		drawWeapon = "",
		lastDashAt = 0,
		iframesUntil = 0,
		lastSlamAt = 0,
		airborne = false,
		peakY = 0,
		lastPeakY = -math.huge,
		landedAt = 0,
		diveSpeed = 0,
		lastDiveSpeed = 0,
		lastY = nil,
		salt = Random.new():NextInteger(1, SEED_MODULUS - 1),
		damageLog = {},
		lastHits = 0,
		lastKills = 0,
		connections = {},
	}
	shooters[player] = shooter
	table.insert(
		shooter.connections,
		player.CharacterAdded:Connect(function(character: Model)
			prepareCharacter(player, character)
		end)
	)
	local character = player.Character
	if character ~= nil then
		prepareCharacter(player, character)
	end
	tuneStateFor(shooter)
	sendStats(shooter)
end

function RangeService.RemovePlayer(player: Player): ()
	local shooter = shooters[player]
	if shooter == nil then
		return
	end
	for _, connection in shooter.connections do
		connection:Disconnect()
	end
	shooters[player] = nil
	local survivors: { Projectile } = {}
	for _, projectile in projectiles do
		if projectile.player ~= player then
			table.insert(survivors, projectile)
		end
	end
	projectiles = survivors
end

-- Studio flag for other systems (none in P1 hurt a player; the attribute shows it in Studio).
function RangeService.IsInvulnerable(player: Player): boolean
	local shooter = shooters[player]
	return shooter ~= nil and os.clock() < shooter.iframesUntil
end

-- Intents (payload shapes already checked by CombatRemotes) -----------------------------------

-- `weapon` is a family id and must be the family the player holds in that family's slot.
-- `charge` (0-1) matters only for charge weapons and is capped by the server's draw clock.
function RangeService.OnAttack(
	player: Player,
	weapon: string,
	seq: number,
	origin: Vector3,
	direction: Vector3,
	_ads: boolean,
	charge: number?
): ()
	local shooter = shooters[player]
	if not active or shooter == nil then
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
		sendRefused(shooter)
		return
	end
	if seq <= (shooter.lastSeq[slot] or -1) then
		return
	end
	local _character, root = rootOf(player)
	if root == nil then
		return
	end
	local variantKey, variant = variantFor(config, shooter, weapon)
	if variant == nil or variant.rate <= 0 then
		return
	end
	local now = os.clock()
	local interval = 1 / variant.rate
	local previousAttackAt = shooter.lastAttackAt[slot] or 0
	if now - previousAttackAt < interval * timingTolerance() then
		sendRefused(shooter)
		return
	end
	if variant.kind == "ranged" then
		-- Fortnite aim: the ray starts at the camera, which must sit near this character's head.
		-- A moving character's camera leads the server's view of it by the ping plus a margin.
		local character = player.Character
		local head = if character ~= nil then character:FindFirstChild("Head") else nil
		local anchor = if head ~= nil and head:IsA("BasePart") then head.Position else root.Position
		local shooting = config.shooting
		local lag = math.max(player:GetNetworkPing(), 0) + math.max(shooting.originLagSeconds, 0)
		local allowed = shooting.originPad + root.AssemblyLinearVelocity.Magnitude * lag
		if (origin - anchor).Magnitude > allowed then
			sendRefused(shooter)
			return
		end
		-- A split shot becomes splitCount arrows: the whole volley must fit, or the shot is refused.
		if
			(variant.projectileSpeed or 0) > 0
			and #projectiles + volleySize(variant) > MAX_PROJECTILES
		then
			sendRefused(shooter)
			return
		end
	elseif now - previousAttackAt > config.controls.comboResetSeconds then
		-- A pause breaks the combo: the next swing is step 1 again.
		shooter.combo[weapon] = 0
	end
	shooter.lastSeq[slot] = seq
	shooter.lastAttackAt[slot] = now
	if variant.kind == "melee" then
		resolveMelee(config, shooter, weapon, variantKey, variant, root, direction)
	else
		local used, scale, full =
			resolveCharge(shooter, weapon, variant, charge or 0, previousAttackAt, now)
		resolveRanged(
			config,
			shooter,
			weapon,
			variantKey,
			variant,
			seq,
			origin,
			direction,
			used,
			scale,
			full
		)
	end
end

-- The bow's draw start. It carries nothing the server trusts: it stamps its own clock, and
-- OnAttack caps the charge by the time since this stamp.
function RangeService.OnDraw(player: Player, weapon: string): ()
	local shooter = shooters[player]
	if not active or shooter == nil then
		return
	end
	local def = familyDef(Tuning.Get(), weapon)
	if def == nil then
		return
	end
	local slot: SlotName = if def.slot == "melee" then "melee" else "ranged"
	if slotFamily(shooter, slot) ~= weapon then
		return
	end
	shooter.drawStartedAt = os.clock()
	shooter.drawWeapon = weapon
end

-- Opens the i-frame window; the dash itself moves the client-owned character.
function RangeService.OnDash(player: Player, _direction: Vector3): ()
	local shooter = shooters[player]
	if not active or shooter == nil then
		return
	end
	local character, root = rootOf(player)
	if character == nil or root == nil then
		return
	end
	local movement = Tuning.Get().movement
	local now = os.clock()
	if now - shooter.lastDashAt < movement.dashCooldown * timingTolerance() then
		return
	end
	shooter.lastDashAt = now
	shooter.iframesUntil = now + movement.dashIframes
	character:SetAttribute(IFRAMES_ATTRIBUTE, true)
end

-- The slam lands where the SERVER sees the character come down, and only after a fall of at
-- least slamMinHeight from the server-tracked peak with a dive of at least slamMinDiveSpeed in
-- that airtime. The client may send it at impact, so a request within slamLandingGrace of the
-- landing still counts that jump.
function RangeService.OnSlam(player: Player): ()
	local shooter = shooters[player]
	if not active or shooter == nil then
		return
	end
	local _character, root, humanoid = rootOf(player)
	if root == nil or humanoid == nil then
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
	local tally = newTally()
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

-- Studio only. The path must name a scalar in the base config and keep its type; an override
-- equal to the base is dropped rather than stored.
function RangeService.OnTune(_player: Player, path: string, value: Types.TuneValue): ()
	if not active or not isStudio or not Tuning.Validate(path, value) then
		return
	end
	local updated = Tuning.GetOverrides()
	if Tuning.BaseValue(path) == value then
		updated[path] = nil
	else
		updated[path] = value
	end
	Tuning.SetOverrides(updated)
end

local function onTuningChanged(): ()
	for _, shooter in shooters do
		tuneStateFor(shooter)
	end
end

function RangeService.OnCommand(player: Player, command: string, argument: string?): ()
	local shooter = shooters[player]
	if not active or not isStudio or shooter == nil then
		return
	end
	local config = Tuning.Get()
	if command == "set" and argument ~= nil then
		loadSet(argument)
	elseif command == "reset" then
		loadSet(if currentSet ~= "" then currentSet else config.defaultSet)
	elseif command == "stress" then
		-- The stress set at crowd.stressCount (its first group's count is replaced).
		loadSet("stress", config.crowd.stressCount)
	elseif command == "weapon" and argument ~= nil then
		-- `weapon <familyId>`: the family goes into its own slot.
		local def = familyDef(config, argument)
		if def == nil then
			warn(`[RangeService] no weapon family "{argument}"`)
			return
		end
		if def.slot == "melee" then
			shooter.loadout.melee = argument
		else
			shooter.loadout.ranged = argument
		end
		shooter.combo[argument] = 0
		shooter.drawStartedAt = 0
		tuneStateFor(shooter)
	elseif command == "variant" and argument ~= nil then
		-- `variant <familyId> <key>` arrives as one argument string.
		local family, key = string.match(argument, "^(%S+)%s+(%S+)$")
		local def = if family ~= nil then familyDef(config, family) else nil
		if family == nil or key == nil or def == nil or def.variants[key] == nil then
			warn(`[RangeService] bad variant command "{argument}" (want: <family> <key>)`)
			return
		end
		shooter.loadout.variants[family] = key
		shooter.combo[family] = 0
		tuneStateFor(shooter)
	elseif command == "export" then
		print(`[RangeService] ProvingGrounds.json with the current tuning:\n{Tuning.Export()}`)
	elseif command == "clearTune" then
		Tuning.SetOverrides({})
	else
		warn(`[RangeService] unknown or incomplete range command "{command}"`)
		return
	end
	sendStats(shooter)
end

function RangeService.Init(): () end

-- Builds the range and loads the default set. Only when Configure(true) took effect.
function RangeService.Start(): ()
	if not active or started then
		return
	end
	started = true
	local config = Tuning.Get()
	local center, halfSize = ArenaService.BuildProvingArena(config.arena)
	floorHalfSize = halfSize
	CrowdService.SetBounds(center, halfSize)
	CrowdService.OnKilled(function(id: number, _byUserId: number)
		slotGone(id)
	end)
	Tuning.Changed:Connect(onTuningChanged)
	RunService.Heartbeat:Connect(step)
	loadSet(config.defaultSet)
	print("[RangeService] Proving Grounds ready")
end

return RangeService
