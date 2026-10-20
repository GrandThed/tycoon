--!strict
-- The Armory screen's shelf (docs/prompts/l3-w1-contract.md, L3-19): one card per weapon family,
-- in ArmoryModel.Shelf's order (by window start, melee before ranged, then name), so the shelf
-- reads as the path of levels. In landscape one scrolling row; in portrait a grid of
-- ARMORY_SCREEN_PORTRAIT_COLUMNS (5 x 3 for the 15 families), scrolling past three rows.
--
-- A card is a button: its name, its tier ("T3") or "Not found" for one not owned, a dot in its
-- element's colour, a gold bar under the held pair, a gold ring on the selected one. An unowned
-- card is dark. Tapping a card selects it; so does a gamepad's selection landing on it, so the
-- stage follows the d-pad. Every card is at least 48 design px tall (44 physical at MIN_SCALE).
-- Presses go through the screen's router (deps.bind), which also serves gamepad A.

local ArmoryModel = require(script.Parent:WaitForChild("ArmoryModel"))
local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Deps = {
	onSelect: (family: string) -> (),
	-- The screen's press router: Activated, gamepad A and the debounce in one place. Returns the
	-- function that unbinds the button.
	bind: (button: GuiButton, handler: () -> ()) -> () -> (),
}

export type Shelf = {
	frame: ScrollingFrame,
	Show: (cards: { ArmoryModel.Card }, selected: string?) -> (),
	-- portrait = the grid; width = the shelf's width in design px.
	SetLayout: (portrait: boolean, width: number) -> (),
	-- The shelf's height in design px for the layout last set.
	Height: () -> number,
	ButtonOf: (family: string) -> GuiButton?,
	Destroy: () -> (),
}

type CardFrame = {
	family: string,
	button: TextButton,
	name: TextLabel,
	tier: TextLabel,
	dot: Frame,
	bar: Frame,
	stroke: UIStroke,
	unbind: () -> (),
	selectionConnection: RBXScriptConnection,
}

local NOT_FOUND = "Not found"

local ArmoryShelf = {}

