--!strict
-- Studio bench only (animbench.project.json): can a camp's worth of skinned raiders play their
-- clips on this machine? Clones the rig AnimBenchServer made into the crowd's body cap
-- (`crowd.maxAlive`), on a grid in front of the spawn, and times a fixed series of phases from a
-- fixed camera, logging one `[AnimBench]` line each (Studio's log is how the lead reads them).
-- Then the camera is handed back and M cycles the modes to look at.
--
-- A quarter of the bodies loop an attack, a quarter idle, half walk a small circle (moved by one
-- BulkMoveTo, as CrowdRenderer moves the real crowd). "lod" poses bodies past NEAR every
-- MID_EVERY frames and past MID every FAR_EVERY frames, staggered, unblended.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local data = require(ReplicatedStorage:WaitForChild("AnimTestData")) :: any
local AnimClips = require(ReplicatedStorage:WaitForChild("AnimTestLib"):WaitForChild("AnimClips"))

local COLUMNS = 16
local SPACING = 8
local FIRST_ROW = 20
local CAMERA_BACK, CAMERA_UP = 12, 14
local PHASE_SECONDS = 8
-- Frames right after a phase change (parenting, first skinning) are not the steady cost.
local WARMUP_SECONDS = 1.5
local NEAR, MID = 35, 70
local MID_EVERY, FAR_EVERY = 3, 10
local CIRCLE_RADIUS, CIRCLE_SPEED = 1.5, 0.8
local CLIP_BY_ROLE = { attack = "attack0_ring", idle = "idle", walk = "walk" }
-- Engine timings some builds expose on Stats; read when they are, left out of the line when not.
local ENGINE_STATS = { "RenderCPUFrameTime", "RenderGPUFrameTime", "HeartbeatTimeMs" }

type Mode = "none" | "full" | "lod"
type Phase = { name: string, share: number, mode: Mode, move: boolean }
local PHASES: { Phase } = {
	{ name = "empty", share = 0, mode = "none", move = false },
	{ name = "standing, not animated", share = 1, mode = "none", move = false },
	{ name = "walkers moving, not animated", share = 1, mode = "none", move = true },
	{ name = "animated, every body every frame", share = 1, mode = "full", move = true },
	{ name = "animated, lod", share = 1, mode = "lod", move = true },
	{ name = "animated, every frame, half the bodies", share = 0.5, mode = "full", move = true },
}
local FREE_MODES: { Mode } = { "lod", "full", "none" }

type Track = { bone: Bone, list: { CFrame } }
type Figure = {
	model: Model,
	part: BasePart,
	home: Vector3,
	-- The part's frame at home, so a walk turns the mesh about the body's spot, keeping whatever
	-- turn the importer gave it.
	rest: CFrame,
	walks: boolean,
	clip: AnimClips.Clip,
	tracks: { Track },
	offset: number,
	slot: number,
}

local rig = ReplicatedStorage:WaitForChild("AnimBenchRig") :: Model
while not rig:GetAttribute("Ready") do
	rig:GetAttributeChangedSignal("Ready"):Wait()
end
local scale = rig:GetAttribute("AnimScale") :: number
local origin = rig:GetAttribute("Origin") :: Vector3
local bodies = rig:GetAttribute("Bodies") :: number

local clipBySlot: { [string]: AnimClips.Clip } = {}
for _, clip in AnimClips.Decode(data, scale) do
	clipBySlot[clip.slot] = clip
end

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0, 44)
label.BackgroundTransparency = 0.3
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.TextColor3 = Color3.new(1, 1, 1)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
local screen = Instance.new("ScreenGui")
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
label.Parent = screen
screen.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
label.Text = "Animation bench: building the crowd..."

local folder = Instance.new("Folder")
folder.Name = "AnimBench"
folder.Parent = Workspace

local figures: { Figure } = {}
for n = 1, bodies do
	local model = rig:Clone()
	local part = model:FindFirstChildWhichIsA("MeshPart", true) :: BasePart
	local row, column = (n - 1) // COLUMNS, (n - 1) % COLUMNS
	local home = origin
		+ Vector3.new((column - (COLUMNS - 1) / 2) * SPACING, 0, -(FIRST_ROW + row * SPACING))
	local role = if n % 4 == 0 then "attack" elseif n % 4 == 1 then "idle" else "walk"
	local clip = clipBySlot[CLIP_BY_ROLE[role]]
	local tracks: { Track } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			local list = clip.poses[d.Name]
			if list then
				table.insert(tracks, { bone = d, list = list })
			end
		end
	end
	model:PivotTo(model:GetPivot() + home)
	table.insert(figures, {
		model = model,
		part = part,
		home = home,
		rest = part.CFrame - home,
		walks = role == "walk",
		clip = clip,
		tracks = tracks,
		offset = (n * 0.37) % clip.length,
		slot = n,
	})
	if n % 20 == 0 then
		task.wait()
	end
end

local active: { Figure } = {}
local walkers: { BasePart } = {}
local walkerFigures: { Figure } = {}
local function activate(share: number)
	table.clear(active)
	table.clear(walkers)
	table.clear(walkerFigures)
	for n, figure in figures do
		-- Spread a share evenly over the grid rather than taking its front rows.
		local on = math.floor(n * share) ~= math.floor((n - 1) * share)
		figure.model.Parent = if on then folder else nil
		if on then
			table.insert(active, figure)
			if figure.walks then
				table.insert(walkers, figure.part)
				table.insert(walkerFigures, figure)
			end
		end
	end
