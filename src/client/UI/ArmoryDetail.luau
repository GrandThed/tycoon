--!strict
-- The Armory screen's detail column (docs/prompts/l3-w1-contract.md, L3-19 to L3-21): beside the
-- stage, the selected family's name, slot and tier; the track; the next line ("T5: 303 → 500
-- dmg · HP +120 → +170"); the cost line ("500 Timber · Forest Road · needs ★ Hard"); its ability;
-- its style buttons; Equip and Upgrade. Every text and every button state is ArmoryModel.Detail's:
-- this only draws it and routes a press back with the family (the screen holds what is pending).
--
-- Top-down: title, track and the three lines; the button row sits on the column's foot so it
-- lines up with the stage's. At its smallest (682 x 313 design px, a 640 x 360 phone) the column
-- is 173 tall and its content 163. Every button is 48 design px tall (44 physical at MIN_SCALE),
-- a text that does not fit wraps to two lines inside it. An unowned family has no buttons and its
-- "Not found yet" line may take the cost line's room.

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local ArmoryModel = require(script.Parent:WaitForChild("ArmoryModel"))
local ArmoryTrack = require(script.Parent:WaitForChild("ArmoryTrack"))

export type Deps = {
	onUpgrade: (family: string) -> (),
	onEquip: (family: string, variant: string) -> (),
	bind: (button: GuiButton, handler: () -> ()) -> () -> (),
}

