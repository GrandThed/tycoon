--!strict
-- Owns the Remotes folder, per-player-per-remote token-bucket rate limiting, and payload type
-- validation, so game services only ever see well-typed intents (docs/INTERFACES.md "Remotes").
-- Rate-limit overflow and malformed payloads are dropped silently per contract: an ActionResult
-- reply would require trusting an unvalidated slotId.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))

-- Every reserved remote exists from Init so the client can WaitForChild all of them.
-- FxEvent (M3) is server→client only: presentation events, owner only, never on bulk restore.
local REMOTE_NAMES = {
	"RequestSnapshot",
	"RequestBuy",
	"RequestLevelUp",
	"RequestAdvanceEra",
	"RequestRebirth",
	"RequestSetSetting",
	"RequestPrompt",
	"RequestRetryLoad",
	"RequestBuyPerk",
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
	RequestPrompt = function(args: PackedArgs): boolean
		-- The key itself is resolved (and unknown keys dropped) by MonetizationService, which
		-- owns the pass/product tables; the validator only guarantees the shape.
		return args.n == 1 and typeof(args[1]) == "string"
	end,
	RequestSetSetting = function(args: PackedArgs): boolean
		-- Only the two Types.SettingKey values exist; anything else is a silent drop.
		return args.n == 2
			and (args[1] == "music" or args[1] == "sfx")
			and typeof(args[2]) == "boolean"
	end,
	RequestRetryLoad = function(args: PackedArgs): boolean
		-- Shape only; the real throttle is DataService's retry cooldown (M5 safe mode).
		return args.n == 0
	end,
	RequestBuyPerk = function(args: PackedArgs): boolean
		-- The perk id is resolved (and unknown ids refused) by LegacyShopService, which owns
		-- the purchase chain; shared callsPerSecond bucket (M6 — earned currency, no dialog).
		return args.n == 1 and typeof(args[1]) == "string"
	end,
}

-- Resolved once in Init from Game.json, clamped to >= 1: a fractional refill rate would start
-- every bucket empty and silently disable the remote, which is worse than a loud warn.
local MIN_CALLS_PER_SECOND = 1
local bucketRates = {
	calls = MIN_CALLS_PER_SECOND,
	prompt = MIN_CALLS_PER_SECOND,
	snapshot = MIN_CALLS_PER_SECOND,
}

local function clampRate(keyName: string, configured: number): number
	if configured >= MIN_CALLS_PER_SECOND then
		return configured
	end
	warn(
		`[RemoteService] remotes.{keyName} = {configured} is below {MIN_CALLS_PER_SECOND};`
			.. ` clamped (a lower rate would disable the remote)`
	)
	return MIN_CALLS_PER_SECOND
end

-- RequestPrompt opens a modal OS purchase dialog rather than performing a game action, so it
-- gets its own much tighter budget (Game.json v1.4); RequestSnapshot answers with a full
-- state snapshot, the most expensive reply the server makes, so it gets its own too (v1.5).
-- Every other remote shares callsPerSecond.
local function bucketCallsPerSecond(remoteName: string): number
	if remoteName == "RequestPrompt" then
		return bucketRates.prompt
	end
	if remoteName == "RequestSnapshot" then
		return bucketRates.snapshot
	end
	return bucketRates.calls
end

local function tryConsumeToken(player: Player, remoteName: string): boolean
	local callsPerSecond = bucketCallsPerSecond(remoteName)
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
	local remotesConfig = Catalog.GetGameConfig().remotes
	bucketRates.calls = clampRate("callsPerSecond", remotesConfig.callsPerSecond)
	bucketRates.prompt = clampRate("promptCallsPerSecond", remotesConfig.promptCallsPerSecond)
	bucketRates.snapshot = clampRate("snapshotCallsPerSecond", remotesConfig.snapshotCallsPerSecond)

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
