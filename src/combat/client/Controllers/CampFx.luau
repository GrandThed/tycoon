--!strict
-- The living road's camp cues (docs/INTERFACES.md "L1b contracts — the living road" ->
-- Client), kept out of CombatFxController and CrowdRenderer, which are near the compile gate's
-- local budget. CombatFxController hands it the two new `camp` events; nothing here reads a
-- remote, decides a wake or touches a body's pose.
--
--  * `alert` (L1b-21): a group woke. A "!" stands over each of its bodies for
--    Theme.COMBAT_ALERT_SECONDS, its foot Theme.COMBAT_ALERT_STUDS above the head. It hangs on
--    the body's head part (CrowdRenderer.GetHead), so it follows a sitter standing up. Sized in
--    studs plus pixels: it grows near and keeps a floor of pixels far away, so it reads at 60
--    studs on a landscape phone. Always on top, because raiders see through the palisade and
--    the mark is the player's only word that they did. A body not drawn is skipped; a mark
--    whose body dies, leaves or is handed to another id goes at once.
--  * `checkpoint` (L1b-18): "Checkpoint" for Theme.COMBAT_CHECKPOINT_NOTICE_SECONDS, through the
--    host's notice handler (CombatHud.ShowNotice under the wallet, in the mission HUD).
--
-- The marks are pooled BillboardGuis (a wake is a handful of bodies; a party may wake several
-- groups at once). The pop is motion and is skipped where Theme.reducedMotion says so (every
-- touch device); the fade is not motion and always runs. No sound: combat has none.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local CrowdRenderer = require(script.Parent:WaitForChild("CrowdRenderer"))

type Mark = {
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	-- The body it stands over: the crowd id and the head part it was hung on (a pooled body
	-- handed to another id keeps its head, so both are checked).
	id: number,
	head: BasePart?,
	-- os.clock() it showed up.
	since: number,
}

local CHECKPOINT_TEXT = "✓ Checkpoint"
local ALERT_TEXT = "!"
-- The pop's overshoot (the standard ease-out-back constant: about 10% past full size).
local BACK_OVERSHOOT = 1.70158

local marks: { Mark } = {}
local free: { Mark } = {}
local all: { Mark } = {}
local state = {
	connection = nil :: RBXScriptConnection?,
	notice = nil :: ((text: string, seconds: number) -> ())?,
}

local function build(playerGui: Instance): Mark
	local gui = Create("BillboardGui", {
		Name = "CampAlert",
		Active = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		MaxDistance = Theme.COMBAT_ALERT_MAX_DISTANCE,
		Size = UDim2.new(
			Theme.COMBAT_ALERT_WIDTH_STUDS,
			Theme.COMBAT_ALERT_WIDTH_PX,
			Theme.COMBAT_ALERT_HEIGHT_STUDS,
			Theme.COMBAT_ALERT_HEIGHT_PX
		),
		-- Its foot, not its middle, at the offset point: the mark stands on the head's air.
		SizeOffset = Vector2.new(0, 0.5),
		Enabled = false,
		Parent = playerGui,
	}) :: BillboardGui
	local label = Create("TextLabel", {
		Name = "Mark",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextScaled = true,
		TextColor3 = Theme.COMBAT_ALERT_COLOR,
		Text = ALERT_TEXT,
		Parent = gui,
	}) :: TextLabel
	local stroke = Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.COMBAT_ALERT_STROKE,
		Parent = label,
	}) :: UIStroke
	local mark: Mark = {
		gui = gui,
		label = label,
		stroke = stroke,
		scale = Create("UIScale", { Parent = label }) :: UIScale,
		id = 0,
		head = nil,
		since = 0,
	}
	table.insert(all, mark)
	return mark
end

local function give(index: number): ()
	local mark = marks[index]
	marks[index] = marks[#marks]
	marks[#marks] = nil
	-- Disabled, it draws nothing; its Adornee is set again when it is next taken.
	mark.gui.Enabled = false
	mark.head = nil
	mark.id = 0
	table.insert(free, mark)
end

-- One frame of every mark: the pop, the fade, and the end (its time, or its body's).
local function step(): ()
	if #marks == 0 then
		return
	end
	local now = os.clock()
	local lasts = Theme.COMBAT_ALERT_SECONDS
	local fade = math.max(Theme.COMBAT_ALERT_FADE_SECONDS, 1e-3)
	local pop = math.max(Theme.COMBAT_ALERT_POP_SECONDS, 1e-3)
	for index = #marks, 1, -1 do
		local mark = marks[index]
		local age = now - mark.since
		if age >= lasts or CrowdRenderer.GetHead(mark.id) ~= mark.head then
			give(index)
			continue
		end
		local seen = math.clamp((lasts - age) / fade, 0, 1)
		local transparency = 1 - seen
		if mark.label.TextTransparency ~= transparency then
			mark.label.TextTransparency = transparency
			mark.stroke.Transparency = transparency
		end
		if not Theme.reducedMotion and mark.scale.Scale ~= 1 then
			-- Out a little past full size and back (an ease-out-back): a pop that reads "now".
			local u = math.min(age / pop, 1)
			local back = u - 1
			local eased = 1
				+ (BACK_OVERSHOOT + 1) * back * back * back
				+ BACK_OVERSHOOT * back * back
			local from = Theme.COMBAT_ALERT_POP_FROM
			mark.scale.Scale = if u >= 1 then 1 else from + (1 - from) * eased
		end
	end
end

local CampFx = {}

-- `ids`: the crowd ids of the group that woke, as the server sent them (read defensively).
function CampFx.Alert(ids: any): ()
	if typeof(ids) ~= "table" then
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	if state.connection == nil then
		state.connection = RunService.Heartbeat:Connect(step)
	end
	local now = os.clock()
	local rise = Theme.COMBAT_ALERT_STUDS
	for _, id in ids :: { any } do
		if typeof(id) ~= "number" then
			continue
		end
		local head = CrowdRenderer.GetHead(id)
		if head == nil then
			continue
		end
		-- A group that wakes again restarts its body's mark rather than stacking a second.
		local mark: Mark? = nil
		for _, live in marks do
			if live.id == id then
				mark = live
				break
			end
		end
		if mark == nil then
			local made = table.remove(free) or build(playerGui)
			table.insert(marks, made)
			mark = made
		end
		local shown = mark :: Mark
		shown.id = id
		shown.head = head
		shown.since = now
		shown.gui.Adornee = head
		shown.gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.5 + rise, 0)
		shown.label.TextTransparency = 0
		shown.stroke.Transparency = 0
		shown.scale.Scale = if Theme.reducedMotion then 1 else Theme.COMBAT_ALERT_POP_FROM
		shown.gui.Enabled = true
	end
end

-- A checkpoint reached: the host's notice says so.
function CampFx.Checkpoint(): ()
	local notice = state.notice
	if notice ~= nil then
		notice(CHECKPOINT_TEXT, Theme.COMBAT_CHECKPOINT_NOTICE_SECONDS)
	end
end

-- The host's notice line (the mission HUD's, under the wallet). nil = no notice is shown.
function CampFx.SetNoticeHandler(handler: ((text: string, seconds: number) -> ())?): ()
	state.notice = handler
end

function CampFx.Destroy(): ()
	local connection = state.connection
	if connection ~= nil then
		connection:Disconnect()
		state.connection = nil
	end
	state.notice = nil
	for _, mark in all do
		mark.gui:Destroy()
	end
	table.clear(all)
	table.clear(marks)
	table.clear(free)
end

return CampFx
