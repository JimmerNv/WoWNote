-- WowNote_ItemTracker.lua
-- Configurable low-item tracker with movable HUD and text/sound alerts.

local frame, listFrame, hudFrame, dropButton, statusText
local rows = {}
local hudRows = {}
local sounds = {
    NONE = { label = "None", file = nil },
    RAID_WARNING = { label = "Raid Warning", file = "Sound\\Interface\\RaidWarning.wav" },
    TELL = { label = "Tell Message", file = "Sound\\Interface\\TellMessage.wav" },
    READY_CHECK = { label = "Ready Check", file = "Sound\\Interface\\ReadyCheck.wav" },
    AUCTION = { label = "Auction Open", file = "Sound\\Interface\\AuctionWindowOpen.wav" },
}
local soundOrder = { "NONE", "RAID_WARNING", "TELL", "READY_CHECK", "AUCTION" }

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function InitDB()
    if WowNote_Internal and WowNote_Internal.InitDB then WowNote_Internal.InitDB() end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.itemTracker) ~= "table" then WowNoteDB.itemTracker = {} end
    if type(WowNoteDB.itemTracker.trackedItems) ~= "table" then WowNoteDB.itemTracker.trackedItems = {} end
    if type(WowNoteDB.itemTracker.hud) ~= "table" then
        WowNoteDB.itemTracker.hud = { shown = true, locked = true, point = "CENTER", relativePoint = "CENTER", x = 260, y = -80, scale = 1.0 }
    end
end

local function MakeButton(parent, text, width, height)
    if WowNote_Internal and WowNote_Internal.MakeButton then return WowNote_Internal.MakeButton(parent, text, width, height) end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width or 80); b:SetHeight(height or 22); b:SetText(text or "")
    return b
end

local function MakeEdit(parent, width)
    local bg = CreateFrame("Frame", nil, parent)
    bg:SetWidth(width or 55); bg:SetHeight(22)
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    bg:SetBackdropColor(0,0,0,0.85)
    local edit = CreateFrame("EditBox", nil, bg)
    edit:SetAutoFocus(false); edit:SetNumeric(true); edit:SetFontObject(ChatFontNormal); edit:SetTextInsets(4,4,0,0)
    edit:SetPoint("TOPLEFT", bg, "TOPLEFT", 2, -2); edit:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -2, 2)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit.bg = bg
    return edit
end

local function MakeCheck(parent)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetWidth(24); c:SetHeight(24)
    return c
end

local function SetHelp(widget, title, body)
    if not widget then return end
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "WowNote", 1, 1, 1)
        if body and body ~= "" then GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ExtractItemId(link)
    if WowNote_ItemSnapshots_ExtractItemId then return WowNote_ItemSnapshots_ExtractItemId(link) end
    local id = link and string.match(link, "item:(%-?%d+)")
    return id and tonumber(id) or nil
end

local function CountItem(item)
    if WowNote_ItemSnapshots_CountTracked then return WowNote_ItemSnapshots_CountTracked(item.itemId, item.countMode or "character") end
    return 0
end

local function SetStatus(msg)
    if statusText then statusText:SetText(msg or "") end
end

local function CycleSound(item)
    local current = item.alert and item.alert.soundKey or "RAID_WARNING"
    local idx = 1
    for i = 1, table.getn(soundOrder) do if soundOrder[i] == current then idx = i end end
    idx = idx + 1
    if idx > table.getn(soundOrder) then idx = 1 end
    item.alert.soundKey = soundOrder[idx]
    item.alert.sound = item.alert.soundKey ~= "NONE"
end

local function ToggleMode(item)
    if item.countMode == "account" then item.countMode = "character" else item.countMode = "account" end
end

