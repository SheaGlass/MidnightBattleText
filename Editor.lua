-------------------------------------------------------------------------------
-- MidnightBattleText - Editor
-- Visual settings editor with interactive drag mode
-- All widgets are custom-built to avoid Blizzard secure template taint.
-- Copyright (c) 2026 Shea (iTek). All Rights Reserved.
-------------------------------------------------------------------------------

local ADDON_NAME, MBT = ...

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local PANEL_WIDTH  = 300
local PANEL_HEIGHT = 620
local INDENT       = 16
local SLIDER_WIDTH = 250
local ROW_HEIGHT   = 28
local SLIDER_ROW   = 44
local SECTION_GAP  = 12
local DROPDOWN_ROW = 50

local BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-------------------------------------------------------------------------------
-- Live preview (throttled)
-------------------------------------------------------------------------------

local lastTestTime = 0
local function FireTestText()
    if not MBT.db or not MBT.db.enabled then return end
    local now = GetTime()
    if now - lastTestTime < 0.4 then return end
    lastTestTime = now
    MBT:DisplayScrollText(12345, "damage", "incoming", nil, false)
    MBT:DisplayScrollText(54321, "damage", "outgoing", nil, true)
    MBT:DisplayScrollText(8765,  "heal",   "incoming", nil, false)
end

-------------------------------------------------------------------------------
-- Custom widget factories (no Blizzard secure templates)
-------------------------------------------------------------------------------

local function CreateSection(parent, y, title)
    local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    hdr:SetText("|cff00ccff" .. title .. "|r")

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    line:SetColorTexture(0, 0.6, 0.8, 0.4)

    return y - 22
end

-- Custom slider: raw Slider frame with manual thumb + labels
local function CreateSlider(parent, y, label, dbKey, minVal, maxVal, step)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(SLIDER_WIDTH, 36)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", INDENT + 4, y)

    -- Label + value text
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOP", container, "TOP", 0, 0)
    text:SetText(label .. ": " .. MBT.db[dbKey])

    -- Slider track
    local slider = CreateFrame("Slider", nil, container)
    slider:SetSize(SLIDER_WIDTH, 14)
    slider:SetPoint("TOP", text, "BOTTOM", 0, -2)
    slider:SetOrientation("HORIZONTAL")

    -- Track background
    local bg = slider:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    local border = slider:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    -- Thumb
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(16, 14)
    thumb:SetColorTexture(0.7, 0.7, 0.7, 0.8)
    slider:SetThumbTexture(thumb)

    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(MBT.db[dbKey])
    slider:EnableMouse(true)

    -- Min/Max labels
    local lowText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -1)
    lowText:SetText(minVal)

    local highText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -1)
    highText:SetText(maxVal)

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        MBT.db[dbKey] = value
        text:SetText(label .. ": " .. value)
        FireTestText()
    end)

    slider.dbKey = dbKey
    -- Expose SetValue on the container for external sync
    container.SetValue = function(_, val)
        slider:SetValue(val)
    end
    container.dbKey = dbKey
    return container, y - SLIDER_ROW
end

-- Custom checkbox: simple clickable frame with check mark texture
local function CreateCheckbox(parent, y, label, dbKey)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(SLIDER_WIDTH, 20)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", INDENT, y)
    frame:EnableMouse(true)

    -- Box background
    local box = frame:CreateTexture(nil, "BACKGROUND")
    box:SetSize(18, 18)
    box:SetPoint("LEFT", 0, 0)
    box:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    local boxBorder = frame:CreateTexture(nil, "BORDER")
    boxBorder:SetSize(20, 20)
    boxBorder:SetPoint("CENTER", box, "CENTER")
    boxBorder:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Check mark
    local check = frame:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("CENTER", box, "CENTER")
    check:SetColorTexture(0, 0.8, 1, 1)

    -- Label
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
    lbl:SetText(label)

    local function UpdateVisual()
        if MBT.db[dbKey] then
            check:Show()
        else
            check:Hide()
        end
    end
    UpdateVisual()

    frame:SetScript("OnMouseDown", function()
        MBT.db[dbKey] = not MBT.db[dbKey]
        UpdateVisual()
        FireTestText()
    end)

    frame:SetScript("OnEnter", function()
        boxBorder:SetColorTexture(0.6, 0.6, 0.6, 0.8)
    end)
    frame:SetScript("OnLeave", function()
        boxBorder:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    end)

    frame.dbKey = dbKey
    return frame, y - ROW_HEIGHT
