local Scripts = script.Parent
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local Config = require(Scripts.Configurations)
local AntiCheatData = require(Scripts.AntiCheatData)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local ExpectedHandshakes = {}
local RemoteThrottles = {}
local AntiCheat = {}
local ServiceMap = {}

local MAX_REMOTES_PER_SECOND = 10
local MAX_VERTICAL_SPEED = 30
local FLY_HOVER_GRACE = 3
local FLY_HOVER_THRESHOLD = 1.0
local SPEED_VIOLATION_THRESHOLD = 3
local FLY_VIOLATION_THRESHOLD = 3
local MIN_ELAPSED = 0.05
local MAX_ELAPSED = 0.3
local SAVE_INTERVAL = 2
local RUBBERBAND_COOLDOWN = 3
local POST_RUBBERBAND_IMMUNITY = 2.5
local MAX_ERROR_LOGS = 100

local BlacklistedTerms = {
	"httpget", "loadstring", "getgenv", "getrawmetatable",
	"hookmetamethod", "hookfunction", "newcclosure", "replaceclosure",
	"synapse", "krnl", "fluxus", "xeno", "madium", "wave",
	"dex", "remotespy", "rayfield", "electron", "oxygen",
	"celery", "scriptware", "exploit", "executor", "Injector"
}

local BlacklistedPatterns = {
	"get.*env",
	"hook.*method",
	"hook.*function",
	"load.*string",
	"http.*get",
	"raw.*equal",
	"set.*readonly",
	"make.*writeable",
}

local RecentlyFlagged = {}
local PlayerMovementData = {}

local function AppendErrorLog(player: Player, logType: string, message: string, source: string)
	local Data = AntiCheatData.GetData(player)
	if not Data then return end
	if not Data.ErrorLogs then Data.ErrorLogs = {} end

	if #Data.ErrorLogs >= MAX_ERROR_LOGS then
		table.remove(Data.ErrorLogs, 1)
	end

	table.insert(Data.ErrorLogs, {
		Type = logType,
		Message = message,
		Source = source,
		Timestamp = os.time(),
	})
end

local function ObfuscateServices()
	local namingTargets = {
		{ service = game:GetService("Workspace") },
		{ service = game:GetService("Lighting") },
		{ service = game:GetService("MaterialService") },
		{ service = game:GetService("ReplicatedFirst") },
		{ service = game:GetService("ReplicatedStorage") },
		{ service = game:GetService("StarterGui") },
		{ service = game:GetService("StarterPack") },
		{ service = game:GetService("StarterPlayer") },
		{ service = game:GetService("Teams") },
		{ service = game:GetService("SoundService") },
		{ service = game:GetService("TextChatService") },
	}

	for _, entry in ipairs(namingTargets) do
		local newName = HttpService:GenerateGUID(false)
		local success, err = pcall(function()
			ServiceMap[entry.service] = {
				originalName = entry.service.Name,
				obfuscatedName = newName,
			}
			entry.service.Name = newName
		end)
		if not success then
			warn("[AntiCheat] Could not rename service '" .. entry.service.Name .. "': " .. tostring(err))
		end
	end
end

local function IsSpamming(player: Player)
	local now = os.clock()
	if not RemoteThrottles[player.UserId] then
		RemoteThrottles[player.UserId] = { lastReset = now, count = 0 }
	end

	local data = RemoteThrottles[player.UserId]
	if now - data.lastReset >= 1 then
		data.count = 1
		data.lastReset = now
		return false
	else
		data.count += 1
		return data.count > MAX_REMOTES_PER_SECOND
	end
end

local function CheckMessageForExploits(player: Player, message: string, source: string)
	if type(message) ~= "string" then return false end
	local lowerMessage = string.lower(message)

	RecentlyFlagged[player.UserId] = RecentlyFlagged[player.UserId] or {}
	local playerFlags = RecentlyFlagged[player.UserId]

	for _, term in ipairs(BlacklistedTerms) do
		if string.find(lowerMessage, term, 1, true) then
			if playerFlags[term] then return false end
			playerFlags[term] = true
			task.delay(5, function()
				if playerFlags then playerFlags[term] = nil end
			end)

			local reason = "Blacklisted term detected (" .. term .. "). Source: " .. source
			local Data = AntiCheatData.GetData(player)
			if not Data then return true end

			AppendErrorLog(player, "BlacklistedTerm", message, source)

			if Config.USE_FLAG_SYSTEM then Data.Flagged = true end
			if Config.USE_IMMEDIATE_ACTION_SYSTEM then player:Kick(reason) end
			return true
		end
	end

	for _, pattern in ipairs(BlacklistedPatterns) do
		if string.find(lowerMessage, pattern) then
			local flagKey = "pattern_" .. pattern
			if playerFlags[flagKey] then return false end
			playerFlags[flagKey] = true
			task.delay(5, function()
				if playerFlags then playerFlags[flagKey] = nil end
			end)

			local reason = "Suspicious pattern detected. Source: " .. source
			local Data = AntiCheatData.GetData(player)
			if not Data then return true end

			AppendErrorLog(player, "SuspiciousPattern", message, source)

			if Config.USE_FLAG_SYSTEM then Data.Flagged = true end
			if Config.USE_IMMEDIATE_ACTION_SYSTEM then player:Kick(reason) end
			return true
		end
	end

	return false
