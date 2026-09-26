-- WowNote Raid Spell Tracker
-- Multi-spell raid utility cooldown order/overlay synchronization for WoW 3.3.5a.

WowNote_RaidPlanner = WowNote_RaidPlanner or {}
local RP = WowNote_RaidPlanner
local ST = {}
local UpdateOverlay
local MergeOrderWithRoster
ST.liveTargets = {}
ST.talentCache = {}
ST.talentInspect = { elapsed = 0, pending = nil, pendingElapsed = 0 }
RP.SpellTracker = ST

local ADDON_PREFIX = "WNSpell"
local MAX_ROWS = 25
local CONFIG_ROWS = 9
local UPDATE_INTERVAL = 0.20
local SELF_STATUS_INTERVAL = 1.00
local SYNC_INTERVAL = 12.00
local TALENT_INSPECT_INTERVAL = 0.75
local TALENT_INSPECT_TIMEOUT = 4.00
local TALENT_CACHE_TTL = 120.00
local RESOURCE_SAMPLE_INTERVAL = 0.80

local SPELLS = {
    -- Paladin
    { id = 1022,  name = "Hand of Protection", class = "PALADIN", cooldown = 300, baseline = true },
    { id = 6940,  name = "Hand of Sacrifice", class = "PALADIN", cooldown = 120, baseline = true },
    { id = 1038,  name = "Hand of Salvation", class = "PALADIN", cooldown = 120, baseline = true },
    { id = 1044,  name = "Hand of Freedom", class = "PALADIN", cooldown = 25, baseline = true },
    { id = 633,   name = "Lay on Hands", class = "PALADIN", cooldown = 1200, baseline = true },
    { id = 19752, name = "Divine Intervention", class = "PALADIN", cooldown = 1200, baseline = true },
    { id = 31821, name = "Aura Mastery", class = "PALADIN", cooldown = 120, talent = true },
    { id = 64205, name = "Divine Sacrifice", class = "PALADIN", cooldown = 120, talent = true, inspectTalent = true },
    { id = 2812,  name = "Holy Wrath", class = "PALADIN", cooldown = 30, baseline = true },
    { id = 853,   name = "Hammer of Justice", class = "PALADIN", cooldown = 60, baseline = true },

    -- Priest
    { id = 33206, name = "Pain Suppression", class = "PRIEST", cooldown = 180, talent = true },
    { id = 47788, name = "Guardian Spirit", class = "PRIEST", cooldown = 180, talent = true },
    { id = 10060, name = "Power Infusion", class = "PRIEST", cooldown = 120, talent = true },
    { id = 64843, name = "Divine Hymn", class = "PRIEST", cooldown = 480, baseline = true },
    { id = 64901, name = "Hymn of Hope", class = "PRIEST", cooldown = 360, baseline = true },
    { id = 15487, name = "Silence", class = "PRIEST", cooldown = 45, talent = true },

    -- Druid
    { id = 29166, name = "Innervate", class = "DRUID", cooldown = 180, baseline = true },
    { id = 20484, name = "Rebirth", class = "DRUID", cooldown = 600, baseline = true },
    { id = 740,   name = "Tranquility", class = "DRUID", cooldown = 480, baseline = true },
    { id = 50516, name = "Typhoon", class = "DRUID", cooldown = 20, talent = true },
    { id = 17116, name = "Nature's Swiftness", class = "DRUID", cooldown = 180, talent = true },
    { id = 16979, name = "Feral Charge - Bear", class = "DRUID", cooldown = 15, talent = true },

    -- Shaman
    { id = 2825,  name = "Bloodlust", class = "SHAMAN", cooldown = 300, baseline = true },
    { id = 32182, name = "Heroism", class = "SHAMAN", cooldown = 300, baseline = true },
    { id = 16190, name = "Mana Tide Totem", class = "SHAMAN", cooldown = 300, talent = true },
    { id = 51490, name = "Thunderstorm", class = "SHAMAN", cooldown = 45, talent = true },
    { id = 57994, name = "Wind Shear", class = "SHAMAN", cooldown = 6, baseline = true },
    { id = 8177,  name = "Grounding Totem", class = "SHAMAN", cooldown = 15, baseline = true },
    { id = 2062,  name = "Earth Elemental Totem", class = "SHAMAN", cooldown = 600, baseline = true },
    { id = 2894,  name = "Fire Elemental Totem", class = "SHAMAN", cooldown = 600, baseline = true },

    -- Death Knight
    { id = 51052, name = "Anti-Magic Zone", class = "DEATHKNIGHT", cooldown = 120, talent = true },
    { id = 49016, name = "Hysteria", class = "DEATHKNIGHT", cooldown = 180, talent = true },
    { id = 49576, name = "Death Grip", class = "DEATHKNIGHT", cooldown = 35, baseline = true },
    { id = 47476, name = "Strangulate", class = "DEATHKNIGHT", cooldown = 120, baseline = true },
    { id = 47528, name = "Mind Freeze", class = "DEATHKNIGHT", cooldown = 10, baseline = true },
    { id = 42650, name = "Army of the Dead", class = "DEATHKNIGHT", cooldown = 600, baseline = true },

    -- Warrior
    { id = 1161,  name = "Challenging Shout", class = "WARRIOR", cooldown = 180, baseline = true },
    { id = 3411,  name = "Intervene", class = "WARRIOR", cooldown = 30, baseline = true },
    { id = 871,   name = "Shield Wall", class = "WARRIOR", cooldown = 300, baseline = true },
    { id = 12975, name = "Last Stand", class = "WARRIOR", cooldown = 180, talent = true },
    { id = 46968, name = "Shockwave", class = "WARRIOR", cooldown = 20, talent = true },
    { id = 6552,  name = "Pummel", class = "WARRIOR", cooldown = 10, baseline = true },

    -- Hunter
    { id = 34477, name = "Misdirection", class = "HUNTER", cooldown = 30, baseline = true },
    { id = 34490, name = "Silencing Shot", class = "HUNTER", cooldown = 20, talent = true },
    { id = 5384,  name = "Feign Death", class = "HUNTER", cooldown = 30, baseline = true },

    -- Rogue
    { id = 57934, name = "Tricks of the Trade", class = "ROGUE", cooldown = 30, baseline = true },
    { id = 1766,  name = "Kick", class = "ROGUE", cooldown = 10, baseline = true },
    { id = 51722, name = "Dismantle", class = "ROGUE", cooldown = 60, baseline = true },

    -- Mage
    { id = 2139,  name = "Counterspell", class = "MAGE", cooldown = 24, baseline = true },
    { id = 45438, name = "Ice Block", class = "MAGE", cooldown = 300, baseline = true },

    -- Warlock
    { id = 30283, name = "Shadowfury", class = "WARLOCK", cooldown = 20, talent = true },
    { id = 6789,  name = "Death Coil", class = "WARLOCK", cooldown = 120, baseline = true },
}

local SPELL_BY_ID = {}
for _, spell in ipairs(SPELLS) do SPELL_BY_ID[spell.id] = spell end

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WowNote|r Spell Tracker: " .. tostring(msg or "")) end
end

local function Now() return GetTime and GetTime() or 0 end
local function Trim(text)
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end
local function NormalizeName(name)
    name = Trim(name)
    name = string.gsub(name, "%-.*$", "")
    return name
end
local function PlayerName() return NormalizeName(UnitName and UnitName("player") or "") end

local function InitDB()
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.raidSpellTracker) ~= "table" then WowNoteDB.raidSpellTracker = {} end
    local db = WowNoteDB.raidSpellTracker
    if type(db.orders) ~= "table" then db.orders = {} end
    if type(db.targets) ~= "table" then db.targets = {} end
    if type(db.targetPositions) ~= "table" then db.targetPositions = {} end
    if type(db.resourceMonitors) ~= "table" then db.resourceMonitors = {} end
    if type(db.overlayScales) ~= "table" then db.overlayScales = {} end
    if type(db.overlaySizes) ~= "table" then db.overlaySizes = {} end
    if tonumber(db.overlaySizeSchema) ~= 4 then
        -- Older builds saved widths of 560-900 px. Reset them once so the
        -- smaller HUD layout is actually visible after updating the addon.
        db.overlaySizes = {}
        db.overlaySizeSchema = 4
    end
    if type(db.enabledSpells) ~= "table" then
        db.enabledSpells = {}
        db.enabledSpells[1022] = true
        if SPELL_BY_ID[tonumber(db.selectedSpellId)] then db.enabledSpells[tonumber(db.selectedSpellId)] = true end
    end
    if not SPELL_BY_ID[tonumber(db.selectedSpellId)] then db.selectedSpellId = 1022 end
    if db.channels == nil then db.channels = "/raid" end
    if db.warnTurn == nil then db.warnTurn = true end
    if db.warnNext == nil then db.warnNext = true end
    if db.autoOpenRemote == nil then db.autoOpenRemote = true end
    if db.turnSound == nil then db.turnSound = "RaidWarning" end
    if db.nextSound == nil then db.nextSound = "ReadyCheck" end
    return db
end

local function SelectedSpell()
    local db = InitDB()
    return SPELL_BY_ID[tonumber(db.selectedSpellId)] or SPELLS[1]
end
local function IsSpellEnabled(spellId) return InitDB().enabledSpells[tonumber(spellId)] == true end
local function SetSpellEnabled(spellId, enabled) InitDB().enabledSpells[tonumber(spellId)] = enabled and true or nil end
-- Monitoring preferences are local to this client and stored per tracked spell.
-- They deliberately do not alter the shared caster order or the secure cast target.
local function GetResourceMonitor(spellId)
    local db = InitDB()
    local key = tostring(tonumber(spellId) or spellId)
    local value = db.resourceMonitors[key]
    if type(value) ~= "table" then
        value = { mode = "off", threshold = 65, alert = false }
        db.resourceMonitors[key] = value
    end
    if value.mode ~= "mana" and value.mode ~= "health" then value.mode = "off" end
    value.threshold = math.floor(math.max(1, math.min(100, tonumber(value.threshold) or 65)))
    if value.alert == nil then value.alert = false end
    return value
end

-- UnitPower(unit, 0) explicitly reads mana (also for shapeshifted druids).
-- Both UnitPower and UnitPowerMax were present in the WotLK 3.3.5 API.
local function ReadTargetResourcePercent(unit, mode)
    if not unit or not UnitExists or not UnitExists(unit) then return nil end
    if UnitIsConnected and not UnitIsConnected(unit) then return nil end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return nil end
    local current, maximum
    if mode == "mana" then
        if not UnitPower or not UnitPowerMax then return nil end
        current, maximum = UnitPower(unit, 0), UnitPowerMax(unit, 0)
    elseif mode == "health" then
        if not UnitHealth or not UnitHealthMax then return nil end
        current, maximum = UnitHealth(unit), UnitHealthMax(unit)
    else
        return nil
    end
    current, maximum = tonumber(current), tonumber(maximum)
    if not current or not maximum or maximum <= 0 then return nil end
    return math.floor((math.max(0, math.min(current, maximum)) * 100 / maximum) + 0.5)
end

local function SampleTargetResourcePercent(state, unit, targetName, mode)
    if not state or not unit or mode == "off" then return nil end
    state.resourceSamples = state.resourceSamples or {}
    local key = tostring(unit) .. ":" .. string.lower(NormalizeName(targetName)) .. ":" .. mode
    local entry = state.resourceSamples[key]
    if entry and (Now() - entry.at) < RESOURCE_SAMPLE_INTERVAL then return entry.value end
    local value = ReadTargetResourcePercent(unit, mode)
    state.resourceSamples[key] = { at = Now(), value = value }
    return value
end
local function ClampOverlayScale(value)
    value = tonumber(value) or 1
    if value < 0.60 then value = 0.60 end
    if value > 1.60 then value = 1.60 end
    return math.floor((value * 10) + 0.5) / 10
end
local function GetOverlayScale(spellId)
    return ClampOverlayScale(InitDB().overlayScales[tostring(tonumber(spellId) or spellId)] or 1)
end
local function SetOverlayScale(spellId, value)
    local scale = ClampOverlayScale(value)
    InitDB().overlayScales[tostring(tonumber(spellId) or spellId)] = scale
    return scale
