------------------------------------------------------------------------
-- Vault of Truths - Sync/Receiver.lua
-- Inbound message handling: reassembly, decompression, dispatch
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Receiver = {}
local Receiver = GF.Receiver
GF:RegisterModule("Receiver", Receiver)

-- Chunk reassembly buffers: [sender:msgType] = { chunks = {}, expected = N, received = N }
local reassemblyBuffers = {}
local BUFFER_TIMEOUT = 30 -- seconds before discarding incomplete messages

-- Track online Vault of Truths users
local onlinePeers = {} -- [playerName] = { syncVersion, lastSeen }

function Receiver:Init()
    -- Auto-resync when chunks are lost
    GF.Events:On("GF_SYNC_CHUNK_LOST", function(msgType, sender)
        C_Timer.After(2, function()
            if msgType == "LSYNC_DATA" or msgType == "FULL_SYNC_DATA" then
                GF.Sender:RequestSync()
            elseif msgType == "ORDER_NEW" or msgType == "ORDER_UPD" then
                GF.Sender:RequestFullSync()
            end
        end)
    end)

    -- Listen for addon messages (guild broadcasts, whisper replies, and shared channels)
    GF.Events:Register("CHAT_MSG_ADDON", function(event, prefix, message, channel, sender)
        if prefix ~= GF.PREFIX then return end
        if channel ~= "GUILD" and channel ~= "OFFICER" and channel ~= "WHISPER" then return end

        -- Don't process our own messages
        local myName = GF.Utils:GetPlayerFullName()
        -- Sender might not include realm
        if sender == myName or sender == myName:match("^(.+)-") then
            return
        end

        Receiver:OnMessage(message, sender)
    end)

    -- Periodic cleanup of stale buffers
    C_Timer.NewTicker(BUFFER_TIMEOUT, function()
        Receiver:CleanupBuffers()
    end)
end

