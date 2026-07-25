local MODULE_NAME = "WowNote Auto Sell Quick Add"

BINDING_HEADER_WOWNOTE = BINDING_HEADER_WOWNOTE or "WowNote"
BINDING_NAME_WOWNOTE_QUICKADD_FORCE = "Quick add item to Auto Sell whitelist"
BINDING_NAME_WOWNOTE_QUICKADD_NEVER = "Quick add item to Auto Sell blacklist"
BINDING_NAME_WOWNOTE_QUICKADD_PROTECT = "Quick add item to WowNote Item Protection"

local captureTarget = nil
local hooked = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg))
end

local function EnsureVendorDB()
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.autoVendor) ~= "table" then WowNoteCharDB.autoVendor = {} end
    local settings = WowNoteCharDB.autoVendor
    if settings.quickAddEnabled == nil then settings.quickAddEnabled = true end
    if settings.quickAddModifier == nil then settings.quickAddModifier = "ALT" end
    if settings.quickAddTarget == nil then settings.quickAddTarget = "force" end
    return settings
end

local function IsAltDown()
    return IsAltKeyDown and IsAltKeyDown() and true or false
end

local function IsCtrlDown()
    return IsControlKeyDown and IsControlKeyDown() and true or false
end

local function IsShiftDown()
    return IsShiftKeyDown and IsShiftKeyDown() and true or false
end

local function ModifierMatches(settings)
    -- Exact matching is intentional: Alt+Shift is reserved for Item Protection and
    -- must not be swallowed by Auto Sell when its modifier is configured as Alt-click.
    local mod = settings.quickAddModifier or "ALT"
    local alt, ctrl, shift = IsAltDown(), IsCtrlDown(), IsShiftDown()
    if mod == "ALT" then return alt and not ctrl and not shift end
    if mod == "CTRL" then return ctrl and not alt and not shift end
    if mod == "SHIFT" then return shift and not alt and not ctrl end
    return false
end

local function IsProtectionModifierDown()
    return IsAltDown() and IsShiftDown() and not IsCtrlDown()
end

local function GetButtonItemLink(button)
    if not button then return nil end
    local bag, slot
    if button:GetParent() and button:GetParent().GetID then bag = button:GetParent():GetID() end
    if button.GetID then slot = button:GetID() end
    if bag and slot and GetContainerItemLink then
        return GetContainerItemLink(bag, slot)
    end
    if button.link then return button.link end
    return nil
end

local function AddLink(target, link)
    if not link or link == "" then return false end
    if target == "protect" then
        if WowNote_AddProtectedItem then
            WowNote_AddProtectedItem(link)
        end
        if WowNote_LootTools_RefreshProtectionList then
            WowNote_LootTools_RefreshProtectionList()
        end
        return true
    end
    if WowNote_AddAutoVendorListEntry then
        WowNote_AddAutoVendorListEntry(target == "never" and "never" or "force", link)
    end
    if WowNote_LootTools_RefreshAutoSellLists then
        WowNote_LootTools_RefreshAutoSellLists()
    end
    return true
end

function WowNote_StartAutoSellQuickAdd(target)
    captureTarget = target == "protect" and "protect" or (target == "never" and "never" or "force")
    local label = captureTarget == "protect" and "Item Protection" or (captureTarget == "never" and "Never Sell" or "Force Sell")
    Print("Quick add armed for " .. label .. ". Click a bag item to add it.")
end

function WowNote_QuickAddCursorItemToAutoSell(target)
    local kind, itemID, itemLink = GetCursorInfo and GetCursorInfo()
    if kind == "item" then
        local link = itemLink
        if not link and itemID and GetItemInfo then link = select(2, GetItemInfo(itemID)) end
        if AddLink(target, link or tostring(itemID or "")) then
            ClearCursor()
            return
        end
    end
    WowNote_StartAutoSellQuickAdd(target)
end

function WOWNOTE_QUICKADD_FORCE()
    WowNote_QuickAddCursorItemToAutoSell("force")
end

function WOWNOTE_QUICKADD_NEVER()
    WowNote_QuickAddCursorItemToAutoSell("never")
end

function WOWNOTE_QUICKADD_PROTECT()
    WowNote_QuickAddCursorItemToAutoSell("protect")
end

local function HandleBagClick(button, mouseButton)
    if WowNote_ItemProtection_HandleBagModifiedClick and WowNote_ItemProtection_HandleBagModifiedClick(button, mouseButton) then return end
    if WowNote_ItemProtection_HandleBagClick and WowNote_ItemProtection_HandleBagClick(button) then return end

    local link = GetButtonItemLink(button)
    if not link then return end

    if captureTarget then
        local target = captureTarget
        captureTarget = nil
        AddLink(target, link)
        return
    end

    local settings = EnsureVendorDB()
    if not settings.quickAddEnabled then return end
    if mouseButton ~= "LeftButton" and mouseButton ~= nil then return end
    if not ModifierMatches(settings) then return end

    AddLink(settings.quickAddTarget or "force", link)
end

local function InstallHooks()
    if hooked then return end
    hooked = true

    if hooksecurefunc then
        if type(ContainerFrameItemButton_OnModifiedClick) == "function" then
            hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(button, mouseButton)
                HandleBagClick(button, mouseButton or "LeftButton")
            end)
        end
        if type(ContainerFrameItemButton_OnClick) == "function" then
            hooksecurefunc("ContainerFrameItemButton_OnClick", function(button, mouseButton)
                -- Fallback for clients/skins that route Alt+Shift bag clicks through OnClick
                -- instead of OnModifiedClick. Do not run normal Auto Sell quick-add from here,
                -- otherwise modified clicks can be handled twice.
                if captureTarget or IsProtectionModifierDown() then
                    HandleBagClick(button, mouseButton or "LeftButton")
                end
            end)
        end
    end
end

EnsureVendorDB()
InstallHooks()
