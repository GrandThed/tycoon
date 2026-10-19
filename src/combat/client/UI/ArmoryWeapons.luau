--!strict
-- The Armory's Weapons tab (docs/prompts/l2-w2-contract.md, section 2, L2-30 to L2-33). A display
-- and an intent: the server decides what may be held (Unlocks.FamilyVerdict) and confirms the
-- loadout on TuneState, which the host hands in.
--
--  * Two columns, Melee and Ranged. Each owned family is a card: its name, a chip for its
--    element ("FIRE"), and one row of 48 design px buttons: "Equip" for a one-variant family,
--    one button per variant (its label) for a family with two. What is held is gold and does
--    nothing when pressed.
--  * Owned = a starter (the config `loadout`) or a family the profile's `families` holds
--    (Unlocks.OwnsFamily, the server's own rule). An unowned family is listed only when a level's
--    secret pays it, locked, with where it hides ("Hidden on Forest Road": a secret is seen before
--    it is reached, MISSIONS_DESIGN section 7). Today that is the Flamethrower alone.
--  * A press sends RequestSetFamily(slot, family, variant) through the host and greys every
--    button until the `setFamily` ActionResult that names its family (or
--    Theme.ABILITIES_RESULT_TIMEOUT_SECONDS, the one Armory timeout). An ok shows the pick as held
--    at once; the TuneState after it is the truth.
--
-- Laid out for the 340-wide sheet: two 155 design px columns, cards 80 tall (name row 20, the
-- button row 48, three 4 px gaps). A name is truncated, never wrapped; a variant label wraps to two
-- lines inside its button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Types = require(sharedFolder:WaitForChild("Types"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

-- "melee" | "ranged" (a string, as the remote carries it).
export type Slot = string

export type Deps = {
	-- Sends RequestSetFamily(slot, family, variant); false = it could not be sent (no remote).
	onSetFamily: (slot: Slot, family: string, variant: string) -> boolean,
	toast: (text: string, seconds: number, isError: boolean) -> (),
	-- Whether a press may act now (the sheet is open and the lobby is up).
	isLive: () -> boolean,
	-- After every repaint (a button may have gone unselectable or been rebuilt away): the panel
	-- puts a gamepad's selection back on a live button (c-m2).
	onRepaint: (() -> ())?,
}

export type VariantModel = { key: string, label: string }

-- One card: a family as the tab shows it. `hidden` = where an unowned family hides (locked).
export type CardModel = {
	family: string,
	name: string,
	slot: Slot,
	era: number,
	element: string?,
	variants: { VariantModel },
	default: string,
	owned: boolean,
	hidden: string?,
}

export type Columns = { melee: { CardModel }, ranged: { CardModel } }

export type Page = {
	frame: ScrollingFrame,
	-- The Snapshot's `combat.families` (nil = none written).
	SetFamilies: (families: { [string]: any }?) -> (),
	-- The loadout the server last confirmed (FeedbackController.GetLoadout), nil = the starters.
	SetLoadout: (loadout: Types.RangeLoadout?) -> (),
	-- The server's ActionResult for a pick (action "setFamily"); anything else is ignored.
	OnResult: (payload: any) -> (),
	Paint: () -> (),
	FirstSelection: () -> GuiObject?,
	NaturalHeight: () -> number,
	Destroy: () -> (),
}

type Button = { button: TextButton, variant: string }
type Card = {
	model: CardModel,
	frame: Frame,
	stroke: UIStroke,
	buttons: { Button },
	connections: { RBXScriptConnection },
}

local MELEE: Slot = "melee"
local RANGED: Slot = "ranged"
local COLUMN_TITLES: { [string]: string } = { melee = "Melee", ranged = "Ranged" }
local EQUIP_TEXT = "Equip"
local EQUIPPED_TEXT = "Equipped"
local EQUIPPING_TEXT = "Equipping..."
local HIDDEN_PREFIX = "Hidden on "
local HIDDEN_FALLBACK = "Hidden in a level"
local REFUSALS: { [string]: string } = {
	locked = "Not yours yet",
	busy = "Only in the lobby",
	invalid = "Can't equip that",
}
local REFUSAL_FALLBACK = "Try again"

local ArmoryWeapons = {}

-- Every family a level's secret pays, and the name of that level: where it hides. Read from
-- Config/Levels (the first level in id order that pays it).
function ArmoryWeapons.HiddenWhere(): { [string]: string }
	local where: { [string]: string } = {}
	local ids = table.clone(Catalog.GetLevelIds())
	table.sort(ids)
	for _, id in ids do
		local file = Catalog.GetLevelFile(id)
		local secrets = if file ~= nil then file.secrets else nil
		if file == nil or secrets == nil then
			continue
		end
		for _, secret in secrets do
			local family = secret.family
			if typeof(family) == "string" and family ~= "" and where[family] == nil then
				where[family] = file.name
			end
		end
	end
	return where
end

-- The two columns, pure: every owned family of `weapons`, and the unowned ones `hidden` names,
-- each in its own slot's column by era then name. A family whose def is malformed (no variants,
-- a slot that is neither) is left out.
function ArmoryWeapons.Columns(
	weapons: { [string]: Types.RangeWeaponDef },
	starters: { [string]: boolean },
	families: { [string]: boolean }?,
	hidden: { [string]: string }
): Columns
	local columns: Columns = { melee = {}, ranged = {} }
	for family, def in weapons do
		if typeof(def) ~= "table" or typeof(def.variants) ~= "table" then
			continue
		end
		local slot: Slot? = if def.slot == MELEE
			then MELEE
			elseif def.slot == RANGED then RANGED
			else nil
		if slot == nil then
			continue
		end
		local owned = Unlocks.OwnsFamily(families, family, starters)
		local where = hidden[family]
		if not owned and where == nil then
			continue
		end
		local variants: { VariantModel } = {}
		for key, variant in def.variants do
			table.insert(variants, {
				key = key,
				label = if typeof(variant.label) == "string" and variant.label ~= ""
					then variant.label
					else key,
			})
		end
		if #variants == 0 then
			continue
		end
		table.sort(variants, function(a: VariantModel, b: VariantModel): boolean
			return a.key < b.key
		end)
		table.insert(if slot == MELEE then columns.melee else columns.ranged, {
			family = family,
			name = if typeof(def.name) == "string" and def.name ~= "" then def.name else family,
			slot = slot,
			era = if typeof(def.era) == "number" then def.era else math.huge,
			element = Unlocks.ElementOf(weapons, family),
			variants = variants,
			default = if def.variants[def.default] ~= nil then def.default else variants[1].key,
			owned = owned,
			hidden = if owned then nil else where,
		})
	end
	for _, list in { columns.melee, columns.ranged } do
		table.sort(list, function(a: CardModel, b: CardModel): boolean
			if a.owned ~= b.owned then
				return a.owned
			end
			if a.era ~= b.era then
				return a.era < b.era
			end
			return a.name < b.name
		end)
	end
	return columns
end

local function cardHeight(): number
	return Theme.LOBBY_ARMORY_CARD_PAD * 3
		+ Theme.LOBBY_ARMORY_CARD_NAME_HEIGHT
		+ Theme.ABILITIES_BUTTON_HEIGHT
end

local function columnHeight(count: number): number
	local cards = math.max(count, 1)
	return Theme.LOBBY_ARMORY_COLUMN_TITLE_HEIGHT + cards * (cardHeight() + Theme.ABILITIES_ROW_GAP)
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
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: TextLabel
end

local function rounded(instance: Instance, radius: number): ()
	Create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = instance })
