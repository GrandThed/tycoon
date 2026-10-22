--!strict
-- How a raider is posed (docs/prompts/l4-w2-contract.md, section 3.3; L4W2-9). Pure: no `game`,
-- no Roblox type, no require. Constants and the kind's entry come in as tables and every
-- transform goes out as 12 numbers in CFrame.new order (x, y, z, R00, R01, R02, R10, ... R22), so
-- tools/check_raider_mirror.py runs this very file under luau.exe against
-- tools/testfit/raiderpose.py on the same inputs, every number within 1e-6.
--
-- Five functions, each the port of one raiderpose.py function (the names in brackets):
--   Threat  [threat_pose]  CrowdRenderer's pose of an attack phase (lean, thrust, twist, squash,
--                          the tint and the lit cue's charge) plus the clocks the arm reads.
--                          CrowdRenderer keeps the phase clock, setTint and the ground tell; the
--                          placeholder figure and the models draw from these same numbers.
--   Rig     [rig]          the five rigid pieces of a model body for one pose: the head stays on
--                          the scored head (moving only up and down by the clamped drop), every
--                          lean bends the body below the neck, the legs aim back at the floor.
--   Arm     [arm_channel]  the weapon arm's pitch, yaw and roll: keyed poses blended the short way
--                          round on Threat's clocks, the throw path, the whirl, the steady aim.
--   Walk    [walk_step]    one frame of the walk cycle (phase and amplitude). raiderpose.py's
--                          mirror of it is D2's (the formula is written out at Walk below).
--   Paint   [paint]        each painted role's colour and whether it is Neon.
--
-- Frames: the glTF / Roblox body frame, feet at the origin, front -Z, up +Y, right +X; a body
-- turned by `yaw` faces lookOf(yaw) = (-sin yaw, 0, -cos yaw). Colours are { r, g, b } in 0-1.
-- Allocation: every function writes into an `out` table it is given (or makes one when given
-- nil), so a frame of a whole crowd allocates nothing here.

export type Rgb = { number }

-- Theme.luau's and CrowdRenderer.luau's numbers by their Luau names (the names raiderpose.py
-- reads), colours as { r, g, b }; restDrop is ProvingGrounds.json crowd.restDrop.
export type Consts = {
	COMBAT_RANGE_TELL_COLOR: Rgb,
	COMBAT_RANGE_TELL_SPENT_COLOR: Rgb,
	COMBAT_RANGE_TELL_HEAT_SHARE: number,
	COMBAT_RANGE_TELL_SPENT_SHARE: number,
	COMBAT_RANGE_TELL_TINT_STEPS: number,
	COMBAT_RANGE_TELL_COIL_SHARE: number,
	COMBAT_RANGE_TELL_LEAN_BACK: number,
	COMBAT_RANGE_TELL_LEAN_FORWARD: number,
	COMBAT_RANGE_TELL_PULL_BACK: number,
	COMBAT_RANGE_TELL_ARC_TWIST_SHARE: number,
	COMBAT_RANGE_TELL_ARC_SWEEP_SHARE: number,
	COMBAT_RANGE_TELL_SPENT_LEAN: number,
	COMBAT_RANGE_TELL_SPENT_SQUASH: number,
	COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS: number,
	COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS: number,
	COMBAT_RANGE_RING_SLAM_RISE: number,
	COMBAT_RANGE_RING_SLAM_SQUASH: number,
	COMBAT_RANGE_RING_SLAM_LEAN: number,
	COMBAT_RANGE_CALL_LEAN: number,
	COMBAT_RANGE_CALL_SHAKE: number,
	COMBAT_RANGE_CALL_SHAKE_HZ: number,
	COMBAT_RANGE_CALL_STRETCH: number,
	COMBAT_RANGE_ENRAGE_COLOR: Rgb,
	COMBAT_RANGE_ENRAGE_SHARE: number,
	COMBAT_RANGE_ENRAGE_GLOW_COLOR: Rgb,
	COMBAT_RAIDER_WALK_EASE_RATE: number,
	COMBAT_RAIDER_WALK_SETTLE: number,
	LEG_SHADE: Rgb,
	LEG_SHADE_SHARE: number,
	VISOR_COLOR: Rgb,
	VISOR_HOT_COLOR: Rgb,
	FLASH_COLOR: Rgb,
	restDrop: number,
}

-- RaiderModels.json `rig`: every key raiderpose.py's RIG_DEFAULTS names. The client counts a
-- config only when all of them are numbers (Figures), so nothing here falls back to a default.
export type RigNumbers = {
	headKeep: number,
	headNod: number,
	headTurn: number,
	legSwing: number,
	armSwing: number,
	walkLean: number,
	strideLegs: number,
	walkFullShare: number,
	walkNearStuds: number,
	stepShare: number,
	seatLean: number,
	seatSplay: number,
	airTuck: number,
	throwShare: number,
}

export type ArmShape = {
	coil: { number }?,
	strike: { number }?,
	follow: { number }?,
	whirl: { turns: number, sin: { number }, cos: { number } }?,
	steady: boolean?,
}