end
local function GetOverlaySize(spellId)
    local key = tostring(tonumber(spellId) or spellId)
    local saved = InitDB().overlaySizes[key]
    local width = saved and tonumber(saved.width) or 420
    local height = saved and tonumber(saved.height) or 68
    if width < 280 then width = 280 end
    if width > 900 then width = 900 end
    if height < 68 then height = 68 end
    if height > 600 then height = 600 end
    return width, height
end
local function SaveOverlaySize(spellId, frame)
    if not frame then return end
    local key = tostring(tonumber(spellId) or spellId)
    InitDB().overlaySizes[key] = {
        width = math.floor((frame:GetWidth() or 520) + 0.5),
        height = math.floor((frame:GetHeight() or 120) + 0.5),
    }
end

local function IsInRaid() return GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0 end
local function IsInParty() return GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0 end
local function GroupDistribution()
    if IsInRaid() then return "RAID" end
    if IsInParty() then return "PARTY" end
    return nil
end
local function SendAddon(payload, target)
    if not SendAddonMessage then return false end
    local distribution = target and "WHISPER" or GroupDistribution()
    if not distribution then return false end
    local ok, result = pcall(SendAddonMessage, ADDON_PREFIX, payload, distribution, target)
    return ok and result ~= false
end
local function RegisterPrefix()
    if RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, ADDON_PREFIX) end
end

local function SpellBookIndex(spell)
    if not spell or not GetSpellName then return nil end
    local wanted = GetSpellInfo and GetSpellInfo(spell.id) or spell.name
    wanted = wanted or spell.name
    local i = 1
    while i <= 500 do
        local name = GetSpellName(i, BOOKTYPE_SPELL or "spell")
        if not name then break end
        if name == wanted or name == spell.name then return i end
        i = i + 1
    end
    return nil
end
local function CanPlayerCast(spell) return SpellBookIndex(spell) ~= nil end
local function LocalCooldownRemaining(spell)
    local index = SpellBookIndex(spell)
    if not index or not GetSpellCooldown then return nil end
    local start, duration, enabled = GetSpellCooldown(index, BOOKTYPE_SPELL or "spell")
    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    if enabled == 0 then return 0 end
    if start <= 0 or duration <= 1.5 then return 0 end
    local remains = (start + duration) - Now()
    if remains < 0 then remains = 0 end
    return remains, duration
end

