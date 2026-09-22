--!strict
-- Armory panel (C0 contract, docs/INTERFACES.md "Hub client"): weapons only, two permanent
-- slots. A pinned header shows the Max HP the two weapons grant and one wallet chip per
-- material band, then one row per slot with the current weapon, its damage and HP, and the
-- next tier's line "Tier 4 · 20 Steel · unlocks at 1K/s (you: 620/s)". The Ascend rows
-- appear only once Rebirth has unlocked them.
--
-- Every number here is server state or a read-only call into the shared pure Armory module
-- the server validates with: the panel uses Armory.CanBuy / CanAscend to COLOUR a button,
-- never to decide an entitlement. A tap fires RequestBuyGear(slot) / RequestAscend(slot)
-- with no amount; the server subtracts the materials and the next delta carries the new
-- combat profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local PanelDock = require(script.Parent:WaitForChild("PanelDock"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Slot = "melee" | "ranged"

export type Deps = {
	armoryConfig: Types.ArmoryConfig,
	onBuy: (slot: Slot) -> (),
	onAscend: (slot: Slot) -> (),
	onClose: () -> (),
}

export type ArmoryPanelHandle = {
	DesignHeight: number,
	Refresh: (state: Types.PlayerState, persistedIncomePerSecond: number) -> (),
	FlashSlot: (slot: Slot) -> (),
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

type SlotRow = {
	slot: Slot,
	frame: Frame,
	nameLabel: TextLabel,
	statLabel: TextLabel,
	nextLabel: TextLabel,
	button: TextButton,
	buttonTitle: TextLabel,
	buttonCost: TextLabel,
	stroke: UIStroke,
	enabled: boolean,
	flashUntil: number,
	ascendFrame: Frame,
	ascendNameLabel: TextLabel,
	ascendCostLabel: TextLabel,
	ascendButton: TextButton,
	ascendButtonTitle: TextLabel,
	ascendEnabled: boolean,
}

type Chip = { material: string, valueLabel: TextLabel }

local SLOTS: { { slot: Slot, label: string } } = {
	{ slot = "melee", label = "Melee" },
	{ slot = "ranged", label = "Ranged" },
}

local BLANK = "—"

local ArmoryPanel = {}

function ArmoryPanel.new(parent: Instance, deps: Deps): ArmoryPanelHandle
	local connections: { RBXScriptConnection } = {}
	local rows: { [string]: SlotRow } = {}
	local chips: { Chip } = {}
	local lastState: Types.PlayerState? = nil
	local lastRate = 0
	local lastActionTime = 0
	local cfg = deps.armoryConfig
	local ascension = cfg.ascension

	local panel = Panel.new(parent, {
		name = "ArmoryPanel",
		title = "Armory",
		designHeight = Theme.PANEL_HEIGHT,
		onClose = deps.onClose,
	})

	-- Pinned header: Max HP (what weapons are FOR) plus the wallet, so a red Buy always has
	-- its reason on screen no matter how far the list is scrolled.
	local headerHeight = Theme.ARMORY_MAX_HP_HEIGHT
		+ Theme.ARMORY_CHIP_GAP
		+ Theme.ARMORY_CHIP_HEIGHT
	local maxHpLabel = Create("TextLabel", {
		Name = "MaxHp",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.ARMORY_MAX_HP_HEIGHT),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Max HP " .. BLANK,
		Parent = panel.Content,
	}) :: TextLabel

	local wallet = Create("Frame", {
		Name = "Wallet",
		Position = UDim2.fromOffset(0, Theme.ARMORY_MAX_HP_HEIGHT + Theme.ARMORY_CHIP_GAP),
		Size = UDim2.new(1, 0, 0, Theme.ARMORY_CHIP_HEIGHT),
		BackgroundTransparency = 1,
		Parent = panel.Content,
	}) :: Frame
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.ARMORY_CHIP_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wallet,
	})

	-- One chip per band, in band order, so the wallet reads the same whatever the era.
	local bandCount = math.max(#cfg.bands, 1)
	for index, band in cfg.bands do
		local chip = Create("Frame", {
			Name = band.material,
			LayoutOrder = index,
			-- Scale width: in landscape the dock may clamp the sheet to PANEL_MIN_WIDTH.
			Size = UDim2.new(1 / bandCount, -Theme.ARMORY_CHIP_GAP, 0, Theme.ARMORY_CHIP_HEIGHT),
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Parent = wallet,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = chip })
		local nameLabel = Create("TextLabel", {
			Name = "Material",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, 2),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			Text = band.material,
			Parent = chip,
		}) :: TextLabel
		Create("UITextSizeConstraint", {
			MinTextSize = Theme.ARMORY_CHIP_MIN_TEXT,
			MaxTextSize = Theme.TEXT_SMALL,
			Parent = nameLabel,
		})
		local valueLabel = Create("TextLabel", {
			Name = "Amount",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, Theme.ARMORY_CHIP_VALUE_Y),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.ROW_NAME_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			Text = "0",
			Parent = chip,
		}) :: TextLabel
		Create("UITextSizeConstraint", {
			MinTextSize = Theme.ARMORY_CHIP_MIN_TEXT,
			MaxTextSize = Theme.TEXT_MEDIUM,
			Parent = valueLabel,
		})
		table.insert(chips, { material = band.material, valueLabel = valueLabel })
	end

	local scrollTop = headerHeight + Theme.ARMORY_HEADER_GAP
	local scroll = Create("ScrollingFrame", {
		Name = "Slots",
		Position = UDim2.fromOffset(0, scrollTop),
		Size = UDim2.new(1, 0, 1, -scrollTop),
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

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
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

	local function makeActionButton(
		parentFrame: Frame,
		title: string
	): (TextButton, TextLabel, TextLabel)
		local button = Create("TextButton", {
			Name = "Action",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.ROW_NAME_Y),
			Size = UDim2.fromOffset(Theme.ROW_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Text = "",
			Parent = parentFrame,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		local titleLabel = Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, Theme.BUTTON_TITLE_Y),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.BUTTON_TITLE_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = title,
			Parent = button,
		}) :: TextLabel
		local costLabel = Create("TextLabel", {
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
		return button, titleLabel, costLabel
	end

	local function makeRowFrame(name: string): Frame
		local frame = Create("Frame", {
			Name = name,
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, 0),
			-- Height follows the wrapped line under the button, exactly as Shop rows do, so
			-- the long unlock sentence can never be clipped on a 340 px sheet.
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Parent = scroll,
		}) :: Frame
		Create("UIPadding", {
			PaddingBottom = UDim.new(0, Theme.ARMORY_ROW_PAD_BOTTOM),
			Parent = frame,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
		return frame
	end

	local function makeLine(
		frame: Frame,
		name: string,
		y: number,
		font: Enum.Font,
		size: number,
		color: Color3,
		beside: boolean
	): TextLabel
		local width = if beside
			then -Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP
			else -Theme.ROW_TEXT_LEFT * 2
		return Create("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, y),
			Size = UDim2.new(1, width, 0, if beside then Theme.ROW_LINE_HEIGHT else 0),
			AutomaticSize = if beside then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
			Font = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = not beside,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTruncate = if beside then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,
			Text = "",
			Parent = frame,
		}) :: TextLabel
	end

	for _, entry in SLOTS do
		local frame = makeRowFrame(entry.slot)
		local stroke = Create("UIStroke", {
			Color = Theme.COLOR_ERROR,
			Thickness = Theme.STROKE_THICKNESS,
			Enabled = false,
			Parent = frame,
		}) :: UIStroke
		local nameLabel = makeLine(
			frame,
			"Name",
			Theme.ROW_NAME_Y,
			Theme.FONT_BOLD,
			Theme.TEXT_MEDIUM,
			Theme.COLOR_TEXT,
			true
		)
		nameLabel.Size = UDim2.new(
			1,
			-Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP,
			0,
			Theme.ROW_NAME_HEIGHT
		)
		local statLabel = makeLine(
			frame,
			"Stats",
			Theme.ARMORY_STAT_Y,
			Theme.FONT,
			Theme.TEXT_SMALL,
			Theme.COLOR_ACCENT,
			true
		)
		local nextLabel = makeLine(
			frame,
			"NextTier",
			Theme.ARMORY_NEXT_Y,
			Theme.FONT,
			Theme.TEXT_SMALL,
			Theme.COLOR_TEXT_DIM,
			false
		)
		local button, buttonTitle, buttonCost = makeActionButton(frame, "Buy")

		-- Ascend is its own row: it spends all four materials plus Valor, which is a
		-- different decision from buying the next tier, and it only exists after a Rebirth.
		local ascendFrame = makeRowFrame(entry.slot .. "Ascend")
		ascendFrame.Visible = false
		local ascendNameLabel = makeLine(
			ascendFrame,
			"Name",
			Theme.ROW_NAME_Y,
			Theme.FONT_BOLD,
			Theme.TEXT_MEDIUM,
			Theme.COLOR_HIGHLIGHT,
			true
		)
		ascendNameLabel.Size = UDim2.new(
			1,
			-Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP,
			0,
			Theme.ROW_NAME_HEIGHT
		)
		local ascendCostLabel = makeLine(
			ascendFrame,
			"Cost",
			Theme.ARMORY_STAT_Y,
			Theme.FONT,
			Theme.TEXT_SMALL,
			Theme.COLOR_TEXT_DIM,
			false
		)
		local ascendButton, ascendTitle, ascendCost = makeActionButton(ascendFrame, "Ascend")
		ascendCost.Visible = false
		ascendTitle.Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, 0)
		ascendTitle.Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 1, 0)

		local row: SlotRow = {
			slot = entry.slot,
			frame = frame,
			nameLabel = nameLabel,
			statLabel = statLabel,
			nextLabel = nextLabel,
			button = button,
			buttonTitle = buttonTitle,
			buttonCost = buttonCost,
			stroke = stroke,
			enabled = false,
			flashUntil = 0,
			ascendFrame = ascendFrame,
			ascendNameLabel = ascendNameLabel,
			ascendCostLabel = ascendCostLabel,
			ascendButton = ascendButton,
			ascendButtonTitle = ascendTitle,
			ascendEnabled = false,
		}
		rows[entry.slot] = row

		table.insert(
			connections,
			button.Activated:Connect(function()
				-- A disabled Buy is a status, not an offer: the reason is already on the row,
				-- so a server round-trip that can only fail is not worth the rate limit.
				if not row.enabled then
					return
				end
				tryAction(function()
					deps.onBuy(entry.slot)
				end)
			end)
		)
		table.insert(
			connections,
			ascendButton.Activated:Connect(function()
				if not row.ascendEnabled then
					return
				end
				tryAction(function()
					deps.onAscend(entry.slot)
				end)
			end)
		)
	end

	local function materialAmount(combat: Types.CombatProfile, material: string): number
		local amount = combat.materials[material]
		return if typeof(amount) == "number" then amount else 0
	end

	local function paintActionButton(
		button: TextButton,
		title: TextLabel,
		cost: TextLabel,
		enabled: boolean,
		reason: string?
	): ()
		button.Active = enabled
		button.AutoButtonColor = enabled
		button.BackgroundColor3 = if enabled then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT
		button.BackgroundTransparency = if enabled then 0 else Theme.DIM_TRANSPARENCY
		title.TextColor3 = if enabled then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT_DIM
		-- The reason lives in the colour as well as the words: amber = the city is not
		-- earning enough yet, red = the materials are short (C0 contract).
		cost.TextColor3 = if enabled
			then Theme.COLOR_TEXT_DARK
			elseif reason == "locked" then Theme.COLOR_HIGHLIGHT
			elseif reason == "insufficientFunds" then Theme.COLOR_ERROR
			else Theme.COLOR_TEXT_DIM
	end

	local function paintRow(row: SlotRow, state: Types.PlayerState, rate: number): ()
		local combat = state.combat
		local slotLabel = if row.slot == "melee" then "Melee" else "Ranged"
		local gear = combat.gear
		local ascLevel = combat.ascension[row.slot]
		local tier = gear[row.slot]
		-- TierDef is optional on purpose: a profile can hold a tier a shrunk Armory.json no
		-- longer defines, and the panel must say so instead of erroring.
		local tierDef = Armory.TierDef(cfg, row.slot, tier)
		local damage = Armory.WeaponDamage(cfg, row.slot, tier, ascLevel)
		local hp = Armory.WeaponHp(cfg, row.slot, tier, ascLevel)

		row.nameLabel.Text = slotLabel
			.. " · "
			.. (if tierDef ~= nil then tierDef.name else BLANK)
			.. (if tier > 0 then " · Tier " .. tostring(tier) else " · Starter")
		row.statLabel.Text = Format.Cash(damage)
			.. " dmg · +"
			.. Format.Cash(hp)
			.. " HP"
			.. (if ascLevel > 0 then " · Ascension " .. tostring(ascLevel) else "")

		local nextTier = Armory.NextTier(cfg, gear, row.slot)
		if nextTier == nil then
			row.enabled = false
			row.nextLabel.Text = "Fully upgraded"
			row.nextLabel.TextColor3 = Theme.COLOR_TEXT_DIM
			row.buttonTitle.Text = "Maxed"
			row.buttonCost.Text = ""
			paintActionButton(row.button, row.buttonTitle, row.buttonCost, false, nil)
		else
			local material, amount = Armory.TierCost(cfg, row.slot, nextTier)
			local unlockRate = Armory.TierUnlockRate(cfg, row.slot, nextTier)
			local ok, reason = Armory.CanBuy(cfg, state, row.slot, rate)
			local line = "Tier "
				.. tostring(nextTier)
				.. " · "
				.. Format.Cash(amount)
				.. " "
				.. material
			if unlockRate > 0 then
				-- "you:" is the city's PERSISTED income/s — the rate the server gates on,
				-- never the reported one (it carries neighbours and the Studio multiplier).
				local need = Format.Rate(unlockRate)
				local have = Format.Rate(rate)
				line ..= " · unlocks at " .. need .. "/s (you: " .. have .. "/s)"
			end
			row.enabled = ok
			row.nextLabel.Text = line
			row.nextLabel.TextColor3 = if ok
				then Theme.COLOR_ACCENT
				elseif reason == "locked" then Theme.COLOR_HIGHLIGHT
				elseif reason == "insufficientFunds" then Theme.COLOR_ERROR
				else Theme.COLOR_TEXT_DIM
			row.buttonTitle.Text = if reason == "locked" then "Locked" else "Buy"
			row.buttonCost.Text = Format.Cash(amount) .. " " .. material
			paintActionButton(row.button, row.buttonTitle, row.buttonCost, ok, reason)
		end

		-- Keep an active failure flash visible across refreshes until it expires.
		row.stroke.Enabled = os.clock() < row.flashUntil

		local cap = Armory.AscensionCap(cfg, state.rebirthCount)
		local visible = state.rebirthCount >= ascension.requiresRebirth
		row.ascendFrame.Visible = visible
		if not visible then
			row.ascendEnabled = false
			return
		end
		row.ascendNameLabel.Text = "Ascend "
			.. slotLabel
			.. " · Lv "
			.. tostring(ascLevel)
			.. "/"
			.. tostring(cap)
		local nextLevel = ascLevel + 1
		local levelCost = Armory.AscensionCost(cfg, nextLevel)
		if levelCost == nil then
			row.ascendEnabled = false
			row.ascendCostLabel.Text = "Fully ascended"
			row.ascendCostLabel.TextColor3 = Theme.COLOR_TEXT_DIM
			row.ascendButtonTitle.Text = "Maxed"
			paintActionButton(
				row.ascendButton,
				row.ascendButtonTitle,
				row.ascendCostLabel,
				false,
				nil
			)
			return
		end
		local parts: { string } = {}
		-- Band order, not table order: a dictionary's iteration order is not stable and the
		-- cost line must read the same on every refresh.
		for _, band in cfg.bands do
			local need = levelCost.materials[band.material]
			if typeof(need) == "number" and need > 0 then
				table.insert(
					parts,
					Format.Cash(need)
						.. " "
						.. band.material
						.. " ("
						.. Format.Cash(materialAmount(combat, band.material))
						.. ")"
				)
			end
		end
		table.insert(
			parts,
			Format.Cash(levelCost.valor) .. " Valor (" .. Format.Cash(combat.valor) .. ")"
		)
		local ascendOk, ascendReason = Armory.CanAscend(cfg, state, row.slot)
		row.ascendEnabled = ascendOk
		row.ascendCostLabel.Text = table.concat(parts, " · ")
		row.ascendCostLabel.TextColor3 = if ascendOk
			then Theme.COLOR_ACCENT
			elseif ascendReason == "locked" then Theme.COLOR_HIGHLIGHT
			elseif ascendReason == "insufficientFunds" then Theme.COLOR_ERROR
			else Theme.COLOR_TEXT_DIM
		row.ascendButtonTitle.Text = if ascendOk then "Ascend" else "Locked"
		paintActionButton(
			row.ascendButton,
			row.ascendButtonTitle,
			row.ascendCostLabel,
			ascendOk,
			ascendReason
		)
	end

	local function refresh(state: Types.PlayerState, persistedIncomePerSecond: number): ()
		lastState = state
		lastRate = persistedIncomePerSecond
		local combat = state.combat
		if combat == nil then
			-- A server that predates the combat profile: show nothing rather than zeros a
			-- player could mistake for their real wallet.
			maxHpLabel.Text = "Max HP " .. BLANK
			for _, chip in chips do
				chip.valueLabel.Text = BLANK
			end
			for _, row in rows do
				row.enabled = false
				row.ascendEnabled = false
				row.ascendFrame.Visible = false
			end
			return
		end
		local maxHpText = "Max HP " .. Format.Cash(Armory.MaxHp(cfg, combat.gear, combat.ascension))
		if state.rebirthCount >= ascension.requiresRebirth then
			maxHpText ..= " · Valor " .. Format.Cash(combat.valor)
		end
		maxHpLabel.Text = maxHpText
		for _, chip in chips do
			chip.valueLabel.Text = Format.Cash(materialAmount(combat, chip.material))
		end
		for _, entry in SLOTS do
			paintRow(rows[entry.slot], state, persistedIncomePerSecond)
		end
	end

	local function flashSlot(slot: Slot): ()
		local row = rows[slot]
		if row == nil then
			return
		end
		row.flashUntil = os.clock() + Theme.FLASH_SECONDS
		row.stroke.Enabled = true
		task.delay(Theme.FLASH_SECONDS, function()
			local state = lastState
			if state ~= nil then
				refresh(state, lastRate) -- restores true colours once the flash window passed
			end
		end)
	end

	local handle: ArmoryPanelHandle = {
		DesignHeight = panel.DesignHeight,
		Refresh = refresh,
		FlashSlot = flashSlot,
		SetOpen = panel.SetOpen,
		IsOpen = panel.IsOpen,
		SetLayout = panel.SetLayout,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			panel.Destroy()
		end,
	}
	return handle
end

return ArmoryPanel
