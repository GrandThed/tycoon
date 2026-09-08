--!strict
-- Owns world geometry and purchases: hub + plot ring at Init, plot claim/release, buy pads,
-- building spawns (with placeholder fallback), level-up prompts, and the M2 era actions
-- (Advance Era / Rebirth with plot teardown + rebuild). Only derived geometry lives in code;
-- every number comes from Game.json or the era layout module. Claim/Release are called by
-- Main's join/leave orchestration — this service connects no player lifecycle events itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

-- Era indices are 1-based by schema; rebirth returns here (docs/INTERFACES.md M2 contracts).
local FIRST_ERA_INDEX = 1

type PlotRecord = {
	index: number,
	folder: Folder,
	base: Part,
	buildingsFolder: Folder,
	padsFolder: Folder,
	owner: Player?,
	connections: { RBXScriptConnection },
	padTouchLast: { [string]: number },
	prompts: { [string]: ProximityPrompt },
}

-- Derived per-era lookups: effective `requires` is "omitted ⇒ previous slot in the array,
-- first slot ⇒ none" (frozen semantics), resolved once here so both intents share it.
type EraMaps = {
	slotsById: { [string]: Types.SlotConfig },
	effectiveRequires: { [string]: string },
}

local plots: { PlotRecord } = {}
local plotsByPlayer: { [Player]: PlotRecord } = {}
local eraMapsCache: { [number]: EraMaps } = {}
local isStudio = RunService:IsStudio()

local function getEraMaps(eraConfig: Types.EraConfig): EraMaps
	local cached = eraMapsCache[eraConfig.eraIndex]
	if cached ~= nil then
		return cached
	end
	local slotsById: { [string]: Types.SlotConfig } = {}
	local effectiveRequires: { [string]: string } = {}
	local previousId: string? = nil
	for _, slot in eraConfig.slots do
		slotsById[slot.id] = slot
		local requiresId = slot.requires or previousId
		if requiresId ~= nil then
			effectiveRequires[slot.id] = requiresId
		end
		previousId = slot.id
	end
	local maps: EraMaps = { slotsById = slotsById, effectiveRequires = effectiveRequires }
	eraMapsCache[eraConfig.eraIndex] = maps
	return maps
end

local function sendFailure(
	player: Player,
	action: "buy" | "levelUp" | "advanceEra" | "rebirth",
	slotId: string,
	reason: "insufficientFunds" | "locked" | "invalid"
): ()
	local result: Types.ActionResult =
		{ action = action, slotId = slotId, ok = false, reason = reason }
	RemoteService.FireClient(player, "ActionResult", result)
end

