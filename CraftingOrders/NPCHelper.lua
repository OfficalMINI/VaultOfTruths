------------------------------------------------------------------------
-- Vault of Truths - CraftingOrders/NPCHelper.lua
-- Pop-out craft queue with item icons, tooltips, shift-click linking
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.NPCHelper = {}
local NH = GF.NPCHelper
GF:RegisterModule("NPCHelper", NH)

local helperFrame = nil
local orderRows = {}
local MAX_ROWS = 8

function NH:Init()
    GF.Events:Register("CRAFTINGORDERS_SHOW_CRAFTER", function()
        NH:ShowCrafterHelper()
    end)
    GF.Events:Register("CRAFTINGORDERS_HIDE_CRAFTER", function()
        NH:Hide()
    end)
    GF.Events:Register("CRAFTINGORDERS_SHOW_CUSTOMER", function()
        NH:ShowCustomerHelper()
    end)
    GF.Events:Register("CRAFTINGORDERS_HIDE_CUSTOMER", function()
        NH:Hide()
    end)

    -- Auto-pop craft queue when a new order comes in or is created
    GF.Events:On("GF_ORDER_CREATED", function()
        NH:ShowCrafterHelper()
    end)
    GF.Events:On("GF_ORDER_RECEIVED", function()
        NH:ShowCrafterHelper()
    end)
end

local function EnsureFrame()
    if helperFrame then return end

    helperFrame = CreateFrame("Frame", "VoTCraftQueue", UIParent, "BackdropTemplate")
    helperFrame:SetSize(300, 360)
    helperFrame:SetPoint("TOPLEFT", UIParent, "CENTER", 310, 150)
    helperFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    helperFrame:SetBackdropColor(0.04, 0.06, 0.1, 0.96)
    helperFrame:SetBackdropBorderColor(0.2, 0.5, 0.8, 0.9)
    helperFrame:SetFrameStrata("DIALOG")
    helperFrame:SetMovable(true)
    helperFrame:EnableMouse(true)
    helperFrame:SetClampedToScreen(true)

    -- Title bar (draggable)
    local titleBar = CreateFrame("Frame", nil, helperFrame)
    titleBar:SetHeight(22)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() helperFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() helperFrame:StopMovingOrSizing() end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 8, 0)
    helperFrame._title = title

    local closeBtn = CreateFrame("Button", nil, helperFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -1, -1)
    closeBtn:SetSize(22, 22)

    -- Row templates
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, helperFrame)
        row:SetHeight(40)
        if i == 1 then
            row:SetPoint("TOPLEFT", 6, -28)
            row:SetPoint("RIGHT", -6, 0)
        else
            row:SetPoint("TOPLEFT", orderRows[i - 1], "BOTTOMLEFT", 0, -2)
            row:SetPoint("RIGHT", -6, 0)
        end

        -- Background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        row._bg = bg

        -- Highlight
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.15, 0.3, 0.5, 0.4)

        -- Item icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(32, 32)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        -- Item name (top line)
        row.itemName = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.itemName:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.itemName:SetPoint("RIGHT", -6, 0)
        row.itemName:SetJustifyH("LEFT")

        -- Details (bottom line)
        row.details = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.details:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
        row.details:SetPoint("RIGHT", -6, 0)
        row.details:SetJustifyH("LEFT")
        row.details:SetTextColor(0.5, 0.5, 0.5)

        row._itemLink = nil
        row._itemName = nil

        -- Tooltip on hover
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._itemLink then
                GameTooltip:SetHyperlink(self._itemLink)
            elseif self._itemName then
                GameTooltip:SetText(self._itemName, 0.2, 0.67, 1)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cFFFFFF00Shift-click|r to paste into search/chat", 1, 1, 1)
            GameTooltip:Show()
        end)

        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Shift-click: insert item link or name into focused editbox
        row:SetScript("OnClick", function(self, button)
            if IsShiftKeyDown() then
                local text = self._itemLink or self._itemName or ""
                if text ~= "" then
                    local editBox = GetCurrentKeyBoardFocus()
                    if editBox then
                        editBox:Insert(text)
                    elseif ChatFrame1EditBox and ChatFrame1EditBox:IsShown() then
                        ChatFrame1EditBox:Insert(text)
                    else
                        ChatFrame_OpenChat(text)
                    end
                end
            end
        end)

        row:RegisterForClicks("LeftButtonUp")
        row:Hide()
        orderRows[i] = row
    end

    -- Bottom hint
    helperFrame._hint = helperFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helperFrame._hint:SetPoint("BOTTOMLEFT", 8, 8)
    helperFrame._hint:SetPoint("BOTTOMRIGHT", -8, 8)
    helperFrame._hint:SetJustifyH("CENTER")
    helperFrame._hint:SetTextColor(0.4, 0.4, 0.4)

    helperFrame:Hide()
