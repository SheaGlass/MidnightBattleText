-------------------------------------------------------------------------------
-- MidnightBattleText - Core
-- Scrolling battle text built for WoW Midnight (12.0) Secret Values API
--
-- Event sources:
--   1. UNIT_COMBAT (via RegisterUnitEvent) — incoming + outgoing damage/heals
--   2. COMBAT_TEXT_UPDATE — fallback for incoming if available
--   3. CLEU as a pcall-wrapped fallback for outgoing when accessible
--
-- Copyright (c) 2026 Shea (iTek). All Rights Reserved.
-------------------------------------------------------------------------------

local ADDON_NAME, MBT = ...

-------------------------------------------------------------------------------
-- Bundled font table: name -> path (relative to Interface\AddOns)
-------------------------------------------------------------------------------

local FONT_DIR = "Interface\\AddOns\\MidnightBattleText\\Fonts\\"

MBT.FONTS = {
    ["Default"]            = "Fonts\\FRIZQT__.TTF",
    ["A Another Tag"]      = FONT_DIR .. "aAnotherTag.ttf",
    ["Black Bones"]        = FONT_DIR .. "Black Bones Personal Use Only.ttf",
    ["Cheri"]              = FONT_DIR .. "CHERI___.TTF",
    ["Creato Display"]     = FONT_DIR .. "CreatoDisplay-Regular.otf",
    ["Creato Display Bold"]= FONT_DIR .. "CreatoDisplay-Bold.otf",
    ["Lemon Milk"]         = FONT_DIR .. "LEMONMILK-Regular.otf",
    ["Lemon Milk Bold"]    = FONT_DIR .. "LEMONMILK-Bold.otf",
    ["Nunuk"]              = FONT_DIR .. "nunuk.ttf",
    ["Pastel Trunk"]       = FONT_DIR .. "PastelTrunk-Regular.otf",
    ["Road Rage"]          = FONT_DIR .. "Road_Rage.otf",
    ["Sanseriffic"]        = FONT_DIR .. "Sanseriffic.otf",
    ["Skyforge"]           = FONT_DIR .. "Skyforge PERSONAL USE ONLY!.ttf",
    ["Square"]             = FONT_DIR .. "Square.ttf",
    ["Urban Heroes"]       = FONT_DIR .. "Urban Heroes.ttf",
    -- New fonts
    ["Boston Traffic"]     = FONT_DIR .. "Boston Traffic.ttf",
    ["Breathe Fire V"]     = FONT_DIR .. "Breathe Fire V.otf",
    ["Consola Mono"]       = FONT_DIR .. "ConsolaMono-Book.ttf",
    ["Consola Mono Bold"]  = FONT_DIR .. "ConsolaMono-Bold.ttf",
    ["Cream Cake"]         = FONT_DIR .. "Cream Cake.otf",
    ["Cream Cake Bold"]    = FONT_DIR .. "Cream Cake Bold.otf",
    ["Creativo"]           = FONT_DIR .. "Creativo Regular.otf",
    ["Fast Hand"]          = FONT_DIR .. "Fast Hand.otf",
    ["Greek Freak"]        = FONT_DIR .. "Greek-Freak.ttf",
    ["Hoshiko Satsuki"]    = FONT_DIR .. "Hoshiko Satsuki.ttf",
    ["Hunters K-Pop"]      = FONT_DIR .. "Hunters K-Pop.otf",
    ["Japanese 3017"]      = FONT_DIR .. "Japanese 3017.otf",
    ["KG Perfect Penmanship"] = FONT_DIR .. "KGPerfectPenmanship.otf",
    ["Revamped"]           = FONT_DIR .. "Revamped.otf",
    ["Robot Crush"]        = FONT_DIR .. "Robot Crush.otf",
    ["Roman SD"]           = FONT_DIR .. "Roman SD.ttf",
}

-- Sorted name list for the /mbt fonts command
MBT.FONT_NAMES = {}
for name in pairs(MBT.FONTS) do
    table.insert(MBT.FONT_NAMES, name)
end
table.sort(MBT.FONT_NAMES)

