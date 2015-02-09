--[[
	item.lua
		An item slot button
--]]

local ADDON, Addon = ...
local ItemSlot = Addon:NewClass('ItemSlot', 'Button')
ItemSlot.dummyBags = {}
ItemSlot.unused = {}
ItemSlot.nextID = 0

local Cache = LibStub('LibItemCache-1.1')
local ItemSearch = LibStub('LibItemSearch-1.2')
local Unfit = LibStub('Unfit-1.0')
local QuestSearch = format('t:%s|%s', select(10, GetAuctionItemClasses()), 'quest')


--[[ Constructor ]]--

function ItemSlot:New()
	return self:Restore() or self:Create()
end

function ItemSlot:Create()
	local id = self:GetNextItemSlotID()
	local item = self:Bind(self:GetBlizzardItemSlot(id) or self:ConstructNewItemSlot(id))
	local name = item:GetName()

	-- add a quality border texture
	local border = item:CreateTexture(nil, 'OVERLAY')
	border:SetSize(67, 67)
	border:SetPoint('CENTER', item)
	border:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
	border:SetBlendMode('ADD')
	border:Hide()

	-- add flash find animation
	local flash = item:CreateAnimationGroup()
	for i = 1, 3 do
		local fade = flash:CreateAnimation('Alpha')
		fade:SetDuration(.2)
		fade:SetChange(-.8)
		fade:SetOrder(i * 2)

		local fade = flash:CreateAnimation('Alpha')
		fade:SetDuration(.3)
		fade:SetChange(.8)
		fade:SetOrder(i * 2 + 1)
	end
	
	item.UpdateTooltip = nil
	item.Border, item.Flash = border, flash
	item.newitemglowAnim:SetLooping('NONE')
	item.QuestBorder = _G[name .. 'IconQuestTexture']
	item.Cooldown = _G[name .. 'Cooldown']
	item:SetScript('OnShow', item.OnShow)
	item:SetScript('OnHide', item.OnHide)
	item:SetScript('PreClick', item.OnPreClick)
	item:HookScript('OnDragStart', item.OnDragStart)
	item:HookScript('OnClick', item.OnClick)
	item:SetScript('OnEnter', item.OnEnter)
	item:SetScript('OnLeave', item.OnLeave)
	item:SetScript('OnEvent', nil)

	return item
end

function ItemSlot:ConstructNewItemSlot(id)
	return CreateFrame('Button', ('%s%s%d'):format(ADDON, self.Name, id), nil, 'ContainerFrameItemButtonTemplate')
end

function ItemSlot:GetBlizzardItemSlot(id)
	if not Addon:AreBasicFramesEnabled() or not Addon.sets.useBlizzard then
		return
	end

	local bag = ceil(id / MAX_CONTAINER_ITEMS)
	local slot = (id-1) % MAX_CONTAINER_ITEMS + 1
	local item = _G[format('ContainerFrame%dItem%d', bag, slot)]

	if item then
		item:SetID(0)
		item:ClearAllPoints()
		return item
	end
end

function ItemSlot:Restore()
	return tremove(self.unused)
end

function ItemSlot:GetNextItemSlotID()
  self.nextID = self.nextID + 1
  return self.nextID
end

function ItemSlot:Free()
	self:Hide()
	self:SetParent(nil)
	self.depositSlot = nil
	tinsert(self.unused, self)
end


--[[ Interaction ]]--

function ItemSlot:OnShow()
	self:RegisterMessage('SEARCH_UPDATE', 'UpdateSearch')
	self:RegisterMessage('FLASH_ITEM', 'OnItemFlashed')
	self:Update()
end

function ItemSlot:OnHide()
	if self.hasStackSplit == 1 then
		StackSplitFrame:Hide()
	end

	if self:IsNew() then
		C_NewItems.RemoveNewItem(self:GetBag(), self:GetID())
	end

	self:UnregisterMessages()
end

function ItemSlot:OnDragStart()
	ItemSlot.Cursor = self
end

function ItemSlot:OnPreClick(button)
	if not IsModifiedClick() and button == 'RightButton' then
		if Cache.atBank and IsReagentBankUnlocked() and GetContainerNumFreeSlots(REAGENTBANK_CONTAINER) > 0 and ItemSearch:TooltipPhrase(self:GetItem(), PROFESSIONS_USED_IN_COOKING) then
			return UseContainerItem(self:GetBag(), self:GetID(), nil, true)
		end

		if not self.canDeposit then
			for i = 1,9 do
				if not GetVoidTransferDepositInfo(i) then
					self.depositSlot = i
					return
				end
			end
		end
	end
end

function ItemSlot:OnClick(button)
	if IsAltKeyDown() and button == 'LeftButton' then
		if Addon.sets.flashFind then
			self:SendMessage('FLASH_ITEM', self:GetItem())
		end
	elseif GetNumVoidTransferDeposit() > 0 and button == 'RightButton' then
		if self.canDeposit and self.depositSlot then
			ClickVoidTransferDepositSlot(self.depositSlot, true)
		end

		self.canDeposit = not self.canDeposit
	end
