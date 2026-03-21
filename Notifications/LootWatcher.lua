------------------------------------------------------------------------
-- Vault of Truths - Notifications/LootWatcher.lua
-- Detects bankable items from loot, vendors, mail, trade, bags
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.LootWatcher = {}
local LW = GF.LootWatcher
GF:RegisterModule("LootWatcher", LW)

local knownBagItems = {} -- [bag:slot] = { itemID, count }
local bagScanInitialized = false
local guildBankOpen = false -- suppress notifications while withdrawing from bank
local mailboxOpen = false  -- suppress notifications while collecting mail

function LW:Init()
    -- Track guild bank / mailbox open to suppress false notifications
    GF.Events:Register("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(event, interactionType)
        if interactionType == 10 then -- guild bank
            guildBankOpen = true
        elseif interactionType == 17 then -- mailbox
            mailboxOpen = true
        end
    end)
    GF.Events:Register("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(event, interactionType)
        if interactionType == 10 then
            C_Timer.After(2, function()
                guildBankOpen = false
                LW:InitBagState()
            end)
        elseif interactionType == 17 then
            C_Timer.After(2, function()
                mailboxOpen = false
                LW:InitBagState()
            end)
        end
    end)

    -- Loot drops
    GF.Events:Register("CHAT_MSG_LOOT", function(event, msg)
        if GF.Settings:GetChar("lootWatcher.enabled") ~= false then
            LW:OnLootMessage(msg)
        end
    end)

    -- Bag changes (catches everything: loot, vendor, mail, trade, craft)
    GF.Events:Register("BAG_UPDATE_DELAYED", function()
        if GF.Settings:GetChar("lootWatcher.enabled") ~= false and not guildBankOpen and not mailboxOpen then
            LW:ScanBagsForNew()
        end
    end)

    -- Vendor window closed — scan after purchase
    GF.Events:Register("MERCHANT_CLOSED", function()
        if GF.Settings:GetChar("lootWatcher.enabled") ~= false then
            -- Short delay to let bag update finish
            C_Timer.After(0.3, function()
                LW:ScanBagsForNew()
            end)
        end
    end)

    -- Mail collected — suppressed while mailbox is open to avoid spam
    -- Items will be detected after mailbox closes and bags are re-snapshotted

    -- Initialize bag state on login
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(3, function()
            LW:InitBagState()
        end)
    end)
end

--- Parse a CHAT_MSG_LOOT message for item links
function LW:OnLootMessage(msg)
    local link = msg:match("|c%x+|Hitem:.-|h%[.-%]|h|r")
    if not link then return end

    local itemID = GF.Utils:GetItemIDFromLink(link)
    if not itemID then return end

    local isBankable, reason = GF.PVPItems:CheckLootedItem(itemID, link)
    if isBankable then
        self:NotifyBankableItem(itemID, link, reason)
    end
end

--- Notify about a bankable item (used by both loot and bag scan)
function LW:NotifyBankableItem(itemID, link, reason)
    local value, source = GF.TSM:GetBestPrice(itemID)

    if GF.Toast then
        GF.Toast:LootNotify(link or ("Item:" .. itemID), value)
    end

    if GF.Settings:GetChar("lootWatcher.autoPrintValue") ~= false then
        local valueStr = value and GF.Utils:FormatMoney(value) or "N/A"
        local sourceStr = source and (" (" .. source .. ")") or ""
        local reasonStr = reason and (" [" .. reason .. "]") or ""
        local linkStr = link or ("Item:" .. itemID)
        GF.ChatNotify:Info("Bankable: " .. linkStr .. " — " .. valueStr .. sourceStr .. reasonStr)
    end

    GF.Events:Fire("GF_BANKABLE_ITEM_LOOTED", itemID, link, value)
end

--- Initialize known bag state (baseline snapshot)
function LW:InitBagState()
    wipe(knownBagItems)
    for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local key = bag .. ":" .. slot
                knownBagItems[key] = { itemID = info.itemID, count = info.stackCount or 1 }
            end
        end
    end
    bagScanInitialized = true
end

--- Scan bags and detect new or increased items since last snapshot
function LW:ScanBagsForNew()
    if not bagScanInitialized then
        self:InitBagState()
        return
    end

    local newBagItems = {}
    local foundNew = {}

    for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local key = bag .. ":" .. slot
                local known = knownBagItems[key]

                -- New item in this slot, or different item, or stack increased
                local isNew = false
                if not known then
                    isNew = true
                elseif known.itemID ~= info.itemID then
                    isNew = true
                elseif info.stackCount > known.count then
                    isNew = true
                end

                if isNew then
                    -- Dedupe: only notify once per itemID per scan
                    if not foundNew[info.itemID] then
                        foundNew[info.itemID] = true

                        local bankable, reason = GF.PVPItems:CheckLootedItem(info.itemID, info.hyperlink)
                        if bankable then
                            self:NotifyBankableItem(info.itemID, info.hyperlink, reason)
                        end
                    end
                end

                newBagItems[key] = { itemID = info.itemID, count = info.stackCount or 1 }
            end
        end
    end

    knownBagItems = newBagItems
end
