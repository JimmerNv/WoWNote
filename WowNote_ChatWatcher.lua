-- WowNote Chat Watcher
-- Watches selected chat channels for profile-specific phrases or Lua patterns.

local ADDON_NAME = "WowNote"
local MODULE_TITLE = "Chat Watcher"
local MAX_PROFILE_ROWS = 9
local ALERT_DEDUPE_SECONDS = 8

local frame
local popup
local helpFrame
local eventFrame
local initialized = false
local profileRows = {}
local profileOffset = 0
local selectedProfileId
local alertQueue = {}
local currentAlert
local recentAlerts = {}
local RefreshUI
local RefreshEventRegistrations
local ShowNextAlert
local EnsurePatternHelp
local Initialize

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote Chat Watcher:|r " .. tostring(message))
    end
end

local function Trim(value)
    value = tostring(value or "")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

local function NormalizePlayerName(name)
    name = Trim(name)
    name = string.gsub(name, "%-.*$", "")
    return name
end

local function Lower(value)
    return string.lower(tostring(value or ""))
end

local function NowEpoch()
    if time then return time() end
    return math.floor(GetTime and GetTime() or 0)
end

local function MonotonicNow()
    return GetTime and GetTime() or NowEpoch()
end

local function DB()
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.chatWatcher) ~= "table" then WowNoteDB.chatWatcher = {} end
    local db = WowNoteDB.chatWatcher

    if db.enabled == nil then db.enabled = false end
    if db.playSound == nil then db.playSound = true end
    if tonumber(db.defaultMuteHours) == nil then db.defaultMuteHours = 2 end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if type(db.mutedUsers) ~= "table" then db.mutedUsers = {} end
    if tonumber(db.nextProfileId) == nil then db.nextProfileId = 1 end

    if #db.profiles == 0 then
        local id = db.nextProfileId
        db.nextProfileId = id + 1
        db.profiles[1] = {
            id = id,
            name = "ICC 25",
            enabled = false,
            channels = "LookingForGroup, Trade",
            phrases = "ICC 25",
            excludePhrases = "",
            caseInsensitive = true,
            usePatterns = false,
        }
    end

    -- Backward-compatible migration for profiles created before exclude phrases existed.
    for _, profile in ipairs(db.profiles) do
        if profile.excludePhrases == nil then profile.excludePhrases = "" end
    end

    return db
end

local function NewProfile(name)
    local db = DB()
    local id = db.nextProfileId
    db.nextProfileId = id + 1
    local profile = {
        id = id,
        name = name or ("Profile " .. tostring(id)),
        enabled = false,
        channels = "LookingForGroup, Trade",
        phrases = "",
        excludePhrases = "",
        caseInsensitive = true,
        usePatterns = false,
    }
    table.insert(db.profiles, profile)
    return profile
end

local function ProfileById(profileId)
    profileId = tonumber(profileId)
    for _, profile in ipairs(DB().profiles) do
        if tonumber(profile.id) == profileId then return profile end
    end
    return nil
end

local function ProfileIndexById(profileId)
    profileId = tonumber(profileId)
    for index, profile in ipairs(DB().profiles) do
        if tonumber(profile.id) == profileId then return index end
    end
    return nil
end

local function SelectedProfile()
    local profile = ProfileById(selectedProfileId)
    if profile then return profile end
    profile = DB().profiles[1]
    selectedProfileId = profile and profile.id or nil
    return profile
end

local function SplitCommaList(text)
    local values = {}
    for value in string.gmatch(tostring(text or "") .. ",", "(.-),") do
        value = Trim(value)
        if value ~= "" then table.insert(values, value) end
    end
    return values
end

local function SplitPhraseLines(text)
    local values = {}
    text = tostring(text or "")
    text = string.gsub(text, "\r\n", "\n")
    text = string.gsub(text, "\r", "\n")
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        line = Trim(line)
        if line ~= "" then table.insert(values, line) end
    end
    return values
end

local CHANNEL_EVENT_ALIASES = {
    CHAT_MSG_SAY = { "say" },
    CHAT_MSG_YELL = { "yell" },
    CHAT_MSG_GUILD = { "guild" },
    CHAT_MSG_OFFICER = { "officer" },
    CHAT_MSG_PARTY = { "party" },
    CHAT_MSG_PARTY_LEADER = { "party", "partyleader" },
    CHAT_MSG_RAID = { "raid" },
    CHAT_MSG_RAID_LEADER = { "raid", "raidleader" },
    CHAT_MSG_RAID_WARNING = { "raid", "raidwarning" },
    CHAT_MSG_BATTLEGROUND = { "battleground", "bg" },
    CHAT_MSG_BATTLEGROUND_LEADER = { "battleground", "bg", "bgleader" },
    CHAT_MSG_WHISPER = { "whisper", "tell" },
    CHAT_MSG_EMOTE = { "emote" },
    CHAT_MSG_TEXT_EMOTE = { "emote" },
}

