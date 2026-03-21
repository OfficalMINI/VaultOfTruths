------------------------------------------------------------------------
-- Vault of Truths - Notifications/ChatNotify.lua
-- Color-coded chat frame messages with [Vault of Truths] prefix
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.ChatNotify = {}
local CN = GF.ChatNotify
GF:RegisterModule("ChatNotify", CN)

-- Color codes for message types
local COLORS = {
    INFO = "|cFF33AAFF",     -- Blue
    SUCCESS = "|cFF00FF00",  -- Green
    WARNING = "|cFFFFAA00",  -- Orange
    ERROR = "|cFFFF0000",    -- Red
    GOLD = "|cFFFFD700",     -- Gold
    MUTED = "|cFF888888",    -- Grey
}

local PREFIX = COLORS.INFO .. "[Vault of Truths]|r "

function CN:Init()
    -- Wire up to internal events for auto-notifications
    GF.Events:On("GF_LEDGER_ENTRY_ADDED", function(entry)
        CN:OnLedgerEntry(entry)
    end)

    GF.Events:On("GF_PAYOUT_RECORDED", function(player, amount)
        if player == GF.Utils:GetPlayerFullName() then
            CN:Gold("Payout received: " .. GF.Utils:FormatMoney(amount))
        end
    end)

    -- Track promotion notifications
    GF.Events:On("GF_TRACK_PROMOTED", function(player, track, newTier)
        local displayName = player:match("^(.+)-") or player
        local isMe = player == GF.Utils:GetPlayerFullName()
        local trackColors = { pvper = COLORS.SUCCESS, crafter = COLORS.INFO }
        local color = trackColors[track] or COLORS.GOLD
        local rankName = GF.Roles:GetRecommendedRankName(player) or newTier

        if isMe then
            CN:Success("You've been promoted! " .. color .. track:upper() .. "|r track: " ..
                COLORS.GOLD .. rankName .. "|r")
            if GF.Toast and GF.Toast.Show then
                GF.Toast:Show("Promotion!", rankName, "Interface\\Icons\\Achievement_PVP_P_15")
            end
        else
            -- Officers see all promotions
            if GF.Roles:IsAddonOfficer() then
                CN:Info(displayName .. " is ready for promotion to " .. COLORS.GOLD .. rankName .. "|r")
            end
        end
    end)

    -- Promotion ready notifications (officer)
    GF.Events:On("GF_PROMOTION_READY", function(player, track, currentTier, newTier)
        if GF.Roles:IsAddonOfficer() then
            local displayName = player:match("^(.+)-") or player
            CN:Warning("Promotion ready: " .. displayName .. " (" .. track .. ": " ..
                currentTier .. " -> " .. COLORS.GOLD .. newTier .. "|r)")
        end
    end)

    -- Officer login: check for mat debt alerts
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(20, function()
            if not GF.Roles:IsAddonOfficer() then return end
            CN:CheckMatDebtAlerts()
            CN:CheckGuildApplicants()
        end)
    end)

    -- Guild applicant notifications (real-time)
    pcall(function()
        local applicantFrame = CreateFrame("Frame")
        applicantFrame:RegisterEvent("CLUB_FINDER_APPLICATIONS_UPDATED")
        applicantFrame:SetScript("OnEvent", function()
            if GF.Roles:IsAddonOfficer() or GF.Utils:IsOfficer() then
                C_Timer.After(1, function()
                    CN:CheckGuildApplicants()
                end)
            end
        end)
    end)

    -- Track selection notification
    GF.Events:On("GF_TRACK_SELECTED", function(player, track)
        local displayName = player:match("^(.+)-") or player
        local isMe = player == GF.Utils:GetPlayerFullName()
        if isMe then
            local trackNames = { pvper = "PVP Contributor", crafter = "Guild Crafter" }
            CN:Success("You've enrolled as a " .. COLORS.GOLD .. (trackNames[track] or track) .. "|r! Type /vot progress to see your track.")
        elseif GF.Roles:IsAddonOfficer() then
            CN:Info(displayName .. " enrolled as " .. track .. ". Consider promoting to " ..
                COLORS.GOLD .. (GF.Roles:GetRecommendedRankName(player) or "recruit") .. "|r")
        end
    end)

    -- AH Sale notifications — broadcast received from auctioneer
    GF.Events:On("GF_AH_SALE_RECORDED", function(sale)
        if not sale then return end
        local myName = GF.Utils:GetPlayerFullName()
        local itemName = sale._itemName or sale.itemName or "an item"
        local saleStr = GF.Utils:FormatMoney(sale.salePrice or 0)
        local profitStr = GF.Utils:FormatMoney(sale.profit or 0)

        -- Skip if we're the auctioneer (already got local notification)
        if sale.auctioneer == myName then return end

        -- Everyone in guild sees the sale
        CN:Gold("Guild AH Sale: " .. itemName .. " sold for " .. saleStr)

        -- Special callout if you were the crafter
        if sale.crafterName and sale.crafterName == myName then
            CN:Success("Your craft sold! Profit: " .. profitStr)
            if GF.Toast and GF.Toast.Show then
                GF.Toast:Show("Your Craft Sold!", profitStr, "Interface\\Icons\\Trade_Engineering")
            end
        end
    end)

    -- On login: show recent sales the player may have missed
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(8, function()
            CN:ShowMissedSales()
        end)
    end)
