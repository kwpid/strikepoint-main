local SwordManager = {}

local SWORDS_DATA = {
	["DefaultSword"] = {
		Path = "DefaultSword",
		Name = "DefaultSword",
		Desc = "A basic sword for beginners.",
		Price = 0,
		Rarity = "Common",
		ImageId = 1133333333, -- Original was number
	},
	["Dark Scythe"] = {
		Path = "Dark Scythe",
		Name = "Dark Scythe",
		Desc = "A deadly scythe with dark energy.",
		Price = 1000,
		Rarity = "Rare",
		ImageId = 1133333334, -- Original was number
	}
}

function SwordManager.GetSword(name)
	return SWORDS_DATA[name]
end

function SwordManager.GetAllSwords()
	return SWORDS_DATA
end

return SwordManager
