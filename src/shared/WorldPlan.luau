--!strict
-- The plot ring and everything laid out from it (M13, docs/INTERFACES.md "M13 contracts"). Pure:
-- no Roblox globals of any kind, only `math`, so the server, later waves and a Python mirror share
-- one definition; every size arrives as an argument from Game.json, World.json or the era layout.
-- Angles are radians, plot indices are 1-based, and a plot's centre is
-- (cos(angle), sin(angle)) * radius in X, Z.

-- Roblox's largest Part side. The ground is a single Part, so no wanted side can exceed it.
local MAX_PART_SIDE = 2048

export type Ring = {
	plotCount: number,
	-- Plot centres.
	radius: number,
	-- pi / plotCount: the angle from a plot's radial to the line splitting it from a neighbour.
	halfSector: number,
	-- The hub-side edge of every plot, and the far edge.
	frontRadius: number,
	backRadius: number,
}
export type Road = { angle: number, innerRadius: number, outerRadius: number, width: number }

local WorldPlan = {}

-- Plots are radial rectangles, so neighbours converge toward the hub and their inner corners
-- collide first. The ring is sized so each inner corner stays plotMargin / 2 clear of the radial
-- line splitting two plots (coplanar overlapping bases z-fight at the seam), and never so tight
-- that a front edge comes within plotMargin of the hub.
function WorldPlan.Ring(
	plotCount: number,
	plotMargin: number,
	hubRadius: number,
	plotSizeX: number,
	plotSizeZ: number
): Ring
	local halfSector = math.pi / plotCount
	local radius = math.max(
		plotSizeZ / 2
			+ (plotSizeX / 2 * math.cos(halfSector) + plotMargin / 2) / math.sin(halfSector),
		hubRadius + plotMargin + plotSizeZ / 2
	)
	return {
		plotCount = plotCount,
		radius = radius,
		halfSector = halfSector,
		frontRadius = radius - plotSizeZ / 2,
		backRadius = radius + plotSizeZ / 2,
	}
end

function WorldPlan.PlotAngle(ring: Ring, index: number): number
	return (index - 1) / ring.plotCount * 2 * math.pi
end

-- Side of the ground square. Without a wanted side it is the pre-M13 square, one plot depth past
-- the ring's back edge; a wanted side can only grow that, so the ground never ends under a plot.
function WorldPlan.GroundSide(ring: Ring, plotSizeZ: number, wantedSide: number?): number
	local ringSide = 2 * (ring.radius + plotSizeZ)
	if wantedSide == nil then
		return ringSide
	end
	return math.min(MAX_PART_SIDE, math.max(wantedSide, ringSide))
end

-- One strip per plot along its radial, from the hub to the plot's front edge. Two neighbouring
-- strips of this width start to overlap inside width / (2 * tan(halfSector)), so starting no
-- closer than that keeps their tops from ever sharing a plane at any plotCount. Every strip has
-- the same radii: the list is either one road per plot in plot order (entry i is plot i's) or,
-- when the strip would have no length, empty.
function WorldPlan.Roads(ring: Ring, hubRadius: number, width: number): { Road }
	local innerRadius = math.max(hubRadius, width / (2 * math.tan(ring.halfSector)))
	local outerRadius = ring.frontRadius
	local roads: { Road } = {}
	if innerRadius >= outerRadius then
		return roads
	end
	for index = 1, ring.plotCount do
		roads[index] = {
			angle = WorldPlan.PlotAngle(ring, index),
			innerRadius = innerRadius,
			outerRadius = outerRadius,
			width = width,
		}
	end
	return roads
end

return WorldPlan
