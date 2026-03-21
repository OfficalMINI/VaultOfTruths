------------------------------------------------------------------------
-- Vault of Truths - CraftingOrders/MatPricing.lua
-- Material cost aggregation for recipes using TSM pricing
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.MatPricing = {}
local MP = GF.MatPricing

--- Calculate the total material cost for a list of materials
---@param mats table Array of { itemID, quantity }
---@return number totalCost Total in copper
---@return table details Array of { itemID, quantity, unitCost, totalCost, available }
---@return number missingCount Number of items with no price data
function MP:CalculateCost(mats)
    local totalCost = 0
    local details = {}
    local missing = 0

    for _, mat in ipairs(mats) do
        local unitCost, source = GF.TSM:GetBestPrice(mat.itemID)
        local matTotal = 0

        if unitCost then
            matTotal = unitCost * mat.quantity
            totalCost = totalCost + matTotal
        else
            missing = missing + 1
        end

        details[#details + 1] = {
            itemID = mat.itemID,
            quantity = mat.quantity,
            unitCost = unitCost or 0,
            totalCost = matTotal,
            priceSource = source or "unknown",
            available = unitCost ~= nil,
        }
    end

    return totalCost, details, missing
end

--- Check if all materials are available in the guild bank
---@param mats table Array of { itemID, quantity }
---@return boolean allAvailable
---@return table availability { [itemID] = { needed, inBank, shortfall } }
function MP:CheckBankAvailability(mats)
    local snapshot = GF.Scanner:GetSnapshot()
    if not snapshot or not snapshot.tabs then
        return false, {}
    end

    -- Build inventory from snapshot
    local bankInventory = {} -- [itemID] = totalQuantity
    for _, tabData in pairs(snapshot.tabs) do
        if tabData.items then
            for _, item in pairs(tabData.items) do
                bankInventory[item.itemID] = (bankInventory[item.itemID] or 0) + item.quantity
            end
        end
    end

    local allAvailable = true
    local availability = {}

    for _, mat in ipairs(mats) do
        local inBank = bankInventory[mat.itemID] or 0
        local shortfall = math.max(0, mat.quantity - inBank)
        availability[mat.itemID] = {
            needed = mat.quantity,
            inBank = inBank,
            shortfall = shortfall,
        }
        if shortfall > 0 then
            allAvailable = false
        end
    end

    return allAvailable, availability
end

--- Format a material list with prices for display
---@param mats table Array from CalculateCost details
---@return string Formatted multi-line string
function MP:FormatMaterialList(mats)
    local lines = {}
    for _, mat in ipairs(mats) do
        local status = mat.available and GF.Utils:FormatMoney(mat.totalCost) or "|cFFFF0000No Price|r"
        lines[#lines + 1] = string.format("  x%d Item:%d — %s",
            mat.quantity, mat.itemID, status)
    end
    return table.concat(lines, "\n")
end
