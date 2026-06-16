local ADDON_NAME = "WowNote"
local MODULE_VERSION = "1.10.29"

local RI = {}
WowNoteRaidIdTracker = RI

local frame
local listRows = {}
local statusText
local selectedCharKey
local selectedRaidIndex = nil
local scanFrame = CreateFrame("Frame", "WowNoteRaidIdTrackerEventFrame")
local pendingScan = false
local ScheduleScan
local MergePostedRaidIdData
local RefreshBossEditor

local function Internal()
    return WowNote_Internal or {}
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg))
end

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GetPlayerKey()
    local name, realm = UnitName("player")
    realm = realm and realm ~= "" and realm or GetRealmName()
    return (name or "Unknown") .. " - " .. (realm or "Unknown")
end


local function AddUnique(list, value)
    value = Trim(value or "")
    if value == "" then return end
    for _, existing in ipairs(list) do
        if string.lower(existing) == string.lower(value) then return end
    end
    table.insert(list, value)
end

local function SortNames(list)
    table.sort(list, function(a, b) return string.lower(tostring(a)) < string.lower(tostring(b)) end)
end

local function GetCurrentGroupMemberNames()
    local members = {}
    local function add(unit)
        if UnitExists and UnitExists(unit) then
            local name, realm = UnitName(unit)
            if name and name ~= "" and name ~= UNKNOWN then
                if realm and realm ~= "" then
                    AddUnique(members, name .. "-" .. realm)
                else
                    AddUnique(members, name)
                end
            end
        end
    end
    add("player")
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do add("raid" .. i) end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do add("party" .. i) end
    end
    SortNames(members)
    return members
end

local function MakeLockKey(lock)
    return tostring(lock and lock.id or "") .. "|" .. tostring(lock and lock.name or "") .. "|" .. tostring(lock and lock.difficulty or "")
end

local function EnsureDB()
    if WowNote_Internal and WowNote_Internal.InitDB then
        WowNote_Internal.InitDB()
    end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.raidIds) ~= "table" then WowNoteDB.raidIds = {} end
    if type(WowNoteDB.raidIds.characters) ~= "table" then WowNoteDB.raidIds.characters = {} end
    if type(WowNoteDB.raidIds.liveBossKills) ~= "table" then WowNoteDB.raidIds.liveBossKills = {} end
    return WowNoteDB.raidIds
end

local function FormatMoneyLikeTime(seconds)
    seconds = tonumber(seconds or 0) or 0
    if seconds <= 0 then return "expired" end
    local days = math.floor(seconds / 86400)
    seconds = seconds - days * 86400
    local hours = math.floor(seconds / 3600)
    seconds = seconds - hours * 3600
    local minutes = math.floor(seconds / 60)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end
    return string.format("%dm", minutes)
end

local function SortLocks(a, b)
    if a.name == b.name then
        return tostring(a.difficulty or "") < tostring(b.difficulty or "")
    end
    return tostring(a.name or "") < tostring(b.name or "")
end

local function GetDifficultyText(difficulty, maxPlayers, difficultyName)
    if difficultyName and difficultyName ~= "" then return difficultyName end
    if maxPlayers and maxPlayers > 0 then return tostring(maxPlayers) end
    if difficulty and difficulty > 0 then return "Difficulty " .. tostring(difficulty) end
    return "Raid"
end

local function ScanEncounterProgress(instanceIndex, numEncountersFromInfo, encounterProgressFromInfo)
    local bosses = {}
    local killed = 0
    local total = tonumber(numEncountersFromInfo or 0) or 0

    if GetSavedInstanceEncounterInfo then
        local limit = total > 0 and total or 25
        for encounterIndex = 1, limit do
            local ok, bossName, _, isKilled = pcall(GetSavedInstanceEncounterInfo, instanceIndex, encounterIndex)
            if not ok or not bossName then
                if total <= 0 then break end
            else
                local boss = {
                    name = tostring(bossName),
                    killed = isKilled and true or false,
                }
                table.insert(bosses, boss)
                if boss.killed then killed = killed + 1 end
            end
        end
    end

    if total <= 0 then
        total = #bosses
    end

    local progress = tonumber(encounterProgressFromInfo or 0) or 0
    if progress <= 0 then
        progress = killed
    end

    return bosses, total, progress
end

