local PhysicsService = game:GetService("PhysicsService")

local GROUPS = {
	"RedPlayer",
	"BluePlayer",
	"ZoneRed",
	"ZoneBlue",
	"Ball"
}


local function safeRegisterGroup(name)
	local success, err = pcall(function() 
		PhysicsService:RegisterCollisionGroup(name)
	end)
	if not success then
		warn("CollisionSetup: Info registering group " .. name .. ": " .. tostring(err))
	end
end

for _, group in ipairs(GROUPS) do
	safeRegisterGroup(group)
end

PhysicsService:CollisionGroupSetCollidable("RedPlayer", "ZoneBlue", true)
PhysicsService:CollisionGroupSetCollidable("RedPlayer", "ZoneRed", false)

PhysicsService:CollisionGroupSetCollidable("BluePlayer", "ZoneRed", true) 
PhysicsService:CollisionGroupSetCollidable("BluePlayer", "ZoneBlue", false) 


PhysicsService:CollisionGroupSetCollidable("Ball", "ZoneRed", false)
PhysicsService:CollisionGroupSetCollidable("Ball", "ZoneBlue", false)

PhysicsService:CollisionGroupSetCollidable("RedPlayer", "Default", true)
PhysicsService:CollisionGroupSetCollidable("BluePlayer", "Default", true)

print("CollisionSetup: Groups and rules configured.")
