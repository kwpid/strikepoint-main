local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.BallConfig)

local RemoteEventsFolder = ReplicatedStorage:WaitForChild(Config.Paths.REMOTE_EVENTS_FOLDER)
local swingEvent = RemoteEventsFolder:WaitForChild("SwingEvent")
local deviceTypeEvent = RemoteEventsFolder:WaitForChild("DeviceTypeEvent")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local isOnCooldown = false

local function detectDeviceType()
        if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
                return "Mobile"
        elseif UserInputService.GamepadEnabled then
                return "Console"
        else
                return "Desktop"
        end
end

task.wait(1)
deviceTypeEvent:FireServer(detectDeviceType())

local function performSwing()
        if isOnCooldown then return end
        
        isOnCooldown = true
        local cameraDirection = camera.CFrame.LookVector
        
        swingEvent:FireServer(cameraDirection)
        
        task.delay(Config.Parry.COOLDOWN, function()
                isOnCooldown = false
        end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                performSwing()
        elseif input.UserInputType == Enum.UserInputType.Touch then
                performSwing()
        elseif input.UserInputType == Enum.UserInputType.Gamepad1 then
                if input.KeyCode == Enum.KeyCode.ButtonR2 or 
                   input.KeyCode == Enum.KeyCode.ButtonR1 or
                   input.KeyCode == Enum.KeyCode.ButtonA then
                        performSwing()
                end
        end
end)

print("Input client initialized (Mouse, Touch, Gamepad support)")
