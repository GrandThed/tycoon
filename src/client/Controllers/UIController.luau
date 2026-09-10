--!strict
-- Owns the HUD. The client is a display and input device: the local model below is
-- replaced by server snapshots and patched by deltas, and every button press becomes a
-- remote intent. Cash and income are never computed here; Build-panel previews and the
-- Legacy previews use the shared pure Economy module and are overwritten by the next
-- server push (docs/INTERFACES.md, M1–M3 client contracts). M3 adds the bottom bar with
-- Legacy/Settings panels, the era-advance screen, the ceremony overlay, the welcome-back
-- card, sound hooks, and the landscape docking layout. M4 adds the Shop panel, the
-- welcome-back "Double it" offer, purchase feedback, and the bonuses readout - all driven
-- by Monetization.json ids, so with every id 0 the HUD is exactly the M3 HUD. M5 adds the
-- data-load safe-mode card: until the first snapshot the HUD is blank (dashes, no bottom
-- bar) behind a LoadScreen driven by LoadStatus payloads, and a failed load offers Retry
-- (RequestRetryLoad) or Leave instead of a kick. M6 turns the Legacy panel into the
-- Legacy shop: RequestBuyPerk intents, the legacyShop delta merge, perkBought / buyPerk
-- feedback, and one automatic (dismissable, non-modal) open of the panel after a
-- ceremony when a tier has become affordable — earned currency, not Robux.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Format = require(sharedFolder:WaitForChild("Format"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local PanelDock = require(uiFolder:WaitForChild("PanelDock"))
local TopBar = require(uiFolder:WaitForChild("TopBar"))
local BottomBar = require(uiFolder:WaitForChild("BottomBar"))
local BuildPanel = require(uiFolder:WaitForChild("BuildPanel"))
local LegacyPanel = require(uiFolder:WaitForChild("LegacyPanel"))
local ShopPanel = require(uiFolder:WaitForChild("ShopPanel"))
local SettingsPanel = require(uiFolder:WaitForChild("SettingsPanel"))
local EraAdvanceScreen = require(uiFolder:WaitForChild("EraAdvanceScreen"))
local Ceremony = require(uiFolder:WaitForChild("Ceremony"))
local WelcomeBackCard = require(uiFolder:WaitForChild("WelcomeBackCard"))
local Toast = require(uiFolder:WaitForChild("Toast"))
local LoadScreen = require(uiFolder:WaitForChild("LoadScreen"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

type Model = {
	plotIndex: number,
	eraName: string,
	state: Types.PlayerState,
	incomePerSecond: number,
	-- The rate the server prices cash packs off (no Studio debug multiplier, neighbors
	-- pinned to 1). Tracked like incomePerSecond and never derived here: only the Shop's
	-- pack preview reads it, and only the server may compute it (wave-2 ruling 4).
	persistedIncomePerSecond: number,
}

type PrestigeKind = "advance" | "rebirth"

type PanelKey = "build" | "legacy" | "shop" | "settings"

-- Every dockable panel exposes this slice; UIController keeps one open at a time.
type DockablePanel = {
	DesignHeight: number,
	SetOpen: (open: boolean) -> (),
	SetLayout: (dock: PanelDock.Dock) -> (),
}

local FIRST_ERA = 1

-- Spec section 6: an item whose id is still 0 does not exist for the player. The Shop
-- button appears only once the human has created at least one item the Shop can list --
-- shopVisible = false products (DoubleOffline) are welcome-back-only, so on their own
-- they must not open an empty panel (wave-2 ruling 6).
local function hasShopListableId(monetization: Types.MonetizationConfig): boolean
	for _, pass in monetization.passes do
		if pass.id ~= 0 then
			return true
		end
	end
	for _, product in monetization.products do
		if product.id ~= 0 and product.shopVisible then
			return true
		end
	end
	return false
end

-- Server-published rate; absent means luau-engineer's snapshot change is not in this
-- build, and a 0 preview understates rather than overstating a real-money item.
local function readPersistedRate(payload: { [string]: any }): number
	local rate = payload.persistedIncomePerSecond
	return if typeof(rate) == "number" then rate else 0
end

-- All UI copy uses displayName (M3 contract); a config that predates it degrades to name.
local function eraDisplayName(eraConfig: Types.EraConfig?, fallback: string): string
	if eraConfig == nil then
		return fallback
	end
	local displayName = eraConfig.displayName
	if typeof(displayName) == "string" and displayName ~= "" then
		return displayName
	end
	return eraConfig.name
end

local function findMonument(eraConfig: Types.EraConfig): Types.SlotConfig?
	for _, slot in eraConfig.slots do
		if slot.type == "monument" then
			return slot
		end
	end
	return nil
end

-- M2 affordance rule (docs/INTERFACES.md): monument owned decides eligibility; the
-- server independently validates the full every-slot-owned rule on the intent.
local function prestigeKindFor(state: Types.PlayerState): PrestigeKind?
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		return nil
	end
	local monument = findMonument(eraConfig)
	if monument == nil or state.slots[monument.id] == nil then
		return nil
	end
	local eraCount = Catalog.GetEraCount()
	if state.era < eraCount then
		return "advance"
	elseif state.era == eraCount then
		return "rebirth"
	end
	return nil
end

local function prestigeLabelFor(kind: PrestigeKind?, state: Types.PlayerState): string?
	if kind == "advance" then
		-- Missing next-era config degrades to a generic label, never an error.
		local nextEra = Catalog.GetEraConfig(state.era + 1)
		return if nextEra ~= nil
			then "Advance Era → " .. eraDisplayName(nextEra, nextEra.name)
			else "Advance Era"
	elseif kind == "rebirth" then
		return "Rebirth → Era " .. tostring(FIRST_ERA)
	end
	return nil
end

local function totalLevels(state: Types.PlayerState): number
	local total = 0
	for _, slotState in state.slots do
		total += slotState.level
	end
	return total
end

-- Settings arrive from the network; only a table with both booleans is trusted.
local function isSettings(source: any): boolean
	return typeof(source) == "table"
		and typeof(source.music) == "boolean"
		and typeof(source.sfx) == "boolean"
end

-- The delta's shop state arrives from the network; only the full shape is trusted.
local function isLegacyShopState(source: any): boolean
	return typeof(source) == "table"
		and typeof(source.spent) == "number"
		and typeof(source.perks) == "table"
end

-- Linear scan over a dozen entries; the array is display order.
local function findPerk(shopConfig: Types.LegacyShopConfig, perkId: string): Types.PerkDef?
	for _, perk in shopConfig.perks do
		if perk.id == perkId then
			return perk
		end
	end
	return nil
end

-- True when the spendable balance covers at least one perk's next tier — the trigger
-- for the single automatic Legacy-panel open after a ceremony.
local function hasAffordableTier(
	shopConfig: Types.LegacyShopConfig,
	state: Types.PlayerState
): boolean
	local spendable = Economy.LegacySpendable(state)
	for _, perk in shopConfig.perks do
		local nextTier = Economy.NextPerkTier(shopConfig, state.legacyShop, perk.id)
		if nextTier ~= nil and spendable >= nextTier.cost then
			return true
		end
	end
	return false
end

local UIController = {}

local function boot(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- RemoteService creates this folder at server Init; wait rather than assume order.
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent
	local actionResult = remotesFolder:WaitForChild("ActionResult") :: RemoteEvent
	local fxEvent = remotesFolder:WaitForChild("FxEvent") :: RemoteEvent
	local requestSnapshot = remotesFolder:WaitForChild("RequestSnapshot") :: RemoteEvent
	local requestBuy = remotesFolder:WaitForChild("RequestBuy") :: RemoteEvent
	local requestLevelUp = remotesFolder:WaitForChild("RequestLevelUp") :: RemoteEvent
	local requestAdvanceEra = remotesFolder:WaitForChild("RequestAdvanceEra") :: RemoteEvent
	local requestRebirth = remotesFolder:WaitForChild("RequestRebirth") :: RemoteEvent
	local requestSetSetting = remotesFolder:WaitForChild("RequestSetSetting") :: RemoteEvent
	local requestPrompt = remotesFolder:WaitForChild("RequestPrompt") :: RemoteEvent
	local requestRetryLoad = remotesFolder:WaitForChild("RequestRetryLoad") :: RemoteEvent
	local requestBuyPerk = remotesFolder:WaitForChild("RequestBuyPerk") :: RemoteEvent

	local gameConfig = Catalog.GetGameConfig()
	-- Static for the life of the server, so the Shop button's visibility is decided once.
	local monetization = Catalog.GetMonetizationConfig()
	-- Static too; an absent LegacyShop.json yields an empty perk list and the panel hides
	-- the shop (M6 contract).
	local shopConfig = Catalog.GetLegacyShopConfig()
	local hasShop = #shopConfig.perks > 0

	local screenGui = Create("ScreenGui", {
		Name = "EraCityHUD",
		ResetOnSpawn = false,
		-- Sibling, explicitly: under the legacy Global behavior a scrim's high ZIndex
		-- (Theme.ZINDEX_*) also covers its own card, whose children default to 1 — the
		-- dialogs rendered behind their own scrim and swallowed every tap. Sibling makes
		-- the ZINDEX_* constants order the overlay roots only, which is what they mean.
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	local model: Model? = nil
	-- The contract puts welcomeBack only on the first post-grant snapshot, but duplicate
	-- snapshots must be harmless, so the card additionally fires at most once a session.
	local welcomeBackShown = false
	local openPanelKey: PanelKey? = nil
	-- Mirrors state.settings, but exists before the first snapshot so a toggle pressed
	-- during loading still reaches SoundController (M3 carry-over b).
	local localSettings = { music = true, sfx = true }

	-- Forward declarations: layout and panel wiring reference each other.
	local applyLayout: () -> ()

	local topBar = TopBar.new(screenGui)
	local toast = Toast.new(screenGui)
	-- Up from boot so a slow first status still isn't a blank HUD; Hide() on the first
	-- snapshot is permanent. Retry is an intent; the server decides whether to honor it.
	local loadScreen = LoadScreen.new(screenGui, {
		onRetry = function()
			requestRetryLoad:FireServer()
		end,
		onLeave = function()
			-- Kick is allowed on the local player; the message shows on the disconnect screen.
			player:Kick("Rejoin to load your save.")
		end,
	})
	local welcomeCard = WelcomeBackCard.new(screenGui, {
		onVisibilityChanged = function()
			applyLayout() -- the toast stacks below the card while it is visible
		end,
	})
	local eraScreen = EraAdvanceScreen.new(screenGui)

	-- String-keyed so the three panels can be registered after their deps exist below.
	local panels: { [string]: DockablePanel } = {}
	local togglePanel: (key: PanelKey) -> ()
	local openPanel: (key: PanelKey) -> ()

	local ceremony = Ceremony.new(screenGui, {
		onClosed = function()
			-- Contract: the new era's ambient starts after the overlay, not under the jingle.
			local current = model
			if current ~= nil then
				SoundController.SetAmbientEra(current.eraName)
				-- M6: Legacy only moves on advance, so this is the one moment the shop is
				-- "new". A plain panel the player can close, never a modal (LEGACY_SHOP.md §8).
				if hasAffordableTier(shopConfig, current.state) then
					openPanel("legacy")
				end
			end
		end,
	})
	local bottomBar = BottomBar.new(screenGui, {
		onTap = function(key: BottomBar.BarKey)
			togglePanel(key)
		end,
	})
	bottomBar.SetShopVisible(hasShopListableId(monetization))

	togglePanel = function(panelKey: PanelKey): ()
		local previous = openPanelKey
		if previous ~= nil then
			panels[previous].SetOpen(false)
		end
		if previous == panelKey then
			openPanelKey = nil
		else
			openPanelKey = panelKey
			panels[panelKey].SetOpen(true)
		end
		bottomBar.SetActive(openPanelKey)
	end

	openPanel = function(panelKey: PanelKey): ()
		if openPanelKey ~= panelKey then
			togglePanel(panelKey)
		end
	end

	local function closePanels(): ()
		local previous = openPanelKey
		if previous ~= nil then
			panels[previous].SetOpen(false)
			openPanelKey = nil
			bottomBar.SetActive(nil)
		end
	end

	local function openPrestigeScreen(): ()
		local current = model
		if current == nil then
			return
		end
		local state = current.state
		local kind = prestigeKindFor(state)
		if kind == nil then
			return
		end
		-- Both prestige paths grant LegacyGain (contract amended mid-M2: rebirth is the
		-- final era's "advance"). The server computes with the pre-increment rebirthCount,
		-- which is exactly state.rebirthCount here.
		local gain =
			Economy.LegacyGain(state.era, totalLevels(state), state.rebirthCount, gameConfig)
		local nextEraIndex = if kind == "advance" then state.era + 1 else FIRST_ERA
		local nextEraConfig = Catalog.GetEraConfig(nextEraIndex)
		eraScreen.Show({
			kind = kind :: PrestigeKind,
			nextEraIndex = nextEraIndex,
			nextEraName = eraDisplayName(nextEraConfig, "the next era"),
			nextEraConfig = nextEraConfig,
			legacyGain = gain,
			legacy = state.legacy,
			rebirthCount = state.rebirthCount,
			onConfirm = function()
				if kind == "advance" then
					requestAdvanceEra:FireServer()
				else
					requestRebirth:FireServer()
				end
			end,
		})
	end

	local buildPanel = BuildPanel.new(screenGui, {
		gameConfig = gameConfig,
		shopConfig = shopConfig,
		onBuy = function(slotId: string)
			requestBuy:FireServer(slotId)
		end,
		onLevelUp = function(slotId: string, count: number)
			requestLevelUp:FireServer(slotId, count)
		end,
		onPrestige = openPrestigeScreen,
		onClose = closePanels,
	})
	local legacyPanel = LegacyPanel.new(screenGui, {
		gameConfig = gameConfig,
		monetization = monetization,
		shopConfig = shopConfig,
		onPrestige = openPrestigeScreen,
		-- Intent only: the server checks tier order and the Legacy balance.
		onBuyPerk = function(perkId: string)
			requestBuyPerk:FireServer(perkId)
		end,
		onClose = closePanels,
	})
	local shopPanel = ShopPanel.new(screenGui, {
		monetization = monetization,
		-- Intent only: the server decides whether a prompt may be shown at all (spec
		-- section 6 rule 2 - never a prompt the player did not open themselves).
		onPrompt = function(key: string)
			requestPrompt:FireServer(key)
		end,
		onClose = closePanels,
	})
	local settingsPanel = SettingsPanel.new(screenGui, {
		onToggle = function(key: Types.SettingKey, value: boolean)
			-- Apply locally at once, loaded or not (M3 carry-over b): the toggle must be
			-- audible immediately even before the first snapshot arrives. The next
			-- snapshot/delta stays authoritative and re-applies.
			if key == "music" then
				localSettings.music = value
			else
				localSettings.sfx = value
			end
			SoundController.ApplySettings(localSettings)
			local current = model
			if current ~= nil then
				current.state.settings = { music = localSettings.music, sfx = localSettings.sfx }
			end
			requestSetSetting:FireServer(key, value)
		end,
		onClose = closePanels,
	})
	panels.build = buildPanel
	panels.legacy = legacyPanel
	panels.shop = shopPanel
	panels.settings = settingsPanel

	local function applySettings(pushed: { music: boolean, sfx: boolean }): ()
		localSettings = { music = pushed.music, sfx = pushed.sfx }
		SoundController.ApplySettings(localSettings)
		settingsPanel.SetSettings(localSettings)
	end

	-- Bonuses readout: VIP from server state, Premium from the local player's membership,
	-- neighbors from the live player count (spec section 4). All three are previews of
	-- what the server already folded into incomePerSecond.
	local function refreshBonuses(): ()
		local current = model
		local vip = current ~= nil and current.state.passes.VIP == true
		local premium = player.MembershipType == Enum.MembershipType.Premium
		legacyPanel.SetBonuses(vip, premium, #Players:GetPlayers())
	end

	local function refreshAll(): ()
		local current = model
		if current == nil then
			return
		end
		local state = current.state
		topBar.SetCash(state.cash)
		topBar.SetIncome(current.incomePerSecond)
		-- Spendable rides beside the lifetime total (M6 playtest): the total never drops,
		-- so on its own it hid why every Buy had gone red. Nil hides it when no shop exists.
		topBar.SetLegacy(state.legacy, if hasShop then Economy.LegacySpendable(state) else nil)
		-- Deltas can deliver the monument purchase, so the affordance recomputes every push.
		local prestigeLabel = prestigeLabelFor(prestigeKindFor(state), state)
		buildPanel.SetPrestige(prestigeLabel)
		legacyPanel.SetPrestige(prestigeLabel)
		buildPanel.Refresh(state)
		legacyPanel.Refresh(state)
		-- Pack previews follow the persisted rate, which is what the server charges
		-- against, and re-render on every push because that rate moves with the build.
		shopPanel.Refresh(state, current.persistedIncomePerSecond, Catalog.GetEraConfig(state.era))
		refreshBonuses()
	end

	local function applySnapshot(payload: { [string]: any }): ()
		local state = payload.state
		if typeof(state) ~= "table" or typeof(state.era) ~= "number" then
			return
		end
		local snapshot = (payload :: any) :: Types.Snapshot
		local previous = model
		local eraChanged = previous ~= nil and previous.state.era ~= snapshot.state.era
		-- Replace, never merge: duplicate snapshots must land on identical UI.
		model = {
			plotIndex = snapshot.plotIndex,
			eraName = snapshot.eraName,
			state = snapshot.state,
			incomePerSecond = snapshot.incomePerSecond,
			persistedIncomePerSecond = readPersistedRate(payload),
		}
		if eraChanged then
			-- Any open prestige screen described the era we just left; its numbers are stale.
			eraScreen.Hide()
		end
		if previous == nil then
			-- First model of the session: the safe-mode card is done for good and the bar
			-- finally has something to act on.
			loadScreen.Hide()
			bottomBar.SetVisible(true)
		end
		local eraConfig = Catalog.GetEraConfig(snapshot.state.era)
		topBar.SetEra(snapshot.state.era, eraDisplayName(eraConfig, snapshot.eraName))
		-- Missing era config degrades to the panel's empty state, never an error.
		-- BuildPanel.SetEra skips rebuilds only when eraIndex matches, so an era-changing
		-- snapshot always rebuilds the rows (M2 contract check).
		buildPanel.SetEra(eraConfig)
		refreshAll()

		if isSettings(snapshot.state.settings) then
			applySettings(snapshot.state.settings)
		end
		-- The ceremony switches the ambient itself once its overlay closes.
		if not ceremony.IsOpen() then
			SoundController.SetAmbientEra(snapshot.eraName)
		end

		local welcomeBack = payload.welcomeBack
		if
			not welcomeBackShown
			and typeof(welcomeBack) == "table"
			and typeof(welcomeBack.grantedCash) == "number"
			and typeof(welcomeBack.elapsedSeconds) == "number"
		then
			welcomeBackShown = true
			-- Spec section 6 rule 3: the one contextual offer of the session, and only
			-- when the human has actually created the product. Nothing auto-opens.
			local doubleOffline = Catalog.GetProductDef("DoubleOffline")
			if doubleOffline ~= nil and doubleOffline.id ~= 0 then
				welcomeCard.SetDoubleOffer({
					label = doubleOffline.name,
					onTap = function()
						requestPrompt:FireServer(doubleOffline.key)
						welcomeCard.SetDoubleOffer(nil) -- one offer; the card may stay
					end,
				})
			else
				welcomeCard.SetDoubleOffer(nil)
			end
			welcomeCard.Show(welcomeBack.grantedCash, welcomeBack.elapsedSeconds)
		end
	end

	local function applyDelta(payload: { [string]: any }): ()
		local current = model
		if current == nil then
			-- Delta raced ahead of the first snapshot; the RequestSnapshot below covers us.
			return
		end
		local delta = (payload :: any) :: Types.Delta
		if typeof(delta.cash) == "number" then
			current.state.cash = delta.cash
		end
		if typeof(delta.incomePerSecond) == "number" then
			current.incomePerSecond = delta.incomePerSecond
			-- Contract: the persisted rate ships with every income flush.
			current.persistedIncomePerSecond = readPersistedRate(payload)
		end
		local slots = delta.slots
		if typeof(slots) == "table" then
			for slotId, slotState in slots do
				current.state.slots[slotId] = slotState
			end
		end
		local settings = delta.settings
		if settings ~= nil and isSettings(settings) then
			current.state.settings = { music = settings.music, sfx = settings.sfx }
			applySettings(current.state.settings)
		end
		-- M6: the whole shop state whenever a perk purchase lands (a copy, never aliased).
		local legacyShop = delta.legacyShop
		if isLegacyShopState(legacyShop) then
			current.state.legacyShop = legacyShop :: Types.LegacyShopState
		end
		refreshAll()
	end

	-- Sent only while the player has no loaded state (Types.LoadStatus, M5). Once a model
	-- exists the screen is hidden for good and any straggler is ignored by LoadScreen.
	local function applyLoadStatus(payload: { [string]: any }): ()
		local phase = payload.phase
		if phase ~= "loading" and phase ~= "failed" then
			return
		end
		local attempt = payload.attempt
		local retryAvailableIn = payload.retryAvailableIn
		loadScreen.Apply({
			phase = phase,
			attempt = if typeof(attempt) == "number" then attempt else 1,
			retryAvailableIn = if typeof(retryAvailableIn) == "number" then retryAvailableIn else 0,
		})
	end

	local function onStateChanged(payload: any): ()
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "snapshot" then
			applySnapshot(payload)
		elseif payload.kind == "delta" then
			applyDelta(payload)
		elseif payload.kind == "loadStatus" then
			applyLoadStatus(payload)
		end
	end

	local function onActionResult(payload: any): ()
		-- Failure-only by contract, but stay safe against future success payloads.
		if typeof(payload) ~= "table" or payload.ok ~= false then
			return
		end
		local action = payload.action
		if action == "advanceEra" then
			-- slotId is "" for era actions — no row to flash, so a small toast instead.
			toast.Show(
				"Can't advance yet — own every slot first",
				Theme.TOAST_ERROR_SECONDS,
				true
			)
		elseif action == "rebirth" then
			toast.Show(
				"Can't rebirth yet — own every slot first",
				Theme.TOAST_ERROR_SECONDS,
				true
			)
		elseif action == "buyPerk" then
			-- M6: slotId carries the perkId. The row can only be tapped with the panel
			-- open, so the flash is on-screen; the sound is for the balance failure only.
			local perkId = payload.slotId
			if typeof(perkId) == "string" then
				legacyPanel.FlashPerk(perkId)
			end
			local current = model
			if payload.reason == "insufficientFunds" then
				SoundController.Play("insufficientFunds")
				-- Explicit reason (M6 playtest): the flash alone did not say WHY. Both
				-- numbers are server state / the shared config, never computed here.
				if current ~= nil and typeof(perkId) == "string" then
					local have = Economy.LegacySpendable(current.state)
					local nextTier =
						Economy.NextPerkTier(shopConfig, current.state.legacyShop, perkId)
					local need = if nextTier ~= nil then Format.Cash(nextTier.cost) else "more"
					toast.Show(
						"Not enough spendable Legacy (have "
							.. Format.Cash(have)
							.. ", need "
							.. need
							.. ")",
						Theme.TOAST_ERROR_SECONDS,
						true
					)
				end
			elseif not legacyPanel.IsOpen() then
				toast.Show("Can't buy that perk right now", Theme.TOAST_ERROR_SECONDS, true)
			end
		elseif typeof(payload.slotId) == "string" and payload.slotId ~= "" then
			-- M3 contract: every slot failure flashes the row; only a failed payment sounds.
			buildPanel.FlashSlot(payload.slotId)
			if payload.reason == "insufficientFunds" then
				SoundController.Play("insufficientFunds")
			end
			-- M5 feedback audit: a buy pad or ProximityPrompt fails with the Build panel
			-- closed, so the row flash is off-screen and the sound may be id 0 - a toast is
			-- the only visible answer the player gets.
			if not buildPanel.IsOpen() then
				local reason = payload.reason
				local message = if reason == "insufficientFunds"
					then "Not enough cash"
					elseif reason == "locked" then "Locked — buy the previous slot first"
					else "Can't do that right now"
				toast.Show(message, Theme.TOAST_ERROR_SECONDS, true)
			end
		end
	end

	-- M4 purchase feedback. The cash itself arrives as a normal delta; this is only the
	-- acknowledgement, and it reuses the existing purchase sound (Sounds.json is frozen).
	local function onPurchaseFx(payload: { [string]: any }): ()
		if payload.kind == "purchase" then
			local granted = if typeof(payload.grantedCash) == "number"
				then payload.grantedCash
				else 0
			-- A zero grant is reachable (a DoubleOffline receipt replayed with no record
			-- left); "+$0" reads worse than saying nothing (wave-2 ruling 6).
			if granted > 0 then
				toast.Show("+$" .. Format.Cash(granted), Theme.TOAST_SECONDS, false)
			end
		else
			local passKey = payload.passKey
			if typeof(passKey) ~= "string" then
				return
			end
			local def = Catalog.GetPassDef(passKey)
			toast.Show(
				(if def ~= nil then def.name else passKey) .. " active",
				Theme.TOAST_SECONDS,
				false
			)
			-- The grant delta carries income, not passes, so mirror the pass locally for
			-- the badge and the Shop's Owned state; the next snapshot overwrites it.
			local current = model
			if current ~= nil then
				current.state.passes[passKey] = true
				refreshAll()
			end
		end
		SoundController.Play("purchase")
	end

	-- M6 perk purchase acknowledgement: the new legacyShop state arrives as a delta; this
	-- is the toast plus the existing purchase sound (Sounds.json is frozen).
	local function onPerkBoughtFx(payload: { [string]: any }): ()
		local perkId = payload.perkId
		if typeof(perkId) ~= "string" then
			return
		end
		local perk = findPerk(shopConfig, perkId)
		local name = if perk ~= nil then perk.name else perkId
		local tier = if typeof(payload.tier) == "number" then payload.tier else 0
		local message = if perk ~= nil and perk.cosmetic
			then name .. " unlocked"
			else name .. " — Tier " .. tostring(tier)
		toast.Show(message, Theme.TOAST_SECONDS, false)
		SoundController.Play("purchase")
	end

	-- eraAdvance / rebirth / purchase / passGranted / perkBought; PlotVisualsController
	-- owns reveal and levelUp.
	local function onFxEvent(payload: any): ()
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "purchase" or payload.kind == "passGranted" then
			onPurchaseFx(payload)
			return
		end
		if payload.kind == "perkBought" then
			onPerkBoughtFx(payload)
			return
		end
		if typeof(payload.toEra) ~= "number" then
			return
		end
		local kind = payload.kind
		if kind ~= "eraAdvance" and kind ~= "rebirth" then
			return
		end
		local legacyGained = if typeof(payload.legacyGained) == "number"
			then payload.legacyGained
			else 0
		local rebirthCount = if typeof(payload.rebirthCount) == "number"
			then payload.rebirthCount
			else 0
		local toEra: number = payload.toEra
		local nextEraConfig = Catalog.GetEraConfig(toEra)
		eraScreen.Hide()
		ceremony.Show({
			kind = kind,
			eraIndex = toEra,
			displayName = eraDisplayName(nextEraConfig, "Era " .. tostring(toEra)),
			legacyGained = legacyGained,
			rebirthCount = rebirthCount,
		})
	end

	local function onCashAttribute(): ()
		local value = player:GetAttribute("Cash")
		if typeof(value) ~= "number" then
			return
		end
		local current = model
		if current ~= nil then
			current.state.cash = value
			refreshAll() -- keeps the affordability highlight in step with the income tick
		else
			-- The attribute can beat the first snapshot; show cash while the panel waits.
			topBar.SetCash(value)
		end
	end

	applyLayout = function(): ()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return -- AbsoluteSize is zero before first layout; the changed signal re-enters
		end
		-- MIN_SCALE is derived in Theme so tap targets never drop below 44 physical px;
		-- panels adapt their height/docking to the viewport through PanelDock.
		local scale = math.clamp(
			math.min(size.X / Theme.DESIGN_WIDTH, size.Y / Theme.DESIGN_HEIGHT),
			Theme.MIN_SCALE,
			Theme.MAX_SCALE
		)
		local landscape = PanelDock.IsLandscape(size)
		topBar.SetLayout(scale, landscape)
		bottomBar.SetScale(scale)
		for _, panel in panels do
			panel.SetLayout(PanelDock.Compute(scale, size, panel.DesignHeight))
		end
		eraScreen.SetLayout(scale, size)
		ceremony.SetScale(scale)
		loadScreen.SetScale(scale)
		welcomeCard.SetLayout(scale, landscape)
		local stackedAbove = if welcomeCard.IsVisible()
			then welcomeCard.DesignHeight() + Theme.TOAST_GAP
			else 0
		toast.SetLayout(scale, landscape, stackedAbove)
	end

	-- The HUD lives for the whole session (ResetOnSpawn = false); these connections die
	-- with the client. Components expose Destroy() for any future screen rebuild.
	stateChanged.OnClientEvent:Connect(onStateChanged)
	actionResult.OnClientEvent:Connect(onActionResult)
	fxEvent.OnClientEvent:Connect(onFxEvent)
	player:GetAttributeChangedSignal("Cash"):Connect(onCashAttribute)
	-- The neighbors bonus tracks the live player count, not a server push.
	Players.PlayerAdded:Connect(refreshBonuses)
	Players.PlayerRemoving:Connect(refreshBonuses)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	applyLayout()
	onCashAttribute()
	refreshBonuses()
	-- One explicit request on boot: the server's proactive join snapshot may have fired
	-- before our connection existed; duplicate snapshots are harmless by design.
	requestSnapshot:FireServer()
end

function UIController.Init(): ()
	-- UI needs replicated instances (Shared, Remotes, PlayerGui); everything happens in
	-- Start so Init stays yield-free per the boot contract.
end

function UIController.Start(): ()
	-- Async so SoundController/PlotVisualsController start immediately while we wait on
	-- replication.
	task.spawn(boot)
end

return UIController