local function RosterMembers()
    local result, seen = {}, {}
    local function Add(name, classToken, unit, online)
        name = NormalizeName(name)
        local key = string.lower(name)
        if name == "" or seen[key] then return end
        seen[key] = true
        local guid = UnitGUID and unit and UnitGUID(unit) or nil
        result[#result + 1] = { name = name, class = classToken, unit = unit, online = online ~= false, guid = guid }
    end
    local raidCount = GetNumRaidMembers and (GetNumRaidMembers() or 0) or 0
    if raidCount > 0 and GetRaidRosterInfo then
        for i = 1, raidCount do
            local name, _, _, _, _, classToken, _, online = GetRaidRosterInfo(i)
            Add(name, classToken, "raid" .. i, online)
        end
    else
        local playerClass
        if UnitClass then _, playerClass = UnitClass("player") end
        Add(UnitName and UnitName("player"), playerClass, "player", true)
        local partyCount = GetNumPartyMembers and (GetNumPartyMembers() or 0) or 0
        for i = 1, partyCount do
            local unit = "party" .. i
            local classToken
            if UnitClass then _, classToken = UnitClass(unit) end
            local online = not UnitIsConnected or UnitIsConnected(unit)
            Add(UnitName and UnitName(unit), classToken, unit, online)
        end
    end
    return result
end
local function FindRosterMember(name)
    local wanted = string.lower(NormalizeName(name))
    for _, member in ipairs(RosterMembers()) do if string.lower(member.name) == wanted then return member end end
    return nil
end
local function FindGroupUnitByName(name)
    local wanted = string.lower(NormalizeName(name))
    if wanted == "" then return nil end

    local function Matches(unit)
        if UnitExists and not UnitExists(unit) then return false end
        return string.lower(NormalizeName(UnitName and UnitName(unit) or "")) == wanted
    end

    if Matches("player") then return "player" end

    local raidCount = GetNumRaidMembers and (GetNumRaidMembers() or 0) or 0
    for i = 1, raidCount do
        local unit = "raid" .. i
        if Matches(unit) then return unit end
    end

    local partyCount = GetNumPartyMembers and (GetNumPartyMembers() or 0) or 0
    for i = 1, partyCount do
        local unit = "party" .. i
        if Matches(unit) then return unit end
    end

    return nil
end

local function RotateTexture(texture, angle)
    if not texture or not texture.SetTexCoord then return end
    local c = math.cos(angle or 0)
    local sn = math.sin(angle or 0)
    local function point(x, y)
        local dx = x - 0.5
        local dy = y - 0.5
        return 0.5 + (dx * c - dy * sn), 0.5 + (dx * sn + dy * c)
    end
    local ulx, uly = point(0, 0)
    local llx, lly = point(0, 1)
    local urx, ury = point(1, 0)
    local lrx, lry = point(1, 1)
    texture:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

local function Atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

local function NormalizeAngle(angle)
    local full = math.pi * 2
    angle = tonumber(angle) or 0
    while angle < 0 do angle = angle + full end
    while angle >= full do angle = angle - full end
    return angle
end

local function DirectionToUnit(unit)
    if not unit or not GetPlayerMapPosition then return nil, false end
    local px, py = GetPlayerMapPosition("player")
    local tx, ty = GetPlayerMapPosition(unit)
    if not px or not py or not tx or not ty or (px == 0 and py == 0) or (tx == 0 and ty == 0) then
        if SetMapToCurrentZone then pcall(SetMapToCurrentZone) end
        px, py = GetPlayerMapPosition("player")
        tx, ty = GetPlayerMapPosition(unit)
    end
    if not px or not py or not tx or not ty or (px == 0 and py == 0) or (tx == 0 and ty == 0) then return nil, false end
    local mapAngle = math.pi - Atan2(px - tx, ty - py)
    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    return NormalizeAngle(mapAngle - NormalizeAngle(facing)), true
end

local function SpellRangeState(spell, unit)
    if not spell or not unit or not UnitExists or not UnitExists(unit) then return nil end
    local spellName = (GetSpellInfo and GetSpellInfo(spell.id)) or spell.name
    if IsSpellInRange and spellName then
        local ok, result = pcall(IsSpellInRange, spellName, unit)
        if ok and result ~= nil then return result == 1 end
    end
    if UnitInRange then
        local ok, result = pcall(UnitInRange, unit)
        if ok and result ~= nil then return result and true or false end
    end
    return nil
end
local function TalentCacheKey(member)
    if not member then return nil end
    if member.guid and member.guid ~= "" then return tostring(member.guid) end
    local name = NormalizeName(member.name)
    return name ~= "" and ("name:" .. string.lower(name)) or nil
end

local function GetCachedTalent(member, spell)
    if not member or not spell or not spell.inspectTalent then return true end
    if string.lower(NormalizeName(member.name)) == string.lower(PlayerName()) then
        return CanPlayerCast(spell) and true or false
    end
    local key = TalentCacheKey(member)
    local entry = key and ST.talentCache[key] or nil
    if not entry then return nil end
    if (Now() - (tonumber(entry.checkedAt) or 0)) > TALENT_CACHE_TTL then return nil end
    local value = entry.spells and entry.spells[spell.id]
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function SetCachedTalent(member, spellId, value)
    local key = TalentCacheKey(member)
    if not key then return end
    local entry = ST.talentCache[key]
    if type(entry) ~= "table" then entry = { spells = {} }; ST.talentCache[key] = entry end
    if type(entry.spells) ~= "table" then entry.spells = {} end
    entry.checkedAt = Now()
    entry.spells[tonumber(spellId)] = value and true or false
end

local function TalentSpellNeededForClass(classToken)
    for spellId, state in pairs(ST.states or {}) do
        local spell = SPELL_BY_ID[spellId]
        local overlay = ST.overlays and ST.overlays[spellId]
        if state and state.active and not state.testMode and spell and spell.inspectTalent and spell.class == classToken and overlay and overlay:IsShown() then
            return true
        end
    end
    return false
end

local function ReadInspectedTalents(member)
    if not member or not member.class or not GetTalentInfo then return false end
    local learned = {}
    local foundData = false
    local talentGroup = 1
    if GetActiveTalentGroup then
        local ok, value = pcall(GetActiveTalentGroup, true)
        if ok and tonumber(value) then talentGroup = tonumber(value) end
    end

    for tab = 1, 3 do
        for talentIndex = 1, 50 do
            local ok, name, _, _, _, rank = pcall(GetTalentInfo, tab, talentIndex, true, false, talentGroup)
            if not ok then
                ok, name, _, _, _, rank = pcall(GetTalentInfo, tab, talentIndex, true)
            end
            if not ok then return false end
            if not name then break end
            foundData = true
            if (tonumber(rank) or 0) > 0 then learned[string.lower(tostring(name))] = true end
        end
    end

    if not foundData then return false end
    for _, trackedSpell in ipairs(SPELLS) do
        if trackedSpell.inspectTalent and trackedSpell.class == member.class then
            local localizedName = (GetSpellInfo and GetSpellInfo(trackedSpell.id)) or trackedSpell.name
            local hasTalent = learned[string.lower(tostring(localizedName or trackedSpell.name))] == true
            SetCachedTalent(member, trackedSpell.id, hasTalent)
        end
    end
    return true
end

local function ClearTalentInspectPending()
    local hadPending = ST.talentInspect and ST.talentInspect.pending ~= nil
    if hadPending and ClearInspectPlayer then pcall(ClearInspectPlayer) end
    ST.talentInspect.pending = nil
    ST.talentInspect.pendingElapsed = 0
end

local function HandleTalentInspectReady(eventGUID)
    local pending = ST.talentInspect.pending
    if not pending then return end
    if eventGUID and pending.guid and tostring(eventGUID) ~= tostring(pending.guid) then return end
    local success = ReadInspectedTalents(pending)
    ClearTalentInspectPending()
    if success then
        for spellId, state in pairs(ST.states or {}) do
            if state and state.active and not state.testMode then
                local spell = SPELL_BY_ID[spellId]
                if spell and MergeOrderWithRoster then MergeOrderWithRoster(spell) end
                UpdateOverlay(state)
            end
        end
        if ST.RefreshConfig then ST.RefreshConfig() end
    end
end

local function UpdateTalentInspection(elapsed)
    local inspect = ST.talentInspect
    if not inspect or not NotifyInspect or not CanInspect or not GetTalentInfo then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown() then return end

    if inspect.pending then
        inspect.pendingElapsed = (inspect.pendingElapsed or 0) + (elapsed or 0)
        if inspect.pendingElapsed >= TALENT_INSPECT_TIMEOUT then ClearTalentInspectPending() end
        return
    end

    inspect.elapsed = (inspect.elapsed or 0) + (elapsed or 0)
    if inspect.elapsed < TALENT_INSPECT_INTERVAL then return end
    inspect.elapsed = 0

    for _, member in ipairs(RosterMembers()) do
        if member.unit and string.lower(NormalizeName(member.name)) ~= string.lower(PlayerName()) and member.online ~= false and TalentSpellNeededForClass(member.class) then
            local needsInspection = false
            for _, trackedSpell in ipairs(SPELLS) do
                if trackedSpell.inspectTalent and trackedSpell.class == member.class and GetCachedTalent(member, trackedSpell) == nil then
                    needsInspection = true
                    break
                end
            end
            if needsInspection then
                local connected = not UnitIsConnected or UnitIsConnected(member.unit)
                local exists = not UnitExists or UnitExists(member.unit)
                local canInspect = false
                if connected and exists then
                    local ok, value = pcall(CanInspect, member.unit)
                    canInspect = ok and value and true or false
                end
                if canInspect then
                    inspect.pending = { name = member.name, class = member.class, unit = member.unit, online = member.online, guid = member.guid }
                    inspect.pendingElapsed = 0
                    local ok = pcall(NotifyInspect, member.unit)
                    if not ok then ClearTalentInspectPending() end
                    return
                end
            end
        end
    end
end

local function IsMemberReadyAvailable(member)
    if not member or member.online == false then return false end
    if member.unit and UnitIsDeadOrGhost and UnitIsDeadOrGhost(member.unit) then return false end
    return true
end

local function GetOrder(spellId)
    local db = InitDB(); local key = tostring(spellId)
    if type(db.orders[key]) ~= "table" then db.orders[key] = {} end
    return db.orders[key]
end
local RepairTargetMappingsForOrder
local function SetOrder(spellId, order)
    InitDB().orders[tostring(spellId)] = order or {}
    if RepairTargetMappingsForOrder then RepairTargetMappingsForOrder(spellId, order or {}) end
end
local function GetTargets(spellId)
    local db = InitDB(); local key = tostring(spellId)
    if type(db.targets[key]) ~= "table" then db.targets[key] = {} end
    return db.targets[key]
end

local function GetTargetPositions(spellId)
    local db = InitDB(); local key = tostring(spellId)
    if type(db.targetPositions[key]) ~= "table" then db.targetPositions[key] = {} end
    return db.targetPositions[key]
end

local function FindCasterPosition(spellId, caster)
    caster = string.lower(NormalizeName(caster))
    if caster == "" then return nil end
    for index, name in ipairs(GetOrder(spellId)) do
        if string.lower(NormalizeName(name)) == caster then return index end
    end
    return nil
end

local function GetTarget(spellId, caster, position)
    caster = NormalizeName(caster)
    local liveBySpell = ST.liveTargets[tonumber(spellId)]
    local live = liveBySpell and NormalizeName(liveBySpell[string.lower(caster)] or "") or ""
    if live ~= "" then return live end

    local targets = GetTargets(spellId)
    local byName = NormalizeName(targets[string.lower(caster)] or "")
    if byName ~= "" then return byName end

    position = tonumber(position) or FindCasterPosition(spellId, caster)
    if position then
        local byPosition = NormalizeName(GetTargetPositions(spellId)[tostring(position)] or "")
        if byPosition ~= "" then
            -- Repair the name mapping automatically once the caster is known.
            targets[string.lower(caster)] = byPosition
            return byPosition
        end
    end
    return ""
end

local function SetTarget(spellId, caster, target, position)
    caster = NormalizeName(caster)
    target = NormalizeName(target)
    if caster == "" then return end

    local targets = GetTargets(spellId)
    local positions = GetTargetPositions(spellId)
    local key = string.lower(caster)
    position = tonumber(position) or FindCasterPosition(spellId, caster)
    ST.liveTargets[tonumber(spellId)] = ST.liveTargets[tonumber(spellId)] or {}

    if target == "" then
        targets[key] = nil
        ST.liveTargets[tonumber(spellId)][key] = nil
        if position then positions[tostring(position)] = nil end
    else
        targets[key] = target
        ST.liveTargets[tonumber(spellId)][key] = target
        if position then positions[tostring(position)] = target end
    end
end
RepairTargetMappingsForOrder = function(spellId, order)
    local targets = GetTargets(spellId)
    local positions = GetTargetPositions(spellId)
    for index, caster in ipairs(order or {}) do
        local positionalTarget = NormalizeName(positions[tostring(index)] or "")
        if positionalTarget ~= "" then
            targets[string.lower(NormalizeName(caster))] = positionalTarget
        end
    end
end

local function BuildCandidateNames(spell)
    local names = {}
    for _, member in ipairs(RosterMembers()) do
        if member.class == spell.class and (not spell.inspectTalent or GetCachedTalent(member, spell) == true) then
            names[#names + 1] = member.name
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end
MergeOrderWithRoster = function(spell)
    local saved, candidates = GetOrder(spell.id), BuildCandidateNames(spell)
    local eligible, merged, used = {}, {}, {}
    for _, name in ipairs(candidates) do eligible[string.lower(name)] = name end
    for _, name in ipairs(saved) do
        local key = string.lower(NormalizeName(name))
        if eligible[key] and not used[key] then merged[#merged + 1] = eligible[key]; used[key] = true end
    end
    for _, name in ipairs(candidates) do
        local key = string.lower(name)
        if not used[key] then merged[#merged + 1] = name; used[key] = true end
    end
    SetOrder(spell.id, merged)
    return merged
end

ST.states = {}
ST.overlays = {}
ST.testMode = false

local function NewSession() return tostring(math.floor(Now() * 1000)) .. tostring(math.random(100, 999)) end
local function NewState(spellId, owner, session, testMode)
    return {
        active = true, spellId = spellId, owner = NormalizeName(owner ~= "" and owner or PlayerName()),
        session = session and tostring(session) or NewSession(), cooldowns = {}, capabilities = {}, orderBuffer = {},
        elapsed = 0, selfElapsed = 0, syncElapsed = 0, lastSelfEnd = -1, lastWarnState = nil,
        testMode = testMode and true or false, testOrder = nil,
    }
end
local function StateFor(spellId) return ST.states[tonumber(spellId)] end
local function ActiveCount()
    local n = 0; for _, state in pairs(ST.states) do if state.active then n = n + 1 end end; return n
end
local function AnyActive() return ActiveCount() > 0 end

local function SetCooldown(state, name, seconds, source)
    if not state then return end
    name = NormalizeName(name); if name == "" then return end
    seconds = math.max(0, tonumber(seconds) or 0)
    state.cooldowns[string.lower(name)] = { name = name, endsAt = Now() + seconds, source = source or "observed" }
end
local function CooldownRemainingFor(state, name)
    if not state then return 0 end
    local data = state.cooldowns[string.lower(NormalizeName(name))]
    if not data then return 0 end
    local remains = (tonumber(data.endsAt) or 0) - Now()
    return remains > 0 and remains or 0
end
local function FormatCooldown(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds <= 0 then return "READY" end
    seconds = math.ceil(seconds)
    if seconds >= 60 then return string.format("%d:%02d", math.floor(seconds / 60), (seconds % 60)) end
    return tostring(seconds) .. "s"
end

local SOUND_FILES = { RaidWarning = "Sound\\Interface\\RaidWarning.wav", ReadyCheck = "Sound\\Interface\\ReadyCheck.wav", Alarm = "Sound\\Interface\\AlarmClockWarning3.wav" }
local function PlayConfiguredSound(key)
    local file = SOUND_FILES[key] or SOUND_FILES.RaidWarning
    if PlaySoundFile then local ok = pcall(PlaySoundFile, file); if ok then return end end
    if PlaySound then pcall(PlaySound, key == "ReadyCheck" and "ReadyCheck" or "RaidWarning") end
end
local function RaidWarningText(text)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo.RAID_WARNING) else Print(text) end
end

local function TestOrderFor(state)
    if state.testOrder then return state.testOrder end
    local spell = SPELL_BY_ID[state.spellId]
    local base = spell and spell.class or "Player"
    state.testOrder = { PlayerName() ~= "" and PlayerName() or "TestPlayer", "Test" .. base .. "Two", "Test" .. base .. "Three" }
    state.capabilities[string.lower(state.testOrder[1])] = true
    state.capabilities[string.lower(state.testOrder[2])] = true
    state.capabilities[string.lower(state.testOrder[3])] = true
    SetCooldown(state, state.testOrder[1], 0, "test")
    SetCooldown(state, state.testOrder[2], math.max(8, math.floor((spell.cooldown or 60) * 0.20)), "test")
    SetCooldown(state, state.testOrder[3], math.max(18, math.floor((spell.cooldown or 60) * 0.45)), "test")
    return state.testOrder
end
local function DisplayOrder(state)
    if state and state.testMode then return TestOrderFor(state) end
    return state and GetOrder(state.spellId) or {}
end
local function IncludeName(state, name, spell)
    if state.testMode then return true, { name = name, class = spell.class, online = true } end
    local member = FindRosterMember(name)
    if not member or member.class ~= spell.class then return false, member end
    if not spell.inspectTalent then return true, member end

    local key = string.lower(NormalizeName(name))
    if state and state.capabilities and state.capabilities[key] then return true, member end

    -- Talent spells are shown only after they are positively confirmed either
    -- by WoWNote sync/combat-log observation or by an out-of-combat talent inspect.
    return GetCachedTalent(member, spell) == true, member
end
local function CurrentReadyOrder(state)
    local spell = state and SPELL_BY_ID[state.spellId]
    if not spell then return {} end
    local ready = {}
    for _, name in ipairs(DisplayOrder(state)) do
        local include, member = IncludeName(state, name, spell)
        if include and IsMemberReadyAvailable(member) and CooldownRemainingFor(state, name) <= 0 then ready[#ready + 1] = name end
    end
    return ready
end
local function EvaluateWarnings(state)
    if not state or not state.active then return end
    local db, spell, ready = InitDB(), SPELL_BY_ID[state.spellId], CurrentReadyOrder(state)
    local me, newState = string.lower(PlayerName()), "none"
    if ready[1] and string.lower(ready[1]) == me then newState = "turn"
    elseif ready[2] and string.lower(ready[2]) == me then newState = "next" end
    if newState ~= state.lastWarnState then
        state.lastWarnState = newState
        if newState == "turn" and db.warnTurn then
            local target = GetTarget(state.spellId, PlayerName()); RaidWarningText("YOUR TURN: " .. spell.name .. (target ~= "" and (" -> " .. target) or "")); PlayConfiguredSound(db.turnSound)
        elseif newState == "next" and db.warnNext then
            local target = GetTarget(state.spellId, PlayerName()); RaidWarningText("YOU ARE NEXT: " .. spell.name .. (target ~= "" and (" -> " .. target) or "")); PlayConfiguredSound(db.nextSound)
        end
    end
end

local HasVisibleTrackerHUD
local StartRuntimeEvents
local StopRuntimeEventsIfIdle

local function OverlayGeometryKey(spellId) return "raidSpellTrackerOverlay_" .. tostring(spellId) end
local function EnsureOverlay(spellId)
    spellId = tonumber(spellId); if ST.overlays[spellId] then return ST.overlays[spellId] end
    local spell = SPELL_BY_ID[spellId]; if not spell then return nil end
    local f = CreateFrame("Frame", "WowNoteRaidSpellTrackerOverlay" .. tostring(spellId), UIParent)
    ST.overlays[spellId] = f
    local savedWidth, savedHeight = GetOverlaySize(spellId)
    f:SetWidth(savedWidth); f:SetHeight(savedHeight)
    f:SetScale(1)
    f:SetFrameStrata("HIGH"); f:SetMovable(true); f:SetResizable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    if f.SetMinResize then f:SetMinResize(280, 68) end
    if f.SetMaxResize then f:SetMaxResize(900, 600) end
    local ordinal = 0; for _, s in ipairs(SPELLS) do if s.id == spellId then break else ordinal = ordinal + 1 end end
    f:SetPoint("CENTER", UIParent, "CENTER", 360, 180 - ((ordinal % 5) * 50))
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); if WowNote_SaveWindowGeometry then WowNote_SaveWindowGeometry(OverlayGeometryKey(spellId), self, false) end end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10); f.title:SetText(spell.name)
    f.resourceAlert = CreateFrame("Frame", nil, f)
    f.resourceAlert:SetHeight(21)
    f.resourceAlert:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 6, 4)
    f.resourceAlert:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -6, 4)
    f.resourceAlert:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, edgeSize = 9, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    f.resourceAlert:SetBackdropColor(0.22, 0.02, 0.02, 0.95)
    f.resourceAlert:SetBackdropBorderColor(0.95, 0.24, 0.24, 1)
    f.resourceAlert.text = f.resourceAlert:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.resourceAlert.text:SetPoint("LEFT", f.resourceAlert, "LEFT", 5, 0)
    f.resourceAlert.text:SetPoint("RIGHT", f.resourceAlert, "RIGHT", -5, 0)
    f.resourceAlert.text:SetJustifyH("CENTER")
    f.resourceAlert:Hide()
    local config = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); config:SetWidth(24); config:SetHeight(20); config:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -7); config:SetText("C")
    config:SetScript("OnClick", function() InitDB().selectedSpellId = spellId; if ST.ShowConfig then ST.ShowConfig() end end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -3)

    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetWidth(18); resizeGrip:SetHeight(18)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function()
        if InCombatLockdown and InCombatLockdown() then
            if Print then Print("Spell Tracker HUD cannot be resized during combat.") end
            return
        end
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SaveOverlaySize(spellId, f)
        if ST.states[spellId] then UpdateOverlay(ST.states[spellId]) end
    end)
    resizeGrip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to resize")
        GameTooltip:AddLine("Resize this spell HUD freely.", 1, 1, 1)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.resizeGrip = resizeGrip
    close:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnShow", function()
        if StartRuntimeEvents then StartRuntimeEvents() end
    end)
    f:SetScript("OnHide", function()
        if StopRuntimeEventsIfIdle then StopRuntimeEventsIfIdle() end
    end)
    f.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, f); row:SetHeight(24); row:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -34 - ((i - 1) * 25)); row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -9, -34 - ((i - 1) * 25))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        row.index = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.index:SetPoint("LEFT", row, "LEFT", 7, 0); row.index:SetWidth(24); row.index:SetJustifyH("LEFT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.index, "RIGHT", 2, 0)
        row.name:SetWidth(82)
        row.name:SetJustifyH("LEFT")

        -- The visible target plaque itself is the secure cast button.
        row.targetPlaque = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
        row.targetPlaque:SetHeight(22)
        row.targetPlaque:SetFrameLevel(row:GetFrameLevel() + 4)
        row.targetPlaque:EnableMouse(true)
        row.targetPlaque:RegisterForClicks("AnyUp")
        row.targetPlaque:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 9,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row.targetPlaque:SetBackdropColor(0.02, 0.12, 0.28, 1.00)
        row.targetPlaque:SetBackdropBorderColor(0.20, 0.55, 1.00, 1.00)

        row.targetPlaque.icon = row.targetPlaque:CreateTexture(nil, "ARTWORK")
        row.targetPlaque.icon:SetWidth(18); row.targetPlaque.icon:SetHeight(18)
        row.targetPlaque.icon:SetPoint("LEFT", row.targetPlaque, "LEFT", 3, 0)
        local spellIcon = nil
        if GetSpellTexture then spellIcon = GetSpellTexture(spell.id) or GetSpellTexture(spell.name) end
        if not spellIcon and GetSpellInfo then
            local _, _, iconById = GetSpellInfo(spell.id)
            local _, _, iconByName = GetSpellInfo(spell.name)
            spellIcon = iconById or iconByName
        end
        row.targetPlaque.icon:SetTexture(spellIcon)
        row.targetPlaque.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if spellIcon then row.targetPlaque.icon:Show() else row.targetPlaque.icon:Hide() end

        row.targetPlaque.text = row.targetPlaque:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.targetPlaque.text:SetPoint("LEFT", row.targetPlaque.icon, "RIGHT", 4, 0)
        row.targetPlaque.text:SetPoint("RIGHT", row.targetPlaque, "RIGHT", -21, 0)
        row.targetPlaque.text:SetJustifyH("CENTER")
        row.targetPlaque.metric = row.targetPlaque:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.targetPlaque.metric:SetPoint("BOTTOMLEFT", row.targetPlaque, "BOTTOMLEFT", 25, 1)
        row.targetPlaque.metric:SetPoint("BOTTOMRIGHT", row.targetPlaque, "BOTTOMRIGHT", -17, 1)
        row.targetPlaque.metric:SetJustifyH("CENTER")
        row.targetPlaque.metric:Hide()

        row.targetPlaque.arrow = row.targetPlaque:CreateTexture(nil, "ARTWORK")
        row.targetPlaque.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
        row.targetPlaque.arrow:SetWidth(15); row.targetPlaque.arrow:SetHeight(15)
        row.targetPlaque.arrow:SetPoint("RIGHT", row.targetPlaque, "RIGHT", -3, 0)
        row.targetPlaque.arrow:Hide()

        row.targetPlaque:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(spell.name)
            if self.targetName and self.targetName ~= "" then
                GameTooltip:AddLine("Click to cast on " .. self.targetName, 1, 1, 1)
                if self.secureSpell and self.secureUnit then
                    GameTooltip:AddLine(self.secureSpell .. " -> " .. self.secureUnit, 0.35, 0.65, 1.00)
                else
                    GameTooltip:AddLine("Target is not available as a raid/party unit.", 1.00, 0.55, 0.20, true)
                end
            else
                GameTooltip:AddLine("No target assigned", 0.7, 0.7, 0.7)
            end
            if self.securePending then
                GameTooltip:AddLine("Target changed in combat - button updates after combat.", 1, 0.35, 0.2, true)
            end
            GameTooltip:Show()
        end)
        row.targetPlaque:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        row.targetBlocker = CreateFrame("Frame", nil, row)
        row.targetBlocker:EnableMouse(true)
        row.targetBlocker:SetFrameLevel(row.targetPlaque:GetFrameLevel() + 2)
        row.targetBlocker:Hide()
        row.targetBlocker.text = row.targetBlocker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.targetBlocker.text:SetAllPoints(row.targetBlocker)
        row.targetBlocker.text:SetText("LOCKED")
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetWidth(54)
        row.status:SetJustifyH("RIGHT")
        row.targetPlaque:SetWidth(110)

        row.targetPlaque:ClearAllPoints()
        row.targetPlaque:SetPoint("RIGHT", row, "RIGHT", -7, 0)
        row.targetPlaque:SetHeight(22)

        row.status:ClearAllPoints()
        row.status:SetPoint("RIGHT", row.targetPlaque, "LEFT", -6, 0)
        row.targetBlocker:SetAllPoints(row.targetPlaque)

        row:Hide(); f.rows[i] = row
    end
    f:Hide()
    if WowNote_RestoreWindowGeometry then WowNote_RestoreWindowGeometry(OverlayGeometryKey(spellId), f, { point = "CENTER", relativePoint = "CENTER", x = 360, y = 180 - ((ordinal % 5) * 50) }, false) end
    return f
