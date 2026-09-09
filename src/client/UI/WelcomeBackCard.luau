--!strict
-- Welcome-back card (spec §10, M3 contract): a non-blocking card under the top bar with
-- the offline earnings, a dismiss X, and an auto-dismiss. A hidden secondary button slot
-- is reserved for M4's "Double it" dev product via SetDoubleOffer; until then the card
-- keeps its short height. Fixed aspect (UIAspectRatioConstraint) per orientation of the
-- content — the ratio switches with the offer row.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Motion = require(script.Parent:WaitForChild("Motion"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type DoubleOffer = { label: string, onTap: () -> () }

export type Deps = { onVisibilityChanged: (visible: boolean) -> () }

export type WelcomeBackCardHandle = {
	Show: (grantedCash: number, elapsedSeconds: number) -> (),
	Hide: () -> (),
	IsVisible: () -> boolean,
	DesignHeight: () -> number,
	SetDoubleOffer: (offer: DoubleOffer?) -> (),
	SetLayout: (scale: number, landscape: boolean) -> (),
	Destroy: () -> (),
}

local WelcomeBackCard = {}

function WelcomeBackCard.new(parent: Instance, deps: Deps): WelcomeBackCardHandle
	local activeToken = 0
	local visible = false
	local offer: DoubleOffer? = nil
	local fadeTweens: { Tween } = {}
	local connections: { RBXScriptConnection } = {}

	local function cardHeight(): number
		return if offer ~= nil then Theme.WELCOME_CARD_OFFER_HEIGHT else Theme.WELCOME_CARD_HEIGHT
	end

	local root = Create("Frame", {
		Name = "WelcomeBackCard",
		Active = true, -- sinks taps on the card body; gameplay taps around it pass through
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(
			0.5,
			0,
			0,
			Theme.SCREEN_MARGIN + Theme.TOP_BAR_HEIGHT + Theme.TOAST_GAP
		),
		Size = UDim2.fromOffset(Theme.WELCOME_CARD_WIDTH, Theme.WELCOME_CARD_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = root })
	Create("UIStroke", {
		Color = Theme.COLOR_HIGHLIGHT,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = root,
	})
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	local aspect = Create("UIAspectRatioConstraint", {
		AspectRatio = Theme.WELCOME_CARD_WIDTH / Theme.WELCOME_CARD_HEIGHT,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
		Parent = root,
	}) :: UIAspectRatioConstraint

	local padding = Theme.WELCOME_CARD_PADDING
	local textWidth = -padding * 2 - Theme.CLOSE_BUTTON_SIZE
	local titleLabel = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padding, padding),
		Size = UDim2.new(1, textWidth, 0, Theme.WELCOME_TITLE_HEIGHT),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_HIGHLIGHT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Welcome back!",
		Parent = root,
	}) :: TextLabel
	local bodyLabel = Create("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padding, padding + Theme.WELCOME_TITLE_HEIGHT),
		Size = UDim2.new(1, textWidth, 0, Theme.WELCOME_BODY_HEIGHT),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = root,
	}) :: TextLabel
	local closeButton = Create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(Theme.CLOSE_BUTTON_SIZE, Theme.CLOSE_BUTTON_SIZE),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		Text = "X",
		Parent = root,
	}) :: TextButton
	-- M4 "Double it" slot: hidden until SetDoubleOffer receives a product to show.
	local offerButton = Create("TextButton", {
		Name = "DoubleOffer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -padding),
		Size = UDim2.new(1, -padding * 2, 0, Theme.ROW_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_ACCENT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "",
		Visible = false,
		Parent = root,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = offerButton }
	)

	local function cancelTweens(): ()
		for _, tween in fadeTweens do
			tween:Cancel()
		end
		table.clear(fadeTweens)
	end

	local function resetTransparency(): ()
		root.BackgroundTransparency = Theme.BG_TRANSPARENCY
		titleLabel.TextTransparency = 0
		bodyLabel.TextTransparency = 0
		closeButton.TextTransparency = 0
	end

	local function setVisible(nextVisible: boolean): ()
		if visible == nextVisible then
			return
		end
		visible = nextVisible
		root.Visible = nextVisible
		deps.onVisibilityChanged(nextVisible)
	end

	local function hide(): ()
		activeToken += 1
		cancelTweens()
		setVisible(false)
	end

	local function fadeOut(token: number): ()
		if Theme.reducedMotion then
			setVisible(false)
			return
		end
		local info = Motion.Info(Theme.WELCOME_FADE_SECONDS)
		local tweens = {
			TweenService:Create(root, info, { BackgroundTransparency = 1 }),
			TweenService:Create(titleLabel, info, { TextTransparency = 1 }),
			TweenService:Create(bodyLabel, info, { TextTransparency = 1 }),
			TweenService:Create(closeButton, info, { TextTransparency = 1 }),
		}
		for _, tween in tweens do
			table.insert(fadeTweens, tween)
			tween:Play()
		end
		tweens[1].Completed:Once(function()
			if token == activeToken then
				setVisible(false)
			end
		end)
	end

	local function show(grantedCash: number, elapsedSeconds: number): ()
		activeToken += 1
		local token = activeToken
		cancelTweens()
		resetTransparency()
		bodyLabel.Text = "You earned $"
			.. Format.Cash(grantedCash)
			.. " while away ("
			.. Format.Duration(elapsedSeconds)
			.. ")"
		setVisible(true)
		SoundController.Play("welcomeBack")
		task.delay(Theme.WELCOME_SECONDS, function()
			if token == activeToken then
				fadeOut(token)
			end
		end)
	end

	local function applySize(): ()
		local height = cardHeight()
		aspect.AspectRatio = Theme.WELCOME_CARD_WIDTH / height
		root.Size = UDim2.fromOffset(Theme.WELCOME_CARD_WIDTH, height)
	end

	table.insert(
		connections,
		closeButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			hide()
		end)
	)
	table.insert(
		connections,
		offerButton.Activated:Connect(function()
			local current = offer
			if current ~= nil then
				SoundController.Play("uiClick")
				current.onTap()
			end
		end)
	)

	local handle: WelcomeBackCardHandle = {
		Show = show,
		Hide = hide,
		IsVisible = function()
			return visible
		end,
		DesignHeight = cardHeight,
		SetDoubleOffer = function(nextOffer: DoubleOffer?)
			offer = nextOffer
			offerButton.Visible = nextOffer ~= nil
			offerButton.Text = if nextOffer ~= nil then nextOffer.label else ""
			applySize()
			if visible then
				deps.onVisibilityChanged(true) -- height changed; whoever stacks below re-lays out
			end
		end,
		SetLayout = function(scale: number, landscape: boolean)
			uiScale.Scale = scale
			-- Under the top bar, matching its alignment (top-left in landscape). UIScale
			-- multiplies size, not position offsets, so offsets scale by hand.
			local top = (Theme.SCREEN_MARGIN + Theme.TOP_BAR_HEIGHT + Theme.TOAST_GAP) * scale
			if landscape then
				root.AnchorPoint = Vector2.new(0, 0)
				root.Position = UDim2.fromOffset(Theme.SCREEN_MARGIN * scale, top)
			else
				root.AnchorPoint = Vector2.new(0.5, 0)
				root.Position = UDim2.new(0.5, 0, 0, top)
			end
		end,
		Destroy = function()
			activeToken += 1
			cancelTweens()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			root:Destroy()
		end,
	}
	return handle
end

return WelcomeBackCard
