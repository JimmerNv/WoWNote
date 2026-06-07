-- WowNote_PallyPowerCompat.lua
-- PallyPower compatible assignment bridge and integrated WowNote PallyBuffs UI for WoW 3.3.5a.

local ADDON_NAME = ...
local WN = WowNote_Internal or {}

local PP_PREFIX = "PLPWR"
local MAX_CLASSES = 11
local MAX_AURAS = 7

local CLASS_NAMES = {
    [1] = "Warrior",
    [2] = "Rogue",
    [3] = "Priest",
    [4] = "Druid",
    [5] = "Paladin",
    [6] = "Hunter",
    [7] = "Mage",
    [8] = "Warlock",
    [9] = "Shaman",
    [10] = "Death Knight",
    [11] = "Pet",
}

local BLESSING_NAMES = {
    [0] = "None",
    [1] = "Wisdom",
    [2] = "Might",
    [3] = "Kings",
    [4] = "Sanctuary",
}

local DEFAULT_BLESSING_ICONS = {
    [1] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofWisdom",
    [2] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings",
    [3] = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings",
    [4] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofSanctuary",
}

local AURA_NAMES = {
    [0] = "None",
    [1] = "Devotion Aura",
    [2] = "Retribution Aura",
    [3] = "Concentration Aura",
    [4] = "Shadow Resistance Aura",
    [5] = "Frost Resistance Aura",
    [6] = "Fire Resistance Aura",
    [7] = "Crusader Aura",
}

local DEFAULT_AURA_ICONS = {
    [1] = "Interface\\Icons\\Spell_Holy_DevotionAura",
    [2] = "Interface\\Icons\\Spell_Holy_AuraOfLight",
    [3] = "Interface\\Icons\\Spell_Holy_MindSooth",
    [4] = "Interface\\Icons\\Spell_Shadow_SealOfKings",
    [5] = "Interface\\Icons\\Spell_Frost_WizardMark",
    [6] = "Interface\\Icons\\Spell_Fire_SealOfFire",
    [7] = "Interface\\Icons\\Spell_Holy_CrusaderAura",
}

local DEFAULT_CLASS_ICONS = {
    [1] = "Interface\\AddOns\\WoWNote\\Icons\\Warrior",
    [2] = "Interface\\AddOns\\WoWNote\\Icons\\Rogue",
    [3] = "Interface\\AddOns\\WoWNote\\Icons\\Priest",
    [4] = "Interface\\AddOns\\WoWNote\\Icons\\Druid",
    [5] = "Interface\\AddOns\\WoWNote\\Icons\\Paladin",
    [6] = "Interface\\AddOns\\WoWNote\\Icons\\Hunter",
    [7] = "Interface\\AddOns\\WoWNote\\Icons\\Mage",
    [8] = "Interface\\AddOns\\WoWNote\\Icons\\Warlock",
    [9] = "Interface\\AddOns\\WoWNote\\Icons\\Shaman",
    [10] = "Interface\\AddOns\\WoWNote\\Icons\\DeathKnight",
    [11] = "Interface\\AddOns\\WoWNote\\Icons\\Pet",
}

AllPallys = AllPallys or {}
SyncList = SyncList or {}
ChatControl = ChatControl or {}
PallyPower_Assignments = PallyPower_Assignments or {}
PallyPower_NormalAssignments = PallyPower_NormalAssignments or {}
PallyPower_AuraAssignments = PallyPower_AuraAssignments or {}
PP_Symbols = PP_Symbols or 0

local SAMPLE_PALLIES = { "Sampleadin", "Bufflord" }

local EnsureConfig

local state = {
    pallies = {},
    assignments = {},
    normalAssignments = {},
    auras = {},
    freeassign = {},
    symbols = {},
    spellInfo = {},
    auraInfo = {},
}

local frame
local scrollChild
local statusText
local infoText
local testModeButton
local freeAssignButton
local buffFrameButton
local buffFrame
local buffFrameButtons = {}
local autoBuffedList = {}
local previousAutoBuffedUnit
local rows = {}
local Refresh
local RefreshBuffFrame

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WowNote|r: " .. tostring(msg))
    end
end

local function MakeButton(parent, text, width, height)
    local button
    if WN.MakeButton then
        button = WN.MakeButton(parent, text, width, height)
    else
        button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetWidth(width or 80)
        button:SetHeight(height or 24)
        button:SetText(text or "")
    end
    if button and button.RegisterForClicks then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    return button
end

local function SetButtonEnabled(button, enabled)
    if not button then return end
    if button.SetEnabled then
        button:SetEnabled(enabled and true or false)
    elseif enabled then
        if button.Enable then button:Enable() end
        button:EnableMouse(true)
        button:SetAlpha(1)
    else
        if button.Disable then button:Disable() end
        button:EnableMouse(false)
        button:SetAlpha(0.55)
    end
end

local function RaiseFrame(f)
    if WN.RaiseFrame then
        WN.RaiseFrame(f)
    else
        f:SetFrameStrata("DIALOG")
        f:Raise()
    end
end

local function SetStatus(text)
    if statusText then
        statusText:SetText(tostring(text or ""))
    end
end

local function AddTooltip(widget, title, text)
    if not widget then return end
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "WowNote PallyBuffs", 1, 1, 1)
        if text and text ~= "" then
            GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function AddActionTooltip(widget, title, actions)
    if not widget then return end
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "WowNote PallyBuffs", 1, 1, 1)
        for _, action in ipairs(actions or {}) do
            if action.key and action.text then
                GameTooltip:AddDoubleLine("|cffffd100" .. action.key .. "|r", action.text, 1, 1, 1, 0.85, 0.85, 0.85)
            elseif action.text then
                GameTooltip:AddLine(action.text, 0.85, 0.85, 0.85, true)
            end
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function TableContains(list, value)
    if type(list) ~= "table" then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function SyncAdd(name)
    if not name or name == "" or TableContains(SyncList, name) then return end
    table.insert(SyncList, name)
    table.sort(SyncList)
end

local function EnsureNativeTables(name)
    if not name or name == "" then return end
    AllPallys[name] = AllPallys[name] or {}
    PallyPower_Assignments[name] = PallyPower_Assignments[name] or {}
    PallyPower_NormalAssignments[name] = PallyPower_NormalAssignments[name] or {}
    if PallyPower_AuraAssignments[name] == nil then PallyPower_AuraAssignments[name] = 0 end
    for classId = 1, MAX_CLASSES do
        if PallyPower_Assignments[name][classId] == nil then
            PallyPower_Assignments[name][classId] = 0
        end
    end
end

local function IsSenderLeader(sender)
    if not sender or sender == "" then return false end
    if sender == UnitName("player") then
        return (IsPartyLeader and IsPartyLeader()) or (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())
    end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 and GetRaidRosterInfo then
        for i = 1, GetNumRaidMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name == sender then return tonumber(rank) and tonumber(rank) > 0 end
        end
    end
    return false
end

