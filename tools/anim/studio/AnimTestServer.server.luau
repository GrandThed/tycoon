--!strict
-- Studio test only (animtest.project.json, never a shipped place): stands the rig uploaded by
-- `animate.py studio` in front of the hub spawn, at its crowd kind's height, turned to face the
-- spawn. AnimTestClient plays the clips, because Bone.Transform does not replicate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local data = require(ReplicatedStorage:WaitForChild("AnimTestData")) :: any
local AnimRig = require(ReplicatedStorage:WaitForChild("AnimTestLib"):WaitForChild("AnimRig"))

local NAME = "AnimTest"
-- A fresh player looks down -Z from the spawn, so the rig stands there, facing back at the spawn.
local DISTANCE = 22

local spawnLocation = Workspace:WaitForChild("Spawn", 30)
local model = AnimRig.Load(data.assetId, NAME, "AnimTest")
if not model or not spawnLocation then
	return
end

model.Name = NAME
model.Parent = Workspace
AnimRig.Describe(model, "AnimTest")
AnimRig.Record(model, data.name)
local scale = AnimRig.Prepare(model, data.height)
model:PivotTo(model:GetPivot() + Vector3.new(0, 0, -DISTANCE))

model:SetAttribute("AnimScale", scale)
model:SetAttribute("Ready", true)
print(
	`[AnimTest] standing {DISTANCE} studs in front of the spawn, {data.height} studs tall (x{scale})`
)
