--!strict
-- Thin wrapper over Roblox's AnalyticsService for the frozen M4 taxonomy
-- (docs/INTERFACES.md "Analytics taxonomy"). Analytics is strictly observational: every call
-- is pcall'd on a detached thread, and a missing service or enum degrades the whole module to
-- a no-op, so a telemetry outage can never break a purchase, a build, or a prestige.
--
-- Income ticks are deliberately never logged (1 Hz per player would swamp the event quota);
-- one RequestLevelUp granting n levels logs exactly one event.

local RobloxAnalytics = game:GetService("AnalyticsService")

-- Currency names are part of the taxonomy and appear verbatim on the dashboards.
local CASH_CURRENCY = "cash"
local LEGACY_CURRENCY = "legacy"
-- Progression path name for era advances/rebirths; the completed era index is the level.
local ERA_PROGRESSION_PATH = "EraProgression"

-- Infrastructure retry policy, not game balance (mirrors DataService's precedent): a single
-- retry covers a transient backend hiccup; anything worse is dropped rather than queued.
local LOG_RETRY_ATTEMPTS = 2
local LOG_RETRY_BASE_SECONDS = 1

-- Resolved once in Init. Enum lookups are pcall'd because an older engine may not expose them,
-- and reading a missing member of the Enum tree throws rather than returning nil.
local flowSink: Enum.AnalyticsEconomyFlowType? = nil
local flowSource: Enum.AnalyticsEconomyFlowType? = nil
local progressionComplete: Enum.AnalyticsProgressionType? = nil
local transactionTypeNames: { [string]: string } = {}

-- The taxonomy's four transaction types; resolved through the enum so a typo or a renamed
-- member is caught at boot instead of silently producing an unqueryable event name.
local TRANSACTION_TYPE_KEYS = { "Shop", "TimedReward", "IAP", "Gameplay" }

export type TransactionType = "Shop" | "TimedReward" | "IAP" | "Gameplay"

-- Runs the logging call off the caller's thread: analytics must never add latency to (or
-- yield inside) a purchase or a build path.
local function logAsync(description: string, call: () -> ()): ()
	task.spawn(function()
		for attempt = 1, LOG_RETRY_ATTEMPTS do
			-- The wrapper returns nil so pcall's result tuple carries the error message; a
			-- zero-return call would make `pcall` a single-value expression.
			local ok, err = pcall(function(): any?
				call()
				return nil
			end)
			if ok then
				return
			end
			if attempt == LOG_RETRY_ATTEMPTS then
				warn(`[AnalyticsService] {description} failed after {attempt} attempts: {err}`)
				return
			end
			task.wait(LOG_RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end)
end

-- Roblox's LogEconomyEvent takes the transaction type as a string (the enum item's Name).
local function logEconomy(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType?,
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: TransactionType,
	itemSku: string
): ()
	local transactionName = transactionTypeNames[transactionType]
	if flowType == nil or transactionName == nil then
		return
	end
	-- Amounts and balances are integers by contract; the dashboards reject fractional cash.
	local roundedAmount = math.floor(amount)
	local roundedBalance = math.floor(endingBalance)
	if roundedAmount <= 0 then
		return
	end
	logAsync(`LogEconomyEvent {itemSku}`, function()
		RobloxAnalytics:LogEconomyEvent(
			player,
			flowType :: Enum.AnalyticsEconomyFlowType,
			currency,
			roundedAmount,
			roundedBalance,
			transactionName,
			itemSku
		)
	end)
end

local AnalyticsService = {}

-- Cash spent by the player (slot buys, level-ups). Always transaction type Shop.
function AnalyticsService.LogCashSink(
	player: Player,
	amount: number,
	endingBalance: number,
	itemSku: string
): ()
	logEconomy(player, flowSink, CASH_CURRENCY, amount, endingBalance, "Shop", itemSku)
end

function AnalyticsService.LogCashSource(
	player: Player,
	amount: number,
	endingBalance: number,
	transactionType: TransactionType,
	itemSku: string
): ()
	logEconomy(player, flowSource, CASH_CURRENCY, amount, endingBalance, transactionType, itemSku)
end

-- Legacy is only ever earned, and only from an era advance or a rebirth.
function AnalyticsService.LogLegacySource(
	player: Player,
	amount: number,
	endingBalance: number,
	itemSku: string
): ()
	logEconomy(player, flowSource, LEGACY_CURRENCY, amount, endingBalance, "Gameplay", itemSku)
end

-- One event per era advance and per rebirth; eraIndex is the era just COMPLETED.
function AnalyticsService.LogEraProgression(
	player: Player,
	eraIndex: number,
	isRebirth: boolean
): ()
	local status = progressionComplete
	if status == nil then
		return
	end
	local levelName = if isRebirth then "rebirth" else "advance"
	logAsync(`LogProgressionEvent era {eraIndex}`, function()
		RobloxAnalytics:LogProgressionEvent(
			player,
			ERA_PROGRESSION_PATH,
			status :: Enum.AnalyticsProgressionType,
			eraIndex,
			levelName
		)
	end)
end

function AnalyticsService.Init(): ()
	local ok, err = pcall(function()
		flowSink = Enum.AnalyticsEconomyFlowType.Sink
		flowSource = Enum.AnalyticsEconomyFlowType.Source
		progressionComplete = Enum.AnalyticsProgressionType.Complete
		for _, key in TRANSACTION_TYPE_KEYS do
			local item = (Enum.AnalyticsEconomyTransactionType :: any)[key] :: EnumItem
			transactionTypeNames[key] = item.Name
		end
	end)
	if not ok then
		-- Every public function guards on the resolved values, so this leaves the module a
		-- silent no-op rather than erroring on the first purchase.
		warn(`[AnalyticsService] analytics enums unavailable; logging disabled: {err}`)
	end
end

function AnalyticsService.Start(): () end

return AnalyticsService
