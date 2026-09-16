--!strict
-- Settings panel (M3 contract): Music and SFX toggles bound to state.settings. A tap flips
-- the toggle at once (UIController applies it to SoundController and fires
-- RequestSetSetting); the next snapshot/delta is authoritative and SetSettings re-paints
-- from it. The VIP skins row (2026-09-16 amendment) exists only for VIP owners: hidden, not
-- disabled, so non-VIP players never see a setting they cannot use.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local Create = require(script.Parent:WaitForChild("Create"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local PanelDock = require(script.Parent:WaitForChild("PanelDock"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Settings = { music: boolean, sfx: boolean, vipSkins: boolean }

export type Deps = {
	onToggle: (key: Types.SettingKey, value: boolean) -> (),
	onClose: () -> (),
}

export type SettingsPanelHandle = {
	DesignHeight: number,
	SetSettings: (settings: Settings) -> (),
	SetVipVisible: (visible: boolean) -> (),
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

type ToggleRow = { key: Types.SettingKey, row: Frame, button: TextButton, value: boolean }

local ROWS: { { key: Types.SettingKey, label: string } } = {
	{ key = "music", label = "Music" },
	{ key = "sfx", label = "Sound effects" },
	{ key = "vipSkins", label = "VIP building skins" },
}

-- Rows shown only while the player owns the VIP pass.
local VIP_ONLY: { [string]: boolean } = { vipSkins = true }

local SettingsPanel = {}

function SettingsPanel.new(parent: Instance, deps: Deps): SettingsPanelHandle
	local connections: { RBXScriptConnection } = {}
	local toggles: { [string]: ToggleRow } = {}

	local panel = Panel.new(parent, {
		name = "SettingsPanel",
		title = "Settings",
		designHeight = Theme.PANEL_HEIGHT_COMPACT,
		onClose = deps.onClose,
	})
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ROW_SPACING),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel.Content,
	})

	local function paint(toggle: ToggleRow): ()
		toggle.button.Text = if toggle.value then "ON" else "OFF"
		toggle.button.BackgroundColor3 = if toggle.value
			then Theme.COLOR_ACCENT
			else Theme.COLOR_BG_LIGHT
		toggle.button.TextColor3 = if toggle.value then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT
	end

	for index, entry in ROWS do
		local row = Create("Frame", {
			Name = entry.key,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, Theme.SETTINGS_ROW_HEIGHT),
			-- UIListLayout skips invisible children, so a hidden row leaves no gap.
			Visible = not VIP_ONLY[entry.key],
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Parent = panel.Content,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = row })
		Create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, 0),
			Size = UDim2.new(
				1,
				-Theme.ROW_TEXT_LEFT - Theme.TOGGLE_WIDTH - Theme.ROW_TEXT_GAP,
				1,
				0
			),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = entry.label,
			Parent = row,
		})
		local button = Create("TextButton", {
			Name = "Toggle",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Theme.ROW_SPACING, 0.5, 0),
			Size = UDim2.fromOffset(Theme.TOGGLE_WIDTH, Theme.TOGGLE_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			Text = "ON",
			Parent = row,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		local toggle: ToggleRow = { key = entry.key, row = row, button = button, value = true }
		toggles[entry.key] = toggle
		paint(toggle)
		table.insert(
			connections,
			button.Activated:Connect(function()
				-- Flip locally first so the click itself reflects the new SFX state.
				toggle.value = not toggle.value
				paint(toggle)
				deps.onToggle(toggle.key, toggle.value)
				SoundController.Play("uiClick")
			end)
		)
	end

	local handle: SettingsPanelHandle = {
		DesignHeight = panel.DesignHeight,
		SetSettings = function(settings: Settings)
			for key, toggle in toggles do
				local value = (settings :: any)[key]
				if typeof(value) == "boolean" then
					toggle.value = value
					paint(toggle)
				end
			end
		end,
		SetVipVisible = function(visible: boolean)
			for key, toggle in toggles do
				if VIP_ONLY[key] then
					toggle.row.Visible = visible
				end
			end
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

return SettingsPanel