end

-- Custom dropdown: button that opens a popup list (no UIDropDownMenu)
local function CreateDropdown(parent, y, label, items, getValue, setValue)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", INDENT, y)
    lbl:SetText(label)

    -- Dropdown button (custom, no UIPanelButtonTemplate)
    local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
    btn:SetSize(SLIDER_WIDTH, 22)
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    btn:EnableMouse(true)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnText:SetPoint("LEFT", 8, 0)
    btnText:SetPoint("RIGHT", -20, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetText(getValue())

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetText("v")

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0, 0.8, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    end)

    -- Popup list with scroll support for long lists
    local popup = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    popup:SetFrameStrata("TOOLTIP")
    popup:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    popup:SetBackdrop(BACKDROP)
    popup:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
    popup:Hide()
    popup.buttons = {}

    -- Scrollable content inside popup
    local popupScroll = CreateFrame("ScrollFrame", nil, popup)
    popupScroll:SetPoint("TOPLEFT", 4, -5)
    popupScroll:SetPoint("BOTTOMRIGHT", -4, 5)

    local popupContent = CreateFrame("Frame", nil, popupScroll)
    popupContent:SetWidth(SLIDER_WIDTH - 8)
    popupContent:SetHeight(1)
    popupScroll:SetScrollChild(popupContent)

    popupScroll:EnableMouseWheel(true)
    popupScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScrollVal = popupContent:GetHeight() - self:GetHeight()
        if maxScrollVal < 0 then maxScrollVal = 0 end
        local newScroll = current - (delta * 40)
        if newScroll < 0 then newScroll = 0 end
        if newScroll > maxScrollVal then newScroll = maxScrollVal end
        self:SetVerticalScroll(newScroll)
    end)

    local function BuildPopup()
        for _, b in ipairs(popup.buttons) do b:Hide() end

        local rowH = 20
        local maxVisible = math.min(#items, 20)
        popup:SetSize(SLIDER_WIDTH, maxVisible * rowH + 10)

        for i, item in ipairs(items) do
            local row = popup.buttons[i]
            if not row then
                row = CreateFrame("Frame", nil, popupContent)
                row:EnableMouse(true)

                -- Manual highlight (plain Frame has no SetHighlightTexture)
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.15)
                row.highlight = hl

                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.label:SetPoint("LEFT", 8, 0)
                row.label:SetPoint("RIGHT", -8, 0)
                row.label:SetJustifyH("LEFT")
                popup.buttons[i] = row
            end
            row:SetSize(SLIDER_WIDTH - 8, rowH)
            row:SetPoint("TOPLEFT", popupContent, "TOPLEFT", 0, -(rowH * (i - 1)))

            local displayName = type(item) == "table" and item.name or item
            local value = type(item) == "table" and item.value or item
            row.label:SetText(displayName)

            -- Font preview: render the label in the actual font
            if type(item) == "table" and item.path then
                row.label:SetFont(item.path, 12, "OUTLINE")
            else
                row.label:SetFontObject(GameFontNormalSmall)
            end

            row:SetScript("OnMouseDown", function()
                setValue(value, displayName)
                btnText:SetText(displayName)
                popup:Hide()
                FireTestText()
            end)
            row:Show()
        end

        -- Set content height for scrolling
        popupContent:SetHeight(#items * rowH)
    end

    btn:SetScript("OnMouseDown", function()
        if popup:IsShown() then
            popup:Hide()
        else
            BuildPopup()
            popup:Show()
        end
    end)

    btn.Refresh = function()
        btnText:SetText(getValue())
    end
    -- Expose SetText for visual mode sync
    btn.SetText = function(_, t)
        btnText:SetText(t)
    end

    return btn, y - DROPDOWN_ROW
end

-- Custom color swatch: small colored square that opens ColorPickerFrame on click
local function CreateColorSwatch(parent, y, label, dbKey)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(SLIDER_WIDTH, 22)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", INDENT, y)
    frame:EnableMouse(true)

    -- Color square
    local swatch = frame:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", 0, 0)

    local swatchBorder = frame:CreateTexture(nil, "BORDER")
    swatchBorder:SetSize(20, 20)
    swatchBorder:SetPoint("CENTER", swatch, "CENTER")
    swatchBorder:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Label
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    lbl:SetText(label)

    local function UpdateColor()
        local c = MBT.db[dbKey]
        if c then
            swatch:SetColorTexture(c[1], c[2], c[3], 1)
        end
    end
    UpdateColor()

    frame:SetScript("OnMouseDown", function()
        local c = MBT.db[dbKey] or {1, 1, 1}
        local info = {
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                MBT.db[dbKey] = {r, g, b}
                UpdateColor()
            end,
            cancelFunc = function(prev)
                MBT.db[dbKey] = {prev.r, prev.g, prev.b}
                UpdateColor()
            end,
            r = c[1], g = c[2], b = c[3],
            hasOpacity = false,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    frame:SetScript("OnEnter", function()
        swatchBorder:SetColorTexture(0.6, 0.6, 0.6, 0.8)
    end)
    frame:SetScript("OnLeave", function()
        swatchBorder:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    end)

    frame.dbKey = dbKey
    frame.UpdateColor = UpdateColor
    return frame, y - ROW_HEIGHT
end

-- Custom button (no UIPanelButtonTemplate)
local function CreateButton(parent, y, label, width, onClick)
    local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", INDENT, y)
    btn:SetSize(width, 24)
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    btn:EnableMouse(true)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    btn.label = text

    btn:SetScript("OnMouseDown", function()
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        if onClick then onClick() end
    end)
    btn:SetScript("OnMouseUp", function()
        btn:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0, 0.8, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    end)

    -- Expose SetText
    btn.SetText = function(_, t) text:SetText(t) end

    return btn, y - 30
end

-------------------------------------------------------------------------------
-- Custom scroll frame (no UIPanelScrollFrameTemplate)
-------------------------------------------------------------------------------

local function CreateScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 8, -36)
    scroll:SetPoint("BOTTOMRIGHT", -12, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(PANEL_WIDTH - 30)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    -- Mouse wheel scrolling
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = content:GetHeight() - self:GetHeight()
        if maxScroll < 0 then maxScroll = 0 end
        local newScroll = current - (delta * 30)
        if newScroll < 0 then newScroll = 0 end
        if newScroll > maxScroll then newScroll = maxScroll end
        self:SetVerticalScroll(newScroll)
    end)

    return scroll, content
end

-------------------------------------------------------------------------------
-- Main editor frame (created on first open)
-------------------------------------------------------------------------------

local editorFrame
local widgets = {}

local function CreateEditorFrame()
    local f = CreateFrame("Frame", "MBTEditorFrame", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.05, 0.05, 0.1, 0.92)
    f:SetBackdropBorderColor(0, 0.6, 0.8, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cff00ccffMidnightBattleText|r")

    -- Custom close button (no UIPanelCloseButton)
    local closeBtn = CreateFrame("Frame", nil, f)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:EnableMouse(true)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("|cffff4444X|r")
    closeBtn:SetScript("OnMouseDown", function()
        MBT:ToggleEditor()
    end)
    closeBtn:SetScript("OnEnter", function()
        closeText:SetText("|cffff8888X|r")
    end)
    closeBtn:SetScript("OnLeave", function()
        closeText:SetText("|cffff4444X|r")
    end)

    ---------------------------------------------------------------------------
    -- Scroll frame for content
    ---------------------------------------------------------------------------
    local scroll, content = CreateScrollFrame(f)

    ---------------------------------------------------------------------------
    -- Layout all sections
    ---------------------------------------------------------------------------
    local db = MBT.db
    local y = -4

    -- GENERAL ----------------------------------------------------------------
    y = CreateSection(content, y, "General")
    local cbEnabled
    cbEnabled, y = CreateCheckbox(content, y, "Enabled", "enabled")

    local cbHideBlizz
    cbHideBlizz, y = CreateCheckbox(content, y, "Hide Blizzard FCT", "hideBlizzardFCT")

    local dirItems = { "up", "down", "left", "right", "fountain" }
    local dirDD
    dirDD, y = CreateDropdown(content, y, "Scroll Direction", dirItems,
        function() return db.scrollDirection or "up" end,
        function(val) db.scrollDirection = val end
    )

    y = y - SECTION_GAP

    -- FONT -------------------------------------------------------------------
    y = CreateSection(content, y, "Font")

    local fontItems = {}
    for _, name in ipairs(MBT.FONT_NAMES) do
        table.insert(fontItems, { name = name, value = name, path = MBT.FONTS[name] })
    end

    local function GetCurrentFontName()
        for name, path in pairs(MBT.FONTS) do
            if path == db.font then return name end
        end
        return "Default"
    end

    local fontDD
    fontDD, y = CreateDropdown(content, y, "Font", fontItems,
        GetCurrentFontName,
        function(val)
            db.font = MBT.FONTS[val] or db.font
        end
    )
    widgets.fontDD = fontDD

    local fontSizeSlider
    fontSizeSlider, y = CreateSlider(content, y, "Font Size", "fontSize", 8, 72, 1)
    widgets.fontSize = fontSizeSlider

    local flagItems = {
        { name = "OUTLINE",       value = "OUTLINE" },
        { name = "THICKOUTLINE",  value = "THICKOUTLINE" },
        { name = "MONOCHROME",    value = "MONOCHROME" },
        { name = "None",          value = "" },
    }
    local flagsDD
    flagsDD, y = CreateDropdown(content, y, "Font Flags", flagItems,
        function() return db.fontFlags ~= "" and db.fontFlags or "None" end,
        function(val) db.fontFlags = val end
    )

    y = y - SECTION_GAP

    -- ANIMATION --------------------------------------------------------------
    y = CreateSection(content, y, "Animation")

    local durSlider
    durSlider, y = CreateSlider(content, y, "Duration", "scrollDuration", 0.5, 5, 0.1)

    local heightSlider
    heightSlider, y = CreateSlider(content, y, "Scroll Height", "scrollHeight", 20, 500, 5)

    local fadeSlider
    fadeSlider, y = CreateSlider(content, y, "Fade Start", "fadeStart", 0, 1, 0.05)

    y = y - SECTION_GAP

    -- CRITS ------------------------------------------------------------------
    y = CreateSection(content, y, "Crits")

    local cbCrits
    cbCrits, y = CreateCheckbox(content, y, "Emphasize Crits", "showCrits")

    local critSlider
    critSlider, y = CreateSlider(content, y, "Crit Scale", "critScale", 1, 3, 0.1)

    local cbOnlyCrits
    cbOnlyCrits, y = CreateCheckbox(content, y, "Only Show Crits", "showOnlyCrits")

    y = y - SECTION_GAP

    -- TEXT --------------------------------------------------------------------
    y = CreateSection(content, y, "Text")

    local cbAbbreviate
    cbAbbreviate, y = CreateCheckbox(content, y, "Abbreviate Numbers", "abbreviateNumbers")

    local cbHealPrefix
    cbHealPrefix, y = CreateCheckbox(content, y, "Heal '+' Prefix", "showHealPrefix")

    local cbFontShadow
    cbFontShadow, y = CreateCheckbox(content, y, "Font Shadow", "fontShadow")

    local cbIcons
    cbIcons, y = CreateCheckbox(content, y, "Show Spell Icons", "showIcons")

    local iconSizeSlider
    iconSizeSlider, y = CreateSlider(content, y, "Icon Size", "iconSize", 8, 32, 1)

    local alphaSlider
    alphaSlider, y = CreateSlider(content, y, "Text Opacity", "textAlpha", 0.3, 1.0, 0.05)

    local gapSlider
    gapSlider, y = CreateSlider(content, y, "Stacking Gap", "stackingGap", 0, 30, 1)

    y = y - SECTION_GAP

    -- COLORS ------------------------------------------------------------------
    y = CreateSection(content, y, "Colors")

    local cbClassColors
    cbClassColors, y = CreateCheckbox(content, y, "Use Class Colors (Outgoing)", "useClassColors")

    local swDamage
    swDamage, y = CreateColorSwatch(content, y, "Damage Color", "damageColor")

    local swHeal
    swHeal, y = CreateColorSwatch(content, y, "Heal Color", "healColor")

    local swMiss
    swMiss, y = CreateColorSwatch(content, y, "Miss Color", "missColor")

    local swCritDamage
    swCritDamage, y = CreateColorSwatch(content, y, "Crit Damage Color", "critDamageColor")

    local swCritHeal
    swCritHeal, y = CreateColorSwatch(content, y, "Crit Heal Color", "critHealColor")

    y = y - SECTION_GAP

    -- COLUMNS ----------------------------------------------------------------
    y = CreateSection(content, y, "Columns & Position")

    local inSlider
    inSlider, y = CreateSlider(content, y, "Incoming X", "incomingOffsetX", -600, 600, 5)
    widgets.incomingX = inSlider

    local outSlider
    outSlider, y = CreateSlider(content, y, "Outgoing X", "outgoingOffsetX", -600, 600, 5)
    widgets.outgoingX = outSlider

    local oySlider
    oySlider, y = CreateSlider(content, y, "Offset Y", "offsetY", -400, 400, 5)

    local cbNameplate
    cbNameplate, y = CreateCheckbox(content, y, "Nameplate Mode (outgoing)", "nameplateMode")

    local npOffsetSlider
    npOffsetSlider, y = CreateSlider(content, y, "Nameplate Y Offset", "nameplateOffsetY", -50, 100, 1)

    -- Visual mode handle selection buttons
    local vmLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vmLabel:SetPoint("TOPLEFT", content, "TOPLEFT", INDENT, y)
    vmLabel:SetText("Visual Mode — select handles to move:")
    y = y - 18

    local vmAnchorBtn
    vmAnchorBtn, y = CreateButton(content, y, "Move Anchor", 120, function()
        MBT:ShowHandle("anchor")
    end)
    widgets.vmAnchorBtn = vmAnchorBtn

    local vmIncomingBtn
    vmIncomingBtn, y = CreateButton(content, y, "Move Incoming", 120, function()
        MBT:ShowHandle("incoming")
    end)
    widgets.vmIncomingBtn = vmIncomingBtn

    local vmOutgoingBtn
    vmOutgoingBtn, y = CreateButton(content, y, "Move Outgoing", 120, function()
        MBT:ShowHandle("outgoing")
    end)
    widgets.vmOutgoingBtn = vmOutgoingBtn

    local vmAllBtn
    vmAllBtn, y = CreateButton(content, y, "Move All", 120, function()
        MBT:ShowHandle("all")
    end)
    widgets.vmAllBtn = vmAllBtn

    local vmExitBtn
    vmExitBtn, y = CreateButton(content, y, "Exit Visual Mode", 120, function()
        MBT:ExitVisualMode()
    end)
    widgets.vmExitBtn = vmExitBtn

    y = y - SECTION_GAP

    -- FILTERS ----------------------------------------------------------------
    y = CreateSection(content, y, "Filters")

    local threshSlider
    threshSlider, y = CreateSlider(content, y, "Threshold", "filterThreshold", 0, 50000, 100)

    local cbInDmg
    cbInDmg, y = CreateCheckbox(content, y, "Incoming Damage", "showIncomingDamage")
    local cbOutDmg
    cbOutDmg, y = CreateCheckbox(content, y, "Outgoing Damage", "showOutgoingDamage")
    local cbInHeal
    cbInHeal, y = CreateCheckbox(content, y, "Incoming Heals", "showIncomingHeals")
    local cbOutHeal
    cbOutHeal, y = CreateCheckbox(content, y, "Outgoing Heals", "showOutgoingHeals")
    local cbMisses
    cbMisses, y = CreateCheckbox(content, y, "Misses", "showMisses")
    local cbPet
    cbPet, y = CreateCheckbox(content, y, "Pet Damage", "showPetDamage")

    y = y - SECTION_GAP

    -- ACTIONS ----------------------------------------------------------------
    y = CreateSection(content, y, "Actions")

    local testBtn
    testBtn, y = CreateButton(content, y, "Test", 80, function()
        MBT:DisplayScrollText(12345,  "damage", "incoming", nil, false)
        MBT:DisplayScrollText(8765,   "damage", "outgoing", nil, false)
        MBT:DisplayScrollText(54321,  "damage", "outgoing", nil, true)
        MBT:DisplayScrollText(5432,   "heal",   "incoming", nil, false)
        MBT:DisplayScrollText(19876,  "heal",   "incoming", nil, true)
        MBT:DisplayScrollText("DODGE", "miss",  "incoming", nil, false)
    end)

    local resetBtn
    resetBtn, y = CreateButton(content, y, "Reset Defaults", 120, function()
        wipe(MidnightBattleTextDB)
        print("|cff00ccffMBT|r: Settings reset. Reload UI (/reload) to apply.")
    end)

    y = y - SECTION_GAP

    -- PROFILES ---------------------------------------------------------------
    y = CreateSection(content, y, "Profiles")

    -- Profile name input
    local profileInput = CreateFrame("EditBox", nil, content, "BackdropTemplate")
    profileInput:SetSize(SLIDER_WIDTH, 22)
    profileInput:SetPoint("TOPLEFT", content, "TOPLEFT", INDENT, y)
    profileInput:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    profileInput:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    profileInput:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    profileInput:SetFontObject(GameFontNormalSmall)
    profileInput:SetTextInsets(6, 6, 0, 0)
    profileInput:SetAutoFocus(false)
    profileInput:SetMaxLetters(30)
    profileInput:SetText("")

    local profilePlaceholder = profileInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    profilePlaceholder:SetPoint("LEFT", 6, 0)
    profilePlaceholder:SetText("Profile name...")
    profileInput:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then
            profilePlaceholder:Show()
        else
            profilePlaceholder:Hide()
        end
    end)
    profileInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    profileInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    y = y - 28

    -- Profile status text
    local profileStatus = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileStatus:SetPoint("TOPLEFT", content, "TOPLEFT", INDENT, y + 6)
    profileStatus:SetText("")

    -- Save button
    local saveBtn
    saveBtn, y = CreateButton(content, y, "Save Profile", 100, function()
        local name = profileInput:GetText()
        if name == "" then
            profileStatus:SetText("|cffff4444Enter a name first|r")
            return
        end
        if MBT:SaveProfile(name) then
            profileStatus:SetText("|cff00ff00Saved: " .. name .. "|r")
        end
    end)

    -- Load button
    local loadBtn
    loadBtn, y = CreateButton(content, y, "Load Profile", 100, function()
        local name = profileInput:GetText()
        if name == "" then
            profileStatus:SetText("|cffff4444Enter a name first|r")
            return
        end
        if MBT:LoadProfile(name) then
            profileStatus:SetText("|cff00ff00Loaded: " .. name .. ". /reload to apply.|r")
        else
            profileStatus:SetText("|cffff4444Profile not found|r")
        end
    end)

    -- Delete button
    local delBtn
    delBtn, y = CreateButton(content, y, "Delete Profile", 100, function()
        local name = profileInput:GetText()
        if name == "" then
            profileStatus:SetText("|cffff4444Enter a name first|r")
            return
        end
        if MBT:DeleteProfile(name) then
            profileStatus:SetText("|cffffd700Deleted: " .. name .. "|r")
        else
            profileStatus:SetText("|cffff4444Profile not found|r")
        end
    end)

    -- List profiles button
    local listBtn
    listBtn, y = CreateButton(content, y, "List Profiles", 100, function()
        local names = MBT:GetProfileNames()
        if #names == 0 then
            profileStatus:SetText("|cff888888No saved profiles|r")
        else
            profileStatus:SetText("|cffffd700" .. table.concat(names, ", ") .. "|r")
        end
    end)

    -- Set content height for scrolling
    content:SetHeight(math.abs(y) + 20)

    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- Visual Mode: draggable column handles + live preview ticker
-- Supports showing individual handles so stacked columns can be moved
-- independently via "Move Anchor" / "Move Incoming" / "Move Outgoing" / "All"
-------------------------------------------------------------------------------

local visualActive = false
local activeHandles = {}  -- tracks which handles are currently shown
local handles = {}
local previewTicker

local function CreateHandle(labelText, r, g, b)
    local h = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    h:SetSize(130, 32)
    h:SetFrameStrata("DIALOG")
    h:SetBackdrop(BACKDROP)
    h:SetBackdropColor(r, g, b, 0.5)
    h:SetBackdropBorderColor(r, g, b, 1)

    local text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText(labelText)

    h:SetMovable(true)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetClampedToScreen(true)
    h:Hide()
    return h
end

local function PositionHandle(hType)
    local db = MBT.db
    local anchorFrame = MBT.anchor
    if not anchorFrame then return end

    local ax, ay = anchorFrame:GetCenter()
    if not ax then return end

    if hType == "anchor" and handles.anchor then
        handles.anchor:ClearAllPoints()
        handles.anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ax, ay)
    elseif hType == "incoming" and handles.incoming then
        handles.incoming:ClearAllPoints()
        handles.incoming:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            ax + db.incomingOffsetX, ay + db.offsetY)
    elseif hType == "outgoing" and handles.outgoing then
        handles.outgoing:ClearAllPoints()
        handles.outgoing:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            ax + db.outgoingOffsetX, ay + db.offsetY)
    end
