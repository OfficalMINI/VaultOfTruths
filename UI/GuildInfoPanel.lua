------------------------------------------------------------------------
-- Vault of Truths - UI/GuildInfoPanel.lua
-- Guild information page: how the economy works, ranks, profit splits
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.GuildInfoPanel = {}
local GIP = GF.UI.GuildInfoPanel

local T -- resolved lazily
local panel = nil

local function CreatePanel()
    if panel then return end

    T = GF.UI.Theme

    panel = CreateFrame("Frame", "VaultOfTruthsGuildInfo", UIParent, "BackdropTemplate")
    panel:SetSize(560, 620)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(0.05, 0.06, 0.09, 0.97)
    panel:SetBackdropBorderColor(0.15, 0.25, 0.4, 0.8)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:Hide()

    tinsert(UISpecialFrames, "VaultOfTruthsGuildInfo")

    -- Drag
    local titleBar = CreateFrame("Frame", nil, panel)
    titleBar:SetHeight(30)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() panel:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    -- Close
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -1, -1)
    closeBtn:SetSize(22, 22)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -8)
    title:SetText("|cFFFFCC00Vault of Truths|r")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
    subtitle:SetText("|cFF888888PVP Guild Economy|r")

    -- Scroll area
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -34)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(content)

    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(w)
    end)

    local y = 0
    local PAD = 12
    local LINE = 14

    -- Helper: section card
    local function Section(headerText, iconPath)
        local card = T:Card(content)
        card:SetPoint("TOPLEFT", 0, y)
        card:SetPoint("RIGHT", content, "RIGHT", 0, 0)

        if iconPath then
            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("TOPLEFT", PAD, -PAD)
            icon:SetTexture(iconPath)

            local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            header:SetText("|cFFFFCC00" .. headerText .. "|r")
        else
            local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", PAD, -PAD)
            header:SetText("|cFFFFCC00" .. headerText .. "|r")
        end

        return card
    end

    -- Helper: text line in a card
    local function TextLine(card, lineY, text, color)
        local fs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", PAD, lineY)
        fs:SetPoint("RIGHT", card, "RIGHT", -PAD, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetSpacing(2)
        if color then
            fs:SetTextColor(color[1], color[2], color[3])
        else
            fs:SetTextColor(0.8, 0.8, 0.8)
        end
        fs:SetText(text)
        return fs
    end

    -- ================================================================
    -- SECTION 1: How It Works
    -- ================================================================
    local card1 = Section("How It Works", "Interface\\Icons\\INV_Misc_Book_09")
    TextLine(card1, -PAD - 20,
        "Vault of Truths runs a shared guild economy where PVP earnings are pooled, "..
        "crafted into valuable items, sold on the Auction House, and profits split "..
        "back to everyone who contributed.\n\n"..
        "|cFFFFCC00The Flow:|r\n"..
        "|cFF00FF00 1.|r PVP & earn honor, loot, and BoE drops\n"..
        "|cFF00FF00 2.|r Deposit bankable items to the guild bank\n"..
        "|cFF00FF00 3.|r Crafters turn raw materials into finished goods\n"..
        "|cFF00FF00 4.|r Auctioneers list items on the AH\n"..
        "|cFF00FF00 5.|r When items sell, profits are split to all contributors\n"..
        "|cFF00FF00 6.|r Get paid via guild mail payouts")
    card1:SetHeight(190)
    y = y - 198

    -- ================================================================
    -- SECTION 2: Progression Tracks
    -- ================================================================
    local card2 = Section("Progression Tracks", "Interface\\Icons\\Achievement_PVP_P_15")

    local guildData = GF.Settings and GF.Settings:GetGuildData()
    local thresholds = guildData and guildData.guildSettings.trackThresholds or GF.DEFAULT_TRACK_THRESHOLDS

    local pvpMember = GF.Utils:FormatGold(thresholds.pvper.member)
    local pvpVeteran = GF.Utils:FormatGold(thresholds.pvper.veteran)
    local crafterMid = thresholds.crafter.crafter
    local crafterTop = thresholds.crafter.master

    TextLine(card2, -PAD - 20,
        "|cFF00FF00PVP Track|r — progress by depositing PVP items\n"..
        "  |cFF888888Combatant|r  — Starting rank. Deposit to guild bank.\n"..
        "  |cFF00FF00Gladiator|r  — " .. pvpMember .. " contributed. Better repairs & supplies.\n"..
        "  |cFFFFD700Warlord|r    — " .. pvpVeteran .. " contributed. Top-tier access.\n\n"..
        "|cFF00AAFFCrafter Track|r — progress by crafting OR contributing\n"..
        "  |cFF888888Apprentice|r — Starting rank. Access to basic mats.\n"..
        "  |cFF00AAFFArtisan|r    — " .. (crafterMid.crafts or 25) .. " crafts (or " .. pvpMember .. "). More mat access.\n"..
        "  |cFFFFD700Grand Artisan|r — " .. (crafterTop.crafts or 100) .. " crafts (or " .. pvpVeteran .. "). Full access.\n\n"..
        "|cFF888888Crafters also receive PVP benefits at their equivalent tier.|r")
    card2:SetHeight(210)
    y = y - 218

    -- ================================================================
    -- SECTION 3: Profit Split
    -- ================================================================
    local card3 = Section("Profit Split", "Interface\\Icons\\INV_Misc_Coin_17")

    local split = guildData and guildData.guildSettings.profitSplit or GF.DEFAULT_PROFIT_SPLIT
    local commission = guildData and guildData.guildSettings.craftCommission or GF.DEFAULT_CRAFT_COMMISSION

    TextLine(card3, -PAD - 20,
        "When an item sells on the AH, the profit is split:\n\n"..
        "  |cFF00FF00Contributors:|r  " .. split.contributors .. "%  — PVPers who deposited materials\n"..
        "  |cFF00AAFFCrafters:|r      " .. split.crafters .. "%  — Whoever crafted the item\n"..
        "  |cFFFFAA00Auctioneers:|r   " .. split.auctioneers .. "%  — The AH account that sold it\n"..
        "  |cFF888888Guild Tax:|r     " .. split.guildTax .. "%  — Stays in guild bank for reinvestment\n\n"..
        "|cFFFFCC00Craft Commission:|r " .. GF.Utils:FormatMoney(commission) .. "\n"..
        "|cFF888888Charged when guild supplies mats. Profit from commission\ngoes back to the material contributors.|r")
    card3:SetHeight(180)
    y = y - 188

    -- ================================================================
    -- SECTION 4: Guild Bank Tabs
    -- ================================================================
    local card4 = Section("Guild Bank Layout", "Interface\\Icons\\INV_Misc_Bag_10_Green")
    TextLine(card4, -PAD - 20,
        "|cFFFFCC00Tab 1 — Public Deposits|r\n"..
        "  Everyone deposits here. This is where your contributions are tracked.\n\n"..
        "|cFFFFCC00Tab 2 — PVP Supplies|r\n"..
        "  Consumables, gems, enchants. Withdraw limit based on your rank.\n\n"..
        "|cFFFFCC00Tab 3 — Crafting Mats T1|r\n"..
        "  Basic materials. Crafters withdraw to make items. Tracked as debt.\n\n"..
        "|cFFFFCC00Tab 4 — Crafting Mats T2|r\n"..
        "  Expensive materials. Higher-rank crafters only.\n\n"..
        "|cFFFFCC00Tab 5 — Finished Goods|r\n"..
        "  Crafted items waiting for AH listing. Auctioneers pick up from here.\n\n"..
        "|cFFFFCC00Tab 6 — Officer Reserves|r\n"..
        "  Officer-only storage.")
    card4:SetHeight(240)
    y = y - 248

    -- ================================================================
    -- SECTION 5: Getting Started
    -- ================================================================
    local card5 = Section("Getting Started", "Interface\\Icons\\Spell_Holy_BlessingOfProtection")
    TextLine(card5, -PAD - 20,
        "|cFF00FF001.|r Choose your track — PVP Contributor or Crafter\n"..
        "|cFF00FF002.|r Start depositing PVP items or crafting for the guild\n"..
        "|cFF00FF003.|r Watch your progression in the Dashboard\n"..
        "|cFF00FF004.|r Earn profit shares when items sell on the AH\n"..
        "|cFF00FF005.|r Get paid via mail payouts from officers\n\n"..
        "|cFFFFCC00Commands:|r\n"..
        "  |cFFFFFF00/vot|r — Open the main panel\n"..
        "  |cFFFFFF00/vot progress|r — View your rank progression\n"..
        "  |cFFFFFF00/vot balance|r — Check your earnings balance\n"..
        "  |cFFFFFF00/vot status|r — Addon status & sync info\n\n"..
        "|cFFFFCC00Recommended:|r Install TradeSkillMaster (TSM) for accurate\n"..
        "item pricing. Without it, prices show as 'Not Synced' until\n"..
        "received from a guild member who has TSM.")
    card5:SetHeight(230)
    y = y - 238

    content:SetHeight(math.abs(y) + 10)
end

function GIP:Show()
    CreatePanel()
    panel:Show()
end

function GIP:Hide()
    if panel then panel:Hide() end
end

function GIP:Toggle()
    CreatePanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end
