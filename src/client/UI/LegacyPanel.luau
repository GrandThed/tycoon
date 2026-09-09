--!strict
-- Legacy panel (M3 contract): legacy count, the current income multiplier, rebirth count,
-- a preview of the next advance's gain, and the Advance Era / Rebirth entry when eligible
-- (UIController decides eligibility exactly as it does for the Build-panel banner). The
-- Legacy shop is Phase 2, so one dim placeholder line is all it gets. Display only:
-- every number is server state or a shared-Economy preview of it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local PanelDock = require(script.Parent:WaitForChild("PanelDock"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = {
	gameConfig: Types.GameConfig,
	onPrestige: () -> (),
	onClose: () -> (),
}

export type LegacyPanelHandle = {
	DesignHeight: number,
	Refresh: (state: Types.PlayerState) -> (),
	SetPrestige: (label: string?) -> (),
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

local LegacyPanel = {}

function LegacyPanel.new(parent: Instance, deps: Deps): LegacyPanelHandle
	local connections: { RBXScriptConnection } = {}

	local panel = Panel.new(parent, {
		name = "LegacyPanel",
		title = "Legacy",
		designHeight = Theme.PANEL_HEIGHT_COMPACT,
		onClose = deps.onClose,
	})
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.INFO_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel.Content,
	})

	local function line(name: string, order: number, color: Color3, bold: boolean): TextLabel
		return Create("TextLabel", {
			Name = name,
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, Theme.INFO_LINE_HEIGHT),
			Font = if bold then Theme.FONT_BOLD else Theme.FONT,
			TextSize = if bold then Theme.TEXT_HEADER else Theme.TEXT_MEDIUM,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = panel.Content,
		}) :: TextLabel
	end

	local legacyLabel = line("LegacyCount", 1, Theme.COLOR_HIGHLIGHT, true)
	local multiplierLabel = line("Multiplier", 2, Theme.COLOR_TEXT, false)
	local rebirthLabel = line("Rebirths", 3, Theme.COLOR_TEXT, false)
	local nextGainLabel = line("NextGain", 4, Theme.COLOR_TEXT_DIM, false)

	local prestigeButton = Create("TextButton", {
		Name = "PrestigeEntry",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Theme.PRESTIGE_ROW_HEIGHT),
		BackgroundColor3 = Theme.COLOR_HIGHLIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Visible = false,
		Parent = panel.Content,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = prestigeButton }
	)

	local perksLabel = line("Perks", 6, Theme.COLOR_TEXT_DIM, false)
	perksLabel.Text = "Legacy perks: coming later"

	local function refresh(state: Types.PlayerState): ()
		legacyLabel.Text = "Legacy: " .. Format.Cash(state.legacy)
		-- Format.Rate is the bounded-decimals formatter; a multiplier is not cash.
		multiplierLabel.Text = "Income multiplier: ×"
			.. Format.Rate(Economy.LegacyMult(state.legacy, deps.gameConfig))
		rebirthLabel.Text = "Rebirths: " .. tostring(state.rebirthCount)
		local totalLevels = 0
		for _, slotState in state.slots do
			totalLevels += slotState.level
		end
		local gain = Economy.LegacyGain(state.era, totalLevels, state.rebirthCount, deps.gameConfig)
		nextGainLabel.Text = "Next advance: +" .. Format.Cash(gain) .. " Legacy"
	end

	table.insert(
		connections,
		prestigeButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onPrestige()
		end)
	)

	local handle: LegacyPanelHandle = {
		DesignHeight = panel.DesignHeight,
		Refresh = refresh,
		SetPrestige = function(label: string?)
			prestigeButton.Visible = label ~= nil
			prestigeButton.Text = label or ""
		end,
		SetOpen = panel.SetOpen,
		IsOpen = panel.IsOpen,
		SetLayout = panel.SetLayout,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			panel.Destroy()
		end,
	}
	return handle
end

return LegacyPanel
