--!strict
-- Data-load safe-mode card (M5, docs/INTERFACES.md "Client contracts (M5)"). Visible from
-- boot until the first Snapshot, driven by LoadStatus payloads. A player whose profile
-- cannot load is no longer kicked: they watch this card, may retry or leave, and meanwhile
-- can walk the hub and look at other plots (spec section 5) - so the dim behind the card is
-- a passive Frame that never sinks input, and only the small centered card is Active.
-- Pure display/input: UIController fires the remote and performs the kick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

-- Structural view of Types.LoadStatus: UIController validates the network payload and
-- passes the three fields the card renders.
export type LoadStatusView = { phase: string, attempt: number, retryAvailableIn: number }

export type LoadScreenDeps = { onRetry: () -> (), onLeave: () -> () }

export type LoadScreenHandle = {
	Apply: (status: LoadStatusView) -> (),
	Hide: () -> (),
	SetScale: (scale: number) -> (),
	Destroy: () -> (),
}

type Phase = "loading" | "failed" | "retrying"

local LOADING_TITLE = "Loading your city…"
local SLOW_LINE = "Still working — another server may be finishing your last save."
local FAILED_TITLE = "We couldn't load your save"
local FAILED_BODY = "Nothing you do now will be saved. Try again in a moment, or rejoin."

local LoadScreen = {}

