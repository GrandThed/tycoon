--!strict
-- What LevelScenery decides, as pure functions (docs/prompts/l4-w2-fix-round.md K7, K8; the L4 W2
-- review, slice 2 s1), so tools/crowd_harness/tests_l4w2_scenery.luau runs the very rules the
-- controller acts on. No Instance, no service, no clock: LevelScenery reads the world and hands
-- the readings in.
--  * Decide: what the server's word (Workspace.Level's `Dress` and `DressHash`) means on this
--    client, and whether the answer may be kept for that word. Nothing is decided before the
--    place has loaded (the dress files and the templates replicate with it), and a nil answer is
--    never kept: the next reading of the same word asks again.
--  * Jobs: the steps of a build, in order (contract 2.3).
--  * Show: the local writes a view makes on the server's Parts. A client that cannot dress a
--    dressed level shows the grey level: every hidden Part, and every invisible wall drawn in the
--    grey level's wall look, so no wall fences a player that he cannot see (K7). Studio's Y grey
--    view is the same picture.
--  * Mood: mood B is on only while the level is dressed here and the body is not in the lobby
--    camp (K8: a member waiting there during a run keeps the lobby's light).
--  * Box and InBox: the lobby camp's flat box, and whether a point stands in it (the server's
--    StageFlow.OutOfBox, flat).
--  * Rgb: an RGB triple 0-255 from a config, or nil.
--  * Crosshair (docs/prompts/l4-w2-fix2.md L3; the fix-diff review's s2): K9 keeps the shoulder
--    camera up through a dressed level's summary and ended, so that its boom stops at the
--    scenery; the crosshair hides there all the same, so none is drawn under the summary card.
--    RUN_OVER is the one list of those phases, CameraController's as well.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local ScenePlan = {}

export type View = "forest" | "grey" | "walls"
-- "none": not dressed, the level as built. "wait": the place has not loaded, nothing is decided.
-- "build": draw `dress`. "fail": the server dressed the level and this client cannot (`reason`).
export type Action = "none" | "wait" | "build" | "fail"
export type Decision = {
	action: Action,
	-- false: the same word is read again the next time it is asked (it is not an answer yet).
	keep: boolean,
	reason: string?,
	dress: Types.LevelDress?,
}
export type Job = {
	kind: "mesh" | "prop" | "fire",
	mesh: Types.LevelDressMesh?,
	prop: Types.LevelDressProp?,
	effect: Types.LevelDressEffect?,
}
-- `folder`: the scenery is parented. `skinned`: the Parts the scenery covers are shown. `walls`:
-- the invisible walls drawn in Studio's red ("debug") or in the grey level's wall look ("grey").
export type Show = { folder: boolean, skinned: boolean, walls: "none" | "debug" | "grey" }
-- A flat box in world studs, and a Part's flat footprint (centre and half extents).
export type Box = { minX: number, maxX: number, minZ: number, maxZ: number }
export type Footprint = { x: number, z: number, hx: number, hz: number }

-- The only dress frame the game reads (world studs) and the only effect kind.
ScenePlan.FRAME = "level"
ScenePlan.FIRE = "fire"
-- The mesh groups in build order: what covers hidden collision first, so the floor is under the
-- player's feet soonest. A group not listed comes after these (its meshes are still built).
ScenePlan.GROUP_ORDER =
	{ "ground", "skin", "camp", "rock", "canopy", "dress", "backdrop" } :: { string }
-- The Expeditions.json look the grey level gives its walls.
ScenePlan.WALL_LOOK = "wall"
-- The run phases (Types.RunPhase) in which the run is over: the summary card, then the wait to
-- leave. Roblox's camera takes over there unless the level is dressed (K9); no crosshair shows.
ScenePlan.RUN_OVER = { summary = true, ended = true } :: { [string]: boolean }

local function isList(value: any): boolean
	return type(value) == "table"
end

local function shown(value: any): string
	return if type(value) == "string" then `"{value}"` else tostring(value)
end

-- The key of the server's word: "" for not dressed. Two readings with one key mean the same.
function ScenePlan.Key(dress: any, hash: any): string
	return if type(dress) == "string" then `{dress}\0{tostring(hash)}` else ""
end

-- What the server's word means here. `dress` and `hash` are the two attributes as read,
-- `loaded` is game:IsLoaded(), `lookup` the dress file by layout (Catalog.GetLevelDress); it is
-- asked only once the place has loaded.
function ScenePlan.Decide(
	dress: any,
	hash: any,
	loaded: boolean,
	lookup: (string) -> Types.LevelDress?
): Decision
	if type(dress) ~= "string" then
		return { action = "none", keep = true }
	end
	if not loaded then
		return { action = "wait", keep = false }
	end
	if type(hash) ~= "string" then
		-- LevelService sets the hash first; until it comes nothing may stay invisible.
		return {
			action = "fail",
			keep = false,
			reason = `Workspace.Level has Dress "{dress}" but no DressHash`,
		}
	end
	local file = lookup(dress)
	if file == nil then
		return { action = "fail", keep = false, reason = `Config/LevelDress/{dress} is missing` }
	end
	local read: any = file
	if read.planHash ~= hash then
		return {
			action = "fail",
			keep = true,
			reason = `Config/LevelDress/{dress} has plan hash {shown(read.planHash)}, the server dressed "{hash}"`,
		}
	end
	if read.frame ~= ScenePlan.FRAME then
		return {
			action = "fail",
			keep = true,
			reason = `Config/LevelDress/{dress} has frame {shown(read.frame)}, not "{ScenePlan.FRAME}"`,
		}
	end
	-- The lists the build walks (an entry it cannot use throws inside the build's pcall).
	for _, field in { "meshes", "props", "effects" } do
		if not isList(read[field]) then
			return {
				action = "fail",
				keep = true,
				reason = `Config/LevelDress/{dress} has no {field} list`,
			}
		end
	end
	return { action = "build", keep = true, dress = file }
end

-- The steps of a build, in order (2.3): the meshes by GROUP_ORDER (the dress's own order inside a
-- group), the props, then the fires, none on a low-end device (L4W2-15).
function ScenePlan.Jobs(dress: Types.LevelDress, lowEnd: boolean): { Job }
	local jobs: { Job } = {}
	local rank: { [string]: number } = {}
	for index, group in ScenePlan.GROUP_ORDER do
		rank[group] = index
	end
	local last = #ScenePlan.GROUP_ORDER + 1
	local meshes = table.clone(dress.meshes)
	local position: { [Types.LevelDressMesh]: number } = {}
	for index, mesh in meshes do
		position[mesh] = index
	end
	table.sort(meshes, function(a: Types.LevelDressMesh, b: Types.LevelDressMesh): boolean
		local ra = rank[a.group] or last
		local rb = rank[b.group] or last
		if ra ~= rb then
			return ra < rb
		end
		return position[a] < position[b]
	end)
	for _, mesh in meshes do
		table.insert(jobs, { kind = "mesh", mesh = mesh })
	end
	for _, prop in dress.props do
		table.insert(jobs, { kind = "prop", prop = prop })
	end
	if not lowEnd then
		for _, effect in dress.effects do
			if effect.kind == ScenePlan.FIRE then
				table.insert(jobs, { kind = "fire", effect = effect })
			end
		end
	end
	return jobs
end

-- The local writes on the server's Parts. `dressed`: this client is showing a dress (built or
-- building); `failed`: the server dressed the level and this client could not.
function ScenePlan.Show(dressed: boolean, failed: boolean, view: View): Show
	if failed then
		return { folder = false, skinned = true, walls = "grey" }
	end
	if not dressed then
		return { folder = false, skinned = false, walls = "none" }
	end
	if view == "grey" then
		return { folder = false, skinned = true, walls = "grey" }
	end
	if view == "walls" then
		return { folder = true, skinned = false, walls = "debug" }
	end
	return { folder = true, skinned = false, walls = "none" }
end

-- Mood B: dressed here, not failed, wanted (Studio's O), and the body not in the lobby camp.
function ScenePlan.Mood(
	dressed: boolean,
	failed: boolean,
	wanted: boolean,
	inLobby: boolean
): boolean
	return dressed and not failed and wanted and not inLobby
end

-- The flat box round `footprints`, nil for none.
function ScenePlan.Box(footprints: { Footprint }): Box?
	local box: Box? = nil
	for _, foot in footprints do
		local minX, maxX = foot.x - foot.hx, foot.x + foot.hx
		local minZ, maxZ = foot.z - foot.hz, foot.z + foot.hz
		local grown = box
		if grown == nil then
			box = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
		else
			grown.minX = math.min(grown.minX, minX)
			grown.maxX = math.max(grown.maxX, maxX)
			grown.minZ = math.min(grown.minZ, minZ)
			grown.maxZ = math.max(grown.maxZ, maxZ)
		end
	end
	return box
end

-- Whether (x, z) stands in `box` grown by `margin` (Combat.json levels.boxMargin, the server's
-- margin for the same box in StageFlow.Rescue). No box: nowhere is in it.
function ScenePlan.InBox(box: Box?, x: number, z: number, margin: number): boolean
	if box == nil then
		return false
	end
	return x >= box.minX - margin
		and x <= box.maxX + margin
		and z >= box.minZ - margin
		and z <= box.maxZ + margin
end

-- An RGB triple of finite numbers 0-255, or nil.
function ScenePlan.Rgb(value: any): { number }?
	if type(value) ~= "table" or #value ~= 3 then
		return nil
	end
	for index = 1, 3 do
		local channel = value[index]
		if type(channel) ~= "number" or channel ~= channel or channel < 0 or channel > 255 then
			return nil
		end
	end
	return { value[1], value[2], value[3] }
end

-- The grey level's wall colour (Expeditions.json looks.wall), or nil (the wall keeps its own).
function ScenePlan.WallColor(looks: any): { number }?
	if type(looks) ~= "table" then
		return nil
	end
	local look = looks[ScenePlan.WALL_LOOK]
	return if type(look) == "table" then ScenePlan.Rgb(look.color) else nil
end

-- Whether the crosshair shows. It marks the shoulder camera's aim, so it needs that camera up
-- (`cameraUp`), and a run that is over has nothing to aim at, even where K9 keeps the camera. The
-- range bench has no run phase (`range`), as for the camera.
function ScenePlan.Crosshair(cameraUp: boolean, phase: string, range: boolean): boolean
	return cameraUp and (range or ScenePlan.RUN_OVER[phase] ~= true)
end

return ScenePlan