export type ArmKeys = {
	carry: { number },
	seat: { number },
	slump: { number },
	shapes: { [string]: ArmShape },
}

-- What the rig and the arm read of one RaiderModels.json kind entry. `points` holds at least
-- head, neck, hipL, hipR and shoulder (Figures checks them).
export type Model = {
	height: number,
	headRadius: number,
	legLength: number,
	leadLeg: string?,
	armSwingShare: number?,
	points: { [string]: { number } },
	arm: ArmKeys,
}

-- raiderpose.py's Pose. lean = along the facing (+ forward), leanSide = across it (+ toward the
-- body's right); seat = 0-1 before the ease; the arm is Arm's three angles.
export type Pose = {
	yaw: number,
	lean: number,
	leanSide: number,
	twist: number,
	squash: number,
	thrust: number,
	seat: number,
	airborne: boolean,
	walkPhase: number,
	walkAmp: number,
	armPitch: number,
	armYaw: number,
	armRoll: number,
}

-- One attack phase as CrowdRenderer draws it (its loadThreat numbers): reach = threatReach (the
-- lunge's jab, an arc's radius, a lane's or a line's length, a ring's or a call's radius), arc in
-- radians, lock = a line's lockSeconds. serverNow drives the call's shake; stride = how much of
-- the slump walking has lifted; unwind = how far an arc's body was turned at the blow's end;
-- held = an enraged boss's chained recover (interval + lag).
export type ThreatIn = {
	shape: string,
	phase: string,
	age: number,
	windup: number,
	strike: number,
	recover: number,
	reach: number,
	arc: number,
	lock: number,
	radius: number,
	serverNow: number,
	stride: number,
	unwind: number,
	held: number,
}

-- raiderpose.py's Threat. tint is already stepped; tintColor is one of the consts' colours (or
-- white); phase is "none" once a recover's clock has run out.
export type ThreatOut = {
	phase: string,
	age: number,
	lean: number,
	thrust: number,
	twist: number,
	squash: number,
	tint: number,
	tintColor: Rgb,
	glow: boolean,
	visorHot: boolean,
	charge: number,
	build: number,
	snap: number,
	u: number,
	sweep: number,
	settle: number,
	spent: number,
	slump: number,
}

-- Rig's answer: each piece's transform (body frame to world, 12 numbers), the scored head's
-- centre height (anchorY; its x and z are 0), where the head is drawn, how far it is from the
-- anchor, the clamped drop and how far each foot floats.
export type RigOut = {
	head: { number },
	torso: { number },
	arm: { number },
	legL: { number },
	legR: { number },
	anchorY: number,
	headX: number,
	headY: number,
	headZ: number,
	headOffset: number,
	drop: number,
	footL: number,
	footR: number,
}

-- Paint's answer: per role its colour and whether it is Neon (else SmoothPlastic).
export type PaintOut = {
	cloth: Rgb,
	clothNeon: boolean,
	clothLeg: Rgb,
	clothLegNeon: boolean,
	skin: Rgb,
	skinNeon: boolean,
	glow: Rgb,
	glowNeon: boolean,
}

-- What Paint reads of a frame's threat (a ThreatOut has all four; CrowdRenderer hands its
-- entity's own).
export type PaintThreat = {
	tint: number,
	tintColor: Rgb,
	glow: boolean,
	visorHot: boolean,
}

local TWO_PI = 2 * math.pi
local HALF_PI = math.pi / 2
local WHITE: Rgb = { 1, 1, 1 }
-- Shapes whose windup ends in a snap to the strike key (raiderpose.py SNAP_SHAPES), and those
-- that leave the hand during the strike (THROW_SHAPES).
local SNAP_SHAPES: { [string]: boolean } = { lunge = true, ring = true }
local THROW_SHAPES: { [string]: boolean } = { shot = true, lob = true, line = true }

local RaiderPose = {}

-- --- small maths: rotations as 9 numbers, row-major ------------------------------------------

local function clamp(x: number, lo: number, hi: number): number
	return math.min(math.max(x, lo), hi)
end

local function smoothstep(u: number): number
	return u * u * (3 - 2 * u)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Luau's math.round is half away from zero, which raiderpose.py's luau_round copies.
local function stepped(consts: Consts, share: number): number
	local steps = consts.COMBAT_RANGE_TELL_TINT_STEPS
	return math.round(clamp(share, 0, 1) * steps) / steps
end

local function rotX(
	a: number
): (number, number, number, number, number, number, number, number, number)
	local c, s = math.cos(a), math.sin(a)
	return 1, 0, 0, 0, c, -s, 0, s, c
end

local function rotY(
	a: number
): (number, number, number, number, number, number, number, number, number)
	local c, s = math.cos(a), math.sin(a)
	return c, 0, s, 0, 1, 0, -s, 0, c
end

local function rotZ(
	a: number
): (number, number, number, number, number, number, number, number, number)
	local c, s = math.cos(a), math.sin(a)
	return c, -s, 0, s, c, 0, 0, 0, 1
end

