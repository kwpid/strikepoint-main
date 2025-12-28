local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Vector3 = Vector3
local task = task
local Enum = Enum
local workspace = workspace
local Color3 = Color3
local RaycastParams = RaycastParams
local Instance = Instance
local CFrame = CFrame
local UDim2 = UDim2
local math = math
local BrickColor = BrickColor

local BallConfig = require(ReplicatedStorage:WaitForChild("BallConfig"))
local BallPhysics = require(ReplicatedStorage:WaitForChild("BallPhysics"))

local RemoteEventsFolder = ReplicatedStorage:WaitForChild(BallConfig.Paths.REMOTE_EVENTS_FOLDER)
local RemoteEvents = {
	ballUpdate = RemoteEventsFolder:WaitForChild("BallUpdateEvent"),
}
local ServerEvents = {}
ServerEvents.ballHit = RemoteEventsFolder:WaitForChild("ServerBallHit")

local ClearClientBallEvent = RemoteEventsFolder:WaitForChild("ClearClientBall")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local currentBall = nil
local clientBall = nil
local clientState = BallPhysics.new(Vector3.zero)
local serverState = BallPhysics.new(Vector3.zero)

ClearClientBallEvent.OnClientEvent:Connect(function(gameId)
	if clientBall and clientBall:GetAttribute("GameId") == gameId then
		clientBall:Destroy()
		clientBall = nil
	end
	currentBall = nil

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj.Name == "ClientBall" and obj:GetAttribute("PlayerId") == player.UserId and obj:GetAttribute("GameId") == gameId then
			obj:Destroy()
		end
	end
end)

local debugFolder = workspace:FindFirstChild("BallDebug")
if not debugFolder then
	debugFolder = Instance.new("Folder")
	debugFolder.Name = "BallDebug"
	debugFolder.Parent = workspace
end

local debugEnabled = false
local debugHitboxEnabled = false
local balLCamEnabled = false
local originalCameraSubject = nil

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function createClientBall(gameId)
	if clientBall then clientBall:Destroy() end
	clientBall = ReplicatedStorage:WaitForChild("Ball"):Clone()
	clientBall.Name = "ClientBall"
	clientBall.Transparency = 0
	clientBall.CanCollide = false
	clientBall.Anchored = true
	clientBall:SetAttribute("PlayerId", player.UserId)
	clientBall:SetAttribute("GameId", gameId)
	clientBall.Parent = workspace

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.Parent = clientBall
end

local function updateRaycastFilter()
	local filterList = { currentBall, clientBall }
	if debugFolder then table.insert(filterList, debugFolder) end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(filterList, p.Character) end
	end
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local name = obj.Name:lower()
			local isMarker = name == "ballspawn" or name == "t1" or name == "t2" or name:find("plate")
			local isHitbox = name == "hitbox"
			local isFloor = name:find("floor") or name:find("field") or name:find("arena")
			local isGoal = name:find("goaldetector")
			local isTransparent = obj.Transparency >= 0.9 
			local isMesh = obj:IsA("MeshPart")
			if isMarker or ((isTransparent or isMesh) and not isHitbox and not isFloor and not isGoal) then
				table.insert(filterList, obj)
			end
		end
	end
	raycastParams.FilterDescendantsInstances = filterList
end

local function findMyBall()
	local myGameId = player:GetAttribute("GameId")
	if myGameId then
		for _, desc in ipairs(workspace:GetDescendants()) do
			if desc.Name == "Ball" and desc:GetAttribute("GameId") == myGameId then
				return desc
			end
		end
	end
	return nil
end

local function getHitRange()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return BallConfig.Parry.MOBILE_RANGE
	elseif UserInputService.GamepadEnabled then
		return BallConfig.Parry.CONSOLE_RANGE
	else
		return BallConfig.Parry.RANGE
	end
end

local function checkCollision(from, to)
	local direction = (to - from)
	local distance = direction.Magnitude
	if distance < 0.001 then return nil end
	local ballSize = clientBall and clientBall.Size.X or 4
	local rayResult = workspace:Raycast(from, direction.Unit * (distance + ballSize / 2), raycastParams)
	
	if rayResult and clientBall then
		local hitName = rayResult.Instance.Name:lower()
		if hitName:find("goaldetector") then
			local lastTeam = clientBall:GetAttribute("LastTeam")
			local isRedGoal = hitName:find("red")
			local isBlueGoal = hitName:find("blue")

			if (lastTeam == "blue" and isRedGoal) or (lastTeam == "red" and isBlueGoal) then
				return nil
			end
		end
	end

	return rayResult
end