local function IncomingCanControl(sender, targetName)
    if not sender or not targetName then return false end
    if sender == targetName then return true end
    if IsSenderLeader(sender) then return true end
    if EnsureConfig().freeAssign ~= false then return true end
    if AllPallys[targetName] and AllPallys[targetName].freeassign == true then return true end
    if state.freeassign[targetName] == true then return true end
    return false
end

EnsureConfig = function()
    WowNoteDB = WowNoteDB or {}
    WowNoteDB.pallyCompat = WowNoteDB.pallyCompat or {}
    if WowNoteDB.pallyCompat.testMode == nil then
        WowNoteDB.pallyCompat.testMode = false
    end
    if WowNoteDB.pallyCompat.freeAssign == nil then
        WowNoteDB.pallyCompat.freeAssign = true
    end
    if WowNoteDB.pallyCompat.buffFrameVisible == nil then
        WowNoteDB.pallyCompat.buffFrameVisible = true
    end
    return WowNoteDB.pallyCompat
end

local function IsTestModeEnabled()
    return EnsureConfig().testMode == true
end

local function SetTestModeEnabled(value)
    EnsureConfig().testMode = value and true or false
    if testModeButton then
        if EnsureConfig().testMode then
            testModeButton:SetText("Test On")
        else
            testModeButton:SetText("Test Off")
        end
    end
end

local SendPP
local EnsurePally

local function UpdateFreeAssignButton()
    if freeAssignButton then
        freeAssignButton:SetText(EnsureConfig().freeAssign and "Free On" or "Free Off")
    end
end

local function UpdateBuffFrameButton()
    if buffFrameButton then
        buffFrameButton:SetText(EnsureConfig().buffFrameVisible and "Buff On" or "Buff Off")
    end
end

local function IsFreeAssignEnabled()
    return EnsureConfig().freeAssign ~= false
end

local function SetFreeAssignEnabled(value, announce)
    local cfg = EnsureConfig()
    cfg.freeAssign = value and true or false
    local player = UnitName("player")
    if player then
        state.freeassign[player] = cfg.freeAssign
    end
    UpdateFreeAssignButton()
    if announce then
        SendPP(cfg.freeAssign and "FREEASSIGN YES" or "FREEASSIGN NO")
        SetStatus(cfg.freeAssign and "Free assignment enabled." or "Free assignment disabled.")
    end
end

local function GetDistribution()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "pvp" then return "BATTLEGROUND" end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
    return "PARTY"
end

SendPP = function(message)
    message = tostring(message or "")
    if message == "" then return end
    if PallyPower and PallyPower.SendMessage then
        PallyPower:SendMessage(message)
    else
        SendAddonMessage(PP_PREFIX, message, GetDistribution())
    end
end

local function GetAssignmentPayload(name)
    local parts = {}
    local assignment = state.assignments[name] or {}
    for classId = 1, MAX_CLASSES do
        local value = tonumber(assignment[classId]) or 0
        if value <= 0 then
            parts[classId] = "n"
        else
            parts[classId] = tostring(value)
        end
    end
    return table.concat(parts, "")
end

local function IsPlayerPaladin()
    local _, classToken = UnitClass("player")
    return classToken == "PALADIN"
end

local function SpellKnownByIds(ids)
    if type(ids) ~= "table" then return false end
    for _, spellId in ipairs(ids) do
        if IsSpellKnown and IsSpellKnown(spellId) then
            return true
        elseif IsPlayerSpell and IsPlayerSpell(spellId) then
            return true
        end
    end
    return false
end

local BLESSING_SPELL_IDS = {
    [1] = { 25894, 25918, 27143, 48936, 48938 },
    [2] = { 25782, 25916, 27141, 48932, 48934 },
    [3] = { 25898 },
    [4] = { 25899 },
    [5] = { 25890, 27145 },
    [6] = { 25895, 25896 },
}

local AURA_SPELL_IDS = {
    [1] = { 465, 10290, 643, 10291, 1032, 10292, 48941, 48942 },
    [2] = { 7294, 10298, 10299, 10300, 10301, 27150, 54043 },
    [3] = { 19746 },
    [4] = { 19876, 19895, 19896, 19897, 19898, 27151, 48943 },
    [5] = { 19888, 19897, 19899, 19900, 19901, 27152, 48945 },
    [6] = { 19891, 19899, 19900, 19901, 27153, 48947 },
    [7] = { 32223 },
}

local function BuildSkillPayload(spellIdTable, maxCount)
    local payload = ""
    for id = 1, maxCount do
        if IsPlayerPaladin() and SpellKnownByIds(spellIdTable[id]) then
            payload = payload .. "10"
        else
            payload = payload .. "nn"
        end
    end
    return payload
end

local function AnnounceSelf()
    local player = UnitName("player")
    if not player or player == "" or not IsPlayerPaladin() then return end
    EnsurePally(player)
    state.freeassign[player] = IsFreeAssignEnabled()
    AllPallys[player].freeassign = IsFreeAssignEnabled()
    AllPallys[player].symbols = PP_Symbols
    local assignmentPayload = GetAssignmentPayload(player)
    local auraPayload = tostring(tonumber(state.auras[player]) or 0)
    SendPP("SELF " .. BuildSkillPayload(BLESSING_SPELL_IDS, 6) .. "@" .. assignmentPayload)
    SendPP("ASELF " .. BuildSkillPayload(AURA_SPELL_IDS, MAX_AURAS) .. "@" .. auraPayload)
    SendPP("SYMCOUNT " .. tostring(PP_Symbols or 0))
    SendPP(IsFreeAssignEnabled() and "FREEASSIGN YES" or "FREEASSIGN NO")
end

local function IsPallyPowerLoaded()
    return type(PallyPower) == "table"
end

EnsurePally = function(name)
    if not name or name == "" then return end
    state.pallies[name] = true
    state.assignments[name] = state.assignments[name] or {}
    state.normalAssignments[name] = state.normalAssignments[name] or {}
    state.spellInfo[name] = state.spellInfo[name] or {}
    state.auraInfo[name] = state.auraInfo[name] or {}
    state.auras[name] = tonumber(state.auras[name]) or 0
    EnsureNativeTables(name)
end

local function CopyTableInto(target, source)
    if type(source) ~= "table" then return end
    for k, v in pairs(source) do
        if type(v) == "table" then
            target[k] = target[k] or {}
            CopyTableInto(target[k], v)
        else
            target[k] = v
        end
    end
end

local function GetFirstSpellTexture(ids)
    if type(ids) ~= "table" or not GetSpellTexture then return nil end
    for _, spellId in ipairs(ids) do
        local ok, texture = pcall(GetSpellTexture, spellId)
        if ok and texture and texture ~= "" then
            return texture
        end
    end
    return nil
end

local function GetBlessingIcon(id)
    id = tonumber(id) or 0
    if id <= 0 then return nil end
    local spellTexture = GetFirstSpellTexture(BLESSING_SPELL_IDS[id])
    if spellTexture then return spellTexture end
    if PallyPower and PallyPower.BlessingIcons and PallyPower.BlessingIcons[id] and PallyPower.BlessingIcons[id] ~= "" then
        return PallyPower.BlessingIcons[id]
    end
    return DEFAULT_BLESSING_ICONS[id]
