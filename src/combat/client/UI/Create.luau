--!strict
-- COPY of src/client/UI/Create.luau for the Expeditions place (C0): the hub and combat
-- client trees never require across each other. Dedupe is a follow-up.
-- Tiny instance builder. Applies properties first and parents last, so instances never
-- render half-configured and the "no parent argument in Instance.new" rule is enforced
-- in exactly one place.

local function create(className: string, props: { [string]: any }): Instance
	local instance = Instance.new(className)
	local target = instance :: any
	local parent: Instance? = nil
	for key, value in props do
		if key == "Parent" then
			parent = value :: Instance
		else
			target[key] = value
		end
	end
	if parent ~= nil then
		instance.Parent = parent
	end
	return instance
end

return create
