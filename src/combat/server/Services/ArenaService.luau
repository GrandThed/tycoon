--!strict
-- The arena, the party roster and the authoritative RunState (docs/INTERFACES.md "C0 contracts"
-- → "Combat place server", "C1 contracts" → "Arena"). C1 replaces C0's bare pad with the
-- mission's own layout and gives every member the record the AI and the hit math read.
--
-- The weapons decide max HP, so the Humanoid is resized from the PROFILE on every spawn — never
-- from anything the client sent, and never from the teleport data.
--
-- The per-wave numbers in RunState (wave, alive, tempo, boss…) are pushed here by WaveService
-- through SetRunFields: WaveService sits above this service in the boot order, so it cannot be
-- required from here, and one payload builder for the whole HUD is worth the indirection.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local RunRegistry = require(script.Parent:WaitForChild("RunRegistry"))
local EnemyService = require(script.Parent:WaitForChild("EnemyService"))

-- The degrade arena: no Layouts/Arenas/<name> module means one pad and no walls, and the run
-- still plays (spec: missing content is a placeholder, never an error).
local FALLBACK_FLOOR_SIZE = 110
local FALLBACK_FLOOR_COLOR = Color3.fromRGB(106, 127, 63)
local ARENA_FOLDER_NAME = "Arena"
local LOBBY_PAD_SIZE = Vector3.new(6, 1, 6)
local SPAWN_SIZE = Vector3.new(6, 1, 6)
-- Studs above the floor a character is placed at, so nobody spawns inside the geometry.
local SPAWN_CLEARANCE = 4
local WALL_THICKNESS = 1
local BOT_COLOR = Color3.fromRGB(70, 120, 190)
local BOT_USER_ID_BASE = -1000
local DEFAULT_BOT_HP = 150

local partyOrder: { number } = {}
local party: { [number]: Types.RunMember } = {}
local byPlayer: { [Player]: Types.RunMember } = {}
local summaries: { [number]: Types.RunSummary } = {}
-- Rebuilt lazily by GetMembers and dropped by every roster change; see GetMembers for why.
local memberCache: { Types.RunMember }? = nil
local runMission: Types.MissionConfig? = nil
local runOverdrive = false
local hostUserId = 0
local hostName = ""
-- The verified reserved code this run is reachable at; nil = unjoinable (nothing published).
local runAccessCode: string? = nil
local warnedUnjoinable = false
local characterConnections: { [Player]: { RBXScriptConnection } } = {}
local arenaFolder: Folder? = nil
local builtArena = ""
local lobbySpawn: SpawnLocation? = nil
local lobbyPosition = Vector3.zero
local playerSpawns: { Vector3 } = {}
local spawnCursor = 0
local runStartedAt = 0
local combatConfig: Types.CombatConfig? = nil
local sendSnapshot: ((player: Player) -> ())? = nil

-- Everything WaveService owns in the RunState payload, defaulted to the lobby.
type RunFields = {
	wave: number,
	alive: number,
	remaining: number,
	tempo: number,
	merged: boolean,
	breatherEndsIn: number?,
	runEndsIn: number,
	boss: { name: string, hp: number, maxHp: number }?,
	inRun: boolean,
}
local runFields: RunFields = {
	wave = 0,
	alive = 0,
	remaining = 0,
	tempo = 1,
	merged = false,
	breatherEndsIn = nil,
	runEndsIn = 0,
	boss = nil,
	inRun = false,
}

local ArenaService = {}

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
	part.Parent = parent
	return part
end

-- The arena is code-built so nothing in the place file has to be kept in sync; Ben can still
-- drop scenery around it (combat.project.json keeps Workspace at $ignoreUnknownInstances).
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
	lobbySpawn = spawn
	lobbyPosition = position
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
	buildLobbyPad(folder, Vector3.new(0, 0.5, 0), Color3.fromRGB(96, 104, 120))
	playerSpawns = { lobbyPosition }
	EnemyService.SetSpawnPoints({})
end

