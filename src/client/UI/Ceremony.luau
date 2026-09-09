--!strict
-- Ceremony overlay (M3 contract) shown on FxEvent eraAdvance / rebirth: full-screen
-- scrim, a fixed-aspect title block ("ERA n — <displayName>", rebirth adds "REBIRTH ×n"),
-- "+X Legacy", the matching jingle, auto-dismiss after a Theme duration or on tap.
-- Reduce-motion shortens both the pop-in and the hold. The fresh snapshot rebuilds the
-- HUD behind it; onClosed lets UIController switch the ambient loop afterwards.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Motion = require(script.Parent:WaitForChild("Motion"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type CeremonyKind = "eraAdvance" | "rebirth"

export type ShowOptions = {
	kind: CeremonyKind,
	eraIndex: number,
	displayName: string,
	legacyGained: number,
	rebirthCount: number,
}

export type Deps = { onClosed: () -> () }

export type CeremonyHandle = {
	Show: (options: ShowOptions) -> (),
	IsOpen: () -> boolean,
	SetScale: (scale: number) -> (),
	Destroy: () -> (),
}

local Ceremony = {}

function Ceremony.new(parent: Instance, deps: Deps): CeremonyHandle
	local activeToken = 0
	local isOpen = false
	local tweens: { Tween } = {}
	local connections: { RBXScriptConnection } = {}

	local overlay = Create("TextButton", {
		Name = "Ceremony",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = Theme.CEREMONY_SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = Theme.ZINDEX_CEREMONY,
		Parent = parent,
	}) :: TextButton

	-- Outer frame carries the HUD scale; the inner CanvasGroup carries the pop-in scale
	-- and a single GroupTransparency for the fade (two UIScales on one object don't stack).
	local holder = Create("Frame", {
		Name = "TitleHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.CEREMONY_TITLE_WIDTH, Theme.CEREMONY_TITLE_HEIGHT),
		BackgroundTransparency = 1,
		Parent = overlay,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = holder }) :: UIScale
	Create("UIAspectRatioConstraint", {
		AspectRatio = Theme.CEREMONY_TITLE_WIDTH / Theme.CEREMONY_TITLE_HEIGHT,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
		Parent = holder,
	})

	local block = Create("CanvasGroup", {
		Name = "TitleBlock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Parent = holder,
	}) :: CanvasGroup
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = block })
	Create("UIStroke", {
		Color = Theme.COLOR_HIGHLIGHT,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = block,
	})
	local popScale = Create("UIScale", { Parent = block }) :: UIScale
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.ERA_SCREEN_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = block,
	})

	local function line(
		name: string,
		order: number,
		height: number,
		font: Enum.Font,
		textSize: number,
		color: Color3
	): TextLabel
		return Create("TextLabel", {
			Name = name,
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -Theme.PADDING * 2, 0, height),
			Font = font,
			TextSize = textSize,
			TextColor3 = color,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = block,
		}) :: TextLabel
	end

	local kickerLabel = line(
		"Kicker",
		1,
		Theme.INFO_LINE_HEIGHT,
		Theme.FONT_BOLD,
		Theme.TEXT_MEDIUM,
		Theme.COLOR_HIGHLIGHT
	)
	local titleLabel = line(
		"Title",
		2,
		Theme.TEXT_TITLE + Theme.PADDING,
		Theme.FONT_BOLD,
		Theme.TEXT_TITLE,
		Theme.COLOR_TEXT
	)
	local legacyLabel = line(
		"Legacy",
		3,
		Theme.INFO_LINE_HEIGHT,
		Theme.FONT_BOLD,
		Theme.TEXT_HEADER,
		Theme.COLOR_HIGHLIGHT
	)
	local hintLabel =
		line("Hint", 4, Theme.ROW_LINE_HEIGHT, Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	hintLabel.Text = "Tap to continue"

	local function cancelTweens(): ()
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
	end

	local function play(tween: Tween): ()
		table.insert(tweens, tween)
		tween:Play()
	end

	local function close(): ()
		if not isOpen then
			return
		end
		isOpen = false
		cancelTweens()
		overlay.Visible = false
		block.GroupTransparency = 0
		popScale.Scale = 1
		deps.onClosed()
	end

	local function dismiss(token: number): ()
		if token ~= activeToken or not isOpen then
			return
		end
		activeToken += 1 -- a second tap or the timer can't dismiss twice
		if Theme.reducedMotion then
			close()
			return
		end
		cancelTweens()
		local info = Motion.Info(Theme.CEREMONY_FADE_SECONDS)
		local fade = TweenService:Create(overlay, info, { BackgroundTransparency = 1 })
		fade.Completed:Once(close)
		play(fade)
		play(TweenService:Create(block, info, { GroupTransparency = 1 }))
	end

	local function show(options: ShowOptions): ()
		activeToken += 1
		local token = activeToken
		cancelTweens()
		isOpen = true
		kickerLabel.Text = if options.kind == "rebirth"
			then "REBIRTH ×" .. tostring(options.rebirthCount)
			else "ERA ADVANCED"
		titleLabel.Text = "ERA " .. tostring(options.eraIndex) .. " — " .. options.displayName
		legacyLabel.Text = "+" .. Format.Cash(options.legacyGained) .. " Legacy"
		block.GroupTransparency = 0
		overlay.Visible = true
		SoundController.Play(options.kind)
		if Theme.reducedMotion then
			overlay.BackgroundTransparency = Theme.CEREMONY_SCRIM_TRANSPARENCY
			popScale.Scale = 1
		else
			overlay.BackgroundTransparency = 1
			popScale.Scale = Theme.CEREMONY_TITLE_START_SCALE
			play(
				TweenService:Create(
					overlay,
					Motion.Info(Theme.CEREMONY_FADE_SECONDS),
					{ BackgroundTransparency = Theme.CEREMONY_SCRIM_TRANSPARENCY }
				)
			)
			play(
				TweenService:Create(
					popScale,
					Motion.Info(
						Theme.CEREMONY_FADE_SECONDS,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.Out
					),
					{ Scale = 1 }
				)
			)
		end
		task.delay(Motion.Seconds(Theme.CEREMONY_SECONDS), function()
			dismiss(token)
		end)
	end

	table.insert(
		connections,
		overlay.Activated:Connect(function()
			dismiss(activeToken)
		end)
	)

	local handle: CeremonyHandle = {
		Show = show,
		IsOpen = function()
			return isOpen
		end,
		SetScale = function(scale: number)
			uiScale.Scale = scale
		end,
		Destroy = function()
			activeToken += 1
			isOpen = false
			cancelTweens()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			overlay:Destroy()
		end,
	}
	return handle
end

return Ceremony
