local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Vector3 = Vector3

local Config = require(ReplicatedStorage.BallConfig)

local SWORD_FOLDER = ReplicatedStorage:WaitForChild("Swords")
local DEFAULT_SWORD_NAME = "DefaultSword"
local DUMMY = workspace:WaitForChild("Dummy")
local DUMMY_TORSO_ATTACHMENT = DUMMY:WaitForChild("Torso"):WaitForChild("SwordAttachment")
local DUMMY_ARM_ATTACHMENT = DUMMY:WaitForChild("Right Arm"):WaitForChild("SwordSwing")

local RemoteEventsFolder = ReplicatedStorage:WaitForChild(Config.Paths.REMOTE_EVENTS_FOLDER)

local RemoteEvents = {
	swing = RemoteEventsFolder:WaitForChild("SwingEvent"),
	deviceType = RemoteEventsFolder:WaitForChild("DeviceTypeEvent"),
}

local ServerEvents = {}
ServerEvents.ballHit = RemoteEventsFolder:FindFirstChild("ServerBallHit")
if not ServerEvents.ballHit then
	ServerEvents.ballHit = Instance.new("BindableEvent")
	ServerEvents.ballHit.Name = "ServerBallHit"
	ServerEvents.ballHit.Parent = RemoteEventsFolder
end

local playerData = {}
local ballHitImmunity = {}

local VALID_DEVICE_TYPES = {
	["Mobile"] = true,
	["Desktop"] = true,
	["Console"] = true,
}

local function cloneAttachment(parent, template, name)
	if parent:FindFirstChild(name) then return end
	local cloned = template:Clone()
	cloned.Name = name
	cloned.Parent = parent
end

local function equipSword(character, swordModel)
	local existing = character:FindFirstChild("HipSword")
	if existing then existing:Destroy() end
	local existingWeld = character:FindFirstChild("Torso") and character.Torso:FindFirstChild("SwordWeld")
	if existingWeld then existingWeld:Destroy() end

	local torso = character:FindFirstChild("Torso")
	local rightArm = character:FindFirstChild("Right Arm")
	if not torso or not rightArm then return end

	cloneAttachment(torso, DUMMY_TORSO_ATTACHMENT, "SwordAttachment")
	cloneAttachment(rightArm, DUMMY_ARM_ATTACHMENT, "SwordSwing")

	local swordClone = swordModel:Clone()
	swordClone.Name = "HipSword"
	swordClone.Parent = character

	local handle = swordClone:FindFirstChild("Handle")
	if not handle then return end

	local swordAttachment = handle:FindFirstChild("SwordAttachment")
	local torsoAttachment = torso:FindFirstChild("SwordAttachment")

	if swordAttachment and torsoAttachment then
		local weld = Instance.new("Weld")
		weld.Name = "SwordWeld"
		weld.Part0 = torso
		weld.Part1 = handle
		weld.C0 = torsoAttachment.CFrame
		weld.C1 = swordAttachment.CFrame
		weld.Parent = torso
	end
end

local function isBallInHitImmunity(userId)
	if not ballHitImmunity[userId] then return false end
	return tick() - ballHitImmunity[userId] < Config.Parry.HIT_IMMUNITY_TIME
end

local function setBallHitImmunity(userId)
	ballHitImmunity[userId] = tick()
end