local function EnsureItemDefaults(item)
    if type(item.alert) ~= "table" then item.alert = {} end
    if type(item.hud) ~= "table" then item.hud = {} end
    if type(item.restock) ~= "table" then item.restock = {} end
    if item.threshold == nil then item.threshold = 0 end
    if item.target == nil then item.target = item.threshold end
    if item.countMode ~= "account" then item.countMode = "character" end
    if item.alert.enabled == nil then item.alert.enabled = true end
    if item.alert.text == nil then item.alert.text = true end
    if item.alert.sound == nil then item.alert.sound = false end
    if not item.alert.soundKey then item.alert.soundKey = "RAID_WARNING" end
    if item.alert.repeatEnabled == nil then item.alert.repeatEnabled = true end
    if not item.alert.repeatSeconds then item.alert.repeatSeconds = 300 end
    if item.hud.enabled == nil then item.hud.enabled = true end
    if item.restock.enabled == nil then item.restock.enabled = false end
    if item.restock.autoBuy == nil then item.restock.autoBuy = false end
    if not item.restock.maxSpendCopper then item.restock.maxSpendCopper = 1000000 end
end

local function SortedItems()
    InitDB()
    local out = {}
    for itemId, item in pairs(WowNoteDB.itemTracker.trackedItems) do
        if type(item) == "table" then
            EnsureItemDefaults(item)
            table.insert(out, item)
        end
    end
    table.sort(out, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
    return out
end

function WowNote_ItemTracker_AddItem(link, threshold, target)
    InitDB()
    local itemId = ExtractItemId(link)
    if not itemId then Print("Could not read item id."); return end
    local name, itemLink, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture = GetItemInfo(link or itemId)
    local item = WowNoteDB.itemTracker.trackedItems[itemId] or {}
    item.itemId = itemId
    item.name = name or item.name or ("Item " .. tostring(itemId))
    item.link = link or itemLink or item.link
    item.texture = texture or item.texture
    item.threshold = tonumber(threshold) or item.threshold or 0
    item.target = tonumber(target) or item.target or item.threshold or 0
    EnsureItemDefaults(item)
    WowNoteDB.itemTracker.trackedItems[itemId] = item
    SetStatus("Tracking: " .. item.name)
    if WowNote_ItemTracker_Refresh then WowNote_ItemTracker_Refresh() end
    if WowNote_ItemTracker_RefreshHud then WowNote_ItemTracker_RefreshHud() end
end

local function AddCursorItem()
    local cursorType, itemId, itemLink = GetCursorInfo()
    if cursorType ~= "item" then SetStatus("Drop an item here first."); return end
    ClearCursor()
    if not itemLink and itemId and GetItemInfo then itemLink = select(2, GetItemInfo(itemId)) end
    WowNote_ItemTracker_AddItem(itemLink, 0, 0)
end

local function SaveRow(row)
    local item = row.item
    if not item then return end
    item.threshold = tonumber(row.threshold:GetText()) or 0
    item.target = tonumber(row.target:GetText()) or item.threshold
    item.alert.enabled = row.alertEnabled:GetChecked() and true or false
    item.alert.text = row.textEnabled:GetChecked() and true or false
    item.alert.repeatEnabled = row.repeatEnabled:GetChecked() and true or false
    item.alert.repeatSeconds = tonumber(row.repeatSeconds:GetText()) or 300
    item.hud.enabled = row.hudEnabled:GetChecked() and true or false
    item.restock.enabled = row.restockEnabled:GetChecked() and true or false
    item.restock.autoBuy = row.autoBuy:GetChecked() and true or false
    if item.target < item.threshold then item.target = item.threshold end
end

local function SaveAllRows()
    for i = 1, table.getn(rows) do
        if rows[i]:IsShown() then SaveRow(rows[i]) end
    end
    SetStatus("Tracker settings saved.")
    WowNote_ItemTracker_Refresh()
    WowNote_ItemTracker_RefreshHud()
    WowNote_ItemTracker_Evaluate(true)
end

local function CreateRow(index)
    local row = rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, listFrame)
    row:SetWidth(710); row:SetHeight(60)
    row:EnableMouse(true)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(28); row.icon:SetHeight(28); row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0); row.name:SetWidth(145); row.name:SetJustifyH("LEFT")

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("LEFT", row.name, "RIGHT", 4, 0); row.count:SetWidth(54); row.count:SetJustifyH("LEFT")

    row.threshold = MakeEdit(row, 52); row.threshold.bg:SetPoint("LEFT", row.count, "RIGHT", 4, 0)
    row.target = MakeEdit(row, 52); row.target.bg:SetPoint("LEFT", row.threshold.bg, "RIGHT", 6, 0)
    row.mode = MakeButton(row, "Char", 64, 22); row.mode:SetPoint("LEFT", row.target.bg, "RIGHT", 6, 0)
    row.remove = MakeButton(row, "Remove", 66, 22); row.remove:SetPoint("LEFT", row.mode, "RIGHT", 8, 0)

    row.hudLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.hudLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -36); row.hudLabel:SetText("HUD")
    row.hudEnabled = MakeCheck(row); row.hudEnabled:SetPoint("LEFT", row.hudLabel, "RIGHT", 2, 0)

    row.alertLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.alertLabel:SetPoint("LEFT", row.hudEnabled, "RIGHT", 8, 0); row.alertLabel:SetText("Alert")
    row.alertEnabled = MakeCheck(row); row.alertEnabled:SetPoint("LEFT", row.alertLabel, "RIGHT", 2, 0)

    row.textLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.textLabel:SetPoint("LEFT", row.alertEnabled, "RIGHT", 8, 0); row.textLabel:SetText("Text")
    row.textEnabled = MakeCheck(row); row.textEnabled:SetPoint("LEFT", row.textLabel, "RIGHT", 2, 0)

    row.sound = MakeButton(row, "Sound", 102, 22); row.sound:SetPoint("LEFT", row.textEnabled, "RIGHT", 8, 0)

    row.repeatLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.repeatLabel:SetPoint("LEFT", row.sound, "RIGHT", 8, 0); row.repeatLabel:SetText("Repeat")
    row.repeatEnabled = MakeCheck(row); row.repeatEnabled:SetPoint("LEFT", row.repeatLabel, "RIGHT", 2, 0)
    row.repeatSeconds = MakeEdit(row, 44); row.repeatSeconds.bg:SetPoint("LEFT", row.repeatEnabled, "RIGHT", 2, 0)

    row.restockLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.restockLabel:SetPoint("LEFT", row.repeatSeconds.bg, "RIGHT", 8, 0); row.restockLabel:SetText("Restock")
    row.restockEnabled = MakeCheck(row); row.restockEnabled:SetPoint("LEFT", row.restockLabel, "RIGHT", 2, 0)

    row.autoLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.autoLabel:SetPoint("LEFT", row.restockEnabled, "RIGHT", 8, 0); row.autoLabel:SetText("Auto")
    row.autoBuy = MakeCheck(row); row.autoBuy:SetPoint("LEFT", row.autoLabel, "RIGHT", 2, 0)

    SetHelp(row.threshold.bg, "Minimum count", "Alert when the counted amount is below this value.")
    SetHelp(row.target.bg, "Target count", "Restock target. The restock assistant buys up to this amount when possible.")
    SetHelp(row.mode, "Count mode", "Char = count only the current character. Acct = count all saved account snapshots.")
    SetHelp(row.hudEnabled, "HUD", "Show this item in the movable tracker HUD.")
    SetHelp(row.alertEnabled, "Alert", "Enable or disable low-count alerts for this item.")
    SetHelp(row.textEnabled, "Text alert", "Show low-count warnings in chat and the error text area.")
    SetHelp(row.sound, "Alert sound", "Click to cycle the configured alert sound.")
    SetHelp(row.repeatEnabled, "Repeat alert", "Repeat the alert while the item remains below the minimum count.")
    SetHelp(row.repeatSeconds.bg, "Repeat seconds", "Delay in seconds between repeated low-count alerts.")
    SetHelp(row.restockEnabled, "Restock", "Show this item in the merchant restock assistant when it is below target.")
    SetHelp(row.autoBuy, "Auto-buy", "When enabled, the restock module may buy this item automatically at matching merchants, subject to safety limits.")

    row:SetScript("OnEnter", function(self)
        if self.item and self.item.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.item.link); GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.mode:SetScript("OnClick", function(self) ToggleMode(row.item); SaveAllRows() end)
    row.sound:SetScript("OnClick", function(self) CycleSound(row.item); SaveAllRows() end)
    row.remove:SetScript("OnClick", function(self)
        if row.item and row.item.itemId then WowNoteDB.itemTracker.trackedItems[row.item.itemId] = nil end
        WowNote_ItemTracker_Refresh(); WowNote_ItemTracker_RefreshHud()
    end)
    rows[index] = row
    return row