-- Billboard dimensions are in studs (BillboardGui scale units), derived from layout sizes so
-- label proportions remain a layout decision; the per-line fractions are pure UI arithmetic.
local function createLabelBillboard(
	lines: { string },
	widthStuds: number,
	heightStuds: number,
	offsetYStuds: number
): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromScale(widthStuds, heightStuds)
	billboard.StudsOffset = Vector3.new(0, offsetYStuds, 0)
	for index, text in lines do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. index
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1 / #lines)
		label.Position = UDim2.fromScale(0, (index - 1) / #lines)
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = billboard
	end
	return billboard
end

local function tryLevelUp(player: Player, slotId: string, count: number): ()
	-- Frozen validation order: plot → slot exists in era → ownership/level rules → requires
	-- (ownership already implies the chain for level-ups) → affordability.
	local record = plotsByPlayer[player]
	local state = DataService.GetState(player)
	if record == nil or state == nil then
		sendFailure(player, "levelUp", slotId, "invalid")
		return
	end
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		sendFailure(player, "levelUp", slotId, "invalid")
		return
	end
	local slot = getEraMaps(eraConfig).slotsById[slotId]
	if slot == nil then
		sendFailure(player, "levelUp", slotId, "invalid")
		return
	end
	local slotState = state.slots[slotId]
	if slotState == nil or slot.type ~= "building" then
		sendFailure(player, "levelUp", slotId, "invalid")
		return
	end
	local gameConfig = Catalog.GetGameConfig()
	local headroom = gameConfig.maxLevel - slotState.level
	if headroom <= 0 then
		sendFailure(player, "levelUp", slotId, "invalid")
		return
	end

	local wanted = math.min(count, headroom)
	local granted = 0
	if isStudio and gameConfig.debug.studioFreeBuy then
		-- Free-buy skips affordability entirely: grant the full clamped count, charge nothing.
		granted = wanted
	else
		-- Accumulating per-step costs equals LevelUpCostTotal for the granted range and finds
		-- the affordable count in the same pass.
		local totalCost = 0
		for step = 1, wanted do
			local stepCost = Economy.LevelUpCost(slot.baseCost, slotState.level + step, gameConfig)
			if totalCost + stepCost > state.cash then
				break
			end
			totalCost += stepCost
			granted = step
		end
		if granted == 0 then
			sendFailure(player, "levelUp", slotId, "insufficientFunds")
			return
		end
		state.cash -= totalCost
	end

	slotState.level += granted
	if slotState.level >= gameConfig.maxLevel then
		-- Optional annotation: map indexing is non-optional under the old solver.
		local prompt: ProximityPrompt? = record.prompts[slotId]
		if prompt ~= nil then
			prompt.Enabled = false
		end
	end
	EconomyService.MarkDirty(player, { cash = true, income = true, slotIds = { slotId } })
end

local function onPromptTriggered(record: PlotRecord, slotId: string, player: Player): ()
	-- Prompts render for everyone; ownership is enforced here (spec §5: only the owner interacts).
	if record.owner ~= player then
		return
	end
	-- Prompt triggers bypass remotes, so spend from the RequestLevelUp bucket: one rate-limit
	-- budget across both level-up paths, with the same silent-drop-on-overflow semantics.
	if not RemoteService.TryConsumeToken(player, "RequestLevelUp") then
		return
	end
	tryLevelUp(player, slotId, 1)
end

local function spawnBuilding(
	record: PlotRecord,
	slot: Types.SlotConfig,
	eraName: string,
	layout: Types.EraLayout
): ()
	local anchor = record.base:FindFirstChild("Slot_" .. slot.id)
	local anchorCFrame: CFrame
	if anchor ~= nil and anchor:IsA("Attachment") then
		anchorCFrame = anchor.WorldCFrame
	else
		-- Layout gap already warned about at configure time; degrade to the plot's top center.
		-- The built base part is the geometry authority: the ring is world-fixed at boot, so
		-- per-era layouts drive colors/positions but never resize or move the base.
		anchorCFrame = record.base.CFrame * CFrame.new(0, record.base.Size.Y / 2, 0)
	end

	local spawned: Instance
	local assetsFolder = ServerStorage:FindFirstChild("Assets")
	local eraAssets = if assetsFolder ~= nil then assetsFolder:FindFirstChild(eraName) else nil
	local template = if eraAssets ~= nil then eraAssets:FindFirstChild(slot.modelName) else nil
	if template ~= nil and template:IsA("Model") then
		local model = template:Clone()
		model.Name = "Building_" .. slot.id
		model:PivotTo(anchorCFrame)
		model.Parent = record.buildingsFolder
		spawned = model
	else
		-- Placeholder fallback (spec §5): fully playable before any Kenney asset is imported.
		local part = Instance.new("Part")
		part.Name = "Building_" .. slot.id
		part.Anchored = true
		part.Size = layout.placeholderSize
		part.CFrame = anchorCFrame * CFrame.new(0, layout.placeholderSize.Y / 2, 0)
		local billboard = createLabelBillboard(
			{ slot.modelName },
			layout.padSize.X,
			layout.padSize.Z / 2,
			layout.placeholderSize.Y
		)
		billboard.Parent = part
		part.Parent = record.buildingsFolder
		spawned = part
	end

	if slot.type == "building" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LevelUpPrompt"
		prompt.ActionText = "Level Up"
		prompt.ObjectText = slot.name
		prompt.RequiresLineOfSight = false
		table.insert(
			record.connections,
			prompt.Triggered:Connect(function(triggeringPlayer: Player)
				onPromptTriggered(record, slot.id, triggeringPlayer)
			end)
		)
		prompt.Parent = spawned
		record.prompts[slot.id] = prompt
	end
end

local function padWorldCFrame(
	record: PlotRecord,
	slot: Types.SlotConfig,
	layout: Types.EraLayout
): CFrame
	local slotLayout = layout.slots[slot.id]
	local localPosition: Vector3
	if slotLayout ~= nil and slotLayout.padPosition ~= nil then
		localPosition = slotLayout.padPosition
	elseif slotLayout ~= nil then
		-- Default rule: padOffset studs in front of the building, along its facing.
		local facing = CFrame.Angles(0, math.rad(slotLayout.rotationY), 0)
		localPosition = slotLayout.position
			+ facing:VectorToWorldSpace(Vector3.new(0, 0, -layout.padOffset))
	else
		localPosition = Vector3.zero
	end
	local padTop = Vector3.new(0, record.base.Size.Y / 2 + layout.padSize.Y / 2, 0)
	return record.base.CFrame * CFrame.new(localPosition + padTop)
end

-- Forward-declared: the pad Touched handler and the RequestBuy remote share this buy path.
local tryBuy: (player: Player, slotId: string) -> ()

local function onPadTouched(record: PlotRecord, slot: Types.SlotConfig, hit: BasePart): ()
	local owner = record.owner
	if owner == nil then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	if character == nil then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player == nil or player ~= owner then
		return
	end
	-- Debounce counts accepted touches only: non-owner brushes never reset the window.
	local now = os.clock()
	local last = record.padTouchLast[slot.id]
	if last ~= nil and now - last < Catalog.GetGameConfig().remotes.padTouchDebounce then
		return
	end
	record.padTouchLast[slot.id] = now
	tryBuy(player, slot.id)
end

local function createPad(record: PlotRecord, slot: Types.SlotConfig, layout: Types.EraLayout): ()
	if record.padsFolder:FindFirstChild("Pad_" .. slot.id) ~= nil then
		return
	end
	local pad = Instance.new("Part")
	pad.Name = "Pad_" .. slot.id
	pad.Anchored = true
	pad.CanCollide = false
	pad.Size = layout.padSize
	pad.CFrame = padWorldCFrame(record, slot, layout)

	local billboard = createLabelBillboard(
		{ slot.name, Format.Cash(slot.baseCost) },
		layout.padSize.X,
		layout.padSize.Z / 2,
		layout.placeholderSize.Y / 2
	)
	billboard.Parent = pad

	table.insert(
		record.connections,
		pad.Touched:Connect(function(hit: BasePart)
			onPadTouched(record, slot, hit)
		end)
	)
	pad.Parent = record.padsFolder
end

-- Full-scan reconciliation of the "pad exists iff unowned AND requires owned" rule; idempotent,
-- so it serves the claim path, the after-purchase reveal, and era rebuilds.
local function refreshPads(
	record: PlotRecord,
	state: Types.PlayerState,
	eraConfig: Types.EraConfig,
	layout: Types.EraLayout
): ()
	local maps = getEraMaps(eraConfig)
	for _, slot in eraConfig.slots do
		local shouldExist = state.slots[slot.id] == nil
		if shouldExist then
			local requiresId = maps.effectiveRequires[slot.id]
			shouldExist = requiresId == nil or state.slots[requiresId] ~= nil
		end
		local pad = record.padsFolder:FindFirstChild("Pad_" .. slot.id)
		if shouldExist then
			if pad == nil then
				createPad(record, slot, layout)
			end
		elseif pad ~= nil then
			pad:Destroy()
		end
	end
end

function tryBuy(player: Player, slotId: string): ()
	-- Frozen validation order: plot → slot exists in era → ownership → requires → affordability.
	local record = plotsByPlayer[player]
	local state = DataService.GetState(player)
	if record == nil or state == nil then
		sendFailure(player, "buy", slotId, "invalid")
		return
	end
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		sendFailure(player, "buy", slotId, "invalid")
		return
	end
	local maps = getEraMaps(eraConfig)
	local slot = maps.slotsById[slotId]
	if slot == nil then
		sendFailure(player, "buy", slotId, "invalid")
		return
	end
	if state.slots[slotId] ~= nil then
		sendFailure(player, "buy", slotId, "invalid")
		return
	end
	local requiresId = maps.effectiveRequires[slotId]
	if requiresId ~= nil and state.slots[requiresId] == nil then
		sendFailure(player, "buy", slotId, "locked")
		return
	end
	local gameConfig = Catalog.GetGameConfig()
	-- Free-buy skips affordability only (never the requires chain) and charges nothing, so
	-- testing from zero cash cannot drive the balance negative.
	local freeBuy = isStudio and gameConfig.debug.studioFreeBuy
	if not freeBuy then
		if state.cash < slot.baseCost then
			sendFailure(player, "buy", slotId, "insufficientFunds")
			return
		end
		state.cash -= slot.baseCost
	end
	state.slots[slotId] = { level = 1 }

	local layout = Catalog.GetLayout(eraConfig.name)
	if layout ~= nil then
		spawnBuilding(record, slot, eraConfig.name, layout)
		refreshPads(record, state, eraConfig, layout)
	end
	EconomyService.MarkDirty(player, { cash = true, income = true, slotIds = { slotId } })
end

-- Recolor + re-anchor a plot base for an era. Attachments are era-specific, so old ones are
-- destroyed first (a released plot keeps its last owner's attachments until the next claim).
local function configureBaseForEra(
	record: PlotRecord,
	eraConfig: Types.EraConfig,
	layout: Types.EraLayout
): ()
	record.base.Color = layout.baseColor
	for _, child in record.base:GetChildren() do
		if child:IsA("Attachment") then
			child:Destroy()
		end
	end
	for _, slot in eraConfig.slots do
		local slotLayout = layout.slots[slot.id]
		if slotLayout == nil then
			warn(
				`[PlotService] layout '{eraConfig.name}' missing slot '{slot.id}'; using plot center`
			)
		end
		local localPosition = if slotLayout ~= nil then slotLayout.position else Vector3.zero
		local rotationY = if slotLayout ~= nil then slotLayout.rotationY else 0
		local attachment = Instance.new("Attachment")
		attachment.Name = "Slot_" .. slot.id
		attachment.CFrame = CFrame.new(localPosition + Vector3.new(0, record.base.Size.Y / 2, 0))
			* CFrame.Angles(0, math.rad(rotationY), 0)
		attachment.Parent = record.base
	end
end

local function clearPlotContents(record: PlotRecord): ()
	for _, connection in record.connections do
		connection:Disconnect()
	end
	table.clear(record.connections)
	table.clear(record.padTouchLast)
	table.clear(record.prompts)
	record.buildingsFolder:ClearAllChildren()
	record.padsFolder:ClearAllChildren()
end

-- Tear down and rebuild a plot for state.era: recolored base, regenerated anchors/pads, and a
-- bulk restore of owned buildings WITHOUT tweens/sounds (M2 contract: 24 reveal effects on a
-- rejoin would be noise, and M3 owns reveal presentation anyway). Serves both the claim path
-- (state.slots populated from persistence) and era changes (state.slots freshly emptied).
local function rebuildPlotForEra(record: PlotRecord, state: Types.PlayerState): ()
	clearPlotContents(record)
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		warn(`[PlotService] era {state.era} config missing; plot {record.index} left bare`)
		return
	end
	local layout = Catalog.GetLayout(eraConfig.name)
	if layout == nil then
		warn(`[PlotService] layout '{eraConfig.name}' missing; plot {record.index} left bare`)
		return
	end
	configureBaseForEra(record, eraConfig, layout)
	local maxLevel = Catalog.GetGameConfig().maxLevel
	for _, slot in eraConfig.slots do
		local owned = state.slots[slot.id]
		if owned ~= nil then
			spawnBuilding(record, slot, eraConfig.name, layout)
			if owned.level >= maxLevel then
				local prompt: ProximityPrompt? = record.prompts[slot.id]
				if prompt ~= nil then
					prompt.Enabled = false
				end
			end
		end
	end
	refreshPads(record, state, eraConfig, layout)
end

local function tryAdvanceEra(player: Player): ()
	-- Standard chain (no slot involved): plot/state → era headroom → all slots owned.
	local record = plotsByPlayer[player]
	local state = DataService.GetState(player)
	if record == nil or state == nil then
		sendFailure(player, "advanceEra", "", "invalid")
		return
	end
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		sendFailure(player, "advanceEra", "", "invalid")
		return
	end
	if state.era >= Catalog.GetEraCount() then
		sendFailure(player, "advanceEra", "", "locked")
		return
	end
	local totalLevelsThisEra = 0
	for _, slot in eraConfig.slots do
		local owned = state.slots[slot.id]
		if owned == nil then
			sendFailure(player, "advanceEra", "", "locked")
			return
		end
		totalLevelsThisEra += owned.level
	end
	-- Effects are atomic (no yields), so a second in-flight RequestAdvanceEra revalidates
	-- against the emptied slots table and fails "locked" — legacy can never double-grant.
	state.legacy += Economy.LegacyGain(
		state.era,
		totalLevelsThisEra,
		state.rebirthCount,
		Catalog.GetGameConfig()
	)
	state.era += 1
	state.cash = 0
	state.slots = {}
	state.stats.erasCompleted += 1
	rebuildPlotForEra(record, state)
	-- Restamp the persisted rate NOW (0 for the empty era): a disconnect before the next tick
	-- must not save the completed era's rate for ApplyOfflineGrant to pay into the new era.
	EconomyService.RefreshPersistedRate(player)
	-- Fresh full snapshot: the era differs from the client's model, which rebuilds its panel.
	EconomyService.SendSnapshot(player)
end

local function tryRebirth(player: Player): ()
	local record = plotsByPlayer[player]
	local state = DataService.GetState(player)
	if record == nil or state == nil then
		sendFailure(player, "rebirth", "", "invalid")
		return
	end
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		sendFailure(player, "rebirth", "", "invalid")
		return
	end
	if state.era ~= Catalog.GetEraCount() then
		sendFailure(player, "rebirth", "", "locked")
		return
	end
	local totalLevelsThisEra = 0
	for _, slot in eraConfig.slots do
		local owned = state.slots[slot.id]
		if owned == nil then
			sendFailure(player, "rebirth", "", "locked")
			return
		end
		totalLevelsThisEra += owned.level
	end
	-- Rebirth is the final era's "advance" (amended contract): grant its legacy FIRST, with
	-- rebirthCount at its pre-increment value — otherwise the longest era pays zero prestige.
	-- Existing legacy is kept. Same atomicity argument as tryAdvanceEra: no yields, and a
	-- second in-flight rebirth revalidates against the emptied slots table.
	state.legacy += Economy.LegacyGain(
		state.era,
		totalLevelsThisEra,
		state.rebirthCount,
		Catalog.GetGameConfig()
	)
	state.rebirthCount += 1
	state.era = FIRST_ERA_INDEX
	state.cash = 0
	state.slots = {}
	state.stats.erasCompleted += 1
	rebuildPlotForEra(record, state)
	-- Same as tryAdvanceEra: never let the Era-4 rate persist next to Era 1's empty slots.
	EconomyService.RefreshPersistedRate(player)
	EconomyService.SendSnapshot(player)
end

local function buildWorld(): ()
	-- The ring is sized once from the first era's layout; all era layouts share plotSize by
	-- design (economy-designer guidance), and per-era differences degrade to this fixed base.
	local eraConfig = Catalog.GetEraConfig(FIRST_ERA_INDEX)
	if eraConfig == nil then
		warn("[PlotService] era 1 config missing; world not built")
		return
	end
	local layout = Catalog.GetLayout(eraConfig.name)
	if layout == nil then
		warn(`[PlotService] layout '{eraConfig.name}' missing; world not built`)
		return
	end
	local gameConfig = Catalog.GetGameConfig()
	local plotSize = layout.plotSize
	local plotCount = gameConfig.plotCount

	-- The ring circumference must fit every plot plus its margin; never overlap the hub.
	local ringRadius = math.max(
		plotCount * (plotSize.X + gameConfig.plotMargin) / (2 * math.pi),
		gameConfig.hubRadius + gameConfig.plotMargin + plotSize.Z / 2
	)

	-- Ground plane so players can walk from the hub to any plot; bases rest on its top and all
	-- walkable tops sit at Y = 0 (attachment Y in layouts is a ground-level offset).
	local groundSide = 2 * (ringRadius + plotSize.Z)
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.Size = Vector3.new(groundSide, plotSize.Y, groundSide)
	ground.CFrame = CFrame.new(0, -plotSize.Y - plotSize.Y / 2, 0)
	ground.Parent = Workspace

	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Shape = Enum.PartType.Cylinder
	hub.Anchored = true
	hub.Size = Vector3.new(plotSize.Y, gameConfig.hubRadius * 2, gameConfig.hubRadius * 2)
	-- A cylinder's axis is X; stand it upright so the flat face is the floor.
	hub.CFrame = CFrame.new(0, -plotSize.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	hub.Parent = Workspace

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = layout.padSize
	spawnLocation.CFrame = CFrame.new(0, layout.padSize.Y / 2, 0)
	spawnLocation.Parent = Workspace

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = Workspace

	for index = 1, plotCount do
		local angle = (index - 1) / plotCount * 2 * math.pi
		local position =
			Vector3.new(math.cos(angle) * ringRadius, -plotSize.Y / 2, math.sin(angle) * ringRadius)

		local plotFolder = Instance.new("Folder")
		plotFolder.Name = "Plot_" .. index

		local base = Instance.new("Part")
		base.Name = "Base"
		base.Anchored = true
		base.Size = plotSize
		base.Color = layout.baseColor
		-- lookAt points local -Z at the hub, so layout -Z ("front") faces arriving players.
		base.CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
		base.Parent = plotFolder

		local buildingsFolder = Instance.new("Folder")
		buildingsFolder.Name = "Buildings"
		buildingsFolder.Parent = plotFolder
		local padsFolder = Instance.new("Folder")
		padsFolder.Name = "Pads"
		padsFolder.Parent = plotFolder
		plotFolder.Parent = plotsFolder

		table.insert(plots, {
			index = index,
			folder = plotFolder,
			base = base,
			buildingsFolder = buildingsFolder,
			padsFolder = padsFolder,
			owner = nil :: Player?,
			connections = {},
			padTouchLast = {},
			prompts = {},
		})
	end
end

local PlotService = {}

-- Main calls this after DataService.LoadAsync + the offline grant; state is guaranteed loaded.
-- Idempotent: a duplicate orchestration thread for the same player is a no-op.
function PlotService.ClaimPlot(player: Player): ()
	if plotsByPlayer[player] ~= nil then
		return
	end
	local state = DataService.GetState(player)
	if state == nil then
		warn(`[PlotService] ClaimPlot before LoadAsync for {player.Name}; skipping`)
		return
	end
	local record: PlotRecord? = nil
	for _, candidate in plots do
		if candidate.owner == nil then
			record = candidate
			break
		end
	end
	if record == nil then
		-- plotCount is sized to server capacity; if misconfigured, degrade rather than error.
		warn(`[PlotService] no free plot for {player.Name}`)
		return
	end
	record.owner = player
	plotsByPlayer[player] = record
	player:SetAttribute("PlotIndex", record.index)
	-- Rebuilds owned buildings from persisted state.slots (bulk restore, no reveal effects).
	rebuildPlotForEra(record, state)
end

-- Main calls this first on PlayerRemoving (before EconomyService.Cleanup/DataService.Release).
function PlotService.Release(player: Player): ()
	local record = plotsByPlayer[player]
	if record == nil then
		return
	end
	plotsByPlayer[player] = nil
	record.owner = nil
	clearPlotContents(record)
end

function PlotService.Init(): ()
	buildWorld()
	-- Payload types are already validated by RemoteService; casts narrow the varargs.
	RemoteService.SetHandler("RequestBuy", function(player: Player, slotId: any)
		tryBuy(player, slotId :: string)
	end)
	RemoteService.SetHandler("RequestLevelUp", function(player: Player, slotId: any, count: any)
		tryLevelUp(player, slotId :: string, count :: number)
	end)
	RemoteService.SetHandler("RequestAdvanceEra", function(player: Player)
		tryAdvanceEra(player)
	end)
	RemoteService.SetHandler("RequestRebirth", function(player: Player)
		tryRebirth(player)
	end)
end

function PlotService.Start(): () end

return PlotService
