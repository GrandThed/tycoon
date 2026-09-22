--!strict
-- Top HUD bar: cash, income/s, Gear Power (C0), Legacy count (M2), era badge. Display-only —
-- UIController pushes every value from server state; nothing here computes cash, income,
-- or legacy (docs/INTERFACES.md, M1/M2/M3 client contracts). Landscape (M3) parks the bar
-- top-left so the docked side panel never overlaps it on a 667x375 phone. Until the first
-- snapshot every value reads as a dash (M5): a player whose save failed to load must never
-- see "$0 / 0/s" and take it for their real balance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local BLANK = "—"

export type TopBarHandle = {
	SetCash: (cash: number) -> (),
	SetIncome: (incomePerSecond: number) -> (),
	-- C0: Gear Power from the server's Armory.GearPower. nil hides it (no Armory config)
	-- and hands the income/Legacy labels their pre-C0 columns back.
	SetPower: (power: number?) -> (),
	-- spendable is nil when there is no Legacy shop (empty perk config): total only.
	SetLegacy: (legacy: number, spendable: number?) -> (),
	SetEra: (eraIndex: number, displayName: string) -> (),
	SetLayout: (scale: number, landscape: boolean) -> (),
	Destroy: () -> (),
}

local TopBar = {}

function TopBar.new(parent: Instance): TopBarHandle
	local root = Create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.SCREEN_MARGIN),
		Size = UDim2.fromOffset(Theme.TOP_BAR_WIDTH, Theme.TOP_BAR_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = root })
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale

	local cashLabel = Create("TextLabel", {
		Name = "Cash",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.new(1, -14 - Theme.ERA_BADGE_WIDTH - 16, 0, 26),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_LARGE,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = BLANK,
		Parent = root,
	}) :: TextLabel

	local incomeLabel = Create("TextLabel", {
		Name = "Income",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.fromOffset(Theme.TOP_INCOME_WIDTH, 15),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = BLANK,
		Parent = root,
	}) :: TextLabel

	-- C0: Gear Power. Hidden until the server pushes one, so a hub with no Armory config
	-- shows the M9 bar. TextScaled (bounded) because "⚔ 12.4M" outgrows the column.
	local powerLabel = Create("TextLabel", {
		Name = "Power",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14 + Theme.TOP_INCOME_WIDTH_POWER + Theme.TOP_POWER_GAP, 34),
		Size = UDim2.fromOffset(Theme.TOP_POWER_WIDTH, 15),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_ACCENT_ALT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Visible = false,
		Text = "",
		Parent = root,
	}) :: TextLabel
	Create("UITextSizeConstraint", {
		MinTextSize = Theme.TOP_POWER_MIN_TEXT,
		MaxTextSize = Theme.TEXT_SMALL,
		Parent = powerLabel,
	})

	-- M2 contract: Legacy is visible from era 1 so the first advance means something.
	-- Right-aligned against the same text-column edge the cash/income labels stop at.
	local legacyLabel = Create("TextLabel", {
		Name = "Legacy",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -Theme.ERA_BADGE_WIDTH - 16, 0, 34),
		Size = UDim2.fromOffset(Theme.TOP_LEGACY_WIDTH, 15),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_HIGHLIGHT,
		TextXAlignment = Enum.TextXAlignment.Right,
		-- M6: "LEGACY 29 / 279" can outgrow the column at two K-suffixed values; shrink
		-- the text (bounded) instead of cutting the total off the end.
		TextScaled = true,
		Text = "LEGACY " .. BLANK,
		Parent = root,
	}) :: TextLabel
	Create("UITextSizeConstraint", {
		MinTextSize = Theme.TOP_LEGACY_MIN_TEXT,
		MaxTextSize = Theme.TEXT_SMALL,
		Parent = legacyLabel,
	})

	local badge = Create("Frame", {
		Name = "EraBadge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Theme.SCREEN_MARGIN, 0.5, 0),
		Size = UDim2.fromOffset(Theme.ERA_BADGE_WIDTH, Theme.TOP_BAR_HEIGHT - 14),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Parent = root,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = badge })

	local eraIndexLabel = Create("TextLabel", {
		Name = "EraIndex",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 5),
		Size = UDim2.new(1, -16, 0, 13),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "ERA",
		Parent = badge,
	}) :: TextLabel

	local eraNameLabel = Create("TextLabel", {
		Name = "EraName",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 20),
		Size = UDim2.new(1, -16, 0, 16),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = BLANK,
		Parent = badge,
	}) :: TextLabel

	-- The income line holds three fields at 375 px only while Gear Power is on screen, so
	-- the two neighbours give up column width exactly then and take it back otherwise.
	local function setPowerVisible(visible: boolean): ()
		powerLabel.Visible = visible
		incomeLabel.Size = UDim2.fromOffset(
			if visible then Theme.TOP_INCOME_WIDTH_POWER else Theme.TOP_INCOME_WIDTH,
			15
		)
		legacyLabel.Size = UDim2.fromOffset(
			if visible then Theme.TOP_LEGACY_WIDTH_POWER else Theme.TOP_LEGACY_WIDTH,
			15
		)
	end

	local handle: TopBarHandle = {
		SetCash = function(cash: number)
			cashLabel.Text = "$" .. Format.Cash(cash)
		end,
		SetIncome = function(incomePerSecond: number)
			-- Format.Rate keeps sub-1/s starters from rendering "0/s" (M3 contract).
			incomeLabel.Text = Format.Rate(incomePerSecond) .. "/s"
		end,
		SetPower = function(power: number?)
			if power == nil then
				setPowerVisible(false)
				return
			end
			-- Format.Cash, not tostring: Gear Power reaches six figures by Metropolis.
			powerLabel.Text = "⚔ " .. Format.Cash(power)
			setPowerVisible(true)
		end,
		SetLegacy = function(legacy: number, spendable: number?)
			-- Spendable first: it is the number the player acts on; the lifetime total
			-- (which never decreases) follows so the multiplier still has its explanation.
			legacyLabel.Text = if spendable ~= nil
				then "LEGACY " .. Format.Cash(spendable) .. " / " .. Format.Cash(legacy)
				else "LEGACY " .. Format.Cash(legacy)
		end,
		SetEra = function(eraIndex: number, displayName: string)
			-- tostring, not Format.Cash: an era index is an ordinal, never "1.2K".
			eraIndexLabel.Text = "ERA " .. tostring(eraIndex)
			eraNameLabel.Text = displayName
		end,
		SetLayout = function(scale: number, landscape: boolean)
			uiScale.Scale = scale
			-- UIScale multiplies size, not position offsets, so the margin scales by hand.
			local margin = Theme.SCREEN_MARGIN * scale
			if landscape then
				root.AnchorPoint = Vector2.new(0, 0)
				root.Position = UDim2.fromOffset(margin, margin)
			else
				root.AnchorPoint = Vector2.new(0.5, 0)
				root.Position = UDim2.new(0.5, 0, 0, margin)
			end
		end,
		Destroy = function()
			root:Destroy()
		end,
	}
	return handle
end

return TopBar