local function buildFromLayout(folder: Folder, layout: Types.ArenaLayout): ()
	local sizeX = layout.size.x
	local sizeZ = layout.size.z
	local floor = newPart("Floor", Vector3.new(sizeX, 1, sizeZ), Vector3.new(0, -0.5, 0), folder)
	floor.Color = colorOf(layout.floor.color)
	floor.Material = materialOf(layout.floor.material)

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
		end
	end

	for index, obstacle in layout.obstacles do
		local part = newPart(
			`Obstacle{index}`,
			Vector3.new(obstacle.sx, obstacle.sy, obstacle.sz),
			Vector3.new(obstacle.x, obstacle.sy / 2, obstacle.z),
			folder
		)
		part.Color = colorOf(obstacle.color)
		part.Material = materialOf(obstacle.material)
	end

	buildLobbyPad(
		folder,
		Vector3.new(layout.lobbyPad.x, LOBBY_PAD_SIZE.Y / 2, layout.lobbyPad.z),
		colorOf(layout.floor.color):Lerp(Color3.new(1, 1, 1), 0.35)
	)

	playerSpawns = {}
	for _, point in layout.playerSpawns do
		table.insert(playerSpawns, Vector3.new(point.x, 0, point.z))
	end
	if #playerSpawns == 0 then
		playerSpawns = { lobbyPosition }
	end

	local enemyPoints: { Vector3 } = {}
	for _, point in layout.enemySpawns do
		table.insert(enemyPoints, Vector3.new(point.x, 0, point.z))
	end
	EnemyService.SetSpawnPoints(enemyPoints)
end

-- Idempotent per arena name: the first admit of a run builds the mission's arena over the
-- fallback pad, and a second run of the same mission in a reused reserved server reuses it.
local function ensureArena(arenaName: string): ()
	local folder = arenaFolder
	if folder == nil or builtArena == arenaName then
		return
	end
	folder:ClearAllChildren()
	lobbySpawn = nil
	local layout = loadLayout(arenaName)
	if layout == nil then
		warn(`[ArenaService] no Layouts/Arenas/{arenaName}; using the bare pad`)
		buildFallbackArena(folder)
	else
		buildFromLayout(folder, layout)
	end
	builtArena = arenaName
end

local function lobbyCFrame(): CFrame
	return CFrame.new(lobbyPosition + Vector3.new(0, SPAWN_CLEARANCE, 0))
end

