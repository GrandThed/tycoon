--!strict
-- L4B-7 (docs/prompts/l4-w1b-contract.md §4): a dash's i-frames count only once the server's
-- own ring of the dasher's positions has seen the dash. Before L4 a dash request opened its
-- window by itself, so a client that never moved held 0.25 s of every 0.64 s (39%) for free.
-- WeaponService.OnDash now only records a claim; each Heartbeat, right after the ring sample,
-- Step judges it, and a proven claim opens its window from the request.
--
-- F1 (docs/prompts/l4-w1b-fix-round.md): the dash keeps its pre-L4 feel. VitalsService holds a
-- decision that a pending claim would cover (Pending) until the claim is proven (voided) or
-- lapses (it lands), so the proof's latency never costs a dodge. What this stops is a dash
-- claimed with no movement and a dash into a wall, not a modified client that moves its own
-- root (the game has no movement anti-cheat: such a client can already step out of any shape).
--
-- Pure: PositionRing (pure), the Types annotations and numbers; no service, no Instance, no clock
-- of its own (every time is an argument), so tools/crowd_harness loads it as it stands
-- (tests_l4b.luau) and runs it against the real VitalsService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local PositionRing = require(script.Parent:WaitForChild("PositionRing"))

-- What a claim is judged by, from the config (DashProof.Rule).
export type Rule = {
	-- Studs/s the flat motion must reach: movement.dashProofShare x dashDistance / dashSeconds.
	speed: number,
	-- The stretch the speed is measured over (movement.dashProofSeconds).
	span: number,
	-- shooting.originLagMaxSeconds: a dash's motion may replicate before its remote arrives, so
	-- motion that ended up to this long before the request still proves it.
	lookback: number,
	-- Seconds after the request when an unproven claim lapses: dashSeconds + lookback.
	lapse: number,
}
export type Verdict = "proven" | "lapsed" | "pending"
-- A player's i-frame clock as WeaponService keeps it on os.clock(): the latest window
-- [iframesFrom, iframesUntil) and the one before it, both kept after they lapse (VitalsService
-- judges an impact a moment after it falls).
export type Windows = {
	iframesFrom: number,
	iframesUntil: number,
	iframesWasFrom: number,
	iframesWasUntil: number,
}
-- The same clock with the pending claim beside it (WeaponService's Shooter): os.clock() of the
-- accepted dash request the ring has not proven yet, nil = none.
export type Claimant = {
	dashClaimAt: number?,
	iframesFrom: number,
	iframesUntil: number,
	iframesWasFrom: number,
	iframesWasUntil: number,
}

local DashProof = {}

local function positive(value: any): boolean
	return type(value) == "number" and value > 0 and value < math.huge
end

-- The rule from ProvingGrounds.json's `movement` and `shooting`; nil when a number it needs is
-- missing or not a positive finite number (lookback may be 0). Then no claim is ever proven, and
-- a dash earns no i-frames: the server cannot judge one, so it never forgives one.
function DashProof.Rule(
	movement: Types.RangeMovementConfig,
	shooting: Types.RangeShootingConfig
): Rule?
	local share = movement.dashProofShare
	local span = movement.dashProofSeconds
	local distance = movement.dashDistance
	local seconds = movement.dashSeconds
	local lookback = shooting.originLagMaxSeconds
	if
		not positive(share)
		or not positive(span)
		or not positive(distance)
		or not positive(seconds)
		or not (type(lookback) == "number" and lookback >= 0 and lookback < math.huge)
	then
		return nil
	end
	return {
		speed = share * distance / seconds,
		span = span,
		lookback = lookback,
		lapse = seconds + lookback,
	}
end

-- One pending claim made at `claimAt`, judged at `now` against the ring and the root's
-- `position` now: "proven" once the fastest flat stretch of `rule.span` that ended at or after
-- `claimAt - rule.lookback` reaches `rule.speed`; else "lapsed" once `now` is past
-- `claimAt + rule.lapse`; else "pending". A proof wins over a lapse judged in the same frame.
function DashProof.Verdict(
	history: PositionRing.History,
	now: number,
	position: Vector3,
	claimAt: number,
	rule: Rule
): Verdict
	local window = now - claimAt + rule.lookback
	if window > 0 then
		local speed = PositionRing.Motion(history, now, position, window, rule.span, true)
		-- A NaN speed fails the comparison: never proven.
		if speed >= rule.speed then
			return "proven"
		end
	end
	if now > claimAt + rule.lapse then
		return "lapsed"
	end
	return "pending"
end

-- Opens an i-frame window [from, from + seconds), keeping the two windows VitalsService reads:
-- * the latest window lapsed before `from`: it steps back, and this one is the latest;
-- * the latest window meets this one: they become one (it never shortens a longer window: a dash
--   inside an ability's leap; a dash proven late may start before a window granted since);
-- * this one ended before the latest began (a dash proven after a later window was granted): it
--   takes the earlier slot when it ends later than the window there.
-- `from` is a proven dash's request, or now for a window the server grants.
function DashProof.Open(windows: Windows, from: number, seconds: number): ()
	local untilClock = from + math.max(seconds, 0)
	if from >= windows.iframesUntil then
		windows.iframesWasFrom = windows.iframesFrom
		windows.iframesWasUntil = windows.iframesUntil
		windows.iframesFrom = from
		windows.iframesUntil = untilClock
	elseif untilClock >= windows.iframesFrom then
		windows.iframesFrom = math.min(windows.iframesFrom, from)
		windows.iframesUntil = math.max(windows.iframesUntil, untilClock)
	elseif untilClock > windows.iframesWasUntil then
		windows.iframesWasFrom = from
		windows.iframesWasUntil = untilClock
	end
end

-- One Heartbeat of a claimant's pending claim, everything WeaponService does with it after the
-- frame's ring sample: judged (Verdict); proven, its window of `seconds` opens from the request
-- (Open) and the claim is over; lapsed, it is over and nothing opens. Without a rule the claim
-- is over unproven ("lapsed"). Returns the verdict, nil when there was no claim.
function DashProof.Step(
	claimant: Claimant,
	history: PositionRing.History,
	now: number,
	position: Vector3,
	rule: Rule?,
	seconds: number
): Verdict?
	local claimAt = claimant.dashClaimAt
	if claimAt == nil then
		return nil
	end
	if rule == nil then
		claimant.dashClaimAt = nil
		return "lapsed"
	end
	local verdict: Verdict = DashProof.Verdict(history, now, position, claimAt, rule)
	if verdict == "proven" then
		claimant.dashClaimAt = nil
		DashProof.Open(claimant, claimAt, seconds)
	elseif verdict == "lapsed" then
		claimant.dashClaimAt = nil
	end
	return verdict
end

-- What a pending claim holds a decision for (F1): the window of `seconds` it opens if it is
-- proven, [from, untilClock), and the last moment it can still be proven, lapseAt (Verdict's
-- lapse). 0, 0, 0 = nothing to wait for (no claim, or no rule to prove one by).
function DashProof.Pending(claimAt: number?, rule: Rule?, seconds: number): (number, number, number)
	if claimAt == nil or rule == nil then
		return 0, 0, 0
	end
	return claimAt, claimAt + math.max(seconds, 0), claimAt + rule.lapse
end

return DashProof
