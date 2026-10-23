--!strict
-- The Armory screen's Abilities tab (docs/prompts/l3-w1-contract.md, L3-18): the lobby panel's
-- Abilities tab (L2-10, L2 W2 section 2) moved into the shared screen, its rows unchanged in
-- behaviour: a display and an intent, nothing else.
--
-- The list is Config/Expeditions.json `abilities.list` in `order` (Offers: exactly what the
-- server sells, Unlocks.Sellable); what the player has is the latest Snapshot (`combat.valor`,
-- `combat.abilities`), which the screen hands in. Buy sends RequestBuyAbility(id) through the
-- host and stays quiet until the server's `buyAbility` ActionResult (or
-- ARMORY_SCREEN_RESULT_TIMEOUT_SECONDS): the server decides, the Snapshot after it is the truth.
-- A row reads Owned, Buy, or "Need N more Valor". The Valor held is the page's first line.
--
-- Read-only where the host gives no buy (the hub, `onBuy` nil): every row not owned reads
-- "Bought in the dungeon's lobby" and nothing is a button. Rows are 68 design px, Buy is 48
-- (44 physical at MIN_SCALE); the page is at most ARMORY_SCREEN_ABILITY_MAX_WIDTH wide, centred,
-- and scrolls when the screen cannot hold it.
--
-- L4 W3 (docs/prompts/l4-w3-contract.md section 7): below the offers, each of `abilities.upcoming`
-- (Glide) is a locked row with no button: its name and text, and "With the Castle" (the map
-- node its `with` names, in RunTally.WithText's words so the report card's "next:" line and this
-- row agree) where a Buy would stand, so Valor has a purpose on screen before the next level
-- exists. Never sold (Unlocks.Sellable reads `list` only), in both places alike.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Format = require(sharedFolder:WaitForChild("Format"))
local Types = require(sharedFolder:WaitForChild("Types"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local RunTally = require(script.Parent:WaitForChild("RunTally"))

export type Deps = {
	-- Sends RequestBuyAbility(abilityId); false = it could not be sent. nil = read-only (the hub).
	onBuy: ((abilityId: string) -> boolean)?,
	toast: (text: string, seconds: number?, isError: boolean?) -> (),
	-- Whether a press may act now (the screen is open and available).
	isLive: () -> boolean,
	bind: (button: GuiButton, handler: () -> ()) -> () -> (),
}

-- One ability the tab offers, read from the config and checked (it is a JSON file). `with` = an
-- upcoming ability's words ("With the Castle"): a locked row, never bought; nil = on sale.
export type Offer = {
	id: string,
	name: string,
	text: string,
	price: number,
	order: number,
	with: string?,
}

export type Page = {
	frame: ScrollingFrame,
	-- The offers as the configs read now (the screen asks at every open, 4-s3: Expeditions may
	-- arrive after the host mounts the screen); the rows are rebuilt only when they changed.
	SetOffers: (offers: { Offer }) -> (),
	SetState: (valor: number, owned: { [string]: any }?) -> (),
	-- The server's ActionResult for a purchase (action "buyAbility"); anything else is ignored.
	OnResult: (payload: any) -> (),
	-- The first live Buy (nil = none): where a gamepad's selection starts.
	FirstSelection: () -> GuiObject?,
	-- Whether some Buy is live now (the screen opens on this tab the first time if so).
	HasLiveBuy: () -> boolean,
	SetSize: (width: number, height: number) -> (),
	Destroy: () -> (),
}

-- `button` on a row on sale; `note` (its words where the Buy would be) on an upcoming row.
type Row = {
	offer: Offer,
	frame: Frame,
	button: TextButton?,
	note: TextLabel?,
	unbind: () -> (),
}

local OWNED_TEXT = "Owned"
local BUY_TEXT = "Buy"
local BUYING_TEXT = "Buying..."
local LOBBY_ONLY_TEXT = "Bought in the dungeon's lobby"
local EMPTY_TEXT = "Nothing to learn yet"
local REFUSALS: { [string]: string } = {
	owned = "Already yours",
	busy = "Only in the lobby",
	insufficientFunds = "Not enough Valor",
}
local REFUSAL_FALLBACK = "Try again"

local ArmoryAbilityPage = {}

-- L4 W3: an upcoming ability's words from its `with` node: RunTally's ("with the Castle"),
-- starting a row with a capital.
local function withText(nodeId: string): string
	local words = RunTally.WithText(nodeId)
	return string.upper(string.sub(words, 1, 1)) .. string.sub(words, 2)
end

-- The offers of Config/Expeditions.json `abilities.list`, by `order` (then id): exactly the
-- entries the server sells (Unlocks.Sellable, the rule UnlockService.Init and Unlocks.Find read,
-- caps and a repeated id included), so the tab never offers what cannot be bought. The server
-- warns about the entries left out; the tab stays quiet. L4 W3: then `abilities.upcoming` in
-- config order, each with its `with` words (locked rows; an entry missing a string field, or
-- with the id of one on sale, is left out).
function ArmoryAbilityPage.Offers(expeditions: Types.ExpeditionsConfig?): { Offer }
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
	local abilities = if expeditions ~= nil then expeditions.abilities else nil
	local upcoming = if abilities ~= nil then abilities.upcoming else nil
	if expeditions == nil or typeof(upcoming) ~= "table" then
		return offers
	end
	local taken: { [string]: boolean } = {}
	for _, offer in offers do
		taken[offer.id] = true
	end
	for _, def in upcoming do
		if
			typeof(def) == "table"
			and typeof(def.id) == "string"
			and typeof(def.name) == "string"
			and typeof(def.text) == "string"
			and typeof(def.with) == "string"
			and not taken[def.id]
		then
			taken[def.id] = true
			table.insert(offers, {
				id = def.id,
				name = def.name,
				text = def.text,
				price = 0,
				order = #offers + 1,
				with = withText(def.with),
			})
		end
	end
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

function ArmoryAbilityPage.new(parent: Instance, offers: { Offer }, deps: Deps): Page
	local rows: { Row } = {}
	local readOnly = deps.onBuy == nil
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
	local padding = Theme.ARMORY_SCREEN_PADDING
	local buttonWidth = if readOnly
		then Theme.ARMORY_SCREEN_ABILITY_NOTE_WIDTH
		else Theme.ARMORY_SCREEN_ABILITY_BUTTON_WIDTH

	local list = Create("ScrollingFrame", {
		Name = "AbilitiesPage",
		Active = true,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		ScrollBarImageColor3 = Theme.MAP_COLOR_DIM,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: ScrollingFrame
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ARMORY_SCREEN_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = list,
	})
	-- Rows take the page's width less the scroll bar, up to the cap.
	local function rowSize(height: number): UDim2
		return UDim2.new(1, -Theme.SCROLLBAR_THICKNESS, 0, height)
	end

	local valorLabel = label("Valor", Theme.TEXT_MEDIUM, Theme.MAP_COLOR_GOLD, list)
	valorLabel.LayoutOrder = 0
	valorLabel.Size = rowSize(Theme.ARMORY_SCREEN_VALOR_ROW_HEIGHT)
	valorLabel.TextXAlignment = Enum.TextXAlignment.Right

	local function owns(id: string): boolean
		return view.owned[id] == true or view.learned[id] == true
	end

	local function paintRow(row: Row): ()
		local offer = row.offer
		local note = row.note
		if note ~= nil then
			note.Text = if owns(offer.id) then OWNED_TEXT else offer.with or ""
			note.TextColor3 = if owns(offer.id) then Theme.COLOR_ACCENT else Theme.MAP_COLOR_DIM
		end
		local button = row.button
		if button == nil then
			return
		end
		local short = offer.price - view.valor
		local live = false
		if owns(offer.id) then
			button.Text = OWNED_TEXT
			button.BackgroundColor3 = Theme.MAP_COLOR_PANEL_SELECTED
			button.TextColor3 = Theme.COLOR_ACCENT
		elseif readOnly then
			button.Text = LOBBY_ONLY_TEXT
			button.BackgroundColor3 = Theme.MAP_COLOR_PANEL
			button.TextColor3 = Theme.MAP_COLOR_DIM
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
		-- 4-s2: a Buy waiting for its answer keeps a pad's selection (its press re-checks).
		button.Selectable = live or view.pending == offer.id
	end

	local function paint(): ()
		valorLabel.Text = Format.Cash(view.valor) .. " Valor"
		for _, row in rows do
			paintRow(row)
		end
	end

	local function buy(row: Row): ()
		local offer = row.offer
		local onBuy = deps.onBuy
		if
			onBuy == nil
			or offer.with ~= nil
			or not deps.isLive()
			or view.pending ~= nil
			or owns(offer.id)
			or view.valor < offer.price
		then
			return
		end
		if not onBuy(offer.id) then
			deps.toast(REFUSAL_FALLBACK, Theme.ARMORY_SCREEN_TOAST_SECONDS, true)
			return
		end
		view.pending = offer.id
		view.token += 1
		local token = view.token
		paint()
		task.delay(Theme.ARMORY_SCREEN_RESULT_TIMEOUT_SECONDS, function()
			if token == view.token and view.pending ~= nil then
				view.pending = nil
				paint()
			end
		end)
	end

	local textWidth = -(padding * 2 + buttonWidth + Theme.ARMORY_SCREEN_GAP)
	-- What the rows were built from: the screen hands the offers in again at every open.
	local built = { signature = nil :: string?, empty = nil :: TextLabel? }
	local function signatureOf(offerList: { Offer }): string
		local parts: { string } = {}
		for _, offer in offerList do
			table.insert(
				parts,
				table.concat(
					{ offer.id, offer.name, offer.text, tostring(offer.price), offer.with or "" },
					"|"
				)
			)
		end
		return table.concat(parts, ",")
	end
	local function dropRows(): ()
		for _, row in rows do
			row.unbind()
			row.frame:Destroy()
		end
		table.clear(rows)
		local empty = built.empty
		if empty ~= nil then
			empty:Destroy()
			built.empty = nil
		end
	end
	local function build(offerList: { Offer }): ()
		local signature = signatureOf(offerList)
		if signature == built.signature then
			return
		end
		built.signature = signature
		dropRows()
		for index, offer in offerList do
			local frame = Create("Frame", {
				Name = "Ability_" .. offer.id,
				Active = false,
				LayoutOrder = index,
				Size = rowSize(Theme.ARMORY_SCREEN_ABILITY_ROW_HEIGHT),
				-- An upcoming row sits a shade darker: it cannot be bought yet.
				BackgroundColor3 = if offer.with ~= nil
					then Theme.MAP_COLOR_PANEL
					else Theme.MAP_COLOR_PANEL_LIGHT,
				BorderSizePixel = 0,
				ZIndex = Theme.ZINDEX_CARD,
				Parent = list,
			}) :: Frame
			rounded(frame, Theme.ROW_CORNER_RADIUS)
			local nameHeight = Theme.ARMORY_SCREEN_ABILITY_NAME_TEXT + 4
			local lineHeight = Theme.TEXT_SMALL + 2
			local name =
				label("Name", Theme.ARMORY_SCREEN_ABILITY_NAME_TEXT, Theme.MAP_COLOR_TEXT, frame)
			name.Position = UDim2.fromOffset(padding, 4)
			name.Size = UDim2.new(1, textWidth, 0, nameHeight)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = offer.name
			local text = label("Text", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, frame)
			text.Font = Theme.FONT
			text.Position = UDim2.fromOffset(padding, 4 + nameHeight)
			text.Size = UDim2.new(1, textWidth, 0, lineHeight * 2)
			text.TextWrapped = true
			text.TextTruncate = Enum.TextTruncate.AtEnd
			text.TextYAlignment = Enum.TextYAlignment.Top
			text.Text = offer.text
			local row: Row = {
				offer = offer,
				frame = frame,
				button = nil,
				note = nil,
				unbind = function() end,
			}
			table.insert(rows, row)
			if offer.with ~= nil then
				-- L4 W3: upcoming, so no price and no button: its words stand where Buy would.
				local note = label("With", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, frame)
				note.AnchorPoint = Vector2.new(1, 0.5)
				note.Position = UDim2.new(1, -padding, 0.5, 0)
				note.Size = UDim2.fromOffset(buttonWidth, Theme.ARMORY_SCREEN_BUTTON_HEIGHT)
				note.TextXAlignment = Enum.TextXAlignment.Right
				note.TextWrapped = true
				row.note = note
				continue
			end
			local price = label("Price", Theme.TEXT_SMALL, Theme.MAP_COLOR_GOLD, frame)
			price.Position = UDim2.fromOffset(padding, 4 + nameHeight + lineHeight * 2)
			price.Size = UDim2.new(1, textWidth, 0, lineHeight)
			price.Text = Format.Cash(offer.price) .. " Valor"
			local button = Create("TextButton", {
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -padding, 0.5, 0),
				Size = UDim2.fromOffset(buttonWidth, Theme.ARMORY_SCREEN_BUTTON_HEIGHT),
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
			row.button = button
			row.unbind = deps.bind(button, function()
				buy(row)
			end)
		end
		if #offerList == 0 then
			local empty = label("Empty", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, list)
			empty.Font = Theme.FONT
			empty.LayoutOrder = 1
			empty.Size = rowSize(Theme.ARMORY_SCREEN_ABILITY_ROW_HEIGHT)
			empty.TextXAlignment = Enum.TextXAlignment.Center
			empty.Text = EMPTY_TEXT
			built.empty = empty
		end
	end
	build(offers)

	paint()

	local page: Page = {
		frame = list,
		SetOffers = function(offerList: { Offer })
			build(offerList)
			paint()
		end,
		SetState = function(valor: number, owned: { [string]: any }?)
			view.valor = valor
			table.clear(view.owned)
			if owned ~= nil then
				for id, value in owned do
					if typeof(id) == "string" and value == true then
						view.owned[id] = true
					end
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
				deps.toast(name .. " learned!", Theme.ARMORY_SCREEN_TOAST_SECONDS, false)
			else
				local reason = payload.reason
				deps.toast(
					if typeof(reason) == "string"
						then REFUSALS[reason] or REFUSAL_FALLBACK
						else REFUSAL_FALLBACK,
					Theme.ARMORY_SCREEN_TOAST_SECONDS,
					true
				)
			end
			paint()
		end,
		FirstSelection = function(): GuiObject?
			for _, row in rows do
				local button = row.button
				if button ~= nil and button.Active then
					return button
				end
			end
			return nil
		end,
		HasLiveBuy = function(): boolean
			if readOnly then
				return false
			end
			for _, row in rows do
				local offer = row.offer
				if offer.with == nil and not owns(offer.id) and view.valor >= offer.price then
					return true
				end
			end
			return false
		end,
		SetSize = function(width: number, height: number)
			list.Size =
				UDim2.fromOffset(math.min(width, Theme.ARMORY_SCREEN_ABILITY_MAX_WIDTH), height)
		end,
		Destroy = function()
			dropRows()
			list:Destroy()
		end,
	}
	return page
end

return ArmoryAbilityPage