local function FormatBossProgress(lock)
    local total = tonumber(lock and lock.numEncounters or 0) or 0
    local progress = tonumber(lock and lock.encounterProgress or 0) or 0
    if total > 0 then
        return tostring(progress) .. "/" .. tostring(total)
    end
    if lock and lock.bosses and #lock.bosses > 0 then
        return tostring(progress) .. "/" .. tostring(#lock.bosses)
    end
    return "unknown"
end

local function GetKilledBossNames(lock)
    local names = {}
    for _, boss in ipairs((lock and lock.bosses) or {}) do
        if boss.killed then
            table.insert(names, boss.name or "Unknown")
        end
    end
    return names
end



local ICC_BOSS_ORDER = {
    "Lord Marrowgar",
    "Lady Deathwhisper",
    "Icecrown Gunship Battle",
    "Deathbringer Saurfang",
    "Festergut",
    "Rotface",
    "Professor Putricide",
    "Blood Prince Council",
    "Blood-Queen Lana'thel",
    "Valithria Dreamwalker",
    "Sindragosa",
    "The Lich King",
}

local INSTANCE_BOSS_ORDER = {
    ["icecrown citadel"] = ICC_BOSS_ORDER,
    ["eiskronenzitadelle"] = ICC_BOSS_ORDER,
}

local BOSS_ALIASES = {
    ["gunship battle"] = "Icecrown Gunship Battle",
    ["icecrown gunship battle"] = "Icecrown Gunship Battle",
    ["luftschiffkampf"] = "Icecrown Gunship Battle",
    ["luftschiffschlacht"] = "Icecrown Gunship Battle",
    ["luftschiffkampf um die eiskronenzitadelle"] = "Icecrown Gunship Battle",
    ["the skybreaker"] = "Icecrown Gunship Battle",
    ["orgrim's hammer"] = "Icecrown Gunship Battle",
    ["dbs"] = "Deathbringer Saurfang",
    ["saurfang"] = "Deathbringer Saurfang",
    ["todesbringer saurfang"] = "Deathbringer Saurfang",
}

local KNOWN_RAID_BOSSES = {
    ["lord marrowgar"] = true,
    ["lady deathwhisper"] = true,
    ["deathbringer saurfang"] = true,
    ["dbs"] = true,
    ["saurfang"] = true,
    ["todesbringer saurfang"] = true,
    ["icecrown gunship battle"] = true,
    ["gunship battle"] = true,
    ["luftschiffkampf"] = true,
    ["luftschiffschlacht"] = true,
    ["luftschiffkampf um die eiskronenzitadelle"] = true,
    ["the skybreaker"] = true,
    ["orgrim's hammer"] = true,
    ["festergut"] = true,
    ["rotface"] = true,
    ["professor putricide"] = true,
    ["blood prince council"] = true,
    ["prince valanar"] = true,
    ["prince taldaram"] = true,
    ["prince keleseth"] = true,
    ["blood-queen lana'thel"] = true,
    ["blood queen lana'thel"] = true,
    ["valithria dreamwalker"] = true,
    ["sindragosa"] = true,
    ["the lich king"] = true,
    ["gormok the impaler"] = true,
    ["acidmaw"] = true,
    ["dreadscale"] = true,
    ["icehowl"] = true,
    ["lord jaraxxus"] = true,
    ["faction champions"] = true,
    ["eydis darkbane"] = true,
    ["fjola lightbane"] = true,
    ["anub'arak"] = true,
    ["halion"] = true,
    ["saviana ragefire"] = true,
    ["baltharus the warborn"] = true,
    ["general zarithrian"] = true,
    ["archavon the stone watcher"] = true,
    ["emalon the storm watcher"] = true,
    ["koralon the flame watcher"] = true,
    ["toravon the ice watcher"] = true,
    ["flame leviathan"] = true,
    ["ignis the furnace master"] = true,
    ["razorscale"] = true,
    ["xt-002 deconstructor"] = true,
    ["the assembly of iron"] = true,
    ["steelbreaker"] = true,
    ["runemaster molgeim"] = true,
    ["stormcaller brundir"] = true,
    ["kologarn"] = true,
    ["auriaya"] = true,
    ["hodir"] = true,
    ["thorim"] = true,
    ["freya"] = true,
    ["mimiron"] = true,
    ["general vezax"] = true,
    ["yogg-saron"] = true,
    ["algalon the observer"] = true,
    ["anub'rekhan"] = true,
    ["grand widow faerlina"] = true,
    ["maexxna"] = true,
    ["noth the plaguebringer"] = true,
    ["heigan the unclean"] = true,
    ["loatheb"] = true,
    ["instructor razuvious"] = true,
    ["gothik the harvester"] = true,
    ["the four horsemen"] = true,
    ["patchwerk"] = true,
    ["grobbulus"] = true,
    ["gluth"] = true,
    ["thaddius"] = true,
    ["sapphiron"] = true,
    ["kel'thuzad"] = true,
    ["malygos"] = true,
    ["sartharion"] = true,
    ["onyxia"] = true,
}

local function NormalizeBossName(name)
    return string.lower(Trim(name or ""))
end

local function CanonicalBossName(name)
    local original = Trim(name or "")
    local normalized = NormalizeBossName(original)
    return BOSS_ALIASES[normalized] or original
end

local function IsKnownRaidBoss(name)
    local normalized = NormalizeBossName(CanonicalBossName(name))
    return normalized ~= "" and KNOWN_RAID_BOSSES[normalized] == true
end

local function AddFallbackEncounterProgress(instanceName, bosses, total, progress)
    local order = INSTANCE_BOSS_ORDER[NormalizeBossName(instanceName)]
    if not order then return bosses, total, progress end

    bosses = bosses or {}
    total = math.max(tonumber(total or 0) or 0, #order)
    progress = tonumber(progress or 0) or 0

    local orderIndexByName = {}
    for index, bossName in ipairs(order) do
        orderIndexByName[NormalizeBossName(bossName)] = index
    end

    local byName = {}
    for _, boss in ipairs(bosses) do
        local canonical = CanonicalBossName(boss.name)
        local key = NormalizeBossName(canonical)
        if key ~= NormalizeBossName(boss.name) then
            boss.name = canonical
        end
        byName[key] = boss
        if boss.killed and orderIndexByName[key] then
            progress = math.max(progress, orderIndexByName[key])
        end
    end

    for index, bossName in ipairs(order) do
        local key = NormalizeBossName(bossName)
        if not byName[key] then
            local boss = { name = bossName, killed = index <= progress, inferred = true }
            table.insert(bosses, boss)
            byName[key] = boss
        elseif index <= progress then
            byName[key].killed = true
        end
    end

    return bosses, total, progress
end

local function MergeBossIntoLock(lock, bossName, killed)
    bossName = CanonicalBossName(bossName)
    if not lock or not bossName or bossName == "" then return false end
    lock.bosses = lock.bosses or {}
    local normalized = NormalizeBossName(bossName)
    local existing
    for _, boss in ipairs(lock.bosses) do
        if NormalizeBossName(boss.name) == normalized then
            existing = boss
            break
        end
    end
    if existing then
        existing.killed = existing.killed or (killed and true or false)
    else
        table.insert(lock.bosses, { name = bossName, killed = killed and true or false, recordedLive = true })
    end
    local killedCount = 0
    for _, boss in ipairs(lock.bosses or {}) do
        if boss.killed then killedCount = killedCount + 1 end
    end
    lock.numEncounters = math.max(tonumber(lock.numEncounters or 0) or 0, #lock.bosses)
    lock.encounterProgress = math.max(tonumber(lock.encounterProgress or 0) or 0, killedCount)
    return true
end

local function GetSelectedLock()
    local db = EnsureDB()
    local entry = selectedCharKey and db.characters and db.characters[selectedCharKey]
    local raids = entry and entry.raids or {}
    return selectedRaidIndex and raids[selectedRaidIndex] or nil
end

local function IsBossKilledInLock(lock, bossName)
    local key = NormalizeBossName(CanonicalBossName(bossName))
    for _, boss in ipairs(lock and lock.bosses or {}) do
        if NormalizeBossName(CanonicalBossName(boss.name)) == key then
            return boss.killed and true or false
        end
    end
    return false
end

local function SetManualBossKill(lock, bossName, killed)
    if not lock or not bossName or bossName == "" then return false end
    bossName = CanonicalBossName(bossName)
    lock.bosses = lock.bosses or {}
    local key = NormalizeBossName(bossName)
    local found
    for _, boss in ipairs(lock.bosses) do
        if NormalizeBossName(CanonicalBossName(boss.name)) == key then
            found = boss
            break
        end
    end
    if not found then
        found = { name = bossName, killed = false, manual = true }
        table.insert(lock.bosses, found)
    end
    found.name = bossName
    found.killed = killed and true or false
    found.manual = true
    lock.manualBossUpdatedAt = time()

    local killedCount = 0
    for _, boss in ipairs(lock.bosses or {}) do
        if boss.killed then killedCount = killedCount + 1 end
    end
    lock.numEncounters = math.max(tonumber(lock.numEncounters or 0) or 0, #lock.bosses)
    lock.encounterProgress = killedCount
    return true
end

local function ToggleSelectedBossKill(bossName)
    local lock = GetSelectedLock()
    if not lock or not bossName then return end
    local killed = not IsBossKilledInLock(lock, bossName)
    SetManualBossKill(lock, bossName, killed)
    if statusText then
        statusText:SetText((killed and "Marked killed: " or "Cleared kill: ") .. tostring(CanonicalBossName(bossName)))
    end
    if RI.RefreshUI then RI.RefreshUI() end
    if RefreshBossEditor then RefreshBossEditor() end
end

local function GetCurrentRaidContext()
    if not GetInstanceInfo then return nil end
    local instanceName, instanceType, difficultyIndex, difficultyName, maxPlayers = GetInstanceInfo()
    if instanceType == "raid" and instanceName and instanceName ~= "" then
        return {
            name = instanceName,
            difficultyIndex = difficultyIndex,
            difficultyName = difficultyName,
            maxPlayers = tonumber(maxPlayers or 0) or 0,
        }
    end
    return nil
end

local function GetCurrentRaidInstanceName()
    local context = GetCurrentRaidContext()
    return context and context.name or nil
end

local function ShouldAttachCurrentGroupToLock(lock, context)
    if not lock or not context or not context.name then return false end
    if tostring(lock.name or "") ~= tostring(context.name or "") then return false end

    local contextMaxPlayers = tonumber(context.maxPlayers or 0) or 0
    local lockMaxPlayers = tonumber(lock.maxPlayers or 0) or 0
    if contextMaxPlayers > 0 and lockMaxPlayers > 0 and contextMaxPlayers ~= lockMaxPlayers then
        return false
    end

    return true
end

local function MergeLiveBossKillsIntoLock(db, charKey, lock)
    if not db or not charKey or not lock or not lock.name then return end
    local byChar = db.liveBossKills and db.liveBossKills[charKey]
    local byInstance = byChar and byChar[lock.name]
    if not byInstance then return end
    for bossName in pairs(byInstance) do
        MergeBossIntoLock(lock, bossName, true)
    end
end

local function RecordLiveEncounterProgress(instanceName, progress, reason)
    local order = INSTANCE_BOSS_ORDER[NormalizeBossName(instanceName)]
    if not order then return false end

    progress = math.min(math.max(tonumber(progress or 0) or 0, 0), #order)
    if progress <= 0 then return false end

    local db = EnsureDB()
    local charKey = GetPlayerKey()
    if type(db.liveBossKills) ~= "table" then db.liveBossKills = {} end
    db.liveBossKills[charKey] = db.liveBossKills[charKey] or {}
    db.liveBossKills[charKey][instanceName] = db.liveBossKills[charKey][instanceName] or {}

    local now = time()
    for index = 1, progress do
        db.liveBossKills[charKey][instanceName][CanonicalBossName(order[index])] = now
    end

    local entry = db.characters[charKey]
    if entry and entry.raids then
        for _, lock in ipairs(entry.raids) do
            if tostring(lock.name or "") == tostring(instanceName) then
                for index = 1, progress do
                    MergeBossIntoLock(lock, order[index], true)
                end
                lock.bosses, lock.numEncounters, lock.encounterProgress = AddFallbackEncounterProgress(lock.name, lock.bosses, lock.numEncounters, lock.encounterProgress)
                lock.liveBossUpdatedAt = now
            end
        end
    end

    if statusText then
        statusText:SetText(reason or ("Recorded raid progress: " .. tostring(progress) .. " bosses in " .. tostring(instanceName) .. "."))
    end
    if RI.RefreshUI then RI.RefreshUI() end
    if RequestRaidInfo then RequestRaidInfo() end
    ScheduleScan()
    return true
end

local function IsSaurfangCombatName(name)
    local normalized = NormalizeBossName(CanonicalBossName(name))
    return normalized == "deathbringer saurfang" or normalized == "dbs" or normalized == "saurfang" or normalized == "todesbringer saurfang"
end

local function RecordSaurfangPullFallback(sourceName, destName)
    local instanceName = GetCurrentRaidInstanceName()
    if not instanceName or not INSTANCE_BOSS_ORDER[NormalizeBossName(instanceName)] then return false end
    if not IsSaurfangCombatName(sourceName) and not IsSaurfangCombatName(destName) then return false end
    return RecordLiveEncounterProgress(instanceName, 3, "Recorded ICC progress: Saurfang combat seen; marking Marrowgar, Deathwhisper and Gunship as done.")
end

local function RecordLiveBossKill(bossName)
    bossName = CanonicalBossName(bossName)
    if bossName == "" or not IsKnownRaidBoss(bossName) then return false end
    local instanceName = GetCurrentRaidInstanceName()
    if not instanceName then return false end

    local db = EnsureDB()
    local charKey = GetPlayerKey()
    if type(db.liveBossKills) ~= "table" then db.liveBossKills = {} end
    db.liveBossKills[charKey] = db.liveBossKills[charKey] or {}
    db.liveBossKills[charKey][instanceName] = db.liveBossKills[charKey][instanceName] or {}
    db.liveBossKills[charKey][instanceName][bossName] = time()

    local entry = db.characters[charKey]
    if entry and entry.raids then
        for _, lock in ipairs(entry.raids) do
            if tostring(lock.name or "") == tostring(instanceName) then
                MergeBossIntoLock(lock, bossName, true)
                lock.liveBossUpdatedAt = time()
            end
        end
    end

    if statusText then
        statusText:SetText("Recorded boss kill: " .. bossName .. " (" .. instanceName .. ").")
    end
    if RI.RefreshUI then RI.RefreshUI() end
    if RequestRaidInfo then RequestRaidInfo() end
    ScheduleScan()
    return true
end

local function HandleCombatLogEvent(...)
    -- WoW 3.3.5a combat log signature has no hideCaster argument.
    local timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags = ...

    if subevent ~= "UNIT_DIED" and subevent ~= "PARTY_KILL" then
        RecordSaurfangPullFallback(sourceName, destName)
        return
    end

    if type(destName) ~= "string" or destName == "" then return end
    RecordLiveBossKill(destName)
end

function RI.ScanCurrentCharacter()
    local db = EnsureDB()
    local charKey = GetPlayerKey()
    local now = time()
    local currentMembers = GetCurrentGroupMemberNames()
    local currentRaidContext = GetCurrentRaidContext()
    local entry = db.characters[charKey] or {}
    local previousByKey = {}
    if entry.raids then
        for _, oldLock in ipairs(entry.raids) do
            previousByKey[MakeLockKey(oldLock)] = oldLock
        end
    end

    entry.name = UnitName("player") or "Unknown"
    entry.realm = GetRealmName() or "Unknown"
    entry.updatedAt = now
    entry.raids = {}

    if RequestRaidInfo then RequestRaidInfo() end

    local count = GetNumSavedInstances and GetNumSavedInstances() or 0
    for i = 1, count do
        local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        if isRaid == true and locked == true and name then
            local resetSeconds = tonumber(reset or 0) or 0
            local bosses, totalEncounters, killedEncounters = ScanEncounterProgress(i, numEncounters, encounterProgress)
            bosses, totalEncounters, killedEncounters = AddFallbackEncounterProgress(name, bosses, totalEncounters, killedEncounters)
            local lock = {
                name = name,
                id = id,
                reset = resetSeconds,
                expiresAt = now + resetSeconds,
                difficulty = GetDifficultyText(difficulty, maxPlayers, difficultyName),
                difficultyId = difficulty,
                maxPlayers = maxPlayers,
                extended = extended and true or false,
                numEncounters = totalEncounters,
                encounterProgress = killedEncounters,
                bosses = bosses,
                members = {},
                firstSeenAt = now,
                lastSeenAt = now,
            }
            local old = previousByKey[MakeLockKey(lock)]
            if old then
                lock.firstSeenAt = old.firstSeenAt or now
                lock.members = old.members or {}
                -- Always merge previously recorded/manual boss states. Saved-instance scans
                -- can return partial encounter data and must not erase manual corrections.
                if old.bosses then
                    lock.bosses = lock.bosses or {}
                    local currentByName = {}
                    for _, boss in ipairs(lock.bosses) do
                        currentByName[NormalizeBossName(CanonicalBossName(boss.name))] = boss
                    end
                    for _, oldBoss in ipairs(old.bosses) do
                        local key = NormalizeBossName(CanonicalBossName(oldBoss.name))
                        local current = currentByName[key]
                        if current then
                            if oldBoss.killed then current.killed = true end
                            if oldBoss.manual then current.manual = true end
                            if oldBoss.recordedLive then current.recordedLive = true end
                        else
                            local copy = {
                                name = CanonicalBossName(oldBoss.name),
                                killed = oldBoss.killed and true or false,
                                manual = oldBoss.manual and true or false,
                                recordedLive = oldBoss.recordedLive and true or false,
                                inferred = oldBoss.inferred and true or false,
                            }
                            table.insert(lock.bosses, copy)
                            currentByName[key] = copy
                        end
                    end
                    local killedCount = 0
                    for _, boss in ipairs(lock.bosses) do
                        if boss.killed then killedCount = killedCount + 1 end
                    end
                    lock.numEncounters = math.max(tonumber(lock.numEncounters or 0) or 0, tonumber(old.numEncounters or 0) or 0, #lock.bosses)
                    lock.encounterProgress = math.max(tonumber(lock.encounterProgress or 0) or 0, killedCount)
                    lock.manualBossUpdatedAt = old.manualBossUpdatedAt
                    lock.liveBossUpdatedAt = old.liveBossUpdatedAt
                end
            end
            MergeLiveBossKillsIntoLock(db, charKey, lock)
            lock.bosses, lock.numEncounters, lock.encounterProgress = AddFallbackEncounterProgress(lock.name, lock.bosses, lock.numEncounters, lock.encounterProgress)
            if ShouldAttachCurrentGroupToLock(lock, currentRaidContext) then
                for _, memberName in ipairs(currentMembers) do
                    AddUnique(lock.members, memberName)
                end
                lock.membersRecordedInInstance = currentRaidContext and currentRaidContext.name or lock.name
                lock.membersUpdatedAt = now
            end
            SortNames(lock.members)
            table.insert(entry.raids, lock)
        end
    end
    table.sort(entry.raids, SortLocks)
    db.characters[charKey] = entry
    if not selectedCharKey then
        selectedCharKey = charKey
    end
    if RI.RefreshUI then RI.RefreshUI() end
    if statusText then
        statusText:SetText("Updated " .. charKey .. " (" .. #entry.raids .. " raid IDs).")
    end
end

ScheduleScan = function()
    if pendingScan then return end
    pendingScan = true
    local elapsed = 0
    scanFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= 1.0 then
            self:SetScript("OnUpdate", nil)
            pendingScan = false
            RI.ScanCurrentCharacter()
        end
    end)
end

scanFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
scanFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
scanFrame:RegisterEvent("RAID_ROSTER_UPDATE")
scanFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
scanFrame:RegisterEvent("CHAT_MSG_GUILD")
scanFrame:RegisterEvent("CHAT_MSG_PARTY")
scanFrame:RegisterEvent("CHAT_MSG_RAID")
scanFrame:RegisterEvent("CHAT_MSG_CHANNEL")
scanFrame:RegisterEvent("CHAT_MSG_WHISPER")
scanFrame:RegisterEvent("CHAT_MSG_YELL")
scanFrame:RegisterEvent("CHAT_MSG_SAY")
scanFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
scanFrame:SetScript("OnEvent", function(self, event, ...)
    if string.find(tostring(event or ""), "^CHAT_MSG_") then
        local message, sender = ...
        MergePostedRaidIdData(message, sender)
        return
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLogEvent(...)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if RequestRaidInfo then RequestRaidInfo() end
        ScheduleScan()
    elseif event == "UPDATE_INSTANCE_INFO" or event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        ScheduleScan()
    end
end)

local function MakeButton(parent, text, width, height)
    if WowNote_Internal and WowNote_Internal.MakeButton then
        return WowNote_Internal.MakeButton(parent, text, width, height)
    end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 90, height or 24)
    b:SetText(text or "Button")
    return b
end

local function MakeTitle(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function MakeSmall(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function CreateCharButton(parent, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(190, 22)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.text:SetJustifyH("LEFT")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetTexture(0.16, 0.12, 0.06, 0.55)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b:SetScript("OnClick", function(self)
        selectedCharKey = self.charKey
        RI.RefreshUI()
    end)
    return b
end

local function CreateRaidRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(585, 22)
    row.index = index
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(0.10, 0.08, 0.04, 0.25)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnMouseDown", function(self)
        selectedRaidIndex = self.index
        RI.RefreshUI()
    end)
    row:SetScript("OnClick", function(self)
        selectedRaidIndex = self.index
        RI.RefreshUI()
    end)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetWidth(255)
    row.name:SetJustifyH("LEFT")
    row.diff = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.diff:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.diff:SetWidth(120)
    row.diff:SetJustifyH("LEFT")
    row.id = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.id:SetPoint("LEFT", row.diff, "RIGHT", 8, 0)
    row.id:SetWidth(90)
    row.id:SetJustifyH("LEFT")
    row.reset = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.reset:SetPoint("LEFT", row.id, "RIGHT", 8, 0)
    row.reset:SetWidth(90)
    row.reset:SetJustifyH("LEFT")
    return row
end


local function GetAlsoSavedOnAccount(db, lock)
    local names = {}
    local key = MakeLockKey(lock)
    for charKey, entry in pairs(db.characters or {}) do
        for _, otherLock in ipairs(entry.raids or {}) do
            if MakeLockKey(otherLock) == key then
                AddUnique(names, charKey)
            end
        end
    end
    SortNames(names)
    return names
end

local function BuildLockLine(charKey, lock)
    local members = lock.members and #lock.members or 0
    return string.format("%s: %s %s ID %s, progress %s, %s remaining, seen with %d player%s",
        tostring(charKey or "Character"),
        tostring(lock.name or "Unknown"),
        tostring(lock.difficulty or "Raid"),
        tostring(lock.id or "-"),
        FormatBossProgress(lock),
        FormatMoneyLikeTime((lock.expiresAt or time()) - time()),
        members,
        members == 1 and "" or "s")
end

local function BuildMemberHeaderLine(charKey, lock)
    local members = lock.members or {}
    return string.format("%s: members seen with %s %s ID %s (%d):",
        tostring(charKey or "Character"),
        tostring(lock.name or "Unknown"),
        tostring(lock.difficulty or "Raid"),
        tostring(lock.id or "-"),
        #members)
end

local function BuildMemberListLines(charKey, lock)
    local members = {}
    for _, member in ipairs(lock.members or {}) do
        AddUnique(members, member)
    end
    SortNames(members)

    local lines = { BuildMemberHeaderLine(charKey, lock) }
    if #members == 0 then
        table.insert(lines, "No members recorded for this ID yet.")
        return lines
    end

    local current = ""
    for _, member in ipairs(members) do
        local candidate
        if current == "" then
            candidate = tostring(member)
        else
            candidate = current .. ", " .. tostring(member)
        end

        if string.len(candidate) > 210 then
            table.insert(lines, current)
            current = tostring(member)
        else
            current = candidate
        end
    end
    if current ~= "" then table.insert(lines, current) end
    return lines
end

local function EncodeField(value)
    value = tostring(value or "")
    value = value:gsub("%%", "%%25")
    value = value:gsub(";", "%%3B")
    value = value:gsub(",", "%%2C")
    value = value:gsub("\n", "%%0A")
    return value
end

local function DecodeField(value)
    value = tostring(value or "")
    value = value:gsub("%%0A", "\n")
    value = value:gsub("%%2C", ",")
    value = value:gsub("%%3B", ";")
    value = value:gsub("%%25", "%%")
    return value
end

local function BuildMachineLine(charKey, lock)
    local encodedMembers = {}
    for _, member in ipairs(lock.members or {}) do
        table.insert(encodedMembers, EncodeField(member))
    end
    local encodedBosses = {}
    for _, boss in ipairs(lock.bosses or {}) do
        table.insert(encodedBosses, EncodeField((boss.killed and "1" or "0") .. ":" .. tostring(boss.name or "Unknown")))
    end
    return "WNRI:v1;id=" .. EncodeField(lock.id or "")
        .. ";name=" .. EncodeField(lock.name or "")
        .. ";diff=" .. EncodeField(lock.difficulty or "")
        .. ";char=" .. EncodeField(charKey or "")
        .. ";progress=" .. EncodeField(FormatBossProgress(lock))
        .. ";bosses=" .. table.concat(encodedBosses, ",")
        .. ";members=" .. table.concat(encodedMembers, ",")
end

local function ParseMachineLine(message)
    message = tostring(message or "")
    if not string.find(message, "^WNRI:v1;") then return nil end
    local payload = string.sub(message, 9)
    local data = { members = {} }
    for part in string.gmatch(payload, "[^;]+") do
        local key, value = string.match(part, "^([^=]+)=(.*)$")
        if key and value then
            if key == "members" then
                for member in string.gmatch(value, "[^,]+") do
                    AddUnique(data.members, DecodeField(member))
                end
            elseif key == "bosses" then
                data.bosses = data.bosses or {}
                for bossValue in string.gmatch(value, "[^,]+") do
                    local decodedBoss = DecodeField(bossValue)
                    local killedFlag, bossName = string.match(decodedBoss, "^([01]):(.*)$")
                    if bossName and bossName ~= "" then
                        table.insert(data.bosses, { name = bossName, killed = killedFlag == "1" })
                    end
                end
            else
                data[key] = DecodeField(value)
            end
        end
    end
    if not data.id or data.id == "" then return nil end
    return data
end

MergePostedRaidIdData = function(message, sender)
    local data = ParseMachineLine(message)
    if not data then return false end
    local db = EnsureDB()
    local merged = 0
    for _, entry in pairs(db.characters or {}) do
        for _, lock in ipairs(entry.raids or {}) do
            if tostring(lock.id or "") == tostring(data.id or "") then
                lock.members = lock.members or {}
                AddUnique(lock.members, data.char or sender or "")
                for _, member in ipairs(data.members or {}) do
                    AddUnique(lock.members, member)
                end
                SortNames(lock.members)
                if data.bosses and #data.bosses > 0 then
                    lock.bosses = lock.bosses or {}
                    local existing = {}
                    for _, boss in ipairs(lock.bosses) do
                        existing[string.lower(tostring(boss.name or ""))] = boss
                    end
                    for _, postedBoss in ipairs(data.bosses) do
                        local key = string.lower(tostring(postedBoss.name or ""))
                        if key ~= "" then
                            if existing[key] then
                                existing[key].killed = existing[key].killed or postedBoss.killed
                            else
                                table.insert(lock.bosses, { name = postedBoss.name, killed = postedBoss.killed and true or false })
                            end
                        end
                    end
                    local killedCount = 0
                    for _, boss in ipairs(lock.bosses) do if boss.killed then killedCount = killedCount + 1 end end
                    lock.numEncounters = math.max(tonumber(lock.numEncounters or 0) or 0, #lock.bosses)
                    lock.encounterProgress = math.max(tonumber(lock.encounterProgress or 0) or 0, killedCount)
                end
                lock.lastImportedAt = time()
                lock.lastImportedFrom = sender
                merged = merged + 1
            end
        end
    end
    if merged > 0 then
        if statusText then
            statusText:SetText("Imported posted raid ID data for ID " .. tostring(data.id) .. ".")
        end
        if RI.RefreshUI then RI.RefreshUI() end
    end
    return true
end

local function SendToChannel(message, channelText)
    channelText = Trim(channelText or "/g")
    local lower = string.lower(channelText)
    local whisperTarget = string.match(channelText, "^%s*/w%s+([^%s]+)") or string.match(channelText, "^%s*/whisper%s+([^%s]+)")
        or string.match(channelText, "^%s*w%s+([^%s]+)") or string.match(channelText, "^%s*whisper%s+([^%s]+)")
    if whisperTarget and whisperTarget ~= "" then
        SendChatMessage(message, "WHISPER", nil, whisperTarget)
    elseif lower == "/g" or lower == "g" or lower == "/guild" then
        SendChatMessage(message, "GUILD")
    elseif lower == "/p" or lower == "p" or lower == "/party" then
        SendChatMessage(message, "PARTY")
    elseif lower == "/raid" or lower == "/ra" or lower == "raid" then
        SendChatMessage(message, "RAID")
    elseif lower == "/y" or lower == "y" or lower == "/yell" then
        SendChatMessage(message, "YELL")
    elseif lower == "/s" or lower == "s" or lower == "/say" then
        SendChatMessage(message, "SAY")
    else
        local num = tonumber(string.match(lower, "^/?(%d+)$"))
        if num then
            local id = GetChannelName(num)
            if id and id > 0 then
                SendChatMessage(message, "CHANNEL", nil, id)
            else
                Print("Channel " .. tostring(channelText) .. " not found.")
            end
        else
            SendChatMessage(message, "GUILD")
        end
    end
end

function RI.PostSelected()
    local db = EnsureDB()
    local entry = selectedCharKey and db.characters[selectedCharKey]
    local lock = entry and entry.raids and entry.raids[selectedRaidIndex or 1]
    if not lock then Print("Select a raid ID first.") return end
    local channel = frame and frame.channelEdit and frame.channelEdit:GetText() or "/g"
    SendToChannel(BuildLockLine(selectedCharKey, lock), channel)
    SendToChannel(BuildMachineLine(selectedCharKey, lock), channel)
end

function RI.PostSelectedMembers()
    local db = EnsureDB()
    local entry = selectedCharKey and db.characters[selectedCharKey]
    local lock = entry and entry.raids and entry.raids[selectedRaidIndex or 1]
    if not lock then Print("Select a raid ID first.") return end
    local channel = frame and frame.channelEdit and frame.channelEdit:GetText() or "/g"
    local lines = BuildMemberListLines(selectedCharKey, lock)
    for _, line in ipairs(lines) do
        SendToChannel(line, channel)
    end
end


function RI.ClearSelectedMembers()
    local db = EnsureDB()
    local entry = selectedCharKey and db.characters[selectedCharKey]
    local lock = entry and entry.raids and entry.raids[selectedRaidIndex or 1]
    if not lock then Print("Select a raid ID first.") return end
    lock.members = {}
    lock.membersUpdatedAt = nil
    lock.membersRecordedInInstance = nil
    Print("Cleared saved member list for " .. tostring(lock.name or "selected raid ID") .. " ID " .. tostring(lock.id or "-"))
    if RI.RefreshUI then RI.RefreshUI() end
end

function RI.PostAll()
    local db = EnsureDB()
    local channel = frame and frame.channelEdit and frame.channelEdit:GetText() or "/g"
    for charKey, entry in pairs(db.characters or {}) do
        for _, lock in ipairs(entry.raids or {}) do
            SendToChannel(BuildLockLine(charKey, lock), channel)
            SendToChannel(BuildMachineLine(charKey, lock), channel)
        end
    end
end

function RI.RefreshUI()
    if not frame then return end
    local db = EnsureDB()
    local chars = {}
    for key, entry in pairs(db.characters) do
        table.insert(chars, { key = key, updatedAt = entry.updatedAt or 0 })
    end
    table.sort(chars, function(a, b) return tostring(a.key) < tostring(b.key) end)
    if not selectedCharKey and #chars > 0 then selectedCharKey = chars[1].key end

    for i = 1, 12 do
        local b = frame.charButtons[i]
        local c = chars[i]
        if c then
            b.charKey = c.key
            local entry = db.characters[c.key]
            local count = entry and entry.raids and #entry.raids or 0
            b.text:SetText(c.key .. " (" .. count .. ")")
            if c.key == selectedCharKey then
                b.bg:SetTexture(0.35, 0.24, 0.08, 0.85)
            else
                b.bg:SetTexture(0.16, 0.12, 0.06, 0.55)
            end
            b:Show()
        else
            b.charKey = nil
            b:Hide()
        end
    end

    local entry = selectedCharKey and db.characters[selectedCharKey]
    frame.selectedText:SetText(selectedCharKey and ("Selected: " .. selectedCharKey) or "Selected: none")
    local raids = entry and entry.raids or {}
    local now = time()

    for i = 1, 16 do
        local row = frame.raidRows[i]
        local lock = raids[i]
        if lock then
            row.name:SetText(lock.name or "Unknown")
            row.diff:SetText(lock.difficulty or "Raid")
            row.id:SetText(lock.id and tostring(lock.id) or "-")
            local remaining = (lock.expiresAt or now) - now
            row.reset:SetText(FormatMoneyLikeTime(remaining))
            if i == selectedRaidIndex then
                row.bg:SetTexture(0.35, 0.24, 0.08, 0.70)
            else
                row.bg:SetTexture(0.10, 0.08, 0.04, 0.25)
            end
            row:Show()
        else
            row:Hide()
        end
    end

    if #raids == 0 then
        frame.emptyText:Show()
        selectedRaidIndex = nil
    else
        frame.emptyText:Hide()
        if not selectedRaidIndex or selectedRaidIndex > #raids then selectedRaidIndex = 1 end
    end

    if frame.detailsText then
        local lock = selectedRaidIndex and raids[selectedRaidIndex]
        if lock then
            local account = GetAlsoSavedOnAccount(db, lock)
            local members = lock.members or {}
            local killedBosses = GetKilledBossNames(lock)
            local detailLines = {
                "Selected ID details:",
                "Raid: " .. tostring(lock.name or "Unknown") .. " | " .. tostring(lock.difficulty or "Raid") .. " | ID: " .. tostring(lock.id or "-"),
                "Progress: " .. FormatBossProgress(lock),
                "Killed bosses: " .. (#killedBosses > 0 and table.concat(killedBosses, ", ") or "none recorded"),
                "Also saved on this account: " .. (#account > 0 and table.concat(account, ", ") or "none"),
                "Seen with this ID/group: " .. (#members > 0 and table.concat(members, ", ") or "none recorded"),
            }
            local detail = table.concat(detailLines, "\n")
            frame.detailsText:SetText(detail)
        else
            frame.detailsText:SetText("Select a raid ID to see saved-with details.")
        end
    end

    if frame.editBossButton then
        local lock = selectedRaidIndex and raids[selectedRaidIndex]
        local order = lock and INSTANCE_BOSS_ORDER[NormalizeBossName(lock.name or "")] or nil
        if lock and order then
            frame.editBossButton:Show()
        else
            frame.editBossButton:Hide()
            if frame.bossEditor then frame.bossEditor:Hide() end
        end
    end

    if RefreshBossEditor then RefreshBossEditor() end
end

RefreshBossEditor = function()
    if not frame or not frame.bossEditor then return end
    local lock = GetSelectedLock()
    local order = lock and INSTANCE_BOSS_ORDER[NormalizeBossName(lock.name or "")] or nil
    if not frame.bossEditor:IsShown() then return end
    if not lock or not order then
        frame.bossEditor:Hide()
        return
    end

    frame.bossEditor.title:SetText("Edit killed bosses: " .. tostring(lock.name or "Raid"))
    for i = 1, 12 do
        local button = frame.bossEditor.buttons[i]
        local bossName = order[i]
        if button and bossName then
            local killed = IsBossKilledInLock(lock, bossName)
            button.bossName = bossName
            button:SetChecked(killed and true or false)
            if button.text then
                button.text:SetText(tostring(bossName))
                button.text:Show()
            end
            button:Show()
        elseif button then
            button.bossName = nil
            button:SetChecked(false)
            button:Hide()
            if button.text then button.text:Hide() end
        end
    end
end

local function CreateUI()
    if frame then return end
    frame = CreateFrame("Frame", "WowNoteRaidIdTrackerFrame", UIParent)
    frame:SetSize(840, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture(0.05, 0.04, 0.03, 0.96)

    local border = CreateFrame("Frame", nil, frame)
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    border:SetBackdropBorderColor(0.95, 0.75, 0.35, 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -18)
    title:SetText("WowNote Raid ID Tracker")

    local close = MakeButton(frame, "Close", 80, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -16)
    close:SetScript("OnClick", function() frame:Hide() end)

    local refresh = MakeButton(frame, "Refresh", 90, 24)
    refresh:SetPoint("RIGHT", close, "LEFT", -8, 0)
    refresh:SetScript("OnClick", function()
        if RequestRaidInfo then RequestRaidInfo() end
        RI.ScanCurrentCharacter()
    end)

    local postSelected = MakeButton(frame, "Post Selected", 105, 24)
    postSelected:SetPoint("RIGHT", refresh, "LEFT", -8, 0)
    postSelected:SetScript("OnClick", function() RI.PostSelected() end)

    local postMembers = MakeButton(frame, "Post Members", 105, 24)
    postMembers:SetPoint("RIGHT", postSelected, "LEFT", -8, 0)
    postMembers:SetScript("OnClick", function() RI.PostSelectedMembers() end)

    local clearMembers = MakeButton(frame, "Clear Members", 105, 24)
    clearMembers:SetPoint("RIGHT", postMembers, "LEFT", -8, 0)
    clearMembers:SetScript("OnClick", function() RI.ClearSelectedMembers() end)

    local postAll = MakeButton(frame, "Post All", 75, 24)
    postAll:SetPoint("RIGHT", clearMembers, "LEFT", -8, 0)
    postAll:SetScript("OnClick", function() RI.PostAll() end)

    frame.channelEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.channelEdit:SetSize(90, 22)
    frame.channelEdit:SetPoint("RIGHT", postAll, "LEFT", -10, 0)
    frame.channelEdit:SetAutoFocus(false)
    frame.channelEdit:SetText("/g")

    MakeTitle(frame, "Characters", 22, -58)
    MakeTitle(frame, "Saved Raid IDs", 240, -58)
    frame.selectedText = MakeSmall(frame, "Selected: none", 240, -82)

    frame.charButtons = {}
    for i = 1, 12 do
        local b = CreateCharButton(frame, i)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -82 - ((i - 1) * 24))
        frame.charButtons[i] = b
    end

    local headerRaid = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerRaid:SetPoint("TOPLEFT", frame, "TOPLEFT", 240, -112)
    headerRaid:SetText("Raid")

    local headerMode = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerMode:SetPoint("TOPLEFT", frame, "TOPLEFT", 500, -112)
    headerMode:SetText("Size/Mode")

    local headerId = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerId:SetPoint("TOPLEFT", frame, "TOPLEFT", 628, -112)
    headerId:SetText("ID")

    local headerRemaining = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerRemaining:SetPoint("TOPLEFT", frame, "TOPLEFT", 724, -112)
    headerRemaining:SetText("Remaining")

    frame.raidRows = {}
    for i = 1, 16 do
        local row = CreateRaidRow(frame, i)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 240, -136 - ((i - 1) * 22))
        frame.raidRows[i] = row
    end

    frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 244, -140)
    frame.emptyText:SetText("No saved raid IDs for this character.")

    frame.detailsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.detailsText:SetPoint("TOPLEFT", frame, "TOPLEFT", 240, -388)
    frame.detailsText:SetWidth(570)
    frame.detailsText:SetHeight(80)
    frame.detailsText:SetJustifyH("LEFT")
    frame.detailsText:SetJustifyV("TOP")
    frame.detailsText:SetText("Select a raid ID to see saved-with details.")

    frame.editBossButton = MakeButton(frame, "Edit Kills", 88, 20)
    frame.editBossButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 720, -386)
    frame.editBossButton:SetScript("OnClick", function()
        if not frame.bossEditor then return end
        frame.bossEditor:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
        frame.bossEditor:Show()
        frame.bossEditor:Raise()
        RefreshBossEditor()
    end)
    frame.editBossButton:Hide()

    frame.bossEditor = CreateFrame("Frame", nil, frame)
    frame.bossEditor:SetSize(640, 142)
    frame.bossEditor:SetPoint("CENTER", frame, "CENTER", 70, -80)
    frame.bossEditor:SetFrameStrata("FULLSCREEN_DIALOG")
    frame.bossEditor:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    frame.bossEditor:EnableMouse(true)
    frame.bossEditor:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame.bossEditor:SetBackdropColor(0.03, 0.02, 0.01, 0.98)
    frame.bossEditor:SetBackdropBorderColor(0.95, 0.75, 0.35, 1)
    frame.bossEditor:Hide()

    frame.bossEditor.title = frame.bossEditor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.bossEditor.title:SetPoint("TOPLEFT", frame.bossEditor, "TOPLEFT", 12, -10)
    frame.bossEditor.title:SetText("Edit killed bosses")

    local closeBossEditor = MakeButton(frame.bossEditor, "Done", 56, 18)
    closeBossEditor:SetPoint("TOPRIGHT", frame.bossEditor, "TOPRIGHT", -10, -8)
    closeBossEditor:SetScript("OnClick", function() frame.bossEditor:Hide() end)

    frame.bossEditor.buttons = {}
    for i = 1, 12 do
        local bossButton = CreateFrame("CheckButton", nil, frame.bossEditor, "UICheckButtonTemplate")
        bossButton:SetFrameLevel(frame.bossEditor:GetFrameLevel() + 2)
        bossButton:EnableMouse(true)
        bossButton:RegisterForClicks("LeftButtonUp")
        bossButton:SetSize(22, 22)
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        bossButton:SetPoint("TOPLEFT", frame.bossEditor, "TOPLEFT", 14 + (col * 205), -36 - (row * 24))
        bossButton.index = i
        bossButton.text = frame.bossEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bossButton.text:SetPoint("LEFT", bossButton, "RIGHT", 2, 0)
        bossButton.text:SetWidth(178)
        bossButton.text:SetJustifyH("LEFT")
        bossButton:SetScript("OnClick", function(self)
            if self.bossName then
                SetManualBossKill(GetSelectedLock(), self.bossName, self:GetChecked() and true or false)
                if statusText then
                    statusText:SetText(((self:GetChecked() and "Marked killed: ") or "Cleared kill: ") .. tostring(CanonicalBossName(self.bossName)))
                end
                RI.RefreshUI()
                RefreshBossEditor()
            end
        end)
        bossButton:Hide()
        bossButton.text:Hide()
        frame.bossEditor.buttons[i] = bossButton
    end

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 18)
    statusText:SetText("Raid IDs are stored account-wide for all characters using WowNote.")
end

function WowNote_OpenRaidIdTracker()
    CreateUI()
    if not selectedCharKey then
        selectedCharKey = GetPlayerKey()
    end
    RI.ScanCurrentCharacter()
    frame:Show()
    if WowNote_Internal and WowNote_Internal.RaiseFrame then
        WowNote_Internal.RaiseFrame(frame)
    else
        frame:SetFrameLevel(100)
    end
    RI.RefreshUI()
end

function WowNote_ScanRaidIds()
    RI.ScanCurrentCharacter()
end

SLASH_WOWNOTERAIDIDS1 = "/wnids"
SLASH_WOWNOTERAIDIDS2 = "/raidids"
SlashCmdList["WOWNOTERAIDIDS"] = function()
    WowNote_OpenRaidIdTracker()
end