end

function WowNote_ItemTracker_Refresh()
    if not frame then return end
    InitDB()
    local items = SortedItems()
    for i = 1, table.getn(rows) do rows[i]:Hide() end
    for i = 1, table.getn(items) do
        local item = items[i]
        local row = CreateRow(i)
        row.item = item
        row.icon:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(item.name or tostring(item.itemId))
        row.count:SetText(tostring(CountItem(item)))
        row.threshold:SetText(tostring(item.threshold or 0))
        row.target:SetText(tostring(item.target or item.threshold or 0))
        row.mode:SetText(item.countMode == "account" and "Acct" or "Char")
        row.hudEnabled:SetChecked(item.hud and item.hud.enabled)
        row.alertEnabled:SetChecked(item.alert and item.alert.enabled)
        row.textEnabled:SetChecked(item.alert and item.alert.text)
        row.sound:SetText((sounds[item.alert.soundKey or "RAID_WARNING"] and sounds[item.alert.soundKey or "RAID_WARNING"].label) or "Sound")
        row.repeatEnabled:SetChecked(item.alert and item.alert.repeatEnabled)
        row.repeatSeconds:SetText(tostring((item.alert and item.alert.repeatSeconds) or 300))
        row.restockEnabled:SetChecked(item.restock and item.restock.enabled)
        row.autoBuy:SetChecked(item.restock and item.restock.autoBuy)
        row:ClearAllPoints()
        if i == 1 then row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, 0) else row:SetPoint("TOPLEFT", rows[i-1], "BOTTOMLEFT", 0, -6) end
        row:Show()
    end
    listFrame:SetHeight(math.max(356, table.getn(items) * 66))
