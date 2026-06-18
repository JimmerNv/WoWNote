-- WowNote Raid Planner roster/assignment logic

WowNote_RaidPlanner = WowNote_RaidPlanner or {}
local RP = WowNote_RaidPlanner
local WNI = WowNote_Internal or {}
local Trim = WNI.Trim or function(text)
    text = text or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function NormalizeName(name)
    name = Trim(name or "")
    name = string.gsub(name, "%-.*$", "")
    return string.lower(name)
end

local function ParseRosterText(text)
    local rows = {}
    text = text or ""
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        line = Trim(line)
        if line ~= "" then
            local name, class = string.match(line, "^([^,;%-]+)[,;%-]%s*(.+)$")
            if not name then
                name = line
                class = ""
            end
            name = Trim(name or "")
            class = Trim(class or "")
            if name ~= "" then
                table.insert(rows, { name = name, class = class })
            end
        end
    end
    return rows
end

local function FormatRosterText(rows)
    local lines = {}
    if type(rows) == "table" then
        for _, entry in ipairs(rows) do
            local name = Trim(entry and entry.name or "")
            local class = Trim(entry and entry.class or "")
            if name ~= "" then
                if class ~= "" then
                    table.insert(lines, name .. ", " .. class)
                else
                    table.insert(lines, name)
                end
            end
        end
    end
    return table.concat(lines, "\n")
end

local function GetCurrentGroupNames()
    local names = {}
    local hasGroup = false
    local function addUnit(unit)
        if UnitExists and UnitExists(unit) then
            local name = UnitName(unit)
            if name and name ~= "" then
                names[NormalizeName(name)] = true
                hasGroup = true
            end
        end
    end

    addUnit("player")
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            addUnit("raid" .. i)
        end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            addUnit("party" .. i)
        end
    end

    return names, hasGroup
end

local function FilterRosterRows(rows, groupNames)
    local kept = {}
    local removed = 0
    for _, entry in ipairs(rows or {}) do
        local name = NormalizeName(entry and entry.name or "")
        if name ~= "" and groupNames[name] then
            table.insert(kept, entry)
        else
            removed = removed + 1
        end
    end
    return kept, removed
end

function RP.GetRosterData()
    local roster = {}
    for _, role in ipairs(RP.roles or {}) do
        local edit = RP.rosterEdits and RP.rosterEdits[role]
        roster[role] = ParseRosterText(edit and edit:GetText() or "")
    end
    return roster
end

function RP.SetRosterData(roster)
    RP.rosterEdits = RP.rosterEdits or {}
    for _, role in ipairs(RP.roles or {}) do
        local edit = RP.rosterEdits[role]
        if edit then
            edit:SetText(FormatRosterText(roster and roster[role] or {}))
        end
    end
    RP.UpdateHaveFromRoster()
end

function RP.ClearRoster()
    if not RP.rosterEdits then return end
    for _, role in ipairs(RP.roles or {}) do
        local edit = RP.rosterEdits[role]
        if edit then edit:SetText("") end
    end
    RP.forceRosterCount = true
    RP.UpdateHaveFromRoster()
    RP.forceRosterCount = false
end

function RP.UpdateHaveFromRoster()
    if not RP.rosterEdits then return end
    local map = {
        tanks = RP.tankHaveEdit,
        healers = RP.healHaveEdit,
        dps = RP.dpsHaveEdit,
        mdps = RP.mdpsHaveEdit,
        rdps = RP.rdpsHaveEdit,
    }
    for role, edit in pairs(map) do
        local rosterEdit = RP.rosterEdits[role]
        local rosterText = rosterEdit and rosterEdit:GetText() or ""
        local rows = ParseRosterText(rosterText)
        local shouldAutoCount = RP.forceRosterCount or Trim(rosterText) ~= ""
        if shouldAutoCount and edit and edit:GetText() ~= tostring(#rows) then
            RP.suppressPreview = true
            edit:SetText(tostring(#rows))
            RP.suppressPreview = false
        end
    end
end

function RP.RemoveLeaversFromRoster()
    if not RP.frame or not RP.rosterEdits then return end
    if RP.autoRemoveCheck and not RP.autoRemoveCheck:GetChecked() then return end

    local groupNames, hasGroup = GetCurrentGroupNames()
    if not hasGroup then return end

    local totalRemoved = 0
    for _, role in ipairs(RP.roles or {}) do
        local edit = RP.rosterEdits[role]
        if edit then
            local rows = ParseRosterText(edit:GetText() or "")
            local kept, removed = FilterRosterRows(rows, groupNames)
            if removed > 0 then
                edit:SetText(FormatRosterText(kept))
                totalRemoved = totalRemoved + removed
            end
        end
    end

    RP.forceRosterCount = true
    RP.UpdateHaveFromRoster()
    RP.forceRosterCount = false
    if totalRemoved > 0 then
        WowNote_RaidPlanner_SetStatus("Removed " .. totalRemoved .. " roster entr" .. (totalRemoved == 1 and "y" or "ies") .. " no longer in group.")
    end
    WowNote_RaidPlanner_UpdatePreview()
end

function RP.ScanGroupIntoRoster()
    local groupNames, hasGroup = GetCurrentGroupNames()
    if not hasGroup then
        WowNote_RaidPlanner_SetStatus("No group or raid found.")
        return
    end
    -- This intentionally does not auto-assign roles. It only refreshes counts/removes leavers.
    RP.RemoveLeaversFromRoster()
    WowNote_RaidPlanner_SetStatus("Group roster checked. Assign players manually to the role columns.")
end

function RP.EnsureRosterEventFrame()
    if RP.rosterEventFrame then return end
    local f = CreateFrame("Frame", "WowNoteRaidPlannerRosterEventFrame")
    RP.rosterEventFrame = f
    f:RegisterEvent("RAID_ROSTER_UPDATE")
    f:RegisterEvent("PARTY_MEMBERS_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    WowNoteProfiler_SetScript(f, "OnEvent", "RaidPlanner.RosterEvents", function()
        if RP.frame and RP.frame:IsShown() then
            RP.RemoveLeaversFromRoster()
        end
    end)
end

RP.EnsureRosterEventFrame()
