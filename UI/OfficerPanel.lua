------------------------------------------------------------------------
-- Vault of Truths - UI/OfficerPanel.lua
-- Officer-only: role management, payouts, sync status, recruitment
-- Layout: full-width vertical sections, no overlapping columns
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.OfficerPanel = {}
local OP = GF.UI.OfficerPanel

local initialized = false
local T -- resolved lazily

local function SectionHeader(parent, y, text)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 4, y)
    divider:SetPoint("RIGHT", -4, 0)
    divider:SetColorTexture(0.2, 0.35, 0.6, 0.6)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 8, y - 4)
    label:SetText("|cFFFFCC00" .. text .. "|r")
    return label
end

local function StatRow(block, y, label)
    local lbl = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 8, y)
    lbl:SetText(label)
    lbl:SetTextColor(0.6, 0.6, 0.6)
    local val = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("TOPRIGHT", -8, y)
    return val
end

local function Init()
    if initialized then return end

    T = GF.UI.Theme

    local parent = GF.UI.MainFrame:GetContentFrame("officer")
    if not parent then return end

    -- ===== HEADER =====
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 8, -6)
    header:SetText("|cFF33AAFFOfficer Panel|r")

    local permText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    permText:SetPoint("TOPRIGHT", -100, -10)
    parent._permText = permText

    -- Setup Guide button
    local setupBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    setupBtn:SetSize(90, 20)
    setupBtn:SetPoint("TOPRIGHT", -4, -6)
    setupBtn:SetText("Setup Guide")
    setupBtn:SetScript("OnClick", function()
        if GF.UI.SetupGuide and GF.UI.SetupGuide.Show then
            GF.UI.SetupGuide:Show()
        end
    end)

    -- ===== PROMOTIONS (top section — time-sensitive) =====
    SectionHeader(parent, -24, "Pending Promotions")

    local promoListFrame = CreateFrame("Frame", nil, parent)
    promoListFrame:SetPoint("TOPLEFT", 4, -42)
    promoListFrame:SetPoint("RIGHT", -4, 0)
    promoListFrame:SetHeight(70)

    local promoList = GF.UI.Widgets:CreateScrollList(promoListFrame, 22,
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 4, 0)
            row.nameText:SetWidth(100)
            row.nameText:SetJustifyH("LEFT")

            row.trackText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.trackText:SetPoint("LEFT", 108, 0)
            row.trackText:SetWidth(160)
            row.trackText:SetJustifyH("LEFT")

            row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.rankText:SetPoint("LEFT", 272, 0)
            row.rankText:SetWidth(120)
            row.rankText:SetTextColor(0, 0.9, 0.3)

            row.reason = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.reason:SetPoint("RIGHT", -4, 0)
            row.reason:SetWidth(160)
            row.reason:SetJustifyH("RIGHT")
            row.reason:SetTextColor(0.5, 0.5, 0.5)

            if index % 2 == 0 then
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(1, 1, 1, 0.02)
            end

            return row
        end,
        function(row, entry)
            row.nameText:SetText(entry.displayName or "")
            local trackColors = { pvper = "|cFF00FF00", crafter = "|cFF00AAFF" }
            local color = trackColors[entry.track] or "|cFFFFFFFF"
            row.trackText:SetText(color .. (entry.currentTier or "") .. " -> " .. (entry.newTier or "") .. "|r")
            row.rankText:SetText("-> " .. (GF.RANK_NAMES[entry.recommendedRank] or "?"))
            row.reason:SetText(entry.reason or "")
        end
    )
    parent._promoList = promoList

    -- ===== ROLE MANAGEMENT =====
    SectionHeader(parent, -118, "Role Management")

    local roleListFrame = CreateFrame("Frame", nil, parent)
    roleListFrame:SetPoint("TOPLEFT", 4, -136)
    roleListFrame:SetPoint("RIGHT", -4, 0)
    roleListFrame:SetHeight(100)

    local ROLE_KEYS = { GF.ROLES.PVPER, GF.ROLES.CRAFTER, GF.ROLES.AUCTIONEER }
    local ROLE_LABELS = { "PVP", "Craft", "AH" }
    local ROLE_COLORS = {
        [GF.ROLES.PVPER]      = { on = {0, 1, 0, 0.6}, off = {0.15, 0.15, 0.15, 0.4} },
        [GF.ROLES.CRAFTER]    = { on = {0, 0.67, 1, 0.6}, off = {0.15, 0.15, 0.15, 0.4} },
        [GF.ROLES.AUCTIONEER] = { on = {1, 0.67, 0, 0.6}, off = {0.15, 0.15, 0.15, 0.4} },
    }

    local roleList = GF.UI.Widgets:CreateScrollList(roleListFrame, 22,
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 4, 0)
            row.nameText:SetWidth(140)
            row.nameText:SetJustifyH("LEFT")

            row.roleButtons = {}
            for i, roleKey in ipairs(ROLE_KEYS) do
                local btn = CreateFrame("Button", nil, row)
                btn:SetSize(42, 16)
                btn:SetPoint("LEFT", 150 + (i - 1) * 50, 0)

                local bg = btn:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                btn._bg = bg

                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("CENTER")
                label:SetText(ROLE_LABELS[i])
                btn._label = label

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.15)

                btn.roleKey = roleKey
                row.roleButtons[roleKey] = btn
            end

            row.tierText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.tierText:SetPoint("RIGHT", -4, 0)
            row.tierText:SetWidth(50)

            if index % 2 == 0 then
                local stripe = row:CreateTexture(nil, "BACKGROUND")
                stripe:SetAllPoints()
                stripe:SetColorTexture(1, 1, 1, 0.02)
            end

            return row
        end,
        function(row, entry)
            row.nameText:SetText(entry.displayName)

            local isOfficer = GF.Roles:GetPermissionLevel() >= GF.PERMISSIONS.OFFICER
            local roles = GF.Roles:GetRoles(entry.fullName)

            for _, roleKey in ipairs(ROLE_KEYS) do
                local btn = row.roleButtons[roleKey]
                local active = roles[roleKey] == true
                local colors = ROLE_COLORS[roleKey]

                if active then
                    btn._bg:SetColorTexture(unpack(colors.on))
                    btn._label:SetTextColor(1, 1, 1)
                else
                    btn._bg:SetColorTexture(unpack(colors.off))
                    btn._label:SetTextColor(0.4, 0.4, 0.4)
                end

                btn:SetScript("OnClick", function()
                    if not isOfficer then
                        GF.ChatNotify:Error("Only officers can change roles.")
                        return
                    end
                    if active then
                        GF.Roles:RemoveRole(entry.fullName, roleKey)
                    else
                        GF.Roles:AssignRole(entry.fullName, roleKey)
                    end
                    OP:Refresh()
                end)
            end

            local rankName = GF.Roles:GetRecommendedRankName(entry.fullName) or "Newcomer"
            local rankIdx = GF.Roles:ResolveWoWRank(entry.fullName)
            local rankColors = {
                [0] = "|cFFFFD700", [1] = "|cFF00AAFF", [2] = "|cFFFFD700", [3] = "|cFFFFD700",
                [4] = "|cFF00AAFF", [5] = "|cFF00FF00", [6] = "|cFF00AAFF", [7] = "|cFF00FF00",
                [8] = "|cFF888888", [9] = "|cFF555555",
            }
            local color = rankColors[rankIdx] or "|cFFFFFFFF"
            row.tierText:SetText(color .. rankName .. "|r")
        end
    )
    parent._roleList = roleList

    -- ===== MAT DEBTS =====
    SectionHeader(parent, -244, "Mat Debts")

    local debtListFrame = CreateFrame("Frame", nil, parent)
    debtListFrame:SetPoint("TOPLEFT", 4, -262)
    debtListFrame:SetPoint("RIGHT", -4, 0)
    debtListFrame:SetHeight(88)

    local debtList = GF.UI.Widgets:CreateScrollList(debtListFrame, 22,
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 4, 0)
            row.nameText:SetWidth(100)
            row.nameText:SetJustifyH("LEFT")

            row.debtText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.debtText:SetPoint("LEFT", 108, 0)
            row.debtText:SetWidth(80)
            row.debtText:SetTextColor(1, 0.3, 0.3)

            row.creditText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.creditText:SetPoint("LEFT", 192, 0)
            row.creditText:SetWidth(80)
            row.creditText:SetTextColor(0, 0.9, 0.3)

            row.netText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.netText:SetPoint("LEFT", 276, 0)
            row.netText:SetWidth(80)

            -- Clear debt button
            row.clearBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.clearBtn:SetSize(50, 16)
            row.clearBtn:SetPoint("RIGHT", -4, 0)
            row.clearBtn:SetText("Clear")
            row.clearBtn:GetFontString():SetFont(row.clearBtn:GetFontString():GetFont(), 10)

            if index % 2 == 0 then
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(1, 1, 1, 0.02)
            end

            return row
        end,
        function(row, entry)
            row.nameText:SetText(entry.displayName)
            row.debtText:SetText("-" .. GF.Utils:FormatGold(entry.debt))
            row.creditText:SetText("+" .. GF.Utils:FormatGold(entry.credits))

            if entry.net < 0 then
                row.netText:SetText("|cFFFF4444-" .. GF.Utils:FormatGold(-entry.net) .. "|r")
            else
                row.netText:SetText("|cFF00FF00+" .. GF.Utils:FormatGold(entry.net) .. "|r")
            end

            row.clearBtn:SetScript("OnClick", function()
                GF.UI.Widgets:ShowConfirmDialog(
                    "Clear Mat Debt",
                    "Clear all mat debt for |cFFFFFFFF" .. entry.displayName .. "|r?\n" ..
                    "Net: " .. GF.Utils:FormatGold(math.abs(entry.net)) .. "\n\n" ..
                    "This marks the debt as settled.",
                    function()
                        GF.CrafterTracking:ClearMatDebt(entry.player)
                        OP:Refresh()
                    end
                )
            end)
        end
    )
    parent._debtList = debtList

    -- Debt column headers (inside the list frame, above rows)
    local debtHeaderRow = CreateFrame("Frame", nil, parent)
    debtHeaderRow:SetHeight(14)
    debtHeaderRow:SetPoint("BOTTOMLEFT", debtListFrame, "TOPLEFT", 0, 2)
    debtHeaderRow:SetPoint("BOTTOMRIGHT", debtListFrame, "TOPRIGHT", 0, 2)

    local colName = debtHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colName:SetPoint("LEFT", 4, 0)
    colName:SetText("|cFF888888Name|r")
    local colDebt = debtHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colDebt:SetPoint("LEFT", 108, 0)
    colDebt:SetText("|cFF888888Withdrawn|r")
    local colCredit = debtHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colCredit:SetPoint("LEFT", 192, 0)
    colCredit:SetText("|cFF888888Deposited|r")
    local colNet = debtHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colNet:SetPoint("LEFT", 276, 0)
    colNet:SetText("|cFF888888Net|r")

    -- Overdue allocations count (right of section header)
    local overdueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overdueText:SetPoint("BOTTOMRIGHT", debtHeaderRow, "TOPRIGHT", 0, 4)
    parent._overdueText = overdueText

    -- ===== BOTTOM ROW: 3 blocks side-by-side =====
    local bottomY = -358

    -- --- PAYOUTS (left third) ---
    SectionHeader(parent, bottomY, "Payouts")

    local payoutBlock = T:Card(parent)
    payoutBlock:SetPoint("TOPLEFT", 4, bottomY - 18)
    payoutBlock:SetPoint("RIGHT", parent, "LEFT", parent:GetWidth() * 0.38, 0)
    payoutBlock:SetPoint("BOTTOM", 0, 4)

    local payoutListFrame2 = CreateFrame("Frame", nil, payoutBlock)
    payoutListFrame2:SetPoint("TOPLEFT", 2, -2)
    payoutListFrame2:SetPoint("BOTTOMRIGHT", -2, 34)

    local payoutList = GF.UI.Widgets:CreateScrollList(payoutListFrame2, 22,
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame)

            row.player = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.player:SetPoint("LEFT", 4, 0)
            row.player:SetWidth(90)
            row.player:SetJustifyH("LEFT")

            row.balance = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.balance:SetPoint("RIGHT", -4, 0)
            row.balance:SetTextColor(1, 0.82, 0)

            if index % 2 == 0 then
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(1, 1, 1, 0.02)
            end

            return row
        end,
        function(row, entry)
            row.player:SetText(entry.player:match("^(.+)-") or entry.player)
            row.balance:SetText(GF.Utils:FormatGold(entry.balance))
        end
    )
    parent._payoutList = payoutList

    -- Liability + button at bottom of payout block
    local liabilityText = payoutBlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    liabilityText:SetPoint("BOTTOMLEFT", 6, 20)
    liabilityText:SetTextColor(0.6, 0.6, 0.6)
    parent._liabilityText = liabilityText

    local payoutBtn = CreateFrame("Button", nil, payoutBlock, "UIPanelButtonTemplate")
    payoutBtn:SetSize(110, 20)
    payoutBtn:SetPoint("BOTTOMLEFT", 4, 4)
    payoutBtn:SetText("Mail Payouts")
    payoutBtn:SetScript("OnClick", function()
        GF.UI.Widgets:ShowConfirmDialog(
            "Start Payouts",
            "Mail payouts to all eligible members?\nMailbox must be open.",
            function()
                local ok, err = GF.MailPayout:Start()
                if not ok then
                    GF.ChatNotify:Error(err or "Failed to start payouts")
                end
            end
        )
    end)

    -- --- SYNC STATUS (middle third) ---
    local syncLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncLabel:SetPoint("TOPLEFT", payoutBlock, "TOPRIGHT", 8, 18)
    syncLabel:SetText("|cFFFFCC00Sync Status|r")

    local syncBlock = T:Card(parent)
    syncBlock:SetPoint("TOPLEFT", payoutBlock, "TOPRIGHT", 4, 0)
    syncBlock:SetSize(180, 0)
    syncBlock:SetPoint("BOTTOM", 0, 4)

    parent._syncPeers     = StatRow(syncBlock, -4,  "Peers:")
    parent._syncVersion   = StatRow(syncBlock, -18, "Sync Ver:")
    parent._syncEntries   = StatRow(syncBlock, -32, "Entries:")
    parent._syncQueue     = StatRow(syncBlock, -46, "Queue:")
    parent._syncPending   = StatRow(syncBlock, -60, "Pending:")
    parent._syncLastRecv  = StatRow(syncBlock, -74, "Last Sync:")

    local forceSyncBtn = CreateFrame("Button", nil, syncBlock, "UIPanelButtonTemplate")
    forceSyncBtn:SetSize(76, 20)
    forceSyncBtn:SetPoint("BOTTOMLEFT", 4, 4)
    forceSyncBtn:SetText("Guild Sync")
    forceSyncBtn:SetScript("OnClick", function()
        GF.Sender:AnnounceVersion()
        GF.Sender:RequestSync()
        GF.Sender:RequestFullSync()
        GF.ChatNotify:Info("Guild sync requested.")
        C_Timer.After(3, function() OP:Refresh() end)
    end)

    -- Community Sync button (posts sync data to community chat — requires click)
    local commSyncBtn = CreateFrame("Button", nil, syncBlock, "UIPanelButtonTemplate")
    commSyncBtn:SetSize(76, 20)
    commSyncBtn:SetPoint("LEFT", forceSyncBtn, "RIGHT", 4, 0)
    commSyncBtn:SetText("Community")
    commSyncBtn:RegisterForClicks("LeftButtonUp")
    commSyncBtn:SetScript("OnClick", function()
        if GF.CommunityBridge and GF.CommunityBridge.ShowSyncCopyDialog then
            GF.CommunityBridge:ShowSyncCopyDialog()
        else
            GF.ChatNotify:Warning("Community sync not available.")
        end
    end)

    -- --- RECRUITMENT (right third) ---
    local recruitLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    recruitLabel:SetPoint("TOPLEFT", syncBlock, "TOPRIGHT", 8, 18)
    recruitLabel:SetText("|cFFFFCC00Recruitment|r")

    local recruitBlock = T:Card(parent)
    recruitBlock:SetPoint("TOPLEFT", syncBlock, "TOPRIGHT", 4, 0)
    recruitBlock:SetPoint("RIGHT", -4, 0)
    recruitBlock:SetPoint("BOTTOM", 0, 4)

    -- Guild Link
    local guildLinkBtn = CreateFrame("Button", nil, recruitBlock, "UIPanelButtonTemplate")
    guildLinkBtn:SetSize(120, 22)
    guildLinkBtn:SetPoint("TOPLEFT", 6, -6)
    guildLinkBtn:SetText("Guild Link")
    guildLinkBtn:RegisterForClicks("LeftButtonUp")

    local guildLinkPending = false
    guildLinkBtn:SetScript("OnClick", function()
        if guildLinkPending then return end
        guildLinkPending = true

        local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        if not clubId then
            GF.ChatNotify:Warning("Could not find guild club ID.")
            guildLinkPending = false
            return
        end

        -- Try multiple approaches to get the guild link
        local function TryGetLink()
            -- Method 1: GetRecruitmentChatLink (no params)
            if C_ClubFinder and C_ClubFinder.GetRecruitmentChatLink then
                local link = C_ClubFinder.GetRecruitmentChatLink()
                if link and link ~= "" then return link end
            end

            -- Method 2: GetClubFinderLink with GUID
            if GetClubFinderLink then
                local guildName = GetGuildInfo("player")
                if guildName then
                    -- Try to get the club finder GUID
                    local clubInfo = C_ClubFinder and C_ClubFinder.GetRecruitingClubInfoFromClubID and
                        C_ClubFinder.GetRecruitingClubInfoFromClubID(clubId)
                    if clubInfo and clubInfo.clubFinderGUID then
                        local link = GetClubFinderLink(clubInfo.clubFinderGUID, guildName)
                        if link and link ~= "" then return link end
                    end
                end
            end

            return nil
        end

        -- Request posting info first
        if C_ClubFinder and C_ClubFinder.RequestPostingInformationFromClubId then
            C_ClubFinder.RequestPostingInformationFromClubId(clubId)
        end

        -- Try immediately (might already be cached)
        local link = TryGetLink()
        if link then
            guildLinkPending = false
            ChatFrame_OpenChat(link)
            GF.ChatNotify:Success("Guild link pasted into chat.")
            return
        end

        -- Retry after server responds (try multiple delays)
        local attempts = 0
        local function RetryGetLink()
            attempts = attempts + 1
            local link = TryGetLink()
            if link then
                guildLinkPending = false
                ChatFrame_OpenChat(link)
                GF.ChatNotify:Success("Guild link pasted into chat.")
            elseif attempts < 3 then
                C_Timer.After(1, RetryGetLink)
            else
                guildLinkPending = false
                GF.ChatNotify:Warning("Could not generate link. Try opening Guild & Communities (J) first, then retry.")
            end
        end
        C_Timer.After(1, RetryGetLink)
    end)

    local linkHint = recruitBlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    linkHint:SetPoint("TOPLEFT", guildLinkBtn, "BOTTOMLEFT", 0, -2)
    linkHint:SetText("|cFF666666Pastes shareable link\ninto chat|r")
    linkHint:SetJustifyH("LEFT")

    -- Invite
    local inviteBtn = CreateFrame("Button", nil, recruitBlock, "UIPanelButtonTemplate")
    inviteBtn:SetSize(120, 22)
    inviteBtn:SetPoint("TOPLEFT", linkHint, "BOTTOMLEFT", 0, -8)
    inviteBtn:SetText("Invite Player")

    local inviteBox = CreateFrame("EditBox", nil, recruitBlock, "InputBoxTemplate")
    inviteBox:SetSize(110, 20)
    inviteBox:SetPoint("TOPLEFT", inviteBtn, "BOTTOMLEFT", 0, -4)
    inviteBox:SetAutoFocus(false)
    inviteBox:Hide()

    local inviteHint = recruitBlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inviteHint:SetPoint("TOPLEFT", inviteBtn, "BOTTOMLEFT", 0, -4)
    inviteHint:SetText("|cFF666666Player-Realm|r")

    inviteBtn:SetScript("OnClick", function()
        if inviteBox:IsShown() then
            local target = inviteBox:GetText()
            if target and target ~= "" then
                if not CanGuildInvite or not CanGuildInvite() then
                    GF.ChatNotify:Warning("No invite permission.")
                    return
                end
                GuildInvite(target)
                GF.ChatNotify:Success("Invite sent to " .. target)
                inviteBox:SetText("")
                inviteBox:Hide()
                inviteHint:Show()
                inviteBtn:SetText("Invite Player")
            end
        else
            inviteBox:Show()
            inviteBox:SetFocus()
            inviteHint:Hide()
            inviteBtn:SetText("Send Invite")
        end
    end)

    inviteBox:SetScript("OnEnterPressed", function() inviteBtn:Click() end)
    inviteBox:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:Hide(); self:ClearFocus()
        inviteHint:Show(); inviteBtn:SetText("Invite Player")
    end)

    -- Config hint at very bottom of recruit block
    local configHint = recruitBlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    configHint:SetPoint("BOTTOMLEFT", 6, 6)
    configHint:SetPoint("RIGHT", -6, 0)
    configHint:SetText("|cFF444444Config in Settings tab|r")
    configHint:SetJustifyH("LEFT")

    -- ===== GUILD OWNER ONLY: RESET DATA =====
    local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetBtn:SetSize(100, 20)
    resetBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    resetBtn:SetText("Reset All Data")
    resetBtn:GetFontString():SetTextColor(1, 0.3, 0.3)
    resetBtn:SetScript("OnClick", function()
        if not GF.Utils:IsGuildMaster() then
            GF.ChatNotify:Error("Only the Guild Owner can reset data.")
            return
        end
        GF.UI.Widgets:ShowConfirmDialog(
            "RESET ALL DATA",
            "|cFFFF0000WARNING: This will permanently erase:|r\n\n" ..
            "- All ledger entries (deposits, withdrawals)\n" ..
            "- All AH sale records\n" ..
            "- All item trails\n" ..
            "- All member balances & payouts\n" ..
            "- All mat debt records\n" ..
            "- All crafting order allocations\n\n" ..
            "|cFFFF4444This cannot be undone.|r\n" ..
            "Type |cFFFFD700RESET|r to confirm:",
            function()
                -- Double confirm via typed input
                OP:ShowResetConfirmInput()
            end
        )
    end)
    parent._resetBtn = resetBtn

    initialized = true
