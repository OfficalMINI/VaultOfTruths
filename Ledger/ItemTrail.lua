------------------------------------------------------------------------
-- Vault of Truths - Ledger/ItemTrail.lua
-- Tracks the full lifecycle of items through the guild economy:
-- Deposit -> Crafter Withdraw -> Craft -> Deposit Back -> AH Withdraw -> AH List -> Sold
-- Each item gets a trail ID linking all steps together.
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.ItemTrail = {}
local IT = GF.ItemTrail
GF:RegisterModule("ItemTrail", IT)

IT._ahOpen = false
IT._ahBagSnapshot = {}

function IT:Init()
    -- Track AH listings via bag diff
    if C_AuctionHouse then
        -- Snapshot bags when AH opens
        GF.Events:Register("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(event, interactionType)
            if interactionType == 21 then -- auction house
                IT._ahOpen = true
                IT:SnapshotBagsForAH()
            end
        end)
        GF.Events:Register("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(event, interactionType)
            if interactionType == 21 then
                IT._ahOpen = false
            end
        end)

        -- When an auction is created, wait for bags to update then detect
        GF.Events:Register("AUCTION_HOUSE_AUCTION_CREATED", function(event, auctionID)
            C_Timer.After(0.5, function()
                IT:DetectAHListing()
            end)
        end)

        -- Hook posting APIs to catch commodity listings
        if C_AuctionHouse.PostCommodity then
            hooksecurefunc(C_AuctionHouse, "PostCommodity", function()
                C_Timer.After(1, function()
                    IT:DetectAHListing()
                end)
            end)
        end
        if C_AuctionHouse.PostItem then
            hooksecurefunc(C_AuctionHouse, "PostItem", function()
                C_Timer.After(1, function()
                    IT:DetectAHListing()
                end)
            end)
        end
    end
end