--- Handle an incoming addon message
---@param message string Raw message
---@param sender string Sender name
function Receiver:OnMessage(message, sender)
    local parsed = GF.Protocol:ParseMessage(message)
    if not parsed then
        if GF.debug then
            GF.ChatNotify:Debug("Sync: unparseable message from " .. sender)
        end
        return
    end

    -- Version check — v2 only
    if parsed.protocolVersion > GF.Protocol.PROTOCOL_VERSION then
        GF.ChatNotify:Warning("Guild member " .. sender .. " has a newer Vault of Truths version. Consider updating!")
        return
    elseif parsed.protocolVersion < GF.Protocol.PROTOCOL_VERSION then
        -- Reject old protocol messages — data was reset, everyone should be on v2
        return
    end

    -- Single-chunk message: process immediately
    if parsed.totalChunks == 1 then
        self:Dispatch(parsed.msgType, parsed.payload, sender, parsed.msgID)
        return
    end

    -- Multi-chunk: reassemble
    local bufferKey = sender .. ":" .. parsed.msgType
    if not reassemblyBuffers[bufferKey] then
        reassemblyBuffers[bufferKey] = {
            chunks = {},
            expected = parsed.totalChunks,
            received = 0,
            startTime = time(),
            msgID = parsed.msgID,
        }
    end

    local buffer = reassemblyBuffers[bufferKey]
    buffer.chunks[parsed.chunkNum] = parsed.payload
    buffer.received = buffer.received + 1

    -- All chunks received?
    if buffer.received >= buffer.expected then
        -- Verify all chunks present — don't fill gaps with empty strings
        local missing = {}
        for i = 1, buffer.expected do
            if not buffer.chunks[i] then
                missing[#missing + 1] = i
            end
        end
        if #missing > 0 then
            GF.ChatNotify:Warning("Sync: missing chunk(s) " .. table.concat(missing, ",") ..
                " for " .. parsed.msgType .. " from " .. sender)
            GF.Events:Fire("GF_SYNC_CHUNK_LOST", parsed.msgType, sender, buffer.received, buffer.expected)
            reassemblyBuffers[bufferKey] = nil
            return
        end
        local fullPayload = table.concat(buffer.chunks)
        local msgID = buffer.msgID or parsed.msgID
        reassemblyBuffers[bufferKey] = nil
        self:Dispatch(parsed.msgType, fullPayload, sender, msgID)
    end
end

--- Dispatch a complete message to the appropriate handler
---@param msgType string
---@param encodedPayload string
---@param sender string
-- Critical message types that warrant visible warnings on failure
local CRITICAL_MSG_TYPES = {
    [GF.Protocol.MSG.LSYNC_DATA] = true,
    [GF.Protocol.MSG.ORDER_NEW] = true,
    [GF.Protocol.MSG.ORDER_UPD] = true,
    [GF.Protocol.MSG.FULL_SYNC_DATA] = true,
    [GF.Protocol.MSG.PAYOUT_REC] = true,
    [GF.Protocol.MSG.SETTINGS] = true,
    [GF.Protocol.MSG.ROLE_UPD] = true,
}

function Receiver:Dispatch(msgType, encodedPayload, sender, msgID)
    local data, err = GF.Protocol:Decode(encodedPayload)
    if not data then
        if CRITICAL_MSG_TYPES[msgType] then
            GF.ChatNotify:Warning("Sync error: failed to decode " .. msgType .. " from " .. sender .. ". Requesting re-sync...")
            C_Timer.After(2, function() GF.Sender:RequestSync() end)
        elseif GF.debug then
            GF.ChatNotify:Debug("Sync decode error from " .. sender .. ": " .. (err or "unknown"))
        end
        return
    end

    if GF.debug then
        GF.ChatNotify:Debug("Sync recv: " .. msgType .. " from " .. sender)
    end

    local handler = self.handlers[msgType]
    if handler then
        local ok, handlerErr = xpcall(handler, geterrorhandler(), self, data, sender)
        if not ok then
            if CRITICAL_MSG_TYPES[msgType] then
                GF.ChatNotify:Warning("Sync handler error (" .. msgType .. "): " .. tostring(handlerErr))
            elseif GF.debug then
                GF.ChatNotify:Debug("Sync handler error (" .. msgType .. "): " .. tostring(handlerErr))
            end
        elseif msgID and CRITICAL_MSG_TYPES[msgType] then
            -- Successfully handled a critical message with msgID — send ACK
            GF.Sender:SendAck(msgID, sender)
        end
    end
end

-- Message handlers
Receiver.handlers = {}

--- VER: Version announcement — a peer just came online
Receiver.handlers[GF.Protocol.MSG.VER] = function(self, data, sender)
    local isNew = not onlinePeers[sender]
    onlinePeers[sender] = {
        version = data.version,
        protocol = data.protocol,
        lastSeen = time(),
    }

    -- If this is a newly seen peer, replay any pending changes we made while alone
    if isNew and GF.Sender:GetPendingCount() > 0 then
        C_Timer.After(2, function()
            GF.Sender:ReplayPending(sender)
        end)
    end
end

--- PING: Heartbeat
Receiver.handlers[GF.Protocol.MSG.PING] = function(self, data, sender)
    onlinePeers[sender] = {
        syncVersion = data.syncVersion,
        lastSeen = time(),
    }

    -- Reply with our sync version (whisper back to sender)
    local guildData = GF.Settings:GetGuildData()
    if guildData then
        GF.Sender:SendPong(guildData.ledger.nextSyncVersion - 1, sender)
    end
end

--- PONG: Heartbeat reply
Receiver.handlers[GF.Protocol.MSG.PONG] = function(self, data, sender)
    onlinePeers[sender] = {
        syncVersion = data.syncVersion,
        lastSeen = time(),
        playerName = data.playerName,
    }

    -- If they have newer data, request it
    local guildData = GF.Settings:GetGuildData()
    if guildData and data.syncVersion > (guildData.ledger.nextSyncVersion - 1) then
        GF.Sender:RequestSync()
    end
end

--- LSYNC_REQ: Ledger sync request (whisper response back to requester)
Receiver.handlers[GF.Protocol.MSG.LSYNC_REQ] = function(self, data, sender)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    local sinceVersion = data.sinceSyncVersion or 0
    local entries = {}

    for _, entry in ipairs(guildData.ledger.entries) do
        if entry.syncVersion > sinceVersion then
            entries[#entries + 1] = entry
        end
    end

    if #entries > 0 then
        GF.Sender:SendTo(GF.Protocol.MSG.LSYNC_DATA, { entries = entries }, sender)
    end
end

--- LSYNC_DATA: Ledger entries received
Receiver.handlers[GF.Protocol.MSG.LSYNC_DATA] = function(self, data, sender)
    if not data.entries then return end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    local added = 0
    for _, entry in ipairs(data.entries) do
        -- Check for duplicates by ID
        local isDuplicate = false
        for _, existing in ipairs(guildData.ledger.entries) do
            if existing.id == entry.id then
                isDuplicate = true
                break
            end
        end

        if not isDuplicate then
            -- Fill in missing prices from our TSM if sender didn't have it
            if GF.TSM and GF.TSM:IsAvailable() and entry.items then
                local recalcTotal = false
                for _, item in ipairs(entry.items) do
                    if item.itemID and (not item.unitValue or item.unitValue == 0) then
                        local price = GF.TSM:GetBestPrice(item.itemID)
                        if price and price > 0 then
                            item.unitValue = price
                            item.priceSource = "tsm_receiver"
                            recalcTotal = true
                        end
                    end
                end
                -- Recalculate total value if we filled in prices
                if recalcTotal then
                    local total = 0
                    for _, item in ipairs(entry.items) do
                        total = total + (item.unitValue or 0) * (item.quantity or 1)
                    end
                    if total > 0 and (entry.totalValue or 0) == 0 then
                        entry.totalValue = total
                    end
                end
            end

            table.insert(guildData.ledger.entries, entry)
            added = added + 1

            -- Update sync version
            if entry.syncVersion >= guildData.ledger.nextSyncVersion then
                guildData.ledger.nextSyncVersion = entry.syncVersion + 1
            end

            -- Update contribution tracking
            if entry.action == GF.ACTIONS.DEPOSIT then
                GF.Ledger:UpdateContribution(entry.player, entry.totalValue)
            end
        end
    end

    if added > 0 then
        -- Sort entries by timestamp (newest first)
        table.sort(guildData.ledger.entries, function(a, b)
            return a.timestamp > b.timestamp
        end)

        GF.Events:Fire("GF_SYNC_RECEIVED", added, sender)

        if GF.debug then
            GF.ChatNotify:Debug("Synced " .. added .. " ledger entries from " .. sender)
        end
    end
end

--- FULL_SYNC_REQ: Full state sync request (whisper response)
Receiver.handlers[GF.Protocol.MSG.FULL_SYNC_REQ] = function(self, data, sender)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    -- Build a full state snapshot (excluding sensitive financial details for non-officers)
    local response = {
        orders = guildData.orders or {},
        members = guildData.members or {},
        guildSettings = guildData.guildSettings or {},
        timestamp = time(),
    }

    GF.Sender:SendTo(GF.Protocol.MSG.FULL_SYNC_DATA, response, sender)

    if GF.debug then
        GF.ChatNotify:Debug("Full sync sent to " .. sender)
    end
end

--- FULL_SYNC_DATA: Full state received — merge into local data
Receiver.handlers[GF.Protocol.MSG.FULL_SYNC_DATA] = function(self, data, sender)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    local ordersAdded = 0
    local membersUpdated = 0

    -- Merge orders (dedupe by ID)
    if data.orders then
        local existingIDs = {}
        for _, order in ipairs(guildData.orders) do
            existingIDs[order.id] = true
        end
        for _, order in ipairs(data.orders) do
            if not existingIDs[order.id] then
                guildData.orders[#guildData.orders + 1] = order
                ordersAdded = ordersAdded + 1
            else
                -- Update status of existing orders (theirs may be newer)
                for _, existing in ipairs(guildData.orders) do
                    if existing.id == order.id then
                        if order.status ~= existing.status then
                            -- Take the more advanced status
                            local statusPriority = {
                                [GF.ORDER_STATUS.OPEN] = 1,
                                [GF.ORDER_STATUS.ACCEPTED] = 2,
                                [GF.ORDER_STATUS.COMPLETED] = 3,
                                [GF.ORDER_STATUS.CANCELLED] = 3,
                            }
                            local theirs = statusPriority[order.status] or 0
                            local ours = statusPriority[existing.status] or 0
                            if theirs > ours then
                                existing.status = order.status
                                existing.crafter = order.crafter or existing.crafter
                                existing.accepted = order.accepted or existing.accepted
                                existing.completed = order.completed or existing.completed
                                existing.lastUpdated = order.lastUpdated or existing.lastUpdated
                            elseif theirs == ours and (order.lastUpdated or 0) > (existing.lastUpdated or 0) then
                                -- Same status priority but theirs is newer — take their metadata
                                existing.updatedBy = order.updatedBy or existing.updatedBy
                                existing.lastUpdated = order.lastUpdated
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    -- Merge members/roles (their data wins if we have no record)
    if data.members then
        for playerName, memberData in pairs(data.members) do
            if not guildData.members[playerName] then
                guildData.members[playerName] = memberData
                membersUpdated = membersUpdated + 1
            else
                -- Merge roles we don't have
                local ours = guildData.members[playerName]
                if memberData.roles and not ours.roles then
                    ours.roles = memberData.roles
                    membersUpdated = membersUpdated + 1
                elseif memberData.roles and ours.roles then
                    for role, val in pairs(memberData.roles) do
                        if ours.roles[role] == nil then
                            ours.roles[role] = val
                            membersUpdated = membersUpdated + 1
                        end
                    end
                end
            end
        end
    end

    -- Merge guild settings (only if we haven't been configured yet)
    if data.guildSettings then
        GF.Settings:MergeDefaults(guildData.guildSettings, data.guildSettings)
    end

    if ordersAdded > 0 or membersUpdated > 0 then
        GF.Events:Fire("GF_FULL_SYNC_RECEIVED", ordersAdded, membersUpdated, sender)
    end

    -- We've synced with someone — clear pending entries they already have
    local syncVer = guildData.ledger.nextSyncVersion - 1
    GF.Sender:ClearPending(syncVer)

    if GF.debug then
        GF.ChatNotify:Debug("Full sync from " .. sender .. ": +" .. ordersAdded .. " orders, " .. membersUpdated .. " member updates")
    end
end

--- ORDER_NEW: New crafting order
Receiver.handlers[GF.Protocol.MSG.ORDER_NEW] = function(self, data, sender)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    -- Check for duplicate order ID
    for _, order in ipairs(guildData.orders) do
        if order.id == data.id then return end
    end

    guildData.orders[#guildData.orders + 1] = data
    GF.Events:Fire("GF_ORDER_RECEIVED", data)
    GF.Toast:OrderUpdate(data.id, "New order from " .. sender)
end

--- ORDER_UPD: Order status change (with timestamp conflict resolution)
Receiver.handlers[GF.Protocol.MSG.ORDER_UPD] = function(self, data, sender)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    for _, order in ipairs(guildData.orders) do
        if order.id == data.orderID then
            -- Conflict resolution: reject stale updates
            local existingTimestamp = order.lastUpdated or order.accepted or order.completed or 0
            local incomingTimestamp = data.timestamp or 0

            if incomingTimestamp < existingTimestamp then
                if GF.debug then
                    GF.ChatNotify:Debug("Stale order update from " .. sender .. " — ours: " ..
                        existingTimestamp .. ", theirs: " .. incomingTimestamp)
                end
                return
            end

            order.status = data.status
            order.updatedBy = data.updatedBy
            order.lastUpdated = incomingTimestamp
            if data.status == GF.ORDER_STATUS.ACCEPTED then
                order.crafter = data.updatedBy
                order.accepted = data.timestamp
            elseif data.status == GF.ORDER_STATUS.COMPLETED then
                order.completed = data.timestamp
            end
            GF.Events:Fire("GF_ORDER_UPDATED", order)
            GF.Toast:OrderUpdate(data.orderID, data.status)
            break
        end
    end
end

--- PAYOUT_REC: Payout recorded or AH sale broadcast
Receiver.handlers[GF.Protocol.MSG.PAYOUT_REC] = function(self, data, sender)
    local myName = GF.Utils:GetPlayerFullName()

    if data.type == "ah_sale" then
        -- AH sale broadcast — fire event so ChatNotify can handle it
        GF.Events:Fire("GF_AH_SALE_RECORDED", {
            itemID = data.itemID,
            _itemName = data.itemName,
            itemName = data.itemName,
            salePrice = data.salePrice,
            profit = data.profit,
            crafterName = data.crafterName,
            auctioneer = data.auctioneer or sender,
            timestamp = data.timestamp,
        })
    elseif data.player == myName then
        -- Regular payout notification
        GF.Toast:PayoutReceived(data.amount, data.method)
    end
end

--- SETTINGS: Guild settings update
Receiver.handlers[GF.Protocol.MSG.SETTINGS] = function(self, data, sender)
    -- Only accept settings from officers/owner
    -- Note: we can't verify rank over addon comms, so we trust the sender
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    -- Merge received settings
    GF.Settings:MergeDefaults(guildData.guildSettings, data)
    GF.Events:Fire("GF_SETTINGS_SYNCED", data, sender)

    if GF.debug then
        GF.ChatNotify:Debug("Guild settings synced from " .. sender)
    end
end

--- ROLE_UPD: Role assignment change
Receiver.handlers[GF.Protocol.MSG.ROLE_UPD] = function(self, data, sender)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    local member = GF.Roles:EnsureMemberRecord(data.player)
    member.roles = data.roles or {}
    GF.Events:Fire("GF_ROLE_CHANGED", data.player, data.roles)
end

--- ACK: Acknowledge receipt of a critical message
Receiver.handlers[GF.Protocol.MSG.ACK] = function(self, data, sender)
    if data.msgID then
        GF.Sender:ConfirmAck(data.msgID)
    end
end

--- RECIPES: Crafter recipe data synced
Receiver.handlers["RECIPES"] = function(self, data, sender)
    if data.player and data.profName and data.recipes then
        GF.Events:Fire("GF_RECIPES_RECEIVED", data.player, data)
    end
end

--- Community bridge handlers (non-guildie support) ---

--- CB_PRES: Guild member presence on shared channel
Receiver.handlers[GF.Protocol.MSG.CB_PRES] = function(self, data, sender)
    if GF.CommunityBridge then
        GF.CommunityBridge:OnPresenceReceived(data, sender)
    end
end

--- CB_RECIPE_REQ: Non-guildie requests recipe catalog
Receiver.handlers[GF.Protocol.MSG.CB_RECIPE_REQ] = function(self, data, sender)
    if not IsInGuild() then return end
    if GF.CommunityBridge then
        GF.CommunityBridge:OnRecipeRequest(data, sender)
    end
end

--- CB_RECIPE_DATA: Recipe catalog response (non-guildie receives)
Receiver.handlers[GF.Protocol.MSG.CB_RECIPE_DATA] = function(self, data, sender)
    if GF.CommunityBridge then
        GF.CommunityBridge:OnRecipeDataReceived(data, sender)
    end
end

--- CB_ORDER_NEW: Crafting order from non-guildie
Receiver.handlers[GF.Protocol.MSG.CB_ORDER_NEW] = function(self, data, sender)
    if not IsInGuild() then return end
    if GF.CommunityBridge then
        GF.CommunityBridge:OnExternalOrder(data, sender)
    end
end

--- CB_ORDER_ACK: Order acknowledgment (non-guildie receives)
Receiver.handlers[GF.Protocol.MSG.CB_ORDER_ACK] = function(self, data, sender)
    if GF.CommunityBridge then
        GF.CommunityBridge:OnOrderAcknowledged(data, sender)
    end
end

--- CB_ORDER_UPD: Order status update for non-guildie
Receiver.handlers[GF.Protocol.MSG.CB_ORDER_UPD] = function(self, data, sender)
    if GF.CommunityBridge then
        GF.CommunityBridge:OnExternalOrderUpdate(data, sender)
    end
end

--- Cleanup stale reassembly buffers — report chunk loss
function Receiver:CleanupBuffers()
    local now = time()
    for key, buffer in pairs(reassemblyBuffers) do
        if now - buffer.startTime > BUFFER_TIMEOUT then
            local sender, msgType = key:match("^(.+):([%u_]+)$")
            GF.ChatNotify:Warning("Sync: incomplete " .. (msgType or "?") .. " from " ..
                (sender or "?") .. " — " .. buffer.received .. "/" .. buffer.expected ..
                " chunks. Discarding.")
            GF.Events:Fire("GF_SYNC_CHUNK_LOST", msgType, sender, buffer.received, buffer.expected)
            reassemblyBuffers[key] = nil
        end
    end
end

--- Get list of online Vault of Truths peers
---@return table { [playerName] = { syncVersion, lastSeen, ... } }
function Receiver:GetOnlinePeers()
    -- Prune stale peers (not seen in 5 minutes)
    local now = time()
    for name, peer in pairs(onlinePeers) do
        if now - peer.lastSeen > 300 then
            onlinePeers[name] = nil
        end
    end
    return onlinePeers
end

--- Get count of online peers
---@return number
function Receiver:GetPeerCount()
    local count = 0
    for _ in pairs(self:GetOnlinePeers()) do
        count = count + 1
    end
    return count
end
