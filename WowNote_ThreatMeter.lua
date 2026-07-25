-- WowNote_ThreatMeter.lua
-- Native WoW 3.3.5a threat meter integrated into WowNote.
-- Threat acquisition behavior follows the public Omen 3.0.9 implementation:
-- UnitDetailedThreatSituation, event-coalesced scans, focus/target selection,
-- targettarget fallback polling, raid/pet scanning, TPS history and 110/130% aggro limits.
-- No Omen libraries, frames, globals, saved variables or assets are embedded.

local WN = WowNote_Internal or {}
local TM = {}
WowNoteThreatMeter = TM

local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local tonumber = tonumber
local math_floor = math.floor
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local string_format = string.format
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local unpack = unpack
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitHealth = UnitHealth
local UnitIsPlayer = UnitIsPlayer
local UnitPlayerControlled = UnitPlayerControlled
local UnitCanAttack = UnitCanAttack
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat

local THREAT_NEGATIVE_OFFSET = 410065408
local TARGETTARGET_INTERVAL = 0.5
local TPS_REFRESH_INTERVAL = 0.50
local SCAN_MIN_INTERVAL = 0.35
local THREAT_EVENT_MIN_INTERVAL = 0.20
local ROSTER_EVENT_MIN_INTERVAL = 0.75
local TARGET_EVENT_MIN_INTERVAL = 0.15
local NO_CANDIDATE_CLEAR_INTERVAL = 0.50
local MAX_BARS = 40
local MIN_BARS = 3

local CLASS_ORDER = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST",
    "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR", "PET", "*NOTINPARTY*",
}

local CLASS_LABELS = {
    DEATHKNIGHT = "Death Knight",
    DRUID = "Druid",
    HUNTER = "Hunter",
    MAGE = "Mage",
    PALADIN = "Paladin",
    PRIEST = "Priest",
    ROGUE = "Rogue",
    SHAMAN = "Shaman",
    WARLOCK = "Warlock",
    WARRIOR = "Warrior",
    PET = "Pets",
    ["*NOTINPARTY*"] = "Other units",
}

local TEXTURES = {
    Blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    Smooth = "Interface\\Buttons\\WHITE8X8",
    Minimalist = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    Charcoal = "Interface\\Tooltips\\UI-Tooltip-Background",
}

local SOUNDS = {
    ["Raid Warning"] = "Sound\\Interface\\RaidWarning.wav",
    ["Fel Nova"] = "Sound\\Spells\\SeepingGaseous_Fel_Nova.wav",
    ["Alarm Clock"] = "Sound\\Interface\\AlarmClockWarning3.wav",
    ["Bell"] = "Sound\\Doodad\\BellTollAlliance.wav",
}

local FRAME_STRATA_VALUES = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }

local DEFAULTS = {
    shown = true,
    alpha = 1,
    scale = 1,
    width = 250,
    numBars = 10,
    growUp = false,
    autocollapse = false,
    collapseHide = false,
    locked = false,
    point = "TOPLEFT",
    x = 420,
    y = -220,
    configPoint = "CENTER",
    configX = 0,
    configY = 0,
    useFocus = false,
    ignorePlayerPets = true,
    frameStrata = "MEDIUM",
    clampToScreen = true,
    clickThrough = false,
    testMode = false,
    background = {
        color = { r = 0.035, g = 0.035, b = 0.045, a = 0.94 },
        borderColor = { r = 0.92, g = 0.65, b = 0.18, a = 1 },
        inset = 4,
    },
    title = {
        show = true,
        height = 22,
        fontSize = 11,
        color = { r = 1, g = 0.82, b = 0.35, a = 1 },
    },
    bar = {
        height = 17,
        spacing = 2,
        fontSize = 10,
        texture = "Blizzard",
        animate = true,
        shortNumbers = true,
        showTPS = true,
        tpsWindow = 10,
        showHeadings = true,
        showPercent = true,
        showValue = true,
        useClassColors = true,
        useTankColor = false,
        alwaysShowSelf = true,
        showAggro = true,
        defaultColor = { r = 0.72, g = 0.16, b = 0.12, a = 1 },
        tankColor = { r = 0.12, g = 0.55, b = 0.92, a = 1 },
        aggroColor = { r = 0.92, g = 0.12, b = 0.12, a = 0.95 },
        petColor = { r = 0.66, g = 0.18, b = 0.90, a = 1 },
        fadeColor = { r = 0.42, g = 0.42, b = 0.42, a = 1 },
        classes = {
            DEATHKNIGHT = true,
            DRUID = true,
            HUNTER = true,
            MAGE = true,
            PALADIN = true,
            PRIEST = true,
            ROGUE = true,
            SHAMAN = true,
            WARLOCK = true,
            WARRIOR = true,
            PET = true,
            ["*NOTINPARTY*"] = true,
        },
    },
    showWith = {
        enabled = true,
        pet = true,
        alone = false,
        party = true,
        raid = true,
        hideWhileResting = true,
        hideInPVP = true,
        hideWhenOOC = false,
    },
    warnings = {
        enabled = true,
        sound = true,
        flash = true,
        shake = false,
        message = false,
        threshold = 90,
        soundName = "Fel Nova",
        disableWhileTanking = true,
    },
}

local state = {
    enabled = false,
    initialized = false,
    runtimeEvents = false,
    updatePending = false,
    autoCollapsed = false,
    currentMobUnit = nil,
    currentMobGUID = nil,
    currentTankGUID = nil,
    currentTankThreat = 0,
    topThreat = 0,
    targetPollElapsed = 0,
    tpsElapsed = 0,
    scanThrottleElapsed = 0,
    lastScanTime = 0,
    lastThreatEventRequest = 0,
    lastRosterEventRequest = 0,
    lastTargetEventRequest = 0,
    lastCandidateCheck = 0,
    cachedHasCandidate = false,
    lastNoCandidateClear = 0,
    barsShown = 0,
    inRaid = false,
    inParty = false,
    lastWarnMobGUID = nil,
    lastWarnPercent = 0,
    lastWarnTankGUID = nil,
    warnedOmenConflict = false,
    manualVisible = false,
}

local db
local mainFrame
local titleFrame
local titleText
local selfTankCheck
local headerFrame
local barsFrame
local resizeGrip
local configFrame
local configPages = {}
local configTabs = {}
local configControls = {}
local sliderCounter = 0
local dropdownCounter = 0
local profileDropdown
local profileNameEdit
local bars = {}
local LayoutBars
local sortList = {}
local threatValues = {}
local negativeThreat = {}
local guidNames = {}
local guidClasses = {}
local tpsSamples = {}
local tpsTimes = {}
local eventFrame = CreateFrame("Frame")
local throttleFrame = CreateFrame("Frame")
local tickerFrame = CreateFrame("Frame")
local animationFrame = CreateFrame("Frame")
local flashFrame
local shakeFrame
local testTick = 0
local aggroItemQueried = false

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote Threat:|r " .. tostring(message))
    end
end

local function AddCounter(name, amount)
    if WowNoteProfiler_AddCounter then WowNoteProfiler_AddCounter("ThreatMeter." .. tostring(name), amount or 1) end
end

local function SetGauge(name, value)
    if WowNoteProfiler_SetGauge then WowNoteProfiler_SetGauge("ThreatMeter." .. tostring(name), value or 0) end
end

local function DeepCopy(source)
    if type(source) ~= "table" then return source end
    local target = {}
    for key, value in pairs(source) do target[key] = DeepCopy(value) end
    return target
end

local function MergeDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local EnsureDatabase

local function CharacterKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Realm"
    return name .. " - " .. realm
end

local function ActiveSpecKey()
    if GetActiveTalentGroup then
        local ok, value = pcall(GetActiveTalentGroup)
        if ok and value then return tostring(value) end
    end
    return "1"
end

local function SelfTankStore()
    EnsureDatabase()
    local root = WowNoteDB.threatMeter
    if type(root.selfTankByCharacter) ~= "table" then root.selfTankByCharacter = {} end
    local character = CharacterKey()
    if type(root.selfTankByCharacter[character]) ~= "table" then root.selfTankByCharacter[character] = {} end
    return root.selfTankByCharacter[character]
end

local function IsSelfTankForCurrentSpec()
    local store = SelfTankStore()
    return store[ActiveSpecKey()] == true
end

local function SetSelfTankForCurrentSpec(enabled)
    local store = SelfTankStore()
    store[ActiveSpecKey()] = enabled and true or false
end

local function RefreshSelfTankCheck()
    if not selfTankCheck then return end
    selfTankCheck.refreshing = true
    selfTankCheck:SetChecked(IsSelfTankForCurrentSpec())
    selfTankCheck.refreshing = false
end

EnsureDatabase = function()
    if WN.InitDB then WN.InitDB() end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.threatMeter) ~= "table" then WowNoteDB.threatMeter = {} end
    local root = WowNoteDB.threatMeter

    if type(root.profiles) ~= "table" then
        local migrated = nil
        if root.width or root.bar or root.showWith or root.warnings then migrated = DeepCopy(root) end
        root.profiles = {}
        root.profileKeys = {}
        if migrated then root.profiles.Default = MergeDefaults(migrated, DeepCopy(DEFAULTS)) end
    end
    if type(root.profileKeys) ~= "table" then root.profileKeys = {} end
    if type(root.profiles.Default) ~= "table" then root.profiles.Default = DeepCopy(DEFAULTS) end
    root.profiles.Default = MergeDefaults(root.profiles.Default, DEFAULTS)

    local key = CharacterKey()
    local profileName = root.profileKeys[key] or "Default"
    if type(root.profiles[profileName]) ~= "table" then profileName = "Default" end
    root.profileKeys[key] = profileName
    root.profiles[profileName] = MergeDefaults(root.profiles[profileName], DEFAULTS)
    db = root.profiles[profileName]
    return db
end

local function CurrentProfileName()
    EnsureDatabase()
    return WowNoteDB.threatMeter.profileKeys[CharacterKey()] or "Default"
end

local function ResetTable(target)
    for key in pairs(target) do target[key] = nil end
end

local function CopyColor(color)
    return { r = color.r or 1, g = color.g or 1, b = color.b or 1, a = color.a or 1 }
end

local function TexturePath()
    EnsureDatabase()
    return TEXTURES[db.bar.texture] or TEXTURES.Blizzard
end

local function CacheUnit(unitId, forcedClass)
    if not unitId or not UnitExists(unitId) then return nil end
    local guid = UnitGUID(unitId)
    if not guid then return nil end
    local name = UnitName(unitId)
    if name then guidNames[guid] = name end
    local class = forcedClass
    if not class then
        local _, token = UnitClass(unitId)
        class = token
    end
    if class then guidClasses[guid] = class end
    return guid
