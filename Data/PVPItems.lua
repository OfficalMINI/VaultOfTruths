------------------------------------------------------------------------
-- Vault of Truths - Data/PVPItems.lua
-- Midnight (12.0) tradeable items: PVP, recipes, crafting mats.
-- All BoP items excluded. Only items that can go in guild bank.
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.PVPItems = {}
local PVPItems = GF.PVPItems

local BIND_ON_PICKUP = 1

PVPItems.CATEGORIES = {
    PVP_HERALDRY = "pvp_heraldry",
    REAGENT = "reagent",
    RECIPE = "recipe",
    ENCHANT_MAT = "enchant_mat",
    CRAFT_MAT = "craft_mat",
    BOE_GEAR = "boe_gear",
    MISC = "misc",
}

-- ONLY tradeable Midnight items. Verified each on wowhead.com March 2026.
PVPItems.items = {
    -- ========== GALACTIC HERALDRY (Midnight PVP) ==========
    -- Combatant's is the ONLY tradeable heraldry
    -- Aspirant's (256607) = BoP, Gladiator's (256608) = BoP
    [256559] = { category = "pvp_heraldry", desc = "Galactic Combatant's Heraldry" },

    -- ========== REAGENTS (tradeable) ==========
    -- The gems themselves (241142/3/4) are BoP Unique-Equipped
    [253307] = { category = "reagent", desc = "Infused Heliotrope" },

    -- ========== CONSUMABLES (tradeable, from PVP boxes / crafted) ==========
    [259085] = { category = "reagent", desc = "Void-Touched Augment Rune" },
    [241334] = { category = "reagent", desc = "Vicious Thalassian Flask of Honor (Rank 2)" },
    [241335] = { category = "reagent", desc = "Vicious Thalassian Flask of Honor (Rank 1)" },

    -- ========== RECIPES from Mirvedon (NPC 243225) ==========
    -- All tradeable, bought with 7500 Honor each

    -- Alchemy (1)
    [257417] = { category = "recipe", desc = "Recipe: Vicious Thalassian Flask of Honor" },

    -- Blacksmithing (16)
    [238218] = { category = "recipe", desc = "Plans: Thalassian Competitor's Plate Breastplate" },
    [238219] = { category = "recipe", desc = "Plans: Thalassian Competitor's Plate Sabatons" },
    [238220] = { category = "recipe", desc = "Plans: Thalassian Competitor's Plate Gauntlets" },
    [238221] = { category = "recipe", desc = "Plans: Thalassian Competitor's Plate Helm" },
    [238222] = { category = "recipe", desc = "Plans: Thalassian Competitor's Plate Greaves" },
    [238223] = { category = "recipe", desc = "Plans: Thalassian Competitor's Plate Pauldrons" },
    [238224] = { category = "recipe", desc = "Plans: Thalassian Competitor's Plate Waistguard" },
    [238225] = { category = "recipe", desc = "Plans: Thalassian Competitor's Plate Armguards" },
    [238226] = { category = "recipe", desc = "Plans: Thalassian Competitor's Pickaxe" },
    [238227] = { category = "recipe", desc = "Plans: Thalassian Competitor's Knife" },
    [238228] = { category = "recipe", desc = "Plans: Thalassian Competitor's Maxim" },
    [238229] = { category = "recipe", desc = "Plans: Thalassian Competitor's Bulwark" },
    [238230] = { category = "recipe", desc = "Plans: Thalassian Competitor's Splitter" },
    [238231] = { category = "recipe", desc = "Plans: Thalassian Competitor's Skewer" },
    [238232] = { category = "recipe", desc = "Plans: Thalassian Competitor's Greatsword" },
    [238233] = { category = "recipe", desc = "Plans: Thalassian Competitor's Sword" },

    -- Engineering (13)
    [268480] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Rifle" },
    [257298] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Plate Dunkers" },
    [257369] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Mail Footlinks" },
    [257370] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Leather Sliders" },
    [257371] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Cloth Tip-Toes" },
    [257407] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Plate Bindings" },
    [257408] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Plate Guard" },
    [257410] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Cloth Cuffs" },
    [257411] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Cloth Goggles" },
    [257413] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Leather Bands" },
    [257414] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Leather Optics" },
    [257415] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Mail Links" },
    [257416] = { category = "recipe", desc = "Schematic: Thalassian Competitor's Mail Visor" },

    -- Enchanting (7)
    [257243] = { category = "recipe", desc = "Technique: Thalassian Competitor's Lamp" },
    [257258] = { category = "recipe", desc = "Technique: Thalassian Competitor's Bow" },
    [257259] = { category = "recipe", desc = "Technique: Thalassian Competitor's Pillar" },
    [257260] = { category = "recipe", desc = "Technique: Thalassian Competitor's Emblem" },
    [257261] = { category = "recipe", desc = "Technique: Thalassian Competitor's Insignia of Alacrity" },
    [257262] = { category = "recipe", desc = "Technique: Thalassian Competitor's Medallion" },
    [268366] = { category = "recipe", desc = "Technique: Thalassian Competitor's Staff" },

    -- Jewelcrafting (5)
    [256702] = { category = "recipe", desc = "Design: Thalassian Competitor's Signet" },
    [256706] = { category = "recipe", desc = "Design: Determined Heliotrope" },
    [256710] = { category = "recipe", desc = "Design: Enduring Heliotrope" },
    [256712] = { category = "recipe", desc = "Design: Cognitive Heliotrope" },
    [256719] = { category = "recipe", desc = "Design: Thalassian Competitor's Amulet" },

    -- Leatherworking - Leather (8)
    [256626] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Leather Boots" },
    [256627] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Leather Chestpiece" },
    [256628] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Leather Gloves" },
    [256629] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Leather Trousers" },
    [256630] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Leather Shoulderpads" },
    [256631] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Leather Belt" },
    [256632] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Leather Mask" },
    [256635] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Leather Wristwraps" },

    -- Leatherworking - Mail (8)
    [256633] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Chain Stompers" },
    [256634] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Chain Tunic" },
    [256641] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Chain Leggings" },
    [256643] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Chain Grips" },
    [256644] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Chain Epaulets" },
    [256646] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Chain Cowl" },
    [256649] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Chain Girdle" },
    [256654] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Chain Cuffs" },

    -- Tailoring (9)
    [256880] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Bands" },
    [256884] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Sash" },
    [256885] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Tunic" },
    [256886] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Treads" },
    [256887] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Gloves" },
    [256888] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Hood" },
    [256889] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Leggings" },
    [256890] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Shoulderpads" },
    [256891] = { category = "recipe", desc = "Pattern: Thalassian Competitor's Cloth Cloak" },

    -- ========== RAW CRAFTING MATERIALS (Midnight T1 & T2 only) ==========

    -- Mining - Ores
    [237359] = { category = "craft_mat", desc = "Refulgent Copper Ore (T1)" },
    [237361] = { category = "craft_mat", desc = "Refulgent Copper Ore (T2)" },
    [237362] = { category = "craft_mat", desc = "Umbral Tin Ore (T1)" },
    [237363] = { category = "craft_mat", desc = "Umbral Tin Ore (T2)" },
    [237364] = { category = "craft_mat", desc = "Brilliant Silver Ore (T1)" },
    [237365] = { category = "craft_mat", desc = "Brilliant Silver Ore (T2)" },
    [237366] = { category = "craft_mat", desc = "Dazzling Thorium" },

    -- Mining - Motes (no quality tiers)
    [236949] = { category = "craft_mat", desc = "Mote of Light" },
    [236950] = { category = "craft_mat", desc = "Mote of Primal Energy" },
    [236951] = { category = "craft_mat", desc = "Mote of Wild Magic" },
    [236952] = { category = "craft_mat", desc = "Mote of Pure Void" },

    -- Herbalism
    [236761] = { category = "craft_mat", desc = "Tranquility Bloom (T1)" },
    [236767] = { category = "craft_mat", desc = "Tranquility Bloom (T2)" },
    [236770] = { category = "craft_mat", desc = "Sanguithorn (T1)" },
    [236771] = { category = "craft_mat", desc = "Sanguithorn (T2)" },
    [236774] = { category = "craft_mat", desc = "Azeroot (T1)" },
    [236775] = { category = "craft_mat", desc = "Azeroot (T2)" },
    [236776] = { category = "craft_mat", desc = "Argentleaf (T1)" },
    [236777] = { category = "craft_mat", desc = "Argentleaf (T2)" },
    [236778] = { category = "craft_mat", desc = "Mana Lily (T1)" },
    [236779] = { category = "craft_mat", desc = "Mana Lily (T2)" },
    [236780] = { category = "craft_mat", desc = "Nocturnal Lotus" },

    -- Skinning
    [238511] = { category = "craft_mat", desc = "Void-Tempered Leather (T1)" },
    [238512] = { category = "craft_mat", desc = "Void-Tempered Leather (T2)" },
    [238513] = { category = "craft_mat", desc = "Void-Tempered Scales (T1)" },
    [238514] = { category = "craft_mat", desc = "Void-Tempered Scales (T2)" },
    [238518] = { category = "craft_mat", desc = "Void-Tempered Hide (T1)" },
    [238519] = { category = "craft_mat", desc = "Void-Tempered Hide (T2)" },
    [238520] = { category = "craft_mat", desc = "Void-Tempered Plating (T1)" },
    [238521] = { category = "craft_mat", desc = "Void-Tempered Plating (T2)" },
    [238522] = { category = "craft_mat", desc = "Peerless Plumage" },
    [238523] = { category = "craft_mat", desc = "Carving Canine" },
    [238525] = { category = "craft_mat", desc = "Fantastic Fur" },

    -- Cloth
    [236963] = { category = "craft_mat", desc = "Bright Linen (T1)" },
    [236965] = { category = "craft_mat", desc = "Bright Linen (T2)" },

    -- Enchanting - Disenchanting materials
    [243599] = { category = "enchant_mat", desc = "Eversinging Dust (T1)" },
    [243600] = { category = "enchant_mat", desc = "Eversinging Dust (T2)" },
    [243602] = { category = "enchant_mat", desc = "Radiant Shard (T1)" },
    [243603] = { category = "enchant_mat", desc = "Radiant Shard (T2)" },
    [243605] = { category = "enchant_mat", desc = "Dawn Crystal (T1)" },
    [243606] = { category = "enchant_mat", desc = "Dawn Crystal (T2)" },
}

