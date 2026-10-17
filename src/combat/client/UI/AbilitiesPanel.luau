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
-- Gamepad (the fix round's c2): ButtonY toggles it, bound only while the lobby is up (in a run
-- ButtonY is the weapon swap, which the lobby has no use for); the host closes the map when the
-- panel opens, whatever opened it. Opened after gamepad input, the first live Buy is selected
-- (else the close button) and selection cannot leave the sheet; ButtonB closes it, bound above
-- the dash's priority (MovementController binds B at High) only while it is open.
--
-- Laid out for a landscape phone first: one sheet under one UIScale, 340 design px wide (fits
-- 375 px portrait at MIN_SCALE), centred; the rows scroll when a short screen cannot hold them.
-- At 667 x 375 under a 58 px top bar the sheet has 330 design px of height, and one row needs
-- 48 + 6 + 68 + 6 + 14 + 20 = 162. The close button and Buy are 48 design px (44 physical at
-- MIN_SCALE).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Format = require(sharedFolder:WaitForChild("Format"))
local Types = require(sharedFolder:WaitForChild("Types"))
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
	-- true = ButtonY toggles the panel while the lobby is up (the host closes the map in
	-- onOpenChanged, as for every other way in).
	padToggle: boolean?,
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
local REFUSALS: { [string]: string } = {
	owned = "Already yours",
	busy = "Only in the lobby",
	insufficientFunds = "Not enough Valor",
}
local REFUSAL_FALLBACK = "Try again"
-- Gamepad: the lobby's toggle and the open panel's close, above the High bindings of the run
-- (InputController's swap on Y, MovementController's dash on B) so neither also fires.
local PAD_TOGGLE_ACTION = "ExpeditionAbilitiesPad"
local PAD_CLOSE_ACTION = "ExpeditionAbilitiesClose"
local PAD_TOGGLE_KEY = Enum.KeyCode.ButtonY
local PAD_CLOSE_KEY = Enum.KeyCode.ButtonB
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 1

-- Whether the player's latest input came from a gamepad (Gamepad1 to Gamepad8).
local function padLast(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

local AbilitiesPanel = {}

-- The gamepad toggle's button, for the host's hints ("Y").
AbilitiesPanel.PAD_TOGGLE_NAME = "Y"

-- The offers of Config/Expeditions.json `abilities.list`, by `order` (then id): exactly the
-- entries the server sells (Unlocks.Sellable, the rule UnlockService.Init and Unlocks.Find read,
-- caps and a repeated id included), so the panel never offers what cannot be bought. The server
-- warns about the entries left out; the panel stays quiet.
function AbilitiesPanel.Offers(expeditions: Types.ExpeditionsConfig?): { Offer }
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
		Selectable = false,
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
		-- A gamepad's selection stays on the sheet's buttons while it is open.
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
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

	-- The first live Buy, else the close button: where a gamepad's selection starts.
	local function firstSelection(): GuiObject
		for _, row in rows do
			if row.button.Active then
				return row.button
			end
		end
		return close
	end

	local setOpen: (open: boolean) -> ()

	local function onPadClose(
		_action: string,
		state: Enum.UserInputState,
		_input: InputObject
	): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			setOpen(false)
		end
		return Enum.ContextActionResult.Sink
	end

	setOpen = function(open: boolean): ()
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
			ContextActionService:BindActionAtPriority(
				PAD_CLOSE_ACTION,
				onPadClose,
				false,
				PAD_PRIORITY,
				PAD_CLOSE_KEY
			)
			if padLast() then
				GuiService.SelectedObject = firstSelection()
			end
		else
			ContextActionService:UnbindAction(PAD_CLOSE_ACTION)
			local selected = GuiService.SelectedObject
			if selected ~= nil and selected:IsDescendantOf(root) then
				GuiService.SelectedObject = nil
			end
		end
		deps.onOpenChanged(open)
	end

	-- The lobby's gamepad toggle; bound while the lobby is up (SetLobby).
	local padBound = false
	local function onPadToggle(
		_action: string,
		state: Enum.UserInputState,
		_input: InputObject
	): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			setOpen(not view.open)
		end
		return Enum.ContextActionResult.Sink
	end
	local function bindPadToggle(bound: boolean): ()
		if deps.padToggle ~= true or bound == padBound then
			return
		end
		padBound = bound
		if bound then
			ContextActionService:BindActionAtPriority(
				PAD_TOGGLE_ACTION,
				onPadToggle,
				false,
				PAD_PRIORITY,
				PAD_TOGGLE_KEY
			)
		else
			ContextActionService:UnbindAction(PAD_TOGGLE_ACTION)
		end
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
			bindPadToggle(inLobby)
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
			setOpen(false)
			bindPadToggle(false)
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
