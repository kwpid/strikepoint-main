local GoalManager = {}

local contentProvider = game:GetService("ContentProvider")

local GOALS_DATA = {
	["Default"] = {
		Path = "Default",
		Name = "Default",
		Desc = "The default goal explosion.",
		Price = 0,
		Rarity = "Common",
		ImageId = 109497098441738
	},
	["Plasma"] = {
		Path = "Plasma",
		Name = "Plasma",
		Desc = "Awaken the yes",
		Price = 150,
		Rarity = "Uncommon",
		ImageId = 86847204888892
	},
}

function GoalManager.GetGoal(name)
	return GOALS_DATA[name]
end

function GoalManager.GetAllGoals()
	return GOALS_DATA
end

return GoalManager