-------------------------------------------------------------------------------
-- Saved variables defaults
-------------------------------------------------------------------------------

local DEFAULTS = {
    enabled = true,
    -- Display
    font = "Fonts\\FRIZQT__.TTF",
    fontSize = 24,
    fontFlags = "OUTLINE",
    iconSize = 16,
    iconOffsetX = -4,
    iconOffsetY = 0,
    iconBorder = true,
    iconBorderColor = {0, 0, 0},
    iconBorderSize = 1,
    iconDesaturate = false,
    iconRound = false,
    iconAlpha = 1.0,
    iconAnchor = "LEFT",  -- which side of the text: "LEFT" or "RIGHT"
    scrollHeight = 120,
    scrollDuration = 1.5,
    fadeStart = 0.7,
    scrollDirection = "up",
    -- Anchor position
    anchorPoint = "CENTER",
    anchorRelPoint = "CENTER",
    anchorX = 0,
    anchorY = 100,
    -- Columns
    incomingOffsetX = -200,
    outgoingOffsetX = 200,
    offsetY = 0,
    -- Crits
    critScale = 1.5,
    showCrits = true,
    showOnlyCrits = false,
    -- Text options
    abbreviateNumbers = false,
    showHealPrefix = true,
    showIcons = true,
    textAlpha = 1.0,
    stackingGap = 6,
    fontShadow = false,
    -- Colors
    damageColor     = {1.0, 0.2, 0.2},
    healColor       = {0.2, 1.0, 0.2},
    missColor       = {0.7, 0.7, 0.7},
    critDamageColor = {1.0, 0.8, 0.0},
    critHealColor   = {0.4, 1.0, 0.6},
    useClassColors  = false,
    -- Filters
    filterThreshold = 0,
    -- Event toggles
    showIncomingDamage = true,
    showIncomingHeals = true,
    showOutgoingDamage = true,
    showOutgoingHeals = true,
    showMisses = true,
    showPetDamage = true,
    -- Blizzard FCT
    hideBlizzardFCT = true,
    -- Nameplate mode
    nameplateMode = false,
    nameplateOffsetY = 20,
    -- Source filtering
    onlyPlayerDamage = true,
    -- Debug
    debug = false,
}

-------------------------------------------------------------------------------
-- Profile system
-- Profiles stored in MidnightBattleTextDB._profiles = { ["name"] = {settings} }
-------------------------------------------------------------------------------

-- Keys to save/restore in profiles (everything except internal state)
local PROFILE_KEYS = {
    "enabled", "font", "fontSize", "fontFlags",
    "iconSize", "iconOffsetX", "iconOffsetY",
    "iconBorder", "iconBorderColor", "iconBorderSize",
    "iconDesaturate", "iconRound", "iconAlpha", "iconAnchor",
    "scrollHeight", "scrollDuration", "fadeStart", "scrollDirection",
    "anchorPoint", "anchorRelPoint", "anchorX", "anchorY",
    "incomingOffsetX", "outgoingOffsetX", "offsetY",
    "critScale", "showCrits", "showOnlyCrits",
    "abbreviateNumbers", "showHealPrefix", "showIcons",
    "textAlpha", "stackingGap", "fontShadow",
    "damageColor", "healColor", "missColor", "critDamageColor", "critHealColor",
    "useClassColors",
    "filterThreshold",
    "showIncomingDamage", "showIncomingHeals", "showOutgoingDamage", "showOutgoingHeals",
    "showMisses", "showPetDamage", "onlyPlayerDamage",
    "hideBlizzardFCT", "nameplateMode", "nameplateOffsetY",
}

function MBT:SaveProfile(name)
    if not name or name == "" then return false end
    local db = self.db
    if not MidnightBattleTextDB._profiles then
        MidnightBattleTextDB._profiles = {}
    end
    local profile = {}
    for _, key in ipairs(PROFILE_KEYS) do
        local val = db[key]
        if type(val) == "table" then
            profile[key] = {val[1], val[2], val[3]}
        else
            profile[key] = val
        end
    end
    MidnightBattleTextDB._profiles[name] = profile
    return true
