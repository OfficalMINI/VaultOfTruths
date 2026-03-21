------------------------------------------------------------------------
-- Vault of Truths - Ledger/Ledger.lua
-- Core contribution ledger: add entries, query, compute balances
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Ledger = {}
local Ledger = GF.Ledger
GF:RegisterModule("Ledger", Ledger)

function Ledger:Init()
    -- Auto-create ledger entries from guild bank transactions
    GF.Events:On("GF_BANK_TRANSACTION", function(transaction)
        Ledger:ProcessBankTransaction(transaction)
    end)
end

--- Add a ledger entry
---@param action string One of GF.ACTIONS
---@param player string "Player-Realm"
---@param items table Array of { itemID, quantity, unitValue, priceSource }
---@param totalValue number Total value in copper
---@param note string|nil Optional note
---@param status string|nil "pending", "crafted", "sold", "credited" (default "credited" for non-deposits)
---@param trailID string|nil Optional trail ID linking this entry to an item trail
---@return table|nil entry The created entry
function Ledger:AddEntry(action, player, items, totalValue, note, status, trailID)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end

    if guildData.guildSettings.systemLocked then
        if GF.debug then
            print("|cFF33AAFF[Vault of Truths]|r System is locked. Cannot add ledger entry.")
        end
        return nil
    end

    -- Deposits start as "pending" until the item is crafted + sold
    -- Other actions (payout, fee, etc.) are immediately "credited"
    if not status then
        status = (action == GF.ACTIONS.DEPOSIT) and "pending" or "credited"
    end

    -- Fill in missing prices from TSM if available
    if items and GF.TSM and GF.TSM:IsAvailable() then
        local recalc = false
        for _, item in ipairs(items) do
            if item.itemID and (not item.unitValue or item.unitValue == 0) then
                local price = GF.TSM:GetBestPrice(item.itemID)
                if price and price > 0 then
                    item.unitValue = price
                    item.priceSource = item.priceSource or "tsm"
                    recalc = true
                end
            end
        end
        if recalc and (not totalValue or totalValue == 0) then
            totalValue = 0
            for _, item in ipairs(items) do
                totalValue = totalValue + (item.unitValue or 0) * (item.quantity or 1)
            end
        end
    end

    local entry = {
        id = GF.Utils:GenerateID(),
        timestamp = GF.Utils:GetTime(),
        player = player,
        action = action,
        items = items or {},
        totalValue = totalValue or 0,
        note = note,
        status = status,
        trailID = trailID,
        syncVersion = guildData.ledger.nextSyncVersion,
    }

    guildData.ledger.nextSyncVersion = guildData.ledger.nextSyncVersion + 1
    table.insert(guildData.ledger.entries, 1, entry) -- Newest first

    -- Only credit contribution when status is "credited" (after sale)
    -- Deposits start as "pending" — credited later via MarkDepositsAsSold
    if action == GF.ACTIONS.DEPOSIT and status == "credited" then
        self:UpdateContribution(player, totalValue)
    end

    GF.Events:Fire("GF_LEDGER_ENTRY_ADDED", entry)

    -- Broadcast to guild so other clients sync this entry
    if GF.Sender and GF.Sender.BroadcastLedgerEntry then
        GF.Sender:BroadcastLedgerEntry(entry)
    end

    if GF.debug then
        print("|cFF33AAFF[Vault of Truths]|r Ledger: " .. action .. " by " .. player .. " — " .. GF.Utils:FormatMoney(totalValue))
    end

    return entry
end

--- Process a guild bank transaction into a ledger entry
---@param transaction table From TransactionLog
-- Tab classification for ledger tracking
local DEPOSIT_TABS = { [1] = true }          -- Deposits here = contributions
local PERK_TABS = { [2] = true }             -- Withdrawals here = rank perks (no ledger entry)
local SKIP_TABS = { [5] = true, [6] = true } -- Internal logistics (no ledger entry either way)

function Ledger:ProcessBankTransaction(transaction)
    if not transaction.itemID then return end
    if transaction.type ~= "deposit" and transaction.type ~= "withdraw" then return end

    local tab = transaction.tabIndex

    if tab then
        -- Skip internal logistics tabs entirely
        if SKIP_TABS[tab] then return end

        -- Deposits: only count items going into deposit tabs as contributions
        if transaction.type == "deposit" and not DEPOSIT_TABS[tab] then return end

        -- Withdrawals: skip perk tabs (PVP supplies are a reward, not debt)
        if transaction.type == "withdraw" and PERK_TABS[tab] then return end
    end
    -- If tab is nil (unknown), let it through — better to record than miss

    local action = transaction.type == "deposit" and GF.ACTIONS.DEPOSIT or GF.ACTIONS.WITHDRAW
    local value, source = GF.TSM:GetBestPrice(transaction.itemID)
    local unitValue = value or 0

    local items = {
        {
            itemID = transaction.itemID,
            quantity = transaction.quantity or 1,
            unitValue = unitValue,
            priceSource = source or "unknown",
        },
    }

    local totalValue = unitValue * (transaction.quantity or 1)

    self:AddEntry(action, transaction.player, items, totalValue, transaction.itemLink)
