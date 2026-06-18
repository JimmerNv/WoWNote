local ADDON_NAME = "WowNote"
local TITAN_ID = "WowNote"
local WOWNOTE_NOTE_FORMAT_VERSION = "1.0.0"
local WOWNOTE_TALENT_FORMAT_VERSION = "1.0.0"

WowNoteDB = WowNoteDB or nil

local frame
local listFrame
local menuFrame
local talentFrame
local talentClassDropDown
local talentClassText
local talentPointsText
local talentTreeFrames = {}
local talentButtons = {}
local itemFrame
local itemListFrame
local itemLinkEdit
local itemNameEdit
local itemStatusText
local itemButtons = {}
local currentItemGuid = nil
local shareFrame
local shareTargetEdit
local shareAuthEdit
local shareReceiveButton
local shareReceiveCodeText
local shareReceiveStatusText
local shareStatusText
local dataReceiveEnabled = false
local dataReceiveCode = nil
local incomingTransfers = {}
local pendingIncomingNotes = {}
local pendingIncomingTransferRequests = {}
local approvedIncomingTransfers = {}
local titleEdit
local contentEdit
local contentScroll
local contentViewFrame
local contentViewText
local contentViewMessage
local contentModeText
local editToggleButton
local editMode = false
local statusText
local currentGuid = nil
local randomSeeded = false
local buttons = {}
local activeEditBox = nil
local originalChatEditInsertLink = nil

local InitDB
local RefreshList
local ClearEditor
local LoadNote
local SaveNote
local DeleteNote
local SetEditMode
local RefreshMarkdownView
local ShowNoteContextMenu
local InsertCursorItemLink
local CreateTalentUI
local WowNote_OpenTalents
local CreateItemUI
local WowNote_OpenItems
local RefreshItemList
local SaveItem
local DeleteItem
local InsertSelectedItemIntoNote
local ShowItemContextMenu
local CreateShareUI
local WowNote_OpenShare
local SendCurrentNoteToPlayer
local HandleAddonMessage
local CreateUI
local HookItemLinks

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg))
end

local function Trim(text)
    text = text or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function SetShareStatus(message)
    if shareStatusText then
        shareStatusText:SetText(tostring(message or ""))
    end
end

local function BuildReceiveCode()
    if not randomSeeded then
        randomSeeded = true
        local seed = time and time() or 1
        if GetTime and math and math.floor then
            seed = seed + math.floor(GetTime() * 100000)
        end
        if math and math.randomseed then
            math.randomseed(seed)
        elseif randomseed then
            randomseed(seed)
        end
    end
    local value
    if math and math.random then
        value = math.random(1000, 9999)
    elseif random then
        value = random(1000, 9999)
    else
        value = 1000
    end
    value = tonumber(value) or 1000
    if value < 1000 then value = value + 1000 end
    if value > 9999 then value = 9999 end
    return string.format("%04d", value)
end

local function RefreshReceiveStatus()
    if shareReceiveButton then
        shareReceiveButton:SetText(dataReceiveEnabled and "Receive: ON" or "Receive: OFF")
    end
    if shareReceiveCodeText then
        if dataReceiveEnabled and dataReceiveCode then
            shareReceiveCodeText:SetText("Receive code: " .. tostring(dataReceiveCode))
        else
            shareReceiveCodeText:SetText("Receive code: disabled")
        end
    end
    if shareReceiveStatusText then
        if dataReceiveEnabled then
            shareReceiveStatusText:SetText("Only transfers with this code are accepted while this window stays open.")
        else
            shareReceiveStatusText:SetText("Receiving is blocked. Enable it before someone sends data.")
        end
    end
end

local function SetDataReceiveEnabled(enabled)
    dataReceiveEnabled = enabled and true or false
    if dataReceiveEnabled and (not dataReceiveCode or dataReceiveCode == "") then
        dataReceiveCode = BuildReceiveCode()
    end
    RefreshReceiveStatus()
end

local function IsDataReceiveAllowed(authCode)
    if not shareFrame or not shareFrame:IsShown() or not dataReceiveEnabled then
        return false, "receive-disabled"
    end
    authCode = Trim(authCode or "")
    if not dataReceiveCode or dataReceiveCode == "" or authCode ~= tostring(dataReceiveCode) then
        return false, "bad-code"
    end
    return true, nil
end

local function IsValidReceiverCode(authCode)
    authCode = Trim(authCode or "")
    return string.match(authCode, "^%d%d%d%d$") ~= nil
end

local function ShowHyperlinkTooltip(owner, linkData)
    if not linkData or linkData == "" then return end
    GameTooltip:SetOwner(owner or UIParent, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(linkData)
    GameTooltip:Show()
end

local function HideHyperlinkTooltip()
    GameTooltip:Hide()
end

local function ChatLinkFromHyperlink(linkData, linkText, linkButton)
    if not linkData or linkData == "" then return end
    local color = "|cffffffff"
    if string.sub(linkData, 1, 5) == "item:" then
        color = "|cffffffff"
    elseif string.sub(linkData, 1, 6) == "spell:" then
        color = "|cffffd000"
    end
    return color .. "|H" .. linkData .. "|h[" .. (linkText or linkData) .. "]|h|r"
end

local function HandleHyperlinkClick(self, linkData, linkText, button)
    if not linkData or linkData == "" then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
        local chatLink = ChatLinkFromHyperlink(linkData, linkText, button)
        if chatLink and ChatEdit_InsertLink then
            ChatEdit_InsertLink(chatLink)
        end
        return
    end
    ShowHyperlinkTooltip(self, linkData)
end

local function WowNote_Random(minValue, maxValue)
    if math and math.random then
        return math.random(minValue, maxValue)
    end
    if random then
        return random(minValue, maxValue)
    end
    return 0
end

local function SeedRandom()
    if randomSeeded then return end
    randomSeeded = true

    local seed = time and time() or 1
    if GetTime and math and math.floor then
        seed = seed + math.floor(GetTime() * 100000)
    end

    if math and math.randomseed then
        math.randomseed(seed)
    elseif randomseed then
        randomseed(seed)
    end

    WowNote_Random(0, 2147483647)
    WowNote_Random(0, 2147483647)
    WowNote_Random(0, 2147483647)
end

local function RandomHex(length)
    local chars = {}
    for i = 1, length do
        chars[i] = string.format("%x", WowNote_Random(0, 15))
    end
    return table.concat(chars)
end

local function GenerateGUID()
    SeedRandom()

    local guid
    repeat
        guid = RandomHex(8) .. "-" .. RandomHex(4) .. "-4" .. RandomHex(3) .. "-" .. RandomHex(4) .. "-" .. RandomHex(12)
    until not WowNoteDB.notes[guid]

    return guid
end

local function IsGuidKey(value)
    return type(value) == "string" and string.match(value, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local function MigrateNotesToGuids()
    if type(WowNoteDB.notes) ~= "table" then return end

    local migrated = {}
    local changed = false

    for key, note in pairs(WowNoteDB.notes) do
        if type(note) == "string" then
            local guid = GenerateGUID()
            migrated[guid] = {
                guid = guid,
                version = WOWNOTE_NOTE_FORMAT_VERSION,
                title = Trim(tostring(key or "")) ~= "" and tostring(key) or "Untitled",
                content = note,
                created = time and time() or 0,
                updated = time and time() or 0,
            }
            changed = true
        elseif type(note) == "table" then
            local guid = nil
            if IsGuidKey(key) then
                guid = key
            elseif IsGuidKey(note.guid) then
                guid = note.guid
                changed = true
            else
                guid = GenerateGUID()
                changed = true
            end

            note.guid = guid
            if not note.version or Trim(note.version or "") == "" then
                note.version = WOWNOTE_NOTE_FORMAT_VERSION
                changed = true
            end
            migrated[guid] = note
        else
            changed = true
        end
    end

    if changed then
        WowNoteDB.notes = migrated
    end
end

InitDB = function()
    if type(WowNoteDB) ~= "table" then
        WowNoteDB = {}
    end
    if type(WowNoteDB.notes) ~= "table" then
        WowNoteDB.notes = {}
    end
    if type(WowNoteDB.talentPlans) ~= "table" then
        WowNoteDB.talentPlans = {}
    end
    if type(WowNoteDB.items) ~= "table" then
        WowNoteDB.items = {}
    end
    if type(WowNoteDB.share) ~= "table" then
        WowNoteDB.share = { sent = 0, received = 0 }
    end
    if type(WowNoteDB.raidPlannerPresets) ~= "table" then
        WowNoteDB.raidPlannerPresets = {}
    end
    if type(WowNoteDB.modules) ~= "table" then WowNoteDB.modules = {} end
    if type(WowNoteDB.characterNoteOptions) ~= "table" then WowNoteDB.characterNoteOptions = {} end
    if type(WowNoteDB.social) ~= "table" then WowNoteDB.social = {} end
    if type(WowNoteDB.minimap) ~= "table" then WowNoteDB.minimap = {} end
    if type(WowNoteDB.characterNotes) ~= "table" then WowNoteDB.characterNotes = {} end
    if type(WowNoteDB.tacticalMaps) ~= "table" then WowNoteDB.tacticalMaps = {} end
    if type(WowNoteDB.pallyCompat) ~= "table" then WowNoteDB.pallyCompat = {} end
    if type(WowNoteDB.raidIds) ~= "table" then WowNoteDB.raidIds = {} end
    if type(WowNoteDB.raidPlannerPortHelper) ~= "table" then WowNoteDB.raidPlannerPortHelper = {} end
    if type(WowNoteDB.inventorySnapshots) ~= "table" then WowNoteDB.inventorySnapshots = {} end
    if type(WowNoteDB.bankSnapshots) ~= "table" then WowNoteDB.bankSnapshots = {} end
    if type(WowNoteDB.cursorEffects) ~= "table" then WowNoteDB.cursorEffects = {} end
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.cursorEffects) ~= "table" then WowNoteCharDB.cursorEffects = {} end
    MigrateNotesToGuids()
end

local function CountNotes()
    local count = 0
    for _ in pairs(WowNoteDB.notes) do
        count = count + 1
    end
    return count
end

local function SortNotes()
    local sorted = {}
    for guid, note in pairs(WowNoteDB.notes) do
        table.insert(sorted, { guid = guid, title = note.title or "" })
    end
    table.sort(sorted, function(a, b)
        return string.lower(a.title or "") < string.lower(b.title or "")
    end)
    return sorted
end

local function SetStatus(text)
    if statusText then
        statusText:SetText(text or "")
    end
end

local function UpdateTitan()
    if TitanPanelButton_UpdateButton then
        TitanPanelButton_UpdateButton(TITAN_ID)
    end
    if TitanPanelButton_UpdateTooltip then
        TitanPanelButton_UpdateTooltip()
    end
end

local function EscapeWowPipes(text)
    text = text or ""
    text = string.gsub(text, "||", "\001")
    return text
end

local function RestoreWowPipes(text)
    text = text or ""
    text = string.gsub(text, "\001", "||")
    return text
end

local function ApplyInlineMarkdown(line)
    line = line or ""

    -- WoW item links already use pipe/color syntax. Leave them untouched and only
    -- apply conservative inline formatting around normal text.
    line = EscapeWowPipes(line)
    line = string.gsub(line, "`([^`]+)`", "|cffcccccc%1|r")
    line = string.gsub(line, "%*%*([^%*]+)%*%*", "|cffffd200%1|r")
    line = string.gsub(line, "__([^_]+)__", "|cffffd200%1|r")
    line = string.gsub(line, "%*([^%*]+)%*", "|cffbbbbff%1|r")
    line = string.gsub(line, "_([^_]+)_", "|cffbbbbff%1|r")
    line = string.gsub(line, "%[([^%]]+)%]%(([^%)]+)%)", "|cff66ccff%1|r <|cff999999%2|r>")
    return RestoreWowPipes(line)
end

local function RenderMarkdown(markdown)
    markdown = markdown or ""
    markdown = string.gsub(markdown, "\r\n", "\n")
    markdown = string.gsub(markdown, "\r", "\n")

    local rendered = {}
    for line in string.gmatch(markdown .. "\n", "(.-)\n") do
        local out = line
        local heading = string.match(line, "^(#+)%s+(.+)$")
        if heading then
            local hashes, text = string.match(line, "^(#+)%s+(.+)$")
            if string.len(hashes) == 1 then
                out = "|cffffd200" .. ApplyInlineMarkdown(text) .. "|r"
            elseif string.len(hashes) == 2 then
                out = "|cffffee88" .. ApplyInlineMarkdown(text) .. "|r"
            else
                out = "|cffdddddd" .. ApplyInlineMarkdown(text) .. "|r"
            end
        elseif string.match(line, "^%s*%-%-%-+%s*$") or string.match(line, "^%s*___+%s*$") or string.match(line, "^%s*%*%*%*+%s*$") then
            -- Markdown horizontal rule. Keep this check before list handling so
            -- a line containing only '---' is not treated as plain text.
            out = "|cff777777------------------------------------------------------------|r"
        elseif string.match(line, "^%s*[-%*+]%s+.+") then
            out = string.gsub(line, "^%s*[-%*+]%s+", "  |cffffd200•|r ")
            out = ApplyInlineMarkdown(out)
        elseif string.match(line, "^%s*%d+%.%s+.+") then
            out = ApplyInlineMarkdown(line)
        elseif string.match(line, "^%s*>%s+.+") then
            out = string.gsub(line, "^%s*>%s+", "")
            out = "|cffaaaaaa> " .. ApplyInlineMarkdown(out) .. "|r"
        else
            out = ApplyInlineMarkdown(line)
        end
        table.insert(rendered, out)
    end

    local result = table.concat(rendered, "\n")
    if result == "" then
        result = "|cff777777No content.|r"
    end
    return result
end

RefreshMarkdownView = function()
    local content = contentEdit and contentEdit:GetText() or ""
    local rendered = RenderMarkdown(content)

    -- Use a top-anchored FontString for rendered note content.
    -- ScrollingMessageFrame behaves like a chat frame and bottom-aligns short text,
    -- which made the note view look like a large empty box with the content at the bottom.
    if contentViewText then
        contentViewText:SetText(rendered)
    elseif contentViewMessage then
        contentViewMessage:Clear()
        for line in string.gmatch(rendered .. "\n", "(.-)\n") do
            contentViewMessage:AddMessage(line, 1, 1, 1)
        end
        if contentViewMessage.ScrollToTop then
            contentViewMessage:ScrollToTop()
        elseif contentViewMessage.ScrollToBottom then
            contentViewMessage:ScrollToBottom()
        end
    end

    if contentViewText and contentViewText.GetStringHeight and contentViewFrame then
        local height = math.max(245, math.floor(contentViewText:GetStringHeight() or 245) + 20)
        contentViewFrame:SetHeight(height)
    elseif contentViewFrame then
        contentViewFrame:SetHeight(245)
    end
end

local function FocusContentEditor()
    if titleEdit and titleEdit.ClearFocus then
        titleEdit:ClearFocus()
    end
    if contentEdit then
        if contentScroll then
            contentScroll:SetScrollChild(contentEdit)
        end
        contentEdit:Show()
        contentEdit:EnableMouse(true)
        contentEdit:SetFocus()
    end
end

SetEditMode = function(enabled)
    editMode = enabled and true or false
    if contentModeText then
        contentModeText:SetText(editMode and "Edit: raw Markdown" or "View: rendered Markdown")
    end
    if editToggleButton then
        editToggleButton:SetText(editMode and "View" or "Edit")
    end
    if contentScroll then
        if editMode then
            if contentViewFrame then contentViewFrame:Hide() end
            FocusContentEditor()
        else
            RefreshMarkdownView()
            if contentEdit then contentEdit:Hide() end
            if contentViewFrame then
                contentViewFrame:Show()
                contentScroll:SetScrollChild(contentViewFrame)
            end
        end
    end
end

local function GetEditorValues()
    local title = Trim(titleEdit and titleEdit:GetText() or "")
    local content = contentEdit and contentEdit:GetText() or ""

    if title == "" and content == "" then
        return nil, nil, "Nothing to save"
    end
    if title == "" then
        title = "Untitled"
    end

    return title, content, nil
end

LoadNote = function(noteGuid)
    InitDB()
    local note = WowNoteDB.notes[noteGuid]
    if not note then
        SetStatus("Note not found")
        return
    end

    currentGuid = noteGuid
    titleEdit:SetText(note.title or "")
    contentEdit:SetText(note.content or "")
    SetEditMode(false)
    SetStatus("Loaded: " .. (note.title or "Untitled"))
    RefreshList()
end

ClearEditor = function()
    currentGuid = nil
    if titleEdit then
        titleEdit:SetText("")
        if titleEdit.ClearFocus then titleEdit:ClearFocus() end
    end
    if contentEdit then
        contentEdit:SetText("")
        if contentEdit.ClearFocus then contentEdit:ClearFocus() end
    end
    SetEditMode(true)
    FocusContentEditor()
    SetStatus("New note")
    if RefreshList then RefreshList() end
end

SaveNote = function(forceNew)
    InitDB()

    local title, content, err = GetEditorValues()
    if err then
        SetStatus(err)
        return
    end

    if forceNew or not currentGuid or not WowNoteDB.notes[currentGuid] then
        currentGuid = GenerateGUID()
        WowNoteDB.notes[currentGuid] = {
            guid = currentGuid,
            version = WOWNOTE_NOTE_FORMAT_VERSION,
            created = time(),
        }
    end

    local note = WowNoteDB.notes[currentGuid]
    note.guid = currentGuid
    note.version = note.version or WOWNOTE_NOTE_FORMAT_VERSION
    note.title = title
    note.content = content
    note.updated = time()

    titleEdit:SetText(title)
    RefreshMarkdownView()
    SetEditMode(false)
    SetStatus("Saved: " .. title)
    RefreshList()
end

DeleteNote = function(noteGuid)
    InitDB()

    local targetGuid = noteGuid or currentGuid
    if not targetGuid or not WowNoteDB.notes[targetGuid] then
        SetStatus("No note selected")
        return
    end

    local oldTitle = WowNoteDB.notes[targetGuid].title or "Untitled"
    WowNoteDB.notes[targetGuid] = nil

    if currentGuid == targetGuid then
        currentGuid = nil
        titleEdit:SetText("")
        contentEdit:SetText("")
        SetEditMode(true)
    end

    SetStatus("Deleted: " .. oldTitle)
    RefreshList()
end

local function InsertTextIntoEditor(text)
    if not text or text == "" then return end
    local edit = contentEdit
    if frame and frame:IsShown() and edit then
        SetEditMode(true)
        edit:Insert(text)
        edit:SetFocus()
        activeEditBox = edit
    end
end

InsertCursorItemLink = function()
    local cursorType, itemID, itemLink = GetCursorInfo()
    if cursorType == "item" then
        local link = itemLink
        if not link and itemID then
            link = select(2, GetItemInfo(itemID))
        end
        ClearCursor()
        if link then
            InsertTextIntoEditor(link)
            SetStatus("Item link inserted")
        else
            SetStatus("Item link is not cached yet")
        end
    end
end

local function MakeButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width or 80)
    button:SetHeight(height or 22)
    button:SetText(text)
    return button
end

local WOW_NOTE_DIALOG_BASE_LEVEL = 100
local function RaiseFrame(frameToRaise)
    if not frameToRaise then return end
    if frameToRaise.SetFrameStrata then frameToRaise:SetFrameStrata("FULLSCREEN_DIALOG") end
    if frameToRaise.SetToplevel then frameToRaise:SetToplevel(true) end
    if frameToRaise.SetFrameLevel and frameToRaise.GetFrameLevel then
        local level = tonumber(frameToRaise:GetFrameLevel()) or 0
        -- Keep normal WowNote windows inside a bounded level range. Very large
        -- hard-coded levels can block unrelated dialogs and tooltips even after
        -- another window is brought to the front.
        if level < 80 or level > 200 then
            frameToRaise:SetFrameLevel(WOW_NOTE_DIALOG_BASE_LEVEL)
        end
    end
    if frameToRaise.Raise then frameToRaise:Raise() end
end

local function EnableRaiseOnInteraction(frameToRaise)
    if not frameToRaise then return end
    if frameToRaise.SetToplevel then frameToRaise:SetToplevel(true) end
    if frameToRaise.SetScript then
        frameToRaise:SetScript("OnMouseDown", function(self) RaiseFrame(self) end)
    end
end

local function SafeSetScript(frame, scriptName, handler)
    if not frame or not frame.SetScript then
        return false
    end
    if frame.HasScript and not frame:HasScript(scriptName) then
        return false
    end
    local ok = pcall(frame.SetScript, frame, scriptName, handler)
    return ok and true or false
end

local function ScrollMarkdownView(delta)
    if not contentViewMessage then return end
    if delta and delta > 0 then
        if contentViewMessage.ScrollUp then
            contentViewMessage:ScrollUp()
        end
    else
        if contentViewMessage.ScrollDown then
            contentViewMessage:ScrollDown()
        end
    end
end

local function MakeEditBox(parent, multiline)
    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(6, 6, 6, 6)
    edit:EnableMouse(true)
    edit:SetMultiLine(multiline and true or false)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function(self) activeEditBox = self end)
    edit:SetScript("OnEditFocusLost", function(self) if activeEditBox == self then activeEditBox = nil end end)
    edit:SetScript("OnReceiveDrag", InsertCursorItemLink)
    edit:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            InsertCursorItemLink()
        end
    end)
    if edit.SetHyperlinksEnabled then
        edit:SetHyperlinksEnabled(true)
    end
    SafeSetScript(edit, "OnHyperlinkEnter", function(self, linkData, linkText)
        ShowHyperlinkTooltip(self, linkData)
    end)
    SafeSetScript(edit, "OnHyperlinkLeave", HideHyperlinkTooltip)
    SafeSetScript(edit, "OnHyperlinkClick", HandleHyperlinkClick)
    return edit
end

ShowNoteContextMenu = function(noteGuid)
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "WowNoteContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    local menu = {
        {
            text = "Save",
            notCheckable = 1,
            func = function()
                currentGuid = noteGuid
                SaveNote(false)
            end,
        },
        {
            text = "Delete",
            notCheckable = 1,
            func = function()
                DeleteNote(noteGuid)
            end,
        },
        {
            text = "Save as new",
            notCheckable = 1,
            func = function()
                SaveNote(true)
            end,
        },
        {
            text = "Cancel",
            notCheckable = 1,
            func = function() end,
        },
    }

    if EasyMenu then
        EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
    end
end

