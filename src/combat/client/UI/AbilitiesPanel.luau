--!strict
-- The Abilities panel (docs/prompts/l2-w1-contract.md, L2-10): bought abilities, in the dungeon
-- place's lobby only. In L3 it becomes the Armory's second tab (docs/MISSIONS_DESIGN.md
-- section 10).
--
-- A display and an intent, nothing else. The list is Config/Expeditions.json `abilities.list`
-- in `order`; what the player has and holds is the latest Snapshot (`combat.valor`,
-- `combat.abilities`), which the host hands in. Buy sends RequestBuyAbility(id) through the
-- host and stays quiet until the server's `buyAbility` ActionResult (or
-- Theme.ABILITIES_RESULT_TIMEOUT_SECONDS): the server decides, the Snapshot after it is the
-- truth. A row reads Owned, Buy, or "Need N more Valor".
--
-- Opens from the run layer's "Abilities" button (phones) or K (the host binds it), only while
-- the host says the lobby is up (SetLobby); closes on K, Esc, its close button or a tap on the
-- scrim, and whenever the lobby goes. No sound (Ben, 2026-09-24).
--
-- Laid out for a landscape phone first: one sheet under one UIScale, 340 design px wide (fits
-- 375 px portrait at MIN_SCALE), centred; the rows scroll when a short screen cannot hold them.
-- At 667 x 375 under a 58 px top bar the sheet has 330 design px of height, and one row needs
-- 48 + 6 + 68 + 6 + 14 + 20 = 162. The close button and Buy are 48 design px (44 physical at
-- MIN_SCALE).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Format = require(sharedFolder:WaitForChild("Format"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Deps = {
	-- Sends RequestBuyAbility(abilityId); false = it could not be sent (no remote).
	onBuy: (abilityId: string) -> boolean,
	onOpenChanged: (open: boolean) -> (),
	toast: (text: string, seconds: number, isError: boolean) -> (),
	-- The line naming the keys that close it; nil = no line.
	keyHint: string?,
}

export type AbilitiesPanelHandle = {
	-- From every Snapshot: the Valor held and the abilities owned (combat.abilities).
	SetState: (valor: number, owned: { [string]: any }) -> (),
	-- false closes the panel and keeps it shut (it is the lobby's).
	SetLobby: (inLobby: boolean) -> (),
	Open: () -> (),
	Close: () -> (),
	Toggle: () -> (),
	IsOpen: () -> boolean,
	-- The server's ActionResult for a purchase (action "buyAbility"); anything else is ignored.
	OnResult: (payload: any) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

-- One ability the panel offers, read from the config and checked (it is a JSON file).
export type Offer = { id: string, name: string, text: string, price: number, order: number }

type Row = {
	offer: Offer,
	frame: Frame,
	price: TextLabel,
	button: TextButton,
}

local TITLE_TEXT = "Abilities"
local CLOSE_GLYPH = "X"
local OWNED_TEXT = "Owned"
local BUY_TEXT = "Buy"
local BUYING_TEXT = "Buying..."
local EMPTY_TEXT = "Nothing to learn yet"
local MAX_ID_LENGTH = 32
local REFUSALS: { [string]: string } = {
	owned = "Already yours",
	busy = "Only in the lobby",
	insufficientFunds = "Not enough Valor",
}
local REFUSAL_FALLBACK = "Try again"

local AbilitiesPanel = {}

-- The offers of Config/Expeditions.json `abilities.list`, by `order` (then id). An entry the
-- server would refuse to sell (Unlocks.DefProblem, the server's own rule) is left out: the panel
-- never offers what cannot be bought. `expeditions` is read loosely because the block is
-- optional and comes from JSON.
function AbilitiesPanel.Offers(expeditions: any): { Offer }
	local offers: { Offer } = {}
	local block = if typeof(expeditions) == "table" then expeditions.abilities else nil
	local list = if typeof(block) == "table" then block.list else nil
	if typeof(list) ~= "table" then
		return offers
	end
	local seen: { [string]: boolean } = {}
	for _, entry in list do
		local id = if typeof(entry) == "table" then entry.id else nil
		if typeof(id) ~= "string" or seen[id] then
			continue
		end
		-- The first entry of an id is the only one the server reads (Unlocks.Find), sound or not.
		seen[id] = true
		if Unlocks.DefProblem(entry) ~= nil or #id > MAX_ID_LENGTH then
			continue
		end
		table.insert(offers, {
			id = entry.id,
			name = entry.name,
			text = entry.text,
			price = entry.price.valor,
			order = entry.order,
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
		Parent = parent,
	}) :: TextLabel
end

local function rounded(instance: Instance, radius: number): ()
	Create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = instance })
end

function AbilitiesPanel.new(parent: Instance, offers: { Offer }, deps: Deps): AbilitiesPanelHandle
	local connections: { RBXScriptConnection } = {}
	local rows: { Row } = {}
	-- `owned` is the last Snapshot's; `learned` the purchases the server confirmed since (the
	-- Snapshot that follows them overwrites both). `pending` is the id whose Buy waits for its
	-- answer, `token` names that wait so an old timer cannot free a newer one.
	local view = {
		open = false,
		lobby = false,
		valor = 0,
		owned = {} :: { [string]: boolean },
		learned = {} :: { [string]: boolean },
		pending = nil :: string?,
		token = 0,
	}

	-- The scrim closes the panel on a tap that misses the sheet, and takes it: nothing under an
	-- open panel is played through it.
	local root = Create("TextButton", {
		Name = "AbilitiesPanel",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = Theme.MAP_SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: TextButton
	local sheet = Create("Frame", {
		Name = "Sheet",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.ABILITIES_WIDTH, Theme.ABILITIES_HEADER_HEIGHT),
		BackgroundColor3 = Theme.MAP_COLOR_PANEL,
		BorderSizePixel = 0,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = root,
	}) :: Frame
	rounded(sheet, Theme.CORNER_RADIUS)
	local uiScale = Create("UIScale", { Parent = sheet }) :: UIScale
	local padding = Theme.ABILITIES_PADDING
	local inner = Theme.ABILITIES_WIDTH - padding * 2

	local title = label("Title", Theme.TEXT_HEADER, Theme.MAP_COLOR_TEXT, sheet)
	title.Position = UDim2.fromOffset(padding, padding)
	title.Size = UDim2.fromOffset(inner / 2, Theme.ABILITIES_HEADER_HEIGHT)
	title.Text = TITLE_TEXT
	title.ZIndex = Theme.ZINDEX_CARD
	local valorLabel = label("Valor", Theme.TEXT_MEDIUM, Theme.MAP_COLOR_GOLD, sheet)
	valorLabel.Position = UDim2.fromOffset(padding + inner / 2, padding)
	valorLabel.Size = UDim2.fromOffset(
		inner / 2 - Theme.MAP_CLOSE_SIZE - Theme.ABILITIES_ROW_GAP,
		Theme.ABILITIES_HEADER_HEIGHT
	)
	valorLabel.TextXAlignment = Enum.TextXAlignment.Right
	valorLabel.ZIndex = Theme.ZINDEX_CARD
	local close = Create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -padding, 0, padding),
		Size = UDim2.fromOffset(Theme.MAP_CLOSE_SIZE, Theme.MAP_CLOSE_SIZE),
		BackgroundColor3 = Theme.MAP_COLOR_PANEL_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.MAP_COLOR_TEXT,
		Text = CLOSE_GLYPH,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = sheet,
	}) :: TextButton
	rounded(close, Theme.CORNER_RADIUS)

	local listTop = padding + Theme.ABILITIES_HEADER_HEIGHT + Theme.ABILITIES_ROW_GAP
	local list = Create("ScrollingFrame", {
		Name = "Rows",
		Active = true,
		Position = UDim2.fromOffset(padding, listTop),
		Size = UDim2.fromOffset(inner, Theme.ABILITIES_ROW_HEIGHT),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = sheet,
	}) :: ScrollingFrame
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ABILITIES_ROW_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	local rowWidth = inner - Theme.SCROLLBAR_THICKNESS
	local textWidth = rowWidth
		- padding * 2
		- Theme.ABILITIES_BUTTON_WIDTH
		- Theme.ABILITIES_ROW_GAP

	local hintText = deps.keyHint
	local hint: TextLabel? = nil
	if hintText ~= nil then
		local line = label("Keys", Theme.ABILITIES_HINT_TEXT, Theme.MAP_COLOR_DIM, sheet)
		line.Font = Theme.FONT
		line.AnchorPoint = Vector2.new(0, 1)
		line.Size = UDim2.fromOffset(inner, Theme.ABILITIES_HINT_HEIGHT)
		line.TextTruncate = Enum.TextTruncate.AtEnd
		line.Text = hintText
		line.ZIndex = Theme.ZINDEX_CARD
		hint = line
	end

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
			not view.open
			or not view.lobby
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
		name.ZIndex = Theme.ZINDEX_CARD
		local text = label("Text", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, frame)
		text.Font = Theme.FONT
		text.Position = UDim2.fromOffset(padding, 4 + nameHeight)
		text.Size = UDim2.fromOffset(textWidth, lineHeight * 2)
		text.TextWrapped = true
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.Text = offer.text
		text.ZIndex = Theme.ZINDEX_CARD
		local price = label("Price", Theme.TEXT_SMALL, Theme.MAP_COLOR_GOLD, frame)
		price.Position = UDim2.fromOffset(padding, 4 + nameHeight + lineHeight * 2)
		price.Size = UDim2.fromOffset(textWidth, lineHeight)
		price.Text = Format.Cash(offer.price) .. " Valor"
		price.ZIndex = Theme.ZINDEX_CARD
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
		local row: Row = { offer = offer, frame = frame, price = price, button = button }
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
		empty.Size = UDim2.fromOffset(rowWidth, Theme.ABILITIES_ROW_HEIGHT)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Text = EMPTY_TEXT
		empty.ZIndex = Theme.ZINDEX_CARD
	end

	local function setOpen(open: boolean): ()
		if open and not view.lobby then
			return
		end
		if open == view.open then
			return
		end
		view.open = open
		root.Visible = open
		if open then
			paint()
		end
		deps.onOpenChanged(open)
	end

	table.insert(
		connections,
		close.Activated:Connect(function()
			setOpen(false)
		end)
	)
	table.insert(
		connections,
		root.Activated:Connect(function()
			setOpen(false)
		end)
	)
	-- Esc: Roblox's menu takes the key itself, so the press is watched whether or not it was
	-- processed, and the menu opening closes the panel as well.
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape then
				setOpen(false)
			end
		end)
	)
	table.insert(
		connections,
		GuiService.MenuOpened:Connect(function()
			setOpen(false)
		end)
	)

	paint()

	local handle: AbilitiesPanelHandle = {
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
		SetLobby = function(inLobby: boolean)
			view.lobby = inLobby
			if not inLobby then
				setOpen(false)
			end
		end,
		Open = function()
			setOpen(true)
		end,
		Close = function()
			setOpen(false)
		end,
		Toggle = function()
			setOpen(not view.open)
		end,
		IsOpen = function(): boolean
			return view.open
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
		SetLayout = function(scale: number, viewportSize: Vector2)
			if scale <= 0 then
				return
			end
			uiScale.Scale = scale
			-- Everything but the rows is fixed; the rows get what the screen leaves, at least one.
			local hintRoom = if hint ~= nil
				then Theme.ABILITIES_HINT_HEIGHT + Theme.ABILITIES_ROW_GAP
				else 0
			local fixed = listTop + hintRoom + padding
			local count = math.max(#offers, 1)
			local natural = count * Theme.ABILITIES_ROW_HEIGHT
				+ (count - 1) * Theme.ABILITIES_ROW_GAP
			local room = viewportSize.Y / scale - Theme.SCREEN_MARGIN * 2 - fixed
			local height = math.max(math.min(natural, room), Theme.ABILITIES_ROW_HEIGHT)
			list.Size = UDim2.fromOffset(inner, height)
			sheet.Size = UDim2.fromOffset(Theme.ABILITIES_WIDTH, fixed + height)
			local line = hint
			if line ~= nil then
				line.Position = UDim2.fromOffset(padding, fixed + height - padding)
			end
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			table.clear(rows)
			root:Destroy()
		end,
	}
	return handle
end

return AbilitiesPanel
