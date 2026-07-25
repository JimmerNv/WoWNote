-- WowNote Raid Planner Port Helper
-- Collects summon requests from chat and exposes one clickable target button per player.

WowNote_RaidPlanner = WowNote_RaidPlanner or {}
local RP = WowNote_RaidPlanner

local PH = {}
RP.PortHelper = PH

local ROW_HEIGHT = 30
local MAX_ROWS = 10
local UPDATE_INTERVAL = 0.5
local MESSAGE_PREFIX = "WoWNote- PortHelper:"
local RefreshPortMonitoringState

local function Trim(text)
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function ShortName(name)
    name = tostring(name or "")
    return string.match(name, "^[^-]+") or name
end

local function SafePlayerName(name)
    return string.match(ShortName(name), "^[^%s;/]+$")
end

local function EnsureDB()
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.raidPlannerPortHelper) ~= "table" then WowNoteDB.raidPlannerPortHelper = {} end
    local db = WowNoteDB.raidPlannerPortHelper
    if type(db.code) ~= "string" or db.code == "" then db.code = "123" end
    if type(db.channel) ~= "string" or db.channel == "" then db.channel = "/raid" end
    if type(db.message) ~= "string" or db.message == "" then
        db.message = "Need a summon? Write %code"
    elseif db.message == "Need a summon? Whisper %code" then
        db.message = "Need a summon? Write %code"
    end
    db.channel = "/raid"
    if type(db.tracking) ~= "boolean" then db.tracking = false end
    return db
end

local function SortedDigits(text)
    local digits = {}
    for digit in string.gmatch(tostring(text or ""), "%d") do
        table.insert(digits, digit)
    end
    table.sort(digits)
    return table.concat(digits)
end

local function IsMatchingRequest(message)
    local db = EnsureDB()
    local expected = string.gsub(db.code or "", "%D", "")
    if expected == "" then return false end

    local actual = string.gsub(tostring(message or ""), "%D", "")
    if string.len(actual) ~= string.len(expected) then return false end
    return SortedDigits(actual) == SortedDigits(expected)
end

local function FindGroupUnit(playerName)
    local wanted = string.lower(ShortName(playerName))
    local function matches(unit)
        if not UnitExists(unit) then return false end
        local name = UnitName(unit)
        return name and string.lower(ShortName(name)) == wanted
    end

    if matches("player") then return "player" end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            if matches(unit) then return unit end
        end
    else
        local count = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, count do
            local unit = "party" .. i
            if matches(unit) then return unit end
        end
    end
    return nil
end

local function GetPlayerStatus(entry)
    local unit = FindGroupUnit(entry.name)
    if not unit then return "Waiting", 1, 0.82, 0 end
    if UnitIsConnected and not UnitIsConnected(unit) then return "Offline", 0.55, 0.55, 0.55 end

    local inRange = UnitInRange and UnitInRange(unit)
    if inRange == 1 or inRange == true then
        return "In range", 0.2, 1, 0.2
    end
    return "In group", 1, 0.82, 0
end

local function UpdateTrackingUI()
    if not PH.frame then return end
    local db = EnsureDB()
    if PH.trackingButton then
        PH.trackingButton:SetText(db.tracking and "Stop Tracking" or "Start Tracking")
    end
    if PH.trackingText then
        if db.tracking then
            PH.trackingText:SetText("Tracking active")
            PH.trackingText:SetTextColor(0.2, 1, 0.2)
        else
            PH.trackingText:SetText("Tracking stopped")
            PH.trackingText:SetTextColor(1, 0.25, 0.25)
        end
    end
end

local function SetTracking(enabled)
    local db = EnsureDB()
    db.tracking = enabled and true or false
    UpdateTrackingUI()
    if RefreshPortMonitoringState then RefreshPortMonitoringState() end
    if WowNote_RaidPlanner_SetStatus then
        WowNote_RaidPlanner_SetStatus(db.tracking and "Port Helper tracking started." or "Port Helper tracking stopped.")
    end
end

