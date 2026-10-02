--!strict
-- AbilityFx child: everything that owns instances. The pools (parts, wedges, beams, emitters,
-- trails, lights) under one Workspace folder, the kit a visual borrows from them, the drawing
-- helpers, the batched move queue (one Workspace:BulkMoveTo per frame) and the world rays that
-- must skip that folder.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Shared = require(script.Parent:WaitForChild("Shared"))

type Cast = Shared.Cast
type BeamHandle = Shared.BeamHandle
type EmitterHandle = Shared.EmitterHandle
type TrailHandle = Shared.TrailHandle
type LightHandle = Shared.LightHandle
type Kit = Shared.Kit
type EmitterStyle = Shared.EmitterStyle
type Placed = Shared.Placed

local lowEnd = Shared.lowEnd
local EPSILON = Shared.EPSILON
local TAU = Shared.TAU
local UP = Shared.UP
local STAND_UP = Shared.STAND_UP
local FLOOR_PROBE_UP = Shared.FLOOR_PROBE_UP
local FLOOR_PROBE_DOWN = Shared.FLOOR_PROBE_DOWN
local LIFT = Shared.LIFT
local MIN_RADIUS = Shared.MIN_RADIUS
local MIN_SIZE = Shared.MIN_SIZE
local JOINT_OVERLAP = Shared.JOINT_OVERLAP
local RING_WIDTH = Shared.RING_WIDTH
local RING_HEIGHT = Shared.RING_HEIGHT
local DISC_THICKNESS = Shared.DISC_THICKNESS
local DUST_RISE = Shared.DUST_RISE
local around = Shared.around
local tangentOf = Shared.tangentOf
local barFrame = Shared.barFrame
local rootHeightOf = Shared.rootHeightOf

local FOLDER_NAME = "RangeAbilityFx"
local PART_POOL_MAX = 500
local WEDGE_POOL_MAX = 80
local BEAM_POOL_MAX = 48
local EMITTER_POOL_MAX = 32
local TRAIL_POOL_MAX = 6
local LIGHT_POOL_MAX = 16
local SECTOR_THICKNESS = 0.05
local TRAIL_TRANSPARENCY = NumberSequence.new(0.15, 1)
local TRAIL_TAPER = NumberSequence.new(1, 0.3)
local folder: Folder? = nil
local anchor: Part? = nil
local partPool: { Part } = {}
local wedgePool: { WedgePart } = {}
local beamPool: { BeamHandle } = {}
local emitterPool: { EmitterHandle } = {}
local trailPool: { TrailHandle } = {}
local lightPool: { LightHandle } = {}
-- Parts past the pool cap wait here for one BulkMoveTo, which may still hold a move for them.
local doomed: { BasePart } = {}
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

-- Skips every character and this module's folder. Crowd bodies and Feedback's fx parts have
-- CanQuery off, so the world is all that is left.
local function worldParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = {}
	local root = folder
	if root ~= nil then
		table.insert(ignored, root)
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignored, character)
		end
	end
	params.FilterDescendantsInstances = ignored
	params.IgnoreWater = true
	return params
end

local function rayEnd(from: Vector3, direction: Vector3, range: number): Vector3
	local hit = Workspace:Raycast(from, direction * range, worldParams())
	return if hit ~= nil then hit.Position else from + direction * range
end

local function floorBelow(position: Vector3, fallbackY: number): Vector3
	local hit = Workspace:Raycast(
		position + UP * FLOOR_PROBE_UP,
		Vector3.new(0, -FLOOR_PROBE_DOWN, 0),
		worldParams()
	)
	if hit ~= nil then
		return hit.Position
	end
	return Vector3.new(position.X, fallbackY, position.Z)
end

-- The cast's ground point (zones, landing, Earthquake's floor centre), lifted off the floor. The
-- server always sends one for these; the probe below the cast root covers an older server.
local function groundOf(cast: Cast): Vector3
	local target = cast.target
	local ground = if target ~= nil
		then target
		else floorBelow(cast.origin, cast.origin.Y - rootHeightOf(cast.userId))
	return ground + UP * LIFT
end

local function newKit(): Kit
	return { parts = {}, beams = {}, emitters = {}, trails = {}, lights = {} }
end

