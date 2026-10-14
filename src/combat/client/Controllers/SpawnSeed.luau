--!strict
-- L1b Wave 2 (docs/INTERFACES.md "Wave 2 — the long road", L1b-W2-11). A crowd spawn info now
-- carries the body as it stood when the info was sent (`at` = its feet, `yaw`, `state`), so
-- CrowdRenderer can draw a body it has no snapshot of: every resident of the level on arrival,
-- and a dormant body, which the server leaves out of every snapshot. This module only reads
-- those three fields. They crossed the network, so each one is checked. Pure: no Instance.
--
-- A seed is a pose, never an attack. A spawn info is a still picture whose age the client
-- cannot know, so a windup, a blow or a recover seen in one would start a tell on a guessed
-- clock. Those states, and a stagger or a hop, seed as standing (`idle`); the first snapshot
-- then names what the body is doing, timed properly. A `dead` body is not seeded at all: its
-- death is the snapshot's and CrowdRemove's to show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local SpawnSeed = {}

local function finite(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

-- (feet, yaw, state) to seed the body with, or nil when the info carries no usable `at` (the
-- range's bodies, an older server) or describes a dead body.
function SpawnSeed.Read(info: any): (Vector3?, number, Types.CrowdState)
	if typeof(info) ~= "table" then
		return nil, 0, "idle"
	end
	local at = info.at
	if typeof(at) ~= "Vector3" or not (finite(at.X) and finite(at.Y) and finite(at.Z)) then
		return nil, 0, "idle"
	end
	local state = info.state
	if state == "dead" then
		return nil, 0, "idle"
	end
	-- The resting and walking poses are kept as they are; everything else stands.
	local pose: Types.CrowdState = "idle"
	if state == "move" then
		pose = "move"
	elseif state == "rest" then
		pose = "rest"
	elseif state == "rise" then
		pose = "rise"
	end
	local yaw = info.yaw
	return at, if finite(yaw) then yaw else 0, pose
end

return SpawnSeed