-- a * b for two rotations.
local function mul(
	a00: number,
	a01: number,
	a02: number,
	a10: number,
	a11: number,
	a12: number,
	a20: number,
	a21: number,
	a22: number,
	b00: number,
	b01: number,
	b02: number,
	b10: number,
	b11: number,
	b12: number,
	b20: number,
	b21: number,
	b22: number
): (number, number, number, number, number, number, number, number, number)
	return a00 * b00 + a01 * b10 + a02 * b20,
		a00 * b01 + a01 * b11 + a02 * b21,
		a00 * b02 + a01 * b12 + a02 * b22,
		a10 * b00 + a11 * b10 + a12 * b20,
		a10 * b01 + a11 * b11 + a12 * b21,
		a10 * b02 + a11 * b12 + a12 * b22,
		a20 * b00 + a21 * b10 + a22 * b20,
		a20 * b01 + a21 * b11 + a22 * b21,
		a20 * b02 + a21 * b12 + a22 * b22
end

-- CFrame.fromEulerAnglesYXZ(pitch, yaw, roll) = Ry(yaw) * Rx(pitch) * Rz(roll).
local function eulerYXZ(
	pitch: number,
	yaw: number,
	roll: number
): (number, number, number, number, number, number, number, number, number)
	local y00, y01, y02, y10, y11, y12, y20, y21, y22 = rotY(yaw)
	local x00, x01, x02, x10, x11, x12, x20, x21, x22 = rotX(pitch)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = mul(
		y00,
		y01,
		y02,
		y10,
		y11,
		y12,
		y20,
		y21,
		y22,
		x00,
		x01,
		x02,
		x10,
		x11,
		x12,
		x20,
		x21,
		x22
	)
	local z00, z01, z02, z10, z11, z12, z20, z21, z22 = rotZ(roll)
	return mul(
		m00,
		m01,
		m02,
		m10,
		m11,
		m12,
		m20,
		m21,
		m22,
		z00,
		z01,
		z02,
		z10,
		z11,
		z12,
		z20,
		z21,
		z22
	)
end

-- CFrame.fromAxisAngle (Rodrigues, right-handed); the axis must be a unit vector.
local function axisAngle(
	x: number,
	y: number,
	z: number,
	angle: number
): (number, number, number, number, number, number, number, number, number)
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	return t * x * x + c,
		t * x * y - s * z,
		t * x * z + s * y,
		t * x * y + s * z,
		t * y * y + c,
		t * y * z - s * x,
		t * x * z - s * y,
		t * y * z + s * x,
		t * z * z + c
end

-- rootFrame's lean: up x lean tips the top of the body toward the lean by |lean| radians.
local function leanRotation(
	lx: number,
	ly: number,
	lz: number
): (
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number
)
	local angle = math.sqrt(lx * lx + ly * ly + lz * lz)
	if angle <= 1e-4 then
		return 1, 0, 0, 0, 1, 0, 0, 0, 1
	end
	-- up x lean = (lz, 0, -lx), scaled by 1 / angle as raiderpose.py's v_mul does.
	local inverse = 1 / angle
	local ax, ay, az = lz * inverse, 0 * inverse, -lx * inverse
	local n = math.sqrt(ax * ax + ay * ay + az * az)
	if n <= 1e-9 then
		return 1, 0, 0, 0, 1, 0, 0, 0, 1
	end
	local unit = 1 / n
	return axisAngle(ax * unit, ay * unit, az * unit, angle)
end

local function write(
	into: { number },
	px: number,
	py: number,
	pz: number,
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number
): ()
	into[1], into[2], into[3] = px, py, pz
	into[4], into[5], into[6] = r00, r01, r02
	into[7], into[8], into[9] = r10, r11, r12
	into[10], into[11], into[12] = r20, r21, r22
end

-- cf_at(at) * R * cf_at(-pivot): the piece turned by R about `pivot`, which lands on `at`.
local function place(
	into: { number },
	atX: number,
	atY: number,
	atZ: number,
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number,
	pivot: { number }
): ()
	local px, py, pz = -pivot[1], -pivot[2], -pivot[3]
	write(
		into,
		r00 * px + r01 * py + r02 * pz + atX,
		r10 * px + r11 * py + r12 * pz + atY,
		r20 * px + r21 * py + r22 * pz + atZ,
		r00,
		r01,
		r02,
		r10,
		r11,
		r12,
		r20,
		r21,
		r22
	)
end

-- a_lerp: one angle blended the shortest way round (its difference wrapped into [-pi, pi) first).
local function angleLerp(a: number, b: number, t: number): number
	return a + ((b - a + math.pi) % TWO_PI - math.pi) * t
end

local function armLerp(
	a1: number,
	a2: number,
	a3: number,
	b: { number },
	t: number
): (number, number, number)
	return angleLerp(a1, b[1], t), angleLerp(a2, b[2], t), angleLerp(a3, b[3], t)
end

-- --- constructors (the mirror and the client each keep one of each and reuse it) ---------------

function RaiderPose.NewThreatOut(): ThreatOut
	return {
		phase = "none",
		age = 0,
		lean = 0,
		thrust = 0,
		twist = 0,
		squash = 1,
		tint = 0,
		tintColor = WHITE,
		glow = false,
		visorHot = false,
		charge = 0,
		build = 0,
		snap = 0,
		u = 0,
		sweep = 0,
		settle = 0,
		spent = 0,
		slump = 0,
	}
