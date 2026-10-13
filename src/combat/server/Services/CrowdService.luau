--!strict
-- Lightweight crowd enemies for the Proving Grounds (docs/INTERFACES.md "P1 contracts",
-- decision 1; docs/COMBAT_DESIGN.md §7). An enemy is a plain Luau record: no Instance, no
-- Humanoid, no physics body. The server moves the records on a fixed-step Heartbeat loop and
-- replicates them three ways: CrowdSpawn (reliable, batched) introduces an id, CrowdSnapshot
-- (unreliable, CrowdCodec buffers) carries every record each step, CrowdRemove (reliable,
-- batched) ends one. Clients draw pooled bodies from those.
--
-- Rules that shape the module:
-- * Nothing in the step may yield (C1 review lesson): kill callbacks run on their own threads
--   via task.spawn, and every send is a fire-and-forget remote.
-- * Every number comes through Tuning.Get() when it is used (crowd.kinds, crowd.behaviour,
--   deadSeconds, staggerSeconds, knockFriction, knockMax, armorFloor), so a Studio slider moves
--   the crowd immediately. Module constants are engine plumbing only.
-- * A record's position is its FEET. Body sphere: centre height/2, `radius`. Head sphere:
--   centre height − headRadius, `headRadius`.
-- * The loop starts itself on the first Spawn or SetBounds, so a mission server that never
--   touches the range never runs it.
--
-- P4 (INTERFACES "P4 contracts"): an enemy whose group's behaviour is `fight` carries a mind and
-- is steered by CrowdBrain instead of the passive behaviours below, which are untouched. The
-- brain only queues its impacts; after the step they go to the threat hooks (VitalsService),
-- which this file never requires. The snapshot is CrowdCodec v2 (plated, attack index).
-- Wave 2: a kind with `plate` wears it in every set, passive ones included (Damage); a brute's
-- charge is carried by the brain (integrate), and nothing else moves it.
-- Stop 3 (the Warlord): a `guarded` kind's plate takes no damage until its guard has been
-- called and is dead (Damage); a summoned body's spawn names its summoner, so every client can
-- count that guard.
-- Stop 2 (the Colossus): a `summon` impact raises its bodies here (summon), and they go when
-- their summoner dies (dismiss), as does everything a `boss` kind had in the air. A body of
-- crowd.largeRadius or more is separated in a pass of its own, so one giant does not widen the
-- neighbourhood every other body scans, and nothing smaller ever pushes it.
-- P5 (INTERFACES "P5 contracts", rulings 9, 10, 14 and 26): the crowd fights in missions too.
-- A run sets crowd-wide scales once (SetScales: HP, plate), a boss body takes its party HP factor
-- at Spawn, and a hit's HP loss is multiplied by the attacker's tier scale while the plate,
-- heavyHit, the interrupt and armour keep judging the unscaled tier-1 amount. A kill carries what
-- the run pays for (CrowdKillInfo). In Studio the step's cost is logged as a `[Perf]` line.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local CrowdCodec = require(sharedFolder:WaitForChild("CrowdCodec"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local RemoteService =
	require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("RemoteService"))
local CrowdBrain = require(script.Parent:WaitForChild("CrowdBrain"))

type Behaviour = "idle" | "walk" | "strafe" | "jump" | "chase" | "fight"

type Enemy = {
	id: number,
	kind: string,
	behaviour: Behaviour,
	-- Last known kind def, used if Tuning ever stops listing the kind mid-life.
	def: Types.CrowdKindDef,
	anchor: Vector3,
	position: Vector3,
	-- Total velocity of the last step (steering + knockback + vertical), reported by Get.
	velocity: Vector3,
	-- Horizontal knockback velocity; bleeds off by friction on the ground, kept in the air.
	knock: Vector3,
	vy: number,
	yaw: number,
	hp: number,
	maxHp: number,
	-- What is left of the plate (0 = none, or broken) and what it started with.
	plate: number,
	plateMax: number,
	state: Types.CrowdState,
	staggerUntil: number,
	deadAt: number?,
	-- Per-id offset so a row of movers does not march in lockstep.
	phase: number,
	-- walk: which end of the pace line it is heading for (±1).
	leg: number,
	nextHopAt: number,
	-- Dense-list slot, for O(1) swap removal.
	index: number,
	entry: Types.CrowdSnapshotEntry,
	spawnInfo: Types.CrowdSpawnInfo,
	-- Only a `fight` enemy has one; nil keeps every passive path exactly as it was.
	mind: CrowdBrain.Mind?,
	-- The enemy whose `summon` raised this one, and how many this one has raised itself: a
	-- summoned body is no slot of any set, never respawns and goes when its summoner dies.
	summoner: Enemy?,
	summoned: number,
	-- How many of the bodies it summoned are alive now (a body in its dead state is not).
	guard: number,
	-- A summoned body: which of its summoner's even places it rose on (0-based).
	place: number,
	-- P5: HP removed from this body per userId, each hit capped at the HP it had left.
	damageBy: { [number]: number },
}

-- P5: the run's crowd-wide multipliers. The range never sets them.
export type CrowdScales = { hp: number, plate: number }
-- P5 ruling 14: what a kill hands the run. Bodies removed without a kill carry none.
export type CrowdKillInfo = {
	id: number,
	kind: string,
	boss: boolean,
	position: Vector3,
	byUserId: number,
	damageBy: { [number]: number },
}
type KillCallback = (id: number, byUserId: number, info: CrowdKillInfo) -> ()

type CrowdConfig = typeof((({} :: any) :: Types.ProvingGroundsConfig).crowd)
type CrowdBehaviourConfig = typeof((({} :: any) :: CrowdConfig).behaviour)

type EnemyView = {
	position: Vector3,
	velocity: Vector3,
	kind: string,
	hp: number,
	maxHp: number,
	state: Types.CrowdState,
}

-- What fighting enemies need from whoever owns the players' bodies. Every hook is called from
-- the Heartbeat that stepped and must not yield.
export type ThreatHooks = {
	-- May a fighting enemy go for this player? (Not while they are down.)
	canTarget: (player: Player) -> boolean,
	-- One enemy attack's impact, its shape frozen. Called after the step, never inside it.
	impact: (strike: CrowdBrain.Strike) -> (),
	-- The bodies with these ids are gone for good (a boss has died, and its summons with it):
	-- nothing of their attacks may land any more.
	gone: (ids: { [number]: boolean }) -> (),
	-- Once per Heartbeat that stepped, after the impacts, with the frame's os.clock(): the
	-- attacks that travel (shots, charges) are judged here.
	step: (clock: number) -> (),
	-- Enemy shots in the air, for the brain's cap.
	shotsAlive: () -> number,
}

-- What Damage did besides the number: blocked = a plate stopped it (nothing happened); plate =
-- it went to the plate; broke = it emptied the plate; gone = there is no such body (any more);
-- guarded = blocked, heavy or not, because the body's guard lives (a `guarded` kind).
export type Verdict = "blocked" | "guarded" | "plate" | "broke" | "gone"

