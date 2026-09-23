--!strict
-- The MemoryStore run registry (docs/INTERFACES.md "C0 contracts" → "Combat place server",
-- C1 "Studio bridge" → "Combat side"). This server advertises its own run so a friend in the
-- hub can find and join it; the hub only ever READS the sorted map, so a run can never be
-- advertised by a server that is not hosting it.
--
-- The reserved access code cannot be read back from any API, so the hub writes a RunTicket to a
-- server-only hash map beside the registry (`<mapName>Codes`, key `code_<hostUserId>`) and this
-- module reads it once, verifying that the entry really describes the run being started AND that
-- it was reserved for this very server (C2: `privateServerId`). There is no fallback: without a
-- verified ticket the run publishes nothing and stays unjoinable, which is strictly better than
-- advertising a code that cannot teleport anyone.
--
-- Every call is pcall + retry + warn and nothing depends on the result: a registry outage costs
-- join-in-progress, never the run itself.
--
-- C1: Studio is no longer a no-op. With API access on, a Studio session talks to the real
-- MemoryStore exactly as a live server does; only ProfileStore's in-memory mock (no API access)
-- swaps in the module-level tables below, which keep the same TTL semantics so a Local Server
-- test in one Studio still sees its own run. The ForceRegistryFailure lever makes every call
-- raise inside its pcall, so the backoff and the warns are exercised on demand.

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local StudioBridge = require(servicesFolder:WaitForChild("StudioBridge"))

-- Infrastructure retry policy, like DataService's: three attempts, 1 s / 2 s / 4 s backoff.
local RETRY_ATTEMPTS = 3
local RETRY_BASE_SECONDS = 1
local CODES_MAP_SUFFIX = "Codes"
local CODES_KEY_PREFIX = "code_"
-- Bridge mode has no ReserveServer, so the hub stamps this in place of a real private server id
-- (docs/INTERFACES.md "C2 contracts" -> "Combat place (A)").
local STUDIO_PRIVATE_SERVER_ID = "studio"
-- Sort keys: joinable runs sort by wave and every closed run sorts after all of them, so the
-- hub's single ascending GetRangeAsync page is spent on runs someone can actually join. Waves
-- never approach this offset.
local CLOSED_SORT_OFFSET = 1000

type MapKind = "runs" | "codes"
-- The in-memory stand-in for one MemoryStore map: value plus the moment it expires, checked on
-- read so an entry cannot outlive its TTL any more than a real one would.
type MockEntry = { value: any, expiresAt: number, sortKey: number? }

local sortedMap: any = nil
local codesMap: any = nil
local mockRuns: { [string]: MockEntry } = {}
local mockCodes: { [string]: MockEntry } = {}
-- Set by Main's BindToClose. The retry backoff yields, and a yield inside the shutdown handler
-- would delay DataService.Release (the final save) behind a registry write nobody will read:
-- the entry expires on its TTL anyway.
local closing = false

-- Checked per call, never cached: ProfileStore probes API access asynchronously after require,
-- so a verdict taken at Init would call every session a mock.
local function useMock(): boolean
	return StudioBridge.IsActive() and DataService.IsMockMode()
end

local function mockStore(kind: MapKind): { [string]: MockEntry }
	return if kind == "codes" then mockCodes else mockRuns
end

-- Raised INSIDE every pcall'd body below, so the lever produces the same retries, warns and
-- degraded behaviour a real MemoryStore outage would.
local function failIfLeverSet(): ()
	if StudioBridge.RegistryShouldFail() then
		error("ForceRegistryFailure lever is on", 0)
	end
end

local function getAsync(kind: MapKind, key: string): (boolean, any)
	if useMock() then
		return pcall(function(): any
			failIfLeverSet()
			local store = mockStore(kind)
			local entry = store[key]
			if entry == nil then
				return nil
			end
			if os.clock() >= entry.expiresAt then
				store[key] = nil
				return nil
			end
			return entry.value
		end)
	end
	local map = if kind == "codes" then codesMap else sortedMap
	if map == nil then
		return false, "registry unavailable"
	end
	return pcall(function(): any
		failIfLeverSet()
		return map:GetAsync(key)
	end)
end

local function callWithRetry(description: string, call: () -> ()): boolean
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, err = pcall(function()
			failIfLeverSet()
			call()
		end)
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

-- `sortKey` only means something on the sorted map; the hash map's SetAsync has no such argument.
local function setAsync(
	kind: MapKind,
	key: string,
	value: any,
	ttlSeconds: number,
	sortKey: number?
): boolean
	if useMock() then
		return callWithRetry(`mock SetAsync {key}`, function()
			mockStore(kind)[key] =
				{ value = value, expiresAt = os.clock() + ttlSeconds, sortKey = sortKey }
		end)
	end
	local map = if kind == "codes" then codesMap else sortedMap
	if map == nil then
		return false
	end
	return callWithRetry(`SetAsync {key}`, function()
		if kind == "runs" and sortKey ~= nil then
			map:SetAsync(key, value, ttlSeconds, sortKey)
		else
			map:SetAsync(key, value, ttlSeconds)
		end
	end)
end

local function removeAsync(kind: MapKind, key: string): boolean
	if useMock() then
		return callWithRetry(`mock RemoveAsync {key}`, function()
			mockStore(kind)[key] = nil
		end)
	end
	local map = if kind == "codes" then codesMap else sortedMap
	if map == nil then
		return false
	end
	return callWithRetry(`RemoveAsync {key}`, function()
		map:RemoveAsync(key)
	end)
end

local RunRegistry = {}

