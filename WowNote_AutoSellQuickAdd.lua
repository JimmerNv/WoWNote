local MODULE_NAME = "WowNote Auto Sell Quick Add"

BINDING_HEADER_WOWNOTE = BINDING_HEADER_WOWNOTE or "WowNote"
BINDING_NAME_WOWNOTE_QUICKADD_FORCE = "Quick add item to Auto Sell whitelist"
BINDING_NAME_WOWNOTE_QUICKADD_NEVER = "Quick add item to Auto Sell blacklist"

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

local function ModifierMatches(settings)
    local mod = settings.quickAddModifier or "ALT"
    if mod == "ALT" then return IsAltKeyDown and IsAltKeyDown() end
    if mod == "CTRL" then return IsControlKeyDown and IsControlKeyDown() end
    if mod == "SHIFT" then return IsShiftKeyDown and IsShiftKeyDown() end
    return false
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
    if WowNote_AddAutoVendorListEntry then
        WowNote_AddAutoVendorListEntry(target == "never" and "never" or "force", link)
    end
    if WowNote_LootTools_RefreshAutoSellLists then
        WowNote_LootTools_RefreshAutoSellLists()
    end
    return true
end

function WowNote_StartAutoSellQuickAdd(target)
    captureTarget = target == "never" and "never" or "force"
    Print("Quick add armed for " .. (captureTarget == "never" and "Never Sell" or "Force Sell") .. ". Click a bag item to add it.")
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

local function HandleBagClick(button, mouseButton)
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
                if captureTarget then HandleBagClick(button, mouseButton or "LeftButton") end
            end)
        end
    end
end

EnsureVendorDB()
InstallHooks()
