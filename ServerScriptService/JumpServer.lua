local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(ReplicatedStorage:WaitForChild("BallConfig"))
local RemoteEventsFolder = ReplicatedStorage:WaitForChild(Config.Paths.REMOTE_EVENTS_FOLDER)
local doubleJumpEvent = RemoteEventsFolder:WaitForChild("DoubleJumpEvent")
local jumpEffect = ReplicatedStorage:FindFirstChild("JumpEffect")

doubleJumpEvent.OnServerEvent:Connect(function(player)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			doubleJumpEvent:FireClient(otherPlayer, player)
		end
	end
end)
-- this script literally just makes it so eveyrone can see the jump effect
