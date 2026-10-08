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
