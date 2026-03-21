------------------------------------------------------------------------
-- Vault of Truths - UI/MinimapButton.lua
-- Minimap icon button (no LibDBIcon dependency)
-- Uses the standard minimap button pattern used by most WoW addons
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
GF.UI.MinimapButton = {}
local MB = GF.UI.MinimapButton

local button = nil

--- Create the minimap button
local function CreateButton()
    if button then return end

    button = CreateFrame("Button", "VaultOfTruthsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetClampedToScreen(true)

    -- Background circle
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", 0, 0)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Icon texture — masked to circle
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    if icon.SetMask then
        icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end
    button.icon = icon

    -- Border ring — anchor so the ring center aligns with button center
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", button, "CENTER", -18, 18)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Highlight
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(20, 20)
    highlight:SetPoint("CENTER", 0, 0)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    -- Click handler
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            GF.UI.MainFrame:Toggle()
        elseif btn == "RightButton" then
            if GF.SlashCommands then
                SlashCmdList["VAULTOFTRUTHS"]("status")
            end
        end
    end)

    -- Drag to reposition around minimap edge
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.atan2(cy - my, cx - mx)
            VaultOfTruthsCharDB.minimapAngle = angle
            MB:SetPosition(angle)
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cFF33AAFFVault of Truths|r v" .. GF.VERSION)
        GameTooltip:AddLine("Left-click: Open Vault of Truths", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Status", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Set initial position
    local angle = VaultOfTruthsCharDB and VaultOfTruthsCharDB.minimapAngle or 3.84 -- ~220 degrees
    MB:SetPosition(angle)
end

--- Position the button around the OUTSIDE edge of the minimap
---@param angle number Angle in radians
function MB:SetPosition(angle)
    if not button then return end

    -- Minimap is typically ~70px radius; we want the button center on the edge
    -- Use the minimap's actual half-width for accuracy
    local mWidth, mHeight = Minimap:GetSize()
    local radius = (mWidth / 2) + 5  -- Slightly outside the edge

    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

--- Show or hide the minimap button
function MB:UpdateVisibility()
    if not button then return end
    local hide = VaultOfTruthsDB and VaultOfTruthsDB.settings and VaultOfTruthsDB.settings.minimapIcon and VaultOfTruthsDB.settings.minimapIcon.hide
    if hide then
        button:Hide()
    else
        button:Show()
    end
end

--- Initialize (called after PLAYER_LOGIN)
function MB:Init()
    CreateButton()
    self:UpdateVisibility()
end

-- Hook into addon lifecycle
GF.Events:On("GF_PLAYER_LOGIN", function()
    MB:Init()
end)