RefreshList = function()
    if not listFrame then return end

    InitDB()
    local sorted = SortNotes()
    for i = 1, table.getn(buttons) do
        buttons[i]:Hide()
    end

    local last
    for i = 1, table.getn(sorted) do
        local info = sorted[i]
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", nil, listFrame)
            button:SetHeight(22)
            button:SetWidth(180)
            button:EnableMouse(true)
            button:SetFrameLevel(listFrame:GetFrameLevel() + 2)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button.selectedTexture = button:CreateTexture(nil, "BACKGROUND")
            button.selectedTexture:SetAllPoints(button)
            button.selectedTexture:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            button.selectedTexture:SetBlendMode("ADD")
            button.selectedTexture:Hide()
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("LEFT", button, "LEFT", 4, 0)
            button.text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
            button.text:SetJustifyH("LEFT")
            button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            buttons[i] = button
        end

        button.noteGuid = info.guid
        button.text:SetText(info.title ~= "" and info.title or "Untitled")
        if currentGuid == info.guid then
            button.selectedTexture:Show()
        else
            button.selectedTexture:Hide()
        end
        button:ClearAllPoints()
        if last then
            button:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
        else
            button:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, 0)
        end
        button:SetScript("OnMouseDown", function(self, mouseButton)
            -- Load notes on mouse-down as well as click. Some high-strata child frames
            -- in older 3.3.5a clients can steal the mouse-up event after focus changes.
            if mouseButton == "LeftButton" and self.noteGuid then
                LoadNote(self.noteGuid)
            end
        end)
        button:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                LoadNote(self.noteGuid)
                ShowNoteContextMenu(self.noteGuid)
            elseif self.noteGuid then
                LoadNote(self.noteGuid)
            end
        end)
        button:Show()
        last = button
    end

    local requiredHeight = math.max(360, table.getn(sorted) * 24)
    listFrame:SetHeight(requiredHeight)
    UpdateTitan()
end


local COMM_PREFIX = "WNOTE"
local COMM_VERSION = "WN1"
local CHAT_COMM_MARKER = "WN1:"
local LEGACY_CHAT_COMM_MARKER = "<WN1>"
local COMM_CHANNEL_NAME = "WowNoteShare"
local commChannelNumber = nil
local COMM_CHUNK_SIZE = 180
local sentTransfers = {}
local commMaintenanceFrame = nil
local commDebug = false
local BuildTransferId

function WowNote_IsCommDebugEnabled()
    return commDebug == true
end

function WowNote_SetCommDebugEnabled(enabled)
    commDebug = enabled == true
end

function WowNote_CommDebug(message)
    if commDebug then
        Print("DEBUG " .. tostring(message or ""))
    end
end

local function EscapeChatPayload(payload)
    payload = tostring(payload or "")
    -- Chat channels treat | as an escape introducer for links/colors/textures.
    -- Carbonite avoids raw pipes for the same reason.
    return string.gsub(payload, "|", "\001")
end

local function UnescapeChatPayload(payload)
    payload = tostring(payload or "")
    return string.gsub(payload, "\001", "|")
end

local function IsWowNoteChatMessage(message)
    if type(message) ~= "string" then return false end
    if string.sub(message, 1, string.len(CHAT_COMM_MARKER)) == CHAT_COMM_MARKER then return true end
    if string.sub(message, 1, string.len(LEGACY_CHAT_COMM_MARKER)) == LEGACY_CHAT_COMM_MARKER then return true end
    return false
end

local function NormalizeShareTarget(target)
    target = Trim(target or "")
    target = string.gsub(target, "%s+", "")

    -- WoW 3.3.5a WHISPER addon messages are realm-local.
    -- A modern Name-Realm target often does not receive anything on WotLK/private servers.
    local nameOnly = string.match(target, "^([^-]+)%-.+$")
    if nameOnly and nameOnly ~= "" then
        return nameOnly, true
    end

    return target, false
end

local function SendAddonWhisper(target, payload)
    if not SendAddonMessage then return false end
    local ok = pcall(SendAddonMessage, COMM_PREFIX, payload, "WHISPER", target)
    if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("out", "WNOTE WHISPER", string.len(tostring(payload or "")), ok and true or false) end
    if commDebug then
        Print("DEBUG send WHISPER to " .. tostring(target or "?") .. ": " .. tostring(payload or ""))
    end
    return ok and true or false
end

local function SendAddonChannel(channel, payload)
    if not SendAddonMessage then return false end
    local ok = pcall(SendAddonMessage, COMM_PREFIX, payload, channel)
    if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("out", "WNOTE " .. tostring(channel or "?"), string.len(tostring(payload or "")), ok and true or false) end
    if commDebug then
        Print("DEBUG send " .. tostring(channel or "?") .. ": " .. tostring(payload or ""))
    end
    return ok and true or false
end

local function SendChatWhisper(target, payload)
    if not SendChatMessage then return false end
    target = NormalizeShareTarget(target or "")
    if target == "" then return false end
    local text = CHAT_COMM_MARKER .. EscapeChatPayload(payload)
    local ok = pcall(SendChatMessage, text, "WHISPER", nil, target)
    if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("out", "CHAT WHISPER", string.len(text or ""), ok and true or false) end
    if commDebug then
        Print("DEBUG send CHAT-WHISPER to " .. tostring(target or "?") .. ": " .. tostring(payload or ""))
    end
    return ok and true or false
end

local function JoinWowNoteChannel(silent)
    if not JoinChannelByName or not GetChannelName then return false end

    local number = GetChannelName(COMM_CHANNEL_NAME)
    if number and number ~= 0 then
        commChannelNumber = number
        return true
    end

    local ok = pcall(JoinChannelByName, COMM_CHANNEL_NAME)
    if not ok then
        if not silent then
            Print("Could not join WowNote channel " .. COMM_CHANNEL_NAME .. ".")
        end
        return false
    end

    number = GetChannelName(COMM_CHANNEL_NAME)
    if number and number ~= 0 then
        commChannelNumber = number
    end

    if commDebug and not silent then
        Print("Joining channel " .. COMM_CHANNEL_NAME .. ". Send again if the first attempt only joined the channel.")
    end
    return true
end

local function SendChatChannel(target, payload)
    if not SendChatMessage then return false end
    target = NormalizeShareTarget(target or "")
    if target == "" then return false end

    JoinWowNoteChannel(true)

    local number = commChannelNumber
    if not number or number == 0 then
        number = GetChannelName and GetChannelName(COMM_CHANNEL_NAME) or 0
        commChannelNumber = number
    end
    if not number or number == 0 then
        if commDebug then
            Print("DEBUG channel not ready: " .. COMM_CHANNEL_NAME)
        end
        return false
    end

    local text = CHAT_COMM_MARKER .. target .. ":" .. EscapeChatPayload(payload)
    local ok = pcall(SendChatMessage, text, "CHANNEL", nil, number)
    if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("out", "CHAT CHANNEL", string.len(text or ""), ok and true or false) end
    if commDebug then
        Print("DEBUG send CHANNEL " .. COMM_CHANNEL_NAME .. " #" .. tostring(number or "?") .. " to " .. tostring(target or "?") .. ": " .. tostring(payload or ""))
    end
    return ok and true or false
end

local function WowNoteChatFilter(self, event, message, sender, ...)
    if IsWowNoteChatMessage(message) then
        return true
    end
    return false
end

local function SendCommPing(target)
    local normalizedTarget, strippedRealm = NormalizeShareTarget(target or "")
    if normalizedTarget == "" then
        Print("Usage: /wn ping CharacterName")
        return
    end
    if strippedRealm then
        Print("WotLK 3.3.5a uses local character names. Pinging " .. normalizedTarget .. ".")
    end
    SendAddonWhisper(normalizedTarget, COMM_VERSION .. "|P|" .. BuildTransferId() .. "|ping")
    Print("Ping sent to " .. normalizedTarget .. ". If the other client receives addon whispers, this client should get a pong.")
end

local function SendCommPingChat(target)
    local normalizedTarget, strippedRealm = NormalizeShareTarget(target or "")
    if normalizedTarget == "" then
        Print("Usage: /wn pingchat CharacterName")
        return
    end
    if strippedRealm then
        Print("WotLK 3.3.5a uses local character names. Chat-pinging " .. normalizedTarget .. ".")
    end
    SendChatWhisper(normalizedTarget, COMM_VERSION .. "|P|" .. BuildTransferId() .. "|chatwhisper")
    Print("Chat ping sent to " .. normalizedTarget .. ". If normal whispers work, this client should get a chat pong.")
end

local function PrintChannelInfo()
    local number = GetChannelName and GetChannelName(COMM_CHANNEL_NAME) or 0
    commChannelNumber = number
    Print("WowNote channel " .. COMM_CHANNEL_NAME .. " number: " .. tostring(number or 0) .. ".")
end

local function SendVisibleChannelTest()
    JoinWowNoteChannel(false)
    local number = commChannelNumber
    if not number or number == 0 then
        number = GetChannelName and GetChannelName(COMM_CHANNEL_NAME) or 0
        commChannelNumber = number
    end
    if not number or number == 0 then
        Print("WowNote channel is not ready. Use /wn joinchan, wait one second, then /wn chantest.")
        return
    end
    local ok = pcall(SendChatMessage, "WowNote visible channel test from " .. (UnitName and UnitName("player") or "unknown"), "CHANNEL", nil, number)
    Print("Visible channel test sent to " .. COMM_CHANNEL_NAME .. " #" .. tostring(number) .. ": " .. tostring(ok and "ok" or "failed"))
end

local function SendCommPingChannel(target)
    local normalizedTarget, strippedRealm = NormalizeShareTarget(target or "")
    if normalizedTarget == "" then
        Print("Usage: /wn pingchan CharacterName")
        return
    end
    if strippedRealm then
        Print("WotLK 3.3.5a uses local character names. Channel-pinging " .. normalizedTarget .. ".")
    end
    JoinWowNoteChannel(false)
    SendChatChannel(normalizedTarget, COMM_VERSION .. "|P|" .. BuildTransferId() .. "|channel")
    Print("Channel ping sent to " .. normalizedTarget .. " via " .. COMM_CHANNEL_NAME .. ".")
end

local function SendCommPingRoutes(target)
    local normalizedTarget, strippedRealm = NormalizeShareTarget(target or "")
    if normalizedTarget == "" then
        Print("Usage: /wn pingroutes CharacterName")
        return
    end
    if strippedRealm then
        Print("WotLK 3.3.5a uses local character names. Testing routes for " .. normalizedTarget .. ".")
    end

    local transferId = BuildTransferId()
    SendAddonWhisper(normalizedTarget, COMM_VERSION .. "|P|" .. transferId .. "|whisper")
    SendAddonChannel("PARTY", COMM_VERSION .. "|P|" .. transferId .. "|party")
    SendAddonChannel("RAID", COMM_VERSION .. "|P|" .. transferId .. "|raid")
    SendAddonChannel("GUILD", COMM_VERSION .. "|P|" .. transferId .. "|guild")
    Print("Route ping sent to " .. normalizedTarget .. " via WHISPER, PARTY, RAID and GUILD. Ignore Lua errors from channels you are not in; pcall should suppress them.")
end

local function SendShareAck(target, transferId, state, returnMode)
    target = NormalizeShareTarget(target or "")
    if target == "" or not transferId then return end
    local payload = COMM_VERSION .. "|A|" .. tostring(transferId) .. "|" .. tostring(state or "seen")
    if returnMode == "CHATWHISPER" then
        SendChatWhisper(target, payload)
    elseif returnMode == "CHANNEL" then
        SendChatChannel(target, payload)
    else
        SendAddonWhisper(target, payload)
    end
end

local function BuildMissingPacketList(transfer)
    local missing = {}
    if not transfer or not transfer.total then return missing, 0 end
    local i
    for i = 1, transfer.total do
        if not transfer.chunks or transfer.chunks[i] == nil then
            table.insert(missing, i)
        end
    end
    return missing, table.getn(missing)
end

local function PacketListToText(list)
    local parts = {}
    local i
    for i = 1, table.getn(list or {}) do
        table.insert(parts, tostring(list[i]))
    end
    return table.concat(parts, ",")
end

local function ParsePacketList(text, total)
    local list = {}
    local seen = {}
    total = tonumber(total or 0) or 0
    for numberText in string.gmatch(tostring(text or ""), "([^,]+)") do
        local index = tonumber(Trim(numberText or "")) or 0
        if index > 0 and (total <= 0 or index <= total) and not seen[index] then
            seen[index] = true
            table.insert(list, index)
        end
    end
    return list
end

local function SendShareMissing(target, transferId, missingList, returnMode)
    local text = PacketListToText(missingList or {})
    if text == "" then return false end
    SendShareAck(target, transferId, "missing:" .. text, returnMode)
    return true
end

local function RequestMissingPackets(sender, transfer, reason)
    if not sender or not transfer then return false end
    local missing, missingCount = BuildMissingPacketList(transfer)
    if missingCount <= 0 then return false end
    transfer.lastMissingRequest = time and time() or 0
    SendShareMissing(sender, transfer.id, missing, transfer.returnMode)
    if shareReceiveStatusText then
        shareReceiveStatusText:SetText("Missing " .. tostring(missingCount) .. " packet(s): " .. PacketListToText(missing) .. ". Waiting for resend...")
    end
    if reason and reason ~= "" then
        Print("WowNote transfer " .. tostring(transfer.id or "?") .. " is incomplete (" .. tostring(transfer.count or 0) .. "/" .. tostring(transfer.total or 0) .. "). Requesting missing packet(s): " .. PacketListToText(missing) .. ".")
    end
    return true
end

local function HasIncompleteIncomingTransfers()
    local id, transfer
    for id, transfer in pairs(incomingTransfers) do
        if transfer and transfer.total and transfer.count and transfer.count < transfer.total then
            return true
        end
    end
    return false
end

local function EnsureCommMaintenanceFrame()
    if not CreateFrame then return end
    if not commMaintenanceFrame then
        commMaintenanceFrame = CreateFrame("Frame")
        commMaintenanceFrame:Hide()
        commMaintenanceFrame.elapsed = 0
        WowNoteProfiler_SetScript(commMaintenanceFrame, "OnUpdate", "Core.CommMaintenance", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + (elapsed or 0)
            if self.elapsed < 1.0 then return end
            self.elapsed = 0

            local now = time and time() or 0
            local id, transfer
            local hasIncomplete = false
            for id, transfer in pairs(incomingTransfers) do
                if transfer and transfer.total and transfer.count and transfer.count < transfer.total then
                    hasIncomplete = true
                    local lastPacket = transfer.lastPacketAt or transfer.started or now
                    local lastMissing = transfer.lastMissingRequest or 0
                    if now - lastPacket >= 4 and now - lastMissing >= 4 then
                        RequestMissingPackets(transfer.sender, transfer, "timeout")
                    end
                end
            end
            if not hasIncomplete then
                self:Hide()
            end
        end)
    end

    if HasIncompleteIncomingTransfers() then
        commMaintenanceFrame.elapsed = 0
        commMaintenanceFrame:Show()
    else
        commMaintenanceFrame:Hide()
    end
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_REVERSE = nil

local function BuildBase64Reverse()
    if BASE64_REVERSE then return BASE64_REVERSE end
    BASE64_REVERSE = {}
    local i
    for i = 1, string.len(BASE64_ALPHABET) do
        BASE64_REVERSE[string.sub(BASE64_ALPHABET, i, i)] = i - 1
    end
    return BASE64_REVERSE
end

local function Base64Encode(text)
    text = text or ""
    local out = {}
    local i = 1
    local len = string.len(text)

    while i <= len do
        local b1 = string.byte(text, i) or 0
        local b2 = string.byte(text, i + 1)
        local b3 = string.byte(text, i + 2)

        local c1 = math.floor(b1 / 4)
        local c2 = ((b1 - (c1 * 4)) * 16) + math.floor((b2 or 0) / 16)
        local c3 = (((b2 or 0) - (math.floor((b2 or 0) / 16) * 16)) * 4) + math.floor((b3 or 0) / 64)
        local c4 = (b3 or 0) - (math.floor((b3 or 0) / 64) * 64)

        table.insert(out, string.sub(BASE64_ALPHABET, c1 + 1, c1 + 1))
        table.insert(out, string.sub(BASE64_ALPHABET, c2 + 1, c2 + 1))
        if b2 then
            table.insert(out, string.sub(BASE64_ALPHABET, c3 + 1, c3 + 1))
        else
            table.insert(out, "=")
        end
        if b3 then
            table.insert(out, string.sub(BASE64_ALPHABET, c4 + 1, c4 + 1))
        else
            table.insert(out, "=")
        end

        i = i + 3
    end

    return table.concat(out)
end

local function Base64Decode(text)
    text = text or ""
    text = string.gsub(text, "[^A-Za-z0-9%+/%=]", "")
    local rev = BuildBase64Reverse()
    local out = {}
    local i = 1
    local len = string.len(text)

    while i <= len do
        local ch1 = string.sub(text, i, i)
        local ch2 = string.sub(text, i + 1, i + 1)
        local ch3 = string.sub(text, i + 2, i + 2)
        local ch4 = string.sub(text, i + 3, i + 3)

        local c1 = rev[ch1]
        local c2 = rev[ch2]
        local c3 = rev[ch3]
        local c4 = rev[ch4]

        if c1 and c2 then
            local b1 = (c1 * 4) + math.floor(c2 / 16)
            table.insert(out, string.char(b1))

            if ch3 ~= "=" and c3 then
                local b2 = ((c2 - (math.floor(c2 / 16) * 16)) * 16) + math.floor(c3 / 4)
                table.insert(out, string.char(b2))
            end

            if ch4 ~= "=" and c3 and c4 then
                local b3 = ((c3 - (math.floor(c3 / 4) * 4)) * 64) + c4
                table.insert(out, string.char(b3))
            end
        end

        i = i + 4
    end

    return table.concat(out)
end

local function PercentEncode(text)
    text = text or ""
    return string.gsub(text, "([^A-Za-z0-9_%-%.])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function PercentDecode(text)
    text = text or ""
    return string.gsub(text, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function CompressText(text)
    text = text or ""
    local out = {}
    local i = 1
    local len = string.len(text)

    while i <= len do
        local char = string.sub(text, i, i)
        local count = 1
        while i + count <= len and string.sub(text, i + count, i + count) == char and count < 255 do
            count = count + 1
        end

        if count >= 5 then
            table.insert(out, string.char(254))
            table.insert(out, string.char(count))
            table.insert(out, char)
        else
            table.insert(out, string.rep(char, count))
        end
        i = i + count
    end

    return table.concat(out)
end

local function DecompressText(text)
    text = text or ""
    local out = {}
    local i = 1
    local len = string.len(text)

    while i <= len do
        local char = string.sub(text, i, i)
        if string.byte(char) == 254 and i + 2 <= len then
            local count = string.byte(string.sub(text, i + 1, i + 1)) or 0
            local repeated = string.sub(text, i + 2, i + 2)
            table.insert(out, string.rep(repeated, count))
            i = i + 3
        else
            table.insert(out, char)
            i = i + 1
        end
    end

    return table.concat(out)
end

local function SerializeNote(note)
    note = note or {}
    local noteVersion = Trim(note.version or "")
    if noteVersion == "" then
        noteVersion = WOWNOTE_NOTE_FORMAT_VERSION
    end
    return "noteVersion=" .. PercentEncode(noteVersion)
        .. "\ntitle=" .. PercentEncode(note.title or "")
        .. "\ncontent=" .. PercentEncode(note.content or "")
end

local function DeserializeNote(text)
    local note = { title = "Shared note", content = "", version = WOWNOTE_NOTE_FORMAT_VERSION }
    text = text or ""
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        local key, value = string.match(line, "^([^=]+)=(.*)$")
        if key == "noteVersion" or key == "version" then
            note.version = PercentDecode(value or "")
            if note.version == "" then note.version = WOWNOTE_NOTE_FORMAT_VERSION end
        elseif key == "title" then
            note.title = PercentDecode(value or "")
        elseif key == "content" then
            note.content = PercentDecode(value or "")
        end
    end
    return note
end


WOWNOTE_EXPORT_WRAPPER_PREFIX = "WNX1\n"

function WowNote_EncodeNoteForExport(note)
    local serialized = SerializeNote(note)
    local compressed = CompressText(serialized)
    local payload = "B64:" .. Base64Encode(compressed)
    return Base64Encode(WOWNOTE_EXPORT_WRAPPER_PREFIX .. payload), string.len(serialized or ""), string.len(compressed or "")
end

function WowNote_DecodeExportedNote(exportText)
    exportText = Trim(exportText or "")
    exportText = string.gsub(exportText, "%s+", "")
    if exportText == "" then
        return nil, "No import text entered."
    end

    local decoded = Base64Decode(exportText)
    local payload
    if string.sub(decoded or "", 1, string.len(WOWNOTE_EXPORT_WRAPPER_PREFIX)) == WOWNOTE_EXPORT_WRAPPER_PREFIX then
        payload = string.sub(decoded, string.len(WOWNOTE_EXPORT_WRAPPER_PREFIX) + 1)
    elseif string.sub(exportText, 1, 4) == "B64:" then
        payload = exportText
    else
        return nil, "Invalid WowNote export text."
    end

    local compressed
    if string.sub(payload or "", 1, 4) == "B64:" then
        compressed = Base64Decode(string.sub(payload, 5))
    else
        compressed = PercentDecode(payload or "")
    end

    local serialized = DecompressText(compressed)
    if not serialized or serialized == "" then
        return nil, "Could not decode WowNote export text."
    end

    local note = DeserializeNote(serialized)
    if not note or ((note.title or "") == "" and (note.content or "") == "") then
        return nil, "Decoded text does not contain a note."
    end

    note.title = Trim(note.title or "Untitled")
    if note.title == "" then note.title = "Untitled" end
    note.content = note.content or ""
    note.version = note.version or WOWNOTE_NOTE_FORMAT_VERSION
    return note, nil
end

function WowNote_LoadImportedNoteIntoEditor(note)
    CreateUI()
    currentGuid = nil
    titleEdit:SetText(note.title or "Untitled")
    contentEdit:SetText(note.content or "")
    RefreshMarkdownView()
    SetEditMode(false)
    SetStatus("Imported note loaded. Click Save to store it.")
    if RefreshList then RefreshList() end
end

function WowNote_OpenNoteImportExportDialog(mode, initialText, status)
    CreateUI()

    if not WowNoteImportExportFrame then
        WowNoteImportExportFrame = CreateFrame("Frame", "WowNoteImportExportFrame", UIParent)
        WowNoteImportExportFrame:SetWidth(640)
        WowNoteImportExportFrame:SetHeight(420)
        WowNoteImportExportFrame:SetPoint("CENTER")
        WowNoteImportExportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        WowNoteImportExportFrame:SetFrameLevel(120)
        WowNoteImportExportFrame:SetToplevel(true)
        WowNoteImportExportFrame:EnableMouse(true)
        WowNoteImportExportFrame:SetMovable(true)
        WowNoteImportExportFrame:RegisterForDrag("LeftButton")
        WowNoteImportExportFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        WowNoteImportExportFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        WowNoteImportExportFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })

        WowNoteImportExportFrame.title = WowNoteImportExportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        WowNoteImportExportFrame.title:SetPoint("TOPLEFT", WowNoteImportExportFrame, "TOPLEFT", 18, -16)

        local close = CreateFrame("Button", nil, WowNoteImportExportFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", WowNoteImportExportFrame, "TOPRIGHT", -4, -4)

        local label = WowNoteImportExportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", WowNoteImportExportFrame, "TOPLEFT", 24, -52)
        label:SetText("Export/import text")

        local bg = CreateFrame("Frame", nil, WowNoteImportExportFrame)
        bg:SetPoint("TOPLEFT", WowNoteImportExportFrame, "TOPLEFT", 22, -70)
        bg:SetWidth(590)
        bg:SetHeight(270)
        bg:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        bg:SetBackdropColor(0, 0, 0, 0.85)

        local scroll = CreateFrame("ScrollFrame", "WowNoteImportExportScrollFrame", bg, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -28, 4)

        WowNoteImportExportEditBox = MakeEditBox(scroll, true)
        WowNoteImportExportEditBox:SetWidth(540)
        WowNoteImportExportEditBox:SetHeight(900)
        WowNoteImportExportEditBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
            if ScrollingEdit_OnCursorChanged then
                ScrollingEdit_OnCursorChanged(self, x, y, w, h)
            end
        end)
        WowNoteProfiler_SetScript(WowNoteImportExportEditBox, "OnUpdate", "Core.ImportExportEdit", function(self, elapsed)
            if ScrollingEdit_OnUpdate then
                ScrollingEdit_OnUpdate(self, elapsed, self:GetParent())
            end
        end)
        WowNoteImportExportEditBox:SetScript("OnTextChanged", function(self)
            if ScrollingEdit_OnTextChanged then
                ScrollingEdit_OnTextChanged(self, self:GetParent())
            end
        end)
        scroll:SetScrollChild(WowNoteImportExportEditBox)

        WowNoteImportExportStatusText = WowNoteImportExportFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        WowNoteImportExportStatusText:SetPoint("TOPLEFT", WowNoteImportExportFrame, "TOPLEFT", 24, -350)
        WowNoteImportExportStatusText:SetWidth(580)
        WowNoteImportExportStatusText:SetJustifyH("LEFT")

        WowNoteImportExportFrame.importButton = MakeButton(WowNoteImportExportFrame, "Import", 90, 24)
        WowNoteImportExportFrame.importButton:SetPoint("BOTTOMLEFT", WowNoteImportExportFrame, "BOTTOMLEFT", 24, 22)
        WowNoteImportExportFrame.importButton:SetScript("OnClick", function()
            local note, err = WowNote_DecodeExportedNote(WowNoteImportExportEditBox:GetText() or "")
            if not note then
                WowNoteImportExportStatusText:SetText(err or "Import failed.")
                SetStatus(err or "Import failed")
                return
            end
            WowNote_LoadImportedNoteIntoEditor(note)
            WowNoteImportExportStatusText:SetText("Imported: " .. (note.title or "Untitled") .. ". Click Save to store it.")
            WowNoteImportExportFrame:Hide()
        end)

        WowNoteImportExportFrame.selectButton = MakeButton(WowNoteImportExportFrame, "Select all", 100, 24)
        WowNoteImportExportFrame.selectButton:SetPoint("LEFT", WowNoteImportExportFrame.importButton, "RIGHT", 8, 0)
        WowNoteImportExportFrame.selectButton:SetScript("OnClick", function()
            WowNoteImportExportEditBox:SetFocus()
            WowNoteImportExportEditBox:HighlightText()
        end)

        local closeButton = MakeButton(WowNoteImportExportFrame, "Close", 90, 24)
        closeButton:SetPoint("LEFT", WowNoteImportExportFrame.selectButton, "RIGHT", 8, 0)
        closeButton:SetScript("OnClick", function() WowNoteImportExportFrame:Hide() end)
    end

    if mode == "export" then
        WowNoteImportExportFrame.title:SetText("Export WowNote note")
        WowNoteImportExportFrame.importButton:Hide()
        WowNoteImportExportFrame.selectButton:ClearAllPoints()
        WowNoteImportExportFrame.selectButton:SetPoint("BOTTOMLEFT", WowNoteImportExportFrame, "BOTTOMLEFT", 24, 22)
        WowNoteImportExportEditBox:SetText(initialText or "")
        WowNoteImportExportStatusText:SetText(status or "Copy this text and paste it into another WowNote client via Import.")
        WowNoteImportExportEditBox:SetFocus()
        WowNoteImportExportEditBox:HighlightText()
    else
        WowNoteImportExportFrame.title:SetText("Import WowNote note")
        WowNoteImportExportFrame.importButton:Show()
        WowNoteImportExportFrame.selectButton:ClearAllPoints()
        WowNoteImportExportFrame.selectButton:SetPoint("LEFT", WowNoteImportExportFrame.importButton, "RIGHT", 8, 0)
        WowNoteImportExportEditBox:SetText(initialText or "")
        WowNoteImportExportStatusText:SetText(status or "Paste exported WowNote text here, then click Import.")
        WowNoteImportExportEditBox:SetFocus()
        WowNoteImportExportEditBox:HighlightText(0, 0)
    end

    WowNoteImportExportFrame:Show()
    if WowNoteImportExportFrame.Raise then WowNoteImportExportFrame:Raise() end
