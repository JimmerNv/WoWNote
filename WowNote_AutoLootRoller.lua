local MODULE_NAME = "WowNote Auto Loot Roller"

local frame
local eventFrame
local statusText
local enabledCheck
local preferDisenchantCheck
local useMaxItemLevelCheck
local qualityButton
local minPlayerLevelEdit
local maxItemLevelEdit
local blacklistEdit
local pendingRolls = {}
local rollQueue = {}
local tooltipScanner
local tooltipLines = {}
local textAreaCounter = 0

local QUALITY_NAMES = {
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
}

local QUALITY_VALUES = {2, 3, 4}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg))
end

local function Trim(text)
    text = text or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function EnsureDB()
    if type(WowNoteCharDB) ~= "table" then
        WowNoteCharDB = {}
    end
    if type(WowNoteCharDB.autoLootRoller) ~= "table" then
        WowNoteCharDB.autoLootRoller = {}
    end

    local settings = WowNoteCharDB.autoLootRoller
    if settings.enabled == nil then settings.enabled = false end
    if settings.quality == nil then settings.quality = 2 end
    if settings.minPlayerLevel == nil then settings.minPlayerLevel = 80 end
    if settings.useMaxItemLevel == nil then settings.useMaxItemLevel = true end
    if settings.maxItemLevel == nil then settings.maxItemLevel = 220 end
    if settings.preferDisenchant == nil then settings.preferDisenchant = true end
    if settings.blacklist == nil then settings.blacklist = "" end
    return settings
end

local function SetStatus(text)
    if statusText then
        statusText:SetText(text or "")
    end
end

local function ToNumber(value, fallback)
    local numberValue = tonumber(Trim(value))
    if not numberValue then
        return fallback
    end
    return numberValue
end

local function UpdateControlsFromSettings()
    if not frame then return end
    local settings = EnsureDB()

    if enabledCheck then enabledCheck:SetChecked(settings.enabled and true or false) end
    if preferDisenchantCheck then preferDisenchantCheck:SetChecked(settings.preferDisenchant and true or false) end
    if useMaxItemLevelCheck then useMaxItemLevelCheck:SetChecked(settings.useMaxItemLevel and true or false) end
    if qualityButton then qualityButton:SetText("Max rarity: " .. (QUALITY_NAMES[settings.quality] or "Uncommon")) end
    if minPlayerLevelEdit then minPlayerLevelEdit:SetText(tostring(settings.minPlayerLevel or 80)) end
    if maxItemLevelEdit then maxItemLevelEdit:SetText(tostring(settings.maxItemLevel or 220)) end
    if blacklistEdit then blacklistEdit:SetText(tostring(settings.blacklist or "")) end

    local enabledText = settings.enabled and "enabled" or "disabled"
    SetStatus("Auto loot roller is " .. enabledText .. ".")
end

local function SaveControlsToSettings()
    local settings = EnsureDB()
    if enabledCheck then settings.enabled = enabledCheck:GetChecked() and true or false end
    if preferDisenchantCheck then settings.preferDisenchant = preferDisenchantCheck:GetChecked() and true or false end
    if useMaxItemLevelCheck then settings.useMaxItemLevel = useMaxItemLevelCheck:GetChecked() and true or false end
    if minPlayerLevelEdit then settings.minPlayerLevel = ToNumber(minPlayerLevelEdit:GetText(), 80) end
    if maxItemLevelEdit then settings.maxItemLevel = ToNumber(maxItemLevelEdit:GetText(), 220) end
    if blacklistEdit then settings.blacklist = blacklistEdit:GetText() or "" end
    UpdateControlsFromSettings()
end

local function RaiseFrame(target)
    if not target then return end
    target:SetFrameStrata("FULLSCREEN_DIALOG")
    target:SetFrameLevel(100)
    target:SetToplevel(true)
    if target.Raise then
        target:Raise()
    end
end

local function MakeLabel(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function MakeEdit(parent, width, height, x, y)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, height)
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); SaveControlsToSettings() end)
    edit:SetScript("OnEditFocusLost", function() SaveControlsToSettings() end)
    return edit
