------------------------------------------------------------------------
-- Vault of Truths - UI/Widgets/Tooltip.lua
-- Hooks into GameTooltip to show VoT info on ALL item tooltips
-- Shows: bankable status, contribution value, profit estimate, crafts
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
if not GF.UI.Widgets then GF.UI.Widgets = {} end

local Tooltip = {}
GF.UI.Widgets.Tooltip = Tooltip
GF:RegisterModule("TooltipHook", Tooltip)

local VOT_COLOR = { r = 0.2, g = 0.67, b = 1 }
local GOLD_COLOR = { r = 1, g = 0.82, b = 0 }
local GREEN_COLOR = { r = 0, g = 1, b = 0 }
local GREY_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

function Tooltip:Init()
    -- Hook into the game tooltip system
    -- TooltipDataProcessor is the modern (Dragonflight+) way
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip then return end
            local itemID = data and data.id
            if itemID then
                Tooltip:AddVoTLines(tooltip, itemID)
            end
        end)
    else
        -- Fallback: hook OnTooltipSetItem
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            local _, link = tooltip:GetItem()
            if link then
                local itemID = GF.Utils:GetItemIDFromLink(link)
                if itemID then
                    Tooltip:AddVoTLines(tooltip, itemID)
                end
            end
        end)
    end
end

--- Add Vault of Truths lines to an item tooltip
---@param tooltip GameTooltip
---@param itemID number
function Tooltip:AddVoTLines(tooltip, itemID)
    if not itemID then return end

    -- Check if bankable
    local isBankable, reason = false, nil
    if GF.PVPItems.items[itemID] then
        isBankable = true
        reason = GF.PVPItems.items[itemID].desc or "Known PVP item"
    elseif GF.PVPItems.CheckLootedItem then
        isBankable, reason = GF.PVPItems:CheckLootedItem(itemID)
    end

    -- Check soulbound status
    local isSoulbound = GF.PVPItems:IsSoulbound(itemID)

    -- Only show VoT section if the item is relevant
    if not isBankable and not GF.PVPItems.items[itemID] then return end

    -- Separator
    tooltip:AddLine(" ")
    tooltip:AddLine("|cFF33AAFF--- Vault of Truths ---|r")

    -- Bankable status
    if isBankable and not isSoulbound then
        tooltip:AddLine("|cFF00FF00BANKABLE|r — Deposit to guild bank!", GREEN_COLOR.r, GREEN_COLOR.g, GREEN_COLOR.b)
    elseif isSoulbound then
        tooltip:AddLine("|cFFFF4444Soulbound|r — DE for bankable mats", 1, 0.3, 0.3)
    end

    -- Category
    local category = GF.PVPItems:GetCategory(itemID)
    if category then
        local categoryNames = {
            crest = "Upgrade Crest",
            reagent = "Crafting Reagent",
            pvp_heraldry = "PVP Heraldry (Crafting Reagent)",
            pvp_gem = "PVP Gem (Jewelcrafting)",
            enchant_mat = "Enchanting Material",
            recipe = "Recipe/Formula",
            currency_item = "Currency Item",
        }
        local catName = categoryNames[category] or category
        tooltip:AddDoubleLine("Type:", catName, GREY_COLOR.r, GREY_COLOR.g, GREY_COLOR.b, 1, 1, 1)
    end

    -- TSM value (contribution points if deposited)
    if GF.TSM and GF.TSM:IsAvailable() then
        local value, source = GF.TSM:GetBestPrice(itemID)
        if value then
            tooltip:AddDoubleLine("Guild Value:", GF.Utils:FormatMoney(value), GREY_COLOR.r, GREY_COLOR.g, GREY_COLOR.b, GOLD_COLOR.r, GOLD_COLOR.g, GOLD_COLOR.b)

            -- Estimate contribution reward
            local guildData = GF.Settings:GetGuildData()
            if guildData then
                local split = guildData.guildSettings.profitSplit or GF.DEFAULT_PROFIT_SPLIT
                local contributorPct = split.contributors or 50

                -- Estimate: if this item sells at TSM value, your cut would be...
                -- Simplified: assume 5% AH cut, your share = value * 0.95 * (contributorPct/100) * yourShare
                local afterAHCut = math.floor(value * 0.95)
                local contributorPool = math.floor(afterAHCut * contributorPct / 100)

                tooltip:AddDoubleLine("Est. Contributor Pool:", GF.Utils:FormatMoney(contributorPool) .. " (" .. contributorPct .. "%)",
                    GREY_COLOR.r, GREY_COLOR.g, GREY_COLOR.b, GREEN_COLOR.r, GREEN_COLOR.g, GREEN_COLOR.b)
            end
        else
            tooltip:AddDoubleLine("Guild Value:", "N/A (no TSM data)", GREY_COLOR.r, GREY_COLOR.g, GREY_COLOR.b, 0.6, 0.6, 0.6)
        end
    end

    -- Possible crafts this item is used in (if it's a reagent)
    if category == "pvp_heraldry" then
        tooltip:AddLine(" ")
        tooltip:AddLine("Used in: Crafted PVP gear (all armor types)", 0.7, 0.7, 0.7)
        tooltip:AddLine("Apply via WoW crafting order as optional reagent", 0.5, 0.5, 0.5)
    elseif category == "crest" then
        tooltip:AddLine(" ")
        tooltip:AddLine("Used in: Gear upgrades (item level increase)", 0.7, 0.7, 0.7)
    elseif category == "reagent" and itemID == 253307 then -- Infused Heliotrope
        tooltip:AddLine(" ")
        tooltip:AddLine("Used in: Heliotrope PVP Gems (JC)", 0.7, 0.7, 0.7)
        tooltip:AddLine("Determined / Cognitive / Enduring Heliotrope", 0.5, 0.5, 0.5)
    elseif category == "enchant_mat" then
        tooltip:AddLine(" ")
        tooltip:AddLine("Used in: Weapon & armor enchants", 0.7, 0.7, 0.7)
        tooltip:AddLine("Enchanted Crests, combat enchants", 0.5, 0.5, 0.5)
    elseif category == "pvp_gem" then
        tooltip:AddLine(" ")
        tooltip:AddLine("Socket into gear for PVP combat effects", 0.7, 0.7, 0.7)
    elseif category == "recipe" then
        tooltip:AddLine(" ")
        tooltip:AddLine("Learn this recipe to craft for the guild!", 0.7, 0.7, 0.7)
    end

    tooltip:Show() -- Refresh tooltip size
end

--- Attach a simple text tooltip to a custom frame
function Tooltip:Attach(frame, title, lines, anchor)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(title, VOT_COLOR.r, VOT_COLOR.g, VOT_COLOR.b)
        if lines then
            for _, line in ipairs(lines) do
                if type(line) == "table" then
                    GameTooltip:AddDoubleLine(line[1], line[2],
                        line[3] or 1, line[4] or 1, line[5] or 1,
                        line[6] or 1, line[7] or 0.82, line[8] or 0)
                else
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            end
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
