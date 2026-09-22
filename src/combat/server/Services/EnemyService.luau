--!strict
-- Enemy rigs and their AI (docs/INTERFACES.md "C1 contracts" → "Enemy models"). Everything an
-- enemy is lives here: the model, the walk/attack loop, its HP and who has damaged it.
--
-- Two rules shape the whole module:
-- * Enemies NEVER damage a Humanoid directly through touch or physics. Every point of damage in
--   both directions goes through CombatService, which is the only place god mode, contribution
--   tracking and kill credit are applied.
-- * This service sits at the BOTTOM of the combat boot order, so it requires none of
--   ArenaService/CombatService/WaveService. They hand it the party roster, the damage sink and
--   the kill callback through SetHooks, which is what keeps the requires acyclic.
--
-- No model is required to ship: a cloned placeholder R15 rig (and, if even that fails, a block
-- rig built in code) is the default, recoloured per enemy key.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

-- Presentation constants, deliberately not in Combat.json: the C1 contract freezes that file's
-- keys, and a colour per enemy key is content rather than balance. Moving them into the mission
-- JSON is a follow-up.
local KEY_COLORS: { [string]: Color3 } = {
	raider = Color3.fromRGB(150, 84, 54),
	archer = Color3.fromRGB(110, 122, 70),
	brute = Color3.fromRGB(120, 44, 44),
}
local DEFAULT_ENEMY_COLOR = Color3.fromRGB(128, 96, 96)
local BOSS_COLOR = Color3.fromRGB(96, 26, 30)
local BOT_FALLBACK_COLOR = Color3.fromRGB(70, 120, 190)
-- Two enemies handed the same rim spawn would arrive inside each other, so each one is nudged
-- around a small ring by its own id. Deterministic: no RNG anywhere in a run.
local SPAWN_RING_RADIUS = 3.5
local SPAWN_RING_STEP_RADIANS = 2.39996
local ENEMY_FOLDER_NAME = "Enemies"
-- Degrade values used only when Combat.json is missing (the place then never starts a wave).
local DEFAULT_TICK_HZ = 10
local DEFAULT_CORPSE_SECONDS = 0.6
-- The windup pose: the attacking arm swings up, then snaps back on the hit. Server writes to a
-- Motor6D replicate for free, so every client sees the tell without a single remote.
local WINDUP_ARM_DEGREES = -70
local WALK_BOB_DEGREES = 6
local WALK_BOB_HZ = 2.2
-- Spawn clearance above the arena floor, so a rig never starts inside it.
local SPAWN_LIFT = 3
-- The ArenaLayout contract puts the floor's top face at y = 0, so anything this far below it
-- has fallen off the map (a 40-stud axe knockback clears the 4-stud fence) and is on its way to
-- FallenPartsDestroyHeight. Reaped so it stops counting as alive.
local VOID_Y = -20

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
	dead: boolean,
	-- os.clock() stamps.
	nextAttackAt: number,
	retargetAt: number,
	stunUntil: number,
	targetUserId: number,
	walkPhase: number,
	attackJoint: Motor6D?,
	attackJointRest: CFrame?,
	waistJoint: Motor6D?,
	waistRest: CFrame?,
	walkTrack: AnimationTrack?,
	attackTrack: AnimationTrack?,
	deathTrack: AnimationTrack?,
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
}

local hooks: Hooks? = nil
local combatConfig: Types.CombatConfig? = nil
local mission: Types.MissionConfig? = nil
local enemiesFolder: Folder? = nil
local placeholderTemplate: Model? = nil
local spawnPoints: { Vector3 } = {}
local enemies: { Enemy } = {}
local byId: { [number]: Enemy } = {}
local nextEnemyId = 1
local tickAccumulator = 0
local aiConnection: RBXScriptConnection? = nil

local EnemyService = {}

local function tickInterval(): number
	local config = combatConfig
	local hz = if config ~= nil then config.enemy.tickHz else DEFAULT_TICK_HZ
	if hz <= 0 then
		return 1 / DEFAULT_TICK_HZ
	end
	return 1 / hz
end

-- "RaiderChief" becomes "Raider Chief": the template name is what the HUD shows, and a boss
-- banner reading "RaiderChief" looks like a bug.
local function humanise(name: string): string
	local spaced = string.gsub(name, "(%l)(%u)", "%1 %2")
	return spaced
end

local function colorFor(key: string, isBoss: boolean): Color3
	if isBoss then
		return BOSS_COLOR
	end
	return KEY_COLORS[key] or DEFAULT_ENEMY_COLOR
end

