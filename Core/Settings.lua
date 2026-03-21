------------------------------------------------------------------------
-- Vault of Truths - Core/Settings.lua
-- SavedVariables initialization, defaults, and schema migration
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Settings = {}
local Settings = GF.Settings

local SCHEMA_VERSION = 2
local CHAR_SCHEMA_VERSION = 1

-- Default account-wide database
local DB_DEFAULTS = {
    version = SCHEMA_VERSION,
    guilds = {},
    externalGuilds = {}, -- [guildName] = { crafterRecipes, orders, channelName, lastSync }
    settings = {
        minimapIcon = { hide = false },
        debugMode = false,
        syncEnabled = true,
        guildChatAnnounce = true, -- Post sale announcements to guild chat
    },
}

-- Default per-character database
local CHAR_DB_DEFAULTS = {
    version = CHAR_SCHEMA_VERSION,
    notifications = {
        toastEnabled = true,
        chatEnabled = true,
        soundEnabled = true,
    },
    ui = {
        mainFramePoint = { "CENTER", nil, "CENTER", 0, 0 },
        mainFrameWidth = 900,
        mainFrameHeight = 620,
        lastTab = "dashboard",
    },
    lootWatcher = {
        enabled = true,
        autoPrintValue = true,
    },
    minimapAngle = 3.8397, -- ~220 degrees in radians
}

-- Default guild data structure
local GUILD_DEFAULTS = {
    ledger = {
        entries = {},
        nextSyncVersion = 1,
    },
    members = {}, -- ["Player-Realm"] = { roles = {}, tracks = {}, ... }
    payouts = {},
    orders = {},
    bankSnapshots = {
        lastScan = 0,
        tabs = {},
    },
    transactionLog = {},
    ahSales = {},
    guildSettings = {
        priceSource = "first(DBMinBuyout, DBMarket)",
        feePercent = 10,
        profitSplit = {
            contributors = 50,
            crafters = 15,
            auctioneers = 10,
            guildTax = 25,
        },
        tierThresholds = {
            bronze = 1000000,
            silver = 10000000,
            gold = 100000000,
        },
        trackingPeriod = "weekly", -- "weekly" or "monthly"
        delegatedOfficers = {}, -- ["Player-Realm"] = true
        ahAccounts = {}, -- ["Player-Realm"] = true
        craftCommission = 30000000, -- 3,000g in copper
        trackThresholds = {
            pvper = {
                recruit = 0,
                member = 50000000,        -- 5,000g
                veteran = 5000000000,     -- 500,000g
            },
            crafter = {
                recruit = 0,
                crafter = { crafts = 25, reliability = 80 },
                master = { crafts = 100, reliability = 90 },
            },
        },
        systemLocked = false,
    },
}

--- Initialize SavedVariables with defaults
function Settings:Init()
    -- Account-wide DB
    if not VaultOfTruthsDB then
        VaultOfTruthsDB = GF.Utils:DeepCopy(DB_DEFAULTS)
    else
        -- Merge any missing defaults
        self:MergeDefaults(VaultOfTruthsDB, DB_DEFAULTS)
        -- Run migrations if needed
        self:MigrateDB(VaultOfTruthsDB)
    end

    -- Per-character DB
    if not VaultOfTruthsCharDB then
        VaultOfTruthsCharDB = GF.Utils:DeepCopy(CHAR_DB_DEFAULTS)
    else
        self:MergeDefaults(VaultOfTruthsCharDB, CHAR_DB_DEFAULTS)
        self:MigrateCharDB(VaultOfTruthsCharDB)
    end

    -- Apply debug mode
    GF.debug = VaultOfTruthsDB.settings.debugMode

    -- Print load message
    if GF.Utils:IsInVoTGuild() then
        print("|cFF33AAFF[Vault of Truths]|r v" .. GF.VERSION .. " — PVP guild economy. Type /vot for commands.")
    else
        print("|cFF33AAFF[Vault of Truths]|r v" .. GF.VERSION .. " — Join Vault of Truths to use this addon. Search Guild Finder (J) to apply.")
    end
end

--- Ensure the current guild has a data entry
---@return table|nil Guild data table, or nil if not in a guild
function Settings:GetGuildData()
    local key = GF.Utils:GetGuildKey()
    if not key then return nil end

    if not VaultOfTruthsDB.guilds[key] then
        VaultOfTruthsDB.guilds[key] = GF.Utils:DeepCopy(GUILD_DEFAULTS)
    end

    return VaultOfTruthsDB.guilds[key]
