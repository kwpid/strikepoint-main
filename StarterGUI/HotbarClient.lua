local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")
local hotbar = mainUI:WaitForChild("Hotbar") 

local Config = require(ReplicatedStorage:WaitForChild("BallConfig"))
local AbilityManager = require(ReplicatedStorage.Abilities.AbilityManager)
local RemoteEventsFolder = ReplicatedStorage:WaitForChild(Config.Paths.REMOTE_EVENTS_FOLDER)

local swingEvent = RemoteEventsFolder:WaitForChild("SwingEvent")
local parryCooldownEvent = RemoteEventsFolder:WaitForChild("ParryCooldownEvent", 10)
local dashCooldownEvent = RemoteEventsFolder:WaitForChild("DashCooldownEvent", 10)

if not parryCooldownEvent then
	warn("HotbarClient: ParryCooldownEvent not found!")
end


local parryBtn = hotbar:WaitForChild("Parry")
local abilityBtn = hotbar:WaitForChild("Ability")
local dashBtn = hotbar:WaitForChild("Dash")

print("HotbarClient: UI Loaded via", hotbar:GetFullName())

-- State
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled


local function setupButton(btn, callback)
	btn.MouseButton1Click:Connect(callback)
end


local function onParry()
	local camera = workspace.CurrentCamera
	local direction = camera.CFrame.LookVector
	swingEvent:FireServer(direction)
end

setupButton(parryBtn, onParry)


local function onAbility()

end

setupButton(abilityBtn, onAbility)

-- Dash Logic
local function onDash()
	local char = player.Character
	if char then
		char:SetAttribute("DashTrigger", true)
	end
end
if dashBtn then
	setupButton(dashBtn, onDash)
end


local function playCooldown(btn, duration)
	local progress = btn:FindFirstChild("progress") or btn:FindFirstChild("Progress")
	if not progress then 
		warn("HotbarClient: 'Progress' frame not found in", btn.Name)
		return 
	end

	print("HotbarClient: Playing cooldown for", btn.Name, "Duration:", duration)

	progress.AnchorPoint = Vector2.new(0, 1)
	progress.Position = UDim2.new(0, 0, 1, 0)
	progress.Size = UDim2.new(1, 0, 1, 0) 
	progress.BackgroundTransparency = 0.6 
	progress.Visible = true

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
	local goal = { Size = UDim2.new(1, 0, 0, 0) }

	local tween = TweenService:Create(progress, tweenInfo, goal)
	tween:Play()

	tween.Completed:Connect(function()
		progress.Visible = false
	end)
end


if parryCooldownEvent then
	parryCooldownEvent.OnClientEvent:Connect(function(duration)
		playCooldown(parryBtn, duration)
	end)
end

if dashCooldownEvent and dashBtn then
	dashCooldownEvent.OnClientEvent:Connect(function(duration)
		playCooldown(dashBtn, duration)
	end)
end


local function updateAbilityButton()
	local char = player.Character
	if not char then return end

	local abilityName = char:GetAttribute("EquippedAbility") or "Quad"
	local abilityData = AbilityManager.GetAbility(abilityName)

	if abilityData and abilityData.Config and abilityData.Config.ImageId then
		abilityBtn.Image = abilityData.Config.ImageId
	else
		warn("HotbarClient: No ImageId found for ability:", abilityName)
	end
end

player.CharacterAdded:Connect(function(char)
	char:GetAttributeChangedSignal("EquippedAbility"):Connect(updateAbilityButton)
	task.wait(0.1)
	updateAbilityButton()
end)

if player.Character then
	updateAbilityButton()
	player.Character:GetAttributeChangedSignal("EquippedAbility"):Connect(updateAbilityButton)
end

local function updateLockedState()
	local char = player.Character
	if not char then return end

	local isLocked = char:GetAttribute("FeaturesLocked") or false

	local dashLocked = dashBtn:FindFirstChild("locked")
	if dashLocked and dashLocked:IsA("TextLabel") then
		dashLocked.Visible = isLocked
	end

	local abilityLocked = abilityBtn:FindFirstChild("locked")
	if abilityLocked and abilityLocked:IsA("TextLabel") then
		abilityLocked.Visible = isLocked
	end
end

player.CharacterAdded:Connect(function(char)
	char:GetAttributeChangedSignal("FeaturesLocked"):Connect(updateLockedState)
	task.wait(0.1)
	updateLockedState()
end)

if player.Character then
	player.Character:GetAttributeChangedSignal("FeaturesLocked"):Connect(updateLockedState)
	updateLockedState()
end
