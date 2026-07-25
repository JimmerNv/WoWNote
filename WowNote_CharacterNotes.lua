-- WowNote_CharacterNotes.lua
-- Account-wide player notes, unit-popup integration and optional tooltip display.

local WN = WowNote_Internal or {}
local listFrame, editorFrame, noteFrame, menuFrame, punkWarningFrame
local rows = {}
local knownRosterKeys = {}
local lastPunkAlerts = {}
local rosterInitialized = false
local portraitMarkers = {}
local currentKey
local accountMigrationDone = false

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function Trim(text)
    if WN.Trim then return WN.Trim(text) end
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function NormalizeRealm(realm)
    realm = Trim(realm or "")
    if realm == "" and GetRealmName then realm = GetRealmName() or "" end
    realm = string.gsub(realm, "%s+", "")
    return realm
end

local function BuildKey(name, realm)
    name = Trim(name or "")
    if name == "" then return nil end
    realm = NormalizeRealm(realm)
    if realm ~= "" then return name .. "-" .. realm end
    return name
end
local PUNK_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local PUNK_LABEL = "|cffff2020PUNK|r"
local function PunkIcon(size)
    size = tonumber(size) or 14
    return "|T" .. PUNK_ICON_TEXTURE .. ":" .. size .. ":" .. size .. ":0:0|t"
end

local function NormalizeKeyName(name, realm)
    local key = BuildKey(name, realm)
    return key and string.lower(key) or nil
end


local function SplitNameRealm(name)
    name = Trim(name or "")
    local n, r = string.match(name, "^([^-]+)%-(.+)$")
    if n and n ~= "" then return n, NormalizeRealm(r) end
    return name, NormalizeRealm(nil)
end

local function ImportLegacyCharacterNotes(source)
    if type(source) ~= "table" then return 0 end
    local target = WowNoteDB.characterNotes
    local migrated = 0

    for key, value in pairs(source) do
        local name, realm, noteText, updated

        if type(value) == "table" then
            name = value.name
            realm = value.realm
            noteText = value.note or value.text or value.value
            updated = value.updated or value.updatedAt or value.time
        elseif type(value) == "string" then
            noteText = value
        end

        noteText = Trim(noteText or "")
        if noteText ~= "" then
            if not name or Trim(name) == "" then
                name, realm = SplitNameRealm(tostring(key or ""))
            end

            local accountKey = BuildKey(name, realm)
            if accountKey and (not target[accountKey] or Trim(target[accountKey].note or "") == "") then
                target[accountKey] = {
                    name = Trim(name),
                    realm = NormalizeRealm(realm),
                    note = noteText,
                    updated = tonumber(updated) or (time and time() or 0),
                }
                migrated = migrated + 1
            end
        end
    end

    return migrated
end

local function EnsureDB()
    if WN.InitDB then WN.InitDB() end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.characterNotes) ~= "table" then WowNoteDB.characterNotes = {} end

    if not accountMigrationDone then
        accountMigrationDone = true
        local migrated = 0

        if type(WowNoteCharDB) == "table" then
            migrated = migrated + ImportLegacyCharacterNotes(WowNoteCharDB.characterNotes)
            migrated = migrated + ImportLegacyCharacterNotes(WowNoteCharDB.playerNotes)
            if migrated > 0 then
                WowNoteCharDB.characterNotesMigratedToAccount = true
            end
        end

        migrated = migrated + ImportLegacyCharacterNotes(WowNoteCharacterNotesDB)

        if migrated > 0 then
            Print("Migrated " .. migrated .. " character note(s) to account-wide storage.")
        end
    end

    return WowNoteDB.characterNotes
end

local function GetNote(name, realm)
    local db = EnsureDB()
    local key = BuildKey(name, realm)
    return key and db[key], key
end

local function SaveNote(name, realm, text, punkOverride)
    local db = EnsureDB()
    local key = BuildKey(name, realm)
    if not key then return end
    text = Trim(text or "")
    local old = db[key]
    local punk = old and old.punk == true
    if punkOverride ~= nil then punk = punkOverride and true or false end
    if text == "" and not punk then
        db[key] = nil
        return
    end
    db[key] = db[key] or {}
    db[key].name = Trim(name)
    db[key].realm = NormalizeRealm(realm)
    db[key].note = text
    db[key].punk = punk and true or nil
    db[key].updated = time and time() or 0