local CHANNEL_TOKEN_ALIASES = {
    lfg = "lookingforgroup",
    lookingforgroup = "lookingforgroup",
    trade = "trade",
    general = "general",
    localdefense = "localdefense",
    worlddefense = "worlddefense",
    raidwarning = "raidwarning",
    rw = "raidwarning",
    bg = "battleground",
    tell = "whisper",
}

local function NormalizeChannelToken(token)
    token = Lower(Trim(token))
    token = string.gsub(token, "^/", "")
    token = string.gsub(token, "[%s%-_]", "")
    return CHANNEL_TOKEN_ALIASES[token] or token
end

local function AddChannelCandidate(candidates, value)
    value = NormalizeChannelToken(value)
    if value ~= "" then candidates[value] = true end
end

local function ChannelCandidates(event, channelString, channelNumber, channelBaseName)
    local candidates = {}
    AddChannelCandidate(candidates, event)
    for _, alias in ipairs(CHANNEL_EVENT_ALIASES[event] or {}) do AddChannelCandidate(candidates, alias) end
    AddChannelCandidate(candidates, channelString)
    AddChannelCandidate(candidates, channelBaseName)
    if channelNumber ~= nil then AddChannelCandidate(candidates, tostring(channelNumber)) end
    return candidates
end

local function ChannelTokenMatches(token, candidates)
    token = NormalizeChannelToken(token)
    if token == "" then return false end
    if token == "all" or token == "*" then return true end
    for candidate in pairs(candidates) do
        if candidate == token or string.find(candidate, token, 1, true) or string.find(token, candidate, 1, true) then
            return true
        end
    end
    return false
end

local function ProfileChannelMatches(profile, event, channelString, channelNumber, channelBaseName)
    local tokens = SplitCommaList(profile and profile.channels or "")
    if #tokens == 0 then return false end
    local candidates = ChannelCandidates(event, channelString, channelNumber, channelBaseName)
    for _, token in ipairs(tokens) do
        if ChannelTokenMatches(token, candidates) then return true end
    end
    return false
end

local function FindWithPattern(message, pattern)
    local ok, startPos = pcall(string.find, message, pattern)
    if not ok then return false, tostring(startPos) end
    return startPos ~= nil, nil
end

local function PhraseMatches(profile, haystack, originalPhrase)
    local phrase = profile.caseInsensitive and Lower(originalPhrase) or originalPhrase
    if profile.usePatterns then
        local matched, err = FindWithPattern(haystack, phrase)
        return matched, err
    end
    return string.find(haystack, phrase, 1, true) ~= nil, nil
end

local function ProfileMessageMatches(profile, message)
    if not profile then return false, nil, "No profile" end
    local phrases = SplitPhraseLines(profile.phrases)
    if #phrases == 0 then return false, nil, nil end

    local haystack = tostring(message or "")
    if profile.caseInsensitive then haystack = Lower(haystack) end

    -- Exclusions are evaluated first. Any matching exclusion suppresses the alert.
    for _, excludedPhrase in ipairs(SplitPhraseLines(profile.excludePhrases)) do
        local excluded, err = PhraseMatches(profile, haystack, excludedPhrase)
        if err then return false, nil, err end
        if excluded then return false, nil, nil end
    end

    for _, originalPhrase in ipairs(phrases) do
        local matched, err = PhraseMatches(profile, haystack, originalPhrase)
        if err then return false, nil, err end
        if matched then return true, originalPhrase, nil end
    end
    return false, nil, nil
end

local function ValidateProfilePatterns(profile)
    if not profile or not profile.usePatterns then return nil end
    local function ValidateList(text, label)
        for _, phrase in ipairs(SplitPhraseLines(text)) do
            local testPhrase = profile.caseInsensitive and Lower(phrase) or phrase
            local _, err = FindWithPattern("", testPhrase)
            if err then return "Invalid " .. label .. " Lua pattern '" .. phrase .. "': " .. err end
        end
        return nil
    end
    return ValidateList(profile.phrases, "include") or ValidateList(profile.excludePhrases, "exclude")
end

local function IsProfileUsable(profile)
    return profile and profile.enabled and Trim(profile.channels) ~= "" and #SplitPhraseLines(profile.phrases) > 0 and not ValidateProfilePatterns(profile)
end