end


local function MakeTextArea(parent, width, height, x, y)
    local bg = CreateFrame("Frame", nil, parent)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bg:SetSize(width, height)
    bg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    bg:SetBackdropColor(0, 0, 0, 0.85)

    textAreaCounter = textAreaCounter + 1
    local scroll = CreateFrame("ScrollFrame", "WowNoteAutoLootTextAreaScroll" .. textAreaCounter, bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -28, 4)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(width - 36)
    edit:SetHeight(height * 2)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); SaveControlsToSettings() end)
    edit:SetScript("OnEditFocusLost", function() SaveControlsToSettings() end)
    edit:SetScript("OnCursorChanged", function(self, cx, cy, cw, ch)
        if ScrollingEdit_OnCursorChanged then
            ScrollingEdit_OnCursorChanged(self, cx, cy, cw, ch)
        end
    end)
    edit:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then
            ScrollingEdit_OnUpdate(self, elapsed, self:GetParent())
        end
    end)
    edit:SetScript("OnTextChanged", function(self)
        if ScrollingEdit_OnTextChanged then
            ScrollingEdit_OnTextChanged(self, self:GetParent())
        end
    end)
    scroll:SetScrollChild(edit)
    return edit
end

local function MakeButton(parent, text, width, height, x, y)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    return button
end

