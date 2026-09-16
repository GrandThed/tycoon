--!strict
-- City dressing prop clones (docs/INTERFACES.md "M9 contracts": "Props", "Principles"). Every
-- dressing instance the City modules create passes through Seal, and every template clone
-- through Spawn, so the no-collision rule and the hide-until-loaded gate live in one place.
--
-- Templates are read from ReplicatedStorage/Assets/Props/<Era>/<PropName> and share the
-- building template shape (invisible `Base` at the bottom-centre anchor, `Stage<n>` Models).
-- Any missing link in that path is "feature off": Spawn returns nil and nothing is logged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local AssetPreloader =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("AssetPreloader"))

-- Rojo mapping and template shape frozen in docs/INTERFACES.md (M7 "Template shape", M9 "Props").
local ASSETS_FOLDER = "Assets"
local PROPS_FOLDER = "Props"
local TEMPLATE_BASE_NAME = "Base"
local STAGE_CHILD_PATTERN = "^Stage(%d+)$"
-- ChosenStage's answer for a template without Stage children (kept whole, like a legacy
-- building template), so a caller comparing stages never swaps it.
local WHOLE_TEMPLATE_STAGE = 0

type StageMap = { [number]: Model }

-- Templates whose content has finished (or given up) loading; later clones show at once.
local loadedTemplates: { [Model]: boolean } = {}
-- Parts hidden while their template loads, released together by one waiter per template.
local waitingParts: { [Model]: { BasePart } } = {}

local function sealPart(part: BasePart): ()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

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

-- Same rule as PlotService.pickStage: the highest present stage <= wanted, nil when none.
local function pickStage(stages: StageMap, wanted: number): number?
	local best: number? = nil
	for index in stages do
		if index <= wanted and (best == nil or index > best) then
			best = index
		end
	end
	return best
end

-- One waiter per template: forty trees cloned in one frame share a single PreloadAsync pass.
-- The template (in ReplicatedStorage) carries the same MeshIds/TextureIDs as every clone.
local function gate(template: Model, clone: Model): ()
	if loadedTemplates[template] then
		return
	end
	local parts: { BasePart } = {}
	local hasMesh = false
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			hasMesh = hasMesh or descendant:IsA("MeshPart")
		end
	end
	if not hasMesh then
		return
	end
	local waiting = waitingParts[template]
	local startWaiter = waiting == nil
	if waiting == nil then
		waiting = {}
		waitingParts[template] = waiting
	end
	for _, part in parts do
		part.LocalTransparencyModifier = 1
		table.insert(waiting :: { BasePart }, part)
	end
	if not startWaiter then
		return
	end
	task.spawn(function()
		AssetPreloader.AwaitInstance(template, Theme.ASSET_LOAD_TIMEOUT_SECONDS)
		-- A timeout counts as loaded too: grey beats invisible, and it must not re-hide later clones.
		loadedTemplates[template] = true
		local released = waitingParts[template]
		waitingParts[template] = nil
		if released ~= nil then
			for _, part in released do
				-- Parts destroyed meanwhile accept the write harmlessly.
				part.LocalTransparencyModifier = 0
			end
		end
	end)
end

local PropFactory = {}

-- Applied to fresh Parts and to every clone: a stale template may still carry collision flags.
function PropFactory.Seal(root: Instance): ()
	if root:IsA("BasePart") then
		sealPart(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			sealPart(descendant)
		end
	end
end

function PropFactory.Template(eraName: string, propName: string?): Model?
	if propName == nil or propName == "" then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER)
	local props = if assets ~= nil then assets:FindFirstChild(PROPS_FOLDER) else nil
	local era = if props ~= nil then props:FindFirstChild(eraName) else nil
	local template = if era ~= nil then era:FindFirstChild(propName) else nil
	if template ~= nil and template:IsA("Model") then
		return template
	end
	return nil
end

-- The stage a Spawn with `wanted` would show, or nil when it would spawn nothing.
function PropFactory.ChosenStage(eraName: string, propName: string?, wanted: number): number?
	local template = PropFactory.Template(eraName, propName)
	if template == nil then
		return nil
	end
	local stages = stageChildren(template)
	if next(stages) == nil then
		return WHOLE_TEMPLATE_STAGE
	end
	return pickStage(stages, wanted)
end

-- Clones the prop at the chosen stage, pivots its bottom-centre Base onto `cframe` (the
-- spawnBuilding convention: front -Z), drops the invisible Base so a prop costs one piece,
-- seals it, gates it on its content and parents it. Nil when the template or stage is missing.
function PropFactory.Spawn(
	eraName: string,
	propName: string?,
	wanted: number,
	cframe: CFrame,
	parent: Instance?
): Model?
	local template = PropFactory.Template(eraName, propName)
	if template == nil then
		return nil
	end
	local stages = stageChildren(template)
	local chosen: number? = nil
	if next(stages) ~= nil then
		chosen = pickStage(stages, wanted)
		if chosen == nil then
			return nil
		end
	end
	local clone = template:Clone()
	if chosen ~= nil then
		for index, stageModel in stageChildren(clone) do
			if index ~= chosen then
				stageModel:Destroy()
			end
		end
	end
	local base = clone:FindFirstChild(TEMPLATE_BASE_NAME)
	if base ~= nil and base:IsA("BasePart") then
		clone.PrimaryPart = base
	end
	clone:PivotTo(cframe)
	if base ~= nil and base:IsA("BasePart") then
		base:Destroy()
	end
	PropFactory.Seal(clone)
	gate(template, clone)
	if parent ~= nil then
		clone.Parent = parent
	end
	return clone
end

return PropFactory