end

local function GetAuraIcon(id)
    id = tonumber(id) or 0
    if id <= 0 then return nil end
    local spellTexture = GetFirstSpellTexture(AURA_SPELL_IDS[id])
    if spellTexture then return spellTexture end
    if PallyPower and PallyPower.AuraIcons and PallyPower.AuraIcons[id] and PallyPower.AuraIcons[id] ~= "" then
        return PallyPower.AuraIcons[id]
    end
    return DEFAULT_AURA_ICONS[id]
end

local function GetClassIcon(id)
    id = tonumber(id) or 0
    if PallyPower and PallyPower.ClassIcons and PallyPower.ClassIcons[id] and PallyPower.ClassIcons[id] ~= "" then
        return PallyPower.ClassIcons[id]
    end
    return DEFAULT_CLASS_ICONS[id]
end


local CLASS_TOKEN_TO_ID = {
    WARRIOR = 1,
    ROGUE = 2,
    PRIEST = 3,
    DRUID = 4,
    PALADIN = 5,
    HUNTER = 6,
    MAGE = 7,
    WARLOCK = 8,
    SHAMAN = 9,
    DEATHKNIGHT = 10,
}

local BLESSING_FALLBACK_SPELL_NAMES = {
    [1] = "Greater Blessing of Wisdom",
    [2] = "Greater Blessing of Might",
    [3] = "Greater Blessing of Kings",
    [4] = "Greater Blessing of Sanctuary",
}

local function GetBestSpellName(ids, fallback)
    if type(ids) == "table" and GetSpellInfo then
        local i
        for i = table.getn(ids), 1, -1 do
            local ok, name = pcall(GetSpellInfo, ids[i])
            if ok and name and name ~= "" then return name end
        end
    end
    return fallback
end

local function GetBlessingSpellName(blessingId)
    blessingId = tonumber(blessingId) or 0
    if blessingId <= 0 then return nil end
    return GetBestSpellName(BLESSING_SPELL_IDS[blessingId], BLESSING_FALLBACK_SPELL_NAMES[blessingId])
end

local function UnitClassId(unit)
    if not UnitExists or not UnitExists(unit) then return nil end
    local _, token = UnitClass(unit)
    return CLASS_TOKEN_TO_ID[token or ""]
end

local function AddBuffScanUnit(units, unit)
    if not UnitExists or not UnitExists(unit) or not UnitIsPlayer or not UnitIsPlayer(unit) then return end
    local classId = UnitClassId(unit)
    if not classId then return end
    local name = UnitName(unit)
    if not name or name == "" then return end
    table.insert(units, { unit = unit, name = name, classId = classId })
end

local function GetGroupUnitsForBuffScan()
    local units = {}
    AddBuffScanUnit(units, "player")
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local i
        for i = 1, GetNumRaidMembers() do AddBuffScanUnit(units, "raid" .. i) end
    elseif GetNumPartyMembers then
        local i
        for i = 1, GetNumPartyMembers() do AddBuffScanUnit(units, "party" .. i) end
    end
    return units
end

local function FindUnitBuffRemaining(unit, blessingId)
    if not UnitBuff then return nil end
    local spellName = GetBlessingSpellName(blessingId)
    if not spellName or spellName == "" then return nil end
    local i = 1
    while true do
        local name, _, _, _, _, duration, expirationTime = UnitBuff(unit, i)
        if not name then break end
        if name == spellName or string.find(name, BLESSING_NAMES[blessingId] or "", 1, true) then
            if expirationTime and expirationTime > 0 and GetTime then
                return expirationTime - GetTime()
            end
            return 999999
        end
        i = i + 1
        if i > 40 then break end
    end
    return nil
end

local function FormatRemaining(seconds)
    seconds = tonumber(seconds) or 0
    if seconds >= 999000 then return "active" end
    if seconds < 0 then seconds = 0 end
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds - (minutes * 60))
    return string.format("%d:%02d", minutes, secs)
end

local function BuildBuffTasks()
    local tasks = {}
    local player = UnitName("player")
    if not player or not state.assignments[player] then return tasks end
    local units = GetGroupUnitsForBuffScan()
    local byClass = {}
    local _, item
    for _, item in ipairs(units) do
        byClass[item.classId] = byClass[item.classId] or {}
        table.insert(byClass[item.classId], item)
    end
    local classId
    for classId = 1, MAX_CLASSES do
        local blessingId = tonumber(state.assignments[player][classId]) or 0
        if blessingId > 0 and blessingId <= 4 and byClass[classId] then
            local classUnits = byClass[classId]
            local minRemaining = nil
            local targetUnit, targetName
            local _, unitInfo
            for _, unitInfo in ipairs(classUnits) do
                local remaining = FindUnitBuffRemaining(unitInfo.unit, blessingId)
                if not remaining then
                    targetUnit = unitInfo.unit
                    targetName = unitInfo.name
                    minRemaining = nil
                    break
                elseif not minRemaining or remaining < minRemaining then
                    minRemaining = remaining
                    targetUnit = unitInfo.unit
                    targetName = unitInfo.name
                end
            end
            if targetUnit then
                local missing = minRemaining == nil
                if missing or minRemaining <= 300 then
                    table.insert(tasks, {
                        unit = targetUnit,
                        targetName = targetName,
                        classId = classId,
                        className = CLASS_NAMES[classId] or "Class",
                        blessingId = blessingId,
                        blessingName = BLESSING_NAMES[blessingId] or "Blessing",
                        spellName = GetBlessingSpellName(blessingId),
                        remaining = minRemaining,
                        missing = missing,
                    })
                end
            end
        end
    end
    table.sort(tasks, function(a, b)
        if a.missing ~= b.missing then return a.missing end
        return (a.remaining or 0) < (b.remaining or 0)
    end)
    return tasks
end

local function IsBuffTaskInRange(task)
    if not task or not task.spellName or not task.unit then return false end
    if not UnitExists or not UnitExists(task.unit) then return false end
    if IsSpellInRange then
        local ok, result = pcall(IsSpellInRange, task.spellName, task.unit)
        if ok and result == 1 then return true end
        if ok and result == nil then return true end
        return false
    end
    return true
end

local function GetAutoBuffPenalty(task)
    if not task or not task.targetName then return 0 end
    local now = time and time() or 0
    local penalty = 0
    if autoBuffedList[task.targetName] and now - autoBuffedList[task.targetName] < 20 then
        penalty = penalty + 900
    end
    if previousAutoBuffedUnit and previousAutoBuffedUnit.name == task.targetName then
        penalty = penalty + 1800
    end
    return penalty
end

local function SelectAutoBuffTask()
    local tasks = BuildBuffTasks()
    local bestTask
    local bestScore = 999999
    local i
    for i = 1, table.getn(tasks) do
        local task = tasks[i]
        if task and task.spellName and IsBuffTaskInRange(task) then
            local score = (task.missing and 0 or (task.remaining or 0)) + GetAutoBuffPenalty(task)
            if score < bestScore then
                bestTask = task
                bestScore = score
            end
        end
    end
    return bestTask, tasks
