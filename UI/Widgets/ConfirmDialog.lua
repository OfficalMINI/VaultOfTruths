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
    if not dialog then
        dialog = CreateFrame("Frame", "VaultOfTruthsConfirmDialog", UIParent, "BackdropTemplate")
        dialog:SetSize(340, 160)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        dialog:SetBackdropColor(0.1, 0.1, 0.15, 0.95)
        dialog:SetBackdropBorderColor(0.6, 0.2, 0.2, 1)

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
        dialog.yesBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.yesBtn:SetSize(100, 26)
        dialog.yesBtn:SetPoint("BOTTOMLEFT", 40, 16)
        dialog.yesBtn:SetText("Confirm")

        -- No button
        dialog.noBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.noBtn:SetSize(100, 26)
        dialog.noBtn:SetPoint("BOTTOMRIGHT", -40, 16)
        dialog.noBtn:SetText("Cancel")

        -- Make it close with Escape
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
