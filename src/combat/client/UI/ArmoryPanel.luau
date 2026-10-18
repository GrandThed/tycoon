--!strict
-- The Armory panel (docs/prompts/l2-w2-contract.md, section 2; MISSIONS_DESIGN section 10 calls it
-- the Armory screen): W1's Abilities panel (docs/prompts/l2-w1-contract.md, L2-10) grown into a
-- sheet with two tabs, Weapons (UI/ArmoryWeapons) and Abilities (UI/ArmoryAbilities). The pages
-- own their rows and intents; this module owns the sheet, the tabs, the keys and the layout.
--
-- Opens from the run layer's "Armory" button (phones) or K (the host binds it), only while the
-- host says the lobby is up (SetLobby), on the tab it was last left on (the first time: Abilities
-- when something there can be bought now, else Weapons). Closes on K, Esc, its close button or a
-- tap on the scrim, and whenever the lobby goes. No sound (Ben, 2026-09-24).
--
-- Gamepad (W1's fix round c2, kept): ButtonY toggles it, bound only while the lobby is up (in a run
-- ButtonY is the weapon swap); ButtonB closes it and LB / RB switch the tab, bound above the run's
-- High bindings (the dash on B, the abilities on L1 / R1) only while it is open. Opened after
-- gamepad input, the first live button of the tab is selected (else its tab button) and selection
-- cannot leave the sheet. The host closes the map whenever the panel opens.
--
-- Laid out for a landscape phone first: one sheet under one UIScale, 340 design px wide (fits a
-- 375 px portrait phone at MIN_SCALE), centred. The tab row is the header (two 48 px tabs and the
-- 48 px close button), then the page, then the key line; the page scrolls when a short screen
-- cannot hold it. The Weapons page with two ranged cards makes a 284 design px sheet, inside the
-- 313 a 640 x 360 phone leaves under its top bar (Theme's LOBBY_ARMORY_* note).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local ArmoryAbilities = require(script.Parent:WaitForChild("ArmoryAbilities"))
local ArmoryWeapons = require(script.Parent:WaitForChild("ArmoryWeapons"))

-- "weapons" | "abilities".
export type Tab = string

export type Deps = {
	-- Sends RequestBuyAbility(abilityId); false = it could not be sent (no remote).
	onBuy: (abilityId: string) -> boolean,
	-- Sends RequestSetFamily(slot, family, variant); false = it could not be sent.
	onSetFamily: (slot: ArmoryWeapons.Slot, family: string, variant: string) -> boolean,
	onOpenChanged: (open: boolean) -> (),
	toast: (text: string, seconds: number, isError: boolean) -> (),
	-- The line naming the keys; nil = no line.
	keyHint: string?,
	-- true = ButtonY toggles the panel while the lobby is up.
	padToggle: boolean?,
}

export type ArmoryPanelHandle = {
	-- From every Snapshot: the Valor held, the abilities owned (combat.abilities) and the families
	-- written (combat.families).
	SetState: (valor: number, owned: { [string]: any }, families: { [string]: any }?) -> (),
	-- From every TuneState: the loadout the server confirmed.
	SetLoadout: (loadout: Types.RangeLoadout?) -> (),
	-- false closes the panel and keeps it shut (it is the lobby's).
	SetLobby: (inLobby: boolean) -> (),
	Open: () -> (),
	Close: () -> (),
	Toggle: () -> (),
	IsOpen: () -> boolean,
	-- The server's ActionResult for a purchase ("buyAbility") or a pick ("setFamily").
	OnResult: (payload: any) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

type PageRef = {
	frame: ScrollingFrame,
	Paint: () -> (),
	FirstSelection: () -> GuiObject?,
	NaturalHeight: () -> number,
}

local CLOSE_GLYPH = "X"
local TAB_TEXTS: { [string]: string } = { weapons = "Weapons", abilities = "Abilities" }
local TAB_ORDER: { Tab } = { "weapons", "abilities" }
local PAD_TOGGLE_ACTION = "ExpeditionArmoryPad"
local PAD_CLOSE_ACTION = "ExpeditionArmoryClose"
local PAD_TAB_ACTION = "ExpeditionArmoryTabs"
local PAD_TOGGLE_KEY = Enum.KeyCode.ButtonY
local PAD_CLOSE_KEY = Enum.KeyCode.ButtonB
local PAD_TAB_KEYS: { [Enum.KeyCode]: number } =
	{ [Enum.KeyCode.ButtonL1] = -1, [Enum.KeyCode.ButtonR1] = 1 }
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 1

-- Whether the player's latest input came from a gamepad (Gamepad1 to Gamepad8).
local function padLast(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

local ArmoryPanel = {}

-- The gamepad toggle's button and the tab keys, for the host's hints.
ArmoryPanel.PAD_TOGGLE_NAME = "Y"
ArmoryPanel.PAD_TAB_NAMES = "LB RB"

-- Re-exported so the host needs one require.
ArmoryPanel.Offers = ArmoryAbilities.Offers

local function rounded(instance: Instance, radius: number): ()
	Create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = instance })
end

function ArmoryPanel.new(
	parent: Instance,
	offers: { ArmoryAbilities.Offer },
	deps: Deps
): ArmoryPanelHandle
	local connections: { RBXScriptConnection } = {}
	local view = {
		open = false,
		lobby = false,
		tab = nil :: Tab?,
		scale = 0,
		viewport = Vector2.zero,
	}

	-- The scrim closes the panel on a tap that misses the sheet, and takes it: nothing under an
	-- open panel is played through it.
	local root = Create("TextButton", {
		Name = "ArmoryPanel",
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

	local tabButtons: { [string]: TextButton } = {}
	for index, tab in TAB_ORDER do
		local button = Create("TextButton", {
			Name = "Tab_" .. tab,
			Position = UDim2.fromOffset(
				padding + (index - 1) * (Theme.LOBBY_ARMORY_TAB_WIDTH + Theme.ABILITIES_ROW_GAP),
				padding
			),
			Size = UDim2.fromOffset(Theme.LOBBY_ARMORY_TAB_WIDTH, Theme.ABILITIES_HEADER_HEIGHT),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			Text = TAB_TEXTS[tab],
			ZIndex = Theme.ZINDEX_CARD,
			Parent = sheet,
		}) :: TextButton
		rounded(button, Theme.CORNER_RADIUS)
		tabButtons[tab] = button
	end
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

	local pageTop = padding + Theme.ABILITIES_HEADER_HEIGHT + Theme.ABILITIES_ROW_GAP
	local setOpen: (open: boolean) -> ()
	local function isLive(): boolean
		return view.open and view.lobby
	end
	local weapons = ArmoryWeapons.new(sheet, inner, {
		onSetFamily = deps.onSetFamily,
		toast = deps.toast,
		isLive = isLive,
	})
	local abilities = ArmoryAbilities.new(sheet, inner, offers, {
		onBuy = deps.onBuy,
		toast = deps.toast,
		isLive = isLive,
	})
	local pages: { [string]: PageRef } = { weapons = weapons, abilities = abilities }
	for _, page in pages do
		page.frame.Position = UDim2.fromOffset(padding, pageTop)
	end

	local hintText = deps.keyHint
	local hint: TextLabel? = nil
	if hintText ~= nil then
		hint = Create("TextLabel", {
			Name = "Keys",
			Active = false,
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			TextSize = Theme.ABILITIES_HINT_TEXT,
			TextColor3 = Theme.MAP_COLOR_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.fromOffset(inner, Theme.ABILITIES_HINT_HEIGHT),
			Text = hintText,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = sheet,
		}) :: TextLabel
	end

	local function currentTab(): Tab
		return view.tab or "weapons"
	end

	-- The sheet's height for the tab on show: everything but the page is fixed; the page gets
	-- what the screen leaves, at least one card's height (it scrolls the rest).
	local function layout(): ()
		local scale = view.scale
		if scale <= 0 then
			return
		end
		uiScale.Scale = scale
		local hintRoom = if hint ~= nil
			then Theme.ABILITIES_HINT_HEIGHT + Theme.ABILITIES_ROW_GAP
			else 0
		local fixed = pageTop + hintRoom + padding
		local page = pages[currentTab()]
		local natural = page.NaturalHeight()
		local room = view.viewport.Y / scale - Theme.SCREEN_MARGIN * 2 - fixed
		local height = math.max(math.min(natural, room), Theme.ABILITIES_BUTTON_HEIGHT)
		for _, other in pages do
			other.frame.Size = UDim2.fromOffset(inner, height)
		end
		sheet.Size = UDim2.fromOffset(Theme.ABILITIES_WIDTH, fixed + height)
		local line = hint
		if line ~= nil then
			line.Position = UDim2.fromOffset(padding, fixed + height - padding)
		end
	end

	local function paintTabs(): ()
		local shown = currentTab()
		for tab, button in tabButtons do
			local on = tab == shown
			button.BackgroundColor3 = if on
				then Theme.MAP_COLOR_GOLD
				else Theme.MAP_COLOR_PANEL_LIGHT
			button.TextColor3 = if on then Theme.MAP_COLOR_INK else Theme.MAP_COLOR_TEXT
			pages[tab].frame.Visible = on
		end
	end

	-- Where a gamepad's selection starts on the tab on show: its first live button, else its tab.
	local function firstSelection(): GuiObject
		local tab = currentTab()
		return pages[tab].FirstSelection() or tabButtons[tab]
	end

	local function showTab(tab: Tab): ()
		view.tab = tab
		paintTabs()
		pages[tab].Paint()
		layout()
		local selected = GuiService.SelectedObject
		if view.open and selected ~= nil and selected:IsDescendantOf(root) then
			GuiService.SelectedObject = firstSelection()
		end
	end

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

	local function onPadTab(
		_action: string,
		state: Enum.UserInputState,
		input: InputObject
	): Enum.ContextActionResult
		local step = PAD_TAB_KEYS[input.KeyCode]
		if state == Enum.UserInputState.Begin and step ~= nil then
			local index = table.find(TAB_ORDER, currentTab()) or 1
			local count = #TAB_ORDER
			showTab(TAB_ORDER[(index - 1 + step) % count + 1])
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
			if view.tab == nil then
				view.tab = if abilities.HasLiveBuy() then "abilities" else "weapons"
			end
			showTab(currentTab())
			ContextActionService:BindActionAtPriority(
				PAD_CLOSE_ACTION,
				onPadClose,
				false,
				PAD_PRIORITY,
				PAD_CLOSE_KEY
			)
			local tabKeys: { Enum.KeyCode } = {}
			for key in PAD_TAB_KEYS do
				table.insert(tabKeys, key)
			end
			ContextActionService:BindActionAtPriority(
				PAD_TAB_ACTION,
				onPadTab,
				false,
				PAD_PRIORITY,
				table.unpack(tabKeys)
			)
			if padLast() then
				GuiService.SelectedObject = firstSelection()
			end
		else
			ContextActionService:UnbindAction(PAD_CLOSE_ACTION)
			ContextActionService:UnbindAction(PAD_TAB_ACTION)
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

	for tab, button in tabButtons do
		table.insert(
			connections,
			button.Activated:Connect(function()
				showTab(tab)
			end)
		)
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

	paintTabs()

	local handle: ArmoryPanelHandle = {
		SetState = function(valor: number, owned: { [string]: any }, families: { [string]: any }?)
			abilities.SetState(valor, owned)
			weapons.SetFamilies(families)
			-- A new family adds a card: the Weapons page may have grown.
			layout()
		end,
		SetLoadout = function(loadout: Types.RangeLoadout?)
			weapons.SetLoadout(loadout)
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
			if typeof(payload) ~= "table" then
				return
			end
			if payload.action == "buyAbility" then
				abilities.OnResult(payload)
			elseif payload.action == "setFamily" then
				weapons.OnResult(payload)
			end
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			if scale <= 0 then
				return
			end
			view.scale = scale
			view.viewport = viewportSize
			layout()
		end,
		Destroy = function()
			setOpen(false)
			bindPadToggle(false)
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			weapons.Destroy()
			abilities.Destroy()
			root:Destroy()
		end,
	}
	return handle
end

return ArmoryPanel