end

function WowNote_ExportCurrentNoteToDialog()
    InitDB()
    if not currentGuid or not WowNoteDB.notes[currentGuid] then
        SetStatus("No note selected")
        Print("No saved note selected. Save first or select a note on the left.")
        return
    end

    local note = WowNoteDB.notes[currentGuid]
    local text, originalSize, compressedSize = WowNote_EncodeNoteForExport(note)
    WowNote_OpenNoteImportExportDialog("export", text, "Exported " .. tostring(note.title or "Untitled") .. " (RLE " .. tostring(compressedSize or "?") .. "/" .. tostring(originalSize or "?") .. " bytes).")
    SetStatus("Export ready: copy the selected text")
end

function WowNote_OpenImportNoteDialog()
    WowNote_OpenNoteImportExportDialog("import", "", "Paste exported WowNote text here, then click Import.")
end

BuildTransferId = function()
    SeedRandom()
    return tostring(time and time() or 0) .. tostring(WowNote_Random(10000, 99999))
end

local function SplitPayload(payload)
    local chunks = {}
    payload = payload or ""
    local pos = 1
    while pos <= string.len(payload) do
        table.insert(chunks, string.sub(payload, pos, pos + COMM_CHUNK_SIZE - 1))
        pos = pos + COMM_CHUNK_SIZE
    end
    if table.getn(chunks) == 0 then
        table.insert(chunks, "")
    end
    return chunks
end

local function SendTransferPacket(transfer, payload)
    if not transfer then return false end
    local mode = transfer.returnMode or "WHISPER"
    if mode == "CHATWHISPER" then
        return SendChatWhisper(transfer.target, payload)
    elseif mode == "CHANNEL" then
        return SendChatChannel(transfer.target, payload)
    elseif mode == "PARTY" or mode == "RAID" or mode == "GUILD" or mode == "BATTLEGROUND" then
        return SendAddonChannel(mode, payload)
    end
    return SendAddonWhisper(transfer.target, payload)
end

local function SendSelectedTransferPackets(transferId, indices, label)
    local transfer = sentTransfers[transferId]
    if not transfer or not transfer.chunks then return false end

    local ok = true
    local sent = 0
    local i
    for i = 1, table.getn(indices or {}) do
        local index = tonumber(indices[i] or 0) or 0
        if index > 0 and index <= (transfer.total or 0) then
            sent = sent + 1
            if not SendTransferPacket(transfer, COMM_VERSION .. "|C|" .. transferId .. "|" .. tostring(index) .. "|" .. tostring(transfer.chunks[index] or "")) then
                ok = false
            end
        end
    end
    if not SendTransferPacket(transfer, COMM_VERSION .. "|E|" .. transferId) then
        ok = false
    end

    if shareStatusText then
        shareStatusText:SetText("Resent " .. tostring(sent) .. " missing packet(s). Waiting for receiver save...")
    end
    if ok then
        Print("Resent " .. tostring(sent) .. " missing WowNote packet(s) to " .. tostring(transfer.target or "?") .. ".")
    else
        Print("Tried to resend " .. tostring(sent) .. " missing WowNote packet(s), but at least one send call failed.")
    end
    return ok
end

local function SendPreparedTransfer(transferId)
    local transfer = sentTransfers[transferId]
    if not transfer or not transfer.chunks then return false end

    local ok = SendTransferPacket(transfer, COMM_VERSION .. "|B|" .. transferId .. "|" .. tostring(transfer.total or 0))
    local indices = {}
    local i
    for i = 1, transfer.total do
        table.insert(indices, i)
    end
    if not SendSelectedTransferPackets(transferId, indices, "full") then
        ok = false
    end

    transfer.sentChunks = true
    if shareStatusText then
        shareStatusText:SetText("Receiver accepted. Sent " .. tostring(transfer.total or 0) .. " packets. Waiting for final response...")
    end

    if ok then
        Print("Receiver accepted the transfer. Sent " .. tostring(transfer.total or 0) .. " WowNote packets to " .. tostring(transfer.target or "?") .. ".")
    else
        Print("Receiver accepted, but not all WowNote packets could be sent to " .. tostring(transfer.target or "?") .. ".")
    end
    return ok
end

local function FindOpenSentTransfer(target, noteGuid)
    local id, transfer
    for id, transfer in pairs(sentTransfers) do
        if transfer and transfer.target == target and transfer.noteGuid == noteGuid and transfer.chunks then
            return id, transfer
        end
    end
    return nil, nil
end

SendCurrentNoteToPlayer = function(target, authCodeOverride)
    InitDB()
    target = Trim(target or "")
    local normalizedTarget, strippedRealm = NormalizeShareTarget(target)
    target = normalizedTarget

    if target == "" then
        Print("No recipient specified.")
        return
    end

    if strippedRealm then
        Print("WotLK 3.3.5a uses local character names for addon whispers. Sending to " .. target .. ".")
    end

    if not currentGuid or not WowNoteDB.notes[currentGuid] then
        Print("No saved note selected. Save first or select a note on the left.")
        return
    end

    if not SendAddonMessage then
        Print("AddOn communication is not available in this client.")
        return
    end

    local authCode = Trim(authCodeOverride or "")
    if authCode == "" and shareAuthEdit then
        authCode = Trim(shareAuthEdit:GetText() or "")
    end
    if not IsValidReceiverCode(authCode) then
        Print("Enter the 4-digit receiver code before sending. The receiver must enable receiving in the Share window and give you the code.")
        SetShareStatus("Missing or invalid receiver code. Enter the 4-digit code before sending.")
        if shareAuthEdit then
            shareAuthEdit:SetFocus()
            shareAuthEdit:HighlightText()
        end
        return
    end

    local note = WowNoteDB.notes[currentGuid]
    local serialized = SerializeNote(note)
    local compressed = CompressText(serialized)
    local payload = "B64:" .. Base64Encode(compressed)
    local chunks = SplitPayload(payload)
    local transferId, existingTransfer = FindOpenSentTransfer(target, currentGuid)
    local total = table.getn(chunks)
    if transferId and existingTransfer then
        existingTransfer.started = time()
        existingTransfer.authCode = authCode
        existingTransfer.returnMode = existingTransfer.returnMode or "WHISPER"
        existingTransfer.retryRequest = true
        if shareStatusText then
            shareStatusText:SetText("Retrying existing transfer. Receiver will request only missing packets if it still has partial data...")
        end
    else
        transferId = BuildTransferId()
        sentTransfers[transferId] = {
            target = target,
            noteGuid = currentGuid,
            total = total,
            started = time(),
            title = note.title or "Untitled",
            chunks = chunks,
            authCode = authCode,
            returnMode = "WHISPER",
        }
    end

    local requestPayload = COMM_VERSION .. "|M|" .. transferId .. "|" .. tostring(total) .. "|" .. tostring(string.len(payload or "")) .. "|" .. PercentEncode(authCode) .. "|" .. PercentEncode(note.title or "Untitled")
    local okAddon = SendAddonWhisper(target, requestPayload)
    local okChat = SendChatWhisper(target, requestPayload)
    local ok = okAddon or okChat

    WowNoteDB.share.sent = (WowNoteDB.share.sent or 0) + 1
    if shareStatusText then
        shareStatusText:SetText("Transfer request sent to " .. target .. ". Waiting for receiver code check/accept...")
    end

    if ok then
        Print("WowNote transfer request sent to " .. target .. " via addon whisper and chat fallback. Waiting for receiver code check before sending " .. tostring(total) .. " packets.")
    else
        sentTransfers[transferId] = nil
        Print("Could not send the WowNote transfer request to " .. target .. ". Check the player name and that the target is online.")
    end
end

function WowNote_SendDataItemToPlayer(target, authCodeOverride, dataItem)
    InitDB()
    target = Trim(target or "")
    local normalizedTarget, strippedRealm = NormalizeShareTarget(target)
    target = normalizedTarget

    if target == "" then
        Print("No recipient specified.")
        return false
    end

    if strippedRealm then
        Print("WotLK 3.3.5a uses local character names for addon whispers. Sending to " .. target .. ".")
    end

    if not SendAddonMessage then
        Print("AddOn communication is not available in this client.")
        return false
    end

    local authCode = Trim(authCodeOverride or "")
    if authCode == "" and shareAuthEdit then
        authCode = Trim(shareAuthEdit:GetText() or "")
    end
    if not IsValidReceiverCode(authCode) then
        Print("Enter the 4-digit receiver code before sending. The receiver must enable receiving in the Share window and give you the code.")
        SetShareStatus("Missing or invalid receiver code. Enter the 4-digit code before sending.")
        if shareAuthEdit then
            shareAuthEdit:SetFocus()
            shareAuthEdit:HighlightText()
        end
        return false
    end

    if type(dataItem) ~= "table" or not WowNote_BuildTransferPayloadForDataItem then
        Print("No transferable WowNote data selected.")
        return false
    end

    local payload, originalSize, compressedSize = WowNote_BuildTransferPayloadForDataItem(dataItem)
    if not payload or payload == "" then
        Print("Could not encode selected WowNote data.")
        return false
    end

    local chunks = SplitPayload(payload)
    local transferId = BuildTransferId()
    local total = table.getn(chunks)
    local title = dataItem.title or dataItem.key or dataItem.type or "WowNote data"
    sentTransfers[transferId] = {
        target = target,
        noteGuid = tostring(dataItem.type or "data") .. ":" .. tostring(dataItem.key or title),
        total = total,
        started = time(),
        title = title,
        dataType = dataItem.type or "data",
        chunks = chunks,
        authCode = authCode,
        returnMode = "WHISPER",
    }

    local requestTitle = tostring(title or "WowNote data")
    local requestPayload = COMM_VERSION .. "|M|" .. transferId .. "|" .. tostring(total) .. "|" .. tostring(string.len(payload or "")) .. "|" .. PercentEncode(authCode) .. "|" .. PercentEncode(requestTitle)
    local okAddon = SendAddonWhisper(target, requestPayload)
    local okChat = SendChatWhisper(target, requestPayload)
    local ok = okAddon or okChat

    WowNoteDB.share.sent = (WowNoteDB.share.sent or 0) + 1
    if shareStatusText then
        shareStatusText:SetText("Transfer request sent to " .. target .. ": " .. requestTitle .. ". Waiting for receiver accept...")
    end

    if ok then
        Print("WowNote data transfer request sent to " .. target .. ": " .. requestTitle .. " (" .. tostring(total) .. " packets).")
        return true
    end

    sentTransfers[transferId] = nil
    Print("Could not send the WowNote transfer request to " .. target .. ". Check the player name and that the target is online.")
    return false
end

local function SendCurrentNoteToPlayerViaChat(target)
    InitDB()
    target = Trim(target or "")
    local normalizedTarget, strippedRealm = NormalizeShareTarget(target)
    target = normalizedTarget

    if target == "" then
        Print("No recipient specified.")
        return
    end

    if strippedRealm then
        Print("WotLK 3.3.5a uses local character names for normal whispers. Sending to " .. target .. ".")
    end

    if not currentGuid or not WowNoteDB.notes[currentGuid] then
        Print("No saved note selected. Save first or select a note on the left.")
        return
    end

    if not SendChatMessage then
        Print("Chat whisper communication is not available in this client.")
        return
    end

    local note = WowNoteDB.notes[currentGuid]
    local serialized = SerializeNote(note)
    local compressed = CompressText(serialized)
    local payload = "B64:" .. Base64Encode(compressed)
    local chunks = SplitPayload(payload)
    local transferId = BuildTransferId()
    local total = table.getn(chunks)

    local ok = SendChatWhisper(target, COMM_VERSION .. "|B|" .. transferId .. "|" .. tostring(total))
    for i = 1, total do
        if not SendChatWhisper(target, COMM_VERSION .. "|C|" .. transferId .. "|" .. tostring(i) .. "|" .. chunks[i]) then
            ok = false
        end
    end
    if not SendChatWhisper(target, COMM_VERSION .. "|E|" .. transferId) then
        ok = false
    end

    sentTransfers[transferId] = {
        target = target,
        noteGuid = currentGuid,
        total = total,
        started = time(),
        title = note.title or "Untitled",
        chunks = chunks,
        returnMode = "CHATWHISPER",
    }

    WowNoteDB.share.sent = (WowNoteDB.share.sent or 0) + 1
    if shareStatusText then
        shareStatusText:SetText("Sent to " .. target .. " via normal whisper (" .. tostring(total) .. " packets). Waiting for receiver...")
    end

    if ok then
        Print("Note transfer sent to " .. target .. " via normal whisper (" .. tostring(total) .. " packets). Waiting for receiver response.")
    else
        Print("Could not send all WowNote chat packets to " .. target .. ". Check the player name and that the target is online.")
    end
end

local function SendCurrentNoteToPlayerViaChannel(target)
    InitDB()
    target = Trim(target or "")
    local normalizedTarget, strippedRealm = NormalizeShareTarget(target)
    target = normalizedTarget

    if target == "" then
        Print("No recipient specified.")
        return
    end

    if strippedRealm then
        Print("WotLK 3.3.5a uses local character names for channel fallback. Sending to " .. target .. ".")
    end

    if not currentGuid or not WowNoteDB.notes[currentGuid] then
        Print("No saved note selected. Save first or select a note on the left.")
        return
    end

    if not SendChatMessage then
        Print("Channel communication is not available in this client.")
        return
    end

    JoinWowNoteChannel(false)

    local note = WowNoteDB.notes[currentGuid]
    local serialized = SerializeNote(note)
    local compressed = CompressText(serialized)
    local payload = "B64:" .. Base64Encode(compressed)
    local chunks = SplitPayload(payload)
    local transferId = BuildTransferId()
    local total = table.getn(chunks)

    local ok = SendChatChannel(target, COMM_VERSION .. "|B|" .. transferId .. "|" .. tostring(total))
    for i = 1, total do
        if not SendChatChannel(target, COMM_VERSION .. "|C|" .. transferId .. "|" .. tostring(i) .. "|" .. chunks[i]) then
            ok = false
        end
    end
    if not SendChatChannel(target, COMM_VERSION .. "|E|" .. transferId) then
        ok = false
    end

    sentTransfers[transferId] = {
        target = target,
        total = total,
        started = time(),
        title = note.title or "Untitled",
    }

    WowNoteDB.share.sent = (WowNoteDB.share.sent or 0) + 1
    if shareStatusText then
        shareStatusText:SetText("Sent to " .. target .. " via channel (" .. tostring(total) .. " packets). Waiting for receiver...")
    end

    if ok then
        Print("Note transfer sent to " .. target .. " via channel " .. COMM_CHANNEL_NAME .. " (" .. tostring(total) .. " packets). Waiting for receiver response.")
    else
        Print("Could not send all WowNote channel packets to " .. target .. ". If this was the first try, wait a second and send again after the channel join completes.")
    end
end

local function DecodeTransferItem(transfer)
    local payload = table.concat(transfer.chunks, "")
    local compressed
    if string.sub(payload or "", 1, 4) == "B64:" then
        compressed = Base64Decode(string.sub(payload, 5))
    else
        compressed = PercentDecode(payload)
    end
    local serialized = DecompressText(compressed)
    if WowNote_IsGenericTransferSerialized and WowNote_IsGenericTransferSerialized(serialized) and WowNote_DecodeGenericTransferSerialized then
        local item = WowNote_DecodeGenericTransferSerialized(serialized)
        if item then return item end
    end
    return { type = "note", title = "Shared note", data = DeserializeNote(serialized) }
end

local function SaveIncomingNote(pendingId)
    InitDB()
    local pending = pendingIncomingNotes[pendingId]
    if not pending or not pending.item then
        Print("Shared WowNote data request is no longer available.")
        return
    end

    local sender = pending.sender
    local ok, msg
    if WowNote_SaveTransferredDataItem then
        ok, msg = WowNote_SaveTransferredDataItem(pending.item, sender)
    else
        ok, msg = false, "Data import handler is not available."
    end

    if ok then
        WowNoteDB.share.received = (WowNoteDB.share.received or 0) + 1
        pendingIncomingNotes[pendingId] = nil
        if pending.transferId then
            SendShareAck(sender, pending.transferId, "saved", pending.returnMode)
        end
        if listFrame then RefreshList() end
        Print(msg or "Shared WowNote data saved.")
    else
        Print(msg or "Shared WowNote data could not be saved.")
    end
end

local function SaveReceivedNoteDirect(sender, item, transfer)
    InitDB()
    local ok, msg
    if WowNote_SaveTransferredDataItem then
        ok, msg = WowNote_SaveTransferredDataItem(item, sender)
    else
        ok, msg = false, "Data import handler is not available."
    end

    if ok then
        WowNoteDB.share.received = (WowNoteDB.share.received or 0) + 1
        if transfer and transfer.id then
            SendShareAck(sender, transfer.id, "saved", transfer.returnMode)
        end
        if listFrame then RefreshList() end
        Print("Accepted WowNote transfer from " .. tostring(sender or "Unknown") .. ": " .. tostring(msg or item.title or "data"))
    else
        Print(msg or "Accepted WowNote transfer could not be saved.")
    end
end

StaticPopupDialogs["WOWNOTE_ACCEPT_SHARED_NOTE"] = {
    text = "Accept WowNote data from %s?\n\n%s",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(self, pendingId)
        SaveIncomingNote(pendingId)
    end,
    OnCancel = function(self, pendingId)
        local pending = pendingIncomingNotes[pendingId]
        if pending and pending.transferId then
            SendShareAck(pending.sender, pending.transferId, "declined", pending.returnMode)
        end
        pendingIncomingNotes[pendingId] = nil
        Print("Shared WowNote data declined.")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWNOTE_ACCEPT_TRANSFER_REQUEST"] = {
    text = "Accept WowNote transfer from %s?\n\n%s",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(self, requestId)
        local request = pendingIncomingTransferRequests[requestId]
        if not request then
            Print("WowNote transfer request is no longer available.")
            return
        end
        approvedIncomingTransfers[request.transferId] = true
        SendShareAck(request.sender, request.transferId, "request-accepted", request.returnMode)
        pendingIncomingTransferRequests[requestId] = nil
        if shareReceiveStatusText then
            shareReceiveStatusText:SetText("Accepted request from " .. tostring(request.sender or "Unknown") .. ". Waiting for packets...")
        end
        Print("Accepted WowNote transfer from " .. tostring(request.sender or "Unknown") .. ". Waiting for packets...")
    end,
    OnCancel = function(self, requestId)
        local request = pendingIncomingTransferRequests[requestId]
        if request then
            SendShareAck(request.sender, request.transferId, "declined", request.returnMode)
            pendingIncomingTransferRequests[requestId] = nil
        end
        Print("WowNote transfer declined.")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 4,
}

