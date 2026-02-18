-------------------------------------------------------------------------------
-- MidnightBattleText - Minimap Button
-- Custom minimap icon (no external libraries)
-- Copyright (c) 2026 Shea (iTek). All Rights Reserved.
-------------------------------------------------------------------------------

local ADDON_NAME, MBT = ...

-------------------------------------------------------------------------------
-- Minimap button
-------------------------------------------------------------------------------

local ICON_TEXTURE = "Interface\\Icons\\spell_holy_surgeoflight"
local BUTTON_SIZE  = 33
local DEFAULT_ANGLE = 220  -- degrees, starting position on minimap

local minimapButton

local function GetMinimapButtonPosition(angle)
    local rad = math.rad(angle)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    return x, y
end

local function UpdatePosition(button, angle)
    local x, y = GetMinimapButtonPosition(angle)
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MBT:CreateMinimapButton()
    if minimapButton then return end

    local btn = CreateFrame("Button", "MBTMinimapButton", Minimap)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Background circle
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(BUTTON_SIZE + 1, BUTTON_SIZE + 1)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Icon texture
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ICON_TEXTURE)
    btn.icon = icon

    -- Overlay highlight
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetPoint("CENTER", 0, 1)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    -- Position from saved angle
    local angle = MBT.db.minimapAngle or DEFAULT_ANGLE
    UpdatePosition(btn, angle)

    -- Drag to reposition around minimap
    local isDragging = false
    btn:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local newAngle = math.deg(math.atan2(cy - my, cx - mx))
            MBT.db.minimapAngle = newAngle
            UpdatePosition(self, newAngle)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    -- Click: left = toggle editor, right = toggle addon
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            MBT:ToggleEditor()
        elseif button == "RightButton" then
            MBT.db.enabled = not MBT.db.enabled
            local state = MBT.db.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
            print("|cff00ccffMBT|r: Addon " .. state)
        end
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00ccffMidnightBattleText|r")
        GameTooltip:AddLine("|cffffffffLeft-click|r to open settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffRight-click|r to toggle on/off", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffDrag|r to move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapButton = btn
    MBT.minimapButton = btn
end

function MBT:SetMinimapButtonShown(show)
    if minimapButton then
        if show then
            minimapButton:Show()
        else
            minimapButton:Hide()
        end
    end
end
