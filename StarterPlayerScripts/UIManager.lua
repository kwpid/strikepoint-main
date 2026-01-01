local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ClientUIManager = {}

function ClientUIManager.Init()
	local gameUI = Instance.new("ScreenGui")
	gameUI.Name = "GameUI"
	gameUI.ResetOnSpawn = false
	gameUI.IgnoreGuiInset = true
	gameUI.Parent = playerGui


	local mainUI = playerGui:WaitForChild("MainUI", 10)
	if not mainUI then
		warn("ClientUIManager: MainUI not found")
		return
	end

	local function updateState()
		local gameId = player:GetAttribute("GameId")
		local inGame = (gameId ~= nil)

		mainUI.Enabled = not inGame
		gameUI.Enabled = inGame

	end

	player:GetAttributeChangedSignal("GameId"):Connect(updateState)

	updateState()
end

ClientUIManager.Init()

return ClientUIManager