local function UpdateRowTargetBinding(row, entry)
    if not row then return end
    if InCombatLockdown and InCombatLockdown() then
        row.pendingTargetName = entry and entry.name or nil
        return
    end

    row.pendingTargetName = nil
    if not entry then
        row:SetAttribute("type", nil)
        row:SetAttribute("type1", nil)
        row:SetAttribute("type2", nil)
        row:SetAttribute("unit", nil)
        row:SetAttribute("macrotext", nil)
        row:SetAttribute("macrotext1", nil)
        return
    end

    local safeName = SafePlayerName(entry.name)
    if not safeName then
        row:SetAttribute("type", nil)
        row:SetAttribute("type1", nil)
        row:SetAttribute("type2", nil)
        row:SetAttribute("unit", nil)
        row:SetAttribute("macrotext", nil)
        row:SetAttribute("macrotext1", nil)
        return
    end

    local macro = "/target " .. safeName
    row:SetAttribute("type", nil)
    row:SetAttribute("type1", "macro")
    row:SetAttribute("type2", nil)
    row:SetAttribute("unit", nil)
    row:SetAttribute("macrotext", macro)
    row:SetAttribute("macrotext1", macro)
end

local function RemoveArrivedEntries()
    if not PH.entries then return false end

    local now = GetTime and GetTime() or 0
    local changed = false
    for i = #PH.entries, 1, -1 do
        local entry = PH.entries[i]
        local unit = FindGroupUnit(entry.name)
        local inRange = unit and UnitIsConnected(unit) and UnitInRange and UnitInRange(unit)
        if inRange == 1 or inRange == true then
            entry.inRangeSince = entry.inRangeSince or now
            if now - entry.inRangeSince >= 0.75 then
                table.remove(PH.entries, i)
                changed = true
            end
        else
            entry.inRangeSince = nil
        end
    end
    return changed
end

