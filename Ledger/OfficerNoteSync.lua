------------------------------------------------------------------------
-- Vault of Truths - Ledger/OfficerNoteSync.lua
-- Read-only: import role & crafter data from officer notes
-- Writing officer notes is fully protected in Midnight — addons cannot
-- write them. All data propagation uses addon-to-addon sync instead.
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.OfficerNoteSync = {}
local ONS = GF.OfficerNoteSync
GF:RegisterModule("OfficerNoteSync", ONS)

local PROF_ABBREV = {
    ["Alchemy"] = "AL", ["Blacksmithing"] = "BS", ["Enchanting"] = "EN",
    ["Engineering"] = "EG", ["Herbalism"] = "HB", ["Inscription"] = "IN",
    ["Jewelcrafting"] = "JC", ["Leatherworking"] = "LW", ["Mining"] = "MI",
    ["Skinning"] = "SK", ["Tailoring"] = "TL",
}

local PROF_FROM_ABBREV = {}
for full, abbr in pairs(PROF_ABBREV) do PROF_FROM_ABBREV[abbr] = full end

local ROLE_CHARS = {
    [GF.ROLES.PVPER] = "P",
    [GF.ROLES.CRAFTER] = "C",
    [GF.ROLES.AUCTIONEER] = "A",
}

local ROLE_FROM_CHAR = {}
for role, ch in pairs(ROLE_CHARS) do ROLE_FROM_CHAR[ch] = role end

function ONS:Init()
    -- Read notes on login (import any data officers set manually)
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(8, function()
            if IsInGuild() then
                C_GuildInfo.GuildRoster()
                C_Timer.After(2, function()
                    ONS:ReadAllNotes()
                end)
            end
        end)
    end)

    -- Re-read on roster update (throttled)
    local rosterReadPending = false
    GF.Events:Register("GUILD_ROSTER_UPDATE", function()
        if rosterReadPending then return end
        rosterReadPending = true
        C_Timer.After(3, function()
            rosterReadPending = false
            ONS:ReadAllNotes()
        end)
    end)
end

--- Decode an officer note
function ONS:DecodeNote(note)
    if not note or not note:find("^VoT:") then return nil end

    local data = { roles = {}, tracks = { pvper = 0, crafter = 0 }, professions = {} }
    local payload = note:sub(5)

    -- Split on pipes
    local sections = {}
    for section in (payload .. "|"):gmatch("([^|]*)|") do
        sections[#sections + 1] = section
    end

    -- Section 1: roles
    local rolePart = sections[1] or ""
    for ch in rolePart:gmatch("[A-Z]") do
        local role = ROLE_FROM_CHAR[ch]
        if role then data.roles[role] = true end
    end

    local profPart
    if #sections >= 3 then
        -- New format: roles|tracks|professions
        local trackPart = sections[2] or ""
        local pTier = tonumber(trackPart:match("p(%d)"))
        local cTier = tonumber(trackPart:match("c(%d)"))
        data.tracks.pvper = pTier or 0
        data.tracks.crafter = cTier or 0
        profPart = sections[3]
    else
        -- Old format: roles|professions
        profPart = sections[2]
    end

    -- Professions
    if profPart then
        for abbr, count in profPart:gmatch("(%u%u)(%d+)") do
            if PROF_FROM_ABBREV[abbr] then
                data.professions[PROF_FROM_ABBREV[abbr]] = tonumber(count) or 0
            end
        end
    end

    return data
end

--- Read all guild members' officer notes and import VoT data
function ONS:ReadAllNotes()
    if not IsInGuild() then return end

    local NUM_TO_PVP_TIER = { [0] = "none", [1] = "recruit", [2] = "member", [3] = "veteran" }
    local NUM_TO_CRAFT_TIER = { [0] = "none", [1] = "recruit", [2] = "crafter", [3] = "master" }

    local numTotal = GetNumGuildMembers()
    local imported = 0

    for i = 1, numTotal do
        local name, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if name and officerNote then
            local data = self:DecodeNote(officerNote)
            if data then
                -- Import roles
                local member = GF.Roles:EnsureMemberRecord(name)
                for role, active in pairs(data.roles) do
                    if active then member.roles[role] = true end
                end

                -- Import track tiers
                local guildData = GF.Settings:GetGuildData()
                if guildData then
                    if not guildData.members[name] then guildData.members[name] = {} end
                    if not guildData.members[name].tracks then guildData.members[name].tracks = {} end

                    local pvpNum = data.tracks.pvper or 0
                    local craftNum = data.tracks.crafter or 0

                    if pvpNum > 0 then
                        if type(guildData.members[name].tracks.pvper) ~= "table" then
                            guildData.members[name].tracks.pvper = { tier = "recruit", totalContributed = 0, promotedAt = 0 }
                        end
                        guildData.members[name].tracks.pvper.tier = NUM_TO_PVP_TIER[pvpNum] or "recruit"
                    end
                    if craftNum > 0 then
                        if type(guildData.members[name].tracks.crafter) ~= "table" then
                            guildData.members[name].tracks.crafter = { tier = "recruit", craftsCompleted = 0, reliability = 100, promotedAt = 0 }
                        end
                        guildData.members[name].tracks.crafter.tier = NUM_TO_CRAFT_TIER[craftNum] or "recruit"
                    end
                end

                -- Import profession summary
                if guildData then
                    if not guildData.crafterRecipes then guildData.crafterRecipes = {} end
                    if not guildData.crafterRecipes[name] then
                        guildData.crafterRecipes[name] = { professions = {}, lastScan = 0 }
                    end
                    for profName, count in pairs(data.professions) do
                        if not guildData.crafterRecipes[name].professions[profName] then
                            guildData.crafterRecipes[name].professions[profName] = {
                                count = count, recipes = {}, scannedAt = 0,
                            }
                        end
                    end
                end

                imported = imported + 1
            end
        end
    end

    if imported > 0 and GF.debug then
        GF.ChatNotify:Debug("Imported VoT data from " .. imported .. " officer notes")
    end
end

--- Stub: pending count is always 0 now (no writes)
function ONS:GetPendingCount()
    return 0
end
