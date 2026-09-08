--!strict
-- Owns the 1 Hz income loop, the Cash player-attribute mirror, offline grants, and all
-- StateChanged emission: full snapshots on join/request plus dirty-flag deltas batched at
-- ≤ remotes.stateDeltaHz (docs/INTERFACES.md "Server runtime contracts" + "M2 contracts").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

export type DirtyFields = { cash: boolean?, income: boolean?, slotIds: { string }? }
type DirtyRecord = { cash: boolean, income: boolean, slotIds: { [string]: boolean } }

local dirtyRecords: { [Player]: DirtyRecord } = {}
local pendingWelcomeBack: { [Player]: Types.WelcomeBack } = {}
local isStudio = RunService:IsStudio()
local tickAccumulator = 0
local flushAccumulator = 0

local function getDirtyRecord(player: Player): DirtyRecord
	local record = dirtyRecords[player]
	if record == nil then
		record = { cash = false, income = false, slotIds = {} }
		dirtyRecords[player] = record
	end
	return record
end

-- Legacy + neighbors are live since M2; pass/premium stay 1 until M4.
local function computeIncomeWithMults(state: Types.PlayerState, mults: Types.Multipliers): number
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		return 0
	end
	return Economy.IncomePerSecond(state.slots, eraConfig, Catalog.GetGameConfig(), mults)
end

