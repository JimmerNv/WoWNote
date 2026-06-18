local MODULE_NAME = "WowNote Loot Tools"

local frame
local statusText
local activeTab = "roll"
local tabs = {}
local panels = {}
local controls = {}
local SELL_QUALITY_NAMES = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }
local SELL_QUALITY_VALUES = { 0, 1, 2, 3, 4 }
local QUICK_ADD_MODIFIERS = { "ALT", "CTRL", "SHIFT" }
local QUICK_ADD_MODIFIER_NAMES = { ALT = "Alt-click", CTRL = "Ctrl-click", SHIFT = "Shift-click" }
local QUICK_ADD_TARGET_NAMES = { force = "Force Sell", never = "Never Sell" }
local textAreaCounter = 0
local activeTextArea = nil
local linkHookInstalled = false

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

local function ToNumber(value, fallback)
    local n = tonumber(Trim(value))
    if n == nil then return fallback end
    return n
end

local function EnsureRollDB()
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.autoLootRoller) ~= "table" then WowNoteCharDB.autoLootRoller = {} end
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

local function EnsureVendorDB()
    if WowNote_GetAutoVendorSettings then
        return WowNote_GetAutoVendorSettings()
    end
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.autoVendor) ~= "table" then WowNoteCharDB.autoVendor = {} end
    return WowNoteCharDB.autoVendor
end

local function SetStatus(text)
    if statusText then statusText:SetText(text or "") end
end

local function RaiseFrame(target)
    if not target then return end
    if WowNote_Internal and WowNote_Internal.RaiseFrame then
        WowNote_Internal.RaiseFrame(target)
        return
    end
    target:SetFrameStrata("FULLSCREEN_DIALOG")
    target:SetFrameLevel(100)
    target:SetToplevel(true)
    if target.Raise then target:Raise() end
end

local function RaiseChild(child, parent, offset)
    if child and parent and parent.GetFrameLevel then
        child:SetFrameLevel((parent:GetFrameLevel() or 100) + (offset or 1))
    end
    return child
end

local function MakeButton(parent, text, width, height, x, y)
    local button = RaiseChild(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"), parent, 5)
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    return button
end

local function MakeLabel(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function MakeSmallText(parent, text, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width or 420)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function MakeEdit(parent, width, height, x, y, numeric)
    local edit = RaiseChild(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"), parent, 5)
    edit:SetSize(width, height)
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    edit:SetAutoFocus(false)
    if numeric then edit:SetNumeric(true) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); WowNote_LootTools_SaveActiveTab() end)
    edit:SetScript("OnEditFocusLost", function() WowNote_LootTools_SaveActiveTab() end)
    return edit
end


local function EnsureTextAreaLinkHook()
    if linkHookInstalled then return end
    linkHookInstalled = true

    local originalInsertLink = ChatEdit_InsertLink
    if type(originalInsertLink) == "function" then
        ChatEdit_InsertLink = function(link)
            if activeTextArea and activeTextArea:IsVisible() and activeTextArea:HasFocus() then
                activeTextArea:Insert(link)
                return true
            end
            return originalInsertLink(link)
        end
    end
end

local function MakeTextArea(parent, width, height, x, y)
    EnsureTextAreaLinkHook()

    local bg = RaiseChild(CreateFrame("Frame", nil, parent), parent, 4)
    bg:EnableMouse(true)
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
    local scroll = RaiseChild(CreateFrame("ScrollFrame", "WowNoteLootToolsTextAreaScroll" .. textAreaCounter, bg, "UIPanelScrollFrameTemplate"), bg, 2)
    scroll:EnableMouse(true)
    scroll:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -28, 4)

    local edit = RaiseChild(CreateFrame("EditBox", "WowNoteLootToolsTextAreaEdit" .. textAreaCounter, scroll), scroll, 2)
    edit:EnableMouse(true)
    edit:EnableKeyboard(true)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(width - 36)
    edit:SetHeight(height * 2)
    edit:SetMaxLetters(0)

    local function FocusEdit()
        edit:SetFocus()
        activeTextArea = edit
    end

    bg:SetScript("OnMouseDown", FocusEdit)
    scroll:SetScript("OnMouseDown", FocusEdit)
    edit:SetScript("OnMouseDown", function(self)
        self:SetFocus()
        activeTextArea = self
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        activeTextArea = self
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        WowNote_LootTools_SaveActiveTab()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if activeTextArea == self then activeTextArea = nil end
        WowNote_LootTools_SaveActiveTab()
    end)
    edit:SetScript("OnCursorChanged", function(self, cx, cy, cw, ch)
        if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, cx, cy, cw, ch) end
    end)
    WowNoteProfiler_SetScript(edit, "OnUpdate", "LootTools.EditBox", function(self, elapsed)
        if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, self:GetParent()) end
    end)
    edit:SetScript("OnTextChanged", function(self)
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, self:GetParent()) end
    end)
    scroll:SetScrollChild(edit)
    return edit
