------------------------------------------------------------------------
-- Vault of Truths - Sync/Sender.lua
-- Outbound message queue with throttling
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Sender = {}
local Sender = GF.Sender
GF:RegisterModule("Sender", Sender)

local sendQueue = {}
local isSending = false
local THROTTLE_INTERVAL = 1.0 -- 1 second between messages (WoW rate limit)
local BURST_LIMIT = 10 -- Initial burst allowance
local burstRemaining = BURST_LIMIT

-- ACK tracking for critical messages
local pendingAcks = {} -- [msgID] = { msgType, data, channel, target, sentAt, retries }
local MAX_RETRIES = 3
local ACK_TIMEOUT = 10 -- seconds

-- Critical message types that need ACK confirmation
local ACK_MSG_TYPES = {
    [GF.Protocol.MSG.LSYNC_DATA] = true,
    [GF.Protocol.MSG.ORDER_NEW] = true,
    [GF.Protocol.MSG.ORDER_UPD] = true,
    [GF.Protocol.MSG.PAYOUT_REC] = true,
    [GF.Protocol.MSG.SETTINGS] = true,
    [GF.Protocol.MSG.ROLE_UPD] = true,
}

function Sender:Init()
    -- Reset burst allowance periodically
    C_Timer.NewTicker(10, function()
        burstRemaining = math.min(burstRemaining + 5, BURST_LIMIT)
    end)

    -- ACK retry ticker — check every 5s for unacknowledged critical messages
    C_Timer.NewTicker(5, function()
        local now = time()
        for msgID, entry in pairs(pendingAcks) do
            if now - entry.sentAt > ACK_TIMEOUT then
                if entry.retries < MAX_RETRIES then
                    entry.retries = entry.retries + 1
                    entry.sentAt = now
                    -- Re-enqueue with same msgID
                    Sender:_EnqueueRaw(entry.msgType, entry.encoded, entry.channel, entry.target, msgID)
                    if GF.debug then
                        GF.ChatNotify:Debug("Retry #" .. entry.retries .. " for " .. entry.msgType .. " (" .. msgID .. ")")
                    end
                else
                    GF.ChatNotify:Warning("Sync: " .. entry.msgType .. " not acknowledged after " .. MAX_RETRIES .. " retries.")
                    pendingAcks[msgID] = nil
                end
            end
        end
    end)

    -- On login, announce version and request sync
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(5, function() -- Delay to let guild roster load
            Sender:AnnounceVersion()
            Sender:RequestSync()
            -- Full state sync (orders, roles, settings) after ledger sync
            C_Timer.After(3, function()
                Sender:RequestFullSync()
            end)
        end)

        -- Adaptive heartbeat — faster after errors, slower when stable
        local heartbeatInterval = 300
        local syncErrorCount = 0

        GF.Events:On("GF_SYNC_CHUNK_LOST", function()
            syncErrorCount = syncErrorCount + 1
            heartbeatInterval = 60 -- Fast recovery mode
        end)

        GF.Events:On("GF_SYNC_RECEIVED", function()
            if syncErrorCount > 0 then
                syncErrorCount = syncErrorCount - 1
                if syncErrorCount == 0 then
                    heartbeatInterval = 300 -- Back to normal
                end
            end
        end)

        local function DoHeartbeat()
            if IsInGuild() then
                Sender:RequestSync()
            end
            C_Timer.After(heartbeatInterval, DoHeartbeat)
        end
        C_Timer.After(heartbeatInterval, DoHeartbeat)

        -- Resync when guild roster changes (member comes online)
        GF.Events:Register("GUILD_ROSTER_UPDATE", function()
            if IsInGuild() then
                Sender:AnnounceVersion()
            end
        end)
    end)
end

--- Send a message to the guild channel
---@param msgType string One of GF.Protocol.MSG
---@param data any Data to serialize and send
function Sender:Send(msgType, data)
    self:_Enqueue(msgType, data, "GUILD", nil)
end

--- Send a message to a specific player via whisper
---@param msgType string One of GF.Protocol.MSG
---@param data any Data to serialize and send
---@param target string Player name to whisper
function Sender:SendTo(msgType, data, target)
    self:_Enqueue(msgType, data, "WHISPER", target)
end

