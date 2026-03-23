------------------------------------------------------------------------
-- Vault of Truths - UI/AHPanel.lua
-- AH account view: pending sales, profit return queue, fund breakdown
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.AHPanel = {}
local AHP = GF.UI.AHPanel
local T -- resolved on first Init

local initialized = false

local function Init()
    if initialized then return end

    T = GF.UI.Theme
    local parent = GF.UI.MainFrame:GetContentFrame("ah")
    if not parent then return end

    local PAD = 12
    local INNER = 10

    ---------- Section: Header ----------
    local _, headerContainer = T:SectionHeader(
        parent,
        { "TOPLEFT", parent, "TOPLEFT", PAD, -PAD },
        "Auction House",
        "Interface\\ICONS\\INV_Misc_Coin_01"
    )
    headerContainer:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)

    ---------- Section: Stats Card ----------
    local statsCard = T:Card(parent)
    statsCard:SetPoint("TOPLEFT", headerContainer, "BOTTOMLEFT", 0, -INNER)
    statsCard:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
    statsCard:SetHeight(126)

    parent._totalSales    = T:StatRow(statsCard, -INNER,       "Total Sales:")
    parent._totalProfit   = T:StatRow(statsCard, -INNER - 16,  "Total Profit:")
    parent._pendingProfit = T:StatRow(statsCard, -INNER - 32,  "Undistributed:")
    parent._pendingCount  = T:StatRow(statsCard, -INNER - 48,  "Pending Sales:")

    T:Divider(statsCard, -INNER - 62)
    parent._ahReturned    = T:StatRow(statsCard, -INNER - 68,  "Returned to GB:")
    parent._ahOwed        = T:StatRow(statsCard, -INNER - 84,  "Owed to Guild Bank:")

    ---------- Section: Recent Sales ----------
    local _, salesHeaderContainer = T:SectionHeader(
        parent,
        { "TOPLEFT", statsCard, "BOTTOMLEFT", 0, -PAD },
        "Recent Sales",
        "Interface\\ICONS\\INV_Misc_Note_01"
    )
    salesHeaderContainer:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)

    local divider = T:DividerBelow(parent, salesHeaderContainer, 4)

    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -6)
    listFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAD, 56)

    local list = GF.UI.Widgets:CreateScrollList(listFrame, 24,
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame)
            row:EnableMouse(true)

            row.time = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.time:SetPoint("LEFT", 4, 0)
            row.time:SetWidth(70)
            row.time:SetTextColor(unpack(T.COLORS.textDim))

            row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.item:SetPoint("LEFT", 78, 0)
            row.item:SetWidth(120)

            row.sale = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.sale:SetPoint("LEFT", 202, 0)
            row.sale:SetWidth(80)
            row.sale:SetTextColor(unpack(T.COLORS.gold))

            row.profit = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.profit:SetPoint("LEFT", 286, 0)
            row.profit:SetWidth(80)

            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.status:SetPoint("RIGHT", -4, 0)

            -- Item tooltip on hover
            row:SetScript("OnEnter", function(self)
                if self._itemID and self._itemID > 0 then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self._itemID)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            T:StripeRow(row, index)

            return row
        end,
        function(row, sale)
            row.time:SetText(GF.Utils:FormatRelativeTime(sale.timestamp))
            row._itemID = sale.itemID

            -- Resolve item name: use stored link/name, or fetch on demand
            local displayName = sale.itemLink or sale.itemName
            if not displayName or displayName == "" then
                local name, link = C_Item.GetItemInfo(sale.itemID or 0)
                displayName = link or name
                -- Backfill the sale record so it's resolved for next time
                if name then sale.itemName = name end
                if link then sale.itemLink = link end
            end
            displayName = displayName or ("Item:" .. (sale.itemID or "?"))

            local qtyStr = sale.quantity > 1 and (" x" .. sale.quantity) or ""
            row.item:SetText(displayName .. qtyStr)

            row.sale:SetText(GF.Utils:FormatGold(sale.salePrice))

            if sale.profit > 0 then
                row.profit:SetText("|cFF00FF00+" .. GF.Utils:FormatGold(sale.profit) .. "|r")
            else
                row.profit:SetText("|cFFFF0000" .. GF.Utils:FormatGold(sale.profit) .. "|r")
            end

            row.status:SetText(sale.distributed and "|cFF00FF00Paid|r" or "|cFFFFAA00Undistributed|r")
        end
    )
    parent._salesList = list

    ---------- Section: Action Buttons ----------
    local actionBar = T:Card(parent)
    actionBar:SetHeight(44)
    actionBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", PAD, PAD)
    actionBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAD, PAD)

    local distributeBtn = T:ActionButton(actionBar, "Distribute All", 150, 28)
    distributeBtn:SetPoint("LEFT", INNER, 0)
    distributeBtn:SetScript("OnClick", function()
        local pendingCount = GF.SalesLedger:GetPendingSalesCount()
        if pendingCount == 0 then
            GF.ChatNotify:Warning("No pending sales to distribute.")
            return
        end
        GF.UI.Widgets:ShowConfirmDialog(
            "Distribute Profits",
            "Distribute " .. pendingCount .. " pending sale profit(s) to contributors, crafters, and auctioneers?",
            function()
                local count, totalProfit = GF.SalesLedger:DistributeAllPending()
                AHP:Refresh()
            end
        )
    end)
    parent._distributeBtn = distributeBtn

    local summaryBtn = T:ActionButton(actionBar, "Summary", 100, 28)
    summaryBtn:SetPoint("LEFT", distributeBtn, "RIGHT", INNER, 0)
    summaryBtn:SetScript("OnClick", function()
        GF.ProfitReturn:PrintSummary()
    end)
    parent._summaryBtn = summaryBtn

    -- Mark Returned button — manually record gold deposited to GB
    local markReturnBtn = T:ActionButton(actionBar, "Mark Returned", 120, 28)
    markReturnBtn:SetPoint("LEFT", summaryBtn, "RIGHT", INNER, 0)
    markReturnBtn:SetScript("OnClick", function()
        local owed = GF.ProfitReturn:CalculateReturnAmount()
        if owed <= 0 then
            GF.ChatNotify:Info("Nothing owed — balance is clear.")
            return
        end
        GF.UI.Widgets:ShowConfirmDialog(
            "Return & Distribute",
            "Record |cFFFFD700" .. GF.Utils:FormatMoney(owed) .. "|r returned to guild bank and distribute profits to members?\n\n" ..
            "|cFF888888This marks all pending sales as distributed\nand credits member balances.|r",
            function()
                GF.ProfitReturn:ManualReturn(owed)
                GF.SalesLedger:DistributeAllPending()
                AHP:Refresh()
            end
        )
    end)
    parent._markReturnBtn = markReturnBtn

    initialized = true
