--!strict
-- The run's own effects (`wave`, `bossDown`, `mentor`, and Studio toasts) on the CombatFx event
-- (docs/INTERFACES.md "P5 contracts", ruling 23). The C1 combat server's batching, moved here
-- when missions moved to the crowd (that server went in L4 W1b): once per Heartbeat frame, one
-- FireClient per member per frame instead of one per effect. Only run members receive them. (The
-- per-player queue did not move: nothing in a crowd mission sends a private effect.)
--
-- No per-kill `kill` effect goes through here in crowd missions: the clients draw the deaths
-- from the crowd stream, and a crowd dies five to ten times as often as the old waves did.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))

local broadcastQueue: { Types.CombatFx } = {}
local running = false

local RunFx = {}

local function flush(): ()
	if #broadcastQueue == 0 then
		return
	end
	local batch = broadcastQueue
	broadcastQueue = {}
	for _, member in ArenaService.GetMembers() do
		RemoteService.FireClient(member.player, "CombatFx", batch)
	end
end

-- Started by the first effect, so a place that never pushes one never runs the loop.
local function ensureRunning(): ()
	if running then
		return
	end
	running = true
	RunService.Heartbeat:Connect(flush)
end

-- To every run member, in this frame's batch.
function RunFx.Push(fx: Types.CombatFx): ()
	ensureRunning()
	table.insert(broadcastQueue, fx)
end

return RunFx
