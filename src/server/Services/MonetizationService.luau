--!strict
-- Game passes, developer products, and the idempotent ProcessReceipt (spec §6,
-- docs/INTERFACES.md "MonetizationService"). Every MarketplaceService call is pcall'd; a
-- Marketplace outage degrades to "no passes applied this session", never to an error.
--
-- Two invariants drive the whole file:
--   * The server never prompts on its own initiative — a prompt exists only as the direct
--     response to a RequestPrompt intent (spec §6 rule 2).
--   * An id of 0 means "not created yet": the item is never queried, never prompted, and
--     never granted, so the game is fully playable before a single product exists.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

-- Config keys, not tunables: the only two entries this service must recognise by name.
local VIP_PASS_KEY = "VIP"
local DOUBLE_OFFLINE_PRODUCT_KEY = "DoubleOffline"

-- Infrastructure retry policy, not game balance (mirrors DataService's precedent).
local MARKETPLACE_RETRY_ATTEMPTS = 3
local MARKETPLACE_RETRY_BASE_SECONDS = 1

-- Server-side world cosmetic (mirrors PlotService's plot-sign constants block): the VIP name
-- tag lives in the world, so its sizing belongs here and not in the client's Theme.
local VIP_TAG_NAME = "VipTag"
local VIP_TAG_TEXT = "VIP"
local VIP_TAG_COLOR = Color3.fromRGB(255, 200, 60)
local VIP_TAG_WIDTH_STUDS = 3
local VIP_TAG_HEIGHT_STUDS = 0.8
local VIP_TAG_OFFSET_STUDS = 2.5
-- A character can replicate its Head a frame or two after CharacterAdded; give up quietly
-- rather than leaving a thread parked forever.
local HEAD_WAIT_SECONDS = 5

local characterConnections: { [Player]: RBXScriptConnection } = {}

-- Yields. Retries transient Marketplace failures (spec §11); returns ok plus the call's value.
local function callWithRetry<T>(description: string, call: () -> T): (boolean, T?)
	for attempt = 1, MARKETPLACE_RETRY_ATTEMPTS do
		local ok, result = pcall(call)
		if ok then
			return true, result
		end
		warn(`[MonetizationService] {description} failed (attempt {attempt}): {result}`)
		if attempt < MARKETPLACE_RETRY_ATTEMPTS then
			task.wait(MARKETPLACE_RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return false, nil
end

local function fireFx(player: Player, payload: Types.FxEvent): ()
	RemoteService.FireClient(player, "FxEvent", payload)
end

-- Creates or removes the tag to match the player's current VIP state; safe to call at any
-- time and as often as needed (both directions are idempotent).
local function applyVipTag(player: Player): ()
	local character = player.Character
	if character == nil then
		return
	end
	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local state = DataService.GetState(player)
	local isVip = state ~= nil and state.passes[VIP_PASS_KEY] == true
	local existing = head:FindFirstChild(VIP_TAG_NAME)
	if not isVip then
		if existing ~= nil then
			existing:Destroy()
		end
		return
	end
	if existing ~= nil then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = VIP_TAG_NAME
	billboard.Size = UDim2.fromScale(VIP_TAG_WIDTH_STUDS, VIP_TAG_HEIGHT_STUDS)
	billboard.StudsOffset = Vector3.new(0, VIP_TAG_OFFSET_STUDS, 0)
	local label = Instance.new("TextLabel")
	label.Name = "Line1"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	-- Same gold as the VIP plot sign, so the two cosmetics read as one set (spec §6).
	label.TextColor3 = VIP_TAG_COLOR
	label.Text = VIP_TAG_TEXT
	label.Parent = billboard
	billboard.Parent = head
end

local function onCharacterAdded(player: Player, character: Model): ()
	task.spawn(function()
		if character:WaitForChild("Head", HEAD_WAIT_SECONDS) == nil then
			return
		end
		applyVipTag(player)
	end)
end

-- Applies a pass that just became owned mid-session. Idempotent: the join refresh may deliver
-- the same pass again next session, and the prompt signal can fire more than once.
local function applyPass(player: Player, passKey: string): ()
	local state = DataService.GetState(player)
	if state == nil or state.passes[passKey] == true then
		return
	end
	state.passes[passKey] = true
	-- Income multipliers move immediately, including the rate that persists for offline pay.
	EconomyService.RefreshPersistedRate(player)
	EconomyService.MarkDirty(player, { income = true })
	-- VIP is the only pass with cosmetics today; calling this for any pass is harmless.
	PlotService.RefreshCosmetics(player)
	applyVipTag(player)
	fireFx(player, { kind = "passGranted", passKey = passKey })
end

local function findProductDefById(productId: number): Types.ProductDef?
	for _, productDef in Catalog.GetMonetizationConfig().products do
		if productDef.id ~= 0 and productDef.id == productId then
			return productDef
		end
	end
	return nil
end

local function findPassDefById(gamePassId: number): Types.PassDef?
	for _, passDef in Catalog.GetMonetizationConfig().passes do
		if passDef.id ~= 0 and passDef.id == gamePassId then
			return passDef
		end
	end
	return nil
end

-- Computes and applies a product's cash grant to the in-memory profile. Returns the granted
-- amount, or nil when the grant could not be computed (the caller answers NotProcessedYet so
-- Roblox retries later). The player-visible effects (analytics, FxEvent) are deliberately NOT
-- fired here: they belong after the save succeeds, because a failed save rolls this back.
local function grantProduct(
	player: Player,
	state: Types.PlayerState,
	productDef: Types.ProductDef,
	purchaseId: string
): number?
	local granted: number
	if productDef.key == DOUBLE_OFFLINE_PRODUCT_KEY then
		granted = EconomyService.ConsumeDoubleOfflineGrant(player)
		if granted <= 0 then
			-- Only reachable when Roblox retries a receipt after the player rejoined: the
			-- session's offline record is gone. Granting 0 beats an infinite retry loop.
			warn(
				`[MonetizationService] DoubleOffline receipt {purchaseId} for {player.Name}`
					.. ` had no pending offline grant; granting 0`
			)
		end
	else
		local minutes = productDef.minutes
		if minutes == nil then
			warn(`[MonetizationService] product '{productDef.key}' has no minutes; cannot grant`)
			return nil
		end
		local eraConfig = Catalog.GetEraConfig(state.era)
		if eraConfig == nil then
			warn(`[MonetizationService] era {state.era} config missing; cannot price a pack`)
			return nil
		end
		local monetizationConfig = Catalog.GetMonetizationConfig()
		-- The persisted-rate flavour (no Studio debug multiplier, neighbors pinned to 1), so a
		-- Studio playtest cannot inflate a pack. Computed live rather than read from
		-- state.incomeAtSave: the shop preview publishes this same number, so the row cannot
		-- advertise one amount and the receipt grant another.
		granted = Economy.PackGrant(
			minutes,
			EconomyService.GetPersistedIncomePerSecond(player),
			Economy.EraSlotCostTotal(eraConfig),
			-- Per-pack ceiling, falling back to the config-wide default (M4 amendment): a
			-- single shared cap made every pack grant the same amount past early-era.
			productDef.capFraction or monetizationConfig.packCapFractionOfEraSlotCost
		)
	end

	if granted > 0 then
		state.cash += granted
		state.stats.totalCashAllTime += granted
		EconomyService.MarkDirty(player, { cash = true })
	end
	return granted
end

-- Undoes grantProduct when the receipt could not be persisted. Without this the cash can still
-- reach the DataStore via ProfileStore's autosave while the PurchaseId does not, and Roblox's
-- retry would grant a second time.
local function rollbackGrant(
	player: Player,
	state: Types.PlayerState,
	productDef: Types.ProductDef,
	granted: number
): ()
	if granted > 0 then
		-- Floored at 0: the same retry yield lets the player spend the granted cash before the
		-- reversal lands, and an exact subtraction would then render a negative balance in the
		-- HUD. Forgiving the shortfall is the cheaper failure — this path only runs when a
		-- purchase is being handed back to Roblox to retry.
		state.cash = math.max(0, state.cash - granted)
		-- totalCashAllTime only ever grows, so the exact reversal cannot underflow it.
		state.stats.totalCashAllTime -= granted
		EconomyService.MarkDirty(player, { cash = true })
	end
	if productDef.key == DOUBLE_OFFLINE_PRODUCT_KEY then
		-- Put the offer back so the retried receipt (or a re-prompt) can grant it once.
		EconomyService.ReleaseDoubleOfflineGrant(player)
	end
end

-- The decision order is frozen in docs/INTERFACES.md; every early return is a deliberate
-- "let Roblox retry" rather than an eaten purchase.
local function handleReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local productDef = findProductDefById(receiptInfo.ProductId)
	if productDef == nil then
		-- A product created on the Creator Hub whose id was never pasted into the config must
		-- not be silently eaten; Roblox will re-deliver it once the config catches up.
		warn(`[MonetizationService] unknown ProductId {receiptInfo.ProductId}; not processed`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local state = DataService.GetState(player)
	if state == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	for _, processedId in state.processedReceipts do
		if processedId == purchaseId then
			-- Already granted in this profile; answering PurchaseGranted stops the retries.
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	local granted = grantProduct(player, state, productDef, purchaseId)
	if granted == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	table.insert(state.processedReceipts, purchaseId)
	local limit = Catalog.GetMonetizationConfig().receiptHistoryLimit
	while #state.processedReceipts > limit do
		-- FIFO trim: the only ids this can evict are old ones Roblox was already told
		-- PurchaseGranted for, and Roblox never re-delivers a granted receipt.
		table.remove(state.processedReceipts, 1)
	end

	-- The grant and the receipt id ride the same profile write. If that write is refused, the
	-- in-memory grant must be undone before we ask Roblox to retry: an active session can still
	-- autosave the cash on its own, and the retry would then grant it a second time.
	if not DataService.SaveAsync(player) then
		-- Remove by value, not by position: SaveAsync's retry backoff yields, so a second
		-- receipt for this player can append its own id meanwhile, and a bare table.remove
		-- would pop THAT id and leave ours behind — Roblox would then find ours already
		-- recorded and retire the purchase without ever granting it.
		local index = table.find(state.processedReceipts, purchaseId)
		if index ~= nil then
			table.remove(state.processedReceipts, index)
		end
		rollbackGrant(player, state, productDef, granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	AnalyticsService.LogCashSource(player, granted, state.cash, "IAP", `product:{productDef.key}`)
	fireFx(player, { kind = "purchase", productKey = productDef.key, grantedCash = granted })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local ok, decision = pcall(handleReceipt, receiptInfo)
	if not ok then
		warn(`[MonetizationService] ProcessReceipt errored: {decision}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision :: Enum.ProductPurchaseDecision
end

local function onRequestPrompt(player: Player, key: string): ()
	local state = DataService.GetState(player)
	if state == nil then
		return
	end
	-- Keys are unique across both tables, so one namespace resolves passes first, then products.
	local passDef = Catalog.GetPassDef(key)
	if passDef ~= nil then
		if passDef.id == 0 or state.passes[passDef.key] == true then
			return -- not created yet, or already owned: nothing to sell
		end
		-- Prompts are deliberately NOT retried: a retry would re-open the purchase dialog the
		-- player just dismissed. A failed prompt is logged and forgotten.
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, passDef.id)
		end)
		if not ok then
			warn(`[MonetizationService] PromptGamePassPurchase failed for {player.Name}: {err}`)
		end
		return
	end
	local productDef = Catalog.GetProductDef(key)
	if productDef == nil or productDef.id == 0 then
		return
	end
	local isDoubleOffline = productDef.key == DOUBLE_OFFLINE_PRODUCT_KEY
	if isDoubleOffline and EconomyService.ReserveDoubleOfflineGrant(player) == nil then
		-- The one contextual offer exists only while an unused offline grant is pending, and
		-- only for one dialog at a time: reserving here is what stops a client opening two.
		return
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productDef.id)
	end)
	if not ok then
		warn(`[MonetizationService] PromptProductPurchase failed for {player.Name}: {err}`)
		if isDoubleOffline then
			EconomyService.ReleaseDoubleOfflineGrant(player)
		end
	end
end

local MonetizationService = {}

-- Yields. Main calls this after LoadAsync and before ApplyOfflineGrant, so the offline grant
-- already reflects Offline Pro. One query per non-zero pass id per session — never per tick.
function MonetizationService.RefreshPassesAsync(player: Player): ()
	for _, passDef in Catalog.GetMonetizationConfig().passes do
		if passDef.id == 0 then
			continue
		end
		local ok, owns = callWithRetry(`UserOwnsGamePassAsync {passDef.key}`, function(): boolean
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passDef.id)
		end)
		-- Re-read after the yield: the player may have left, or the profile been released.
		local state = DataService.GetState(player)
		if state == nil or player.Parent == nil then
			return
		end
		if ok then
			-- Write the API's answer verbatim, including false — refunds and revokes must
			-- take effect. On failure keep the persisted value: never downgrade on an error.
			state.passes[passDef.key] = owns == true
		end
	end
	-- The character may already exist by the time the queries finish.
	applyVipTag(player)
end

function MonetizationService.Init(): ()
	-- Assigned exactly once, at Init, per Roblox's ProcessReceipt contract.
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			local passDef = findPassDefById(gamePassId)
			if passDef == nil then
				return -- a pass from another experience, or one not yet in the config
			end
			applyPass(player, passDef.key)
		end
	)

	-- A declined DoubleOffline dialog frees the reservation so the card can offer it again.
	-- (Successful purchases are settled by ProcessReceipt, which is the only authority on a
	-- completed sale; this signal carries no receipt.)
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, isPurchased: boolean)
			if isPurchased then
				return
			end
			local productDef = findProductDefById(productId)
			if productDef == nil or productDef.key ~= DOUBLE_OFFLINE_PRODUCT_KEY then
				return
			end
			local player = Players:GetPlayerByUserId(userId)
			if player ~= nil then
				EconomyService.ReleaseDoubleOfflineGrant(player)
			end
		end
	)

	-- Payload types are already validated by RemoteService; the cast narrows the varargs.
	RemoteService.SetHandler("RequestPrompt", function(player: Player, key: any)
		onRequestPrompt(player, key :: string)
	end)
end

function MonetizationService.Start(): ()
	-- Cosmetic listeners only; per-player lifecycle stays in Main's orchestration, so these
	-- are deliberately order-independent.
	local function trackPlayer(player: Player): ()
		characterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end)
		local character = player.Character
		if character ~= nil then
			onCharacterAdded(player, character)
		end
	end

	Players.PlayerAdded:Connect(trackPlayer)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		-- Optional annotation: map indexing is non-optional under the old solver.
		local connection: RBXScriptConnection? = characterConnections[player]
		if connection ~= nil then
			connection:Disconnect()
			characterConnections[player] = nil
		end
	end)
end

return MonetizationService