end

local function SaveHudPosition()
    InitDB()
    local point, relativeTo, relativePoint, x, y = hudFrame:GetPoint(1)
    WowNoteDB.itemTracker.hud.point = point or "CENTER"
    WowNoteDB.itemTracker.hud.relativePoint = relativePoint or "CENTER"
    WowNoteDB.itemTracker.hud.x = x or 0
    WowNoteDB.itemTracker.hud.y = y or 0
end

local function ApplyHudPosition()
    InitDB()
    local cfg = WowNoteDB.itemTracker.hud
    hudFrame:ClearAllPoints()
    hudFrame:SetPoint(cfg.point or "CENTER", UIParent, cfg.relativePoint or "CENTER", cfg.x or 260, cfg.y or -80)
    hudFrame:SetScale(cfg.scale or 1.0)
end

local function CreateHud()
    if hudFrame then return end
    InitDB()
    hudFrame = CreateFrame("Frame", "WowNoteItemTrackerHud", UIParent)
    hudFrame:SetWidth(190); hudFrame:SetHeight(40)
    hudFrame:SetFrameStrata("HIGH")
    hudFrame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    hudFrame:SetBackdropColor(0,0,0,0.55)
    hudFrame:SetMovable(true); hudFrame:RegisterForDrag("LeftButton")
    hudFrame:SetScript("OnDragStart", function(self) if not WowNoteDB.itemTracker.hud.locked then self:StartMoving() end end)
    hudFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveHudPosition() end)
    ApplyHudPosition()
end


function WowNote_ItemTracker_SetHudShown(shown)
    InitDB(); CreateHud()
    WowNoteDB.itemTracker.hud.shown = shown and true or false
    WowNote_ItemTracker_RefreshHud()
    Print(WowNoteDB.itemTracker.hud.shown and "Tracker HUD shown." or "Tracker HUD hidden.")
end

function WowNote_ItemTracker_SetHudLocked(locked)
    InitDB(); CreateHud()
    WowNoteDB.itemTracker.hud.locked = locked and true or false
    hudFrame:EnableMouse(not WowNoteDB.itemTracker.hud.locked)
    if WowNoteDB.itemTracker.hud.locked then
        hudFrame:SetBackdropColor(0,0,0,0.25)
        Print("Tracker HUD locked.")
    else
        hudFrame:SetBackdropColor(0,0,0,0.85)
        Print("Tracker HUD unlocked. Drag it with the left mouse button.")
    end