-- The live rate ticks/HUD run on: legacy + neighbors active since M2, pass/premium 1 until M4.
local function computeLiveIncomePerSecond(state: Types.PlayerState): number
	local gameConfig = Catalog.GetGameConfig()
	return computeIncomeWithMults(state, {
		legacy = Economy.LegacyMult(state.legacy, gameConfig),
		pass = 1,
		premium = 1,
		neighbors = Economy.NeighborsMult(#Players:GetPlayers(), gameConfig),
	})
end

-- The rate incomeAtSave persists — the ONLY code path that computes it (tick rule,
-- RefreshPersistedRate, and the ApplyOfflineGrant restamp all call this). Differs from the
-- live rate twice by design: no Studio debug multiplier (offline grants are never
-- debug-inflated, M2 contract) and neighbors pinned to 1 (lead ruling: a live-social bonus,
-- not an away bonus — also closes idling in a full server right before logout).
local function computePersistedIncomePerSecond(state: Types.PlayerState): number
	local gameConfig = Catalog.GetGameConfig()
	return computeIncomeWithMults(state, {
		legacy = Economy.LegacyMult(state.legacy, gameConfig),
		pass = 1,
		premium = 1,
		neighbors = 1,
	})
end

-- Reported and live-granted income share the Studio debug multiplier so the HUD matches gains.
local function computeReportedIncomePerSecond(state: Types.PlayerState): number
	local incomePerSecond = computeLiveIncomePerSecond(state)
	if isStudio then
		incomePerSecond *= Catalog.GetGameConfig().debug.studioIncomeMultiplier
	end
	return incomePerSecond
end

local function grantIncome(seconds: number): ()
	local debugMultiplier = Catalog.GetGameConfig().debug.studioIncomeMultiplier
	local now = os.time()
	for _, player in Players:GetPlayers() do
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		state.stats.playtimeSeconds += seconds
		-- Tick rule (M2): keep persistence-facing fields fresh every tick so whatever save
		-- ProfileStore fires next (auto-save, final save, shutdown) is always correct. The
		-- persisted rate deliberately differs from the granted one (see the compute helpers).
		state.lastSeen = now
		state.incomeAtSave = computePersistedIncomePerSecond(state)
		local grantPerSecond = computeLiveIncomePerSecond(state)
		if isStudio then
			grantPerSecond *= debugMultiplier
		end
		if grantPerSecond > 0 then
			local earned = grantPerSecond * seconds
			state.cash += earned
			state.stats.totalCashAllTime += earned
			player:SetAttribute("Cash", state.cash)
			getDirtyRecord(player).cash = true
		end
	end
end

local function flushDeltas(): ()
	for player, record in dirtyRecords do
		if not (record.cash or record.income or next(record.slotIds) ~= nil) then
			continue
		end
		local state = DataService.GetState(player)
		if state == nil then
			dirtyRecords[player] = nil
			continue
		end
		local delta: Types.Delta = { kind = "delta" }
		if record.cash then
			delta.cash = state.cash
		end
		if record.income then
			delta.incomePerSecond = computeReportedIncomePerSecond(state)
		end
		if next(record.slotIds) ~= nil then
			local slots: { [string]: Types.SlotState } = {}
			for slotId in record.slotIds do
				local slotState = state.slots[slotId]
				if slotState ~= nil then
					slots[slotId] = { level = slotState.level }
				end
			end
			delta.slots = slots
		end
		record.cash = false
		record.income = false
		table.clear(record.slotIds)
		RemoteService.FireClient(player, "StateChanged", delta)
	end
end

-- The neighbors multiplier moves with the server population, so everyone's displayed rate is
-- stale the moment a player joins or leaves. Order-independent: only marks display dirty.
local function markAllIncomeDirty(): ()
	for _, player in Players:GetPlayers() do
		if DataService.GetState(player) ~= nil then
			getDirtyRecord(player).income = true
		end
	end
end

local EconomyService = {}

-- Duplicate snapshots are harmless by contract: sent proactively after plot claim (Main calls
-- this) and again whenever the client fires RequestSnapshot once its listener is ready.
function EconomyService.SendSnapshot(player: Player): ()
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	local eraConfig = Catalog.GetEraConfig(state.era)
	local plotIndexValue = player:GetAttribute("PlotIndex")
	-- One-shot: consumed by the first snapshot after the grant so later duplicates (or the
	-- client's own RequestSnapshot) never re-show the card. Missing the proactive snapshot is
	-- safe — remote firings queue per client until its listener connects.
	local welcomeBack = pendingWelcomeBack[player]
	pendingWelcomeBack[player] = nil
	local snapshot: Types.Snapshot = {
		kind = "snapshot",
		plotIndex = if typeof(plotIndexValue) == "number" then plotIndexValue else 0,
		eraName = if eraConfig ~= nil then eraConfig.name else "",
		state = state,
		incomePerSecond = computeReportedIncomePerSecond(state),
		welcomeBack = welcomeBack,
	}
	player:SetAttribute("Cash", state.cash)
	RemoteService.FireClient(player, "StateChanged", snapshot)
end

-- Main calls this after LoadAsync and before the first snapshot (M2 join orchestration).
-- Deliberately NOT multiplied by the Studio debug income multiplier.
function EconomyService.ApplyOfflineGrant(player: Player): ()
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	local offlineConfig = Catalog.GetGameConfig().offline
	local now = os.time()
	-- lastSeen == 0 marks a first-ever join: nothing was earned, no card.
	if state.lastSeen > 0 then
		local elapsed = math.clamp(now - state.lastSeen, 0, offlineConfig.capSeconds)
		local granted = Economy.OfflineGrant(
			elapsed,
			state.incomeAtSave,
			offlineConfig.capSeconds,
			offlineConfig.efficiency
		)
		if granted > 0 then
			state.cash += granted
			state.stats.totalCashAllTime += granted
			-- The card only appears when the player was away at least the configured minimum
			-- (Game.json v1.3 offline.welcomeBackMinSeconds) AND the grant was positive.
			if elapsed >= offlineConfig.welcomeBackMinSeconds then
				pendingWelcomeBack[player] = { grantedCash = granted, elapsedSeconds = elapsed }
			end
		end
	end
	-- Stamp immediately (not just on the next tick): a leave before the first tick must not
	-- leave the old lastSeen in place, or rejoining would re-earn the same offline window.
	state.lastSeen = now
	state.incomeAtSave = computePersistedIncomePerSecond(state)
end

-- PlotService calls this after an era mutation (advance/rebirth), before the fresh snapshot:
-- without it, prestige-then-disconnect-before-the-next-tick would persist the COMPLETED era's
-- rate alongside the new era's empty slots, and ApplyOfflineGrant on rejoin would pay up to
-- capSeconds of it into an era that should never see that income.
function EconomyService.RefreshPersistedRate(player: Player): ()
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	state.incomeAtSave = computePersistedIncomePerSecond(state)
	state.lastSeen = os.time()
end

-- PlotService calls this after every purchase/level-up so changes ride the next delta flush.
function EconomyService.MarkDirty(player: Player, fields: DirtyFields): ()
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	local record = getDirtyRecord(player)
	if fields.cash then
		record.cash = true
		player:SetAttribute("Cash", state.cash)
	end
	if fields.income then
		record.income = true
	end
	if fields.slotIds ~= nil then
		for _, slotId in fields.slotIds do
			record.slotIds[slotId] = true
		end
	end
end

-- Main calls this on PlayerRemoving (after PlotService.Release, before DataService.Release).
function EconomyService.Cleanup(player: Player): ()
	dirtyRecords[player] = nil
	pendingWelcomeBack[player] = nil
end

function EconomyService.Init(): ()
	RemoteService.SetHandler("RequestSnapshot", function(player: Player)
		EconomyService.SendSnapshot(player)
	end)
end

function EconomyService.Start(): ()
	local gameConfig = Catalog.GetGameConfig()
	-- tickRate is Hz (spec §7: income ticks at 1 Hz); grant whole ticks, carry the remainder.
	local tickInterval = 1 / gameConfig.tickRate
	local flushInterval = 1 / gameConfig.remotes.stateDeltaHz

	RunService.Heartbeat:Connect(function(deltaTime: number)
		tickAccumulator += deltaTime
		local ticks = 0
		while tickAccumulator >= tickInterval do
			tickAccumulator -= tickInterval
			ticks += 1
		end
		if ticks > 0 then
			grantIncome(ticks * tickInterval)
		end

		flushAccumulator += deltaTime
		if flushAccumulator >= flushInterval then
			-- Reset instead of carrying the remainder: flushes may run late but never denser
			-- than stateDeltaHz, which is the contract's ceiling.
			flushAccumulator = 0
			flushDeltas()
		end
	end)

	-- Display freshness only — per-player lifecycle stays in Main's orchestration.
	Players.PlayerAdded:Connect(markAllIncomeDirty)
	Players.PlayerRemoving:Connect(markAllIncomeDirty)
end

return EconomyService
