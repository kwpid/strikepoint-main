local module = {}

local abilities = {}
local folder = script.Parent

for _, child in ipairs(folder:GetChildren()) do
	if child:IsA("ModuleScript") and child ~= script then
		local data = require(child)
		if data.Config then
			abilities[data.Config.Name] = data
		end
	end
end

function module.GetAbility(name)
	return abilities[name]
end

function module.GetAllAbilities()
	return abilities
end

return module