local function nextPlayerSpawn(): CFrame
	if #playerSpawns == 0 then
		return lobbyCFrame()
	end
	spawnCursor += 1
	local point = playerSpawns[(spawnCursor - 1) % #playerSpawns + 1]
	return CFrame.new(point + Vector3.new(0, SPAWN_CLEARANCE, 0))
end

-- The profile is authoritative for max HP. Without Armory.json the Humanoid keeps its default
-- 100, which is the degrade path, not an error.
local function applyMaxHp(member: Types.RunMember): ()
	local humanoid = member.humanoid
	if humanoid == nil then
		return
	end
	if member.bot then
		local config = combatConfig
		local botHp = if config ~= nil then config.debug.botHp else DEFAULT_BOT_HP
		humanoid.MaxHealth = botHp
		humanoid.Health = botHp
		return
	end
	local player = member.player
	local state = if player ~= nil then DataService.GetState(player) else nil
	local armoryConfig = Catalog.GetArmoryConfig()
	if state == nil or armoryConfig == nil then
		return
	end
	local maxHp = Armory.MaxHp(armoryConfig, state.combat.gear, state.combat.ascension)
	humanoid.MaxHealth = maxHp
	humanoid.Health = maxHp
end

local function emptySummary(): Types.RunSummary
	local mission = runMission
	return {
		missionId = if mission ~= nil then mission.id else "",
		overdrive = runOverdrive,
		wavesCleared = 0,
		bestWave = 0,
		died = false,
		cash = 0,
		materials = {},
		valor = 0,
		kills = 0,
		seconds = 0,
	}
end

local function summaryFor(userId: number): Types.RunSummary
	local summary = summaries[userId]
	if summary == nil then
		summary = emptySummary()
		summaries[userId] = summary
	end
	return summary
end

function ArenaService.IsAlive(member: Types.RunMember): boolean
	local humanoid = member.humanoid
	local character = member.character
	return humanoid ~= nil and character ~= nil and character.Parent ~= nil and humanoid.Health > 0
end

local function memberEntry(member: Types.RunMember): Types.PartyMember
	local humanoid = member.humanoid
	local now = os.clock()
	return {
		userId = member.userId,
		name = member.name,
		hp = if humanoid ~= nil then humanoid.Health else 0,
		maxHp = if humanoid ~= nil then humanoid.MaxHealth else 0,
		ready = member.ready,
		alive = ArenaService.IsAlive(member),
		bot = member.bot,
		abilityReadyIn = {
			melee = math.max(0, member.abilityReadyAt.melee - now),
			ranged = math.max(0, member.abilityReadyAt.ranged - now),
		},
		stance = member.stance,
	}
end

-- One payload for the whole HUD, so the client never derives a phase.
function ArenaService.BuildRunState(
	phase: Types.RunPhase,
	summary: Types.RunSummary?
): Types.RunState
	local mission = runMission
	local members: { Types.PartyMember } = {}
	for _, userId in partyOrder do
		local member = party[userId]
		if member ~= nil then
			table.insert(members, memberEntry(member))
		end
	end
	return {
		kind = "run",
		phase = phase,
		missionId = if mission ~= nil then mission.id else "",
		overdrive = runOverdrive,
		wave = runFields.wave,
		waves = if mission ~= nil then mission.waves else 0,
		alive = runFields.alive,
		remaining = runFields.remaining,
		tempo = runFields.tempo,
		merged = runFields.merged,
		party = members,
		breatherEndsIn = runFields.breatherEndsIn,
		runEndsIn = runFields.runEndsIn,
		boss = runFields.boss,
		summary = summary,
	}
end

function ArenaService.Broadcast(phase: Types.RunPhase): ()
	local runState = ArenaService.BuildRunState(phase, nil)
	for _, userId in partyOrder do
		local member = party[userId]
		local player = if member ~= nil then member.player else nil
		if player ~= nil then
			RemoteService.FireClient(player, "RunState", runState)
		end
	end
end

-- The summary is per player (their own share), so this one cannot reuse a single payload.
function ArenaService.BroadcastSummary(): ()
	for _, userId in partyOrder do
		local member = party[userId]
		local player = if member ~= nil then member.player else nil
		if player ~= nil then
			RemoteService.FireClient(
				player,
				"RunState",
				ArenaService.BuildRunState("summary", summaryFor(userId))
			)
		end
	end
end

-- WaveService pushes the wave-facing half of RunState here every time it changes.
function ArenaService.SetRunFields(fields: {
	wave: number,
	alive: number,
	remaining: number,
	tempo: number,
	merged: boolean,
	breatherEndsIn: number?,
	runEndsIn: number,
	boss: { name: string, hp: number, maxHp: number }?,
	inRun: boolean,
}): ()
	runFields = fields
end

-- True from the first spawn of wave 1 until the run ends: the gate CombatService uses to refuse
-- swings fired in the lobby or after the summary card.
function ArenaService.InRun(): boolean
	return runFields.inRun
end

function ArenaService.SetSnapshotSender(sender: (player: Player) -> ()): ()
	sendSnapshot = sender
end

-- Used after a reward flush so the HUD wallet strip is current; Main owns the Snapshot shape.
function ArenaService.SendSnapshot(player: Player): ()
	local sender = sendSnapshot
	if sender ~= nil then
		sender(player)
	end
end

-- RunRegistry.Publish and .Clear YIELD: they retry with a task.wait backoff, so with the
-- registry failing a single call parks for seven seconds. Every caller here is on a path that
-- must not yield — the wave loop's Heartbeat tick (a yield there re-enters tick() with the
-- wave-clear branch still true and flushes the same pot again) and the teardown that runs just
-- before DataService.Release. So the registry is driven by ONE worker thread with a one-slot
-- mailbox: the newest intent wins, a publish requested mid-flight is coalesced, and a clear
-- that lands after a publish still ends up last because both go through the same queue.
local registryBusy = false
local registryWanted: string? = nil
local registryClearHost = 0

