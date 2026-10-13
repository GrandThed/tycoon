--!strict
-- The screen half of being hit in the Proving Grounds (docs/INTERFACES.md "P4 contracts",
-- rulings 4 and 6; docs/COMBAT_DESIGN.md section 4: with no sound, a hit must be SEEN).
--  * the health bar, which never hides: a loss shows at once and leaves the chunk just lost
--    behind it for a moment, a gain eases in;
--  * the hurt flash at the screen's edges, as strong as the share of max health the hit took;
--  * where the hit came from: a pointer on a ring round the screen centre, turned to the
--    attacker's bearing every frame (straight down = behind the camera), so it reads without
--    seeing the attacker;
--  * knocked down: a banner with the time left, the edge flash held, and a pop on the get-up.
--    P5: a mission's down has no get-up time (upAt = math.huge): the banner reads "DOWN" with
--    no count and no running-out line until the caller stands the player up.
--
-- Pure display. VitalsController hears the server's `hurt` effects and reads the Humanoid; it
-- pushes values in and calls Step from its one RenderStepped connection, so nothing here
-- connects per effect, tweens, or decides anything. Every frame writes only what changed.
--
-- Nothing is gated on Theme.reducedMotion or lowEndDevice: every touch device has
-- reducedMotion set, and all of this is information. Every frame is Active = false, so no
-- aiming drag on a phone is ever swallowed.
--
-- Placement (SetLayout; checked at 375x667 and 1920x1080 against the AbilityBar, the thumb
-- cluster, the crosshair and its counters, and the RangePanel's tab and readouts):
--  * PC and gamepad: the bar sits bottom centre, over the AbilityBar and the "-N.Ns" refund
--    that rises out of it, and slides left with it when the RangePanel's column would cover
--    both.
--  * Touch (the caller passes the thumb cluster's left and top edges): at the bottom edge,
--    beside the cluster, when the screen is wide enough for both; otherwise centred above the
--    cluster's top row (a portrait phone).
--  * The pointer ring is a share of the shorter screen side, pulled in so that a pointer at
--    the bottom never reaches the bar, and (Stop 2) one at the top never reaches the boss bar
--    where that sits low: on a phone, in either orientation.
--  * The banner hangs under the crosshair, inside the ring, where the ring is wide enough to
--    hold it (a monitor); on a phone it sits on the bar and the ring is pulled in above it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Layout = {
	scale: number,
	-- Design px kept free at the right edge (the RangePanel's column), as for the AbilityBar.
	rightReserve: number,
	-- Touch only: the left and top edges, in px, of the right-thumb cluster. nil on devices
	-- without it, where the AbilityBar is what sits under the bar.
	clusterLeft: number?,
	clusterTop: number?,
	-- Stop 2: the bottom edge, in this HUD's own px, of whatever sits above the crosshair (the
	-- boss bar). The pointer ring is pulled in so a pointer at its top stays under it: in a
	-- boss fight most hits come from straight ahead, which is exactly that pointer.
	topLimit: number?,
}

export type VitalsHudHandle = {
	SetLayout: (layout: Layout) -> (),
	SetHealth: (health: number, maxHealth: number) -> (),
	-- A hit landed: `share` of max health lost (0-1) sets the flash's strength.
	Hurt: (share: number) -> (),
	-- A pointer at the world position the hit came from.
	Point: (from: Vector3) -> (),
	-- Knocked down until `upAt` (server time), `seconds` in all; nil = standing again;
	-- math.huge = held until the caller says otherwise (a mission's down: no count).
	SetDown: (upAt: number?, seconds: number) -> (),
	-- `origin` = the local character's root, the point bearings are taken from (nil = the
	-- camera's own position).
	Step: (deltaTime: number, origin: Vector3?) -> (),
	Destroy: () -> (),
}

type Pointer = {
	frame: Frame,
	blade: Frame,
	tip: Frame,
	from: Vector3,
	startedAt: number,
	bearing: number,
	shown: number,
	active: boolean,
}

type Edge = { size: UDim2, position: UDim2, anchor: Vector2, rotation: number, flip: boolean }

local TAU = 2 * math.pi
-- Below this many studs on the flat an attacker has no bearing; the pointer keeps its last.
local MIN_BEARING_STUDS = 0.05
-- The banner's line; the seconds left follow it. A held down (a mission's) has no seconds.
local DOWN_TEXT = "DOWN · up in "
local DOWN_HELD_TEXT = "DOWN"
-- tenthsShown for the held line, which no count can equal.
local HELD_TENTHS = -2
-- The pointer's bar fades out toward both ends, so it reads as an arc of the ring.
local BLADE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.9),
	NumberSequenceKeypoint.new(0.3, 0),
	NumberSequenceKeypoint.new(0.7, 0),
	NumberSequenceKeypoint.new(1, 0.9),
})

