--!strict
-- Studio bench only (animbench.project.json, never a shipped place): makes the one rig every
-- client clones into the crowd AnimBenchClient times. It comes from the built-in template
-- (ReplicatedStorage.AnimTemplate, written by `animate.py template` from a previous Play's log)
-- when there is one, else from LoadAsset, which also logs the record that template is made from.
-- Sized to a fodder raider, the commonest body in a camp.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local data = require(ReplicatedStorage:WaitForChild("AnimTestData")) :: any
local AnimRig = require(ReplicatedStorage:WaitForChild("AnimTestLib"):WaitForChild("AnimRig"))
local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local ProvingGrounds = require(config:WaitForChild("ProvingGrounds")) :: any

local TAG = "AnimBench"

local spawnLocation = Workspace:WaitForChild("Spawn", 30) :: BasePart?
local template = ReplicatedStorage:FindFirstChild("AnimTemplate")
local source = if template and template:IsA("Model") then "template" else "LoadAsset"
local model: Model? = if template and template:IsA("Model")
	then template:Clone()
	else AnimRig.Load(data.assetId, "AnimBenchRig", TAG)
if not model or not spawnLocation then
	return
end

model.Parent = Workspace
AnimRig.Describe(model, TAG)
if source == "LoadAsset" then
	AnimRig.Record(model, data.name)
end
local height = ProvingGrounds.crowd.kinds.fodder.height
local scale = AnimRig.Prepare(model, height)

model.Name = "AnimBenchRig"
model:SetAttribute("AnimScale", scale)
model:SetAttribute("Source", source)
model:SetAttribute("Origin", spawnLocation.Position * Vector3.new(1, 0, 1))
model:SetAttribute("Bodies", ProvingGrounds.crowd.maxAlive)
model.Parent = ReplicatedStorage
model:SetAttribute("Ready", true)
print(
	`[{TAG}] rig from {source}, {height} studs tall (x{scale}), {ProvingGrounds.crowd.maxAlive} bodies`
)
