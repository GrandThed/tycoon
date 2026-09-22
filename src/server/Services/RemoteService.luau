--!strict
-- Owns the Remotes folder, per-player-per-remote token-bucket rate limiting, and payload type
-- validation, so game services only ever see well-typed intents (docs/INTERFACES.md "Remotes").
-- Rate-limit overflow and malformed payloads are dropped silently per contract: an ActionResult
-- reply would require trusting an unvalidated slotId.
--
-- C0: the remote tables themselves are no longer here. Each place hands its own set to
-- Configure() before Init — HubRemotes in the hub, CombatRemotes in the Expeditions place — so
-- one module serves both trees and neither place can create the other's remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type PackedArgs = { n: number, [number]: any }
export type Validator = (args: PackedArgs) -> boolean
-- bucket names a shared refill rate in `rates`; the token bucket itself stays per remote, so
-- two remotes on the same bucket each get that many calls per second (unchanged from M1).
export type IntentDef = { validate: Validator, bucket: string }
export type RemoteDefs = {
	intents: { [string]: IntentDef },
	events: { string },
	rates: { [string]: number },
}

type Handler = (player: Player, ...any) -> ()
type Bucket = { tokens: number, last: number }

local remotes: { [string]: RemoteEvent } = {}
local handlers: { [string]: Handler } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}
local defs: RemoteDefs? = nil

-- Resolved in Init from the configured rates, clamped to >= 1: a fractional refill rate would
-- start every bucket empty and silently disable the remote, which is worse than a loud warn.
local MIN_CALLS_PER_SECOND = 1
local bucketRates: { [string]: number } = {}

local function clampRate(keyName: string, configured: number): number
	if configured >= MIN_CALLS_PER_SECOND then
		return configured
	end
	warn(
		`[RemoteService] rate {keyName} = {configured} is below {MIN_CALLS_PER_SECOND};`
			.. ` clamped (a lower rate would disable the remote)`
	)
	return MIN_CALLS_PER_SECOND
end

local function bucketCallsPerSecond(remoteName: string): number
	local remoteDefs = defs
	if remoteDefs == nil then
		return MIN_CALLS_PER_SECOND
	end
	local intent = remoteDefs.intents[remoteName]
	if intent == nil then
		return MIN_CALLS_PER_SECOND
	end
	return bucketRates[intent.bucket] or MIN_CALLS_PER_SECOND
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
	local remoteDefs = defs
	if remoteDefs == nil then
		return
	end
	if not tryConsumeToken(player, remoteName) then
		return
	end
	local intent = remoteDefs.intents[remoteName]
	if intent == nil or not intent.validate(args) then
		return
	end
	local handler = handlers[remoteName]
	if handler == nil then
		return
	end
	handler(player, table.unpack(args, 1, args.n))
end

local RemoteService = {}

-- Must be called before Init. The place's boot script owns the definitions, so adding a remote
-- never touches this module.
function RemoteService.Configure(remoteDefs: RemoteDefs): ()
	defs = remoteDefs
end

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
	local remoteDefs = defs
	if remoteDefs == nil then
		-- Refusing to boot the remote layer is the safe failure: creating no remotes leaves the
		-- client on its loading card, where creating unvalidated ones would expose every intent.
		warn("[RemoteService] Init without Configure — no remotes created")
		return
	end

	for bucketName, configured in remoteDefs.rates do
		bucketRates[bucketName] = clampRate(bucketName, configured)
	end

	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage

	local function createRemote(remoteName: string): RemoteEvent
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = folder
		remotes[remoteName] = remote
		return remote
	end

	-- Every remote exists from Init so the client can WaitForChild all of them. Events are
	-- server → client only: no validator, no bucket, no OnServerEvent connection.
	for _, remoteName in remoteDefs.events do
		createRemote(remoteName)
	end
	for remoteName, intent in remoteDefs.intents do
		if remoteDefs.rates[intent.bucket] == nil then
			warn(
				`[RemoteService] {remoteName} names bucket "{intent.bucket}", which has no rate;`
					.. ` falling back to {MIN_CALLS_PER_SECOND}/s`
			)
		end
		local remote = createRemote(remoteName)
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