local function AnyActiveProfile()
    for _, profile in ipairs(DB().profiles) do
        if IsProfileUsable(profile) then return true end
    end
    return false
end

local function CleanupMutedUsers()
    local now = NowEpoch()
    for key, expiresAt in pairs(DB().mutedUsers) do
        if tonumber(expiresAt) == nil or tonumber(expiresAt) <= now then DB().mutedUsers[key] = nil end
    end
end

local function IsUserMuted(sender)
    CleanupMutedUsers()
    local key = Lower(NormalizePlayerName(sender))
    local expiresAt = tonumber(DB().mutedUsers[key])
    return expiresAt and expiresAt > NowEpoch() or false
end

local function MuteUser(sender, hours)
    sender = NormalizePlayerName(sender)
    hours = tonumber(hours) or tonumber(DB().defaultMuteHours) or 2
    if hours < 0.1 then hours = 0.1 end
    if hours > 168 then hours = 168 end
    DB().mutedUsers[Lower(sender)] = NowEpoch() + math.floor(hours * 3600)
    return hours
end

local function IsDuplicateAlert(sender, message, profileIds)
    local key = Lower(NormalizePlayerName(sender)) .. "|" .. tostring(message or "") .. "|" .. table.concat(profileIds or {}, ",")
    local now = MonotonicNow()
    for oldKey, seenAt in pairs(recentAlerts) do
        if now - seenAt > ALERT_DEDUPE_SECONDS then recentAlerts[oldKey] = nil end
    end
    if recentAlerts[key] and now - recentAlerts[key] <= ALERT_DEDUPE_SECONDS then return true end
    recentAlerts[key] = now
    return false
end

local function StartWhisper(sender)
    sender = NormalizePlayerName(sender)
    if sender == "" then return end
    if ChatFrame_SendTell then
        ChatFrame_SendTell(sender)
        return
    end
    local editBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
    if editBox and ChatEdit_ActivateChat then
        ChatEdit_ActivateChat(editBox)
        editBox:SetText("/w " .. sender .. " ")
        editBox:SetFocus()
    else
        Print("Unable to open whisper for " .. sender .. ".")
    end
end

local function PlayAlertSound()
    if not DB().playSound then return end
    if PlaySoundFile then
        local ok = pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.wav")
        if ok then return end
    end
    if PlaySound then pcall(PlaySound, "RaidWarning") end
end

local function MakeButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width or 90)
    button:SetHeight(height or 22)
    button:SetText(text or "")
    return button
end

