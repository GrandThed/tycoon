--!strict
-- A fixed ring of one body's positions over time, and how fast that body has been moving by
-- the ring's own account (docs/INTERFACES.md "P5 contracts" → "Wave 1", ruling 7). WeaponService
-- keeps one per player, samples the server's copy of the root every Heartbeat, and reads the
-- speed when a client claims a position: the slack it grants comes from what the server saw,
-- never from the velocity the client replicates.
--
-- Pure: only Vector3 and table.create, no Roblox services and no clock of its own (every time
-- is an argument), so tools/crowd_harness can load it as it stands.

export type History = {
	capacity: number,
	times: { number },
	positions: { Vector3 },
	-- The newest slot, and how many slots hold a sample.
	head: number,
	count: number,
}

local PositionRing = {}

-- The ring index of the `order`-th newest sample (1 = the newest).
local function indexOf(history: History, order: number): number
	return (history.head - order) % history.capacity + 1
end

-- `capacity` samples are kept (floored, at least 1); a window longer than they cover reads the
-- oldest one, which only makes the speed smaller.
function PositionRing.New(capacity: number): History
	local size = math.max(math.floor(capacity), 1)
	return {
		capacity = size,
		times = table.create(size, 0),
		positions = table.create(size, Vector3.zero),
		head = 0,
		count = 0,
	}
end

-- One sample into the fixed ring: nothing is allocated.
function PositionRing.Record(history: History, now: number, position: Vector3): ()
	local head = history.head % history.capacity + 1
	history.head = head
	history.times[head] = now
	history.positions[head] = position
	history.count = math.min(history.count + 1, history.capacity)
end

-- Forgets every sample (a fresh character, or no living root): the motion behind them is not
-- this body's.
function PositionRing.Clear(history: History): ()
	history.count = 0
end

-- The fastest average speed over any stretch of about `span` seconds that ended within the last
-- `window` seconds: for `position` now and for every sample that recent, the displacement since
-- the newest sample at least `span` older (else the oldest it has), over the time between them
-- but never over less than `span`. A short history (a fresh spawn) can therefore only
-- under-read, and a body that has not moved reads 0.
-- Why a short stretch and not the net displacement over the whole window: a burst move ramps up
-- too slowly in that. A 20-stud dash of 0.15 s read 7 studs/s on its first server frame and
-- never its 133, so a swing made mid-dash was pulled back behind the player.
-- Why the fastest stretch and not only the one ending now: the reading then holds through a
-- replication stall of a few frames (and for `window` after a burst ends).
-- 0 for an empty history or a window that is not positive.
function PositionRing.Speed(
	history: History,
	now: number,
	position: Vector3,
	window: number,
	span: number
): number
	local count = history.count
	-- Written so that a NaN window, which fails every comparison, also returns 0.
	if not (window > 0) or count == 0 then
		return 0
	end
	-- A span that is not a positive number (or NaN, which fails the comparison) or is longer
	-- than the window falls back to the whole window, the most cautious reading.
	local stretch = if span > 0 and span < window then span else window
	local fastest = 0
	local endAt = now
	local endPosition = position
	local anchorOrder = 1
	-- order 0 = `position` now; order k = the k-th newest sample.
	for order = 0, count - 1 do
		if order > 0 then
			local index = indexOf(history, order)
			endAt = history.times[index]
			endPosition = history.positions[index]
			if now - endAt > window then
				break
			end
		end
		-- The anchor only ever moves further back. It needs no push past the end: the loop below
		-- walks it on until it is `stretch` older, `stretch` is positive, and the oldest sample
		-- is never an end, so the anchor always comes out an older sample than the end.
		local anchor = indexOf(history, anchorOrder)
		while anchorOrder < count and endAt - history.times[anchor] < stretch do
			anchorOrder += 1
			anchor = indexOf(history, anchorOrder)
		end
		local elapsed = endAt - history.times[anchor]
		local speed = (endPosition - history.positions[anchor]).Magnitude
			/ math.max(elapsed, stretch)
		-- A NaN fails the comparison and is dropped.
		if speed > fastest then
			fastest = speed
		end
	end
	return fastest
end

return PositionRing