local SPAWN_EVENT = "CrowdSpawn"
local SNAPSHOT_EVENT = "CrowdSnapshot"
local REMOVE_EVENT = "CrowdRemove"

-- Wire ids are u16 (CrowdCodec); 0 is the "refused" return of Spawn.
local MAX_ID = 65535
-- After a long frame the loop runs at most this many steps, then drops the backlog rather than
-- spiralling.
local MAX_CATCHUP_STEPS = 3
-- A slider dragged to 0 must not divide by zero or hop every step.
local MIN_PERIOD_SECONDS = 0.1
local GROUND_EPSILON = 0.01
local MOVE_THRESHOLD = 0.2
-- Before SetBounds: floor at y 0, effectively unbounded sideways, launches capped at 200.
local DEFAULT_HALF_SIZE = Vector3.new(1024, 200, 1024)
-- Spatial hash. Small cells keep a packed stress crowd at ~2 bodies per cell; separation widens
-- its neighbourhood to cover the widest living body that is not large (crowd.largeRadius).
local CELL_SIZE = 4
local CELL_OFFSET = 32768
local CELL_STRIDE = 65536
local GOLDEN_RATIO_FRACTION = 0.6180339887
-- Step times kept for the [Perf] line: more than ten seconds at the fastest snapshot rate.
local PERF_RING = 512

local BEHAVIOURS: { [string]: Behaviour } = {
	idle = "idle",
	walk = "walk",
	strafe = "strafe",
	jump = "jump",
	chase = "chase",
	fight = "fight",
}

local enemies: { [number]: Enemy } = {}
local order: { Enemy } = {}
local aliveCount = 0
local lastId = 0
local simTime = 0
local accumulator = 0
local lastStepMs = 0

local boundsCenter = Vector3.zero
local boundsHalf = DEFAULT_HALF_SIZE

local grid: { [number]: { Enemy } } = {}
local usedCells: { number } = {}

-- Pending lifecycle sends, flushed once per step: removes first, then spawns, so a client never
-- sees an id introduced and then ended out of order within one batch.
local pendingSpawnOrder: { number } = {}
local pendingSpawnSet: { [number]: boolean } = {}
local pendingRemoves: { number } = {}

local killCallbacks: { KillCallback } = {}
local warnedKinds: { [string]: boolean } = {}
local threatHooks: ThreatHooks? = nil
local scales: CrowdScales = { hp = 1, plate = 1 }
-- The [Perf] line (ruling 26): `every` 0 = off. A fixed ring of step times, so a step allocates
-- nothing; a copy is sorted only when a line is printed.
local perf = {
	every = 0,
	ring = table.create(PERF_RING, 0) :: { number },
	sorted = table.create(PERF_RING, 0) :: { number },
	head = 0,
	count = 0,
	peak = 0,
	since = 0,
}

-- Scratch tables reused every step so the loop allocates nothing per enemy.
local targets: { Vector3 } = {}
local expired: { Enemy } = {}
local giants: { Enemy } = {}
local chunk: { Types.CrowdSnapshotEntry } = {}

local running = false

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector(value: Vector3): boolean
	return isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z)
end

local function currentDef(enemy: Enemy, kinds: { [string]: Types.CrowdKindDef }): Types.CrowdKindDef
	local def = kinds[enemy.kind]
	if def ~= nil then
		enemy.def = def
		return def
	end
	return enemy.def
end

local function gravity(): number
	return Workspace.Gravity
end

local function launchSpeed(height: number): number
	if height <= 0 then
		return 0
	end
	return math.sqrt(2 * gravity() * height)
end

-- Keeps a body wholly inside the arena footprint and under the launch ceiling. A clamp that
-- bites cancels the knockback on that axis so the body does not grind against the wall.
local function clampToBounds(enemy: Enemy, radius: number): ()
	local position = enemy.position
	local limitX = math.max(boundsHalf.X - radius, 0)
	local limitZ = math.max(boundsHalf.Z - radius, 0)
	local floorY = boundsCenter.Y
	local x = math.clamp(position.X, boundsCenter.X - limitX, boundsCenter.X + limitX)
	local z = math.clamp(position.Z, boundsCenter.Z - limitZ, boundsCenter.Z + limitZ)
	local y = math.clamp(position.Y, floorY, floorY + boundsHalf.Y)
	if x ~= position.X or z ~= position.Z or y ~= position.Y then
		local knock = enemy.knock
		enemy.knock = Vector3.new(
			if x ~= position.X then 0 else knock.X,
			0,
			if z ~= position.Z then 0 else knock.Z
		)
		if y > position.Y or (y < position.Y and enemy.vy > 0) then
			enemy.vy = 0
		end
		enemy.position = Vector3.new(x, y, z)
	end
end

local function cellKeyOf(position: Vector3): number
	local cx = math.floor(position.X / CELL_SIZE)
	local cz = math.floor(position.Z / CELL_SIZE)
	return (cx + CELL_OFFSET) * CELL_STRIDE + (cz + CELL_OFFSET)
end

local function gridInsert(enemy: Enemy): ()
	local key = cellKeyOf(enemy.position)
	local cell = grid[key]
	if cell == nil then
		cell = {}
		grid[key] = cell
	end
	if #cell == 0 then
		table.insert(usedCells, key)
	end
	table.insert(cell, enemy)
end

-- Cell tables are kept and cleared, not dropped: the set of cells an arena ever touches is small.
local function gridRebuild(): ()
	for _, key in usedCells do
		table.clear(grid[key])
	end
	table.clear(usedCells)
	for _, enemy in order do
		if enemy.deadAt == nil then
			gridInsert(enemy)
		end
	end
end

local function fireAll(eventName: string, payload: any): ()
	for _, player in Players:GetPlayers() do
		RemoteService.FireClient(player, eventName, payload)
	end
end

