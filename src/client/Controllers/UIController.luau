--!strict
-- Owns the HUD. The client is a display and input device: the local model below is
-- replaced by server snapshots and patched by deltas, and every button press becomes a
-- remote intent. Cash and income are never computed here; Build-panel previews and the
-- Advance-Era legacy preview use the shared pure Economy module and are overwritten by
-- the next server push (docs/INTERFACES.md, M1/M2 client contracts).

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
local TopBar = require(uiFolder:WaitForChild("TopBar"))
local BuildPanel = require(uiFolder:WaitForChild("BuildPanel"))
local ConfirmDialog = require(uiFolder:WaitForChild("ConfirmDialog"))
local Toast = require(uiFolder:WaitForChild("Toast"))

type Model = {
	plotIndex: number,
	eraName: string,
	state: Types.PlayerState,
	incomePerSecond: number,
}

type PrestigeKind = "advance" | "rebirth"

local function getEraCount(): number
	return Catalog.GetEraCount()
end

-- e.g. 11520 -> "3h 12m". Durations are not cash, so Format.Cash does not apply; the
-- welcomeBack contract guarantees elapsed >= 60 s but the seconds branch stays anyway.
local function humanizeDuration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end
	if minutes > 0 then
		return string.format("%dm", minutes)
	end
	return string.format("%ds", total)
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
	local eraCount = getEraCount()
	if state.era < eraCount then
		return "advance"
	elseif state.era == eraCount then
		return "rebirth"
	end
	return nil
end

local function prestigeLabelFor(kind: PrestigeKind?, state: Types.PlayerState): string?
	if kind == "advance" then
		local nextEra = Catalog.GetEraConfig(state.era + 1)
		-- Missing next-era config degrades to a generic label, never an error.
		return if nextEra ~= nil then "Advance Era → " .. nextEra.name else "Advance Era"
	elseif kind == "rebirth" then
		return "Rebirth → Era 1"
	end
	return nil
end

local UIController = {}