end

local function PrepareAutoBuffButton(button, mousebutton)
    -- Mirrors PallyPower's secure pattern: PreClick computes the spell/unit and
    -- writes only SecureActionButton attributes. No TargetUnit/CastSpell path.
    if not button then return nil end
    if InCombatLockdown and InCombatLockdown() then return nil end

    local task = SelectAutoBuffTask()
    button.wowNotePreparedTask = task

    if task and task.spellName and task.unit and UnitExists and UnitExists(task.unit) then
        button:SetAttribute("unit", task.unit)
        button:SetAttribute("spell", task.spellName)
        if time then
            autoBuffedList[task.targetName or task.unit] = time()
        end
        previousAutoBuffedUnit = { name = task.targetName or task.unit, unit = task.unit }
        return task
    end

    button:SetAttribute("unit", nil)
    button:SetAttribute("spell", nil)
    return nil
end

local function ClearAutoBuffButton(button)
    -- PallyPower clears the secure action target after the click. Do the same so
    -- stale spell/unit attributes cannot fire from a later tainted path.
    if not button then return end
    if InCombatLockdown and InCombatLockdown() then return end
    button:SetAttribute("unit", nil)
    button:SetAttribute("spell", nil)
    button.wowNotePreparedTask = nil
end

local function CastBuffTask(task)
    -- Deprecated: targeting/casting via TargetUnit taints protected execution paths.
    -- The visible buff button uses PallyPower-style PreClick secure attributes instead.
    if not task then
        SetStatus("No missing or expiring PallyBuffs found.")
    else
        SetStatus("Use the secure PallyBuffs button to cast " .. tostring(task.blessingName or "Buff") .. ".")
    end
end

local function AddVisiblePaladin(list, seen, name)
    if not name or name == "" or seen[name] then return end
    seen[name] = true
    table.insert(list, name)
end

local function AddPaladinUnit(list, seen, unit)
    if not UnitExists(unit) then return end
    local name = UnitName(unit)
    local _, classToken = UnitClass(unit)
    if classToken == "PALADIN" then
        EnsurePally(name)
        AddVisiblePaladin(list, seen, name)
    end
end

local function GetCurrentPaladins()
    local list = {}
    local seen = {}

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            AddPaladinUnit(list, seen, "raid" .. i)
        end
    else
        AddPaladinUnit(list, seen, "player")
        if GetNumPartyMembers then
            for i = 1, GetNumPartyMembers() do
                AddPaladinUnit(list, seen, "party" .. i)
            end
        end
    end

    table.sort(list)
    return list
end

local function EnsureSampleData()
    local playerName = UnitName("player") or "You"
    for index, name in ipairs(SAMPLE_PALLIES) do
        EnsurePally(name)
        for classId = 1, MAX_CLASSES do
            state.assignments[name][classId] = ((classId + index) % 4) + 1
        end
        state.auras[name] = index
    end
    EnsurePally(playerName)
end

local function SyncFromPallyPower()
    if type(AllPallys) == "table" then
        for name, info in pairs(AllPallys) do
            EnsurePally(name)
            if type(info) == "table" then
                state.freeassign[name] = info.freeassign == true
                state.symbols[name] = info.symbols
                state.spellInfo[name] = info
                state.auraInfo[name] = info.AuraInfo or state.auraInfo[name]
            end
        end
    end
    if type(PallyPower_Assignments) == "table" then
        for name, assignment in pairs(PallyPower_Assignments) do
            EnsurePally(name)
            state.assignments[name] = {}
            CopyTableInto(state.assignments[name], assignment)
        end
    end
    if type(PallyPower_AuraAssignments) == "table" then
        for name, aura in pairs(PallyPower_AuraAssignments) do
            EnsurePally(name)
            state.auras[name] = tonumber(aura) or 0
        end
    end
    local player = UnitName("player")
    local _, class = UnitClass("player")
    if class == "PALADIN" then
        EnsurePally(player)
        state.freeassign[player] = IsFreeAssignEnabled()
    end
end

local function CanControl(name)
    if PallyPower and PallyPower.CanControl then
        local ok, result = pcall(function() return PallyPower:CanControl(name) end)
        if ok then return result end
    end
    return ((IsPartyLeader and IsPartyLeader()) or (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer()) or name == UnitName("player") or state.freeassign[name] == true)
end

local function SetAssignment(name, classId, blessingId)
    if not name or not classId then return end
    blessingId = tonumber(blessingId) or 0
    classId = tonumber(classId) or 0
    if not CanControl(name) then
        Print("Cannot control assignments for " .. tostring(name) .. ". You need leader/officer, own paladin, or free assignment.")
        return
    end
    EnsurePally(name)
    state.assignments[name][classId] = blessingId
    PallyPower_Assignments[name] = PallyPower_Assignments[name] or {}
    PallyPower_Assignments[name][classId] = blessingId
    SendPP("ASSIGN " .. name .. " " .. classId .. " " .. blessingId)
    if name == UnitName("player") then AnnounceSelf() end
    SetStatus(name .. " -> " .. CLASS_NAMES[classId] .. ": " .. BLESSING_NAMES[blessingId])
end

local function SetMassAssignment(name, blessingId, overwrite)
    if not name then return end
    blessingId = tonumber(blessingId) or 0
    if not CanControl(name) then
        Print("Cannot control assignments for " .. tostring(name) .. ".")
        return
    end
    EnsurePally(name)
    local changed = 0
    for classId = 1, MAX_CLASSES do
        local current = tonumber(state.assignments[name][classId]) or 0
        if overwrite or blessingId == 0 or current == 0 then
            state.assignments[name][classId] = blessingId
            PallyPower_Assignments[name][classId] = blessingId
            changed = changed + 1
        end
    end
    if overwrite or blessingId == 0 then
        SendPP("MASSIGN " .. name .. " " .. blessingId)
    else
        for classId = 1, MAX_CLASSES do
            if tonumber(PallyPower_Assignments[name][classId]) == blessingId then
                SendPP("ASSIGN " .. name .. " " .. classId .. " " .. blessingId)
            end
        end
    end
    if name == UnitName("player") then AnnounceSelf() end
    SetStatus(name .. " -> " .. changed .. " class slots: " .. BLESSING_NAMES[blessingId] .. (overwrite and " (overwrite)" or " (empty only)"))
end

local function SetAura(name, auraId)
    if not name then return end
    auraId = tonumber(auraId) or 0
    if not CanControl(name) then
        Print("Cannot control aura assignment for " .. tostring(name) .. ".")
        return
    end
    EnsurePally(name)
    state.auras[name] = auraId
    PallyPower_AuraAssignments[name] = auraId
    SendPP("AASSIGN " .. name .. " " .. auraId)
    if name == UnitName("player") then AnnounceSelf() end
    SetStatus(name .. " aura: " .. AURA_NAMES[auraId])
end