local function StoreReceivedNote(sender, transfer)
    InitDB()
    local item = DecodeTransferItem(transfer)
    incomingTransfers[transfer.id] = nil
    if commMaintenanceFrame and not HasIncompleteIncomingTransfers() then
        commMaintenanceFrame:Hide()
    end

    if type(item) ~= "table" then
        Print("Received WowNote data could not be decoded.")
        SendShareAck(sender, transfer.id, "declined", transfer.returnMode)
        return
    end

    local title = Trim(item.title or item.key or item.type or "WowNote data")
    if title == "" then title = "WowNote data" end

    if transfer.approved then
        approvedIncomingTransfers[transfer.id] = nil
        SaveReceivedNoteDirect(sender, item, transfer)
        if shareReceiveStatusText then
            shareReceiveStatusText:SetText("Saved data from " .. tostring(sender or "Unknown") .. ": " .. tostring(title))
        end
        return
    end

    local pendingId = tostring(sender or "Unknown") .. ":" .. tostring(transfer.id or BuildTransferId())
    pendingIncomingNotes[pendingId] = {
        sender = sender,
        item = item,
        received = time(),
        transferId = transfer.id,
        returnMode = transfer.returnMode,
    }

    SendShareAck(sender, transfer.id, "received", transfer.returnMode)

    local summary = tostring(title)
    if string.len(summary) > 60 then
        summary = string.sub(summary, 1, 57) .. "..."
    end

    if StaticPopup_Show then
        StaticPopup_Show("WOWNOTE_ACCEPT_SHARED_NOTE", tostring(sender or "Unknown"), summary, pendingId)
    else
        Print("Shared WowNote data received from " .. tostring(sender or "Unknown") .. ": " .. title .. ". Type /wn to open WowNote.")
    end
end

HandleAddonMessage = function(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX or type(message) ~= "string" then return end
    if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("in", "WNOTE " .. tostring(channel or "?"), string.len(message), true) end

    if commDebug then
        Print("DEBUG recv from " .. tostring(sender or "?") .. " via " .. tostring(channel or "?") .. ": " .. tostring(message or ""))
    end

    local version, command, transferId, rest = string.match(message, "^([^|]+)|([^|]+)|([^|]+)|?(.*)$")
    if version ~= COMM_VERSION or not transferId then return end

    if command == "P" then
        if channel == "CHATWHISPER" then
            SendChatWhisper(sender, COMM_VERSION .. "|O|" .. tostring(transferId) .. "|chatwhisper")
        elseif channel == "WHISPER" then
            SendAddonWhisper(sender, COMM_VERSION .. "|O|" .. tostring(transferId) .. "|whisper")
        elseif channel == "CHANNEL" then
            SendChatChannel(sender, COMM_VERSION .. "|O|" .. tostring(transferId) .. "|channel")
        elseif channel == "PARTY" or channel == "RAID" or channel == "GUILD" or channel == "BATTLEGROUND" then
            SendAddonChannel(channel, COMM_VERSION .. "|O|" .. tostring(transferId) .. "|" .. tostring(string.lower(channel or "channel")))
        else
            SendAddonWhisper(sender, COMM_VERSION .. "|O|" .. tostring(transferId) .. "|unknown")
        end
        Print("Ping received from " .. tostring(sender or "Unknown") .. " via " .. tostring(channel or "?") .. "; pong sent.")
    elseif command == "O" then
        Print("Pong received from " .. tostring(sender or "Unknown") .. " via " .. tostring(channel or "?") .. " (route: " .. tostring(Trim(rest or "?")) .. ").")
    elseif command == "A" then
        local transfer = sentTransfers[transferId]
        local state = Trim(rest or "")
        if transfer then
            if state == "begin" then
                Print("Receiver " .. tostring(sender or transfer.target or "Unknown") .. " answered. Transfer is reaching the other client.")
                if shareStatusText then
                    shareStatusText:SetText("Receiver answered. Sending/assembling packets...")
                end
            elseif state == "request-accepted" then
                if channel == "CHATWHISPER" or channel == "CHANNEL" or channel == "PARTY" or channel == "RAID" or channel == "GUILD" or channel == "BATTLEGROUND" then
                    transfer.returnMode = channel
                else
                    transfer.returnMode = "WHISPER"
                end
                Print("Receiver " .. tostring(sender or transfer.target or "Unknown") .. " accepted the transfer request. Sending packets via " .. tostring(transfer.returnMode or "WHISPER") .. "...")
                if shareStatusText then
                    shareStatusText:SetText("Receiver accepted request. Sending packets via " .. tostring(transfer.returnMode or "WHISPER") .. "...")
                end
                SendPreparedTransfer(transferId)
            elseif string.sub(state, 1, 8) == "missing:" then
                local listText = string.sub(state, 9)
                local indices = ParsePacketList(listText, transfer.total)
                if table.getn(indices) > 0 then
                    if channel == "CHATWHISPER" or channel == "CHANNEL" or channel == "PARTY" or channel == "RAID" or channel == "GUILD" or channel == "BATTLEGROUND" then
                        transfer.returnMode = channel
                    end
                    Print("Receiver " .. tostring(sender or transfer.target or "Unknown") .. " is missing packet(s): " .. PacketListToText(indices) .. ". Resending only those.")
                    SendSelectedTransferPackets(transferId, indices, "missing")
                end
            elseif state == "received" then
                Print("Receiver " .. tostring(sender or transfer.target or "Unknown") .. " got the WowNote transfer and should see the accept dialog.")
                if shareStatusText then
                    shareStatusText:SetText("Receiver got transfer. Waiting for accept/decline...")
                end
            elseif state == "accepted" or state == "saved" then
                Print("Receiver " .. tostring(sender or transfer.target or "Unknown") .. " saved the shared note.")
                if shareStatusText then
                    shareStatusText:SetText("Receiver saved the note. Transfer complete.")
                end
                sentTransfers[transferId] = nil
            elseif state == "auth-required" then
                Print("Receiver " .. tostring(sender or transfer.target or "Unknown") .. " is not in receive mode.")
                if shareStatusText then
                    shareStatusText:SetText("Receiver is not in receive mode. Ask them to open Share and enable Receive.")
                end
                sentTransfers[transferId] = nil
            elseif state == "auth-failed" then
                Print("Receiver " .. tostring(sender or transfer.target or "Unknown") .. " rejected the transfer code.")
                if shareStatusText then
                    shareStatusText:SetText("Receiver code rejected. Check the code and send again.")
                end
                sentTransfers[transferId] = nil
            elseif state == "declined" then
                Print("Receiver " .. tostring(sender or transfer.target or "Unknown") .. " declined the shared note.")
                if shareStatusText then
                    shareStatusText:SetText("Receiver declined the note.")
                end
                sentTransfers[transferId] = nil
            end
        end
    elseif command == "M" then
        local totalText, sizeText, authText, titleText = string.match(rest or "", "^([^|]+)|([^|]+)|([^|]+)|(.*)$")
        if not titleText then
            totalText, sizeText, titleText = string.match(rest or "", "^([^|]+)|([^|]+)|(.*)$")
            authText = ""
        end
        local total = tonumber(totalText or "0") or 0
        local size = tonumber(sizeText or "0") or 0
        if total <= 0 or total > 200 or size < 0 or size > 65535 then return end

        local allowed, reason = IsDataReceiveAllowed(PercentDecode(authText or ""))
        if not allowed then
            if reason == "receive-disabled" then
                SendShareAck(sender, transferId, "auth-required", channel)
            else
                SendShareAck(sender, transferId, "auth-failed", channel)
            end
            return
        end

        local title = PercentDecode(titleText or "")
        if Trim(title or "") == "" then title = "Shared note" end
        local requestId = tostring(sender or "Unknown") .. ":" .. tostring(transferId)

        if approvedIncomingTransfers[transferId] then
            local existing = incomingTransfers[transferId]
            if existing and existing.count and existing.total and existing.count < existing.total then
                existing.returnMode = channel
                RequestMissingPackets(sender, existing, "retry-request")
            else
                SendShareAck(sender, transferId, "request-accepted", channel)
            end
            return
        end
        if pendingIncomingTransferRequests[requestId] then
            return
        end

        pendingIncomingTransferRequests[requestId] = {
            sender = sender,
            transferId = transferId,
            total = total,
            size = size,
            title = title,
            returnMode = channel,
            received = time(),
        }

        local summary = title .. "\nPackets: " .. tostring(total) .. "\nSize: " .. tostring(size) .. " bytes"
        Print("WowNote transfer request received from " .. tostring(sender or "Unknown") .. ": " .. title .. ".")
        if shareReceiveStatusText then
            shareReceiveStatusText:SetText("Request from " .. tostring(sender or "Unknown") .. ": " .. tostring(title) .. " (" .. tostring(total) .. " packets).")
        end
        if StaticPopup_Show then
            StaticPopup_Show("WOWNOTE_ACCEPT_TRANSFER_REQUEST", tostring(sender or "Unknown"), summary, requestId)
        else
            Print("Popup support is unavailable. Transfer cannot be accepted through the UI.")
        end
    elseif command == "B" then
        if not approvedIncomingTransfers[transferId] then
            SendShareAck(sender, transferId, "auth-required", channel)
            return
        end
        local total = tonumber(rest or "0") or 0
        if total <= 0 or total > 200 then return end
        local existing = incomingTransfers[transferId]
        if existing and existing.total == total then
            existing.sender = sender
            existing.returnMode = channel
            existing.approved = approvedIncomingTransfers[transferId] and true or false
            existing.lastPacketAt = time and time() or existing.lastPacketAt
            SendShareAck(sender, transferId, "begin", channel)
            RequestMissingPackets(sender, existing, "resume-begin")
            if shareReceiveStatusText then
                shareReceiveStatusText:SetText("Resuming from " .. tostring(sender or "Unknown") .. ": " .. tostring(existing.count or 0) .. "/" .. tostring(total) .. " packets.")
            end
            EnsureCommMaintenanceFrame()
            return
        end
        incomingTransfers[transferId] = {
            id = transferId,
            sender = sender,
            total = total,
            chunks = {},
            count = 0,
            started = time(),
            lastPacketAt = time(),
            returnMode = channel,
            approved = approvedIncomingTransfers[transferId] and true or false,
        }
        SendShareAck(sender, transferId, "begin", channel)
        EnsureCommMaintenanceFrame()
        if shareReceiveStatusText then
            shareReceiveStatusText:SetText("Receiving from " .. tostring(sender or "Unknown") .. ": 0/" .. tostring(total) .. " packets.")
        end
    elseif command == "C" then
        local indexText, payload = string.match(rest or "", "^([^|]+)|(.*)$")
        local index = tonumber(indexText or "0") or 0
        local transfer = incomingTransfers[transferId]
        if not transfer or index <= 0 or index > transfer.total then return end
        if not transfer.chunks[index] then
            transfer.count = transfer.count + 1
        end
        transfer.chunks[index] = payload or ""
        transfer.lastPacketAt = time and time() or transfer.lastPacketAt
        if shareReceiveStatusText then
            shareReceiveStatusText:SetText("Receiving from " .. tostring(sender or transfer.sender or "Unknown") .. ": " .. tostring(transfer.count or 0) .. "/" .. tostring(transfer.total or 0) .. " packets.")
        end
        if transfer.count >= transfer.total then
            StoreReceivedNote(sender, transfer)
        end
    elseif command == "E" then
        local transfer = incomingTransfers[transferId]
        if transfer and transfer.count >= transfer.total then
            StoreReceivedNote(sender, transfer)
        elseif transfer then
            RequestMissingPackets(sender, transfer, "end-marker")
        end
    end
end

local function HandleChatWhisper(message, sender)
    if type(message) ~= "string" then return end
    local payload
    if string.sub(message, 1, string.len(CHAT_COMM_MARKER)) == CHAT_COMM_MARKER then
        payload = string.sub(message, string.len(CHAT_COMM_MARKER) + 1)
    elseif string.sub(message, 1, string.len(LEGACY_CHAT_COMM_MARKER)) == LEGACY_CHAT_COMM_MARKER then
        payload = string.sub(message, string.len(LEGACY_CHAT_COMM_MARKER) + 1)
    else
        return
    end
    payload = UnescapeChatPayload(payload)
    HandleAddonMessage(COMM_PREFIX, payload, "CHATWHISPER", sender)
end

local function HandleChatChannel(message, sender, channelName)
    if type(message) ~= "string" then return end
    if channelName and channelName ~= "" and channelName ~= COMM_CHANNEL_NAME then return end

    local framed
    if string.sub(message, 1, string.len(CHAT_COMM_MARKER)) == CHAT_COMM_MARKER then
        framed = string.sub(message, string.len(CHAT_COMM_MARKER) + 1)
    elseif string.sub(message, 1, string.len(LEGACY_CHAT_COMM_MARKER)) == LEGACY_CHAT_COMM_MARKER then
        framed = string.sub(message, string.len(LEGACY_CHAT_COMM_MARKER) + 1)
    else
        return
    end

    local target, payload = string.match(framed or "", "^([^:]+):(.*)$")
    if not target or not payload then
        -- Backward compatibility for the previous broken frame format.
        target, payload = string.match(framed or "", "^([^|]+)|(.*)$")
    end
    if not target or not payload then return end
    payload = UnescapeChatPayload(payload)

    local me = UnitName and UnitName("player") or ""
    if string.lower(NormalizeShareTarget(target or "")) ~= string.lower(me or "") then
        return
    end

    HandleAddonMessage(COMM_PREFIX, payload, "CHANNEL", sender)
end

CreateShareUI = function()
    if shareFrame then return end

    shareFrame = CreateFrame("Frame", "WowNoteShareFrame", UIParent)
    shareFrame:SetWidth(520)
    shareFrame:SetHeight(340)
    shareFrame:SetPoint("CENTER", UIParent, "CENTER", 80, 40)
    shareFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if shareFrame.SetToplevel then shareFrame:SetToplevel(true) end
    shareFrame:SetFrameLevel(100)
    shareFrame:EnableMouse(true)
    shareFrame:SetMovable(true)
    shareFrame:RegisterForDrag("LeftButton")
    EnableRaiseOnInteraction(shareFrame)
    shareFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    shareFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    shareFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    shareFrame:Hide()
    shareFrame:SetScript("OnHide", function()
        SetDataReceiveEnabled(false)
    end)

    local title = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 18, -16)
    title:SetText("Share WowNote note")

    local close = CreateFrame("Button", nil, shareFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", shareFrame, "TOPRIGHT", -4, -4)

    local label = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 22, -54)
    label:SetText("Player name")

    local bg = CreateFrame("Frame", nil, shareFrame)
    bg:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 110, -48)
    bg:SetWidth(220)
    bg:SetHeight(28)
    bg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    bg:SetBackdropColor(0, 0, 0, 0.85)

    shareTargetEdit = MakeEditBox(bg, false)
    shareTargetEdit:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
    shareTargetEdit:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -4, 4)
    shareTargetEdit:SetScript("OnEnterPressed", function(self)
        SendCurrentNoteToPlayer(self:GetText())
        self:ClearFocus()
    end)

    local hint = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 110, -77)
    hint:SetWidth(380)
    hint:SetJustifyH("LEFT")
    hint:SetText("Enter the receiver name, then enter the 4-digit code shown on the receiver client.")

    local codeLabel = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    codeLabel:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 22, -104)
    codeLabel:SetText("4-digit code")

    local codeBg = CreateFrame("Frame", nil, shareFrame)
    codeBg:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 110, -98)
    codeBg:SetWidth(90)
    codeBg:SetHeight(28)
    codeBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    codeBg:SetBackdropColor(0, 0, 0, 0.85)

    shareAuthEdit = MakeEditBox(codeBg, false)
    shareAuthEdit:SetPoint("TOPLEFT", codeBg, "TOPLEFT", 4, -4)
    shareAuthEdit:SetPoint("BOTTOMRIGHT", codeBg, "BOTTOMRIGHT", -4, 4)
    if shareAuthEdit.SetMaxLetters then shareAuthEdit:SetMaxLetters(4) end
    if shareAuthEdit.SetNumeric then shareAuthEdit:SetNumeric(true) end
    shareAuthEdit:SetScript("OnEnterPressed", function(self)
        SendCurrentNoteToPlayer(shareTargetEdit:GetText())
        self:ClearFocus()
    end)

    local codeHint = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    codeHint:SetPoint("LEFT", codeBg, "RIGHT", 8, 0)
    codeHint:SetWidth(260)
    codeHint:SetJustifyH("LEFT")
    codeHint:SetText("Required before sending. No request is sent without this 4-digit code.")

    local targetButton = MakeButton(shareFrame, "Target", 70, 24)
    targetButton:SetPoint("LEFT", bg, "RIGHT", 8, 0)
    targetButton:SetScript("OnClick", function()
        if UnitName and UnitExists and UnitIsPlayer and UnitExists("target") and UnitIsPlayer("target") then
            shareTargetEdit:SetText(UnitName("target"))
            shareStatusText:SetText("Current target copied.")
        else
            shareStatusText:SetText("No player target selected.")
        end
    end)

    local sendButton = MakeButton(shareFrame, "Send", 80, 24)
    sendButton:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 74, -140)
    sendButton:SetScript("OnClick", function()
        if WowNote_OpenDataSendPicker then
            WowNote_OpenDataSendPicker(shareTargetEdit:GetText(), shareAuthEdit and shareAuthEdit:GetText() or "")
        else
            SendCurrentNoteToPlayer(shareTargetEdit:GetText())
        end
    end)

    local sendTargetButton = MakeButton(shareFrame, "Send target", 110, 24)
    sendTargetButton:SetPoint("LEFT", sendButton, "RIGHT", 8, 0)
    sendTargetButton:SetScript("OnClick", function()
        if UnitName and UnitExists and UnitIsPlayer and UnitExists("target") and UnitIsPlayer("target") then
            local name = UnitName("target")
            shareTargetEdit:SetText(name)
            if WowNote_OpenDataSendPicker then
                WowNote_OpenDataSendPicker(name, shareAuthEdit and shareAuthEdit:GetText() or "")
            else
                SendCurrentNoteToPlayer(name)
            end
        else
            shareStatusText:SetText("No player target selected.")
        end
    end)

    local closeButton = MakeButton(shareFrame, "Close", 80, 24)
    closeButton:SetPoint("LEFT", sendTargetButton, "RIGHT", 8, 0)
    closeButton:SetScript("OnClick", function() shareFrame:Hide() end)

    local receiveTitle = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    receiveTitle:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 22, -220)
    receiveTitle:SetText("Receive data")

    shareReceiveButton = MakeButton(shareFrame, "Receive: OFF", 110, 24)
    shareReceiveButton:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 110, -214)
    shareReceiveButton:SetScript("OnClick", function()
        if dataReceiveEnabled then
            SetDataReceiveEnabled(false)
            SetShareStatus("Receiving disabled.")
        else
            dataReceiveCode = BuildReceiveCode()
            SetDataReceiveEnabled(true)
            SetShareStatus("Receiving enabled. Give the code to the sender.")
        end
    end)

    shareReceiveCodeText = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shareReceiveCodeText:SetPoint("LEFT", shareReceiveButton, "RIGHT", 10, 0)
    shareReceiveCodeText:SetWidth(250)
    shareReceiveCodeText:SetJustifyH("LEFT")

    shareReceiveStatusText = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    shareReceiveStatusText:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 22, -246)
    shareReceiveStatusText:SetWidth(476)
    shareReceiveStatusText:SetJustifyH("LEFT")

    shareStatusText = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shareStatusText:SetPoint("TOPLEFT", shareFrame, "TOPLEFT", 22, -180)
    shareStatusText:SetWidth(476)
    shareStatusText:SetJustifyH("LEFT")
    shareStatusText:SetText("Recipient must have WowNote installed. Manual input: Player or Player-Realm.")
    RefreshReceiveStatus()
end

WowNote_OpenShare = function()
    CreateUI()
    CreateShareUI()
    shareFrame:Show()
    RefreshReceiveStatus()
    RaiseFrame(shareFrame)
    if shareTargetEdit then
        shareTargetEdit:SetFocus()
    end
end

_G.WowNote_OpenShare = WowNote_OpenShare

