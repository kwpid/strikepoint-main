local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Vector3 = Vector3
local task = task
local Enum = Enum
local workspace = workspace
local Color3 = Color3
local Instance = Instance
local RaycastParams = RaycastParams
local CFrame = CFrame
local math = math

local BallPhysics = require(ReplicatedStorage.BallPhysics)
local Config = require(ReplicatedStorage.BallConfig)

local RemoteEventsFolder = ReplicatedStorage:WaitForChild(Config.Paths.REMOTE_EVENTS_FOLDER)

local RemoteEvents = {
        ballUpdate = RemoteEventsFolder:WaitForChild("BallUpdateEvent"),
}

local ServerEvents = {}
ServerEvents.ballHit = RemoteEventsFolder:FindFirstChild("ServerBallHit")
if not ServerEvents.ballHit then
        ServerEvents.ballHit = Instance.new("BindableEvent")
        ServerEvents.ballHit.Name = "ServerBallHit"
        ServerEvents.ballHit.Parent = RemoteEventsFolder
end

local ResetBallEvent = RemoteEventsFolder:FindFirstChild("ResetBall")
if not ResetBallEvent then
        ResetBallEvent = Instance.new("BindableEvent")
        ResetBallEvent.Name = "ResetBall"
        ResetBallEvent.Parent = RemoteEventsFolder
end

local GoalScoredEvent = RemoteEventsFolder:FindFirstChild("GoalScored")
if not GoalScoredEvent then
        GoalScoredEvent = Instance.new("BindableEvent")
        GoalScoredEvent.Name = "GoalScored"
        GoalScoredEvent.Parent = RemoteEventsFolder
end

local ClearBallEvent = RemoteEventsFolder:FindFirstChild("ClearBall")
if not ClearBallEvent then
        ClearBallEvent = Instance.new("BindableEvent")
        ClearBallEvent.Name = "ClearBall"
        ClearBallEvent.Parent = RemoteEventsFolder
end

local ClearClientBallEvent = RemoteEventsFolder:FindFirstChild("ClearClientBall")
if not ClearClientBallEvent then
        ClearClientBallEvent = Instance.new("RemoteEvent")
        ClearClientBallEvent.Name = "ClearClientBall"
        ClearClientBallEvent.Parent = RemoteEventsFolder
end

local ballTemplate = ReplicatedStorage:WaitForChild("Ball")

local oldBall = workspace:FindFirstChild("Ball")
if oldBall then oldBall:Destroy() end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function getGameMap(ball)
        return ball.Parent
end

local function setBallVisuals(ball, enabled)
        if not ball then return end
        for _, descendant in ipairs(ball:GetDescendants()) do
                if descendant:IsA("BasePart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
                        descendant.Transparency = enabled and (descendant:GetAttribute("OriginalTransparency") or 0) or 1
                elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
                        descendant.Enabled = enabled
                elseif descendant:IsA("Light") then
                        descendant.Enabled = enabled
                end
        end
end

local ActiveBalls = {}

local function updateRaycastFilter()
        local filterList = {}

        for _, data in pairs(ActiveBalls) do
                if data.object then
                        table.insert(filterList, data.object)
                end
        end

        for _, player in pairs(Players:GetPlayers()) do
                if player.Character then
                        for _, part in pairs(player.Character:GetDescendants()) do
                                if part:IsA("BasePart") then
                                        table.insert(filterList, part)
                                end
                        end
                end
        end

        for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("BasePart") then
                        local name = obj.Name:lower()
                        local isMarker = name == "ballspawn" or name == "t1" or name == "t2" or name:find("plate")
                        local isHitbox = name == "hitbox"
                        local isFloor = name:find("floor") or name:find("field") or name:find("arena")
                        local isTransparent = obj.Transparency >= 0.9 
                        local isMesh = obj:IsA("MeshPart")
                        local isZone = name:find("zone")

                        if isMarker or ((isTransparent or isMesh) and not isHitbox and not isFloor and not isZone) then
                                table.insert(filterList, obj)
                        end
                end
        end

        raycastParams.FilterDescendantsInstances = filterList
end

Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
                task.wait(0.5)
                updateRaycastFilter()
        end)
end)

updateRaycastFilter() 

local function getGroundHeight(position)
        local rayOrigin = Vector3.new(position.X, position.Y + 5, position.Z)
        local rayDirection = Vector3.new(0, -500, 0)
        local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

        if rayResult then
                return rayResult.Position.Y
        end

        return 0
end

local function checkCollision(from, to, ballSize)
        local direction = (to - from)
        local distance = direction.Magnitude
        if distance == 0 then
                return nil
        end

        local rayResult = workspace:Raycast(from, direction.Unit * (distance + ballSize / 2), raycastParams)

        if rayResult and ballObject then
                local hitName = rayResult.Instance.Name:lower()
                if hitName:find("goaldetector") then 
                        local lastTeam = ballObject:GetAttribute("LastTeam")
                        local isRedGoal = hitName:find("red")
                        local isBlueGoal = hitName:find("blue")

                        if (lastTeam == "red" and isRedGoal) or (lastTeam == "blue" and isBlueGoal) then
                                return nil
                        end
                end   
        end

        if rayResult then
                print("Ball Hit:", rayResult.Instance:GetFullName())
        end
        return rayResult
