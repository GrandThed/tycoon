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

-- Read-only view of the combat place's run registry. The hub never writes it: the place that
-- owns a run owns its entry, so a hub bug can never advertise a run that does not exist.
local function registryMap(): any?
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil or isStudio then
		-- MemoryStore needs API access; in Studio the run list is simply empty.
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
	if isStudio then
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

local function readRegistryEntry(hostUserId: number): Types.ActiveRun?
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

-- Steps 3-7 of the contract, shared by Depart and Join: the checks that do not depend on how
-- the run was chosen, then the reservation (or the joined run's code), then the handoff.
-- Returns true only when TeleportAsync was accepted, i.e. when the in-flight guard must stay.
local function teleportToRun(
	player: Player,
	departure: Departure,
	missionId: string,
	overdrive: boolean,
	hostUserId: number,
	accessCode: string?
): boolean
	local places = Catalog.GetPlacesConfig()
	if places.combatPlaceId == 0 or isStudio then
		if isStudio then
			warn("[ExpeditionService] Studio can't teleport — open build/combat.rbxl instead")
		end
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

	local code = accessCode
	if code == nil or code == "" then
		local ok, reserved = callWithRetry("ReserveServer", function(): string
			local reservedCode = TeleportService:ReserveServer(places.combatPlaceId)
			return reservedCode
		end)
		if not ok or reserved == nil or reserved == "" then
			sendResult(player, departure.action, departure.slotId, false, "unavailable")
			return false
		end
		code = reserved
		-- The reserving server is the only one that ever sees this code, so it publishes it for
		-- the combat server it is about to fill.
		if not writeAccessCode(combatConfig, hostUserId, reserved, missionId, overdrive) then
			sendResult(player, departure.action, departure.slotId, false, "unavailable")
			return false
		end
	end

	local state = DataService.GetState(player)
	if state == nil then
		-- The reservation yielded; the profile may have been released meanwhile.
		sendResult(player, departure.action, departure.slotId, false, "unavailable")
		return false
	end
	-- Stamped before the release so the away window is already in the final save: the offline
	-- grant on return reads expeditionSeconds, and the combat place keeps adding to it.
	state.combat.expeditionSince = os.time()
	state.combat.expeditionSeconds = 0
	state.combat.stats.expeditions += 1
	EconomyService.RefreshPersistedRate(player)
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
	for _, run in runs do
		if run.hostUserId == player.UserId then
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
			-- The access code never leaves the server: with it, any client could teleport
			-- itself into a reserved server.
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
	end
	RemoteService.FireClient(player, "RunList", { runs = visible })
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
	-- the hub with no profile, no plot and no card. Cannot be reproduced in Studio, where every
	-- teleport is refused before it starts (see the Depart/isStudio branch).
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