local function RefreshRows()
    if not PH.frame then return end
    PH.entries = PH.entries or {}
    RemoveArrivedEntries()

    for i = 1, MAX_ROWS do
        local row = PH.rows[i]
        local entry = PH.entries[i]
        if entry then
            row.entry = entry
            UpdateRowTargetBinding(row, entry)
            row.nameText:SetText(entry.name)
            row.requestText:SetText(entry.message or "")
            local unit = FindGroupUnit(entry.name)
            local classToken = nil
            if unit then
                local className
                className, classToken = UnitClass(unit)
            end
            if classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken] then
                local coords = CLASS_ICON_TCOORDS[classToken]
                row.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
                row.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else
                row.icon:SetTexture("Interface\\Icons\\Spell_Shadow_Twilight")
                row.icon:SetTexCoord(0, 1, 0, 1)
            end
            local status, r, g, b = GetPlayerStatus(entry)
            row.statusText:SetText(status)
            row.statusText:SetTextColor(r, g, b)
            row:Show()
        else
            row.entry = nil
            UpdateRowTargetBinding(row, nil)
            row:Hide()
        end
    end

    PH.countText:SetText(tostring(#PH.entries) .. " waiting")
end

local function RemoveEntry(name)
    if not PH.entries then return end
    local wanted = string.lower(ShortName(name))
    for i = #PH.entries, 1, -1 do
        if string.lower(ShortName(PH.entries[i].name)) == wanted then
            table.remove(PH.entries, i)
        end
    end
    RefreshRows()
end

local function AddRequest(name, message)
    if not name or name == "" then return end
    PH.entries = PH.entries or {}
    local short = ShortName(name)
    local playerName = UnitName and UnitName("player") or nil
    if playerName and string.lower(ShortName(playerName)) == string.lower(short) then
        return
    end
    local wanted = string.lower(short)

    for _, entry in ipairs(PH.entries) do
        if string.lower(ShortName(entry.name)) == wanted then
            entry.message = Trim(message)
            entry.received = time and time() or 0
            RefreshRows()
            return
        end
    end

    table.insert(PH.entries, {
        name = short,
        message = Trim(message),
        received = time and time() or 0,
    })
    RefreshRows()
end

local function SendConfiguredMessage()
    local db = EnsureDB()
    db.code = Trim(PH.codeEdit:GetText())
    db.channel = Trim(PH.channelEdit:GetText())
    db.message = Trim(PH.messageEdit:GetText())

    local message = string.gsub(db.message, "%%code", db.code)
    message = Trim(message)
    if message == "" then
        WowNote_RaidPlanner_SetStatus("Port Helper message is empty.")
        return
    end

    local text = message
    if string.sub(text, 1, string.len(MESSAGE_PREFIX)) ~= MESSAGE_PREFIX then
        text = MESSAGE_PREFIX .. " " .. text
    end

    -- Port requests are always posted to raid chat. This avoids leaking the
    -- message into whisper or another channel selected in the Raid Planner.
    db.channel = "/raid"
    PH.channelEdit:SetText(db.channel)
    local ok, err
    if not SendChatMessage then
        ok, err = false, "Chat API is unavailable."
    else
        local callOk, result = pcall(SendChatMessage, text, "RAID")
        if not callOk then
            ok, err = false, result
        elseif result == false then
            ok, err = false, "Chat message was rejected."
        else
            ok = true
        end
    end

    if ok then
        WowNote_RaidPlanner_SetStatus("Port request posted: " .. text)
    else
        WowNote_RaidPlanner_SetStatus("Port request failed: " .. tostring(err or "unknown error"))
    end
    return ok, err
end

local function CreateEdit(parent, width, height, text)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetWidth(width)
    edit:SetHeight(height or 24)
    edit:SetAutoFocus(false)
    edit:SetText(text or "")
    return edit
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(height or 22)
    button:SetText(text)
    return button
end

local function CreateFrameUI()
    if PH.frame then return end
    local db = EnsureDB()

    local f = CreateFrame("Frame", "WowNoteRaidPlannerPortHelperFrame", UIParent)
    PH.frame = f
    f:SetWidth(440)
    f:SetHeight(510)
    f:SetPoint("CENTER", UIParent, "CENTER", 280, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.SetToplevel then f:SetToplevel(true) end
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    title:SetText("Raid Planner Port Helper")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local codeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    codeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -52)
    codeLabel:SetText("Reply code")
    PH.codeEdit = CreateEdit(f, 70, 24, db.code)
    PH.codeEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -68)

    local channelLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 112, -52)
    channelLabel:SetText("Channel (fixed)")
    PH.channelEdit = CreateEdit(f, 96, 24, "/raid")
    PH.channelEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 112, -68)
    -- WoW 3.3.5 EditBox has no Disable() method. Keep the fixed channel
    -- field visible but non-interactive instead.
    PH.channelEdit:EnableMouse(false)
    PH.channelEdit:SetAutoFocus(false)
    PH.channelEdit:SetTextColor(0.65, 0.65, 0.65)

    local messageLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    messageLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -104)
    messageLabel:SetText("Message (%code = reply code; prefix is added automatically)")
    PH.messageEdit = CreateEdit(f, 390, 24, db.message)
    PH.messageEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -120)

    local post = CreateButton(f, "Post for Port", 120, 24)
    PH.postButton = post
    post:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -157)
    post:SetScript("OnClick", function()
        SetTracking(false)
        local ok = SendConfiguredMessage()
        if ok then
            SetTracking(true)
        end
    end)

    PH.trackingButton = CreateButton(f, "Start Tracking", 110, 24)
    PH.trackingButton:SetPoint("LEFT", post, "RIGHT", 8, 0)
    PH.trackingButton:SetScript("OnClick", function()
        SetTracking(not EnsureDB().tracking)
    end)

    local clear = CreateButton(f, "Clear", 70, 24)
    clear:SetPoint("LEFT", PH.trackingButton, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        PH.entries = {}
        UpdateTrackingUI()
        RefreshRows()
    end)

    PH.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    PH.countText:SetPoint("LEFT", clear, "RIGHT", 12, 0)
    PH.countText:SetText("0 waiting")

    PH.trackingText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    PH.trackingText:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -188)
    PH.trackingText:SetText("Tracking stopped")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -206)
    hint:SetWidth(395)
    hint:SetJustifyH("LEFT")
    hint:SetText("Replies such as 123, 132, 1 2 3 or 'port 123' are accepted. Left-click a player to target them. Right-click removes the entry.")

    PH.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
        PH.rows[i] = row
        row:SetWidth(396)
        row:SetHeight(ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -250 - ((i - 1) * ROW_HEIGHT))
        row:RegisterForClicks("AnyUp")
        row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        row:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(22)
        icon:SetHeight(22)
        icon:SetPoint("LEFT", row, "LEFT", 5, 0)
        icon:SetTexture("Interface\\Icons\\Spell_Shadow_Twilight")
        row.icon = icon

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 7, 4)
        nameText:SetWidth(130)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local requestText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        requestText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1)
        requestText:SetWidth(190)
        requestText:SetJustifyH("LEFT")
        row.requestText = requestText

        local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        statusText:SetWidth(90)
        statusText:SetJustifyH("RIGHT")
        row.statusText = statusText

        row:SetScript("PostClick", function(self, button)
            if not self.entry then return end
            if button == "RightButton" then
                RemoveEntry(self.entry.name)
                return
            end
            WowNote_RaidPlanner_SetStatus("Targeting " .. self.entry.name .. " for summon.")
        end)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.18, 0.18, 0.18, 0.95)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.entry and self.entry.name or "Port request")
            GameTooltip:AddLine("Left-click: target player", 1, 1, 1)
            GameTooltip:AddLine("Right-click: remove request", 1, 1, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
            GameTooltip:Hide()
        end)
        row:Hide()
    end

    f:SetScript("OnShow", function()
        local current = EnsureDB()
        if PH.postButton then
            if PH.postButton.Enable then PH.postButton:Enable() end
            if PH.postButton.EnableMouse then PH.postButton:EnableMouse(true) end
            if PH.postButton.SetAlpha then PH.postButton:SetAlpha(1) end
        end
        PH.codeEdit:SetText(current.code)
        current.channel = "/raid"
        PH.channelEdit:SetText("/raid")
        PH.messageEdit:SetText(current.message)
        RefreshRows()
        if RefreshPortMonitoringState then RefreshPortMonitoringState() end
    end)
    f:SetScript("OnHide", function()
        if RefreshPortMonitoringState then RefreshPortMonitoringState() end
    end)
    f:Hide()
