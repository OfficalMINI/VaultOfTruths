------------------------------------------------------------------------
-- Vault of Truths - Ledger/Payouts.lua
-- Payout tracking, balance queries, profit split calculations
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Payouts = {}
local Payouts = GF.Payouts
GF:RegisterModule("Payouts", Payouts)

function Payouts:Init()
    -- Nothing special on init
end

--- Get a member's payout record
---@param player string "Player-Realm"
---@return table|nil record { totalContributed, totalPaidOut, currentBalance, crafterEarnings, auctioneerEarnings }
function Payouts:GetRecord(player)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end
    return guildData.payouts[player]
end

--- Record a payout to a member
---@param player string "Player-Realm"
---@param amount number Amount in copper
---@param method string "mail" or "trade" or "guildbank"
---@param recordedBy string Officer who approved the payout
---@return boolean success
function Payouts:RecordPayout(player, amount, method, recordedBy)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return false end

    local record = guildData.payouts[player]
    if not record then
        print("|cFFFF0000[Vault of Truths]|r No payout record for " .. player)
        return false
    end

    record.totalPaidOut = record.totalPaidOut + amount
    record.currentBalance = record.totalContributed + (record.crafterEarnings or 0) + (record.auctioneerEarnings or 0) - record.totalPaidOut
    record.lastPayout = GF.Utils:GetTime()

    -- Create ledger entry for the payout
    GF.Ledger:AddEntry(GF.ACTIONS.PAYOUT, player, nil, amount,
        "Payout via " .. method .. " by " .. recordedBy)

    GF.Events:Fire("GF_PAYOUT_RECORDED", player, amount, method)
    return true
end

--- Get a member's available (unpaid) balance
--- Factors in mat debt from crafting withdrawals (can go negative)
---@param player string "Player-Realm"
---@return number balance in copper (negative if mat debt exceeds earnings)
function Payouts:GetBalance(player)
    local record = self:GetRecord(player)
    if not record then return 0 end
    local earned = (record.contributorEarnings or 0) + (record.crafterEarnings or 0) + (record.auctioneerEarnings or 0)
    local balance = earned - record.totalPaidOut

    -- Subtract outstanding mat debt from crafting withdrawals
    if GF.CrafterTracking then
        local matBalance = GF.CrafterTracking:GetMatBalance(player)
        if matBalance < 0 then
            balance = balance + matBalance -- matBalance is negative, so this subtracts
        end
    end

    return balance
end

--- Deduct an amount from a member's balance to pay for a craft order
--- Records it as a payout in the ledger so the balance is properly tracked
---@param player string "Player-Realm"
---@param amount number Amount in copper to deduct
---@param orderNote string Description of what was paid for
---@return boolean success
---@return string|nil error
function Payouts:PayFromBalance(player, amount, orderNote)
    local balance = self:GetBalance(player)
    if balance < amount then
        return false, "Insufficient balance (" .. GF.Utils:FormatMoney(balance) .. " available)"
    end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return false, "No guild data" end

    local record = guildData.payouts[player]
    if not record then return false, "No payout record" end

    -- Deduct by recording it as a payout
    record.totalPaidOut = record.totalPaidOut + amount
    record.currentBalance = self:GetBalance(player)
    record.lastPayout = GF.Utils:GetTime()

    -- Log in ledger
    GF.Ledger:AddEntry(GF.ACTIONS.PAYOUT, player, nil, amount,
        "Craft payment from balance: " .. (orderNote or ""))

    GF.Events:Fire("GF_BALANCE_PAYMENT", player, amount)

    GF.ChatNotify:Success("Paid " .. GF.Utils:FormatMoney(amount) .. " from your balance for: " .. (orderNote or "craft order"))
    return true
end

