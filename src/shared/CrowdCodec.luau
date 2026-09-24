--!strict
-- Compact wire format for CrowdSnapshot (docs/INTERFACES.md "P1 contracts", decision 1). The
-- snapshot rides an UnreliableRemoteEvent, whose payload is capped near 900 bytes, so the server
-- splits a frame into packets of at most MAX_ENTRIES entries; every packet of one frame carries
-- the same server time, which is how the client knows they belong together. A packet that is lost
-- only freezes its enemies for one snapshot: removal is never implied by absence (CrowdRemove is
-- the only end of an enemy).
--
-- Layout, little-endian:
--   header (10 bytes)  u8 FORMAT_VERSION, u8 entry count, f64 server time (GetServerTimeNow)
--   entry  (11 bytes)  u16 id, i16 x, i16 y, i16 z (1/POSITION_SCALE studs from origin),
--                      u8 yaw (1/256 turn), u8 state (index into STATES), u8 hp (1/255)
-- Positions are the enemy's FEET, relative to the origin both sides pass in (the arena origin).
-- At 1/32 stud the range is ±1024 studs; anything further is clamped, never wrapped.
--
-- Pure apart from the Vector3 / buffer builtins, so the client decodes exactly what the server
-- encoded.

local Types = require(script.Parent:WaitForChild("Types"))

local FORMAT_VERSION = 1
local HEADER_BYTES = 10
local ENTRY_BYTES = 11
local POSITION_SCALE = 32
local INT16_MIN = -32768
local INT16_MAX = 32767
local MAX_ID = 65535
local TWO_PI = 2 * math.pi
-- Wire order is part of the format: append new states, never reorder.
local STATES: { Types.CrowdState } = { "idle", "move", "windup", "stagger", "airborne", "dead" }

local stateIndex: { [string]: number } = {}
for index, state in STATES do
	stateIndex[state] = index - 1
end

local function quantize(value: number): number
	local scaled = math.round(value * POSITION_SCALE)
	if scaled ~= scaled then
		return 0
	end
	return math.clamp(scaled, INT16_MIN, INT16_MAX)
end

local function encodeYaw(yaw: number): number
	if yaw ~= yaw then
		return 0
	end
	return math.round(yaw / TWO_PI * 256) % 256
end

local function decodeYaw(byte: number): number
	local yaw = byte / 256 * TWO_PI
	if yaw > math.pi then
		yaw -= TWO_PI
	end
	return yaw
end

-- Any living enemy keeps at least 1/255 so a sliver of HP never reads as a dead bar.
local function encodeHp(fraction: number): number
	if fraction ~= fraction or fraction <= 0 then
		return 0
	end
	return math.clamp(math.ceil(fraction * 255), 1, 255)
end

local CrowdCodec = {}

-- Entries per packet: 10 + 64 × 11 = 714 bytes, clear of the unreliable payload cap after
-- Roblox's own framing.
CrowdCodec.MAX_ENTRIES = 64
-- Snapshot (= crowd step) rate bounds; the server clamps crowd.snapshotHz to these and the
-- renderer clamps its interpolation delay the same way.
CrowdCodec.MIN_HZ = 2
CrowdCodec.MAX_HZ = 60