local function newPart(className: string): BasePart
	return Create(className, {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Parent = folder,
	}) :: BasePart
end

-- Every part comes out hidden; the visual's step decides when it shows.
local function takePart(
	kit: Kit,
	shape: Enum.PartType,
	color: Color3,
	material: Enum.Material
): BasePart
	local part = table.remove(partPool) or newPart("Part") :: Part
	part.Shape = shape
	part.Color = color
	part.Material = material
	part.Transparency = 1
	table.insert(kit.parts, part)
	-- Callers keep parts in records typed BasePart (table fields are invariant).
	return part :: BasePart
end

local function takeParts(
	kit: Kit,
	count: number,
	shape: Enum.PartType,
	color: Color3,
	material: Enum.Material
): { BasePart }
	local parts: { BasePart } = {}
	for _ = 1, count do
		table.insert(parts, takePart(kit, shape, color, material))
	end
	return parts
end

local function takeWedge(kit: Kit, color: Color3): BasePart
	local wedge = table.remove(wedgePool) or newPart("WedgePart") :: WedgePart
	wedge.Color = color
	wedge.Material = Enum.Material.Neon
	wedge.Transparency = 1
	table.insert(kit.parts, wedge)
	return wedge :: BasePart
end

local function givePart(part: BasePart): ()
	part.Transparency = 1
	if part:IsA("WedgePart") then
		if #wedgePool < WEDGE_POOL_MAX then
			table.insert(wedgePool, part)
			return
		end
	elseif part:IsA("Part") then
		if #partPool < PART_POOL_MAX then
			table.insert(partPool, part)
			return
		end
	end
	table.insert(doomed, part)
end

local function newAttachment(name: string): Attachment
	return Create("Attachment", { Name = name, Parent = anchor }) :: Attachment
end

-- A camera-facing ribbon between two pooled attachments, fully transparent until shown.
local function takeBeam(kit: Kit, color: Color3, width: number): BeamHandle
	local handle = table.remove(beamPool)
	if handle == nil then
		local a0 = newAttachment("BeamStart")
		local a1 = newAttachment("BeamEnd")
		local beam = Create("Beam", {
			Attachment0 = a0,
			Attachment1 = a1,
			FaceCamera = true,
			LightEmission = 1,
			LightInfluence = 0,
			Segments = 1,
			Enabled = false,
			Parent = anchor,
		}) :: Beam
		handle = { beam = beam, a0 = a0, a1 = a1, shown = 1 }
	end
	local resolved = handle :: BeamHandle
	resolved.beam.Color = ColorSequence.new(color)
	resolved.beam.Width0 = width
	resolved.beam.Width1 = width
	resolved.beam.Transparency = NumberSequence.new(1)
	resolved.shown = 1
	resolved.beam.Enabled = true
	table.insert(kit.beams, resolved)
	return resolved
end

local function giveBeam(handle: BeamHandle): ()
	handle.beam.Enabled = false
	if #beamPool < BEAM_POOL_MAX then
		table.insert(beamPool, handle)
		return
	end
	handle.beam:Destroy()
	handle.a0:Destroy()
	handle.a1:Destroy()
end

local function takeEmitter(kit: Kit, style: EmitterStyle, color: Color3): EmitterHandle
	local now = os.clock()
	local handle: EmitterHandle? = nil
	for index = #emitterPool, 1, -1 do
		if emitterPool[index].readyAt <= now then
			handle = table.remove(emitterPool, index)
			break
		end
	end
	if handle == nil then
		local attachment = newAttachment("Emitter")
		local emitter = Create("ParticleEmitter", {
			Enabled = false,
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 360),
			Rate = 0,
			Parent = attachment,
		}) :: ParticleEmitter
		handle = { attachment = attachment, emitter = emitter, readyAt = 0, lifeMax = 0 }
	end
	local resolved = handle :: EmitterHandle
	local emitter = resolved.emitter
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Texture = style.texture
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = style.lightEmission
	emitter.LightInfluence = style.lightInfluence
	emitter.Size = style.size
	emitter.Transparency = style.transparency
	emitter.Lifetime = style.lifetime
	emitter.Speed = style.speed
	emitter.SpreadAngle = Vector2.new(style.spreadDegrees, style.spreadDegrees)
	emitter.Acceleration = style.acceleration
	emitter.Drag = style.drag
	emitter.RotSpeed = style.rotSpeed
	resolved.lifeMax = style.lifetime.Max
	table.insert(kit.emitters, resolved)
	return resolved
