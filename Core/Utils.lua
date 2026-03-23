------------------------------------------------------------------------
-- Vault of Truths - Core/Utils.lua
-- Shared utility functions
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Utils = {}
local Utils = GF.Utils

--- Convert copper amount to formatted gold string
---@param copper number Amount in copper
---@return string Formatted string like "1,234g 56s 78c"
function Utils:FormatMoney(copper)
    if not copper then return "|cFF888888Not Synced|r" end
    if copper == 0 then return "0g" end

    local negative = copper < 0
    copper = math.abs(copper)

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100

    local parts = {}
    if gold > 0 then
        -- Add comma separators for large gold amounts
        local formatted = tostring(gold)
        local k
        while true do
            formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
            if k == 0 then break end
        end
        parts[#parts + 1] = formatted .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if cop > 0 then
        parts[#parts + 1] = cop .. "c"
    end

    local result = table.concat(parts, " ")
    if negative then result = "-" .. result end
    return result
end

--- Convert copper to simple gold string (no silver/copper)
---@param copper number Amount in copper
---@return string Like "1,234g"
function Utils:FormatGold(copper)
    if not copper then return "|cFF888888Not Synced|r" end
    if copper == 0 then return "0g" end
    local gold = math.floor(math.abs(copper) / 10000)
    local formatted = tostring(gold)
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    if copper < 0 then formatted = "-" .. formatted end
    return formatted .. "g"
end

--- Generate a short unique ID (8 hex chars from time + random)
---@return string
function Utils:GenerateID()
    local t = time()
    local r = math.random(0, 0xFFFF)
    return string.format("%08x", bit.bxor(t, r))
end

--- Get the player's full name with realm
---@return string "PlayerName-RealmName"
function Utils:GetPlayerFullName()
    local name, realm = UnitFullName("player")
    realm = realm or GetNormalizedRealmName() or ""
    if realm == "" then
        realm = GetNormalizedRealmName() or "UnknownRealm"
    end
    return name .. "-" .. realm
end

--- Parse an item link to extract the item ID
---@param link string Item link string
---@return number|nil itemID
function Utils:GetItemIDFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

--- Deep copy a table
---@param orig table
---@return table
function Utils:DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[self:DeepCopy(k)] = self:DeepCopy(v)
    end
    return setmetatable(copy, getmetatable(orig))
end

--- Get current time as Unix timestamp
---@return number
function Utils:GetTime()
    return time()
end

--- Format a Unix timestamp into a readable date string
---@param timestamp number Unix timestamp
---@return string "YYYY-MM-DD HH:MM"
function Utils:FormatDate(timestamp)
    return date("%Y-%m-%d %H:%M", timestamp)
end

--- Format a Unix timestamp as relative time ("2h ago", "3d ago")
---@param timestamp number Unix timestamp
---@return string
function Utils:FormatRelativeTime(timestamp)
    local diff = time() - timestamp
    if diff < 60 then return "just now" end
    if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    return math.floor(diff / 86400) .. "d ago"
end

--- Calculate percentage with rounding
---@param part number
---@param whole number
---@return number Percentage (0-100)
function Utils:Percentage(part, whole)
    if not whole or whole == 0 then return 0 end
    return math.floor((part / whole) * 10000 + 0.5) / 100
end

--- Check if the player is the guild master
---@return boolean
function Utils:IsGuildMaster()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 0
end

--- Check if the player is a guild officer
---@return boolean
function Utils:IsOfficer()
    if C_GuildInfo then
        if C_GuildInfo.IsGuildOfficer then
            return C_GuildInfo.IsGuildOfficer()
        end
        if C_GuildInfo.CanEditOfficerNote then
            return C_GuildInfo.CanEditOfficerNote()
        end
    end
    if CanEditOfficerNote then
        return CanEditOfficerNote()
    end
    if IsInGuild() then
        local _, _, rankIndex = GetGuildInfo("player")
        return rankIndex and rankIndex <= 1
    end
    return false
end

--- Get the guild key for SavedVariables
--- Uses guild name + realm so all alts in the same guild share data
---@return string|nil
function Utils:GetGuildKey()
    if not IsInGuild() then return nil end
    local guildName = GetGuildInfo("player")
    if not guildName then return nil end
    local realm = GetNormalizedRealmName() or "UnknownRealm"
    return guildName .. "-" .. realm
end

--- Check if the player is in Vault of Truths guild
---@return boolean
function Utils:IsInVoTGuild()
    if not IsInGuild() then return false end
    local guildName = GetGuildInfo("player")
    return guildName == "Vault of Truths"
end
-- test
