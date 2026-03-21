------------------------------------------------------------------------
-- Vault of Truths - Ledger/Progression.lua
-- Track progression tracking and promotion recommendations
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Progression = {}
local Prog = GF.Progression
GF:RegisterModule("Progression", Prog)

-- In-memory promotion queue (recalculated on login, not persisted)
local promotionQueue = {}

-- Tier ordering for comparison (lower index = lower tier)
local PVPER_TIER_ORDER = { "none", "recruit", "member", "veteran" }
local CRAFTER_TIER_ORDER = { "none", "recruit", "crafter", "master" }

local function TierIndex(tier, tierOrder)
    for i, t in ipairs(tierOrder) do
        if t == tier then return i end
    end
    return 1
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

function Prog:Init()
    -- When a deposit ledger entry is added, update BOTH tracks
    -- PVP contributions progress pvpers AND crafters
    GF.Events:On("GF_LEDGER_ENTRY_ADDED", function(entry)
        if entry.action == GF.ACTIONS.DEPOSIT and entry.status == "credited" then
            self:UpdatePVPerProgress(entry.player)
            self:UpdateCrafterProgress(entry.player)
        end
    end)

    -- When a craft order completes, update crafter track
    GF.Events:On("GF_ORDER_COMPLETED", function(order)
        if order.crafter then
            self:UpdateCrafterProgress(order.crafter)
        end
    end)

    -- Officers get a full promotion check 15s after login
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(15, function()
            if GF.Roles:IsAddonOfficer() then
                self:CheckAllPromotions()
            end
        end)
    end)
end

------------------------------------------------------------------------
-- PVPer Track Progression
------------------------------------------------------------------------

--- Recalculate pvper track tier based on totalContributed vs thresholds
---@param player string "Player-Realm"
function Prog:UpdatePVPerProgress(player)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[player] then return end

    local member = guildData.members[player]
    if not member.tracks or not member.tracks.pvper then return end

    local track = member.tracks.pvper

    -- Gather total contribution from the payouts ledger
    local payoutRecord = guildData.payouts and guildData.payouts[player]
    if payoutRecord then
        track.totalContributed = payoutRecord.totalContributed or 0
    end

    local thresholds = GF.Settings:GetGuild("trackThresholds") or GF.DEFAULT_TRACK_THRESHOLDS
    local pvpThresholds = thresholds.pvper
    if not pvpThresholds then return end

    local newTier = "recruit"

    if track.totalContributed >= (pvpThresholds.veteran or 0) then
        newTier = "veteran"
    elseif track.totalContributed >= (pvpThresholds.member or 0) then
        newTier = "member"
    end

    local oldTier = track.tier or "recruit"
    if TierIndex(newTier, PVPER_TIER_ORDER) > TierIndex(oldTier, PVPER_TIER_ORDER) then
        GF.Roles:SetTrackTier(player, "pvper", newTier)
    end
end

------------------------------------------------------------------------
-- Crafter Track Progression
------------------------------------------------------------------------

