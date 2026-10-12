--!strict
-- The boss bar of the Proving Grounds (docs/INTERFACES.md "P4 contracts" -> "Stop 2 — the
-- Colossus", "The boss bar"). One row: the boss's name written on its health, a mark where
-- its second phase begins, and "ENRAGED" from the moment it crosses that mark.
--
-- Pure display. The caller reads the boss off CrowdRenderer (the health share the crowd
-- snapshot already carries) and pushes it in every frame through Update; nothing here
-- connects, tweens or decides anything, and a frame writes only what changed.
--
-- Three beats, none of them a message from the server:
--  * shown: the bar drops open when a boss is first seen;
--  * ENRAGED: the bar thumps taller, flashes white, changes colour and STAYS changed, with the
--    word on it. The colour and the word are information and are never gated; only the
--    thump's size is halved under Theme.reducedMotion;
--  * dead: the bar empties, flashes and folds shut. A boss that is simply taken away (a set
--    load) has no ending to show: the bar goes at once.
--
-- Placement (SetLayout; the bar lives in the HUD ScreenGui that respects the top bar and the
-- device's safe area, the same one the RangePanel is in). Checked at 1920x1080, 667x375 and
-- 375x667 against the RangePanel's tab and readouts, the crosshair and its counters, the
-- health bar, the pointer ring and the thumb clusters:
--  * where the strip left of the RangePanel's column is wide enough (a monitor, a landscape
--    phone): at the top edge, on the screen's centre line if that fits, else slid left until
--    it clears the column;
--  * where it is not (a portrait phone, whose top the panel spans): full width, just under
--    the panel's readouts, still well above the crosshair.
-- It never takes input (Active = false), so no aiming drag is swallowed.

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type BossBarDeps = {
	-- The boss on show has just entered its second phase (once per boss).
	onEnrage: () -> (),
}

export type BossBarHandle = {
	-- scale = the HUD's UI scale; viewportSize = the parent ScreenGui's size in px; panelLeft =
	-- the left edge, in px, of the column kept for the RangePanel (the viewport's width when
	-- there is none); panelBottom = the bottom edge, in px, of what that panel shows shut.
	-- Returns the bar's own bottom edge in px, for whatever must keep under it.
	SetLayout: (
		scale: number,
		viewportSize: Vector2,
		panelLeft: number,
		panelBottom: number
	) -> number,
	-- id = the boss on show (nil = none); share = its health, 0-1 (0 = dead); enrageAt = the
	-- share its second phase begins at (0 = it has none); enraged = it is in it.
	Update: (
		deltaTime: number,
		id: number?,
		name: string,
		share: number,
		enrageAt: number,
		enraged: boolean
	) -> (),
	Destroy: () -> (),
}

local BossBar = {}

local function corner(instance: Instance): ()
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS / 2), Parent = instance }
	)
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

local function text(name: string, alignment: Enum.TextXAlignment, parent: Instance): TextLabel
	local label = Create("TextLabel", {
		Name = name,
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_RANGE_BOSS_BAR_TEXT,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = alignment,
		Text = "",
		ZIndex = 4,
		Parent = parent,
	}) :: TextLabel
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS / 2,
		Parent = label,
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, Theme.ROW_CORNER_RADIUS),
		PaddingRight = UDim.new(0, Theme.ROW_CORNER_RADIUS),
		Parent = label,
	})
	return label
end

