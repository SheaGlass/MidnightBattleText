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

-- Accumulation stacking state
local activeStacks    = {}  -- stackKey -> stack object
local stackSlotCount  = { incoming = 0, outgoing = 0 }  -- live slot counter per column

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
        if f.onRelease then f.onRelease() f.onRelease = nil end
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

local function LaunchStackAnimation(stack)
    local f = stack.frame
    local db = MBT.db
    local direction = db.scrollDirection or "up"
    local scrollX, scrollY = GetScrollOffset(direction, db.scrollHeight)
    local duration = db.scrollDuration
    f.translateAnim:SetOffset(scrollX, scrollY)
    f.translateAnim:SetDuration(duration)
    local fadeDelay = duration * db.fadeStart
    f.fadeAnim:SetStartDelay(fadeDelay)
    f.fadeAnim:SetDuration(duration - fadeDelay)
    f.animGroup:Play()
    if stack.isCrit and db.showCrits then
        f.critGroup:Play()
    end
    stack.animStarted = true
end

local function OnUpdate(self, elapsed)
    local db = MBT.db
    if db and db.stackingMode then
        -- Stacking mode: check each active stack for timeout
        local timeout = db.stackTimeout or 1.0
        local now = GetTime()
        for _, stack in pairs(activeStacks) do
            if not stack.animStarted and (now - stack.lastHitTime) >= timeout then
                LaunchStackAnimation(stack)
            end
        end
    else
        -- Normal mode: reset column offsets periodically to prevent drift
        resetTimer = resetTimer + elapsed
        if resetTimer >= RESET_INTERVAL then
            resetTimer = 0
            columnNextOffset.incoming = 0
            columnNextOffset.outgoing = 0
        end
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
-- Spell icon texture lookup (shared by stacking and regular display)
-- Tries every available API in order of reliability.
-------------------------------------------------------------------------------

local function GetSpellIconTexture(spellId)
    if not spellId then return nil end

    -- 1. Modern API: C_Spell.GetSpellTexture → fileDataID
    local ok1, tex1 = pcall(C_Spell.GetSpellTexture, spellId)
    if ok1 and tex1 then return tex1 end

    -- 2. Old global GetSpellInfo → name, _, texture (3rd return = icon)
    if GetSpellInfo then
        local ok2, _, _, icon2 = pcall(GetSpellInfo, spellId)
        if ok2 and icon2 then return icon2 end
    end

    -- 3. C_Spell.GetSpellInfo struct → .iconID
    if C_Spell and C_Spell.GetSpellInfo then
        local ok3, info = pcall(C_Spell.GetSpellInfo, spellId)
        if ok3 and info and info.iconID then return info.iconID end
    end

    -- 4. Legacy GetSpellTexture
    if GetSpellTexture then
        local ok4, tex4 = pcall(GetSpellTexture, spellId)
        if ok4 and tex4 then return tex4 end
    end

    -- 5. Last resort: the current player's last-cast spell (non-secret, from UNIT_SPELLCAST_SUCCEEDED)
    if MBT.GetLastPlayerSpellId and spellId ~= MBT.GetLastPlayerSpellId() then
        local altId = MBT.GetLastPlayerSpellId()
        if altId then
            local ok5, tex5 = pcall(C_Spell.GetSpellTexture, altId)
            if ok5 and tex5 then return tex5 end
            if GetSpellInfo then
                local ok6, _, _, icon6 = pcall(GetSpellInfo, altId)
                if ok6 and icon6 then return icon6 end
            end
        end
    end

    return nil
end

-- Apply spell icon to a frame (shared setup)
local function ApplySpellIcon(f, spellId, db)
    local iconTexture = GetSpellIconTexture(spellId)
    if not iconTexture then
        f.iconFrame:Hide()
        f.icon:Hide()
        return
    end

    local sz = db.iconSize
    f.iconFrame:SetSize(sz, sz)
    f.iconFrame:ClearAllPoints()

    local anchorPos = db.iconAnchor or "LEFT"
    local ox, oy = db.iconOffsetX or -4, db.iconOffsetY or 0
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
    f.iconFrame:SetPoint(pts[1], f.text, pts[2], pts[3], pts[4])

    f.icon:SetTexture(iconTexture)
    f.icon:SetAlpha(db.iconAlpha or 1.0)
    f.icon:SetDesaturated(db.iconDesaturate or false)

    if db.iconRound then
        f.icon:AddMaskTexture(f.iconMask)
    else
        f.icon:RemoveMaskTexture(f.iconMask)
    end

    if db.iconBorder then
        local bs = db.iconBorderSize or 1
        f.iconBorder:ClearAllPoints()
        f.iconBorder:SetPoint("TOPLEFT",     f.iconFrame, "TOPLEFT",     -bs,  bs)
        f.iconBorder:SetPoint("BOTTOMRIGHT", f.iconFrame, "BOTTOMRIGHT",  bs, -bs)
        local bc = db.iconBorderColor or {0, 0, 0}
        f.iconBorder:SetColorTexture(bc[1], bc[2], bc[3], 1)
        f.iconBorder:Show()
    else
        f.iconBorder:Hide()
    end

    f.iconFrame:Show()
    f.icon:Show()
end

-------------------------------------------------------------------------------
-- Stacking accumulation display
-------------------------------------------------------------------------------

local function FormatStackText(stack, db)
    local amount = stack.total
    local displayAmount = db.abbreviateNumbers and AbbreviateNumber(amount) or amount
    local prefix = stack.isPet and "Pet " or ""
    local h, c = stack.hits, stack.crits
    -- Concatenation can throw on secret numeric values; pcall-wrap and fall back to raw amount.
    local ok, result = pcall(function()
        if h <= 1 then
            return prefix .. displayAmount
        end
        if c == 0 then
            return prefix .. displayAmount .. " [" .. h .. " Hits]"
        elseif c == h then
            return prefix .. displayAmount .. " [" .. c .. (c == 1 and " Crit]" or " Crits]")
        else
            return prefix .. displayAmount .. " [" .. h .. " Hits, " .. c .. (c == 1 and " Crit]" or " Crits]")
        end
    end)
    return ok and result or displayAmount
