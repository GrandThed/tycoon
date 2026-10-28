--!strict
-- Studio tests only: AnimTestData's clips as per-bone CFrame lists, and where in a clip a time is.

local AnimClips = {}

export type Clip = {
	slot: string,
	clip: string,
	fps: number,
	frames: number,
	loop: boolean,
	windup: number?,
	-- A loop wraps from its last frame to its first; a one-shot ends on its last frame.
	length: number,
	poses: { [string]: { CFrame } },
}

-- Translations are in the rig's glTF units, so they take the model's scale.
function AnimClips.Decode(data: any, scale: number): { Clip }
	local clips: { Clip } = {}
	for _, c in data.clips do
		local poses: { [string]: { CFrame } } = {}
		for name, track in c.bones do
			local list = table.create(c.frames)
			local r, t = track.r, track.t
			for i = 0, c.frames - 1 do
				local x, y, z = 0, 0, 0
				if t then
					x, y, z = t[i * 3 + 1] * scale, t[i * 3 + 2] * scale, t[i * 3 + 3] * scale
				end
				list[i + 1] =
					CFrame.new(x, y, z, r[i * 4 + 1], r[i * 4 + 2], r[i * 4 + 3], r[i * 4 + 4])
			end
			poses[name] = list
		end
		table.insert(clips, {
			slot = c.slot,
			clip = c.clip,
			fps = c.fps,
			frames = c.frames,
			loop = c.loop,
			windup = c.windup,
			length = (if c.loop then c.frames else c.frames - 1) / c.fps,
			poses = poses,
		})
	end
	return clips
end

-- The frame index (0-based) and the blend toward the next frame at `t` seconds into the clip.
function AnimClips.At(clip: Clip, t: number): (number, number)
	local f = t * clip.fps
	local i = math.floor(f)
	local a = f - i
	if not clip.loop and i + 1 >= clip.frames then
		return clip.frames - 1, 0
	end
	return i % clip.frames, a
end

function AnimClips.Sample(clip: Clip, list: { CFrame }, i: number, a: number): CFrame
	local from = list[i + 1]
	if a <= 0 then
		return from
	end
	return from:Lerp(list[(i + 1) % clip.frames + 1], a)
end

return AnimClips