function BossBar.new(parent: Instance, deps: BossBarDeps): BossBarHandle
	local root = plain("BossBar", Theme.COLOR_BG, parent)
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Size = UDim2.fromOffset(Theme.COMBAT_RANGE_BOSS_BAR_WIDTH, 0)
	root.BackgroundTransparency = Theme.COMBAT_RANGE_VITALS_BG_TRANSPARENCY
	root.ClipsDescendants = true
	root.Visible = false
	corner(root)
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = root,
	})
	-- The chunk just lost stays behind the fill for a moment, as on the player's own bar.
	local lost = plain("Lost", Theme.COMBAT_RANGE_VITALS_LOST_COLOR, root)
	lost.Size = UDim2.fromScale(1, 1)
	corner(lost)
	local fill = plain("Fill", Theme.COMBAT_RANGE_BOSS_BAR_FILL_COLOR, root)
	fill.Size = UDim2.fromScale(1, 1)
	corner(fill)
	local mark = plain("EnrageMark", Theme.COLOR_TEXT, root)
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Size = UDim2.new(0, Theme.COMBAT_RANGE_BOSS_BAR_MARK_WIDTH, 1, 0)
	mark.ZIndex = 2
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS / 2,
		Parent = mark,
	})
	local flashFrame = plain("Flash", Color3.new(1, 1, 1), root)
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.ZIndex = 3
	local title = text("Name", Enum.TextXAlignment.Left, root)
	local phase = text("Phase", Enum.TextXAlignment.Right, root)
	phase.Text = Theme.COMBAT_RANGE_BOSS_BAR_ENRAGED_LABEL
	phase.Visible = false

	local shownId: number? = nil
	-- The boss whose death beat has played: it is still reported, dead, for the rest of its
	-- death flight, and must not open the bar again.
	local endedId: number? = nil
	local visible = false
	local target = 1
	local fillShare = 1
	local lostShare = 1
	local lostHoldUntil = 0
	local fillShown = -1
	local lostShown = -1
	local markShown = -1
	local enragedShown = false
	local shownAt = -math.huge
	local popAt = -math.huge
	local flashAt = -math.huge
	local deadAt: number? = nil
	local heightShown = -1
	local flashShown = 1

	local function hide(): ()
		if deadAt ~= nil then
			endedId = shownId
		end
		shownId = nil
		visible = false
		deadAt = nil
		root.Visible = false
	end

	local function paintPhase(enraged: boolean): ()
		enragedShown = enraged
		fill.BackgroundColor3 = if enraged
			then Theme.COMBAT_RANGE_BOSS_BAR_ENRAGED_COLOR
			else Theme.COMBAT_RANGE_BOSS_BAR_FILL_COLOR
		phase.Visible = enraged
	end

	local function show(id: number, name: string, share: number, enraged: boolean, now: number): ()
		shownId = id
		visible = true
		deadAt = nil
		target = share
		fillShare = share
		lostShare = share
		fillShown = -1
		lostShown = -1
		shownAt = now
		popAt = -math.huge
		flashAt = -math.huge
		title.Text = string.upper(name)
		-- Already enraged when first seen (this client joined late): the look, with no beat.
		paintPhase(enraged)
		root.Visible = true
	end

	local function stepFill(now: number, deltaTime: number): ()
		if target < fillShare then
			lostShare = math.max(lostShare, fillShare)
			fillShare = target
			lostHoldUntil = now + Theme.COMBAT_RANGE_VITALS_LOST_HOLD_SECONDS
		elseif target > fillShare then
			fillShare = target
		end
		if lostShare > fillShare and now >= lostHoldUntil then
			lostShare = math.max(
				lostShare - Theme.COMBAT_RANGE_VITALS_LOST_DRAIN_PER_SECOND * deltaTime,
				fillShare
			)
		elseif lostShare < fillShare then
			lostShare = fillShare
		end
		if math.abs(fillShare - fillShown) > 0.0005 then
			fillShown = fillShare
			fill.Size = UDim2.fromScale(fillShare, 1)
		end
		if math.abs(lostShare - lostShown) > 0.0005 then
			lostShown = lostShare
			lost.Size = UDim2.fromScale(lostShare, 1)
		end
	end

	local handle: BossBarHandle = {
		SetLayout = function(
			scale: number,
			viewportSize: Vector2,
			panelLeft: number,
			panelBottom: number
		): number
			local margin = Theme.SCREEN_MARGIN * scale
			local width = Theme.COMBAT_RANGE_BOSS_BAR_WIDTH * scale
			local top = margin
			local centreX = viewportSize.X / 2
			-- The strip at the top that the RangePanel's column leaves free.
			local band = panelLeft - 2 * margin
			if band >= Theme.COMBAT_RANGE_BOSS_BAR_MIN_WIDTH * scale then
				width = math.min(width, band)
				centreX = math.clamp(centreX, margin + width / 2, panelLeft - margin - width / 2)
			else
				width = math.min(width, viewportSize.X - 2 * margin)
				top = panelBottom + margin
			end
			uiScale.Scale = scale
			root.Position = UDim2.fromOffset(centreX, top)
			root.Size = UDim2.fromOffset(width / scale, root.Size.Y.Offset)
			return top + Theme.COMBAT_RANGE_BOSS_BAR_HEIGHT * scale
		end,
		Update = function(
			deltaTime: number,
			id: number?,
			name: string,
			share: number,
			enrageAt: number,
			enraged: boolean
		)
			local now = os.clock()
			if id == nil then
				-- Gone with no death seen: nothing to end. A death beat under way plays out.
				if visible and deadAt == nil then
					hide()
				end
			elseif id ~= endedId then
				if id ~= shownId then
					show(id, name, share, enraged, now)
				end
				target = math.clamp(share, 0, 1)
				if math.abs(enrageAt - markShown) > 0.0005 then
					markShown = enrageAt
					mark.Visible = enrageAt > 0 and enrageAt < 1
					mark.Position = UDim2.fromScale(enrageAt, 0)
				end
				if enraged and not enragedShown then
					paintPhase(true)
					popAt = now
					flashAt = now
					deps.onEnrage()
				end
				if target <= 0 and deadAt == nil then
					deadAt = now
					flashAt = now
				end
			end
			if not visible then
				return
			end
			stepFill(now, deltaTime)

			-- One height carries all three beats: it opens, thumps on the enrage and folds
			-- shut on the death. Growing downward only, it never widens into its neighbours.
			local opened =
				math.clamp((now - shownAt) / Theme.COMBAT_RANGE_BOSS_BAR_SHOW_SECONDS, 0, 1)
			local thump = math.max(0, 1 - (now - popAt) / Theme.COMBAT_RANGE_BOSS_BAR_POP_SECONDS)
			local grow = (Theme.COMBAT_RANGE_BOSS_BAR_POP_SCALE - 1)
				* (if Theme.reducedMotion then Theme.REDUCED_MOTION_FACTOR else 1)
			local shut = 0
			local died = deadAt
			if died ~= nil then
				local u = (now - died) / Theme.COMBAT_RANGE_BOSS_BAR_DEATH_SECONDS
				if u >= 1 then
					hide()
					return
				end
				shut = math.clamp(
					(u - Theme.COMBAT_RANGE_BOSS_BAR_DEATH_HOLD_SHARE)
						/ (1 - Theme.COMBAT_RANGE_BOSS_BAR_DEATH_HOLD_SHARE),
					0,
					1
				)
			end
			local height = math.round(
				Theme.COMBAT_RANGE_BOSS_BAR_HEIGHT
					* opened
					* (1 + grow * thump * thump)
					* (1 - shut)
			)
			if height ~= heightShown then
				heightShown = height
				root.Size = UDim2.fromOffset(root.Size.X.Offset, height)
			end
			local lit = math.max(0, 1 - (now - flashAt) / Theme.COMBAT_RANGE_BOSS_BAR_FLASH_SECONDS)
			local flashed = 1 - (1 - Theme.COMBAT_RANGE_BOSS_BAR_FLASH_TRANSPARENCY) * lit * lit
			if math.abs(flashed - flashShown) > 0.01 then
				flashShown = flashed
				flashFrame.BackgroundTransparency = flashed
			end
		end,
		Destroy = function()
			root:Destroy()
		end,
	}
	return handle
end

return BossBar
