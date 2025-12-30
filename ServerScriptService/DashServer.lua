local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("BallConfig"))
local RemoteEventsFolder = ReplicatedStorage:WaitForChild(Config.Paths.REMOTE_EVENTS_FOLDER)

local dashEvent = RemoteEventsFolder:FindFirstChild("DashEvent")
if not dashEvent then
	dashEvent = Instance.new("RemoteEvent")
	dashEvent.Name = "DashEvent"
	dashEvent.Parent = RemoteEventsFolder
end

local dashCooldownEvent = RemoteEventsFolder:FindFirstChild("DashCooldownEvent")
if not dashCooldownEvent then
	dashCooldownEvent = Instance.new("RemoteEvent")
	dashCooldownEvent.Name = "DashCooldownEvent"
	dashCooldownEvent.Parent = RemoteEventsFolder
end

local playerDashData = {}

local function onDash(player, direction)
	local userId = player.UserId
	local lastDash = playerDashData[userId] or 0

	if tick() - lastDash < Config.Dash.COOLDOWN then
		return
	end

	playerDashData[userId] = tick()
	dashCooldownEvent:FireClient(player, Config.Dash.COOLDOWN)
end

dashEvent.OnServerEvent:Connect(onDash)

Players.PlayerRemoving:Connect(function(player)
	playerDashData[player.UserId] = nil
end)