local function paint(model: Model, color: Color3): ()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = color
			-- Placeholder rigs ship with the default avatar look; flattening the material is
			-- what makes the recolour readable at tycoon camera distance.
			descendant.Material = Enum.Material.SmoothPlastic
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant:Destroy()
		end
	end
end

-- A four-part stand-in for the days CreateHumanoidModelFromDescription cannot reach the avatar
-- endpoint (offline Studio, throttling). It walks, it takes damage, it dies: that is all a wave
-- needs, and it is never an error.
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

-- Returns the model plus the two parts the AI drives.
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

-- Shared with ArenaService, which dresses debug bots in the same placeholder rig. Returns an
-- unparented model.
function EnemyService.BuildRig(color: Color3?): (Model, Humanoid, BasePart)
	local model, humanoid, root = buildRig()
	paint(model, color or BOT_FALLBACK_COLOR)
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

local function loadTrack(animator: Animator, assetId: number): AnimationTrack?
	if assetId <= 0 then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{assetId}`
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn(`[EnemyService] animation {assetId} failed to load: {track}`)
		return nil
	end
	return track :: AnimationTrack
end

-- Config animation ids override the procedural Motor6D poses when they are set; an id of 0 (the
-- shipped default) leaves the joints doing the work.
local function setupAnimations(enemy: Enemy): ()
	local config = combatConfig
	if config == nil then
		return
	end
	local ids = config.animations
	if
		ids.enemyIdle == 0
		and ids.enemyWalk == 0
		and ids.enemyAttack == 0
		and ids.enemyDeath == 0
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
	enemy.walkTrack = loadTrack(animator, ids.enemyWalk)
	enemy.attackTrack = loadTrack(animator, ids.enemyAttack)
	enemy.deathTrack = loadTrack(animator, ids.enemyDeath)
	local idle = loadTrack(animator, ids.enemyIdle)
	if idle ~= nil then
		idle.Looped = true
		idle:Play()
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
		elseif descendant.Name == "Waist" and enemy.waistJoint == nil then
			enemy.waistJoint = descendant
			enemy.waistRest = descendant.C0
		end
	end
end

local function spawnPosition(spawnIndex: number, enemyId: number): Vector3
	if #spawnPoints == 0 then
		return Vector3.new(0, SPAWN_LIFT, 0)
	end
	local point = spawnPoints[(spawnIndex - 1) % #spawnPoints + 1]
	local angle = enemyId * SPAWN_RING_STEP_RADIANS
	local offset =
		Vector3.new(math.cos(angle) * SPAWN_RING_RADIUS, 0, math.sin(angle) * SPAWN_RING_RADIUS)
	return point + offset + Vector3.new(0, SPAWN_LIFT, 0)
end

function EnemyService.SetHooks(serviceHooks: Hooks): ()
	hooks = serviceHooks
end

-- ArenaService hands these over once the arena exists; an empty list spawns everything at the
-- origin, which is the "no layout module" degrade path.
function EnemyService.SetSpawnPoints(points: { Vector3 }): ()
	spawnPoints = points
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
-- which is defined after it (it needs removeEnemy).
local killEnemy: (enemy: Enemy, byUserId: number) -> ()

-- A rig can leave the run without anyone hitting it: Humanoid.Died fired by something else, or
-- the model destroyed out of band (FallenPartsDestroyHeight after a knockback over the fence).
-- Without this it would stay in `enemies` forever and the wave would never clear. Rewards are
-- credited normally, to nobody in particular.
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

-- `boss` is the mission BossDef for this wave when isBoss is true: EnemyService does not know
-- the wave number, so the caller (WaveService, which resolved the spec) passes it in.
function EnemyService.Spawn(
	key: string,
	stats: Types.EnemyStats,
	isBoss: boolean,
	spawnIndex: number,
	boss: Types.BossDef?
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
		paint(model, colorFor(key, isBoss))
	end

	local enemyId = nextEnemyId
	nextEnemyId += 1
	applyScale(
		humanoid,
		if isBoss then config.enemy.bossScale elseif def.elite then config.enemy.eliteScale else 1
	)

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

	model:PivotTo(CFrame.new(spawnPosition(spawnIndex, enemyId)))
	model.Parent = folder
	-- Server-owned bodies: a client must never be able to shove an enemy off the arena.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local now = os.clock()
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
		dead = false,
		nextAttackAt = now + def.attackCooldown,
		retargetAt = 0,
		stunUntil = 0,
		targetUserId = 0,
		walkPhase = enemyId,
		attackJoint = nil,
		attackJointRest = nil,
		waistJoint = nil,
		waistRest = nil,
		walkTrack = nil,
		attackTrack = nil,
		deathTrack = nil,
		watchers = {},
	}
	findJoints(enemy)
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

-- Death is presentation-first: the corpse stays for corpseSeconds so the client dissolve has
-- something to dissolve, but the enemy stops counting as alive the moment it dies.
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
	local config = combatConfig
	local corpseSeconds = if config ~= nil
		then config.player.corpseSeconds
		else DEFAULT_CORPSE_SECONDS
	enemy.model:SetAttribute("Dead", true)
	enemy.model:SetAttribute("Attacking", false)
	enemy.humanoid.WalkSpeed = 0
	enemy.humanoid.Health = 0
	local death = enemy.deathTrack
	if death ~= nil then
		death:Play()
	end
	local serviceHooks = hooks
	if serviceHooks ~= nil then
		serviceHooks.onKilled(enemy, byUserId)
	end
	task.delay(corpseSeconds, function()
		enemy.model:Destroy()
	end)
end

-- The single entry point for damage TO an enemy; CombatService is its only caller, so god mode,
-- the per-user tally and the effects all happen in one place. True when this hit killed.
function EnemyService.Damage(enemy: Enemy, amount: number, byUserId: number): boolean
	if enemy.dead or amount <= 0 then
		return false
	end
	enemy.hp -= amount
	if enemy.hp <= 0 then
		killEnemy(enemy, byUserId)
		return true
	end
	enemy.humanoid.Health = enemy.hp
	return false
end

function EnemyService.Stun(enemy: Enemy, seconds: number): ()
	if enemy.dead or seconds <= 0 then
		return
	end
	enemy.stunUntil = math.max(enemy.stunUntil, os.clock() + seconds)
	enemy.humanoid:MoveTo(enemy.root.Position)
end

function EnemyService.Knockback(enemy: Enemy, direction: Vector3, studs: number): ()
	if enemy.dead or studs <= 0 then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude <= 0 then
		return
	end
	enemy.root.AssemblyLinearVelocity = flat.Unit * studs + Vector3.new(0, studs * 0.25, 0)
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
		for _, connection in enemy.watchers do
			connection:Disconnect()
		end
		table.clear(enemy.watchers)
		enemy.model:Destroy()
	end
	table.clear(enemies)
	table.clear(byId)
end

local function memberRoot(member: Types.RunMember): BasePart?
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

local function findTarget(enemy: Enemy, aggroRange: number): (Types.RunMember?, BasePart?)
	local serviceHooks = hooks
	if serviceHooks == nil then
		return nil, nil
	end
	local best: Types.RunMember? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = aggroRange
	for _, member in serviceHooks.targets() do
		local root = memberRoot(member)
		if root == nil then
			continue
		end
		local distance = (root.Position - enemy.root.Position).Magnitude
		if distance <= bestDistance then
			bestDistance = distance
			best = member
			bestRoot = root
		end
	end
	return best, bestRoot
end

local function currentTarget(enemy: Enemy): (Types.RunMember?, BasePart?)
	local serviceHooks = hooks
	if serviceHooks == nil or enemy.targetUserId == 0 then
		return nil, nil
	end
	for _, member in serviceHooks.targets() do
		if member.userId == enemy.targetUserId then
			return member, memberRoot(member)
		end
	end
	return nil, nil
end

local function poseWindup(enemy: Enemy, active: boolean): ()
	local joint = enemy.attackJoint
	local rest = enemy.attackJointRest
	if joint == nil or rest == nil or joint.Parent == nil then
		return
	end
	if active then
		joint.C0 = rest * CFrame.Angles(math.rad(WINDUP_ARM_DEGREES), 0, 0)
	else
		joint.C0 = rest
	end
end

-- Raycast so a ranged enemy cannot shoot through the arena boulders; other enemies are ignored,
-- because friendly fire would turn a crowd into a self-clearing wave.
local function rangedShotLands(enemy: Enemy, targetRoot: BasePart): boolean
	local folder = enemiesFolder
	local origin = enemy.root.Position + Vector3.new(0, 1.5, 0)
	local delta = targetRoot.Position - origin
	if delta.Magnitude <= 0 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if folder ~= nil then { folder } else {}
	local result = workspace:Raycast(origin, delta, params)
	if result == nil then
		return true
	end
	local character = targetRoot.Parent
	return character ~= nil and result.Instance:IsDescendantOf(character)
end

local function strike(enemy: Enemy, member: Types.RunMember): ()
	local serviceHooks = hooks
	if serviceHooks == nil or enemy.dead then
		return
	end
	local root = memberRoot(member)
	if root == nil then
		return
	end
	local distance = (root.Position - enemy.root.Position).Magnitude
	if enemy.kind == "ranged" then
		if distance > enemy.reach or not rangedShotLands(enemy, root) then
			return
		end
	elseif distance > enemy.reach + 1 then
		-- The target walked out of reach during the windup: a tell the player can dodge.
		return
	end
	serviceHooks.damagePlayer(member, enemy.damage)
end

local function attack(enemy: Enemy, member: Types.RunMember, windup: number): ()
	enemy.nextAttackAt = os.clock() + enemy.attackCooldown + windup
	enemy.model:SetAttribute("Attacking", true)
	poseWindup(enemy, true)
	local track = enemy.attackTrack
	if track ~= nil then
		track:Play()
	end
	local userId = member.userId
	task.delay(windup, function()
		if enemy.dead then
			return
		end
		enemy.model:SetAttribute("Attacking", false)
		poseWindup(enemy, false)
		if enemy.targetUserId ~= userId then
			return
		end
		strike(enemy, member)
	end)
end

local function bob(enemy: Enemy, delta: number, moving: boolean): ()
	local joint = enemy.waistJoint
	local rest = enemy.waistRest
	if joint == nil or rest == nil or joint.Parent == nil then
		return
	end
	if not moving then
		joint.C0 = rest
		return
	end
	enemy.walkPhase += delta * WALK_BOB_HZ * math.pi * 2
	joint.C0 = rest * CFrame.Angles(0, 0, math.rad(WALK_BOB_DEGREES) * math.sin(enemy.walkPhase))
end

local function tickEnemy(enemy: Enemy, now: number, delta: number, config: Types.CombatConfig): ()
	if enemy.dead then
		return
	end
	if enemy.root.Position.Y < VOID_Y or enemy.model.Parent == nil then
		-- Reaped before FallenPartsDestroyHeight gets to it, so `alive` is right this frame.
		killEnemy(enemy, 0)
		return
	end
	if now < enemy.stunUntil then
		enemy.humanoid:MoveTo(enemy.root.Position)
		bob(enemy, delta, false)
		return
	end

	local member, targetRoot = currentTarget(enemy)
	if member == nil or targetRoot == nil or now >= enemy.retargetAt then
		local found, foundRoot = findTarget(enemy, config.enemy.aggroRange)
		if found == nil then
			-- Fallback: aggroRange (80) is smaller than a Village rim spawn is from the far
			-- corner (~155 studs), so an enemy with nobody in range must still WALK toward the
			-- nearest member. Standing idle would leave the wave uncleared forever, which the
			-- run cap is not supposed to be the answer to.
			found, foundRoot = findTarget(enemy, math.huge)
		end
		if found ~= nil and foundRoot ~= nil then
			member, targetRoot = found, foundRoot
			enemy.targetUserId = found.userId
		elseif member == nil then
			enemy.targetUserId = 0
		end
		enemy.retargetAt = now + config.enemy.retargetSeconds
	end
	if member == nil or targetRoot == nil then
		bob(enemy, delta, false)
		return
	end

	local distance = (targetRoot.Position - enemy.root.Position).Magnitude
	local inRange = distance <= enemy.reach
	if inRange then
		enemy.humanoid:MoveTo(enemy.root.Position)
		-- Face the target even while standing still, so the windup reads as aimed.
		local flat =
			Vector3.new(targetRoot.Position.X, enemy.root.Position.Y, targetRoot.Position.Z)
		if (flat - enemy.root.Position).Magnitude > 0.1 then
			enemy.root.CFrame = CFrame.lookAt(enemy.root.Position, flat)
		end
	else
		enemy.humanoid:MoveTo(targetRoot.Position)
	end
	bob(enemy, delta, not inRange)
	local walk = enemy.walkTrack
	if walk ~= nil then
		if not inRange and not walk.IsPlaying then
			walk.Looped = true
			walk:Play()
		elseif inRange and walk.IsPlaying then
			walk:Stop()
		end
	end

	if inRange and now >= enemy.nextAttackAt then
		attack(enemy, member, config.enemy.attackWindupSeconds)
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
	-- Off the boot thread: the avatar call yields and can take seconds without API access, and
	-- blocking Init would leave Main's remote handlers unregistered that whole time. Until it
	-- lands, buildRig falls back to the block rig — which is the documented degrade anyway.
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
		local interval = tickInterval()
		if tickAccumulator < interval then
			return
		end
		local elapsed = tickAccumulator
		tickAccumulator = 0
		local now = os.clock()
		for _, enemy in table.clone(enemies) do
			tickEnemy(enemy, now, elapsed, config)
		end
	end)
end

return EnemyService
