------------------------------------------------------------------------
-- Vault of Truths - Sync/CommunityBridge.lua
-- Community-based discovery for non-guildies.
-- Uses the "Vault of Truths" community to find online guild members,
-- then whispers them for recipe sync and craft orders.
-- Community provides cross-realm member roster; whispers carry the data.
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.CommunityBridge = {}
local CB = GF.CommunityBridge
GF:RegisterModule("CommunityBridge", CB)

local COMMUNITY_NAME = "Vault of Truths"
local communityClubId = nil
local discoveredPeers = {} -- [playerName] = { lastSeen, version }

local recipeRequestCooldowns = {}
local RECIPE_REQUEST_COOLDOWN = 60
local PEER_TIMEOUT = 300

function CB:Init()
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(5, function()
            CB:Setup()
        end)
    end)

    -- Guild members: respond to non-guildie requests (handled by Receiver handlers)
    GF.Events:On("GF_ORDER_ACCEPTED", function(order) CB:NotifyExternalRequester(order) end)
    GF.Events:On("GF_ORDER_COMPLETED", function(order) CB:NotifyExternalRequester(order) end)
    GF.Events:On("GF_ORDER_CANCELLED", function(order) CB:NotifyExternalRequester(order) end)
end

function CB:Setup()
    if GF.Utils:IsInVoTGuild() then
        -- Guild members: all sync handled via GUILD channel. No community needed.
        -- Optionally find community for posting sync beacons for non-guildies
        communityClubId = self:FindCommunity()
        return
    end

    -- Non-guildies: find the community for sync
    communityClubId = self:FindCommunity()

    if not communityClubId then
        -- Not in the community — can't auto-discover
        return
    end

    -- Start listening for sync beacons in community chat
    self:InitBeaconListener()

    -- Non-guildie in the community: periodically sync recipes from online guild members
    C_Timer.NewTicker(120, function()
        self:AutoSyncRecipes()
    end)
    C_Timer.After(10, function()
        self:AutoSyncRecipes()
    end)
end

