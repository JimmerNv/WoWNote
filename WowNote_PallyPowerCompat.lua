-- WowNote_PallyPowerCompat.lua
-- PallyPower compatible assignment bridge and integrated WowNote PallyBuffs UI for WoW 3.3.5a.

local ADDON_NAME = ...
local WN = WowNote_Internal or {}

local PP_PREFIX = "PLPWR"
local MAX_CLASSES = 11
local MAX_AURAS = 7
local AURA_REFRESH_DELAY = 0.08
local SPELLCAST_REFRESH_DELAY = 0.10
local ROSTER_REFRESH_DELAY = 0.25
local COMM_REFRESH_DELAY = 0.10
local SAVE_REFRESH_DELAY = 0.20

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

local CLASS_ID_TO_TOKEN = {
    [1] = "WARRIOR",
    [2] = "ROGUE",
    [3] = "PRIEST",
    [4] = "DRUID",
    [5] = "PALADIN",
    [6] = "HUNTER",
    [7] = "MAGE",
    [8] = "WARLOCK",
    [9] = "SHAMAN",
    [10] = "DEATHKNIGHT",
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
    [2] = "Interface\\Icons\\Spell_Holy_FistOfJustice",
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

if type(AllPallys) ~= "table" then AllPallys = {} end
if type(SyncList) ~= "table" then SyncList = {} end
if type(ChatControl) ~= "table" then ChatControl = {} end
if type(PallyPower_Assignments) ~= "table" then PallyPower_Assignments = {} end
if type(PallyPower_NormalAssignments) ~= "table" then PallyPower_NormalAssignments = {} end
if type(PallyPower_AuraAssignments) ~= "table" then PallyPower_AuraAssignments = {} end
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
local buffFrameRows = {}
local autoBuffedList = {}
local previousAutoBuffedUnit
local rows = {}
local Refresh
local RefreshBuffFrame
local UpdateCastButtonVisual
local UpdateSecureCastButton
local QueueVisualRefresh
local UpdateRuntimeEventRegistration
local loadedTalentGroup

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

local function GetActiveTalentGroupKey()
    local group = 1
    if GetActiveTalentGroup then
        local ok, value = pcall(GetActiveTalentGroup)
        if ok and tonumber(value) then group = tonumber(value) end
    end
    if group ~= 2 then group = 1 end
    return tostring(group)
end

local function EnsureSpecProfile(cfg, specKey)
    cfg.specProfiles = type(cfg.specProfiles) == "table" and cfg.specProfiles or {}
    specKey = tostring(specKey or GetActiveTalentGroupKey())
    if type(cfg.specProfiles[specKey]) ~= "table" then cfg.specProfiles[specKey] = {} end
    local profile = cfg.specProfiles[specKey]
    if type(profile.savedAssignments) ~= "table" then profile.savedAssignments = {} end
    if type(profile.savedAuras) ~= "table" then profile.savedAuras = {} end
    return profile
end

EnsureConfig = function()
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.pallyCompat) ~= "table" then WowNoteDB.pallyCompat = {} end
    local cfg = WowNoteDB.pallyCompat
    if cfg.testMode == nil then cfg.testMode = false end
    if cfg.freeAssign == nil then cfg.freeAssign = true end
    if cfg.buffFrameVisible == nil then cfg.buffFrameVisible = true end
    if type(cfg.savedAssignments) ~= "table" then cfg.savedAssignments = {} end
    if type(cfg.savedAuras) ~= "table" then cfg.savedAuras = {} end
    if type(cfg.specProfiles) ~= "table" then cfg.specProfiles = {} end

    local activeKey = GetActiveTalentGroupKey()
    local profile = EnsureSpecProfile(cfg, activeKey)
    if cfg.specProfileVersion ~= 1 then
        -- Preserve the previous single-profile configuration as the initial
        -- configuration for the talent group that is active during migration.
        if next(profile.savedAssignments) == nil then
            for name, assignment in pairs(cfg.savedAssignments) do
                if type(assignment) == "table" then
                    profile.savedAssignments[name] = {}
                    for classId = 1, MAX_CLASSES do
                        profile.savedAssignments[name][classId] = tonumber(assignment[classId]) or 0
                    end
                end
            end
        end
        if next(profile.savedAuras) == nil then
            for name, aura in pairs(cfg.savedAuras) do
                profile.savedAuras[name] = tonumber(aura) or 0
            end
        end
        cfg.specProfileVersion = 1
    end
    return cfg
end

local SendPP
local EnsurePally