end

local function RefreshRosterCache()
    state.inRaid = (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
    state.inParty = not state.inRaid and (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0

    CacheUnit("player")
    CacheUnit("pet", "PET")

    local index
    if state.inRaid then
        for index = 1, GetNumRaidMembers() do
            CacheUnit("raid" .. index)
            CacheUnit("raidpet" .. index, "PET")
        end
    elseif state.inParty then
        for index = 1, GetNumPartyMembers() do
            CacheUnit("party" .. index)
            CacheUnit("partypet" .. index, "PET")
        end
    end
end

local function IsEnabledInSettings()
    if WowNote_IsModuleEnabled then return WowNote_IsModuleEnabled("threatMeter") end
    if type(WowNoteDB) == "table" and type(WowNoteDB.modules) == "table" and WowNoteDB.modules.threatMeter ~= nil then
        return WowNoteDB.modules.threatMeter == true
    end
    return true
end

local function ShowRuleAllows(event)
    EnsureDatabase()
    if db.testMode then return db.shown == true end
    if not db.shown then return false end
    -- Explicit user actions (menu, slash command or Show button) must always
    -- open the meter, even when automatic solo/resting/OOC rules would hide it.
    if state.manualVisible then return true end
    local rules = db.showWith
    if not rules.enabled then return true end

    if rules.hideWhenOOC and not InCombatLockdown() and event ~= "PLAYER_REGEN_DISABLED" then return false end

    local show = (rules.pet and UnitExists("pet"))
        or (rules.party and state.inParty)
        or (rules.raid and state.inRaid)
        or (rules.alone and not state.inParty and not state.inRaid and not UnitExists("pet"))

    local _, instanceType = IsInInstance()
    if rules.hideWhileResting and IsResting() then show = false end
    if rules.hideInPVP and (instanceType == "pvp" or instanceType == "arena") then show = false end
    return show and true or false
end

local function RegisterRuntimeEvents(active)
    if active == state.runtimeEvents then return end
    state.runtimeEvents = active
    local events = {
        "UNIT_THREAT_LIST_UPDATE",
        "UNIT_THREAT_SITUATION_UPDATE",
        "PLAYER_TARGET_CHANGED",
    }
    local i
    if active then
        for i = 1, #events do eventFrame:RegisterEvent(events[i]) end
        if db and db.useFocus then eventFrame:RegisterEvent("UNIT_TARGET") end
    else
        for i = 1, #events do eventFrame:UnregisterEvent(events[i]) end
        eventFrame:UnregisterEvent("UNIT_TARGET")
        state.updatePending = false
        throttleFrame:Hide()
        tickerFrame:Hide()
        state.targetPollElapsed = 0
        state.tpsElapsed = 0
        state.scanThrottleElapsed = 0
        SetGauge("TargetTargetTimer", 0)
    end
    SetGauge("RuntimeEvents", active and 1 or 0)
end

local function ApplyPosition(offsetX, offsetY)
    if not mainFrame then return end
    EnsureDatabase()
    local restored = false
    if WowNote_RestoreWindowGeometry then
        restored = WowNote_RestoreWindowGeometry("ThreatMeter", mainFrame, {
            point = db.point or "CENTER",
            relativePoint = db.relativePoint or db.point or "CENTER",
            x = tonumber(db.x) or 0,
            y = tonumber(db.y) or 0,
        }, false)
        if restored and ((offsetX or 0) ~= 0 or (offsetY or 0) ~= 0) then
            local point, relativeTo, relativePoint, x, y = mainFrame:GetPoint(1)
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(point or "CENTER", relativeTo or UIParent, relativePoint or point or "CENTER", (x or 0) + (offsetX or 0), (y or 0) + (offsetY or 0))
        end
    end
    if not restored and not WowNote_RestoreWindowGeometry then
        mainFrame:ClearAllPoints()
        local point = db.point or "CENTER"
        mainFrame:SetPoint(point, UIParent, point, (tonumber(db.x) or 0) + (offsetX or 0), (tonumber(db.y) or 0) + (offsetY or 0))
    end
end

local function SavePosition()
    if not mainFrame or not UIParent then return end
    EnsureDatabase()
    if WowNote_SaveWindowGeometry then WowNote_SaveWindowGeometry("ThreatMeter", mainFrame, false) end
    local point, _, relativePoint, x, y = mainFrame:GetPoint(1)
    if point then
        db.point = point
        db.relativePoint = relativePoint or point
        db.x = tonumber(x) or 0
        db.y = tonumber(y) or 0
    end
end

local function SaveConfigPosition()
    if not configFrame or not UIParent then return end
    EnsureDatabase()
    if WowNote_SaveWindowGeometry then WowNote_SaveWindowGeometry("ThreatMeterConfig", configFrame, false) end
    local point, _, relativePoint, x, y = configFrame:GetPoint(1)
    if point then
        db.configPoint = point
        db.configRelativePoint = relativePoint or point
        db.configX = tonumber(x) or 0
        db.configY = tonumber(y) or 0
    end
end

local function SaveWindowState()
    EnsureDatabase()
    SavePosition()
    SaveConfigPosition()
end

local function StartTickerIfNeeded()
    if not state.enabled or not mainFrame or not mainFrame:IsShown() then
        tickerFrame:Hide()
        SetGauge("TargetTargetTimer", 0)
        return
    end
    local needsTPS = db.bar.showTPS and state.currentMobGUID ~= nil and state.barsShown > 0
    if (needsTPS or state.currentMobUnit == "targettarget" or db.testMode) then tickerFrame:Show() else tickerFrame:Hide() end
    SetGauge("TargetTargetTimer", state.currentMobUnit == "targettarget" and 1 or 0)
end

local function SetVisible(visible, autoCollapsed)
    if not mainFrame then return end
    state.autoCollapsed = autoCollapsed and true or false
    if visible then
        mainFrame:Show()
        RegisterRuntimeEvents(not db.testMode)
        StartTickerIfNeeded()
    else
        mainFrame:Hide()
        if state.autoCollapsed and state.enabled then
            RegisterRuntimeEvents(not db.testMode)
        else
            RegisterRuntimeEvents(false)
        end
        tickerFrame:Hide()
    end
    SetGauge("Visible", visible and 1 or 0)
end

local function ClearHistory()
    local i
    for i = #tpsSamples, 1, -1 do tpsSamples[i] = nil end
    for i = #tpsTimes, 1, -1 do tpsTimes[i] = nil end
    state.lastWarnMobGUID = nil
    state.lastWarnTankGUID = nil
    state.lastWarnPercent = 0
    SetGauge("TPSSamples", 0)
end

local function ClearBars(resetTitle)
    local i
    for i = 1, #bars do
        bars[i]:Hide()
        bars[i].guid = nil
    end
    state.barsShown = 0
    SetGauge("Bars", 0)
    if LayoutBars and mainFrame then LayoutBars(0) end
    if resetTitle and titleText then titleText:SetText("WowNote Threat Meter") end
    if db and db.autocollapse and db.collapseHide and db.shown and state.enabled and not state.manualVisible and ShowRuleAllows() then
        SetVisible(false, true)
    end
end

local function ApplyVisibility(event)
    if not state.enabled then
        SetVisible(false, false)
        return
    end
    if ShowRuleAllows(event) then
        if not state.autoCollapsed then SetVisible(true, false) end
    else
        SetVisible(false, false)
        ClearBars(false)
        ClearHistory()
    end
end

local function HasValidThreatCandidate()
    EnsureDatabase()
    if db.testMode then return true end
    local candidates
    if db.useFocus then
        candidates = { "focus", "focustarget", "target", "targettarget" }
    else
        candidates = { "target", "targettarget" }
    end
    local i
    for i = 1, #candidates do
        local unitId = candidates[i]
        if UnitExists(unitId) and not UnitIsPlayer(unitId) and UnitCanAttack("player", unitId) and (UnitHealth(unitId) or 0) > 0 then
            if not db.ignorePlayerPets or not UnitPlayerControlled(unitId) then return true end
        end
    end
    return false
end

local function HasValidThreatCandidateCached(force)
    local now = GetTime and GetTime() or 0
    if force or now - (state.lastCandidateCheck or 0) >= 0.20 then
        state.cachedHasCandidate = HasValidThreatCandidate() and true or false
        state.lastCandidateCheck = now
    end
    return state.cachedHasCandidate
end

local function RequestUpdate(reason)
    if not state.enabled or not mainFrame then return end
    if not mainFrame:IsShown() then
        if state.autoCollapsed and ShowRuleAllows(reason) then
            SetVisible(true, false)
        else
            return
        end
    end
    if reason ~= "testtick" and not HasValidThreatCandidateCached(reason == "PLAYER_TARGET_CHANGED" or reason == "target" or reason == "enable" or reason == "restore") then
        state.currentMobUnit = nil
        state.currentMobGUID = nil
        local now = GetTime and GetTime() or 0
        if state.barsShown > 0 or (now - (state.lastNoCandidateClear or 0)) >= NO_CANDIDATE_CLEAR_INTERVAL then
            ClearBars(false)
            ClearHistory()
            state.lastNoCandidateClear = now
        end
        StartTickerIfNeeded()
        return
    end
    if state.updatePending then
        AddCounter("CoalescedUpdates", 1)
        return
    end
    state.updatePending = true
    throttleFrame:Show()
end

local function FindThreatMob()
    local candidates
    if db.useFocus then
        candidates = { "focus", "focustarget", "target", "targettarget" }
    else
        candidates = { "target", "targettarget" }
    end
    local firstName
    local i
    for i = 1, #candidates do
        local unitId = candidates[i]
        if UnitExists(unitId) then
            local name = UnitName(unitId)
            if name and not firstName then firstName = name end
            CacheUnit(unitId)
            if not UnitIsPlayer(unitId) and UnitCanAttack("player", unitId) and (UnitHealth(unitId) or 0) > 0 then
                if not db.ignorePlayerPets or not UnitPlayerControlled(unitId) then
                    return unitId, UnitGUID(unitId), name
                end
            end
        end
    end
    return nil, nil, firstName
end

local function UpdateThreatForUnit(unitId, mobUnitId, forcedClass)
    if not unitId or not UnitExists(unitId) then return end
    local guid = CacheUnit(unitId, forcedClass)
    if not guid or threatValues[guid] ~= nil then return end
    local isTanking, _, _, _, threatValue = UnitDetailedThreatSituation(unitId, mobUnitId)
    if threatValue ~= nil then
        if threatValue < 0 then
            threatValue = threatValue + THREAT_NEGATIVE_OFFSET
            negativeThreat[guid] = true
        end
        if threatValue > state.topThreat then state.topThreat = threatValue end
        if isTanking then state.currentTankGUID = guid end
        threatValues[guid] = threatValue
    else
        threatValues[guid] = -1
    end
end

local function ScanPartyThreat(mob)
    local i
    if state.inRaid then
        for i = 1, GetNumRaidMembers() do
            UpdateThreatForUnit("raid" .. i, mob)
            UpdateThreatForUnit("raidpet" .. i, mob, "PET")
            UpdateThreatForUnit("raid" .. i .. "target", mob)
            UpdateThreatForUnit("raidpet" .. i .. "target", mob)
        end
    elseif state.inParty then
        for i = 1, GetNumPartyMembers() do
            UpdateThreatForUnit("party" .. i, mob)
            UpdateThreatForUnit("partypet" .. i, mob, "PET")
            UpdateThreatForUnit("party" .. i .. "target", mob)
            UpdateThreatForUnit("partypet" .. i .. "target", mob)
        end
    end

    if not state.inRaid then
        UpdateThreatForUnit("player", mob)
        UpdateThreatForUnit("pet", mob, "PET")
        UpdateThreatForUnit("pettarget", mob)
    end
    UpdateThreatForUnit("target", mob)
    UpdateThreatForUnit("targettarget", mob)
    UpdateThreatForUnit("focus", mob)
    UpdateThreatForUnit("focustarget", mob)
    UpdateThreatForUnit("mouseover", mob)
    UpdateThreatForUnit("mouseovertarget", mob)
end

local function AggroMultiplier(mob)
    if GetItemInfo and GetItemInfo(37727) and IsItemInRange then
        return IsItemInRange(37727, mob) == 1 and 1.1 or 1.3
    end
    if not aggroItemQueried and ItemRefTooltip and not ItemRefTooltip:IsVisible() then
        ItemRefTooltip:SetHyperlink("item:37727")
        aggroItemQueried = true
    end
    return CheckInteractDistance(mob, 3) and 1.1 or 1.3
end

local function FormatThreat(value)
    value = tonumber(value) or 0
    if db.bar.shortNumbers and value >= 100000 then return string_format("%.1fk", value / 100000) end
    return string_format("%d", math_floor(value / 100))
end

local function ClassColor(classToken)
    if classToken == "PET" then return db.bar.petColor end
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    return colors and colors[classToken] or nil
end

local function ShouldShowGuid(guid, myGUID)
    if guid == "AGGRO" then return db.bar.showAggro end
    if guid == myGUID and db.bar.alwaysShowSelf then return true end
    local class = guidClasses[guid]
    if class then return db.bar.classes[class] ~= false end
    return db.bar.classes["*NOTINPARTY*"] ~= false
end

local function BarColor(guid, myGUID)
    if guid == myGUID then return { r = 0, g = 0, b = 0, a = 1 } end
    if negativeThreat[guid] then return db.bar.fadeColor end
    if guid == "AGGRO" then return db.bar.aggroColor end
    if guid == state.currentTankGUID and db.bar.useTankColor then return db.bar.tankColor end
    local class = guidClasses[guid]
    if db.bar.useClassColors then
        local color = ClassColor(class)
        if color then return color end
    end
    return db.bar.defaultColor
end

local function CreateBar(index)
    if bars[index] then return bars[index] end
    local bar = CreateFrame("Frame", nil, barsFrame)
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    bar:SetBackdropColor(0.04, 0.04, 0.05, 0.9)
    bar:SetBackdropBorderColor(0.18, 0.18, 0.2, 1)

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    bar.fill:SetTexture(TexturePath())
    bar.fill:SetWidth(1)

    bar.marker = bar:CreateTexture(nil, "OVERLAY")
    bar.marker:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.marker:SetWidth(2)
    bar.marker:SetPoint("TOP", bar.fill, "TOPRIGHT", 0, 0)
    bar.marker:SetPoint("BOTTOM", bar.fill, "BOTTOMRIGHT", 0, 0)
    bar.marker:Hide()

    bar.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.nameText:SetPoint("LEFT", bar, "LEFT", 5, 0)
    bar.nameText:SetJustifyH("LEFT")

    bar.valueText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.valueText:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    bar.valueText:SetJustifyH("RIGHT")

    bar.tpsText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.tpsText:SetPoint("RIGHT", bar.valueText, "LEFT", -8, 0)
    bar.tpsText:SetJustifyH("RIGHT")

    bar.currentWidth = 1
    bar.targetWidth = 1
    bar:Hide()
    bars[index] = bar
    return bar
end

LayoutBars = function(barCount)
    if not mainFrame then return end
    EnsureDatabase()
    barCount = math_max(0, math_min(MAX_BARS, barCount or db.numBars))
    local titleHeight = db.title.show and db.title.height or 0
    local bodyBars = db.autocollapse and math_max(0, state.barsShown) or db.numBars
    local headerHeight = db.bar.showHeadings and bodyBars > 0 and db.bar.height or 0
    local bodyHeight = headerHeight + bodyBars * db.bar.height + math_max(0, bodyBars - 1) * db.bar.spacing + 8
    local totalHeight = titleHeight + bodyHeight
    mainFrame:SetWidth(db.width)
    mainFrame:SetHeight(math_max(40, totalHeight))

    titleFrame:ClearAllPoints()
    barsFrame:ClearAllPoints()
    if db.growUp then
        if db.title.show then
            titleFrame:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 0, 0)
            titleFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
            barsFrame:SetPoint("BOTTOMLEFT", titleFrame, "TOPLEFT", 0, 0)
            barsFrame:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
        else
            barsFrame:SetAllPoints(mainFrame)
        end
    else
        if db.title.show then
            titleFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
            titleFrame:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
            barsFrame:SetPoint("TOPLEFT", titleFrame, "BOTTOMLEFT", 0, 0)
            barsFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
        else
            barsFrame:SetAllPoints(mainFrame)
        end
    end

    titleFrame:SetHeight(math_max(0.01, titleHeight))
    if db.title.show then titleFrame:Show() else titleFrame:Hide() end

    headerFrame:ClearAllPoints()
    if db.growUp then
        headerFrame:SetPoint("BOTTOMLEFT", barsFrame, "BOTTOMLEFT", 4, 4)
        headerFrame:SetPoint("BOTTOMRIGHT", barsFrame, "BOTTOMRIGHT", -4, 4)
    else
        headerFrame:SetPoint("TOPLEFT", barsFrame, "TOPLEFT", 4, -4)
        headerFrame:SetPoint("TOPRIGHT", barsFrame, "TOPRIGHT", -4, -4)
    end
    headerFrame:SetHeight(db.bar.height)
    if db.bar.showTPS then headerFrame.tpsText:Show() else headerFrame.tpsText:Hide() end
    if db.bar.showValue and db.bar.showPercent then
        headerFrame.valueText:SetText("Threat [%]")
    elseif db.bar.showValue then
        headerFrame.valueText:SetText("Threat")
    elseif db.bar.showPercent then
        headerFrame.valueText:SetText("Threat %")
    else
        headerFrame.valueText:SetText("")
    end
    if db.bar.showHeadings and bodyBars > 0 then headerFrame:Show() else headerFrame:Hide() end

    local anchor = headerFrame
    local i
    for i = 1, MAX_BARS do
        local bar = CreateBar(i)
        bar:ClearAllPoints()
        bar:SetHeight(db.bar.height)
        bar.nameText:SetFont(STANDARD_TEXT_FONT, db.bar.fontSize, "OUTLINE")
        bar.valueText:SetFont(STANDARD_TEXT_FONT, db.bar.fontSize, "OUTLINE")
        bar.tpsText:SetFont(STANDARD_TEXT_FONT, db.bar.fontSize, "OUTLINE")
        bar.fill:SetTexture(TexturePath())
        if db.growUp then
            if i == 1 then
                if db.bar.showHeadings then bar:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, db.bar.spacing) else bar:SetPoint("BOTTOMLEFT", barsFrame, "BOTTOMLEFT", 4, 4) end
            else
                bar:SetPoint("BOTTOMLEFT", bars[i - 1], "TOPLEFT", 0, db.bar.spacing)
            end
        else
            if i == 1 then
                if db.bar.showHeadings then bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -db.bar.spacing) else bar:SetPoint("TOPLEFT", barsFrame, "TOPLEFT", 4, -4) end
            else
                bar:SetPoint("TOPLEFT", bars[i - 1], "BOTTOMLEFT", 0, -db.bar.spacing)
            end
        end
        bar:SetPoint("RIGHT", barsFrame, "RIGHT", -4, 0)
    end

    resizeGrip:ClearAllPoints()
    if db.growUp then resizeGrip:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -2, -2) else resizeGrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2) end
    ApplyPosition()
