local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapManager = {}
local function setupMapsFolder()
	local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
	if not mapsFolder then
		mapsFolder = Instance.new("Folder")
		mapsFolder.Name = "Maps"
		mapsFolder.Parent = ReplicatedStorage
	end


	return mapsFolder
end

local function getAvailableMaps(mode)
	local mapsFolder = setupMapsFolder()
	local targetFolder = mapsFolder:FindFirstChild(mode)
	local maps = {}

	for _, map in ipairs(targetFolder:GetChildren()) do
		if map:IsA("Model") then
			table.insert(maps, map)
		end
	end

	return maps
end

local function selectRandomMap(mode)
	local availableMaps = getAvailableMaps(mode)
	if #availableMaps == 0 then
		warn("MapManager: No maps found in ReplicatedStorage/Maps!")
		return nil
	end

	local randomIndex = math.random(1, #availableMaps)
	return availableMaps[randomIndex]
end


function MapManager.createGameArena(gameId, offsetIndex, mapContainer, mode)
	local selectedMap = selectRandomMap(mode)

	if not selectedMap then
		warn("MapManager: Failed to select a map for game", gameId)
		return nil
	end

	local arena = selectedMap:Clone()
	arena.Name = "Arena_" .. gameId

	local offsetPos = Vector3.new(offsetIndex * 2500, 0, 0)
	arena:PivotTo(arena:GetPivot() + offsetPos)
	arena.Parent = mapContainer
	local refs = {
		BallSpawn = arena:FindFirstChild("BallSpawn"),
		T1 = arena:FindFirstChild("T1"),
		T2 = arena:FindFirstChild("T2"),
		Plate1 = arena:FindFirstChild("Plate1"),
		Plate2 = arena:FindFirstChild("Plate2"),
	}

	if mode == "2v2" then
		refs.T3 = arena:FindFirstChild("T3")
		refs.T4 = arena:FindFirstChild("T4")
		refs.Plate3 = arena:FindFirstChild("Plate3")
		refs.Plate4 = arena:FindFirstChild("Plate4")
	end

	if refs.Plate then refs.Board1 = arena:FindFirstChild("Board1") end
	if refs.Plate2 then refs.Board2 = arena:FindFirstChild("Board2") end
	if refs.Plate3 then refs.Board3 = arena:FindFirstChild("Board3") end
	if refs.Plate4 then refs.Board4 = arena:FindFirstChild("Board4") end

	if not refs.BallSpawn or not refs.T1 or not refs.T2 then
		warn("MapManager: Selected map missing critical parts! Ensure map has BallSpawn, T1, and T2.")
		arena:Destroy()
		return nil
	end

	return arena, refs
end

function MapManager.validateMap(map, mode)
	local required = {"BallSpawn", "T1", "T2"}

	if mode == "2v2" then
		table.insert(required, "T3")
		table.insert(required, "T4")
	end

	for _, partName in ipairs(required) do
		if not map:FindFirstChild(partName) then
			return false, "Map missing required part: " .. partName
		end
	end

	return true
end

return MapManager
