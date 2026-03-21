------------------------------------------------------------------------
-- Vault of Truths - UI/ProgressionPanel.lua
-- Elegant popup showing track progression, rewards, and progress
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.ProgressionPanel = {}
local PP = GF.UI.ProgressionPanel

local T -- resolved lazily
local panel = nil

-- Tier info for display
local PVPER_TIERS = {
    {
        tier = "recruit", name = "Combatant", rank = 7,
        icon = "Interface\\Icons\\Achievement_PVP_P_01",
        color = "|cFF888888",
        rewards = {
            "Guild chat access",
            "PVP Supplies tab: 1 stack/day",
            "50g daily repairs",
        },
    },
    {
        tier = "member", name = "Gladiator", rank = 5,
        icon = "Interface\\Icons\\Achievement_BG_WinAB",
        color = "|cFF00FF00",
        threshold = 50000000, -- 5,000g
        rewards = {
            "PVP Supplies tab: 3 stacks/day",
            "200g daily repairs",
            "Higher profit share",
        },
    },
    {
        tier = "veteran", name = "Warlord", rank = 3,
        icon = "Interface\\Icons\\Achievement_PVP_P_15",
        color = "|cFFFFD700",
        threshold = 5000000000, -- 500,000g
        rewards = {
            "PVP Supplies tab: 5 stacks/day",
            "300g daily repairs",
            "Top-tier profit share",
            "Invite permissions",
        },
    },
}

local CRAFTER_TIERS = {
    {
        tier = "recruit", name = "Apprentice", rank = 6,
        icon = "Interface\\Icons\\Trade_Engineering",
        color = "|cFF888888",
        rewards = {
            "Crafting Mats T1: 2 stacks/day",
            "View T2 mats",
            "100g daily repairs",
            "PVP benefits at same tier",
        },
    },
    {
        tier = "crafter", name = "Artisan", rank = 4,
        icon = "Interface\\Icons\\INV_Hammer_20",
        color = "|cFF00AAFF",
        threshold = "25 crafts (80% reliable) OR 5,000g contributed",
        rewards = {
            "Crafting Mats T1: 5 stacks/day",
            "Crafting Mats T2: 2 stacks/day",
            "200g daily repairs",
            "Crafter profit share",
            "PVP benefits (Gladiator tier)",
        },
    },
    {
        tier = "master", name = "Grand Artisan", rank = 2,
        icon = "Interface\\Icons\\INV_Misc_Coin_17",
        color = "|cFFFFD700",
        threshold = "100 crafts (90% reliable) OR 500,000g contributed",
        rewards = {
            "Crafting Mats T1: 10 stacks/day",
            "Crafting Mats T2: 5 stacks/day",
            "PVP Supplies: 2 stacks/day",
            "300g daily repairs",
            "Deposit to Finished Goods tab",
            "PVP benefits (Warlord tier)",
        },
    },
}

local function CreatePanel()
    if panel then return end

    T = GF.UI.Theme

    panel = CreateFrame("Frame", "VaultOfTruthsProgressionPanel", UIParent, "BackdropTemplate")
    panel:SetSize(460, 500)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(0.05, 0.06, 0.09, 0.97)
    panel:SetBackdropBorderColor(0.15, 0.25, 0.4, 0.8)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:Hide()

    tinsert(UISpecialFrames, "VaultOfTruthsProgressionPanel")

    -- Drag
    local titleBar = CreateFrame("Frame", nil, panel)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() panel:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    -- Close
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -1, -1)
    closeBtn:SetSize(22, 22)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetText("|cFFFFCC00Your Progression|r")

    -- Player info line
    panel._playerInfo = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel._playerInfo:SetPoint("TOPLEFT", 12, -28)

    -- Scroll area for tier cards
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -48)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(content)
    panel._content = content

    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(w)
    end)
end