CreateUI = function()
    if frame then return end

    frame = CreateFrame("Frame", "WowNoteFrame", UIParent)
    frame:SetWidth(910)
    frame:SetHeight(540)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    EnableRaiseOnInteraction(frame)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    local addonVersion = GetAddOnMetadata and GetAddOnMetadata("WoWNote", "Version")
    title:SetText(addonVersion and addonVersion ~= "" and ("WowNote v" .. addonVersion) or "WowNote")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -52)
    listLabel:SetText("Notes")

    local normalNotesTab = MakeButton(frame, "Normal", 72, 22)
    normalNotesTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -47)
    normalNotesTab:SetScript("OnClick", function()
        if listFrame then RefreshList() end
    end)

    local characterNotesTab = MakeButton(frame, "Characters", 92, 22)
    characterNotesTab:SetPoint("LEFT", normalNotesTab, "RIGHT", 4, 0)
    characterNotesTab:SetScript("OnClick", function()
        if WowNote_OpenCharacterNotes then WowNote_OpenCharacterNotes() else Print("Character Notes module is not loaded.") end
    end)

    local leftBg = CreateFrame("Frame", nil, frame)
    leftBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -70)
    leftBg:SetWidth(220)
    leftBg:SetHeight(423)
    leftBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    leftBg:SetBackdropColor(0, 0, 0, 0.75)

    local listScroll = CreateFrame("ScrollFrame", "WowNoteListScrollFrame", leftBg, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", leftBg, "TOPLEFT", 8, -8)
    listScroll:SetPoint("BOTTOMRIGHT", leftBg, "BOTTOMRIGHT", -28, 8)
    listScroll:EnableMouse(true)
    listScroll:SetFrameLevel(leftBg:GetFrameLevel() + 2)

    listFrame = CreateFrame("Frame", nil, listScroll)
    listFrame:SetWidth(185)
    listFrame:SetHeight(400)
    listFrame:EnableMouse(true)
    listFrame:SetFrameLevel(listScroll:GetFrameLevel() + 1)
    listScroll:SetScrollChild(listFrame)

    local titleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 256, -52)
    titleLabel:SetText("Title")

    local titleBg = CreateFrame("Frame", nil, frame)
    titleBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 256, -70)
    titleBg:SetWidth(470)
    titleBg:SetHeight(28)
    titleBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    titleBg:SetBackdropColor(0, 0, 0, 0.85)

    titleEdit = MakeEditBox(titleBg, false)
    titleEdit:SetPoint("TOPLEFT", titleBg, "TOPLEFT", 4, -4)
    titleEdit:SetPoint("BOTTOMRIGHT", titleBg, "BOTTOMRIGHT", -4, 4)
    titleEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        SetEditMode(true)
        FocusContentEditor()
    end)
    titleEdit:SetScript("OnTabPressed", function(self)
        self:ClearFocus()
        SetEditMode(true)
        FocusContentEditor()
    end)

    local contentLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contentLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 256, -110)
    contentLabel:SetText("Content - Markdown view; Shift-click item links are preserved")

    local contentBg = CreateFrame("Frame", nil, frame)
    contentBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 256, -130)
    contentBg:SetWidth(470)
    contentBg:SetHeight(275)
    contentBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    contentBg:SetBackdropColor(0, 0, 0, 0.85)
    contentBg:EnableMouse(true)
    contentBg:SetScript("OnMouseDown", function()
        SetEditMode(true)
        FocusContentEditor()
    end)

    contentScroll = CreateFrame("ScrollFrame", "WowNoteContentScrollFrame", contentBg, "UIPanelScrollFrameTemplate")
    contentScroll:SetPoint("TOPLEFT", contentBg, "TOPLEFT", 4, -4)
    contentScroll:SetPoint("BOTTOMRIGHT", contentBg, "BOTTOMRIGHT", -28, 4)
    contentScroll:EnableMouse(true)
    contentScroll:SetScript("OnMouseDown", function()
        SetEditMode(true)
        FocusContentEditor()
    end)

    contentViewFrame = CreateFrame("Frame", nil, contentScroll)
    contentViewFrame:SetWidth(422)
    contentViewFrame:SetHeight(245)
    contentViewFrame:EnableMouse(true)
    contentViewFrame:SetScript("OnMouseDown", function()
        SetEditMode(true)
        FocusContentEditor()
    end)
    contentViewMessage = nil
    contentViewText = contentViewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contentViewText:SetPoint("TOPLEFT", contentViewFrame, "TOPLEFT", 6, -6)
    contentViewText:SetWidth(410)
    contentViewText:SetJustifyH("LEFT")
    contentViewText:SetJustifyV("TOP")
    contentViewText:SetTextColor(1, 1, 1, 1)
    contentViewText:SetText("")
    contentViewFrame:EnableMouseWheel(true)
    contentViewFrame:SetScript("OnMouseWheel", function(self, delta)
        ScrollMarkdownView(delta)
    end)
    contentBg:EnableMouseWheel(true)
    contentBg:SetScript("OnMouseWheel", function(self, delta)
        if not editMode then
            ScrollMarkdownView(delta)
        end
    end)
    contentEdit = MakeEditBox(contentScroll, true)
    contentEdit:SetWidth(422)
    contentEdit:SetHeight(1800)
    contentEdit:SetScript("OnMouseDown", function(self)
        if titleEdit and titleEdit.ClearFocus then titleEdit:ClearFocus() end
        self:SetFocus()
    end)
    contentEdit:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if ScrollingEdit_OnCursorChanged then
            ScrollingEdit_OnCursorChanged(self, x, y, w, h)
        end
    end)
    WowNoteProfiler_SetScript(contentEdit, "OnUpdate", "Core.NoteEditor", function(self, elapsed)
        if ScrollingEdit_OnUpdate then
            ScrollingEdit_OnUpdate(self, elapsed, self:GetParent())
        end
    end)
    contentEdit:SetScript("OnTextChanged", function(self)
        if ScrollingEdit_OnTextChanged then
            ScrollingEdit_OnTextChanged(self, self:GetParent())
        end
    end)
    contentScroll:SetScrollChild(contentViewFrame)

    contentModeText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    contentModeText:SetPoint("TOPLEFT", frame, "TOPLEFT", 256, -410)
    contentModeText:SetText("View: rendered Markdown")

    local newButton = MakeButton(frame, "New", 70, 24)
    newButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 256, -424)
    newButton:SetScript("OnClick", ClearEditor)

    local saveButton = MakeButton(frame, "Save", 75, 24)
    saveButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 342, -424)
    saveButton:SetScript("OnClick", function() SaveNote(false) end)

    local deleteButton = MakeButton(frame, "Delete", 75, 24)
    deleteButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 428, -424)
    deleteButton:SetScript("OnClick", function() DeleteNote() end)

    editToggleButton = MakeButton(frame, "Edit", 75, 24)
    editToggleButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 514, -424)
    editToggleButton:SetScript("OnClick", function() SetEditMode(not editMode) end)

    if WowNote_BuildSideMenu then
        WowNote_BuildSideMenu(frame, MakeButton)
    else
        local sideTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sideTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 748, -52)
        sideTitle:SetText("Main")
        local notesButton = MakeButton(frame, "Notes", 130, 24)
        notesButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 748, -76)
        notesButton:SetScript("OnClick", function() WowNote_Open() end)
        local settingsButton = MakeButton(frame, "Settings", 130, 24)
        settingsButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 748, -106)
        settingsButton:SetScript("OnClick", function() if WowNote_OpenSettings then WowNote_OpenSettings() end end)
    end

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 18)
    statusText:SetText("Ready")

    frame:SetScript("OnShow", function()
        InitDB()
        RefreshList()
        if not currentGuid then
            ClearEditor()
        end
    end)
end

function WowNote_Toggle()
    CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        RaiseFrame(frame)
    end
end

function WowNote_Open()
    CreateUI()
    frame:Show()
    RaiseFrame(frame)
end


-- Shared helpers for split module files.
-- Keep these small and stable so feature modules do not need to duplicate core helpers.
WowNote_Internal = WowNote_Internal or {}
WowNote_Internal.InitDB = InitDB
WowNote_Internal.MakeButton = MakeButton
WowNote_Internal.RaiseFrame = RaiseFrame
WowNote_Internal.PercentEncode = PercentEncode
WowNote_Internal.PercentDecode = PercentDecode
WowNote_Internal.Base64Encode = Base64Encode
WowNote_Internal.Base64Decode = Base64Decode
WowNote_Internal.Trim = Trim
WowNote_Internal.MakeEditBox = MakeEditBox
WowNote_Internal.CompressText = CompressText
WowNote_Internal.DecompressText = DecompressText

local function WowNote_LoadItemModule()
local wowNoteChatEditInsertLink = nil
local modifiedItemHookInstalled = false
local lastInsertedLink = nil
local lastInsertedAt = -1

local function TryInsertLinkIntoCurrentNote(text)
    if not (frame and frame:IsShown() and contentEdit) then
        return false
    end
    if type(text) ~= "string" or text == "" then
        return false
    end

    InsertTextIntoEditor(text)
    lastInsertedLink = text
    lastInsertedAt = GetTime and GetTime() or 0
    return true
end

HookItemLinks = function()
    if ChatEdit_InsertLink and ChatEdit_InsertLink ~= wowNoteChatEditInsertLink then
        originalChatEditInsertLink = ChatEdit_InsertLink
        wowNoteChatEditInsertLink = function(text)
            if TryInsertLinkIntoCurrentNote(text) then
                return true
            end
            if originalChatEditInsertLink then
                return originalChatEditInsertLink(text)
            end
            return false
        end
        ChatEdit_InsertLink = wowNoteChatEditInsertLink
    end

    -- Some inventory-style item buttons route modified clicks through
    -- HandleModifiedItemClick without reaching ChatEdit_InsertLink when no chat
    -- edit box is active. Use a secure post-hook instead of replacing the global
    -- function, because replacing it can taint unrelated UI actions.
    if hooksecurefunc and HandleModifiedItemClick and not modifiedItemHookInstalled then
        local ok = pcall(hooksecurefunc, "HandleModifiedItemClick", function(link)
            if not (link and IsModifiedClick and IsModifiedClick("CHATLINK")) then return end
            local now = GetTime and GetTime() or 0
            if lastInsertedLink == link and lastInsertedAt >= 0 and (now - lastInsertedAt) < 0.2 then
                return
            end
            TryInsertLinkIntoCurrentNote(link)
        end)
        modifiedItemHookInstalled = ok and true or false
    end
end


local function ExtractFirstItemLink(text)
    text = text or ""
    local link = string.match(text, "(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)")
    if link then return link end
    link = string.match(text, "(|Hitem:[^|]+|h%[[^%]]+%]|h)")
    return link
end

local function GetItemNameFromLink(link)
    if not link then return "" end
    local name = string.match(link, "%[([^%]]+)%]")
    return name or link
end

local function SortItems()
    local sorted = {}
    InitDB()
    for guid, item in pairs(WowNoteDB.items) do
        if type(item) == "table" then
            table.insert(sorted, { guid = guid, name = item.name or GetItemNameFromLink(item.link), link = item.link or "" })
        end
    end
    table.sort(sorted, function(a, b)
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    return sorted
end

local function SetItemStatus(text)
    if itemStatusText then
        itemStatusText:SetText(text or "")
    end
    SetStatus(text or "")
end

local function LoadItem(itemGuid)
    InitDB()
    local item = WowNoteDB.items[itemGuid]
    if not item then
        SetItemStatus("Item not found")
        return
    end
    currentItemGuid = itemGuid
    if itemNameEdit then itemNameEdit:SetText(item.name or GetItemNameFromLink(item.link)) end
    if itemLinkEdit then itemLinkEdit:SetText(item.link or "") end
    RefreshItemList()
end

local function ClearItemEditor()
    currentItemGuid = nil
    if itemNameEdit then itemNameEdit:SetText("") end
    if itemLinkEdit then itemLinkEdit:SetText("") end
    SetItemStatus("New item")
    RefreshItemList()
end

SaveItem = function(forceNew)
    InitDB()
    local raw = itemLinkEdit and itemLinkEdit:GetText() or ""
    local link = ExtractFirstItemLink(raw)
    if not link then
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" then
            link = itemLink or (itemID and select(2, GetItemInfo(itemID)))
            ClearCursor()
        end
    end
    if not link then
        SetItemStatus("No item link found")
        return
    end

    local name = Trim(itemNameEdit and itemNameEdit:GetText() or "")
    if name == "" then
        name = GetItemNameFromLink(link)
    end

    if forceNew or not currentItemGuid or not WowNoteDB.items[currentItemGuid] then
        currentItemGuid = GenerateGUID()
        WowNoteDB.items[currentItemGuid] = {
            guid = currentItemGuid,
            created = time(),
        }
    end

    local item = WowNoteDB.items[currentItemGuid]
    item.guid = currentItemGuid
    item.name = name
    item.link = link
    item.updated = time()

    if itemNameEdit then itemNameEdit:SetText(name) end
    if itemLinkEdit then itemLinkEdit:SetText(link) end
    SetItemStatus("Item saved: " .. name)
    RefreshItemList()
end

DeleteItem = function(itemGuid)
    InitDB()
    local targetGuid = itemGuid or currentItemGuid
    if not targetGuid or not WowNoteDB.items[targetGuid] then
        SetItemStatus("No item selected")
        return
    end
    local oldName = WowNoteDB.items[targetGuid].name or GetItemNameFromLink(WowNoteDB.items[targetGuid].link)
    WowNoteDB.items[targetGuid] = nil
    if currentItemGuid == targetGuid then
        ClearItemEditor()
    else
        RefreshItemList()
    end
    SetItemStatus("Item deleted: " .. oldName)
end

InsertSelectedItemIntoNote = function(itemGuid)
    InitDB()
    local targetGuid = itemGuid or currentItemGuid
    local item = targetGuid and WowNoteDB.items[targetGuid]
    if not item or not item.link then
        SetItemStatus("No item selected")
        return
    end
    WowNote_Open()
    InsertTextIntoEditor(item.link)
    SetItemStatus("Item inserted into note: " .. (item.name or GetItemNameFromLink(item.link)))
end

ShowItemContextMenu = function(itemGuid)
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "WowNoteContextMenu", UIParent, "UIDropDownMenuTemplate")
    end
    local menu = {
        {
            text = "Insert into note",
            notCheckable = 1,
            func = function() InsertSelectedItemIntoNote(itemGuid) end,
        },
        {
            text = "Save",
            notCheckable = 1,
            func = function()
                currentItemGuid = itemGuid
                SaveItem(false)
            end,
        },
        {
            text = "Delete",
            notCheckable = 1,
            func = function() DeleteItem(itemGuid) end,
        },
        {
            text = "Save as new",
            notCheckable = 1,
            func = function() SaveItem(true) end,
        },
        {
            text = "Cancel",
            notCheckable = 1,
            func = function() end,
        },
    }
    if EasyMenu then
        EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
    end
end

RefreshItemList = function()
    if not itemListFrame then return end
    InitDB()
    local sorted = SortItems()
    for i = 1, table.getn(itemButtons) do
        itemButtons[i]:Hide()
    end

    local last
    for i = 1, table.getn(sorted) do
        local info = sorted[i]
        local button = itemButtons[i]
        if not button then
            button = CreateFrame("Button", nil, itemListFrame)
            button:SetHeight(22)
            button:SetWidth(220)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button.selectedTexture = button:CreateTexture(nil, "BACKGROUND")
            button.selectedTexture:SetAllPoints(button)
            button.selectedTexture:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            button.selectedTexture:SetBlendMode("ADD")
            button.selectedTexture:Hide()
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("LEFT", button, "LEFT", 4, 0)
            button.text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
            button.text:SetJustifyH("LEFT")
            button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            itemButtons[i] = button
        end
        button.itemGuid = info.guid
        button.text:SetText(info.link ~= "" and info.link or info.name)
        if currentItemGuid == info.guid then
            button.selectedTexture:Show()
        else
            button.selectedTexture:Hide()
        end
        button:ClearAllPoints()
        if last then
            button:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
        else
            button:SetPoint("TOPLEFT", itemListFrame, "TOPLEFT", 0, 0)
        end
        button:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                LoadItem(self.itemGuid)
                ShowItemContextMenu(self.itemGuid)
            else
                LoadItem(self.itemGuid)
            end
        end)
        button:SetScript("OnEnter", function(self)
            local item = WowNoteDB.items[self.itemGuid]
            if item and item.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.link)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:Show()
        last = button
    end
    itemListFrame:SetHeight(math.max(320, table.getn(sorted) * 24))
end

CreateItemUI = function()
    if itemFrame then return end

    itemFrame = CreateFrame("Frame", "WowNoteItemFrame", UIParent)
    itemFrame:SetWidth(620)
    itemFrame:SetHeight(430)
    itemFrame:SetPoint("CENTER", UIParent, "CENTER", 60, -35)
    itemFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if itemFrame.SetToplevel then itemFrame:SetToplevel(true) end
    itemFrame:SetFrameLevel(100)
    itemFrame:EnableMouse(true)
    itemFrame:SetMovable(true)
    itemFrame:RegisterForDrag("LeftButton")
    EnableRaiseOnInteraction(itemFrame)
    itemFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    itemFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    itemFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    itemFrame:Hide()

    local title = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 18, -16)
    title:SetText("WowNote Items")

    local close = CreateFrame("Button", nil, itemFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", itemFrame, "TOPRIGHT", -4, -4)

    local listLabel = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 22, -52)
    listLabel:SetText("Saved items (right-click for options)")

    local leftBg = CreateFrame("Frame", nil, itemFrame)
    leftBg:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 18, -70)
    leftBg:SetWidth(270)
    leftBg:SetHeight(295)
    leftBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    leftBg:SetBackdropColor(0, 0, 0, 0.75)

    local itemScroll = CreateFrame("ScrollFrame", "WowNoteItemListScrollFrame", leftBg, "UIPanelScrollFrameTemplate")
    itemScroll:SetPoint("TOPLEFT", leftBg, "TOPLEFT", 8, -8)
    itemScroll:SetPoint("BOTTOMRIGHT", leftBg, "BOTTOMRIGHT", -28, 8)

    itemListFrame = CreateFrame("Frame", nil, itemScroll)
    itemListFrame:SetWidth(225)
    itemListFrame:SetHeight(320)
    itemScroll:SetScrollChild(itemListFrame)

    local nameLabel = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 310, -52)
    nameLabel:SetText("Name")

    local nameBg = CreateFrame("Frame", nil, itemFrame)
    nameBg:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 310, -70)
    nameBg:SetWidth(270)
    nameBg:SetHeight(28)
    nameBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    nameBg:SetBackdropColor(0, 0, 0, 0.85)
    itemNameEdit = MakeEditBox(nameBg, false)
    itemNameEdit:SetPoint("TOPLEFT", nameBg, "TOPLEFT", 4, -4)
    itemNameEdit:SetPoint("BOTTOMRIGHT", nameBg, "BOTTOMRIGHT", -4, 4)

    local linkLabel = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    linkLabel:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 310, -110)
    linkLabel:SetText("Item link - Shift-click or drag & drop like in chat")

    local linkBg = CreateFrame("Frame", nil, itemFrame)
    linkBg:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 310, -130)
    linkBg:SetWidth(270)
    linkBg:SetHeight(58)
    linkBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    linkBg:SetBackdropColor(0, 0, 0, 0.85)
    itemLinkEdit = MakeEditBox(linkBg, false)
    itemLinkEdit:SetPoint("TOPLEFT", linkBg, "TOPLEFT", 4, -4)
    itemLinkEdit:SetPoint("BOTTOMRIGHT", linkBg, "BOTTOMRIGHT", -4, 4)

    local hint = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 310, -202)
    hint:SetWidth(270)
    hint:SetJustifyH("LEFT")
    hint:SetText("Shift-click an item from bags/character window or drag it here. Saved items can then be inserted into notes.")

    local newButton = MakeButton(itemFrame, "New", 62, 24)
    newButton:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 310, -265)
    newButton:SetScript("OnClick", ClearItemEditor)

    local saveButton = MakeButton(itemFrame, "Save", 62, 24)
    saveButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 342, -424)
    saveButton:SetScript("OnClick", function() SaveItem(false) end)

    local deleteButton = MakeButton(itemFrame, "Delete", 62, 24)
    deleteButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 428, -424)
    deleteButton:SetScript("OnClick", function() DeleteItem() end)

    local insertButton = MakeButton(itemFrame, "Insert", 82, 24)
    insertButton:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 310, -298)
    insertButton:SetScript("OnClick", function() InsertSelectedItemIntoNote() end)

    local saveAsButton = MakeButton(itemFrame, "Save as new", 105, 24)
    saveAsButton:SetPoint("LEFT", insertButton, "RIGHT", 8, 0)
    saveAsButton:SetScript("OnClick", function() SaveItem(true) end)

    local cursorButton = MakeButton(itemFrame, "Cursor", 70, 24)
    cursorButton:SetPoint("LEFT", saveAsButton, "RIGHT", 8, 0)
    cursorButton:SetScript("OnClick", function()
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" then
            local link = itemLink or (itemID and select(2, GetItemInfo(itemID)))
            ClearCursor()
            if link then
                itemLinkEdit:SetText(link)
                if Trim(itemNameEdit:GetText() or "") == "" then
                    itemNameEdit:SetText(GetItemNameFromLink(link))
                end
                SetItemStatus("Cursor item copied")
            else
                SetItemStatus("Item link is not cached yet")
            end
        else
            SetItemStatus("No item on cursor")
        end
    end)

    itemStatusText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemStatusText:SetPoint("BOTTOMLEFT", itemFrame, "BOTTOMLEFT", 22, 18)
    itemStatusText:SetText("Ready")

    itemFrame:SetScript("OnShow", function()
        InitDB()
        RefreshItemList()
    end)
end

WowNote_OpenItems = function()
    CreateItemUI()
    itemFrame:Show()
    RaiseFrame(itemFrame)
    RefreshItemList()
end

end
WowNote_LoadItemModule()