end

--- Show AH sales that happened since last logout
function CN:ShowMissedSales()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.ahSales then return end

    -- Get last seen timestamp (stored per-character)
    local lastSeen = GF.Settings:GetChar("lastSaleNotifTime") or 0
    local now = time()
    local myName = GF.Utils:GetPlayerFullName()

    local newSales = {}
    for _, sale in ipairs(guildData.ahSales) do
        if (sale.timestamp or 0) > lastSeen then
            newSales[#newSales + 1] = sale
        end
    end

    if #newSales > 0 then
        local totalRevenue = 0
        local myCraftsSold = 0
        for _, sale in ipairs(newSales) do
            totalRevenue = totalRevenue + (sale.salePrice or 0)
            if sale.crafterName == myName then
                myCraftsSold = myCraftsSold + 1
            end
        end

        self:Gold("While you were away: " .. #newSales .. " AH sale(s) totaling " .. GF.Utils:FormatMoney(totalRevenue))

        if myCraftsSold > 0 then
            self:Success(myCraftsSold .. " of your crafts sold!")
            if GF.Toast and GF.Toast.Show then
                GF.Toast:Show("Crafts Sold!", myCraftsSold .. " while you were away", "Interface\\Icons\\Trade_Engineering")
            end
        end
    end

    -- Update last seen time
    GF.Settings:SetChar("lastSaleNotifTime", now)
end

--- Check for new guild applicants (officer only)
function CN:CheckGuildApplicants()
    if not C_ClubFinder then return end
    if not IsInGuild() then return end

    local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not clubId then return end

    -- Request fresh applicant data
    if C_ClubFinder.RequestApplicantList then
        pcall(C_ClubFinder.RequestApplicantList, Enum.ClubFinderRequestType.Guild)
    end

    -- Get applicant list
    local applicants
    if C_ClubFinder.ReturnClubApplicantList then
        applicants = C_ClubFinder.ReturnClubApplicantList(clubId)
    end

    if not applicants or #applicants == 0 then return end

    -- Track which applicants we've already notified about
    if not self._seenApplicants then self._seenApplicants = {} end

    local newCount = 0
    local newNames = {}
    for _, applicant in ipairs(applicants) do
        local name = applicant.name or applicant.playerName or "Unknown"
        if not self._seenApplicants[name] then
            self._seenApplicants[name] = true
            newCount = newCount + 1
            newNames[#newNames + 1] = name
        end
    end

    if newCount > 0 then
        self:Warning("New guild applicant(s): |cFF00FF00" .. table.concat(newNames, ", ") .. "|r")
        self:Info("Review in Guild & Communities (J) > Recruitment > Applicants")
        if GF.Toast and GF.Toast.Show then
            GF.Toast:Show("Guild Applicant!", newCount .. " new", "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
        end
    elseif #applicants > 0 then
        -- Existing applicants not yet processed
        self:Info(#applicants .. " pending guild applicant(s). Review in Guild & Communities (J).")
    end
end

--- Check for crafters with excessive mat debt (>5k gold for >24h)
--- Called on officer login
function CN:CheckMatDebtAlerts()
    if not GF.CrafterTracking then return end

    local debts = GF.CrafterTracking:GetAllMatDebts()
    local DEBT_THRESHOLD = 50000000 -- 5,000g in copper
    local TIME_THRESHOLD = 86400    -- 24 hours

    local alertCount = 0
    for _, entry in ipairs(debts) do
        if entry.net < 0 and math.abs(entry.net) >= DEBT_THRESHOLD then
            -- Check if the oldest withdrawal is over 24h old
            local oldestWithdraw = nil
            for _, e in ipairs(entry.entries or {}) do
                if e.type == "withdraw" then
                    if not oldestWithdraw or e.timestamp < oldestWithdraw then
                        oldestWithdraw = e.timestamp
                    end
                end
            end

            if oldestWithdraw and (time() - oldestWithdraw) > TIME_THRESHOLD then
                self:Error("MAT DEBT ALERT: " .. entry.displayName ..
                    " owes " .. GF.Utils:FormatMoney(math.abs(entry.net)) ..
                    " — outstanding for " .. GF.Utils:FormatRelativeTime(oldestWithdraw))
                alertCount = alertCount + 1
            end
        end
    end

    if alertCount > 0 then
        self:Warning(alertCount .. " crafter(s) with overdue mat debt. Check Officer Panel.")
        if GF.Toast and GF.Toast.Show then
            GF.Toast:Show("Mat Debt Alert", alertCount .. " overdue debts", "Interface\\Icons\\INV_Misc_Coin_01")
        end
    end
end

--- Print an info message
---@param msg string
function CN:Info(msg)
    if GF.Settings:GetChar("notifications.chatEnabled") == false then return end
    print(PREFIX .. msg)
end

--- Print a success message
---@param msg string
function CN:Success(msg)
    if GF.Settings:GetChar("notifications.chatEnabled") == false then return end
    print(PREFIX .. COLORS.SUCCESS .. msg .. "|r")
end

--- Print a warning message
---@param msg string
function CN:Warning(msg)
    if GF.Settings:GetChar("notifications.chatEnabled") == false then return end
    print(PREFIX .. COLORS.WARNING .. msg .. "|r")
end

--- Print an error message (always shown regardless of settings)
---@param msg string
function CN:Error(msg)
    print(PREFIX .. COLORS.ERROR .. msg .. "|r")
end

--- Print a gold/money message
---@param msg string
function CN:Gold(msg)
    if GF.Settings:GetChar("notifications.chatEnabled") == false then return end
    print(PREFIX .. COLORS.GOLD .. msg .. "|r")
end

--- Print a muted/debug message
---@param msg string
function CN:Debug(msg)
    if not GF.debug then return end
    print(PREFIX .. COLORS.MUTED .. msg .. "|r")
end

--- Handle automatic notifications for new ledger entries
---@param entry table Ledger entry
function CN:OnLedgerEntry(entry)
    if GF.Settings:GetChar("notifications.chatEnabled") == false then return end

    local player = entry.player
    local isMe = player == GF.Utils:GetPlayerFullName()
    local valueStr = GF.Utils:FormatMoney(entry.totalValue)

    if entry.action == GF.ACTIONS.DEPOSIT and isMe then
        -- Suppressed: summary shown on bank close by Scanner:ShowDepositSummary()
    elseif entry.action == GF.ACTIONS.WITHDRAW and isMe then
        self:Warning("Withdrew " .. valueStr .. " from guild bank. Balance adjusted.")
    elseif entry.action == GF.ACTIONS.CRAFT_WITHDRAW and isMe then
        self:Info("Mats withdrawn for crafting: " .. valueStr .. " (tracked as debt)")
    elseif entry.action == GF.ACTIONS.AH_SALE then
        self:Gold("AH Sale: " .. valueStr .. " — " .. (entry.note or ""))
    end
end
