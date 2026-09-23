--!strict
-- The trip home (docs/INTERFACES.md "C0 contracts" → "Combat place server", "C2 contracts" →
-- "Combat place (A)"). Three exits, one shape: every trip home carries a Types.ReturnData.
-- * SendHome: one player leaves on their own (Return button, a rejoin that cannot be admitted):
--   only their own summary, no party hint.
-- * SendHomeGroup: the summary countdown ran out; the departed hub party goes in ONE teleport
--   with its summaries plus the party hint, so the hub can re-form it; mid-run joiners go alone.
-- * Refuse: an arrival CheckAdmission turned away (full / over / locked), before any admit.
--
-- Nothing here writes cash, lastSeen, incomeAtSave or slots: the hub owns the city economy, and
-- a combat server must never be able to restamp it.
--
-- Like the hub's handoff, this releases the session before it teleports, so every failure path
-- (a thrown call OR an asynchronous refusal on TeleportInitFailed) has to get the profile back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local StudioBridge = require(servicesFolder:WaitForChild("StudioBridge"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))

-- Infrastructure retry policy, like DataService's: three attempts, 1 s / 2 s / 4 s backoff.
local RETRY_ATTEMPTS = 3
local RETRY_BASE_SECONDS = 1
local BRIDGE_HOME_MESSAGE = "Run over — Stop Play, then reopen build/test.rbxl"
local BRIDGE_REFUSED_MESSAGE = "Could not join that run — Stop Play, then reopen build/test.rbxl"

export type Hooks = {
	-- The combat Main's join sequence, re-run when the trip home fails so the player is not
	-- stranded with no profile. Called synchronously (it yields until the profile is back).
	rejoin: (player: Player) -> (),
}

export type Refusal = "full" | "over" | "locked"

-- "home" re-admits on failure; "refused" only reloads the profile (re-running admission would
-- refuse again and loop through the teleport forever).
type LeaveKind = "home" | "refused"

local hooks: Hooks? = nil
-- Present exactly while a trip home is in flight. RequestLeave shares the 10/s gameplay bucket,
-- so without this ten taps on Return would start ten teleports and ten releases.
local leaving: { [Player]: LeaveKind } = {}

local function sendUnavailable(player: Player): ()
	local result: Types.ActionResult =
		{ action = "expedition", slotId = "", ok = false, reason = "unavailable" }
	RemoteService.FireClient(player, "ActionResult", result)
end

-- A player who was never admitted (a refused arrival pressing Return) still goes home, with a
-- zeroed card, and without creating a summary entry for a non-member.
local function buildSummary(player: Player): Types.RunSummary
	if ArenaService.IsAdmitted(player) then
		return ArenaService.GetSummary(player.UserId)
	end
	local mission = ArenaService.GetMission()
	return {
		missionId = if mission ~= nil then mission.id else "",
		overdrive = ArenaService.IsOverdrive(),
		wavesCleared = 0,
		bestWave = 0,
		died = false,
		cash = 0,
		materials = {},
		valor = 0,
		kills = 0,
		seconds = 0,
		mentorValor = 0,
		damageShare = 0,
	}
end

-- Only ARGUMENT errors throw; a runtime refusal arrives later on TeleportInitFailed.
local function teleportWithRetry(
	placeId: number,
	players: { Player },
	data: Types.ReturnData,
	description: string
): boolean
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(data)
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, players, options)
		end)
		if ok then
			return true
		end
		warn(`[ReturnService] TeleportAsync failed for {description} (attempt {attempt}): {err}`)
		if attempt < RETRY_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return false
end

-- The session is already released, so the player has to be put back into the run rather than
-- left in safe mode.
local function abortReturn(player: Player): ()
	leaving[player] = nil
	sendUnavailable(player)
	local serviceHooks = hooks
	if serviceHooks == nil or not player:IsDescendantOf(Players) then
		return
	end
	serviceHooks.rejoin(player)
end

-- A refused arrival whose trip home failed: profile back, no admission. They stay unadmitted
-- with the toast, and the Return button (SendHome) is their way out.
local function abortRefusal(player: Player): ()
	leaving[player] = nil
	sendUnavailable(player)
	if not player:IsDescendantOf(Players) then
		return
	end
	if DataService.LoadAsync(player) ~= nil then
		ArenaService.SendSnapshot(player)
	end
end

-- ArenaService.CheckAdmission's verdict reaches callers as a plain string (the old solver widens
-- a singleton union returned across modules), so it is narrowed back here; anything unexpected
-- is the most conservative refusal.
local function refusalOf(reason: string): Refusal
	if reason == "full" then
		return "full"
	elseif reason == "over" then
		return "over"
	end
	return "locked"
end