end

function ItemSlot:OnModifiedClick(...)
	local link = self:IsCached() and self:GetItem()
	if link and not HandleModifiedItemClick(link) then
		self:OnClick(...)
	end
end

function ItemSlot:OnEnter()
	if self:IsCached() then
		local dummy = self:GetDummySlot()
		dummy:SetParent(self)
		dummy:SetAllPoints(self)
		dummy:Show()
	elseif self:GetItem() then
		self:AnchorTooltip()
		self:ShowTooltip()
		self:UpdateBorder()
	else
		self:OnLeave()
	end
end

function ItemSlot:OnLeave()
	GameTooltip:Hide()
	BattlePetTooltip:Hide()
	ResetCursor()
end

function ItemSlot:OnItemFlashed(_,item)
	self.Flash:Stop()

	local link = self:GetItem()
	if link and link:match('item:(%d+)') == item:match('item:(%d+)') then
		self.Flash:Play()
	end
end


--[[ Update ]]--

function ItemSlot:SetTarget(parent, bag, slot)
  	self:SetParent(self:GetDummyBag(parent, bag))
  	self:SetID(slot)
  	self.bag = bag

  	if self:IsVisible() then
  		self:Update()
  	else
		self:Show()
	end
end

function ItemSlot:Update()
	local icon, count, locked, quality, readable, lootable, link = self:GetInfo()
	self:SetItem(link)
	self:SetTexture(icon)
	self:SetCount(count)
	self:SetLocked(locked)
	self:SetReadable(readable)
	self:UpdateBorder()
	self:UpdateCooldown()
	self:UpdateSlotColor()
	self:UpdateSearch()

	if GameTooltip:IsOwned(self) then
		self:UpdateTooltip()
	end
end

function ItemSlot:SetItem(item)
	self.hasItem = item -- CursorUpdate
end

function ItemSlot:GetItem()
	return self.hasItem
end


--[[ Icon ]]--

function ItemSlot:SetTexture(texture)
	SetItemButtonTexture(self, texture or self:GetEmptyItemIcon())
end

function ItemSlot:GetEmptyItemIcon()
	return Addon.sets.emptySlots and 'Interface/PaperDoll/UI-Backpack-EmptySlot'
end


--[[ Slot Color ]]--

function ItemSlot:UpdateSlotColor()
	if not self:GetItem() and Addon.sets.colorSlots then
		local color = Addon.sets[self:GetBagType() .. 'Color']
		self:SetSlotColor(color[1], color[2], color[3])
	else 
		self:SetSlotColor(1, 1, 1)
	end
end

function ItemSlot:SetSlotColor(...)
	SetItemButtonTextureVertexColor(self, ...)
	self:GetNormalTexture():SetVertexColor(...)
end

function ItemSlot:SetCount(count)
	SetItemButtonCount(self, count)
end

function ItemSlot:SetReadable(readable)
	self.readable = readable
end


--[[ Locked ]]--

function ItemSlot:UpdateLocked()
	self:SetLocked(self:IsLocked())
end

function ItemSlot:SetLocked(locked)
	SetItemButtonDesaturated(self, locked)
end

function ItemSlot:IsLocked()
	return select(3, self:GetInfo())
end


--[[ Border Glow ]]--

function ItemSlot:UpdateBorder()
	local _,_,_, quality = self:GetInfo()
	local item = self:GetItem()
	self:HideBorder()

	if item then
		local isQuestItem, isQuestStarter = self:IsQuestItem()
		if isQuestStarter then
			self.QuestBorder:SetTexture(TEXTURE_ITEM_QUEST_BANG)
			self.QuestBorder:Show()
			return
		end

		if Addon.sets.glowNew and self:IsNew() then
			if not self.flashAnim:IsPlaying() then
				self.flashAnim:Play()
				self.newitemglowAnim:SetLooping('NONE')
				self.newitemglowAnim:Play()
			end

			if self:IsPaid() then
				return self.BattlepayItemTexture:Show()
			else
				self.NewItemTexture:SetAtlas(quality and NEW_ITEM_ATLAS_BY_QUALITY[quality] or 'bags-glow-white')
				self.NewItemTexture:Show()
				return
			end
		end

		if Addon.sets.glowQuest and isQuestItem then
			return self:SetBorderColor(1, .82, .2)
		end

		if Addon.sets.glowSet and ItemSearch:InSet(item) then
	   		return self:SetBorderColor(.1, 1, 1)
	  	end

		if Addon.sets.glowUnusable and Unfit:IsItemUnusable(item) then
			return self:SetBorderColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
		end

		if Addon.sets.glowQuality and quality and quality > 1 then
			self:SetBorderColor(GetItemQualityColor(quality))
		end
	end
end

function ItemSlot:SetBorderColor(r, g, b)
	self.Border:SetVertexColor(r, g, b, Addon.sets.glowAlpha)
	self.Border:Show()
end

function ItemSlot:HideBorder()
	self.QuestBorder:Hide()
	self.Border:Hide()
	self.NewItemTexture:Hide()
	self.BattlepayItemTexture:Hide()