local function WowNote_LoadTalentModule()
local TALENT_CLASSES = {
    { key = "WARRIOR", name = "Warrior", trees = { "Arms", "Fury", "Protection" }, backgrounds = { "WarriorArms", "WarriorFury", "WarriorProtection" } },
    { key = "PALADIN", name = "Paladin", trees = { "Holy", "Protection", "Retribution" }, backgrounds = { "PaladinHoly", "PaladinProtection", "PaladinCombat" } },
    { key = "HUNTER", name = "Hunter", trees = { "Beast Mastery", "Marksmanship", "Survival" }, backgrounds = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" } },
    { key = "ROGUE", name = "Rogue", trees = { "Assassination", "Combat", "Subtlety" }, backgrounds = { "RogueAssassination", "RogueCombat", "RogueSubtlety" } },
    { key = "PRIEST", name = "Priest", trees = { "Discipline", "Holy", "Shadow" }, backgrounds = { "PriestDiscipline", "PriestHoly", "PriestShadow" } },
    { key = "DEATHKNIGHT", name = "Death Knight", trees = { "Blood", "Frost", "Unholy" }, backgrounds = { "DeathKnightBlood", "DeathKnightFrost", "DeathKnightUnholy" } },
    { key = "SHAMAN", name = "Shaman", trees = { "Elemental", "Enhancement", "Restoration" }, backgrounds = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" } },
    { key = "MAGE", name = "Mage", trees = { "Arcane", "Fire", "Frost" }, backgrounds = { "MageArcane", "MageFire", "MageFrost" } },
    { key = "WARLOCK", name = "Warlock", trees = { "Affliction", "Demonology", "Destruction" }, backgrounds = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" } },
    { key = "DRUID", name = "Druid", trees = { "Balance", "Feral Combat", "Restoration" }, backgrounds = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" } },
}

local TALENT_SPELLDATA = {
DEATHKNIGHT=[=[48979;49483,48997;49490;49491,49182;49500;49501;55225;55226,%48978;49390;49391;49392;49393,49004;49508;49509,55107;55108,%48982,48987;49477;49478;49479;49480,49467;50033;50034,%c48985;49488;49489,!49145;49495;49497,49015;50154;55136,48977;49394;49395,!49006;49526;50029,49005,!h48988;49503;49504,53137;53138,%49027;49542;49543,49016,50365;50371,%62905;62908,49018;49529;49530,55233,%49189;50149;50150,55050,49023;49533;49534,&61154;61155;61156;61157;61158,&49028|49175;50031;51456,49455;50147,49042;49786;49787;49788;49789,&55061;55062,49140;49661;49662;49663;49664,49226;50137;50138,f50880;50884;50885;50886;50887,49039,51468;51472;51473,&51123;51127;51128;51129;51130,49149;50115,49137;49657,!49186;51108;51109,49471;49790;49791,49796,i55610,49024;49538,49188;56822;59057,%50040;50041;50043,49203,50384;50385,%65661;66191;66192,54639;54638;54637,51271,%49200;50151;50152,49143,50187;50190;50191,&49202;50127;50128;50129;50130,&49184|51745;51746,48962;49567;49568,55129;55130;55131;55132;55133,%49036;49562,48963;49564;49565,49588;49589,48965;49571;49572,49013;55236;55237,51459;51462;51463;51464;51465,49158,&49146;51267,49219;49627;49628,55620;55623,49194,49220;49633;49635;49636;49638,49223;49599,%55666;55667,49224;49610;49611,49208;56834;56835,g52143,66799;66814;66815;66816;66817,d51052,50391;50392,d63560,!49032;49631;49632,49222,%49217;49654;49655,c51099;51160;51161,55090,&50117;50118;50119;50120;50121,&49206]=],
WARRIOR=[=[12282;12663;12664,16462;16463;16464;16465;16466,12286;12658,%12285;12697,12300;12959;12960,12295;12676;12677,%12290;12963,12296,16493;16494,a12834;12849;12867,!12163;12711;12712,56636;56637;56638,%12700;12781;12783;12784;12785,12328,12284;12701;12702;12703;12704,12281;12812;12813;12814;12815,20504;20505,!12289;12668;23695,46854;46855,29834;29838,g12294,46865;46866,12862;12330,64976,d35446;35448;35449,46859;46860,%29723;29725;29724,29623,29836;29859,&46867;56611;56612;56613;56614,&46924|61216;61221;61222,12321;12835,12320;12852;12853;12855;12856,&12324;12876;12877;12878;12879,12322;12999;13000;13001;13002,%12329;12950;20496,12323,16487;16489;16492,12318;12857;12858;12860;12861,23584;23585;23586;23587;23588,20502;20503,12317;13045;13046;13047;13048,%29590;29591;29592,12292,29888;29889,%20500;20501,!12319;12971;12972;12973;12974,%46908;46909;56924,e23881,!29721;29776,46910;46911,"29759;29760;29761;29762;29763,60970,e29801,f46913;46914;46915,&56927;56929;56930;56931;56932,&46917|12301;12818,12298;12724;12725;12726;12727,12287;12665;12666,&50685;50686;50687,12297;12750;12751;12752;12753,%12975,12797;12799,29598;29599,12299;12761;12762;12763;12764,59088;59089,12313;12804,12308;12810;12811,%12312;12803,12809,12311;12958,'16538;16539;16540;16541;16542,%29593;29594,d50720,29787;29790;29792,&29140;29143;29144,46945;46949,%57499,20243,47294;47295;47296,&b46951;46952;46953,58872;58874,&46968]=],
ROGUE=[=[14162;14163;14164,14144;14148,14138;14139;14140;14141;14142,%14156;14160;14161,51632;51633,!13733;13865;13866,14983,14168;14169,f14128;14132;14135;14136;14137,&16513;16514;16515,14113;14114;14115;14116;14117,%31208;31209,14177,14174;14175;14176,31244;31245,!c14186;14190;14193;14194;14195,14158;14159,%51625;51626,58426,31380;31382;31383,%51634;51635;51636,!31234;31235;31236,%31226;31227;58410,e1329,51627;51628;51629,&51664;51665;51667;51668;51669,&51662|13741;13793;13792,13732;13863,13715;13848;13849;13851;13852,%14165;14166,13713;13853;13854,!13705;13832;13843;13844;13845,13742;13872,c14251,f13706;13804;13805;13806;13807,%13754;13867,13743;13875,13712;13788;13789,18427;18428;18429;61330;61331,13709;13800;13801;13802;13803,13877,13960;13961;13962;13963;13964,&b30919;30920,31124;31126,%31122;31123;61329,13750,31130;31131,%5952;51679,!35541;35550;35551;35552;35553,%51672;51674,e32601,51682;58413,&51685;51686;51687;51688;51689,&51690|14179;58422;58423;58424;58425,13958;13970;13971,14057;14072,%30892;30893,14076;14094,13975;14062;14063,%13981;14066,14278,14171;14172;14173,%13983;14070;14071,13976;13979;13980,14079;14080,%30894;30895,14185,14082;14083,g16511,31221;31222;31223,!30902;30903;30904;30905;30906,%31211;31212;31213,f14183,31228;31229;31230,&b31216;31217;31218;31219;31220,51692;51696,%51698;51700;51701,36554,58414;58415,&51708;51709;51710;51711;51712,&51713]=],
MAGE=[=[11210;12592,11222;12839;12840,11237;12463;12464;16769;16770,%28574;54658;54659,29441;29444,11213;12574;12575;12576;12577,%11247;12606,11242;12467;12469,44397;44398;44399,54646,11252;12605,11255;12598,18462;18463;18464,29447;55339;55340,31569;31570,12043,!11232;12500;12501;12502;12503,31574;31575;54354,c15058;15059;15060,d31571;31572,%31579;31582;31583,c12042,44394;44395;44396,&b44378;44379,31584;31585;31586;31587;31588,&31589,44404;54486;54488;54489;54490,&44400;44402;44403,35578;35581,&44425|11078;11080,18459;18460;54734,11069;12338;12339;12340;12341,%11119;11120;12846;12847;12848,54747;54749,11108;12349;12350,%11100;12353,11103;12357;12358,11366,11083;12351,11095;12872;12873,11094;13043,!29074;29075;29076,31638;31639;31640,11115;11367;11368,g11113,%31641;31642,!11124;12378;12398;12399;12400,%34293;34295;34296,e11129,31679;31680,%64353;64357,!31656;31657;31658,%A44442;44443,e31661,44445;44446;44448,&44449;44469;44470;44471;44472,&44457|11071;12496;12497,11070;12473;16763;16765;16766,31670;31672;55094,%11207;12672;15047,11189;28332,29438;29439;29440,11175;12569;12571,11151;12952;12953,12472,11185;12487;12488,%16757;16758,11160;12518;12519,11170;12982;12983,&11958,11190;12489;12490,31667;31668;31669,c55091;55092,!11180;28592;28593,%A44745;54787,f11426,31674;31675;31676;31677;31678,&31682;31683,44543;44545,%44546;44548;44549,31687,a44557;44560;44561,&44566;44567;44568;44570;44571,&44572]=],
PRIEST=[=[!14522;14788;14789;14790;14791,47586;47587;47588;52802;52803,%14523;14784;14785,14747;14770;14771,14749;14767,14531;14774,14521;14776;14777,14751,14748;14768;14769,%33167;33171;33172,14520;14780;14781,!14750;14772,33201;33202,18551;18552;18553;18554;18555,f63574,%33186;33190,!34908;34909;34910,%45234;45243;45244,e10060,63504;63505;63506,%57470;57472,47535;47536;47537,47507;47508,%47509;47511;47515,33206,47516;47517,&52795;52797;52798;52799;52800,&47540|14913;15012,14908;15020;17191,14889;15008;15009;15010;15011,&27900;27901;27902;27903;27904,18530;18531;18533;18534;18535,%19236,27811;27815;27816,!14892;15362;15363,27789;27790,14912;15013;15014,f14909;15017,%14911;15018,20711,14901;15028;15029;15030;15031,%33150;33154,!14898;15349;15354;15355;15356,%34753;34859;34860,e724,33142;33145;33146,%64127;64129,33158;33159;33160;33161;33162,63730;63733;63737,%63534;63542;63543,34861,47558;47559;47560,&47562;47564;47565;47566;47567,&47788|15270;15335;15336,a15337;15338,15259;15307;15308;15309;15310,%15318;15272;15320,15275;15317,15260;15327;15328,%15392;15448,15273;15312;15313;15314;15316,15407,&15274;15311,17322;17323,15257;15331;15332,f15487,15286,a27839;27840,33213;33214;33215,14910;33371,!63625;63626;63627,&e15473,33221;33222;33223;33224;33225,%b47569;47570,!33191;33192;33193,%64044,e34914,47580;47581;47582,'47573;47577;47578;51166;51167,&c47585]=],
WARLOCK=[=[18827;18829,18174;18175;18176,17810;17811;17812;17813;17814,%18179;18180,18213;18372,18182;18183,17804;17805,53754;53759,17783;17784;17785,18288,%18218;18219,18094;18095,!32381;32382;32383,32385;32387;32392;32393;32394,63108,f18223,%54037;54038,c18271;18272;18273;18274;18275,%47195;47196;47197,30060;30061;30062;30063;30064,18220,%30054;30057,!32477;32483;32484,%47198;47199;47200,e30108,a58435,&47201;47202;47203;47204;47205,&48181|18692;18693,18694;18695;18696,18697;18698;18699,47230;47231,18703;18704,18705;18706;18707,18731;18743;18744,%18754;18755;18756,19028,18708,30143;30144;30145,!c18769;18770;18771;18772;18773,c18709;18710,%b30326,!18767;18768,&d23785;23822;23823;23824;23825,47245;47246;47247,%30319;30320;30321,c47193,35691;35692;35693,&30242;30245;30246;30247;30248,63156;63158,%b54347;54348;54349,30146,63117;63121;63123,&47236;47237;47238;47239;47240,&59672|!17793;17796;17801;17802;17803,17788;17789;17790;17791;17792,%18119;18120,63349;63350;63351,17778;17779;17780,%18126;18127,17877,17959;59738;59739;59740;59741,%18135;18136,17917;17918,!17927;17929;17930,c34935;34938;34939,17815;17833;17834,f18130,%30299;30301;30302,!17954;17955;17956;17957;17958,&d17962,30293;30295;30296,18096;18073;63245,!30288;30289;30290;30291;30292,c54117;54118,%e47258;47259;47260,30283,47220;47221;47223,&47266;47267;47268;47269;47270,&50796]=],
HUNTER=[=[!19552;19553;19554;19555;19556,19583;19584;19585;19586;19587,%35029;35030,19549;19550;19551,19609;19610;19612,24443;19575,19559;19560,53265,19616;19617;19618;19619;19620,&19572;19573,19598;19599;19600;19601;19602,%19578;20895,19577,!19590;19592,34453;34454,!e19621;19622;19623;19624;19625,%34455;34459;34460,e19574,34462;34464;34465,%c53252;53253,!34466;34467;34468;34469;34470,%53262;53263;53264,e34692,c53256;53259;53260,&56314;56315;56316;56317;56318,&53270|19407;19412,53620;53621;53622,19426;19427;19429;19430;19431,%34482;34483;34484,19421;19422;19423,19485;19487;19488;19489;19490,%34950;34954,19454;19455;19456,c19434,34948;34949,!19464;19465;19466,19416;19417;19418;19419;19420,%35100;35102,23989,19461;19462;24691,%34475;34476,"19507;19508;19509,53234;53237;53238,e19506,e35104;35110;35111,&34485;34486;34487;34488;34489,53228;53232,%53215;53216;53217,c34490,53221;53222;53224,&53241;53243;53244;53245;53246,&53209|52783;52785;52786;52787;52788,19498;19499;19500,19159;19160,%19290;19294;24283,19184;19387;19388,19376;63457;63458,34494;34496,19255;19256;19257;19258;19259,19503,19295;19297;19298,19286;19287,!56333;56336;56337,!56342;56343;56344,f56339;56340;56341,19370;19371;19373,f19306,%19168;19180;19181;24296;24297,!34491;34492;34493,%b34500;34502;34503,e19386,34497;34498;34499,%34506;34507;34508;34838;34839,c53295;53296;53297,%53298;53299,3674,!53302;53303;53304,"f53290;53291;53292,&c53301]=],
DRUID=[=[!16814;16815;16816;16817;16818,57810;57811;57812;57813;57814,%16845;16846;16847,35363;35364,!16821;16822,16836;16839;16840,c16880;61345;61346,d57865,16819;16820,!16909;16910;16911;16912;16913,16850;16923;16924,%33589;33590;33591,5570,a57849;57850;57851,%33597;33599;33956,16896;16897;16899,33592;33596,&24858,a48384;48395;48396,33600;33601;33602,c48389;48392;48393,!33603;33604;33605;33606;33607,%48516;48521;48525,f50516,33831,48488;48514,!48506;48510;48511,&48505|!16934;16935;16936;16937;16938,16858;16859;16860;16861;16862,%16947;16948;16949,16998;16999,16929;16930;16931,%17002;24866,61336,16942;16943;16944,%16966;16968,16972;16974;16975,c37116;37117,d48409;48410,16940;16941,!49377,33872;33873,57878;57880;57881,g17003;17004;17005;17006;24894,33853;33855;33856,&17007,a34297;34300,33851;33852;33957,c57873;57876;57877,!33859;33866;33867,48483;48484;48485,48492;48494;48495,g33917,a48532;48489;48491,&48432;48433;48434;51268;51269,a63503,&50334|17050;17051,17063;17065;17066,17056;17058;17059;17060;17061,%17069;17070;17071;17072;17073,17118;17119;17120,16833;16834;16835,%17106;17107;17108,16864,c48411;48412,&24968;24969;24970;24971;24972,17111;17112;17113,%e17116,17104;24943;24944;24945;24946,!17123;17124,33879;33880,!e17074;17075;17076;17077;17078,%34151;34152;34153,e18562,33881;33882;33883,&33886;33887;33888;33889;33890,48496;48499;48500,%48539;48544;48545,c65139,a48535;48536;48537,%63410;63411,!51179;51180;51181;51182;51183,&d48438]=],
SHAMAN=[=[!16039;16109;16110;16111;16112,16035;16105;16106;16107;16108,%16038;16160;16161,28996;28997;28998,30160;29179;29180,%16040;16113;16114;16115;16116,16164,16089;60184;60185;60187;60188,%16086;16544,"29062;29064;29065,28999;29000,e16041,!30664;30665;30666,30672;30673;30674,!g16578;16579;16580;16581;16582,&d16166,51483;51485;51486,%63370;63372,c51466;51470,30675;30678;30679,%51474;51478;51479,30706,51480;51481;51482,&62097;62098;62099;62100;62101,&51490|16259;16295;52456,16043;16130,17485;17486;17487;17488;17489,%16258;16293,16255;16302;16303;16304;16305,16262;16287,16261;16290;51881,16266;29079;29080,!43338,16254;16271;16272,!f16256;16281;16282;16283;16284,16252;16306;16307;16308;16309,%29192;29193,16268,51883;51884;51885,%30802;30808;30809,!29082;29084;29086,63373;63374,A30816;30818;30819,f30798,17364,%51525;51526;51527,c60103,c51521;51522,%30812;30813;30814,30823,51523;51524,&51528;51529;51530;51531;51532,&51533|!16182;16226;16227;16228;16229,16173;16222;16223;16224;16225,%16184;16209,29187;29189;29191,16179;16214;16215;16216;16217,%16180;16196;16198,16181;16230;16232,55198,16176;16235;16240,!16187;16205;16206,16194;16218;16219;16220;16221,%29206;29205;29202,!16188,30864;30865;30866,"16178;16210;16211;16212;16213,%30881;30883;30884;30885;30886,g16190,c51886,%51554;51555,30872;30873,30867;30868;30869,%51556;51557;51558,974,a51560;51561,&51562;51563;51564;51565;51566,&61295]=],
PALADIN=[=[!20205;20206;20207;20209;20208,20224;20225;20330;20331;20332,%20237;20238;20239,20257;20258;20259;20260;20261,9453;25836,%31821,20210;20212;20213;20214;20215,20234;20235,%20254;20255;20256,!20244;20245,53660;53661,31822;31823,f20216,20359;20360;20361,%31825;31826,!5923;5924;5925;5926;25829,%31833;31835;31836,e20473,31828;31829;31830,%53551;53552;53553,!31837;31838;31839;31840;31841,%31842,!53671;53673;54151;54154;54155,&f53569;53576,53556;53557,&53563|!63646;63647;63648;63649;63650,20262;20263;20264;20265;20266,%31844;31845;53519,20174;20175,20096;20097;20098;20099;20100,%64205,20468;20469;20470,20143;20144;20145;20146;20147,%c53527;53530,20487;20488,20138;20139;20140,&20911,20177;20179;20181;20180;20182,%31848;31849,!20196;20197;20198,%31785;33776,e20925,31850;31851;31852,%20127;20130;20135,!31858;31859;31860,%53590;53591;53592,e31935,53583;53585,&b53709;53710;53711,53695;53696,&53595|!20060;20061;20062;20063;20064,20101;20102;20103;20104;20105,%25956;25957,20335;20336;20337,20042;20045,%9452;26016,20117;20118;20119;20120;20121,20375,26022;26023,9799;25988,!32043;35396;35397,31866;31867;31868,20111;20112;20113,!31869,&h20049;20056;20057,31871;31872,%53486;53488,20066,31876;31877;31878,&b31879;31880;31881,53375;53376,%53379;53484;53648,35395,53501;53502;53503,&53380;53381;53382,&53385]=],
}

local talentClassIndex = 1
local talentBuiltClassKey = nil
local activeTalentTreeIndex = 1
local ModifyTalentPoint
local AddTreeBackground
local TALENT_MAX_POINTS = 71
local TALENT_DATA_CACHE = {}
local TALENT_PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function SplitBySep(value, sep)
    local result = {}
    if not value then return result end
    local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
    local last = 1
    while last <= string.len(value) do
        local a, b, part = string.find(value, pattern, last)
        if not a then break end
        if b < last then break end
        table.insert(result, part or "")
        last = b + 1
        if b >= string.len(value) then break end
    end
    return result
end

local function ParseTalentRanks(raw)
    local ranks = {}
    local first = raw or ""
    local pos, row, column, req = 1, nil, nil, nil
    local c = string.byte(first, pos)
    if c == 42 then
        row, column = nil, -1
        pos = pos + 1
        c = string.byte(first, pos)
    elseif c and c > 32 and c <= 40 then
        column = c - 32
        if column > 4 then
            row = true
            column = column - 4
        end
        pos = pos + 1
        c = string.byte(first, pos)
    end
    if c and c >= 65 and c <= 90 then
        req = c - 64
        pos = pos + 1
    elseif c and c >= 97 and c <= 122 then
        req = 96 - c
        pos = pos + 1
    end
    local pieces = SplitBySep(first:sub(pos) .. ";", ";")
    for i = 1, table.getn(pieces) do
        local n = tonumber(pieces[i])
        if n then table.insert(ranks, n) end
    end
    return { ranks = ranks, row = row, column = column, req = req, inactive = not ranks[1] }
end

local function NextTalentPos(row, column)
    column = column + 1
    if column >= 5 then
        return row + 1, 1
    end
    return row, column
end

local function ParseTalentTree(rawTree)
    local entries = {}
    local chunks = SplitBySep(rawTree .. ",", ",")
    for i = 1, table.getn(chunks) do
        if chunks[i] and chunks[i] ~= "" then
            table.insert(entries, ParseTalentRanks(chunks[i]))
        end
    end
    local row, column = 1, 1
    for index = 1, table.getn(entries) do
        local talent = entries[index]
        local drow, dcolumn = talent.row, talent.column
        if dcolumn == -1 then
            if entries[index - 1] then
                talent.row = entries[index - 1].row
                talent.column = entries[index - 1].column
            else
                talent.row, talent.column = row, column
            end
            talent.inactive = true
        elseif dcolumn then
            if drow then
                row = row + 1
                column = dcolumn
            else
                column = column + dcolumn
            end
            talent.row, talent.column = row, column
        else
            talent.row, talent.column = row, column
        end
        if dcolumn ~= -1 or drow then
            row, column = NextTalentPos(row, column)
        end
        if talent.req then
            talent.req = talent.req + index
            if talent.req <= 0 or talent.req > table.getn(entries) then talent.req = nil end
        end
    end
    return entries
end

local function GetClassTalentData(classKey)
    if TALENT_DATA_CACHE[classKey] then return TALENT_DATA_CACHE[classKey] end
    local raw = TALENT_SPELLDATA[classKey]
    local data = { {}, {}, {} }
    if raw then
        local trees = SplitBySep(raw .. "|", "|")
        for i = 1, 3 do data[i] = ParseTalentTree(trees[i] or "") end
    end
    TALENT_DATA_CACHE[classKey] = data
    return data
end

local function GetTalentClass()
    return TALENT_CLASSES[talentClassIndex] or TALENT_CLASSES[1]
end

local function EnsureTalentPlan(classKey)
    InitDB()
    if type(WowNoteDB.talentPlans[classKey]) ~= "table" then
        WowNoteDB.talentPlans[classKey] = { trees = { {}, {}, {} } }
    end
    local plan = WowNoteDB.talentPlans[classKey]
    if type(plan.trees) ~= "table" then plan.trees = { {}, {}, {} } end
    for i = 1, 3 do
        if type(plan.trees[i]) ~= "table" then plan.trees[i] = {} end
    end
    return plan
end

local function GetTalentRank(classKey, treeIndex, index)
    local plan = EnsureTalentPlan(classKey)
    return tonumber(plan.trees[treeIndex][index]) or 0
end

local function SetTalentRank(classKey, treeIndex, index, rank)
    local plan = EnsureTalentPlan(classKey)
    if rank <= 0 then plan.trees[treeIndex][index] = nil else plan.trees[treeIndex][index] = rank end
end

local function CountTalentPoints(classKey, treeIndex)
    local plan = EnsureTalentPlan(classKey)
    local total = 0
    if treeIndex then
        for _, rank in pairs(plan.trees[treeIndex]) do total = total + (tonumber(rank) or 0) end
    else
        for i = 1, 3 do total = total + CountTalentPoints(classKey, i) end
    end
    return total
end

local function GetTalentSummary(classInfo)
    classInfo = classInfo or GetTalentClass()
    return tostring(CountTalentPoints(classInfo.key, 1)) .. "/" .. tostring(CountTalentPoints(classInfo.key, 2)) .. "/" .. tostring(CountTalentPoints(classInfo.key, 3))
end

local function GetTalentCode(classInfo)
    classInfo = classInfo or GetTalentClass()
    local data = GetClassTalentData(classInfo.key)
    local parts = {}
    for treeIndex = 1, 3 do
        local ranks = {}
        for index = 1, table.getn(data[treeIndex]) do
            table.insert(ranks, tostring(GetTalentRank(classInfo.key, treeIndex, index)))
        end
        table.insert(parts, table.concat(ranks, ""))
    end
    return classInfo.key .. ";" .. table.concat(parts, "|")
end

local function GetTalentName(talent)
    if not talent or not talent.ranks or not talent.ranks[1] then return "Unknown Talent" end
    local name = GetSpellInfo(talent.ranks[1])
    return name or ("Spell " .. tostring(talent.ranks[1]))
end

local function GetTalentIcon(talent)
    if not talent or not talent.ranks or not talent.ranks[1] then return TALENT_PLACEHOLDER_ICON end
    local _, _, icon = GetSpellInfo(talent.ranks[1])
    return icon or TALENT_PLACEHOLDER_ICON
end

local function CountTalentPointsBeforeRow(classKey, treeIndex, rowLimit, overrideIndex, overrideRank)
    local data = GetClassTalentData(classKey)
    local treeData = data[treeIndex] or {}
    local total = 0
    for talentIndex, treeTalent in ipairs(treeData) do
        if treeTalent and not treeTalent.inactive and treeTalent.row and treeTalent.row < rowLimit then
            if overrideIndex and talentIndex == overrideIndex then
                total = total + (overrideRank or 0)
            else
                total = total + GetTalentRank(classKey, treeIndex, talentIndex)
            end
        end
    end
    return total
end

local function CanRaiseTalent(classKey, treeIndex, index, talent)
    local total = CountTalentPoints(classKey)
    if total >= TALENT_MAX_POINTS then return false, "Maximum 71 talent points" end
    local pointsInTree = CountTalentPoints(classKey, treeIndex)
    local requiredTierPoints = ((talent.row or 1) - 1) * 5
    if pointsInTree < requiredTierPoints then return false, "Requires " .. tostring(requiredTierPoints) .. " points in this tree" end
    if talent.req then
        local prereq = GetClassTalentData(classKey)[treeIndex][talent.req]
        local prereqRank = GetTalentRank(classKey, treeIndex, talent.req)
        local prereqMax = prereq and prereq.ranks and table.getn(prereq.ranks) or 0
        if prereqRank < prereqMax then return false, "Requires " .. GetTalentName(prereq) end
    end
    return true
end

local function CanLowerTalent(classKey, treeIndex, index, newRank)
    local data = GetClassTalentData(classKey)
    local treeData = data[treeIndex] or {}
    local target = treeData[index]
    if not target then return true end

    for talentIndex, talent in ipairs(treeData) do
        if talent and not talent.inactive then
            local rank = GetTalentRank(classKey, treeIndex, talentIndex)
            if talentIndex == index then rank = newRank end
            if rank and rank > 0 then
                local requiredTierPoints = ((talent.row or 1) - 1) * 5
                if requiredTierPoints > 0 then
                    local pointsBeforeRow = CountTalentPointsBeforeRow(classKey, treeIndex, talent.row or 1, index, newRank)
                    if pointsBeforeRow < requiredTierPoints then
                        return false, "Cannot remove: higher tier talents still require these points"
                    end
                end
                if talent.req then
                    local prereqRank = GetTalentRank(classKey, treeIndex, talent.req)
                    if talent.req == index then prereqRank = newRank end
                    local prereq = treeData[talent.req]
                    local prereqMax = prereq and prereq.ranks and table.getn(prereq.ranks) or 0
                    if prereqRank < prereqMax then
                        return false, "Cannot remove: " .. GetTalentName(talent) .. " requires " .. GetTalentName(prereq)
                    end
                end
            end
        end
    end

    return true
end

local RefreshTalentPlanner

local function GetTalentButtonPosition(talent)
    -- Blizzard TalentFrame uses a compact 4-column grid with fixed icon anchors.
    -- These offsets match the WotLK TalentFrame proportions much more closely than the
    -- previous three-tree custom layout.
    local x = 32 + ((talent.column - 1) * 64)
    local y = -48 - ((talent.row - 1) * 45)
    return x, y
end

local function UpdateTalentPrereqLines(tree, classKey, treeIndex)
    if not tree then return end
    if tree.reqLines then
        for _, line in pairs(tree.reqLines) do
            if line then line:Hide() end
        end
    else
        tree.reqLines = {}
    end

    local data = GetClassTalentData(classKey)
    local treeData = data[treeIndex] or {}
    local lineIndex = 1
    for talentIndex, talent in ipairs(treeData) do
        if talent and talent.req and talent.row and talent.column then
            local prereq = treeData[talent.req]
            if prereq and prereq.row and prereq.column then
                local srcX, srcY = GetTalentButtonPosition(prereq)
                local dstX, dstY = GetTalentButtonPosition(talent)
                local srcRank = GetTalentRank(classKey, treeIndex, talent.req)
                local srcMax = prereq.ranks and table.getn(prereq.ranks) or 0
                local active = srcRank >= srcMax
                local colorR, colorG, colorB = 0.35, 0.35, 0.35
                if active then colorR, colorG, colorB = 1, 0.82, 0.1 end

                local function getLine()
                    local line = tree.reqLines[lineIndex]
                    if not line then
                        line = tree:CreateTexture(nil, "BORDER")
                        line:SetTexture("Interface\\Buttons\\WHITE8X8")
                        tree.reqLines[lineIndex] = line
                    end
                    lineIndex = lineIndex + 1
                    line:Show()
                    line:SetVertexColor(colorR, colorG, colorB, 0.85)
                    return line
                end

                local sx = srcX + 16
                local sy = srcY - 32
                local dx = dstX + 16
                local dy = dstY

                if prereq.column == talent.column then
                    local line = getLine()
                    line:SetPoint("TOPLEFT", tree, "TOPLEFT", sx - 2, sy)
                    line:SetWidth(4)
                    line:SetHeight(math.abs(sy - dy))
                else
                    local midY = sy - math.floor(math.abs(sy - dy) / 2)
                    local line1 = getLine()
                    line1:SetPoint("TOPLEFT", tree, "TOPLEFT", sx - 2, sy)
                    line1:SetWidth(4)
                    line1:SetHeight(math.abs(sy - midY))
                    local line2 = getLine()
                    line2:SetPoint("TOPLEFT", tree, "TOPLEFT", math.min(sx, dx), midY)
                    line2:SetWidth(math.abs(dx - sx) + 4)
                    line2:SetHeight(4)
                    local line3 = getLine()
                    line3:SetPoint("TOPLEFT", tree, "TOPLEFT", dx - 2, midY)
                    line3:SetWidth(4)
                    line3:SetHeight(math.abs(midY - dy))
                end
            end
        end
    end
end

local function CreateTalentButton(tree, treeIndex, index, talent)
    local button = nil
    -- Use the Blizzard talent button template when it is present. Some private 3.3.5a
    -- clients expose it, some don't; the fallback below keeps the AddOn safe.
    local ok, frameOrError = pcall(CreateFrame, "Button", nil, tree, "TalentFrameTalentButtonTemplate")
    if ok and frameOrError then
        button = frameOrError
    else
        button = CreateFrame("Button", nil, tree)
    end

    button:SetWidth(32)
    button:SetHeight(32)
    local x, y = GetTalentButtonPosition(talent)
    button:SetPoint("TOPLEFT", tree, "TOPLEFT", x, y)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    end
    button.icon:SetTexture(TALENT_PLACEHOLDER_ICON)

    if not button.slot then
        button.slot = button:CreateTexture(nil, "BACKGROUND")
        button.slot:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.slot:SetWidth(44)
        button.slot:SetHeight(44)
        button.slot:SetTexture("Interface\\Buttons\\UI-Quickslot")
    end

    if not button.border then
        button.border = button:CreateTexture(nil, "OVERLAY")
        button.border:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.border:SetWidth(46)
        button.border:SetHeight(46)
        button.border:SetTexture("Interface\\TalentFrame\\TalentFrameTalentIcon")
    end

    if not button.rankBg then
        button.rankBg = button:CreateTexture(nil, "OVERLAY")
        button.rankBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 7, -7)
        button.rankBg:SetWidth(26)
        button.rankBg:SetHeight(14)
        button.rankBg:SetTexture("Interface\\TalentFrame\\TalentFrame-RankBorder")
    end

    if not button.rankText then
        button.rankText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.rankText:SetPoint("CENTER", button.rankBg, "CENTER", 0, 1)
    end

    local clickTreeIndex, clickIndex = treeIndex, index
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then ModifyTalentPoint(clickTreeIndex, clickIndex, -1) else ModifyTalentPoint(clickTreeIndex, clickIndex, 1) end
    end)
    button:SetScript("OnEnter", function(self)
        local ci = GetTalentClass(); local d = GetClassTalentData(ci.key); local t = d[clickTreeIndex][clickIndex]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local rank = GetTalentRank(ci.key, clickTreeIndex, clickIndex)
        local spell = t and t.ranks and t.ranks[rank > 0 and rank or 1]
        if spell then GameTooltip:SetHyperlink("spell:" .. tostring(spell)) else GameTooltip:SetText(GetTalentName(t)) end
        GameTooltip:AddLine("Rank " .. tostring(rank) .. "/" .. tostring(t and t.ranks and table.getn(t.ranks) or 0), 1, 1, 1)
        local canRaise, reason = CanRaiseTalent(ci.key, clickTreeIndex, clickIndex, t)
        if rank == 0 and not canRaise and reason then GameTooltip:AddLine(reason, 1, 0.2, 0.2) end
        GameTooltip:AddLine("Left-click: +1 point", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: -1 point", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function ShowTalentTree(treeIndex)
    activeTalentTreeIndex = treeIndex or 1
    for i = 1, 3 do
        local tree = talentTreeFrames[i]
        if tree then
            if i == activeTalentTreeIndex then tree:Show() else tree:Hide() end
        end
        local tab = talentTreeTabs and talentTreeTabs[i]
        if tab then
            if i == activeTalentTreeIndex then
                tab:LockHighlight()
            else
                tab:UnlockHighlight()
            end
        end
    end
    RefreshTalentPlanner()
end

local function RebuildTalentButtons()
    if not talentFrame then return end
    local classInfo = GetTalentClass()
    local data = GetClassTalentData(classInfo.key)

    for treeIndex = 1, 3 do
        local tree = talentTreeFrames[treeIndex]
        if tree then
            if AddTreeBackground then AddTreeBackground(tree, classInfo.backgrounds[treeIndex]) end
            if tree.title then tree.title:SetText(classInfo.trees[treeIndex]) end
            if talentButtons[treeIndex] then
                for _, button in pairs(talentButtons[treeIndex]) do
                    if button then button:Hide(); button:SetParent(nil) end
                end
            end
            talentButtons[treeIndex] = {}
            local treeData = data[treeIndex] or {}
            for index, talent in ipairs(treeData) do
                if talent and not talent.inactive and talent.row and talent.column then
                    talentButtons[treeIndex][index] = CreateTalentButton(tree, treeIndex, index, talent)
                end
            end
        end
    end
    talentBuiltClassKey = classInfo.key
    ShowTalentTree(activeTalentTreeIndex)
end

RefreshTalentPlanner = function()
    if not talentFrame then return end
    local classInfo = GetTalentClass()
    local data = GetClassTalentData(classInfo.key)
    EnsureTalentPlan(classInfo.key)
    if talentBuiltClassKey ~= classInfo.key then RebuildTalentButtons() end
    if talentClassText then talentClassText:SetText(classInfo.name) end
    if talentPointsText then talentPointsText:SetText("Points spent: " .. tostring(CountTalentPoints(classInfo.key)) .. " / " .. tostring(TALENT_MAX_POINTS)) end
    if talentClassDropDown and UIDropDownMenu_SetText then UIDropDownMenu_SetText(talentClassDropDown, classInfo.name) end

    for treeIndex = 1, 3 do
        local tree = talentTreeFrames[treeIndex]
        if tree and tree.title then tree.title:SetText(classInfo.trees[treeIndex]) end
        local tab = talentTreeTabs and talentTreeTabs[treeIndex]
        if tab and tab.text then tab.text:SetText(classInfo.trees[treeIndex] .. " (" .. tostring(CountTalentPoints(classInfo.key, treeIndex)) .. ")") end
        local buttons = talentButtons[treeIndex] or {}
        for index, button in pairs(buttons) do
            local talent = data[treeIndex][index]
            local rank = GetTalentRank(classInfo.key, treeIndex, index)
            local maxRank = talent and talent.ranks and table.getn(talent.ranks) or 0
            if button.rankText then button.rankText:SetText(tostring(rank) .. "/" .. tostring(maxRank)) end
            if button.icon then button.icon:SetTexture(GetTalentIcon(talent)) end
            local canRaise = CanRaiseTalent(classInfo.key, treeIndex, index, talent)
            if rank > 0 then
                button.icon:SetVertexColor(1, 1, 1)
                if button.border then button.border:SetVertexColor(0, 1, 0) end
            elseif canRaise then
                button.icon:SetVertexColor(1, 1, 1)
                if button.border then button.border:SetVertexColor(1, 0.82, 0) end
            else
                button.icon:SetVertexColor(0.32, 0.32, 0.32)
                if button.border then button.border:SetVertexColor(0.45, 0.45, 0.45) end
            end
        end
        UpdateTalentPrereqLines(tree, classInfo.key, treeIndex)
    end
end


-- Compatibility alias for intermediate builds that referenced the old rebuild function name.
-- WoW 3.3.5a resolves dropdown callbacks at click time, so keeping this global alias
-- prevents stale UIDropDownMenu callbacks from crashing after an addon update.
_G.RebuildTalentButtons = RefreshTalentPlanner

ModifyTalentPoint = function(treeIndex, index, delta)
    local classInfo = GetTalentClass()
    local data = GetClassTalentData(classInfo.key)
    local talent = data[treeIndex] and data[treeIndex][index]
    if not talent or talent.inactive then return end
    local current = GetTalentRank(classInfo.key, treeIndex, index)
    local maxRank = talent.ranks and table.getn(talent.ranks) or 0
    local nextRank = current + delta
    if nextRank < 0 then nextRank = 0 end
    if nextRank > maxRank then nextRank = maxRank end
    if nextRank > current then
        local ok, reason = CanRaiseTalent(classInfo.key, treeIndex, index, talent)
        if not ok then SetStatus(reason or "Talent locked"); return end
    elseif nextRank < current then
        local ok, reason = CanLowerTalent(classInfo.key, treeIndex, index, nextRank)
        if not ok then SetStatus(reason or "Talent is required by later talents"); return end
    end
    SetTalentRank(classInfo.key, treeIndex, index, nextRank)
    RefreshTalentPlanner()
end

local function ResetTalentPlan()
    local classInfo = GetTalentClass()
    WowNoteDB.talentPlans[classInfo.key] = { trees = { {}, {}, {} } }
    RefreshTalentPlanner()
    SetStatus("Talent build reset: " .. classInfo.name)
end

local function BuildTalentPlanText(classInfo)
    local data = GetClassTalentData(classInfo.key)
    local lines = {}
    table.insert(lines, "")
    table.insert(lines, "[WowNote Talent Build]")
    table.insert(lines, "TalentVersion: " .. WOWNOTE_TALENT_FORMAT_VERSION)
    table.insert(lines, "NoteVersion: " .. WOWNOTE_NOTE_FORMAT_VERSION)
    table.insert(lines, "Class: " .. classInfo.name)
    table.insert(lines, "Build: " .. classInfo.trees[1] .. " " .. CountTalentPoints(classInfo.key, 1) .. " / " .. classInfo.trees[2] .. " " .. CountTalentPoints(classInfo.key, 2) .. " / " .. classInfo.trees[3] .. " " .. CountTalentPoints(classInfo.key, 3))
    table.insert(lines, "Summary: " .. GetTalentSummary(classInfo))
    table.insert(lines, "Code: " .. GetTalentCode(classInfo))
    for treeIndex = 1, 3 do
        table.insert(lines, "")
        table.insert(lines, classInfo.trees[treeIndex] .. ":")
        for index, talent in ipairs(data[treeIndex]) do
            local rank = GetTalentRank(classInfo.key, treeIndex, index)
            if rank > 0 then
                table.insert(lines, "- " .. GetTalentName(talent) .. " " .. tostring(rank) .. "/" .. tostring(table.getn(talent.ranks)))
            end
        end
    end
    table.insert(lines, "[/WowNote Talent Build]")
    return table.concat(lines, "\n") .. "\n"
end


local function ClearTalentPlanForClass(classKey)
    local plan = EnsureTalentPlan(classKey)
    plan.trees = { {}, {}, {} }
end

local function FindTalentClassIndexByKey(classKey)
    classKey = tostring(classKey or "")
    for i = 1, table.getn(TALENT_CLASSES) do
        if TALENT_CLASSES[i].key == classKey then return i end
    end
    return nil
end

local function ApplyTalentCode(classKey, codePart)
    local idx = FindTalentClassIndexByKey(classKey)
    if not idx then
        SetStatus("Talent import failed: unknown class " .. tostring(classKey or ""))
        return false
    end

    local data = GetClassTalentData(classKey)
    local chunks = {}
    for chunk in string.gmatch(tostring(codePart or ""), "([^|]+)") do
        table.insert(chunks, chunk)
    end
    if table.getn(chunks) ~= 3 then
        SetStatus("Talent import failed: invalid code format")
        return false
    end

    talentClassIndex = idx
    ClearTalentPlanForClass(classKey)

    for treeIndex = 1, 3 do
        local code = chunks[treeIndex] or ""
        local treeData = data[treeIndex] or {}
        for talentIndex = 1, table.getn(treeData) do
            local digit = tonumber(string.sub(code, talentIndex, talentIndex)) or 0
            local maxRank = treeData[talentIndex] and treeData[talentIndex].ranks and table.getn(treeData[talentIndex].ranks) or 0
            if digit > maxRank then digit = maxRank end
            if digit > 0 then SetTalentRank(classKey, treeIndex, talentIndex, digit) end
        end
    end

    if RefreshTalentPlanner then RefreshTalentPlanner() end
    SetStatus("Talent build loaded from note: " .. TALENT_CLASSES[idx].name .. " " .. GetTalentSummary(TALENT_CLASSES[idx]))
    return true
end

local function FindTalentBlockInText(text)
    text = tostring(text or "")
    local block = string.match(text, "%[WowNote Talent Build%](.-)%[/WowNote Talent Build%]")
    return block or text
end

local function LoadTalentPlanFromText(text)
    local block = FindTalentBlockInText(text)
    local talentVersion = string.match(block, "\nTalentVersion:%s*([^\n\r]+)") or string.match(block, "^TalentVersion:%s*([^\n\r]+)")
    if not talentVersion or Trim(talentVersion or "") == "" then
        talentVersion = WOWNOTE_TALENT_FORMAT_VERSION
    end
    if Trim(talentVersion) ~= WOWNOTE_TALENT_FORMAT_VERSION then
        SetStatus("Talent import: version " .. Trim(talentVersion) .. " detected; trying compatibility mode")
    end
    local codeLine = string.match(block, "\nCode:%s*([^\n\r]+)") or string.match(block, "^Code:%s*([^\n\r]+)")
    if not codeLine then
        SetStatus("No WowNote talent code found in selected note")
        return false
    end
    local classKey, codePart = string.match(Trim(codeLine), "^([A-Z]+);(.+)$")
    if not classKey or not codePart then
        SetStatus("Talent import failed: broken Code line")
        return false
    end
    return ApplyTalentCode(classKey, codePart)
end

local function LoadTalentPlanFromCurrentNote()
    InitDB()
    local text = nil
    if currentGuid and WowNoteDB.notes[currentGuid] then
        text = WowNoteDB.notes[currentGuid].content or ""
    elseif contentEdit then
        text = contentEdit:GetText() or ""
    end
    return LoadTalentPlanFromText(text)
end

local function ReplaceTalentBlockInText(text, block)
    text = tostring(text or "")
    block = tostring(block or "")
    local pattern = "%[WowNote Talent Build%].-%[/WowNote Talent Build%]"
    local replaced, count = string.gsub(text, pattern, block, 1)
    if count and count > 0 then
        return replaced, true
    end
    if text ~= "" and string.sub(text, -1) ~= "\n" then text = text .. "\n" end
    return text .. "\n" .. block, false
end

local function UpdateTalentPlanInCurrentNote()
    InitDB()
    if not currentGuid or not WowNoteDB.notes[currentGuid] then
        SetStatus("Select an existing note first")
        return
    end
    local classInfo = GetTalentClass()
    local block = BuildTalentPlanText(classInfo)
    local currentText = WowNoteDB.notes[currentGuid].content or ""
    local updatedText, replaced = ReplaceTalentBlockInText(currentText, block)
    WowNote_Open()
    SetEditMode(true)
    contentEdit:SetText(updatedText)
    SaveNote(false)
    if replaced then
        SetStatus("Talent build updated in selected note: " .. classInfo.name .. " " .. GetTalentSummary(classInfo))
    else
        SetStatus("No existing talent block found; talent build inserted into selected note")
    end
end

local function InsertTalentPlanIntoCurrentNote(forceNew)
    local classInfo = GetTalentClass()
    local summary = GetTalentSummary(classInfo)
    local text = "\n" .. BuildTalentPlanText(classInfo)
    WowNote_Open()
    if forceNew then
        ClearEditor()
        SetEditMode(true)
        titleEdit:SetText("Talent: " .. classInfo.name .. " " .. summary)
        contentEdit:SetText(text)
        SaveNote(true)
    else
        if not currentGuid or not WowNoteDB.notes[currentGuid] then
            SetStatus("Select an existing note first, or use As new note")
            return
        end
        SetEditMode(true)
        if contentEdit then contentEdit:Insert(text) end
        SaveNote(false)
    end
    SetStatus("Talent build saved to note: " .. classInfo.name .. " " .. summary)
end

local function InitTalentClassDropDown()
    if not talentClassDropDown or not UIDropDownMenu_Initialize then return end
    UIDropDownMenu_Initialize(talentClassDropDown, function()
        for i = 1, table.getn(TALENT_CLASSES) do
            local idx = i
            local classInfo = TALENT_CLASSES[idx]
            local info = UIDropDownMenu_CreateInfo()
            info.text = classInfo.name
            info.value = classInfo.key
            info.notCheckable = 1
            info.func = function() talentClassIndex = idx; activeTalentTreeIndex = 1; RebuildTalentButtons(); RefreshTalentPlanner() end
            UIDropDownMenu_AddButton(info)
        end
    end)
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(talentClassDropDown, 150) end
end

AddTreeBackground = function(tree, background)
    local prefix = "Interface\\TalentFrame\\" .. background
    if not tree.backgroundTextures then
        tree.backgroundTextures = {}
        tree.backgroundTextures.tl = tree:CreateTexture(nil, "BACKGROUND")
        tree.backgroundTextures.tl:SetPoint("TOPLEFT", tree, "TOPLEFT", 6, -30)
        tree.backgroundTextures.tl:SetWidth(128); tree.backgroundTextures.tl:SetHeight(256)
        tree.backgroundTextures.tr = tree:CreateTexture(nil, "BACKGROUND")
        tree.backgroundTextures.tr:SetPoint("TOPRIGHT", tree, "TOPRIGHT", -6, -30)
        tree.backgroundTextures.tr:SetWidth(128); tree.backgroundTextures.tr:SetHeight(256)
        tree.backgroundTextures.bl = tree:CreateTexture(nil, "BACKGROUND")
        tree.backgroundTextures.bl:SetPoint("BOTTOMLEFT", tree, "BOTTOMLEFT", 6, 10)
        tree.backgroundTextures.bl:SetWidth(128); tree.backgroundTextures.bl:SetHeight(128)
        tree.backgroundTextures.br = tree:CreateTexture(nil, "BACKGROUND")
        tree.backgroundTextures.br:SetPoint("BOTTOMRIGHT", tree, "BOTTOMRIGHT", -6, 10)
        tree.backgroundTextures.br:SetWidth(128); tree.backgroundTextures.br:SetHeight(128)
    end
    tree.backgroundTextures.tl:SetTexture(prefix .. "-TopLeft")
    tree.backgroundTextures.tr:SetTexture(prefix .. "-TopRight")
    tree.backgroundTextures.bl:SetTexture(prefix .. "-BottomLeft")
    tree.backgroundTextures.br:SetTexture(prefix .. "-BottomRight")
end

local function CreateTalentTreeTab(parent, treeIndex)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetWidth(145)
    tab:SetHeight(32)
    tab:SetNormalTexture("Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab")
    tab:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
    tab:SetPushedTexture("Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab")
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.text:SetPoint("CENTER", tab, "CENTER", 0, 2)
    tab:SetScript("OnClick", function() ShowTalentTree(treeIndex) end)
    return tab
end

CreateTalentUI = function()
    if talentFrame then return end
    talentFrame = CreateFrame("Frame", "WowNoteTalentFrame", UIParent)
    talentFrame:SetWidth(565)
    talentFrame:SetHeight(760)
    talentFrame:SetPoint("CENTER", UIParent, "CENTER", 35, 0)
    talentFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if talentFrame.SetToplevel then talentFrame:SetToplevel(true) end
    talentFrame:SetFrameLevel(100)
    talentFrame:EnableMouse(true)
    talentFrame:SetMovable(true)
    talentFrame:RegisterForDrag("LeftButton")
    EnableRaiseOnInteraction(talentFrame)
    talentFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    talentFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    talentFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    talentFrame:Hide()

    local title = talentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", talentFrame, "TOPLEFT", 18, -16)
    title:SetText("WowNote Talent Planner")
    local close = CreateFrame("Button", nil, talentFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", talentFrame, "TOPRIGHT", -4, -4)

    local classLabel = talentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classLabel:SetPoint("TOPLEFT", talentFrame, "TOPLEFT", 24, -52)
    classLabel:SetText("Class")
    talentClassDropDown = CreateFrame("Frame", "WowNoteTalentClassDropDown", talentFrame, "UIDropDownMenuTemplate")
    talentClassDropDown:SetPoint("TOPLEFT", talentFrame, "TOPLEFT", 70, -43)
    InitTalentClassDropDown()
    talentClassText = talentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    talentClassText:SetPoint("LEFT", talentClassDropDown, "RIGHT", -10, 2)
    talentClassText:SetText("")
    talentPointsText = talentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    talentPointsText:SetPoint("TOPRIGHT", talentFrame, "TOPRIGHT", -28, -54)
    talentPointsText:SetText("")

    local treeContainer = CreateFrame("Frame", nil, talentFrame)
    treeContainer:SetPoint("TOP", talentFrame, "TOP", 0, -78)
    treeContainer:SetWidth(340)
    treeContainer:SetHeight(575)

    talentTreeTabs = {}
    for treeIndex = 1, 3 do
        local tree = CreateFrame("Frame", nil, treeContainer)
        tree:SetWidth(340)
        tree:SetHeight(575)
        tree:SetPoint("TOPLEFT", treeContainer, "TOPLEFT", 0, 0)
        tree:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        tree:SetBackdropColor(0, 0, 0, 0.85)
        talentTreeFrames[treeIndex] = tree
        talentButtons[treeIndex] = {}

        local classInfo = GetTalentClass()
        AddTreeBackground(tree, classInfo.backgrounds[treeIndex])
        tree.title = tree:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        tree.title:SetPoint("TOP", tree, "TOP", 0, -12)
        tree.title:SetText(classInfo.trees[treeIndex])

        local tab = CreateTalentTreeTab(talentFrame, treeIndex)
        tab:SetPoint("TOPLEFT", talentFrame, "TOPLEFT", 46 + ((treeIndex - 1) * 148), -660)
        talentTreeTabs[treeIndex] = tab
    end

    local resetButton = MakeButton(talentFrame, "Reset", 70, 24)
    resetButton:SetPoint("BOTTOMLEFT", talentFrame, "BOTTOMLEFT", 24, 54)
    resetButton:SetScript("OnClick", ResetTalentPlan)
    local loadButton = MakeButton(talentFrame, "Load selected", 110, 24)
    loadButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)
    loadButton:SetScript("OnClick", LoadTalentPlanFromCurrentNote)
    local updateButton = MakeButton(talentFrame, "Update", 80, 24)
    updateButton:SetPoint("LEFT", loadButton, "RIGHT", 8, 0)
    updateButton:SetScript("OnClick", UpdateTalentPlanInCurrentNote)
    local saveButton = MakeButton(talentFrame, "Insert selected note", 155, 24)
    saveButton:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", 0, -8)
    saveButton:SetScript("OnClick", function() InsertTalentPlanIntoCurrentNote(false) end)
    local saveNewButton = MakeButton(talentFrame, "As new note", 105, 24)
    saveNewButton:SetPoint("LEFT", saveButton, "RIGHT", 8, 0)
    saveNewButton:SetScript("OnClick", function() InsertTalentPlanIntoCurrentNote(true) end)
    local hint = talentFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", talentFrame, "BOTTOMRIGHT", -28, 20)
    hint:SetText("Left-click: add point  |  Right-click: remove point")

    talentFrame:SetScript("OnShow", function()
        RebuildTalentButtons()
        ShowTalentTree(activeTalentTreeIndex)
        RefreshTalentPlanner()
    end)
end


WowNote_OpenTalents = function()
    CreateTalentUI()
    talentFrame:Show()
    RaiseFrame(talentFrame)
    RefreshTalentPlanner()
end
_G.WowNote_OpenTalents = WowNote_OpenTalents

end
WowNote_LoadTalentModule()


function WowNote_PrintHelp()
    Print("WowNote commands:")
    Print("/wn or /wownote - Toggle the main WowNote window.")
    Print("/wn help - Show this command overview.")
    Print("/wn profile - Open the WowNote-only performance profiler (disabled by default).")
    Print("/wn profile on/off - Enable or fully disable WowNote profiling load.")
    Print("/wn profile report - Print a compact WowNote-only performance summary.")
    Print("/wn profile timeline - Open selectable total/module/handler history with WowNote attribution.")
    Print("/wn profile reset - Reset the current profiler session.")
    Print("/wn profile mark <text> - Add a marker to the profiler timeline.")
    Print("/wn profile detailed on/off - Toggle per-handler timing.")
    Print("/wn new - Open WowNote and create a new empty note.")
    Print("/wn share - Open the send/receive dialog with receiver-code protected note sharing.")
    Print("/wn talents - Open the talent planner.")
    Print("/wn talents load - Load the selected note's talent build into the planner.")
    Print("/wn raid - Open the raid planner.")
    Print("/wn ids - Open the raid ID / lockout tracker.")
    Print("/wn loot - Open loot tools.")
    Print("/wn loot roll - Open auto loot roller settings.")
    Print("/wn loot sell - Open auto sell settings.")
    Print("/wn loot repair - Open auto repair settings.")
    Print("/wn draw - Open the screen drawing overlay.")
    Print("/wn tactics - Open the tactical board.")
    Print("/wn bank - Open the account bank snapshot viewer.")
    Print("/wn tracker - Open the item tracker configuration.")
    Print("/wn tracker lock - Lock the movable tracker HUD.")
    Print("/wn tracker unlock - Unlock the tracker HUD for dragging.")
    Print("/wn tracker show - Show the tracker HUD.")
    Print("/wn tracker hide - Hide the tracker HUD.")
    Print("/wn restock - Open the merchant restock assistant.")
    Print("/wn pallybuffs - Open PallyBuffs assignments.")
    Print("/wn cursor - Open cursor effect settings.")
    Print("/wn bite - Open the Blood-Queen Bite Helper.")
    Print("/wnbite test on/off - Toggle the local Bite Helper test mode.")
    Print("/wn pally sync - Request a PallyBuffs assignment sync.")
    Print("/wn pally test on - Enable the PallyBuffs sample/test mode.")
    Print("/wn pally test off - Disable the PallyBuffs sample/test mode.")
    Print("/wn joinchan - Join the WowNote addon channel.")
    Print("/wn chaninfo - Print addon channel status.")
    Print("/wn chantest - Send a visible addon channel test message.")
    Print("/wn ping <character> - Send a direct addon ping.")
    Print("/wn pingchat <character> - Send a visible chat based ping.")
    Print("/wn pingchan <character> - Send a channel based addon ping.")
    Print("/wn pingroutes <character> - Test all configured communication routes.")
    Print("/wn send <character> <code> - Send the current note through the code-protected request/accept transfer.")
    Print("/wn sendchat <character> - Legacy debug path; normal protected sending uses /wn share.")
    Print("/wn sendchan <character> - Legacy debug path; normal protected sending uses /wn share.")
    Print("/wn debug on - Enable communication debug output.")
    Print("/wn debug off - Disable communication debug output.")
end

SLASH_WOWNOTE1 = "/wownote"
SLASH_WOWNOTE2 = "/wn"
SlashCmdList["WOWNOTE"] = function(msg)
    local rawMsg = Trim(msg or "")
    local lowerMsg = string.lower(rawMsg)
    if lowerMsg == "help" or lowerMsg == "hilfe" or lowerMsg == "commands" or lowerMsg == "?" then
        WowNote_PrintHelp()
    elseif lowerMsg == "new" or lowerMsg == "neu" then
        WowNote_Open()
        ClearEditor()
    elseif lowerMsg == "share" or lowerMsg == "send" or lowerMsg == "transfer" or lowerMsg == "datatransfer" or lowerMsg == "teilen" then
        if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("dataTransfer") then Print("Data transfer module is disabled."); return end
        WowNote_OpenShare()
    elseif lowerMsg == "settings" or lowerMsg == "optionen" or lowerMsg == "options" then
        if WowNote_OpenSettings then WowNote_OpenSettings() else Print("Settings module is not loaded.") end
    elseif lowerMsg == "profile" or lowerMsg == "profiler" then
        if WowNote_ProfilerHandleSlash then WowNote_ProfilerHandleSlash("") else Print("Profiler module is not loaded.") end
    elseif string.sub(lowerMsg, 1, 8) == "profile " or string.sub(lowerMsg, 1, 9) == "profiler " then
        local arguments = string.match(rawMsg, "^%S+%s+(.+)$") or ""
        if WowNote_ProfilerHandleSlash then WowNote_ProfilerHandleSlash(arguments) else Print("Profiler module is not loaded.") end
    elseif lowerMsg == "characters" or lowerMsg == "characternotes" or lowerMsg == "playernotes" or lowerMsg == "spielernotizen" then
        if WowNote_OpenCharacterNotes then WowNote_OpenCharacterNotes() else Print("Character Notes module is not loaded.") end
    elseif lowerMsg == "talents" or lowerMsg == "talente" or lowerMsg == "talent" then
        WowNote_OpenTalents()
    elseif lowerMsg == "raid" or lowerMsg == "raidplanner" or lowerMsg == "lfm" then
        WowNote_OpenRaidPlanner()
    elseif lowerMsg == "bite" or lowerMsg == "bitehelper" or lowerMsg == "byte" then
        if WowNote_OpenBiteHelper then WowNote_OpenBiteHelper(true) else Print("Bite Helper module is not loaded.") end
    elseif lowerMsg == "loot" or lowerMsg == "looter" or lowerMsg == "loottools" then
        if WowNote_OpenLootTools then
            WowNote_OpenLootTools("roll")
        elseif WowNote_OpenAutoLootRoller then
            WowNote_OpenAutoLootRoller()
        else
            Print("Loot Tools module is not loaded.")
        end
    elseif lowerMsg == "loot sell" or lowerMsg == "autosell" or lowerMsg == "sell" then
        if WowNote_OpenLootTools then
            WowNote_OpenLootTools("sell")
        else
            Print("Loot Tools module is not loaded.")
        end
    elseif lowerMsg == "loot repair" or lowerMsg == "autorepair" or lowerMsg == "repair" then
        if WowNote_OpenLootTools then
            WowNote_OpenLootTools("repair")
        else
            Print("Loot Tools module is not loaded.")
        end
    elseif lowerMsg == "loot roll" or lowerMsg == "lootroller" or lowerMsg == "autoroll" then
        if WowNote_OpenLootTools then
            WowNote_OpenLootTools("roll")
        elseif WowNote_OpenAutoLootRoller then
            WowNote_OpenAutoLootRoller()
        else
            Print("Loot Tools module is not loaded.")
        end
    elseif lowerMsg == "ids" or lowerMsg == "raidids" or lowerMsg == "raid ids" or lowerMsg == "lockouts" then
        if WowNote_OpenRaidIdTracker then
            WowNote_OpenRaidIdTracker()
        else
            Print("Raid ID Tracker module is not loaded.")
        end
    elseif lowerMsg == "draw" or lowerMsg == "screen" or lowerMsg == "screendraw" or lowerMsg == "paint" then
        if WowNote_OpenScreenDraw then
            WowNote_OpenScreenDraw()
        else
            Print("Screen Draw module is not loaded.")
        end
    elseif lowerMsg == "tactics" or lowerMsg == "tactic" or lowerMsg == "mapdraw" or lowerMsg == "board" then
        if WowNote_OpenTacticalMap then
            WowNote_OpenTacticalMap()
        else
            Print("Tactical Map module is not loaded.")
        end
    elseif lowerMsg == "talents load" or lowerMsg == "talent load" or lowerMsg == "load talents" then
        WowNote_OpenTalents()
        LoadTalentPlanFromCurrentNote()
    elseif lowerMsg == "items" or lowerMsg == "item" or lowerMsg == "gegenstand" or lowerMsg == "gegenstände" then
        WowNote_Open()
        SetEditMode(true)
        FocusContentEditor()
        Print("Item window was removed. Shift-click or drag items directly into the note content field.")
    elseif lowerMsg == "bank" or lowerMsg == "banks" or lowerMsg == "bankviewer" then
        if WowNote_OpenBankViewer then
            WowNote_OpenBankViewer()
        else
            Print("Bank Viewer module is not loaded.")
        end
    elseif lowerMsg == "tracker" or lowerMsg == "itemtracker" or lowerMsg == "track" then
        if WowNote_OpenItemTracker then
            WowNote_OpenItemTracker()
        else
            Print("Item Tracker module is not loaded.")
        end
    elseif lowerMsg == "tracker lock" or lowerMsg == "track lock" then
        if WowNote_ItemTracker_SetHudLocked then WowNote_ItemTracker_SetHudLocked(true) end
    elseif lowerMsg == "tracker unlock" or lowerMsg == "track unlock" then
        if WowNote_ItemTracker_SetHudLocked then WowNote_ItemTracker_SetHudLocked(false) end
    elseif lowerMsg == "tracker show" or lowerMsg == "track show" then
        if WowNote_ItemTracker_SetHudShown then WowNote_ItemTracker_SetHudShown(true) end
    elseif lowerMsg == "tracker hide" or lowerMsg == "track hide" then
        if WowNote_ItemTracker_SetHudShown then WowNote_ItemTracker_SetHudShown(false) end
    elseif lowerMsg == "restock" or lowerMsg == "nachkaufen" then
        if WowNote_OpenRestock then
            WowNote_OpenRestock()
        else
            Print("Restock module is not loaded.")
        end
    elseif lowerMsg == "cursor" or lowerMsg == "cursoreffects" or lowerMsg == "mousefx" then
        if WowNote_OpenCursorEffects then
            WowNote_OpenCursorEffects()
        else
            Print("Cursor Effects module is not loaded.")
        end
    elseif lowerMsg == "pally" or lowerMsg == "pallypower" or lowerMsg == "pallybuffs" or lowerMsg == "buffs" or lowerMsg == "blessings" then
        if WowNote_OpenPallyBuffs then
            WowNote_OpenPallyBuffs()
        else
            Print("PallyBuffs module is not loaded.")
        end
    elseif lowerMsg == "pally sync" or lowerMsg == "pallypower sync" then
        if WowNote_PallyPower_RequestSync then
            WowNote_PallyPower_RequestSync()
        else
            Print("PallyBuffs module is not loaded.")
        end
    elseif lowerMsg == "pally test" or lowerMsg == "pally test on" or lowerMsg == "pallypower test" or lowerMsg == "pallypower test on" then
        if WowNote_PallyPower_SetTestMode then
            WowNote_PallyPower_SetTestMode(true)
            Print("PallyBuffs test mode enabled.")
        else
            Print("PallyBuffs module is not loaded.")
        end
    elseif lowerMsg == "pally test off" or lowerMsg == "pallypower test off" then
        if WowNote_PallyPower_SetTestMode then
            WowNote_PallyPower_SetTestMode(false)
            Print("PallyBuffs test mode disabled.")
        else
            Print("PallyBuffs module is not loaded.")
        end
    elseif lowerMsg == "debug" or lowerMsg == "debug on" then
        commDebug = true
        Print("Communication debug enabled.")
    elseif lowerMsg == "debug off" then
        commDebug = false
        Print("Communication debug disabled.")
    elseif string.sub(lowerMsg, 1, 11) == "pingroutes " then
        local target = string.match(rawMsg, "^%S+%s+(.+)$")
        SendCommPingRoutes(target)
    elseif lowerMsg == "joinchan" or lowerMsg == "channel" then
        JoinWowNoteChannel(false)
        Print("WowNote channel join requested: " .. COMM_CHANNEL_NAME .. ".")
    elseif lowerMsg == "chaninfo" then
        PrintChannelInfo()
    elseif lowerMsg == "chantest" then
        SendVisibleChannelTest()
    elseif string.sub(lowerMsg, 1, 9) == "pingchan " then
        local target = string.match(rawMsg, "^%S+%s+(.+)$")
        SendCommPingChannel(target)
    elseif string.sub(lowerMsg, 1, 9) == "pingchat " then
        local target = string.match(rawMsg, "^%S+%s+(.+)$")
        SendCommPingChat(target)
    elseif string.sub(lowerMsg, 1, 5) == "ping " then
        local target = string.match(rawMsg, "^%S+%s+(.+)$")
        SendCommPing(target)
    elseif string.sub(lowerMsg, 1, 9) == "sendchan " then
        local target = string.match(rawMsg, "^%S+%s+(.+)$")
        SendCurrentNoteToPlayerViaChannel(target)
    elseif string.sub(lowerMsg, 1, 9) == "sendchat " then
        local target = string.match(rawMsg, "^%S+%s+(.+)$")
        SendCurrentNoteToPlayerViaChat(target)
    elseif string.sub(lowerMsg, 1, 5) == "send " or string.sub(lowerMsg, 1, 7) == "teilen " then
        local target, authCode = string.match(rawMsg, "^%S+%s+(%S+)%s+(%S+)$")
        if not target then
            target = string.match(rawMsg, "^%S+%s+(.+)$")
        end
        SendCurrentNoteToPlayer(target, authCode)
    else
        WowNote_Toggle()
    end
end

function TitanPanelWowNoteButton_GetButtonText(id)
    InitDB()
    return "WowNote", TitanUtils_GetHighlightText(tostring(CountNotes()))
end

function TitanPanelWowNoteButton_GetTooltipText()
    InitDB()
    return "Notes: " .. TitanUtils_GetHighlightText(tostring(CountNotes())) .. "\n" ..
        "Left-click: " .. TitanUtils_GetHighlightText("open WowNote") .. "\n" ..
        "Right-click note: " .. TitanUtils_GetHighlightText("Save / Delete / Save as new") .. "\n" ..
        "Slash: " .. TitanUtils_GetHighlightText("/wn") .. "\n" ..
        "Item links: " .. TitanUtils_GetHighlightText("Shift-click or drag & drop")
end

function TitanPanelRightClickMenu_PrepareWowNoteMenu()
    local hideText = TITAN_PANEL_MENU_HIDE or "Hide"
    TitanPanelRightClickMenu_AddTitle("WowNote")
    TitanPanelRightClickMenu_AddCommand("Open", TITAN_ID, "WowNote_Open")
    TitanPanelRightClickMenu_AddCommand("New note", TITAN_ID, "WowNote_NewFromTitan")
    TitanPanelRightClickMenu_AddCommand("Talent Planner", TITAN_ID, "WowNote_OpenTalents")
    TitanPanelRightClickMenu_AddCommand("Raid Planner", TITAN_ID, "WowNote_OpenRaidPlanner")
    TitanPanelRightClickMenu_AddCommand("Bite Helper", TITAN_ID, "WowNote_OpenBiteHelper")
    TitanPanelRightClickMenu_AddCommand("Loot Tools", TITAN_ID, "WowNote_OpenAutoLootRoller")
    TitanPanelRightClickMenu_AddCommand("Raid IDs", TITAN_ID, "WowNote_OpenRaidIdTracker")
    TitanPanelRightClickMenu_AddCommand("Bank Viewer", TITAN_ID, "WowNote_OpenBankViewer")
    TitanPanelRightClickMenu_AddCommand("Item Tracker", TITAN_ID, "WowNote_OpenItemTracker")
    TitanPanelRightClickMenu_AddCommand("Restock", TITAN_ID, "WowNote_OpenRestock")
    TitanPanelRightClickMenu_AddCommand("PallyBuffs", TITAN_ID, "WowNote_OpenPallyBuffs")
    TitanPanelRightClickMenu_AddCommand("Profiler", TITAN_ID, "WowNote_OpenProfiler")
    TitanPanelRightClickMenu_AddCommand("Help", TITAN_ID, "WowNote_PrintHelp")
    TitanPanelRightClickMenu_AddCommand("Screen Draw", TITAN_ID, "WowNote_OpenScreenDraw")
    TitanPanelRightClickMenu_AddSpacer()
    TitanPanelRightClickMenu_AddToggleIcon(TITAN_ID)
    TitanPanelRightClickMenu_AddToggleLabelText(TITAN_ID)
    TitanPanelRightClickMenu_AddSpacer()
    TitanPanelRightClickMenu_AddCommand(hideText, TITAN_ID, TITAN_PANEL_MENU_FUNC_HIDE)
end

function WowNote_NewFromTitan()
    WowNote_Open()
    ClearEditor()
end

function TitanPanelWowNoteButton_OnLoad(self)
    self.registry = {
        id = TITAN_ID,
        menuText = "WowNote",
        version = GetAddOnMetadata and GetAddOnMetadata("WoWNote", "Version") or "1.14.73",
        category = "Information",
        buttonTextFunction = "TitanPanelWowNoteButton_GetButtonText",
        tooltipTitle = "WowNote",
        tooltipTextFunction = "TitanPanelWowNoteButton_GetTooltipText",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        iconWidth = 16,
        savedVariables = {
            ShowIcon = 1,
            ShowLabelText = 1,
            DisplayOnRightSide = false,
        },
        controlVariables = {
            ShowIcon = true,
            ShowLabelText = true,
            DisplayOnRightSide = true,
        },
    }
end

local function CreateTitanPlugin()
    if not TitanPanelButton_OnLoad then return end
    if _G["TitanPanelWowNoteButton"] then return end

    local ok, button = pcall(CreateFrame, "Button", "TitanPanelWowNoteButton", UIParent, "TitanPanelComboTemplate")
    if ok and button then
        TitanPanelWowNoteButton_OnLoad(button)
        TitanPanelButton_OnLoad(button)
        button:SetScript("OnClick", function(self, buttonName)
            if buttonName == "LeftButton" then
                WowNote_Toggle()
            elseif TitanPanelButton_OnClick then
                TitanPanelButton_OnClick(self, buttonName)
            end
        end)
    end
end

-- Minimap button moved to WowNote_Minimap.lua


local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
WowNoteProfiler_SetScript(eventFrame, "OnEvent", "Core.Events", function(self, event, addon, ...)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        InitDB()
        HookItemLinks()
        if RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(COMM_PREFIX)
        end
        CreateTitanPlugin()
    elseif event == "PLAYER_LOGIN" then
        HookItemLinks()
        if RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(COMM_PREFIX)
        end
        CreateUI()
        CreateTitanPlugin()
        if WowNote_CreateMinimapButton then WowNote_CreateMinimapButton() end
        JoinWowNoteChannel(true)
        if ChatFrame_AddMessageEventFilter then
            ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", WowNoteChatFilter)
            ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", WowNoteChatFilter)
            ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", WowNoteChatFilter)
        end
    elseif event == "CHAT_MSG_ADDON" then
        HandleAddonMessage(addon, select(1, ...), select(2, ...), select(3, ...))
    elseif event == "CHAT_MSG_WHISPER" then
        HandleChatWhisper(addon, select(1, ...))
    elseif event == "CHAT_MSG_CHANNEL" then
        HandleChatChannel(addon, select(1, ...), select(8, ...))
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
        if addon == "YOU_JOINED" then
            local channelName = select(8, ...)
            if channelName == COMM_CHANNEL_NAME then
                commChannelNumber = GetChannelName and GetChannelName(COMM_CHANNEL_NAME) or commChannelNumber
                if commDebug then
                    Print("DEBUG joined channel " .. COMM_CHANNEL_NAME .. " #" .. tostring(commChannelNumber or "?") .. ".")
                end
            end
        end
    end
end)