local ReturnService = {}

-- The recovery for a failed trip: a member goes back into the run, anyone else (a refused
-- arrival pressing Return) only gets the profile back. Re-admitting a non-member here would skip
-- CheckAdmission entirely (a fifth seat, a late join, a locked mission).
local function abortFor(player: Player, kind: LeaveKind): ()
	if kind == "refused" then
		abortRefusal(player)
	else
		abortReturn(player)
	end
end

-- Returns true only when the trip was accepted, i.e. when the in-flight guard must stay. `kind`
-- was decided BEFORE ArenaService.Remove, while membership could still be read.
local function trySendHome(player: Player, reason: string, kind: LeaveKind): boolean
	local summary = buildSummary(player)
	local summaryState = ArenaService.BuildRunState("summary", summary)
	-- Going alone: the group countdown does not apply to this card.
	summaryState.returnIn = nil
	RemoteService.FireClient(player, "RunState", summaryState)

	local places = Catalog.GetPlacesConfig()
	if places.hubPlaceId == 0 then
		-- Nowhere to go: keep the player (and their profile) exactly where they are, with the
		-- summary card up, rather than releasing a session we cannot hand over.
		warn(`[ReturnService] cannot send {player.Name} home ({reason}): hub place id not set`)
		sendUnavailable(player)
		return false
	end

	local data: Types.ReturnData = { summaries = { [tostring(player.UserId)] = summary } }

	-- C1: in Studio the trip home is a handoff record plus a kick (docs/INTERFACES.md "Studio
	-- bridge" → "Combat side"). The release, the failure recovery and the summary itself are
	-- the live code path; only TeleportAsync is replaced.
	if StudioBridge.IsActive() then
		if not StudioBridge.WriteReturn(player, data) then
			-- Nothing released: the player stays in the run with the summary card up, exactly
			-- as they would with hubPlaceId = 0.
			sendUnavailable(player)
			return false
		end
		ArenaService.Remove(player)
		DataService.Release(player)
		if StudioBridge.TeleportShouldFail() then
			-- The lever reproduces TeleportInitFailed, so it runs that handler's recovery.
			abortFor(player, kind)
			return false
		end
		StudioBridge.Depart(player, BRIDGE_HOME_MESSAGE)
		return true
	end

	ArenaService.Remove(player)
	-- Released BEFORE the teleport, exactly like the hub does on departure: the hub server must
	-- find the key free when it loads the profile.
	DataService.Release(player)
	if teleportWithRetry(places.hubPlaceId, { player }, data, player.Name) then
		return true
	end
	abortFor(player, kind)
	return false
end

-- Yields (the teleport retries). `reason` is for the log only: the client learns why from the
-- RunState/ActionResult it already gets.
function ReturnService.SendHome(player: Player, reason: string): ()
	if leaving[player] ~= nil then
		return
	end
	local kind: LeaveKind = if ArenaService.IsAdmitted(player) then "home" else "refused"
	leaving[player] = kind
	if not trySendHome(player, reason, kind) then
		leaving[player] = nil
	end
end

-- Yields. The end-of-run group return. The party hint lists only the humans still here who
-- DEPARTED together (ticket.expected): a stranger who joined mid-run was never in that hub party,
-- so the hub must not pull them into it. Leader = the host if present, else the first of them;
-- fewer than two left means no party to re-form, so no hint. The party goes in ONE teleport with
-- its members' summaries; everyone else goes on their own with only their own summary.
function ReturnService.SendHomeGroup(players: { Player }, reason: string): ()
	local group: { Player } = {}
	for _, player in players do
		if
			player:IsDescendantOf(Players)
			and leaving[player] == nil
			and ArenaService.IsAdmitted(player)
		then
			table.insert(group, player)
		end
	end
	if #group == 0 then
		return
	end

	local places = Catalog.GetPlacesConfig()
	if places.hubPlaceId == 0 then
		warn(`[ReturnService] cannot send the party home ({reason}): hub place id not set`)
		for _, player in group do
			sendUnavailable(player)
		end
		return
	end

	local summaries: { [string]: Types.RunSummary } = {}
	local partyPlayers: { Player } = {}
	local partyIds: { number } = {}
	for _, player in group do
		leaving[player] = "home"
		summaries[tostring(player.UserId)] = buildSummary(player)
		if ArenaService.IsExpected(player.UserId) then
			table.insert(partyPlayers, player)
			table.insert(partyIds, player.UserId)
		end
	end
	local partyData: Types.ReturnData? = nil
	if #partyIds >= 2 then
		local host = ArenaService.GetHostUserId()
		local partySummaries: { [string]: Types.RunSummary } = {}
		for _, userId in partyIds do
			partySummaries[tostring(userId)] = summaries[tostring(userId)]
		end
		partyData = {
			summaries = partySummaries,
			party = {
				leaderUserId = if table.find(partyIds, host) ~= nil then host else partyIds[1],
				memberIds = partyIds,
			},
		}
	else
		partyPlayers = {}
	end
	local function soloData(player: Player): Types.ReturnData
		local key = tostring(player.UserId)
		return { summaries = { [key] = summaries[key] } }
	end

	if StudioBridge.IsActive() then
		local sent: { Player } = {}
		for _, player in group do
			local inParty = table.find(partyPlayers, player) ~= nil
			local data = if inParty and partyData ~= nil then partyData else soloData(player)
			if StudioBridge.WriteReturn(player, data) then
				table.insert(sent, player)
			else
				-- Nothing released for this one: they stay on the summary card with a toast
				-- and can still press Return.
				leaving[player] = nil
				sendUnavailable(player)
			end
		end
		for _, player in sent do
			ArenaService.Remove(player)
			DataService.Release(player)
		end
		-- Read once for the whole group, like the single TeleportAsync it stands in for.
		if StudioBridge.TeleportShouldFail() then
			for _, player in sent do
				task.spawn(abortReturn, player)
			end
			return
		end
		for _, player in sent do
			StudioBridge.Depart(player, BRIDGE_HOME_MESSAGE)
		end
		return
	end

	for _, player in group do
		ArenaService.Remove(player)
		DataService.Release(player)
	end
	-- One batch per teleport: the party together, each stranger alone. In parallel, and each
	-- failed batch recovers its own members (each rejoin yields on its own profile load).
	local batches: { { players: { Player }, data: Types.ReturnData } } = {}
	if partyData ~= nil then
		table.insert(batches, { players = partyPlayers, data = partyData })
	end
	for _, player in group do
		if table.find(partyPlayers, player) == nil then
			table.insert(batches, { players = { player }, data = soloData(player) })
		end
	end
	for _, batch in batches do
		task.spawn(function()
			local description = `{#batch.players} player(s)`
			if teleportWithRetry(places.hubPlaceId, batch.players, batch.data, description) then
				return
			end
			for _, player in batch.players do
				task.spawn(abortReturn, player)
			end
		end)
	end
end

-- Yields. An arrival CheckAdmission turned away, sent back before it was ever admitted: a
-- ReturnData with no summaries and the reason, which the hub shows as a joinRun refusal.
function ReturnService.Refuse(player: Player, verdict: string): ()
	if leaving[player] ~= nil then
		return
	end
	local reason: Refusal = refusalOf(verdict)
	-- Shown here too, in case the trip home cannot happen (Studio without API access).
	local result: Types.ActionResult =
		{ action = "joinRun", slotId = "", ok = false, reason = reason }
	RemoteService.FireClient(player, "ActionResult", result)

	local places = Catalog.GetPlacesConfig()
	if places.hubPlaceId == 0 then
		warn(`[ReturnService] cannot refuse {player.Name} ({reason}): hub place id not set`)
		return
	end
	leaving[player] = "refused"
	local data: Types.ReturnData = { summaries = {}, refused = reason }

	if StudioBridge.IsActive() then
		if not StudioBridge.WriteReturn(player, data) then
			leaving[player] = nil
			return
		end
		DataService.Release(player)
		if StudioBridge.TeleportShouldFail() then
			abortRefusal(player)
			return
		end
		StudioBridge.Depart(player, BRIDGE_REFUSED_MESSAGE)
		return
	end

	DataService.Release(player)
	if not teleportWithRetry(places.hubPlaceId, { player }, data, player.Name) then
		abortRefusal(player)
	end
end

-- Called from Main's PlayerRemoving: the trip home is over one way or the other.
function ReturnService.Forget(player: Player): ()
	leaving[player] = nil
end

function ReturnService.Init(serviceHooks: Hooks?): ()
	hooks = serviceHooks

	-- TeleportAsync only THROWS for argument errors; an unpublished hub place, a throttle or a
	-- full destination is refused asynchronously and lands here, after the pcall returned true
	-- and the profile was already released. In Studio there is no teleport to refuse, so the
	-- ForceTeleportFailure lever drives this same recovery from the bridge branches above.
	TeleportService.TeleportInitFailed:Connect(
		function(player: Player, teleportResult: Enum.TeleportResult, errorMessage: string)
			local kind: LeaveKind? = leaving[player]
			if kind == nil then
				return
			end
			warn(
				`[ReturnService] teleport refused for {player.Name}`
					.. ` ({teleportResult.Name}): {errorMessage}`
			)
			abortFor(player, kind)
		end
	)
end

function ReturnService.Start(): () end

return ReturnService
