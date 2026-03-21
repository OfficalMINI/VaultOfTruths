------------------------------------------------------------------------
-- Vault of Truths - GuildBank/Scanner.lua
-- Scans guild bank tabs, detects diffs against previous snapshots
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Scanner = {}
local Scanner = GF.Scanner
GF:RegisterModule("Scanner", Scanner)

local isScanning = false
local pendingTabs = {}
local currentSnapshot = {}

local pollTimer = nil
local POLL_INTERVAL = 30 -- seconds between re-scans while bank is open
local bankIsOpen = false
local sessionDeposits = {} -- accumulated deposits during this bank session

--- Initialize scanner event hooks
function Scanner:Init()
    -- Start scanning when guild bank opens
    -- Midnight: guild bank uses PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE type 10
    -- Register directly on a raw frame to avoid event dispatcher arg issues
    local bankEventFrame = CreateFrame("Frame")
    bankEventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    bankEventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    bankEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    bankEventFrame:SetScript("OnEvent", function(self, event, interactionType)
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and interactionType == 10 then
            if not bankIsOpen then
                -- Only snapshot on FIRST open, not on repeated SHOW events
                Scanner:SnapshotBags()
                wipe(sessionDeposits)
            end
            bankIsOpen = true
            Scanner:StartScan()
            GF.ChatNotify:Info("Guild bank opened — tracking deposits.")
            if pollTimer then pollTimer:Cancel() end
            pollTimer = C_Timer.NewTicker(POLL_INTERVAL, function()
                if bankIsOpen then Scanner:StartScan() end
            end)
        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and interactionType == 10 then
            bankIsOpen = false
            if isScanning then Scanner:FinalizeScan() end
            if pollTimer then pollTimer:Cancel(); pollTimer = nil end
            -- Show summary notification for all deposits this session
            Scanner:ShowDepositSummary()
        elseif event == "BAG_UPDATE_DELAYED" and bankIsOpen then
            Scanner:CheckForDeposits()
        end
    end)

    -- GUILDBANKBAGSLOTS_CHANGED still fires in Midnight for tab scanning
    GF.Events:Register("GUILDBANKBAGSLOTS_CHANGED", function()
        if isScanning then
            Scanner:ProcessCurrentTab()
        end
    end)
end

