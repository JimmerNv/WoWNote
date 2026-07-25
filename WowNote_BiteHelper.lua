-- WowNote_BiteHelper.lua
-- Blood-Queen Lana'thel bite-order planning, synchronization, overlay and test mode.

local WNI = WowNote_Internal or {}
local MakeButton = WNI.MakeButton
local RaiseFrame = WNI.RaiseFrame

if not MakeButton then
    MakeButton = function(parent, text, width, height)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetWidth(width or 80)
        button:SetHeight(height or 22)
        button:SetText(text or "")
        return button
    end
end

local ADDON_PREFIX = "WowNote"
local FALLBACK_ADDON_PREFIX = "WNOTE"
local PROTOCOL_VERSION = "B2"
local FALLBACK_PROTOCOL_VERSION = "WN1"
local MESSAGE_KIND = "B"
local LEGACY_ADDON_PREFIX = "WNBITE"
local LEGACY_PROTOCOL_VERSION = "B1"
local CHAT_PROTOCOL_VERSION = "C3"
local LEGACY_CHAT_PROTOCOL_VERSION = "C2"
local MAX_CHAT_MESSAGE_LENGTH = 230
local MAX_CHUNK = 180
local MAX_TRANSFER_CHUNKS = 64
local MAX_BITE_ROWS = 10
local MAX_ASSIGNMENTS_PER_ROW = 40
local DEFAULT_TEST_NAMES = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }
local BITE_SPELL_IDS = { [70946] = true, [71726] = true, [71727] = true }
local ESSENCE_SPELL_IDS = { [70867] = true, [71531] = true, [71532] = true, [71533] = true }

local editorFrame
local overlayFrame
local dragGhost
local draggedName
local selectedRosterName
local receiveBuffers = {}
local chatReceiveBuffers = {}
local pendingChatTransferBySender = {}
local completedTransfers = {}
local acknowledgedTransfers = {}
local sendQueue = {}
local sendFrame
local secureRebuildPending = false
local lastAuraState = {}
local testDead = {}
local lastTestDeadName
local testDirection = 0
local runtimeRows
local overlayElapsed = 0
local chatSyncFiltersRegistered = false
local eventFrame
local overlayUpdateHandler
local backgroundMonitoringActive = false
local rosterMonitoringActive = false
local RefreshBackgroundMonitoring

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWoWNote Bite Helper:|r " .. tostring(msg))
    end
end

local function Debug(msg)
    if WowNote_IsCommDebugEnabled and WowNote_IsCommDebugEnabled() then
        Print("DEBUG " .. tostring(msg))
    end
end

local function Trim(value)
    value = tostring(value or "")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

local function NormalizeName(name)
    name = Trim(name)
    local localName = string.match(name, "^([^-]+)%-.+$")
    return localName or name
end

local VALID_ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function RowsNeedSanitize(rows)
    if type(rows) ~= "table" then return true end
    local rowIndex
    for rowIndex = 1, table.getn(rows) do
        local row = rows[rowIndex]
        if type(row) ~= "table" or type(row.assignments) ~= "table" then return true end
        local assignmentIndex
        for assignmentIndex = 1, table.getn(row.assignments) do
            if type(row.assignments[assignmentIndex]) ~= "table" then return true end
        end
    end
    return false
end

local function SanitizeRows(rows)
    local sanitized = {}
    if type(rows) ~= "table" then return sanitized end
    local rowIndex
    for rowIndex = 1, math.min(table.getn(rows), MAX_BITE_ROWS) do
        local sourceRow = rows[rowIndex]
        if type(sourceRow) == "table" then
            local row = { assignments = {} }
            local assignments = type(sourceRow.assignments) == "table" and sourceRow.assignments or {}
            local assignmentIndex
            for assignmentIndex = 1, math.min(table.getn(assignments), MAX_ASSIGNMENTS_PER_ROW) do
                local assignment = assignments[assignmentIndex]
                if type(assignment) == "table" then
                    table.insert(row.assignments, {
                        source = NormalizeName(assignment.source),
                        target = NormalizeName(assignment.target),
                        completed = assignment.completed == true,
                    })
                end
            end
            table.insert(sanitized, row)
        end
    end
    return sanitized
end

local function TestRosterNeedsSanitize(roster)
    if type(roster) ~= "table" or table.getn(roster) == 0 then return true end
    local seen = {}
    local i
    for i = 1, table.getn(roster) do
        local name = NormalizeName(roster[i])
        if name == "" or seen[name] then return true end
        seen[name] = true
    end
    return false
end

local function SanitizeTestRoster(roster)
    local result = {}
    local seen = {}
    if type(roster) == "table" then
        local i
        for i = 1, table.getn(roster) do
            local name = NormalizeName(roster[i])
            if name ~= "" and not seen[name] then
                seen[name] = true
                table.insert(result, name)
            end
        end
    end
    if table.getn(result) == 0 then
        local i
        for i = 1, table.getn(DEFAULT_TEST_NAMES) do table.insert(result, DEFAULT_TEST_NAMES[i]) end
    end
    return result
end

local function EnsureDB()
    if WNI.InitDB then WNI.InitDB() end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteDB.biteHelper) ~= "table" then WowNoteDB.biteHelper = {} end
    if type(WowNoteCharDB.biteHelper) ~= "table" then WowNoteCharDB.biteHelper = {} end

    local db = WowNoteDB.biteHelper
    local char = WowNoteCharDB.biteHelper
    if RowsNeedSanitize(db.rows) then db.rows = SanitizeRows(db.rows) end
    if RowsNeedSanitize(db.testRows) then db.testRows = SanitizeRows(db.testRows) end
    if TestRosterNeedsSanitize(db.testRoster) then db.testRoster = SanitizeTestRoster(db.testRoster) end
    db.testMode = db.testMode == true
    db.revision = tonumber(db.revision) or 0
    char.overlayVisible = char.overlayVisible == true
    if tonumber(char.overlayDragVersion or 0) < 2 then
        char.overlayLocked = false
        char.overlayDragVersion = 2
    elseif char.overlayLocked == nil then
        char.overlayLocked = false
    else
        char.overlayLocked = char.overlayLocked == true
    end
    if not VALID_ANCHOR_POINTS[char.overlayPoint] then char.overlayPoint = "CENTER" end
    if not VALID_ANCHOR_POINTS[char.overlayRelativePoint] then char.overlayRelativePoint = "CENTER" end
    char.overlayX = tonumber(char.overlayX) or 0
    char.overlayY = tonumber(char.overlayY) or 250
    return db, char
end

local function ActiveRows()
    local db = EnsureDB()
    if db.testMode then return db.testRows end
    return db.rows
end

local function DeepCopyRows(rows)
    local copy = {}
    if type(rows) ~= "table" then return copy end
    local rowIndex
    for rowIndex = 1, math.min(table.getn(rows), MAX_BITE_ROWS) do
        local sourceRow = rows[rowIndex]
        if type(sourceRow) == "table" then
            local row = { assignments = {} }
            local assignments = type(sourceRow.assignments) == "table" and sourceRow.assignments or {}
            local assignmentIndex
            for assignmentIndex = 1, math.min(table.getn(assignments), MAX_ASSIGNMENTS_PER_ROW) do
                local assignment = assignments[assignmentIndex]
                if type(assignment) == "table" then
                    table.insert(row.assignments, {
                        source = NormalizeName(assignment.source),
                        target = NormalizeName(assignment.target),
                        completed = assignment.completed == true,
                        skipped = assignment.skipped == true,
                    })
                end
            end
            table.insert(copy, row)
        end
    end
    return copy
end

local function GetPlayerName()
    return NormalizeName(UnitName and UnitName("player") or "")
end

local function SamePlayerName(left, right)
    return string.lower(NormalizeName(left)) == string.lower(NormalizeName(right))
end

local function IsLeaderOrAssistant(name)
    name = NormalizeName(name or GetPlayerName())
    if SamePlayerName(name, GetPlayerName()) then
        if IsRaidLeader and IsRaidLeader() then return true end
        if IsRaidOfficer and IsRaidOfficer() then return true end
    end
    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    local i
    for i = 1, count do
        local rosterName, rank = GetRaidRosterInfo(i)
        if SamePlayerName(rosterName, name) then
            return tonumber(rank or 0) >= 1
        end
    end
    return false
end

local function IsRaidActive()
    return (GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0) and true or false
end

local function CanEdit()
    local db = EnsureDB()
    if db.testMode == true then return true end
    -- Editing the local bite plan must always remain available. Posting/syncing
    -- to the raid is still protected inside PostOrder() by IsLeaderOrAssistant().
    return true
end

local function GetRoster()
    local db = EnsureDB()
    local result = {}
    local seen = {}
    if db.testMode then
        local i
        for i = 1, table.getn(db.testRoster) do
            local name = NormalizeName(db.testRoster[i])
            if name ~= "" and not seen[name] then
                seen[name] = true
                table.insert(result, name)
            end
        end
    else
        local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
        if raidCount > 0 then
            local i
            for i = 1, raidCount do
                local name = NormalizeName(GetRaidRosterInfo(i))
                if name ~= "" and not seen[name] then
                    seen[name] = true
                    table.insert(result, name)
                end
            end
        else
            local player = GetPlayerName()
            if player ~= "" then seen[player] = true; table.insert(result, player) end
            local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
            local i
            for i = 1, partyCount do
                local name = NormalizeName(UnitName("party" .. i))
                if name ~= "" and not seen[name] then seen[name] = true; table.insert(result, name) end
            end
        end
    end
    table.sort(result, function(a, b) return string.lower(a) < string.lower(b) end)
    return result
end

local function FindUnitByName(name)
    name = NormalizeName(name)
    if name == "" then return nil end
    if NormalizeName(UnitName and UnitName("player") or "") == name then return "player" end
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    local i
    for i = 1, raidCount do
        local unit = "raid" .. i
        if NormalizeName(UnitName(unit)) == name then return unit end
    end
    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i = 1, partyCount do
        local unit = "party" .. i
        if NormalizeName(UnitName(unit)) == name then return unit end
    end
    return nil
end

local function IsNameDead(name)
    local db = EnsureDB()
    if db.testMode then return testDead[NormalizeName(name)] == true end
    local unit = FindUnitByName(name)
    return unit and UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false
end

local function HasEssence(name)
    local db = EnsureDB()
    if db.testMode then return false end
    local unit = FindUnitByName(name)
    if not unit or not UnitBuff then return false end
    local index
    for index = 1, 40 do
        local auraName, _, _, _, _, _, _, _, _, _, spellId = UnitBuff(unit, index)
        if not auraName then break end
        if ESSENCE_SPELL_IDS[tonumber(spellId or 0)] or string.find(string.lower(auraName), "essence of the blood", 1, true) then
            return true
        end
    end
    return false
end

local function BuildAuraBaseline()
    lastAuraState = {}
    local roster = GetRoster()
    local i
    for i = 1, table.getn(roster) do lastAuraState[roster[i]] = HasEssence(roster[i]) end
