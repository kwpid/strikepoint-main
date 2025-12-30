local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local HttpService = game:GetService("HttpService")
local workspace = game:GetService("Workspace")

-- CONFIGURATIONS
local CONFIG = {
	MATCH_DURATION = 180,
	KICKOFF_DURATION = 3,
	LOBBY_COUNTDOWN = 5,
	OVERTIME_ENABLED = true,
	XP_REWARDS = {
		WIN = 100,
		LOSS = 20,
		DRAW = 40,
		GOAL = 25
	}
}

local BallConfig = require(ReplicatedStorage:WaitForChild("BallConfig"))
local MapManager = require(script.Parent:WaitForChild("MapManager"))
local DataService = require(ReplicatedStorage:WaitForChild("DataService"))
local Scoreboard = require(script.Parent:WaitForChild("Scoreboard")) 
local Zones = require(ReplicatedStorage.Modules.Zone)

local RemoteEventsFolder = ReplicatedStorage:WaitForChild(BallConfig.Paths.REMOTE_EVENTS_FOLDER)
local ResetBallEvent = RemoteEventsFolder:WaitForChild("ResetBall")
local GoalScoredEvent = RemoteEventsFolder:WaitForChild("GoalScored")
local ClearBallEvent = RemoteEventsFolder:WaitForChild("ClearBall")
local ClearClientBallEvent = RemoteEventsFolder:WaitForChild("ClearClientBall")

local MatchManager = {}
local GameInstance = {}
GameInstance.__index = GameInstance

local ActiveGames = {}
local AllStages = {}
local StageData = {}

local function setupTeams()
	if not Teams:FindFirstChild("Lobby") then
		local lobby = Instance.new("Team")
		lobby.Name = "Lobby"
		lobby.TeamColor = BrickColor.new("White")
		lobby.AutoAssignable = true
		lobby.Parent = Teams
	end
	if not Teams:FindFirstChild("In-Game") then
		local inGame = Instance.new("Team")
		inGame.Name = "In-Game"
		inGame.TeamColor = BrickColor.new("Bright red")
		inGame.AutoAssignable = false
		inGame.Parent = Teams
	end
end

function GameInstance.new(gameId, offsetIndex, mapType)
	local self = setmetatable({}, GameInstance)
	self.GameId = gameId
	self.OffsetIndex = offsetIndex
	self.Players = {}
	self.Scores = { red = 0, blue = 0 }
	self.RemainingTime = CONFIG.MATCH_DURATION
	self.InProgress = false
	self.TimerRunning = false
	self.IsOvertime = false
	self.OvertimeSeconds = 0
	self.KickoffInProgress = false

	local GamesFolder = workspace:FindFirstChild("Games") or Instance.new("Folder", workspace)
	GamesFolder.Name = "Games"

	local gameContainer = Instance.new("Folder")
	gameContainer.Name = "Game_" .. gameId
	gameContainer.Parent = GamesFolder
	self.GameContainer = gameContainer

	self.Arena, self.Refs = MapManager.createGameArena(gameId, offsetIndex, gameContainer, mapType)

	if not self.Arena then
		warn("MatchManager: Failed to create game arena for", gameId)
		return nil
	end

	if self.Refs.Plate1 and not self.Refs.Board1 then self.Refs.Board1 = self.Refs.Plate1:FindFirstChild("Board") end
	if self.Refs.Plate2 and not self.Refs.Board2 then self.Refs.Board2 = self.Refs.Plate2:FindFirstChild("Board") end

	return self
end

