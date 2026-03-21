------------------------------------------------------------------------
-- Vault of Truths - Data/DailyActivities.lua
-- Daily activity suggestions — PVP sourced, tradeable only, no AH buying
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.DailyActivities = {}
local DA = GF.DailyActivities

function DA:GetSuggestions()
    local suggestions = {}

    -- PVP activities that generate bankable items
    suggestions[#suggestions + 1] = {
        title = "Spend Honor on Heraldry",
        description = "Buy Aspirant's Heraldry (tradeable) from the Honor vendor. Deposit to guild bank.",
        priority = 1,
        category = "pvp",
        icon = "Interface\\Icons\\INV_Misc_Tournaments_banner_Human",
    }

    suggestions[#suggestions + 1] = {
        title = "PVP for BoE Drops",
        description = "Battlegrounds and War Mode can drop tradeable BoE gear. Bank any you won't use.",
        priority = 1,
        category = "pvp",
        icon = "Interface\\Icons\\Achievement_BG_WinAB",
    }

    suggestions[#suggestions + 1] = {
        title = "Disenchant BoP PVP Gear",
        description = "DE soulbound PVP gear you don't need. Midnight mats like Fractured Glass and Shattered Starlight are bankable.",
        priority = 2,
        category = "pvp",
        icon = "Interface\\Icons\\INV_Enchant_Dust",
    }

    suggestions[#suggestions + 1] = {
        title = "Buy Heliotrope with Honor",
        description = "Trade Honor at the vendor for Infused Heliotrope (crafting material). Deposit to guild bank for crafters.",
        priority = 1,
        category = "pvp",
        icon = "Interface\\Icons\\INV_Misc_Gem_01",
    }

    suggestions[#suggestions + 1] = {
        title = "Buy Recipes with Honor",
        description = "Honor vendor sells tradeable PVP crafting recipes. Buy and deposit to guild bank for crafters.",
        priority = 2,
        category = "pvp",
        icon = "Interface\\Icons\\INV_Scroll_03",
    }

    -- Dynamic: open orders
    local guildData = GF.Settings:GetGuildData()
    if guildData then
        local openOrders = GF.OrderBoard:GetOrders(GF.ORDER_STATUS.OPEN)
        if #openOrders > 0 then
            suggestions[#suggestions + 1] = {
                title = #openOrders .. " Crafting Orders Open",
                description = "Guild members are waiting. Check the Crafting tab to accept an order and earn your crafter share.",
                priority = 1,
                category = "crafting",
                icon = "Interface\\Icons\\INV_Misc_Note_01",
            }
        end
    end

    -- Deposit
    suggestions[#suggestions + 1] = {
        title = "Deposit Bankable Items",
        description = "Check bags for heraldry, crests, reagents, and BoE drops. Deposit to guild bank for contribution credit.",
        priority = 1,
        category = "guild",
        icon = "Interface\\Icons\\INV_Misc_Bag_10_Green",
    }

    return suggestions
end