end

local function IsBiteModuleEnabled()
    return not WowNote_IsModuleEnabled or WowNote_IsModuleEnabled("biteHelper")
end

local function IsBiteHudActive()
    if not IsBiteModuleEnabled() or not overlayFrame or not overlayFrame.IsShown or not overlayFrame:IsShown() then return false end
    local _, char = EnsureDB()
    return char.overlayVisible == true
end

local function SetEventRegistration(frame, eventName, enabled)
    if not frame then return end
    if enabled then
        frame:RegisterEvent(eventName)
    else
        frame:UnregisterEvent(eventName)
    end
end

RefreshBackgroundMonitoring = function()
    local hudActive = IsBiteHudActive()
    local editorActive = editorFrame and editorFrame.IsShown and editorFrame:IsShown() or false
    local rosterNeeded = hudActive or editorActive
    local becameActive = hudActive and not backgroundMonitoringActive

    backgroundMonitoringActive = hudActive
    rosterMonitoringActive = rosterNeeded

    if overlayFrame and overlayFrame.SetScript then
        WowNoteProfiler_SetScript(overlayFrame, "OnUpdate", "BiteHelper.HUD", hudActive and overlayUpdateHandler or nil)
    end
    if not hudActive then overlayElapsed = 0 end

    if eventFrame then
        SetEventRegistration(eventFrame, "COMBAT_LOG_EVENT_UNFILTERED", hudActive)
        SetEventRegistration(eventFrame, "UNIT_AURA", hudActive)
        SetEventRegistration(eventFrame, "RAID_ROSTER_UPDATE", rosterNeeded)
        SetEventRegistration(eventFrame, "PARTY_MEMBERS_CHANGED", rosterNeeded)
    end

    if becameActive then BuildAuraBaseline() end
end

local function EnsureFirstRow(rows)
    if table.getn(rows) == 0 then
        table.insert(rows, { assignments = { { source = "", target = "", completed = false } } })
    elseif type(rows[1].assignments) ~= "table" or table.getn(rows[1].assignments) == 0 then
        rows[1].assignments = { { source = "", target = "", completed = false } }
    end
end

local function CollectParticipants(rows, throughRow)
    local result = {}
    local seen = {}
    local last = throughRow or table.getn(rows or {})
    local rowIndex
    for rowIndex = 1, math.min(last, table.getn(rows or {})) do
        local row = rows[rowIndex]
        local assignmentIndex
        for assignmentIndex = 1, table.getn(row.assignments or {}) do
            local assignment = row.assignments[assignmentIndex]
            local source = NormalizeName(assignment.source)
            local target = NormalizeName(assignment.target)
            if source ~= "" and not seen[source] then seen[source] = true; table.insert(result, source) end
            if target ~= "" and not seen[target] then seen[target] = true; table.insert(result, target) end
        end
    end
    return result
end

local function RebuildFollowingRows(startRow)
    local rows = ActiveRows()
    local rowIndex
    for rowIndex = math.max(2, startRow or 2), table.getn(rows) do
        local oldTargets = {}
        local oldAssignments = rows[rowIndex].assignments or {}
        local i
        for i = 1, table.getn(oldAssignments) do oldTargets[NormalizeName(oldAssignments[i].source)] = NormalizeName(oldAssignments[i].target) end
        local participants = CollectParticipants(rows, rowIndex - 1)
        local rebuilt = {}
        for i = 1, table.getn(participants) do
            local source = participants[i]
            table.insert(rebuilt, { source = source, target = oldTargets[source] or "", completed = false })
        end
        rows[rowIndex].assignments = rebuilt
    end
end

local function AddRow()
    if not CanEdit() then Print("Bite order editing is not available right now."); return end
    local rows = ActiveRows()
    EnsureFirstRow(rows)
    local first = rows[1].assignments[1]
    if table.getn(rows) == 1 and NormalizeName(first.source) == "" and NormalizeName(first.target) == "" then
        Print("Assign Bite 1 first.")
        return
    end
    local participants = CollectParticipants(rows)
    if table.getn(participants) == 0 then Print("Assign at least one Bite 1 pair first."); return end
    local row = { assignments = {} }
    local i
    for i = 1, table.getn(participants) do table.insert(row.assignments, { source = participants[i], target = "", completed = false }) end
    table.insert(rows, row)
end



local function CurrentActiveRow(rows)
    local rowIndex
    for rowIndex = 1, table.getn(rows or {}) do
        local hasAssignment = false
        local allComplete = true
        local row = rows[rowIndex]
        local assignmentIndex
        for assignmentIndex = 1, table.getn(row.assignments or {}) do
            local assignment = row.assignments[assignmentIndex]
            if NormalizeName(assignment.source) ~= "" and NormalizeName(assignment.target) ~= "" then
                hasAssignment = true
                if not assignment.completed then allComplete = false end
            end
        end
        if hasAssignment and not allComplete then return rowIndex end
    end
    return nil
end

local function SkipDeadActiveTargets(rows)
    local changed = false
    local guard = 0
    while guard < MAX_BITE_ROWS do
        guard = guard + 1
        local activeRow = CurrentActiveRow(rows)
        if not activeRow then break end
        local row = rows[activeRow]
        local rowChanged = false
        local assignmentIndex
        for assignmentIndex = 1, table.getn(row.assignments or {}) do
            local assignment = row.assignments[assignmentIndex]
            local target = NormalizeName(assignment.target)
            if not assignment.completed and target ~= "" and IsNameDead(target) then
                assignment.completed = true
                assignment.skipped = true
                rowChanged = true
                changed = true
                Print("Bite " .. activeRow .. " skipped: " .. NormalizeName(assignment.source) .. " > " .. target .. " (target dead)")
            end
        end
        if not rowChanged then break end
    end
    return changed
end

local function ResetProgress(rows)
    local rowIndex
    for rowIndex = 1, table.getn(rows or {}) do
        local assignmentIndex
        for assignmentIndex = 1, table.getn(rows[rowIndex].assignments or {}) do
            rows[rowIndex].assignments[assignmentIndex].completed = false
            rows[rowIndex].assignments[assignmentIndex].skipped = nil
        end
    end
    if IsBiteHudActive() then BuildAuraBaseline() else lastAuraState = {} end
end

local function MarkBiteCompleted(sourceName, targetName, reason)
    sourceName = NormalizeName(sourceName)
    targetName = NormalizeName(targetName)
    local rows = runtimeRows or ActiveRows()
    local rowIndex
    for rowIndex = 1, table.getn(rows or {}) do
        local row = rows[rowIndex]
        local assignmentIndex
        for assignmentIndex = 1, table.getn(row.assignments or {}) do
            local assignment = row.assignments[assignmentIndex]
            if not assignment.completed and NormalizeName(assignment.source) == sourceName and NormalizeName(assignment.target) == targetName then
                assignment.completed = true
                Print("Bite " .. rowIndex .. " completed: " .. sourceName .. " > " .. targetName .. (reason and (" (" .. reason .. ")") or ""))
                return true
            end
        end
    end
    return false
end

local function MarkTargetAuraGain(targetName)
    targetName = NormalizeName(targetName)
    local rows = runtimeRows or ActiveRows()
    local activeRow = CurrentActiveRow(rows)
    if not activeRow then return false end
    local row = rows[activeRow]
    local i
    for i = 1, table.getn(row.assignments or {}) do
        local assignment = row.assignments[i]
        if not assignment.completed and NormalizeName(assignment.target) == targetName then
            assignment.completed = true
            Print("Bite " .. activeRow .. " completed from aura: " .. NormalizeName(assignment.source) .. " > " .. targetName)
            return true
        end
    end
    return false
end

local function Escape(value)
    value = tostring(value or "")
    value = string.gsub(value, "%%", "%%25")
    value = string.gsub(value, "|", "%%7C")
    value = string.gsub(value, ";", "%%3B")
    value = string.gsub(value, ",", "%%2C")
    value = string.gsub(value, ">", "%%3E")
    return value
end

local function Unescape(value)
    value = tostring(value or "")
    value = string.gsub(value, "%%7C", "|")
    value = string.gsub(value, "%%3B", ";")
    value = string.gsub(value, "%%2C", ",")
    value = string.gsub(value, "%%3E", ">")
    value = string.gsub(value, "%%25", "%%")
    return value
end

local function Split(text, separator)
    local result = {}
    text = tostring(text or "")
    if text == "" then return result end
    local start = 1
    while true do
        local pos = string.find(text, separator, start, true)
        if not pos then table.insert(result, string.sub(text, start)); break end
        table.insert(result, string.sub(text, start, pos - 1))
        start = pos + string.len(separator)
    end
    return result
end

local function SerializeRows(rows)
    local rowParts = {}
    local rowIndex
    for rowIndex = 1, table.getn(rows or {}) do
        local assignmentParts = {}
        local row = rows[rowIndex]
        local assignmentIndex
        for assignmentIndex = 1, table.getn(row.assignments or {}) do
            local assignment = row.assignments[assignmentIndex]
            table.insert(assignmentParts, Escape(NormalizeName(assignment.source)) .. ">" .. Escape(NormalizeName(assignment.target)))
        end
        table.insert(rowParts, table.concat(assignmentParts, ","))
    end
    return table.concat(rowParts, ";")
end

local function DeserializeRows(payload)
    local rows = {}
    local rowParts = Split(payload, ";")
    local rowIndex
    for rowIndex = 1, table.getn(rowParts) do
        local row = { assignments = {} }
        local assignmentParts = Split(rowParts[rowIndex], ",")
        local assignmentIndex
        for assignmentIndex = 1, table.getn(assignmentParts) do
            local pair = assignmentParts[assignmentIndex]
            local pos = string.find(pair, ">", 1, true)
            if pos then
                table.insert(row.assignments, {
                    source = NormalizeName(Unescape(string.sub(pair, 1, pos - 1))),
                    target = NormalizeName(Unescape(string.sub(pair, pos + 1))),
                    completed = false,
                })
            end
        end
        if table.getn(row.assignments) > 0 then table.insert(rows, row) end
    end
    return rows
end

local function BuildTransferId()
    return tostring(time and time() or 0) .. tostring(math.random and math.random(1000, 9999) or 1000)
end

