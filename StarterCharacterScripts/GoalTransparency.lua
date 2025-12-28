local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = script.Parent
local camera = workspace.CurrentCamera

local FADED_TRANSPARENCY = 0.8
local fadingParts = {}

function updateTransparency()
	local head = character:FindFirstChild("Head")
	if not head then return end
	
	local ignoreList = {character}
	local obstructingParts = camera:GetPartsObscuringTarget({head.Position}, ignoreList)
	
	local currentFrameObstructing = {}
	
	for _, part in ipairs(obstructingParts) do
		if part.Name == "Main" and part:IsA("BasePart") then
			currentFrameObstructing[part] = true
			
			if not fadingParts[part] then
				fadingParts[part] = part.Transparency
				part.Transparency = FADED_TRANSPARENCY
			end
		end
	end
	
	for part, originalTransparency in pairs(fadingParts) do
		if not currentFrameObstructing[part] then
			part.Transparency = originalTransparency
			fadingParts[part] = nil
		end
	end
end

RunService.RenderStepped:Connect(updateTransparency)
