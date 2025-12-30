local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent



local handler = gui:WaitForChild("Handler", 10)
local popout = gui:WaitForChild("Popout", 10)
local sample = script:FindFirstChild("Sample")

if not handler or not popout or not sample then
	warn("InventoryGUI: Critical elements missing (Handler, Popout, or Sample)")
	return
end


local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
local getInventoryFunc = remoteEvents:WaitForChild("GetInventoryFunction", 10)
local getEquippedFunc = remoteEvents:WaitForChild("GetEquippedItemsFunction", 10)
local equipItemEvent = remoteEvents:WaitForChild("EquipItemEvent", 10)
local inventoryUpdatedEvent = remoteEvents:WaitForChild("InventoryUpdatedEvent", 10)

if not getInventoryFunc or not getEquippedFunc or not equipItemEvent then
	warn("InventoryGUI: Remote functions/events missing")
	return
end


local currentInventory = {}
local equippedItems = {}

local selectedItem = nil


local uiName = popout:WaitForChild("ItemName", 5)
local uiImage = popout:WaitForChild("ImageLabel", 5)
local uiValue = popout:FindFirstChild("Value") 

local btnEquip = popout:WaitForChild("Equip", 5)

if not uiName or not uiImage or not btnEquip then
	warn("InventoryGUI: Missing Popout elements (ItemName, ImageLabel, or Equip)")
end


local function formatNumber(n)
	return tostring(n):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
end


local currentTab = "Swords" -- "Swords" or "Abilities"

-- Tab Elements (Assumed to be created or I will create them logically if missing)
-- For now, let's assume the GUI structure is getting updated or we inject buttons.
-- User mentioned "Inventory.Tabs is a frame, with Swords and Abilities buttons"

local tabsFrame = popout.Parent:FindFirstChild("Tabs") or gui:FindFirstChild("Tabs")
if not tabsFrame then
	-- Create logic to support tabs if missing, or just warn. 
	-- Assuming user said they updated it, let's try to find them.
	tabsFrame = popout.Parent:FindFirstChild("Tabs")
end

local btnTabSwords = tabsFrame and tabsFrame:FindFirstChild("Swords")
local btnTabAbilities = tabsFrame and tabsFrame:FindFirstChild("Abilities")




local function updatePopout()
	if not selectedItem then
		popout.Visible = false
		return
	end

	popout.Visible = true

	if uiName then uiName.Text = selectedItem.Name end

	if uiImage then
		local rbxId = selectedItem.RobloxId or 0
		if type(rbxId) == "string" and (string.find(rbxId, "rbxassetid") or string.find(rbxId, "http")) then
			uiImage.Image = rbxId
		else
			uiImage.Image = "rbxthumb://type=Asset&id=" .. rbxId .. "&w=420&h=420"
		end
	end

	if uiValue and selectedItem.Value then
		uiValue.Text = "R$ " .. formatNumber(selectedItem.Value)
	elseif uiValue then
		uiValue.Text = ""
	end

	if btnEquip then
		local isEquipped = false
		if selectedItem.Type == "Ability" then
			-- Logic for checking if Ability is equipped
			-- We don't have the equipped ability in 'equippedItems' map yet because it's set up for swords
			-- Let's fetch equipped items again or assume logic needed in refreshInventory
		else
			isEquipped = equippedItems[selectedItem.Name]
		end

		-- Quick refresh of equipped status from the last fetch
		-- We need to know if THIS item is equipped.
		-- 'equippedItems' is a set for swords, but we need to track ability too.

		-- Let's rely on refreshInventory to populate a comprehensive 'equippedSet'
		isEquipped = equippedItems[selectedItem.Name]

		if isEquipped then
			btnEquip.Text = "Unequip"
		else
			btnEquip.Text = "Equip"
		end
	end
end

