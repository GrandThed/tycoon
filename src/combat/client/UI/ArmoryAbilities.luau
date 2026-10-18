--!strict
-- The Armory's Abilities tab (docs/prompts/l2-w1-contract.md, L2-10; grown into a tab by
-- docs/prompts/l2-w2-contract.md, section 2). W1's Abilities panel rows, unchanged in behaviour:
-- a display and an intent, nothing else.
--
-- The list is Config/Expeditions.json `abilities.list` in `order`; what the player has and holds
-- is the latest Snapshot (`combat.valor`, `combat.abilities`), which the host hands in. Buy sends
-- RequestBuyAbility(id) through the host and stays quiet until the server's `buyAbility`
-- ActionResult (or Theme.ABILITIES_RESULT_TIMEOUT_SECONDS): the server decides, the Snapshot
-- after it is the truth. A row reads Owned, Buy, or "Need N more Valor". The Valor held is the
-- page's first line (it is this tab's currency). Rows are 68 design px, Buy is 48 (44 physical at
-- MIN_SCALE); the page scrolls when the sheet cannot hold it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Format = require(sharedFolder:WaitForChild("Format"))
local Types = require(sharedFolder:WaitForChild("Types"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Deps = {
	-- Sends RequestBuyAbility(abilityId); false = it could not be sent (no remote).
	onBuy: (abilityId: string) -> boolean,
	toast: (text: string, seconds: number, isError: boolean) -> (),
	-- Whether a press may act now (the sheet is open and the lobby is up).
	isLive: () -> boolean,
}

-- One ability the tab offers, read from the config and checked (it is a JSON file).
export type Offer = { id: string, name: string, text: string, price: number, order: number }

export type Page = {
	frame: ScrollingFrame,
	SetState: (valor: number, owned: { [string]: any }) -> (),
	-- The server's ActionResult for a purchase (action "buyAbility"); anything else is ignored.
	OnResult: (payload: any) -> (),
	Paint: () -> (),
	-- The first live Buy (nil = none): where a gamepad's selection starts.
	FirstSelection: () -> GuiObject?,
	-- Whether some Buy is live now (the sheet opens on this tab the first time if so).
	HasLiveBuy: () -> boolean,
	NaturalHeight: () -> number,
	Destroy: () -> (),
}

type Row = {
	offer: Offer,
	frame: Frame,
	button: TextButton,
}

local OWNED_TEXT = "Owned"
local BUY_TEXT = "Buy"
local BUYING_TEXT = "Buying..."
local EMPTY_TEXT = "Nothing to learn yet"
local REFUSALS: { [string]: string } = {
	owned = "Already yours",
	busy = "Only in the lobby",
	insufficientFunds = "Not enough Valor",
}
local REFUSAL_FALLBACK = "Try again"

local ArmoryAbilities = {}

-- The offers of Config/Expeditions.json `abilities.list`, by `order` (then id): exactly the
-- entries the server sells (Unlocks.Sellable, the rule UnlockService.Init and Unlocks.Find read,
-- caps and a repeated id included), so the tab never offers what cannot be bought. The server
-- warns about the entries left out; the tab stays quiet.
function ArmoryAbilities.Offers(expeditions: Types.ExpeditionsConfig?): { Offer }
	local offers: { Offer } = {}
	local sellable = Unlocks.Sellable(expeditions)
	for _, def in sellable do
		table.insert(offers, {
			id = def.id,
			name = def.name,
			text = def.text,
			price = def.price.valor,
			order = def.order,
		})
	end
	table.sort(offers, function(a: Offer, b: Offer): boolean
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.id < b.id
	end)
	return offers
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

-- `width` is the page's width in design px (the sheet's inner width).
function ArmoryAbilities.new(parent: Instance, width: number, offers: { Offer }, deps: Deps): Page
	local connections: { RBXScriptConnection } = {}
	local rows: { Row } = {}
	-- `owned` is the last Snapshot's; `learned` the purchases the server confirmed since (the
	-- Snapshot that follows them overwrites both). `pending` is the id whose Buy waits for its
	-- answer, `token` names that wait so an old timer cannot free a newer one.
	local view = {
		valor = 0,
		owned = {} :: { [string]: boolean },
		learned = {} :: { [string]: boolean },
		pending = nil :: string?,
		token = 0,
	}
	local padding = Theme.ABILITIES_PADDING

	local list = Create("ScrollingFrame", {
		Name = "AbilitiesPage",
		Active = true,
		Size = UDim2.fromOffset(width, Theme.ABILITIES_ROW_HEIGHT),
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
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ABILITIES_ROW_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	local rowWidth = width - Theme.SCROLLBAR_THICKNESS
	local textWidth = rowWidth
		- padding * 2
		- Theme.ABILITIES_BUTTON_WIDTH
		- Theme.ABILITIES_ROW_GAP

	local valorLabel = label("Valor", Theme.TEXT_MEDIUM, Theme.MAP_COLOR_GOLD, list)
	valorLabel.LayoutOrder = 0
	valorLabel.Size = UDim2.fromOffset(rowWidth, Theme.LOBBY_ARMORY_VALOR_ROW_HEIGHT)
	valorLabel.TextXAlignment = Enum.TextXAlignment.Right

	local function owns(id: string): boolean
		return view.owned[id] == true or view.learned[id] == true
	end

	local function paintRow(row: Row): ()
		local offer = row.offer
		local button = row.button
		local short = offer.price - view.valor
		local live = false
		if owns(offer.id) then
			button.Text = OWNED_TEXT
			button.BackgroundColor3 = Theme.MAP_COLOR_PANEL_SELECTED
			button.TextColor3 = Theme.COLOR_ACCENT
		elseif view.pending == offer.id then
			button.Text = BUYING_TEXT
			button.BackgroundColor3 = Theme.MAP_COLOR_PANEL_SELECTED
			button.TextColor3 = Theme.MAP_COLOR_GOLD
		elseif short > 0 then
			button.Text = "Need " .. Format.Cash(short) .. " more Valor"
			button.BackgroundColor3 = Theme.MAP_COLOR_PANEL_LIGHT
			button.TextColor3 = Theme.MAP_COLOR_DIM
		else
			live = view.pending == nil
			button.Text = BUY_TEXT
			button.BackgroundColor3 = if live
				then Theme.MAP_COLOR_GOLD
				else Theme.MAP_COLOR_PANEL_LIGHT
			button.TextColor3 = if live then Theme.MAP_COLOR_INK else Theme.MAP_COLOR_DIM
		end
		button.Active = live
		button.Selectable = live
	end

	local function paint(): ()
		valorLabel.Text = Format.Cash(view.valor) .. " Valor"
		for _, row in rows do
			paintRow(row)
		end
	end

	local function buy(row: Row): ()
		local offer = row.offer
		if
			not deps.isLive()
			or view.pending ~= nil
			or owns(offer.id)
			or view.valor < offer.price
		then
			return
		end
		if not deps.onBuy(offer.id) then
			deps.toast(REFUSAL_FALLBACK, Theme.ABILITIES_TOAST_SECONDS, true)
			return
		end
		view.pending = offer.id
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

	for index, offer in offers do
		local frame = Create("Frame", {
			Name = "Ability_" .. offer.id,
			Active = false,
			LayoutOrder = index,
			Size = UDim2.fromOffset(rowWidth, Theme.ABILITIES_ROW_HEIGHT),
			BackgroundColor3 = Theme.MAP_COLOR_PANEL_LIGHT,
			BorderSizePixel = 0,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = list,
		}) :: Frame
		rounded(frame, Theme.ROW_CORNER_RADIUS)
		local nameHeight = Theme.ABILITIES_NAME_TEXT + 4
		local lineHeight = Theme.TEXT_SMALL + 2
		local name = label("Name", Theme.ABILITIES_NAME_TEXT, Theme.MAP_COLOR_TEXT, frame)
		name.Position = UDim2.fromOffset(padding, 4)
		name.Size = UDim2.fromOffset(textWidth, nameHeight)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = offer.name
		local text = label("Text", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, frame)
		text.Font = Theme.FONT
		text.Position = UDim2.fromOffset(padding, 4 + nameHeight)
		text.Size = UDim2.fromOffset(textWidth, lineHeight * 2)
		text.TextWrapped = true
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.Text = offer.text
		local price = label("Price", Theme.TEXT_SMALL, Theme.MAP_COLOR_GOLD, frame)
		price.Position = UDim2.fromOffset(padding, 4 + nameHeight + lineHeight * 2)
		price.Size = UDim2.fromOffset(textWidth, lineHeight)
		price.Text = Format.Cash(offer.price) .. " Valor"
		local button = Create("TextButton", {
			Name = "Buy",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -padding, 0.5, 0),
			Size = UDim2.fromOffset(Theme.ABILITIES_BUTTON_WIDTH, Theme.ABILITIES_BUTTON_HEIGHT),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextWrapped = true,
			Text = "",
			ZIndex = Theme.ZINDEX_CARD,
			Parent = frame,
		}) :: TextButton
		rounded(button, Theme.ROW_CORNER_RADIUS)
		local row: Row = { offer = offer, frame = frame, button = button }
		table.insert(rows, row)
		table.insert(
			connections,
			button.Activated:Connect(function()
				buy(row)
			end)
		)
	end
	if #offers == 0 then
		local empty = label("Empty", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, list)
		empty.Font = Theme.FONT
		empty.LayoutOrder = 1
		empty.Size = UDim2.fromOffset(rowWidth, Theme.ABILITIES_ROW_HEIGHT)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Text = EMPTY_TEXT
	end

	paint()

	local page: Page = {
		frame = list,
		SetState = function(valor: number, owned: { [string]: any })
			view.valor = valor
			table.clear(view.owned)
			for id, value in owned do
				if typeof(id) == "string" and value == true then
					view.owned[id] = true
				end
			end
			-- The Snapshot is the truth from here on, purchases included.
			table.clear(view.learned)
			paint()
		end,
		OnResult = function(payload: any)
			if typeof(payload) ~= "table" or payload.action ~= "buyAbility" then
				return
			end
			local id = payload.slotId
			view.pending = nil
			view.token += 1
			local offer: Offer? = nil
			for _, row in rows do
				if row.offer.id == id then
					offer = row.offer
				end
			end
			if payload.ok == true then
				if typeof(id) == "string" then
					view.learned[id] = true
				end
				local name = if offer ~= nil then offer.name else "Ability"
				deps.toast(name .. " learned!", Theme.ABILITIES_TOAST_SECONDS, false)
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
			for _, row in rows do
				if row.button.Active then
					return row.button
				end
			end
			return nil
		end,
		HasLiveBuy = function(): boolean
			for _, row in rows do
				local offer = row.offer
				if not owns(offer.id) and view.valor >= offer.price then
					return true
				end
			end
			return false
		end,
		NaturalHeight = function(): number
			local count = math.max(#offers, 1)
			return Theme.LOBBY_ARMORY_VALOR_ROW_HEIGHT
				+ Theme.ABILITIES_ROW_GAP
				+ count * Theme.ABILITIES_ROW_HEIGHT
				+ (count - 1) * Theme.ABILITIES_ROW_GAP
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			table.clear(rows)
			list:Destroy()
		end,
	}
	return page
end

return ArmoryAbilities
