------------------------------------------------------------------------
-- Vault of Truths - Sync/Protocol.lua
-- Message types, serialization/compression pipeline, versioning
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Protocol = {}
local Proto = GF.Protocol

-- Message type codes
Proto.MSG = {
    VER = "VER",               -- Version announcement
    LSYNC_REQ = "LSYNC_REQ",  -- Request ledger entries newer than syncVersion
    LSYNC_DATA = "LSYNC_DATA",-- Chunked ledger entries response
    ACK = "ACK",               -- Acknowledge receipt of a critical message
    ORDER_NEW = "ORDER_NEW",   -- New crafting order posted
    ORDER_UPD = "ORDER_UPD",   -- Order status change
    PAYOUT_REC = "PAYOUT_REC", -- Payout recorded
    SETTINGS = "SETTINGS",     -- Guild settings update from owner/officer
    ROLE_UPD = "ROLE_UPD",     -- Role assignment change
    PING = "PING",             -- Heartbeat with local syncVersion
    PONG = "PONG",             -- Reply to PING
    FULL_SYNC_REQ = "FULL_SYNC_REQ",   -- Request full state (orders, roles, settings)
    FULL_SYNC_DATA = "FULL_SYNC_DATA", -- Full state response
    -- Community bridge (non-guildie support)
    CB_PRES = "CB_PRES",          -- Guild member presence broadcast on shared channel
    CB_RECIPE_REQ = "CB_RECIPE_REQ",  -- Non-guildie requests recipe catalog
    CB_RECIPE_DATA = "CB_RECIPE_DATA", -- Guild member responds with recipe catalog
    CB_ORDER_NEW = "CB_ORDER_NEW",     -- Non-guildie submits a crafting order
    CB_ORDER_ACK = "CB_ORDER_ACK",     -- Guild member acknowledges order receipt
    CB_ORDER_UPD = "CB_ORDER_UPD",     -- Order status update whispered to non-guildie
}

-- Protocol version (bump when message format changes)
Proto.PROTOCOL_VERSION = 2

-- Max payload per addon message (WoW limit is 255 chars)
Proto.MAX_CHUNK_SIZE = 240 -- Leave room for header

--- Serialize and compress a data payload
---@param data any Lua value to serialize
---@return string|nil encoded Encoded string ready for chunking
---@return string|nil error
function Proto:Encode(data)
    local LibSerialize = LibStub and LibStub("LibSerialize", true)
    local LibDeflate = LibStub and LibStub("LibDeflate", true)

    if not LibSerialize or not LibDeflate then
        return nil, "LibSerialize or LibDeflate not available"
    end

    local serialized = LibSerialize:Serialize(data)
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
    return encoded, nil
end

--- Decompress and deserialize a received payload
---@param encoded string Encoded string
---@return any|nil data Deserialized Lua value
---@return string|nil error
function Proto:Decode(encoded)
    local LibSerialize = LibStub and LibStub("LibSerialize", true)
    local LibDeflate = LibStub and LibStub("LibDeflate", true)

    if not LibSerialize or not LibDeflate then
        return nil, "LibSerialize or LibDeflate not available"
    end

    local compressed = LibDeflate:DecodeForWoWAddonChannel(encoded)
    if not compressed then return nil, "Decode failed" end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil, "Decompress failed" end

    local success, data = LibSerialize:Deserialize(serialized)
    if not success then return nil, "Deserialize failed" end

    return data, nil
end

--- Generate a short message ID (6 hex chars)
---@return string msgID
function Proto:GenerateMsgID()
    return string.format("%06x", math.random(0, 0xFFFFFF))
end

--- Build a message with v2 header (always includes msgID)
---@param msgType string One of Proto.MSG
---@param payload string Encoded payload
---@param msgID string|nil Message ID for ACK tracking (auto-generated if nil)
---@return table chunks Array of strings to send
function Proto:BuildMessage(msgType, payload, msgID)
    msgID = msgID or self:GenerateMsgID()

    local totalChunks = math.ceil(#payload / Proto.MAX_CHUNK_SIZE)
    if totalChunks == 0 then totalChunks = 1 end

    local chunks = {}
    for i = 1, totalChunks do
        local start = (i - 1) * Proto.MAX_CHUNK_SIZE + 1
        local chunk = payload:sub(start, start + Proto.MAX_CHUNK_SIZE - 1)
        local header = string.format("%s:%d:%d/%d:%s:", msgType, Proto.PROTOCOL_VERSION, i, totalChunks, msgID)
        chunks[#chunks + 1] = header .. chunk
    end

    return chunks
end

--- Parse a received message header (v2 format only)
---@param message string Raw addon message
---@return table|nil parsed { msgType, protocolVersion, chunkNum, totalChunks, msgID, payload }
function Proto:ParseMessage(message)
    -- v2 format: TYPE:PROTO:CHUNK/TOTAL:MSGID:PAYLOAD
    local msgType, protoVer, chunkNum, totalChunks, msgID, payload =
        message:match("^([%u_]+):(%d+):(%d+)/(%d+):(%x+):(.*)$")
    if msgType then
        return {
            msgType = msgType,
            protocolVersion = tonumber(protoVer),
            chunkNum = tonumber(chunkNum),
            totalChunks = tonumber(totalChunks),
            msgID = msgID,
            payload = payload,
        }
    end

    return nil
end

