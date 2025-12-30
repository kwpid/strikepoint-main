local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryDataStore = DataStoreService:GetDataStore("PlayerInventory_v1")
local StatsDataStore = DataStoreService:GetDataStore("PlayerStats_v1")

local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not remoteEvents then
	remoteEvents = Instance.new("Folder")
	remoteEvents.Name = "RemoteEvents"
	remoteEvents.Parent = ReplicatedStorage
end

local function createRemote(className, name)
	local remote = remoteEvents:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = remoteEvents
	end
	return remote
end

local getInventoryFunction = createRemote("RemoteFunction", "GetInventoryFunction")
local getEquippedItemsFunction = createRemote("RemoteFunction", "GetEquippedItemsFunction")
local equipItemEvent = createRemote("RemoteEvent", "EquipItemEvent")
local inventoryUpdatedEvent = createRemote("RemoteEvent", "InventoryUpdatedEvent")
local sellItemEvent = createRemote("RemoteEvent", "SellItemEvent")
local sellAllItemEvent = createRemote("RemoteEvent", "SellAllItemEvent")
local toggleLockItemEvent = createRemote("RemoteEvent", "ToggleLockItemEvent")

local statsUpdatedEvent = createRemote("RemoteEvent", "StatsUpdatedEvent")

local sessionData = {}

local AbilityManager = require(ReplicatedStorage.Abilities.AbilityManager)

local SWORD_DEFINITIONS = {
	["DefaultSword"] = {
		Name = "DefaultSword",
		RobloxId = 1133333333,
		Value = 0,
		Rarity = "Common",
		Type = "Sword"
	},
	["Dark Scythe"] = {
		Name = "Dark Scythe",
		RobloxId = 1133333334,
		Value = 1000,
		Rarity = "Rare",
		Type = "Sword"
	}
}

local function calculateLevelFromXP(xp)
	local level = 1
	local cumulativeXP = 0

	while true do
		local xpForNextLevel = level * 100
		if cumulativeXP + xpForNextLevel > xp then
			break
		end
		cumulativeXP = cumulativeXP + xpForNextLevel
		level = level + 1
	end

	return level
end

local function getXPForLevel(level)
	local totalXP = 0
	for i = 1, level - 1 do
		totalXP = totalXP + (i * 100)
	end
	return totalXP
end

local function getFullItemData(itemName, itemType)
	if itemType == "Ability" then
		local ability = AbilityManager.GetAbility(itemName)
		if ability then
			return {
				Name = ability.Config.Name,
				RobloxId = ability.Config.ImageId, -- using ImageId as ID for now
				Value = ability.Config.Price,
				Rarity = "Common",
				Type = "Ability",
				IsLocked = false
			}
		end
	else
		local def = SWORD_DEFINITIONS[itemName]
		if def then
			return {
				Name = def.Name,
				RobloxId = def.RobloxId,
				Value = def.Value,
				Rarity = def.Rarity,
				Type = "Sword",
				IsLocked = false,
			}
		end
	end
	return nil
end

local function loadData(player)
	local userId = player.UserId

	local success, data = pcall(function()
		return InventoryDataStore:GetAsync(tostring(userId))
	end)

	if success and data then
		sessionData[userId] = data
	else
		sessionData[userId] = {
			Inventory = {},
			Equipped = {}, -- Swords
			EquippedAbility = "Quad" -- Default Ability
		}
	end

	-- Ensure data structure integrity
	if not sessionData[userId].EquippedAbility then
		sessionData[userId].EquippedAbility = "Quad"
	end

	local STARTER_SWORDS = { "DefaultSword", "Dark Scythe" }
	local STARTER_ABILITIES = { "Quad" }
	local inventory = sessionData[userId].Inventory

	local ownedItems = {}
	for _, item in ipairs(inventory) do
		ownedItems[item.Name] = true
	end

	for _, itemName in ipairs(STARTER_SWORDS) do
		if not ownedItems[itemName] then
			local itemData = getFullItemData(itemName, "Sword")
			if itemData then table.insert(inventory, itemData) end
		end
	end

	for _, itemName in ipairs(STARTER_ABILITIES) do
		if not ownedItems[itemName] then
			local itemData = getFullItemData(itemName, "Ability")
			if itemData then table.insert(inventory, itemData) end
		end
	end

	if #sessionData[userId].Equipped == 0 then
		table.insert(sessionData[userId].Equipped, "DefaultSword")
	end

	local statsSuccess, statsData = pcall(function()
		return StatsDataStore:GetAsync(tostring(userId))
	end)

	if statsSuccess and statsData then
		sessionData[userId].Stats = statsData
	else
		sessionData[userId].Stats = {
			Wins = 0,
			Losses = 0,
			WinStreak = 0,
			PeakWinStreak = 0,
			XP = 0,
			TotalGoals = 0,
		}
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local stats = sessionData[userId].Stats
	local level = calculateLevelFromXP(stats.XP)

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = stats.Wins
	wins.Parent = leaderstats

	local winStreak = Instance.new("IntValue")
	winStreak.Name = "Win Streak"
	winStreak.Value = stats.WinStreak
	winStreak.Parent = leaderstats

	local levelValue = Instance.new("IntValue")
	levelValue.Name = "Level"
	levelValue.Value = level
	levelValue.Parent = leaderstats
end