local VitalsHud = {}

local function corner(instance: Instance, radius: number): ()
	Create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = instance })
end

local function plain(name: string, color: Color3, parent: Instance): Frame
	return Create("Frame", {
		Name = name,
		Active = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
end

local function text(name: string, size: number, color: Color3, parent: Instance): TextLabel
	local label = Create("TextLabel", {
		Name = name,
		Active = false,
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = size,
		TextColor3 = color,
		Text = "",
		Parent = parent,
	}) :: TextLabel
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS / 2,
		Parent = label,
	})
	return label
end

-- Degrees clockwise from straight ahead of the camera to `from`, seen from `origin` on the
-- flat: 0 = ahead, 90 = right, 180 = behind. nil when the two coincide.
local function bearingOf(camera: CFrame, origin: Vector3, from: Vector3): number?
	local look = camera.LookVector
	local ahead = Vector3.new(look.X, 0, look.Z)
	local offset = Vector3.new(from.X - origin.X, 0, from.Z - origin.Z)
	if ahead.Magnitude < MIN_BEARING_STUDS or offset.Magnitude < MIN_BEARING_STUDS then
		return nil
	end
	ahead = ahead.Unit
	return math.deg(math.atan2(offset.X * -ahead.Z + offset.Z * ahead.X, offset:Dot(ahead)))
end