end

--- Get a setting value from account-wide settings
---@param key string Setting key (dot notation supported: "notifications.toastEnabled")
---@return any
function Settings:Get(key)
    return self:GetNested(VaultOfTruthsDB.settings, key)
end

--- Set a setting value in account-wide settings
---@param key string Setting key
---@param value any
function Settings:Set(key, value)
    self:SetNested(VaultOfTruthsDB.settings, key, value)
end

--- Get a per-character setting
---@param key string Setting key (dot notation)
---@return any
function Settings:GetChar(key)
    return self:GetNested(VaultOfTruthsCharDB, key)
end

--- Set a per-character setting
---@param key string Setting key
---@param value any
function Settings:SetChar(key, value)
    self:SetNested(VaultOfTruthsCharDB, key, value)
end

--- Get a guild-level setting
---@param key string Setting key
---@return any
function Settings:GetGuild(key)
    local guildData = self:GetGuildData()
    if not guildData then return nil end
    return self:GetNested(guildData.guildSettings, key)
end

--- Set a guild-level setting (owner/officer only)
---@param key string Setting key
---@param value any
---@return boolean success
function Settings:SetGuild(key, value)
    local guildData = self:GetGuildData()
    if not guildData then return false end
    self:SetNested(guildData.guildSettings, key, value)
    GF.Events:Fire("GF_GUILD_SETTING_CHANGED", key, value)
    return true
end

--- Recursively merge defaults into an existing table (doesn't overwrite existing values)
---@param target table
---@param defaults table
function Settings:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = GF.Utils:DeepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            self:MergeDefaults(target[k], v)
        end
    end
end

--- Get a value using dot notation path
---@param tbl table
---@param path string Dot-separated path like "notifications.toastEnabled"
---@return any
function Settings:GetNested(tbl, path)
    local current = tbl
    for key in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[key]
    end
    return current
end

--- Set a value using dot notation path
---@param tbl table
---@param path string
---@param value any
function Settings:SetNested(tbl, path, value)
    local current = tbl
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        keys[#keys + 1] = key
    end
    for i = 1, #keys - 1 do
        local key = keys[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    current[keys[#keys]] = value
end

--- Run database migrations
---@param db table
function Settings:MigrateDB(db)
    if not db.version then db.version = 0 end

    -- Migration 1->2: Migrate per-character guild keys to shared guild keys
    -- Old format: "PlayerName-Realm::GuildName" -> New format: "GuildName-Realm"
    if db.version < 2 and db.guilds then
        local toMigrate = {}
        for key, data in pairs(db.guilds) do
            local guildName = key:match("::(.+)$")
            local playerRealm = key:match("^(.+)::")
            local realm = playerRealm and playerRealm:match("-(.+)$")
            if guildName and realm then
                local newKey = guildName .. "-" .. realm
                if not toMigrate[newKey] then
                    toMigrate[newKey] = data
                end
            end
        end
        for newKey, data in pairs(toMigrate) do
            if not db.guilds[newKey] then
                db.guilds[newKey] = data
            end
        end
    end

    db.version = SCHEMA_VERSION
end

--- Run per-character database migrations
---@param db table
function Settings:MigrateCharDB(db)
    if not db.version then db.version = 0 end

    -- Future migrations go here

    db.version = CHAR_SCHEMA_VERSION
end

--- Get or create external guild data for a non-guildie connection
---@param guildName string
---@return table
function Settings:GetExternalGuildData(guildName)
    if not VaultOfTruthsDB.externalGuilds then
        VaultOfTruthsDB.externalGuilds = {}
    end
    if not VaultOfTruthsDB.externalGuilds[guildName] then
        VaultOfTruthsDB.externalGuilds[guildName] = {
            crafterRecipes = {},
            orders = {},
            channelName = GF.CHANNEL_PREFIX .. guildName:gsub("%s", ""),
            lastSync = 0,
        }
    end
    return VaultOfTruthsDB.externalGuilds[guildName]
end

--- Remove an external guild connection
---@param guildName string
function Settings:RemoveExternalGuild(guildName)
    if VaultOfTruthsDB.externalGuilds then
        VaultOfTruthsDB.externalGuilds[guildName] = nil
    end
end

--- Get all connected external guild names
---@return table Array of guild name strings
function Settings:GetExternalGuildNames()
    local names = {}
    if VaultOfTruthsDB.externalGuilds then
        for name in pairs(VaultOfTruthsDB.externalGuilds) do
            names[#names + 1] = name
        end
    end
    return names
end
