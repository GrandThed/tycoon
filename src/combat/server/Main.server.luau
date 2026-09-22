--!strict
-- Boot + join orchestration for the Expeditions place (docs/INTERFACES.md "C0 contracts" →
-- "Combat place server"). The same Services folder as the hub is mounted here, so this script
-- requires only DataService and RemoteService from it: PlotService, EconomyService,
-- MonetizationService, LegacyShopService and ArmoryService are hub-only and stay inert.
--
-- The teleport data is a HINT, never an entitlement: the mission it names is re-checked against
-- the loaded profile, and a refusal sends the player straight home.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Combat = require(sharedFolder:WaitForChild("Combat"))

local servicesFolder = script.Parent:WaitForChild("Services")
local combatFolder = script.Parent:WaitForChild("Combat")

local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local StudioBridge = require(servicesFolder:WaitForChild("StudioBridge"))
local CombatRemotes = require(combatFolder:WaitForChild("CombatRemotes"))
local RunRegistry = require(combatFolder:WaitForChild("RunRegistry"))
local ArenaService = require(combatFolder:WaitForChild("ArenaService"))
local EnemyService = require(combatFolder:WaitForChild("EnemyService"))
local CombatService = require(combatFolder:WaitForChild("CombatService"))
local WaveService = require(combatFolder:WaitForChild("WaveService"))
local DebugService = require(combatFolder:WaitForChild("DebugService"))
local ReturnService = require(combatFolder:WaitForChild("ReturnService"))

type Service = {
	Init: () -> (),
	Start: () -> (),
}

type Loader = (player: Player) -> Types.PlayerState?

-- Studio (or a standalone boot with no teleport data) plays the first mission unless the
-- DebugMission attribute says otherwise.
local DEFAULT_DEBUG_MISSION_ID = "village"
-- The away clock ticks once a second (the Studio levers moved to DebugService in C1).
local TICK_INTERVAL_SECONDS = 1

local tickAccumulator = 0

-- The combat place sends the same Snapshot shape as the hub so the client model is identical,
-- with the city fields zeroed: there is no plot and no income here. persistedIncomePerSecond is
-- the rate the hub last saved, which is what the Armory readout compares unlock rates against.
local function sendSnapshot(player: Player): ()
	local state = DataService.GetState(player)
	if state == nil then
		-- Safe mode: the client's boot request may land before, during or after the first load
		-- attempt; whichever it is, it must end with a status or a snapshot.
		local status = DataService.GetLoadStatus(player)
		if status ~= nil then
			RemoteService.FireClient(player, "StateChanged", status)
		end
		return
	end
	local mission = ArenaService.GetMission()
	local armoryConfig = Catalog.GetArmoryConfig()
	local snapshot: Types.Snapshot = {
		kind = "snapshot",
		plotIndex = 0,
		eraName = if mission ~= nil then mission.eraName else "",
		state = state,
		incomePerSecond = 0,
		persistedIncomePerSecond = state.incomeAtSave,
		gearPower = if armoryConfig ~= nil
			then Armory.GearPower(armoryConfig, state.combat.gear, state.combat.ascension)
			else 0,
		welcomeBack = nil,
	}
	RemoteService.FireClient(player, "StateChanged", snapshot)
end