local function ValidateRows(rows)
    if type(rows) ~= "table" or table.getn(rows) == 0 then return false, "No bite rows exist." end
    if table.getn(rows) > MAX_BITE_ROWS then return false, "Too many bite rows." end
    local rowIndex
    for rowIndex = 1, table.getn(rows) do
        local row = rows[rowIndex]
        if type(row) ~= "table" or type(row.assignments) ~= "table" or table.getn(row.assignments) == 0 then
            return false, "Bite " .. rowIndex .. " is empty."
        end
        if table.getn(row.assignments) > MAX_ASSIGNMENTS_PER_ROW then return false, "Bite " .. rowIndex .. " has too many assignments." end
        local usedTargets = {}
        local assignmentIndex
        for assignmentIndex = 1, table.getn(row.assignments) do
            local assignment = row.assignments[assignmentIndex]
            if type(assignment) ~= "table" then return false, "Bite " .. rowIndex .. " contains invalid data." end
            local source = NormalizeName(assignment.source)
            local target = NormalizeName(assignment.target)
            if source == "" or target == "" then return false, "Bite " .. rowIndex .. " contains an incomplete assignment." end
            if source == target then return false, source .. " cannot bite themselves." end
            if usedTargets[target] then return false, target .. " is assigned twice in Bite " .. rowIndex .. "." end
            usedTargets[target] = true
        end
    end
    return true
end

local function FormatOrderLines(rows, transferId)
    local formattedRows = {}
    local requiresChunkProtocol = false
    local rowIndex
    for rowIndex = 1, table.getn(rows or {}) do
        local entries = {}
        local row = rows[rowIndex]
        local assignmentIndex
        for assignmentIndex = 1, table.getn(row.assignments or {}) do
            local assignment = row.assignments[assignmentIndex]
            local source = NormalizeName(assignment.source)
            local target = NormalizeName(assignment.target)
            if source ~= "" and target ~= "" then table.insert(entries, source .. " > " .. target) end
        end

        if table.getn(entries) > 0 then
            local chunks = {}
            local current = {}
            local reservedPrefixLength = string.len("WN: Bite " .. rowIndex .. " [99/99]: ")
            local entryIndex
            for entryIndex = 1, table.getn(entries) do
                local entry = entries[entryIndex]
                local candidateLength = reservedPrefixLength + string.len(table.concat(current, ", "))
                if table.getn(current) > 0 then candidateLength = candidateLength + 2 end
                candidateLength = candidateLength + string.len(entry)
                if candidateLength > MAX_CHAT_MESSAGE_LENGTH and table.getn(current) > 0 then
                    table.insert(chunks, table.concat(current, ", "))
                    current = { entry }
                else
                    table.insert(current, entry)
                end
            end
            if table.getn(current) > 0 then table.insert(chunks, table.concat(current, ", ")) end
            if table.getn(chunks) > 1 then requiresChunkProtocol = true end
            formattedRows[rowIndex] = chunks
        end
    end

    -- Keep the C2 wire format for normal orders so older WowNote versions can
    -- still receive them. C3 is only required when a row must be split.
    local protocolVersion = requiresChunkProtocol and CHAT_PROTOCOL_VERSION or LEGACY_CHAT_PROTOCOL_VERSION
    local lines = {
        "WoWNote Bite Helper: Bite Order [" .. protocolVersion .. ":"
            .. tostring(transferId or "") .. ":" .. tostring(table.getn(rows or {})) .. "]"
    }

    for rowIndex = 1, table.getn(rows or {}) do
        local chunks = formattedRows[rowIndex] or {}
        if protocolVersion == LEGACY_CHAT_PROTOCOL_VERSION then
            if chunks[1] then table.insert(lines, "WN: Bite " .. rowIndex .. ": " .. chunks[1]) end
        else
            local chunkCount = table.getn(chunks)
            local chunkIndex
            for chunkIndex = 1, chunkCount do
                table.insert(lines, "WN: Bite " .. rowIndex .. " [" .. chunkIndex .. "/" .. chunkCount .. "]: " .. chunks[chunkIndex])
            end
        end
    end
    return lines
end

local function RegisterCommPrefixes()
    if not RegisterAddonMessagePrefix then
        Debug("RegisterAddonMessagePrefix is unavailable.")
        return
    end
    local okPrimary, primaryResult = pcall(RegisterAddonMessagePrefix, ADDON_PREFIX)
    local okFallback, fallbackResult = pcall(RegisterAddonMessagePrefix, FALLBACK_ADDON_PREFIX)
    local okLegacy, legacyResult = pcall(RegisterAddonMessagePrefix, LEGACY_ADDON_PREFIX)
    Debug("prefix registration " .. ADDON_PREFIX .. "=" .. tostring(okPrimary and primaryResult ~= false)
        .. ", " .. FALLBACK_ADDON_PREFIX .. "=" .. tostring(okFallback and fallbackResult ~= false)
        .. ", " .. LEGACY_ADDON_PREFIX .. "=" .. tostring(okLegacy and legacyResult ~= false))
end

local function EnsureSendFrame()
    if sendFrame then return end
    sendFrame = CreateFrame("Frame")
    sendFrame:Hide()
    sendFrame.elapsed = 0
    WowNoteProfiler_SetScript(sendFrame, "OnUpdate", "BiteHelper.SendQueue", function(self, elapsed)
        self.elapsed = self.elapsed + (elapsed or 0)
        if self.elapsed < 0.06 then return end
        self.elapsed = 0
        local packet = table.remove(sendQueue, 1)
        if not packet then self:Hide(); return end
        local ok, result = pcall(SendAddonMessage, packet.prefix, packet.message, packet.channel, packet.target)
        local sent = ok and result ~= false
        if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("out", tostring(packet.prefix or "?") .. " " .. tostring(packet.channel or "?"), string.len(tostring(packet.message or "")), sent) end
        if WowNoteProfiler_SetGauge then WowNoteProfiler_SetGauge("BiteHelper.SendQueueDepth", table.getn(sendQueue)) end
        Debug("send " .. tostring(packet.prefix) .. " " .. tostring(packet.channel)
            .. " packet " .. tostring(packet.seq) .. "/" .. tostring(packet.total)
            .. " id=" .. tostring(packet.id) .. " result=" .. tostring(sent))
        if not sent then
            Print("Could not send Bite Order packet " .. tostring(packet.seq) .. "/" .. tostring(packet.total)
                .. " via " .. tostring(packet.prefix) .. ".")
        end
        if table.getn(sendQueue) == 0 then self:Hide() end
    end)
end

local function QueueAddonPacket(prefix, message, channel, target, id, seq, total)
    table.insert(sendQueue, {
        prefix = prefix,
        message = message,
        channel = channel,
        target = target,
        id = id,
        seq = seq,
        total = total,
    })
    if WowNoteProfiler_SetGauge then WowNoteProfiler_SetGauge("BiteHelper.SendQueueDepth", table.getn(sendQueue)) end
end

local function GetSyncRecipients()
    local recipients = {}
    local player = GetPlayerName()
    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    local i
    for i = 1, count do
        local name = NormalizeName(GetRaidRosterInfo(i))
        if name ~= "" and not SamePlayerName(name, player) then
            table.insert(recipients, name)
        end
    end
    return recipients
end

local function SendOrderSync(rows, transferId)
    if not SendAddonMessage then Print("Addon communication is unavailable; raid-chat fallback remains active."); return false end
    RegisterCommPrefixes()
    EnsureSendFrame()
    local payload = SerializeRows(rows)
    local id = tostring(transferId or BuildTransferId())
    local total = math.max(1, math.ceil(string.len(payload) / MAX_CHUNK))
    if total > MAX_TRANSFER_CHUNKS then
        Print("Bite order is too large to synchronize.")
        return false
    end
    local recipients = GetSyncRecipients()
    local index
    for index = 1, total do
        local chunk = string.sub(payload, ((index - 1) * MAX_CHUNK) + 1, index * MAX_CHUNK)
        local primaryMessage = "BITE|" .. PROTOCOL_VERSION .. "|" .. id .. "|" .. index .. "|" .. total .. "|" .. chunk
        local fallbackMessage = FALLBACK_PROTOCOL_VERSION .. "|" .. MESSAGE_KIND .. "|" .. id .. "|" .. index .. "|" .. total .. "|" .. chunk

        -- Keep the efficient raid broadcasts for clients/servers that deliver addon RAID traffic.
        QueueAddonPacket(ADDON_PREFIX, primaryMessage, "RAID", nil, id, index, total)
        QueueAddonPacket(FALLBACK_ADDON_PREFIX, fallbackMessage, "RAID", nil, id, index, total)

        -- Warmane can acknowledge SendAddonMessage while dropping RAID addon traffic.
        -- Direct WNOTE whispers use WowNote's established communication prefix and
        -- independently reach every raid member without relying on the RAID route.
        local recipientIndex
        for recipientIndex = 1, table.getn(recipients) do
            QueueAddonPacket(FALLBACK_ADDON_PREFIX, fallbackMessage, "WHISPER", recipients[recipientIndex], id, index, total)
        end
    end
    Debug("queued Bite Order id=" .. id .. " packets=" .. total .. " raidRoutes=2 directWhispers="
        .. tostring(table.getn(recipients)) .. " payload=" .. string.len(payload))
    sendFrame:Show()
    return true
end

local function ApplyRuntimeOrder(rows)
    runtimeRows = DeepCopyRows(rows)
    ResetProgress(runtimeRows)
    secureRebuildPending = true
end

local function PostOrder()
    local db = EnsureDB()
    local rows = ActiveRows()
    local valid, message = ValidateRows(rows)
    if not valid then Print(message); return end
    if db.testMode then
        ApplyRuntimeOrder(rows)
        Print("Local test order applied. No raid message was sent.")
        return
    end
    if not IsLeaderOrAssistant() then Print("Only raid leaders or assistants can post the bite order."); return end
    if not SendChatMessage then Print("Raid chat is unavailable."); return end
    local transferId = BuildTransferId()
    local lines = FormatOrderLines(rows, transferId)
    local i
    for i = 1, table.getn(lines) do
        local ok, result = pcall(SendChatMessage, lines[i], "RAID")
        if not ok or result == false then
            Print("Could not post the bite order to raid chat: " .. tostring(ok and "message rejected" or result or "unknown error"))
            return false
        end
    end
    local synchronized = SendOrderSync(rows, transferId)
    ApplyRuntimeOrder(rows)
    if synchronized then
        Print("Bite order posted; addon packets and raid-chat fallback sent.")
    else
        Print("Bite order posted; raid-chat fallback sent.")
    end
end

local function SendSyncAck(sender, transferId)
    sender = NormalizeName(sender)
    if sender == "" or not SendAddonMessage then return end
    local primaryMessage = "BITEACK|" .. PROTOCOL_VERSION .. "|" .. tostring(transferId or "")
    local fallbackMessage = FALLBACK_PROTOCOL_VERSION .. "|BA|" .. tostring(transferId or "")
    local okPrimary, primaryResult = pcall(SendAddonMessage, ADDON_PREFIX, primaryMessage, "WHISPER", sender)
    local okFallback, fallbackResult = pcall(SendAddonMessage, FALLBACK_ADDON_PREFIX, fallbackMessage, "WHISPER", sender)
    Debug("send ACK to " .. sender .. " id=" .. tostring(transferId)
        .. " primary=" .. tostring(okPrimary and primaryResult ~= false)
        .. " fallback=" .. tostring(okFallback and fallbackResult ~= false))
end

