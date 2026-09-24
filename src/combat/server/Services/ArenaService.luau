--!strict
-- The arena, the party roster and the authoritative RunState (docs/INTERFACES.md "C0 contracts"
-- → "Combat place server", "C1 contracts" → "Arena", "C2 contracts" → "Combat place (A)"). C1
-- replaces C0's bare pad with the mission's own layout and gives every member the record the AI
-- and the hit math read; C2 adds the run ticket, admission, and the wave-boundary entry rule.
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
local Combat = require(sharedFolder:WaitForChild("Combat"))

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
local BOT_USER_ID_BASE = -1000
local DEFAULT_BOT_HP = 150
local NEUTRAL_EMPOWER = 1

-- The verdict every arrival gets before Admit. "ok" admits; anything else is a refusal the hub
-- shows on the way back (ReturnData.refused).
export type Admission = "ok" | "full" | "over" | "locked"
-- probe = the admitCheck lever: judge the caller as a STRANGER arriving right now (their own seat
-- still counted, their membership and any expected-list entry ignored), so one Studio client can
-- see the verdict a real joiner would get without anyone being sent home.
export type AdmissionHint = { probe: boolean }

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
-- The verified hub ticket; nil = a private run (no code, no expected list, nothing published).
local runTicket: Types.RunTicket? = nil
-- True while the first arrival's ResolveTicket is in flight. Later arrivals park on
-- ticketWaiters until it lands, because admission reads the ticket (host gate, expected list).
local ticketPending = false
local ticketWaiters: { thread } = {}
-- os.clock() of the first admit of this run, for coop.lobbyWaitSeconds.
local firstArrivalAt = 0
-- Every userId admitted at least once this run: an expected member who arrived and then left
-- must not hold the lobby for the whole wait.
local everAdmitted: { [number]: boolean } = {}
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
-- CombatService's run-wide raw damage share. Handed in (CombatService sits above this service).
local shareSource: ((userId: number) -> number)? = nil
-- WaveService.Reset, handed in for the same reason: called whenever the run resets.
local resetHook: (() -> ())? = nil

-- Everything WaveService owns in the RunState payload, defaulted to the lobby.
export type RunFields = {
	phase: Types.RunPhase,
	wave: number,
	alive: number,
	remaining: number,
	tempo: number,
	merged: boolean,
	breatherEndsIn: number?,
	runEndsIn: number,
	boss: { name: string, hp: number, maxHp: number }?,
	inRun: boolean,
	returnIn: number?,
}
local runFields: RunFields = {
	phase = "lobby",
	wave = 0,
	alive = 0,
	remaining = 0,
	tempo = 1,
	merged = false,
	breatherEndsIn = nil,
	runEndsIn = 0,
	boss = nil,
	inRun = false,
	returnIn = nil,
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
	EnemyService.SetObstacles({})
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
	EnemyService.SetObstacles(cover)

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

-- A wave or boss fight is under way: anyone entering now waits on the pad for the boundary.
local function midWave(): boolean
	return runFields.phase == "wave" or runFields.phase == "boss"
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
		mentorValor = 0,
		damageShare = 0,
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

local function damageShareOf(userId: number): number
	local source = shareSource
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

-- In the fight right now: alive and not parked on the pad for the next wave boundary.
function ArenaService.IsFighting(member: Types.RunMember): boolean
	return not member.waiting and ArenaService.IsAlive(member)
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
		host = member.userId == hostUserId,
		waiting = member.waiting,
		damageShare = damageShareOf(member.userId),
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
		returnIn = if phase == "summary" then runFields.returnIn else nil,
	}
end

function ArenaService.GetSummary(userId: number): Types.RunSummary
	local summary = summaryFor(userId)
	summary.seconds = math.floor(ArenaService.RunSeconds())
	summary.damageShare = damageShareOf(userId)
	return summary
end