local function ClearAssignments()
    SendPP("CLEAR")
    for name, _ in pairs(state.assignments) do
        for classId = 1, MAX_CLASSES do
            state.assignments[name][classId] = 0
        end
        state.auras[name] = 0
    end
    for name, assignment in pairs(PallyPower_Assignments) do
        for classId = 1, MAX_CLASSES do assignment[classId] = 0 end
    end
    for name, _ in pairs(PallyPower_AuraAssignments) do
        PallyPower_AuraAssignments[name] = 0
    end
    if PallyPower and PallyPower.ClearAssignments then
        pcall(function() PallyPower:ClearAssignments(UnitName("player")) end)
    end
    SetStatus("Clear request sent.")
end

local function RequestSync()
    SyncFromPallyPower()
    AnnounceSelf()
    SendPP("REQ")
    SetStatus("PallyBuffs sync requested.")
end

local function RegisterSlashCommands()
    SLASH_WOWNOTEPALLYPOWER1 = "/wnpp"
    SLASH_WOWNOTEPALLYPOWER2 = "/wnbuffs"
    SlashCmdList["WOWNOTEPALLYPOWER"] = function()
        WowNote_OpenPallyBuffs()
    end
    if not PallyPower then
        SLASH_PALLYPOWER1 = "/pp"
        SlashCmdList["PALLYPOWER"] = function()
            WowNote_OpenPallyBuffs()
        end
    end
end

local function GetVisiblePallies()
    SyncFromPallyPower()
    local list = GetCurrentPaladins()
    if table.getn(list) == 0 and IsTestModeEnabled() then
        EnsureSampleData()
        local sampleSeen = {}
        for _, name in ipairs(SAMPLE_PALLIES) do
            AddVisiblePaladin(list, sampleSeen, name)
        end
        table.sort(list)
    end
    return list
end

local function ParseSelf(sender, msg)
    EnsurePally(sender)
    PallyPower_NormalAssignments[sender] = {}
    PallyPower_Assignments[sender] = {}
    AllPallys[sender] = {}
    SyncAdd(sender)

    local numbers, assign = string.match(msg, "SELF%s+([0-9n]*)@([0-9n]*)")
    numbers = numbers or ""
    assign = assign or ""
    for i = 1, 6 do
        local rank = string.sub(numbers, (i - 1) * 2 + 1, (i - 1) * 2 + 1)
        local talent = string.sub(numbers, (i - 1) * 2 + 2, (i - 1) * 2 + 2)
        if rank ~= "n" and rank ~= "" then
            AllPallys[sender][i] = { rank = tonumber(rank) or 0, talent = tonumber(talent) or 0 }
        end
    end
    state.spellInfo[sender] = AllPallys[sender]
    state.assignments[sender] = state.assignments[sender] or {}
    for classId = 1, MAX_CLASSES do
        local ch = string.sub(assign, classId, classId)
        local value = tonumber(ch) or 0
        state.assignments[sender][classId] = value
        PallyPower_Assignments[sender][classId] = value
    end
end

local function ParseASelf(sender, msg)
    EnsurePally(sender)
    AllPallys[sender] = AllPallys[sender] or {}
    AllPallys[sender].AuraInfo = {}
    local numbers, assign = string.match(msg, "ASELF%s+([0-9a-fn]*)@([0-9n]*)")
    numbers = numbers or ""
    assign = assign or "0"
    for i = 1, MAX_AURAS do
        local rank = string.sub(numbers, (i - 1) * 2 + 1, (i - 1) * 2 + 1)
        local talent = string.sub(numbers, (i - 1) * 2 + 2, (i - 1) * 2 + 2)
        if rank ~= "n" and rank ~= "" then
            AllPallys[sender].AuraInfo[i] = { rank = tonumber(rank, 16) or 0, talent = tonumber(talent, 16) or 0 }
        end
    end
    local aura = tonumber(assign) or 0
    state.auras[sender] = aura
    PallyPower_AuraAssignments[sender] = aura
    state.auraInfo[sender] = AllPallys[sender].AuraInfo
end

local function ParseNormalAssignments(sender, msg)
    for pname, classId, targetName, skill in string.gmatch(string.sub(msg, 9), "([^@]*) ([^@]*) ([^@]*) ([^@]*)") do
        if IncomingCanControl(sender, pname) then
            classId = tonumber(classId) or 0
            skill = tonumber(skill) or 0
            EnsurePally(pname)
            PallyPower_NormalAssignments[pname] = PallyPower_NormalAssignments[pname] or {}
            PallyPower_NormalAssignments[pname][classId] = PallyPower_NormalAssignments[pname][classId] or {}
            state.normalAssignments[pname] = state.normalAssignments[pname] or {}
            state.normalAssignments[pname][classId] = state.normalAssignments[pname][classId] or {}
            if skill == 0 then skill = nil end
            PallyPower_NormalAssignments[pname][classId][targetName] = skill
            state.normalAssignments[pname][classId][targetName] = skill
        end
    end
end

local function ParseAddonMessage(sender, msg)
    if not sender or sender == UnitName("player") then return end
    msg = tostring(msg or "")
    if msg == "REQ" then
        AnnounceSelf()
    elseif string.find(msg, "^SELF") then
        ParseSelf(sender, msg)
    elseif string.find(msg, "^ASSIGN") then
        local name, classId, skill = string.match(msg, "^ASSIGN%s+(.*)%s+(%d+)%s+(%d+)")
        if name and IncomingCanControl(sender, name) then
            classId = tonumber(classId) or 0
            skill = tonumber(skill) or 0
            EnsurePally(name)
            state.assignments[name][classId] = skill
            PallyPower_Assignments[name][classId] = skill
        end
    elseif string.find(msg, "^NASSIGN") then
        ParseNormalAssignments(sender, msg)
    elseif string.find(msg, "^MASSIGN") then
        local name, skill = string.match(msg, "^MASSIGN%s+(.*)%s+(%d+)")
        if name and IncomingCanControl(sender, name) then
            skill = tonumber(skill) or 0
            EnsurePally(name)
            for classId = 1, MAX_CLASSES do
                state.assignments[name][classId] = skill
                PallyPower_Assignments[name][classId] = skill
            end
        end
    elseif string.find(msg, "^AASSIGN") then
        local name, aura = string.match(msg, "^AASSIGN%s+(.*)%s+(%d+)")
        if name and IncomingCanControl(sender, name) then
            aura = tonumber(aura) or 0
            EnsurePally(name)
            state.auras[name] = aura
            PallyPower_AuraAssignments[name] = aura
        end
    elseif string.find(msg, "^ASELF") then
        ParseASelf(sender, msg)
    elseif string.find(msg, "^SYMCOUNT") then
        local count = string.match(msg, "^SYMCOUNT%s+(%d+)")
        EnsurePally(sender)
        state.symbols[sender] = tonumber(count) or 0
        AllPallys[sender].symbols = state.symbols[sender]
    elseif msg == "FREEASSIGN YES" then
        EnsurePally(sender)
        state.freeassign[sender] = true
        AllPallys[sender].freeassign = true
    elseif msg == "FREEASSIGN NO" then
        EnsurePally(sender)
        state.freeassign[sender] = false
        AllPallys[sender].freeassign = false
    elseif string.find(msg, "^CLEAR") then
        if IsSenderLeader(sender) then
            for name, assignment in pairs(state.assignments) do
                for classId = 1, MAX_CLASSES do
                    assignment[classId] = 0
                    if PallyPower_Assignments[name] then PallyPower_Assignments[name][classId] = 0 end
                end
                state.auras[name] = 0
                PallyPower_AuraAssignments[name] = 0
            end
        end
    end
