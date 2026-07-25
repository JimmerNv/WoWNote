-- WowNote_Settings.lua
-- Central module switches and small settings UI.

local WN = WowNote_Internal or {}
local settingsFrame
local moduleChecks = {}

local POSTAL_OPEN_INTERVAL_DEFAULT = 0.50
local POSTAL_OPEN_INTERVAL_MIN = 0.05

local MODULE_DEFAULTS = {
    mailFeatures = true,
    pallyBuffs = true,
    characterNotes = true,
    social = true,
    dataTransfer = true,
    cursorEffects = true,
    biteHelper = true,
    threatMeter = true,
}

local MODULE_LABELS = {
    { key = "mailFeatures", label = "Mail features" },
    { key = "pallyBuffs", label = "PallyBuffs" },
    { key = "characterNotes", label = "Character notes" },
    { key = "social", label = "Social protections" },
    { key = "dataTransfer", label = "Data transfer" },
    { key = "cursorEffects", label = "Cursor effects" },
    { key = "biteHelper", label = "Bite Helper" },
    { key = "threatMeter", label = "Threat Meter" },
}

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function NormalizePostalOpenInterval(value)
    local text = tostring(value or "")
    text = string.gsub(text, ",", ".")
    local number = tonumber(text)
    if not number or number <= 0 then number = POSTAL_OPEN_INTERVAL_DEFAULT end
    if number < POSTAL_OPEN_INTERVAL_MIN then number = POSTAL_OPEN_INTERVAL_MIN end
    return number
end

local function FormatPostalOpenInterval(value)
    local number = NormalizePostalOpenInterval(value)
    local text = string.format("%.2f", number)
    text = string.gsub(text, "0+$", "")
    text = string.gsub(text, "%.$", "")
    return text
end

local function EnsureSettings()
    if WN.InitDB then WN.InitDB() end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.modules) ~= "table" then WowNoteDB.modules = {} end
    for key, value in pairs(MODULE_DEFAULTS) do
        if WowNoteDB.modules[key] == nil then WowNoteDB.modules[key] = value end
    end
    if type(WowNoteDB.characterNoteOptions) ~= "table" then WowNoteDB.characterNoteOptions = {} end
    if WowNoteDB.characterNoteOptions.alwaysShow == nil then WowNoteDB.characterNoteOptions.alwaysShow = false end
    if WowNoteDB.characterNoteOptions.warnPunks == nil then WowNoteDB.characterNoteOptions.warnPunks = false end
    if type(WowNoteDB.social) ~= "table" then WowNoteDB.social = {} end
    if WowNoteDB.social.blockGuildInvite == nil then WowNoteDB.social.blockGuildInvite = false end
    if WowNoteDB.social.cleanManabonkMail == nil then WowNoteDB.social.cleanManabonkMail = true end
    if type(WowNoteDB.minimap) ~= "table" then WowNoteDB.minimap = {} end
    if WowNoteDB.minimap.hide == nil then WowNoteDB.minimap.hide = false end
    if type(WowNoteDB.postalLite) ~= "table" then WowNoteDB.postalLite = {} end
    if WowNoteDB.postalLite.openAllInterval == nil then
        WowNoteDB.postalLite.openAllInterval = NormalizePostalOpenInterval(WowNoteDB.postalOpenInterval or POSTAL_OPEN_INTERVAL_DEFAULT)
    else
        WowNoteDB.postalLite.openAllInterval = NormalizePostalOpenInterval(WowNoteDB.postalLite.openAllInterval)
    end
    return WowNoteDB.modules
end

function WowNote_IsModuleEnabled(key)
    local modules = EnsureSettings()
    if modules[key] == nil then return true end
    return modules[key] == true
end

local function ApplyMailModuleState(enabled)
    if WowNotePostal_ModuleMenuButton then if enabled then WowNotePostal_ModuleMenuButton:Show() else WowNotePostal_ModuleMenuButton:Hide() end end
    if not WowNotePostal then return end
    if WowNotePostal.db and WowNotePostal.db.profile and WowNotePostal.db.profile.ModuleEnabledState then
        for name, module in WowNotePostal:IterateModules() do
            WowNotePostal.db.profile.ModuleEnabledState[name] = enabled and true or false
            if enabled then
                if module.Enable then module:Enable() end
            else
                if module.Disable then module:Disable() end
            end
        end
    elseif WowNotePostal.SetEnabledState then
        WowNotePostal:SetEnabledState(enabled and true or false)
    end
end

