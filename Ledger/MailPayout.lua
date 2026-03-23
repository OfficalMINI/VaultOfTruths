------------------------------------------------------------------------
-- Vault of Truths - Ledger/MailPayout.lua
-- One-click-per-person mail payout queue
-- Pre-fills recipient + gold, officer clicks Send for each
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.MailPayout = {}
local MP = GF.MailPayout
GF:RegisterModule("MailPayout", MP)

local payoutQueue = {}
local currentIndex = 0
local totalQueued = 0
local totalSent = 0
local totalGoldSent = 0
local isActive = false

local payoutFrame = nil

function MP:Init()
    -- Use raw frame for mail events (Midnight-safe)
    local mailEventFrame = CreateFrame("Frame")
    mailEventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
    mailEventFrame:RegisterEvent("MAIL_FAILED")
    mailEventFrame:RegisterEvent("MAIL_CLOSED")
    mailEventFrame:RegisterEvent("MAIL_SHOW")
    mailEventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    mailEventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    mailEventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "MAIL_SEND_SUCCESS" then
            if isActive then MP:OnMailSent() end
        elseif event == "MAIL_FAILED" then
            if isActive then
                GF.ChatNotify:Error("Mail failed! Check recipient name and retry.")
            end
        elseif event == "MAIL_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg1 == 17) then
            MP:ShowPayoutButton()
        elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and arg1 == 17) then
            if isActive then MP:Cancel() end
            MP:HidePayoutButton()
        end
    end)
end

