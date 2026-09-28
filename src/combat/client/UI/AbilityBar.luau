--!strict
-- P3 ability cooldown HUD for PC and gamepad (docs/INTERFACES.md "P3 contracts": rulings 1-3
-- and "Client APIs"). Two tiles at the bottom centre, melee then ranged, each with its key
-- (Q / E, or LB / RB after the last gamepad input), the ability's name, a clockwise cooldown
-- sweep with the whole seconds left, a highlight on the active slot, a veil while the caster
-- is busy, a pulse when the ability comes back and a floating "−N.Ns" when a kill refund
-- shortens it (every kill takes killRefundSeconds off BOTH slots, ruling 2).
--
-- Pure display: every time comes from the server's RangeAbility state (read through the
-- caller's getters, which InputController owns) against workspace:GetServerTimeNow(); the
-- sweep's full length is the live cooldownSeconds × abilities.cooldownScale from Tuning. It
-- never decides whether a cast is allowed.
--
-- Touch devices never show it: Motion's touch ability buttons carry the same cooldowns there,
-- and two copies would crowd a phone. Nothing here takes input.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent:WaitForChild("Motion"))

type Slot = "melee" | "ranged"

export type Deps = {
	getState: () -> Types.RangeAbilityState?,
	isBusy: () -> boolean,
	getActiveSlot: () -> Slot,
	-- The loadout the server last confirmed (nil before the first TuneState).
	getLoadout: () -> Types.RangeLoadout?,
}

export type AbilityBarHandle = {
	-- rightReserve: design px kept free at the right edge (the RangePanel's column).
	SetLayout: (scale: number, viewportSize: Vector2, rightReserve: number) -> (),
	Destroy: () -> (),
}

-- The last painted values ride along so a frame writes only what changed.
type Tile = {
	frame: Frame,
	pop: UIScale,
	stroke: UIStroke,
	keyChip: Frame,
	keyLabel: TextLabel,
	nameLabel: TextLabel,
	secondsLabel: TextLabel,
	sweep: Frame,
	sweepRight: UIGradient,
	sweepLeft: UIGradient,
	glow: Frame,
	veil: Frame,
	refund: TextLabel,
	ability: string,
	readyAt: number,
	floorAt: number,
	cooling: boolean,
	seconds: number,
	ready: boolean?,
	active: boolean?,
	busy: boolean?,
}

local SLOTS = { "melee", "ranged" }
-- Mirrors InputController's bindings (Q / E, ButtonL1 / ButtonR1) for the hint only.
-- Keyed by device ("pc" / "pad"), then slot.
local KEYS: { [string]: { [string]: string } } = {
	pc = { melee = "Q", ranged = "E" },
	pad = { melee = "LB", ranged = "RB" },
}
-- The dark sector's edge inside each half: transparent up to the gradient's midpoint, opaque
-- after it. Turning the gradient (UIGradient.Rotation is clockwise) uncovers the tile clockwise
-- from twelve o'clock: the right half over the first half of the cooldown, the left the second.
local SWEEP_EDGE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.499, 1),
	NumberSequenceKeypoint.new(0.501, 0),
	NumberSequenceKeypoint.new(1, 0),
})
local FULL_TURN_DEGREES = 360
local NO_ABILITY_TEXT = "No ability"

local AbilityBar = {}

local function deviceOf(inputType: Enum.UserInputType): string?
	if string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return "pad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "pc"
	end
	return nil
end

-- A family's ability block. The server's id wins when the two disagree for a moment (a family
-- switch whose TuneState and RangeAbility arrive in either order); "" means no ability.
local function abilityOf(family: string?, id: string?): Types.RangeAbilityDef?
	if id == "" then
		return nil
	end
	local weapons = (Tuning.Get() :: any).weapons
	if typeof(weapons) ~= "table" then
		return nil
	end
	local own = if family ~= nil then weapons[family] else nil
	if
		typeof(own) == "table"
		and typeof(own.ability) == "table"
		and (id == nil or own.ability.id == id)
	then
		return own.ability :: Types.RangeAbilityDef
	end
	if id == nil then
		return nil
	end
	for _, def in weapons do
		if typeof(def) == "table" and typeof(def.ability) == "table" and def.ability.id == id then
			return def.ability :: Types.RangeAbilityDef
		end
	end
	return nil
end

local function cooldownScale(): number
	local abilities = (Tuning.Get() :: any).abilities
	local scale = if typeof(abilities) == "table" then abilities.cooldownScale else nil
	return if typeof(scale) == "number" then math.max(scale, 0) else 1
end

local function corner(instance: Instance, radius: number): ()
	Create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = instance })
end

