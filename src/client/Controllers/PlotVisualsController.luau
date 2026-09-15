--!strict
-- Client-side plot presentation (docs/INTERFACES.md, M3 client contracts): the reveal
-- tween on a purchase and the floating level-up text, both driven by the server's FxEvent.
-- Touches only the local player's own Workspace/Plots/Plot_<i>/Buildings/Building_<slotId>
-- copies — never pads, never other plots — and nothing here replicates back. Every
-- instance it creates is destroyed when its effect ends. eraAdvance/rebirth belong to
-- UIController (two listeners on one RemoteEvent, disjoint kinds).
--
-- M6: the level-up pitch counts milestones from the player's own list (Extra Milestone),
-- so this controller keeps a copy of the pushed legacyShop state from StateChanged; and
-- under reduce-motion the server's advanceFireworks ParticleEmitter (replicated under the
-- owner's monument) is disabled on the local copy only. World cosmetics are otherwise
-- entirely server-side.
--
-- M7: stageUp plays a growth pop on the model whose Stage<n> the server just swapped. It
-- arrives right after the milestone levelUp for the same crossing, so the shared fanfare
-- (milestone sound, flash, burst) is deduped per slot; the pop never fights the reveal
-- tween because both register in scaleTweens by slotId.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Economy = require(sharedFolder:WaitForChild("Economy"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Motion = require(uiFolder:WaitForChild("Motion"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

-- World naming frozen since M1 (docs/INTERFACES.md).
local PLOT_ATTRIBUTE = "PlotIndex"
local PLOTS_FOLDER = "Plots"
local PLOT_PREFIX = "Plot_"
local BUILDINGS_FOLDER = "Buildings"
local BUILDING_PREFIX = "Building_"

local player = Players.LocalPlayer

-- Mirrors state.legacyShop from snapshots/deltas; nil until the first snapshot, which
-- Economy.MilestoneLevels treats as "no perks" (the game list).
local legacyShopState: Types.LegacyShopState? = nil

-- The reduce-motion emitter watch on the local plot; replaced (never doubled) if the
-- PlotIndex attribute changes again.
local plotWatch: RBXScriptConnection? = nil

-- One scale animation per building at a time. A reveal owns the slot until it completes
-- (a stageUp then skips its pop); a new pop cancels a pop still settling.
type ScaleTween = { kind: "reveal" | "pop", cancel: () -> () }
local scaleTweens: { [string]: ScaleTween } = {}

-- os.clock of the last milestone fanfare per slot, so levelUp(milestone) and stageUp for
-- the same crossing play the sound/flash/burst once between them.
local lastMilestoneFx: { [string]: number } = {}

local function localBuildingsFolder(): Instance?
	local plotIndex = player:GetAttribute(PLOT_ATTRIBUTE)
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plots = Workspace:FindFirstChild(PLOTS_FOLDER)
	if plots == nil then
		return nil
	end
	local plot = plots:FindFirstChild(PLOT_PREFIX .. tostring(plotIndex))
	if plot == nil then
		return nil
	end
	return plot:FindFirstChild(BUILDINGS_FOLDER)
end

-- The part effects attach to: the placeholder itself, or a model's primary/first part.
local function anchorPart(building: Instance): BasePart?
	if building:IsA("BasePart") then
		return building
	end
	if building:IsA("Model") then
		return building.PrimaryPart or building:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Studs from the anchor part's position up to the building's top edge.
local function topOffset(building: Instance, part: BasePart): number
	if building:IsA("Model") then
		local boundsCFrame, boundsSize = building:GetBoundingBox()
		return boundsCFrame.Position.Y + boundsSize.Y / 2 - part.Position.Y
	end
	return part.Size.Y / 2
end

local function countMilestones(toLevel: number): number
	local count = 0
	local milestoneLevels = Economy.MilestoneLevels(
		Catalog.GetLegacyShopConfig(),
		legacyShopState,
		Catalog.GetGameConfig()
	)
	for _, milestoneLevel in milestoneLevels do
		if milestoneLevel <= toLevel then
			count += 1
		end
	end
	return count
end

local function burst(part: BasePart, count: number): ()
	if Theme.reducedMotion then
		return
	end
	local emitter = Create("ParticleEmitter", {
		Name = "FxBurst",
		Rate = 0,
		Lifetime = NumberRange.new(Theme.PARTICLE_LIFETIME_MIN, Theme.PARTICLE_LIFETIME_MAX),
		Speed = NumberRange.new(Theme.PARTICLE_SPEED_MIN, Theme.PARTICLE_SPEED_MAX),
		SpreadAngle = Vector2.new(Theme.PARTICLE_SPREAD, Theme.PARTICLE_SPREAD),
		Size = NumberSequence.new(Theme.PARTICLE_SIZE, 0),
		Color = ColorSequence.new(Theme.COLOR_HIGHLIGHT),
		Parent = part,
	}) :: ParticleEmitter
	emitter:Emit(count)
	task.delay(Theme.PARTICLE_LIFETIME_MAX, function()
		emitter:Destroy()
	end)
end

-- Model scale animations drive Model:ScaleTo from a NumberValue so TweenService supplies
-- the easing. pcall around ScaleTo: an imported model with unscalable content must never
-- break the purchase flow (spec §12.4). The driver lives under this script (never in the
-- replicated model) and is destroyed with the animation.
type ScaleDriver = {
	value: NumberValue,
	finish: () -> (),
}

local function newScaleDriver(model: Model, slotId: string, startScale: number): ScaleDriver
	local previous = scaleTweens[slotId]
	if previous ~= nil then
		previous.cancel()
	end
	local driver = Create("NumberValue", {
		Name = "Scale_" .. slotId,
		Value = startScale,
		Parent = script,
	}) :: NumberValue
	local function applyScale(scale: number): ()
		if model.Parent ~= nil then
			pcall(model.ScaleTo, model, scale)
		end
	end
	applyScale(startScale)
	local connection = driver:GetPropertyChangedSignal("Value"):Connect(function()
		applyScale(driver.Value)
	end)
	local finished = false
	local function finish(): ()
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		driver:Destroy()
		local registered = scaleTweens[slotId]
		if registered ~= nil and registered.cancel == finish then
			scaleTweens[slotId] = nil
		end
		applyScale(1) -- always land on the replicated size, even when cut short
	end
	return { value = driver, finish = finish }
end

local function revealModel(model: Model, slotId: string): Tween
	local driver = newScaleDriver(model, slotId, Theme.REVEAL_START_SCALE)
	local tween = TweenService:Create(
		driver.value,
		Motion.Info(Theme.REVEAL_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	scaleTweens[slotId] = { kind = "reveal", cancel = driver.finish }
	tween.Completed:Once(driver.finish)
	tween:Play()
	return tween
end

-- Growth pop on a stage swap: shrink, overshoot past full size with the reveal's Back-out,
-- then settle to 1. Two chained tweens on the one driver; cancelling either lands on 1.
local function popModel(model: Model, slotId: string): ()
	local driver = newScaleDriver(model, slotId, Theme.STAGE_POP_START_SCALE)
	local growSeconds = Theme.STAGE_POP_SECONDS * Theme.STAGE_POP_PEAK_FRACTION
	local settleSeconds = Theme.STAGE_POP_SECONDS - growSeconds
	local grow = TweenService:Create(
		driver.value,
		Motion.Info(growSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = Theme.STAGE_POP_PEAK_SCALE }
	)
	local settle = TweenService:Create(driver.value, Motion.Info(settleSeconds), { Value = 1 })
	scaleTweens[slotId] = { kind = "pop", cancel = driver.finish }
	grow.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState ~= Enum.PlaybackState.Completed or driver.value.Parent == nil then
			return -- cancelled: finish() already snapped the model back to 1
		end
		settle.Completed:Once(driver.finish)
		settle:Play()
	end)
	grow:Play()
end

-- Placeholder reveal: grow Size from a sliver to the replicated size with the bottom face
-- fixed. Size and CFrame share one easing alpha, so the bottom stays put even through the
-- Back-out overshoot.
local function revealPart(part: BasePart): Tween
	local size = part.Size
	local cframe = part.CFrame
	local startSize = size * Theme.REVEAL_START_SCALE
	part.Size = startSize
	part.CFrame = cframe * CFrame.new(0, -(size.Y - startSize.Y) / 2, 0)
	local tween = TweenService:Create(
		part,
		Motion.Info(Theme.REVEAL_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = size, CFrame = cframe }
	)
	tween:Play()
	return tween
end

local function floatText(building: Instance, part: BasePart, text: string, milestone: boolean): ()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local startOffset = Vector3.new(0, topOffset(building, part) + Theme.LEVELUP_OFFSET_Y, 0)
	local gui = Create("BillboardGui", {
		Name = "FxLevelUp",
		Adornee = part,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(Theme.LEVELUP_BILLBOARD_WIDTH, Theme.LEVELUP_BILLBOARD_HEIGHT),
		StudsOffsetWorldSpace = startOffset,
		Parent = playerGui,
	}) :: BillboardGui
	local label = Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = if milestone then Theme.LEVELUP_MILESTONE_TEXT_SIZE else Theme.LEVELUP_TEXT_SIZE,
		TextColor3 = if milestone then Theme.COLOR_HIGHLIGHT else Theme.COLOR_ACCENT,
		Text = text,
		Parent = gui,
	}) :: TextLabel
	local stroke = Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = label,
	}) :: UIStroke

	local info = Motion.Info(Theme.LEVELUP_FLOAT_SECONDS)
	local rise = TweenService:Create(gui, info, {
		StudsOffsetWorldSpace = startOffset + Vector3.new(0, Theme.LEVELUP_FLOAT_RISE, 0),
	})
	rise.Completed:Once(function()
		gui:Destroy()
	end)
	rise:Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
end

local function flashHighlight(building: Instance, milestone: boolean): ()
	local color = if milestone then Theme.COLOR_HIGHLIGHT else Theme.COLOR_ACCENT_ALT
	local highlight = Create("Highlight", {
		Name = "FxHighlight",
		FillColor = color,
		FillTransparency = Theme.LEVELUP_HIGHLIGHT_FILL,
		OutlineColor = color,
		OutlineTransparency = 0,
		Parent = building, -- Adornee defaults to the parent
	}) :: Highlight
	local tween = TweenService:Create(
		highlight,
		Motion.Info(Theme.LEVELUP_HIGHLIGHT_SECONDS),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	)
	tween.Completed:Once(function()
		highlight:Destroy()
	end)
	tween:Play()
end

local function onReveal(payload: Types.FxReveal): ()
	-- WaitForChild yields; keep the remote handler itself non-blocking.
	task.spawn(function()
		local buildings = localBuildingsFolder()
		if buildings == nil then
			return
		end
		local building: Instance? =
			buildings:WaitForChild(BUILDING_PREFIX .. payload.slotId, Theme.REVEAL_WAIT_SECONDS)
		if building == nil then
			return -- not replicated in time; the building still stands, just without fanfare
		end
		SoundController.Play("purchase")
		local tween: Tween? = nil
		if building:IsA("Model") then
			tween = revealModel(building, payload.slotId)
		elseif building:IsA("BasePart") then
			tween = revealPart(building)
		end
		if tween ~= nil then
			tween.Completed:Once(function()
				SoundController.Play("reveal")
			end)
		else
			SoundController.Play("reveal")
		end
		local part = anchorPart(building)
		if part ~= nil then
			burst(part, Theme.REVEAL_PARTICLES)
		end
	end)
end

-- The milestone fanfare shared by levelUp(milestone) and stageUp: whichever of the two
-- arrives first for a crossing plays it, the other finds the dedupe window and skips.
local function milestoneFanfare(slotId: string, building: Instance?, part: BasePart?): ()
	local now = os.clock()
	local last = lastMilestoneFx[slotId]
	if last ~= nil and now - last < Theme.MILESTONE_FX_DEDUPE_SECONDS then
		return
	end
	lastMilestoneFx[slotId] = now
	SoundController.Play("levelUpMilestone")
	if building ~= nil then
		flashHighlight(building, true)
	end
	if part ~= nil then
		burst(part, Theme.LEVELUP_PARTICLES)
	end
end

local function onLevelUp(payload: Types.FxLevelUp): ()
	SoundController.Play("levelUp", { milestones = countMilestones(payload.toLevel) })
	local buildings = localBuildingsFolder()
	local building = if buildings ~= nil
		then buildings:FindFirstChild(BUILDING_PREFIX .. payload.slotId)
		else nil
	local part = if building ~= nil then anchorPart(building) else nil
	if payload.milestone then
		milestoneFanfare(payload.slotId, building, part)
	elseif building ~= nil then
		flashHighlight(building, false)
	end
	if building == nil or part == nil then
		return
	end
	local gained = payload.toLevel - payload.fromLevel
	local text = if payload.milestone
		then "MILESTONE! +" .. tostring(gained)
		else "+" .. tostring(gained)
	floatText(building, part, text, payload.milestone)
end

-- The server swapped Stage<n> before firing, so the pop scales the new mesh. Placeholder
-- Parts (no template) only get the shared flash; a model mid-reveal keeps its reveal.
local function onStageUp(payload: Types.FxStageUp): ()
	local buildings = localBuildingsFolder()
	if buildings == nil then
		return
	end
	local building = buildings:FindFirstChild(BUILDING_PREFIX .. payload.slotId)
	if building == nil then
		return
	end
	milestoneFanfare(payload.slotId, building, anchorPart(building))
	local active = scaleTweens[payload.slotId]
	if building:IsA("Model") and (active == nil or active.kind ~= "reveal") then
		popModel(building, payload.slotId)
	end
end

local function onFxEvent(payload: any): ()
	if typeof(payload) ~= "table" or typeof(payload.slotId) ~= "string" then
		return
	end
	if payload.kind == "reveal" then
		onReveal(payload :: Types.FxReveal)
	elseif
		payload.kind == "levelUp"
		and typeof(payload.fromLevel) == "number"
		and typeof(payload.toLevel) == "number"
	then
		local levelUp = payload :: Types.FxLevelUp
		levelUp.milestone = levelUp.milestone == true
		onLevelUp(levelUp)
	elseif payload.kind == "stageUp" and typeof(payload.stage) == "number" then
		onStageUp(payload :: Types.FxStageUp)
	end
end

local function isLegacyShopState(source: any): boolean
	return typeof(source) == "table"
		and typeof(source.spent) == "number"
		and typeof(source.perks) == "table"
end

local function onStateChanged(payload: any): ()
	if typeof(payload) ~= "table" then
		return
	end
	local source: any = nil
	if payload.kind == "snapshot" and typeof(payload.state) == "table" then
		source = payload.state.legacyShop
	elseif payload.kind == "delta" then
		source = payload.legacyShop
	end
	if isLegacyShopState(source) then
		legacyShopState = source :: Types.LegacyShopState
	end
end

-- Reduce-motion: the server bursts advanceFireworks with Enabled toggled by task.delay,
-- and that toggle replicates, so a one-time `Enabled = false` would be overwritten by the
-- server's own flip; re-assert on every change instead. Our own FxBurst emitters never
-- exist under reduce-motion (burst() returns early), so any emitter here is the server's.
local function silenceEmitter(instance: Instance): ()
	if not instance:IsA("ParticleEmitter") then
		return
	end
	local emitter = instance :: ParticleEmitter
	emitter.Enabled = false
	-- Dies with the emitter (the server destroys it after the burst).
	emitter:GetPropertyChangedSignal("Enabled"):Connect(function()
		if emitter.Enabled then
			emitter.Enabled = false
		end
	end)
end

local function watchLocalPlot(): ()
	local plotIndex = player:GetAttribute(PLOT_ATTRIBUTE)
	if typeof(plotIndex) ~= "number" then
		return
	end
	local plots = Workspace:FindFirstChild(PLOTS_FOLDER)
	if plots == nil then
		return
	end
	local plot = plots:FindFirstChild(PLOT_PREFIX .. tostring(plotIndex))
	if plot == nil then
		return
	end
	for _, descendant in plot:GetDescendants() do
		silenceEmitter(descendant)
	end
	local previous = plotWatch
	if previous ~= nil then
		previous:Disconnect()
	end
	plotWatch = plot.DescendantAdded:Connect(silenceEmitter)
end

local PlotVisualsController = {}

function PlotVisualsController.Init(): ()
	-- Needs replicated remotes; everything happens in Start so Init stays yield-free.
end

function PlotVisualsController.Start(): ()
	task.spawn(function()
		-- RemoteService creates this folder at server Init; wait rather than assume order.
		local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
		local fxEvent = remotesFolder:WaitForChild("FxEvent") :: RemoteEvent
		local stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent
		-- Live for the whole session; the connections die with the client.
		fxEvent.OnClientEvent:Connect(onFxEvent)
		stateChanged.OnClientEvent:Connect(onStateChanged)
	end)
	if Theme.reducedMotion then
		-- The plot is assigned on claim (PlotIndex attribute), possibly before we run.
		player:GetAttributeChangedSignal(PLOT_ATTRIBUTE):Connect(watchLocalPlot)
		watchLocalPlot()
	end
end

return PlotVisualsController
