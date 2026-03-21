------------------------------------------------------------------------
-- Vault of Truths - UI/SetupGuide.lua
-- Officer-facing setup checklist — reads live guild state and shows
-- what is configured correctly vs what needs manual setup.
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.SetupGuide = {}

local SG = GF.UI.SetupGuide
local T  -- resolved lazily so load order doesn't matter

------------------------------------------------------------------------
-- Expected guild configuration
------------------------------------------------------------------------
local EXPECTED_RANK_COUNT = 10

local EXPECTED_BANK_TAB_COUNT = 6
local EXPECTED_BANK_TAB_NAMES = {
    [1] = "Public Deposits",
    [2] = "PVP Supplies",
    [3] = "Crafting Mats T1",
    [4] = "Crafting Mats T2",
    [5] = "Finished Goods",
    [6] = "Officer Reserves",
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

--- Safe wrapper around WoW APIs that may not exist or may error.
local function safeCall(fn, ...)
    if not fn then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

--- Safe wrapper that returns multiple values.
local function safeCallMulti(fn, ...)
    if not fn then return end
    local results = { pcall(fn, ...) }
    if results[1] then
        table.remove(results, 1)
        return unpack(results)
    end
    return nil
end

------------------------------------------------------------------------
-- Check generation
------------------------------------------------------------------------

--- Build the full checklist by reading live guild state.
---@return table checks  Array of { passed = bool, label = string, hint = string|nil }
local function BuildChecks()
    local checks = {}

    local function add(passed, label, hint)
        checks[#checks + 1] = {
            passed = passed,
            label = label,
            hint = hint,
        }
    end

    local function addHeader(text)
        checks[#checks + 1] = {
            isHeader = true,
            label = text,
        }
    end

    -- ----------------------------------------------------------------
    -- RANK SETUP
    -- ----------------------------------------------------------------
    addHeader("Rank Setup")

    local numRanks = safeCall(GuildControlGetNumRanks) or 0

    add(numRanks == EXPECTED_RANK_COUNT,
        "Rank count: " .. numRanks .. " / " .. EXPECTED_RANK_COUNT,
        numRanks ~= EXPECTED_RANK_COUNT
            and "Open Guild > Roster > Ranks and add/remove ranks until you have exactly "
                .. EXPECTED_RANK_COUNT .. "."
            or nil)

    for i = 0, EXPECTED_RANK_COUNT - 1 do
        local expected = GF.RANK_NAMES[i]
        local actual = safeCall(GuildControlGetRankName, i + 1) -- API is 1-based
        local match = (actual == expected)
        local displayActual = actual or "<missing>"

        add(match,
            "Rank " .. i .. ": " .. (match and expected or (displayActual .. "  (expected: " .. expected .. ")")),
            (not match)
                and "Rename rank " .. (i + 1) .. ' to "' .. expected
                    .. '" via Guild > Roster > Ranks.'
                or nil)
    end

    -- ----------------------------------------------------------------
    -- BANK TAB SETUP
    -- ----------------------------------------------------------------
    addHeader("Bank Tab Setup")

    local numTabs = safeCall(GetNumGuildBankTabs) or 0

    add(numTabs >= EXPECTED_BANK_TAB_COUNT,
        "Bank tabs purchased: " .. numTabs .. " / " .. EXPECTED_BANK_TAB_COUNT .. "+",
        numTabs < EXPECTED_BANK_TAB_COUNT
            and "Purchase more guild bank tabs. Visit a guild vault NPC."
            or nil)

    for i = 1, EXPECTED_BANK_TAB_COUNT do
        local tabName, tabIcon = safeCallMulti(GetGuildBankTabInfo, i)
        local expected = EXPECTED_BANK_TAB_NAMES[i]
        local match = (tabName == expected)
        local displayActual = tabName or "<not purchased>"

        add(match,
            "Tab " .. i .. ": " .. (match and expected or (displayActual .. "  (expected: " .. expected .. ")")),
            (not match)
                and 'Rename bank tab ' .. i .. ' to "' .. expected
                    .. '" via the guild bank tab settings.'
                or nil)
    end

    -- ----------------------------------------------------------------
    -- MANUAL VERIFICATION REMINDERS
    -- ----------------------------------------------------------------
    addHeader("Manual Verification")

    add(false,
        "Bank tab withdrawal limits — Verify manually",
        "Withdrawal limits and tab permissions are protected and cannot "
            .. "be read by addons. Check each rank's per-tab withdrawal "
            .. "limits in Guild > Roster > Ranks.")

    add(false,
        "Bank tab view/deposit permissions — Verify manually",
        "Ensure each rank can view/deposit into the correct tabs. "
            .. "Officer Reserves should be officer-only.")

    return checks
end

------------------------------------------------------------------------
-- Frame creation and layout
------------------------------------------------------------------------

local frame -- reused across Show() calls

local function EnsureFrame()
    if frame then return end

    T = GF.UI.Theme

    frame = CreateFrame("Frame", "VaultOfTruthsSetupGuide", UIParent, "BackdropTemplate")
    frame:SetSize(500, 450)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    -- Backdrop — clean 1px border
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.06, 0.07, 0.11, 0.95)
    frame:SetBackdropBorderColor(0.15, 0.22, 0.35, 0.8)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFFFFCC00Vault of Truths|r |cFFAAAAAA\226\128\148|r |cFFDDDDDDGuild Setup Guide|r")

    -- Divider below title
    T:Divider(frame, -34)

    -- Scroll area
    local scrollContainer = CreateFrame("Frame", nil, frame)
    scrollContainer:SetPoint("TOPLEFT", 10, -42)
    scrollContainer:SetPoint("BOTTOMRIGHT", -10, 44)

    -- Row factory
    local function createRow(index, parent)
        local row = CreateFrame("Frame", nil, parent)
        row:EnableMouse(true)

        -- Status icon (checkmark / X)
        local icon = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        icon:SetPoint("LEFT", 6, 0)
        icon:SetWidth(16)
        row.icon = icon

        -- Label
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 24, 0)
        label:SetPoint("RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label

        return row
    end

    -- Row updater
    local function updateRow(row, data, index)
        if data.isHeader then
            row.icon:SetText("")
            row.label:SetFontObject("GameFontNormal")
            row.label:SetText("|cFFFFCC00" .. data.label .. "|r")
            -- Remove tooltip on headers
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
        else
            if data.passed then
                row.icon:SetText("|cFF00E640\226\156\147|r") -- green checkmark
            else
                row.icon:SetText("|cFFFF3333\226\156\151|r") -- red X
            end
            row.label:SetFontObject("GameFontHighlightSmall")
            row.label:SetText(data.label)

            -- Hint tooltip on failed checks
            if not data.passed and data.hint then
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("How to fix", 1, 0.8, 0)
                    GameTooltip:AddLine(data.hint, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
            end
        end

        -- Alternate row shading
        if not data.isHeader then
            T:StripeRow(row, index)
        end
    end

    -- Build scroll list widget
    local scrollList = GF.UI.Widgets:CreateScrollList(scrollContainer, 22, createRow, updateRow)
    frame.scrollList = scrollList

    -- Bottom bar divider
    T:Divider(frame, -406)

    -- Refresh button
    local refreshBtn = T:ActionButton(frame, "Refresh", 90, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", 12, 10)
    refreshBtn:SetScript("OnClick", function()
        SG:Refresh()
    end)

    -- Close button
    local closeBtn = T:ActionButton(frame, "Close", 70, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- ESC to close
    tinsert(UISpecialFrames, "VaultOfTruthsSetupGuide")
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

--- Refresh the checklist with current guild state.
function SG:Refresh()
    if not frame then return end
    local checks = BuildChecks()
    frame.scrollList:SetData(checks)
end

--- Show the setup guide dialog.
function SG:Show()
    EnsureFrame()
    self:Refresh()
    frame:Show()
end

--- Hide the setup guide dialog.
function SG:Hide()
    if frame then frame:Hide() end
end