local function ReceiveOrder(rows, sender, transferId)
    local db, char = EnsureDB()
    db.rows = DeepCopyRows(rows)
    db.revision = (tonumber(db.revision) or 0) + 1
    ApplyRuntimeOrder(rows)
    char.overlayVisible = true
    if WowNote_OpenBiteHelper then
        WowNote_OpenBiteHelper(false)
    elseif WowNote_BiteHelper_RefreshOverlay then
        WowNote_BiteHelper_RefreshOverlay()
    end
    SendSyncAck(sender, transferId)
    Print("Bite order received from " .. NormalizeName(sender) .. ".")
end

local function ParseSyncMessage(prefix, message)
    if prefix == ADDON_PREFIX then
        local marker, version, id, seq, total, chunk = string.match(message, "^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
        if marker == "BITE" and version == PROTOCOL_VERSION then
            return id, seq, total, chunk
        end
        local ackMarker, ackVersion, ackId = string.match(message, "^([^|]+)|([^|]+)|([^|]+)$")
        if ackMarker == "BITEACK" and ackVersion == PROTOCOL_VERSION then
            return nil, nil, nil, nil, ackId
        end
    elseif prefix == FALLBACK_ADDON_PREFIX then
        local ackVersion, ackKind, ackId = string.match(message, "^([^|]+)|([^|]+)|([^|]+)$")
        if ackVersion == FALLBACK_PROTOCOL_VERSION and ackKind == "BA" then
            return nil, nil, nil, nil, ackId
        end
        local version, kind, id, seq, total, chunk = string.match(message, "^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
        if version == FALLBACK_PROTOCOL_VERSION and kind == MESSAGE_KIND then
            return id, seq, total, chunk
        end
    elseif prefix == LEGACY_ADDON_PREFIX then
        local version, kind, id, seq, total, chunk = string.match(message, "^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
        if version == LEGACY_PROTOCOL_VERSION and kind == "ORDER" then
            return id, seq, total, chunk
        end
    end
    return nil
end

local function HandleAddonMessage(prefix, message, channel, sender)
    if type(message) ~= "string" then return end
    if prefix ~= ADDON_PREFIX and prefix ~= FALLBACK_ADDON_PREFIX and prefix ~= LEGACY_ADDON_PREFIX then return end
    if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("in", tostring(prefix or "?") .. " " .. tostring(channel or "?"), string.len(message), true) end
    Debug("recv prefix=" .. tostring(prefix) .. " channel=" .. tostring(channel)
        .. " sender=" .. tostring(sender) .. " bytes=" .. tostring(string.len(message)))

    local id, seq, total, chunk, ackId = ParseSyncMessage(prefix, message)
    if ackId then
        local ackSender = NormalizeName(sender)
        local ackKey = string.lower(ackSender) .. ":" .. tostring(ackId)
        if acknowledgedTransfers[ackKey] then
            Debug("ignored duplicate ACK " .. ackKey)
            return
        end
        acknowledgedTransfers[ackKey] = GetTime and GetTime() or 1
        Print("Bite order acknowledged by " .. ackSender .. ".")
        Debug("ACK id=" .. tostring(ackId) .. " sender=" .. tostring(sender))
        return
    end
    if not id then
        Debug("ignored unrecognized Bite Helper payload on prefix " .. tostring(prefix))
        return
    end

    sender = NormalizeName(sender)
    if sender == "" then Debug("ignored packet without sender"); return end
    if not IsLeaderOrAssistant(sender) then
        Debug("ignored packet from non-lead/non-assist sender " .. sender)
        return
    end
    seq = tonumber(seq); total = tonumber(total)
    if not seq or not total or seq < 1 or total < 1 or total > MAX_TRANSFER_CHUNKS or seq > total or id == "" then
        Debug("ignored invalid packet metadata id=" .. tostring(id) .. " seq=" .. tostring(seq) .. " total=" .. tostring(total))
        return
    end

    local key = string.lower(sender) .. ":" .. id
    if completedTransfers[key] then
        Debug("ignored duplicate completed transfer " .. key)
        return
    end
    if type(receiveBuffers[key]) ~= "table" or receiveBuffers[key].total ~= total then
        receiveBuffers[key] = { total = total, count = 0, chunks = {}, started = GetTime and GetTime() or 0 }
    end
    local buffer = receiveBuffers[key]
    if not buffer.chunks[seq] then
        buffer.chunks[seq] = chunk or ""
        buffer.count = buffer.count + 1
    end
    Debug("receive " .. key .. " packet " .. seq .. "/" .. total .. " count=" .. buffer.count)
    if buffer.count >= buffer.total then
        local parts = {}
        local i
        for i = 1, buffer.total do
            if buffer.chunks[i] == nil then
                Debug("transfer " .. key .. " still missing packet " .. i)
                return
            end
            table.insert(parts, buffer.chunks[i])
        end
        receiveBuffers[key] = nil
        local rows = DeserializeRows(table.concat(parts, ""))
        local valid, reason = ValidateRows(rows)
        if valid then
            completedTransfers[key] = GetTime and GetTime() or 1
            ReceiveOrder(rows, sender, id)
            Debug("applied transfer " .. key)
        else
            Print("Rejected invalid Bite Order from " .. sender .. ": " .. tostring(reason or "invalid data"))
            Debug("rejected transfer " .. key .. " reason=" .. tostring(reason))
        end
    end
end

local function ParseChatAssignmentRow(message)
    message = tostring(message or "")
    local rowIndexText, partIndexText, partCountText, entriesText = string.match(message,
        "^WN: Bite (%d+) %[(%d+)/(%d+)%]: (.+)$")
    if not rowIndexText then
        rowIndexText, entriesText = string.match(message, "^WN: Bite (%d+): (.+)$")
        partIndexText, partCountText = "1", "1"
    end

    local rowIndex = tonumber(rowIndexText)
    local partIndex = tonumber(partIndexText)
    local partCount = tonumber(partCountText)
    if not rowIndex or rowIndex < 1 or rowIndex > MAX_BITE_ROWS then return nil end
    if not partIndex or not partCount or partIndex < 1 or partCount < 1 or partIndex > partCount
        or partCount > MAX_ASSIGNMENTS_PER_ROW then return nil end

    local row = { assignments = {} }
    local entries = Split(entriesText, ", ")
    local i
    for i = 1, table.getn(entries) do
        local source, target = string.match(entries[i], "^%s*(.-)%s+>%s+(.-)%s*$")
        source = NormalizeName(source)
        target = NormalizeName(target)
        if source == "" or target == "" then return nil end
        table.insert(row.assignments, { source = source, target = target, completed = false })
    end
    if table.getn(row.assignments) == 0 then return nil end
    return rowIndex, row, partIndex, partCount
end

local function FinishChatTransfer(key, sender)
    local buffer = chatReceiveBuffers[key]
    if type(buffer) ~= "table" or buffer.count < buffer.total then return end
    local rows = {}
    local i
    for i = 1, buffer.total do
        if type(buffer.rows[i]) ~= "table" then return end
        table.insert(rows, buffer.rows[i])
    end

    chatReceiveBuffers[key] = nil
    pendingChatTransferBySender[string.lower(sender)] = nil
    if completedTransfers[key] then
        Debug("chat fallback ignored already completed transfer " .. key)
        return
    end

    local valid, reason = ValidateRows(rows)
    if not valid then
        Debug("rejected raid-chat transfer " .. key .. " reason=" .. tostring(reason))
        return
    end

    completedTransfers[key] = GetTime and GetTime() or 1
    ReceiveOrder(rows, sender, buffer.id)
    Debug("applied raid-chat fallback transfer " .. key)
end

local function HandleChatSyncMessage(message, sender, eventName)
    if type(message) ~= "string" then return end
    sender = NormalizeName(sender)
    if sender == "" or SamePlayerName(sender, GetPlayerName()) then return end

    local version, transferId, totalText = string.match(message,
        "^WoWNote Bite Helper: Bite Order %[(C%d+):([^:]+):(%d+)%]$")
    if version then
        local total = tonumber(totalText)
        if (version ~= CHAT_PROTOCOL_VERSION and version ~= LEGACY_CHAT_PROTOCOL_VERSION)
            or not total or total < 1 or total > MAX_BITE_ROWS then
            Debug("ignored invalid raid-chat Bite Order header from " .. sender)
            return
        end
        if eventName ~= "CHAT_MSG_RAID_LEADER" and not IsLeaderOrAssistant(sender) then
            Debug("ignored raid-chat Bite Order header from non-lead/non-assist " .. sender)
            return
        end
        local key = string.lower(sender) .. ":" .. transferId
        local existing = chatReceiveBuffers[key]
        if type(existing) ~= "table" or existing.total ~= total then
            chatReceiveBuffers[key] = {
                id = transferId,
                total = total,
                count = 0,
                rows = {},
                rowParts = {},
                started = GetTime and GetTime() or 0,
            }
        end
        pendingChatTransferBySender[string.lower(sender)] = key
        Debug("raid-chat fallback header " .. key .. " rows=" .. total .. " event=" .. tostring(eventName))
        return
    end

    local rowIndex, row, partIndex, partCount = ParseChatAssignmentRow(message)
    if not rowIndex then return end
    if eventName ~= "CHAT_MSG_RAID_LEADER" and not IsLeaderOrAssistant(sender) then
        Debug("ignored raid-chat Bite row from non-lead/non-assist " .. sender)
        return
    end

    local senderKey = string.lower(sender)
    local key = pendingChatTransferBySender[senderKey]
    local buffer = key and chatReceiveBuffers[key] or nil
    if type(buffer) ~= "table" then
        Debug("ignored raid-chat Bite row without matching header from " .. sender)
        return
    end
    if rowIndex > buffer.total then
        Debug("ignored raid-chat Bite row " .. rowIndex .. " beyond expected " .. buffer.total)
        return
    end

    buffer.rowParts = buffer.rowParts or {}
    local partState = buffer.rowParts[rowIndex]
    if type(partState) ~= "table" then
        partState = { total = partCount, count = 0, parts = {} }
        buffer.rowParts[rowIndex] = partState
    elseif partState.total ~= partCount then
        Debug("ignored raid-chat Bite row " .. rowIndex .. " with inconsistent part count")
        return
    end

    if partState.parts[partIndex] then
        Debug("ignored duplicate raid-chat Bite row " .. rowIndex .. " part " .. partIndex)
        return
    end
    partState.parts[partIndex] = row
    partState.count = partState.count + 1
    if partState.count < partState.total then
        Debug("raid-chat fallback receive " .. key .. " row " .. rowIndex .. " part "
            .. partIndex .. "/" .. partCount)
        return
    end

    local combined = { assignments = {} }
    local currentPart
    for currentPart = 1, partState.total do
        local partRow = partState.parts[currentPart]
        if type(partRow) ~= "table" then return end
        local assignmentIndex
        for assignmentIndex = 1, table.getn(partRow.assignments or {}) do
            table.insert(combined.assignments, partRow.assignments[assignmentIndex])
        end
    end
    if table.getn(combined.assignments) > MAX_ASSIGNMENTS_PER_ROW then
        Debug("ignored raid-chat Bite row " .. rowIndex .. " with too many combined assignments")
        return
    end

    if not buffer.rows[rowIndex] then buffer.count = buffer.count + 1 end
    buffer.rows[rowIndex] = combined
    Debug("raid-chat fallback receive " .. key .. " row " .. rowIndex .. "/" .. buffer.total
        .. " parts=" .. partCount .. " count=" .. buffer.count)
    FinishChatTransfer(key, sender)
end

local function RegisterChatSyncFilters()
    if chatSyncFiltersRegistered or not ChatFrame_AddMessageEventFilter then return end

    local function ChatSyncFilter(self, eventName, message, sender, ...)
        -- This hook is an intentional second receive path. Some 3.3.5a private-server
        -- clients display raid chat while addon event callbacks do not reach every frame.
        -- Returning false keeps the visible raid order unchanged.
        HandleChatSyncMessage(message, sender, eventName)
        return false
    end

    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", ChatSyncFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", ChatSyncFilter)
    chatSyncFiltersRegistered = true
    Debug("raid-chat synchronization filters registered")
end

local function RotateTexture(texture, angle)
    if not texture or not texture.SetTexCoord then return end
    local c = math.cos(angle or 0)
    local s = math.sin(angle or 0)
    local function point(x, y)
        local dx = x - 0.5
        local dy = y - 0.5
        return 0.5 + (dx * c - dy * s), 0.5 + (dx * s + dy * c)
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

local function GetDirectionToName(name)
    local db = EnsureDB()
    if db.testMode then return NormalizeAngle(testDirection), true end
    local unit = FindUnitByName(name)
    if not unit or not GetPlayerMapPosition then return nil, false end
    local px, py = GetPlayerMapPosition("player")
    local tx, ty = GetPlayerMapPosition(unit)
    if not px or not py or not tx or not ty or (px == 0 and py == 0) or (tx == 0 and ty == 0) then
        if SetMapToCurrentZone then pcall(SetMapToCurrentZone) end
        px, py = GetPlayerMapPosition("player")
        tx, ty = GetPlayerMapPosition(unit)
    end
    if not px or not py or not tx or not ty or (px == 0 and py == 0) or (tx == 0 and ty == 0) then return nil, false end

    -- WoW map Y increases toward the south. This is the 3.3.5 direction
    -- convention used by DBM/TomTom-style arrows: north=0, west=pi/2,
    -- south=pi, east=3*pi/2, then rotate relative to player facing.
    local mapAngle = math.pi - Atan2(px - tx, ty - py)
    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    return NormalizeAngle(mapAngle - NormalizeAngle(facing)), true
end

local function CurrentRows()
    if runtimeRows and table.getn(runtimeRows) > 0 then return runtimeRows end
    return ActiveRows()
end

local function CurrentPersonalAssignment()
    local rows = CurrentRows()
    SkipDeadActiveTargets(rows)
    local player = GetPlayerName()
    local db = EnsureDB()
    if db.testMode and player == "" then player = DEFAULT_TEST_NAMES[1] end
    local startRow = CurrentActiveRow(rows) or 1
    local rowIndex
    for rowIndex = startRow, table.getn(rows or {}) do
        local row = rows[rowIndex]
        local i
        for i = 1, table.getn(row.assignments or {}) do
            local assignment = row.assignments[i]
            if NormalizeName(assignment.source) == player and not assignment.completed then
                local target = NormalizeName(assignment.target)
                if target ~= "" and IsNameDead(target) then
                    assignment.completed = true
                    assignment.skipped = true
                    Print("Bite " .. rowIndex .. " skipped: " .. player .. " > " .. target .. " (target dead)")
                else
                    return assignment, rowIndex
                end
            end
        end
    end
    if db.testMode then
        for rowIndex = startRow, table.getn(rows or {}) do
            local row = rows[rowIndex]
            local i
            for i = 1, table.getn(row.assignments or {}) do
                local assignment = row.assignments[i]
                if not assignment.completed then return assignment, rowIndex end
            end
        end
    end
    return nil, nil
end

local function SaveOverlayPosition()
    if not overlayFrame then return end
    local _, char = EnsureDB()
    local point, _, relativePoint, x, y = overlayFrame:GetPoint(1)
    char.overlayPoint = point or "CENTER"
    char.overlayRelativePoint = relativePoint or point or "CENTER"
    char.overlayX = tonumber(x) or 0
    char.overlayY = tonumber(y) or 0
end

local function SetSecureTarget(button, name)
    if not button then return end
    if InCombatLockdown and InCombatLockdown() then secureRebuildPending = true; return end
    name = NormalizeName(name)
    button:SetAttribute("type", name ~= "" and "macro" or nil)
    button:SetAttribute("macrotext", name ~= "" and ("/target " .. name) or nil)
    button.wowNoteTargetName = name
end

local function StartOverlayDrag(force)
    if not overlayFrame then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local _, char = EnsureDB()
    if char.overlayLocked and force ~= true then return end
    overlayFrame:StartMoving()
end

local function StopOverlayDrag()
    if not overlayFrame then return end
    if InCombatLockdown and InCombatLockdown() then return end
    overlayFrame:StopMovingOrSizing()
    SaveOverlayPosition()
end

local function CreateOverlay()
    if overlayFrame then return end
    local _, char = EnsureDB()
    overlayFrame = CreateFrame("Frame", "WowNoteBiteHelperOverlay", UIParent)
    overlayFrame:SetWidth(560); overlayFrame:SetHeight(180)
    overlayFrame:SetPoint(char.overlayPoint, UIParent, char.overlayRelativePoint, char.overlayX, char.overlayY)
    overlayFrame:SetFrameStrata("DIALOG")
    if overlayFrame.SetClampedToScreen then overlayFrame:SetClampedToScreen(true) end
    overlayFrame:SetMovable(true); overlayFrame:EnableMouse(true); overlayFrame:RegisterForDrag("LeftButton")
    overlayFrame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 12, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    overlayFrame:SetBackdropColor(0.02, 0.02, 0.02, 0.90)
    overlayFrame:SetBackdropBorderColor(0.48, 0.38, 0.18, 1)
    overlayFrame:SetScript("OnDragStart", function() StartOverlayDrag(true) end)
    overlayFrame:SetScript("OnDragStop", StopOverlayDrag)

    overlayFrame.dragBar = CreateFrame("Frame", nil, overlayFrame)
    overlayFrame.dragBar:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", 4, -4)
    overlayFrame.dragBar:SetPoint("TOPRIGHT", overlayFrame, "TOPRIGHT", -80, -4)
    overlayFrame.dragBar:SetHeight(26)
    overlayFrame.dragBar:EnableMouse(true)
    overlayFrame.dragBar:RegisterForDrag("LeftButton")
    overlayFrame.dragBar:SetScript("OnDragStart", function() StartOverlayDrag(true) end)
    overlayFrame.dragBar:SetScript("OnDragStop", StopOverlayDrag)
    overlayFrame.dragBar:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    overlayFrame.dragBar:SetBackdropColor(0, 0, 0, 0)

    overlayFrame.title = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlayFrame.title:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", 10, -8)
    overlayFrame.title:SetText("Bite Helper  |cffb0b0b0(drag here to move)|r")
    overlayFrame.testLabel = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlayFrame.testLabel:SetPoint("TOP", overlayFrame, "TOP", 0, -8)
    overlayFrame.testLabel:SetText("|cffff3030TEST MODE|r")
    overlayFrame.testLabel:Hide()

    overlayFrame.edit = CreateFrame("Button", nil, overlayFrame)
    overlayFrame.edit:SetWidth(22); overlayFrame.edit:SetHeight(22)
    overlayFrame.edit:SetPoint("TOPRIGHT", overlayFrame, "TOPRIGHT", -56, -4)
    overlayFrame.edit:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    overlayFrame.edit:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    overlayFrame.edit:SetScript("OnClick", function() if WowNote_OpenBiteHelper then WowNote_OpenBiteHelper(true) end end)

    overlayFrame.lock = CreateFrame("Button", nil, overlayFrame)
    overlayFrame.lock:SetWidth(22); overlayFrame.lock:SetHeight(22)
    overlayFrame.lock:SetPoint("TOPRIGHT", overlayFrame, "TOPRIGHT", -32, -4)
    overlayFrame.lock:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    overlayFrame.lock:SetScript("OnClick", function()
        local _, saved = EnsureDB()
        saved.overlayLocked = not saved.overlayLocked
        if WowNote_BiteHelper_RefreshOverlay then WowNote_BiteHelper_RefreshOverlay() end
        Print(saved.overlayLocked and "Player HUD locked. The title bar remains movable." or "Player HUD unlocked. Drag the title bar, background, or a player field to move it.")
    end)

    overlayFrame.close = CreateFrame("Button", nil, overlayFrame, "UIPanelCloseButton")
    overlayFrame.close:SetPoint("TOPRIGHT", overlayFrame, "TOPRIGHT", 1, 1)
    overlayFrame.close:SetScript("OnClick", function() local _, saved = EnsureDB(); saved.overlayVisible = false; overlayFrame:Hide() end)

    overlayFrame.roundText = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlayFrame.roundText:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", 10, -34)
    overlayFrame.roundText:SetText("Waiting for bite order")

    overlayFrame.chainButtons = {}
    overlayFrame.chainArrows = {}
    local i
    for i = 1, 5 do
        local button = CreateFrame("Button", "WowNoteBiteTargetButton" .. i, overlayFrame, "SecureActionButtonTemplate")
        button:SetWidth(88); button:SetHeight(42); button:RegisterForClicks("AnyUp"); button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", StartOverlayDrag)
        button:SetScript("OnDragStop", StopOverlayDrag)
        button:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        button:SetBackdropColor(0.03, 0.03, 0.03, 0.94); button:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetPoint("CENTER"); button.text:SetWidth(80); button.text:SetJustifyH("CENTER")
        button.skull = button:CreateTexture(nil, "OVERLAY")
        button.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        button.skull:SetWidth(22); button.skull:SetHeight(22); button.skull:SetPoint("CENTER"); button.skull:Hide()
        button.deadX = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        button.deadX:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.deadX:SetText("|cffff2020X|r")
        button.deadX:Hide()
        button.glow = button:CreateTexture(nil, "OVERLAY")
        button.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); button.glow:SetBlendMode("ADD")
        button.glow:SetPoint("TOPLEFT", button, "TOPLEFT", -13, 13); button.glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 13, -13)
        button.glow:SetVertexColor(1, 0.72, 0.12, 0.9); button.glow:Hide()
        overlayFrame.chainButtons[i] = button
        if i > 1 then
            local arrow = overlayFrame:CreateTexture(nil, "ARTWORK")
            arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            arrow:SetWidth(22); arrow:SetHeight(22)
            overlayFrame.chainArrows[i - 1] = arrow
        end
    end

    overlayFrame.direction = CreateFrame("Frame", nil, overlayFrame)
    overlayFrame.direction:SetWidth(54); overlayFrame.direction:SetHeight(54)
    overlayFrame.direction:SetPoint("BOTTOM", overlayFrame, "BOTTOM", 0, 8)
    overlayFrame.direction.arrow = overlayFrame.direction:CreateTexture(nil, "ARTWORK")
    overlayFrame.direction.arrow:SetAllPoints(overlayFrame.direction)
    overlayFrame.direction.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    overlayFrame.direction.arrow:SetVertexColor(1, 0.82, 0.18, 1)
    overlayFrame.direction.glow = overlayFrame.direction:CreateTexture(nil, "BACKGROUND")
    overlayFrame.direction.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); overlayFrame.direction.glow:SetBlendMode("ADD")
    overlayFrame.direction.glow:SetPoint("TOPLEFT", overlayFrame.direction, "TOPLEFT", -12, 12); overlayFrame.direction.glow:SetPoint("BOTTOMRIGHT", overlayFrame.direction, "BOTTOMRIGHT", 12, -12)
    overlayFrame.direction.text = overlayFrame.direction:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    overlayFrame.direction.text:SetPoint("TOP", overlayFrame.direction, "BOTTOM", 0, 2)

    overlayUpdateHandler = function(self, elapsed)
        if not backgroundMonitoringActive then return end
        overlayElapsed = overlayElapsed + (elapsed or 0)
        local pulse = 0.55 + (0.45 * math.abs(math.sin((GetTime and GetTime() or 0) * 3)))
        local j
        for j = 1, table.getn(self.chainButtons) do if self.chainButtons[j].glow:IsShown() then self.chainButtons[j].glow:SetAlpha(pulse) end end
        self.direction.glow:SetAlpha(pulse)
        if overlayElapsed >= 0.25 then
            overlayElapsed = 0
            if WowNote_BiteHelper_RefreshOverlay then WowNote_BiteHelper_RefreshOverlay() end
        end
    end
    overlayFrame:SetScript("OnShow", function() if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end end)
    overlayFrame:SetScript("OnHide", function() if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end end)
    overlayFrame:Hide()