end
local function GetLiveConfigTarget(spellId, caster, position)
    local saved = GetTarget(spellId, caster, position)
    if not ST.config or not ST.config:IsShown() then return saved end

    local selected = SelectedSpell()
    if not selected or tonumber(selected.id) ~= tonumber(spellId) then return saved end

    local visibleIndex = tonumber(position) and (tonumber(position) - (ST.configOffset or 0)) or nil
    local configRow = visibleIndex and ST.rows and ST.rows[visibleIndex] or nil
    if not configRow or configRow.pos ~= tonumber(position) or not configRow.target then
        return saved
    end

    local live = NormalizeName(configRow.target:GetText())
    if live ~= saved then
        SetTarget(spellId, caster, live, position)
        configRow.liveTarget = live
        configRow.liveSpellId = spellId
        configRow.liveCaster = caster
    end
    return live
end

local function ConfigureTargetButton(row, spell, targetName, targetMember)
    local plaque = row and row.targetPlaque
    local button = plaque
    if not plaque then return end

    targetName = NormalizeName(targetName)
    plaque.targetName = targetName
    button.targetName = targetName
    plaque.text:SetText(targetName ~= "" and targetName or "")
    if plaque.icon and not plaque.icon:GetTexture() then plaque.icon:Hide() end

    local desiredUnit = (targetMember and targetMember.unit) or FindGroupUnitByName(targetName)
    local desiredKey = tostring(spell and spell.id or "") .. ":" .. tostring(desiredUnit or "") .. ":" .. string.lower(targetName)
    local inCombat = InCombatLockdown and InCombatLockdown()

    if not inCombat then
        -- Clear old bindings first.
        button:SetAttribute("type", nil)
        button:SetAttribute("spell", nil)
        button:SetAttribute("unit", nil)
        button:SetAttribute("type1", nil)
        button:SetAttribute("spell1", nil)
        button:SetAttribute("unit1", nil)
        button:SetAttribute("*type1", nil)
        button:SetAttribute("*spell1", nil)
        button:SetAttribute("*unit1", nil)
        button:SetAttribute("useparent-unit", false)
        button:SetAttribute("checkselfcast", false)
        button:SetAttribute("checkfocuscast", false)

        if targetName ~= "" and desiredUnit and spell then
            local spellName = spell.name
            if GetSpellInfo then
                local resolved = GetSpellInfo(spell.id)
                if resolved and resolved ~= "" then spellName = resolved end
            end
            button:SetAttribute("unit", desiredUnit)
            button:SetAttribute("unit1", desiredUnit)
            button:SetAttribute("type1", "spell")
            button:SetAttribute("spell1", spellName)
            button:SetAttribute("type", "spell")
            button:SetAttribute("spell", spellName)
            button:SetAttribute("*type1", "spell")
            button:SetAttribute("*spell1", spellName)
            button:SetAttribute("*unit1", desiredUnit)
            button.secureSpell = spellName
            button.secureUnit = desiredUnit
            button:EnableMouse(true)
            button:Show()
        else
            button.secureSpell = nil
            button.secureUnit = nil
        end
        button.secureKey = desiredKey
        button.securePending = false
        row.targetBlocker:Hide()
    elseif button.secureKey ~= desiredKey then
        button.securePending = true
        row.targetBlocker:Show()
    else
        button.securePending = false
        row.targetBlocker:Hide()
    end

    if targetName == "" then
        plaque:Hide()
        plaque.arrow:Hide()
        return
    end

    plaque:Show()
    plaque.icon:Show()
    if not desiredUnit then
        plaque:SetBackdropColor(0.12, 0.09, 0.02, 1.00)
        plaque:SetBackdropBorderColor(0.75, 0.60, 0.20, 1.00)
        plaque.arrow:Hide()
        return
    end

    local inRange = SpellRangeState(spell, desiredUnit)
    if inRange == false then
        plaque:SetBackdropColor(0.18, 0.02, 0.02, 1.00)
        plaque:SetBackdropBorderColor(0.85, 0.20, 0.20, 1.00)
        local angle, available = DirectionToUnit(desiredUnit)
        if available then RotateTexture(plaque.arrow, angle); plaque.arrow:Show() else plaque.arrow:Hide() end
    elseif inRange == true then
        plaque:SetBackdropColor(0.02, 0.12, 0.28, 1.00)
        plaque:SetBackdropBorderColor(0.20, 0.55, 1.00, 1.00)
        plaque.arrow:Hide()
    else
        plaque:SetBackdropColor(0.12, 0.09, 0.02, 1.00)
        plaque:SetBackdropBorderColor(0.75, 0.60, 0.20, 1.00)
        plaque.arrow:Hide()
    end
end

-- Only the local caster's assigned target causes an alert. One sound per
-- threshold crossing, with 5 percentage points of hysteresis to prevent spam.
local function UpdateResourceAlert(state, spell, overlay, targetName, value, settings)
    local banner = overlay and overlay.resourceAlert
    if not banner then return end
    banner:Hide()
    if not settings or settings.mode == "off" or not settings.alert or state.testMode then
        state.resourceWarning = nil
        return
    end
    if not targetName or targetName == "" then
        state.resourceWarning = nil
        return
    end
    local key = string.lower(NormalizeName(targetName)) .. ":" .. settings.mode .. ":" .. tostring(settings.threshold)
    if not state.resourceWarning or state.resourceWarning.key ~= key then
        state.resourceWarning = { key = key, armed = true }
    end
    local warning = state.resourceWarning
    if value == nil then return end
    if value >= math.min(100, settings.threshold + 5) then warning.armed = true end
    if value > settings.threshold then return end
    -- Spellbook searches are expensive; only refresh readiness once per second.
    local readiness = state.resourceReadiness
    if not readiness or (Now() - readiness.at) >= 1.0 then
        readiness = { at = Now(), remaining = LocalCooldownRemaining(spell) }
        state.resourceReadiness = readiness
    end
    if readiness.remaining == nil or readiness.remaining > 0 then return end
    local label = settings.mode == "mana" and "MANA" or "HEALTH"
    banner.text:SetText(label .. " " .. tostring(value) .. "%: " .. targetName .. " - click to cast")
    banner:Show()
    if warning.armed then
        warning.armed = false
        Print("Low " .. string.lower(label) .. ": " .. targetName .. " (" .. tostring(value) .. "% <= " .. tostring(settings.threshold) .. "%) - click your " .. spell.name .. " target plaque.")
        PlayConfiguredSound(InitDB().turnSound)
    end
end

