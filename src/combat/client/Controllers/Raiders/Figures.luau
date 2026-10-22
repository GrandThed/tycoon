--!strict
-- The raiders' model bodies (docs/prompts/l4-w2-contract.md, sections 3.2 and 3.3;
-- docs/prompts/l4-w2-reports/raiders.md). CrowdRenderer owns every body's record, its clocks and
-- its reactions; this module owns what a body of a kind with a model looks like.
--
-- * A kind is drawn as a model when Config/RaiderModels.json names it, its height, radius and
--   headRadius equal the kind's in ProvingGrounds.json, and its template
--   (ReplicatedStorage.Assets.Props.<folder>.<model>: Base plus a Stage per piece) carries every
--   MeshPart the entry names. Anything less is today's placeholder figure (L4W2-8), with one
--   warning for a kind the config names; kinds it does not name (the guard, the Warlord, the
--   Colossus, the range's dummies) are placeholders by design and say nothing.
-- * One pool per kind (Prewarm fills it from RunState.prewarm; an empty pool builds on demand).
--   A figure is the template's clone: five pieces whose MeshParts keep their rest frames relative
--   to Base, an invisible ball `Head` at the scored head (what GetHead, PlateBar and CampFx's "!"
--   hang on), the Chief's Warhammer and, through Cues, the kind's lit piece.
-- * Every frame a body moves, RaiderPose.Rig turns the pose into five transforms and Queue writes
--   every MeshPart, the anchor, the lit piece and the hammer into CrowdRenderer's one BulkMoveTo.
--   Pose (the walk cycle and the arm) runs first and says whether anything moved, so an idle
--   crowd still costs nothing.
-- * Paint is RaiderPose.Paint per role (cloth, clothLeg, skin, glow); gear is never painted and
--   keeps its texture; every painted MeshPart's TextureID is cleared once per clone (L4W2-10).
--   The plate role carries today's shell rule (raiders.md section 3). Everything fades with the
--   body; the anchor is never seen.
-- * Shadows: only the torso piece's, none on a low-end device (L4W2-15). The walk stops past
--   RaiderModels.json rig.walkNearStuds from the camera, COMBAT_RAIDER_WALK_NEAR_LOW on a
--   low-end device. Tells, cues and the plate are never thinned.
-- * Reactions that follow a landed hit (the death fling and topple, a vanish) are whole-body
--   transforms of the rest pose (QueueRest), as raiderpose.py exempts them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local Theme = require(script.Parent.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local RaiderPose = require(script.Parent:WaitForChild("RaiderPose"))
local Cues = require(script.Parent.Parent:WaitForChild("ThreatFx"):WaitForChild("Cues"))

-- RaiderPose's piece order; a config entry names each once.
local PIECE_NAMES = { "head", "torso", "arm", "legL", "legR" }
local TORSO_INDEX = 2
local POINT_NAMES = { "head", "neck", "hipL", "hipR", "shoulder" }
local RIG_KEYS = {
	"headKeep",
	"headNod",
	"headTurn",
	"legSwing",
	"armSwing",
	"walkLean",
	"strideLegs",
	"walkFullShare",
	"walkNearStuds",
	"stepShare",
	"seatLean",
	"seatSplay",
	"airTuck",
	"throwShare",
}
local ARM_KEYS = { "carry", "seat", "slump" }
local SHAPE_KEYS = { "coil", "strike", "follow" }
-- A MeshPart's role (raiders.md sections 3 and 5). gear keeps the template's look.
local ROLES: { [string]: boolean } =
	{ gear = true, cloth = true, clothLeg = true, skin = true, glow = true, plate = true }
local PAINTED_ROLES = { "cloth", "clothLeg", "skin", "glow" }
local TEMPLATE_BASE = "Base"
local ANCHOR_NAME = "Head"
-- The hammer is the L3 template's first stage, as HeldWeapons shows it.
local HELD_STAGE = "Stage0"
-- What counts as moved (CrowdRenderer's SETTLE_EPSILON): a smaller change is not redrawn.
local SETTLE = 0.002
local SIZE_EPSILON = 1e-6
local WHITE = Color3.new(1, 1, 1)

type LookPart = { name: string, role: string, rest: CFrame }
type LookPiece = { name: string, stage: string, parts: { LookPart } }
type LookHold = { template: Model, frame: CFrame, scale: number, piece: string }

-- One kind's validated model, shared by every figure of the kind. `entry` is the config entry
-- itself (RaiderPose reads it); color and speed follow the kind's def at every Look call.
export type Look = {
	kind: string,
	template: Model,
	entry: RaiderPose.Model,
	skin: { number },
	color: { number },
	speed: number,
	height: number,
	radius: number,
	headRadius: number,
	firstShape: string,
	pieces: { LookPiece },
	cue: Cues.Rig?,
	hold: LookHold?,
}

-- parts[i] = piece i's BaseParts in look.pieces[i].parts order. shown = every part the fade
-- writes plainly (not the plates, not the anchor). painted / neon = the last paint per role.
-- plateShell = 0 on, 1 gone, between = the break's share (as Cues' shell).
export type Figure = {
	look: Look,
	model: Model,
	anchor: BasePart,
	parts: { { BasePart } },
	shown: { BasePart },
	roles: { [string]: { BasePart } },
	plates: { BasePart },
	plateSizes: { Vector3 },
	hammer: { BasePart },
	hammerOffsets: { CFrame },
	walkPhase: number,
	walkAmp: number,
	lastPosition: Vector3?,
	armPitch: number,
	armYaw: number,
	armRoll: number,
	thrust: number,
	fade: number,
	painted: { [string]: Color3 },
	neon: { [string]: boolean },
	plateShell: number,
	plateGlint: boolean,
	plateWarded: boolean,
}

local enabled = true
local destroyed = false
-- Built by Configure; restDrop follows Tuning (Retune).
local consts: RaiderPose.Consts? = nil
-- kind -> its look; plain = kinds checked and drawn as placeholders (both until Retune).
local looks: { [string]: Look } = {}
local plain: { [string]: boolean } = {}
local warned: { [string]: boolean } = {}
local pools: { [string]: { Figure } } = {}
local built: { [string]: number } = {}
local everyFigure: { Figure } = {}
-- Per frame (BeginFrame): where the camera is and how far from it a body walks.
local frameState = { camera = Vector3.zero, near = 0 }
-- Scratch, reused by every body: one frame of one body is finished before the next starts.
local scratchPose = RaiderPose.NewPose()
local rigOut = RaiderPose.NewRigOut()
local rigPieces = { rigOut.head, rigOut.torso, rigOut.arm, rigOut.legL, rigOut.legR }
local paintOut = RaiderPose.NewPaintOut()
local paintThreat: RaiderPose.PaintThreat =
	{ tint = 0, tintColor = { 1, 1, 1 }, glow = false, visorHot = false }
local posed: { [string]: CFrame } = {}

local Figures = {}

local function warnOnce(key: string, message: string): ()
	if not warned[key] then
		warned[key] = true
		warn(`[Figures] {message}`)
	end
end

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function isTriple(value: any): boolean
	return typeof(value) == "table"
		and isNumber(value[1])
		and isNumber(value[2])
		and isNumber(value[3])
end

local function rgbOf(color: Color3): RaiderPose.Rgb
	return { color.R, color.G, color.B }
end

local function vectorOf(triple: { number }): Vector3
	return Vector3.new(triple[1], triple[2], triple[3])
end

-- The shared rig numbers, or nil (with one warning) when any is missing.
local function rigOf(config: any): RaiderPose.RigNumbers?
	local rig = if typeof(config) == "table" then config.rig else nil
	if typeof(rig) ~= "table" then
		warnOnce("rig", "RaiderModels.json has no rig: every kind is drawn as a placeholder")
		return nil
	end
	for _, key in RIG_KEYS do
		if not isNumber(rig[key]) then
			warnOnce(
				"rig",
				`RaiderModels.json rig.{key} is not a number: every kind is a placeholder`
			)
			return nil
		end
	end
	return rig :: RaiderPose.RigNumbers
end

-- The config's rig, checked once per config table (Catalog caches the module for good).
local rigSeen: any = nil
local rigChecked: RaiderPose.RigNumbers? = nil
local function currentRig(): RaiderPose.RigNumbers?
	local config: any = Catalog.GetRaiderModelsConfig()
	if config == nil then
		return nil
	end
	if config ~= rigSeen then
		rigSeen = config
		rigChecked = rigOf(config)
	end
	return rigChecked
end

local function templateOf(folder: any, name: any): Model?
	if typeof(folder) ~= "string" or typeof(name) ~= "string" then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = if assets ~= nil then assets:FindFirstChild("Props") else nil
	local set = if props ~= nil then props:FindFirstChild(folder) else nil
	local template = if set ~= nil then set:FindFirstChild(name) else nil
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local base = template:FindFirstChild(TEMPLATE_BASE)
	if base == nil or not base:IsA("BasePart") then
		return nil
	end
	return template
end

-- The arm's keys as RaiderPose reads them: carry, seat and slump, and per shape coil, strike and
-- follow where written, a whirl and a steady flag.
local function armProblem(arm: any): string?
	if typeof(arm) ~= "table" or typeof(arm.shapes) ~= "table" then
		return "its arm has no shapes"
	end
	for _, key in ARM_KEYS do
		if not isTriple(arm[key]) then
			return `its arm.{key} is not three numbers`
		end
	end
	for shape, keys in arm.shapes do
		if typeof(keys) ~= "table" then
			return `its arm shape {shape} is not a table`
		end
		for _, key in SHAPE_KEYS do
			if keys[key] ~= nil and not isTriple(keys[key]) then
				return `its arm shape {shape}.{key} is not three numbers`
			end
		end
		local whirl = keys.whirl
		if
			whirl ~= nil
			and not (
				typeof(whirl) == "table"
				and isNumber(whirl.turns)
				and isTriple(whirl.sin)
				and isTriple(whirl.cos)
			)
		then
			return `its arm shape {shape}.whirl is not turns, sin and cos`
		end
	end
	return nil
end

-- One piece: its stage in the template, every BasePart of it with its role (a part the entry
-- does not name is gear) and its rest frame relative to Base.
local function pieceOf(template: Model, base: BasePart, raw: any): (LookPiece?, string?)
	local name = raw.name
	if not isNumber(raw.stage) or typeof(raw.parts) ~= "table" then
		return nil, `its piece {name} has no stage or parts`
	end
	local stageName = `Stage{math.floor(raw.stage)}`
	local stage = template:FindFirstChild(stageName)
	if stage == nil or not stage:IsA("Model") then
		return nil, `the template has no {stageName} for its {name}`
	end
	local parts: { LookPart } = {}
	local seen: { [string]: boolean } = {}
	for _, child in stage:GetDescendants() do
		if child:IsA("BasePart") then
			if seen[child.Name] then
				return nil, `{stageName} holds two parts named {child.Name}`
			end
			seen[child.Name] = true
			local role = raw.parts[child.Name]
			table.insert(parts, {
				name = child.Name,
				role = if typeof(role) == "string" then role else "gear",
				rest = base.CFrame:ToObjectSpace(child.CFrame),
			})
		end
	end
	for partName, role in raw.parts do
		if typeof(role) ~= "string" or not ROLES[role] then
			return nil, `its {name} part {partName} has no known role`
		end
		if not seen[partName] then
			return nil, `the template's {stageName} has no {partName}`
		end
	end
	return { name = name, stage = stageName, parts = parts }, nil
end

-- The carried weapon (the Chief's Warhammer): its template and where it sits on its piece. A
-- missing template draws the body without it.
local function holdOf(kind: string, raw: any): LookHold?
	if raw == nil then
		return nil
	end
	if
		typeof(raw) ~= "table"
		or not isTriple(raw.grip)
		or not isTriple(raw.right)
		or not isTriple(raw.up)
		or not isNumber(raw.scale)
		or raw.scale <= 0
		or typeof(raw.piece) ~= "string"
		or table.find(PIECE_NAMES, raw.piece) == nil
	then
		warnOnce(`hold:{kind}`, `RaiderModels.json {kind}.hold is malformed: drawn without it`)
		return nil
	end
	local template = templateOf(raw.folder, raw.model)
	if template == nil then
		warnOnce(
			`hold:{kind}`,
			`no template Assets.Props.{raw.folder}.{raw.model}: {kind} is drawn without it`
		)
		return nil
	end
	return {
		template = template,
		frame = CFrame.fromMatrix(vectorOf(raw.grip), vectorOf(raw.right), vectorOf(raw.up)),
		scale = raw.scale,
		piece = raw.piece,
	}
end

local function cueOf(raw: any, points: any): (Cues.Rig?, string?)
	if raw == nil then
		return { piece = nil, point = Vector3.zero, size = nil, charged = nil }, nil
	end
	if
		typeof(raw) ~= "table"
		or typeof(raw.piece) ~= "string"
		or table.find(PIECE_NAMES, raw.piece) == nil
	then
		return nil, "its cue names no piece"
	end
	local point = if typeof(raw.point) == "string" then points[raw.point] else nil
	if not isTriple(point) then
		return nil, `its cue point {raw.point} is not one of its points`
	end
	local size = if isNumber(raw.size) and raw.size > 0 then raw.size else nil
	local charged = if isNumber(raw.charged) and raw.charged > 0 then raw.charged else nil
	return { piece = raw.piece, point = vectorOf(point), size = size, charged = charged }, nil
end

-- A kind's look from its config entry, or nil and why not.
local function lookOf(kind: string, def: Types.CrowdKindDef, config: any): (Look?, string?)
	local entry = config.kinds[kind]
	if typeof(entry) ~= "table" then
		return nil, "its entry is not a table"
	end
	local sizes = { height = def.height, radius = def.radius, headRadius = def.headRadius }
	for key, wanted in sizes do
		if not isNumber(entry[key]) or math.abs(entry[key] - wanted) > SIZE_EPSILON then
			return nil, `the model was built for {key} {entry[key]}, the kind has {wanted}`
		end
	end
	if not isNumber(entry.legLength) or entry.legLength <= 0 then
		return nil, "its legLength is not a positive number"
	end
	if typeof(entry.points) ~= "table" then
		return nil, "it has no points"
	end
	for _, name in POINT_NAMES do
		if not isTriple(entry.points[name]) then
			return nil, `its point {name} is not three numbers`
		end
	end
	local armWhy = armProblem(entry.arm)
	if armWhy ~= nil then
		return nil, armWhy
	end
	if not isTriple(entry.skin) then
		return nil, "its skin is not three numbers"
	end
	if entry.leadLeg ~= nil and entry.leadLeg ~= "legL" and entry.leadLeg ~= "legR" then
		return nil, "its leadLeg is neither legL nor legR"
	end
	if entry.armSwingShare ~= nil and not isNumber(entry.armSwingShare) then
		return nil, "its armSwingShare is not a number"
	end
	local template = templateOf(config.folder, entry.model)
	if template == nil then
		return nil, `there is no template Assets.Props.{config.folder}.{entry.model}`
	end
	local base = template:FindFirstChild(TEMPLATE_BASE) :: BasePart
	if typeof(entry.pieces) ~= "table" then
		return nil, "it has no pieces"
	end
	local pieces: { LookPiece } = {}
	for index, name in PIECE_NAMES do
		local raw = nil
		for _, candidate in entry.pieces do
			if typeof(candidate) == "table" and candidate.name == name then
				raw = candidate
			end
		end
		if raw == nil then
			return nil, `it has no {name} piece`
		end
		local piece, why = pieceOf(template, base, raw)
		if piece == nil then
			return nil, why
		end
		pieces[index] = piece
	end
	local cue, cueWhy = cueOf(entry.cue, entry.points)
	if cue == nil then
		return nil, cueWhy
	end
	local attacks = def.attacks
	local first = if attacks ~= nil then attacks[1] else nil
	local firstShape: string = if first ~= nil then first.shape else ""
	return {
		kind = kind,
		template = template,
		entry = entry :: RaiderPose.Model,
		skin = entry.skin,
		color = def.color,
		speed = def.speed,
		height = def.height,
		radius = def.radius,
		headRadius = def.headRadius,
		firstShape = firstShape,
		pieces = pieces,
		cue = cue,
		hold = holdOf(kind, entry.hold),
	},
		nil
end

local function seal(part: BasePart): ()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- The carried weapon's clone, scaled once about its grip; its parts and their frames relative
-- to the grip go into the figure.
local function addHold(figure: Figure, hold: LookHold): ()
	local weapon = hold.template:Clone()
	local base = weapon:FindFirstChild(TEMPLATE_BASE) :: BasePart
	weapon.PrimaryPart = base
	for _, child in weapon:GetChildren() do
		if
			child:IsA("Model")
			and child.Name ~= HELD_STAGE
			and string.match(child.Name, "^Stage%d+$")
		then
			child:Destroy()
		end
	end
	if hold.scale ~= 1 then
		weapon:ScaleTo(hold.scale)
	end
	for _, part in weapon:GetDescendants() do
		if part:IsA("BasePart") and part ~= base then
			seal(part)
			table.insert(figure.hammer, part)
			table.insert(figure.hammerOffsets, base.CFrame:ToObjectSpace(part.CFrame))
			table.insert(figure.shown, part)
		end
	end
	base:Destroy()
	weapon.Name = "Held"
	weapon.Parent = figure.model
end

local function build(look: Look): Figure
	local model = look.template:Clone()
	model.Name = `Raider_{look.kind}`
	local anchor = Instance.new("Part")
	anchor.Name = ANCHOR_NAME
	anchor.Shape = Enum.PartType.Ball
	anchor.Size = Vector3.one * (2 * look.headRadius)
	anchor.Transparency = 1
	seal(anchor)
	local figure: Figure = {
		look = look,
		model = model,
		anchor = anchor,
		parts = {},
		shown = {},
		roles = {},
		plates = {},
		plateSizes = {},
		hammer = {},
		hammerOffsets = {},
		walkPhase = 0,
		walkAmp = 0,
		lastPosition = nil,
		armPitch = 0,
		armYaw = 0,
		armRoll = 0,
		thrust = 0,
		fade = 0,
		painted = {},
		neon = {},
		plateShell = 1,
		plateGlint = false,
		plateWarded = false,
	}
	for _, role in PAINTED_ROLES do
		figure.roles[role] = {}
	end
	local shadows = not Theme.lowEndDevice
	for index, piece in look.pieces do
		local stage = model:FindFirstChild(piece.stage) :: Model
		local list: { BasePart } = {}
		for _, entry in piece.parts do
			local part = stage:FindFirstChild(entry.name, true) :: BasePart
			seal(part)
			part.CastShadow = shadows and index == TORSO_INDEX
			if entry.role ~= "gear" and part:IsA("MeshPart") then
				-- L4W2-10: a painted role shows its paint, whatever texture the template holds.
				part.TextureID = ""
			end
			if entry.role == "plate" then
				table.insert(figure.plates, part)
				table.insert(figure.plateSizes, part.Size)
				part.Transparency = 1
			else
				table.insert(figure.shown, part)
				local painted = figure.roles[entry.role]
				if painted ~= nil then
					table.insert(painted, part)
				end
			end
			table.insert(list, part)
		end
		figure.parts[index] = list
	end
	-- Nothing but the five pieces is ever moved: anything else in the template would stand at
	-- the template's origin.
	for _, child in model:GetChildren() do
		local used = false
		for _, piece in look.pieces do
			used = used or child.Name == piece.stage
		end
		if not used then
			child:Destroy()
		end
	end
	model.PrimaryPart = nil
	anchor.Parent = model
	local hold = look.hold
	if hold ~= nil then
		addHold(figure, hold)
	end
	built[look.kind] = (built[look.kind] or 0) + 1
	table.insert(everyFigure, figure)
	return figure
end

-- Theme's numbers and CrowdRenderer's figure colours (by the names raiderpose.py reads), as
-- RaiderPose takes them. Called once by CrowdRenderer as it loads; the table is shared from then
-- on, and restDrop is filled by the first Retune (CrowdRenderer.Start).
function Figures.Configure(renderer: {
	LEG_SHADE: Color3,
	LEG_SHADE_SHARE: number,
	VISOR_COLOR: Color3,
	VISOR_HOT_COLOR: Color3,
	FLASH_COLOR: Color3,
}): RaiderPose.Consts
	local made: RaiderPose.Consts = {
		COMBAT_RANGE_TELL_COLOR = rgbOf(Theme.COMBAT_RANGE_TELL_COLOR),
		COMBAT_RANGE_TELL_SPENT_COLOR = rgbOf(Theme.COMBAT_RANGE_TELL_SPENT_COLOR),
		COMBAT_RANGE_TELL_HEAT_SHARE = Theme.COMBAT_RANGE_TELL_HEAT_SHARE,
		COMBAT_RANGE_TELL_SPENT_SHARE = Theme.COMBAT_RANGE_TELL_SPENT_SHARE,
		COMBAT_RANGE_TELL_TINT_STEPS = Theme.COMBAT_RANGE_TELL_TINT_STEPS,
		COMBAT_RANGE_TELL_COIL_SHARE = Theme.COMBAT_RANGE_TELL_COIL_SHARE,
		COMBAT_RANGE_TELL_LEAN_BACK = Theme.COMBAT_RANGE_TELL_LEAN_BACK,
		COMBAT_RANGE_TELL_LEAN_FORWARD = Theme.COMBAT_RANGE_TELL_LEAN_FORWARD,
		COMBAT_RANGE_TELL_PULL_BACK = Theme.COMBAT_RANGE_TELL_PULL_BACK,
		COMBAT_RANGE_TELL_ARC_TWIST_SHARE = Theme.COMBAT_RANGE_TELL_ARC_TWIST_SHARE,
		COMBAT_RANGE_TELL_ARC_SWEEP_SHARE = Theme.COMBAT_RANGE_TELL_ARC_SWEEP_SHARE,
		COMBAT_RANGE_TELL_SPENT_LEAN = Theme.COMBAT_RANGE_TELL_SPENT_LEAN,
		COMBAT_RANGE_TELL_SPENT_SQUASH = Theme.COMBAT_RANGE_TELL_SPENT_SQUASH,
		COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS = Theme.COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS,
		COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS = Theme.COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS,
		COMBAT_RANGE_RING_SLAM_RISE = Theme.COMBAT_RANGE_RING_SLAM_RISE,
		COMBAT_RANGE_RING_SLAM_SQUASH = Theme.COMBAT_RANGE_RING_SLAM_SQUASH,
		COMBAT_RANGE_RING_SLAM_LEAN = Theme.COMBAT_RANGE_RING_SLAM_LEAN,
		COMBAT_RANGE_CALL_LEAN = Theme.COMBAT_RANGE_CALL_LEAN,
		COMBAT_RANGE_CALL_SHAKE = Theme.COMBAT_RANGE_CALL_SHAKE,
		COMBAT_RANGE_CALL_SHAKE_HZ = Theme.COMBAT_RANGE_CALL_SHAKE_HZ,
		COMBAT_RANGE_CALL_STRETCH = Theme.COMBAT_RANGE_CALL_STRETCH,
		COMBAT_RANGE_ENRAGE_COLOR = rgbOf(Theme.COMBAT_RANGE_ENRAGE_COLOR),
		COMBAT_RANGE_ENRAGE_SHARE = Theme.COMBAT_RANGE_ENRAGE_SHARE,
		COMBAT_RANGE_ENRAGE_GLOW_COLOR = rgbOf(Theme.COMBAT_RANGE_ENRAGE_GLOW_COLOR),
		COMBAT_RAIDER_WALK_EASE_RATE = Theme.COMBAT_RAIDER_WALK_EASE_RATE,
		COMBAT_RAIDER_WALK_SETTLE = Theme.COMBAT_RAIDER_WALK_SETTLE,
		LEG_SHADE = rgbOf(renderer.LEG_SHADE),
		LEG_SHADE_SHARE = renderer.LEG_SHADE_SHARE,
		VISOR_COLOR = rgbOf(renderer.VISOR_COLOR),
		VISOR_HOT_COLOR = rgbOf(renderer.VISOR_HOT_COLOR),
		FLASH_COLOR = rgbOf(renderer.FLASH_COLOR),
		restDrop = 0,
	}
	consts = made
	return made
end

-- The tuned numbers moved (or the first time): the seat's drop follows crowd.restDrop, and every
-- kind's look is checked again against its def.
function Figures.Retune(): ()
	local made = consts
	local crowd = Tuning.Get().crowd
	if made ~= nil then
		made.restDrop = if crowd ~= nil then crowd.restDrop or 0 else 0
	end
	table.clear(looks)
	table.clear(plain)
end

-- X in Studio: models or placeholders for every kind. CrowdRenderer re-dresses the live bodies.
function Figures.SetEnabled(on: boolean): ()
	enabled = on
end

function Figures.Enabled(): boolean
	return enabled
end

-- The look a body of `kind` wears, or nil: a placeholder.
function Figures.Look(kind: string, def: Types.CrowdKindDef): Look?
	if not enabled or destroyed or consts == nil then
		return nil
	end
	if plain[kind] then
		return nil
	end
	local cached = looks[kind]
	if cached ~= nil then
		cached.color = def.color
		cached.speed = def.speed
		return cached
	end
	local config: any = Catalog.GetRaiderModelsConfig()
	if config == nil or typeof(config.kinds) ~= "table" or currentRig() == nil then
		-- Not cached: the module or a whole rig may still show up (Catalog re-checks).
		return nil
	end
	if config.kinds[kind] == nil then
		plain[kind] = true
		return nil
	end
	local look, why = lookOf(kind, def, config)
	if look == nil then
		warnOnce(`look:{kind}`, `{kind} is drawn as a placeholder: {why}`)
		plain[kind] = true
		return nil
	end
	looks[kind] = look
	return look
end

-- A body for `look`: a pooled one of its kind, else a fresh clone. Unparented.
function Figures.Take(look: Look): Figure
	local pool = pools[look.kind]
	local pooled: Figure? = if pool ~= nil then table.remove(pool) else nil
	local figure = if pooled ~= nil then pooled else build(look)
	figure.look = look
	return figure
end

-- Back into its kind's pool, unparented and plain: the next Take repaints it.
function Figures.Give(figure: Figure): ()
	figure.model.Parent = nil
	figure.walkPhase = 0
	figure.walkAmp = 0
	figure.lastPosition = nil
	figure.armPitch, figure.armYaw, figure.armRoll = 0, 0, 0
	figure.thrust = 0
	table.clear(figure.painted)
	table.clear(figure.neon)
	Figures.Plate(figure, false, 1, false, false)
	Figures.Fade(figure, 0)
	local kind = figure.look.kind
	local pool = pools[kind]
	if pool == nil then
		pools[kind] = { figure }
	else
		table.insert(pool, figure)
	end
end

-- Builds bodies into the pools a few a frame until each kind of `counts` has its count (drawn
-- and spare), at most `cap` in all. Yields.
function Figures.Prewarm(counts: { [string]: number }, cap: number): ()
	local crowd = Tuning.Get().crowd
	if crowd == nil or crowd.kinds == nil then
		return
	end
	local kinds: { string } = {}
	for kind in counts do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	local left = cap
	local made = 0
	local perFrame = math.max(math.floor(Theme.COMBAT_RAIDER_PREWARM_PER_FRAME), 1)
	for _, kind in kinds do
		local def = crowd.kinds[kind]
		local look = if def ~= nil then Figures.Look(kind, def) else nil
		local count = counts[kind]
		if look ~= nil and isNumber(count) then
			local want = math.min(math.floor(count), left)
			left -= math.max(want, 0)
			while not destroyed and enabled and (built[kind] or 0) < want do
				Figures.Give(build(look))
				made += 1
				if made % perFrame == 0 then
					task.wait()
				end
			end
		end
	end
end

-- Once a frame before the bodies: where the camera is, and how far from it a body walks.
function Figures.BeginFrame(): ()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		frameState.camera = camera.CFrame.Position
	end
	local rig = currentRig()
	local near = if rig ~= nil then rig.walkNearStuds else 0
	frameState.near = if Theme.lowEndDevice
		then math.min(near, Theme.COMBAT_RAIDER_WALK_NEAR_LOW)
		else near
end

-- The flat lean along the body's facing (+ forward) and across it (+ toward its right): the two
-- numbers RaiderPose leans with, taken from the lean vector CrowdRenderer keeps.
local function leanParts(yaw: number, lean: Vector3): (number, number)
	local s, c = math.sin(yaw), math.cos(yaw)
	return lean.X * -s + lean.Z * -c, lean.X * c + lean.Z * -s
end

-- One frame of the walk cycle and the arm, before CrowdRenderer decides whether the body is
-- redrawn: true when either moved. `position` = the drawn feet without reaction offsets;
-- `threat` = this frame's RaiderPose.Threat (nil = no attack), `shape` its attack's shape and
-- `attack` its windup and lock.
function Figures.Pose(
	figure: Figure,
	dt: number,
	position: Vector3,
	yaw: number,
	lean: Vector3,
	threat: RaiderPose.ThreatOut?,
	shape: string,
	attack: RaiderPose.ThreatIn?,
	seat: number,
	thrust: number
): boolean
	local made = consts
	local rig = currentRig()
	if made == nil or rig == nil then
		return false
	end
	local look = figure.look
	local last = figure.lastPosition
	local travel = 0
	if last ~= nil then
		local dx, dz = position.X - last.X, position.Z - last.Z
		travel = math.sqrt(dx * dx + dz * dz)
	end
	figure.lastPosition = position
	local distance = (position - frameState.camera).Magnitude
	local phase, amp = RaiderPose.Walk(
		figure.walkPhase,
		figure.walkAmp,
		travel,
		dt,
		look.speed,
		look.entry.legLength,
		distance,
		frameState.near,
		rig,
		made
	)
	local pose = scratchPose
	pose.lean = leanParts(yaw, lean)
	pose.seat = seat
	pose.walkPhase = phase
	pose.walkAmp = amp
	local live = threat ~= nil and threat.phase ~= "none"
	local pitch, turn, roll = RaiderPose.Arm(
		look.entry,
		if live then shape else look.firstShape,
		threat,
		pose,
		rig,
		attack
	)
	-- The phase moves nothing while the amplitude is 0 (a body too far to walk, or standing).
	local moved = (amp > 0 and phase ~= figure.walkPhase)
		or amp ~= figure.walkAmp
		or math.abs(pitch - figure.armPitch) > SETTLE
		or math.abs(turn - figure.armYaw) > SETTLE
		or math.abs(roll - figure.armRoll) > SETTLE
		or math.abs(thrust - figure.thrust) > SETTLE
	figure.walkPhase, figure.walkAmp = phase, amp
	if moved then
		figure.armPitch, figure.armYaw, figure.armRoll = pitch, turn, roll
		figure.thrust = thrust
	end
	return moved
end

-- Every posed piece under `root` (the body's feet, and a launch's tumble) into the move queue:
-- the MeshParts, the anchor at the scored head, the lit piece and the carried weapon.
local function lay(
	figure: Figure,
	root: CFrame,
	cues: Cues.CueSet?,
	parts: { BasePart },
	frames: { CFrame },
	count: number
): number
	local look = figure.look
	for index, name in PIECE_NAMES do
		local t = rigPieces[index]
		local world = root
			* CFrame.new(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12])
		posed[name] = world
		local rests = look.pieces[index].parts
		for slot, part in figure.parts[index] do
			count += 1
			parts[count] = part
			frames[count] = world * rests[slot].rest
		end
	end
	count += 1
	parts[count] = figure.anchor
	frames[count] = root * CFrame.new(0, rigOut.anchorY, 0)
	if cues ~= nil then
		count = Cues.QueueRig(cues, posed, parts, frames, count)
	end
	local hold = look.hold
	if hold ~= nil and #figure.hammer > 0 then
		local grip = posed[hold.piece] * hold.frame
		local offsets = figure.hammerOffsets
		for slot, part in figure.hammer do
			count += 1
			parts[count] = part
			frames[count] = grip * offsets[slot]
		end
	end
	return count
end

-- A living body's frame: `root` = its feet (with a launch's tumble), yaw its heading, twist what
-- the attack or a reel turns its upper body by, lean CrowdRenderer's lean vector (flinches
-- included), squash as drawn (hundredths). The walk, the arm and the thrust are Pose's.
function Figures.Queue(
	figure: Figure,
	root: CFrame,
	yaw: number,
	twist: number,
	lean: Vector3,
	squash: number,
	seat: number,
	airborne: boolean,
	cues: Cues.CueSet?,
	parts: { BasePart },
	frames: { CFrame },
	count: number
): number
	local made = consts
	local rig = currentRig()
	if made == nil or rig == nil then
		return count
	end
	local pose = scratchPose
	pose.yaw = yaw
	pose.lean, pose.leanSide = leanParts(yaw, lean)
	pose.twist = twist
	pose.squash = squash
	pose.thrust = figure.thrust
	pose.seat = seat
	pose.airborne = airborne
	pose.walkPhase = figure.walkPhase
	pose.walkAmp = figure.walkAmp
	pose.armPitch, pose.armYaw, pose.armRoll = figure.armPitch, figure.armYaw, figure.armRoll
	RaiderPose.Rig(figure.look.entry, rig, made, pose, rigOut)
	return lay(figure, root, cues, parts, frames, count)
