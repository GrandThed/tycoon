--!strict
-- Proving Grounds crosshair (P1 contract, docs/INTERFACES.md "P1 contracts" → Feedback layers,
-- docs/COMBAT_DESIGN.md §3 and §4 layer 1). A centre dot, four ticks pushed out by the live
-- bloom, a bloom ring for ranged weapons, an ADS tint, and the three hit markers: a tick
-- burst on every hit, a bigger yellow one on a crit, a red X on a kill. The whole reticle
-- "kicks" (a short scale pop) on every hit.
--
-- Pure display: FeedbackController converts the bloom angle into screen pixels and decides
-- which marker a strike earns. The parent ScreenGui must ignore the GUI inset so the dot
-- sits on the camera's true centre line, which is the ray the server resolves.
--
-- Nothing here takes input (every frame is inactive), so aiming drags on the right half of
-- a phone pass straight through it.

local TweenService = game:GetService("TweenService")

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent:WaitForChild("Motion"))

export type CrosshairHandle = {
	-- gapPixels = bloom radius in physical screen px (nil = melee: fixed gap, no ring).
	Update: (gapPixels: number?, ads: boolean, visible: boolean) -> (),
	-- Every hit gets the tick burst (yellow and bigger when any hit was a crit); a kill adds the X.
	Mark: (crit: boolean, kill: boolean, strength: number) -> (),
	-- The server refused the last attack: the reticle greys out once.
	Refused: () -> (),
	SetLayout: (scale: number) -> (),
	Destroy: () -> (),
}

local Crosshair = {}

local function bar(name: string, parent: Instance, color: Color3): Frame
	local frame = Create("Frame", {
		Name = name,
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	-- A dark outline keeps a white tick readable against a bright sky or a white flash.
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = 1,
		Transparency = Theme.COMBAT_RETICLE_STROKE_TRANSPARENCY,
		Parent = frame,
	})
	return frame
end

