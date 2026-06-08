-- WowNote_DataTransferPicker.lua
-- Central send/export/import picker for all transferable WowNote data types.

local WN = WowNote_Internal or {}
local pickerFrame, importFrame
local categoryButtons, itemButtons = {}, {}
local selectedCategory, selectedItem
local currentMode, currentTarget, currentAuthCode

local EXPORT_PREFIX = "WNDATA1"

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

local function PercentEncode(text)
    if WN.PercentEncode then return WN.PercentEncode(text) end
    text = tostring(text or "")
    text = string.gsub(text, "([^A-Za-z0-9_%.%-])", function(c) return string.format("%%%02X", string.byte(c)) end)
    return text
end

local function PercentDecode(text)
    if WN.PercentDecode then return WN.PercentDecode(text) end
    text = tostring(text or "")
    text = string.gsub(text, "%%(%x%x)", function(h) return string.char(tonumber(h, 16) or 32) end)
    return text
end

local function MakeButton(parent, text, width, height)
    if WN.MakeButton then return WN.MakeButton(parent, text, width, height) end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width or 90)
    b:SetHeight(height or 22)
    b:SetText(text or "")
    return b
end

local function InitDB()
    if WN.InitDB then WN.InitDB() end
    WowNoteDB = WowNoteDB or {}
    WowNoteDB.notes = WowNoteDB.notes or {}
    WowNoteDB.characterNotes = WowNoteDB.characterNotes or {}
    WowNoteDB.tacticalMaps = WowNoteDB.tacticalMaps or {}
    WowNoteDB.raidPlannerPresets = WowNoteDB.raidPlannerPresets or {}
    WowNoteDB.talentPlans = WowNoteDB.talentPlans or {}
    WowNoteCharDB = WowNoteCharDB or {}
end

