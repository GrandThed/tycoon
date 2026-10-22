--!strict
-- The client's draw time for Studio's "Draw N ms" line (docs/prompts/l4-w2-contract.md, section
-- 8): CrowdRenderer's Heartbeat step and LevelScenery's build steps each add the seconds they
-- spent, and CombatHud takes the sum once a frame and keeps its p95. A plain counter in a module
-- of its own, so the two drawers need nothing of each other or of the HUD.
--
-- A frame's sum may land one Heartbeat late (the order of Heartbeat handlers is the engine's), so
-- a single sample can hold two frames' work or none; over a window of hundreds of frames that
-- only shifts which frame a cost is booked to, not the p95. Outside Studio nothing takes it and
-- the sum only grows, by a few seconds an hour: one number, never read.

local DrawClock = {}

local pending = 0

-- `seconds` of drawing done this frame (os.clock differences; a negative or NaN is dropped).
function DrawClock.Add(seconds: number): ()
	if seconds == seconds and seconds > 0 then
		pending += seconds
	end
end

-- The seconds added since the last Take, and the counter back to 0.
function DrawClock.Take(): number
	local seconds = pending
	pending = 0
	return seconds
end

return DrawClock
