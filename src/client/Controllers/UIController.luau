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
-- ceremony when a tier has become affordable — earned currency, not Robux. C0 adds the
-- Expeditions surface: the Gear Power readout, the Armory panel (RequestBuyGear /
-- RequestAscend) and the Expedition panel (RequestExpedition / RequestJoinRun /
-- RequestRunList). Both are pure views of `state.combat` and the server's `gearPower`; with
-- Armory.json or Combat.json absent, or on a server that never created the remotes, the
-- buttons simply do not exist and the HUD is exactly the M9 HUD. C1 adds the run report
-- (the ExpeditionSummary event -> ExpeditionSummaryCard) and, in Studio only, the debug
-- strip that drives the hub's RequestDebug levers. C2 adds the hub party: PartyState feeds
-- the Expedition panel's party strip, PartyInvite raises the non-blocking PartyInviteToast,
-- and the four RequestParty* intents are the only way the client touches a party.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
local ArmoryPanel = require(uiFolder:WaitForChild("ArmoryPanel"))
local ExpeditionPanel = require(uiFolder:WaitForChild("ExpeditionPanel"))
local ExpeditionSummaryCard = require(uiFolder:WaitForChild("ExpeditionSummaryCard"))
local DebugPanel = require(uiFolder:WaitForChild("DebugPanel"))
local PartyInviteToast = require(uiFolder:WaitForChild("PartyInviteToast"))
local SettingsPanel = require(uiFolder:WaitForChild("SettingsPanel"))
local EraAdvanceScreen = require(uiFolder:WaitForChild("EraAdvanceScreen"))
local Ceremony = require(uiFolder:WaitForChild("Ceremony"))
local WelcomeBackCard = require(uiFolder:WaitForChild("WelcomeBackCard"))
local Toast = require(uiFolder:WaitForChild("Toast"))
local LoadScreen = require(uiFolder:WaitForChild("LoadScreen"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local AssetPreloader = require(script.Parent:WaitForChild("AssetPreloader"))
local CityDressingController = require(script.Parent:WaitForChild("CityDressingController"))

type Model = {
	plotIndex: number,
	eraName: string,
	state: Types.PlayerState,
	incomePerSecond: number,
	-- The rate the server prices cash packs off (no Studio debug multiplier, neighbors
	-- pinned to 1). Tracked like incomePerSecond and never derived here: only the Shop's
	-- pack preview reads it, and only the server may compute it (wave-2 ruling 4).
	persistedIncomePerSecond: number,
	-- C0: Armory.GearPower as the SERVER computed it (Snapshot and Delta both carry it).
	-- The client never derives it, so a stale weapon table can never flatter the readout.
	gearPower: number,
}

type PrestigeKind = "advance" | "rebirth"

type PanelKey = "build" | "armory" | "expedition" | "legacy" | "shop" | "settings"

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

-- Same rule for Gear Power: absent means this server has no Armory, and 0 understates
-- rather than promising a player power they do not have.
local function readGearPower(payload: { [string]: any }): number
	local power = payload.gearPower
	return if typeof(power) == "number" then power else 0
end

-- C1: the run report the hub forwards after a return teleport (or a Studio handoff record).
-- It is presentation only — the rewards are already in the profile — so a malformed payload
-- is dropped rather than half-drawn. `bestWave` and `died` are optional: a combat place that
-- predates them omits them and the card falls back to wavesCleared / not died.
local function readRunSummary(payload: any): Types.RunSummary?
	if
		typeof(payload) ~= "table"
		or typeof(payload.missionId) ~= "string"
		or typeof(payload.materials) ~= "table"
		or typeof(payload.wavesCleared) ~= "number"
		or typeof(payload.cash) ~= "number"
		or typeof(payload.valor) ~= "number"
		or typeof(payload.kills) ~= "number"
		or typeof(payload.seconds) ~= "number"
	then
		return nil
	end
	local materials: { [string]: number } = {}
	for name, amount in payload.materials do
		if typeof(name) == "string" and typeof(amount) == "number" then
			materials[name] = amount
		end
	end
	local summary: any = {
		missionId = payload.missionId,
		overdrive = payload.overdrive == true,
		wavesCleared = payload.wavesCleared,
		cash = payload.cash,
		materials = materials,
		valor = payload.valor,
		kills = payload.kills,
		seconds = payload.seconds,
		bestWave = if typeof(payload.bestWave) == "number"
			then payload.bestWave
			else payload.wavesCleared,
		died = payload.died == true,
	}
	return summary :: Types.RunSummary
end

-- C2: PartyState payload. Entries with a bad shape are dropped rather than the whole party,
-- but a party without a numeric leader or member list is not a party.
local function readHubParty(payload: any): Types.HubParty?
	if
		typeof(payload) ~= "table"
		or typeof(payload.leaderUserId) ~= "number"
		or typeof(payload.members) ~= "table"
	then
		return nil
	end
	local members: { Types.HubPartyMember } = {}
	for _, member in payload.members do
		if
			typeof(member) == "table"
			and typeof(member.userId) == "number"
			and typeof(member.name) == "string"
		then
			table.insert(members, { userId = member.userId, name = member.name })
		end
	end
	local pending: { Types.HubPartyInvite } = {}
	if typeof(payload.pending) == "table" then
		for _, invite in payload.pending do
			if
				typeof(invite) == "table"
				and typeof(invite.userId) == "number"
				and typeof(invite.name) == "string"
				and typeof(invite.expiresIn) == "number"
			then
				table.insert(
					pending,
					{ userId = invite.userId, name = invite.name, expiresIn = invite.expiresIn }
				)
			end
		end
	end
	return { leaderUserId = payload.leaderUserId, members = members, pending = pending }
end

local function readPartyInvite(payload: any): Types.PartyInviteEvent?
	if
		typeof(payload) ~= "table"
		or typeof(payload.leaderUserId) ~= "number"
		or typeof(payload.leaderName) ~= "string"
		or typeof(payload.expiresIn) ~= "number"
	then
		return nil
	end
	return {
		leaderUserId = payload.leaderUserId,
		leaderName = payload.leaderName,
		expiresIn = payload.expiresIn,
	}
end

-- C2 refusal copy for the co-op reasons (contract wording). `full` on a party action is the
-- party at maxParty, not a run, so it gets its own line.
local function coopReasonMessage(action: string, reason: any): string?
	if reason == "full" then
		return if action == "party" then "Your party is full" else "That run is full"
	elseif reason == "over" then
		return "That run has moved past joining"
	elseif reason == "busy" then
		return if action == "expedition"
			then "Not everyone in your party could depart"
			else "They're already in a party"
	elseif reason == "expired" then
		return "That invite expired"
	elseif reason == "notLeader" then
		return "Only the party leader can do that"
	end
	return nil
end

-- The delta's combat profile arrives from the network; only the full shape is trusted, and
-- it replaces `state.combat` wholesale (the server sends a copy, never a patch).
local function isCombatProfile(source: any): boolean
	return typeof(source) == "table"
		and typeof(source.materials) == "table"
		and typeof(source.gear) == "table"
		and typeof(source.ascension) == "table"
		and typeof(source.valor) == "number"
		and typeof(source.highestEra) == "number"
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

-- Settings arrive from the network; only a table with music and sfx booleans is trusted.
-- A missing vipSkins or cityDetail reads as true (the profile default) so a server build that
-- predates the key still delivers music/sfx instead of the whole table being rejected.
local function readSettings(source: any): SettingsPanel.Settings?
	if
		typeof(source) ~= "table"
		or typeof(source.music) ~= "boolean"
		or typeof(source.sfx) ~= "boolean"
	then
		return nil
	end
	return {
		music = source.music,
		sfx = source.sfx,
		vipSkins = source.vipSkins ~= false,
		cityDetail = source.cityDetail ~= false,
	}
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

	-- C0: nil config hides the whole feature (the nil-is-the-signal pattern), and a mission
	-- list is only read once, since Config/Missions is static for the life of the server.
	local armoryConfig = Catalog.GetArmoryConfig()
	local combatConfig = Catalog.GetCombatConfig()
	local placesConfig = Catalog.GetPlacesConfig()
	local missions: { Types.MissionConfig } = {}
	if combatConfig ~= nil then
		for eraIndex = 1, Catalog.GetEraCount() do
			local mission = Catalog.GetMissionConfig(eraIndex)
			if mission ~= nil then
				table.insert(missions, mission)
			end
		end
	end
	-- The combat remotes are created in one RemoteService.Init pass, which may not have run
	-- when the HUD boots and never runs at all on a hub server that predates Expeditions.
	-- Boot waits for neither case (review of 2026-09-17): the panels are built from config
	-- alone, and their buttons appear the moment the remotes exist — now, or from the
	-- ChildAdded listener further down.
	local requestBuyGear: RemoteEvent? = nil
	local requestAscend: RemoteEvent? = nil
	local requestExpedition: RemoteEvent? = nil
	local requestJoinRun: RemoteEvent? = nil
	local requestRunList: RemoteEvent? = nil
	-- C1: the hub's Studio-only debug intent. Absent on a server that predates the Studio
	-- bridge, which is exactly why the DebugPanel's taps are no-ops rather than errors.
	local requestDebug: RemoteEvent? = nil
	-- C2 party intents, created in the same RemoteService pass as the rest.
	local requestPartyInvite: RemoteEvent? = nil
	local requestPartyRespond: RemoteEvent? = nil
	local requestPartyLeave: RemoteEvent? = nil
	local requestPartyKick: RemoteEvent? = nil
	local combatRemotesReady = false
	local function resolveCombatRemotes(): ()
		requestBuyGear = remotesFolder:FindFirstChild("RequestBuyGear") :: RemoteEvent?
		requestAscend = remotesFolder:FindFirstChild("RequestAscend") :: RemoteEvent?
		requestExpedition = remotesFolder:FindFirstChild("RequestExpedition") :: RemoteEvent?
		requestJoinRun = remotesFolder:FindFirstChild("RequestJoinRun") :: RemoteEvent?
		requestRunList = remotesFolder:FindFirstChild("RequestRunList") :: RemoteEvent?
		requestDebug = remotesFolder:FindFirstChild("RequestDebug") :: RemoteEvent?
		requestPartyInvite = remotesFolder:FindFirstChild("RequestPartyInvite") :: RemoteEvent?
		requestPartyRespond = remotesFolder:FindFirstChild("RequestPartyRespond") :: RemoteEvent?
		requestPartyLeave = remotesFolder:FindFirstChild("RequestPartyLeave") :: RemoteEvent?
		requestPartyKick = remotesFolder:FindFirstChild("RequestPartyKick") :: RemoteEvent?
		-- One intent decides for all of them: RemoteService creates the whole set at once.
		combatRemotesReady = requestBuyGear ~= nil
	end
	resolveCombatRemotes()
	local hasArmory = armoryConfig ~= nil
	-- The place id being 0 does NOT hide the panel: the contract wants the tiles visible and
	-- disabled with "Publish the Expeditions place first", so the feature is discoverable
	-- before the second place exists.
	local hasExpeditions = combatConfig ~= nil and #missions > 0

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
	local localSettings: SettingsPanel.Settings =
		{ music = true, sfx = true, vipSkins = true, cityDetail = true }

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
	-- C1 review fix: the expedition report and the welcome-back card are both decided by the
	-- same join, and every run is longer than welcomeBackMinSeconds, so they always collide.
	-- The report is modal and would cover the welcome card's one DoubleOffline offer, so it
	-- is held here until that card is gone. Forward declaration: the welcome card is built
	-- long before the report card exists.
	local pendingSummary: Types.RunSummary? = nil
	local flushExpeditionSummary: () -> ()
	local welcomeCard = WelcomeBackCard.new(screenGui, {
		onVisibilityChanged = function(visible: boolean)
			applyLayout() -- the toast stacks below the card while it is visible
			if not visible then
				flushExpeditionSummary() -- the report waits its turn behind the offer
			end
		end,
	})
	local eraScreen = EraAdvanceScreen.new(screenGui)
	-- C2: stacks under the welcome-back card and above the error toast, so its visibility
	-- re-runs the layout like the welcome card's does.
	local inviteToast: PartyInviteToast.PartyInviteToastHandle? = nil
	if hasExpeditions then
		inviteToast = PartyInviteToast.new(screenGui, {
			onRespond = function(leaderUserId: number, accept: boolean)
				if requestPartyRespond ~= nil then
					requestPartyRespond:FireServer(leaderUserId, accept)
				end
			end,
			onVisibilityChanged = function()
				applyLayout()
			end,
		})
	end

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
	bottomBar.SetKeyVisible("shop", hasShopListableId(monetization))
	-- A panel whose intent does not exist yet would only be able to fail, so the key stays
	-- hidden until the remotes are there.
	local function refreshCombatKeys(): ()
		bottomBar.SetKeyVisible("armory", hasArmory and combatRemotesReady)
		bottomBar.SetKeyVisible("expedition", hasExpeditions and combatRemotesReady)
	end
	refreshCombatKeys()

	togglePanel = function(panelKey: PanelKey): ()
		if panels[panelKey] == nil then
			return -- the feature's config is absent, so its panel was never built
		end
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
			elseif key == "sfx" then
				localSettings.sfx = value
			elseif key == "vipSkins" then
				localSettings.vipSkins = value
			else
				localSettings.cityDetail = value
			end
			SoundController.ApplySettings(localSettings)
			-- Thinning the city is local-only display, so it follows the tap at once too.
			CityDressingController.SetCityDetail(localSettings.cityDetail)
			local current = model
			if current ~= nil then
				current.state.settings = table.clone(localSettings)
			end
			requestSetSetting:FireServer(key, value)
		end,
		onClose = closePanels,
	})
	-- C0: built only when the config AND the remotes exist, so every tap below has somewhere
	-- to go. Intents carry a slot or a mission id and nothing else — no amounts, ever.
	local armoryPanel: ArmoryPanel.ArmoryPanelHandle? = nil
	if hasArmory and armoryConfig ~= nil then
		armoryPanel = ArmoryPanel.new(screenGui, {
			armoryConfig = armoryConfig,
			onBuy = function(slot: ArmoryPanel.Slot)
				if requestBuyGear ~= nil then
					requestBuyGear:FireServer(slot)
				end
			end,
			onAscend = function(slot: ArmoryPanel.Slot)
				if requestAscend ~= nil then
					requestAscend:FireServer(slot)
				end
			end,
			onClose = closePanels,
		})
	end
	local expeditionPanel: ExpeditionPanel.ExpeditionPanelHandle? = nil
	if hasExpeditions and combatConfig ~= nil then
		expeditionPanel = ExpeditionPanel.new(screenGui, {
			missions = missions,
			placesConfig = placesConfig,
			combatConfig = combatConfig,
			onDepart = function(missionId: string, overdrive: boolean, public: boolean)
				if requestExpedition ~= nil then
					requestExpedition:FireServer(missionId, overdrive, public)
				end
			end,
			onJoin = function(hostUserId: number)
				if requestJoinRun ~= nil then
					requestJoinRun:FireServer(hostUserId)
				end
			end,
			onRefreshRuns = function()
				if requestRunList ~= nil then
					requestRunList:FireServer()
				end
			end,
			onPartyInvite = function(userId: number)
				if requestPartyInvite ~= nil then
					requestPartyInvite:FireServer(userId)
				end
			end,
			onPartyLeave = function()
				if requestPartyLeave ~= nil then
					requestPartyLeave:FireServer()
				end
			end,
			onPartyKick = function(userId: number)
				if requestPartyKick ~= nil then
					requestPartyKick:FireServer(userId)
				end
			end,
			onClose = closePanels,
		})
	end
	-- C1: the report of the run the player just came back from. Built with the Expeditions
	-- surface (a hub without Combat.json can never receive an ExpeditionSummary) and shown
	-- only when that event fires; it holds no state of its own between runs.
	local summaryCard: ExpeditionSummaryCard.ExpeditionSummaryCardHandle? = nil
	if hasExpeditions then
		summaryCard = ExpeditionSummaryCard.new(screenGui, {
			onClose = function()
				-- The card is sized from its own content, so the HUD re-lays out once it
				-- is gone: a rotation while the modal was up otherwise leaves the scale
				-- it was shown with.
				applyLayout()
			end,
		})
	end
	-- Shows a held report once nothing else owns the screen. Safe to call at any time: with
	-- no report held, or with the welcome-back card still up, it does nothing.
	flushExpeditionSummary = function(): ()
		local summary = pendingSummary
		local card = summaryCard
		if summary == nil or card == nil or welcomeCard.IsVisible() then
			return
		end
		pendingSummary = nil
		card.Show(summary)
		applyLayout() -- the card just sized itself to its rows; re-fit it
	end

	-- The event can land before or after the first snapshot, and only that snapshot decides
	-- whether a welcome-back card exists at all, so the report is always parked first and
	-- released by whichever of the two happens last.
	local function showExpeditionSummary(summary: Types.RunSummary): ()
		pendingSummary = summary
		if model ~= nil then
			flushExpeditionSummary()
		end
	end

	-- C1 Studio bridge: a strip of buttons for the hub's debug levers. Studio-only by
	-- construction — a live client never builds it, and the server ignores the intent
	-- anyway, so the lever cannot be reached from a published place.
	local debugPanel: DebugPanel.DebugPanelHandle? = nil
	if RunService:IsStudio() then
		debugPanel = DebugPanel.new(screenGui, {
			onLever = function(lever: string, value: any)
				if requestDebug ~= nil then
					requestDebug:FireServer(lever, value)
				end
			end,
		})
	end
	panels.build = buildPanel
	panels.legacy = legacyPanel
	panels.shop = shopPanel
	panels.settings = settingsPanel
	if armoryPanel ~= nil then
		panels.armory = armoryPanel
	end
	if expeditionPanel ~= nil then
		panels.expedition = expeditionPanel
	end

	local function applySettings(pushed: SettingsPanel.Settings): ()
		localSettings = table.clone(pushed)
		SoundController.ApplySettings(localSettings)
		CityDressingController.SetCityDetail(localSettings.cityDetail)
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
		-- Every path that changes passes (snapshot, delta, the mid-session grant mirror)
		-- ends here, so the VIP-only settings row can never go stale.
		settingsPanel.SetVipVisible(vip)
	end

	-- The era/VIP/next-era combination last handed to AssetPreloader, so deltas (which all
	-- land in refreshAll) only re-request when one of the three actually changed.
	local preloadKey: string? = nil
	local function refreshPreload(current: Model): ()
		local state = current.state
		local vip = state.passes.VIP == true
		-- Warm the era the player is about to enter once the monument makes it reachable.
		local kind = prestigeKindFor(state)
		local nextEraConfig = if kind == "advance"
			then Catalog.GetEraConfig(state.era + 1)
			elseif kind == "rebirth" then Catalog.GetEraConfig(FIRST_ERA)
			else nil
		local nextEraName = if nextEraConfig ~= nil then nextEraConfig.name else nil
		local key = current.eraName .. "|" .. tostring(vip) .. "|" .. (nextEraName or "")
		if key == preloadKey then
			return
		end
		preloadKey = key
		AssetPreloader.PreloadEra(current.eraName, vip)
		if nextEraName ~= nil and nextEraName ~= current.eraName then
			AssetPreloader.PreloadEra(nextEraName, vip)
		end
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
		-- C0: nil hides the readout entirely on a hub without an Armory.
		topBar.SetPower(if hasArmory and combatRemotesReady then current.gearPower else nil)
		local armory = armoryPanel
		if armory ~= nil then
			-- The Armory gates on the PERSISTED rate, which is the one the server checks.
			armory.Refresh(state, current.persistedIncomePerSecond)
		end
		local expedition = expeditionPanel
		if expedition ~= nil then
			expedition.Refresh(state, current.gearPower)
		end
		refreshBonuses()
		refreshPreload(current)
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
			gearPower = readGearPower(payload),
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

		local settings = readSettings(snapshot.state.settings)
		if settings ~= nil then
			snapshot.state.settings = settings
			applySettings(settings)
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
		-- The join has settled: with no welcome-back card to wait for, a report held by the
		-- ExpeditionSummary event goes up now.
		flushExpeditionSummary()
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
		local settings = readSettings(delta.settings)
		if settings ~= nil then
			current.state.settings = settings
			applySettings(settings)
		end
		-- M6: the whole shop state whenever a perk purchase lands (a copy, never aliased).
		local legacyShop = delta.legacyShop
		if isLegacyShopState(legacyShop) then
			current.state.legacyShop = legacyShop :: Types.LegacyShopState
		end
		-- C0: the whole combat profile whenever the combat dirty flag flushes, with the new
		-- Gear Power beside it. Replaced wholesale, never merged, like legacyShop.
		local combat = delta.combat
		if isCombatProfile(combat) then
			current.state.combat = combat :: Types.CombatProfile
		end
		-- The contract ships gearPower as its own optional field beside it, so it is read
		-- independently: a flush that only re-prices the loadout still moves the readout.
		if typeof(delta.gearPower) == "number" then
			current.gearPower = delta.gearPower
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

	-- C0/C1: why an expedition could not start, in the player's terms. In Studio the bridge
	-- only refuses when the failure lever is armed or the handoff store is unreachable; an
	-- unpublished second place is the same dead end with a different cause.
	local function expeditionUnavailableMessage(joining: boolean): string
		if RunService:IsStudio() then
			return "Departure failed — ForceTeleportFailure is on, or Studio has no API access"
		end
		if placesConfig.combatPlaceId == 0 then
			return "Expeditions aren't available yet"
		end
		return if joining
			then "That run is full or already over"
			else "Couldn't start the expedition — try again"
	end

	-- C1: a Depart/Join answer releases the panel's in-flight lock, and it also means the
	-- server has read (and reset) the forced-teleport-failure attribute, so the strip's
	-- toggle must not keep claiming the lever is armed.
	local function onExpeditionAnswer(): ()
		local expedition = expeditionPanel
		if expedition ~= nil then
			expedition.ClearDeparting()
		end
		local strip = debugPanel
		if strip ~= nil then
			strip.SetForceTeleportFailure(false)
		end
	end

	local function onCombatActionResult(payload: { [string]: any }): ()
		local action = payload.action
		local reason = payload.reason
		local armory = armoryPanel
		if action == "buyGear" or action == "ascend" then
			local slot = payload.slotId
			if armory ~= nil and (slot == "melee" or slot == "ranged") then
				armory.FlashSlot(slot :: ArmoryPanel.Slot)
			end
			if reason == "insufficientFunds" then
				SoundController.Play("insufficientFunds")
			end
			-- The Armory can be closed by the time a refusal lands (rate limit, a race with
			-- the panel's close), so the reason is always said in words too.
			local message: string
			if action == "buyGear" then
				message = if reason == "insufficientFunds"
					then "Not enough materials"
					elseif reason == "locked" then "Locked — your city's income is too low"
					else "Can't buy that weapon right now"
			else
				message = if reason == "insufficientFunds"
					then "Not enough materials or Valor"
					elseif
						reason == "locked"
					then "Ascension is capped — Rebirth again to raise it"
					else "Can't ascend right now"
			end
			toast.Show(message, Theme.TOAST_ERROR_SECONDS, true)
			return
		end
		if action == "party" then
			-- A refused invite frees its picker row; a late Accept retires the card.
			local expedition = expeditionPanel
			if expedition ~= nil then
				expedition.ClearInviteSent()
			end
			local card = inviteToast
			if card ~= nil and reason == "expired" then
				card.Dismiss(tonumber(payload.slotId))
			end
			toast.Show(
				coopReasonMessage(action, reason) or "Couldn't update your party",
				Theme.TOAST_ERROR_SECONDS,
				true
			)
			return
		end
		-- expedition / joinRun: nothing to flash (the tile may be off-screen and the failure
		-- is about the world, not the row), so the toast carries the whole message.
		onExpeditionAnswer()
		local joining = action == "joinRun"
		local message: string
		local coopMessage = coopReasonMessage(action, reason)
		if coopMessage ~= nil then
			message = coopMessage
		elseif reason == "unavailable" then
			message = expeditionUnavailableMessage(joining)
		elseif reason == "locked" then
			message = if joining
				then "That run is locked for you"
				else "That expedition is locked — advance your city first"
		else
			message = if joining then "Couldn't join that run" else "Can't depart right now"
		end
		toast.Show(message, Theme.TOAST_ERROR_SECONDS, true)
	end

	local function onActionResult(payload: any): ()
		if typeof(payload) ~= "table" then
			return
		end
		local isCombatAction = payload.action == "buyGear"
			or payload.action == "ascend"
			or payload.action == "expedition"
			or payload.action == "joinRun"
			or payload.action == "party"
		if payload.ok == true then
			-- C0 is the first action that succeeds loudly: the teleport takes a moment and
			-- the player has to know their tap was heard.
			if payload.action == "expedition" or payload.action == "joinRun" then
				onExpeditionAnswer()
				-- C1 Studio bridge: there is no teleport in Studio, only a handoff record
				-- and a kick a second later, so the toast has to say what to do next.
				toast.Show(
					if RunService:IsStudio()
						then "Handoff saved — Stop Play, then open build/combat.rbxl"
						else "Departing…",
					Theme.TOAST_SECONDS,
					false
				)
			end
			return
		end
		-- Failure-only by contract, but stay safe against future success payloads.
		if payload.ok ~= false then
			return
		end
		if isCombatAction then
			onCombatActionResult(payload)
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
		-- C0: six keys share the bar, so it needs the viewport to pick a button width that
		-- still fits a 375 px portrait canvas.
		bottomBar.SetLayout(scale, size)
		for _, panel in panels do
			panel.SetLayout(PanelDock.Compute(scale, size, panel.DesignHeight))
		end
		eraScreen.SetLayout(scale, size)
		local card = summaryCard
		if card ~= nil then
			card.SetLayout(scale, size)
		end
		local strip = debugPanel
		if strip ~= nil then
			strip.SetLayout(scale)
		end
		ceremony.SetScale(scale)
		loadScreen.SetScale(scale)
		welcomeCard.SetLayout(scale, landscape)
		local stackedAbove = if welcomeCard.IsVisible()
			then welcomeCard.DesignHeight() + Theme.TOAST_GAP
			else 0
		local inviteCard = inviteToast
		if inviteCard ~= nil then
			inviteCard.SetLayout(scale, landscape, stackedAbove)
			if inviteCard.IsVisible() then
				stackedAbove += inviteCard.DesignHeight() + Theme.TOAST_GAP
			end
		end
		toast.SetLayout(scale, landscape, stackedAbove)
	end

	-- The HUD lives for the whole session (ResetOnSpawn = false); these connections die
	-- with the client. Components expose Destroy() for any future screen rebuild.
	stateChanged.OnClientEvent:Connect(onStateChanged)
	actionResult.OnClientEvent:Connect(onActionResult)
	fxEvent.OnClientEvent:Connect(onFxEvent)
	-- C0: answers the panel's RequestRunList. The access code never reaches the client (the
	-- server strips it), so this is a display list only. Connected once, whenever the event
	-- turns up.
	local runListConnected = false
	local function connectRunList(): ()
		local panel = expeditionPanel
		if runListConnected or panel == nil then
			return
		end
		local event = remotesFolder:FindFirstChild("RunList")
		if event == nil then
			return
		end
		runListConnected = true
		local remote = event :: RemoteEvent
		remote.OnClientEvent:Connect(function(payload: any)
			if typeof(payload) ~= "table" or typeof(payload.runs) ~= "table" then
				return
			end
			panel.SetRuns(payload.runs :: { Types.RunListEntry })
		end)
	end
	connectRunList()
	-- C1: the hub fires this once, on the join sequence, when the player came back from a
	-- run (teleport data, or the Studio bridge's return record). Connected the same way as
	-- RunList: whenever the event turns up, never waited for.
	local summaryConnected = false
	local function connectExpeditionSummary(): ()
		local card = summaryCard
		if summaryConnected or card == nil then
			return
		end
		local event = remotesFolder:FindFirstChild("ExpeditionSummary")
		if event == nil then
			return
		end
		summaryConnected = true
		local remote = event :: RemoteEvent
		remote.OnClientEvent:Connect(function(payload: any)
			local summary = readRunSummary(payload)
			if summary ~= nil then
				showExpeditionSummary(summary)
			end
		end)
	end
	connectExpeditionSummary()
	-- C2: PartyState reaches every member and, per Types, anyone with a pending invite from
	-- that party. The panel shows only a party this player is a MEMBER of; a state that lists
	-- them as neither member nor invitee means that leader's invite is gone (withdrawn,
	-- expired or filled), so its card goes too.
	local localUserId = player.UserId
	local function onPartyState(payload: any): ()
		local party = readHubParty(payload)
		local mine: Types.HubParty? = nil
		local invited = false
		if party ~= nil then
			for _, member in party.members do
				if member.userId == localUserId then
					mine = party
				end
			end
			for _, invite in party.pending do
				if invite.userId == localUserId then
					invited = true
				end
			end
		end
		local expedition = expeditionPanel
		if expedition ~= nil then
			expedition.SetParty(mine)
		end
		local card = inviteToast
		if card ~= nil then
			if mine ~= nil then
				card.Dismiss(nil) -- in a party now, so no other invite can be accepted
			elseif party ~= nil and not invited then
				card.Dismiss(party.leaderUserId)
			end
		end
		local strip = debugPanel
		if strip ~= nil then
			local fakeCount = 0
			if mine ~= nil then
				for _, member in mine.members do
					if member.userId < 0 then
						fakeCount += 1
					end
				end
			end
			strip.SetFakePartyCount(fakeCount)
		end
	end
	local function onPartyInvite(payload: any): ()
		local invite = readPartyInvite(payload)
		local card = inviteToast
		if invite ~= nil and card ~= nil then
			card.Show(invite)
		end
	end
	local partyConnected = false
	local function connectParty(): ()
		if partyConnected or not hasExpeditions then
			return
		end
		local stateEvent = remotesFolder:FindFirstChild("PartyState")
		local inviteEvent = remotesFolder:FindFirstChild("PartyInvite")
		if stateEvent == nil or inviteEvent == nil then
			return
		end
		partyConnected = true
		local stateRemote = stateEvent :: RemoteEvent
		local inviteRemote = inviteEvent :: RemoteEvent
		stateRemote.OnClientEvent:Connect(onPartyState)
		inviteRemote.OnClientEvent:Connect(onPartyInvite)
	end
	connectParty()
	-- Instant boot in both worlds: the HUD never waits on the combat remotes, it just picks
	-- them up if the server creates them a moment later (and drops the listener once it has
	-- everything it needs).
	local function combatWiringComplete(): boolean
		return combatRemotesReady
			and (expeditionPanel == nil or runListConnected)
			and (summaryCard == nil or summaryConnected)
			and (not hasExpeditions or partyConnected)
	end
	if (hasArmory or hasExpeditions) and not combatWiringComplete() then
		local childAdded: RBXScriptConnection? = nil
		childAdded = remotesFolder.ChildAdded:Connect(function()
			resolveCombatRemotes()
			connectRunList()
			connectExpeditionSummary()
			connectParty()
			refreshCombatKeys()
			refreshAll() -- the Power readout follows the same gate as the keys
			local connection = childAdded
			if combatWiringComplete() and connection ~= nil then
				connection:Disconnect()
			end
		end)
	end
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