end

local function CreateAssignmentIconButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width or 26)
    button:SetHeight(height or 26)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    button:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    button:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.noneText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.noneText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.noneText:SetText("-")

    function button:SetAssignmentVisual(iconPath, label)
        if iconPath and iconPath ~= "" then
            self.icon:SetTexture(iconPath)
            self.icon:Show()
            self.noneText:Hide()
        else
            self.icon:SetTexture(nil)
            self.icon:Hide()
            self.noneText:SetText(label or "-")
            self.noneText:Show()
        end
    end

    return button
end

local function CreateBuffFrame()
    if buffFrame then return end

    buffFrame = CreateFrame("Frame", "WowNotePallyPowerBuffFrame", UIParent)
    buffFrame:SetWidth(238)
    buffFrame:SetHeight(118)
    buffFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
    buffFrame:SetMovable(true)
    buffFrame:EnableMouse(true)
    buffFrame:RegisterForDrag("LeftButton")
    buffFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    buffFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    buffFrame:SetFrameStrata("DIALOG")
    buffFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 12,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    buffFrame:SetBackdropColor(0.02, 0.02, 0.02, 0.92)
    buffFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    buffFrame.title = buffFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    buffFrame.title:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 10, -8)
    buffFrame.title:SetText("PallyBuffs")

    buffFrame.close = CreateFrame("Button", nil, buffFrame, "UIPanelCloseButton")
    buffFrame.close:SetPoint("TOPRIGHT", buffFrame, "TOPRIGHT", 1, 1)
    buffFrame.close:SetScript("OnClick", function()
        EnsureConfig().buffFrameVisible = false
        UpdateBuffFrameButton()
        buffFrame:Hide()
    end)

    buffFrame.castButton = CreateFrame("Button", "WowNotePallyBuffsSecureCastButton", buffFrame, "SecureActionButtonTemplate")
    buffFrame.castButton:SetWidth(42)
    buffFrame.castButton:SetHeight(42)
    buffFrame.castButton:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 12, -32)
    buffFrame.castButton:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 12,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    buffFrame.castButton:SetBackdropColor(0.02, 0.02, 0.02, 0.9)
    buffFrame.castButton:SetBackdropBorderColor(0.8, 0.62, 0.2, 1)
    buffFrame.castButton.icon = buffFrame.castButton:CreateTexture(nil, "ARTWORK")
    buffFrame.castButton.icon:SetPoint("TOPLEFT", buffFrame.castButton, "TOPLEFT", 4, -4)
    buffFrame.castButton.icon:SetPoint("BOTTOMRIGHT", buffFrame.castButton, "BOTTOMRIGHT", -4, 4)
    buffFrame.castButton.text = buffFrame.castButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    buffFrame.castButton.text:SetPoint("CENTER", buffFrame.castButton, "CENTER", 0, 0)
    buffFrame.castButton:RegisterForClicks("AnyUp")
    buffFrame.castButton:SetAttribute("type", "spell")
    buffFrame.castButton:SetAttribute("unit", nil)
    buffFrame.castButton:SetAttribute("spell", nil)
    buffFrame.castButton:SetScript("PreClick", function(self, mouseButton)
        PrepareAutoBuffButton(self, mouseButton)
    end)
    buffFrame.castButton:SetScript("PostClick", function(self)
        local task = self.wowNotePreparedTask or buffFrame.nextTask
        if task then
            SetStatus("PallyBuffs click: " .. tostring(task.blessingName or "Buff") .. " for " .. tostring(task.className or "Class") .. ".")
        else
            SetStatus("No missing or expiring PallyBuffs found.")
        end
        ClearAutoBuffButton(self)
    end)

    buffFrame.summary = buffFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buffFrame.summary:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 64, -34)
    buffFrame.summary:SetWidth(158)
    buffFrame.summary:SetJustifyH("LEFT")
    buffFrame.summary:SetText("Scanning...")

    buffFrame.popup = buffFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    buffFrame.popup:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 12, -78)
    buffFrame.popup:SetWidth(212)
    buffFrame.popup:SetJustifyH("LEFT")
    buffFrame.popup:SetText("")

    buffFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + (elapsed or 0)
        if self.elapsed >= 1.0 then
            self.elapsed = 0
            RefreshBuffFrame()
        end
    end)
end

local function UpdateSecureCastButton(task)
    -- Do not set spell/unit here. PallyPower sets secure spell/unit attributes
    -- in PreClick and clears them in PostClick. Updating them from OnUpdate can
    -- produce Blizzard-only/taint errors on older 3.3.5 clients.
    if not buffFrame or not buffFrame.castButton then return end
    buffFrame.nextTask = task
end

RefreshBuffFrame = function()
    EnsureConfig()
    CreateBuffFrame()
    UpdateBuffFrameButton()

    if not EnsureConfig().buffFrameVisible then
        buffFrame:Hide()
        return
    end

    if not IsPlayerPaladin() then
        buffFrame:Hide()
        return
    end

    local player = UnitName("player")
    EnsurePally(player)
    buffFrame:Show()

    local tasks = BuildBuffTasks()
    local task = tasks[1]
    buffFrame.nextTask = task
    UpdateSecureCastButton(task)

    if task then
        buffFrame.castButton.icon:SetTexture(GetBlessingIcon(task.blessingId))
        buffFrame.castButton.icon:Show()
        buffFrame.castButton.text:SetText("")
        buffFrame.summary:SetText((task.blessingName or "Buff") .. " -> " .. (task.className or "Class"))
    else
        buffFrame.castButton.icon:SetTexture("Interface\\Icons\\Spell_Holy_SealOfSalvation")
        buffFrame.castButton.icon:Show()
        buffFrame.castButton.text:SetText("")
        buffFrame.summary:SetText("All assigned buffs OK")
    end

    local lines = {}
    local maxLines = 3
    local i
    for i = 1, table.getn(tasks) do
        if i > maxLines then break end
        local t = tasks[i]
        table.insert(lines, (t.className or "Class") .. ": " .. (t.blessingName or "Buff") .. " " .. (t.missing and "missing" or FormatRemaining(t.remaining)))
    end
    if table.getn(tasks) > maxLines then
        table.insert(lines, "+" .. tostring(table.getn(tasks) - maxLines) .. " more")
    end
    if table.getn(lines) == 0 then
        buffFrame.popup:SetText("No missing or expiring assignments.")
    else
        buffFrame.popup:SetText(table.concat(lines, "\n"))
    end

    AddActionTooltip(buffFrame.castButton, "PallyBuffs cast button", {
        { key = "Left-click", text = task and ("Cast " .. tostring(task.blessingName) .. " for " .. tostring(task.className) .. ".") or "No missing buff to cast." },
        { text = "Uses the same safe PreClick pattern as PallyPower: one real click prepares and casts the next missing or expiring buff." },
        { text = "The list below shows missing buffs and remaining time." },
    })