end

-- Resolve color for a stack (mirrors DisplayScrollText color logic)
local function GetStackColor(stack, db)
    if stack.category == "damage" and not stack.spellId and not stack.isPet then
        return {1, 1, 1}  -- auto-attack: white
    end
    if not stack.isPet and db.useClassColors and stack.category == "damage" and stack.column == "outgoing" then
        if not playerClassColor then
            local _, class = UnitClass("player")
            local cc = RAID_CLASS_COLORS[class]
            if cc then playerClassColor = {cc.r, cc.g, cc.b} end
        end
        return playerClassColor
    end
    if stack.isCrit and db.showCrits and CRIT_COLOR_KEYS[stack.category] then
        return db[CRIT_COLOR_KEYS[stack.category]]
    end
    return db[COLOR_KEYS[stack.category] or "damageColor"] or FALLBACK_COLOR
end

function MBT:AccumulateAndDisplay(amount, category, column, spellId, isCrit, destGUID, isPet)
    local db = self.db

    -- Build a safe (non-secret) stack key.
    -- destGUID from UnitGUID() can be a secret value even inside pcall success,
    -- so we exclude it from the key to avoid "table index is secret" errors.
    local spellKey = spellId and tostring(spellId) or (isPet and "petswing" or "swing")
    local stackKey = spellKey .. "|" .. column

    local stack = activeStacks[stackKey]

    if stack and not stack.animStarted then
        -- Update existing accumulation entry in-place
        local ok, newTotal = pcall(function() return stack.total + amount end)
        stack.total = ok and newTotal or stack.total
        stack.hits  = stack.hits + 1
        if isCrit then
            stack.crits  = stack.crits + 1
            stack.isCrit = true
        end
        stack.lastHitTime = GetTime()
        -- Update displayed text (frame is still static, no animation yet)
        local textStr = FormatStackText(stack, db)
        local color = GetStackColor(stack, db)
        stack.frame.text:SetText(textStr)
        stack.frame.text:SetTextColor(color[1], color[2], color[3], 1)
        return
    end

    -- New stack: acquire a frame and show it statically (animation deferred until timeout)
    local f = AcquireFrame()

    -- Font
    local size = db.fontSize
    if isCrit and db.showCrits then size = math.floor(size * db.critScale) end
    f.text:SetFont(db.font, size, db.fontFlags)
    if db.fontShadow then
        f.text:SetShadowOffset(2, -2)
        f.text:SetShadowColor(0, 0, 0, 0.8)
    else
        f.text:SetShadowOffset(0, 0)
    end

    local newStack = {
        key         = stackKey,
        spellId     = spellId,
        category    = category,
        column      = column,
        destGUID    = destGUID,
        isPet       = isPet,
        isCrit      = isCrit,
        total       = amount,
        hits        = 1,
        crits       = isCrit and 1 or 0,
        frame       = f,
        lastHitTime = GetTime(),
        animStarted = false,
        slotIdx     = stackSlotCount[column],
    }
    stackSlotCount[column] = stackSlotCount[column] + 1
    activeStacks[stackKey] = newStack

    -- Text content
    local textStr = FormatStackText(newStack, db)
    f.text:SetText(textStr)

    -- Color
    local color = GetStackColor(newStack, db)
    f.text:SetTextColor(color[1], color[2], color[3], 1)

    -- Spell icon
    if db.showIcons then
        ApplySpellIcon(f, spellId, db)
    else
        f.iconFrame:Hide()
        f.icon:Hide()
    end

    -- Position (static; animation translation will play from here when timeout fires)
    local direction = db.scrollDirection or "up"
    local gap = db.stackingGap or 6
    local colOffsetX = (column == "incoming") and db.incomingOffsetX or db.outgoingOffsetX
    local slotIdx = newStack.slotIdx
    local stackDX, stackDY = GetStackStep(direction, db.fontSize, gap)
    local posX = colOffsetX + (stackDX * slotIdx)
    local posY = db.offsetY + (stackDY * slotIdx)
    f:SetPoint("CENTER", anchor, "CENTER", posX, posY)

    -- Alpha and show (no animation yet)
    f:SetAlpha(db.textAlpha or 1)
    f:Show()

    -- When animation finishes, clean up stack entry.
    -- Guard with identity check: a new stack for the same key may have replaced us.
    f.onRelease = function()
        if activeStacks[stackKey] == newStack then
            activeStacks[stackKey] = nil
        end
        stackSlotCount[column] = math.max(0, stackSlotCount[column] - 1)
    end
end

-------------------------------------------------------------------------------
-- Display a scrolling text entry
-------------------------------------------------------------------------------

function MBT:DisplayScrollText(amount, category, column, spellId, isCrit, destGUID, isPet)
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
    -- Auto-attacks (swings) have no spellId — always show as white
    if category == "damage" and spellId == nil then
        color = {1, 1, 1}
    end
    if not color and db.useClassColors and category == "damage" and column == "outgoing" then
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
        if isPet then
            local ok, prefixed = pcall(function()
                return "Pet " .. displayAmount
            end)
            displayAmount = ok and prefixed or displayAmount
        end
        f.text:SetText(displayAmount)
    end

    ---------------------------------------------------------------------------
    -- Spell icon
    ---------------------------------------------------------------------------
    if db.showIcons then
        ApplySpellIcon(f, spellId, db)
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
