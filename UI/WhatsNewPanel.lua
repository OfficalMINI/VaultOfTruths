------------------------------------------------------------------------
-- Vault of Truths - UI/WhatsNewPanel.lua
-- In-game changelog / "What's New" panel
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.WhatsNew = {}
local WN = GF.UI.WhatsNew

local initialized = false

-- Changelog entries: newest first
-- Each entry: { version, date, changes = { "line1", "line2", ... } }
local CHANGELOG = {
    {
        version = "1.2.0",
        changes = {
            "Fix confirm dialog buttons not clicking",
            "Fix nil contributorEarnings crash on old payout records",
            "Fix value inflation from deposit-withdraw-redeposit cycles",
            "Add /vot redist to repair broken profit distributions",
            "Add in-game What's New tab",
            "Ledger footer shows deposits, withdrawals, and sales separately",
            "Crafter recipe snapshot exported on commit",
        },
    },
    {
        version = "1.1.4",
        changes = {
            "Fix withdrawal trail tracking to split across multiple depositors (FIFO)",
            "Stacked guild bank items now properly attribute to each depositor",
        },
    },
    {
        version = "1.1.3",
        changes = {
            "Fix Distribute button not responding to clicks",
            "Fix guild chat incorrectly showing 'craft' for raw PVP item sales",
            "Distribute button now force-marks as distributed if no deposits match",
            "Add crafter recipe export script (snapshots on commit)",
        },
    },
    {
        version = "1.1.2",
        changes = {
            "Include guild bank tab 5 (Finished Goods) in ledger tracking",
        },
    },
    {
        version = "1.1.1",
        changes = {
            "Fix withdrawals not tracked in ledger or notified",
            "Scanner now fires events and chat notifications for withdrawals",
        },
    },
    {
        version = "1.1.0",
        changes = {
            "Restyle all UI panels to custom theme — no default WoW chrome",
            "Fix crafting item search lag (was scanning 67k item IDs)",
            "Fix 'I Supply Mats' mode not showing fee confirmation",
            "Auto-size confirm dialog based on content",
            "Add CurseForge automatic packaging",
        },
    },
    {
        version = "1.0.6",
        changes = {
            "Add mat debt management UI to Officer Panel",
            "Fix misleading 'Pending' label on sold AH items",
            "Add per-sale Distribute button",
        },
    },
    {
        version = "1.0.5",
        changes = {
            "Fix trail misattribution (raw deposits showing as 'Crafted by X')",
            "Remove PVPER role gate from contributor earnings",
            "All depositors now get proportional contributor share",
        },
    },
    {
        version = "1.0.4",
        changes = {
            "Fix deposits not recording in ledger",
        },
    },
    {
        version = "1.0.0",
        changes = {
            "Initial release",
            "PVP guild economy management",
            "Contribution tracking, crafting orders, AH profit sharing",
        },
    },
}

local function Init()
    if initialized then return end

    local T = GF.UI.Theme
    local parent = GF.UI.MainFrame:GetContentFrame("whatsnew")
    if not parent then return end

    local PAD = 12

    -- Header
    local _, headerContainer = T:SectionHeader(
        parent,
        { "TOPLEFT", parent, "TOPLEFT", PAD, -PAD },
        "What's New",
        "Interface\\ICONS\\INV_Misc_Note_06"
    )
    headerContainer:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)

    -- Current version
    local versionText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("RIGHT", headerContainer, "RIGHT", 0, 0)
    versionText:SetText("|cFF888888Current: v" .. GF.VERSION .. "|r")
    parent._versionText = versionText

    -- Scroll list of changelog entries
    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", headerContainer, "BOTTOMLEFT", 0, -8)
    listFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAD, PAD)

    -- Build flat display data: version headers + change lines
    local function BuildDisplayData()
        local data = {}
        for _, entry in ipairs(CHANGELOG) do
            -- Version header
            data[#data + 1] = {
                type = "version",
                text = entry.version,
                isCurrent = entry.version == GF.VERSION or
                            ("v" .. entry.version) == GF.VERSION,
            }
            -- Change lines
            for _, change in ipairs(entry.changes) do
                data[#data + 1] = {
                    type = "change",
                    text = change,
                }
            end
        end
        return data
    end

    local list = GF.UI.Widgets:CreateScrollList(listFrame, 18,
        function(index, contentFrame)
            local row = CreateFrame("Frame", nil, contentFrame)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetPoint("RIGHT", -8, 0)
            row.text:SetJustifyH("LEFT")

            return row
        end,
        function(row, entry)
            if entry.type == "version" then
                local color = entry.isCurrent and "|cFF00FF00" or "|cFFFFCC00"
                local tag = entry.isCurrent and " |cFF00FF00(current)|r" or ""
                row.text:SetText(color .. "v" .. entry.text .. "|r" .. tag)
                row.text:SetFontObject("GameFontNormal")
            else
                row.text:SetText("|cFFBBBBBB  - " .. entry.text .. "|r")
                row.text:SetFontObject("GameFontNormalSmall")
            end
        end
    )
    parent._list = list
    parent._buildData = BuildDisplayData

    initialized = true
end

function WN:Refresh()
    Init()

    local parent = GF.UI.MainFrame:GetContentFrame("whatsnew")
    if not parent then return end

    if parent._versionText then
        parent._versionText:SetText("|cFF888888Current: v" .. GF.VERSION .. "|r")
    end

    if parent._list and parent._buildData then
        parent._list:SetData(parent._buildData())
    end
end
