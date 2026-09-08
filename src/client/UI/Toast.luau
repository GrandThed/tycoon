--!strict
-- Small non-blocking toast under the top bar. M2 uses it for the welcome-back message
-- and for generic prestige-failure feedback; M3 replaces the welcome-back use with the
-- real card (spec §10). Never intercepts input: the frame stays inactive and holds no
-- buttons, so gameplay taps pass straight through it.

local TweenService = game:GetService("TweenService")

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type ToastHandle = {
	Show: (message: string, seconds: number, isError: boolean) -> (),
	SetScale: (scale: number) -> (),
	Destroy: () -> (),
}

local Toast = {}

function Toast.new(parent: Instance): ToastHandle
	-- Token guards the auto-dismiss: a newer Show invalidates any pending fade/hide.
	local activeToken = 0
	local currentScale = 1
	local fadeTweens: { Tween } = {}

	local function rootPosition(): UDim2
		-- Sits just below the scaled top bar; UIScale multiplies size, not position
		-- offsets, so the offset scales by hand like every other HUD margin.
		return UDim2.new(
			0.5,
			0,
			0,
			(Theme.SCREEN_MARGIN + Theme.TOP_BAR_HEIGHT + Theme.TOAST_GAP) * currentScale
		)
	end

	local root = Create("Frame", {
		Name = "Toast",
		Active = false, -- explicit: a toast must never block input (M2 contract)
		AnchorPoint = Vector2.new(0.5, 0),
		Position = rootPosition(),
		Size = UDim2.fromOffset(Theme.TOAST_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_TOAST,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = root })
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.TOAST_PADDING),
		PaddingBottom = UDim.new(0, Theme.TOAST_PADDING),
		PaddingLeft = UDim.new(0, Theme.TOAST_PADDING),
		PaddingRight = UDim.new(0, Theme.TOAST_PADDING),
		Parent = root,
	})
	local label = Create("TextLabel", {
		Name = "Message",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.FONT,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = root,
	}) :: TextLabel

	local function cancelTweens(): ()
		for _, tween in fadeTweens do
			tween:Cancel()
		end
		table.clear(fadeTweens)
	end

	local function show(message: string, seconds: number, isError: boolean): ()
		activeToken += 1
		local token = activeToken
		cancelTweens()
		label.Text = message
		label.TextColor3 = if isError then Theme.COLOR_ERROR else Theme.COLOR_TEXT
		label.TextTransparency = 0
		root.BackgroundTransparency = Theme.BG_TRANSPARENCY
		root.Visible = true
		task.delay(seconds, function()
			if token ~= activeToken then
				return -- a newer toast owns the frame now
			end
			if Theme.reducedMotion then
				root.Visible = false
				return
			end
			local info = TweenInfo.new(
				Theme.TOAST_FADE_SECONDS,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			local backgroundTween = TweenService:Create(root, info, { BackgroundTransparency = 1 })
			local textTween = TweenService:Create(label, info, { TextTransparency = 1 })
			table.insert(fadeTweens, backgroundTween)
			table.insert(fadeTweens, textTween)
			backgroundTween.Completed:Once(function()
				if token == activeToken then
					root.Visible = false
				end
			end)
			backgroundTween:Play()
			textTween:Play()
		end)
	end

	local handle: ToastHandle = {
		Show = show,
		SetScale = function(scale: number)
			currentScale = scale
			uiScale.Scale = scale
			root.Position = rootPosition()
		end,
		Destroy = function()
			activeToken += 1 -- invalidates any pending task.delay dismissal
			cancelTweens()
			root:Destroy()
		end,
	}
	return handle
end

return Toast
