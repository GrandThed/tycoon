--!strict
-- Legacy panel (M3 contract): legacy count, the current income multiplier, rebirth count,
-- a preview of the next advance's gain, and the Advance Era / Rebirth entry when eligible
-- (UIController decides eligibility exactly as it does for the Build-panel banner). The
-- Legacy shop is Phase 2, so one dim placeholder line is all it gets. Display only:
-- every number is server state or a shared-Economy preview of it.
--
-- M4 adds the bonuses readout (contract: top bar or Legacy panel, my judgment): the
-- neighbors bonus (spec §4, always shown so players see why friends help) plus VIP and
-- Premium lines that only exist while the player actually has them. The 375x667 top bar
-- is already four values wide, so this lives here; the content scrolls because a
-- 360 px-tall landscape viewport cannot show every line at once.

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
	monetization: Types.MonetizationConfig,
	onPrestige: () -> (),
	onClose: () -> (),
}

export type LegacyPanelHandle = {
	DesignHeight: number,
	Refresh: (state: Types.PlayerState) -> (),
	SetBonuses: (vip: boolean, premium: boolean, playerCount: number) -> (),
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
		-- Full height since M4 added the bonuses block: at 375x667 every line fits
		-- without scrolling, and short landscape viewports scroll instead of clipping.
		designHeight = Theme.PANEL_HEIGHT,
		onClose = deps.onClose,
	})
	local scroll = Create("ScrollingFrame", {
		Name = "Lines",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		ScrollBarImageColor3 = Theme.COLOR_TEXT_DIM,
		Parent = panel.Content,
	}) :: ScrollingFrame
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.INFO_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	local function line(name: string, order: number, color: Color3, bold: boolean): TextLabel
		return Create("TextLabel", {
			Name = name,
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.INFO_LINE_HEIGHT),
			Font = if bold then Theme.FONT_BOLD else Theme.FONT,
			TextSize = if bold then Theme.TEXT_HEADER else Theme.TEXT_MEDIUM,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = scroll,
		}) :: TextLabel
	end

	local legacyLabel = line("LegacyCount", 1, Theme.COLOR_HIGHLIGHT, true)
	local multiplierLabel = line("Multiplier", 2, Theme.COLOR_TEXT, false)
	local rebirthLabel = line("Rebirths", 3, Theme.COLOR_TEXT, false)
	local nextGainLabel = line("NextGain", 4, Theme.COLOR_TEXT_DIM, false)

	local prestigeButton = Create("TextButton", {
		Name = "PrestigeEntry",
		LayoutOrder = 5,
		Size = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.PRESTIGE_ROW_HEIGHT),
		BackgroundColor3 = Theme.COLOR_HIGHLIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Visible = false,
		Parent = scroll,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = prestigeButton }
	)

	local bonusesHeader = line("Bonuses", 6, Theme.COLOR_TEXT_DIM, true)
	bonusesHeader.Text = "BONUSES"
	local neighborsLabel = line("Neighbors", 7, Theme.COLOR_ACCENT_ALT, false)
	local vipLabel = line("Vip", 8, Theme.COLOR_HIGHLIGHT, false)
	vipLabel.Visible = false
	local premiumLabel = line("Premium", 9, Theme.COLOR_HIGHLIGHT, false)
	premiumLabel.Visible = false

	local perksLabel = line("Perks", 10, Theme.COLOR_TEXT_DIM, false)
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

	-- Multipliers are previews of what the server already applied to incomePerSecond; the
	-- numbers come from the same shared config the server reads, never from the client.
	local function setBonuses(vip: boolean, premium: boolean, playerCount: number): ()
		local neighbors = Economy.NeighborsMult(playerCount, deps.gameConfig)
		neighborsLabel.Text = "Neighbors: ×"
			.. Format.Rate(neighbors)
			.. " ("
			.. tostring(playerCount)
			.. (if playerCount == 1 then " player)" else " players)")
		local multipliers = deps.monetization.multipliers
		vipLabel.Visible = vip
		vipLabel.Text = "VIP: ×" .. Format.Rate(multipliers.vip) .. " income"
		premiumLabel.Visible = premium
		premiumLabel.Text = "Premium: ×" .. Format.Rate(multipliers.premium) .. " income"
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
		SetBonuses = setBonuses,
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