function WowNote_SetModuleEnabled(key, enabled)
    EnsureSettings()
    WowNoteDB.modules[key] = enabled and true or false
    if key == "mailFeatures" then ApplyMailModuleState(enabled) end
    if key == "pallyBuffs" then
        if WowNote_PallyBuffs_SetEnabled then
            WowNote_PallyBuffs_SetEnabled(enabled)
        elseif not enabled and WowNotePallyPowerFrame then
            WowNotePallyPowerFrame:Hide()
        end
    end
    if key == "characterNotes" and not enabled and WowNoteCharacterNotesFrame then WowNoteCharacterNotesFrame:Hide() end
    if key == "cursorEffects" and WowNote_SetCursorEffectsModuleEnabled then WowNote_SetCursorEffectsModuleEnabled(enabled) end
    if key == "biteHelper" and WowNote_BiteHelper_SetEnabled then WowNote_BiteHelper_SetEnabled(enabled) end
    if key == "threatMeter" and WowNote_ThreatMeter_SetEnabled then WowNote_ThreatMeter_SetEnabled(enabled) end
    Print((enabled and "Enabled " or "Disabled ") .. tostring(key))
end

function WowNote_AreCharacterNotesAlwaysShown()
    EnsureSettings()
    return WowNoteDB.characterNoteOptions.alwaysShow == true
end

function WowNote_SetCharacterNotesAlwaysShown(enabled)
    EnsureSettings()
    WowNoteDB.characterNoteOptions.alwaysShow = enabled and true or false
end

function WowNote_ArePunkJoinWarningsEnabled()
    EnsureSettings()
    return WowNoteDB.characterNoteOptions.warnPunks == true
end

function WowNote_SetPunkJoinWarningsEnabled(enabled)
    EnsureSettings()
    WowNoteDB.characterNoteOptions.warnPunks = enabled and true or false
    if settingsFrame and settingsFrame.warnPunksCheck then settingsFrame.warnPunksCheck:SetChecked(enabled and true or false) end
end

function WowNote_IsGuildInviteBlockEnabled()
    EnsureSettings()
    return WowNoteDB.social.blockGuildInvite == true
end

function WowNote_SetGuildInviteBlockEnabled(enabled)
    EnsureSettings()
    WowNoteDB.social.blockGuildInvite = enabled and true or false
end

function WowNote_IsManabonkMailCleanerEnabled()
    EnsureSettings()
    return WowNoteDB.social.cleanManabonkMail == true
end

function WowNote_SetManabonkMailCleanerEnabled(enabled)
    EnsureSettings()
    WowNoteDB.social.cleanManabonkMail = enabled and true or false
    if enabled and WowNote_TryCleanManabonkMail then WowNote_TryCleanManabonkMail() end
end

function WowNote_IsMinimapIconHidden()
    EnsureSettings()
    return WowNoteDB.minimap and WowNoteDB.minimap.hide == true
end

function WowNote_SetMinimapIconHidden(enabled)
    EnsureSettings()
    if enabled then
        if WowNote_HideMinimapButton then WowNote_HideMinimapButton() end
    else
        if WowNote_ShowMinimapButton then WowNote_ShowMinimapButton() end
    end
end

function WowNote_GetPostalOpenInterval()
    EnsureSettings()
    return NormalizePostalOpenInterval(WowNoteDB.postalLite and WowNoteDB.postalLite.openAllInterval or POSTAL_OPEN_INTERVAL_DEFAULT)
end

function WowNote_SetPostalOpenInterval(value)
    EnsureSettings()
    local interval = NormalizePostalOpenInterval(value)
    WowNoteDB.postalLite.openAllInterval = interval
    WowNoteDB.postalOpenInterval = nil
    if settingsFrame and settingsFrame.postalIntervalEdit then
        settingsFrame.postalIntervalEdit:SetText(FormatPostalOpenInterval(interval))
    end
    Print("Postal Open All interval saved: " .. FormatPostalOpenInterval(interval) .. " sec")
    return interval
end

local function RefreshBagSortDirectionButton()
    if not settingsFrame or not settingsFrame.bagSortDirectionButton then return end
    local direction = "top"
    if WowNote_BagOrganizer_GetSortDirection then direction = WowNote_BagOrganizer_GetSortDirection() or "top" end
    settingsFrame.bagSortDirectionButton:SetText("Bag sort: " .. (direction == "bottom" and "Bottom" or "Top"))
end

