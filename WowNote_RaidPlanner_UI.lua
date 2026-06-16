-- WowNote Raid Planner UI and import/export dialog

WowNote_RaidPlanner = WowNote_RaidPlanner or {}
local RP = WowNote_RaidPlanner
local WNI = WowNote_Internal or {}
local InitDB = WNI.InitDB
local MakeButton = WNI.MakeButton
local MakeEditBox = WNI.MakeEditBox
local RaiseFrame = WNI.RaiseFrame or function(frameToRaise) if frameToRaise and frameToRaise.SetFrameStrata then frameToRaise:SetFrameStrata("FULLSCREEN_DIALOG") end end

function WowNote_RaidPlanner_MakeHelp(parent, anchor, helpText)
    if not parent or not anchor or not helpText or helpText == "" then return nil end

    local help = CreateFrame("Button", nil, parent)
    help:SetWidth(16)
    help:SetHeight(16)
    help:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    help:EnableMouse(true)

    local text = help:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", help, "CENTER", 0, 0)
    text:SetText("?")

    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Raid Planner Help", 1, 0.82, 0)
        GameTooltip:AddLine(helpText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return help
end

function WowNote_RaidPlanner_MakeLabeledEdit(parent, labelText, x, y, width, defaultText, multiline, height, helpText)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(labelText)
    WowNote_RaidPlanner_MakeHelp(parent, label, helpText)

    local bg = CreateFrame("Frame", nil, parent)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    bg:SetWidth(width or 120)
    bg:SetHeight(height or (multiline and 56 or 24))
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0, 0, 0, 0.85)

    local edit = MakeEditBox(bg, multiline)
    edit:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
    edit:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -4, 4)
    edit:SetText(defaultText or "")
    edit:SetScript("OnTextChanged", function(self)
        if not RP.suppressPreview then
            WowNote_RaidPlanner_UpdatePreview()
        end
    end)
    return edit
end

function WowNote_RaidPlanner_MakeNumberRow(parent, labelText, x, y, defaultNeed, defaultHave, helpText)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(labelText)
    WowNote_RaidPlanner_MakeHelp(parent, label, helpText)

    local need = WowNote_RaidPlanner_MakeLabeledEdit(parent, "Need", x + 95, y + 18, 46, tostring(defaultNeed or 0), false, 24, "Total number needed for this role.")
    local have = WowNote_RaidPlanner_MakeLabeledEdit(parent, "Have", x + 154, y + 18, 46, tostring(defaultHave or 0), false, 24, "Current number already assigned. It is usually updated from the roster, but can also be adjusted manually.")
    if need.SetNumeric then need:SetNumeric(true) end
    if have.SetNumeric then have:SetNumeric(true) end

    local up = MakeButton(parent, "+", 22, 18)
    up:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 204, y)
    up:SetScript("OnClick", function()
        WowNote_RaidPlanner_SetNumber(have, WowNote_RaidPlanner_GetNumber(have) + 1)
        WowNote_RaidPlanner_UpdatePreview()
    end)
    WowNote_RaidPlanner_MakeHelp(parent, up, "Increase the current Have value by one.")

    local down = MakeButton(parent, "-", 22, 18)
    down:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 204, y - 20)
    down:SetScript("OnClick", function()
        WowNote_RaidPlanner_SetNumber(have, WowNote_RaidPlanner_GetNumber(have) - 1)
        WowNote_RaidPlanner_UpdatePreview()
    end)

    return need, have
end

local function MakeCheckButton(parent, text, x, y, checked, helpText)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetChecked(checked and true or false)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(text)
    WowNote_RaidPlanner_MakeHelp(parent, label, helpText)
    check:SetScript("OnClick", function()
        if RP.RemoveLeaversFromRoster then RP.RemoveLeaversFromRoster() end
        WowNote_RaidPlanner_UpdatePreview()
    end)
    return check
end

function WowNote_RaidPlanner_MakeRosterColumn(parent, role, title, x, y, width, height)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(title)
    WowNote_RaidPlanner_MakeHelp(parent, label, "One player per line. Format: Name, Class. Example: Karlid, Paladin. The Have counter for this role is calculated from this column.")

    local bg = CreateFrame("Frame", nil, parent)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    bg:SetWidth(width)
    bg:SetHeight(height)
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0, 0, 0, 0.85)

    local edit = MakeEditBox(bg, true)
    edit:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
    edit:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -4, 4)
    edit:SetScript("OnTextChanged", function()
        if RP.suppressPreview then return end
        if RP.UpdateHaveFromRoster then RP.UpdateHaveFromRoster() end
        WowNote_RaidPlanner_UpdatePreview()
    end)

    RP.rosterEdits = RP.rosterEdits or {}
    RP.rosterEdits[role] = edit
    return edit
