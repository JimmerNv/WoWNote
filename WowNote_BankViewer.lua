-- WowNote_BankViewer.lua
-- Snapshot bank browser with character list, search and item tooltips.

local frame, charListFrame, gridFrame, searchBox, titleText, updatedText
local charButtons = {}
local slotButtons = {}
local selectedRealm, selectedChar
local SLOT_SIZE = 34
local SLOT_GAP = 4

local function WowNote_BankViewer_Mod(value, divisor)
    return value - math.floor(value / divisor) * divisor
end
local BANK_ID = BANK_CONTAINER or -1
local BANK_BAG_MIN = (NUM_BAG_SLOTS or 4) + 1
local BANK_BAG_MAX = (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7)

local function InitDB()
    if WowNote_Internal and WowNote_Internal.InitDB then WowNote_Internal.InitDB() end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.bankSnapshots) ~= "table" then WowNoteDB.bankSnapshots = {} end
end

local function MakeButton(parent, text, width, height)
    if WowNote_Internal and WowNote_Internal.MakeButton then
        return WowNote_Internal.MakeButton(parent, text, width, height)
    end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width or 80); b:SetHeight(height or 22); b:SetText(text or "")
    return b
end

local function Raise(f)
    if WowNote_Internal and WowNote_Internal.RaiseFrame then WowNote_Internal.RaiseFrame(f) end
end

local function FormatTime(ts)
    if not ts or ts == 0 then return "never" end
    if date then return date("%d.%m.%Y %H:%M", ts) end
    return tostring(ts)
end

local function GetCharacters()
    InitDB()
    local result = {}
    for realm, chars in pairs(WowNoteDB.bankSnapshots) do
        if type(chars) == "table" then
            for char, snapshot in pairs(chars) do
                if type(snapshot) == "table" then
                    table.insert(result, { realm = realm, char = char, updatedAt = snapshot.updatedAt or 0 })
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.realm == b.realm then return string.lower(a.char) < string.lower(b.char) end
        return string.lower(a.realm) < string.lower(b.realm)
    end)
    return result
end

local function GetSelectedSnapshot()
    InitDB()
    if selectedRealm and selectedChar and WowNoteDB.bankSnapshots[selectedRealm] then
        return WowNoteDB.bankSnapshots[selectedRealm][selectedChar]
    end
    return nil
end

local function ClearGrid()
    for i = 1, table.getn(slotButtons) do slotButtons[i]:Hide() end
end

local function CreateSlot(index)
    local button = slotButtons[index]
    if button then return button end
    button = CreateFrame("Button", nil, gridFrame)
    button:SetFrameLevel((gridFrame:GetFrameLevel() or 1) + 2)
    button:SetWidth(SLOT_SIZE)
    button:SetHeight(SLOT_SIZE)
    button:EnableMouse(true)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints(button)
    button.bg:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slotButtons[index] = button
    return button
end

local function MatchesSearch(item, query)
    if not item then return query == "" end
    if query == "" then return true end
    local hay = string.lower((item.name or "") .. " " .. (item.link or "") .. " " .. (item.itemType or "") .. " " .. (item.itemSubType or "") .. " " .. tostring(item.itemId or ""))
    return string.find(hay, query, 1, true) ~= nil
end