end

--- Show typed confirmation input for data reset (guild owner only)
function OP:ShowResetConfirmInput()
    local confirmFrame = CreateFrame("Frame", "VoTResetConfirm", UIParent, "BackdropTemplate")
    confirmFrame:SetSize(300, 100)
    confirmFrame:SetPoint("CENTER")
    confirmFrame:SetFrameStrata("DIALOG")
    confirmFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    confirmFrame:SetBackdropColor(0.1, 0.05, 0.05, 0.95)
    confirmFrame:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)

    local label = confirmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", 0, -12)
    label:SetText("|cFFFF4444Type RESET to erase all data:|r")

    local input = CreateFrame("EditBox", nil, confirmFrame, "InputBoxTemplate")
    input:SetSize(150, 22)
    input:SetPoint("CENTER", 0, -4)
    input:SetAutoFocus(true)

    local cancelBtn = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -10, 8)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() confirmFrame:Hide() end)

    input:SetScript("OnEnterPressed", function(self)
        if self:GetText() == "RESET" then
            confirmFrame:Hide()
            OP:ExecuteReset()
        else
            GF.ChatNotify:Error("Type RESET exactly to confirm.")
        end
    end)
    input:SetScript("OnEscapePressed", function() confirmFrame:Hide() end)
end

--- Execute full data reset (guild owner only)
function OP:ExecuteReset()
    if not GF.Utils:IsGuildMaster() then return end

    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    -- Reset ledger
    guildData.ledger.entries = {}
    guildData.ledger.nextSyncVersion = 1

    -- Reset AH sales
    guildData.ahSales = {}

    -- Reset item trails
    guildData.itemTrails = {}

    -- Reset member balances
    guildData.payouts = {}

    -- Reset mat debts
    guildData.matDebts = {}

    -- Reset crafting allocations
    guildData.matAllocations = {}

    -- Reset transaction log
    guildData.transactionLog = {}

    -- Reset bank snapshots
    guildData.bankSnapshots = { lastScan = 0, tabs = {} }

    -- Keep guild settings, member records (roles/tracks), and orders intact
    GF.ChatNotify:Success("ALL DATA RESET. Ledger, sales, trails, balances, and debts cleared.")
    GF.ChatNotify:Warning("Member roles and guild settings were preserved.")

    OP:Refresh()
