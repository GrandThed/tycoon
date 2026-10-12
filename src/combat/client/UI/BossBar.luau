--!strict
-- The boss bar of the Proving Grounds (docs/INTERFACES.md "P4 contracts" -> "Stop 2 — the
-- Colossus", "The boss bar", and "Stop 3 — the Warlord and his guard"). The health row: the
-- boss's name written on its health, a mark where its second phase begins, and that phase's
-- word from the moment it begins. For a boss with a plate, a thin plate row over it (the
-- elite's overhead bar, written large), and for one with a guard, a pip per guard.
--
-- Pure display. The caller reads the boss off CrowdRenderer (the shares the crowd snapshot
-- already carries) and pushes it in every frame through Update; nothing here connects, tweens
-- or decides anything, and a frame writes only what changed.
--
-- The beats, none of them a message from the server:
--  * shown: the bar drops open when a boss is first seen;
--  * the second phase: the health row thumps taller, flashes white, changes colour and STAYS
--    changed, with the phase's word on it ("ENRAGED"; for a boss with a guard, "DUEL"). The
--    colour and the word are information and are never gated; only the thump's size is halved
--    under Theme.reducedMotion;
--  * the guard falls: the plate row, which was the guard's colour while they protected it,
--    flashes and turns the plate's own colour: it can be broken now. The pips went out one by
--    one before it;
--  * the plate breaks: its row empties and folds away. For a boss whose second phase begins
--    there, that is the same moment as the beat above: the siege is over;
--  * dead: the bar empties, flashes and folds shut. A boss that is simply taken away (a set
--    load) has no ending to show: the bar goes at once.
--
-- Placement (SetLayout; the bar lives in the HUD ScreenGui that respects the top bar and the
-- device's safe area, the same one the RangePanel is in). Checked at 1920x1080, 667x375 and
-- 375x667, at its full height with the plate row, against the RangePanel's tab and readouts,
-- the crosshair and its counters, the health bar, the pointer ring and the thumb clusters:
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

-- The boss on show, as CrowdRenderer.GetBoss reports it. health = its health share, 0 = dead;
-- plate = its plate's share, -1 = it has no plate; enrageAt = the health share its second phase
-- begins at (0 = it has none); label = that phase's word; guards of guardTotal = its guard,
-- living and called; guarded = its plate cannot be touched now.
export type Boss = {
	id: number,
	name: string,
	health: number,
	plate: number,
	enrageAt: number,
	enraged: boolean,
	label: string,
	guards: number,
	guardTotal: number,
	guarded: boolean,
}

export type BossBarHandle = {
	-- scale = the HUD's UI scale; viewportSize = the parent ScreenGui's size in px; panelLeft =
	-- the left edge, in px, of the column kept for the RangePanel (the viewport's width when
	-- there is none); panelBottom = the bottom edge, in px, of what that panel shows shut.
	-- Returns the bar's own bottom edge in px at its tallest (with a plate row), for whatever
	-- must keep under it.
	SetLayout: (
		scale: number,
		viewportSize: Vector2,
		panelLeft: number,
		panelBottom: number
	) -> number,
	-- boss = the boss on show this frame; nil = none.
	Update: (deltaTime: number, boss: Boss?) -> (),
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

-- A row of the bar: a dark track that clips what it holds, outlined.
local function track(name: string, parent: Instance): Frame
	local row = plain(name, Theme.COLOR_BG, parent)
	row.BackgroundTransparency = Theme.COMBAT_RANGE_VITALS_BG_TRANSPARENCY
	row.ClipsDescendants = true
	corner(row)
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = row,
	})
	return row
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
	local root = Create("Frame", {
		Name = "BossBar",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(Theme.COMBAT_RANGE_BOSS_BAR_WIDTH, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale

	-- The plate row: there only for a boss with a plate, and only while the plate lasts.
	local plateRow = track("Plate", root)
	plateRow.Size = UDim2.fromScale(1, 0)
	local plateFill = plain("Fill", Theme.COMBAT_RANGE_PLATE_COLOR, plateRow)
	plateFill.Size = UDim2.fromScale(1, 1)
	corner(plateFill)
	local plateFlash = plain("Flash", Color3.new(1, 1, 1), plateRow)
	plateFlash.Size = UDim2.fromScale(1, 1)
	plateFlash.BackgroundTransparency = 1
	plateFlash.ZIndex = 2

	-- The health row.
	local bar = track("Health", root)
	bar.Size = UDim2.fromScale(1, 0)
	-- The chunk just lost stays behind the fill for a moment, as on the player's own bar.
	local lost = plain("Lost", Theme.COMBAT_RANGE_VITALS_LOST_COLOR, bar)
	lost.Size = UDim2.fromScale(1, 1)
	corner(lost)
	local fill = plain("Fill", Theme.COMBAT_RANGE_BOSS_BAR_FILL_COLOR, bar)
	fill.Size = UDim2.fromScale(1, 1)
	corner(fill)
	local mark = plain("EnrageMark", Theme.COLOR_TEXT, bar)
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Size = UDim2.new(0, Theme.COMBAT_RANGE_BOSS_BAR_MARK_WIDTH, 1, 0)
	mark.ZIndex = 2
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS / 2,
		Parent = mark,
	})
	local flashFrame = plain("Flash", Color3.new(1, 1, 1), bar)
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.ZIndex = 3
	local title = text("Name", Enum.TextXAlignment.Left, bar)
	local phase = text("Phase", Enum.TextXAlignment.Right, bar)
	phase.Visible = false
	-- The guard: one pip each at the row's right end, lit while that guard lives. They share
	-- the place of the phase's word, which only ever shows once the guard is gone.
	local pips: { Frame } = {}

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
	local labelShown = ""
	local shownAt = -math.huge
	local popAt = -math.huge
	local flashAt = -math.huge
	local deadAt: number? = nil
	local barHeightShown = -1
	local flashShown = 1
	-- The plate row: how far it is open (0-1, eased), what it last showed.
	local plateOpen = 0
	local plateHeightShown = -1
	local plateShown = -1
	local guardedShown = false
	local plateFlashAt = -math.huge
	local plateFlashShown = 1
	local pipsLit = -1
	local totalShown = -1

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

	local function paintGuarded(guarded: boolean): ()
		guardedShown = guarded
		plateFill.BackgroundColor3 = if guarded
			then Theme.COMBAT_RANGE_WARD_COLOR
			else Theme.COMBAT_RANGE_PLATE_COLOR
	end

	local function show(boss: Boss, now: number): ()
		shownId = boss.id
		visible = true
		deadAt = nil
		target = boss.health
		fillShare = boss.health
		lostShare = boss.health
		fillShown = -1
		lostShown = -1
		shownAt = now
		popAt = -math.huge
		flashAt = -math.huge
		plateFlashAt = -math.huge
		plateOpen = if boss.plate > 0 then 1 else 0
		plateShown = -1
		pipsLit = -1
		totalShown = -1
		title.Text = string.upper(boss.name)
		-- Already in its second phase, or already guarded, when first seen (this client
		-- joined late): the look, with no beat.
		paintPhase(boss.enraged)
		paintGuarded(boss.guarded)
		root.Visible = true
	end

	-- A pip per guard, the first `lit` of them alight. Pips are made once and kept.
	local function paintPips(total: number, lit: number): ()
		local size = Theme.COMBAT_RANGE_BOSS_BAR_PIP
		local gap = Theme.COMBAT_RANGE_BOSS_BAR_PIP_GAP
		while #pips < total do
			local pip = plain("Guard", Theme.COMBAT_RANGE_WARD_COLOR, bar)
			pip.AnchorPoint = Vector2.new(1, 0.5)
			pip.Size = UDim2.fromOffset(size, size)
			pip.Position =
				UDim2.new(1, -(Theme.ROW_CORNER_RADIUS + #pips * (size + gap) + gap), 0.5, 0)
			-- Turned on its point: a diamond is never mistaken for a piece of the bar.
			pip.Rotation = 45
			pip.ZIndex = 4
			Create("UIStroke", {
				Color = Theme.COLOR_TEXT_DARK,
				Thickness = Theme.STROKE_THICKNESS / 2,
				Parent = pip,
			})
			table.insert(pips, pip)
		end
		-- The lit ones are the ones nearest the name, so the row empties toward the right.
		for index, pip in pips do
			pip.Visible = index <= total
			pip.BackgroundTransparency = if total - index < lit
				then 0
				else Theme.COMBAT_RANGE_BOSS_BAR_PIP_DEAD_TRANSPARENCY
		end
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
			return top
				+ (
						Theme.COMBAT_RANGE_BOSS_BAR_PLATE_HEIGHT
						+ Theme.COMBAT_RANGE_BOSS_BAR_PLATE_GAP
						+ Theme.COMBAT_RANGE_BOSS_BAR_HEIGHT
					)
					* scale
		end,
		Update = function(deltaTime: number, boss: Boss?)
			local now = os.clock()
			local wantsPlate = false
			if boss == nil then
				-- Gone with no death seen: nothing to end. A death beat under way plays out.
				if visible and deadAt == nil then
					hide()
				end
			elseif boss.id ~= endedId then
				if boss.id ~= shownId then
					show(boss, now)
				end
				target = math.clamp(boss.health, 0, 1)
				local enrageAt = boss.enrageAt
				if math.abs(enrageAt - markShown) > 0.0005 then
					markShown = enrageAt
					mark.Visible = enrageAt > 0 and enrageAt < 1
					mark.Position = UDim2.fromScale(enrageAt, 0)
				end
				if boss.label ~= labelShown then
					labelShown = boss.label
					phase.Text = boss.label
				end
				if boss.enraged and not enragedShown then
					paintPhase(true)
					popAt = now
					flashAt = now
					deps.onEnrage()
				end
				if target <= 0 and deadAt == nil then
					deadAt = now
					flashAt = now
				end

				-- The plate row and the guard's pips.
				local plate = boss.plate
				wantsPlate = plate > 0 and deadAt == nil
				if plate >= 0 and math.abs(plate - plateShown) > 0.0005 then
					if plateShown > 0 and plate <= 0 then
						-- Broken: the row flashes as it folds away.
						plateFlashAt = now
					end
					plateShown = plate
					plateFill.Size = UDim2.fromScale(math.clamp(plate, 0, 1), 1)
				end
				if boss.guarded ~= guardedShown then
					if guardedShown then
						-- The last of the guard fell: the plate is the plate's colour again,
						-- with a flash that says it can be broken now.
						plateFlashAt = now
					end
					paintGuarded(boss.guarded)
				end
				local total = if boss.enraged or deadAt ~= nil
					then 0
					else math.min(boss.guardTotal, Theme.COMBAT_RANGE_BOSS_BAR_MAX_PIPS)
				local lit = math.min(boss.guards, total)
				if total ~= totalShown or lit ~= pipsLit then
					totalShown = total
					pipsLit = lit
					paintPips(total, lit)
				end
			end
			if not visible then
				return
			end
			stepFill(now, deltaTime)

			-- The health row's height carries three beats: it opens, thumps on the second
			-- phase and folds shut on the death. Growing downward only, it never widens into
			-- its neighbours.
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
			local barHeight = math.round(
				Theme.COMBAT_RANGE_BOSS_BAR_HEIGHT
					* opened
					* (1 + grow * thump * thump)
					* (1 - shut)
			)
			-- The plate row eases open while there is a plate and folds away when it breaks,
			-- taking its gap with it, so the health row slides up into its place.
			local wanted = if wantsPlate then 1 else 0
			plateOpen += (wanted - plateOpen) * (1 - math.exp(
				-Theme.COMBAT_RANGE_BOSS_BAR_PLATE_FOLD_RATE * deltaTime
			))
			if math.abs(wanted - plateOpen) < 0.01 then
				plateOpen = wanted
			end
			local plateHeight =
				math.round(Theme.COMBAT_RANGE_BOSS_BAR_PLATE_HEIGHT * plateOpen * opened)
			if barHeight ~= barHeightShown or plateHeight ~= plateHeightShown then
				barHeightShown = barHeight
				plateHeightShown = plateHeight
				local barTop = if plateHeight > 0
					then plateHeight + Theme.COMBAT_RANGE_BOSS_BAR_PLATE_GAP
					else 0
				plateRow.Visible = plateHeight > 0
				plateRow.Size = UDim2.new(1, 0, 0, plateHeight)
				bar.Position = UDim2.fromOffset(0, barTop)
				bar.Size = UDim2.new(1, 0, 0, barHeight)
				root.Size = UDim2.fromOffset(root.Size.X.Offset, barTop + barHeight)
			end
			local lit = math.max(0, 1 - (now - flashAt) / Theme.COMBAT_RANGE_BOSS_BAR_FLASH_SECONDS)
			local flashed = 1 - (1 - Theme.COMBAT_RANGE_BOSS_BAR_FLASH_TRANSPARENCY) * lit * lit
			if math.abs(flashed - flashShown) > 0.01 then
				flashShown = flashed
				flashFrame.BackgroundTransparency = flashed
			end
			local plateLit =
				math.max(0, 1 - (now - plateFlashAt) / Theme.COMBAT_RANGE_BOSS_BAR_FLASH_SECONDS)
			local plateFlashed = 1
				- (1 - Theme.COMBAT_RANGE_BOSS_BAR_FLASH_TRANSPARENCY) * plateLit * plateLit
			if math.abs(plateFlashed - plateFlashShown) > 0.01 then
				plateFlashShown = plateFlashed
				plateFlash.BackgroundTransparency = plateFlashed
			end
		end,
		Destroy = function()
			root:Destroy()
		end,
	}
	return handle
end

return BossBar
