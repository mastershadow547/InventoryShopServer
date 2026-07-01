local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local _WORKSPACE_ = game:GetService("Workspace")

local InventoryGui = script.Parent
local MainFrame = InventoryGui.MainFrame
local CategoryButtons = MainFrame.CategoryButtons
local CharacterTemplate = script:FindFirstChild("CharacterTemplate")
local SearchBox = MainFrame.Search.SearchBox

local CharactersModule = require(ReplicatedStorage.CharacterConfig.Characters)
local CharacterModels = ReplicatedStorage:FindFirstChild("CharacterModels")

local Player = Players.LocalPlayer
local CharacterLookup = {}
local CategoryLookup = {}
local InventoryFunctions = {}

local CurrentCategory = "Killers"
local SelectedCharacter = nil
local isLoadingUI = false
local isEquipping = false
local isInMoreInfo = false
local isInSkinsMode = false
local SelectedSkin = nil
local SearchQuery = ""

local lastClosedTime = 0

InventoryGui:SetAttribute("Open", false)
MainFrame.CharacterFrame.Visible = false
MainFrame.Visible = false

local backButton = MainFrame:FindFirstChild("BackButton")
if backButton then
	backButton.Visible = false
end

for categoryName, categoryList in pairs(CharactersModule) do
	for _, data in ipairs(categoryList) do
		CharacterLookup[data.Id] = data
		CategoryLookup[data.Id] = categoryName
	end
end