end

--- Refresh the officer panel
function OP:Refresh()
    Init()

    local parent = GF.UI.MainFrame:GetContentFrame("officer")
    if not parent then return end

    -- Permission display
    local permLevel = GF.Roles:GetPermissionLevel()
    if permLevel == GF.PERMISSIONS.OWNER then
        parent._permText:SetText("|cFFFFD700Owner|r")
    elseif permLevel == GF.PERMISSIONS.OFFICER then
        parent._permText:SetText("|cFF00AAFFOfficer|r")
    else
        parent._permText:SetText("|cFF888888Member|r")
    end

    -- Reset button — guild owner only
    if parent._resetBtn then
        if GF.Utils:IsGuildMaster() then
            parent._resetBtn:Show()
        else
            parent._resetBtn:Hide()
        end
    end

    -- Promotion queue
    if parent._promoList and GF.Progression then
        local promoQueue = GF.Progression:GetPromotionQueue()
        if #promoQueue == 0 then
            parent._promoList:SetData({
                { displayName = "No pending promotions", track = "", currentTier = "", newTier = "", recommendedRank = nil, reason = "" }
            })
        else
            parent._promoList:SetData(promoQueue)
        end
    end

    -- Payout queue
    local queue = GF.Payouts:GetPayoutQueue()
    parent._payoutList:SetData(queue)

    local liability = GF.Payouts:GetTotalLiability()
    parent._liabilityText:SetText(GF.Utils:FormatGold(liability) .. " (" .. #queue .. ")")

    -- Sync status
    if parent._syncPeers then
        local peerCount = GF.Receiver:GetPeerCount()
        parent._syncPeers:SetText(peerCount > 0 and ("|cFF00FF00" .. peerCount .. "|r") or "|cFFFF00000|r")

        local guildData = GF.Settings:GetGuildData()
        if guildData then
            parent._syncVersion:SetText(tostring(guildData.ledger.nextSyncVersion - 1))
            parent._syncEntries:SetText(tostring(#guildData.ledger.entries))
        else
            parent._syncVersion:SetText("—")
            parent._syncEntries:SetText("0")
        end

        parent._syncQueue:SetText(tostring(GF.Sender:GetQueueSize()))

        local pendingCount = GF.Sender:GetPendingCount()
        if pendingCount > 0 then
            parent._syncPending:SetText("|cFFFFAA00" .. pendingCount .. "|r")
        else
            parent._syncPending:SetText("|cFF00FF000|r")
        end

        local peers = GF.Receiver:GetOnlinePeers()
        local latestSeen = 0
        for _, peer in pairs(peers) do
            if peer.lastSeen and peer.lastSeen > latestSeen then
                latestSeen = peer.lastSeen
            end
        end
        parent._syncLastRecv:SetText(latestSeen > 0 and GF.Utils:FormatRelativeTime(latestSeen) or "|cFF666666Never|r")
    end

    -- Mat debts
    if parent._debtList and GF.CrafterTracking then
        local debts = GF.CrafterTracking:GetAllMatDebts()
        if #debts == 0 then
            parent._debtList:SetData({
                { displayName = "No outstanding debts", player = "", debt = 0, credits = 0, net = 0 }
            })
        else
            parent._debtList:SetData(debts)
        end

        -- Overdue allocation count
        local overdueCount = 0
        local guildData = GF.Settings:GetGuildData()
        if guildData and guildData.matAllocations then
            local now = GF.Utils:GetTime()
            for orderID, alloc in pairs(guildData.matAllocations) do
                if alloc.deadline and now > alloc.deadline then
                    local order = GF.OrderBoard:GetOrder(orderID)
                    if order and order.status == GF.ORDER_STATUS.ACCEPTED then
                        overdueCount = overdueCount + 1
                    end
                end
            end
        end

        if overdueCount > 0 then
            parent._overdueText:SetText("|cFFFF4444" .. overdueCount .. " overdue order(s)|r")
        else
            parent._overdueText:SetText("|cFF00FF00No overdue|r")
        end
    end

    -- Role management
    if IsInGuild() then
        C_GuildInfo.GuildRoster()
        local rosterData = {}
        local numTotal = GetNumGuildMembers()
        for i = 1, numTotal do
            local name, rankName, rankIndex, level, classDisplayName,
                  zone, publicNote, officerNote, isOnline = GetGuildRosterInfo(i)
            if name then
                rosterData[#rosterData + 1] = {
                    fullName = name,
                    displayName = name:match("^(.+)-") or name,
                    rank = rankName,
                    online = isOnline,
                }
            end
        end
        table.sort(rosterData, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.displayName < b.displayName
        end)
        parent._roleList:SetData(rosterData)
    else
        parent._roleList:SetData({})
    end
end

--- Open payouts directly (from slash command)
function OP:ShowPayouts()
    GF.UI.MainFrame:Show()
end
