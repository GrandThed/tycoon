--!strict
-- Boot (frozen Init/Start order) + the M2 per-player join/leave orchestration: Main owns the
-- explicit sequence load → offline grant → claim → snapshot, so no service assumes any
-- PlayerAdded/PlayerRemoving ordering (docs/INTERFACES.md "M2 contracts").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local servicesFolder = script.Parent:WaitForChild("Services")

local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local EconomyService = require(servicesFolder:WaitForChild("EconomyService"))
local PlotService = require(servicesFolder:WaitForChild("PlotService"))
local MonetizationService = require(servicesFolder:WaitForChild("MonetizationService"))

type Service = {
	Init: () -> (),
	Start: () -> (),
}

-- Init/Start order is frozen in docs/INTERFACES.md.
local orderedServices: { Service } = {
	DataService,
	RemoteService,
	EconomyService,
	PlotService,
	MonetizationService,
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

local function onPlayerAdded(player: Player): ()
	task.spawn(function()
		local state = DataService.LoadAsync(player)
		if state == nil then
			-- nil covers load failure, a still-locked session, or the player leaving mid-load
			-- (DataService already released the profile in that case). Kick only if present.
			if player.Parent ~= nil then
				player:Kick("Your data couldn't be loaded — please rejoin in a minute.")
			end
			return
		end
		if player.Parent == nil then
			DataService.Release(player)
			return
		end
		-- Grant before claim/snapshot so the join snapshot already carries the earned cash
		-- (and the welcomeBack card when elapsed >= 60 s and the grant was positive).
		EconomyService.ApplyOfflineGrant(player)
		PlotService.ClaimPlot(player)
		EconomyService.SendSnapshot(player)
	end)
end

local function onPlayerRemoving(player: Player): ()
	-- Teardown order per contract: world first, emission state next, final save last (the tick
	-- rule keeps lastSeen/incomeAtSave fresh, so Release needs no extra stamping).
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

-- Reading Game.json here is deliberate: it proves the JSON→ModuleScript pipeline end-to-end.
local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local gameConfig = require(configFolder:WaitForChild("Game") :: ModuleScript) :: { [string]: any }

print("[Server] booted — tickRate=" .. tostring(gameConfig.tickRate))