function Crosshair.new(parent: Instance): CrosshairHandle
	local scale = 1
	local refusedUntil = 0
	-- One live tween per instance: a newer mark replaces the fade or kick still running.
	local activeTweens: { [Instance]: Tween? } = {}

	local root = Create("Frame", {
		Name = "Crosshair",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(
			Theme.COMBAT_RANGE_CROSSHAIR_SIZE,
			Theme.COMBAT_RANGE_CROSSHAIR_SIZE
		),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local layoutScale = Create("UIScale", { Parent = root }) :: UIScale

	-- A nested frame with its own UIScale carries the kick, so the pop multiplies the layout
	-- scale instead of fighting SetLayout for one property.
	local reticle = Create("Frame", {
		Name = "Reticle",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = root,
	}) :: Frame
	local kickScale = Create("UIScale", { Parent = reticle }) :: UIScale

	local dot = bar("Dot", reticle, Theme.COLOR_TEXT)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(Theme.COMBAT_RANGE_CROSSHAIR_DOT, Theme.COMBAT_RANGE_CROSSHAIR_DOT)
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })

	local ring = Create("Frame", {
		Name = "BloomRing",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = reticle,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	local ringStroke = Create("UIStroke", {
		Color = Theme.COLOR_TEXT,
		Thickness = 1,
		Transparency = Theme.COMBAT_RANGE_BLOOM_RING_TRANSPARENCY,
		Parent = ring,
	}) :: UIStroke

	-- Up, down, left, right: each tick sits `gap` px from the centre along its axis.
	local tickAxes =
		{ Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) }
	local ticks: { Frame } = {}
	for index, axis in tickAxes do
		local tick = bar("Tick" .. tostring(index), reticle, Theme.COLOR_TEXT)
		tick.Size = if axis.X == 0
			then UDim2.fromOffset(
				Theme.COMBAT_RANGE_CROSSHAIR_TICK_THICKNESS,
				Theme.COMBAT_RANGE_CROSSHAIR_TICK_LENGTH
			)
			else UDim2.fromOffset(
				Theme.COMBAT_RANGE_CROSSHAIR_TICK_LENGTH,
				Theme.COMBAT_RANGE_CROSSHAIR_TICK_THICKNESS
			)
		table.insert(ticks, tick)
	end

	-- Hit marker: four short diagonal bars around the centre (the classic shooter tick
	-- burst). Its own UIScale grows it for a crit and with the hitMarker strength.
	-- CanvasGroups, so one GroupTransparency fades each bar together with its outline.
	local marker = Create("CanvasGroup", {
		Name = "HitMarker",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = reticle,
	}) :: CanvasGroup
	local markerScale = Create("UIScale", { Parent = marker }) :: UIScale
	local markerBars: { Frame } = {}
	local diagonal = Theme.COMBAT_RANGE_MARKER_OFFSET + Theme.COMBAT_RANGE_MARKER_LENGTH / 2
	for _, corner in
		{ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) }
	do
		local markBar = bar("Mark", marker, Theme.COLOR_TEXT)
		markBar.Size =
			UDim2.fromOffset(Theme.COMBAT_RANGE_MARKER_LENGTH, Theme.COMBAT_RANGE_MARKER_THICKNESS)
		local offset = corner * (diagonal / math.sqrt(2))
		markBar.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		markBar.Rotation = if corner.X * corner.Y > 0 then 45 else -45
		table.insert(markerBars, markBar)
	end

	-- Kill X: two long red bars through the centre, over everything else.
	local killX = Create("CanvasGroup", {
		Name = "KillX",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = reticle,
	}) :: CanvasGroup
	local killScale = Create("UIScale", { Parent = killX }) :: UIScale
	local killBars: { Frame } = {}
	for _, rotation in { 45, -45 } do
		local killBar = bar("X", killX, Theme.COMBAT_RANGE_KILL_COLOR)
		killBar.Position = UDim2.fromScale(0.5, 0.5)
		killBar.Size =
			UDim2.fromOffset(Theme.COMBAT_RANGE_KILL_X_LENGTH, Theme.COMBAT_RANGE_KILL_X_THICKNESS)
		killBar.Rotation = rotation
		table.insert(killBars, killBar)
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

	local function flash(group: CanvasGroup, bars: { Frame }, color: Color3, seconds: number): ()
		for _, item in bars do
			item.BackgroundColor3 = color
		end
		group.GroupTransparency = 0
		-- Eased in, so the marker holds before it fades: one that starts fading at once is
		-- gone before the eye lands on it. It is information, so reduce motion keeps it whole.
		play(
			group,
			TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
	end

	local handle: CrosshairHandle = {
		Update = function(gapPixels: number?, ads: boolean, visible: boolean)
			root.Visible = visible
			if not visible then
				return
			end
			local gap: number
			if gapPixels == nil then
				gap = Theme.COMBAT_RANGE_CROSSHAIR_MELEE_GAP
				ring.Visible = false
			else
				-- Pixels arrive in physical screen px; the reticle is drawn in design px.
				gap = math.clamp(
					gapPixels / math.max(scale, 0.01),
					Theme.COMBAT_RANGE_CROSSHAIR_MIN_GAP,
					Theme.COMBAT_RANGE_CROSSHAIR_MAX_GAP
				)
				ring.Visible = true
				ring.Size = UDim2.fromOffset(gap * 2, gap * 2)
			end
			local offset = gap + Theme.COMBAT_RANGE_CROSSHAIR_TICK_LENGTH / 2
			for index, axis in tickAxes do
				ticks[index].Position = UDim2.new(0.5, axis.X * offset, 0.5, axis.Y * offset)
			end
			-- ADS reads as a colour change on the ticks and ring: the gap shrinks on its own,
			-- because InputController already multiplies the bloom by adsBloomMult.
			local color = if os.clock() < refusedUntil
				then Theme.COMBAT_RANGE_REFUSED_COLOR
				elseif ads then Theme.COLOR_ACCENT
				else Theme.COLOR_TEXT
			for _, tick in ticks do
				tick.BackgroundColor3 = color
			end
			dot.BackgroundColor3 = if os.clock() < refusedUntil
				then Theme.COMBAT_RANGE_REFUSED_COLOR
				else Theme.COLOR_TEXT
			ringStroke.Color = color
		end,
		Mark = function(crit: boolean, kill: boolean, strength: number)
			if strength <= 0 then
				return
			end
			local size = math.clamp(
				strength,
				Theme.COMBAT_RANGE_MARKER_MIN_SCALE,
				Theme.COMBAT_RANGE_MARKER_MAX_SCALE
			)
			markerScale.Scale = if crit then size * Theme.COMBAT_RANGE_CRIT_MARKER_SCALE else size
			flash(
				marker,
				markerBars,
				if crit then Theme.COMBAT_RANGE_CRIT_COLOR else Theme.COLOR_TEXT,
				Theme.COMBAT_RANGE_MARKER_SECONDS
			)
			if kill then
				killScale.Scale = size
				flash(
					killX,
					killBars,
					Theme.COMBAT_RANGE_KILL_COLOR,
					Theme.COMBAT_RANGE_KILL_X_SECONDS
				)
			end
			-- The kick: pop outward and settle. Reduce motion keeps a smaller pop.
			local kick = 1 + (Theme.COMBAT_RANGE_KICK_SCALE - 1) * size
			if Theme.reducedMotion then
				kick = 1 + (kick - 1) * Theme.REDUCED_MOTION_FACTOR
			end
			kickScale.Scale = kick
			play(
				kickScale,
				Motion.Info(Theme.COMBAT_RANGE_KICK_SECONDS, Enum.EasingStyle.Back),
				{ Scale = 1 }
			)
		end,
		Refused = function()
			refusedUntil = os.clock() + Theme.COMBAT_RANGE_REFUSED_SECONDS
		end,
		SetLayout = function(nextScale: number)
			scale = nextScale
			layoutScale.Scale = nextScale
		end,
		Destroy = function()
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

return Crosshair
