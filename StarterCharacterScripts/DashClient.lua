local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local camera = workspace.CurrentCamera

local Config = require(ReplicatedStorage:WaitForChild("BallConfig"))
local RemoteEventsFolder = ReplicatedStorage:WaitForChild(Config.Paths.REMOTE_EVENTS_FOLDER)
local dashEvent = RemoteEventsFolder:WaitForChild("DashEvent")
local dashCooldownEvent = RemoteEventsFolder:WaitForChild("DashCooldownEvent")

local lastDashTime = 0
local trailTemplate = ReplicatedStorage:FindFirstChild("DashTrail")

if not trailTemplate then

	local att0 = Instance.new("Attachment")
	att0.Name = "DashAtt0"
	local att1 = Instance.new("Attachment")
	att1.Name = "DashAtt1"

	local t = Instance.new("Trail")
	t.Name = "DashTrail"
	t.FaceCamera = true
	t.Lifetime = 0.3
	t.Attachment0 = att0
	t.Attachment1 = att1
	t.Color = ColorSequence.new(Color3.new(1,1,1))
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	trailTemplate = t
	trailTemplate.Parent = ReplicatedStorage
end

local function getBallInView()
	local myGameId = character:GetAttribute("GameId")

	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc.Name == "Ball" then
			local ballGameId = desc:GetAttribute("GameId")

			if ballGameId == myGameId or myGameId == nil then
				if not desc:IsA("BasePart") then continue end

				local vectorToBall = (desc.Position - camera.CFrame.Position)
				local distance = vectorToBall.Magnitude
				local direction = vectorToBall.Unit

				local lookVector = camera.CFrame.LookVector
				local dot = lookVector:Dot(direction)

				if distance < 30 or dot > 0.6 then 
					return desc
				end
			end
		end
	end
	return nil
end

local RunService = game:GetService("RunService")

local function performDash()
	if tick() - lastDashTime < Config.Dash.COOLDOWN then return end
	if character:GetAttribute("FeaturesLocked") then return end

	local ball = getBallInView()
	lastDashTime = tick()

	if ball then
		local startTime = tick()
		local duration = Config.Dash.DURATION
		local startCFrame = rootPart.CFrame
		local originalAutoRotate = humanoid.AutoRotate

		humanoid.AutoRotate = false
		rootPart.Anchored = true

		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			local elapsed = tick() - startTime
			local alpha = math.clamp(elapsed / duration, 0, 1)

			local ballVel = ball:GetAttribute("Velocity") or Vector3.zero
			local timeLeft = math.max(duration - elapsed, 0)
			local predictedPos = ball.Position + (ballVel * timeLeft)

			local direction = (predictedPos - startCFrame.Position).Unit
			local targetDest = startCFrame.Position + direction * (Config.Dash.POWER * Config.Dash.DURATION)

			if alpha >= 1 then
				connection:Disconnect()
				rootPart.Anchored = false
				humanoid.AutoRotate = originalAutoRotate
				rootPart.AssemblyLinearVelocity = direction * Config.Dash.POWER
				return
			end

			local currentPos = startCFrame.Position:Lerp(targetDest, alpha)
			rootPart.CFrame = CFrame.new(currentPos, predictedPos)
		end)

		local t = trailTemplate:Clone()
		local att0 = rootPart:FindFirstChild("DashAtt0") or Instance.new("Attachment", rootPart)
		att0.Name = "DashAtt0" 
		att0.Position = Vector3.new(0, 1, 0)

		local att1 = rootPart:FindFirstChild("DashAtt1") or Instance.new("Attachment", rootPart)
		att1.Name = "DashAtt1"
		att1.Position = Vector3.new(0, -1, 0)

		t.Attachment0 = att0
		t.Attachment1 = att1
		t.Parent = rootPart
		t.Enabled = true

		task.delay(duration, function()
			t.Enabled = false
			Debris:AddItem(t, 1)
		end)

		dashEvent:FireServer((ball.Position - rootPart.Position).Unit)

	else
		local dashDirection = Vector3.zero
		if humanoid.MoveDirection.Magnitude > 0 then
			dashDirection = humanoid.MoveDirection
		else
			dashDirection = (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
		end

		local vectorForce = Instance.new("LinearVelocity")
		vectorForce.Name = "DashVelocity"
		vectorForce.Attachment0 = rootPart:FindFirstChild("RootRigAttachment") or rootPart:FindFirstChild("RootAttachment") 

		if not vectorForce.Attachment0 then
			local att = Instance.new("Attachment", rootPart)
			att.Name = "DashAttachment"
			vectorForce.Attachment0 = att
		end

		vectorForce.MaxForce = 1000000
		vectorForce.VectorVelocity = dashDirection * Config.Dash.POWER
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
		vectorForce.Parent = rootPart

		Debris:AddItem(vectorForce, Config.Dash.DURATION)

		local t = trailTemplate:Clone()
		local att0 = rootPart:FindFirstChild("DashAtt0") or Instance.new("Attachment", rootPart)
		att0.Name = "DashAtt0"
		att0.Position = Vector3.new(0, 1, 0)

		local att1 = rootPart:FindFirstChild("DashAtt1") or Instance.new("Attachment", rootPart)
		att1.Name = "DashAtt1"
		att1.Position = Vector3.new(0, -1, 0)

		t.Attachment0 = att0
		t.Attachment1 = att1
		t.Parent = rootPart
		t.Enabled = true

		task.delay(Config.Dash.DURATION, function()
			t.Enabled = false
			Debris:AddItem(t, 1)
		end)

		dashEvent:FireServer(dashDirection)
	end
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonX then
		performDash()
	end
end)


character:SetAttribute("DashTrigger", false)
character:GetAttributeChangedSignal("DashTrigger"):Connect(function()
	if character:GetAttribute("DashTrigger") == true then
		performDash()
		character:SetAttribute("DashTrigger", false)
	end
end)

player.CharacterAdded:Connect(function(newChar)
	character = newChar
	rootPart = character:WaitForChild("HumanoidRootPart")
	humanoid = character:WaitForChild("Humanoid")


end)