end

function RaiderPose.NewRigOut(): RigOut
	return {
		head = table.create(12, 0),
		torso = table.create(12, 0),
		arm = table.create(12, 0),
		legL = table.create(12, 0),
		legR = table.create(12, 0),
		anchorY = 0,
		headX = 0,
		headY = 0,
		headZ = 0,
		headOffset = 0,
		drop = 0,
		footL = 0,
		footR = 0,
	}
end

function RaiderPose.NewPaintOut(): PaintOut
	return {
		cloth = { 1, 1, 1 },
		clothNeon = false,
		clothLeg = { 1, 1, 1 },
		clothLegNeon = false,
		skin = { 1, 1, 1 },
		skinNeon = false,
		glow = { 1, 1, 1 },
		glowNeon = false,
	}
end

function RaiderPose.NewPose(): Pose
	return {
		yaw = 0,
		lean = 0,
		leanSide = 0,
		twist = 0,
		squash = 1,
		thrust = 0,
		seat = 0,
		airborne = false,
		walkPhase = 0,
		walkAmp = 0,
		armPitch = 0,
		armYaw = 0,
		armRoll = 0,
	}
end

-- --- Threat [threat_pose] -----------------------------------------------------------------------

-- The pose of one attack phase `input.age` seconds into it. A recover whose clock has run out
-- answers phase "none" and the rest pose (the caller then ends the attack).
function RaiderPose.Threat(input: ThreatIn, consts: Consts, out: ThreatOut?): ThreatOut
	local o = out or RaiderPose.NewThreatOut()
	local c = consts
	local phase = input.phase
	local age = input.age
	o.phase, o.age = phase, age
	o.lean, o.thrust, o.twist, o.squash = 0, 0, 0, 1
	o.tint, o.tintColor, o.glow, o.visorHot, o.charge = 0, WHITE, false, false, 0
	o.build, o.snap, o.u, o.sweep, o.settle, o.spent, o.slump = 0, 0, 0, 0, 0, 0, 0
	local twistMost = input.arc * 0.5 * c.COMBAT_RANGE_TELL_ARC_TWIST_SHARE
	local shape = input.shape
	if phase == "windup" then
		local u = if input.windup > 0 then math.min(age / input.windup, 1) else 1
		local coil = c.COMBAT_RANGE_TELL_COIL_SHARE
		-- Squared: a slow start and an unmistakable end, so the pose reads as building.
		local build = math.min(u / coil, 1) ^ 2
		o.u, o.build = u, build
		-- A shooter's lit piece swells straight on the windup, so it is largest at the shot.
		o.charge = u * u
		o.tint = stepped(c, build * c.COMBAT_RANGE_TELL_HEAT_SHARE)
		o.tintColor = c.COMBAT_RANGE_TELL_COLOR
		o.visorHot = true
		local back = -c.COMBAT_RANGE_TELL_LEAN_BACK * build
		if shape == "lunge" then
			local pull = -input.radius * c.COMBAT_RANGE_TELL_PULL_BACK * build
			if u <= coil then
				o.lean, o.thrust = back, pull
				return o
			end
			-- The last of the windup is the thrust leaving: fully out exactly at the impact.
			local snap = ((u - coil) / (1 - coil)) ^ 2
			o.snap = snap
			o.lean = back + (c.COMBAT_RANGE_TELL_LEAN_FORWARD - back) * snap
			o.thrust = pull + (input.reach - pull) * snap
			return o
		elseif shape == "ring" then
			-- The slam: up on its toes through the coil, then flat on the floor at the impact.
			local rise = 1 + c.COMBAT_RANGE_RING_SLAM_RISE * build
			if u <= coil then
				o.lean, o.squash = back, rise
				return o
			end
			local snap = ((u - coil) / (1 - coil)) ^ 2
			o.snap = snap
			o.lean = back + (c.COMBAT_RANGE_RING_SLAM_LEAN - back) * snap
			o.squash = rise + (c.COMBAT_RANGE_RING_SLAM_SQUASH - rise) * snap
			return o
		elseif shape == "summon" then
			-- The call: head thrown back, the body shaking harder as it builds.
			o.lean = -c.COMBAT_RANGE_CALL_LEAN * build
			o.twist = c.COMBAT_RANGE_CALL_SHAKE
				* build
				* math.sin(input.serverNow * 2 * math.pi * c.COMBAT_RANGE_CALL_SHAKE_HZ)
			o.squash = 1 + c.COMBAT_RANGE_CALL_STRETCH * build
			return o
		end
		o.lean, o.twist = back, -twistMost * build
		return o
	elseif phase == "attack" then
		local u = if input.strike > 0 then math.min(age / input.strike, 1) else 1
		local left = 1 - u
		o.u = u
		o.tint, o.tintColor, o.glow = 1, c.COMBAT_RANGE_TELL_COLOR, true
		o.visorHot = true
		local forward = c.COMBAT_RANGE_TELL_LEAN_FORWARD * left
		if shape == "lunge" then
			o.lean, o.thrust = forward, input.reach * left * left
			return o
		elseif shape == "lane" then
			-- Head down for the whole charge; the run itself is CrowdRenderer's stepRush.
			o.lean = c.COMBAT_RANGE_TELL_LEAN_FORWARD
			return o
		elseif shape == "ring" then
			o.lean = c.COMBAT_RANGE_RING_SLAM_LEAN * left
			o.squash = 1 - (1 - c.COMBAT_RANGE_RING_SLAM_SQUASH) * left
			return o
		end
		local sweep = smoothstep(math.min(u / c.COMBAT_RANGE_TELL_ARC_SWEEP_SHARE, 1))
		o.sweep = sweep
		o.lean, o.twist = forward, twistMost * (2 * sweep - 1)
		return o
	elseif phase == "recover" then
		if age >= input.recover then
			o.phase = "none"
			return o
		end
		-- Spent: slumped and dull, settling in fast and waking as the opening closes.
		local settle =
			math.min(math.max(age - input.held, 0) / c.COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS, 1)
		local wake = math.min((input.recover - age) / c.COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS, 1)
		local spent = math.min(settle, wake)
		o.settle, o.spent = settle, spent
		o.tint = stepped(c, spent * c.COMBAT_RANGE_TELL_SPENT_SHARE)
		o.tintColor = c.COMBAT_RANGE_TELL_SPENT_COLOR
		o.twist = if shape == "arc" then input.unwind * (1 - settle) else 0
		local slump = spent * (1 - input.stride)
		o.slump = slump
		o.lean = c.COMBAT_RANGE_TELL_SPENT_LEAN * slump
		o.squash = 1 - (1 - c.COMBAT_RANGE_TELL_SPENT_SQUASH) * slump
		return o
	end
	return o