local function MakeCheck(parent, label, x, y, checked, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check:SetWidth(24)
    check:SetHeight(24)
    check.text = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check.text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.text:SetText(label)
    check:SetChecked(checked and true or false)
    check:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return check
end

local function RefreshSettingsUI()
    EnsureSettings()
    for key, check in pairs(moduleChecks) do
        check:SetChecked(WowNote_IsModuleEnabled(key))
    end
    if settingsFrame and settingsFrame.alwaysNotesCheck then settingsFrame.alwaysNotesCheck:SetChecked(WowNote_AreCharacterNotesAlwaysShown()) end
    if settingsFrame and settingsFrame.warnPunksCheck then settingsFrame.warnPunksCheck:SetChecked(WowNote_ArePunkJoinWarningsEnabled()) end
    if settingsFrame and settingsFrame.blockGuildCheck then settingsFrame.blockGuildCheck:SetChecked(WowNote_IsGuildInviteBlockEnabled()) end
    if settingsFrame and settingsFrame.manabonkCleanCheck then settingsFrame.manabonkCleanCheck:SetChecked(WowNote_IsManabonkMailCleanerEnabled()) end
    if settingsFrame and settingsFrame.hideMinimapCheck then settingsFrame.hideMinimapCheck:SetChecked(WowNote_IsMinimapIconHidden()) end
    if settingsFrame and settingsFrame.postalIntervalEdit then
        settingsFrame.postalIntervalEdit:SetText(FormatPostalOpenInterval(WowNote_GetPostalOpenInterval()))
    end
    RefreshBagSortDirectionButton()
end

local function CreateSettingsFrame()
    if settingsFrame then return end
    settingsFrame = CreateFrame("Frame", "WowNoteSettingsFrame", UIParent)
    settingsFrame:SetWidth(430)
    settingsFrame:SetHeight(545)
    settingsFrame:SetPoint("CENTER")
    settingsFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if settingsFrame.SetToplevel then settingsFrame:SetToplevel(true) end
    settingsFrame:SetFrameLevel(100)
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    settingsFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    settingsFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    settingsFrame:Hide()

    local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 18, -16)
    title:SetText("WowNote Settings")

    local close = CreateFrame("Button", nil, settingsFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -4, -4)

    local moduleTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moduleTitle:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 24, -52)
    moduleTitle:SetText("Modules")

    local y = -78
    for _, info in ipairs(MODULE_LABELS) do
        moduleChecks[info.key] = MakeCheck(settingsFrame, info.label, 28, y, WowNote_IsModuleEnabled(info.key), function(checked)
            WowNote_SetModuleEnabled(info.key, checked)
        end)
        y = y - 30
    end

    local optionTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionTitle:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -52)
    optionTitle:SetText("Options")

    settingsFrame.alwaysNotesCheck = MakeCheck(settingsFrame, "Always show character note", 220, -78, WowNote_AreCharacterNotesAlwaysShown(), function(checked)
        WowNote_SetCharacterNotesAlwaysShown(checked)
    end)
    settingsFrame.warnPunksCheck = MakeCheck(settingsFrame, "Warn when punks join", 220, -108, WowNote_ArePunkJoinWarningsEnabled(), function(checked)
        WowNote_SetPunkJoinWarningsEnabled(checked)
    end)
    settingsFrame.blockGuildCheck = MakeCheck(settingsFrame, "Block guild invite", 220, -138, WowNote_IsGuildInviteBlockEnabled(), function(checked)
        WowNote_SetGuildInviteBlockEnabled(checked)
    end)
    settingsFrame.manabonkCleanCheck = MakeCheck(settingsFrame, "Clean Manabonk mail", 220, -168, WowNote_IsManabonkMailCleanerEnabled(), function(checked)
        WowNote_SetManabonkMailCleanerEnabled(checked)
    end)
    settingsFrame.hideMinimapCheck = MakeCheck(settingsFrame, "Hide minimap icon", 220, -198, WowNote_IsMinimapIconHidden(), function(checked)
        WowNote_SetMinimapIconHidden(checked)
    end)
    settingsFrame.showThreatButton = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    settingsFrame.showThreatButton:SetWidth(145)
    settingsFrame.showThreatButton:SetHeight(24)
    settingsFrame.showThreatButton:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -228)
    settingsFrame.showThreatButton:SetText("Show Threat Meter")
    settingsFrame.showThreatButton:SetScript("OnClick", function()
        if WowNote_OpenThreatMeter then WowNote_OpenThreatMeter() else Print("Threat Meter module is not loaded.") end
    end)

    settingsFrame.threatConfigButton = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    settingsFrame.threatConfigButton:SetWidth(145)
    settingsFrame.threatConfigButton:SetHeight(24)
    settingsFrame.threatConfigButton:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -258)
    settingsFrame.threatConfigButton:SetText("Threat Meter Config")
    settingsFrame.threatConfigButton:SetScript("OnClick", function()
        if WowNote_OpenThreatMeterConfig then WowNote_OpenThreatMeterConfig() else Print("Threat Meter module is not loaded.") end
    end)

    local postalTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    postalTitle:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -292)
    postalTitle:SetText("Postal Lite")

    local postalLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    postalLabel:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -318)
    postalLabel:SetText("Open All interval (sec)")

    settingsFrame.postalIntervalEdit = CreateFrame("EditBox", "WowNotePostalOpenIntervalEdit", settingsFrame, "InputBoxTemplate")
    settingsFrame.postalIntervalEdit:SetWidth(62)
    settingsFrame.postalIntervalEdit:SetHeight(20)
    settingsFrame.postalIntervalEdit:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -342)
    settingsFrame.postalIntervalEdit:SetAutoFocus(false)
    settingsFrame.postalIntervalEdit:SetText(FormatPostalOpenInterval(WowNote_GetPostalOpenInterval()))
    settingsFrame.postalIntervalEdit:SetScript("OnEnterPressed", function(self)
        WowNote_SetPostalOpenInterval(self:GetText())
        self:ClearFocus()
    end)
    settingsFrame.postalIntervalEdit:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatPostalOpenInterval(WowNote_GetPostalOpenInterval()))
        self:ClearFocus()
    end)

    settingsFrame.postalIntervalSaveButton = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    settingsFrame.postalIntervalSaveButton:SetWidth(72)
    settingsFrame.postalIntervalSaveButton:SetHeight(22)
    settingsFrame.postalIntervalSaveButton:SetPoint("LEFT", settingsFrame.postalIntervalEdit, "RIGHT", 10, 0)
    settingsFrame.postalIntervalSaveButton:SetText("Save")
    settingsFrame.postalIntervalSaveButton:SetScript("OnClick", function()
        if settingsFrame and settingsFrame.postalIntervalEdit then
            WowNote_SetPostalOpenInterval(settingsFrame.postalIntervalEdit:GetText())
            settingsFrame.postalIntervalEdit:ClearFocus()
        end
    end)

    local postalHint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    postalHint:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -370)
    postalHint:SetWidth(180)
    postalHint:SetJustifyH("LEFT")
    postalHint:SetText("Free numeric value. Comma or dot decimals are accepted. Minimum is 0.05 sec to avoid a tight loop.")

    local bagTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bagTitle:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -405)
    bagTitle:SetText("Bag Organizer")

    settingsFrame.bagSortDirectionButton = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    settingsFrame.bagSortDirectionButton:SetWidth(145)
    settingsFrame.bagSortDirectionButton:SetHeight(22)
    settingsFrame.bagSortDirectionButton:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -429)
    settingsFrame.bagSortDirectionButton:SetScript("OnClick", function()
        if WowNote_BagOrganizer_ToggleSortDirection then
            WowNote_BagOrganizer_ToggleSortDirection()
            RefreshBagSortDirectionButton()
        else
            Print("Bag Organizer module is not loaded.")
        end
    end)
    RefreshBagSortDirectionButton()

    local bagHint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bagHint:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 220, -456)
    bagHint:SetWidth(180)
    bagHint:SetJustifyH("LEFT")
    bagHint:SetText("Top fills bags from top/left. Bottom fills from bottom/right. Reserved slots are kept with their reserved item or empty. Reserve hovered slot with keybinding R by default.")

    local hint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", settingsFrame, "BOTTOMLEFT", 24, 24)
    hint:SetWidth(330)
    hint:SetJustifyH("LEFT")
    hint:SetText("Disabled modules stop their runtime events and background work. PallyBuffs keeps PLPWR compatibility internally.")
end

function WowNote_OpenSettings()
    EnsureSettings()
    CreateSettingsFrame()
    RefreshSettingsUI()
    settingsFrame:Show()
    if WN.RaiseFrame then WN.RaiseFrame(settingsFrame) end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
WowNoteProfiler_SetScript(init, "OnEvent", "Settings.Init", function()
    EnsureSettings()
    ApplyMailModuleState(WowNote_IsModuleEnabled("mailFeatures"))
    if WowNote_SetCursorEffectsModuleEnabled then WowNote_SetCursorEffectsModuleEnabled(WowNote_IsModuleEnabled("cursorEffects")) end
    if WowNote_BiteHelper_SetEnabled then WowNote_BiteHelper_SetEnabled(WowNote_IsModuleEnabled("biteHelper")) end
    if WowNote_ThreatMeter_SetEnabled then WowNote_ThreatMeter_SetEnabled(WowNote_IsModuleEnabled("threatMeter")) end
end)
