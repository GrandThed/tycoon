--!strict
-- Smooth path-ribbon geometry (docs/INTERFACES.md "Wave 1c — ribbon paths", "Geometry"). A
-- 1:1 port of tools/pathmock/pathgeom.py, the offline mock Ben approved: control points are
-- cleaned and filleted, splined (centripetal Catmull-Rom) and resampled by arc length, joiners
-- snap onto their host's smoothed curve, a tapered two-sine meander is applied, and each visible
-- run is skinned as a 4-column soft-edged strip with flares at joins and rounded caps at ends.
--
-- Pure: numbers, tables and arrays only, no Roblox globals or services, so the same file runs
-- under a plain Luau interpreter against the Python mock. Points are `{ x, z }` in plot-local
-- studs (origin at the plot's top-centre, front -Z).
--
-- The whole network (every spine polyline, connector and routable spur) is smoothed once per
-- layout, whatever is owned. A drawn piece is only an arc range of that fixed curve, so adding a
-- path never changes another path's geometry and every client derives identical meshes.

export type Point = { number }

-- CityDressing.json eras.<Era>.road.ribbon (mirrors Types.CityRibbonConfig; kept structural so
-- this module needs no require).
export type RibbonConfig = {
	textureLength: number,
	meshWidthFactor: number,
	cornerRadiusWidths: number,
	sampleSpacing: number,
	capLength: number,
	flare: number,
	layerLift: number,
	growSeconds: number,
}

export type MeanderConfig = { amplitude: number, wavelength: number, widthJitter: number }

export type Curve = {
	p: { Point },
	s: { number }, -- cumulative arc length per point
	total: number,
}

export type ChainKind = "lane" | "connector" | "spur"

export type Chain = {
	kind: ChainKind,
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
	uOffset: number,
}

export type ConnectorInput = { key: number, from: Point, to: Point }
export type SpurInput = { id: string, points: { Point } }

export type NetworkInput = {
	width: number,
	thickness: number,
	meander: MeanderConfig?,
	ribbon: RibbonConfig,
	polylines: { { Point } },
	connectors: { ConnectorInput },
	spurs: { SpurInput }, -- sorted by slot id
}

export type Network = {
	width: number,
	thickness: number,
	amplitude: number,
	wavelength: number,
	jitter: number,
	ribbon: RibbonConfig,
	chains: { Chain },
	polylineChains: { number }, -- polyline index -> chain index
	connectorChains: { [number]: number }, -- connector key -> chain index
	spurChains: { [string]: number }, -- slot id -> chain index
}

-- A visible node-to-node interval of one chain in `final` arc length (ends in either order).
-- dist* is the network distance from the entrance at that end (math.huge when unknown); growth
-- starts from the nearer end.
export type Span = { chain: number, a: number, b: number, distA: number, distB: number }

-- One drawn strip: an arc range of a chain's final curve including its end extensions.
export type Piece = {
	chain: number,
	lo: number,
	hi: number,
	nodeLo: number, -- the node arcs the range was built from (without extensions)
	nodeHi: number,
	startCap: number, -- cap length at lo; 0 = open full-width end (the plot entrance)
	endCap: number,
	distLo: number,
	distHi: number,
	key: string,
}

-- Growth tip: rows on the growing side of `anchor` are squeezed toward it by `progress` (0..1).
export type Growth = { anchor: number, towardHigh: boolean, progress: number }

export type MeshData = {
	rows: number,
	positions: { number }, -- x, y, z per vertex (plot-local; y = layer height)
	uvs: { number }, -- u, v per vertex
	triangles: { number }, -- 1-based vertex indices, three per triangle, CCW seen from +Y
}

-- Look constants from pathgeom.py; docs/INTERFACES.md "Wave 1c — Geometry" freezes them as part
-- of the approved look, so they are code, not config.
local CAP_STEP = 0.25 -- denser sampling inside rounded caps keeps the tip outline round
local FILLET_MIN_DEG = 4 -- gentler corners are left to the spline
local ARC_STEP_DEG = 12 -- fillet arc sampling
local CR_ALPHA = 0.5 -- centripetal Catmull-Rom: no loops or cusps on uneven legs
local CR_SAMPLES_PER_STUD = 8
local MEANDER_TAPER_WIDTHS = 2 -- the wobble fades to 0 over this many widths at ends and joins
local MEANDER_STEP = 0.1 -- dense resample of the meandered centreline
local MIN_LEG_WIDTHS = 1 -- a shorter control leg cannot hold a bend without folding
local FLARE_LENGTH = 3 -- a joiner widens over this many studs before its join
local TIP_FADE = 3 -- a tip turns transparent over this many fade widths
local EXTEND_WIDTHS = 0.45 -- a joiner runs this far past the host centreline, capped round
local ROUND_END_WIDTHS = 0.8 -- a lane end hosting a join runs on this far, capped round
local ROUND_END_REACH = 1.5 -- a join this close to a lane end rounds that end
local HOST_REACH_EXTRA = 0.1 -- host test radius beyond width / 2
local FADE_V = 0.265 -- texture rows 0..FADE_V (and mirrored) hold the whole alpha fade
local COLUMNS = 4
local TANGENT_H = 0.35 -- central-difference half step for the meander normal
local SECTION_TANGENT_H = 0.2 -- and for the cross-section normal
local MIN_CAP_SCALE = 0.01 -- a cap never collapses a row to exactly zero width
-- The meander wave: two sines at an irrational-looking ratio so the wobble never visibly repeats.
local WAVE_A = 0.62
local WAVE_B = 0.38
local WAVE_RATIO = 2.13
local WAVE_PHASE_SCALE = 1.71
local WAVE_PHASE_SHIFT = 0.9
-- Width jitter reuses the wave, stretched and shifted so it is independent of the wobble.
local WIDTH_ARC_SCALE = 1.37
local WIDTH_PHASE_SHIFT = 2.1
local WIDTH_WAVELENGTH_SCALE = 0.8
local WIDTH_WAVE_GAIN = 0.5
local GOLDEN_ANGLE = 2.399963 -- spreads per-chain phases evenly around the circle
local GOLDEN_RATIO_FRACTION = 0.618034 -- spreads per-chain texture offsets evenly along u
local FALLBACK_WAVELENGTH = 18 -- unused without a meander (amplitude 0), kept finite
local ROW_ROUND = 1e5 -- row arc lengths dedupe on this grid (pathgeom rounds to 5 decimals)
local DEDUPE_EPS = 0.05
local DENSE_DEDUPE_EPS = 1e-3
local PARAM_EPS = 1e-4
local TINY = 1e-9
local END_EPS = 0.05 -- a node this close to a curve end is that end
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

local function widthAt(network: Network, chain: Chain, arc: number): number
	return network.width
		+ network.jitter
			* wave(
				arc * WIDTH_ARC_SCALE,
				chain.phase + WIDTH_PHASE_SHIFT,
				network.wavelength * WIDTH_WAVELENGTH_SCALE
			)
			* WIDTH_WAVE_GAIN
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
		uOffset = 0,
	}
