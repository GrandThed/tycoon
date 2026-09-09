--!strict
-- Owns the HUD. The client is a display and input device: the local model below is
-- replaced by server snapshots and patched by deltas, and every button press becomes a
-- remote intent. Cash and income are never computed here; Build-panel previews and the
-- Legacy previews use the shared pure Economy module and are overwritten by the next
-- server push (docs/INTERFACES.md, M1–M3 client contracts). M3 adds the bottom bar with
-- Legacy/Settings panels, the era-advance screen, the ceremony overlay, the welcome-back
-- card, sound hooks, and the landscape docking layout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Economy = require(sharedFolder:WaitForChild("Economy"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local PanelDock = require(uiFolder:WaitForChild("PanelDock"))
local TopBar = require(uiFolder:WaitForChild("TopBar"))
local BottomBar = require(uiFolder:WaitForChild("BottomBar"))
local BuildPanel = require(uiFolder:WaitForChild("BuildPanel"))
local LegacyPanel = require(uiFolder:WaitForChild("LegacyPanel"))
local SettingsPanel = require(uiFolder:WaitForChild("SettingsPanel"))
local EraAdvanceScreen = require(uiFolder:WaitForChild("EraAdvanceScreen"))
local Ceremony = require(uiFolder:WaitForChild("Ceremony"))
local WelcomeBackCard = require(uiFolder:WaitForChild("WelcomeBackCard"))
local Toast = require(uiFolder:WaitForChild("Toast"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

type Model = {
	plotIndex: number,
	eraName: string,
	state: Types.PlayerState,
	incomePerSecond: number,
}

type PrestigeKind = "advance" | "rebirth"

type PanelKey = "build" | "legacy" | "settings"

-- Every dockable panel exposes this slice; UIController keeps one open at a time.
type DockablePanel = {
	DesignHeight: number,
	SetOpen: (open: boolean) -> (),
	SetLayout: (dock: PanelDock.Dock) -> (),
}

local FIRST_ERA = 1

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

	local gameConfig = Catalog.GetGameConfig()

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

	-- Forward declarations: layout and panel wiring reference each other.
	local applyLayout: () -> ()

	local topBar = TopBar.new(screenGui)
	local toast = Toast.new(screenGui)
	local welcomeCard = WelcomeBackCard.new(screenGui, {
		onVisibilityChanged = function()
			applyLayout() -- the toast stacks below the card while it is visible
		end,
	})
	local eraScreen = EraAdvanceScreen.new(screenGui)
	local ceremony = Ceremony.new(screenGui, {
		onClosed = function()
			-- Contract: the new era's ambient starts after the overlay, not under the jingle.
			local current = model
			if current ~= nil then
				SoundController.SetAmbientEra(current.eraName)
			end
		end,
	})

	-- String-keyed so the three panels can be registered after their deps exist below.
	local panels: { [string]: DockablePanel } = {}
	local togglePanel: (key: PanelKey) -> ()
	local bottomBar = BottomBar.new(screenGui, {
		onTap = function(key: BottomBar.BarKey)
			-- Shop stays hidden until M4 wires monetization ids; nothing to open.
			if key == "build" or key == "legacy" or key == "settings" then
				togglePanel(key)
			end
		end,
	})
	bottomBar.SetShopVisible(false)

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
		onPrestige = openPrestigeScreen,
		onClose = closePanels,
	})
	local settingsPanel = SettingsPanel.new(screenGui, {
		onToggle = function(key: Types.SettingKey, value: boolean)
			-- Apply locally at once; the next snapshot/delta is authoritative.
			local current = model
			if current ~= nil then
				if key == "music" then
					current.state.settings.music = value
				else
					current.state.settings.sfx = value
				end
				SoundController.ApplySettings(current.state.settings)
			end
			requestSetSetting:FireServer(key, value)
		end,
		onClose = closePanels,
	})
	panels.build = buildPanel
	panels.legacy = legacyPanel
	panels.settings = settingsPanel

	local function applySettings(settings: { music: boolean, sfx: boolean }): ()
		SoundController.ApplySettings(settings)
		settingsPanel.SetSettings(settings)
	end

	local function refreshAll(): ()
		local current = model
		if current == nil then
			return
		end
		local state = current.state
		topBar.SetCash(state.cash)
		topBar.SetIncome(current.incomePerSecond)
		topBar.SetLegacy(state.legacy)
		-- Deltas can deliver the monument purchase, so the affordance recomputes every push.
		local prestigeLabel = prestigeLabelFor(prestigeKindFor(state), state)
		buildPanel.SetPrestige(prestigeLabel)
		legacyPanel.SetPrestige(prestigeLabel)
		buildPanel.Refresh(state)
		legacyPanel.Refresh(state)
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
		}
		if eraChanged then
			-- Any open prestige screen described the era we just left; its numbers are stale.
			eraScreen.Hide()
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
		refreshAll()
	end

	local function onStateChanged(payload: any): ()
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "snapshot" then
			applySnapshot(payload)
		elseif payload.kind == "delta" then
			applyDelta(payload)
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
		elseif typeof(payload.slotId) == "string" and payload.slotId ~= "" then
			-- M3 contract: every slot failure flashes the row; only a failed payment sounds.
			buildPanel.FlashSlot(payload.slotId)
			if payload.reason == "insufficientFunds" then
				SoundController.Play("insufficientFunds")
			end
		end
	end

	-- eraAdvance / rebirth only; PlotVisualsController owns reveal / levelUp.
	local function onFxEvent(payload: any): ()
		if typeof(payload) ~= "table" or typeof(payload.toEra) ~= "number" then
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
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	applyLayout()
	onCashAttribute()
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