end

function MBT:LoadProfile(name)
    if not name or name == "" then return false end
    local profiles = MidnightBattleTextDB._profiles
    if not profiles or not profiles[name] then return false end
    local profile = profiles[name]
    local db = self.db
    for _, key in ipairs(PROFILE_KEYS) do
        if profile[key] ~= nil then
            local val = profile[key]
            if type(val) == "table" then
                db[key] = {val[1], val[2], val[3]}
            else
                db[key] = val
            end
        end
    end
    return true
end

function MBT:DeleteProfile(name)
    if not name or name == "" then return false end
    local profiles = MidnightBattleTextDB._profiles
    if not profiles or not profiles[name] then return false end
    profiles[name] = nil
    return true
end

function MBT:GetProfileNames()
    local names = {}
    local profiles = MidnightBattleTextDB and MidnightBattleTextDB._profiles
    if profiles then
        for name in pairs(profiles) do
            table.insert(names, name)
        end
        table.sort(names)
    end
    return names
end

-------------------------------------------------------------------------------
-- Secret Values helpers
-------------------------------------------------------------------------------

local function IsRestricted()
    if not C_RestrictedActions or not C_RestrictedActions.IsAddOnRestrictionActive then
        return false
    end
    local ok, result = pcall(C_RestrictedActions.IsAddOnRestrictionActive, 0)
    return ok and result or false
end

local function CanAccess(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true
end

local function IsSecret(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

local function DebugPrint(...)
    if MBT.db and MBT.db.debug then
        print("|cff888888MBT Debug:|r", ...)
    end
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

MBT.restricted = false

local playerGUID
local petGUID
local eventFrame = CreateFrame("Frame")
local hasUnitCombat = false  -- track whether UNIT_COMBAT registration worked

-------------------------------------------------------------------------------
-- Spell tracking for icons
-- UNIT_COMBAT doesn't provide spellId, so we capture the last spell cast
-- via UNIT_SPELLCAST_SUCCEEDED and use it for outgoing damage/heal display.
-------------------------------------------------------------------------------

local lastPlayerSpellId = nil
local lastPlayerSpellTime = 0
local lastPetSpellId = nil
local lastPetSpellTime = 0
local SPELL_TRACK_WINDOW = 1.5  -- seconds to associate a spell with combat

local spellTrackFrame = CreateFrame("Frame")
pcall(function()
    spellTrackFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
end)
spellTrackFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellId)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
    local now = GetTime()
    if unit == "player" then
        lastPlayerSpellId = spellId
        lastPlayerSpellTime = now
    elseif unit == "pet" then
        lastPetSpellId = spellId
        lastPetSpellTime = now
    end
end)

local function GetLastPlayerSpellId()
    if lastPlayerSpellId and (GetTime() - lastPlayerSpellTime) <= SPELL_TRACK_WINDOW then
        return lastPlayerSpellId
    end
    return nil
end

local function GetLastPetSpellId()
    if lastPetSpellId and (GetTime() - lastPetSpellTime) <= SPELL_TRACK_WINDOW then
        return lastPetSpellId
    end
    return nil
end

-------------------------------------------------------------------------------
-- Dedup: CLEU and UNIT_COMBAT both fire for outgoing damage/heals.
-- We prefer CLEU (has spellId for icons). Track recent CLEU events so
-- UNIT_COMBAT can skip duplicates.
-------------------------------------------------------------------------------

local recentCLEU = {}        -- { [amount..category..time] = true }
local DEDUP_WINDOW = 0.15    -- 150ms window for same-frame events

local function MarkCLEUEvent(amount, category)
    local key = tostring(amount) .. category
    recentCLEU[key] = GetTime()
end

local function IsDuplicateOfCLEU(amount, category)
    local key = tostring(amount) .. category
    local t = recentCLEU[key]
    if t and (GetTime() - t) <= DEDUP_WINDOW then
        recentCLEU[key] = nil
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- UNIT_COMBAT handler
-- Args: unitTarget, event, flagText, amount, schoolMask
-- event: "WOUND" (damage), "HEAL", "BLOCK", "DODGE", "PARRY", "MISS", etc.
-- flagText: "CRITICAL", "CRUSHING", "GLANCING", or ""
-------------------------------------------------------------------------------

