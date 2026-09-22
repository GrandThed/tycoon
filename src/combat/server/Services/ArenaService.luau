--!strict
-- The lobby and the party roster of this server's run (docs/INTERFACES.md "C0 contracts" →
-- "Combat place server"). C0 ships the arena as a code-built pad and the authoritative RunState
-- the HUD draws; C1 replaces the pad with the mission's arena and adds the wave phases.
--
-- The weapons decide max HP, so the Humanoid is resized from the PROFILE on every spawn — never
-- from anything the client sent, and never from the teleport data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local RunRegistry = require(script.Parent:WaitForChild("RunRegistry"))

-- Arena geometry is code-built at C0 (nothing in the place file to keep in sync, and Ben can
-- still drop scenery around it): one anchored pad centred on the origin with a spawn on top.
local LOBBY_PAD_SIZE = Vector3.new(64, 2, 64)
local LOBBY_PAD_POSITION = Vector3.new(0, 4, 0)
local LOBBY_PAD_COLOR = Color3.fromRGB(96, 104, 120)
local SPAWN_SIZE = Vector3.new(8, 1, 8)
-- Studs above the pad surface a character is placed at, so nobody spawns inside the pad.
local SPAWN_CLEARANCE = 4

type PartyMember = { player: Player, ready: boolean }

local partyOrder: { Player } = {}
local party: { [Player]: PartyMember } = {}
local runMission: Types.MissionConfig? = nil
local runOverdrive = false
local hostUserId = 0
local hostName = ""
-- The verified reserved code this run is reachable at; nil = unjoinable (nothing published).
local runAccessCode: string? = nil
local warnedUnjoinable = false
-- One CharacterAdded connection per admitted player, disconnected on remove so a run never
-- accumulates listeners for players who have gone home (PlotService TitleTag precedent).
local characterConnections: { [Player]: RBXScriptConnection } = {}
local spawnPart: SpawnLocation? = nil

local function spawnCFrame(): CFrame
	local part = spawnPart
	local y = if part ~= nil then part.Position.Y else LOBBY_PAD_POSITION.Y
	return CFrame.new(Vector3.new(LOBBY_PAD_POSITION.X, y + SPAWN_CLEARANCE, LOBBY_PAD_POSITION.Z))
end

-- The profile is authoritative for max HP. Without Armory.json the Humanoid keeps its default
-- 100, which is the degrade path, not an error.
local function applyMaxHp(player: Player): ()
	local character = player.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local state = DataService.GetState(player)
	local armoryConfig = Catalog.GetArmoryConfig()
	if humanoid == nil or state == nil or armoryConfig == nil then
		return
	end
	local maxHp = Armory.MaxHp(armoryConfig, state.combat.gear, state.combat.ascension)
	humanoid.MaxHealth = maxHp
	humanoid.Health = maxHp
end

local function memberEntry(member: PartyMember): Types.RunPartyMember
	local character = member.player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	return {
		userId = member.player.UserId,
		name = member.player.Name,
		hp = if humanoid ~= nil then humanoid.Health else 0,
		maxHp = if humanoid ~= nil then humanoid.MaxHealth else 0,
		ready = member.ready,
	}
end

local ArenaService = {}

-- One payload for the whole HUD, so the client never derives a phase. C0 only ever sends
-- `lobby` and `summary`; the wave/breather/boss phases arrive with C1.
function ArenaService.BuildRunState(
	phase: "lobby" | "wave" | "breather" | "boss" | "summary" | "ended",
	summary: Types.RunSummary?
): Types.RunState
	local mission = runMission
	local members: { Types.RunPartyMember } = {}
	for _, player in partyOrder do
		local member = party[player]
		if member ~= nil then
			table.insert(members, memberEntry(member))
		end
	end
	return {
		kind = "run",
		phase = phase,
		missionId = if mission ~= nil then mission.id else "",
		overdrive = runOverdrive,
		wave = 0,
		waves = if mission ~= nil then mission.waves else 0,
		alive = 0,
		tempo = 0,
		party = members,
		breatherEndsIn = nil,
		summary = summary,
	}
end

