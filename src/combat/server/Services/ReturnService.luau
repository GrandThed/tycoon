--!strict
-- The trip home (docs/INTERFACES.md "C0 contracts" → "Combat place server"). Every exit from a
-- run goes through SendHome: the summary card first, then the profile release, then the teleport
-- back to the hub. The hub pays the away time from expeditionSeconds on arrival.
--
-- Nothing here writes cash, lastSeen, incomeAtSave or slots: the hub owns the city economy, and
-- a combat server must never be able to restamp it.
--
-- Like the hub's handoff, this releases the session before it teleports, so every failure path
-- (a thrown call OR an asynchronous refusal on TeleportInitFailed) has to re-admit the player.

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

export type Hooks = {
	-- The combat Main's join sequence, re-run when the trip home fails so the player is not
	-- stranded with no profile. Called synchronously (it yields until the profile is back).
	rejoin: (player: Player) -> (),
}

local hooks: Hooks? = nil
-- Present exactly while a trip home is in flight. RequestLeave shares the 10/s gameplay bucket,
-- so without this ten taps on Return would start ten teleports and ten releases.
local leaving: { [Player]: boolean } = {}

local function sendUnavailable(player: Player): ()
	local result: Types.ActionResult =
		{ action = "expedition", slotId = "", ok = false, reason = "unavailable" }
	RemoteService.FireClient(player, "ActionResult", result)
end

-- The run's own numbers come from ArenaService.GetSummary (C1, luau-engineer A's WaveService
-- feeds it). A build where it does not exist yet — or a player who was never admitted — still
-- goes home, with the zeroed C0 card rather than an error on the way out. Built through `any`
-- because Types.RunSummary gains bestWave/died in this same milestone.
local function buildSummary(player: Player): Types.RunSummary
	local getSummary = (ArenaService :: any).GetSummary
	if typeof(getSummary) == "function" then
		local ok, summary = pcall(getSummary, player.UserId)
		if ok and typeof(summary) == "table" then
			return summary :: Types.RunSummary
		end
	end
	local mission = ArenaService.GetMission()
	local empty: any = {
		missionId = if mission ~= nil then mission.id else "",
		overdrive = ArenaService.IsOverdrive(),
		wavesCleared = 0,
		cash = 0,
		materials = {},
		valor = 0,
		kills = 0,
		seconds = 0,
		bestWave = 0,
		died = false,
	}
	return empty :: Types.RunSummary
end

-- Shared by the retry-exhausted branch and TeleportInitFailed: the session is already released,
-- so the player has to be put back into the run rather than left in safe mode.
local function abortReturn(player: Player): ()
	leaving[player] = nil
	sendUnavailable(player)
	local serviceHooks = hooks
	if serviceHooks == nil or not player:IsDescendantOf(Players) then
		return
	end
	serviceHooks.rejoin(player)
end

local ReturnService = {}

-- Returns true only when TeleportAsync was accepted, i.e. when the in-flight guard must stay.
local function trySendHome(player: Player, reason: string): boolean
	local summary = buildSummary(player)
	local summaryState = ArenaService.BuildRunState("summary", summary)
	RemoteService.FireClient(player, "RunState", summaryState)

	local places = Catalog.GetPlacesConfig()
	if places.hubPlaceId == 0 then
		-- Nowhere to go: keep the player (and their profile) exactly where they are, with the
		-- summary card up, rather than releasing a session we cannot hand over.
		warn(`[ReturnService] cannot send {player.Name} home ({reason}): hub place id not set`)
		sendUnavailable(player)
		return false
	end

	-- C1: in Studio the trip home is a handoff record plus a kick (docs/INTERFACES.md "Studio
	-- bridge" → "Combat side"). The release, the failure recovery and the summary itself are
	-- the live code path; only TeleportAsync is replaced.
	if StudioBridge.IsActive() then
		if not StudioBridge.WriteReturn(player, summary) then
			-- Nothing released: the player stays in the run with the summary card up, exactly
			-- as they would with hubPlaceId = 0.
			sendUnavailable(player)
			return false
		end
		ArenaService.Remove(player)
		DataService.Release(player)
		if StudioBridge.TeleportShouldFail() then
			-- The lever reproduces TeleportInitFailed, so it runs that handler's recovery.
			abortReturn(player)
			return false
		end
		StudioBridge.Depart(player, "Run over — Stop Play, then reopen build/test.rbxl")
		return true
	end

	ArenaService.Remove(player)
	-- Released BEFORE the teleport, exactly like the hub does on departure: the hub server must
	-- find the key free when it loads the profile.
	DataService.Release(player)

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ summary = summaryState.summary })
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(places.hubPlaceId, { player }, options)
		end)
		if ok then
			return true
		end
		warn(`[ReturnService] TeleportAsync failed for {player.Name} (attempt {attempt}): {err}`)
		if attempt < RETRY_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end

	-- Only ARGUMENT errors throw above; a runtime refusal arrives later on TeleportInitFailed.
	abortReturn(player)
	return false
end

-- Yields (the teleport retries). `reason` is for the log only: the client learns why from the
-- RunState/ActionResult it already gets.
function ReturnService.SendHome(player: Player, reason: string): ()
	if leaving[player] then
		return
	end
	leaving[player] = true
	if not trySendHome(player, reason) then
		leaving[player] = nil
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
	-- ForceTeleportFailure lever drives this same recovery from the bridge branch above.
	TeleportService.TeleportInitFailed:Connect(
		function(player: Player, teleportResult: Enum.TeleportResult, errorMessage: string)
			if not leaving[player] then
				return
			end
			warn(
				`[ReturnService] teleport refused for {player.Name}`
					.. ` ({teleportResult.Name}): {errorMessage}`
			)
			abortReturn(player)
		end
	)
end

function ReturnService.Start(): () end

return ReturnService
