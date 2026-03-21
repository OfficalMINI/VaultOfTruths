------------------------------------------------------------------------
-- Vault of Truths - TSMBridge/TSMBridge.lua
-- Interface with TradeSkillMaster for item pricing
-- Soft dependency: addon works without TSM, prices show "N/A"
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.TSM = {}
local TSM = GF.TSM
GF:RegisterModule("TSMBridge", TSM)

-- Price cache: [priceSource:itemID] = { value, expiry }
local priceCache = {}
local CACHE_TTL = 300 -- 5 minutes

--- Initialize TSM bridge — called after ADDON_LOADED
function TSM:Init()
    -- TSM4+ exposes TSM_API global after it loads
    if TSM_API then
        self.available = true
        self.apiVersion = 4
        -- Clear cache on init in case price source changed
        wipe(priceCache)
        if GF.debug then
            print("|cFF33AAFF[Vault of Truths]|r TSM_API detected (v4+)")
        end
    else
        self.available = false
        print("|cFF33AAFF[Vault of Truths]|r |cFFFFAA00TradeSkillMaster not detected.|r Prices show as 'Not Synced' until received from a guild member with TSM.")
        print("|cFF33AAFF[Vault of Truths]|r Install TSM for accurate local pricing: |cFF00AAFFhttps://www.tradeskillmaster.com|r")
    end
end

--- Check if TSM is available
---@return boolean
function TSM:IsAvailable()
    return self.available == true
end

--- Get the value of an item using TSM pricing
---@param itemID number Item ID
---@param priceSource string|nil Price source string (default: guild setting or "dbmarket")
---@return number|nil value Value in copper
---@return string|nil error Error message if no price
function TSM:GetItemValue(itemID, priceSource)
    if not self.available then
        return nil, "TSM not loaded"
    end

    if not itemID then
        return nil, "No item ID"
    end

    -- Determine price source
    -- TSM source names: DBMinBuyout (live AH min), DBMarket (historical)
    -- first() returns the first valid (non-zero) value
    local savedSource = GF.Settings:GetGuild("priceSource")

    -- Fix legacy price strings that use wrong case
    if savedSource and (savedSource == "first(minbuyout, dbmarket)" or savedSource == "dbmarket") then
        savedSource = "first(DBMinBuyout, DBMarket)"
        GF.Settings:SetGuild("priceSource", savedSource)
    end

    priceSource = priceSource or savedSource or "first(DBMinBuyout, DBMarket)"

    -- Check cache
    local cacheKey = priceSource .. ":" .. itemID
    local cached = priceCache[cacheKey]
    if cached and cached.expiry > time() then
        return cached.value, nil
    end

    -- Query TSM
    local itemString = "i:" .. tostring(itemID)
    local ok, value = pcall(TSM_API.GetCustomPriceValue, priceSource, itemString)

    if not ok then
        return nil, "TSM API error"
    end

    if value and value > 0 then
        -- Cache the result
        priceCache[cacheKey] = { value = value, expiry = time() + CACHE_TTL }
        return value, nil
    end

    return nil, "No TSM price for item " .. itemID
end

--- Get values for multiple items at once
---@param itemIDs table Array of item IDs
---@param priceSource string|nil
---@return table results { [itemID] = value } (missing items not included)
function TSM:GetBulkValues(itemIDs, priceSource)
    local results = {}
    for _, itemID in ipairs(itemIDs) do
        local value = self:GetItemValue(itemID, priceSource)
        if value then
            results[itemID] = value
        end
    end
    return results
end

--- Calculate the total value of a set of items
---@param items table Array of { itemID, quantity }
---@param priceSource string|nil
---@return number totalValue Total in copper
---@return number valuedCount Number of items with valid prices
---@return number totalCount Total number of items
function TSM:CalculateTotalValue(items, priceSource)
    local total = 0
    local valued = 0
    local count = #items

    for _, item in ipairs(items) do
        local unitValue = self:GetItemValue(item.itemID, priceSource)
        if unitValue then
            total = total + (unitValue * (item.quantity or 1))
            valued = valued + 1
        end
    end

    return total, valued, count
end

--- Get vendor sell price as fallback (uses GetItemInfo)
---@param itemID number
---@return number|nil value Vendor price in copper
function TSM:GetVendorPrice(itemID)
    local _, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemID)
    if sellPrice and sellPrice > 0 then
        return sellPrice
    end
    return nil
end

--- Get the best available price for an item (TSM first, then vendor)
---@param itemID number
---@return number|nil value
---@return string source "tsm" or "vendor" or nil
function TSM:GetBestPrice(itemID)
    local tsmValue = self:GetItemValue(itemID)
    if tsmValue then
        return tsmValue, "tsm"
    end

    local vendorValue = self:GetVendorPrice(itemID)
    if vendorValue then
        return vendorValue, "vendor"
    end

    return nil, nil
end

--- Clear the price cache (useful after TSM data update)
function TSM:ClearCache()
    wipe(priceCache)
    if GF.debug then
        print("|cFF33AAFF[Vault of Truths]|r TSM price cache cleared.")
    end
end
