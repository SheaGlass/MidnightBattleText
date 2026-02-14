-------------------------------------------------------------------------------
-- MidnightBattleText - Config
-- Slash command interface for settings
-- Copyright (c) 2026 Shea (iTek). All Rights Reserved.
-------------------------------------------------------------------------------

local ADDON_NAME, MBT = ...

-------------------------------------------------------------------------------
-- Slash command: /mbt
-------------------------------------------------------------------------------

SLASH_MIDNIGHTBATTLETEXT1 = "/mbt"
SLASH_MIDNIGHTBATTLETEXT2 = "/midnightbattletext"

local function PrintHelp()
    local lines = {
        "|cff00ccffMidnightBattleText|r commands:",
        "  /mbt |cff88ff88config|r - Open visual settings editor",
        "  /mbt |cff88ff88toggle|r - Enable/disable the addon",
        "  /mbt |cff88ff88fonts|r - List available fonts",
        "  /mbt |cff88ff88font <name>|r - Set font by name (use /mbt fonts to list)",
        "  /mbt |cff88ff88fontsize <size>|r - Set font size (default: 24)",
        "  /mbt |cff88ff88duration <sec>|r - Scroll duration (default: 1.5)",
        "  /mbt |cff88ff88height <px>|r - Scroll distance (default: 120)",
        "  /mbt |cff88ff88direction <up|down|left|right|fountain>|r - Scroll direction",
        "  /mbt |cff88ff88move|r - Unlock anchor for dragging",
        "  /mbt |cff88ff88lock|r - Lock anchor and save position",
        "  /mbt |cff88ff88offsetx <incoming|outgoing> <px>|r - Column X offset",
        "  /mbt |cff88ff88threshold <n>|r - Hide hits below n (0 = show all)",
        "  /mbt |cff88ff88incoming|r - Toggle incoming damage",
        "  /mbt |cff88ff88outgoing|r - Toggle outgoing damage",
        "  /mbt |cff88ff88heals|r - Toggle healing",
        "  /mbt |cff88ff88misses|r - Toggle misses",
        "  /mbt |cff88ff88pet|r - Toggle pet damage",
        "  /mbt |cff88ff88blizzfct|r - Toggle Blizzard's floating combat text",
        "  /mbt |cff88ff88nameplate|r - Toggle nameplate-anchored outgoing text",
        "  /mbt |cff88ff88crits|r - Toggle crit emphasis",
        "  /mbt |cff88ff88critscale <n>|r - Crit font multiplier (default: 1.5)",
        "  /mbt |cff88ff88onlycrits|r - Only show critical hits",
        "  /mbt |cff88ff88abbreviate|r - Toggle number abbreviation (1.5k, 2.3M)",
        "  /mbt |cff88ff88healprefix|r - Toggle '+' prefix on heals",
        "  /mbt |cff88ff88icons|r - Toggle spell icons",
        "  /mbt |cff88ff88shadow|r - Toggle font shadow",
        "  /mbt |cff88ff88classcolor|r - Toggle class-colored outgoing damage",
        "  /mbt |cff88ff88alpha <0.3-1.0>|r - Set text opacity",
        "  /mbt |cff88ff88gap <0-30>|r - Set stacking gap between texts",
        "  /mbt |cff88ff88color <type> <hex>|r - Set color (damage|heal|miss|critdamage|critheal)",
        "  /mbt |cff88ff88profile save <name>|r - Save current settings as a profile",
        "  /mbt |cff88ff88profile load <name>|r - Load a saved profile",
        "  /mbt |cff88ff88profile delete <name>|r - Delete a saved profile",
        "  /mbt |cff88ff88profile list|r - List saved profiles",
        "  /mbt |cff88ff88test|r - Show test text (includes crits)",
        "  /mbt |cff88ff88debug|r - Toggle debug output (event tracing)",
        "  /mbt |cff88ff88reset|r - Reset all settings to defaults",
    }
    for _, line in ipairs(lines) do
        print(line)
    end
end

local function Toggle(db, key, label)
    db[key] = not db[key]
    local state = db[key] and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    print("|cff00ccffMBT|r: " .. label .. " " .. state)
end