end

-- A body after a landed hit ends it (the fling, the topple, a vanish): the rest pose, seated as it
-- sat, as a whole under `root`, which carries its facing.
function Figures.QueueRest(
	figure: Figure,
	root: CFrame,
	seat: number,
	cues: Cues.CueSet?,
	parts: { BasePart },
	frames: { CFrame },
	count: number
): number
	local made = consts
	local rig = currentRig()
	if made == nil or rig == nil then
		return count
	end
	local look = figure.look
	local pose = scratchPose
	pose.yaw, pose.lean, pose.leanSide, pose.twist = 0, 0, 0, 0
	pose.squash, pose.thrust, pose.seat, pose.airborne = 1, 0, seat, false
	pose.walkPhase, pose.walkAmp = 0, 0
	pose.armPitch, pose.armYaw, pose.armRoll =
		RaiderPose.Arm(look.entry, look.firstShape, nil, pose, rig, nil)
	RaiderPose.Rig(look.entry, rig, made, pose, rigOut)
	return lay(figure, root, cues, parts, frames, count)
end

local function paintRole(figure: Figure, role: string, rgb: RaiderPose.Rgb, neon: boolean): ()
	local list = figure.roles[role]
	if list == nil or #list == 0 then
		return
	end
	local color = Color3.new(rgb[1], rgb[2], rgb[3])
	if figure.painted[role] == color and figure.neon[role] == neon then
		return
	end
	figure.painted[role] = color
	figure.neon[role] = neon
	local material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for _, part in list do
		part.Color = color
		part.Material = material
	end