local function MakeCheck(parent, label, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetWidth(24); check:SetHeight(24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label:SetText(label)
    return check
end

local function MakeEdit(parent, width, height, x, y)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetWidth(width); edit:SetHeight(height or 22)
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return edit
end

local function EstimateMultilineHeight(text, width, minimumHeight)
    text = tostring(text or "")
    local usableWidth = math.max(80, (tonumber(width) or 200) - 40)
    -- Avoid newer line-count methods that are not available on every 3.3.5 client.
    -- Estimate wrapped rows from the text itself using only Lua 5.1 functions.
    local charsPerRow = math.max(12, math.floor(usableWidth / 7))
    local rows = 0
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        rows = rows + math.max(1, math.ceil(string.len(line) / charsPerRow))
    end
    return math.max(tonumber(minimumHeight) or 22, (rows * 15) + 16)
end

local function MakeMultilineEdit(parent, name, width, height, x, y)
    -- 3.3.5's ScrollFrame template has no visible edit-box border of its own.
    -- Keep an explicit border around the complete field so the right/bottom edge
    -- cannot visually disappear behind the scrollbar or parent background.
    local border = CreateFrame("Frame", name .. "Border", parent)
    border:SetWidth(width); border:SetHeight(height)
    border:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    border:SetBackdropColor(0.01, 0.01, 0.01, 0.78)
    border:SetBackdropBorderColor(0.40, 0.40, 0.40, 0.95)

    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", border, "UIPanelScrollFrameTemplate")
    scroll:SetWidth(width - 10); scroll:SetHeight(height - 10)
    scroll:SetPoint("TOPLEFT", border, "TOPLEFT", 5, -5)

    local edit = CreateFrame("EditBox", name .. "Edit", scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetWidth(width - 42)
    edit:SetHeight(height - 10)
    edit:SetTextInsets(6, 6, 6, 6)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self)
        self:SetHeight(EstimateMultilineHeight(self:GetText(), width - 10, height - 10))
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    end)
    scroll:SetScrollChild(edit)
    scroll.border = border
    edit.border = border
    return scroll, edit
end

local PATTERN_HELP_TEXT = [[Lua patterns are the pattern language built into WoW's Lua 5.1.
They are similar to regular expressions, but they are not full PCRE regex.

PROFILE RULES
- Include phrases: one phrase or pattern per line.
- Multiple include lines are OR: any matching include line can trigger the profile.
- Exclude phrases: one phrase or pattern per line; ANY matching exclude line blocks the alert.
- Exclusions are checked before includes.
- "Case insensitive" applies to both include and exclude phrases.
- "Use Lua patterns" applies to both include and exclude phrases.
- Without "Use Lua patterns", every line is searched as literal text.

EXCLUDE EXAMPLE
Include phrase: ICC 25
Exclude phrase: LFG
"LFM ICC 25 HC" matches, while "LFG ICC 25" is suppressed.

COMMON PATTERN ELEMENTS
.       any single character
%s      whitespace character
%d      digit 0-9
%a      letter
%w      letter or digit
%c      control character
%p      punctuation
%x      hexadecimal character
[abc]   one character from the set
[^abc]  one character not in the set
+       one or more repetitions
*       zero or more repetitions
-       zero or more, shortest match
?       zero or one occurrence
^       start of the chat message
$       end of the chat message
%       escapes a special pattern character

EXAMPLES
ICC%s*25
Matches: ICC25, ICC 25, ICC     25

^LFM
Matches only messages beginning with LFM.

%d+/%d+
Matches group counts such as 18/25 or 4/10.

ICC.*HC
Matches ICC followed later by HC in the same message.

10%%
Matches the literal text 10%.

3%.3%.5
Matches the literal text 3.3.5.

IMPORTANT DIFFERENCES FROM PCRE
- There is no alternation with |. Put alternatives on separate lines.
- Parentheses create captures; they do not make (10|25) work.
- Invalid patterns are caught when saving and the profile is disabled.]]

EnsurePatternHelp = function()
    if helpFrame then return helpFrame end

    local h = CreateFrame("Frame", "WowNoteChatWatcherPatternHelp", UIParent)
    h:SetWidth(610); h:SetHeight(520)
    h:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    h:SetFrameStrata("FULLSCREEN_DIALOG")
    h:SetToplevel(true)
    h:SetMovable(true); h:EnableMouse(true); h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function(self) self:StartMoving() end)
    h:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    h:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    h:Hide()

    h.title = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    h.title:SetPoint("TOP", h, "TOP", 0, -18)
    h.title:SetText("Chat Watcher - Lua Pattern Help")

    local close = CreateFrame("Button", nil, h, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", h, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() h:Hide() end)

    h.intro = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.intro:SetPoint("TOPLEFT", h, "TOPLEFT", 24, -48)
    h.intro:SetWidth(560); h.intro:SetJustifyH("LEFT")
    h.intro:SetText("The text below can be selected and copied. Each profile treats separate lines as alternatives.")

    local helpScroll
    helpScroll, h.text = MakeMultilineEdit(h, "WowNoteChatWatcherPatternHelpText", 555, 405, 24, -72)
    h.text:SetText(PATTERN_HELP_TEXT)
    h.text:SetCursorPosition(0)

    h.closeButton = MakeButton(h, "Close", 100, 24)
    h.closeButton:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -24, 20)
    h.closeButton:SetScript("OnClick", function() h:Hide() end)

    helpFrame = h
    return h
end

local function SaveSelectedProfileFromUI()
    if not frame then return false end
    local profile = SelectedProfile()
    if not profile then return false end

    profile.name = Trim(frame.profileName:GetText())
    if profile.name == "" then profile.name = "Profile " .. tostring(profile.id) end
    profile.enabled = frame.profileEnabled:GetChecked() and true or false
    profile.channels = Trim(frame.channels:GetText())
    profile.phrases = frame.phrases:GetText() or ""
    profile.excludePhrases = frame.excludePhrases:GetText() or ""
    profile.caseInsensitive = frame.caseInsensitive:GetChecked() and true or false
    profile.usePatterns = frame.usePatterns:GetChecked() and true or false

    local patternError = ValidateProfilePatterns(profile)
    if patternError then
        profile.enabled = false
        frame.profileEnabled:SetChecked(false)
        frame.status:SetText(patternError .. " Profile was disabled.")
    else
        frame.status:SetText("Saved profile '" .. profile.name .. "'.")
    end

    if RefreshEventRegistrations then RefreshEventRegistrations() end
    return patternError == nil
end

local function SelectProfile(profileId)
    if frame then SaveSelectedProfileFromUI() end
    selectedProfileId = tonumber(profileId)
    if RefreshUI then RefreshUI() end
end