local function saveData(player)
	local userId = player.UserId
	if sessionData[userId] then
		pcall(function()
			InventoryDataStore:SetAsync(tostring(userId), {
				Inventory = sessionData[userId].Inventory,
				Equipped = sessionData[userId].Equipped,
				EquippedAbility = sessionData[userId].EquippedAbility
			})
		end)

		pcall(function()
			StatsDataStore:SetAsync(tostring(userId), sessionData[userId].Stats)
		end)
	end
end

getInventoryFunction.OnServerInvoke = function(player)
	local data = sessionData[player.UserId]
	return data and data.Inventory or {}
end

getEquippedItemsFunction.OnServerInvoke = function(player)
	local data = sessionData[player.UserId]
	if not data then return {} end

	local equippedNames = {}
	-- Add Swords
	for _, itemName in ipairs(data.Equipped) do
		table.insert(equippedNames, itemName)
	end
	-- Add Ability
	if data.EquippedAbility then
		table.insert(equippedNames, data.EquippedAbility)
	end
	return equippedNames
end

equipItemEvent.OnServerEvent:Connect(function(player, itemName, isUnequip, itemType)
	local data = sessionData[player.UserId]
	if not data then return end

	local ownsItem = false
	for _, item in ipairs(data.Inventory) do
		if item.Name == itemName then
			ownsItem = true
			break
		end
	end

	if not ownsItem then return end

	if itemType == "Ability" then
		if isUnequip then
			-- Can't really unequip default ability, but logic for swapping:
			if data.EquippedAbility == itemName then
				data.EquippedAbility = "Quad" -- Revert to default
			end
		else
			data.EquippedAbility = itemName
		end

		if player.Character then
			player.Character:SetAttribute("EquippedAbility", data.EquippedAbility)
		end
	else 
		-- Sword Logic
		if isUnequip then
			local index = table.find(data.Equipped, itemName)
			if index then table.remove(data.Equipped, index) end
			if #data.Equipped == 0 then table.insert(data.Equipped, "DefaultSword") end
		else
			data.Equipped = { itemName }
		end

		if player.Character then
			local newSword = data.Equipped[1] or "None"
			player.Character:SetAttribute("EquippedSword", newSword)
		end
	end

	inventoryUpdatedEvent:FireClient(player)
end)

local function applyCharacterAttributes(player, char)
	local data = sessionData[player.UserId]
	if data then
		local ability = data.EquippedAbility or "Quad"
		char:SetAttribute("EquippedAbility", ability)

		local sword = (data.Equipped and data.Equipped[1]) or "DefaultSword"
		if sword ~= "None" then
			char:SetAttribute("EquippedSword", sword)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		applyCharacterAttributes(player, char)
	end)

	loadData(player)

	-- Apply again in case character spawned during load
	if player.Character then
		applyCharacterAttributes(player, player.Character)
	end
end)

Players.PlayerRemoving:Connect(saveData)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadData, player)
end

local DataService = {}

function DataService.GetEquippedSword(player)
	local data = sessionData[player.UserId]
	return data and data.Equipped[1] or "DefaultSword"
end

function DataService.GetEquippedAbility(player)
	local data = sessionData[player.UserId]
	return data and data.EquippedAbility or "Quad"
end

function DataService.AddWin(player)
	local data = sessionData[player.UserId]
	if not data or not data.Stats then return end

	data.Stats.Wins = data.Stats.Wins + 1
	data.Stats.WinStreak = data.Stats.WinStreak + 1

	if data.Stats.WinStreak > data.Stats.PeakWinStreak then
		data.Stats.PeakWinStreak = data.Stats.WinStreak
	end

	DataService.UpdateLeaderStats(player)
end

function DataService.AddLoss(player)
	local data = sessionData[player.UserId]
	if not data or not data.Stats then return end

	data.Stats.Losses = data.Stats.Losses + 1
	data.Stats.WinStreak = 0

	DataService.UpdateLeaderStats(player)
end

function DataService.AddXP(player, amount)
	local data = sessionData[player.UserId]
	if not data or not data.Stats then return end

	data.Stats.XP = data.Stats.XP + amount

	local newLevel = calculateLevelFromXP(data.Stats.XP)
	DataService.UpdateLeaderStats(player)
end

function DataService.AddGoal(player)
	local data = sessionData[player.UserId]
	if not data or not data.Stats then return end

	data.Stats.TotalGoals = data.Stats.TotalGoals + 1
end

function DataService.UpdateLeaderStats(player)
	local data = sessionData[player.UserId]
	if not data or not data.Stats then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local stats = data.Stats
	local level = calculateLevelFromXP(stats.XP)

	local winsValue = leaderstats:FindFirstChild("Wins")
	if winsValue then
		winsValue.Value = stats.Wins
	end

	local winStreakValue = leaderstats:FindFirstChild("Win Streak")
	if winStreakValue then
		winStreakValue.Value = stats.WinStreak
	end

	local levelValue = leaderstats:FindFirstChild("Level")
	if levelValue then
		levelValue.Value = level
	end

	statsUpdatedEvent:FireClient(player, stats, level)
end

function DataService.GetStats(player)
	local data = sessionData[player.UserId]
	if not data or not data.Stats then return nil end

	local stats = data.Stats
	local level = calculateLevelFromXP(stats.XP)

	return {
		Wins = stats.Wins,
		Losses = stats.Losses,
		WinStreak = stats.WinStreak,
		PeakWinStreak = stats.PeakWinStreak,
		XP = stats.XP,
		Level = level,
		TotalGoals = stats.TotalGoals,
	}
end

_G.DataService = DataService

return DataService