end

RunService.Heartbeat:Connect(function(dt)
        local hasUpdate = false

        for gameId, data in pairs(ActiveBalls) do
                local ball = data.object

                if ball and ball.Parent then
                        local ballState = data.state
                        local ballFrozen = data.frozen
                        local updated = false

                        if not ballFrozen then
                                data.lastGroundCheck = data.lastGroundCheck + dt
                                local currentGroundHeight = 0

                                if data.lastGroundCheck > 0.1 then
                                        currentGroundHeight = getGroundHeight(ballState.position)
                                        data.lastGroundCheck = 0
                                        data.cachedGroundHeight = currentGroundHeight 
                                else
                                        currentGroundHeight = data.cachedGroundHeight or 0
                                end

                                updated = ballState:update(dt, function(a, b) 
                                        return checkCollision(a, b, ball.Size.X) 
                                end, currentGroundHeight, ball.Size.X / 2, function(collision)
                                        if ball:FindFirstChild("Bounce") then
                                                ball.Bounce:Play()
                                        end
                                end)

                                ballState:enforceFloatHeight(currentGroundHeight)

                                local isGrounded = (ballState.position.Y <= currentGroundHeight + Config.Physics.FLOAT_HEIGHT + 0.1)
                                if ball:GetAttribute("Grounded") ~= isGrounded then
                                        ball:SetAttribute("Grounded", isGrounded)
                                end
                                ball:SetAttribute("Velocity", ballState.velocity)
                        end

                        ball.Position = ballState.position
                        ball.Color = ballState.color
                        ball.Transparency = ballState.transparency or 0

                        if not ballFrozen and ballState.isMoving then
                                -- Skip goal detection for 0.5 seconds after ball spawn to prevent instant goals
                                local timeSinceSpawn = tick() - data.spawnTime
                                
                                if timeSinceSpawn > 0.5 then
                                        local map = ball.Parent 
                                        if map then
                                                local redGoal = map:FindFirstChild("GoalDetectorRed", true)
                                                local blueGoal = map:FindFirstChild("GoalDetectorBlue", true)

                                                if not redGoal or not blueGoal then
                                                        warn("Goal detectors not found in map! Red:", redGoal ~= nil, "Blue:", blueGoal ~= nil)
                                                end

                                                local function isPointInPart(point, part, radius)
                                                        radius = radius or 0
                                                        local relativePos = part.CFrame:PointToObjectSpace(point)
                                                        return math.abs(relativePos.X) <= (part.Size.X/2 + radius)
                                                                and math.abs(relativePos.Y) <= (part.Size.Y/2 + radius)
                                                                and math.abs(relativePos.Z) <= (part.Size.Z/2 + radius)
                                                end

                                                if redGoal then
                                                        local dist = (ball.Position - redGoal.Position).Magnitude
                                                        local isInside = isPointInPart(ball.Position, redGoal, ball.Size.X / 2)

                                                        if isInside or dist <= 6 then
                                                                local lastTeam = ball:GetAttribute("LastTeam")
                                                                if lastTeam == "blue" then
                                                                        data.frozen = true
                                                                        ball.Anchored = true
                                                                        setBallVisuals(ball, false)
                                                                        ballState.transparency = 1

                                                                        RemoteEvents.ballUpdate:FireAllClients(ballState:serialize(), gameId)
                                                                        GoalScoredEvent:Fire("blue", gameId, ballState.lastHitter)

                                                                        ball:Destroy()
                                                                        ball = nil
                                                                        ActiveBalls[gameId] = nil
                                                                        return
                                                                end
                                                        end
                                                end

                                                if blueGoal then
                                                        local dist = (ball.Position - blueGoal.Position).Magnitude
                                                        local isInside = isPointInPart(ball.Position, blueGoal, ball.Size.X / 2)

                                                        if isInside or dist <= 6 then
                                                                local lastTeam = ball:GetAttribute("LastTeam")
                                                                if lastTeam == "red" then
                                                                        data.frozen = true
                                                                        ball.Anchored = true
                                                                        setBallVisuals(ball, false)
                                                                        ballState.transparency = 1

                                                                        RemoteEvents.ballUpdate:FireAllClients(ballState:serialize(), gameId)
                                                                        GoalScoredEvent:Fire("red", gameId, ballState.lastHitter)

                                                                        ball:Destroy()
                                                                        ball = nil
                                                                        ActiveBalls[gameId] = nil
                                                                        return
                                                                end
                                                        end
                                                end
                                        end
                                end
                        end

                        data.lastNetworkUpdate = data.lastNetworkUpdate + dt
                        if data.lastNetworkUpdate >= 1 / Config.Network.UPDATE_RATE then
                                if updated or ballState.isMoving or ballFrozen then
                                        local serialized = ballState:serialize()
                                        for _, player in ipairs(Players:GetPlayers()) do
                                                if player:GetAttribute("GameId") == gameId then
                                                        RemoteEvents.ballUpdate:FireClient(player, serialized, gameId)
                                                end
                                        end
                                end
                                data.lastNetworkUpdate = 0
                        end
                else
                        ActiveBalls[gameId] = nil 
                        updateRaycastFilter() 
                end
        end
end)