end

-- The body's colours: the hit flash, the attack's tint (a share already stepped, its colour and
-- whether the blow glows), the visor's heat (the glow role) and the enraged look. Writes only
-- the roles that changed.
function Figures.Paint(
	figure: Figure,
	flash: boolean,
	tint: number,
	tintColor: Color3,
	glow: boolean,
	visorHot: boolean,
	enraged: boolean
): ()
	local made = consts
	if made == nil then
		return
	end
	local threat = paintThreat
	threat.tint = tint
	local rgb = threat.tintColor
	rgb[1], rgb[2], rgb[3] = tintColor.R, tintColor.G, tintColor.B
	threat.glow = glow
	threat.visorHot = visorHot
	local look = figure.look
	local out = RaiderPose.Paint(look.color, look.skin, threat, flash, enraged, made, paintOut)
	paintRole(figure, "cloth", out.cloth, out.clothNeon)
	paintRole(figure, "clothLeg", out.clothLeg, out.clothLegNeon)
	paintRole(figure, "skin", out.skin, out.skinNeon)
	paintRole(figure, "glow", out.glow, out.glowNeon)
end

-- The plate role (raiders.md section 3), today's shell rule: shown in the plate's colour while
-- plated; white and lit while it turns a hit; a ward (its guard lives) in the ward's colour as a
-- force field, prouder; on the break white and lit, growing about each MeshPart's own centre as
-- the burst plays and fading with it, then gone for good. breakShare = how much of the burst has
-- played (1 = none playing).
function Figures.Plate(
	figure: Figure,
	plated: boolean,
	breakShare: number,
	glint: boolean,
	warded: boolean
): ()
	local plates = figure.plates
	if #plates == 0 then
		return
	end
	local shell = if plated then 0 else math.clamp(breakShare, 0.001, 1)
	if
		shell == figure.plateShell
		and glint == figure.plateGlint
		and warded == figure.plateWarded
	then
		return
	end
	figure.plateShell = shell
	figure.plateGlint = glint
	figure.plateWarded = warded
	local breaking = shell > 0 and shell < 1
	local lit = glint or breaking
	local color = if lit
		then WHITE
		elseif warded then Theme.COMBAT_RANGE_WARD_COLOR
		else Theme.COMBAT_RANGE_PLATE_COLOR
	local material = if lit
		then Enum.Material.Neon
		elseif warded then Enum.Material.ForceField
		else Theme.COMBAT_RAIDER_PLATE_MATERIAL
	local grow = if breaking
		then 1 + Theme.COMBAT_RANGE_CUE_BREAK_GROW * shell
		elseif warded then Theme.COMBAT_RANGE_WARD_SHELL_SCALE
		else 1
	local shown = 1 - (1 - shell) * (1 - figure.fade)
	for slot, part in plates do
		part.Size = figure.plateSizes[slot] * grow
		part.Color = color
		part.Material = material
		part.Transparency = shown
	end
end

-- The body's own fade (a death, a vanish) over every part; the plate keeps its own share under
-- it, and the anchor is never seen.
function Figures.Fade(figure: Figure, fade: number): ()
	if fade == figure.fade then
		return
	end
	figure.fade = fade
	for _, part in figure.shown do
		part.Transparency = fade
	end
	local shown = 1 - (1 - figure.plateShell) * (1 - fade)
	for _, part in figure.plates do
		part.Transparency = shown
	end
end

-- The lit piece Cues hangs on a model kind (RaiderModels.json `cue`), or the empty rig: a model
-- kind with no lit piece (Cues.Attach then gives it nothing at all).
function Figures.CueRig(look: Look): Cues.Rig
	return look.cue or { piece = nil, point = Vector3.zero, size = nil, charged = nil }
end

function Figures.Destroy(): ()
	destroyed = true
	for _, figure in everyFigure do
		figure.model:Destroy()
	end
	table.clear(everyFigure)
	table.clear(pools)
	table.clear(built)
	table.clear(looks)
	table.clear(plain)
	table.clear(posed)
end

return Figures
