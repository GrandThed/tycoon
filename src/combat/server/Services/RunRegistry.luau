--!strict
-- The MemoryStore run registry (docs/INTERFACES.md "C0 contracts" → "Combat place server").
-- This server advertises its own run so a friend in the hub can find and join it; the hub only
-- ever READS the sorted map, so a run can never be advertised by a server that is not hosting it.
--
-- The reserved access code cannot be read back from any API, so the hub writes it to a
-- server-only hash map beside the registry (`<mapName>Codes`, key `code_<hostUserId>`) and this
-- module reads it once, verifying that the entry really describes the run being started. There
-- is no fallback: without a verified code the run publishes nothing and stays unjoinable, which
-- is strictly better than advertising a code that cannot teleport anyone.
--
-- Every call is pcall + retry + warn and nothing depends on the result: a registry outage costs
-- join-in-progress, never the run itself. In Studio the whole module is a no-op (MemoryStore
-- needs API access, and a Studio playtest must not publish a server nobody can teleport into).

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

-- Infrastructure retry policy, like DataService's: three attempts, 1 s / 2 s / 4 s backoff.
local RETRY_ATTEMPTS = 3
local RETRY_BASE_SECONDS = 1
local CODES_MAP_SUFFIX = "Codes"
local CODES_KEY_PREFIX = "code_"

local isStudio = RunService:IsStudio()
local sortedMap: any = nil
local codesMap: any = nil
-- Set by Main's BindToClose. The retry backoff yields, and a yield inside the shutdown handler
-- would delay DataService.Release (the final save) behind a registry write nobody will read:
-- the entry expires on its TTL anyway.
local closing = false

local function callWithRetry(description: string, call: () -> boolean): boolean
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, err = pcall(call)
		if ok then
			return true
		end
		warn(`[RunRegistry] {description} failed (attempt {attempt}): {err}`)
		if attempt < RETRY_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return false
end

local RunRegistry = {}

-- Main calls this first in BindToClose.
function RunRegistry.MarkClosing(): ()
	closing = true
end

-- Reads the code the hub reserved for this run. Verified, not trusted: the hash map entry must
-- describe the same mission and Overdrive flag as the run actually starting, so a stale entry
-- from an earlier expedition by the same host can never be advertised for this one.
function RunRegistry.ResolveAccessCode(
	hostUserId: number,
	missionId: string,
	overdrive: boolean
): string?
	local map = codesMap
	if map == nil or closing then
		return nil
	end
	local key = CODES_KEY_PREFIX .. hostUserId
	local ok, value = pcall(function(): any
		return map:GetAsync(key)
	end)
	if not ok then
		warn(`[RunRegistry] codes GetAsync {hostUserId} failed: {value}`)
		return nil
	end
	if typeof(value) ~= "table" then
		warn(`[RunRegistry] no reserved code for host {hostUserId}; run stays unjoinable`)
		return nil
	end
	local entry = value :: any
	if
		typeof(entry.accessCode) ~= "string"
		or entry.accessCode == ""
		or entry.missionId ~= missionId
		or entry.overdrive ~= overdrive
	then
		warn(
			`[RunRegistry] reserved code for host {hostUserId} does not match this run`
				.. ` ({missionId}, overdrive={overdrive}); run stays unjoinable`
		)
		return nil
	end
	return entry.accessCode
end

-- Publishes (or refreshes) this run. Called on every admit and, from C1, on every wave, so the
-- TTL keeps being pushed forward while the run is alive and a crashed server simply expires.
function RunRegistry.Publish(run: Types.ActiveRun): ()
	local map = sortedMap
	local combatConfig = Catalog.GetCombatConfig()
	if map == nil or combatConfig == nil or closing then
		return
	end
	if run.accessCode == "" then
		-- Nobody could teleport in, so advertising it would only produce failed joins.
		return
	end
	local stored: Types.ActiveRun = {
		hostUserId = run.hostUserId,
		hostName = run.hostName,
		missionId = run.missionId,
		era = run.era,
		wave = run.wave,
		overdrive = run.overdrive,
		partySize = run.partySize,
		accessCode = run.accessCode,
	}
	local ttl = combatConfig.registry.ttlSeconds
	callWithRetry(`SetAsync {run.hostUserId}`, function(): boolean
		map:SetAsync(tostring(run.hostUserId), stored, ttl)
		return true
	end)
end

-- Called when the last player leaves, so the hub stops offering a run nobody is in.
function RunRegistry.Clear(hostUserId: number): ()
	local map = sortedMap
	if map == nil or closing then
		return
	end
	callWithRetry(`RemoveAsync {hostUserId}`, function(): boolean
		map:RemoveAsync(tostring(hostUserId))
		return true
	end)
end

function RunRegistry.Init(): ()
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil or isStudio then
		return
	end
	local mapName = combatConfig.registry.mapName
	local ok, maps = pcall(function(): { any }
		return {
			MemoryStoreService:GetSortedMap(mapName),
			MemoryStoreService:GetHashMap(mapName .. CODES_MAP_SUFFIX),
		}
	end)
	if not ok then
		warn(`[RunRegistry] MemoryStore lookup failed: {maps}`)
		return
	end
	sortedMap = maps[1]
	codesMap = maps[2]
end

function RunRegistry.Start(): () end

return RunRegistry
