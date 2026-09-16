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
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

export type DirtyFields = {
	cash: boolean?,
	income: boolean?,
	slotIds: { string }?,
	settings: boolean?,
	legacyShop: boolean?,
}
type DirtyRecord = {
	cash: boolean,
	income: boolean,
	slotIds: { [string]: boolean },
	settings: boolean,
	legacyShop: boolean,
}

-- Studio-only playtest lever (same pattern as DataService's ForceLoadFailure): Legacy only moves
-- on an era advance, so a numeric Workspace attribute set in the Properties pane stands in for
-- one. Consumed by the 1 Hz tick and reset to 0. Ignored outside Studio.
local GRANT_LEGACY_ATTRIBUTE = "GrantLegacy"
-- Same lever for cash (M7): levelling a building to 100 at real pace takes hours, and the
-- stage-growth check needs every base milestone in one sitting.
local GRANT_CASH_ATTRIBUTE = "GrantCash"

-- Session-scoped record of the offline grant this player received on join, so the welcome-back
-- card's "Double it" product can be honoured for the whole session (the card can be tapped a
-- while after the snapshot). Single use: ConsumeDoubleOfflineGrant flips `used`.
-- reserved: a purchase dialog for DoubleOffline is open right now. Reserving at prompt time
-- (not at receipt time) is what stops a modified client opening two dialogs and paying twice
-- for one grant; a declined or failed prompt releases the reservation.
-- previousPending: the persisted amount an EARLIER session's still-open dialog left behind,
-- stashed while this session's dialog is up so a decline puts it back rather than zeroing it.
type OfflineRecord = { amount: number, reserved: boolean, used: boolean, previousPending: number }

-- Which store a DoubleOffline receipt settled from, so a rolled-back grant can put the amount
-- back where it came from: this session's reserved record, the persisted amount an earlier
-- session's dialog left behind (M5 schema v2), or nothing.
export type DoubleOfflineSource = "session" | "persisted" | "none"

local dirtyRecords: { [Player]: DirtyRecord } = {}
local pendingWelcomeBack: { [Player]: Types.WelcomeBack } = {}
local offlineRecords: { [Player]: OfflineRecord } = {}
-- The income tick must not touch a player whose join sequence is still running: passes are
-- refreshed with a yielding Marketplace call before ApplyOfflineGrant, and a tick landing in
-- that window would restamp lastSeen and silently zero the offline grant. It also stops income
-- accruing into a plot the player has not been given yet.
local joinComplete: { [Player]: boolean } = {}
local isStudio = RunService:IsStudio()
local tickAccumulator = 0
local flushAccumulator = 0

local function getDirtyRecord(player: Player): DirtyRecord
	local record = dirtyRecords[player]
	if record == nil then
		record =
			{ cash = false, income = false, slotIds = {}, settings = false, legacyShop = false }
		dirtyRecords[player] = record
	end
	return record
end

-- Passes and Premium are account properties, not session state, so they multiply the live,
-- the reported AND the persisted rate (M4 contract): offline earnings carry them too.
-- The monetization config is passed in rather than fetched here: grantIncome resolves it once
-- per tick instead of four times per player.
local function computePassMult(
	state: Types.PlayerState,
	monetizationConfig: Types.MonetizationConfig
): number
	return Economy.PassMult(state.passes, monetizationConfig)
end

local function computePremiumMult(
	player: Player,
	monetizationConfig: Types.MonetizationConfig
): number
	return Economy.PremiumMult(
		player.MembershipType == Enum.MembershipType.Premium,
		monetizationConfig
	)
end

-- Extra Milestone (M6) changes which levels double a slot, so the owner's list rides along with
-- every income computation rather than the global Game.json list.
local function computeIncomeWithMults(state: Types.PlayerState, mults: Types.Multipliers): number
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		return 0
	end
	local gameConfig = Catalog.GetGameConfig()
	return Economy.IncomePerSecond(
		state.slots,
		eraConfig,
		gameConfig,
		mults,
		Economy.MilestoneLevels(Catalog.GetLegacyShopConfig(), state.legacyShop, gameConfig)
	)
end