local function CountTable(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function SortedKeys(t)
    local keys = {}
    if type(t) == "table" then for k in pairs(t) do table.insert(keys, tostring(k)) end end
    table.sort(keys, function(a, b) return string.lower(a) < string.lower(b) end)
    return keys
end

local function SerializeValue(value, depth)
    depth = depth or 0
    if depth > 12 then return "nil" end
    local valueType = type(value)
    if valueType == "nil" then
        return "nil"
    elseif valueType == "number" or valueType == "boolean" then
        return tostring(value)
    elseif valueType == "string" then
        return string.format("%q", value)
    elseif valueType == "table" then
        local parts = { "{" }
        for k, v in pairs(value) do
            if type(k) == "string" or type(k) == "number" then
                table.insert(parts, "[" .. SerializeValue(k, depth + 1) .. "]=" .. SerializeValue(v, depth + 1) .. ",")
            end
        end
        table.insert(parts, "}")
        return table.concat(parts, "")
    end
    return "nil"
end

local function DeserializeValue(text)
    if type(text) ~= "string" or text == "" then return nil end
    local loader = loadstring or load
    if not loader then return nil end
    local fn, err = loader("return " .. text)
    if not fn then return nil, err end
    local ok, value = pcall(fn)
    if not ok then return nil, value end
    return value
end

local function EncodeDataItem(item)
    local serialized = EXPORT_PREFIX .. "\n" .. SerializeValue(item)
    local compressed = WN.CompressText and WN.CompressText(serialized) or serialized
    local b64 = WN.Base64Encode and WN.Base64Encode(compressed) or compressed
    return WN.Base64Encode and WN.Base64Encode(EXPORT_PREFIX .. "\nB64:" .. b64) or (EXPORT_PREFIX .. "\n" .. serialized), string.len(serialized or ""), string.len(compressed or "")
end

function WowNote_DecodeDataTransferText(exportText)
    exportText = Trim(exportText or "")
    exportText = string.gsub(exportText, "%s+", "")
    if exportText == "" then return nil, "No import text entered." end

    local decoded = WN.Base64Decode and WN.Base64Decode(exportText) or exportText
    if string.sub(decoded or "", 1, string.len(EXPORT_PREFIX)) ~= EXPORT_PREFIX then
        return nil, "Invalid WowNote data export text."
    end

    local payload = string.match(decoded, "^" .. EXPORT_PREFIX .. "\n(.*)$") or ""
    local serialized
    if string.sub(payload, 1, 4) == "B64:" and WN.Base64Decode then
        local compressed = WN.Base64Decode(string.sub(payload, 5))
        serialized = WN.DecompressText and WN.DecompressText(compressed or "") or compressed
    else
        serialized = payload
    end
    if string.sub(serialized or "", 1, string.len(EXPORT_PREFIX)) == EXPORT_PREFIX then
        serialized = string.match(serialized, "^" .. EXPORT_PREFIX .. "\n(.*)$") or ""
    end
    local item, err = DeserializeValue(serialized)
    if type(item) ~= "table" then return nil, err or "Decoded export does not contain WowNote data." end
    return item, nil
end

function WowNote_IsGenericTransferSerialized(serialized)
    return type(serialized) == "string" and string.sub(serialized, 1, string.len(EXPORT_PREFIX)) == EXPORT_PREFIX
end

function WowNote_DecodeGenericTransferSerialized(serialized)
    if not WowNote_IsGenericTransferSerialized(serialized) then return nil end
    local payload = string.match(serialized, "^" .. EXPORT_PREFIX .. "\n(.*)$") or ""
    local item = DeserializeValue(payload)
    if type(item) == "table" then return item end
    return nil
end

function WowNote_BuildTransferPayloadForDataItem(item)
    if type(item) ~= "table" then return nil, "No data selected." end
    local serialized = EXPORT_PREFIX .. "\n" .. SerializeValue(item)
    local compressed = WN.CompressText and WN.CompressText(serialized) or serialized
    local payload = "B64:" .. (WN.Base64Encode and WN.Base64Encode(compressed) or compressed)
    return payload, string.len(serialized or ""), string.len(compressed or "")
end

local function CloneTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = CloneTable(v) end
    return copy
end

local function BuildItem(dataType, key, title, data)
    return {
        type = dataType,
        key = key,
        title = title or tostring(key or dataType),
        data = CloneTable(data),
        exportedAt = time and time() or 0,
    }
end

local function BuildBundle(items)
    return {
        type = "bundle",
        key = "bundle",
        title = "All supported WowNote data",
        items = items,
        exportedAt = time and time() or 0,
    }
end

local function GetCategories()
    InitDB()
    local categories = {}
    local function add(key, label, items)
        table.insert(categories, { key = key, label = label, items = items or {} })
    end

    local items = {}
    for _, guid in ipairs(SortedKeys(WowNoteDB.notes)) do
        local note = WowNoteDB.notes[guid]
        if type(note) == "table" then table.insert(items, BuildItem("note", guid, note.title or guid, note)) end
    end
    add("notes", "Notes", items)

    items = {}
    for _, key in ipairs(SortedKeys(WowNoteDB.characterNotes)) do
        local note = WowNoteDB.characterNotes[key]
        if type(note) == "table" then table.insert(items, BuildItem("characterNote", key, key, note)) end
    end
    add("characterNotes", "Character Notes", items)

    items = {}
    for _, key in ipairs(SortedKeys(WowNoteDB.tacticalMaps)) do
        table.insert(items, BuildItem("tacticalMap", key, key, WowNoteDB.tacticalMaps[key]))
    end
    add("tactics", "Tactics", items)

    items = {}
    for _, key in ipairs(SortedKeys(WowNoteDB.raidPlannerPresets)) do
        table.insert(items, BuildItem("raidPlannerPreset", key, key, WowNoteDB.raidPlannerPresets[key]))
    end
    add("raidPlanner", "Raid Planner", items)

    items = {}
    for _, key in ipairs(SortedKeys(WowNoteDB.talentPlans)) do
        table.insert(items, BuildItem("talentPlan", key, key, WowNoteDB.talentPlans[key]))
    end
    add("talents", "Talents", items)

    items = {}
    if type(WowNoteDB.raidIds) == "table" and CountTable(WowNoteDB.raidIds) > 0 then
        table.insert(items, BuildItem("raidIds", "raidIds", "All Raid IDs", WowNoteDB.raidIds))
    end
    add("raidIds", "Raid IDs", items)

    items = {}
    if type(WowNoteCharDB.itemTracker) == "table" and CountTable(WowNoteCharDB.itemTracker) > 0 then
        table.insert(items, BuildItem("itemTracker", "itemTracker", "Tracker / Restock data (current character)", WowNoteCharDB.itemTracker))
    end
    add("tracker", "Tracker / Restock", items)

    items = {}
    if type(WowNoteDB.bankSnapshots) == "table" and CountTable(WowNoteDB.bankSnapshots) > 0 then
        table.insert(items, BuildItem("bankSnapshots", "bankSnapshots", "Bank snapshots", WowNoteDB.bankSnapshots))
    end
    add("bank", "Bank", items)

    local all = {}
    for _, category in ipairs(categories) do
        for _, item in ipairs(category.items or {}) do table.insert(all, item) end
    end
    table.insert(categories, 1, { key = "all", label = "All supported", items = { BuildBundle(all) } })
    return categories
end

function WowNote_SaveTransferredDataItem(item, sender)
    InitDB()
    if type(item) ~= "table" then return false, "No data item." end

    if item.type == "bundle" then
        local count = 0
        for _, child in ipairs(item.items or {}) do
            local ok = WowNote_SaveTransferredDataItem(child, sender)
            if ok then count = count + 1 end
        end
        return true, "Imported " .. tostring(count) .. " bundled item(s)."
    end

    local key = Trim(item.key or "")
    local data = CloneTable(item.data)
    if item.type == "note" then
        local guid = tostring(time and time() or 0) .. tostring(math and math.random and math.random(10000, 99999) or 10000)
        data = type(data) == "table" and data or {}
        data.guid = guid
        data.title = Trim(data.title or item.title or "Shared note")
        if sender and sender ~= "" then data.title = data.title .. " (from " .. tostring(sender) .. ")" end
        data.created = time and time() or data.created
        data.updated = time and time() or data.updated
        data.sharedFrom = sender
        WowNoteDB.notes[guid] = data
        return true, "Imported note: " .. tostring(data.title or "Untitled")
    elseif item.type == "characterNote" then
        if key == "" and type(data) == "table" and data.name then key = tostring(data.name) .. (data.realm and data.realm ~= "" and ("-" .. tostring(data.realm)) or "") end
        if key == "" then return false, "Character note key missing." end
        WowNoteDB.characterNotes[key] = data
        return true, "Imported character note: " .. key
    elseif item.type == "tacticalMap" then
        if key == "" then key = item.title or "Imported tactic" end
        WowNoteDB.tacticalMaps = WowNoteDB.tacticalMaps or {}
        WowNoteDB.tacticalMaps[key] = data
        return true, "Imported tactic: " .. key
    elseif item.type == "raidPlannerPreset" then
        if key == "" then key = item.title or "Imported preset" end
        WowNoteDB.raidPlannerPresets[key] = data
        return true, "Imported raid preset: " .. key
    elseif item.type == "talentPlan" then
        if key == "" then return false, "Talent class key missing." end
        WowNoteDB.talentPlans[key] = data
        return true, "Imported talent plan: " .. key
    elseif item.type == "raidIds" then
        WowNoteDB.raidIds = data
        return true, "Imported raid ID data."
    elseif item.type == "itemTracker" then
        WowNoteCharDB = WowNoteCharDB or {}
        WowNoteCharDB.itemTracker = data
        return true, "Imported tracker/restock data for this character."
    elseif item.type == "bankSnapshots" then
        WowNoteDB.bankSnapshots = data
        return true, "Imported bank snapshots."
    end
    return false, "Unsupported data type: " .. tostring(item.type)
end

local function CreatePicker()
    if pickerFrame then return end
    pickerFrame = CreateFrame("Frame", "WowNoteDataTransferPicker", UIParent)
    pickerFrame:SetWidth(660)
    pickerFrame:SetHeight(430)
    pickerFrame:SetPoint("CENTER", UIParent, "CENTER", 80, 20)
    pickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    pickerFrame:SetToplevel(true)
    pickerFrame:EnableMouse(true)
    pickerFrame:SetMovable(true)
    pickerFrame:RegisterForDrag("LeftButton")
    pickerFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    pickerFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    pickerFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    pickerFrame:Hide()

    pickerFrame.title = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pickerFrame.title:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", 18, -16)
    local close = CreateFrame("Button", nil, pickerFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", pickerFrame, "TOPRIGHT", -4, -4)

    pickerFrame.hint = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pickerFrame.hint:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", 22, -48)
    pickerFrame.hint:SetWidth(610)
    pickerFrame.hint:SetJustifyH("LEFT")

    pickerFrame.categoryTitle = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pickerFrame.categoryTitle:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", 24, -78)
    pickerFrame.categoryTitle:SetText("Data type")

    pickerFrame.itemTitle = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pickerFrame.itemTitle:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", 224, -78)
    pickerFrame.itemTitle:SetText("Item")

    pickerFrame.status = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickerFrame.status:SetPoint("BOTTOMLEFT", pickerFrame, "BOTTOMLEFT", 24, 54)
    pickerFrame.status:SetWidth(610)
    pickerFrame.status:SetJustifyH("LEFT")

    pickerFrame.action = MakeButton(pickerFrame, "Action", 110, 24)
    pickerFrame.action:SetPoint("BOTTOMLEFT", pickerFrame, "BOTTOMLEFT", 24, 24)
    pickerFrame.action:SetScript("OnClick", function()
        if not selectedItem then pickerFrame.status:SetText("Select a data item first."); return end
        local text, originalSize, compressedSize = EncodeDataItem(selectedItem)
        if currentMode == "export" then
            WowNote_OpenDataImportExportDialog("export", text, "Exported " .. tostring(selectedItem.title or selectedItem.type or "data") .. " (" .. tostring(compressedSize or "?") .. "/" .. tostring(originalSize or "?") .. " bytes).")
            pickerFrame:Hide()
        elseif currentMode == "send" then
            if not WowNote_SendDataItemToPlayer then pickerFrame.status:SetText("Send function is not available."); return end
            local ok = WowNote_SendDataItemToPlayer(currentTarget, currentAuthCode, selectedItem)
            if ok ~= false then pickerFrame:Hide() end
        end
    end)

    local cancel = MakeButton(pickerFrame, "Cancel", 90, 24)
    cancel:SetPoint("LEFT", pickerFrame.action, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function() pickerFrame:Hide() end)
end

local function RenderItems(category)
    for _, b in ipairs(itemButtons) do b:Hide() end
    selectedItem = nil
    if not category then return end
    if table.getn(category.items or {}) == 0 then
        pickerFrame.status:SetText("No " .. tostring(category.label or "data") .. " available.")
        return
    end
    pickerFrame.status:SetText("Select one item, then click " .. (currentMode == "send" and "Send" or "Export") .. ".")
    for i, item in ipairs(category.items or {}) do
        local b = itemButtons[i]
        if not b then
            b = MakeButton(pickerFrame, "", 390, 23)
            b:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", 224, -100 - ((i - 1) * 26))
            itemButtons[i] = b
        end
        local label = tostring(item.title or item.key or item.type or "Data")
        if string.len(label) > 54 then label = string.sub(label, 1, 51) .. "..." end
        b:SetText(label)
        b:SetScript("OnClick", function()
            selectedItem = item
            pickerFrame.status:SetText("Selected: " .. tostring(item.title or item.key or item.type or "Data"))
        end)
        b:Show()
        if i >= 11 then break end
    end
end

local function RenderCategories()
    local categories = GetCategories()
    for _, b in ipairs(categoryButtons) do b:Hide() end
    for i, category in ipairs(categories) do
        local b = categoryButtons[i]
        if not b then
            b = MakeButton(pickerFrame, "", 170, 23)
            b:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", 24, -100 - ((i - 1) * 26))
            categoryButtons[i] = b
        end
        b:SetText((category.label or category.key or "Data") .. " (" .. tostring(table.getn(category.items or {})) .. ")")
        b:SetScript("OnClick", function()
            selectedCategory = category
            RenderItems(category)
        end)
        b:Show()
    end
    selectedCategory = categories[1]
    RenderItems(selectedCategory)
end

function WowNote_OpenTransferPicker(mode, target, authCode)
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("dataTransfer") then Print("Data transfer module is disabled."); return end
    CreatePicker()
    currentMode = mode == "send" and "send" or "export"
    currentTarget = target
    currentAuthCode = authCode
    pickerFrame.title:SetText(currentMode == "send" and "Send WowNote data" or "Export WowNote data")
    pickerFrame.hint:SetText(currentMode == "send" and "Choose what to send. You no longer need to open the note or tool first." or "Choose what to export. You no longer need to open the note or tool first.")
    pickerFrame.action:SetText(currentMode == "send" and "Send" or "Export")
    RenderCategories()
    pickerFrame:Show()
    if WN.RaiseFrame then WN.RaiseFrame(pickerFrame) elseif pickerFrame.Raise then pickerFrame:Raise() end
end

function WowNote_OpenDataExportPicker()
    WowNote_OpenTransferPicker("export")
end

function WowNote_OpenDataSendPicker(target, authCode)
    WowNote_OpenTransferPicker("send", target, authCode)
end

function WowNote_OpenDataImportExportDialog(mode, initialText, status)
    if not importFrame then
        importFrame = CreateFrame("Frame", "WowNoteDataImportExportFrame", UIParent)
        importFrame:SetWidth(640)
        importFrame:SetHeight(420)
        importFrame:SetPoint("CENTER")
        importFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        importFrame:SetToplevel(true)
        importFrame:EnableMouse(true)
        importFrame:SetMovable(true)
        importFrame:RegisterForDrag("LeftButton")
        importFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        importFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        importFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })

        importFrame.title = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        importFrame.title:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 18, -16)
        local close = CreateFrame("Button", nil, importFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", importFrame, "TOPRIGHT", -4, -4)

        local bg = CreateFrame("Frame", nil, importFrame)
        bg:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 22, -70)
        bg:SetWidth(590)
        bg:SetHeight(270)
        bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        bg:SetBackdropColor(0, 0, 0, 0.85)

        local scroll = CreateFrame("ScrollFrame", "WowNoteDataImportExportScroll", bg, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -28, 4)
        importFrame.edit = CreateFrame("EditBox", "WowNoteDataImportExportEdit", scroll)
        importFrame.edit:SetMultiLine(true)
        importFrame.edit:SetAutoFocus(false)
        importFrame.edit:SetFontObject(ChatFontNormal)
        importFrame.edit:SetWidth(540)
        importFrame.edit:SetHeight(900)
        importFrame.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(importFrame.edit)

        importFrame.status = importFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        importFrame.status:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 24, -350)
        importFrame.status:SetWidth(580)
        importFrame.status:SetJustifyH("LEFT")

        importFrame.importButton = MakeButton(importFrame, "Import", 90, 24)
        importFrame.importButton:SetPoint("BOTTOMLEFT", importFrame, "BOTTOMLEFT", 24, 22)
        importFrame.importButton:SetScript("OnClick", function()
            local item, err = WowNote_DecodeDataTransferText(importFrame.edit:GetText() or "")
            if not item and WowNote_DecodeExportedNote then
                local note, noteErr = WowNote_DecodeExportedNote(importFrame.edit:GetText() or "")
                if note then item = BuildItem("note", "legacy-note", note.title or "Imported note", note) else err = err or noteErr end
            end
            if not item then importFrame.status:SetText(err or "Import failed."); return end
            local ok, msg = WowNote_SaveTransferredDataItem(item, UnitName and UnitName("player") or nil)
            importFrame.status:SetText(msg or (ok and "Import complete." or "Import failed."))
            if ok then Print(msg or "Import complete.") end
        end)

        importFrame.selectButton = MakeButton(importFrame, "Select all", 100, 24)
        importFrame.selectButton:SetPoint("LEFT", importFrame.importButton, "RIGHT", 8, 0)
        importFrame.selectButton:SetScript("OnClick", function() importFrame.edit:SetFocus(); importFrame.edit:HighlightText() end)

        local closeButton = MakeButton(importFrame, "Close", 90, 24)
        closeButton:SetPoint("LEFT", importFrame.selectButton, "RIGHT", 8, 0)
        closeButton:SetScript("OnClick", function() importFrame:Hide() end)
    end
    if mode == "export" then
        importFrame.title:SetText("Export WowNote data")
        importFrame.importButton:Hide()
        importFrame.selectButton:ClearAllPoints()
        importFrame.selectButton:SetPoint("BOTTOMLEFT", importFrame, "BOTTOMLEFT", 24, 22)
        importFrame.edit:SetText(initialText or "")
        importFrame.status:SetText(status or "Copy this text and import it in another WowNote client.")
        importFrame.edit:SetFocus(); importFrame.edit:HighlightText()
    else
        importFrame.title:SetText("Import WowNote data")
        importFrame.importButton:Show()
        importFrame.selectButton:ClearAllPoints()
        importFrame.selectButton:SetPoint("LEFT", importFrame.importButton, "RIGHT", 8, 0)
        importFrame.edit:SetText(initialText or "")
        importFrame.status:SetText(status or "Paste exported WowNote data here, then click Import.")
        importFrame.edit:SetFocus(); importFrame.edit:HighlightText(0, 0)
    end
    importFrame:Show()
    if WN.RaiseFrame then WN.RaiseFrame(importFrame) elseif importFrame.Raise then importFrame:Raise() end
end

function WowNote_OpenGenericImportDialog()
    WowNote_OpenDataImportExportDialog("import", "", "Paste exported WowNote data here, then click Import.")
end
