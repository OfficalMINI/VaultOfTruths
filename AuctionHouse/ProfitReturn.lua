------------------------------------------------------------------------
-- Vault of Truths - AuctionHouse/ProfitReturn.lua
-- Track and facilitate returning AH profits to guild bank
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.ProfitReturn = {}
local PR = GF.ProfitReturn
GF:RegisterModule("ProfitReturn", PR)

local lastBankMoney = nil
local bankOpen = false

function PR:Init()
    -- Use raw frame for bank events (more reliable than Events dispatcher)
    local moneyFrame = CreateFrame("Frame")

    pcall(function() moneyFrame:RegisterEvent("GUILDBANK_UPDATE_MONEY") end)
    pcall(function() moneyFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW") end)
    pcall(function() moneyFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE") end)

    moneyFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg1 == 10 then
            bankOpen = true
            lastBankMoney = GetGuildBankMoney and GetGuildBankMoney() or nil
            if GF.debug then
                GF.ChatNotify:Debug("Bank opened. Gold: " .. GF.Utils:FormatMoney(lastBankMoney or 0))
            end

        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and arg1 == 10 then
            -- Check gold diff on bank CLOSE (catches deposits made during session)
            if lastBankMoney and bankOpen then
                local currentMoney = GetGuildBankMoney and GetGuildBankMoney() or 0
                local diff = currentMoney - lastBankMoney
                if diff > 0 then
                    PR:RecordReturn(diff)
                end
            end
            bankOpen = false
            lastBankMoney = nil

        elseif event == "GUILDBANK_UPDATE_MONEY" and bankOpen then
            if not lastBankMoney then return end
            local currentMoney = GetGuildBankMoney and GetGuildBankMoney() or 0
            local diff = currentMoney - lastBankMoney
            if diff > 0 then
                PR:RecordReturn(diff)
                lastBankMoney = currentMoney
            end
        end
    end)
end

--- Manually record a gold return (for when auto-detect fails)
---@param amount number Copper amount
function PR:ManualReturn(amount)
    if amount and amount > 0 then
        self:RecordReturn(amount)
    end
end

--- Calculate how much gold the AH account is holding that belongs to the guild
--- This is ALL sale revenue (minus AH cut) that hasn't been deposited back
---@return number totalOwed Total copper the AH account owes the guild bank
---@return table breakdown { totalRevenue, ahCuts, matCosts, profit, returned, owed }
function PR:CalculateReturnAmount()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.ahSales then return 0, {} end

    local totalRevenue = 0   -- All sale prices
    local totalAHCuts = 0    -- AH fees
    local totalMatCosts = 0  -- Mat costs
    local totalProfit = 0    -- Revenue - cuts - mats

    for _, sale in ipairs(guildData.ahSales) do
        totalRevenue = totalRevenue + (sale.salePrice or 0)
        totalAHCuts = totalAHCuts + (sale.ahCut or 0)
        totalMatCosts = totalMatCosts + (sale.matCost or 0)
        totalProfit = totalProfit + (sale.profit or 0)
    end

    -- Calculate how much has already been returned via AH_RETURN ledger entries
    local totalReturned = 0
    for _, entry in ipairs(guildData.ledger.entries) do
        if entry.action == GF.ACTIONS.AH_RETURN then
            totalReturned = totalReturned + (entry.totalValue or 0)
        end
    end

    -- Net received by AH account = revenue - AH cuts (what WoW gives you in mail)
    local netReceived = totalRevenue - totalAHCuts

    -- Owed = what was received minus what was already returned
    local owed = math.max(0, netReceived - totalReturned)

    local breakdown = {
        totalRevenue = totalRevenue,
        ahCuts = totalAHCuts,
        netReceived = netReceived,
        matCosts = totalMatCosts,
        profit = totalProfit,
        returned = totalReturned,
        owed = owed,
        salesCount = #guildData.ahSales,
    }

    return owed, breakdown
end

--- Record that profits have been returned to the guild bank
---@param amount number Copper deposited back
---@return boolean success
function PR:RecordReturn(amount)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return false end

    local auctioneer = GF.Utils:GetPlayerFullName()

    -- Create ledger entry
    GF.Ledger:AddEntry(GF.ACTIONS.AH_RETURN, auctioneer, nil, amount,
        "AH profit return to guild bank")

    GF.Events:Fire("GF_PROFIT_RETURNED", amount, auctioneer)
    GF.ChatNotify:Success("Returned " .. GF.Utils:FormatMoney(amount) .. " to guild bank.")

    return true
end

--- Get a formatted summary of what needs to be returned
---@return string Multi-line summary
function PR:GetReturnSummary()
    local owed, b = self:CalculateReturnAmount()

    local lines = {
        "|cFF33AAFF[Vault of Truths]|r AH Account Summary:",
        "  Total sales (" .. b.salesCount .. "): " .. GF.Utils:FormatMoney(b.totalRevenue),
        "  AH fees:           -" .. GF.Utils:FormatMoney(b.ahCuts),
        "  Net received:       " .. GF.Utils:FormatMoney(b.netReceived),
        "  Already returned:  -" .. GF.Utils:FormatMoney(b.returned),
        "  |cFFFFAA00Owed to guild bank: " .. GF.Utils:FormatMoney(owed) .. "|r",
    }

    return table.concat(lines, "\n")
end

--- Print the return summary to chat
function PR:PrintSummary()
    print(self:GetReturnSummary())
end