local function label(name: string, size: number, parent: Instance): TextLabel
	return Create("TextLabel", {
		Name = name,
		Active = false,
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = size,
		TextColor3 = Theme.MAP_COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: TextLabel
end

function ArmoryShelf.new(parent: Instance, deps: Deps): Shelf
	local cards: { CardFrame } = {}
	local view = { portrait = false, width = 0, count = 0, signature = "" }

	local frame = Create("ScrollingFrame", {
		Name = "Shelf",
		Active = true,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		ScrollBarImageColor3 = Theme.MAP_COLOR_DIM,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: ScrollingFrame
	local grid = Create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(Theme.ARMORY_SCREEN_CARD_GAP, Theme.ARMORY_SCREEN_CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	}) :: UIGridLayout

	local function drop(): ()
		for _, card in cards do
			card.unbind()
			card.selectionConnection:Disconnect()
			card.button:Destroy()
		end
		table.clear(cards)
	end

	local function build(list: { ArmoryModel.Card }): ()
		drop()
		local pad = Theme.ARMORY_SCREEN_CARD_PAD
		for index, model in list do
			local family = model.family
			local button = Create("TextButton", {
				Name = "Card_" .. family,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
				BorderSizePixel = 0,
				ZIndex = Theme.ZINDEX_CARD,
				Parent = frame,
			}) :: TextButton
			Create(
				"UICorner",
				{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button }
			)
			local stroke = Create("UIStroke", {
				Color = Theme.MAP_COLOR_GOLD,
				Thickness = Theme.STROKE_THICKNESS,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Enabled = false,
				Parent = button,
			}) :: UIStroke
			local name = label("Name", Theme.ARMORY_SCREEN_CARD_NAME_TEXT, button)
			name.Position = UDim2.fromOffset(pad, pad)
			-- The whole width: a portrait card is 68 wide, and "Flamethrower" scales down to fit
			-- (never below CARD_NAME_MIN_TEXT, the bottom bar's floor) rather than truncate.
			name.Size = UDim2.new(1, -pad * 2, 0, Theme.ARMORY_SCREEN_CARD_NAME_HEIGHT)
			name.TextWrapped = true
			name.TextScaled = true
			Create("UITextSizeConstraint", {
				MaxTextSize = Theme.ARMORY_SCREEN_CARD_NAME_TEXT,
				MinTextSize = Theme.ARMORY_SCREEN_CARD_NAME_MIN_TEXT,
				Parent = name,
			})
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextYAlignment = Enum.TextYAlignment.Top
			local tier = label("Tier", Theme.ARMORY_SCREEN_CARD_TIER_TEXT, button)
			tier.AnchorPoint = Vector2.new(0, 1)
			tier.Position = UDim2.new(0, pad, 1, -pad)
			tier.Size = UDim2.new(1, -pad * 2, 0, Theme.ARMORY_SCREEN_CARD_TIER_TEXT + 2)
			local dot = Create("Frame", {
				Name = "Element",
				Active = false,
				-- Beside the tier, so the name keeps the card's width.
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(
					1,
					-pad,
					1,
					-pad - (Theme.ARMORY_SCREEN_CARD_TIER_TEXT + 2) / 2
				),
				Size = UDim2.fromOffset(Theme.ARMORY_SCREEN_CARD_DOT, Theme.ARMORY_SCREEN_CARD_DOT),
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = Theme.ZINDEX_CARD,
				Parent = button,
			}) :: Frame
			Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
			local bar = Create("Frame", {
				Name = "Held",
				Active = false,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.new(
					1,
					-Theme.ROW_CORNER_RADIUS * 2,
					0,
					Theme.ARMORY_SCREEN_CARD_HELD_BAR
				),
				BackgroundColor3 = Theme.MAP_COLOR_GOLD,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = Theme.ZINDEX_CARD,
				Parent = button,
			}) :: Frame
			table.insert(cards, {
				family = family,
				button = button,
				name = name,
				tier = tier,
				dot = dot,
				bar = bar,
				stroke = stroke,
				unbind = deps.bind(button, function()
					deps.onSelect(family)
				end),
				-- The d-pad browses: the stage follows the selection.
				selectionConnection = button.SelectionGained:Connect(function()
					deps.onSelect(family)
				end),
			})
		end
	end

	local function paint(list: { ArmoryModel.Card }, selected: string?): ()
		for index, model in list do
			local card = cards[index]
			local owned = model.owned
			card.button.BackgroundColor3 = if owned
				then Theme.MAP_COLOR_PANEL_LIGHT
				else Theme.ARMORY_SCREEN_CARD_DARK
			card.stroke.Enabled = model.family == selected
			card.name.Text = model.name
			card.name.TextColor3 = if owned then Theme.MAP_COLOR_TEXT else Theme.MAP_COLOR_DIM
			card.tier.Text = if owned then model.tierText else NOT_FOUND
			card.tier.TextSize = if owned
				then Theme.ARMORY_SCREEN_CARD_TIER_TEXT
				else Theme.ARMORY_SCREEN_CARD_NAME_TEXT
			card.tier.TextColor3 = if model.held
				then Theme.MAP_COLOR_GOLD
				elseif owned then Theme.MAP_COLOR_TEXT
				else Theme.MAP_COLOR_OFF
			card.bar.Visible = model.held
			local element = model.element
			local color = if element ~= nil
				then Theme.ARMORY_SCREEN_ELEMENT_COLORS[element]
				else nil
			card.dot.Visible = color ~= nil
			if color ~= nil then
				card.dot.BackgroundColor3 = color
				card.dot.BackgroundTransparency = if owned then 0 else Theme.ARMORY_SCREEN_DARK_CHIP
			end
		end
	end

	local function rows(): number
		local columns = Theme.ARMORY_SCREEN_PORTRAIT_COLUMNS
		return math.max(1, math.ceil(view.count / columns))
	end

	local function layout(): ()
		local gap = Theme.ARMORY_SCREEN_CARD_GAP
		if view.portrait then
			local columns = Theme.ARMORY_SCREEN_PORTRAIT_COLUMNS
			local inner = view.width - Theme.SCROLLBAR_THICKNESS - gap
			local cell = math.floor((inner - gap * (columns - 1)) / columns)
			grid.FillDirection = Enum.FillDirection.Horizontal
			grid.FillDirectionMaxCells = columns
			grid.CellSize = UDim2.fromOffset(cell, Theme.ARMORY_SCREEN_CARD_HEIGHT)
			frame.ScrollingDirection = Enum.ScrollingDirection.Y
			frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		else
			-- One row: a vertical fill of one cell per column runs left to right.
			grid.FillDirection = Enum.FillDirection.Vertical
			grid.FillDirectionMaxCells = 1
			grid.CellSize =
				UDim2.fromOffset(Theme.ARMORY_SCREEN_CARD_WIDTH, Theme.ARMORY_SCREEN_CARD_HEIGHT)
			frame.ScrollingDirection = Enum.ScrollingDirection.X
			frame.AutomaticCanvasSize = Enum.AutomaticSize.X
		end
		frame.CanvasSize = UDim2.new()
	end

	local shelf: Shelf = {
		frame = frame,
		Show = function(list: { ArmoryModel.Card }, selected: string?)
			local parts: { string } = {}
			for _, model in list do
				table.insert(parts, model.family)
			end
			local signature = table.concat(parts, ",")
			if signature ~= view.signature then
				view.signature = signature
				view.count = #list
				build(list)
			end
			paint(list, selected)
		end,
		SetLayout = function(portrait: boolean, width: number)
			view.portrait = portrait
			view.width = width
			layout()
		end,
		Height = function(): number
			if not view.portrait then
				return Theme.ARMORY_SCREEN_SHELF_HEIGHT
			end
			local shown = math.min(rows(), Theme.ARMORY_SCREEN_PORTRAIT_ROWS)
			return shown * Theme.ARMORY_SCREEN_CARD_HEIGHT
				+ (shown - 1) * Theme.ARMORY_SCREEN_CARD_GAP
		end,
		ButtonOf = function(family: string): GuiButton?
			for _, card in cards do
				if card.family == family then
					return card.button
				end
			end
			return nil
		end,
		Destroy = function()
			drop()
			frame:Destroy()
		end,
	}
	return shelf
end

return ArmoryShelf
