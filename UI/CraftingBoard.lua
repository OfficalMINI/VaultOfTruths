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

    local parent = GF.UI.MainFrame:GetContentFrame("crafting")
    if not parent then return end

    -- Header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetText("|cFF33AAFFGuild Crafting|r")

    -- Open orders count
    local countText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("LEFT", header, "RIGHT", 12, 0)
    countText:SetTextColor(0.6, 0.6, 0.6)
    parent._countText = countText

    -- My Queue indicator (shows if you have assigned orders)
    local myQueueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    myQueueText:SetPoint("TOPLEFT", 8, -24)
    myQueueText:SetTextColor(1, 0.5, 0)
    parent._myQueueText = myQueueText

    -- Guild Crafters panel (right side)
    local crafterPanel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    crafterPanel:SetPoint("TOPRIGHT", -4, -36)
    crafterPanel:SetWidth(200)
    crafterPanel:SetPoint("BOTTOM", 0, 60)
    crafterPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    crafterPanel:SetBackdropColor(0.06, 0.08, 0.14, 0.9)

    local crafterTitle = crafterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    crafterTitle:SetPoint("TOP", 0, -4)
    crafterTitle:SetText("|cFF33AAFFGuild Crafters|r")

    -- Search box
    local crafterSearch = CreateFrame("EditBox", nil, crafterPanel, "InputBoxTemplate")
    crafterSearch:SetSize(170, 20)
    crafterSearch:SetPoint("TOP", 0, -22)
    crafterSearch:SetAutoFocus(false)
    crafterSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local searchHint = crafterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchHint:SetPoint("TOP", crafterSearch, "BOTTOM", 0, -1)
    searchHint:SetText("|cFF555555Search recipes...|r")

    -- Crafter scroll list (interactive rows)
    local crafterListFrame = CreateFrame("Frame", nil, crafterPanel)
    crafterListFrame:SetPoint("TOPLEFT", 4, -58)
    crafterListFrame:SetPoint("BOTTOMRIGHT", -4, 4)

    local crafterList = GF.UI.Widgets:CreateScrollList(crafterListFrame, 38,
        function(index, contentFrame)
            local row = CreateFrame("Button", nil, contentFrame)

            -- Highlight on hover
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.2, 0.4, 0.6, 0.3)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("TOPLEFT", 4, -3)
            row.name:SetPoint("RIGHT", -4, 0)
            row.name:SetJustifyH("LEFT")

            row.info = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.info:SetPoint("TOPLEFT", 4, -16)
            row.info:SetPoint("RIGHT", -4, 0)
            row.info:SetJustifyH("LEFT")
            row.info:SetTextColor(0.5, 0.5, 0.5)

            -- Separator line
            local sep = row:CreateTexture(nil, "ARTWORK")
            sep:SetHeight(1)
            sep:SetPoint("BOTTOMLEFT", 2, 0)
            sep:SetPoint("BOTTOMRIGHT", -2, 0)
            sep:SetColorTexture(0.2, 0.2, 0.3, 0.4)

            return row
        end,
        function(row, entry)
            if entry.type == "crafter" then
                row.name:SetText("|cFF00FF00" .. entry.displayName .. "|r")
                row.info:SetText(entry.professions or "")
                row:SetScript("OnClick", function()
                    -- Show what this crafter can make
                    if parent._crafterSearch and GF.RecipeScanner then
                        parent._crafterSearch:SetText("")
                        local extGuild = not IsInGuild() and GF.CommunityBridge and GF.CommunityBridge:GetConnectedGuild() or nil
                        local profs = GF.RecipeScanner:GetPlayerProfessions(entry.playerName, extGuild)
                        local data = {}
                        for profName, profData in pairs(profs) do
                            -- Show first 15 recipes from each profession
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
                    -- Build cost breakdown text
                    local commission = GF.Settings:GetGuild("craftCommission") or GF.DEFAULT_CRAFT_COMMISSION
                    local commissionText = GF.Utils:FormatMoney(commission)

                    -- Try to calculate mat cost from stored reagents
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

                    -- Check if requester has balance to pay from earnings
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
                                -- Try to pay from balance if sufficient
                                local myName = GF.Utils:GetPlayerFullName()
                                local myBalance = GF.Payouts:GetBalance(myName)
                                local orderFee = totalOrderCost > 0 and totalOrderCost or commission

                                -- Guild member: create order directly
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

                                    -- Deduct from balance if available
                                    if myBalance >= orderFee and orderFee > 0 then
                                        local ok = GF.Payouts:PayFromBalance(myName, orderFee, entry.recipeName or "craft order")
                                        if ok then
                                            order.paidFromBalance = true
                                            order.paidAmount = orderFee
                                        end
                                    elseif myBalance > 0 and orderFee > 0 then
                                        -- Partial payment from balance
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
                                -- Non-guildie: create external order
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

    -- Order list (left of crafter panel)
    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", 8, -42)
    listFrame:SetPoint("BOTTOMRIGHT", crafterPanel, "BOTTOMLEFT", -4, 0)

    local list = GF.UI.Widgets:CreateScrollList(listFrame, 40,
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
            row:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            row:SetBackdropColor(0.12, 0.12, 0.18, 0.6)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.name:SetPoint("TOPLEFT", 8, -4)
            row.name:SetTextColor(1, 1, 1)

            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.status:SetPoint("TOPRIGHT", -8, -4)

            row.details = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.details:SetPoint("BOTTOMLEFT", 8, 4)
            row.details:SetTextColor(0.6, 0.6, 0.6)

            row.fee = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.fee:SetPoint("BOTTOMRIGHT", -8, 4)
            row.fee:SetTextColor(1, 0.82, 0)

            -- Action buttons (right side of row)
            row.acceptBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.acceptBtn:SetSize(60, 20)
            row.acceptBtn:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
            row.acceptBtn:SetText("Accept")
            row.acceptBtn:Hide()

            row.completeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.completeBtn:SetSize(70, 20)
            row.completeBtn:SetPoint("RIGHT", row.acceptBtn, "LEFT", -4, 0)
            row.completeBtn:SetText("Complete")
            row.completeBtn:Hide()

            row.cancelBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.cancelBtn:SetSize(60, 20)
            row.cancelBtn:SetPoint("RIGHT", row.completeBtn, "LEFT", -4, 0)
            row.cancelBtn:SetText("Cancel")
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

            -- Accept: open orders, player has crafter role
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

            -- Complete: accepted orders where you're the crafter
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

            -- Cancel: open/accepted, requester or officer
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

    -- Bottom action bar
    local actionBar = CreateFrame("Frame", nil, parent)
    actionBar:SetHeight(50)
    actionBar:SetPoint("BOTTOMLEFT", 8, 4)
    actionBar:SetPoint("BOTTOMRIGHT", -8, 4)

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, actionBar, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 26)
    refreshBtn:SetPoint("LEFT", 0, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() CB:Refresh() end)

    -- Post Order button
    local postBtn = CreateFrame("Button", nil, actionBar, "UIPanelButtonTemplate")
    postBtn:SetSize(100, 26)
    postBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
    postBtn:SetText("Post Order")

    -- === Order Creation Overlay ===
    local overlay = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    overlay:SetAllPoints(listFrame)
    overlay:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    overlay:SetBackdropColor(0.08, 0.08, 0.12, 0.98)
    overlay:SetFrameLevel(parent:GetFrameLevel() + 10)
    overlay:Hide()
    parent._orderOverlay = overlay

    -- Title bar with icon
    local overlayTitleIcon = overlay:CreateTexture(nil, "ARTWORK")
    overlayTitleIcon:SetSize(20, 20)
    overlayTitleIcon:SetPoint("TOPLEFT", 10, -8)
    overlayTitleIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")

    local overlayTitle = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    overlayTitle:SetPoint("LEFT", overlayTitleIcon, "RIGHT", 6, 0)
    overlayTitle:SetText("|cFF33AAFFPost Crafting Order|r")

    local overlaySubtitle = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlaySubtitle:SetPoint("TOPLEFT", 12, -32)
    overlaySubtitle:SetPoint("RIGHT", -12, 0)
    overlaySubtitle:SetText("|cFF888888Search for an item, pick who supplies mats, and submit.|r")
    overlaySubtitle:SetJustifyH("LEFT")

    -- Divider
    local div1 = overlay:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT", 8, -46)
    div1:SetPoint("RIGHT", -8, 0)
    div1:SetColorTexture(0.2, 0.3, 0.5, 0.5)

    -- Section 1: Item Search
    local searchIcon = overlay:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("TOPLEFT", 12, -52)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")

    local searchLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
    searchLabel:SetText("Item to Craft")
    searchLabel:SetTextColor(1, 0.82, 0)

    local searchBox = CreateFrame("EditBox", nil, overlay, "InputBoxTemplate")
    searchBox:SetSize(280, 22)
    searchBox:SetPoint("TOPLEFT", 12, -70)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Selected item display
    local selectedFrame = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    selectedFrame:SetPoint("TOPLEFT", 12, -98)
    selectedFrame:SetPoint("RIGHT", overlay, "RIGHT", -12, 0)
    selectedFrame:SetHeight(40)
    selectedFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    selectedFrame:SetBackdropColor(0.1, 0.15, 0.2, 0.8)

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

    -- "Who can craft this" display
    local crafterMatchText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    crafterMatchText:SetPoint("TOPLEFT", selectedFrame, "BOTTOMLEFT", 0, -4)
    crafterMatchText:SetPoint("RIGHT", overlay, "RIGHT", -12, 0)
    crafterMatchText:SetJustifyH("LEFT")
    crafterMatchText:SetWordWrap(true)
    crafterMatchText:SetTextColor(0.6, 0.6, 0.6)
    crafterMatchText:SetText("")
    overlay._crafterMatchText = crafterMatchText

    -- Autocomplete dropdown
    local dropdown = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -2)
    dropdown:SetPoint("RIGHT", overlay, "RIGHT", -12, 0)
    dropdown:SetHeight(160)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    dropdown:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
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
        hl:SetColorTexture(0.2, 0.4, 0.6, 0.4)

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

    -- Search function: scan cached items by name
    local function DoSearch(query)
        if not query or #query < 2 then
            dropdown:Hide()
            return
        end

        query = query:lower()
        local results = {}

        -- Search common crafted item ID ranges (scan cached items)
        -- WoW caches items you've seen; GetItemInfo returns nil for uncached
        -- We scan a range of IDs known to contain TWW/Midnight craftable items
        local scanRanges = {
            {190000, 200000},  -- Dragonflight crafts
            {210000, 215000},  -- TWW S1
            {220000, 232000},  -- TWW S2-S3
            {240000, 257000},  -- Midnight
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

        -- Also search items in player bags
        for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
            local slots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, slots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(info.itemID)
                    if name and name:lower():find(query, 1, true) then
                        -- Dedupe
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

        -- Sort by quality descending
        table.sort(results, function(a, b) return a.quality > b.quality end)

        -- Populate dropdown
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
                row._itemID = r.itemID
                row._itemName = r.name
                row._itemIcon = r.icon
                row:SetScript("OnClick", function()
                    overlay._selectedItemID = r.itemID
                    overlay._selectedName = r.name
                    selectedIcon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    selectedText:SetText(colorPrefix .. r.name .. "|r  (ID: " .. r.itemID .. ")")
                    searchBox:SetText(r.name)
                    searchBox:ClearFocus()
                    dropdown:Hide()

                    -- Search for guild crafters who can make this
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

    -- Throttle search to avoid scanning every keystroke
    local searchTimer = nil
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.3, function()
            DoSearch(self:GetText())
        end)
    end)

    searchBox:SetScript("OnEnterPressed", function(self)
        DoSearch(self:GetText())
    end)

    -- Divider
    local div2 = overlay:CreateTexture(nil, "ARTWORK")
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT", 8, -148)
    div2:SetPoint("RIGHT", -8, 0)
    div2:SetColorTexture(0.2, 0.3, 0.5, 0.5)

    -- Section 2: Supply Mode
    local supplyIcon = overlay:CreateTexture(nil, "ARTWORK")
    supplyIcon:SetSize(14, 14)
    supplyIcon:SetPoint("TOPLEFT", 12, -154)
    supplyIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10_Green")

    local supplyLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    supplyLabel:SetPoint("LEFT", supplyIcon, "RIGHT", 4, 0)
    supplyLabel:SetText("Material Supply")
    supplyLabel:SetTextColor(1, 0.82, 0)

    overlay._supplyMode = "guild"

    local guildMatBtn = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
    guildMatBtn:SetSize(130, 26)
    guildMatBtn:SetPoint("TOPLEFT", 12, -174)
    guildMatBtn:SetText("Guild Supplies")

    local reqMatBtn = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
    reqMatBtn:SetSize(130, 26)
    reqMatBtn:SetPoint("LEFT", guildMatBtn, "RIGHT", 8, 0)
    reqMatBtn:SetText("I Supply Mats")

    -- Supply mode explanation text
    local supplyExplain = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    supplyExplain:SetPoint("TOPLEFT", 12, -204)
    supplyExplain:SetPoint("RIGHT", -12, 0)
    supplyExplain:SetJustifyH("LEFT")
    supplyExplain:SetWordWrap(true)
    overlay._supplyExplain = supplyExplain

    -- Cost preview
    local costPreview = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    costPreview:SetPoint("TOPLEFT", 12, -224)
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

    -- Divider
    local div3 = overlay:CreateTexture(nil, "ARTWORK")
    div3:SetHeight(1)
    div3:SetPoint("TOPLEFT", 8, -246)
    div3:SetPoint("RIGHT", -8, 0)
    div3:SetColorTexture(0.2, 0.3, 0.5, 0.5)

    -- Section 3: Notes
    local notesIcon = overlay:CreateTexture(nil, "ARTWORK")
    notesIcon:SetSize(14, 14)
    notesIcon:SetPoint("TOPLEFT", 12, -252)
    notesIcon:SetTexture("Interface\\Icons\\INV_Inscription_Scroll")

    local notesLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLabel:SetPoint("LEFT", notesIcon, "RIGHT", 4, 0)
    notesLabel:SetText("Notes")
    notesLabel:SetTextColor(1, 0.82, 0)

    local notesHint = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notesHint:SetPoint("LEFT", notesLabel, "RIGHT", 8, 0)
    notesHint:SetText("|cFF666666(optional — quality, enchant, etc.)|r")

    local notesBox = CreateFrame("EditBox", nil, overlay, "InputBoxTemplate")
    notesBox:SetSize(280, 22)
    notesBox:SetPoint("TOPLEFT", 12, -270)
    notesBox:SetAutoFocus(false)
    notesBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    overlay._notesBox = notesBox

    -- Submit / Cancel
    local submitBtn = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
    submitBtn:SetSize(140, 30)
    submitBtn:SetPoint("BOTTOMLEFT", 12, 12)
    submitBtn:SetText("Submit Order")
    submitBtn:SetScript("OnClick", function()
        local itemID = overlay._selectedItemID
        local itemName = overlay._selectedName
        if not itemName or itemName == "" then
            GF.ChatNotify:Warning("Search and select an item first.")
            return
        end

        -- Build mats from the item info if available (simplified — just the item itself)
        local mats = {}
        if itemID then
            mats[#mats + 1] = { itemID = itemID, quantity = 1 }
        end

        local notes = notesBox:GetText()
        if notes and notes ~= "" then
            itemName = itemName .. " (" .. notes .. ")"
        end

        -- Show cost confirmation for guild mat orders
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
            -- Calculate mat cost if we have reagent data
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

    local cancelFormBtn = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
    cancelFormBtn:SetSize(100, 30)
    cancelFormBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    cancelFormBtn:SetText("Cancel")
    cancelFormBtn:SetScript("OnClick", function() overlay:Hide() end)

    -- Post button toggles overlay
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
        -- Non-guildie: show orders from external guild data
        local guildName = GF.CommunityBridge and GF.CommunityBridge:GetConnectedGuild()
        if guildName then
            local extData = GF.Settings:GetExternalGuildData(guildName)
            orders = extData.orders or {}
        else
            orders = {}
        end
    end

    -- Sort: MY assigned orders first, then open, then others
    table.sort(orders, function(a, b)
        -- My accepted orders always on top
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

    -- Counts
    local openCount = #GF.OrderBoard:GetOrders(GF.ORDER_STATUS.OPEN)
    local myOrders = GF.OrderBoard:GetCrafterOrders(myName)
    local myActiveCount = 0
    for _, o in ipairs(myOrders) do
        if o.status == GF.ORDER_STATUS.ACCEPTED then myActiveCount = myActiveCount + 1 end
    end

    parent._countText:SetText(openCount .. " open")

    if parent._myQueueText then
        if myActiveCount > 0 then
            parent._myQueueText:SetText("|cFFFFAA00Your queue: " .. myActiveCount .. " order(s) to craft|r")
        else
            parent._myQueueText:SetText("")
        end
    end

    -- Refresh crafter directory
    self:RefreshCrafterList()
end

--- Refresh the crafter list panel (default view when not searching)
function CB:RefreshCrafterList()
    local parent = GF.UI.MainFrame:GetContentFrame("crafting")
    if not parent or not parent._crafterList then return end

    local data = {}

    -- Determine which guild data source to use
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

    -- Fallback: role-based crafters without recipe data (guild members only)
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

