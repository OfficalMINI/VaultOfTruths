------------------------------------------------------------------------
-- Vault of Truths - UI/OnboardingDialog.lua
-- Track selection dialog shown to new guild members on first install
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.OnboardingDialog = {}
local OD = GF.UI.OnboardingDialog
GF:RegisterModule("OnboardingDialog", OD)

local T = GF.UI.Theme
local dialog = nil

-- Card definitions for the two track choices
-- Note: Crafters are implicitly PVPers (same tier benefits) but progress via crafting
local TRACK_CARDS = {
    {
        track = "pvper",
        title = "PVP Contributor",
        icon  = "Interface\\Icons\\Achievement_BG_WinAB",
        color = "|cFF00FF00",
        desc  = "Deposit PVP loot, honor purchases, and BoE drops to the guild bank. Progress through Combatant, Gladiator, and Warlord ranks based on contribution value.",
    },
    {
        track = "crafter",
        title = "Guild Crafter",
        icon  = "Interface\\Icons\\Trade_Engineering",
        color = "|cFF00AAFF",
        desc  = "Take guild mats, craft profitable items, deposit back for AH sale. Progress through Apprentice, Artisan, and Grand Artisan. You also get full PVP benefits at your crafter tier.",
    },
}

------------------------------------------------------------------------
-- Build UI
------------------------------------------------------------------------
local function CreateDialog()
    if dialog then return end

    -- Main frame
    dialog = CreateFrame("Frame", "VaultOfTruthsOnboardingDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(420, 260)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    dialog:SetBackdropColor(0.05, 0.06, 0.09, 0.97)
    dialog:SetBackdropBorderColor(0.15, 0.25, 0.4, 0.8)
    dialog:EnableMouse(true)
    dialog:SetClampedToScreen(true)
    dialog:Hide()

    -- ESC to close
    tinsert(UISpecialFrames, "VaultOfTruthsOnboardingDialog")

    -- Title
    local guildName = GetGuildInfo("player") or "Your Guild"
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cFFFFCC00Welcome to " .. guildName .. "!|r")
    title:SetWidth(370)

    -- Subtitle
    local subtitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
    subtitle:SetText("Choose your path to start earning guild rewards.")
    subtitle:SetTextColor(0.85, 0.85, 0.85)

    -- Track cards
    local cardHeight = 52
    local cardSpacing = 6
    local startY = -72

    for i, info in ipairs(TRACK_CARDS) do
        local card = CreateFrame("Button", nil, dialog, "BackdropTemplate")
        card:SetHeight(cardHeight)
        card:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, startY - (i - 1) * (cardHeight + cardSpacing))
        card:SetPoint("RIGHT", dialog, "RIGHT", -16, 0)
        card:SetBackdrop(T.CARD_BACKDROP)
        card:SetBackdropColor(0.08, 0.09, 0.14, 0.9)
        card:SetBackdropBorderColor(0.15, 0.22, 0.35, 0.6)

        -- Hover highlight
        card:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.12, 0.16, 0.25, 0.95)
            self:SetBackdropBorderColor(0.3, 0.5, 0.8, 0.9)
        end)
        card:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.09, 0.14, 0.9)
            self:SetBackdropBorderColor(0.15, 0.22, 0.35, 0.6)
        end)

        -- Icon
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(32, 32)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexture(info.icon)

        -- Title
        local cardTitle = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cardTitle:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
        cardTitle:SetText((info.color or "|cFF33AAFF") .. info.title .. "|r")

        -- Description
        local desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", cardTitle, "BOTTOMLEFT", 0, -2)
        desc:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        desc:SetText(info.desc)
        desc:SetTextColor(0.7, 0.7, 0.7)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)

        -- Click handler
        card:SetScript("OnClick", function()
            local player = GF.Utils:GetPlayerFullName()
            GF.Roles:SelectTrack(player, info.track)
            OD:Hide()
        end)
    end

    -- "Later" link at bottom
    local later = CreateFrame("Button", nil, dialog)
    later:SetSize(60, 20)
    later:SetPoint("BOTTOM", 0, 10)

    local laterText = later:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    laterText:SetAllPoints()
    laterText:SetText("|cFF888888Later|r")

    later:SetScript("OnEnter", function()
        laterText:SetText("|cFFAAAAAALater|r")
    end)
    later:SetScript("OnLeave", function()
        laterText:SetText("|cFF888888Later|r")
    end)
    later:SetScript("OnClick", function()
        OD:Hide()
    end)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function OD:Show()
    CreateDialog()
    dialog:Show()
end

function OD:Hide()
    if dialog then
        dialog:Hide()
    end
end

------------------------------------------------------------------------
-- Init — auto-show for new guild members with no track selected
------------------------------------------------------------------------

function OD:Init()
    GF.Events:On("GF_PLAYER_LOGIN", function()
        if not IsInGuild() then return end

        local player = GF.Utils:GetPlayerFullName()
        if GF.Roles:GetPrimaryTrack(player) then return end

        -- Delay slightly so the UI settles and guild info is available
        C_Timer.After(3, function()
            -- Re-check in case track was set during the delay
            if not GF.Roles:GetPrimaryTrack(player) then
                OD:Show()
            end
        end)
    end)
end