-- Note: Dawncrests (Midnight upgrade system) are CURRENCIES not items.
-- Enchanting mats from DE'ing PVP gear are detected dynamically via CheckLootedItem.
-- BoE gear drops are also detected dynamically.

function PVPItems:IsSoulbound(itemID)
    if not itemID then return true end
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(itemID)
    return bindType == BIND_ON_PICKUP
end

function PVPItems:IsBankable(itemID)
    if not itemID then return false end
    -- Items in our verified list are ALWAYS bankable (we already confirmed tradeable)
    if self.items[itemID] then return true end
    -- Custom officer-added items are trusted too
    local guildData = GF.Settings:GetGuildData()
    if guildData and guildData.guildSettings.pvpItemIDs and guildData.guildSettings.pvpItemIDs[itemID] then
        return true
    end
    -- For unknown items, check soulbound
    if self:IsSoulbound(itemID) then return false end
    return false
end

--- Smart check: catches known items + BoE gear + valuable reagents
function PVPItems:CheckLootedItem(itemID, itemLink)
    if not itemID then return false, nil end

    -- Known list — skip soulbound check, we verified these
    if self.items[itemID] then
        return true, self.items[itemID].desc
    end

    -- Custom officer-added items — trusted
    local guildData = GF.Settings:GetGuildData()
    if guildData and guildData.guildSettings.pvpItemIDs and guildData.guildSettings.pvpItemIDs[itemID] then
        return true, "Custom tracked item"
    end

    -- Only flag items explicitly in our curated list or added by officers
    -- No auto-detection of random BoE gear or reagents — too noisy
    return false, nil
end

function PVPItems:GetCategory(itemID)
    if not itemID then return nil end
    local entry = self.items[itemID]
    return entry and entry.category or nil
end

function PVPItems:AddCustomItem(itemID, category)
    if self:IsSoulbound(itemID) then
        GF.ChatNotify:Warning("Cannot add soulbound item.")
        return false
    end
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return false end
    if not guildData.guildSettings.pvpItemIDs then guildData.guildSettings.pvpItemIDs = {} end
    guildData.guildSettings.pvpItemIDs[itemID] = {
        category = category or "misc",
        addedBy = GF.Utils:GetPlayerFullName(),
        addedAt = GF.Utils:GetTime(),
    }
    return true
end

function PVPItems:RemoveCustomItem(itemID)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.guildSettings.pvpItemIDs then return false end
    guildData.guildSettings.pvpItemIDs[itemID] = nil
    return true
end

function PVPItems:GetAllItemIDs()
    local ids = {}
    for id in pairs(self.items) do ids[#ids + 1] = id end
    local guildData = GF.Settings:GetGuildData()
    if guildData and guildData.guildSettings.pvpItemIDs then
        for id in pairs(guildData.guildSettings.pvpItemIDs) do ids[#ids + 1] = id end
    end
    return ids
end