UpdateOverlay = function(state)
    if not state or not state.active then return end
    -- An unrelated active spell HUD must not keep hidden trackers polling.
    local existing = ST.overlays[state.spellId]
    if existing and not existing:IsShown() then return end
    local spell, f = SPELL_BY_ID[state.spellId], EnsureOverlay(state.spellId)
    if not spell or not f then return end
    f.title:SetText(spell.name .. (state.testMode and " |cff66ccff[TEST]|r" or ""))
    local settings = GetResourceMonitor(state.spellId)
    local resourceOn = settings.mode ~= "off"
    if not resourceOn then state.resourceSamples = nil; state.resourceReadiness = nil end
    local rowHeight = resourceOn and 34 or 25
    local ready = CurrentReadyOrder(state)
    local highlightedKey = ready[1] and string.lower(ready[1]) or nil
    local myKey = string.lower(PlayerName())
    local ownTarget, ownValue = nil, nil
    local visible = 0
    for _, name in ipairs(DisplayOrder(state)) do
        local include, member = IncludeName(state, name, spell)
        if include and visible < MAX_ROWS then
            visible = visible + 1
            local row = f.rows[visible]
            local remaining = CooldownRemainingFor(state, name)
            -- Protected child buttons must not be moved or resized in combat.
            -- Reflow only if the monitoring mode changes, not every 0.2 s tick.
            if row.resourceLayout ~= resourceOn and not (InCombatLockdown and InCombatLockdown()) then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -34 - ((visible - 1) * rowHeight))
                row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -9, -34 - ((visible - 1) * rowHeight))
                row:SetHeight(rowHeight - 1)
                row.targetPlaque:SetHeight(resourceOn and 30 or 22)
                row.targetPlaque.text:ClearAllPoints()
                if resourceOn then
                    row.targetPlaque.text:SetPoint("TOPLEFT", row.targetPlaque, "TOPLEFT", 25, -2)
                    row.targetPlaque.text:SetPoint("TOPRIGHT", row.targetPlaque, "TOPRIGHT", -17, -2)
                else
                    row.targetPlaque.text:SetPoint("LEFT", row.targetPlaque.icon, "RIGHT", 4, 0)
                    row.targetPlaque.text:SetPoint("RIGHT", row.targetPlaque, "RIGHT", -21, 0)
                end
                row.resourceLayout = resourceOn
            end
            row.index:SetText(tostring(visible) .. ".")
            row.name:SetText(name)
            local target = GetLiveConfigTarget(state.spellId, name, visible)
            local targetMember = target ~= "" and FindRosterMember(target) or nil
            ConfigureTargetButton(row, spell, target, targetMember)
            if resourceOn then
                local unit = targetMember and targetMember.unit or FindGroupUnitByName(target)
                local value = target ~= "" and SampleTargetResourcePercent(state, unit, target, settings.mode) or nil
                local abbreviated = settings.mode == "mana" and "M" or "HP"
                row.targetPlaque.metric:SetText(abbreviated .. " " .. (value and tostring(value) .. "%" or "--"))
                local low = settings.alert and value and value <= settings.threshold
                if low then
                    row.targetPlaque.metric:SetTextColor(1.0, 0.28, 0.28)
                else
                    row.targetPlaque.metric:SetTextColor(0.35, 0.72, 1.0)
                end
                -- A newly enabled monitor may need to wait until combat ends
                -- before its protected button can be safely resized/reflowed.
                if row.resourceLayout == true then
                    row.targetPlaque.metric:Show()
                else
                    row.targetPlaque.metric:Hide()
                end
                if low and target ~= "" then
                    row.targetPlaque:SetBackdropBorderColor(0.95, 0.25, 0.25, 1)
                end
                if string.lower(NormalizeName(name)) == myKey then
                    ownTarget, ownValue = target, value
                end
            else
                row.targetPlaque.metric:Hide()
            end
            local status = FormatCooldown(remaining)
            if member.online == false then
                status = "OFFLINE"
            elseif member.unit and UnitIsDeadOrGhost and UnitIsDeadOrGhost(member.unit) then
                status = "DEAD"
            end
            row.status:SetText(status)
            if highlightedKey and string.lower(name) == highlightedKey then
                row:SetBackdropBorderColor(1, 0.82, 0, 1)
                row:SetBackdropColor(0.20, 0.16, 0.02, 0.75)
            elseif remaining > 0 then
                row:SetBackdropBorderColor(0.55, 0.20, 0.20, 0.9)
                row:SetBackdropColor(0.10, 0.02, 0.02, 0.60)
            else
                row:SetBackdropBorderColor(0.20, 0.55, 1.00, 0.9)
                row:SetBackdropColor(0.02, 0.06, 0.14, 0.60)
            end
            row:Show()
        end
    end
    for i = visible + 1, MAX_ROWS do
        f.rows[i].targetPlaque:Hide()
        f.rows[i]:Hide()
    end
    local requiredHeight = math.max(68, 43 + (visible * rowHeight))
    if (f:GetHeight() or 0) < requiredHeight and not (InCombatLockdown and InCombatLockdown()) then
        f:SetHeight(requiredHeight)
    end
    UpdateResourceAlert(state, spell, f, ownTarget, ownValue, settings)
    EvaluateWarnings(state)
end
local function UpdateAllOverlays() for _, state in pairs(ST.states) do if state.active then UpdateOverlay(state) end end end

