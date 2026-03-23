------------------------------------------------------------------------
-- Vault of Truths - UI/SettingsPanel.lua
-- Per-character notification/sync toggles and preferences
-- Modern card-based layout using Theme module
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.SettingsPanel = {}
local SP = GF.UI.SettingsPanel
local T  -- resolved lazily on first Init

local initialized = false

-- Padding / sizing constants
local PAD           = 12
local CARD_PAD      = 10
local TOGGLE_H      = 26
local COL_GAP       = 14
local HEADER_H      = 22
local SPLIT_ROW_H   = 24
local CONTROL_ROW_H = 26

--- Create a toggle checkbox widget
local function CreateToggle(parent, x, y, label, settingPath, isChar)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", x, y)

    local text = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetText(label)

    check:SetScript("OnClick", function(self)
        local val = self:GetChecked()
        -- Special case: minimapIcon.hide is inverted
        if settingPath == "minimapIcon.hide" then
            val = not val
        end
        if isChar then
            GF.Settings:SetChar(settingPath, val)
        else
            GF.Settings:Set(settingPath, val)
        end
        -- Apply debug mode immediately
        if settingPath == "debugMode" then
            GF.debug = val
            if val then
                GF.ChatNotify:Info("Debug mode |cFF00FF00ON|r")
            else
                GF.ChatNotify:Info("Debug mode |cFFFF0000OFF|r")
            end
        end
    end)

    check._settingPath = settingPath
    check._isChar = isChar
    return check
end