end

local function PositionAllHandles()
    PositionHandle("anchor")
    PositionHandle("incoming")
    PositionHandle("outgoing")
end

local function SyncHandleToDb(handle, handleType)
    local db = MBT.db
    local anchorFrame = MBT.anchor
    if not anchorFrame then return end

    if handleType == "anchor" then
        local hx, hy = handle:GetCenter()
        local sw, sh = UIParent:GetSize()
        db.anchorPoint    = "CENTER"
        db.anchorRelPoint = "CENTER"
        db.anchorX = hx - sw / 2
        db.anchorY = hy - sh / 2
        anchorFrame:ClearAllPoints()
        anchorFrame:SetPoint("CENTER", UIParent, "CENTER", db.anchorX, db.anchorY)
    else
        local ax, ay = anchorFrame:GetCenter()
        local hx, hy = handle:GetCenter()
        if ax and hx then
            local offsetX = math.floor(hx - ax + 0.5)
            local offsetY = math.floor(hy - ay + 0.5)
            if handleType == "incoming" then
                db.incomingOffsetX = offsetX
                if widgets.incomingX then
                    widgets.incomingX:SetValue(offsetX)
                end
            else
                db.outgoingOffsetX = offsetX
                if widgets.outgoingX then
                    widgets.outgoingX:SetValue(offsetX)
                end
            end
        end
    end