--- Build a tier card inside the content frame
local function BuildTierCard(parent, y, tierInfo, isCurrent, isCompleted, progressText)
    local card = T:Card(parent)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    card:SetHeight(0) -- will be computed

    -- Status indicator
    local statusIcon = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusIcon:SetPoint("TOPRIGHT", -10, -8)

    if isCompleted then
        statusIcon:SetText("|cFF00FF00COMPLETED|r")
    elseif isCurrent then
        statusIcon:SetText("|cFFFFAA00CURRENT|r")
    else
        statusIcon:SetText("|cFF555555LOCKED|r")
    end

    -- Icon
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 10, -8)
    icon:SetTexture(tierInfo.icon)
    if not isCurrent and not isCompleted then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.4)
    end

    -- Name + rank
    local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    nameText:SetText(tierInfo.color .. tierInfo.name .. "|r" ..
        "  |cFF666666(Rank: " .. (GF.RANK_NAMES[tierInfo.rank] or "?") .. ")|r")

    -- Threshold
    local threshText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    threshText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
    if tierInfo.threshold then
        if type(tierInfo.threshold) == "number" then
            threshText:SetText("|cFF888888Requires: " .. GF.Utils:FormatMoney(tierInfo.threshold) .. " contributed|r")
        else
            threshText:SetText("|cFF888888Requires: " .. tierInfo.threshold .. "|r")
        end
    else
        threshText:SetText("|cFF888888Starting tier|r")
    end

    -- Progress bar (only for current tier)
    local barHeight = 0
    if isCurrent and progressText then
        local barBg = card:CreateTexture(nil, "BACKGROUND")
        barBg:SetPoint("TOPLEFT", 10, -52)
        barBg:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        barBg:SetHeight(14)
        barBg:SetColorTexture(0.1, 0.1, 0.15, 0.8)

        local barFill = card:CreateTexture(nil, "ARTWORK")
        barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
        barFill:SetHeight(14)
        barFill:SetColorTexture(0.2, 0.5, 0.8, 0.8)

        -- Parse progress percent from stats
        local pct = progressText:match("(%d+)%%") or "0"
        pct = math.min(tonumber(pct) or 0, 100)
        barFill:SetWidth(math.max(1, (barBg:GetWidth() or 380) * pct / 100))

        local barText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        barText:SetPoint("CENTER", barBg, "CENTER", 0, 0)
        barText:SetText("|cFFFFFFFF" .. progressText .. "|r")

        barHeight = 20
    end

    -- Rewards
    local rewardY = -(52 + barHeight + 4)
    local rewardHeader = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rewardHeader:SetPoint("TOPLEFT", 10, rewardY)
    rewardHeader:SetText("|cFFFFCC00Rewards:|r")

    local rewardListY = rewardY - 14
    for i, reward in ipairs(tierInfo.rewards) do
        local line = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetPoint("TOPLEFT", 20, rewardListY - (i - 1) * 13)
        line:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        line:SetJustifyH("LEFT")
        if isCompleted or isCurrent then
            line:SetText("|cFF00FF00+|r " .. reward)
        else
            line:SetText("|cFF555555+|r |cFF555555" .. reward .. "|r")
        end
    end

    local totalHeight = math.abs(rewardListY) + #tierInfo.rewards * 13 + 12
    card:SetHeight(totalHeight)

    return totalHeight
end

--- Refresh the panel with current player data
function PP:Refresh()
    CreatePanel()

    local content = panel._content
    -- Clear existing content children
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local player = GF.Utils:GetPlayerFullName()
    local primaryTrack = GF.Roles:GetPrimaryTrack(player)

    if not primaryTrack then
        panel._playerInfo:SetText("|cFF888888No track selected. Use /vot to choose.|r")
        content:SetHeight(1)
        return
    end

    -- Determine which tier lists to show
    local tiers
    local trackLabel
    if primaryTrack == "crafter" then
        tiers = CRAFTER_TIERS
        trackLabel = "|cFF00AAFFCrafter Track|r"
    else
        tiers = PVPER_TIERS
        trackLabel = "|cFF00FF00PVPer Track|r"
    end

    local currentTier = GF.Roles:GetTrackTier(player, primaryTrack)
    panel._playerInfo:SetText(trackLabel .. "  —  Current: " ..
        (currentTier ~= "none" and currentTier or "none"))

    -- Build tier cards
    local y = 0
    local tierOrder
    if primaryTrack == "pvper" then
        tierOrder = { recruit = 1, member = 2, veteran = 3 }
    else
        tierOrder = { recruit = 1, crafter = 2, master = 3 }
    end
    local currentIndex = tierOrder[currentTier] or 0

    for i, tierInfo in ipairs(tiers) do
        local isCompleted = i < currentIndex + 1 and currentIndex > 0
        local isCurrent = (i == currentIndex + 1) or (i == 1 and currentIndex == 0)

        -- Get progress text for current tier
        local progressText = nil
        if isCurrent and GF.Progression then
            local stats = GF.Progression:GetTrackStats(player, primaryTrack)
            if stats and stats.progressPercent then
                if type(stats.nextTierAt) == "number" then
                    progressText = GF.Utils:FormatMoney(stats.progress) .. " / " ..
                        GF.Utils:FormatMoney(stats.nextTierAt) .. " (" .. math.floor(stats.progressPercent) .. "%)"
                else
                    progressText = math.floor(stats.progressPercent) .. "% complete"
                end
            end
        end

        if isCompleted then isCurrent = false end

        local cardHeight = BuildTierCard(content, y, tierInfo, isCurrent, isCompleted, progressText)
        y = y - cardHeight - 8
    end

    -- If crafter, also show PVP benefits note
    if primaryTrack == "crafter" then
        local note = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        note:SetPoint("TOPLEFT", 0, y - 4)
        note:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        note:SetText("|cFF888888As a crafter, you also receive PVP benefits at your equivalent tier.\nYour PVP tier upgrades automatically as your crafter rank increases.|r")
        note:SetJustifyH("LEFT")
        note:SetWordWrap(true)
        y = y - 36
    end

    content:SetHeight(math.abs(y) + 10)
end

function PP:Show()
    CreatePanel()
    self:Refresh()
    panel:Show()
end

function PP:Hide()
    if panel then panel:Hide() end
end

function PP:Toggle()
    CreatePanel()
    if panel:IsShown() then
        panel:Hide()
    else
        self:Show()
    end
end
