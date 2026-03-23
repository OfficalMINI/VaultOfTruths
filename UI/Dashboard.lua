------------------------------------------------------------------------
-- Vault of Truths - UI/Dashboard.lua
-- Member dashboard: how it works, stats, suggestions, activity
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.Dashboard = {}
local Dash = GF.UI.Dashboard
local T -- resolved lazily

local initialized = false

local function Init()
    if initialized then return end

    T = GF.UI.Theme
    local C = T.COLORS

    local parent = GF.UI.MainFrame:GetContentFrame("dashboard")
    if not parent then return end

    -- ================================================================
    -- HOW IT WORKS  (full-width card across the top)
    -- ================================================================
    local _, howHeader = T:SectionHeader(parent,
        { "TOPLEFT", parent, "TOPLEFT", 6, -6 },
        "How It Works",
        "Interface\\Icons\\INV_Misc_Book_09")

    -- Guild Info button (opens the detailed info panel)
    local infoBtn = T:Button(parent, "Guild Info", 70, 18)
    infoBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -6)
    infoBtn:SetScript("OnClick", function()
        if GF.UI.GuildInfoPanel then GF.UI.GuildInfoPanel:Toggle() end
    end)

    local howCard = T:Card(parent)
    howCard:SetPoint("TOPLEFT", howHeader, "BOTTOMLEFT", -6, -4)
    howCard:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    howCard:SetHeight(58)

    local steps = {
        { icon = "Interface\\Icons\\Achievement_BG_WinAB",            label = "PVP",      color = C.positive   },
        { icon = "Interface\\Icons\\INV_Misc_Bag_10_Green",           label = "Deposit",   color = C.accent     },
        { icon = "Interface\\Icons\\Trade_Engineering",               label = "Craft",     color = C.accent     },
        { icon = "Interface\\Icons\\INV_Misc_Coin_02",                label = "AH Sell",   color = C.gold       },
        { icon = "Interface\\Icons\\INV_Misc_Coin_17",                label = "Split",     color = C.warning    },
        { icon = "Interface\\Icons\\Spell_Holy_BlessingOfProtection", label = "Get Paid",  color = C.positive   },
    }

    local prevElement = nil
    for i, step in ipairs(steps) do
        -- Arrow separator between steps
        if i > 1 then
            local arrow = howCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            arrow:SetPoint("LEFT", prevElement, "RIGHT", 4, 6)
            arrow:SetText("|cFF555555>|r")
            prevElement = arrow
        end

        local stepFrame = CreateFrame("Frame", nil, howCard)
        stepFrame:SetSize(60, 50)
        if i == 1 then
            stepFrame:SetPoint("LEFT", howCard, "LEFT", 12, 0)
        else
            stepFrame:SetPoint("LEFT", prevElement, "RIGHT", 4, -6)
        end

        local iconTex = stepFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(26, 26)
        iconTex:SetPoint("TOP", 0, -2)
        iconTex:SetTexture(step.icon)
        if iconTex.SetMask then
            iconTex:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end

        local label = stepFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", iconTex, "BOTTOM", 0, -2)
        label:SetText(step.label)
        label:SetTextColor(step.color[1], step.color[2], step.color[3])

        prevElement = stepFrame
    end

    -- ================================================================
    -- YOUR STATS  (left column card)
    -- ================================================================
    local _, statsHeader = T:SectionHeader(parent,
        { "TOPLEFT", howCard, "BOTTOMLEFT", 6, -10 },
        "Your Stats",
        "Interface\\Icons\\INV_Misc_Spyglass_03")

    -- Track progress bar (compact, above stats card)
    local progressCard = T:Card(parent)
    progressCard:SetPoint("TOPLEFT", statsHeader, "BOTTOMLEFT", -6, -4)
    progressCard:SetPoint("RIGHT", parent, "CENTER", -4, 0)
    progressCard:SetHeight(32)

    parent._trackLabel = progressCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    parent._trackLabel:SetPoint("TOPLEFT", 10, -4)
    parent._trackLabel:SetText("")

    -- Progress bar background
    local barBg = progressCard:CreateTexture(nil, "BACKGROUND")
    barBg:SetPoint("TOPLEFT", 10, -16)
    barBg:SetPoint("RIGHT", progressCard, "RIGHT", -70, 0)
    barBg:SetHeight(10)
    barBg:SetColorTexture(0.1, 0.1, 0.15, 0.8)
    parent._progressBarBg = barBg

    local barFill = progressCard:CreateTexture(nil, "ARTWORK")
    barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    barFill:SetHeight(10)
    barFill:SetWidth(1)
    barFill:SetColorTexture(0.2, 0.5, 0.8, 0.9)
    parent._progressBarFill = barFill

    local barPct = progressCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barPct:SetPoint("LEFT", barBg, "RIGHT", 4, 0)
    barPct:SetTextColor(0.7, 0.7, 0.7)
    parent._progressPct = barPct

    -- View details button
    local viewBtn = CreateFrame("Button", nil, progressCard)
    viewBtn:SetSize(16, 16)
    viewBtn:SetPoint("RIGHT", -6, 0)
    local viewIcon = viewBtn:CreateTexture(nil, "ARTWORK")
    viewIcon:SetAllPoints()
    viewIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    viewIcon:SetAlpha(0.6)
    viewBtn:SetScript("OnEnter", function() viewIcon:SetAlpha(1) end)
    viewBtn:SetScript("OnLeave", function() viewIcon:SetAlpha(0.6) end)
    viewBtn:SetScript("OnClick", function()
        if GF.UI.ProgressionPanel then GF.UI.ProgressionPanel:Toggle() end
    end)

    local statsCard = T:Card(parent)
    statsCard:SetPoint("TOPLEFT", progressCard, "BOTTOMLEFT", 0, -4)
    statsCard:SetPoint("RIGHT", parent, "CENTER", -4, 0)
    statsCard:SetHeight(170)

    -- Stat rows inside the card
    local ROW_H   = 14
    local PAD_TOP = -7
    parent._roleVal        = T:StatRow(statsCard, PAD_TOP,              "Role:")
    parent._tierVal        = T:StatRow(statsCard, PAD_TOP - ROW_H,      "Rank:")
    parent._shareVal       = T:StatRow(statsCard, PAD_TOP - ROW_H * 2,  "Share:")
    parent._contributedVal = T:StatRow(statsCard, PAD_TOP - ROW_H * 3,  "Contributed:")

    -- Divider between contributions and earnings
    T:Divider(statsCard, PAD_TOP - ROW_H * 4 + 3)

    parent._pendingVal     = T:StatRow(statsCard, PAD_TOP - ROW_H * 4,  "Pending Sale:")
    parent._soldUnpaidVal  = T:StatRow(statsCard, PAD_TOP - ROW_H * 5,  "Profit Earned:")
    parent._crafterVal     = T:StatRow(statsCard, PAD_TOP - ROW_H * 6,  "Crafter Earnings:")
    parent._ahVal          = T:StatRow(statsCard, PAD_TOP - ROW_H * 7,  "AH Earnings:")
    parent._totalPaidVal   = T:StatRow(statsCard, PAD_TOP - ROW_H * 8,  "Total Paid Out:")

    T:Divider(statsCard, PAD_TOP - ROW_H * 9 + 3)
    parent._balanceVal     = T:StatRow(statsCard, PAD_TOP - ROW_H * 9,  "Available:")

    -- ================================================================
    -- GUILD TOTALS  (right column card, aligned with stats)
    -- ================================================================
    local _, guildHeaderContainer = T:SectionHeader(parent,
        { "TOPLEFT", parent, "TOP", 2, -(58 + 18 + 10 + 6) },
        "Guild Totals",
        "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")

    local guildCard = T:Card(parent)
    guildCard:SetPoint("TOPLEFT", guildHeaderContainer, "BOTTOMLEFT", 0, -4)
    guildCard:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    guildCard:SetHeight(120)

    parent._gTotalContrib = T:StatRow(guildCard, PAD_TOP,              "Contributions:")
    parent._gPending      = T:StatRow(guildCard, PAD_TOP - ROW_H,      "Pending Payouts:")
    parent._gMembers      = T:StatRow(guildCard, PAD_TOP - ROW_H * 2,  "Members:")
    parent._gOrders       = T:StatRow(guildCard, PAD_TOP - ROW_H * 3,  "Open Orders:")
    parent._gAHSales      = T:StatRow(guildCard, PAD_TOP - ROW_H * 4,  "AH Sales:")

    T:DividerBelow(guildCard, parent._gAHSales, 6)

    local splitLabel = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    splitLabel:SetPoint("TOPLEFT", 10, PAD_TOP - ROW_H * 5 - 4)
    splitLabel:SetText("Profit Split:")
    splitLabel:SetTextColor(unpack(C.textDim))

    parent._splitDisplay = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    parent._splitDisplay:SetPoint("TOPRIGHT", -10, PAD_TOP - ROW_H * 5 - 4)
    parent._splitDisplay:SetTextColor(unpack(C.gold))

    -- ================================================================
    -- DAILY TASKS  (left column, below stats card)
    -- ================================================================
    local _, taskHeader = T:SectionHeader(parent,
        { "TOPLEFT", statsCard, "BOTTOMLEFT", 6, -10 },
        "Daily Tasks",
        "Interface\\Icons\\INV_Misc_Note_05")

    local taskCard = T:Card(parent)
    taskCard:SetPoint("TOPLEFT", taskHeader, "BOTTOMLEFT", -6, -4)
    taskCard:SetPoint("RIGHT", parent, "CENTER", -4, 0)
    taskCard:SetPoint("BOTTOM", parent, "BOTTOM", 0, 6)

    parent._suggestList = GF.UI.Widgets:CreateScrollList(taskCard, 44,
        function(index, contentFrame)
            local row = T:Card(contentFrame)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(26, 26)
            row.icon:SetPoint("LEFT", 8, 0)

            row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.title:SetPoint("TOPLEFT", 40, -4)
            row.title:SetPoint("RIGHT", -8, 0)
            row.title:SetJustifyH("LEFT")
            row.title:SetTextColor(unpack(C.headerGold))

            row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.desc:SetPoint("TOPLEFT", 40, -18)
            row.desc:SetPoint("BOTTOMRIGHT", -8, 3)
            row.desc:SetJustifyH("LEFT")
            row.desc:SetJustifyV("TOP")
            row.desc:SetTextColor(unpack(C.textDim))
            row.desc:SetWordWrap(true)

            return row
        end,
        function(row, entry)
            row.title:SetText(entry.title)
            row.desc:SetText(entry.description)
            if entry.icon then
                row.icon:SetTexture(entry.icon)
                row.icon:Show()
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
        end
    )

    -- ================================================================
    -- RECENT ACTIVITY  (right column, below guild totals card)
    -- ================================================================
    local _, actHeader = T:SectionHeader(parent,
        { "TOPLEFT", guildCard, "BOTTOMLEFT", 6, -10 },
        "Recent Activity",
        "Interface\\Icons\\INV_Scroll_11")

    local actCard = T:Card(parent)
    actCard:SetPoint("TOPLEFT", actHeader, "BOTTOMLEFT", -6, -4)
    actCard:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    actCard:SetPoint("BOTTOM", parent, "BOTTOM", 0, 6)

    parent._activityList = GF.UI.Widgets:CreateScrollList(actCard, 20,
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame)
            T:StripeRow(row, index)

            row.action = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.action:SetPoint("LEFT", 6, 0)
            row.action:SetWidth(50)

            row.player = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.player:SetPoint("LEFT", 58, 0)
            row.player:SetWidth(70)

            row.item = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.item:SetPoint("LEFT", 130, 0)
            row.item:SetPoint("RIGHT", -60, 0)
            row.item:SetJustifyH("LEFT")
            row.item:SetTextColor(unpack(C.textNormal))

            row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.value:SetPoint("RIGHT", -6, 0)
            row.value:SetWidth(55)
            row.value:SetJustifyH("RIGHT")
            row.value:SetTextColor(unpack(C.gold))

            return row
        end,
        function(row, entry)
            -- Color-code action
            local actionColors = {
                [GF.ACTIONS.DEPOSIT] = "|cFF00FF00",
                [GF.ACTIONS.WITHDRAW] = "|cFFFF4444",
                [GF.ACTIONS.PAYOUT] = "|cFFFFAA00",
                [GF.ACTIONS.FEE] = "|cFF00AAFF",
                [GF.ACTIONS.AH_SALE] = "|cFFFFD700",
                [GF.ACTIONS.AH_RETURN] = "|cFF00FF88",
                [GF.ACTIONS.CRAFT_WITHDRAW] = "|cFFFF8800",
                [GF.ACTIONS.CRAFT_DEPOSIT] = "|cFF00AAFF",
            }
            local actionColor = actionColors[entry.action] or "|cFFFFFFFF"
            row.action:SetText(actionColor .. (entry.action or "") .. "|r")

            row.player:SetText(entry.player:match("^(.+)-") or entry.player)

            -- Show item name if available
            local itemText = ""
            if entry.items and #entry.items > 0 then
                local firstItem = entry.items[1]
                if firstItem.itemID then
                    local name, link = C_Item.GetItemInfo(firstItem.itemID)
                    local qty = firstItem.quantity or firstItem.count or 1
                    if link then
                        itemText = link
                        if qty > 1 then itemText = itemText .. " x" .. qty end
                    elseif name then
                        itemText = name
                        if qty > 1 then itemText = itemText .. " x" .. qty end
                    end
                    if #entry.items > 1 then
                        itemText = itemText .. " +" .. (#entry.items - 1)
                    end
                end
            elseif entry.note and entry.note ~= "" then
                -- Fallback to note (e.g. "AH profit return to guild bank")
                itemText = entry.note
            end
            row.item:SetText(itemText)

            row.value:SetText(GF.Utils:FormatGold(entry.totalValue))
        end
    )

    initialized = true
