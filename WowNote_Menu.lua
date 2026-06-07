-- WowNote_Menu.lua
-- Anchored side menu and submenu routing for the main WoWNote window.

local submenu
local submenuButtons = {}
local currentMenuKey

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function IsEnabled(key)
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled(key) then return false end
    return true
end

local function EnsureSubmenu(parent)
    if submenu then return submenu end
    submenu = CreateFrame("Frame", "WowNoteSideSubmenu", parent)
    submenu:SetWidth(168)
    submenu:SetHeight(180)
    submenu:SetPoint("TOPLEFT", parent, "TOPLEFT", 930, -96)
    submenu:SetFrameStrata("DIALOG")
    submenu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    submenu:SetBackdropColor(0.02, 0.02, 0.02, 0.94)
    submenu:SetBackdropBorderColor(0.45, 0.35, 0.18, 1)
    submenu:EnableMouse(true)
    submenu:Hide()

    submenu.title = submenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    submenu.title:SetPoint("TOPLEFT", submenu, "TOPLEFT", 10, -8)
    submenu.title:SetWidth(148)
    submenu.title:SetJustifyH("LEFT")
    return submenu
end

local function HideSubmenu()
    currentMenuKey = nil
    if submenu then submenu:Hide() end
end

local function ClearSubmenu()
    for _, button in ipairs(submenuButtons) do
        button:Hide()
    end
end