-- Encodes at most MAX_ENTRIES entries (the rest are ignored; the caller splits). serverTime is
-- carried in the header for ordering and interpolation; 0 when omitted.
function CrowdCodec.Encode(
	entries: { Types.CrowdSnapshotEntry },
	origin: Vector3,
	serverTime: number?
): buffer
	local count = math.min(#entries, CrowdCodec.MAX_ENTRIES)
	local data = buffer.create(HEADER_BYTES + count * ENTRY_BYTES)
	buffer.writeu8(data, 0, FORMAT_VERSION)
	buffer.writeu8(data, 1, count)
	buffer.writef64(data, 2, serverTime or 0)
	for index = 1, count do
		local entry = entries[index]
		local offset = HEADER_BYTES + (index - 1) * ENTRY_BYTES
		local relative = entry.position - origin
		buffer.writeu16(data, offset, math.clamp(entry.id, 0, MAX_ID))
		buffer.writei16(data, offset + 2, quantize(relative.X))
		buffer.writei16(data, offset + 4, quantize(relative.Y))
		buffer.writei16(data, offset + 6, quantize(relative.Z))
		buffer.writeu8(data, offset + 8, encodeYaw(entry.yaw))
		buffer.writeu8(data, offset + 9, stateIndex[entry.state] or 0)
		buffer.writeu8(data, offset + 10, encodeHp(entry.hpFraction))
	end
	return data
end

-- A malformed or foreign packet decodes to an empty list rather than erroring: the client drops
-- it and waits for the next snapshot.
function CrowdCodec.Decode(data: buffer, origin: Vector3): { Types.CrowdSnapshotEntry }
	local entries: { Types.CrowdSnapshotEntry } = {}
	local length = buffer.len(data)
	if length < HEADER_BYTES or buffer.readu8(data, 0) ~= FORMAT_VERSION then
		return entries
	end
	local count = buffer.readu8(data, 1)
	if length < HEADER_BYTES + count * ENTRY_BYTES then
		return entries
	end
	for index = 1, count do
		local offset = HEADER_BYTES + (index - 1) * ENTRY_BYTES
		local x = buffer.readi16(data, offset + 2) / POSITION_SCALE
		local y = buffer.readi16(data, offset + 4) / POSITION_SCALE
		local z = buffer.readi16(data, offset + 6) / POSITION_SCALE
		entries[index] = {
			id = buffer.readu16(data, offset),
			position = origin + Vector3.new(x, y, z),
			yaw = decodeYaw(buffer.readu8(data, offset + 8)),
			state = STATES[buffer.readu8(data, offset + 9) + 1] or "idle",
			hpFraction = buffer.readu8(data, offset + 10) / 255,
		}
	end
	return entries
end

-- Allocation-free decode for the per-snapshot hot path: calls fn once per entry with world
-- coordinates (origin already added) as plain numbers. Returns false, calling fn never, for a
-- malformed or foreign packet.
function CrowdCodec.DecodeEach(
	data: buffer,
	origin: Vector3,
	fn: (
		id: number,
		x: number,
		y: number,
		z: number,
		yaw: number,
		state: Types.CrowdState,
		hpFraction: number
	) -> ()
): boolean
	local length = buffer.len(data)
	if length < HEADER_BYTES or buffer.readu8(data, 0) ~= FORMAT_VERSION then
		return false
	end
	local count = buffer.readu8(data, 1)
	if length < HEADER_BYTES + count * ENTRY_BYTES then
		return false
	end
	local originX, originY, originZ = origin.X, origin.Y, origin.Z
	for index = 1, count do
		local offset = HEADER_BYTES + (index - 1) * ENTRY_BYTES
		fn(
			buffer.readu16(data, offset),
			originX + buffer.readi16(data, offset + 2) / POSITION_SCALE,
			originY + buffer.readi16(data, offset + 4) / POSITION_SCALE,
			originZ + buffer.readi16(data, offset + 6) / POSITION_SCALE,
			decodeYaw(buffer.readu8(data, offset + 8)),
			STATES[buffer.readu8(data, offset + 9) + 1] or "idle",
			buffer.readu8(data, offset + 10) / 255
		)
	end
	return true
end

-- The frame's server time (GetServerTimeNow at the step), or nil for a malformed packet. Packets
-- sharing a time are one frame; an older time than the newest seen is a late packet.
function CrowdCodec.ReadTime(data: buffer): number?
	if buffer.len(data) < HEADER_BYTES or buffer.readu8(data, 0) ~= FORMAT_VERSION then
		return nil
	end
	return buffer.readf64(data, 2)
end

return CrowdCodec