------------------------------------------------------------------------
-- Helper: lay toggles inside a card, returning the bottom Y consumed
------------------------------------------------------------------------
local function AddTogglesInCard(card, startY, parent, toggleDefs)
    local y = startY
    for _, def in ipairs(toggleDefs) do
        parent._toggles[#parent._toggles + 1] =
            CreateToggle(card, CARD_PAD, y, def[1], def[2], def[3])
        y = y - TOGGLE_H
    end
    return y
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
local function Init()
    if initialized then return end

    T = GF.UI.Theme

    local parent = GF.UI.MainFrame:GetContentFrame("settings")
    if not parent then return end

    parent._toggles = {}
    parent._splitControls = {}

    local pw = parent:GetWidth()
    local colW = (pw - PAD * 3) / 2    -- two equal columns with padding

    --------------------------------------------------------------------
    -- LEFT COLUMN
    --------------------------------------------------------------------
    local leftAnchor = parent  -- relative frame
    local leftX = PAD
    local curY  = -PAD

    -- ---- Notifications card ----
    local notifCard = T:Card(parent)
    notifCard:SetPoint("TOPLEFT", leftAnchor, "TOPLEFT", leftX, curY)
    notifCard:SetWidth(colW)

    local _, notifHdrC = T:SectionHeader(notifCard,
        {"TOPLEFT", notifCard, "TOPLEFT", CARD_PAD, -CARD_PAD},
        "Notifications", "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon_bell")

    local ny = -(CARD_PAD + HEADER_H + 4)
    ny = AddTogglesInCard(notifCard, ny, parent, {
        { "Show toast popups",         "notifications.toastEnabled",  true  },
        { "Show chat messages",        "notifications.chatEnabled",   true  },
        { "Play notification sounds",  "notifications.soundEnabled",  true  },
    })
    notifCard:SetHeight(-ny + CARD_PAD)

    -- ---- Loot Watcher card ----
    curY = -PAD   -- relative to bottom of previous card
    local lootCard = T:Card(parent)
    lootCard:SetPoint("TOPLEFT", notifCard, "BOTTOMLEFT", 0, -COL_GAP)
    lootCard:SetWidth(colW)

    T:SectionHeader(lootCard,
        {"TOPLEFT", lootCard, "TOPLEFT", CARD_PAD, -CARD_PAD},
        "Loot Watcher", "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon_loot")

    local ly = -(CARD_PAD + HEADER_H + 4)
    ly = AddTogglesInCard(lootCard, ly, parent, {
        { "Detect bankable PVP items", "lootWatcher.enabled",         true },
        { "Auto-print item values",    "lootWatcher.autoPrintValue",  true },
    })
    lootCard:SetHeight(-ly + CARD_PAD)

    -- ---- Sync card ----
    local syncCard = T:Card(parent)
    syncCard:SetPoint("TOPLEFT", lootCard, "BOTTOMLEFT", 0, -COL_GAP)
    syncCard:SetWidth(colW)

    T:SectionHeader(syncCard,
        {"TOPLEFT", syncCard, "TOPLEFT", CARD_PAD, -CARD_PAD},
        "Sync", "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon_sync")

    local sy = -(CARD_PAD + HEADER_H + 4)
    sy = AddTogglesInCard(syncCard, sy, parent, {
        { "Enable guild sync", "syncEnabled", false },
    })
    syncCard:SetHeight(-sy + CARD_PAD)

    -- ---- Other card ----
    local otherCard = T:Card(parent)
    otherCard:SetPoint("TOPLEFT", syncCard, "BOTTOMLEFT", 0, -COL_GAP)
    otherCard:SetWidth(colW)

    T:SectionHeader(otherCard,
        {"TOPLEFT", otherCard, "TOPLEFT", CARD_PAD, -CARD_PAD},
        "Other", "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon_gear")

    local oy = -(CARD_PAD + HEADER_H + 4)
    oy = AddTogglesInCard(otherCard, oy, parent, {
        { "Debug mode",        "debugMode",       false },
        { "Show minimap icon", "minimapIcon.hide", false },
    })
    otherCard:SetHeight(-oy + CARD_PAD)

    --------------------------------------------------------------------
    -- RIGHT COLUMN  -  Guild Configuration (owner-only)
    --------------------------------------------------------------------
    local rightX = PAD + colW + PAD

    local guildCard = T:Card(parent)
    guildCard:SetPoint("TOPLEFT", parent, "TOPLEFT", rightX, -PAD)
    guildCard:SetWidth(colW)
    parent._guildConfigCard = guildCard

    -- Header
    T:SectionHeader(guildCard,
        {"TOPLEFT", guildCard, "TOPLEFT", CARD_PAD, -CARD_PAD},
        "Guild Configuration")

    T:Hint(guildCard,
        {"TOPLEFT", guildCard, "TOPLEFT", CARD_PAD, -(CARD_PAD + HEADER_H)},
        "Only the Guild Owner can edit these values")

    -- ---- Profit Split sub-section ----
    local secY = -(CARD_PAD + HEADER_H + 18)
    T:Divider(guildCard, secY)
    secY = secY - 8

    local splitLbl = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    splitLbl:SetPoint("TOPLEFT", CARD_PAD, secY)
    splitLbl:SetText("|cFF33AAFFProfit Split|r")

    parent._splitTotal = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    parent._splitTotal:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -CARD_PAD, secY - 2)

    secY = secY - HEADER_H

    local splitLabels = { "Contributors (PVPers)", "Crafters", "Auctioneers", "Guild Tax" }
    local splitKeys   = { "contributors", "crafters", "auctioneers", "guildTax" }
    local splitColors = { {0.3,1,0.3}, {0.3,0.7,1}, {1,0.7,0.3}, {0.6,0.6,0.6} }

    for i, label in ipairs(splitLabels) do
        local ry = secY - (i - 1) * SPLIT_ROW_H

        local lbl = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", CARD_PAD + 4, ry)
        lbl:SetText(label)
        lbl:SetTextColor(splitColors[i][1], splitColors[i][2], splitColors[i][3])

        local val = guildCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -68, ry)

        local minus = T:Button(guildCard, "-", 22, 18)
        minus:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -42, ry + 2)

        local plus = T:Button(guildCard, "+", 22, 18)
        plus:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -CARD_PAD, ry + 2)

        parent._splitControls[splitKeys[i]] = { val = val, minus = minus, plus = plus }
    end

    secY = secY - (#splitLabels * SPLIT_ROW_H) - 6

    -- ---- Crafting Fee sub-section ----
    T:Divider(guildCard, secY)
    secY = secY - CONTROL_ROW_H

    local feeLbl = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    feeLbl:SetPoint("TOPLEFT", CARD_PAD, secY)
    feeLbl:SetText("Crafting Fee %:")
    feeLbl:SetTextColor(0.7, 0.7, 0.7)

    parent._feeVal = guildCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    parent._feeVal:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -68, secY)

    parent._feeMinus = T:Button(guildCard, "-", 22, 18)
    parent._feeMinus:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -42, secY + 2)

    parent._feePlus = T:Button(guildCard, "+", 22, 18)
    parent._feePlus:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -CARD_PAD, secY + 2)

    secY = secY - CONTROL_ROW_H - 4

    -- ---- TSM Price String sub-section ----
    T:Divider(guildCard, secY)
    secY = secY - 6

    local tsmLbl = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsmLbl:SetPoint("TOPLEFT", CARD_PAD, secY)
    tsmLbl:SetText("TSM Price String:")
    tsmLbl:SetTextColor(0.7, 0.7, 0.7)

    secY = secY - 18

    local tsmBox = T:EditBox(guildCard, 0, 20)
    tsmBox:SetPoint("TOPLEFT", CARD_PAD + 2, secY)
    tsmBox:SetPoint("RIGHT", guildCard, "RIGHT", -CARD_PAD - 2, 0)
    tsmBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            -- Validate by trying it against TSM
            local valid = true
            if GF.TSM and GF.TSM:IsAvailable() and TSM_API then
                local ok, val = pcall(TSM_API.GetCustomPriceValue, text, "i:2589")
                if not ok then valid = false end
            end
            if valid then
                GF.Settings:SetGuild("priceSource", text)
                -- Clear price cache so new string takes effect
                if GF.TSM then GF.TSM:ClearCache() end
                GF.ChatNotify:Success("TSM price string updated.")
            else
                GF.ChatNotify:Error("Invalid TSM price string. Check syntax.")
            end
        end
        self:ClearFocus()
    end)
    parent._tsmBox = tsmBox

    local tsmHint = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsmHint:SetPoint("TOPLEFT", CARD_PAD, secY - 20)
    tsmHint:SetPoint("RIGHT", guildCard, "RIGHT", -CARD_PAD, 0)
    tsmHint:SetText("|cFF666666e.g. first(DBMinBuyout, DBMarket) or DBRegionMarketAvg|r")
    tsmHint:SetJustifyH("LEFT")

    secY = secY - 40

    -- ---- Tracking Period sub-section ----
    T:Divider(guildCard, secY)
    secY = secY - CONTROL_ROW_H

    local periodLbl = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    periodLbl:SetPoint("TOPLEFT", CARD_PAD, secY)
    periodLbl:SetText("Tracking Period:")
    periodLbl:SetTextColor(0.7, 0.7, 0.7)

    parent._weeklyBtn = T:Button(guildCard, "Weekly", 65, 20)
    parent._weeklyBtn:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -76, secY + 1)

    parent._monthlyBtn = T:Button(guildCard, "Monthly", 65, 20)
    parent._monthlyBtn:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -CARD_PAD, secY + 1)

    secY = secY - CONTROL_ROW_H - 4

    -- ---- System Lock sub-section ----
    T:Divider(guildCard, secY)
    secY = secY - CONTROL_ROW_H

    local lockLbl = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockLbl:SetPoint("TOPLEFT", CARD_PAD, secY)
    lockLbl:SetText("System:")
    lockLbl:SetTextColor(0.7, 0.7, 0.7)

    parent._lockBtn = T:Button(guildCard, "Toggle Lock", 90, 20)
    parent._lockBtn:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -46, secY + 1)

    parent._lockStatus = guildCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    parent._lockStatus:SetPoint("TOPRIGHT", guildCard, "TOPRIGHT", -CARD_PAD, secY)

    secY = secY - CARD_PAD
    guildCard:SetHeight(-secY + CARD_PAD)

    -- ---- Version footer ----
    local infoText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("BOTTOMLEFT", PAD, 8)
    infoText:SetText("|cFF888888Vault of Truths v" .. GF.VERSION .. " | /vot help|r")

    initialized = true