end

--- Refresh the AH panel
function AHP:Refresh()
    Init()

    local parent = GF.UI.MainFrame:GetContentFrame("ah")
    if not parent then return end

    -- Hide officer-only buttons for non-officers
    local isOfficer = GF.Roles:GetPermissionLevel() >= GF.PERMISSIONS.OFFICER
    if parent._distributeBtn then
        if isOfficer then parent._distributeBtn:Show() else parent._distributeBtn:Hide() end
    end
    if parent._summaryBtn then
        if isOfficer then parent._summaryBtn:Show() else parent._summaryBtn:Hide() end
    end
    if parent._markReturnBtn then
        if isOfficer then parent._markReturnBtn:Show() else parent._markReturnBtn:Hide() end
    end

    local summary = GF.SalesLedger:GetSummary()
    parent._totalSales:SetText(GF.Utils:FormatMoney(summary.totalSales))
    parent._totalProfit:SetText(GF.Utils:FormatMoney(summary.totalProfit))
    parent._pendingProfit:SetText("|cFF00FF00" .. GF.Utils:FormatMoney(summary.totalPending) .. "|r")
    parent._pendingCount:SetText(tostring(GF.SalesLedger:GetPendingSalesCount()))

    -- AH account owed/returned
    local owed, breakdown = GF.ProfitReturn:CalculateReturnAmount()
    if parent._ahReturned then
        parent._ahReturned:SetText(GF.Utils:FormatMoney(breakdown.returned or 0))
    end
    if parent._ahOwed then
        if owed > 0 then
            parent._ahOwed:SetText("|cFFFF4444" .. GF.Utils:FormatMoney(owed) .. "|r")
        else
            parent._ahOwed:SetText("|cFF00FF000g|r")
        end
    end

    local sales = GF.SalesLedger:GetRecentSales(50)
    parent._salesList:SetData(sales)
end