local function DeleteSelectedProfile()
    local db = DB()
    local index = ProfileIndexById(selectedProfileId)
    if not index then return end
    table.remove(db.profiles, index)
    if #db.profiles == 0 then NewProfile("ICC 25") end
    local nextProfile = db.profiles[math.min(index, #db.profiles)] or db.profiles[1]
    selectedProfileId = nextProfile and nextProfile.id or nil
    if RefreshEventRegistrations then RefreshEventRegistrations() end
    if RefreshUI then RefreshUI() end
end

local function AlertProfileNames(alert)
    return table.concat(alert.profileNames or {}, ", ")
end

local function DismissCurrentAlert()
    currentAlert = nil
    if popup then popup:Hide() end
    if ShowNextAlert then ShowNextAlert() end
end

local function DisableMatchedProfiles(alert)
    for _, profileId in ipairs(alert and alert.profileIds or {}) do
        local profile = ProfileById(profileId)
        if profile then profile.enabled = false end
    end
    if RefreshEventRegistrations then RefreshEventRegistrations() end
    if RefreshUI then RefreshUI() end
end

local function EnsurePopup()
    if popup then return popup end

    local p = CreateFrame("Frame", "WowNoteChatWatcherPopup", UIParent)
    p:SetWidth(580); p:SetHeight(330)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetToplevel(true)
    p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function(self) self:StartMoving() end)
    p:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    p:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    p:Hide()

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    p.title:SetPoint("TOP", p, "TOP", 0, -18)
    p.title:SetText("Chat Watcher Match")

    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", DismissCurrentAlert)

    p.meta = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.meta:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -52)
    p.meta:SetWidth(530); p.meta:SetJustifyH("LEFT")

    p.senderLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.senderLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -78)
    p.senderLabel:SetText("Sender")

    p.sender = MakeEdit(p, 270, 22, 90, -72)
    p.sender:SetScript("OnTextChanged", function(self)
        if currentAlert and not p.settingSender then currentAlert.sender = NormalizePlayerName(self:GetText()) end
    end)

    p.copyName = MakeButton(p, "Select name", 100, 22)
    p.copyName:SetPoint("LEFT", p.sender, "RIGHT", 8, 0)
    p.copyName:SetScript("OnClick", function()
        p.sender:SetFocus(); p.sender:HighlightText()
    end)

    p.whisper = MakeButton(p, "Whisper", 90, 22)
    p.whisper:SetPoint("LEFT", p.copyName, "RIGHT", 8, 0)
    p.whisper:SetScript("OnClick", function()
        if currentAlert then StartWhisper(currentAlert.sender) end
    end)
    p.whisper:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Open whisper")
        GameTooltip:AddLine("Uses WoW's normal whisper flow. WIM can intercept this and open its whisper window.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.whisper:SetScript("OnLeave", function() GameTooltip:Hide() end)

    p.messageLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.messageLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -110)
    p.messageLabel:SetText("Complete chat message")

    local messageScroll
    messageScroll, p.message = MakeMultilineEdit(p, "WowNoteChatWatcherPopupMessage", 525, 105, 24, -130)
    p.message:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    p.copyMessage = MakeButton(p, "Select message", 110, 22)
    p.copyMessage:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -246)
    p.copyMessage:SetScript("OnClick", function()
        p.message:SetFocus(); p.message:HighlightText()
    end)

    p.muteHoursLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.muteHoursLabel:SetPoint("LEFT", p.copyMessage, "RIGHT", 10, 0)
    p.muteHoursLabel:SetText("Mute hours:")
    p.muteHours = MakeEdit(p, 44, 22, 0, 0)
    p.muteHours:ClearAllPoints(); p.muteHours:SetPoint("LEFT", p.muteHoursLabel, "RIGHT", 6, 0)

    p.mute = MakeButton(p, "Mute sender", 100, 22)
    p.mute:SetPoint("LEFT", p.muteHours, "RIGHT", 7, 0)
    p.mute:SetScript("OnClick", function()
        if not currentAlert then return end
        local hours = MuteUser(currentAlert.sender, p.muteHours:GetText())
        Print(currentAlert.sender .. " muted in Chat Watcher for " .. tostring(hours) .. " hour(s).")
        DismissCurrentAlert()
    end)

    p.disableProfile = MakeButton(p, "Disable profile(s)", 125, 22)
    p.disableProfile:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -280)
    p.disableProfile:SetScript("OnClick", function()
        DisableMatchedProfiles(currentAlert)
        DismissCurrentAlert()
    end)

    p.pause = MakeButton(p, "Pause watcher", 110, 22)
    p.pause:SetPoint("LEFT", p.disableProfile, "RIGHT", 8, 0)
    p.pause:SetScript("OnClick", function()
        DB().enabled = false
        if RefreshEventRegistrations then RefreshEventRegistrations() end
        if RefreshUI then RefreshUI() end
        DismissCurrentAlert()
    end)

    p.dismiss = MakeButton(p, "Dismiss / next", 110, 22)
    p.dismiss:SetPoint("RIGHT", p, "RIGHT", -24, 0)
    p.dismiss:SetPoint("TOP", p, "TOP", 0, -280)
    p.dismiss:SetScript("OnClick", DismissCurrentAlert)

    popup = p
    return p