end

local function giveEmitter(handle: EmitterHandle): ()
	handle.emitter.Enabled = false
	handle.readyAt = os.clock() + handle.lifeMax
	if #emitterPool < EMITTER_POOL_MAX then
		table.insert(emitterPool, handle)
		return
	end
	-- Past the cap: let the last particles land before the emitter goes.
	local attachment = handle.attachment
	task.delay(handle.lifeMax, function()
		attachment:Destroy()
	end)
end

local function emitAt(handle: EmitterHandle, frame: CFrame, count: number): ()
	if count <= 0 then
		return
	end
	handle.attachment.WorldCFrame = frame
	handle.emitter:Emit(count)
end

local function setEmitting(handle: EmitterHandle, on: boolean): ()
	if handle.emitter.Enabled ~= on then
		handle.emitter.Enabled = on
	end
end

-- A trail between two attachments this module moves (never parented into a character, so a
-- respawn cannot take pooled instances with it).
local function takeTrail(
	kit: Kit,
	color: Color3,
	lifetime: number,
	centre: Vector3,
	halfWidth: number
): TrailHandle
	local handle = table.remove(trailPool)
	if handle == nil then
		local a0 = newAttachment("TrailTop")
		local a1 = newAttachment("TrailBottom")
		local trail = Create("Trail", {
			Attachment0 = a0,
			Attachment1 = a1,
			FaceCamera = true,
			LightEmission = 1,
			LightInfluence = 0,
			MinLength = 0.05,
			Transparency = TRAIL_TRANSPARENCY,
			WidthScale = TRAIL_TAPER,
			Enabled = false,
			Parent = anchor,
		}) :: Trail
		handle = { trail = trail, a0 = a0, a1 = a1 }
	end
	local resolved = handle :: TrailHandle
	resolved.trail.Color = ColorSequence.new(color)
	resolved.trail.Lifetime = lifetime
	resolved.a0.WorldPosition = centre + UP * halfWidth
	resolved.a1.WorldPosition = centre - UP * halfWidth
	-- Cleared after the move, so no streak runs from wherever the pooled trail last was.
	resolved.trail:Clear()
	resolved.trail.Enabled = true
	table.insert(kit.trails, resolved)
	return resolved
end

local function layTrail(handle: TrailHandle, centre: Vector3, halfWidth: number): ()
	handle.a0.WorldPosition = centre + UP * halfWidth
	handle.a1.WorldPosition = centre - UP * halfWidth
end

local function giveTrail(handle: TrailHandle): ()
	handle.trail.Enabled = false
	handle.trail:Clear()
	if #trailPool < TRAIL_POOL_MAX then
		table.insert(trailPool, handle)
		return
	end
	handle.trail:Destroy()
	handle.a0:Destroy()
	handle.a1:Destroy()
end

-- Low-end devices get no lights at all (nil), and every caller accepts that.
local function takeLight(kit: Kit, color: Color3, range: number): LightHandle?
	if lowEnd then
		return nil
	end
	local handle = table.remove(lightPool)
	if handle == nil then
		local attachment = newAttachment("Light")
		local light = Create("PointLight", {
			Shadows = false,
			Brightness = 0,
			Parent = attachment,
		}) :: PointLight
		handle = { attachment = attachment, light = light }
	end
	local resolved = handle :: LightHandle
	resolved.light.Color = color
	resolved.light.Range = range
	resolved.light.Brightness = 0
	resolved.light.Enabled = true
	table.insert(kit.lights, resolved)
	return resolved
end

local function lightAt(handle: LightHandle?, position: Vector3, brightness: number): ()
	if handle == nil then
		return
	end
	handle.attachment.WorldPosition = position
	handle.light.Brightness = math.max(brightness, 0)
end

local function giveLight(handle: LightHandle): ()
	handle.light.Brightness = 0
	handle.light.Enabled = false
	if #lightPool < LIGHT_POOL_MAX then
		table.insert(lightPool, handle)
		return
	end
	handle.attachment:Destroy()
