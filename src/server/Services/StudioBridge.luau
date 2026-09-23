--!strict
-- The Studio stand-in for the one thing Studio cannot do (docs/INTERFACES.md "C1 contracts" →
-- "Studio bridge"). Ben cannot reach the published pair of places, so a Studio playtest has to
-- be able to walk the whole expedition loop: the hub writes a HANDOFF RECORD to a DataStore and
-- kicks, the Expeditions place reads it on boot, and the trip home writes the ReturnData the same
-- way. Everything else (profile release, registry, retries, failure recovery) runs for real.
--
-- Nothing in this module does anything outside RunService:IsStudio(): every public function
-- returns the "inactive" value immediately, so a live server behaves exactly as it did at C0.
-- The one exception is ParseReturnData, a pure validator the hub also runs on live teleport data.
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

-- Studio only, so negative ids are legal: Local Server test players have them (C2 co-op tests
-- run two of them). Zero, fractions and ±inf are still malformed.
local function isUserId(value: any): boolean
	return typeof(value) == "number"
		and value == math.floor(value)
		and value ~= 0
		and math.abs(value) < 2 ^ 53
end

-- The same rule for data that may come from a live teleport, where only a real account id is
-- legal and a negative one can only be forged.
local function isLiveUserId(value: any): boolean
	return isUserId(value) and (value > 0 or isStudio)
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

local function numberOr(value: any, fallback: number): number
	if typeof(value) == "number" and value == value then
		return value
	end
	return fallback
end

-- Validated exactly like a live TeleportData summary: the transport differs, the trust does not.
-- The fields a newer combat build adds (bestWave/died at C1, mentorValor/damageShare at C2) are
-- read leniently, so an older place build only costs the line it does not send.
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
	local summary: Types.RunSummary = {
		missionId = raw.missionId,
		overdrive = raw.overdrive,
		wavesCleared = raw.wavesCleared,
		cash = raw.cash,
		materials = materials,
		valor = raw.valor,
		kills = raw.kills,
		seconds = raw.seconds,
		bestWave = numberOr(raw.bestWave, 0),
		died = raw.died == true,
		mentorValor = numberOr(raw.mentorValor, 0),
		damageShare = numberOr(raw.damageShare, 0),
	}
	return summary
end

local function maxParty(): number
	local combatConfig = Catalog.GetCombatConfig()
	return if combatConfig ~= nil then combatConfig.coop.maxParty else 1
end

local function readPartyHint(value: any): Types.PartyHint?
	if typeof(value) ~= "table" then
		return nil
	end
	local raw = value :: any
	if not isLiveUserId(raw.leaderUserId) or typeof(raw.memberIds) ~= "table" then
		return nil
	end
	local memberIds: { number } = {}
	for _, userId in raw.memberIds :: { any } do
		if not isLiveUserId(userId) or #memberIds >= maxParty() then
			return nil
		end
		table.insert(memberIds, userId)
	end
	return { leaderUserId = raw.leaderUserId, memberIds = memberIds }
end

-- A summary for a player the ReturnData names is copied only when its key is a userId string;
-- anything past a full party's worth of keys is ignored rather than walked.
local function readSummaries(value: any): { [string]: Types.RunSummary }?
	if typeof(value) ~= "table" then
		return nil
	end
	local summaries: { [string]: Types.RunSummary } = {}
	local count = 0
	for key, entry in value :: { [any]: any } do
		if count >= maxParty() then
			break
		end
		if typeof(key) == "string" and isLiveUserId(tonumber(key)) then
			local summary = readSummary(entry)
			if summary ~= nil then
				summaries[key] = summary
				count += 1
			end
		end
	end
	return summaries
end

local StudioBridge = {}

function StudioBridge.IsActive(): boolean
	return isStudio
end

-- The one validator for a ReturnData, whichever transport carried it: the hub runs it on live
-- TeleportData too, so it is the single exception to "does nothing outside Studio" — it is pure
-- and touches no DataStore. nil = malformed; every field is copied, never aliased.
function StudioBridge.ParseReturnData(value: any): Types.ReturnData?
	if typeof(value) ~= "table" then
		return nil
	end
	local raw = value :: any
	local summaries = readSummaries(raw.summaries)
	if summaries == nil then
		return nil
	end
	local refused = raw.refused
	if refused ~= nil and refused ~= "full" and refused ~= "over" and refused ~= "locked" then
		return nil
	end
	local party: Types.PartyHint? = nil
	if raw.party ~= nil then
		party = readPartyHint(raw.party)
		if party == nil then
			return nil
		end
	end
	return { summaries = summaries, party = party, refused = refused }
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
		or not isUserId(record.hostUserId)
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

-- Combat place, on the trip home: the stand-in for TeleportAsync's ReturnData (C2: summaries for
-- every member, the party hint, or a refusal).
function StudioBridge.WriteReturn(player: Player, data: Types.ReturnData): boolean
	if not isStudio then
		return false
	end
	return writeRecord(player, `return SetAsync {player.UserId}`, {
		kind = "return",
		data = data,
		stamp = os.time(),
	})
end

-- Hub, on join. Presentation and re-form hints only: the rewards are already in the profile the
-- combat place saved, so a missing or malformed record costs the card, never the cash.
function StudioBridge.ReadReturn(player: Player): Types.ReturnData?
	if not isStudio then
		return nil
	end
	local record = readRecord(player)
	if record == nil or record.kind ~= "return" then
		return nil
	end
	removeRecord(player)
	local data = StudioBridge.ParseReturnData(record.data)
	if data == nil then
		warn(`[StudioBridge] malformed return record for {player.Name}; ignored`)
	end
	return data
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