function GameInstance:Start(p1, p2)
	self.Players = { p1, p2 }
	self.InProgress = true

	p1:SetAttribute("GameId", self.GameId)
	p1:SetAttribute("Team", "red")
	p1.Team = Teams:FindFirstChild("In-Game")
	local function setCharGroup(player, group)
		if player.Character then

			for _, part in ipairs(player.Character:GetDescendants()) do
				if part:IsA("BasePart") then part.CollisionGroup = group end
			end
			player.Character.DescendantAdded:Connect(function(part)
				if part:IsA("BasePart") then part.CollisionGroup = group end
			end)
			print("MatchManager: Set collision group", group, "for", player.Name)
		end
	end

	p2:SetAttribute("GameId", self.GameId)
	p2:SetAttribute("Team", "blue")
	p2.Team = Teams:FindFirstChild("In-Game")

	setCharGroup(p1, "RedPlayer")
	setCharGroup(p2, "BluePlayer")

	self:ConnectDeaths()
	self:ConnectDisconnects()

	Scoreboard.UpdateBoard(p1, self.Refs.Board1, Color3.new(1, 0, 0))
	Scoreboard.UpdateBoard(p2, self.Refs.Board2, Color3.new(0, 0, 1))

	if p1.Character and p1.Character.PrimaryPart then
		p1.Character.PrimaryPart.CFrame = self.Refs.T1.CFrame + Vector3.new(0, 3, 0)
	end
	if p2.Character and p2.Character.PrimaryPart then
		p2.Character.PrimaryPart.CFrame = self.Refs.T2.CFrame + Vector3.new(0, 3, 0)
	end

	local initialTimeText = Scoreboard.FormatTime(self.RemainingTime, false)
	Scoreboard.SetGameUIVisibility(self.Players, true, initialTimeText)
	Scoreboard.UpdateScoreUI(self.Players, self.Scores)

	task.spawn(function() self:Kickoff() end)
	task.spawn(function() self:RunTimer() end)
end

function GameInstance:Kickoff()
	self.TimerRunning = false
	self.KickoffInProgress = true
	self:SetControls(false)

	if self.Players[1].Character and self.Players[1].Character.PrimaryPart then
		self.Players[1].Character.PrimaryPart.CFrame = self.Refs.T1.CFrame + Vector3.new(0, 3, 0)
	end
	if self.Players[2].Character and self.Players[2].Character.PrimaryPart then
		self.Players[2].Character.PrimaryPart.CFrame = self.Refs.T2.CFrame + Vector3.new(0, 3, 0)
	end

	if self.Refs.BallSpawn then
		ResetBallEvent:Fire(self.Refs.BallSpawn.Position, self.GameId, self.Arena)
	end

	for i = CONFIG.KICKOFF_DURATION, 1, -1 do
		Scoreboard.SetCountdownText(self.Players, tostring(i))
		task.wait(1)
	end
	Scoreboard.SetCountdownText(self.Players, "GO!")

	self.KickoffInProgress = false
	self:SetControls(true)
	self.TimerRunning = true
	task.wait(1)
	Scoreboard.SetCountdownText(self.Players, "")
end

function GameInstance:RunTimer()
	while self.InProgress do
		if self.TimerRunning then
			if not self.IsOvertime then
				if self.RemainingTime > 0 then
					self.RemainingTime = self.RemainingTime - 1
				end

				Scoreboard.UpdateClockUI(self.Players, Scoreboard.FormatTime(self.RemainingTime, false))

				if self.RemainingTime <= 0 then
					local ball = self.Arena:FindFirstChild("Ball", true)
					local isGrounded = not ball or ball:GetAttribute("Grounded")

					if isGrounded then
						if self.Scores.red == self.Scores.blue and CONFIG.OVERTIME_ENABLED then
							self.IsOvertime = true
							self.TimerRunning = false
							self:Kickoff()
						else
							self:EndGame("Time Limit")
							break
						end
					else
						while self.InProgress do
							task.wait(1)
							ball = self.Arena:FindFirstChild("Ball", true)
							isGrounded = not ball or ball:GetAttribute("Grounded") == true
							if isGrounded then break end
						end
						if self.Scores.red == self.Scores.blue and CONFIG.OVERTIME_ENABLED then
							self.IsOvertime = true
							self.TimerRunning = false
							self:Kickoff()
						else
							self:EndGame("Time Limit")
							break
						end
					end
				end
			else
				self.OvertimeSeconds = self.OvertimeSeconds + 1
				Scoreboard.UpdateClockUI(self.Players, Scoreboard.FormatTime(self.OvertimeSeconds, true))
			end
		end
		task.wait(1)
	end
end

