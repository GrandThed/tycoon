--!strict
-- The Proving Grounds server (docs/INTERFACES.md "P1 contracts", docs/COMBAT_DESIGN.md §8):
-- dummy sets and respawns, the per-player weapon and variant, attack resolution against the
-- crowd, dash i-frames, the ground slam, live tuning and the readouts.
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

type WeaponName = "sword" | "gun"
type Variant = Types.RangeWeaponVariant

-- Contract: projectiles live at most 3 s; DPS is a 5 s window; readouts go out at 2 Hz.
local PROJECTILE_MAX_SECONDS = 3
local DPS_WINDOW_SECONDS = 5
local STATS_INTERVAL_SECONDS = 0.5
-- Lead ruling: a group of up to this many is one row along x; larger groups are a square grid.
local ROW_MAX_COUNT = 10
-- Used when Combat.json is absent: the share of an interval a client may arrive early by
-- (network jitter), same meaning as Combat.json player.comboTimingTolerance.
local DEFAULT_TIMING_TOLERANCE = 0.8
-- A slam request may trail the landing by this much: the client sends it at impact and the
-- server's view of the character lags the client's.
local SLAM_LANDING_GRACE_SECONDS = 0.5
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
}
type Respawn = { at: number, slot: Slot }
type Projectile = {
	player: Player,
	weapon: WeaponName,
	variantKey: string,
	variant: Variant,
	origin: Vector3,
	position: Vector3,
	direction: Vector3,
	travelled: number,
	age: number,
	seq: number,
}
type DamageEntry = { at: number, amount: number }
type Shooter = {
	player: Player,
	weapon: WeaponName,
	variants: { [string]: string },
	lastSeq: { [string]: number },
	lastAttackAt: { [string]: number },
	combo: { [string]: number },
	lastDashAt: number,
	iframesUntil: number,
	lastSlamAt: number,
	airborne: boolean,
	peakY: number,
	-- The peak of the airborne phase that ended at landedAt (for a slam request that trails it).
	lastPeakY: number,
	landedAt: number,
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

local function isWeapon(value: string): boolean
	return value == "sword" or value == "gun"
end

local function weaponDef(
	config: Types.ProvingGroundsConfig,
	weapon: WeaponName
): Types.RangeWeaponDef
	return if weapon == "sword" then config.weapons.sword else config.weapons.gun
end

local function variantOf(
	config: Types.ProvingGroundsConfig,
	weapon: WeaponName,
	key: string
): Variant?
	return weaponDef(config, weapon).variants[key]
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
	-- TuneState carries three arguments, which RemoteService.FireClient (one payload) cannot.
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
		shooter.weapon,
		shooter.variants[shooter.weapon] or ""
	)
end

local function statsFor(shooter: Shooter, now: number): Types.RangeStats
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
	}
end

local function sendStats(shooter: Shooter): ()
	RemoteService.FireClient(shooter.player, "RangeStats", statsFor(shooter, os.clock()))
end

