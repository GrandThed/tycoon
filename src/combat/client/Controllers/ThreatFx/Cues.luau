--!strict
-- ThreatFx child, drawn by CrowdRenderer: what tells the fighting roles apart at a glance
-- (docs/INTERFACES.md "P4 contracts" -> "Wave 2", "The client"). A kind's colour and size come
-- from its config; on top of that each role gets ONE cheap shape cue, read off what the kind
-- does, not off its name, so a new kind with the same attack is dressed with no code:
--
--   shot (slinger)   an orb held out in the right hand
--   line (marksman)  a long barrel with a lit tip
--   lob  (lobber)    a pack on the back with the next round on top
--   lane (brute)     two horns
--   plate (elite)    a metal shell round the torso, there only while the plate is
--
-- A kind with none of these (fodder, dummies, the boss) gets nothing: no part, no cost.
--
-- The lit pieces are also the shooters' windup tell. A slinger and a lobber put nothing on
-- the ground before they fire, so their body is the tell: the orb or the round swells to a
-- large share of the body's height and reddens as the windup runs, big enough to read across
-- their band. The shell answers the plate: it glints when it turns a hit, and when the plate
-- breaks it bursts outward and is gone, leaving the bare torso.
--
-- At most a few parts per body, pooled, parented into the body's own model so they show and
-- hide with it. Paint writes only what changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Theme = require(script.Parent.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

-- plain = never changes; glow = swells and reddens as a windup charges; shell = the plate.
-- `own` is the piece's transparency before the body's fade is laid over it.
type Piece = {
	part: Part,
	offset: CFrame,
	size: Vector3,
	color: Color3,
	role: "plain" | "glow" | "shell",
	swell: number,
	own: number,
}
-- swollen / charge / shell / glint are what was last painted: the charge the lit pieces were
-- sized for, the step of it they were coloured for, the shell (0 = on, 1 = gone, between =
-- the share of the break burst that has played) and whether it was glinting.
export type CueSet = {
	pieces: { Piece },
	swollen: number,
	charge: number,
	shell: number,
	glint: boolean,
	fade: number,
}

local WHITE = Color3.new(1, 1, 1)
-- How far a lit piece's resting colour is taken from the body's own toward white.
local GLOW_REST_SHARE = 0.45
local DARK_SHARE = 0.55
-- The shell stands a little proud of the torso on every side.
local SHELL_SCALE = Vector3.new(1.22, 1.04, 1.3)

local free: { Part } = {}

local Cues = {}

local function newPart(): Part
	local part = Instance.new("Part")
	part.Name = "Cue"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function add(
	set: CueSet,
	model: Model,
	role: "plain" | "glow" | "shell",
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	swell: number
): ()
	local part: Part = table.remove(free) or newPart()
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = if role == "glow"
		then Enum.Material.Neon
		elseif role == "shell" then Enum.Material.Metal
		else Enum.Material.SmoothPlastic
	part.Transparency = 0
	part.Parent = model
	table.insert(set.pieces, {
		part = part,
		offset = offset,
		size = size,
		color = color,
		role = role,
		swell = swell,
		own = 0,
	})
end

-- The cue pieces for a kind, parented into `model`, or nil when the kind has no cue. The
-- measurements are CrowdRenderer's figure: body radius and height, leg and torso heights, head
-- radius, the torso's size and the kind's colour.
function Cues.Attach(
	model: Model,
	def: Types.CrowdKindDef,
	radius: number,
	height: number,
	legHeight: number,
	torsoHeight: number,
	headRadius: number,
	torsoSize: Vector3,
	color: Color3
): CueSet?
	local attacks = def.attacks
	local first = if attacks ~= nil then attacks[1] else nil
	local shape = if first ~= nil then first.shape else nil
	local plated = (def.plate or 0) > 0
	if
		not plated
		and shape ~= "shot"
		and shape ~= "line"
		and shape ~= "lob"
		and shape ~= "lane"
	then
		return nil
	end
	local set: CueSet = { pieces = {}, swollen = 0, charge = 0, shell = 1, glint = false, fade = 0 }
	local chest = legHeight + torsoHeight * 0.62
	local lit = color:Lerp(WHITE, GLOW_REST_SHARE)
	local dark = color:Lerp(Theme.COMBAT_RANGE_CUE_DARK_COLOR, DARK_SHARE)
	local charged = height * Theme.COMBAT_RANGE_CUE_CHARGE_SHARE
	if shape == "shot" then
		local d = math.max(radius * 0.75, 0.6)
		add(
			set,
			model,
			"glow",
			Enum.PartType.Ball,
			Vector3.one * d,
			CFrame.new(radius * 1.2, chest, -radius * 0.5),
			lit,
			charged / d
		)
	elseif shape == "lob" then
		local depth = radius * 0.8
		add(
			set,
			model,
			"plain",
			Enum.PartType.Block,
			Vector3.new(radius * 1.3, torsoHeight * 0.85, depth),
			CFrame.new(0, legHeight + torsoHeight * 0.55, radius * 0.65 + depth / 2),
			dark,
			1
		)
		local d = math.max(radius * 0.8, 0.7)
		add(
			set,
			model,
			"glow",
			Enum.PartType.Ball,
			Vector3.one * d,
			CFrame.new(0, legHeight + torsoHeight + d * 0.35, radius * 0.65 + depth / 2),
			lit,
			charged / d
		)
	elseif shape == "line" then
		local length = radius * 2.4 + 1
		local side = radius * 0.6
		add(
			set,
			model,
			"plain",
			Enum.PartType.Block,
			Vector3.new(0.32, 0.32, length),
			CFrame.new(side, chest, -(radius * 0.65 + length / 2)),
			Theme.COMBAT_RANGE_CUE_DARK_COLOR,
			1
		)
		local d = 0.55
		add(
			set,
			model,
			"glow",
			Enum.PartType.Ball,
			Vector3.one * d,
			CFrame.new(side, chest, -(radius * 0.65 + length)),
			lit,
			height * Theme.COMBAT_RANGE_CUE_AIM_CHARGE_SHARE / d
		)
	elseif shape == "lane" then
		local horn = Vector3.new(radius * 0.3, radius, radius * 0.3)
		local headY = height - headRadius
		for side = -1, 1, 2 do
			add(
				set,
				model,
				"plain",
				Enum.PartType.Block,
				horn,
				CFrame.new(side * headRadius * 0.85, headY + headRadius * 0.8, -headRadius * 0.25)
					* CFrame.Angles(math.rad(-30), 0, math.rad(-25 * side)),
				Theme.COMBAT_RANGE_CUE_HORN_COLOR,
				1
			)
		end
	end
	if plated then
		add(
			set,
			model,
			"shell",
			Enum.PartType.Block,
			torsoSize * SHELL_SCALE,
			CFrame.new(0, legHeight + torsoHeight / 2, 0),
			Theme.COMBAT_RANGE_PLATE_COLOR,
			1
		)
		-- Painted on by the first Paint, which knows whether the plate is there.
		local piece = set.pieces[#set.pieces]
		piece.own = 1
		piece.part.Transparency = 1
	end
	return set
end

function Cues.Detach(set: CueSet): ()
	for _, piece in set.pieces do
		piece.part.Parent = nil
		table.insert(free, piece.part)
	end
	table.clear(set.pieces)
end

-- Appends every piece's frame under the body's `root` to the caller's move queue; returns
-- the queue's new length.
function Cues.Queue(
	set: CueSet,
	root: CFrame,
	parts: { BasePart },
	frames: { CFrame },
	count: number
): number
	for _, piece in set.pieces do
		count += 1
		parts[count] = piece.part
		frames[count] = root * piece.offset
	end
	return count
end

local function show(piece: Piece, fade: number): ()
	local transparency = 1 - (1 - piece.own) * (1 - fade)
	if math.abs(piece.part.Transparency - transparency) > 0.01 then
		piece.part.Transparency = transparency
	end
end

-- charge: how far a windup has built, 0-1 (the lit pieces swell and redden with it).
-- plated: the plate is on. breakShare: how much of the break burst has played, 0-1, or 1 when
-- none is playing. glint: the plate has just turned a hit.
function Cues.Paint(
	set: CueSet,
	charge: number,
	plated: boolean,
	breakShare: number,
	glint: boolean
): ()
	local steps = Theme.COMBAT_RANGE_TELL_TINT_STEPS
	local raw = math.clamp(charge, 0, 1)
	-- The swell follows the charge closely; the colour moves in a few steps, as the body's
	-- own tint does, so a windup repaints a handful of times.
	local quantised = math.round(raw * steps) / steps
	local resize = math.abs(raw - set.swollen) >= 0.01
	local shell = if plated then 0 else math.clamp(breakShare, 0.001, 1)
	if not resize and quantised == set.charge and shell == set.shell and glint == set.glint then
		return
	end
	for _, piece in set.pieces do
		if piece.role == "glow" then
			if resize then
				piece.part.Size = piece.size * (1 + (piece.swell - 1) * raw)
			end
			if quantised ~= set.charge then
				-- Red by half charge, so the colour says "danger" before the size does.
				piece.part.Color =
					piece.color:Lerp(Theme.COMBAT_RANGE_TELL_COLOR, math.min(quantised * 2, 1))
			end
		elseif piece.role == "shell" and (shell ~= set.shell or glint ~= set.glint) then
			local breaking = shell > 0 and shell < 1
			piece.own = shell
			piece.part.Size = if breaking
				then piece.size * (1 + Theme.COMBAT_RANGE_CUE_BREAK_GROW * shell)
				else piece.size
			-- White and lit while it turns a hit or flies apart; plain metal otherwise.
			local lit = glint or breaking
			piece.part.Color = if lit then WHITE else piece.color
			piece.part.Material = if lit then Enum.Material.Neon else Enum.Material.Metal
			show(piece, set.fade)
		end
	end
	if resize then
		set.swollen = raw
	end
	set.charge = quantised
	set.shell = shell
	set.glint = glint
end

-- The body's own fade (a death, a vanish) laid over every piece.
function Cues.Fade(set: CueSet, fade: number): ()
	if fade == set.fade then
		return
	end
	set.fade = fade
	for _, piece in set.pieces do
		show(piece, fade)
	end
end

function Cues.Destroy(): ()
	for _, part in free do
		part:Destroy()
	end
	table.clear(free)
end

return Cues
