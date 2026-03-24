------------------------------------------------------------------------
-- Vault of Truths - UI/Widgets/ConfirmDialog.lua
-- Modal yes/no confirmation dialog
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
if not GF.UI.Widgets then GF.UI.Widgets = {} end

local dialog = nil
local DIALOG_WIDTH = 380
local MIN_HEIGHT = 140
local PADDING = 20

--- Show a confirmation dialog
---@param title string Dialog title
---@param message string Dialog message
---@param onConfirm function Called when user clicks Yes
---@param onCancel function|nil Called when user clicks No
function GF.UI.Widgets:ShowConfirmDialog(title, message, onConfirm, onCancel)
    local T = GF.UI.Theme

    if not dialog then
        dialog = T:Card(UIParent)
        dialog:SetWidth(DIALOG_WIDTH)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetBackdropColor(0.06, 0.07, 0.11, 0.98)
        dialog:SetBackdropBorderColor(0.2, 0.35, 0.55, 0.8)

        -- Title
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dialog.title:SetPoint("TOP", 0, -PADDING)
        dialog.title:SetTextColor(1, 0.8, 0)

        -- Message
        dialog.message = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.message:SetPoint("TOP", dialog.title, "BOTTOM", 0, -10)
        dialog.message:SetPoint("LEFT", PADDING, 0)
        dialog.message:SetPoint("RIGHT", -PADDING, 0)
        dialog.message:SetWordWrap(true)
        dialog.message:SetJustifyH("CENTER")

        -- Confirm button (accent) — elevated above dialog to receive clicks
        dialog.yesBtn = T:ActionButton(dialog, "Confirm", 120, 28)
        dialog.yesBtn:SetPoint("BOTTOMLEFT", 40, PADDING)
        dialog.yesBtn:SetFrameLevel(dialog:GetFrameLevel() + 10)

        -- Cancel button
        dialog.noBtn = T:Button(dialog, "Cancel", 120, 28)
        dialog.noBtn:SetPoint("BOTTOMRIGHT", -40, PADDING)
        dialog.noBtn:SetFrameLevel(dialog:GetFrameLevel() + 10)
    end

    dialog.title:SetText(title)
    dialog.message:SetText(message)

    -- Auto-size height based on message content
    local msgHeight = dialog.message:GetStringHeight() or 40
    local titleHeight = dialog.title:GetStringHeight() or 20
    local totalHeight = PADDING + titleHeight + 10 + msgHeight + 16 + 28 + PADDING
    dialog:SetHeight(math.max(MIN_HEIGHT, totalHeight))

    dialog.yesBtn:SetScript("OnClick", function()
        print("|cFF00FF00[VoT]|r Confirm clicked")
        dialog:Hide()
        if onConfirm then onConfirm() end
    end)

    dialog.noBtn:SetScript("OnClick", function()
        print("|cFFFFAA00[VoT]|r Cancel clicked")
        dialog:Hide()
        if onCancel then onCancel() end
    end)

    dialog:Show()
end