--- Begin scanning all guild bank tabs
function Scanner:StartScan()
    local numTabs = GetNumGuildBankTabs()
    if numTabs == 0 then
        if GF.debug then
            print("|cFF33AAFF[Vault of Truths]|r No guild bank tabs available.")
        end
        return
    end

    isScanning = true
    currentSnapshot = {}
    pendingTabs = {}

    for i = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(i)
        if isViewable then
            pendingTabs[#pendingTabs + 1] = i
        end
    end

    if GF.debug then
        print("|cFF33AAFF[Vault of Truths]|r Scanning " .. #pendingTabs .. " guild bank tabs...")
    end

    -- Query the first tab
    self:QueryNextTab()
end

--- Query the next pending tab
function Scanner:QueryNextTab()
    if #pendingTabs == 0 then
        self:FinalizeScan()
        return
    end

    local tab = table.remove(pendingTabs, 1)
    self._currentTab = tab
    QueryGuildBankTab(tab)
end

--- Read all slots in the current tab
function Scanner:ProcessCurrentTab()
    local tab = self._currentTab
    if not tab then return end

    local tabData = { items = {} }
    local name, icon = GetGuildBankTabInfo(tab)
    tabData.name = name
    tabData.icon = icon

    local MAX_SLOTS = 98 -- 14 columns x 7 rows per tab
    for slot = 1, MAX_SLOTS do
        local texture, count, locked, isFiltered, quality = GetGuildBankItemInfo(tab, slot)
        if texture then
            local link = GetGuildBankItemLink(tab, slot)
            local itemID = link and GF.Utils:GetItemIDFromLink(link)
            if itemID then
                tabData.items[slot] = {
                    itemID = itemID,
                    quantity = count or 1,
                    link = link,
                    quality = quality,
                }
            end
        end
    end

    currentSnapshot[tab] = tabData

    if GF.debug then
        local itemCount = 0
        for _ in pairs(tabData.items) do itemCount = itemCount + 1 end
        print("|cFF33AAFF[Vault of Truths]|r Tab " .. tab .. " (" .. (name or "?") .. "): " .. itemCount .. " items")
    end

    -- Move to next tab
    self:QueryNextTab()
end

--- Finalize scan: diff against previous snapshot and save
function Scanner:FinalizeScan()
    isScanning = false

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    local previousSnapshot = guildData.bankSnapshots.tabs or {}
    local diff = self:ComputeDiff(previousSnapshot, currentSnapshot)

    -- Save new snapshot
    guildData.bankSnapshots.tabs = currentSnapshot
    guildData.bankSnapshots.lastScan = GF.Utils:GetTime()

    -- Fire events for diff results
    if diff.added and #diff.added > 0 then
        GF.Events:Fire("GF_BANK_ITEMS_ADDED", diff.added)
        if GF.debug then
            print("|cFF33AAFF[Vault of Truths]|r " .. #diff.added .. " new item stacks detected in guild bank.")
        end
    end

    if diff.removed and #diff.removed > 0 then
        GF.Events:Fire("GF_BANK_ITEMS_REMOVED", diff.removed)
        if GF.debug then
            print("|cFF33AAFF[Vault of Truths]|r " .. #diff.removed .. " item stacks removed from guild bank.")
        end
    end

    GF.Events:Fire("GF_BANK_SCAN_COMPLETE", currentSnapshot, diff)

    if GF.debug then
        print("|cFF33AAFF[Vault of Truths]|r Guild bank scan complete.")
    end
end

--- Compute the difference between two snapshots
---@param oldSnap table Previous snapshot
---@param newSnap table Current snapshot
---@return table { added = {}, removed = {}, changed = {} }
function Scanner:ComputeDiff(oldSnap, newSnap)
    local diff = { added = {}, removed = {}, changed = {} }

    -- Build lookup of old items: [tab:slot] = { itemID, quantity }
    local oldItems = {}
    for tab, tabData in pairs(oldSnap) do
        if tabData.items then
            for slot, item in pairs(tabData.items) do
                oldItems[tab .. ":" .. slot] = item
            end
        end
    end

    -- Build lookup of new items
    local newItems = {}
    for tab, tabData in pairs(newSnap) do
        if tabData.items then
            for slot, item in pairs(tabData.items) do
                newItems[tab .. ":" .. slot] = item
            end
        end
    end

    -- Find added/changed items
    for key, newItem in pairs(newItems) do
        local oldItem = oldItems[key]
        if not oldItem then
            diff.added[#diff.added + 1] = {
                tab = tonumber(key:match("^(%d+):")),
                slot = tonumber(key:match(":(%d+)$")),
                itemID = newItem.itemID,
                quantity = newItem.quantity,
                link = newItem.link,
            }
        elseif oldItem.itemID ~= newItem.itemID or oldItem.quantity ~= newItem.quantity then
            diff.changed[#diff.changed + 1] = {
                tab = tonumber(key:match("^(%d+):")),
                slot = tonumber(key:match(":(%d+)$")),
                itemID = newItem.itemID,
                quantity = newItem.quantity,
                oldItemID = oldItem.itemID,
                oldQuantity = oldItem.quantity,
                link = newItem.link,
            }
        end
    end

    -- Find removed items
    for key, oldItem in pairs(oldItems) do
        if not newItems[key] then
            diff.removed[#diff.removed + 1] = {
                tab = tonumber(key:match("^(%d+):")),
                slot = tonumber(key:match(":(%d+)$")),
                itemID = oldItem.itemID,
                quantity = oldItem.quantity,
                link = oldItem.link,
            }
        end
    end

    return diff
end

--- Force a manual scan (slash command handler)
function Scanner:ForceScan()
    if not C_GuildInfo then
        print("|cFF33AAFF[Vault of Truths]|r Guild bank must be open to scan.")
        return
    end
    self:StartScan()
end

--- Get the current snapshot
---@return table|nil
function Scanner:GetSnapshot()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end
    return guildData.bankSnapshots
end

--- Get total item count across all tabs
---@return number
function Scanner:GetTotalItemCount()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.bankSnapshots.tabs then return 0 end

    local count = 0
    for _, tabData in pairs(guildData.bankSnapshots.tabs) do
        if tabData.items then
            for _ in pairs(tabData.items) do
                count = count + 1
            end
        end
    end
    return count
end

-- Track bag item counts for deposit detection
-- Simple approach: [itemID] = { total count, link }
Scanner._bagSnapshot = {}

--- Count all items in bags by itemID
function Scanner:CountBagItems()
    local counts = {}
    for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                if not counts[info.itemID] then
                    counts[info.itemID] = { count = 0, link = info.hyperlink }
                end
                counts[info.itemID].count = counts[info.itemID].count + (info.stackCount or 1)
            end
        end
    end
    return counts
end

--- Snapshot bag item counts when bank opens
function Scanner:SnapshotBags()
    Scanner._bagSnapshot = self:CountBagItems()
end

--- Check what left your bags since snapshot (deposited)
function Scanner:CheckForDeposits()
    local current = self:CountBagItems()
    local playerName = GF.Utils:GetPlayerFullName()

    local deposited = {}
    local withdrawn = {}

    -- Only count deposits into Tab 1 (Public Deposits)
    local currentTab = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or nil

    -- Items that LEFT bags = deposited to bank
    for itemID, old in pairs(Scanner._bagSnapshot) do
        local cur = current[itemID]
        local curCount = cur and cur.count or 0
        local diff = old.count - curCount
        if diff > 0 then
            -- Only track as a contribution if depositing to Tab 1
            if currentTab == 1 then
                local bankable, reason = GF.PVPItems:CheckLootedItem(itemID, old.link)
                if bankable then
                    deposited[itemID] = { count = diff, link = old.link, reason = reason }
                end
            end
        end
    end

    -- Items that APPEARED in bags = withdrawn from bank
    -- Skip Tab 1 (Public Deposits) — withdrawals there are officers sorting, not real withdrawals
    for itemID, cur in pairs(current) do
        local old = Scanner._bagSnapshot[itemID]
        local oldCount = old and old.count or 0
        local diff = cur.count - oldCount
        if diff > 0 and currentTab ~= 1 then
            withdrawn[itemID] = { count = diff, link = cur.link }
        end
    end

    -- Process deposits — log as PENDING, accumulate for summary on bank close
    for itemID, info in pairs(deposited) do
        local value, source = GF.TSM:GetBestPrice(itemID)
        local unitValue = value or 0
        local totalValue = unitValue * info.count

        -- Log to item trail FIRST so we get the trailID for the ledger entry
        local trailID = nil
        if GF.ItemTrail then
            trailID = GF.ItemTrail:OnDeposit(playerName, itemID, info.link, info.count, totalValue)
        end

        GF.Ledger:AddEntry(GF.ACTIONS.DEPOSIT, playerName, {
            { itemID = itemID, quantity = info.count, unitValue = unitValue, priceSource = source or "unknown" },
        }, totalValue, info.link, "pending", trailID)

        -- Accumulate for session summary (shown on bank close)
        if not sessionDeposits[itemID] then
            sessionDeposits[itemID] = { count = 0, value = 0, link = info.link }
        end
        sessionDeposits[itemID].count = sessionDeposits[itemID].count + info.count
        sessionDeposits[itemID].value = sessionDeposits[itemID].value + totalValue
    end

    -- Process withdrawals — fire bank transaction event and log to trail
    -- (Ledger and CrafterTracking will handle tab-based filtering)
    for itemID, info in pairs(withdrawn) do
        local value, source = GF.TSM:GetBestPrice(itemID)
        local unitValue = value or 0
        local totalValue = unitValue * info.count

        -- Log withdrawal to item trail so supplier chain is tracked
        if GF.ItemTrail then
            GF.ItemTrail:OnWithdraw(playerName, itemID, info.count, totalValue)
        end

        GF.Events:Fire("GF_BANK_TRANSACTION", {
            type = "withdraw",
            player = playerName,
            itemID = itemID,
            itemLink = info.link,
            quantity = info.count,
            tabIndex = nil, -- unknown from bag diff — Ledger lets nil through
            timestamp = GF.Utils:GetTime(),
        })

        if GF.debug then
            local name = C_Item.GetItemInfo(itemID) or "Item:" .. itemID
            GF.ChatNotify:Debug("Withdrew x" .. info.count .. " " .. name ..
                " — Value: " .. GF.Utils:FormatMoney(totalValue))
        end
    end

    -- Update snapshot
    Scanner._bagSnapshot = current
end

--- Show a single summary notification for all deposits this bank session
function Scanner:ShowDepositSummary()
    local totalItems = 0
    local totalValue = 0
    local lines = {}

    for itemID, info in pairs(sessionDeposits) do
        totalItems = totalItems + info.count
        totalValue = totalValue + info.value
        local name = info.link or (C_Item.GetItemInfo(itemID) or ("Item:" .. itemID))
        lines[#lines + 1] = "  x" .. info.count .. " " .. name .. " — " .. GF.Utils:FormatMoney(info.value)
    end

    if totalItems == 0 then return end

    -- Get total contribution (lifetime, not just this session)
    local playerName = GF.Utils:GetPlayerFullName()
    local guildData = GF.Settings:GetGuildData()
    local totalContributed = 0
    if guildData and guildData.payouts[playerName] then
        totalContributed = guildData.payouts[playerName].totalContributed or 0
    end

    -- Toast summary
    if GF.Toast then
        GF.Toast:DepositConfirm(totalItems, totalValue, totalContributed)
    end

    -- Chat summary
    GF.ChatNotify:Success("Deposited " .. totalItems .. " item(s) — Total value: " .. GF.Utils:FormatMoney(totalValue))
    for _, line in ipairs(lines) do
        GF.ChatNotify:Info(line)
    end
    GF.ChatNotify:Info("Total contribution: " .. GF.Utils:FormatMoney(totalContributed))

    wipe(sessionDeposits)
end
