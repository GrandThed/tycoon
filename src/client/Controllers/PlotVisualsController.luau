--!strict
-- Client-side plot presentation (docs/INTERFACES.md, M3 client contracts): the reveal
-- tween on a purchase and the floating level-up text, both driven by the server's FxEvent.
-- Effects touch only the local player's own Workspace/Plots/Plot_<i>/Buildings/Building_<slotId>
-- copies — never pads — and nothing here replicates back. Every instance it creates is
-- destroyed when its effect ends. eraAdvance/rebirth belong to
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
--
-- Asset preload amendment: on every plot (other players' buildings flash too) a template
-- building or a new Stage<n> is held at LocalTransparencyModifier 1 until AssetPreloader
-- reports its MeshParts loaded or Theme.ASSET_LOAD_TIMEOUT_SECONDS passes. The modifier is
-- local and separate from the Size/CFrame the scale driver writes, so the two never conflict.
-- The reveal and the pop wait on the same gate, so they never animate an invisible or grey model.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ContentProvider = game:GetService("ContentProvider")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Economy = require(sharedFolder:WaitForChild("Economy"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Motion = require(uiFolder:WaitForChild("Motion"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local AssetPreloader = require(script.Parent:WaitForChild("AssetPreloader"))

-- World naming frozen since M1 (docs/INTERFACES.md).
local PLOT_ATTRIBUTE = "PlotIndex"
local PLOTS_FOLDER = "Plots"
local PLOT_PREFIX = "Plot_"
local BUILDINGS_FOLDER = "Buildings"
local BUILDING_PREFIX = "Building_"
local PROMPT_ANCHOR = "PromptAnchor" -- Attachment under a template's Base (M7 contracts)

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

-- Load gate bookkeeping per live building Model. `pending` counts gates still loading;
-- `waiters` are FX threads resumed once it drops to zero. `hiddenParts` stay hidden until
-- then, so an earlier gate never shows its parts full size while a reveal is still waiting
-- on a later one. `gated` marks roots and parts already considered, so a Stage<n> and its
-- MeshParts arriving as separate DescendantAdded events are handled once; it lives and dies
-- with the watch.
type BuildingWatch = {
	pending: number,
	waiters: { thread },
	hiddenParts: { BasePart },
	gated: { [Instance]: boolean },
	connections: { RBXScriptConnection },
}
-- Entries are removed by unwatchBuilding (AncestryChanged / Destroying).
local watches: { [Model]: BuildingWatch } = {}

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

-- Where particles emit from and the float text starts (instance + world position). A
-- template's Base is a flat invisible part at ground level, so the server keeps a
-- PromptAnchor Attachment on it at half the visible stage's height (M7); placeholders
-- and templates without one fall back to the anchor part itself.
local function fxOrigin(building: Instance): (Instance?, Vector3?)
	local part = anchorPart(building)
	if part == nil then
		return nil, nil
	end
	local attachment = part:FindFirstChild(PROMPT_ANCHOR)
	if attachment ~= nil and attachment:IsA("Attachment") then
		return attachment, attachment.WorldPosition
	end
	return part, part.Position
end

-- Studs from the origin's height up to the building's top edge.
local function topOffset(building: Instance, originY: number): number
	if building:IsA("Model") then
		local boundsCFrame, boundsSize = building:GetBoundingBox()
		return boundsCFrame.Position.Y + boundsSize.Y / 2 - originY
	elseif building:IsA("BasePart") then
		return building.Position.Y + building.Size.Y / 2 - originY
	end
	return 0
end

local function releaseWaiters(watch: BuildingWatch): ()
	local waiters = watch.waiters
	watch.waiters = {}
	for _, waiter in waiters do
		task.spawn(waiter)
	end
end

local function showHiddenParts(watch: BuildingWatch): ()
	local parts = watch.hiddenParts
	watch.hiddenParts = {}
	for _, part in parts do
		part.LocalTransparencyModifier = 0
	end
end

local function isFetched(content: string): boolean
	if content == "" then
		return true -- nothing to download
	end
	local ok, status = pcall(function()
		return ContentProvider:GetAssetFetchStatus(content)
	end)
	return ok and status == Enum.AssetFetchStatus.Success
end

-- Rebuilds (RefreshCosmetics), stage swaps and streamed-back parts usually reuse content this
-- client already has; hiding those would blink them for a frame or two on every client.
local function allFetched(meshParts: { MeshPart }): boolean
	for _, meshPart in meshParts do
		if not isFetched(meshPart.MeshId) or not isFetched(meshPart.TextureID) then
			return false
		end
	end
	return true
end

-- Hides every not-yet-gated BasePart under `root` until its MeshParts load. A root with no
-- new MeshParts (a Model whose meshes have not streamed in yet, a legacy Part-only model) is
-- left alone and unmarked; its MeshParts gate themselves when they arrive.
local function gate(watch: BuildingWatch, root: Instance): ()
	local gated = watch.gated
	if gated[root] then
		return
	end
	local parts: { BasePart } = {}
	local meshParts: { MeshPart } = {}
	local function consider(instance: Instance): ()
		if instance:IsA("BasePart") and not gated[instance] then
			table.insert(parts, instance)
			if instance:IsA("MeshPart") then
				table.insert(meshParts, instance)
			end
		end
	end
	consider(root)
	for _, descendant in root:GetDescendants() do
		consider(descendant)
	end
	if #meshParts == 0 then
		return
	end
	gated[root] = true
	for _, part in parts do
		gated[part] = true
	end
	if allFetched(meshParts) then
		return
	end
	for _, part in parts do
		part.LocalTransparencyModifier = 1
		table.insert(watch.hiddenParts, part)
	end
	watch.pending += 1
	task.spawn(function()
		AssetPreloader.AwaitInstance(root, Theme.ASSET_LOAD_TIMEOUT_SECONDS)
		-- After unwatchBuilding this record is detached: the count may land at zero again,
		-- but its waiter and hidden lists were already emptied there.
		watch.pending -= 1
		if watch.pending == 0 then
			-- Waiters run synchronously up to their first yield, so a reveal applies its
			-- start scale before the parts show and no full-size frame slips through.
			releaseWaiters(watch)
			showHiddenParts(watch)
		end
	end)
end

local function gateCandidate(instance: Instance): boolean
	return instance:IsA("Model") or instance:IsA("MeshPart")
end

local function unwatchBuilding(model: Model): ()
	local watch = watches[model]
	if watch == nil then
		return
	end
	watches[model] = nil
	for _, connection in watch.connections do
		connection:Disconnect()
	end
	-- A waiter must never hang on a building the server removed (rebuild, rebirth), and
	-- nothing it hid may stay hidden.
	releaseWaiters(watch)
	showHiddenParts(watch)
	watch.gated = {}
end

-- Idempotent: the Buildings watcher and an FX handler that got there first both land here.
local function watchBuilding(model: Model): BuildingWatch
	local existing = watches[model]
	if existing ~= nil then
		return existing
	end
	local watch: BuildingWatch = {
		pending = 0,
		waiters = {},
		hiddenParts = {},
		gated = {},
		connections = {},
	}
	watches[model] = watch
	gate(watch, model)
	-- Covers stage swaps (a new Stage<n> Model) and MeshParts that stream in late, whether
	-- their stage is still hidden or already shown.
	table.insert(
		watch.connections,
		model.DescendantAdded:Connect(function(descendant: Instance)
			if gateCandidate(descendant) then
				gate(watch, descendant)
			end
		end)
	)
	table.insert(
		watch.connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then
				unwatchBuilding(model)
			end
		end)
	)
	table.insert(
		watch.connections,
		model.Destroying:Connect(function()
			unwatchBuilding(model)
		end)
	)
	return watch
end

-- Yields until the building's gates are all open (at most about the load timeout). Sweeps
-- first because a stage the server swapped just before firing FxEvent may still have its
-- DescendantAdded event queued behind this handler.
local function awaitVisible(building: Instance): ()
	if not building:IsA("Model") or not building:IsDescendantOf(Workspace) then
		return
	end
	local watch = watchBuilding(building)
	for _, descendant in building:GetDescendants() do
		if gateCandidate(descendant) then
			gate(watch, descendant)
		end
	end
	if watch.pending == 0 then
		return
	end
	table.insert(watch.waiters, coroutine.running())
	coroutine.yield()
end

local function watchBuildingsFolder(folder: Instance): ()
	local function onChild(child: Instance): ()
		if child:IsA("Model") then
			watchBuilding(child)
		end
	end
	for _, child in folder:GetChildren() do
		onChild(child)
	end
	-- Plot folders live for the whole server; Destroy would disconnect this anyway.
	folder.ChildAdded:Connect(onChild)
end

local function watchPlot(plot: Instance): ()
	if string.sub(plot.Name, 1, #PLOT_PREFIX) ~= PLOT_PREFIX then
		return
	end
	local buildings = plot:FindFirstChild(BUILDINGS_FOLDER)
	if buildings ~= nil then
		watchBuildingsFolder(buildings)
		return
	end
	local connection: RBXScriptConnection? = nil
	connection = plot.ChildAdded:Connect(function(child: Instance)
		if child.Name == BUILDINGS_FOLDER and connection ~= nil then
			connection:Disconnect()
			watchBuildingsFolder(child)
		end
	end)
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

local function burst(origin: Instance, count: number): ()
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
		Parent = origin, -- a BasePart or an Attachment; both host emitters
	}) :: ParticleEmitter
	emitter:Emit(count)
	task.delay(Theme.PARTICLE_LIFETIME_MAX, function()
		emitter:Destroy()
	end)
end

-- Model scale animations drive a NumberValue so TweenService supplies the easing, and
-- scale a snapshot of the BaseParts present when the driver was created (Size and CFrame
-- relative to the pivot, i.e. the ground-level Base). Model:ScaleTo is deliberately not
-- used: it rescales every current descendant against the model's tracked scale, so a
-- Stage<n> that replicates mid-animation would be mis-sized by the final restore. Parts
-- that arrive later are simply left alone, and finish() restores the snapshot exactly.
-- The driver lives under this script (never in the replicated model) and is destroyed
-- with the animation.
type ScaleDriver = {
	value: NumberValue,
	finish: () -> (),
}

type PartSnapshot = { part: BasePart, size: Vector3, offset: CFrame }

local function newScaleDriver(model: Model, slotId: string, startScale: number): ScaleDriver
	local previous = scaleTweens[slotId]
	if previous ~= nil then
		previous.cancel()
	end
	local pivot = model:GetPivot()
	local snapshot: { PartSnapshot } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(snapshot, {
				part = descendant,
				size = descendant.Size,
				offset = pivot:ToObjectSpace(descendant.CFrame),
			})
		end
	end
	local driver = Create("NumberValue", {
		Name = "Scale_" .. slotId,
		Value = startScale,
		Parent = script,
	}) :: NumberValue
	local function applyScale(scale: number): ()
		for _, entry in snapshot do
			local part = entry.part
			if part.Parent ~= nil then
				part.Size = entry.size * scale
				part.CFrame = pivot * (entry.offset.Rotation + entry.offset.Position * scale)
			end
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

local function floatText(
	building: Instance,
	origin: Instance,
	originPosition: Vector3,
	text: string,
	milestone: boolean
): ()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local startOffset =
		Vector3.new(0, topOffset(building, originPosition.Y) + Theme.LEVELUP_OFFSET_Y, 0)
	local gui = Create("BillboardGui", {
		Name = "FxLevelUp",
		Adornee = origin, -- BasePart or Attachment
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
		awaitVisible(building)
		if building.Parent == nil then
			return -- rebuilt or removed while its assets loaded
		end
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
		local origin = fxOrigin(building)
		if origin ~= nil then
			burst(origin, Theme.REVEAL_PARTICLES)
		end
	end)
end

-- The milestone fanfare shared by levelUp(milestone) and stageUp: whichever of the two
-- arrives first for a crossing plays it, the other finds the dedupe window and skips.
-- Claiming is separate from playing so stageUp can claim on arrival (keeping the dedupe
-- window honest) and play once its stage has loaded, however long that takes.
local function claimMilestoneFanfare(slotId: string): boolean
	local now = os.clock()
	local last = lastMilestoneFx[slotId]
	if last ~= nil and now - last < Theme.MILESTONE_FX_DEDUPE_SECONDS then
		return false
	end
	lastMilestoneFx[slotId] = now
	return true
end

local function playMilestoneFanfare(building: Instance?, origin: Instance?): ()
	SoundController.Play("levelUpMilestone")
	if building ~= nil then
		flashHighlight(building, true)
	end
	if origin ~= nil then
		burst(origin, Theme.LEVELUP_PARTICLES)
	end
end

local function milestoneFanfare(slotId: string, building: Instance?, origin: Instance?): ()
	if claimMilestoneFanfare(slotId) then
		playMilestoneFanfare(building, origin)
	end
end

local function onLevelUp(payload: Types.FxLevelUp): ()
	SoundController.Play("levelUp", { milestones = countMilestones(payload.toLevel) })
	local buildings = localBuildingsFolder()
	local building = if buildings ~= nil
		then buildings:FindFirstChild(BUILDING_PREFIX .. payload.slotId)
		else nil
	local origin: Instance? = nil
	local originPosition: Vector3? = nil
	if building ~= nil then
		origin, originPosition = fxOrigin(building)
	end
	if payload.milestone then
		milestoneFanfare(payload.slotId, building, origin)
	elseif building ~= nil then
		flashHighlight(building, false)
	end
	if building == nil or origin == nil or originPosition == nil then
		return
	end
	local gained = payload.toLevel - payload.fromLevel
	local text = if payload.milestone
		then "MILESTONE! +" .. tostring(gained)
		else "+" .. tostring(gained)
	floatText(building, origin, originPosition, text, payload.milestone)
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
	if not building:IsA("Model") then
		milestoneFanfare(payload.slotId, building, (fxOrigin(building)))
		return
	end
	local model = building :: Model
	local claimed = claimMilestoneFanfare(payload.slotId)
	-- The server destroys the old stage in the same frame it parents the new one, so there
	-- is nothing left to keep on screen: the new stage stays hidden until loaded, then the
	-- flash/burst and the pop land on it together.
	task.spawn(function()
		awaitVisible(model)
		if model.Parent == nil then
			return
		end
		if claimed then
			playMilestoneFanfare(model, (fxOrigin(model)))
		end
		local active = scaleTweens[payload.slotId]
		if active == nil or active.kind ~= "reveal" then
			popModel(model, payload.slotId)
		end
	end)
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
	task.spawn(function()
		-- PlotService builds every plot at server boot, so the set is fixed for the session.
		local plots = Workspace:WaitForChild(PLOTS_FOLDER)
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		plots.ChildAdded:Connect(watchPlot)
	end)
	if Theme.reducedMotion then
		-- The plot is assigned on claim (PlotIndex attribute), possibly before we run.
		player:GetAttributeChangedSignal(PLOT_ATTRIBUTE):Connect(watchLocalPlot)
		watchLocalPlot()
	end
end

return PlotVisualsController