--- Recalculate crafter track tier based on craftsCompleted and reliability.
--- Reliability = (crafts completed / crafts accepted) * 100.
--- Blocks promotion if crafter has outstanding mat debt.
---@param player string "Player-Realm"
function Prog:UpdateCrafterProgress(player)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[player] then return end

    local member = guildData.members[player]
    if not member.tracks or not member.tracks.crafter then return end

    local track = member.tracks.crafter

    -- Count completed and accepted orders from the order board
    local orders = GF.OrderBoard and GF.OrderBoard:GetCrafterOrders(player) or {}
    local accepted = 0
    local completed = 0
    for _, order in ipairs(orders) do
        if order.status == GF.ORDER_STATUS.COMPLETED then
            completed = completed + 1
            accepted = accepted + 1
        elseif order.status == GF.ORDER_STATUS.ACCEPTED then
            accepted = accepted + 1
        elseif order.status == GF.ORDER_STATUS.CANCELLED and order.crafter == player then
            -- Cancelled after acceptance counts as accepted but not completed
            if order.accepted then
                accepted = accepted + 1
            end
        end
    end

    track.craftsCompleted = completed
    track.reliability = accepted > 0 and (completed / accepted * 100) or 100

    -- Block promotion if crafter has outstanding mat debt
    if GF.CrafterTracking and GF.CrafterTracking.GetMatBalance then
        local netBalance = GF.CrafterTracking:GetMatBalance(player)
        if netBalance < 0 then
            return -- outstanding debt, do not promote
        end
    end

    local thresholds = GF.Settings:GetGuild("trackThresholds") or GF.DEFAULT_TRACK_THRESHOLDS
    local crafterThresholds = thresholds.crafter
    local pvpThresholds = thresholds.pvper
    if not crafterThresholds then return end

    -- Crafters can also progress via PVP contributions (deposits)
    local totalContributed = 0
    local payoutRecord = guildData.payouts and guildData.payouts[player]
    if payoutRecord then
        totalContributed = payoutRecord.totalContributed or 0
    end

    local newTier = "recruit"

    -- Check master tier first (highest)
    -- Can reach via crafting milestones OR PVP contribution equivalent
    local masterReq = crafterThresholds.master
    local masterViaCrafts = false
    local masterViaPvp = false
    if type(masterReq) == "table" then
        masterViaCrafts = completed >= (masterReq.crafts or 0) and track.reliability >= (masterReq.reliability or 0)
    end
    if pvpThresholds then
        masterViaPvp = totalContributed >= (pvpThresholds.veteran or math.huge)
    end
    if masterViaCrafts or masterViaPvp then
        newTier = "master"
    end

    -- Check crafter tier if not already master
    if newTier ~= "master" then
        local crafterReq = crafterThresholds.crafter
        local crafterViaCrafts = false
        local crafterViaPvp = false
        if type(crafterReq) == "table" then
            crafterViaCrafts = completed >= (crafterReq.crafts or 0) and track.reliability >= (crafterReq.reliability or 0)
        end
        if pvpThresholds then
            crafterViaPvp = totalContributed >= (pvpThresholds.member or math.huge)
        end
        if crafterViaCrafts or crafterViaPvp then
            newTier = "crafter"
        end
    end

    local oldTier = track.tier or "recruit"
    if TierIndex(newTier, CRAFTER_TIER_ORDER) > TierIndex(oldTier, CRAFTER_TIER_ORDER) then
        GF.Roles:SetTrackTier(player, "crafter", newTier)
    end
end

------------------------------------------------------------------------
-- Promotion Checking
------------------------------------------------------------------------

--- Check both tracks for a player and queue a promotion if eligible.
---@param player string "Player-Realm"
function Prog:CheckPromotion(player)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[player] then return end

    local member = guildData.members[player]
    if not member.tracks then return end

    local displayName = player:match("^(.+)-") or player

    for _, trackName in ipairs({ "pvper", "crafter" }) do
        if member.tracks[trackName] then
            local currentTier = GF.Roles:GetTrackTier(player, trackName)
            local tierOrder = trackName == "pvper" and PVPER_TIER_ORDER or CRAFTER_TIER_ORDER

            -- Determine what tier they qualify for now
            local qualifiedTier = self:GetQualifiedTier(player, trackName)

            if TierIndex(qualifiedTier, tierOrder) > TierIndex(currentTier, tierOrder) then
                local currentRank = GF.Roles:ResolveWoWRank(player)
                -- Temporarily compute what rank they'd get with the new tier
                local mapping = GF.TRACK_TO_RANK[trackName]
                local newRankFromTrack = mapping and mapping[qualifiedTier] or currentRank

                -- For dual-track, take the best (lowest index) rank
                local recommendedRank = newRankFromTrack
                for otherTrack, otherData in pairs(member.tracks) do
                    if otherTrack ~= trackName then
                        local otherMapping = GF.TRACK_TO_RANK[otherTrack]
                        if otherMapping and otherData.tier then
                            local otherRank = otherMapping[otherData.tier]
                            if otherRank and otherRank < recommendedRank then
                                recommendedRank = otherRank
                            end
                        end
                    end
                end

                -- Check for duplicates in the queue
                local isDuplicate = false
                for _, existing in ipairs(promotionQueue) do
                    if existing.player == player and existing.track == trackName then
                        -- Update existing entry
                        existing.newTier = qualifiedTier
                        existing.recommendedRank = recommendedRank
                        isDuplicate = true
                        break
                    end
                end

                if not isDuplicate then
                    promotionQueue[#promotionQueue + 1] = {
                        player = player,
                        displayName = displayName,
                        track = trackName,
                        currentTier = currentTier,
                        newTier = qualifiedTier,
                        reason = self:BuildPromotionReason(player, trackName, currentTier, qualifiedTier),
                        currentRank = currentRank,
                        recommendedRank = recommendedRank,
                    }

                    GF.Events:Fire("GF_PROMOTION_READY", player, trackName, qualifiedTier)
                end
            end
        end
    end
