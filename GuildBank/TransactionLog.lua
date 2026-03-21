------------------------------------------------------------------------
-- Vault of Truths - GuildBank/TransactionLog.lua
-- Poll and persist guild bank transaction log (API limited to 25 entries)
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.TransactionLog = {}
local TLog = GF.TransactionLog
GF:RegisterModule("TransactionLog", TLog)

-- Transaction type mapping from API constants
-- Modern WoW may return strings directly; legacy returned numbers
local TRANSACTION_TYPES = {
    [1] = "deposit",
    [2] = "withdraw",
    [3] = "move",
    [4] = "deposit_money",
    [5] = "withdraw_money",
    [6] = "repair_money",
    [7] = "move_money",
    [8] = "buy_tab",
    [9] = "update_tab",
    -- String keys for modern API
    ["deposit"] = "deposit",
    ["withdraw"] = "withdraw",
    ["move"] = "move",
}

--- Initialize transaction log hooks
function TLog:Init()
    -- Query transaction log when guild bank opens
    GF.Events:On("GF_BANK_SCAN_COMPLETE", function()
        TLog:PollAllTabs()
    end)

    -- Process log data when it arrives (may not exist in all WoW versions)
    pcall(function()
        GF.Events:Register("GUILDBANKLOG_UPDATE", function()
            TLog:ProcessLogUpdate()
        end)
    end)

    -- Re-poll when guild bank contents change
    pcall(function()
        GF.Events:Register("GUILDBANKBAGSLOTS_CHANGED", function()
            C_Timer.After(0.5, function()
                TLog:PollAllTabs()
            end)
        end)
    end)
end

--- Query transaction logs for all viewable tabs
function TLog:PollAllTabs()
    local numTabs = GetNumGuildBankTabs()
    self._pendingLogTabs = {}

    for i = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(i)
        if isViewable then
            self._pendingLogTabs[#self._pendingLogTabs + 1] = i
        end
    end

    -- Also query the money log (tab index = MAX_GUILDBANK_TABS + 1)
    self:QueryNextLogTab()
end

--- Query the next log tab
function TLog:QueryNextLogTab()
    if not self._pendingLogTabs or #self._pendingLogTabs == 0 then
        if GF.debug then
            print("|cFF33AAFF[Vault of Truths]|r Transaction log polling complete.")
        end
        return
    end

    local tab = table.remove(self._pendingLogTabs, 1)
    self._currentLogTab = tab
    QueryGuildBankLog(tab)
end

--- Process received log data for the current tab
function TLog:ProcessLogUpdate()
    local tab = self._currentLogTab
    if not tab then return end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    if not guildData.transactionLog then
        guildData.transactionLog = {}
    end

    local numTransactions = GetNumGuildBankTransactions(tab)
    local newEntries = 0

    for i = 1, numTransactions do
        local transType, playerName, itemLink, count, moveTab1, moveTab2, year, month, day, hour = GetGuildBankTransaction(tab, i)

        if transType and playerName then
            local itemID = itemLink and GF.Utils:GetItemIDFromLink(itemLink) or nil

            -- Approximate timestamp from "X time ago" fields
            local approxTimestamp = self:ApproximateTimestamp(year, month, day, hour)

            -- Generate stable dedup hash: snap the approximate timestamp to
            -- the nearest calendar day so the hash doesn't drift as time passes.
            -- Two polls of the same transaction hours apart produce the same hash.
            local stableDay = math.floor(approxTimestamp / 86400)
            local hashInput = tostring(transType) .. playerName .. tostring(itemID or "money") ..
                tostring(count or 0) .. tostring(tab) .. tostring(stableDay)
            local hash = self:SimpleHash(hashInput)

            -- Check for duplicates
            if not self:HasTransaction(guildData.transactionLog, hash) then
                local entry = {
                    tabIndex = tab,
                    type = TRANSACTION_TYPES[transType] or "unknown",
                    player = playerName,
                    itemID = itemID,
                    itemLink = itemLink,
                    quantity = count or 0,
                    timestamp = approxTimestamp,
                    hash = hash,
                }

                -- Insert newest first
                table.insert(guildData.transactionLog, 1, entry)
                newEntries = newEntries + 1

                -- Fire event for new transactions (useful for ledger wiring)
                GF.Events:Fire("GF_BANK_TRANSACTION", entry)
            end
        end
    end

    if GF.debug and newEntries > 0 then
        print("|cFF33AAFF[Vault of Truths]|r Tab " .. tab .. ": " .. newEntries .. " new transactions logged.")
    end

    -- Trim log to prevent unbounded growth (keep last 2000 entries)
    while #guildData.transactionLog > 2000 do
        table.remove(guildData.transactionLog)
    end

    -- Query next tab
    self:QueryNextLogTab()
end

--- Check if a transaction hash already exists in the log
---@param log table Transaction log array
---@param hash string Hash to check
---@return boolean
function TLog:HasTransaction(log, hash)
    for i = 1, #log do
        if log[i].hash == hash then
            return true
        end
    end
    return false
end

--- Approximate a timestamp from the API's relative time fields
---@param year number|nil
---@param month number|nil
---@param day number|nil
---@param hour number|nil
---@return number Unix timestamp (approximate)
function TLog:ApproximateTimestamp(year, month, day, hour)
    local offset = 0
    if year and year > 0 then offset = offset + year * 31536000 end
    if month and month > 0 then offset = offset + month * 2592000 end
    if day and day > 0 then offset = offset + day * 86400 end
    if hour and hour > 0 then offset = offset + hour * 3600 end
    return time() - offset
end

--- Simple hash function for dedup (not cryptographic)
---@param str string
---@return string 8-char hex hash
function TLog:SimpleHash(str)
    local hash = 5381
    for i = 1, #str do
        hash = bit.bxor(hash * 33, string.byte(str, i))
        hash = bit.band(hash, 0xFFFFFFFF)
    end
    return string.format("%08x", hash)
end

--- Get recent transactions for a specific player
---@param playerName string
---@param limit number|nil Max entries to return (default 25)
---@return table Array of transaction entries
function TLog:GetPlayerTransactions(playerName, limit)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.transactionLog then return {} end

    limit = limit or 25
    local results = {}
    for _, entry in ipairs(guildData.transactionLog) do
        if entry.player == playerName then
            results[#results + 1] = entry
            if #results >= limit then break end
        end
    end
    return results
end

--- Get recent deposits (for ledger cross-referencing)
---@param limit number|nil
---@return table
function TLog:GetRecentDeposits(limit)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.transactionLog then return {} end

    limit = limit or 50
    local results = {}
    for _, entry in ipairs(guildData.transactionLog) do
        if entry.type == "deposit" then
            results[#results + 1] = entry
            if #results >= limit then break end
        end
    end
    return results
end
