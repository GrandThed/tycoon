--!strict
-- Boot (frozen Init/Start order) + the per-player join/leave orchestration: Main owns the
-- explicit sequence load → passes → offline grant → claim → snapshot, so no service assumes any
-- PlayerAdded/PlayerRemoving ordering (docs/INTERFACES.md "M2 contracts", M5 safe mode).
-- C0: it also owns the remote definitions handed to RemoteService and the release/rejoin hooks
-- the expedition handoff borrows, which is what keeps ExpeditionService out of a require cycle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local servicesFolder = script.Parent:WaitForChild("Services")

local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local HubRemotes = require(servicesFolder:WaitForChild("HubRemotes"))
local EconomyService = require(servicesFolder:WaitForChild("EconomyService"))
local PlotService = require(servicesFolder:WaitForChild("PlotService"))
local LegacyShopService = require(servicesFolder:WaitForChild("LegacyShopService"))
local ArmoryService = require(servicesFolder:WaitForChild("ArmoryService"))
local ExpeditionService = require(servicesFolder:WaitForChild("ExpeditionService"))
local StudioBridge = require(servicesFolder:WaitForChild("StudioBridge"))
local MonetizationService = require(servicesFolder:WaitForChild("MonetizationService"))
local AnalyticsService = require(servicesFolder:WaitForChild("AnalyticsService"))

type Service = {
	Init: () -> (),
	Start: () -> (),
}

type Loader = (player: Player) -> Types.PlayerState?

-- Players with a VIP skin rebuild already scheduled; flips inside the window share it.
local pendingSkinRefresh: { [Player]: boolean } = {}
-- Players who already saw their expedition card this session. Teleport data survives a re-run
-- of the join sequence (a failed departure re-loads the profile), and the card must not come
-- back with it; the Studio bridge's record is consumed on its first read and needs no guard.
local summarySent: { [Player]: boolean } = {}

-- Teardown order per contract: world first, emission state next, final save last (the tick
-- rule keeps lastSeen/incomeAtSave fresh, so Release needs no extra stamping). Every step is
-- idempotent, so PlayerRemoving, the shutdown flush and a departing expedition may all run it
-- for one player.
-- The combat place's RunSummary as it arrives in teleport data: a hint like any other, so every
-- field is type-checked before the client is told anything. bestWave/died are read leniently
-- because a place build without C1's WaveService simply does not send them.
local function asRunSummary(value: any): Types.RunSummary?
	if typeof(value) ~= "table" then
		return nil
	end
	local raw = value :: any
	if
		typeof(raw.missionId) ~= "string"
		or typeof(raw.overdrive) ~= "boolean"
		or typeof(raw.wavesCleared) ~= "number"
		or typeof(raw.cash) ~= "number"
		or typeof(raw.valor) ~= "number"
		or typeof(raw.kills) ~= "number"
		or typeof(raw.seconds) ~= "number"
		or typeof(raw.materials) ~= "table"
	then
		return nil
	end
	local materials: { [string]: number } = {}
	for material, amount in raw.materials :: { [string]: any } do
		if typeof(material) == "string" and typeof(amount) == "number" then
			materials[material] = amount
		end
	end
	-- Built through `any`: bestWave/died land with C1's WaveService, so neither their absence
	-- nor their arrival may break this build.
	local summary: any = {
		missionId = raw.missionId,
		overdrive = raw.overdrive,
		wavesCleared = raw.wavesCleared,
		cash = raw.cash,
		materials = materials,
		valor = raw.valor,
		kills = raw.kills,
		seconds = raw.seconds,
		bestWave = if typeof(raw.bestWave) == "number" then raw.bestWave else 0,
		died = raw.died == true,
	}
	return summary :: Types.RunSummary
end