SlashCmdList["MIDNIGHTBATTLETEXT"] = function(msg)
    local db = MBT.db
    if not db then return end

    local cmd, arg = msg:match("^(%S+)%s*(.*)")
    cmd = cmd and cmd:lower() or ""

    if cmd == "config" or cmd == "options" or cmd == "editor" then
        MBT:ToggleEditor()

    elseif cmd == "toggle" then
        Toggle(db, "enabled", "Addon")

    elseif cmd == "fonts" then
        print("|cff00ccffMBT|r: Available fonts:")
        for _, name in ipairs(MBT.FONT_NAMES) do
            local marker = (MBT.FONTS[name] == db.font) and " |cff00ff00(active)|r" or ""
            print("  |cffffd700" .. name .. "|r" .. marker)
        end

    elseif cmd == "font" then
        if arg == "" then
            print("|cff00ccffMBT|r: Usage: /mbt font <name> (use /mbt fonts to list)")
            return
        end
        -- Case-insensitive match
        local argLower = arg:lower()
        local matched
        for name, path in pairs(MBT.FONTS) do
            if name:lower() == argLower then
                matched = { name = name, path = path }
                break
            end
        end
        if matched then
            db.font = matched.path
            print("|cff00ccffMBT|r: Font set to |cffffd700" .. matched.name .. "|r")
        else
            print("|cff00ccffMBT|r: Unknown font '" .. arg .. "'. Use /mbt fonts to list.")
        end

    elseif cmd == "fontsize" then
        local size = tonumber(arg)
        if size and size >= 8 and size <= 72 then
            db.fontSize = size
            print("|cff00ccffMBT|r: Font size set to " .. size)
        else
            print("|cff00ccffMBT|r: Usage: /mbt fontsize <8-72>")
        end

    elseif cmd == "duration" then
        local dur = tonumber(arg)
        if dur and dur >= 0.5 and dur <= 5 then
            db.scrollDuration = dur
            print("|cff00ccffMBT|r: Scroll duration set to " .. dur .. "s")
        else
            print("|cff00ccffMBT|r: Usage: /mbt duration <0.5-5>")
        end

    elseif cmd == "height" then
        local h = tonumber(arg)
        if h and h >= 20 and h <= 500 then
            db.scrollHeight = h
            print("|cff00ccffMBT|r: Scroll height set to " .. h .. "px")
        else
            print("|cff00ccffMBT|r: Usage: /mbt height <20-500>")
        end

    elseif cmd == "direction" then
        local dir = arg:lower()
        if dir == "up" or dir == "down" or dir == "left" or dir == "right" or dir == "fountain" then
            db.scrollDirection = dir
            print("|cff00ccffMBT|r: Scroll direction set to |cffffd700" .. dir .. "|r")
        else
            print("|cff00ccffMBT|r: Usage: /mbt direction <up|down|left|right>")
        end

    elseif cmd == "move" then
        MBT:MoveAnchor()

    elseif cmd == "lock" then
        MBT:LockAnchor()

    elseif cmd == "offsetx" then
        local col, px = arg:match("^(%S+)%s+([%d%-]+)")
        col = col and col:lower()
        px = tonumber(px)
        if col == "incoming" and px then
            db.incomingOffsetX = px
            print("|cff00ccffMBT|r: Incoming X offset set to " .. px)
        elseif col == "outgoing" and px then
            db.outgoingOffsetX = px
            print("|cff00ccffMBT|r: Outgoing X offset set to " .. px)
        else
            print("|cff00ccffMBT|r: Usage: /mbt offsetx <incoming|outgoing> <px>")
        end

    elseif cmd == "threshold" then
        local t = tonumber(arg)
        if t and t >= 0 then
            db.filterThreshold = t
            if t == 0 then
                print("|cff00ccffMBT|r: Threshold filter disabled (showing all)")
            else
                print("|cff00ccffMBT|r: Hiding hits below " .. t)
            end
        else
            print("|cff00ccffMBT|r: Usage: /mbt threshold <number>")
        end

    elseif cmd == "incoming" then
        Toggle(db, "showIncomingDamage", "Incoming damage")

    elseif cmd == "outgoing" then
        Toggle(db, "showOutgoingDamage", "Outgoing damage")

    elseif cmd == "heals" then
        db.showIncomingHeals = not db.showIncomingHeals
        db.showOutgoingHeals = db.showIncomingHeals
        local state = db.showIncomingHeals and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        print("|cff00ccffMBT|r: Healing " .. state)

    elseif cmd == "misses" then
        Toggle(db, "showMisses", "Misses")

    elseif cmd == "pet" then
        Toggle(db, "showPetDamage", "Pet damage")

    elseif cmd == "blizzfct" then
        Toggle(db, "hideBlizzardFCT", "Hide Blizzard FCT")
        MBT:UpdateBlizzardFCT()

    elseif cmd == "nameplate" then
        Toggle(db, "nameplateMode", "Nameplate mode")

    elseif cmd == "crits" then
        Toggle(db, "showCrits", "Crit emphasis")

    elseif cmd == "critscale" then
        local s = tonumber(arg)
        if s and s >= 1.0 and s <= 3.0 then
            db.critScale = s
            print("|cff00ccffMBT|r: Crit scale set to " .. s .. "x")
        else
            print("|cff00ccffMBT|r: Usage: /mbt critscale <1.0-3.0>")
        end

    elseif cmd == "onlycrits" then
        Toggle(db, "showOnlyCrits", "Only show crits")

    elseif cmd == "abbreviate" then
        Toggle(db, "abbreviateNumbers", "Number abbreviation")

    elseif cmd == "healprefix" then
        Toggle(db, "showHealPrefix", "Heal '+' prefix")

    elseif cmd == "icons" then
        Toggle(db, "showIcons", "Spell icons")

    elseif cmd == "shadow" then
        Toggle(db, "fontShadow", "Font shadow")

    elseif cmd == "classcolor" then
        Toggle(db, "useClassColors", "Class colors")

    elseif cmd == "alpha" then
        local a = tonumber(arg)
        if a and a >= 0.3 and a <= 1.0 then
            db.textAlpha = a
            print("|cff00ccffMBT|r: Text alpha set to " .. a)
        else
            print("|cff00ccffMBT|r: Usage: /mbt alpha <0.3-1.0>")
        end

    elseif cmd == "gap" then
        local g = tonumber(arg)
        if g and g >= 0 and g <= 30 then
            db.stackingGap = g
            print("|cff00ccffMBT|r: Stacking gap set to " .. g)
        else
            print("|cff00ccffMBT|r: Usage: /mbt gap <0-30>")
        end

    elseif cmd == "color" then
        local ctype, hex = arg:match("^(%S+)%s+(%x%x%x%x%x%x)")
        if ctype and hex then
            local r = tonumber(hex:sub(1,2), 16) / 255
            local g = tonumber(hex:sub(3,4), 16) / 255
            local b = tonumber(hex:sub(5,6), 16) / 255
            local keyMap = {
                damage = "damageColor",
                heal = "healColor",
                miss = "missColor",
                critdamage = "critDamageColor",
                critheal = "critHealColor",
            }
            local dbKey = keyMap[ctype:lower()]
            if dbKey then
                db[dbKey] = {r, g, b}
                print("|cff00ccffMBT|r: " .. ctype .. " color set to #" .. hex)
            else
                print("|cff00ccffMBT|r: Unknown color type. Use: damage, heal, miss, critdamage, critheal")
            end
        else
            print("|cff00ccffMBT|r: Usage: /mbt color <type> <hex> (e.g. /mbt color damage ff3333)")
        end

    elseif cmd == "profile" then
        local sub, pname = arg:match("^(%S+)%s*(.*)")
        sub = sub and sub:lower() or ""
        if sub == "save" and pname ~= "" then
            if MBT:SaveProfile(pname) then
                print("|cff00ccffMBT|r: Profile |cffffd700" .. pname .. "|r saved.")
            end
        elseif sub == "load" and pname ~= "" then
            if MBT:LoadProfile(pname) then
                print("|cff00ccffMBT|r: Profile |cffffd700" .. pname .. "|r loaded. Reload UI for full effect.")
            else
                print("|cff00ccffMBT|r: Profile '" .. pname .. "' not found.")
            end
        elseif sub == "delete" and pname ~= "" then
            if MBT:DeleteProfile(pname) then
                print("|cff00ccffMBT|r: Profile |cffffd700" .. pname .. "|r deleted.")
            else
                print("|cff00ccffMBT|r: Profile '" .. pname .. "' not found.")
            end
        elseif sub == "list" then
            local names = MBT:GetProfileNames()
            if #names == 0 then
                print("|cff00ccffMBT|r: No saved profiles.")
            else
                print("|cff00ccffMBT|r: Saved profiles:")
                for _, n in ipairs(names) do
                    print("  |cffffd700" .. n .. "|r")
                end
            end
        else
            print("|cff00ccffMBT|r: Usage: /mbt profile <save|load|delete|list> [name]")
        end

    elseif cmd == "test" then
        print("|cff00ccffMBT|r: Showing test text...")
        MBT:DisplayScrollText(12345, "damage", "incoming", nil, false)
        MBT:DisplayScrollText(8765,  "damage", "outgoing", nil, false)
        MBT:DisplayScrollText(54321, "damage", "outgoing", nil, true)  -- crit!
        MBT:DisplayScrollText(5432,  "heal",   "incoming", nil, false)
        MBT:DisplayScrollText(19876, "heal",   "incoming", nil, true)  -- crit heal!
        MBT:DisplayScrollText("DODGE", "miss", "incoming", nil, false)

    elseif cmd == "debug" then
        Toggle(db, "debug", "Debug mode")

    elseif cmd == "reset" then
        wipe(MidnightBattleTextDB)
        print("|cff00ccffMBT|r: Settings reset to defaults. Reload UI to apply.")

    else
        PrintHelp()
    end
end