end

local function DeleteRow(rowIndex)
    if not CanEdit() then Print("Bite order editing is not available right now."); return end
    rowIndex = tonumber(rowIndex) or 0
    local rows = ActiveRows()
    EnsureFirstRow(rows)
    local count = table.getn(rows)
    if rowIndex < 1 or rowIndex > count then return end

    if count > 1 then
        table.remove(rows, rowIndex)
        RebuildFollowingRows(math.max(2, rowIndex))
    else
        rows[1].assignments = { { source = "", target = "", completed = false } }
    end
    ResetProgress(rows)
    if WowNote_BiteHelper_RefreshEditor then WowNote_BiteHelper_RefreshEditor() end
    if WowNote_BiteHelper_RefreshOverlay then WowNote_BiteHelper_RefreshOverlay() end
end

local function ToggleHudVisibility()
    CreateOverlay()
    local _, char = EnsureDB()
    char.overlayVisible = not (char.overlayVisible == true)
    if char.overlayVisible then
        overlayFrame:Show()
    else
        overlayFrame:Hide()
    end
    if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end
    if WowNote_BiteHelper_RefreshEditor then WowNote_BiteHelper_RefreshEditor() end
end


local function PersonalChain(rows, player)
    local chain = {}
    local rowIndex
    for rowIndex = 1, table.getn(rows or {}) do
        local assignmentIndex
        for assignmentIndex = 1, table.getn(rows[rowIndex].assignments or {}) do
            local assignment = rows[rowIndex].assignments[assignmentIndex]
            if NormalizeName(assignment.source) == player then table.insert(chain, { row = rowIndex, assignment = assignment }) end
        end
    end
    return chain