end

local function SetupVisualMode()
    if not handles.anchor then
        handles.anchor   = CreateHandle("|cff00ccffAnchor|r",   0, 0.8, 1)
        handles.incoming = CreateHandle("|cffff4444Incoming|r", 1, 0.3, 0.3)
        handles.outgoing = CreateHandle("|cff44ff44Outgoing|r", 0.3, 1, 0.3)

        for hType, handle in pairs(handles) do
            handle:SetScript("OnDragStart", function(self)
                self:StartMoving()
            end)
            handle:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                SyncHandleToDb(self, hType)
                -- Reposition other visible handles when anchor moves
                if hType == "anchor" then
                    for _, visType in ipairs(activeHandles) do
                        if visType ~= "anchor" then
                            PositionHandle(visType)
                        end
                    end
                end
            end)
        end
    end
end

local function StartPreviewTicker()
    if previewTicker then previewTicker:Cancel() end
    previewTicker = C_Timer.NewTicker(2.0, function()
        MBT:DisplayScrollText(math.random(1000, 50000), "damage", "incoming", nil, false)
        MBT:DisplayScrollText(math.random(1000, 50000), "damage", "outgoing", nil, false)
        if math.random(1, 3) == 1 then
            MBT:DisplayScrollText(math.random(10000, 99999), "damage", "outgoing", nil, true)
        end
        MBT:DisplayScrollText(math.random(1000, 20000), "heal", "incoming", nil, false)
    end)