end

--- Update a member's running contribution total
---@param player string
---@param amount number Copper value to add
function Ledger:UpdateContribution(player, amount)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    if not guildData.payouts[player] then
        guildData.payouts[player] = {
            totalContributed = 0,
            totalPaidOut = 0,
            currentBalance = 0,
            crafterEarnings = 0,
            auctioneerEarnings = 0,
        }
    end

    local record = guildData.payouts[player]
    record.totalContributed = record.totalContributed + amount
    record.currentBalance = record.totalContributed - record.totalPaidOut
end

--- Mark a pending deposit as "crafted" (mats used in a craft order)
---@param entryID string Ledger entry ID
function Ledger:MarkAsCrafted(entryID)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end
    for _, entry in ipairs(guildData.ledger.entries) do
        if entry.id == entryID and entry.status == "pending" then
            entry.status = "crafted"
            GF.Events:Fire("GF_DEPOSIT_STATUS_CHANGED", entry)
            return true
        end
    end
    return false
end

--- Mark deposits as "sold" and credit contributors (called when AH sale recorded)
---@param itemID number Item that was sold
---@param saleValue number Actual sale price in copper
function Ledger:CreditDepositsForSale(itemID, saleValue)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    -- Find all pending/crafted deposits for this item
    local deposits = {}
    for _, entry in ipairs(guildData.ledger.entries) do
        if entry.action == GF.ACTIONS.DEPOSIT
            and (entry.status == "pending" or entry.status == "crafted") then
            for _, item in ipairs(entry.items) do
                if item.itemID == itemID then
                    deposits[#deposits + 1] = entry
                    break
                end
            end
        end
    end

    if #deposits == 0 then return end

    -- Credit each depositor proportionally based on their deposit value
    local totalDepositValue = 0
    for _, entry in ipairs(deposits) do
        totalDepositValue = totalDepositValue + entry.totalValue
    end

    for _, entry in ipairs(deposits) do
        entry.status = "sold"
        local share = totalDepositValue > 0 and (entry.totalValue / totalDepositValue) or 0
        local creditAmount = math.floor(saleValue * share)

        -- NOW credit the contributor
        self:UpdateContribution(entry.player, creditAmount)

        GF.ChatNotify:Success(
            (entry.player:match("^(.+)-") or entry.player) ..
            " credited " .. GF.Utils:FormatMoney(creditAmount) ..
            " from sale of " .. (C_Item.GetItemInfo(itemID) or "item"))
    end

    GF.Events:Fire("GF_DEPOSITS_CREDITED", itemID, saleValue, deposits)
end

--- Get all pending deposits (not yet credited)
---@return table Array of ledger entries with status "pending" or "crafted"
function Ledger:GetPendingDeposits()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    local pending = {}
    for _, entry in ipairs(guildData.ledger.entries) do
        if entry.action == GF.ACTIONS.DEPOSIT
            and (entry.status == "pending" or entry.status == "crafted") then
            pending[#pending + 1] = entry
        end
    end
    return pending
end

--- Get a member's contribution share (percentage of total deposits)
---@param player string
---@return number share Percentage (0-100)
---@return number playerTotal Player's total contributions in copper
---@return number guildTotal Guild total contributions in copper
function Ledger:GetContributionShare(player)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return 0, 0, 0 end

    local guildTotal = 0
    local playerTotal = 0

    for name, record in pairs(guildData.payouts) do
        guildTotal = guildTotal + record.totalContributed
        if name == player then
            playerTotal = record.totalContributed
        end
    end

    local share = GF.Utils:Percentage(playerTotal, guildTotal)
    return share, playerTotal, guildTotal
end

--- Calculate profit distribution for a sale
---@param saleAmount number Total sale price in copper
---@param matCost number Material cost in copper
---@param ahCut number AH fee in copper
---@param crafterName string|nil Crafter who made the item
---@param auctioneerName string|nil Auctioneer who listed it
---@return table distribution { contributors = {[player]=amount}, crafter = amount, auctioneer = amount, guildTax = amount }
function Ledger:CalculateProfitDistribution(saleAmount, matCost, ahCut, crafterName, auctioneerName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    local profit = saleAmount - matCost - ahCut
    if profit <= 0 then
        return { contributors = {}, crafter = 0, auctioneer = 0, guildTax = 0, profit = profit }
    end

    local split = guildData.guildSettings.profitSplit or GF.DEFAULT_PROFIT_SPLIT

    -- Calculate each pool
    local contributorPool = math.floor(profit * split.contributors / 100)
    local crafterPool = math.floor(profit * split.crafters / 100)
    local auctioneerPool = math.floor(profit * split.auctioneers / 100)
    local guildTax = profit - contributorPool - crafterPool - auctioneerPool -- Remainder to guild

    -- Split contributor pool proportionally by contribution share
    local contributorPayouts = {}
    local guildTotal = 0
    for _, record in pairs(guildData.payouts) do
        guildTotal = guildTotal + record.totalContributed
    end

    if guildTotal > 0 and contributorPool > 0 then
        for playerName, record in pairs(guildData.payouts) do
            if record.totalContributed > 0 then
                -- Only PVPers and Both get contributor share
                if GF.Roles:HasRole(playerName, GF.ROLES.PVPER) then
                    local share = record.totalContributed / guildTotal
                    local payout = math.floor(contributorPool * share)
                    if payout > 0 then
                        contributorPayouts[playerName] = payout
                    end
                end
            end
        end
    end

    return {
        profit = profit,
        contributors = contributorPayouts,
        crafter = crafterPool,
        crafterName = crafterName,
        auctioneer = auctioneerPool,
        auctioneerName = auctioneerName,
        guildTax = guildTax,
    }
end

--- Record a profit distribution (after AH sale)
--- Balance = totalContributed + contributorEarnings + crafterEarnings + auctioneerEarnings - totalPaidOut
---@param distribution table From CalculateProfitDistribution
function Ledger:RecordProfitDistribution(distribution)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    local function EnsureRecord(playerName)
        if not guildData.payouts[playerName] then
            guildData.payouts[playerName] = {
                totalContributed = 0,
                contributorEarnings = 0,
                crafterEarnings = 0,
                auctioneerEarnings = 0,
                totalPaidOut = 0,
                currentBalance = 0,
            }
        end
        return guildData.payouts[playerName]
    end

    -- Credit each contributor their profit share
    for playerName, amount in pairs(distribution.contributors) do
        local record = EnsureRecord(playerName)
        record.contributorEarnings = record.contributorEarnings + amount
    end

    -- Credit crafter
    if distribution.crafterName and distribution.crafter > 0 then
        local record = EnsureRecord(distribution.crafterName)
        record.crafterEarnings = (record.crafterEarnings or 0) + distribution.crafter
    end

    -- Credit auctioneer
    if distribution.auctioneerName and distribution.auctioneer > 0 then
        local record = EnsureRecord(distribution.auctioneerName)
        record.auctioneerEarnings = (record.auctioneerEarnings or 0) + distribution.auctioneer
    end

    GF.Events:Fire("GF_PROFIT_DISTRIBUTED", distribution)
end

--- Get recent ledger entries
---@param limit number|nil Default 20
---@param filter table|nil { action = "deposit", player = "Name-Realm" }
---@return table Array of entries
function Ledger:GetRecent(limit, filter)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    limit = limit or 20
    local results = {}

    for _, entry in ipairs(guildData.ledger.entries) do
        local match = true
        if filter then
            if filter.action and entry.action ~= filter.action then match = false end
            if filter.player and entry.player ~= filter.player then match = false end
        end
        if match then
            results[#results + 1] = entry
            if #results >= limit then break end
        end
    end

    return results
end

--- Print recent ledger entries to chat
---@param limit number|nil
function Ledger:PrintRecent(limit)
    local entries = self:GetRecent(limit or 10)
    if #entries == 0 then
        print("|cFF33AAFF[Vault of Truths]|r No ledger entries yet.")
        return
    end

    print("|cFF33AAFF[Vault of Truths]|r Recent ledger entries:")
    for _, entry in ipairs(entries) do
        local timeStr = GF.Utils:FormatRelativeTime(entry.timestamp)
        local valueStr = GF.Utils:FormatMoney(entry.totalValue)
        print(string.format("  %s | %s | %s | %s | %s",
            timeStr, entry.action, entry.player, valueStr, entry.note or ""))
    end
end

--- Export ledger to CSV format (printed to chat for copy/paste)
function Ledger:ExportCSV()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then
        print("|cFF33AAFF[Vault of Truths]|r No guild data to export.")
        return
    end

    print("|cFF33AAFF[Vault of Truths]|r === CSV Export Start ===")
    print("timestamp,action,player,totalValue,note")
    for _, entry in ipairs(guildData.ledger.entries) do
        print(string.format("%s,%s,%s,%d,%s",
            GF.Utils:FormatDate(entry.timestamp),
            entry.action,
            entry.player,
            entry.totalValue,
            (entry.note or ""):gsub(",", ";")))
    end
    print("|cFF33AAFF[Vault of Truths]|r === CSV Export End ===")
end
