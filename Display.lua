-------------------------------------------------------------------------------
-- MidnightBattleText - Display
-- Frame pooling, scroll animations, and draggable anchor
-- Copyright (c) 2026 Shea (iTek). All Rights Reserved.
-------------------------------------------------------------------------------

local ADDON_NAME, MBT = ...

-------------------------------------------------------------------------------
-- Anchor frame
-------------------------------------------------------------------------------

local anchor
local anchorOverlay  -- visible drag handle shown during /mbt move

-------------------------------------------------------------------------------
-- Frame pool
-------------------------------------------------------------------------------

local pool = {}
local activeFrames = {}
local POOL_MAX = 30

-- Stacking offset per column, resets periodically to avoid runaway drift
local columnNextOffset = { incoming = 0, outgoing = 0 }

-------------------------------------------------------------------------------
-- Number abbreviation helper
-------------------------------------------------------------------------------

local function AbbreviateNumber(amount)
    local ok, result = pcall(function()
        if amount >= 1000000 then
            return string.format("%.1fM", amount / 1000000)
        elseif amount >= 1000 then
            return string.format("%.1fk", amount / 1000)
        end
        return tostring(amount)
    end)
    return ok and result or amount
end

-------------------------------------------------------------------------------
-- Direction helpers
-------------------------------------------------------------------------------

local function GetScrollOffset(direction, distance)
    if direction == "down"     then return 0, -distance end
    if direction == "left"     then return -distance, 0 end
    if direction == "right"    then return  distance, 0 end
    if direction == "fountain" then
        local angle = math.rad(math.random(30, 150))
        return math.cos(angle) * distance, math.sin(angle) * distance
    end
    return 0, distance -- "up" (default)
end

local function GetStackStep(direction, fontSize, gap)
    local step = fontSize + (gap or 6)
    if direction == "fountain" then
        return 0, 0
    end
    if direction == "left" or direction == "right" then
        return 0, step
    end
    if direction == "down" then return 0, -step end
    return 0, step -- "up"
end

-------------------------------------------------------------------------------
-- Acquire / Release
-------------------------------------------------------------------------------

local function CreateTextFrame()
    local f = CreateFrame("Frame", nil, anchor)
    f:SetSize(300, 40)
    f:SetFrameStrata("HIGH")

    -- Spell icon container (for border + mask)
    local iconFrame = CreateFrame("Frame", nil, f)
    iconFrame:SetSize(16, 16)
    iconFrame:SetPoint("RIGHT", f, "LEFT", -4, 0)
    f.iconFrame = iconFrame

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconFrame)
    f.icon = icon

    -- Round mask (applied dynamically)
    local iconMask = iconFrame:CreateMaskTexture()
    iconMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    iconMask:SetAllPoints(iconFrame)
    f.iconMask = iconMask

    -- Border overlay
    local iconBorder = iconFrame:CreateTexture(nil, "OVERLAY")
    iconBorder:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 1, -1)
    iconBorder:SetColorTexture(0, 0, 0, 1)
    iconBorder:Hide()
    f.iconBorder = iconBorder

    -- Icon goes on top of border
    icon:SetDrawLayer("ARTWORK", 1)
    iconBorder:SetDrawLayer("ARTWORK", 0)

    -- Text
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    f.text = text

    -- Animation group: translate + fade out
    local ag = f:CreateAnimationGroup()
    f.animGroup = ag

    local translate = ag:CreateAnimation("Translation")
    translate:SetSmoothing("OUT")
    f.translateAnim = translate

    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    f.fadeAnim = fade

    -- Crit bounce
    local critGroup = f:CreateAnimationGroup()
    f.critGroup = critGroup

    local scaleUp = critGroup:CreateAnimation("Scale")
    scaleUp:SetScaleFrom(1, 1)
    scaleUp:SetScaleTo(1.4, 1.4)
    scaleUp:SetDuration(0.1)
    scaleUp:SetSmoothing("IN")
    scaleUp:SetOrder(1)

    local scaleDown = critGroup:CreateAnimation("Scale")
    scaleDown:SetScaleFrom(1.4, 1.4)
    scaleDown:SetScaleTo(1, 1)
    scaleDown:SetDuration(0.15)
    scaleDown:SetSmoothing("OUT")
    scaleDown:SetOrder(2)

    ag:SetScript("OnFinished", function()
        f:Hide()
        f:ClearAllPoints()
        f.icon:Hide()
        f.iconFrame:Hide()
        f.iconBorder:Hide()
        f.icon:RemoveMaskTexture(f.iconMask)
        -- Restore parent to anchor if it was re-parented for nameplate mode
        if f.nameplateBound then
            f:SetParent(anchor)
            f:SetFrameStrata("HIGH")
            f.nameplateBound = nil
        end
        for i, active in ipairs(activeFrames) do
            if active == f then
                table.remove(activeFrames, i)
                break
            end
        end
        if #pool < POOL_MAX then
            table.insert(pool, f)
        end
    end)

    return f
