------------------------------------------------------------------------
-- Vault of Truths - UI/Widgets/ConfirmDialog.lua
-- Modal yes/no confirmation dialog
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
if not GF.UI.Widgets then GF.UI.Widgets = {} end

local dialog = nil

--- Show a confirmation dialog
---@param title string Dialog title
---@param message string Dialog message
---@param onConfirm function Called when user clicks Yes
---@param onCancel function|nil Called when user clicks No
function GF.UI.Widgets:ShowConfirmDialog(title, message, onConfirm, onCancel)
    local T = GF.UI.Theme

    if not dialog then
        dialog = T:Card(UIParent)
        dialog:SetSize(340, 160)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetBackdropColor(0.06, 0.07, 0.11, 0.98)
        dialog:SetBackdropBorderColor(0.2, 0.35, 0.55, 0.8)

        -- Title
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dialog.title:SetPoint("TOP", 0, -14)

        -- Message
        dialog.message = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.message:SetPoint("TOP", dialog.title, "BOTTOM", 0, -12)
        dialog.message:SetPoint("LEFT", 20, 0)
        dialog.message:SetPoint("RIGHT", -20, 0)
        dialog.message:SetWordWrap(true)

        -- Yes button
        dialog.yesBtn = T:ActionButton(dialog, "Confirm", 100, 26)
        dialog.yesBtn:SetPoint("BOTTOMLEFT", 40, 16)

        -- No button
        dialog.noBtn = T:Button(dialog, "Cancel", 100, 26)
        dialog.noBtn:SetPoint("BOTTOMRIGHT", -40, 16)

        -- Make it close with Escape
        dialog:SetFrameRef("name", dialog)
        tinsert(UISpecialFrames, "VaultOfTruthsConfirmDialog")
    end

    dialog.title:SetText(title)
    dialog.message:SetText(message)

    dialog.yesBtn:SetScript("OnClick", function()
        dialog:Hide()
        if onConfirm then onConfirm() end
    end)

    dialog.noBtn:SetScript("OnClick", function()
        dialog:Hide()
        if onCancel then onCancel() end
    end)

    dialog:Show()
end