end

--- Refresh settings toggles to match current values
function SP:Refresh()
    Init()

    local parent = GF.UI.MainFrame:GetContentFrame("settings")
    if not parent or not parent._toggles then return end

    for _, toggle in ipairs(parent._toggles) do
        local val
        if toggle._isChar then
            val = GF.Settings:GetChar(toggle._settingPath)
        else
            val = GF.Settings:Get(toggle._settingPath)
        end

        -- Special case: minimapIcon.hide is inverted
        if toggle._settingPath == "minimapIcon.hide" then
            val = not val
        end

        toggle:SetChecked(val ~= false) -- Default to true if nil
    end

    -- ===== Guild Configuration controls (officer+ only) =====
    local isOfficer = GF.Roles:GetPermissionLevel() >= GF.PERMISSIONS.OFFICER
    if parent._guildConfigCard then
        if isOfficer then
            parent._guildConfigCard:Show()
        else
            parent._guildConfigCard:Hide()
        end
    end

    local guildData = IsInGuild() and GF.Settings:GetGuildData() or nil
    local isOwner = GF.Utils:IsGuildMaster()

    if guildData and parent._splitControls then
        local split = guildData.guildSettings.profitSplit or GF.DEFAULT_PROFIT_SPLIT
        local splitKeys = { "contributors", "crafters", "auctioneers", "guildTax" }

        local total = 0
        for _, key in ipairs(splitKeys) do
            local v = split[key] or 0
            total = total + v
            local ctrl = parent._splitControls[key]
            if ctrl then
                ctrl.val:SetText("|cFFFFFFFF" .. v .. "%|r")
                ctrl.minus:SetScript("OnClick", function()
                    if not isOwner then GF.ChatNotify:Error("Only Guild Owner can change splits."); return end
                    if split[key] > 0 then split[key] = split[key] - 5; SP:Refresh() end
                end)
                ctrl.plus:SetScript("OnClick", function()
                    if not isOwner then GF.ChatNotify:Error("Only Guild Owner can change splits."); return end
                    split[key] = split[key] + 5; SP:Refresh()
                end)
                if isOwner then ctrl.minus:Enable(); ctrl.plus:Enable()
                else ctrl.minus:Disable(); ctrl.plus:Disable() end
            end
        end

        if parent._splitTotal then
            if total == 100 then
                parent._splitTotal:SetText("|cFF00FF00Total: " .. total .. "%|r")
            else
                parent._splitTotal:SetText("|cFFFF0000Total: " .. total .. "% (must = 100!)|r")
            end
        end

        -- Fee
        if parent._feeVal then
            local fee = guildData.guildSettings.feePercent or 10
            parent._feeVal:SetText("|cFFFFFFFF" .. fee .. "%|r")
            parent._feeMinus:SetScript("OnClick", function()
                if not isOwner then GF.ChatNotify:Error("Only Guild Owner."); return end
                if fee > 0 then guildData.guildSettings.feePercent = fee - 1; SP:Refresh() end
            end)
            parent._feePlus:SetScript("OnClick", function()
                if not isOwner then GF.ChatNotify:Error("Only Guild Owner."); return end
                guildData.guildSettings.feePercent = fee + 1; SP:Refresh()
            end)
            if isOwner then parent._feeMinus:Enable(); parent._feePlus:Enable()
            else parent._feeMinus:Disable(); parent._feePlus:Disable() end
        end

        -- TSM Price String
        if parent._tsmBox then
            local priceSource = guildData.guildSettings.priceSource or "first(DBMinBuyout, DBMarket)"
            parent._tsmBox:SetText(priceSource)
            if isOwner then
                parent._tsmBox:Enable()
                parent._tsmBox:SetTextColor(1, 1, 1)
            else
                parent._tsmBox:Disable()
                parent._tsmBox:SetTextColor(0.5, 0.5, 0.5)
            end
        end

        -- Period
        if parent._weeklyBtn then
            local period = guildData.guildSettings.trackingPeriod or "weekly"
            parent._weeklyBtn:SetScript("OnClick", function()
                if not isOwner then return end
                guildData.guildSettings.trackingPeriod = "weekly"; SP:Refresh()
            end)
            parent._monthlyBtn:SetScript("OnClick", function()
                if not isOwner then return end
                guildData.guildSettings.trackingPeriod = "monthly"; SP:Refresh()
            end)
            if period == "weekly" then parent._weeklyBtn:Disable(); parent._monthlyBtn:Enable()
            else parent._weeklyBtn:Enable(); parent._monthlyBtn:Disable() end
        end

        -- Lock
        if parent._lockBtn then
            parent._lockBtn:SetScript("OnClick", function()
                if not isOwner then GF.ChatNotify:Error("Only Guild Owner."); return end
                guildData.guildSettings.systemLocked = not guildData.guildSettings.systemLocked
                SP:Refresh()
            end)
            if guildData.guildSettings.systemLocked then
                parent._lockStatus:SetText("|cFFFF0000LOCKED|r")
            else
                parent._lockStatus:SetText("|cFF00FF00Active|r")
            end
        end
    end
end

--- Show the settings panel (from slash command)
function SP:Show()
    GF.UI.MainFrame:Show()
    -- Would ideally switch to settings tab
end
