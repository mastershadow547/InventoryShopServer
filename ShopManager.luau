--[[ 
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
	THE SHOWCASE VIDEO IS THIS: https://drive.google.com/file/d/1MhB_feMLIHQgJasPUFExvDuE2cqBHT_a/view?usp=sharing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShopGui = script.Parent
local MainFrame = ShopGui.MainFrame
local ToggleOpenButton = ShopGui.ToggleOpen
local CategoryButtons = MainFrame.CategoryButtons
local PurchaseFrame = MainFrame.PurchaseFrame
local SelectedCharacterFrame = PurchaseFrame.SelectedCharacter
local PurchaseButton = PurchaseFrame.PurchaseButton	
local SkinsButton = PurchaseFrame.SkinsButton

local CharactersModule = require(ReplicatedStorage.CharacterConfig.Characters)
local GamepassesModule = require(ReplicatedStorage.GamepassConfig.Gamepasses)
local CharacterModels = ReplicatedStorage:FindFirstChild("CharacterModels")
local Remotes = ReplicatedStorage.Remotes

local CharacterTemplate = script:FindFirstChild("CharacterTemplate")
local GamepassTemplate = script:FindFirstChild("GamepassTemplate")
local SkinTemplate = script:FindFirstChild("SkinTemplate")

local Player = Players.LocalPlayer
local CurrentCategory = "Monster"
local SelectedCharacter = nil
local isPurchasing = false
local isLoadingUI = false

local ViewingSkins = false
local SelectedSkin = nil

local CharacterLookup = {}
local ShopFunctions = {}

local lastClosedTime = 0

for _, categoryList in pairs(CharactersModule) do
	for _, data in ipairs(categoryList) do
		CharacterLookup[data.Id] = data
	end
end

ShopGui:SetAttribute("Open", false)
MainFrame.Visible = false

function ShopFunctions.ClearPooledTemplates()
	for _, child in ipairs(MainFrame.Container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

function ShopFunctions.TriggerCleanupTimer()
	lastClosedTime = os.clock()
	task.delay(120, function()
		local isOpen = ShopGui:GetAttribute("Open") == true
		if not isOpen and (os.clock() - lastClosedTime) >= 119 then
			ShopFunctions.ClearPooledTemplates()
		end
	end)
end

Player:GetAttributeChangedSignal("IsPlayerInRound"):Connect(function()
	if Player:GetAttribute("IsPlayerInRound") == true then
		if ShopGui:GetAttribute("Open") == true then
			ShopGui:SetAttribute("Open", false)
			MainFrame.Visible = false
			ShopFunctions.ResetPurchaseFrame()
			isLoadingUI = false
			ShopFunctions.TriggerCleanupTimer()
		end
	end
end)

function ShopFunctions.RenderThumbnail(viewport: ViewportFrame, modelId: string, isSkin: boolean, baseCharacterId: string)
	local model

	if isSkin then
		if modelId == "Default" and baseCharacterId then
			model = CharacterModels:FindFirstChild(baseCharacterId)
		else
			local SkinModels = ReplicatedStorage:FindFirstChild("SkinModels")
			if SkinModels then
				model = SkinModels:FindFirstChild(modelId)
			end
		end
	else
		if CharacterModels then
			model = CharacterModels:FindFirstChild(modelId)
		end
	end

	if not model then return end

	local worldModel = viewport:FindFirstChildWhichIsA("WorldModel")
	if not worldModel then
		worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport
	end
	worldModel:ClearAllChildren()

	local modelClone = model:Clone()
	modelClone:PivotTo(CFrame.new(0, 0, 0))
	modelClone.Parent = worldModel

	local camera = viewport:FindFirstChildWhichIsA("Camera")
	if not camera then
		camera = Instance.new("Camera")
		camera.FieldOfView = 50
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end

	local modelCenter = modelClone:GetPivot().Position
	camera.CFrame = CFrame.new(modelCenter + Vector3.new(0, 2, 7), modelCenter)
end

function ShopFunctions.ResetPurchaseFrame()
	SelectedCharacter = nil
	SelectedSkin = nil
	ViewingSkins = false
	SelectedCharacterFrame.CharacterName.Text = ""
	SelectedCharacterFrame.SoulCurrency.SoulsLabel.Text = ""
	PurchaseButton.Text = "Purchase"
	SkinsButton.Text = "SKINS"
	PurchaseFrame.StatusLabel.Text = ""
	PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
end

function ShopFunctions.ToggleShop()
	if isLoadingUI then return end

	if Player:GetAttribute("IsPlayerInRound") == true then
		return
	end

	isLoadingUI = true

	local isOpen = ShopGui:GetAttribute("Open") or false
	local newState = not isOpen

	ShopGui:SetAttribute("Open", newState)
	MainFrame.Visible = newState

	if newState then
		ShopFunctions.ResetPurchaseFrame()
		MainFrame.CategoryLabel.Text = CurrentCategory
		ShopFunctions.loadCategory(CurrentCategory)
	else
		ShopFunctions.TriggerCleanupTimer()
	end

	task.wait(0.2)
	isLoadingUI = false
end

function ShopFunctions.OnSkinButtonClicked()
	if not SelectedCharacter or isLoadingUI then return end

	isLoadingUI = true

	if ViewingSkins then

		ViewingSkins = false
		SelectedSkin = nil
		SkinsButton.Text = "SKINS"

		MainFrame.CategoryLabel.Text = CurrentCategory

		SelectedCharacterFrame.CharacterName.Text = tostring(SelectedCharacter.Name)
		SelectedCharacterFrame.SoulCurrency.SoulsLabel.Text = tostring(SelectedCharacter.Souls)
		PurchaseFrame.StatusLabel.Text = "Status: "
		PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

		local CharactersFolder = Player:FindFirstChild("Characters")
		if CharactersFolder and CharactersFolder:FindFirstChild(SelectedCharacter.Id) and CharactersFolder:FindFirstChild(SelectedCharacter.Id).Value then
			PurchaseButton.Text = "OWNED"
		else
			PurchaseButton.Text = "PURCHASE"
		end

		ShopFunctions.loadCategory(CurrentCategory)

	else
		ViewingSkins = true
		SelectedSkin = nil
		SkinsButton.Text = "BACK"

		for _, child in ipairs(MainFrame.Container:GetChildren()) do
			if child:IsA("GuiObject") and not child:IsA("UIGridLayout") then
				child.Visible = false
			end
		end

		MainFrame.CategoryLabel.Text = SelectedCharacter.Name .. "'s Skins"

		SelectedCharacterFrame.CharacterName.Text = ""
		SelectedCharacterFrame.SoulCurrency.SoulsLabel.Text = ""
		PurchaseButton.Text = "Purchase"
		PurchaseFrame.StatusLabel.Text = ""
		PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

		if SelectedCharacter.Skins then
			for _, skinData in ipairs(SelectedCharacter.Skins) do
				local existingTemplate = MainFrame.Container:FindFirstChild(skinData.SkinId)
				if existingTemplate then
					existingTemplate.Visible = true
				else
					ShopFunctions.CreateSkinTemplate(skinData)
				end
			end
		end
	end

	task.wait(0.2)
	isLoadingUI = false
end

function ShopFunctions.OpenCategory(categoryName: string, color: Color3)
	if not (ShopGui:GetAttribute("Open") == true) or isLoadingUI then return end
	if CurrentCategory == categoryName then return end

	isLoadingUI = true
	CurrentCategory = categoryName
	MainFrame.CategoryLabel.Text = CurrentCategory
	MainFrame.CategoryLabel.TextColor3 = color
	ShopFunctions.ResetPurchaseFrame()

	if categoryName == "Gamepass" then
		PurchaseFrame.Visible = false
		ShopFunctions.loadGamepassCategory()
	else
		PurchaseFrame.Visible = true
		ShopFunctions.loadCategory(CurrentCategory)
	end

	task.wait(0.25)
	isLoadingUI = false
end

function ShopFunctions.OnPurchaseButton()
	local purchaseId, purchaseType

	if ViewingSkins then
		if not SelectedSkin then return end
		purchaseId = SelectedSkin.SkinId
		purchaseType = "SKIN"
	else
		if not SelectedCharacter then return end
		purchaseId = SelectedCharacter.Id
		purchaseType = "CHARACTER"
	end

	if isPurchasing or Player:GetAttribute("IsPlayerInRound") == true then return end

	isPurchasing = true
	PurchaseButton.Text = "..."

	task.spawn(function()
		local success, message = Remotes.ShopFunction:InvokeServer(purchaseId, "SOULS", purchaseType)

		if message == "ALREADY_OWNED" then
			PurchaseFrame.StatusLabel.Text = "Status: Already Owned!"
			PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
			PurchaseButton.Text = "OWNED"
		elseif message == "INSUFFICIENT_SOULS" then
			PurchaseFrame.StatusLabel.Text = "Status: Not Enough Souls!"
			PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(255, 170, 0)
			PurchaseButton.Text = "Purchase"
		elseif message == "SUCCESS" then
			PurchaseFrame.StatusLabel.Text = "Status: Purchased Successfully!"
			PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
			PurchaseButton.Text = "OWNED"

			local template = MainFrame.Container:FindFirstChild(purchaseId)
			if template then
				template.Soul.SoulLabel.Visible = false
				template.Soul.SoulIcon.Visible = false
				if template:FindFirstChild("Robux") then
					template.Robux.RobuxLabel.Visible = false
					template.Robux.RobuxIcon.Visible = false
				end
				template.OwnedLabel.Visible = true
			end
		else
			PurchaseFrame.StatusLabel.Text = "Status: Failed to Purchase! " .. tostring(message)
			PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(255, 0, 4)
			PurchaseButton.Text = "Purchase"
		end

		task.wait(0.5)
		if PurchaseButton.Text ~= "OWNED" then
			PurchaseButton.Text = "PURCHASE"
		end
		PurchaseFrame.StatusLabel.Text = "Status: "
		PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

		isPurchasing = false
	end)
end

function ShopFunctions.CreateTemplate(CharacterId: string)
	local characterData = CharacterLookup[CharacterId]
	if not characterData then return end

	local CharactersFolder = Player:FindFirstChild("Characters")
	if not CharactersFolder then return end

	local template = CharacterTemplate:Clone()
	template.Name = CharacterId
	template.CharacterName.Text = tostring(characterData.Name)
	template.Soul.SoulLabel.Text = tostring(characterData.Souls)
	template.Robux.RobuxLabel.Text = tostring(characterData.Robux)
	template.Active = true
	template.Interactable = true

	ShopFunctions.RenderThumbnail(template, CharacterId, false, nil)	

	if CharactersFolder:FindFirstChild(CharacterId) and CharactersFolder:FindFirstChild(CharacterId).Value then
		template.Soul.SoulLabel.Visible = false
		template.Soul.SoulIcon.Visible = false
		template.Robux.RobuxLabel.Visible = false
		template.Robux.RobuxIcon.Visible = false
		template.OwnedLabel.Visible = true
	end

	template.Parent = MainFrame.Container

	template.InputBegan:Connect(function(Input: InputObject)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			SelectedCharacterFrame.CharacterName.Text = tostring(characterData.Name)
			SelectedCharacterFrame.SoulCurrency.SoulsLabel.Text = tostring(characterData.Souls)
			SelectedCharacterFrame.RobuxCurrency.RobuxLabel.Text = tostring(characterData.Robux)
			PurchaseFrame.StatusLabel.Text = "Status: "
			PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

			if CharactersFolder:FindFirstChild(CharacterId) and CharactersFolder:FindFirstChild(CharacterId).Value then
				PurchaseButton.Text = "OWNED"
			else
				PurchaseButton.Text = "PURCHASE"
			end
			SelectedCharacter = characterData
		end
	end)
end

function ShopFunctions.loadCategory(category: string)
	local characterList = CharactersModule[category]
	if not characterList then return end

	local currentCategoryIds = {}
	for _, data in ipairs(characterList) do currentCategoryIds[data.Id] = true end

	for _, child in ipairs(MainFrame.Container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") then
			child.Visible = currentCategoryIds[child.Name] == true
		end
	end

	for _, data in ipairs(characterList) do
		local existingTemplate = MainFrame.Container:FindFirstChild(data.Id)
		if existingTemplate then
			existingTemplate.Visible = true
		else
			ShopFunctions.CreateTemplate(data.Id)
		end
	end
end

function ShopFunctions.CreateSkinTemplate(skinData)
	local template = SkinTemplate:Clone()
	template.Name = skinData.SkinId
	template.CharacterName.Text = skinData.Name
	template.Soul.SoulLabel.Text = tostring(skinData.Souls)
	template.Active = true
	template.Interactable = true

	if SelectedCharacter then
		ShopFunctions.RenderThumbnail(template, skinData.SkinId, true, SelectedCharacter.Id)
	end

	template.Parent = MainFrame.Container

	task.spawn(function()
		local playerData = Remotes.GetData:InvokeServer()
		local isOwned = playerData and playerData.OwnedSkins and playerData.OwnedSkins[skinData.SkinId]

		if isOwned then
			template.Soul.SoulLabel.Visible = false
			template.Soul.SoulIcon.Visible = false
			template.OwnedLabel.Visible = true
		end
	end)

	template.InputBegan:Connect(function(Input: InputObject)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			SelectedSkin = skinData
			SelectedCharacterFrame.CharacterName.Text = tostring(skinData.Name)
			SelectedCharacterFrame.SoulCurrency.SoulsLabel.Text = tostring(skinData.Souls)

			PurchaseFrame.StatusLabel.Text = "Status: "
			PurchaseFrame.StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

			PurchaseButton.Text = "..." 

			task.spawn(function()
				local playerData = Remotes.GetData:InvokeServer()
				local currentlyOwned = playerData and playerData.OwnedSkins and playerData.OwnedSkins[skinData.SkinId]

				if SelectedSkin == skinData then
					if currentlyOwned then
						PurchaseButton.Text = "OWNED"
					else
						PurchaseButton.Text = "PURCHASE"
					end
				end
			end)
		end
	end)
end

function ShopFunctions.loadGamepassCategory()
	for _, child in ipairs(MainFrame.Container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") then
			child.Visible = child:HasTag("GamepassTemplate")
		end
	end

	for gamepassName, _ in pairs(GamepassesModule.Gamepasses) do
		local existingTemplate = MainFrame.Container:FindFirstChild(gamepassName)
		if existingTemplate then
			existingTemplate.Visible = true
		else
			ShopFunctions.GamepassTemplateCreate(gamepassName)
		end
	end
end

function ShopFunctions.GamepassTemplateCreate(GamepassName: string)
	local GamepassData = GamepassesModule.Gamepasses[GamepassName]
	if not GamepassData then return end

	local template = GamepassTemplate:Clone()
	template.Name = GamepassName
	template.Robux.RobuxLabel.Text = tostring(GamepassData.Price)
	template.Soul.SoulLabel.Text = tostring(GamepassData.Soul)

	template:AddTag("GamepassTemplate")
	template.Parent = MainFrame.Container

	template.GamepassButton.MouseButton1Click:Connect(function()
		Remotes.PromptGamepass:FireServer(GamepassName)
	end)
end

ToggleOpenButton.MouseButton1Click:Connect(ShopFunctions.ToggleShop)
CategoryButtons.Monster.MouseButton1Click:Connect(function() ShopFunctions.OpenCategory("Monster", Color3.fromRGB(255, 0, 4)) end)
CategoryButtons.Survivor.MouseButton1Click:Connect(function() ShopFunctions.OpenCategory("Survivor", Color3.fromRGB(47, 120, 255)) end)
CategoryButtons.Gamepasses.MouseButton1Click:Connect(function() ShopFunctions.OpenCategory("Gamepass", Color3.fromRGB(0, 255, 0)) end)
PurchaseFrame.PurchaseButton.MouseButton1Click:Connect(ShopFunctions.OnPurchaseButton)
SkinsButton.MouseButton1Click:Connect(function() ShopFunctions.OnSkinButtonClicked() end)

return ShopFunctions
