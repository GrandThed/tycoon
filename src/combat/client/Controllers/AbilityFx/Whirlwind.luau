--!strict
-- AbilityFx child: the `whirlwind` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local Workspace = game:GetService("Workspace")

local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type AbilityStrike = Shared.AbilityStrike
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local lowEnd = Shared.lowEnd
local TAU = Shared.TAU
local UP = Shared.UP
local FLAT_U = Shared.FLAT_U
local FLAT_V = Shared.FLAT_V
local STAND_UP = Shared.STAND_UP
local FLOOR_PROBE_DOWN = Shared.FLOOR_PROBE_DOWN
local LIFT = Shared.LIFT
local MIN_RADIUS = Shared.MIN_RADIUS
local JOINT_OVERLAP = Shared.JOINT_OVERLAP
local RING_WIDTH = Shared.RING_WIDTH
local RING_HEIGHT = Shared.RING_HEIGHT
local RING_TRANSPARENCY = Shared.RING_TRANSPARENCY
local FILL_PULSE_TRANSPARENCY = Shared.FILL_PULSE_TRANSPARENCY
local DISC_THICKNESS = Shared.DISC_THICKNESS
local PULSE_SECONDS = Shared.PULSE_SECONDS
local ABILITY_COLOR = Shared.ABILITY_COLOR
local HOT_WHITE = Shared.HOT_WHITE
local lerp = Shared.lerp
local envelope = Shared.envelope
local around = Shared.around
local tangentOf = Shared.tangentOf
local positive = Shared.positive
local ringSegments = Shared.ringSegments
local casterOf = Shared.casterOf
local floorUnder = Shared.floorUnder
local rootHeightOf = Shared.rootHeightOf
local worldParams = Pool.worldParams
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local place = Pool.place
local show = Pool.show
local showAll = Pool.showAll
local layCircle = Pool.layCircle

type Streak = { part: BasePart, radius: number, angle: number, lift: number, born: number }

-- Whirlwind: three crescent slashes spinning at the reach, the exact ring on the floor, streaks.
local WHIRL_COLOR = HOT_WHITE
local WHIRL_GLOW = ABILITY_COLOR
local WHIRL_BLADES = 3
local WHIRL_BLADE_SEGMENTS = 8
local WHIRL_BLADE_DEGREES = 110
local WHIRL_BLADE_HEAD_WIDTH = 1.3
local WHIRL_BLADE_TAIL_WIDTH = 0.2
local WHIRL_BLADE_HEIGHT = 0.15
local WHIRL_BLADE_HEAD_TRANSPARENCY = 0
local WHIRL_BLADE_TAIL_TRANSPARENCY = 0.85
local WHIRL_SPIN = math.rad(900)
local WHIRL_SPIN_UP_SECONDS = 0.12
local WHIRL_FADE_SECONDS = 0.18
local WHIRL_STREAKS = 8
local WHIRL_STREAK_LENGTH = 2.6
local WHIRL_STREAK_WIDTH = 0.12
local WHIRL_STREAK_SECONDS = 0.3
local WHIRL_STREAK_SPEED = 1.4
local WHIRL_STREAK_MIN_SHARE = 0.35
local WHIRL_STREAK_MAX_SHARE = 0.95
local WHIRL_STREAK_LIFT = 1.2
local WHIRL_STREAK_TRANSPARENCY = 0.2
local WHIRL_FILL_TRANSPARENCY = 0.93

