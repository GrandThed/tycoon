--!strict
-- Enemy rigs and their AI (docs/INTERFACES.md "C1 contracts" -> "Enemy models", "C2.5 + C3
-- contracts" -> "Combat server"). Everything an enemy is lives here: the model, the steering, the
-- telegraphed attacks, the reactions to being hit, the ragdoll, its HP and who has damaged it.
--
-- Rules that shape the whole module:
-- * Enemies NEVER damage a Humanoid directly through touch or physics. Every point of damage in
--   both directions goes through CombatService, which is the only place god mode, contribution
--   tracking and kill credit are applied.
-- * This service sits at the BOTTOM of the combat boot order, so it requires none of
--   ArenaService/CombatService/WaveService. They hand it the party roster, the damage sink, the
--   effect feed and the summon queue through SetHooks/SetSummonHandler, which keeps requires acyclic.
-- * Nothing in the AI tick may yield (C1 review lesson). Attacks are a state machine read on the
--   tick rather than task.delay closures, and pathfinding runs on its own spawned threads.
-- * No RNG anywhere in a run: strafe directions, spawn nudges and attack offsets derive from ids.
--
-- No model is required to ship: a cloned placeholder R15 rig (and, if even that fails, a block
-- rig built in code) is the default, recoloured per enemy key from the mission's EnemyDef.color
-- or Combat.json enemy.defaultColor / bossColor.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

-- Two enemies handed the same rim spawn would arrive inside each other, so each one is nudged
-- around a small ring by its own id.
local SPAWN_RING_RADIUS = 3.5
local GOLDEN_ANGLE = 2.39996
local ENEMY_FOLDER_NAME = "Enemies"
-- Degrade values used only when Combat.json is missing (the place then never starts a wave).
local DEFAULT_TICK_HZ = 10
local DEFAULT_CORPSE_SECONDS = 0.6
local DEFAULT_RAGDOLL_SECONDS = 1.2
-- Procedural poses. Server writes to a Motor6D C0 replicate for free, so every client sees the
-- tell without a remote; loaded animations drive Motor6D.Transform, so the two stack cleanly.
local WINDUP_ARM_DEGREES = -70
local SLAM_ARMS_DEGREES = 160
local CHARGE_LEAN_DEGREES = -22
local STAGGER_LEAN_DEGREES = 16
local WALK_BOB_DEGREES = 6
local WALK_BOB_HZ = 2.2
-- Spawn clearance above the arena floor, so a rig never starts inside it.
local SPAWN_LIFT = 3
-- The ArenaLayout contract puts the floor's top face at y = 0, so anything this far below it
-- has fallen off the map and is on its way to FallenPartsDestroyHeight. Reaped so it stops
-- counting as alive.
local VOID_Y = -20

-- Steering geometry. These shape how the crowd moves, not how hard it hits; the tunables Ben
-- balances (radii, slot count, speeds, windups) are in Combat.json `ai`.
-- A slotted attacker stands this fraction of its reach from the target, so it is in range with
-- a little slack for the target drifting.
local SLOT_REACH_FRACTION = 0.75
local SLOT_MIN_RING = 2.5
-- How far round the hold ring a circling enemy aims per tick of steering (radians).
local CIRCLE_STEP_RADIANS = 0.6
-- Beyond holdRadius + this, an enemy runs straight in at full speed instead of strafing.
local APPROACH_MARGIN = 8
-- A slot holder that ends up this far outside the hold ring (knocked back) loses the slot.
local SLOT_KEEP_MARGIN = 8
-- Retarget only when another member is this much closer, so enemies do not flip between two
-- players standing side by side (which would also churn the attack slots).
local RETARGET_HYSTERESIS = 4
-- Every enemy flips its strafe direction on its own period, so a ring never rotates in lockstep.
local STRAFE_FLIP_SECONDS = 2.5
local STRAFE_FLIP_SPREAD = 0.7
-- Moving at or above this fraction of full speed plays the run animation, below it the walk.
local RUN_SPEED_FRACTION = 0.85
-- Closer than this to the steered point counts as standing (idle animation, no bob).
local ARRIVE_STUDS = 0.6
-- A charger starts its windup only inside this fraction of chargeDistance, so the dash reaches.
local CHARGE_TRIGGER_FRACTION = 0.9
local MEMBER_RADIUS = 1.2
-- Grace on top of the ideal dash time before a dash blocked by an obstacle is ended.
local DASH_TIMEOUT_PAD = 0.35
-- A boss slam starts when a member is within its radius plus this.
local SLAM_TRIGGER_MARGIN = 2
local DEFAULT_SLAM_RADIUS = 10
local DEFAULT_SUMMON_COUNT = 2
-- A cancelled windup (staggered) pushes the next attack back by this fraction of the cooldown.
local CANCEL_COOLDOWN_FRACTION = 0.5
-- The first swing of a fresh spawn is offset by id so a wave's attacks do not land in unison.
local SPAWN_ATTACK_OFFSET = 0.15
local SPAWN_ATTACK_OFFSET_STEPS = 5
-- Pathfinding: waypoint arrival, probe height (above the floor, below every obstacle top), how
-- far the path's goal may drift from the live goal before the path is ignored, and a cap on
-- concurrent ComputeAsync jobs so a jammed wave cannot flood the pathfinder.
local WAYPOINT_REACHED_STUDS = 3
local PROBE_HEIGHT = 1.5
local PATH_GOAL_TOLERANCE = 12
local MAX_PATH_JOBS = 4
local PATH_AGENT_RADIUS = 2
local PATH_AGENT_HEIGHT = 5
-- Enemies face their target (not their feet) once they are this close to the hold ring.
local ENGAGE_FACE_MARGIN = 8
local FACE_RESPONSIVENESS = 25
-- Hit reaction and death.
local STAGGER_SHOVE = 6
local RAGDOLL_LIFT_FRACTION = 0.4
local RAGDOLL_UPPER_ANGLE = 70

type ActionKind = "strike" | "shoot" | "slam" | "charge" | "summon"

-- One attack in flight: telegraphed at start, resolved at impactAt from positions read THEN.
type Action = {
	kind: ActionKind,
	impactAt: number,
	-- Flat unit vector locked at the start of the windup.
	facing: Vector3,
	targetUserId: number,
	damage: number,
	radius: number,
	-- Boss patterns do not reset the ordinary attack cooldown.
	pattern: boolean,
	summonKey: string?,
	summonCount: number,
	windupSeconds: number,
	dashing: boolean,
	dashFrom: Vector3,
	dashLast: Vector3,
	dashEndAt: number,
	dashHit: { [number]: boolean },
}

type Tracks = {
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	run: AnimationTrack?,
	attack: AnimationTrack?,
	hit: AnimationTrack?,
}

type Motion = "idle" | "walk" | "run"

export type Enemy = {
	id: number,
	key: string,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	kind: string,
	hp: number,
	maxHp: number,
	damage: number,
	speed: number,
	reach: number,
	attackCooldown: number,
	cash: number,
	materials: number,
	isBoss: boolean,
	elite: boolean,
	displayName: string,
	scale: number,
	dead: boolean,
	-- os.clock() stamps.
	nextAttackAt: number,
	retargetAt: number,
	stunUntil: number,
	staggerUntil: number,
	strafeFlipAt: number,
	targetUserId: number,
	walkPhase: number,
	strafeSign: number,
	-- Melee attack slot around targetUserId: 0 = circling at holdRadius.
	slotTarget: number,
	slotIndex: number,
	action: Action?,
	patterns: { Types.BossPatternDef },
	patternReadyAt: { number },
	patternCursor: number,
	walkSpeedNow: number,
	motion: Motion,
	lastHitDirection: Vector3?,
	align: AlignOrientation?,
	attackJoint: Motor6D?,
	attackJointRest: CFrame?,
	leftArmJoint: Motor6D?,
	leftArmRest: CFrame?,
	waistJoint: Motor6D?,
	waistRest: CFrame?,
	tracks: Tracks,
	path: Path?,
	waypoints: { Vector3 }?,
	waypointIndex: number,
	pathGoal: Vector3?,
	pathRequestedAt: number,
	pathToken: number,
	pathPending: boolean,
	-- The reaper: Humanoid.Died and "the model left Workspace" both mean this rig is gone,
	-- however it got there. Disconnected the moment the enemy is booked as dead.
	watchers: { RBXScriptConnection },
}

export type Hooks = {
	-- The live party roster, players and debug bots alike: enemies aggro on both.
	targets: () -> { Types.RunMember },
	-- CombatService.DamagePlayer: god mode and the down/respawn bookkeeping live there.
	damagePlayer: (member: Types.RunMember, amount: number) -> (),
	-- WaveService: credits the reward pool and pushes the kill effect.
	onKilled: (enemy: Enemy, byUserId: number) -> (),
	-- CombatService.PushFx: telegraphs go out in the same per-frame batch as hits.
	pushFx: (fx: Types.CombatFx) -> (),
}

-- WaveService queues summoned enemies through its normal spawn path (maxAlive, rewards).
export type SummonHandler = (key: string, count: number, near: Vector3) -> ()

type TargetInfo = { member: Types.RunMember, root: BasePart, position: Vector3 }
type Neighbour = { enemy: Enemy, position: Vector3 }

local hooks: Hooks? = nil
local summonHandler: SummonHandler? = nil
local combatConfig: Types.CombatConfig? = nil
local mission: Types.MissionConfig? = nil
local enemiesFolder: Folder? = nil
local placeholderTemplate: Model? = nil
local spawnPoints: { Vector3 } = {}
local obstacleParams: RaycastParams? = nil
-- Shared by every line-of-sight ray; the enemy folder is excluded once it exists (Init).
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
local enemies: { Enemy } = {}
local byId: { [number]: Enemy } = {}
local nextEnemyId = 1
local tickAccumulator = 0
local aiConnection: RBXScriptConnection? = nil
local activePathJobs = 0
-- One Animation instance per asset id, shared by every rig, and one warn per failing id.
local animationObjects: { [number]: Animation } = {}
local warnedAnimations: { [number]: boolean } = {}

local EnemyService = {}

local function tickInterval(): number
	local config = combatConfig
	local hz = if config ~= nil then config.enemy.tickHz else DEFAULT_TICK_HZ
	if hz <= 0 then
		return 1 / DEFAULT_TICK_HZ
	end
	return 1 / hz
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function unitOr(vector: Vector3, fallback: Vector3): Vector3
	if vector.Magnitude < 1e-3 then
		return fallback
	end
	return vector.Unit
end

local function ringDirection(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function angleBetween(a: Vector3, b: Vector3): number
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then
		return 0
	end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- Flat distance from a point to the segment a-b.
local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local p = flat(point)
	local from = flat(a)
	local segment = flat(b) - from
	local lengthSquared = segment:Dot(segment)
	if lengthSquared < 1e-6 then
		return (p - from).Magnitude
	end
	local t = math.clamp((p - from):Dot(segment) / lengthSquared, 0, 1)
	return (p - (from + segment * t)).Magnitude
end

-- "RaiderChief" becomes "Raider Chief": the template name is what the HUD shows.
local function humanise(name: string): string
	local spaced = string.gsub(name, "(%l)(%u)", "%1 %2")
	return spaced
end

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1] or 255, values[2] or 255, values[3] or 255)
end