end

-- --- Rig [rig] ------------------------------------------------------------------------------------

-- One leg: hangs from its hip (carried by the torso) and is aimed back at the floor spot under
-- the rest hip, plus the walk swing; a foot that cannot reach slides toward the spot under the
-- hip; seated it lies forward. Writes `into` and answers how far the foot floats.
local function placeLeg(
	into: { number },
	torso: { number },
	hip: { number },
	sign: number,
	step: number,
	model: Model,
	rig: RigNumbers,
	pose: Pose,
	swing: number,
	seat: number
): number
	local legLength = model.legLength
	local hx, hy, hz = hip[1], hip[2], hip[3]
	-- hip_world = torso.point(hip)
	local wx = torso[4] * hx + torso[5] * hy + torso[6] * hz + torso[1]
	local wy = torso[7] * hx + torso[8] * hy + torso[9] * hz + torso[2]
	local wz = torso[10] * hx + torso[11] * hy + torso[12] * hz + torso[3]
	-- The hip in the legs' own frame: ry(yaw) inverse (its transpose) on hip_world.
	local f00, f01, f02, f10, f11, f12, f20, f21, f22 = rotY(pose.yaw)
	local lx = f00 * wx + f10 * wy + f20 * wz
	local ly = f01 * wx + f11 * wy + f21 * wz
	local lz = f02 * wx + f12 * wy + f22 * wz
	local tx, tz = hx, hz - step
	local fx, fz = tx - lx, tz - lz
	local span = math.sqrt(fx * fx + fz * fz)
	local reach = math.sqrt(math.max(legLength * legLength - ly * ly, 0))
	if span > reach and span > 1e-9 then
		tx, tz = lx + fx * reach / span, lz + fz * reach / span
	end
	local vx, vy, vz = tx - lx, 0 - ly, tz - lz
	local n = math.sqrt(vx * vx + vy * vy + vz * vz)
	local ux, uz = 0, 0
	if n > 1e-9 then
		ux, uz = vx / n, vz / n
	end
	local gamma = math.asin(clamp(ux, -1, 1))
	local cg = math.cos(gamma)
	local beta = if cg > 1e-6 then math.asin(clamp(-uz / cg, -1, 1)) else 0
	beta += sign * swing
	if pose.airborne then
		beta += rig.airTuck
	end
	local float = math.max(ly - legLength * math.cos(gamma) * math.cos(beta), 0)
	if seat > 0 then
		beta = lerp(beta, HALF_PI, seat)
		gamma = lerp(gamma, -sign * rig.seatSplay, seat)
	end
	local e00, e01, e02, e10, e11, e12, e20, e21, e22 = eulerYXZ(beta, 0, gamma)
	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = mul(
		f00,
		f01,
		f02,
		f10,
		f11,
		f12,
		f20,
		f21,
		f22,
		e00,
		e01,
		e02,
		e10,
		e11,
		e12,
		e20,
		e21,
		e22
	)
	place(into, wx, wy, wz, r00, r01, r02, r10, r11, r12, r20, r21, r22, hip)
	return float
end