end

local function AcquireFrame()
    local f = table.remove(pool)
    if not f then
        f = CreateTextFrame()
    end
    table.insert(activeFrames, f)
    return f
end

-------------------------------------------------------------------------------
-- Reset column stacking periodically
-------------------------------------------------------------------------------

local resetTimer = 0
local RESET_INTERVAL = 0.3

local function OnUpdate(self, elapsed)
    resetTimer = resetTimer + elapsed
    if resetTimer >= RESET_INTERVAL then
        resetTimer = 0
        columnNextOffset.incoming = 0
        columnNextOffset.outgoing = 0
    end
end

-------------------------------------------------------------------------------
-- Color lookup from db
-------------------------------------------------------------------------------

local COLOR_KEYS = {
    damage = "damageColor",
    heal   = "healColor",
    miss   = "missColor",
}

local CRIT_COLOR_KEYS = {
    damage = "critDamageColor",
    heal   = "critHealColor",
}

local FALLBACK_COLOR = {1.0, 0.2, 0.2}

-- Class color cache (populated on first use)
local playerClassColor

-------------------------------------------------------------------------------
-- Display a scrolling text entry
-------------------------------------------------------------------------------

function MBT:DisplayScrollText(amount, category, column, spellId, isCrit, destGUID)
    local db = self.db
    local f = AcquireFrame()
    local applyCrit = isCrit and db.showCrits

    -- Font: crits get a scaled-up size
    local size = db.fontSize
    if applyCrit then
        size = math.floor(size * db.critScale)
    end
    f.text:SetFont(db.font, size, db.fontFlags)

    -- Font shadow
    if db.fontShadow then
        f.text:SetShadowOffset(2, -2)
        f.text:SetShadowColor(0, 0, 0, 0.8)
    else
        f.text:SetShadowOffset(0, 0)
    end

    -- Color from db (class colors override damage colors for outgoing)
    local color
    if db.useClassColors and category == "damage" and column == "outgoing" then
        if not playerClassColor then
            local _, class = UnitClass("player")
            local cc = RAID_CLASS_COLORS[class]
            if cc then
                playerClassColor = {cc.r, cc.g, cc.b}
            end
        end
        color = playerClassColor
    end
    if not color then
        if applyCrit and CRIT_COLOR_KEYS[category] then
            color = db[CRIT_COLOR_KEYS[category]]
        end
    end
    if not color then
        color = db[COLOR_KEYS[category] or "damageColor"] or FALLBACK_COLOR
    end
    f.text:SetTextColor(color[1], color[2], color[3], 1)

    ---------------------------------------------------------------------------
    -- Set the text content
    ---------------------------------------------------------------------------
    if category == "miss" then
        f.text:SetText(amount)
    else
        local displayAmount = amount
        if db.abbreviateNumbers then
            displayAmount = AbbreviateNumber(amount)
        end
        if category == "heal" and db.showHealPrefix then
            local ok, prefixed = pcall(function()
                return "+" .. displayAmount
            end)
            displayAmount = ok and prefixed or displayAmount
        end
        f.text:SetText(displayAmount)
    end

    ---------------------------------------------------------------------------
    -- Spell icon
    -- C_Spell.GetSpellTexture may be restricted by Secret Values in 12.0,
    -- so we try multiple APIs with pcall safety.
    ---------------------------------------------------------------------------
    if db.showIcons and spellId then
        local iconTexture
        -- Try C_Spell.GetSpellTexture first (modern API)
        local ok1, tex1 = pcall(C_Spell.GetSpellTexture, spellId)
        if ok1 and tex1 then
            iconTexture = tex1
        else
            -- Try C_Spell.GetSpellInfo which returns icon as .iconID
            local ok2, info = pcall(C_Spell.GetSpellInfo, spellId)
            if ok2 and info and info.iconID then
                iconTexture = info.iconID
            else
                -- Try legacy GetSpellTexture if available
                if GetSpellTexture then
                    local ok3, tex3 = pcall(GetSpellTexture, spellId)
                    if ok3 and tex3 then
                        iconTexture = tex3
                    end
                end
            end
        end
        if iconTexture then
            local sz = db.iconSize
            f.iconFrame:SetSize(sz, sz)
            f.iconFrame:ClearAllPoints()

            -- Anchor position relative to the text
            local anchorPos = db.iconAnchor or "LEFT"
            local ox = db.iconOffsetX or -4
            local oy = db.iconOffsetY or 0
            local anchorMap = {
                LEFT        = {"RIGHT",       "LEFT",        ox, oy},
                RIGHT       = {"LEFT",        "RIGHT",       ox, oy},
                TOP         = {"BOTTOM",      "TOP",         ox, oy},
                BOTTOM      = {"TOP",         "BOTTOM",      ox, oy},
                TOPLEFT     = {"BOTTOMRIGHT", "TOPLEFT",     ox, oy},
                TOPRIGHT    = {"BOTTOMLEFT",  "TOPRIGHT",    ox, oy},
                BOTTOMLEFT  = {"TOPRIGHT",    "BOTTOMLEFT",  ox, oy},
                BOTTOMRIGHT = {"TOPLEFT",     "BOTTOMRIGHT", ox, oy},
            }
            local pts = anchorMap[anchorPos] or anchorMap["LEFT"]
            f.iconFrame:SetPoint(pts[1], f, pts[2], pts[3], pts[4])

            f.icon:SetTexture(iconTexture)
            f.icon:SetAlpha(db.iconAlpha or 1.0)
            f.icon:SetDesaturated(db.iconDesaturate or false)

            -- Round mask
            if db.iconRound then
                f.icon:AddMaskTexture(f.iconMask)
            else
                f.icon:RemoveMaskTexture(f.iconMask)
            end

            -- Border
            if db.iconBorder then
                local bs = db.iconBorderSize or 1
                f.iconBorder:ClearAllPoints()
                f.iconBorder:SetPoint("TOPLEFT", f.iconFrame, "TOPLEFT", -bs, bs)
                f.iconBorder:SetPoint("BOTTOMRIGHT", f.iconFrame, "BOTTOMRIGHT", bs, -bs)
                local bc = db.iconBorderColor or {0, 0, 0}
                f.iconBorder:SetColorTexture(bc[1], bc[2], bc[3], 1)
                f.iconBorder:Show()
            else
                f.iconBorder:Hide()
            end

            f.iconFrame:Show()
            f.icon:Show()
        else
            f.iconFrame:Hide()
            f.icon:Hide()
        end
    else
        f.iconFrame:Hide()
        f.icon:Hide()
    end

    ---------------------------------------------------------------------------
    -- Position: nameplate mode or fixed anchor + column offsets
    ---------------------------------------------------------------------------
    local direction = db.scrollDirection or "up"
    local gap = db.stackingGap or 6
    local usedNameplate = false

    if db.nameplateMode and column == "outgoing" and destGUID then
        local plate = MBT:GetNameplateByGUID(destGUID)
        if plate then
            -- Re-parent to UIParent so the frame isn't clipped or offset by
            -- the anchor's own position / scale.
            f:SetParent(UIParent)
            f:SetFrameStrata("HIGH")
            f.nameplateBound = true

            local stackIdx = columnNextOffset[column] or 0
            local stackDX, stackDY = GetStackStep(direction, db.fontSize, gap)
            local posX = stackDX * stackIdx
            local posY = (db.nameplateOffsetY or 20) + (stackDY * stackIdx)
            f:SetPoint("BOTTOM", plate, "TOP", posX, posY)
            columnNextOffset[column] = stackIdx + 1
            usedNameplate = true
        end
    end

    if not usedNameplate then
        local colOffsetX = (column == "incoming") and db.incomingOffsetX or db.outgoingOffsetX
        local stackIdx = columnNextOffset[column] or 0
        local stackDX, stackDY = GetStackStep(direction, db.fontSize, gap)
        local posX = colOffsetX + (stackDX * stackIdx)
        local posY = db.offsetY + (stackDY * stackIdx)
        f:SetPoint("CENTER", anchor, "CENTER", posX, posY)
        columnNextOffset[column] = stackIdx + 1
    end

    ---------------------------------------------------------------------------
    -- Animation: scroll in configured direction + fade
    ---------------------------------------------------------------------------
    local duration = db.scrollDuration
    local scrollX, scrollY = GetScrollOffset(direction, db.scrollHeight)

    f.translateAnim:SetOffset(scrollX, scrollY)
    f.translateAnim:SetDuration(duration)

    local fadeDelay = duration * db.fadeStart
    f.fadeAnim:SetStartDelay(fadeDelay)
    f.fadeAnim:SetDuration(duration - fadeDelay)

    f:SetAlpha(db.textAlpha or 1)
    f:Show()
    f.animGroup:Play()

    -- Crit bounce
    if applyCrit then
        f.critGroup:Play()
    end
