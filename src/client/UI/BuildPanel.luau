--!strict
-- Build panel plus its bottom-bar toggle button. Rows come from the era config and
-- their live state from server pushes. Costs and income deltas shown here are previews
-- computed with the shared pure Economy module; the server stays authoritative and the
-- next snapshot/delta overwrites anything predicted (docs/INTERFACES.md, M1 client
-- contract).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

-- Legacy/neighbors multipliers activate at M2, pass/premium at M4; M1 previews pass
-- all 1s per INTERFACES.md so client math matches the server's.
local UNIT_MULTIPLIERS: Types.Multipliers = { legacy = 1, pass = 1, premium = 1, neighbors = 1 }

export type Deps = {
	gameConfig: Types.GameConfig,
	onBuy: (slotId: string) -> (),
	onLevelUp: (slotId: string, count: number) -> (),
	onPrestige: () -> (),
}

export type BuildPanelHandle = {
	SetEra: (eraConfig: Types.EraConfig?) -> (),
	Refresh: (state: Types.PlayerState) -> (),
	FlashSlot: (slotId: string) -> (),
	SetPrestige: (label: string?) -> (),
	SetOpen: (open: boolean) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

type RowMode = "locked" | "buy" | "level" | "max" | "owned"

type Row = {
	slot: Types.SlotConfig,
	requiresId: string?,
	frame: Frame,
	nameLabel: TextLabel,
	statusLabel: TextLabel,
	previewLabel: TextLabel,
	button: TextButton,
	buttonTitle: TextLabel,
	buttonCost: TextLabel,
	stroke: UIStroke,
	mode: RowMode,
	cost: number,
	flashUntil: number,
}

local BuildPanel = {}

function BuildPanel.new(parent: Instance, deps: Deps): BuildPanelHandle
	local currentEra: Types.EraConfig? = nil
	local rows: { Row } = {}
	local rowsById: { [string]: Row } = {}
	local namesById: { [string]: string } = {}
	local lastState: Types.PlayerState? = nil
	local isOpen = false
	local currentScale = 1
	local openTween: Tween? = nil
	local lastActionTime = 0
	local connections: { RBXScriptConnection } = {}

	local buildButton = Create("TextButton", {
		Name = "BuildButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.PADDING),
		Size = UDim2.fromOffset(Theme.BUILD_BUTTON_WIDTH, Theme.BUILD_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_ACCENT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "Build",
		Parent = parent,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = buildButton })
	local buttonScale = Create("UIScale", { Parent = buildButton }) :: UIScale

	local panel = Create("Frame", {
		Name = "BuildPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.PANEL_BOTTOM_MARGIN),
		Size = UDim2.fromOffset(Theme.PANEL_WIDTH, Theme.PANEL_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = panel })
	-- No aspect-ratio lock here: SetLayout derives the panel height from the real
	-- viewport (M1 review decision — landscape phones get a shorter, scrollable panel
	-- rather than a scaled-down portrait canvas). M3's landscape layout may revisit.
	local panelScale = Create("UIScale", { Parent = panel }) :: UIScale

	local titleLabel = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(Theme.PADDING + 2, 0),
		Size = UDim2.new(1, -Theme.PADDING - Theme.CLOSE_BUTTON_SIZE - 16, 0, Theme.HEADER_HEIGHT),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Build",
		Parent = panel,
	}) :: TextLabel

	local closeButton = Create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(Theme.CLOSE_BUTTON_SIZE, Theme.CLOSE_BUTTON_SIZE),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		Text = "X",
		Parent = panel,
	}) :: TextButton

	local scroll = Create("ScrollingFrame", {
		Name = "SlotList",
		Position = UDim2.fromOffset(Theme.PADDING, Theme.HEADER_HEIGHT),
		Size = UDim2.new(1, -Theme.PADDING * 2, 1, -Theme.HEADER_HEIGHT - Theme.PADDING),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.COLOR_TEXT_DIM,
		Parent = panel,
	}) :: ScrollingFrame
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ROW_SPACING),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	-- M2 prestige affordance (Advance Era / Rebirth). Pinned above the slot rows
	-- (LayoutOrder 0; rows start at 1) so a fresh open leads with it once the era is
	-- complete. UIController owns visibility and label; era rebuilds never touch it.
	local prestigeButton = Create("TextButton", {
		Name = "PrestigeBanner",
		LayoutOrder = 0,
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

	local emptyLabel = Create("TextLabel", {
		Name = "EmptyState",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -Theme.PADDING * 2, 0, 40),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextWrapped = true,
		Text = "Loading...",
		Visible = true,
		Parent = panel,
	}) :: TextLabel

	local function panelPosition(): UDim2
		-- UIScale multiplies size, not position offsets, so margins scale by hand.
		return UDim2.new(0.5, 0, 1, -Theme.PANEL_BOTTOM_MARGIN * currentScale)
	end

	local function projectedIncome(
		state: Types.PlayerState,
		eraConfig: Types.EraConfig,
		slotId: string,
		level: number
	): number
		local projected = table.clone(state.slots)
		projected[slotId] = { level = level }
		return Economy.IncomePerSecond(projected, eraConfig, deps.gameConfig, UNIT_MULTIPLIERS)
	end

	local function computeMode(row: Row, state: Types.PlayerState): ()
		local slot = row.slot
		local owned = state.slots[slot.id]
		if owned ~= nil then
			if slot.type == "building" then
				if owned.level >= deps.gameConfig.maxLevel then
					row.mode = "max"
					row.cost = 0
				else
					row.mode = "level"
					row.cost = Economy.LevelUpCost(slot.baseCost, owned.level + 1, deps.gameConfig)
				end
			else
				row.mode = "owned"
				row.cost = 0
			end
		else
			local requiresId = row.requiresId
			if requiresId ~= nil and state.slots[requiresId] == nil then
				row.mode = "locked"
				row.cost = 0
			else
				row.mode = "buy"
				row.cost = slot.baseCost
			end
		end
	end

	local function applyVisuals(
		row: Row,
		state: Types.PlayerState,
		eraConfig: Types.EraConfig,
		currentIncome: number,
		highlighted: boolean
	): ()
		local slot = row.slot
		local mode = row.mode
		local locked = mode == "locked"

		row.frame.BackgroundColor3 = if locked then Theme.COLOR_ROW_LOCKED else Theme.COLOR_ROW
		row.nameLabel.TextColor3 = if locked then Theme.COLOR_TEXT_DIM else Theme.COLOR_TEXT
		row.stroke.Color = Theme.COLOR_HIGHLIGHT
		row.stroke.Enabled = highlighted

		local statusText = ""
		local statusColor = Theme.COLOR_TEXT_DIM
		local previewText = ""
		local buttonVisible = true
		local buttonTitleText = ""
		local buttonCostText = ""
		local buttonActive = false
		local buttonColor = Theme.COLOR_BG_LIGHT
		local buttonTextColor = Theme.COLOR_TEXT_DIM

		if mode == "locked" then
			local requiresId = row.requiresId
			local requiresName = if requiresId ~= nil
				then namesById[requiresId] or requiresId
				else "?"
			statusText = "Requires " .. requiresName
			buttonTitleText = "Locked"
		elseif mode == "buy" then
			local affordable = state.cash >= row.cost
			statusText = "$" .. Format.Cash(row.cost)
			statusColor = if affordable then Theme.COLOR_TEXT else Theme.COLOR_TEXT_DIM
			local delta = projectedIncome(state, eraConfig, slot.id, 1) - currentIncome
			if delta > 0 then
				previewText = "+" .. Format.Cash(delta) .. "/s"
			end
			buttonTitleText = "Buy"
			buttonActive = true
			if affordable then
				buttonColor = Theme.COLOR_ACCENT
				buttonTextColor = Theme.COLOR_TEXT_DARK
			end
		elseif mode == "level" then
			local owned = state.slots[slot.id]
			local level = if owned ~= nil then owned.level else 1
			local affordable = state.cash >= row.cost
			statusText = "Lv " .. tostring(level)
			statusColor = Theme.COLOR_TEXT
			local delta = projectedIncome(state, eraConfig, slot.id, level + 1) - currentIncome
			if delta > 0 then
				previewText = "+" .. Format.Cash(delta) .. "/s"
			end
			buttonTitleText = "Level Up ×1"
			buttonCostText = "$" .. Format.Cash(row.cost)
			buttonActive = true
			if affordable then
				buttonColor = Theme.COLOR_ACCENT_ALT
				buttonTextColor = Theme.COLOR_TEXT_DARK
			end
		elseif mode == "max" then
			local owned = state.slots[slot.id]
			local level = if owned ~= nil then owned.level else deps.gameConfig.maxLevel
			statusText = "Lv " .. tostring(level)
			statusColor = Theme.COLOR_TEXT
			buttonTitleText = "MAX"
		else -- owned unlock/decor/monument: nothing further to do with this slot in M1
			statusText = "Owned"
			statusColor = Theme.COLOR_ACCENT
			buttonVisible = false
		end

		row.statusLabel.Text = statusText
		row.statusLabel.TextColor3 = statusColor
		row.previewLabel.Text = previewText
		row.button.Visible = buttonVisible
		row.buttonTitle.Text = buttonTitleText
		row.buttonCost.Text = buttonCostText
		row.button.Active = buttonActive
		row.button.AutoButtonColor = buttonActive
		row.button.BackgroundColor3 = buttonColor
		row.buttonTitle.TextColor3 = buttonTextColor
		row.buttonCost.TextColor3 = buttonTextColor
		-- Two-line button only when a cost is shown; a lone title centers vertically.
		if buttonCostText == "" then
			row.buttonTitle.Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, 0)
			row.buttonTitle.Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 1, 0)
		else
			row.buttonTitle.Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, Theme.BUTTON_TITLE_Y)
			row.buttonTitle.Size =
				UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.BUTTON_TITLE_HEIGHT)
		end

		-- Keep an active failure flash visible across refreshes until it expires.
		if os.clock() < row.flashUntil then
			row.statusLabel.TextColor3 = Theme.COLOR_ERROR
			row.buttonCost.TextColor3 = Theme.COLOR_ERROR
			row.stroke.Color = Theme.COLOR_ERROR
			row.stroke.Enabled = true
		end
	end

	local function refresh(state: Types.PlayerState): ()
		lastState = state
		local eraConfig = currentEra
		if eraConfig == nil then
			return
		end
		if not isOpen then
			-- Visuals rebuild on open; skipping keeps the 1 Hz cash ticks cheap while hidden.
			return
		end
		for _, row in rows do
			computeMode(row, state)
		end
		-- "Next affordable" = first slot in purchase order you can buy right now.
		local highlightId: string? = nil
		for _, row in rows do
			if row.mode == "buy" and state.cash >= row.cost then
				highlightId = row.slot.id
				break
			end
		end
		local currentIncome =
			Economy.IncomePerSecond(state.slots, eraConfig, deps.gameConfig, UNIT_MULTIPLIERS)
		for _, row in rows do
			applyVisuals(row, state, eraConfig, currentIncome, row.slot.id == highlightId)
		end
	end

	local function makeRow(slot: Types.SlotConfig, index: number, requiresId: string?): ()
		local frame = Create("Frame", {
			Name = slot.id,
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.ROW_HEIGHT),
			LayoutOrder = index,
			Parent = scroll,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
		local stroke = Create("UIStroke", {
			Color = Theme.COLOR_HIGHLIGHT,
			Thickness = Theme.STROKE_THICKNESS,
			Enabled = false,
			Parent = frame,
		}) :: UIStroke

		local textWidth = -Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP
		local nameLabel = Create("TextLabel", {
			Name = "SlotName",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.ROW_NAME_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_NAME_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = slot.name,
			Parent = frame,
		}) :: TextLabel
		local statusLabel = Create("TextLabel", {
			Name = "Status",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.ROW_STATUS_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		local previewLabel = Create("TextLabel", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.ROW_PREVIEW_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_ACCENT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel

		local button = Create("TextButton", {
			Name = "Action",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Theme.ROW_SPACING, 0.5, 0),
			Size = UDim2.fromOffset(Theme.ROW_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Text = "",
			Parent = frame,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		local buttonTitle = Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, 0),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 1, 0),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = button,
		}) :: TextLabel
		local buttonCost = Create("TextLabel", {
			Name = "Cost",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, Theme.BUTTON_COST_Y),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = button,
		}) :: TextLabel

		local row: Row = {
			slot = slot,
			requiresId = requiresId,
			frame = frame,
			nameLabel = nameLabel,
			statusLabel = statusLabel,
			previewLabel = previewLabel,
			button = button,
			buttonTitle = buttonTitle,
			buttonCost = buttonCost,
			stroke = stroke,
			mode = "locked",
			cost = 0,
			flashUntil = 0,
		}
		table.insert(rows, row)
		rowsById[slot.id] = row

		-- Connection dies with the button when the row is destroyed (era rebuild/Destroy).
		button.Activated:Connect(function()
			-- Small client-side debounce so double-taps don't burn the server rate limit.
			local now = os.clock()
			if now - lastActionTime < Theme.ACTION_DEBOUNCE_SECONDS then
				return
			end
			if row.mode == "buy" then
				lastActionTime = now
				deps.onBuy(slot.id)
			elseif row.mode == "level" then
				lastActionTime = now
				deps.onLevelUp(slot.id, 1)
			end
		end)
	end

	local function setEra(eraConfig: Types.EraConfig?): ()
		local existing = currentEra
		if eraConfig ~= nil and existing ~= nil and eraConfig.eraIndex == existing.eraIndex then
			-- Duplicate snapshot for the same era: keep rows so the rebuild is idempotent.
			currentEra = eraConfig
			return
		end
		currentEra = eraConfig
		for _, row in rows do
			row.frame:Destroy()
		end
		table.clear(rows)
		table.clear(rowsById)
		table.clear(namesById)
		if eraConfig == nil then
			-- Missing era config degrades to an empty panel, never an error (M1 contract).
			titleLabel.Text = "Build"
			emptyLabel.Text = "Era data unavailable"
			emptyLabel.Visible = true
			return
		end
		titleLabel.Text = "Build — " .. eraConfig.name
		emptyLabel.Visible = false
		for _, slot in eraConfig.slots do
			namesById[slot.id] = slot.name
		end
		for index, slot in eraConfig.slots do
			local requiresId = slot.requires
			if requiresId == nil and index > 1 then
				-- Frozen semantics: omitted `requires` means the previous slot in the array.
				requiresId = eraConfig.slots[index - 1].id
			end
			makeRow(slot, index, requiresId)
		end
	end

	local function setPrestige(label: string?): ()
		if label == nil then
			prestigeButton.Visible = false
		else
			prestigeButton.Text = label
			prestigeButton.Visible = true
		end
	end

	local function flashSlot(slotId: string): ()
		local row = rowsById[slotId]
		if row == nil then
			return
		end
		row.flashUntil = os.clock() + Theme.FLASH_SECONDS
		row.statusLabel.TextColor3 = Theme.COLOR_ERROR
		row.buttonCost.TextColor3 = Theme.COLOR_ERROR
		row.stroke.Color = Theme.COLOR_ERROR
		row.stroke.Enabled = true
		task.delay(Theme.FLASH_SECONDS, function()
			local state = lastState
			if state ~= nil then
				refresh(state) -- restores true colors once the flash window passed
			end
		end)
	end

	local function setOpen(open: boolean): ()
		if open == isOpen then
			return
		end
		isOpen = open
		buildButton.Text = if open then "Close" else "Build"
		local tween = openTween
		if tween ~= nil then
			tween:Cancel()
			openTween = nil
		end
		if open then
			local state = lastState
			if state ~= nil then
				refresh(state)
			end
			panel.Visible = true
			if Theme.reducedMotion then
				panel.Position = panelPosition()
			else
				panel.Position = panelPosition() + UDim2.fromOffset(0, Theme.PANEL_SLIDE_OFFSET)
				local newTween = TweenService:Create(
					panel,
					TweenInfo.new(
						Theme.OPEN_TWEEN_SECONDS,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out
					),
					{ Position = panelPosition() }
				)
				openTween = newTween
				newTween:Play()
			end
		else
			panel.Visible = false
			panel.Position = panelPosition()
		end
	end

	local function setLayout(scale: number, viewportSize: Vector2): ()
		currentScale = scale
		panelScale.Scale = scale
		buttonScale.Scale = scale
		buildButton.Position = UDim2.new(0.5, 0, 1, -Theme.PADDING * scale)
		-- Landscape fix (M1 review): when the viewport is short, derive the panel height
		-- from what actually fits between the top bar and the Build button instead of
		-- scaling the portrait canvas down (which shrank tap targets and overflowed).
		-- The budget is physical px; divide by scale because UIScale multiplies size.
		local topZone = (Theme.SCREEN_MARGIN * 2 + Theme.TOP_BAR_HEIGHT) * scale
		local bottomZone = Theme.PANEL_BOTTOM_MARGIN * scale
		local budget = (viewportSize.Y - topZone - bottomZone) / scale
		local panelHeight = math.clamp(budget, Theme.PANEL_MIN_HEIGHT, Theme.PANEL_HEIGHT)
		panel.Size = UDim2.fromOffset(Theme.PANEL_WIDTH, panelHeight)
		panel.Position = panelPosition()
	end

	local function destroy(): ()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		local tween = openTween
		if tween ~= nil then
			tween:Cancel()
			openTween = nil
		end
		panel:Destroy() -- row button connections die with their instances here
		buildButton:Destroy()
	end

	table.insert(
		connections,
		buildButton.Activated:Connect(function()
			setOpen(not isOpen)
		end)
	)
	table.insert(
		connections,
		closeButton.Activated:Connect(function()
			setOpen(false)
		end)
	)
	table.insert(
		connections,
		prestigeButton.Activated:Connect(function()
			-- No debounce: this only opens the local confirm dialog, no remote fires here.
			deps.onPrestige()
		end)
	)

	local handle: BuildPanelHandle = {
		SetEra = setEra,
		Refresh = refresh,
		FlashSlot = flashSlot,
		SetPrestige = setPrestige,
		SetOpen = setOpen,
		SetLayout = setLayout,
		Destroy = destroy,
	}
	return handle
end

return BuildPanel
