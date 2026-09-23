--!strict
-- Party invite card (C2 contract, docs/INTERFACES.md "Hub client (ui-engineer B)"): a
-- non-blocking card under the top bar saying who invited the player, with Accept / Decline
-- and a countdown to the server's `expiresIn`, after which it dismisses itself. It carries
-- no entitlement: both buttons only fire RequestPartyRespond(leaderUserId, accept) and the
-- server decides (a late Accept comes back as ActionResult "expired").
--
-- Only the newest invite is shown: a second invite replaces the first, which the server
-- still lets expire on its own. The card stacks below the welcome-back card and above the
-- error toast; UIController passes the offset and reads DesignHeight for the toast.

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Invite = { leaderUserId: number, leaderName: string, expiresIn: number }

export type Deps = {
	onRespond: (leaderUserId: number, accept: boolean) -> (),
	onVisibilityChanged: (visible: boolean) -> (),
}

export type PartyInviteToastHandle = {
	Show: (invite: Invite) -> (),
	-- Hides the card only if it is showing this leader's invite (nil = whatever it shows).
	Dismiss: (leaderUserId: number?) -> (),
	IsVisible: () -> boolean,
	DesignHeight: () -> number,
	SetLayout: (scale: number, landscape: boolean, extraTopDesignPx: number) -> (),
	Destroy: () -> (),
}

local PartyInviteToast = {}

function PartyInviteToast.new(parent: Instance, deps: Deps): PartyInviteToastHandle
	local connections: { RBXScriptConnection } = {}
	local visible = false
	local current: Invite? = nil
	local deadline = 0
	-- Token for the countdown loop: a newer Show or a dismissal ends the old loop.
	local activeToken = 0

	local padding = Theme.WELCOME_CARD_PADDING
	local cardHeight = padding
		+ Theme.PARTY_INVITE_TITLE_HEIGHT
		+ Theme.PARTY_INVITE_BODY_HEIGHT
		+ Theme.PARTY_INVITE_GAP
		+ Theme.DIALOG_BUTTON_HEIGHT
		+ padding

	local root = Create("Frame", {
		Name = "PartyInviteToast",
		Active = true, -- sinks taps on the card body; gameplay taps around it pass through
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(
			0.5,
			0,
			0,
			Theme.SCREEN_MARGIN + Theme.TOP_BAR_HEIGHT + Theme.TOAST_GAP
		),
		Size = UDim2.fromOffset(Theme.PARTY_INVITE_CARD_WIDTH, cardHeight),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = root })
	Create("UIStroke", {
		Color = Theme.COLOR_ACCENT_ALT,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = root,
	})
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	Create("UIAspectRatioConstraint", {
		AspectRatio = Theme.PARTY_INVITE_CARD_WIDTH / cardHeight,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
		Parent = root,
	})

	local titleLabel = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padding, padding),
		Size = UDim2.new(1, -padding * 2, 0, Theme.PARTY_INVITE_TITLE_HEIGHT),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_ACCENT_ALT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Party invite",
		Parent = root,
	}) :: TextLabel
	local bodyLabel = Create("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padding, padding + Theme.PARTY_INVITE_TITLE_HEIGHT),
		Size = UDim2.new(1, -padding * 2, 0, Theme.PARTY_INVITE_BODY_HEIGHT),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = root,
	}) :: TextLabel

	local buttonWidth = (Theme.PARTY_INVITE_CARD_WIDTH - padding * 2 - Theme.DIALOG_BUTTON_GAP) / 2
	local function makeButton(
		name: string,
		text: string,
		color: Color3,
		textColor: Color3,
		x: number
	): TextButton
		local button = Create("TextButton", {
			Name = name,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, x, 1, -padding),
			Size = UDim2.fromOffset(buttonWidth, Theme.DIALOG_BUTTON_HEIGHT),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = textColor,
			Text = text,
			Parent = root,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		return button
	end
	local declineButton =
		makeButton("Decline", "Decline", Theme.COLOR_BG_LIGHT, Theme.COLOR_TEXT, padding)
	local acceptButton = makeButton(
		"Accept",
		"Accept",
		Theme.COLOR_ACCENT,
		Theme.COLOR_TEXT_DARK,
		padding + buttonWidth + Theme.DIALOG_BUTTON_GAP
	)

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
		current = nil
		setVisible(false)
	end

	local function paintCountdown(): ()
		local seconds = math.max(math.ceil(deadline - os.clock()), 0)
		titleLabel.Text = "Party invite · " .. tostring(seconds) .. "s"
	end

	local function show(invite: Invite): ()
		activeToken += 1
		local token = activeToken
		current = invite
		deadline = os.clock() + math.max(invite.expiresIn, 0)
		bodyLabel.Text = invite.leaderName .. " invited you to an expedition party"
		paintCountdown()
		setVisible(true)
		SoundController.Play("uiClick")
		-- One repaint a second is all a whole-second countdown needs; the loop ends itself at
		-- the deadline or when a newer Show/hide bumps the token.
		local function tick(): ()
			if token ~= activeToken then
				return
			end
			if os.clock() >= deadline then
				hide()
				return
			end
			paintCountdown()
			task.delay(Theme.PARTY_TICK_SECONDS, tick)
		end
		task.delay(Theme.PARTY_TICK_SECONDS, tick)
	end

	local function respond(accept: boolean): ()
		local invite = current
		if invite == nil then
			return
		end
		SoundController.Play("uiClick")
		hide()
		deps.onRespond(invite.leaderUserId, accept)
	end

	table.insert(
		connections,
		acceptButton.Activated:Connect(function()
			respond(true)
		end)
	)
	table.insert(
		connections,
		declineButton.Activated:Connect(function()
			respond(false)
		end)
	)

	local handle: PartyInviteToastHandle = {
		Show = show,
		Dismiss = function(leaderUserId: number?)
			local invite = current
			if invite == nil then
				return
			end
			if leaderUserId == nil or invite.leaderUserId == leaderUserId then
				hide()
			end
		end,
		IsVisible = function()
			return visible
		end,
		DesignHeight = function()
			return cardHeight
		end,
		SetLayout = function(scale: number, landscape: boolean, extraTopDesignPx: number)
			uiScale.Scale = scale
			-- Under the top bar (and any card above), matching its alignment. UIScale
			-- multiplies size, not position offsets, so offsets scale by hand.
			local top = (
				Theme.SCREEN_MARGIN
				+ Theme.TOP_BAR_HEIGHT
				+ Theme.TOAST_GAP
				+ extraTopDesignPx
			) * scale
			if landscape then
				root.AnchorPoint = Vector2.new(0, 0)
				root.Position = UDim2.fromOffset(Theme.SCREEN_MARGIN * scale, top)
			else
				root.AnchorPoint = Vector2.new(0.5, 0)
				root.Position = UDim2.new(0.5, 0, 0, top)
			end
		end,
		Destroy = function()
			activeToken += 1 -- ends the countdown loop
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			root:Destroy()
		end,
	}
	return handle
end

return PartyInviteToast
