local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Vector3 = Vector3

local Config = require(ReplicatedStorage.BallConfig)

local SWORD_FOLDER = ReplicatedStorage:WaitForChild("AssetManager"):WaitForChild("Swords")
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

ServerEvents.parryCooldown = RemoteEventsFolder:FindFirstChild("ParryCooldownEvent")
if not ServerEvents.parryCooldown then
	ServerEvents.parryCooldown = Instance.new("RemoteEvent")
	ServerEvents.parryCooldown.Name = "ParryCooldownEvent"
	ServerEvents.parryCooldown.Parent = RemoteEventsFolder
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


local function createDefaultSlashEffect(slashMesh, handlePosition, cameraDirection, ballPosition, playerPosition)
	if not slashMesh then 
		warn("No slash mesh provided")
		return 
	end

	local slash = slashMesh:Clone()

	local midpoint = (handlePosition + ballPosition) / 2
	slash.Position = midpoint
	local lookCFrame = CFrame.lookAt(slash.Position, slash.Position + cameraDirection)
	slash.CFrame = lookCFrame * CFrame.Angles(0, math.rad(100), 0)
	slash.CanCollide = false
	slash.Anchored = true
	local originalTransparency = slash.Transparency
	slash.Transparency = 1
	slash.Parent = workspace
	local fadeInInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInTween = TweenService:Create(slash, fadeInInfo, {Transparency = originalTransparency})
	fadeInTween:Play()
	task.delay(0.1, function()
		local fadeOutInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fadeOutTween = TweenService:Create(slash, fadeOutInfo, {Transparency = 1})
		fadeOutTween:Play()
		fadeOutTween.Completed:Connect(function()
			slash:Destroy()
		end)
	end)

	Debris:AddItem(slash, 1)
end

local function createSlashEffect(swordModel, handlePosition, cameraDirection, ballPosition, playerPosition)
	if not swordModel then return end
	local slashModule = swordModel:FindFirstChild("SlashModule")
	if slashModule and slashModule:IsA("ModuleScript") then
		local success, customSlash = pcall(require, slashModule)
		if success and customSlash and typeof(customSlash.CreateSlash) == "function" then
			customSlash.CreateSlash(swordModel, handlePosition, cameraDirection, ballPosition, playerPosition)
			return
		else
			warn("SlashModule found but invalid or missing CreateSlash function for sword: " .. swordModel.Name)
		end
	end

	local slashVFXFolder = swordModel:FindFirstChild("SlashVFX")
	if not slashVFXFolder then 
		warn("No SlashVFX folder found in sword: " .. swordModel.Name)
		return 
	end

	local slashMesh = slashVFXFolder:FindFirstChildOfClass("MeshPart") or slashVFXFolder:FindFirstChild("DefaultSlash")
	if slashMesh then
		createDefaultSlashEffect(slashMesh, handlePosition, cameraDirection, ballPosition, playerPosition)
	else
		warn("No slash mesh found in SlashVFX folder for sword: " .. swordModel.Name)
	end
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

	-- PARRY VFX LOGIC
	local parryVFX = nil
	local AssetManager = ReplicatedStorage:FindFirstChild("AssetManager")
	local vfxTemplate = AssetManager and AssetManager:FindFirstChild("ParryVFX")

	if vfxTemplate then
		parryVFX = vfxTemplate:Clone()
		local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
		if root then
			parryVFX.Parent = root
			for _, emitter in ipairs(parryVFX:GetChildren()) do
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(1)
					emitter.Enabled = true
				end
			end
		else
			parryVFX:Destroy()
			parryVFX = nil
		end
	end

	local function cleanupParryVFX()
		if parryVFX then
			for _, child in ipairs(parryVFX:GetChildren()) do
				if child:IsA("ParticleEmitter") then
					child.Enabled = false
				end
			end
			Debris:AddItem(parryVFX, 2) 
			parryVFX = nil
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
			cleanupParryVFX()
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
			cleanupParryVFX()
			return 
		end

		local distance = (hrp.Position - ball.Position).Magnitude
		local velocity = ball:GetAttribute("Velocity") or Vector3.zero
		local predictedPosition = ball.Position + (velocity * 0.1)
		local predictedDistance = (hrp.Position - predictedPosition).Magnitude

		if distance <= parryWindow.parryRange or predictedDistance <= parryWindow.parryRange then
			print("SwordServer: Hit detected! Distance:", distance, "GameId:", myGameId)
			parryWindow.hitBall = true
			parryWindow.active = false
			disableTrail()
			cleanupParryVFX()

			setBallHitImmunity(player.UserId)

			failTrack:Stop()

			weld.Part0 = attachments.rightArm
			weld.C0 = attachments.swing.CFrame
			weld.C1 = attachments.sword.CFrame * CFrame.Angles(0, 0, math.rad(90))

			local parryTrack = animator:LoadAnimation(animations.parry)
			parryTrack:Play()
			local swordModel = character:FindFirstChild("HipSword")
			createSlashEffect(swordModel, handle.Position, parryWindow.cameraDirection, ball.Position, hrp.Position)

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
			cleanupParryVFX()
			playerData[player.UserId].cooldown = false
			ServerEvents.parryCooldown:FireClient(player, Config.Parry.PARRY_MISS_COOLDOWN)
			playerData[player.UserId].cooldown = true
			task.delay(Config.Parry.PARRY_MISS_COOLDOWN, function()
				playerData[player.UserId].cooldown = false
			end)
		end
	end)

	task.delay(Config.Parry.TIMEOUT, function()
		if parryWindow.active then
			parryWindow.active = false
			disableTrail()
			cleanupParryVFX()
			failTrack:Stop()
			ServerEvents.parryCooldown:FireClient(player, Config.Parry.PARRY_MISS_COOLDOWN)
			playerData[player.UserId].cooldown = true
			task.delay(Config.Parry.PARRY_MISS_COOLDOWN, function()
				playerData[player.UserId].cooldown = false
			end)
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