end

local function HandleGhostScript(player: Player)
	RecentlyFlagged[player.UserId] = RecentlyFlagged[player.UserId] or {}
	local playerFlags = RecentlyFlagged[player.UserId]

	if not playerFlags["GhostScript"] then
		playerFlags["GhostScript"] = true
		task.delay(5, function()
			if playerFlags then playerFlags["GhostScript"] = nil end
		end)

		local Data = AntiCheatData.GetData(player)
		if not Data then return end

		AppendErrorLog(player, "GhostScript", "[GhostScript]", "NilScript")

		if Config.USE_FLAG_SYSTEM then Data.Flagged = true end
		if Config.USE_IMMEDIATE_ACTION_SYSTEM then
			player:Kick("Error fired from a nil/external script environment.")
		end
	end
end

local function IsGrounded(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return false end

	local rayOrigin = hrp.Position
	local rayDirection = Vector3.new(0, -(humanoid.HipHeight + 3), 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = game:GetService("Workspace"):Raycast(rayOrigin, rayDirection, raycastParams)
	return result ~= nil
end

local function GetAllowedSpeed(humanoid)
	if not humanoid then return 24 end
	return humanoid.WalkSpeed + 10
end

local function TeleportToSavedPosition(player)
	local data = PlayerMovementData[player.UserId]
	if not data or not data.lastGoodPosition then return end

	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:MoveTo(data.lastGoodPosition) end
	hrp.CFrame = CFrame.new(data.lastGoodPosition + Vector3.new(0, 3, 0))

	data.immuneUntil = tick() + POST_RUBBERBAND_IMMUNITY
	data.airTime = 0
	data.flyViolations = 0
	data.speedViolations = 0
	data.lastPosition = nil
	data.lastPositionTime = nil
end

local function FlagOrKick(player, reason)
	local data = PlayerMovementData[player.UserId]
	if not data then return end

	local now = tick()
	if data.lastRubberbandTime and (now - data.lastRubberbandTime) < RUBBERBAND_COOLDOWN then
		return
	end
	data.lastRubberbandTime = now

	local acData = AntiCheatData.GetData(player)
	if not acData then return end

	AppendErrorLog(player, "MovementViolation", reason, "ServerMovementCheck")

	TeleportToSavedPosition(player)

	if Config.USE_FLAG_SYSTEM then acData.Flagged = true end
	if Config.USE_IMMEDIATE_ACTION_SYSTEM then
		acData.Banned = true
		player:Kick(reason)
	end
end

local function StartMovementChecks(player)
	local connection
	local saveTimer = 0

	connection = RunService.Heartbeat:Connect(function(dt)
		if not player or not player.Parent then
			connection:Disconnect()
			return
		end

		local data = PlayerMovementData[player.UserId]
		if not data then
			connection:Disconnect()
			return
		end

		local character = player.Character
		if not character then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not hrp or not humanoid or humanoid.Health <= 0 then return end

		local now = tick()

		if data.immuneUntil and now < data.immuneUntil then
			data.lastPosition = hrp.Position
			data.lastPositionTime = now
			return
		end

		local currentPos = hrp.Position
		local grounded = IsGrounded(character)

		if grounded then
			if not data.wasGrounded then
				data.airTime = 0
				data.flyViolations = 0
			end
			data.wasGrounded = true
			data.speedViolations = math.max(0, (data.speedViolations or 0) - 1)
		else
			data.wasGrounded = false
			data.airTime = (data.airTime or 0) + dt
		end

		if data.lastPosition and data.lastPositionTime then
			local elapsed = now - data.lastPositionTime

			if elapsed >= MIN_ELAPSED and elapsed <= MAX_ELAPSED then
				local delta = currentPos - data.lastPosition
				local horizontalSpeed = Vector3.new(delta.X, 0, delta.Z).Magnitude / elapsed
				local verticalSpeed = delta.Y / elapsed
				local absVerticalSpeed = math.abs(verticalSpeed)

				local allowedSpeed = GetAllowedSpeed(humanoid)
				if horizontalSpeed > allowedSpeed then
					data.speedViolations = (data.speedViolations or 0) + 1
					if data.speedViolations >= SPEED_VIOLATION_THRESHOLD then
						data.speedViolations = 0
						FlagOrKick(player, "Speed Hack Detected")
					end
				end

				if not grounded then
					local isSustainedUpward = verticalSpeed > MAX_VERTICAL_SPEED
					local isHovering = data.airTime > FLY_HOVER_GRACE and absVerticalSpeed < FLY_HOVER_THRESHOLD

					if isSustainedUpward or isHovering then
						data.flyViolations = (data.flyViolations or 0) + 1
					else
						data.flyViolations = math.max(0, (data.flyViolations or 0) - 1)
					end

					if (data.flyViolations or 0) >= FLY_VIOLATION_THRESHOLD then
						data.flyViolations = 0
						FlagOrKick(player, "Fly Hack Detected")
					end
				end
			end
		end

		saveTimer += dt
		if saveTimer >= SAVE_INTERVAL then
			saveTimer = 0
			if grounded then data.lastGoodPosition = currentPos end
		end

		data.lastPosition = currentPos
		data.lastPositionTime = now
	end)
end

Players.PlayerAdded:Connect(function(player: Player)
	PlayerMovementData[player.UserId] = {
		lastGoodPosition = nil,
		immuneUntil = tick() + 3,
		lastPosition = nil,
		lastPositionTime = nil,
		airTime = 0,
		flyViolations = 0,
		speedViolations = 0,
		wasGrounded = false,
	}
	RecentlyFlagged[player.UserId] = {}

	task.wait(1)

	local gui = player:WaitForChild("PlayerGui", 10)
	if gui then
		local watchdog = script.LocalScript:Clone()
		watchdog.Name = "ClientWatchdog"
		watchdog.Parent = gui
	end

	player.CharacterAdded:Connect(function()
		if PlayerMovementData[player.UserId] then
			local d = PlayerMovementData[player.UserId]
			d.lastPosition = nil
			d.lastPositionTime = nil
			d.immuneUntil = tick() + 3
			d.airTime = 0
			d.flyViolations = 0
			d.speedViolations = 0
		end
		task.wait(2)
		StartMovementChecks(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerMovementData[player.UserId] = nil
	ExpectedHandshakes[player.UserId] = nil
	RecentlyFlagged[player.UserId] = nil
	RemoteThrottles[player.UserId] = nil
end)

Remotes.ExploitDetected.OnServerEvent:Connect(function(Player: Player, Reason: string)
	if IsSpamming(Player) then Player:Kick("Remote Spam") return end
	if type(Reason) ~= "string" then return end

	print(Reason)

	local Data = AntiCheatData.GetData(Player)
	if not Data then return end

	AppendErrorLog(Player, "ExploitDetected", Reason, "ClientWatchdog")

	if Config.USE_FLAG_SYSTEM then Data.Flagged = true end
	if Config.USE_IMMEDIATE_ACTION_SYSTEM then Player:Kick(Reason) end
end)

Remotes.LogReport.OnServerEvent:Connect(function(Player: Player, message: string, source: string)
	if IsSpamming(Player) then return end
	if type(message) ~= "string" or type(source) ~= "string" then return end
	if message == "__actest__" then return end

	if message == "[GhostScript]" and source == "NilScript" then
		HandleGhostScript(Player)
		return
	end

	print(message, source)

	AppendErrorLog(Player, "LogReport", message, source)

	CheckMessageForExploits(Player, message, source)
end)

Remotes.Handshake.OnServerEvent:Connect(function(Player: Player, Token: string)
	if ExpectedHandshakes[Player.UserId] == Token then
		ExpectedHandshakes[Player.UserId] = nil
	else
		AppendErrorLog(Player, "InvalidHandshake", "Token mismatch", "Handshake")
		Player:Kick("Invalid Handshake")
	end
end)

task.spawn(function()
	while true do
		task.wait(20)
		for _, Player in pairs(Players:GetPlayers()) do
			local Token = HttpService:GenerateGUID(false)
			ExpectedHandshakes[Player.UserId] = Token
			Remotes.Handshake:FireClient(Player, Token)
		end
	end
end)

task.spawn(function()
	ObfuscateServices()
	while true do
		task.wait(120)
		ObfuscateServices()
	end
end)

return AntiCheat