-- One half of the sweep: a clip over half the tile holding a full-tile dark frame whose
-- gradient edge turns about the tile's centre.
local function sweepHalf(parent: Instance, right: boolean): UIGradient
	local clip = Create("Frame", {
		Name = if right then "Right" else "Left",
		Active = false,
		Position = UDim2.fromScale(if right then 0.5 else 0, 0),
		Size = UDim2.fromScale(0.5, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = parent,
	}) :: Frame
	local shade = Create("Frame", {
		Name = "Shade",
		Active = false,
		Position = UDim2.fromScale(if right then -1 else 0, 0),
		Size = UDim2.fromScale(2, 1),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.COMBAT_ABILITY_BAR_SWEEP_TRANSPARENCY,
		BorderSizePixel = 0,
		Parent = clip,
	}) :: Frame
	corner(shade, Theme.ROW_CORNER_RADIUS)
	return Create("UIGradient", { Transparency = SWEEP_EDGE, Parent = shade }) :: UIGradient
end

local function newTile(slot: string, order: number, parent: Instance): Tile
	local inset = Theme.COMBAT_ABILITY_BAR_INSET
	local frame = Create("Frame", {
		Name = if slot == "melee" then "MeleeAbility" else "RangedAbility",
		Active = false,
		LayoutOrder = order,
		Size = UDim2.fromOffset(
			Theme.COMBAT_ABILITY_BAR_TILE_WIDTH,
			Theme.COMBAT_ABILITY_BAR_TILE_HEIGHT
		),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.COMBAT_ABILITY_BAR_BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	corner(frame, Theme.ROW_CORNER_RADIUS)
	local pop = Create("UIScale", { Parent = frame }) :: UIScale
	local stroke = Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DIM,
		Thickness = Theme.COMBAT_ABILITY_BAR_IDLE_STROKE,
		Transparency = Theme.COMBAT_ABILITY_BAR_IDLE_STROKE_TRANSPARENCY,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	}) :: UIStroke

	local sweep = Create("Frame", {
		Name = "Sweep",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = frame,
	}) :: Frame
	local sweepRight = sweepHalf(sweep, true)
	local sweepLeft = sweepHalf(sweep, false)

	-- The ready pulse's flash of the ability colour over the whole tile.
	local glow = Create("Frame", {
		Name = "Glow",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COMBAT_RANGE_ABILITY_COLOR,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = frame,
	}) :: Frame
	corner(glow, Theme.ROW_CORNER_RADIUS)

	local keyChip = Create("Frame", {
		Name = "Key",
		Active = false,
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.fromOffset(
			Theme.COMBAT_ABILITY_BAR_KEY_WIDTH,
			Theme.COMBAT_ABILITY_BAR_KEY_HEIGHT
		),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = frame,
	}) :: Frame
	corner(keyChip, Theme.ROW_CORNER_RADIUS / 2)
	local keyLabel = Create("TextLabel", {
		Name = "Label",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_ABILITY_BAR_KEY_TEXT,
		TextColor3 = Theme.COLOR_TEXT,
		Text = KEYS.pc[slot],
		ZIndex = 4,
		Parent = keyChip,
	}) :: TextLabel

	local secondsLabel = Create("TextLabel", {
		Name = "Seconds",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(
			0.5,
			0,
			0,
			(Theme.COMBAT_ABILITY_BAR_TILE_HEIGHT - Theme.COMBAT_ABILITY_BAR_NAME_HEIGHT - inset)
				/ 2
		),
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_ABILITY_BAR_SECONDS_TEXT + inset),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_ABILITY_BAR_SECONDS_TEXT,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "",
		ZIndex = 4,
		Parent = frame,
	}) :: TextLabel
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = secondsLabel,
	})

	local nameLabel = Create("TextLabel", {
		Name = "Ability",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -inset),
		Size = UDim2.new(1, -inset * 2, 0, Theme.COMBAT_ABILITY_BAR_NAME_HEIGHT),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextScaled = true,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "",
		ZIndex = 4,
		Parent = frame,
	}) :: TextLabel
	-- Scaled only downward, so "Overcharged Shot" fits the tile instead of truncating.
	Create("UITextSizeConstraint", {
		MaxTextSize = Theme.COMBAT_ABILITY_BAR_NAME_TEXT,
		MinTextSize = Theme.COMBAT_ABILITY_BAR_NAME_MIN_TEXT,
		Parent = nameLabel,
	})

	local veil = Create("Frame", {
		Name = "Busy",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.COMBAT_ABILITY_BAR_BUSY_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = frame,
	}) :: Frame
	corner(veil, Theme.ROW_CORNER_RADIUS)

	-- Sits on the tile's top edge and rises out of it.
	local refund = Create("TextLabel", {
		Name = "Refund",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_ABILITY_BAR_REFUND_TEXT + inset),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_ABILITY_BAR_REFUND_TEXT,
		TextColor3 = Theme.COMBAT_RANGE_ABILITY_COLOR,
		TextTransparency = 1,
		Text = "",
		ZIndex = 6,
		Parent = frame,
	}) :: TextLabel
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Transparency = 1,
		Parent = refund,
	})

	return {
		frame = frame,
		pop = pop,
		stroke = stroke,
		keyChip = keyChip,
		keyLabel = keyLabel,
		nameLabel = nameLabel,
		secondsLabel = secondsLabel,
		sweep = sweep,
		sweepRight = sweepRight,
		sweepLeft = sweepLeft,
		glow = glow,
		veil = veil,
		refund = refund,
		-- A value no ability id takes, so the first frame paints the name.
		ability = "\0",
		readyAt = 0,
		floorAt = 0,
		cooling = false,
		seconds = -1,
		ready = nil,
		active = nil,
		busy = nil,
	}