end

ShowNextAlert = function()
    if currentAlert or #alertQueue == 0 then return end
    currentAlert = table.remove(alertQueue, 1)
    local p = EnsurePopup()
    p.meta:SetText(
        "Profile: " .. AlertProfileNames(currentAlert) ..
        "  |  Channel: " .. tostring(currentAlert.channelLabel or currentAlert.event or "?") ..
        "  |  Queue: " .. tostring(#alertQueue)
    )
    p.settingSender = true
    p.sender:SetText(currentAlert.sender or "")
    p.settingSender = false
    p.message:SetText(currentAlert.message or "")
    p.message:SetCursorPosition(0)
    p.muteHours:SetText(tostring(DB().defaultMuteHours or 2))
    p:Show(); if p.Raise then p:Raise() end
    PlayAlertSound()
end

local function EnqueueAlert(alert)
    if IsDuplicateAlert(alert.sender, alert.message, alert.profileIds) then return end
    table.insert(alertQueue, alert)
    if ShowNextAlert then ShowNextAlert() end
end

local function ProcessChatMessage(event, message, sender, language, channelString, target, flags, unknown, channelNumber, channelBaseName)
    local db = DB()
    if not db.enabled or not AnyActiveProfile() then return end

    sender = NormalizePlayerName(sender)
    if sender == "" or IsUserMuted(sender) then return end
    if UnitName and NormalizePlayerName(UnitName("player")) == sender then return end

    local matchedIds, matchedNames, matchedPhrases = {}, {}, {}
    for _, profile in ipairs(db.profiles) do
        if IsProfileUsable(profile) and ProfileChannelMatches(profile, event, channelString, channelNumber, channelBaseName) then
            local matched, phrase = ProfileMessageMatches(profile, message)
            if matched then
                table.insert(matchedIds, profile.id)
                table.insert(matchedNames, profile.name)
                table.insert(matchedPhrases, phrase or "")
            end
        end
    end

    if #matchedIds == 0 then return end
    EnqueueAlert({
        event = event,
        channelLabel = channelBaseName or channelString or event,
        sender = sender,
        message = tostring(message or ""),
        profileIds = matchedIds,
        profileNames = matchedNames,
        matchedPhrases = matchedPhrases,
        receivedAt = NowEpoch(),
    })
end

local CHAT_EVENTS = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_BATTLEGROUND",
    "CHAT_MSG_BATTLEGROUND_LEADER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
}

RefreshEventRegistrations = function()
    if not eventFrame then return end
    for _, event in ipairs(CHAT_EVENTS) do eventFrame:UnregisterEvent(event) end
    if DB().enabled and AnyActiveProfile() then
        for _, event in ipairs(CHAT_EVENTS) do eventFrame:RegisterEvent(event) end
    end
end

Initialize = function()
    if initialized then return true end
    if not eventFrame then return false end

    DB()
    CleanupMutedUsers()
    if RefreshEventRegistrations then RefreshEventRegistrations() end
    initialized = true
    return true
end

