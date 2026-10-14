--!strict
-- The session: who is in this dungeon server, and the authoritative RunState (docs/INTERFACES.md
-- "C0 contracts" → "Combat place server", "C2 contracts" → "Combat place (A)", "L1 contracts"
-- rulings 3–7 and 18).
--
-- L1 splits what C1's `runMission` did in one variable. A SESSION is the party on this server:
-- host, ticket, roster, admission, the summaries and the registry entry. It opens at the first
-- arrival and ends when the last human leaves. What is PLAYED is a level, set by WaveService at
-- each start (SetLevel) and cleared at each return to the lobby. Any admitted party lands in the
-- lobby camp, whatever mission its hub departure named: that id is kept for one thing, the key
-- the hub's ticket is verified against.
--
-- This file builds nothing of a level and decides nowhere a body goes. LevelService owns the
-- Instances; WaveService hands in the placer (StageFlow's rule for where a member belongs);
-- MoveMember here is the one function that moves a member's body. The C1 arena builder stays
-- for the range alone (BuildProvingArena, ProvingSpawn), unchanged.
--
-- The weapons decide max HP: a human's Humanoid is VitalsService's alone (P5 ruling 11); this
-- file sizes only the debug bots.
--
-- The run's numbers in RunState are pushed here by WaveService through SetRunFields: WaveService
-- sits above this service in the boot order, so it cannot be required from here, and one payload
-- builder for the whole HUD is worth the indirection.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local CombatMode = require(sharedFolder:WaitForChild("CombatMode"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local RunRegistry = require(script.Parent:WaitForChild("RunRegistry"))
local EnemyService = require(script.Parent:WaitForChild("EnemyService"))
local BarrierGroups = require(script.Parent:WaitForChild("BarrierGroups"))

-- The range's degrade arena: no Layouts/Arenas/<name> module means one pad and no walls.
local FALLBACK_FLOOR_SIZE = 110
local FALLBACK_FLOOR_COLOR = Color3.fromRGB(106, 127, 63)
local ARENA_FOLDER_NAME = "Arena"
local LOBBY_PAD_SIZE = Vector3.new(6, 1, 6)
local SPAWN_SIZE = Vector3.new(6, 1, 6)
-- Studs above a feet point a character is placed at, so nobody is put inside the geometry.
local SPAWN_CLEARANCE = 4
local WALL_THICKNESS = 1
local BOT_USER_ID_BASE = -1000
local DEFAULT_BOT_HP = 150
-- What MoveMember writes on the character it moved, for the client that owns the body: where
-- its feet were put (a Vector3) and a count that goes up by one with every move.
local PLACED_ATTRIBUTE = "Placed"
local PLACED_SEQ_ATTRIBUTE = "PlacedSeq"
local NEUTRAL_EMPOWER = 1
-- Shown as the session card's title when Expeditions.json is missing.
local DEFAULT_SESSION_NAME = "Expeditions"

-- The verdict every arrival gets before Admit. "ok" admits; anything else is a refusal the hub
-- shows on the way back (ReturnData.refused).
export type Admission = "ok" | "full" | "over" | "locked"
-- probe = the admitCheck lever: judge the caller as a STRANGER arriving right now (their own seat
-- still counted, their membership and any expected-list entry ignored), so one Studio client can
-- see the verdict a real joiner would get without anyone being sent home.
export type AdmissionHint = { probe: boolean }
-- What is being played (L1 ruling 3). `mission` = the mission whose record the level writes.
export type LevelInfo = {
	id: string,
	name: string,
	difficulty: string,
	material: string,
	mission: string?,
}

local partyOrder: { number } = {}
local party: { [number]: Types.RunMember } = {}
local byPlayer: { [Player]: Types.RunMember } = {}
-- Rebuilt lazily by GetMembers and dropped by every roster change; see GetMembers for why.
local memberCache: { Types.RunMember }? = nil
local characterConnections: { [Player]: { RBXScriptConnection } } = {}
local combatConfig: Types.CombatConfig? = nil

-- The session (ruling 3): open from the first arrival until the last human leaves.
local session = {
	open = false,
	-- The hub departure's hint, kept only as the key its ticket is verified against (ruling 4).
	missionId = "",
	overdrive = false,
	hostUserId = 0,
	hostName = "",
	-- The verified hub ticket; nil = a private session (no code, no expected list, not published).
	ticket = nil :: Types.RunTicket?,
	-- True while the first arrival's ResolveTicket is in flight. Later arrivals park on `waiters`
	-- until it lands, because admission reads the ticket (the expected list).
	ticketPending = false,
	waiters = {} :: { thread },
	-- os.clock() of the first admit of this session, for coop.lobbyWaitSeconds.
	firstArrivalAt = 0,
	-- Every userId admitted at least once: an expected member who arrived and then left must not
	-- hold the lobby for the whole wait.
	everAdmitted = {} :: { [number]: boolean },
	warnedUnjoinable = false,
	-- Where a member's body respawns by Roblox's own rule (LevelService's lobby SpawnLocation).
	lobbySpawn = nil :: SpawnLocation?,
}

-- What is played right now (nil = the lobby), and what each member's card and trip home show.
local play = {
	level = nil :: LevelInfo?,
	-- os.clock() the run started and ended (0 = not yet): the run card's seconds stop at the end.
	startedAt = 0,
	endedAt = 0,
	-- Per member: the run's summary (reset at each start; the card shows it), the session's (every
	-- credit since the admit; the trip home carries it), and the run's result.
	runSummaries = {} :: { [number]: Types.RunSummary },
	sessionSummaries = {} :: { [number]: Types.RunSummary },
	admittedAt = {} :: { [number]: number },
	results = {} :: { [number]: Types.RunResult },
	-- Per userId: how many times MoveMember has moved their body (the PlacedSeq attribute). Kept
	-- across their characters and for the life of the server (a failed trip home re-admits the
	-- same client), so one client never sees a value twice.
	placedSeq = {} :: { [number]: number },
}

-- Handed in by the services above this one in the boot order.
local hooks = {
	sendSnapshot = nil :: ((player: Player) -> ())?,
	-- WaveService's run-wide raw damage share.
	share = nil :: ((userId: number) -> number)?,
	-- WaveService.Reset: called when the session ends.
	reset = nil :: (() -> ())?,
	-- Called last whenever a member's character is added (WeaponService.PrepareCharacter).
	character = nil :: ((player: Player, character: Model) -> ())?,
	-- Is this member down (VitalsService), for PartyMember.down.
	down = nil :: ((userId: number) -> boolean)?,
	-- Called after every move this service makes of a human's body, so whoever measures that
	-- body's motion can forget the jump (WeaponService.ForgetMotion).
	moved = nil :: ((player: Player) -> ())?,
	-- L1 ruling 18: where a member's body belongs right now (feet), and whether they wait.
	placer = nil :: ((member: Types.RunMember) -> (Vector3, boolean))?,
}

-- The range's arena (BuildProvingArena): the C1 builder's state. Nothing of a mission is here.
local arena = {
	folder = nil :: Folder?,
	built = "",
	spawn = nil :: SpawnLocation?,
	lobbyPosition = Vector3.zero,
	playerSpawns = {} :: { Vector3 },
	spawnCursor = 0,
	-- Half the floor's footprint of the arena last built (X and Z).
	floorHalfSize = Vector3.new(FALLBACK_FLOOR_SIZE / 2, 0, FALLBACK_FLOOR_SIZE / 2),
}

-- Everything WaveService owns in the RunState payload, defaulted to the lobby.
export type RunFields = {
	phase: Types.RunPhase,
	-- `wave` and `waves` count inside the live camp.
	wave: number,
	waves: number,
	alive: number,
	remaining: number,
	tempo: number,
	merged: boolean,
	breatherEndsIn: number?,
	runEndsIn: number,
	-- True in the five live phases: travel, gate, wave, boss, breather.
	inRun: boolean,
	returnIn: number?,
	stage: number,
	stages: number,
	stageKind: string,
	stageName: string,
	campsCleared: number,
	camps: number,
	left: number,
	bossName: string?,
	gateIn: number?,
	banked: number,
	floor: Types.RunFloor?,
	maxAlive: number,
}
local runFields: RunFields = {
	phase = "lobby",
	wave = 0,
	waves = 0,
	alive = 0,
	remaining = 0,
	tempo = 1,
	merged = false,
	breatherEndsIn = nil,
	runEndsIn = 0,
	inRun = false,
	returnIn = nil,
	stage = 0,
	stages = 0,
	stageKind = "",
	stageName = "",
	campsCleared = 0,
	camps = 0,
	left = 0,
	bossName = nil,
	gateIn = nil,
	banked = 0,
	floor = nil,
	maxAlive = 0,
}

local ArenaService = {}

-- The range's arena builder (C1, unchanged) --------------------------------------------------

local function colorOf(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

local function materialOf(name: string): Enum.Material
	local material = (Enum.Material :: any)[name]
	if typeof(material) == "EnumItem" then
		return material :: Enum.Material
	end
	warn(`[ArenaService] unknown material "{name}"; using Plastic`)
	return Enum.Material.Plastic
end

local function newPart(name: string, size: Vector3, position: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	-- The arena's own collision group, kept from C1 (EnemyService registers it; it is never
	-- Init'd since P5, so the group is the default one until L4 removes this).
	local group = EnemyService.ArenaCollisionGroup()
	if group ~= nil then
		part.CollisionGroup = group
	end
	part.Parent = parent
	return part
end

-- The arena is code-built so nothing in the place file has to be kept in sync.
local function loadLayout(arenaName: string): Types.ArenaLayout?
	local layoutsFolder = sharedFolder:FindFirstChild("Layouts")
	local arenasFolder = if layoutsFolder ~= nil
		then layoutsFolder:FindFirstChild("Arenas")
		else nil
	if arenasFolder == nil then
		return nil
	end
	local module = arenasFolder:FindFirstChild(arenaName)
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, layout = pcall(require, module)
	if not ok or typeof(layout) ~= "table" then
		warn(`[ArenaService] arena layout {arenaName} failed to load: {layout}`)
		return nil
	end
	return layout :: Types.ArenaLayout
end

local function buildLobbyPad(folder: Folder, position: Vector3, color: Color3): ()
	local pad = newPart("LobbyPad", LOBBY_PAD_SIZE, position, folder)
	pad.Color = color
	pad.Material = Enum.Material.Concrete

	-- A real SpawnLocation (not just a PivotTo): Roblox respawns a dead player at
	-- Player.RespawnLocation, which only accepts one.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = SPAWN_SIZE
	spawn.Position = position + Vector3.new(0, LOBBY_PAD_SIZE.Y / 2 + SPAWN_SIZE.Y / 2, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = pad
	arena.spawn = spawn
	arena.lobbyPosition = position
end

local function buildFallbackArena(folder: Folder): ()
	local floor = newPart(
		"Floor",
		Vector3.new(FALLBACK_FLOOR_SIZE, 1, FALLBACK_FLOOR_SIZE),
		Vector3.new(0, -0.5, 0),
		folder
	)
	floor.Color = FALLBACK_FLOOR_COLOR
	floor.Material = Enum.Material.Grass
	arena.floorHalfSize = Vector3.new(FALLBACK_FLOOR_SIZE / 2, 0, FALLBACK_FLOOR_SIZE / 2)
	buildLobbyPad(folder, Vector3.new(0, 0.5, 0), Color3.fromRGB(96, 104, 120))
	arena.playerSpawns = { arena.lobbyPosition }
	EnemyService.SetSpawnPoints({})
	EnemyService.SetArenaGeometry({}, {}, floor)
end

local function buildFromLayout(folder: Folder, layout: Types.ArenaLayout): ()
	local sizeX = layout.size.x
	local sizeZ = layout.size.z
	local floor = newPart("Floor", Vector3.new(sizeX, 1, sizeZ), Vector3.new(0, -0.5, 0), folder)
	floor.Color = colorOf(layout.floor.color)
	floor.Material = materialOf(layout.floor.material)
	arena.floorHalfSize = Vector3.new(sizeX / 2, 0, sizeZ / 2)

	local fence: { BasePart } = {}
	local wall = layout.wall
	if wall ~= nil then
		local height = wall.height
		local color = colorOf(wall.color)
		local material = materialOf(wall.material)
		local halfX = sizeX / 2 + WALL_THICKNESS / 2
		local halfZ = sizeZ / 2 + WALL_THICKNESS / 2
		local sides = {
			{
				size = Vector3.new(sizeX + WALL_THICKNESS * 2, height, WALL_THICKNESS),
				position = Vector3.new(0, height / 2, -halfZ),
			},
			{
				size = Vector3.new(sizeX + WALL_THICKNESS * 2, height, WALL_THICKNESS),
				position = Vector3.new(0, height / 2, halfZ),
			},
			{
				size = Vector3.new(WALL_THICKNESS, height, sizeZ),
				position = Vector3.new(-halfX, height / 2, 0),
			},
			{
				size = Vector3.new(WALL_THICKNESS, height, sizeZ),
				position = Vector3.new(halfX, height / 2, 0),
			},
		}
		for index, side in sides do
			local part = newPart(`Fence{index}`, side.size, side.position, folder)
			part.Color = color
			part.Material = material
			table.insert(fence, part)
		end
		-- The invisible wall behind the fence (P5 review): from the floor up to `barrierHeight`,
		-- its inner face on the fence's outer face, `barrierThickness` deep outward, the two Z
		-- sides running past the X sides so the corners close. Only characters collide with it
		-- (BarrierGroups), and it is not handed to EnemyService as a wall.
		local barrierHeight = wall.barrierHeight
		if barrierHeight ~= nil and barrierHeight > 0 and BarrierGroups.Ensure() then
			local depth = math.max(wall.barrierThickness or WALL_THICKNESS, WALL_THICKNESS)
			local outerX = sizeX / 2 + WALL_THICKNESS
			local outerZ = sizeZ / 2 + WALL_THICKNESS
			local barriers = {
				{
					size = Vector3.new((outerX + depth) * 2, barrierHeight, depth),
					position = Vector3.new(0, barrierHeight / 2, -(outerZ + depth / 2)),
				},
				{
					size = Vector3.new((outerX + depth) * 2, barrierHeight, depth),
					position = Vector3.new(0, barrierHeight / 2, outerZ + depth / 2),
				},
				{
					size = Vector3.new(depth, barrierHeight, outerZ * 2),
					position = Vector3.new(-(outerX + depth / 2), barrierHeight / 2, 0),
				},
				{
					size = Vector3.new(depth, barrierHeight, outerZ * 2),
					position = Vector3.new(outerX + depth / 2, barrierHeight / 2, 0),
				},
			}
			for index, side in barriers do
				local barrier = newPart(`Barrier{index}`, side.size, side.position, folder)
				barrier.CollisionGroup = BarrierGroups.BARRIER
				barrier.Transparency = 1
				barrier.CanTouch = false
				barrier.CastShadow = false
			end
		end
	end

	-- Handed to EnemyService: only real cover sends an enemy to the pathfinder.
	local cover: { BasePart } = {}
	for index, obstacle in layout.obstacles do
		local part = newPart(
			`Obstacle{index}`,
			Vector3.new(obstacle.sx, obstacle.sy, obstacle.sz),
			Vector3.new(obstacle.x, obstacle.sy / 2, obstacle.z),
			folder
		)
		part.Color = colorOf(obstacle.color)
		part.Material = materialOf(obstacle.material)
		table.insert(cover, part)
	end
	EnemyService.SetArenaGeometry(cover, fence, floor)

	buildLobbyPad(
		folder,
		Vector3.new(layout.lobbyPad.x, LOBBY_PAD_SIZE.Y / 2, layout.lobbyPad.z),
		colorOf(layout.floor.color):Lerp(Color3.new(1, 1, 1), 0.35)
	)

	arena.playerSpawns = {}
	for _, point in layout.playerSpawns do
		table.insert(arena.playerSpawns, Vector3.new(point.x, 0, point.z))
	end
	if #arena.playerSpawns == 0 then
		arena.playerSpawns = { arena.lobbyPosition }
	end

	local enemyPoints: { Vector3 } = {}
	for _, point in layout.enemySpawns do
		table.insert(enemyPoints, Vector3.new(point.x, 0, point.z))
	end
	EnemyService.SetSpawnPoints(enemyPoints)
end

-- The range's folder, made on first use: a mission server never has one.
local function arenaFolder(): Folder
	local folder = arena.folder
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = ARENA_FOLDER_NAME
		created.Parent = workspace
		arena.folder = created
		return created
	end
	return folder
end

-- Idempotent per arena name: the range builds its own arena over the fallback pad of Init.
local function ensureArena(arenaName: string): ()
	local folder = arenaFolder()
	if arena.built == arenaName then
		return
	end
	folder:ClearAllChildren()
	arena.spawn = nil
	local layout = loadLayout(arenaName)
	if layout == nil then
		warn(`[ArenaService] no Layouts/Arenas/{arenaName}; using the bare pad`)
		buildFallbackArena(folder)
	else
		buildFromLayout(folder, layout)
	end
	arena.built = arenaName
end

local function nextPlayerSpawn(): CFrame
	local spawns = arena.playerSpawns
	if #spawns == 0 then
		return CFrame.new(arena.lobbyPosition + Vector3.new(0, SPAWN_CLEARANCE, 0))
	end
	arena.spawnCursor += 1
	local point = spawns[(arena.spawnCursor - 1) % #spawns + 1]
	return CFrame.new(point + Vector3.new(0, SPAWN_CLEARANCE, 0))
end

-- P1 Proving Grounds (docs/INTERFACES.md "P1 contracts"). The range opens no session and admits
-- nobody: it only borrows the arena builder and the spawn points. Returns the floor's bounds
-- (centre, half-size) for CrowdService.SetBounds. halfSize.Y is the highest a launch may carry a
-- dummy above the floor: levels.crowdCeiling, the same key a level's camp reads. (The range only
-- boots with Combat.json, so the 0 is never the answer.)
function ArenaService.BuildProvingArena(arenaName: string): (Vector3, Vector3)
	ensureArena(arenaName)
	local half = arena.floorHalfSize
	local config = Catalog.GetCombatConfig()
	local ceiling = if config ~= nil then config.levels.crowdCeiling else 0
	return Vector3.zero, Vector3.new(half.X, ceiling, half.Z)
end

-- Where a range player (re)spawns: the lobby SpawnLocation for Roblox's own respawn, and the
-- round-robin player spawn the body is moved to.
function ArenaService.ProvingSpawn(): (SpawnLocation?, CFrame)
	return arena.spawn, nextPlayerSpawn()
end

-- Members and their summaries ----------------------------------------------------------------

-- Bots only (P5 ruling 11): a human's maximum is VitalsService's, through the character hook.
local function applyMaxHp(member: Types.RunMember): ()
	local humanoid = member.humanoid
	if humanoid == nil or not member.bot then
		return
	end
	local config = combatConfig
	local botHp = if config ~= nil then config.debug.botHp else DEFAULT_BOT_HP
	humanoid.MaxHealth = botHp
	humanoid.Health = botHp
end

local function emptySummary(missionId: string): Types.RunSummary
	return {
		missionId = missionId,
		-- L1 ruling 24: Overdrive is inert; the field stays for the hub's card.
		overdrive = false,
		wavesCleared = 0,
		bestWave = 0,
		died = false,
		cash = 0,
		materials = {},
		valor = 0,
		kills = 0,
		seconds = 0,
		mentorValor = 0,
		damageShare = 0,
	}
end

-- The session card's title: the map's name.
local function sessionName(): string
	local expeditions = Catalog.GetExpeditionsConfig()
	return if expeditions ~= nil then expeditions.name else DEFAULT_SESSION_NAME
end

local function runSummaryFor(userId: number): Types.RunSummary
	local summary = play.runSummaries[userId]
	if summary == nil then
		local level = play.level
		summary = emptySummary(if level ~= nil then level.id else "")
		play.runSummaries[userId] = summary
	end
	return summary
end

local function sessionSummaryFor(userId: number): Types.RunSummary
	local summary = play.sessionSummaries[userId]
	if summary == nil then
		summary = emptySummary(sessionName())
		play.sessionSummaries[userId] = summary
	end
	return summary
end

local function damageShareOf(userId: number): number
	local source = hooks.share
	if source == nil then
		return 0
	end
	return source(userId)
end

function ArenaService.IsAlive(member: Types.RunMember): boolean
	local humanoid = member.humanoid
	local character = member.character
	return humanoid ~= nil and character ~= nil and character.Parent ~= nil and humanoid.Health > 0
end

-- In the fight right now: alive and not waiting in the lobby camp for the next boundary.
function ArenaService.IsFighting(member: Types.RunMember): boolean
	return not member.waiting and ArenaService.IsAlive(member)
end

local function isDown(member: Types.RunMember): boolean
	local source = hooks.down
	return not member.bot and source ~= nil and source(member.userId)
end

-- L1 ruling 7: the host when the host is in the roster, else the first human in party order.
-- 0 with no human member.
function ArenaService.LeaderUserId(): number
	local host = party[session.hostUserId]
	if host ~= nil and not host.bot then
		return host.userId
	end
	for _, userId in partyOrder do
		local member = party[userId]
		if member ~= nil and not member.bot then
			return userId
		end
	end
	return 0
end

local function memberEntry(member: Types.RunMember, leader: number): Types.PartyMember
	local humanoid = member.humanoid
	local now = os.clock()
	return {
		userId = member.userId,
		name = member.name,
		hp = if humanoid ~= nil then humanoid.Health else 0,
		maxHp = if humanoid ~= nil then humanoid.MaxHealth else 0,
		-- L1 ruling 7: there is no Ready button; the field goes in L4.
		ready = false,
		alive = ArenaService.IsAlive(member),
		bot = member.bot,
		abilityReadyIn = {
			melee = math.max(0, member.abilityReadyAt.melee - now),
			ranged = math.max(0, member.abilityReadyAt.ranged - now),
		},
		stance = member.stance,
		-- The leader: the one whose Depart and Abandon the server takes.
		host = member.userId == leader,
		waiting = member.waiting,
		damageShare = damageShareOf(member.userId),
		down = isDown(member),
	}
end

-- One payload for the whole HUD, so the client never derives a phase. `summary` and `result` are
-- one member's own (the summary phase, and the card on the way home).
function ArenaService.BuildRunState(
	phase: Types.RunPhase,
	summary: Types.RunSummary?,
	result: Types.RunResult?
): Types.RunState
	local level = play.level
	local leader = ArenaService.LeaderUserId()
	local members: { Types.PartyMember } = {}
	for _, userId in partyOrder do
		local member = party[userId]
		if member ~= nil then
			table.insert(members, memberEntry(member, leader))
		end
	end
	return {
		kind = "run",
		phase = phase,
		overdrive = false,
		wave = runFields.wave,
		waves = runFields.waves,
		alive = runFields.alive,
		remaining = runFields.remaining,
		tempo = runFields.tempo,
		merged = runFields.merged,
		party = members,
		breatherEndsIn = runFields.breatherEndsIn,
		runEndsIn = runFields.runEndsIn,
		summary = summary,
		returnIn = if phase == "summary" then runFields.returnIn else nil,
		levelId = if level ~= nil then level.id else "",
		levelName = if level ~= nil then level.name else "",
		difficulty = if level ~= nil then level.difficulty else "",
		material = if level ~= nil then level.material else "",
		stage = runFields.stage,
		stages = runFields.stages,
		stageKind = runFields.stageKind,
		stageName = runFields.stageName,
		campsCleared = runFields.campsCleared,
		camps = runFields.camps,
		left = runFields.left,
		bossName = runFields.bossName,
		gateIn = runFields.gateIn,
		banked = runFields.banked,
		floor = runFields.floor,
		maxAlive = runFields.maxAlive,
		leaderUserId = leader,
		result = result,
	}
end

function ArenaService.RunSeconds(): number
	if play.startedAt == 0 then
		return 0
	end
	local untilClock = if play.endedAt > 0 then play.endedAt else os.clock()
	return math.max(untilClock - play.startedAt, 0)
end

function ArenaService.MarkRunStarted(): ()
	play.startedAt = os.clock()
	play.endedAt = 0
end

-- The run's card for one member: what this run banked for them.
function ArenaService.GetSummary(userId: number): Types.RunSummary
	local summary = runSummaryFor(userId)
	summary.seconds = math.floor(ArenaService.RunSeconds())
	summary.damageShare = damageShareOf(userId)
	return summary
end

-- The session's card for one member: everything credited since their admit. This is what the
-- trip home carries (the hub shows it under the map's name).
function ArenaService.GetSessionSummary(userId: number): Types.RunSummary
	local summary = sessionSummaryFor(userId)
	local since = play.admittedAt[userId]
	summary.seconds = if since ~= nil then math.floor(math.max(os.clock() - since, 0)) else 0
	return summary
end

-- Each member's own card, with the run's result. A member with no result (admitted during the
-- summary) is told the phase and gets no card.
local function sendSummaryTo(player: Player, userId: number): ()
	local result = play.results[userId]
	local summary = if result ~= nil then ArenaService.GetSummary(userId) else nil
	RemoteService.FireClient(
		player,
		"RunState",
		ArenaService.BuildRunState("summary", summary, result)
	)
end

function ArenaService.BroadcastSummary(): ()
	for _, userId in partyOrder do
		local member = party[userId]
		local player = if member ~= nil then member.player else nil
		if player ~= nil then
			sendSummaryTo(player, userId)
		end
	end
end

-- The summary is per player (their own share), so that phase cannot reuse a single payload.
function ArenaService.Broadcast(phase: Types.RunPhase): ()
	if phase == "summary" then
		ArenaService.BroadcastSummary()
		return
	end
	local runState = ArenaService.BuildRunState(phase, nil, nil)
	for _, userId in partyOrder do
		local member = party[userId]
		local player = if member ~= nil then member.player else nil
		if player ~= nil then
			RemoteService.FireClient(player, "RunState", runState)
		end
	end
end

-- WaveService pushes the run's half of RunState here every time it changes.
function ArenaService.SetRunFields(fields: RunFields): ()
	runFields = fields
end

-- True in the five live phases (travel, gate, wave, boss, breather): the gate WaveService's act
-- rule uses to refuse attacks sent in the lobby or on the summary card.
function ArenaService.InRun(): boolean
	return runFields.inRun
end

-- L1 ruling 3: what is played. nil = the lobby. WaveService sets it at each start and clears it
-- at each return.
function ArenaService.SetLevel(info: LevelInfo?): ()
	play.level = info
end

function ArenaService.GetLevel(): LevelInfo?
	return play.level
end

-- The run ended: each member's result for the summary card, and the card's clock stops.
function ArenaService.SetResults(results: { [number]: Types.RunResult }): ()
	play.results = results
	play.endedAt = os.clock()
end

-- A fresh run summary for every member, and no result: a run is starting.
function ArenaService.ResetSummaries(): ()
	local level = play.level
	local id = if level ~= nil then level.id else ""
	play.results = {}
	for _, userId in partyOrder do
		play.runSummaries[userId] = emptySummary(id)
	end
end

-- Hooks --------------------------------------------------------------------------------------

function ArenaService.SetSnapshotSender(sender: (player: Player) -> ()): ()
	hooks.sendSnapshot = sender
end

function ArenaService.SetResetHook(hook: () -> ()): ()
	hooks.reset = hook
end

-- WaveService hands its run-wide share lookup over at Init.
function ArenaService.SetShareSource(source: (userId: number) -> number): ()
	hooks.share = source
end

-- Run last whenever an admitted member's character is added, after it has been placed.
function ArenaService.SetCharacterHook(hook: (player: Player, character: Model) -> ()): ()
	hooks.character = hook
end

-- Called after every move this service makes of a human member's body.
function ArenaService.SetMovedHook(hook: (player: Player) -> ()): ()
	hooks.moved = hook
end

-- Fills PartyMember.down (always false for bots).
function ArenaService.SetDownSource(source: (userId: number) -> boolean): ()
	hooks.down = source
end

-- L1 ruling 18: where a member's body belongs right now (feet) and whether they wait for the
-- next boundary. Asked whenever a character is placed: at the admit and at every respawn.
function ArenaService.SetPlacer(placer: (member: Types.RunMember) -> (Vector3, boolean)): ()
	hooks.placer = placer
end

-- The lobby camp's SpawnLocation (LevelService's): Admit points RespawnLocation at it.
function ArenaService.SetLobby(spawn: SpawnLocation?): ()
	session.lobbySpawn = spawn
end

-- Used after a reward flush so the HUD wallet strip is current; Main owns the Snapshot shape.
function ArenaService.SendSnapshot(player: Player): ()
	local sender = hooks.sendSnapshot
	if sender ~= nil then
		sender(player)
	end
end

-- The registry -------------------------------------------------------------------------------

local function humanIds(): { number }
	local ids: { number } = {}
	for _, userId in partyOrder do
		local member = party[userId]
		if member ~= nil and not member.bot then
			table.insert(ids, userId)
		end
	end
	return ids
end

local function humanCount(): number
	return #humanIds()
end

local function isExpected(userId: number): boolean
	local ticket = session.ticket
	return ticket ~= nil and table.find(ticket.expected, userId) ~= nil
end

-- Seats held for expected party members still loading in. Only in the lobby: once a run is
-- under way a no-show has had lobbyWaitSeconds. `except` drops the arrival's own reservation.
local function reservedSeats(except: number?): number
	local ticket = session.ticket
	if ticket == nil or runFields.phase ~= "lobby" then
		return 0
	end
	local reserved = 0
	for _, userId in ticket.expected do
		if userId ~= except and not session.everAdmitted[userId] and party[userId] == nil then
			reserved += 1
		end
	end
	return reserved
end

-- Humans + bots + seats held for the departing party. Also what the registry advertises as
-- partySize, so the hub's `full` pre-filter agrees with the admission check here.
local function seatsTaken(except: number?): number
	return #partyOrder + reservedSeats(except)
end

-- RunRegistry.Publish and .Clear YIELD: they retry with a task.wait backoff, so with the
-- registry failing a single call parks for seven seconds. Every caller here is on a path that
-- must not yield — the run loop's Heartbeat tick and the teardown that runs just before
-- DataService.Release. So the registry is driven by ONE worker thread with a mailbox: pending
-- clears are kept per host and always run before a publish, and publishes coalesce into one
-- flag. A publish can therefore never swallow a clear, and a publish queued behind a clear
-- re-reads the live state (publishNow refuses a closed session) so it cannot resurrect the entry
-- the clear just removed.
local registry = {
	busy = false,
	publishWanted = false,
	clearsWanted = {} :: { [number]: boolean },
}

-- Yields. Only ever called from the worker thread below, and it re-reads the live state so a
-- coalesced publish always advertises the LATEST phase and party size.
local function publishNow(): ()
	local config = combatConfig
	if not session.open or session.hostUserId == 0 or config == nil then
		return
	end
	local ticket = session.ticket
	if ticket == nil or session.missionId == "" then
		-- No verified ticket (or no hub departure at all): the session is playable but nobody can
		-- teleport into it, so it is deliberately not advertised. Said once per session, and said
		-- as what it is: a session nobody departed for (Studio, a place opened on its own) is
		-- private by design and no fault; a proving build is always one, so it says nothing.
		if not session.warnedUnjoinable then
			session.warnedUnjoinable = true
			if session.missionId ~= "" then
				warn(
					`[ArenaService] the session of host {session.hostUserId} has no verified ticket;`
						.. ` it will not appear in any run list`
				)
			elseif not CombatMode.IsProving() then
				print(
					`[ArenaService] the session of host {session.hostUserId} was opened with no hub`
						.. ` departure: it is private and in no run list`
				)
			end
		end
		return
	end
	local mission = Catalog.GetMissionById(session.missionId)
	RunRegistry.Publish({
		hostUserId = session.hostUserId,
		hostName = session.hostName,
		-- The hub lists runs by the mission its departure named; here it chooses nothing.
		missionId = session.missionId,
		era = if mission ~= nil then mission.era else 0,
		-- L1 ruling 6: joinable only in the lobby. Any other phase is advertised past
		-- joinUntilWave, which closes the sort key and makes the hub's own Join answer `over`.
		wave = if runFields.phase == "lobby" then 0 else config.coop.joinUntilWave + 1,
		overdrive = session.overdrive,
		partySize = seatsTaken(nil),
		accessCode = ticket.accessCode,
		public = ticket.public,
		memberIds = humanIds(),
	})
end

local function pumpRegistry(): ()
	if registry.busy then
		return
	end
	local clearHost = next(registry.clearsWanted)
	if clearHost == nil and not registry.publishWanted then
		return
	end
	registry.busy = true
	if clearHost ~= nil then
		registry.clearsWanted[clearHost] = nil
	else
		registry.publishWanted = false
	end
	task.spawn(function()
		if clearHost ~= nil then
			RunRegistry.Clear(clearHost)
		else
			publishNow()
		end
		registry.busy = false
		pumpRegistry()
	end)
end

local function publishRun(): ()
	registry.publishWanted = true
	pumpRegistry()
end

local function clearRun(host: number): ()
	if host == 0 then
		-- Nothing was ever advertised (no host resolved), so there is nothing to withdraw.
		return
	end
	registry.clearsWanted[host] = true
	pumpRegistry()
end

-- Fire and forget: returns on the same frame it was called on, whatever the registry is doing.
-- WaveService calls it at every start and every return to the lobby (ruling 6).
function ArenaService.PublishRun(): ()
	publishRun()
end

-- The session is over (the last human left): a reserved server can be reused by a later
-- arrival, and leaving the old host and ticket in place would advertise a party that is gone.
local function resetSession(): ()
	-- Queued, not called: this runs from PlayerRemoving and from ReturnService immediately
	-- before DataService.Release, and the registry retry backoff must never delay a save.
	clearRun(session.hostUserId)
	-- Debug bots belong to the session: left behind they would hold seats in the next one.
	for _, userId in table.clone(partyOrder) do
		local member = party[userId]
		if member ~= nil and member.bot then
			local character = member.character
			if character ~= nil then
				character:Destroy()
			end
			party[userId] = nil
			table.remove(partyOrder, table.find(partyOrder, userId) :: number)
		end
	end
	memberCache = nil
	session.open = false
	session.missionId = ""
	session.overdrive = false
	session.hostUserId = 0
	session.hostName = ""
	session.ticket = nil
	session.firstArrivalAt = 0
	session.everAdmitted = {}
	session.warnedUnjoinable = false
	play.level = nil
	play.startedAt = 0
	play.endedAt = 0
	play.runSummaries = {}
	play.sessionSummaries = {}
	play.admittedAt = {}
	play.results = {}
	-- The run machine goes back to the lobby with the session (and removes the level), so a
	-- rejoin after a failed trip home opens a fresh lobby.
	local hook = hooks.reset
	if hook ~= nil then
		hook()
	end
end

-- Bodies -------------------------------------------------------------------------------------

-- L1 ruling 18: the ONE function that moves a member's body. `feet` is a point on the ground;
-- the body is put SPAWN_CLEARANCE above it with its speed taken away (a fall's speed would
-- carry it through the floor on the frame it lands), and whoever measures its motion is told
-- the jump is not the player's (the moved hook). False when the member has no body to move.
-- The client that owns the body is told too, as a fact and not a guess from its own speed: the
-- character carries where its feet were put (`Placed`) and a count that rises with every move
-- (`PlacedSeq`, so a move to the same place is still news). Attributes replicate by themselves.
function ArenaService.MoveMember(member: Types.RunMember, feet: Vector3): boolean
	local character = member.character
	if character == nil or character.Parent == nil then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.new(feet + Vector3.new(0, SPAWN_CLEARANCE, 0)))
	local seq = (play.placedSeq[member.userId] or 0) + 1
	play.placedSeq[member.userId] = seq
	-- The place first: whoever hears the count change reads the place it belongs to.
	character:SetAttribute(PLACED_ATTRIBUTE, feet)
	character:SetAttribute(PLACED_SEQ_ATTRIBUTE, seq)
	local hook = hooks.moved
	local player = member.player
	if hook ~= nil and player ~= nil then
		hook(player)
	end
	return true
end

-- Places a (re)spawned body where the placer says it belongs. Without a placer (nothing is
-- wired before WaveService.Init) the body stays where Roblox spawned it, in the lobby camp.
local function placeBody(member: Types.RunMember): ()
	local placer = hooks.placer
	if placer == nil then
		member.waiting = false
		return
	end
	local feet, waiting = placer(member)
	member.waiting = waiting
	ArenaService.MoveMember(member, feet)
end

-- A boundary (a wave clear, a camp clear, a wave's start): everyone waiting in the lobby camp
-- enters at `feet`, the run's safe point, with full health. WaveService broadcasts right after.
function ArenaService.ReleaseWaiting(feet: Vector3): ()
	for _, userId in partyOrder do
		local member = party[userId]
		if member == nil or not member.waiting then
			continue
		end
		member.waiting = false
		local humanoid = member.humanoid
		if humanoid == nil or humanoid.Health <= 0 then
			continue
		end
		humanoid.Health = humanoid.MaxHealth
		ArenaService.MoveMember(member, feet)
	end
end

-- Sends the roster to the party, or just this player's own card when the run is over.
local function announce(player: Player?): ()
	local phase: Types.RunPhase = runFields.phase
	if phase == "summary" and player ~= nil then
		local member = byPlayer[player]
		if member ~= nil then
			sendSummaryTo(player, member.userId)
		end
		return
	end
	ArenaService.Broadcast(phase)
end

local function watchCharacter(member: Types.RunMember, character: Model): ()
	member.character = character
	member.humanoid = character:FindFirstChildOfClass("Humanoid")
	applyMaxHp(member)
	local player = member.player
	local connections = if player ~= nil then characterConnections[player] else nil
	-- First, and whatever the body still lacks: a character whose Humanoid has not arrived yet
	-- must already be stopped by a camp's invisible wall, or it walks out of a closed camp.
	if player ~= nil and BarrierGroups.Ensure() then
		-- Every part of the body, and whatever it is given later (accessories, tools): only this
		-- group is stopped by a camp's invisible wall.
		for _, descendant in character:GetDescendants() do
			BarrierGroups.JoinPlayers(descendant)
		end
		local joined = character.DescendantAdded:Connect(BarrierGroups.JoinPlayers)
		if connections ~= nil then
			table.insert(connections, joined)
		end
	end
	local humanoid = member.humanoid
	if humanoid == nil or connections == nil then
		return
	end
	table.insert(
		connections,
		humanoid.Died:Connect(function()
			-- The line both cards show; whether the run is lost is WaveService's to rule.
			ArenaService.MarkDied(member.userId)
		end)
	)
end

-- The session ---------------------------------------------------------------------------------

-- Opens the session at the FIRST arrival; everyone after joins the session already here,
-- whatever their teleport data claimed. `missionId` and `overdrive` are the hub departure's
-- hint ("" and false with none) and choose nothing: they are the key the ticket is verified
-- against (ruling 4). Yields: the first call reads the hub's ticket from MemoryStore, and later
-- arrivals wait for that read so admission sees the real ticket.
function ArenaService.OpenSession(
	missionId: string,
	overdrive: boolean,
	hostUserId: number,
	arrivalName: string
): ()
	if session.open then
		if session.ticketPending then
			table.insert(session.waiters, coroutine.running())
			coroutine.yield()
		end
		return
	end
	session.open = true
	session.missionId = missionId
	session.overdrive = overdrive
	session.hostUserId = hostUserId
	-- Replaced by the host's own name when the host arrives; until then (or if the host never
	-- does) the session is listed under whoever opened it.
	session.hostName = arrivalName
	session.ticket = nil
	session.firstArrivalAt = 0
	session.everAdmitted = {}

	session.ticketPending = true
	-- Resolved once per session: the ticket is fixed for the life of the reserved server.
	local ticket = RunRegistry.ResolveTicket(hostUserId, missionId, overdrive)
	session.ticketPending = false
	-- A reset cannot land during the read (ResetIfEmpty waits on ticketPending), so the session
	-- this ticket belongs to is still the current one.
	session.ticket = ticket
	local waiters = session.waiters
	session.waiters = {}
	for _, thread in waiters do
		task.spawn(thread)
	end
end

-- One function for every arrival (and for the admitCheck lever), run before Admit. L1 ruling 5:
-- admission is seats and timing. `locked` only without Combat.json; `over` for an arrival
-- outside the ticket's expected list in any phase but the lobby (joining a live run is L5);
-- `full` at coop.maxParty; else `ok`. What may be played is decided at RequestStartLevel.
function ArenaService.CheckAdmission(player: Player, hint: AdmissionHint): Admission
	local config = combatConfig
	if config == nil then
		return "locked"
	end
	local probe = hint.probe
	local expected = not probe and isExpected(player.UserId)
	if runFields.phase ~= "lobby" and not expected then
		return "over"
	end
	local member = if probe then nil else byPlayer[player]
	if member == nil then
		local seats = if probe then seatsTaken(nil) else seatsTaken(player.UserId)
		if seats >= config.coop.maxParty then
			return "full"
		end
	end
	return "ok"
end

-- Adds an arrival that CheckAdmission let in. The placer says where they stand: the lobby camp
-- in the lobby and on the summary, the lobby camp as `waiting` during a fight, the run's safe
-- point otherwise (ruling 18).
function ArenaService.Admit(player: Player): ()
	if not session.open then
		return
	end
	if player.UserId == session.hostUserId then
		session.hostName = player.Name
	end
	session.everAdmitted[player.UserId] = true
	if session.firstArrivalAt == 0 then
		session.firstArrivalAt = os.clock()
	end

	local member = byPlayer[player]
	if member == nil then
		local state = DataService.GetState(player)
		local newMember: Types.RunMember = {
			userId = player.UserId,
			name = player.Name,
			player = player,
			bot = false,
			ready = false,
			character = nil,
			humanoid = nil,
			stance = "melee",
			abilityReadyAt = { melee = 0, ranged = 0 },
			godMode = false,
			respawnAt = 0,
			spawnIndex = 0,
			waiting = false,
			-- The hub refreshed incomeAtSave at departure, so this is the city's current rate.
			incomeRate = if state ~= nil then state.incomeAtSave else 0,
			drawStartedAt = 0,
			empoweredUntil = 0,
			empowerMult = NEUTRAL_EMPOWER,
		}
		member = newMember
		party[player.UserId] = newMember
		byPlayer[player] = newMember
		table.insert(partyOrder, player.UserId)
		memberCache = nil
		local level = play.level
		play.runSummaries[player.UserId] = emptySummary(if level ~= nil then level.id else "")
		play.sessionSummaries[player.UserId] = emptySummary(sessionName())
		play.admittedAt[player.UserId] = os.clock()
		characterConnections[player] = {}
		table.insert(
			characterConnections[player],
			player.CharacterAdded:Connect(function(character: Model)
				local live = byPlayer[player]
				if live == nil then
					return
				end
				watchCharacter(live, character)
				placeBody(live)
				local hook = hooks.character
				if hook ~= nil then
					hook(player, character)
				end
				announce(nil)
			end)
		)
	end

	local spawn = session.lobbySpawn
	if spawn ~= nil then
		player.RespawnLocation = spawn
	end
	local character = player.Character
	if character ~= nil then
		watchCharacter(member, character)
		placeBody(member)
	end
	publishRun()
	-- On the summary phase this sends only this player's own state: a rejoin after a failed trip
	-- home lands back on its card (when it has one) rather than on everybody's.
	announce(player)
end

-- The departing party is in: every userId of the ticket's expected list has been admitted at
-- least once, or coop.lobbyWaitSeconds have passed since the first arrival. (C2's start rule,
-- without the ready flags.) False while the ticket is still being read.
function ArenaService.PartyIn(): boolean
	local config = combatConfig
	if not session.open or config == nil or session.ticketPending then
		return false
	end
	local ticket = session.ticket
	if ticket ~= nil then
		for _, userId in ticket.expected do
			if not session.everAdmitted[userId] then
				return session.firstArrivalAt > 0
					and os.clock() - session.firstArrivalAt >= config.coop.lobbyWaitSeconds
			end
		end
	end
	return true
end

function ArenaService.IsAdmitted(player: Player): boolean
	return byPlayer[player] ~= nil
end

-- Admitted to THIS session at some point (a rejoin after a failed trip home may skip admission
-- only then; the set empties when the session ends).
function ArenaService.WasAdmitted(userId: number): boolean
	return session.everAdmitted[userId] == true
end

-- In the ticket's expected list: departed from the hub together, i.e. the hub party.
function ArenaService.IsExpected(userId: number): boolean
	return isExpected(userId)
end

function ArenaService.BotCount(): number
	return #partyOrder - humanCount()
end

function ArenaService.GetHostUserId(): number
	return session.hostUserId
end

-- The server-side records (character, cooldown stamps): the client payload list is what
-- BuildRunState projects.
--
-- Cached and returned BY REFERENCE: the run loop asks for it several times a frame. The roster
-- only changes on Admit/Remove/AddBot/RemoveBot, which is where the cache is dropped. Callers
-- iterate it; none of them may mutate it.
function ArenaService.GetMembers(): { Types.RunMember }
	local cached = memberCache
	if cached ~= nil then
		return cached
	end
	local members: { Types.RunMember } = {}
	for _, userId in partyOrder do
		local member = party[userId]
		if member ~= nil then
			table.insert(members, member)
		end
	end
	memberCache = members
	return members
end

function ArenaService.GetMember(userId: number): Types.RunMember?
	return party[userId]
end

function ArenaService.GetMemberFor(player: Player): Types.RunMember?
	return byPlayer[player]
end

-- Humans + bots, waiting or not: the count wave size and boss HP scale by.
function ArenaService.PartySize(): number
	return #partyOrder
end

-- Credits -------------------------------------------------------------------------------------

-- WaveService credits the split of a banked pool here, so both cards and the profile agree.
function ArenaService.CreditSummary(
	userId: number,
	cash: number,
	material: string,
	materials: number,
	valor: number,
	kills: number
): ()
	for _, summary in { runSummaryFor(userId), sessionSummaryFor(userId) } do
		summary.cash += cash
		summary.valor += valor
		summary.kills += kills
		if materials > 0 and material ~= "" then
			summary.materials[material] = (summary.materials[material] or 0) + materials
		end
	end
end

-- Mentor Valor is part of `valor` AND shown on its own line, so both move together.
function ArenaService.CreditMentor(userId: number, valor: number): ()
	for _, summary in { runSummaryFor(userId), sessionSummaryFor(userId) } do
		summary.valor += valor
		summary.mentorValor += valor
	end
end

function ArenaService.MarkWaveCleared(wave: number, count: number): ()
	for _, userId in partyOrder do
		local runSummary = runSummaryFor(userId)
		runSummary.wavesCleared += count
		runSummary.bestWave = math.max(runSummary.bestWave, wave)
		local sessionSummary = sessionSummaryFor(userId)
		sessionSummary.wavesCleared += count
		sessionSummary.bestWave = math.max(sessionSummary.bestWave, wave)
	end
end

function ArenaService.MarkDied(userId: number): ()
	if party[userId] == nil then
		return
	end
	runSummaryFor(userId).died = true
	sessionSummaryFor(userId).died = true
end

-- Debug bots (inert until L4) -----------------------------------------------------------------

-- A bot's feet: where the placer would put it, else the origin.
local function placeBot(member: Types.RunMember, model: Model): ()
	local placer = hooks.placer
	local feet = Vector3.zero
	if placer ~= nil then
		feet, member.waiting = placer(member)
	end
	model:PivotTo(CFrame.new(feet + Vector3.new(0, SPAWN_CLEARANCE, 0)))
end

-- Debug bots (Studio only): server rigs that hold a party slot. The crowd cannot target them,
-- so DebugService's lever refuses to add any (P5 ruling 24); these stay until L4 decides.
function ArenaService.AddBot(index: number): Types.RunMember?
	local userId = BOT_USER_ID_BASE - index
	if party[userId] ~= nil then
		return party[userId]
	end
	local config = combatConfig
	if config == nil then
		return nil
	end
	local model, humanoid, _root = EnemyService.BuildRig(colorOf(config.enemy.botColor))
	model.Name = `Bot_{index}`
	local member: Types.RunMember = {
		userId = userId,
		name = `Bot {index}`,
		player = nil,
		bot = true,
		ready = true,
		character = model,
		humanoid = humanoid,
		stance = "melee",
		abilityReadyAt = { melee = 0, ranged = 0 },
		godMode = false,
		respawnAt = 0,
		spawnIndex = index,
		waiting = false,
		incomeRate = config.debug.botIncomeRate,
		drawStartedAt = 0,
		empoweredUntil = 0,
		empowerMult = NEUTRAL_EMPOWER,
	}
	placeBot(member, model)
	model.Parent = workspace
	applyMaxHp(member)
	party[userId] = member
	table.insert(partyOrder, userId)
	memberCache = nil
	publishRun()
	ArenaService.Broadcast(runFields.phase)
	return member
end

function ArenaService.RemoveBot(index: number): ()
	local userId = BOT_USER_ID_BASE - index
	local member = party[userId]
	if member == nil then
		return
	end
	local character = member.character
	if character ~= nil then
		character:Destroy()
	end
	party[userId] = nil
	play.runSummaries[userId] = nil
	play.sessionSummaries[userId] = nil
	local position = table.find(partyOrder, userId)
	if position ~= nil then
		table.remove(partyOrder, position)
	end
	memberCache = nil
	publishRun()
	ArenaService.Broadcast(runFields.phase)
end

-- Bots have no Roblox respawn path of their own.
function ArenaService.RespawnBot(member: Types.RunMember): ()
	local config = combatConfig
	if not member.bot or config == nil then
		return
	end
	local old = member.character
	if old ~= nil then
		old:Destroy()
	end
	local model, humanoid, _root = EnemyService.BuildRig(colorOf(config.enemy.botColor))
	model.Name = `Bot_{member.spawnIndex}`
	placeBot(member, model)
	model.Parent = workspace
	member.character = model
	member.humanoid = humanoid
	member.respawnAt = 0
	applyMaxHp(member)
end

-- Leaving --------------------------------------------------------------------------------------

-- Leaving, teleporting home, or disconnecting all end here. The session (and its registry
-- entry) goes with the last human, so the hub never offers an empty one.
function ArenaService.Remove(player: Player): ()
	local member = byPlayer[player]
	if member == nil then
		return
	end
	byPlayer[player] = nil
	party[member.userId] = nil
	play.runSummaries[member.userId] = nil
	play.sessionSummaries[member.userId] = nil
	play.admittedAt[member.userId] = nil
	play.results[member.userId] = nil
	local index = table.find(partyOrder, member.userId)
	if index ~= nil then
		table.remove(partyOrder, index)
	end
	memberCache = nil
	local connections = characterConnections[player]
	if connections ~= nil then
		for _, connection in connections do
			connection:Disconnect()
		end
		characterConnections[player] = nil
	end

	if humanCount() == 0 then
		resetSession()
		return
	end
	publishRun()
	ArenaService.Broadcast(runFields.phase)
end

-- For an arrival that opened the session and was then refused (or left mid-load) without ever
-- being admitted: Remove never ran for them, so the session they opened would otherwise linger.
-- Never during the first ticket read, whose arrival is about to be admitted.
function ArenaService.ResetIfEmpty(): ()
	if not session.open or session.ticketPending or humanCount() > 0 then
		return
	end
	resetSession()
end

function ArenaService.Init(): ()
	combatConfig = Catalog.GetCombatConfig()
	if CombatMode.Get() == "range" then
		-- The range stands on this pad until RangeService builds its own arena over it, as at
		-- P5. A mission server builds nothing here: its lobby and its levels are LevelService's.
		buildFallbackArena(arenaFolder())
	end

	-- Roblox owns the respawn timer, so the contract's respawnSeconds is set here rather than
	-- re-implemented: CharacterAdded then places the body by the placer's rule.
	local config = combatConfig
	if config ~= nil then
		Players.RespawnTime = config.player.respawnSeconds
	end
end

function ArenaService.Start(): () end

return ArenaService
