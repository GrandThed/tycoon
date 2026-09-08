--!strict
-- Top HUD bar: cash, income/s, Legacy count (M2), era badge. Display-only by contract —
-- UIController pushes every value from server state; nothing here computes cash, income,
-- or legacy (docs/INTERFACES.md, M1/M2 client contracts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type TopBarHandle = {
	SetCash: (cash: number) -> (),
	SetIncome: (incomePerSecond: number) -> (),
	SetLegacy: (legacy: number) -> (),
	SetEra: (eraIndex: number, eraName: string) -> (),
	SetScale: (scale: number) -> (),
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
		Text = "$0",
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
		Text = "0/s",
		Parent = root,
	}) :: TextLabel

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
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "LEGACY 0",
		Parent = root,
	}) :: TextLabel

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
		Text = "Loading...",
		Parent = badge,
	}) :: TextLabel

	local handle: TopBarHandle = {
		SetCash = function(cash: number)
			cashLabel.Text = "$" .. Format.Cash(cash)
		end,
		SetIncome = function(incomePerSecond: number)
			incomeLabel.Text = Format.Cash(incomePerSecond) .. "/s"
		end,
		SetLegacy = function(legacy: number)
			legacyLabel.Text = "LEGACY " .. Format.Cash(legacy)
		end,
		SetEra = function(eraIndex: number, eraName: string)
			-- tostring, not Format.Cash: an era index is an ordinal, never "1.2K".
			eraIndexLabel.Text = "ERA " .. tostring(eraIndex)
			eraNameLabel.Text = eraName
		end,
		SetScale = function(scale: number)
			uiScale.Scale = scale
			-- UIScale multiplies size, not position offsets, so the margin scales by hand.
			root.Position = UDim2.new(0.5, 0, 0, Theme.SCREEN_MARGIN * scale)
		end,
		Destroy = function()
			root:Destroy()
		end,
	}
	return handle
end

return TopBar