--- Create and show the payout button when mailbox opens
function MP:ShowPayoutButton()
    if not GF.Roles:IsAddonOfficer() then return end

    local queue = GF.Payouts:GetPayoutQueue()
    if #queue == 0 then return end

    if not payoutFrame then
        payoutFrame = GF.UI.Theme:Card(UIParent)
        payoutFrame:SetSize(220, 120)
        payoutFrame:SetPoint("TOPLEFT", UIParent, "CENTER", 280, 50)
        payoutFrame:SetBackdropColor(0.04, 0.06, 0.1, 0.96)
        payoutFrame:SetBackdropBorderColor(0.2, 0.5, 0.8, 0.9)
        payoutFrame:SetFrameStrata("DIALOG")
        payoutFrame:SetMovable(true)
        payoutFrame:EnableMouse(true)

        local titleBar = CreateFrame("Frame", nil, payoutFrame)
        titleBar:SetHeight(20)
        titleBar:SetPoint("TOPLEFT", 0, 0)
        titleBar:SetPoint("TOPRIGHT", 0, 0)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() payoutFrame:StartMoving() end)
        titleBar:SetScript("OnDragStop", function() payoutFrame:StopMovingOrSizing() end)

        local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", 8, 0)
        title:SetText("|cFF33AAFFPayouts|r")

        payoutFrame._info = payoutFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        payoutFrame._info:SetPoint("TOPLEFT", 8, -22)
        payoutFrame._info:SetPoint("RIGHT", -8, 0)
        payoutFrame._info:SetJustifyH("LEFT")
        payoutFrame._info:SetWordWrap(true)

        -- Send button
        payoutFrame._sendBtn = GF.UI.Theme:ActionButton(payoutFrame, "Send Payout", 90, 26)
        payoutFrame._sendBtn:SetPoint("BOTTOMLEFT", 8, 8)

        -- Skip button
        payoutFrame._skipBtn = GF.UI.Theme:Button(payoutFrame, "Skip", 60, 26)
        payoutFrame._skipBtn:SetPoint("LEFT", payoutFrame._sendBtn, "RIGHT", 4, 0)

        -- Close
        local closeBtn = CreateFrame("Button", nil, payoutFrame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -1, -1)
        closeBtn:SetSize(20, 20)
    end

    -- Update info
    if not isActive then
        payoutFrame._info:SetText("|cFFFFAA00" .. #queue .. " members|r awaiting payout\nTotal: " .. GF.Utils:FormatMoney(GF.Payouts:GetTotalLiability()) .. "\n\nClick Send to start.")
        payoutFrame._sendBtn:SetText("Start Payouts")
        payoutFrame._sendBtn:SetScript("OnClick", function()
            local ok, err = MP:Start()
            if ok then
                MP:UpdatePayoutFrame()
            else
                GF.ChatNotify:Error(err or "Failed")
            end
        end)
        payoutFrame._skipBtn:Hide()
    else
        MP:UpdatePayoutFrame()
    end

    payoutFrame:Show()
end

--- Update the payout frame with current recipient info
function MP:UpdatePayoutFrame()
    if not payoutFrame or not payoutFrame:IsShown() then return end

    local payout = self._currentPayout
    if not payout then
        payoutFrame._info:SetText("|cFF00FF00All payouts complete!|r")
        payoutFrame._sendBtn:Hide()
        payoutFrame._skipBtn:Hide()
        return
    end

    payoutFrame._info:SetText(
        "|cFFFFFF00[" .. payout.index .. "/" .. payout.total .. "]|r " ..
        payout.mailTarget .. "\n" ..
        "|cFFFFD700" .. GF.Utils:FormatMoney(payout.amount) .. "|r" ..
        " (" .. string.format("%.1f%%", payout.share) .. " share)")

    payoutFrame._sendBtn:SetText("Send Payout")
    payoutFrame._sendBtn:SetScript("OnClick", function()
        MP:SendCurrent()
    end)

    payoutFrame._skipBtn:Show()
    payoutFrame._skipBtn:SetScript("OnClick", function()
        MP:SkipCurrent()
        MP:UpdatePayoutFrame()
    end)
end

function MP:HidePayoutButton()
    if payoutFrame then payoutFrame:Hide() end
end

--- Start a payout session from the payout queue
---@return boolean success
---@return string|nil error
function MP:Start()
    if not GF.Roles:IsAddonOfficer() then
        return false, "Only officers can send payouts"
    end

    if not MailFrame or not MailFrame:IsShown() then
        return false, "Mailbox must be open to send payouts"
    end

    -- Build queue from current payout data
    local queue = GF.Payouts:GetPayoutQueue()
    if #queue == 0 then
        return false, "No pending payouts"
    end

    payoutQueue = queue
    currentIndex = 1
    totalQueued = #queue
    totalSent = 0
    totalGoldSent = 0
    isActive = true

    print("|cFF33AAFF[Vault of Truths]|r Payout session started — " .. totalQueued .. " recipients")
    print("|cFF33AAFF[Vault of Truths]|r Click 'Send Payout' for each recipient. One click per mail.")

    -- Pre-fill the first recipient
    self:PrepareNext()
    return true
end

--- Pre-fill the mail UI with the next recipient and gold amount
function MP:PrepareNext()
    if currentIndex > totalQueued then
        self:Complete()
        return
    end

    local entry = payoutQueue[currentIndex]
    if not entry then
        self:Complete()
        return
    end

    -- Convert copper to gold/silver/copper for the mail API
    local copper = entry.balance

    -- Pre-fill the send mail fields
    -- Player needs to have the mailbox open
    local playerName = entry.player
    -- Strip realm if same realm (mail doesn't need it for same-realm)
    local name, realm = playerName:match("^(.+)-(.+)$")
    local myRealm = GetNormalizedRealmName()
    local mailTarget = (realm == myRealm) and name or playerName

    -- Set the mail fields
    -- The actual SendMail call happens when the officer clicks the button
    -- We just prepare the data for the UI to display

    self._currentPayout = {
        player = entry.player,
        mailTarget = mailTarget,
        amount = copper,
        share = entry.share,
        roles = entry.roles,
        index = currentIndex,
        total = totalQueued,
    }

    GF.Events:Fire("GF_PAYOUT_READY", self._currentPayout)

    print(string.format("|cFF33AAFF[Vault of Truths]|r [%d/%d] Ready: %s — %s (%.1f%% share)",
        currentIndex, totalQueued, mailTarget, GF.Utils:FormatMoney(copper), entry.share))

    MP:UpdatePayoutFrame()
end

--- Send the current payout mail (called from UI button click)
---@return boolean success
function MP:SendCurrent()
    if not MailFrame or not MailFrame:IsShown() then
        GF.ChatNotify:Warning("Mailbox must be open to send payouts.")
        return false
    end

    local payout = self._currentPayout
    if not payout then
        print("|cFFFF0000[Vault of Truths]|r No payout prepared.")
        return false
    end

    -- Set the gold amount on the mail
    SetSendMailMoney(payout.amount)

    -- Send the mail with a Vault of Truths subject line
    local subject = "Vault of Truths Payout — " .. GF.Utils:FormatMoney(payout.amount)
    local body = string.format(
        "Vault of Truths Payout\nShare: %.1f%%\nPeriod: %s\n\nThank you for your contributions!",
        payout.share, GF.Utils:FormatDate(GF.Utils:GetTime())
    )

    SendMail(payout.mailTarget, subject, body)
    return true
end

--- Called when a mail is successfully sent
function MP:OnMailSent()
    local payout = self._currentPayout
    if not payout then return end

    -- Record the payout in the ledger
    local officerName = GF.Utils:GetPlayerFullName()
    GF.Payouts:RecordPayout(payout.player, payout.amount, "mail", officerName)

    totalSent = totalSent + 1
    totalGoldSent = totalGoldSent + payout.amount

    print(string.format("|cFF00FF00[Vault of Truths]|r Sent! %s — %s (%d/%d done, %s total sent)",
        payout.mailTarget, GF.Utils:FormatMoney(payout.amount),
        totalSent, totalQueued, GF.Utils:FormatMoney(totalGoldSent)))

    -- Advance to next
    currentIndex = currentIndex + 1
    self:PrepareNext()
    self:UpdatePayoutFrame()
end

--- Skip the current recipient
function MP:SkipCurrent()
    if not isActive then return end

    local payout = self._currentPayout
    if payout then
        print("|cFFFFAA00[Vault of Truths]|r Skipped: " .. payout.mailTarget)
    end

    currentIndex = currentIndex + 1
    self:PrepareNext()
end

--- Complete the payout session
function MP:Complete()
    isActive = false
    self._currentPayout = nil

    print("|cFF00FF00[Vault of Truths]|r Payout session complete!")
    print(string.format("  Sent: %d/%d | Total gold: %s",
        totalSent, totalQueued, GF.Utils:FormatMoney(totalGoldSent)))

    GF.Events:Fire("GF_PAYOUT_SESSION_COMPLETE", totalSent, totalGoldSent)
end

--- Cancel the payout session
function MP:Cancel()
    if not isActive then return end
    isActive = false
    self._currentPayout = nil

    print("|cFFFFAA00[Vault of Truths]|r Payout session cancelled.")
    print(string.format("  Sent before cancel: %d/%d | Gold sent: %s",
        totalSent, totalQueued, GF.Utils:FormatMoney(totalGoldSent)))
end

--- Get current session status
---@return table|nil { current, total, sent, goldSent, isActive, currentPayout }
function MP:GetStatus()
    if not isActive then return nil end
    return {
        current = currentIndex,
        total = totalQueued,
        sent = totalSent,
        goldSent = totalGoldSent,
        isActive = isActive,
        currentPayout = self._currentPayout,
    }
end

--- Check if a payout session is active
---@return boolean
function MP:IsActive()
    return isActive
end