end

function AbilityBar.new(parent: Instance, deps: Deps): AbilityBarHandle
	local connections: { RBXScriptConnection } = {}
	-- One live tween per instance and property group: a newer pulse replaces the one running.
	local activeTweens: { [Instance]: Tween? } = {}
	local visible = not UserInputService.TouchEnabled
	local device = deviceOf(UserInputService:GetLastInputType()) or "pc"

	local root = Create("Frame", {
		Name = "AbilityBar",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(
			Theme.COMBAT_ABILITY_BAR_TILE_WIDTH * 2 + Theme.COMBAT_ABILITY_BAR_GAP,
			Theme.COMBAT_ABILITY_BAR_TILE_HEIGHT
		),
		BackgroundTransparency = 1,
		Visible = visible,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.COMBAT_ABILITY_BAR_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})

	local tiles: { [string]: Tile } = {}
	for index, slot in SLOTS do
		tiles[slot] = newTile(slot, index, root)
	end

	local function play(instance: Instance, info: TweenInfo, goal: { [string]: any }): ()
		local previous = activeTweens[instance]
		if previous ~= nil then
			previous:Cancel()
		end
		local tween = TweenService:Create(instance, info, goal)
		activeTweens[instance] = tween
		tween:Play()
	end

	local function paintKeys(): ()
		for _, slot in SLOTS do
			tiles[slot].keyLabel.Text = KEYS[device][slot]
		end
	end

	-- The ability is back: a pop (smaller under reduced motion) and a flash of its colour.
	local function pulse(tile: Tile): ()
		local peak = Theme.COMBAT_ABILITY_BAR_PULSE_SCALE
		if Theme.reducedMotion then
			peak = 1 + (peak - 1) * Theme.REDUCED_MOTION_FACTOR
		end
		tile.pop.Scale = peak
		local info = Motion.Info(Theme.COMBAT_ABILITY_BAR_PULSE_SECONDS, Enum.EasingStyle.Back)
		play(tile.pop, info, { Scale = 1 })
		tile.glow.BackgroundTransparency = Theme.COMBAT_ABILITY_BAR_BG_TRANSPARENCY
		play(
			tile.glow,
			Motion.Info(Theme.COMBAT_ABILITY_BAR_PULSE_SECONDS),
			{ BackgroundTransparency = 1 }
		)
	end

	-- A kill refund took `seconds` off: "−N.Ns" rises out of the tile and fades.
	local function showRefund(tile: Tile, seconds: number): ()
		local label = tile.refund
		local stroke = label:FindFirstChildOfClass("UIStroke")
		label.Text = "−" .. Format.Rate(seconds) .. "s"
		label.TextTransparency = 0
		label.Position = UDim2.fromScale(0.5, 0)
		local info = Motion.Info(
			Theme.COMBAT_ABILITY_BAR_REFUND_SECONDS,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		local rise = if Theme.reducedMotion then 0 else Theme.COMBAT_ABILITY_BAR_REFUND_RISE
		play(label, info, { TextTransparency = 1, Position = UDim2.new(0.5, 0, 0, -rise) })
		if stroke ~= nil then
			stroke.Transparency = 0
			play(stroke, info, { Transparency = 1 })
		end
	end

	local function familyIn(slot: string): string?
		local loadout = deps.getLoadout()
		if loadout ~= nil then
			return if slot == "melee" then loadout.melee else loadout.ranged
		end
		local start = (Tuning.Get() :: any).loadout
		if typeof(start) ~= "table" then
			return nil
		end
		local family = if slot == "melee" then start.melee else start.ranged
		return if typeof(family) == "string" then family else nil
	end

	local function paintTile(
		tile: Tile,
		slot: string,
		state: Types.RangeAbilityState?,
		now: number,
		active: boolean,
		busy: boolean
	): ()
		local slotState = if state == nil
			then nil
			elseif slot == "melee" then state.melee
			else state.ranged
		local def = abilityOf(familyIn(slot), if slotState ~= nil then slotState.ability else nil)
		local id = if def ~= nil then def.id else ""
		local readyAt = if slotState ~= nil and def ~= nil then slotState.readyAt else 0
		local floorAt = if slotState ~= nil and def ~= nil then slotState.floorAt else 0
		local noise = Theme.COMBAT_ABILITY_BAR_REFUND_MIN
		if id ~= tile.ability then
			tile.ability = id
			tile.nameLabel.Text = if def ~= nil then def.name else NO_ABILITY_TEXT
		elseif
			tile.readyAt > now
			and readyAt < tile.readyAt - noise
			and math.abs(floorAt - tile.floorAt) < noise
		then
			-- The same cast (its floor unchanged) got ready sooner while cooling: a kill refund.
			-- A refused or cancelled cast moves the floor too, so it never reads as one.
			showRefund(tile, math.min(tile.readyAt - readyAt, tile.readyAt - now))
		end
		tile.readyAt = readyAt
		tile.floorAt = floorAt

		local remaining = math.max(readyAt - now, 0)
		local cooling = def ~= nil and remaining > 0
		if def ~= nil and tile.cooling and not cooling then
			pulse(tile)
		end
		tile.cooling = cooling

		tile.sweep.Visible = cooling
		if cooling and def ~= nil then
			-- The sweep's full turn is the tuned cooldown; a longer remainder (a tuning change
			-- racing the state) simply starts the sweep full.
			local total = math.max(def.cooldownSeconds * cooldownScale(), remaining)
			local elapsed = 1 - remaining / total
			tile.sweepRight.Rotation = FULL_TURN_DEGREES * math.min(elapsed, 0.5)
			tile.sweepLeft.Rotation = FULL_TURN_DEGREES * math.max(elapsed, 0.5)
		end
		local seconds = if cooling then math.ceil(remaining) else 0
		if seconds ~= tile.seconds then
			tile.seconds = seconds
			tile.secondsLabel.Text = if seconds > 0 then Format.Cash(seconds) else ""
		end
		-- Ready reads at a glance: a lit key and a bright name; cooling or empty is dim.
		local ready = def ~= nil and not cooling
		if ready ~= tile.ready then
			tile.ready = ready
			tile.keyChip.BackgroundColor3 = if ready
				then Theme.COLOR_HIGHLIGHT
				else Theme.COLOR_BG_LIGHT
			tile.keyLabel.TextColor3 = if ready then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT_DIM
			tile.nameLabel.TextColor3 = if ready then Theme.COLOR_TEXT else Theme.COLOR_TEXT_DIM
		end

		if active ~= tile.active then
			tile.active = active
			tile.stroke.Color = if active then Theme.COLOR_HIGHLIGHT else Theme.COLOR_TEXT_DIM
			tile.stroke.Thickness = if active
				then Theme.COMBAT_ABILITY_BAR_ACTIVE_STROKE
				else Theme.COMBAT_ABILITY_BAR_IDLE_STROKE
			tile.stroke.Transparency = if active
				then 0
				else Theme.COMBAT_ABILITY_BAR_IDLE_STROKE_TRANSPARENCY
		end
		if busy ~= tile.busy then
			tile.busy = busy
			tile.veil.Visible = busy
		end
	end

	local function refresh(): ()
		local state = deps.getState()
		local now = Workspace:GetServerTimeNow()
		local activeSlot = deps.getActiveSlot()
		local busy = deps.isBusy()
		for _, slot in SLOTS do
			paintTile(tiles[slot], slot, state, now, slot == activeSlot, busy)
		end
	end

	if visible then
		table.insert(
			connections,
			UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
				local nextDevice = deviceOf(inputType)
				if nextDevice ~= nil and nextDevice ~= device then
					device = nextDevice
					paintKeys()
				end
			end)
		)
		table.insert(connections, RunService.RenderStepped:Connect(refresh))
		paintKeys()
		refresh()
	end

	local handle: AbilityBarHandle = {
		SetLayout = function(scale: number, viewportSize: Vector2, rightReserve: number)
			uiScale.Scale = scale
			-- Bottom centre, unless a narrow window would put the bar under the panel's column:
			-- then it slides left, never past the left margin.
			local half = root.Size.X.Offset * scale / 2
			local margin = Theme.SCREEN_MARGIN * scale
			local limit = viewportSize.X - (rightReserve + Theme.SCREEN_MARGIN) * scale - half
			local centre = math.max(math.min(viewportSize.X / 2, limit), half + margin)
			root.Position =
				UDim2.fromOffset(centre, viewportSize.Y - Theme.COMBAT_ABILITY_BAR_BOTTOM * scale)
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			for _, tween in activeTweens do
				if tween ~= nil then
					tween:Cancel()
				end
			end
			table.clear(activeTweens)
			root:Destroy()
		end,
	}
	return handle
end

return AbilityBar