end

local function MakeCheck(parent, text, x, y)
    local check = RaiseChild(CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"), parent, 5)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check.text = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check.text:SetPoint("LEFT", check, "RIGHT", -2, 0)
    check.text:SetText(text)
    check:SetScript("OnClick", function() WowNote_LootTools_SaveActiveTab() end)
    return check
end

local function SaveRollControls()
    local settings = EnsureRollDB()
    if controls.rollEnabled then settings.enabled = controls.rollEnabled:GetChecked() and true or false end
    if controls.rollPreferDE then settings.preferDisenchant = controls.rollPreferDE:GetChecked() and true or false end
    if controls.rollUseIlvl then settings.useMaxItemLevel = controls.rollUseIlvl:GetChecked() and true or false end
    if controls.rollMinLevel then settings.minPlayerLevel = ToNumber(controls.rollMinLevel:GetText(), 80) end
    if controls.rollMaxIlvl then settings.maxItemLevel = ToNumber(controls.rollMaxIlvl:GetText(), 220) end
    if controls.rollBlacklist then settings.blacklist = controls.rollBlacklist:GetText() or "" end
    SetStatus("Auto Roll settings saved for this character.")
end

local function SaveSellControls()
    local values = {
        sellEnabled = controls.sellEnabled and controls.sellEnabled:GetChecked() and true or false,
        sellGray = controls.sellGray and controls.sellGray:GetChecked() and true or false,
        sellWeapons = controls.sellWeapons and controls.sellWeapons:GetChecked() and true or false,
        sellArmor = controls.sellArmor and controls.sellArmor:GetChecked() and true or false,
        sellEquipmentMaxQuality = controls.sellEquipmentQualityValue or 1,
        useEquipmentMaxItemLevel = controls.sellUseIlvl and controls.sellUseIlvl:GetChecked() and true or false,
        equipmentMaxItemLevel = ToNumber(controls.sellMaxIlvl and controls.sellMaxIlvl:GetText(), 200),
        printSellSummary = controls.sellSummary and controls.sellSummary:GetChecked() and true or false,
        quickAddEnabled = controls.quickAddEnabled and controls.quickAddEnabled:GetChecked() and true or false,
        quickAddModifier = controls.quickAddModifierValue or "ALT",
        quickAddTarget = controls.quickAddTargetValue or "force",
        forceSell = controls.forceSell and controls.forceSell:GetText() or "",
        neverSell = controls.neverSell and controls.neverSell:GetText() or "",
    }
    if WowNote_NormalizeAutoVendorList then
        values.forceSell = WowNote_NormalizeAutoVendorList(values.forceSell)
        values.neverSell = WowNote_NormalizeAutoVendorList(values.neverSell)
    end
    if WowNote_SaveAutoVendorSettings then WowNote_SaveAutoVendorSettings(values) end
    if controls.forceSell then controls.forceSell:SetText(values.forceSell or "") end
    if controls.neverSell then controls.neverSell:SetText(values.neverSell or "") end
    SetStatus("Auto Sell settings saved and lists sorted for this character.")
end

local function SaveRepairControls()
    local values = {
        repairEnabled = controls.repairEnabled and controls.repairEnabled:GetChecked() and true or false,
        repairGuild = controls.repairGuild and controls.repairGuild:GetChecked() and true or false,
        printRepairSummary = controls.repairSummary and controls.repairSummary:GetChecked() and true or false,
    }
    if WowNote_SaveAutoVendorSettings then WowNote_SaveAutoVendorSettings(values) end
    SetStatus("Auto Repair settings saved for this character.")
end

function WowNote_LootTools_SaveActiveTab()
    if activeTab == "roll" then SaveRollControls()
    elseif activeTab == "sell" then SaveSellControls()
    elseif activeTab == "repair" then SaveRepairControls()
    end
end

local function UpdateRollControls()
    local settings = EnsureRollDB()
    if controls.rollEnabled then controls.rollEnabled:SetChecked(settings.enabled and true or false) end
    if controls.rollPreferDE then controls.rollPreferDE:SetChecked(settings.preferDisenchant and true or false) end
    if controls.rollUseIlvl then controls.rollUseIlvl:SetChecked(settings.useMaxItemLevel and true or false) end
    if controls.rollMinLevel then controls.rollMinLevel:SetText(tostring(settings.minPlayerLevel or 80)) end
    if controls.rollMaxIlvl then controls.rollMaxIlvl:SetText(tostring(settings.maxItemLevel or 220)) end
    if controls.rollBlacklist then controls.rollBlacklist:SetText(tostring(settings.blacklist or "")) end
    if controls.rollQuality then controls.rollQuality:SetText("Max rarity: " .. (QUALITY_NAMES[settings.quality] or "Uncommon")) end
end

local function UpdateSellControls()
    local settings = EnsureVendorDB()
    if controls.sellEnabled then controls.sellEnabled:SetChecked(settings.sellEnabled and true or false) end
    if controls.sellGray then controls.sellGray:SetChecked(settings.sellGray and true or false) end
    if controls.sellWeapons then controls.sellWeapons:SetChecked(settings.sellWeapons and true or false) end
    if controls.sellArmor then controls.sellArmor:SetChecked(settings.sellArmor and true or false) end
    controls.sellEquipmentQualityValue = tonumber(settings.sellEquipmentMaxQuality) or 1
    if controls.sellEquipmentQuality then controls.sellEquipmentQuality:SetText("Max equipment rarity: " .. (SELL_QUALITY_NAMES[controls.sellEquipmentQualityValue] or "Common")) end
    if controls.sellUseIlvl then controls.sellUseIlvl:SetChecked(settings.useEquipmentMaxItemLevel and true or false) end
    if controls.sellMaxIlvl then controls.sellMaxIlvl:SetText(tostring(settings.equipmentMaxItemLevel or 200)) end
    if controls.sellSummary then controls.sellSummary:SetChecked(settings.printSellSummary and true or false) end
    if controls.quickAddEnabled then controls.quickAddEnabled:SetChecked(settings.quickAddEnabled and true or false) end
    controls.quickAddModifierValue = settings.quickAddModifier or "ALT"
    controls.quickAddTargetValue = settings.quickAddTarget or "force"
    if controls.quickAddModifier then controls.quickAddModifier:SetText("Quick add modifier: " .. (QUICK_ADD_MODIFIER_NAMES[controls.quickAddModifierValue] or "Alt-click")) end
    if controls.quickAddTarget then controls.quickAddTarget:SetText("Quick add target: " .. (QUICK_ADD_TARGET_NAMES[controls.quickAddTargetValue] or "Force Sell")) end
    if controls.forceSell then controls.forceSell:SetText(tostring(settings.forceSell or "")) end
    if controls.neverSell then controls.neverSell:SetText(tostring(settings.neverSell or "")) end
end

local function UpdateRepairControls()
    local settings = EnsureVendorDB()
    if controls.repairEnabled then controls.repairEnabled:SetChecked(settings.repairEnabled and true or false) end
    if controls.repairGuild then controls.repairGuild:SetChecked(settings.repairGuild and true or false) end
    if controls.repairSummary then controls.repairSummary:SetChecked(settings.printRepairSummary and true or false) end
end

local function CycleQuality()
    local settings = EnsureRollDB()
    local current = settings.quality or 2
    local nextValue = QUALITY_VALUES[1]
    for index, value in ipairs(QUALITY_VALUES) do
        if value == current then
            nextValue = QUALITY_VALUES[index + 1] or QUALITY_VALUES[1]
            break
        end
    end
    settings.quality = nextValue
    UpdateRollControls()
    SaveRollControls()
end

local function SelectTab(tabName)
    WowNote_LootTools_SaveActiveTab()
    activeTab = tabName
    for name, panel in pairs(panels) do
        if name == tabName then panel:Show() else panel:Hide() end
    end
    for name, button in pairs(tabs) do
        button:Enable()
        if button.UnlockHighlight then button:UnlockHighlight() end
        if name == tabName and button.LockHighlight then button:LockHighlight() end
    end
    UpdateRollControls()
    UpdateSellControls()
    UpdateRepairControls()
    SetStatus("Settings are saved per character.")
end

local function CreateRollPanel(parent)
    local panel = RaiseChild(CreateFrame("Frame", nil, parent), parent, 2)
    panel:EnableMouse(true)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    controls.rollEnabled = MakeCheck(panel, "Enable auto roll", 22, -10)
    controls.rollPreferDE = MakeCheck(panel, "Prefer Disenchant if available", 22, -40)
    controls.rollUseIlvl = MakeCheck(panel, "Use max item level", 22, -70)

    MakeSmallText(panel, "Always excluded: Epic BoE items and Primordial Saronite", 42, -96, 430)

    MakeLabel(panel, "Only if player level >=", 42, -124)
    controls.rollMinLevel = MakeEdit(panel, 55, 22, 190, -119, true)

    MakeLabel(panel, "Max item level", 42, -156)
    controls.rollMaxIlvl = MakeEdit(panel, 55, 22, 190, -151, true)

    controls.rollQuality = MakeButton(panel, "Max rarity: Uncommon", 180, 24, 42, -188)
    controls.rollQuality:SetScript("OnClick", CycleQuality)

    MakeLabel(panel, "Auto Roll Blacklist (one item name, item link, or item ID per line)", 42, -224)
    controls.rollBlacklist = MakeTextArea(panel, 430, 115, 42, -242)

    local save = MakeButton(panel, "Save", 80, 24, 42, -370)
    save:SetScript("OnClick", SaveRollControls)
    return panel
end

local function CycleSellEquipmentQuality()
    local current = controls.sellEquipmentQualityValue or 1
    local nextValue = SELL_QUALITY_VALUES[1]
    for index, value in ipairs(SELL_QUALITY_VALUES) do
        if value == current then
            nextValue = SELL_QUALITY_VALUES[index + 1] or SELL_QUALITY_VALUES[1]
            break
        end
    end
    controls.sellEquipmentQualityValue = nextValue
    if controls.sellEquipmentQuality then
        controls.sellEquipmentQuality:SetText("Max equipment rarity: " .. (SELL_QUALITY_NAMES[nextValue] or "Common"))
    end
    SaveSellControls()
end

local function CycleQuickAddModifier()
    local current = controls.quickAddModifierValue or "ALT"
    local nextValue = QUICK_ADD_MODIFIERS[1]
    for index, value in ipairs(QUICK_ADD_MODIFIERS) do
        if value == current then
            nextValue = QUICK_ADD_MODIFIERS[index + 1] or QUICK_ADD_MODIFIERS[1]
            break
        end
    end
    controls.quickAddModifierValue = nextValue
    if controls.quickAddModifier then controls.quickAddModifier:SetText("Quick add modifier: " .. (QUICK_ADD_MODIFIER_NAMES[nextValue] or nextValue)) end
    SaveSellControls()
end

local function CycleQuickAddTarget()
    local nextValue = (controls.quickAddTargetValue == "force") and "never" or "force"
    controls.quickAddTargetValue = nextValue
    if controls.quickAddTarget then controls.quickAddTarget:SetText("Quick add target: " .. (QUICK_ADD_TARGET_NAMES[nextValue] or nextValue)) end
    SaveSellControls()
end

local function RefreshSellListsFromDB()
    if controls.forceSell and WowNote_GetAutoVendorListText then controls.forceSell:SetText(WowNote_GetAutoVendorListText("force") or "") end
    if controls.neverSell and WowNote_GetAutoVendorListText then controls.neverSell:SetText(WowNote_GetAutoVendorListText("never") or "") end
end

function WowNote_LootTools_RefreshAutoSellLists()
    RefreshSellListsFromDB()
end

local function CreateSellPanel(parent)
    local panel = RaiseChild(CreateFrame("Frame", nil, parent), parent, 2)
    panel:EnableMouse(true)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    controls.sellEnabled = MakeCheck(panel, "Enable auto sell", 22, -10)
    controls.sellGray = MakeCheck(panel, "Sell gray items automatically", 22, -40)
    controls.sellWeapons = MakeCheck(panel, "Sell weapons automatically", 22, -70)
    controls.sellArmor = MakeCheck(panel, "Sell armor automatically", 250, -70)
    controls.sellUseIlvl = MakeCheck(panel, "Use max item level for weapons/armor", 22, -100)

    MakeLabel(panel, "Max item level", 250, -100)
    controls.sellMaxIlvl = MakeEdit(panel, 55, 22, 340, -95, true)

    controls.sellEquipmentQuality = MakeButton(panel, "Max equipment rarity: Common", 210, 24, 42, -132)
    controls.sellEquipmentQuality:SetScript("OnClick", CycleSellEquipmentQuality)

    controls.sellSummary = MakeCheck(panel, "Print sell summary in chat", 22, -164)

    controls.quickAddEnabled = MakeCheck(panel, "Enable quick add from bag clicks", 250, -164)
    controls.quickAddModifier = MakeButton(panel, "Quick add modifier: Alt-click", 190, 24, 42, -194)
    controls.quickAddModifier:SetScript("OnClick", CycleQuickAddModifier)
    controls.quickAddTarget = MakeButton(panel, "Quick add target: Force Sell", 190, 24, 250, -194)
    controls.quickAddTarget:SetScript("OnClick", CycleQuickAddTarget)

    MakeSmallText(panel, "Equipment auto-sell only affects Armor/Weapons up to the selected rarity and optional item level. Never Sell has priority. Lists are sorted and deduplicated when saved. You can also set key bindings for quick adding items.", 42, -224, 470)

    MakeLabel(panel, "Force Sell / Whitelist (one item name, item link, or item ID per line)", 42, -258)
    controls.forceSell = MakeTextArea(panel, 430, 62, 42, -276)

    MakeLabel(panel, "Never Sell / Blacklist (one item name, item link, or item ID per line)", 42, -350)
    controls.neverSell = MakeTextArea(panel, 430, 62, 42, -368)

    local save = MakeButton(panel, "Save", 80, 24, 42, -437)
    save:SetScript("OnClick", SaveSellControls)

    local sort = MakeButton(panel, "Sort lists", 90, 24, 132, -437)
    sort:SetScript("OnClick", SaveSellControls)

    local addForce = MakeButton(panel, "Quick Force", 105, 24, 232, -437)
    addForce:SetScript("OnClick", function()
        SaveSellControls()
        if WowNote_StartAutoSellQuickAdd then WowNote_StartAutoSellQuickAdd("force") end
    end)

    local addNever = MakeButton(panel, "Quick Never", 105, 24, 347, -437)
    addNever:SetScript("OnClick", function()
        SaveSellControls()
        if WowNote_StartAutoSellQuickAdd then WowNote_StartAutoSellQuickAdd("never") end
    end)

    local runNow = MakeButton(panel, "Run now", 90, 24, 42, -465)
    runNow:SetScript("OnClick", function()
        SaveSellControls()
        if WowNote_RunAutoVendorNow then WowNote_RunAutoVendorNow() end
    end)
    return panel
end

local function CreateRepairPanel(parent)
    local panel = RaiseChild(CreateFrame("Frame", nil, parent), parent, 2)
    panel:EnableMouse(true)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    controls.repairEnabled = MakeCheck(panel, "Enable auto repair", 22, -10)
    controls.repairGuild = MakeCheck(panel, "Use guild repair if available", 22, -40)
    controls.repairSummary = MakeCheck(panel, "Print repair summary in chat", 22, -70)

    MakeSmallText(panel, "Auto Repair runs when you open a merchant that can repair. If guild repair is enabled, WowNote tries guild repair first and otherwise uses your own gold.", 42, -105, 440)

    local save = MakeButton(panel, "Save", 80, 24, 42, -170)
    save:SetScript("OnClick", SaveRepairControls)

    local runNow = MakeButton(panel, "Run now", 90, 24, 132, -170)
    runNow:SetScript("OnClick", function()
        SaveRepairControls()
        if WowNote_RunAutoVendorNow then WowNote_RunAutoVendorNow() end
    end)
    return panel
end

local function CreateLootToolsUI()
    if frame then return end

    frame = CreateFrame("Frame", "WowNoteLootToolsFrame", UIParent)
    frame:SetSize(560, 520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function() WowNote_LootTools_SaveActiveTab() end)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.97)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("WowNote Loot Tools")

    local charText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    charText:SetPoint("TOP", frame, "TOP", 0, -34)
    charText:SetText("Auto Roll, Auto Sell, and Auto Repair settings are saved per character.")

    local close = RaiseChild(CreateFrame("Button", nil, frame, "UIPanelCloseButton"), frame, 10)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    tabs.roll = MakeButton(frame, "Auto Roll", 100, 24, 24, -58)
    tabs.sell = MakeButton(frame, "Auto Sell", 100, 24, 130, -58)
    tabs.repair = MakeButton(frame, "Auto Repair", 110, 24, 236, -58)

    local content = RaiseChild(CreateFrame("Frame", nil, frame), frame, 3)
    content:EnableMouse(true)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -90)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 42)

    panels.roll = CreateRollPanel(content)
    panels.sell = CreateSellPanel(content)
    panels.repair = CreateRepairPanel(content)

    tabs.roll:SetScript("OnClick", function() SelectTab("roll") end)
    tabs.sell:SetScript("OnClick", function() SelectTab("sell") end)
    tabs.repair:SetScript("OnClick", function() SelectTab("repair") end)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 18)
    statusText:SetWidth(500)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Ready")

    frame:Hide()
end

function WowNote_OpenLootTools(tabName)
    CreateLootToolsUI()
    SelectTab(tabName or activeTab or "roll")
    frame:Show()
    RaiseFrame(frame)
end

-- Keep old public entry points working. Existing buttons and slash commands call these names.
function WowNote_OpenAutoLootRoller()
    WowNote_OpenLootTools("roll")
end

function WowNote_OpenAutoSell()
    WowNote_OpenLootTools("sell")
end

function WowNote_OpenAutoRepair()
    WowNote_OpenLootTools("repair")
end

function WowNote_ToggleAutoLootRoller()
    local settings = EnsureRollDB()
    settings.enabled = not settings.enabled
    Print("Auto loot roller " .. (settings.enabled and "enabled" or "disabled") .. ".")
end

EnsureRollDB()
EnsureVendorDB()
