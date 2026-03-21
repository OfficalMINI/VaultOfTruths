------------------------------------------------------------------------
-- Vault of Truths - Core/Init.lua
-- Addon namespace, version constants, and shared state initialization
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

-- Version info
GF.VERSION = "1.0.0"
GF.ADDON_NAME = ADDON_NAME
GF.PREFIX = "VaultOfTruths" -- Addon message prefix (max 16 chars)
GF.CHANNEL_PREFIX = "VoT_" -- Shared channel prefix for non-guildie discovery

-- Role constants
GF.ROLES = {
    PVPER = "pvper",
    CRAFTER = "crafter",
    AUCTIONEER = "auctioneer",
}

-- Permission levels
GF.PERMISSIONS = {
    MEMBER = 1,
    OFFICER = 2,
    OWNER = 3,
}

-- Ledger action types
GF.ACTIONS = {
    DEPOSIT = "deposit",
    WITHDRAW = "withdraw",
    PAYOUT = "payout",
    FEE = "fee",
    CRAFT_WITHDRAW = "craft_withdraw",
    CRAFT_DEPOSIT = "craft_deposit",   -- Finished item deposited back after crafting
    AH_WITHDRAW = "ah_withdraw",       -- Item taken for AH listing
    AH_LIST = "ah_list",               -- Item listed on AH
    AH_SALE = "ah_sale",
    AH_RETURN = "ah_return",
}

-- Order status constants
GF.ORDER_STATUS = {
    OPEN = "open",
    ACCEPTED = "accepted",
    COMPLETED = "completed",
    CANCELLED = "cancelled",
}

-- Role tier thresholds (in copper, configurable via settings)
GF.DEFAULT_TIER_THRESHOLDS = {
    BRONZE = 1000000,   -- 100g
    SILVER = 10000000,  -- 1,000g
    GOLD = 100000000,   -- 10,000g
}

-- Default profit split percentages
GF.DEFAULT_PROFIT_SPLIT = {
    contributors = 50,
    crafters = 15,
    auctioneers = 10,
    guildTax = 25,
}

-- External craft commission (copper) — charged when guild supplies mats
GF.DEFAULT_CRAFT_COMMISSION = 30000000 -- 3,000g

-- Guild rank names (index 0-9, matching WoW rank order)
GF.RANK_NAMES = {
    [0] = "Guild Master",
    [1] = "Officer",
    [2] = "Grand Artisan",
    [3] = "Warlord",
    [4] = "Artisan",
    [5] = "Gladiator",
    [6] = "Apprentice",
    [7] = "Combatant",
    [8] = "Enlisted",
    [9] = "Newcomer",
}

-- Track tiers (progression within each track)
GF.TRACK_TIERS = {
    NONE = "none",
    RECRUIT = "recruit",
    MEMBER = "member",       -- PVPer mid-tier
    VETERAN = "veteran",     -- PVPer top-tier
    CRAFTER = "crafter",     -- Crafter mid-tier
    MASTER = "master",       -- Crafter top-tier
}

-- Map track + tier to WoW rank index (lower = higher rank)
GF.TRACK_TO_RANK = {
    pvper = {
        recruit = 7,  -- PVPer Recruit
        member = 5,   -- PVPer
        veteran = 3,  -- PVPer Veteran
    },
    crafter = {
        recruit = 6,  -- Crafter Recruit
        crafter = 4,  -- Crafter
        master = 2,   -- Master Crafter
    },
}

-- Default progression thresholds (copper for PVP, counts for crafter)
GF.DEFAULT_TRACK_THRESHOLDS = {
    pvper = {
        recruit = 0,              -- auto on track selection
        member = 50000000,        -- 5,000g contributed
        veteran = 5000000000,     -- 500,000g contributed
    },
    crafter = {
        recruit = 0,
        crafter = { crafts = 25, reliability = 80 },
        master = { crafts = 100, reliability = 90 },
    },
}

-- Module registry
GF.modules = {}

--- Register a module with Vault of Truths
---@param name string Module name
---@param module table Module table
function GF:RegisterModule(name, module)
    self.modules[name] = module
end

--- Get a registered module
---@param name string Module name
---@return table|nil
function GF:GetModule(name)
    return self.modules[name]
end

-- Expose the namespace globally only in debug mode
-- Production builds should not pollute globals
if GF.debug then
    _G["VaultOfTruths"] = GF
end