local function removeRecord(enemy: Enemy): ()
	enemies[enemy.id] = nil
	local last = order[#order]
	order[enemy.index] = last
	last.index = enemy.index
	order[#order] = nil
	if enemy.deadAt == nil then
		aliveCount -= 1
		-- Removed alive (a set load, its summoner's death): it leaves its summoner's guard.
		local summoner = enemy.summoner
		if summoner ~= nil then
			summoner.guard = math.max(summoner.guard - 1, 0)
		end
	end
	if pendingSpawnSet[enemy.id] then
		-- Never announced, so there is nothing to end on the client.
		pendingSpawnSet[enemy.id] = nil
	else
		table.insert(pendingRemoves, enemy.id)
	end
end

local function nextId(): number
	for _ = 1, MAX_ID do
		lastId = lastId % MAX_ID + 1
		if enemies[lastId] == nil then
			return lastId
		end
	end
	return 0
end

local function yawToward(direction: Vector3): number
	-- CFrame.Angles(0, yaw, 0).LookVector points along `direction`.
	return math.atan2(-direction.X, -direction.Z)
end

local function nearestTarget(position: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, target in targets do
		local dx = target.X - position.X
		local dz = target.Z - position.Z
		local distance = dx * dx + dz * dz
		if distance < bestDistance then
			bestDistance = distance
			best = target
		end
	end
	return best
end

-- Horizontal velocity toward `goal`, arriving exactly (no overshoot jitter) and stopping at
-- `stopDistance`.
local function seek(
	from: Vector3,
	goal: Vector3,
	speed: number,
	stopDistance: number,
	dt: number
): Vector3
	local dx = goal.X - from.X
	local dz = goal.Z - from.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance <= stopDistance or speed <= 0 then
		return Vector3.zero
	end
	local travel = math.min(speed, (distance - stopDistance) / dt)
	return Vector3.new(dx / distance * travel, 0, dz / distance * travel)
end

local function steer(
	enemy: Enemy,
	def: Types.CrowdKindDef,
	shapes: CrowdBehaviourConfig,
	target: Vector3?,
	dt: number
): Vector3
	local behaviour = enemy.behaviour
	local speed = math.max(def.speed, 0)
	local position = enemy.position
	if behaviour == "chase" then
		if target == nil then
			return Vector3.zero
		end
		return seek(position, target, speed, def.radius + shapes.chaseStandoff, dt)
	elseif behaviour == "walk" then
		local goal = enemy.anchor + Vector3.new(0, 0, enemy.leg * shapes.walkLength / 2)
		local dx = goal.X - position.X
		local dz = goal.Z - position.Z
		local tolerance = math.max(shapes.homeTolerance, 0)
		if dx * dx + dz * dz <= tolerance * tolerance then
			enemy.leg = -enemy.leg
			goal = enemy.anchor + Vector3.new(0, 0, enemy.leg * shapes.walkLength / 2)
		end
		return seek(position, goal, speed * math.max(shapes.walkPace, 0), 0, dt)
	elseif behaviour == "strafe" then
		local period = math.max(shapes.strafePeriod, MIN_PERIOD_SECONDS)
		local side = if math.floor((simTime + enemy.phase * period) / period) % 2 == 0
			then 1
			else -1
		return seek(
			position,
			enemy.anchor + Vector3.new(side * shapes.strafeWidth / 2, 0, 0),
			speed,
			0,
			dt
		)
	elseif behaviour == "jump" and simTime >= enemy.nextHopAt then
		enemy.vy = launchSpeed(shapes.hopHeight)
		enemy.nextHopAt = simTime + math.max(shapes.hopPeriod, MIN_PERIOD_SECONDS)
	end
	-- idle and jump drift home after a shove, so a knocked-over row re-forms.
	return seek(
		position,
		enemy.anchor,
		speed * math.max(shapes.homePace, 0),
		math.max(shapes.homeTolerance, 0),
		dt
	)
end

-- `targets` is what the passive behaviours chase and watch: every living player. The brain's
-- targets are the same players less the ones the threat hooks rule out.
local function gatherTargets(shooting: Types.RangeShootingConfig): ()
	table.clear(targets)
	local hooks = threatHooks
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0 then
			table.insert(targets, root.Position)
			if hooks == nil or hooks.canTarget(player) then
				-- R15's HipHeight is measured to the root's underside.
				local standY = boundsCenter.Y + humanoid.HipHeight + root.Size.Y / 2
				local lag = Tuning.CommitLag(shooting, player:GetNetworkPing())
				CrowdBrain.AddTarget(player.UserId, root.Position, standY, lag)
			end
		end
	end
end

local function integrate(
	enemy: Enemy,
	def: Types.CrowdKindDef,
	crowd: CrowdConfig,
	dt: number,
	g: number
): ()
	local floorY = boundsCenter.Y
	local position = enemy.position
	local grounded = position.Y <= floorY + GROUND_EPSILON and enemy.vy <= 0
	local alive = enemy.deadAt == nil
	local mind = enemy.mind
	-- A fighting body looks where its brain says: its own target, which a downed player is not.
	local target = if alive and mind == nil then nearestTarget(position) else nil

	local desired = Vector3.zero
	local free = alive and grounded and simTime >= enemy.staggerUntil
	if mind ~= nil then
		if alive then
			-- Called even when the body is not free: an attack under way keeps its timeline
			-- through a stagger or a hop.
			local goal, stopDistance = CrowdBrain.Think(enemy, mind, def, crowd, free)
			local carried = if mind.charge ~= nil then CrowdBrain.Carried(mind) else nil
			if carried ~= nil then
				-- A charge: the brain carries the body down its lane, and nothing else moves it
				-- or shows over it. It stops at the arena's edge (the brain cut its run there).
				enemy.knock = Vector3.zero
				enemy.vy = 0
				enemy.position = Vector3.new(carried.X, floorY, carried.Z)
				clampToBounds(enemy, def.radius)
				enemy.velocity = (enemy.position - position) / dt
				enemy.yaw = yawToward(mind.facing)
				-- attack through the run; recover in the one step that sets it down at its end.
				enemy.state = CrowdBrain.StateOf(mind) or "idle"
				return
			end
			if goal ~= nil then
				desired = seek(position, goal, math.max(def.speed, 0), stopDistance, dt)
			end
		end
	elseif free then
		desired = steer(enemy, def, crowd.behaviour, target, dt)
	end

	local knock = enemy.knock
	if grounded then
		local knockSpeed = knock.Magnitude
		if knockSpeed > 0 then
			local slowed = math.max(knockSpeed - math.max(crowd.knockFriction, 0) * dt, 0)
			knock = if slowed > 0 then knock * (slowed / knockSpeed) else Vector3.zero
			enemy.knock = knock
		end
	end

	local horizontal = desired + knock
	enemy.vy -= g * dt
	enemy.position = Vector3.new(
		position.X + horizontal.X * dt,
		math.max(position.Y + enemy.vy * dt, floorY),
		position.Z + horizontal.Z * dt
	)
	if enemy.position.Y <= floorY and enemy.vy < 0 then
		enemy.vy = 0
	end
	clampToBounds(enemy, def.radius)
	enemy.velocity = Vector3.new(horizontal.X, enemy.vy, horizontal.Z)

	local moving = desired.Magnitude > MOVE_THRESHOLD
	if alive then
		if mind ~= nil then
			-- Walking, a rusher faces where it goes; otherwise, and for a shooter always, its
			-- target or the heading its windup locked (the brain keeps `facing` for both).
			enemy.yaw = yawToward(if moving and not mind.watch then desired else mind.facing)
		elseif moving and enemy.behaviour ~= "strafe" then
			-- Strafers and idlers watch the player; walkers and chasers face where they go.
			enemy.yaw = yawToward(desired)
		elseif target ~= nil then
			local toTarget = target - enemy.position
			if toTarget.X ~= 0 or toTarget.Z ~= 0 then
				enemy.yaw = yawToward(toTarget)
			end
		end
	end

	if not alive then
		enemy.state = "dead"
	elseif enemy.position.Y > floorY + GROUND_EPSILON then
		enemy.state = "airborne"
	elseif simTime < enemy.staggerUntil then
		enemy.state = "stagger"
	else
		-- windup, attack or recover while the brain is in one. A stagger or a launch shows over
		-- it and the phase shows again after, its clock never having stopped.
		local phase: Types.CrowdState? = if mind ~= nil then CrowdBrain.StateOf(mind) else nil
		if phase ~= nil then
			enemy.state = phase
		elseif moving then
			enemy.state = "move"
		else
			enemy.state = "idle"
		end
	end
end

-- The large bodies' share of separation: each against everything in the cells it can reach.
-- A smaller body gives way to a large one by the whole overlap, and a large one is never moved
-- by a smaller one: where the smaller one is planted in its windup or attack the two simply
-- overlap until it has struck. Two large bodies split their overlap as any pair does.
-- `widest` = the widest living body that is not large; `largeRadius` = crowd.largeRadius.
local function shoulder(widest: number, largeRadius: number): ()
	local broadest = widest
	for _, giant in giants do
		broadest = math.max(broadest, giant.def.radius)
	end
	for _, giant in giants do
		local def = giant.def
		local radius = def.radius
		local mind = giant.mind
		local planted = mind ~= nil and CrowdBrain.IsStriking(mind)
		local cx = math.floor(giant.position.X / CELL_SIZE) + CELL_OFFSET
		local cz = math.floor(giant.position.Z / CELL_SIZE) + CELL_OFFSET
		local reach = math.ceil((radius + broadest) / CELL_SIZE)
		for ox = -reach, reach do
			for oz = -reach, reach do
				local cell = grid[(cx + ox) * CELL_STRIDE + (cz + oz)]
				if cell == nil then
					continue
				end
				for _, other in cell do
					if other == giant or other.deadAt ~= nil then
						continue
					end
					local otherDef = other.def
					local large = otherDef.radius >= largeRadius
					if large and other.id < giant.id then
						-- That pair was handled from the other side.
						continue
					end
					local a = giant.position
					local b = other.position
					if math.abs(a.Y - b.Y) > (def.height + otherDef.height) / 2 then
						continue
					end
					local dx = b.X - a.X
					local dz = b.Z - a.Z
					local minDistance = radius + otherDef.radius
					local distanceSq = dx * dx + dz * dz
					if distanceSq >= minDistance * minDistance then
						continue
					end
					local distance = math.sqrt(distanceSq)
					local nx: number, nz: number
					if distance > 1e-4 then
						nx = dx / distance
						nz = dz / distance
					else
						local angle = (giant.id * GOLDEN_RATIO_FRACTION % 1) * 2 * math.pi
						nx = math.cos(angle)
						nz = math.sin(angle)
					end
					local overlap = minDistance - distance
					local otherMind = other.mind
					local otherPlanted = otherMind ~= nil and CrowdBrain.IsStriking(otherMind)
					local shareA = 0
					if large then
						local massA = radius * radius
						local massB = otherDef.radius * otherDef.radius
						shareA = massB / (massA + massB)
						if planted ~= otherPlanted then
							shareA = if planted then 0 else 1
						elseif planted then
							continue
						end
					elseif otherPlanted then
						continue
					end
					local shareB = 1 - shareA
					giant.position = a
						- Vector3.new(nx * overlap * shareA, 0, nz * overlap * shareA)
					other.position = b
						+ Vector3.new(nx * overlap * shareB, 0, nz * overlap * shareB)
				end
			end
		end
	end
end

-- Pushes overlapping living bodies apart, heavier (wider) bodies moving less. Each pair is
-- handled once, by its lower id. A body of `largeRadius` (crowd.largeRadius) or more is large:
-- it is left to `shoulder`, so the crowd around it keeps scanning the cells it would scan
-- without it.
-- Runs right after integrate, which refreshed every enemy's def for this step.
-- P4: a fighting body in windup or attack is planted. Its neighbour takes the whole overlap, and
-- two planted bodies leave each other where they are. Only this pass spares it: a player's hit
-- still shoves and launches it through integrate.
local function separate(largeRadius: number): ()
	local widest = 0
	table.clear(giants)
	for _, enemy in order do
		if enemy.deadAt == nil then
			local radius = enemy.def.radius
			if radius >= largeRadius then
				table.insert(giants, enemy)
			else
				widest = math.max(widest, radius)
			end
		end
	end
	for _, enemy in order do
		if enemy.deadAt ~= nil then
			continue
		end
		local def = enemy.def
		local radius = def.radius
		if radius >= largeRadius then
			continue
		end
		local mind = enemy.mind
		local planted = mind ~= nil and CrowdBrain.IsStriking(mind)
		local cx = math.floor(enemy.position.X / CELL_SIZE) + CELL_OFFSET
		local cz = math.floor(enemy.position.Z / CELL_SIZE) + CELL_OFFSET
		local reach = math.ceil((radius + widest) / CELL_SIZE)
		for ox = -reach, reach do
			for oz = -reach, reach do
				local cell = grid[(cx + ox) * CELL_STRIDE + (cz + oz)]
				if cell == nil then
					continue
				end
				for _, other in cell do
					if other.id <= enemy.id or other.deadAt ~= nil then
						continue
					end
					local otherDef = other.def
					if otherDef.radius >= largeRadius then
						continue
					end
					local a = enemy.position
					local b = other.position
					if math.abs(a.Y - b.Y) > (def.height + otherDef.height) / 2 then
						continue
					end
					local dx = b.X - a.X
					local dz = b.Z - a.Z
					local minDistance = radius + otherDef.radius
					local distanceSq = dx * dx + dz * dz
					if distanceSq >= minDistance * minDistance then
						continue
					end
					local distance = math.sqrt(distanceSq)
					local nx: number, nz: number
					if distance > 1e-4 then
						nx = dx / distance
						nz = dz / distance
					else
						-- Exactly stacked (same spawn point): split along an id-derived angle.
						local angle = (enemy.id * GOLDEN_RATIO_FRACTION % 1) * 2 * math.pi
						nx = math.cos(angle)
						nz = math.sin(angle)
					end
					local overlap = minDistance - distance
					local massA = radius * radius
					local massB = otherDef.radius * otherDef.radius
					local shareA = massB / (massA + massB)
					local otherMind = other.mind
					local otherPlanted = otherMind ~= nil and CrowdBrain.IsStriking(otherMind)
					if planted ~= otherPlanted then
						shareA = if planted then 0 else 1
					elseif planted then
						continue
					end
					local shareB = 1 - shareA
					enemy.position = a
						- Vector3.new(nx * overlap * shareA, 0, nz * overlap * shareA)
					other.position = b
						+ Vector3.new(nx * overlap * shareB, 0, nz * overlap * shareB)
				end
			end
		end
	end
	if #giants > 0 then
		shoulder(widest, largeRadius)
	end
end

-- `clock` = the frame's os.clock(): what the brain times its attacks on.
local function simulate(dt: number, clock: number): ()
	simTime += dt
	local config = Tuning.Get()
	local crowd = config.crowd
	local kinds = crowd.kinds
	local g = gravity()
	local hooks = threatHooks
	CrowdBrain.BeginStep(
		clock,
		boundsCenter.Y,
		g,
		if hooks ~= nil then hooks.shotsAlive() else 0,
		Tuning.FastestMove(config)
	)
	gatherTargets(config.shooting)
	-- The places each kind holds against each player are counted before anyone thinks, so a
	-- body walked late in the step never finds its own place taken by one that started after it.
	for _, enemy in order do
		local mind = enemy.mind
		if mind ~= nil and enemy.deadAt == nil then
			CrowdBrain.Commit(enemy, mind)
		end
	end

	table.clear(expired)
	for _, enemy in order do
		local deadAt = enemy.deadAt
		if deadAt ~= nil and simTime - deadAt >= crowd.deadSeconds then
			table.insert(expired, enemy)
			continue
		end
		integrate(enemy, currentDef(enemy, kinds), crowd, dt, g)
	end
	for _, enemy in expired do
		removeRecord(enemy)
	end

	gridRebuild()
	separate(crowd.largeRadius)
	for _, enemy in order do
		if enemy.deadAt == nil then
			clampToBounds(enemy, currentDef(enemy, kinds).radius)
		end
	end
	-- Rebuilt after separation so Query's cells match the positions it reads.
	gridRebuild()
end

local function flushLifecycle(): ()
	if #pendingRemoves > 0 then
		fireAll(REMOVE_EVENT, pendingRemoves)
		pendingRemoves = {}
	end
	if #pendingSpawnOrder > 0 then
		local batch: { Types.CrowdSpawnInfo } = {}
		for _, id in pendingSpawnOrder do
			local enemy = enemies[id]
			if pendingSpawnSet[id] and enemy ~= nil then
				-- Cleared as it goes so an id queued twice is announced once.
				pendingSpawnSet[id] = nil
				table.insert(batch, enemy.spawnInfo)
			end
		end
		table.clear(pendingSpawnOrder)
		table.clear(pendingSpawnSet)
		if #batch > 0 then
			fireAll(SPAWN_EVENT, batch)
		end
	end
end

local function sendSnapshot(serverTime: number): ()
	if #order == 0 or #Players:GetPlayers() == 0 then
		return
	end
	local count = 0
	for _, enemy in order do
		local entry = enemy.entry
		local mind = enemy.mind
		local state: Types.CrowdState = enemy.state
		entry.position = enemy.position
		entry.yaw = enemy.yaw
		entry.state = state
		-- While the plate lasts the bar is the plate's: HP cannot change under it.
		local plated = enemy.plate > 0
		entry.plated = plated
		entry.hpFraction = if plated
			then enemy.plate / enemy.plateMax
			elseif enemy.maxHp > 0 then enemy.hp / enemy.maxHp
			else 0
		-- The attack's index rides with the three states that draw it. Under a stagger or a hop
		-- it stays set only while the windup or the thrust runs on underneath (an elite's
		-- survives a light hit): 0 there tells the client it was cancelled or is over.
		local drawn = state == "windup" or state == "attack" or state == "recover"
		local overlaid = state == "stagger" or state == "airborne"
		entry.attack = if mind ~= nil and (drawn or (overlaid and CrowdBrain.IsStriking(mind)))
			then mind.attack
			else 0
		count += 1
		chunk[count] = entry
		if count == CrowdCodec.MAX_ENTRIES then
			RemoteService.FireAllUnreliable(
				SNAPSHOT_EVENT,
				CrowdCodec.Encode(chunk, boundsCenter, serverTime)
			)
			table.clear(chunk)
			count = 0
		end
	end
	if count > 0 then
		RemoteService.FireAllUnreliable(
			SNAPSHOT_EVENT,
			CrowdCodec.Encode(chunk, boundsCenter, serverTime)
		)
		table.clear(chunk)
	end
end

-- Where every impact the brain raised goes after the step. A summon is the crowd's own
-- business; every other shape is the threat hooks'.
local dispatch: (strike: CrowdBrain.Strike) -> ()

local function stepInterval(): number
	-- snapshotHz is the step rate as well: one step, one snapshot. Clamped (to the bounds the
	-- renderer shares) so a bad slider value can neither stall the crowd nor flood the network.
	local hz = Tuning.Get().crowd.snapshotHz
	if typeof(hz) ~= "number" or not isFinite(hz) then
		hz = CrowdCodec.MIN_HZ
	end
	return 1 / math.clamp(hz, CrowdCodec.MIN_HZ, CrowdCodec.MAX_HZ)
end

-- One stepping Heartbeat's cost into the ring; every `perf.every` seconds, one line over the
-- steps since the last one. Only steps with a living body count: an empty field (lobby,
-- breather, summary) costs nothing worth reading, and would both print a line every window and
-- drag the median down. A window starts at its first counted step.
local function notePerf(clock: number, ms: number): ()
	if perf.every <= 0 or aliveCount == 0 then
		return
	end
	if perf.count == 0 then
		perf.since = clock
		perf.peak = 0
		perf.head = 0
	end
	perf.head = perf.head % PERF_RING + 1
	perf.ring[perf.head] = ms
	perf.count += 1
	perf.peak = math.max(perf.peak, aliveCount)
	if clock - perf.since < perf.every then
		return
	end
	local samples = math.min(perf.count, PERF_RING)
	local sorted = perf.sorted
	table.move(perf.ring, 1, samples, 1, sorted)
	for index = samples + 1, #sorted do
		sorted[index] = nil
	end
	table.sort(sorted)
	local p50 = sorted[math.max(math.ceil(samples * 0.5), 1)]
	local p95 = sorted[math.max(math.ceil(samples * 0.95), 1)]
	print(
		string.format(
			"[Perf] crowd step p50 %.2f ms p95 %.2f ms (%d steps, peak alive %d)",
			p50,
			p95,
			perf.count,
			perf.peak
		)
	)
	perf.count = 0
end

local function onHeartbeat(deltaTime: number): ()
	local interval = stepInterval()
	accumulator = math.min(accumulator + deltaTime, interval * MAX_CATCHUP_STEPS)
	if accumulator < interval then
		return
	end
	-- Both clocks are read once, at the same moment, for the whole frame: the brain times its
	-- attacks on `started` and the snapshot is stamped `serverNow`. A windup that starts in any
	-- step of this frame therefore lands exactly `windup` after the stamp of the snapshot that
	-- first shows it, which is how every client times the tell.
	local started = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	while accumulator >= interval do
		accumulator -= interval
		simulate(interval, started)
	end
	flushLifecycle()
	sendSnapshot(serverNow)
	-- Last, so a failing hook can never hold back the crowd's own stream.
	CrowdBrain.DrainStrikes(dispatch)
	local hooks = threatHooks
	if hooks ~= nil then
		hooks.step(started)
	end
	lastStepMs = (os.clock() - started) * 1000
	notePerf(started, lastStepMs)
end

-- A late joiner learns every enemy already announced; ones still pending go out in the next
-- batch to everyone, the joiner included.
local function onPlayerAdded(player: Player): ()
	local batch: { Types.CrowdSpawnInfo } = {}
	for _, enemy in order do
		if not pendingSpawnSet[enemy.id] then
			table.insert(batch, enemy.spawnInfo)
		end
	end
	if #batch > 0 then
		RemoteService.FireClient(player, SPAWN_EVENT, batch)
	end
end

local function ensureRunning(): ()
	if running then
		return
	end
	running = true
	RunService.Heartbeat:Connect(onHeartbeat)
	Players.PlayerAdded:Connect(onPlayerAdded)
end

local CrowdService = {}

-- center = the arena origin: the floor's top face and the XZ centre. halfSize.X/Z = the
-- footprint's half extents (bodies stay wholly inside); halfSize.Y = the highest a launch can
-- carry a body above the floor. center is also the CrowdCodec origin of every snapshot, so the
-- client must decode against the same point (every arena is built at the world origin).
function CrowdService.SetBounds(center: Vector3, halfSize: Vector3): ()
	if not isFiniteVector(center) or not isFiniteVector(halfSize) then
		warn("[CrowdService] SetBounds ignored: non-finite bounds")
		return
	end
	boundsCenter = center
	boundsHalf = Vector3.new(math.abs(halfSize.X), math.abs(halfSize.Y), math.abs(halfSize.Z))
	CrowdBrain.SetArena(boundsCenter, boundsHalf)
	ensureRunning()
end

-- Until they are set, fighting enemies go for every living player and their impacts are dropped.
function CrowdService.SetThreatHooks(hooks: ThreatHooks): ()
	threatHooks = hooks
end

-- P5 ruling 10: the run's scales, read by every Spawn from here on (summons included). A
-- non-finite or negative scale keeps its old value. The range never calls this: { 1, 1 }.
function CrowdService.SetScales(wanted: CrowdScales): ()
	local hp = wanted.hp
	local plate = wanted.plate
	if typeof(hp) ~= "number" or not isFinite(hp) or hp < 0 then
		warn(`[CrowdService] SetScales: bad hp scale {hp}; kept {scales.hp}`)
		hp = scales.hp
	end
	if typeof(plate) ~= "number" or not isFinite(plate) or plate < 0 then
		warn(`[CrowdService] SetScales: bad plate scale {plate}; kept {scales.plate}`)
		plate = scales.plate
	end
	scales = { hp = hp, plate = plate }
end

-- Ruling 26: Main turns the [Perf] line on in Studio with Combat.json debug.perfLogSeconds; 0 or
-- less turns it off. (This module reads no Combat.json and asks nothing of RunService itself.)
function CrowdService.SetPerfLog(seconds: number): ()
	perf.every = if isFinite(seconds) and seconds > 0 then seconds else 0
	perf.count = 0
end

-- Returns the new id, or 0 when refused (unknown kind, non-finite position, maxAlive reached).
-- anchor = the point idle/walk/strafe/jump behaviours hold to; defaults to the spawn position.
-- behaviour `fight` runs the kind's brain (CrowdBrain); a kind without one stands.
-- P5: maxHp = def.hp x scales.hp x hpMult (a boss body's party factor), plate = def.plate x
-- scales.plate.
function CrowdService.Spawn(
	kind: string,
	position: Vector3,
	behaviour: string,
	anchor: Vector3?,
	hpMult: number?
): number
	ensureRunning()
	local config = Tuning.Get()
	local def = config.crowd.kinds[kind]
	if def == nil then
		if not warnedKinds[kind] then
			warnedKinds[kind] = true
			warn(`[CrowdService] unknown crowd kind "{kind}"; spawn refused`)
		end
		return 0
	end
	if not isFiniteVector(position) or (anchor ~= nil and not isFiniteVector(anchor)) then
		return 0
	end
	if aliveCount >= config.crowd.maxAlive then
		return 0
	end
	local id = nextId()
	if id == 0 then
		return 0
	end
	local resolvedBehaviour: Behaviour = BEHAVIOURS[behaviour] or "idle"
	if BEHAVIOURS[behaviour] == nil then
		warn(`[CrowdService] unknown behaviour "{behaviour}"; using idle`)
	end
	local bodyMult = if hpMult ~= nil and isFinite(hpMult) and hpMult > 0 then hpMult else 1
	local maxHp = math.max(def.hp * scales.hp * bodyMult, 1)
	local plate = math.max((def.plate or 0) * scales.plate, 0)
	local phase = id * GOLDEN_RATIO_FRACTION % 1
	local start = Vector3.new(position.X, math.max(position.Y, boundsCenter.Y), position.Z)
	local enemy: Enemy = {
		id = id,
		kind = kind,
		behaviour = resolvedBehaviour,
		def = def,
		anchor = anchor or start,
		position = start,
		velocity = Vector3.zero,
		knock = Vector3.zero,
		vy = 0,
		yaw = 0,
		hp = maxHp,
		maxHp = maxHp,
		plate = plate,
		plateMax = plate,
		state = "idle",
		staggerUntil = 0,
		deadAt = nil,
		phase = phase,
		leg = if id % 2 == 0 then 1 else -1,
		nextHopAt = simTime
			+ phase * math.max(config.crowd.behaviour.hopPeriod, MIN_PERIOD_SECONDS),
		index = #order + 1,
		entry = {
			id = id,
			position = start,
			yaw = 0,
			state = "idle",
			hpFraction = 1,
			plated = plate > 0,
			attack = 0,
		},
		spawnInfo = { id = id, kind = kind, maxHp = maxHp },
		mind = if resolvedBehaviour == "fight" then CrowdBrain.NewMind(os.clock()) else nil,
		summoner = nil,
		summoned = 0,
		guard = 0,
		place = 0,
		damageBy = {},
	}
	clampToBounds(enemy, def.radius)
	enemies[id] = enemy
	order[enemy.index] = enemy
	aliveCount += 1
	pendingSpawnSet[id] = true
	table.insert(pendingSpawnOrder, id)
	gridInsert(enemy)
	return id
end

-- A `summon` impact. The attack's `count` even places lie on a circle of `radius` round the
-- summoner, turned so that none lies straight behind it: the first on its facing for an odd
-- count, half a step off it for an even one. (A body that rises straight behind its summoner
-- walks into its back on the way to the player and, head on, never gets round it: it would
-- shove a summoner that keeps its distance, or stay stuck behind one nothing moves.) A call
-- tops the summoner's living summons up to `count`:
-- it raises one body of the `summon` kind on a place none of them rose on, as many as are
-- missing, and none when all are alive (the attack plays all the same). When crowd.maxAlive
-- leaves room for fewer, those are spread evenly through the free places. Each is kept inside
-- the arena, fights (so it waits out threat.spawnGrace like any spawn) and is announced with
-- the next batch. A summoner that died before the drain raises nothing.
local function summon(strike: CrowdBrain.Strike): ()
	local summoner = enemies[strike.bodyId]
	local attack = strike.def
	local kind = attack.summon
	if summoner == nil or summoner.deadAt ~= nil or kind == nil then
		return
	end
	local count = math.floor(attack.count or 0)
	if not (count > 0) then
		return
	end
	-- Which places its living summons hold, and how many of them there are.
	local held: { [number]: boolean } = {}
	local living = 0
	if summoner.summoned > 0 then
		for _, other in order do
			if other.summoner == summoner and other.deadAt == nil then
				living += 1
				held[other.place] = true
			end
		end
	end
	local free: { number } = {}
	for place = 0, count - 1 do
		if not held[place] then
			table.insert(free, place)
		end
	end
	local room = math.floor(Tuning.Get().crowd.maxAlive) - aliveCount
	local raise = math.min(count - living, room, #free)
	if not (raise > 0) then
		return
	end
	local radius = math.max(attack.radius or 0, 0)
	local centre = summoner.position
	local turned = if count % 2 == 0 then 0.5 else 0
	for index = 0, raise - 1 do
		-- All the free places when every missing body fits; evenly through them otherwise.
		local place = free[index * #free // raise + 1]
		-- Yaw as yawToward has it: 0 looks down -Z.
		local angle = summoner.yaw + (place + turned) / count * 2 * math.pi
		local spot = Vector3.new(
			centre.X - math.sin(angle) * radius,
			boundsCenter.Y,
			centre.Z - math.cos(angle) * radius
		)
		local risen = enemies[CrowdService.Spawn(kind, spot, "fight")]
		if risen ~= nil then
			risen.summoner = summoner
			risen.place = place
			summoner.summoned += 1
			summoner.guard += 1
			-- Its spawn names its summoner: the client's exact count of a boss's living guard.
			risen.spawnInfo.summonerId = summoner.id
		end
	end
end

function dispatch(strike: CrowdBrain.Strike): ()
	if strike.def.shape == "summon" then
		summon(strike)
		return
	end
	local hooks = threatHooks
	if hooks ~= nil then
		hooks.impact(strike)
	end
end

-- An enemy is dead or removed. What it summoned is removed with it, and when it is a boss
-- (`whole`) its own attacks end too: nothing it or its summons had queued, in the air or on
-- the run lands after this.
local function dismiss(enemy: Enemy, whole: boolean): ()
	if enemy.summoned == 0 and not whole then
		return
	end
	local ids: { [number]: boolean } = {}
	if whole then
		ids[enemy.id] = true
	end
	if enemy.summoned > 0 then
		enemy.summoned = 0
		-- Backwards: a removal moves the last record into the freed slot.
		for index = #order, 1, -1 do
			local other = order[index]
			if other.summoner == enemy then
				ids[other.id] = true
				removeRecord(other)
			end
		end
	end
	CrowdBrain.Recall(ids)
	local hooks = threatHooks
	if hooks ~= nil then
		hooks.gone(ids)
	end
end

-- Ends an enemy at once (no dead state, no OnKilled): for set changes and resets.
function CrowdService.Remove(id: number): ()
	local enemy = enemies[id]
	if enemy ~= nil then
		dismiss(enemy, true)
		removeRecord(enemy)
	end
end

-- Every enemy goes, and with them the impacts their brains had still queued. (Whoever holds
-- the threat hooks clears what is already in the air: VitalsService.OnSetLoaded.)
function CrowdService.Clear(): ()
	for index = #order, 1, -1 do
		removeRecord(order[index])
	end
	CrowdBrain.DrainStrikes(nil)
end

-- Broadphase: every living enemy whose body (body sphere and head sphere) may reach within
-- `radius` of `center`. Callers run the exact HitShapes test on Get(id).
function CrowdService.Query(center: Vector3, radius: number): { number }
	local ids: { number } = {}
	if not isFiniteVector(center) or not isFinite(radius) or radius < 0 then
		return ids
	end
	local kinds = Tuning.Get().crowd.kinds
	local reachPad = 0
	for _, def in kinds do
		reachPad = math.max(reachPad, def.radius, def.height / 2)
	end

	local function consider(enemy: Enemy): ()
		if enemy.deadAt ~= nil or enemies[enemy.id] ~= enemy then
			return
		end
		local def = currentDef(enemy, kinds)
		-- Bounding sphere of the whole body, centred at half height.
		local reach = radius + math.max(def.radius, def.height / 2)
		local offset = enemy.position + Vector3.new(0, def.height / 2, 0) - center
		if offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z <= reach * reach then
			table.insert(ids, enemy.id)
		end
	end

	local span = radius + reachPad
	local minX = math.floor((center.X - span) / CELL_SIZE)
	local maxX = math.floor((center.X + span) / CELL_SIZE)
	local minZ = math.floor((center.Z - span) / CELL_SIZE)
	local maxZ = math.floor((center.Z + span) / CELL_SIZE)
	-- A long ray's query covers more cells than there are enemies; scanning the list is cheaper.
	if (maxX - minX + 1) * (maxZ - minZ + 1) > #order then
		for _, enemy in order do
			consider(enemy)
		end
		return ids
	end
	for cx = minX, maxX do
		for cz = minZ, maxZ do
			local cell = grid[(cx + CELL_OFFSET) * CELL_STRIDE + (cz + CELL_OFFSET)]
			if cell ~= nil then
				for _, enemy in cell do
					consider(enemy)
				end
			end
		end
	end
	return ids
end

function CrowdService.Get(id: number): EnemyView?
	local enemy = enemies[id]
	if enemy == nil then
		return nil
	end
	return {
		position = enemy.position,
		velocity = enemy.velocity,
		kind = enemy.kind,
		hp = enemy.hp,
		maxHp = enemy.maxHp,
		state = enemy.state,
	}
end

-- The death path, for a killing blow and for KillAll alike: the body lies dead for deadSeconds,
-- leaves its summoner's guard, and a boss takes its fight with it. Every kill callback is handed
-- what the run pays for (ruling 14), each on its own thread.
local function die(enemy: Enemy, def: Types.CrowdKindDef, crowd: CrowdConfig, byUserId: number): ()
	local mind = enemy.mind
	if mind ~= nil then
		-- Ruling 22: a blow whose impact time has already come still lands.
		CrowdBrain.OnKilled(enemy, mind, def, crowd, os.clock())
	end
	enemy.hp = 0
	enemy.deadAt = simTime
	enemy.state = "dead"
	aliveCount -= 1
	local summoner = enemy.summoner
	if summoner ~= nil then
		summoner.guard = math.max(summoner.guard - 1, 0)
	end
	-- A boss's death is the end of its fight: its summons, and whatever it had in the air.
	local boss = def.boss == true
	dismiss(enemy, boss)
	if #killCallbacks == 0 then
		return
	end
	local info: CrowdKillInfo = {
		id = enemy.id,
		kind = enemy.kind,
		boss = boss,
		position = enemy.position,
		byUserId = byUserId,
		damageBy = enemy.damageBy,
	}
	for _, callback in killCallbacks do
		task.spawn(callback, enemy.id, byUserId, info)
	end
end

-- Returns (dealt, killed, verdict). dealt = amount after flat armour, not capped at the
-- remaining HP (the number the player sees). push = horizontal velocity change in studs/s (its
-- Y is ignored); launch = apex height in studs. Both scale by the kind's knockbackMult, as does
-- the stagger. A dead or unknown id takes nothing, and an unknown one says so (`gone`: a strike
-- must not book a body its own killing blow removed). A fighting enemy's windup may be cancelled by
-- the hit (CrowdBrain.OnHit); push, launch and stagger apply to it as to any other, except in a
-- brute's charge, which only the damage reaches.
-- The plate (wave 2), while it lasts: a hit under crowd.heavyHit is blocked and does nothing at
-- all (dealt 0). A heavy hit takes its amount off the plate, never off HP (dealt = that amount,
-- the excess is lost), and otherwise acts as any hit; the one that empties the plate leaves the
-- enemy reeling for crowd.plateBreakSeconds, whatever its knockbackMult, and cancels the windup
-- it was in, whatever that attack's `interrupt`. After that the kind's armor applies.
-- P5 ruling 9: `amount` is the attacker's tier-1 number and `scale` (nil = 1) their tier's
-- multiplier. heavyHit, the plate, the interrupt and armour all judge `amount`; only the HP loss
-- is scaled, so a plate hit returns its unscaled plate loss and an HP hit its scaled loss.
-- damageBy books the HP actually removed, capped at what was left (plate loss is not booked).
function CrowdService.Damage(
	id: number,
	amount: number,
	byUserId: number,
	push: Vector3?,
	launch: number?,
	scale: number?
): (number, boolean, Verdict?)
	local enemy = enemies[id]
	if enemy == nil then
		return 0, false, "gone"
	end
	if enemy.deadAt ~= nil then
		return 0, false, nil
	end
	local crowd = Tuning.Get().crowd
	local def = currentDef(enemy, crowd.kinds)
	local mind = enemy.mind
	local plated = enemy.plate > 0
	if
		plated
		and def.guarded == true
		and (enemy.guard > 0 or (mind ~= nil and CrowdBrain.OwesCall(mind, def)))
	then
		-- Stop 3: its plate takes nothing, heavy or not, from the moment it spawns until its
		-- guard has been called and is dead. A `guarded` kind with no summon attack, or one
		-- that does not fight, is never guarded (nothing ships that way). Judged before the
		-- amount is looked at: a hit of 0 says `guarded` too, or a client would read the plain
		-- hit it got instead as the guard being gone.
		return 0, false, "guarded"
	end
	if not isFinite(amount) or amount <= 0 then
		return 0, false, nil
	end
	local verdict: Verdict? = nil
	local dealt: number
	if plated then
		if amount < crowd.heavyHit then
			return 0, false, "blocked"
		end
		enemy.plate = math.max(enemy.plate - amount, 0)
		verdict = if enemy.plate > 0 then "plate" else "broke"
		dealt = amount
	else
		-- Armour is a flat per-hit reduction (lead ruling, P1), floored so a weak hit still chips.
		local lossScale = if scale ~= nil and isFinite(scale) and scale >= 0 then scale else 1
		dealt = math.max(
			amount - math.max(def.armor, 0),
			amount * math.clamp(crowd.armorFloor, 0, 1)
		) * lossScale
	end
	local mult = math.max(def.knockbackMult, 0)
	-- Nothing moves, staggers or stops a charge, short of the blow that kills the brute.
	local charging = mind ~= nil
		and CrowdBrain.IsCharging(mind)
		and (plated or enemy.hp - dealt > 0)
	if charging then
		mult = 0
	end

	if push ~= nil and isFiniteVector(push) and mult > 0 then
		local shove = Vector3.new(push.X, 0, push.Z) * mult
		if shove.Magnitude > 0 then
			local knock = enemy.knock + shove
			local knockMax = math.max(crowd.knockMax, 0)
			if knock.Magnitude > knockMax then
				knock = if knockMax > 0 then knock.Unit * knockMax else Vector3.zero
			end
			enemy.knock = knock
			-- A shoved body turns to face the blow.
			enemy.yaw = yawToward(-shove)
		end
	end
	if launch ~= nil and isFinite(launch) and launch > 0 and mult > 0 then
		enemy.vy = math.max(enemy.vy, launchSpeed(launch * mult))
	end

	if not plated then
		local removed = math.min(dealt, enemy.hp)
		if removed > 0 then
			enemy.damageBy[byUserId] = (enemy.damageBy[byUserId] or 0) + removed
		end
		enemy.hp -= dealt
	end
	if enemy.hp <= 0 then
		die(enemy, def, crowd, byUserId)
		return dealt, true, verdict
	end
	local stagger = math.max(crowd.staggerSeconds, 0) * mult
	local reels = verdict == "broke" and not charging
	if reels then
		-- The opening: it reels for the config's time whatever its knockbackMult, a body that
		-- no ordinary hit moves or staggers included (Stop 3: a plate break always reels). Only
		-- a charge under way runs on.
		stagger = math.max(stagger, math.max(crowd.plateBreakSeconds, 0))
	end
	enemy.staggerUntil = math.max(enemy.staggerUntil, simTime + stagger)
	if mind ~= nil then
		-- `amount`, not `dealt`: a heavy hit is judged before armour (ruling 10).
		CrowdBrain.OnHit(mind, def, amount, stagger > 0, reels, crowd.heavyHit, os.clock())
	end
	return dealt, false, verdict
end

-- Callbacks run on their own threads, so they may yield without stalling the caller. A body
-- removed without a kill (a boss's summons at its death, Remove, Clear) calls none of them.
function CrowdService.OnKilled(callback: KillCallback): ()
	table.insert(killCallbacks, callback)
end

-- Every living body dies through the death path, credited to `byUserId` (0 = nobody), and the
-- kill callbacks pay for each. Bodies a dying boss takes with it are removed, not killed.
-- Returns how many died.
function CrowdService.KillAll(byUserId: number): number
	local crowd = Tuning.Get().crowd
	local living: { Enemy } = {}
	for _, enemy in order do
		if enemy.deadAt == nil then
			table.insert(living, enemy)
		end
	end
	local killed = 0
	for _, enemy in living do
		if enemies[enemy.id] == enemy and enemy.deadAt == nil then
			die(enemy, currentDef(enemy, crowd.kinds), crowd, byUserId)
			killed += 1
		end
	end
	return killed
end

function CrowdService.AliveCount(): number
	return aliveCount
end

-- Wall time of the last Heartbeat that stepped: simulation, lifecycle batches and snapshot
-- encoding and sending, in milliseconds.
function CrowdService.StepMs(): number
	return lastStepMs
end

return CrowdService