end

function WowNote_BiteHelper_RefreshOverlay()
    CreateOverlay()
    local db, char = EnsureDB()
    if not IsBiteModuleEnabled() then
        overlayFrame:Hide()
        if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end
        return
    end
    if not char.overlayVisible then
        overlayFrame:Hide()
        if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end
        return
    end
    overlayFrame:Show()
    if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end
    if db.testMode then overlayFrame.testLabel:Show() else overlayFrame.testLabel:Hide() end
    overlayFrame.lock:SetNormalTexture(char.overlayLocked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
    if char.overlayLocked then
        overlayFrame.dragBar:SetBackdropColor(0.20, 0.14, 0.02, 0.28)
        overlayFrame.title:SetText("Bite Helper - drag title to move")
    else
        overlayFrame.dragBar:SetBackdropColor(0.55, 0.38, 0.02, 0.45)
        overlayFrame.title:SetText("Bite Helper - drag anywhere")
    end

    local rows = CurrentRows()
    SkipDeadActiveTargets(rows)
    local player = GetPlayerName()
    if db.testMode and player == "" then player = DEFAULT_TEST_NAMES[1] end
    local chain = PersonalChain(rows, player)
    if table.getn(chain) == 0 and db.testMode then player = DEFAULT_TEST_NAMES[1]; chain = PersonalChain(rows, player) end
    local currentAssignment, currentRow = CurrentPersonalAssignment()
    overlayFrame.roundText:SetText(currentRow and ("Bite " .. currentRow .. " - " .. player) or (table.getn(rows) > 0 and "Bite order complete" or "Waiting for bite order"))

    local startIndex = 1
    if table.getn(chain) > 5 then
        local k
        for k = 1, table.getn(chain) do if chain[k].row >= (currentRow or 1) then startIndex = math.max(1, k - 1); break end end
    end
    local visible = 0
    local currentButton = nil
    local chainIndex
    for chainIndex = startIndex, math.min(table.getn(chain), startIndex + 4) do
        visible = visible + 1
        local info = chain[chainIndex]
        local assignment = info.assignment
        local target = NormalizeName(assignment.target)
        local button = overlayFrame.chainButtons[visible]
        button:ClearAllPoints(); button:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", 12 + ((visible - 1) * 108), -56)
        button.text:SetText(target ~= "" and target or "Unassigned")
        if target ~= "" and IsNameDead(target) then
            button.skull:Show(); button.deadX:Show(); button.text:Hide()
        else
            button.skull:Hide(); button.deadX:Hide(); button.text:Show()
        end
        if currentRow == info.row and assignment == currentAssignment and not assignment.completed and target ~= "" then
            button.glow:Show()
            currentButton = button
        else
            button.glow:Hide()
        end
        if assignment.skipped then
            button:SetBackdropColor(0.30, 0.02, 0.02, 0.94); button:SetBackdropBorderColor(0.95, 0.15, 0.15, 1)
        elseif assignment.completed then
            button:SetBackdropColor(0.02, 0.22, 0.04, 0.94); button:SetBackdropBorderColor(0.2, 0.8, 0.25, 1)
        elseif currentRow == info.row and assignment == currentAssignment then
            button:SetBackdropColor(0.36, 0.24, 0.02, 0.96); button:SetBackdropBorderColor(1, 0.78, 0.2, 1)
        else
            button:SetBackdropColor(0.04, 0.04, 0.04, 0.94); button:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
        end
        if button.wowNoteTargetName ~= target then SetSecureTarget(button, target) end
        button:Show()
        if visible > 1 then
            local arrow = overlayFrame.chainArrows[visible - 1]
            arrow:ClearAllPoints(); arrow:SetPoint("LEFT", overlayFrame.chainButtons[visible - 1], "RIGHT", 0, 0); arrow:Show()
        end
    end
    local i
    for i = visible + 1, table.getn(overlayFrame.chainButtons) do overlayFrame.chainButtons[i]:Hide() end
    for i = math.max(1, visible), table.getn(overlayFrame.chainArrows) do overlayFrame.chainArrows[i]:Hide() end

    if currentAssignment and NormalizeName(currentAssignment.target) ~= "" then
        local angle, available = GetDirectionToName(currentAssignment.target)
        overlayFrame.direction:ClearAllPoints()
        if currentButton then
            overlayFrame.direction:SetPoint("TOP", currentButton, "BOTTOM", 0, -4)
        else
            overlayFrame.direction:SetPoint("BOTTOM", overlayFrame, "BOTTOM", 0, 8)
        end
        overlayFrame.direction:Show()
        if available then
            RotateTexture(overlayFrame.direction.arrow, angle); overlayFrame.direction.arrow:SetVertexColor(1, 0.82, 0.18, 1)
            overlayFrame.direction.text:SetText(currentAssignment.target)
        else
            RotateTexture(overlayFrame.direction.arrow, 0); overlayFrame.direction.arrow:SetVertexColor(0.55, 0.55, 0.55, 1)
            overlayFrame.direction.text:SetText(currentAssignment.target .. " - direction unavailable")
        end
    else
        overlayFrame.direction:Hide()
    end
end

local function CreateDragGhost()
    if dragGhost then return end
    dragGhost = CreateFrame("Frame", nil, UIParent)
    dragGhost:SetWidth(100); dragGhost:SetHeight(24); dragGhost:SetFrameStrata("TOOLTIP")
    dragGhost:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    dragGhost:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    dragGhost.text = dragGhost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); dragGhost.text:SetPoint("CENTER")
    WowNoteProfiler_SetScript(dragGhost, "OnUpdate", "BiteHelper.DragGhost", function(self)
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        self:ClearAllPoints(); self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)
    dragGhost:Hide()
end

local function StartNameDrag(name)
    draggedName = NormalizeName(name); selectedRosterName = draggedName
    CreateDragGhost(); dragGhost.text:SetText(draggedName); dragGhost:Show()
end

local function StopNameDrag()
    if dragGhost then dragGhost:Hide() end
    draggedName = nil
end

local function AssignNameToSlot(slot, name)
    if not CanEdit() then return end
    name = NormalizeName(name or selectedRosterName or draggedName)
    if name == "" or not slot or not slot.assignment then return end
    if slot.kind == "source" then
        slot.assignment.source = name
        if NormalizeName(slot.assignment.target) == name then slot.assignment.target = "" end
    else
        slot.assignment.target = name; slot.assignment.completed = false
    end
    RebuildFollowingRows((slot.rowIndex or 1) + 1)
    StopNameDrag()
    if WowNote_BiteHelper_RefreshEditor then WowNote_BiteHelper_RefreshEditor() end
end

