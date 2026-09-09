--!strict
-- Legacy panel. Since M6 it is also the Legacy shop (docs/INTERFACES.md "Client contracts
-- (M6)", docs/LEGACY_SHOP.md): a header with the Legacy total, the spendable balance
-- (Legacy earned minus Legacy invested), the multiplier breakdown row
-- `Legacy ×a · Perks ×b · Passes ×c` and the softcap note, then one row per perk in
-- config order and the cosmetics below them with the same row shape. A row's Buy button
-- fires RequestBuyPerk(perkId) and nothing else: the server validates tier order and
-- the balance, the next delta carries the new legacyShop state, and FxEvent perkBought /
-- ActionResult buyPerk are the acknowledgement. With an empty perk list (LegacyShop.json
-- absent) only the pre-M6 Legacy info renders — no shop, no errors.
--
-- Every number is server state or a shared-Economy preview of it; the client never
-- computes a balance or a cost of its own. The neighbors / VIP / Premium bonus lines
-- (M4) stay at the bottom because the neighbors bonus is the one that explains why
-- friends help (spec §4). Long Memory copy is per-tier ("+2 h on your offline cap"),
-- never a total (LEGACY_SHOP.md §8): the delta between tier values is what is shown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local PanelDock = require(script.Parent:WaitForChild("PanelDock"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = {
	gameConfig: Types.GameConfig,
	monetization: Types.MonetizationConfig,
	shopConfig: Types.LegacyShopConfig,
	onPrestige: () -> (),
	onBuyPerk: (perkId: string) -> (),
	onClose: () -> (),
}

export type LegacyPanelHandle = {
	DesignHeight: number,
	Refresh: (state: Types.PlayerState) -> (),
	SetBonuses: (vip: boolean, premium: boolean, playerCount: number) -> (),
	SetPrestige: (label: string?) -> (),
	FlashPerk: (perkId: string) -> (),
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

type PerkRow = {
	perk: Types.PerkDef,
	frame: Frame,
	tierLabel: TextLabel,
	button: TextButton,
	buttonTitle: TextLabel,
	buttonCost: TextLabel,
	stroke: UIStroke,
	affordable: boolean,
	flashUntil: number,
}

local PERCENT = 100
local SECONDS_PER_HOUR = 3600

-- What the NEXT tier adds, in the player's terms. `value` is the total effect at that
-- tier, so per-tier copy (Long Memory) is the difference from the tier below.
local function nextTierEffect(perk: Types.PerkDef, tier: Types.PerkTier, tierIndex: number): string
	local effect = perk.effect
	if effect == "incomeMult" then
		return "+" .. tostring(math.round((tier.value - 1) * PERCENT)) .. "% income"
	elseif effect == "levelCostDiscount" then
		return "−" .. tostring(math.round(tier.value * PERCENT)) .. "% level-up cost"
	elseif effect == "startingSlots" then
		return "cash for the first " .. tostring(tier.value) .. " buildings"
	elseif effect == "levelFloor" then
		return "new buildings start at Lv " .. tostring(tier.value)
	elseif effect == "extraMilestone" then
		return "Lv " .. tostring(tier.value) .. " becomes a milestone"
	elseif effect == "neighbours" then
		local maxBonus = tier.maxBonus
		local text = "+" .. tostring(math.round(tier.value * PERCENT)) .. "% per neighbour"
		if maxBonus ~= nil then
			text ..= " (max " .. tostring(math.round(maxBonus * PERCENT)) .. "%)"
		end
		return text
	elseif effect == "offlineCapSeconds" then
		local previous = perk.tiers[tierIndex - 1]
		local added = tier.value - (if previous ~= nil then previous.value else 0)
		local hours = added / SECONDS_PER_HOUR
		local label = if hours == math.floor(hours)
			then tostring(hours) .. " h"
			else Format.Duration(added)
		return "+" .. label .. " on your offline cap"
	end
	return "" -- cosmetic: the description says it all
end

local LegacyPanel = {}

function LegacyPanel.new(parent: Instance, deps: Deps): LegacyPanelHandle
	local connections: { RBXScriptConnection } = {}
	local perkRows: { PerkRow } = {}
	local rowsById: { [string]: PerkRow } = {}
	local lastState: Types.PlayerState? = nil
	local lastPremium = false
	local lastActionTime = 0
	local gameConfig = deps.gameConfig
	local shopConfig = deps.shopConfig
	local hasShop = #shopConfig.perks > 0

	local panel = Panel.new(parent, {
		name = "LegacyPanel",
		title = "Legacy",
		designHeight = Theme.PANEL_HEIGHT,
		onClose = deps.onClose,
	})
	local scroll = Create("ScrollingFrame", {
		Name = "Lines",
		Size = UDim2.fromScale(1, 1),
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
		Padding = UDim.new(0, Theme.INFO_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function line(name: string, color: Color3, bold: boolean, small: boolean?): TextLabel
		return Create("TextLabel", {
			Name = name,
			LayoutOrder = nextOrder(),
			BackgroundTransparency = 1,
			Size = UDim2.new(
				1,
				-Theme.ROW_SPACING,
				0,
				if small then Theme.PERK_NOTE_LINE_HEIGHT else Theme.INFO_LINE_HEIGHT
			),
			Font = if bold then Theme.FONT_BOLD else Theme.FONT,
			TextSize = if small
				then Theme.TEXT_SMALL
				elseif bold then Theme.TEXT_HEADER
				else Theme.TEXT_MEDIUM,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = scroll,
		}) :: TextLabel
	end

	local function sectionHeader(title: string): TextLabel
		local header = line(title, Theme.COLOR_TEXT_DIM, true)
		header.Text = string.upper(title)
		return header
	end

	-- Header block.
	local legacyLabel = line("LegacyCount", Theme.COLOR_HIGHLIGHT, true)
	local spendableLabel = line("Spendable", Theme.COLOR_TEXT, false)
	spendableLabel.Visible = hasShop
	local breakdownLabel = line("Breakdown", Theme.COLOR_TEXT, false, true)
	-- Softcap note (HUD honesty, LEGACY_SHOP.md §8): only when Game.json declares one.
	local softcap = gameConfig.legacy.softcap
	local softcapLabel = line("Softcap", Theme.COLOR_TEXT_DIM, false, true)
	softcapLabel.Visible = softcap ~= nil
	if softcap ~= nil then
		softcapLabel.Text = "Legacy grows slower past " .. Format.Cash(softcap)
	end
	local rebirthLabel = line("Rebirths", Theme.COLOR_TEXT, false)
	local nextGainLabel = line("NextGain", Theme.COLOR_TEXT_DIM, false)

	local prestigeButton = Create("TextButton", {
		Name = "PrestigeEntry",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.PRESTIGE_ROW_HEIGHT),
		BackgroundColor3 = Theme.COLOR_HIGHLIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Visible = false,
		Parent = scroll,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = prestigeButton }
	)

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

	local function makePerkRow(perk: Types.PerkDef): ()
		-- Height follows the description (AutomaticSize) exactly as Shop rows do, so the
		-- designer's copy can be any length without clipping on a 340 px sheet.
		local frame = Create("Frame", {
			Name = perk.id,
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Parent = scroll,
		}) :: Frame
		Create("UIPadding", {
			PaddingBottom = UDim.new(0, Theme.PERK_ROW_PAD_BOTTOM),
			Parent = frame,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
		local stroke = Create("UIStroke", {
			Color = Theme.COLOR_ERROR,
			Thickness = Theme.STROKE_THICKNESS,
			Enabled = false,
			Parent = frame,
		}) :: UIStroke

		local textWidth = -Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP
		Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.ROW_NAME_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_NAME_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = perk.name,
			Parent = frame,
		})
		local tierLabel = Create("TextLabel", {
			Name = "Tier",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.PERK_TIER_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_ACCENT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		Create("TextLabel", {
			Name = "Description",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.PERK_DESC_Y),
			Size = UDim2.new(1, -Theme.ROW_TEXT_LEFT * 2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = perk.description,
			Parent = frame,
		})

		local button = Create("TextButton", {
			Name = "Buy",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.ROW_NAME_Y),
			Size = UDim2.fromOffset(Theme.ROW_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Text = "",
			Parent = frame,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		local buttonTitle = Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, Theme.BUTTON_TITLE_Y),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.BUTTON_TITLE_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = button,
		}) :: TextLabel
		local buttonCost = Create("TextLabel", {
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

		local row: PerkRow = {
			perk = perk,
			frame = frame,
			tierLabel = tierLabel,
			button = button,
			buttonTitle = buttonTitle,
			buttonCost = buttonCost,
			stroke = stroke,
			affordable = false,
			flashUntil = 0,
		}
		table.insert(perkRows, row)
		rowsById[perk.id] = row

		table.insert(
			connections,
			button.Activated:Connect(function()
				-- Disabled (unaffordable or maxed) is a status, not an offer: the contract
				-- wants the cost in red, not a server round-trip that can only fail.
				if not row.affordable then
					return
				end
				tryAction(function()
					deps.onBuyPerk(perk.id)
				end)
			end)
		)
	end

	-- Built once: LegacyShop.json is static for the life of the server. Perks first,
	-- cosmetics below, each in config order.
	if hasShop then
		local perkCount = 0
		for _, perk in shopConfig.perks do
			if not perk.cosmetic then
				if perkCount == 0 then
					sectionHeader("Perks")
				end
				perkCount += 1
				makePerkRow(perk)
			end
		end
		local cosmeticCount = 0
		for _, perk in shopConfig.perks do
			if perk.cosmetic then
				if cosmeticCount == 0 then
					sectionHeader("Cosmetics")
				end
				cosmeticCount += 1
				makePerkRow(perk)
			end
		end
	end

	sectionHeader("Bonuses")
	local neighborsLabel = line("Neighbors", Theme.COLOR_ACCENT_ALT, false)
	local vipLabel = line("Vip", Theme.COLOR_HIGHLIGHT, false)
	vipLabel.Visible = false
	local premiumLabel = line("Premium", Theme.COLOR_HIGHLIGHT, false)
	premiumLabel.Visible = false

	local function paintPerkRow(row: PerkRow, state: Types.PlayerState, spendable: number): ()
		local perk = row.perk
		local shopState = state.legacyShop
		local total = #perk.tiers
		-- A profile can hold a tier above a shrunk config's count; PerkValue clamps and
		-- NextPerkTier says maxed, so the label agrees rather than reading "Tier 5/3".
		local owned = math.min(Economy.PerkTier(shopState, perk.id), total)
		local nextTier, nextIndex = Economy.NextPerkTier(shopConfig, shopState, perk.id)

		local tierText: string
		if perk.cosmetic then
			tierText = if owned > 0 then "Owned" else "Not owned"
		else
			tierText = "Tier " .. tostring(owned) .. "/" .. tostring(total)
		end
		local affordable = false
		local titleText = "Maxed"
		local costText = ""
		local buttonColor = Theme.COLOR_BG_LIGHT
		local titleColor = Theme.COLOR_TEXT_DIM
		local costColor = Theme.COLOR_TEXT_DIM
		local transparency = 0
		if nextTier ~= nil then
			local effectText = nextTierEffect(perk, nextTier, nextIndex)
			if effectText ~= "" then
				tierText ..= " → " .. effectText
			end
			affordable = spendable >= nextTier.cost
			titleText = "Buy"
			costText = Format.Cash(nextTier.cost) .. " Legacy"
			if affordable then
				buttonColor = Theme.COLOR_ACCENT
				titleColor = Theme.COLOR_TEXT_DARK
				costColor = Theme.COLOR_TEXT_DARK
			else
				transparency = Theme.DIM_TRANSPARENCY
				costColor = Theme.COLOR_ERROR
			end
		end

		row.affordable = affordable
		row.tierLabel.Text = tierText
		row.tierLabel.TextColor3 = if owned > 0 then Theme.COLOR_ACCENT else Theme.COLOR_TEXT_DIM
		row.buttonTitle.Text = titleText
		row.buttonCost.Text = costText
		row.button.Active = affordable
		row.button.AutoButtonColor = affordable
		row.button.BackgroundColor3 = buttonColor
		row.button.BackgroundTransparency = transparency
		row.buttonTitle.TextColor3 = titleColor
		row.buttonCost.TextColor3 = costColor
		-- Two-line button only when a cost is shown; "Maxed" alone centers vertically.
		if costText == "" then
			row.buttonTitle.Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, 0)
			row.buttonTitle.Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 1, 0)
		else
			row.buttonTitle.Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, Theme.BUTTON_TITLE_Y)
			row.buttonTitle.Size =
				UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.BUTTON_TITLE_HEIGHT)
		end
		-- Keep an active failure flash visible across refreshes until it expires.
		if os.clock() < row.flashUntil then
			row.buttonCost.TextColor3 = Theme.COLOR_ERROR
			row.stroke.Enabled = true
		else
			row.stroke.Enabled = false
		end
	end

	-- The breakdown row needs both the pushed state and the local membership signal, so
	-- it repaints from whichever of Refresh / SetBonuses arrived last.
	local function paintBreakdown(): ()
		local state = lastState
		if state == nil then
			return
		end
		local legacyMult = Economy.LegacyMult(state.legacy, gameConfig)
		local perkMult = Economy.PerkIncomeMult(shopConfig, state.legacyShop)
		local passMult = Economy.PassMult(state.passes, deps.monetization)
			* Economy.PremiumMult(lastPremium, deps.monetization)
		breakdownLabel.Text = "Legacy ×"
			.. Format.Rate(legacyMult)
			.. " · Perks ×"
			.. Format.Rate(perkMult)
			.. " · Passes ×"
			.. Format.Rate(passMult)
	end

	local function refresh(state: Types.PlayerState): ()
		lastState = state
		legacyLabel.Text = "Legacy: " .. Format.Cash(state.legacy)
		rebirthLabel.Text = "Rebirths: " .. tostring(state.rebirthCount)
		local totalLevels = 0
		for _, slotState in state.slots do
			totalLevels += slotState.level
		end
		local gain = Economy.LegacyGain(state.era, totalLevels, state.rebirthCount, gameConfig)
		nextGainLabel.Text = "Next advance: +" .. Format.Cash(gain) .. " Legacy"
		paintBreakdown()
		if hasShop then
			local spendable = Economy.LegacySpendable(state)
			spendableLabel.Text = "Spendable: " .. Format.Cash(spendable)
			for _, row in perkRows do
				paintPerkRow(row, state, spendable)
			end
		end
	end

	-- Multipliers are previews of what the server already applied to incomePerSecond; the
	-- numbers come from the same shared config the server reads, never from the client.
	local function setBonuses(vip: boolean, premium: boolean, playerCount: number): ()
		local neighbors = Economy.NeighborsMult(playerCount, gameConfig)
		neighborsLabel.Text = "Neighbors: ×"
			.. Format.Rate(neighbors)
			.. " ("
			.. tostring(playerCount)
			.. (if playerCount == 1 then " player)" else " players)")
		local multipliers = deps.monetization.multipliers
		vipLabel.Visible = vip
		vipLabel.Text = "VIP: ×" .. Format.Rate(multipliers.vip) .. " income"
		premiumLabel.Visible = premium
		premiumLabel.Text = "Premium: ×" .. Format.Rate(multipliers.premium) .. " income"
		lastPremium = premium
		paintBreakdown()
	end

	local function flashPerk(perkId: string): ()
		local row = rowsById[perkId]
		if row == nil then
			return
		end
		row.flashUntil = os.clock() + Theme.FLASH_SECONDS
		row.buttonCost.TextColor3 = Theme.COLOR_ERROR
		row.stroke.Enabled = true
		task.delay(Theme.FLASH_SECONDS, function()
			local state = lastState
			if state ~= nil then
				refresh(state) -- restores true colors once the flash window passed
			end
		end)
	end

	table.insert(
		connections,
		prestigeButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onPrestige()
		end)
	)

	local handle: LegacyPanelHandle = {
		DesignHeight = panel.DesignHeight,
		Refresh = refresh,
		SetBonuses = setBonuses,
		SetPrestige = function(label: string?)
			prestigeButton.Visible = label ~= nil
			prestigeButton.Text = label or ""
		end,
		FlashPerk = flashPerk,
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

return LegacyPanel
