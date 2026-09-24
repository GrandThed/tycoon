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

type Behaviour = "idle" | "walk" | "strafe" | "jump" | "chase"

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
}

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

local SPAWN_EVENT = "CrowdSpawn"
local SNAPSHOT_EVENT = "CrowdSnapshot"
local REMOVE_EVENT = "CrowdRemove"

-- Wire ids are u16 (CrowdCodec); 0 is the "refused" return of Spawn.
local MAX_ID = 65535
-- snapshotHz is the step rate as well: one step, one snapshot. Clamped so a bad slider value
-- can neither stall the crowd nor flood the network.
local MIN_STEP_HZ = 2
local MAX_STEP_HZ = 60
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
-- its neighbourhood to cover the widest living body, so a boss still meets everything it overlaps.
local CELL_SIZE = 4
local CELL_OFFSET = 32768
local CELL_STRIDE = 65536
-- How a displaced dummy returns: pace as a share of its speed, and the arrival slack. The
-- tunable motion shapes are crowd.behaviour in ProvingGrounds.json.
local HOME_SPEED_MULT = 0.5
local HOME_TOLERANCE = 0.75
local WALK_SPEED_MULT = 0.6
local GOLDEN_RATIO_FRACTION = 0.6180339887

local BEHAVIOURS: { [string]: Behaviour } = {
	idle = "idle",
	walk = "walk",
	strafe = "strafe",
	jump = "jump",
	chase = "chase",
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

local killCallbacks: { (id: number, byUserId: number) -> () } = {}
local warnedKinds: { [string]: boolean } = {}

-- Scratch tables reused every step so the loop allocates nothing per enemy.
local targets: { Vector3 } = {}
local expired: { Enemy } = {}
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
		if dx * dx + dz * dz <= HOME_TOLERANCE * HOME_TOLERANCE then
			enemy.leg = -enemy.leg
			goal = enemy.anchor + Vector3.new(0, 0, enemy.leg * shapes.walkLength / 2)
		end
		return seek(position, goal, speed * WALK_SPEED_MULT, 0, dt)
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
	return seek(position, enemy.anchor, speed * HOME_SPEED_MULT, HOME_TOLERANCE, dt)
end

local function gatherTargets(): ()
	table.clear(targets)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0 then
			table.insert(targets, root.Position)
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
	local target = if alive then nearestTarget(position) else nil

	local desired = Vector3.zero
	if alive and grounded and simTime >= enemy.staggerUntil then
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
		-- Strafers and idlers watch the player; walkers and chasers face where they go.
		if moving and enemy.behaviour ~= "strafe" then
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
	elseif moving then
		enemy.state = "move"
	else
		enemy.state = "idle"
	end
end

-- Pushes overlapping living bodies apart, heavier (wider) bodies moving less. Each pair is
-- handled once, by its lower id.
-- Runs right after integrate, which refreshed every enemy's def for this step.
local function separate(): ()
	local widest = 0
	for _, enemy in order do
		if enemy.deadAt == nil then
			widest = math.max(widest, enemy.def.radius)
		end
	end
	for _, enemy in order do
		if enemy.deadAt ~= nil then
			continue
		end
		local def = enemy.def
		local radius = def.radius
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
					local shareB = 1 - shareA
					enemy.position = a
						- Vector3.new(nx * overlap * shareA, 0, nz * overlap * shareA)
					other.position = b
						+ Vector3.new(nx * overlap * shareB, 0, nz * overlap * shareB)
				end
			end
		end
	end
end

local function simulate(dt: number): ()
	simTime += dt
	local crowd = Tuning.Get().crowd
	local kinds = crowd.kinds
	local g = gravity()
	gatherTargets()

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
	separate()
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

local function sendSnapshot(): ()
	if #order == 0 or #Players:GetPlayers() == 0 then
		return
	end
	local serverTime = Workspace:GetServerTimeNow()
	local count = 0
	for _, enemy in order do
		local entry = enemy.entry
		entry.position = enemy.position
		entry.yaw = enemy.yaw
		entry.state = enemy.state
		entry.hpFraction = if enemy.maxHp > 0 then enemy.hp / enemy.maxHp else 0
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

local function stepInterval(): number
	local hz = Tuning.Get().crowd.snapshotHz
	if typeof(hz) ~= "number" or not isFinite(hz) then
		hz = MIN_STEP_HZ
	end
	return 1 / math.clamp(hz, MIN_STEP_HZ, MAX_STEP_HZ)
end

local function onHeartbeat(deltaTime: number): ()
	local interval = stepInterval()
	accumulator = math.min(accumulator + deltaTime, interval * MAX_CATCHUP_STEPS)
	if accumulator < interval then
		return
	end
	local started = os.clock()
	while accumulator >= interval do
		accumulator -= interval
		simulate(interval)
	end
	flushLifecycle()
	sendSnapshot()
	lastStepMs = (os.clock() - started) * 1000
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
	ensureRunning()
end

-- Returns the new id, or 0 when refused (unknown kind, non-finite position, maxAlive reached).
-- anchor = the point idle/walk/strafe/jump behaviours hold to; defaults to the spawn position.
function CrowdService.Spawn(
	kind: string,
	position: Vector3,
	behaviour: string,
	anchor: Vector3?
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
	local maxHp = math.max(def.hp, 1)
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
		state = "idle",
		staggerUntil = 0,
		deadAt = nil,
		phase = phase,
		leg = if id % 2 == 0 then 1 else -1,
		nextHopAt = simTime
			+ phase * math.max(config.crowd.behaviour.hopPeriod, MIN_PERIOD_SECONDS),
		index = #order + 1,
		entry = { id = id, position = start, yaw = 0, state = "idle", hpFraction = 1 },
		spawnInfo = { id = id, kind = kind, maxHp = maxHp },
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

-- Ends an enemy at once (no dead state, no OnKilled): for set changes and resets.
function CrowdService.Remove(id: number): ()
	local enemy = enemies[id]
	if enemy ~= nil then
		removeRecord(enemy)
	end
end

function CrowdService.Clear(): ()
	for index = #order, 1, -1 do
		removeRecord(order[index])
	end
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

-- Returns (dealt, killed). dealt = amount after flat armour, not capped at the remaining HP (the
-- number the player sees). push = horizontal velocity change in studs/s (its Y is ignored);
-- launch = apex height in studs. Both scale by the kind's knockbackMult, as does the stagger.
-- A dead or unknown id takes nothing.
function CrowdService.Damage(
	id: number,
	amount: number,
	byUserId: number,
	push: Vector3?,
	launch: number?
): (number, boolean)
	local enemy = enemies[id]
	if enemy == nil or enemy.deadAt ~= nil or not isFinite(amount) or amount <= 0 then
		return 0, false
	end
	local crowd = Tuning.Get().crowd
	local def = currentDef(enemy, crowd.kinds)
	-- Armour is a flat per-hit reduction (lead ruling, P1), floored so a weak hit still chips.
	local dealt =
		math.max(amount - math.max(def.armor, 0), amount * math.clamp(crowd.armorFloor, 0, 1))
	local mult = math.max(def.knockbackMult, 0)

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

	enemy.hp -= dealt
	if enemy.hp <= 0 then
		enemy.hp = 0
		enemy.deadAt = simTime
		enemy.state = "dead"
		aliveCount -= 1
		for _, callback in killCallbacks do
			task.spawn(callback, id, byUserId)
		end
		return dealt, true
	end
	enemy.staggerUntil =
		math.max(enemy.staggerUntil, simTime + math.max(crowd.staggerSeconds, 0) * mult)
	return dealt, false
end

-- Callbacks run on their own threads, so they may yield without stalling the caller.
function CrowdService.OnKilled(callback: (id: number, byUserId: number) -> ()): ()
	table.insert(killCallbacks, callback)
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
