------------------------------------------------------------------------
-- Vault of Truths - CraftingOrders/FeeCalculator.lua
-- Crafting order fee calculation using TSM prices + configurable markup
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.FeeCalculator = {}
local FC = GF.FeeCalculator

--- Calculate the fee for a crafting order
---@param matCost number Total material cost in copper
---@param customPercent number|nil Override fee percentage
---@return number fee Fee in copper
function FC:Calculate(matCost, customPercent)
    local feePercent = customPercent or GF.Settings:GetGuild("feePercent") or 10
    return math.floor(matCost * feePercent / 100)
end

--- Calculate the total cost for an order (mats + fee)
---@param matCost number Material cost in copper
---@param supplyMode string "requester" or "guild"
---@return number totalCost
---@return number fee
---@return number matCharge (0 if requester supplies)
function FC:CalculateTotal(matCost, supplyMode)
    local fee = self:Calculate(matCost)

    if supplyMode == "requester" then
        -- Requester supplies mats, only pays the crafting fee
        return fee, fee, 0
    else
        -- Guild supplies mats: mat cost + fee
        return matCost + fee, fee, matCost
    end
end

--- Format a cost breakdown as a string
---@param matCost number
---@param supplyMode string
---@return string
function FC:FormatBreakdown(matCost, supplyMode)
    local total, fee, matCharge = self:CalculateTotal(matCost, supplyMode)
    local feePercent = GF.Settings:GetGuild("feePercent") or 10

    local parts = {}
    if matCharge > 0 then
        parts[#parts + 1] = "Mats: " .. GF.Utils:FormatMoney(matCharge)
    end
    parts[#parts + 1] = "Fee (" .. feePercent .. "%): " .. GF.Utils:FormatMoney(fee)
    parts[#parts + 1] = "Total: " .. GF.Utils:FormatMoney(total)

    return table.concat(parts, " | ")
end