end

local function ApplyAppearance()
    if not mainFrame then return end
    EnsureDatabase()
    mainFrame:SetAlpha(db.alpha)
    mainFrame:SetScale(db.scale)
    mainFrame:SetFrameStrata(db.frameStrata)
    mainFrame:SetClampedToScreen(db.clampToScreen)
    mainFrame:SetBackdropColor(db.background.color.r, db.background.color.g, db.background.color.b, db.background.color.a)
    mainFrame:SetBackdropBorderColor(db.background.borderColor.r, db.background.borderColor.g, db.background.borderColor.b, db.background.borderColor.a)
    titleText:SetTextColor(db.title.color.r, db.title.color.g, db.title.color.b, db.title.color.a)
    titleText:SetFont(STANDARD_TEXT_FONT, db.title.fontSize, "OUTLINE")
    titleFrame:EnableMouse(not db.clickThrough)
    mainFrame:EnableMouse(not db.clickThrough)
    resizeGrip:EnableMouse(not db.locked and not db.clickThrough)
    if db.locked or db.clickThrough then resizeGrip:Hide() else resizeGrip:Show() end
    LayoutBars(db.numBars)
end

local function SetBarWidth(bar, width, immediate)
    width = math_max(1, width or 1)
    bar.targetWidth = width
    if immediate or not db.bar.animate then
        bar.currentWidth = width
        bar.fill:SetWidth(width)
    else
        animationFrame:Show()
    end
end

