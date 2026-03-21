------------------------------------------------------------------------
-- Vault of Truths - Notifications/Toast.lua
-- Floating toast notification frame (top-right, slides in, fades out)
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Toast = {}
local Toast = GF.Toast
GF:RegisterModule("Toast", Toast)

local toastQueue = {}
local isShowing = false
local TOAST_DURATION = 5 -- seconds visible
local FADE_DURATION = 1 -- seconds to fade out
local SLIDE_DURATION = 0.3

-- Toast frame (created on demand)
local toastFrame

function Toast:Init()
    -- Frame created on first use
end

--- Create the toast frame if it doesn't exist
local function EnsureFrame()
    if toastFrame then return end

    toastFrame = CreateFrame("Frame", "VaultOfTruthsToast", UIParent, "BackdropTemplate")
    toastFrame:SetSize(320, 72)
    toastFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -100)
    toastFrame:SetFrameStrata("DIALOG")
    toastFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    toastFrame:SetBackdropColor(0.1, 0.1, 0.15, 0.95)
    toastFrame:SetBackdropBorderColor(0.3, 0.5, 0.8, 1)

    -- Icon
    toastFrame.icon = toastFrame:CreateTexture(nil, "ARTWORK")
    toastFrame.icon:SetSize(36, 36)
    toastFrame.icon:SetPoint("LEFT", 10, 0)
    toastFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")

    -- Title
    toastFrame.title = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toastFrame.title:SetPoint("TOPLEFT", toastFrame.icon, "TOPRIGHT", 8, -2)
    toastFrame.title:SetPoint("RIGHT", toastFrame, "RIGHT", -10, 0)
    toastFrame.title:SetJustifyH("LEFT")
    toastFrame.title:SetTextColor(0.2, 0.67, 1)

    -- Body text
    toastFrame.body = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toastFrame.body:SetPoint("TOPLEFT", toastFrame.title, "BOTTOMLEFT", 0, -4)
    toastFrame.body:SetPoint("RIGHT", toastFrame, "RIGHT", -10, 0)
    toastFrame.body:SetJustifyH("LEFT")
    toastFrame.body:SetWordWrap(true)

    -- Fade animation group
    toastFrame.fadeAnim = toastFrame:CreateAnimationGroup()
    local fadeOut = toastFrame.fadeAnim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(FADE_DURATION)
    fadeOut:SetSmoothing("OUT")
    toastFrame.fadeAnim:SetScript("OnFinished", function()
        toastFrame:Hide()
        isShowing = false
        Toast:ShowNext()
    end)

    -- Slide-in animation
    toastFrame.slideAnim = toastFrame:CreateAnimationGroup()
    local slide = toastFrame.slideAnim:CreateAnimation("Translation")
    slide:SetOffset(-320, 0) -- Slides in from right
    slide:SetDuration(SLIDE_DURATION)
    slide:SetSmoothing("OUT")
    slide:SetOrder(1)

    -- Click to dismiss
    toastFrame:EnableMouse(true)
    toastFrame:SetScript("OnMouseDown", function()
        toastFrame.fadeAnim:Play()
    end)

    toastFrame:Hide()
end

--- Show a toast notification
---@param title string Title text
---@param body string Body text
---@param icon string|nil Texture path (defaults to Vault of Truths icon)
---@param sound string|nil Sound to play
function Toast:Show(title, body, icon, sound)
    -- Check if notifications are enabled
    if GF.Settings:GetChar("notifications.toastEnabled") == false then return end

    toastQueue[#toastQueue + 1] = {
        title = title,
        body = body,
        icon = icon,
        sound = sound,
    }

    if not isShowing then
        self:ShowNext()
    end
end

--- Show the next toast in the queue
function Toast:ShowNext()
    if #toastQueue == 0 then return end

    EnsureFrame()

    local data = table.remove(toastQueue, 1)
    isShowing = true

    toastFrame.title:SetText(data.title or "Vault of Truths")
    toastFrame.body:SetText(data.body or "")
    if data.icon then
        toastFrame.icon:SetTexture(data.icon)
    else
        toastFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    end

    -- Reset and show
    toastFrame:SetAlpha(1)
    toastFrame.fadeAnim:Stop()
    toastFrame:Show()

    -- Play slide-in
    toastFrame.slideAnim:Play()

    -- Play sound
    if data.sound and GF.Settings:GetChar("notifications.soundEnabled") ~= false then
        PlaySound(data.sound)
    end

    -- Schedule fade-out
    C_Timer.After(TOAST_DURATION, function()
        if isShowing and toastFrame:IsShown() then
            toastFrame.fadeAnim:Play()
        end
    end)
end

-- Convenience methods for common toast types

--- Toast for a bankable item being looted
---@param itemLink string
---@param value number|nil Copper value
function Toast:LootNotify(itemLink, value)
    local valueStr = value and GF.Utils:FormatMoney(value) or "N/A"
    self:Show(
        "Bankable Item!",
        itemLink .. "\nGuild value: " .. valueStr,
        nil,
        SOUNDKIT.UI_GARRISON_TOAST_MISSION_COMPLETE -- satisfying ding
    )
end

--- Toast for a deposit confirmation (shown once on bank close)
---@param itemCount number Total items deposited this session
---@param totalValue number Copper value of this session's deposits
---@param totalContributed number Copper lifetime contribution
function Toast:DepositConfirm(itemCount, totalValue, totalContributed)
    self:Show(
        "Deposited!",
        itemCount .. " item(s) — " .. GF.Utils:FormatMoney(totalValue) ..
        "\nTotal contribution: " .. GF.Utils:FormatMoney(totalContributed),
        "Interface\\Icons\\INV_Misc_Bag_10_Green",
        SOUNDKIT.LOOT_WINDOW_COIN_SOUND
    )
end

--- Toast for receiving a payout
---@param amount number Copper
---@param source string "mail" or "trade"
function Toast:PayoutReceived(amount, source)
    self:Show(
        "Payout Received!",
        GF.Utils:FormatMoney(amount) .. " via " .. source,
        "Interface\\Icons\\INV_Misc_Coin_17",
        SOUNDKIT.LOOT_WINDOW_COIN_SOUND
    )
end

--- Toast for tier promotion
---@param newTier string
function Toast:TierPromotion(newTier)
    self:Show(
        "Tier Promoted!",
        "You are now |cFFFFD700" .. newTier:upper() .. "|r tier!",
        "Interface\\Icons\\Achievement_Reputation_08",
        SOUNDKIT.UI_GARRISON_TOAST_BUILDING_COMPLETE
    )
end

--- Toast for crafting order status change
---@param orderID string
---@param status string
function Toast:OrderUpdate(orderID, status)
    self:Show(
        "Order Update",
        "Order #" .. orderID .. " — " .. status,
        "Interface\\Icons\\Trade_Engineering"
    )
end