--- Get all members with a positive balance (eligible for payout)
---@return table Array of { player, balance, share, roles }
function Payouts:GetPayoutQueue()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    local queue = {}
    for player, record in pairs(guildData.payouts) do
        -- Balance = all earnings from profit splits minus what's been paid out
        local contributorEarnings = record.contributorEarnings or 0
        local crafterEarnings = record.crafterEarnings or 0
        local auctioneerEarnings = record.auctioneerEarnings or 0
        local totalEarned = contributorEarnings + crafterEarnings + auctioneerEarnings
        local balance = totalEarned - record.totalPaidOut

        if balance > 0 then
            local share = GF.Ledger:GetContributionShare(player)
            queue[#queue + 1] = {
                player = player,
                balance = balance,
                share = share,
                totalContributed = record.totalContributed,
                contributorEarnings = contributorEarnings,
                crafterEarnings = crafterEarnings,
                auctioneerEarnings = auctioneerEarnings,
                totalPaidOut = record.totalPaidOut,
                roles = GF.Roles:GetRoles(player),
                rank = GF.Roles:GetRecommendedRankName(player),
            }
        end
    end

    -- Sort by balance descending
    table.sort(queue, function(a, b) return a.balance > b.balance end)
    return queue
end

--- Show balance for a player in chat
---@param targetPlayer string|nil Defaults to current player
function Payouts:ShowBalance(targetPlayer)
    local player = targetPlayer or GF.Utils:GetPlayerFullName()
    local record = self:GetRecord(player)

    if not record then
        print("|cFF33AAFF[Vault of Truths]|r No record for " .. player)
        return
    end

    local share, playerTotal, guildTotal = GF.Ledger:GetContributionShare(player)
    local roles = GF.Roles:GetRoleDisplay(player)
    local rankName = GF.Roles:GetRecommendedRankName(player) or "Newcomer"

    local contributorEarnings = record.contributorEarnings or 0
    local crafterEarnings = record.crafterEarnings or 0
    local auctioneerEarnings = record.auctioneerEarnings or 0
    local totalEarned = contributorEarnings + crafterEarnings + auctioneerEarnings
    local balance = math.max(0, totalEarned - record.totalPaidOut)

    print("|cFF33AAFF[Vault of Truths]|r Balance for " .. player .. ":")
    print("  Roles: " .. roles)
    print("  Rank: |cFFFFD700" .. rankName .. "|r")
    print("  Contribution share: " .. share .. "% (" .. GF.Utils:FormatGold(playerTotal) .. " of " .. GF.Utils:FormatGold(guildTotal) .. ")")
    print("  |cFFAAAAAABreakdown:|r")
    print("    Deposits (raw):      " .. GF.Utils:FormatMoney(record.totalContributed))
    print("    Contributor profit:   " .. GF.Utils:FormatMoney(contributorEarnings))
    print("    Crafter earnings:     " .. GF.Utils:FormatMoney(crafterEarnings))
    print("    Auctioneer earnings:  " .. GF.Utils:FormatMoney(auctioneerEarnings))
    print("    |cFFFFFFFFTotal earned:        " .. GF.Utils:FormatMoney(totalEarned) .. "|r")
    print("    Total paid out:       " .. GF.Utils:FormatMoney(record.totalPaidOut))
    print("  |cFF00FF00Available balance: " .. GF.Utils:FormatMoney(balance) .. "|r")
end

--- Get total guild payout liability (sum of all unpaid balances)
---@return number Total in copper
function Payouts:GetTotalLiability()
    local queue = self:GetPayoutQueue()
    local total = 0
    for _, entry in ipairs(queue) do
        total = total + entry.balance
    end
    return total
end

--- Get payout summary stats
---@return table { totalDistributed, totalPending, memberCount, avgBalance }
function Payouts:GetSummary()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return { totalDistributed = 0, totalPending = 0, memberCount = 0, avgBalance = 0 } end

    local totalDist = 0
    local totalPending = 0
    local count = 0

    for _, record in pairs(guildData.payouts) do
        totalDist = totalDist + record.totalPaidOut
        local earned = (record.contributorEarnings or 0) + (record.crafterEarnings or 0) + (record.auctioneerEarnings or 0)
        local balance = earned - record.totalPaidOut
        if balance > 0 then
            totalPending = totalPending + balance
        end
        count = count + 1
    end

    return {
        totalDistributed = totalDist,
        totalPending = totalPending,
        memberCount = count,
        avgBalance = count > 0 and math.floor(totalPending / count) or 0,
    }
end
