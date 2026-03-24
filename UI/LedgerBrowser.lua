------------------------------------------------------------------------
-- Vault of Truths - UI/LedgerBrowser.lua
-- Sortable, filterable contribution history
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.LedgerBrowser = {}
local LB = GF.UI.LedgerBrowser
local T  = GF.UI.Theme

local initialized = false
local currentFilter = {}
local currentSort = { field = "timestamp", desc = true }

------------------------------------------------------------------------
-- Filter button factory
------------------------------------------------------------------------
local function CreateFilterButton(parent, text, width, onClick)
    local btn = T:ActionButton(parent, text, width, 24)
    btn:SetScript("OnClick", onClick)
    return btn
end

------------------------------------------------------------------------
-- Column header factory (clickable sort label)
------------------------------------------------------------------------
local function CreateColumnHeader(parent, h, xOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", xOffset, 0)
    if h.width > 0 then label:SetWidth(h.width) end
    label:SetText(h.label)
    label:SetTextColor(unpack(T.COLORS.headerGold))

    local hit = CreateFrame("Button", nil, parent)
    hit:SetPoint("LEFT", xOffset, 0)
    hit:SetSize(h.width > 0 and h.width or 100, 22)
    hit:SetScript("OnClick", function()
        if currentSort.field == h.field then
            currentSort.desc = not currentSort.desc
        else
            currentSort.field = h.field
            currentSort.desc = true
        end
        LB:Refresh()
    end)

    return label
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
local function Init()
    if initialized then return end

    local parent = GF.UI.MainFrame:GetContentFrame("ledger")
    if not parent then return end

    local PAD   = 10     -- outer padding
    local GAP   =  6     -- vertical gap between sections

    ----------------------------------------------------------------
    -- 1.  Filter bar  (card-style)
    ----------------------------------------------------------------
    local filterCard = T:Card(parent)
    filterCard:SetHeight(40)
    filterCard:SetPoint("TOPLEFT",  PAD, -PAD)
    filterCard:SetPoint("TOPRIGHT", -PAD, -PAD)

    local filterLabel = filterCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("LEFT", 12, 0)
    filterLabel:SetText("Filter:")
    filterLabel:SetTextColor(unpack(T.COLORS.textDim))

    local allBtn = CreateFilterButton(filterCard, "All", 54, function()
        currentFilter = {}
        LB:Refresh()
    end)
    allBtn:SetPoint("LEFT", filterLabel, "RIGHT", 10, 0)

    local depBtn = CreateFilterButton(filterCard, "Deposits", 76, function()
        currentFilter = { action = GF.ACTIONS.DEPOSIT }
        LB:Refresh()
    end)
    depBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)

    local payBtn = CreateFilterButton(filterCard, "Payouts", 70, function()
        currentFilter = { action = GF.ACTIONS.PAYOUT }
        LB:Refresh()
    end)
    payBtn:SetPoint("LEFT", depBtn, "RIGHT", 6, 0)

    local ahBtn = CreateFilterButton(filterCard, "AH Sales", 76, function()
        currentFilter = { action = GF.ACTIONS.AH_SALE }
        LB:Refresh()
    end)
    ahBtn:SetPoint("LEFT", payBtn, "RIGHT", 6, 0)

    ----------------------------------------------------------------
    -- 2.  Column headers  (card-style header row)
    ----------------------------------------------------------------
    local headerCard = T:Card(parent)
    headerCard:SetHeight(26)
    headerCard:SetPoint("TOPLEFT",  filterCard, "BOTTOMLEFT",  0, -GAP)
    headerCard:SetPoint("TOPRIGHT", filterCard, "BOTTOMRIGHT", 0, -GAP)

    local headers = {
        { field = "timestamp",  label = "Time",   width =  60, point = "LEFT"  },
        { field = "action",     label = "Action", width =  65, point = "LEFT"  },
        { field = "player",     label = "Player", width = 100, point = "LEFT"  },
        { field = "items",      label = "Items",  width = 170, point = "LEFT"  },
        { field = "totalValue", label = "Value",  width =  80, point = "RIGHT" },
        { field = "status",     label = "Status", width =  60, point = "LEFT"  },
        { field = "trail",      label = "Trail",  width =   0, point = "LEFT"  },
    }

    local xOffset = 10
    for _, h in ipairs(headers) do
        CreateColumnHeader(headerCard, h, xOffset)
        xOffset = xOffset + (h.width > 0 and h.width or 100)
    end

    ----------------------------------------------------------------
    -- 3.  Scroll list of ledger entries
    ----------------------------------------------------------------
    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT",     headerCard, "BOTTOMLEFT",   0, -GAP)
    listFrame:SetPoint("BOTTOMRIGHT", parent,     "BOTTOMRIGHT", -PAD, 34)

    local list = GF.UI.Widgets:CreateScrollList(listFrame, 22,
        -- row factory
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame)
            row:EnableMouse(true)

            row.time = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.time:SetPoint("LEFT", 10, 0)
            row.time:SetWidth(60)
            row.time:SetTextColor(unpack(T.COLORS.textDim))

            row.action = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.action:SetPoint("LEFT", 70, 0)
            row.action:SetWidth(65)

            row.player = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.player:SetPoint("LEFT", 135, 0)
            row.player:SetWidth(100)

            -- Items column — shows item tooltip on hover
            row.itemBtn = CreateFrame("Button", nil, row)
            row.itemBtn:SetPoint("LEFT", 235, 0)
            row.itemBtn:SetSize(170, 20)
            row.items = row.itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.items:SetAllPoints()
            row.items:SetJustifyH("LEFT")
            row.items:SetTextColor(unpack(T.COLORS.textNormal))
            row.itemBtn:SetScript("OnEnter", function(self)
                if self:GetParent()._itemLinks and #self:GetParent()._itemLinks > 0 then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self:GetParent()._itemLinks[1])
                    GameTooltip:Show()
                end
            end)
            row.itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.value:SetPoint("LEFT", 405, 0)
            row.value:SetWidth(80)
            row.value:SetJustifyH("RIGHT")
            row.value:SetTextColor(unpack(T.COLORS.gold))

            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.status:SetPoint("LEFT", 490, 0)
            row.status:SetWidth(60)
            row.status:SetTextColor(unpack(T.COLORS.textDim))

            -- Trail column — separate button with its own custom tooltip
            row.trailBtn = CreateFrame("Button", nil, row)
            row.trailBtn:SetPoint("LEFT", 555, 0)
            row.trailBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.trailBtn:SetHeight(20)
            row.trailText = row.trailBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.trailText:SetAllPoints()
            row.trailText:SetJustifyH("LEFT")

            row.trailBtn:SetScript("OnEnter", function(self)
                local trail = self:GetParent()._trailData
                if not trail then return end

                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine("|cFFFFCC00Item Trail|r")
                GameTooltip:AddLine(" ")

                for _, evt in ipairs(trail.events or {}) do
                    local evtPlayer = evt.player and (evt.player:match("^(.+)-") or evt.player) or "?"
                    local evtTime = GF.Utils:FormatRelativeTime(evt.timestamp or 0)
                    local evtValue = evt.value and evt.value > 0 and (" " .. GF.Utils:FormatMoney(evt.value)) or ""

                    local actionLabels = {
                        [GF.ACTIONS.DEPOSIT] = "|cFF00FF00Deposited|r",
                        [GF.ACTIONS.WITHDRAW] = "|cFFFF4444Withdrawn|r",
                        [GF.ACTIONS.CRAFT_WITHDRAW] = "|cFFFF8800Taken for craft|r",
                        [GF.ACTIONS.CRAFT_DEPOSIT] = "|cFF00AAFFCrafted & deposited|r",
                        [GF.ACTIONS.AH_LIST] = "|cFFFFD700Listed on AH|r",
                        [GF.ACTIONS.AH_SALE] = "|cFF00FF00Sold on AH|r",
                    }
                    local label = actionLabels[evt.action] or evt.action
                    GameTooltip:AddDoubleLine(
                        label .. " by " .. evtPlayer,
                        evtTime .. evtValue,
                        1, 1, 1, 0.6, 0.6, 0.6
                    )
                end

                if GF.ItemTrail then
                    local statusText, statusColor = GF.ItemTrail:GetTrailStatusText(trail)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Status: " .. statusColor .. statusText .. "|r", 1, 1, 1)
                end

                -- Show all involved players
                local depositors, suppliers, crafters, listers = {}, {}, {}, {}
                for _, evt in ipairs(trail.events or {}) do
                    local name = evt.player and (evt.player:match("^(.+)-") or evt.player) or nil
                    if name then
                        if evt.action == GF.ACTIONS.DEPOSIT then depositors[name] = true
                        elseif evt.action == GF.ACTIONS.CRAFT_DEPOSIT then crafters[name] = true
                        elseif evt.action == GF.ACTIONS.AH_LIST then listers[name] = true
                        end
                    end
                end

                -- Include suppliers from material trails (who deposited the raw mats)
                if trail.suppliers then
                    for playerName in pairs(trail.suppliers) do
                        local short = playerName:match("^(.+)-") or playerName
                        suppliers[short] = true
                    end
                end

                local parts = {}
                local depNames = {}
                for n in pairs(depositors) do depNames[#depNames + 1] = n end
                if #depNames > 0 then parts[#parts + 1] = "|cFF00FF00Deposited:|r " .. table.concat(depNames, ", ") end

                local supNames = {}
                for n in pairs(suppliers) do supNames[#supNames + 1] = n end
                if #supNames > 0 then parts[#parts + 1] = "|cFF88FF88Supplied mats:|r " .. table.concat(supNames, ", ") end

                local craftNames = {}
                for n in pairs(crafters) do craftNames[#craftNames + 1] = n end
                if #craftNames > 0 then parts[#parts + 1] = "|cFF00AAFFCrafted:|r " .. table.concat(craftNames, ", ") end

                local listNames = {}
                for n in pairs(listers) do listNames[#listNames + 1] = n end
                if #listNames > 0 then parts[#parts + 1] = "|cFFFFD700Listed:|r " .. table.concat(listNames, ", ") end

                if #parts > 0 then
                    GameTooltip:AddLine(" ")
                    for _, p in ipairs(parts) do
                        GameTooltip:AddLine(p, 1, 1, 1)
                    end
                end

                GameTooltip:Show()
            end)
            row.trailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            T:StripeRow(row, index)

            return row
        end,
        -- row updater
        function(row, entry)
            row.time:SetText(GF.Utils:FormatRelativeTime(entry.timestamp))

            local actionColors = {
                [GF.ACTIONS.DEPOSIT]        = "|cFF00FF00",
                [GF.ACTIONS.WITHDRAW]       = "|cFFFF4444",
                [GF.ACTIONS.PAYOUT]         = "|cFFFFAA00",
                [GF.ACTIONS.FEE]            = "|cFF00AAFF",
                [GF.ACTIONS.CRAFT_WITHDRAW] = "|cFFFF8800",
                [GF.ACTIONS.CRAFT_DEPOSIT]  = "|cFF00AAFF",
                [GF.ACTIONS.AH_LIST]        = "|cFFFFD700",
                [GF.ACTIONS.AH_SALE]        = "|cFFFFD700",
                [GF.ACTIONS.AH_RETURN]      = "|cFF00FF88",
            }
            local color = actionColors[entry.action] or "|cFFFFFFFF"
            row.action:SetText(color .. (entry.action or "") .. "|r")

            row.player:SetText(entry.player:match("^(.+)-") or entry.player)
            row.value:SetText(GF.Utils:FormatGold(entry.totalValue))
            row._note = entry.note

            -- Status column
            local statusColors = {
                pending = "|cFFFFAA00",
                credited = "|cFF00FF00",
                crafted = "|cFF00AAFF",
                sold = "|cFFFFD700",
            }
            local statusColor = statusColors[entry.status] or "|cFF888888"
            row.status:SetText(statusColor .. (entry.status or "") .. "|r")

            -- Build items display
            row._itemLinks = {}
            row._trailData = nil
            local firstItemID = nil

            if entry.items and #entry.items > 0 then
                local itemParts = {}
                for _, item in ipairs(entry.items) do
                    local itemName, itemLink = C_Item.GetItemInfo(item.itemID or 0)
                    if not firstItemID and item.itemID then firstItemID = item.itemID end
                    if itemLink then
                        row._itemLinks[#row._itemLinks + 1] = itemLink
                        local qty = item.quantity or item.count or 1
                        if qty > 1 then
                            itemParts[#itemParts + 1] = itemLink .. " x" .. qty
                        else
                            itemParts[#itemParts + 1] = itemLink
                        end
                    elseif itemName then
                        local qty = item.quantity or item.count or 1
                        itemParts[#itemParts + 1] = itemName .. (qty > 1 and (" x" .. qty) or "")
                    elseif item.itemID then
                        local qty = item.quantity or item.count or 1
                        itemParts[#itemParts + 1] = "Item:" .. item.itemID .. (qty > 1 and (" x" .. qty) or "")
                        if not firstItemID then firstItemID = item.itemID end
                        C_Item.GetItemInfo(item.itemID)
                    end
                end
                row.items:SetText(table.concat(itemParts, ", "))
            else
                row.items:SetText("|cFF666666" .. (entry.note or "") .. "|r")
            end

            -- Look up item trail — use trailID if available (unique per transaction)
            if entry.trailID and GF.ItemTrail then
                row._trailData = GF.ItemTrail:GetTrail(entry.trailID)
            elseif firstItemID and GF.ItemTrail then
                local guildData = GF.Settings:GetGuildData()
                if guildData and guildData.itemTrails then
                    for _, trail in pairs(guildData.itemTrails) do
                        if trail.itemID == firstItemID or trail.craftedItemID == firstItemID then
                            row._trailData = trail
                            break
                        end
                    end
                end
            end

            -- Trail column text
            if row._trailData and GF.ItemTrail then
                local statusText, statusColor = GF.ItemTrail:GetTrailStatusText(row._trailData)
                row.trailText:SetText(statusColor .. statusText .. "|r")
            elseif row._trailData then
                row.trailText:SetText("|cFF888888" .. (row._trailData.status or "") .. "|r")
            else
                row.trailText:SetText("")
            end
        end
    )
    parent._list = list

    ----------------------------------------------------------------
    -- 4.  Summary footer  (card-style)
    ----------------------------------------------------------------
    local footerCard = T:Card(parent)
    footerCard:SetHeight(28)
    footerCard:SetPoint("BOTTOMLEFT",  PAD, PAD)
    footerCard:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    local footer = footerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetPoint("LEFT", 12, 0)
    footer:SetTextColor(unpack(T.COLORS.textDim))
    parent._footer = footer

    initialized = true
end

--- Refresh the ledger browser
function LB:Refresh()
    Init()

    local parent = GF.UI.MainFrame:GetContentFrame("ledger")
    if not parent then return end

    -- Get filtered entries
    local entries = GF.Ledger:GetRecent(500, currentFilter)

    -- Sort
    if currentSort.field then
        table.sort(entries, function(a, b)
            local va, vb = a[currentSort.field], b[currentSort.field]
            if va == nil then return false end
            if vb == nil then return true end
            if currentSort.desc then
                return va > vb
            else
                return va < vb
            end
        end)
    end

    parent._list:SetData(entries)

    -- Update footer
    local depositValue = 0
    local withdrawValue = 0
    local salesValue = 0
    for _, e in ipairs(entries) do
        if e.action == GF.ACTIONS.DEPOSIT then
            depositValue = depositValue + (e.totalValue or 0)
        elseif e.action == GF.ACTIONS.WITHDRAW then
            withdrawValue = withdrawValue + (e.totalValue or 0)
        elseif e.action == GF.ACTIONS.AH_SALE then
            salesValue = salesValue + (e.totalValue or 0)
        end
    end
    parent._footer:SetText(#entries .. " entries | Deposits: " .. GF.Utils:FormatGold(depositValue) ..
        " | Withdrawn: " .. GF.Utils:FormatGold(withdrawValue) ..
        " | Sales: " .. GF.Utils:FormatGold(salesValue))
end