end

Refresh = function()
    if not frame or not scrollChild then return end

    SyncFromPallyPower()
    for i = 1, table.getn(rows) do
        rows[i]:Hide()
    end

    local pallies = GetVisiblePallies()
    if table.getn(pallies) == 0 then
        scrollChild:SetHeight(1)
        SetStatus("No paladins in the current party or raid. Enable Test Mode if you want to preview the UI.")
        if infoText then
            infoText:SetText("Only current party / raid paladins are shown. No assignment rows are rendered when none are present.")
        end
        RefreshBuffFrame()
        return
    end

    if infoText then
        infoText:SetText("Only current party / raid paladins are shown. Left-click a cell to cycle assignments, right-click to clear. Compatibility uses the PLPWR protocol and mirrors AllPallys / assignment tables internally.")
    end

    local y = -4
    for index, name in ipairs(pallies) do
        local row = rows[index]
        if not row then
            row = CreateFrame("Frame", nil, scrollChild)
            row:SetWidth(860)
            row:SetHeight(30)
            rows[index] = row

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.name:SetWidth(112)
            row.name:SetJustifyH("LEFT")

            row.mass = MakeButton(row, "All", 40, 22)
            row.mass:SetPoint("LEFT", row, "LEFT", 122, 0)
            AddActionTooltip(row.mass, "Mass assignment", {
                { key = "Left-click", text = "Fill empty class slots with the next blessing." },
                { key = "Shift-left-click", text = "Overwrite all class slots with the next blessing." },
                { key = "Right-click", text = "Clear all class blessing assignments." },
            })

            row.classButtons = {}
            local x = 170
            for classId = 1, MAX_CLASSES do
                local button = CreateAssignmentIconButton(row, 26, 26)
                button:SetPoint("LEFT", row, "LEFT", x, 0)
                x = x + 30
                row.classButtons[classId] = button
            end

            row.aura = CreateAssignmentIconButton(row, 26, 26)
            row.aura:SetPoint("LEFT", row, "LEFT", x + 8, 0)
            AddTooltip(row.aura, "Aura assignment", "Left-click cycles aura assignment. Right-click clears it.")
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:Show()
        row.pallyName = name
        row.name:SetText(name)

        local control = CanControl(name)
        if control then
            row.name:SetTextColor(0.2, 1.0, 0.2)
        else
            row.name:SetTextColor(1.0, 0.75, 0.2)
        end

        row.mass:SetScript("OnClick", function(self, button)
            local cur = 0
            if state.assignments[name] then
                cur = tonumber(state.assignments[name][1]) or 0
            end
            local nextValue = button == "RightButton" and 0 or ((cur + 1) % 5)
            local overwrite = button == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown())
            SetMassAssignment(name, nextValue, overwrite)
            Refresh()
        end)
        SetButtonEnabled(row.mass, control)

        for classId = 1, MAX_CLASSES do
            local value = 0
            if state.assignments[name] then
                value = tonumber(state.assignments[name][classId]) or 0
            end
            local button = row.classButtons[classId]
            button.pallyName = name
            button.classId = classId
            button:SetAssignmentVisual(GetBlessingIcon(value), "-")
            button:SetScript("OnClick", function(self, mouseButton)
                local cur = 0
                if state.assignments[name] then
                    cur = tonumber(state.assignments[name][classId]) or 0
                end
                local nextValue = mouseButton == "RightButton" and 0 or ((cur + 1) % 5)
                SetAssignment(name, classId, nextValue)
                Refresh()
            end)
            AddTooltip(button, name .. " -> " .. CLASS_NAMES[classId], "Current blessing: " .. (BLESSING_NAMES[value] or "None") .. "\nLeft-click cycles blessings. Right-click clears this assignment.")
            if control then
                button:SetAlpha(1)
                button:EnableMouse(true)
                button:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            else
                button:SetAlpha(0.55)
                button:EnableMouse(true)
                button:SetBackdropBorderColor(0.4, 0.2, 0.2, 1)
            end
        end

        local auraId = tonumber(state.auras[name]) or 0
        row.aura:SetAssignmentVisual(GetAuraIcon(auraId), "-")
        row.aura:SetScript("OnClick", function(self, button)
            local cur = tonumber(state.auras[name]) or 0
            local nextValue = button == "RightButton" and 0 or ((cur + 1) % (MAX_AURAS + 1))
            SetAura(name, nextValue)
            Refresh()
        end)
        AddTooltip(row.aura, name .. " -> Aura", "Current aura: " .. (AURA_NAMES[auraId] or "None") .. "\nLeft-click cycles auras. Right-click clears this assignment.")
        if control then
            row.aura:SetAlpha(1)
            row.aura:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        else
            row.aura:SetAlpha(0.55)
            row.aura:SetBackdropBorderColor(0.4, 0.2, 0.2, 1)
        end

        y = y - 32
    end

    scrollChild:SetHeight(math.max(260, table.getn(pallies) * 32 + 10))
    SetStatus("Visible paladins: " .. table.getn(pallies) .. (IsTestModeEnabled() and " | Test Mode" or "") .. (IsPallyPowerLoaded() and " | Native compatible client detected" or " | Standalone mode"))
    RefreshBuffFrame()
end

local function CreateHeaderIcon(parent, x, classId)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(26)
    holder:SetHeight(26)
    holder:SetPoint("LEFT", parent, "LEFT", x, 0)

    local iconPath = GetClassIcon(classId)
    if iconPath then
        holder.icon = holder:CreateTexture(nil, "ARTWORK")
        holder.icon:SetAllPoints(holder)
        holder.icon:SetTexture(iconPath)
        holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        holder.text:SetAllPoints(holder)
        holder.text:SetText(string.sub(CLASS_NAMES[classId], 1, 3))
    end
    AddTooltip(holder, CLASS_NAMES[classId], "Class assignment column")
    return holder
end