end


--[[ Cooldown ]]--

function ItemSlot:UpdateCooldown()
	if self:GetItem() and (not self:IsCached()) then
		ContainerFrame_UpdateCooldown(self:GetBag(), self)
	else
		CooldownFrame_SetTimer(self.Cooldown, 0, 0, 0)
		SetItemButtonTextureVertexColor(self, 1, 1, 1)
	end
end


--[[ Search ]]--

function ItemSlot:UpdateSearch()
	local search = Addon.search or ''
	local matches = search == '' or ItemSearch:Matches(self:GetItem(), search)

	if matches then
		self:SetAlpha(1)
		self:UpdateLocked()
		self:UpdateSlotColor()
		self:UpdateBorder()
	else
		self:SetLocked(true)
		self:SetAlpha(0.4)
		self:HideBorder()
	end
end

function ItemSlot:SetHighlight(enable)
	if enable then
		self:LockHighlight()
	else
		self:UnlockHighlight()
	end
end


--[[ Tooltip ]]--

function ItemSlot:AnchorTooltip()
	if self:GetRight() >= (GetScreenWidth() / 2) then
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
	else
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
	end
end

function ItemSlot:ShowTooltip()
	local bag = self:GetBag()
	local getSlot = Addon:IsBank(bag) and BankButtonIDToInvSlotID or Addon:IsReagents(bag) and ReagentBankButtonIDToInvSlotID
	
	if getSlot then
		GameTooltip:SetInventoryItem('player', getSlot(self:GetID()))
		GameTooltip:Show()
		CursorUpdate(self)
	else
		ContainerFrameItemButton_OnEnter(self)
	end	
end


function ItemSlot:UpdateTooltip()
	self:OnEnter()
end


--[[ Accessor Methods ]]--

function ItemSlot:IsQuestItem()
	local item = self:GetItem()
	if not item then
		return false
	end

	if self:IsCached() then
		return ItemSearch:Matches(item, QuestSearch), false
	else
		local isQuestItem, questID, isActive = GetContainerItemQuestInfo(self:GetBag(), self:GetID())
		return isQuestItem, (questID and not isActive)
	end
end

function ItemSlot:IsNew()
	return self:GetBag() and C_NewItems.IsNewItem(self:GetBag(), self:GetID())
end

function ItemSlot:IsPaid()
	return IsBattlePayItem(self:GetBag(), self:GetID())
end

function ItemSlot:IsCached()
	return select(8, self:GetInfo())
end

function ItemSlot:GetInfo()
	return Cache:GetItemInfo(self:GetPlayer(), self:GetBag(), self:GetID())
end

function ItemSlot:IsSlot(bag, slot)
	return self:GetBag() == bag and self:GetID() == slot
end

function ItemSlot:GetBagType()
	return Addon:GetBagType(self:GetPlayer(), self:GetBag())
end

function ItemSlot:GetBag()
	return self.bag
end


--[[ Dummies ]]--

function ItemSlot:GetDummyBag(parent, bag)
	parent.dummyBags = parent.dummyBags or {}

	if not parent.dummyBags[bag] then
		parent.dummyBags[bag] = ItemSlot:Bind(CreateFrame('Frame', nil, parent))
		parent.dummyBags[bag]:SetID(tonumber(bag) or 1)
	end

	return parent.dummyBags[bag]
end

function ItemSlot:GetDummySlot()
	self.dummySlot = self.dummySlot or self:CreateDummySlot()
	self.dummySlot:Hide()
	return self.dummySlot
end

function ItemSlot:CreateDummySlot()
	local slot = CreateFrame('Button')
	slot:RegisterForClicks('anyUp')
	slot:SetToplevel(true)

	local function Slot_OnEnter(self)
		local parent = self:GetParent()
		local item = parent:IsCached() and parent:GetItem()
		
		if item then
			parent.AnchorTooltip(self)
			
			if item:find('battlepet:') then
				local _, specie, level, quality, health, power, speed = strsplit(':', item)
				local name = item:match('%[(.-)%]')
				
				BattlePetToolTip_Show(tonumber(specie), level, tonumber(quality), health, power, speed, name)
			else
				GameTooltip:SetHyperlink(item)
				GameTooltip:Show()
			end
		end
		
		parent:LockHighlight()
		CursorUpdate(parent)
	end

	local function Slot_OnLeave(self)
		self:GetParent():OnLeave()
		self:Hide()
	end

	local function Slot_OnHide(self)
		local parent = self:GetParent()
		if parent then
			parent:UnlockHighlight()
		end
	end

	local function Slot_OnClick(self, button)
		self:GetParent():OnModifiedClick(button)
	end

	slot.UpdateTooltip = Slot_OnEnter
	slot:SetScript('OnClick', Slot_OnClick)
	slot:SetScript('OnEnter', Slot_OnEnter)
	slot:SetScript('OnLeave', Slot_OnLeave)
	slot:SetScript('OnShow', Slot_OnEnter)
	slot:SetScript('OnHide', Slot_OnHide)
	return slot
end