end

--- Collect all possible item IDs from an order for cache priming
local function GetOrderItemIDs(order)
    local ids = {}
    if order.outputItemID then ids[#ids + 1] = order.outputItemID end
    if order.recipeID then ids[#ids + 1] = order.recipeID end
    if order.mats then
        for _, mat in ipairs(order.mats) do
            if mat.itemID then ids[#ids + 1] = mat.itemID end
        end
    end
    return ids
end

--- Try to resolve an item ID, name, link, and icon from order data
local function ResolveItemInfo(order)
    local itemName, itemLink, itemIcon, itemID

    -- 1. If order has an explicit itemID stored, use that
    if order.outputItemID then
        itemName, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(order.outputItemID)
        if itemLink then return itemName, itemLink, itemIcon, order.outputItemID end
    end

    -- 2. Try recipeID as an item ID (works if the order stored an actual item ID)
    if order.recipeID then
        itemName, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(order.recipeID)
        if itemLink then return itemName, itemLink, itemIcon, order.recipeID end
    end

    -- 3. Try the first mat's item ID
    if order.mats and order.mats[1] and order.mats[1].itemID then
        local matID = order.mats[1].itemID
        itemName, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(matID)
        if itemLink then return itemName, itemLink, itemIcon, matID end
    end

    -- 4. Try to find by recipe name in the game item cache
    if order.recipeName then
        itemName, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(order.recipeName)
        if itemLink then
            local id = itemLink:match("item:(%d+)")
            return itemName, itemLink, itemIcon, id and tonumber(id)
        end
    end

    return nil, nil, nil, nil
end

--- Update a single row with resolved item data
local function UpdateRowItemInfo(row, order)
    local itemName, itemLink, itemIcon, itemID = ResolveItemInfo(order)

    if itemIcon then
        row.icon:SetTexture(itemIcon)
    end
    if itemLink then
        row._itemLink = itemLink
        -- Show the linked item name with quality color
        local displayName = itemLink:match("%[(.-)%]") or itemName or order.recipeName
        row.itemName:SetText(itemLink)
    end
    row._itemName = order.recipeName or itemName
end

--- Fill rows with order data
local function PopulateOrders(orders, mode)
    -- Prime the item cache for all orders so icons/links resolve
    for _, order in ipairs(orders) do
        local ids = GetOrderItemIDs(order)
        for _, id in ipairs(ids) do
            C_Item.GetItemInfo(id) -- triggers async cache request
        end
    end

    for i = 1, MAX_ROWS do
        local row = orderRows[i]
        local order = orders[i]

        if order then
            local itemName, itemLink, itemIcon, itemID = ResolveItemInfo(order)

            row.icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
            -- Show item link (colored, clickable-looking) if available, else recipe name
            if itemLink then
                row.itemName:SetText(itemLink)
            else
                row.itemName:SetText(order.recipeName or "Unknown")
            end

            local requester = order.requester or "?"
            local crafter = order.crafter or "Open"

            if mode == "crafter" then
                local supply = order.supplyMode == "guild" and "Guild mats" or "Their mats"
                if order.status == GF.ORDER_STATUS.ACCEPTED and order.crafter == GF.Utils:GetPlayerFullName() then
                    row.details:SetText("|cFFFFAA00YOUR ORDER|r — For: " .. requester .. " — " .. supply)
                    row._bg:SetColorTexture(0.12, 0.1, 0.04, 0.8)
                else
                    row.details:SetText("For: " .. requester .. " — " .. supply .. " — " .. crafter)
                    row._bg:SetColorTexture(i % 2 == 0 and 0.06 or 0.08, i % 2 == 0 and 0.08 or 0.1, i % 2 == 0 and 0.12 or 0.16, 0.7)
                end
            else
                row.details:SetText("Crafter: |cFF00AAFF" .. crafter .. "|r")
                row._bg:SetColorTexture(i % 2 == 0 and 0.06 or 0.08, i % 2 == 0 and 0.08 or 0.1, i % 2 == 0 and 0.12 or 0.16, 0.7)
            end

            row._itemLink = itemLink
            row._itemName = order.recipeName or itemName
            row._order = order
            row:Show()
        else
            row._order = nil
            row:Hide()
        end
    end

    -- Retry after a short delay for items that weren't cached yet
    -- GET_ITEM_INFO_RECEIVED fires per-item but a simple delayed refresh is simpler
    C_Timer.After(0.5, function()
        for i = 1, MAX_ROWS do
            local row = orderRows[i]
            if row._order and not row._itemLink then
                UpdateRowItemInfo(row, row._order)
            end
        end
    end)
end

function NH:ShowCrafterHelper()
    EnsureFrame()

    local myName = GF.Utils:GetPlayerFullName()
    local myOrders = GF.OrderBoard:GetCrafterOrders(myName)

    local active = {}
    for _, order in ipairs(myOrders) do
        if order.status == GF.ORDER_STATUS.ACCEPTED then
            active[#active + 1] = order
        end
    end

    local openOrders = GF.OrderBoard:GetOrders(GF.ORDER_STATUS.OPEN)
    local allOrders = {}
    for _, o in ipairs(active) do allOrders[#allOrders + 1] = o end
    for _, o in ipairs(openOrders) do allOrders[#allOrders + 1] = o end

    helperFrame._title:SetText("|cFF33AAFFCraft Queue|r — " .. #active .. " yours, " .. #openOrders .. " open")
    PopulateOrders(allOrders, "crafter")

    helperFrame._hint:SetText("Shift-click item to paste into NPC search")

    local rowCount = math.min(#allOrders, MAX_ROWS)
    helperFrame:SetHeight(math.max(rowCount * 42 + 46, 90))
    helperFrame:Show()
end

function NH:ShowCustomerHelper()
    EnsureFrame()

    local crafterEntries = {}

    if GF.RecipeScanner then
        local summary = GF.RecipeScanner:GetCrafterSummary()
        for _, crafter in ipairs(summary) do
            local profs = {}
            for _, p in ipairs(crafter.professions) do
                profs[#profs + 1] = p.name
            end
            crafterEntries[#crafterEntries + 1] = {
                recipeName = crafter.displayName,
                _isCrafter = true,
                _professions = table.concat(profs, ", "),
                crafter = crafter.playerName,
            }
        end
    end

    if #crafterEntries == 0 then
        local crafters = GF.Roles:GetMembersWithRole(GF.ROLES.CRAFTER)
        for _, name in ipairs(crafters) do
            crafterEntries[#crafterEntries + 1] = {
                recipeName = name:match("^(.+)-") or name,
                _isCrafter = true,
                _professions = "Guild crafter",
                crafter = name,
            }
        end
    end

    helperFrame._title:SetText("|cFF33AAFFGuild Crafters|r — Shift-click for recipient name")

    for i = 1, MAX_ROWS do
        local row = orderRows[i]
        local entry = crafterEntries[i]

        if entry then
            row.icon:SetTexture("Interface\\Icons\\Trade_Engineering")
            row.itemName:SetText("|cFF00FF00" .. entry.recipeName .. "|r")
            row.details:SetText(entry._professions or "")
            row._itemLink = nil
            row._itemName = entry.recipeName
            row._bg:SetColorTexture(i % 2 == 0 and 0.06 or 0.08, i % 2 == 0 and 0.08 or 0.1, i % 2 == 0 and 0.12 or 0.16, 0.7)

            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(entry.recipeName, 0, 1, 0)
                GameTooltip:AddLine(entry._professions, 0.7, 0.7, 0.7)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFFFFF00Shift-click|r to paste into recipient field", 1, 1, 1)
                GameTooltip:Show()
            end)

            row:Show()
        else
            row:Hide()
        end
    end

    helperFrame._hint:SetText("Shift-click name to paste into Personal order recipient")

    local rowCount = math.min(#crafterEntries, MAX_ROWS)
    helperFrame:SetHeight(math.max(rowCount * 42 + 46, 90))
    helperFrame:Show()
end

function NH:Hide()
    if helperFrame then helperFrame:Hide() end
end

function NH:Toggle()
    EnsureFrame()
    if helperFrame:IsShown() then
        helperFrame:Hide()
    else
        NH:ShowCrafterHelper()
    end
end