local function broadcastStrike(strike: Types.CombatFxStrike): ()
	local batch: { Types.CombatFx } = { strike }
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
	if id == 0 then
		-- Refused (crowd.maxAlive reached): try again after the group's respawn delay.
		table.insert(respawns, { at = os.clock() + math.max(slot.respawnSeconds, 1), slot = slot })
		return
	end
	slotById[id] = slot
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
	projectiles = {}
	currentSet = name
	clearStartedAt = 0
	clearSeconds = nil
	for groupIndex, group in groups do
		local def = kindDef(config, group.kind)
		if def == nil then
			warn(`[RangeService] set {name}: unknown crowd kind "{group.kind}"`)
			continue
		end
		local count = if groupIndex == 1 and countOverride ~= nil
			then countOverride
			else group.count
		count = math.max(0, math.floor(count))
		for _, position in groupPositions(group, count, def.radius) do
			local slot: Slot = {
				kind = group.kind,
				behaviour = group.behaviour,
				position = position,
				respawnSeconds = group.respawnSeconds,
				cleared = false,
			}
			table.insert(setSlots, slot)
			spawnSlot(slot)
		end
	end
	print(`[RangeService] loaded set "{name}" ({#setSlots} dummies)`)
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
	}
): ()
	local now = os.clock()
	if tally.dealt > 0 and clearStartedAt == 0 then
		clearStartedAt = now
	end
	broadcastStrike({
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
	shooter.lastHits = #tally.hits
	shooter.lastKills = tally.kills
	if tally.dealt > 0 then
		table.insert(shooter.damageLog, { at = now, amount = tally.dealt })
	end
	sendStats(shooter)
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
	weapon: WeaponName,
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
	local tally = newTally()

	if shape == "sphere" then
		explode(config, shooter.player, origin, range, variant, damage, heading, tally)
	else
		local tip = origin + heading * range
		local test = function(body: Vector3, r: number): (number?, boolean)
			local touched = false
			if shape == "arc" then
				touched = HitShapes.Arc(origin, heading, range, arcDegrees or 360, pad, body, r)
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
		local candidates = gather(config, origin, range + pad + halfWidth, test)
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
		endPoint = nil,
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

local function launchProjectile(
	shooter: Shooter,
	weapon: WeaponName,
	variantKey: string,
	variant: Variant,
	origin: Vector3,
	direction: Vector3,
	seq: number
): ()
	table.insert(projectiles, {
		player = shooter.player,
		weapon = weapon,
		variantKey = variantKey,
		-- Frozen at the trigger pull: a slider moved mid-flight applies to the next shot.
		variant = table.clone(variant),
		origin = origin,
		position = origin,
		direction = direction,
		travelled = 0,
		age = 0,
		seq = seq,
	})
end

local function resolveRanged(
	config: Types.ProvingGroundsConfig,
	shooter: Shooter,
	weapon: WeaponName,
	variantKey: string,
	variant: Variant,
	seq: number,
	origin: Vector3,
	direction: Vector3
): ()
	local unit = direction.Unit
	if (variant.projectileSpeed or 0) > 0 then
		launchProjectile(shooter, weapon, variantKey, variant, origin, unit, seq)
		return
	end
	local critMult = config.shooting.critMult
	local params = worldParams()
	local player = shooter.player
	local tally = newTally()
	local pushBase = (flatten(unit) or Vector3.zero) * variant.knockback
	local pellets = variant.pellets or 0

	if pellets > 0 then
		-- Each pellet is one hit on the first live enemy it meets; the pattern is the server's
		-- own, seeded by seq (HitShapes.Pellets, so a client can draw the same one).
		local struck: { [number]: boolean } = {}
		local killed: { [number]: boolean } = {}
		local distinct = 0
		local cap = if variant.cap > 0 then variant.cap else math.huge
		for _, pelletDirection in HitShapes.Pellets(unit, pellets, variant.spreadDegrees or 0, seq) do
			local reach = worldReach(origin, pelletDirection, variant.range, params)
			for _, candidate in rayCandidates(config, origin, pelletDirection, reach, variant) do
				if killed[candidate.id] then
					continue
				end
				if not struck[candidate.id] then
					if distinct >= cap then
						break
					end
					distinct += 1
				end
				local amount = if candidate.crit then variant.damage * critMult else variant.damage
				-- Knockback once per enemy, not once per pellet.
				local push = if struck[candidate.id] then nil else pushBase
				struck[candidate.id] = true
				if
					strike(
						tally,
						player,
						candidate.id,
						amount,
						candidate.crit,
						push,
						variant.launch
					)
				then
					killed[candidate.id] = true
				end
				break
			end
		end
		finish(player, weapon, variantKey, tally, {
			shape = variant.shape,
			origin = origin,
			direction = unit,
			size = variant.range,
			arcDegrees = variant.arcDegrees,
			width = variant.width,
			endPoint = nil,
			seq = seq,
		})
		return
	end

	local reach = worldReach(origin, unit, variant.range, params)
	if variant.shape == "ray" then
		local candidates = rayCandidates(config, origin, unit, reach, variant)
		local limit = capOf(variant, math.min(#candidates, math.max(1, variant.pierce or 1)))
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
			seq = seq,
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
			seq = seq,
		})
		return
	end

	-- Arc, cone or capsule fired from the camera ray: everything inside, nearest first.
	local shape: Types.HitShape = variant.shape
	local halfWidth = (variant.width or 0) / 2
	local tip = origin + unit * reach
	local candidates = gather(
		config,
		origin,
		reach + variant.pad + halfWidth,
		function(body: Vector3, r: number): (number?, boolean)
			local touched = false
			if shape == "cone" then
				touched = HitShapes.Cone(
					origin,
					unit,
					reach,
					(variant.arcDegrees or 0) / 2,
					variant.pad,
					body,
					r
				)
			elseif shape == "arc" then
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
		seq = seq,
	})
end

local function detonate(
	config: Types.ProvingGroundsConfig,
	projectile: Projectile,
	impact: Vector3
): ()
	local player = projectile.player
	if player.Parent == nil then
		return
	end
	local variant = projectile.variant
	local radius = variant.splashRadius or 0
	local tally = newTally()
	explode(config, player, impact, radius, variant, variant.damage, projectile.direction, tally)
	finish(player, projectile.weapon, projectile.variantKey, tally, {
		shape = "sphere",
		origin = projectile.origin,
		direction = projectile.direction,
		size = radius,
		arcDegrees = nil,
		width = nil,
		endPoint = impact,
		seq = projectile.seq,
	})
end

-- Straight-line flight, tested segment by segment against the world and the crowd. A shell
-- that reaches its range or lifetime without touching anything bursts where it is.
local function stepProjectiles(config: Types.ProvingGroundsConfig, deltaTime: number): ()
	if #projectiles == 0 then
		return
	end
	local params = worldParams()
	local survivors: { Projectile } = {}
	for _, projectile in projectiles do
		local variant = projectile.variant
		local speed = variant.projectileSpeed or 0
		local length =
			math.min(speed * deltaTime, math.max(0, variant.range - projectile.travelled))
		local impact: Vector3? = nil
		if length > 0 then
			local from = projectile.position
			local direction = projectile.direction
			local stop = worldReach(from, direction, length, params)
			local candidates = rayCandidates(config, from, direction, stop, variant)
			local first = candidates[1]
			if first ~= nil then
				impact = from + direction * first.order
			elseif stop < length then
				impact = from + direction * stop
			end
			projectile.position = from + direction * length
			projectile.travelled += length
		end
		projectile.age += deltaTime
		if
			impact == nil
			and (projectile.age >= PROJECTILE_MAX_SECONDS or projectile.travelled >= variant.range)
		then
			impact = projectile.position
		end
		if impact ~= nil then
			detonate(config, projectile, impact)
		else
			table.insert(survivors, projectile)
		end
	end
	projectiles = survivors
end

-- Air tracking for the slam: the server's own view of how high each character got.
local function trackAir(now: number): ()
	if next(shooters) == nil then
		return
	end
	local params = worldParams()
	for player, shooter in shooters do
		local _character, root, humanoid = rootOf(player)
		if root == nil or humanoid == nil then
			shooter.airborne = false
			continue
		end
		local floorY = floorBelow(root, params)
		local height = if floorY ~= nil then root.Position.Y - floorY else math.huge
		local airborne = height > standingOffset(root, humanoid) + AIRBORNE_MARGIN_STUDS
		local y = root.Position.Y
		if airborne then
			shooter.peakY = if shooter.airborne then math.max(shooter.peakY, y) else y
		elseif shooter.airborne then
			shooter.lastPeakY = shooter.peakY
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
	trackAir(now)
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
		weapon = "sword",
		variants = { sword = config.weapons.sword.default, gun = config.weapons.gun.default },
		lastSeq = { sword = -1, gun = -1 },
		lastAttackAt = { sword = 0, gun = 0 },
		combo = { sword = 0, gun = 0 },
		lastDashAt = 0,
		iframesUntil = 0,
		lastSlamAt = 0,
		airborne = false,
		peakY = 0,
		lastPeakY = -math.huge,
		landedAt = 0,
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

function RangeService.OnAttack(
	player: Player,
	weapon: string,
	seq: number,
	origin: Vector3,
	direction: Vector3,
	_ads: boolean
): ()
	local shooter = shooters[player]
	if not active or shooter == nil or not isWeapon(weapon) then
		return
	end
	local weaponName: WeaponName = if weapon == "sword" then "sword" else "gun"
	if seq <= (shooter.lastSeq[weaponName] or -1) then
		return
	end
	local _character, root = rootOf(player)
	if root == nil then
		return
	end
	local config = Tuning.Get()
	local variantKey = shooter.variants[weaponName] or ""
	local variant = variantOf(config, weaponName, variantKey)
	if variant == nil or variant.rate <= 0 then
		return
	end
	local now = os.clock()
	local interval = 1 / variant.rate
	if now - (shooter.lastAttackAt[weaponName] or 0) < interval * timingTolerance() then
		return
	end
	if variant.kind == "ranged" then
		-- Fortnite aim: the ray starts at the camera, which must sit near this character's head.
		local character = player.Character
		local head = if character ~= nil then character:FindFirstChild("Head") else nil
		local anchor = if head ~= nil and head:IsA("BasePart") then head.Position else root.Position
		if (origin - anchor).Magnitude > config.shooting.originPad then
			return
		end
	end
	shooter.lastSeq[weaponName] = seq
	shooter.lastAttackAt[weaponName] = now
	if shooter.weapon ~= weaponName then
		-- The client switched weapons locally; keep the TuneState it reads in step.
		shooter.weapon = weaponName
		tuneStateFor(shooter)
	end
	if variant.kind == "melee" then
		resolveMelee(config, shooter, weaponName, variantKey, variant, root, direction)
	else
		resolveRanged(config, shooter, weaponName, variantKey, variant, seq, origin, direction)
	end
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
-- least slamMinHeight from the server-tracked peak. The client may send it at impact, so a
-- request just after landing still counts that jump's peak.
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
	if shooter.airborne then
		peak = shooter.peakY
	elseif now - shooter.landedAt <= SLAM_LANDING_GRACE_SECONDS then
		peak = shooter.lastPeakY
	else
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
	elseif command == "weapon" and argument ~= nil and isWeapon(argument) then
		shooter.weapon = if argument == "sword" then "sword" else "gun"
		tuneStateFor(shooter)
	elseif command == "variant" and argument ~= nil then
		if variantOf(config, shooter.weapon, argument) == nil then
			warn(`[RangeService] {shooter.weapon} has no variant "{argument}"`)
			return
		end
		shooter.variants[shooter.weapon] = argument
		shooter.combo[shooter.weapon] = 0
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