end


local function GetGroupMembers()
    local members = {}
    local function add(unit)
        if UnitExists and UnitExists(unit) then
            local name = UnitName(unit)
            if name and name ~= "" then
                local _, class = UnitClass(unit)
                table.insert(members, { name = name, class = class or "" })
            end
        end
    end
    add("player")
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do add("raid" .. i) end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do add("party" .. i) end
    end
    table.sort(members, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return members
end

local function SetDropDownText(dropdown, text)
    if dropdown and dropdown.text then dropdown.text:SetText(text or "") end
end

local function CreateSimpleDropDown(parent, name, x, y, width, getItems, onSelect, defaultText)
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dd.text = _G[name .. "Text"]
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dd, width or 120)
    UIDropDownMenu_Initialize(dd, function(self, level)
        local items = getItems and getItems() or {}
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.func = function()
                if onSelect then onSelect(item) end
                SetDropDownText(dd, item.text)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    SetDropDownText(dd, defaultText or "Select")
    return dd
end

local function AppendRosterLine(role, name, className)
    if not role or not name or name == "" or not RP.rosterEdits or not RP.rosterEdits[role] then return false end
    local edit = RP.rosterEdits[role]
    local line = name
    if className and className ~= "" then line = line .. ", " .. className end
    local current = edit:GetText() or ""
    if current ~= "" and string.sub(current, -1) ~= "\n" then current = current .. "\n" end
    edit:SetText(current .. line)
    if RP.UpdateHaveFromRoster then RP.UpdateHaveFromRoster() end
    WowNote_RaidPlanner_UpdatePreview()
    return true
end

function WowNote_RaidPlanner_CreateRosterDropDowns(parent, x, y)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText("Add group member")
    WowNote_RaidPlanner_MakeHelp(parent, title, "Select a current group or raid member, choose a role, then add the player to the roster table. The class is filled automatically when available.")

    RP.selectedRosterMember = nil
    RP.selectedRosterRole = "tanks"

    RP.memberDropDown = CreateSimpleDropDown(parent, "WowNoteRaidPlannerMemberDropDown", x, y - 20, 150, function()
        local items = {}
        for _, member in ipairs(GetGroupMembers()) do
            table.insert(items, { text = member.name .. (member.class ~= "" and (" (" .. member.class .. ")") or ""), value = member })
        end
        if #items == 0 then table.insert(items, { text = "No group members", value = nil }) end
        return items
    end, function(item)
        RP.selectedRosterMember = item and item.value or nil
    end, "Member")

    RP.roleDropDown = CreateSimpleDropDown(parent, "WowNoteRaidPlannerRoleDropDown", x + 170, y - 20, 90, function()
        return {
            { text = "Tanks", value = "tanks" },
            { text = "Healers", value = "healers" },
            { text = "DPS", value = "dps" },
            { text = "mDPS", value = "mdps" },
            { text = "rDPS", value = "rdps" },
        }
    end, function(item)
        RP.selectedRosterRole = item and item.value or "tanks"
    end, "Tanks")

    local addButton = MakeButton(parent, "Add", 56, 22)
    addButton:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 300, y - 22)
    addButton:SetScript("OnClick", function()
        local m = RP.selectedRosterMember
        if not m or not m.name then
            WowNote_RaidPlanner_SetStatus("Select a group member first.")
            return
        end
        if AppendRosterLine(RP.selectedRosterRole or "tanks", m.name, m.class) then
            WowNote_RaidPlanner_SetStatus("Added " .. m.name .. " to roster.")
        end
    end)
    WowNote_RaidPlanner_MakeHelp(parent, addButton, "Adds the selected member to the selected role column.")
end