local function sendSummaryTo(player: Player, userId: number): ()
	RemoteService.FireClient(
		player,
		"RunState",
		ArenaService.BuildRunState("summary", ArenaService.GetSummary(userId))
	)
end

-- The summary is per player (their own share), so that phase cannot reuse a single payload.
function ArenaService.Broadcast(phase: Types.RunPhase): ()
	if phase == "summary" then
		ArenaService.BroadcastSummary()
		return
	end
	local runState = ArenaService.BuildRunState(phase, nil)
	for _, userId in partyOrder do
		local member = party[userId]
		local player = if member ~= nil then member.player else nil
		if player ~= nil then
			RemoteService.FireClient(player, "RunState", runState)
		end
	end
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

-- WaveService pushes the wave-facing half of RunState here every time it changes.
function ArenaService.SetRunFields(fields: RunFields): ()
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

function ArenaService.SetResetHook(hook: () -> ()): ()
	resetHook = hook
end

-- CombatService hands its run-wide share lookup over at Init.
function ArenaService.SetShareSource(source: (userId: number) -> number): ()
	shareSource = source
end

-- Used after a reward flush so the HUD wallet strip is current; Main owns the Snapshot shape.
function ArenaService.SendSnapshot(player: Player): ()
	local sender = sendSnapshot
	if sender ~= nil then
		sender(player)
	end
end

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

local function isExpected(userId: number): boolean
	local ticket = runTicket
	return ticket ~= nil and table.find(ticket.expected, userId) ~= nil
end

-- Seats held for expected party members still loading in. Only in the lobby: once the run is
-- under way a no-show has had lobbyWaitSeconds, and an expected latecomer is admitted on the
-- same seat check as anyone else. `except` drops the arrival's own reservation.
local function reservedSeats(except: number?): number
	local ticket = runTicket
	if ticket == nil or runFields.phase ~= "lobby" then
		return 0
	end
	local reserved = 0
	for _, userId in ticket.expected do
		if userId ~= except and not everAdmitted[userId] and party[userId] == nil then
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
-- must not yield — the wave loop's Heartbeat tick (a yield there re-enters tick() with the
-- wave-clear branch still true and flushes the same pot again) and the teardown that runs just
-- before DataService.Release. So the registry is driven by ONE worker thread with a mailbox:
-- pending clears are kept per host and always run before a publish, and publishes coalesce
-- into one flag. A publish can therefore never swallow a clear, and a publish queued behind a
-- clear re-reads the live state (publishNow refuses an ended or reset run) so it cannot
-- resurrect the entry the clear just removed.
local registryBusy = false
local publishWanted = false
local clearsWanted: { [number]: boolean } = {}

-- Yields. Only ever called from the worker thread below, and it re-reads the live run state so
-- a coalesced publish always advertises the LATEST wave and party size.
local function publishNow(): ()
	local mission = runMission
	local phase = runFields.phase
	if mission == nil or hostUserId == 0 or phase == "summary" or phase == "ended" then
		-- A finished run stops being joinable the moment it ends (WaveService clears it then).
		return
	end
	local ticket = runTicket
	if ticket == nil then
		-- No verified ticket: the run is playable but nobody can teleport into it, so it is
		-- deliberately not advertised (warned once per run rather than on every admit).
		if not warnedUnjoinable then
			warnedUnjoinable = true
			warn(
				`[ArenaService] run {mission.id} for host {hostUserId} has no verified ticket;`
					.. ` it will not appear in any run list`
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
		partySize = seatsTaken(nil),
		accessCode = ticket.accessCode,
		public = ticket.public,
		memberIds = humanIds(),
	})
end

local function pumpRegistry(): ()
	if registryBusy then
		return
	end
	local clearHost = next(clearsWanted)
	if clearHost == nil and not publishWanted then
		return
	end
	registryBusy = true
	if clearHost ~= nil then
		clearsWanted[clearHost] = nil
	else
		publishWanted = false
	end
	task.spawn(function()
		if clearHost ~= nil then
			RunRegistry.Clear(clearHost)
		else
			publishNow()
		end
		registryBusy = false
		pumpRegistry()
	end)
