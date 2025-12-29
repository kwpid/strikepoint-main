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
local doubleJumpEvent = RemoteEventsFolder:WaitForChild("DoubleJumpEvent")
local jumpEffectTemplate = ReplicatedStorage:WaitForChild("JumpEffect")

local hasDoubleJumped = false

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
	if newState == Enum.HumanoidStateType.Landed then
		hasDoubleJumped = false
	end
end)

local function tryDoubleJump()
	local state = humanoid:GetState()
	local inAir = (state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping)

	if inAir and not hasDoubleJumped then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		hasDoubleJumped = true

		playDoubleJumpEffect(rootPart.CFrame)
		doubleJumpEvent:FireServer()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if
		input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space
		or input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA
	then
		tryDoubleJump()
	end
end)

UserInputService.JumpRequest:Connect(function()
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
		tryDoubleJump()
	end
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