local function CreateDropSlot(parent, width)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetWidth(width or 78); slot:SetHeight(38)
    slot:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    slot:SetBackdropColor(0.04, 0.04, 0.04, 0.94); slot:SetBackdropBorderColor(0.65, 0.65, 0.65, 1)
    slot.text = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); slot.text:SetPoint("CENTER"); slot.text:SetWidth((width or 78) - 8)
    slot:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    slot:RegisterForClicks("LeftButtonUp")
    slot:SetScript("OnClick", function(self) AssignNameToSlot(self, selectedRosterName) end)
    slot:SetScript("OnReceiveDrag", function(self) AssignNameToSlot(self, draggedName) end)
    slot:SetScript("OnMouseUp", function(self) if draggedName then AssignNameToSlot(self, draggedName) end end)
    return slot
end

local function SetButtonEnabled(button, enabled)
    if not button then return end
    if enabled then
        if button.Enable then button:Enable() end
        if button.EnableMouse then button:EnableMouse(true) end
        if button.SetAlpha then button:SetAlpha(1) end
    else
        if button.Disable then button:Disable() end
        if button.EnableMouse then button:EnableMouse(false) end
        if button.SetAlpha then button:SetAlpha(0.55) end
    end
end

local function CreateEditor()
    if editorFrame then return end
    editorFrame = CreateFrame("Frame", "WowNoteBiteHelperEditor", UIParent)
    editorFrame:SetWidth(1080); editorFrame:SetHeight(680); editorFrame:SetPoint("CENTER")
    editorFrame:SetFrameStrata("FULLSCREEN_DIALOG"); editorFrame:SetFrameLevel(100); editorFrame:SetToplevel(true)
    editorFrame:SetMovable(true); editorFrame:EnableMouse(true); editorFrame:RegisterForDrag("LeftButton")
    editorFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    editorFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    editorFrame:SetScript("OnShow", function() if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end end)
    editorFrame:SetScript("OnHide", function() if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end end)
    editorFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    editorFrame:Hide()

    editorFrame.title = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editorFrame.title:SetPoint("TOPLEFT", editorFrame, "TOPLEFT", 18, -16); editorFrame.title:SetText("WoWNote Bite Helper")
    local close = CreateFrame("Button", nil, editorFrame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -4, -4)
    editorFrame.status = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editorFrame.status:SetPoint("TOPLEFT", editorFrame, "TOPLEFT", 18, -46); editorFrame.status:SetWidth(660); editorFrame.status:SetJustifyH("LEFT")

    editorFrame.hudButton = MakeButton(editorFrame, "HUD", 85, 24)
    editorFrame.hudButton:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -430, -18)
    editorFrame.hudButton:SetScript("OnClick", function() ToggleHudVisibility() end)

    editorFrame.testButton = MakeButton(editorFrame, "Test Mode", 95, 24)
    editorFrame.testButton:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -340, -18)
    editorFrame.testButton:SetScript("OnClick", function()
        local db = EnsureDB(); db.testMode = not db.testMode
        if db.testMode then EnsureFirstRow(db.testRows); ApplyRuntimeOrder(db.testRows); Print("Test mode enabled.")
        else ApplyRuntimeOrder(db.rows); testDead = {}; Print("Test mode disabled.") end
        WowNote_BiteHelper_RefreshEditor()
    end)
    editorFrame.addRow = MakeButton(editorFrame, "Add Row", 90, 24)
    editorFrame.addRow:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -230, -18)
    editorFrame.addRow:SetScript("OnClick", function() AddRow(); WowNote_BiteHelper_RefreshEditor() end)
    editorFrame.deleteRow = MakeButton(editorFrame, "Delete Last", 95, 24)
    editorFrame.deleteRow:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -130, -18)
    editorFrame.deleteRow:SetScript("OnClick", function() local rows = ActiveRows(); DeleteRow(table.getn(rows)) end)
    editorFrame.post = MakeButton(editorFrame, "Post / Apply", 100, 24)
    editorFrame.post:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -26, -18)
    editorFrame.post:SetScript("OnClick", function() PostOrder(); WowNote_BiteHelper_RefreshEditor() end)

    editorFrame.rowsScroll = CreateFrame("ScrollFrame", "WowNoteBiteRowsScroll", editorFrame, "UIPanelScrollFrameTemplate")
    editorFrame.rowsScroll:SetPoint("TOPLEFT", editorFrame, "TOPLEFT", 18, -76)
    editorFrame.rowsScroll:SetPoint("BOTTOMRIGHT", editorFrame, "BOTTOMRIGHT", -318, 100)
    editorFrame.rowsContent = CreateFrame("Frame", nil, editorFrame.rowsScroll)
    editorFrame.rowsContent:SetWidth(720); editorFrame.rowsContent:SetHeight(500)
    editorFrame.rowsScroll:SetScrollChild(editorFrame.rowsContent)
    editorFrame.rowFrames = {}

    editorFrame.rosterTitle = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorFrame.rosterTitle:SetPoint("TOPLEFT", editorFrame, "TOPRIGHT", -292, -78); editorFrame.rosterTitle:SetText("Raid Roster")
    editorFrame.rosterButtons = {}

    editorFrame.testPanel = CreateFrame("Frame", nil, editorFrame)
    editorFrame.testPanel:SetPoint("BOTTOMLEFT", editorFrame, "BOTTOMLEFT", 18, 22); editorFrame.testPanel:SetWidth(730); editorFrame.testPanel:SetHeight(66)
    editorFrame.testPanel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    editorFrame.testPanel:SetBackdropColor(0.16, 0.03, 0.03, 0.94)
    editorFrame.testPanel.title = editorFrame.testPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    editorFrame.testPanel.title:SetPoint("TOPLEFT", editorFrame.testPanel, "TOPLEFT", 8, -7); editorFrame.testPanel.title:SetText("TEST MODE CONTROLS")

    local simBite = MakeButton(editorFrame.testPanel, "Sim Bite", 80, 22); simBite:SetPoint("BOTTOMLEFT", editorFrame.testPanel, "BOTTOMLEFT", 8, 8)
    simBite:SetScript("OnClick", function()
        local assignment, row = CurrentPersonalAssignment()
        if assignment then assignment.completed = true; Print("Simulated Bite " .. tostring(row) .. ".") end
    end)
    local previous = MakeButton(editorFrame.testPanel, "Previous", 80, 22); previous:SetPoint("LEFT", simBite, "RIGHT", 6, 0)
    previous:SetScript("OnClick", function()
        local rows = CurrentRows(); local lastCompleted
        local r, a
        for r = 1, table.getn(rows) do for a = 1, table.getn(rows[r].assignments or {}) do if rows[r].assignments[a].completed then lastCompleted = rows[r].assignments[a] end end end
        if lastCompleted then lastCompleted.completed = false end
    end)
    local reset = MakeButton(editorFrame.testPanel, "Reset", 70, 22); reset:SetPoint("LEFT", previous, "RIGHT", 6, 0)
    reset:SetScript("OnClick", function() ResetProgress(CurrentRows()); testDead = {} end)
    local kill = MakeButton(editorFrame.testPanel, "Kill/Revive", 90, 22); kill:SetPoint("LEFT", reset, "RIGHT", 6, 0)
    kill:SetScript("OnClick", function()
        if lastTestDeadName and testDead[lastTestDeadName] then
            testDead[lastTestDeadName] = nil
            lastTestDeadName = nil
            return
        end
        local assignment = CurrentPersonalAssignment()
        if assignment then
            local target = NormalizeName(assignment.target)
            if target ~= "" then
                testDead[target] = true
                lastTestDeadName = target
            end
        end
    end)
    local direction = MakeButton(editorFrame.testPanel, "Rotate Arrow", 95, 22); direction:SetPoint("LEFT", kill, "RIGHT", 6, 0)
    direction:SetScript("OnClick", function() testDirection = testDirection + (math.pi / 4) end)
    local localSync = MakeButton(editorFrame.testPanel, "Local Sync", 85, 22); localSync:SetPoint("LEFT", direction, "RIGHT", 6, 0)
    localSync:SetScript("OnClick", function()
        ApplyRuntimeOrder(ActiveRows())
        local _, char = EnsureDB()
        char.overlayVisible = true
        if WowNote_BiteHelper_RefreshOverlay then WowNote_BiteHelper_RefreshOverlay() end
    end)
end

local function GetOrCreateRowFrame(index)
    local frame = editorFrame.rowFrames[index]
    if frame then return frame end
    frame = CreateFrame("Frame", nil, editorFrame.rowsContent)
    frame:SetWidth(700); frame:SetHeight(80)
    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal"); frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -4)
    frame.deleteButton = MakeButton(frame, "Delete row", 78, 20)
    frame.deleteButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -2)
    frame.deleteButton:SetScript("OnClick", function(self) DeleteRow(self.rowIndex) end)
    frame.slots = {}; editorFrame.rowFrames[index] = frame
    return frame
end

local function GetOrCreatePair(rowFrame, index)
    local pair = rowFrame.slots[index]
    if pair then return pair end
    pair = CreateFrame("Frame", nil, rowFrame); pair:SetWidth(220); pair:SetHeight(56)
    pair.source = CreateDropSlot(pair, 78); pair.source:SetPoint("LEFT", pair, "LEFT", 0, 0)
    pair.arrow = pair:CreateTexture(nil, "ARTWORK"); pair.arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"); pair.arrow:SetWidth(24); pair.arrow:SetHeight(24); pair.arrow:SetPoint("LEFT", pair.source, "RIGHT", 4, 0)
    pair.target = CreateDropSlot(pair, 78); pair.target:SetPoint("LEFT", pair.arrow, "RIGHT", 4, 0)
    pair.remove = CreateFrame("Button", nil, pair); pair.remove:SetWidth(18); pair.remove:SetHeight(18); pair.remove:SetPoint("TOPLEFT", pair.target, "TOPRIGHT", -2, 4)
    pair.remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up"); pair.remove:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    rowFrame.slots[index] = pair
    return pair
end

