--!strict
-- Build panel content: one row per slot of the current era, live state from server
-- pushes. Costs and income deltas shown here are previews computed with the shared pure
-- Economy module; the server stays authoritative and the next snapshot/delta overwrites
-- anything predicted (docs/INTERFACES.md, M1–M3 client contracts). M3 adds the
-- ×1 / ×10 / Max strip on levelable rows and the "cheapest affordable action" highlight.

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

-- Legacy/neighbors multipliers activate at M2, pass/premium at M4, perk at M6; previews
-- pass all 1s per INTERFACES.md — deltas are relative, so the shared factors cancel out.
local UNIT_MULTIPLIERS: Types.Multipliers =
	{ legacy = 1, perk = 1, pass = 1, premium = 1, neighbors = 1 }

export type Deps = {
	gameConfig: Types.GameConfig,
	shopConfig: Types.LegacyShopConfig,
	onBuy: (slotId: string) -> (),
	onLevelUp: (slotId: string, count: number) -> (),
	onPrestige: () -> (),
	onClose: () -> (),
}

export type BuildPanelHandle = {
	DesignHeight: number,
	SetEra: (eraConfig: Types.EraConfig?) -> (),
	Refresh: (state: Types.PlayerState) -> (),
	FlashSlot: (slotId: string) -> (),
	SetPrestige: (label: string?) -> (),
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

type RowMode = "locked" | "buy" | "level" | "max" | "owned"

type LevelOption = "one" | "ten" | "max"

type LevelButton = {
	option: LevelOption,
	button: TextButton,
	title: TextLabel,
	cost: TextLabel,
	delta: TextLabel,
}

type Row = {
	slot: Types.SlotConfig,
	requiresId: string?,
	frame: Frame,
	textWidth: number, -- negative offset that keeps a text line clear of the action button
	nameLabel: TextLabel,
	statusLabel: TextLabel,
	previewLabel: TextLabel,
	button: TextButton,
	buttonTitle: TextLabel,
	buttonCost: TextLabel,
	levelStrip: Frame,
	levelButtons: { LevelButton },
	stroke: UIStroke,
	mode: RowMode,
	cost: number, -- buy price, or the ×1 level-up price: the "next affordable" candidate
	flashUntil: number,
}

-- Requested counts per strip button. "Max" asks for maxLevel; the server grants what is
-- affordable (docs/INTERFACES.md RequestLevelUp).
local LEVEL_OPTIONS: { { option: LevelOption, label: string } } = {
	{ option = "one", label = "×1" },
	{ option = "ten", label = "×10" },
	{ option = "max", label = "Max" },
}
local TEN_LEVELS = 10

local BuildPanel = {}

function BuildPanel.new(parent: Instance, deps: Deps): BuildPanelHandle
	local currentEra: Types.EraConfig? = nil
	local rows: { Row } = {}
	local rowsById: { [string]: Row } = {}
	local namesById: { [string]: string } = {}
	local lastState: Types.PlayerState? = nil
	local lastActionTime = 0
	local connections: { RBXScriptConnection } = {}
	local gameConfig = deps.gameConfig
	local shopConfig = deps.shopConfig
	-- M6 per-player economy inputs, recomputed from the pushed legacyShop state on every
	-- refresh. The discount is applied inside Economy.LevelUpCost only (never here), so
	-- this preview and the server's charge cannot disagree. previewGame is gameConfig
	-- with milestoneLevels swapped for the player's own list (Extra Milestone), so every
	-- income delta below goes through the same SlotIncome the server uses; the rows never
	-- read Game.milestoneLevels directly.
	local levelDiscount = 0
	local levelFloor = 1
	local milestoneLevels: { number } = gameConfig.milestoneLevels
	local previewGame: Types.GameConfig = gameConfig

	local panel = Panel.new(parent, {
		name = "BuildPanel",
		title = "Build",
		designHeight = Theme.PANEL_HEIGHT,
		onClose = deps.onClose,
	})

	local scroll = Create("ScrollingFrame", {
		Name = "SlotList",
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

	-- Twin of the pinned banner, parked after the last slot row (LayoutOrder far above any
	-- row index). A player who completes the era while scrolled to the bottom of a 24-row
	-- list would otherwise have to scroll back up to find the affordance.
	local prestigeButtonBottom = Create("TextButton", {
		Name = "PrestigeBannerBottom",
		LayoutOrder = 10000,
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
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = prestigeButtonBottom }
	)

	local emptyLabel = Create("TextLabel", {
		Name = "EmptyState",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -Theme.PADDING * 2, 0, Theme.EMPTY_LABEL_HEIGHT),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextWrapped = true,
		Text = "Loading...",
		Visible = true,
		Parent = panel.Root,
	}) :: TextLabel

	local function projectedIncome(
		state: Types.PlayerState,
		eraConfig: Types.EraConfig,
		slotId: string,
		level: number
	): number
		local projected = table.clone(state.slots)
		projected[slotId] = { level = level }
		return Economy.IncomePerSecond(projected, eraConfig, previewGame, UNIT_MULTIPLIERS)
	end

	-- The first milestone above `level`, for the level row's status line.
	local function nextMilestone(level: number): number?
		for _, milestoneLevel in milestoneLevels do
			if milestoneLevel > level then
				return milestoneLevel
			end
		end
		return nil
	end

	-- M7: the level at which the building's next visual stage appears. Stages follow the
	-- BASE milestone list only (docs/INTERFACES.md M7 "Stage rule"): the Extra Milestone
	-- perk doubles income at its level but never grows the model, so this deliberately
	-- reads gameConfig rather than the per-player list above. nil at the last stage.
	local function nextGrowthLevel(level: number): number?
		for _, milestoneLevel in gameConfig.milestoneLevels do
			if milestoneLevel > level then
				return milestoneLevel
			end
		end
		return nil
	end

	local function deltaText(delta: number): string
		return if delta > 0 then "+" .. Format.Rate(delta) .. "/s" else ""
	end

	local function computeMode(row: Row, state: Types.PlayerState): ()
		local slot = row.slot
		local owned = state.slots[slot.id]
		if owned ~= nil then
			if slot.type == "building" then
				if owned.level >= gameConfig.maxLevel then
					row.mode = "max"
					row.cost = 0
				else
					row.mode = "level"
					row.cost = Economy.LevelUpCost(
						slot.baseCost,
						owned.level + 1,
						gameConfig,
						levelDiscount
					)
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

	-- Target level for each strip button. Max is a greedy display prediction over
	-- LevelUpCost: the largest n whose total the player can pay right now. When nothing is
	-- affordable it shows the ×1 price so the button still reads as a price tag.
	local function levelTarget(
		option: LevelOption,
		baseCost: number,
		level: number,
		cash: number
	): (number, number)
		local maxLevel = gameConfig.maxLevel
		if option == "one" then
			return level + 1, Economy.LevelUpCost(baseCost, level + 1, gameConfig, levelDiscount)
		elseif option == "ten" then
			local target = math.min(level + TEN_LEVELS, maxLevel)
			return target,
				Economy.LevelUpCostTotal(baseCost, level, target, gameConfig, levelDiscount)
		end
		local target = level
		local total = 0
		while target < maxLevel do
			local nextCost = Economy.LevelUpCost(baseCost, target + 1, gameConfig, levelDiscount)
			if total + nextCost > cash then
				break
			end
			total += nextCost
			target += 1
		end
		if target == level then
			return level + 1, Economy.LevelUpCost(baseCost, level + 1, gameConfig, levelDiscount)
		end
		return target, total
	end

	local function paintLevelStrip(
		row: Row,
		state: Types.PlayerState,
		eraConfig: Types.EraConfig,
		level: number,
		currentIncome: number
	): ()
		for index, levelButton in row.levelButtons do
			local target, cost =
				levelTarget(levelButton.option, row.slot.baseCost, level, state.cash)
			local affordable = state.cash >= cost
			local label = LEVEL_OPTIONS[index].label
			if levelButton.option == "max" and affordable then
				label = label .. " ×" .. tostring(target - level)
			end
			levelButton.title.Text = label
			levelButton.cost.Text = "$" .. Format.Cash(cost)
			levelButton.delta.Text =
				deltaText(projectedIncome(state, eraConfig, row.slot.id, target) - currentIncome)
			-- Dimmed but tappable when unaffordable: the server answers insufficientFunds.
			levelButton.button.BackgroundTransparency = if affordable
				then 0
				else Theme.DIM_TRANSPARENCY
			levelButton.button.BackgroundColor3 = if affordable
				then Theme.COLOR_ACCENT_ALT
				else Theme.COLOR_BG_LIGHT
			local textColor = if affordable then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT_DIM
			levelButton.title.TextColor3 = textColor
			levelButton.cost.TextColor3 = textColor
			levelButton.delta.TextColor3 = if affordable
				then Theme.COLOR_TEXT_DARK
				else Theme.COLOR_ACCENT
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
		local isLevel = mode == "level"

		row.frame.BackgroundColor3 = if locked then Theme.COLOR_ROW_LOCKED else Theme.COLOR_ROW
		row.frame.Size = UDim2.new(
			1,
			-Theme.ROW_SPACING,
			0,
			if isLevel then Theme.LEVEL_ROW_HEIGHT else Theme.ROW_HEIGHT
		)
		row.nameLabel.TextColor3 = if locked then Theme.COLOR_TEXT_DIM else Theme.COLOR_TEXT
		row.stroke.Color = Theme.COLOR_HIGHLIGHT
		row.stroke.Enabled = highlighted
		row.levelStrip.Visible = isLevel
		-- The level row hides the action button, so its status line ("Lv 12 · ×2 at Lv 25 ·
		-- Grows at Lv 25") may run the full row width instead of stopping at the button.
		row.statusLabel.Size = UDim2.new(
			1,
			if isLevel then -Theme.ROW_TEXT_LEFT - Theme.ROW_SPACING else row.textWidth,
			0,
			Theme.ROW_LINE_HEIGHT
		)

		local statusText = ""
		local statusColor = Theme.COLOR_TEXT_DIM
		local previewText = ""
		local buttonVisible = not isLevel
		local buttonTitleText = ""
		local buttonCostText = ""
		local buttonActive = false
		local buttonColor = Theme.COLOR_BG_LIGHT
		local buttonTextColor = Theme.COLOR_TEXT_DIM
		local buttonTransparency = 0

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
			-- Level Floor: a new building opens at the floor level, and the preview says so.
			-- Unlock/decor/monument slots have no level to speak of (SlotIncome ignores them).
			local startLevel = if slot.type == "building" then levelFloor else 1
			previewText =
				deltaText(projectedIncome(state, eraConfig, slot.id, startLevel) - currentIncome)
			if startLevel > 1 then
				previewText ..= " (opens at Lv " .. tostring(startLevel) .. ")"
			end
			buttonTitleText = "Buy"
			buttonActive = true
			if affordable then
				buttonColor = Theme.COLOR_ACCENT
				buttonTextColor = Theme.COLOR_TEXT_DARK
			else
				buttonTransparency = Theme.DIM_TRANSPARENCY
			end
		elseif mode == "level" then
			local owned = state.slots[slot.id]
			local level = if owned ~= nil then owned.level else 1
			statusText = "Lv " .. tostring(level)
			local milestone = nextMilestone(level)
			if milestone ~= nil then
				statusText ..= " · ×" .. Format.Rate(gameConfig.milestoneMultiplier) .. " at Lv " .. tostring(
					milestone
				)
			end
			local growthLevel = nextGrowthLevel(level)
			if growthLevel ~= nil then
				statusText ..= " · " .. string.format(Theme.GROW_HINT_FORMAT, growthLevel)
			end
			statusColor = Theme.COLOR_TEXT
			paintLevelStrip(row, state, eraConfig, level, currentIncome)
		elseif mode == "max" then
			local owned = state.slots[slot.id]
			local level = if owned ~= nil then owned.level else gameConfig.maxLevel
			statusText = "Lv " .. tostring(level)
			statusColor = Theme.COLOR_TEXT
			buttonTitleText = "MAX"
		else -- owned unlock/decor/monument: nothing further to do with this slot
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
		row.button.BackgroundTransparency = buttonTransparency
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
		if not panel.IsOpen() then
			-- Visuals rebuild on open; skipping keeps the 1 Hz cash ticks cheap while hidden.
			return
		end
		local shopState = state.legacyShop
		levelDiscount = Economy.LevelCostDiscount(shopConfig, shopState)
		levelFloor = Economy.LevelFloor(shopConfig, shopState)
		milestoneLevels = Economy.MilestoneLevels(shopConfig, shopState, gameConfig)
		previewGame = table.clone(gameConfig)
		previewGame.milestoneLevels = milestoneLevels
		for _, row in rows do
			computeMode(row, state)
		end
		-- "Next affordable" = the cheapest affordable buy or ×1 level-up; ties go to
		-- purchase order (strict < keeps the first row).
		local highlightId: string? = nil
		local highlightCost = math.huge
		for _, row in rows do
			local candidate = row.mode == "buy" or row.mode == "level"
			if candidate and state.cash >= row.cost and row.cost < highlightCost then
				highlightId = row.slot.id
				highlightCost = row.cost
			end
		end
		local currentIncome =
			Economy.IncomePerSecond(state.slots, eraConfig, previewGame, UNIT_MULTIPLIERS)
		for _, row in rows do
			applyVisuals(row, state, eraConfig, currentIncome, row.slot.id == highlightId)
		end
	end

	-- Small client-side debounce so double-taps don't burn the server rate limit.
	local function tryAction(action: () -> ()): ()
		local now = os.clock()
		if now - lastActionTime < Theme.ACTION_DEBOUNCE_SECONDS then
			return
		end
		lastActionTime = now
		SoundController.Play("uiClick")
		action()
	end

	local function makeLevelButton(strip: Frame, index: number, option: LevelOption): LevelButton
		local button = Create("TextButton", {
			Name = option,
			LayoutOrder = index,
			Size = UDim2.new(
				1 / #LEVEL_OPTIONS,
				-Theme.LEVEL_BUTTON_GAP * (#LEVEL_OPTIONS - 1) / #LEVEL_OPTIONS,
				1,
				0
			),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Text = "",
			Parent = strip,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		local function line(name: string, y: number, bold: boolean): TextLabel
			return Create("TextLabel", {
				Name = name,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, y),
				Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.ROW_LINE_HEIGHT),
				Font = if bold then Theme.FONT_BOLD else Theme.FONT,
				TextSize = Theme.TEXT_SMALL,
				TextColor3 = Theme.COLOR_TEXT_DIM,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = "",
				Parent = button,
			}) :: TextLabel
		end
		return {
			option = option,
			button = button,
			title = line("Title", Theme.LEVEL_BUTTON_TITLE_Y, true),
			cost = line("Cost", Theme.LEVEL_BUTTON_COST_Y, false),
			delta = line("Delta", Theme.LEVEL_BUTTON_DELTA_Y, false),
		}
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
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(
				1,
				-Theme.ROW_SPACING,
				0,
				(Theme.ROW_HEIGHT - Theme.ROW_BUTTON_HEIGHT) / 2
			),
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

		local levelStrip = Create("Frame", {
			Name = "LevelStrip",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.LEVEL_BUTTONS_Y),
			Size = UDim2.new(
				1,
				-Theme.ROW_TEXT_LEFT - Theme.ROW_SPACING,
				0,
				Theme.LEVEL_BUTTON_HEIGHT
			),
			Visible = false,
			Parent = frame,
		}) :: Frame
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, Theme.LEVEL_BUTTON_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = levelStrip,
		})
		local levelButtons: { LevelButton } = {}
		for optionIndex, entry in LEVEL_OPTIONS do
			table.insert(levelButtons, makeLevelButton(levelStrip, optionIndex, entry.option))
		end

		local row: Row = {
			slot = slot,
			requiresId = requiresId,
			frame = frame,
			textWidth = textWidth,
			nameLabel = nameLabel,
			statusLabel = statusLabel,
			previewLabel = previewLabel,
			button = button,
			buttonTitle = buttonTitle,
			buttonCost = buttonCost,
			levelStrip = levelStrip,
			levelButtons = levelButtons,
			stroke = stroke,
			mode = "locked",
			cost = 0,
			flashUntil = 0,
		}
		table.insert(rows, row)
		rowsById[slot.id] = row

		-- Connections die with their buttons when the row is destroyed (era rebuild/Destroy).
		button.Activated:Connect(function()
			if row.mode == "buy" then
				tryAction(function()
					deps.onBuy(slot.id)
				end)
			end
		end)
		for _, levelButton in levelButtons do
			levelButton.button.Activated:Connect(function()
				if row.mode ~= "level" then
					return
				end
				local count = if levelButton.option == "one"
					then 1
					elseif levelButton.option == "ten" then TEN_LEVELS
					else gameConfig.maxLevel
				tryAction(function()
					deps.onLevelUp(slot.id, count)
				end)
			end)
		end
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
			panel.SetTitle("Build")
			emptyLabel.Text = "Era data unavailable"
			emptyLabel.Visible = true
			return
		end
		panel.SetTitle("Build — " .. eraConfig.displayName)
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
			prestigeButtonBottom.Visible = false
		else
			prestigeButton.Text = label
			prestigeButton.Visible = true
			prestigeButtonBottom.Text = label
			prestigeButtonBottom.Visible = true
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
		if open == panel.IsOpen() then
			return
		end
		panel.SetOpen(open)
		local state = lastState
		if open and state ~= nil then
			refresh(state)
		end
	end

	local function onPrestigeTapped(): ()
		-- No debounce: this only opens the local era-advance screen, no remote fires.
		SoundController.Play("uiClick")
		deps.onPrestige()
	end
	table.insert(connections, prestigeButton.Activated:Connect(onPrestigeTapped))
	table.insert(connections, prestigeButtonBottom.Activated:Connect(onPrestigeTapped))

	local handle: BuildPanelHandle = {
		DesignHeight = panel.DesignHeight,
		SetEra = setEra,
		Refresh = refresh,
		FlashSlot = flashSlot,
		SetPrestige = setPrestige,
		SetOpen = setOpen,
		IsOpen = panel.IsOpen,
		SetLayout = panel.SetLayout,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			panel.Destroy() -- row button connections die with their instances here
		end,
	}
	return handle
end

return BuildPanel
