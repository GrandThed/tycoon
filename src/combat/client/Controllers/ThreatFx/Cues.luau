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
--   boss (Stop 2)    shoulders, a crown of three spikes, two spines down the back and a core
--                    in the chest that charges through every windup; enraged, the crown, the
--                    spines and the core are lit for good
--   commander        (Stop 3: a boss with `guarded`) not a giant but a leader: a cloak, a
--                    crest on the helm, and a standard on a pole with a flag in his guard's
--                    colour and an orb on top that charges through every windup, high over
--                    their heads; his shell is a ward while his guard lives
--   his guard        the pennant each of them carries, in the same colour: they are his
--
-- A kind with none of these (fodder, the passive dummies) gets nothing: no part, no cost.
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

-- plain = never changes; ember = never changes and is lit (an enraged boss's crown); glow =
-- swells and reddens as a windup charges; shell = the plate. `own` is the piece's transparency
-- before the body's fade is laid over it.
type Role = "plain" | "ember" | "glow" | "shell"
type Piece = {
	part: Part,
	offset: CFrame,
	size: Vector3,
	color: Color3,
	role: Role,
	swell: number,
	own: number,
}
-- swollen / charge / shell / glint are what was last painted: the charge the lit pieces were
-- sized for, the step of it they were coloured for, the shell (0 = on, 1 = gone, between =
-- the share of the break burst that has played), whether it was glinting and whether it
-- was a ward (its body's guard lives).
export type CueSet = {
	pieces: { Piece },
	swollen: number,
	charge: number,
	shell: number,
	glint: boolean,
	warded: boolean,
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
	role: Role,
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
	part.Material = if role == "glow" or role == "ember"
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
-- radius, the torso's size and the kind's colour. `enraged` = a boss in its second phase;
-- `guards` = the kind is the guard some boss calls up.
function Cues.Attach(
	model: Model,
	def: Types.CrowdKindDef,
	radius: number,
	height: number,
	legHeight: number,
	torsoHeight: number,
	headRadius: number,
	torsoSize: Vector3,
	color: Color3,
	enraged: boolean,
	guards: boolean
): CueSet?
	local attacks = def.attacks
	local first = if attacks ~= nil then attacks[1] else nil
	local shape = if first ~= nil then first.shape else nil
	local plated = (def.plate or 0) > 0
	local boss = def.boss == true
	if
		not plated
		and not boss
		and not guards
		and shape ~= "shot"
		and shape ~= "line"
		and shape ~= "lob"
		and shape ~= "lane"
	then
		return nil
	end
	local set: CueSet = {
		pieces = {},
		swollen = 0,
		charge = 0,
		shell = 1,
		glint = false,
		warded = false,
		fade = 0,
	}
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
	-- Lit in the guard's colour; enraged, in the enrage's.
	local mark = if enraged
		then Theme.COMBAT_RANGE_ENRAGE_GLOW_COLOR
		else Theme.COMBAT_RANGE_WARD_COLOR
	local behind = torsoSize.Z * 0.5
	if guards then
		-- One of a guard: a pennant on its back in the colour of the tether and of the ward
		-- it keeps up, turned a quarter so it shows from the front and from the side.
		local pole = height * 0.55
		local foot = legHeight + torsoHeight * 0.4
		local flag = Vector3.new(radius * 0.9, pole * 0.4, 0.1)
		local out = (flag.X / 2 + 0.1) * math.sqrt(0.5)
		add(
			set,
			model,
			"plain",
			Enum.PartType.Block,
			Vector3.new(0.18, pole, 0.18),
			CFrame.new(0, foot + pole / 2, behind + 0.25),
			Theme.COMBAT_RANGE_CUE_DARK_COLOR,
			1
		)
		add(
			set,
			model,
			"ember",
			Enum.PartType.Block,
			flag,
			CFrame.new(-out, foot + pole - flag.Y / 2, behind + 0.25 + out)
				* CFrame.Angles(0, math.rad(45), 0),
			Theme.COMBAT_RANGE_WARD_COLOR,
			1
		)
	end
	if boss and def.guarded == true then
		-- A commander: the same height band as his guard's elites would be lost among them,
		-- so what marks him stands above them. A cloak down his back, a crest along his helm,
		-- and a standard: a pole half again his height with a flag and, on top, the orb that
		-- charges through every windup (a barrage thrown from across his band is read off
		-- it). Front is -Z.
		local cloak = Vector3.new(torsoSize.X * 0.95, torsoHeight + legHeight * 0.55, 0.25)
		add(
			set,
			model,
			"plain",
			Enum.PartType.Block,
			cloak,
			CFrame.new(0, legHeight * 0.45 + cloak.Y / 2, behind + 0.4)
				* CFrame.Angles(math.rad(8), 0, 0),
			dark,
			1
		)
		add(
			set,
			model,
			"ember",
			Enum.PartType.Block,
			Vector3.new(headRadius * 0.3, headRadius * 0.9, headRadius * 1.9),
			CFrame.new(0, height + headRadius * 0.2, 0),
			mark,
			1
		)
		local pole = height * 0.85
		local foot = legHeight + torsoHeight * 0.35
		local staff = CFrame.new(-torsoSize.X * 0.3, foot, behind + 0.75)
		add(
			set,
			model,
			"plain",
			Enum.PartType.Block,
			Vector3.new(0.3, pole, 0.3),
			staff * CFrame.new(0, pole / 2, 0),
			Theme.COMBAT_RANGE_CUE_DARK_COLOR,
			1
		)
		local flag = Vector3.new(radius * 1.3, pole * 0.32, 0.14)
		local out = (flag.X / 2 + 0.15) * math.sqrt(0.5)
		add(
			set,
			model,
			"ember",
			Enum.PartType.Block,
			flag,
			staff
				* CFrame.new(-out, pole - flag.Y / 2 - 0.2, out)
				* CFrame.Angles(0, math.rad(45), 0),
			mark,
			1
		)
		local d = math.max(radius * 0.4, 0.7)
		add(
			set,
			model,
			"glow",
			Enum.PartType.Ball,
			Vector3.one * d,
			staff * CFrame.new(0, pole + d * 0.4, 0),
			mark:Lerp(WHITE, GLOW_REST_SHARE),
			math.max(height * Theme.COMBAT_RANGE_CUE_COMMANDER_CHARGE_SHARE / d, 1)
		)
	elseif boss then
		-- A silhouette no other body has, in eight parts: wide shoulders, a crown, spines, and
		-- the core that says "something is coming" whatever the attack. Front is -Z.
		local shoulder = Vector3.new(radius * 0.95, torsoHeight * 0.3, radius * 1.5)
		for side = -1, 1, 2 do
			add(
				set,
				model,
				"plain",
				Enum.PartType.Block,
				shoulder,
				CFrame.new(
					side * (torsoSize.X * 0.5 + shoulder.X * 0.2),
					legHeight + torsoHeight * 0.9,
					0
				) * CFrame.Angles(0, 0, math.rad(-14 * side)),
				dark,
				1
			)
		end
		-- Enraged, the crown and the spines are lit and stay lit: the phase reads off the
		-- body from any side, with no bar in view.
		local spikeRole: Role = if enraged then "ember" else "plain"
		local spikeColor = if enraged
			then Theme.COMBAT_RANGE_ENRAGE_GLOW_COLOR
			else Theme.COMBAT_RANGE_CUE_HORN_COLOR
		local spike = Vector3.new(headRadius * 0.34, headRadius * 1.3, headRadius * 0.34)
		for slot = -1, 1 do
			add(
				set,
				model,
				spikeRole,
				Enum.PartType.Block,
				spike,
				CFrame.new(slot * headRadius * 0.6, height - headRadius * 0.05, 0)
					* CFrame.Angles(0, 0, math.rad(-22 * slot)),
				spikeColor,
				1
			)
		end
		local spine = Vector3.new(radius * 0.22, torsoHeight * 0.42, radius * 0.22)
		for slot = 0, 1 do
			add(
				set,
				model,
				spikeRole,
				Enum.PartType.Block,
				spine,
				CFrame.new(
					0,
					legHeight + torsoHeight * (0.45 + 0.38 * slot),
					torsoSize.Z * 0.5 + spine.Z * 0.5
				) * CFrame.Angles(math.rad(40), 0, 0),
				spikeColor,
				1
			)
		end
		local d = math.max(radius * 0.6, 0.8)
			* (if enraged then Theme.COMBAT_RANGE_ENRAGE_CORE_SCALE else 1)
		add(
			set,
			model,
			"glow",
			Enum.PartType.Ball,
			Vector3.one * d,
			CFrame.new(0, chest, -torsoSize.Z * 0.5),
			if enraged then Theme.COMBAT_RANGE_ENRAGE_GLOW_COLOR else lit,
			math.max(height * Theme.COMBAT_RANGE_CUE_BOSS_CHARGE_SHARE / d, 1)
		)
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
-- none is playing. glint: the plate has just turned a hit. warded: the plate cannot be
-- touched because the body's guard lives (the shell is then a ward, not a plate).
function Cues.Paint(
	set: CueSet,
	charge: number,
	plated: boolean,
	breakShare: number,
	glint: boolean,
	warded: boolean
): ()
	local steps = Theme.COMBAT_RANGE_TELL_TINT_STEPS
	local raw = math.clamp(charge, 0, 1)
	-- The swell follows the charge closely; the colour moves in a few steps, as the body's
	-- own tint does, so a windup repaints a handful of times.
	local quantised = math.round(raw * steps) / steps
	local resize = math.abs(raw - set.swollen) >= 0.01
	local shell = if plated then 0 else math.clamp(breakShare, 0.001, 1)
	if
		not resize
		and quantised == set.charge
		and shell == set.shell
		and glint == set.glint
		and warded == set.warded
	then
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
		elseif
			piece.role == "shell"
			and (shell ~= set.shell or glint ~= set.glint or warded ~= set.warded)
		then
			local breaking = shell > 0 and shell < 1
			piece.own = shell
			piece.part.Size = if breaking
				then piece.size * (1 + Theme.COMBAT_RANGE_CUE_BREAK_GROW * shell)
				elseif warded then piece.size * Theme.COMBAT_RANGE_WARD_SHELL_SCALE
				else piece.size
			-- White and lit while it turns a hit or flies apart. While the guard lives it is a
			-- ward: a shimmering field in the guard's colour, prouder of the body, which no
			-- plate looks like. Plain metal otherwise: a plate, to be broken.
			local lit = glint or breaking
			piece.part.Color = if lit
				then WHITE
				elseif warded then Theme.COMBAT_RANGE_WARD_COLOR
				else piece.color
			piece.part.Material = if lit
				then Enum.Material.Neon
				elseif warded then Enum.Material.ForceField
				else Enum.Material.Metal
			show(piece, set.fade)
		end
	end
	if resize then
		set.swollen = raw
	end
	set.charge = quantised
	set.shell = shell
	set.glint = glint
	set.warded = warded
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