local function MakeCheck(parent, text, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check.text = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check.text:SetPoint("LEFT", check, "RIGHT", -2, 0)
    check.text:SetText(text)
    check:SetScript("OnClick", SaveControlsToSettings)
    return check
end

local function CycleQuality()
    local settings = EnsureDB()
    local current = settings.quality or 2
    local nextValue = QUALITY_VALUES[1]
    for index, value in ipairs(QUALITY_VALUES) do
        if value == current then
            nextValue = QUALITY_VALUES[index + 1] or QUALITY_VALUES[1]
            break
        end
    end
    settings.quality = nextValue
    UpdateControlsFromSettings()
end


local function ExtractItemId(itemLink)
    if not itemLink then return nil end
    return tonumber(string.match(itemLink, "item:(%d+):"))
end

local function EnsureTooltipScanner()
    if tooltipScanner then return tooltipScanner end
    tooltipScanner = CreateFrame("GameTooltip", "WowNoteAutoLootTooltipScanner", UIParent, "GameTooltipTemplate")
    tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")
    for index = 1, 12 do
        tooltipLines[index] = _G["WowNoteAutoLootTooltipScannerTextLeft" .. index]
    end
    return tooltipScanner
end

local function IsBindOnEquip(itemLink)
    if not itemLink then return false end
    local scanner = EnsureTooltipScanner()
    scanner:ClearLines()
    scanner:SetHyperlink(itemLink)

    local boeText = ITEM_BIND_ON_EQUIP or "Binds when equipped"
    for index = 1, scanner:NumLines() do
        local line = tooltipLines[index]
        local text = line and line:GetText()
        if text and text == boeText then
            return true
        end
    end
    return false
end

local function IsPrimordialSaronite(item)
    if not item then return false end
    local itemId = ExtractItemId(item.link)
    if itemId == 49908 then
        return true
    end

    local itemName = string.lower(item.name or "")
    return itemName == "primordial saronite"
end

local function IsAlwaysExcluded(item)
    if not item then return false end

    if IsPrimordialSaronite(item) then
        return true, "Primordial Saronite is always excluded"
    end

    if tonumber(item.quality) == 4 and IsBindOnEquip(item.link) then
        return true, "Epic bind-on-equip items are always excluded"
    end

    return false
end


local function IsBlacklisted(item)
    if not item then return false end
    local settings = EnsureDB()
    local blacklist = settings.blacklist or ""
    if Trim(blacklist) == "" then return false end

    local itemName = string.lower(Trim(item.name or ""))
    local itemId = ExtractItemId(item.link)

    for rawLine in string.gmatch(blacklist .. "\n", "(.-)\n") do
        local entry = string.lower(Trim(rawLine or ""))
        entry = string.gsub(entry, "^%-+%s*", "")
        if entry ~= "" then
            local numeric = tonumber(entry)
            if numeric and itemId and numeric == itemId then
                return true, "blacklisted item ID " .. tostring(numeric)
            end
            if itemName ~= "" and itemName == entry then
                return true, "blacklisted item name"
            end
        end
    end

    return false
end

local function GetRollItemData(rollID)
    local texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    local link = GetLootRollItemLink and GetLootRollItemLink(rollID) or nil
    local itemName, itemLink, itemQuality, itemLevel, requiredLevel

    if link then
        itemName, itemLink, itemQuality, itemLevel, requiredLevel = GetItemInfo(link)
    end

    return {
        name = itemName or name,
        link = itemLink or link,
        quality = itemQuality or quality,
        itemLevel = itemLevel,
        requiredLevel = requiredLevel,
        canGreed = canGreed,
        canDisenchant = canDisenchant,
    }
end

local function RollTypeName(rollType)
    if rollType == 3 then return "Disenchant" end
    if rollType == 2 then return "Greed" end
    if rollType == 1 then return "Need" end
    return "Pass"
end

local function RemoveQueuedRoll(rollID)
    pendingRolls[rollID] = nil
    for index = #rollQueue, 1, -1 do
        if rollQueue[index] == rollID then
            table.remove(rollQueue, index)
        end
    end

    local nextRollID = rollQueue[1]
    if nextRollID and pendingRolls[nextRollID] then
        pendingRolls[nextRollID].timeLeft = math.max(pendingRolls[nextRollID].timeLeft or 0, 0.65)
    end
end

local function ConfirmAutoRoll(rollID, rollType)
    if ConfirmLootRoll then
        pcall(ConfirmLootRoll, rollID, rollType)
    end

    local accepted = false
    for index = 1, 4 do
        local popup = _G["StaticPopup" .. index]
        local button = _G["StaticPopup" .. index .. "Button1"]
        if popup and button and popup:IsShown() then
            local which = popup.which
            if which == "CONFIRM_LOOT_ROLL" or which == "CONFIRM_DISENCHANT_ROLL" then
                local data = popup.data
                if data == rollID or data == nil then
                    button:Click()
                    accepted = true
                end
            end
        end
    end
    return accepted
end

local function EvaluateRoll(rollID, attempt)
    local settings = EnsureDB()
    if not settings.enabled then return true end

    local playerLevel = UnitLevel and UnitLevel("player") or 0
    if playerLevel < (settings.minPlayerLevel or 80) then
        return true
    end

    local item = GetRollItemData(rollID)
    if not item.name or not item.quality then
        return false
    end

    if settings.useMaxItemLevel and not item.itemLevel and (attempt or 1) < 8 then
        return false
    end

    local excluded, reason = IsAlwaysExcluded(item)
    if excluded then
        if attempt == 1 then
            Print("Auto roll skipped " .. (item.link or item.name or "loot") .. ": " .. reason .. ".")
        end
        return true
    end

    local blacklisted, blacklistReason = IsBlacklisted(item)
    if blacklisted then
        if attempt == 1 then
            Print("Auto roll skipped " .. (item.link or item.name or "loot") .. ": " .. blacklistReason .. ".")
        end
        return true
    end

    local maxQuality = tonumber(settings.quality) or 2
    if item.quality > maxQuality then
        return true
    end

    if settings.useMaxItemLevel then
        local maxItemLevel = tonumber(settings.maxItemLevel) or 220
        if not item.itemLevel or item.itemLevel > maxItemLevel then
            return true
        end
    end

    local rollType
    if settings.preferDisenchant and item.canDisenchant then
        rollType = 3
    elseif item.canGreed then
        rollType = 2
    end

    if rollType and RollOnLoot then
        RollOnLoot(rollID, rollType)
        ConfirmAutoRoll(rollID, rollType)
        Print("Auto rolled " .. RollTypeName(rollType) .. " on " .. (item.link or item.name or "loot") .. ".")
    end

    return true
end

local function QueueRoll(rollID)
    if pendingRolls[rollID] then
        return
    end

    pendingRolls[rollID] = {
        timeLeft = 0.25,
        attempt = 1,
    }
    table.insert(rollQueue, rollID)

    if eventFrame then
        eventFrame:Show()
    end
end

local function ProcessPendingRolls(elapsed)
    local rollID = rollQueue[1]
    if not rollID then
        if eventFrame then eventFrame:Hide() end
        return
    end

    local state = pendingRolls[rollID]
    if not state then
        table.remove(rollQueue, 1)
        return
    end

    state.timeLeft = (state.timeLeft or 0) - elapsed
    if state.timeLeft > 0 then
        return
    end

    local done = EvaluateRoll(rollID, state.attempt or 1)
    if done or (state.attempt or 1) >= 10 then
        RemoveQueuedRoll(rollID)
    else
        state.attempt = (state.attempt or 1) + 1
        state.timeLeft = 0.35
    end

    if not next(pendingRolls) and eventFrame then
        eventFrame:Hide()
    end
end

local function CreateAutoLootRollerUI()
    if frame then return end

    frame = CreateFrame("Frame", "WowNoteAutoLootRollerFrame", UIParent)
    frame:SetSize(470, 405)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("WowNote Auto Loot Roller")

    local charText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    charText:SetPoint("TOP", frame, "TOP", 0, -34)
    charText:SetText("Settings are saved per character.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    enabledCheck = MakeCheck(frame, "Enable auto roll", 24, -48)
    preferDisenchantCheck = MakeCheck(frame, "Prefer Disenchant if available", 24, -78)
    useMaxItemLevelCheck = MakeCheck(frame, "Use max item level", 24, -108)

    local excludeText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    excludeText:SetPoint("TOPLEFT", frame, "TOPLEFT", 42, -132)
    excludeText:SetText("Always excluded: Epic BoE items and Primordial Saronite")

    MakeLabel(frame, "Only if player level >=", 42, -158)
    minPlayerLevelEdit = MakeEdit(frame, 55, 22, 190, -153)

    MakeLabel(frame, "Max item level", 42, -190)
    maxItemLevelEdit = MakeEdit(frame, 55, 22, 190, -185)

    MakeLabel(frame, "Blacklist (one item name or item ID per line)", 42, -222)
    blacklistEdit = MakeTextArea(frame, 390, 80, 42, -240)

    qualityButton = MakeButton(frame, "Max rarity: Uncommon", 180, 24, 42, -330)
    qualityButton:SetScript("OnClick", CycleQuality)
    qualityButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Max rarity to auto-roll", 1, 1, 1)
        GameTooltip:AddLine("Items with a higher rarity are ignored.", nil, nil, nil, true)
        GameTooltip:AddLine("Example: Uncommon + item level 220 rolls on items up to Uncommon and item level <= 220.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    qualityButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local testButton = MakeButton(frame, "Save", 70, 24, 240, -330)
    testButton:SetScript("OnClick", SaveControlsToSettings)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 16)
    statusText:SetText("Ready")

    frame:Hide()
end

function WowNote_OpenAutoLootRoller()
    CreateAutoLootRollerUI()
    UpdateControlsFromSettings()
    frame:Show()
    RaiseFrame(frame)
end

function WowNote_ToggleAutoLootRoller()
    local settings = EnsureDB()
    settings.enabled = not settings.enabled
    Print("Auto loot roller " .. (settings.enabled and "enabled" or "disabled") .. ".")
    UpdateControlsFromSettings()
end

local function RegisterEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("START_LOOT_ROLL")
    eventFrame:RegisterEvent("CANCEL_LOOT_ROLL")
    eventFrame:SetScript("OnEvent", function(self, event, rollID)
        if event == "START_LOOT_ROLL" and rollID then
            QueueRoll(rollID)
        elseif event == "CANCEL_LOOT_ROLL" and rollID then
            RemoveQueuedRoll(rollID)
        end
    end)
    eventFrame:SetScript("OnUpdate", function(self, elapsed)
        ProcessPendingRolls(elapsed or 0)
    end)
    eventFrame:Hide()
end

EnsureDB()
RegisterEvents()