local function CreateUI()
    if frame then return frame end

    local f = CreateFrame("Frame", "WowNoteChatWatcherFrame", UIParent)
    f:SetWidth(820); f:SetHeight(640)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -18)
    f.title:SetText(MODULE_TITLE)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() SaveSelectedProfileFromUI(); f:Hide() end)

    f.globalEnabled = MakeCheck(f, "Watcher active", 22, -48)
    f.globalEnabled:SetScript("OnClick", function(self)
        DB().enabled = self:GetChecked() and true or false
        if RefreshEventRegistrations then RefreshEventRegistrations() end
        if RefreshUI then RefreshUI() end
    end)

    f.playSound = MakeCheck(f, "Sound", 180, -48)
    f.playSound:SetScript("OnClick", function(self) DB().playSound = self:GetChecked() and true or false end)

    f.muteHoursLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.muteHoursLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 300, -53)
    f.muteHoursLabel:SetText("Default mute hours")
    f.defaultMuteHours = MakeEdit(f, 48, 22, 410, -46)
    f.defaultMuteHours:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText()) or 2
        if value < 0.1 then value = 0.1 elseif value > 168 then value = 168 end
        DB().defaultMuteHours = value
        self:SetText(tostring(value))
    end)

    f.listTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.listTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -86)
    f.listTitle:SetText("Profiles")

    for i = 1, MAX_PROFILE_ROWS do
        local button = MakeButton(f, "", 185, 28)
        button:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -108 - ((i - 1) * 31))
        button:SetScript("OnClick", function(self)
            if self.profileId then SelectProfile(self.profileId) end
        end)
        profileRows[i] = button
    end

    f.prev = MakeButton(f, "Prev", 82, 22)
    f.prev:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -415)
    f.prev:SetScript("OnClick", function()
        SaveSelectedProfileFromUI()
        profileOffset = math.max(0, profileOffset - MAX_PROFILE_ROWS)
        if RefreshUI then RefreshUI() end
    end)
    f.next = MakeButton(f, "Next", 82, 22)
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 12, 0)
    f.next:SetScript("OnClick", function()
        SaveSelectedProfileFromUI()
        profileOffset = profileOffset + MAX_PROFILE_ROWS
        if RefreshUI then RefreshUI() end
    end)

    f.newProfile = MakeButton(f, "New profile", 185, 24)
    f.newProfile:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -455)
    f.newProfile:SetScript("OnClick", function()
        SaveSelectedProfileFromUI()
        local profile = NewProfile()
        selectedProfileId = profile.id
        profileOffset = math.max(0, #DB().profiles - MAX_PROFILE_ROWS)
        if RefreshUI then RefreshUI() end
    end)

    f.deleteProfile = MakeButton(f, "Delete profile", 185, 24)
    f.deleteProfile:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -487)
    f.deleteProfile:SetScript("OnClick", DeleteSelectedProfile)

    f.testProfile = MakeButton(f, "Test popup", 185, 24)
    f.testProfile:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -519)
    f.testProfile:SetScript("OnClick", function()
        SaveSelectedProfileFromUI()
        local profile = SelectedProfile()
        if not profile then return end
        local phrase = SplitPhraseLines(profile.phrases)[1] or "Test message"
        EnqueueAlert({
            event = "TEST",
            channelLabel = "Test",
            sender = "TestPlayer",
            message = "Test: " .. phrase,
            profileIds = { profile.id },
            profileNames = { profile.name },
            matchedPhrases = { phrase },
        })
    end)

    f.profileTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.profileTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -86)
    f.profileTitle:SetText("Selected profile")

    f.nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.nameLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -112)
    f.nameLabel:SetText("Profile name")
    f.profileName = MakeEdit(f, 300, 22, 350, -105)

    f.profileEnabled = MakeCheck(f, "Profile active", 668, -108)

    f.channelsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.channelsLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -146)
    f.channelsLabel:SetText("Channels, comma-separated")
    f.channels = MakeEdit(f, 525, 22, 245, -163)

    f.channelsHelp = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.channelsHelp:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -190)
    f.channelsHelp:SetWidth(525); f.channelsHelp:SetJustifyH("LEFT")
    f.channelsHelp:SetText("Examples: LookingForGroup, Trade, General, Raid, Guild, 4, *")

    f.phrasesLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.phrasesLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -214)
    f.phrasesLabel:SetText("Include phrases — one per line; any matching line triggers")
    local phraseScroll
    phraseScroll, f.phrases = MakeMultilineEdit(f, "WowNoteChatWatcherPhrases", 525, 105, 245, -234)

    f.excludeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.excludeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -350)
    f.excludeLabel:SetText("Exclude phrases — one per line; any match blocks the alert")
    local excludeScroll
    excludeScroll, f.excludePhrases = MakeMultilineEdit(f, "WowNoteChatWatcherExcludePhrases", 525, 80, 245, -370)

    f.caseInsensitive = MakeCheck(f, "Case insensitive", 245, -462)
    f.usePatterns = MakeCheck(f, "Use Lua patterns", 455, -462)
    f.usePatterns:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Lua patterns")
        GameTooltip:AddLine("WoW 3.3.5 uses Lua 5.1 patterns, not full PCRE regex. Examples: ICC%s*25, ^LFM, %d+/%d+.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.usePatterns:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.save = MakeButton(f, "Save profile", 120, 26)
    f.save:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -500)
    f.save:SetScript("OnClick", function() SaveSelectedProfileFromUI(); if RefreshUI then RefreshUI() end end)

    f.patternHelpButton = MakeButton(f, "Lua pattern help", 135, 24)
    f.patternHelpButton:SetPoint("LEFT", f.save, "RIGHT", 12, 0)
    f.patternHelpButton:SetScript("OnClick", function()
        local h = EnsurePatternHelp and EnsurePatternHelp() or nil
        if h then
            h.text:SetText(PATTERN_HELP_TEXT)
            h.text:SetCursorPosition(0)
            h:Show()
            if h.Raise then h:Raise() end
        end
    end)

    f.patternHelp = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.patternHelp:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -538)
    f.patternHelp:SetWidth(525); f.patternHelp:SetJustifyH("LEFT")
    f.patternHelp:SetText("Includes use OR. Any matching exclude blocks the alert. Case/pattern settings apply to both lists. Click 'Lua pattern help' for syntax.")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 245, -590)
    f.status:SetWidth(525); f.status:SetJustifyH("LEFT")

    frame = f
    return f