-- The hub's teleport data: { missionId, overdrive, hostUserId }. It never carries the reserved
-- access code (the teleporting client can read teleport data) — the code comes from the
-- server-only MemoryStore hash map that RunRegistry verifies. Wrapped in pcall because
-- GetJoinData throws for a player who has already left.
local function readTeleportHint(player: Player): (string?, boolean, number?)
	local ok, joinData = pcall(function(): any
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then
		return nil, false, nil
	end
	local data = (joinData :: any).TeleportData
	if typeof(data) ~= "table" then
		return nil, false, nil
	end
	local missionId = if typeof(data.missionId) == "string" then data.missionId else nil
	local hostUserId = if typeof(data.hostUserId) == "number"
			and data.hostUserId == math.floor(data.hostUserId)
			and data.hostUserId > 0
		then data.hostUserId
		else nil
	return missionId, data.overdrive == true, hostUserId
end

-- C1: in Studio the hub cannot teleport, so it leaves a handoff record instead (docs/INTERFACES.md
-- "Studio bridge"). The record is consumed once and validated EXACTLY like live teleport data —
-- it is a hint from another session, not an entitlement.
local function readArrival(player: Player): (string?, boolean, number?)
	local ok, hint = pcall(StudioBridge.ReadArrival, player)
	if not ok or typeof(hint) ~= "table" then
		return nil, false, nil
	end
	local data = hint :: any
	local missionId = if typeof(data.missionId) == "string" then data.missionId else nil
	local hostUserId = if typeof(data.hostUserId) == "number"
			and data.hostUserId == math.floor(data.hostUserId)
			and data.hostUserId > 0
		then data.hostUserId
		else nil
	return missionId, data.overdrive == true, hostUserId
end

-- Resolution order: live teleport data, then the Studio handoff record, then the Workspace
-- attributes, then the default mission — so build/combat.rbxl still plays on its own with no
-- hub, no teleport and no record.
local function resolveRun(player: Player): (Types.MissionConfig?, boolean, number)
	local combatConfig = Catalog.GetCombatConfig()
	local missionId, overdrive, hintHostUserId = readTeleportHint(player)
	if combatConfig == nil then
		return nil, false, player.UserId
	end
	if missionId == nil then
		local bridgeId, bridgeOverdrive, bridgeHost = readArrival(player)
		if bridgeId ~= nil then
			missionId = bridgeId
			overdrive = bridgeOverdrive
			hintHostUserId = bridgeHost
		end
	end
	local resolvedId = missionId or ""
	if missionId == nil then
		local debugConfig = combatConfig.debug
		local missionAttribute = workspace:GetAttribute(debugConfig.missionAttribute)
		resolvedId = if typeof(missionAttribute) == "string" and missionAttribute ~= ""
			then missionAttribute
			else DEFAULT_DEBUG_MISSION_ID
		overdrive = workspace:GetAttribute(debugConfig.overdriveAttribute) == true
	end
	-- No hint (Studio or a standalone boot): this player is the host of whatever starts here.
	return Catalog.GetMissionById(resolvedId), overdrive, hintHostUserId or player.UserId
end

-- Shared by the first join (LoadAsync) and a safe-mode retry (RetryLoadAsync). Yields.
local function runJoinSequence(player: Player, loader: Loader): ()
	local state = loader(player)
	if state == nil then
		-- Load failure, still-locked session, refused retry, or the player left mid-load. No
		-- kick (M5 safe mode): DataService has already published the load status, and the
		-- client's card offers Retry.
		return
	end
	if not player:IsDescendantOf(Players) then
		DataService.Release(player)
		return
	end
	Combat.TouchHighestEra(state)

	local mission, overdrive, hostUserId = resolveRun(player)
	local combatConfig = Catalog.GetCombatConfig()
	if
		mission == nil
		or combatConfig == nil
		or not Combat.MissionUnlocked(state, mission, overdrive, combatConfig)
	then
		-- The hint asked for something this profile has not unlocked (or the configs are
		-- missing): straight home, which in Studio means "stay with a toast".
		ReturnService.SendHome(player, "locked")
		return
	end
	ArenaService.Admit(player, mission, overdrive, hostUserId)
	-- The hint is only a request: this server may already be running a DIFFERENT mission (a
	-- joiner arriving into a run in progress, or a reused reserved server), and that run is
	-- what the player was just admitted to. Re-check the entitlement against it.
	local joined = ArenaService.GetMission()
	if
		joined == nil
		or not Combat.MissionUnlocked(state, joined, ArenaService.IsOverdrive(), combatConfig)
	then
		ReturnService.SendHome(player, "locked")
		return
	end
	sendSnapshot(player)
end

-- Configure before Init: RemoteService refuses to create any remote without its definitions.
RemoteService.Configure(CombatRemotes)

-- There is no Delta pipeline in this place (EconomyService is hub-only), so a fresh Snapshot is
-- how a reward flush or a debug grant reaches the client. Main owns the Snapshot shape;
-- WaveService and DebugService reach it through ArenaService.
ArenaService.SetSnapshotSender(sendSnapshot)

-- ReturnService needs the join sequence to re-admit a player whose teleport home failed, and
-- only Main has it; handing it over as a hook keeps the service free of Main's requires.
local returnBoot: Service = {
	Init = function()
		ReturnService.Init({
			-- Not task.spawn'd: the failure path calls this on its own thread and the profile
			-- must be back before it re-admits the player.
			rejoin = function(player: Player)
				runJoinSequence(player, DataService.LoadAsync)
			end,
		})
	end,
	Start = ReturnService.Start,
}

-- WaveService.Start() is "the lobby is ready, go", not a boot hook, so the boot pass gets its
-- own adapter (same shape as returnBoot above).
local waveBoot: Service = {
	Init = WaveService.Init,
	Start = WaveService.Boot,
}

-- Boot order per contract: data, remotes, registry, arena, enemies, hits, waves, debug, return.
-- Enemies before hits because CombatService wires EnemyService's hooks in its own Init, and
-- hits before waves because WaveService installs the kill handler on CombatService.
local orderedServices: { Service } = {
	DataService,
	RemoteService,
	RunRegistry,
	ArenaService,
	EnemyService,
	CombatService,
	waveBoot,
	DebugService,
	returnBoot,
}

for _, service in orderedServices do
	service.Init()
end

for _, service in orderedServices do
	service.Start()
end

RemoteService.SetHandler("RequestSnapshot", function(player: Player)
	sendSnapshot(player)
end)

-- Safe-mode retry. Silent drops here are a courtesy; RetryLoadAsync re-checks the same
-- conditions plus the cooldown, so a modified client gains nothing by skipping the card.
RemoteService.SetHandler("RequestRetryLoad", function(player: Player)
	if DataService.GetState(player) ~= nil or DataService.IsLoading(player) then
		return
	end
	task.spawn(runJoinSequence, player, DataService.RetryLoadAsync)
end)

-- Ready is a toggle; the run starts the moment every non-bot member has it on. Deliberately
-- here rather than in ArenaService: the roster service sits below WaveService in the boot order
-- and may not require it.
RemoteService.SetHandler("RequestReady", function(player: Player)
	-- Both halves are guarded on the lobby: ArenaService ignores the toggle once the run is
	-- under way, and nothing here may restart a run that is already going.
	if WaveService.GetPhase() ~= "lobby" then
		return
	end
	ArenaService.SetReady(player)
	if ArenaService.AllReady() then
		WaveService.Start()
	end
end)

-- Yields (the teleport retries), so it gets its own thread.
RemoteService.SetHandler("RequestLeave", function(player: Player)
	task.spawn(ReturnService.SendHome, player, "leave")
end)

-- The hit and ability math (server raycasts and arc checks against the live wave). Every
-- payload here has already passed its validator; CombatService re-resolves every id.
RemoteService.SetHandler(
	"RequestAttack",
	function(player: Player, swingSeq: number, targetIds: { number })
		CombatService.OnAttack(player, swingSeq, targetIds)
	end
)

RemoteService.SetHandler(
	"RequestFire",
	function(player: Player, seq: number, origin: Vector3, direction: Vector3, charge: number)
		CombatService.OnFire(player, seq, origin, direction, charge)
	end
)

RemoteService.SetHandler("RequestAbility", function(player: Player, slot: string)
	CombatService.OnAbility(player, slot)
end)

-- Studio levers, the remote half (the attribute half is DebugService's own 1 Hz poll). The
-- handler itself refuses everything outside Studio.
RemoteService.SetHandler("RequestDebug", function(player: Player, lever: string, value: any)
	DebugService.OnRequest(player, lever, value)
end)

-- The away clock: every second an admitted player spends here is a second the hub pays at
-- Combat.json's expeditionEfficiency when they get back.
local function tickExpeditionSeconds(seconds: number): ()
	for _, player in Players:GetPlayers() do
		if not ArenaService.IsAdmitted(player) then
			continue
		end
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		state.combat.expeditionSeconds += seconds
	end
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	tickAccumulator += deltaTime
	local ticks = 0
	while tickAccumulator >= TICK_INTERVAL_SECONDS do
		tickAccumulator -= TICK_INTERVAL_SECONDS
		ticks += 1
	end
	if ticks == 0 then
		return
	end
	tickExpeditionSeconds(ticks * TICK_INTERVAL_SECONDS)
end)

local function onPlayerAdded(player: Player): ()
	task.spawn(runJoinSequence, player, DataService.LoadAsync)
end

-- Teardown: leave the party (which clears the registry entry with the last member), then the
-- final save. Both steps are idempotent, so PlayerRemoving and the shutdown flush may both run.
local function releasePlayer(player: Player): ()
	ArenaService.Remove(player)
	-- With the last member gone the run is over; a reserved server may be reused by a later
	-- arrival, so the wave machine goes back to the lobby rather than staying in `summary`.
	if ArenaService.GetMission() == nil then
		WaveService.Reset()
	end
	DataService.Release(player)
end

-- A real leave: the trip home is over one way or the other, so its guard goes with it.
local function onPlayerRemoving(player: Player): ()
	ReturnService.Forget(player)
	releasePlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	-- Studio edge: a player can exist before this script connects. LoadAsync dedupes the rare
	-- overlap with the PlayerAdded connection, and the follow-up steps are idempotent.
	onPlayerAdded(player)
end

-- Shutdown flush, same contract as the hub's: ProfileStore's own BindToClose already blocks
-- shutdown until every final save has landed, so this must not yield.
game:BindToClose(function()
	-- First: registry writes must not yield in the backoff ahead of the final saves. The entry
	-- expires on its TTL, so skipping it costs nothing.
	RunRegistry.MarkClosing()
	if RunService:IsStudio() and DataService.IsMockMode() then
		return
	end
	for _, player in Players:GetPlayers() do
		onPlayerRemoving(player)
	end
end)

print("[Combat] booted — mission attribute lever ready")