local function getGroundHeight(position)
	local rayOrigin = Vector3.new(position.X, position.Y + 2, position.Z)
	local rayDirection = Vector3.new(0, -300, 0)
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if rayResult then return rayResult.Position.Y end

	local backupOrigin = Vector3.new(position.X, position.Y + 100, position.Z)
	local backupResult = workspace:Raycast(backupOrigin, rayDirection, raycastParams)
	return backupResult and backupResult.Position.Y or 0
end

RemoteEvents.ballUpdate.OnClientEvent:Connect(function(serializedState, gameId)
	local myGameId = player:GetAttribute("GameId")
	if gameId == myGameId then
		serverState:deserialize(serializedState)
		if (serverState.position - clientState.position).Magnitude > 5 then
			clientState:deserialize(serializedState)
		end
		if serverState.color then clientState.color = serverState.color end
		if serverState.transparency ~= nil then clientState.transparency = serverState.transparency end
	end
end)

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function() task.wait(0.1); updateRaycastFilter() end)
end)
updateRaycastFilter()

TextChatService.SendingMessage:Connect(function(message)
	local isDev = false
	if BallConfig.Debug and BallConfig.Debug.DeveloperIds then
		for _, id in ipairs(BallConfig.Debug.DeveloperIds) do
			if player.UserId == id then isDev = true; break end
		end
	end
	if not isDev then return end

	if message.Text == "/debug" then debugEnabled = not debugEnabled
	elseif message.Text == "/debug:hitbox" then debugHitboxEnabled = not debugHitboxEnabled
	elseif message.Text == "/ballcam" then
		balLCamEnabled = not balLCamEnabled
		local cam = workspace.CurrentCamera
		if balLCamEnabled then
			originalCameraSubject = cam.CameraSubject
			cam.CameraSubject = clientBall
			cam.CameraType = Enum.CameraType.Follow
		else
			if originalCameraSubject then cam.CameraSubject = originalCameraSubject end
			cam.CameraType = Enum.CameraType.Custom
		end
	end
end)