end

--- Refresh all dashboard data
function Dash:Refresh()
    Init()

    local parent = GF.UI.MainFrame:GetContentFrame("dashboard")
    if not parent then return end

    local player = GF.Utils:GetPlayerFullName()
    local inGuild = IsInGuild()

    -- Track progress bar
    if parent._trackLabel and inGuild then
        local primaryTrack = GF.Roles:GetPrimaryTrack(player)
        if primaryTrack and GF.Progression then
            local stats = GF.Progression:GetTrackStats(player, primaryTrack)
            local trackColors = { pvper = "|cFF00FF00", crafter = "|cFF00AAFF" }
            local tierName = GF.Roles:GetTrackTier(player, primaryTrack)
            parent._trackLabel:SetText((trackColors[primaryTrack] or "") .. primaryTrack:upper() .. "|r — " .. (tierName or "none"))
            if stats and stats.progressPercent then
                local pct = math.min(math.floor(stats.progressPercent), 100)
                parent._progressPct:SetText(pct .. "%")
                local barWidth = parent._progressBarBg:GetWidth()
                if barWidth and barWidth > 0 then
                    parent._progressBarFill:SetWidth(math.max(1, barWidth * pct / 100))
                end
            else
                parent._progressPct:SetText("MAX")
                parent._progressBarFill:SetWidth(parent._progressBarBg:GetWidth() or 1)
            end
        else
            parent._trackLabel:SetText("|cFF888888No track selected — /vot progress|r")
            parent._progressPct:SetText("")
            parent._progressBarFill:SetWidth(1)
        end
    end

    -- Your stats
    parent._roleVal:SetText(inGuild and GF.Roles:GetRoleDisplay(player) or "|cFF888888No Role|r")
    -- Show track rank instead of legacy tier
    local trackRankName = inGuild and GF.Roles:GetRecommendedRankName(player) or "N/A"
    parent._tierVal:SetText("|cFFFFD700" .. trackRankName .. "|r")

    local share, playerTotal, guildTotal = 0, 0, 0
    if inGuild then
        share, playerTotal, guildTotal = GF.Ledger:GetContributionShare(player)
    end
    parent._shareVal:SetText(share .. "% (" .. GF.Utils:FormatGold(playerTotal) .. ")")

    -- Calculate pending deposits (items deposited but not yet sold)
    local pendingValue = 0
    local soldUnpaidValue = 0
    if inGuild then
        local entries = GF.Ledger:GetRecent(500)
        for _, e in ipairs(entries) do
            if e.player == player and e.action == GF.ACTIONS.DEPOSIT then
                if e.status == "pending" then
                    pendingValue = pendingValue + (e.totalValue or 0)
                elseif e.status == "credited" then
                    -- credited but check if paid out yet
                end
            end
        end
    end

    if parent._pendingVal then
        if pendingValue > 0 then
            parent._pendingVal:SetText("|cFFFFAA00" .. GF.Utils:FormatMoney(pendingValue) .. "|r")
        else
            parent._pendingVal:SetText("|cFF8888880g|r")
        end
    end

    -- Show raw contribution value (deposits — separate from earnings)
    if parent._contributedVal then
        local record2 = inGuild and GF.Payouts:GetRecord(player) or nil
        if record2 and record2.totalContributed > 0 then
            parent._contributedVal:SetText("|cFF00AAFF" .. GF.Utils:FormatMoney(record2.totalContributed) .. "|r")
        else
            parent._contributedVal:SetText("|cFF8888880g|r")
        end
    end

    local record = inGuild and GF.Payouts:GetRecord(player) or nil
    if record then
        -- Earnings = profit shares from sales (NOT raw deposit value)
        local contributorEarnings = record.contributorEarnings or 0
        local crafterEarnings = record.crafterEarnings or 0
        local auctioneerEarnings = record.auctioneerEarnings or 0
        local totalEarnings = contributorEarnings + crafterEarnings + auctioneerEarnings

        -- Factor in mat debt from crafting withdrawals
        local matDebt = 0
        if GF.CrafterTracking then
            local matBalance = GF.CrafterTracking:GetMatBalance(myName)
            if matBalance < 0 then
                matDebt = math.abs(matBalance)
            end
        end

        local available = totalEarnings - record.totalPaidOut - matDebt

        -- Sold (unpaid) = earnings not yet paid out
        soldUnpaidValue = math.max(0, totalEarnings - record.totalPaidOut)

        if parent._soldUnpaidVal then
            if contributorEarnings > 0 then
                parent._soldUnpaidVal:SetText("|cFF00FF00" .. GF.Utils:FormatMoney(contributorEarnings) .. "|r")
            else
                parent._soldUnpaidVal:SetText("|cFF8888880g|r")
            end
        end

        parent._crafterVal:SetText(GF.Utils:FormatMoney(crafterEarnings))
        parent._ahVal:SetText(GF.Utils:FormatMoney(auctioneerEarnings))
        parent._totalPaidVal:SetText(GF.Utils:FormatMoney(record.totalPaidOut))
        if available < 0 then
            parent._balanceVal:SetText("|cFFFF4444-" .. GF.Utils:FormatMoney(math.abs(available)) .. "|r")
        else
            parent._balanceVal:SetText("|cFF00FF00" .. GF.Utils:FormatMoney(available) .. "|r")
        end
    else
        if parent._soldUnpaidVal then parent._soldUnpaidVal:SetText("|cFF8888880g|r") end
        parent._crafterVal:SetText("0g")
        parent._ahVal:SetText("0g")
        parent._totalPaidVal:SetText("0g")
        parent._balanceVal:SetText("0g")
    end

    -- Guild totals
    local summary = inGuild and GF.Payouts:GetSummary() or { totalPending = 0, memberCount = 0 }
    parent._gTotalContrib:SetText(GF.Utils:FormatGold(guildTotal))
    parent._gPending:SetText(GF.Utils:FormatMoney(summary.totalPending))
    parent._gMembers:SetText(tostring(summary.memberCount))

    local openOrders = inGuild and GF.OrderBoard:GetOrders(GF.ORDER_STATUS.OPEN) or {}
    parent._gOrders:SetText(tostring(#openOrders))

    local ahSummary = inGuild and GF.SalesLedger:GetSummary() or { totalSales = 0 }
    parent._gAHSales:SetText(GF.Utils:FormatGold(ahSummary.totalSales))

    -- Profit split display
    if parent._splitDisplay then
        local guildData = inGuild and GF.Settings:GetGuildData() or nil
        if guildData then
            local s = guildData.guildSettings.profitSplit or GF.DEFAULT_PROFIT_SPLIT
            parent._splitDisplay:SetText(s.contributors .. "/" .. s.crafters .. "/" .. s.auctioneers .. "/" .. s.guildTax)
        else
            parent._splitDisplay:SetText("50/15/10/25")
        end
    end

    -- Daily suggestions
    if GF.DailyActivities and parent._suggestList then
        parent._suggestList:SetData(GF.DailyActivities:GetSuggestions())
    end

    -- Recent activity
    local entries = inGuild and GF.Ledger:GetRecent(50) or {}
    if #entries == 0 then
        -- Show placeholder entries so the list isn't blank
        parent._activityList:SetData({
            { timestamp = time(), action = "—", player = "No activity yet", totalValue = 0 },
        })
    else
        parent._activityList:SetData(entries)
    end
end
