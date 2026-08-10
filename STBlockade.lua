-- ============================================================
-- Blockade MAIN: HUD + ESP + Auto-Buy / Auto-Heal
-- Авто-фарм живёт отдельно в blockade_farm.lua
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local ws = workspace
local rs = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

_G.__BC_MAIN_EPOCH = (_G.__BC_MAIN_EPOCH or 0) + 1
local myEpoch = _G.__BC_MAIN_EPOCH
local function alive() return myEpoch == _G.__BC_MAIN_EPOCH end
local running = true

if _G.blockade_main_reg then
    local reg = _G.blockade_main_reg
    if reg.conn then pcall(reg.conn.Disconnect, reg.conn) end
    if reg.stop then pcall(reg.stop) end
    for _, d in ipairs(reg.draws or {}) do pcall(function(x) x:Remove() end, d) end
    _G.blockade_main_reg = nil
end

UI.RemoveTab("Blockade Main")

local STATE_FILE = "blockade_main_state.txt"
local saved = {}
if isfile(STATE_FILE) then
    local ok, data = pcall(readfile, STATE_FILE)
    if ok and data then
        for line in (data .. "\n"):gmatch("(.-)\n") do
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                if v == "true" then saved[k] = true
                elseif v == "false" then saved[k] = false
                else
                    saved[k] = tonumber(v) or v
                end
            end
        end
    end
end

local objects = {}
local function new(t) local o = Drawing.new(t); table.insert(objects, o); return o end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local POOL = 40
local ITEM_POOL = 16
local mobsCache = {}
local itemsCache = {}

-- ============================================================
-- UI: вкладка "Blockade Main"
-- ============================================================

local MODES_IGNORE = nil

-- общие предметы (Weapons + Misc) и улучшения персонажей (Skills X)
local BUY_ITEMS = {
    "Jetpack", "HeadPhone", "Headphone", "Armor", "Rockets", "Machetes", "Knifes", "Grenade",
    "SpikesPlungers", "Jetpack Upgrade", "MoreGuns", "Speaker", "Upgrade", "RepairArms",
    "Titan-Request", "SpecialTitan-Request", "Speaker-Request", "Laser", "Cannon", "Lens", "Anti-Dose",
    "EPD", "RocketLauncher", "Large Laser Gun", "Stun-Baton", "Nail Gun",
    "Explosive Nail Gun", "Grenade Launcher", "Hand Drill", "Small Laser Gun",
    "Saw Blade", "Dual Barrel Blaster", "Tazer Sniper", "Tazer Gun", "Astro Blaster",
    "Stungun", "Flamethrower", "Harpoon Gun", "Shot Gun", "Pulse Rifle", "Shot Harpoon Gun"
}
local BUY_UPGRADES = {
    "Pulse Cannon", "Double Plungers", "Body Improvement", "Body Improvement II", "Knuckle", "Fist",
    "Rocket", "Copter", "Armor Upgrade", "Speaker Upgrade", "Sound Improvement",
    "OrbitalPrecisionStrike", "Eagle500kgBomb", "OrbitalLaser", "Spider", "UPGGundam", "Gundam",
    "Combat (Shield)", "Shield", "Wired Bat", "UpgradeKnife2", "UpgradeKnife1", "Knife",
    "Bats", "Combat (Bat)", "Bat", "Katanas", "Ground Slam",
    "Combat Skills (Shield)", "Enchated (Shield)", "Combat Skills (Laser)",
    "Laser Arm", "Repair Arm", "New Copter", "Spear n' knife", "Multi Task", "Guns",
    "Shield Drone", "Attacker Drone", "Blaster Tank", "Large Blaster Tank", "Healer Drone",
    "TV Strider", "Core", "Back Speaker", "Shoulder Speaker", "Core Upgrade", "Core Base Upgrade",
    "Extra Armor", "Armored", "Upgrade Blaster+", "Upgrade Blaster", "Trail",
    "Aerial Variant", "Hook", "Head Armor", "Armor 2", "Extra Speaker", "Crown",
    "Upgrade Cannon", "Upgraded Blaster", "Under Armor", "Upgrade Jetpack 2", "Upgrade Jetpack",
    "Claw", "Head Laser", "Backpack", "Body Upgrade", "Shoulder Plate",
    "Extra TV (Shoulder)", "Extra TV (Head)", "Finger Bomb", "Upgrade Shield", "Shoulder Cannon",
    "Core Armor", "Stun Gun", "Energy Boost", "Tazer Laser", "Energized Blaster",
    "Booster Jetpack", "Copter Upgrade", "TV Upgrade", "Parasite Head", "Blade", "Combat Body",
    "Back Blade", "Spinner", "Waist Core", "Energized", "Strikers", "Vanguard", "Blitzers",
    "Higher Output", "Lower Output", "Astro Laser", "Armor | 1", "Armor | 2"
}