end

local function SetPunk(name, realm, enabled)
    local db = EnsureDB()
    local key = BuildKey(name, realm)
    if not key then return false end
    local note = db[key]
    local existingText = note and Trim(note.note or "") or ""
    enabled = enabled and true or false
    if not enabled and existingText == "" then
        db[key] = nil
    else
        db[key] = db[key] or {}
        db[key].name = Trim(name)
        db[key].realm = NormalizeRealm(realm)
        db[key].note = existingText
        db[key].punk = enabled and true or nil
        db[key].updated = time and time() or 0
    end
    if WowNote_RefreshCharacterNotes then WowNote_RefreshCharacterNotes() end
    if WowNote_UpdatePunkPortraitMarkers then WowNote_UpdatePunkPortraitMarkers() end
    return true
end

function WowNote_IsCharacterPunk(name, realm)
    local note = GetNote(name, realm)
    return note and note.punk == true or false
end

function WowNote_SetCharacterPunk(name, realm, enabled)
    name, realm = SplitNameRealm(name or "")
    if not name or name == "" then Print("No player selected."); return end
    if SetPunk(name, realm, enabled) then
        Print((enabled and "Marked " or "Unmarked ") .. name .. (enabled and " as Punk." or " as Punk."))
    end
end

function WowNote_ToggleCharacterPunk(name, realm)
    name, realm = SplitNameRealm(name or (UnitName and UnitName("target") or ""))
    if not name or name == "" then Print("No player selected."); return end
    local isPunk = WowNote_IsCharacterPunk(name, realm)
    WowNote_SetCharacterPunk(name, realm, not isPunk)
end

local function DeleteNote(name, realm)
    local db = EnsureDB()
    local key = BuildKey(name, realm)
    if not key then return end
    db[key] = nil
    if currentKey == key then currentKey = nil end
    if noteFrame then noteFrame:Hide() end
    if WowNote_RefreshCharacterNotes then WowNote_RefreshCharacterNotes() end
end

local pendingDeleteName, pendingDeleteRealm

local function ConfirmDeleteNote(name, realm)
    name, realm = SplitNameRealm(name or "")
    if not name or name == "" then return end

    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs["WOWNOTE_DELETE_CHARACTER_NOTE"] = StaticPopupDialogs["WOWNOTE_DELETE_CHARACTER_NOTE"] or {
            text = "Delete WowNote character note for %s?",
            button1 = YES or "Yes",
            button2 = NO or "No",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            OnAccept = function()
                DeleteNote(pendingDeleteName, pendingDeleteRealm)
            end,
        }
        pendingDeleteName, pendingDeleteRealm = name, realm
        StaticPopup_Show("WOWNOTE_DELETE_CHARACTER_NOTE", name)
    else
        DeleteNote(name, realm)
    end
end

local function MakeButton(parent, text, width, height)
    if WN.MakeButton then return WN.MakeButton(parent, text, width, height) end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width or 80); b:SetHeight(height or 22); b:SetText(text or "")
    return b
end