end

function PathRibbon.Build(input: NetworkInput): Network
	local width = input.width
	local meander = input.meander
	local network: Network = {
		width = width,
		thickness = input.thickness,
		amplitude = if meander ~= nil then meander.amplitude else 0,
		wavelength = if meander ~= nil and meander.wavelength > 0
			then meander.wavelength
			else FALLBACK_WAVELENGTH,
		jitter = if meander ~= nil then meander.widthJitter else 0,
		ribbon = input.ribbon,
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

	local radius = input.ribbon.cornerRadiusWidths * width
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
		chain.uOffset = (chain.key * GOLDEN_RATIO_FRACTION) % 1
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

-- ------------------------------------------------------------------ 5. pieces

local function pieceKey(piece: Piece): string
	return string.format(
		"%d:%.4f:%.4f:%.4f:%.4f",
		piece.chain,
		piece.lo,
		piece.hi,
		piece.startCap,
		piece.endCap
	)
end

-- Visible spans merged into contiguous runs per chain, each with its end treatment: a curve end
-- keeps the chain's join or round extension (or a free cap, or stays open at the entrance); a
-- run ending mid-curve sits on a node that hosts a join, so it runs on and caps round there.
function PathRibbon.Pieces(network: Network, spans: { Span }): { Piece }
	local byChain: { [number]: { Span } } = {}
	local chainOrder: { number } = {}
	for _, span in spans do
		local list = byChain[span.chain]
		if list == nil then
			list = {}
			byChain[span.chain] = list
			table.insert(chainOrder, span.chain)
		end
		table.insert(list :: { Span }, span)
	end
	table.sort(chainOrder)
	local roundLength = ROUND_END_WIDTHS * network.width
	local capLength = network.ribbon.capLength
	local pieces: { Piece } = {}
	for _, chainIndex in chainOrder do
		local chain = network.chains[chainIndex]
		local total = chain.final.total
		local startNode, endNode = chain.extStart, total - chain.extEnd
		type Run = { lo: number, hi: number, distLo: number, distHi: number }
		local runs: { Run } = {}
		local list = byChain[chainIndex]
		local normalized: { Run } = {}
		for _, span in list do
			if span.a <= span.b then
				table.insert(
					normalized,
					{ lo = span.a, hi = span.b, distLo = span.distA, distHi = span.distB }
				)
			else
				table.insert(
					normalized,
					{ lo = span.b, hi = span.a, distLo = span.distB, distHi = span.distA }
				)
			end
		end
		table.sort(normalized, function(a: Run, b: Run): boolean
			return a.lo < b.lo
		end)
		for _, span in normalized do
			local last = runs[#runs]
			if last ~= nil and span.lo <= last.hi + END_EPS then
				if span.hi > last.hi then
					last.hi = span.hi
					last.distHi = span.distHi
				end
			else
				table.insert(runs, table.clone(span))
			end
		end
		for _, run in runs do
			local lo, startCap
			if run.lo <= startNode + END_EPS then
				lo = 0
				startCap = if chain.entrance
					then 0
					elseif chain.extStart > 0 then chain.extStart
					else capLength
			else
				lo = math.max(0, run.lo - roundLength)
				startCap = run.lo - lo
			end
			local hi, endCap
			if run.hi >= endNode - END_EPS then
				hi = total
				endCap = if chain.extEnd > 0 then chain.extEnd else capLength
			else
				hi = math.min(total, run.hi + roundLength)
				endCap = hi - run.hi
			end
			if startCap <= 0 and not (chain.entrance and lo == 0) then
				startCap = capLength
			end
			if endCap <= 0 then
				endCap = capLength
			end
			local piece: Piece = {
				chain = chainIndex,
				lo = lo,
				hi = hi,
				nodeLo = run.lo,
				nodeHi = run.hi,
				startCap = startCap,
				endCap = endCap,
				distLo = run.distLo,
				distHi = run.distHi,
				key = "",
			}
			piece.key = pieceKey(piece)
			table.insert(pieces, piece)
		end
	end
	return pieces
end

-- ------------------------------------------------------------------ 6. ribbon

-- pathgeom.sample_positions: uniform rows plus denser rows inside both caps.
local function sampleRows(network: Network, piece: Piece): { number }
	local lo, hi = piece.lo, piece.hi
	local seen: { [number]: boolean } = {}
	local keys: { number } = {}
	local function add(x: number): ()
		local key = math.round(x * ROW_ROUND)
		if not seen[key] then
			seen[key] = true
			table.insert(keys, key)
		end
	end
	local count = math.max(1, math.ceil((hi - lo) / network.ribbon.sampleSpacing))
	for k = 0, count do
		add(lo + (hi - lo) * k / count)
	end
	local caps = { { lo, lo + piece.startCap }, { hi - piece.endCap, hi } }
	for _, cap in caps do
		local a, b = cap[1], cap[2]
		local m = math.max(1, math.ceil((b - a) / CAP_STEP))
		for k = 0, m do
			add(a + (b - a) * k / m)
		end
	end
	table.sort(keys)
	local rows: { number } = {}
	for _, key in keys do
		local x = key / ROW_ROUND
		if x >= lo - 1e-6 and x <= hi + 1e-6 then
			table.insert(rows, x)
		end
	end
	return rows
end

export type Frame = {
	lo: number,
	hi: number,
	startCap: number,
	endCap: number,
	openStart: boolean,
	openEnd: boolean,
}

-- Reusable buffers for a growing piece: Fill writes the frame and remapped arcs into them instead
-- of allocating, and recomputes only rows first..last (the rest provably never move).
export type Scratch = { frame: Frame, arcs: { number }, first: number, last: number }

local function resetFrame(frame: Frame, piece: Piece): ()
	frame.lo = piece.lo
	frame.hi = piece.hi
	frame.startCap = piece.startCap
	frame.endCap = piece.endCap
	frame.openStart = piece.startCap <= 0
	frame.openEnd = piece.endCap <= 0
end

-- The range, caps and remapped row arcs of a piece at a growth stage (or fully grown), for rows
-- first..last. With `scratch` nothing is allocated.
local function frameFor(
	network: Network,
	piece: Piece,
	rows: { number },
	growth: Growth?,
	scratch: Scratch?
): (Frame, { number }, number, number)
	local frame: Frame = if scratch ~= nil
		then scratch.frame
		else {
			lo = 0,
			hi = 0,
			startCap = 0,
			endCap = 0,
			openStart = false,
			openEnd = false,
		}
	resetFrame(frame, piece)
	local first = if scratch ~= nil then scratch.first else 1
	local last = if scratch ~= nil then scratch.last else #rows
	if growth == nil or growth.progress >= 1 then
		return frame, rows, first, last
	end
	local p = math.max(growth.progress, 0)
	local anchor = math.clamp(growth.anchor, piece.lo, piece.hi)
	local arcs: { number } = if scratch ~= nil then scratch.arcs else table.create(#rows)
	if growth.towardHigh then
		frame.hi = anchor + (piece.hi - anchor) * p
		frame.endCap = network.ribbon.capLength
		frame.openEnd = false
		for index = first, last do
			local s = rows[index]
			arcs[index] = if s > anchor then anchor + (s - anchor) * p else s
		end
	else
		frame.lo = anchor - (anchor - piece.lo) * p
		frame.startCap = network.ribbon.capLength
		frame.openStart = false
		for index = first, last do
			local s = rows[index]
			arcs[index] = if s < anchor then anchor - (anchor - s) * p else s
		end
	end
	return frame, arcs, first, last
end

-- The widest half-width a section can reach (jitter up, full flare).
local function widestHalfWidth(network: Network): number
	local ribbon = network.ribbon
	return ribbon.meshWidthFactor
		* (network.width + math.abs(network.jitter) * WIDTH_WAVE_GAIN)
		/ 2
		* (1 + math.max(ribbon.flare, 0))
end

-- Buffers for growing `piece`. A row on the fixed side of the anchor keeps its arc, and once it
-- is further than any cap plus the tip fade from the moving end its cap and fade terms are 1 at
-- every stage, so it is written once when the piece is added and skipped from then on.
function PathRibbon.NewScratch(
	network: Network,
	piece: Piece,
	rows: { number },
	growth: Growth
): Scratch
	local reach = math.max(network.ribbon.capLength, piece.startCap, piece.endCap)
		+ TIP_FADE * FADE_V * 2 * widestHalfWidth(network)
	local first, last = 1, #rows
	if growth.towardHigh then
		while first < last and rows[first] <= growth.anchor - reach do
			first += 1
		end
	else
		while last > first and rows[last] >= growth.anchor + reach do
			last -= 1
		end
	end
	return {
		frame = {
			lo = 0,
			hi = 0,
			startCap = 0,
			endCap = 0,
			openStart = false,
			openEnd = false,
		},
		arcs = table.create(#rows, 0),
		first = first,
		last = last,
	}
end

function PathRibbon.LayerHeight(network: Network, layer: number): number
	return network.thickness + layer * network.ribbon.layerLift
end

-- One row's centre, unit normal (left of travel) and the outline and inner half-widths with
-- the inner v, exactly pathgeom.ribbon's per-row body.
local function section(
	network: Network,
	chain: Chain,
	frame: Frame,
	s: number
): (number, number, number, number, number, number, number)
	local final = chain.final
	local px, pz = PathRibbon.CurvePoint(final, s)
	local tx, tz = PathRibbon.CurveTangent(final, s, SECTION_TANGENT_H)
	local nx, nz = -tz, tx
	local hw = network.ribbon.meshWidthFactor * widthAt(network, chain, s - chain.extStart) / 2
	local flare = 1
	local gain = network.ribbon.flare
	if chain.joinStart then
		flare = math.max(flare, 1 + gain * smoothstep(1 - (s - chain.extStart) / FLARE_LENGTH))
	end
	if chain.joinEnd then
		flare = math.max(
			flare,
			1 + gain * smoothstep(1 - ((final.total - chain.extEnd) - s) / FLARE_LENGTH)
		)
	end
	local cap = 1
	if not frame.openStart then
		local x0 = (s - frame.lo) / frame.startCap
		if x0 < 1 then
			cap = math.min(cap, math.sqrt(math.max(0, 1 - (1 - x0) ^ 2)))
		end
	end
	if not frame.openEnd then
		local x1 = (frame.hi - s) / frame.endCap
		if x1 < 1 then
			cap = math.min(cap, math.sqrt(math.max(0, 1 - (1 - x1) ^ 2)))
		end
	end
	local h = hw * flare * math.max(cap, MIN_CAP_SCALE)
	-- The fade band keeps a constant world width inside each edge, so flares keep the same soft
	-- edge; within one fade width of the outline or the tip the inner columns slide to the
	-- centre and their v into the band, so a narrowing tip fades out instead of outlining.
	local fade = FADE_V * 2 * hw
	local k = math.min(1, h / fade)
	if not frame.openStart then
		k = math.min(k, (s - frame.lo) / (TIP_FADE * fade))
	end
	if not frame.openEnd then
		k = math.min(k, (frame.hi - s) / (TIP_FADE * fade))
	end
	local inner = math.max(0, h - fade) * k
	return px, pz, nx, nz, h, inner, FADE_V * k
end

-- Writes positions and uvs for the rows of `piece` (at `growth`, when given) into the arrays in
-- place: every row, or only scratch.first..scratch.last with `scratch`, allocating nothing then.
function PathRibbon.Fill(
	network: Network,
	piece: Piece,
	rows: { number },
	growth: Growth?,
	positions: { number },
	uvs: { number },
	scratch: Scratch?
): ()
	local chain = network.chains[piece.chain]
	local y = PathRibbon.LayerHeight(network, chain.layer)
	local frame, arcs, first, last = frameFor(network, piece, rows, growth, scratch)
	local textureLength = network.ribbon.textureLength
	for index = first, last do
		local s = arcs[index]
		local px, pz, nx, nz, h, inner, fadeV = section(network, chain, frame, s)
		local u = s / textureLength + chain.uOffset
		local base = (index - 1) * COLUMNS
		for column = 1, COLUMNS do
			local offset = if column == 1
				then h
				elseif column == 2 then inner
				elseif column == 3 then -inner
				else -h
			local v = if column == 1
				then 0
				elseif column == 2 then fadeV
				elseif column == 3 then 1 - fadeV
				else 1
			local vertex = base + column - 1
			positions[vertex * 3 + 1] = px + nx * offset
			positions[vertex * 3 + 2] = y
			positions[vertex * 3 + 3] = pz + nz * offset
			uvs[vertex * 2 + 1] = u
			uvs[vertex * 2 + 2] = v
		end
	end
end

function PathRibbon.Rows(network: Network, piece: Piece): { number }
	return sampleRows(network, piece)
end

function PathRibbon.TriangleCount(rows: number): number
	return math.max(rows - 1, 0) * (COLUMNS - 1) * 2
end

function PathRibbon.VertexCount(rows: number): number
	return rows * COLUMNS
end

-- Strip indices for `rows` rows: 1-based vertex indices, three per triangle, CCW seen from +Y.
function PathRibbon.Triangles(rows: number): { number }
	local triangles: { number } = table.create(PathRibbon.TriangleCount(rows) * 3)
	for i = 0, rows - 2 do
		for j = 0, COLUMNS - 2 do
			local l0, r0 = COLUMNS * i + j + 1, COLUMNS * i + j + 2
			local l1, r1 = l0 + COLUMNS, r0 + COLUMNS
			table.insert(triangles, l0)
			table.insert(triangles, l1)
			table.insert(triangles, r0)
			table.insert(triangles, r0)
			table.insert(triangles, l1)
			table.insert(triangles, r1)
		end
	end
	return triangles
end

function PathRibbon.Mesh(network: Network, piece: Piece, growth: Growth?): MeshData
	local rows = sampleRows(network, piece)
	local positions: { number } = table.create(#rows * COLUMNS * 3)
	local uvs: { number } = table.create(#rows * COLUMNS * 2)
	PathRibbon.Fill(network, piece, rows, growth, positions, uvs)
	return {
		rows = #rows,
		positions = positions,
		uvs = uvs,
		triangles = PathRibbon.Triangles(#rows),
	}
end

-- Beam fallback knots every `spacing` of arc from the piece start, plus the piece ends and the
-- inner end of each cap (so a beam tapers only over its cap): centre, unit tangent and full
-- drawn width, from the same section the ribbon uses.
export type Knot = { x: number, z: number, tx: number, tz: number, width: number, arc: number }

function PathRibbon.Knots(network: Network, piece: Piece, spacing: number): { Knot }
	local chain = network.chains[piece.chain]
	local frame = frameFor(network, piece, {}, nil)
	local step = math.max(spacing, DEDUPE_EPS)
	local arcs: { number } = { piece.lo, piece.hi }
	for k = 1, math.ceil((piece.hi - piece.lo) / step) - 1 do
		table.insert(arcs, piece.lo + k * step)
	end
	for _, capEnd in { piece.lo + piece.startCap, piece.hi - piece.endCap } do
		if capEnd > piece.lo and capEnd < piece.hi then
			table.insert(arcs, capEnd)
		end
	end
	table.sort(arcs)
	local knots: { Knot } = {}
	for index, s in arcs do
		local last = knots[#knots]
		local isEnd = index == #arcs
		if last ~= nil and s - last.arc < DEDUPE_EPS then
			if not isEnd then
				continue
			end
			table.remove(knots)
		end
		local px, pz, nx, nz, h = section(network, chain, frame, s)
		table.insert(knots, { x = px, z = pz, tx = nz, tz = -nx, width = 2 * h, arc = s })
	end
	return knots
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

-- Largest |x| or |z| any drawn vertex can reach: every final curve point plus the widest
-- possible half-width (jitter up, full flare).
function PathRibbon.Extent(network: Network): number
	local widest = widestHalfWidth(network)
	local extent = 0
	for _, chain in network.chains do
		for _, p in chain.final.p do
			extent = math.max(extent, math.abs(p[1]), math.abs(p[2]))
		end
	end
	return extent + widest
end

return PathRibbon