end

RefreshUI = function()
    if not frame then return end
    local db = DB()
    local profile = SelectedProfile()

    local maxOffset = math.max(0, #db.profiles - MAX_PROFILE_ROWS)
    if profileOffset > maxOffset then profileOffset = maxOffset end

    frame.globalEnabled:SetChecked(db.enabled and true or false)
    frame.playSound:SetChecked(db.playSound and true or false)
    frame.defaultMuteHours:SetText(tostring(db.defaultMuteHours or 2))

    for rowIndex = 1, MAX_PROFILE_ROWS do
        local button = profileRows[rowIndex]
        local profileIndex = profileOffset + rowIndex
        local rowProfile = db.profiles[profileIndex]
        if rowProfile then
            button.profileId = rowProfile.id
            local prefix = rowProfile.enabled and "|cff3399ff[ON]|r " or "|cff888888[OFF]|r "
            button:SetText(prefix .. tostring(rowProfile.name or ("Profile " .. tostring(rowProfile.id))))
            button:SetAlpha(tonumber(rowProfile.id) == tonumber(selectedProfileId) and 1 or 0.78)
            button:Show()
        else
            button.profileId = nil
            button:Hide()
        end
    end

    if profileOffset > 0 then frame.prev:Enable() else frame.prev:Disable() end
    if profileOffset < maxOffset then frame.next:Enable() else frame.next:Disable() end

    if profile then
        frame.profileName:SetText(profile.name or "")
        frame.profileEnabled:SetChecked(profile.enabled and true or false)
        frame.channels:SetText(profile.channels or "")
        frame.phrases:SetText(profile.phrases or "")
        frame.excludePhrases:SetText(profile.excludePhrases or "")
        frame.caseInsensitive:SetChecked(profile.caseInsensitive and true or false)
        frame.usePatterns:SetChecked(profile.usePatterns and true or false)
        local patternError = ValidateProfilePatterns(profile)
        if patternError then
            frame.status:SetText(patternError)
        elseif db.enabled and IsProfileUsable(profile) then
            frame.status:SetText("Watcher and profile are active.")
        elseif not db.enabled then
            frame.status:SetText("Watcher is paused globally.")
        elseif not profile.enabled then
            frame.status:SetText("This profile is inactive.")
        else
            frame.status:SetText("Enter channels and at least one include phrase.")
        end
    end
end

function WowNote_OpenChatWatcher()
    if Initialize then Initialize() end
    local f = CreateUI()
    f:Show(); if f.Raise then f:Raise() end
    if RefreshUI then RefreshUI() end
end

function WowNote_ChatWatcher_OpenPatternHelp()
    if Initialize then Initialize() end
    local h = EnsurePatternHelp and EnsurePatternHelp() or nil
    if not h then return end
    h.text:SetText(PATTERN_HELP_TEXT)
    h.text:SetCursorPosition(0)
    h:Show(); if h.Raise then h:Raise() end
end

function WowNote_ChatWatcher_TestProfile(profile, message, event, channelString, channelNumber, channelBaseName)
    if Initialize then Initialize() end
    local channelMatch = ProfileChannelMatches(profile, event or "CHAT_MSG_CHANNEL", channelString or "LookingForGroup", channelNumber, channelBaseName)
    local messageMatch, phrase, err = ProfileMessageMatches(profile, message)
    return channelMatch and messageMatch, phrase, err
end

function WowNote_ChatWatcher_TestMessage(message, sender, channelString)
    if Initialize then Initialize() end
    ProcessChatMessage("CHAT_MSG_CHANNEL", message, sender or "TestPlayer", nil, channelString or "LookingForGroup", nil, nil, nil, nil, channelString)
end

eventFrame = CreateFrame("Frame", "WowNoteChatWatcherEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == ADDON_NAME and Initialize then
            Initialize()
        end
        return
    end
    ProcessChatMessage(event, ...)
end)
