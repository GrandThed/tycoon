--!strict
-- The haptic pulse of the Proving Grounds' feedback (docs/COMBAT_DESIGN.md section 4: with no
-- sound, vibration is one of the layers a hit is felt through). FeedbackController pulses for
-- the player's own hits and VitalsController for the hits the player takes; both drive the
-- same motors, so both go through this one module. The newest pulse owns the motors: an older
-- pulse's end never cuts a newer one short, which two private copies could not guarantee.
--
-- Gamepads have two motors, phones (where supported) one. Support is read when a controller
-- starts (Detect), not per pulse; a pulse on a device with no motor is a no-op. How strong a
-- pulse is (feedback.haptics, a layer's own scale) is the caller's business.

local HapticService = game:GetService("HapticService")

type Target = { input: Enum.UserInputType, motor: Enum.VibrationMotor }

local INPUTS = { Enum.UserInputType.Gamepad1, Enum.UserInputType.Touch }
local MOTORS = { Enum.VibrationMotor.Large, Enum.VibrationMotor.Small }

local targets: { Target } = {}
local token = 0

local function setMotors(value: number): ()
	for _, target in targets do
		-- pcall: a gamepad unplugged mid-fight must not break the feedback loop.
		pcall(function()
			HapticService:SetMotor(target.input, target.motor, value)
		end)
	end
end

local Haptics = {}

-- Reads which motors this device has. Called from each user's Start; a second call only
-- reads them again.
function Haptics.Detect(): ()
	table.clear(targets)
	for _, input in INPUTS do
		local ok, supported = pcall(function()
			return HapticService:IsVibrationSupported(input)
		end)
		if ok and supported == true then
			for _, motor in MOTORS do
				local motorOk, motorSupported = pcall(function()
					return HapticService:IsMotorSupported(input, motor)
				end)
				if motorOk and motorSupported == true then
					table.insert(targets, { input = input, motor = motor })
				end
			end
		end
	end
end

-- Runs every motor at `amount` (0-1) for `seconds`, replacing any pulse still running.
function Haptics.Pulse(amount: number, seconds: number): ()
	if amount <= 0 or #targets == 0 then
		return
	end
	token += 1
	local current = token
	setMotors(math.clamp(amount, 0, 1))
	task.delay(seconds, function()
		if current == token then
			setMotors(0)
		end
	end)
end

-- Stops the motors now and disowns any pulse still waiting to end.
function Haptics.Stop(): ()
	token += 1
	setMotors(0)
end

return Haptics
