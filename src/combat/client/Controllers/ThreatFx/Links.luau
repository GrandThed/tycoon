--!strict
-- ThreatFx child: the tethers between a boss and the guard that protects its plate
-- (docs/INTERFACES.md "P4 contracts" -> "Stop 3 — the Warlord and his guard"). While any of
-- his guard lives the Warlord's plate cannot be damaged, and the player has to learn that
-- without reading: a lit line runs from each living guard to him, in the guard's colour, so
-- the eye goes from the thing that will not break to the things that must die first. A guard
-- that dies takes its line with it; when the last one goes there are none, and his shell
-- opens (CrowdRenderer).
--
-- CrowdRenderer knows who guards whom; every frame ThreatFx feeds this module the pairs, and a
-- tether nobody fed is gone the same frame. One pooled part each, moved in the frame's one
-- batch. They are information and are never thinned.

local Theme = require(script.Parent.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Link = { part: Part, seen: boolean, length: number }

local TAU = 2 * math.pi
-- Two chests closer than this have nothing to draw between them.
local MIN_LENGTH = 0.5

local links: { [number]: Link } = {}

local Links = {}

-- One tether this frame, from a living guard's chest to the chest of the boss it guards.
function Links.Feed(guardId: number, from: Vector3, to: Vector3, serverNow: number): ()
	local length = (to - from).Magnitude
	if length < MIN_LENGTH then
		return
	end
	local known: Link? = links[guardId]
	local link: Link = known
		or {
			part = Pool.Take(Enum.PartType.Block, Theme.COMBAT_RANGE_WARD_COLOR),
			seen = true,
			length = -1,
		}
	links[guardId] = link
	link.seen = true
	if math.abs(length - link.length) > 0.02 then
		link.length = length
		local thickness = Theme.COMBAT_RANGE_LINK_THICKNESS
		link.part.Size = Vector3.new(thickness, thickness, length)
	end
	Pool.Place(link.part, CFrame.lookAt((from + to) / 2, to))
	-- A slow breath on the server clock, so every tether (and every client) swings together.
	local wave = 0.5 + 0.5 * math.sin(serverNow * TAU * Theme.COMBAT_RANGE_LINK_PULSE_HZ)
	local least = Theme.COMBAT_RANGE_LINK_TRANSPARENCY
	Pool.Show(link.part, least + (1 - least) * Theme.COMBAT_RANGE_LINK_PULSE * wave)
end

-- After the frame's feeds: a tether nobody fed has lost its guard, or its boss, and goes.
function Links.Sweep(): ()
	for guardId, link in links do
		if link.seen then
			link.seen = false
		else
			links[guardId] = nil
			Pool.Give(link.part)
		end
	end
end

function Links.Clear(): ()
	for guardId, link in links do
		links[guardId] = nil
		Pool.Give(link.part)
	end
end

return Links