local function CreateEditor()
    if editorFrame then return end
    editorFrame = CreateFrame("Frame", "WowNoteCharacterNoteEditor", UIParent)
    editorFrame:SetWidth(360); editorFrame:SetHeight(240); editorFrame:SetPoint("CENTER")
    editorFrame:SetFrameStrata("FULLSCREEN_DIALOG"); if editorFrame.SetToplevel then editorFrame:SetToplevel(true) end; editorFrame:SetFrameLevel(100); editorFrame:SetMovable(true); editorFrame:EnableMouse(true)
    editorFrame:RegisterForDrag("LeftButton")
    editorFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    editorFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    editorFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    editorFrame:Hide()

    editorFrame.title = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editorFrame.title:SetPoint("TOPLEFT", editorFrame, "TOPLEFT", 18, -16)
    editorFrame.title:SetText("Character Note")
    local close = CreateFrame("Button", nil, editorFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -4, -4)

    local bg = CreateFrame("Frame", nil, editorFrame)
    bg:SetPoint("TOPLEFT", editorFrame, "TOPLEFT", 22, -52); bg:SetWidth(316); bg:SetHeight(96)
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0,0,0,0.85)

    editorFrame.edit = CreateFrame("EditBox", nil, bg)
    editorFrame.edit:SetPoint("TOPLEFT", bg, "TOPLEFT", 6, -6); editorFrame.edit:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6, 6)
    editorFrame.edit:SetAutoFocus(false); editorFrame.edit:SetMultiLine(true); editorFrame.edit:SetFontObject(ChatFontNormal)
    editorFrame.edit:SetTextInsets(2,2,2,2)
    editorFrame.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    editorFrame.punkCheck = CreateFrame("CheckButton", nil, editorFrame, "UICheckButtonTemplate")
    editorFrame.punkCheck:SetPoint("BOTTOMLEFT", editorFrame, "BOTTOMLEFT", 22, 56)
    editorFrame.punkCheck:SetWidth(24); editorFrame.punkCheck:SetHeight(24)
    editorFrame.punkCheck.text = editorFrame.punkCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    editorFrame.punkCheck.text:SetPoint("LEFT", editorFrame.punkCheck, "RIGHT", 4, 0)
    editorFrame.punkCheck.text:SetText(PunkIcon(14) .. " Mark as Punk")

    local save = MakeButton(editorFrame, "Save", 80, 24)
    save:SetPoint("BOTTOMLEFT", editorFrame, "BOTTOMLEFT", 24, 24)
    save:SetScript("OnClick", function()
        local name, realm = editorFrame.playerName, editorFrame.realm
        SaveNote(name, realm, editorFrame.edit:GetText() or "", editorFrame.punkCheck and editorFrame.punkCheck:GetChecked())
        editorFrame:Hide()
        if WowNote_RefreshCharacterNotes then WowNote_RefreshCharacterNotes() end
    end)
    local delete = MakeButton(editorFrame, "Delete", 80, 24)
    delete:SetPoint("LEFT", save, "RIGHT", 8, 0)
    delete:SetScript("OnClick", function()
        local name, realm = editorFrame.playerName, editorFrame.realm
        editorFrame:Hide()
        ConfirmDeleteNote(name, realm)
    end)
    local cancel = MakeButton(editorFrame, "Cancel", 80, 24)
    cancel:SetPoint("LEFT", delete, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function() editorFrame:Hide() end)
end

function WowNote_OpenCharacterNoteEditor(name, realm)
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("characterNotes") then return end
    name, realm = SplitNameRealm(name or (UnitName("target") or ""))
    if not name or name == "" then Print("No player selected."); return end
    CreateEditor()
    local note = GetNote(name, realm)
    editorFrame.playerName = name; editorFrame.realm = realm
    editorFrame.title:SetText("Character Note: " .. name)
    editorFrame.edit:SetText(note and note.note or "")
    if editorFrame.punkCheck then editorFrame.punkCheck:SetChecked(note and note.punk == true or false) end
    editorFrame:Show(); editorFrame.edit:SetFocus()
    if WN.RaiseFrame then WN.RaiseFrame(editorFrame) end
end

function WowNote_ShowCharacterNote(name, realm)
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("characterNotes") then return end
    name, realm = SplitNameRealm(name or (UnitName("target") or ""))
    local note = GetNote(name, realm)
    if not note or Trim(note.note or "") == "" then Print("No character note for " .. tostring(name) .. "."); return end
    if not noteFrame then
        noteFrame = CreateFrame("Frame", "WowNoteCharacterNoteView", UIParent)
        noteFrame:SetWidth(340); noteFrame:SetHeight(170); noteFrame:SetPoint("CENTER")
        noteFrame:SetFrameStrata("FULLSCREEN_DIALOG"); if noteFrame.SetToplevel then noteFrame:SetToplevel(true) end; noteFrame:SetFrameLevel(100); noteFrame:SetMovable(true); noteFrame:EnableMouse(true)
        noteFrame:RegisterForDrag("LeftButton")
        noteFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        noteFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        noteFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        local close = CreateFrame("Button", nil, noteFrame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", noteFrame, "TOPRIGHT", -4, -4)
        noteFrame.title = noteFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); noteFrame.title:SetPoint("TOPLEFT", noteFrame, "TOPLEFT", 18, -16)
        noteFrame.text = noteFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); noteFrame.text:SetPoint("TOPLEFT", noteFrame, "TOPLEFT", 24, -52); noteFrame.text:SetWidth(290); noteFrame.text:SetJustifyH("LEFT"); noteFrame.text:SetJustifyV("TOP")
    end
    noteFrame.title:SetText((note.punk and (PunkIcon(16) .. " Punk Note: ") or "Character Note: ") .. name)
    noteFrame.text:SetText(((note.punk and (PUNK_LABEL .. "\n\n") or "") .. (note.note or "")))
    noteFrame:Show(); if WN.RaiseFrame then WN.RaiseFrame(noteFrame) end
