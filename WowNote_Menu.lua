-- WowNote_Menu.lua
-- Anchored side menu and submenu routing for the main WoWNote window.

local submenu
local submenuButtons = {}
local currentMenuKey
local submenuOwner

local SUBMENU_X_OFFSET = 930
local SUBMENU_Y_OFFSET = -96
local SUBMENU_FALLBACK_X_OFFSET = 742

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function IsEnabled(key)
    if WowNote_IsModuleEnabled and not WowNote_IsModuleEnabled(key) then return false end
    return true
end

local function EnsureSubmenu(parent)
    if submenu then return submenu end
    submenuOwner = parent
    -- Keep the submenu anchored to the main WowNote frame, but parent it to UIParent.
    -- A child frame placed outside the main frame can be visually shown while still losing
    -- mouse hits to higher-level siblings/overlays. UIParent + explicit strata/level keeps
    -- the anchored flyout clickable.
    submenu = CreateFrame("Frame", "WowNoteSideSubmenu", UIParent)
    submenu:SetWidth(178)
    submenu:SetHeight(180)
    submenu:SetPoint("TOPLEFT", parent, "TOPLEFT", SUBMENU_X_OFFSET, SUBMENU_Y_OFFSET)
    submenu:SetFrameStrata("FULLSCREEN_DIALOG")
    submenu:SetToplevel(true)
    submenu:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
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

function WowNote_HideSideSubmenu()
    HideSubmenu()
end

local function AttachSubmenuLifecycle(parent)
    if not parent or parent.__wowNoteSubmenuLifecycleHooked then return end
    parent.__wowNoteSubmenuLifecycleHooked = true
    if parent.HookScript then
        parent:HookScript("OnHide", function() HideSubmenu() end)
    else
        local oldOnHide = parent:GetScript("OnHide")
        parent:SetScript("OnHide", function(self, ...)
            HideSubmenu()
            if oldOnHide then oldOnHide(self, ...) end
        end)
    end
end

local function ClearSubmenu()
    for _, button in ipairs(submenuButtons) do
        button:Hide()
        button:SetScript("OnClick", nil)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
    end
end

local function ShowSubmenu(parent, makeButton, title, key, items)
    local menu = EnsureSubmenu(parent)
    submenuOwner = parent
    menu:SetParent(UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
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
            button = makeButton(menu, "", 154, 23)
            button:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -26 - ((i - 1) * 28))
            button:EnableMouse(true)
            submenuButtons[i] = button
        end
        button:SetParent(menu)
        button:SetFrameStrata("FULLSCREEN_DIALOG")
        button:SetFrameLevel(menu:GetFrameLevel() + 1 + i)
        button:EnableMouse(true)
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
    menu:SetPoint("TOPLEFT", parent, "TOPLEFT", SUBMENU_X_OFFSET, SUBMENU_Y_OFFSET)
    menu:Show()
    menu:Raise()
    if menu.GetRight and UIParent and UIParent.GetRight and menu:GetRight() and UIParent:GetRight() and menu:GetRight() > UIParent:GetRight() then
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", parent, "TOPLEFT", SUBMENU_FALLBACK_X_OFFSET, SUBMENU_Y_OFFSET)
    end
end

local function OpenNotes()
    if WowNote_Open then WowNote_Open() end
    HideSubmenu()
end

function WowNote_BuildSideMenu(parent, makeButton)
    if not parent or not makeButton then return end
    AttachSubmenuLifecycle(parent)

    local sideTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sideTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 748, -52)
    sideTitle:SetText("Main")

    local y = -76
    local function AddButton(text, onClick, tooltip)
        local button = makeButton(parent, text, 130, 24)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", 748, y)
        button:EnableMouse(true)
        button:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
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

    AddButton("Port Helper", function()
        HideSubmenu()
        if WowNote_RaidPlanner and WowNote_RaidPlanner.ShowPortHelper then
            WowNote_RaidPlanner.ShowPortHelper()
        else
            Print("Port Helper module is not loaded.")
        end
    end, "Open the Raid Planner summon request helper.")

    y = y - 8
    AddButton("Quality of Life", function()
        ShowSubmenu(parent, makeButton, "Quality of Life", "qol", {
            { text = "Raid Planner", tooltip = "Open raid planning presets and roster assignments.", func = function() if WowNote_OpenRaidPlanner then WowNote_OpenRaidPlanner() else Print("Raid Planner module is not loaded.") end end },
            { text = "PallyBuffs", moduleKey = "pallyBuffs", tooltip = "Open Blessing and Aura assignments.", func = function() if WowNote_OpenPallyBuffs then WowNote_OpenPallyBuffs() else Print("PallyBuffs module is not loaded.") end end },
            { text = "Cursor Effects", moduleKey = "cursorEffects", tooltip = "Configure animated effects that follow the mouse cursor.", func = function() if WowNote_OpenCursorEffects then WowNote_OpenCursorEffects() else Print("Cursor Effects module is not loaded.") end end },
            { text = "Screen Draw", tooltip = "Open the free screen drawing overlay.", func = function() if WowNote_OpenScreenDraw then WowNote_OpenScreenDraw() else Print("Screen Draw module is not loaded.") end end },
            { text = "Tactical Board", tooltip = "Open the tactical drawing board for raid tactics.", func = function() if WowNote_OpenTacticalMap then WowNote_OpenTacticalMap() else Print("Tactical Board module is not loaded.") end end },
            { text = "Clear Tactical HUD", tooltip = "Clear the active tactical HUD overlay.", func = function() if WowNote_HudDraw_Clear then WowNote_HudDraw_Clear() else Print("Tactical HUD module is not loaded.") end end },
        })
    end, "Open raid planning, cursor effects, PallyBuffs and draw tools.")

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
            { text = "Loot Tools", tooltip = "Open auto roll, auto sell, and auto repair settings.", func = function() if WowNote_OpenLootTools then WowNote_OpenLootTools("roll") elseif WowNote_OpenAutoLootRoller then WowNote_OpenAutoLootRoller() else Print("Loot Tools module is not loaded.") end end },
            { text = "Auto Sell", tooltip = "Open auto sell settings directly.", func = function() if WowNote_OpenLootTools then WowNote_OpenLootTools("sell") elseif WowNote_OpenAutoSell then WowNote_OpenAutoSell() else Print("Auto Sell module is not loaded.") end end },
            { text = "Auto Repair", tooltip = "Open auto repair settings directly.", func = function() if WowNote_OpenLootTools then WowNote_OpenLootTools("repair") elseif WowNote_OpenAutoRepair then WowNote_OpenAutoRepair() else Print("Auto Repair module is not loaded.") end end },
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
            { text = "Clean Manabonk Mail", moduleKey = "social", tooltip = "Toggle automatic cleanup of Manabonk mail with The Mischief Maker attachment.", func = function()
                if not WowNote_SetManabonkMailCleanerEnabled or not WowNote_IsManabonkMailCleanerEnabled then Print("Social settings are not loaded."); return end
                local nextValue = not WowNote_IsManabonkMailCleanerEnabled()
                WowNote_SetManabonkMailCleanerEnabled(nextValue)
                Print(nextValue and "Manabonk mail cleanup enabled." or "Manabonk mail cleanup disabled.")
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
