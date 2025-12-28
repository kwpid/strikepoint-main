local Players = game:GetService("Players")
local Enum = Enum
local Color3 = Color3

local Scoreboard = {}

-- Helper to format time
local function formatTime(seconds, isOvertime)
	local min = math.floor(math.abs(seconds) / 60)
	local sec = math.abs(seconds) % 60
	if isOvertime then
		return string.format("+%d:%02d", min, sec)
	else
		return string.format("%d:%02d", min, sec)
	end
end

function Scoreboard.UpdateBoard(player, boardInfo, color)
	if not boardInfo then
		warn("Scoreboard: boardInfo is nil")
		return
	end

	local surface = boardInfo:FindFirstChild("SurfaceGui")
	if surface and surface:FindFirstChild("Frame") then
		local frame = surface.Frame
		frame.PlayerName.Text = player.DisplayName
		if boardInfo.Parent and boardInfo.Parent:FindFirstChild("Union") then
			boardInfo.Parent.Union.Color = color
		end
		task.spawn(function()
			local content = Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420)
			frame.PlayerIcon.Image = content
		end)
	end
end

function Scoreboard.UpdateLobbyBoard(board, player)
	local surface = board:FindFirstChild("SurfaceGui")
	if not surface then return end
	local frame = surface:FindFirstChild("Frame")
	if not frame then return end

	if player then
		frame.PlayerName.Text = player.DisplayName
		if board.Parent and board.Parent:FindFirstChild("Union") then
			board.Parent.Union.Color = Color3.new(0, 1, 0)
		end
		task.spawn(function()
			frame.PlayerIcon.Image = Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420)
		end)
	else
		frame.PlayerName.Text = "Waiting..."
		if board.Parent and board.Parent:FindFirstChild("Union") then
			board.Parent.Union.Color = Color3.new(1, 1, 1)
		end
		frame.PlayerIcon.Image = "rbxassetid://9319891706"
	end
end

function Scoreboard.SetGameUIVisibility(players, visible, initialTimeText)
	for _, p in ipairs(players) do
		local gui = p:FindFirstChild("PlayerGui")
		if gui and gui:FindFirstChild("GameGUI") then
			local screen = gui.GameGUI:FindFirstChild("GameScreen")
			if screen then
				screen.Visible = visible
				if visible and initialTimeText and screen:FindFirstChild("Clock") then
					screen.Clock.ClockText.Text = initialTimeText
				end
			end
		end
	end
end

function Scoreboard.UpdateScoreUI(players, scores)
	for _, p in ipairs(players) do
		local gui = p:FindFirstChild("PlayerGui")
		if gui and gui:FindFirstChild("GameGUI") then
			local screen = gui.GameGUI:FindFirstChild("GameScreen")
			if screen then
				if screen:FindFirstChild("Red") then screen.Red.RedScore.Text = tostring(scores.red) end
				if screen:FindFirstChild("Blue") then screen.Blue.BlueScore.Text = tostring(scores.blue) end
			end
		end
	end
end

function Scoreboard.UpdateClockUI(players, timeText)
	for _, p in ipairs(players) do
		local gui = p:FindFirstChild("PlayerGui")
		if gui and gui:FindFirstChild("GameGUI") and gui.GameGUI:FindFirstChild("GameScreen") then
			local clock = gui.GameGUI.GameScreen:FindFirstChild("Clock")
			if clock then clock.ClockText.Text = timeText end
		end
	end
end

function Scoreboard.SetCountdownText(players, txt)
	for _, p in ipairs(players) do
		local gui = p:FindFirstChild("PlayerGui")
		if gui and gui:FindFirstChild("GameGUI") then
			local cd = gui.GameGUI:FindFirstChild("Countdown")
			if cd then
				cd.Visible = (txt ~= "")
				cd.TextLabel.Text = txt
			end
		end
	end
end

function Scoreboard.ShowGoalUI(players, playerName)
	for _, p in ipairs(players) do
		local gui = p:FindFirstChild("PlayerGui")
		if gui and gui:FindFirstChild("GameGUI") then
			local goalFrame = gui.GameGUI:FindFirstChild("Goal")
			if goalFrame then
				goalFrame.Visible = true
				if goalFrame:FindFirstChild("TextLabel") then
					goalFrame.TextLabel.Text = (playerName or "Someone") .. " SCORED!"
				end
				task.delay(3, function()
					goalFrame.Visible = false
				end)
			end
		end
	end
end

function Scoreboard.UpdateStatusText(lobbyRef, msg)
	local mainSurf = lobbyRef.MainBoard:FindFirstChild("SurfaceGui")
	if mainSurf and mainSurf:FindFirstChild("Frame") then
		local status = mainSurf.Frame:FindFirstChild("Status")
		if status then
			status.Text = msg
		else
			local lbl = mainSurf.Frame:FindFirstChild("PlayerName") or mainSurf.Frame:FindFirstChildOfClass("TextLabel")
			if lbl then lbl.Text = msg end
		end
	end
end

function Scoreboard.FormatTime(seconds, isOvertime)
	return formatTime(seconds, isOvertime)
end

return Scoreboard
