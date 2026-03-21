------------------------------------------------------------------------
-- Vault of Truths - UI/Widgets/TabGroup.lua
-- Tab button switching for the main frame
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
if not GF.UI.Widgets then GF.UI.Widgets = {} end

--- Create a tab group widget
---@param parent Frame Parent frame
---@param tabs table Array of { id, label, content (Frame) }
---@param onChange function(tabID) Callback when tab changes
---@return table TabGroup widget
function GF.UI.Widgets:CreateTabGroup(parent, tabs, onChange)
    local widget = {}
    widget.tabs = tabs
    widget.activeTab = nil

    local TAB_HEIGHT = 32
    local INDICATOR_HEIGHT = 3
    local SIDE_MARGIN = 8

    local tabButtons = {}
    local contentFrames = {}

    local numTabs = #tabs
    local availableWidth = parent:GetWidth() - (SIDE_MARGIN * 2)
    local tabWidth = availableWidth / numTabs

    for i, tab in ipairs(tabs) do
        -- Tab button
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(tabWidth, TAB_HEIGHT)
        if i == 1 then
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", SIDE_MARGIN, -4)
        else
            btn:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", 0, 0)
        end

        -- Button background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.08, 0.12, 0.7)
        btn._bg = bg

        -- Button text
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER", 0, 1)
        text:SetText(tab.label)
        text:SetTextColor(0.55, 0.55, 0.55)
        btn._text = text

        -- Hover highlight
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.04)

        -- Active indicator (bottom bar)
        local indicator = btn:CreateTexture(nil, "OVERLAY")
        indicator:SetHeight(INDICATOR_HEIGHT)
        indicator:SetPoint("BOTTOMLEFT", 0, 0)
        indicator:SetPoint("BOTTOMRIGHT", 0, 0)
        indicator:SetColorTexture(0.2, 0.5, 1, 1)
        indicator:Hide()
        btn._indicator = indicator

        btn.tabID = tab.id
        btn:SetScript("OnClick", function()
            widget:SetActiveTab(tab.id)
        end)

        tabButtons[i] = btn
        contentFrames[tab.id] = tab.content
    end

    widget.tabButtons = tabButtons
    widget.contentFrames = contentFrames

    --- Set the active tab
    ---@param tabID string
    function widget:SetActiveTab(tabID)
        self.activeTab = tabID

        -- Update button visuals
        for _, btn in ipairs(tabButtons) do
            if btn.tabID == tabID then
                btn._bg:SetColorTexture(0.15, 0.25, 0.4, 0.95)
                btn._text:SetTextColor(1, 1, 1)
                btn._indicator:Show()
            else
                btn._bg:SetColorTexture(0.08, 0.08, 0.12, 0.7)
                btn._text:SetTextColor(0.55, 0.55, 0.55)
                btn._indicator:Hide()
            end
        end

        -- Show/hide content frames
        for id, frame in pairs(contentFrames) do
            if id == tabID then
                frame:Show()
            else
                frame:Hide()
            end
        end

        -- Save last tab (protected — DB might not be ready)
        pcall(GF.Settings.SetChar, GF.Settings, "ui.lastTab", tabID)

        if onChange then
            onChange(tabID)
        end
    end

    --- Get a tab button by ID (for hiding specific tabs)
    ---@param tabID string
    ---@return Frame|nil
    function widget:GetTabButton(tabID)
        for _, btn in ipairs(tabButtons) do
            if btn.tabID == tabID then
                return btn
            end
        end
        return nil
    end

    return widget
end
