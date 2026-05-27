--[[ 
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
]]

local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local IsStudio = RunService:IsStudio()
local DataStoreVersion = script:GetAttribute("DataStoreVersion") or "1"
local DataStoreName = (IsStudio and "TestNotificationStore_" or "NotificationStore_") .. DataStoreVersion

local NotificationStore = DataStoreService:GetDataStore(DataStoreName)

export type CategoryType = "Success" | "Error" | "Warning" | "General"
export type ToNotify = Player | "All"
export type GlobalToNotify = number | "All"

local Categories: { [string]: { Name: CategoryType, LoweredName: string, Color: Color3 } } = {
	success = {Name = "Success", LoweredName = "success", Color = Color3.new(0, 1, 0)},
	error = {Name = "Error", LoweredName = "error", Color = Color3.new(1, 0, 0)},
	warning = {Name = "Warning", LoweredName = "warning", Color = Color3.new(1, 0.631373, 0.0745098)},
	general = {Name = "General", LoweredName = "general", Color = Color3.new(0.2, 0.2, 0.2)}
}

local DefaultData = {
	HadNotification = false,
	Category = "",
	Message = "",
	Time = 0
}

local TemplateGui = script:FindFirstChild("NotificationGui")
assert(TemplateGui, "NotificationGui not found under script")

local MAX_NOTIFICATION_DURATION = 100

local NotificationRemotes = ReplicatedStorage:FindFirstChild("NotificationRemotes") or Instance.new("Folder")
NotificationRemotes.Name = "NotificationRemotes"
NotificationRemotes.Parent = ReplicatedStorage

local RobloxNotificationRemote = NotificationRemotes:FindFirstChild("RobloxNotificationRemote") or Instance.new("RemoteEvent")
RobloxNotificationRemote.Name = "RobloxNotificationRemote"
RobloxNotificationRemote.Parent = NotificationRemotes

local Internal = {}
local NotificationService = {}

local ActiveNotifications: { [Player]: boolean } = {}

function NotificationService:Notify(Category: CategoryType, Target: ToNotify, Message: string, Time: number): boolean
	local categoryKey = string.lower(Category)
	local categoryData = Categories[categoryKey]
	if not categoryData then return false end

	Time = math.clamp(Time, 1, MAX_NOTIFICATION_DURATION)

	if typeof(Target) == "string" and string.lower(Target) == "all" then
		for _, player in Players:GetPlayers() do
			if not ActiveNotifications[player] then
				Internal.ShowNotificationToPlayer(player, categoryData, Message, Time)
			end
		end
		return true
	end

	if typeof(Target) == "Instance" and Target:IsA("Player") then
		if ActiveNotifications[Target] then return false end
		Internal.ShowNotificationToPlayer(Target, categoryData, Message, Time)
		return true
	end

	return false
end

function NotificationService:RobloxNotify(Target: ToNotify, Title: string, Text: string, Icon: string?, Duration: number, Button1: string?, Button2: string?): boolean
	if typeof(Target) == "string" and string.lower(Target) == "all" then
		RobloxNotificationRemote:FireAllClients(Title, Text, Icon, Duration, Button1, Button2)
		return true
	end

	if typeof(Target) == "Instance" and Target:IsA("Player") then
		RobloxNotificationRemote:FireClient(Target, Title, Text, Icon, Duration, Button1, Button2)
		return true
	end

	warn("[NotificationService] Invalid target provided to RobloxNotify")
	return false
end

function NotificationService:NotifyOffline(Category: CategoryType, UserID: number, Message: string, Time: number): boolean
	local categoryKey = string.lower(Category)
	if not Categories[categoryKey] then return false end

	Time = math.clamp(Time, 1, MAX_NOTIFICATION_DURATION)

	local dataToSave = {
		HadNotification = true,
		Category = Category,
		Message = Message,
		Time = Time,
	}

	local key = tostring(UserID) .. "-" .. DataStoreName
	local success, err = pcall(function()
		NotificationStore:SetAsync(key, dataToSave)
	end)

	if not success then
		warn("[NotifyOffline] Failed to store for user ID:", UserID, err)
		return false
	end

	return true
end