function VitalsHud.new(parent: Instance): VitalsHudHandle
	local layout: Layout = { scale = 1, rightReserve = 0 }
	local connections: { RBXScriptConnection } = {}

	local root = Create("Frame", {
		Name = "RangeVitals",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame

	-- Edge flash: four bars fading inward, as FeedbackController builds its kill flash (there
	-- is no vignette image asset), in the hurt colour.
	local thickness = Theme.COMBAT_RANGE_HURT_FLASH_THICKNESS
	local vertical = UDim2.new(0, thickness, 1, 0)
	local horizontal = UDim2.new(1, 0, 0, thickness)
	local edges: { Edge } = {
		{
			size = vertical,
			position = UDim2.fromScale(0, 0),
			anchor = Vector2.zero,
			rotation = 0,
			flip = false,
		},
		{
			size = vertical,
			position = UDim2.fromScale(1, 0),
			anchor = Vector2.xAxis,
			rotation = 0,
			flip = true,
		},
		{
			size = horizontal,
			position = UDim2.fromScale(0, 0),
			anchor = Vector2.zero,
			rotation = 90,
			flip = false,
		},
		{
			size = horizontal,
			position = UDim2.fromScale(0, 1),
			anchor = Vector2.yAxis,
			rotation = 90,
			flip = true,
		},
	}
	local edgeBars: { Frame } = {}
	for _, edge in edges do
		local bar = plain("HurtFlash", Theme.COMBAT_RANGE_HURT_COLOR, root)
		bar.Size = edge.size
		bar.Position = edge.position
		bar.AnchorPoint = edge.anchor
		bar.BackgroundTransparency = 1
		Create("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, if edge.flip then 1 else 0),
				NumberSequenceKeypoint.new(1, if edge.flip then 0 else 1),
			}),
			Parent = bar,
		})
		table.insert(edgeBars, bar)
	end

	-- Pointers: a bar across the ring with a point on its outer side. The frame is placed on
	-- the ring and turned to the bearing, so its children need no maths of their own.
	local pointers: { Pointer } = {}
	for _ = 1, Theme.COMBAT_RANGE_HURT_POINTERS do
		local frame = Create("Frame", {
			Name = "HurtFrom",
			Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = root,
		}) :: Frame
		local tip = plain("Tip", Theme.COMBAT_RANGE_HURT_COLOR, frame)
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.fromScale(0.5, 0)
		tip.Rotation = 45
		local blade = plain("Blade", Theme.COMBAT_RANGE_HURT_COLOR, frame)
		blade.Size = UDim2.fromScale(1, 1)
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = blade })
		Create("UIGradient", { Transparency = BLADE_FADE, Parent = blade })
		table.insert(pointers, {
			frame = frame,
			blade = blade,
			tip = tip,
			from = Vector3.zero,
			startedAt = 0,
			bearing = 0,
			shown = 1,
			active = false,
		})
	end
	local ringRadius = 0

	-- The health bar: lost chunk under the fill, the numbers over both.
	local bar = plain("Health", Theme.COLOR_BG, root)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Size = UDim2.fromOffset(Theme.COMBAT_RANGE_VITALS_WIDTH, Theme.COMBAT_RANGE_VITALS_HEIGHT)
	bar.BackgroundTransparency = Theme.COMBAT_RANGE_VITALS_BG_TRANSPARENCY
	corner(bar, Theme.ROW_CORNER_RADIUS / 2)
	local barScale = Create("UIScale", { Parent = bar }) :: UIScale
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = bar,
	})
	local lost = plain("Lost", Theme.COMBAT_RANGE_VITALS_LOST_COLOR, bar)
	lost.Size = UDim2.fromScale(0, 1)
	corner(lost, Theme.ROW_CORNER_RADIUS / 2)
	local fill = plain("Fill", Theme.COMBAT_RANGE_VITALS_FILL_COLOR, bar)
	fill.Size = UDim2.fromScale(1, 1)
	corner(fill, Theme.ROW_CORNER_RADIUS / 2)
	local value = text("Value", Theme.COMBAT_RANGE_VITALS_TEXT, Theme.COLOR_TEXT, bar)
	value.Size = UDim2.fromScale(1, 1)
	value.ZIndex = 2

	-- Knocked down: one line with the time left, over a line that runs out with it.
	local banner = plain("Down", Theme.COLOR_BG, root)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Size = UDim2.fromOffset(Theme.COMBAT_RANGE_DOWN_WIDTH, Theme.COMBAT_RANGE_DOWN_HEIGHT)
	banner.BackgroundTransparency = Theme.SCRIM_TRANSPARENCY
	banner.Visible = false
	corner(banner, Theme.ROW_CORNER_RADIUS)
	local bannerScale = Create("UIScale", { Parent = banner }) :: UIScale
	Create("UIStroke", {
		Color = Theme.COMBAT_RANGE_HURT_COLOR,
		Thickness = Theme.STROKE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = banner,
	})
	local caption =
		text("Caption", Theme.COMBAT_RANGE_DOWN_TEXT, Theme.COMBAT_RANGE_HURT_COLOR, banner)
	caption.Size = UDim2.new(1, 0, 1, -Theme.COMBAT_RANGE_DOWN_BAR_HEIGHT)
	local timer = plain("Timer", Theme.COMBAT_RANGE_HURT_COLOR, banner)
	timer.AnchorPoint = Vector2.new(0, 1)
	timer.Position = UDim2.new(0, Theme.ROW_CORNER_RADIUS, 1, -Theme.COMBAT_RANGE_DOWN_BAR_HEIGHT)
	timer.Size = UDim2.new(1, -2 * Theme.ROW_CORNER_RADIUS, 0, Theme.COMBAT_RANGE_DOWN_BAR_HEIGHT)

	-- What is shown, so a frame writes only changes.
	local target = 1
	local fillShare = 1
	local lostShare = 1
	local lostHoldUntil = 0
	local fillShown = -1
	local lostShown = -1
	local fillColor = Theme.COMBAT_RANGE_VITALS_FILL_COLOR
	local healthShown = -1
	local maxShown = -1
	local popAt = -math.huge
	local scaleShown = -1
	local flash = 0
	local flashShown = 1
	local downUntil: number? = nil
	local downSeconds = 0
	local tenthsShown = -1
	local timerShown = -1
	local clock = 0
	-- The point bearings were last taken from, so a new pointer starts where it will stay.
	local lastOrigin: Vector3? = nil

	local function applyLayout(): ()
		local size = root.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local scale = layout.scale
		local half = Theme.COMBAT_RANGE_VITALS_WIDTH * scale / 2
		local gap = Theme.COMBAT_RANGE_VITALS_GAP * scale
		local margin = Theme.SCREEN_MARGIN * scale
		local centreX = size.X / 2
		local bottom = size.Y - Theme.COMBAT_RANGE_VITALS_BOTTOM * scale
		local clusterLeft = layout.clusterLeft
		local clusterTop = layout.clusterTop
		if clusterLeft ~= nil and clusterTop ~= nil then
			local beside = math.min(centreX, clusterLeft - gap - half)
			if beside - half >= margin then
				centreX = beside
			else
				bottom = clusterTop - gap
			end
		else
			-- Over the AbilityBar and its refund text, on the AbilityBar's own slide rule.
			local limit = size.X - (layout.rightReserve + Theme.SCREEN_MARGIN) * scale - half
			centreX = math.max(math.min(centreX, limit), half + margin)
			local under = Theme.COMBAT_ABILITY_BAR_BOTTOM
				+ Theme.COMBAT_ABILITY_BAR_TILE_HEIGHT
				+ Theme.COMBAT_ABILITY_BAR_REFUND_TEXT
				+ Theme.COMBAT_ABILITY_BAR_INSET
				+ Theme.COMBAT_ABILITY_BAR_REFUND_RISE
			bottom = size.Y - under * scale - gap
		end
		bar.Position = UDim2.fromOffset(centreX, bottom)
		local barTop = bottom - Theme.COMBAT_RANGE_VITALS_HEIGHT * scale

		local centreY = size.Y / 2
		local bladeHeight = Theme.COMBAT_RANGE_HURT_POINTER_THICKNESS * scale
		local tipSize = Theme.COMBAT_RANGE_HURT_POINTER_TIP * scale
		-- A pointer reaches past its radius by half its bar and its point.
		local reach = bladeHeight / 2 + tipSize
		local wanted = Theme.COMBAT_RANGE_HURT_POINTER_RADIUS_SHARE * math.min(size.X, size.Y)
		local radius = math.min(wanted, barTop - centreY - reach - gap)
		-- The banner hangs under the crosshair where the ring is wide enough to hold it inside
		-- (a monitor). On a phone it is not, and the blow that puts a player down may well
		-- come from behind: there the banner sits on the bar and the ring is pulled in above
		-- it, so the pointer at the bottom never crosses the banner.
		local bannerHeight = Theme.COMBAT_RANGE_DOWN_HEIGHT * scale
		local bannerTop = centreY + Theme.COMBAT_RANGE_CROSSHAIR_SIZE / 2 * scale + gap
		if bannerTop + bannerHeight + gap > centreY + radius - bladeHeight / 2 then
			bannerTop = barTop - gap - bannerHeight
			radius = math.min(wanted, bannerTop - centreY - reach - gap)
		end
		banner.Position = UDim2.fromOffset(centreX, bannerTop)
		bannerScale.Scale = scale
		local topLimit = layout.topLimit
		if topLimit ~= nil then
			radius = math.min(radius, centreY - topLimit - reach - gap)
		end
		ringRadius = math.max(radius, 0)
		for _, pointer in pointers do
			pointer.frame.Size =
				UDim2.fromOffset(Theme.COMBAT_RANGE_HURT_POINTER_WIDTH * scale, bladeHeight)
			pointer.tip.Size = UDim2.fromOffset(tipSize, tipSize)
		end
	end

	local function placePointer(pointer: Pointer): ()
		local angle = math.rad(pointer.bearing)
		pointer.frame.Position =
			UDim2.new(0.5, ringRadius * math.sin(angle), 0.5, -ringRadius * math.cos(angle))
		pointer.frame.Rotation = pointer.bearing
	end

	local function stepPointers(now: number, origin: Vector3?): ()
		local camera = Workspace.CurrentCamera
		local frame = if camera ~= nil then camera.CFrame else nil
		for _, pointer in pointers do
			if not pointer.active then
				continue
			end
			local u = (now - pointer.startedAt) / Theme.COMBAT_RANGE_HURT_POINTER_SECONDS
			if u >= 1 then
				pointer.active = false
				pointer.frame.Visible = false
				continue
			end
			if frame ~= nil then
				local bearing = bearingOf(frame, origin or frame.Position, pointer.from)
				if bearing ~= nil then
					pointer.bearing = bearing
				end
			end
			placePointer(pointer)
			local fadeFrom = Theme.COMBAT_RANGE_HURT_POINTER_FADE_FROM
			local fade = if u <= fadeFrom then 0 else (u - fadeFrom) / (1 - fadeFrom)
			local shown = 1 - (1 - Theme.COMBAT_RANGE_HURT_POINTER_TRANSPARENCY) * (1 - fade)
			if math.abs(shown - pointer.shown) > 0.01 then
				pointer.shown = shown
				pointer.blade.BackgroundTransparency = shown
				pointer.tip.BackgroundTransparency = shown
			end
		end
	end

	local function stepBar(now: number, deltaTime: number): ()
		if target < fillShare then
			-- A loss: the fill drops at once and the chunk it left stays, bright, for a moment.
			lostShare = math.max(lostShare, fillShare)
			fillShare = target
			lostHoldUntil = now + Theme.COMBAT_RANGE_VITALS_LOST_HOLD_SECONDS
		elseif target > fillShare then
			fillShare += (target - fillShare) * (1 - math.exp(
				-Theme.COMBAT_RANGE_VITALS_GAIN_RATE * deltaTime
			))
			if target - fillShare < 0.002 then
				fillShare = target
			end
		end
		if lostShare > fillShare and now >= lostHoldUntil then
			lostShare = math.max(
				lostShare - Theme.COMBAT_RANGE_VITALS_LOST_DRAIN_PER_SECOND * deltaTime,
				fillShare
			)
		elseif lostShare < fillShare then
			lostShare = fillShare
		end
		if math.abs(fillShare - fillShown) > 0.001 then
			fillShown = fillShare
			fill.Size = UDim2.fromScale(fillShare, 1)
			local color = if fillShare <= Theme.COMBAT_RANGE_VITALS_CRITICAL_SHARE
				then Theme.COMBAT_RANGE_HURT_COLOR
				elseif
					fillShare <= Theme.COMBAT_RANGE_VITALS_LOW_SHARE
				then Theme.COMBAT_RANGE_VITALS_LOW_COLOR
				else Theme.COMBAT_RANGE_VITALS_FILL_COLOR
			if color ~= fillColor then
				fillColor = color
				fill.BackgroundColor3 = color
			end
		end
		if math.abs(lostShare - lostShown) > 0.001 then
			lostShown = lostShare
			lost.Size = UDim2.fromScale(lostShare, 1)
		end
		local popLeft = math.max(0, 1 - (now - popAt) / Theme.COMBAT_RANGE_VITALS_POP_SECONDS)
		local scale = layout.scale * (1 + (Theme.COMBAT_RANGE_VITALS_POP_SCALE - 1) * popLeft)
		if scale ~= scaleShown then
			scaleShown = scale
			barScale.Scale = scale
		end
	end

	local function stepFlash(deltaTime: number, down: boolean): ()
		flash = math.max(flash - deltaTime / Theme.COMBAT_RANGE_HURT_FLASH_SECONDS, 0)
		local level = flash
		if down then
			-- Held while down, breathing slowly, so the screen itself says "not yet".
			local wave = 0.5 + 0.5 * math.sin(clock * TAU / Theme.COMBAT_RANGE_DOWN_PULSE_SECONDS)
			level = math.max(
				level,
				Theme.COMBAT_RANGE_DOWN_FLASH * (1 - Theme.COMBAT_RANGE_DOWN_PULSE_DEPTH * wave)
			)
		end
		local shown = 1 - (1 - Theme.COMBAT_RANGE_HURT_FLASH_TRANSPARENCY) * level
		if math.abs(shown - flashShown) > 0.005 then
			flashShown = shown
			for _, edgeBar in edgeBars do
				edgeBar.BackgroundTransparency = shown
			end
		end
	end

	local function stepBanner(): boolean
		local upAt = downUntil
		if upAt == nil then
			return false
		end
		if upAt == math.huge then
			if tenthsShown ~= HELD_TENTHS then
				tenthsShown = HELD_TENTHS
				caption.Text = DOWN_HELD_TEXT
				timerShown = 0
				timer.Visible = false
			end
			return true
		end
		if not timer.Visible then
			timer.Visible = true
		end
		local left = math.max(upAt - Workspace:GetServerTimeNow(), 0)
		-- Tenths, so the line is rewritten ten times a second, not every frame.
		local tenths = math.ceil(left * 10)
		if tenths ~= tenthsShown then
			tenthsShown = tenths
			caption.Text = DOWN_TEXT .. Format.Rate(tenths / 10) .. " s"
		end
		local share = if downSeconds > 0 then math.clamp(left / downSeconds, 0, 1) else 0
		if math.abs(share - timerShown) > 0.002 then
			timerShown = share
			-- A share of the banner's width between its rounded corners.
			timer.Size = UDim2.new(
				share,
				-2 * Theme.ROW_CORNER_RADIUS * share,
				0,
				Theme.COMBAT_RANGE_DOWN_BAR_HEIGHT
			)
		end
		return true
	end

	table.insert(connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout))
	applyLayout()

	local handle: VitalsHudHandle = {
		SetLayout = function(nextLayout: Layout)
			layout = nextLayout
			applyLayout()
		end,
		SetHealth = function(health: number, maxHealth: number)
			if health == healthShown and maxHealth == maxShown then
				return
			end
			healthShown = health
			maxShown = maxHealth
			target = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
			value.Text = Format.Cash(math.max(math.ceil(health), 0))
				.. " / "
				.. Format.Cash(math.max(maxHealth, 0))
		end,
		Hurt = function(share: number)
			local strength = math.clamp(
				share / Theme.COMBAT_RANGE_HURT_FLASH_FULL_SHARE,
				Theme.COMBAT_RANGE_HURT_FLASH_MIN,
				1
			)
			flash = math.max(flash, strength)
			popAt = os.clock()
		end,
		Point = function(from: Vector3)
			local now = os.clock()
			local camera = Workspace.CurrentCamera
			local frame = if camera ~= nil then camera.CFrame else CFrame.identity
			local bearing = bearingOf(frame, lastOrigin or frame.Position, from)
			if bearing == nil then
				-- It came from where the player stands (a lob landing on them): there is no
				-- way to point at that, and a pointer straight ahead would be a lie.
				return
			end
			-- A hit from where a live pointer already points renews it; otherwise a free
			-- pointer, or the oldest.
			local chosen: Pointer? = nil
			local oldest: Pointer? = nil
			for _, pointer in pointers do
				if pointer.active then
					local apart = math.abs((bearing - pointer.bearing + 180) % 360 - 180)
					if apart <= Theme.COMBAT_RANGE_HURT_POINTER_MERGE_DEGREES then
						chosen = pointer
						break
					end
					if oldest == nil or pointer.startedAt < oldest.startedAt then
						oldest = pointer
					end
				elseif chosen == nil then
					chosen = pointer
				end
			end
			local pointer = chosen or oldest
			if pointer == nil then
				return
			end
			pointer.from = from
			pointer.startedAt = now
			pointer.bearing = bearing
			pointer.active = true
			placePointer(pointer)
			pointer.frame.Visible = true
		end,
		SetDown = function(upAt: number?, seconds: number)
			downUntil = upAt
			downSeconds = seconds
			tenthsShown = -1
			timerShown = -1
			banner.Visible = upAt ~= nil
			if upAt == nil then
				-- The get-up beat: the screen clears at once and the bar pops as it refills.
				flash = 0
				popAt = os.clock()
			end
		end,
		Step = function(deltaTime: number, origin: Vector3?)
			local now = os.clock()
			clock += deltaTime
			lastOrigin = origin
			local down = stepBanner()
			stepFlash(deltaTime, down)
			stepBar(now, deltaTime)
			stepPointers(now, origin)
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			root:Destroy()
		end,
	}
	return handle
end

return VitalsHud