function WowNote_RaidPlanner_ShowTransferFrame(mode)
    if not RP.transferFrame then
        local f = CreateFrame("Frame", "WowNoteRaidPresetTransferFrame", UIParent)
        RP.transferFrame = f
        f:SetWidth(560)
        f:SetHeight(360)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        if f.SetToplevel then f:SetToplevel(true) end
        f:SetFrameLevel(100)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnMouseDown", function(self) RaiseFrame(self) end)
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
        title:SetText("Raid Planner Preset Import / Export")
        RP.transferTitle = title

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -52)
        label:SetText("Preset text")

        local bg = CreateFrame("Frame", nil, f)
        bg:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -72)
        bg:SetWidth(512)
        bg:SetHeight(190)
        bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        bg:SetBackdropColor(0, 0, 0, 0.85)

        local edit = MakeEditBox(bg, true)
        edit:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
        edit:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -4, 4)
        RP.transferEdit = edit

        local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        help:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -270)
        help:SetWidth(512)
        help:SetJustifyH("LEFT")
        help:SetText("Export creates a shareable preset string including the roster table. Import loads the setup into the Raid Planner. Click Save Preset afterwards if you want to store it account-wide.")

        local selectAll = MakeButton(f, "Select all", 86, 24)
        selectAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 24)
        selectAll:SetScript("OnClick", function()
            RP.transferEdit:SetFocus()
            RP.transferEdit:HighlightText()
        end)

        local action = MakeButton(f, "Import", 86, 24)
        action:SetPoint("LEFT", selectAll, "RIGHT", 8, 0)
        RP.transferActionButton = action

        local closeButton = MakeButton(f, "Close", 86, 24)
        closeButton:SetPoint("RIGHT", f, "RIGHT", -24, 0)
        closeButton:SetPoint("BOTTOM", f, "BOTTOM", 0, 24)
        closeButton:SetScript("OnClick", function() f:Hide() end)

        f:Hide()
    end

    if mode == "export" then
        local name = WowNote_RaidPlanner_GetText(RP.presetNameEdit, "")
        local exportText = WowNote_RaidPlanner_EncodePreset(WowNote_RaidPlanner_GetCurrentPresetData(), name)
        RP.transferTitle:SetText("Export Raid Planner Preset")
        RP.transferEdit:SetText(exportText)
        RP.transferEdit:SetFocus()
        RP.transferEdit:HighlightText()
        RP.transferActionButton:SetText("Refresh")
        RP.transferActionButton:SetScript("OnClick", function()
            local refreshed = WowNote_RaidPlanner_EncodePreset(WowNote_RaidPlanner_GetCurrentPresetData(), WowNote_RaidPlanner_GetText(RP.presetNameEdit, ""))
            RP.transferEdit:SetText(refreshed)
            RP.transferEdit:SetFocus()
            RP.transferEdit:HighlightText()
            WowNote_RaidPlanner_SetStatus("Raid preset export refreshed.")
        end)
        WowNote_RaidPlanner_SetStatus("Raid preset export ready. Copy the selected text.")
    else
        RP.transferTitle:SetText("Import Raid Planner Preset")
        RP.transferEdit:SetText("")
        RP.transferEdit:SetFocus()
        RP.transferActionButton:SetText("Import")
        RP.transferActionButton:SetScript("OnClick", function()
            local preset, presetName, err = WowNote_RaidPlanner_DecodePreset(RP.transferEdit:GetText() or "")
            if err then
                WowNote_RaidPlanner_SetStatus(err)
                return
            end
            if WowNote_RaidPlanner_ApplyPresetData(preset, presetName) then
                WowNote_RaidPlanner_SetStatus("Raid preset imported. Click Save Preset to store it account-wide.")
                RP.transferFrame:Hide()
            end
        end)
        WowNote_RaidPlanner_SetStatus("Paste a raid preset export string and click Import.")
    end
    RP.transferFrame:Show()
    RaiseFrame(RP.transferFrame)
end

function WowNote_RaidPlanner_ExportPreset()
    WowNote_RaidPlanner_ShowTransferFrame("export")
end

function WowNote_RaidPlanner_ImportPreset()
    WowNote_RaidPlanner_ShowTransferFrame("import")
end