local function ShowSubmenu(parent, makeButton, title, key, items)
    local menu = EnsureSubmenu(parent)
    ClearSubmenu()
    currentMenuKey = key
    menu.title:SetText(title or "Menu")

    local height = 34 + (table.getn(items or {}) * 28)
    if height < 64 then height = 64 end
    menu:SetHeight(height)

    local i
    for i = 1, table.getn(items or {}) do
        local item = items[i]
        local button = submenuButtons[i]
        if not button then
            button = makeButton(menu, "", 144, 23)
            button:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -26 - ((i - 1) * 28))
            submenuButtons[i] = button
        end
        button:SetText(item.text or "")
        button:SetScript("OnClick", function()
            if item.moduleKey and not IsEnabled(item.moduleKey) then
                Print((item.text or "Module") .. " is disabled.")
                return
            end
            if item.func then item.func() end
        end)
        if item.tooltip then
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(item.text or "WowNote", 1, 0.82, 0)
                GameTooltip:AddLine(item.tooltip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            button:SetScript("OnEnter", nil)
            button:SetScript("OnLeave", nil)
        end
        button:Show()
    end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", parent, "TOPLEFT", 930, -96)
    menu:Show()
    if menu.GetRight and UIParent and UIParent.GetRight and menu:GetRight() and UIParent:GetRight() and menu:GetRight() > UIParent:GetRight() then
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", parent, "TOPLEFT", 742, -96)
    end
end

local function OpenNotes()
    if WowNote_Open then WowNote_Open() end
    HideSubmenu()
end

function WowNote_BuildSideMenu(parent, makeButton)
    if not parent or not makeButton then return end

    local sideTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sideTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 748, -52)
    sideTitle:SetText("Main")

    local y = -76
    local function AddButton(text, onClick, tooltip)
        local button = makeButton(parent, text, 130, 24)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", 748, y)
        y = y - 30
        button:SetScript("OnClick", onClick)
        if tooltip then
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(text, 1, 0.82, 0)
                GameTooltip:AddLine(tooltip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return button
    end

    AddButton("Notes", function() OpenNotes() end, "Open normal notes.")
    AddButton("Character Notes", function()
        HideSubmenu()
        if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled("characterNotes") then Print("Character notes module is disabled."); return end
        if WowNote_OpenCharacterNotes then WowNote_OpenCharacterNotes() else Print("Character Notes module is not loaded.") end
    end, "Open player-name attached notes.")
    AddButton("Bank", function()
        HideSubmenu()
        if WowNote_OpenBankViewer then WowNote_OpenBankViewer() else Print("Bank module is not loaded.") end
    end, "Open the bank viewer.")

    y = y - 8
    AddButton("Quality of Life", function()
        ShowSubmenu(parent, makeButton, "Quality of Life", "qol", {
            { text = "Raid Planner", tooltip = "Open raid planning presets and roster assignments.", func = function() if WowNote_OpenRaidPlanner then WowNote_OpenRaidPlanner() else Print("Raid Planner module is not loaded.") end end },
            { text = "PallyBuffs", moduleKey = "pallyBuffs", tooltip = "Open Blessing and Aura assignments.", func = function() if WowNote_OpenPallyBuffs then WowNote_OpenPallyBuffs() else Print("PallyBuffs module is not loaded.") end end },
        })
    end, "Open raid planning and PallyBuffs tools.")

    AddButton("Data Transfer", function()
        ShowSubmenu(parent, makeButton, "Data Transfer", "transfer", {
            { text = "Send / Receive", moduleKey = "dataTransfer", tooltip = "Open protected sending/receiving. Send will ask what data to transfer.", func = function() if WowNote_OpenShare then WowNote_OpenShare() else Print("Share dialog is not available.") end end },
            { text = "Import / Export", moduleKey = "dataTransfer", tooltip = "Choose what to export or import WowNote data.", func = function()
                ShowSubmenu(parent, makeButton, "Import / Export", "importexport", {
                    { text = "Export...", moduleKey = "dataTransfer", func = function() if WowNote_OpenDataExportPicker then WowNote_OpenDataExportPicker() else Print("Export picker is not available.") end end },
                    { text = "Import...", moduleKey = "dataTransfer", func = function() if WowNote_OpenGenericImportDialog then WowNote_OpenGenericImportDialog() elseif WowNote_OpenImportNoteDialog then WowNote_OpenImportNoteDialog() else Print("Import is not available.") end end },
                })
            end },
        })
    end, "Open Send/Receive or Import/Export actions.")

    AddButton("Character Tools", function()
        ShowSubmenu(parent, makeButton, "Character Tools", "character", {
            { text = "Talents", tooltip = "Open the talent planner.", func = function() if WowNote_OpenTalents then WowNote_OpenTalents() else Print("Talent planner is not loaded.") end end },
            { text = "Raid IDs", tooltip = "Open the raid ID tracker.", func = function() if WowNote_OpenRaidIdTracker then WowNote_OpenRaidIdTracker() else Print("Raid ID tracker is not loaded.") end end },
            { text = "Tracker", tooltip = "Open the item tracker.", func = function() if WowNote_OpenItemTracker then WowNote_OpenItemTracker() else Print("Tracker module is not loaded.") end end },
            { text = "Restock", tooltip = "Open restock rules.", func = function() if WowNote_OpenRestock then WowNote_OpenRestock() else Print("Restock module is not loaded.") end end },
        })
    end, "Open character-related utility tools.")

    AddButton("Social", function()
        ShowSubmenu(parent, makeButton, "Social", "social", {
            { text = "Block Guild Invite", moduleKey = "social", tooltip = "Toggle automatic guild invite blocking.", func = function()
                if not WowNote_SetGuildInviteBlockEnabled or not WowNote_IsGuildInviteBlockEnabled then Print("Social settings are not loaded."); return end
                local nextValue = not WowNote_IsGuildInviteBlockEnabled()
                WowNote_SetGuildInviteBlockEnabled(nextValue)
                Print(nextValue and "Block guild invite enabled." or "Block guild invite disabled.")
                if WowNote_OpenSocial then WowNote_OpenSocial() end
            end },
        })
    end, "Open social protection actions.")

    AddButton("Settings", function()
        HideSubmenu()
        if WowNote_OpenSettings then WowNote_OpenSettings() else Print("Settings module is not loaded.") end
    end, "Enable or disable modules and note-tooltip options.")

    AddButton("Help", function()
        HideSubmenu()
        if WowNote_PrintHelp then WowNote_PrintHelp() end
    end, "Print WowNote commands and usage hints.")
end
