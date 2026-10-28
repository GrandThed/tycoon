--!strict
-- Studio test only: plays every clip of AnimTestData on the rig AnimTestServer stood in front of
-- the spawn, writing Bone.Transform each frame. ] next clip, [ previous, P stops or resumes cycling,
-- F turns the cross-fade between clips off and on (to compare against the snap).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local data = require(ReplicatedStorage:WaitForChild("AnimTestData")) :: any
local AnimClips = require(ReplicatedStorage:WaitForChild("AnimTestLib"):WaitForChild("AnimClips"))

-- A loop shows for this long; a one-shot plays once and holds its last frame for HOLD.
local LOOP_SECONDS = 3
local HOLD = 0.8
-- How long the label reads HIT after an attack's contact (its windup).
local HIT_SECONDS = 0.15
-- Cross-fade from the last pose into the next clip. Short into an attack, because the fade runs
-- inside its windup (the contact stays on the windup, its first moments are blended); longer into
-- idle, walk and reactions, where nothing is timed.
local FADE_INTO_ATTACK = 0.12
local FADE_OTHERWISE = 0.25

local model = Workspace:WaitForChild("AnimTest") :: Model
while not model:GetAttribute("Ready") do
	model:GetAttributeChangedSignal("Ready"):Wait()
end
local scale = model:GetAttribute("AnimScale") :: number

local bones: { [string]: Bone } = {}
local anchor: BasePart? = nil
for _, d in model:GetDescendants() do
	if d:IsA("Bone") then
		bones[d.Name] = d
	elseif d:IsA("MeshPart") and not anchor then
		anchor = d
	end
end

local clips = AnimClips.Decode(data, scale)

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 0.35
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.TextColor3 = Color3.new(1, 1, 1)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
local board = Instance.new("BillboardGui")
board.Size = UDim2.fromOffset(460, 38)
board.StudsOffsetWorldSpace = Vector3.new(0, data.height * 0.5 + 2, 0)
board.AlwaysOnTop = true
board.Adornee = anchor
label.Parent = board
board.Parent = model

local index = 1
local started = os.clock()
local cycling = true
local fading = true
local fadeFrom: { [Bone]: CFrame } = {}
local fadeSeconds = 0

local function show(i: number)
	index = (i - 1) % #clips + 1
	started = os.clock()
	for _, bone in bones do
		fadeFrom[bone] = bone.Transform
	end
	fadeSeconds = if not fading
		then 0
		elseif clips[index].windup then FADE_INTO_ATTACK
		else FADE_OTHERWISE
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightBracket then
		show(index + 1)
	elseif input.KeyCode == Enum.KeyCode.LeftBracket then
		show(index - 1)
	elseif input.KeyCode == Enum.KeyCode.P then
		cycling = not cycling
	elseif input.KeyCode == Enum.KeyCode.F then
		fading = not fading
	end
end)

RunService.PreRender:Connect(function()
	local clip = clips[index]
	if not clip then
		return
	end
	local shown = if clip.loop then math.max(LOOP_SECONDS, clip.length) else clip.length + HOLD
	local elapsed = os.clock() - started
	if elapsed >= shown then
		-- A paused cycle replays the same clip, and fades into it from its held last frame.
		show(if cycling then index + 1 else index)
		clip = clips[index]
		elapsed = 0
	end
	local t = if clip.loop then elapsed % clip.length else math.min(elapsed, clip.length)
	local i, a = AnimClips.At(clip, t)
	-- Smoothstep weight, so the blend eases out of the old pose and into the new one.
	local w = if fadeSeconds > 0 then math.min(elapsed / fadeSeconds, 1) else 1
	w = w * w * (3 - 2 * w)
	for name, bone in bones do
		local list = clip.poses[name]
		local pose = if list then AnimClips.Sample(clip, list, i, a) else CFrame.identity
		bone.Transform = if w < 1 then (fadeFrom[bone] or CFrame.identity):Lerp(pose, w) else pose
	end
	local hit = clip.windup ~= nil and t >= clip.windup and t < clip.windup + HIT_SECONDS
	label.TextColor3 = if hit then Color3.fromRGB(255, 80, 60) else Color3.new(1, 1, 1)
	label.Text = string.format(
		"%d/%d  %s  (%s)  %.2f s%s%s%s",
		index,
		#clips,
		clip.slot,
		clip.clip,
		t,
		if hit then "  HIT" else "",
		if cycling then "" else "  [paused cycle]",
		if fading then "" else "  [no fade]"
	)
end)

show(1)