end

local function publishRun(): ()
	publishWanted = true
	pumpRegistry()
end

local function clearRun(host: number): ()
	if host == 0 then
		-- Nothing was ever advertised (no host resolved), so there is nothing to withdraw.
		return
	end
	clearsWanted[host] = true
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

-- The run is over: a reserved server can be reused by a later arrival (or by a rejoin after a
-- failed trip home), and leaving the old mission, host and ticket in place would advertise a run
-- that no longer exists.
local function resetRun(): ()
	-- Queued, not called: this runs from PlayerRemoving and from ReturnService immediately
	-- before DataService.Release, and the registry retry backoff must never delay a save.
	clearRun(hostUserId)
	-- Debug bots belong to the run: left behind they would hold seats in whatever run this
	-- reserved server hosts next. DebugService reads the live count, so it re-adds them only
	-- if its lever still asks for them once a new run opens.
	for _, userId in table.clone(partyOrder) do
		local member = party[userId]
		if member ~= nil and member.bot then
			local character = member.character
			if character ~= nil then
				character:Destroy()
			end
			party[userId] = nil
			summaries[userId] = nil
			table.remove(partyOrder, table.find(partyOrder, userId) :: number)
		end
	end
	memberCache = nil
	runMission = nil
	runOverdrive = false
	hostUserId = 0
	hostName = ""
	runTicket = nil
	firstArrivalAt = 0
	everAdmitted = {}
	warnedUnjoinable = false
	EnemyService.SetMission(nil)
	-- The wave machine goes back to the lobby with the run, so a rejoin after a failed group
	-- return opens a fresh lobby instead of landing on a stale summary card.
	local hook = resetHook
	if hook ~= nil then
		hook()
	end
end

local function humanCount(): number
	local humans = 0
	for _, userId in partyOrder do
		local member = party[userId]
		if member ~= nil and not member.bot then
			humans += 1
		end
	end
	return humans
end

-- Places a (re)spawned body by the wave-boundary rule: mid-wave it waits on the pad, in a
-- breather it goes straight to a player spawn, in the lobby or on the summary it stays home.
local function placeBody(member: Types.RunMember, character: Model): ()
	if midWave() then
		member.waiting = true
		character:PivotTo(lobbyCFrame())
	elseif runFields.inRun then
		member.waiting = false
		character:PivotTo(nextPlayerSpawn())
	else
		member.waiting = false
		character:PivotTo(lobbyCFrame())
	end
end

-- Sends the roster to the party, or just this player's summary card when the run is over.
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

-- Sets up the run the FIRST arrival asked for; everyone after joins the run already here,
-- whatever their teleport data claimed. Yields: the first call reads the hub's ticket from
-- MemoryStore, and later arrivals wait for that read so admission sees the real ticket.
function ArenaService.EnsureRun(
	mission: Types.MissionConfig,
	overdrive: boolean,
	runHostUserId: number,
	arrivalName: string
): ()
	if runMission ~= nil then
		if ticketPending then
			table.insert(ticketWaiters, coroutine.running())
			coroutine.yield()
		end
		return
	end
	runMission = mission
	runOverdrive = overdrive
	hostUserId = runHostUserId
	-- Replaced by the host's own name when the host arrives; until then (or if the host never
	-- does) the run is listed under whoever opened it.
	hostName = arrivalName
	runTicket = nil
	firstArrivalAt = 0
	everAdmitted = {}
	EnemyService.SetMission(mission)
	runStartedAt = os.clock()
	ensureArena(mission.arena)

	ticketPending = true
	-- Resolved once per run: the ticket is fixed for the life of the reserved server.
	local ticket = RunRegistry.ResolveTicket(runHostUserId, mission.id, overdrive)
	ticketPending = false
	-- A reset cannot land during the read (ResetIfEmpty waits on ticketPending), so the run
	-- this ticket belongs to is still the current one.
	runTicket = ticket
	local waiters = ticketWaiters
	ticketWaiters = {}
	for _, thread in waiters do
		task.spawn(thread)
	end