local function CreateUI()
    if frame then return end

    EnsureConfig()

    frame = CreateFrame("Frame", "WowNotePallyPowerFrame", UIParent)
    frame:SetWidth(960)
    frame:SetHeight(520)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 }
    })
    frame:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -14)
    title:SetText("WowNote - PallyBuffs")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    local requestButton = MakeButton(frame, "Request Sync", 104, 24)
    requestButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -42)
    requestButton:SetScript("OnClick", function()
        RequestSync()
        Refresh()
    end)
    AddTooltip(requestButton, "Request Sync", "Requests assignment data from compatible buff clients.")

    local refreshButton = MakeButton(frame, "Refresh", 74, 24)
    refreshButton:SetPoint("LEFT", requestButton, "RIGHT", 8, 0)
    refreshButton:SetScript("OnClick", function() Refresh() end)

    local clearButton = MakeButton(frame, "Clear", 68, 24)
    clearButton:SetPoint("LEFT", refreshButton, "RIGHT", 8, 0)
    clearButton:SetScript("OnClick", function()
        ClearAssignments()
        Refresh()
    end)
    AddTooltip(clearButton, "Clear", "Sends a compatible clear request. Other clients accept it only when you have permission.")

    local nativeConfigButton = MakeButton(frame, "Native Config", 108, 24)
    nativeConfigButton:SetPoint("LEFT", clearButton, "RIGHT", 8, 0)
    nativeConfigButton:SetScript("OnClick", function()
        if PallyPowerConfig_Toggle then
            PallyPowerConfig_Toggle()
        elseif PallyPowerConfigFrame then
            if PallyPowerConfigFrame:IsVisible() then PallyPowerConfigFrame:Hide() else PallyPowerConfigFrame:Show() end
        else
            Print("Native compatible config frame is not available.")
        end
    end)

    buffFrameButton = MakeButton(frame, EnsureConfig().buffFrameVisible and "Buff On" or "Buff Off", 78, 24)
    buffFrameButton:SetPoint("LEFT", nativeConfigButton, "RIGHT", 8, 0)
    buffFrameButton:SetScript("OnClick", function()
        EnsureConfig().buffFrameVisible = not EnsureConfig().buffFrameVisible
        RefreshBuffFrame()
        SetStatus(EnsureConfig().buffFrameVisible and "Buff frame shown." or "Buff frame hidden.")
    end)
    AddTooltip(buffFrameButton, "Buff Button", "Shows or hides the single PallyBuffs cast button and missing-buff list.")

    freeAssignButton = MakeButton(frame, EnsureConfig().freeAssign and "Free On" or "Free Off", 84, 24)
    freeAssignButton:SetPoint("LEFT", buffFrameButton, "RIGHT", 8, 0)
    freeAssignButton:SetScript("OnClick", function()
        SetFreeAssignEnabled(not IsFreeAssignEnabled(), true)
        AnnounceSelf()
        Refresh()
    end)
    AddTooltip(freeAssignButton, "Free Assignment", "Toggles whether other compatible buff clients may change your assignments. Default: Free On.")

    local helpButton = MakeButton(frame, "Help", 58, 24)
    helpButton:SetPoint("LEFT", freeAssignButton, "RIGHT", 8, 0)
    helpButton:SetScript("OnClick", function()
        Print("PallyBuffs: only current party / raid paladins are shown. Left-click cycles a class or aura icon, right-click clears it. This module announces SELF/ASELF/SYMCOUNT/FREEASSIGN and parses ASSIGN/MASSIGN/NASSIGN/AASSIGN/CLEAR on PLPWR, so other compatible clients can treat it as compatible.")
    end)

    testModeButton = MakeButton(frame, EnsureConfig().testMode and "Test On" or "Test Off", 74, 24)
    testModeButton:SetPoint("LEFT", helpButton, "RIGHT", 8, 0)
    testModeButton:SetScript("OnClick", function()
        SetTestModeEnabled(not IsTestModeEnabled())
        Refresh()
    end)
    AddTooltip(testModeButton, "Test Mode", "Shows a small sample roster when no paladins are in the current party or raid.")

    local headerBg = CreateFrame("Frame", nil, frame)
    headerBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -76)
    headerBg:SetWidth(900)
    headerBg:SetHeight(32)
    headerBg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    headerBg:SetBackdropColor(0.10, 0.10, 0.10, 0.95)

    local pallyHeader = headerBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pallyHeader:SetPoint("LEFT", headerBg, "LEFT", 8, 0)
    pallyHeader:SetWidth(112)
    pallyHeader:SetJustifyH("LEFT")
    pallyHeader:SetText("Paladin")

    local allHeader = headerBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    allHeader:SetPoint("LEFT", headerBg, "LEFT", 126, 0)
    allHeader:SetWidth(40)
    allHeader:SetText("All")

    local x = 170
    for classId = 1, MAX_CLASSES do
        CreateHeaderIcon(headerBg, x, classId)
        x = x + 30
    end

    local auraHeader = CreateAssignmentIconButton(headerBg, 26, 26)
    auraHeader:SetPoint("LEFT", headerBg, "LEFT", x + 8, 0)
    auraHeader:SetAssignmentVisual(GetAuraIcon(1), "A")
    AddTooltip(auraHeader, "Aura", "Aura assignment column")

    local scrollBg = CreateFrame("Frame", nil, frame)
    scrollBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -110)
    scrollBg:SetWidth(900)
    scrollBg:SetHeight(332)
    scrollBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    scrollBg:SetBackdropColor(0.04, 0.04, 0.04, 0.94)

    local scroll = CreateFrame("ScrollFrame", "WowNotePallyPowerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -114)
    scroll:SetWidth(892)
    scroll:SetHeight(324)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(868)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)

    infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 42)
    infoText:SetWidth(900)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("Only current party / raid paladins are shown.")

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 20)
    statusText:SetWidth(900)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Ready")

    frame:SetScript("OnShow", function()
        RequestSync()
        Refresh()
    end)
end

function WowNote_OpenPallyBuffs()
    CreateUI()
    frame:Show()
    RaiseFrame(frame)
    Refresh()
end

function WowNote_PallyPower_RequestSync()
    RequestSync()
    Refresh()
end

function WowNote_PallyPower_SetTestMode(enabled)
    SetTestModeEnabled(enabled)
    if frame and frame:IsVisible() then
        Refresh()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    local moduleEnabled = not (WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("pallyBuffs"))
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME or arg1 == "WoWNote" or arg1 == "PallyPower" then
            if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PP_PREFIX) end
            EnsureConfig()
            RegisterSlashCommands()
            if moduleEnabled then
                SyncFromPallyPower()
                SetFreeAssignEnabled(IsFreeAssignEnabled(), false)
                AnnounceSelf()
                if frame and frame:IsVisible() then Refresh() else RefreshBuffFrame() end
            end
        end
    elseif event == "PLAYER_LOGIN" then
        if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PP_PREFIX) end
        EnsureConfig()
        RegisterSlashCommands()
        if moduleEnabled then
            SyncFromPallyPower()
            SetFreeAssignEnabled(IsFreeAssignEnabled(), false)
            AnnounceSelf()
            RefreshBuffFrame()
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, distribution, sender = arg1, arg2, arg3, arg4
        if moduleEnabled and prefix == PP_PREFIX then
            ParseAddonMessage(sender, message)
            if frame and frame:IsVisible() then Refresh() else RefreshBuffFrame() end
        end
    elseif event == "UNIT_AURA" then
        if moduleEnabled then
            RefreshBuffFrame()
        end
    else
        if moduleEnabled then
            SyncFromPallyPower()
            AnnounceSelf()
            if frame and frame:IsVisible() then Refresh() else RefreshBuffFrame() end
        end
    end
end)