-- Main calls this first in BindToClose.
function RunRegistry.MarkClosing(): ()
	closing = true
end

local function isUserId(value: any): boolean
	if typeof(value) ~= "number" or value ~= math.floor(value) or value == 0 then
		return false
	end
	-- Local Server test players have negative ids; a live server never does.
	return value > 0 or RunService:IsStudio()
end

-- Every field type-checked: the hash map is server-written, but a malformed entry (an older hub
-- build, a hand edit) must degrade to "no ticket", never to a runtime error mid-admission.
local function readTicket(value: any): Types.RunTicket?
	if typeof(value) ~= "table" then
		return nil
	end
	local entry = value :: any
	if
		typeof(entry.accessCode) ~= "string"
		or entry.accessCode == ""
		or typeof(entry.privateServerId) ~= "string"
		or typeof(entry.missionId) ~= "string"
		or typeof(entry.overdrive) ~= "boolean"
		or typeof(entry.public) ~= "boolean"
		or typeof(entry.expected) ~= "table"
	then
		return nil
	end
	local expected: { number } = {}
	for _, userId in entry.expected :: { any } do
		if not isUserId(userId) then
			return nil
		end
		table.insert(expected, userId)
	end
	return {
		accessCode = entry.accessCode,
		privateServerId = entry.privateServerId,
		missionId = entry.missionId,
		overdrive = entry.overdrive,
		public = entry.public,
		expected = expected,
	}
end

-- The id this server must find in a ticket: ReserveServer's second return on a live reserved
-- server, the bridge's stand-in in Studio. A public (non-reserved) server has "" here, so no
-- ticket can ever match it: a forged teleport into a public server cannot claim a host gate.
local function expectedPrivateServerId(): string
	if StudioBridge.IsActive() then
		return STUDIO_PRIVATE_SERVER_ID
	end
	return game.PrivateServerId
end

-- Reads the ticket the hub wrote for this run. Verified, not trusted: it must describe the same
-- mission and Overdrive flag as the run actually starting (a stale entry from an earlier
-- expedition by the same host is never honoured) and name this server. nil = the run is private:
-- no expected list, nothing published, and every arrival is unlock-checked (C1 rules).
--
-- Mock mode (Studio without API access) can never receive a hub-written ticket, because the
-- handoff store is unreachable, so it stands one in: public per coop.publicByDefault, the host
-- as the only expected member. That keeps the ticket-driven paths (host gate, lobby start,
-- publish with sort keys into the mock map) exercisable from a solo or Local Server test. Only
-- reachable when StudioBridge.IsActive(), so a live server never synthesises a ticket.
function RunRegistry.ResolveTicket(
	hostUserId: number,
	missionId: string,
	overdrive: boolean
): Types.RunTicket?
	if closing then
		return nil
	end
	if useMock() then
		local combatConfig = Catalog.GetCombatConfig()
		return {
			accessCode = STUDIO_PRIVATE_SERVER_ID,
			privateServerId = STUDIO_PRIVATE_SERVER_ID,
			missionId = missionId,
			overdrive = overdrive,
			public = if combatConfig ~= nil then combatConfig.coop.publicByDefault else false,
			expected = { hostUserId },
		}
	end
	local key = CODES_KEY_PREFIX .. hostUserId
	local ok, value = getAsync("codes", key)
	if not ok then
		warn(`[RunRegistry] codes GetAsync {hostUserId} failed: {value}`)
		return nil
	end
	if value == nil then
		warn(`[RunRegistry] no run ticket for host {hostUserId}; run stays private`)
		return nil
	end
	local ticket = readTicket(value)
	if ticket == nil then
		warn(`[RunRegistry] malformed run ticket for host {hostUserId}; run stays private`)
		return nil
	end
	if ticket.missionId ~= missionId or ticket.overdrive ~= overdrive then
		warn(
			`[RunRegistry] run ticket for host {hostUserId} does not match this run`
				.. ` ({missionId}, overdrive={overdrive}); run stays private`
		)
		return nil
	end
	if ticket.privateServerId ~= expectedPrivateServerId() then
		warn(
			`[RunRegistry] run ticket for host {hostUserId} names another server`
				.. ` ({ticket.privateServerId}); run stays private`
		)
		return nil
	end
	return ticket
end

-- Publishes (or refreshes) this run. Called on every admit and, from C1, on every wave, so the
-- TTL keeps being pushed forward while the run is alive and a crashed server simply expires.
-- C2: the sort key is `wave` while the run is joinable and CLOSED_SORT_OFFSET + wave once it is
-- full or past coop.joinUntilWave. Yields (retry backoff): ArenaService calls it only from its
-- one-slot mailbox thread.
function RunRegistry.Publish(run: Types.ActiveRun): ()
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil or closing then
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
		public = run.public,
		memberIds = table.clone(run.memberIds),
	}
	local coop = combatConfig.coop
	local joinable = run.partySize < coop.maxParty and run.wave <= coop.joinUntilWave
	local sortKey = if joinable then run.wave else CLOSED_SORT_OFFSET + run.wave
	setAsync("runs", tostring(run.hostUserId), stored, combatConfig.registry.ttlSeconds, sortKey)
end

-- Called when the last player leaves, so the hub stops offering a run nobody is in.
function RunRegistry.Clear(hostUserId: number): ()
	if closing then
		return
	end
	removeAsync("runs", tostring(hostUserId))
end

function RunRegistry.Init(): ()
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil then
		return
	end
	-- Resolved unconditionally (including in Studio): these calls build local handles, and
	-- whether they are ever used is a per-call decision in useMock().
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