function IT:SnapshotBagsForAH()
    self._ahBagSnapshot = {}
    for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                self._ahBagSnapshot[info.itemID] = (self._ahBagSnapshot[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
end

--- Ensure the trail log exists
local function EnsureTrailLog()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end
    if not guildData.itemTrails then
        guildData.itemTrails = {}
    end
    return guildData.itemTrails
end

--- Create a new trail entry for an item event
---@param action string One of GF.ACTIONS
---@param player string Who performed the action
---@param itemID number
---@param itemLink string|nil
---@param quantity number
---@param value number Value in copper (price-locked at event time)
---@param trailID string|nil Existing trail ID to link to, or nil for new trail
---@param note string|nil
---@return string trailID
function IT:LogEvent(action, player, itemID, itemLink, quantity, value, trailID, note)
    local trails = EnsureTrailLog()
    if not trails then return "" end

    trailID = trailID or GF.Utils:GenerateID()

    if not trails[trailID] then
        trails[trailID] = {
            id = trailID,
            itemID = itemID,
            startedBy = player,
            startedAt = GF.Utils:GetTime(),
            events = {},
            status = "active", -- active, crafted, listed, sold, lost
            remainingQty = quantity or 1,
        }
    end

    local trail = trails[trailID]
    trail.events[#trail.events + 1] = {
        action = action,
        player = player,
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity,
        value = value,
        timestamp = GF.Utils:GetTime(),
        note = note,
    }

    -- Update trail status based on action
    if action == GF.ACTIONS.CRAFT_DEPOSIT then
        trail.status = "crafted"
        trail.craftedItemID = itemID
        trail.craftedBy = player
    elseif action == GF.ACTIONS.AH_LIST then
        trail.status = "listed"
        trail.listedBy = player
    elseif action == GF.ACTIONS.AH_SALE then
        trail.status = "sold"
        trail.soldAt = GF.Utils:GetTime()
        trail.salePrice = value
    end

    -- Trim old trails (keep last 500)
    local count = 0
    for _ in pairs(trails) do count = count + 1 end
    if count > 500 then
        local oldest
        local oldestTime = math.huge
        for id, t in pairs(trails) do
            if t.startedAt < oldestTime then
                oldest = id
                oldestTime = t.startedAt
            end
        end
        if oldest then trails[oldest] = nil end
    end

    return trailID
end

--- Find the OLDEST active trail for an item (FIFO — first deposited, first consumed)
---@param itemID number
---@param quantity number|nil Quantity to consume (reduces remainingQty)
---@return string|nil trailID
function IT:FindActiveTrail(itemID, quantity)
    local trails = EnsureTrailLog()
    if not trails then return nil end

    -- Collect all active trails for this item, sorted oldest first
    local candidates = {}
    for id, trail in pairs(trails) do
        if trail.itemID == itemID and trail.status == "active" and (trail.remainingQty or 0) > 0 then
            candidates[#candidates + 1] = { id = id, startedAt = trail.startedAt }
        end
    end

    if #candidates == 0 then return nil end

    -- Sort oldest first (FIFO)
    table.sort(candidates, function(a, b) return a.startedAt < b.startedAt end)

    local trailID = candidates[1].id
    local trail = trails[trailID]

    -- Consume quantity from this trail
    if quantity and trail.remainingQty then
        trail.remainingQty = trail.remainingQty - quantity
        if trail.remainingQty <= 0 then
            trail.remainingQty = 0
        end
    end

    return trailID
end

--- Find a trail for a crafted item (deposited back, ready for AH)
--- Returns the OLDEST crafted trail (FIFO)
---@param itemID number
---@return string|nil trailID
function IT:FindCraftedTrail(itemID)
    local trails = EnsureTrailLog()
    if not trails then return nil end

    local best, bestTime = nil, math.huge
    for id, trail in pairs(trails) do
        if trail.craftedItemID == itemID and trail.status == "crafted" then
            if trail.startedAt < bestTime then
                best = id
                bestTime = trail.startedAt
            end
        end
    end
    return best
end

--- Get the full trail for an item
---@param trailID string
---@return table|nil trail { id, itemID, events[], status, ... }
function IT:GetTrail(trailID)
    local trails = EnsureTrailLog()
    if not trails then return nil end
    return trails[trailID]
end

--- Get all trails for a player (as depositor, crafter, or auctioneer)
---@param player string
---@param limit number|nil
---@return table Array of trails
function IT:GetPlayerTrails(player, limit)
    local trails = EnsureTrailLog()
    if not trails then return {} end

    limit = limit or 50
    local results = {}

    for _, trail in pairs(trails) do
        local involved = false
        for _, evt in ipairs(trail.events) do
            if evt.player == player then
                involved = true
                break
            end
        end
        if involved then
            results[#results + 1] = trail
            if #results >= limit then break end
        end
    end

    -- Sort newest first
    table.sort(results, function(a, b) return a.startedAt > b.startedAt end)
    return results
end

--- Get all active/pending trails (items in the pipeline)
---@return table Array of trails
function IT:GetPipelineItems()
    local trails = EnsureTrailLog()
    if not trails then return {} end

    local results = {}
    for _, trail in pairs(trails) do
        if trail.status ~= "sold" and trail.status ~= "lost" then
            results[#results + 1] = trail
        end
    end

    table.sort(results, function(a, b) return a.startedAt > b.startedAt end)
    return results
end

--- Get a human-readable status for a trail
---@param trail table
---@return string status text
---@return string color code
function IT:GetTrailStatusText(trail)
    if trail.status == "active" then
        return "In guild bank", "|cFFFFAA00"
    elseif trail.status == "crafted" then
        local crafter = trail.craftedBy and (trail.craftedBy:match("^(.+)-") or trail.craftedBy) or "?"
        local supplierNames = {}
        if trail.suppliers then
            for playerName in pairs(trail.suppliers) do
                supplierNames[#supplierNames + 1] = playerName:match("^(.+)-") or playerName
            end
        end
        if #supplierNames > 0 then
            return "Crafted by " .. crafter .. " (mats: " .. table.concat(supplierNames, ", ") .. ")", "|cFF00AAFF"
        end
        return "Crafted by " .. crafter, "|cFF00AAFF"
    elseif trail.status == "listed" then
        local lister = trail.listedBy and (trail.listedBy:match("^(.+)-") or trail.listedBy) or nil
        if lister then
            return "Listed on AH by " .. lister, "|cFFFFD700"
        end
        return "Listed on AH", "|cFFFFD700"
    elseif trail.status == "sold" then
        return "Sold for " .. GF.Utils:FormatMoney(trail.salePrice or 0), "|cFF00FF00"
    elseif trail.status == "lost" then
        return "Lost/Unknown", "|cFFFF0000"
    end
    return "Unknown", "|cFF888888"
end

--- Called when an auction is created — link to a trail
function IT:DetectAHListing()
    if not self._ahOpen then return end

    local player = GF.Utils:GetPlayerFullName()

    -- Compare bags to snapshot to find what was listed
    local currentBags = {}
    for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                currentBags[info.itemID] = (currentBags[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end

    -- Find items that decreased (were listed) — only track guild items
    for itemID, oldCount in pairs(self._ahBagSnapshot) do
        local newCount = currentBags[itemID] or 0
        local diff = oldCount - newCount
        if diff > 0 then
            -- Only track if this item has a guild trail (came from guild bank)
            local trailID = self:FindCraftedTrail(itemID) or self:FindActiveTrail(itemID)
            if trailID then
                local value = GF.TSM and GF.TSM:GetBestPrice(itemID) or 0
                self:OnAHList(player, itemID, diff, value * diff)

                GF.Ledger:AddEntry(GF.ACTIONS.AH_LIST, player, {
                    { itemID = itemID, quantity = diff, unitValue = value, priceSource = "tsm" },
                }, value * diff, "Listed on AH")

                local name = C_Item.GetItemInfo(itemID) or ("Item:" .. itemID)
                GF.ChatNotify:Info("AH listing tracked: x" .. diff .. " " .. name)
            end
        end
    end

    -- Update snapshot for next listing
    self._ahBagSnapshot = currentBags
end

--- Hook: call this from Scanner when a deposit is detected
---@param player string
---@param itemID number
---@param itemLink string|nil
---@param quantity number
---@param value number
---@return string trailID
function IT:OnDeposit(player, itemID, itemLink, quantity, value)
    return self:LogEvent(GF.ACTIONS.DEPOSIT, player, itemID, itemLink, quantity, value, nil,
        "Deposited to guild bank")
end

--- Hook: log any guild bank withdrawal to the trail (all tabs)
--- Does NOT consume the trail (item may be returned)
---@param player string
---@param itemID number
---@param quantity number
---@param value number
function IT:OnWithdraw(player, itemID, quantity, value)
    local trailID = self:FindActiveTrail(itemID)
    if trailID then
        self:LogEvent(GF.ACTIONS.WITHDRAW, player, itemID, nil, quantity, value, trailID,
            "Withdrawn from guild bank")
    end
end

--- Hook: call this from CrafterTracking when mats are withdrawn
--- Consumes from oldest active trail (FIFO)
---@param player string
---@param itemID number
---@param quantity number
---@param value number
function IT:OnCraftWithdraw(player, itemID, quantity, value)
    local remaining = quantity
    while remaining > 0 do
        local trailID = self:FindActiveTrail(itemID, remaining)
        if not trailID then break end
        self:LogEvent(GF.ACTIONS.CRAFT_WITHDRAW, player, itemID, nil, remaining, value, trailID,
            "Withdrawn for crafting")
        remaining = 0 -- FindActiveTrail already consumed the qty
    end
end

--- Hook: call this from CrafterTracking when a crafted item is deposited back
---@param player string
---@param itemID number
---@param itemLink string|nil
---@param quantity number
---@param value number
function IT:OnCraftDeposit(player, itemID, itemLink, quantity, value)
    local trails = EnsureTrailLog()
    if not trails then return end

    -- Find this crafter's last craft deposit timestamp — everything withdrawn
    -- between that and now are the inputs for THIS craft
    local lastCraftTime = 0
    for _, trail in pairs(trails) do
        for _, evt in ipairs(trail.events) do
            if evt.action == GF.ACTIONS.CRAFT_DEPOSIT and evt.player == player then
                if evt.timestamp > lastCraftTime then
                    lastCraftTime = evt.timestamp
                end
            end
        end
    end

    -- Find ALL trails where this player withdrew mats SINCE the last craft deposit
    -- This captures all inputs (heraldries, cloth, ore, etc.) used for this craft
    local matTrails = {}
    for id, trail in pairs(trails) do
        for _, evt in ipairs(trail.events) do
            if (evt.action == GF.ACTIONS.CRAFT_WITHDRAW or evt.action == GF.ACTIONS.WITHDRAW)
                and evt.player == player
                and evt.timestamp > lastCraftTime then
                matTrails[#matTrails + 1] = { id = id, trail = trail, timestamp = evt.timestamp }
                break
            end
        end
    end

    -- Sort FIFO — oldest withdrawal first
    table.sort(matTrails, function(a, b) return a.timestamp < b.timestamp end)

    -- Collect all suppliers (depositors) from the consumed material trails
    local suppliers = {}
    for _, mt in ipairs(matTrails) do
        for _, evt in ipairs(mt.trail.events) do
            if evt.action == GF.ACTIONS.DEPOSIT and evt.player then
                if not suppliers[evt.player] then
                    suppliers[evt.player] = { depositTime = evt.timestamp }
                end
            end
        end
    end

    -- Use the oldest mat trail as the primary link
    local bestTrail = matTrails[1] and matTrails[1].id or nil

    if bestTrail then
        self:LogEvent(GF.ACTIONS.CRAFT_DEPOSIT, player, itemID, itemLink, quantity, value, bestTrail,
            "Crafted item deposited")
        -- Store all suppliers on the trail so tooltip can show them
        trails[bestTrail].suppliers = suppliers
    else
        -- New trail for the crafted item
        self:LogEvent(GF.ACTIONS.CRAFT_DEPOSIT, player, itemID, itemLink, quantity, value, nil,
            "Crafted item deposited (no mat trail found)")
    end
end

--- Hook: call this from SalesLedger when an item is listed on AH
---@param player string
---@param itemID number
---@param quantity number
---@param listPrice number
function IT:OnAHList(player, itemID, quantity, listPrice)
    local trailID = self:FindCraftedTrail(itemID) or self:FindActiveTrail(itemID)
    if trailID then
        self:LogEvent(GF.ACTIONS.AH_LIST, player, itemID, nil, quantity, listPrice, trailID,
            "Listed on AH for " .. GF.Utils:FormatMoney(listPrice))
    end
end

--- Hook: call this from SalesLedger when an item sells
--- Matches to oldest listed/crafted/active trail (FIFO)
---@param player string
---@param itemID number
---@param quantity number
---@param salePrice number
function IT:OnAHSale(player, itemID, quantity, salePrice)
    local trails = EnsureTrailLog()
    if not trails then return end

    -- Try listed trails first (already on AH), then crafted, then active
    local statusOrder = { "listed", "crafted", "active" }
    for _, status in ipairs(statusOrder) do
        local best, bestTime = nil, math.huge
        for id, trail in pairs(trails) do
            if trail.status == status and (trail.craftedItemID == itemID or trail.itemID == itemID) then
                if trail.startedAt < bestTime then
                    best = id
                    bestTime = trail.startedAt
                end
            end
        end
        if best then
            self:LogEvent(GF.ACTIONS.AH_SALE, player, itemID, nil, quantity, salePrice, best,
                "Sold on AH")
            return
        end
    end

    -- No trail found — standalone sale
    self:LogEvent(GF.ACTIONS.AH_SALE, player, itemID, nil, quantity, salePrice, nil,
        "AH sale (no deposit trail)")
end

------------------------------------------------------------------------
-- Admin: Repair broken trails (officer-only)
-- Rebuilds supplier links and fixes FIFO ordering on all trails
------------------------------------------------------------------------
function IT:RepairTrails()
    if not GF.Roles:IsAddonOfficer() then
        GF.ChatNotify:Error("Only officers can repair trails.")
        return
    end

    local trails = EnsureTrailLog()
    if not trails then return end

    local fixed = 0

    for id, trail in pairs(trails) do
        -- Fix 1: Rebuild suppliers on crafted trails
        if trail.craftedBy and (trail.status == "crafted" or trail.status == "listed" or trail.status == "sold") then
            local crafter = trail.craftedBy
            local suppliers = {}

            -- Find when this craft deposit happened
            local craftDepositTime = 0
            for _, evt in ipairs(trail.events or {}) do
                if evt.action == GF.ACTIONS.CRAFT_DEPOSIT and evt.player == crafter then
                    craftDepositTime = evt.timestamp or 0
                end
            end

            -- Find this crafter's PREVIOUS craft deposit (to set the time window start)
            local prevCraftTime = 0
            for _, otherTrail in pairs(trails) do
                for _, evt in ipairs(otherTrail.events or {}) do
                    if evt.action == GF.ACTIONS.CRAFT_DEPOSIT and evt.player == crafter then
                        if evt.timestamp > prevCraftTime and evt.timestamp < craftDepositTime then
                            prevCraftTime = evt.timestamp
                        end
                    end
                end
            end

            -- Find all material trails where this crafter withdrew mats
            -- in the window between their previous craft deposit and this one
            for otherId, otherTrail in pairs(trails) do
                if otherId ~= id then
                    for _, evt in ipairs(otherTrail.events or {}) do
                        if (evt.action == GF.ACTIONS.CRAFT_WITHDRAW or evt.action == GF.ACTIONS.WITHDRAW)
                            and evt.player == crafter
                            and (evt.timestamp or 0) > prevCraftTime
                            and (evt.timestamp or 0) <= craftDepositTime then
                            for _, depEvt in ipairs(otherTrail.events) do
                                if depEvt.action == GF.ACTIONS.DEPOSIT and depEvt.player then
                                    if not suppliers[depEvt.player] then
                                        suppliers[depEvt.player] = { depositTime = depEvt.timestamp }
                                    end
                                end
                            end
                            break
                        end
                    end
                end
            end

            if next(suppliers) then
                trail.suppliers = suppliers
                fixed = fixed + 1
            end
        end

        -- Fix 2: Ensure remainingQty is not negative
        if trail.remainingQty and trail.remainingQty < 0 then
            trail.remainingQty = 0
            fixed = fixed + 1
        end
    end

    -- Fix 3: Re-sort and reassign FIFO order on pending deposit credits
    -- Credit oldest deposits first for any items that have been sold
    local guildData = GF.Settings:GetGuildData()
    if guildData then
        local pendingDeposits = {}
        for _, entry in ipairs(guildData.ledger.entries) do
            if entry.status == "pending" and entry.action == GF.ACTIONS.DEPOSIT then
                pendingDeposits[#pendingDeposits + 1] = entry
            end
        end

        -- Sort oldest first (FIFO)
        table.sort(pendingDeposits, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)

        -- Check if any sold items match pending deposits and credit in FIFO order
        local soldItemIDs = {}
        for _, sale in ipairs(guildData.ahSales or {}) do
            if sale.distributed and sale.itemID and sale.itemID > 0 then
                soldItemIDs[sale.itemID] = true
            end
        end

        for _, entry in ipairs(pendingDeposits) do
            if entry.items then
                for _, item in ipairs(entry.items) do
                    if soldItemIDs[item.itemID] then
                        entry.status = "credited"
                        GF.Ledger:UpdateContribution(entry.player, entry.totalValue)
                        fixed = fixed + 1
                        break
                    end
                end
            end
        end
    end

    GF.ChatNotify:Success("Trail repair complete: " .. fixed .. " fix(es) applied.")
    return fixed
end
