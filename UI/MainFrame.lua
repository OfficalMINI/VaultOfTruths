------------------------------------------------------------------------
-- Vault of Truths - UI/MainFrame.lua
-- Top-level container frame with tab navigation
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.MainFrame = {}
local MF = GF.UI.MainFrame

local mainFrame = nil
local tabGroup = nil

--- Create the main frame (called on first open)
local function CreateMainFrame()
    if mainFrame then return end

    -- Main container
    mainFrame = CreateFrame("Frame", "VaultOfTruthsMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(900, 620)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    mainFrame:SetBackdropColor(0.05, 0.06, 0.09, 0.97)
    mainFrame:SetBackdropBorderColor(0.15, 0.25, 0.4, 0.8)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)

    -- Minimum size
    if mainFrame.SetResizeBounds then
        mainFrame:SetResizeBounds(780, 550, 1400, 1000)
    end

    -- Restore saved size
    local savedW = GF.Settings:GetChar("ui.mainFrameWidth")
    local savedH = GF.Settings:GetChar("ui.mainFrameHeight")
    if savedW and savedH and savedW > 0 and savedH > 0 then
        mainFrame:SetSize(savedW, savedH)
    end

    -- Resize handle (bottom-right corner)
    local resizer = CreateFrame("Button", nil, mainFrame)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT", 0, 0)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function()
        mainFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizer:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        -- Save new size
        GF.Settings:SetChar("ui.mainFrameWidth", math.floor(mainFrame:GetWidth()))
        GF.Settings:SetChar("ui.mainFrameHeight", math.floor(mainFrame:GetHeight()))
    end)

    -- Title bar (drag region)
    local titleBar = CreateFrame("Frame", nil, mainFrame)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        MF:SavePosition()
    end)

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 12, 0)
    titleText:SetText("|cFF33AAFFVault of Truths|r")

    -- Version + context text
    local versionText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("LEFT", titleText, "RIGHT", 8, 0)
    -- Determined at Show() time based on guild status
    mainFrame._versionText = versionText
    versionText:SetText("|cFF888888v" .. GF.VERSION .. "|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- Tab content area
    local contentArea = CreateFrame("Frame", nil, mainFrame)
    contentArea:SetPoint("TOPLEFT", 8, -64)
    contentArea:SetPoint("BOTTOMRIGHT", -8, 32)

    -- Status bar
    local statusBar = CreateFrame("Frame", nil, mainFrame)
    statusBar:SetHeight(24)
    statusBar:SetPoint("BOTTOMLEFT", 8, 4)
    statusBar:SetPoint("BOTTOMRIGHT", -8, 4)

    local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT")
    statusText:SetTextColor(0.5, 0.5, 0.5)
    mainFrame._statusText = statusText

    mainFrame._joinGuildBtn = nil -- removed

    -- Create content frames for each tab
    local dashboardContent = CreateFrame("Frame", nil, contentArea)
    dashboardContent:SetAllPoints()

    local ledgerContent = CreateFrame("Frame", nil, contentArea)
    ledgerContent:SetAllPoints()

    local craftingContent = CreateFrame("Frame", nil, contentArea)
    craftingContent:SetAllPoints()

    local ahContent = CreateFrame("Frame", nil, contentArea)
    ahContent:SetAllPoints()

    local officerContent = CreateFrame("Frame", nil, contentArea)
    officerContent:SetAllPoints()

    local settingsContent = CreateFrame("Frame", nil, contentArea)
    settingsContent:SetAllPoints()

    -- Store references for sub-panels to use
    mainFrame._contentFrames = {
        dashboard = dashboardContent,
        ledger = ledgerContent,
        crafting = craftingContent,
        ah = ahContent,
        officer = officerContent,
        settings = settingsContent,
    }

    -- Build tabs based on access level:
    -- Guild member: full UI
    -- Community member: crafting tab
    -- Neither: join CTA
    local isVoT = GF.Utils:IsInVoTGuild()
    local isInCommunity = GF.CommunityBridge and GF.CommunityBridge:IsInCommunity()
    local tabs
    if isVoT then
        tabs = {
            { id = "dashboard", label = "Dashboard", content = dashboardContent },
            { id = "ledger", label = "Ledger", content = ledgerContent },
            { id = "crafting", label = "Crafting", content = craftingContent },
            { id = "ah", label = "AH", content = ahContent },
            { id = "officer", label = "Officer", content = officerContent },
            { id = "settings", label = "Settings", content = settingsContent },
        }
    elseif isInCommunity then
        tabs = {
            { id = "crafting", label = "Crafting", content = craftingContent },
        }
    else
        -- Build a join CTA panel for non-guildies
        local joinContent = CreateFrame("Frame", nil, contentArea)
        joinContent:SetAllPoints()

        -- Large centered card
        local T = GF.UI.Theme
        local ctaCard = T:Card(joinContent)
        ctaCard:SetSize(440, 430)
        ctaCard:SetPoint("CENTER", joinContent, "CENTER", 0, 10)

        -- Icon
        local ctaIcon = ctaCard:CreateTexture(nil, "ARTWORK")
        ctaIcon:SetSize(64, 64)
        ctaIcon:SetPoint("TOP", 0, -20)
        ctaIcon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")

        -- Title
        local ctaTitle = ctaCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        ctaTitle:SetPoint("TOP", ctaIcon, "BOTTOM", 0, -10)
        ctaTitle:SetText("|cFFFFCC00Join Vault of Truths|r")

        -- Description
        local ctaDesc = ctaCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ctaDesc:SetPoint("TOP", ctaTitle, "BOTTOM", 0, -12)
        ctaDesc:SetPoint("LEFT", ctaCard, "LEFT", 30, 0)
        ctaDesc:SetPoint("RIGHT", ctaCard, "RIGHT", -30, 0)
        ctaDesc:SetJustifyH("CENTER")
        ctaDesc:SetWordWrap(true)
        ctaDesc:SetSpacing(3)
        ctaDesc:SetText(
            "Vault of Truths is a PVP guild economy.\n" ..
            "Deposit PVP loot, get profit shares when items sell.\n" ..
            "Crafters earn by turning mats into valuable goods.\n\n" ..
            "|cFFFFCC00Join the community to get started:|r\n" ..
            "|cFF00FF00+|r Browse guild crafters & request crafts\n" ..
            "|cFF00FF00+|r Get synced recipe data cross-realm\n" ..
            "|cFF00FF00+|r Submit crafting orders\n\n" ..
            "|cFFFFCC00Join the guild for full access:|r\n" ..
            "|cFF00FF00+|r Track contributions & earn profit shares\n" ..
            "|cFF00FF00+|r Rank up: Combatant > Gladiator > Warlord\n" ..
            "|cFF888888Guild invite links are shared in the community.|r"
        )
        ctaDesc:SetTextColor(0.8, 0.8, 0.8)

        -- Buttons anchored from bottom of card, going upward
        -- Paste Search button (bottom)
        local pasteBtn = T:Button(ctaCard, "Paste Search", 260, 28)
        pasteBtn:SetPoint("BOTTOM", ctaCard, "BOTTOM", 0, 16)
        pasteBtn:SetScript("OnClick", function()
            pcall(function()
                if not CommunitiesFrame or not CommunitiesFrame:IsShown() then
                    GF.ChatNotify:Warning("Open Communities first (J), then click Paste Search.")
                    return
                end

                local searchBox = nil
                local function FindSearchBox(frame, depth)
                    if depth > 5 or searchBox then return end
                    for _, child in ipairs({ frame:GetChildren() }) do
                        local name = child:GetName() or ""
                        if child:IsObjectType("EditBox") and (
                            name:find("Search") or name:find("search") or
                            name:find("Filter") or name:find("Input")
                        ) then
                            searchBox = child
                            return
                        end
                        if child.SearchBox then searchBox = child.SearchBox; return end
                        if child.searchBox then searchBox = child.searchBox; return end
                        FindSearchBox(child, depth + 1)
                    end
                end
                FindSearchBox(CommunitiesFrame, 0)

                if searchBox then
                    searchBox:SetText("Vault of Truths")
                    searchBox:SetFocus()
                    GF.ChatNotify:Success("'Vault of Truths' pasted — press Enter to search!")
                else
                    ChatFrame_OpenChat("Vault of Truths")
                    GF.ChatNotify:Info("Type |cFFFFCC00Vault of Truths|r in the search field.")
                end
            end)
        end)

        -- Find Community button (above paste)
        local ctaBtn = T:ActionButton(ctaCard, "Find Community", 260, 32)
        ctaBtn:SetPoint("BOTTOM", pasteBtn, "TOP", 0, 6)
        ctaBtn:SetScript("OnClick", function()
            if ToggleGuildFrame then
                ToggleGuildFrame()
            elseif Communities_LoadUI then
                Communities_LoadUI()
                CommunitiesFrame:Show()
            end
            GF.ChatNotify:Info("Switch to |cFFFFCC00Communities|r tab, then click |cFFFFCC00Paste Search|r.")
        end)

        -- Hint
        local ctaHint = ctaCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ctaHint:SetPoint("BOTTOM", ctaCard, "BOTTOM", 0, 4)
        ctaHint:SetText("|cFF555555J > Communities tab > search 'Vault of Truths'|r")

        mainFrame._contentFrames.join = joinContent

        tabs = {
            { id = "join", label = "Join Guild", content = joinContent },
        }
    end
    mainFrame._isVoTGuild = isVoT

    -- Tab bar area
    local tabBar = CreateFrame("Frame", nil, mainFrame)
    tabBar:SetHeight(32)
    tabBar:SetPoint("TOPLEFT", 0, -32)
    tabBar:SetPoint("TOPRIGHT", 0, -32)

    tabGroup = GF.UI.Widgets:CreateTabGroup(tabBar, tabs, function(tabID)
        MF:OnTabChanged(tabID)
    end)

    -- ESC to close
    tinsert(UISpecialFrames, "VaultOfTruthsMainFrame")

    -- Restore position
    MF:RestorePosition()

    mainFrame:Hide()
end

--- Called when tab changes
function MF:OnTabChanged(tabID)
    if GF.debug then print("|cFF00FF00[VoT]|r Tab changed: " .. tostring(tabID)) end

    -- Update status bar (protected)
    pcall(function() self:UpdateStatus() end)

    -- Role-based tab visibility (protected)
    pcall(function()
        local permLevel = GF.Roles:GetPermissionLevel()
        local officerBtn = tabGroup:GetTabButton("officer")
        if officerBtn then
            if permLevel >= GF.PERMISSIONS.OFFICER then
                officerBtn:Show()
            else
                officerBtn:Hide()
            end
        end
    end)

    -- Initialize/refresh tab content
    local tabRefreshMap = {
        dashboard = GF.UI.Dashboard,
        ledger = GF.UI.LedgerBrowser,
        crafting = GF.UI.CraftingBoard,
        ah = GF.UI.AHPanel,
        officer = GF.UI.OfficerPanel,
        settings = GF.UI.SettingsPanel,
    }
    local panel = tabRefreshMap[tabID]
    if panel and panel.Refresh then
        local ok, err = pcall(panel.Refresh, panel)
        if not ok then
            -- Always show errors regardless of debug mode
            print("|cFFFF0000[Vault of Truths]|r Error in " .. tabID .. ": " .. tostring(err))
        end
    elseif GF.debug then
        print("|cFFFF0000[VoT]|r No panel for tab: " .. tostring(tabID))
    end
end

--- Update the status bar text
function MF:UpdateStatus()
    if not mainFrame or not mainFrame._statusText then return end

    local parts = {}

    local isVoT = GF.Utils:IsInVoTGuild()

    -- Update version text
    if mainFrame._versionText then
        if isVoT then
            mainFrame._versionText:SetText("|cFF888888v" .. GF.VERSION .. " — PVP Guild Economy|r")
        else
            mainFrame._versionText:SetText("|cFF888888v" .. GF.VERSION .. " — Crafting Orders|r")
        end
    end

    if isVoT then
        -- Guild name
        local guild = GetGuildInfo("player")
        if guild then parts[#parts + 1] = guild end

        -- TSM status
        if GF.TSM:IsAvailable() then
            parts[#parts + 1] = "TSM: |cFF00FF00OK|r"
        else
            parts[#parts + 1] = "TSM: |cFFFF0000N/A|r"
        end

        -- Sync peers
        local peers = GF.Receiver:GetPeerCount()
        parts[#parts + 1] = "Peers: " .. peers

        -- Last bank scan
        local guildData = GF.Settings:GetGuildData()
        if guildData and guildData.bankSnapshots.lastScan > 0 then
            parts[#parts + 1] = "Bank: " .. GF.Utils:FormatRelativeTime(guildData.bankSnapshots.lastScan)
        end
    else
        local inCommunity = GF.CommunityBridge and GF.CommunityBridge:IsInCommunity()
        if inCommunity then
            parts[#parts + 1] = "Community Member"
            local peerCount = GF.CommunityBridge:GetPeerCount("Vault of Truths")
            if peerCount > 0 then
                parts[#parts + 1] = "Peers: " .. peerCount
            end
        else
            parts[#parts + 1] = "Join community for access"
        end

        -- (join button removed)
    end

    -- (join button removed)

    mainFrame._statusText:SetText(table.concat(parts, " | "))
end

--- Save frame position to per-character settings
function MF:SavePosition()
    if not mainFrame then return end
    local point, _, relPoint, x, y = mainFrame:GetPoint()
    GF.Settings:SetChar("ui.mainFramePoint", { point, nil, relPoint, x, y })
end

--- Restore frame position
function MF:RestorePosition()
    if not mainFrame then return end
    local pos = GF.Settings:GetChar("ui.mainFramePoint")
    if pos and pos[1] then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos[1], UIParent, pos[3] or "CENTER", pos[4] or 0, pos[5] or 0)
    end
end

--- Show the main frame
function MF:Show()
    CreateMainFrame()
    mainFrame:Show()

    -- Default to last tab or dashboard (non-VoT members always get crafting)
    local lastTab
    if GF.Utils:IsInVoTGuild() then
        lastTab = GF.Settings:GetChar("ui.lastTab") or "dashboard"
    elseif GF.CommunityBridge and GF.CommunityBridge:IsInCommunity() then
        lastTab = "crafting"
    else
        lastTab = "join"
    end
    if tabGroup then
        tabGroup:SetActiveTab(lastTab)
    end

    self:UpdateStatus()
end

--- Hide the main frame
function MF:Hide()
    if mainFrame then mainFrame:Hide() end
end

--- Toggle the main frame
function MF:Toggle()
    CreateMainFrame()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:Show()
    end
end

--- Get the main frame (for other panels to reference)
---@return Frame|nil
function MF:GetFrame()
    return mainFrame
end

--- Get a specific content frame by tab ID
---@param tabID string
---@return Frame|nil
function MF:GetContentFrame(tabID)
    if mainFrame and mainFrame._contentFrames then
        return mainFrame._contentFrames[tabID]
    end
    return nil
end