-- The live rate ticks/HUD run on: every multiplier active (legacy + neighbors since M2,
-- pass + premium since M4, Founder's perk + Good Neighbours params since M6).
local function computeLiveIncomePerSecond(
	player: Player,
	state: Types.PlayerState,
	monetizationConfig: Types.MonetizationConfig
): number
	local gameConfig = Catalog.GetGameConfig()
	local shopConfig = Catalog.GetLegacyShopConfig()
	local perPlayer, maxBonus = Economy.NeighborsParams(shopConfig, state.legacyShop, gameConfig)
	return computeIncomeWithMults(state, {
		legacy = Economy.LegacyMult(state.legacy, gameConfig),
		perk = Economy.PerkIncomeMult(shopConfig, state.legacyShop),
		pass = computePassMult(state, monetizationConfig),
		premium = computePremiumMult(player, monetizationConfig),
		neighbors = Economy.NeighborsMult(#Players:GetPlayers(), gameConfig, perPlayer, maxBonus),
	})
end

-- The rate incomeAtSave persists — the ONLY code path that computes it (tick rule,
-- RefreshPersistedRate, and the ApplyOfflineGrant restamp all call this). Differs from the
-- live rate twice by design: no Studio debug multiplier (offline grants are never
-- debug-inflated, M2 contract) and neighbors pinned to 1 (lead ruling: a live-social bonus,
-- not an away bonus — also closes idling in a full server right before logout). Passes and
-- Premium DO apply here (M4): they are account properties, so offline earnings carry them —
-- and so does Founder's Blessing (M6), a permanent perk.
local function computePersistedIncomePerSecond(
	player: Player,
	state: Types.PlayerState,
	monetizationConfig: Types.MonetizationConfig
): number
	local gameConfig = Catalog.GetGameConfig()
	return computeIncomeWithMults(state, {
		legacy = Economy.LegacyMult(state.legacy, gameConfig),
		perk = Economy.PerkIncomeMult(Catalog.GetLegacyShopConfig(), state.legacyShop),
		pass = computePassMult(state, monetizationConfig),
		premium = computePremiumMult(player, monetizationConfig),
		neighbors = 1,
	})
end

-- Reported and live-granted income share the Studio debug multiplier so the HUD matches gains.
local function computeReportedIncomePerSecond(player: Player, state: Types.PlayerState): number
	local incomePerSecond =
		computeLiveIncomePerSecond(player, state, Catalog.GetMonetizationConfig())
	if isStudio then
		incomePerSecond *= Catalog.GetGameConfig().debug.studioIncomeMultiplier
	end
	return incomePerSecond
end

local function grantIncome(seconds: number): ()
	local debugMultiplier = Catalog.GetGameConfig().debug.studioIncomeMultiplier
	local monetizationConfig = Catalog.GetMonetizationConfig()
	local now = os.time()
	for _, player in Players:GetPlayers() do
		local state = DataService.GetState(player)
		-- Skip anyone mid-join: restamping lastSeen here would destroy their offline grant.
		if state == nil or not joinComplete[player] then
			continue
		end
		state.stats.playtimeSeconds += seconds
		-- Tick rule (M2): keep persistence-facing fields fresh every tick so whatever save
		-- ProfileStore fires next (auto-save, final save, shutdown) is always correct. The
		-- persisted rate deliberately differs from the granted one (see the compute helpers).
		state.lastSeen = now
		state.incomeAtSave = computePersistedIncomePerSecond(player, state, monetizationConfig)
		local grantPerSecond = computeLiveIncomePerSecond(player, state, monetizationConfig)
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

-- The live persisted rate: what a cash pack is priced against and what the shop previews.
-- Deliberately NOT state.incomeAtSave — that is a persistence field the 1 Hz tick restamps,
-- so publishing it handed the client a rate one purchase out of date, and 0 for a whole era
-- after an advance (the advance restamps it against the new era's empty slots). Exposed as
-- EconomyService.GetPersistedIncomePerSecond so the receipt path prices with this same number.
local function livePersistedRate(player: Player): number
	local state = DataService.GetState(player)
	if state == nil then
		return 0
	end
	return computePersistedIncomePerSecond(player, state, Catalog.GetMonetizationConfig())
end

local function flushDeltas(): ()
	for player, record in dirtyRecords do
		if
			not (
				record.cash
				or record.income
				or record.settings
				or record.legacyShop
				or next(record.slotIds) ~= nil
			)
		then
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
			delta.incomePerSecond = computeReportedIncomePerSecond(player, state)
			-- The rate the shop prices against. Computed live, NOT read from state.incomeAtSave:
			-- that field is only restamped by the 1 Hz tick, so publishing it sent the client a
			-- rate one purchase out of date — and 0 for a whole era after an advance, because
			-- the advance restamps it against the new era's empty slots. The receipt path calls
			-- this same function, so preview and grant agree exactly.
			delta.persistedIncomePerSecond = livePersistedRate(player)
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
		if record.settings then
			-- Whole table by contract (M3): a copy, so the client's merge never aliases state.
			delta.settings = { music = state.settings.music, sfx = state.settings.sfx }
		end
		if record.legacyShop then
			-- Whole table by contract (M6), copied so the client's merge never aliases state.
			delta.legacyShop =
				{ spent = state.legacyShop.spent, perks = table.clone(state.legacyShop.perks) }
		end
		record.cash = false
		record.income = false
		record.settings = false
		record.legacyShop = false
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
		incomePerSecond = computeReportedIncomePerSecond(player, state),
		persistedIncomePerSecond = livePersistedRate(player),
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
	local gameConfig = Catalog.GetGameConfig()
	local offlineConfig = gameConfig.offline
	local now = os.time()
	-- Offline Pro widens the window and removes the efficiency haircut (M4); Long Memory (M6)
	-- adds hours to whichever cap applies and never touches efficiency. Main refreshes passes
	-- before calling this, so state.passes is already authoritative for the session.
	local pro = state.passes.OfflinePro == true
	local cap = Economy.OfflineCapSeconds(
		state.passes,
		state.legacyShop,
		Catalog.GetLegacyShopConfig(),
		gameConfig
	)
	local efficiency = if pro then offlineConfig.efficiencyOfflinePro else offlineConfig.efficiency
	-- lastSeen == 0 marks a first-ever join: nothing was earned, no card.
	if state.lastSeen > 0 then
		local elapsed = math.clamp(now - state.lastSeen, 0, cap)
		local granted = Economy.OfflineGrant(elapsed, state.incomeAtSave, cap, efficiency)
		if isStudio then
			-- Playtest diagnostic (Studio only): the grant is invisible next to the ×debug
			-- income, so print the inputs the checklist asks the human to sanity-check.
			print(
				`[EconomyService] offline grant for {player.Name}: away {elapsed}s, `
					.. `saved rate {state.incomeAtSave}/s, cap {cap}s, efficiency {efficiency}, `
					.. `granted {granted}`
			)
		end
		if granted > 0 then
			state.cash += granted
			state.stats.totalCashAllTime += granted
			-- Recorded for the whole session so the welcome-back card's "Double it" product
			-- can still be honoured minutes later; a single use, cleared in Cleanup.
			offlineRecords[player] =
				{ amount = granted, reserved = false, used = false, previousPending = 0 }
			AnalyticsService.LogCashSource(player, granted, state.cash, "TimedReward", "offline")
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
	state.incomeAtSave =
		computePersistedIncomePerSecond(player, state, Catalog.GetMonetizationConfig())
	-- Join sequence over: the income tick may now touch this player (see joinComplete).
	joinComplete[player] = true
end

-- Claims the offer for one purchase dialog. nil when there is nothing to sell or a dialog is
-- already open, so two RequestPrompts can never produce two chargeable prompts for one grant.
-- The reservation is also persisted (pendingDoubleOfflineAmount): a player who leaves with the
-- dialog open and completes it later is still charged, and the receipt must find the amount.
function EconomyService.ReserveDoubleOfflineGrant(player: Player): number?
	local record = offlineRecords[player]
	local state = DataService.GetState(player)
	if record == nil or state == nil or record.used or record.reserved then
		return nil
	end
	record.reserved = true
	record.previousPending = state.pendingDoubleOfflineAmount
	state.pendingDoubleOfflineAmount = record.amount
	-- Queue the write now rather than waiting for the next autosave: the reservation only
	-- matters if the player leaves with the dialog open, which can be seconds away.
	DataService.SaveAsync(player)
	return record.amount
end

-- Returns a reservation to the pool: the player declined the dialog or the prompt call failed.
-- Nothing was charged, so the persisted field goes back to whatever an earlier session's
-- dialog left there (its receipt may still arrive). `used` is untouched: rollback
-- re-grantability is RestoreDoubleOfflineGrant's job.
function EconomyService.ReleaseDoubleOfflineGrant(player: Player): ()
	local state = DataService.GetState(player)
	local record = offlineRecords[player]
	if state ~= nil then
		state.pendingDoubleOfflineAmount = if record ~= nil then record.previousPending else 0
	end
	if record == nil then
		return
	end
	record.reserved = false
end

-- Settles one DoubleOffline receipt: this session's reserved record first; else the persisted
-- amount an earlier session's dialog left behind; else 0 (the receipt handler grants 0 rather
-- than retrying forever). Every path zeroes the persisted field, so a receipt can never be paid
-- twice. Also returns which source paid, for rollback.
function EconomyService.ConsumeDoubleOfflineGrant(player: Player): (number, DoubleOfflineSource)
	local state = DataService.GetState(player)
	local record = offlineRecords[player]
	if record ~= nil and record.reserved and not record.used then
		record.used = true
		record.reserved = false
		if state ~= nil then
			state.pendingDoubleOfflineAmount = 0
		end
		return record.amount, "session"
	end
	if state ~= nil and state.pendingDoubleOfflineAmount > 0 then
		local amount = state.pendingDoubleOfflineAmount
		state.pendingDoubleOfflineAmount = 0
		return amount, "persisted"
	end
	if state ~= nil then
		state.pendingDoubleOfflineAmount = 0
	end
	return 0, "none"
end

-- Undoes ConsumeDoubleOfflineGrant after a failed receipt save: the Robux charge stands and
-- Roblox will redeliver the receipt, so the amount goes back to exactly the source it came from
-- (the session record stays reserved — its dialog completed — and the persisted field is
-- restored so a rejoin-then-redeliver still finds it).
function EconomyService.RestoreDoubleOfflineGrant(
	player: Player,
	source: DoubleOfflineSource,
	amount: number
): ()
	local state = DataService.GetState(player)
	if source == "session" then
		local record = offlineRecords[player]
		if record ~= nil then
			record.used = false
			record.reserved = true
		end
	elseif source == "none" then
		return
	end
	if state ~= nil then
		state.pendingDoubleOfflineAmount = amount
	end
end

-- PlotService calls this after an era mutation (advance/rebirth), before the fresh snapshot:
-- without it, prestige-then-disconnect-before-the-next-tick would persist the COMPLETED era's
-- rate alongside the new era's empty slots, and ApplyOfflineGrant on rejoin would pay up to
-- capSeconds of it into an era that should never see that income.
-- Public form of livePersistedRate: MonetizationService prices cash packs with this, so the
-- receipt grants exactly what the shop row previewed. Never read state.incomeAtSave for that.
function EconomyService.GetPersistedIncomePerSecond(player: Player): number
	return livePersistedRate(player)
end

function EconomyService.RefreshPersistedRate(player: Player): ()
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	state.incomeAtSave =
		computePersistedIncomePerSecond(player, state, Catalog.GetMonetizationConfig())
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
	if fields.settings then
		record.settings = true
	end
	if fields.legacyShop then
		record.legacyShop = true
	end
end

-- Studio lever: GrantLegacy > 0 on Workspace pays that much Legacy to every loaded player once,
-- then resets itself. Legacy is a snapshot-only field, so a fresh snapshot follows the rate
-- refresh (a delta could not carry it).
local function consumeGrantLegacyLever(): ()
	local value = workspace:GetAttribute(GRANT_LEGACY_ATTRIBUTE)
	-- NaN/inf are refused too: Studio with API access writes a real profile, and a corrupted
	-- legacy field would survive the session.
	if typeof(value) ~= "number" or value <= 0 or value ~= value or value == math.huge then
		return
	end
	workspace:SetAttribute(GRANT_LEGACY_ATTRIBUTE, 0)
	local granted = 0
	for _, player in Players:GetPlayers() do
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		state.legacy += value
		EconomyService.RefreshPersistedRate(player)
		EconomyService.MarkDirty(player, { income = true })
		EconomyService.SendSnapshot(player)
		granted += 1
	end
	warn(
		`[EconomyService] {GRANT_LEGACY_ATTRIBUTE} lever: granted {value} Legacy to {granted}`
			.. ` loaded player(s); attribute reset to 0`
	)
end

-- Studio lever: GrantCash > 0 on Workspace pays that much cash to every loaded player once,
-- then resets itself. Cash rides the normal dirty/delta path, so no snapshot is needed.
local function consumeGrantCashLever(): ()
	local value = workspace:GetAttribute(GRANT_CASH_ATTRIBUTE)
	if typeof(value) ~= "number" or value <= 0 or value ~= value or value == math.huge then
		return
	end
	workspace:SetAttribute(GRANT_CASH_ATTRIBUTE, 0)
	local granted = 0
	for _, player in Players:GetPlayers() do
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		state.cash += value
		player:SetAttribute("Cash", state.cash)
		EconomyService.MarkDirty(player, { cash = true })
		granted += 1
	end
	warn(
		`[EconomyService] {GRANT_CASH_ATTRIBUTE} lever: granted {value} cash to {granted}`
			.. ` loaded player(s); attribute reset to 0`
	)
end

-- Main calls this on PlayerRemoving (after PlotService.Release, before DataService.Release).
function EconomyService.Cleanup(player: Player): ()
	dirtyRecords[player] = nil
	pendingWelcomeBack[player] = nil
	offlineRecords[player] = nil
	joinComplete[player] = nil
end

function EconomyService.Init(): ()
	RemoteService.SetHandler("RequestSnapshot", function(player: Player)
		if DataService.GetState(player) == nil then
			-- Safe mode (M5): the client's boot request may land before, during, or after the
			-- first load attempt; whichever it is, it must end with a status or a snapshot.
			local status = DataService.GetLoadStatus(player)
			if status ~= nil then
				RemoteService.FireClient(player, "StateChanged", status)
			end
			return
		end
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
			if isStudio then
				consumeGrantLegacyLever()
				consumeGrantCashLever()
			end
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