-- The torso turns about the neck joint (the hips swing the other way), the arm about the
-- shoulder it carries.
local function placeUpper(
	out: RigOut,
	model: Model,
	pose: Pose,
	lx: number,
	lz: number,
	lift: number
): ()
	local neck = model.points.neck
	local shoulder = model.points.shoulder
	local upperYaw = pose.yaw + pose.twist
	local u00, u01, u02, u10, u11, u12, u20, u21, u22 = rotY(upperYaw)
	-- neck_world = ry(upper_yaw).rotate((neck.x, 0, neck.z)) + (0, neck.y - seat drop - drop, 0)
	local nx = u00 * neck[1] + u02 * neck[3]
	local ny = u10 * neck[1] + u12 * neck[3] + (neck[2] - lift)
	local nz = u20 * neck[1] + u22 * neck[3]
	local l00, l01, l02, l10, l11, l12, l20, l21, l22 = leanRotation(lx, 0, lz)
	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = mul(
		l00,
		l01,
		l02,
		l10,
		l11,
		l12,
		l20,
		l21,
		l22,
		u00,
		u01,
		u02,
		u10,
		u11,
		u12,
		u20,
		u21,
		u22
	)
	local torso = out.torso
	place(torso, nx, ny, nz, r00, r01, r02, r10, r11, r12, r20, r21, r22, neck)
	-- arm = torso * cf_at(shoulder) * euler(arm) * cf_at(-shoulder)
	local e00, e01, e02, e10, e11, e12, e20, e21, e22 =
		eulerYXZ(pose.armPitch, pose.armYaw, pose.armRoll)
	local sx, sy, sz = shoulder[1], shoulder[2], shoulder[3]
	local ox = sx - (e00 * sx + e01 * sy + e02 * sz)
	local oy = sy - (e10 * sx + e11 * sy + e12 * sz)
	local oz = sz - (e20 * sx + e21 * sy + e22 * sz)
	local a00, a01, a02, a10, a11, a12, a20, a21, a22 = mul(
		r00,
		r01,
		r02,
		r10,
		r11,
		r12,
		r20,
		r21,
		r22,
		e00,
		e01,
		e02,
		e10,
		e11,
		e12,
		e20,
		e21,
		e22
	)
	write(
		out.arm,
		r00 * ox + r01 * oy + r02 * oz + torso[1],
		r10 * ox + r11 * oy + r12 * oz + torso[2],
		r20 * ox + r21 * oy + r22 * oz + torso[3],
		a00,
		a01,
		a02,
		a10,
		a11,
		a12,
		a20,
		a21,
		a22
	)
end

-- The five pieces for one pose, in the body frame turned by pose.yaw (feet at the origin). The
-- head rule: the head sits on the scored head (HitShapes: feet + height - headRadius, lowered by
-- the seat as the server lowers it) and moves from it only vertically, by the drop the lean,
-- squash and walk ask for, clamped to headKeep head radii; it nods and turns about its own centre.
function RaiderPose.Rig(
	model: Model,
	rig: RigNumbers,
	consts: Consts,
	pose: Pose,
	out: RigOut?
): RigOut
	local o = out or RaiderPose.NewRigOut()
	local points = model.points
	local headC = points.head
	local hipL, hipR = points.hipL, points.hipR
	local legLength = model.legLength
	local torsoLength = points.neck[2] - (hipL[2] + hipR[2]) / 2

	local seat = smoothstep(clamp(pose.seat, 0, 1))
	local seatDrop = model.height * consts.restDrop * seat
	local walk = pose.walkAmp
	local swing = rig.legSwing * walk * math.sin(pose.walkPhase)
	local yaw = pose.yaw
	-- facing = (-sin yaw, 0, -cos yaw); side = the body's right, (cos yaw, 0, -sin yaw).
	local sinYaw, cosYaw = math.sin(yaw), math.cos(yaw)
	local leanF = pose.lean + rig.walkLean * walk + rig.seatLean * seat
	local lx = -sinYaw * leanF + cosYaw * pose.leanSide
	local lz = -cosYaw * leanF + -sinYaw * pose.leanSide
	local theta = math.sqrt(lx * lx + lz * lz)

	-- The drop: the hips' rise from bending about the neck, the carried squash, the walk.
	local wanted = torsoLength * (1 - math.cos(theta))
		+ torsoLength * (1 - pose.squash)
		+ legLength * (1 - math.cos(math.abs(swing))) * (1 - seat)
	local keep = rig.headKeep * model.headRadius
	local drop = clamp(wanted, -keep, keep)
	o.drop = drop
	o.anchorY = headC[2] - seatDrop

	-- The head, about its own centre.
	local headX, headY, headZ = headC[1], headC[2] - seatDrop - drop, headC[3]
	local nod = rig.headNod
	local n00, n01, n02, n10, n11, n12, n20, n21, n22 = leanRotation(lx * nod, 0, lz * nod)
	local t00, t01, t02, t10, t11, t12, t20, t21, t22 = rotY(yaw + pose.twist * rig.headTurn)
	local h00, h01, h02, h10, h11, h12, h20, h21, h22 = mul(
		n00,
		n01,
		n02,
		n10,
		n11,
		n12,
		n20,
		n21,
		n22,
		t00,
		t01,
		t02,
		t10,
		t11,
		t12,
		t20,
		t21,
		t22
	)
	place(o.head, headX, headY, headZ, h00, h01, h02, h10, h11, h12, h20, h21, h22, headC)
	o.headX, o.headY, o.headZ = headX, headY, headZ
	local dy = headY - o.anchorY
	o.headOffset = math.sqrt(headX * headX + dy * dy + headZ * headZ)

	placeUpper(o, model, pose, lx, lz, seatDrop + drop)

	local lead = model.leadLeg or "legL"
	local step = pose.thrust * rig.stepShare
	o.footL = placeLeg(
		o.legL,
		o.torso,
		hipL,
		1,
		if lead == "legL" then step else 0,
		model,
		rig,
		pose,
		swing,
		seat
	)
	o.footR = placeLeg(
		o.legR,
		o.torso,
		hipR,
		-1,
		if lead == "legR" then step else 0,
		model,
		rig,
		pose,
		swing,
		seat
	)
	return o