end

function WowNote_ItemTracker_RefreshHud()
    InitDB(); CreateHud()
    local cfg = WowNoteDB.itemTracker.hud
    if not cfg.shown then hudFrame:Hide(); return end
    ApplyHudPosition()
    hudFrame:EnableMouse(not cfg.locked)
    local items = SortedItems()
    local visible = 0
    for i = 1, table.getn(hudRows) do hudRows[i]:Hide() end
    for i = 1, table.getn(items) do
        local item = items[i]
        if item.hud and item.hud.enabled then
            visible = visible + 1
            local row = hudRows[visible]
            if not row then
                row = CreateFrame("Frame", nil, hudFrame)
                row:SetWidth(180); row:SetHeight(24)
                row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetWidth(20); row.icon:SetHeight(20); row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0); row.text:SetWidth(145); row.text:SetJustifyH("LEFT")
                hudRows[visible] = row
            end
            local count = CountItem(item)
            row.icon:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            local color = count < (item.threshold or 0) and "|cffff5555" or "|cffdddddd"
            row.text:SetText(color .. (item.name or tostring(item.itemId)) .. ": " .. tostring(count) .. " / " .. tostring(item.target or item.threshold or 0) .. "|r")
            row:ClearAllPoints()
            if visible == 1 then row:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 5, -5) else row:SetPoint("TOPLEFT", hudRows[visible-1], "BOTTOMLEFT", 0, -2) end
            row:Show()
        end
    end
    hudFrame:SetHeight(math.max(32, visible * 26 + 10))
    if visible > 0 then hudFrame:Show() else hudFrame:Hide() end
end

local function FireAlert(item, count, force)
    EnsureItemDefaults(item)
    if not item.alert.enabled then return end
    local now = GetTime and GetTime() or 0
    if not force then
        if not item.alert.repeatEnabled and item.alert.firedLow then return end
        if item.alert.repeatEnabled and item.alert.lastAlertAt and now - item.alert.lastAlertAt < (item.alert.repeatSeconds or 300) then return end
    end
    item.alert.lastAlertAt = now
    item.alert.firedLow = true
    local msg = (item.name or tostring(item.itemId)) .. " low: " .. tostring(count) .. " / " .. tostring(item.threshold or 0)
    if item.alert.text then
        Print(msg)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage("WowNote: " .. msg, 1, 0.2, 0.2, 1.0) end
    end
    if item.alert.sound and item.alert.soundKey and sounds[item.alert.soundKey] and sounds[item.alert.soundKey].file then
        PlaySoundFile(sounds[item.alert.soundKey].file)
    end
end

function WowNote_ItemTracker_Evaluate(force)
    InitDB()
    for _, item in pairs(WowNoteDB.itemTracker.trackedItems) do
        if type(item) == "table" then
            EnsureItemDefaults(item)
            local count = CountItem(item)
            if count < (tonumber(item.threshold) or 0) then
                FireAlert(item, count, force)
            else
                if item.alert then item.alert.firedLow = false end
            end
        end
    end
    if WowNote_ItemTracker_RefreshHud then WowNote_ItemTracker_RefreshHud() end
    if WowNote_Restock_CheckMerchant then WowNote_Restock_CheckMerchant() end
end