end

--- Get the tier a player currently qualifies for based on their stats.
---@param player string
---@param trackName string "pvper" or "crafter"
---@return string tier
function Prog:GetQualifiedTier(player, trackName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[player] then return "none" end

    local member = guildData.members[player]
    if not member.tracks or not member.tracks[trackName] then return "none" end

    local track = member.tracks[trackName]
    local thresholds = GF.Settings:GetGuild("trackThresholds") or GF.DEFAULT_TRACK_THRESHOLDS

    if trackName == "pvper" then
        local pvpThresholds = thresholds.pvper or {}
        local contributed = track.totalContributed or 0

        if contributed >= (pvpThresholds.veteran or 0) then
            return "veteran"
        elseif contributed >= (pvpThresholds.member or 0) then
            return "member"
        end
        return "recruit"
    elseif trackName == "crafter" then
        local crafterThresholds = thresholds.crafter or {}
        local completed = track.craftsCompleted or 0
        local reliability = track.reliability or 100

        -- Block if mat debt exists
        if GF.CrafterTracking and GF.CrafterTracking.GetMatBalance then
            local netBalance = GF.CrafterTracking:GetMatBalance(player)
            if netBalance < 0 then
                return track.tier or "recruit" -- stay at current tier
            end
        end

        local masterReq = crafterThresholds.master
        if type(masterReq) == "table"
            and completed >= (masterReq.crafts or 0)
            and reliability >= (masterReq.reliability or 0) then
            return "master"
        end

        local crafterReq = crafterThresholds.crafter
        if type(crafterReq) == "table"
            and completed >= (crafterReq.crafts or 0)
            and reliability >= (crafterReq.reliability or 0) then
            return "crafter"
        end

        return "recruit"
    end

    return "none"
end

--- Build a human-readable reason for a promotion
---@param player string
---@param trackName string
---@param oldTier string
---@param newTier string
---@return string
function Prog:BuildPromotionReason(player, trackName, oldTier, newTier)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[player] then return "" end

    local member = guildData.members[player]
    local track = member.tracks and member.tracks[trackName]
    if not track then return "" end

    if trackName == "pvper" then
        return string.format("Contributed %s total",
            GF.Utils:FormatMoney(track.totalContributed or 0))
    elseif trackName == "crafter" then
        return string.format("%d crafts completed, %.0f%% reliability",
            track.craftsCompleted or 0, track.reliability or 0)
    end

    return ""
end

------------------------------------------------------------------------
-- Batch Operations
------------------------------------------------------------------------

--- Check all guild members for pending promotions. Only runs for officers.
function Prog:CheckAllPromotions()
    if not GF.Roles:IsAddonOfficer() then return end

    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members then return end

    -- Clear the queue before a full scan
    wipe(promotionQueue)

    for playerName, _ in pairs(guildData.members) do
        self:CheckPromotion(playerName)
    end

    -- Sort by readiness: biggest tier jump first, then alphabetical
    table.sort(promotionQueue, function(a, b)
        local aTierOrderList = a.track == "pvper" and PVPER_TIER_ORDER or CRAFTER_TIER_ORDER
        local bTierOrderList = b.track == "pvper" and PVPER_TIER_ORDER or CRAFTER_TIER_ORDER
        local aJump = TierIndex(a.newTier, aTierOrderList) - TierIndex(a.currentTier, aTierOrderList)
        local bJump = TierIndex(b.newTier, bTierOrderList) - TierIndex(b.currentTier, bTierOrderList)
        if aJump ~= bJump then
            return aJump > bJump
        end
        return a.displayName < b.displayName
    end)

    if #promotionQueue > 0 then
        print("|cFF33AAFF[Vault of Truths]|r " .. #promotionQueue .. " member(s) eligible for promotion.")
    end
end

------------------------------------------------------------------------
-- Query API
------------------------------------------------------------------------

--- Returns the sorted promotion queue.
---@return table Array of { player, displayName, track, currentTier, newTier, reason, currentRank, recommendedRank }
function Prog:GetPromotionQueue()
    return promotionQueue
end

--- Get track stats for a player suitable for UI display.
---@param player string "Player-Realm"
---@param track string "pvper" or "crafter"
---@return table|nil stats { tier, progress, nextTierAt, progressPercent }
function Prog:GetTrackStats(player, track)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.members[player] then return nil end

    local member = guildData.members[player]
    if not member.tracks or not member.tracks[track] then return nil end

    local trackData = member.tracks[track]
    local thresholds = GF.Settings:GetGuild("trackThresholds") or GF.DEFAULT_TRACK_THRESHOLDS

    if track == "pvper" then
        local pvpThresholds = thresholds.pvper or {}
        local contributed = trackData.totalContributed or 0
        local currentTier = trackData.tier or "recruit"

        -- Determine next tier threshold
        local nextTierAt = 0
        local currentFloor = 0
        if currentTier == "recruit" then
            nextTierAt = pvpThresholds.member or 0
            currentFloor = pvpThresholds.recruit or 0
        elseif currentTier == "member" then
            nextTierAt = pvpThresholds.veteran or 0
            currentFloor = pvpThresholds.member or 0
        else
            -- veteran (max tier) — show as 100%
            nextTierAt = contributed
            currentFloor = pvpThresholds.veteran or 0
        end

        local range = nextTierAt - currentFloor
        local progressInRange = contributed - currentFloor
        local percent = range > 0 and math.min(100, math.floor(progressInRange / range * 100)) or 100

        return {
            tier = currentTier,
            progress = contributed,
            nextTierAt = nextTierAt,
            progressPercent = percent,
        }
    elseif track == "crafter" then
        local crafterThresholds = thresholds.crafter or {}
        local completed = trackData.craftsCompleted or 0
        local currentTier = trackData.tier or "recruit"

        local nextTierAt = 0
        local currentFloor = 0
        if currentTier == "recruit" then
            local crafterReq = crafterThresholds.crafter
            nextTierAt = type(crafterReq) == "table" and (crafterReq.crafts or 0) or 0
            currentFloor = 0
        elseif currentTier == "crafter" then
            local masterReq = crafterThresholds.master
            nextTierAt = type(masterReq) == "table" and (masterReq.crafts or 0) or 0
            local crafterReq = crafterThresholds.crafter
            currentFloor = type(crafterReq) == "table" and (crafterReq.crafts or 0) or 0
        else
            -- master (max tier) — show as 100%
            nextTierAt = completed
            local masterReq = crafterThresholds.master
            currentFloor = type(masterReq) == "table" and (masterReq.crafts or 0) or 0
        end

        local range = nextTierAt - currentFloor
        local progressInRange = completed - currentFloor
        local percent = range > 0 and math.min(100, math.floor(progressInRange / range * 100)) or 100

        return {
            tier = currentTier,
            progress = completed,
            nextTierAt = nextTierAt,
            progressPercent = percent,
        }
    end

    return nil
end