function ArenaService.Broadcast(
	phase: "lobby" | "wave" | "breather" | "boss" | "summary" | "ended"
): ()
	local runState = ArenaService.BuildRunState(phase, nil)
	for _, player in partyOrder do
		RemoteService.FireClient(player, "RunState", runState)
	end
end

local function publishRun(): ()
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
		-- C0 has no waves yet; C1 republishes on every wave so the hub can honour joinUntilWave.
		wave = 0,
		overdrive = runOverdrive,
		partySize = #partyOrder,
		accessCode = accessCode,
	})
end

-- The mission and the Overdrive flag are decided by the FIRST admitted player: everyone else
-- joins the run that is already here, whatever their teleport data claimed. `runHostUserId` is
-- the host from the teleport hint (the departing player's own id for a fresh run), which is the
-- key the hub filed this run's reserved access code under.
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
	end
	if party[player] == nil then
		party[player] = { player = player, ready = false }
		table.insert(partyOrder, player)
	end
	-- Optional annotation: map indexing is non-optional under the old solver.
	local watching: RBXScriptConnection? = characterConnections[player]
	if watching == nil then
		characterConnections[player] = player.CharacterAdded:Connect(function()
			applyMaxHp(player)
			if party[player] ~= nil then
				ArenaService.Broadcast("lobby")
			end
		end)
	end

	local spawn = spawnPart
	if spawn ~= nil then
		-- Respawns after a C1 death land back on the pad, not at the world origin.
		player.RespawnLocation = spawn
	end
	local character = player.Character
	if character ~= nil then
		character:PivotTo(spawnCFrame())
	end
	applyMaxHp(player)
	publishRun()
	ArenaService.Broadcast("lobby")
end

-- RequestReady toggles: the button is the same button in both directions, and C1 starts wave 1
-- once every member is ready.
function ArenaService.SetReady(player: Player): ()
	local member = party[player]
	if member == nil then
		return
	end
	member.ready = not member.ready
	ArenaService.Broadcast("lobby")
end

function ArenaService.IsAdmitted(player: Player): boolean
	return party[player] ~= nil
end

function ArenaService.GetMission(): Types.MissionConfig?
	return runMission
end

function ArenaService.IsOverdrive(): boolean
	return runOverdrive
end

-- Leaving, teleporting home, or disconnecting all end here. The registry entry goes away with
-- the last member so the hub never offers an empty run.
function ArenaService.Remove(player: Player): ()
	if party[player] == nil then
		return
	end
	party[player] = nil
	local index = table.find(partyOrder, player)
	if index ~= nil then
		table.remove(partyOrder, index)
	end
	local connection: RBXScriptConnection? = characterConnections[player]
	if connection ~= nil then
		connection:Disconnect()
		characterConnections[player] = nil
	end
	if #partyOrder == 0 then
		if hostUserId ~= 0 then
			RunRegistry.Clear(hostUserId)
		end
		-- The run is over: a reserved server can be reused by a later arrival (or by a rejoin
		-- after a failed trip home), and leaving the old mission, host and access code in place
		-- would advertise a run that no longer exists.
		runMission = nil
		runOverdrive = false
		hostUserId = 0
		hostName = ""
		runAccessCode = nil
		warnedUnjoinable = false
		return
	end
	publishRun()
	ArenaService.Broadcast("lobby")
end

function ArenaService.Init(): ()
	local pad = Instance.new("Part")
	pad.Name = "LobbyPad"
	pad.Size = LOBBY_PAD_SIZE
	pad.Position = LOBBY_PAD_POSITION
	pad.Anchored = true
	pad.Color = LOBBY_PAD_COLOR
	pad.Material = Enum.Material.Concrete
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Parent = workspace

	-- A real SpawnLocation (not just a PivotTo): respawns after a C1 death must land here too,
	-- and RespawnLocation only accepts one.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = SPAWN_SIZE
	spawn.Position = LOBBY_PAD_POSITION + Vector3.new(0, LOBBY_PAD_SIZE.Y / 2 + SPAWN_SIZE.Y / 2, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = pad
	spawnPart = spawn

	-- The per-player CharacterAdded watch is connected in Admit (and dropped in Remove): max HP
	-- only has to be re-applied on respawn for players who are actually in the run.
end

function ArenaService.Start(): () end

return ArenaService