-- достроить списки из открытого магазина (003-A): Weapons/Misc -> items, Skills * -> upgrades
do
    local pg = lp:FindFirstChild("PlayerGui")
    local hwa = pg and pg:FindFirstChild("003-A")
    if hwa then
        local known = {}
        for _, it in ipairs(BUY_ITEMS) do known[it] = true end
        local knownU = {}
        for _, it in ipairs(BUY_UPGRADES) do knownU[it] = true end
        local sc = hwa:FindFirstChild("Main") and hwa.Main:FindFirstChild("ScrollingFrame")
        if sc then
            for _, sf in ipairs(sc:GetChildren()) do
                if sf.ClassName == "ScrollingFrame" then
                    local isUpg = sf.Name:sub(1, 7) == "Skills "
                    local dst = isUpg and BUY_UPGRADES or BUY_ITEMS
                    local seen = isUpg and knownU or known
                    for _, f in ipairs(sf:GetChildren()) do
                        local nm = f.Name
                        if nm ~= "" and nm ~= "Unreadable_name" and nm ~= "UIGridLayout"
                           and nm ~= "UIListLayout" and not seen[nm] then
                            seen[nm] = true
                            dst[#dst + 1] = nm
                        end
                    end
                end
            end
        end
    end
    print("[main] items=" .. #BUY_ITEMS .. " upgrades=" .. #BUY_UPGRADES)
end

local cfgSave, cfgLoad, cfgDelete, cfgApply
local cfgList = {}
for _, f in pairs(listfiles("") or {}) do
    local bn = f:match("[^/\\]+$") or f
    local nm = bn:match("^cfg_(.+)%.txt$")
    if nm and nm ~= "" then cfgList[#cfgList + 1] = nm end
end
table.sort(cfgList)

UI.AddTab("Blockade Main", function(tab)
    local esp = tab:Section("ESP", "Left", {"Toilets", "Items"})
    if esp.page == 0 then
        esp:Toggle("esp_on", "ESP Enabled", true)
        esp:Toggle("esp_3d", "3D Hitbox (Torso + Fake Head)", false)
        esp:Toggle("esp_names", "Names + Distance", true)
        esp:Toggle("esp_hp", "HP Bars", true)
        esp:SliderInt("esp_dist", "Max Distance", 50, 3000, 3000)
        esp:Combo("esp_danger_mode", "ESP Filter", {"All", "Sign target only", "Danger list (S+/S/A)"}, 1)
        esp:Tip("All mobs with a Humanoid in Living")
    else
        esp:Toggle("esp_items", "Item ESP", true)
        esp:Toggle("esp_itemname", "Show Item Names", true)
        esp:SliderInt("esp_item_dist", "Item Max Distance", 50, 3000, 3000)
        esp:Tip("Flash Drive, Clock Spider, Keycard, cores, Astro parts...")
    end

    local buy = tab:Section("AutoBuy", "Right", {"AutoHeal", "Items", "Upgrades"})
    if buy.page == 0 then
        buy:Toggle("fr_heal", "[Hybrid] Auto Heal", true)
        buy:SliderInt("fr_healpct", "Heal below %", 10, 90, 40)
        buy:Tip("Buys FillHP while shop is open")
    elseif buy.page == 1 then
        buy:Toggle("fr_buy", "[Hybrid] Auto Buy", false)
        for _, it in ipairs(BUY_ITEMS) do
            buy:Toggle("buy_" .. it, it, false)
        end
        buy:Tip("Buys while the in-game shop is open")
    else
        buy:Toggle("fr_buyupg", "[Hybrid] Auto Buy Upgrades", false)
        for _, it in ipairs(BUY_UPGRADES) do
            buy:Toggle("buyu_" .. it, it, false)
        end
        buy:Tip("Character upgrades (Skills categories)")
    end

    local hud = tab:Section("HUD", "Left", {"HUD", "Warning"})
    if hud.page == 0 then
        hud:Toggle("hud_on", "HUD visible", true)
        hud:Toggle("hud_wave", "Show wave", true)
        hud:Toggle("hud_count", "Show toilet count", true)
        hud:Toggle("hud_list", "Show top-5 list by HP", true)
        hud:Tip("Right-side panel: wave, count, list")
    else
        hud:Toggle("sgn_on", "Danger warnings", true)
        hud:SliderInt("sgn_time", "Show for (s)", 1, 10, 3)
        hud:Toggle("sgn_rank", "Show danger rank", true)
        hud:Tip("Top-right warning sign for S+/S/A named enemies")
    end

    local ext = tab:Section("Extras", "Left", {"Inv", "Quest", "Allies", "Spoof"})
    if ext.page == 0 then
        ext:Toggle("inv_on", "Inventory overlay", false)
        ext:Toggle("inv_counts", "Show counts", true)
        ext:Button("Page +1", function()
            invPageDelta(1)
        end)
        ext:Button("Page -1", function()
            invPageDelta(-1)
        end)
        ext:Button("Print Inventory", function()
            printInventory()
        end)
        ext:Tip("Key I toggles overlay (12 rows/page)")
    elseif ext.page == 1 then
        ext:Toggle("quest_on", "Quest overlay", false)
        ext:Button("Page +1", function()
            qPageDelta(1)
        end)
        ext:Button("Page -1", function()
            qPageDelta(-1)
        end)
        ext:Button("Print Quests", function()
            printQuests()
        end)
        ext:Tip("Key O toggles overlay (8 rows/page)")
    elseif ext.page == 2 then
        ext:InputText("alli_map", "Ally names", "BigCam3.0, Cam3.0")
        ext:Tip("Comma-separated; each entry may be a character")
        ext:Tip("name OR a player nick - either way it matches")
        ext:Tip("Allies are hidden from ESP and HUD")
    else
        ext:Toggle("spoof_on", "Spoof my nick", false)
        ext:InputText("spoof_name", "Fake nick", "Anonymous")
        ext:Tip("Draws a fake nameplate above your head")
        ext:Tip("covering the real nick (local only).")
        ext:Tip("Server-side nick cannot be overwritten")
    end

    local cfg = tab:Section("Configs", "Left", {"Save", "Load", "Auto"})
    if cfg.page == 0 then
        cfg:InputText("cfg_name", "Config name", "main")
        cfg:Button("Save Config", function()
            cfgSave()
        end)
        cfg:Tip("Saved as cfg_<name>.txt in workspace")
    elseif cfg.page == 1 then
        cfg:Combo("cfg_select", "Config", cfgList, 1)
        cfg:Button("Load Config", function()
            cfgLoad()
        end)
        cfg:Button("Delete Config", function()
            cfgDelete()
        end)
        cfg:Tip("New configs appear after script reload")
    else
        cfg:Toggle("cfg_autoload", "Auto-load on start", false)
        cfg:InputText("cfg_autoname", "Auto config name", "")
        cfg:Tip("Chosen config loads every time the script starts")
    end

    local ctl = tab:Section("Control", "Left")
    ctl:Button("Stop / Remove", function()
        mainStop()
    end)
end)

for id, v in pairs(saved) do
    pcall(UI.SetValue, id, v)
end

local ALL_IDS = {"esp_on", "esp_3d", "esp_names", "esp_hp", "esp_dist", "esp_danger_mode", "esp_items", "esp_itemname", "esp_item_dist", "fr_buy", "fr_heal", "fr_healpct", "fr_buyupg", "hud_on", "hud_wave", "hud_count", "hud_list", "sgn_on", "sgn_time", "sgn_rank", "inv_on", "inv_counts", "quest_on", "alli_map", "spoof_on", "spoof_name", "cfg_name", "cfg_select", "cfg_autoload", "cfg_autoname"}
for _, it in ipairs(BUY_ITEMS) do
    ALL_IDS[#ALL_IDS + 1] = "buy_" .. it
end
for _, it in ipairs(BUY_UPGRADES) do
    ALL_IDS[#ALL_IDS + 1] = "buyu_" .. it
end

local function gw(id)
    local ok, v = pcall(UI.GetValue, id)
    if not ok then return nil end
    return v
end

local vals = {}
local function value(id, def)
    local v = vals[id]
    if v == nil then v = gw(id) end
    if v == nil then return def end
    vals[id] = v
    return v
end

local lastVals = 0
local function refreshVals(now)
    if now - lastVals < 0.5 then return end
    lastVals = now
    for i = 1, #ALL_IDS do
        vals[ALL_IDS[i]] = gw(ALL_IDS[i])
    end
end

function cfgSave()
    local name = tostring(value("cfg_name", "main") or "main")
    if name == "" then name = "main" end
    local fn = "cfg_" .. name .. ".txt"
    local lines = {}
    for _, id in ipairs(ALL_IDS) do
        local v = gw(id)
        if v ~= nil then
            local s = type(v) == "number" and string.format("%.6g", v) or tostring(v)
            lines[#lines + 1] = id .. "=" .. s
        end
    end
    local ok2 = pcall(function()
        writefile(fn, table.concat(lines, "\n"))
    end)
    if ok2 then
        print("[cfg] saved " .. fn .. " (" .. #lines .. " keys)")
    else
        print("[cfg] save failed " .. fn)
    end
end

function cfgApply(name)
    local fn = "cfg_" .. name .. ".txt"
    if not isfile(fn) then
        print("[cfg] missing: " .. fn)
        return
    end
    local okd, data = pcall(readfile, fn)
    if not okd or not data then return end
    local n = 0
    for line in (data .. "\n"):gmatch("(.-)\n") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v then
            local bv = v == "true" and true or (v == "false" and false or (tonumber(v) or v))
            pcall(UI.SetValue, k, bv)
            n = n + 1
        end
    end
    refreshVals(tick())
    print("[cfg] loaded " .. fn .. " (" .. n .. " values)")
end

function cfgLoad()
    local idx = value("cfg_select", 1)
    local name = cfgList[math.floor(idx or 1)]
    if name then
        cfgApply(name)
    else
        print("[cfg] no config selected")
    end
end

function cfgDelete()
    local idx = value("cfg_select", 1)
    local name = cfgList[math.floor(idx or 1)]
    if name then
        local fn = "cfg_" .. name .. ".txt"
        local ok2 = pcall(delfile, fn)
        print("[cfg] deleted " .. fn .. " ok=" .. tostring(ok2))
    else
        print("[cfg] no config selected")
    end
end

if saved.cfg_autoload then
    local autoName = tostring(saved.cfg_autoname or "")
    if autoName ~= "" then
        print("[cfg] auto-loading " .. autoName)
        cfgApply(autoName)
    end
end

local function persist()
    local out = {}
    for i = 1, #ALL_IDS do
        local v = gw(ALL_IDS[i])
        if v ~= nil then
            local s = type(v) == "number" and string.format("%.6g", v) or tostring(v)
            out[#out + 1] = ALL_IDS[i] .. "=" .. s
        end
    end
    pcall(writefile, STATE_FILE, table.concat(out, "\n"))
end
task.spawn(function()
    while running do
        persist()
        task.wait(10)
    end
end)

-- ============================================================
-- ДАННЫЕ HUD
-- ============================================================

local WAVE     = 1
local MAX_WAVE = 1
local TOILETS  = {}
local TOILET_NAME = "???"
local DANGER_RANK = "?"

local RANK_COLORS = {
    ["D"]  = rgb(107, 114, 128),
    ["C"]  = rgb(34,  197, 94 ),
    ["B"]  = rgb(59,  130, 246),
    ["A"]  = rgb(168, 85,  247),
    ["S"]  = rgb(249, 115, 22 ),
    ["S+"] = rgb(239, 68,  68 ),
}
local function accent() return RANK_COLORS[DANGER_RANK] or rgb(249, 115, 22) end

local DANGER_LIST = {
    ["G-Toilet 4.0"] = "S+",
    ["Siren Titan Raid Boss"] = "S+",
    ["Infected Clock Titan"] = "S+",
    ["Astro Entrapper"] = "S+",
    ["Zombie Upgraded Titan Speaker V2"] = "S+",
    ["Mutated Zombie Scientist Toilet"] = "S+",
    ["Christmas Wraith"] = "S+",
    ["Astro High Impactor"] = "S",
    ["Astro Obliterator"] = "S",
    ["Astro Destructor"] = "S",
    ["Air Dropper"] = "S",
    ["Scientist Toilet"] = "S",
    ["Big Acid bomber"] = "A",
    ["Transmitter toilet"] = "A",
    ["White Mafia"] = "A",
}

-- знак: показываем 3 сек, потом прячем и ждём следующего.
-- уже показанных (по addr) повторно не показываем.
local seenDanger  = {}
local currentDanger
local dangerTimer  = 0
local DANGER_SHOW_TIME = 3

local function readDanger()
    local now = tick()

    if currentDanger and now - dangerTimer < value("sgn_time", 3) then
        for _, t in ipairs(TOILETS) do
            if t.addr == currentDanger then
                TOILET_NAME = t.name
                DANGER_RANK = DANGER_LIST[t.name] or "?"
                return
            end
        end
        seenDanger[currentDanger] = true
        currentDanger = nil
    end

    if currentDanger then
        seenDanger[currentDanger] = true
        currentDanger = nil
    end

    for _, t in ipairs(TOILETS) do
        if DANGER_LIST[t.name] and t.addr and not seenDanger[t.addr] then
            currentDanger = t.addr
            dangerTimer = now
            TOILET_NAME = t.name
            DANGER_RANK = DANGER_LIST[t.name]
            return
        end
    end

    TOILET_NAME = "---"
    DANGER_RANK = "?"
end

local lastWaveScan = 0
local waveScanTick = 2

local function readWave()
    local now = tick()
    if now - lastWaveScan < waveScanTick then return end
    lastWaveScan = now
    local ok, pg = pcall(function() return lp:FindFirstChild("PlayerGui") end)
    if not (ok and pg) then return end
    local w
    local ok2, desc = pcall(function() return pg:GetDescendants() end)
    if not ok2 then return end
    for _, obj in ipairs(desc) do
        if obj.ClassName == "TextLabel" then
            local ok3, txt = pcall(function() return obj.Text end)
            if ok3 and txt then
                local wRaw = txt:match("^Waves%s+(%d+)$")
                if wRaw then
                    w = tonumber(wRaw)
                    break
                end
            end
        end
    end
    if w then WAVE = w end
end

-- ============================================================
-- КОЛЛЕКТОР: мобы + туалеты + предметы + имена игроков
-- ============================================================

local playerNames = {}
local lastNamesScan = 0

local function split_allies(s)
    local out = {}
    for part in (s or ""):gmatch("[^,]+") do
        local p = part:gsub("^%s+", ""):gsub("%s+$", "")
        if p ~= "" then out[#out + 1] = p:lower() end
    end
    return out
end

local ALLY_PREFIX = {"villanarc", "blaster tank", "cam turret", "attacker drone", "missile rocket", "[ ai ]", "camera"}

local function ignored_name(n, ign)
    local low = n:lower()
    for i = 1, #ALLY_PREFIX do
        if low:find(ALLY_PREFIX[i], 1, true) then return true end
    end
    for i = 1, #ign do
        if low == ign[i] or low:find(ign[i], 1, true) then return true end
    end
    return false
end

local function is_player_model(m)
    if playerNames[m.Name] then return true end
    if m:FindFirstChild("Shirt") then return true end
    if m:FindFirstChild("M1Script") then return true end
    if m:FindFirstChild("PassiveHealth") then return true end
    if m:FindFirstChild("Skin-Name") then return true end
    if m:FindFirstChild("Grade") then return true end
    if m:FindFirstChild("headphone") then return true end
    if m:FindFirstChild("SoundImprovement") then return true end
    return false
end

local ITEM_EXACT = {
    "Clock Spider", "Keycard", "Energy Core Base", "Green Core Energy", "X18 Core",
    "Lighting Module", "Genesis Core", "Weird Shard", "100MVisitPickOneOfThem",
    "Astro Impactor : Cannon", "Astro Destructor : Core", "Astro Destructor : Laser",
    "Astro Specialist : Spinner", "Astro Interceptor : Spinner", "Astro Interceptor : Mask",
    "Astro Specialist : Blade",
    "Instant Level 80 Mastery : Special Titan", "Instant Level 80 Mastery : Normal Titan",
    "Instant Level 50 Mastery : Special Titan", "Instant Level 50 Mastery : Normal",
    "Mastery Card : Special Titan II", "Mastery Card : Normal II",
    "BlackGear", "BlueGear", "GreenGear",
    "Scorching Ember", "Toilet Token", "Gacha Capsule", "Honor badge", "Special Titan Pass",
    "Normal Titan Pass", "1M$.TITAN-PASS", "TITAN-PASS"
}
local ITEM_PREFIX = {"Flash Drive", "Drive #"}

local function is_item_name(n)
    if ITEM_EXACT[n] then return true end
    local stripped = n:gsub("%s*%(.+%)%s*$", "")
    if stripped ~= n and ITEM_EXACT[stripped] then return true end
    for i = 1, #ITEM_PREFIX do
        local p = ITEM_PREFIX[i]
        if n:sub(1, #p) == p then return true end
    end
    return false
end

local function collectAll()
    refreshVals(tick())
    local now = tick()
    if now - lastNamesScan >= 0.5 then
        lastNamesScan = now
        local out = {}
        local ok, pls = pcall(function() return Players:GetPlayers() end)
        if ok then
            for _, p in ipairs(pls) do
                local ok2, nm = pcall(function() return p.Name end)
                if ok2 and nm then out[nm] = true end
            end
        end
        out[lp.Name] = true
        playerNames = out
    end

    local living = ws:FindFirstChild("Living")
    local lpRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local ignAllies = split_allies(value("alli_map", "BigCam3.0, Cam3.0"))
    local mobsOut, toysOut = {}, {}

    if living then
        local okC, children = pcall(function() return living:GetChildren() end)
        if okC then
            for _, v in ipairs(children) do
                if v.ClassName == "Model" and not is_player_model(v) and not v:FindFirstChild("GoodAI") and not ignored_name(v.Name, ignAllies) then
                    local hum = v:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local hrp = v:FindFirstChild("HumanoidRootPart")
                        if not hrp then hrp = v:FindFirstChild("RootPart") end
                        if not hrp then hrp = v:FindFirstChildWhichIsA("BasePart") end
                        if hrp then
                            local hp, mx = 0, 1
                            pcall(function() hp = hum.Health or 0 end)
                            pcall(function() mx = hum.MaxHealth or 1 end)
                            local addr
                            pcall(function() addr = v.Address end)
                            local hb = {}
                            local torso = v:FindFirstChild("Torso")
                            local fake = v:FindFirstChild("Fake Head")
                            if torso then hb[#hb + 1] = { cfr = torso.CFrame, size = torso.Size } end
                            if fake then hb[#hb + 1] = { cfr = fake.CFrame, size = fake.Size } end
                            if #hb == 0 then hb[#hb + 1] = { cfr = hrp.CFrame, size = hrp.Size } end
                            mobsOut[#mobsOut + 1] = {
                                name = v.Name, addr = addr, pos = hrp.Position, cfr = hrp.CFrame,
                                sz = hrp.Size, hb = hb, hum = hum,
                                dist = lpRoot and (hrp.Position - lpRoot.Position).Magnitude or 0
                            }
                            if hp > 0 then
                                toysOut[#toysOut + 1] = { name = v.Name, addr = addr, hp = hp, maxHp = mx }
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(toysOut, function(a, b) return a.hp > b.hp end)
    mobsCache = mobsOut
    TOILETS = toysOut

    local items = {}
    local seen = {}
    local okW, wChildren = pcall(function() return ws:GetChildren() end)
    if okW then
        for _, v in ipairs(wChildren) do
            if (v.ClassName == "Model" or v.ClassName == "Tool") and is_item_name(v.Name) then
                local bp = v.PrimaryPart or v:FindFirstChildOfClass("BasePart")
                if bp then
                    local addr
                    pcall(function() addr = v.Address end)
                    if not seen[addr] then
                        seen[addr] = true
                        items[#items + 1] = {
                            name = v.Name,
                            pos = bp.Position,
                            dist = lpRoot and (bp.Position - lpRoot.Position).Magnitude or 0,
                            addr = addr
                        }
                    end
                end
            end
        end
    end
    itemsCache = items
end

task.spawn(function()
    local lastCam = ""
    local lastCamLog = 0
    local lastItemsLog = 0
    while running do
        if not alive() then return end
        local okC, errC = pcall(collectAll)
        if not okC then print("[main] collectAll err: " .. tostring(errC)) end
        local itc = tick()
        if itc - lastItemsLog > 30 then
            lastItemsLog = itc
            print("[main] items=" .. #itemsCache .. " mobs=" .. #mobsCache)
        end
        local cc = workspace.CurrentCamera
        if cc then
            local okFull, full = pcall(function() return cc:GetFullName() end)
            local nm = okFull and full or cc.Name
            if nm ~= lastCam then
                lastCam = nm
                if tick() - lastCamLog > 3 then
                    lastCamLog = tick()
                    print("[main] camera -> " .. tostring(nm))
                end
            end
        end
        task.wait(0.15)
    end
end)

-- ============================================================
-- ЗНАК ПРЕДУПРЕЖДЕНИЯ  (вверху экрана, по центру)
-- ============================================================

local cam = workspace.CurrentCamera
local SW  = cam.ViewportSize.X
local SH  = cam.ViewportSize.Y
local SGN_W, SGN_H = 200, 175
local SGN_X = SW - SGN_W - 16
local SGN_Y = 20

local signRefs = {}
local signAll  = {}

do
    local bg = new("Square")
    bg.Filled = true; bg.Color = rgb(10, 10, 14)
    bg.Position = Vector2.new(SGN_X, SGN_Y); bg.Size = Vector2.new(SGN_W, SGN_H)
    bg.Visible = true; bg.ZIndex = 20
    signAll[#signAll + 1] = bg
end

do
    local brd = new("Square")
    brd.Filled = false; brd.Color = accent(); brd.Thickness = 2
    brd.Position = Vector2.new(SGN_X, SGN_Y); brd.Size = Vector2.new(SGN_W, SGN_H)
    brd.Visible = true; brd.ZIndex = 21
    signAll[#signAll + 1] = brd
    signRefs.brd = brd
end

do
    local top = new("Square")
    top.Filled = true; top.Color = accent()
    top.Position = Vector2.new(SGN_X, SGN_Y); top.Size = Vector2.new(SGN_W, 3)
    top.Visible = true; top.ZIndex = 22
    signAll[#signAll + 1] = top
    signRefs.top = top
end

do
    local bot = new("Square")
    bot.Filled = true; bot.Color = accent()
    bot.Position = Vector2.new(SGN_X, SGN_Y + SGN_H - 3); bot.Size = Vector2.new(SGN_W, 3)
    bot.Visible = true; bot.ZIndex = 22
    signAll[#signAll + 1] = bot
    signRefs.bot = bot
end

do
    local cx  = SGN_X + SGN_W / 2
    local tip = SGN_Y + 16
    local base = SGN_Y + 84
    local half = 42

    for _, pts in ipairs({
        { Vector2.new(cx, tip), Vector2.new(cx - half, base) },
        { Vector2.new(cx, tip), Vector2.new(cx + half, base) },
        { Vector2.new(cx - half, base), Vector2.new(cx + half, base) },
    }) do
        local l = new("Line")
        l.From = pts[1]; l.To = pts[2]
        l.Color = accent(); l.Thickness = 2; l.Visible = true; l.ZIndex = 23
        signRefs.tri = signRefs.tri or {}
        signRefs.tri[#signRefs.tri + 1] = l
        signAll[#signAll + 1] = l
    end

    local excl = new("Text")
    excl.Text = "!"; excl.Color = accent(); excl.Size = 28
    excl.Font = Drawing.Fonts.SystemBold; excl.Center = true; excl.Outline = false
    excl.Position = Vector2.new(cx, tip + 20); excl.Visible = true; excl.ZIndex = 24
    signRefs.excl = excl
    signAll[#signAll + 1] = excl
end

do
    local d = new("Line")
    d.From = Vector2.new(SGN_X + 14, SGN_Y + 92)
    d.To   = Vector2.new(SGN_X + SGN_W - 14, SGN_Y + 92)
    d.Color = accent(); d.Thickness = 1; d.Transparency = 0.6; d.Visible = true; d.ZIndex = 22
    signRefs.div1 = d
    signAll[#signAll + 1] = d
end

do
    local nm = new("Text")
    nm.Text = TOILET_NAME; nm.Color = rgb(230, 230, 230); nm.Size = 16
    nm.Font = Drawing.Fonts.SystemBold; nm.Center = true; nm.Outline = true
    nm.Position = Vector2.new(SGN_X + SGN_W / 2, SGN_Y + 100)
    nm.Visible = true; nm.ZIndex = 24
    signRefs.name = nm
    signAll[#signAll + 1] = nm
end

do
    local d2 = new("Line")
    d2.From = Vector2.new(SGN_X + 14, SGN_Y + 126)
    d2.To   = Vector2.new(SGN_X + SGN_W - 14, SGN_Y + 126)
    d2.Color = accent(); d2.Thickness = 1; d2.Transparency = 0.75; d2.Visible = true; d2.ZIndex = 22
    signRefs.div2 = d2
    signAll[#signAll + 1] = d2
end

do
    local lbl = new("Text")
    lbl.Text = "РАНГ ОПАСНОСТИ"; lbl.Color = rgb(75, 75, 90); lbl.Size = 10
    lbl.Font = Drawing.Fonts.System; lbl.Center = false; lbl.Outline = false
    lbl.Position = Vector2.new(SGN_X + 12, SGN_Y + 138); lbl.Visible = true; lbl.ZIndex = 24
    signRefs.rlbl = lbl
    signAll[#signAll + 1] = lbl
end

do
    local rnk = new("Text")
    rnk.Text = DANGER_RANK; rnk.Color = accent(); rnk.Size = 22
    rnk.Font = Drawing.Fonts.SystemBold; rnk.Center = false; rnk.Outline = true
    rnk.Position = Vector2.new(SGN_X + SGN_W - 26, SGN_Y + 132)
    rnk.Visible = true; rnk.ZIndex = 24
    signRefs.rank = rnk
    signAll[#signAll + 1] = rnk
end

local function repaintSign()
    local col = accent()
    signRefs.brd.Color  = col
    signRefs.top.Color  = col
    signRefs.bot.Color  = col
    signRefs.excl.Color = col
    signRefs.div1.Color = col
    signRefs.div2.Color = col
    signRefs.rank.Color = col
    for _, l in ipairs(signRefs.tri) do l.Color = col end
end

local function setSignVisible(v)
    for _, o in ipairs(signAll) do
        if o then o.Visible = v end
    end
end

-- ============================================================
-- HUD (справа)
-- ============================================================

local HUD_X = SW - 260 - 16
local HUD_Y = SGN_Y + SGN_H + 8
local HUD_W = 260

local function panel(x, y, w, h, lineColor, baseZ)
    baseZ = baseZ or 20
    local bg = new("Square")
    bg.Filled = true; bg.Color = rgb(8, 8, 14)
    bg.Position = Vector2.new(x, y); bg.Size = Vector2.new(w, h)
    bg.Visible = true; bg.ZIndex = baseZ

    local fr = new("Square")
    fr.Filled = false; fr.Color = rgb(255, 255, 255); fr.Transparency = 0.85; fr.Thickness = 1
    fr.Position = Vector2.new(x, y); fr.Size = Vector2.new(w, h)
    fr.Visible = true; fr.ZIndex = baseZ + 1

    local ac
    if lineColor then
        ac = new("Line")
        ac.From = Vector2.new(x, y); ac.To = Vector2.new(x + w, y)
        ac.Color = lineColor; ac.Thickness = 2; ac.Visible = true; ac.ZIndex = baseZ + 2
    end
    return { bg = bg, fr = fr, ac = ac }
end

local function txt(str, x, y, size, color, center, font, z)
    local t = new("Text")
    t.Text = str; t.Color = color or rgb(200, 200, 200); t.Size = size or 12
    t.Font = font or Drawing.Fonts.SystemBold
    t.Position = Vector2.new(x, y); t.Center = center or false
    t.Outline = true; t.Visible = true; t.ZIndex = z or 25
    return t
end

local TOP_H = 42
local HUD_objs = {}

do
    local p = panel(HUD_X, HUD_Y, HUD_W, TOP_H, rgb(249, 115, 22))
    HUD_objs[#HUD_objs + 1] = p.bg
    HUD_objs[#HUD_objs + 1] = p.fr
end

HUD_objs[#HUD_objs + 1] = txt("ВОЛНА", HUD_X + 10, HUD_Y + 8, 10, rgb(120, 120, 130), false, Drawing.Fonts.System)
local waveTxt = txt(WAVE .. (MAX_WAVE > 1 and " / " .. MAX_WAVE or ""), HUD_X + 10, HUD_Y + 22, 16, rgb(249, 115, 22), false)
HUD_objs[#HUD_objs + 1] = waveTxt

do
    local vl = new("Line")
    vl.From = Vector2.new(HUD_X + HUD_W / 2, HUD_Y + 8)
    vl.To   = Vector2.new(HUD_X + HUD_W / 2, HUD_Y + TOP_H - 8)
    vl.Color = rgb(255, 255, 255); vl.Transparency = 0.85; vl.Thickness = 1; vl.Visible = true; vl.ZIndex = 24
    HUD_objs[#HUD_objs + 1] = vl
end

HUD_objs[#HUD_objs + 1] = txt("ТУАЛЕТОВ", HUD_X + HUD_W / 2 + 10, HUD_Y + 8, 10, rgb(120, 120, 130), false, Drawing.Fonts.System)
local countTxt = txt(tostring(#TOILETS), HUD_X + HUD_W / 2 + 10, HUD_Y + 22, 16, rgb(239, 68, 68), false)
HUD_objs[#HUD_objs + 1] = countTxt

local LIST_Y = HUD_Y + TOP_H + 2
local ROW_H  = 30
local MAX_ROWS = 5

local listPanel = panel(HUD_X, LIST_Y, HUD_W, MAX_ROWS * ROW_H + 20, nil)
HUD_objs[#HUD_objs + 1] = listPanel.bg
HUD_objs[#HUD_objs + 1] = listPanel.fr
HUD_objs[#HUD_objs + 1] = txt("СПИСОК ПО ХП", HUD_X + 10, LIST_Y + 8, 9, rgb(60, 60, 75), false, Drawing.Fonts.System)

local rows = {}
for i = 1, MAX_ROWS do
    local ry = LIST_Y + 22 + (i - 1) * ROW_H
    local barX, barY = HUD_X + 22, ry + 16

    local num  = txt(tostring(i), HUD_X + 8, ry + 2, 10, rgb(60, 60, 75), false, Drawing.Fonts.System)
    local name = txt("", HUD_X + 22, ry, 12, rgb(215, 215, 220), false)

    local bbg = new("Square")
    bbg.Filled = true; bbg.Color = rgb(25, 25, 38)
    bbg.Position = Vector2.new(barX, barY); bbg.Size = Vector2.new(100, 7)
    bbg.Visible = true; bbg.ZIndex = 23

    local bfill = new("Square")
    bfill.Filled = true; bfill.Color = rgb(34, 197, 94)
    bfill.Position = Vector2.new(barX, barY); bfill.Size = Vector2.new(0, 7)
    bfill.Visible = true; bfill.ZIndex = 24

    local hpTxt = txt("", HUD_X + 130, ry + 14, 10, rgb(34, 197, 94), false, Drawing.Fonts.Monospace)

    local sep
    if i < MAX_ROWS then
        sep = new("Line")
        sep.From = Vector2.new(HUD_X + 8, ry + ROW_H - 2)
        sep.To   = Vector2.new(HUD_X + HUD_W - 8, ry + ROW_H - 2)
        sep.Color = rgb(255, 255, 255); sep.Transparency = 0.92; sep.Thickness = 1
        sep.Visible = true; sep.ZIndex = 22
    end

    rows[i] = { num = num, name = name, bbg = bbg, bfill = bfill, hp = hpTxt, sep = sep }
end

local function updateList()
    local hOn    = value("hud_on", true) == true
    local showWave  = hOn and value("hud_wave", true) == true
    local showCount = hOn and value("hud_count", true) == true
    local showList  = hOn and value("hud_list", true) == true

    for _, o in ipairs(HUD_objs) do
        if o.Visible ~= hOn then o.Visible = hOn end
    end
    if showWave ~= waveTxt.Visible then waveTxt.Visible = showWave end
    if showCount ~= countTxt.Visible then countTxt.Visible = showCount end

    local n = math.min(#TOILETS, MAX_ROWS)
    local h = 20 + n * ROW_H
    listPanel.bg.Size = Vector2.new(HUD_W, h)
    listPanel.fr.Size = Vector2.new(HUD_W, h)

    countTxt.Text = tostring(#TOILETS)
    waveTxt.Text  = WAVE .. (MAX_WAVE > 1 and " / " .. MAX_WAVE or "")

    for i = 1, MAX_ROWS do
        local row = rows[i]
        local toilet = TOILETS[i]
        if showList and toilet then
            local pct = toilet.hp / toilet.maxHp
            local r = DANGER_LIST[toilet.name]
            local bCol = (r and RANK_COLORS[r]) or
                (pct > 0.6 and rgb(34, 197, 94)
                or pct > 0.3 and rgb(249, 115, 22)
                or rgb(239, 68, 68))

            row.num.Text = tostring(i)
            row.num.Visible = true
            row.name.Text = toilet.name
            row.name.Visible = true
            row.bbg.Visible = true
            row.bbg.Size = Vector2.new(100, 7)
            row.bfill.Visible = true
            row.bfill.Color = bCol
            row.bfill.Size = Vector2.new(100 * pct, 7)
            row.hp.Text = toilet.hp .. "/" .. toilet.maxHp
            row.hp.Color = bCol
            row.hp.Visible = true
            if row.sep then row.sep.Visible = i < n end
        else
            row.num.Visible = false
            row.name.Visible = false
            row.bbg.Visible = false
            row.bfill.Visible = false
            row.hp.Visible = false
            if row.sep then row.sep.Visible = false end
        end
    end
end

local function updateHud()
    readWave()
    readDanger()

    local warnShow = value("sgn_on", true) == true
    if warnShow and currentDanger then
        signRefs.name.Text = TOILET_NAME
        signRefs.rank.Text = DANGER_RANK
        repaintSign()
        setSignVisible(true)
        local hasRank = value("sgn_rank", true) == true
        if signRefs.rank then signRefs.rank.Visible = hasRank end
        if signRefs.rlbl then signRefs.rlbl.Visible = hasRank end
    else
        setSignVisible(false)
    end

    updateList()
end

-- ============================================================
-- ИНВЕНТАРЬ / КВЕСТЫ (оверлеи слева + дамп в логи)
-- ============================================================

local invCache = {}
local chipCount = 0
local questCache = { activeName = "", activeDetail = "", completed = 0, masteries = {}, progress = {} }

local function collectInv()
    local ok, res = pcall(function()
        local lp2 = Players.LocalPlayer
        local out = {}
        local chips = 0
        local f = lp2 and lp2:FindFirstChild("ItemsFolder")
        if f then
            for _, c in ipairs(f:GetChildren()) do
                if c.ClassName == "NumberValue" then
                    local v = 0
                    pcall(function() v = c.Value or 0 end)
                    out[#out + 1] = { name = c.Name, cnt = v, hasCnt = true }
                elseif c.ClassName == "StringValue" then
                    out[#out + 1] = { name = c.Name, cnt = nil, hasCnt = false }
                    chips = chips + 1
                end
            end
        end
        table.sort(out, function(a, b)
            if a.hasCnt ~= b.hasCnt then return a.hasCnt end
            if a.hasCnt and a.cnt ~= b.cnt then return a.cnt > b.cnt end
            return a.name < b.name
        end)
        invCache = out
        chipCount = chips
    end)
    if not ok then print("[main] inv err: " .. tostring(res)) end
end

local function collectQuests()
    local ok, res = pcall(function()
        local lp2 = Players.LocalPlayer
        local q = { activeName = "", activeDetail = "", completed = 0, masteries = {}, progress = {} }
        local pg2 = lp2 and lp2:FindFirstChild("PlayerGui")
        local qu = pg2 and pg2:FindFirstChild("QuestUI")
        local ql = qu and qu:FindFirstChild("LocalScript") and qu.LocalScript:FindFirstChild("Frame") and qu.LocalScript.Frame:FindFirstChild("Frame")
        if ql then
            local a = ql:FindFirstChild("Quest name")
            local d = ql:FindFirstChild("Quest detail")
            pcall(function() q.activeName = a and a.Text or "" end)
            pcall(function() q.activeDetail = d and d.Text or "" end)
        end
        local ud = lp2 and lp2:FindFirstChild("UnlockData")
        if ud then
            local ms, pr, compl = {}, {}, 0
            for _, c in ipairs(ud:GetChildren()) do
                local nm = c.Name
                if nm:find("CompleteQuest", 1, true) then
                    local v = false
                    pcall(function() v = c.Value end)
                    if v == true or v == 1 then compl = compl + 1 end
                elseif nm:find(":Mastery:", 1, true) then
                    local unit = nm:match("^(.*):Mastery:%d+$")
                    local lvl = 0
                    pcall(function() lvl = c.Value or 0 end)
                    if unit then ms[#ms + 1] = { name = unit, lvl = lvl, done = lvl >= 100 } end
                else
                    local v
                    pcall(function() v = c.Value end)
                    if type(v) == "number" and nm ~= "SkinNumber" and not nm:find("AstroTechLv", 1, true) then
                        pr[#pr + 1] = { name = nm, val = v }
                    end
                end
            end
            table.sort(ms, function(a, b) return a.lvl > b.lvl end)
            table.sort(pr, function(a, b) return a.val < b.val end)
            q.completed = compl
            q.masteries = ms
            q.progress = pr
        end
        questCache = q
    end)
    if not ok then print("[main] quest err: " .. tostring(res)) end
end

task.spawn(function()
    while running do
        if not alive() then return end
        pcall(collectInv)
        pcall(collectQuests)
        task.wait(1.5)
    end
end)

function printInventory()
    print("[inv] total=" .. #invCache)
    for _, it in ipairs(invCache) do
        if it.hasCnt then
            print("[inv] " .. it.name .. " = " .. tostring(it.cnt))
        else
            print("[inv] " .. it.name)
        end
    end
end

function printQuests()
    print("[quest] active=" .. tostring(questCache.activeName) .. " | " .. tostring(questCache.activeDetail))
    print("[quest] completed=" .. tostring(questCache.completed))
    for _, p in ipairs(questCache.progress) do
        print("[quest] " .. p.name .. " = " .. tostring(p.val))
    end
    for _, m in ipairs(questCache.masteries) do
        print("[quest] mastery " .. m.name .. " = " .. tostring(m.lvl))
    end
end

local SCALE = 1.4
local INV_W = math.floor(300 * SCALE)
local INV_ROWS = 12
local IROW_H = math.floor(18 * SCALE)
local INV_H = math.floor(22 * SCALE) + INV_ROWS * IROW_H
local QROWS = 8
local qRowH = math.floor(15 * SCALE)
local qH = math.floor(18 * SCALE) + math.floor(12 * SCALE) + math.floor(10 * SCALE) + math.floor(11 * SCALE) + 8 + QROWS * qRowH
local INV_X = math.floor((SW - INV_W) * 0.5)
local INV_Y = math.floor((SH - (INV_H + 6 + qH)) * 0.5)

local invPanel = panel(INV_X, INV_Y, INV_W, INV_H, rgb(255, 215, 0))
local invTitle = txt("ИНВЕНТАРЬ", INV_X + 14, INV_Y + math.floor(2 * SCALE), math.floor(11 * SCALE), rgb(255, 215, 0), false, Drawing.Fonts.SystemBold)
local invRows = {}
for i = 1, INV_ROWS do
    invRows[i] = {
        name = txt("", INV_X + 14, INV_Y + math.floor(22 * SCALE) + (i - 1) * IROW_H, math.floor(11 * SCALE), rgb(215, 215, 220), false, Drawing.Fonts.System),
        cnt = txt("", INV_X + INV_W - 84, INV_Y + math.floor(22 * SCALE) + (i - 1) * IROW_H, math.floor(11 * SCALE), rgb(255, 215, 0), true, Drawing.Fonts.Monospace)
    }
end

local qY = INV_Y + INV_H + 6
local qPanel = panel(INV_X, qY, INV_W, qH, rgb(168, 85, 247))
local qTitle = txt("КВЕСТЫ", INV_X + 14, qY + math.floor(2 * SCALE), math.floor(11 * SCALE), rgb(168, 85, 247), false, Drawing.Fonts.SystemBold)
local qNameT = txt("", INV_X + 14, qY + math.floor(20 * SCALE), math.floor(12 * SCALE), rgb(230, 230, 230), false)
local qDetailT = txt("", INV_X + 14, qY + math.floor(34 * SCALE), math.floor(10 * SCALE), rgb(150, 150, 160), false, Drawing.Fonts.System)
local qDoneT = txt("", INV_X + 14, qY + math.floor(48 * SCALE), math.floor(11 * SCALE), rgb(34, 197, 94), false, Drawing.Fonts.System)
local qRows = {}
for i = 1, QROWS do
    qRows[i] = txt("", INV_X + 14, qY + math.floor(64 * SCALE) + (i - 1) * qRowH, math.floor(10 * SCALE), rgb(200, 200, 210), false, Drawing.Fonts.System)
end

local invPage, qPage = 1, 1

local function updateExtra()
    local invOn = value("inv_on", false)
    if invOn then
        local showCnt = value("inv_counts", true)
        invPanel.bg.Visible = true
        invPanel.fr.Visible = true
        if invPanel.ac then invPanel.ac.Visible = true end
        invTitle.Visible = true
        local maxP = math.max(1, math.ceil(#invCache / INV_ROWS))
        local page = invPage
        if page < 1 then page = 1 end
        if page > maxP then page = maxP end
        for i = 1, INV_ROWS do
            local it = invCache[(page - 1) * INV_ROWS + i]
            local r = invRows[i]
            if it then
                r.name.Text = it.name
                r.name.Visible = true
                if showCnt and it.hasCnt then
                    r.cnt.Text = tostring(it.cnt)
                    r.cnt.Visible = true
                else
                    r.cnt.Visible = false
                end
            else
                r.name.Visible = false
                r.cnt.Visible = false
            end
        end
        invTitle.Text = "ИНВЕНТАРЬ (" .. #invCache .. ", чипов: " .. chipCount .. ")  стр. " .. page .. "/" .. maxP
    else
        invPanel.bg.Visible = false
        invPanel.fr.Visible = false
        if invPanel.ac then invPanel.ac.Visible = false end
        invTitle.Visible = false
        for i = 1, INV_ROWS do
            invRows[i].name.Visible = false
            invRows[i].cnt.Visible = false
        end
    end

    local qOn = value("quest_on", false)
    if qOn then
        qPanel.bg.Visible = true
        qPanel.fr.Visible = true
        if qPanel.ac then qPanel.ac.Visible = true end
        qTitle.Visible = true
        qNameT.Text = questCache.activeName == "" and "-" or questCache.activeName
        qNameT.Visible = true
        local d = questCache.activeDetail
        if #d > 54 then d = d:sub(1, 54) .. "..." end
        qDetailT.Text = d == "" and "-" or d
        qDetailT.Visible = true
        qDoneT.Text = "Выполнено: " .. questCache.completed
        qDoneT.Visible = true
        local qList = {}
        for _, p in ipairs(questCache.progress) do
            qList[#qList + 1] = { txt = p.name .. " = " .. tostring(p.val) }
        end
        for _, m in ipairs(questCache.masteries) do
            if not m.done then
                qList[#qList + 1] = { txt = m.name .. " : " .. tostring(m.lvl) }
            end
        end
        local qMaxP = math.max(1, math.ceil(#qList / QROWS))
        local qpage = qPage
        if qpage < 1 then qpage = 1 end
        if qpage > qMaxP then qpage = qMaxP end
        for i = 1, QROWS do
            local e = qList[(qpage - 1) * QROWS + i]
            local r = qRows[i]
            if e then
                r.Text = e.txt
                r.Visible = true
            else
                r.Visible = false
            end
        end
        qTitle.Text = "КВЕСТЫ (стр. " .. qpage .. "/" .. qMaxP .. ")"
    else
        qPanel.bg.Visible = false
        qPanel.fr.Visible = false
        if qPanel.ac then qPanel.ac.Visible = false end
        qTitle.Visible = false
        qNameT.Visible = false
        qDetailT.Visible = false
        qDoneT.Visible = false
        for i = 1, QROWS do qRows[i].Visible = false end
    end
end

function invPageDelta(d)
    local maxP = math.max(1, math.ceil(#invCache / INV_ROWS))
    invPage = invPage + d
    if invPage < 1 then invPage = 1 end
    if invPage > maxP then invPage = maxP end
end

function qPageDelta(d)
    local n = #questCache.progress
    for _, m in ipairs(questCache.masteries) do
        if not m.done then n = n + 1 end
    end
    local maxP = math.max(1, math.ceil(n / QROWS))
    qPage = qPage + d
    if qPage < 1 then qPage = 1 end
    if qPage > maxP then qPage = maxP end
end

UIS.InputBegan:Connect(function(input)
    if not running or not alive() then return end
    local kc = input and input.KeyCode
    if not kc then return end
    if kc == 105 then
        vals.inv_on = nil
        pcall(UI.SetValue, "inv_on", not value("inv_on", false))
    elseif kc == 111 then
        vals.quest_on = nil
        pcall(UI.SetValue, "quest_on", not value("quest_on", false))
    elseif value("inv_on", false) then
        if kc == 169 or kc == 38 or kc == 119 then invPageDelta(-1) end
        if kc == 170 or kc == 40 or kc == 115 then invPageDelta(1) end
    end
end)

task.spawn(function()
    while true do
        pcall(updateHud)
        pcall(updateExtra)
        task.wait(0.4)
    end
end)

-- ============================================================
-- ESP
-- ============================================================

local pool = {}
for i = 1, POOL do
    local box = new("Square")
    box.Thickness = 1
    box.Visible = false
    local name = new("Text")
    name.Size = 12
    name.Center = true
    name.Outline = true
    name.Visible = false
    local bar = new("Square")
    bar.Filled = true
    bar.Visible = false
    local rank = new("Text")
    rank.Size = 11
    rank.Center = true
    rank.Outline = true
    rank.Color = rgb(160, 160, 170)
    rank.Visible = false
    pool[i] = { box = box, name = name, bar = bar, rank = rank }
end

local itemPool = {}
for i = 1, ITEM_POOL do
    local box = new("Square")
    box.Thickness = 1
    box.Visible = false
    box.Color = rgb(255, 215, 0)
    local name = new("Text")
    name.Size = 11
    name.Center = true
    name.Outline = true
    name.Color = rgb(255, 235, 120)
    name.Visible = false
    itemPool[i] = { box = box, name = name }
end

local BOX_EDGES = {
    {1, 2}, {2, 3}, {3, 4}, {4, 1},
    {5, 6}, {6, 7}, {7, 8}, {8, 5},
    {1, 5}, {2, 6}, {3, 7}, {4, 8}
}
local pool3d = {}
for i = 1, POOL do
    local ls = {}
    for j = 1, 12 do
        local ln = new("Line")
        ln.Thickness = 1
        ln.Visible = false
        ln.Color = rgb(255, 120, 60)
        ls[j] = ln
    end
    pool3d[i] = ls
end

local function hide_all()
    for i = 1, POOL do
        pool[i].box.Visible = false
        pool[i].name.Visible = false
        pool[i].bar.Visible = false
        pool[i].rank.Visible = false
    end
    for i = 1, POOL do
        for j = 1, 12 do pool3d[i][j].Visible = false end
    end
    for i = 1, ITEM_POOL do
        itemPool[i].box.Visible = false
        itemPool[i].name.Visible = false
    end
end

local renderer
local rendererErrShown = false
local dTrack = { addr = nil, name = nil, at = 0 }
local updateSpoofTag

-- проекция через нативную WorldToScreen: это камера реального рендера
-- (своя математика по CurrentCamera.CFrame расходится на катсценах/камерах-хелперах)
local tmpVW, tmpVH
local function proj(pos)
    local p, vis = WorldToScreen(pos)
    if not vis then return nil, false end
    if p.X < 0 or p.X > tmpVW or p.Y < 0 or p.Y > tmpVH then return nil, false end
    return p, true
end

renderer = RunService.RenderStepped:Connect(function()
    if not running or not alive() then
        hide_all()
        return
    end
    local okR, errR = pcall(function()
    local curCam = workspace.CurrentCamera
    if not curCam then return end
    cam = curCam
    tmpVH = cam.ViewportSize.Y
    tmpVW = cam.ViewportSize.X
    local nowTick = tick()
    local lpChar = lp.Character
    local lpRoot = lpChar and lpChar:FindFirstChild("HumanoidRootPart")

    local n = 0
    local use3d = value("esp_3d", false)
    if value("esp_on", true) and lpRoot then
        local maxDist = value("esp_dist", 3000)
        local mc = mobsCache
        for i = 1, #mc do
            if n >= POOL then break end
            local t = mc[i]
            if not t then break end
            if t.dist <= maxDist then
                local dm = value("esp_danger_mode", 1)
                local isDanger = true
                if dm == 2 then
                    if currentDanger then
                        if dTrack.addr ~= currentDanger then
                            dTrack.addr = currentDanger
                            dTrack.at = nowTick
                            local nm = TOILET_NAME
                            for _, t2 in ipairs(TOILETS) do
                                if t2.addr == currentDanger then nm = t2.name break end
                            end
                            dTrack.name = nm
                        elseif nowTick - dTrack.at >= 30 then
                            dTrack.at = nowTick
                        end
                    elseif not dTrack.addr then
                        local nm = TOILET_NAME
                        if nm ~= "---" and nm ~= "" then
                            dTrack.name = nm
                            dTrack.at = nowTick
                        end
                    end
                    if nowTick - dTrack.at < 30 then
                        if dTrack.addr then
                            isDanger = (t.addr ~= nil and t.addr == dTrack.addr)
                                or (dTrack.name ~= nil and dTrack.name ~= "---" and t.name == dTrack.name)
                        else
                            isDanger = dTrack.name ~= nil and dTrack.name ~= "---" and t.name == dTrack.name
                        end
                    else
                        isDanger = false
                    end
                elseif dm == 3 then
                    isDanger = DANGER_LIST[t.name] ~= nil
                end
                if isDanger then
                local big = t.name:find("Big", 1, true) or t.name:find("Giant", 1, true)
                local up = big and 2.2 or 1.4
                local dn = big and 1.2 or 1.2
                if use3d then
                    local hb = t.hb
                    local first = true
                    for hidx = 1, #hb do
                        if n >= POOL then break end
                        local pt = hb[hidx]
                        local pc = pt.cfr
                        local ps = pt.size
                        local corners = {
                            pc:PointToWorldSpace(Vector3.new(-ps.X * 0.5, -ps.Y * 0.5, -ps.Z * 0.5)),
                            pc:PointToWorldSpace(Vector3.new(ps.X * 0.5, -ps.Y * 0.5, -ps.Z * 0.5)),
                            pc:PointToWorldSpace(Vector3.new(ps.X * 0.5, -ps.Y * 0.5, ps.Z * 0.5)),
                            pc:PointToWorldSpace(Vector3.new(-ps.X * 0.5, -ps.Y * 0.5, ps.Z * 0.5)),
                            pc:PointToWorldSpace(Vector3.new(-ps.X * 0.5, ps.Y * 0.5, -ps.Z * 0.5)),
                            pc:PointToWorldSpace(Vector3.new(ps.X * 0.5, ps.Y * 0.5, -ps.Z * 0.5)),
                            pc:PointToWorldSpace(Vector3.new(ps.X * 0.5, ps.Y * 0.5, ps.Z * 0.5)),
                            pc:PointToWorldSpace(Vector3.new(-ps.X * 0.5, ps.Y * 0.5, ps.Z * 0.5))
                        }
                        local okAll = true
                        local scr = {}
                        for k = 1, 8 do
                            local p, vis = proj(corners[k])
                            if not vis then okAll = false break end
                            scr[k] = p
                        end
                        if okAll then
                            n = n + 1
                            local e = pool[n]
                            local ls = pool3d[n]
                            e.box.Visible = false
                            for j = 1, 12 do
                                local ed = BOX_EDGES[j]
                                ls[j].From = scr[ed[1]]
                                ls[j].To = scr[ed[2]]
                                ls[j].Visible = true
                            end
                            if first then
                                if value("esp_names", true) then
                                    local nx = (scr[5].X + scr[7].X) * 0.5
                                    e.name.Text = t.name .. " [" .. math.floor(t.dist) .. "]"
                                    e.name.Position = Vector2.new(nx, scr[5].Y - 14)
                                    e.name.Visible = true
                                    local rk = DANGER_LIST[t.name]
                                    if rk then
                                        e.rank.Text = rk
                                        e.rank.Position = Vector2.new(nx, scr[5].Y - 27)
                                        e.rank.Color = RANK_COLORS[rk] or rgb(160, 160, 170)
                                        e.rank.Visible = true
                                    else
                                        e.rank.Visible = false
                                    end
                                else
                                    e.name.Visible = false
                                    e.rank.Visible = false
                                end
                                if value("esp_hp", true) then
                                    local hp, mx = 0, 1
                                    pcall(function() hp = t.hum.Health or 0 end)
                                    pcall(function() mx = t.hum.MaxHealth or 1 end)
                                    local frac = mx > 0 and hp / mx or 0
                                    local w = scr[2].X - scr[1].X
                                    e.bar.Position = Vector2.new(scr[1].X, scr[1].Y + 2)
                                    e.bar.Size = Vector2.new(w, 3)
                                    e.bar.Color = Color3.fromHSV(math.clamp(frac, 0, 1) * 0.33, 1, 1)
                                    e.bar.Visible = true
                                else
                                    e.bar.Visible = false
                                end
                                first = false
                            else
                                e.name.Visible = false
                                e.bar.Visible = false
                            end
                        end
                    end
                else
                    local top, v1 = proj(t.pos + Vector3.new(0, up, 0))
                    local bot, v2 = proj(t.pos - Vector3.new(0, dn, 0))
                    if v1 and v2 and bot.Y > top.Y then
                        n = n + 1
                        local e = pool[n]
                        local h = bot.Y - top.Y
                        local w = h * 0.5
                        e.box.Position = Vector2.new(top.X - w * 0.5, top.Y)
                        e.box.Size = Vector2.new(w, h)
                        e.box.Visible = true
                        if value("esp_names", true) then
                            e.name.Text = t.name .. " [" .. math.floor(t.dist) .. "]"
                            e.name.Position = Vector2.new(top.X, top.Y - 14)
                            e.name.Visible = true
                            local rk = DANGER_LIST[t.name]
                            if rk then
                                e.rank.Text = rk
                                e.rank.Position = Vector2.new(top.X, top.Y - 27)
                                e.rank.Color = RANK_COLORS[rk] or rgb(160, 160, 170)
                                e.rank.Visible = true
                            else
                                e.rank.Visible = false
                            end
                        else
                            e.name.Visible = false
                            e.rank.Visible = false
                        end
                        if value("esp_hp", true) then
                            local hp, mx = 0, 1
                            pcall(function() hp = t.hum.Health or 0 end)
                            pcall(function() mx = t.hum.MaxHealth or 1 end)
                            local frac = mx > 0 and hp / mx or 0
                            e.bar.Position = Vector2.new(top.X - w * 0.5, bot.Y + 2)
                            e.bar.Size = Vector2.new(w, 3)
                            e.bar.Color = Color3.fromHSV(math.clamp(frac, 0, 1) * 0.33, 1, 1)
                            e.bar.Visible = true
                        else
                            e.bar.Visible = false
                        end
                    end
                end
                end
            end
        end
    end
    for i = n + 1, POOL do
        pool[i].box.Visible = false
        pool[i].name.Visible = false
        pool[i].bar.Visible = false
        pool[i].rank.Visible = false
        for j = 1, 12 do pool3d[i][j].Visible = false end
    end

    local nI = 0
    if value("esp_items", true) and lpRoot then
        local maxDist = value("esp_item_dist", 3000)
        local showName = value("esp_itemname", true)
        local ic = itemsCache
        for i = 1, #ic do
            if nI >= ITEM_POOL then break end
            local it = ic[i]
            if not it then break end
            if it.dist <= maxDist then
                local top, v1 = proj(it.pos + Vector3.new(0, 1.5, 0))
                local bot, v2 = proj(it.pos - Vector3.new(0, 1.5, 0))
                if v1 and v2 and bot.Y > top.Y then
                    nI = nI + 1
                    local e = itemPool[nI]
                    local h = bot.Y - top.Y
                    local w = h * 0.9
                    e.box.Position = Vector2.new(top.X - w * 0.5, top.Y)
                    e.box.Size = Vector2.new(w, h)
                    e.box.Visible = true
                    if showName then
                        e.name.Text = it.name .. " [" .. math.floor(it.dist) .. "]"
                        e.name.Position = Vector2.new(top.X, top.Y - 14)
                        e.name.Visible = true
                    else
                        e.name.Visible = false
                    end
                end
            end
        end
    end
    for i = nI + 1, ITEM_POOL do
        itemPool[i].box.Visible = false
        itemPool[i].name.Visible = false
    end
    updateSpoofTag()
    end)
    if not okR and not rendererErrShown then
        rendererErrShown = true
        print("[main-render] " .. tostring(errR))
    end
end)

-- ============================================================
-- NICK SPOOF (fake nameplate above own character)
-- ============================================================

local spoofSq = new("Square")
spoofSq.Filled = true
spoofSq.Color = rgb(15, 15, 20)
spoofSq.Transparency = 0.1
spoofSq.Visible = false
objects[#objects + 1] = spoofSq

local spoofTxt = new("Text")
spoofTxt.Size = 14
spoofTxt.Center = true
spoofTxt.Outline = true
spoofTxt.Color = rgb(255, 255, 255)
spoofTxt.Visible = false
objects[#objects + 1] = spoofTxt

updateSpoofTag = function()
    local on = value("spoof_on", false)
    local fake = tostring(value("spoof_name", "Anonymous"))
    if fake == "" then fake = "Anonymous" end
    local show = on and alive()
    if show then
        local char = lp.Character
        local head = char and char:FindFirstChild("Head")
        show = head ~= nil
        if show then
            local hp, vis = proj(head.Position + Vector3.new(0, 3.2, 0))
            if vis then
                spoofSq.Position = Vector2.new(hp.X - 70, hp.Y - 9)
                spoofSq.Size = Vector2.new(140, 18)
                spoofSq.Visible = true
                spoofTxt.Text = fake
                spoofTxt.Position = Vector2.new(hp.X, hp.Y)
                spoofTxt.Visible = true
            else
                show = false
            end
        end
    end
    if not show then
        spoofSq.Visible = false
        spoofTxt.Visible = false
    end
end

-- ============================================================
-- AUTO BUY / AUTO HEAL
-- ============================================================

local ownedT = {}
local lastBuy, lastHeal, lastSkipMsg = 0, 0, 0
local shopPhase = nil

task.spawn(function()
    while running do
        if not alive() then return end
        local ok, err = pcall(function()
            local now = tick()
            local char = lp.Character
            local pg = lp:FindFirstChild("PlayerGui")
            local shopOpen = ws.CanUseShop and ws.CanUseShop.Value
            if shopPhase ~= shopOpen then
                shopPhase = shopOpen
                print("[main] shop " .. (shopOpen and "OPEN - auto-buy active" or "closed (wave) - auto-buy paused"))
            end
            if not shopOpen then return end

            if value("fr_heal", true) and char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                local hp, mx = hum and hum.Health or 0, hum and hum.MaxHealth or 1
                local pct = value("fr_healpct", 40)
                if mx > 0 and hp / mx * 100 < pct and now - lastHeal > 3 then
                    pcall(function()
                        rs.ShopSystem:FireServer("Buy", "FillHP")
                    end)
                    lastHeal = now
                    print("[main] healed")
                end
            end

            local wantItems = value("fr_buy", false)
            local wantUpgs = value("fr_buyupg", false)
            if (wantItems or wantUpgs) then
                local data = lp:FindFirstChild("Data")
                local money = data and data:FindFirstChild("MoneysInShop") and data.MoneysInShop.Value or 0

                local hwa = pg and pg:FindFirstChild("003-A")
                local sc = hwa and hwa:FindFirstChild("Main") and hwa.Main:FindFirstChild("ScrollingFrame")
                local mats = sc and sc:GetChildren() or {}

                local function shopCost(item)
                    for _, sf in ipairs(mats) do
                        if sf.ClassName == "ScrollingFrame" then
                            local f = sf:FindFirstChild(item)
                            if f then
                                local costLab = f:FindFirstChild("cost")
                                if costLab then
                                    local digits = tostring(costLab.Text):match("%d+")
                                    return digits and tonumber(digits) or -1
                                end
                                return -1
                            end
                        end
                    end
                    return nil
                end

                local function tryBuy(item)
                    if not value("buy_" .. item, false) and not value("buyu_" .. item, false) then return end
                    local owned = ownedT[item] == true
                    if not owned then
                        local bp = lp:FindFirstChild("Backpack")
                        if bp then
                            for _, t in ipairs(bp:GetChildren()) do
                                if t.ClassName == "Tool" and t.Name == item then owned = true break end
                            end
                        end
                        if not owned and data then
                            local dval = data:FindFirstChild(item)
                            if dval then
                                local v = 0
                                pcall(function() v = dval.Value or 0 end)
                                if v and v ~= 0 then owned = true end
                            end
                        end
                    end

                    local cost = shopCost(item)
                    if cost == nil then owned = true end

                    local skip = nil
                    if owned then skip = "already owned" end
                    if cost and cost < 0 then skip = "cost unknown" end
                    if cost and money and money < cost then skip = "not enough money" end
                    if not skip and now - lastBuy > 2 then
                        pcall(function()
                            rs.ShopSystem:FireServer("Buy", item)
                        end)
                        lastBuy = now
                        ownedT[item] = true
                        notify("Bought " .. item, "Blockade", 3)
                        print("[main] bought " .. item .. " (" .. tostring(cost) .. ")")
                        return true
                    elseif skip and now - lastSkipMsg > 5 then
                        lastSkipMsg = now
                        print("[main] buy skip: " .. skip .. " (" .. item .. ")")
                    end
                end

                local boughtOne = false
                if wantItems then
                    for _, item in ipairs(BUY_ITEMS) do
                        if tryBuy(item) then boughtOne = true break end
                    end
                end
                if not boughtOne and wantUpgs then
                    for _, item in ipairs(BUY_UPGRADES) do
                        if tryBuy(item) then break end
                    end
                end
            end
        end)
        if not ok then
            print("[main-auto] " .. tostring(err))
            task.wait(1)
        end
        task.wait(0.5)
    end
end)

-- ============================================================
-- STOP / REG
-- ============================================================

function mainStop()
    if not running then return end
    running = false
    for _, o in ipairs(objects) do
        pcall(function(x) x:Remove() end, o)
    end
    UI.RemoveTab("Blockade Main")
end

_G.blockade_main_reg = {
    conn = renderer,
    draws = objects,
    stop = function()
        mainStop()
    end
}
_G.bc_items = function()
    return itemsCache
end

print("[main] v5.9 loaded - mobs=" .. #mobsCache .. " items=" .. #itemsCache)