end

-- A signature of the columns, so a Snapshot that changes nothing rebuilds nothing.
local function signature(columns: Columns): string
	local parts: { string } = {}
	for _, list in { columns.melee, columns.ranged } do
		for _, card in list do
			table.insert(parts, card.family .. (if card.owned then "+" else "-"))
		end
		table.insert(parts, "|")
	end
	return table.concat(parts, ",")
end

-- `width` is the page's width in design px (the sheet's inner width).
function ArmoryWeapons.new(parent: Instance, width: number, deps: Deps): Page
	local cards: { Card } = {}
	-- `families` is the last Snapshot's; `loadout` the last TuneState's; `picked` a pick the
	-- server accepted since (the TuneState after it replaces it); `pending` the pick waiting for
	-- its answer and `token` that wait's name, so an old timer cannot free a newer one.
	local view = {
		families = {} :: { [string]: boolean },
		loadout = nil :: Types.RangeLoadout?,
		picked = nil :: { slot: Slot, family: string, variant: string }?,
		pending = nil :: { slot: Slot, family: string, variant: string }?,
		token = 0,
		signature = "",
		counts = { melee = 0, ranged = 0 },
		-- Where the unowned families hide: the level configs do not change in a session.
		hidden = nil :: { [string]: string }?,
	}

	local page = Create("ScrollingFrame", {
		Name = "WeaponsPage",
		Active = true,
		Size = UDim2.fromOffset(width, cardHeight()),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: ScrollingFrame
	local columnWidth = (width - Theme.SCROLLBAR_THICKNESS - Theme.LOBBY_ARMORY_COLUMN_GAP) / 2
	local columnFrames: { [string]: Frame } = {}
	for index, slot in { MELEE, RANGED } do
		local column = Create("Frame", {
			Name = COLUMN_TITLES[slot],
			Active = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(
				(index - 1) * (columnWidth + Theme.LOBBY_ARMORY_COLUMN_GAP),
				0
			),
			Size = UDim2.fromOffset(columnWidth, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = page,
		}) :: Frame
		Create("UIListLayout", {
			Padding = UDim.new(0, Theme.ABILITIES_ROW_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = column,
		})
		local title = label("Title", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, column)
		title.LayoutOrder = 0
		title.Size = UDim2.fromOffset(columnWidth, Theme.LOBBY_ARMORY_COLUMN_TITLE_HEIGHT)
		title.Text = string.upper(COLUMN_TITLES[slot])
		columnFrames[slot] = column
	end

	-- What a slot holds now: the accepted pick, else the TuneState's loadout, else the starters.
	local function held(slot: Slot): (string?, string?)
		local picked = view.picked
		if picked ~= nil and picked.slot == slot then
			return picked.family, picked.variant
		end
		local loadout = view.loadout
		if loadout ~= nil then
			local family = if slot == MELEE then loadout.melee else loadout.ranged
			return family, loadout.variants[family]
		end
		local config = Catalog.GetProvingGroundsConfig()
		if config ~= nil then
			return if slot == MELEE then config.loadout.melee else config.loadout.ranged, nil
		end
		return nil, nil
	end

	local function paintCard(card: Card): ()
		local model = card.model
		local heldFamily, heldVariant = held(model.slot)
		local isHeld = model.owned and heldFamily == model.family
		local heldKey = if isHeld then heldVariant or model.default else nil
		local pending = view.pending
		local waiting = pending ~= nil
		local thisPending = pending ~= nil and pending.family == model.family
		card.stroke.Enabled = isHeld
		for _, entry in card.buttons do
			local button = entry.button
			local live = false
			if not model.owned then
				button.BackgroundColor3 = Theme.MAP_COLOR_LOCKED
				button.TextColor3 = Theme.MAP_COLOR_DIM
			elseif thisPending and pending ~= nil and pending.variant == entry.variant then
				button.BackgroundColor3 = Theme.MAP_COLOR_PANEL_SELECTED
				button.TextColor3 = Theme.MAP_COLOR_GOLD
				if #card.buttons == 1 then
					button.Text = EQUIPPING_TEXT
				end
			elseif heldKey == entry.variant then
				button.BackgroundColor3 = Theme.MAP_COLOR_GOLD
				button.TextColor3 = Theme.MAP_COLOR_INK
				if #card.buttons == 1 then
					button.Text = EQUIPPED_TEXT
				end
			else
				live = not waiting
				button.BackgroundColor3 = if live
					then Theme.MAP_COLOR_PANEL_SELECTED
					else Theme.MAP_COLOR_PANEL_LIGHT
				button.TextColor3 = if live then Theme.MAP_COLOR_TEXT else Theme.MAP_COLOR_DIM
				if #card.buttons == 1 then
					button.Text = EQUIP_TEXT
				end
			end
			button.Active = live
			button.Selectable = live
		end
	end

	local function paint(): ()
		for _, card in cards do
			paintCard(card)
		end
		local onRepaint = deps.onRepaint
		if onRepaint ~= nil then
			onRepaint()
		end
	end

	local function pick(card: Card, variant: string): ()
		local model = card.model
		if not deps.isLive() or view.pending ~= nil or not model.owned then
			return
		end
		local heldFamily, heldVariant = held(model.slot)
		if heldFamily == model.family and (heldVariant or model.default) == variant then
			return
		end
		if not deps.onSetFamily(model.slot, model.family, variant) then
			deps.toast(REFUSAL_FALLBACK, Theme.ABILITIES_TOAST_SECONDS, true)
			return
		end
		view.pending = { slot = model.slot, family = model.family, variant = variant }
		view.token += 1
		local token = view.token
		paint()
		task.delay(Theme.ABILITIES_RESULT_TIMEOUT_SECONDS, function()
			if token == view.token and view.pending ~= nil then
				view.pending = nil
				paint()
			end
		end)
	end

	local function buildCard(model: CardModel, order: number): Card
		local pad = Theme.LOBBY_ARMORY_CARD_PAD
		local inner = columnWidth - pad * 2
		local frame = Create("Frame", {
			Name = "Family_" .. model.family,
			Active = false,
			LayoutOrder = order,
			Size = UDim2.fromOffset(columnWidth, cardHeight()),
			BackgroundColor3 = if model.owned
				then Theme.MAP_COLOR_PANEL_LIGHT
				else Theme.MAP_COLOR_PANEL,
			BorderSizePixel = 0,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = columnFrames[model.slot],
		}) :: Frame
		rounded(frame, Theme.ROW_CORNER_RADIUS)
		local stroke = Create("UIStroke", {
			Color = Theme.MAP_COLOR_GOLD,
			Thickness = Theme.STROKE_THICKNESS,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = false,
			Parent = frame,
		}) :: UIStroke
		local element = model.element
		local chipWidth = 0
		if element ~= nil then
			local word = Theme.SECRET_NEED_WORDS[element] or string.upper(element)
			local bounds = TextService:GetTextSize(
				word,
				Theme.LOBBY_ARMORY_CHIP_TEXT,
				Theme.FONT_BOLD,
				Vector2.new(math.huge, math.huge)
			)
			chipWidth = math.ceil(bounds.X) + Theme.LOBBY_ARMORY_CHIP_PAD * 2
			local chip = label("Element", Theme.LOBBY_ARMORY_CHIP_TEXT, Theme.MAP_COLOR_INK, frame)
			chip.AnchorPoint = Vector2.new(1, 0)
			chip.BackgroundTransparency = 0
			chip.BackgroundColor3 = Theme.LOBBY_ARMORY_ELEMENT_COLORS[element]
				or Theme.MAP_COLOR_GOLD
			chip.Position = UDim2.new(
				1,
				-pad,
				0,
				pad + (Theme.LOBBY_ARMORY_CARD_NAME_HEIGHT - Theme.LOBBY_ARMORY_CHIP_HEIGHT) / 2
			)
			chip.Size = UDim2.fromOffset(chipWidth, Theme.LOBBY_ARMORY_CHIP_HEIGHT)
			chip.TextXAlignment = Enum.TextXAlignment.Center
			chip.Text = word
			rounded(chip, Theme.LOBBY_ARMORY_CHIP_HEIGHT // 2)
		end
		local name = label("Name", Theme.LOBBY_ARMORY_CARD_NAME_TEXT, Theme.MAP_COLOR_TEXT, frame)
		name.Position = UDim2.fromOffset(pad, pad)
		name.Size = UDim2.fromOffset(
			inner - (if chipWidth > 0 then chipWidth + pad else 0),
			Theme.LOBBY_ARMORY_CARD_NAME_HEIGHT
		)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = model.name
		if not model.owned then
			name.TextColor3 = Theme.MAP_COLOR_DIM
		end

		local card: Card =
			{ model = model, frame = frame, stroke = stroke, buttons = {}, connections = {} }
		local rowTop = pad * 2 + Theme.LOBBY_ARMORY_CARD_NAME_HEIGHT
		if not model.owned then
			-- Locked: a plain line in the button row, never a button.
			local line = label("Hidden", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, frame)
			line.Font = Theme.FONT
			line.BackgroundTransparency = 0
			line.BackgroundColor3 = Theme.MAP_COLOR_LOCKED
			line.Position = UDim2.fromOffset(pad, rowTop)
			line.Size = UDim2.fromOffset(inner, Theme.ABILITIES_BUTTON_HEIGHT)
			line.TextXAlignment = Enum.TextXAlignment.Center
			line.TextWrapped = true
			line.Text = if model.hidden ~= nil
				then HIDDEN_PREFIX .. model.hidden
				else HIDDEN_FALLBACK
			rounded(line, Theme.ROW_CORNER_RADIUS)
			return card
		end
		local single = #model.variants == 1
		local count = #model.variants
		local buttonWidth = (inner - pad * (count - 1)) / count
		for index, variant in model.variants do
			local button = Create("TextButton", {
				Name = "Variant_" .. variant.key,
				Position = UDim2.fromOffset(pad + (index - 1) * (buttonWidth + pad), rowTop),
				Size = UDim2.fromOffset(buttonWidth, Theme.ABILITIES_BUTTON_HEIGHT),
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Font = Theme.FONT_BOLD,
				TextSize = Theme.TEXT_SMALL,
				TextWrapped = true,
				Text = if single then EQUIP_TEXT else variant.label,
				ZIndex = Theme.ZINDEX_CARD,
				Parent = frame,
			}) :: TextButton
			rounded(button, Theme.ROW_CORNER_RADIUS)
			table.insert(card.buttons, { button = button, variant = variant.key })
			table.insert(
				card.connections,
				button.Activated:Connect(function()
					pick(card, variant.key)
				end)
			)
		end
		return card
	end

	local function dropCards(): ()
		for _, card in cards do
			for _, connection in card.connections do
				connection:Disconnect()
			end
			card.frame:Destroy()
		end
		table.clear(cards)
	end

	local function rebuild(columns: Columns): ()
		dropCards()
		for _, list in { columns.melee, columns.ranged } do
			for index, model in list do
				table.insert(cards, buildCard(model, index))
			end
		end
		view.counts.melee = #columns.melee
		view.counts.ranged = #columns.ranged
	end

	local function hiddenWhere(): { [string]: string }
		local known = view.hidden
		if known ~= nil then
			return known
		end
		local made = ArmoryWeapons.HiddenWhere()
		view.hidden = made
		return made
	end

	local function refresh(): ()
		local config = Catalog.GetProvingGroundsConfig()
		if config == nil then
			return
		end
		local columns = ArmoryWeapons.Columns(
			config.weapons,
			Unlocks.Starters(config.loadout),
			view.families,
			hiddenWhere()
		)
		local nextSignature = signature(columns)
		if nextSignature ~= view.signature then
			view.signature = nextSignature
			rebuild(columns)
		end
		paint()
	end

	refresh()

	local handle: Page = {
		frame = page,
		SetFamilies = function(families: { [string]: any }?)
			table.clear(view.families)
			if typeof(families) == "table" then
				for id, value in families do
					if typeof(id) == "string" and value == true then
						view.families[id] = true
					end
				end
			end
			refresh()
		end,
		SetLoadout = function(loadout: Types.RangeLoadout?)
			view.loadout = loadout
			-- The server's word replaces the pick it confirmed.
			view.picked = nil
			paint()
		end,
		OnResult = function(payload: any)
			if typeof(payload) ~= "table" or payload.action ~= "setFamily" then
				return
			end
			-- c-m3: only the answer to the pick in flight frees it; a late answer to one that timed
			-- out still toasts, and its loadout comes on TuneState.
			local pending = view.pending
			local answers = pending ~= nil and pending.family == payload.slotId
			if answers then
				view.pending = nil
				view.token += 1
			end
			local name = "Weapon"
			for _, card in cards do
				if card.model.family == payload.slotId then
					name = card.model.name
				end
			end
			if payload.ok == true then
				if answers then
					view.picked = pending
				end
				deps.toast(name .. " equipped", Theme.ABILITIES_TOAST_SECONDS, false)
			else
				local reason = payload.reason
				deps.toast(
					if typeof(reason) == "string"
						then REFUSALS[reason] or REFUSAL_FALLBACK
						else REFUSAL_FALLBACK,
					Theme.ABILITIES_TOAST_SECONDS,
					true
				)
			end
			paint()
		end,
		Paint = paint,
		FirstSelection = function(): GuiObject?
			for _, card in cards do
				for _, entry in card.buttons do
					if entry.button.Active then
						return entry.button
					end
				end
			end
			return nil
		end,
		NaturalHeight = function(): number
			return math.max(columnHeight(view.counts.melee), columnHeight(view.counts.ranged))
		end,
		Destroy = function()
			dropCards()
			page:Destroy()
		end,
	}
	return handle
end

return ArmoryWeapons
