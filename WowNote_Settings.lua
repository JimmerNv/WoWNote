-- WowNote_Settings.lua
-- Central module switches and small settings UI.

local WN = WowNote_Internal or {}
local settingsFrame
local moduleChecks = {}

local MODULE_DEFAULTS = {
    mailFeatures = true,
    pallyBuffs = true,
    characterNotes = true,
    social = true,
    dataTransfer = true,
}

local MODULE_LABELS = {
    { key = "mailFeatures", label = "Mail features" },
    { key = "pallyBuffs", label = "PallyBuffs" },
    { key = "characterNotes", label = "Character notes" },
    { key = "social", label = "Social protections" },
    { key = "dataTransfer", label = "Data transfer" },
}

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function EnsureSettings()
    if WN.InitDB then WN.InitDB() end
    WowNoteDB = WowNoteDB or {}
    WowNoteDB.modules = WowNoteDB.modules or {}
    for key, value in pairs(MODULE_DEFAULTS) do
        if WowNoteDB.modules[key] == nil then WowNoteDB.modules[key] = value end
    end
    WowNoteDB.characterNoteOptions = WowNoteDB.characterNoteOptions or {}
    if WowNoteDB.characterNoteOptions.alwaysShow == nil then WowNoteDB.characterNoteOptions.alwaysShow = false end
    WowNoteDB.social = WowNoteDB.social or {}
    if WowNoteDB.social.blockGuildInvite == nil then WowNoteDB.social.blockGuildInvite = false end
    if WowNoteDB.social.cleanManabonkMail == nil then WowNoteDB.social.cleanManabonkMail = true end
    WowNoteDB.minimap = WowNoteDB.minimap or {}
    if WowNoteDB.minimap.hide == nil then WowNoteDB.minimap.hide = false end
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
    if key == "pallyBuffs" and not enabled and WowNotePallyPowerFrame then WowNotePallyPowerFrame:Hide() end
    if key == "characterNotes" and not enabled and WowNoteCharacterNotesFrame then WowNoteCharacterNotesFrame:Hide() end
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
    if settingsFrame and settingsFrame.blockGuildCheck then settingsFrame.blockGuildCheck:SetChecked(WowNote_IsGuildInviteBlockEnabled()) end
    if settingsFrame and settingsFrame.manabonkCleanCheck then settingsFrame.manabonkCleanCheck:SetChecked(WowNote_IsManabonkMailCleanerEnabled()) end
    if settingsFrame and settingsFrame.hideMinimapCheck then settingsFrame.hideMinimapCheck:SetChecked(WowNote_IsMinimapIconHidden()) end
end

local function CreateSettingsFrame()
    if settingsFrame then return end
    settingsFrame = CreateFrame("Frame", "WowNoteSettingsFrame", UIParent)
    settingsFrame:SetWidth(390)
    settingsFrame:SetHeight(330)
    settingsFrame:SetPoint("CENTER")
    settingsFrame:SetFrameStrata("DIALOG")
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
    settingsFrame.blockGuildCheck = MakeCheck(settingsFrame, "Block guild invite", 220, -108, WowNote_IsGuildInviteBlockEnabled(), function(checked)
        WowNote_SetGuildInviteBlockEnabled(checked)
    end)
    settingsFrame.manabonkCleanCheck = MakeCheck(settingsFrame, "Clean Manabonk mail", 220, -138, WowNote_IsManabonkMailCleanerEnabled(), function(checked)
        WowNote_SetManabonkMailCleanerEnabled(checked)
    end)
    settingsFrame.hideMinimapCheck = MakeCheck(settingsFrame, "Hide minimap icon", 220, -168, WowNote_IsMinimapIconHidden(), function(checked)
        WowNote_SetMinimapIconHidden(checked)
    end)

    local hint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", settingsFrame, "BOTTOMLEFT", 24, 24)
    hint:SetWidth(330)
    hint:SetJustifyH("LEFT")
    hint:SetText("Mail features run at the mailbox only. PallyBuffs keeps PLPWR compatibility internally.")
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
init:SetScript("OnEvent", function()
    EnsureSettings()
    ApplyMailModuleState(WowNote_IsModuleEnabled("mailFeatures"))
end)
