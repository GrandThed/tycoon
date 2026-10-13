--!strict
-- The run's own effects (`wave`, `bossDown`, `mentor`, and Studio toasts) on the CombatFx event
-- (docs/INTERFACES.md "P5 contracts", ruling 23). Moved verbatim from CombatService.PushFx when
-- missions moved to the crowd: batched once per Heartbeat frame, one FireClient per member per
-- frame instead of one per effect. Only run members receive them, as before.
--
-- No per-kill `kill` effect goes through here in crowd missions: the clients draw the deaths
-- from the crowd stream, and a crowd dies five to ten times as often as the old waves did.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))

local broadcastQueue: { Types.CombatFx } = {}
local privateQueue: { [Player]: { Types.CombatFx } } = {}
local running = false

local RunFx = {}

local function flush(): ()
	if #broadcastQueue == 0 and next(privateQueue) == nil then
		return
	end
	local shared = broadcastQueue
	broadcastQueue = {}
	local personal = privateQueue
	privateQueue = {}
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if player == nil then
			continue
		end
		local own = personal[player]
		local batch = shared
		if own ~= nil then
			batch = table.clone(shared)
			table.move(own, 1, #own, #batch + 1, batch)
		end
		if #batch > 0 then
			RemoteService.FireClient(player, "CombatFx", batch)
		end
	end
end

-- Started by the first effect, so a place that never pushes one never runs the loop.
local function ensureRunning(): ()
	if running then
		return
	end
	running = true
	RunService.Heartbeat:Connect(flush)
	Players.PlayerRemoving:Connect(function(player: Player)
		privateQueue[player] = nil
	end)
end

-- To every run member, in this frame's batch.
function RunFx.Push(fx: Types.CombatFx): ()
	ensureRunning()
	table.insert(broadcastQueue, fx)
end

-- To one member only, in the same frame's batch.
function RunFx.PushTo(player: Player, fx: Types.CombatFx): ()
	ensureRunning()
	local queue = privateQueue[player]
	if queue == nil then
		queue = {}
		privateQueue[player] = queue
	end
	table.insert(queue, fx)
end

return RunFx