function WowNote_BiteHelper_RefreshEditor()
    CreateEditor()
    local db = EnsureDB()
    local rows = ActiveRows(); EnsureFirstRow(rows)
    local _, char = EnsureDB()
    editorFrame.hudButton:SetText(char.overlayVisible and "HUD: ON" or "HUD: OFF")
    editorFrame.testButton:SetText(db.testMode and "Test: ON" or "Test: OFF")
    if db.testMode then editorFrame.testPanel:Show() else editorFrame.testPanel:Hide() end
    local canEdit = CanEdit()
    local status
    local canPost = db.testMode or (IsRaidActive() and IsLeaderOrAssistant())
    if db.testMode then
        status = "|cffff4040TEST MODE - local simulation only|r"
    elseif canPost then
        status = "Raid leader/assistant: local editing and posting enabled"
    else
        status = "Local editing enabled; posting requires raid lead/assist"
    end
    editorFrame.status:SetText(status)

    local totalHeight = 0
    local rowIndex
    for rowIndex = 1, table.getn(rows) do
        local row = rows[rowIndex]
        local rowFrame = GetOrCreateRowFrame(rowIndex)
        rowFrame:ClearAllPoints(); rowFrame:SetPoint("TOPLEFT", editorFrame.rowsContent, "TOPLEFT", 0, -totalHeight)
        rowFrame.label:SetText("Bite " .. rowIndex)
        rowFrame.deleteButton.rowIndex = rowIndex
        rowFrame.deleteButton:SetText(table.getn(rows) > 1 and "Delete row" or "Clear row")
        if canEdit then rowFrame.deleteButton:Show() else rowFrame.deleteButton:Hide() end
        local count = table.getn(row.assignments or {})
        local lines = math.max(1, math.ceil(count / 3))
        local height = 30 + (lines * 62); rowFrame:SetHeight(height)
        local assignmentIndex
        for assignmentIndex = 1, count do
            local assignment = row.assignments[assignmentIndex]
            local pair = GetOrCreatePair(rowFrame, assignmentIndex)
            local column = (assignmentIndex - 1) % 3
            local line = math.floor((assignmentIndex - 1) / 3)
            pair:ClearAllPoints(); pair:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", column * 230, -24 - (line * 62))
            pair.source.assignment = assignment; pair.source.kind = "source"; pair.source.rowIndex = rowIndex
            pair.target.assignment = assignment; pair.target.kind = "target"; pair.target.rowIndex = rowIndex
            pair.source.text:SetText(NormalizeName(assignment.source) ~= "" and NormalizeName(assignment.source) or "Drop source")
            pair.target.text:SetText(NormalizeName(assignment.target) ~= "" and NormalizeName(assignment.target) or "Drop target")
            pair.source:EnableMouse(rowIndex == 1 and CanEdit()); pair.target:EnableMouse(CanEdit())
            pair.remove.assignment = assignment; pair.remove.rowIndex = rowIndex
            pair.remove:SetScript("OnClick", function(self)
                if not CanEdit() then return end
                if self.rowIndex == 1 then self.assignment.source = ""; self.assignment.target = "" else self.assignment.target = "" end
                self.assignment.completed = false; RebuildFollowingRows(self.rowIndex + 1); WowNote_BiteHelper_RefreshEditor()
            end)
            if CanEdit() then pair.remove:Show() else pair.remove:Hide() end
            pair:Show()
        end
        local i
        for i = count + 1, table.getn(rowFrame.slots) do rowFrame.slots[i]:Hide() end
        rowFrame:Show(); totalHeight = totalHeight + height + 6
    end
    local i
    for i = table.getn(rows) + 1, table.getn(editorFrame.rowFrames) do editorFrame.rowFrames[i]:Hide() end
    editorFrame.rowsContent:SetHeight(math.max(500, totalHeight))

    local roster = GetRoster()
    for i = 1, table.getn(roster) do
        local button = editorFrame.rosterButtons[i]
        if not button then
            button = CreateFrame("Button", nil, editorFrame); button:SetWidth(50); button:SetHeight(38)
            button:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            button:SetBackdropColor(0.04, 0.04, 0.04, 0.95); button:SetBackdropBorderColor(0.65, 0.65, 0.65, 1)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); button.text:SetPoint("CENTER"); button.text:SetWidth(46)
            button:RegisterForClicks("LeftButtonUp"); button:RegisterForDrag("LeftButton")
            button:SetScript("OnClick", function(self) selectedRosterName = self.playerName; WowNote_BiteHelper_RefreshEditor() end)
            button:SetScript("OnDragStart", function(self) StartNameDrag(self.playerName) end)
            button:SetScript("OnDragStop", function(self)
                local focus = GetMouseFocus and GetMouseFocus() or nil
                local depth = 0
                while focus and not focus.assignment and focus.GetParent and depth < 4 do
                    focus = focus:GetParent()
                    depth = depth + 1
                end
                if focus and focus.assignment then AssignNameToSlot(focus, self.playerName) else StopNameDrag() end
            end)
            editorFrame.rosterButtons[i] = button
        end
        local column = (i - 1) % 5; local row = math.floor((i - 1) / 5)
        button:ClearAllPoints(); button:SetPoint("TOPLEFT", editorFrame, "TOPRIGHT", -292 + (column * 54), -106 - (row * 42))
        button.playerName = roster[i]; button.text:SetText(roster[i])
        if selectedRosterName == roster[i] then button:SetBackdropBorderColor(1, 0.78, 0.2, 1) else button:SetBackdropBorderColor(0.65, 0.65, 0.65, 1) end
        button:Show()
    end
    for i = table.getn(roster) + 1, table.getn(editorFrame.rosterButtons) do editorFrame.rosterButtons[i]:Hide() end
    -- Post / Apply must remain clickable. PostOrder performs the authoritative
    -- raid-leader/assistant check and prints a useful reason instead of leaving
    -- the user with a grey, inert button. Editing controls still follow CanEdit.
    SetButtonEnabled(editorFrame.post, true)
    SetButtonEnabled(editorFrame.hudButton, true)
    SetButtonEnabled(editorFrame.addRow, canEdit)
    SetButtonEnabled(editorFrame.deleteRow, canEdit)
    WowNote_BiteHelper_RefreshOverlay()
end

function WowNote_OpenBiteHelper(openEditor)
    if not IsBiteModuleEnabled() then Print("Bite Helper module is disabled."); return end
    EnsureDB(); CreateOverlay()
    local _, char = EnsureDB(); char.overlayVisible = true; overlayFrame:Show()
    if openEditor ~= false then CreateEditor(); WowNote_BiteHelper_RefreshEditor(); editorFrame:Show(); if RaiseFrame then RaiseFrame(editorFrame) elseif editorFrame.Raise then editorFrame:Raise() end end
    if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end
    WowNote_BiteHelper_RefreshOverlay()
end

function WowNote_BiteHelper_SetEnabled(enabled)
    if not enabled then
        if editorFrame then editorFrame:Hide() end
        if overlayFrame then overlayFrame:Hide() end
    else
        WowNote_BiteHelper_RefreshOverlay()
    end
    if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end
end

local function CheckAuraTransitions()
    if not IsBiteHudActive() then return end
    local db = EnsureDB(); if db.testMode then return end
    local roster = GetRoster(); local i
    for i = 1, table.getn(roster) do
        local name = roster[i]; local has = HasEssence(name)
        if has and lastAuraState[name] == false then MarkTargetAuraGain(name) end
        lastAuraState[name] = has
    end
end

WowNote_BiteHelper_TestAPI = {
    SerializeRows = SerializeRows,
    DeserializeRows = DeserializeRows,
    ValidateRows = ValidateRows,
    DeepCopyRows = DeepCopyRows,
    CurrentActiveRow = CurrentActiveRow,
    MarkBiteCompleted = MarkBiteCompleted,
    MarkTargetAuraGain = MarkTargetAuraGain,
    ApplyRuntimeOrder = ApplyRuntimeOrder,
    GetRuntimeRows = function() return runtimeRows end,
    ResetProgress = ResetProgress,
    SkipDeadActiveTargets = SkipDeadActiveTargets,
    GetDirectionToName = GetDirectionToName,
    CurrentPersonalAssignment = CurrentPersonalAssignment,
    HandleAddonMessage = HandleAddonMessage,
    HandleChatSyncMessage = HandleChatSyncMessage,
    SendOrderSync = SendOrderSync,
    FormatOrderLines = FormatOrderLines,
    IsHudActive = IsBiteHudActive,
    IsBackgroundMonitoringActive = function() return backgroundMonitoringActive end,
    IsRosterMonitoringActive = function() return rosterMonitoringActive end,
    RefreshBackgroundMonitoring = function() if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end end,
    GetOverlayFrame = function() return overlayFrame end,
    GetEditorFrame = function() return editorFrame end,
    GetEventFrame = function() return eventFrame end,
}

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
WowNoteProfiler_SetScript(eventFrame, "OnEvent", "BiteHelper.Events", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = select(1, ...)
        if addonName == "WoWNote" then EnsureDB(); RegisterCommPrefixes(); RegisterChatSyncFilters() end
    elseif event == "PLAYER_LOGIN" then
        local db, char = EnsureDB(); RegisterCommPrefixes(); RegisterChatSyncFilters()
        char.overlayVisible = false
        runtimeRows = DeepCopyRows(db.testMode and db.testRows or db.rows)
        lastAuraState = {}
        if overlayFrame then overlayFrame:Hide() end
        if editorFrame then editorFrame:Hide() end
        if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = select(1, ...), select(2, ...), select(3, ...), select(4, ...)
        Debug("CHAT_MSG_ADDON event prefix=" .. tostring(prefix) .. " channel=" .. tostring(channel)
            .. " sender=" .. tostring(sender))
        HandleAddonMessage(prefix, message, channel, sender)
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_RAID_WARNING" then
        HandleChatSyncMessage(select(1, ...), select(2, ...), event)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not IsBiteHudActive() then return end
        local _, subEvent, _, sourceName, _, _, destName, _, spellId, spellName = ...
        local lowerSpell = string.lower(tostring(spellName or ""))
        if (subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_AURA_APPLIED") and (BITE_SPELL_IDS[tonumber(spellId or 0)] or string.find(lowerSpell, "vampiric bite", 1, true)) then
            MarkBiteCompleted(sourceName, destName, "combat log")
        end
    elseif event == "UNIT_AURA" then
        if IsBiteHudActive() then CheckAuraTransitions() end
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        if editorFrame and editorFrame:IsShown() then WowNote_BiteHelper_RefreshEditor() end
        if IsBiteHudActive() then WowNote_BiteHelper_RefreshOverlay() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if secureRebuildPending and IsBiteHudActive() then
            secureRebuildPending = false
            WowNote_BiteHelper_RefreshOverlay()
        end
    end
end)

if RefreshBackgroundMonitoring then RefreshBackgroundMonitoring() end

SLASH_WOWNOTEBITE1 = "/wnbite"
SLASH_WOWNOTEBITE2 = "/bitehelper"
SlashCmdList["WOWNOTEBITE"] = function(msg)
    msg = string.lower(Trim(msg))
    local db = EnsureDB()
    if msg == "test" or msg == "test on" then db.testMode = true; EnsureFirstRow(db.testRows); ApplyRuntimeOrder(db.testRows); WowNote_OpenBiteHelper(true)
    elseif msg == "test off" then db.testMode = false; ApplyRuntimeOrder(db.rows); WowNote_OpenBiteHelper(true)
    elseif msg == "overlay" then WowNote_OpenBiteHelper(false)
    elseif msg == "reset" then ResetProgress(CurrentRows()); WowNote_BiteHelper_RefreshOverlay()
    elseif msg == "debug" or msg == "debug on" then
        if WowNote_SetCommDebugEnabled then WowNote_SetCommDebugEnabled(true) end
        RegisterCommPrefixes()
        Print("Communication debug enabled for addon and raid-chat synchronization.")
    elseif msg == "debug off" then
        if WowNote_SetCommDebugEnabled then WowNote_SetCommDebugEnabled(false) end
        Print("Communication debug disabled.")
    else WowNote_OpenBiteHelper(true) end
end
