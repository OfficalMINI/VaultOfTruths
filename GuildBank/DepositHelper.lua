------------------------------------------------------------------------
-- Vault of Truths - GuildBank/DepositHelper.lua
-- Helpers for bulk depositing items from bags to guild bank
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.DepositHelper = {}
local DH = GF.DepositHelper
GF:RegisterModule("DepositHelper", DH)

local depositQueue = {}
local isDepositing = false
local depositTimer = nil
local DEPOSIT_INTERVAL = 0.3 -- seconds between moves (throttle)

function DH:Init()
    -- Nothing to init yet; hooks added when guild bank is open
end

--- Scan player bags for bankable PVP items
---@return table Array of { bag, slot, itemID, quantity, link, value }
function DH:FindBankableItems()
    local found = {}

    for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                if GF.PVPItems:IsBankable(info.itemID) then
                    local value, source = GF.TSM:GetBestPrice(info.itemID)
                    found[#found + 1] = {
                        bag = bag,
                        slot = slot,
                        itemID = info.itemID,
                        quantity = info.stackCount or 1,
                        link = info.hyperlink,
                        value = value,
                        priceSource = source,
                        totalValue = value and (value * (info.stackCount or 1)) or nil,
                    }
                end
            end
        end
    end

    return found
end

--- Queue items for deposit into a specific guild bank tab
---@param items table Array from FindBankableItems
---@param targetTab number Guild bank tab index
function DH:QueueDeposit(items, targetTab)
    if not items or #items == 0 then
        print("|cFF33AAFF[Vault of Truths]|r No items to deposit.")
        return
    end

    for _, item in ipairs(items) do
        depositQueue[#depositQueue + 1] = {
            bag = item.bag,
            slot = item.slot,
            targetTab = targetTab,
            itemID = item.itemID,
            link = item.link,
        }
    end

    if GF.debug then
        print("|cFF33AAFF[Vault of Truths]|r Queued " .. #items .. " items for deposit to tab " .. targetTab)
    end

    if not isDepositing then
        self:ProcessQueue()
    end
end

--- Process the deposit queue one item at a time
function DH:ProcessQueue()
    if #depositQueue == 0 then
        isDepositing = false
        GF.Events:Fire("GF_DEPOSIT_COMPLETE")
        if GF.debug then
            print("|cFF33AAFF[Vault of Truths]|r Deposit queue complete.")
        end
        return
    end

    isDepositing = true
    local item = table.remove(depositQueue, 1)

    -- Pick up item from bag and place in guild bank
    C_Container.PickupContainerItem(item.bag, item.slot)

    -- Find an empty slot in the target tab
    local emptySlot = self:FindEmptySlot(item.targetTab)
    if emptySlot then
        PickupGuildBankItem(item.targetTab, emptySlot)
    else
        -- Try to stack with existing items of same type
        local stackSlot = self:FindStackableSlot(item.targetTab, item.itemID)
        if stackSlot then
            PickupGuildBankItem(item.targetTab, stackSlot)
        else
            -- No space — clear cursor and warn
            ClearCursor()
            print("|cFFFF0000[Vault of Truths]|r No space in guild bank tab " .. item.targetTab .. " for " .. (item.link or "item"))
        end
    end

    -- Schedule next item
    C_Timer.After(DEPOSIT_INTERVAL, function()
        DH:ProcessQueue()
    end)
end

--- Find an empty slot in a guild bank tab
---@param tab number Tab index
---@return number|nil slot
function DH:FindEmptySlot(tab)
    local MAX_SLOTS = 98
    for slot = 1, MAX_SLOTS do
        local texture = GetGuildBankItemInfo(tab, slot)
        if not texture then
            return slot
        end
    end
    return nil
end

--- Find a slot with the same item that can be stacked
---@param tab number Tab index
---@param itemID number
---@return number|nil slot
function DH:FindStackableSlot(tab, itemID)
    local MAX_SLOTS = 98
    for slot = 1, MAX_SLOTS do
        local texture, count = GetGuildBankItemInfo(tab, slot)
        if texture then
            local link = GetGuildBankItemLink(tab, slot)
            local slotItemID = link and GF.Utils:GetItemIDFromLink(link)
            if slotItemID == itemID then
                -- Check if stack has room
                local maxStack = select(8, C_Item.GetItemInfo(itemID)) or 1
                if count < maxStack then
                    return slot
                end
            end
        end
    end
    return nil
end

--- Cancel any pending deposits
function DH:CancelDeposit()
    wipe(depositQueue)
    isDepositing = false
    ClearCursor()
    print("|cFF33AAFF[Vault of Truths]|r Deposit cancelled.")
end

--- Get the number of items still in the deposit queue
---@return number
function DH:GetQueueSize()
    return #depositQueue
end

--- Check if a deposit is currently in progress
---@return boolean
function DH:IsDepositing()
    return isDepositing
end
