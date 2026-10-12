--!strict
-- ThreatFx child: the parts every enemy tell and projectile is drawn with. They are pooled
-- under one Workspace folder and moved with one Workspace:BulkMoveTo a frame, whichever
-- visual queued them. A part comes out hidden and neon in the colour asked for; nothing here
-- collides, answers a query or casts a shadow, so the world's own rays never see a tell.
--
-- The pool is never trimmed: its size is the most parts one moment ever needed (the `fight`
-- set peaks around 250), and a part destroyed while still in the frame's move queue would
-- break the batched move.

local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local FOLDER_NAME = "RangeThreatFx"

local folder: Folder? = nil
local free: { Part } = {}
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local moveCount = 0

local Pool = {}

-- Called once from ThreatFx.Start (range only).
function Pool.Start(): ()
	if folder ~= nil then
		return
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
end

function Pool.IsReady(): boolean
	return folder ~= nil
end

local function newPart(): Part
	local part = Instance.new("Part")
	part.Name = "ThreatFx"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	part.Parent = folder
	return part
end

function Pool.Take(shape: Enum.PartType, color: Color3): Part
	local part: Part = table.remove(free) or newPart()
	part.Shape = shape
	part.Color = color
	return part
end

function Pool.Give(part: Part): ()
	part.Transparency = 1
	table.insert(free, part)
end

-- The height, in studs above its surface, of the top face of the flat mark in `slot` (0 = the
-- lowest). Marks that can overlap each take a slot of their own, so no two top faces share a
-- height and none fights another for the same pixels; they are not stacked, only told apart,
-- so the whole set stays close to the floor (Theme, "Flat marks"). Three heights are already
-- taken and are skipped: the top of the lane's and the line's strip and of the elite's wedge,
-- the top of their outline bars, and the top of the lane's two discs.
function Pool.MarkTop(slot: number): number
	local step = Theme.COMBAT_RANGE_MARK_STEP
	local top = Theme.COMBAT_RANGE_MARK_FLOOR + step * slot
	local strip = Theme.COMBAT_RANGE_TELL_LIFT + Theme.COMBAT_RANGE_TELL_THICKNESS / 2
	local bars = Theme.COMBAT_RANGE_TELL_LIFT + Theme.COMBAT_RANGE_TELL_EDGE_HEIGHT / 2
	local discs = strip + Theme.COMBAT_RANGE_TELL_THICKNESS
	-- Lowest first: each skip moves this slot, and every one above it, a step up.
	if top > strip - step / 2 then
		top += step
	end
	if top > bars - step / 2 then
		top += step
	end
	if top > discs - step / 2 then
		top += step
	end
	return top
end

-- Queues a move for this frame's batch.
function Pool.Place(part: BasePart, frame: CFrame): ()
	moveCount += 1
	moveParts[moveCount] = part
	moveFrames[moveCount] = frame
end

-- Writes a transparency only when it changed enough to see.
function Pool.Show(part: BasePart, transparency: number): ()
	if math.abs(part.Transparency - transparency) > 0.01 then
		part.Transparency = transparency
	end
end

-- The frame's one batched move. Entries left over from a longer frame are cleared first, so
-- BulkMoveTo sees exact arrays.
function Pool.Flush(): ()
	for index = #moveParts, moveCount + 1, -1 do
		moveParts[index] = nil
		moveFrames[index] = nil
	end
	if moveCount > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	moveCount = 0
end

function Pool.Destroy(): ()
	table.clear(free)
	table.clear(moveParts)
	table.clear(moveFrames)
	moveCount = 0
	local root = folder
	folder = nil
	if root ~= nil then
		root:Destroy()
	end
end

return Pool