end

-- One function for every arrival (and for the admitCheck lever), run before Admit. Order
-- matters: `over` beats `full` beats `locked`, so the hub shows the most permanent reason.
function ArenaService.CheckAdmission(player: Player, hint: AdmissionHint): Admission
	local mission = runMission
	local config = combatConfig
	if mission == nil or config == nil then
		return "locked"
	end
	local coop = config.coop
	local probe = hint.probe
	local phase = runFields.phase
	if phase == "summary" or phase == "ended" then
		return "over"
	end
	local expected = not probe and isExpected(player.UserId)
	if not expected and runFields.wave > coop.joinUntilWave then
		return "over"
	end
	local member = if probe then nil else byPlayer[player]
	if member == nil then
		local seats = if probe then seatsTaken(nil) else seatsTaken(player.UserId)
		if seats >= coop.maxParty then
			return "full"
		end
	end
	-- Host-gated (Ben's ruling): with a ticket the hub already checked the leader's unlock at
	-- departure and joiners fight on the host's entitlement, so only the host is re-checked.
	-- Without one nothing vouches for anybody and every arrival is checked as at C1.
	local mustCheck = runTicket == nil or (not probe and player.UserId == hostUserId)
	if mustCheck then
		local state = DataService.GetState(player)
		if state == nil or not Combat.MissionUnlocked(state, mission, runOverdrive, config) then
			return "locked"
		end
	end
	return "ok"
end

-- Adds an arrival that CheckAdmission let in. Mid-wave it waits on the lobby pad for the next
-- boundary; in the lobby or a breather it enters at once.
function ArenaService.Admit(player: Player): ()
	local mission = runMission
	if mission == nil then
		return
	end
	ensureArena(mission.arena)
	if player.UserId == hostUserId then
		hostName = player.Name
	end
	everAdmitted[player.UserId] = true
	if firstArrivalAt == 0 then
		firstArrivalAt = os.clock()
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
			waiting = midWave(),
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
				-- A co-op death respawns here: mid-wave onto the pad as waiting, in a breather
				-- straight back into the fight.
				placeBody(live, character)
				announce(nil)
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
		placeBody(member, character)
	end
	publishRun()
	-- On the summary phase this sends only this player's card: a rejoin after a failed trip home
	-- lands back on it rather than on an empty lobby.
	announce(player)
end

-- RequestReady toggles: the button is the same button in both directions. Ignored once the run
-- is under way — RequestReady shares the 10/s gameplay bucket, so without this guard a modified
-- client could flap the whole party's phase back to "lobby" ten times a second.
function ArenaService.SetReady(player: Player): ()
	local member = byPlayer[player]
	if member == nil or runFields.inRun or runFields.phase ~= "lobby" then
		return
	end
	member.ready = not member.ready
	ArenaService.Broadcast("lobby")
end

-- The lobby start rule: every present human ready, AND either the whole departing party is in or
-- coop.lobbyWaitSeconds have passed since the first arrival. Bots are always ready.
function ArenaService.CanStart(): boolean
	local config = combatConfig
	if runMission == nil or config == nil or ticketPending then
		return false
	end
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
	if humans == 0 then
		return false
	end
	local ticket = runTicket
	if ticket ~= nil then
		for _, userId in ticket.expected do
			if not everAdmitted[userId] then
				return firstArrivalAt > 0
					and os.clock() - firstArrivalAt >= config.coop.lobbyWaitSeconds
			end
		end
	end
	return true
end

-- The wave boundary (a breather begins, or a wave begins): everyone parked on the pad enters the
-- fight at a player spawn with full HP. WaveService broadcasts right after.
function ArenaService.ReleaseWaiting(): ()
	for _, userId in partyOrder do
		local member = party[userId]
		if member == nil or not member.waiting then
			continue
		end
		member.waiting = false
		local character = member.character
		local humanoid = member.humanoid
		if character == nil or humanoid == nil or humanoid.Health <= 0 then
			continue
		end
		humanoid.Health = humanoid.MaxHealth
		character:PivotTo(nextPlayerSpawn())
	end
end

function ArenaService.IsAdmitted(player: Player): boolean
	return byPlayer[player] ~= nil
end

-- Admitted to THIS run at some point (a rejoin after a failed trip home may skip admission only
-- then; the set empties when the run resets).
function ArenaService.WasAdmitted(userId: number): boolean
	return everAdmitted[userId] == true
end

-- In the ticket's expected list: departed from the hub together, i.e. the hub party.
function ArenaService.IsExpected(userId: number): boolean
	return isExpected(userId)
end

function ArenaService.BotCount(): number
	return #partyOrder - humanCount()
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

function ArenaService.GetPhase(): Types.RunPhase
	return runFields.phase
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

-- Humans + bots, waiting or not: the count wave size and boss HP scale by.
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

local function placeBot(member: Types.RunMember, model: Model): ()
	if midWave() then
		member.waiting = true
		model:PivotTo(lobbyCFrame())
	else
		member.waiting = false
		model:PivotTo(nextPlayerSpawn())
	end
end

-- Debug bots (Studio only, DebugService.SetBots): server rigs that hold a party slot so party
-- scaling, aggro and the contribution split can be seen from a single client. A bot added
-- mid-wave waits for the boundary exactly like a joiner.
function ArenaService.AddBot(index: number): Types.RunMember?
	local userId = BOT_USER_ID_BASE - index
	if party[userId] ~= nil then
		return party[userId]
	end
	local config = combatConfig
	if config == nil then
		-- Bots are a DebugService lever, which needs Combat.json anyway.
		return nil
	end
	local model, humanoid, _root = EnemyService.BuildRig(colorOf(config.enemy.botColor))
	model.Name = `Bot_{index}`
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
	summaries[userId] = emptySummary()
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
	summaries[userId] = nil
	local position = table.find(partyOrder, userId)
	if position ~= nil then
		table.remove(partyOrder, position)
	end
	memberCache = nil
	publishRun()
	ArenaService.Broadcast(runFields.phase)
end

-- Bots have no Roblox respawn path of their own, so the wave loop asks for one here.
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

-- Mentor Valor is part of `valor` AND shown on its own line, so both move together.
function ArenaService.CreditMentor(userId: number, valor: number): ()
	local summary = summaryFor(userId)
	summary.valor += valor
	summary.mentorValor += valor
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

	if humanCount() == 0 then
		resetRun()
		return
	end
	publishRun()
	ArenaService.Broadcast(runFields.phase)
end

-- For an arrival that opened the run and was then refused (or left mid-load) without ever being
-- admitted: Remove never ran for them, so the run they opened would otherwise linger. Never
-- during the first ticket read, whose arrival is about to be admitted.
function ArenaService.ResetIfEmpty(): ()
	if runMission == nil or ticketPending or humanCount() > 0 then
		return
	end
	resetRun()
end

function ArenaService.Init(): ()
	combatConfig = Catalog.GetCombatConfig()
	local folder = Instance.new("Folder")
	folder.Name = ARENA_FOLDER_NAME
	folder.Parent = workspace
	arenaFolder = folder
	buildFallbackArena(folder)

	-- Roblox owns the respawn timer, so the contract's respawnSeconds is set here rather than
	-- re-implemented: CharacterAdded then places the player by the wave-boundary rule.
	local config = combatConfig
	if config ~= nil then
		Players.RespawnTime = config.player.respawnSeconds
	end
end

function ArenaService.Start(): () end

return ArenaService
