--!strict
-- Owns world geometry and purchases: hub + plot ring at Init, plot claim/release, buy pads,
-- building spawns (template at the level's stage → placeholder, M7), stage swaps on base
-- milestones, the VIP texture swap, level-up prompts, the M2 era actions
-- (Advance Era / Rebirth with plot teardown + rebuild), the M3 plot sign, and the M3 FxEvent
-- firing points (owner only, after each successful mutation, never on bulk restore). Only
-- derived geometry lives in code; every number comes from Game.json or the era layout module.
-- Claim/Release are called by Main's join/leave orchestration — this service connects no
-- player lifecycle events itself.

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
local CityGrowth = require(sharedFolder:WaitForChild("CityGrowth"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

-- Era indices are 1-based by schema; rebirth returns here (docs/INTERFACES.md M2 contracts).
local FIRST_ERA_INDEX = 1
-- ServerStorage/Assets/<EraName>_VIP holds VIP skin variants (spec §8).
local VIP_ASSET_SUFFIX = "_VIP"
-- M7 template shape (docs/INTERFACES.md "Template shape"): Stage<n> Models under the template,
-- one MeshPart per kit named after the kit, and an invisible `Base` PrimaryPart at the anchor.
local STAGE_CHILD_PATTERN = "^Stage(%d+)$"
local STAGE_CHILD_PREFIX = "Stage"
local TEMPLATE_BASE_NAME = "Base"
-- Attachment under a template's Base at half the visible stage's height: the LevelUpPrompt and
-- the client's particle/float-text origin hang here, so neither sits at the building's feet.
local PROMPT_ANCHOR_NAME = "PromptAnchor"
local ASSET_ID_PREFIX = "rbxassetid://"
-- M9 plot-folder attributes (docs/INTERFACES.md "Server behaviour — attributes only"): the whole
-- server side of city dressing; clients derive everything else from them.
local ERA_NAME_ATTRIBUTE = "EraName"
local GROWTH_TIER_ATTRIBUTE = "GrowthTier"

type PlotRecord = {
	index: number,
	folder: Folder,
	base: Part,
	buildingsFolder: Folder,
	padsFolder: Folder,
	signBillboard: BillboardGui,
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

-- Buys and level-ups recompute the tier far more often than it changes, so compare first rather
-- than sending a property write per purchase to every client.
local function setAttributeIfChanged(instance: Instance, name: string, value: string | number): ()
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

-- Owned count and level sum over the era's own slots, exactly as tryAdvanceEra/tryRebirth total
-- totalLevelsThisEra, so a stale slot id left in a profile never inflates the tier.
local function growthTierFor(state: Types.PlayerState, eraConfig: Types.EraConfig): number
	local dressing = Catalog.GetCityDressingConfig()
	if dressing == nil then
		return 0
	end
	local ownedCount = 0
	local totalLevels = 0
	for _, slot in eraConfig.slots do
		local owned = state.slots[slot.id]
		if owned ~= nil then
			ownedCount += 1
			totalLevels += owned.level
		end
	end
	local score = CityGrowth.Score(ownedCount, totalLevels, dressing.tier.ownedWeight)
	return CityGrowth.TierFor(score, dressing.tier.thresholds)
end

-- Both attributes for a claimed plot; a missing era config (already warned about by the caller)
-- leaves them as they were rather than publishing a name no layout matches.
local function publishCityAttributes(record: PlotRecord, state: Types.PlayerState): ()
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig == nil then
		return
	end
	setAttributeIfChanged(record.folder, ERA_NAME_ATTRIBUTE, eraConfig.name)
	setAttributeIfChanged(record.folder, GROWTH_TIER_ATTRIBUTE, growthTierFor(state, eraConfig))
end

-- Unclaimed plots read as a bare first-era plot. The name comes from era 1's config (the lobby
-- era, Village) rather than a literal; buildWorld builds no plots without that config.
local function publishLobbyAttributes(record: PlotRecord): ()
	local firstEra = Catalog.GetEraConfig(FIRST_ERA_INDEX)
	if firstEra ~= nil then
		setAttributeIfChanged(record.folder, ERA_NAME_ATTRIBUTE, firstEra.name)
	end
	setAttributeIfChanged(record.folder, GROWTH_TIER_ATTRIBUTE, 0)
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

-- The only presentation colors in this service: neutral white for every world label, gold for
-- the plot sign of a VIP owner (M4 flips passes.VIP; the branch exists now per the M3 contract).
local LABEL_TEXT_COLOR = Color3.new(1, 1, 1)
local VIP_SIGN_TEXT_COLOR = Color3.fromRGB(255, 200, 60)

local function fireFx(player: Player, payload: Types.FxEvent): ()
	RemoteService.FireClient(player, "FxEvent", payload)
end

-- M6 Legacy shop cosmetics (server-side world cosmetics, applied silently on spawn/claim/
-- refresh; a missing or unowned perk spawns nothing). Perk ids are the frozen config keys.
local PERK_SIGN_TITLE = "signTitle"
local PERK_NAME_TAG_COLOUR = "nameTagColour"
local PERK_MONUMENT_GLOW = "monumentGlow"
local PERK_ADVANCE_FIREWORKS = "advanceFireworks"
local PERK_GOLDEN_ROADS = "goldenRoads"
-- Sizing of the world-space cosmetics lives here for the same reason MonetizationService keeps
-- the VIP tag's: they are server instances, not client Theme values. The title tag sits one VIP
-- tag height above the VIP tag's offset so the two stack when both exist.
local TITLE_TAG_NAME = "TitleTag"
local TITLE_TAG_WIDTH_STUDS = 4
local TITLE_TAG_HEIGHT_STUDS = 0.8
local TITLE_TAG_OFFSET_STUDS = 3.3
local MONUMENT_LIGHT_NAME = "MonumentGlow"
local MONUMENT_LIGHT_BRIGHTNESS = 2
local MONUMENT_LIGHT_RANGE = 24
-- M7: mesh monuments glow through a Highlight (a MeshPart's texture would swallow Neon).
local MONUMENT_HIGHLIGHT_NAME = "MonumentGlow"
local MONUMENT_HIGHLIGHT_FILL_TRANSPARENCY = 0.6
local MONUMENT_HIGHLIGHT_OUTLINE_TRANSPARENCY = 0.2
local FIREWORKS_NAME = "AdvanceFireworks"
local FIREWORKS_SECONDS = 2
local FIREWORKS_RATE = 60
local FIREWORKS_SPEED = 25
local FIREWORKS_LIFETIME = 2
local FIREWORKS_SIZE = 1.5
local FIREWORKS_SPREAD_DEGREES = 40
-- Character tracking for the title tag (the head can replicate a frame after CharacterAdded).
local HEAD_WAIT_SECONDS = 5

local characterConnections: { [Player]: RBXScriptConnection } = {}

-- Owned AND present in the config: a perk id left in a profile after a config edit is ignored.
local function ownsCosmetic(state: Types.PlayerState, perkId: string): boolean
	return Economy.PerkValue(Catalog.GetLegacyShopConfig(), state.legacyShop, perkId) ~= nil
end

-- "#RRGGBB" from LegacyShop.json; nil (cosmetic skipped) on anything malformed, never an error.
local function perkColor(perkId: string): Color3?
	local perkDef = Catalog.GetPerkDef(perkId)
	local hex = if perkDef ~= nil then perkDef.color else nil
	if hex == nil then
		return nil
	end
	local ok, color = pcall(Color3.fromHex, hex)
	return if ok then color else nil
end

-- Creates or removes the coloured name tag to match the owner's perk; idempotent both ways.
local function applyTitleTag(player: Player): ()
	local character = player.Character
	if character == nil then
		return
	end
	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local state = DataService.GetState(player)
	local color = if state ~= nil and ownsCosmetic(state, PERK_NAME_TAG_COLOUR)
		then perkColor(PERK_NAME_TAG_COLOUR)
		else nil
	local existing = head:FindFirstChild(TITLE_TAG_NAME)
	-- The tag replaces the Humanoid's overhead name (otherwise the owner reads their name twice);
	-- removing the tag restores the default so nothing changes for anyone without the perk.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if color == nil then
		if existing ~= nil then
			existing:Destroy()
			if humanoid ~= nil then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
			end
		end
		return
	end
	if existing ~= nil then
		return
	end
	if humanoid ~= nil then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = TITLE_TAG_NAME
	billboard.Size = UDim2.fromScale(TITLE_TAG_WIDTH_STUDS, TITLE_TAG_HEIGHT_STUDS)
	billboard.StudsOffset = Vector3.new(0, TITLE_TAG_OFFSET_STUDS, 0)
	local label = Instance.new("TextLabel")
	label.Name = "Line1"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextColor3 = color
	label.Text = player.DisplayName
	label.Parent = billboard
	billboard.Parent = head
end

local function onCharacterAdded(player: Player, character: Model): ()
	task.spawn(function()
		if character:WaitForChild("Head", HEAD_WAIT_SECONDS) == nil then
			return
		end
		applyTitleTag(player)
	end)
end

-- The part a model-based cosmetic attaches to: the part itself, else the model's primary part,
-- else its first BasePart; nil for an empty model (cosmetic skipped).
local function cosmeticTargetPart(spawned: Instance): BasePart?
	if spawned:IsA("BasePart") then
		return spawned
	end
	if spawned:IsA("Model") then
		local primary = spawned.PrimaryPart
		if primary ~= nil then
			return primary
		end
		return spawned:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Monument Glow: a PointLight on the anchor part plus, for a template Model, a Highlight over
-- the whole model (it survives stage swaps, so the swap path never re-applies it); a placeholder
-- Part keeps the pre-M7 Neon look. The perk carries no colour in LegacyShop.json today, so the
-- glow takes the part's own colour until one is configured.
local function applyMonumentGlow(spawned: Instance): ()
	local target = cosmeticTargetPart(spawned)
	if target == nil then
		return
	end
	local color = perkColor(PERK_MONUMENT_GLOW) or target.Color
	if spawned:IsA("Model") then
		local highlight = Instance.new("Highlight")
		highlight.Name = MONUMENT_HIGHLIGHT_NAME
		highlight.FillColor = color
		highlight.FillTransparency = MONUMENT_HIGHLIGHT_FILL_TRANSPARENCY
		highlight.OutlineColor = color
		highlight.OutlineTransparency = MONUMENT_HIGHLIGHT_OUTLINE_TRANSPARENCY
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = spawned
	else
		target.Material = Enum.Material.Neon
	end
	local light = Instance.new("PointLight")
	light.Name = MONUMENT_LIGHT_NAME
	light.Brightness = MONUMENT_LIGHT_BRIGHTNESS
	light.Range = MONUMENT_LIGHT_RANGE
	light.Color = color
	light.Parent = target
end

-- M7 stage rule (docs/INTERFACES.md "Server behaviour"): the stage is the count of BASE
-- milestones at or below the level, so L1-9 → 0, 10-24 → 1, 25-49 → 2, 50-99 → 3, 100 → 4.
-- Pure so the rule is testable; callers pass Game.json's list, never the owner's perk list.
local function stageForLevel(level: number, milestoneLevels: { number }): number
	local stage = 0
	for _, milestone in milestoneLevels do
		if milestone <= level then
			stage += 1
		end
	end
	return stage
end

-- Only buildings grow; unlock/decor/monument templates are single-stage by contract.
local function stageForSlot(slot: Types.SlotConfig, level: number): number
	if slot.type ~= "building" then
		return 0
	end
	return stageForLevel(level, Catalog.GetGameConfig().milestoneLevels)
end

type StageMap = { [number]: Model }

-- Stage<n> Models directly under a template or live building; empty for a legacy single-model
-- template (kept whole) and for a placeholder Part.
local function stageChildren(container: Instance): StageMap
	local stages: StageMap = {}
	for _, child in container:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local digits = string.match(child.Name, STAGE_CHILD_PATTERN)
		local index = if digits ~= nil then tonumber(digits) else nil
		if index ~= nil then
			stages[index] = child
		end
	end
	return stages
end

-- The highest present stage <= wanted (a template may be missing later stages while the
-- pipeline is mid-upload); nil when none qualifies, which callers treat as "no template".
local function pickStage(stages: StageMap, wanted: number): number?
	local best: number? = nil
	for index in stages do
		if index <= wanted and (best == nil or index > best) then
			best = index
		end
	end
	return best
end

-- VIP (M7): one recoloured colormap per kit in Assets.json, applied by swapping TextureID on
-- the visible stage's MeshParts (named after their kit). Missing config or an id of 0 (not
-- uploaded yet) leaves the normal texture; nothing here can error.
local function applyVipTextures(stageModel: Model): ()
	local assets = Catalog.GetAssetsConfig()
	if assets == nil or type(assets.textures) ~= "table" then
		return
	end
	for _, descendant in stageModel:GetDescendants() do
		if not descendant:IsA("MeshPart") then
			continue
		end
		-- Optional annotation: map indexing is non-optional under the old solver.
		local texture: Types.AssetTexture? = assets.textures[descendant.Name]
		local vipImageId = if texture ~= nil then texture.vipImageId else nil
		if type(vipImageId) == "number" and vipImageId > 0 then
			descendant.TextureID = ASSET_ID_PREFIX .. tostring(vipImageId)
		end
	end
end

-- The VIP pass grants the skin, but the owner may switch it off (settings.vipSkins); nil counts as
-- on so a profile read before its migration still shows what the pass paid for. Only the skin
-- honours the toggle — the gold sign text and income bonus stay tied to the pass alone.
local function usesVipSkins(state: Types.PlayerState): boolean
	return state.passes.VIP == true and state.settings.vipSkins ~= false
end

-- Everything owner-dependent about a visible stage, in one place so the spawn and swap paths
-- cannot drift: the VIP texture, then the Golden Roads tint on unlock slots (Color multiplies
-- the texture, so the road reads as gilded rather than flat).
local function dressStage(stageModel: Model, slot: Types.SlotConfig, state: Types.PlayerState): ()
	if usesVipSkins(state) then
		applyVipTextures(stageModel)
	end
	if slot.type == "unlock" and ownsCosmetic(state, PERK_GOLDEN_ROADS) then
		local roadColor = perkColor(PERK_GOLDEN_ROADS)
		if roadColor ~= nil then
			for _, descendant in stageModel:GetDescendants() do
				if descendant:IsA("MeshPart") then
					descendant.Color = roadColor
				end
			end
		end
	end
end

-- Creates or moves Base.PromptAnchor to mid-height of the visible stage so the prompt's
-- billboard and activation radius track the building as it grows. Nil when the building has
-- no BasePart to hang it from (an empty legacy model), in which case the prompt falls back.
local function positionPromptAnchor(building: Model, stageModel: Model): Attachment?
	local base = cosmeticTargetPart(building)
	if base == nil then
		return nil
	end
	local existing = base:FindFirstChild(PROMPT_ANCHOR_NAME)
	local anchor: Attachment
	if existing ~= nil and existing:IsA("Attachment") then
		anchor = existing
	else
		anchor = Instance.new("Attachment")
		anchor.Name = PROMPT_ANCHOR_NAME
		anchor.Parent = base
	end
	-- Extents are the stage's bounding box in studs; Base sits at the footprint's bottom-centre.
	local height = stageModel:GetExtentsSize().Y
	anchor.Position = Vector3.new(0, height / 2, 0)
	return anchor
end

-- The template's ground-level Base, found by name. The PrimaryPart ref is not trusted: it can
-- arrive nil in a live session, and a Model without one pivots about its bounding-box centre,
-- which sank every building by half its height in the M7 playtest.
local function templateBase(model: Model): BasePart?
	local base = model:FindFirstChild(TEMPLATE_BASE_NAME)
	return if base ~= nil and base:IsA("BasePart") then base else nil
end

-- Clones `stage` out of the template into the live building at the same offset from the
-- building's Base as it has from the template's (pivot fallback for a template without one),
-- then dresses it and re-aims the prompt anchor. Hidden stages are never kept alive.
local function attachStage(
	template: Model,
	building: Model,
	stage: number,
	slot: Types.SlotConfig,
	state: Types.PlayerState
): Model?
	local templateStage: Model? = stageChildren(template)[stage]
	if templateStage == nil then
		return nil
	end
	local clone = templateStage:Clone()
	clone.Name = STAGE_CHILD_PREFIX .. tostring(stage)
	local sourceBase = templateBase(template)
	local targetBase = templateBase(building)
	local sourceFrame = if sourceBase ~= nil then sourceBase.CFrame else template:GetPivot()
	local targetFrame = if targetBase ~= nil then targetBase.CFrame else building:GetPivot()
	clone:PivotTo(targetFrame * sourceFrame:ToObjectSpace(templateStage:GetPivot()))
	dressStage(clone, slot, state)
	clone.Parent = building
	positionPromptAnchor(building, clone)
	return clone
end

-- The signTitle perk's title for this owner: titles[min(rebirthCount + 1, #titles)].
local function signTitleFor(state: Types.PlayerState): string?
	if not ownsCosmetic(state, PERK_SIGN_TITLE) then
		return nil
	end
	local perkDef = Catalog.GetPerkDef(PERK_SIGN_TITLE)
	local titles = if perkDef ~= nil then perkDef.titles else nil
	if titles == nil or #titles == 0 then
		return nil
	end
	return titles[math.min(state.rebirthCount + 1, #titles)]
end

-- displayName is required by era schema v1.1; a pre-v1.1 config degrades to the module key.
local function eraDisplayName(eraConfig: Types.EraConfig): string
	local displayName: string? = eraConfig.displayName
	return if displayName ~= nil and displayName ~= "" then displayName else eraConfig.name
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
		label.TextColor3 = LABEL_TEXT_COLOR
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = billboard
	end
	return billboard
end

-- Lines beyond `lines` go blank rather than being destroyed: the sign keeps its two-line
-- geometry so the second line simply appears at the first rebirth.
local function setSignLines(record: PlotRecord, lines: { string }, color: Color3): ()
	for _, child in record.signBillboard:GetChildren() do
		if not child:IsA("TextLabel") then
			continue
		end
		local index = tonumber(string.match(child.Name, "^Line(%d+)$"))
		local text: string? = if index ~= nil then lines[index] else nil
		child.Text = text or ""
		child.TextColor3 = color
	end
end

-- Spec §3 cosmetic rank: "<DisplayName>'s <era displayName>" plus "Rebirth ×n" once reborn,
-- plus the signTitle perk's title on the third line (M6) when owned.
local function refreshSign(record: PlotRecord, player: Player, state: Types.PlayerState): ()
	local eraConfig = Catalog.GetEraConfig(state.era)
	local eraName = if eraConfig ~= nil then eraDisplayName(eraConfig) else ""
	local lines = { `{player.DisplayName}'s {eraName}` }
	if state.rebirthCount > 0 then
		table.insert(lines, `Rebirth ×{state.rebirthCount}`)
	end
	local title = signTitleFor(state)
	if title ~= nil then
		-- Always the third line, so the title does not jump when the rebirth line appears.
		lines[2] = lines[2] or ""
		lines[3] = title
	end
	local color = if state.passes.VIP == true then VIP_SIGN_TEXT_COLOR else LABEL_TEXT_COLOR
	setSignLines(record, lines, color)
end

local function clearSign(record: PlotRecord): ()
	setSignLines(record, {}, LABEL_TEXT_COLOR)
end

-- True iff a milestone lies in (fromLevel, toLevel] — the granted range just crossed one. The
-- owner's list (Extra Milestone perk), never Game.json's directly.
local function crossesMilestone(
	state: Types.PlayerState,
	fromLevel: number,
	toLevel: number
): boolean
	local milestoneLevels = Economy.MilestoneLevels(
		Catalog.GetLegacyShopConfig(),
		state.legacyShop,
		Catalog.GetGameConfig()
	)
	for _, milestone in milestoneLevels do
		if milestone > fromLevel and milestone <= toLevel then
			return true
		end
	end
	return false
end

-- Forward-declared: defined with the spawn helpers below (it needs findTemplate), used here.
local swapStage: (
	record: PlotRecord,
	slot: Types.SlotConfig,
	eraName: string,
	state: Types.PlayerState,
	fromLevel: number,
	toLevel: number
) -> number?

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
	-- Cash actually charged, for the single analytics sink event this action logs (a grant of
	-- n levels is one event, never n) — stays 0 on the Studio free-buy path.
	local charged = 0
	if isStudio and gameConfig.debug.studioFreeBuy then
		-- Free-buy skips affordability entirely: grant the full clamped count, charge nothing.
		granted = wanted
	else
		-- Accumulating per-step costs equals LevelUpCostTotal for the granted range and finds
		-- the affordable count in the same pass. Master Builders (M6) is applied inside
		-- LevelUpCost only, so the Build panel's preview and this charge cannot disagree.
		local discount = Economy.LevelCostDiscount(Catalog.GetLegacyShopConfig(), state.legacyShop)
		local totalCost = 0
		for step = 1, wanted do
			local stepCost =
				Economy.LevelUpCost(slot.baseCost, slotState.level + step, gameConfig, discount)
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
		charged = totalCost
	end

	local fromLevel = slotState.level
	slotState.level += granted
	if slotState.level >= gameConfig.maxLevel then
		-- Optional annotation: map indexing is non-optional under the old solver.
		local prompt: ProximityPrompt? = record.prompts[slotId]
		if prompt ~= nil then
			prompt.Enabled = false
		end
	end
	-- Swap before MarkDirty/FX so the new Stage<n> replicates ahead of the events (as the
	-- reveal does for the whole building).
	local newStage = swapStage(record, slot, eraConfig.name, state, fromLevel, slotState.level)
	publishCityAttributes(record, state)
	EconomyService.MarkDirty(player, { cash = true, income = true, slotIds = { slotId } })
	AnalyticsService.LogCashSink(player, charged, state.cash, `level:{eraConfig.name}:{slotId}`)
	fireFx(player, {
		kind = "levelUp",
		slotId = slotId,
		fromLevel = fromLevel,
		toLevel = slotState.level,
		milestone = crossesMilestone(state, fromLevel, slotState.level),
	})
	if newStage ~= nil then
		fireFx(player, { kind = "stageUp", slotId = slotId, stage = newStage })
	end
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

-- Template lookup order (M3 contract): <EraName>_VIP when the owner holds VIP, then <EraName>,
-- then nil (placeholder). Only Model instances count; a stray Folder/Part is not a template.
local function findTemplate(eraName: string, modelName: string, vipSkins: boolean): Model?
	local assetsFolder = ServerStorage:FindFirstChild("Assets")
	if assetsFolder == nil then
		return nil
	end
	local folderNames: { string } = if vipSkins
		then { eraName .. VIP_ASSET_SUFFIX, eraName }
		else { eraName }
	for _, folderName in folderNames do
		local eraAssets = assetsFolder:FindFirstChild(folderName)
		local template = if eraAssets ~= nil then eraAssets:FindFirstChild(modelName) else nil
		if template ~= nil and template:IsA("Model") then
			return template
		end
	end
	return nil
end

-- state drives the owner-dependent looks: the VIP texture (M7), and the monumentGlow/
-- goldenRoads perks (M6). Template path (M7): clone at the stage for the slot's level, keeping
-- only that Stage<n>; a template with Stage children but none <= the wanted stage degrades to
-- the placeholder, and a template with no Stage children at all is a legacy single model.
local function spawnBuilding(
	record: PlotRecord,
	slot: Types.SlotConfig,
	eraName: string,
	layout: Types.EraLayout,
	state: Types.PlayerState
): ()
	local vipSkins = usesVipSkins(state)
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

	if slot.streetOnly == true then
		-- The client repaves the streets when it sees this marker (INTERFACES "Wave 1e"); a kit
		-- road tile on the pad would only duplicate, or sit on top of, the real street.
		local marker = Instance.new("Model")
		marker.Name = "Building_" .. slot.id
		marker.WorldPivot = anchorCFrame
		marker.Parent = record.buildingsFolder
		return
	end

	local spawned: Instance
	local promptParent: Instance? = nil
	local template = findTemplate(eraName, slot.modelName, vipSkins)
	local chosenStage: number? = nil
	if template ~= nil then
		local stages = stageChildren(template)
		if next(stages) ~= nil then
			local owned = state.slots[slot.id]
			local level = if owned ~= nil then owned.level else 1
			chosenStage = pickStage(stages, stageForSlot(slot, level))
			if chosenStage == nil then
				template = nil
			end
		end
	end
	if template ~= nil then
		local model = template:Clone()
		model.Name = "Building_" .. slot.id
		local base = templateBase(model)
		if base ~= nil then
			model.PrimaryPart = base
		end
		if chosenStage ~= nil then
			for index, stageModel in stageChildren(model) do
				if index ~= chosenStage then
					stageModel:Destroy()
				else
					dressStage(stageModel, slot, state)
					promptParent = positionPromptAnchor(model, stageModel)
				end
			end
		end
		-- A spur runs under the building to its anchor; without the lift it draws over any floor,
		-- ramp or step lower than the path surface.
		local dressing = Catalog.GetCityDressingConfig()
		local lift = if dressing ~= nil and dressing.paths ~= nil
			then dressing.paths.buildingLift or 0
			else 0
		model:PivotTo(anchorCFrame * CFrame.new(0, lift, 0))
		model.Parent = record.buildingsFolder
		spawned = model
	else
		-- Placeholder fallback (spec §5): fully playable before any Kenney asset is imported.
		local part = Instance.new("Part")
		part.Name = "Building_" .. slot.id
		part.Anchored = true
		part.Size = layout.placeholderSize
		part.CFrame = anchorCFrame * CFrame.new(0, layout.placeholderSize.Y / 2, 0)
		if slot.type == "unlock" and ownsCosmetic(state, PERK_GOLDEN_ROADS) then
			local roadColor = perkColor(PERK_GOLDEN_ROADS)
			if roadColor ~= nil then
				part.Color = roadColor
			end
		end
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

	if slot.type == "monument" and ownsCosmetic(state, PERK_MONUMENT_GLOW) then
		applyMonumentGlow(spawned)
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
		-- A ProximityPrompt is inert unless its parent is a BasePart or Attachment: the
		-- template's Base.PromptAnchor (mid-height, so the billboard and reach are not measured
		-- from the floor), else a legacy model's first part, else the placeholder Part itself.
		prompt.Parent = promptParent or cosmeticTargetPart(spawned) or spawned
		record.prompts[slot.id] = prompt
	end
end

-- M7 stage swap after a level-up: when the base-milestone stage changed, replace the live
-- building's Stage<n> with the template's. Returns the stage now shown, or nil when nothing
-- changed (placeholder, same stage, or the template lacks anything new to show) so the caller
-- fires stageUp only for a real visual change. The Highlight/PointLight cosmetics sit on the
-- model and Base, so they survive; the stage-level dressing is re-applied by attachStage.
function swapStage(
	record: PlotRecord,
	slot: Types.SlotConfig,
	eraName: string,
	state: Types.PlayerState,
	fromLevel: number,
	toLevel: number
): number?
	if stageForSlot(slot, fromLevel) == stageForSlot(slot, toLevel) then
		return nil
	end
	local building = record.buildingsFolder:FindFirstChild("Building_" .. slot.id)
	if building == nil or not building:IsA("Model") then
		return nil
	end
	local template = findTemplate(eraName, slot.modelName, usesVipSkins(state))
	if template == nil then
		return nil
	end
	local chosen = pickStage(stageChildren(template), stageForSlot(slot, toLevel))
	if chosen == nil then
		return nil
	end
	local liveStages = stageChildren(building)
	local alreadyShown: Model? = liveStages[chosen]
	if alreadyShown ~= nil then
		return nil
	end
	if attachStage(template, building, chosen, slot, state) == nil then
		return nil
	end
	for _, stageModel in liveStages do
		stageModel:Destroy()
	end
	return chosen
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
	-- Pads bypass remotes, so spend from the RequestBuy bucket as well: one rate-limit budget
	-- across both buy paths (M5 audit), with the same silent-drop-on-overflow semantics.
	if not RemoteService.TryConsumeToken(player, "RequestBuy") then
		return
	end
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
	local charged = 0
	if not freeBuy then
		if state.cash < slot.baseCost then
			sendFailure(player, "buy", slotId, "insufficientFunds")
			return
		end
		state.cash -= slot.baseCost
		charged = slot.baseCost
	end
	-- Level Floor (M6): building slots start at the perk's level (unlock/decor/monument stay at
	-- 1). Floor levels count toward LegacyGain by design (docs/LEGACY_SHOP.md §8); the reveal
	-- event is unchanged — no levelUp event for the floor.
	local startLevel = 1
	if slot.type == "building" then
		startLevel = math.clamp(
			Economy.LevelFloor(Catalog.GetLegacyShopConfig(), state.legacyShop),
			1,
			gameConfig.maxLevel
		)
	end
	state.slots[slotId] = { level = startLevel }

	local layout = Catalog.GetLayout(eraConfig.name)
	if layout ~= nil then
		spawnBuilding(record, slot, eraConfig.name, layout, state)
		refreshPads(record, state, eraConfig, layout)
	end
	-- After the spawn so the client sees Building_<slotId> (its spur) no later than the new tier.
	publishCityAttributes(record, state)
	EconomyService.MarkDirty(player, { cash = true, income = true, slotIds = { slotId } })
	AnalyticsService.LogCashSink(player, charged, state.cash, `slot:{eraConfig.name}:{slotId}`)
	-- After spawn + MarkDirty so the Building_<slotId> instance replicates ahead of the event.
	fireFx(player, {
		kind = "reveal",
		slotId = slotId,
		slotType = slot.type,
		modelName = slot.modelName,
	})
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
local function rebuildPlotContents(record: PlotRecord, state: Types.PlayerState): ()
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
			spawnBuilding(record, slot, eraConfig.name, layout, state)
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

-- Every era (re)configuration — claim, cosmetic refresh, advance, rebirth — ends here, so the
-- M9 attributes cannot be skipped by a new caller. Published after the buildings exist so a
-- client rebuilding on an EraName change already sees them; also on a bare (layout-less) plot.
local function rebuildPlotForEra(record: PlotRecord, state: Types.PlayerState): ()
	rebuildPlotContents(record, state)
	publishCityAttributes(record, state)
end

-- Inheritance (M6): cash worth the first N slots of the era just entered, granted after the
-- reset so it lands in the new era. Cash only — slots are still bought in order.
local function grantInheritance(player: Player, state: Types.PlayerState): ()
	local newEra = Catalog.GetEraConfig(state.era)
	if newEra == nil then
		return
	end
	local cash = Economy.InheritanceCash(newEra, Catalog.GetLegacyShopConfig(), state.legacyShop)
	if cash <= 0 then
		return
	end
	state.cash += cash
	state.stats.totalCashAllTime += cash
	AnalyticsService.LogCashSource(player, cash, state.cash, "Gameplay", "inheritance")
end

-- advanceFireworks (M6): a short server-side burst at the new era's monument anchor (the old
-- monument was just torn down), visible to everyone. Enabled is toggled with task.delay and the
-- emitter part removed once the last particle has expired.
local function spawnFireworks(record: PlotRecord, state: Types.PlayerState): ()
	if not ownsCosmetic(state, PERK_ADVANCE_FIREWORKS) then
		return
	end
	local origin = record.base.CFrame * CFrame.new(0, record.base.Size.Y / 2, 0)
	local eraConfig = Catalog.GetEraConfig(state.era)
	if eraConfig ~= nil then
		for _, slot in eraConfig.slots do
			local anchor = record.base:FindFirstChild("Slot_" .. slot.id)
			if slot.type == "monument" and anchor ~= nil and anchor:IsA("Attachment") then
				origin = anchor.WorldCFrame
				break
			end
		end
	end
	local part = Instance.new("Part")
	part.Name = FIREWORKS_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = origin
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = FIREWORKS_RATE
	emitter.Speed = NumberRange.new(FIREWORKS_SPEED)
	emitter.Lifetime = NumberRange.new(FIREWORKS_LIFETIME)
	emitter.Size = NumberSequence.new(FIREWORKS_SIZE)
	emitter.SpreadAngle = Vector2.new(FIREWORKS_SPREAD_DEGREES, FIREWORKS_SPREAD_DEGREES)
	emitter.LightEmission = 1
	emitter.Enabled = true
	emitter.Parent = part
	part.Parent = record.folder
	task.delay(FIREWORKS_SECONDS, function()
		emitter.Enabled = false
	end)
	task.delay(FIREWORKS_SECONDS + FIREWORKS_LIFETIME, function()
		part:Destroy()
	end)
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
	local fromEra = state.era
	local legacyGained = Economy.LegacyGain(
		state.era,
		totalLevelsThisEra,
		state.rebirthCount,
		Catalog.GetGameConfig()
	)
	state.legacy += legacyGained
	state.era += 1
	state.cash = 0
	state.slots = {}
	state.stats.erasCompleted += 1
	grantInheritance(player, state)
	rebuildPlotForEra(record, state)
	refreshSign(record, player, state)
	spawnFireworks(record, state)
	AnalyticsService.LogLegacySource(player, legacyGained, state.legacy, `era:{fromEra}`)
	AnalyticsService.LogEraProgression(player, fromEra, false)
	-- Restamp the persisted rate NOW (0 for the empty era): a disconnect before the next tick
	-- must not save the completed era's rate for ApplyOfflineGrant to pay into the new era.
	EconomyService.RefreshPersistedRate(player)
	-- Ceremony event BEFORE the snapshot so the overlay opens first and the panel rebuilds
	-- behind it (M3 contract).
	fireFx(player, {
		kind = "eraAdvance",
		fromEra = fromEra,
		toEra = state.era,
		legacyGained = legacyGained,
	})
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
	local fromEra = state.era
	local legacyGained = Economy.LegacyGain(
		state.era,
		totalLevelsThisEra,
		state.rebirthCount,
		Catalog.GetGameConfig()
	)
	state.legacy += legacyGained
	state.rebirthCount += 1
	state.era = FIRST_ERA_INDEX
	state.cash = 0
	state.slots = {}
	state.stats.erasCompleted += 1
	grantInheritance(player, state)
	rebuildPlotForEra(record, state)
	refreshSign(record, player, state)
	spawnFireworks(record, state)
	AnalyticsService.LogLegacySource(player, legacyGained, state.legacy, `era:{fromEra}`)
	AnalyticsService.LogEraProgression(player, fromEra, true)
	-- Same as tryAdvanceEra: never let the Era-4 rate persist next to Era 1's empty slots.
	EconomyService.RefreshPersistedRate(player)
	-- Ceremony event before the snapshot, as in tryAdvanceEra.
	fireFx(player, {
		kind = "rebirth",
		fromEra = fromEra,
		toEra = state.era,
		legacyGained = legacyGained,
		rebirthCount = state.rebirthCount,
	})
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

	-- Plots are radial rectangles, so neighbours converge toward the hub and their inner
	-- corners collide first. Size the ring so each inner corner stays plotMargin / 2 clear of
	-- the radial line splitting two plots; coplanar overlapping bases z-fight at the seam.
	local halfSector = math.pi / plotCount
	local ringRadius = math.max(
		plotSize.Z / 2
			+ (plotSize.X / 2 * math.cos(halfSector) + gameConfig.plotMargin / 2)
				/ math.sin(halfSector),
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

		-- Plot sign (M3): a post as thin as a pad is tall, straddling the front-edge center
		-- (local -Z, the hub-facing edge) and rising one placeholder height. Layouts keep every
		-- pad inside the base with padOffset clearance, so the edge line never overlaps one, and
		-- CanCollide stays off so the hub walkway is unobstructed. Text is blank until claimed.
		local signHeight = layout.placeholderSize.Y
		local sign = Instance.new("Part")
		sign.Name = "Sign"
		sign.Anchored = true
		sign.CanCollide = false
		sign.Size = Vector3.new(layout.padSize.Y, signHeight, layout.padSize.Y)
		sign.CFrame = base.CFrame * CFrame.new(0, plotSize.Y / 2 + signHeight / 2, -plotSize.Z / 2)
		-- Wide enough for "<DisplayName>'s Orbital Colony" at readable height from the hub.
		local signLabelHeight = layout.placeholderSize.Y / 2
		-- Three line slots: owner, rebirth rank, and the M6 signTitle perk's title.
		local signBillboard = createLabelBillboard(
			{ "", "", "" },
			plotSize.X / 4,
			signLabelHeight,
			signHeight / 2 + signLabelHeight / 2
		)
		signBillboard.Parent = sign
		sign.Parent = plotFolder

		local record: PlotRecord = {
			index = index,
			folder = plotFolder,
			base = base,
			buildingsFolder = buildingsFolder,
			padsFolder = padsFolder,
			signBillboard = signBillboard,
			owner = nil,
			connections = {},
			padTouchLast = {},
			prompts = {},
		}
		-- Before parenting, so clients never observe a plot without its attributes.
		publishLobbyAttributes(record)
		plotFolder.Parent = plotsFolder
		table.insert(plots, record)
	end
end

local PlotService = {}

-- M7 stage rule, exported for tests and the reviewer; see the local above. Pass Game.json's
-- milestoneLevels: the Legacy milestone75 perk changes income, never the visual stage.
function PlotService.stageForLevel(level: number, milestoneLevels: { number }): number
	return stageForLevel(level, milestoneLevels)
end

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
	refreshSign(record, player, state)
	applyTitleTag(player)
end

-- MonetizationService calls this when a pass is granted mid-session and LegacyShopService after
-- every perk purchase. Re-runs the bulk-restore path, which re-resolves every owned building
-- through spawnBuilding (stage selection, VIP texture, M6 perk cosmetics), and re-tints the plot sign
-- and name tag — silently, per bulk-restore rules: no FxEvents, no tweens, no sounds.
function PlotService.RefreshCosmetics(player: Player): ()
	local record = plotsByPlayer[player]
	local state = DataService.GetState(player)
	if record == nil or state == nil then
		return
	end
	rebuildPlotForEra(record, state)
	refreshSign(record, player, state)
	applyTitleTag(player)
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
	clearSign(record)
	publishLobbyAttributes(record)
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

function PlotService.Start(): ()
	-- Title-tag listeners only (mirrors MonetizationService's VIP tag); per-player lifecycle
	-- stays in Main's orchestration, so these are deliberately order-independent.
	local function trackPlayer(player: Player): ()
		characterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end)
		local character = player.Character
		if character ~= nil then
			onCharacterAdded(player, character)
		end
	end

	Players.PlayerAdded:Connect(trackPlayer)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		-- Optional annotation: map indexing is non-optional under the old solver.
		local connection: RBXScriptConnection? = characterConnections[player]
		if connection ~= nil then
			connection:Disconnect()
			characterConnections[player] = nil
		end
	end)
end

return PlotService
