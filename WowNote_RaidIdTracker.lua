local ADDON_NAME = "WowNote"
local MODULE_VERSION = "1.9.74-raid-id-import-forwardfix"

local RI = {}
WowNoteRaidIdTracker = RI

local frame
local listRows = {}
local statusText
local selectedCharKey
local scanFrame = CreateFrame("Frame", "WowNoteRaidIdTrackerEventFrame")
local pendingScan = false
local MergePostedRaidIdData

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
    WowNoteDB = WowNoteDB or {}
    WowNoteDB.raidIds = WowNoteDB.raidIds or {}
    WowNoteDB.raidIds.characters = WowNoteDB.raidIds.characters or {}
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

function RI.ScanCurrentCharacter()
    local db = EnsureDB()
    local charKey = GetPlayerKey()
    local now = time()
    local currentMembers = GetCurrentGroupMemberNames()
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
        local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName = GetSavedInstanceInfo(i)
        if isRaid == true and locked == true and name then
            local resetSeconds = tonumber(reset or 0) or 0
            local lock = {
                name = name,
                id = id,
                reset = resetSeconds,
                expiresAt = now + resetSeconds,
                difficulty = GetDifficultyText(difficulty, maxPlayers, difficultyName),
                difficultyId = difficulty,
                maxPlayers = maxPlayers,
                extended = extended and true or false,
                members = {},
                firstSeenAt = now,
                lastSeenAt = now,
            }
            local old = previousByKey[MakeLockKey(lock)]
            if old then
                lock.firstSeenAt = old.firstSeenAt or now
                lock.members = old.members or {}
            end
            for _, memberName in ipairs(currentMembers) do
                AddUnique(lock.members, memberName)
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

local function ScheduleScan()
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
scanFrame:SetScript("OnEvent", function(self, event, message, sender)
    if string.find(tostring(event or ""), "^CHAT_MSG_") then
        MergePostedRaidIdData(message, sender)
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

local selectedRaidIndex = nil

local function CreateRaidRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(470, 22)
    row.index = index
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(0.10, 0.08, 0.04, 0.25)
    row:SetHighlightTexture("Interface\QuestFrame\UI-QuestTitleHighlight")
    row:SetScript("OnClick", function(self)
        selectedRaidIndex = self.index
        RI.RefreshUI()
    end)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetWidth(210)
    row.name:SetJustifyH("LEFT")
    row.diff = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.diff:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.diff:SetWidth(85)
    row.diff:SetJustifyH("LEFT")
    row.id = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.id:SetPoint("LEFT", row.diff, "RIGHT", 8, 0)
    row.id:SetWidth(80)
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
    return string.format("%s: %s %s ID %s, %s remaining, seen with %d player%s",
        tostring(charKey or "Character"),
        tostring(lock.name or "Unknown"),
        tostring(lock.difficulty or "Raid"),
        tostring(lock.id or "-"),
        FormatMoneyLikeTime((lock.expiresAt or time()) - time()),
        members,
        members == 1 and "" or "s")
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
    return "WNRI:v1;id=" .. EncodeField(lock.id or "")
        .. ";name=" .. EncodeField(lock.name or "")
        .. ";diff=" .. EncodeField(lock.difficulty or "")
        .. ";char=" .. EncodeField(charKey or "")
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
            local detailLines = {
                "Selected ID details:",
                "Also saved on this account: " .. (#account > 0 and table.concat(account, ", ") or "none"),
                "Seen with this ID/group: " .. (#members > 0 and table.concat(members, ", ") or "none recorded"),
            }
            local detail = table.concat(detailLines, "\n")
            frame.detailsText:SetText(detail)
        else
            frame.detailsText:SetText("Select a raid ID to see saved-with details.")
        end
    end
end

local function CreateUI()
    if frame then return end
    frame = CreateFrame("Frame", "WowNoteRaidIdTrackerFrame", UIParent)
    frame:SetSize(720, 470)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
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

    local postAll = MakeButton(frame, "Post All", 75, 24)
    postAll:SetPoint("RIGHT", postSelected, "LEFT", -8, 0)
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

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 240, -112)
    header:SetText("Raid                         Size/Mode       ID                 Remaining")

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
    frame.detailsText:SetPoint("TOPLEFT", frame, "TOPLEFT", 240, -370)
    frame.detailsText:SetWidth(455)
    frame.detailsText:SetHeight(60)
    frame.detailsText:SetJustifyH("LEFT")
    frame.detailsText:SetJustifyV("TOP")
    frame.detailsText:SetText("Select a raid ID to see saved-with details.")

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