end

local function releaseKit(kit: Kit): ()
	for _, part in kit.parts do
		givePart(part)
	end
	for _, handle in kit.beams do
		giveBeam(handle)
	end
	for _, handle in kit.emitters do
		giveEmitter(handle)
	end
	for _, handle in kit.trails do
		giveTrail(handle)
	end
	for _, handle in kit.lights do
		giveLight(handle)
	end
	table.clear(kit.parts)
	table.clear(kit.beams)
	table.clear(kit.emitters)
	table.clear(kit.trails)
	table.clear(kit.lights)
end

local function place(part: BasePart, frame: CFrame): ()
	table.insert(moveParts, part)
	table.insert(moveFrames, frame)
end

-- `base` transparency at full visibility, scaled toward invisible as v falls to 0.
local function visibleAs(base: number, v: number): number
	if v <= 0 then
		return 1
	end
	return 1 - (1 - base) * math.min(v, 1)
end

local function show(part: BasePart, base: number, v: number): ()
	local value = visibleAs(base, v)
	if math.abs(part.Transparency - value) > 1e-3 then
		part.Transparency = value
	end
end

local function showAll(parts: { BasePart }, base: number, v: number): ()
	local value = visibleAs(base, v)
	for _, part in parts do
		if math.abs(part.Transparency - value) > 1e-3 then
			part.Transparency = value
		end
	end
end

local function layBeam(handle: BeamHandle, from: Vector3, to: Vector3): ()
	handle.a0.WorldPosition = from
	handle.a1.WorldPosition = to
end

local function showBeam(handle: BeamHandle, base: number, v: number): ()
	local value = visibleAs(base, v)
	if math.abs(handle.shown - value) > 1e-3 then
		handle.beam.Transparency = NumberSequence.new(value)
		handle.shown = value
	end
end

local function widenBeam(handle: BeamHandle, width: number): ()
	if math.abs(handle.beam.Width0 - width) > 1e-3 then
		handle.beam.Width0 = width
		handle.beam.Width1 = width
	end
end

-- Lays `parts` end to end along the circle of `radius` around `centre` in the plane (u, v), from
-- angle `from` to `to` (radians). The centreline runs on the circle, as Feedback's hitbox rings do,
-- so an outline of radius r is the shape's radius r. Sizes are written only when `resize`.
local function layCircle(
	parts: { BasePart },
	centre: Vector3,
	u: Vector3,
	v: Vector3,
	radius: number,
	from: number,
	to: number,
	width: number,
	height: number,
	resize: boolean
): ()
	local count = #parts
	if count == 0 or math.abs(to - from) < EPSILON then
		return
	end
	local r = math.max(radius, MIN_RADIUS)
	local step = (to - from) / count
	local normal = v:Cross(u)
	local length = 2 * r * math.abs(math.sin(step / 2)) + width * JOINT_OVERLAP
	for index, part in parts do
		local a = from + step * (index - 1)
		local b = a + step
		local pa = centre + (u * math.cos(a) + v * math.sin(a)) * r
		local pb = centre + (u * math.cos(b) + v * math.sin(b)) * r
		if resize then
			part.Size = Vector3.new(width, height, length)
		end
		place(part, CFrame.lookAt((pa + pb) / 2, pb, normal))
	end
end

local function layBar(part: BasePart, a: Vector3, b: Vector3, width: number, up: Vector3): ()
	local frame, length = barFrame(a, b, up)
	part.Size = Vector3.new(width, width, math.max(length, MIN_SIZE))
	place(part, frame)
end

local function layBall(part: BasePart, centre: Vector3, diameter: number): ()
	part.Size = Vector3.one * math.max(diameter, MIN_SIZE)
	place(part, CFrame.new(centre))
end

-- A flat disc of `radius` (a standing Cylinder), placed once.
local function layDisc(part: BasePart, centre: Vector3, radius: number): ()
	part.Size = Vector3.new(DISC_THICKNESS, radius * 2, radius * 2)
	place(part, CFrame.new(centre) * STAND_UP)
end

