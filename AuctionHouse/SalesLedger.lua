------------------------------------------------------------------------
-- Vault of Truths - AuctionHouse/SalesLedger.lua
-- Track AH sales, link back to source (crafted/deposited items)
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.SalesLedger = {}
local SL = GF.SalesLedger
GF:RegisterModule("SalesLedger", SL)

function SL:Init()
    -- Scan owned auctions when AH opens (detect completed sales)
    GF.Events:Register("AUCTION_HOUSE_SHOW", function()
        C_Timer.After(1, function()
            SL:ScanOwnedAuctions()
        end)
    end)

    -- Also scan when AH data updates
    GF.Events:Register("OWNED_AUCTIONS_UPDATED", function()
        SL:ScanOwnedAuctions()
    end)

    -- Detect sale gold arriving in mailbox
    GF.Events:Register("MAIL_SHOW", function()
        C_Timer.After(1, function()
            SL:ScanMailForSales()
        end)
    end)

    -- Also scan mail inbox updates
    GF.Events:Register("MAIL_INBOX_UPDATE", function()
        SL:ScanMailForSales()
    end)
end

--- Record a sale manually (for when auto-detection doesn't work)
---@param itemID number
---@param quantity number
---@param salePrice number Total sale price in copper
---@param ahCut number AH fee in copper (typically 5%)
---@param sourceOrderID string|nil Linked crafting order ID
---@param crafterName string|nil Who crafted the item
---@return table|nil sale record
function SL:RecordSale(itemID, quantity, salePrice, ahCut, sourceOrderID, crafterName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end

    if not guildData.ahSales then
        guildData.ahSales = {}
    end

    -- Only record sales for guild-tracked items
    local isGuildItem = false

    -- Check 1: has an item trail (was deposited/withdrawn through guild bank)
    if GF.ItemTrail then
        local trailID = GF.ItemTrail:FindActiveTrail(itemID)
            or GF.ItemTrail:FindCraftedTrail(itemID)
        if trailID then isGuildItem = true end
    end

    -- Check 2: has a linked crafting order
    if not isGuildItem and sourceOrderID then
        isGuildItem = true
    end

    -- Check 3: item appears in ledger (was deposited/withdrawn at some point)
    if not isGuildItem and itemID and itemID > 0 then
        for _, entry in ipairs(guildData.ledger.entries) do
            if entry.items then
                for _, item in ipairs(entry.items) do
                    if item.itemID == itemID then
                        isGuildItem = true
                        break
                    end
                end
            end
            if isGuildItem then break end
        end
    end

    if not isGuildItem then
        if GF.debug then
            local name = C_Item.GetItemInfo(itemID or 0) or "?"
            GF.ChatNotify:Debug("AH sale skipped (not guild item): " .. name)
        end
        return nil
    end

    -- Deduplicate: check if a sale with same item, quantity, price exists in last hour
    local now = time()
    for _, existing in ipairs(guildData.ahSales) do
        if existing.itemID == itemID and existing.quantity == quantity
           and existing.salePrice == salePrice
           and math.abs((existing.timestamp or 0) - now) < 3600 then
            return nil -- duplicate
        end
    end

    -- Calculate mat cost:
    -- 1. From a linked crafting order (most accurate)
    -- 2. From the item trail (what was deposited/withdrawn)
    -- 3. For direct sales of raw mats, mat cost = 0 (the full sale minus AH cut is profit)
    local matCost = 0
    if sourceOrderID then
        local order = GF.OrderBoard:GetOrder(sourceOrderID)
        if order then
            matCost = order.totalMatCost or 0
        end
    elseif GF.ItemTrail then
        -- Check if there's a trail showing what mats went into this item
        local guildData2 = GF.Settings:GetGuildData()
        if guildData2 and guildData2.itemTrails then
            for _, trail in pairs(guildData2.itemTrails) do
                if (trail.craftedItemID == itemID or trail.itemID == itemID) then
                    -- Sum up withdrawal values as mat cost
                    for _, evt in ipairs(trail.events or {}) do
                        if evt.action == GF.ACTIONS.CRAFT_WITHDRAW then
                            matCost = matCost + (evt.value or 0)
                        end
                    end
                    break
                end
            end
        end
    end
    -- For direct raw material sales (no crafting involved), matCost stays 0
    -- Profit = salePrice - ahCut (the depositor's share comes from the profit split)

    local sale = {
        id = GF.Utils:GenerateID(),
        itemID = itemID,
        quantity = quantity,
        salePrice = salePrice,
        ahCut = ahCut,
        matCost = matCost,
        profit = salePrice - ahCut - matCost,
        sourceOrderID = sourceOrderID,
        crafterName = crafterName,
        auctioneer = GF.Utils:GetPlayerFullName(),
        timestamp = GF.Utils:GetTime(),
        distributed = false, -- Has profit been distributed?
    }

    guildData.ahSales[#guildData.ahSales + 1] = sale

    -- Create ledger entry
    GF.Ledger:AddEntry(GF.ACTIONS.AH_SALE, sale.auctioneer, {
        { itemID = itemID, quantity = quantity, unitValue = salePrice / quantity, priceSource = "ah_sale" },
    }, salePrice, "AH Sale — Profit: " .. GF.Utils:FormatMoney(sale.profit))

    -- Resolve item name for notifications and display
    local itemName = "Unknown Item"
    local itemLink = nil
    if itemID and itemID > 0 then
        local name, link = C_Item.GetItemInfo(itemID)
        itemName = name or ("Item:" .. itemID)
        itemLink = link
    end
    sale.itemName = itemName
    sale.itemLink = itemLink
    sale._itemName = itemLink or itemName

    -- Log to item trail
    if GF.ItemTrail then
        GF.ItemTrail:OnAHSale(sale.auctioneer, itemID, quantity, salePrice)
    end

    GF.Events:Fire("GF_AH_SALE_RECORDED", sale)

    -- Local notification for the auctioneer
    GF.ChatNotify:Gold("AH Sale: " .. itemName .. " — " .. GF.Utils:FormatMoney(salePrice) ..
        " | Profit: " .. GF.Utils:FormatMoney(sale.profit))
    if GF.Toast and GF.Toast.Show then
        GF.Toast:Show("Item Sold!", GF.Utils:FormatMoney(salePrice), "Interface\\Icons\\INV_Misc_Coin_02")
    end

    -- Broadcast to guild addon channel so addon users get rich notifications
    if GF.Sender then
        GF.Sender:Send(GF.Protocol.MSG.PAYOUT_REC, {
            type = "ah_sale",
            itemID = itemID,
            itemName = itemName,
            salePrice = salePrice,
            profit = sale.profit,
            crafterName = crafterName,
            auctioneer = sale.auctioneer,
            timestamp = sale.timestamp,
        })
    end

    -- Post to guild chat — find all involved players from the trail
    if IsInGuild() then
        local depositorNames = {}
        local crafterShort = crafterName and (crafterName:match("^(.+)-") or crafterName) or nil
        local wasCrafted = crafterName ~= nil

        -- Search the item trail for this item
        if GF.ItemTrail then
            -- Find the trail that was used for this sale (prefer active/sold over crafted)
            local guildData2 = GF.Settings:GetGuildData()
            local trail = nil
            if guildData2 and guildData2.itemTrails then
                -- First pass: find a trail with status "sold" for this item (just marked by OnAHSale)
                for _, t in pairs(guildData2.itemTrails) do
                    if t.status == "sold" and (t.itemID == itemID or t.craftedItemID == itemID) then
                        trail = t
                        break
                    end
                end
                -- Second pass: any trail matching this item
                if not trail then
                    for _, t in pairs(guildData2.itemTrails) do
                        if t.itemID == itemID or t.craftedItemID == itemID then
                            trail = t
                            break
                        end
                    end
                end
            end

            if trail then
                for _, evt in ipairs(trail.events or {}) do
                    if evt.action == GF.ACTIONS.DEPOSIT then
                        local name = evt.player:match("^(.+)-") or evt.player
                        depositorNames[name] = true
                    end
                end
                -- Only attribute as crafted if the trail has an actual CRAFT_DEPOSIT event
                local hasCraftDeposit = false
                for _, evt in ipairs(trail.events or {}) do
                    if evt.action == GF.ACTIONS.CRAFT_DEPOSIT then
                        hasCraftDeposit = true
                        break
                    end
                end
                if hasCraftDeposit and trail.craftedBy then
                    wasCrafted = true
                    if not crafterShort then
                        crafterShort = trail.craftedBy:match("^(.+)-") or trail.craftedBy
                    end
                end
            end
        end

        -- Also scan ledger for depositors of this item
        if next(depositorNames) == nil then
            for _, entry in ipairs(guildData.ledger.entries) do
                if entry.action == GF.ACTIONS.DEPOSIT and entry.items then
                    for _, item in ipairs(entry.items) do
                        if item.itemID == itemID then
                            local name = entry.player:match("^(.+)-") or entry.player
                            depositorNames[name] = true
                        end
                    end
                end
            end
        end

        -- Build the message
        local profitStr = GF.Utils:FormatGold(sale.profit)
        local saleStr = GF.Utils:FormatGold(salePrice)
        local displayItem = itemName:match("%[(.-)%]") or itemName
        local msg = "[VoT] " .. displayItem .. " sold " .. saleStr .. "!"

        -- Add profit split recipients
        local recipients = {}
        for name in pairs(depositorNames) do
            recipients[#recipients + 1] = name
        end
        -- Only show (craft) tag if it was actually crafted, not a direct resale
        if wasCrafted and crafterShort then
            recipients[#recipients + 1] = crafterShort .. "(craft)"
        end

        if #recipients > 0 then
            msg = msg .. " Profit " .. profitStr .. " -> " .. table.concat(recipients, ", ")
        else
            msg = msg .. " Profit: " .. profitStr
        end

        -- Truncate to 255 chars (WoW chat limit)
        if #msg > 255 then msg = msg:sub(1, 252) .. "..." end

        if GF.Settings:Get("guildChatAnnounce") ~= false then
            SendChatMessage(msg, "GUILD")
        end
    end

    return sale
end

--- Distribute profit for a sale
---@param saleID string
---@return table|nil distribution
function SL:DistributeProfit(saleID)
    if GF.debug then
        GF.ChatNotify:Debug("DistributeProfit — saleID: " .. tostring(saleID))
    end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end

    local sale
    for i, s in ipairs(guildData.ahSales) do
        if s.id == saleID then
            sale = s
            break
        end
    end

    if not sale then
        GF.ChatNotify:Warning("Sale not found (id: " .. tostring(saleID) .. ")")
        return nil
    end
    if sale.distributed then
        GF.ChatNotify:Warning("Profit for this sale already distributed.")
        return nil
    end

    -- Credit deposit contributions BEFORE calculating profit distribution
    -- so depositors' totalContributed is up-to-date for the proportional split
    local saleItemID = sale.itemID
    local credited = false

    for _, entry in ipairs(guildData.ledger.entries) do
        if entry.status == "pending" and entry.action == GF.ACTIONS.DEPOSIT then
            local shouldCredit = false

            if saleItemID and saleItemID > 0 and entry.items then
                for _, item in ipairs(entry.items) do
                    if item.itemID == saleItemID then
                        shouldCredit = true
                        break
                    end
                end
            elseif (not saleItemID or saleItemID == 0) and not credited then
                local entryValue = entry.totalValue or 0
                local saleValue = sale.salePrice or 0
                if entryValue > 0 and saleValue > 0 then
                    local ratio = entryValue / saleValue
                    if ratio > 0.5 and ratio < 2.0 then
                        shouldCredit = true
                    end
                end
            end

            if shouldCredit then
                entry.status = "credited"
                GF.Ledger:UpdateContribution(entry.player, entry.totalValue)
                credited = true
            end
        end
    end

    -- Fallback: credit all pending deposits up to sale value
    if not credited then
        local remaining = sale.salePrice or 0
        for _, entry in ipairs(guildData.ledger.entries) do
            if entry.status == "pending" and entry.action == GF.ACTIONS.DEPOSIT and remaining > 0 then
                entry.status = "credited"
                GF.Ledger:UpdateContribution(entry.player, entry.totalValue)
                remaining = remaining - (entry.totalValue or 0)
            end
        end
    end

    -- NOW calculate profit distribution — depositors' totalContributed is up-to-date
    local distribution = GF.Ledger:CalculateProfitDistribution(
        sale.salePrice, sale.matCost, sale.ahCut,
        sale.crafterName, sale.auctioneer
    )

    GF.Ledger:RecordProfitDistribution(distribution)
    sale.distributed = true

    GF.Events:Fire("GF_PROFIT_DISTRIBUTED", sale, distribution)
    return distribution
end

--- Distribute all undistributed sale profits
---@return number count Number of sales distributed
---@return number totalProfit Total profit distributed
function SL:DistributeAllPending()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return 0, 0 end

    local count = 0
    local totalProfit = 0

    for i, sale in ipairs(guildData.ahSales) do
        if not sale.distributed then
            print("|cFF33AAFF[VoT]|r DistributeAll — sale #" .. i ..
                " id=" .. tostring(sale.id) ..
                " profit=" .. tostring(sale.profit) ..
                " item=" .. tostring(sale.itemName or sale.itemID))
            if (sale.profit or 0) > 0 then
                self:DistributeProfit(sale.id)
                count = count + 1
                totalProfit = totalProfit + sale.profit
            else
                -- Force-mark zero/negative profit sales as distributed
                sale.distributed = true
                count = count + 1
            end
        end
    end

    -- Also credit any orphaned pending deposits that should have been credited
    -- (handles cases where sales were distributed before the credit-on-distribute fix)
    self:CreditOrphanedDeposits()

    if count > 0 then
        GF.ChatNotify:Gold("Distributed " .. count .. " sale(s): " .. GF.Utils:FormatMoney(totalProfit) .. " profit")
    elseif count == 0 then
        -- Even if no new sales, run orphan cleanup
        GF.ChatNotify:Info("No new sales to distribute.")
    end

    return count, totalProfit
end

--- Credit orphaned pending deposits that have matching distributed sales
function SL:CreditOrphanedDeposits()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    -- Collect all item IDs from distributed sales
    local soldItemIDs = {}
    for _, sale in ipairs(guildData.ahSales or {}) do
        if sale.distributed and sale.itemID and sale.itemID > 0 then
            soldItemIDs[sale.itemID] = true
        end
    end

    -- Check if any pending deposits match sold items
    local credited = 0
    for _, entry in ipairs(guildData.ledger.entries) do
        if entry.status == "pending" and entry.action == GF.ACTIONS.DEPOSIT and entry.items then
            for _, item in ipairs(entry.items) do
                if soldItemIDs[item.itemID] then
                    entry.status = "credited"
                    GF.Ledger:UpdateContribution(entry.player, entry.totalValue)
                    credited = credited + 1
                    break
                end
            end
        end
    end

    -- If there are STILL pending deposits and ALL sales are distributed,
    -- credit them anyway (the items were sold, we just couldn't match IDs)
    local hasUndistributed = false
    for _, sale in ipairs(guildData.ahSales or {}) do
        if not sale.distributed then hasUndistributed = true; break end
    end

    if not hasUndistributed then
        for _, entry in ipairs(guildData.ledger.entries) do
            if entry.status == "pending" and entry.action == GF.ACTIONS.DEPOSIT then
                entry.status = "credited"
                GF.Ledger:UpdateContribution(entry.player, entry.totalValue)
                credited = credited + 1
            end
        end
    end

    if credited > 0 then
        GF.ChatNotify:Info("Credited " .. credited .. " pending deposit(s).")
    end
end

--- Scan for completed auctions (called when AH closes)
-- Track already-processed sales to avoid duplicates
local processedSaleKeys = {}

--- Generate a dedup key for a sale
local function SaleKey(itemID, quantity, price, timestamp)
    return tostring(itemID) .. ":" .. tostring(quantity) .. ":" .. tostring(price) .. ":" .. tostring(math.floor((timestamp or 0) / 60))
end

--- Scan owned auctions via C_AuctionHouse for completed sales
function SL:ScanOwnedAuctions()
    if not C_AuctionHouse or not C_AuctionHouse.GetOwnedAuctions then return end

    local ownedAuctions = C_AuctionHouse.GetOwnedAuctions()
    if not ownedAuctions then return end

    local newSales = 0
    for _, auction in ipairs(ownedAuctions) do
        -- status: 0 = active, 1 = sold
        if auction.status == 1 then
            local itemID = auction.itemKey and auction.itemKey.itemID
            local quantity = auction.quantity or 1
            local buyoutAmount = auction.buyoutAmount or 0

            if itemID and buyoutAmount > 0 then
                local key = SaleKey(itemID, quantity, buyoutAmount, time())
                if not processedSaleKeys[key] then
                    processedSaleKeys[key] = true
                    local ahCut = math.floor(buyoutAmount * 0.05) -- 5% AH cut
                    self:RecordSale(itemID, quantity, buyoutAmount, ahCut)
                    newSales = newSales + 1
                end
            end
        end
    end

    if newSales > 0 then
        GF.ChatNotify:Gold(newSales .. " AH sale(s) detected!")
    end
end

--- Scan mailbox for auction sale mail
function SL:ScanMailForSales()
    local numMail = GetInboxNumItems()
    if not numMail or numMail == 0 then return end

    local newSales = 0
    for i = 1, numMail do
        local _, _, sender, subject, money, _, daysLeft, itemCount, wasRead, _, _, _, isGM = GetInboxHeaderInfo(i)

        -- Auction sale mail has money attached and subject starts with "Auction successful" or similar
        -- WoW locale-dependent, but money > 0 from "Auction House" sender is reliable
        if money and money > 0 and subject then
            local isAuctionMail = subject:find("Auction") or subject:find("auction") or
                                  (sender and sender:find("Auction"))

            if isAuctionMail then
                -- Extract item info from subject if possible
                local itemName = subject:match("%[(.-)%]") or subject:match("Auction%s+%w+:%s*(.+)") or "Unknown Item"

                -- Use mail index + money + daysLeft for a stable dedup key
                -- (avoids collisions from itemID=0 for all mail sales)
                local key = "mail:" .. i .. ":" .. tostring(money) .. ":" .. tostring(daysLeft)
                if not processedSaleKeys[key] then
                    processedSaleKeys[key] = true

                    -- Try to find itemID from the item name
                    local itemID = 0
                    local resolvedName, itemLink = C_Item.GetItemInfo(itemName)
                    if itemLink then
                        itemID = tonumber(itemLink:match("item:(%d+)")) or 0
                    end

                    -- If item cache missed, try matching name against known guild items
                    if itemID == 0 and itemName ~= "Unknown Item" then
                        local guildData = GF.Settings:GetGuildData()
                        if guildData then
                            local lowerName = itemName:lower()
                            -- Search ledger entries for a matching item name
                            for _, entry in ipairs(guildData.ledger.entries) do
                                if entry.items then
                                    for _, item in ipairs(entry.items) do
                                        if item.itemID and item.itemID > 0 then
                                            local knownName = C_Item.GetItemInfo(item.itemID)
                                            if knownName and knownName:lower() == lowerName then
                                                itemID = item.itemID
                                                break
                                            end
                                        end
                                    end
                                end
                                if itemID > 0 then break end
                            end
                            -- Also search item trails
                            if itemID == 0 and guildData.itemTrails then
                                for _, trail in pairs(guildData.itemTrails) do
                                    local trailItemID = trail.craftedItemID or trail.itemID
                                    if trailItemID and trailItemID > 0 then
                                        local knownName = C_Item.GetItemInfo(trailItemID)
                                        if knownName and knownName:lower() == lowerName then
                                            itemID = trailItemID
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- money in mail is already after AH cut, so salePrice = money / 0.95
                    local salePrice = math.floor(money / 0.95)
                    local ahCut = salePrice - money

                    local sale = self:RecordSale(itemID, 1, salePrice, ahCut)
                    if sale then
                        newSales = newSales + 1
                    end
                end
            end
        end
    end

    if newSales > 0 then
        GF.ChatNotify:Gold(newSales .. " AH sale(s) detected from mail!")
    end
end


--- Get count of pending (not yet distributed) sales
---@return number
function SL:GetPendingSalesCount()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.ahSales then return 0 end

    local count = 0
    for _, sale in ipairs(guildData.ahSales) do
        if not sale.distributed then count = count + 1 end
    end
    return count
end

--- Get recent sales
---@param limit number|nil Default 20
---@return table Array of sale records
function SL:GetRecentSales(limit)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.ahSales then return {} end

    limit = limit or 20
    local results = {}
    -- Iterate in reverse (newest first, assuming they're appended)
    for i = #guildData.ahSales, math.max(1, #guildData.ahSales - limit + 1), -1 do
        results[#results + 1] = guildData.ahSales[i]
    end
    return results
end

--- Get total sales summary
---@return table { totalSales, totalProfit, totalDistributed, totalPending }
function SL:GetSummary()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.ahSales then
        return { totalSales = 0, totalProfit = 0, totalDistributed = 0, totalPending = 0 }
    end

    local totalSales = 0
    local totalProfit = 0
    local distributed = 0
    local pending = 0

    for _, sale in ipairs(guildData.ahSales) do
        totalSales = totalSales + sale.salePrice
        totalProfit = totalProfit + sale.profit
        if sale.distributed then
            distributed = distributed + sale.profit
        else
            pending = pending + sale.profit
        end
    end

    return {
        totalSales = totalSales,
        totalProfit = totalProfit,
        totalDistributed = distributed,
        totalPending = pending,
    }
end