-- Whirlwind: three crescent slashes spin around the caster with their outer edge exactly at
-- `range`, the same ring lies on the floor under them, and streaks whip round inside. Follows
-- the caster every frame for durationSeconds; every tick flashes the floor ring.
local function buildWhirlwind(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local range = positive(def.range)
	local duration = positive(def.durationSeconds)
	if range == nil or duration == nil then
		return nil, nil
	end
	local reach: number = range
	local finish = duration + WHIRL_FADE_SECONDS
	local segmentAngle = math.rad(WHIRL_BLADE_DEGREES) / WHIRL_BLADE_SEGMENTS
	local widths: { number } = {}
	local bases: { number } = {}
	local radii: { number } = {}
	for index = 1, WHIRL_BLADE_SEGMENTS do
		local share = (index - 1) / math.max(WHIRL_BLADE_SEGMENTS - 1, 1)
		local width = math.min(lerp(WHIRL_BLADE_HEAD_WIDTH, WHIRL_BLADE_TAIL_WIDTH, share), reach)
		widths[index] = width
		bases[index] = lerp(WHIRL_BLADE_HEAD_TRANSPARENCY, WHIRL_BLADE_TAIL_TRANSPARENCY, share)
		-- The blade's outer edge is the reach: the slash ends exactly where the hit does.
		radii[index] = math.max(reach - width / 2, MIN_RADIUS)
	end
	local blades: { { BasePart } } = {}
	for _ = 1, WHIRL_BLADES do
		local parts = takeParts(
			kit,
			WHIRL_BLADE_SEGMENTS,
			Enum.PartType.Block,
			WHIRL_COLOR,
			Enum.Material.Neon
		)
		for index, part in parts do
			local chord = 2 * radii[index] * math.sin(segmentAngle / 2)
			part.Size = Vector3.new(
				widths[index],
				WHIRL_BLADE_HEIGHT,
				chord + widths[index] * JOINT_OVERLAP
			)
		end
		table.insert(blades, parts)
	end
	local ground =
		takeParts(kit, ringSegments(), Enum.PartType.Block, WHIRL_GLOW, Enum.Material.Neon)
	local rng = Random.new(cast.seq)
	local function respawn(streak: Streak, t: number): ()
		streak.born = t
		streak.radius = reach * rng:NextNumber(WHIRL_STREAK_MIN_SHARE, WHIRL_STREAK_MAX_SHARE)
		streak.angle = rng:NextNumber(0, TAU)
		streak.lift = rng:NextNumber(-WHIRL_STREAK_LIFT, WHIRL_STREAK_LIFT)
	end
	local fill: BasePart? = nil
	local streaks: { Streak } = {}
	if not lowEnd then
		local disc = takePart(kit, Enum.PartType.Cylinder, WHIRL_GLOW, Enum.Material.Neon)
		disc.Size = Vector3.new(DISC_THICKNESS, reach * 2, reach * 2)
		fill = disc
		for _ = 1, WHIRL_STREAKS do
			local part = takePart(kit, Enum.PartType.Block, WHIRL_COLOR, Enum.Material.Neon)
			part.Size = Vector3.new(WHIRL_STREAK_WIDTH, WHIRL_STREAK_WIDTH, WHIRL_STREAK_LENGTH)
			local streak: Streak = { part = part, radius = 0, angle = 0, lift = 0, born = 0 }
			-- Staggered births, so the streaks never all respawn on one frame.
			respawn(streak, -rng:NextNumber(0, WHIRL_STREAK_SECONDS))
			table.insert(streaks, streak)
		end
	end
	local centre = cast.origin
	local floorY = cast.origin.Y - rootHeightOf(cast.userId)
	local pulse = 0
	local sized = false
	-- Built once and rebuilt only when the caster respawns: the probe starts inside the caster,
	-- so their current character must always be excluded.
	local probe = worldParams()
	local _, _, probedCharacter = casterOf(cast.userId)

	local function step(t: number, dt: number): boolean
		if t >= finish then
			return false
		end
		local root, humanoid, character = casterOf(cast.userId)
		if root ~= nil then
			centre = root.Position
			if character ~= probedCharacter then
				probe = worldParams()
				probedCharacter = character
			end
			-- The ring stays on the real floor when the caster jumps mid-channel (ruling 3);
			-- the hip estimate is only the fallback over a void.
			local hit = Workspace:Raycast(centre, Vector3.new(0, -FLOOR_PROBE_DOWN, 0), probe)
			floorY = if hit ~= nil then hit.Position.Y else floorUnder(root, humanoid)
		end
		pulse = math.max(pulse - dt / PULSE_SECONDS, 0)
		local v = envelope(t, 0, finish, WHIRL_SPIN_UP_SECONDS, WHIRL_FADE_SECONDS)
		local floorCentre = Vector3.new(centre.X, floorY + LIFT, centre.Z)
		layCircle(
			ground,
			floorCentre,
			FLAT_U,
			FLAT_V,
			reach,
			0,
			TAU,
			RING_WIDTH,
			RING_HEIGHT,
			not sized
		)
		sized = true
		showAll(ground, RING_TRANSPARENCY * (1 - pulse), v)
		local spin = t * WHIRL_SPIN
		for bladeIndex, parts in blades do
			local head = spin + TAU * (bladeIndex - 1) / #blades
			for index, part in parts do
				local angle = head - segmentAngle * (index - 1)
				local a = centre + around(angle) * radii[index]
				local b = centre + around(angle - segmentAngle) * radii[index]
				place(part, CFrame.lookAt((a + b) / 2, b))
				show(part, bases[index], v)
			end
		end
		for _, streak in streaks do
			local age = t - streak.born
			if age >= WHIRL_STREAK_SECONDS then
				respawn(streak, t)
				age = 0
			end
			local angle = streak.angle + age * WHIRL_SPIN * WHIRL_STREAK_SPEED
			local point = centre + around(angle) * streak.radius + UP * streak.lift
			place(streak.part, CFrame.lookAt(point, point + tangentOf(angle)))
			local life = math.sin(math.pi * age / WHIRL_STREAK_SECONDS)
			show(streak.part, WHIRL_STREAK_TRANSPARENCY, v * life)
		end
		local disc = fill
		if disc ~= nil then
			place(disc, CFrame.new(centre) * STAND_UP)
			show(disc, lerp(WHIRL_FILL_TRANSPARENCY, FILL_PULSE_TRANSPARENCY, pulse), v)
		end
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if not strike.tick then
			return false
		end
		pulse = 1
		return true
	end

	return step, onStrike
end

return buildWhirlwind
