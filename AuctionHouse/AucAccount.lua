------------------------------------------------------------------------
-- Vault of Truths - AuctionHouse/AucAccount.lua
-- Dedicated AH account tracking and management
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.AucAccount = {}
local AA = GF.AucAccount
GF:RegisterModule("AucAccount", AA)

function AA:Init()
    -- If this character is an AH account, show special status
    GF.Events:On("GF_PLAYER_LOGIN", function()
        if GF.Roles:IsAHAccount() then
            GF.ChatNotify:Info("This character is a designated |cFFFFAA00AH Account|r.")
            local pendingSales = GF.SalesLedger:GetPendingSalesCount()
            if pendingSales > 0 then
                GF.ChatNotify:Gold(pendingSales .. " items pending on AH.")
            end
        end
    end)
end

--- Designate a character as an AH account (owner only)
---@param playerName string "Player-Realm"
---@return boolean success
function AA:DesignateAccount(playerName)
    if not GF.Utils:IsGuildMaster() then
        GF.ChatNotify:Error("Only the Guild Owner can designate AH accounts.")
        return false
    end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return false end

    guildData.guildSettings.ahAccounts[playerName] = true

    -- Also assign the auctioneer role
    GF.Roles:AssignRole(playerName, GF.ROLES.AUCTIONEER)

    GF.ChatNotify:Success(playerName .. " designated as AH account.")
    GF.Events:Fire("GF_AH_ACCOUNT_ADDED", playerName)
    return true
end

--- Remove an AH account designation
---@param playerName string
---@return boolean success
function AA:RemoveAccount(playerName)
    if not GF.Utils:IsGuildMaster() then return false end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return false end

    guildData.guildSettings.ahAccounts[playerName] = nil
    GF.Events:Fire("GF_AH_ACCOUNT_REMOVED", playerName)
    return true
end

--- Get all designated AH accounts
---@return table Array of player names
function AA:GetAccounts()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    local accounts = {}
    for name in pairs(guildData.guildSettings.ahAccounts or {}) do
        accounts[#accounts + 1] = name
    end
    return accounts
end

--- Check if the current character is an AH account
---@return boolean
function AA:IsCurrentAccountAH()
    return GF.Roles:IsAHAccount()
end