end

-- --- Arm [arm_channel] -----------------------------------------------------------------------------

-- The weapon arm's pitch, yaw and roll for one frame. `threat` = the frame's Threat (nil = no
-- attack: the carry); `shape` = the attack's shape, or the kind's first attack's out of one;
-- `attack` = that attack's windup and lock (a line is aimed when its line locks).
--   windup: carry -> coil with the build (coil -> strike with the snap for a lunge or a slam),
--     plus the whirl {turns, sin, cos}: build x (sin t x sin + (cos t - 1) x cos), t = 2 pi x
--     turns x u, back on the coil exactly at the release;
--   attack: an arc swings coil -> follow with the sweep; a lane goes coil -> strike over the first
--     quarter of the charge; a throw (shot, lob, line) goes coil -> strike over throwShare of the
--     strike, then strike -> follow; the rest go strike -> follow;
--   recover: from where the blow left it to the slump, waking to the carry.
-- Then the seat, the walk swing, and for a `steady` shape the body's forward lean added to the
-- pitch (the keys are world pitches: the aim stays level while the body leans).
function RaiderPose.Arm(
	model: Model,
	shape: string,
	threat: ThreatOut?,
	pose: Pose,
	rig: RigNumbers,
	attack: ThreatIn?
): (number, number, number)
	local keys = model.arm
	local carry = keys.carry
	local s: ArmShape = keys.shapes[shape] or {}
	local coil = s.coil or carry
	local strike = s.strike or carry
	local follow = s.follow or s.strike or carry
	local phase = if threat ~= nil then threat.phase else "none"
	local a1, a2, a3 = carry[1], carry[2], carry[3]
	if threat ~= nil and phase == "windup" then
		local build = threat.build
		if
			shape == "line"
			and attack ~= nil
			and attack.lock > 0
			and attack.windup > attack.lock
		then
			build = math.min(threat.age / (attack.windup - attack.lock), 1) ^ 2
		end
		a1, a2, a3 = armLerp(carry[1], carry[2], carry[3], coil, build)
		if SNAP_SHAPES[shape] and threat.snap > 0 then
			a1, a2, a3 = armLerp(coil[1], coil[2], coil[3], strike, threat.snap)
		end
		local whirl = s.whirl
		if whirl ~= nil then
			local t = 2 * math.pi * whirl.turns * threat.u
			local sn, cs = math.sin(t), math.cos(t) - 1
			a1 += build * (sn * whirl.sin[1] + cs * whirl.cos[1])
			a2 += build * (sn * whirl.sin[2] + cs * whirl.cos[2])
			a3 += build * (sn * whirl.sin[3] + cs * whirl.cos[3])
		end
	elseif threat ~= nil and phase == "attack" then
		if shape == "arc" then
			a1, a2, a3 = armLerp(coil[1], coil[2], coil[3], follow, threat.sweep)
		elseif shape == "lane" then
			a1, a2, a3 = armLerp(coil[1], coil[2], coil[3], strike, math.min(threat.u / 0.25, 1))
		elseif THROW_SHAPES[shape] then
			local share = rig.throwShare
			if threat.u < share then
				a1, a2, a3 = armLerp(coil[1], coil[2], coil[3], strike, threat.u / share)
			else
				a1, a2, a3 = armLerp(
					strike[1],
					strike[2],
					strike[3],
					follow,
					(threat.u - share) / (1 - share)
				)
			end
		else
			a1, a2, a3 = armLerp(strike[1], strike[2], strike[3], follow, threat.u)
		end
	elseif threat ~= nil and phase == "recover" then
		local last = if shape == "lane" then strike else follow
		local r1, r2, r3 = armLerp(carry[1], carry[2], carry[3], keys.slump, threat.slump)
		a1 = angleLerp(last[1], r1, threat.settle)
		a2 = angleLerp(last[2], r2, threat.settle)
		a3 = angleLerp(last[3], r3, threat.settle)
	end
	local seat = smoothstep(clamp(pose.seat, 0, 1))
	if seat > 0 then
		a1, a2, a3 = armLerp(a1, a2, a3, keys.seat, seat)
	end
	local swing = rig.armSwing
		* (model.armSwingShare or 1)
		* pose.walkAmp
		* math.sin(pose.walkPhase)
	local steady = if s.steady then pose.lean else 0
	return a1 + swing + steady, a2, a3
