--!strict
-- The Studio stand-in for the one thing Studio cannot do (docs/INTERFACES.md "C1 contracts" →
-- "Studio bridge"). Ben cannot reach the published pair of places, so a Studio playtest has to
-- be able to walk the whole expedition loop: the hub writes a HANDOFF RECORD to a DataStore and
-- kicks, the Expeditions place reads it on boot, and the trip home writes the summary the same
-- way. Everything else (profile release, registry, retries, failure recovery) runs for real.
--
-- Nothing in this module does anything outside RunService:IsStudio(): every public function
-- returns the "inactive" value immediately, so a live server behaves exactly as it did at C0.
--
-- The record is a HINT, never an entitlement, exactly like teleport data: the combat place
-- re-checks the mission against the loaded profile, and every field is type-checked on read.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local DataService = require(script.Parent:WaitForChild("DataService"))

-- Infrastructure retry policy, like DataService's: three attempts, 1 s / 2 s / 4 s backoff.
local RETRY_ATTEMPTS = 3
local RETRY_BASE_SECONDS = 1
-- Same key shape as the profile store so a handoff is trivially matched to its profile by eye
-- in the DataStore editor during a playtest.
local KEY_PREFIX = "p_"
-- Long enough for the ActionResult to reach the client and its toast to be read, short enough
-- that the player does not wonder whether the button worked.
local KICK_DELAY_SECONDS = 1

export type TeleportHint = {
	missionId: string,
	overdrive: boolean,
	hostUserId: number,
	accessCode: string?,
}
export type HandoffKind = "depart" | "join"

local isStudio = RunService:IsStudio()
-- Typed `any` on purpose (like ExpeditionService's MemoryStore handles): the DataStore is only
-- ever reached through the pcall'd closures below, and `any` keeps the narrowing out of them.
local handoffStore: any = nil
local handoffStoreName: string? = nil
local warnedMock = false

local function debugConfig(): Types.CombatDebugConfig?
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil then
		return nil
	end
	return combatConfig.debug
end

-- nil = no handoff is possible right now (not Studio, no Combat.json, or ProfileStore is on its
-- in-memory mock because API access is off). Every caller degrades on nil rather than erroring.
local function store(): any?
	if not isStudio then
		return nil
	end
	local config = debugConfig()
	if config == nil then
		return nil
	end
	if DataService.IsMockMode() then
		if not warnedMock then
			warnedMock = true
			warn(
				"[StudioBridge] handoff needs API access"
					.. " (Game Settings → Security → Enable Studio Access to API Services)"
			)
		end
		return nil
	end
	local storeName = config.handoffStoreName
	if handoffStore ~= nil and handoffStoreName == storeName then
		return handoffStore
	end
	local ok, result = pcall(function(): any
		return DataStoreService:GetDataStore(storeName)
	end)
	if not ok then
		warn(`[StudioBridge] GetDataStore({storeName}) failed: {result}`)
		return nil
	end
	handoffStore = result
	handoffStoreName = storeName
	return handoffStore
end

-- Same shape as ExpeditionService.callWithRetry: pcall, log, exponential backoff, and a
-- (false, nil) the caller degrades on rather than an error that kills the calling thread.
local function callWithRetry<T>(description: string, call: () -> T): (boolean, T?)
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, result = pcall(call)
		if ok then
			return true, result
		end
		warn(`[StudioBridge] {description} failed (attempt {attempt}): {result}`)
		if attempt < RETRY_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return false, nil
end

local function keyFor(player: Player): string
	return KEY_PREFIX .. player.UserId
end

local function isPositiveInteger(value: any): boolean
	return typeof(value) == "number" and value == math.floor(value) and value > 0
end

local function removeRecord(player: Player): ()
	local dataStore = store()
	if dataStore == nil then
		return
	end
	callWithRetry(`RemoveAsync {player.UserId}`, function(): boolean
		dataStore:RemoveAsync(keyFor(player))
		return true
	end)
end

local function writeRecord(player: Player, description: string, record: { [string]: any }): boolean
	local dataStore = store()
	if dataStore == nil then
		return false
	end
	local ok = callWithRetry(description, function(): boolean
		dataStore:SetAsync(keyFor(player), record)
		return true
	end)
	return ok
end

-- Returns the raw record, already proved to be a table with a fresh stamp. Anything older than
-- handoffMaxAgeSeconds is dropped AND deleted: a handoff from an aborted session hours ago must
-- never hijack this boot.
local function readRecord(player: Player): any?
	local dataStore = store()
	if dataStore == nil then
		return nil
	end
	local ok, value = callWithRetry(`GetAsync {player.UserId}`, function(): any
		return dataStore:GetAsync(keyFor(player))
	end)
	if not ok or typeof(value) ~= "table" then
		return nil
	end
	local record = value :: any
	local config = debugConfig()
	local maxAge = if config ~= nil then config.handoffMaxAgeSeconds else 0
	-- math.abs so a record stamped in the future (a clock that disagrees) is stale too.
	if typeof(record.stamp) ~= "number" or math.abs(os.time() - record.stamp) > maxAge then
		removeRecord(player)
		return nil
	end
	return record
end

-- Validated exactly like a live TeleportData summary: the transport differs, the trust does not.
-- bestWave/died are read leniently because they arrive with C1's WaveService and an older record
-- (or an older place build) simply does not carry them.
local function readSummary(value: any): Types.RunSummary?
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
	-- Built through `any`: the optional fields are A's (Types.RunSummary gains bestWave/died in
	-- this same milestone), so neither their absence nor their arrival may break this build.
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