function WowNote_RaidPlanner_RefreshPresetList(selectedName)
    if not RP.presetRows then return end
    local names = WowNote_RaidPlanner_GetPresetNames and WowNote_RaidPlanner_GetPresetNames() or {}
    RP.presetListOffset = RP.presetListOffset or 0
    if selectedName and selectedName ~= "" then
        for i, name in ipairs(names) do
            if name == selectedName then
                if i <= RP.presetListOffset then RP.presetListOffset = i - 1 end
                if i > RP.presetListOffset + #RP.presetRows then RP.presetListOffset = i - #RP.presetRows end
                break
            end
        end
    end
    if RP.presetListOffset < 0 then RP.presetListOffset = 0 end
    if RP.presetListOffset > math.max(0, #names - #RP.presetRows) then
        RP.presetListOffset = math.max(0, #names - #RP.presetRows)
    end

    for i, row in ipairs(RP.presetRows) do
        local name = names[RP.presetListOffset + i]
        row.presetName = name
        if name then
            row:SetText(name)
            row:Show()
            if name == (selectedName or RP.selectedPresetName) then
                row:LockHighlight()
            else
                row:UnlockHighlight()
            end
        else
            row:SetText("")
            row:UnlockHighlight()
            row:Hide()
        end
    end

    if RP.presetListCountText then
        RP.presetListCountText:SetText(tostring(#names) .. " preset" .. (#names == 1 and "" or "s"))
    end
end

local function WowNote_RaidPlanner_CreatePresetList(parent, x, y)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText("Saved Presets")
    WowNote_RaidPlanner_MakeHelp(parent, title, "Click a saved preset to select it. Use Load to open it, Save Preset to overwrite/update it, Delete to remove it, or Export Preset to share it.")

    local bg = CreateFrame("Frame", nil, parent)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    bg:SetWidth(220)
    bg:SetHeight(162)
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0, 0, 0, 0.85)

    RP.presetRows = {}
    RP.presetListOffset = 0
    for i = 1, 7 do
        local row = MakeButton(bg, "", 186, 18)
        row:SetPoint("TOPLEFT", bg, "TOPLEFT", 6, -6 - ((i - 1) * 21))
        row:SetScript("OnClick", function(self)
            if self.presetName then
                WowNote_RaidPlanner_SelectPreset(self.presetName)
            end
        end)
        row:SetScript("OnDoubleClick", function(self)
            if self.presetName then
                WowNote_RaidPlanner_SelectPreset(self.presetName)
                WowNote_RaidPlanner_LoadPreset()
            end
        end)
        table.insert(RP.presetRows, row)
    end

    local up = MakeButton(bg, "^", 22, 18)
    up:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -6, -6)
    up:SetScript("OnClick", function()
        RP.presetListOffset = math.max(0, (RP.presetListOffset or 0) - 1)
        WowNote_RaidPlanner_RefreshPresetList(RP.selectedPresetName)
    end)
    WowNote_RaidPlanner_MakeHelp(bg, up, "Scroll preset list up.")

    local down = MakeButton(bg, "v", 22, 18)
    down:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6, 6)
    down:SetScript("OnClick", function()
        RP.presetListOffset = (RP.presetListOffset or 0) + 1
        WowNote_RaidPlanner_RefreshPresetList(RP.selectedPresetName)
    end)

    RP.presetListCountText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    RP.presetListCountText:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 184)
    RP.presetListCountText:SetText("0 presets")

    WowNote_RaidPlanner_RefreshPresetList()
end