function LoadScreen.new(parent: Instance, deps: LoadScreenDeps): LoadScreenHandle
	local connections: { RBXScriptConnection } = {}
	-- Hide() is permanent: once a model exists the card must never come back, even if a
	-- stray LoadStatus arrives afterwards.
	local hidden = false
	local phase: Phase = "loading"
	local attempt = 1
	local loadingSince = os.clock()
	local retryDeadline = os.clock()
	local retryTappedAt = os.clock()
	local retryEnabled = false

	-- A Frame, not a TextButton (unlike ConfirmDialog's scrim): the dim must never swallow
	-- the touch thumbstick, camera drags, or taps on the world.
	local scrim = Create("Frame", {
		Name = "LoadScreen",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = Theme.LOAD_SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = Theme.ZINDEX_LOAD,
		Parent = parent,
	}) :: Frame

	local card = Create("Frame", {
		Name = "Card",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.LOAD_CARD_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.COLOR_BG,
		BorderSizePixel = 0,
		Parent = scrim,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = card })
	-- No aspect-ratio lock: the card grows with its copy (two lines in the failed state,
	-- one plus the slow line while loading), like ConfirmDialog.
	local uiScale = Create("UIScale", { Parent = card }) :: UIScale
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingBottom = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingLeft = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingRight = UDim.new(0, Theme.DIALOG_PADDING),
		Parent = card,
	})
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.DIALOG_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = card,
	})

	local function line(name: string, order: number, font: Enum.Font, size: number, color: Color3)
		return Create("TextLabel", {
			Name = name,
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			Parent = card,
		}) :: TextLabel
	end

	local titleLabel = line("Title", 1, Theme.FONT_BOLD, Theme.TEXT_LARGE, Theme.COLOR_TEXT)
	local bodyLabel = line("Body", 2, Theme.FONT, Theme.TEXT_MEDIUM, Theme.COLOR_TEXT_DIM)
	local slowLabel = line("Slow", 3, Theme.FONT, Theme.TEXT_MEDIUM, Theme.COLOR_TEXT_DIM)
	local attemptLabel = line("Attempt", 4, Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)

	local buttonRow = Create("Frame", {
		Name = "Buttons",
		LayoutOrder = 1000,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.DIALOG_BUTTON_HEIGHT + Theme.DIALOG_BUTTON_TOP_GAP),
		Visible = false,
		Parent = card,
	}) :: Frame
	local leaveButton = Create("TextButton", {
		Name = "Leave",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -Theme.DIALOG_BUTTON_GAP / 2, 0, Theme.DIALOG_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "Leave",
		Parent = buttonRow,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = leaveButton }
	)
	local retryButton = Create("TextButton", {
		Name = "Retry",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -Theme.DIALOG_BUTTON_GAP / 2, 0, Theme.DIALOG_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		AutoButtonColor = false,
		Text = "Retry",
		Parent = buttonRow,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = retryButton }
	)

	local function paintRetry(enabled: boolean, text: string): ()
		retryEnabled = enabled
		retryButton.Text = text
		retryButton.AutoButtonColor = enabled
		retryButton.BackgroundColor3 = if enabled then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT
		retryButton.TextColor3 = if enabled then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT_DIM
	end

	-- Re-derives every label from the phase and the clock; called on each payload and on
	-- every tick so the countdown and the slow line stay live without per-second state.
	local function render(): ()
		local now = os.clock()
		if phase == "loading" then
			titleLabel.Text = LOADING_TITLE
			bodyLabel.Visible = false
			slowLabel.Text = SLOW_LINE
			slowLabel.Visible = now - loadingSince >= Theme.LOAD_SLOW_SECONDS
			attemptLabel.Visible = attempt > 1
			attemptLabel.Text = "Attempt " .. tostring(attempt)
			buttonRow.Visible = false
			return
		end
		titleLabel.Text = FAILED_TITLE
		bodyLabel.Text = FAILED_BODY
		bodyLabel.Visible = true
		slowLabel.Visible = false
		attemptLabel.Visible = true
		attemptLabel.Text = "Attempt " .. tostring(attempt) .. " failed"
		buttonRow.Visible = true
		if phase == "retrying" then
			paintRetry(false, "Retrying…")
			return
		end
		local remaining = math.ceil(retryDeadline - now)
		if remaining > 0 then
			paintRetry(false, "Retry (" .. Format.Duration(remaining) .. ")")
		else
			paintRetry(true, "Retry")
		end
	end

	local function apply(status: LoadStatusView): ()
		if hidden then
			return
		end
		attempt = status.attempt
		if status.phase == "failed" then
			phase = "failed"
			retryDeadline = os.clock() + math.max(status.retryAvailableIn, 0)
		else
			-- A fresh attempt restarts the slow-line clock: the wait the copy describes is
			-- this attempt's, not the session's.
			if phase ~= "loading" then
				loadingSince = os.clock()
			end
			phase = "loading"
		end
		render()
	end

	local function hide(): ()
		hidden = true
		scrim.Visible = false
	end

	local function tick(): ()
		if phase == "retrying" and os.clock() - retryTappedAt >= Theme.LOAD_RETRY_ACK_SECONDS then
			-- The server answers every honored retry with a status; silence means it refused
			-- (cooldown not yet elapsed by its clock) or the intent was dropped. Re-arm so the
			-- player is never stuck on "Retrying…".
			phase = "failed"
			retryDeadline = os.clock()
		end
		render()
	end

	-- One quarter-second loop for the whole loading period; ends itself once hidden.
	task.spawn(function()
		while not hidden do
			task.wait(Theme.LOAD_TICK_SECONDS)
			if not hidden then
				tick()
			end
		end
	end)

	table.insert(
		connections,
		retryButton.Activated:Connect(function()
			if hidden or not retryEnabled then
				return
			end
			SoundController.Play("uiClick")
			phase = "retrying"
			retryTappedAt = os.clock()
			render()
			deps.onRetry()
		end)
	)
	table.insert(
		connections,
		leaveButton.Activated:Connect(function()
			if hidden then
				return
			end
			SoundController.Play("uiClick")
			deps.onLeave()
		end)
	)

	render()

	local handle: LoadScreenHandle = {
		Apply = apply,
		Hide = hide,
		SetScale = function(scale: number)
			uiScale.Scale = scale
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			hidden = true
			scrim:Destroy()
		end,
	}
	return handle
end

return LoadScreen
