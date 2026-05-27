--[[ 
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local _WORKSPACE_ = game:GetService("Workspace")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage.Remotes

local PlayerDataModule = require(ServerScriptService.PlayerData.PlayerData)
local PlayerDataTemplate = require(ReplicatedStorage.PlayerData)
local CharactersModule = require(ReplicatedStorage.CharacterConfig.Characters)
local GamepassModule = require(ReplicatedStorage.GamepassConfig.Gamepasses)

local CharacterLookup = {}
local CategoryLookup = {}
local SkinLookup = {}

for categoryName, categoryList in pairs(CharactersModule) do
	for _, data in ipairs(categoryList) do
		CharacterLookup[data.Id] = data
		CategoryLookup[data.Id] = categoryName

		if data.Skins then
			for _, skin in ipairs(data.Skins) do
				SkinLookup[skin.SkinId] = skin
			end
		end
	end
end

local RateLimits = {}
local function CheckRateLimit(Player: Player, ActionKey: string, Cooldown: number): boolean
	local key = Player.UserId .. "_" .. ActionKey
	local lastCall = RateLimits[key] or 0
	if os.clock() - lastCall < Cooldown then
		return false
	end
	RateLimits[key] = os.clock()
	return true
end

Players.PlayerRemoving:Connect(function(Player: Player)
	RateLimits[Player.UserId .. "_Shop"] = nil
	RateLimits[Player.UserId .. "_Inventory"] = nil
end)

Remotes.ShopFunction.OnServerInvoke = function(Player: Player, ItemId: string, Currency: string, ItemType: string)
	ItemType = ItemType or "CHARACTER"

	if not CheckRateLimit(Player, "Shop", 0.5) then return false, "Rate Limited" end
	if Player:GetAttribute("IsPlayerInRound") == true then return false, "IN_ROUND" end
	if not ItemId or not Currency then return false, "Missing Info" end

	local Data = PlayerDataModule.GetData(Player)
	if not Data then return false, "Data not loaded" end

	if ItemType == "CHARACTER" then
		local CharacterData = CharacterLookup[ItemId]
		if not CharacterData then return false, "Character not found" end

		if Data.Characters[ItemId] and Data.Characters[ItemId].isOwned then
			return false, "ALREADY_OWNED"
		end

		if Currency == "SOULS" then
			local Cost = CharacterData.Souls

			if Data.souls >= Cost then
				Data.souls -= Cost

				local leaderstats = Player:FindFirstChild("leaderstats")
				if leaderstats and leaderstats:FindFirstChild("Souls") then
					leaderstats.Souls.Value = Data.souls
				end

				if not Data.Characters[ItemId] then
					Data.Characters[ItemId] = {isOwned = true, CurrentLevel = 1}
				else
					Data.Characters[ItemId].isOwned = true
				end

				local CharFolder = Player:FindFirstChild("Characters")
				if CharFolder and CharFolder:FindFirstChild(ItemId) then
					CharFolder[ItemId].Value = true
				end

				return true, "SUCCESS"
			else
				return false, "INSUFFICIENT_SOULS"
			end
		end

	elseif ItemType == "SKIN" then
		local SkinData = SkinLookup[ItemId]
		if not SkinData then return false, "Skin not found" end

		if not Data.OwnedSkins then Data.OwnedSkins = {} end
		
		if Data.OwnedSkins[ItemId] then
			return false, "ALREADY_OWNED"
		end

		if Currency == "SOULS" then
			local Cost = SkinData.Souls

			if Data.souls >= Cost then
				Data.souls -= Cost

				local leaderstats = Player:FindFirstChild("leaderstats")
				if leaderstats and leaderstats:FindFirstChild("Souls") then
					leaderstats.Souls.Value = Data.souls
				end

				Data.OwnedSkins[ItemId] = true
				
				return true, "SUCCESS"
			else
				return false, "INSUFFICIENT_SOULS"
			end
		end
	end

	return false, "Unknown Error"
end

Remotes.PromptGamepass.OnServerEvent:Connect(function(Player: Player, GamepassName: string)
	if not Player or not GamepassName then return end

	local GamepassData = GamepassModule.Gamepasses[GamepassName]
	if not GamepassData or not GamepassData.ProductId then return end

	local success, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(Player, GamepassData.ProductId)
	end)

	if not success then
		warn("Error prompting gamepass purchase for ".. Player.Name.. ": ".. tostring(errorMessage))
	end
end)

Remotes.InventoryFunction.OnServerInvoke = function(Player: Player, TargetId: string, Action: string, ExtraId: string)
	if not Player or not TargetId or not Action then return end
	if not CheckRateLimit(Player, "Inventory", 0.25) then return "RATE_LIMITED" end

	if _WORKSPACE_:GetAttribute("IsRoundStarted") == true then 
		return "ROUND_ACTIVE" 
	end

	local Data = PlayerDataModule.GetData(Player)
	if not Data then return end

	if Action == "Equip" then
		local CharacterId = TargetId
		local CharacterData = CharacterLookup[CharacterId]
		if not CharacterData then return end

		local categoryName = CategoryLookup[CharacterId]
		if not categoryName then return end 

		local dataKey = "Equipped" .. categoryName

		if Data[dataKey] == CharacterId then return "ALREADY_EQUIPPED" end

		if Data.Characters[CharacterId] and Data.Characters[CharacterId].isOwned == true then

			Data[dataKey] = CharacterId

			local CharactersFolder = Player:FindFirstChild("Characters")
			if CharactersFolder then
				local charValue = CharactersFolder:FindFirstChild(dataKey)
				if charValue and charValue:IsA("StringValue") then
					charValue.Value = CharacterId
				end
			end
			return "SUCCESS"
		end

	elseif Action == "EquipSkin" then
		local SkinId = TargetId
		local CharacterId = ExtraId

		if not CharacterId or not SkinId then return "MISSING_INFO" end

		local CharacterData = CharacterLookup[CharacterId]
		if not CharacterData then return "INVALID_CHARACTER" end

		if not Data.Characters[CharacterId] or not Data.Characters[CharacterId].isOwned then
			return "CHARACTER_NOT_OWNED"
		end

		if SkinId ~= "Default" then
			if not Data.OwnedSkins or not Data.OwnedSkins[SkinId] then
				return "SKIN_NOT_OWNED"
			end
		end

		if Data.Characters[CharacterId].EquippedCharacterSkin == SkinId then
			return "ALREADY_EQUIPPED"
		end

		Data.Characters[CharacterId].EquippedCharacterSkin = SkinId

		local CharactersFolder = Player:FindFirstChild("Characters")
		if CharactersFolder then
			local charFolder = CharactersFolder:FindFirstChild(CharacterId)
			if charFolder then
				local skinValue = charFolder:FindFirstChild("EquippedCharacterSkin")
				if skinValue and skinValue:IsA("StringValue") then
					skinValue.Value = SkinId
				end
			end
		end

		return "SUCCESS"
	end
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local boughtProduct = nil
	for _, info in pairs(GamepassModule.Gamepasses) do
		if info.ProductId == receiptInfo.ProductId then
			boughtProduct = info
			break
		end
	end

	if boughtProduct then
		local Data = PlayerDataModule.GetData(player)
		if Data then
			Data.souls += boughtProduct.Soul
			Data.robuxSpent += boughtProduct.Price

			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats then
				local soulsValue = leaderstats:FindFirstChild("Souls")
				if soulsValue then
					soulsValue.Value = Data.souls
				end
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
