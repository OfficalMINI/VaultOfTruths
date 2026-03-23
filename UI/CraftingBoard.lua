------------------------------------------------------------------------
-- Vault of Truths - UI/CraftingBoard.lua
-- Browse, post, and accept crafting orders
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.CraftingBoard = {}
local CB = GF.UI.CraftingBoard

local initialized = false

local function Init()
    if initialized then return end

    local T = GF.UI.Theme
    local parent = GF.UI.MainFrame:GetContentFrame("crafting")
    if not parent then return end

    local PAD = 10

    ---------- Header ----------
    local _, headerContainer = T:SectionHeader(
        parent,
        { "TOPLEFT", parent, "TOPLEFT", PAD, -PAD },
        "Guild Crafting",
        "Interface\\ICONS\\Trade_Engineering"
    )
    headerContainer:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)

    -- Open orders count
    local countText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("LEFT", headerContainer, "LEFT", 160, 0)
    countText:SetTextColor(unpack(T.COLORS.textDim))
    parent._countText = countText

    -- My Queue indicator
    local myQueueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    myQueueText:SetPoint("RIGHT", headerContainer, "RIGHT", 0, 0)
    myQueueText:SetTextColor(unpack(T.COLORS.warning))
    parent._myQueueText = myQueueText

    ---------- Guild Crafters Panel (right side card) ----------
    local crafterPanel = T:Card(parent)
    crafterPanel:SetPoint("TOPRIGHT", -PAD, -34)
    crafterPanel:SetWidth(200)
    crafterPanel:SetPoint("BOTTOM", 0, 52)

    local crafterTitle = crafterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    crafterTitle:SetPoint("TOP", 0, -6)
    crafterTitle:SetText("|cFFFFCC00Guild Crafters|r")

    -- Search box
    local crafterSearch = T:EditBox(crafterPanel, 180, 20)
    crafterSearch:SetPoint("TOP", 0, -24)

    local searchHint = crafterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchHint:SetPoint("TOP", crafterSearch, "BOTTOM", 0, -2)
    searchHint:SetText("|cFF555555Search recipes...|r")

    -- Crafter scroll list
    local crafterListFrame = CreateFrame("Frame", nil, crafterPanel)
    crafterListFrame:SetPoint("TOPLEFT", 4, -62)
    crafterListFrame:SetPoint("BOTTOMRIGHT", -4, 4)

    local crafterList = GF.UI.Widgets:CreateScrollList(crafterListFrame, 38,
        function(index, contentFrame)
            local row = CreateFrame("Button", nil, contentFrame)

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(unpack(T.COLORS.rowHover))

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("TOPLEFT", 4, -3)
            row.name:SetPoint("RIGHT", -4, 0)
            row.name:SetJustifyH("LEFT")

            row.info = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.info:SetPoint("TOPLEFT", 4, -16)
            row.info:SetPoint("RIGHT", -4, 0)
            row.info:SetJustifyH("LEFT")
            row.info:SetTextColor(unpack(T.COLORS.textDim))

            local sep = row:CreateTexture(nil, "ARTWORK")
            sep:SetHeight(1)
            sep:SetPoint("BOTTOMLEFT", 2, 0)
            sep:SetPoint("BOTTOMRIGHT", -2, 0)
            sep:SetColorTexture(unpack(T.COLORS.divider))

            return row
        end,
        function(row, entry)
            if entry.type == "crafter" then
                row.name:SetText("|cFF00FF00" .. entry.displayName .. "|r")
                row.info:SetText(entry.professions or "")
                row:SetScript("OnClick", function()
                    if parent._crafterSearch and GF.RecipeScanner then
                        parent._crafterSearch:SetText("")
                        local extGuild = not IsInGuild() and GF.CommunityBridge and GF.CommunityBridge:GetConnectedGuild() or nil
                        local profs = GF.RecipeScanner:GetPlayerProfessions(entry.playerName, extGuild)
                        local data = {}
                        for profName, profData in pairs(profs) do
                            local crafterRecipes
                            if extGuild then
                                local extData = GF.Settings:GetExternalGuildData(extGuild)
                                crafterRecipes = extData and extData.crafterRecipes
                            else
                                local guildData = GF.Settings:GetGuildData()
                                crafterRecipes = guildData and guildData.crafterRecipes
                            end
                            local crafterData = crafterRecipes and crafterRecipes[entry.playerName]
                            if crafterData and crafterData.professions[profName] then
                                for i, recipe in ipairs(crafterData.professions[profName].recipes or {}) do
                                    if i > 15 then
                                        data[#data + 1] = { type = "hint", text = "|cFF666666... and more|r", subtext = "Search to filter" }
                                        break
                                    end
                                    data[#data + 1] = {
                                        type = "recipe_match",
                                        displayName = entry.displayName,
                                        playerName = entry.playerName,
                                        profName = profName,
                                        recipeName = recipe.name or recipe.id,
                                        recipeID = recipe.recipeID or recipe.id,
                                        reagents = recipe.reagents,
                                        outputItemID = recipe.outputItemID,
                                    }
                                end
                            end
                        end
                        if #data == 0 then
                            data[#data + 1] = { type = "hint", text = "|cFF888888No recipes scanned.|r", subtext = "Crafter needs to open professions." }
                        end
                        parent._crafterList:SetData(data)
                    end
                end)
                GF.UI.Widgets.Tooltip:Attach(row, entry.displayName,
                    { "Click to view recipes", entry.professions or "" }, "ANCHOR_LEFT")

            elseif entry.type == "recipe_match" then
                row.name:SetText("|cFF00AAFF" .. (entry.recipeName or "") .. "|r")
                row.info:SetText(entry.displayName .. " — " .. (entry.profName or ""))
                row:SetScript("OnClick", function()
                    local commission = GF.Settings:GetGuild("craftCommission") or GF.DEFAULT_CRAFT_COMMISSION
                    local commissionText = GF.Utils:FormatMoney(commission)

                    local matCostText = ""
                    local totalMatCost = 0
                    if entry.reagents and #entry.reagents > 0 and GF.TSM then
                        for _, r in ipairs(entry.reagents) do
                            local price = GF.TSM:GetBestPrice(r.itemID) or 0
                            totalMatCost = totalMatCost + (price * (r.quantity or 1))
                        end
                        if totalMatCost > 0 then
                            matCostText = "\n|cFFFFD700Mat cost:|r ~" .. GF.Utils:FormatMoney(totalMatCost)
                            matCostText = matCostText .. "\n|cFFFFD700Total:|r ~" .. GF.Utils:FormatMoney(totalMatCost + commission)
                        end
                    end

                    local totalOrderCost = totalMatCost + commission
                    local balanceInfo = ""
                    local playerBalance = 0
                    if IsInGuild() then
                        local myName = GF.Utils:GetPlayerFullName()
                        playerBalance = GF.Payouts:GetBalance(myName)
                        if playerBalance > 0 then
                            balanceInfo = "\n\n|cFF00FF00Your balance:|r " .. GF.Utils:FormatMoney(playerBalance)
                            if playerBalance >= totalOrderCost and totalOrderCost > 0 then
                                balanceInfo = balanceInfo .. "\n|cFF00FF00You can pay for this from your earnings!|r"
                            elseif totalOrderCost > 0 then
                                balanceInfo = balanceInfo .. "\n|cFFFFAA00Partial balance — remainder owed in gold.|r"
                            end
                        end
                    end

                    local costInfo
                    if IsInGuild() then
                        costInfo = "Guild supplies mats. You pay mat cost + commission.\n\n" ..
                            "|cFFFFD700Craft commission:|r " .. commissionText ..
                            matCostText ..
                            balanceInfo .. "\n\n" ..
                            "|cFF888888Commission profit goes to material contributors.|r"
                    else
                        costInfo = "Guild supplies mats. You pay mat cost + commission.\n\n" ..
                            "|cFFFFD700Craft commission:|r " .. commissionText ..
                            matCostText .. "\n\n" ..
                            "|cFF888888Commission split to guild members who\ncontributed the materials.|r"
                    end

                    GF.UI.Widgets:ShowConfirmDialog(
                        "Queue Craft Order",
                        "Request |cFF00AAFF" .. (entry.recipeName or "this item") ..
                        "|r from |cFF00FF00" .. entry.displayName .. "|r?\n\n" .. costInfo,
                        function()
                            if IsInGuild() then
                                local myName = GF.Utils:GetPlayerFullName()
                                local myBalance = GF.Payouts:GetBalance(myName)
                                local orderFee = totalOrderCost > 0 and totalOrderCost or commission

                                local order = GF.OrderBoard:CreateOrder(
                                    entry.recipeID,
                                    entry.recipeName or "Unknown",
                                    entry.reagents or {},
                                    "guild"
                                )
                                if order then
                                    order.commission = commission
                                    if entry.outputItemID then
                                        order.outputItemID = entry.outputItemID
                                    end

                                    if myBalance >= orderFee and orderFee > 0 then
                                        local ok = GF.Payouts:PayFromBalance(myName, orderFee, entry.recipeName or "craft order")
                                        if ok then
                                            order.paidFromBalance = true
                                            order.paidAmount = orderFee
                                        end
                                    elseif myBalance > 0 and orderFee > 0 then
                                        local partial = myBalance
                                        local ok = GF.Payouts:PayFromBalance(myName, partial, entry.recipeName or "craft order (partial)")
                                        if ok then
                                            order.paidFromBalance = true
                                            order.paidAmount = partial
                                            GF.ChatNotify:Info("Remaining " .. GF.Utils:FormatMoney(orderFee - partial) .. " owed in gold.")
                                        end
                                    end

                                    order.crafter = entry.playerName
                                    order.status = GF.ORDER_STATUS.ACCEPTED
                                    order.accepted = GF.Utils:GetTime()
                                    GF.Sender:BroadcastOrderUpdate(order.id, GF.ORDER_STATUS.ACCEPTED, entry.playerName)
                                    GF.ChatNotify:Success("Order queued: " .. (entry.recipeName or "") .. " — assigned to " .. entry.displayName)
                                end
                            else
                                local extGuild = GF.CommunityBridge:GetConnectedGuild()
                                if extGuild then
                                    local order = GF.OrderBoard:CreateExternalOrder(
                                        extGuild,
                                        entry.recipeID,
                                        entry.recipeName or "Unknown",
                                        entry.reagents or {}
                                    )
                                    if order then
                                        order.commission = commission
                                        if entry.outputItemID then
                                            order.outputItemID = entry.outputItemID
                                        end
                                    end
                                else
                                    GF.ChatNotify:Warning("No guild connected.")
                                end
                            end
                            CB:Refresh()
                        end
                    )
                end)
                GF.UI.Widgets.Tooltip:Attach(row, entry.recipeName or "",
                    { entry.displayName .. " (" .. (entry.profName or "") .. ")", "Click to queue craft order" }, "ANCHOR_LEFT")

            elseif entry.type == "hint" then
                row.name:SetText(entry.text or "")
                row.info:SetText(entry.subtext or "")
                row:SetScript("OnClick", nil)
            end
        end
    )
    parent._crafterList = crafterList

    local searchTimer
    crafterSearch:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.4, function()
            local query = self:GetText()
            if query and #query >= 2 and GF.RecipeScanner then
                local extGuild = not IsInGuild() and GF.CommunityBridge and GF.CommunityBridge:GetConnectedGuild() or nil
                local results = GF.RecipeScanner:FindCrafters(query, extGuild)
                local data = {}
                if #results > 0 then
                    for _, r in ipairs(results) do
                        data[#data + 1] = {
                            type = "recipe_match",
                            displayName = r.displayName,
                            playerName = r.playerName,
                            profName = r.profName,
                            recipeName = r.recipeName,
                            recipeID = r.recipeID,
                            reagents = r.reagents,
                            outputItemID = r.outputItemID,
                        }
                    end
                else
                    data[#data + 1] = { type = "hint", text = "|cFF888888No matches.|r", subtext = "Crafters: open professions to scan." }
                end
                crafterList:SetData(data)
            elseif not query or #query < 2 then
                CB:RefreshCrafterList()
            end
        end)
    end)

    parent._crafterPanel = crafterPanel
    parent._crafterSearch = crafterSearch

    ---------- Order List (left of crafter panel) ----------
    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", PAD, -34)
    listFrame:SetPoint("BOTTOMRIGHT", crafterPanel, "BOTTOMLEFT", -6, 0)

    local list = GF.UI.Widgets:CreateScrollList(listFrame, 44,
        function(index, contentFrame)
            local row = T:Card(contentFrame)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.name:SetPoint("TOPLEFT", 10, -6)
            row.name:SetTextColor(unpack(T.COLORS.textNormal))

            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.status:SetPoint("TOPRIGHT", -10, -6)

            row.details = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.details:SetPoint("BOTTOMLEFT", 10, 6)
            row.details:SetTextColor(unpack(T.COLORS.textDim))

            row.fee = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.fee:SetPoint("BOTTOMRIGHT", -10, 6)
            row.fee:SetTextColor(unpack(T.COLORS.gold))

            -- Action buttons
            row.acceptBtn = T:Button(row, "Accept", 56, 18)
            row.acceptBtn:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
            row.acceptBtn:Hide()

            row.completeBtn = T:Button(row, "Complete", 64, 18)
            row.completeBtn:SetPoint("RIGHT", row.acceptBtn, "LEFT", -4, 0)
            row.completeBtn._label:SetTextColor(unpack(T.COLORS.positive))
            row.completeBtn:Hide()

            row.cancelBtn = T:Button(row, "Cancel", 52, 18)
            row.cancelBtn:SetPoint("RIGHT", row.completeBtn, "LEFT", -4, 0)
            row.cancelBtn._label:SetTextColor(unpack(T.COLORS.negative))
            row.cancelBtn:Hide()

            return row
        end,
        function(row, order)
            row.name:SetText(order.recipeName or ("Recipe #" .. (order.recipeID or "?")))

            local statusColors = {
                [GF.ORDER_STATUS.OPEN] = "|cFF00FF00",
                [GF.ORDER_STATUS.ACCEPTED] = "|cFFFFAA00",
                [GF.ORDER_STATUS.COMPLETED] = "|cFF888888",
                [GF.ORDER_STATUS.CANCELLED] = "|cFFFF0000",
            }
            local color = statusColors[order.status] or "|cFFFFFFFF"
            row.status:SetText(color .. order.status:upper() .. "|r")

            local requester = order.requester and (order.requester:match("^(.+)-") or order.requester) or "Unknown"
            local crafter = order.crafter and (order.crafter:match("^(.+)-") or order.crafter) or "Unassigned"
            local mode = order.supplyMode == "requester" and "Requester mats" or "Guild mats"
            row.details:SetText(requester .. " | " .. mode .. " | Crafter: " .. crafter)
            row.fee:SetText("Fee: " .. GF.Utils:FormatMoney(order.fee or 0))

            local myName = GF.Utils:GetPlayerFullName()

            if order.status == GF.ORDER_STATUS.OPEN and GF.Roles:HasRole(myName, GF.ROLES.CRAFTER) then
                row.acceptBtn:Show()
                row.acceptBtn:SetScript("OnClick", function()
                    GF.UI.Widgets:ShowConfirmDialog("Accept Order",
                        "Accept order for " .. (order.recipeName or "this item") .. "?\nFee: " .. GF.Utils:FormatMoney(order.fee or 0),
                        function() GF.OrderBoard:AcceptOrder(order.id); CB:Refresh() end)
                end)
            else
                row.acceptBtn:Hide()
            end

            if order.status == GF.ORDER_STATUS.ACCEPTED and order.crafter == myName then
                row.completeBtn:Show()
                row.completeBtn:SetScript("OnClick", function()
                    GF.UI.Widgets:ShowConfirmDialog("Complete Order",
                        "Mark " .. (order.recipeName or "this item") .. " as completed?\nYou earn: " .. GF.Utils:FormatMoney(order.fee or 0),
                        function() GF.OrderBoard:CompleteOrder(order.id); CB:Refresh() end)
                end)
            else
                row.completeBtn:Hide()
            end

            if (order.status == GF.ORDER_STATUS.OPEN or order.status == GF.ORDER_STATUS.ACCEPTED)
                and (order.requester == myName or GF.Roles:IsAddonOfficer()) then
                row.cancelBtn:Show()
                row.cancelBtn:SetScript("OnClick", function()
                    GF.UI.Widgets:ShowConfirmDialog("Cancel Order",
                        "Cancel order for " .. (order.recipeName or "this item") .. "?",
                        function() GF.OrderBoard:CancelOrder(order.id); CB:Refresh() end)
                end)
            else
                row.cancelBtn:Hide()
            end
        end
    )
    parent._list = list

    ---------- Bottom Action Bar ----------
    local actionBar = T:Card(parent)
    actionBar:SetHeight(42)
    actionBar:SetPoint("BOTTOMLEFT", PAD, PAD)
    actionBar:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    local refreshBtn = T:Button(actionBar, "Refresh", 80, 26)
    refreshBtn:SetPoint("LEFT", 8, 0)
    refreshBtn:SetScript("OnClick", function() CB:Refresh() end)

    local postBtn = T:ActionButton(actionBar, "Post Order", 110, 26)
    postBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)

    ---------- Order Creation Overlay ----------
    local overlay = T:Card(parent)
    overlay:SetAllPoints(listFrame)
    overlay:SetBackdropColor(0.06, 0.07, 0.11, 0.98)
    overlay:SetFrameLevel(parent:GetFrameLevel() + 10)
    overlay:Hide()
    parent._orderOverlay = overlay

    -- Title
    local overlayTitleIcon = overlay:CreateTexture(nil, "ARTWORK")
    overlayTitleIcon:SetSize(18, 18)
    overlayTitleIcon:SetPoint("TOPLEFT", 12, -10)
    overlayTitleIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")

    local overlayTitle = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlayTitle:SetPoint("LEFT", overlayTitleIcon, "RIGHT", 6, 0)
    overlayTitle:SetText("|cFFFFCC00Post Crafting Order|r")

    local overlaySubtitle = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlaySubtitle:SetPoint("TOPLEFT", 12, -32)
    overlaySubtitle:SetPoint("RIGHT", -12, 0)
    overlaySubtitle:SetText("|cFF888888Search for an item, pick who supplies mats, and submit.|r")
    overlaySubtitle:SetJustifyH("LEFT")

    T:Divider(overlay, -46)

    -- Section 1: Item Search
    local searchLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 12, -54)
    searchLabel:SetText("|cFFFFCC00Item to Craft|r")

    local searchBox = T:EditBox(overlay, 280, 22)
    searchBox:SetPoint("TOPLEFT", 12, -72)

    -- Selected item display
    local selectedFrame = T:Card(overlay)
    selectedFrame:SetPoint("TOPLEFT", 12, -100)
    selectedFrame:SetPoint("RIGHT", overlay, "RIGHT", -12, 0)
    selectedFrame:SetHeight(40)
    selectedFrame:SetBackdropColor(0.06, 0.08, 0.12, 0.8)

    local selectedIcon = selectedFrame:CreateTexture(nil, "ARTWORK")
    selectedIcon:SetSize(24, 24)
    selectedIcon:SetPoint("LEFT", 6, 0)
    selectedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local selectedText = selectedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectedText:SetPoint("LEFT", selectedIcon, "RIGHT", 8, 0)
    selectedText:SetPoint("RIGHT", -8, 0)
    selectedText:SetJustifyH("LEFT")
    selectedText:SetText("|cFF888888No item selected — type to search|r")

    overlay._selectedItemID = nil
    overlay._selectedName = nil

    local crafterMatchText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    crafterMatchText:SetPoint("TOPLEFT", selectedFrame, "BOTTOMLEFT", 0, -4)
    crafterMatchText:SetPoint("RIGHT", overlay, "RIGHT", -12, 0)
    crafterMatchText:SetJustifyH("LEFT")
    crafterMatchText:SetWordWrap(true)
    crafterMatchText:SetTextColor(unpack(T.COLORS.textDim))
    crafterMatchText:SetText("")
    overlay._crafterMatchText = crafterMatchText

    -- Autocomplete dropdown
    local dropdown = T:Card(overlay)
    dropdown:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -2, -2)
    dropdown:SetPoint("RIGHT", overlay, "RIGHT", -12, 0)
    dropdown:SetHeight(160)
    dropdown:SetBackdropColor(0.04, 0.05, 0.08, 0.98)
    dropdown:SetFrameLevel(overlay:GetFrameLevel() + 5)
    dropdown:Hide()

    local dropdownRows = {}
    local MAX_DROPDOWN_ROWS = 8

    for i = 1, MAX_DROPDOWN_ROWS do
        local row = CreateFrame("Button", nil, dropdown)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", 4, -(i - 1) * 18 - 4)
        row:SetPoint("RIGHT", -4, 0)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(unpack(T.COLORS.rowHover))

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")

        row:Hide()
        dropdownRows[i] = row
    end

    local function DoSearch(query)
        if not query or #query < 2 then
            dropdown:Hide()
            return
        end

        query = query:lower()
        local results = {}

        local scanRanges = {
            {190000, 200000},
            {210000, 215000},
            {220000, 232000},
            {240000, 257000},
        }

        for _, range in ipairs(scanRanges) do
            for id = range[1], range[2], 1 do
                local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
                if name and name:lower():find(query, 1, true) then
                    results[#results + 1] = { itemID = id, name = name, icon = icon, quality = quality or 1 }
                    if #results >= MAX_DROPDOWN_ROWS then break end
                end
            end
            if #results >= MAX_DROPDOWN_ROWS then break end
        end

        for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
            local slots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, slots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(info.itemID)
                    if name and name:lower():find(query, 1, true) then
                        local found = false
                        for _, r in ipairs(results) do
                            if r.itemID == info.itemID then found = true; break end
                        end
                        if not found then
                            results[#results + 1] = { itemID = info.itemID, name = name, icon = icon, quality = quality or 1 }
                            if #results >= MAX_DROPDOWN_ROWS then break end
                        end
                    end
                end
            end
            if #results >= MAX_DROPDOWN_ROWS then break end
        end

        table.sort(results, function(a, b) return a.quality > b.quality end)

        for i = 1, MAX_DROPDOWN_ROWS do
            local row = dropdownRows[i]
            local r = results[i]
            if r then
                row.icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local colorPrefix = ""
                if r.quality >= 4 then colorPrefix = "|cFFA335EE"
                elseif r.quality >= 3 then colorPrefix = "|cFF0070DD"
                elseif r.quality >= 2 then colorPrefix = "|cFF1EFF00"
                end
                row.text:SetText(colorPrefix .. r.name .. "|r")
                row:SetScript("OnClick", function()
                    overlay._selectedItemID = r.itemID
                    overlay._selectedName = r.name
                    selectedIcon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    selectedText:SetText(colorPrefix .. r.name .. "|r  (ID: " .. r.itemID .. ")")
                    searchBox:SetText(r.name)
                    searchBox:ClearFocus()
                    dropdown:Hide()

                    if GF.RecipeScanner and overlay._crafterMatchText then
                        local crafters = GF.RecipeScanner:FindCrafters(r.name)
                        if #crafters > 0 then
                            local names = {}
                            for _, c in ipairs(crafters) do
                                names[#names + 1] = "|cFF00FF00" .. c.displayName .. "|r (" .. c.profName .. ")"
                            end
                            overlay._crafterMatchText:SetText("Can craft: " .. table.concat(names, ", "))
                        else
                            overlay._crafterMatchText:SetText("|cFF888888No guild crafter found. Use WoW crafting orders with a public crafter.|r")
                        end
                    end
                end)
                row:Show()
            else
                row:Hide()
            end
        end

        if #results > 0 then
            dropdown:SetHeight(math.min(#results, MAX_DROPDOWN_ROWS) * 18 + 8)
            dropdown:Show()
        else
            dropdown:Hide()
        end
    end

    local searchTimer2 = nil
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if searchTimer2 then searchTimer2:Cancel() end
        searchTimer2 = C_Timer.NewTimer(0.3, function()
            DoSearch(self:GetText())
        end)
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        DoSearch(self:GetText())
    end)

    T:Divider(overlay, -148)

    -- Section 2: Supply Mode
    local supplyLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    supplyLabel:SetPoint("TOPLEFT", 12, -156)
    supplyLabel:SetText("|cFFFFCC00Material Supply|r")

    overlay._supplyMode = "guild"

    local guildMatBtn = T:Button(overlay, "Guild Supplies", 130, 26)
    guildMatBtn:SetPoint("TOPLEFT", 12, -176)

    local reqMatBtn = T:Button(overlay, "I Supply Mats", 130, 26)
    reqMatBtn:SetPoint("LEFT", guildMatBtn, "RIGHT", 8, 0)

    local supplyExplain = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    supplyExplain:SetPoint("TOPLEFT", 12, -206)
    supplyExplain:SetPoint("RIGHT", -12, 0)
    supplyExplain:SetJustifyH("LEFT")
    supplyExplain:SetWordWrap(true)
    overlay._supplyExplain = supplyExplain

    local costPreview = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    costPreview:SetPoint("TOPLEFT", 12, -226)
    costPreview:SetPoint("RIGHT", -12, 0)
    costPreview:SetJustifyH("LEFT")
    overlay._costPreview = costPreview

    local function UpdateSupplyToggle()
        local commission = GF.Settings:GetGuild("craftCommission") or GF.DEFAULT_CRAFT_COMMISSION
        if overlay._supplyMode == "guild" then
            guildMatBtn:Disable()
            reqMatBtn:Enable()
            local balText = ""
            if IsInGuild() then
                local bal = GF.Payouts:GetBalance(GF.Utils:GetPlayerFullName())
                if bal > 0 then
                    balText = "\n|cFF00FF00Your balance: " .. GF.Utils:FormatMoney(bal) .. " — can be used to pay!|r"
                end
            end
            supplyExplain:SetText("|cFF888888Guild provides mats. You pay mat cost + craft commission.\nProfit from commission goes to material contributors.|r" .. balText)
            costPreview:SetText("|cFFFFD700Craft commission: " .. GF.Utils:FormatMoney(commission) .. " + mat cost|r")
        else
            guildMatBtn:Enable()
            reqMatBtn:Disable()
            supplyExplain:SetText("|cFF888888You provide mats to the crafter directly.\nSmall crafting fee only.|r")
            costPreview:SetText("|cFF00FF00You supply mats — fee based on mat value.|r")
        end
    end

    guildMatBtn:SetScript("OnClick", function()
        overlay._supplyMode = "guild"
        UpdateSupplyToggle()
    end)
    reqMatBtn:SetScript("OnClick", function()
        overlay._supplyMode = "requester"
        UpdateSupplyToggle()
    end)

    T:Divider(overlay, -248)

    -- Section 3: Notes
    local notesLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLabel:SetPoint("TOPLEFT", 12, -256)
    notesLabel:SetText("|cFFFFCC00Notes|r")

    local notesHint = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notesHint:SetPoint("LEFT", notesLabel, "RIGHT", 8, 0)
    notesHint:SetText("|cFF666666(optional — quality, enchant, etc.)|r")

    local notesBox = T:EditBox(overlay, 280, 22)
    notesBox:SetPoint("TOPLEFT", 12, -274)
    overlay._notesBox = notesBox

    -- Submit / Cancel
    local submitBtn = T:ActionButton(overlay, "Submit Order", 140, 28)
    submitBtn:SetPoint("BOTTOMLEFT", 12, 12)
    submitBtn:SetScript("OnClick", function()
        local itemID = overlay._selectedItemID
        local itemName = overlay._selectedName
        if not itemName or itemName == "" then
            GF.ChatNotify:Warning("Search and select an item first.")
            return
        end

        local mats = {}
        if itemID then
            mats[#mats + 1] = { itemID = itemID, quantity = 1 }
        end

        local notes = notesBox:GetText()
        if notes and notes ~= "" then
            itemName = itemName .. " (" .. notes .. ")"
        end

        local supplyMode = overlay._supplyMode
        local commission = GF.Settings:GetGuild("craftCommission") or GF.DEFAULT_CRAFT_COMMISSION

        local function DoCreateOrder()
            if IsInGuild() then
                local order = GF.OrderBoard:CreateOrder(itemID, itemName, mats, supplyMode)
                if order and supplyMode == "guild" then
                    order.commission = commission
                end
            else
                local extGuild = GF.CommunityBridge and GF.CommunityBridge:GetConnectedGuild()
                if extGuild then
                    local order = GF.OrderBoard:CreateExternalOrder(extGuild, itemID, itemName, mats)
                    if order then
                        order.supplyMode = supplyMode
                        if supplyMode == "guild" then
                            order.commission = commission
                        end
                    end
                else
                    GF.ChatNotify:Warning("No guild connected.")
                    return
                end
            end
            overlay:Hide()
            CB:Refresh()
        end

        if supplyMode == "guild" then
            local commissionText = GF.Utils:FormatMoney(commission)
            local matTotal = 0
            for _, m in ipairs(mats) do
                if m.itemID and GF.TSM then
                    local price = GF.TSM:GetBestPrice(m.itemID) or 0
                    matTotal = matTotal + (price * (m.quantity or 1))
                end
            end
            local breakdown = "|cFFFFD700Craft commission:|r " .. commissionText
            if matTotal > 0 then
                breakdown = breakdown .. "\n|cFFFFD700Est. mat cost:|r ~" .. GF.Utils:FormatMoney(matTotal)
                breakdown = breakdown .. "\n|cFFFFD700Est. total:|r ~" .. GF.Utils:FormatMoney(matTotal + commission)
            end
            GF.UI.Widgets:ShowConfirmDialog(
                "Confirm Order — Guild Mats",
                "|cFF00AAFF" .. itemName .. "|r\n\n" ..
                breakdown .. "\n\n" ..
                "|cFF888888Guild supplies mats. Commission profit\ngoes to material contributors.|r",
                DoCreateOrder
            )
        else
            DoCreateOrder()
        end
    end)

    local cancelFormBtn = T:Button(overlay, "Cancel", 100, 28)
    cancelFormBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    cancelFormBtn:SetScript("OnClick", function() overlay:Hide() end)

    postBtn:SetScript("OnClick", function()
        if overlay:IsShown() then
            overlay:Hide()
        else
            searchBox:SetText("")
            notesBox:SetText("")
            overlay._selectedItemID = nil
            overlay._selectedName = nil
            selectedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            selectedText:SetText("|cFF888888No item selected — type to search|r")
            if overlay._crafterMatchText then overlay._crafterMatchText:SetText("") end
            overlay._supplyMode = "guild"
            UpdateSupplyToggle()
            dropdown:Hide()
            overlay:Show()
            searchBox:SetFocus()
        end
    end)

    UpdateSupplyToggle()
    initialized = true
end

--- Refresh the crafting board
function CB:Refresh()
    Init()

    local parent = GF.UI.MainFrame:GetContentFrame("crafting")
    if not parent then return end

    local myName = GF.Utils:GetPlayerFullName()
    local orders
    if IsInGuild() then
        orders = GF.OrderBoard:GetOrders()
    else
        local guildName = GF.CommunityBridge and GF.CommunityBridge:GetConnectedGuild()
        if guildName then
            local extData = GF.Settings:GetExternalGuildData(guildName)
            orders = extData.orders or {}
        else
            orders = {}
        end
    end

    table.sort(orders, function(a, b)
        local aIsMine = (a.crafter == myName and a.status == GF.ORDER_STATUS.ACCEPTED) and 0 or 1
        local bIsMine = (b.crafter == myName and b.status == GF.ORDER_STATUS.ACCEPTED) and 0 or 1
        if aIsMine ~= bIsMine then return aIsMine < bIsMine end

        local statusOrder = {
            [GF.ORDER_STATUS.OPEN] = 1,
            [GF.ORDER_STATUS.ACCEPTED] = 2,
            [GF.ORDER_STATUS.COMPLETED] = 3,
            [GF.ORDER_STATUS.CANCELLED] = 4,
        }
        local sa = statusOrder[a.status] or 5
        local sb = statusOrder[b.status] or 5
        if sa ~= sb then return sa < sb end
        return (a.created or 0) > (b.created or 0)
    end)

    parent._list:SetData(orders)

    local openCount = #GF.OrderBoard:GetOrders(GF.ORDER_STATUS.OPEN)
    local myOrders = GF.OrderBoard:GetCrafterOrders(myName)
    local myActiveCount = 0
    for _, o in ipairs(myOrders) do
        if o.status == GF.ORDER_STATUS.ACCEPTED then myActiveCount = myActiveCount + 1 end
    end

    parent._countText:SetText(openCount .. " open")

    if parent._myQueueText then
        if myActiveCount > 0 then
            parent._myQueueText:SetText("|cFFFFAA00Your queue: " .. myActiveCount .. " order(s)|r")
        else
            parent._myQueueText:SetText("")
        end
    end

    self:RefreshCrafterList()
end

--- Refresh the crafter list panel
function CB:RefreshCrafterList()
    local parent = GF.UI.MainFrame:GetContentFrame("crafting")
    if not parent or not parent._crafterList then return end

    local data = {}
    local extGuildName = not IsInGuild() and GF.CommunityBridge and GF.CommunityBridge:GetConnectedGuild() or nil

    if GF.RecipeScanner then
        local summary = GF.RecipeScanner:GetCrafterSummary(extGuildName)
        if #summary > 0 then
            for _, crafter in ipairs(summary) do
                local profList = {}
                for _, p in ipairs(crafter.professions) do
                    profList[#profList + 1] = p.name .. " (" .. p.count .. ")"
                end
                data[#data + 1] = {
                    type = "crafter",
                    displayName = crafter.displayName,
                    playerName = crafter.playerName,
                    professions = table.concat(profList, ", "),
                }
            end
        end
    end

    if #data == 0 and IsInGuild() then
        local crafters = GF.Roles:GetMembersWithRole(GF.ROLES.CRAFTER)
        for _, name in ipairs(crafters) do
            data[#data + 1] = {
                type = "crafter",
                displayName = name:match("^(.+)-") or name,
                playerName = name,
                professions = "Recipes not scanned yet",
            }
        end
    end

    if #data == 0 then
        if IsInGuild() then
            data[#data + 1] = { type = "hint", text = "|cFF888888No crafters yet.|r", subtext = "Officers: assign Crafter roles." }
            data[#data + 1] = { type = "hint", text = "|cFF666666Crafters: open professions|r", subtext = "to scan & share recipes." }
        else
            local peerCount = extGuildName and GF.CommunityBridge:GetPeerCount(extGuildName) or 0
            if peerCount > 0 then
                data[#data + 1] = { type = "hint", text = "|cFF888888Syncing crafter data...|r", subtext = "Recipes will appear shortly." }
            else
                data[#data + 1] = { type = "hint", text = "|cFF888888No guild members online.|r", subtext = "Cached data will show when available." }
            end
        end
    end

    parent._crafterList:SetData(data)
end
