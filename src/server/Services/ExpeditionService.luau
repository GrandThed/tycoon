--!strict
-- The hub side of the expedition handoff (docs/INTERFACES.md "C0 contracts" → "Expedition
-- handoff", "C2 contracts" → "Departure, join and the run list"). One profile, two places: the
-- hub RELEASES the ProfileStore session before it teleports, so the Expeditions place can load
-- the same key without ever passing Steal.
--
-- Teardown order is Main's, not ours: Main hands in its own `release` (PlotService.Release →
-- EconomyService.Cleanup → DataService.Release) and `rejoin` (the join sequence) as hooks, which
-- is also what keeps this module out of a require cycle with PlotService/Monetization.
--
-- Because the profile is already gone by the time a teleport can fail, EVERY failure path has to
-- put the player back together: clear the in-flight guard, re-run the join sequence, hand back
-- the departure stat, and tell the client. There are two such paths, and only one of them is a
-- thrown call (see TeleportInitFailed in Init). C2 departs a whole party at once, so both paths
-- recover every member.
--
-- C1: in Studio the teleport is replaced by StudioBridge's handoff record and a kick
-- (docs/INTERFACES.md "C1 contracts" → "Studio bridge"). Everything else — reservation-free
-- access code, stamp, release, failure recovery — is the live path, so a Studio playtest
-- exercises the same code Ben cannot reach on the published pair.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Combat = require(sharedFolder:WaitForChild("Combat"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local PartyService = require(script.Parent:WaitForChild("PartyService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))
local StudioBridge = require(script.Parent:WaitForChild("StudioBridge"))

-- Infrastructure retry policy, like DataService's: three attempts with 1 s / 2 s / 4 s backoff
-- around each Teleport/MemoryStore call. Not balance, so not in Config/*.json.
local RETRY_ATTEMPTS = 3
local RETRY_BASE_SECONDS = 1
-- Contract: one GetRangeAsync(Ascending, 50) per hub server per listCacheSeconds. The combat
-- place sorts joinable runs first, so one page is the joinable set.
local REGISTRY_PAGE_SIZE = 50
-- The run tickets live in their own SERVER-ONLY hash map beside the run registry: an access code
-- is a key to a private server, so it never travels in teleport data (the teleporting client can
-- read that) and never reaches a client in the RunList.
local CODES_MAP_SUFFIX = "Codes"
local CODES_KEY_PREFIX = "code_"
-- C1 Studio bridge: there is no reserved server to teleport into, so the handoff record and the
-- ticket carry a marker instead of a real access code and private server id.
local STUDIO_ACCESS_CODE = "studio"
-- Studio-only stand-ins for other people's runs (the DebugFakeRuns attribute and the `fakeRuns`
-- lever). They live in this module rather than in the MemoryStore registry because nothing
-- outside this server may ever see them, and a run nobody hosts must never be advertised live.
local FAKE_ACCESS_CODE = "fake"
local FAKE_MISSION_ID = "village"
-- The join list shows a handful of runs; more fakes would only push the real ones off it.
local MAX_FAKE_RUNS = 8
local BRIDGE_DEPART_MESSAGE = "Handoff saved — Stop Play, then open build/combat.rbxl"

local RELATION_RANK: { [Types.RunRelation]: number } = { server = 1, friend = 2, public = 3 }

export type Hooks = {
	-- Main's PlayerRemoving teardown, run before the teleport so the profile is free.
	release: (player: Player) -> (),
	-- Main's join sequence. Called synchronously (it yields until the profile is back) so a
	-- failed handoff can undo the departure stamp on the profile the reload produced.
	rejoin: (player: Player) -> (),
}

type Action = "expedition" | "joinRun"
type Reason =
	"insufficientFunds"
	| "locked"
	| "invalid"
	| "unavailable"
	| "full"
	| "over"
	| "busy"
	| "notLeader"
-- What an in-flight departure needs to answer the client if it fails asynchronously. One table
-- is shared by every member of a party departure.
type Departure = { action: Action, slotId: string }
type Handoff = {
	departure: Departure,
	missionId: string,
	overdrive: boolean,
	hostUserId: number,
	accessCode: string,
	kind: StudioBridge.HandoffKind,
}
type ListCache = { runs: { Types.ActiveRun }, fetchedAt: number }
type FriendBudget = { remaining: number }

local hooks: Hooks? = nil
local isStudio = RunService:IsStudio()
-- Present exactly while a teleport is in flight for that player. Also the guard that stops the
-- prompt bucket from admitting a second Depart/Join while the first one yields.
local departing: { [Player]: Departure } = {}
-- Friend verdicts for this session, per requesting player, so a refresh loop does not re-ask
-- Roblox about the same hosts. Cleared in Forget.
local friendVerdicts: { [Player]: { [number]: boolean } } = {}
-- userId → os.clock() expiry for everyone who left this server for a run. Such a run is "in
-- this server" for the list: its members are gone from Players by the time anyone looks.
local departedFromHere: { [number]: number } = {}
-- Studio fake runs and the moment they expire, so the lever behaves like the registry's TTL.
local fakeRuns: { Types.ActiveRun } = {}
local fakeRunsExpireAt = 0
-- The server-wide registry page, shared by every requester for listCacheSeconds; requesters
-- arriving while it is being fetched wait for that fetch instead of starting their own.
local listCache: ListCache? = nil
local listFetching = false
local listWaiters: { thread } = {}

local function sendResult(
	player: Player,
	action: Action,
	slotId: string,
	ok: boolean,
	reason: Reason?
): ()
	local result: Types.ActionResult =
		{ action = action, slotId = slotId, ok = ok, reason = reason }
	RemoteService.FireClient(player, "ActionResult", result)
end

-- Same shape as MonetizationService.callWithRetry: pcall, log, exponential backoff, and a
-- (false, nil) the caller degrades on rather than an error that would kill the intent thread.
local function callWithRetry<T>(description: string, call: () -> T): (boolean, T?)
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, result = pcall(call)
		if ok then
			return true, result
		end
		warn(`[ExpeditionService] {description} failed (attempt {attempt}): {result}`)
		if attempt < RETRY_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return false, nil
end

-- Whether MemoryStore is reachable at all. C1: Studio is no longer excluded — with API access
-- on, a Studio session talks to the real registry exactly as a live server does; only
-- ProfileStore's in-memory mock, i.e. no API access, still disables it. Checked per call:
-- ProfileStore probes access asynchronously after require, so a boot-time verdict would be wrong.
local function registryUnavailable(): boolean
	return isStudio and DataService.IsMockMode()
end

-- Read-only view of the combat place's run registry. The hub never writes it: the place that
-- owns a run owns its entry, so a hub bug can never advertise a run that does not exist.
local function registryMap(): any?
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil or registryUnavailable() then
		return nil
	end
	local mapName = combatConfig.registry.mapName
	local ok, map = pcall(function(): any
		return MemoryStoreService:GetSortedMap(mapName)
	end)
	if not ok then
		warn(`[ExpeditionService] GetSortedMap failed: {map}`)
		return nil
	end
	return map
end

local function codesMap(combatConfig: Types.CombatConfig): any?
	if registryUnavailable() then
		return nil
	end
	local mapName = combatConfig.registry.mapName .. CODES_MAP_SUFFIX
	local ok, map = pcall(function(): any
		return MemoryStoreService:GetHashMap(mapName)
	end)
	if not ok then
		warn(`[ExpeditionService] GetHashMap failed: {map}`)
		return nil
	end
	return map
end

-- Hands the reservation to the combat server that is about to boot: it cannot read its own
-- access code from any API, and the ticket is also what host-gates the mission for guests and
-- tells the lobby whom to wait for. A failure here is treated exactly like a failed reservation.
local function writeTicket(
	combatConfig: Types.CombatConfig,
	hostUserId: number,
	ticket: Types.RunTicket
): boolean
	local map = codesMap(combatConfig)
	if map == nil then
		return false
	end
	local key = CODES_KEY_PREFIX .. hostUserId
	local ttl = combatConfig.registry.ttlSeconds
	local ok = callWithRetry(`ticket SetAsync {hostUserId}`, function(): boolean
		map:SetAsync(key, ticket, ttl)
		return true
	end)
	return ok
end

-- A registry value is written by another server, so every field the join path compares is
-- type-checked before it is used; anything malformed reads as "no such run". public/memberIds
-- are C2 fields, read leniently (private, nobody) so an older combat build cannot hide its runs
-- from friends.
local function asActiveRun(value: any): Types.ActiveRun?
	if typeof(value) ~= "table" then
		return nil
	end
	local run = value :: any
	if
		typeof(run.hostUserId) ~= "number"
		or typeof(run.hostName) ~= "string"
		or typeof(run.missionId) ~= "string"
		or typeof(run.era) ~= "number"
		or typeof(run.wave) ~= "number"
		or typeof(run.overdrive) ~= "boolean"
		or typeof(run.partySize) ~= "number"
		or typeof(run.accessCode) ~= "string"
		or run.accessCode == ""
	then
		return nil
	end
	local memberIds: { number } = {}
	if typeof(run.memberIds) == "table" then
		for _, userId in run.memberIds :: { any } do
			if typeof(userId) == "number" then
				table.insert(memberIds, userId)
			end
		end
	end
	return {
		hostUserId = run.hostUserId,
		hostName = run.hostName,
		missionId = run.missionId,
		era = run.era,
		wave = run.wave,
		overdrive = run.overdrive,
		partySize = run.partySize,
		accessCode = run.accessCode,
		public = run.public == true,
		memberIds = memberIds,
	}
end

-- Empty outside Studio and after the lever's TTL, so no other code path needs to know fakes
-- exist.
local function activeFakeRuns(): { Types.ActiveRun }
	if not isStudio or os.clock() >= fakeRunsExpireAt then
		return {}
	end
	return fakeRuns
end

local function readRegistryEntry(hostUserId: number): Types.ActiveRun?
	for _, run in activeFakeRuns() do
		if run.hostUserId == hostUserId then
			return run
		end
	end
	local map = registryMap()
	if map == nil then
		return nil
	end
	local ok, value = callWithRetry(`registry GetAsync {hostUserId}`, function(): any
		return map:GetAsync(tostring(hostUserId))
	end)
	if not ok then
		return nil
	end
	return asActiveRun(value)
end

local function readRegistryRuns(): { Types.ActiveRun }
	local runs: { Types.ActiveRun } = {}
	local map = registryMap()
	if map == nil then
		return runs
	end
	local ok, items = callWithRetry("registry GetRangeAsync", function(): any
		return map:GetRangeAsync(Enum.SortDirection.Ascending, REGISTRY_PAGE_SIZE)
	end)
	if not ok or typeof(items) ~= "table" then
		return runs
	end
	for _, item in items :: { any } do
		local run = if typeof(item) == "table" then asActiveRun(item.value) else nil
		if run ~= nil then
			table.insert(runs, run)
		end
	end
	return runs
end

-- One registry read per listCacheSeconds for the whole server (contract), however many panels
-- are open. Yields for the fetcher and for everyone waiting on it.
local function cachedRegistryRuns(combatConfig: Types.CombatConfig): { Types.ActiveRun }
	local cache = listCache
	if cache ~= nil and os.clock() - cache.fetchedAt < combatConfig.registry.listCacheSeconds then
		return cache.runs
	end
	if listFetching then
		table.insert(listWaiters, coroutine.running())
		return coroutine.yield() :: { Types.ActiveRun }
	end
	listFetching = true
	local runs = readRegistryRuns()
	listCache = { runs = runs, fetchedAt = os.clock() }
	listFetching = false
	local waiters = listWaiters
	listWaiters = {}
	for _, waiter in waiters do
		task.spawn(waiter, runs)
	end
	return runs
end

-- Cached per requester. nil = unknown: the budget ran out or the web call failed (a failure is
-- not cached, so the next refresh asks again). Negative ids are Studio test players and fakes,
-- which have no friends list to ask about.
local function friendVerdict(player: Player, userId: number, budget: FriendBudget?): boolean?
	if userId <= 0 then
		return false
	end
	local verdicts = friendVerdicts[player]
	if verdicts == nil then
		verdicts = {}
		friendVerdicts[player] = verdicts
	end
	local known = verdicts[userId]
	if known ~= nil then
		return known
	end
	if budget ~= nil then
		if budget.remaining <= 0 then
			return nil
		end
		budget.remaining -= 1
	end
	local ok, result = pcall(function(): boolean
		return player:IsFriendsWithAsync(userId)
	end)
	if not ok then
		warn(`[ExpeditionService] IsFriendsWithAsync({userId}) failed: {result}`)
		return nil
	end
	local verdict = result == true
	verdicts[userId] = verdict
	return verdict
end

local function isHereOrDepartedFromHere(userId: number): boolean
	if Players:GetPlayerByUserId(userId) ~= nil then
		return true
	end
	local expiresAt = departedFromHere[userId]
	return expiresAt ~= nil and os.clock() < expiresAt
end

local function hasLocalMember(run: Types.ActiveRun): boolean
	if isHereOrDepartedFromHere(run.hostUserId) then
		return true
	end
	for _, userId in run.memberIds do
		if isHereOrDepartedFromHere(userId) then
			return true
		end
	end
	return false
end

local function isJoinable(run: Types.ActiveRun, coop: Types.CombatCoopConfig): boolean
	return run.partySize < coop.maxParty and run.wave <= coop.joinUntilWave
end

-- Every way a handoff can fail after the session was released. Clears the guard, tells the
-- client, puts the player back in the hub, and gives back the departure stat.
local function abortDeparture(player: Player, departure: Departure): ()
	departing[player] = nil
	sendResult(player, departure.action, departure.slotId, false, "unavailable")
	local serviceHooks = hooks
	if serviceHooks == nil or not player:IsDescendantOf(Players) then
		return
	end
	-- Synchronous on purpose: the hook yields until the profile is loaded again, which is what
	-- makes the rollback below deterministic instead of a race against the reload.
	serviceHooks.rejoin(player)
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	-- The departure had to be counted BEFORE the release (that is the last moment it could be
	-- saved), so a failed handoff hands it back on the reloaded profile. The away window needs
	-- no undoing: ApplyOfflineGrant zeroed it during the rejoin.
	local stats = state.combat.stats
	stats.expeditions = math.max(0, stats.expeditions - 1)
	EconomyService.MarkDirty(player, { combat = true })
end

-- Stamped before the release so the away window is already in the final save: the offline grant
-- on return reads expeditionSeconds, and the combat place keeps adding to it.
local function stampDeparture(state: Types.PlayerState): ()
	state.combat.expeditionSince = os.time()
	state.combat.expeditionSeconds = 0
	state.combat.stats.expeditions += 1
end

-- The one failure that happens BEFORE the release (a handoff record that cannot be written), so
-- the stamp is undone on the live profile rather than handed back on a reloaded one.
local function unstampDeparture(player: Player): ()
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	state.combat.expeditionSince = 0
	state.combat.expeditionSeconds = 0
	state.combat.stats.expeditions = math.max(0, state.combat.stats.expeditions - 1)
	EconomyService.MarkDirty(player, { combat = true })
end

-- Refusal before anything was stamped or released: drop every claim and tell everyone.
local function refuseAll(group: { Player }, departure: Departure, reason: Reason): ()
	for _, member in group do
		departing[member] = nil
		sendResult(member, departure.action, departure.slotId, false, reason)
	end
end

-- Members who left or lost their profile during a yield drop out of the group (their claim
-- with them). The first entry is the anchor (the leader, or the joiner): without it there is
-- no departure, and `anchored` is false.
local function pruneGroup(group: { Player }): ({ Player }, boolean)
	local kept: { Player } = {}
	for _, member in group do
		if member:IsDescendantOf(Players) and DataService.GetState(member) ~= nil then
			table.insert(kept, member)
		else
			departing[member] = nil
		end
	end
	return kept, #group > 0 and kept[1] == group[1]
end

-- The anchor dropped out mid-departure: nobody goes, and whoever is still here is told.
local function abandon(group: { Player }, departure: Departure): ()
	for _, member in group do
		departing[member] = nil
		if member:IsDescendantOf(Players) then
			sendResult(member, departure.action, departure.slotId, false, "unavailable")
		end
	end
end

-- The shared tail of Depart and Join: stamp, release, then one teleport (or, in Studio, one
-- handoff record and kick per member). Every member must already hold a claim in `departing`.
local function handOff(group: { Player }, handoff: Handoff): ()
	local departure = handoff.departure
	local places = Catalog.GetPlacesConfig()
	local combatConfig = Catalog.GetCombatConfig()
	local serviceHooks = hooks
	local members, anchored = pruneGroup(group)
	if not anchored or serviceHooks == nil or combatConfig == nil then
		abandon(group, departure)
		return
	end

	for _, member in members do
		local state = DataService.GetState(member)
		if state ~= nil then
			stampDeparture(state)
			EconomyService.RefreshPersistedRate(member)
		end
	end
	local departedUntil = os.clock() + combatConfig.registry.ttlSeconds

	if StudioBridge.IsActive() then
		local hint: StudioBridge.TeleportHint = {
			missionId = handoff.missionId,
			overdrive = handoff.overdrive,
			hostUserId = handoff.hostUserId,
			accessCode = handoff.accessCode,
		}
		local written: { Player } = {}
		for index, member in members do
			if StudioBridge.WriteDeparture(member, hint, handoff.kind) then
				table.insert(written, member)
				continue
			end
			-- Nothing has been released yet, so a member whose record failed simply stays with
			-- the profile they already had. Without the anchor's record nobody goes.
			if index == 1 then
				for _, other in members do
					unstampDeparture(other)
				end
				for _, other in written do
					StudioBridge.ClearDeparture(other)
				end
				refuseAll(members, departure, "unavailable")
				return
			end
			unstampDeparture(member)
			departing[member] = nil
			sendResult(member, departure.action, departure.slotId, false, "unavailable")
		end
		for _, member in written do
			sendResult(member, departure.action, departure.slotId, true, nil)
			serviceHooks.release(member)
		end
		if StudioBridge.TeleportShouldFail() then
			-- The lever reproduces TeleportInitFailed, so it runs that handler's recovery for
			-- every member, not a Studio-only imitation of it. Each record goes first: the
			-- arrival it describes is never going to happen.
			for _, member in written do
				task.spawn(function()
					StudioBridge.ClearDeparture(member)
					abortDeparture(member, departure)
				end)
			end
			return
		end
		for _, member in written do
			departedFromHere[member.UserId] = departedUntil
			StudioBridge.Depart(member, BRIDGE_DEPART_MESSAGE)
		end
		return
	end

	-- Frozen teardown order, then the handoff. Sessions must be released BEFORE the teleport or
	-- the combat place would find the keys locked and drop the players into safe mode.
	for _, member in members do
		sendResult(member, departure.action, departure.slotId, true, nil)
		serviceHooks.release(member)
	end
	local travellers: { Player } = {}
	for _, member in members do
		if member:IsDescendantOf(Players) then
			table.insert(travellers, member)
		else
			departing[member] = nil
		end
	end
	if #travellers == 0 then
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = handoff.accessCode
	options:SetTeleportData({
		missionId = handoff.missionId,
		overdrive = handoff.overdrive,
		hostUserId = handoff.hostUserId,
	})
	-- ONE call for the whole party, so the platform lands them in the same server together.
	local teleported = callWithRetry(`TeleportAsync {handoff.missionId}`, function(): boolean
		TeleportService:TeleportAsync(places.combatPlaceId, travellers, options)
		return true
	end)
	if not teleported then
		-- Only ARGUMENT errors throw here; a runtime refusal arrives later on
		-- TeleportInitFailed (see Init). Each rejoin yields, so they run side by side.
		for _, member in travellers do
			task.spawn(abortDeparture, member, departure)
		end
		return
	end
	for _, member in travellers do
		departedFromHere[member.UserId] = departedUntil
	end
end

-- The departing group for a leader: the leader first, then every party member who can go.
-- Returns whether a REAL member stays behind (still loading, already departing, or no seat);
-- each such member present is told `busy` too. Studio fakes are skipped with a warn only,
-- since the client has no copy for them.
local function departingGroup(
	leader: Player,
	missionId: string,
	coop: Types.CombatCoopConfig
): ({ Player }, boolean)
	local group: { Player } = { leader }
	local party = PartyService.Get(leader)
	if party == nil then
		return group, false
	end
	local present: { [number]: Player } = {}
	for _, member in PartyService.Members(leader) do
		present[member.UserId] = member
	end
	local leftBehind = false
	for _, entry in party.members do
		if entry.userId == leader.UserId then
			continue
		end
		if PartyService.IsFake(leader, entry.userId) then
			warn(`[ExpeditionService] Studio fake party member {entry.name} stays in the hub`)
			continue
		end
		local member: Player? = present[entry.userId]
		if
			member == nil
			or departing[member] ~= nil
			or DataService.GetState(member) == nil
			or #group >= coop.maxParty
		then
			leftBehind = true
			-- An already-departing member is mid-teleport on their own run; only the ones who
			-- simply could not come are told.
			if member ~= nil and departing[member] == nil then
				sendResult(member, "expedition", missionId, false, "busy")
			end
			continue
		end
		table.insert(group, member)
	end
	return group, leftBehind
end

-- Depart fixes the group before its yields (reservation, ticket); anyone who left the party
-- meanwhile (Leave, a kick) stays behind and gives up their claim. The leader is always kept.
local function keepPartyMembers(leader: Player, group: { Player }): { Player }
	local current: { [Player]: boolean } = {}
	for _, member in PartyService.Members(leader) do
		current[member] = true
	end
	local kept: { Player } = {}
	for _, member in group do
		if member == leader or current[member] then
			table.insert(kept, member)
		else
			departing[member] = nil
		end
	end
	return kept
end

local ExpeditionService = {}

-- RequestExpedition. Yields (reservation + ticket + teleport), so it runs on its own thread.
function ExpeditionService.Depart(
	player: Player,
	missionId: string,
	overdrive: boolean,
	public: boolean
): ()
	if departing[player] ~= nil then
		-- The prompt bucket admits a second tap while the first teleport is still in flight;
		-- a dropped tap is far better than a second reservation and a second departure stat.
		return
	end
	local state = DataService.GetState(player)
	if state == nil then
		-- Safe mode: no profile to stamp and nothing to release.
		return
	end
	Combat.TouchHighestEra(state)

	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil then
		-- No Combat.json: the whole feature is hidden, so this is a stale or forged intent.
		sendResult(player, "expedition", missionId, false, "unavailable")
		return
	end
	if not PartyService.IsLeader(player) then
		sendResult(player, "expedition", missionId, false, "notLeader")
		return
	end
	-- Host-gated (C2 ruling 4): the LEADER's unlocks decide; guests are never checked here, and
	-- the combat place trusts the ticket below, never the teleport data, for that.
	local mission = Catalog.GetMissionById(missionId)
	if mission == nil or not Combat.MissionUnlocked(state, mission, overdrive, combatConfig) then
		sendResult(player, "expedition", missionId, false, "locked")
		return
	end
	local places = Catalog.GetPlacesConfig()
	if places.combatPlaceId == 0 or hooks == nil then
		sendResult(player, "expedition", missionId, false, "unavailable")
		return
	end

	-- Nothing above yields, so the checks and the claims below cannot interleave.
	local departure: Departure = { action = "expedition", slotId = missionId }
	local group, leftBehind = departingGroup(player, missionId, combatConfig.coop)
	for _, member in group do
		departing[member] = departure
	end
	if leftBehind then
		-- The client reads `busy` on "expedition" as "some members were left behind"; the
		-- departure itself carries on and answers ok on its own.
		sendResult(player, "expedition", missionId, false, "busy")
	end

	local bridged = StudioBridge.IsActive()
	local accessCode = STUDIO_ACCESS_CODE
	local privateServerId = STUDIO_ACCESS_CODE
	if not bridged then
		local ok, reserved = callWithRetry("ReserveServer", function(): { string }
			local code, serverId = TeleportService:ReserveServer(places.combatPlaceId)
			return { code, serverId }
		end)
		if not ok or reserved == nil or typeof(reserved[1]) ~= "string" or reserved[1] == "" then
			refuseAll(group, departure, "unavailable")
			return
		end
		accessCode = reserved[1]
		privateServerId = if typeof(reserved[2]) == "string" then reserved[2] else ""
	end

	group = keepPartyMembers(player, group)
	local members, anchored = pruneGroup(group)
	if not anchored then
		abandon(group, departure)
		return
	end
	local expected: { number } = {}
	for _, member in members do
		table.insert(expected, member.UserId)
	end
	local ticket: Types.RunTicket = {
		accessCode = accessCode,
		privateServerId = privateServerId,
		missionId = missionId,
		overdrive = overdrive,
		public = public,
		expected = expected,
	}
	-- In Studio a missing ticket only costs the host gate (the combat place then unlock-checks
	-- every arrival, the C1 rule), and the handoff record still carries the run; live, a run
	-- without its ticket could never be joined or host-gated, so it is not started at all.
	if not writeTicket(combatConfig, player.UserId, ticket) and not bridged then
		refuseAll(members, departure, "unavailable")
		return
	end

	-- The ticket write yielded too; the ticket's expected list may name someone who then left,
	-- which only makes the lobby wait lobbyWaitSeconds for them.
	handOff(keepPartyMembers(player, members), {
		departure = departure,
		missionId = missionId,
		overdrive = overdrive,
		hostUserId = player.UserId,
		accessCode = accessCode,
		kind = "depart",
	})
end

-- RequestJoinRun. Personal: the requester leaves their hub party and goes alone. No unlock check
-- (host-gated); the combat place re-checks seats, wave and ticket on arrival.
function ExpeditionService.Join(player: Player, hostUserId: number): ()
	local slotId = tostring(hostUserId)
	if departing[player] ~= nil then
		return
	end
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	Combat.TouchHighestEra(state)

	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil then
		sendResult(player, "joinRun", slotId, false, "unavailable")
		return
	end
	-- Yields (MemoryStore), which is why the guard is claimed after it rather than before.
	local entry = readRegistryEntry(hostUserId)
	if entry == nil or entry.accessCode == FAKE_ACCESS_CODE then
		-- Gone or malformed; a Studio fake has no server behind it and answers exactly what a
		-- vanished run answers.
		sendResult(player, "joinRun", slotId, false, "unavailable")
		return
	end
	local coop = combatConfig.coop
	if entry.partySize >= coop.maxParty then
		sendResult(player, "joinRun", slotId, false, "full")
		return
	end
	if entry.wave > coop.joinUntilWave then
		sendResult(player, "joinRun", slotId, false, "over")
		return
	end
	-- The same visibility the list applies, so a client cannot join a friends-only run by
	-- guessing a host id. The friend check is uncapped here: it is one call on the prompt bucket.
	local visible = entry.public
		or hasLocalMember(entry)
		or friendVerdict(player, entry.hostUserId, nil) == true
	if not visible then
		sendResult(player, "joinRun", slotId, false, "unavailable")
		return
	end
	local places = Catalog.GetPlacesConfig()
	if places.combatPlaceId == 0 or hooks == nil then
		sendResult(player, "joinRun", slotId, false, "unavailable")
		return
	end
	if departing[player] ~= nil or DataService.GetState(player) == nil then
		-- A second tap could have claimed the guard (or the player left) while the reads yielded.
		return
	end

	local departure: Departure = { action = "joinRun", slotId = slotId }
	departing[player] = departure
	PartyService.Leave(player)
	handOff({ player }, {
		departure = departure,
		missionId = entry.missionId,
		overdrive = entry.overdrive,
		hostUserId = entry.hostUserId,
		accessCode = entry.accessCode,
		kind = "join",
	})
end

-- RequestRunList. Yields (MemoryStore + friend checks), so it runs on the remote's own thread.
function ExpeditionService.SendRunList(player: Player): ()
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil then
		RemoteService.FireClient(player, "RunList", { runs = {} })
		return
	end
	local coop = combatConfig.coop
	local runs = table.clone(cachedRegistryRuns(combatConfig))
	for _, run in activeFakeRuns() do
		table.insert(runs, run)
	end

	type Row = { entry: Types.RunListEntry, rank: number }
	local rows: { Row } = {}
	local budget: FriendBudget = { remaining = combatConfig.registry.friendChecksPerCall }
	for _, run in runs do
		if run.hostUserId == player.UserId or table.find(run.memberIds, player.UserId) ~= nil then
			continue
		end
		if not isJoinable(run, coop) then
			continue
		end
		local relation: Types.RunRelation
		if run.accessCode == FAKE_ACCESS_CODE then
			-- Studio fakes have no account behind them; they alternate so both groups show.
			relation = if run.public then "public" else "friend"
		elseif hasLocalMember(run) then
			relation = "server"
		else
			local verdict = friendVerdict(player, run.hostUserId, budget)
			if verdict == true then
				relation = "friend"
			elseif run.public then
				relation = "public"
			else
				-- Friends-only and not (yet) known to be a friend: hidden. An unchecked host
				-- resolves on a later refresh once the verdict cache has room.
				continue
			end
		end
		-- The access code never leaves the server: with it, any client could teleport itself
		-- into a reserved server.
		table.insert(rows, {
			rank = RELATION_RANK[relation],
			entry = {
				hostUserId = run.hostUserId,
				hostName = run.hostName,
				missionId = run.missionId,
				wave = run.wave,
				overdrive = run.overdrive,
				partySize = run.partySize,
				relation = relation,
			},
		})
	end
	table.sort(rows, function(a: Row, b: Row): boolean
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		if a.entry.wave ~= b.entry.wave then
			return a.entry.wave < b.entry.wave
		end
		return a.entry.hostUserId < b.entry.hostUserId
	end)
	local visible: { Types.RunListEntry } = {}
	for index = 1, math.min(#rows, combatConfig.registry.listMax) do
		table.insert(visible, rows[index].entry)
	end
	RemoteService.FireClient(player, "RunList", { runs = visible })
end

-- Studio lever (the DebugFakeRuns attribute and the RequestDebug `fakeRuns` button): fills the
-- join list with runs that exist only in this server's memory, so the ACTIVE RUNS panel and its
-- refusal path can be seen without a second published place. A no-op everywhere else, and the
-- entries expire on the registry's own TTL so a forgotten lever does not outlive the session.
function ExpeditionService.PublishFakeRuns(count: number): ()
	if not isStudio then
		return
	end
	local combatConfig = Catalog.GetCombatConfig()
	-- count ~= count rejects NaN: a lever typed into the Properties pane can be anything.
	if combatConfig == nil or count ~= count then
		return
	end
	local wanted = math.clamp(math.floor(count), 0, MAX_FAKE_RUNS)
	local mission = Catalog.GetMissionById(FAKE_MISSION_ID)
	fakeRuns = {}
	fakeRunsExpireAt = os.clock() + combatConfig.registry.ttlSeconds
	for index = 1, wanted do
		-- Negative host ids: no real account can collide with them, and Join recognises the
		-- "fake" access code before anything tries to resolve one. Odd fakes are public, even
		-- ones friends-only, so both list groups can be seen solo.
		table.insert(fakeRuns, {
			hostUserId = -index,
			hostName = `Fake {index}`,
			missionId = FAKE_MISSION_ID,
			era = if mission ~= nil then mission.era else 1,
			wave = index,
			overdrive = false,
			partySize = 1,
			accessCode = FAKE_ACCESS_CODE,
			public = index % 2 == 1,
			memberIds = { -index },
		})
	end
	warn(`[ExpeditionService] fakeRuns lever: {wanted} Studio-only run(s) in the join list`)
end

-- PartyService's busy hook: a departing player can be neither invited nor accept.
function ExpeditionService.IsDeparting(player: Player): boolean
	return departing[player] ~= nil
end

-- Called from Main's PlayerRemoving only — deliberately NOT from its releasePlayer, which the
-- handoff itself runs while a teleport is still in flight.
function ExpeditionService.Forget(player: Player): ()
	departing[player] = nil
	friendVerdicts[player] = nil
end

function ExpeditionService.Init(serviceHooks: Hooks?): ()
	hooks = serviceHooks

	-- TeleportAsync only THROWS for argument errors; an unpublished place, a throttle or a full
	-- destination is refused asynchronously and surfaces here, per player, after the pcall has
	-- already returned true and the profiles have already been released. Without this the player
	-- sits in the hub with no profile, no plot and no card. In Studio there is no teleport to
	-- refuse, so the ForceTeleportFailure lever drives this same recovery from handOff.
	TeleportService.TeleportInitFailed:Connect(
		function(player: Player, teleportResult: Enum.TeleportResult, errorMessage: string)
			local departure = departing[player]
			if departure == nil then
				return
			end
			warn(
				`[ExpeditionService] teleport refused for {player.Name}`
					.. ` ({teleportResult.Name}): {errorMessage}`
			)
			departedFromHere[player.UserId] = nil
			abortDeparture(player, departure)
		end
	)
end

function ExpeditionService.Start(): () end

return ExpeditionService