local function SplitOrderChunks(order)
    local chunks, current = {}, ""
    for _, name in ipairs(order) do
        local candidate = current == "" and name or (current .. "," .. name)
        if string.len(candidate) > 170 and current ~= "" then chunks[#chunks + 1] = current; current = name else current = candidate end
    end
    if current ~= "" then chunks[#chunks + 1] = current end; if #chunks == 0 then chunks[1] = "" end; return chunks
end
local function BroadcastOrder(state)
    if not state or not state.active or state.testMode then return end
    local order = GetOrder(state.spellId); local chunks = SplitOrderChunks(order)
    for i, chunk in ipairs(chunks) do SendAddon("ORD|" .. state.spellId .. "|" .. tostring(state.session) .. "|" .. i .. "|" .. #chunks .. "|" .. chunk) end
end
local function BroadcastTargets(state)
    if not state or not state.active or state.testMode then return end
    local targets = GetTargets(state.spellId)
    RepairTargetMappingsForOrder(state.spellId, GetOrder(state.spellId))
    local parts = {}
    for caster, target in pairs(targets) do
        target = NormalizeName(target)
        if target ~= "" then parts[#parts + 1] = NormalizeName(caster) .. ">" .. target end
    end
    table.sort(parts)
    local chunks, current = {}, ""
    for _, part in ipairs(parts) do
        local candidate = current == "" and part or (current .. "," .. part)
        if string.len(candidate) > 170 and current ~= "" then chunks[#chunks + 1] = current; current = part else current = candidate end
    end
    if current ~= "" then chunks[#chunks + 1] = current end
    if #chunks == 0 then chunks[1] = "" end
    for i, chunk in ipairs(chunks) do SendAddon("TGT|" .. state.spellId .. "|" .. tostring(state.session) .. "|" .. i .. "|" .. #chunks .. "|" .. chunk) end
end
local function BroadcastSelfStatus(state, force)
    if not state or not state.active or state.testMode then return end
    local spell = SPELL_BY_ID[state.spellId]; if not CanPlayerCast(spell) then return end
    local remaining, duration = LocalCooldownRemaining(spell); if remaining == nil then return end
    local endsAt = math.floor((Now() + remaining) * 10) / 10
    if force or math.abs((state.lastSelfEnd or -1) - endsAt) > 1.0 then
        state.lastSelfEnd = endsAt; SetCooldown(state, PlayerName(), remaining, "local")
        SendAddon("CAP|" .. state.spellId .. "|" .. tostring(state.session) .. "|" .. math.floor(remaining + 0.5) .. "|" .. math.floor((duration or spell.cooldown) + 0.5))
    end
end

HasVisibleTrackerHUD = function()
    for spellId, state in pairs(ST.states or {}) do
        local overlay = ST.overlays and ST.overlays[spellId]
        if state and state.active and overlay and overlay:IsShown() then
            return true
        end
    end
    return false
end

StartRuntimeEvents = function()
    if not ST.eventFrame or ST.runtimeStarted or not HasVisibleTrackerHUD() then return end
    ST.runtimeStarted = true
    ST.eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ST.eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    ST.eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    ST.eventFrame:RegisterEvent("INSPECT_TALENT_READY")
    if WowNoteProfiler_SetScript then
        WowNoteProfiler_SetScript(ST.eventFrame, "OnUpdate", "RaidPlanner.SpellTrackerUpdate", ST.OnUpdate)
    else
        ST.eventFrame:SetScript("OnUpdate", ST.OnUpdate)
    end
end

StopRuntimeEventsIfIdle = function()
    if HasVisibleTrackerHUD() or not ST.eventFrame or not ST.runtimeStarted then return end
    ST.runtimeStarted = false
    ST.eventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ST.eventFrame:UnregisterEvent("RAID_ROSTER_UPDATE")
    ST.eventFrame:UnregisterEvent("PARTY_MEMBERS_CHANGED")
    ST.eventFrame:UnregisterEvent("INSPECT_TALENT_READY")
    ClearTalentInspectPending()
    if WowNoteProfiler_SetScript then
        WowNoteProfiler_SetScript(ST.eventFrame, "OnUpdate", "RaidPlanner.SpellTrackerUpdate", nil)
    else
        ST.eventFrame:SetScript("OnUpdate", nil)
    end
end

function ST.Activate(spellId, owner, session, remote, testMode)
    spellId = tonumber(spellId); local spell = SPELL_BY_ID[spellId]; if not spell then return false end
    local existing = StateFor(spellId)
    if existing and existing.active and tostring(existing.session or "") == tostring(session or existing.session or "") and not testMode then
        if CanPlayerCast(spell) then BroadcastSelfStatus(existing, true) end
        return true
    end
    local state = NewState(spellId, owner or PlayerName(), session, testMode); ST.states[spellId] = state
    if not testMode then MergeOrderWithRoster(spell) end
    if CanPlayerCast(spell) or testMode then state.capabilities[string.lower(PlayerName())] = true end
    EnsureOverlay(spellId):Show(); StartRuntimeEvents(); UpdateOverlay(state); BroadcastSelfStatus(state, true)
    if not remote and not testMode then SendAddon("ACT|" .. spellId .. "|" .. tostring(state.session) .. "|" .. PlayerName()); BroadcastOrder(state); BroadcastTargets(state) end
    if ST.RefreshConfig then ST.RefreshConfig() end; return true
end
function ST.DeactivateSpell(spellId, broadcast)
    spellId = tonumber(spellId); local state = StateFor(spellId); if not state then return end
    if broadcast and state.active and not state.testMode then SendAddon("STOP|" .. spellId .. "|" .. tostring(state.session or "")) end
    state.active = false; state.lastWarnState = nil
    if ST.overlays[spellId] then ST.overlays[spellId]:Hide() end
    ST.states[spellId] = nil; StopRuntimeEventsIfIdle(); if ST.RefreshConfig then ST.RefreshConfig() end
end
function ST.Deactivate(broadcast)
    local ids = {}; for spellId in pairs(ST.states) do ids[#ids + 1] = spellId end
    for _, spellId in ipairs(ids) do ST.DeactivateSpell(spellId, broadcast) end
end
function ST.StartEnabled(testMode)
    ST.Deactivate(not testMode)
    local db, count = InitDB(), 0
    for _, spell in ipairs(SPELLS) do if db.enabledSpells[spell.id] then ST.Activate(spell.id, PlayerName(), nil, false, testMode); count = count + 1 end end
    if count == 0 then SetSpellEnabled(db.selectedSpellId, true); ST.Activate(db.selectedSpellId, PlayerName(), nil, false, testMode); count = 1 end
    ST.testMode = testMode and true or false
    Print((testMode and "Test mode: " or "Tracking: ") .. tostring(count) .. " spell tracker(s).")
end

local function ParseOrderChunk(message)
    local spellId, session, part, total, chunk = string.match(message, "^ORD|(%d+)|([^|]*)|(%d+)|(%d+)|(.*)$")
    spellId, part, total = tonumber(spellId), tonumber(part), tonumber(total); local state = StateFor(spellId)
    if not state or not part or not total or session ~= tostring(state.session or "") then return end
    local key = tostring(spellId) .. ":" .. session; local buffer = state.orderBuffer[key]
    if not buffer or buffer.total ~= total then buffer = { total = total, parts = {} }; state.orderBuffer[key] = buffer end
    buffer.parts[part] = chunk or ""; for i = 1, total do if buffer.parts[i] == nil then return end end
    local order = {}; for name in string.gmatch(table.concat(buffer.parts, ","), "[^,]+") do name = NormalizeName(name); if name ~= "" then order[#order + 1] = name end end
    SetOrder(spellId, order); state.orderBuffer[key] = nil; UpdateOverlay(state); if ST.RefreshConfig then ST.RefreshConfig() end
end
local function ParseTargetChunk(message)
    local spellId, session, part, total, chunk = string.match(message, "^TGT|(%d+)|([^|]*)|(%d+)|(%d+)|(.*)$")
    spellId, part, total = tonumber(spellId), tonumber(part), tonumber(total); local state = StateFor(spellId)
    if not state or not part or not total or session ~= tostring(state.session or "") then return end
    state.targetBuffer = state.targetBuffer or {}
    local key = tostring(spellId) .. ":" .. session; local buffer = state.targetBuffer[key]
    if not buffer or buffer.total ~= total then buffer = { total = total, parts = {} }; state.targetBuffer[key] = buffer end
    buffer.parts[part] = chunk or ""; for i = 1, total do if buffer.parts[i] == nil then return end end
    local targets = GetTargets(spellId); for keyName in pairs(targets) do targets[keyName] = nil end
    local combined = table.concat(buffer.parts, ",")
    for pair in string.gmatch(combined, "[^,]+") do
        local caster, target = string.match(pair, "^([^>]+)>(.*)$")
        if caster and target then SetTarget(spellId, caster, target) end
    end
    state.targetBuffer[key] = nil; UpdateOverlay(state); if ST.RefreshConfig then ST.RefreshConfig() end
end
local function HandleAddonMessage(message, sender)
    sender = NormalizeName(sender); local cmd = string.match(message or "", "^([^|]+)")
    if cmd == "ACT" then
        local spellId, session, owner = string.match(message, "^ACT|(%d+)|([^|]*)|([^|]*)$")
        spellId = tonumber(spellId)
        local spell = SPELL_BY_ID[spellId]
        if not spell or sender == PlayerName() then return end

        local state = StateFor(spellId)
        if state and tostring(state.session or "") == tostring(session or "") then
            -- A valid sync for an already known session must also wake a hidden HUD.
            state.active = true
            SetSpellEnabled(spellId, true)
            EnsureOverlay(spellId):Show()
            StartRuntimeEvents()
            UpdateOverlay(state)
            SendAddon("REQ|" .. spellId .. "|" .. tostring(session), sender)
            return
        end

        -- Valid remote tracker announcements are adopted automatically.
        -- This is intentionally independent of whether the local character can cast the spell:
        -- everyone receiving the tracker can follow the sequence/targets/cooldowns in the HUD.
        SetSpellEnabled(spellId, true)
        ST.Activate(spellId, owner ~= "" and owner or sender, session, true, false)
        SendAddon("REQ|" .. spellId .. "|" .. tostring(session), sender)
    elseif cmd == "ORD" then ParseOrderChunk(message)
    elseif cmd == "TGT" then ParseTargetChunk(message)
    elseif cmd == "CAP" then
        local spellId, session, remaining = string.match(message, "^CAP|(%d+)|([^|]*)|(%d+)|"); spellId, remaining = tonumber(spellId), tonumber(remaining); local state = StateFor(spellId)
        if state and session == tostring(state.session or "") then state.capabilities[string.lower(sender)] = true; SetCooldown(state, sender, remaining or 0, "sync"); UpdateOverlay(state) end
    elseif cmd == "USED" then
        local spellId, session, remaining = string.match(message, "^USED|(%d+)|([^|]*)|(%d+)$"); spellId, remaining = tonumber(spellId), tonumber(remaining); local state = StateFor(spellId); local spell = SPELL_BY_ID[spellId]
        if state and spell and session == tostring(state.session or "") then state.capabilities[string.lower(sender)] = true; SetCooldown(state, sender, remaining or spell.cooldown, "sync"); UpdateOverlay(state) end
    elseif cmd == "REQ" then
        local spellId, session = string.match(message, "^REQ|(%d+)|([^|]*)$"); spellId = tonumber(spellId); local state = StateFor(spellId)
        if state and session == tostring(state.session or "") then BroadcastSelfStatus(state, true); if NormalizeName(state.owner) == PlayerName() then BroadcastOrder(state); BroadcastTargets(state) end end
    elseif cmd == "STOP" then
        local spellId, session = string.match(message, "^STOP|(%d+)|([^|]*)$"); spellId = tonumber(spellId); local state = StateFor(spellId)
        if state and session == tostring(state.session or "") and sender == NormalizeName(state.owner) then ST.DeactivateSpell(spellId, false) end
    end
end
local function ObserveCast(sourceName, spellId)
    spellId = tonumber(spellId)
    local state = StateFor(spellId)
    local spell = SPELL_BY_ID[spellId]
    if not state then
        local castName = GetSpellInfo and GetSpellInfo(spellId or 0) or nil
        if castName then
            for activeSpellId, activeState in pairs(ST.states) do
                local activeSpell = SPELL_BY_ID[activeSpellId]
                local trackedName = activeSpell and ((GetSpellInfo and GetSpellInfo(activeSpell.id)) or activeSpell.name) or nil
                if activeState.active and trackedName and (castName == trackedName or castName == activeSpell.name) then
                    state = activeState
                    spell = activeSpell
                    spellId = activeSpellId
                    break
                end
            end
        end
    end
    if not state or not spell or state.testMode then return end
    sourceName = NormalizeName(sourceName); if sourceName == "" then return end
    local remaining = spell.cooldown; state.capabilities[string.lower(sourceName)] = true
    if sourceName == PlayerName() then local localRemaining = LocalCooldownRemaining(spell); if localRemaining and localRemaining > 0 then remaining = localRemaining end; SendAddon("USED|" .. spellId .. "|" .. tostring(state.session or "") .. "|" .. math.floor(remaining + 0.5)) end
    SetCooldown(state, sourceName, remaining, sourceName == PlayerName() and "local" or "combatlog"); UpdateOverlay(state)
end

local function ResolveChatDestinations(text) if RP.ParseConfiguredChannels then return RP.ParseConfiguredChannels(text) end; return nil, "Raid Planner channel parser is unavailable." end
local function SendChatLine(line, destination)
    if not SendChatMessage or not destination then return false end
    local ok, result = pcall(SendChatMessage, line, destination.chatType, nil, destination.target); return ok and result ~= false
end
local function BuildOrderChatLines(spellId)
    local spell, order = SPELL_BY_ID[spellId], GetOrder(spellId); local lines, current, number = {}, "[WN] " .. SPELL_BY_ID[spellId].name .. " order:", 0
    for _, name in ipairs(order) do local member = FindRosterMember(name); if member and member.class == spell.class then number = number + 1; local target = GetTarget(spellId, name); local piece = " " .. number .. ". " .. name .. (target ~= "" and (" -> " .. target) or ""); if string.len(current .. piece) > 220 then lines[#lines + 1] = current; current = "[WN] " .. spell.name .. ":" .. piece else current = current .. piece end end end
    if number == 0 then current = current .. " no eligible players" end; lines[#lines + 1] = current; return lines
end
function ST.PostOrders()
    local destinations, err = ResolveChatDestinations(InitDB().channels); if not destinations then Print(err or "No valid chat destination."); return end
    local spellIds = {}; for _, spell in ipairs(SPELLS) do if IsSpellEnabled(spell.id) then spellIds[#spellIds + 1] = spell.id end end
    if #spellIds == 0 then spellIds[1] = SelectedSpell().id end
    local lines = {}; for _, spellId in ipairs(spellIds) do for _, line in ipairs(BuildOrderChatLines(spellId)) do lines[#lines + 1] = line end end
    for _, destination in ipairs(destinations) do for _, line in ipairs(lines) do SendChatLine(line, destination) end end
    Print("Posted " .. #lines .. " order line(s) for " .. #spellIds .. " tracker(s) to " .. #destinations .. " channel(s).")
end

local function MakeButton(parent, text, width, height) local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); b:SetWidth(width or 90); b:SetHeight(height or 22); b:SetText(text or ""); return b end
local function MakeCheck(parent, label, x, y, getValue, setValue)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"); c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); c:SetWidth(24); c:SetHeight(24)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("LEFT", c, "RIGHT", 2, 0); t:SetText(label)
    c:SetScript("OnClick", function(self) setValue(self:GetChecked() and true or false) end); c.Refresh = function() c:SetChecked(getValue() and true or false) end; c.Refresh(); return c
end
local function MakeDropDown(parent, name, x, y, width, values, getCurrent, setCurrent)
    local holder = CreateFrame("Frame", name, parent)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 16, y - 2)
    holder:SetWidth(width or 150)
    holder:SetHeight(22)

    local prev = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    prev:SetWidth(24); prev:SetHeight(22); prev:SetPoint("LEFT", holder, "LEFT", 0, 0); prev:SetText("<")
    local nextButton = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    nextButton:SetWidth(24); nextButton:SetHeight(22); nextButton:SetPoint("RIGHT", holder, "RIGHT", 0, 0); nextButton:SetText(">")
    local currentButton = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    currentButton:SetHeight(22); currentButton:SetPoint("LEFT", prev, "RIGHT", 2, 0); currentButton:SetPoint("RIGHT", nextButton, "LEFT", -2, 0)

    local function CurrentIndex()
        local current = getCurrent()
        for i, item in ipairs(values) do if item.value == current then return i end end
        return 1
    end
    local function SelectIndex(index)
        if #values == 0 then return end
        if index < 1 then index = #values elseif index > #values then index = 1 end
        local item = values[index]
        setCurrent(item.value)
        holder:Refresh()
        if ST.RefreshConfig then ST.RefreshConfig() end
    end
    holder.Refresh = function()
        local index = CurrentIndex()
        local item = values[index]
        currentButton:SetText(item and item.text or "-")
    end
    prev:SetScript("OnClick", function() SelectIndex(CurrentIndex() - 1) end)
    nextButton:SetScript("OnClick", function() SelectIndex(CurrentIndex() + 1) end)
    currentButton:SetScript("OnClick", function() SelectIndex(CurrentIndex() + 1) end)
    currentButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Left/Right arrows change selection")
        GameTooltip:Show()
    end)
    currentButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    holder:Refresh()
    return holder
end


local function MakeSpellDropDown(parent, name, x, y, width, values, getCurrent, setCurrent)
    local holder = CreateFrame("Frame", name, parent)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    holder:SetWidth(width or 220)
    holder:SetHeight(24)

    local button = CreateFrame("Button", name .. "Button", holder, "UIPanelButtonTemplate")
    button:SetAllPoints(holder)

    local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    arrow:SetText("v")

    local popup = CreateFrame("Frame", name .. "Popup", parent)
    popup:SetWidth(width or 220)
    popup:SetHeight(278)
    popup:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -2)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    popup:Hide()

    local VISIBLE_ROWS = 12
    local ROW_HEIGHT = 22
    local offset = 0
    local rows = {}

    local function CurrentIndex()
        local current = getCurrent()
        for i, item in ipairs(values) do
            if item.value == current then return i end
        end
        return 1
    end

    local function ClampOffset(value)
        local maxOffset = math.max(0, #values - VISIBLE_ROWS)
        value = math.max(0, math.min(maxOffset, tonumber(value) or 0))
        return value
    end

    local function RefreshPopup()
        offset = ClampOffset(offset)
        local current = getCurrent()
        for i = 1, VISIBLE_ROWS do
            local row = rows[i]
            local item = values[offset + i]
            if item then
                row.item = item
                row.text:SetText(item.text)
                if item.value == current then
                    row:SetBackdropColor(0.04, 0.16, 0.35, 0.95)
                    row:SetBackdropBorderColor(0.20, 0.55, 1.00, 1.00)
                else
                    row:SetBackdropColor(0.03, 0.03, 0.03, 0.90)
                    row:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.80)
                end
                row:Show()
            else
                row.item = nil
                row:Hide()
            end
        end
    end

    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, popup)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -6 - ((i - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6 - ((i - 1) * ROW_HEIGHT))
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -7, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            if not self.item then return end
            setCurrent(self.item.value)
            popup:Hide()
            holder:Refresh()
            if ST.RefreshConfig then ST.RefreshConfig() end
        end)
        row:SetScript("OnEnter", function(self)
            if self.item and self.item.value ~= getCurrent() then
                self:SetBackdropBorderColor(0.35, 0.75, 1.00, 1.00)
            end
        end)
        row:SetScript("OnLeave", function() RefreshPopup() end)
        rows[i] = row
    end

    popup:SetScript("OnMouseWheel", function(_, delta)
        offset = ClampOffset(offset - delta)
        RefreshPopup()
    end)

    button:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            local currentIndex = CurrentIndex()
            offset = ClampOffset(currentIndex - math.ceil(VISIBLE_ROWS / 2))
            RefreshPopup()
            popup:Show()
        end
    end)

    holder.Refresh = function()
        local current = getCurrent()
        local label = "-"
        for _, item in ipairs(values) do
            if item.value == current then
                label = item.text
                break
            end
        end
        button:SetText(label)
        if popup:IsShown() then RefreshPopup() end
    end

    holder.popup = popup
    holder.Refresh()
    return holder
end


local function MakeTargetSelector(parent, editBox, row)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(24)
    button:SetHeight(20)
    button:SetText("v")

    local popup = CreateFrame("Frame", nil, parent)
    popup:SetWidth(180)
    popup:SetHeight(254)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    popup:Hide()

    local VISIBLE_ROWS = 10
    local ROW_HEIGHT = 22
    local offset = 0
    local entries = {}
    local popupRows = {}

    local function BuildEntries()
        entries = { { name = "", label = "<No target>" } }
        for _, member in ipairs(RosterMembers()) do
            entries[#entries + 1] = { name = member.name, label = member.name }
        end
        table.sort(entries, function(a, b)
            if a.name == "" then return true end
            if b.name == "" then return false end
            return string.lower(a.label) < string.lower(b.label)
        end)
    end

    local function ClampOffset(value)
        local maxOffset = math.max(0, #entries - VISIBLE_ROWS)
        return math.max(0, math.min(maxOffset, tonumber(value) or 0))
    end

    local function ApplyTarget(targetName)
        local spell = SelectedSpell()
        local order = GetOrder(spell.id)
        local caster = row.pos and order[row.pos]
        if not caster then return end

        targetName = NormalizeName(targetName)
        SetTarget(spell.id, caster, targetName, row.pos)
        editBox:SetText(targetName)

        local state = StateFor(spell.id)
        if state and NormalizeName(state.owner) == PlayerName() then
            BroadcastTargets(state)
        end
        if state then UpdateOverlay(state) end
        popup:Hide()
        ST.RefreshConfig()
    end

    local function RefreshPopup()
        offset = ClampOffset(offset)
        local selected = NormalizeName(editBox:GetText())
        for i = 1, VISIBLE_ROWS do
            local popupRow = popupRows[i]
            local entry = entries[offset + i]
            if entry then
                popupRow.entry = entry
                popupRow.text:SetText(entry.label)
                if NormalizeName(entry.name) == selected then
                    popupRow:SetBackdropColor(0.04, 0.16, 0.35, 0.95)
                    popupRow:SetBackdropBorderColor(0.20, 0.55, 1.00, 1.00)
                else
                    popupRow:SetBackdropColor(0.03, 0.03, 0.03, 0.92)
                    popupRow:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.80)
                end
                popupRow:Show()
            else
                popupRow.entry = nil
                popupRow:Hide()
            end
        end
    end

    for i = 1, VISIBLE_ROWS do
        local popupRow = CreateFrame("Button", nil, popup)
        popupRow:SetHeight(ROW_HEIGHT)
        popupRow:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -6 - ((i - 1) * ROW_HEIGHT))
        popupRow:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6 - ((i - 1) * ROW_HEIGHT))
        popupRow:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        popupRow.text = popupRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        popupRow.text:SetPoint("LEFT", popupRow, "LEFT", 7, 0)
        popupRow.text:SetPoint("RIGHT", popupRow, "RIGHT", -7, 0)
        popupRow.text:SetJustifyH("LEFT")
        popupRow:SetScript("OnClick", function(self)
            if self.entry then ApplyTarget(self.entry.name) end
        end)
        popupRow:SetScript("OnEnter", function(self)
            if self.entry then self:SetBackdropBorderColor(0.35, 0.75, 1.00, 1.00) end
        end)
        popupRow:SetScript("OnLeave", RefreshPopup)
        popupRows[i] = popupRow
    end

    popup:SetScript("OnMouseWheel", function(_, delta)
        offset = ClampOffset(offset - delta)
        RefreshPopup()
    end)

    button:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
            return
        end
        BuildEntries()
        offset = 0
        RefreshPopup()
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", button, "BOTTOMRIGHT", -180, -2)
        popup:Show()
    end)

    row.targetPopup = popup
    row.targetSelect = button
    return button
end

local function EnsureConfig()
    if ST.config then return ST.config end
    local db = InitDB(); local f = CreateFrame("Frame", "WowNoteRaidSpellTrackerConfig", UIParent); ST.config = f
    f:SetWidth(760); f:SetHeight(610); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    f:SetScript("OnDragStart", function(self) self:StartMoving() end); f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); if WowNote_SaveWindowGeometry then WowNote_SaveWindowGeometry("raidSpellTrackerConfig", self, false) end end); f:Hide()
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -22); title:SetText("Raid Spell Tracker")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    local spellValues = {}; for _, spell in ipairs(SPELLS) do spellValues[#spellValues + 1] = { text = spell.name, value = spell.id } end
    local spellLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); spellLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -58); spellLabel:SetText("Configure spell")
    ST.spellDropDown = MakeSpellDropDown(f, "WowNoteSpellTrackerSpell", 24, -72, 220, spellValues, function() return InitDB().selectedSpellId end, function(v) InitDB().selectedSpellId = v; ST.configOffset = 0 end)
    ST.enableCheck = MakeCheck(f, "Track this spell", 265, -76, function() return IsSpellEnabled(InitDB().selectedSpellId) end, function(v) SetSpellEnabled(InitDB().selectedSpellId, v) end)
    local activeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); activeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 410, -78); activeLabel:SetWidth(320); activeLabel:SetJustifyH("LEFT"); ST.activeLabel = activeLabel
    local channelLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); channelLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -112); channelLabel:SetText("Post channels")
    ST.channelEdit = CreateFrame("EditBox", "WowNoteSpellTrackerChannels", f, "InputBoxTemplate"); ST.channelEdit:SetWidth(220); ST.channelEdit:SetHeight(24); ST.channelEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -126); ST.channelEdit:SetAutoFocus(false)
    ST.channelEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end); ST.channelEdit:SetScript("OnEditFocusLost", function(self) db.channels = Trim(self:GetText()); if db.channels == "" then db.channels = "/raid" end; self:SetText(db.channels) end)
    local start = MakeButton(f, "Start / Sync", 100, 24); start:SetPoint("TOPLEFT", f, "TOPLEFT", 270, -124); start:SetScript("OnClick", function() ST.StartEnabled(false) end)
    local stop = MakeButton(f, "Stop All", 80, 24); stop:SetPoint("LEFT", start, "RIGHT", 6, 0); stop:SetScript("OnClick", function() ST.Deactivate(true) end)
    local test = MakeButton(f, "Test Mode", 90, 24); test:SetPoint("LEFT", stop, "RIGHT", 6, 0); test:SetScript("OnClick", function() ST.StartEnabled(true) end)
    local overlays = MakeButton(f, "Show HUDs", 90, 24); overlays:SetPoint("LEFT", test, "RIGHT", 6, 0); overlays:SetScript("OnClick", function() for spellId, state in pairs(ST.states) do if state.active then EnsureOverlay(spellId):Show(); UpdateOverlay(state) end end; StartRuntimeEvents() end)
    ST.turnCheck = MakeCheck(f, "Warn: YOUR TURN", 24, -168, function() return InitDB().warnTurn end, function(v) InitDB().warnTurn = v end)
    ST.nextCheck = MakeCheck(f, "Warn: YOU ARE NEXT", 205, -168, function() return InitDB().warnNext end, function(v) InitDB().warnNext = v end)
    ST.autoCheck = MakeCheck(f, "Auto-open synced trackers I can cast", 410, -168, function() return InitDB().autoOpenRemote end, function(v) InitDB().autoOpenRemote = v end)
    local soundValues = { { text = "Raid Warning", value = "RaidWarning" }, { text = "Ready Check", value = "ReadyCheck" }, { text = "Alarm", value = "Alarm" } }
    local turnSoundLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); turnSoundLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -208); turnSoundLabel:SetText("Turn sound")
    ST.turnSoundDropDown = MakeDropDown(f, "WowNoteSpellTrackerTurnSound", 10, -218, 145, soundValues, function() return InitDB().turnSound end, function(v) InitDB().turnSound = v; PlayConfiguredSound(v) end)
    local nextSoundLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); nextSoundLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 205, -208); nextSoundLabel:SetText("Next sound")
    ST.nextSoundDropDown = MakeDropDown(f, "WowNoteSpellTrackerNextSound", 191, -218, 145, soundValues, function() return InitDB().nextSound end, function(v) InitDB().nextSound = v; PlayConfiguredSound(v) end)
    local post = MakeButton(f, "Post Orders", 105, 24); post:SetPoint("TOPLEFT", f, "TOPLEFT", 410, -224); post:SetScript("OnClick", ST.PostOrders)
    local refresh = MakeButton(f, "Refresh Raid", 105, 24); refresh:SetPoint("LEFT", post, "RIGHT", 8, 0); refresh:SetScript("OnClick", function() for _, spell in ipairs(SPELLS) do if IsSpellEnabled(spell.id) then MergeOrderWithRoster(spell); local state = StateFor(spell.id); if state and NormalizeName(state.owner) == PlayerName() then BroadcastOrder(state); BroadcastTargets(state) end end end; ST.RefreshConfig(); UpdateAllOverlays() end)
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -270)
    help:SetWidth(370)
    help:SetJustifyH("LEFT")
    help:SetText("Choose a spell, set its caster order and targets. Click a target plaque to cast. Resource monitoring is local to you; low-resource alerts never cast automatically. Test Mode sends no sync/chat.")

    local resourceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resourceLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 410, -261)
    resourceLabel:SetText("Watch assigned targets")
    local resourceModes = {
        { text = "Off", value = "off" },
        { text = "Mana %", value = "mana" },
        { text = "Health %", value = "health" },
    }
    ST.resourceModeDropDown = MakeDropDown(f, "WowNoteSpellTrackerResourceMode", 396, -279, 185, resourceModes,
        function() return GetResourceMonitor(InitDB().selectedSpellId).mode end,
        function(mode)
            local spellId = InitDB().selectedSpellId
            GetResourceMonitor(spellId).mode = mode
            local state = StateFor(spellId)
            if state then state.resourceWarning = nil; state.resourceSamples = nil; UpdateOverlay(state) end
        end)
    local thresholdLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thresholdLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 622, -261)
    thresholdLabel:SetText("Below %")
    ST.resourceThreshold = CreateFrame("EditBox", "WowNoteSpellTrackerResourceThreshold", f, "InputBoxTemplate")
    ST.resourceThreshold:SetAutoFocus(false)
    ST.resourceThreshold:SetWidth(48)
    ST.resourceThreshold:SetHeight(22)
    ST.resourceThreshold:SetMaxLetters(3)
    ST.resourceThreshold:SetPoint("TOPLEFT", f, "TOPLEFT", 627, -282)
    local function CommitResourceThreshold(self)
        local spellId = InitDB().selectedSpellId
        local settings = GetResourceMonitor(spellId)
        local entered = tonumber(Trim(self:GetText()))
        if entered then
            settings.threshold = math.floor(math.max(1, math.min(100, entered)))
        end
        self:SetText(tostring(settings.threshold))
        local state = StateFor(spellId)
        if state then state.resourceWarning = nil; UpdateOverlay(state) end
    end
    ST.resourceThreshold:SetScript("OnEnterPressed", function(self) CommitResourceThreshold(self); self:ClearFocus() end)
    ST.resourceThreshold:SetScript("OnEditFocusLost", CommitResourceThreshold)
    ST.resourceThreshold:SetScript("OnEscapePressed", function(self) self:SetText(tostring(GetResourceMonitor(InitDB().selectedSpellId).threshold)); self:ClearFocus() end)
    ST.resourceAlertCheck = MakeCheck(f, "Alert + sound for MY target", 410, -309,
        function() return GetResourceMonitor(InitDB().selectedSpellId).alert end,
        function(enabled)
            local spellId = InitDB().selectedSpellId
            GetResourceMonitor(spellId).alert = enabled
            local state = StateFor(spellId)
            if state then state.resourceWarning = nil; UpdateOverlay(state) end
        end)
    ST.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ST.status:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -316); ST.status:SetText("Order")
    ST.configOffset = 0
    local pageUp = MakeButton(f, "Prev", 60, 20); pageUp:SetPoint("TOPRIGHT", f, "TOPRIGHT", -100, -312)
    local pageDown = MakeButton(f, "Next", 60, 20); pageDown:SetPoint("LEFT", pageUp, "RIGHT", 6, 0)
    pageUp:SetScript("OnClick", function() ST.configOffset = math.max(0, (ST.configOffset or 0) - CONFIG_ROWS); ST.RefreshConfig() end); pageDown:SetScript("OnClick", function() ST.configOffset = (ST.configOffset or 0) + CONFIG_ROWS; ST.RefreshConfig() end); ST.pageUp, ST.pageDown = pageUp, pageDown
    ST.rows = {}
    for i = 1, CONFIG_ROWS do
        local y = -340 - ((i - 1) * 25); local index = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); index:SetPoint("TOPLEFT", f, "TOPLEFT", 30, y - 4); index:SetWidth(24); index:SetJustifyH("RIGHT")
        local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); name:SetPoint("TOPLEFT", f, "TOPLEFT", 62, y - 4); name:SetWidth(165); name:SetJustifyH("LEFT")
        local target = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); target:SetAutoFocus(false); target:SetWidth(105); target:SetHeight(20); target:SetPoint("TOPLEFT", f, "TOPLEFT", 240, y + 2); target:SetMaxLetters(24)
        local cd = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); cd:SetPoint("TOPLEFT", f, "TOPLEFT", 380, y - 4); cd:SetWidth(80); cd:SetJustifyH("LEFT")
        local up = MakeButton(f, "Up", 55, 20); up:SetPoint("TOPLEFT", f, "TOPLEFT", 475, y); local down = MakeButton(f, "Down", 55, 20); down:SetPoint("LEFT", up, "RIGHT", 6, 0)
        local row = { index = index, name = name, target = target, cd = cd, up = up, down = down }
        local targetSelect = MakeTargetSelector(f, target, row); targetSelect:SetPoint("LEFT", target, "RIGHT", 2, 0)

        local function CommitTarget(self, broadcast)
            if row.settingTargetText then return end
            local spell = SelectedSpell()
            local pos = row.pos
            local order = GetOrder(spell.id)
            local caster = pos and order[pos]
            if caster then
                local targetName = NormalizeName(self:GetText())
                SetTarget(spell.id, caster, targetName, row.pos)
                row.liveTarget = targetName
                row.liveSpellId = spell.id
                row.liveCaster = caster

                local state = StateFor(spell.id)
                if broadcast and state and NormalizeName(state.owner) == PlayerName() then
                    BroadcastTargets(state)
                end
                if state then UpdateOverlay(state) end
            end
        end
        row.CommitTarget = CommitTarget

        target:SetScript("OnTextChanged", function(self)
            if not row.settingTargetText then
                CommitTarget(self, false)
            end
        end)
        target:SetScript("OnEnterPressed", function(self)
            CommitTarget(self, true)
            self:ClearFocus()
            ST.RefreshConfig()
        end)
        target:SetScript("OnEditFocusLost", function(self)
            CommitTarget(self, true)
            ST.RefreshConfig()
        end)
        target:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ST.RefreshConfig() end)
        up:SetScript("OnClick", function() local spell = SelectedSpell(); local order = GetOrder(spell.id); local pos = row.pos; if pos and pos > 1 then order[pos], order[pos - 1] = order[pos - 1], order[pos]; SetOrder(spell.id, order); local state = StateFor(spell.id); if state and NormalizeName(state.owner) == PlayerName() then BroadcastOrder(state); BroadcastTargets(state) end; ST.RefreshConfig(); if state then UpdateOverlay(state) end end end)
        down:SetScript("OnClick", function() local spell = SelectedSpell(); local order = GetOrder(spell.id); local pos = row.pos; if pos and pos < #order then order[pos], order[pos + 1] = order[pos + 1], order[pos]; SetOrder(spell.id, order); local state = StateFor(spell.id); if state and NormalizeName(state.owner) == PlayerName() then BroadcastOrder(state); BroadcastTargets(state) end; ST.RefreshConfig(); if state then UpdateOverlay(state) end end end); ST.rows[i] = row
    end
    f:SetScript("OnHide", function()
        for _, configRow in ipairs(ST.rows or {}) do
            if configRow.pos and configRow.CommitTarget and configRow.target then
                configRow.CommitTarget(configRow.target, true)
            end
        end
    end)
    if WowNote_RestoreWindowGeometry then WowNote_RestoreWindowGeometry("raidSpellTrackerConfig", f, { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }, false) end
    return f
end

function ST.RefreshConfig()
    if not ST.config then return end
    local db, spell = InitDB(), SelectedSpell(); if ST.spellDropDown and ST.spellDropDown.Refresh then ST.spellDropDown.Refresh() end
    if ST.turnSoundDropDown then ST.turnSoundDropDown.Refresh() end; if ST.nextSoundDropDown then ST.nextSoundDropDown.Refresh() end; if ST.turnCheck then ST.turnCheck.Refresh() end; if ST.nextCheck then ST.nextCheck.Refresh() end; if ST.autoCheck then ST.autoCheck.Refresh() end; if ST.enableCheck then ST.enableCheck.Refresh() end
    if ST.resourceModeDropDown and ST.resourceModeDropDown.Refresh then ST.resourceModeDropDown.Refresh() end
    if ST.resourceAlertCheck and ST.resourceAlertCheck.Refresh then ST.resourceAlertCheck.Refresh() end
    if ST.resourceThreshold and not ST.resourceThreshold:HasFocus() then
        ST.resourceThreshold:SetText(tostring(GetResourceMonitor(spell.id).threshold))
    end
    if ST.channelEdit and not ST.channelEdit:HasFocus() then ST.channelEdit:SetText(db.channels or "/raid") end
    local enabledNames = {}; for _, s in ipairs(SPELLS) do if IsSpellEnabled(s.id) then enabledNames[#enabledNames + 1] = s.name end end; if ST.activeLabel then ST.activeLabel:SetText("Enabled HUDs: " .. (#enabledNames > 0 and table.concat(enabledNames, ", ") or "none")) end
    local order = MergeOrderWithRoster(spell); local state = StateFor(spell.id); ST.status:SetText("Order - " .. spell.name .. (state and state.active and " |cff3399ff[ACTIVE]|r" or " |cffaaaaaa[stopped]|r"))
    local maxOffset = math.max(0, #order - CONFIG_ROWS); if (ST.configOffset or 0) > maxOffset then ST.configOffset = maxOffset end
    if ST.pageUp then if (ST.configOffset or 0) > 0 then ST.pageUp:Enable() else ST.pageUp:Disable() end end; if ST.pageDown then if (ST.configOffset or 0) < maxOffset then ST.pageDown:Enable() else ST.pageDown:Disable() end end
    for i = 1, CONFIG_ROWS do
        local row, pos = ST.rows[i], (ST.configOffset or 0) + i; local name = order[pos]; row.pos = name and pos or nil
        if name then row.index:SetText(pos .. "."); row.name:SetText(name); if not row.target:HasFocus() then
            local storedTarget = GetTarget(spell.id, name, pos)
            row.settingTargetText = true
            row.target:SetText(storedTarget)
            row.settingTargetText = false
            row.liveTarget = storedTarget
            row.liveSpellId = spell.id
            row.liveCaster = name
        end; local cap = state and state.capabilities[string.lower(name)]; local member = FindRosterMember(name); local talentState = spell.inspectTalent and member and GetCachedTalent(member, spell) or nil; local suffix = cap and " (synced)" or (spell.inspectTalent and talentState == false and " (no talent)" or (spell.inspectTalent and talentState == nil and " (checking)" or "")); row.cd:SetText((state and FormatCooldown(CooldownRemainingFor(state, name)) or "-") .. suffix); row.index:Show(); row.name:Show(); row.target:Show(); row.targetSelect:Show(); row.cd:Show(); row.up:Show(); row.down:Show(); local targetLocked = state and NormalizeName(state.owner) ~= PlayerName(); row.target:SetAlpha(targetLocked and 0.45 or 1.0); row.target:EnableMouse(not targetLocked); row.targetSelect:SetAlpha(targetLocked and 0.45 or 1.0); row.targetSelect:EnableMouse(not targetLocked); if targetLocked and row.target:HasFocus() then row.target:ClearFocus() end; if targetLocked and row.targetPopup then row.targetPopup:Hide() end; if pos == 1 then row.up:Disable() else row.up:Enable() end; if pos == #order then row.down:Disable() else row.down:Enable() end
        else row.index:Hide(); row.name:Hide(); row.target:Hide(); row.targetSelect:Hide(); if row.targetPopup then row.targetPopup:Hide() end; row.cd:Hide(); row.up:Hide(); row.down:Hide() end
    end
end
function ST.ShowConfig() local f = EnsureConfig(); f:Show(); if f.Raise then f:Raise() end; ST.RefreshConfig() end

function ST.OnUpdate(self, elapsed)
    if not AnyActive() or not HasVisibleTrackerHUD() then return end
    for _, state in pairs(ST.states) do
        local overlay = ST.overlays[state.spellId]
        if state.active and overlay and overlay:IsShown() then
            state.elapsed = state.elapsed + (elapsed or 0); state.selfElapsed = state.selfElapsed + (elapsed or 0); state.syncElapsed = state.syncElapsed + (elapsed or 0)
            if state.elapsed >= UPDATE_INTERVAL then state.elapsed = 0; UpdateOverlay(state) end
            if not state.testMode and state.selfElapsed >= SELF_STATUS_INTERVAL then state.selfElapsed = 0; BroadcastSelfStatus(state, false) end
            if not state.testMode and state.syncElapsed >= SYNC_INTERVAL then state.syncElapsed = 0; if NormalizeName(state.owner) == PlayerName() then SendAddon("ACT|" .. state.spellId .. "|" .. tostring(state.session or "") .. "|" .. PlayerName()) end end
        end
    end
    UpdateTalentInspection(elapsed or 0)
    if ST.config and ST.config:IsShown() then ST.RefreshConfig() end
end

ST.eventFrame = CreateFrame("Frame", "WowNoteRaidSpellTrackerEventFrame")
ST.eventFrame:RegisterEvent("PLAYER_LOGIN"); ST.eventFrame:RegisterEvent("CHAT_MSG_ADDON"); ST.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
ST.eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then InitDB(); RegisterPrefix()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...; if prefix == ADDON_PREFIX then HandleAddonMessage(message, sender) end
    elseif event == "PLAYER_REGEN_ENABLED" then UpdateAllOverlays()
    elseif event == "INSPECT_TALENT_READY" then
        local guid = ...
        HandleTalentInspectReady(guid)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not HasVisibleTrackerHUD() then return end local _, subEvent, _, sourceName, _, _, _, _, spellId = ...; if subEvent == "SPELL_CAST_SUCCESS" then ObserveCast(sourceName, spellId) end
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        ClearTalentInspectPending()
        for spellId, state in pairs(ST.states) do
            state.resourceSamples = nil  -- Unit tokens may have changed owners.
            if state.active and not state.testMode then
                MergeOrderWithRoster(SPELL_BY_ID[spellId])
                UpdateOverlay(state)
            end
        end
        if ST.RefreshConfig then ST.RefreshConfig() end
    end
end)

RegisterPrefix(); InitDB()
function WowNote_OpenRaidSpellTracker() ST.ShowConfig() end