function GameInstance:EndGame(reason, winningTeam)
	if not self.InProgress then return end
	self.InProgress = false
	self.TimerRunning = false

	self:CleanupBalls()
	Scoreboard.SetGameUIVisibility(self.Players, false)

	if not winningTeam then
		if self.Scores.red > self.Scores.blue then
			winningTeam = "red"
		elseif self.Scores.blue > self.Scores.red then
			winningTeam = "blue"
		end
	end

	for _, p in ipairs(self.Players) do
		if p.Parent then
			local playerTeam = p:GetAttribute("Team")
			if winningTeam and playerTeam == winningTeam then
				DataService.AddWin(p)
				DataService.AddXP(p, CONFIG.XP_REWARDS.WIN)
			elseif winningTeam then
				DataService.AddLoss(p)
				DataService.AddXP(p, CONFIG.XP_REWARDS.LOSS)
			else
				DataService.AddXP(p, CONFIG.XP_REWARDS.DRAW)
			end

			p:SetAttribute("GameId", nil)
			p:SetAttribute("Team", nil)
			p.Team = Teams:FindFirstChild("Lobby")
			p:LoadCharacter()
		end
	end

	if self.GameContainer then self.GameContainer:Destroy() end
	ActiveGames[self.GameId] = nil
end

function GameInstance:CleanupBalls()
	ClearBallEvent:Fire(self.GameId)
	for _, p in ipairs(self.Players) do
		if p.Parent then ClearClientBallEvent:FireClient(p, self.GameId) end
	end
end

function GameInstance:SetControls(enabled)
	self.StoredSpeeds = self.StoredSpeeds or {}
	for _, p in ipairs(self.Players) do
		if p.Character then
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				if not enabled then
					if hum.WalkSpeed > 0 then
						self.StoredSpeeds[p.UserId] = { ws = hum.WalkSpeed }
					end
					hum.WalkSpeed = 0
				else
					local stored = self.StoredSpeeds[p.UserId]
					hum.WalkSpeed = stored and stored.ws or 16
				end
			end
			p.Character:SetAttribute("FeaturesLocked", not enabled)
		end
	end
end

function GameInstance:ConnectDeaths()
	for _, p in ipairs(self.Players) do
		if p.Character then
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Died:Connect(function()
					if self.InProgress then
						local winner = (p == self.Players[1]) and "blue" or "red"
						self:EndGame("Player Died", winner)
					end
				end)
			end
		end
	end
end

function GameInstance:ConnectDisconnects()
	for _, p in ipairs(self.Players) do
		local playerTeam = p:GetAttribute("Team")
		task.spawn(function()
			repeat task.wait() until not p.Parent or not self.InProgress
			if not self.InProgress then return end
			if not p.Parent then
				local winningTeam = (playerTeam == "red") and "blue" or "red"
				self:EndGame("Player Left", winningTeam)
			end
		end)
	end
end

local function CancelLobbyCountdown(stageIndex)
	local stage = StageData[stageIndex]
	if not stage then return end
	if stage.countdownTask then
		task.cancel(stage.countdownTask)
		stage.countdownTask = nil
	end
	if stage.queuedP1 then Scoreboard.UpdateLobbyBoard(stage.lobbyRef.Board1, stage.queuedP1) end
	if stage.queuedP2 then Scoreboard.UpdateLobbyBoard(stage.lobbyRef.Board2, stage.queuedP2) end
	Scoreboard.UpdateStatusText(stage.lobbyRef, "Waiting for Players...")
end

local function TryStartGameInStage(stageIndex)
	local stage = StageData[stageIndex]
	if not stage or not stage.queuedP1 or not stage.queuedP2 then return end

	local p1, p2 = stage.queuedP1, stage.queuedP2
	local usedIndices = {}
	for _, g in pairs(ActiveGames) do usedIndices[g.OffsetIndex] = true end
	local freeIndex = 0
	while usedIndices[freeIndex] do freeIndex = freeIndex + 1 end

	local gameId = HttpService:GenerateGUID(false)
	local newGame = GameInstance.new(gameId, freeIndex, "1v1")
	if newGame then
		stage.queuedP1 = nil
		stage.queuedP2 = nil
		ActiveGames[gameId] = newGame
		newGame:Start(p1, p2)
	end
end

local function StartLobbyCountdown(stageIndex)
	local stage = StageData[stageIndex]
	if not stage or stage.countdownTask then return end

	stage.countdownTask = task.spawn(function()
		for i = CONFIG.LOBBY_COUNTDOWN, 1, -1 do
			local msg = "Starting in " .. i
			if stage.queuedP1 then stage.lobbyRef.Board1.SurfaceGui.Frame.PlayerName.Text = msg end
			if stage.queuedP2 then stage.lobbyRef.Board2.SurfaceGui.Frame.PlayerName.Text = msg end
			Scoreboard.UpdateStatusText(stage.lobbyRef, msg)
			task.wait(1)
		end
		stage.countdownTask = nil
		Scoreboard.UpdateStatusText(stage.lobbyRef, "Waiting for Players...")
		if stage.queuedP1 and stage.queuedP2 then
			Scoreboard.UpdateLobbyBoard(stage.lobbyRef.Board1, nil)
			Scoreboard.UpdateLobbyBoard(stage.lobbyRef.Board2, nil)
			TryStartGameInStage(stageIndex)
		else
			CancelLobbyCountdown(stageIndex)
		end
	end)
