--!strict
-- AbilityFx child: the `impaleDash` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local lowEnd = Shared.lowEnd
local EPSILON = Shared.EPSILON
local UP = Shared.UP
local ABILITY_COLOR = Shared.ABILITY_COLOR
local HOT_WHITE = Shared.HOT_WHITE
local clamp01 = Shared.clamp01
local flatUnit = Shared.flatUnit
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local casterOf = Shared.casterOf
local takeParts = Pool.takeParts
local takeBeam = Pool.takeBeam
local place = Pool.place
local visibleAs = Pool.visibleAs
local showAll = Pool.showAll
local layBeam = Pool.layBeam
local showBeam = Pool.showBeam

type Ghost = { parts: { BasePart }, born: number }

-- Impale Dash: a streak from the cast root to the dash end with the capsule's edges, afterimages.
local DASH_COLOR = ABILITY_COLOR
local DASH_CORE_COLOR = HOT_WHITE
local DASH_TAIL_WIDTH = 0.15
local DASH_HEAD_WIDTH = 1.4
local DASH_TAIL_TRANSPARENCY = 0.8
local DASH_HEAD_TRANSPARENCY = 0
local DASH_EDGE_WIDTH = 0.2
local DASH_EDGE_TRANSPARENCY = 0.35
local DASH_COLLAPSE_SECONDS = 0.2
local DASH_AFTERIMAGES = 4
local DASH_AFTERIMAGES_LOW_END = 2
local DASH_POSE_PARTS = 16
local DASH_AFTERIMAGE_TRANSPARENCY = 0.45
local DASH_AFTERIMAGE_SECONDS = 0.35

-- Impale Dash: over delaySeconds a bright streak shoots from the cast root to the dash end
-- (the head keeps pace with the dash), flanked by two lines at ±width/2, the capsule's exact
-- edges. Afterimages of the caster's pose drop along the line as the head passes them. After
-- the dash the tail catches up and everything fades. Feedback draws the capsule strike itself.
local function buildImpaleDash(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local width = positive(def.width)
	if delay == nil or width == nil then
		return nil, nil
	end
	local from = cast.origin
	local heading = flatUnit(cast.direction) or Vector3.zAxis
	local range = positive(def.range)
	local to = cast.target or (if range ~= nil then from + heading * range else from)
	local line = to - from
	if line.Magnitude < EPSILON then
		return nil, nil
	end
	local side = heading:Cross(UP) * (width / 2)
	local finish = delay + math.max(DASH_COLLAPSE_SECONDS, DASH_AFTERIMAGE_SECONDS)
	local core = takeBeam(kit, DASH_CORE_COLOR, DASH_HEAD_WIDTH)
	core.beam.Width0 = DASH_TAIL_WIDTH
	local edges = {
		takeBeam(kit, DASH_COLOR, DASH_EDGE_WIDTH),
		takeBeam(kit, DASH_COLOR, DASH_EDGE_WIDTH),
	}

	local ghosts: { Ghost } = {}
	local root, _, character = casterOf(cast.userId)
	if root ~= nil and character ~= nil then
		local offsets: { CFrame } = {}
		local sizes: { Vector3 } = {}
		for _, child in character:GetChildren() do
			if child:IsA("BasePart") and child ~= root and #offsets < DASH_POSE_PARTS then
				table.insert(offsets, root.CFrame:ToObjectSpace(child.CFrame))
				table.insert(sizes, child.Size)
			end
		end
		local count = if lowEnd then DASH_AFTERIMAGES_LOW_END else DASH_AFTERIMAGES
		for index = 1, count do
			local share = (index - 0.5) / count
			local point = from + line * share
			local frame = CFrame.lookAt(point, point + heading)
			local parts =
				takeParts(kit, #offsets, Enum.PartType.Block, DASH_COLOR, Enum.Material.Neon)
			for part = 1, #offsets do
				parts[part].Size = sizes[part]
				place(parts[part], frame * offsets[part])
			end
			table.insert(ghosts, { parts = parts, born = share * delay })
		end
	end

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			return false
		end
		local u = if delay > 0 then clamp01(t / delay) else 1
		local collapse = if t <= delay then 0 else clamp01((t - delay) / DASH_COLLAPSE_SECONDS)
		local head = from + line * u
		local tail = from + line * collapse
		local v = 1 - collapse
		layBeam(core, tail, head)
		core.beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, visibleAs(DASH_TAIL_TRANSPARENCY, v)),
			NumberSequenceKeypoint.new(1, visibleAs(DASH_HEAD_TRANSPARENCY, v)),
		})
		for index, edge in edges do
			local offset = if index == 1 then side else -side
			layBeam(edge, tail + offset, head + offset)
			showBeam(edge, DASH_EDGE_TRANSPARENCY, v)
		end
		for _, ghost in ghosts do
			local age = t - ghost.born
			local ghostV = if age < 0 then 0 else 1 - clamp01(age / DASH_AFTERIMAGE_SECONDS)
			showAll(ghost.parts, DASH_AFTERIMAGE_TRANSPARENCY, ghostV)
		end
		return true
	end

	return step, nil
end

return buildImpaleDash