end

-------------------------------------------------------------------------------
-- Draggable anchor overlay (shown during /mbt move, hidden on /mbt lock)
-------------------------------------------------------------------------------

local function CreateAnchorOverlay()
    local ov = CreateFrame("Frame", "MidnightBattleTextAnchorOverlay", UIParent, "BackdropTemplate")
    ov:SetSize(200, 40)
    ov:SetFrameStrata("DIALOG")
    ov:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    ov:SetBackdropColor(0, 0, 0, 0.7)
    ov:SetBackdropBorderColor(0, 0.8, 1, 1)

    local label = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("|cff00ccffMBT Anchor|r - Drag to move\n/mbt lock to save")
    ov.label = label

    ov:SetMovable(true)
    ov:EnableMouse(true)
    ov:RegisterForDrag("LeftButton")

    ov:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    ov:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        anchor:ClearAllPoints()
        anchor:SetPoint(point, UIParent, relPoint, x, y)
    end)

    ov:Hide()
    return ov
end

-------------------------------------------------------------------------------
-- Move / Lock API
-------------------------------------------------------------------------------

function MBT:MoveAnchor()
    if not anchorOverlay then
        anchorOverlay = CreateAnchorOverlay()
    end
    local db = self.db
    anchorOverlay:ClearAllPoints()
    anchorOverlay:SetPoint(db.anchorPoint, UIParent, db.anchorRelPoint, db.anchorX, db.anchorY)
    anchorOverlay:Show()
    print("|cff00ccffMBT|r: Drag the anchor to reposition. Type |cff00ccff/mbt lock|r when done.")
end

function MBT:LockAnchor()
    if not anchorOverlay or not anchorOverlay:IsShown() then
        print("|cff00ccffMBT|r: Anchor is already locked.")
        return
    end
    local point, _, relPoint, x, y = anchorOverlay:GetPoint(1)
    local db = self.db
    db.anchorPoint    = point
    db.anchorRelPoint = relPoint
    db.anchorX        = x
    db.anchorY        = y

    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, relPoint, x, y)

    anchorOverlay:Hide()
    print("|cff00ccffMBT|r: Anchor locked at " ..
          point .. " (" .. math.floor(x) .. ", " .. math.floor(y) .. ")")
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------

function MBT:InitDisplay()
    anchor = CreateFrame("Frame", "MidnightBattleTextAnchor", UIParent)
    anchor:SetSize(1, 1)

    local db = self.db
    anchor:SetPoint(
        db.anchorPoint or "CENTER",
        UIParent,
        db.anchorRelPoint or "CENTER",
        db.anchorX or 0,
        db.anchorY or 100
    )

    anchor:SetScript("OnUpdate", OnUpdate)

    for i = 1, 10 do
        table.insert(pool, CreateTextFrame())
    end

    MBT.anchor = anchor
end