local function UpdateBarTexts(bar, guid, threat, tankThreat)
    local percent = tankThreat > 0 and threat / tankThreat * 100 or 0
    bar.nameText:SetText(guidNames[guid] or (guid == "AGGRO" and "Aggro limit" or "Unknown"))
    if db.bar.showValue and db.bar.showPercent then
        bar.valueText:SetText(FormatThreat(threat) .. string_format(" [%d%%]", math_floor(percent + 0.5)))
    elseif db.bar.showValue then
        bar.valueText:SetText(FormatThreat(threat))
    elseif db.bar.showPercent then
        bar.valueText:SetText(string_format("%d%%", math_floor(percent + 0.5)))
    else
        bar.valueText:SetText("")
    end
    if db.bar.showTPS then bar.tpsText:Show() else bar.tpsText:Hide() end
end

local function AddTPSSample(values, mobGUID)
    if state.lastWarnMobGUID and state.lastWarnMobGUID ~= mobGUID then ClearHistory() end
    local sample = {}
    local guid, value
    for guid, value in pairs(values) do
        if value and value >= 0 and guid ~= "AGGRO" then sample[guid] = value end
    end
    table_insert(tpsSamples, sample)
    table_insert(tpsTimes, GetTime())
    local cutoff = GetTime() - db.bar.tpsWindow - 2
    while tpsTimes[2] and tpsTimes[2] < cutoff do
        table_remove(tpsSamples, 1)
        table_remove(tpsTimes, 1)
    end
    SetGauge("TPSSamples", #tpsSamples)
end

local function IsPlayerTanking(myGUID)
    return myGUID and state.currentTankGUID == myGUID
end

local function EnsureFlashFrame()
    if flashFrame then return end
    flashFrame = CreateFrame("Frame", nil, UIParent)
    flashFrame:SetAllPoints(UIParent)
    flashFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    flashFrame:EnableMouse(false)
    flashFrame.texture = flashFrame:CreateTexture(nil, "BACKGROUND")
    flashFrame.texture:SetAllPoints(flashFrame)
    flashFrame.texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    flashFrame.texture:SetVertexColor(1, 0.05, 0.05, 0.34)
    flashFrame.elapsed = 0
    WowNoteProfiler_SetScript(flashFrame, "OnUpdate", "ThreatMeter.WarningFlash", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        local duration = 0.65
        if self.elapsed >= duration then self:Hide(); self.elapsed = 0; return end
        self:SetAlpha(1 - self.elapsed / duration)
    end)
    flashFrame:Hide()
end

local function EnsureShakeFrame()
    if shakeFrame then return end
    shakeFrame = CreateFrame("Frame")
    shakeFrame.elapsed = 0
    WowNoteProfiler_SetScript(shakeFrame, "OnUpdate", "ThreatMeter.WarningShake", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 0.55 then
            self:Hide()
            self.elapsed = 0
            ApplyPosition()
            return
        end
        local strength = 5 * (1 - self.elapsed / 0.55)
        ApplyPosition((math.random() * 2 - 1) * strength, (math.random() * 2 - 1) * strength)
    end)
    shakeFrame:Hide()
end

local function TriggerWarning(tankName)
    local warning = db.warnings
    if not warning.enabled then return end
    AddCounter("Warnings", 1)
    if warning.sound then
        local path = SOUNDS[warning.soundName] or SOUNDS["Fel Nova"]
        if path then PlaySoundFile(path) end
    end
    if warning.flash then
        EnsureFlashFrame()
        flashFrame.elapsed = 0
        flashFrame:SetAlpha(1)
        flashFrame:Show()
    end
    if warning.shake then
        EnsureShakeFrame()
        shakeFrame.elapsed = 0
        shakeFrame:Show()
    end
    if warning.message then
        local message = string_format("Passed %d%% of %s's threat!", warning.threshold, tankName or "the tank")
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["RAID_WARNING"])
        elseif UIErrorsFrame then
            UIErrorsFrame:AddMessage(message, 1, 0.2, 0.2, 1)
        end
    end
end

local function CheckWarning(myGUID, mobGUID, tankThreat)
    local myThreat = myGUID and threatValues[myGUID] or nil
    if not myThreat or myThreat < 0 or tankThreat <= 0 then return end
    local percent = myThreat / tankThreat * 100
    local warning = db.warnings
    if state.lastWarnMobGUID == mobGUID and percent >= warning.threshold and state.lastWarnPercent < warning.threshold then
        if not warning.disableWhileTanking or not IsPlayerTanking(myGUID) then
            TriggerWarning(guidNames[state.currentTankGUID or state.lastWarnTankGUID])
        end
    end
    state.lastWarnMobGUID = mobGUID
    state.lastWarnTankGUID = state.currentTankGUID
    state.lastWarnPercent = percent
end