local StudioBridge = {}

function StudioBridge.IsActive(): boolean
	return isStudio
end

-- The hub's stand-in for TeleportAsync's teleport data. False means the record could not be
-- written (no API access, no Combat.json, or three failed SetAsync attempts); the caller must
-- then refuse the departure and release nothing.
function StudioBridge.WriteDeparture(player: Player, hint: TeleportHint, kind: HandoffKind): boolean
	if not isStudio then
		return false
	end
	return writeRecord(player, `departure SetAsync {player.UserId}`, {
		kind = kind,
		missionId = hint.missionId,
		overdrive = hint.overdrive,
		hostUserId = hint.hostUserId,
		accessCode = hint.accessCode,
		stamp = os.time(),
	})
end

-- The simulated teleport failure: the player stays in the hub, so the record they would have
-- arrived with must not survive to hijack a later boot.
function StudioBridge.ClearDeparture(player: Player): ()
	if not isStudio then
		return
	end
	removeRecord(player)
end

-- Combat place, on boot. Consumed once (like teleport data, which only exists on the join that
-- carried it), so a rejoin after a failed trip home falls through to the Workspace attributes.
function StudioBridge.ReadArrival(player: Player): TeleportHint?
	if not isStudio then
		return nil
	end
	local record = readRecord(player)
	if record == nil then
		return nil
	end
	if record.kind ~= "depart" and record.kind ~= "join" then
		-- A return record belongs to the hub; leaving it in place is what lets ReadReturn find it.
		return nil
	end
	removeRecord(player)
	if
		typeof(record.missionId) ~= "string"
		or record.missionId == ""
		or not isPositiveInteger(record.hostUserId)
	then
		warn(`[StudioBridge] malformed handoff for {player.Name}; falling back to the attributes`)
		return nil
	end
	return {
		missionId = record.missionId,
		overdrive = record.overdrive == true,
		hostUserId = record.hostUserId,
		accessCode = if typeof(record.accessCode) == "string" then record.accessCode else nil,
	}
end

-- Combat place, on the trip home: the stand-in for TeleportAsync's `{ summary = … }`.
function StudioBridge.WriteReturn(player: Player, summary: Types.RunSummary): boolean
	if not isStudio then
		return false
	end
	return writeRecord(player, `return SetAsync {player.UserId}`, {
		kind = "return",
		summary = summary,
		stamp = os.time(),
	})
end

-- Hub, on join. Presentation only: the rewards are already in the profile the combat place
-- saved, so a missing or malformed record costs the card, never the cash.
function StudioBridge.ReadReturn(player: Player): Types.RunSummary?
	if not isStudio then
		return nil
	end
	local record = readRecord(player)
	if record == nil or record.kind ~= "return" then
		return nil
	end
	removeRecord(player)
	local summary = readSummary(record.summary)
	if summary == nil then
		warn(`[StudioBridge] malformed return record for {player.Name}; no summary card`)
	end
	return summary
end

-- Studio lever (playtest-repro-methods: a failure path needs a lever that really reaches it).
-- Consumed once so the next attempt succeeds without a trip to the Properties pane.
function StudioBridge.TeleportShouldFail(): boolean
	if not isStudio then
		return false
	end
	local config = debugConfig()
	if config == nil then
		return false
	end
	local attribute = config.forceTeleportFailureAttribute
	if workspace:GetAttribute(attribute) ~= true then
		return false
	end
	workspace:SetAttribute(attribute, false)
	return true
end

-- Sticky, unlike the teleport lever: a registry outage is a condition to play under (every call
-- retries and warns and the run continues), not a single event to reproduce.
function StudioBridge.RegistryShouldFail(): boolean
	if not isStudio then
		return false
	end
	local config = debugConfig()
	if config == nil then
		return false
	end
	return workspace:GetAttribute(config.forceRegistryFailureAttribute) == true
end

-- The Studio stand-in for leaving the server. Delayed so the ActionResult (and its toast) lands
-- first; the message is repeated in the kick dialog because that is what the tester reads next.
function StudioBridge.Depart(player: Player, message: string): ()
	if not isStudio then
		return
	end
	warn(`[StudioBridge] {player.Name}: {message}`)
	task.delay(KICK_DELAY_SECONDS, function()
		if player:IsDescendantOf(Players) then
			player:Kick(message)
		end
	end)
end

return StudioBridge