local lastHitTime = {} 

ServerEvents.ballHit.Event:Connect(function(player, cameraDirection)
        local gameId = player:GetAttribute("GameId")
        if not gameId or not ActiveBalls[gameId] then return end

        local data = ActiveBalls[gameId]
        local ballState = data.state

        if data.frozen then return end

        if cameraDirection.Magnitude < 0.001 then return end

        ballState:applyHit(cameraDirection, nil, player.Name)

        local team = player:GetAttribute("Team")

        if team == "red" then
                ballState.color = Color3.fromRGB(255, 0, 0)
        elseif team == "blue" then
                ballState.color = Color3.fromRGB(0, 0, 255)
        end
        data.object.Color = ballState.color
        data.object:SetAttribute("LastTeam", team)
        ballState.lastHitter = player.Name

        RemoteEvents.ballUpdate:FireAllClients(ballState:serialize(), gameId)
end)

local function SetupBallForGame(position, gameId, parentFolder)
        if not gameId then return end

        local ground = getGroundHeight(position)
        print("BallServer: Spawning at", position, "Detected Ground:", ground)

        local data = ActiveBalls[gameId]
        if data and data.object then
                data.object:Destroy()
                data.object = nil
        end

        local ball = ballTemplate:Clone()
        ball.Name = "Ball" 
        ball.Parent = parentFolder or workspace

        data = {
                object = ball,
                state = nil, 
                frozen = false,
                frozenVelocity = Vector3.zero,
                lastGroundCheck = 0,
                lastNetworkUpdate = 0,
                cachedGroundHeight = ground,
                spawnTime = tick(),
        }
        ActiveBalls[gameId] = data
        updateRaycastFilter()

        local ballState = BallPhysics.new(position)
        ballState.transparency = 0
        ballState.color = Color3.new(1, 1, 1)

        ball.Position = position
        ball.Color = ballState.color
        ball.Anchored = true
        ball.CanCollide = false
        setBallVisuals(ball, true) 
        ball.Transparency = 1
        ball:SetAttribute("LastTeam", "None")
        ball:SetAttribute("GameId", gameId) 

        for _, desc in ipairs(ball:GetDescendants()) do
                if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
                        desc.Transparency = 1
                elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                        desc.Enabled = false
                elseif desc:IsA("Light") then
                        desc.Enabled = false
                end
        end

        ballState.transparency = 0
        ballState.lastHitter = "None"

        data.state = ballState

        ballState:enforceFloatHeight(ground)
        ball.Position = ballState.position

        RemoteEvents.ballUpdate:FireAllClients(ballState:serialize(), gameId)
end

ResetBallEvent.Event:Connect(SetupBallForGame)

ClearBallEvent.Event:Connect(function(gameId)
        if gameId and ActiveBalls[gameId] then
                local data = ActiveBalls[gameId]
                if data.object then
                        data.object:Destroy()
                end
                ActiveBalls[gameId] = nil
                updateRaycastFilter()
        end
end)

local debugResetEvent = RemoteEventsFolder:FindFirstChild("DebugReset")

debugResetEvent.OnServerEvent:Connect(function(player, gameId)
        local isDev = false

        for _, id in ipairs(Config.Debug.DeveloperIds) do
                if player.UserId == id then
                        isDev = true
                        break
                end
        end

        if isDev and gameId and ActiveBalls[gameId] then
                local data = ActiveBalls[gameId]
                local ball = data.object
                local initialGroundHeight = getGroundHeight(ball.Position)
                local spawnPosition = Vector3.new(ball.Position.X, initialGroundHeight + Config.Physics.FLOAT_HEIGHT, ball.Position.Z)
                SetupBallForGame(spawnPosition, gameId, ball.Parent)
        end
end)


local debugFreezeEvent = RemoteEventsFolder:FindFirstChild("DebugFreeze")


debugFreezeEvent.OnServerEvent:Connect(function(player, gameId)
        local isDev = false
        for _, id in ipairs(Config.Debug.DeveloperIds) do
                if player.UserId == id then
                        isDev = true
                        break
                end
        end

        if isDev and gameId and ActiveBalls[gameId] then
                local data = ActiveBalls[gameId]
                data.frozen = true
                data.frozenVelocity = data.state.velocity
        end
end)


local debugUnfreezeEvent = RemoteEventsFolder:FindFirstChild("DebugUnfreeze")

debugUnfreezeEvent.OnServerEvent:Connect(function(player, gameId)
        local isDev = false
        for _, id in ipairs(Config.Debug.DeveloperIds) do
                if player.UserId == id then
                        isDev = true
                        break
                end
        end

        if isDev and gameId and ActiveBalls[gameId] then
                local data = ActiveBalls[gameId]
                data.frozen = false
                data.state.velocity = data.frozenVelocity
        end
end)