local UC_MISS = {
    BLOCK = true, DODGE = true, PARRY = true, MISS = true,
    IMMUNE = true, DEFLECT = true, REFLECT = true,
    RESIST = true, ABSORB = true, EVADE = true,
}

local function OnUnitCombat(unit, action, flagText, amount, schoolMask)
    local db = MBT.db
    if not db or not db.enabled then return end

    DebugPrint("UNIT_COMBAT:", unit, action, flagText, amount)

    local isCrit = (flagText == "CRITICAL")

    -- Incoming: damage/heals/misses on the player
    if unit == "player" then
        if action == "WOUND" then
            if db.showIncomingDamage then
                MBT:ShowText(amount, "damage", "incoming", nil, isCrit)
            end
        elseif action == "HEAL" then
            if db.showIncomingHeals then
                MBT:ShowText(amount, "heal", "incoming", nil, isCrit)
            end
        elseif UC_MISS[action] then
            if db.showMisses then
                MBT:ShowText(action, "miss", "incoming", nil, false)
            end
        end
        return
    end

    -- Outgoing: damage/heals/misses on our target
    -- When onlyPlayerDamage is true, skip UNIT_COMBAT for outgoing damage/heals
    -- entirely — CLEU handles those with proper source filtering + spell icons.
    -- UNIT_COMBAT for "target" fires for ALL damage on the target (any source),
    -- so it would show other players' damage as yours.
    if unit == "target" then
        if not db.onlyPlayerDamage then
            local destGUID = UnitGUID("target")
            if action == "WOUND" then
                if db.showOutgoingDamage and not IsDuplicateOfCLEU(amount, "damage") then
                    MBT:ShowText(amount, "damage", "outgoing", GetLastPlayerSpellId(), isCrit, destGUID)
                end
            elseif action == "HEAL" then
                if db.showOutgoingHeals and not IsDuplicateOfCLEU(amount, "heal") then
                    MBT:ShowText(amount, "heal", "outgoing", GetLastPlayerSpellId(), isCrit, destGUID)
                end
            end
        end
        -- Always handle misses from UNIT_COMBAT (CLEU also handles them, dedup isn't needed for text misses)
        if UC_MISS[action] then
            if db.showMisses then
                local destGUID = UnitGUID("target")
                MBT:ShowText(action, "miss", "outgoing", nil, false, destGUID)
            end
        end
        return
    end

    -- Pet damage — skip if onlyPlayerDamage and CLEU already handles it
    if unit == "pet" then
        if not db.onlyPlayerDamage then
            if action == "WOUND" and db.showPetDamage and not IsDuplicateOfCLEU(amount, "damage") then
                MBT:ShowText(amount, "damage", "outgoing", GetLastPetSpellId(), isCrit)
            end
        end
        return
    end
end

-------------------------------------------------------------------------------
-- COMBAT_TEXT_UPDATE handler (fallback for incoming if UNIT_COMBAT fails)
-------------------------------------------------------------------------------

local CT_DAMAGE = {
    DAMAGE = true, DAMAGE_CRIT = true,
    SPELL_DAMAGE = true, SPELL_DAMAGE_CRIT = true,
    DAMAGE_SHIELD = true,
    SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_DAMAGE_CRIT = true,
}
local CT_DAMAGE_CRIT = {
    DAMAGE_CRIT = true, SPELL_DAMAGE_CRIT = true,
    SPELL_PERIODIC_DAMAGE_CRIT = true,
}
local CT_HEAL = {
    HEAL = true, HEAL_CRIT = true,
    PERIODIC_HEAL = true, PERIODIC_HEAL_CRIT = true,
    SPELL_HEAL = true, SPELL_HEAL_CRIT = true,
}
local CT_HEAL_CRIT = {
    HEAL_CRIT = true, PERIODIC_HEAL_CRIT = true, SPELL_HEAL_CRIT = true,
}
local CT_MISS = {
    MISS = true, DODGE = true, PARRY = true, BLOCK = true,
    RESIST = true, ABSORB = true, IMMUNE = true,
    DEFLECT = true, REFLECT = true, EVADE = true,
}

local function OnCombatTextUpdate(textType)
    -- Skip if UNIT_COMBAT is handling incoming already
    if hasUnitCombat then return end

    local db = MBT.db
    if not db or not db.enabled then return end

    DebugPrint("COMBAT_TEXT_UPDATE:", textType)

    if CT_DAMAGE[textType] then
        if db.showIncomingDamage then
            local amount = GetCurrentCombatTextEventInfo()
            MBT:ShowText(amount, "damage", "incoming", nil, CT_DAMAGE_CRIT[textType] or false)
        end
    elseif CT_HEAL[textType] then
        if db.showIncomingHeals then
            local _, amount = GetCurrentCombatTextEventInfo()
            MBT:ShowText(amount, "heal", "incoming", nil, CT_HEAL_CRIT[textType] or false)
        end
    elseif CT_MISS[textType] then
        if db.showMisses then
            MBT:ShowText(textType, "miss", "incoming", nil, false)
        end
    end
end

-------------------------------------------------------------------------------
-- CLEU handler (pcall-wrapped fallback for outgoing)
-------------------------------------------------------------------------------

local CLEU_DAMAGE = {
    SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true,
}
local CLEU_HEAL = {
    SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true,
}
local CLEU_MISS = {
    SWING_MISSED = true, RANGE_MISSED = true, SPELL_MISSED = true,
}

local function TryParseCLEU()
    local db = MBT.db
    if not db or not db.enabled then return end

    local ok, err = pcall(function()
        local timestamp, subEvent, hideCaster,
              sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
              destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

        local isPlayerSource = (sourceGUID == playerGUID)
        local isPetSource    = (sourceGUID == petGUID)
        if not isPlayerSource and not isPetSource then return end

        local isPlayerDest = (destGUID == playerGUID)

        if CLEU_DAMAGE[subEvent] then
            local amount, spellId, critical
            if subEvent == "SWING_DAMAGE" then
                amount   = select(12, CombatLogGetCurrentEventInfo())
                critical = select(18, CombatLogGetCurrentEventInfo())
            else
                spellId  = select(12, CombatLogGetCurrentEventInfo())
                amount   = select(15, CombatLogGetCurrentEventInfo())
                critical = select(21, CombatLogGetCurrentEventInfo())
            end

            local isCrit = false
            if critical ~= nil then
                local cOk, cVal = pcall(function() return critical == true end)
                isCrit = cOk and cVal or false
            end

            if isPlayerSource and db.showOutgoingDamage then
                MarkCLEUEvent(amount, "damage")
                MBT:ShowText(amount, "damage", "outgoing", spellId, isCrit, destGUID)
            elseif isPetSource and db.showPetDamage then
                MarkCLEUEvent(amount, "damage")
                MBT:ShowText(amount, "damage", "outgoing", spellId, isCrit, destGUID)
            end
            return
        end

        if CLEU_HEAL[subEvent] and isPlayerSource and not isPlayerDest then
            if db.showOutgoingHeals then
                local spellId  = select(12, CombatLogGetCurrentEventInfo())
                local amount   = select(15, CombatLogGetCurrentEventInfo())
                local critical = select(18, CombatLogGetCurrentEventInfo())
                local isCrit = false
                if critical ~= nil then
                    local cOk, cVal = pcall(function() return critical == true end)
                    isCrit = cOk and cVal or false
                end
                MarkCLEUEvent(amount, "heal")
                MBT:ShowText(amount, "heal", "outgoing", spellId, isCrit, destGUID)
            end
            return
        end

        if CLEU_MISS[subEvent] and isPlayerSource then
            if db.showMisses then
                local missType
                if subEvent == "SWING_MISSED" then
                    missType = select(12, CombatLogGetCurrentEventInfo())
                else
                    missType = select(15, CombatLogGetCurrentEventInfo())
                end
                MBT:ShowText(missType, "miss", "outgoing", nil, false, destGUID)
            end
            return
        end
    end)

    if not ok then
        DebugPrint("CLEU parse error:", err)
    end
end

-------------------------------------------------------------------------------
-- ShowText - bridge to Display module
-------------------------------------------------------------------------------

function MBT:ShowText(amount, category, column, spellId, isCrit, destGUID)
    local db = self.db

    -- Only show crits filter
    if db.showOnlyCrits and category ~= "miss" and not isCrit then
        return
    end

    if category ~= "miss" and db.filterThreshold > 0 then
        if CanAccess(amount) and not IsSecret(amount) then
            local ok, passes = pcall(function() return amount >= db.filterThreshold end)
            if ok and not passes then return end
        end
    end

    -- Debug: log spellId availability for icon troubleshooting
    if db.debug and column == "outgoing" and category ~= "miss" then
        local idStr = "nil"
        if spellId then
            local ok, s = pcall(tostring, spellId)
            idStr = ok and s or "secret"
        end
        DebugPrint("ShowText outgoing:", category, "spellId=" .. idStr)
    end

    MBT:DisplayScrollText(amount, category, column, spellId, isCrit, destGUID)
end

-------------------------------------------------------------------------------
-- Nameplate lookup
-------------------------------------------------------------------------------

function MBT:GetNameplateByGUID(guid)
    if not guid then return nil end

    -- Try the efficient per-unit lookup first: iterate visible nameplates
    local ok, result = pcall(function()
        local plates = C_NamePlate.GetNamePlates()
        if not plates then return nil end
        for _, plate in ipairs(plates) do
            -- namePlateUnitToken is the standard WoW property on NamePlateFrame
            local unitToken = plate.namePlateUnitToken
            if unitToken and UnitGUID(unitToken) == guid then
                return plate
            end
        end
        return nil
    end)

    if ok and result then return result end

    -- Fallback: try GetNamePlateForUnit with common unit IDs
    local fallbackUnits = {"target", "focus", "mouseover",
        "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5",
        "nameplate6", "nameplate7", "nameplate8", "nameplate9", "nameplate10",
        "nameplate11", "nameplate12", "nameplate13", "nameplate14", "nameplate15",
        "nameplate16", "nameplate17", "nameplate18", "nameplate19", "nameplate20",
        "nameplate21", "nameplate22", "nameplate23", "nameplate24", "nameplate25",
        "nameplate26", "nameplate27", "nameplate28", "nameplate29", "nameplate30",
        "nameplate31", "nameplate32", "nameplate33", "nameplate34", "nameplate35",
        "nameplate36", "nameplate37", "nameplate38", "nameplate39", "nameplate40",
    }
    for _, unit in ipairs(fallbackUnits) do
        local unitOk, unitGUID = pcall(UnitGUID, unit)
        if unitOk and unitGUID == guid then
            local plateOk, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
            if plateOk and plate then
                return plate
            end
        end
    end

    return nil
end

-------------------------------------------------------------------------------
-- Settings panel (Options > AddOns > MidnightBattleText)
-------------------------------------------------------------------------------

function MBT:RegisterSettings()
    local panel = CreateFrame("Frame")
    panel.name = ADDON_NAME

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    info:SetPoint("TOPLEFT", 20, -20)
    info:SetText("|cff00ccffMidnightBattleText|r")

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -12)
    desc:SetText("Scrolling battle text for WoW Midnight (12.0)")

    -- Open Editor button (custom, no UIPanelButtonTemplate)
    local btn = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    btn:SetSize(200, 30)
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    btn:SetBackdropBorderColor(0, 0.7, 0.9, 1)
    btn:EnableMouse(true)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText("|cff00ccffOpen Settings Editor|r")

    btn:SetScript("OnMouseDown", function()
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        MBT:ToggleEditor()
    end)
    btn:SetScript("OnMouseUp", function()
        btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0.7, 0.9, 1)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    end)

    local usage = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    usage:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -16)
    usage:SetWidth(400)
    usage:SetJustifyH("LEFT")
    usage:SetText(
        "Or type |cff00ccff/mbt config|r to open the editor\n" ..
        "Type |cff00ccff/mbt|r for a list of all slash commands"
    )

    local category, layout = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
    Settings.RegisterAddOnCategory(category)
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

