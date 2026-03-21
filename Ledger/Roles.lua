------------------------------------------------------------------------
-- Vault of Truths - Ledger/Roles.lua
-- Role system: PVPer, Crafter, Auctioneer, multi-role support
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Roles = {}
local Roles = GF.Roles
GF:RegisterModule("Roles", Roles)

-- Valid role names
local VALID_ROLES = {
    [GF.ROLES.PVPER] = true,
    [GF.ROLES.CRAFTER] = true,
    [GF.ROLES.AUCTIONEER] = true,
}


function Roles:Init()
    -- Ensure current player has a member record
    GF.Events:On("GF_PLAYER_LOGIN", function()
        local guildData = GF.Settings:GetGuildData()
        if guildData then
            Roles:EnsureMemberRecord(GF.Utils:GetPlayerFullName())
        end
    end)
end

--- Ensure a member record exists in guild data
---@param playerName string "Player-Realm"
---@return table Member record
function Roles:EnsureMemberRecord(playerName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    if not guildData.members[playerName] then
        guildData.members[playerName] = {
            roles = {},
            joinedAt = GF.Utils:GetTime(),
            lastActive = GF.Utils:GetTime(),
            tracks = {},
            primaryTrack = nil,
            recommendedRank = nil,
        }
    end

    return guildData.members[playerName]
end

--- Assign a role to a guild member (officer/owner action)
---@param playerName string Full player name "Player-Realm"
---@param role string Role name or "both" for all roles
---@return boolean success
---@return string|nil error
function Roles:AssignRole(playerName, role)
    -- Permission check
    if not GF.Utils:IsGuildMaster() and not self:IsAddonOfficer() then
        print("|cFFFF0000[Vault of Truths]|r Only officers and the Guild Owner can assign roles.")
        return false, "No permission"
    end

    local member = self:EnsureMemberRecord(playerName)
    role = role:lower()

    if role == "both" then
        -- Assign all roles
        for r in pairs(VALID_ROLES) do
            member.roles[r] = true
        end
        print("|cFF33AAFF[Vault of Truths]|r " .. playerName .. " assigned all roles (PVPer + Crafter + Auctioneer)")
    elseif VALID_ROLES[role] then
        member.roles[role] = true
        print("|cFF33AAFF[Vault of Truths]|r " .. playerName .. " assigned role: " .. role)
    else
        print("|cFFFF0000[Vault of Truths]|r Invalid role '" .. role .. "'. Valid: pvper, crafter, auctioneer, both")
        return false, "Invalid role"
    end

    member.lastActive = GF.Utils:GetTime()
    GF.Events:Fire("GF_ROLE_CHANGED", playerName, role)
    return true
end

--- Remove a role from a member
---@param playerName string
---@param role string
---@return boolean success
function Roles:RemoveRole(playerName, role)
    if not GF.Utils:IsGuildMaster() and not self:IsAddonOfficer() then
        return false, "No permission"
    end

    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[playerName] then return false end

    role = role:lower()
    if role == "both" then
        wipe(guildData.members[playerName].roles)
    elseif VALID_ROLES[role] then
        guildData.members[playerName].roles[role] = nil
    end

    GF.Events:Fire("GF_ROLE_CHANGED", playerName, nil)
    return true
end

--- Check if a member has a specific role
---@param playerName string
---@param role string
---@return boolean
function Roles:HasRole(playerName, role)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[playerName] then return false end
    return guildData.members[playerName].roles[role] == true
end

--- Get all roles for a member
---@param playerName string
---@return table roles { pvper = true, crafter = true, ... }
function Roles:GetRoles(playerName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[playerName] then return {} end
    return guildData.members[playerName].roles or {}
end

--- Get a display string for a member's roles
---@param playerName string
---@return string Like "PVPer, Crafter" or "No Role"
function Roles:GetRoleDisplay(playerName)
    local roles = self:GetRoles(playerName)
    local parts = {}
    if roles[GF.ROLES.PVPER] then parts[#parts + 1] = "|cFF00FF00PVPer|r" end
    if roles[GF.ROLES.CRAFTER] then parts[#parts + 1] = "|cFF00AAFF Crafter|r" end
    if roles[GF.ROLES.AUCTIONEER] then parts[#parts + 1] = "|cFFFFAA00Auctioneer|r" end

    if #parts == 0 then return "|cFF888888No Role|r" end
    return table.concat(parts, ", ")
end

--- Get the highest track tier for a player (for snapshots/display)
---@param playerName string
---@return string tier name from the track system
function Roles:GetTier(playerName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[playerName] then return "none" end
    local member = guildData.members[playerName]
    if not member.tracks then return "none" end
    -- Return the highest tier across all tracks
    local best = "none"
    for _, trackData in pairs(member.tracks) do
        if trackData.tier and trackData.tier ~= "none" then
            best = trackData.tier
        end
    end
    return best
end


--- Check if the current player is a delegated addon officer
---@return boolean
function Roles:IsAddonOfficer()
    if GF.Utils:IsGuildMaster() then return true end
    if GF.Utils:IsOfficer() then return true end

    -- Check delegated officers list
    local playerName = GF.Utils:GetPlayerFullName()
    local guildData = GF.Settings:GetGuildData()
    if guildData and guildData.guildSettings.delegatedOfficers then
        return guildData.guildSettings.delegatedOfficers[playerName] == true
    end

    return false
end

--- Get the permission level of the current player
---@return number GF.PERMISSIONS value
function Roles:GetPermissionLevel()
    if GF.Utils:IsGuildMaster() then
        return GF.PERMISSIONS.OWNER
    elseif self:IsAddonOfficer() then
        return GF.PERMISSIONS.OFFICER
    else
        return GF.PERMISSIONS.MEMBER
    end
end

--- Get all members with a specific role
---@param role string
---@return table Array of player names
function Roles:GetMembersWithRole(role)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    local results = {}
    for playerName, member in pairs(guildData.members) do
        if member.roles and member.roles[role] then
            results[#results + 1] = playerName
        end
    end
    return results
end

--- Check if the current player is a designated AH account
---@return boolean
function Roles:IsAHAccount()
    local playerName = GF.Utils:GetPlayerFullName()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return false end
    return guildData.guildSettings.ahAccounts[playerName] == true
end

------------------------------------------------------------------------
-- Track-based progression
------------------------------------------------------------------------

local VALID_TRACKS = { pvper = true, crafter = true }

--- Select a track for a player ("pvper", "crafter", or "both")
---@param playerName string "Player-Realm"
---@param track string "pvper", "crafter", or "both"
---@return boolean success
---@return string|nil error
function Roles:SelectTrack(playerName, track)
    local member = self:EnsureMemberRecord(playerName)
    track = track:lower()

    local function initTrack(t)
        if member.tracks[t] then return end -- already selected
        if t == "pvper" then
            member.tracks[t] = {
                tier = "recruit",
                totalContributed = 0,
                promotedAt = GF.Utils:GetTime(),
            }
        elseif t == "crafter" then
            member.tracks[t] = {
                tier = "recruit",
                craftsCompleted = 0,
                reliability = 100,
                promotedAt = GF.Utils:GetTime(),
            }
        end
    end

    if track == "crafter" then
        -- Crafters are implicitly PVPers at the same tier (get PVP benefits)
        initTrack("crafter")
        initTrack("pvper")
        member.primaryTrack = member.primaryTrack or "crafter"
        -- Assign both addon roles
        if not member.roles then member.roles = {} end
        member.roles[GF.ROLES.CRAFTER] = true
        member.roles[GF.ROLES.PVPER] = true
    elseif track == "pvper" then
        initTrack("pvper")
        member.primaryTrack = member.primaryTrack or "pvper"
        if not member.roles then member.roles = {} end
        member.roles[GF.ROLES.PVPER] = true
    else
        return false, "Invalid track '" .. track .. "'. Valid: pvper, crafter"
    end

    member.recommendedRank = self:ResolveWoWRank(playerName)
    member.lastActive = GF.Utils:GetTime()
    GF.Events:Fire("GF_TRACK_SELECTED", playerName, track)
    return true
end

--- Get the tier for a specific track
---@param playerName string
---@param track string "pvper" or "crafter"
---@return string tier "none", "recruit", "member"/"crafter", "veteran"/"master"
function Roles:GetTrackTier(playerName, track)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[playerName] then return "none" end

    local member = guildData.members[playerName]
    if not member.tracks or not member.tracks[track] then return "none" end
    return member.tracks[track].tier or "none"
end

-- Crafter tier to equivalent PVPer tier mapping
-- Crafters get PVP benefits at the same progression level
local CRAFTER_TO_PVPER_TIER = {
    recruit = "recruit",
    crafter = "member",   -- Artisan -> Gladiator equivalent
    master = "veteran",   -- Grand Artisan -> Warlord equivalent
}

--- Set the tier for a specific track and record the promotion timestamp
---@param playerName string
---@param track string "pvper" or "crafter"
---@param tier string The new tier value
---@return boolean success
function Roles:SetTrackTier(playerName, track, tier)
    local member = self:EnsureMemberRecord(playerName)
    if not member.tracks[track] then
        return false
    end

    member.tracks[track].tier = tier
    member.tracks[track].promotedAt = GF.Utils:GetTime()

    -- Crafters inherit PVP tier at equivalent level
    if track == "crafter" and member.tracks.pvper then
        local equivPvpTier = CRAFTER_TO_PVPER_TIER[tier]
        if equivPvpTier then
            -- Only upgrade, never downgrade their PVP tier
            local pvpTierOrder = { none = 0, recruit = 1, member = 2, veteran = 3 }
            local currentPvp = pvpTierOrder[member.tracks.pvper.tier] or 0
            local newPvp = pvpTierOrder[equivPvpTier] or 0
            if newPvp > currentPvp then
                member.tracks.pvper.tier = equivPvpTier
            end
        end
    end

    member.recommendedRank = self:ResolveWoWRank(playerName)
    member.lastActive = GF.Utils:GetTime()
    GF.Events:Fire("GF_TRACK_PROMOTED", playerName, track, tier)
    return true
end

--- Get the player's primary track name
---@param playerName string
---@return string|nil primaryTrack "pvper", "crafter", or nil
function Roles:GetPrimaryTrack(playerName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[playerName] then return nil end
    return guildData.members[playerName].primaryTrack
end

--- Resolve the recommended WoW rank index (0-9) based on track tiers.
--- Dual-track members get the lower index (higher rank).
--- Members with no track get rank 8 (Enlisted).
--- Members with no addon record get rank 9 (Newcomer).
---@param playerName string
---@return number rankIndex 0-9
function Roles:ResolveWoWRank(playerName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[playerName] then return 9 end

    local member = guildData.members[playerName]
    if not member.tracks then return 8 end

    local bestRank = nil

    for track, trackData in pairs(member.tracks) do
        local mapping = GF.TRACK_TO_RANK[track]
        if mapping and trackData.tier then
            local rank = mapping[trackData.tier]
            if rank then
                if bestRank == nil or rank < bestRank then
                    bestRank = rank
                end
            end
        end
    end

    return bestRank or 8
end

--- Get the recommended rank name string for a player
---@param playerName string
---@return string rankName
function Roles:GetRecommendedRankName(playerName)
    local rankIndex = self:ResolveWoWRank(playerName)
    return GF.RANK_NAMES[rankIndex] or "Unknown"
end