local function boot(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- RemoteService creates this folder at server Init; wait rather than assume order.
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent
	local actionResult = remotesFolder:WaitForChild("ActionResult") :: RemoteEvent
	local requestSnapshot = remotesFolder:WaitForChild("RequestSnapshot") :: RemoteEvent
	local requestBuy = remotesFolder:WaitForChild("RequestBuy") :: RemoteEvent
	local requestLevelUp = remotesFolder:WaitForChild("RequestLevelUp") :: RemoteEvent
	local requestAdvanceEra = remotesFolder:WaitForChild("RequestAdvanceEra") :: RemoteEvent
	local requestRebirth = remotesFolder:WaitForChild("RequestRebirth") :: RemoteEvent

	local gameConfig = Catalog.GetGameConfig()

	local screenGui = Create("ScreenGui", {
		Name = "EraCityHUD",
		ResetOnSpawn = false,
		Parent = playerGui,
	}) :: ScreenGui

	local topBar = TopBar.new(screenGui)
	-- ZIndex tiers in Theme keep the dialog above the HUD and the toast above the
	-- dialog regardless of this creation order.
	local dialog = ConfirmDialog.new(screenGui)
	local toast = Toast.new(screenGui)

	local model: Model? = nil
	-- The contract puts welcomeBack only on the first post-grant snapshot, but duplicate
	-- snapshots must be harmless, so the toast additionally fires at most once a session.
	local welcomeBackShown = false

	local function openPrestigeDialog(): ()
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
		local totalLevels = 0
		for _, slotState in state.slots do
			totalLevels += slotState.level
		end
		local gain = Economy.LegacyGain(state.era, totalLevels, state.rebirthCount, gameConfig)
		if kind == "advance" then
			local nextEra = Catalog.GetEraConfig(state.era + 1)
			local nextName = if nextEra ~= nil then nextEra.name else "the next era"
			-- Resets/persists copy mirrors spec §3 exactly: cash/slots/levels/plot reset;
			-- Legacy, era progress, rebirth count, and stats persist.
			dialog.Show({
				title = "Advance to " .. nextName .. "?",
				lines = {
					{
						text = "Earn +" .. Format.Cash(gain) .. " Legacy",
						color = Theme.COLOR_HIGHLIGHT,
						bold = true,
					},
					{ text = "Resets: cash, buildings, levels, and your plot" },
					{ text = "Keeps: Legacy, era progress, rebirth count, and stats" },
				},
				confirmText = "Advance Era",
				onConfirm = function()
					requestAdvanceEra:FireServer()
				end,
			})
		else
			dialog.Show({
				title = "Rebirth?",
				lines = {
					{
						text = "Earn +" .. Format.Cash(gain) .. " Legacy",
						color = Theme.COLOR_HIGHLIGHT,
						bold = true,
					},
					{
						text = "Your " .. Format.Cash(state.legacy) .. " Legacy is KEPT",
						color = Theme.COLOR_TEXT,
					},
					{
						text = "Rebirths: " .. tostring(state.rebirthCount) .. " → " .. tostring(
							state.rebirthCount + 1
						) .. " — future eras grant more Legacy",
						color = Theme.COLOR_TEXT,
					},
					{ text = "Start over in Era 1 with your permanent bonuses" },
					{ text = "Resets: cash, buildings, levels, and your plot" },
					{ text = "Keeps: Legacy, rebirth count, and stats" },
				},
				confirmText = "Rebirth",
				onConfirm = function()
					requestRebirth:FireServer()
				end,
			})
		end
	end

	local buildPanel = BuildPanel.new(screenGui, {
		gameConfig = gameConfig,
		onBuy = function(slotId: string)
			requestBuy:FireServer(slotId)
		end,
		onLevelUp = function(slotId: string, count: number)
			requestLevelUp:FireServer(slotId, count)
		end,
		onPrestige = openPrestigeDialog,
	})

	local function refreshAll(): ()
		local current = model
		if current == nil then
			return
		end
		topBar.SetCash(current.state.cash)
		topBar.SetIncome(current.incomePerSecond)
		topBar.SetLegacy(current.state.legacy)
		-- Deltas can deliver the monument purchase, so the banner recomputes every push.
		buildPanel.SetPrestige(prestigeLabelFor(prestigeKindFor(current.state), current.state))
		buildPanel.Refresh(current.state)
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
			-- Any open confirm described the era we just left; its numbers are stale.
			dialog.Hide()
		end
		topBar.SetEra(snapshot.state.era, snapshot.eraName)
		-- Missing era config degrades to the panel's empty state, never an error.
		-- BuildPanel.SetEra skips rebuilds only when eraIndex matches, so an era-changing
		-- snapshot always rebuilds the rows (M2 contract check).
		buildPanel.SetEra(Catalog.GetEraConfig(snapshot.state.era))
		refreshAll()

		-- Read from the raw payload: the welcomeBack field is an M2 Snapshot amendment
		-- and may precede the Types.luau update in the concurrent server wave.
		local welcomeBack = payload.welcomeBack
		if
			not welcomeBackShown
			and typeof(welcomeBack) == "table"
			and typeof(welcomeBack.grantedCash) == "number"
			and typeof(welcomeBack.elapsedSeconds) == "number"
		then
			welcomeBackShown = true
			toast.Show(
				"You earned $"
					.. Format.Cash(welcomeBack.grantedCash)
					.. " while away — "
					.. humanizeDuration(welcomeBack.elapsedSeconds)
					.. " offline",
				Theme.TOAST_SECONDS,
				false
			)
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
			buildPanel.FlashSlot(payload.slotId)
		end
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

	local function applyScale(): ()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return -- AbsoluteSize is zero before first layout; the changed signal re-enters
		end
		-- MIN_SCALE is derived in Theme so tap targets never drop below 44 physical px;
		-- the panel adapts its height to the viewport inside SetLayout (landscape fix).
		local scale = math.clamp(
			math.min(size.X / Theme.DESIGN_WIDTH, size.Y / Theme.DESIGN_HEIGHT),
			Theme.MIN_SCALE,
			Theme.MAX_SCALE
		)
		topBar.SetScale(scale)
		buildPanel.SetLayout(scale, size)
		dialog.SetScale(scale)
		toast.SetScale(scale)
	end

	-- The HUD lives for the whole session (ResetOnSpawn = false); these connections die
	-- with the client. Components expose Destroy() for when M3 rebuilds screens.
	stateChanged.OnClientEvent:Connect(onStateChanged)
	actionResult.OnClientEvent:Connect(onActionResult)
	player:GetAttributeChangedSignal("Cash"):Connect(onCashAttribute)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)

	applyScale()
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
