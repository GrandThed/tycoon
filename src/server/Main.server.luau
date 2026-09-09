--!strict
-- Boot (frozen Init/Start order) + the per-player join/leave orchestration: Main owns the
-- explicit sequence load → passes → offline grant → claim → snapshot, so no service assumes any
-- PlayerAdded/PlayerRemoving ordering (docs/INTERFACES.md "M2 contracts", M5 safe mode).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local servicesFolder = script.Parent:WaitForChild("Services")

local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local EconomyService = require(servicesFolder:WaitForChild("EconomyService"))
local PlotService = require(servicesFolder:WaitForChild("PlotService"))
local MonetizationService = require(servicesFolder:WaitForChild("MonetizationService"))
local AnalyticsService = require(servicesFolder:WaitForChild("AnalyticsService"))

type Service = {
	Init: () -> (),
	Start: () -> (),
}

type Loader = (player: Player) -> Types.PlayerState?

-- Init/Start order is frozen in docs/INTERFACES.md.
local orderedServices: { Service } = {
	DataService,
	RemoteService,
	EconomyService,
	PlotService,
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
	if DataService.SetSetting(player, key :: Types.SettingKey, value :: boolean) then
		EconomyService.MarkDirty(player, { settings = true })
	end
end)

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
end

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

-- Teardown order per contract: world first, emission state next, final save last (the tick
-- rule keeps lastSeen/incomeAtSave fresh, so Release needs no extra stamping). Every step is
-- idempotent, so PlayerRemoving and the shutdown flush may both run it for one player.
local function onPlayerRemoving(player: Player): ()
	PlotService.Release(player)
	EconomyService.Cleanup(player)
	DataService.Release(player)
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