-- Yields. Only ever called from the worker thread below, and it re-reads the live run state so
-- a coalesced publish always advertises the LATEST wave and party size.
local function publishNow(): ()
	local mission = runMission
	if mission == nil or hostUserId == 0 then
		return
	end
	local accessCode = runAccessCode
	if accessCode == nil then
		-- No verified reserved code: the run is playable but nobody can teleport into it, so it
		-- is deliberately not advertised (warned once per run rather than on every admit).
		if not warnedUnjoinable then
			warnedUnjoinable = true
			warn(
				`[ArenaService] run {mission.id} for host {hostUserId} has no verified access`
					.. ` code; it will not appear in any run list`
			)
		end
		return
	end
	RunRegistry.Publish({
		hostUserId = hostUserId,
		hostName = hostName,
		missionId = mission.id,
		era = mission.era,
		wave = runFields.wave,
		overdrive = runOverdrive,
		partySize = #partyOrder,
		accessCode = accessCode,
	})
end

local function pumpRegistry(): ()
	if registryBusy then
		return
	end
	local wanted = registryWanted
	if wanted == nil then
		return
	end
	registryWanted = nil
	registryBusy = true
	local host = registryClearHost
	task.spawn(function()
		if wanted == "clear" then
			RunRegistry.Clear(host)
		else
			publishNow()
		end
		registryBusy = false
		pumpRegistry()
	end)
end

local function publishRun(): ()
	registryWanted = "publish"
	pumpRegistry()
end

local function clearRun(host: number): ()
	if host == 0 then
		-- Nothing was ever advertised (no host resolved), so there is nothing to withdraw.
		return
	end
	registryClearHost = host
	registryWanted = "clear"
	pumpRegistry()
end

-- Fire and forget: returns on the same frame it was called on, whatever the registry is doing.
function ArenaService.PublishRun(): ()
	publishRun()
end

-- WaveService ends the run inside its Heartbeat tick, so it clears the registry through here
-- rather than calling RunRegistry directly.
function ArenaService.ClearRegistry(host: number): ()
	clearRun(host)
end

local function watchCharacter(member: Types.RunMember, character: Model): ()
	member.character = character
	member.humanoid = character:FindFirstChildOfClass("Humanoid")
	applyMaxHp(member)
	local humanoid = member.humanoid
	if humanoid == nil then
		return
	end
	local player = member.player
	if player == nil then
		return
	end
	local connections = characterConnections[player]
	if connections == nil then
		return
	end
	table.insert(
		connections,
		humanoid.Died:Connect(function()
			-- The summary line the card shows; the run-ending check is WaveService's poll.
			summaryFor(member.userId).died = true
		end)
	)
end

