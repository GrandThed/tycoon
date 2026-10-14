--!strict
-- L1b-W2-13/14 (docs/INTERFACES.md "Wave 2 — the long road"): one melee swing per jump. The
-- server (WeaponService.OnAttack) and the client (InputController) ask the same questions of the
-- same numbers, so the client never sends a swing the server would refuse. Pure: no Instance, no
-- clock.

export type State = { used: boolean } -- an airborne swing was taken since the last landing

local SwingGate = {}

-- How far over its standing height a swing's origin may be and still count as grounded. Shared
-- with WeaponService's air tracking so the landing it sees and the gate agree.
SwingGate.AIR_MARGIN_STUDS = 0.75

function SwingGate.New(): State
	return { used = false }
end

-- height = the swing origin's Y over the floor under it (nil = no floor: airborne).
function SwingGate.IsAir(height: number?, standOffset: number): boolean
	if height == nil then
		return true
	end
	return height > standOffset + SwingGate.AIR_MARGIN_STUDS
end

function SwingGate.Allows(state: State, airborne: boolean): boolean
	return not (airborne and state.used)
end

-- A grounded swing clears the gate; an airborne one spends it until the next landing (a double
-- jump is not a landing).
function SwingGate.Took(state: State, airborne: boolean)
	state.used = airborne
end

function SwingGate.Landed(state: State)
	state.used = false
end

return SwingGate