local function colorFor(def: Types.EnemyDef, isBoss: boolean, config: Types.CombatConfig): Color3
	if isBoss then
		return rgb(config.enemy.bossColor)
	end
	local own = def.color
	return rgb(if own ~= nil then own else config.enemy.defaultColor)
end

local function paint(model: Model, color: Color3): ()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = color
			-- Placeholder rigs ship with the default avatar look; flattening the material is
			-- what makes the recolour readable at camera distance.
			descendant.Material = Enum.Material.SmoothPlastic
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant:Destroy()
		end
	end
end

-- A four-part stand-in for the days CreateHumanoidModelFromDescription cannot reach the avatar
-- endpoint (offline Studio, throttling). It walks, it takes damage, it dies: never an error.
local function buildBlockRig(): (Model, Humanoid, BasePart)
	local model = Instance.new("Model")
	model.Name = "BlockRig"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	local function attach(name: string, size: Vector3, offset: Vector3): ()
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = root.CFrame * CFrame.new(offset)
		part.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	attach("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
	attach("Head", Vector3.new(1.6, 1.2, 1.6), Vector3.new(0, 1.6, 0))
	attach("Legs", Vector3.new(2, 2, 1), Vector3.new(0, -2, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 3
	humanoid.Parent = model
	return model, humanoid, root
end

-- Built once at Init and cloned per enemy: the avatar call yields and can throttle, so paying it
-- per spawn would stutter every wave.
local function buildPlaceholderTemplate(): Model?
	local description = Instance.new("HumanoidDescription")
	local ok, model = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if not ok or typeof(model) ~= "Instance" then
		warn(`[EnemyService] CreateHumanoidModelFromDescription failed: {model}; using block rigs`)
		return nil
	end
	local rig = model :: Model
	-- The rig arrives with the default Animate and Health scripts; both would fight the server
	-- for control of a body the server owns.
	for _, child in rig:GetChildren() do
		if child:IsA("BaseScript") then
			child:Destroy()
		end
	end
	rig.Name = "PlaceholderEnemy"
	return rig
end

local function cloneTemplateFor(templateName: string): Model?
	local root = ServerStorage:FindFirstChild("Enemies")
	local missionConfig = mission
	if root == nil or missionConfig == nil then
		return nil
	end
	local eraFolder = root:FindFirstChild(missionConfig.eraName)
	if eraFolder == nil then
		return nil
	end
	local template = eraFolder:FindFirstChild(templateName)
	if template == nil or not template:IsA("Model") then
		return nil
	end
	return template:Clone()
end

local function buildRig(): (Model, Humanoid, BasePart)
	local template = placeholderTemplate
	if template ~= nil then
		local clone = template:Clone()
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		local root = clone:FindFirstChild("HumanoidRootPart")
		if humanoid ~= nil and root ~= nil and root:IsA("BasePart") then
			return clone, humanoid, root
		end
		clone:Destroy()
	end
	return buildBlockRig()
end

-- Shared with ArenaService, which dresses debug bots in the same placeholder rig (painted
-- Combat.json enemy.botColor). Returns an unparented model.
function EnemyService.BuildRig(color: Color3): (Model, Humanoid, BasePart)
	local model, humanoid, root = buildRig()
	paint(model, color)
	return model, humanoid, root
end

local function applyScale(humanoid: Humanoid, scale: number): ()
	if scale == 1 then
		return
	end
	for _, name in { "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" } do
		local value = humanoid:FindFirstChild(name)
		if value ~= nil and value:IsA("NumberValue") then
			value.Value *= scale
		end
	end
end

-- The Combat.json ids are Roblox defaults written from memory and unverified: a load that throws
-- or an id of 0 leaves the procedural pose in charge, with one warn per id per server. An asset
-- that loads but never resolves shows as Length 0, which trackReady treats the same way.
local function loadTrack(animator: Animator, assetId: number): AnimationTrack?
	if assetId <= 0 then
		return nil
	end
	local cached: Animation? = animationObjects[assetId]
	local animation: Animation
	if cached ~= nil then
		animation = cached
	else
		animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{assetId}`
		animationObjects[assetId] = animation
	end
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	if not ok or typeof(track) ~= "Instance" then
		if not warnedAnimations[assetId] then
			warnedAnimations[assetId] = true
			warn(`[EnemyService] animation {assetId} failed to load: {track}; procedural fallback`)
		end
		return nil
	end
	return track :: AnimationTrack
end

local function trackReady(track: AnimationTrack?): boolean
	return track ~= nil and track.Length > 0
end

local function setupAnimations(enemy: Enemy): ()
	local config = combatConfig
	if config == nil then
		return
	end
	local ids = config.animations
	if
		ids.enemyIdle <= 0
		and ids.enemyWalk <= 0
		and ids.enemyRun <= 0
		and ids.enemyAttack <= 0
		and ids.enemyHit <= 0
	then
		return
	end
	local existing = enemy.humanoid:FindFirstChildOfClass("Animator")
	local animator: Animator
	if existing ~= nil then
		animator = existing
	else
		animator = Instance.new("Animator")
		animator.Parent = enemy.humanoid
	end
	local tracks = enemy.tracks
	tracks.walk = loadTrack(animator, ids.enemyWalk)
	tracks.run = loadTrack(animator, ids.enemyRun)
	tracks.attack = loadTrack(animator, ids.enemyAttack)
	tracks.hit = loadTrack(animator, ids.enemyHit)
	local idle = loadTrack(animator, ids.enemyIdle)
	tracks.idle = idle
	if idle ~= nil then
		idle.Looped = true
		idle:Play()
	end
	for _, track in { tracks.walk, tracks.run } do
		if track ~= nil then
			track.Looped = true
		end
	end
end

local function stopTracks(enemy: Enemy): ()
	local tracks = enemy.tracks
	for _, track in { tracks.idle, tracks.walk, tracks.run, tracks.attack, tracks.hit } do
		if track ~= nil and track.IsPlaying then
			track:Stop(0.1)
		end
	end
end

local function findJoints(enemy: Enemy): ()
	for _, descendant in enemy.model:GetDescendants() do
		if not descendant:IsA("Motor6D") then
			continue
		end
		if descendant.Name == "RightShoulder" and enemy.attackJoint == nil then
			enemy.attackJoint = descendant
			enemy.attackJointRest = descendant.C0
		elseif descendant.Name == "LeftShoulder" and enemy.leftArmJoint == nil then
			enemy.leftArmJoint = descendant
			enemy.leftArmRest = descendant.C0
		elseif descendant.Name == "Waist" and enemy.waistJoint == nil then
			enemy.waistJoint = descendant
			enemy.waistRest = descendant.C0
		end
	end
end

-- Facing is driven by an AlignOrientation rather than Humanoid.AutoRotate, so an enemy can strafe
-- sideways round its target while still looking at it (the core of "circling" reading right).
local function setupFacing(enemy: Enemy): ()
	local attachment = Instance.new("Attachment")
	attachment.Name = "FacingAttachment"
	attachment.Parent = enemy.root
	local align = Instance.new("AlignOrientation")
	align.Name = "Facing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = FACE_RESPONSIVENESS
	align.RigidityEnabled = false
	align.CFrame = enemy.root.CFrame.Rotation
	align.Parent = enemy.root
	enemy.align = align
	enemy.humanoid.AutoRotate = false
end

local function face(enemy: Enemy, direction: Vector3): ()
	local align = enemy.align
	local planar = flat(direction)
	if align == nil or planar.Magnitude < 0.05 then
		return
	end
	align.CFrame = CFrame.lookAt(Vector3.zero, planar.Unit)
end

local function spawnPosition(spawnIndex: number, enemyId: number, at: Vector3?): Vector3
	local angle = enemyId * GOLDEN_ANGLE
	local offset = ringDirection(angle) * SPAWN_RING_RADIUS
	local lift = Vector3.new(0, SPAWN_LIFT, 0)
	if at ~= nil then
		return Vector3.new(at.X, 0, at.Z) + offset + lift
	end
	if #spawnPoints == 0 then
		return lift
	end
	local point = spawnPoints[(spawnIndex - 1) % #spawnPoints + 1]
	return point + offset + lift
end

function EnemyService.SetHooks(serviceHooks: Hooks): ()
	hooks = serviceHooks
end

function EnemyService.SetSummonHandler(handler: SummonHandler): ()
	summonHandler = handler
end

-- ArenaService hands these over once the arena exists; an empty list spawns everything at the
-- origin, which is the "no layout module" degrade path.
function EnemyService.SetSpawnPoints(points: { Vector3 }): ()
	spawnPoints = points
end

-- The arena's cover. Only these block the steering probe, so the floor, the fence and the lobby
-- pad never send an enemy to the pathfinder.
function EnemyService.SetObstacles(parts: { BasePart }): ()
	if #parts == 0 then
		obstacleParams = nil
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local instances: { Instance } = {}
	for _, part in parts do
		table.insert(instances, part)
	end
	params.FilterDescendantsInstances = instances
	obstacleParams = params
end

function EnemyService.SetMission(missionConfig: Types.MissionConfig?): ()
	mission = missionConfig
end

function EnemyService.GetEnemies(): { Enemy }
	return enemies
end

function EnemyService.GetById(enemyId: number): Enemy?
	local enemy = byId[enemyId]
	if enemy == nil or enemy.dead then
		return nil
	end
	return enemy
end

function EnemyService.AliveCount(): number
	local count = 0
	for _, enemy in enemies do
		if not enemy.dead then
			count += 1
		end
	end
	return count
end

-- Forward declaration: the reaper below is installed at Spawn but has to call the kill path,
-- which is defined after it.
local killEnemy: (enemy: Enemy, byUserId: number) -> ()

-- A rig can leave the run without anyone hitting it: Humanoid.Died fired by something else, or
-- the model destroyed out of band (FallenPartsDestroyHeight after a knockback over the fence).
-- Without this it would stay in `enemies` forever and the wave would never clear.
local function watchRig(enemy: Enemy): ()
	table.insert(
		enemy.watchers,
		enemy.humanoid.Died:Connect(function()
			killEnemy(enemy, 0)
		end)
	)
	table.insert(
		enemy.watchers,
		enemy.model.AncestryChanged:Connect(function()
			if not enemy.model:IsDescendantOf(workspace) then
				killEnemy(enemy, 0)
			end
		end)
	)
end

-- Raycast hits land on a part; this walks up to the model that carries the EnemyId attribute.
function EnemyService.FromInstance(instance: Instance?): Enemy?
	local current = instance
	while current ~= nil and current ~= workspace do
		local id = current:GetAttribute("EnemyId")
		if typeof(id) == "number" then
			return EnemyService.GetById(id)
		end
		current = current.Parent
	end
	return nil
end

local function copyPatterns(boss: Types.BossDef?): { Types.BossPatternDef }
	local list: { Types.BossPatternDef } = {}
	if boss == nil or boss.patterns == nil then
		return list
	end
	for _, pattern in boss.patterns :: { Types.BossPatternDef } do
		table.insert(list, pattern)
	end
	return list
end

-- `boss` is the mission BossDef for this wave when isBoss is true: EnemyService does not know
-- the wave number, so the caller (WaveService, which resolved the spec) passes it in. `at` places
-- a summoned enemy beside its boss instead of on the rim.
function EnemyService.Spawn(
	key: string,
	stats: Types.EnemyStats,
	isBoss: boolean,
	spawnIndex: number,
	boss: Types.BossDef?,
	at: Vector3?
): Enemy?
	local missionConfig = mission
	local config = combatConfig
	local folder = enemiesFolder
	if missionConfig == nil or config == nil or folder == nil then
		return nil
	end
	local def = missionConfig.enemies[key]
	if def == nil then
		warn(`[EnemyService] no enemy "{key}" in mission {missionConfig.id}`)
		return nil
	end

	local templateName = if isBoss and boss ~= nil then boss.template else def.template
	local authored = cloneTemplateFor(templateName)
	local model: Model
	local humanoid: Humanoid
	local root: BasePart
	local authoredUsed = false
	if authored ~= nil then
		local authoredHumanoid = authored:FindFirstChildOfClass("Humanoid")
		local authoredRoot = authored:FindFirstChild("HumanoidRootPart")
		if authoredHumanoid ~= nil and authoredRoot ~= nil and authoredRoot:IsA("BasePart") then
			model, humanoid, root = authored, authoredHumanoid, authoredRoot
			authoredUsed = true
		else
			warn(`[EnemyService] template {templateName} has no Humanoid/root; using placeholder`)
			authored:Destroy()
		end
	end
	if not authoredUsed then
		model, humanoid, root = buildRig()
		paint(model, colorFor(def, isBoss, config))
	end

	local enemyId = nextEnemyId
	nextEnemyId += 1
	local scale = if isBoss
		then config.enemy.bossScale
		elseif def.elite then config.enemy.eliteScale
		else 1
	applyScale(humanoid, scale)

	model.Name = `Enemy_{enemyId}`
	local displayName = humanise(templateName)
	model:SetAttribute("EnemyId", enemyId)
	model:SetAttribute("EnemyKey", key)
	model:SetAttribute("DisplayName", displayName)
	model:SetAttribute("IsBoss", isBoss)
	model:SetAttribute("Elite", def.elite)
	model:SetAttribute("Attacking", false)
	model:SetAttribute("Dead", false)

	humanoid.MaxHealth = stats.hp
	humanoid.Health = stats.hp
	humanoid.WalkSpeed = def.speed
	humanoid.BreakJointsOnDeath = false
	humanoid.HealthDisplayDistance = 0
	humanoid.NameDisplayDistance = 0

	model:PivotTo(CFrame.new(spawnPosition(spawnIndex, enemyId, at)))
	model.Parent = folder
	-- Server-owned bodies: a client must never be able to shove an enemy off the arena.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local now = os.clock()
	local patterns: { Types.BossPatternDef } = if isBoss then copyPatterns(boss) else {}
	local patternReadyAt: { number } = {}
	for index, pattern in patterns do
		-- Counted from the spawn, like sim_combat.py: a boss opens with its ordinary attack.
		patternReadyAt[index] = now + math.max(0, pattern.cooldown)
	end
	local enemy: Enemy = {
		id = enemyId,
		key = key,
		model = model,
		humanoid = humanoid,
		root = root,
		kind = def.kind,
		hp = stats.hp,
		maxHp = stats.hp,
		damage = stats.damage,
		speed = def.speed,
		reach = def.reach,
		attackCooldown = def.attackCooldown,
		cash = stats.cash,
		materials = stats.materials,
		isBoss = isBoss,
		elite = def.elite,
		displayName = displayName,
		scale = scale,
		dead = false,
		nextAttackAt = now
			+ def.attackCooldown
			+ (enemyId % SPAWN_ATTACK_OFFSET_STEPS) * SPAWN_ATTACK_OFFSET,
		retargetAt = 0,
		stunUntil = 0,
		staggerUntil = 0,
		strafeFlipAt = now + STRAFE_FLIP_SECONDS + (enemyId % 4) * STRAFE_FLIP_SPREAD,
		targetUserId = 0,
		walkPhase = enemyId,
		strafeSign = if enemyId % 2 == 0 then 1 else -1,
		slotTarget = 0,
		slotIndex = 0,
		action = nil,
		patterns = patterns,
		patternReadyAt = patternReadyAt,
		patternCursor = 1,
		walkSpeedNow = def.speed,
		motion = "idle",
		lastHitDirection = nil,
		align = nil,
		attackJoint = nil,
		attackJointRest = nil,
		leftArmJoint = nil,
		leftArmRest = nil,
		waistJoint = nil,
		waistRest = nil,
		tracks = {},
		path = nil,
		waypoints = nil,
		waypointIndex = 1,
		pathGoal = nil,
		pathRequestedAt = -math.huge,
		pathToken = 0,
		pathPending = false,
		watchers = {},
	}
	findJoints(enemy)
	setupFacing(enemy)
	setupAnimations(enemy)
	table.insert(enemies, enemy)
	byId[enemyId] = enemy
	watchRig(enemy)
	return enemy
end

local function removeEnemy(enemy: Enemy): ()
	local index = table.find(enemies, enemy)
	if index ~= nil then
		table.remove(enemies, index)
	end
	byId[enemy.id] = nil
end

local function setWalkSpeed(enemy: Enemy, speed: number): ()
	if enemy.walkSpeedNow ~= speed then
		enemy.walkSpeedNow = speed
		enemy.humanoid.WalkSpeed = speed
	end
end

local function setMotion(enemy: Enemy, motion: Motion): ()
	if enemy.motion == motion then
		return
	end
	enemy.motion = motion
	local tracks = enemy.tracks
	local wanted: AnimationTrack? = nil
	if motion == "run" then
		wanted = tracks.run or tracks.walk
	elseif motion == "walk" then
		wanted = tracks.walk or tracks.run
	end
	for _, track in { tracks.walk, tracks.run } do
		if track ~= nil and track ~= wanted and track.IsPlaying then
			track:Stop(0.15)
		end
	end
	if wanted ~= nil and not wanted.IsPlaying then
		wanted:Play(0.15)
	end
end

local function hold(enemy: Enemy): ()
	enemy.humanoid:MoveTo(enemy.root.Position)
	setMotion(enemy, "idle")
end

local function setJoint(joint: Motor6D?, rest: CFrame?, offset: CFrame?): ()
	if joint == nil or rest == nil or joint.Parent == nil then
		return
	end
	local wanted = if offset ~= nil then rest * offset else rest
	if joint.C0 ~= wanted then
		joint.C0 = wanted
	end
end

-- Procedural body language, always on: the windup arm, the slam's raised arms, the charge
-- crouch, the stagger lean and (only when no walk/run animation actually loaded) the walk bob.
local function pose(enemy: Enemy, now: number, delta: number): ()
	local rightArm: CFrame? = nil
	local leftArm: CFrame? = nil
	local waist: CFrame? = nil
	local action = enemy.action
	if now < enemy.staggerUntil then
		waist = CFrame.Angles(math.rad(STAGGER_LEAN_DEGREES), 0, 0)
	end
	if action ~= nil then
		if action.kind == "strike" or action.kind == "shoot" then
			rightArm = CFrame.Angles(math.rad(WINDUP_ARM_DEGREES), 0, 0)
		elseif action.kind == "slam" or action.kind == "summon" then
			rightArm = CFrame.Angles(math.rad(SLAM_ARMS_DEGREES), 0, 0)
			leftArm = rightArm
		elseif action.kind == "charge" then
			waist = CFrame.Angles(math.rad(CHARGE_LEAN_DEGREES), 0, 0)
		end
	elseif waist == nil and enemy.motion ~= "idle" then
		local tracks = enemy.tracks
		local animated = if enemy.motion == "run"
			then trackReady(tracks.run) or trackReady(tracks.walk)
			else trackReady(tracks.walk) or trackReady(tracks.run)
		if not animated then
			enemy.walkPhase += delta * WALK_BOB_HZ * math.pi * 2
			waist = CFrame.Angles(0, 0, math.rad(WALK_BOB_DEGREES) * math.sin(enemy.walkPhase))
		end
	end
	setJoint(enemy.attackJoint, enemy.attackJointRest, rightArm)
	setJoint(enemy.leftArmJoint, enemy.leftArmRest, leftArm)
	setJoint(enemy.waistJoint, enemy.waistRest, waist)
end

local function pushFx(fx: Types.CombatFx): ()
	local serviceHooks = hooks
	if serviceHooks ~= nil then
		serviceHooks.pushFx(fx)
	end
end

local function endAction(enemy: Enemy, now: number, cancelled: boolean): ()
	local action = enemy.action
	if action == nil then
		return
	end
	enemy.action = nil
	enemy.model:SetAttribute("Attacking", false)
	setWalkSpeed(enemy, enemy.speed)
	local attackTrack = enemy.tracks.attack
	if attackTrack ~= nil and attackTrack.IsPlaying then
		attackTrack:Stop(0.1)
	end
	if cancelled then
		enemy.nextAttackAt =
			math.max(enemy.nextAttackAt, now + enemy.attackCooldown * CANCEL_COOLDOWN_FRACTION)
	elseif action.pattern then
		-- ai.postPatternAttackDelay keeps a pattern's tell and the ordinary attack's apart.
		local config = combatConfig
		local delay = if config ~= nil then config.ai.postPatternAttackDelay else 0
		enemy.nextAttackAt = math.max(enemy.nextAttackAt, now + delay)
	else
		enemy.nextAttackAt = now + enemy.attackCooldown
	end
end

-- Ragdoll: every Motor6D becomes a limited BallSocket (with a NoCollision so neighbouring limbs
-- cannot fight), limbs collide with the floor, and each part is thrown along the killing hit.
-- Corpse parts leave raycasts and touches so no shot or swing is spent on a body.
local function ragdoll(enemy: Enemy, direction: Vector3?, impulse: number): ()
	local model = enemy.model
	if not model:IsDescendantOf(workspace) then
		return
	end
	local align = enemy.align
	if align ~= nil then
		align.Enabled = false
	end
	enemy.humanoid.AutoRotate = false
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("Motor6D") then
			continue
		end
		local part0 = descendant.Part0
		local part1 = descendant.Part1
		if part0 == nil or part1 == nil then
			continue
		end
		local attachment0 = Instance.new("Attachment")
		attachment0.Name = "RagdollAttachment"
		attachment0.CFrame = descendant.C0
		attachment0.Parent = part0
		local attachment1 = Instance.new("Attachment")
		attachment1.Name = "RagdollAttachment"
		attachment1.CFrame = descendant.C1
		attachment1.Parent = part1
		local socket = Instance.new("BallSocketConstraint")
		socket.Attachment0 = attachment0
		socket.Attachment1 = attachment1
		socket.LimitsEnabled = true
		socket.UpperAngle = RAGDOLL_UPPER_ANGLE
		socket.Parent = part1
		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Part0 = part0
		noCollide.Part1 = part1
		noCollide.Parent = part1
		descendant.Enabled = false
	end
	local root = enemy.root
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanQuery = false
			descendant.CanTouch = false
			if descendant ~= root then
				descendant.CanCollide = true
			end
		end
	end
	root.CanCollide = false
	root.Massless = true

	local along = unitOr(flat(direction or Vector3.zero), -flat(root.CFrame.LookVector))
	local velocity = along * impulse + Vector3.new(0, impulse * RAGDOLL_LIFT_FRACTION, 0)
	root.AssemblyLinearVelocity = velocity
	-- The limbs become their own assemblies only once the engine rebuilds them after the motors
	-- switch off, so the per-part throw and the server ownership land a moment later.
	task.defer(function()
		if model.Parent == nil then
			return
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and not descendant.Anchored then
				descendant.AssemblyLinearVelocity = velocity
				pcall(function()
					descendant:SetNetworkOwner(nil)
				end)
			end
		end
	end)
end

-- Death: the enemy stops counting the moment it dies, the body ragdolls for feel.ragdollSeconds,
-- and `Dead` is stamped player.corpseSeconds before the Destroy so the client dissolve (C1
-- contract) plays over the end of the fall rather than hiding it.
function killEnemy(enemy: Enemy, byUserId: number): ()
	if enemy.dead then
		return
	end
	enemy.dead = true
	enemy.hp = 0
	removeEnemy(enemy)
	for _, connection in enemy.watchers do
		connection:Disconnect()
	end
	table.clear(enemy.watchers)
	enemy.action = nil
	enemy.waypoints = nil
	local config = combatConfig
	local corpseSeconds = if config ~= nil
		then config.player.corpseSeconds
		else DEFAULT_CORPSE_SECONDS
	local ragdollSeconds = if config ~= nil
		then config.feel.ragdollSeconds
		else DEFAULT_RAGDOLL_SECONDS
	local impulse = if config ~= nil then config.feel.ragdollImpulse else 0
	enemy.model:SetAttribute("Attacking", false)
	stopTracks(enemy)
	enemy.humanoid.WalkSpeed = 0
	enemy.humanoid.Health = 0
	local serviceHooks = hooks
	if serviceHooks ~= nil then
		serviceHooks.onKilled(enemy, byUserId)
	end
	ragdoll(enemy, enemy.lastHitDirection, impulse)
	local model = enemy.model
	task.delay(math.max(0, ragdollSeconds - corpseSeconds), function()
		if model.Parent ~= nil then
			model:SetAttribute("Dead", true)
		end
	end)
	task.delay(math.max(ragdollSeconds, corpseSeconds), function()
		model:Destroy()
	end)
end

local function stagger(enemy: Enemy, heavy: boolean, direction: Vector3): ()
	local config = combatConfig
	if config == nil then
		return
	end
	local seconds = if heavy then config.ai.finisherStaggerSeconds else config.ai.staggerSeconds
	if enemy.isBoss then
		seconds *= 0.5
	end
	if seconds <= 0 then
		return
	end
	local now = os.clock()
	enemy.staggerUntil = math.max(enemy.staggerUntil, now + seconds)
	local action = enemy.action
	-- Bosses, elites and a charger mid-dash have super armour: they flinch but finish the blow.
	-- Everything else loses the windup, which is what makes hitting first the right answer.
	local armoured = enemy.isBoss or enemy.elite or (action ~= nil and action.dashing)
	if action ~= nil and not armoured then
		endAction(enemy, now, true)
	end
	if enemy.action == nil then
		hold(enemy)
		enemy.root.AssemblyLinearVelocity += direction * STAGGER_SHOVE
	end
	local hitTrack = enemy.tracks.hit
	if hitTrack ~= nil then
		hitTrack:Play(0.05)
	end
end

-- The single entry point for damage TO an enemy; CombatService is its only caller. `direction`
-- (attacker -> enemy, flat unit) is nil for damage-over-time ticks and bots, which neither
-- stagger nor aim the ragdoll. True when this hit killed.
function EnemyService.Damage(
	enemy: Enemy,
	amount: number,
	byUserId: number,
	direction: Vector3?,
	heavy: boolean?
): boolean
	if enemy.dead or amount <= 0 then
		return false
	end
	if direction ~= nil then
		enemy.lastHitDirection = direction
	end
	enemy.hp -= amount
	if enemy.hp <= 0 then
		killEnemy(enemy, byUserId)
		return true
	end
	enemy.humanoid.Health = enemy.hp
	if direction ~= nil then
		stagger(enemy, heavy == true, direction)
	end
	return false
end

function EnemyService.Stun(enemy: Enemy, seconds: number): ()
	if enemy.dead or seconds <= 0 then
		return
	end
	local now = os.clock()
	enemy.stunUntil = math.max(enemy.stunUntil, now + seconds)
	if not enemy.isBoss then
		endAction(enemy, now, true)
	end
	enemy.humanoid:MoveTo(enemy.root.Position)
end

function EnemyService.Knockback(enemy: Enemy, direction: Vector3, studs: number): ()
	if enemy.dead or studs <= 0 then
		return
	end
	local planar = flat(direction)
	if planar.Magnitude <= 0 then
		return
	end
	enemy.root.AssemblyLinearVelocity = planar.Unit * studs + Vector3.new(0, studs * 0.25, 0)
end

-- Every alive enemy dies with normal rewards (the debug KillAll lever).
function EnemyService.KillAll(byUserId: number): ()
	for _, enemy in table.clone(enemies) do
		killEnemy(enemy, byUserId)
	end
end

-- End of run: no rewards, no kill callbacks, nothing left in the arena.
function EnemyService.ClearAll(): ()
	for _, enemy in table.clone(enemies) do
		-- Marked dead and unwatched BEFORE the Destroy, so the reaper's AncestryChanged does not
		-- try to bill the run for a rig the run itself is tearing down.
		enemy.dead = true
		enemy.action = nil
		for _, connection in enemy.watchers do
			connection:Disconnect()
		end
		table.clear(enemy.watchers)
		enemy.model:Destroy()
	end
	table.clear(enemies)
	table.clear(byId)
end

-- nil = not a target. A member waiting on the lobby pad for the next wave boundary (C2) is
-- untargetable, which is what keeps a joiner safe until they enter the fight.
local function memberRoot(member: Types.RunMember): BasePart?
	if member.waiting then
		return nil
	end
	local character = member.character
	if character == nil or character.Parent == nil then
		return nil
	end
	local humanoid = member.humanoid
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- One pass over the roster per tick: every enemy decision this tick reads these positions.
local function snapshotTargets(): { TargetInfo }
	local list: { TargetInfo } = {}
	local serviceHooks = hooks
	if serviceHooks == nil then
		return list
	end
	for _, member in serviceHooks.targets() do
		local root = memberRoot(member)
		if root ~= nil then
			table.insert(list, { member = member, root = root, position = root.Position })
		end
	end
	return list
end

local function findInfo(targets: { TargetInfo }, userId: number): TargetInfo?
	if userId == 0 then
		return nil
	end
	for _, info in targets do
		if info.member.userId == userId then
			return info
		end
	end
	return nil
end

local function retarget(
	enemy: Enemy,
	targets: { TargetInfo },
	now: number,
	config: Types.CombatConfig
): TargetInfo?
	local current = findInfo(targets, enemy.targetUserId)
	if current ~= nil and now < enemy.retargetAt then
		return current
	end
	enemy.retargetAt = now + config.enemy.retargetSeconds
	local position = enemy.root.Position
	local best: TargetInfo? = nil
	local bestDistance = math.huge
	local aggro = config.enemy.aggroRange
	-- Nearest inside aggroRange; failing that, nearest anywhere. aggroRange (80) is smaller than
	-- a rim spawn is from the far corner, and an idle enemy would leave the wave uncleared.
	for pass = 1, 2 do
		for _, info in targets do
			local distance = (info.position - position).Magnitude
			if (pass == 2 or distance <= aggro) and distance < bestDistance then
				best = info
				bestDistance = distance
			end
		end
		if best ~= nil then
			break
		end
	end
	if current ~= nil and best ~= nil and best ~= current then
		local currentDistance = (current.position - position).Magnitude
		if currentDistance <= bestDistance + RETARGET_HYSTERESIS then
			best = current
		end
	end
	enemy.targetUserId = if best ~= nil then best.member.userId else 0
	return best
end

-- Only non-boss melee and charger enemies compete for slots; a charger without one charges from
-- the hold ring instead (sim_combat.py models the same: it needs a slot to swing).
local function usesSlots(enemy: Enemy): boolean
	return not enemy.isBoss and enemy.kind ~= "ranged"
end

local function slotCount(config: Types.CombatConfig): number
	return math.max(0, math.floor(config.ai.maxMeleeAttackers))
end

-- At most ai.maxMeleeAttackers enemies may be in striking position around one member. Holders
-- keep their slot (no jitter) unless knocked well outside the ring; the rest go nearest first,
-- each to the free slot closest to its own bearing so nobody crosses through the target.
local function assignSlots(targets: { TargetInfo }, config: Types.CombatConfig): ()
	local slots = slotCount(config)
	local byTarget: { [number]: { Enemy } } = {}
	for _, enemy in enemies do
		if enemy.dead or not usesSlots(enemy) or enemy.targetUserId == 0 then
			enemy.slotIndex = 0
			enemy.slotTarget = 0
			continue
		end
		local list = byTarget[enemy.targetUserId]
		if list == nil then
			list = {}
			byTarget[enemy.targetUserId] = list
		end
		table.insert(list, enemy)
	end
	local keepRange = config.ai.holdRadius + SLOT_KEEP_MARGIN
	for userId, list in byTarget do
		local info = findInfo(targets, userId)
		if info == nil then
			for _, enemy in list do
				enemy.slotIndex = 0
				enemy.slotTarget = 0
			end
			continue
		end
		local center = info.position
		local distances: { [Enemy]: number } = {}
		local holding: { [Enemy]: boolean } = {}
		for _, enemy in list do
			local distance = flat(enemy.root.Position - center).Magnitude
			distances[enemy] = distance
			holding[enemy] = enemy.slotTarget == userId
				and enemy.slotIndex > 0
				and enemy.slotIndex <= slots
				and distance <= keepRange
		end
		table.sort(list, function(a: Enemy, b: Enemy): boolean
			if holding[a] ~= holding[b] then
				return holding[a]
			end
			if distances[a] ~= distances[b] then
				return distances[a] < distances[b]
			end
			return a.id < b.id
		end)
		local taken: { [number]: boolean } = {}
		local needing: { Enemy } = {}
		for index, enemy in list do
			if index > slots then
				enemy.slotIndex = 0
				enemy.slotTarget = 0
			elseif holding[enemy] and not taken[enemy.slotIndex] then
				taken[enemy.slotIndex] = true
			else
				table.insert(needing, enemy)
			end
		end
		for _, enemy in needing do
			local offset = flat(enemy.root.Position - center)
			local bearing = math.atan2(offset.Z, offset.X)
			local bestSlot = 0
			local bestGap = math.huge
			for slot = 1, slots do
				if taken[slot] then
					continue
				end
				local slotAngle = (slot - 1) * 2 * math.pi / slots
				local gap = math.abs((bearing - slotAngle + math.pi) % (2 * math.pi) - math.pi)
				if gap < bestGap then
					bestGap = gap
					bestSlot = slot
				end
			end
			if bestSlot > 0 then
				taken[bestSlot] = true
			end
			enemy.slotIndex = bestSlot
			enemy.slotTarget = if bestSlot > 0 then userId else 0
		end
	end
end

local function slotPoint(enemy: Enemy, center: Vector3, slots: number): Vector3
	local angle = (enemy.slotIndex - 1) * 2 * math.pi / math.max(slots, 1)
	local ring = math.max(SLOT_MIN_RING, enemy.reach * SLOT_REACH_FRACTION)
	return center + ringDirection(angle) * ring
end

-- A point on the ring of `radius` round `center`, a step along the enemy's strafe direction, and
-- the speed to take it at: full speed while still closing in, strafe speed once on the ring.
local function circlePoint(
	enemy: Enemy,
	center: Vector3,
	radius: number,
	config: Types.CombatConfig
): (Vector3, number)
	local offset = flat(enemy.root.Position - center)
	local distance = offset.Magnitude
	local bearing = if distance < 1e-3
		then enemy.id * GOLDEN_ANGLE
		else math.atan2(offset.Z, offset.X)
	if distance > radius + APPROACH_MARGIN then
		return center + ringDirection(bearing) * radius, enemy.speed
	end
	local nextBearing = bearing + enemy.strafeSign * CIRCLE_STEP_RADIANS
	return center + ringDirection(nextBearing) * radius, enemy.speed * config.ai.strafeSpeedMult
end

local function separation(enemy: Enemy, neighbours: { Neighbour }, radius: number): Vector3
	if radius <= 0 then
		return Vector3.zero
	end
	local position = enemy.root.Position
	local push = Vector3.zero
	for _, other in neighbours do
		if other.enemy == enemy then
			continue
		end
		local away = flat(position - other.position)
		local distance = away.Magnitude
		if distance >= radius then
			continue
		end
		-- Two enemies on the exact same spot split along their ids, never by chance.
		local direction = if distance < 0.05
			then ringDirection(enemy.id * GOLDEN_ANGLE)
			else away / distance
		push += direction * (1 - distance / radius)
	end
	return push
end

-- Arena cover between two points at knee height. Only the layout's obstacles count.
local function coverBetween(from: Vector3, to: Vector3): boolean
	local params = obstacleParams
	if params == nil then
		return false
	end
	local origin = Vector3.new(from.X, PROBE_HEIGHT, from.Z)
	local delta = Vector3.new(to.X, PROBE_HEIGHT, to.Z) - origin
	if delta.Magnitude < 1 then
		return false
	end
	return workspace:Raycast(origin, delta, params) ~= nil
end

-- Raycast so a ranged enemy cannot shoot through the arena boulders; other enemies are ignored,
-- because friendly fire would turn a crowd into a self-clearing wave.
local function lineOfSight(enemy: Enemy, targetRoot: BasePart): boolean
	local origin = enemy.root.Position + Vector3.new(0, 1.5, 0)
	local delta = targetRoot.Position - origin
	if delta.Magnitude <= 0 then
		return true
	end
	local result = workspace:Raycast(origin, delta, sightParams)
	if result == nil then
		return true
	end
	local character = targetRoot.Parent
	return character ~= nil and result.Instance:IsDescendantOf(character)
end

-- Off the tick thread: ComputeAsync yields. At most one job per enemy, MAX_PATH_JOBS overall,
-- and one request per enemy per ai.pathRecomputeSeconds. A stale or failed result is dropped
-- and the enemy simply keeps steering straight, which is the pre-C2.5 behaviour.
local function requestPath(enemy: Enemy, goal: Vector3, now: number, config: Types.CombatConfig): ()
	if enemy.pathPending or activePathJobs >= MAX_PATH_JOBS then
		return
	end
	if now < enemy.pathRequestedAt + config.ai.pathRecomputeSeconds then
		return
	end
	enemy.pathPending = true
	enemy.pathRequestedAt = now
	enemy.pathToken += 1
	local token = enemy.pathToken
	local from = enemy.root.Position
	activePathJobs += 1
	task.spawn(function()
		local path = enemy.path
		if path == nil then
			local ok, created = pcall(function(): Path
				return PathfindingService:CreatePath({
					AgentRadius = PATH_AGENT_RADIUS * enemy.scale,
					AgentHeight = PATH_AGENT_HEIGHT * enemy.scale,
					AgentCanJump = false,
				})
			end)
			if ok and typeof(created) == "Instance" then
				path = created :: Path
				enemy.path = path
			end
		end
		local waypoints: { Vector3 }? = nil
		if path ~= nil then
			local agentPath: Path = path
			local computed = pcall(function()
				agentPath:ComputeAsync(from, goal)
			end)
			if computed and agentPath.Status == Enum.PathStatus.Success then
				local points: { Vector3 } = {}
				for _, waypoint in agentPath:GetWaypoints() do
					table.insert(points, waypoint.Position)
				end
				waypoints = points
			end
		end
		activePathJobs -= 1
		enemy.pathPending = false
		if enemy.dead or token ~= enemy.pathToken then
			return
		end
		enemy.waypoints = waypoints
		enemy.waypointIndex = 2
		enemy.pathGoal = goal
	end)
end

local function nextWaypoint(enemy: Enemy, goal: Vector3): Vector3?
	local waypoints = enemy.waypoints
	local pathGoal = enemy.pathGoal
	if waypoints == nil or pathGoal == nil then
		return nil
	end
	if flat(pathGoal - goal).Magnitude > PATH_GOAL_TOLERANCE then
		return nil
	end
	local position = enemy.root.Position
	while
		enemy.waypointIndex <= #waypoints
		and flat(waypoints[enemy.waypointIndex] - position).Magnitude < WAYPOINT_REACHED_STUDS
	do
		enemy.waypointIndex += 1
	end
	return waypoints[enemy.waypointIndex]
end

-- The one place an enemy is told where to walk. `goal` is always a steered point (a slot, a spot
-- on a ring, a lane end), never a member's root.
local function steer(
	enemy: Enemy,
	goal: Vector3,
	speed: number,
	neighbours: { Neighbour },
	now: number,
	config: Types.CombatConfig
): ()
	local position = enemy.root.Position
	local destination = goal
	local waypoint: Vector3? = nil
	if coverBetween(position, goal) then
		requestPath(enemy, goal, now, config)
		waypoint = nextWaypoint(enemy, goal)
	else
		enemy.waypoints = nil
	end
	if waypoint ~= nil then
		-- Following a path round cover: separation would push the enemy back into the rock.
		destination = waypoint
	else
		local push = separation(enemy, neighbours, config.ai.separationRadius)
		destination = goal + push * config.ai.separationWeight * config.ai.separationRadius
	end
	setWalkSpeed(enemy, speed)
	enemy.humanoid:MoveTo(destination)
	if flat(destination - position).Magnitude < ARRIVE_STUDS then
		setMotion(enemy, "idle")
	elseif speed >= enemy.speed * RUN_SPEED_FRACTION then
		setMotion(enemy, "run")
	else
		setMotion(enemy, "walk")
	end
end

local function laneHalfWidth(enemy: Enemy, pattern: Types.BossPatternDef?): number
	if pattern ~= nil and pattern.radius ~= nil then
		return pattern.radius
	end
	local config = combatConfig
	local halfWidth = if config ~= nil then config.ai.chargeLaneHalfWidth else 0
	return halfWidth * enemy.scale
end

-- Every attack starts here: the enemy stops, locks its facing, raises the tell and the client
-- gets a telegraph `seconds` before the blow. The damage is resolved later from fresh positions.
local function beginAction(
	enemy: Enemy,
	kind: ActionKind,
	seconds: number,
	facing: Vector3,
	targetUserId: number,
	damage: number,
	radius: number,
	pattern: boolean,
	now: number
): Action
	local locked = unitOr(flat(facing), flat(enemy.root.CFrame.LookVector))
	local action: Action = {
		kind = kind,
		impactAt = now + math.max(0, seconds),
		facing = locked,
		targetUserId = targetUserId,
		damage = damage,
		radius = radius,
		pattern = pattern,
		summonKey = nil,
		summonCount = 0,
		windupSeconds = seconds,
		dashing = false,
		dashFrom = enemy.root.Position,
		dashLast = enemy.root.Position,
		dashEndAt = 0,
		dashHit = {},
	}
	enemy.action = action
	enemy.model:SetAttribute("Attacking", true)
	hold(enemy)
	face(enemy, locked)
	local attackTrack = enemy.tracks.attack
	if attackTrack ~= nil and (kind == "strike" or kind == "shoot") then
		attackTrack:Play(0.05)
	end
	-- A shot is drawn like a strike (glow on the attacker); a summon has its own tell and never
	-- lands on a player, so it carries no radius.
	local telegraphKind: "strike" | "slam" | "charge" | "summon" = if kind == "slam"
		then "slam"
		elseif kind == "charge" then "charge"
		elseif kind == "summon" then "summon"
		else "strike"
	pushFx({
		kind = "telegraph",
		enemyId = enemy.id,
		attack = telegraphKind,
		position = enemy.root.Position,
		direction = locked,
		radius = if kind == "summon" then nil else radius,
		seconds = math.max(0, seconds),
	})
	return action
end

local function damageMember(member: Types.RunMember, amount: number): ()
	local serviceHooks = hooks
	if serviceHooks ~= nil and amount > 0 then
		serviceHooks.damagePlayer(member, amount)
	end
end

local function startDash(enemy: Enemy, action: Action, now: number, config: Types.CombatConfig): ()
	local speed = math.max(1, enemy.speed * config.ai.chargeSpeedMult)
	local distance = config.ai.chargeDistance
	action.dashing = true
	action.dashFrom = enemy.root.Position
	action.dashLast = enemy.root.Position
	action.dashEndAt = now + distance / speed + DASH_TIMEOUT_PAD
	setWalkSpeed(enemy, speed)
	enemy.humanoid:MoveTo(action.dashFrom + action.facing * distance)
	setMotion(enemy, "run")
end

-- Players anywhere along the stretch covered since the last tick take the hit, once per dash.
local function updateDash(
	enemy: Enemy,
	action: Action,
	targets: { TargetInfo },
	now: number,
	config: Types.CombatConfig
): ()
	local position = enemy.root.Position
	local reachWidth = action.radius + MEMBER_RADIUS
	for _, info in targets do
		local userId = info.member.userId
		if action.dashHit[userId] then
			continue
		end
		if distanceToSegment(info.position, action.dashLast, position) <= reachWidth then
			action.dashHit[userId] = true
			damageMember(info.member, action.damage)
		end
	end
	action.dashLast = position
	local distance = config.ai.chargeDistance
	local travelled = flat(position - action.dashFrom).Magnitude
	if travelled >= distance - 1 or now >= action.dashEndAt then
		endAction(enemy, now, false)
		hold(enemy)
		return
	end
	face(enemy, action.facing)
	enemy.humanoid:MoveTo(action.dashFrom + action.facing * distance)
end

-- The blow lands from positions read NOW, not at the windup: moving out of the telegraph works.
local function resolveAction(
	enemy: Enemy,
	action: Action,
	targets: { TargetInfo },
	now: number,
	config: Types.CombatConfig
): ()
	local position = enemy.root.Position
	local ai = config.ai
	if action.kind == "charge" then
		startDash(enemy, action, now, config)
		return
	end
	if action.kind == "strike" then
		for _, info in targets do
			local offset = flat(info.position - position)
			if offset.Magnitude > enemy.reach + ai.strikeReachPad then
				continue
			end
			if
				offset.Magnitude > MEMBER_RADIUS
				and angleBetween(action.facing, offset) > ai.strikeHalfArcDegrees
			then
				continue
			end
			damageMember(info.member, action.damage)
		end
	elseif action.kind == "shoot" then
		local info = findInfo(targets, action.targetUserId)
		if info ~= nil then
			local offset = flat(info.position - position)
			if
				offset.Magnitude <= enemy.reach + ai.strikeReachPad
				and angleBetween(action.facing, offset) <= ai.shotHalfConeDegrees
				and lineOfSight(enemy, info.root)
			then
				damageMember(info.member, action.damage)
			end
		end
	elseif action.kind == "slam" then
		for _, info in targets do
			if flat(info.position - position).Magnitude <= action.radius + MEMBER_RADIUS then
				damageMember(info.member, action.damage)
			end
		end
	elseif action.kind == "summon" then
		local handler = summonHandler
		local key = action.summonKey
		if handler ~= nil and key ~= nil and action.summonCount > 0 then
			handler(key, action.summonCount, position)
		end
	end
	endAction(enemy, now, false)
end

local function patternViable(
	enemy: Enemy,
	pattern: Types.BossPatternDef,
	info: TargetInfo,
	targets: { TargetInfo },
	config: Types.CombatConfig
): boolean
	local position = enemy.root.Position
	if pattern.kind == "slam" then
		local radius = pattern.radius or DEFAULT_SLAM_RADIUS
		for _, other in targets do
			if flat(other.position - position).Magnitude <= radius + SLAM_TRIGGER_MARGIN then
				return true
			end
		end
		return false
	elseif pattern.kind == "charge" then
		local distance = flat(info.position - position).Magnitude
		return distance >= enemy.reach
			and distance <= config.ai.chargeDistance * CHARGE_TRIGGER_FRACTION
			and lineOfSight(enemy, info.root)
	elseif pattern.kind == "summon" then
		local missionConfig = mission
		local key = pattern.enemy
		return missionConfig ~= nil and key ~= nil and missionConfig.enemies[key] ~= nil
	end
	-- An unknown kind in a mission file is skipped, never an error.
	return false
end

-- Bosses cycle their patterns round-robin, each on its own cooldown, alongside the ordinary
-- attack. The first ready-and-viable pattern after the last one used fires.
local function tryPattern(
	enemy: Enemy,
	info: TargetInfo,
	targets: { TargetInfo },
	now: number,
	config: Types.CombatConfig
): boolean
	local count = #enemy.patterns
	if count == 0 then
		return false
	end
	for step = 0, count - 1 do
		local index = (enemy.patternCursor + step - 1) % count + 1
		local pattern = enemy.patterns[index]
		if
			now < enemy.patternReadyAt[index]
			or not patternViable(enemy, pattern, info, targets, config)
		then
			continue
		end
		enemy.patternCursor = index % count + 1
		local windup = math.max(0, pattern.windupSeconds)
		enemy.patternReadyAt[index] = now + windup + math.max(0, pattern.cooldown)
		local damage = enemy.damage * (pattern.damageMult or 1)
		local toTarget = info.position - enemy.root.Position
		if pattern.kind == "slam" then
			beginAction(
				enemy,
				"slam",
				windup,
				toTarget,
				info.member.userId,
				damage,
				pattern.radius or DEFAULT_SLAM_RADIUS,
				true,
				now
			)
		elseif pattern.kind == "charge" then
			beginAction(
				enemy,
				"charge",
				windup,
				toTarget,
				info.member.userId,
				damage,
				laneHalfWidth(enemy, pattern),
				true,
				now
			)
		else
			local action =
				beginAction(enemy, "summon", windup, toTarget, info.member.userId, 0, 0, true, now)
			action.summonKey = pattern.enemy
			action.summonCount = math.max(0, math.floor(pattern.count or DEFAULT_SUMMON_COUNT))
		end
		return true
	end
	return false
end

-- Melee: a slot holder walks to its slot and swings when in reach; everyone else circles at
-- holdRadius facing the fight. Bosses skip the slot rule and walk straight in.
local function behaveMelee(
	enemy: Enemy,
	info: TargetInfo,
	neighbours: { Neighbour },
	now: number,
	config: Types.CombatConfig
): ()
	local toTarget = flat(info.position - enemy.root.Position)
	local distance = toTarget.Magnitude
	local slotted = enemy.isBoss or enemy.slotIndex > 0
	if slotted and distance <= enemy.reach and now >= enemy.nextAttackAt then
		beginAction(
			enemy,
			"strike",
			config.ai.telegraphSeconds,
			toTarget,
			info.member.userId,
			enemy.damage,
			enemy.reach,
			false,
			now
		)
		return
	end
	if enemy.isBoss then
		local ring = math.max(SLOT_MIN_RING, enemy.reach * SLOT_REACH_FRACTION)
		local goal = info.position - unitOr(toTarget, Vector3.xAxis) * ring
		steer(enemy, goal, enemy.speed, neighbours, now, config)
	elseif enemy.slotIndex > 0 then
		steer(
			enemy,
			slotPoint(enemy, info.position, slotCount(config)),
			enemy.speed,
			neighbours,
			now,
			config
		)
	else
		local goal, speed = circlePoint(enemy, info.position, config.ai.holdRadius, config)
		steer(enemy, goal, speed, neighbours, now, config)
	end
	face(
		enemy,
		if distance <= config.ai.holdRadius + ENGAGE_FACE_MARGIN
			then toTarget
			else enemy.humanoid.MoveDirection
	)
end

-- Charger: in a slot it fights like a melee enemy; out of one it circles the hold ring and,
-- whenever its attack is ready and the lane is clear, winds up and dashes through the target.
local function behaveCharger(
	enemy: Enemy,
	info: TargetInfo,
	neighbours: { Neighbour },
	now: number,
	config: Types.CombatConfig
): ()
	local toTarget = flat(info.position - enemy.root.Position)
	local distance = toTarget.Magnitude
	if enemy.slotIndex == 0 and now >= enemy.nextAttackAt then
		if
			distance >= enemy.reach
			and distance <= config.ai.chargeDistance * CHARGE_TRIGGER_FRACTION
			and lineOfSight(enemy, info.root)
		then
			beginAction(
				enemy,
				"charge",
				config.ai.chargeWindupSeconds,
				toTarget,
				info.member.userId,
				enemy.damage,
				laneHalfWidth(enemy, nil),
				false,
				now
			)
			return
		end
	end
	behaveMelee(enemy, info, neighbours, now, config)
end

-- Shooter: holds the [rangedMinDistance, rangedMaxDistance] band, backs off when rushed, closes
-- in when too far, sidesteps at full speed to find a line past cover, and strafes between shots.
local function behaveRanged(
	enemy: Enemy,
	info: TargetInfo,
	neighbours: { Neighbour },
	now: number,
	config: Types.CombatConfig
): ()
	local offset = flat(enemy.root.Position - info.position)
	local distance = offset.Magnitude
	local away = unitOr(offset, ringDirection(enemy.id * GOLDEN_ANGLE))
	local bandMax = math.min(config.ai.rangedMaxDistance, enemy.reach)
	local bandMin = math.min(config.ai.rangedMinDistance, bandMax * 0.6)
	local visible = lineOfSight(enemy, info.root)
	if visible and distance <= enemy.reach and now >= enemy.nextAttackAt then
		beginAction(
			enemy,
			"shoot",
			config.ai.telegraphSeconds,
			-offset,
			info.member.userId,
			enemy.damage,
			0,
			false,
			now
		)
		return
	end
	if distance < bandMin then
		steer(enemy, info.position + away * (bandMin + 2), enemy.speed, neighbours, now, config)
	elseif not visible then
		local goal = circlePoint(
			enemy,
			info.position,
			math.max(bandMin, math.min(distance, bandMax) - 2),
			config
		)
		steer(enemy, goal, enemy.speed, neighbours, now, config)
	elseif distance > bandMax then
		steer(enemy, info.position + away * (bandMax - 2), enemy.speed, neighbours, now, config)
	else
		local goal, speed = circlePoint(enemy, info.position, distance, config)
		steer(enemy, goal, speed, neighbours, now, config)
	end
	face(
		enemy,
		if distance <= bandMax + ENGAGE_FACE_MARGIN then -offset else enemy.humanoid.MoveDirection
	)
end

local function tickEnemy(
	enemy: Enemy,
	now: number,
	delta: number,
	config: Types.CombatConfig,
	targets: { TargetInfo },
	neighbours: { Neighbour }
): ()
	if enemy.dead then
		return
	end
	if enemy.root.Position.Y < VOID_Y or enemy.model.Parent == nil then
		-- Reaped before FallenPartsDestroyHeight gets to it, so `alive` is right this frame.
		killEnemy(enemy, 0)
		return
	end
	if now >= enemy.strafeFlipAt then
		enemy.strafeSign = -enemy.strafeSign
		enemy.strafeFlipAt = now + STRAFE_FLIP_SECONDS + (enemy.id % 4) * STRAFE_FLIP_SPREAD
	end

	local action = enemy.action
	local stunned = now < enemy.stunUntil
	if action ~= nil and not stunned then
		if action.dashing then
			updateDash(enemy, action, targets, now, config)
		elseif now >= action.impactAt then
			resolveAction(enemy, action, targets, now, config)
		else
			enemy.humanoid:MoveTo(enemy.root.Position)
			face(enemy, action.facing)
		end
	elseif stunned or now < enemy.staggerUntil then
		hold(enemy)
	else
		local info = retarget(enemy, targets, now, config)
		if info == nil then
			hold(enemy)
		elseif not (enemy.isBoss and tryPattern(enemy, info, targets, now, config)) then
			-- A pattern that fired has begun its windup; the ordinary attack waits for it.
			if enemy.kind == "ranged" then
				behaveRanged(enemy, info, neighbours, now, config)
			elseif enemy.kind == "charger" and not enemy.isBoss then
				behaveCharger(enemy, info, neighbours, now, config)
			else
				-- Bosses built on a charger key charge only through their `charge` pattern, as
				-- sim_combat.py models them.
				behaveMelee(enemy, info, neighbours, now, config)
			end
		end
	end
	pose(enemy, now, delta)
end

local function tickAll(elapsed: number, config: Types.CombatConfig): ()
	local now = os.clock()
	local targets = snapshotTargets()
	local neighbours: { Neighbour } = {}
	for _, enemy in enemies do
		if not enemy.dead then
			table.insert(neighbours, { enemy = enemy, position = enemy.root.Position })
		end
	end
	-- Retarget before slotting so a slot is never assigned against last tick's target.
	for _, enemy in enemies do
		if not enemy.dead and enemy.action == nil then
			retarget(enemy, targets, now, config)
		end
	end
	assignSlots(targets, config)
	for _, enemy in table.clone(enemies) do
		tickEnemy(enemy, now, elapsed, config, targets, neighbours)
	end
end

function EnemyService.Init(): ()
	combatConfig = Catalog.GetCombatConfig()
	local existing = workspace:FindFirstChild(ENEMY_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		enemiesFolder = existing
	else
		local created = Instance.new("Folder")
		created.Name = ENEMY_FOLDER_NAME
		created.Parent = workspace
		enemiesFolder = created
	end
	sightParams.FilterDescendantsInstances = { enemiesFolder :: Folder }
	-- Off the boot thread: the avatar call yields and can take seconds without API access, and
	-- blocking Init would leave Main's remote handlers unregistered that whole time. Until it
	-- lands, buildRig falls back to the block rig, which is the documented degrade anyway.
	task.spawn(function()
		placeholderTemplate = buildPlaceholderTemplate()
	end)
end

function EnemyService.Start(): ()
	if aiConnection ~= nil then
		return
	end
	aiConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		local config = combatConfig
		if config == nil or #enemies == 0 then
			return
		end
		tickAccumulator += deltaTime
		if tickAccumulator < tickInterval() then
			return
		end
		local elapsed = tickAccumulator
		tickAccumulator = 0
		tickAll(elapsed, config)
	end)
end

return EnemyService