local function CreateUI()
    if frame then return end
    frame = CreateFrame("Frame", "WowNoteItemTrackerFrame", UIParent)
    frame:SetWidth(820); frame:SetHeight(560); frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); if frame.SetToplevel then frame:SetToplevel(true) end
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    frame:Hide()
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -18); title:SetText("WowNote Item Tracker")
    dropButton = MakeButton(frame, "Drop/Add Cursor Item", 160, 24); dropButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -48); dropButton:SetScript("OnClick", AddCursorItem)
    local save = MakeButton(frame, "Save", 70, 24); save:SetPoint("LEFT", dropButton, "RIGHT", 8, 0); save:SetScript("OnClick", SaveAllRows)
    local eval = MakeButton(frame, "Test Alert", 82, 24); eval:SetPoint("LEFT", save, "RIGHT", 8, 0); eval:SetScript("OnClick", function() WowNote_ItemTracker_Evaluate(true) end)
    local bank = MakeButton(frame, "Bank", 70, 24); bank:SetPoint("LEFT", eval, "RIGHT", 8, 0); bank:SetScript("OnClick", function() if WowNote_OpenBankViewer then WowNote_OpenBankViewer() end end)
    local restock = MakeButton(frame, "Restock", 80, 24); restock:SetPoint("LEFT", bank, "RIGHT", 8, 0); restock:SetScript("OnClick", function() if WowNote_OpenRestock then WowNote_OpenRestock() end end)
    local help = MakeButton(frame, "Help", 60, 24); help:SetPoint("LEFT", restock, "RIGHT", 8, 0); help:SetScript("OnClick", function() if WowNote_PrintHelp then WowNote_PrintHelp() end end)

    local lock = MakeButton(frame, "Lock HUD", 80, 24); lock:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -78); lock:SetScript("OnClick", function() WowNote_ItemTracker_SetHudLocked(true) end)
    local unlock = MakeButton(frame, "Unlock HUD", 90, 24); unlock:SetPoint("LEFT", lock, "RIGHT", 8, 0); unlock:SetScript("OnClick", function() WowNote_ItemTracker_SetHudLocked(false) end)
    local showHud = MakeButton(frame, "Show HUD", 80, 24); showHud:SetPoint("LEFT", unlock, "RIGHT", 8, 0); showHud:SetScript("OnClick", function() WowNote_ItemTracker_SetHudShown(true) end)
    local hideHud = MakeButton(frame, "Hide HUD", 80, 24); hideHud:SetPoint("LEFT", showHud, "RIGHT", 8, 0); hideHud:SetScript("OnClick", function() WowNote_ItemTracker_SetHudShown(false) end)

    SetHelp(dropButton, "Drop/Add Cursor Item", "Pick up an item with the cursor, then click this button to track it.")
    SetHelp(save, "Save", "Save all visible tracker settings.")
    SetHelp(eval, "Test Alert", "Force a test evaluation of low-count alerts.")
    SetHelp(bank, "Bank", "Open the account bank snapshot viewer.")
    SetHelp(restock, "Restock", "Open the merchant restock assistant.")
    SetHelp(help, "Help", "Print all WowNote slash commands to chat.")
    SetHelp(lock, "Lock HUD", "Freeze the tracker HUD position.")
    SetHelp(unlock, "Unlock HUD", "Allow dragging the tracker HUD.")
    SetHelp(showHud, "Show HUD", "Show the tracker HUD.")
    SetHelp(hideHud, "Hide HUD", "Hide the tracker HUD.")

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -108)
    header:SetText("Item                         Count     Min     Target   Mode       Remove")
    local header2 = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header2:SetPoint("TOPLEFT", frame, "TOPLEFT", 52, -121)
    header2:SetText("Second row: HUD, alert, text, sound, repeat interval, restock and auto-buy")

    local bg = CreateFrame("Frame", nil, frame)
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -132); bg:SetWidth(770); bg:SetHeight(368)
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    bg:SetBackdropColor(0,0,0,0.72)
    local scroll = CreateFrame("ScrollFrame", "WowNoteItemTrackerScrollFrame", bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", bg, "TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -28, 8)
    listFrame = CreateFrame("Frame", nil, scroll); listFrame:SetWidth(720); listFrame:SetHeight(356)
    scroll:SetScrollChild(listFrame)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 18); statusText:SetWidth(760); statusText:SetJustifyH("LEFT"); statusText:SetText("Ready")
    frame:SetScript("OnShow", function() WowNote_ItemTracker_Refresh() end)
end

function WowNote_OpenItemTracker()
    InitDB(); CreateUI(); CreateHud(); frame:Show(); if WowNote_Internal and WowNote_Internal.RaiseFrame then WowNote_Internal.RaiseFrame(frame) end; WowNote_ItemTracker_Refresh(); WowNote_ItemTracker_RefreshHud()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    InitDB(); CreateHud(); WowNote_ItemTracker_RefreshHud(); WowNote_ItemTracker_Evaluate(false)
end)