-- The mission and the Overdrive flag are decided by the FIRST admitted player: everyone else
-- joins the run that is already here, whatever their teleport data claimed.
function ArenaService.Admit(
	player: Player,
	mission: Types.MissionConfig,
	overdrive: boolean,
	runHostUserId: number?
): ()
	if runMission == nil then
		runMission = mission
		runOverdrive = overdrive
		hostUserId = runHostUserId or player.UserId
		hostName = player.Name
		-- Resolved once per run: the code is fixed for the life of the reserved server.
		runAccessCode = RunRegistry.ResolveAccessCode(hostUserId, mission.id, overdrive)
		EnemyService.SetMission(mission)
		runStartedAt = os.clock()
	end
	ensureArena(mission.arena)

	local member = byPlayer[player]
	if member == nil then
		member = {
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
		}
		party[player.UserId] = member
		byPlayer[player] = member
		table.insert(partyOrder, player.UserId)
		memberCache = nil
		summaries[player.UserId] = emptySummary()
		characterConnections[player] = {}
		table.insert(
			characterConnections[player],
			player.CharacterAdded:Connect(function(character: Model)
				local live = byPlayer[player]
				if live == nil then
					return
				end
				watchCharacter(live, character)
				-- Mid-run respawns land next to the fight, not back on the lobby pad.
				if runFields.inRun then
					character:PivotTo(nextPlayerSpawn())
				else
					character:PivotTo(lobbyCFrame())
				end
				ArenaService.Broadcast(if runFields.inRun then "wave" else "lobby")
			end)
		)
	end

	local spawn = lobbySpawn
	if spawn ~= nil then
		player.RespawnLocation = spawn
	end
	local character = player.Character
	if character ~= nil then
		watchCharacter(member, character)
		-- A joiner arriving into a run in progress lands at a player spawn, not on the lobby pad
		-- in the middle of the fight.
		character:PivotTo(if runFields.inRun then nextPlayerSpawn() else lobbyCFrame())
	end
	publishRun()
	ArenaService.Broadcast(if runFields.inRun then "wave" else "lobby")
end

-- RequestReady toggles: the button is the same button in both directions, and Main starts wave 1
-- once every non-bot member is ready. Ignored once the run is under way — RequestReady shares
-- the 10/s gameplay bucket, so without this guard a modified client could flap the whole party's
-- phase back to "lobby" ten times a second and freeze everyone's HUD and input.
function ArenaService.SetReady(player: Player): ()
	local member = byPlayer[player]
	if member == nil or runFields.inRun then
		return
	end
	member.ready = not member.ready
	ArenaService.Broadcast("lobby")
end

function ArenaService.AllReady(): boolean
	local humans = 0
	for _, userId in partyOrder do
		local member = party[userId]
		if member ~= nil and not member.bot then
			humans += 1
			if not member.ready then
				return false
			end
		end
	end
	return humans > 0
end

function ArenaService.IsAdmitted(player: Player): boolean
	return byPlayer[player] ~= nil
end

function ArenaService.GetMission(): Types.MissionConfig?
	return runMission
end

function ArenaService.IsOverdrive(): boolean
	return runOverdrive
end

function ArenaService.GetHostUserId(): number
	return hostUserId
end

-- The server-side records (character, cooldown stamps): the client payload list is what
-- BuildRunState projects.
--
-- Cached and returned BY REFERENCE: every enemy asks for it twice per AI tick (retarget plus
-- the current-target lookup), so at 24 enemies and 10 Hz a fresh array here was 480 table
-- allocations a second. The roster only changes on Admit/Remove/AddBot/RemoveBot, which is
-- where the cache is dropped. Callers iterate it; none of them may mutate it.
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

function ArenaService.PartySize(): number
	return #partyOrder
end

function ArenaService.RunSeconds(): number
	if runStartedAt == 0 then
		return 0
	end
	return os.clock() - runStartedAt
end

function ArenaService.MarkRunStarted(): ()
	runStartedAt = os.clock()
end

-- Debug bots (Studio only, DebugService.SetBots): server rigs that hold a party slot so party
-- scaling, aggro and the contribution split can be seen from a single client.
function ArenaService.AddBot(index: number): Types.RunMember?
	local userId = BOT_USER_ID_BASE - index
	if party[userId] ~= nil then
		return party[userId]
	end
	local model, humanoid, _root = EnemyService.BuildRig(BOT_COLOR)
	model.Name = `Bot_{index}`
	model:PivotTo(nextPlayerSpawn())
	model.Parent = workspace
	local member: Types.RunMember = {
		userId = userId,
		name = `Bot {index}`,
		player = nil,
		bot = true,
		-- Always ready: a bot must never be the reason a lobby will not start.
		ready = true,
		character = model,
		humanoid = humanoid,
		stance = "melee",
		abilityReadyAt = { melee = 0, ranged = 0 },
		godMode = false,
		respawnAt = 0,
		spawnIndex = index,
	}
	applyMaxHp(member)
	party[userId] = member
	table.insert(partyOrder, userId)
	memberCache = nil
	summaries[userId] = emptySummary()
	ArenaService.Broadcast(if runFields.inRun then "wave" else "lobby")
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
	summaries[userId] = nil
	local position = table.find(partyOrder, userId)
	if position ~= nil then
		table.remove(partyOrder, position)
	end
	memberCache = nil
	ArenaService.Broadcast(if runFields.inRun then "wave" else "lobby")