-- Live transport: the teleport data the combat place set on the way home. Wrapped in pcall
-- because GetJoinData throws for a player who has already left.
local function readTeleportSummary(player: Player): Types.RunSummary?
	local ok, joinData = pcall(function(): any
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then
		return nil
	end
	local data = (joinData :: any).TeleportData
	if typeof(data) ~= "table" then
		return nil
	end
	return asRunSummary((data :: any).summary)
end

-- Presentation only: the rewards are already in the profile the combat place saved, so a
-- missing card never costs anything. In Studio the record the bridge wrote stands in for the
-- teleport data (docs/INTERFACES.md "C1 contracts" → "Studio bridge").
local function sendExpeditionSummary(player: Player): ()
	if summarySent[player] then
		return
	end
	local summary = readTeleportSummary(player) or StudioBridge.ReadReturn(player)
	if summary == nil then
		return
	end
	summarySent[player] = true
	RemoteService.FireClient(player, "ExpeditionSummary", summary)
end

local function releasePlayer(player: Player): ()
	pendingSkinRefresh[player] = nil
	PlotService.Release(player)
	EconomyService.Cleanup(player)
	DataService.Release(player)
end

-- Shared by the first join (LoadAsync) and a safe-mode retry (RetryLoadAsync). Yields.
local function runJoinSequence(player: Player, loader: Loader): ()
	local state = loader(player)
	if state == nil then
		-- Load failure, still-locked session, refused retry, or the player left mid-load (the
		-- profile is released internally then). No kick (M5 safe mode): DataService has already
		-- published the load status, and the player may retry or leave from the card.
		return
	end
	if player.Parent == nil then
		DataService.Release(player)
		return
	end
	-- Passes first (yields): the offline grant must already see Offline Pro's wider cap
	-- and full efficiency, and the join snapshot must report the paid income multipliers.
	MonetizationService.RefreshPassesAsync(player)
	-- Same "left during the yield" guard as above, phrased against Players so the solver
	-- doesn't treat the already-narrowed player.Parent as non-nil.
	if not player:IsDescendantOf(Players) then
		DataService.Release(player)
		return
	end
	-- Grant before claim/snapshot so the join snapshot already carries the earned cash
	-- (and the welcomeBack card when elapsed >= 60 s and the grant was positive).
	EconomyService.ApplyOfflineGrant(player)
	PlotService.ClaimPlot(player)
	EconomyService.SendSnapshot(player)
	-- After the snapshot: the card is read against a client model that already has the wallet
	-- the run paid into. Yields in Studio (the bridge reads a DataStore), so it goes last.
	sendExpeditionSummary(player)
end

-- Configure before Init: RemoteService refuses to create any remote without its definitions.
RemoteService.Configure(HubRemotes)

-- ExpeditionService needs Main's own teardown and join sequence, and Main is the only place
-- that has both; handing them over as hooks at Init keeps the service free of PlotService and
-- MonetizationService requires (which would be a cycle through EconomyService).
local expeditionBoot: Service = {
	Init = function()
		ExpeditionService.Init({
			release = releasePlayer,
			-- Not task.spawn'd: the handoff calls this on its own thread and needs the profile
			-- to be back before it undoes the departure stamp.
			rejoin = function(player: Player)
				runJoinSequence(player, DataService.LoadAsync)
			end,
		})
	end,
	Start = ExpeditionService.Start,
}

-- Init/Start order is frozen in docs/INTERFACES.md.
local orderedServices: { Service } = {
	DataService,
	RemoteService,
	EconomyService,
	PlotService,
	-- M6: sells Legacy shop tiers; needs PlotService (cosmetics refresh) and nothing needs it.
	LegacyShopService,
	-- C0: the Armory sells weapon tiers against EconomyService's persisted rate; the expedition
	-- handoff releases the profile and teleports. Nothing needs either of them.
	ArmoryService,
	expeditionBoot,
	MonetizationService,
	-- AnalyticsService goes last: it depends on nothing, and nothing depends on its Start.
	AnalyticsService,
}

for _, service in orderedServices do
	service.Init()
end

for _, service in orderedServices do
	service.Start()
end

-- RequestSetSetting (M3). The contract places this handler in DataService.Start, but marking
-- the delta needs EconomyService, which already requires DataService — a require cycle. Main
-- requires both, so the wiring lives here; the state write itself stays in DataService.
-- Payload types are already validated by RemoteService; casts narrow the varargs.
RemoteService.SetHandler("RequestSetSetting", function(player: Player, key: any, value: any)
	-- Read before the write: re-sending the current vipSkins value must not rebuild the plot.
	local state = DataService.GetState(player)
	local previousVipSkins = if state ~= nil then state.settings.vipSkins else nil
	if not DataService.SetSetting(player, key :: Types.SettingKey, value :: boolean) then
		return
	end
	EconomyService.MarkDirty(player, { settings = true })
	-- Without VIP nothing on the plot changes, and alternating values would otherwise let any
	-- client force a full plot rebuild on every rate-limited call.
	if
		key ~= "vipSkins"
		or value == previousVipSkins
		or state == nil
		or state.passes.VIP ~= true
	then
		return
	end
	if pendingSkinRefresh[player] then
		return
	end
	pendingSkinRefresh[player] = true
	task.delay(Catalog.GetGameConfig().remotes.skinRefreshDelaySeconds, function()
		if pendingSkinRefresh[player] == nil then
			return -- left during the window
		end
		pendingSkinRefresh[player] = nil
		PlotService.RefreshCosmetics(player)
	end)
end)

local function onPlayerAdded(player: Player): ()
	task.spawn(runJoinSequence, player, DataService.LoadAsync)
end

-- Safe-mode retry. Silent drops here are a courtesy; RetryLoadAsync re-checks the same
-- conditions plus the cooldown, so a modified client gains nothing by skipping the card.
RemoteService.SetHandler("RequestRetryLoad", function(player: Player)
	if DataService.GetState(player) ~= nil or DataService.IsLoading(player) then
		return
	end
	task.spawn(runJoinSequence, player, DataService.RetryLoadAsync)
end)

-- C0 expedition intents. Wired here (not in ExpeditionService.Init) because the handoff runs
-- Main's own release/rejoin sequence; all three yield, so each gets its own thread.
RemoteService.SetHandler(
	"RequestExpedition",
	function(player: Player, missionId: any, overdrive: any)
		task.spawn(ExpeditionService.Depart, player, missionId :: string, overdrive :: boolean)
	end
)

RemoteService.SetHandler("RequestJoinRun", function(player: Player, hostUserId: any)
	task.spawn(ExpeditionService.Join, player, hostUserId :: number)
end)

RemoteService.SetHandler("RequestRunList", function(player: Player)
	task.spawn(ExpeditionService.SendRunList, player)
end)

-- C1 Studio levers from the client DebugPanel. ArmoryService owns the lever table (it already
-- owns the Workspace-attribute half) and ignores every call outside Studio.
RemoteService.SetHandler("RequestDebug", function(player: Player, lever: any, value: any)
	ArmoryService.HandleDebug(player, lever :: string, value)
end)

-- A real leave, as opposed to the release the expedition handoff runs mid-teleport: only here
-- may the in-flight departure guard be forgotten, or a TeleportInitFailed arriving after the
-- handoff released the profile would find no record to recover from.
local function onPlayerRemoving(player: Player): ()
	ExpeditionService.Forget(player)
	summarySent[player] = nil
	releasePlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	-- Studio edge: a player can exist before this script connects. LoadAsync dedupes the rare
	-- overlap with the PlayerAdded connection, and the follow-up steps are idempotent.
	onPlayerAdded(player)
end

-- Shutdown flush: run the leave teardown for everyone still holding a profile so the final
-- save carries the last tick. Must not yield or wait on ProfileStore — its own BindToClose
-- (registered at require time) already blocks shutdown until every final save has landed.
-- In Studio this is skipped only when ProfileStore is writing to its mock (nothing would
-- persist and the wait only slows Stop); with API access on it runs in Studio too.
game:BindToClose(function()
	if RunService:IsStudio() and DataService.IsMockMode() then
		return
	end
	-- Unconditional: ProfileStore's BindToClose may already have ended the sessions, and every
	-- step is a no-op for a player who has nothing to tear down.
	for _, player in Players:GetPlayers() do
		onPlayerRemoving(player)
	end
end)

-- Reading Game.json here is deliberate: it proves the JSON→ModuleScript pipeline end-to-end.
local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local gameConfig = require(configFolder:WaitForChild("Game") :: ModuleScript) :: { [string]: any }

print("[Server] booted — tickRate=" .. tostring(gameConfig.tickRate))
