--!strict
-- Era-advance screen (spec §10, M3 contract), also used for Rebirth with rebirth copy:
-- next era name + index, a preview of what is coming (first three buildings and the
-- monument of the next era config), resets-vs-persists columns, the Legacy to be gained
-- (client preview via shared Economy, computed by UIController), and explicit Confirm /
-- Cancel. Modal on purpose: the scrim blocks stray taps only while this screen is open,
-- and tapping the scrim cancels. Fixed-aspect card sized to fit a 320 px tall viewport.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type PrestigeKind = "advance" | "rebirth"

export type ShowOptions = {
	kind: PrestigeKind,
	nextEraIndex: number,
	nextEraName: string, -- displayName already resolved (with fallback) by the caller
	nextEraConfig: Types.EraConfig?,
	legacyGain: number,
	legacy: number,
	rebirthCount: number,
	onConfirm: () -> (),
}

export type EraAdvanceScreenHandle = {
	Show: (options: ShowOptions) -> (),
	Hide: () -> (),
	IsOpen: () -> boolean,
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

local PREVIEW_BUILDINGS = 3

-- Spec §3: what resets and what persists. Rebirth keeps Legacy too (M2 lead ruling).
local RESETS_COPY = "Cash\nBuildings\nLevels\nPlot"
local KEEPS_COPY_ADVANCE = "Legacy\nEra progress\nRebirth count\nPasses & stats"
local KEEPS_COPY_REBIRTH = "Legacy (kept!)\nRebirth count +1\nPasses & stats\nCosmetic rank"

local EraAdvanceScreen = {}

local function previewCopy(eraConfig: Types.EraConfig?): string
	if eraConfig == nil then
		return "Era data unavailable"
	end
	local buildings: { string } = {}
	local monumentName: string? = nil
	for _, slot in eraConfig.slots do
		if slot.type == "building" and #buildings < PREVIEW_BUILDINGS then
			table.insert(buildings, slot.name)
		elseif slot.type == "monument" then
			monumentName = slot.name
		end
	end
	local text = "Coming up: " .. table.concat(buildings, ", ")
	if monumentName ~= nil then
		text ..= "\nMonument: " .. monumentName
	end
	return text
end

function EraAdvanceScreen.new(parent: Instance): EraAdvanceScreenHandle
	local currentOnConfirm: (() -> ())? = nil
	local connections: { RBXScriptConnection } = {}

	local scrim = Create("TextButton", {
		Name = "EraAdvanceScreen",
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
		Size = UDim2.fromOffset(Theme.ERA_SCREEN_WIDTH, Theme.ERA_SCREEN_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG,
		BorderSizePixel = 0,
		Parent = scrim,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = card })
	Create("UIAspectRatioConstraint", {
		AspectRatio = Theme.ERA_SCREEN_WIDTH / Theme.ERA_SCREEN_HEIGHT,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
		Parent = card,
	})
	local uiScale = Create("UIScale", { Parent = card }) :: UIScale

	local padding = Theme.ERA_SCREEN_PADDING
	local gap = Theme.ERA_SCREEN_GAP
	local innerWidth = -padding * 2

	local function label(
		name: string,
		y: number,
		height: number,
		font: Enum.Font,
		textSize: number,
		color: Color3
	): TextLabel
		return Create("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(padding, y),
			Size = UDim2.new(1, innerWidth, 0, height),
			Font = font,
			TextSize = textSize,
			TextColor3 = color,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = card,
		}) :: TextLabel
	end

	local y = padding
	local kickerLabel = label(
		"Kicker",
		y,
		Theme.ERA_KICKER_HEIGHT,
		Theme.FONT,
		Theme.TEXT_SMALL,
		Theme.COLOR_TEXT_DIM
	)
	y += Theme.ERA_KICKER_HEIGHT + gap
	local titleLabel = label(
		"Title",
		y,
		Theme.ERA_TITLE_HEIGHT,
		Theme.FONT_BOLD,
		Theme.TEXT_LARGE,
		Theme.COLOR_TEXT
	)
	y += Theme.ERA_TITLE_HEIGHT + gap
	local previewLabel = label(
		"Preview",
		y,
		Theme.ERA_PREVIEW_HEIGHT,
		Theme.FONT,
		Theme.TEXT_SMALL,
		Theme.COLOR_ACCENT
	)
	y += Theme.ERA_PREVIEW_HEIGHT + gap

	local columnsY = y
	local function column(name: string, header: string, left: boolean): TextLabel
		local frame = Create("Frame", {
			Name = name,
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(if left then 0 else 1, 0),
			Position = UDim2.new(
				if left then 0 else 1,
				if left then padding else -padding,
				0,
				columnsY
			),
			Size = UDim2.new(0.5, -padding - Theme.ERA_COLUMN_GAP / 2, 0, Theme.ERA_COLUMNS_HEIGHT),
			Parent = card,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
		Create("TextLabel", {
			Name = "Header",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, 0),
			Size = UDim2.new(1, -Theme.ROW_TEXT_LEFT * 2, 0, Theme.ERA_KICKER_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = if left then Theme.COLOR_ERROR else Theme.COLOR_ACCENT,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = header,
			Parent = frame,
		})
		return Create("TextLabel", {
			Name = "Body",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.ERA_KICKER_HEIGHT),
			Size = UDim2.new(1, -Theme.ROW_TEXT_LEFT * 2, 1, -Theme.ERA_KICKER_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = "",
			Parent = frame,
		}) :: TextLabel
	end
	local resetsBody = column("Resets", "RESETS", true)
	local keepsBody = column("Keeps", "KEEPS", false)
	resetsBody.Text = RESETS_COPY
	y += Theme.ERA_COLUMNS_HEIGHT + gap

	local legacyLabel = label(
		"LegacyGain",
		y,
		Theme.ERA_LEGACY_LINE_HEIGHT,
		Theme.FONT_BOLD,
		Theme.TEXT_HEADER,
		Theme.COLOR_HIGHLIGHT
	)
	legacyLabel.TextXAlignment = Enum.TextXAlignment.Center
	y += Theme.ERA_LEGACY_LINE_HEIGHT + gap

	local cancelButton = Create("TextButton", {
		Name = "Cancel",
		Position = UDim2.fromOffset(padding, y),
		Size = UDim2.new(
			0.5,
			-padding - Theme.DIALOG_BUTTON_GAP / 2,
			0,
			Theme.DIALOG_BUTTON_HEIGHT
		),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "Cancel",
		Parent = card,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = cancelButton }
	)
	local confirmButton = Create("TextButton", {
		Name = "Confirm",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -padding, 0, y),
		Size = UDim2.new(
			0.5,
			-padding - Theme.DIALOG_BUTTON_GAP / 2,
			0,
			Theme.DIALOG_BUTTON_HEIGHT
		),
		BackgroundColor3 = Theme.COLOR_ACCENT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "Confirm",
		Parent = card,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = confirmButton }
	)

	local function hide(): ()
		currentOnConfirm = nil
		scrim.Visible = false
	end

	local function show(options: ShowOptions): ()
		local rebirth = options.kind == "rebirth"
		kickerLabel.Text = if rebirth
			then "REBIRTH ×" .. tostring(options.rebirthCount + 1) .. " — start over stronger"
			else "ADVANCE ERA"
		titleLabel.Text = "ERA " .. tostring(options.nextEraIndex) .. " — " .. options.nextEraName
		previewLabel.Text = previewCopy(options.nextEraConfig)
		keepsBody.Text = if rebirth then KEEPS_COPY_REBIRTH else KEEPS_COPY_ADVANCE
		legacyLabel.Text = "+" .. Format.Cash(options.legacyGain) .. " Legacy"
		if rebirth then
			legacyLabel.Text ..= "  (" .. Format.Cash(options.legacy) .. " kept)"
		end
		confirmButton.Text = if rebirth then "Rebirth" else "Advance Era"
		currentOnConfirm = options.onConfirm
		scrim.Visible = true
	end

	local function cancel(): ()
		if scrim.Visible then
			SoundController.Play("uiClick")
		end
		hide()
	end

	table.insert(connections, scrim.Activated:Connect(cancel))
	table.insert(connections, cancelButton.Activated:Connect(cancel))
	table.insert(
		connections,
		confirmButton.Activated:Connect(function()
			-- Hide before firing so a slow server round-trip never leaves a stale modal up.
			local callback = currentOnConfirm
			SoundController.Play("uiClick")
			hide()
			if callback ~= nil then
				callback()
			end
		end)
	)

	local handle: EraAdvanceScreenHandle = {
		Show = show,
		Hide = hide,
		IsOpen = function()
			return scrim.Visible
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			-- Shrink below the HUD scale only when the card would not fit the viewport;
			-- never below MIN_SCALE, so the buttons keep their 44 px.
			local margin = Theme.SCREEN_MARGIN * 2 * scale
			local fit = math.min(
				scale,
				(viewportSize.Y - margin) / Theme.ERA_SCREEN_HEIGHT,
				(viewportSize.X - margin) / Theme.ERA_SCREEN_WIDTH
			)
			uiScale.Scale = math.max(fit, Theme.MIN_SCALE)
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

return EraAdvanceScreen
