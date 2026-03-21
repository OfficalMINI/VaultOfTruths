------------------------------------------------------------------------
-- Vault of Truths - Ledger/Snapshot.lua
-- Periodic ledger snapshots for integrity and period tracking
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Snapshot = {}
local Snapshot = GF.Snapshot
GF:RegisterModule("Snapshot", Snapshot)

function Snapshot:Init()
    -- Check for period rollover on login
    GF.Events:On("GF_PLAYER_LOGIN", function()
        Snapshot:CheckPeriodRollover()
    end)
end

--- Take a snapshot of current balances
---@param reason string "period_end" or "manual"
---@return table|nil snapshot
function Snapshot:Take(reason)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end

    local snapshot = {
        timestamp = GF.Utils:GetTime(),
        reason = reason,
        period = self:GetCurrentPeriodKey(),
        memberBalances = {},
        summary = GF.Payouts:GetSummary(),
        ledgerCount = #guildData.ledger.entries,
    }

    -- Capture each member's state
    for player, record in pairs(guildData.payouts) do
        snapshot.memberBalances[player] = {
            totalContributed = record.totalContributed,
            totalPaidOut = record.totalPaidOut,
            currentBalance = record.totalContributed + (record.crafterEarnings or 0) + (record.auctioneerEarnings or 0) - record.totalPaidOut,
            crafterEarnings = record.crafterEarnings or 0,
            auctioneerEarnings = record.auctioneerEarnings or 0,
            share = GF.Ledger:GetContributionShare(player),
            tier = GF.Roles:GetTier(player),
        }
    end

    -- Store snapshot
    if not guildData.snapshots then
        guildData.snapshots = {}
    end
    table.insert(guildData.snapshots, 1, snapshot)

    -- Keep max 52 snapshots (1 year of weekly)
    while #guildData.snapshots > 52 do
        table.remove(guildData.snapshots)
    end

    GF.Events:Fire("GF_SNAPSHOT_TAKEN", snapshot)

    if GF.debug then
        print("|cFF33AAFF[Vault of Truths]|r Snapshot taken: " .. reason .. " — Period: " .. snapshot.period)
    end

    return snapshot
end

--- Get the current period key (e.g. "2026-W12" or "2026-03")
---@return string
function Snapshot:GetCurrentPeriodKey()
    local guildData = GF.Settings:GetGuildData()
    local period = guildData and guildData.guildSettings.trackingPeriod or "weekly"

    if period == "weekly" then
        local t = date("*t")
        local weekNum = math.ceil((t.yday + (7 - t.wday)) / 7)
        return string.format("%d-W%02d", t.year, weekNum)
    else
        return date("%Y-%m")
    end
end

--- Check if the tracking period has rolled over, and snapshot if so
function Snapshot:CheckPeriodRollover()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    local currentPeriod = self:GetCurrentPeriodKey()
    local lastPeriod = guildData.lastPeriod

    if lastPeriod and lastPeriod ~= currentPeriod then
        -- Period rolled over — take end-of-period snapshot
        print("|cFF33AAFF[Vault of Truths]|r New tracking period: " .. currentPeriod .. " (previous: " .. lastPeriod .. ")")
        self:Take("period_end")
    end

    guildData.lastPeriod = currentPeriod
end

--- Get all snapshots
---@param limit number|nil
---@return table Array of snapshots
function Snapshot:GetAll(limit)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.snapshots then return {} end

    if limit then
        local results = {}
        for i = 1, math.min(limit, #guildData.snapshots) do
            results[i] = guildData.snapshots[i]
        end
        return results
    end

    return guildData.snapshots
end

--- Get the most recent snapshot
---@return table|nil
function Snapshot:GetLatest()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.snapshots or #guildData.snapshots == 0 then return nil end
    return guildData.snapshots[1]
end
