--!strict
-- Minimal modal confirm used for Advance Era / Rebirth (M2). Deliberately generic:
-- UIController composes the copy from server state and shared Economy previews; this
-- module only renders lines and routes taps. The full era-advance ceremony replaces it
-- at M3. Cancel must always be the easy path on mobile, so the Cancel button meets the
-- 44 px tap-target rule and any tap on the scrim outside the card also dismisses.

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type DialogLine = { text: string, color: Color3?, bold: boolean? }

export type DialogOptions = {
	title: string,
	lines: { DialogLine },
	confirmText: string,
	onConfirm: () -> (),
}

export type ConfirmDialogHandle = {
	Show: (options: DialogOptions) -> (),
	Hide: () -> (),
	SetScale: (scale: number) -> (),
	Destroy: () -> (),
}

local ConfirmDialog = {}

function ConfirmDialog.new(parent: Instance): ConfirmDialogHandle
	local currentOnConfirm: (() -> ())? = nil
	local lineLabels: { TextLabel } = {}
	local connections: { RBXScriptConnection } = {}

	-- A TextButton scrim so tapping anywhere outside the card cancels. Modal on purpose
	-- (unlike the toast): a prestige confirm should block stray taps behind it.
	local scrim = Create("TextButton", {
		Name = "ConfirmDialog",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = Theme.SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = Theme.ZINDEX_DIALOG,
		Parent = parent,
	}) :: TextButton

	-- Active sinks input so taps on the card body don't fall through to the scrim-cancel.
	local card = Create("Frame", {
		Name = "Card",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.DIALOG_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.COLOR_BG,
		BorderSizePixel = 0,
		Parent = scrim,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = card })
	local uiScale = Create("UIScale", { Parent = card }) :: UIScale
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingBottom = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingLeft = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingRight = UDim.new(0, Theme.DIALOG_PADDING),
		Parent = card,
	})
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.DIALOG_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = card,
	})

	local titleLabel = Create("TextLabel", {
		Name = "Title",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_LARGE,
		TextColor3 = Theme.COLOR_TEXT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = card,
	}) :: TextLabel

	-- Row height includes a top gap; buttons anchor to its bottom edge so the list gap
	-- plus this gap separates them from the last copy line.
	local buttonRow = Create("Frame", {
		Name = "Buttons",
		LayoutOrder = 1000,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.DIALOG_BUTTON_HEIGHT + Theme.DIALOG_BUTTON_TOP_GAP),
		Parent = card,
	}) :: Frame
	local cancelButton = Create("TextButton", {
		Name = "Cancel",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -Theme.DIALOG_BUTTON_GAP / 2, 0, Theme.DIALOG_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "Cancel",
		Parent = buttonRow,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = cancelButton }
	)
	local confirmButton = Create("TextButton", {
		Name = "Confirm",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -Theme.DIALOG_BUTTON_GAP / 2, 0, Theme.DIALOG_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_ACCENT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "Confirm",
		Parent = buttonRow,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = confirmButton }
	)

	local function hide(): ()
		currentOnConfirm = nil
		scrim.Visible = false
	end

	local function show(options: DialogOptions): ()
		for _, label in lineLabels do
			label:Destroy()
		end
		table.clear(lineLabels)
		titleLabel.Text = options.title
		for index, line in options.lines do
			local label = Create("TextLabel", {
				Name = "Line" .. tostring(index),
				LayoutOrder = 1 + index,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Font = if line.bold then Theme.FONT_BOLD else Theme.FONT,
				TextSize = Theme.TEXT_MEDIUM,
				TextColor3 = line.color or Theme.COLOR_TEXT_DIM,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = line.text,
				Parent = card,
			}) :: TextLabel
			table.insert(lineLabels, label)
		end
		confirmButton.Text = options.confirmText
		currentOnConfirm = options.onConfirm
		scrim.Visible = true
	end

	table.insert(connections, scrim.Activated:Connect(hide))
	table.insert(connections, cancelButton.Activated:Connect(hide))
	table.insert(
		connections,
		confirmButton.Activated:Connect(function()
			-- Hide before firing so a slow server round-trip never leaves a stale modal up.
			local callback = currentOnConfirm
			hide()
			if callback ~= nil then
				callback()
			end
		end)
	)

	local handle: ConfirmDialogHandle = {
		Show = show,
		Hide = hide,
		SetScale = function(scale: number)
			uiScale.Scale = scale
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			currentOnConfirm = nil
			scrim:Destroy()
		end,
	}
	return handle
end

return ConfirmDialog
