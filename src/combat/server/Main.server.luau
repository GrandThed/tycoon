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
local CombatRemotes = require(combatFolder:WaitForChild("CombatRemotes"))
local RunRegistry = require(combatFolder:WaitForChild("RunRegistry"))
local ArenaService = require(combatFolder:WaitForChild("ArenaService"))
local ReturnService = require(combatFolder:WaitForChild("ReturnService"))

type Service = {
	Init: () -> (),
	Start: () -> (),
}

type Loader = (player: Player) -> Types.PlayerState?

-- Studio (or a standalone boot with no teleport data) plays the first mission unless the
-- DebugMission attribute says otherwise.
local DEFAULT_DEBUG_MISSION_ID = "village"
-- The away clock and the Studio levers share one 1 Hz accumulator.
local TICK_INTERVAL_SECONDS = 1

local isStudio = RunService:IsStudio()
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

-- In Studio the Workspace attributes always win, so the place can be played on its own from
-- build/combat.rbxl with no hub and no teleport.
local function resolveRun(player: Player): (Types.MissionConfig?, boolean, number)
	local combatConfig = Catalog.GetCombatConfig()
	local missionId, overdrive, hintHostUserId = readTeleportHint(player)
	if combatConfig == nil then
		return nil, false, player.UserId
	end
	local resolvedId = missionId or ""
	if isStudio or missionId == nil then
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

-- Boot order per contract: data, remotes, registry, arena, return.
local orderedServices: { Service } = {
	DataService,
	RemoteService,
	RunRegistry,
	ArenaService,
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

RemoteService.SetHandler("RequestReady", function(player: Player)
	ArenaService.SetReady(player)
end)

-- Yields (the teleport retries), so it gets its own thread.
RemoteService.SetHandler("RequestLeave", function(player: Player)
	task.spawn(ReturnService.SendHome, player, "leave")
end)

-- C1 owns the hit and ability math (server raycasts against the live wave). The handlers are
-- registered now so a validated intent is dropped deliberately, and the remotes exist for the
-- client to bind to from C0.
RemoteService.SetHandler("RequestAttack", function() end)
RemoteService.SetHandler("RequestAbility", function() end)

-- Studio levers (combat place half of the pair in ArmoryService): a positive number on
-- Workspace is consumed once and reset to 0, so materials and Valor can be handed out without
-- an enemy existing yet.
local function consumeGrantLever(
	attribute: string,
	apply: (state: Types.PlayerState, value: number) -> ()
): ()
	local value = workspace:GetAttribute(attribute)
	-- NaN/inf are refused too: Studio with API access writes a real profile, and a corrupted
	-- materials or Valor field would survive the session.
	if typeof(value) ~= "number" or value <= 0 or value ~= value or value == math.huge then
		return
	end
	workspace:SetAttribute(attribute, 0)
	local granted = 0
	for _, player in Players:GetPlayers() do
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		apply(state, value)
		-- No delta pipeline in this place (EconomyService is hub-only), so a fresh snapshot is
		-- how the client sees the grant.
		sendSnapshot(player)
		granted += 1
	end
	warn(
		`[Combat] {attribute} lever: granted {value} to {granted} loaded player(s);`
			.. ` attribute reset to 0`
	)
end

local function consumeStudioLevers(): ()
	local combatConfig = Catalog.GetCombatConfig()
	local mission = ArenaService.GetMission()
	if combatConfig == nil or mission == nil then
		return
	end
	local material = mission.material
	local debugConfig = combatConfig.debug
	consumeGrantLever(debugConfig.grantMaterialsAttribute, function(state, value)
		state.combat.materials[material] = (state.combat.materials[material] or 0) + value
	end)
	consumeGrantLever(debugConfig.grantValorAttribute, function(state, value)
		state.combat.valor += value
	end)
end

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
	if isStudio then
		consumeStudioLevers()
	end
end)

local function onPlayerAdded(player: Player): ()
	task.spawn(runJoinSequence, player, DataService.LoadAsync)
end

-- Teardown: leave the party (which clears the registry entry with the last member), then the
-- final save. Both steps are idempotent, so PlayerRemoving and the shutdown flush may both run.
local function releasePlayer(player: Player): ()
	ArenaService.Remove(player)
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