end

local frame = 0
local frameCFrames: { CFrame } = {}
local function step(mode: Mode, move: boolean, now: number): number
	frame += 1
	if move then
		table.clear(frameCFrames)
		for k, figure in walkerFigures do
			local angle = now * CIRCLE_SPEED + figure.slot
			local at = figure.home
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * CIRCLE_RADIUS
			-- Round the circle counter-clockwise, facing along it: a body at rest faces +Z, and a
			-- turn of -angle about Y points +Z along the tangent (-sin, 0, cos).
			frameCFrames[k] = CFrame.new(at) * CFrame.Angles(0, -angle, 0) * figure.rest
		end
		Workspace:BulkMoveTo(walkers, frameCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if mode == "none" then
		return 0
	end
	local camera = (Workspace.CurrentCamera :: Camera).CFrame.Position
	local posed = 0
	for _, figure in active do
		local every, smooth = 1, true
		if mode == "lod" then
			local distance = (figure.home - camera).Magnitude
			if distance > MID then
				every, smooth = FAR_EVERY, false
			elseif distance > NEAR then
				every, smooth = MID_EVERY, false
			end
		end
		if (frame + figure.slot) % every == 0 then
			local clip = figure.clip
			local i, a = AnimClips.At(clip, (now + figure.offset) % clip.length)
			if not smooth then
				a = 0
			end
			for _, track in figure.tracks do
				track.bone.Transform = AnimClips.Sample(clip, track.list, i, a)
			end
			posed += #figure.tracks
		end
	end
	return posed
end

local function engineStat(name: string): number?
	local ok, value = pcall(function()
		return (Stats :: any)[name]
	end)
	return if ok and type(value) == "number" then value else nil
end

local function summary(samples: { number }): (number, number)
	if #samples == 0 then
		return 0, 0
	end
	local sorted = table.clone(samples)
	table.sort(sorted)
	local sum = 0
	for _, v in sorted do
		sum += v
	end
	return sum / #sorted, sorted[math.max(1, math.ceil(#sorted * 0.95))]
end

local camera = Workspace.CurrentCamera :: Camera
local centre = origin
	+ Vector3.new(0, 0, -(FIRST_ROW + (math.ceil(bodies / COLUMNS) - 1) * SPACING / 2))
local benchView = CFrame.lookAt(origin + Vector3.new(0, CAMERA_UP, CAMERA_BACK), centre)

local quality = UserSettings():GetService("UserGameSettings").SavedQualityLevel
print(
	`[AnimBench] source {rig:GetAttribute("Source")}, {bodies} bodies, {#figures[1].tracks} animated bones each, graphics {quality}, camera fixed`
)

for index, phase in PHASES do
	activate(phase.share)
	local frames, work, posedSum = {}, {}, 0
	local engine: { [string]: { number } } = {}
	local started = os.clock()
	while os.clock() - started < PHASE_SECONDS do
		local dt = RunService.PreRender:Wait()
		-- Every frame, so a late character spawn cannot take the camera back mid-phase.
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = benchView
		local t0 = os.clock()
		local posed = step(phase.mode, phase.move, os.clock())
		local spent = os.clock() - t0
		local left = PHASE_SECONDS - (os.clock() - started)
		label.Text = string.format(
			"Animation bench %d/%d: %s  (%.0f s, hands off)",
			index,
			#PHASES,
			phase.name,
			left
		)
		if os.clock() - started >= WARMUP_SECONDS then
			table.insert(frames, dt * 1000)
			table.insert(work, spent * 1000)
			posedSum += posed
			for _, name in ENGINE_STATS do
				local v = engineStat(name)
				if v then
					engine[name] = engine[name] or {}
					table.insert(engine[name], v)
				end
			end
		end
	end
	local frameMean, frameP95 = summary(frames)
	local workMean, workP95 = summary(work)
	local extra = {}
	for _, name in ENGINE_STATS do
		if engine[name] then
			local m, p = summary(engine[name])
			table.insert(extra, string.format("%s %.2f/%.2f", name, m, p))
		end
	end
	print(
		string.format(
			"[AnimBench] %d/%d %s: %d bodies (%d walking), %.0f bones/frame; frame %.2f ms mean, %.2f p95 (%.0f fps); script %.3f ms mean, %.3f p95%s",
			index,
			#PHASES,
			phase.name,
			#active,
			#walkers,
			posedSum / math.max(#frames, 1),
			frameMean,
			frameP95,
			if frameMean > 0 then 1000 / frameMean else 0,
			workMean,
			workP95,
			if #extra > 0 then "; " .. table.concat(extra, ", ") else ""
		)
	)
end
print("[AnimBench] DONE")

camera.CameraType = Enum.CameraType.Custom
activate(1)
local freeIndex = 1
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.M then
		freeIndex = freeIndex % #FREE_MODES + 1
	end
end)
local lastFrames: { number } = {}
RunService.PreRender:Connect(function(dt)
	local mode = FREE_MODES[freeIndex]
	step(mode, true, os.clock())
	table.insert(lastFrames, dt * 1000)
	if #lastFrames > 60 then
		table.remove(lastFrames, 1)
	end
	local mean = summary(lastFrames)
	label.Text = string.format(
		"Bench done. Mode %s (M to change), %d bodies, %.0f fps",
		mode,
		#active,
		if mean > 0 then 1000 / mean else 0
	)
end)
