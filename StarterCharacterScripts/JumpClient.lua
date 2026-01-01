local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

local Config = require(ReplicatedStorage:WaitForChild("BallConfig"))
local RemoteEventsFolder = ReplicatedStorage:WaitForChild(Config.Paths.REMOTE_EVENTS_FOLDER)
local AbilityManager = require(ReplicatedStorage.AssetManager.Abilities.AbilityManager)
local doubleJumpEvent = RemoteEventsFolder:WaitForChild("DoubleJumpEvent")
local jumpEffectTemplate = ReplicatedStorage:WaitForChild("JumpEffect")

local hasDoubleJumped = false
local jumpCount = 0
local maxJumps = 2
local lastJumpTime = 0
local TIME_BETWEEN_JUMPS = 0.2 

local function updateAbilities()
	local abilityName = character:GetAttribute("EquippedAbility")
	if abilityName then
		local ability = AbilityManager.GetAbility(abilityName)
		if ability and ability.Config.MaxJumps then
			maxJumps = ability.Config.MaxJumps
		else
			maxJumps = 2
		end
	else
		maxJumps = 2
	end
	print("JumpClient: efficient jumps set to", maxJumps)
end

character:GetAttributeChangedSignal("EquippedAbility"):Connect(updateAbilities)
updateAbilities() 

local function playDoubleJumpEffect(targetCFrame)
	local effectPart = jumpEffectTemplate:Clone()
	effectPart.CFrame = targetCFrame * CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	effectPart.Transparency = 1
	effectPart.Parent = workspace

	-- fade in
	local fadeInInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInGoal = { Transparency = 0.5 }
	local fadeInTween = TweenService:Create(effectPart, fadeInInfo, fadeInGoal)

	-- fade out
	local fadeOutInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeOutGoal = { Transparency = 1 }
	local fadeOutTween = TweenService:Create(effectPart, fadeOutInfo, fadeOutGoal)

	fadeInTween:Play()
	fadeInTween.Completed:Connect(function()
		fadeOutTween:Play()
	end)

	Debris:AddItem(effectPart, 1)
end

humanoid.StateChanged:Connect(function(oldState, newState)
	if newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
		hasDoubleJumped = false
		jumpCount = 0
	elseif newState == Enum.HumanoidStateType.Jumping then
		lastJumpTime = tick()
		jumpCount = jumpCount + 1
	end
end)

local function attemptDoubleJump()
	if character:GetAttribute("FeaturesLocked") then return end

	local state = humanoid:GetState()
	local isAirborne = (state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping)

	if not isAirborne then return end
	if jumpCount >= maxJumps then return end

	if (tick() - lastJumpTime) < TIME_BETWEEN_JUMPS then 
		return 
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	playDoubleJumpEffect(rootPart.CFrame)
	doubleJumpEvent:FireServer()
end

UserInputService.JumpRequest:Connect(function()
	attemptDoubleJump()
end)

doubleJumpEvent.OnClientEvent:Connect(function(otherPlayer)
	if otherPlayer ~= player then
		local otherChar = otherPlayer.Character
		if otherChar then
			local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				playDoubleJumpEffect(otherRoot.CFrame)
			end
		end
	end
end)