local function CopyAssignments(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for name, assignment in pairs(source) do
        if type(assignment) == "table" then
            result[name] = {}
            for classId = 1, MAX_CLASSES do
                result[name][classId] = tonumber(assignment[classId]) or 0
            end
        end
    end
    return result
end

local function CopyAuras(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for name, aura in pairs(source) do result[name] = tonumber(aura) or 0 end
    return result
end

local function SavePallyAssignments(specKey)
    local cfg = EnsureConfig()
    specKey = tostring(specKey or loadedTalentGroup or GetActiveTalentGroupKey())
    local profile = EnsureSpecProfile(cfg, specKey)
    profile.savedAssignments = CopyAssignments(PallyPower_Assignments)
    profile.savedAuras = CopyAuras(PallyPower_AuraAssignments)

    -- Keep the legacy fields synchronized for downgrade compatibility and for
    -- older code paths that still inspect the single-profile values.
    cfg.savedAssignments = CopyAssignments(profile.savedAssignments)
    cfg.savedAuras = CopyAuras(profile.savedAuras)
end

local function ClearLoadedAssignments()
    for name, assignment in pairs(PallyPower_Assignments) do
        if type(assignment) == "table" then
            for classId = 1, MAX_CLASSES do assignment[classId] = 0 end
        end
    end
    for name, assignment in pairs(state.assignments) do
        if type(assignment) == "table" then
            for classId = 1, MAX_CLASSES do assignment[classId] = 0 end
        end
    end
    for name in pairs(PallyPower_AuraAssignments) do PallyPower_AuraAssignments[name] = 0 end
    for name in pairs(state.auras) do state.auras[name] = 0 end
end

local function LoadSavedPallyAssignments(specKey, replaceCurrent)
    local cfg = EnsureConfig()
    specKey = tostring(specKey or GetActiveTalentGroupKey())
    local profile = EnsureSpecProfile(cfg, specKey)
    local savedAssignments = profile.savedAssignments
    local savedAuras = profile.savedAuras

    -- Legacy values are migrated once by EnsureConfig into the then-active
    -- talent group. An empty profile for the other talent group must remain
    -- empty instead of inheriting the active spec's assignments.
    if replaceCurrent then ClearLoadedAssignments() end

    for name, assignment in pairs(savedAssignments) do
        if type(assignment) == "table" then
            EnsurePally(name)
            for classId = 1, MAX_CLASSES do
                local value = tonumber(assignment[classId]) or 0
                state.assignments[name][classId] = value
                PallyPower_Assignments[name][classId] = value
            end
        end
    end

    for name, aura in pairs(savedAuras) do
        EnsurePally(name)
        local value = tonumber(aura) or 0
        state.auras[name] = value
        PallyPower_AuraAssignments[name] = value
    end
    loadedTalentGroup = specKey
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
    local distribution = GetDistribution()
    if PallyPower and PallyPower.SendMessage then
        PallyPower:SendMessage(message)
    else
        SendAddonMessage(PP_PREFIX, message, distribution)
    end
    if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("out", PP_PREFIX .. " " .. tostring(distribution or "?"), string.len(message), true) end
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
    return nil
end

local function SetClassIconVisual(texture, classId)
    if not texture then return end
    classId = tonumber(classId) or 0
    local customIcon = GetClassIcon(classId)
    if customIcon then
        texture:SetTexture(customIcon)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        texture:Show()
        return
    end
    if classId == 11 then
        texture:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Bear")
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        texture:Show()
        return
    end
    local token = CLASS_ID_TO_TOKEN[classId]
    if CLASS_ICON_TCOORDS and token and CLASS_ICON_TCOORDS[token] then
        texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        texture:SetTexCoord(unpack(CLASS_ICON_TCOORDS[token]))
        texture:Show()
        return
    end
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    texture:Show()
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

local function AddBuffScanUnit(units, unit, forcedClassId)
    if not UnitExists or not UnitExists(unit) then return end
    local classId = forcedClassId or UnitClassId(unit)
    if not classId then return end
    if not forcedClassId and UnitIsPlayer and not UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    if not name or name == "" then return end
    table.insert(units, { unit = unit, name = name, classId = classId })
end

local function GetGroupUnitsForBuffScan()
    local units = {}
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local i
        for i = 1, GetNumRaidMembers() do
            AddBuffScanUnit(units, "raid" .. i)
            AddBuffScanUnit(units, "raidpet" .. i, 11)
        end
    else
        AddBuffScanUnit(units, "player")
        AddBuffScanUnit(units, "pet", 11)
        if GetNumPartyMembers then
            local i
            for i = 1, GetNumPartyMembers() do
                AddBuffScanUnit(units, "party" .. i)
                AddBuffScanUnit(units, "partypet" .. i, 11)
            end
        end
    end
    return units
end

local function FindUnitBuffRemaining(unit, blessingId, spellName, shortName, now)
    if not UnitBuff then return nil end
    spellName = spellName or GetBlessingSpellName(blessingId)
    if not spellName or spellName == "" then return nil end
    shortName = shortName or BLESSING_NAMES[blessingId] or ""
    now = now or (GetTime and GetTime() or 0)
    local i = 1
    while true do
        local name, _, _, _, _, _, expirationTime = UnitBuff(unit, i)
        if not name then break end
        if name == spellName or (shortName ~= "" and string.find(name, shortName, 1, true)) then
            if expirationTime and expirationTime > 0 then
                return expirationTime - now
            end
            return 999999
        end
        i = i + 1
        if i > 40 then break end
    end
    return nil
end

local function BuildMissingNamesText(names, limit)
    if type(names) ~= "table" or #names == 0 then return "" end
    limit = tonumber(limit or 3) or 3
    local parts = {}
    local i
    for i = 1, math.min(#names, limit) do
        table.insert(parts, tostring(names[i]))
    end
    if #names > limit then
        table.insert(parts, "+" .. tostring(#names - limit))
    end
    return table.concat(parts, ", ")
end

local function FormatRemaining(seconds)
    seconds = tonumber(seconds) or 0
    if seconds >= 999000 then return "active" end
    if seconds < 0 then seconds = 0 end
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds - (minutes * 60))
    return string.format("%d:%02d", minutes, secs)
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

-- Builds one shared roster/aura snapshot per refresh. The previous implementation
-- rebuilt the complete raid list and rescanned auras repeatedly for every class and
-- every button. In a 25-player raid that produced a large burst of UnitBuff calls.
local function BuildBuffSnapshot()
    local snapshot = {
        units = GetGroupUnitsForBuffScan(),
        byClass = {},
        statuses = {},
        tasks = {},
        buffChecks = 0,
    }
    if WowNoteProfiler_AddCounter then WowNoteProfiler_AddCounter("PallyBuffs.snapshotScans", 1) end

    local _, unitInfo
    for _, unitInfo in ipairs(snapshot.units) do
        snapshot.byClass[unitInfo.classId] = snapshot.byClass[unitInfo.classId] or {}
        table.insert(snapshot.byClass[unitInfo.classId], unitInfo)
    end

    local player = UnitName("player")
    local assignments = player and state.assignments[player]
    local now = GetTime and GetTime() or 0

    local classId
    for classId = 1, MAX_CLASSES do
        local blessingId = assignments and (tonumber(assignments[classId]) or 0) or 0
        if blessingId > 0 and blessingId <= 4 then
            local classUnits = snapshot.byClass[classId] or {}
            local spellName = GetBlessingSpellName(blessingId)
            local shortName = BLESSING_NAMES[blessingId] or ""
            local firstMissingUnit, firstMissingName
            local lowestUnit, lowestName, lowestRemaining
            local totalCount, buffedCount, missingCount = 0, 0, 0
            local missingNames = {}

            for _, unitInfo in ipairs(classUnits) do
                totalCount = totalCount + 1
                snapshot.buffChecks = snapshot.buffChecks + 1
                local remaining = FindUnitBuffRemaining(unitInfo.unit, blessingId, spellName, shortName, now)
                if not remaining then
                    missingCount = missingCount + 1
                    table.insert(missingNames, unitInfo.name or unitInfo.unit or "?")
                    if not firstMissingUnit then
                        firstMissingUnit = unitInfo.unit
                        firstMissingName = unitInfo.name
                    end
                else
                    buffedCount = buffedCount + 1
                    if not lowestRemaining or remaining < lowestRemaining then
                        lowestRemaining = remaining
                        lowestUnit = unitInfo.unit
                        lowestName = unitInfo.name
                    end
                end
            end

            local missing = missingCount > 0
            local targetUnit = firstMissingUnit or lowestUnit
            local targetName = firstMissingName or lowestName
            local remaining = missing and nil or lowestRemaining
            local status = {
                unit = targetUnit,
                targetName = targetName,
                classId = classId,
                className = CLASS_NAMES[classId] or "Class",
                blessingId = blessingId,
                blessingName = BLESSING_NAMES[blessingId] or "Blessing",
                spellName = spellName,
                remaining = remaining,
                missing = missing,
                hasUnit = totalCount > 0,
                totalCount = totalCount,
                buffedCount = buffedCount,
                missingCount = missingCount,
                missingNames = missingNames,
                partial = missingCount > 0 and buffedCount > 0,
            }
            snapshot.statuses[classId] = status
            if targetUnit and (missing or (remaining and remaining <= 300)) then
                table.insert(snapshot.tasks, status)
            end
        end
    end

    table.sort(snapshot.tasks, function(a, b)
        if a.missing ~= b.missing then return a.missing end
        return (a.remaining or 0) < (b.remaining or 0)
    end)
    if WowNoteProfiler_SetGauge then
        WowNoteProfiler_SetGauge("PallyBuffs.unitsInLastSnapshot", table.getn(snapshot.units))
        WowNoteProfiler_SetGauge("PallyBuffs.buffChecksInLastSnapshot", snapshot.buffChecks)
        WowNoteProfiler_SetGauge("PallyBuffs.tasksInLastSnapshot", table.getn(snapshot.tasks))
    end
    return snapshot
end

local function BuildBuffTasks(snapshot)
    snapshot = snapshot or BuildBuffSnapshot()
    return snapshot.tasks, snapshot
end

local function SelectAutoBuffTask(snapshot)
    local tasks
    tasks, snapshot = BuildBuffTasks(snapshot)
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
    return bestTask, tasks, snapshot
end

local function BuildClassBuffStatus(classId, snapshot)
    snapshot = snapshot or BuildBuffSnapshot()
    return snapshot.statuses[tonumber(classId) or 0], snapshot
end

local function SelectClassBuffTask(classId, snapshot)
    local status
    status, snapshot = BuildClassBuffStatus(classId, snapshot)
    if not status or not status.spellName or not status.unit then return nil, snapshot end
    if not IsBuffTaskInRange(status) then return nil, snapshot end
    return status, snapshot
end

local function SetSecureBuffAttributes(button, task)
    if not button then return nil end
    -- SecureActionButton attributes must be prepared while out of combat. In combat
    -- the existing spell/unit attributes stay in place so the button can still cast.
    if InCombatLockdown and InCombatLockdown() then
        return button.wowNotePreparedTask
    end

    button.wowNotePreparedTask = task
    if task and task.spellName and task.unit and UnitExists and UnitExists(task.unit) then
        button:SetAttribute("type", "spell")
        button:SetAttribute("unit", task.unit)
        button:SetAttribute("spell", task.spellName)
        return task
    end

    button:SetAttribute("unit", nil)
    button:SetAttribute("spell", nil)
    return nil
end

local function PrepareAutoBuffButton(button, mousebutton)
    -- Out of combat this computes and writes the next secure spell/unit pair. In
    -- combat it deliberately reuses the already prepared attributes, because the
    -- 3.3.5 secure environment blocks changing protected action attributes there.
    if not button then return nil end

    if InCombatLockdown and InCombatLockdown() then
        local prepared = button.wowNotePreparedTask
        if prepared then
            if time then
                autoBuffedList[prepared.targetName or prepared.unit] = time()
            end
            previousAutoBuffedUnit = { name = prepared.targetName or prepared.unit, unit = prepared.unit }
        end
        return prepared
    end

    local task
    if button.wowNoteClassId then
        task = SelectClassBuffTask(button.wowNoteClassId)
    else
        task = SelectAutoBuffTask()
    end
    SetSecureBuffAttributes(button, task)
    if UpdateCastButtonVisual and not button.wowNoteClassId then
        UpdateCastButtonVisual(task)
    end

    if task and task.spellName and task.unit and UnitExists and UnitExists(task.unit) then
        if time then
            autoBuffedList[task.targetName or task.unit] = time()
        end
        previousAutoBuffedUnit = { name = task.targetName or task.unit, unit = task.unit }
        return task
    end

    return nil
end

local function ClearAutoBuffButton(button)
    -- Do not clear protected attributes in combat; that would disable in-combat
    -- buffing and may be blocked by the secure frame rules. Out of combat we keep
    -- the attributes prepared by RefreshBuffFrame instead of wiping them after
    -- every click.
    if not button then return end
    if InCombatLockdown and InCombatLockdown() then return end
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
    SavePallyAssignments()
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
    SavePallyAssignments()
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
    SavePallyAssignments()
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
    SavePallyAssignments()
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
        local now = GetTime and GetTime() or 0
        ChatControl[sender] = ChatControl[sender] or { time = 0 }
        if now - (tonumber(ChatControl[sender].time) or 0) < 15 then return end
        ChatControl[sender].time = now
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
    buffFrame:SetWidth(156)
    buffFrame:SetHeight(408)
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

    buffFrame.assignButton = MakeButton(buffFrame, "Assign", 60, 20)
    buffFrame.assignButton:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 78, -6)
    buffFrame.assignButton:SetScript("OnClick", function()
        if WowNote_OpenPallyBuffs then
            WowNote_OpenPallyBuffs()
        end
    end)
    AddTooltip(buffFrame.assignButton, "Assignments", "Opens the PallyBuffs distribution menu directly.")

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
        -- UNIT_AURA normally drives the refresh. This short fallback also covers
        -- private-server clients that deliver the aura event late or not at all.
        if QueueVisualRefresh then QueueVisualRefresh(SPELLCAST_REFRESH_DELAY) end
    end)
    buffFrame.castButton:SetScript("OnEnter", function(self)
        local task = self.wowNoteTooltipTask
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("PallyBuffs cast button", 1, 1, 1)
        if task then
            GameTooltip:AddDoubleLine("|cffffd100Left-click|r", "Cast " .. tostring(task.blessingName or "Buff") .. " for " .. tostring(task.className or "Class") .. ".", 1, 1, 1, 0.85, 0.85, 0.85)
        else
            GameTooltip:AddDoubleLine("|cffffd100Left-click|r", "No missing buff to cast.", 1, 1, 1, 0.85, 0.85, 0.85)
        end
        GameTooltip:AddLine("The overlay refreshes from aura, cast and group events while visible.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    buffFrame.castButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    buffFrame.summary = buffFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buffFrame.summary:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 64, -34)
    buffFrame.summary:SetWidth(82)
    buffFrame.summary:SetJustifyH("LEFT")
    buffFrame.summary:SetText("Scanning...")

    buffFrame.popup = buffFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    buffFrame.popup:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 12, -78)
    buffFrame.popup:SetWidth(132)
    buffFrame.popup:SetJustifyH("LEFT")
    buffFrame.popup:SetText("")
    buffFrame.popup:Hide()

    buffFrameRows = {}
    local classId
    for classId = 1, MAX_CLASSES do
        local row = CreateFrame("Button", "WowNotePallyBuffsClassRow" .. classId, buffFrame, "SecureActionButtonTemplate")
        row:SetWidth(132)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 12, -76 - ((classId - 1) * 29))
        row:RegisterForClicks("AnyUp")
        row:SetAttribute("type", "spell")
        row:SetAttribute("unit", nil)
        row:SetAttribute("spell", nil)
        row.wowNoteClassId = classId
        row:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        row:SetBackdropColor(0.0, 0.20, 0.02, 0.92)
        row:SetBackdropBorderColor(0.2, 0.8, 0.25, 1)
        row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.classIcon:SetWidth(22)
        row.classIcon:SetHeight(22)
        row.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.buffIcon = row:CreateTexture(nil, "ARTWORK")
        row.buffIcon:SetPoint("LEFT", row.classIcon, "RIGHT", 3, 0)
        row.buffIcon:SetWidth(22)
        row.buffIcon:SetHeight(22)
        row.buffIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.timeText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.timeText:SetJustifyH("RIGHT")
        row.timeText:SetText("")
        row:SetScript("PreClick", function(self, mouseButton)
            PrepareAutoBuffButton(self, mouseButton)
        end)
        row:SetScript("PostClick", function(self)
            ClearAutoBuffButton(self)
            if QueueVisualRefresh then QueueVisualRefresh(SPELLCAST_REFRESH_DELAY) end
        end)
        AddActionTooltip(row, CLASS_NAMES[classId] or "Class", {
            { key = "Left-click", text = "Cast this class assignment if a valid target is available." },
            { text = "The row shows class icon, assigned blessing and the lowest remaining duration for that class." },
        })
        buffFrameRows[classId] = row
    end

    buffFrame:SetScript("OnShow", function(self)
        if UpdateRuntimeEventRegistration then UpdateRuntimeEventRegistration(true) end
        if not self.wowNoteRefreshInProgress and QueueVisualRefresh then
            QueueVisualRefresh(0)
        end
    end)
    buffFrame:SetScript("OnHide", function(self)
        if UpdateRuntimeEventRegistration then UpdateRuntimeEventRegistration(true) end
    end)
end

UpdateSecureCastButton = function(task)
    if not buffFrame or not buffFrame.castButton then return end
    buffFrame.nextTask = task
    SetSecureBuffAttributes(buffFrame.castButton, task)
end

UpdateCastButtonVisual = function(task)
    if not buffFrame or not buffFrame.castButton or not buffFrame.castButton.icon then return end

    if task then
        buffFrame.castButton.icon:SetTexture(GetBlessingIcon(task.blessingId))
        buffFrame.castButton.icon:Show()
        buffFrame.castButton.text:SetText("")
        if buffFrame.summary then
            buffFrame.summary:SetText((task.blessingName or "Buff") .. " -> " .. (task.className or "Class"))
        end
    else
        buffFrame.castButton.icon:SetTexture("Interface\\Icons\\Spell_Holy_SealOfSalvation")
        buffFrame.castButton.icon:Show()
        buffFrame.castButton.text:SetText("")
        if buffFrame.summary then
            buffFrame.summary:SetText("All assigned buffs OK")
        end
    end
end

RefreshBuffFrame = function()
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("pallyBuffs") then
        if buffFrame then buffFrame:Hide() end
        return
    end
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
    buffFrame.wowNoteRefreshInProgress = true
    buffFrame:Show()
    buffFrame.wowNoteRefreshInProgress = nil
    if UpdateRuntimeEventRegistration then UpdateRuntimeEventRegistration(true) end

    local snapshot = BuildBuffSnapshot()
    local task, tasks = SelectAutoBuffTask(snapshot)
    tasks = tasks or {}
    buffFrame.nextTask = task
    UpdateSecureCastButton(task)
    UpdateCastButtonVisual(task)

    local visibleRows = 0
    local classId
    for classId = 1, MAX_CLASSES do
        local row = buffFrameRows[classId]
        local status = BuildClassBuffStatus(classId, snapshot)
        if row and status then
            visibleRows = visibleRows + 1
            SetSecureBuffAttributes(row, SelectClassBuffTask(classId, snapshot))
            if not (InCombatLockdown and InCombatLockdown()) then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", 12, -76 - ((visibleRows - 1) * 29))
            end
            SetClassIconVisual(row.classIcon, classId)
            row.buffIcon:SetTexture(GetBlessingIcon(status.blessingId))
            if not status.hasUnit then
                row.timeText:SetText("--")
                row.timeText:SetTextColor(0.55, 0.55, 0.55)
                row:SetBackdropColor(0.10, 0.10, 0.10, 0.88)
                row:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            elseif status.missing then
                local countText = tostring(status.buffedCount or 0) .. "/" .. tostring(status.totalCount or 0)
                if status.partial then
                    row.timeText:SetText(countText .. " MISS")
                else
                    row.timeText:SetText("MISS " .. countText)
                end
                row.timeText:SetTextColor(1.0, 0.15, 0.15)
                row:SetBackdropColor(0.26, 0.00, 0.00, 0.92)
                row:SetBackdropBorderColor(0.9, 0.15, 0.15, 1)
            elseif status.remaining and status.remaining <= 300 then
                row.timeText:SetText(FormatRemaining(status.remaining) .. " " .. tostring(status.buffedCount or 0) .. "/" .. tostring(status.totalCount or 0))
                row.timeText:SetTextColor(1.0, 0.82, 0.05)
                row:SetBackdropColor(0.22, 0.14, 0.00, 0.92)
                row:SetBackdropBorderColor(0.9, 0.72, 0.1, 1)
            else
                row.timeText:SetText(FormatRemaining(status.remaining) .. " " .. tostring(status.buffedCount or 0) .. "/" .. tostring(status.totalCount or 0))
                row.timeText:SetTextColor(0.15, 1.0, 0.15)
                row:SetBackdropColor(0.0, 0.20, 0.02, 0.92)
                row:SetBackdropBorderColor(0.2, 0.8, 0.25, 1)
            end
            if not (InCombatLockdown and InCombatLockdown()) then
                row:Show()
            end
        elseif row then
            if not (InCombatLockdown and InCombatLockdown()) then
                row:Hide()
            end
        end
    end
    if visibleRows == 0 and buffFrame.popup then
        buffFrame.popup:Show()
        buffFrame.popup:SetText("No class assignments.")
    elseif buffFrame.popup then
        buffFrame.popup:Hide()
    end

    buffFrame.castButton.wowNoteTooltipTask = task
end

Refresh = function(syncNativeState, skipOverlayQueue)
    if not frame or not scrollChild then return end

    if syncNativeState then SyncFromPallyPower() end
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
        if not skipOverlayQueue and QueueVisualRefresh then QueueVisualRefresh(0, EnsureConfig().buffFrameVisible) end
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
    SetStatus("Visible paladins: " .. table.getn(pallies)
        .. " | Spec " .. tostring(GetActiveTalentGroupKey())
        .. (IsTestModeEnabled() and " | Test Mode" or "")
        .. (IsPallyPowerLoaded() and " | Native compatible client detected" or " | Standalone mode"))
    if not skipOverlayQueue and QueueVisualRefresh then QueueVisualRefresh(0, EnsureConfig().buffFrameVisible) end
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
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetFrameLevel(100)
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
    refreshButton:SetScript("OnClick", function() Refresh(true) end)

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
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("pallyBuffs") then
        Print("PallyBuffs is disabled in WowNote settings.")
        return
    end
    CreateUI()
    frame:Show()
    RaiseFrame(frame)
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

local refreshScheduler = CreateFrame("Frame")
local eventFrame
local pendingVisualAt
local pendingRosterAt
local pendingSaveAt
local pendingShowConfiguredBuffFrame
local pendingRefreshAssignmentUI

local function IsPallyBuffsModuleEnabled()
    return not (WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("pallyBuffs"))
end

local function HasVisiblePallyUI()
    return (frame and frame:IsVisible()) or (buffFrame and buffFrame:IsShown())
end

local function HasVisibleBuffOverlay()
    return buffFrame and buffFrame:IsShown()
end

local function ClearPendingRefreshes()
    pendingVisualAt = nil
    pendingRosterAt = nil
    pendingSaveAt = nil
    pendingShowConfiguredBuffFrame = nil
    pendingRefreshAssignmentUI = nil
end

local function EarliestPendingTime()
    local earliest = pendingVisualAt
    if pendingRosterAt and (not earliest or pendingRosterAt < earliest) then earliest = pendingRosterAt end
    if pendingSaveAt and (not earliest or pendingSaveAt < earliest) then earliest = pendingSaveAt end
    return earliest
end

local ProcessScheduledWork
local ArmRefreshScheduler

local function StopRefreshSchedulerIfIdle()
    if EarliestPendingTime() then return false end
    WowNoteProfiler_SetScript(refreshScheduler, "OnUpdate", "PallyBuffs.RefreshScheduler", nil)
    return true
end

local function RunVisibleRefresh(allowConfiguredBuffFrame, refreshAssignmentUI)
    if refreshAssignmentUI and frame and frame:IsVisible() then
        Refresh(false, true)
    end
    if buffFrame and buffFrame:IsShown() then
        RefreshBuffFrame()
    elseif allowConfiguredBuffFrame and EnsureConfig().buffFrameVisible and IsPlayerPaladin() then
        RefreshBuffFrame()
    end
end

local function RefreshSchedulerOnUpdate()
    local due = EarliestPendingTime()
    local now = GetTime and GetTime() or 0
    if due and now >= due then ProcessScheduledWork() end
end

ArmRefreshScheduler = function()
    if not EarliestPendingTime() then
        StopRefreshSchedulerIfIdle()
        return
    end
    -- The scheduler exists only while work is pending. This avoids permanent
    -- background polling and stays compatible with unmodified 3.3.5a clients.
    WowNoteProfiler_SetScript(refreshScheduler, "OnUpdate", "PallyBuffs.RefreshScheduler", RefreshSchedulerOnUpdate)
end

ProcessScheduledWork = function()
    if not IsPallyBuffsModuleEnabled() then
        ClearPendingRefreshes()
        StopRefreshSchedulerIfIdle()
        return
    end

    local now = GetTime and GetTime() or 0
    local rosterDue = pendingRosterAt and now >= pendingRosterAt
    local visualDue = pendingVisualAt and now >= pendingVisualAt
    local saveDue = pendingSaveAt and now >= pendingSaveAt

    if rosterDue then
        pendingRosterAt = nil
        if WowNoteProfiler_AddCounter then WowNoteProfiler_AddCounter("PallyBuffs.rosterRefreshes", 1) end
        SyncFromPallyPower()
        AnnounceSelf()
        pendingRefreshAssignmentUI = true
        visualDue = true
    end
    if saveDue then
        pendingSaveAt = nil
        if WowNoteProfiler_AddCounter then WowNoteProfiler_AddCounter("PallyBuffs.assignmentSaves", 1) end
        SavePallyAssignments()
    end
    if visualDue then
        local allowConfiguredBuffFrame = pendingShowConfiguredBuffFrame == true
        local refreshAssignmentUI = pendingRefreshAssignmentUI == true
        pendingVisualAt = nil
        pendingShowConfiguredBuffFrame = nil
        pendingRefreshAssignmentUI = nil
        if WowNoteProfiler_AddCounter then WowNoteProfiler_AddCounter("PallyBuffs.visualRefreshes", 1) end
        if HasVisiblePallyUI() or allowConfiguredBuffFrame then
            RunVisibleRefresh(allowConfiguredBuffFrame, refreshAssignmentUI)
        end
    end

    if not StopRefreshSchedulerIfIdle() then ArmRefreshScheduler() end
end

QueueVisualRefresh = function(delay, allowConfiguredBuffFrame, refreshAssignmentUI)
    if not HasVisiblePallyUI() and not allowConfiguredBuffFrame then return end
    local now = GetTime and GetTime() or 0
    local due = now + (tonumber(delay) or 0)
    if not pendingVisualAt or due < pendingVisualAt then pendingVisualAt = due end
    if allowConfiguredBuffFrame then pendingShowConfiguredBuffFrame = true end
    if refreshAssignmentUI then pendingRefreshAssignmentUI = true end
    ArmRefreshScheduler()
end

local function QueueRosterRefresh(delay)
    local now = GetTime and GetTime() or 0
    local due = now + (tonumber(delay) or ROSTER_REFRESH_DELAY)
    if not pendingRosterAt or due < pendingRosterAt then pendingRosterAt = due end
    ArmRefreshScheduler()
end

local function QueueSavedAssignmentRefresh(delay)
    local now = GetTime and GetTime() or 0
    local due = now + (tonumber(delay) or SAVE_REFRESH_DELAY)
    if not pendingSaveAt or due < pendingSaveAt then pendingSaveAt = due end
    ArmRefreshScheduler()
end

local function IsRelevantAuraUnit(unit)
    unit = tostring(unit or "")
    if unit == "player" or unit == "pet" then return true end
    if string.find(unit, "^party%d+$") or string.find(unit, "^partypet%d+$") then return true end
    if string.find(unit, "^raid%d+$") or string.find(unit, "^raidpet%d+$") then return true end
    return false
end

local function ApplyTalentGroupProfile()
    local newKey = GetActiveTalentGroupKey()
    if loadedTalentGroup and loadedTalentGroup ~= newKey then
        SavePallyAssignments(loadedTalentGroup)
        LoadSavedPallyAssignments(newKey, true)
        if WowNoteProfiler_AddCounter then WowNoteProfiler_AddCounter("PallyBuffs.specProfileSwitches", 1) end
        AnnounceSelf()
        SendPP("REQ")
        QueueVisualRefresh(0, EnsureConfig().buffFrameVisible, true)
        SetStatus("Loaded PallyBuffs profile for talent spec " .. tostring(newKey) .. ".")
    else
        loadedTalentGroup = newKey
        AnnounceSelf()
        QueueVisualRefresh(AURA_REFRESH_DELAY, false, frame and frame:IsVisible())
    end
end

function WowNote_PallyBuffs_SetEnabled(enabled)
    if WowNoteProfiler_SetGauge then WowNoteProfiler_SetGauge("PallyBuffs.moduleEnabled", enabled and 1 or 0) end
    if not enabled then
        -- During early addon initialization the settings module may apply the
        -- disabled state before saved assignments have been loaded. Only save
        -- after a talent-group profile is known, otherwise an empty runtime
        -- table could overwrite the persisted profile.
        if loadedTalentGroup then SavePallyAssignments(loadedTalentGroup) end
        ClearPendingRefreshes()
        StopRefreshSchedulerIfIdle()
        if frame then frame:Hide() end
        if buffFrame then buffFrame:Hide() end
        if UpdateRuntimeEventRegistration then UpdateRuntimeEventRegistration(false) end
        return
    end
    EnsureConfig()
    loadedTalentGroup = loadedTalentGroup or GetActiveTalentGroupKey()
    SetFreeAssignEnabled(IsFreeAssignEnabled(), false)
    if UpdateRuntimeEventRegistration then UpdateRuntimeEventRegistration(true) end
    QueueRosterRefresh(0.05)
    if EnsureConfig().buffFrameVisible and IsPlayerPaladin() then
        QueueVisualRefresh(0, true)
    end
end

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

UpdateRuntimeEventRegistration = function(enabled)
    if not eventFrame then return end
    enabled = enabled and IsPallyBuffsModuleEnabled()
    local baseEvents = {
        "CHAT_MSG_ADDON", "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED",
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED",
        "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED", "PLAYER_LOGOUT"
    }
    local overlayEvents = { "UNIT_AURA", "UNIT_PET", "UNIT_SPELLCAST_SUCCEEDED" }
    local i
    for i = 1, table.getn(baseEvents) do
        if enabled then
            eventFrame:RegisterEvent(baseEvents[i])
        elseif eventFrame.UnregisterEvent then
            eventFrame:UnregisterEvent(baseEvents[i])
        end
    end
    local trackOverlay = enabled and HasVisibleBuffOverlay()
    for i = 1, table.getn(overlayEvents) do
        if trackOverlay then
            eventFrame:RegisterEvent(overlayEvents[i])
        elseif eventFrame.UnregisterEvent then
            eventFrame:UnregisterEvent(overlayEvents[i])
        end
    end
end

WowNoteProfiler_SetScript(eventFrame, "OnEvent", "PallyBuffs.Events", function(self, event, arg1, arg2, arg3, arg4)
    local moduleEnabled = IsPallyBuffsModuleEnabled()
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME or arg1 == "WoWNote" or arg1 == "PallyPower" then
            if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PP_PREFIX) end
            EnsureConfig()
            loadedTalentGroup = GetActiveTalentGroupKey()
            LoadSavedPallyAssignments(loadedTalentGroup, false)
            RegisterSlashCommands()
            UpdateRuntimeEventRegistration(moduleEnabled)
            if moduleEnabled then
                SyncFromPallyPower()
                SetFreeAssignEnabled(IsFreeAssignEnabled(), false)
                AnnounceSelf()
                QueueVisualRefresh(0, EnsureConfig().buffFrameVisible)
            end
        end
    elseif event == "PLAYER_LOGIN" then
        if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PP_PREFIX) end
        EnsureConfig()
        loadedTalentGroup = GetActiveTalentGroupKey()
        LoadSavedPallyAssignments(loadedTalentGroup, true)
        RegisterSlashCommands()
        UpdateRuntimeEventRegistration(moduleEnabled)
        if moduleEnabled then
            SyncFromPallyPower()
            SetFreeAssignEnabled(IsFreeAssignEnabled(), false)
            AnnounceSelf()
            if EnsureConfig().buffFrameVisible then QueueVisualRefresh(0, true) end
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, distribution, sender = arg1, arg2, arg3, arg4
        if moduleEnabled and prefix == PP_PREFIX then
            if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("in", PP_PREFIX .. " " .. tostring(distribution or "?"), string.len(tostring(message or "")), true) end
            ParseAddonMessage(sender, message)
            QueueSavedAssignmentRefresh(SAVE_REFRESH_DELAY)
            QueueVisualRefresh(COMM_REFRESH_DELAY, false, frame and frame:IsVisible())
        end
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED"
        or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if moduleEnabled then QueueRosterRefresh(ROSTER_REFRESH_DELAY) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if moduleEnabled then QueueVisualRefresh(0, false, frame and frame:IsVisible()) end
    elseif event == "UNIT_AURA" then
        if moduleEnabled and HasVisibleBuffOverlay() and IsRelevantAuraUnit(arg1) then
            QueueVisualRefresh(AURA_REFRESH_DELAY)
        end
    elseif event == "UNIT_PET" then
        if moduleEnabled and HasVisibleBuffOverlay() then
            QueueVisualRefresh(AURA_REFRESH_DELAY)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if moduleEnabled and HasVisibleBuffOverlay() and arg1 == "player" then
            QueueVisualRefresh(SPELLCAST_REFRESH_DELAY)
        end
    elseif event == "PLAYER_LOGOUT" then
        if moduleEnabled then SavePallyAssignments(loadedTalentGroup or GetActiveTalentGroupKey()) end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        if moduleEnabled then ApplyTalentGroupProfile() end
    elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" then
        if moduleEnabled then
            if GetActiveTalentGroupKey() ~= loadedTalentGroup then
                ApplyTalentGroupProfile()
            else
                AnnounceSelf()
                QueueVisualRefresh(AURA_REFRESH_DELAY, false, frame and frame:IsVisible())
            end
        end
    end
end)

UpdateRuntimeEventRegistration(IsPallyBuffsModuleEnabled())