export type DetailView = {
	frame: Frame,
	Show: (detail: ArmoryModel.Detail?) -> (),
	SetSize: (width: number, height: number) -> (),
	-- The first live button (a gamepad's selection may start there); nil = none.
	FirstSelection: () -> GuiObject?,
	Destroy: () -> (),
}

type Button = { button: TextButton, stroke: UIStroke, unbind: () -> () }

local ArmoryDetail = {}

-- The content's height in design px: title, track, three lines, the gaps and the button row.
function ArmoryDetail.Height(): number
	local line = Theme.ARMORY_SCREEN_LINE_HEIGHT + Theme.ARMORY_SCREEN_LINE_GAP
	return Theme.ARMORY_SCREEN_TITLE_HEIGHT
		+ Theme.ARMORY_SCREEN_LINE_GAP
		+ ArmoryTrack.Height()
		+ Theme.ARMORY_SCREEN_LINE_GAP
		+ line * 3
		+ Theme.ARMORY_SCREEN_BUTTON_HEIGHT
end

local function label(name: string, size: number, color: Color3, parent: Instance): TextLabel
	return Create("TextLabel", {
		Name = name,
		Active = false,
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: TextLabel
end

-- A look's colours: Upgrade is the one gold action; the others' live state is the panel's.
local function paintButton(
	entry: Button,
	state: ArmoryModel.ButtonState | ArmoryModel.StyleButton,
	primary: boolean
): ()
	local button = entry.button
	local look = state.look
	button.Visible = state.visible
	button.Text = state.text
	button.Active = state.live
	-- 4-s2: a press waiting for its answer keeps a pad's selection, so T2 then T3 is A, A (the
	-- handlers act only while their button is live).
	button.Selectable = state.live or look == "pending"
	entry.stroke.Enabled = look == "held"
	if look == "action" then
		button.BackgroundColor3 = if primary
			then Theme.MAP_COLOR_GOLD
			else Theme.MAP_COLOR_PANEL_SELECTED
		button.TextColor3 = if primary then Theme.MAP_COLOR_INK else Theme.MAP_COLOR_TEXT
		if not state.live then
			button.BackgroundColor3 = Theme.MAP_COLOR_PANEL_LIGHT
			button.TextColor3 = Theme.MAP_COLOR_DIM
		end
	elseif look == "held" or look == "pending" then
		button.BackgroundColor3 = Theme.MAP_COLOR_PANEL_SELECTED
		button.TextColor3 = Theme.MAP_COLOR_GOLD
	else
		button.BackgroundColor3 = Theme.MAP_COLOR_PANEL_LIGHT
		button.TextColor3 = Theme.MAP_COLOR_DIM
	end
end

function ArmoryDetail.new(parent: Instance, deps: Deps): DetailView
	local view = {
		width = 0,
		height = 0,
		shown = nil :: ArmoryModel.Detail?,
	}
	local frame = Create("Frame", {
		Name = "Detail",
		Active = false,
		BackgroundTransparency = 1,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame

	local titleRow = Create("Frame", {
		Name = "Title",
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -Theme.ARMORY_SCREEN_TIER_WIDTH, 0, Theme.ARMORY_SCREEN_TITLE_HEIGHT),
		ZIndex = Theme.ZINDEX_CARD,
		Parent = frame,
	}) :: Frame
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, Theme.ARMORY_SCREEN_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = titleRow,
	})
	local name = label("Name", Theme.ARMORY_SCREEN_TITLE_TEXT, Theme.MAP_COLOR_TEXT, titleRow)
	name.LayoutOrder = 1
	name.Size = UDim2.fromOffset(0, Theme.ARMORY_SCREEN_TITLE_HEIGHT)
	name.AutomaticSize = Enum.AutomaticSize.X
	local slot = label("Slot", Theme.ARMORY_SCREEN_LINE_TEXT, Theme.MAP_COLOR_DIM, titleRow)
	slot.LayoutOrder = 2
	slot.Size = UDim2.fromOffset(0, Theme.ARMORY_SCREEN_TITLE_HEIGHT - 2)
	slot.AutomaticSize = Enum.AutomaticSize.X
	local tier = label("Tier", Theme.ARMORY_SCREEN_TIER_TEXT, Theme.MAP_COLOR_GOLD, frame)
	tier.AnchorPoint = Vector2.new(1, 0)
	tier.Position = UDim2.fromScale(1, 0)
	tier.Size = UDim2.fromOffset(Theme.ARMORY_SCREEN_TIER_WIDTH, Theme.ARMORY_SCREEN_TITLE_HEIGHT)
	tier.TextXAlignment = Enum.TextXAlignment.Right

	local trackTop = Theme.ARMORY_SCREEN_TITLE_HEIGHT + Theme.ARMORY_SCREEN_LINE_GAP
	local track = ArmoryTrack.new(frame)
	track.frame.Position = UDim2.fromOffset(0, trackTop)

	local linesTop = trackTop + ArmoryTrack.Height() + Theme.ARMORY_SCREEN_LINE_GAP
	local lineStep = Theme.ARMORY_SCREEN_LINE_HEIGHT + Theme.ARMORY_SCREEN_LINE_GAP
	local lines: { TextLabel } = {}
	for index, lineName in { "Next", "Cost", "Ability" } do
		local line = label(lineName, Theme.ARMORY_SCREEN_LINE_TEXT, Theme.MAP_COLOR_TEXT, frame)
		line.Font = Theme.FONT
		line.Position = UDim2.fromOffset(0, linesTop + (index - 1) * lineStep)
		line.Size = UDim2.new(1, 0, 0, Theme.ARMORY_SCREEN_LINE_HEIGHT)
		lines[index] = line
	end
	local nextLabel, costLabel, abilityLabel = lines[1], lines[2], lines[3]
	costLabel.TextColor3 = Theme.MAP_COLOR_GOLD
	abilityLabel.TextColor3 = Theme.MAP_COLOR_DIM

	local function makeButton(buttonName: string, handler: () -> ()): Button
		local button = Create("TextButton", {
			Name = buttonName,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.ARMORY_SCREEN_LINE_TEXT,
			TextWrapped = true,
			Text = "",
			Visible = false,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = frame,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.ARMORY_SCREEN_BUTTON_TEXT_PAD),
			PaddingRight = UDim.new(0, Theme.ARMORY_SCREEN_BUTTON_TEXT_PAD),
			Parent = button,
		})
		local stroke = Create("UIStroke", {
			Color = Theme.MAP_COLOR_GOLD,
			Thickness = Theme.STROKE_THICKNESS,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = false,
			Parent = button,
		}) :: UIStroke
		return { button = button, stroke = stroke, unbind = deps.bind(button, handler) }
	end

	-- Each press acts on the detail on show, and only while its button is live there: the model
	-- decided it, this never re-decides.
	local styles: { Button } = {}
	local function styleButton(index: number): Button
		local existing = styles[index]
		if existing ~= nil then
			return existing
		end
		local made = makeButton("Style" .. index, function()
			local shown = view.shown
			local state = if shown ~= nil then shown.styles[index] else nil
			if shown ~= nil and state ~= nil and state.live then
				deps.onEquip(shown.card.family, state.variant)
			end
		end)
		styles[index] = made
		return made
	end
	local equip = makeButton("Equip", function()
		local shown = view.shown
		if shown ~= nil and shown.equip.live then
			deps.onEquip(shown.card.family, shown.equipVariant)
		end
	end)
	local upgrade = makeButton("Upgrade", function()
		local shown = view.shown
		if shown ~= nil and shown.upgrade.live then
			deps.onUpgrade(shown.card.family)
		end
	end)

	-- The button row at the column's foot, left to right styles, Equip, Upgrade: Upgrade takes
	-- ARMORY_SCREEN_UPGRADE_SHARE of a share (its refusals are the longest words, "Needs ★ Hard
	-- on Forest Road" stays two lines), the rest one each, none past BUTTON_MAX_WIDTH a share.
	local function placeButtons(): ()
		local row: { Button } = {}
		for _, entry in styles do
			if entry.button.Visible then
				table.insert(row, entry)
			end
		end
		for _, entry in { equip, upgrade } do
			if entry.button.Visible then
				table.insert(row, entry)
			end
		end
		local count = #row
		if count == 0 then
			return
		end
		local gap = Theme.ARMORY_SCREEN_GAP
		local shares = 0
		for _, entry in row do
			shares += if entry == upgrade then Theme.ARMORY_SCREEN_UPGRADE_SHARE else 1
		end
		local share = math.min(
			Theme.ARMORY_SCREEN_BUTTON_MAX_WIDTH,
			(view.width - gap * (count - 1)) / shares
		)
		local top = math.max(view.height, ArmoryDetail.Height()) - Theme.ARMORY_SCREEN_BUTTON_HEIGHT
		local x = 0
		for _, entry in row do
			local width = math.floor(
				share * (if entry == upgrade then Theme.ARMORY_SCREEN_UPGRADE_SHARE else 1)
			)
			entry.button.Position = UDim2.fromOffset(x, top)
			entry.button.Size = UDim2.fromOffset(width, Theme.ARMORY_SCREEN_BUTTON_HEIGHT)
			x += width + gap
		end
	end

	local function paint(): ()
		local shown = view.shown
		frame.Visible = shown ~= nil
		if shown == nil then
			return
		end
		local card = shown.card
		name.Text = card.name
		name.TextColor3 = if card.owned then Theme.MAP_COLOR_TEXT else Theme.MAP_COLOR_DIM
		slot.Text = string.upper(card.slotWord)
		tier.Text = card.tierText
		tier.TextColor3 = if card.owned then Theme.MAP_COLOR_GOLD else Theme.MAP_COLOR_OFF
		track.Show(shown.pips)
		local cost = shown.costLine
		nextLabel.Text = shown.nextLine
		-- Without a cost line the next line may wrap into its room (an unowned family's hint).
		nextLabel.TextWrapped = cost == nil
		nextLabel.Size = UDim2.new(
			1,
			0,
			0,
			if cost == nil
				then Theme.ARMORY_SCREEN_LINE_HEIGHT * 2 + Theme.ARMORY_SCREEN_LINE_GAP
				else Theme.ARMORY_SCREEN_LINE_HEIGHT
		)
		nextLabel.TextYAlignment = Enum.TextYAlignment.Top
		costLabel.Text = cost or ""
		abilityLabel.Text = shown.abilityLine or ""
		for index, state in shown.styles do
			paintButton(styleButton(index), state, false)
		end
		for index = #shown.styles + 1, #styles do
			styles[index].button.Visible = false
			styles[index].button.Selectable = false
		end
		paintButton(equip, shown.equip, false)
		paintButton(upgrade, shown.upgrade, true)
		placeButtons()
	end

	local detail: DetailView = {
		frame = frame,
		Show = function(shown: ArmoryModel.Detail?)
			view.shown = shown
			paint()
		end,
		SetSize = function(width: number, height: number)
			view.width = width
			view.height = height
			frame.Size = UDim2.fromOffset(width, height)
			track.SetWidth(width)
			placeButtons()
		end,
		FirstSelection = function(): GuiObject?
			for _, entry in styles do
				if entry.button.Visible and entry.button.Selectable then
					return entry.button
				end
			end
			for _, entry in { equip, upgrade } do
				if entry.button.Visible and entry.button.Selectable then
					return entry.button
				end
			end
			return nil
		end,
		Destroy = function()
			for _, entry in styles do
				entry.unbind()
			end
			equip.unbind()
			upgrade.unbind()
			table.clear(styles)
			track.Destroy()
			frame:Destroy()
		end,
	}
	return detail
end

return ArmoryDetail
