--!strict
-- Studio tests only (animtest / animbench places, never shipped): gets the rig `animate.py studio`
-- uploaded, says what it holds, and stands it at a height facing +Z.

local InsertService = game:GetService("InsertService")
local Workspace = game:GetService("Workspace")

local AnimRig = {}

local function describe(model: Instance, tag: string)
	local counts: { [string]: number } = {}
	for _, d in model:GetDescendants() do
		counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
	end
	local parts = {}
	for class, n in counts do
		table.insert(parts, `{class} {n}`)
	end
	table.sort(parts)
	print(`[{tag}] {model.Name}: {table.concat(parts, ", ")}`)
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			local ok, skinned = pcall(function()
				return (d :: any).HasSkinnedMesh
			end)
			print(
				`[{tag}]   MeshPart {d.Name}: skinned {if ok then tostring(skinned) else "?"}, size {d.Size}`
			)
		end
	end
end
AnimRig.Describe = describe

-- A pasted Workspace.<name> wins; LoadAsset from the running game is next; the command-bar paste
-- is the fallback for a Studio that refuses LoadAsset there.
function AnimRig.Load(assetId: number, name: string, tag: string): Model?
	local pasted = Workspace:FindFirstChild(name)
	if pasted and pasted:IsA("Model") then
		return pasted
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if ok then
		return result
	end
	warn(`[{tag}] LoadAsset({assetId}) was refused: {result}`)
	print(
		`[{tag}] Stop the game, paste this line into the command bar, press Enter, then Play again:`
	)
	print(
		`local m = game:GetService("InsertService"):LoadAsset({assetId}) m.Name = "{name}" m.Parent = workspace`
	)
	return nil
end

-- One `[AnimRecord]` line per piece, read back from Studio's log by `animate.py template`, which
-- writes the same instances as a Rojo template (does a built-in file keep the skin?). One line per
-- bone keeps every line short, whatever the skeleton.
function AnimRig.Record(model: Model, name: string)
	local mesh = model:FindFirstChildWhichIsA("MeshPart", true)
	if not mesh then
		warn("[AnimRecord] no MeshPart to record")
		return
	end
	local function cf(c: CFrame): string
		local parts = {}
		for _, v in { c:GetComponents() } do
			table.insert(parts, string.format("%.6f", v))
		end
		return table.concat(parts, ",")
	end
	print(
		`[AnimRecord] mesh {name} {mesh.MeshId} {if mesh.TextureID == ""
			then "-"
			else mesh.TextureID} {string.format(
			"%.6f,%.6f,%.6f",
			mesh.Size.X,
			mesh.Size.Y,
			mesh.Size.Z
		)}`
	)
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			local parent = if d.Parent == mesh
				then "@mesh"
				elseif d.Parent == model then "@model"
				else (d.Parent :: Instance).Name
			print(`[AnimRecord] bone {name} {d.Name} {parent} {cf(d.CFrame)}`)
		end
	end
	print(`[AnimRecord] end {name}`)
end

-- Anchored and sealed, scaled to `height` studs, turned so its front (read off the shoulders,
-- never assumed from the importer) faces +Z, feet on Y 0 at the origin. Returns the scale.
function AnimRig.Prepare(model: Model, height: number): number
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local _, restSize = model:GetBoundingBox()
	local scale = height / restSize.Y
	model:ScaleTo(model:GetScale() * scale)

	local bones: { [string]: Bone } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			bones[d.Name] = d
		end
	end
	-- The right of a body facing f is f x up, so f = up x right.
	local facing = Vector3.new(0, 0, -1)
	local left, right = bones.LeftArm, bones.RightArm
	if left and right then
		local across = (right.WorldPosition - left.WorldPosition) * Vector3.new(1, 0, 1)
		if across.Magnitude > 1e-3 then
			facing = Vector3.new(0, 1, 0):Cross(across.Unit)
		end
	else
		warn(
			"[AnimRig] no LeftArm/RightArm bones: the upload lost its skeleton, so nothing can play"
		)
	end
	local target = Vector3.new(0, 0, 1)
	local turn = math.atan2(facing:Cross(target).Y, facing:Dot(target))
	local pivot = model:GetPivot()
	model:PivotTo(
		CFrame.new(pivot.Position)
			* CFrame.Angles(0, turn, 0)
			* (CFrame.new(-pivot.Position) * pivot)
	)
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(-box.X, size.Y / 2 - box.Y, -box.Z))
	return scale
end

return AnimRig
