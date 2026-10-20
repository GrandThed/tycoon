--!strict
-- The Armory screen (docs/prompts/l3-w1-contract.md, L3-18 to L3-23; MISSIONS_DESIGN sections 10
-- and 24): one screen for both places, the dungeon place's lobby and the city hub. Layout A,
-- "Showcase" (Ben's pick): a header with the Weapons and Abilities tabs, the wallet and the close
-- button; under it the stage (UI/ArmoryStage) beside the detail column (UI/ArmoryDetail: name,
-- slot, tier, the track of 20, the next and cost lines, the ability, the styles, Equip and
-- Upgrade); under those the shelf of every family (UI/ArmoryShelf). The Abilities tab is
-- UI/ArmoryAbilityPage. What every part shows is UI/ArmoryModel's pure reading of the state.
--
-- A display and an intent. The host hands in each Snapshot's `combat` (SetState), the held
-- loadout (SetHeld), whether a press may act (SetGate: the lobby, or always in the hub) and the
-- server's ActionResults (OnResult). A press sends a family, a slot and a style key through the
-- host, never an amount or a tier, and disables its button until its answer (3 s at most). An
-- accepted upgrade stays "Upgrading..." until the Snapshot shows the tier; an accepted equip is
-- shown as held until the host's next loadout. Toasts say "Longbow: T2" / "Warhammer equipped",
-- or the refusal in the button's own words. No sound (the combat place has none, Ben 2026-09-24).
--
-- It requires only what both places hold: the Shared modules and Create, Motion, Theme and its
-- own Armory* siblings (combat.project.json maps them into the dungeon place's UI folder).
--
-- Inputs (L3-22): the host binds K (and the lobby's HUD button); this binds the rest. Esc, the
-- close button or a tap on the scrim closes it; gamepad Y toggles it while available when the
-- host asks (`padToggle`: the lobby; in a run Y is the weapon swap), B closes, LB / RB switch the
-- tab, the d-pad and stick move a selection that cannot leave the frame. Gamepad A is bound above
-- the jump while it is open and sunk, so pressing a button never also jumps or walks; the action
-- presses the selected button itself in case sinking also stops the engine's own press (not
-- verified outside Studio), and one press router (`bind`) keeps the two from pressing twice.
--
-- Laid out phones first under one UIScale from the host's SetLayout(scale, size), the hosts'
-- one formula: landscape at 682 x 313 design px (640 x 360 under a 58 px top bar) is a 48 header,
-- a 173 middle (stage 220 wide, detail 440) and a 64 shelf; at 712 x 330 (667 x 375) the middle
-- is 189; on a monitor the frame stops at ARMORY_SCREEN_MAX_WIDTH x MAX_HEIGHT (880 x 420).
-- Portrait at 393 x 648 (375 x 667) stacks the stage (full width, 223 tall), the detail (163)
-- and a 5 x 3 shelf (180). Every tap target is at least 48 design px (44 physical at MIN_SCALE).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Types = require(sharedFolder:WaitForChild("Types"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local ArmoryAbilityPage = require(script.Parent:WaitForChild("ArmoryAbilityPage"))
local ArmoryDetail = require(script.Parent:WaitForChild("ArmoryDetail"))
local ArmoryModel = require(script.Parent:WaitForChild("ArmoryModel"))
local ArmoryShelf = require(script.Parent:WaitForChild("ArmoryShelf"))
local ArmoryStage = require(script.Parent:WaitForChild("ArmoryStage"))

export type Deps = {
	-- Sends RequestUpgradeWeapon(family); false = it could not be sent.
	onUpgrade: (family: string) -> boolean,
	-- Sends RequestSetFamily(slot, family, variant); false = it could not be sent.
	onEquip: (slot: string, family: string, variant: string) -> boolean,
	-- Sends RequestBuyAbility(abilityId); nil in the hub (the Abilities tab is read-only there).
	onBuyAbility: ((abilityId: string) -> boolean)?,
	onOpenChanged: (open: boolean) -> (),
	toast: (text: string, seconds: number?, isError: boolean?) -> (),
	-- The line naming the keys, under the wallet; nil = none.
	keyHint: string?,
	-- true = gamepad Y toggles the screen while it is available (the lobby).
	padToggle: boolean,
}

export type Handle = {
	Open: () -> (),
	Close: () -> (),
	Toggle: () -> (),
	IsOpen: () -> boolean,
	-- false closes it and keeps it shut (the lobby: the phase is "lobby"; the hub: always true).
	-- It starts false.
	SetAvailable: (available: boolean) -> (),
	-- Upgrade's and Equip's gateOpen (UpgradeVerdict, FamilyVerdict). It starts false.
	SetGate: (open: boolean) -> (),
	SetState: (combat: Types.CombatProfile) -> (),
	SetHeld: (loadout: Types.RangeLoadout) -> (),
	-- The server's ActionResult for "upgradeWeapon", "setFamily" or "buyAbility".
	OnResult: (result: Types.ActionResult) -> (),
	SetLayout: (scale: number, size: Vector2) -> (),
	-- Not in L3-18's list: the hosts never need it, the screen also cleans up when its root is
	-- destroyed with the ScreenGui.
	Destroy: () -> (),
}

type Tab = string
type Waiting = {
	family: string,
	slot: string,
	variant: string,
	tier: number?,
	answered: boolean,
}

local TAB_ORDER: { Tab } = { "weapons", "abilities" }
local TAB_TEXTS: { [string]: string } = { weapons = "Weapons", abilities = "Abilities" }
local CLOSE_GLYPH = "X"
local ACTIONS = {
	toggle = "ArmoryScreenPadToggle",
	close = "ArmoryScreenPadClose",
	tabs = "ArmoryScreenPadTabs",
	press = "ArmoryScreenPadPress",
}
local PAD_TAB_KEYS: { [Enum.KeyCode]: number } =
	{ [Enum.KeyCode.ButtonL1] = -1, [Enum.KeyCode.ButtonR1] = 1 }
-- Above the run's High bindings (the dash on B, the abilities on L1 / R1) and the jump on A.
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 1

local ArmoryScreen = {}

-- The gamepad toggle's button and the tab keys, for the hosts' hints.
ArmoryScreen.PAD_TOGGLE_NAME = "Y"
ArmoryScreen.PAD_TAB_NAMES = "LB RB"

-- Whether the player's latest input came from a gamepad (Gamepad1 to Gamepad8).
local function padLast(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

-- The configs the screen reads. None changes in a session, but a client may still be receiving
-- the Config folders when the host mounts the screen (Catalog.GetLevelFile's note), so they are
-- read again at every open: a Forest Road that had not arrived must not read as "not built".
local function readConfigs(): {
	armory: Types.ArmoryConfig?,
	weapons: { [string]: Types.RangeWeaponDef },
	loadout: { melee: string, ranged: string }?,
	expeditions: Types.ExpeditionsConfig?,
	levels: { [string]: Types.LevelFile },
	built: { [string]: boolean },
}
	local proving = Catalog.GetProvingGroundsConfig()
	local levels: { [string]: Types.LevelFile } = {}
	local built: { [string]: boolean } = {}
	for _, id in Catalog.GetLevelIds() do
		local file = Catalog.GetLevelFile(id)
		if file ~= nil then
			levels[id] = file
			built[id] = true
		end
	end
	return {
		armory = Catalog.GetArmoryConfig(),
		weapons = if proving ~= nil then proving.weapons else {},
		loadout = if proving ~= nil then proving.loadout else nil,
		expeditions = Catalog.GetExpeditionsConfig(),
		levels = levels,
		built = built,
	}
end

local function rounded(instance: Instance, radius: number): ()
	Create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = instance })
end

function ArmoryScreen.new(parent: Instance, deps: Deps): Handle
	local configs = readConfigs()
	local connections: { RBXScriptConnection } = {}
	local view = {
		open = false,
		available = false,
		gate = false,
		destroyed = false,
		tab = nil :: Tab?,
		selected = nil :: string?,
		combat = nil :: Types.CombatProfile?,
		held = nil :: Types.RangeLoadout?,
		-- An equip the server accepted, shown as held until the host's next loadout.
		picked = nil :: Waiting?,
		upgrade = nil :: Waiting?,
		equip = nil :: Waiting?,
		scale = 0,
		size = Vector2.zero,
		padBound = false,
		-- The shelf's card count at the last layout: a new family may add a row in portrait.
		cards = 0,
	}

	-- The press router: every button of the screen is pressed through here, by a tap, a click,
	-- the engine's gamepad press or the A action below; a press of one button inside the
	-- debounce is the same press.
	local router = {
		handlers = {} :: { [GuiButton]: () -> () },
		last = {} :: { [GuiButton]: number },
		-- A is down (and a moment after its release) since the A action pressed a button: an
		-- engine press now is that same press, or one on the button the press moved the selection
		-- to (a tab's first Buy), and is skipped. `release` names the latest release's timer.
		padHeld = false,
		release = 0,
		-- When any of the screen's buttons last fired: an A press that the engine already turned
		-- into a press (it may run first) presses nothing more.
		lastAny = -math.huge,
	}
	local function fire(button: GuiButton): ()
		local handler = router.handlers[button]
		if handler == nil or not button.Visible then
			return
		end
		local now = os.clock()
		local last = router.last[button]
		if last ~= nil and now - last < Theme.ACTION_DEBOUNCE_SECONDS then
			return
		end
		router.last[button] = now
		router.lastAny = now
		handler()
	end
	local function bind(button: GuiButton, handler: () -> ()): () -> ()
		router.handlers[button] = handler
		local connection = button.Activated:Connect(function()
			if not router.padHeld then
				fire(button)
			end
		end)
		return function()
			connection:Disconnect()
			router.handlers[button] = nil
			router.last[button] = nil
		end
	end

	-- The scrim closes the screen on a tap that misses the frame, and takes it: nothing under
	-- an open screen is played through it.
	local root = Create("TextButton", {
		Name = "ArmoryScreen",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = Theme.ARMORY_SCREEN_SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		Selectable = false,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: TextButton
	local frame = Create("Frame", {
		Name = "Screen",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
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
	rounded(frame, Theme.CORNER_RADIUS)
	local uiScale = Create("UIScale", { Parent = frame }) :: UIScale
	local padding = Theme.ARMORY_SCREEN_PADDING

	-- Header: the tabs, the wallet over the key line, the close button.
	local header = {
		tabs = {} :: { [string]: TextButton },
		unbinds = {} :: { () -> () },
	}
	local showTab: (tab: Tab) -> ()
	local setOpen: (open: boolean) -> ()
	for index, tab in TAB_ORDER do
		local button = Create("TextButton", {
			Name = "Tab_" .. tab,
			Position = UDim2.fromOffset(
				padding + (index - 1) * (Theme.ARMORY_SCREEN_TAB_WIDTH + Theme.ARMORY_SCREEN_GAP),
				padding
			),
			Size = UDim2.fromOffset(
				Theme.ARMORY_SCREEN_TAB_WIDTH,
				Theme.ARMORY_SCREEN_HEADER_HEIGHT
			),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			Text = TAB_TEXTS[tab],
			ZIndex = Theme.ZINDEX_CARD,
			Parent = frame,
		}) :: TextButton
		rounded(button, Theme.CORNER_RADIUS)
		header.tabs[tab] = button
		table.insert(
			header.unbinds,
			bind(button, function()
				showTab(tab)
			end)
		)
	end
	local close = Create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -padding, 0, padding),
		Size = UDim2.fromOffset(
			Theme.ARMORY_SCREEN_HEADER_HEIGHT,
			Theme.ARMORY_SCREEN_HEADER_HEIGHT
		),
		BackgroundColor3 = Theme.MAP_COLOR_PANEL_LIGHT,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.MAP_COLOR_TEXT,
		Text = CLOSE_GLYPH,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = frame,
	}) :: TextButton
	rounded(close, Theme.CORNER_RADIUS)
	table.insert(
		header.unbinds,
		bind(close, function()
			setOpen(false)
		end)
	)
	local tabsWidth = #TAB_ORDER * Theme.ARMORY_SCREEN_TAB_WIDTH
		+ (#TAB_ORDER - 1) * Theme.ARMORY_SCREEN_GAP
	local walletLeft = padding + tabsWidth + Theme.ARMORY_SCREEN_GAP
	local walletRight = padding + Theme.ARMORY_SCREEN_HEADER_HEIGHT + Theme.ARMORY_SCREEN_GAP
	local hintText = deps.keyHint
	local hintHeight = if hintText ~= nil then Theme.ARMORY_SCREEN_HINT_HEIGHT else 0
	local wallet = Create("TextLabel", {
		Name = "Wallet",
		Active = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(walletLeft, padding),
		Size = UDim2.new(
			1,
			-(walletLeft + walletRight),
			0,
			Theme.ARMORY_SCREEN_HEADER_HEIGHT - hintHeight
		),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.ARMORY_SCREEN_WALLET_TEXT,
		TextColor3 = Theme.MAP_COLOR_GOLD,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = true,
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = frame,
	}) :: TextLabel
	if hintText ~= nil then
		Create("TextLabel", {
			Name = "Keys",
			Active = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(
				walletLeft,
				padding + Theme.ARMORY_SCREEN_HEADER_HEIGHT - hintHeight
			),
			Size = UDim2.new(1, -(walletLeft + walletRight), 0, hintHeight),
			Font = Theme.FONT,
			TextSize = Theme.ARMORY_SCREEN_HINT_TEXT,
			TextColor3 = Theme.MAP_COLOR_DIM,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = hintText,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = frame,
		})
	end

	-- The two pages, each in its own holder under the header.
	local pageTop = padding + Theme.ARMORY_SCREEN_HEADER_HEIGHT + Theme.ARMORY_SCREEN_GAP
	local function holder(name: string): Frame
		return Create("Frame", {
			Name = name,
			Active = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(padding, pageTop),
			Visible = false,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = frame,
		}) :: Frame
	end
	local holders: { [string]: Frame } =
		{ weapons = holder("WeaponsPage"), abilities = holder("AbilitiesHolder") }

	local paint: () -> ()
	local function inputs(): ArmoryModel.Inputs
		local held = view.held
		local picked = view.picked
		if picked ~= nil then
			local base = held
				or Unlocks.LoadoutOf(
					view.combat,
					configs.weapons,
					configs.loadout or { melee = "", ranged = "" }
				)
			local variants = table.clone(base.variants)
			variants[picked.family] = picked.variant
			held = {
				melee = if picked.slot == "melee" then picked.family else base.melee,
				ranged = if picked.slot == "ranged" then picked.family else base.ranged,
				variants = variants,
			}
		end
		local upgrade = view.upgrade
		local equip = view.equip
		return {
			armory = configs.armory,
			weapons = configs.weapons,
			loadout = configs.loadout,
			expeditions = configs.expeditions,
			levels = configs.levels,
			built = configs.built,
			combat = view.combat,
			held = held,
			gateOpen = view.gate,
			pending = {
				upgrade = if upgrade ~= nil then upgrade.family else nil,
				equipFamily = if equip ~= nil then equip.family else nil,
				equipVariant = if equip ~= nil then equip.variant else nil,
			},
		}
	end

	-- A press waits for its answer, at most ARMORY_SCREEN_RESULT_TIMEOUT_SECONDS (the entry is
	-- the wait's name: a timer of an older press frees nothing).
	local function awaitAnswer(kind: "upgrade" | "equip", entry: Waiting): ()
		if kind == "upgrade" then
			view.upgrade = entry
		else
			view.equip = entry
		end
		task.delay(Theme.ARMORY_SCREEN_RESULT_TIMEOUT_SECONDS, function()
			if kind == "upgrade" and view.upgrade == entry then
				view.upgrade = nil
				paint()
			elseif kind == "equip" and view.equip == entry then
				view.equip = nil
				paint()
			end
		end)
	end

	local function familySlot(family: string): string
		local def = configs.weapons[family]
		return if def ~= nil then def.slot else ""
	end

	local stage = ArmoryStage.new(holders.weapons)
	local detail = ArmoryDetail.new(holders.weapons, {
		bind = bind,
		onUpgrade = function(family: string)
			if not (view.open and view.available) or view.upgrade ~= nil then
				return
			end
			local shown = ArmoryModel.Detail(inputs(), family)
			if shown == nil or not shown.upgrade.live then
				return
			end
			if not deps.onUpgrade(family) then
				deps.toast(ArmoryModel.TEXT.retry, Theme.ARMORY_SCREEN_TOAST_SECONDS, true)
				return
			end
			awaitAnswer("upgrade", {
				family = family,
				slot = familySlot(family),
				variant = "",
				tier = shown.nextTier,
				answered = false,
			})
			paint()
		end,
		onEquip = function(family: string, variant: string)
			if not (view.open and view.available) or view.equip ~= nil then
				return
			end
			local slot = familySlot(family)
			if not deps.onEquip(slot, family, variant) then
				deps.toast(ArmoryModel.TEXT.retry, Theme.ARMORY_SCREEN_TOAST_SECONDS, true)
				return
			end
			awaitAnswer(
				"equip",
				{ family = family, slot = slot, variant = variant, answered = false }
			)
			paint()
		end,
	})
	local shelf = ArmoryShelf.new(holders.weapons, {
		bind = bind,
		onSelect = function(family: string)
			if view.selected ~= family then
				view.selected = family
				paint()
			end
		end,
	})
	local abilities =
		ArmoryAbilityPage.new(holders.abilities, ArmoryAbilityPage.Offers(configs.expeditions), {
			onBuy = deps.onBuyAbility,
			toast = deps.toast,
			isLive = function(): boolean
				return view.open and view.available
			end,
			bind = bind,
		})
	abilities.frame.AnchorPoint = Vector2.new(0.5, 0)
	abilities.frame.Position = UDim2.fromScale(0.5, 0)

	local function currentTab(): Tab
		return view.tab or "weapons"
	end

	-- Where a gamepad's selection starts on the tab on show.
	local function firstSelection(): GuiObject
		local tab = currentTab()
		if tab == "abilities" then
			return abilities.FirstSelection() or header.tabs[tab]
		end
		local selected = view.selected
		local card = if selected ~= nil then shelf.ButtonOf(selected) else nil
		return card or detail.FirstSelection() or header.tabs[tab]
	end

	-- A press in flight, a button gone unselectable or a rebuilt shelf can leave a gamepad's
	-- selection on nothing (the stick would then walk the character behind the scrim): while the
	-- screen is open and the pad was the last input, it goes back to the tab's first selection.
	local function reselect(): ()
		if not view.open or not padLast() then
			return
		end
		local selected = GuiService.SelectedObject
		if
			selected ~= nil
			and selected.Selectable
			and selected.Visible
			and selected:IsDescendantOf(frame)
		then
			return
		end
		GuiService.SelectedObject = firstSelection()
	end

	local function layout(): ()
		local scale = view.scale
		if scale <= 0 then
			return
		end
		local margin = Theme.SCREEN_MARGIN * 2
		local availableWidth = view.size.X / scale - margin
		local availableHeight = view.size.Y / scale - margin
		local portrait = availableWidth < availableHeight
		local width = math.floor(math.min(availableWidth, Theme.ARMORY_SCREEN_MAX_WIDTH))
		local height = math.floor(
			math.min(
				availableHeight,
				if portrait
					then Theme.ARMORY_SCREEN_PORTRAIT_MAX_HEIGHT
					else Theme.ARMORY_SCREEN_MAX_HEIGHT
			)
		)
		uiScale.Scale = scale
		frame.Size = UDim2.fromOffset(width, height)
		local inner = width - padding * 2
		local pageHeight = height - pageTop - padding
		for _, box in holders do
			box.Size = UDim2.fromOffset(inner, pageHeight)
		end
		abilities.SetSize(inner, pageHeight)
		shelf.SetLayout(portrait, inner)
		local shelfHeight = shelf.Height()
		local gap = Theme.ARMORY_SCREEN_GAP
		if portrait then
			local detailHeight = ArmoryDetail.Height()
			local stageHeight = math.max(
				Theme.ARMORY_SCREEN_STAGE_PORTRAIT_MIN_HEIGHT,
				pageHeight - detailHeight - shelfHeight - gap * 2
			)
			stage.frame.Position = UDim2.fromOffset(0, 0)
			stage.SetSize(inner, stageHeight)
			detail.frame.Position = UDim2.fromOffset(0, stageHeight + gap)
			detail.SetSize(inner, detailHeight)
			shelf.frame.Position = UDim2.fromOffset(0, stageHeight + gap + detailHeight + gap)
		else
			local middle = math.max(pageHeight - gap - shelfHeight, ArmoryDetail.Height())
			local stageWidth = math.max(
				Theme.ARMORY_SCREEN_STAGE_MIN_WIDTH,
				math.floor(inner * Theme.ARMORY_SCREEN_STAGE_SHARE)
			)
			stage.frame.Position = UDim2.fromOffset(0, 0)
			stage.SetSize(stageWidth, middle)
			detail.frame.Position = UDim2.fromOffset(stageWidth + gap, 0)
			detail.SetSize(inner - stageWidth - gap, middle)
			shelf.frame.Position = UDim2.fromOffset(0, middle + gap)
		end
		shelf.frame.Size = UDim2.fromOffset(inner, shelfHeight)
	end

	paint = function(): ()
		if view.destroyed then
			return
		end
		-- A closed screen paints on its next open.
		if not view.open then
			return
		end
		local model = inputs()
		local cards = ArmoryModel.Shelf(model)
		local selected = view.selected
		local known = false
		for _, card in cards do
			if card.family == selected then
				known = true
			end
		end
		if not known then
			selected = ArmoryModel.DefaultFamily(model, cards)
			view.selected = selected
		end
		shelf.Show(cards, selected)
		local shown = if selected ~= nil then ArmoryModel.Detail(model, selected) else nil
		stage.Show(if shown ~= nil then shown.card else nil)
		detail.Show(shown)
		wallet.Text = ArmoryModel.Wallet(model)
		if #cards ~= view.cards then
			view.cards = #cards
			layout()
		end
		reselect()
	end

	local function paintTabs(): ()
		local shown = currentTab()
		for tab, button in header.tabs do
			local on = tab == shown
			button.BackgroundColor3 = if on
				then Theme.MAP_COLOR_GOLD
				else Theme.MAP_COLOR_PANEL_LIGHT
			button.TextColor3 = if on then Theme.MAP_COLOR_INK else Theme.MAP_COLOR_TEXT
			holders[tab].Visible = on
		end
		abilities.frame.Visible = shown == "abilities"
	end

	showTab = function(tab: Tab): ()
		view.tab = tab
		paintTabs()
		paint()
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
			showTab(TAB_ORDER[(index - 1 + step) % #TAB_ORDER + 1])
		end
		return Enum.ContextActionResult.Sink
	end

	-- Gamepad A while open: sunk (no jump, no walk behind the scrim), and it presses the
	-- selected button itself; the engine's own presses while A is down are skipped.
	local function onPadPress(
		_action: string,
		state: Enum.UserInputState,
		_input: InputObject
	): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			local selected = GuiService.SelectedObject
			router.padHeld = true
			router.release += 1
			local engineFirst = os.clock() - router.lastAny < Theme.ACTION_DEBOUNCE_SECONDS
			if
				not engineFirst
				and selected ~= nil
				and selected:IsA("GuiButton")
				and selected:IsDescendantOf(frame)
			then
				fire(selected :: GuiButton)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			router.release += 1
			local release = router.release
			-- The engine may press on release: keep skipping a moment after.
			task.delay(Theme.ACTION_DEBOUNCE_SECONDS, function()
				if router.release == release then
					router.padHeld = false
				end
			end)
		end
		return Enum.ContextActionResult.Sink
	end

	local function bindOpenKeys(bound: boolean): ()
		if bound then
			ContextActionService:BindActionAtPriority(
				ACTIONS.close,
				onPadClose,
				false,
				PAD_PRIORITY,
				Enum.KeyCode.ButtonB
			)
			local tabKeys: { Enum.KeyCode } = {}
			for key in PAD_TAB_KEYS do
				table.insert(tabKeys, key)
			end
			ContextActionService:BindActionAtPriority(
				ACTIONS.tabs,
				onPadTab,
				false,
				PAD_PRIORITY,
				table.unpack(tabKeys)
			)
			ContextActionService:BindActionAtPriority(
				ACTIONS.press,
				onPadPress,
				false,
				PAD_PRIORITY,
				Enum.KeyCode.ButtonA
			)
		else
			ContextActionService:UnbindAction(ACTIONS.close)
			ContextActionService:UnbindAction(ACTIONS.tabs)
			ContextActionService:UnbindAction(ACTIONS.press)
			router.padHeld = false
			router.release += 1
		end
	end

	setOpen = function(open: boolean): ()
		if open and (not view.available or view.destroyed) then
			return
		end
		if open == view.open then
			return
		end
		view.open = open
		root.Visible = open
		if open then
			configs = readConfigs()
			if view.tab == nil then
				view.tab = if abilities.HasLiveBuy() then "abilities" else "weapons"
			end
			paintTabs()
			paint()
			layout()
			bindOpenKeys(true)
			if padLast() then
				GuiService.SelectedObject = firstSelection()
			end
		else
			bindOpenKeys(false)
			local selected = GuiService.SelectedObject
			if selected ~= nil and selected:IsDescendantOf(root) then
				GuiService.SelectedObject = nil
			end
		end
		deps.onOpenChanged(open)
	end

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
		if not deps.padToggle or bound == view.padBound then
			return
		end
		view.padBound = bound
		if bound then
			ContextActionService:BindActionAtPriority(
				ACTIONS.toggle,
				onPadToggle,
				false,
				PAD_PRIORITY,
				Enum.KeyCode.ButtonY
			)
		else
			ContextActionService:UnbindAction(ACTIONS.toggle)
		end
	end

	table.insert(
		connections,
		root.Activated:Connect(function()
			setOpen(false)
		end)
	)
	-- Esc: Roblox's menu takes the key itself, so the press is watched whether or not it was
	-- processed, and the menu opening closes the screen as well.
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

	-- An answer to the upgrade in flight, once the Snapshot shows its tier, frees its button.
	local function settleUpgrade(): ()
		local waiting = view.upgrade
		local combat = view.combat
		local armory = configs.armory
		if waiting == nil or not waiting.answered or combat == nil or armory == nil then
			return
		end
		local tier = waiting.tier
		if tier == nil or Armory.TierOf(armory, combat, waiting.family) >= tier then
			view.upgrade = nil
		end
	end

	local function onWeaponResult(result: Types.ActionResult, action: string): ()
		local family = result.slotId
		local model = inputs()
		local waiting = if action == "upgradeWeapon" then view.upgrade else view.equip
		local answers = waiting ~= nil and waiting.family == family
		if result.ok then
			local tier = if answers and waiting ~= nil then waiting.tier else nil
			deps.toast(
				ArmoryModel.OkText(model, action, family, tier),
				Theme.ARMORY_SCREEN_TOAST_SECONDS,
				false
			)
			if answers and waiting ~= nil then
				if action == "upgradeWeapon" then
					waiting.answered = true
					settleUpgrade()
				else
					view.picked = waiting
					view.equip = nil
				end
			end
		else
			local reason: string? = result.reason
			if answers then
				if action == "upgradeWeapon" then
					view.upgrade = nil
				else
					view.equip = nil
				end
			end
			deps.toast(
				ArmoryModel.RefusalText(inputs(), action, family, reason),
				Theme.ARMORY_SCREEN_TOAST_SECONDS,
				true
			)
		end
		paint()
	end

	local function teardown(): ()
		if view.destroyed then
			return
		end
		setOpen(false)
		bindPadToggle(false)
		view.destroyed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, unbind in header.unbinds do
			unbind()
		end
		table.clear(header.unbinds)
		stage.Destroy()
		detail.Destroy()
		shelf.Destroy()
		abilities.Destroy()
	end
	table.insert(connections, root.Destroying:Connect(teardown))

	paintTabs()

	local handle: Handle = {
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
		SetAvailable = function(available: boolean)
			view.available = available
			bindPadToggle(available)
			if not available then
				setOpen(false)
			end
		end,
		SetGate = function(open: boolean)
			if view.gate ~= open then
				view.gate = open
				paint()
			end
		end,
		SetState = function(combat: Types.CombatProfile)
			view.combat = combat
			abilities.SetState(combat.valor, combat.abilities)
			settleUpgrade()
			paint()
		end,
		SetHeld = function(loadout: Types.RangeLoadout)
			view.held = loadout
			-- The host's word replaces the pick it confirmed.
			view.picked = nil
			paint()
		end,
		OnResult = function(result: Types.ActionResult)
			if typeof(result) ~= "table" then
				return
			end
			local action: string = result.action
			if action == "buyAbility" then
				abilities.OnResult(result)
				reselect()
			elseif action == "upgradeWeapon" or action == "setFamily" then
				onWeaponResult(result, action)
			end
		end,
		SetLayout = function(scale: number, size: Vector2)
			if scale <= 0 then
				return
			end
			view.scale = scale
			view.size = size
			layout()
		end,
		Destroy = function()
			teardown()
			root:Destroy()
		end,
	}
	return handle
end

return ArmoryScreen