local function RenderSection(snapshot, bag, label, startIndex, y)
    local container = snapshot and snapshot.containers and snapshot.containers[bag]
    local size = container and container.size or 0
    if size <= 0 then return startIndex, y end

    local header = CreateSlot(startIndex)
    header:Hide()

    local text = gridFrame.headers and gridFrame.headers[bag]
    if not gridFrame.headers then gridFrame.headers = {} end
    text = gridFrame.headers[bag]
    if not text then
        text = gridFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gridFrame.headers[bag] = text
    end
    text:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 6, y)
    text:SetText(label)
    text:Show()
    y = y - 18

    local query = string.lower(searchBox and searchBox:GetText() or "")
    local cols = 10
    for slot = 1, size do
        local b = CreateSlot(startIndex)
        local col = WowNote_BankViewer_Mod(slot - 1, cols)
        local row = math.floor((slot - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 6 + col * (SLOT_SIZE + SLOT_GAP), y - row * (SLOT_SIZE + SLOT_GAP))
        local item = container.slots and container.slots[slot]
        b.itemLink = item and item.link or nil
        if item and item.texture then
            b.icon:SetTexture(item.texture)
            b.icon:Show()
            if item.count and item.count > 1 then b.count:SetText(tostring(item.count)) else b.count:SetText("") end
            if MatchesSearch(item, query) then b:SetAlpha(1) else b:SetAlpha(0.18) end
        else
            b.icon:Hide()
            b.count:SetText("")
            b:SetAlpha(query == "" and 1 or 0.25)
        end
        b:Show()
        startIndex = startIndex + 1
    end

    y = y - (math.ceil(size / cols) * (SLOT_SIZE + SLOT_GAP)) - 12
    return startIndex, y
end

local function RefreshCharacters()
    if not charListFrame then return end
    local chars = GetCharacters()
    for i = 1, table.getn(charButtons) do charButtons[i]:Hide() end
    if not selectedChar and table.getn(chars) > 0 then
        selectedRealm = chars[1].realm
        selectedChar = chars[1].char
    end
    for i = 1, table.getn(chars) do
        local info = chars[i]
        local b = charButtons[i]
        if not b then
            b = CreateFrame("Button", nil, charListFrame)
            b:SetFrameLevel((charListFrame:GetFrameLevel() or 1) + 2)
            b:EnableMouse(true)
            b:SetWidth(126); b:SetHeight(22)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.text:SetPoint("LEFT", b, "LEFT", 4, 0)
            b.text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
            b.text:SetJustifyH("LEFT")
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            b.selected = b:CreateTexture(nil, "BACKGROUND")
            b.selected:SetAllPoints(b)
            b.selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            b.selected:SetBlendMode("ADD")
            charButtons[i] = b
        end
        b.realm = info.realm; b.char = info.char
        b.text:SetText(info.char)
        if selectedRealm == info.realm and selectedChar == info.char then b.selected:Show() else b.selected:Hide() end
        b:ClearAllPoints()
        if i == 1 then b:SetPoint("TOPLEFT", charListFrame, "TOPLEFT", 0, 0) else b:SetPoint("TOPLEFT", charButtons[i-1], "BOTTOMLEFT", 0, -2) end
        b:SetScript("OnClick", function(self)
            selectedRealm = self.realm; selectedChar = self.char
            WowNote_BankViewer_Refresh()
        end)
        b:Show()
    end
    charListFrame:SetHeight(math.max(360, table.getn(chars) * 24))
end

function WowNote_BankViewer_Refresh()
    if not frame then return end
    RefreshCharacters()
    ClearGrid()
    if gridFrame and gridFrame.headers then
        for _, header in pairs(gridFrame.headers) do header:Hide() end
    end
    local snapshot = GetSelectedSnapshot()
    if titleText then titleText:SetText(selectedChar and ("Bank: " .. selectedChar) or "Bank") end
    if updatedText then updatedText:SetText(snapshot and ("Last update: " .. FormatTime(snapshot.updatedAt)) or "No bank snapshot. Open a bank with a character once.") end
    if not snapshot then return end
    local index = 1
    local y = -4
    index, y = RenderSection(snapshot, BANK_ID, "Bank", index, y)
    for bag = BANK_BAG_MIN, BANK_BAG_MAX do
        index, y = RenderSection(snapshot, bag, "Bank Bag " .. tostring(bag - BANK_BAG_MIN + 1), index, y)
    end
    gridFrame:SetHeight(math.max(430, math.abs(y) + 30))
end

local function CreateUI()
    if frame then return end
    frame = CreateFrame("Frame", "WowNoteBankViewerFrame", UIParent)
    frame:SetWidth(720); frame:SetHeight(560); frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetFrameLevel(100)
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    frame:Hide()

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -18)
    titleText:SetText("Bank")

    local searchBg = CreateFrame("Frame", nil, frame)
    searchBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -48)
    searchBg:SetWidth(480); searchBg:SetHeight(28)
    searchBg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    searchBg:SetBackdropColor(0,0,0,0.85)
    searchBox = CreateFrame("EditBox", nil, searchBg)
    searchBox:SetAutoFocus(false); searchBox:SetFontObject(ChatFontNormal); searchBox:SetTextInsets(6,6,0,0)
    searchBox:EnableMouse(true)
    searchBox:SetFrameLevel(frame:GetFrameLevel() + 5)
    searchBox:SetPoint("TOPLEFT", searchBg, "TOPLEFT", 3, -3); searchBox:SetPoint("BOTTOMRIGHT", searchBg, "BOTTOMRIGHT", -3, 3)
    searchBox:SetScript("OnTextChanged", function() WowNote_BankViewer_Refresh() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    updatedText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    updatedText:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -82)
    updatedText:SetText("")

    local left = CreateFrame("Frame", nil, frame)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -48); left:SetWidth(160); left:SetHeight(460)
    left:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    left:SetBackdropColor(0,0,0,0.75)
    local charScroll = CreateFrame("ScrollFrame", "WowNoteBankCharScrollFrame", left, "UIPanelScrollFrameTemplate")
    charScroll:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -8); charScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -26, 8)
    charScroll:EnableMouse(true)
    charScroll:SetFrameLevel(frame:GetFrameLevel() + 4)
    charListFrame = CreateFrame("Frame", nil, charScroll); charListFrame:SetWidth(128); charListFrame:SetHeight(420)
    charScroll:SetScrollChild(charListFrame)

    local gridBg = CreateFrame("Frame", nil, frame)
    gridBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -105); gridBg:SetWidth(480); gridBg:SetHeight(403)
    gridBg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    gridBg:SetBackdropColor(0,0,0,0.70)
    local gridScroll = CreateFrame("ScrollFrame", "WowNoteBankGridScrollFrame", gridBg, "UIPanelScrollFrameTemplate")
    gridScroll:SetPoint("TOPLEFT", gridBg, "TOPLEFT", 8, -8); gridScroll:SetPoint("BOTTOMRIGHT", gridBg, "BOTTOMRIGHT", -28, 8)
    gridScroll:EnableMouse(true)
    gridScroll:SetFrameLevel(frame:GetFrameLevel() + 4)
    gridFrame = CreateFrame("Frame", nil, gridScroll); gridFrame:SetWidth(420); gridFrame:SetHeight(430)
    gridScroll:SetScrollChild(gridFrame)

    local refresh = MakeButton(frame, "Refresh", 80, 24)
    refresh:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 20)
    refresh:SetScript("OnClick", function() if WowNote_ItemSnapshots_ScanNow then WowNote_ItemSnapshots_ScanNow() end; WowNote_BankViewer_Refresh() end)

    local tracker = MakeButton(frame, "Tracker", 90, 24)
    tracker:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
    tracker:SetScript("OnClick", function() if WowNote_OpenItemTracker then WowNote_OpenItemTracker() end end)

    local restock = MakeButton(frame, "Restock", 90, 24)
    restock:SetPoint("LEFT", tracker, "RIGHT", 8, 0)
    restock:SetScript("OnClick", function() if WowNote_OpenRestock then WowNote_OpenRestock() end end)

    local help = MakeButton(frame, "Help", 70, 24)
    help:SetPoint("LEFT", restock, "RIGHT", 8, 0)
    help:SetScript("OnClick", function() if WowNote_PrintHelp then WowNote_PrintHelp() end end)

    frame:SetScript("OnShow", function() WowNote_BankViewer_Refresh() end)
end

function WowNote_OpenBankViewer()
    CreateUI()
    InitDB()
    if WowNote_HideSideSubmenu then WowNote_HideSideSubmenu() end
    frame:Show()
    Raise(frame)
    WowNote_BankViewer_Refresh()
end