function InventoryFunctions.ClearPooledTemplates()
	for _, child in ipairs(MainFrame.Container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end

	local activeGeneralInfo = MainFrame.Container:FindFirstChild("ActiveGeneralInfo")
	if activeGeneralInfo then
		activeGeneralInfo:Destroy()
	end
end

function InventoryFunctions.TriggerCleanupTimer()
	lastClosedTime = os.clock()
	task.delay(120, function()
		local isOpen = InventoryGui:GetAttribute("Open") == true
		if not isOpen and (os.clock() - lastClosedTime) >= 119 then
			InventoryFunctions.ClearPooledTemplates()
		end
	end)
end

function InventoryFunctions.CategoryTranslation(categoryName: string)
	if categoryName == "Killers" then return "Monster"
	elseif categoryName == "Survivors" then return "Survivor"
	elseif categoryName == "Emotes" then return "Emotes"
	end
	return nil
end

function InventoryFunctions.FilterTemplates()
	if isInMoreInfo or isInSkinsMode then return end

	local query = SearchQuery:lower()
	local NewCategory = InventoryFunctions.CategoryTranslation(CurrentCategory)
	local CharacterFolder = Player:FindFirstChild("Characters")

	local currentCategoryIds = {}
	if NewCategory and CharactersModule[NewCategory] then
		for _, data in ipairs(CharactersModule[NewCategory]) do
			currentCategoryIds[tostring(data.Id)] = true
		end
	end

	for _, child in ipairs(MainFrame.Container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") and child.Name ~= "ActiveGeneralInfo" and not child:HasTag("InventorySkinTemplate") then
			if not currentCategoryIds[child.Name] then
				child.Visible = false
				continue
			end

			local ownsCharacter = false
			if CharacterFolder then
				local ownershipVal = CharacterFolder:FindFirstChild(child.Name)
				ownsCharacter = ownershipVal and ownershipVal:IsA("BoolValue") and ownershipVal.Value == true
			end

			if not ownsCharacter then
				child.Visible = false
				continue
			end

			if query == "" then
				child.Visible = true
			else
				local charData = CharacterLookup[child.Name]
				local nameMatch = charData and charData.Name:lower():find(query, 1, true)
				child.Visible = nameMatch ~= nil
			end
		end
	end

	if SelectedCharacter then
		local template = MainFrame.Container:FindFirstChild(SelectedCharacter)
		if template and not template.Visible then
			InventoryFunctions.ResetCharacterSelection()
		end
	end
end

function InventoryFunctions.OnSkinsButtonClicked()
	if not (InventoryGui:GetAttribute("Open") == true) or isLoadingUI or isInSkinsMode or isInMoreInfo then return end
	if not SelectedCharacter then return end

	local charData = CharacterLookup[SelectedCharacter]
	if not charData then return end

	isLoadingUI = true
	isInSkinsMode = true
	SelectedSkin = nil

	MainFrame.CharacterFrame.ActionFrame.MoreInfoButton.Visible = false
	MainFrame.CharacterFrame.ActionFrame.SkinsButton.Visible = false
	if backButton then backButton.Visible = true end

	for _, child in ipairs(MainFrame.Container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") then
			child.Visible = false
		end
	end

	task.spawn(function()
		local playerData = ReplicatedStorage.Remotes.GetData:InvokeServer()

		InventoryFunctions.CreateInventorySkinTemplate({
			SkinId = "Default",
			Name = "Default"
		})

		if charData.Skins then
			for _, skinData in ipairs(charData.Skins) do
				if playerData and playerData.OwnedSkins and playerData.OwnedSkins[skinData.SkinId] then
					InventoryFunctions.CreateInventorySkinTemplate(skinData)
				end
			end
		end

		isLoadingUI = false
	end)
end

function InventoryFunctions.CreateInventorySkinTemplate(skinData)
	local skinTemplateSource = script:FindFirstChild("SkinTemplate")
	if not skinTemplateSource then return end

	local Template = skinTemplateSource:Clone()
	Template.Name = skinData.SkinId

	local charNameLabel = Template:FindFirstChild("CharacterName")
	if charNameLabel then
		charNameLabel.Text = skinData.Name
	end

	InventoryFunctions.RenderThumbnail(Template, skinData.SkinId, true, SelectedCharacter)

	Template:AddTag("InventorySkinTemplate")
	Template.Active = true
	Template.Interactable = true
	Template.Visible = true
	Template.Parent = MainFrame.Container

	Template.InputBegan:Connect(function(Input: InputObject)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			SelectedSkin = skinData.SkinId

			MainFrame.CharacterFrame.CharacterInfoFrame.CharacterName.Text = skinData.Name
			MainFrame.CharacterFrame.CharacterInfoFrame.CurrentLevel.Visible = false
			MainFrame.CharacterFrame.CharacterInfoFrame.MaxLevelLabel.Visible = false

			InventoryFunctions.RenderThumbnail(MainFrame.CharacterFrame.CharacterInfoFrame.CharacterDisplayFrame, skinData.SkinId, true, SelectedCharacter)

			local isEquipped = false
			local CharacterFolder = Player:FindFirstChild("Characters")
			if CharacterFolder then
				local charFolder = CharacterFolder:FindFirstChild(SelectedCharacter)
				if charFolder then
					local equippedSkinVal = charFolder:FindFirstChild("EquippedCharacterSkin")
					if equippedSkinVal and equippedSkinVal.Value == skinData.SkinId then
						isEquipped = true
					end
				end
			end

			if isEquipped then
				MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equipped"
			else
				MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equip"
			end
		end
	end)
end

function InventoryFunctions.OnMoreInfoButtonClicked()
	if not (InventoryGui:GetAttribute("Open") == true) or isLoadingUI or isInMoreInfo or isInSkinsMode then return end
	if not SelectedCharacter then return end

	local charData = CharacterLookup[SelectedCharacter]
	if not charData then return end

	isInMoreInfo = true

	CategoryButtons.KillersButton.Visible = false
	CategoryButtons.SurvivorsButton.Visible = false
	CategoryButtons.EmotesButton.Visible = false

	MainFrame.Search.SearchBox.Visible = false
	MainFrame.Search.SearchLabel.Visible = false

	MainFrame.SoulDisplay.SoulDisplay.Visible = false
	MainFrame.SoulDisplay.GamepassPage.Visible = false

	for _, child in ipairs(MainFrame.Container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") then
			child.Visible = false
		end
	end

	local gridLayout = MainFrame.Container:FindFirstChildWhichIsA("UIGridLayout")
	if gridLayout then
		gridLayout.Parent = ReplicatedStorage
	end

	local generalInfoTemplate = script:FindFirstChild("General_Info")
	if not generalInfoTemplate then
		isInMoreInfo = false
		return
	end

	local generalInfo = generalInfoTemplate:Clone()
	generalInfo.Name = "ActiveGeneralInfo"
	generalInfo.Parent = MainFrame.Container

	for _, child in ipairs(generalInfo:GetChildren()) do
		if child:IsA("GuiObject") then
			child.Visible = true
		end
	end

	local characterInfo = generalInfo:FindFirstChild("CharacterInfo")
	if characterInfo then
		local descLabel = characterInfo:FindFirstChild("CharacterDescription")
		if descLabel then descLabel.Text = charData.Description end

		local nameLabel = characterInfo:FindFirstChild("CharacterName")
		if nameLabel then nameLabel.Text = charData.Name end

		local infoLabel = characterInfo:FindFirstChild("InfoLabel")
		if infoLabel then
			infoLabel.Text = string.format(
				"Difficulty: %d/5\nHealth: %d\nRegular Speed: %.2f\nSprinting Speed: %.2f\nMax Stamina: %d",
				charData.Difficulty, charData.Health, charData.RegularSpeed, charData.SprintingSpeed, charData.MaxStamina
			)
		end
	end

	local abilitiesFolder = generalInfo:FindFirstChild("Abilities")
	if abilitiesFolder then
		local abilityTemplate = abilitiesFolder:FindFirstChild("CharacterAbilityTemplate")
		if abilityTemplate then
			abilityTemplate.Visible = false
			local templateHeight = abilityTemplate.Size.Y.Offset
			if templateHeight <= 0 then templateHeight = 80 end
			local ySpacing = 10
			local index = 0

			for _, abilityData in pairs(charData.Abilities) do
				local clonedAbility = abilityTemplate:Clone()
				clonedAbility.Name = abilityData.Name
				clonedAbility.Visible = true
				clonedAbility.Size = UDim2.new(1, 0, 0, templateHeight)
				clonedAbility.Position = UDim2.new(0, 0, abilityTemplate.Position.Y.Scale, abilityTemplate.Position.Y.Offset + (index * (templateHeight + ySpacing)))
				clonedAbility.AnchorPoint = Vector2.new(0, 0)

				local abilityNameLabel = clonedAbility:FindFirstChild("AbilityName")
				if abilityNameLabel then abilityNameLabel.Text = abilityData.Name end

				local quoteLabel = clonedAbility:FindFirstChild("CharacterQuoteLabel")
				if quoteLabel then quoteLabel.Text = abilityData.AbilityQuote end

				local infoLabel = clonedAbility:FindFirstChild("AbilityInfoLabel")
				if infoLabel then
					infoLabel.Text = string.format("Cooldown: %ss\nDamage: %s\nWindup: %ss\nLinger: %ss\nLength: %s studs",
						tostring(abilityData.Cooldown), tostring(abilityData.Damage), tostring(abilityData.Windup), tostring(abilityData.Linger), tostring(abilityData.Length))
				end

				local imageLabel = clonedAbility:FindFirstChild("AbilityImageLabel")
				if imageLabel and imageLabel:IsA("ImageLabel") then
					imageLabel.Image = abilityData.AbilityImage
				end

				clonedAbility.Parent = abilitiesFolder
				index += 1
			end
		end
	end

	if backButton then backButton.Visible = true end
end

function InventoryFunctions.ClearCharacterDisplayFrame()
	local displayFrame = MainFrame.CharacterFrame.CharacterInfoFrame:FindFirstChild("CharacterDisplayFrame")
	if not displayFrame then return end

	local worldModel = displayFrame:FindFirstChildOfClass("WorldModel")
	if worldModel then
		local poolFolder = displayFrame:FindFirstChild("ModelPool")
		if poolFolder then
			for _, child in ipairs(worldModel:GetChildren()) do
				child.Parent = poolFolder
			end
		else
			worldModel:ClearAllChildren()
		end
	end
end

function InventoryFunctions.OnBackButtonClicked()
	InventoryFunctions.ClearCharacterDisplayFrame()

	if isInSkinsMode then
		isInSkinsMode = false
		SelectedSkin = nil
		isLoadingUI = false

		for _, child in ipairs(MainFrame.Container:GetChildren()) do
			if child:HasTag("InventorySkinTemplate") then
				child:Destroy()
			end
		end

		MainFrame.CharacterFrame.ActionFrame.MoreInfoButton.Visible = true
		MainFrame.CharacterFrame.ActionFrame.SkinsButton.Visible = true
		if backButton then backButton.Visible = false end

		MainFrame.CharacterFrame.CharacterInfoFrame.CurrentLevel.Visible = true

		InventoryFunctions.CharacterSelected(CharacterLookup[SelectedCharacter])
		InventoryFunctions.loadCategory(CurrentCategory)
		return
	end

	if not isInMoreInfo then return end
	isInMoreInfo = false
	isLoadingUI = false

	local gridLayout = ReplicatedStorage:FindFirstChild("UIGridLayout")
	if gridLayout then
		gridLayout.Parent = MainFrame.Container
	end

	local activeGeneralInfo = MainFrame.Container:FindFirstChild("ActiveGeneralInfo")
	if activeGeneralInfo then
		activeGeneralInfo:Destroy()
	end

	CategoryButtons.KillersButton.Visible = true
	CategoryButtons.SurvivorsButton.Visible = true
	CategoryButtons.EmotesButton.Visible = true

	MainFrame.Search.SearchBox.Visible = true
	MainFrame.Search.SearchLabel.Visible = true

	MainFrame.SoulDisplay.SoulDisplay.Visible = true
	MainFrame.SoulDisplay.GamepassPage.Visible = true

	if backButton then backButton.Visible = false end

	SearchQuery = ""
	SearchBox.Text = ""
	CurrentCategory = "Killers"
	InventoryFunctions.UpdateCategoryButtons("Killers")

	InventoryFunctions.ResetCharacterSelection()
	InventoryFunctions.loadCategory(CurrentCategory)
end

function InventoryFunctions.ToggleInventory()
	if isLoadingUI then return end
	if Player:GetAttribute("IsPlayerInRound") == true then return end

	isLoadingUI = true

	local isOpen = InventoryGui:GetAttribute("Open") or false
	local newState = not isOpen

	InventoryGui:SetAttribute("Open", newState)
	MainFrame.Visible = newState

	if newState then
		SearchQuery = ""
		SearchBox.Text = ""

		if isInMoreInfo or isInSkinsMode then
			InventoryFunctions.OnBackButtonClicked()
		else
			InventoryFunctions.loadCategory(CurrentCategory)
		end
	else
		InventoryFunctions.TriggerCleanupTimer()
	end

	task.wait(0.2)
	isLoadingUI = false
end

function InventoryFunctions.OpenCategory(categoryName: string)
	if not (InventoryGui:GetAttribute("Open") == true) or isLoadingUI then return end
	if CurrentCategory == categoryName and not isInMoreInfo and not isInSkinsMode then return end

	isLoadingUI = true
	CurrentCategory = categoryName

	if isInMoreInfo or isInSkinsMode then
		InventoryFunctions.OnBackButtonClicked()
	end

	SearchQuery = ""
	SearchBox.Text = ""
	InventoryFunctions.UpdateCategoryButtons(CurrentCategory)
	InventoryFunctions.loadCategory(CurrentCategory)

	task.wait(0.25)
	isLoadingUI = false
end

function InventoryFunctions.OnEquipButtonClicked()
	if not (InventoryGui:GetAttribute("Open") == true) or isLoadingUI or isEquipping then return end

	if Player:GetAttribute("IsPlayerInRound") == true then
		MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Locked!"
		task.wait(1)
		MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equip"
		return
	end

	if isInSkinsMode then
		if not SelectedSkin or not SelectedCharacter then return end
		isEquipping = true
		MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "..."

		local result = ReplicatedStorage.Remotes.InventoryFunction:InvokeServer(SelectedSkin, "EquipSkin", SelectedCharacter)

		if result == "SUCCESS" or result == "ALREADY_EQUIPPED" then
			MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equipped"
		else
			MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equip"
		end

		task.wait(0.2)
		isEquipping = false
		return
	end

	if not SelectedCharacter then return end

	local characterId = SelectedCharacter
	local categoryName = CategoryLookup[characterId]
	if not categoryName then return end

	local equippedValueName = "Equipped" .. categoryName
	local CharacterFolder = Player:FindFirstChild("Characters")
	if CharacterFolder and CharacterFolder:FindFirstChild(equippedValueName) then
		if CharacterFolder[equippedValueName].Value == characterId then return end
	end

	isEquipping = true
	MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "..."

	local result = ReplicatedStorage.Remotes.InventoryFunction:InvokeServer(characterId, "Equip")

	if result == "SUCCESS" or result == "ALREADY_EQUIPPED" then
		MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equipped"
	else
		MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equip"
	end

	task.wait(0.2)
	isEquipping = false
end

function InventoryFunctions.OnGamepassButtonClicked()
	if not (InventoryGui:GetAttribute("Open") == true) or isLoadingUI then return end

	local ShopGui = script.Parent.Parent:FindFirstChild("ShopGui")
	if not ShopGui then return end

	local ShopFunctions = require(ShopGui.ShopFunctions)
	if not ShopFunctions then return end

	InventoryGui:SetAttribute("Open", false)
	InventoryGui.MainFrame.Visible = false
	InventoryGui.MainFrame.CharacterFrame.Visible = false

	local isShopOpen = ShopGui:GetAttribute("Open") == true

	if isShopOpen then
		ShopFunctions.OpenCategory("Gamepass", Color3.fromRGB(0, 255, 0))
	else
		ShopGui:SetAttribute("Open", true)
		ShopGui.MainFrame.Visible = true
		ShopFunctions.OpenCategory("Gamepass", Color3.fromRGB(0, 255, 0))
	end
end

function InventoryFunctions.UpdateCategoryButtons(CategoryName: string)
	local Buttons = {
		Killers = CategoryButtons.KillersButton,
		Survivors = CategoryButtons.SurvivorsButton,
		Emotes = CategoryButtons.EmotesButton
	}

	for name, button in pairs(Buttons) do
		if name == CategoryName then
			button.TextColor3 = Color3.fromRGB(0, 0, 0)
			button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			button.BackgroundTransparency = 0
		else
			button.TextColor3 = Color3.fromRGB(255, 255, 255)
			button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			button.BackgroundTransparency = 0.9
		end
	end
end

function InventoryFunctions.RenderThumbnail(viewport: ViewportFrame, modelId: string, isSkin: boolean, baseCharacterId: string)
	local worldModel = viewport:FindFirstChildWhichIsA("WorldModel")
	if not worldModel then
		worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport
	end

	local ModelPool = ReplicatedStorage:FindFirstChild("ModelPool") 
	if not ModelPool then
		ModelPool = Instance.new("Folder")
		ModelPool.Name = "ModelPool"
		ModelPool.Parent = ReplicatedStorage
	end

	for _, child in ipairs(worldModel:GetChildren()) do
		child.Parent = ModelPool
	end

	local targetModelTemplate = nil
	if isSkin then
		if modelId == "Default" and baseCharacterId then
			targetModelTemplate = CharacterModels:FindFirstChild(baseCharacterId)
		else
			local SkinModels = ReplicatedStorage:FindFirstChild("SkinModels")
			if SkinModels then
				targetModelTemplate = SkinModels:FindFirstChild(modelId)
			end
		end
	else
		if CharacterModels then
			targetModelTemplate = CharacterModels:FindFirstChild(modelId)
		end
	end

	if not targetModelTemplate then
		return
	end

	local modelClone = ModelPool:FindFirstChild(modelId)
	if not modelClone then
		modelClone = targetModelTemplate:Clone()
		modelClone.Name = modelId
	end

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
function InventoryFunctions.CharacterSelected(CharacterData)
	if not CharacterData or typeof(CharacterData) ~= "table" then return end

	local CharacterFolder = Player:FindFirstChild("Characters")
	if not CharacterFolder then return end

	local ownerEntry = CharacterFolder:FindFirstChild(CharacterData.Id)
	if not ownerEntry then return end

	local CharacterLevelValue = ownerEntry:FindFirstChild("CurrentLevel") :: IntValue
	if not CharacterLevelValue then return end

	local categoryName = CategoryLookup[CharacterData.Id]
	local equippedValueName = categoryName and ("Equipped" .. categoryName) or nil

	if equippedValueName and CharacterFolder:FindFirstChild(equippedValueName) and CharacterFolder[equippedValueName].Value == CharacterData.Id then
		MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equipped"
	else
		MainFrame.CharacterFrame.ActionFrame.EquipButton.Text = "Equip"
	end

	MainFrame.CharacterFrame.CharacterInfoFrame.CharacterName.Text = tostring(CharacterData.Name)
	MainFrame.CharacterFrame.CharacterInfoFrame.CurrentLevel.Text = tostring(CharacterLevelValue.Value)
	MainFrame.CharacterFrame.CharacterInfoFrame.CurrentLevel.Visible = true
	MainFrame.CharacterFrame.CharacterInfoFrame.MaxLevelLabel.Visible = (CharacterLevelValue.Value >= 100)
	MainFrame.CharacterFrame.ActionFrame.SkinsButton.Visible = true

	local activeSkinId = "Default"
	local charFolder = CharacterFolder:FindFirstChild(CharacterData.Id)
	if charFolder then
		local equippedSkinVal = charFolder:FindFirstChild("EquippedCharacterSkin")
		if equippedSkinVal and equippedSkinVal:IsA("StringValue") then
			activeSkinId = equippedSkinVal.Value
		end
	end

	InventoryFunctions.RenderThumbnail(MainFrame.CharacterFrame.CharacterInfoFrame.CharacterDisplayFrame, activeSkinId, true, CharacterData.Id)

	SelectedCharacter = CharacterData.Id
	MainFrame.CharacterFrame.Visible = true
end

function InventoryFunctions.ResetCharacterSelection()
	MainFrame.CharacterFrame.Visible = false
	SelectedCharacter = nil

	MainFrame.CharacterFrame.CharacterInfoFrame.CharacterName.Text = "Character Name"
	MainFrame.CharacterFrame.CharacterInfoFrame.CurrentLevel.Text = "1"
	MainFrame.CharacterFrame.CharacterInfoFrame.MaxLevelLabel.Visible = false
	MainFrame.CharacterFrame.ActionFrame.SkinsButton.Visible = false

	InventoryFunctions.ClearCharacterDisplayFrame()
end

function InventoryFunctions.CreateTemplate(CharacterId: string)
	local CharacterData = CharacterLookup[CharacterId]
	if not CharacterData then return end

	local Template = CharacterTemplate:Clone()
	Template.Name = CharacterId
	Template.CharacterName.Text = tostring(CharacterData.Name)
	Template.Active = true
	Template.Interactable = true
	Template.Visible = true

	InventoryFunctions.RenderThumbnail(Template, CharacterId, false, nil)
	Template.Parent = MainFrame.Container

	Template.InputBegan:Connect(function(Input: InputObject)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			InventoryFunctions.CharacterSelected(CharacterData)
		end
	end)
end

function InventoryFunctions.loadCategory(category: string)
	local NewCategory = InventoryFunctions.CategoryTranslation(category)

	if NewCategory == "Emotes" then
		for _, child in ipairs(MainFrame.Container:GetChildren()) do
			if child:IsA("GuiObject") and not child:IsA("UIGridLayout") and child.Name ~= "ActiveGeneralInfo" and not child:HasTag("InventorySkinTemplate") then
				child.Visible = false
			end
		end
		InventoryFunctions.ResetCharacterSelection()
		return
	end

	if not NewCategory then return end
	local characterList = CharactersModule[NewCategory]
	if not characterList then return end

	InventoryFunctions.ResetCharacterSelection()

	local currentCategoryIds = {}
	for _, data in pairs(characterList) do
		currentCategoryIds[tostring(data.Id)] = true
	end

	for _, child in ipairs(MainFrame.Container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") and child.Name ~= "ActiveGeneralInfo" and not child:HasTag("InventorySkinTemplate") then
			if not currentCategoryIds[child.Name] then
				child.Visible = false
			end
		end
	end

	local CharacterFolder = Player:FindFirstChild("Characters")
	for _, data in ipairs(characterList) do
		local existingTemplate = MainFrame.Container:FindFirstChild(data.Id)

		local ownsCharacter = false
		if CharacterFolder then
			local OwnershipValue = CharacterFolder:FindFirstChild(data.Id)
			ownsCharacter = (OwnershipValue and OwnershipValue:IsA("BoolValue") and OwnershipValue.Value == true)
		end

		if existingTemplate then
			existingTemplate.Visible = ownsCharacter
		elseif ownsCharacter then
			InventoryFunctions.CreateTemplate(data.Id)
		end
	end

	InventoryFunctions.FilterTemplates()
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	SearchQuery = SearchBox.Text
	InventoryFunctions.FilterTemplates()
end)

SearchBox.FocusLost:Connect(function(enterPressed: boolean)
	if enterPressed then
		SearchBox:ReleaseFocus()
	end
end)

InventoryGui.ToggleOpen.MouseButton1Click:Connect(function() InventoryFunctions.ToggleInventory() end)
CategoryButtons.KillersButton.MouseButton1Click:Connect(function() InventoryFunctions.OpenCategory("Killers") end)
CategoryButtons.SurvivorsButton.MouseButton1Click:Connect(function() InventoryFunctions.OpenCategory("Survivors") end)
CategoryButtons.EmotesButton.MouseButton1Click:Connect(function() InventoryFunctions.OpenCategory("Emotes") end)

MainFrame.CharacterFrame.ActionFrame.EquipButton.MouseButton1Click:Connect(InventoryFunctions.OnEquipButtonClicked)
MainFrame.CharacterFrame.ActionFrame.MoreInfoButton.MouseButton1Click:Connect(InventoryFunctions.OnMoreInfoButtonClicked)
MainFrame.CharacterFrame.ActionFrame.SkinsButton.MouseButton1Click:Connect(InventoryFunctions.OnSkinsButtonClicked)
MainFrame.SoulDisplay.GamepassPage.MouseButton1Click:Connect(InventoryFunctions.OnGamepassButtonClicked)

if backButton then
	backButton.MouseButton1Click:Connect(InventoryFunctions.OnBackButtonClicked)
end

Player:GetAttributeChangedSignal("IsPlayerInRound"):Connect(function()
	if Player:GetAttribute("IsPlayerInRound") == true then
		if isInMoreInfo or isInSkinsMode then
			InventoryFunctions.OnBackButtonClicked()
		end
		InventoryGui:SetAttribute("Open", false)
		MainFrame.Visible = false
		InventoryFunctions.ResetCharacterSelection()
		isLoadingUI = false
		InventoryFunctions.TriggerCleanupTimer()
	end
end)

task.spawn(function()
	local leaderstats = Player:WaitForChild("leaderstats", 10) :: Folder
	if leaderstats then
		local SoulsValue = leaderstats:WaitForChild("Souls") :: IntValue
		MainFrame.SoulDisplay.SoulDisplay.Text = "$" .. tostring(SoulsValue.Value)
		SoulsValue:GetPropertyChangedSignal("Value"):Connect(function()
			MainFrame.SoulDisplay.SoulDisplay.Text = "$" .. tostring(SoulsValue.Value)
		end)
	end
end)

return InventoryFunctions