end

function MatchManager.Init()
	setupTeams()

	local StagesFolder = workspace:FindFirstChild("Stages")
	if StagesFolder then
		for _, stage in ipairs(StagesFolder:GetChildren()) do
			if stage:IsA("Folder") or stage:IsA("Model") then table.insert(AllStages, stage) end
		end
	end
	if #AllStages == 0 then
		local singleStage = workspace:FindFirstChild("Stage")
		if singleStage then table.insert(AllStages, singleStage) end
	end

	for stageIndex, stageFolder in ipairs(AllStages) do
		local lobbyRef = {
			Plate1 = stageFolder:WaitForChild("Plate1").Zone,
			Plate2 = stageFolder:WaitForChild("Plate2").Zone,
			Board1 = stageFolder:WaitForChild("Plate1").Board,
			Board2 = stageFolder:WaitForChild("Plate2").Board,
			MainBoard = stageFolder:WaitForChild("MainBoard"),
		}
		local zone1 = Zones.new(lobbyRef.Plate1)
		local zone2 = Zones.new(lobbyRef.Plate2)
		StageData[stageIndex] = { zone1 = zone1, zone2 = zone2, queuedP1 = nil, queuedP2 = nil, lobbyRef = lobbyRef }

		zone1.playerEntered:Connect(function(player)
			local data = StageData[stageIndex]
			if not data.queuedP1 then
				data.queuedP1 = player
				Scoreboard.UpdateLobbyBoard(data.lobbyRef.Board1, player)
				if data.queuedP2 then StartLobbyCountdown(stageIndex) end
			end
		end)
		zone1.playerExited:Connect(function(player)
			local data = StageData[stageIndex]
			if data.queuedP1 == player then
				data.queuedP1 = nil
				Scoreboard.UpdateLobbyBoard(data.lobbyRef.Board1, nil)
				CancelLobbyCountdown(stageIndex)
			end
		end)
		zone2.playerEntered:Connect(function(player)
			local data = StageData[stageIndex]
			if not data.queuedP2 then
				data.queuedP2 = player
				Scoreboard.UpdateLobbyBoard(data.lobbyRef.Board2, player)
				if data.queuedP1 then StartLobbyCountdown(stageIndex) end
			end
		end)
		zone2.playerExited:Connect(function(player)
			local data = StageData[stageIndex]
			if data.queuedP2 == player then
				data.queuedP2 = nil
				Scoreboard.UpdateLobbyBoard(data.lobbyRef.Board2, nil)
				CancelLobbyCountdown(stageIndex)
			end
		end)
	end

	GoalScoredEvent.Event:Connect(function(team, gameId, hitterName)
		local gameInst = ActiveGames[gameId]
		if gameInst and gameInst.InProgress then
			gameInst.TimerRunning = false
			if team == "red" then gameInst.Scores.red = gameInst.Scores.red + 1 end
			if team == "blue" then gameInst.Scores.blue = gameInst.Scores.blue + 1 end

			local hitPlayer = Players:FindFirstChild(hitterName)
			local nameToDisplay = hitPlayer and hitPlayer.DisplayName or hitterName

			Scoreboard.UpdateScoreUI(gameInst.Players, gameInst.Scores)
			Scoreboard.ShowGoalUI(gameInst.Players, nameToDisplay)

			if hitPlayer then
				DataService.AddGoal(hitPlayer)
				DataService.AddXP(hitPlayer, CONFIG.XP_REWARDS.GOAL)
			end

			if gameInst.IsOvertime then
				task.wait(2)
				gameInst:EndGame("Buzzer Goal")
			else
				task.wait(2)
				gameInst:SetControls(false)
				task.wait(1)
				if gameInst.InProgress then gameInst:Kickoff() end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local gid = player:GetAttribute("GameId")
		if gid and ActiveGames[gid] then
			ActiveGames[gid]:EndGame("Player Left")
		end
	end)
end

return MatchManager
