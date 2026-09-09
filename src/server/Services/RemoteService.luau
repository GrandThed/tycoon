--!strict
-- Owns the Remotes folder, per-player-per-remote token-bucket rate limiting, and payload type
-- validation, so game services only ever see well-typed intents (docs/INTERFACES.md "Remotes").
-- Rate-limit overflow and malformed payloads are dropped silently per contract: an ActionResult
-- reply would require trusting an unvalidated slotId.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))

-- Every reserved remote exists from Init so the client can WaitForChild all of them;
-- RequestPrompt stays reserved (validator/handler land at M4) and has no dispatcher.
-- FxEvent (M3) is server→client only: presentation events, owner only, never on bulk restore.
local REMOTE_NAMES = {
	"RequestSnapshot",
	"RequestBuy",
	"RequestLevelUp",
	"RequestAdvanceEra",
	"RequestRebirth",
	"RequestSetSetting",
	"RequestPrompt",
	"StateChanged",
	"ActionResult",
	"FxEvent",
}

type PackedArgs = { n: number, [number]: any }
type Validator = (args: PackedArgs) -> boolean
type Handler = (player: Player, ...any) -> ()
type Bucket = { tokens: number, last: number }

local remotes: { [string]: RemoteEvent } = {}
local handlers: { [string]: Handler } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}

local function isCountInRange(value: any): boolean
	if typeof(value) ~= "number" or value ~= math.floor(value) then
		return false
	end
	-- Contract range is 1..100 with maxLevel = 100; bound by config so they cannot drift apart.
	return value >= 1 and value <= Catalog.GetGameConfig().maxLevel
end

local validators: { [string]: Validator } = {
	RequestSnapshot = function(args: PackedArgs): boolean
		return args.n == 0
	end,
	RequestBuy = function(args: PackedArgs): boolean
		return args.n == 1 and typeof(args[1]) == "string"
	end,
	RequestLevelUp = function(args: PackedArgs): boolean
		return args.n == 2 and typeof(args[1]) == "string" and isCountInRange(args[2])
	end,
	RequestAdvanceEra = function(args: PackedArgs): boolean
		return args.n == 0
	end,
	RequestRebirth = function(args: PackedArgs): boolean
		return args.n == 0
	end,
	RequestSetSetting = function(args: PackedArgs): boolean
		-- Only the two Types.SettingKey values exist; anything else is a silent drop.
		return args.n == 2
			and (args[1] == "music" or args[1] == "sfx")
			and typeof(args[2]) == "boolean"
	end,
}

local function tryConsumeToken(player: Player, remoteName: string): boolean
	local callsPerSecond = Catalog.GetGameConfig().remotes.callsPerSecond
	local playerBuckets = buckets[player]
	if playerBuckets == nil then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[remoteName]
	if bucket == nil then
		bucket = { tokens = callsPerSecond, last = now }
		playerBuckets[remoteName] = bucket
	end
	bucket.tokens = math.min(callsPerSecond, bucket.tokens + (now - bucket.last) * callsPerSecond)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

local function dispatch(remoteName: string, player: Player, args: PackedArgs): ()
	-- A remote can land after PlayerRemoving cleanup; without this guard tryConsumeToken would
	-- recreate the defunct player's bucket table and leak it forever.
	if player.Parent == nil then
		return
	end
	if not tryConsumeToken(player, remoteName) then
		return
	end
	local validator = validators[remoteName]
	if validator == nil or not validator(args) then
		return
	end
	local handler = handlers[remoteName]
	if handler == nil then
		return
	end
	handler(player, table.unpack(args, 1, args.n))
end

local RemoteService = {}

-- Handlers receive payloads already validated by the remote's validator above.
function RemoteService.SetHandler(remoteName: string, handler: Handler): ()
	handlers[remoteName] = handler
end

-- For server-side interaction paths (e.g. ProximityPrompts) that funnel into the same action
-- as a remote: spend from that remote's bucket so both paths share one rate-limit budget.
-- Same silent-drop semantics — and the same defunct-player guard — as dispatch above.
function RemoteService.TryConsumeToken(player: Player, remoteName: string): boolean
	if player.Parent == nil then
		return false
	end
	return tryConsumeToken(player, remoteName)
end

function RemoteService.FireClient(player: Player, remoteName: string, payload: any): ()
	-- Optional annotation: map indexing is non-optional under the old solver.
	local remote: RemoteEvent? = remotes[remoteName]
	-- Parent check: the player may have left between a purchase mutation and this reply.
	if remote == nil or player.Parent == nil then
		return
	end
	remote:FireClient(player, payload)
end

function RemoteService.Init(): ()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage

	for _, remoteName in REMOTE_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = folder
		remotes[remoteName] = remote
	end

	-- Only remotes with a validator are client→server intents; connect their dispatchers.
	for remoteName in validators do
		local remote = remotes[remoteName]
		remote.OnServerEvent:Connect(function(player: Player, ...: any)
			dispatch(remoteName, player, table.pack(...))
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)
end

function RemoteService.Start(): () end

return RemoteService