end

-- --- Walk [walk_step] ------------------------------------------------------------------------------

-- One frame of the walk cycle. `travel` = studs the feet moved on the flat this frame, `dt` its
-- seconds, `speed` the kind's, `distance` the body's from the camera and `nearStuds` the most it
-- walks at (rig.walkNearStuds, or Theme.COMBAT_RAIDER_WALK_NEAR_LOW on a low-end device):
--   phase = (phase + 2 pi x travel / (strideLegs x legLength)) mod 2 pi
--   goal  = 0 past nearStuds, else clamp((travel / dt) / (speed x walkFullShare), 0, 1)
--   amp   = goal when |goal - amp| < COMBAT_RAIDER_WALK_SETTLE,
--           else amp + (goal - amp) x (1 - exp(-dt x COMBAT_RAIDER_WALK_EASE_RATE))
-- A zero stride, dt or speed leaves the phase or takes 0 as the goal.
function RaiderPose.Walk(
	phase: number,
	amp: number,
	travel: number,
	dt: number,
	speed: number,
	legLength: number,
	distance: number,
	nearStuds: number,
	rig: RigNumbers,
	consts: Consts
): (number, number)
	local stride = rig.strideLegs * legLength
	if stride > 0 then
		phase = (phase + TWO_PI * travel / stride) % TWO_PI
	end
	local full = speed * rig.walkFullShare
	local goal = 0
	if distance <= nearStuds and dt > 0 and full > 0 then
		goal = clamp((travel / dt) / full, 0, 1)
	end
	local gap = goal - amp
	if math.abs(gap) < consts.COMBAT_RAIDER_WALK_SETTLE then
		amp = goal
	else
		amp += gap * (1 - math.exp(-dt * consts.COMBAT_RAIDER_WALK_EASE_RATE))
	end
	return phase, amp
end

-- --- Paint [paint] ---------------------------------------------------------------------------------

local function setLerp(into: Rgb, a: Rgb, b: Rgb, t: number): ()
	into[1] = lerp(a[1], b[1], t)
	into[2] = lerp(a[2], b[2], t)
	into[3] = lerp(a[3], b[3], t)
end

local function setRgb(into: Rgb, from: Rgb): ()
	into[1], into[2], into[3] = from[1], from[2], from[3]
end

-- Scratch for the two bases: Paint runs once per repaint, never in parallel.
local baseScratch: Rgb = { 0, 0, 0 }
local skinScratch: Rgb = { 0, 0, 0 }
local legScratch: Rgb = { 0, 0, 0 }

-- What each painted role shows. kindColor and skin are 0-255 as the configs write them.
-- cloth = the placeholder torso's rule on the kind's colour, clothLeg = its legs' rule, skin =
-- its head's rule (the tint half as far) on the skin colour, glow = the visor's rule, held lit
-- for good once enraged. Gear and the plate are never painted here.
function RaiderPose.Paint(
	kindColor: { number },
	skin: { number },
	threat: PaintThreat,
	flash: boolean,
	enraged: boolean,
	consts: Consts,
	out: PaintOut?
): PaintOut
	local o = out or RaiderPose.NewPaintOut()
	local c = consts
	local base, skinBase, leg = baseScratch, skinScratch, legScratch
	base[1], base[2], base[3] = kindColor[1] / 255, kindColor[2] / 255, kindColor[3] / 255
	skinBase[1], skinBase[2], skinBase[3] = skin[1] / 255, skin[2] / 255, skin[3] / 255
	if enraged then
		setLerp(base, base, c.COMBAT_RANGE_ENRAGE_COLOR, c.COMBAT_RANGE_ENRAGE_SHARE)
		setLerp(skinBase, skinBase, c.COMBAT_RANGE_ENRAGE_COLOR, c.COMBAT_RANGE_ENRAGE_SHARE * 0.5)
	end
	setLerp(leg, base, c.LEG_SHADE, c.LEG_SHADE_SHARE)
	local neon = flash or threat.glow
	o.clothNeon, o.clothLegNeon, o.skinNeon = neon, neon, neon
	if flash then
		setRgb(o.cloth, c.FLASH_COLOR)
		setRgb(o.clothLeg, c.FLASH_COLOR)
		setRgb(o.skin, c.FLASH_COLOR)
	elseif threat.tint > 0 then
		setLerp(o.cloth, base, threat.tintColor, threat.tint)
		setLerp(o.clothLeg, leg, threat.tintColor, threat.tint)
		setLerp(o.skin, skinBase, threat.tintColor, threat.tint * 0.5)
	else
		setRgb(o.cloth, base)
		setRgb(o.clothLeg, leg)
		setRgb(o.skin, skinBase)
	end
	if enraged then
		setRgb(o.glow, c.COMBAT_RANGE_ENRAGE_GLOW_COLOR)
		o.glowNeon = true
	elseif threat.visorHot then
		setRgb(o.glow, c.VISOR_HOT_COLOR)
		o.glowNeon = true
	else
		setRgb(o.glow, c.VISOR_COLOR)
		o.glowNeon = false
	end
	return o
end

return RaiderPose