end

-- Bots have no Roblox respawn path of their own, so the wave loop asks for one here.
function ArenaService.RespawnBot(member: Types.RunMember): ()
	if not member.bot then
		return
	end
	local old = member.character
	if old ~= nil then
		old:Destroy()
	end
	local model, humanoid, _root = EnemyService.BuildRig(BOT_COLOR)
	model.Name = `Bot_{member.spawnIndex}`
	model:PivotTo(nextPlayerSpawn())
	model.Parent = workspace
	member.character = model
	member.humanoid = humanoid
	member.respawnAt = 0
	applyMaxHp(member)
end

function ArenaService.GetSummary(userId: number): Types.RunSummary
	local summary = summaryFor(userId)
	summary.seconds = math.floor(ArenaService.RunSeconds())
	return summary
end

-- WaveService credits the split of a cleared wave here so the card and the profile agree.
function ArenaService.CreditSummary(
	userId: number,
	cash: number,
	material: string,
	materials: number,
	valor: number,
	kills: number
): ()
	local summary = summaryFor(userId)
	summary.cash += cash
	summary.valor += valor
	summary.kills += kills
	if materials > 0 and material ~= "" then
		summary.materials[material] = (summary.materials[material] or 0) + materials
	end
end

function ArenaService.MarkWaveCleared(wave: number, count: number): ()
	for _, userId in partyOrder do
		local summary = summaryFor(userId)
		summary.wavesCleared += count
		summary.bestWave = math.max(summary.bestWave, wave)
	end
end

function ArenaService.MarkDied(userId: number): ()
	summaryFor(userId).died = true
end

-- Leaving, teleporting home, or disconnecting all end here. The registry entry goes away with
-- the last member so the hub never offers an empty run.
function ArenaService.Remove(player: Player): ()
	local member = byPlayer[player]
	if member == nil then
		return
	end
	byPlayer[player] = nil
	party[member.userId] = nil
	summaries[member.userId] = nil
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

	local humans = 0
	for _, userId in partyOrder do
		local other = party[userId]
		if other ~= nil and not other.bot then
			humans += 1
		end
	end
	if humans == 0 then
		-- Queued, not called: this runs from PlayerRemoving and from ReturnService immediately
		-- before DataService.Release, and the registry retry backoff must never delay a save.
		clearRun(hostUserId)
		-- The run is over: a reserved server can be reused by a later arrival (or by a rejoin
		-- after a failed trip home), and leaving the old mission, host and access code in place
		-- would advertise a run that no longer exists.
		runMission = nil
		runOverdrive = false
		hostUserId = 0
		hostName = ""
		runAccessCode = nil
		warnedUnjoinable = false
		EnemyService.SetMission(nil)
		return
	end
	publishRun()
	ArenaService.Broadcast(if runFields.inRun then "wave" else "lobby")
end

function ArenaService.Init(): ()
	combatConfig = Catalog.GetCombatConfig()
	local folder = Instance.new("Folder")
	folder.Name = ARENA_FOLDER_NAME
	folder.Parent = workspace
	arenaFolder = folder
	buildFallbackArena(folder)

	-- Roblox owns the respawn timer, so the contract's respawnSeconds is set here rather than
	-- re-implemented: CharacterAdded then places the player at an arena spawn.
	local config = combatConfig
	if config ~= nil then
		Players.RespawnTime = config.player.respawnSeconds
	end
end

function ArenaService.Start(): () end

return ArenaService
