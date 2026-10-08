--!strict
-- ThreatFx child: the slinger's slow shots (docs/INTERFACES.md "P4 contracts" -> "Wave 2",
-- `shot`, and "Review round, wave 2"). The server announces a shot once (`enemyShot`), and
-- every client draws it where the server has it: from + velocity x (server time now -
-- firedAt). Nothing is simulated here, so a shot can neither drift nor arrive late.
--
-- How it ends. The world is static, so the server cuts the path at fire: `seconds` is already
-- the moment the shot meets a wall, or its full life. That end is this module's own, on the
-- server clock, exactly at from + velocity x seconds; no message comes for it and none is
-- waited for. `enemyShotEnd` comes only when the shot hurt a player, and when a set load
-- dropped it in flight.
--
-- A shot is a neon orb of its true radius (the sphere the server tests) inside a larger
-- see-through halo, with a short tail of fading copies behind it. It is the enemy's red: the
-- player's own arrows are thin cream shafts and the launcher's shell a dark ball, so a glowing
-- red orb is never theirs. Where it ends, a bright flash says it hit someone and a small dull
-- one that it met a wall, ran out or was dropped.
--
-- A hit is judged at the victim's own lag, so its end reaches a client after the orb has
-- already been drawn through the body it struck. The flash goes where the server says the
-- shot ended; the orb is never pulled back to it. It flies on for a moment, fading: an orb
-- that vanished ahead while a flash of its size appeared behind would read as a jump back.
-- A shot the player dodged gets no end at all and flies on through at full strength.
--
-- The orb and the halo are information and always drawn. The tail and the halo's pulse are
-- decoration and go on a low-end device.