end

local function SortedNotes()
    local out = {}
    for key, note in pairs(EnsureDB()) do table.insert(out, { key = key, note = note }) end
    table.sort(out, function(a,b) return string.lower(a.key) < string.lower(b.key) end)
    return out
end

function WowNote_RefreshCharacterNotes()
    if not listFrame or not listFrame.child then return end
    local sorted = SortedNotes()
    for i=1, table.getn(rows) do rows[i]:Hide() end
    local last
    for i, info in ipairs(sorted) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, listFrame.child)
            row:SetHeight(24); row:SetWidth(340); row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 4, 0); row.text:SetWidth(252); row.text:SetJustifyH("LEFT")
            row.delete = MakeButton(row, "Delete", 62, 20)
            row.delete:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.delete:SetScript("OnClick", function(self)
                local owner = self:GetParent()
                if not owner or not owner.key then return end
                local n, r = SplitNameRealm(owner.key)
                ConfirmDeleteNote(n, r)
            end)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            rows[i] = row
        end
        row.key = info.key
        local punkPrefix = info.note.punk and (PunkIcon(14) .. " ") or ""
        local noteText = Trim(info.note.note or "")
        if noteText == "" and info.note.punk then noteText = "marked as Punk" end
        row.text:SetText(punkPrefix .. (info.note.name or info.key) .. ": " .. string.sub(noteText, 1, 80))
        if info.note.punk then row.text:SetTextColor(1, 0.20, 0.20) else row.text:SetTextColor(1, 0.82, 0) end
        row:ClearAllPoints()
        if last then row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2) else row:SetPoint("TOPLEFT", listFrame.child, "TOPLEFT", 0, 0) end
        row:SetScript("OnClick", function(self, button)
            local n, r = SplitNameRealm(self.key)
            if button == "RightButton" then WowNote_OpenCharacterNoteEditor(n, r) else WowNote_ShowCharacterNote(n, r) end
        end)
        row:Show(); last = row
    end
    listFrame.child:SetHeight(math.max(260, table.getn(sorted) * 26 + 10))
end

function WowNote_OpenCharacterNotes()
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("characterNotes") then Print("Character notes are disabled in settings."); return end
    if not listFrame then
        listFrame = CreateFrame("Frame", "WowNoteCharacterNotesFrame", UIParent)
        listFrame:SetWidth(420); listFrame:SetHeight(420); listFrame:SetPoint("CENTER")
        listFrame:SetFrameStrata("FULLSCREEN_DIALOG"); if listFrame.SetToplevel then listFrame:SetToplevel(true) end; listFrame:SetFrameLevel(100); listFrame:SetMovable(true); listFrame:EnableMouse(true)
        listFrame:RegisterForDrag("LeftButton")
        listFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        listFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        listFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        local title = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 18, -16); title:SetText("Character Notes")
        local close = CreateFrame("Button", nil, listFrame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -4, -4)
        local scroll = CreateFrame("ScrollFrame", "WowNoteCharacterNotesScroll", listFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 22, -52); scroll:SetWidth(360); scroll:SetHeight(300)
        listFrame.child = CreateFrame("Frame", nil, scroll); listFrame.child:SetWidth(340); listFrame.child:SetHeight(300); scroll:SetScrollChild(listFrame.child)
        local new = MakeButton(listFrame, "New target note", 120, 24); new:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMLEFT", 24, 24)
        new:SetScript("OnClick", function() WowNote_OpenCharacterNoteEditor(UnitName("target")) end)
        listFrame.warnPunksCheck = CreateFrame("CheckButton", nil, listFrame, "UICheckButtonTemplate")
        listFrame.warnPunksCheck:SetPoint("LEFT", new, "RIGHT", 18, 0)
        listFrame.warnPunksCheck:SetWidth(24); listFrame.warnPunksCheck:SetHeight(24)
        listFrame.warnPunksCheck.text = listFrame.warnPunksCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        listFrame.warnPunksCheck.text:SetPoint("LEFT", listFrame.warnPunksCheck, "RIGHT", 4, 0)
        listFrame.warnPunksCheck.text:SetText("Warn when punks join")
        listFrame.warnPunksCheck:SetScript("OnClick", function(self)
            if WowNote_SetPunkJoinWarningsEnabled then WowNote_SetPunkJoinWarningsEnabled(self:GetChecked() and true or false) end
        end)
    end
    WowNote_RefreshCharacterNotes()
    if listFrame.warnPunksCheck and WowNote_ArePunkJoinWarningsEnabled then listFrame.warnPunksCheck:SetChecked(WowNote_ArePunkJoinWarningsEnabled()) end
    listFrame:Show(); if WN.RaiseFrame then WN.RaiseFrame(listFrame) end
