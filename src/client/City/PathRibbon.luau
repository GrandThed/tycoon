--!strict
-- Smooth path centrelines (docs/INTERFACES.md "Wave 1d — baked paths"). A 1:1 port of the
-- centreline half of tools/pathmock/pathgeom.py, which `tools/paths/bake.py` also runs to bake
-- the path meshes: control points are cleaned and filleted, splined (centripetal Catmull-Rom)
-- and resampled by arc length, joiners snap onto their host's smoothed curve, and a tapered
-- two-sine meander is applied. The client keeps the curves, not the meshes: the smoothed curves
-- are what tree clearance is measured from, the meandered curves are the lanes vehicles drive
-- and the track a piece's dust burst follows.
--
-- Pure: numbers, tables and arrays only, no Roblox globals or services, so the same file runs
-- under a plain Luau interpreter against the Python mock. Points are `{ x, z }` in plot-local
-- studs (origin at the plot's top-centre, front -Z).
--
-- The whole network (every spine polyline, connector and routable spur) is smoothed once per
-- layout, whatever is owned, so adding a path never changes another path's geometry and every
-- client derives the same curves as the bake did.

export type Point = { number }

-- The width jitter of the drawn path is baked into the meshes, so only the lateral wobble,
-- which moves the centreline, is needed here.
export type MeanderConfig = { amplitude: number, wavelength: number }

export type Curve = {
	p: { Point },
	s: { number }, -- cumulative arc length per point
	total: number,
}

export type ChainKind = "lane" | "connector" | "spur"

export type Chain = {
	kind: ChainKind,
	-- "lane<n>" / "conn<key>" / the slot id: the name tools/paths/network.py gives the same chain
	-- and records per piece in assets/build/paths/<Era>.json, so a chain printed in Studio can be
	-- matched against the bake. Nothing here reads it.
	id: string,
	layer: number, -- 0 polyline 1, 1 other polylines and connectors, 2 spurs
	key: number, -- phase key: polyline index, 96 + connector stretch id, or slot id byte sum
	entrance: boolean, -- polyline 1: its first point is the plot entrance
	points: { Point }, -- control points after join snapping
	raw: Curve, -- the unsmoothed control polyline, for host tests
	curve: Curve, -- smoothed centreline (fillets + spline)
	final: Curve, -- meandered centreline with the straight end extensions
	finalSmooth: { number }, -- `curve` arc length at each `final` point
	extStart: number,
	extEnd: number,
	joinStart: boolean,
	joinEnd: boolean,
	roundStart: boolean,
	roundEnd: boolean,
	junctions: { number }, -- `curve` arc lengths where joiners land
	phase: number,
}

export type ConnectorInput = { key: number, from: Point, to: Point }
export type SpurInput = { id: string, points: { Point } }

export type NetworkInput = {
	width: number,
	meander: MeanderConfig?,
	polylines: { { Point } },
	connectors: { ConnectorInput },
	spurs: { SpurInput }, -- sorted by slot id
}

export type Network = {
	-- The road width the chains were smoothed with, as in network.py's Bake: callers pass their
	-- own copy of it, so this is the record of what these curves were actually built from.
	width: number,
	amplitude: number,
	wavelength: number,
	sampleSpacing: number, -- how finely callers should walk a curve (SAMPLE_SPACING)
	chains: { Chain },
	polylineChains: { number }, -- polyline index -> chain index
	connectorChains: { [number]: number }, -- connector key -> chain index
	spurChains: { [string]: number }, -- slot id -> chain index
}

-- Geometry constants shared with tools/pathmock/pathgeom.py, which bakes the meshes: the client
-- must smooth and meander exactly as the bake did or the lanes and tree clearance would drift
-- off the baked path, so these are code (and part of the approved look), not config.
local SAMPLE_SPACING = 0.6 -- pathgeom SAMPLE_STEP: arc-length resample spacing
local CORNER_RADIUS_WIDTHS = 2 -- pathgeom FILLET_RADIUS_WIDTHS: corner radius / road width
local FILLET_MIN_DEG = 4 -- gentler corners are left to the spline
local ARC_STEP_DEG = 12 -- fillet arc sampling
local CR_ALPHA = 0.5 -- centripetal Catmull-Rom: no loops or cusps on uneven legs
local CR_SAMPLES_PER_STUD = 8
local MEANDER_TAPER_WIDTHS = 2 -- the wobble fades to 0 over this many widths at ends and joins
local MEANDER_STEP = 0.1 -- dense resample of the meandered centreline
local MIN_LEG_WIDTHS = 1 -- a shorter control leg cannot hold a bend without folding
local EXTEND_WIDTHS = 0.45 -- a joiner runs this far past the host centreline, capped round
local ROUND_END_WIDTHS = 0.8 -- a lane end hosting a join runs on this far, capped round
local ROUND_END_REACH = 1.5 -- a join this close to a lane end rounds that end
local HOST_REACH_EXTRA = 0.1 -- host test radius beyond width / 2
local TANGENT_H = 0.35 -- central-difference half step for the meander normal
-- The meander wave: two sines at an irrational-looking ratio so the wobble never visibly repeats.
local WAVE_A = 0.62
local WAVE_B = 0.38
local WAVE_RATIO = 2.13
local WAVE_PHASE_SCALE = 1.71
local WAVE_PHASE_SHIFT = 0.9
local GOLDEN_ANGLE = 2.399963 -- spreads per-chain phases evenly around the circle
local FALLBACK_WAVELENGTH = 18 -- unused without a meander (amplitude 0), kept finite
local DEDUPE_EPS = 0.05
local DENSE_DEDUPE_EPS = 1e-3
local PARAM_EPS = 1e-4
local TINY = 1e-9
local FULL_TURN = 2 * math.pi

local PathRibbon = {}

-- ------------------------------------------------------------------ small helpers

local function len(ax: number, az: number): number
	return math.sqrt(ax * ax + az * az)
end

local function smoothstep(x: number): number
	local c = math.clamp(x, 0, 1)
	return c * c * (3 - 2 * c)
end

local function dist(a: Point, b: Point): number
	return len(a[1] - b[1], a[2] - b[2])
end

local function unit(ax: number, az: number): (number, number)
	local d = len(ax, az)
	if d < TINY then
		return 0, 0
	end
	return ax / d, az / d
end

-- ------------------------------------------------------------------ 1. control points

local function dedupe(points: { Point }, eps: number): { Point }
	local out: { Point } = {}
	for _, p in points do
		if #out == 0 or dist(p, out[#out]) > eps then
			table.insert(out, p)
		end
	end
	return out
end

local function dropCollinear(points: { Point }): { Point }
	if #points < 3 then
		return points
	end
	local out: { Point } = { points[1] }
	for i = 2, #points - 1 do
		local last = out[#out]
		local d0x, d0z = unit(points[i][1] - last[1], points[i][2] - last[2])
		local d1x, d1z = unit(points[i + 1][1] - points[i][1], points[i + 1][2] - points[i][2])
		if d0x * d1x + d0z * d1z < 0.9995 then
			table.insert(out, points[i])
		end
	end
	table.insert(out, points[#points])
	return out
end

-- A leg shorter than minLeg cannot hold a bend: merge its two points into their midpoint, or
-- drop the interior one when the leg touches an end.
local function mergeShortLegs(points: { Point }, minLeg: number): { Point }
	local pts = table.clone(points)
	local changed = true
	while changed and #pts > 2 do
		changed = false
		for i = 1, #pts - 1 do
			if dist(pts[i + 1], pts[i]) >= minLeg then
				continue
			end
			if i == 1 then
				table.remove(pts, 2)
			elseif i + 1 == #pts then
				table.remove(pts, i)
			else
				local merged =
					{ (pts[i][1] + pts[i + 1][1]) * 0.5, (pts[i][2] + pts[i + 1][2]) * 0.5 }
				pts[i] = merged
				table.remove(pts, i + 1)
			end
			changed = true
			break
		end
	end
	return pts
end

-- Each corner becomes a circular arc of `radius` (shrunk when a leg is short), so a 90-degree
-- corner reads as a round bend instead of a kink.
local function fillet(points: { Point }, radius: number): { Point }
	if #points < 3 then
		return table.clone(points)
	end
	local out: { Point } = { points[1] }
	for i = 2, #points - 1 do
		local p0, p1, p2 = out[#out], points[i], points[i + 1]
		local inX, inZ = unit(p1[1] - p0[1], p1[2] - p0[2])
		local outX, outZ = unit(p2[1] - p1[1], p2[2] - p1[2])
		local turn = math.acos(math.clamp(inX * outX + inZ * outZ, -1, 1))
		if math.deg(turn) < FILLET_MIN_DEG then
			table.insert(out, p1)
			continue
		end
		local half = math.tan(turn / 2)
		-- The leg before may already be shortened by the previous arc.
		local limit = math.min(0.95 * dist(p1, p0), 0.48 * dist(p2, p1))
		local tangentLength = math.min(radius * half, limit)
		local r = tangentLength / half
		local ax, az = p1[1] - inX * tangentLength, p1[2] - inZ * tangentLength
		local side = if inX * outZ - inZ * outX > 0 then 1 else -1
		local nx, nz = -inZ * side, inX * side
		local cx, cz = ax + nx * r, az + nz * r
		local start = math.atan2(az - cz, ax - cx)
		local steps = math.max(2, math.ceil(math.deg(turn) / ARC_STEP_DEG))
		for k = 0, steps do
			local angle = start + side * turn * k / steps
			table.insert(out, { cx + r * math.cos(angle), cz + r * math.sin(angle) })
		end
	end
	table.insert(out, points[#points])
	return dedupe(out, DEDUPE_EPS)
end

-- ------------------------------------------------------------------ 2. centripetal Catmull-Rom

-- Dense polyline through `points` (Barry-Goldman form); mirrored phantom ends make the curve
-- leave each end along its first or last leg.
local function catmullRom(points: { Point }): { Point }
	if #points < 2 then
		return table.clone(points)
	end
	local n = #points
	local pts: { Point } = {
		{ points[1][1] * 2 - points[2][1], points[1][2] * 2 - points[2][2] },
	}
	for _, p in points do
		table.insert(pts, p)
	end
	table.insert(pts, { points[n][1] * 2 - points[n - 1][1], points[n][2] * 2 - points[n - 1][2] })
	local out: { Point } = { points[1] }
	for i = 2, #pts - 2 do
		local p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
		local t0 = 0
		local t1 = t0 + math.max(dist(p1, p0), PARAM_EPS) ^ CR_ALPHA
		local t2 = t1 + math.max(dist(p2, p1), PARAM_EPS) ^ CR_ALPHA
		local t3 = t2 + math.max(dist(p3, p2), PARAM_EPS) ^ CR_ALPHA
		local count = math.max(2, math.ceil(dist(p2, p1) * CR_SAMPLES_PER_STUD))
		for k = 1, count do
			local t = t1 + (t2 - t1) * k / count
			local a1x = p0[1] * ((t1 - t) / (t1 - t0)) + p1[1] * ((t - t0) / (t1 - t0))
			local a1z = p0[2] * ((t1 - t) / (t1 - t0)) + p1[2] * ((t - t0) / (t1 - t0))
			local a2x = p1[1] * ((t2 - t) / (t2 - t1)) + p2[1] * ((t - t1) / (t2 - t1))
			local a2z = p1[2] * ((t2 - t) / (t2 - t1)) + p2[2] * ((t - t1) / (t2 - t1))
			local a3x = p2[1] * ((t3 - t) / (t3 - t2)) + p3[1] * ((t - t2) / (t3 - t2))
			local a3z = p2[2] * ((t3 - t) / (t3 - t2)) + p3[2] * ((t - t2) / (t3 - t2))
			local b1x = a1x * ((t2 - t) / (t2 - t0)) + a2x * ((t - t0) / (t2 - t0))
			local b1z = a1z * ((t2 - t) / (t2 - t0)) + a2z * ((t - t0) / (t2 - t0))
			local b2x = a2x * ((t3 - t) / (t3 - t1)) + a3x * ((t - t1) / (t3 - t1))
			local b2z = a2z * ((t3 - t) / (t3 - t1)) + a3z * ((t - t1) / (t3 - t1))
			table.insert(out, {
				b1x * ((t2 - t) / (t2 - t1)) + b2x * ((t - t1) / (t2 - t1)),
				b1z * ((t2 - t) / (t2 - t1)) + b2z * ((t - t1) / (t2 - t1)),
			})
		end
	end
	return dedupe(out, DENSE_DEDUPE_EPS)
end

-- ------------------------------------------------------------------ curves

-- Arc-length parameterised polyline with optional straight extensions at both ends.
local function newCurve(dense: { Point }, extendStart: number, extendEnd: number): Curve
	local p = table.clone(dense)
	local n = #p
	if extendStart > 0 and n >= 2 then
		local other = p[math.min(4, n)]
		local dx, dz = unit(p[1][1] - other[1], p[1][2] - other[2])
		table.insert(p, 1, { p[1][1] + dx * extendStart, p[1][2] + dz * extendStart })
	end
	n = #p
	if extendEnd > 0 and n >= 2 then
		local other = p[math.max(n - 3, 1)]
		local dx, dz = unit(p[n][1] - other[1], p[n][2] - other[2])
		table.insert(p, { p[n][1] + dx * extendEnd, p[n][2] + dz * extendEnd })
	end
	local s: { number } = { 0 }
	for i = 2, #p do
		s[i] = s[i - 1] + dist(p[i], p[i - 1])
	end
	return { p = p, s = s, total = s[#s] }
end

local function locate(curve: Curve, arc: number): (number, number, number)
	local s = math.clamp(arc, 0, curve.total)
	local lo, hi = 1, #curve.s
	if hi == 1 then
		return 1, 1, 0
	end
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if curve.s[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local segment = curve.s[hi] - curve.s[lo]
	local t = if segment < TINY then 0 else (s - curve.s[lo]) / segment
	return lo, hi, t
end

function PathRibbon.CurvePoint(curve: Curve, arc: number): (number, number)
	local lo, hi, t = locate(curve, arc)
	local a, b = curve.p[lo], curve.p[hi]
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
end

function PathRibbon.CurveTangent(curve: Curve, arc: number, h: number): (number, number)
	local ax, az = PathRibbon.CurvePoint(curve, arc + h)
	local bx, bz = PathRibbon.CurvePoint(curve, arc - h)
	return unit(ax - bx, az - bz)
end

-- Nearest point on the curve: (distance, arc length there).
local function project(curve: Curve, qx: number, qz: number): (number, number)
	local bestDistance, bestArc = 1e18, 0
	for i = 2, #curve.p do
		local a, b = curve.p[i - 1], curve.p[i]
		local abx, abz = b[1] - a[1], b[2] - a[2]
		local ll = abx * abx + abz * abz
		local t = if ll < 1e-12
			then 0
			else math.clamp(((qx - a[1]) * abx + (qz - a[2]) * abz) / ll, 0, 1)
		local d = len(qx - (a[1] + abx * t), qz - (a[2] + abz * t))
		if d < bestDistance then
			bestDistance = d
			bestArc = curve.s[i - 1] + t * math.sqrt(ll)
		end
	end
	return bestDistance, bestArc
end

-- ------------------------------------------------------------------ 3. meander + width noise

local function wave(s: number, phase: number, wavelength: number): number
	local k = FULL_TURN / wavelength
	return WAVE_A * math.sin(k * s + phase)
		+ WAVE_B * math.sin(k * WAVE_RATIO * s + phase * WAVE_PHASE_SCALE + WAVE_PHASE_SHIFT)
end

-- ------------------------------------------------------------------ 4. network

local function smoothCurve(points: { Point }, radius: number, minLeg: number): Curve
	return newCurve(catmullRom(fillet(mergeShortLegs(points, minLeg), radius)), 0, 0)
end

local function byteSum(text: string): number
	local sum = 0
	for index = 1, #text do
		sum += string.byte(text, index)
	end
	return sum
end

local function newChain(
	kind: ChainKind,
	id: string,
	layer: number,
	key: number,
	points: { Point }
): Chain
	local cleaned = dropCollinear(dedupe(points, DEDUPE_EPS))
	local empty: Curve = { p = {}, s = {}, total = 0 }
	return {
		kind = kind,
		id = id,
		layer = layer,
		key = key,
		entrance = false,
		points = cleaned,
		raw = empty,
		curve = empty,
		final = empty,
		finalSmooth = {},
		extStart = 0,
		extEnd = 0,
		joinStart = false,
		joinEnd = false,
		roundStart = false,
		roundEnd = false,
		junctions = {},
		phase = 0,
	}
end

function PathRibbon.Build(input: NetworkInput): Network
	local width = input.width
	local meander = input.meander
	local network: Network = {
		width = width,
		amplitude = if meander ~= nil then meander.amplitude else 0,
		wavelength = if meander ~= nil and meander.wavelength > 0
			then meander.wavelength
			else FALLBACK_WAVELENGTH,
		sampleSpacing = SAMPLE_SPACING,
		chains = {},
		polylineChains = {},
		connectorChains = {},
		spurChains = {},
	}
	local chains = network.chains
	-- pathgeom's chain order (connectors, lanes, spurs) so host ties resolve the same way.
	for _, connector in input.connectors do
		table.insert(
			chains,
			newChain(
				"connector",
				`conn{connector.key}`,
				1,
				connector.key,
				{ connector.from, connector.to }
			)
		)
		network.connectorChains[connector.key] = #chains
	end
	for index, points in input.polylines do
		local chain = newChain("lane", `lane{index}`, if index == 1 then 0 else 1, index, points)
		chain.entrance = index == 1
		table.insert(chains, chain)
		network.polylineChains[index] = #chains
	end
	for _, spur in input.spurs do
		if #spur.points < 2 then
			continue
		end
		table.insert(chains, newChain("spur", spur.id, 2, byteSum(spur.id), spur.points))
		network.spurChains[spur.id] = #chains
	end

	local radius = CORNER_RADIUS_WIDTHS * width
	local minLeg = MIN_LEG_WIDTHS * width
	for _, chain in chains do
		chain.curve = smoothCurve(chain.points, radius, minLeg)
		chain.raw = newCurve(chain.points, 0, 0)
	end

	local reach = width / 2 + HOST_REACH_EXTRA
	-- The nearest lower-layer lane whose unsmoothed centreline passes within reach of q (the
	-- street-plan attach rule), and the nearest arc on its smoothed curve.
	local function hostFor(chain: Chain, q: Point): (Chain?, number)
		local best: Chain? = nil
		local bestDistance, bestArc = 0, 0
		for _, host in chains do
			if host.kind == "spur" or host.layer >= chain.layer then
				continue
			end
			local d = project(host.raw, q[1], q[2])
			if d <= reach and (best == nil or d < bestDistance) then
				local _, arc = project(host.curve, q[1], q[2])
				best, bestDistance, bestArc = host, d, arc
			end
		end
		return best, bestArc
	end

	-- Joiners snap their joining end onto where the host really is after filleting (a corner
	-- moves inward by up to R(sqrt2 - 1)). Stable layer order, like pathgeom's sorted().
	local order: { number } = {}
	for index in chains do
		table.insert(order, index)
	end
	table.sort(order, function(a: number, b: number): boolean
		if chains[a].layer == chains[b].layer then
			return a < b
		end
		return chains[a].layer < chains[b].layer
	end)
	for _, index in order do
		local chain = chains[index]
		if chain.layer == 0 then
			continue
		end
		for _, atStart in { true, false } do
			if chain.kind == "spur" and atStart then
				continue -- a spur starts at its slot anchor, under the building
			end
			local q = if atStart then chain.points[1] else chain.points[#chain.points]
			local host, arc = hostFor(chain, q)
			if host == nil then
				continue
			end
			local tx, tz = PathRibbon.CurvePoint(host.curve, arc)
			local pts = table.clone(chain.points)
			if atStart then
				pts[1] = { tx, tz }
				chain.joinStart = true
			else
				pts[#pts] = { tx, tz }
				chain.joinEnd = true
			end
			chain.points = dedupe(pts, DEDUPE_EPS)
			chain.curve = smoothCurve(chain.points, radius, minLeg)
			table.insert(host.junctions, arc)
			-- A join at a lane's dead end rounds that end off past the join.
			if arc < ROUND_END_REACH then
				host.roundStart = true
			end
			if arc > host.curve.total - ROUND_END_REACH then
				host.roundEnd = true
			end
		end
	end

	local taperLength = MEANDER_TAPER_WIDTHS * width
	for _, chain in chains do
		local curve = chain.curve
		local total = curve.total
		chain.phase = (chain.key * GOLDEN_ANGLE) % FULL_TURN
		local nodes: { number } = { 0, total }
		for _, junction in chain.junctions do
			table.insert(nodes, junction)
		end
		-- The plot entrance stays open at full width (Wave 1c fix to the mock): no extension.
		local extStart = if chain.joinStart
			then EXTEND_WIDTHS * width
			elseif chain.roundStart and not chain.entrance then ROUND_END_WIDTHS * width
			else 0
		local extEnd = if chain.joinEnd
			then EXTEND_WIDTHS * width
			elseif chain.roundEnd then ROUND_END_WIDTHS * width
			else 0
		local count = math.max(8, math.ceil(total / MEANDER_STEP))
		local kept: { Point } = {}
		local keptSmooth: { number } = {}
		for k = 0, count do
			local s = total * k / count
			local tx, tz = PathRibbon.CurveTangent(curve, s, TANGENT_H)
			local nearest = math.huge
			for _, node in nodes do
				nearest = math.min(nearest, math.abs(s - node))
			end
			local offset = network.amplitude
				* smoothstep(nearest / taperLength)
				* wave(s, chain.phase, network.wavelength)
			local px, pz = PathRibbon.CurvePoint(curve, s)
			local point = { px - tz * offset, pz + tx * offset }
			if #kept == 0 or dist(point, kept[#kept]) > DENSE_DEDUPE_EPS then
				table.insert(kept, point)
				table.insert(keptSmooth, s)
			end
		end
		chain.final = newCurve(kept, extStart, extEnd)
		if extStart > 0 and #kept >= 2 then
			table.insert(keptSmooth, 1, -extStart)
		end
		if extEnd > 0 and #kept >= 2 then
			table.insert(keptSmooth, total + extEnd)
		end
		chain.finalSmooth = keptSmooth
		chain.extStart = extStart
		chain.extEnd = extEnd
	end
	return network
end

-- Final-curve arc length of the point nearest `(x, z)` on the chain's smoothed centreline, so a
-- network node maps onto the drawn curve the same way a join does.
function PathRibbon.ArcAt(network: Network, chainIndex: number, x: number, z: number): number
	local chain = network.chains[chainIndex]
	local _, smooth = project(chain.curve, x, z)
	local map = chain.finalSmooth
	local final = chain.final
	if #map == 0 then
		return 0
	end
	if smooth <= map[1] then
		return final.s[1]
	end
	if smooth >= map[#map] then
		return final.s[#map]
	end
	local lo, hi = 1, #map
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if map[mid] <= smooth then
			lo = mid
		else
			hi = mid
		end
	end
	local range = map[hi] - map[lo]
	local t = if range < TINY then 0 else (smooth - map[lo]) / range
	return final.s[lo] + (final.s[hi] - final.s[lo]) * t
end

-- The node-to-node range a whole chain covers (its final curve without the extensions).
function PathRibbon.FullSpan(network: Network, chainIndex: number): (number, number)
	local chain = network.chains[chainIndex]
	return chain.extStart, chain.final.total - chain.extEnd
end

-- Points along the drawn (meandered) centreline from arc `a` to arc `b` (either order), about
-- `spacing` apart, for the lane graph.
function PathRibbon.Centreline(
	network: Network,
	chainIndex: number,
	a: number,
	b: number,
	spacing: number
): { Point }
	local final = network.chains[chainIndex].final
	local count = math.max(1, math.ceil(math.abs(b - a) / math.max(spacing, DEDUPE_EPS)))
	local points: { Point } = {}
	for k = 0, count do
		local x, z = PathRibbon.CurvePoint(final, a + (b - a) * k / count)
		table.insert(points, { x, z })
	end
	return points
end

-- The smoothed (pre-meander) centreline of every chain, about `spacing` apart: what tree
-- clearance is measured from, for every path the plot can ever have.
function PathRibbon.SmoothedCentrelines(network: Network, spacing: number): { { Point } }
	local lines: { { Point } } = {}
	for _, chain in network.chains do
		local curve = chain.curve
		local count = math.max(1, math.ceil(curve.total / math.max(spacing, DEDUPE_EPS)))
		local line: { Point } = {}
		for k = 0, count do
			local x, z = PathRibbon.CurvePoint(curve, curve.total * k / count)
			table.insert(line, { x, z })
		end
		table.insert(lines, line)
	end
	return lines
end

return PathRibbon
