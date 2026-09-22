--!strict
-- COPY of src/client/UI/Motion.luau for the Expeditions place (C0), verbatim. Dedupe is a
-- follow-up.
-- Every presentation tween takes its TweenInfo from here so reduce-motion is honored in
-- exactly one place: touch/low-end devices get shorter, linear tweens (spec §10); everyone
-- else gets the requested easing. Callers still decide whether to emit particles.

local Theme = require(script.Parent:WaitForChild("Theme"))

local Motion = {}

function Motion.Seconds(seconds: number): number
	return if Theme.reducedMotion then seconds * Theme.REDUCED_MOTION_FACTOR else seconds
end

function Motion.Info(
	seconds: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): TweenInfo
	if Theme.reducedMotion then
		return TweenInfo.new(seconds * Theme.REDUCED_MOTION_FACTOR, Enum.EasingStyle.Linear)
	end
	return TweenInfo.new(
		seconds,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
end

return Motion