-- Short radial bars just inside a circle's edge, like a reticle's notches.
local function layNotches(parts: { BasePart }, centre: Vector3, radius: number, length: number): ()
	for index, part in parts do
		local angle = TAU * (index - 1) / #parts + math.pi / 4
		local outer = centre + around(angle) * radius
		local inner = centre + around(angle) * math.max(radius - length, 0)
		local frame, span = barFrame(inner, outer, UP)
		part.Size = Vector3.new(RING_WIDTH, RING_HEIGHT, math.max(span, MIN_SIZE))
		place(part, frame)
	end
end

-- A filled triangle from two wedges (the standard right-triangle split, as Feedback draws its
-- arcs). Sized now; the frames are returned so a caller can move the triangle with the caster.
local function triangle(kit: Kit, a: Vector3, b: Vector3, c: Vector3, color: Color3): { Placed }
	local placed: { Placed } = {}
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Relabel so bc is the longest edge; the split point then lies inside it.
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < EPSILON or bc.Magnitude < EPSILON then
		return placed
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local first = takeWedge(kit, color)
	first.Size = Vector3.new(SECTOR_THICKNESS, height, math.abs(ab:Dot(back)))
	table.insert(placed, { part = first, frame = CFrame.fromMatrix((a + b) / 2, right, up, back) })
	local second = takeWedge(kit, color)
	second.Size = Vector3.new(SECTOR_THICKNESS, height, math.abs(ac:Dot(back)))
	table.insert(
		placed,
		{ part = second, frame = CFrame.fromMatrix((a + c) / 2, -right, up, -back) }
	)
	return placed
end

-- Dust thrown up and out all round a ring (Earthquake rings, Leap Smash landing).
local function dustRing(
	handle: EmitterHandle,
	centre: Vector3,
	radius: number,
	points: number,
	perPoint: number
): ()
	for index = 1, points do
		local outward = around(TAU * (index - 1) / points)
		local rise = (outward + UP * DUST_RISE).Unit
		local frame = CFrame.fromMatrix(
			centre + outward * radius,
			tangentOf(TAU * (index - 1) / points),
			rise
		)
		emitAt(handle, frame, perPoint)
	end
end

local function flushMoves(): ()
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(moveParts)
		table.clear(moveFrames)
	end
	for _, part in doomed do
		part:Destroy()
	end
	table.clear(doomed)
end

-- Called once from AbilityFx.Start (range only): the one Workspace folder everything lives in.
local function start(): ()
	local root = Create("Folder", { Name = FOLDER_NAME, Parent = Workspace }) :: Folder
	folder = root
	-- One invisible part at the origin holds every attachment, so an attachment's position is
	-- its world position and nothing pooled ever lives inside a character.
	anchor = Create("Part", {
		Name = "Anchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.one * MIN_SIZE,
		CFrame = CFrame.identity,
		Parent = root,
	}) :: Part
end

local function isReady(): boolean
	return folder ~= nil
end

local function destroy(): ()
	table.clear(moveParts)
	table.clear(moveFrames)
	table.clear(doomed)
	table.clear(partPool)
	table.clear(wedgePool)
	table.clear(beamPool)
	table.clear(emitterPool)
	table.clear(trailPool)
	table.clear(lightPool)
	local root = folder
	if root ~= nil then
		root:Destroy()
		folder = nil
	end
	anchor = nil
end

return {
	worldParams = worldParams,
	rayEnd = rayEnd,
	floorBelow = floorBelow,
	groundOf = groundOf,
	newKit = newKit,
	takePart = takePart,
	takeParts = takeParts,
	takeWedge = takeWedge,
	takeBeam = takeBeam,
	takeEmitter = takeEmitter,
	emitAt = emitAt,
	setEmitting = setEmitting,
	takeTrail = takeTrail,
	layTrail = layTrail,
	takeLight = takeLight,
	lightAt = lightAt,
	releaseKit = releaseKit,
	place = place,
	visibleAs = visibleAs,
	show = show,
	showAll = showAll,
	layBeam = layBeam,
	showBeam = showBeam,
	widenBeam = widenBeam,
	layCircle = layCircle,
	layBar = layBar,
	layBall = layBall,
	layDisc = layDisc,
	layNotches = layNotches,
	triangle = triangle,
	dustRing = dustRing,
	flushMoves = flushMoves,
	start = start,
	destroy = destroy,
	isReady = isReady,
}