function NotificationService:NotifyGlobal(Category: CategoryType, Target: GlobalToNotify, Message: string, Time: number): boolean
	local success, result = pcall(function()
		MessagingService:PublishAsync("GlobalNotification", {
			Category = Category,
			ToNotify = Target,
			Message = Message,
			Time = Time,
		})
	end)

	if not success then
		warn("[NotifyGlobal] Error publishing message:", result)
		return false
	end

	return true
end

function Internal.ShowNotificationToPlayer(player: Player, categoryData, message: string, Time: number)
	ActiveNotifications[player] = true

	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui", 5) 
		if not playerGui then 
			ActiveNotifications[player] = nil 
			return 
		end

		local gui: ScreenGui = playerGui:FindFirstChild(TemplateGui.Name)
		if not gui then ActiveNotifications[player] = nil return end

		local mainFrame: Frame = gui:FindFirstChild("MainFrame")
		if not mainFrame then ActiveNotifications[player] = nil return end

		local label: TextLabel = mainFrame:FindFirstChild("BlueLabel")
		local messageLabel: TextLabel = mainFrame:FindFirstChild("Message")
		if not label or not messageLabel then ActiveNotifications[player] = nil return end

		local stroke = mainFrame:FindFirstChildOfClass("UIStroke")
		local labelStroke = label:FindFirstChildOfClass("UIStroke")

		if stroke then stroke.Color = categoryData.Color end
		if labelStroke then labelStroke.Color = categoryData.Color end

		label.Text = categoryData.Name
		messageLabel.Text = message

		gui.Enabled = true
		task.wait(Time)

		if gui and gui.Parent then
			gui.Enabled = false
		end

		ActiveNotifications[player] = nil
	end)
end

function Internal.PlayerAdded(player: Player)
	local key = tostring(player.UserId) .. "-" .. DataStoreName
	local data

	local success, result = pcall(function()
		return NotificationStore:GetAsync(key)
	end)

	if not success then
		warn("[NotificationService] Failed to load data for", player.Name, ":", result)
		data = table.clone(DefaultData)
	else
		data = result or table.clone(DefaultData)
	end

	if typeof(data) == "table" then
		for k, v in pairs(DefaultData) do
			if data[k] == nil then
				data[k] = v
			end
		end
	end

	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then return end

	local clonedGui = TemplateGui:Clone()

	local ScriptClone = script:FindFirstChild("SendNotification")
	if ScriptClone then
		local newScript = ScriptClone:Clone()
		newScript.Parent = clonedGui
		newScript.Enabled = true
	end

	clonedGui.Parent = playerGui

	if data.HadNotification and data.Message ~= "" then
		local category = data.Category
		local message = data.Message
		local time = data.Time

		if Categories[string.lower(category)] then
			NotificationService:Notify(category, player, message, time)
		end

		pcall(function()
			NotificationStore:UpdateAsync(key, function(oldData)
				return table.clone(DefaultData)
			end)
		end)
	end
end

function Internal.PlayerRemoving(player: Player)
	ActiveNotifications[player] = nil
end

Players.PlayerAdded:Connect(Internal.PlayerAdded)
Players.PlayerRemoving:Connect(Internal.PlayerRemoving)

task.spawn(function()
	local success, err = pcall(function()
		MessagingService:SubscribeAsync("GlobalNotification", function(Message)
			local Data = Message.Data
			if not Data then return end

			local Category: CategoryType = Data.Category
			local ToNotify = Data.ToNotify
			local Msg: string = Data.Message
			local Time: number = Data.Time

			if typeof(Category) ~= "string" or (typeof(ToNotify) ~= "string" and typeof(ToNotify) ~= "number") or typeof(Msg) ~= "string" or typeof(Time) ~= "number" then
				warn("[NotificationService] Received malformed global notification")
				return
			end

			if ToNotify == "All" then
				NotificationService:Notify(Category, "All", Msg, Time)
			elseif typeof(ToNotify) == "number" then
				local targetPlayer = Players:GetPlayerByUserId(ToNotify)
				if targetPlayer then
					NotificationService:Notify(Category, targetPlayer, Msg, Time)
				end
			end
		end)
	end)

	if success then
		print("NotificationService: Successfully subscribed to global notifications")
	else
		warn("NotificationService: Failed to subscribe to global notifications:", err)
	end
end)

return NotificationService