--- Internal: encode and queue a message
---@param msgType string
---@param data any
---@param channel string "GUILD" or "WHISPER"
---@param target string|nil Player name for WHISPER
function Sender:_Enqueue(msgType, data, channel, target)
    if not IsInGuild() and channel == "GUILD" then return end
    if GF.Settings:Get("syncEnabled") == false then return end

    local encoded = GF.Protocol:Encode(data)
    if not encoded then return end

    -- Generate msgID for critical messages (ACK tracking)
    local msgID = nil
    if ACK_MSG_TYPES[msgType] and channel == "WHISPER" then
        msgID = GF.Protocol:GenerateMsgID()
        pendingAcks[msgID] = {
            msgType = msgType,
            encoded = encoded,
            channel = channel,
            target = target,
            sentAt = time(),
            retries = 0,
        }
    end

    local chunks = GF.Protocol:BuildMessage(msgType, encoded, msgID)

    for _, chunk in ipairs(chunks) do
        sendQueue[#sendQueue + 1] = { message = chunk, channel = channel, target = target }
    end

    if not isSending then
        self:ProcessQueue()
    end
end

--- Internal: re-enqueue an already-encoded message (for retries)
function Sender:_EnqueueRaw(msgType, encoded, channel, target, msgID)
    local chunks = GF.Protocol:BuildMessage(msgType, encoded, msgID)
    for _, chunk in ipairs(chunks) do
        sendQueue[#sendQueue + 1] = { message = chunk, channel = channel, target = target }
    end
    if not isSending then
        self:ProcessQueue()
    end
end

--- Process the send queue with throttling
function Sender:ProcessQueue()
    if #sendQueue == 0 then
        isSending = false
        return
    end

    isSending = true
    local entry = table.remove(sendQueue, 1)

    -- Use burst if available, otherwise throttle
    local delay = 0
    if burstRemaining > 0 then
        burstRemaining = burstRemaining - 1
        delay = 0.05 -- Minimal delay during burst
    else
        delay = THROTTLE_INTERVAL
    end

    C_ChatInfo.SendAddonMessage(GF.PREFIX, entry.message, entry.channel, entry.target)

    if GF.debug then
        local dest = entry.channel == "WHISPER" and ("WHISPER:" .. (entry.target or "?")) or entry.channel
        GF.ChatNotify:Debug("Sync sent [" .. dest .. "]: " .. entry.message:sub(1, 50) .. "...")
    end

    C_Timer.After(delay, function()
        Sender:ProcessQueue()
    end)
end

--- Announce our addon version to the guild
function Sender:AnnounceVersion()
    self:Send(GF.Protocol.MSG.VER, {
        version = GF.VERSION,
        protocol = GF.Protocol.PROTOCOL_VERSION,
    })
end

--- Request ledger sync from guild members
function Sender:RequestSync()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    self:Send(GF.Protocol.MSG.LSYNC_REQ, {
        sinceSyncVersion = guildData.ledger.nextSyncVersion - 1,
    })
end

--- Request full state sync (orders, roles, settings) from guild
function Sender:RequestFullSync()
    self:Send(GF.Protocol.MSG.FULL_SYNC_REQ, {
        requestedAt = time(),
    })
end

--- Broadcast a new ledger entry
---@param entry table Ledger entry
function Sender:BroadcastLedgerEntry(entry)
    local data = { entries = { entry } }
    self:Send(GF.Protocol.MSG.LSYNC_DATA, data)
    self:SavePending(GF.Protocol.MSG.LSYNC_DATA, data)
end

--- Broadcast a new crafting order
---@param order table Order data
function Sender:BroadcastNewOrder(order)
    self:Send(GF.Protocol.MSG.ORDER_NEW, order)
    self:SavePending(GF.Protocol.MSG.ORDER_NEW, order)
end

--- Broadcast an order status update
---@param orderID string
---@param status string
---@param updatedBy string
function Sender:BroadcastOrderUpdate(orderID, status, updatedBy)
    local data = {
        orderID = orderID,
        status = status,
        updatedBy = updatedBy,
        timestamp = GF.Utils:GetTime(),
    }
    self:Send(GF.Protocol.MSG.ORDER_UPD, data)
    self:SavePending(GF.Protocol.MSG.ORDER_UPD, data)
end

--- Broadcast a payout record
---@param player string
---@param amount number
---@param method string
function Sender:BroadcastPayout(player, amount, method)
    local data = {
        player = player,
        amount = amount,
        method = method,
        recordedBy = GF.Utils:GetPlayerFullName(),
        timestamp = GF.Utils:GetTime(),
    }
    self:Send(GF.Protocol.MSG.PAYOUT_REC, data)
    self:SavePending(GF.Protocol.MSG.PAYOUT_REC, data)
end

--- Broadcast guild settings update (owner/officer only)
---@param settings table Guild settings table
function Sender:BroadcastSettings(settings)
    self:Send(GF.Protocol.MSG.SETTINGS, settings)
    self:SavePending(GF.Protocol.MSG.SETTINGS, settings)
end

--- Broadcast a role change
---@param player string
---@param roles table
function Sender:BroadcastRoleUpdate(player, roles)
    local data = {
        player = player,
        roles = roles,
        updatedBy = GF.Utils:GetPlayerFullName(),
    }
    self:Send(GF.Protocol.MSG.ROLE_UPD, data)
    self:SavePending(GF.Protocol.MSG.ROLE_UPD, data)
end

--- Reply to a PING (whispered back to the sender)
---@param syncVersion number
---@param target string Player who sent the PING
function Sender:SendPong(syncVersion, target)
    self:SendTo(GF.Protocol.MSG.PONG, {
        syncVersion = syncVersion,
        playerName = GF.Utils:GetPlayerFullName(),
    }, target)
end

--- Confirm receipt of a critical message (called when ACK received)
---@param msgID string
function Sender:ConfirmAck(msgID)
    if pendingAcks[msgID] then
        pendingAcks[msgID] = nil
    end
end

--- Send an ACK back to a sender for a critical message
---@param msgID string
---@param target string Player name to whisper ACK to
function Sender:SendAck(msgID, target)
    self:SendTo(GF.Protocol.MSG.ACK, { msgID = msgID }, target)
end

--- Get queue status
---@return number Pending messages in queue
function Sender:GetQueueSize()
    return #sendQueue
end

------------------------------------------------------------------------
-- Pending changes queue (persists across sessions for offline sync)
------------------------------------------------------------------------

--- Save a broadcast to the pending queue so it can be replayed
--- when a peer comes online after we were alone
---@param msgType string
---@param data table
function Sender:SavePending(msgType, data)
    if not IsInGuild() then return end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    if not guildData._pendingBroadcasts then
        guildData._pendingBroadcasts = {}
    end

    -- Keep max 500 pending items, drop oldest
    if #guildData._pendingBroadcasts >= 500 then
        table.remove(guildData._pendingBroadcasts, 1)
    end

    guildData._pendingBroadcasts[#guildData._pendingBroadcasts + 1] = {
        msgType = msgType,
        data = data,
        savedAt = time(),
    }
end

--- Replay pending broadcasts to a newly online peer
---@param target string Player name to send to
function Sender:ReplayPending(target)
    if not IsInGuild() then return end

    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData._pendingBroadcasts then return end

    local count = #guildData._pendingBroadcasts
    if count == 0 then return end

    if GF.debug then
        GF.ChatNotify:Debug("Replaying " .. count .. " pending changes to " .. target)
    end

    for _, pending in ipairs(guildData._pendingBroadcasts) do
        -- Replay if less than 7 days old
        if time() - pending.savedAt < 604800 then
            self:SendTo(pending.msgType, pending.data, target)
        end
    end
end

--- Clear pending broadcasts (called after successful sync)
--- If syncVersion provided, only clear entries covered by that version
---@param syncVersion number|nil If nil, clears everything
function Sender:ClearPending(syncVersion)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData._pendingBroadcasts then return end

    if not syncVersion then
        guildData._pendingBroadcasts = {}
        return
    end

    -- Only clear entries covered by the received sync version
    local kept = {}
    for _, pending in ipairs(guildData._pendingBroadcasts) do
        local sv = pending.data and pending.data.syncVersion
        if sv and sv > syncVersion then
            -- Ledger entry newer than what peer has — keep
            kept[#kept + 1] = pending
        elseif not sv then
            -- Non-ledger items (orders, settings) — keep if recent (1h)
            if time() - pending.savedAt < 3600 then
                kept[#kept + 1] = pending
            end
        end
    end
    guildData._pendingBroadcasts = kept
end

--- Get count of pending broadcasts
---@return number
function Sender:GetPendingCount()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData._pendingBroadcasts then return 0 end
    return #guildData._pendingBroadcasts
end