--- Find the "Vault of Truths" community in subscribed clubs
---@return string|nil clubId
function CB:FindCommunity()
    if not C_Club or not C_Club.GetSubscribedClubs then return nil end

    local clubs = C_Club.GetSubscribedClubs()
    if not clubs then return nil end

    -- Log all clubs for debugging
    if GF.debug then
        GF.ChatNotify:Debug("Subscribed clubs: " .. #clubs)
        for _, club in ipairs(clubs) do
            GF.ChatNotify:Debug("  Club: '" .. (club.name or "?") .. "' type=" .. tostring(club.clubType) .. " id=" .. tostring(club.clubId))
        end
    end

    for _, club in ipairs(clubs) do
        -- Case-insensitive match, trim whitespace
        local clubName = (club.name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local searchName = COMMUNITY_NAME:lower()
        if clubName == searchName or clubName:find(searchName, 1, true) then
            GF.ChatNotify:Info("Connected to community: " .. club.name)
            return club.clubId
        end
    end
    return nil
end

--- Get online guild members from the community roster
---@return table { [playerName] = { name, presence, classID } }
function CB:GetOnlineCommunityMembers()
    if not communityClubId then return {} end
    if not C_Club.GetClubMembers then return {} end

    local memberIds = C_Club.GetClubMembers(communityClubId)
    if not memberIds then return {} end

    local online = {}
    for _, memberId in ipairs(memberIds) do
        local info = C_Club.GetMemberInfo(communityClubId, memberId)
        if info and info.name and info.presence == Enum.ClubMemberPresence.Online then
            -- Check if this member is in the guild (has guild rank info)
            if info.guildRank or info.guildRankOrder then
                online[info.name] = {
                    name = info.name,
                    presence = info.presence,
                    classID = info.classID,
                    memberId = memberId,
                }
            end
        end
    end
    return online
end

--- Check if player is in the community
---@return boolean
function CB:IsInCommunity()
    if GF.Utils:IsInVoTGuild() then return true end
    return communityClubId ~= nil
end

function CB:IsNonGuildie()
    return not GF.Utils:IsInVoTGuild()
end

function CB:GetConnectedGuild()
    if self:IsInCommunity() then
        return COMMUNITY_NAME
    end
    local names = GF.Settings:GetExternalGuildNames()
    return names[1]
end

function CB:GetPeers(guildName)
    local now = time()
    for name, peer in pairs(discoveredPeers) do
        if now - peer.lastSeen > PEER_TIMEOUT then
            discoveredPeers[name] = nil
        end
    end
    return discoveredPeers
end

function CB:GetPeerCount(guildName)
    local count = 0
    for _ in pairs(self:GetPeers(guildName)) do count = count + 1 end
    return count
end

function CB:GetDiscoveredGuilds()
    if self:IsInCommunity() then
        return { COMMUNITY_NAME }
    end
    return {}
end

------------------------------------------------------------------------
-- Recipe sync (non-guildie side)
------------------------------------------------------------------------

function CB:RequestRecipes(guildName)
    local members = self:GetOnlineCommunityMembers()
    local sent = false

    for memberName in pairs(members) do
        GF.Sender:SendTo(GF.Protocol.MSG.CB_RECIPE_REQ, {
            guildName = guildName or COMMUNITY_NAME,
        }, memberName)
        sent = true

        -- Track as discovered peer
        discoveredPeers[memberName] = {
            lastSeen = time(),
            version = GF.VERSION,
        }
    end

    if not sent and GF.debug then
        GF.ChatNotify:Debug("No online guild members found in community")
    end
end

function CB:AutoSyncRecipes()
    if GF.Utils:IsInVoTGuild() then return end
    if not communityClubId then return end
    self:RequestRecipes(COMMUNITY_NAME)
end

--- Guild member responds to recipe request
function CB:OnRecipeRequest(data, sender)
    if not GF.Utils:IsInVoTGuild() then return end

    local now = time()
    if recipeRequestCooldowns[sender] and now - recipeRequestCooldowns[sender] < RECIPE_REQUEST_COOLDOWN then
        return
    end
    recipeRequestCooldowns[sender] = now

    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.crafterRecipes then return end

    local catalog = {}
    for playerName, playerData in pairs(guildData.crafterRecipes) do
        local profs = {}
        for profName, profData in pairs(playerData.professions or {}) do
            local recipes = {}
            for _, recipe in ipairs(profData.recipes or {}) do
                recipes[#recipes + 1] = {
                    id = recipe.recipeID or recipe.id,
                    name = recipe.name,
                    reagents = recipe.reagents,
                    outputItemID = recipe.outputItemID,
                }
            end
            profs[profName] = { recipes = recipes, count = profData.count or #recipes }
        end
        catalog[playerName] = { professions = profs, lastScan = playerData.lastScan or 0 }
    end

    GF.Sender:SendTo(GF.Protocol.MSG.CB_RECIPE_DATA, {
        guildName = GetGuildInfo("player") or COMMUNITY_NAME,
        crafterRecipes = catalog,
    }, sender)
end

--- Non-guildie receives recipe data
function CB:OnRecipeDataReceived(data, sender)
    if not data.guildName or not data.crafterRecipes then return end

    local extData = GF.Settings:GetExternalGuildData(data.guildName)
    extData.crafterRecipes = data.crafterRecipes
    extData.lastSync = time()

    discoveredPeers[sender] = { lastSeen = time(), version = GF.VERSION }

    GF.Events:Fire("GF_EXTERNAL_RECIPES_UPDATED", data.guildName)
end

------------------------------------------------------------------------
-- Order submission (non-guildie side)
------------------------------------------------------------------------

function CB:SubmitOrder(guildName, order)
    local members = self:GetOnlineCommunityMembers()
    local sent = false

    for memberName in pairs(members) do
        GF.Sender:SendTo(GF.Protocol.MSG.CB_ORDER_NEW, {
            guildName = guildName or COMMUNITY_NAME,
            order = order,
        }, memberName)
        sent = true
    end

    if sent then
        GF.ChatNotify:Info("Crafting order submitted")
    else
        GF.ChatNotify:Warning("No guild members online in community.")
    end
end

function CB:OnExternalOrder(data, sender)
    if not GF.Utils:IsInVoTGuild() then return end
    if not data.order then return end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    local order = data.order

    for _, existing in ipairs(guildData.orders) do
        if existing.id == order.id then return end
    end

    order.isExternal = true
    order.externalRequester = sender

    guildData.orders[#guildData.orders + 1] = order
    GF.Sender:BroadcastNewOrder(order)
    GF.Events:Fire("GF_ORDER_RECEIVED", order)

    GF.Sender:SendTo(GF.Protocol.MSG.CB_ORDER_ACK, {
        orderID = order.id,
        status = "received",
    }, sender)
end

function CB:OnOrderAcknowledged(data, sender)
    if not data.orderID then return end
    GF.ChatNotify:Success("Order #" .. data.orderID:sub(1, 6) .. " received by guild.")
end

function CB:OnExternalOrderUpdate(data, sender)
    if not data.orderID then return end

    local statusMsg = data.status
    if data.status == GF.ORDER_STATUS.ACCEPTED then
        local crafter = data.crafter and (data.crafter:match("^(.+)-") or data.crafter) or "someone"
        statusMsg = "accepted by " .. crafter
    elseif data.status == GF.ORDER_STATUS.COMPLETED then
        statusMsg = "completed!"
    elseif data.status == GF.ORDER_STATUS.CANCELLED then
        statusMsg = "cancelled"
    end

    GF.ChatNotify:Info("Order #" .. data.orderID:sub(1, 6) .. " — " .. statusMsg)
    GF.Events:Fire("GF_EXTERNAL_ORDER_UPDATED", data.orderID, data.status)
end

function CB:NotifyExternalRequester(order)
    if not order.isExternal or not order.externalRequester then return end
    if not GF.Utils:IsInVoTGuild() then return end

    GF.Sender:SendTo(GF.Protocol.MSG.CB_ORDER_UPD, {
        orderID = order.id,
        status = order.status,
        crafter = order.crafter,
    }, order.externalRequester)
end

------------------------------------------------------------------------
-- Presence
------------------------------------------------------------------------
function CB:OnPresenceReceived(data, sender)
    if data.playerName then
        discoveredPeers[sender] = { lastSeen = time(), version = data.version }
    end
end

function CB:Disconnect(guildName)
    discoveredPeers = {}
    if guildName then GF.Settings:RemoveExternalGuild(guildName) end
end

------------------------------------------------------------------------
-- Community Sync Beacon
-- Posts a compact sync version to community chat so others can catch up.
-- C_Club.SendMessage is protected — must be called from button click.
-- The beacon is just a signal; full data syncs via whisper on demand.
------------------------------------------------------------------------

local BEACON_PREFIX = "[VoT:SYNC]"
local lastBeaconTime = 0
local BEACON_INTERVAL = 3600 -- 1 hour

--- Build sync data as plain text messages for community chat copy-paste
---@return table Array of message strings (plain text, max 255 chars each)
function CB:BuildSyncMessages()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    local messages = {}
    local player = GF.Utils:GetPlayerFullName()
    local syncVer = guildData.ledger.nextSyncVersion - 1

    -- Message 1: Header with sync version and summary
    local orderCount = 0
    for _, o in ipairs(guildData.orders or {}) do
        if o.status == GF.ORDER_STATUS.OPEN or o.status == GF.ORDER_STATUS.ACCEPTED then
            orderCount = orderCount + 1
        end
    end
    local memberCount = 0
    for _ in pairs(guildData.members or {}) do memberCount = memberCount + 1 end

    messages[#messages + 1] = string.format(
        "%s 1/H v=%d m=%d o=%d t=%d p=%s",
        BEACON_PREFIX, syncVer, memberCount, orderCount, time(), player
    )

    -- Message 2+: Recent ledger entries (ultra-compact)
    -- Format: id~a~p~v~sv (drop timestamp/status to save space)
    -- a = first char of action, p = short player name, v = value in gold, sv = syncVersion
    local ACTION_SHORT = {
        deposit = "D", withdraw = "W", payout = "P", fee = "F",
        craft_withdraw = "CW", craft_deposit = "CD",
        ah_sale = "AS", ah_return = "AR", ah_list = "AL",
    }
    local entryLines = {}
    local count = 0
    for _, entry in ipairs(guildData.ledger.entries) do
        if count >= 10 then break end
        local shortPlayer = entry.player:match("^(.+)-") or entry.player
        local shortAction = ACTION_SHORT[entry.action] or entry.action:sub(1, 2)
        local goldValue = math.floor((entry.totalValue or 0) / 10000) -- copper to gold
        local line = table.concat({
            entry.id:sub(1, 6),
            shortAction,
            shortPlayer:sub(1, 8),
            tostring(goldValue),
            tostring(entry.syncVersion or 0),
        }, "~")
        entryLines[#entryLines + 1] = line
        count = count + 1
    end

    -- Pack entry lines into 255-char messages
    local currentMsg = BEACON_PREFIX .. " L "
    for _, line in ipairs(entryLines) do
        if #currentMsg + #line + 1 > 250 then
            messages[#messages + 1] = currentMsg
            currentMsg = BEACON_PREFIX .. " L "
        end
        currentMsg = currentMsg .. line .. ";"
    end
    if #currentMsg > #(BEACON_PREFIX .. " L ") then
        messages[#messages + 1] = currentMsg
    end

    -- Renumber messages
    local total = #messages
    for i, msg in ipairs(messages) do
        -- Replace the first occurrence of the chunk marker
        if i == 1 then
            messages[i] = msg:gsub("1/H", i .. "/" .. total)
        end
    end

    return messages
end

--- Parse a community sync message
---@param message string
---@return string type "header" or "ledger"
---@return table|nil data
function CB:ParseSyncMessage(message)
    if not message or not message:find(BEACON_PREFIX, 1, true) then return nil, nil end

    -- Header message: [VoT:SYNC] N/T v=X m=X o=X t=X p=Name
    local ver = message:match("v=(%d+)")
    if ver then
        return "header", {
            syncVersion = tonumber(ver),
            members = tonumber(message:match("m=(%d+)")) or 0,
            orders = tonumber(message:match("o=(%d+)")) or 0,
            timestamp = tonumber(message:match("t=(%d+)")) or 0,
            player = message:match("p=(%S+)"),
        }
    end

    -- Ledger message: [VoT:SYNC] L id~A~player~gold~sv;...
    if message:find(BEACON_PREFIX .. " L ") then
        local ACTION_EXPAND = {
            D = "deposit", W = "withdraw", P = "payout", F = "fee",
            CW = "craft_withdraw", CD = "craft_deposit",
            AS = "ah_sale", AR = "ah_return", AL = "ah_list",
        }
        local entries = {}
        local payload = message:match(BEACON_PREFIX .. " L (.+)")
        if payload then
            for line in payload:gmatch("([^;]+)") do
                local parts = {}
                for part in line:gmatch("([^~]+)") do
                    parts[#parts + 1] = part
                end
                if #parts >= 4 then
                    entries[#entries + 1] = {
                        id = parts[1],
                        action = ACTION_EXPAND[parts[2]] or parts[2],
                        player = parts[3],
                        totalValue = (tonumber(parts[4]) or 0) * 10000, -- gold back to copper
                        syncVersion = tonumber(parts[5]) or 0,
                        timestamp = time(),
                        status = "credited",
                        items = {},
                    }
                end
            end
        end
        return "ledger", entries
    end

    return nil, nil
end

--- Build sync messages for manual copy-paste to community chat
--- Returns the messages and shows a copy dialog
function CB:ShowSyncCopyDialog()
    local messages = self:BuildSyncMessages()

    if #messages == 0 then
        GF.ChatNotify:Warning("No sync data to send.")
        return
    end

    -- Create or reuse the copy dialog
    if not self._copyDialog then
        local dialog = CreateFrame("Frame", "VoTSyncCopyDialog", UIParent, "BackdropTemplate")
        dialog:SetSize(500, 300)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("DIALOG")
        dialog:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        dialog:SetBackdropColor(0.05, 0.06, 0.09, 0.97)
        dialog:SetBackdropBorderColor(0.15, 0.25, 0.4, 0.8)
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        tinsert(UISpecialFrames, "VoTSyncCopyDialog")

        local titleBar = CreateFrame("Frame", nil, dialog)
        titleBar:SetHeight(24)
        titleBar:SetPoint("TOPLEFT", 0, 0)
        titleBar:SetPoint("TOPRIGHT", 0, 0)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() dialog:StartMoving() end)
        titleBar:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -6)
        title:SetText("|cFFFFCC00Community Sync|r")

        local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -1, -1)
        closeBtn:SetSize(20, 20)

        local instructions = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        instructions:SetPoint("TOPLEFT", 10, -26)
        instructions:SetPoint("RIGHT", -10, 0)
        instructions:SetJustifyH("LEFT")
        instructions:SetWordWrap(true)
        dialog._instructions = instructions

        -- Scrollable edit box for the sync text
        local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 10, -58)
        scrollFrame:SetPoint("BOTTOMRIGHT", -28, 40)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetWidth(440)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        editBox:SetScript("OnMouseUp", function(self)
            self:HighlightText()
        end)
        editBox:SetScript("OnTextChanged", function(self)
            -- Resize height to fit content
            self:SetHeight(math.max(200, self:GetStringHeight() + 10))
        end)
        scrollFrame:SetScrollChild(editBox)
        scrollFrame:SetScript("OnSizeChanged", function(self, w)
            editBox:SetWidth(w - 4)
        end)
        dialog._editBox = editBox

        -- Next / Done button
        local nextBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        nextBtn:SetSize(120, 26)
        nextBtn:SetPoint("BOTTOMRIGHT", -10, 10)
        dialog._nextBtn = nextBtn

        -- Select All button
        local selectBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        selectBtn:SetSize(130, 26)
        selectBtn:SetPoint("BOTTOMLEFT", 10, 10)
        selectBtn:SetText("Select All (Ctrl+C)")
        selectBtn:SetScript("OnClick", function()
            dialog._editBox:SetFocus()
            dialog._editBox:HighlightText()
        end)

        dialog:Hide()
        self._copyDialog = dialog
    end

    local dialog = self._copyDialog
    self._syncMessages = messages
    self._currentMessage = 1

    local function ShowCurrentMessage()
        local idx = self._currentMessage
        local total = #self._syncMessages
        local msg = self._syncMessages[idx]

        dialog._instructions:SetText(
            "Message |cFFFFCC00" .. idx .. "/" .. total .. "|r — " ..
            "Copy text below, paste into community chat, press Enter. Then click Next."
        )
        dialog._editBox:SetText(msg)
        dialog._editBox:SetFocus()
        dialog._editBox:HighlightText()

        if idx >= total then
            dialog._nextBtn:SetText("Done")
            dialog._nextBtn:SetScript("OnClick", function()
                lastBeaconTime = time()
                GF.ChatNotify:Success("All " .. total .. " sync messages sent to community!")
                dialog:Hide()
            end)
        else
            dialog._nextBtn:SetText("Next (" .. (idx + 1) .. "/" .. total .. ")")
            dialog._nextBtn:SetScript("OnClick", function()
                self._currentMessage = self._currentMessage + 1
                ShowCurrentMessage()
            end)
        end
    end

    ShowCurrentMessage()
    dialog:Show()
end

--- Check if a beacon is due
function CB:IsBeaconDue()
    return (time() - lastBeaconTime) >= BEACON_INTERVAL
end

--- Prompt the user to sync
function CB:PromptBeacon()
    if not communityClubId then return end
    GF.ChatNotify:Info("Community sync is due. Use Officer Panel > Community Sync.")
end

--- Check if a beacon is due (more than 1 hour since last)
---@return boolean
function CB:IsBeaconDue()
    return (time() - lastBeaconTime) >= BEACON_INTERVAL
end

--- Initialize community chat listener for sync beacons
local reassemblyBuffer = {} -- { chunks = {}, expected = N, received = N }

function CB:InitBeaconListener()
    if not communityClubId then return end

    local beaconFrame = CreateFrame("Frame")
    beaconFrame:RegisterEvent("CLUB_MESSAGE_ADDED")
    beaconFrame:SetScript("OnEvent", function(self, event, clubId, streamId, messageId)
        if clubId ~= communityClubId then return end

        local msgInfo = C_Club.GetMessageInfo(clubId, streamId, messageId)
        if not msgInfo or not msgInfo.content then return end

        CB:ProcessCommunityMessage(msgInfo.content)
    end)

    -- Scan recent community chat history on startup
    C_Timer.After(8, function()
        CB:ScanCommunityHistory()
    end)
end

--- Process a single community chat message for sync data
function CB:ProcessCommunityMessage(content)
    if not content or not content:find(BEACON_PREFIX, 1, true) then return end

    local msgType, data = self:ParseSyncMessage(content)
    if not msgType then return end

    if msgType == "header" then
        -- Store the sender as a discovered peer
        if data.player then
            discoveredPeers[data.player] = { lastSeen = time(), version = GF.VERSION }
        end

        -- Check if we're behind on sync version
        if GF.Utils:IsInVoTGuild() and data.syncVersion then
            local guildData = GF.Settings:GetGuildData()
            if guildData then
                local ourVersion = guildData.ledger.nextSyncVersion - 1
                if data.syncVersion > ourVersion and data.player then
                    -- Request full sync from the sender
                    GF.Sender:SendTo(GF.Protocol.MSG.LSYNC_REQ, {
                        sinceSyncVersion = ourVersion,
                    }, data.player)
                end
            end
        end

    elseif msgType == "ledger" and data then
        local guildData = GF.Settings:GetGuildData()
        if not guildData then return end

        local added = 0
        for _, entry in ipairs(data) do
            -- Dedupe by ID
            local isDup = false
            for _, existing in ipairs(guildData.ledger.entries) do
                if existing.id == entry.id then isDup = true; break end
            end

            if not isDup then
                table.insert(guildData.ledger.entries, entry)
                if entry.syncVersion >= guildData.ledger.nextSyncVersion then
                    guildData.ledger.nextSyncVersion = entry.syncVersion + 1
                end
                added = added + 1
            end
        end

        if added > 0 then
            GF.ChatNotify:Info("Community sync: +" .. added .. " ledger entries")
            GF.Events:Fire("GF_SYNC_RECEIVED", added, "community")
        end
    end
end

--- Scan recent community chat history for sync messages (catch up on login)
function CB:ScanCommunityHistory()
    if not communityClubId then
        if GF.debug then GF.ChatNotify:Debug("No community club ID — skipping history scan") end
        return
    end

    local streams = C_Club.GetStreams(communityClubId)
    if not streams or #streams == 0 then
        if GF.debug then GF.ChatNotify:Debug("No community streams found") end
        return
    end

    if GF.debug then
        GF.ChatNotify:Debug("Community streams: " .. #streams)
        for _, s in ipairs(streams) do
            GF.ChatNotify:Debug("  Stream: " .. tostring(s.streamId) .. " name=" .. (s.name or "?"))
        end
    end

    local streamId = streams[1].streamId

    -- Try multiple API approaches to read history
    local messages = nil

    -- Method 1: GetMessagesBefore
    if C_Club.GetMessagesBefore then
        local ok, result = pcall(C_Club.GetMessagesBefore, communityClubId, streamId, nil, 30)
        if ok and result then
            messages = result
        elseif GF.debug then
            GF.ChatNotify:Debug("GetMessagesBefore failed: " .. tostring(result))
        end
    end

    -- Method 2: GetMessageRanges + GetMessageInfo
    if not messages and C_Club.GetMessageRanges then
        local ok, ranges = pcall(C_Club.GetMessageRanges, communityClubId, streamId)
        if ok and ranges and GF.debug then
            GF.ChatNotify:Debug("Message ranges: " .. #ranges)
        end
    end

    if messages then
        if GF.debug then
            GF.ChatNotify:Debug("Read " .. #messages .. " messages from community history")
        end

        local processed = 0
        for _, msg in ipairs(messages) do
            local content = msg.content or (msg.messageInfo and msg.messageInfo.content)
            if content and content:find(BEACON_PREFIX, 1, true) then
                self:ProcessCommunityMessage(content)
                processed = processed + 1
            end
        end

        if processed > 0 then
            GF.ChatNotify:Info("Synced " .. processed .. " entries from community history.")
        elseif GF.debug then
            GF.ChatNotify:Debug("No sync messages found in community history")
        end
    elseif GF.debug then
        GF.ChatNotify:Debug("Could not read community history")
    end
end