local function OnEvent(self, event, ...)
    if event == "UNIT_COMBAT" then
        OnUnitCombat(...)

    elseif event == "COMBAT_TEXT_UPDATE" then
        OnCombatTextUpdate(...)

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        TryParseCLEU()

    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        MBT.restricted = IsRestricted()

    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        petGUID = UnitGUID("pet")

        if not MidnightBattleTextDB then
            MidnightBattleTextDB = {}
        end
        MBT.db = setmetatable(MidnightBattleTextDB, { __index = DEFAULTS })

        -- Disable Blizzard's floating combat text CVars
        MBT:UpdateBlizzardFCT()

        MBT:InitDisplay()
        MBT:RegisterSettings()

        print("|cff00ccffMidnightBattleText|r loaded. Type |cff00ccff/mbt|r for options.")

    elseif event == "UNIT_PET" then
        local unit = ...
        if unit == "player" then
            petGUID = UnitGUID("pet")
        end
    end
end

-------------------------------------------------------------------------------
-- Blizzard FCT suppression via CVars
-- Sets all floating combat text CVars to 0, same as AdvancedInterfaceOptions.
-- Since we use UNIT_COMBAT (not COMBAT_TEXT_UPDATE), this is safe.
-------------------------------------------------------------------------------

local FCT_CVARS = {
    "enableFloatingCombatText",
    "floatingCombatTextCombatDamage",
    "floatingCombatTextCombatHealing",
    "floatingCombatTextCombatLogPeriodicSpells",
    "floatingCombatTextPetMeleeDamage",
    "floatingCombatTextPetSpellDamage",
    "floatingCombatTextFloatMode",
    "floatingCombatTextDodgeParryMiss",
    "floatingCombatTextDamageReduction",
    "floatingCombatTextAuras",
    "floatingCombatTextHonorGains",
    "floatingCombatTextEnergyGains",
    "floatingCombatTextPeriodicEnergyGains",
    "floatingCombatTextReactives",
    "floatingCombatTextFriendlyHealers",
    "floatingCombatTextComboPoints",
    "floatingCombatTextLowManaHealth",
    "floatingCombatTextRepChanges",
    "floatingCombatTextCombatState",
}