local Theme = require(script.Parent.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Shot = {
	orb: Part,
	halo: Part,
	tail: { Part },
	from: Vector3,
	velocity: Vector3,
	diameter: number,
	firedAt: number,
	seconds: number,
	-- os.clock when a hit ended it and it began to fade out; 0 while it flies.
	spentAt: number,
	-- A set load dropped it in flight: it goes on the next step, where it is drawn then.
	dropped: boolean,
}
-- The flash where a shot ended: a ball growing between two diameters while it fades.
type Burst = { part: Part, startedAt: number, seconds: number, from: number, to: number }

local TAU = 2 * math.pi
-- More live shots than this are not drawn: the server's own cap (crowd.threat.maxShots) is far
-- below it, so reaching it means something is wrong, and the pool must not grow without end.
local MAX_DRAWN = 96

local shots: { [number]: Shot } = {}
local shotCount = 0
local bursts: { Burst } = {}

local Shots = {}

local function tailCount(): number
	return if Theme.lowEndDevice then 0 else Theme.COMBAT_RANGE_SHOT_TAIL
end

local function burst(at: Vector3, diameter: number, hit: boolean, clock: number): ()
	local part = Pool.Take(
		Enum.PartType.Ball,
		if hit then Theme.COMBAT_RANGE_SHOT_HIT_COLOR else Theme.COMBAT_RANGE_SHOT_WALL_COLOR
	)
	local scale = if hit
		then Theme.COMBAT_RANGE_SHOT_HIT_SCALE
		else Theme.COMBAT_RANGE_SHOT_WALL_SCALE
	part.Size = Vector3.one * diameter
	Pool.Place(part, CFrame.new(at))
	table.insert(bursts, {
		part = part,
		startedAt = clock,
		seconds = if hit
			then Theme.COMBAT_RANGE_SHOT_HIT_SECONDS
			else Theme.COMBAT_RANGE_SHOT_WALL_SECONDS,
		from = diameter,
		to = diameter * scale,
	})
end

local function release(id: number, shot: Shot): ()
	shots[id] = nil
	shotCount -= 1
	Pool.Give(shot.orb)
	Pool.Give(shot.halo)
	for _, part in shot.tail do
		Pool.Give(part)
	end
end

-- `enemyShot`: a shot left its slinger at `firedAt` (server time).
function Shots.Fire(
	id: number,
	from: Vector3,
	velocity: Vector3,
	radius: number,
	firedAt: number,
	seconds: number
): ()
	local known = shots[id]
	if known ~= nil then
		release(id, known)
	end
	if shotCount >= MAX_DRAWN or seconds <= 0 then
		return
	end
	local color = Theme.COMBAT_RANGE_TELL_COLOR
	local diameter = math.max(radius, 0.1) * 2
	local orb = Pool.Take(Enum.PartType.Ball, color)
	orb.Size = Vector3.one * diameter
	local halo = Pool.Take(Enum.PartType.Ball, color)
	halo.Size = Vector3.one * (diameter * Theme.COMBAT_RANGE_SHOT_HALO_SCALE)
	local tail: { Part } = {}
	local count = tailCount()
	for index = 1, count do
		local part = Pool.Take(Enum.PartType.Ball, color)
		-- Each copy further back is smaller: the tail tapers to nothing.
		part.Size = Vector3.one * (diameter * (1 - index / (count + 1)))
		table.insert(tail, part)
	end
	shots[id] = {
		orb = orb,
		halo = halo,
		tail = tail,
		from = from,
		velocity = velocity,
		diameter = diameter,
		firedAt = firedAt,
		seconds = seconds,
		spentAt = 0,
		dropped = false,
	}
	shotCount += 1
end

-- `enemyShotEnd`, at most one per shot; it may come in the very batch that fired it. `hit` =
-- it hurt a player, and `at` is the point of its path level with them. Otherwise a set load
-- dropped it where the server had it, which is a lag behind where this client draws it: it
-- fizzles where it is drawn instead, so it never jumps back.
function Shots.End(id: number, at: Vector3, hit: boolean): ()
	local shot = shots[id]
	if shot == nil or shot.spentAt > 0 or shot.dropped then
		return
	end
	if hit then
		-- Already past the body it struck: it fades out on its way (Step) and is not moved.
		local clock = os.clock()
		burst(at, shot.diameter, true, clock)
		shot.spentAt = clock
	else
		shot.dropped = true
	end
end

-- serverNow places the shots; clock (os.clock) runs the flashes and the halo's pulse.
function Shots.Step(serverNow: number, clock: number): ()
	local lowEnd = Theme.lowEndDevice
	local pulse = 1
		+ Theme.COMBAT_RANGE_SHOT_HALO_PULSE
			* math.sin(clock * TAU * Theme.COMBAT_RANGE_SHOT_HALO_PULSE_HZ)
	for id, shot in shots do
		local age = math.max(serverNow - shot.firedAt, 0)
		if shot.dropped or age >= shot.seconds then
			-- The end of its path: the wall the server cut it at, or its full life. The orb was
			-- last drawn just short of this point, never past it, so the dull flash lands
			-- exactly there and nothing pops back. A dropped shot fizzles where it is now.
			if shot.spentAt == 0 then
				burst(
					shot.from + shot.velocity * math.min(age, shot.seconds),
					shot.diameter,
					false,
					clock
				)
			end
			release(id, shot)
			continue
		end
		-- 0 while it flies; 0-1 through the fade after a hit ended it.
		local spent = 0
		if shot.spentAt > 0 then
			spent = (clock - shot.spentAt) / Theme.COMBAT_RANGE_SHOT_SPENT_SECONDS
			if spent >= 1 then
				release(id, shot)
				continue
			end
		end
		local frame = CFrame.new(shot.from + shot.velocity * age)
		local haloBase = Theme.COMBAT_RANGE_SHOT_HALO_TRANSPARENCY
		Pool.Place(shot.orb, frame)
		Pool.Show(shot.orb, spent)
		Pool.Place(shot.halo, frame)
		Pool.Show(shot.halo, haloBase + (1 - haloBase) * spent)
		if not lowEnd then
			shot.halo.Size = Vector3.one
				* (shot.diameter * Theme.COMBAT_RANGE_SHOT_HALO_SCALE * pulse)
		end
		local count = #shot.tail
		for index, part in shot.tail do
			local behind = age - index * Theme.COMBAT_RANGE_SHOT_TAIL_SECONDS
			-- The tail of a spent shot would trail back through the body it hit.
			if behind > 0 and shot.spentAt == 0 then
				Pool.Place(part, CFrame.new(shot.from + shot.velocity * behind))
				Pool.Show(
					part,
					Theme.COMBAT_RANGE_SHOT_TAIL_TRANSPARENCY
						+ (1 - Theme.COMBAT_RANGE_SHOT_TAIL_TRANSPARENCY) * (index - 1) / count
				)
			else
				Pool.Show(part, 1)
			end
		end
	end
	for index = #bursts, 1, -1 do
		local flash = bursts[index]
		local u = (clock - flash.startedAt) / flash.seconds
		if u >= 1 then
			Pool.Give(flash.part)
			table.remove(bursts, index)
		else
			flash.part.Size = Vector3.one * (flash.from + (flash.to - flash.from) * u)
			Pool.Show(flash.part, u)
		end
	end
end

-- Every shot and flash goes at once (the local player loaded a dummy set: the server ends each
-- shot where it is, and this spares the screen a flash for every one of them).
function Shots.Clear(): ()
	for id, shot in shots do
		release(id, shot)
	end
	for _, flash in bursts do
		Pool.Give(flash.part)
	end
	table.clear(bursts)
end

return Shots