local function createParryWindow(player, character, animator, animations, weld, attachments, cameraDirection, handle)
	local data = playerData[player.UserId]
	local parryRange = Config.Parry.RANGE

	if data and data.deviceType == "Mobile" then
		parryRange = Config.Parry.MOBILE_RANGE
	elseif data and data.deviceType == "Console" then
		parryRange = Config.Parry.CONSOLE_RANGE
	end

	-- trail manager
	local trail = nil
	local att0 = handle:FindFirstChild("att0")
	if att0 then
		trail = att0:FindFirstChild("slash")
		if trail and trail:IsA("Trail") then
			trail.Enabled = true
		end
	end

	local function disableTrail()
		if trail then
			trail.Enabled = false
		end
	end

	local parryWindow = {
		active = true,
		hitBall = false,
		connection = nil,
		startTime = tick(),
		cameraDirection = cameraDirection,
		parryRange = parryRange,
	}

	local failTrack = animator:LoadAnimation(animations.fail)
	failTrack:Play()

	parryWindow.connection = RunService.Heartbeat:Connect(function()
		if not parryWindow.active then
			parryWindow.connection:Disconnect()
			disableTrail()
			return
		end

		if parryWindow.hitBall then return end

		local myGameId = player:GetAttribute("GameId")
		local ball = nil
		if not parryWindow.cachedBall then
			for _, desc in ipairs(workspace:GetDescendants()) do
				if desc.Name == "Ball" and desc:GetAttribute("GameId") == myGameId then
					parryWindow.cachedBall = desc
					break
				end
			end
		end
		ball = parryWindow.cachedBall

		if not ball then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then 
			parryWindow.active = false
			disableTrail()
			return 
		end

		if isBallInHitImmunity(player.UserId) then
			return
		end

		local timeSinceStart = tick() - parryWindow.startTime
		if timeSinceStart < Config.Parry.MIN_PARRY_TIME then
			return
		end

		local distance = (hrp.Position - ball.Position).Magnitude
		local velocity = ball:GetAttribute("Velocity") or Vector3.zero
		local predictedPosition = ball.Position + (velocity * 0.1)
		local predictedDistance = (hrp.Position - predictedPosition).Magnitude

		if distance <= parryWindow.parryRange or predictedDistance <= parryWindow.parryRange then
			parryWindow.hitBall = true
			parryWindow.active = false
			disableTrail()

			setBallHitImmunity(player.UserId)

			failTrack:Stop()

			weld.Part0 = attachments.rightArm
			weld.C0 = attachments.swing.CFrame
			weld.C1 = attachments.sword.CFrame * CFrame.Angles(0, 0, math.rad(90))

			local parryTrack = animator:LoadAnimation(animations.parry)
			parryTrack:Play()

			task.wait(0.05)
			ServerEvents.ballHit:Fire(player, parryWindow.cameraDirection)

			parryTrack.Stopped:Connect(function()
				weld.Part0 = attachments.torso
				weld.C0 = attachments.torsoAttachment.CFrame
				weld.C1 = attachments.sword.CFrame
				disableTrail()
			end)

			playerData[player.UserId].cooldown = false
		end
	end)

	failTrack.Stopped:Connect(function()
		if parryWindow.active then
			parryWindow.active = false
			disableTrail()
			playerData[player.UserId].cooldown = false
		end
	end)

	task.delay(Config.Parry.TIMEOUT, function()
		if parryWindow.active then
			parryWindow.active = false
			disableTrail()
			failTrack:Stop()
			playerData[player.UserId].cooldown = false
		end
	end)

	return parryWindow
end

local function onSwing(player, cameraDirection)
	if not cameraDirection or typeof(cameraDirection) ~= "Vector3" then return end

	if cameraDirection.Magnitude < 0.001 then
		warn("Invalid camera direction from player: " .. player.Name)
		return
	end

	local character = player.Character
	if not character then return end

	local data = playerData[player.UserId]
	if not data or data.cooldown then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local sword = character:FindFirstChild("HipSword")
	if not sword then return end

	local handle = sword:FindFirstChild("Handle")
	if not handle then return end

	local animations = {
		parry = handle:FindFirstChild("Parry"),
		fail = handle:FindFirstChild("ParryFail"),
	}

	if not animations.parry or not animations.fail then
		warn("Animations missing for player: " .. player.Name)
		return
	end

	data.cooldown = true

	local torso = character:FindFirstChild("Torso")
	local rightArm = character:FindFirstChild("Right Arm")

	if not torso or not rightArm then
		data.cooldown = false
		return
	end

	local attachments = {
		torso = torso,
		rightArm = rightArm,
		torsoAttachment = torso:FindFirstChild("SwordAttachment"),
		swing = rightArm:FindFirstChild("SwordSwing"),
		sword = handle:FindFirstChild("SwordAttachment"),
	}

	if not attachments.torsoAttachment or not attachments.swing or not attachments.sword then
		data.cooldown = false
		return
	end

	local weld = torso:FindFirstChild("SwordWeld")
	if not weld then
		data.cooldown = false
		return
	end

	createParryWindow(player, character, animator, animations, weld, attachments, cameraDirection, handle)
end

local function onDeviceType(player, deviceType)
	if not VALID_DEVICE_TYPES[deviceType] then
		warn("Invalid device type from player: " .. player.Name)
		return
	end

	local data = playerData[player.UserId]
	if data then
		if data.deviceType then
			warn("Player " .. player.Name .. " attempted to change device type")
			return
		end
		data.deviceType = deviceType
	end
end

RemoteEvents.swing.OnServerEvent:Connect(onSwing)
RemoteEvents.deviceType.OnServerEvent:Connect(onDeviceType)

local function onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	local equippedName = "DefaultSword"
	if _G.DataService then
		equippedName = _G.DataService.GetEquippedSword(player)
	end

	local swordModel = SWORD_FOLDER:FindFirstChild(equippedName)
	if swordModel then
		task.wait(0.5)
		equipSword(character, swordModel)
	else
		local firstSword = SWORD_FOLDER:GetChildren()[1]
		if firstSword then
			equipSword(character, firstSword)
		end
	end

	character:GetAttributeChangedSignal("EquippedSword"):Connect(function()
		local newSwordName = character:GetAttribute("EquippedSword")
		if newSwordName and newSwordName ~= "None" then
			local model = SWORD_FOLDER:FindFirstChild(newSwordName)
			if model then
				equipSword(character, model)
			end
		else

			local existing = character:FindFirstChild("HipSword")
			if existing then existing:Destroy() end
		end
	end)
end

local function onPlayerAdded(player)
	playerData[player.UserId] = {
		cooldown = false,
		deviceType = nil,
	}

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

local function onPlayerRemoving(player)
	playerData[player.UserId] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in pairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