local function BuildTestData()
    ResetTable(threatValues)
    ResetTable(negativeThreat)
    ResetTable(sortList)
    local myGUID = UnitGUID("player") or "TEST_PLAYER"
    local myName = UnitName("player") or "You"
    guidNames[myGUID] = myName
    local _, myClass = UnitClass("player")
    guidClasses[myGUID] = myClass or "PALADIN"
    local names = { "Aegis", "Brann", "Cindara", "Dorn", "Elowen", "Falk", "Grom", "Helia", "Ivar", "Jaina", "Korin", "Lyria", "Merek", "Nora", "Orin" }
    local i
    state.topThreat = 1500000
    state.currentTankGUID = "TEST_1"
    for i = 1, math_min(db.numBars + 5, #names) do
        local guid = "TEST_" .. i
        threatValues[guid] = 1500000 - (i - 1) * 78000
        guidNames[guid] = names[i]
        guidClasses[guid] = CLASS_ORDER[((i - 1) % 10) + 1]
    end
    threatValues[myGUID] = 965000
    threatValues.AGGRO = 1650000
    guidNames.AGGRO = "Aggro limit"
    guidClasses.AGGRO = "AGGRO"
    state.currentMobGUID = "TEST_MOB"
    state.currentMobUnit = nil
    state.currentTankThreat = threatValues[state.currentTankGUID]
    titleText:SetText("Threat Meter - Test Mode")
end

local function SortThreat()
    ResetTable(sortList)
    local guid, value
    for guid, value in pairs(threatValues) do
        if value and value >= 0 then table_insert(sortList, guid) end
    end
    table_sort(sortList, function(a, b)
        local av = threatValues[a] or -1
        local bv = threatValues[b] or -1
        if av == bv then return tostring(guidNames[a] or a) < tostring(guidNames[b] or b) end
        return av > bv
    end)
end

local function UpdateDisplayedBars()
    local myGUID = UnitGUID("player") or "TEST_PLAYER"
    SortThreat()
    if #sortList == 0 then
        ClearBars(false)
        return
    end

    local top = threatValues[sortList[1]] or 1
    if top <= 0 then top = 1 end
    state.topThreat = top
    local tankThreat = state.currentTankThreat
    if not tankThreat or tankThreat <= 0 then tankThreat = top end

    local available = db.numBars
    local selected = {}
    local hasSelf = false
    local i
    for i = 1, #sortList do
        local guid = sortList[i]
        if ShouldShowGuid(guid, myGUID) then
            if guid == myGUID then hasSelf = true end
            if #selected < available then table_insert(selected, guid) end
        end
    end
    if db.bar.alwaysShowSelf and threatValues[myGUID] and threatValues[myGUID] >= 0 and not hasSelf then
        if #selected >= available then selected[#selected] = myGUID else table_insert(selected, myGUID) end
    elseif db.bar.alwaysShowSelf and threatValues[myGUID] and threatValues[myGUID] >= 0 then
        local visible = false
        for i = 1, #selected do if selected[i] == myGUID then visible = true break end end
        if not visible then
            if #selected >= available then selected[#selected] = myGUID else table_insert(selected, myGUID) end
        end
    end

    state.barsShown = #selected
    for i = 1, #selected do
        local guid = selected[i]
        local bar = CreateBar(i)
        local threat = threatValues[guid] or 0
        local color = BarColor(guid, myGUID)
        local maxWidth = math_max(1, db.width - 10)
        local width = maxWidth * threat / top
        bar.guid = guid
        UpdateBarTexts(bar, guid, threat, tankThreat)
        bar.fill:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
        if guid == myGUID then
            bar:SetBackdropColor(0, 0, 0, 1)
            bar:SetBackdropBorderColor(1, 1, 1, 1)
            bar.nameText:SetTextColor(1, 1, 1, 1)
            bar.valueText:SetTextColor(1, 1, 1, 1)
            bar.tpsText:SetTextColor(1, 1, 1, 1)
            bar.marker:SetVertexColor(1, 1, 1, 1)
            bar.marker:Show()
        else
            bar:SetBackdropColor(0.035, 0.035, 0.045, 0.9)
            bar:SetBackdropBorderColor(0.18, 0.18, 0.2, 1)
            bar.nameText:SetTextColor(1, 1, 1, 1)
            bar.valueText:SetTextColor(1, 1, 1, 1)
            bar.tpsText:SetTextColor(1, 1, 1, 1)
            bar.marker:Hide()
        end
        SetBarWidth(bar, width, false)
        bar:Show()
    end
    for i = #selected + 1, #bars do bars[i]:Hide(); bars[i].guid = nil end
    SetGauge("Bars", state.barsShown)
    LayoutBars(state.barsShown)
    if db.autocollapse and db.collapseHide and state.barsShown == 0 then SetVisible(false, true) end
end

local function ScanThreat()
    if not state.enabled or not mainFrame or not mainFrame:IsShown() then return end
    EnsureDatabase()
    if not db.testMode and not HasValidThreatCandidate() then
        state.currentMobUnit = nil
        state.currentMobGUID = nil
        ClearBars(false)
        ClearHistory()
        StartTickerIfNeeded()
        return
    end
    AddCounter("Scans", 1)
    ResetTable(threatValues)
    ResetTable(negativeThreat)
    state.topThreat = -1
    state.currentTankGUID = nil
    state.currentTankThreat = 0

    if db.testMode then
        BuildTestData()
        UpdateDisplayedBars()
        SetGauge("ScannedUnits", #sortList)
        StartTickerIfNeeded()
        return
    end

    local mob, mobGUID, fallbackName = FindThreatMob()
    if not mob then
        state.currentMobUnit = nil
        state.currentMobGUID = nil
        titleText:SetText(fallbackName or "WowNote Threat Meter")
        ClearBars(false)
        ClearHistory()
        StartTickerIfNeeded()
        return
    end

    if state.currentMobGUID and state.currentMobGUID ~= mobGUID then ClearHistory() end
    state.currentMobUnit = mob
    state.currentMobGUID = mobGUID
    titleText:SetText(UnitName(mob) or fallbackName or "Threat Meter")
    threatValues[mobGUID] = -1

    local mobTarget = mob .. "target"
    local mobTargetGUID = CacheUnit(mobTarget)
    ScanPartyThreat(mob)
    UpdateThreatForUnit(mobTarget, mob)

    local tankThreat
    if state.currentTankGUID then tankThreat = threatValues[state.currentTankGUID] end
    if (not tankThreat or tankThreat < 0) and mobTargetGUID then tankThreat = threatValues[mobTargetGUID] end
    if not tankThreat or tankThreat < 0 then tankThreat = state.topThreat end
    if not tankThreat or tankThreat < 0 then tankThreat = 0 end
    state.currentTankThreat = tankThreat

    if db.bar.showAggro and tankThreat > 0 then
        threatValues.AGGRO = tankThreat * AggroMultiplier(mob)
        guidNames.AGGRO = "Aggro limit"
        guidClasses.AGGRO = "AGGRO"
    end

    AddTPSSample(threatValues, mobGUID)
    CheckWarning(UnitGUID("player"), mobGUID, tankThreat)
    UpdateDisplayedBars()
    SetGauge("ScannedUnits", #sortList)
    StartTickerIfNeeded()
end

local function UpdateTPS()
    if not db or not db.bar.showTPS or not mainFrame or not mainFrame:IsShown() then return end
    AddCounter("TPSUpdates", 1)
    if db.testMode then
        local i
        for i = 1, #bars do if bars[i]:IsShown() then bars[i].tpsText:SetText(tostring(1250 - i * 55)) end end
        return
    end
    local cutoff = GetTime() - db.bar.tpsWindow
    while tpsTimes[2] and cutoff > tpsTimes[2] do
        table_remove(tpsSamples, 1)
        table_remove(tpsTimes, 1)
    end
    local count = #tpsTimes
    local i
    if count == 0 or cutoff <= (tpsTimes[1] or cutoff) then
        for i = 1, #bars do if bars[i]:IsShown() then bars[i].tpsText:SetText("??") end end
        return
    end
    if count == 1 then
        for i = 1, #bars do if bars[i]:IsShown() then bars[i].tpsText:SetText("0") end end
        return
    end
    local span = tpsTimes[2] - tpsTimes[1]
    local ratio = span > 0 and (cutoff - tpsTimes[1]) / span or 0
    for i = 1, #bars do
        local bar = bars[i]
        if bar:IsShown() then
            local guid = bar.guid
            if guid == "AGGRO" then
                bar.tpsText:SetText("--")
            else
                local first = tpsSamples[1] and tpsSamples[1][guid]
                local second = tpsSamples[2] and tpsSamples[2][guid]
                local final = tpsSamples[count] and tpsSamples[count][guid]
                if first and second and final then
                    local startThreat = (second - first) * ratio + first
                    bar.tpsText:SetText(string_format("%d", math_floor((final - startThreat) / db.bar.tpsWindow / 100 + 0.5)))
                else
                    bar.tpsText:SetText("??")
                end
            end
        end
    end
end

local function CreateMainFrame()
    if mainFrame then return end
    EnsureDatabase()
    mainFrame = CreateFrame("Frame", "WowNoteThreatMeterFrame", UIParent)
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    mainFrame:SetMinResize(140, 65)
    mainFrame:SetMaxResize(600, 900)
    mainFrame:SetToplevel(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)

    titleFrame = CreateFrame("Frame", nil, mainFrame)
    titleFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    titleFrame:SetBackdropColor(0.08, 0.065, 0.035, 0.98)
    titleFrame:EnableMouse(true)
    titleFrame:RegisterForDrag("LeftButton")
    titleFrame:SetScript("OnDragStart", function(self)
        if not db.locked and not db.clickThrough then
            mainFrame:StartMoving()
            self.positionSaveElapsed = 0
            self:SetScript("OnUpdate", function(owner, elapsed)
                owner.positionSaveElapsed = (owner.positionSaveElapsed or 0) + elapsed
                if owner.positionSaveElapsed >= 0.10 then
                    owner.positionSaveElapsed = 0
                    SavePosition()
                end
            end)
        end
    end)
    titleFrame:SetScript("OnDragStop", function(self)
        mainFrame:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        SavePosition()
    end)
    mainFrame:SetScript("OnHide", function() SavePosition() end)
    titleFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then WowNote_OpenThreatMeterConfig() end
    end)

    titleText = titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("LEFT", titleFrame, "LEFT", 7, 0)
    titleText:SetPoint("RIGHT", titleFrame, "RIGHT", -128, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetText("WowNote Threat Meter")

    selfTankCheck = CreateFrame("CheckButton", "WowNoteThreatMeterSelfTankCheck", titleFrame, "UICheckButtonTemplate")
    selfTankCheck:SetWidth(20)
    selfTankCheck:SetHeight(20)
    selfTankCheck:SetPoint("RIGHT", titleFrame, "RIGHT", -83, 0)
    selfTankCheck.text = selfTankCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selfTankCheck.text:SetPoint("RIGHT", selfTankCheck, "LEFT", 1, 0)
    selfTankCheck.text:SetText("Tank")
    selfTankCheck:SetScript("OnClick", function(self)
        if self.refreshing then return end
        SetSelfTankForCurrentSpec(self:GetChecked() and true or false)
        if WowNoteThreatHelper and WowNoteThreatHelper.Refresh then WowNoteThreatHelper:Refresh() end
        RequestUpdate("selftank")
    end)
    selfTankCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Mark myself as tank", 1, 0.82, 0)
        GameTooltip:AddLine("Saved separately for each talent specialization.", 1, 1, 1)
        GameTooltip:Show()
    end)
    selfTankCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    RefreshSelfTankCheck()

    local helperButton = CreateFrame("Button", "WowNoteThreatMeterHelperButton", titleFrame)
    helperButton:SetWidth(18)
    helperButton:SetHeight(18)
    helperButton:SetPoint("RIGHT", titleFrame, "RIGHT", -38, 0)
    helperButton:EnableMouse(true)
    helperButton:SetNormalTexture("Interface\\Icons\\INV_Shield_06")
    helperButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    helperButton:SetScript("OnClick", function() if WowNote_OpenThreatHelper then WowNote_OpenThreatHelper() end end)
    helperButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Threat Helper", 1, 0.82, 0)
        GameTooltip:AddLine("Open combat-safe raid utility buttons.", 1, 1, 1)
        GameTooltip:Show()
    end)
    helperButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local configButton = CreateFrame("Button", "WowNoteThreatMeterConfigButton", titleFrame)
    configButton:SetWidth(18)
    configButton:SetHeight(18)
    configButton:SetPoint("RIGHT", titleFrame, "RIGHT", -19, 0)
    configButton:EnableMouse(true)
    configButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    configButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    configButton:SetScript("OnClick", function() WowNote_OpenThreatMeterConfig() end)
    configButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Threat Meter settings", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    configButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local close = CreateFrame("Button", nil, titleFrame, "UIPanelCloseButton")
    close:SetWidth(20)
    close:SetHeight(20)
    close:SetPoint("RIGHT", titleFrame, "RIGHT", 2, 0)
    close:SetScript("OnClick", function() TM:SetShown(false) end)

    barsFrame = CreateFrame("Frame", nil, mainFrame)

    headerFrame = CreateFrame("Frame", nil, barsFrame)
    headerFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    headerFrame:SetBackdropColor(0, 0, 0, 0.55)
    headerFrame.nameText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerFrame.nameText:SetPoint("LEFT", headerFrame, "LEFT", 5, 0)
    headerFrame.nameText:SetText("Name")
    headerFrame.valueText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerFrame.valueText:SetPoint("RIGHT", headerFrame, "RIGHT", -5, 0)
    headerFrame.valueText:SetText("Threat")
    headerFrame.tpsText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerFrame.tpsText:SetPoint("RIGHT", headerFrame.valueText, "LEFT", -22, 0)
    headerFrame.tpsText:SetText("TPS")

    resizeGrip = CreateFrame("Button", nil, mainFrame)
    resizeGrip:SetWidth(16)
    resizeGrip:SetHeight(16)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    resizeGrip:SetScript("OnMouseDown", function()
        if db.locked or db.clickThrough then return end
        mainFrame:StartSizing(db.growUp and "TOPRIGHT" or "BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        db.width = math_floor(mainFrame:GetWidth() + 0.5)
        local titleHeight = db.title.show and db.title.height or 0
        local bodyHeight = mainFrame:GetHeight() - titleHeight - 8 - (db.bar.showHeadings and db.bar.height or 0)
        db.numBars = math_max(MIN_BARS, math_min(MAX_BARS, math_floor((bodyHeight + db.bar.spacing) / (db.bar.height + db.bar.spacing))))
        SavePosition()
        ApplyAppearance()
        RequestUpdate("resize")
    end)

    ApplyAppearance()
    mainFrame:Hide()
end

local function SetOption(setter, value, refreshThreat)
    EnsureDatabase()
    setter(value)
    ApplyAppearance()
    if refreshThreat then RequestUpdate("option") end
    if configFrame and configFrame:IsShown() then TM:RefreshConfig() end
    ApplyVisibility("option")
end

local function MakeCheck(parent, label, x, y, getter, setter, tooltip)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check:SetWidth(24)
    check:SetHeight(24)
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label:SetText(label)
    check.getter = getter
    check:SetScript("OnClick", function(self)
        if self.refreshing then return end
        setter(self:GetChecked() and true or false)
    end)
    if tooltip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tooltip, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    table_insert(configControls, check)
    return check
end

local function MakeSlider(parent, label, x, y, width, minValue, maxValue, step, getter, setter, formatText)
    sliderCounter = sliderCounter + 1
    local slider = CreateFrame("Slider", "WowNoteThreatMeterSlider" .. sliderCounter, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(width)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    _G[slider:GetName() .. "Low"]:SetText(tostring(minValue))
    _G[slider:GetName() .. "High"]:SetText(tostring(maxValue))
    slider.getter = getter
    slider.formatText = formatText
    slider:SetScript("OnValueChanged", function(self, value)
        local stepped = math_floor(value / step + 0.5) * step
        _G[self:GetName() .. "Text"]:SetText(label .. ": " .. (formatText and formatText(stepped) or tostring(stepped)))
        if not self.refreshing then setter(stepped) end
    end)
    table_insert(configControls, slider)
    return slider
end

local function MakeDropdown(parent, label, x, y, width, valuesGetter, getter, setter)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetText(label)
    dropdownCounter = dropdownCounter + 1
    local dropdown = CreateFrame("Frame", "WowNoteThreatMeterDropdown" .. dropdownCounter, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(dropdown, width)
    dropdown.getter = getter
    dropdown.valuesGetter = valuesGetter
    UIDropDownMenu_Initialize(dropdown, function()
        local values = valuesGetter()
        local i
        for i = 1, #values do
            local value = values[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = value
            info.value = value
            info.checked = getter() == value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, value)
                UIDropDownMenu_SetText(dropdown, value)
                setter(value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    table_insert(configControls, dropdown)
    return dropdown
end

local function MakeColorButton(parent, label, x, y, getter, setter)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetText(label)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(28)
    button:SetHeight(18)
    button:SetPoint("LEFT", text, "RIGHT", 8, 0)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    button.getter = getter
    button.swatch = button:CreateTexture(nil, "ARTWORK")
    button.swatch:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.swatch:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button:SetScript("OnClick", function()
        local current = CopyColor(getter())
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - (current.a or 1)
        ColorPickerFrame.previousValues = { current.r, current.g, current.b, current.a }
        ColorPickerFrame.func = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = 1 - (OpacitySliderFrame:GetValue() or 0)
            setter({ r = r, g = g, b = b, a = a })
        end
        ColorPickerFrame.opacityFunc = ColorPickerFrame.func
        ColorPickerFrame.cancelFunc = function(previous)
            setter({ r = previous[1], g = previous[2], b = previous[3], a = previous[4] })
        end
        ColorPickerFrame:SetColorRGB(current.r, current.g, current.b)
        ColorPickerFrame:Show()
    end)
    table_insert(configControls, button)
    return button
end

local function SectionTitle(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function CreateGeneralPage(page)
    SectionTitle(page, "Window", 18, -18)
    MakeCheck(page, "Show threat meter", 18, -42, function() return db.shown end, function(v) TM:SetShown(v) end)
    MakeCheck(page, "Lock window", 18, -70, function() return db.locked end, function(v) SetOption(function(x) db.locked = x end, v, false) end)
    MakeCheck(page, "Click-through", 18, -98, function() return db.clickThrough end, function(v) SetOption(function(x) db.clickThrough = x end, v, false) end)
    MakeCheck(page, "Clamp to screen", 18, -126, function() return db.clampToScreen end, function(v) SetOption(function(x) db.clampToScreen = x end, v, false) end)
    MakeCheck(page, "Grow upward", 18, -154, function() return db.growUp end, function(v)
        local left = mainFrame and mainFrame:GetLeft() or db.x
        local top = mainFrame and mainFrame:GetTop() or nil
        local bottom = mainFrame and mainFrame:GetBottom() or nil
        db.growUp = v
        db.x = left or db.x
        if v then
            db.y = bottom or 220
        else
            local parentTop = UIParent:GetTop() or UIParent:GetHeight()
            db.y = top and (top - parentTop) or -220
        end
        ApplyAppearance(); RequestUpdate("grow")
    end)
    MakeCheck(page, "Autocollapse", 18, -182, function() return db.autocollapse end, function(v) SetOption(function(x) db.autocollapse = x end, v, true) end)
    MakeCheck(page, "Hide on zero bars", 18, -210, function() return db.collapseHide end, function(v) SetOption(function(x) db.collapseHide = x end, v, true) end)
    MakeCheck(page, "Use focus first", 18, -238, function() return db.useFocus end, function(v)
        db.useFocus = v
        if state.runtimeEvents then if v then eventFrame:RegisterEvent("UNIT_TARGET") else eventFrame:UnregisterEvent("UNIT_TARGET") end end
        RequestUpdate("focus")
    end, "Checks focus and focustarget before target and targettarget.")
    MakeCheck(page, "Ignore player-controlled pets", 18, -266, function() return db.ignorePlayerPets end, function(v) db.ignorePlayerPets = v; RequestUpdate("pets") end)
    MakeCheck(page, "Test mode", 18, -294, function() return db.testMode end, function(v) TM:SetTestMode(v) end)

    SectionTitle(page, "Dimensions and appearance", 330, -18)
    MakeSlider(page, "Opacity", 330, -54, 230, 0.2, 1, 0.05, function() return db.alpha end, function(v) db.alpha = v; ApplyAppearance() end, function(v) return string_format("%.2f", v) end)
    MakeSlider(page, "Scale", 330, -108, 230, 0.5, 2, 0.05, function() return db.scale end, function(v) db.scale = v; ApplyAppearance() end, function(v) return string_format("%.2f", v) end)
    MakeSlider(page, "Width", 330, -162, 230, 140, 500, 5, function() return db.width end, function(v) db.width = v; ApplyAppearance(); RequestUpdate("width") end)
    MakeSlider(page, "Visible bars", 330, -216, 230, MIN_BARS, MAX_BARS, 1, function() return db.numBars end, function(v) db.numBars = v; ApplyAppearance(); RequestUpdate("bars") end)
    MakeSlider(page, "Title height", 330, -270, 230, 14, 34, 1, function() return db.title.height end, function(v) db.title.height = v; ApplyAppearance() end)
    MakeCheck(page, "Show title bar", 330, -316, function() return db.title.show end, function(v) db.title.show = v; ApplyAppearance() end)
    MakeDropdown(page, "Frame strata", 330, -360, 180, function() return FRAME_STRATA_VALUES end, function() return db.frameStrata end, function(v) db.frameStrata = v; ApplyAppearance() end)
    MakeColorButton(page, "Background", 330, -435, function() return db.background.color end, function(v) db.background.color = v; ApplyAppearance() end)
    MakeColorButton(page, "Border", 330, -463, function() return db.background.borderColor end, function(v) db.background.borderColor = v; ApplyAppearance() end)
    MakeColorButton(page, "Title text", 330, -491, function() return db.title.color end, function(v) db.title.color = v; ApplyAppearance() end)
end

local function CreateBarsPage(page)
    SectionTitle(page, "Bar display", 18, -18)
    MakeCheck(page, "Show headings", 18, -42, function() return db.bar.showHeadings end, function(v) db.bar.showHeadings = v; ApplyAppearance(); RequestUpdate("headings") end)
    MakeCheck(page, "Show threat values", 18, -70, function() return db.bar.showValue end, function(v) db.bar.showValue = v; RequestUpdate("value") end)
    MakeCheck(page, "Show threat percent", 18, -98, function() return db.bar.showPercent end, function(v) db.bar.showPercent = v; RequestUpdate("percent") end)
    MakeCheck(page, "Show TPS", 18, -126, function() return db.bar.showTPS end, function(v) db.bar.showTPS = v; RequestUpdate("tps"); StartTickerIfNeeded() end)
    MakeCheck(page, "Short numbers", 18, -154, function() return db.bar.shortNumbers end, function(v) db.bar.shortNumbers = v; RequestUpdate("numbers") end)
    MakeCheck(page, "Animate bars", 18, -182, function() return db.bar.animate end, function(v) db.bar.animate = v; RequestUpdate("animate") end)
    MakeCheck(page, "Use class colors", 18, -210, function() return db.bar.useClassColors end, function(v) db.bar.useClassColors = v; RequestUpdate("colors") end)
    MakeCheck(page, "Use tank color", 18, -238, function() return db.bar.useTankColor end, function(v) db.bar.useTankColor = v; RequestUpdate("tankcolor") end)
    MakeCheck(page, "Show aggro limit", 18, -266, function() return db.bar.showAggro end, function(v) db.bar.showAggro = v; RequestUpdate("aggro") end)
    MakeCheck(page, "Always show self", 18, -294, function() return db.bar.alwaysShowSelf end, function(v) db.bar.alwaysShowSelf = v; RequestUpdate("self") end)

    MakeSlider(page, "Bar height", 18, -344, 240, 10, 30, 1, function() return db.bar.height end, function(v) db.bar.height = v; ApplyAppearance(); RequestUpdate("height") end)
    MakeSlider(page, "Bar spacing", 18, -398, 240, 0, 8, 1, function() return db.bar.spacing end, function(v) db.bar.spacing = v; ApplyAppearance() end)
    MakeSlider(page, "Font size", 18, -452, 240, 8, 18, 1, function() return db.bar.fontSize end, function(v) db.bar.fontSize = v; ApplyAppearance() end)
    MakeSlider(page, "TPS window", 18, -506, 240, 3, 30, 1, function() return db.bar.tpsWindow end, function(v) db.bar.tpsWindow = v; ClearHistory(); RequestUpdate("tpswindow") end, function(v) return tostring(v) .. " s" end)

    SectionTitle(page, "Texture and colors", 330, -18)
    MakeDropdown(page, "Status bar texture", 330, -45, 180, function()
        local values = {}
        local key
        for key in pairs(TEXTURES) do table_insert(values, key) end
        table_sort(values)
        return values
    end, function() return db.bar.texture end, function(v) db.bar.texture = v; ApplyAppearance(); RequestUpdate("texture") end)
    MakeColorButton(page, "Default bar", 330, -120, function() return db.bar.defaultColor end, function(v) db.bar.defaultColor = v; RequestUpdate("color") end)
    MakeColorButton(page, "Tank bar", 330, -148, function() return db.bar.tankColor end, function(v) db.bar.tankColor = v; RequestUpdate("color") end)
    MakeColorButton(page, "Aggro limit", 330, -176, function() return db.bar.aggroColor end, function(v) db.bar.aggroColor = v; RequestUpdate("color") end)
    MakeColorButton(page, "Pet bar", 330, -204, function() return db.bar.petColor end, function(v) db.bar.petColor = v; RequestUpdate("color") end)
    MakeColorButton(page, "Temporary reduction", 330, -232, function() return db.bar.fadeColor end, function(v) db.bar.fadeColor = v; RequestUpdate("color") end)

    SectionTitle(page, "Visible classes", 330, -276)
    local i
    for i = 1, #CLASS_ORDER do
        local class = CLASS_ORDER[i]
        local column = (i - 1) % 2
        local row = math_floor((i - 1) / 2)
        MakeCheck(page, CLASS_LABELS[class], 330 + column * 145, -300 - row * 28,
            function() return db.bar.classes[class] ~= false end,
            function(v) db.bar.classes[class] = v; RequestUpdate("class") end)
    end
end

local function CreateVisibilityPage(page)
    SectionTitle(page, "Automatic visibility", 18, -18)
    MakeCheck(page, "Enable visibility rules", 18, -42, function() return db.showWith.enabled end, function(v) db.showWith.enabled = v; ApplyVisibility("rules") end)
    MakeCheck(page, "Show while alone", 18, -82, function() return db.showWith.alone end, function(v) db.showWith.alone = v; ApplyVisibility("alone") end)
    MakeCheck(page, "Show with pet", 18, -110, function() return db.showWith.pet end, function(v) db.showWith.pet = v; ApplyVisibility("pet") end)
    MakeCheck(page, "Show in party", 18, -138, function() return db.showWith.party end, function(v) db.showWith.party = v; ApplyVisibility("party") end)
    MakeCheck(page, "Show in raid", 18, -166, function() return db.showWith.raid end, function(v) db.showWith.raid = v; ApplyVisibility("raid") end)
    MakeCheck(page, "Hide while resting", 330, -82, function() return db.showWith.hideWhileResting end, function(v) db.showWith.hideWhileResting = v; ApplyVisibility("resting") end)
    MakeCheck(page, "Hide in battlegrounds/arenas", 330, -110, function() return db.showWith.hideInPVP end, function(v) db.showWith.hideInPVP = v; ApplyVisibility("pvp") end)
    MakeCheck(page, "Hide outside combat", 330, -138, function() return db.showWith.hideWhenOOC end, function(v) db.showWith.hideWhenOOC = v; ApplyVisibility("combat") end)

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -225)
    note:SetWidth(590)
    note:SetJustifyH("LEFT")
    note:SetJustifyV("TOP")
    note:SetText("When the meter is manually hidden or hidden by these rules, full threat scans, TPS history and targettarget polling stop. If 'Hide on zero bars' is active, threat events remain registered only as a lightweight wake-up signal; the meter performs no polling while collapsed.")
end

local function CreateWarningsPage(page)
    SectionTitle(page, "Threat warnings", 18, -18)
    MakeCheck(page, "Enable warnings", 18, -42, function() return db.warnings.enabled end, function(v) db.warnings.enabled = v end)
    MakeCheck(page, "Play sound", 18, -82, function() return db.warnings.sound end, function(v) db.warnings.sound = v end)
    MakeCheck(page, "Flash screen", 18, -110, function() return db.warnings.flash end, function(v) db.warnings.flash = v end)
    MakeCheck(page, "Shake meter", 18, -138, function() return db.warnings.shake end, function(v) db.warnings.shake = v end)
    MakeCheck(page, "Show raid-warning text", 18, -166, function() return db.warnings.message end, function(v) db.warnings.message = v end)
    MakeCheck(page, "Disable while tanking", 18, -194, function() return db.warnings.disableWhileTanking end, function(v) db.warnings.disableWhileTanking = v end)
    MakeSlider(page, "Warning threshold", 330, -62, 240, 50, 130, 1, function() return db.warnings.threshold end, function(v) db.warnings.threshold = v end, function(v) return tostring(v) .. "%" end)
    MakeDropdown(page, "Warning sound", 330, -130, 180, function()
        local values = {}
        local key
        for key in pairs(SOUNDS) do table_insert(values, key) end
        table_sort(values)
        return values
    end, function() return db.warnings.soundName end, function(v) db.warnings.soundName = v; if SOUNDS[v] then PlaySoundFile(SOUNDS[v]) end end)

    local test = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    test:SetWidth(150)
    test:SetHeight(24)
    test:SetPoint("TOPLEFT", page, "TOPLEFT", 330, -215)
    test:SetText("Test warning")
    test:SetScript("OnClick", function() TriggerWarning(UnitName("player") or "Tank") end)
end

local function ProfileNames()
    EnsureDatabase()
    local names = {}
    local name
    for name in pairs(WowNoteDB.threatMeter.profiles) do table_insert(names, name) end
    table_sort(names)
    return names
end

local function SwitchProfile(name)
    EnsureDatabase()
    if type(WowNoteDB.threatMeter.profiles[name]) ~= "table" then return end
    WowNoteDB.threatMeter.profileKeys[CharacterKey()] = name
    db = MergeDefaults(WowNoteDB.threatMeter.profiles[name], DEFAULTS)
    ClearHistory()
    ApplyAppearance()
    ApplyVisibility("profile")
    RequestUpdate("profile")
    TM:RefreshConfig()
    Print("Profile changed to " .. name .. ".")
end

local function CreateProfilesPage(page)
    SectionTitle(page, "Profiles", 18, -18)
    profileDropdown = MakeDropdown(page, "Current profile", 18, -48, 220, ProfileNames, CurrentProfileName, SwitchProfile)

    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -132)
    label:SetText("Profile name")
    profileNameEdit = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    profileNameEdit:SetWidth(220)
    profileNameEdit:SetHeight(24)
    profileNameEdit:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -152)
    profileNameEdit:SetAutoFocus(false)

    local function Button(text, x, y, onClick)
        local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        button:SetWidth(130)
        button:SetHeight(24)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        return button
    end

    Button("Create new", 18, -195, function()
        local name = profileNameEdit:GetText() or ""
        name = string.gsub(name, "^%s+", "")
        name = string.gsub(name, "%s+$", "")
        if name == "" then Print("Enter a profile name."); return end
        EnsureDatabase()
        if WowNoteDB.threatMeter.profiles[name] then Print("That profile already exists."); return end
        WowNoteDB.threatMeter.profiles[name] = DeepCopy(DEFAULTS)
        SwitchProfile(name)
    end)

    Button("Copy current", 160, -195, function()
        local name = profileNameEdit:GetText() or ""
        name = string.gsub(name, "^%s+", "")
        name = string.gsub(name, "%s+$", "")
        if name == "" then Print("Enter a profile name."); return end
        EnsureDatabase()
        if WowNoteDB.threatMeter.profiles[name] then Print("That profile already exists."); return end
        WowNoteDB.threatMeter.profiles[name] = DeepCopy(db)
        SwitchProfile(name)
    end)

    Button("Reset current", 302, -195, function()
        local name = CurrentProfileName()
        WowNoteDB.threatMeter.profiles[name] = DeepCopy(DEFAULTS)
        SwitchProfile(name)
    end)

    Button("Delete current", 444, -195, function()
        local name = CurrentProfileName()
        if name == "Default" then Print("The Default profile cannot be deleted."); return end
        WowNoteDB.threatMeter.profiles[name] = nil
        SwitchProfile("Default")
    end)

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -260)
    note:SetWidth(590)
    note:SetJustifyH("LEFT")
    note:SetText("Profiles are stored inside WowNoteDB. Each character can select its own profile without creating a separate Omen database.")
end

local function ShowConfigPage(index)
    local i
    for i = 1, #configPages do
        if i == index then configPages[i]:Show(); PanelTemplates_SelectTab(configTabs[i]) else configPages[i]:Hide(); PanelTemplates_DeselectTab(configTabs[i]) end
    end
end

local function CreateConfigFrame()
    if configFrame then return end
    EnsureDatabase()
    configFrame = CreateFrame("Frame", "WowNoteThreatMeterConfigFrame", UIParent)
    configFrame:SetWidth(670)
    configFrame:SetHeight(620)
    if WowNote_RestoreWindowGeometry then
        WowNote_RestoreWindowGeometry("ThreatMeterConfig", configFrame, {
            point = db.configPoint or "CENTER",
            relativePoint = db.configRelativePoint or db.configPoint or "CENTER",
            x = db.configX or 0,
            y = db.configY or 0,
        }, false)
    else
        configFrame:SetPoint(db.configPoint or "CENTER", UIParent, db.configRelativePoint or db.configPoint or "CENTER", db.configX or 0, db.configY or 0)
    end
    configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    configFrame:SetToplevel(true)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self.positionSaveElapsed = 0
        self:SetScript("OnUpdate", function(owner, elapsed)
            owner.positionSaveElapsed = (owner.positionSaveElapsed or 0) + elapsed
            if owner.positionSaveElapsed >= 0.10 then
                owner.positionSaveElapsed = 0
                SaveConfigPosition()
            end
        end)
    end)
    configFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        SaveConfigPosition()
    end)
    configFrame:SetScript("OnHide", function() SaveConfigPosition() end)
    configFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, -16)
    title:SetText("WowNote Threat Meter")
    local subtitle = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
    subtitle:SetText("Omen-style native threat tracking")

    local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)

    local tabs = { "General", "Bars", "Visibility", "Warnings", "Profiles" }
    local creators = { CreateGeneralPage, CreateBarsPage, CreateVisibilityPage, CreateWarningsPage, CreateProfilesPage }
    local i
    for i = 1, #tabs do
        local tab = CreateFrame("Button", "WowNoteThreatMeterConfigTab" .. i, configFrame, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(tabs[i])
        tab:SetScript("OnClick", function(self) ShowConfigPage(self:GetID()) end)
        if i == 1 then tab:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 18, -48) else tab:SetPoint("LEFT", configTabs[i - 1], "RIGHT", -14, 0) end
        PanelTemplates_TabResize(tab, 0)
        configTabs[i] = tab

        local page = CreateFrame("Frame", nil, configFrame)
        page:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 16, -82)
        page:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMRIGHT", -16, 16)
        configPages[i] = page
        creators[i](page)
    end
    PanelTemplates_SetNumTabs(configFrame, #tabs)
    ShowConfigPage(1)
    configFrame:SetScript("OnShow", function() TM:RefreshConfig() end)
    configFrame:Hide()
end

function TM:RefreshConfig()
    if not configFrame then return end
    EnsureDatabase()
    local i
    for i = 1, #configControls do
        local control = configControls[i]
        if control.GetObjectType and control:GetObjectType() == "CheckButton" then
            control.refreshing = true
            control:SetChecked(control.getter and control.getter() and true or false)
            control.refreshing = false
        elseif control.GetObjectType and control:GetObjectType() == "Slider" then
            control.refreshing = true
            local value = control.getter and control.getter() or 0
            control:SetValue(value)
            control.refreshing = false
        elseif control.swatch and control.getter then
            local color = control.getter()
            control.swatch:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
        elseif control.valuesGetter and control.getter then
            local value = control.getter()
            UIDropDownMenu_SetSelectedValue(control, value)
            UIDropDownMenu_SetText(control, value)
        end
    end
end

function TM:SetShown(shown)
    EnsureDatabase()
    db.shown = shown and true or false
    if WowNote_SetWindowVisibility then WowNote_SetWindowVisibility("ThreatMeter", db.shown) end
    state.autoCollapsed = false
    state.manualVisible = db.shown
    if db.shown then
        -- A direct user action must display the frame immediately. Automatic
        -- visibility rules are only used for login and event-driven showing.
        SetVisible(true, false)
        RequestUpdate("show")
    else
        SetVisible(false, false)
        ClearBars(false)
        ClearHistory()
    end
    if configFrame and configFrame:IsShown() then self:RefreshConfig() end
end

function TM:SetTestMode(enabled)
    EnsureDatabase()
    if enabled and not state.enabled then
        Print("The Threat Meter module is disabled in WowNote Settings.")
        return
    end
    db.testMode = enabled and true or false
    ClearHistory()
    if db.testMode then
        db.shown = true
        RegisterRuntimeEvents(false)
        SetVisible(true, false)
        RequestUpdate("test")
    else
        RefreshRosterCache()
        ApplyVisibility("testoff")
        RequestUpdate("testoff")
    end
    if configFrame and configFrame:IsShown() then self:RefreshConfig() end
end

function TM:SetEnabled(enabled)
    EnsureDatabase()
    enabled = enabled and true or false
    if enabled == state.enabled then
        if enabled then ApplyVisibility("enable") end
        return
    end
    state.enabled = enabled
    if enabled then
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
        eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
        eventFrame:RegisterEvent("UNIT_PET")
        eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
        eventFrame:RegisterEvent("PLAYER_PET_CHANGED")
        eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
        RefreshRosterCache()
        CreateMainFrame()
        ApplyAppearance()
        ApplyVisibility("enable")
        RequestUpdate("enable")
        if IsAddOnLoaded and IsAddOnLoaded("Omen") and not state.warnedOmenConflict then
            state.warnedOmenConflict = true
            Print("Omen is also loaded. Both meters are independent; disable one if you do not need both.")
        end
    else
        state.manualVisible = false
        RegisterRuntimeEvents(false)
        eventFrame:UnregisterAllEvents()
        eventFrame:RegisterEvent("PLAYER_LOGIN")
        tickerFrame:Hide()
        throttleFrame:Hide()
        animationFrame:Hide()
        if mainFrame then mainFrame:Hide() end
        if configFrame then configFrame:Hide() end
        ClearHistory()
        ClearBars(false)
    end
    SetGauge("Enabled", enabled and 1 or 0)
end

function WowNote_ThreatMeter_SetEnabled(enabled)
    TM:SetEnabled(enabled)
end

function WowNote_OpenThreatMeter()
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("threatMeter") then
        Print("The Threat Meter module is disabled in WowNote Settings.")
        return
    end
    CreateMainFrame()
    TM:SetEnabled(true)
    TM:SetShown(true)
end

function WowNote_ToggleThreatMeter()
    EnsureDatabase()
    if db.shown and mainFrame and mainFrame:IsShown() then TM:SetShown(false) else WowNote_OpenThreatMeter() end
end

function WowNote_OpenThreatMeterConfig()
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("threatMeter") then
        Print("The Threat Meter module is disabled in WowNote Settings.")
        return
    end
    CreateMainFrame()
    CreateConfigFrame()
    configFrame:Show()
    if WN.RaiseFrame then WN.RaiseFrame(configFrame) end
end

function WowNote_ThreatMeter_IsSelfTank()
    return IsSelfTankForCurrentSpec()
end

function WowNote_ThreatMeter_SetSelfTank(enabled)
    SetSelfTankForCurrentSpec(enabled)
    RefreshSelfTankCheck()
    if WowNoteThreatHelper and WowNoteThreatHelper.Refresh then WowNoteThreatHelper:Refresh() end
    RequestUpdate("selftank")
end

function WowNote_ThreatMeterHandleSlash(arguments)
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("threatMeter") then
        Print("The Threat Meter module is disabled in WowNote Settings.")
        return
    end
    local text = string.lower(tostring(arguments or ""))
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "show" then
        WowNote_OpenThreatMeter()
    elseif text == "hide" then
        TM:SetShown(false)
    elseif text == "toggle" then
        WowNote_ToggleThreatMeter()
    elseif text == "config" or text == "options" or text == "settings" then
        WowNote_OpenThreatMeterConfig()
    elseif text == "test" or text == "test on" then
        TM:SetTestMode(true)
        Print("Test mode enabled.")
    elseif text == "test off" then
        TM:SetTestMode(false)
        Print("Test mode disabled.")
    elseif text == "reset" then
        local name = CurrentProfileName()
        WowNoteDB.threatMeter.profiles[name] = DeepCopy(DEFAULTS)
        SwitchProfile(name)
        Print("Current profile reset.")
    else
        WowNote_OpenThreatMeter()
    end
end

WowNoteProfiler_SetScript(throttleFrame, "OnUpdate", "ThreatMeter.Scan", function(self, elapsed)
    if not state.enabled or not mainFrame or not mainFrame:IsShown() then
        self:Hide()
        state.updatePending = false
        state.scanThrottleElapsed = 0
        return
    end
    state.scanThrottleElapsed = (state.scanThrottleElapsed or 0) + (elapsed or 0)
    local now = GetTime and GetTime() or 0
    local sinceLast = now - (state.lastScanTime or 0)
    if sinceLast < SCAN_MIN_INTERVAL and state.scanThrottleElapsed < SCAN_MIN_INTERVAL then
        return
    end
    self:Hide()
    state.scanThrottleElapsed = 0
    state.updatePending = false
    state.lastScanTime = now
    if db.testMode or HasValidThreatCandidateCached(true) then
        ScanThreat()
    else
        state.currentMobUnit = nil
        state.currentMobGUID = nil
        ClearBars(false)
        ClearHistory()
        StartTickerIfNeeded()
    end
end)
throttleFrame:Hide()

WowNoteProfiler_SetScript(tickerFrame, "OnUpdate", "ThreatMeter.Ticker", function(self, elapsed)
    if not state.enabled or not mainFrame or not mainFrame:IsShown() then self:Hide(); return end
    if db.testMode then
        testTick = testTick + elapsed
        if testTick >= 1 then testTick = 0; RequestUpdate("testtick") end
    end
    if state.currentMobUnit == "targettarget" and not db.testMode then
        state.targetPollElapsed = state.targetPollElapsed + elapsed
        if state.targetPollElapsed >= TARGETTARGET_INTERVAL then
            state.targetPollElapsed = 0
            RequestUpdate("targettarget")
        end
    else
        state.targetPollElapsed = 0
    end
    if db.bar.showTPS then
        state.tpsElapsed = state.tpsElapsed + elapsed
        if state.tpsElapsed >= TPS_REFRESH_INTERVAL then
            state.tpsElapsed = 0
            UpdateTPS()
        end
    else
        state.tpsElapsed = 0
    end
    if not db.testMode and state.currentMobUnit ~= "targettarget" and (not db.bar.showTPS or state.currentMobGUID == nil or state.barsShown == 0) then self:Hide() end
end)
tickerFrame:Hide()

WowNoteProfiler_SetScript(animationFrame, "OnUpdate", "ThreatMeter.BarAnimation", function(self, elapsed)
    local any = false
    local speed = math_min(1, elapsed * 12)
    local i
    for i = 1, #bars do
        local bar = bars[i]
        if bar:IsShown() then
            local current = bar.currentWidth or 1
            local target = bar.targetWidth or current
            if math_abs(target - current) > 0.5 then
                current = current + (target - current) * speed
                bar.currentWidth = current
                bar.fill:SetWidth(math_max(1, current))
                any = true
            else
                bar.currentWidth = target
                bar.fill:SetWidth(math_max(1, target))
            end
        end
    end
    if not any then self:Hide() end
end)
animationFrame:Hide()

WowNoteProfiler_SetScript(eventFrame, "OnEvent", "ThreatMeter.Events", function(self, event, arg1)
    AddCounter("Events", 1)
    local now = GetTime and GetTime() or 0
    if event == "PLAYER_LOGIN" then
        EnsureDatabase()
        db.testMode = false
        local restoreVisible = WowNote_GetWindowVisibility and WowNote_GetWindowVisibility("ThreatMeter")
        if restoreVisible == nil then restoreVisible = db.shown == true end
        db.shown = restoreVisible and true or false
        if WowNote_SetWindowVisibility then WowNote_SetWindowVisibility("ThreatMeter", db.shown) end
        state.manualVisible = db.shown
        CreateMainFrame()
        if IsEnabledInSettings() then TM:SetEnabled(true) else TM:SetEnabled(false) end
        if state.enabled and db.shown then
            SetVisible(true, false)
            RequestUpdate("restore")
        end
        return
    end
    if not state.enabled then return end

    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "UNIT_PET" or event == "UNIT_NAME_UPDATE" or event == "PLAYER_PET_CHANGED" then
        if now - (state.lastRosterEventRequest or 0) < ROSTER_EVENT_MIN_INTERVAL then
            AddCounter("RosterEventsCoalesced", 1)
            RequestUpdate(event)
            return
        end
        state.lastRosterEventRequest = now
        RefreshRosterCache()
        ApplyVisibility(event)
        RequestUpdate(event)
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshRosterCache()
        ClearHistory()
        ApplyVisibility(event)
        RequestUpdate(event)
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        RefreshSelfTankCheck()
        if WowNoteThreatHelper and WowNoteThreatHelper.Refresh then WowNoteThreatHelper:Refresh() end
        RequestUpdate(event)
    elseif event == "PLAYER_UPDATE_RESTING" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        ApplyVisibility(event)
        if mainFrame and mainFrame:IsShown() then RequestUpdate(event) end
    elseif event == "UNIT_TARGET" then
        if db.useFocus and (arg1 == "focus" or arg1 == "target") then RequestUpdate(event) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if now - (state.lastTargetEventRequest or 0) < TARGET_EVENT_MIN_INTERVAL then
            AddCounter("TargetEventsCoalesced", 1)
            return
        end
        state.lastTargetEventRequest = now
        state.currentMobUnit = nil
        state.targetPollElapsed = 0
        ClearHistory()
        RequestUpdate(event)
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        if not db.testMode and UnitAffectingCombat and not UnitAffectingCombat("player") then
            return
        end
        if now - (state.lastThreatEventRequest or 0) < THREAT_EVENT_MIN_INTERVAL then
            AddCounter("ThreatEventsCoalesced", 1)
            if not state.updatePending and (now - (state.lastScanTime or 0)) >= SCAN_MIN_INTERVAL then
                RequestUpdate(event)
            end
            return
        end
        state.lastThreatEventRequest = now
        if HasValidThreatCandidateCached(false) then
            if state.autoCollapsed and ShowRuleAllows(event) then SetVisible(true, false) end
            RequestUpdate(event)
        elseif mainFrame and mainFrame:IsShown() then
            if state.barsShown > 0 or (now - (state.lastNoCandidateClear or 0)) >= NO_CANDIDATE_CLEAR_INTERVAL then
                ClearBars(false)
                ClearHistory()
                state.lastNoCandidateClear = now
            end
        end
    end
end)
local persistenceFrame = CreateFrame("Frame")
persistenceFrame:RegisterEvent("PLAYER_LOGOUT")
persistenceFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
persistenceFrame:SetScript("OnEvent", function()
    SaveWindowState()
end)

eventFrame:RegisterEvent("PLAYER_LOGIN")