end

function RP.ShowPortHelper()
    CreateFrameUI()
    PH.frame:Show()
    if WowNote_Internal and WowNote_Internal.RaiseFrame then
        WowNote_Internal.RaiseFrame(PH.frame)
    elseif PH.frame.Raise then
        PH.frame:Raise()
    end
    UpdateTrackingUI()
    RefreshRows()
end

local eventFrame = CreateFrame("Frame")

local CHAT_EVENTS = {
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_RAID",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
}

local function PortHelperOnUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + (elapsed or 0)
    if self.elapsed < UPDATE_INTERVAL then return end
    self.elapsed = 0
    RefreshRows()
end

RefreshPortMonitoringState = function()
    local tracking = EnsureDB().tracking and true or false
    local visible = tracking and PH.frame and PH.frame:IsShown() and true or false
    local i
    for i = 1, table.getn(CHAT_EVENTS) do
        if tracking then
            eventFrame:RegisterEvent(CHAT_EVENTS[i])
        else
            eventFrame:UnregisterEvent(CHAT_EVENTS[i])
        end
    end
    if visible then
        eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
        eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame.elapsed = 0
        WowNoteProfiler_SetScript(eventFrame, "OnUpdate", "PortHelper.DistanceScan", PortHelperOnUpdate)
    else
        eventFrame:UnregisterEvent("RAID_ROSTER_UPDATE")
        eventFrame:UnregisterEvent("PARTY_MEMBERS_CHANGED")
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        WowNoteProfiler_SetScript(eventFrame, "OnUpdate", "PortHelper.DistanceScan", nil)
    end
end

WowNoteProfiler_SetScript(eventFrame, "OnEvent", "PortHelper.Events", function(self, event, message, sender)
    if string.sub(event, 1, 9) == "CHAT_MSG_" then
        if EnsureDB().tracking and IsMatchingRequest(message) then
            AddRequest(sender, message)
        end
    elseif PH.frame and PH.frame:IsShown() and EnsureDB().tracking then
        RefreshRows()
    end
end)

RefreshPortMonitoringState()

SLASH_WOWNOTEPORT1 = "/wnport"
SlashCmdList["WOWNOTEPORT"] = function(msg)
    local text = string.lower(Trim(msg))
    local db = EnsureDB()
    if text == "stop" or text == "off" then
        SetTracking(false)
        RP.ShowPortHelper()
        return
    elseif text == "start" or text == "on" then
        SetTracking(true)
        RP.ShowPortHelper()
        return
    elseif text ~= "" then
        db.code = Trim(msg)
    end
    RP.ShowPortHelper()
end
