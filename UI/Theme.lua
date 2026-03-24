------------------------------------------------------------------------
-- Vault of Truths - UI/Theme.lua
-- Shared UI helpers: cards, headers, dividers, stat rows
-- Modern, clean, consistent visual language across all panels
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.Theme = {}
local T = GF.UI.Theme

-- Color palette
T.COLORS = {
    headerGold    = { 1, 0.8, 0 },
    accent        = { 0.2, 0.67, 1 },
    textNormal    = { 0.85, 0.85, 0.85 },
    textDim       = { 0.5, 0.5, 0.5 },
    textMuted     = { 0.35, 0.35, 0.35 },
    positive      = { 0, 0.9, 0.3 },
    negative      = { 1, 0.3, 0.3 },
    warning       = { 1, 0.67, 0 },
    gold          = { 1, 0.82, 0 },
    cardBg        = { 0.06, 0.07, 0.11, 0.92 },
    cardBorder    = { 0.18, 0.28, 0.45, 0.7 },
    divider       = { 0.2, 0.3, 0.5, 0.4 },
    rowAlt        = { 1, 1, 1, 0.02 },
    rowHover      = { 0.2, 0.4, 0.6, 0.3 },
}

-- Shared backdrop for cards — thin 1px border, no chunky WoW tooltip edges
T.CARD_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

--- Create a card (bordered block with background)
---@param parent Frame
---@return Frame card
function T:Card(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetBackdrop(self.CARD_BACKDROP)
    card:SetBackdropColor(0.08, 0.09, 0.14, 0.9)
    card:SetBackdropBorderColor(0.15, 0.22, 0.35, 0.6)
    return card
end

--- Create a section header with icon and gold text
---@param parent Frame
---@param anchor table { point, relativeTo, relativePoint, x, y }
---@param text string
---@param icon string|nil Icon texture path
---@return FontString header
function T:SectionHeader(parent, anchor, text, icon)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(18)

    if type(anchor) == "number" then
        -- Simple Y offset from top
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, anchor)
        container:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    else
        container:SetPoint(unpack(anchor))
        container:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    end

    if icon then
        local iconTex = container:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(14, 14)
        iconTex:SetPoint("LEFT", 0, 0)
        iconTex:SetTexture(icon)

        local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        label:SetText("|cFFFFCC00" .. text .. "|r")
        return label, container
    else
        local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", 0, 0)
        label:SetText("|cFFFFCC00" .. text .. "|r")
        return label, container
    end
end

--- Create a horizontal divider line
---@param parent Frame
---@param y number Y offset from top of parent
---@return Texture
function T:Divider(parent, y)
    local div = parent:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    div:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    div:SetColorTexture(unpack(self.COLORS.divider))
    return div
end

--- Divider anchored below a frame
---@param parent Frame
---@param anchor Frame Frame to anchor below
---@param spacing number|nil Vertical spacing (default 4)
---@return Texture
function T:DividerBelow(parent, anchor, spacing)
    local div = parent:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(spacing or 4))
    div:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    div:SetColorTexture(unpack(self.COLORS.divider))
    return div
end

--- Create a stat row (label left, value right) inside a card
---@param card Frame
---@param y number Y offset
---@param label string
---@return FontString valueFS
function T:StatRow(card, y, label)
    local lbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 10, y)
    lbl:SetText(label)
    lbl:SetTextColor(unpack(self.COLORS.textDim))

    local val = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("TOPRIGHT", -10, y)
    return val
end

--- Style a row with alternating background
---@param row Frame
---@param index number
function T:StripeRow(row, index)
    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(unpack(self.COLORS.rowAlt))
    end
end

--- Create a flat themed button (no WoW chrome)
---@param parent Frame
---@param text string
---@param width number|nil
---@param height number|nil
---@return Button
function T:Button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:RegisterForClicks("AnyUp")
    btn:SetSize(width or 120, height or 24)
    btn:SetBackdrop(self.CARD_BACKDROP)
    btn:SetBackdropColor(0.14, 0.18, 0.28, 0.9)
    btn:SetBackdropBorderColor(0.2, 0.35, 0.55, 0.7)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(0.9, 0.9, 0.9)
    btn._label = label

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.3, 0.45, 0.95)
        self:SetBackdropBorderColor(0.3, 0.5, 0.8, 0.9)
    end)
    btn:SetScript("OnLeave", function(self)
        if self._disabled then
            self:SetBackdropColor(0.08, 0.09, 0.12, 0.6)
        else
            self:SetBackdropColor(0.14, 0.18, 0.28, 0.9)
        end
        self:SetBackdropBorderColor(0.2, 0.35, 0.55, 0.7)
    end)
    -- Override SetText
    function btn:SetText(t)
        self._label:SetText(t)
    end
    function btn:GetFontString()
        return self._label
    end
    function btn:Disable()
        self._disabled = true
        self:SetBackdropColor(0.08, 0.09, 0.12, 0.6)
        self._label:SetTextColor(0.4, 0.4, 0.4)
        self:EnableMouse(false)
    end
    function btn:Enable()
        self._disabled = false
        self:SetBackdropColor(0.14, 0.18, 0.28, 0.9)
        self._label:SetTextColor(0.9, 0.9, 0.9)
        self:EnableMouse(true)
    end

    return btn
end

--- Create a styled action button (alias for Button with accent color)
---@param parent Frame
---@param text string
---@param width number|nil
---@param height number|nil
---@return Button
function T:ActionButton(parent, text, width, height)
    local btn = self:Button(parent, text, width, height)
    btn:SetBackdropColor(0.12, 0.22, 0.38, 0.9)
    btn:SetBackdropBorderColor(0.2, 0.45, 0.7, 0.8)
    btn._label:SetTextColor(1, 0.85, 0.3)
    return btn
end

--- Create a themed edit box (no WoW InputBoxTemplate)
---@param parent Frame
---@param width number|nil
---@param height number|nil
---@return EditBox
function T:EditBox(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 200, height or 22)
    box:SetBackdrop(self.CARD_BACKDROP)
    box:SetBackdropColor(0.04, 0.05, 0.08, 0.9)
    box:SetBackdropBorderColor(0.15, 0.22, 0.35, 0.6)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.3, 0.5, 0.8, 0.9)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.15, 0.22, 0.35, 0.6)
    end)
    return box
end

--- Muted hint text
---@param parent Frame
---@param anchor table|Frame
---@param text string
---@return FontString
function T:Hint(parent, anchor, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if type(anchor) == "table" then
        fs:SetPoint(unpack(anchor))
    else
        fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    fs:SetText("|cFF666666" .. text .. "|r")
    fs:SetJustifyH("LEFT")
    return fs
end