function MBT:UpdateBlizzardFCT()
    local hide = self.db and self.db.hideBlizzardFCT
    local val = hide and "0" or "1"
    for _, cvar in ipairs(FCT_CVARS) do
        pcall(SetCVar, cvar, val)
    end
    DebugPrint("Blizzard FCT CVars set to", val)
end

-- Register events safely — UNIT_COMBAT may be protected in some builds
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")

-- Try RegisterUnitEvent for UNIT_COMBAT (preferred for unit-specific events)
local ucOk = pcall(function()
    eventFrame:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
end)
if ucOk then
    hasUnitCombat = true
else
    -- Fallback: try regular RegisterEvent
    local ucOk2 = pcall(function()
        eventFrame:RegisterEvent("UNIT_COMBAT")
    end)
    if ucOk2 then
        hasUnitCombat = true
    end
end

-- COMBAT_TEXT_UPDATE as fallback (only used if UNIT_COMBAT failed)
if not hasUnitCombat then
    pcall(function()
        eventFrame:RegisterEvent("COMBAT_TEXT_UPDATE")
    end)
end

eventFrame:SetScript("OnEvent", OnEvent)

-- Re-register for target changes so UNIT_COMBAT tracks the new target
if hasUnitCombat then
    local targetFrame = CreateFrame("Frame")
    targetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetFrame:SetScript("OnEvent", function()
        pcall(function()
            eventFrame:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
        end)
    end)
end

-- Expose for other modules
MBT.IsRestricted = IsRestricted
MBT.CanAccess = CanAccess
MBT.IsSecret = IsSecret