task.spawn(function()
	while true do
		local found = findMyBall()
		if found ~= currentBall then
			currentBall = found
			if currentBall then
				print("BallClient: Found my ball:", currentBall:GetFullName())
				-- int. sync
				local s = BallPhysics.new(currentBall.Position)
				serverState:deserialize(s:serialize())
				clientState:deserialize(s:serialize())
				local gameId = currentBall:GetAttribute("GameId")
				if not clientBall then createClientBall(gameId) end
				updateRaycastFilter()
			else
				if clientBall then
					clientBall:Destroy()
					clientBall = nil
				end
			end
		end
		task.wait(1)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not currentBall or not currentBall.Parent or not clientBall then
		if clientBall then
			clientBall:Destroy()
			clientBall = nil
		end
		return
	end

	local lerpSpeed = 20
	local lerpFactor = math.clamp(dt * lerpSpeed, 0, 1)
	if serverState.isMoving then
		clientState.velocity = clientState.velocity:Lerp(serverState.velocity, lerpFactor)
		clientState:update(dt, checkCollision, getGroundHeight(clientState.position), clientBall.Size.X / 2, function(collision, impactSpeed)
			if impactSpeed and impactSpeed > 5 then
				if clientBall:FindFirstChild("Bounce") then clientBall.Bounce:Play() end
			end
		end)

		local drift = (serverState.position - clientState.position).Magnitude
		if drift > 10 then
			clientState.position = serverState.position
		else
			clientState.position = clientState.position:Lerp(serverState.position, lerpFactor)
		end
	else
		clientState.position = clientState.position:Lerp(serverState.position, lerpFactor)
		clientState.velocity = Vector3.zero
		clientState.isMoving = false
	end
	-- vis sync
	clientBall.Position = clientState.position
	clientBall.Color = clientState.color
	clientBall.Transparency = clientState.transparency or 0

	currentBall.Transparency = 1
	for _, desc in ipairs(currentBall:GetDescendants()) do
		if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
			desc.Enabled = false
		elseif desc:IsA("Light") then
			desc.Enabled = false
		end
	end
	if clientState.lastHitter and clientState.lastHitter ~= "None" then
		local lastHitterPlayer = Players:FindFirstChild(clientState.lastHitter)
		if lastHitterPlayer then
			local team = lastHitterPlayer:GetAttribute("Team")
			if team then clientBall:SetAttribute("LastTeam", team) end
		end
	end

	if balLCamEnabled then
		local cam = workspace.CurrentCamera
		if cam.CameraSubject ~= clientBall then
			cam.CameraSubject = clientBall
			cam.CameraType = Enum.CameraType.Follow
		end
	end

	-- debug vis
	if not debugEnabled and not debugHitboxEnabled then return end

	local debugGui = clientBall:FindFirstChild("DebugGui")
	if not debugGui then
		debugGui = Instance.new("BillboardGui")
		debugGui.Name = "DebugGui"
		debugGui.Size = UDim2.new(0, 400, 0, 150)
		debugGui.StudsOffset = Vector3.new(0, 4, 0)
		debugGui.AlwaysOnTop = true
		debugGui.Parent = clientBall

		local textLabel = Instance.new("TextLabel", debugGui)
		textLabel.Name = "TextLabel"
		textLabel.Size = UDim2.new(1, 0, 1, 0)
		textLabel.BackgroundTransparency = 1
		textLabel.TextColor3 = Color3.new(1, 1, 1)
		textLabel.TextStrokeTransparency = 0
		textLabel.Font = Enum.Font.Code
		textLabel.TextSize = 18
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.TextYAlignment = Enum.TextYAlignment.Top
	end

	local gHeight = getGroundHeight(clientState.position)
	local isBallGrounded = currentBall:GetAttribute("Grounded")
	local debugText = string.format(
		"Speed: %.1f\nHits: %d\nLast: %s\nGrounded: %s", 
		clientState.velocity.Magnitude, 
		clientState.hitCount, 
		clientState.lastHitter or "None",
		tostring(isBallGrounded)
	)
	debugGui.TextLabel.Text = debugText
	debugGui.Enabled = debugEnabled

	local hitboxPart = workspace:FindFirstChild("DebugHitbox_" .. player.UserId)
	if debugHitboxEnabled and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		if not hitboxPart then
			hitboxPart = Instance.new("Part")
			hitboxPart.Name = "DebugHitbox_" .. player.UserId
			hitboxPart.Shape = Enum.PartType.Ball
			hitboxPart.Anchored = true
			hitboxPart.CanCollide = false
			hitboxPart.CanQuery = false
			hitboxPart.CanTouch = false
			hitboxPart.Transparency = 0.85
			hitboxPart.Material = Enum.Material.Neon
			hitboxPart.Color = Color3.new(1, 0, 0)
			hitboxPart.Parent = workspace
		end
		local hitRange = getHitRange()
		hitboxPart.Size = Vector3.new(hitRange * 2, hitRange * 2, hitRange * 2)
		hitboxPart.CFrame = player.Character.HumanoidRootPart.CFrame
	elseif hitboxPart then
		hitboxPart:Destroy()
	end

	local debugParts = debugFolder:GetChildren()
	local partIndex = 1

	if debugEnabled then
		local function getDebugPart()
			local part = debugParts[partIndex]
			if not part then
				part = Instance.new("Part")
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false 
				part.CanTouch = false 
				part.Material = Enum.Material.Neon
				part.Color = Color3.new(1, 0, 0) 
				part.Size = Vector3.new(0.2, 0.2, 0.2)
				part.Parent = debugFolder
			end
			partIndex = partIndex + 1
			return part
		end

		local floatPoint = Vector3.new(clientState.position.X, gHeight, clientState.position.Z)
		local distToFloat = (clientState.position - floatPoint).Magnitude
		if distToFloat > 0.1 then
			local part = getDebugPart()
			part.Color = Color3.new(0, 0, 1) 
			part.Size = Vector3.new(0.05, 0.05, distToFloat)
			part.CFrame = CFrame.lookAt(clientState.position, floatPoint) * CFrame.new(0, 0, -distToFloat / 2)
			part.Transparency = 0.5
		end

		if clientState.isMoving then
			local ghostState = BallPhysics.new(clientState.position)
			ghostState:deserialize(clientState:serialize())

			local collisionCount = 0
			local simDt = 1 / 60
			local points = { ghostState.position }

			for i = 1, 1200 do
				if collisionCount >= 10 then break end
				ghostState:update(simDt, checkCollision, getGroundHeight(ghostState.position), clientBall.Size.X / 2, function()
					collisionCount = collisionCount + 1
				end)
				if i % 2 == 0 then table.insert(points, ghostState.position) end
				if not ghostState.isMoving then break end
			end

			for i = 1, #points - 1 do
				local p1, p2 = points[i], points[i+1]
				local dist = (p2 - p1).Magnitude
				if dist > 0.1 then
					local part = getDebugPart()
					part.Color = Color3.new(1, 0, 0)
					part.Size = Vector3.new(0.1, 0.1, dist)
					part.CFrame = CFrame.lookAt(p1, p2) * CFrame.new(0, 0, -dist / 2)
					part.Transparency = 0
				end
			end
		end
	end

	for i = partIndex, #debugParts do
		debugParts[i].Transparency = 1
		debugParts[i].CFrame = CFrame.new(0, -1000, 0)
	end
end)
