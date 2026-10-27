--!strict
-- Studio test only (animtest.project.json, never a shipped place): stands the rig uploaded by
-- `animate.py studio` in front of the hub spawn, at its crowd kind's height, turned to face the
-- spawn. AnimTestClient plays the clips, because Bone.Transform does not replicate.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local data = require(ReplicatedStorage:WaitForChild("AnimTestData")) :: any

local NAME = "AnimTest"
-- A fresh player looks down -Z from the spawn, so the rig stands there, facing back at the spawn.
local DISTANCE = 22

local function describe(model: Instance)
	local counts: { [string]: number } = {}
	for _, d in model:GetDescendants() do
		counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
	end
	local parts = {}
	for class, n in counts do
		table.insert(parts, `{class} {n}`)
	end
	table.sort(parts)
	print(`[AnimTest] {data.name} (asset {data.assetId}): {table.concat(parts, ", ")}`)
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			local ok, skinned = pcall(function()
				return (d :: any).HasSkinnedMesh
			end)
			print(
				`[AnimTest]   MeshPart {d.Name}: skinned {if ok then tostring(skinned) else "?"}, size {d.Size}`
			)
		end
	end
end

-- The command-bar paste is the fallback for a Studio that refuses LoadAsset from a running game.
local function load(): Model?
	local pasted = Workspace:FindFirstChild(NAME)
	if pasted and pasted:IsA("Model") then
		return pasted
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(data.assetId)
	end)
	if ok then
		return result
	end
	warn(`[AnimTest] LoadAsset({data.assetId}) was refused: {result}`)
	print(
		"[AnimTest] Stop the game, paste this line into the command bar, press Enter, then Play again:"
	)
	print(
		`local m = game:GetService("InsertService"):LoadAsset({data.assetId}) m.Name = "{NAME}" m.Parent = workspace`
	)
	return nil
end

local spawnLocation = Workspace:WaitForChild("Spawn", 30)
local model = load()
if not model or not spawnLocation then
	return
end

model.Name = NAME
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
	end
end
model.Parent = Workspace
describe(model)

local _, restSize = model:GetBoundingBox()
local scale = data.height / restSize.Y
model:ScaleTo(model:GetScale() * scale)

-- The importer's turn is not assumed: the front is read off the shoulders (right of a body facing
-- f is f x up, so f = up x right).
local bones: { [string]: Bone } = {}
for _, d in model:GetDescendants() do
	if d:IsA("Bone") then
		bones[d.Name] = d
	end
end
local facing = Vector3.new(0, 0, -1)
local left, right = bones.LeftArm, bones.RightArm
if left and right then
	local across = (right.WorldPosition - left.WorldPosition) * Vector3.new(1, 0, 1)
	if across.Magnitude > 1e-3 then
		facing = Vector3.new(0, 1, 0):Cross(across.Unit)
	end
else
	warn("[AnimTest] no LeftArm/RightArm bones: the upload lost its skeleton, so nothing can play")
end
local target = Vector3.new(0, 0, 1)
local turn = math.atan2(facing:Cross(target).Y, facing:Dot(target))
local pivot = model:GetPivot()
model:PivotTo(
	CFrame.new(pivot.Position) * CFrame.Angles(0, turn, 0) * (CFrame.new(-pivot.Position) * pivot)
)

local box, size = model:GetBoundingBox()
model:PivotTo(model:GetPivot() + Vector3.new(-box.X, size.Y / 2 - box.Y, -DISTANCE - box.Z))

model:SetAttribute("AnimScale", scale)
model:SetAttribute("Ready", true)
print(
	`[AnimTest] standing {DISTANCE} studs in front of the spawn, {data.height} studs tall (x{scale})`
)