function WowNote_CreateRaidPlannerUI()
    if RP.frame then return end

    if InitDB then InitDB() end
    local f = CreateFrame("Frame", "WowNoteRaidPlannerFrame", UIParent)
    RP.frame = f
    f:SetWidth(980)
    f:SetHeight(720)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.SetToplevel then f:SetToplevel(true) end
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseDown", function(self) RaiseFrame(self) end)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    title:SetText("WowNote Raid Planner")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local portHelperButton = MakeButton(f, "Port Helper", 100, 22)
    portHelperButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -42, -14)
    portHelperButton:SetScript("OnClick", function()
        if RP.ShowPortHelper then RP.ShowPortHelper() end
    end)
    WowNote_RaidPlanner_MakeHelp(f, portHelperButton, "Opens the summon request helper. Post a reply code, collect matching chat replies, and click a player button to target them for summoning.")

    RP.sizeEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Raid Size", 24, -52, 70, "10", false, 24, "Choose 10, 25, or enter any custom size/text you want to show in the message.")
    local size10 = MakeButton(f, "10", 38, 22)
    size10:SetPoint("TOPLEFT", f, "TOPLEFT", 102, -70)
    size10:SetScript("OnClick", function() RP.sizeEdit:SetText("10") end)
    local size25 = MakeButton(f, "25", 38, 22)
    size25:SetPoint("LEFT", size10, "RIGHT", 4, 0)
    size25:SetScript("OnClick", function() RP.sizeEdit:SetText("25") end)
    local custom = MakeButton(f, "Custom", 64, 22)
    custom:SetPoint("LEFT", size25, "RIGHT", 4, 0)
    custom:SetScript("OnClick", function() RP.sizeEdit:SetFocus(); RP.sizeEdit:HighlightText() end)

    RP.raidNameEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Raid Name", 300, -52, 220, "", false, 24, "The raid or activity name. Used by the %name placeholder.")
    RP.channelEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Post Channel", 545, -52, 80, "/2", false, 24, "Where to post the message. Examples: /2, /5, /y, /s, /g, /p, /raid.")
    RP.contactEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Contact", 648, -52, 150, "/w me", false, 24, "Free contact text inserted by the %contact placeholder. Example: /w Stiffbeard.")
    RP.autoRemoveCheck = MakeCheckButton(f, "Auto-remove leavers", 815, -68, true, "When group or raid roster changes, assigned players who are no longer in your group are removed from the roster table automatically.")

    RP.tankNeedEdit, RP.tankHaveEdit = WowNote_RaidPlanner_MakeNumberRow(f, "Tanks", 34, -125, 2, 0, "Tank slots. Have is counted from the Tanks roster column.")
    RP.healNeedEdit, RP.healHaveEdit = WowNote_RaidPlanner_MakeNumberRow(f, "Healers", 34, -168, 3, 0, "Healer slots. Have is counted from the Healers roster column.")
    RP.dpsNeedEdit, RP.dpsHaveEdit = WowNote_RaidPlanner_MakeNumberRow(f, "DPS", 34, -211, 5, 0, "General DPS slots. Used when no mDPS or rDPS need values are set.")
    RP.mdpsNeedEdit, RP.mdpsHaveEdit = WowNote_RaidPlanner_MakeNumberRow(f, "mDPS", 360, -125, 0, 0, "Optional melee DPS slots. If mDPS or rDPS need values are set, %dps is built from those split values automatically.")
    RP.rdpsNeedEdit, RP.rdpsHaveEdit = WowNote_RaidPlanner_MakeNumberRow(f, "rDPS", 360, -168, 0, 0, "Optional ranged DPS slots. If mDPS or rDPS need values are set, %dps is built from those split values automatically.")

    local splitLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    splitLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 360, -220)
    splitLabel:SetText("DPS split is automatic")
    WowNote_RaidPlanner_MakeHelp(f, splitLabel, "There is only one DPS placeholder: %dps. If only the DPS row has values, %dps becomes 5 DPS. If mDPS/rDPS need values are set, %dps becomes 2 mDPS, 3 rDPS.")

    local rosterTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rosterTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -260)
    rosterTitle:SetText("Raid Roster")
    WowNote_RaidPlanner_MakeHelp(f, rosterTitle, "Assign members into role columns. One line per player, for example: Karlid, Paladin. The Have counters above update automatically.")

    WowNote_RaidPlanner_MakeRosterColumn(f, "tanks", "Tanks", 24, -286, 170, 118)
    WowNote_RaidPlanner_MakeRosterColumn(f, "healers", "Healers", 208, -286, 170, 118)
    WowNote_RaidPlanner_MakeRosterColumn(f, "dps", "DPS", 392, -286, 170, 118)
    WowNote_RaidPlanner_MakeRosterColumn(f, "mdps", "mDPS", 576, -286, 170, 118)
    WowNote_RaidPlanner_MakeRosterColumn(f, "rdps", "rDPS", 760, -286, 170, 118)

    local scanButton = MakeButton(f, "Check Group", 92, 22)
    scanButton:SetPoint("TOPLEFT", f, "TOPLEFT", 130, -256)
    scanButton:SetScript("OnClick", function() if RP.ScanGroupIntoRoster then RP.ScanGroupIntoRoster() end end)
    WowNote_RaidPlanner_MakeHelp(f, scanButton, "Checks the current group/raid and removes assigned players that already left, if Auto-remove leavers is enabled.")

    local clearRosterButton = MakeButton(f, "Clear Roster", 92, 22)
    clearRosterButton:SetPoint("LEFT", scanButton, "RIGHT", 8, 0)
    clearRosterButton:SetScript("OnClick", function()
        if RP.ClearRoster then RP.ClearRoster() end
        WowNote_RaidPlanner_UpdatePreview()
        WowNote_RaidPlanner_SetStatus("Roster cleared.")
    end)

    WowNote_RaidPlanner_CreateRosterDropDowns(f, 430, -246)

    RP.templateEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Message Template", 24, -430, 672, RP.defaultTemplate, false, 28, "Available placeholders: %name, %size, %tank, %heal, %dps, %info, %contact. Empty role placeholders are cleaned up automatically.")
    RP.infoEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Additional Info", 24, -486, 320, "", true, 54, "Optional public information appended through %info. Example: chill run, need Discord, 5.8k+.")
    RP.internalNoteEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Internal Note (not posted)", 376, -486, 320, "", true, 54, "Private note for yourself. This text is saved in presets but never posted.")
    WowNote_RaidPlanner_CreatePresetList(f, 720, -430)
    RP.previewEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Preview", 24, -564, 672, "", true, 42, "Shows the exact message that will be sent when you click Post.")
    RP.previewEdit:SetScript("OnTextChanged", function() end)

    RP.presetNameEdit = WowNote_RaidPlanner_MakeLabeledEdit(f, "Preset Name", 24, -633, 180, "", false, 24, "Selected preset name. Pick a preset from the list or type a new name. Saving with an existing name updates that preset.")

    local previewButton = MakeButton(f, "Preview", 72, 24)
    previewButton:SetPoint("TOPLEFT", f, "TOPLEFT", 220, -651)
    previewButton:SetScript("OnClick", function() WowNote_RaidPlanner_UpdatePreview() end)
    local postButton = MakeButton(f, "Post", 72, 24)
    postButton:SetPoint("LEFT", previewButton, "RIGHT", 8, 0)
    postButton:SetScript("OnClick", WowNote_RaidPlanner_Post)
    local saveButton = MakeButton(f, "Save/Update", 100, 24)
    saveButton:SetPoint("LEFT", postButton, "RIGHT", 8, 0)
    saveButton:SetScript("OnClick", WowNote_RaidPlanner_SavePreset)
    local loadButton = MakeButton(f, "Load", 70, 24)
    loadButton:SetPoint("LEFT", saveButton, "RIGHT", 8, 0)
    loadButton:SetScript("OnClick", WowNote_RaidPlanner_LoadPreset)
    local deleteButton = MakeButton(f, "Delete", 70, 24)
    deleteButton:SetPoint("LEFT", loadButton, "RIGHT", 8, 0)
    deleteButton:SetScript("OnClick", WowNote_RaidPlanner_DeletePreset)
    local resetButton = MakeButton(f, "Reset", 70, 24)
    resetButton:SetPoint("LEFT", deleteButton, "RIGHT", 8, 0)
    resetButton:SetScript("OnClick", WowNote_RaidPlanner_Reset)

    local exportPresetButton = MakeButton(f, "Export Preset", 110, 24)
    exportPresetButton:SetPoint("TOPLEFT", f, "TOPLEFT", 220, -681)
    exportPresetButton:SetScript("OnClick", WowNote_RaidPlanner_ExportPreset)
    WowNote_RaidPlanner_MakeHelp(f, exportPresetButton, "Exports the current Raid Planner setup including roster assignments as a shareable text block.")

    local importPresetButton = MakeButton(f, "Import Preset", 110, 24)
    importPresetButton:SetPoint("LEFT", exportPresetButton, "RIGHT", 8, 0)
    importPresetButton:SetScript("OnClick", WowNote_RaidPlanner_ImportPreset)
    WowNote_RaidPlanner_MakeHelp(f, importPresetButton, "Imports a shared Raid Planner preset text block into this window. Use Save Preset afterwards to store it account-wide.")

    RP.statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    RP.statusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 18)
    RP.statusText:SetText("Ready")

    f:SetScript("OnShow", function()
        if InitDB then InitDB() end
        if RP.RemoveLeaversFromRoster then RP.RemoveLeaversFromRoster() end
        WowNote_RaidPlanner_UpdatePreview()
        if WowNote_RaidPlanner_RefreshPresetList then WowNote_RaidPlanner_RefreshPresetList(RP.selectedPresetName) end
    end)
end

function WowNote_OpenRaidPlanner()
    WowNote_CreateRaidPlannerUI()
    RP.frame:Show()
    RaiseFrame(RP.frame)
    WowNote_RaidPlanner_UpdatePreview()
end