local function refreshInventory()
	local successInv, invData = pcall(function() return getInventoryFunc:InvokeServer() end)
	local successEq, eqData = pcall(function() return getEquippedFunc:InvokeServer() end)

	if not successInv or not invData then
		warn("InventoryGUI: Failed to fetch inventory")
		return
	end

	currentInventory = invData

	equippedItems = {}
	if successEq and eqData then
		for _, name in ipairs(eqData) do
			equippedItems[name] = true
		end
	end

	for _, child in ipairs(handler:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Filter items based on Tab
	local filteredItems = {}
	for _, item in ipairs(currentInventory) do
		-- Determine Item Type if not explicitly set (Legacy compatibility)
		local iType = item.Type or "Sword" 

		-- Tab Filtering
		if currentTab == "Swords" and iType == "Sword" then
			table.insert(filteredItems, item)
		elseif currentTab == "Abilities" and iType == "Ability" then
			table.insert(filteredItems, item)
		end
	end

	for i, item in ipairs(filteredItems) do
		local clone = sample:Clone()
		clone.Name = item.Name
		clone.LayoutOrder = i
		clone.Parent = handler
		clone.Visible = true

		if clone:IsA("ImageButton") then
			local rbxId = item.RobloxId or 0
			if type(rbxId) == "string" and (string.find(rbxId, "rbxassetid") or string.find(rbxId, "http")) then
				clone.Image = rbxId
			else
				clone.Image = "rbxthumb://type=Asset&id=" .. rbxId .. "&w=150&h=150"
			end
		end

		local qty = clone:FindFirstChild("Qty")
		if qty and item.Amount then
			qty.Text = "x" .. item.Amount
			qty.Visible = (item.Amount > 1)
		end

		clone.MouseButton1Click:Connect(function()
			selectedItem = item
			updatePopout()
		end)
	end

	if selectedItem then
		-- Check if selected item is still valid for current tab
		local isValid = false
		for _, item in ipairs(filteredItems) do
			if item.Name == selectedItem.Name then isValid = true break end
		end

		if isValid then
			updatePopout()
		else
			selectedItem = nil
			popout.Visible = false
		end
	end
end


if btnEquip then
	btnEquip.MouseButton1Click:Connect(function()
		if not selectedItem then return end

		local itemName = selectedItem.Name
		local itemType = selectedItem.Type or "Sword"
		local isCurrentlyEquipped = equippedItems[itemName]

		if isCurrentlyEquipped then
			equipItemEvent:FireServer(itemName, true, itemType)
			equippedItems[itemName] = nil
			if btnEquip then btnEquip.Text = "Equip" end
		else
			equipItemEvent:FireServer(itemName, false, itemType)

			-- Client side prediction for UI update
			if itemType == "Ability" then
				-- Can only equip one ability type
				-- Clear other abilities from equipped set?
				-- For now, refreshInventory handles the source of truth
			else
				equippedItems = {} -- Single sword equip logic
			end
			equippedItems[itemName] = true
			if btnEquip then btnEquip.Text = "Unequip" end
		end

		task.wait(0.1)
		refreshInventory()
	end)
end


if inventoryUpdatedEvent then
	inventoryUpdatedEvent.OnClientEvent:Connect(refreshInventory)
end

gui:GetPropertyChangedSignal("Visible"):Connect(function()
	if gui.Visible then
		refreshInventory()
	end
end)


local mainUI = gui.Parent

if btnTabSwords then
	btnTabSwords.MouseButton1Click:Connect(function()
		currentTab = "Swords"
		refreshInventory()
	end)
end

if btnTabAbilities then
	btnTabAbilities.MouseButton1Click:Connect(function()
		currentTab = "Abilities"
		refreshInventory()
	end)
end

local inventoryButton = mainUI:FindFirstChild("InventoryButton")

if inventoryButton then
	inventoryButton.MouseButton1Click:Connect(function()
		gui.Visible = not gui.Visible
	end)
else
	warn("InventoryGUI: InventoryButton not found in MainUI")
end

task.spawn(refreshInventory)
