--!strict
-- Proving Grounds tuning panel (P1 contract, docs/INTERFACES.md "P1 contracts" → Remotes and
-- Readouts; docs/COMBAT_DESIGN.md §8). Studio only: CombatUIController never builds it outside
-- the range, and the server ignores RequestTune / RequestRangeCommand outside Studio anyway.
--
-- The panel holds no numbers of its own. Every value it shows is read from Tuning.Get() (the
-- base config merged with the server's overrides), every change is one RequestTune(path,
-- value) intent, and the display refreshes when the server's TuneState lands in Tuning. The
-- slider span and step are derived from the base value so a new config key needs no code.
--
-- Layout: a tab and three readout lines stay on screen; the body opens under them and SCROLLS
-- rather than shrinking on a short phone viewport, because every row is a 48 design px target
-- (44 physical px at MIN_SCALE). Sections collapse so the long lists stay out of the way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Deps = {
	onTune: (path: string, value: Types.TuneValue) -> (),
	onCommand: (cmd: string, arg: string?) -> (),
	onWireframe: (on: boolean) -> (),
	onToggle: (open: boolean) -> (),
}

export type RangePanelHandle = {
	SetLoadout: (weapon: string, variant: string?) -> (),
	SetStats: (stats: Types.RangeStats) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

-- `connections` are the row's own, including two on UserInputService that outlive the row's
-- instances, so a rebuilt variant section must disconnect them itself.
type NumberRow = { path: string, refresh: () -> (), connections: { RBXScriptConnection } }

-- Weapon variant fields in reading order; any other numeric field follows alphabetically.
local VARIANT_ORDER = {
	"damage",
	"rate",
	"range",
	"arcDegrees",
	"finisherArcDegrees",
	"width",
	"pad",
	"cap",
	"knockback",
	"launch",
	"pellets",
	"spreadDegrees",
	"pierce",
	"projectileSpeed",
	"splashRadius",
}
local WEAPONS = { "sword", "gun" }
local FEEDBACK_PREFIX = "feedback."
local TOUCH_MODES = { "autoFire", "tapFire" }
-- Integer-valued bases at or above this magnitude step by whole units (heights, speeds,
-- counts); smaller ones (critMult 2, chain 1.0) get fine steps.
local WHOLE_STEP_FROM = 3

local RangePanel = {}

local function isInteger(value: number): boolean
	return value == math.floor(value)
end

-- 1, 2 or 5 times a power of ten, the nearest at or below `raw`.
local function niceStep(raw: number): number
	if raw <= 0 then
		return 1
	end
	local magnitude = 10 ^ math.floor(math.log10(raw))
	local fraction = raw / magnitude
	if fraction >= 5 then
		return 5 * magnitude
	elseif fraction >= 2 then
		return 2 * magnitude
	end
	return magnitude
end

-- Slider span and step for a path, from its base value.
local function rangeFor(path: string, base: number): (number, number)
	if string.sub(path, 1, #FEEDBACK_PREFIX) == FEEDBACK_PREFIX then
		return Theme.COMBAT_RANGE_PANEL_FEEDBACK_MAX, Theme.COMBAT_RANGE_PANEL_FEEDBACK_STEP
	end
	local span = math.max(
		math.abs(base) * Theme.COMBAT_RANGE_PANEL_RANGE_FACTOR,
		Theme.COMBAT_RANGE_PANEL_MIN_SPAN
	)
	if isInteger(base) and (base == 0 or math.abs(base) >= WHOLE_STEP_FROM) then
		return span, 1
	end
	return span, niceStep(span / Theme.COMBAT_RANGE_PANEL_FINE_STEPS)
end

-- The live value at a dot path (string keys, then array indices), nil if it is not a leaf.
local function valueAt(path: string): any
	local node: any = Tuning.Get()
	for _, segment in string.split(path, ".") do
		if typeof(node) ~= "table" then
			return nil
		end
		local byName = node[segment]
		if byName == nil then
			local index = tonumber(segment)
			byName = if index ~= nil then node[index] else nil
		end
		node = byName
	end
	return node
end

local function displayNumber(value: number): string
	return Format.Rate(math.max(value, 0))
end

local function disconnectAll(list: { RBXScriptConnection }): ()
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function sortedKeys(map: { [string]: any }): { string }
	local keys: { string } = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

function RangePanel.new(parent: Instance, deps: Deps): RangePanelHandle
	local connections: { RBXScriptConnection } = {}
	local tuneConnection: Tuning.Connection? = nil
	local rows: { NumberRow } = {}
	local weaponRows: { NumberRow } = {}
	local weaponButtons: { [string]: TextButton } = {}
	local variantButtons: { [string]: TextButton } = {}
	local variantConnections: { RBXScriptConnection } = {}
	local open = false
	local wireframe = false
	local weapon = WEAPONS[1]
	local variant: string? = nil
	local shownVariant = ""
	local order = 0

	local function nextOrder(): number
		order += 1
		return order
	end

	local root = Create("Frame", {
		Name = "RangePanel",
		-- Inactive container: only the tab, the sheet and its controls take input, so the
		-- empty area beside a closed tab never swallows a camera drag.
		Active = false,
		Position = UDim2.fromOffset(Theme.SCREEN_MARGIN, Theme.SCREEN_MARGIN),
		Size = UDim2.fromOffset(Theme.COMBAT_RANGE_PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})

	local function corner(instance: Instance): ()
		Create(
			"UICorner",
			{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = instance }
		)
	end

	-- `sink` collects the click connection (the panel's own list unless a rebuilt part of
	-- the panel owns it).
	local function button(
		text: string,
		parentFrame: Instance,
		onClick: (() -> ())?,
		sink: { RBXScriptConnection }?
	): TextButton
		local item = Create("TextButton", {
			Name = "Button",
			LayoutOrder = nextOrder(),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.FONT,
			TextSize = Theme.COMBAT_RANGE_PANEL_TEXT,
			TextColor3 = Theme.COLOR_TEXT,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = parentFrame,
		}) :: TextButton
		corner(item)
		if onClick ~= nil then
			table.insert(sink or connections, item.Activated:Connect(onClick))
		end
		return item
	end

	local function label(text: string, height: number, parentFrame: Instance): TextLabel
		return Create("TextLabel", {
			Name = "Label",
			LayoutOrder = nextOrder(),
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height),
			Font = Theme.FONT,
			TextSize = Theme.COMBAT_RANGE_PANEL_TEXT,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = parentFrame,
		}) :: TextLabel
	end

	-- Auto-height vertical stack.
	local function stack(name: string, parentFrame: Instance): Frame
		local frame = Create("Frame", {
			Name = name,
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = parentFrame,
		}) :: Frame
		Create("UIListLayout", {
			Padding = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		return frame
	end

	-- Auto-height grid of 48 px cells, `columns` across the sheet's inner width.
	local function grid(name: string, columns: number, parentFrame: Instance): Frame
		local frame = stack(name, parentFrame)
		local list = frame:FindFirstChildOfClass("UIListLayout")
		if list ~= nil then
			list:Destroy()
		end
		local inner = Theme.COMBAT_RANGE_PANEL_WIDTH
			- Theme.COMBAT_RANGE_PANEL_GAP * 2
			- Theme.SCROLLBAR_THICKNESS
		local gaps = Theme.COMBAT_RANGE_PANEL_GAP * (columns - 1)
		Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(
				math.floor((inner - gaps) / columns),
				Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT
			),
			CellPadding = UDim2.fromOffset(
				Theme.COMBAT_RANGE_PANEL_GAP,
				Theme.COMBAT_RANGE_PANEL_GAP
			),
			FillDirectionMaxCells = columns,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		return frame
	end

	-- The tab: a full tap target so the phone emulator can open it. -------------------
	local toggle = Create("TextButton", {
		Name = "Toggle",
		LayoutOrder = nextOrder(),
		Size = UDim2.fromOffset(
			Theme.COMBAT_RANGE_PANEL_TOGGLE_WIDTH,
			Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT
		),
		BackgroundColor3 = Theme.COLOR_HIGHLIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_RANGE_PANEL_TEXT,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "⚙ Range",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = root,
	}) :: TextButton
	corner(toggle)

	-- Readouts: always visible, never interactive, so a fight can be read with the sheet shut.
	local readouts = Create("Frame", {
		Name = "Readouts",
		LayoutOrder = nextOrder(),
		Active = false,
		Size = UDim2.new(
			1,
			0,
			0,
			Theme.COMBAT_RANGE_PANEL_READOUT_LINE * Theme.COMBAT_RANGE_PANEL_READOUT_LINES
				+ Theme.COMBAT_RANGE_PANEL_GAP
		),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = root,
	}) :: Frame
	corner(readouts)
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP),
		PaddingTop = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP / 2),
		Parent = readouts,
	})
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = readouts })
	local statsLine =
		label("Hits — · Kills — · DPS —", Theme.COMBAT_RANGE_PANEL_READOUT_LINE, readouts)
	local crowdLine =
		label("Clear — · Alive —", Theme.COMBAT_RANGE_PANEL_READOUT_LINE, readouts)
	local frameLine = label("", Theme.COMBAT_RANGE_PANEL_READOUT_LINE, readouts)
	local serverMs: number? = nil
	local clientFps: number? = nil
	local function paintFrameLine(): ()
		local server = serverMs
		local fps = clientFps
		frameLine.Text = "Server "
			.. (if server ~= nil then Format.Rate(server) else "—")
			.. " ms · FPS "
			.. (if fps ~= nil then Format.Cash(fps) else "—")
	end
	paintFrameLine()

	-- The sheet. ---------------------------------------------------------------------------
	local body = Create("ScrollingFrame", {
		Name = "Body",
		LayoutOrder = nextOrder(),
		Active = true, -- taps that miss a control land on the sheet, not in the world
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = root,
	}) :: ScrollingFrame
	corner(body)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP),
		PaddingBottom = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP),
		PaddingLeft = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP),
		PaddingRight = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP + Theme.SCROLLBAR_THICKNESS),
		Parent = body,
	})
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	-- A collapsible section: a full-width header button over an auto-height content stack.
	local function section(title: string, startOpen: boolean): Frame
		local content: Frame
		local header = button("", body, function()
			content.Visible = not content.Visible
		end)
		header.Size = UDim2.new(1, 0, 0, Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT)
		header.Font = Theme.FONT_BOLD
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.BackgroundColor3 = Theme.COLOR_ROW
		Create("UIPadding", { PaddingLeft = UDim.new(0, Theme.PADDING), Parent = header })
		content = stack(title, body)
		content.Visible = startOpen
		local function paint(): ()
			header.Text = (if content.Visible then "▾ " else "▸ ") .. title
		end
		table.insert(connections, content:GetPropertyChangedSignal("Visible"):Connect(paint))
		paint()
		return content
	end

	-- One tunable number: a name line, then [−] [slider] [box] [+]. ---------------------
	local function numberRow(parentFrame: Instance, path: string, caption: string): NumberRow?
		local base = Tuning.BaseValue(path)
		if typeof(base) ~= "number" then
			return nil
		end
		local span, step = rangeFor(path, base)
		local rowConnections: { RBXScriptConnection } = {}
		local row = stack("Row", parentFrame)
		local list = row:FindFirstChildOfClass("UIListLayout")
		if list ~= nil then
			list.Padding = UDim.new(0, 0)
		end
		local name = label(caption, Theme.COMBAT_RANGE_PANEL_LABEL_HEIGHT, row)
		local controls = Create("Frame", {
			Name = "Controls",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT),
			BackgroundTransparency = 1,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = row,
		}) :: Frame
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Theme.COMBAT_RANGE_PANEL_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = controls,
		})
		local stepWidth = Theme.COMBAT_RANGE_PANEL_STEP_WIDTH
		local trackWidth = Theme.COMBAT_RANGE_PANEL_WIDTH
			- Theme.COMBAT_RANGE_PANEL_GAP * 5
			- Theme.SCROLLBAR_THICKNESS
			- stepWidth * 2
			- Theme.COMBAT_RANGE_PANEL_VALUE_WIDTH
		local current = base
		local lastSent = 0

		local function snap(value: number): number
			return math.max(math.floor(value / step + 0.5) * step, 0)
		end

		local minus = button("−", controls, nil)
		minus.Size = UDim2.fromOffset(stepWidth, Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT)
		minus.TextSize = Theme.TEXT_LARGE

		-- The track is the whole 48 px cell so a thumb can grab it; the visible bar is thin.
		local track = Create("Frame", {
			Name = "Track",
			LayoutOrder = nextOrder(),
			Active = true,
			Size = UDim2.fromOffset(trackWidth, Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT),
			BackgroundTransparency = 1,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = controls,
		}) :: Frame
		local bar = Create("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, Theme.COMBAT_RANGE_PANEL_TRACK),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = track,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bar })
		local fill = Create("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Theme.COLOR_ACCENT,
			BorderSizePixel = 0,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = bar,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = fill })
		local knob = Create("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(Theme.COMBAT_RANGE_PANEL_KNOB, Theme.COMBAT_RANGE_PANEL_KNOB),
			BackgroundColor3 = Theme.COLOR_TEXT,
			BorderSizePixel = 0,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = track,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = knob })

		local box = Create("TextBox", {
			Name = "Value",
			LayoutOrder = nextOrder(),
			Size = UDim2.fromOffset(
				Theme.COMBAT_RANGE_PANEL_VALUE_WIDTH,
				Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT
			),
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.COMBAT_RANGE_PANEL_TEXT,
			TextColor3 = Theme.COLOR_TEXT,
			Text = "",
			ZIndex = Theme.ZINDEX_CARD,
			Parent = controls,
		}) :: TextBox
		corner(box)

		local plus = button("+", controls, nil)
		plus.Size = UDim2.fromOffset(stepWidth, Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT)
		plus.TextSize = Theme.TEXT_LARGE

		local function show(value: number): ()
			current = value
			local fraction = math.clamp(value / span, 0, 1)
			fill.Size = UDim2.fromScale(fraction, 1)
			knob.Position = UDim2.fromScale(fraction, 0.5)
			if not box:IsFocused() then
				box.Text = displayNumber(value)
			end
			local overridden = Tuning.GetOverrides()[path] ~= nil
			name.TextColor3 = if overridden then Theme.COLOR_HIGHLIGHT else Theme.COLOR_TEXT
			name.Text = if overridden
				then caption .. "  (base " .. displayNumber(base) .. ")"
				else caption
		end

		local function send(value: number, force: boolean): ()
			local snapped = snap(value)
			show(snapped)
			local now = os.clock()
			if not force and now - lastSent < Theme.COMBAT_RANGE_PANEL_SEND_SECONDS then
				return
			end
			lastSent = now
			deps.onTune(path, snapped)
		end

		table.insert(
			rowConnections,
			minus.Activated:Connect(function()
				send(current - step, true)
			end)
		)
		table.insert(
			rowConnections,
			plus.Activated:Connect(function()
				send(current + step, true)
			end)
		)
		table.insert(
			rowConnections,
			box.FocusLost:Connect(function()
				local typed = tonumber(box.Text)
				if typed ~= nil and typed == typed then
					send(typed, true)
				else
					box.Text = displayNumber(current)
				end
			end)
		)

		local dragging: InputObject? = nil
		local function valueFromX(x: number): number
			local left = track.AbsolutePosition.X
			local width = math.max(track.AbsoluteSize.X, 1)
			return math.clamp((x - left) / width, 0, 1) * span
		end
		table.insert(
			rowConnections,
			track.InputBegan:Connect(function(input: InputObject)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					dragging = input
					send(valueFromX(input.Position.X), false)
				end
			end)
		)
		table.insert(
			rowConnections,
			UserInputService.InputChanged:Connect(function(input: InputObject)
				local held = dragging
				if held == nil then
					return
				end
				local mouseDrag = held.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseMovement
				if mouseDrag or input == held then
					send(valueFromX(input.Position.X), false)
				end
			end)
		)
		table.insert(
			rowConnections,
			UserInputService.InputEnded:Connect(function(input: InputObject)
				local held = dragging
				if held ~= nil and (input == held or input.UserInputType == held.UserInputType) then
					dragging = nil
					-- The last position always goes out, even inside the throttle window.
					send(current, true)
				end
			end)
		)

		local record: NumberRow = {
			path = path,
			connections = rowConnections,
			refresh = function()
				local live = valueAt(path)
				if typeof(live) == "number" then
					show(live)
				end
			end,
		}
		record.refresh()
		return record
	end

	local function rowsFor(
		parentFrame: Instance,
		prefix: string,
		map: { [string]: any },
		into: { NumberRow }
	): ()
		for _, key in sortedKeys(map) do
			if typeof(map[key]) == "number" then
				local row = numberRow(parentFrame, prefix .. key, key)
				if row ~= nil then
					table.insert(into, row)
				end
			end
		end
	end

	-- Section: dummies and commands. --------------------------------------------------------
	local commands = section("Dummies & commands", true)
	local setGrid = grid("Sets", Theme.COMBAT_RANGE_PANEL_COMMAND_COLUMNS, commands)
	local config = Tuning.Get()
	for _, setName in sortedKeys((config :: any).dummySets or {}) do
		button(setName, setGrid, function()
			deps.onCommand("set", setName)
		end)
	end
	local commandGrid = grid("Commands", Theme.COMBAT_RANGE_PANEL_COMMAND_COLUMNS, commands)
	button("Reset", commandGrid, function()
		deps.onCommand("reset", nil)
	end)
	button("Stress", commandGrid, function()
		deps.onCommand("stress", nil)
	end)
	button("Export", commandGrid, function()
		deps.onCommand("export", nil)
	end)
	button("Clear tune", commandGrid, function()
		deps.onCommand("clearTune", nil)
	end)
	local wireButton: TextButton
	wireButton = button("Wire: off", commandGrid, function()
		wireframe = not wireframe
		wireButton.Text = if wireframe then "Wire: ON" else "Wire: off"
		wireButton.BackgroundColor3 = if wireframe
			then Theme.COLOR_ACCENT_ALT
			else Theme.COLOR_BG_LIGHT
		deps.onWireframe(wireframe)
	end)
	local touchButton = button("Touch", commandGrid, function()
		local currentMode = valueAt("controls.touchMode")
		local index = table.find(TOUCH_MODES, currentMode) or 1
		deps.onTune("controls.touchMode", TOUCH_MODES[index % #TOUCH_MODES + 1])
	end)
	local function paintTouchMode(): ()
		local currentMode = valueAt("controls.touchMode")
		touchButton.Text = "Touch: "
			.. (if typeof(currentMode) == "string" then currentMode else "?")
	end

	-- Section: weapon, variant and the variant's numbers. ----------------------------------
	local weaponSection = section("Weapon", true)
	local weaponGrid = grid("Weapons", #WEAPONS, weaponSection)
	for _, name in WEAPONS do
		weaponButtons[name] = button(name, weaponGrid, function()
			deps.onCommand("weapon", name)
		end)
	end
	local variantGrid = grid("Variants", Theme.COMBAT_RANGE_PANEL_COMMAND_COLUMNS, weaponSection)
	local variantRows = stack("VariantRows", weaponSection)

	local function currentDef(): Types.RangeWeaponDef?
		local weapons = (Tuning.Get() :: any).weapons
		local def = if typeof(weapons) == "table" then weapons[weapon] else nil
		return if typeof(def) == "table" then def :: Types.RangeWeaponDef else nil
	end

	local function resolvedVariant(): string
		local def = currentDef()
		if def == nil then
			return ""
		end
		if variant ~= nil and def.variants[variant] ~= nil then
			return variant
		end
		return def.default
	end

	-- Rebuilt only when the weapon or variant changes; values refresh in place otherwise.
	local function buildVariant(): ()
		local def = currentDef()
		local key = resolvedVariant()
		local signature = weapon .. "/" .. key
		for name, item in weaponButtons do
			item.BackgroundColor3 = if name == weapon
				then Theme.COLOR_ACCENT
				else Theme.COLOR_BG_LIGHT
			item.TextColor3 = if name == weapon then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT
		end
		if signature == shownVariant or def == nil then
			return
		end
		shownVariant = signature
		disconnectAll(variantConnections)
		for _, row in weaponRows do
			disconnectAll(row.connections)
		end
		for _, item in variantButtons do
			item:Destroy()
		end
		table.clear(variantButtons)
		for _, child in variantRows:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		table.clear(weaponRows)
		for _, variantKey in sortedKeys(def.variants) do
			local variantDef = def.variants[variantKey]
			local caption = variantKey .. " · " .. variantDef.label
			local item = button(caption, variantGrid, function()
				deps.onCommand("variant", variantKey)
			end, variantConnections)
			local selected = variantKey == key
			item.BackgroundColor3 = if selected then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT
			item.TextColor3 = if selected then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT
			variantButtons[variantKey] = item
		end
		local chosen = def.variants[key]
		if chosen == nil then
			return
		end
		local fields = chosen :: any
		local prefix = "weapons." .. weapon .. ".variants." .. key .. "."
		local listed: { [string]: boolean } = {}
		for _, field in VARIANT_ORDER do
			listed[field] = true
			if typeof(fields[field]) == "number" then
				local row = numberRow(variantRows, prefix .. field, field)
				if row ~= nil then
					table.insert(weaponRows, row)
				end
			end
		end
		local rest: { [string]: any } = {}
		for field, value in fields do
			if not listed[field] then
				rest[field] = value
			end
		end
		rowsFor(variantRows, prefix, rest, weaponRows)
		-- The melee combo multipliers are an array; Tuning addresses them as chain.<n>.
		local chain = fields.chain
		if typeof(chain) == "table" then
			for index, value in chain do
				if typeof(value) == "number" then
					local row = numberRow(
						variantRows,
						prefix .. "chain." .. tostring(index),
						"chain " .. tostring(index)
					)
					if row ~= nil then
						table.insert(weaponRows, row)
					end
				end
			end
		end
	end

	-- Sections: movement, shooting, controls, feedback. ------------------------------------
	local groups = { "movement", "shooting", "controls", "feedback" }
	for _, group in groups do
		local map = (config :: any)[group]
		if typeof(map) == "table" then
			local title = string.upper(string.sub(group, 1, 1)) .. string.sub(group, 2)
			rowsFor(section(title, false), group .. ".", map, rows)
		end
	end

	local function refreshAll(): ()
		buildVariant()
		for _, row in rows do
			row.refresh()
		end
		for _, row in weaponRows do
			row.refresh()
		end
		paintTouchMode()
	end

	table.insert(
		connections,
		toggle.Activated:Connect(function()
			open = not open
			body.Visible = open
			deps.onToggle(open)
		end)
	)
	tuneConnection = Tuning.Changed:Connect(refreshAll)

	-- Client frame rate, averaged over a short window so the readout is steady.
	local frames = 0
	local frameTime = 0
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(deltaTime: number)
			frames += 1
			frameTime += deltaTime
			if frameTime >= Theme.COMBAT_RANGE_FPS_SAMPLE_SECONDS then
				clientFps = frames / frameTime
				frames = 0
				frameTime = 0
				paintFrameLine()
			end
		end)
	)
	refreshAll()

	local handle: RangePanelHandle = {
		SetLoadout = function(nextWeapon: string, nextVariant: string?)
			weapon = nextWeapon
			variant = nextVariant
			refreshAll()
		end,
		SetStats = function(stats: Types.RangeStats)
			statsLine.Text = "Hits "
				.. Format.Cash(stats.lastHits)
				.. " · Kills "
				.. Format.Cash(stats.lastKills)
				.. " · DPS "
				.. Format.Rate(stats.dps)
			local clear = stats.clearSeconds
			crowdLine.Text = "Clear "
				.. (if clear ~= nil then Format.Rate(clear) .. " s" else "—")
				.. " · Alive "
				.. Format.Cash(stats.alive)
			serverMs = stats.serverFrameMs
			paintFrameLine()
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			uiScale.Scale = scale
			-- Whatever height is left under the tab and the readouts, down to one row: the
			-- sheet scrolls past that rather than shrinking its 48 px controls.
			local designHeight = viewportSize.Y / scale
			local used = Theme.SCREEN_MARGIN * 2
				+ Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT
				+ readouts.Size.Y.Offset
				+ Theme.COMBAT_RANGE_PANEL_GAP * 2
			local height = math.max(designHeight - used, Theme.COMBAT_RANGE_PANEL_ROW_HEIGHT)
			body.Size = UDim2.new(1, 0, 0, height)
			root.Position =
				UDim2.fromOffset(Theme.SCREEN_MARGIN * scale, Theme.SCREEN_MARGIN * scale)
		end,
		Destroy = function()
			disconnectAll(connections)
			disconnectAll(variantConnections)
			for _, row in rows do
				disconnectAll(row.connections)
			end
			for _, row in weaponRows do
				disconnectAll(row.connections)
			end
			local tuned = tuneConnection
			if tuned ~= nil then
				tuned:Disconnect()
				tuneConnection = nil
			end
			root:Destroy()
		end,
	}
	return handle
end

return RangePanel