end

local function HideAllHandles()
    if handles.anchor   then handles.anchor:Hide()   end
    if handles.incoming then handles.incoming:Hide() end
    if handles.outgoing then handles.outgoing:Hide() end
    wipe(activeHandles)
end

--- Show a specific handle (or all). Entering visual mode if not already active.
--- @param which string "anchor", "incoming", "outgoing", or "all"
function MBT:ShowHandle(which)
    SetupVisualMode()

    -- Hide everything first so we get a clean state
    HideAllHandles()

    local toShow
    if which == "all" then
        toShow = {"anchor", "incoming", "outgoing"}
    else
        toShow = {which}
    end

    for _, hType in ipairs(toShow) do
        PositionHandle(hType)
        if handles[hType] then
            handles[hType]:Show()
        end
        table.insert(activeHandles, hType)
    end

    if not visualActive then
        visualActive = true
        StartPreviewTicker()
    end

    if which == "all" then
        print("|cff00ccffMBT|r: Showing |cffffd700all|r handles. Drag to reposition.")
    else
        local colorMap = {
            anchor   = "|cff00ccffAnchor|r",
            incoming = "|cffff4444Incoming|r",
            outgoing = "|cff44ff44Outgoing|r",
        }
        print("|cff00ccffMBT|r: Showing " .. (colorMap[which] or which) .. " handle. Drag to reposition.")
    end
end

function MBT:ToggleVisualMode()
    if visualActive then
        MBT:ExitVisualMode()
    else
        MBT:ShowHandle("all")
    end
end

function MBT:EnterVisualMode()
    MBT:ShowHandle("all")
end

function MBT:ExitVisualMode()
    HideAllHandles()

    if previewTicker then
        previewTicker:Cancel()
        previewTicker = nil
    end

    visualActive = false
    print("|cff00ccffMBT|r: Visual mode |cffff0000OFF|r. Positions saved.")
end

-------------------------------------------------------------------------------
-- Open / Close / Toggle
-------------------------------------------------------------------------------

function MBT:ToggleEditor()
    if not editorFrame then
        editorFrame = CreateEditorFrame()
    end
    if editorFrame:IsShown() then
        editorFrame:Hide()
        if visualActive then
            MBT:ExitVisualMode()
        end
    else
        editorFrame:Show()
    end
end

function MBT:OpenEditor()
    if not editorFrame then
        editorFrame = CreateEditorFrame()
    end
    editorFrame:Show()
end

function MBT:CloseEditor()
    if editorFrame then
        editorFrame:Hide()
    end
    if visualActive then
        MBT:ExitVisualMode()
    end
end
