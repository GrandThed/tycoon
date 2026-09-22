--!strict
-- The hub side of the expedition handoff (docs/INTERFACES.md "C0 contracts" → "Expedition
-- handoff"). One profile, two places: the hub RELEASES the ProfileStore session before it
-- teleports, so the Expeditions place can load the same key without ever passing Steal.
--
-- Teardown order is Main's, not ours: Main hands in its own `release` (PlotService.Release →
-- EconomyService.Cleanup → DataService.Release) and `rejoin` (the join sequence) as hooks, which
-- is also what keeps this module out of a require cycle with PlotService/Monetization.
--
-- Because the profile is already gone by the time a teleport can fail, EVERY failure path has to
-- put the player back together: clear the in-flight guard, re-run the join sequence, hand back
-- the departure stat, and tell the client. There are two such paths, and only one of them is a
-- thrown call (see TeleportInitFailed in Init).
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
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))
local StudioBridge = require(script.Parent:WaitForChild("StudioBridge"))

-- Infrastructure retry policy, like DataService's: three attempts with 1 s / 2 s / 4 s backoff
-- around each Teleport/MemoryStore call. Not balance, so not in Config/*.json.
local RETRY_ATTEMPTS = 3
local RETRY_BASE_SECONDS = 1
-- The registry is a handful of runs per shard; one page is plenty for a join list.
local REGISTRY_PAGE_SIZE = 50
-- The reserved access codes live in their own SERVER-ONLY hash map beside the run registry: a
-- code is a key to a private server, so it never travels in teleport data (the teleporting
-- client can read that) and never reaches a client in the RunList.
local CODES_MAP_SUFFIX = "Codes"
local CODES_KEY_PREFIX = "code_"
-- Each friend check is a serial web call, and RequestRunList is client-driven: a full page would
-- cost 50 of them per tap. Eight fills the visible list, and the panel refreshes every 10 s, so
-- a longer list simply resolves over a couple of refreshes.
local MAX_FRIEND_CHECKS_PER_CALL = 8
-- C1 Studio bridge: there is no reserved server to teleport into, so the handoff record carries
-- a marker instead of a real access code.
local STUDIO_ACCESS_CODE = "studio"
-- Studio-only stand-ins for other people's runs (the DebugFakeRuns attribute and the `fakeRuns`
-- lever). They live in this module rather than in the MemoryStore registry because nothing
-- outside this server may ever see them, and a run nobody hosts must never be advertised live.
local FAKE_ACCESS_CODE = "fake"
local FAKE_MISSION_ID = "village"
-- The join list shows a handful of runs; more fakes would only push the real ones off it.
local MAX_FAKE_RUNS = 8
local BRIDGE_DEPART_MESSAGE = "Handoff saved — Stop Play, then open build/combat.rbxl"

export type Hooks = {
	-- Main's PlayerRemoving teardown, run before the teleport so the profile is free.
	release: (player: Player) -> (),
	-- Main's join sequence. Called synchronously (it yields until the profile is back) so a
	-- failed handoff can undo the departure stamp on the profile the reload produced.
	rejoin: (player: Player) -> (),
}

-- What an in-flight departure needs to answer the client if it fails asynchronously.
type Departure = { action: "expedition" | "joinRun", slotId: string }

local hooks: Hooks? = nil
local isStudio = RunService:IsStudio()
-- Present exactly while a teleport is in flight for that player. Also the guard that stops the
-- prompt bucket from admitting a second Depart/Join while the first one yields.
local departing: { [Player]: Departure } = {}
-- Friend verdicts for this session, per requesting player, so a 10 s refresh loop does not
-- re-ask Roblox about the same hosts. Cleared in Forget.
local friendVerdicts: { [Player]: { [number]: boolean } } = {}
-- Studio fake runs and the moment they expire, so the lever behaves like the registry's TTL.
local fakeRuns: { Types.ActiveRun } = {}
local fakeRunsExpireAt = 0

local function sendResult(
	player: Player,
	action: "expedition" | "joinRun",
	slotId: string,
	ok: boolean,
	reason: ("insufficientFunds" | "locked" | "invalid" | "unavailable")?
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
-- on, a Studio session talks to the real registry exactly as a live server does (the C1 bridge
-- exists to make these platform paths playable); only ProfileStore's in-memory mock, i.e. no
-- API access, still disables it. Checked per call: ProfileStore probes access asynchronously
-- after require, so a boot-time verdict would be wrong.
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

-- Hands the reserved code to the combat server that is about to boot: it cannot read its own
-- access code from any API, and without it the arena publishes no registry entry, so the run
-- would be unjoinable. A failure here is treated exactly like a failed reservation.
local function writeAccessCode(
	combatConfig: Types.CombatConfig,
	hostUserId: number,
	accessCode: string,
	missionId: string,
	overdrive: boolean
): boolean
	local map = codesMap(combatConfig)
	if map == nil then
		return false
	end
	local key = CODES_KEY_PREFIX .. hostUserId
	local value = { accessCode = accessCode, missionId = missionId, overdrive = overdrive }
	local ttl = combatConfig.registry.ttlSeconds
	local ok = callWithRetry(`codes SetAsync {hostUserId}`, function(): boolean
		map:SetAsync(key, value, ttl)
		return true
	end)
	return ok
end

-- A registry value is written by another server, so every field the join path compares is
-- type-checked before it is used; anything malformed reads as "no such run".
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
	return run :: Types.ActiveRun
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
	for _, run in activeFakeRuns() do
		table.insert(runs, run)
	end
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
		local run = asActiveRun(item.value)
		if run ~= nil then
			table.insert(runs, run)
		end
	end
	return runs
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
local function unstampDeparture(state: Types.PlayerState): ()
	state.combat.expeditionSince = 0
	state.combat.expeditionSeconds = 0
	state.combat.stats.expeditions = math.max(0, state.combat.stats.expeditions - 1)
end

-- Steps 3-7 of the contract, shared by Depart and Join: the checks that do not depend on how
-- the run was chosen, then the reservation (or the joined run's code), then the handoff.
-- Returns true only when the handoff was accepted, i.e. when the in-flight guard must stay.
local function teleportToRun(
	player: Player,
	departure: Departure,
	missionId: string,
	overdrive: boolean,
	hostUserId: number,
	accessCode: string?
): boolean
	local places = Catalog.GetPlacesConfig()
	if places.combatPlaceId == 0 then
		sendResult(player, departure.action, departure.slotId, false, "unavailable")
		return false
	end
	local combatConfig = Catalog.GetCombatConfig()
	local serviceHooks = hooks
	if combatConfig == nil or serviceHooks == nil then
		warn("[ExpeditionService] no combat config or no hooks; refusing to teleport")
		sendResult(player, departure.action, departure.slotId, false, "unavailable")
		return false
	end
	-- C1: in Studio the teleport itself is replaced by a DataStore handoff record plus a kick
	-- (docs/INTERFACES.md "Studio bridge"); everything around it — the stamp, the release, the
	-- failure recovery — is the live code path.
	local bridged = StudioBridge.IsActive()

	local code = accessCode
	if code == nil or code == "" then
		if bridged then
			-- No reserved server exists, so the record carries a marker. It is still published
			-- to the codes map (a no-op without API access): RunRegistry verifies the code
			-- before the combat place advertises the run, so a Studio run publishes itself
			-- exactly as a live one does.
			code = STUDIO_ACCESS_CODE
			writeAccessCode(combatConfig, hostUserId, STUDIO_ACCESS_CODE, missionId, overdrive)
		else
			local ok, reserved = callWithRetry("ReserveServer", function(): string
				local reservedCode = TeleportService:ReserveServer(places.combatPlaceId)
				return reservedCode
			end)
			if not ok or reserved == nil or reserved == "" then
				sendResult(player, departure.action, departure.slotId, false, "unavailable")
				return false
			end
			code = reserved
			-- The reserving server is the only one that ever sees this code, so it publishes it
			-- for the combat server it is about to fill.
			if not writeAccessCode(combatConfig, hostUserId, reserved, missionId, overdrive) then
				sendResult(player, departure.action, departure.slotId, false, "unavailable")
				return false
			end
		end
	end

	local state = DataService.GetState(player)
	if state == nil then
		-- The reservation yielded; the profile may have been released meanwhile.
		sendResult(player, departure.action, departure.slotId, false, "unavailable")
		return false
	end
	stampDeparture(state)
	EconomyService.RefreshPersistedRate(player)

	if bridged then
		local hint: StudioBridge.TeleportHint = {
			missionId = missionId,
			overdrive = overdrive,
			hostUserId = hostUserId,
			accessCode = code,
		}
		local kind: StudioBridge.HandoffKind = if departure.action == "expedition"
			then "depart"
			else "join"
		if not StudioBridge.WriteDeparture(player, hint, kind) then
			-- Nothing has been released yet, so the player simply stays in the hub with the
			-- profile they already had; the stamp goes back with them.
			unstampDeparture(state)
			EconomyService.MarkDirty(player, { combat = true })
			sendResult(player, departure.action, departure.slotId, false, "unavailable")
			return false
		end
		serviceHooks.release(player)
		if StudioBridge.TeleportShouldFail() then
			-- The lever reproduces TeleportInitFailed, so it runs that handler's recovery, not a
			-- Studio-only imitation of it. The record goes first: the arrival it describes is
			-- never going to happen.
			StudioBridge.ClearDeparture(player)
			abortDeparture(player, departure)
			return false
		end
		sendResult(player, departure.action, departure.slotId, true, nil)
		StudioBridge.Depart(player, BRIDGE_DEPART_MESSAGE)
		return true
	end

	sendResult(player, departure.action, departure.slotId, true, nil)

	-- Frozen teardown order, then the handoff. The session must be released BEFORE the teleport
	-- or the combat place would find the key locked and drop the player into safe mode.
	serviceHooks.release(player)

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code :: string
	options:SetTeleportData({
		missionId = missionId,
		overdrive = overdrive,
		hostUserId = hostUserId,
	})
	local teleported = callWithRetry(`TeleportAsync {missionId}`, function(): boolean
		TeleportService:TeleportAsync(places.combatPlaceId, { player }, options)
		return true
	end)
	if not teleported then
		-- Only ARGUMENT errors throw here; a runtime refusal arrives later on
		-- TeleportInitFailed (see Init).
		abortDeparture(player, departure)
		return false
	end
	return true
end

local ExpeditionService = {}

-- RequestExpedition. Yields (reservation + teleport), so it runs on the remote's own thread.
function ExpeditionService.Depart(player: Player, missionId: string, overdrive: boolean): ()
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

	local mission = Catalog.GetMissionById(missionId)
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil then
		-- No Combat.json: the whole feature is hidden, so this is a stale or forged intent.
		sendResult(player, "expedition", missionId, false, "unavailable")
		return
	end
	if mission == nil or not Combat.MissionUnlocked(state, mission, overdrive, combatConfig) then
		sendResult(player, "expedition", missionId, false, "locked")
		return
	end

	-- Nothing above yields, so the check and the claim below cannot interleave.
	local departure: Departure = { action = "expedition", slotId = missionId }
	departing[player] = departure
	if not teleportToRun(player, departure, missionId, overdrive, player.UserId, nil) then
		departing[player] = nil
	end
end

-- RequestJoinRun. C0 validates the registry entry and hands the reserved code to the same
-- handoff; the full party flow (invites, wave-aware admission) is C2.
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
	if entry ~= nil and entry.accessCode == FAKE_ACCESS_CODE then
		-- A Studio fake has no server behind it: the list exists to be looked at, and Join on
		-- one shows exactly what a vanished run shows.
		sendResult(player, "joinRun", slotId, false, "unavailable")
		return
	end
	if
		entry == nil
		or entry.partySize >= combatConfig.coop.maxParty
		or entry.wave > combatConfig.coop.joinUntilWave
	then
		-- Gone, full, malformed, or too far in: all of them read as "unavailable" to the client.
		sendResult(player, "joinRun", slotId, false, "unavailable")
		return
	end
	local mission = Catalog.GetMissionById(entry.missionId)
	if
		mission == nil
		or not Combat.MissionUnlocked(state, mission, entry.overdrive, combatConfig)
	then
		sendResult(player, "joinRun", slotId, false, "locked")
		return
	end
	if departing[player] ~= nil then
		-- A second tap could have claimed the guard while the registry read yielded.
		return
	end

	local departure: Departure = { action = "joinRun", slotId = slotId }
	departing[player] = departure
	local handedOff = teleportToRun(
		player,
		departure,
		entry.missionId,
		entry.overdrive,
		hostUserId,
		entry.accessCode
	)
	if not handedOff then
		departing[player] = nil
	end
end

-- RequestRunList. Yields (MemoryStore + friend checks), so it runs on the remote's own thread.
function ExpeditionService.SendRunList(player: Player): ()
	local runs = readRegistryRuns()
	local verdicts = friendVerdicts[player]
	if verdicts == nil then
		verdicts = {}
		friendVerdicts[player] = verdicts
	end
	local visible: { Types.ActiveRun } = {}
	local checks = 0
	-- The access code never leaves the server: with it, any client could teleport itself into a
	-- reserved server.
	local function show(run: Types.ActiveRun): ()
		table.insert(visible, {
			hostUserId = run.hostUserId,
			hostName = run.hostName,
			missionId = run.missionId,
			era = run.era,
			wave = run.wave,
			overdrive = run.overdrive,
			partySize = run.partySize,
			accessCode = "",
		})
	end
	for _, run in runs do
		if run.hostUserId == player.UserId then
			continue
		end
		if run.accessCode == FAKE_ACCESS_CODE then
			-- Studio fakes have no account behind them, and IsFriendsWithAsync on their
			-- negative ids would throw and hide the very list the lever exists to show.
			show(run)
			continue
		end
		-- Joinable = a friend's run. Anything else stays invisible, so the list can never
		-- become a public directory of reserved servers. (Party runs with players from this
		-- server are C2.)
		local verdict = verdicts[run.hostUserId]
		if verdict == nil then
			if checks >= MAX_FRIEND_CHECKS_PER_CALL then
				break
			end
			checks += 1
			local ok, result = pcall(function(): boolean
				return player:IsFriendsWithAsync(run.hostUserId)
			end)
			verdict = ok and result == true
			verdicts[run.hostUserId] = verdict
		end
		if verdict then
			show(run)
		end
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
		-- "fake" access code before anything tries to resolve one.
		table.insert(fakeRuns, {
			hostUserId = -index,
			hostName = `Fake {index}`,
			missionId = FAKE_MISSION_ID,
			era = if mission ~= nil then mission.era else 1,
			wave = index,
			overdrive = false,
			partySize = 1,
			accessCode = FAKE_ACCESS_CODE,
		})
	end
	warn(`[ExpeditionService] fakeRuns lever: {wanted} Studio-only run(s) in the join list`)
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
	-- destination is refused asynchronously and surfaces here, after the pcall has already
	-- returned true and the profile has already been released. Without this the player sits in
	-- the hub with no profile, no plot and no card. In Studio there is no teleport to refuse, so
	-- the ForceTeleportFailure lever drives this same recovery from the bridge branch above.
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
			abortDeparture(player, departure)
		end
	)
end

function ExpeditionService.Start(): () end

return ExpeditionService
