--!strict
-- Shared chrome for the bottom-bar panels: rounded sheet, title, 48 px close button, a
-- content area, the open/close slide, and docking. Build/Legacy/Settings compose their
-- rows inside `Content`; UIController owns which panel is open and where it docks.

local TweenService = game:GetService("TweenService")

local Create = require(script.Parent:WaitForChild("Create"))
local Motion = require(script.Parent:WaitForChild("Motion"))
local PanelDock = require(script.Parent:WaitForChild("PanelDock"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type PanelDeps = {
	name: string,
	title: string,
	designHeight: number,
	onClose: () -> (),
}

export type PanelHandle = {
	Root: Frame,
	Content: Frame,
	DesignHeight: number,
	SetTitle: (title: string) -> (),
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

local Panel = {}

function Panel.new(parent: Instance, deps: PanelDeps): PanelHandle
	local isOpen = false
	local openTween: Tween? = nil
	local currentDock: PanelDock.Dock? = nil
	local connections: { RBXScriptConnection } = {}

	local root = Create("Frame", {
		Name = deps.name,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.PANEL_BOTTOM_MARGIN),
		Size = UDim2.fromOffset(Theme.PANEL_WIDTH, deps.designHeight),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = root })
	-- No aspect-ratio lock: PanelDock derives the height from the real viewport.
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale

	local titleLabel = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(Theme.PADDING + 2, 0),
		Size = UDim2.new(1, -Theme.PADDING - Theme.CLOSE_BUTTON_SIZE - 16, 0, Theme.HEADER_HEIGHT),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = deps.title,
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

	local content = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(Theme.PADDING, Theme.HEADER_HEIGHT),
		Size = UDim2.new(1, -Theme.PADDING * 2, 1, -Theme.HEADER_HEIGHT - Theme.PADDING),
		Parent = root,
	}) :: Frame

	local function cancelTween(): ()
		local tween = openTween
		if tween ~= nil then
			tween:Cancel()
			openTween = nil
		end
	end

	local function setOpen(open: boolean): ()
		if open == isOpen then
			return
		end
		isOpen = open
		cancelTween()
		local dock = currentDock
		if not open or dock == nil then
			root.Visible = open
			return
		end
		root.Visible = true
		if Theme.reducedMotion then
			root.Position = dock.position
			return
		end
		root.Position = dock.position + dock.slideOffset
		local tween = TweenService:Create(
			root,
			Motion.Info(Theme.OPEN_TWEEN_SECONDS),
			{ Position = dock.position }
		)
		openTween = tween
		tween:Play()
	end

	local function setLayout(dock: PanelDock.Dock): ()
		currentDock = dock
		cancelTween()
		uiScale.Scale = dock.scale
		root.AnchorPoint = dock.anchor
		root.Size = dock.size
		root.Position = dock.position
	end

	table.insert(
		connections,
		closeButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onClose()
		end)
	)

	local handle: PanelHandle = {
		Root = root,
		Content = content,
		DesignHeight = deps.designHeight,
		SetTitle = function(title: string)
			titleLabel.Text = title
		end,
		SetOpen = setOpen,
		IsOpen = function()
			return isOpen
		end,
		SetLayout = setLayout,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			cancelTween()
			root:Destroy()
		end,
	}
	return handle
end

return Panel