end

local function GetPopupName()
    local menu = UIDROPDOWNMENU_INIT_MENU
    if not menu then return nil end
    local name = menu.name
    local server = menu.server
    if (not name or name == "") and menu.unit and UnitName(menu.unit) then name, server = UnitName(menu.unit) end
    if server and server ~= "" then return name .. "-" .. server end
    return name
end

local function InstallUnitPopup()
    if not UnitPopupButtons or not UnitPopupMenus then return end
    if UnitPopupButtons["WOWNOTE_EDIT_PLAYER_NOTE"] then return end
    UnitPopupButtons["WOWNOTE_EDIT_PLAYER_NOTE"] = { text = "Create/Edit WowNote", dist = 0 }
    UnitPopupButtons["WOWNOTE_SHOW_PLAYER_NOTE"] = { text = "Show WowNote", dist = 0 }
    UnitPopupButtons["WOWNOTE_TOGGLE_PUNK"] = { text = "Mark/Unmark Punk", dist = 0 }
    local menus = { "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "TARGET" }
    for _, menuName in ipairs(menus) do
        local menu = UnitPopupMenus[menuName]
        if type(menu) == "table" then
            table.insert(menu, "WOWNOTE_EDIT_PLAYER_NOTE")
            table.insert(menu, "WOWNOTE_SHOW_PLAYER_NOTE")
            table.insert(menu, "WOWNOTE_TOGGLE_PUNK")
        end
    end
    if UnitPopup_OnClick then
        hooksecurefunc("UnitPopup_OnClick", function(self)
            if not self or not self.value then return end
            if self.value == "WOWNOTE_EDIT_PLAYER_NOTE" then
                WowNote_OpenCharacterNoteEditor(GetPopupName())
            elseif self.value == "WOWNOTE_SHOW_PLAYER_NOTE" then
                WowNote_ShowCharacterNote(GetPopupName())
            elseif self.value == "WOWNOTE_TOGGLE_PUNK" then
                WowNote_ToggleCharacterPunk(GetPopupName())
            end
        end)
    end
end

local oldTooltipSetUnit
local function TooltipUnitHook(self)
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("characterNotes") then return end
    local _, unit = self:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    local name, realm = UnitName(unit)
    local note = GetNote(name, realm)
    if note and note.punk == true then
        self:AddLine(PunkIcon(14) .. " WowNote: PUNK", 1, 0.08, 0.08, true)
        if Trim(note.note or "") ~= "" then
            self:AddLine("Punk note: " .. note.note, 1, 0.55, 0.55, true)
        end
        self:Show()
        return
    end
    if not (WowNote_AreCharacterNotesAlwaysShown and WowNote_AreCharacterNotesAlwaysShown()) then return end
    if note and Trim(note.note or "") ~= "" then
        self:AddLine("WowNote: " .. note.note, 1, 0.82, 0, true)
        self:Show()
    end
end

local function CurrentRosterKeys()
    local members = {}
    local function addUnit(unit)
        if unit and UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
            local name, realm = UnitName(unit)
            local key = BuildKey(name, realm)
            if key then members[key] = { name = name, realm = realm, unit = unit } end
        end
    end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do addUnit("raid" .. i) end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do addUnit("party" .. i) end
    end
    return members
end

local function CreatePunkWarningFrame()
    if punkWarningFrame then return end
    punkWarningFrame = CreateFrame("Frame", "WowNotePunkWarningFrame", UIParent)
    punkWarningFrame:SetWidth(430); punkWarningFrame:SetHeight(215); punkWarningFrame:SetPoint("CENTER")
    punkWarningFrame:SetFrameStrata("FULLSCREEN_DIALOG"); if punkWarningFrame.SetToplevel then punkWarningFrame:SetToplevel(true) end; punkWarningFrame:SetFrameLevel(120)
    punkWarningFrame:SetMovable(true); punkWarningFrame:EnableMouse(true); punkWarningFrame:RegisterForDrag("LeftButton")
    punkWarningFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    punkWarningFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    punkWarningFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 32, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    punkWarningFrame:SetBackdropColor(0.18, 0, 0, 0.96)
    local close = CreateFrame("Button", nil, punkWarningFrame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", punkWarningFrame, "TOPRIGHT", -4, -4)
    punkWarningFrame.icon = punkWarningFrame:CreateTexture(nil, "OVERLAY")
    punkWarningFrame.icon:SetTexture(PUNK_ICON_TEXTURE); punkWarningFrame.icon:SetWidth(36); punkWarningFrame.icon:SetHeight(36); punkWarningFrame.icon:SetPoint("TOPLEFT", punkWarningFrame, "TOPLEFT", 20, -18)
    punkWarningFrame.title = punkWarningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    punkWarningFrame.title:SetPoint("LEFT", punkWarningFrame.icon, "RIGHT", 10, 0); punkWarningFrame.title:SetTextColor(1, 0.08, 0.08); punkWarningFrame.title:SetText("PUNK JOINED")
    punkWarningFrame.text = punkWarningFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    punkWarningFrame.text:SetPoint("TOPLEFT", punkWarningFrame, "TOPLEFT", 24, -70); punkWarningFrame.text:SetWidth(380); punkWarningFrame.text:SetJustifyH("LEFT"); punkWarningFrame.text:SetJustifyV("TOP")
    punkWarningFrame.openNote = MakeButton(punkWarningFrame, "Open Note", 90, 24)
    punkWarningFrame.openNote:SetPoint("BOTTOMLEFT", punkWarningFrame, "BOTTOMLEFT", 24, 22)
    punkWarningFrame.openNote:SetScript("OnClick", function()
        if punkWarningFrame.playerName then WowNote_OpenCharacterNoteEditor(punkWarningFrame.playerName, punkWarningFrame.realm) end
    end)
    local closeButton = MakeButton(punkWarningFrame, "Close", 80, 24)
    closeButton:SetPoint("LEFT", punkWarningFrame.openNote, "RIGHT", 10, 0)
    closeButton:SetScript("OnClick", function() punkWarningFrame:Hide() end)
    punkWarningFrame:Hide()
end

local function PlayPunkWarningSound()
    if PlaySoundFile then
        local ok = pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.wav")
        if ok then return end
    end
    if PlaySound then pcall(PlaySound, "RaidWarning") end
end

local function ShowPunkJoinWarning(name, realm, note)
    CreatePunkWarningFrame()
    punkWarningFrame.playerName = name; punkWarningFrame.realm = realm
    punkWarningFrame.title:SetText(PunkIcon(18) .. " PUNK JOINED: " .. tostring(name or "unknown"))
    local body = "A player marked as Punk joined your group/raid."
    if note and Trim(note.note or "") ~= "" then body = body .. "\n\nChar note:\n" .. note.note end
    punkWarningFrame.text:SetText(body)
    punkWarningFrame:Show(); if WN.RaiseFrame then WN.RaiseFrame(punkWarningFrame) end
    PlayPunkWarningSound()
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] then
        RaidNotice_AddMessage(RaidWarningFrame, "WowNote PUNK joined: " .. tostring(name or "unknown"), ChatTypeInfo["RAID_WARNING"])
    end
end

local function ScanRosterForPunks(reason)
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("characterNotes") then return end
    local current = CurrentRosterKeys()
    if not rosterInitialized then
        knownRosterKeys = current
        rosterInitialized = true
        return
    end
    local warnEnabled = WowNote_ArePunkJoinWarningsEnabled and WowNote_ArePunkJoinWarningsEnabled()
    if warnEnabled then
        local now = time and time() or 0
        for key, info in pairs(current) do
            if not knownRosterKeys[key] then
                local note = GetNote(info.name, info.realm)
                if note and note.punk == true and ((lastPunkAlerts[key] or 0) + 30 <= now) then
                    lastPunkAlerts[key] = now
                    ShowPunkJoinWarning(info.name, info.realm, note)
                end
            end
        end
    end
    knownRosterKeys = current
end

local function CreatePortraitMarker(frameName, portraitName, unit)
    local parent = _G[frameName]
    local portrait = _G[portraitName]
    if not parent or not portrait or portraitMarkers[unit] then return end
    local marker = CreateFrame("Frame", "WowNotePunkPortraitMarker_" .. unit, parent)
    marker:SetWidth(24); marker:SetHeight(24); marker:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", 7, 7)
    marker.texture = marker:CreateTexture(nil, "OVERLAY")
    marker.texture:SetAllPoints(marker); marker.texture:SetTexture(PUNK_ICON_TEXTURE)
    marker:Hide()
    portraitMarkers[unit] = marker
end

function WowNote_UpdatePunkPortraitMarkers()
    CreatePortraitMarker("TargetFrame", "TargetFramePortrait", "target")
    CreatePortraitMarker("FocusFrame", "FocusFramePortrait", "focus")
    for unit, marker in pairs(portraitMarkers) do
        if UnitExists(unit) and UnitIsPlayer(unit) then
            local name, realm = UnitName(unit)
            if WowNote_IsCharacterPunk(name, realm) then marker:Show() else marker:Hide() end
        else
            marker:Hide()
        end
    end
end

function WowNote_CharacterNotesHandleSlash(args)
    args = string.lower(Trim(args or ""))
    if args == "punk" or args == "punk target" then
        local tn, tr = UnitName("target"); WowNote_ToggleCharacterPunk(BuildKey(tn, tr))
    elseif args == "warnpunks on" or args == "punkwarn on" then
        if WowNote_SetPunkJoinWarningsEnabled then WowNote_SetPunkJoinWarningsEnabled(true) end
        Print("Punk join warnings enabled.")
    elseif args == "warnpunks off" or args == "punkwarn off" then
        if WowNote_SetPunkJoinWarningsEnabled then WowNote_SetPunkJoinWarningsEnabled(false) end
        Print("Punk join warnings disabled.")
    else
        Print("/wn punk - Toggle target as Punk")
        Print("/wn punkwarn on/off - Toggle Punk join warnings")
    end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("PARTY_MEMBERS_CHANGED")
init:RegisterEvent("RAID_ROSTER_UPDATE")
init:RegisterEvent("PLAYER_TARGET_CHANGED")
init:RegisterEvent("PLAYER_FOCUS_CHANGED")
init:RegisterEvent("UNIT_NAME_UPDATE")
WowNoteProfiler_SetScript(init, "OnEvent", "CharacterNotes.Init", function(self, event, unit)
    EnsureDB()
    if event == "PLAYER_LOGIN" then
        InstallUnitPopup()
    end
    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_LOGIN" then
        ScanRosterForPunks(event)
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "PLAYER_LOGIN" or (event == "UNIT_NAME_UPDATE" and (unit == "target" or unit == "focus")) then
        WowNote_UpdatePunkPortraitMarkers()
    end
    if event ~= "PLAYER_LOGIN" then return end
    if GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", TooltipUnitHook)
    else
        oldTooltipSetUnit = GameTooltip:GetScript("OnTooltipSetUnit")
        GameTooltip:SetScript("OnTooltipSetUnit", function(self)
            if oldTooltipSetUnit then oldTooltipSetUnit(self) end
            TooltipUnitHook(self)
        end)
    end
end)
