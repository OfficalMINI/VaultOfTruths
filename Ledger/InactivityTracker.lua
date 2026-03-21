------------------------------------------------------------------------
-- Vault of Truths - Ledger/InactivityTracker.lua
-- Track guild member inactivity and suggest/auto-demote inactive members
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.InactivityTracker = {}
local IT = GF.InactivityTracker
GF:RegisterModule("InactivityTracker", IT)

local DEFAULT_SETTINGS = {
    enabled = false,
    warnDays = 14,
    demoteDays = 30,
    removeDays = 60,
    autoWarn = true,
    exemptRanks = {},
    exemptPlayers = {},
}

function IT:Init()
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(15, function()
            if GF.Roles:GetPermissionLevel() >= GF.PERMISSIONS.OFFICER then
                IT:ScanRoster()
            end
        end)
    end)
end

function IT:GetSettings()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return DEFAULT_SETTINGS end
    if not guildData.guildSettings.inactivity then
        guildData.guildSettings.inactivity = GF.Utils:DeepCopy(DEFAULT_SETTINGS)
    end
    return guildData.guildSettings.inactivity
end

function IT:SetSetting(key, value)
    local settings = self:GetSettings()
    settings[key] = value
end

function IT:ScanRoster()
    if not IsInGuild() then return { warned = {}, demote = {}, remove = {}, active = {} } end
    local settings = self:GetSettings()
    if not settings.enabled then return { warned = {}, demote = {}, remove = {}, active = {} } end

    C_GuildInfo.GuildRoster()
    local numTotal = GetNumGuildMembers()
    local results = { warned = {}, demote = {}, remove = {}, active = {} }

    for i = 1, numTotal do
        local name, rankName, rankIndex, level, _, _, _, officerNote, isOnline = GetGuildRosterInfo(i)
        if name and not settings.exemptRanks[rankIndex] and not settings.exemptPlayers[name] then
            local yearsOff, monthsOff, daysOff = GetGuildRosterLastOnline(i)
            local totalDays = (yearsOff or 0) * 365 + (monthsOff or 0) * 30 + (daysOff or 0)
            if isOnline then totalDays = 0 end

            local entry = {
                name = name,
                displayName = name:match("^(.+)-") or name,
                rank = rankName, rankIndex = rankIndex,
                daysOffline = totalDays, rosterIndex = i,
            }

            if totalDays >= settings.removeDays then
                results.remove[#results.remove + 1] = entry
            elseif totalDays >= settings.demoteDays then
                results.demote[#results.demote + 1] = entry
            elseif totalDays >= settings.warnDays then
                results.warned[#results.warned + 1] = entry
            else
                results.active[#results.active + 1] = entry
            end
        end
    end

    for _, list in pairs(results) do
        table.sort(list, function(a, b) return a.daysOffline > b.daysOffline end)
    end

    local totalInactive = #results.warned + #results.demote + #results.remove
    if totalInactive > 0 then
        GF.ChatNotify:Warning("Inactivity: " .. #results.warned .. " warn, " .. #results.demote .. " demote, " .. #results.remove .. " remove")
    end

    return results
end
