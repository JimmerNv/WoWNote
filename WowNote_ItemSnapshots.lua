-- WowNote_ItemSnapshots.lua
-- Account-wide bag and bank snapshots for WoW 3.3.5a.

local MODULE = "WowNote ItemSnapshots"
local BANK_ID = BANK_CONTAINER or -1
local BAG_MIN = 0
local BAG_MAX = NUM_BAG_SLOTS or 4
local BANK_BAG_MIN = (NUM_BAG_SLOTS or 4) + 1
local BANK_BAG_MAX = (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7)

local isBankOpen = false
local pendingBagScan = false
local pendingBankScan = false
local scheduler = CreateFrame("Frame")
scheduler:Hide()
scheduler.elapsed = 0
local INVENTORY_SCAN_INTERVAL = 15
local lastBagScanAt = -INVENTORY_SCAN_INTERVAL
local lastBankScanAt = -INVENTORY_SCAN_INTERVAL
local bagScanDueAt = nil
local bankScanDueAt = nil

local function Now()
    if GetTime then return GetTime() end
    if time then return time() end
    return 0
end

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg))
    end
end

local function InitDB()
    if WowNote_Internal and WowNote_Internal.InitDB then
        WowNote_Internal.InitDB()
    end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.inventorySnapshots) ~= "table" then WowNoteDB.inventorySnapshots = {} end
    if type(WowNoteDB.bankSnapshots) ~= "table" then WowNoteDB.bankSnapshots = {} end
end

local function RealmName()
    return GetRealmName and GetRealmName() or "UnknownRealm"
end

local function CharacterName()
    return UnitName and UnitName("player") or "Unknown"
end

local function ExtractItemId(link)
    if not link then return nil end
    local id = string.match(link, "item:(%-?%d+)")
    if id then return tonumber(id) end
    return nil
end

local function EnsureCharacterSnapshot(root)
    InitDB()
    local realm = RealmName()
    local char = CharacterName()
    if type(root[realm]) ~= "table" then root[realm] = {} end
    if type(root[realm][char]) ~= "table" then root[realm][char] = {} end
    local snapshot = root[realm][char]
    if type(snapshot.containers) ~= "table" then snapshot.containers = {} end
    snapshot.character = char
    snapshot.realm = realm
    snapshot.updatedAt = time and time() or 0
    return snapshot
end

local function SnapshotItem(bag, slot)
    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not texture and not link then return nil end

    local itemId = ExtractItemId(link)
    local name, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture
    if link and GetItemInfo then
        name, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(link)
    elseif itemId and GetItemInfo then
        name, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemId)
    end

    return {
        itemId = itemId,
        link = link or itemLink,
        name = name,
        texture = texture or itemTexture,
        count = count or 1,
        quality = quality or itemQuality,
        itemType = itemType,
        itemSubType = itemSubType,
        equipLoc = itemEquipLoc,
    }
end

local function ScanContainerInto(snapshot, bag)
    if not GetContainerNumSlots then return end
    local size = GetContainerNumSlots(bag) or 0
    local container = {
        bag = bag,
        size = size,
        updatedAt = time and time() or 0,
        slots = {},
    }

    for slot = 1, size do
        container.slots[slot] = SnapshotItem(bag, slot)
    end

    snapshot.containers[bag] = container
end

local function RebuildSnapshotCounts(snapshot)
    local counts = {}
    if type(snapshot) == "table" and type(snapshot.containers) == "table" then
        for _, container in pairs(snapshot.containers) do
            if type(container) == "table" and type(container.slots) == "table" then
                for _, item in pairs(container.slots) do
                    if type(item) == "table" and item.itemId then
                        local itemId = tonumber(item.itemId)
                        if itemId then counts[itemId] = (counts[itemId] or 0) + (tonumber(item.count) or 1) end
                    end
                end
            end
        end
    end
    snapshot.counts = counts
end

local function ScanInventoryNow()
    local snapshot = EnsureCharacterSnapshot(WowNoteDB.inventorySnapshots)
    for bag = BAG_MIN, BAG_MAX do
        ScanContainerInto(snapshot, bag)
    end
    RebuildSnapshotCounts(snapshot)
    snapshot.updatedAt = time and time() or 0
    lastBagScanAt = Now()

    if WowNote_ItemTracker_Evaluate then
        WowNote_ItemTracker_Evaluate(false)
    elseif WowNote_ItemTracker_RefreshHud then
        WowNote_ItemTracker_RefreshHud()
    end
end

local function ScanBankNow()
    if not isBankOpen then return end
    local snapshot = EnsureCharacterSnapshot(WowNoteDB.bankSnapshots)
    ScanContainerInto(snapshot, BANK_ID)
    for bag = BANK_BAG_MIN, BANK_BAG_MAX do
        ScanContainerInto(snapshot, bag)
    end
    RebuildSnapshotCounts(snapshot)
    snapshot.updatedAt = time and time() or 0
    lastBankScanAt = Now()

    if WowNote_BankViewer_Refresh then
        WowNote_BankViewer_Refresh()
    end
    if WowNote_ItemTracker_Evaluate then
        WowNote_ItemTracker_Evaluate(false)
    elseif WowNote_ItemTracker_RefreshHud then
        WowNote_ItemTracker_RefreshHud()
    end
end

local function Schedule(kind, immediate)
    local now = Now()
    if kind == "bank" then
        pendingBankScan = true
        bankScanDueAt = immediate and now or math.max(now + 0.25, lastBankScanAt + INVENTORY_SCAN_INTERVAL)
    else
        pendingBagScan = true
        bagScanDueAt = immediate and now or math.max(now + 0.25, lastBagScanAt + INVENTORY_SCAN_INTERVAL)
    end
    scheduler:Show()
end

WowNoteProfiler_SetScript(scheduler, "OnUpdate", "ItemSnapshots.Scheduler", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + (elapsed or 0)
    if self.elapsed < 0.20 then return end
    self.elapsed = 0
    local now = Now()
    if pendingBagScan and bagScanDueAt and now >= bagScanDueAt then
        pendingBagScan = false
        bagScanDueAt = nil
        ScanInventoryNow()
    end
    if pendingBankScan and bankScanDueAt and now >= bankScanDueAt then
        pendingBankScan = false
        bankScanDueAt = nil
        ScanBankNow()
    end
    if not pendingBagScan and not pendingBankScan then self:Hide() end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
WowNoteProfiler_SetScript(events, "OnEvent", "ItemSnapshots.Events", function(self, event, arg1)
    InitDB()
    if event == "PLAYER_LOGIN" then
        Schedule("bags", true)
    elseif event == "BAG_UPDATE" then
        local bag = tonumber(arg1)
        if not bag or (bag >= BAG_MIN and bag <= BAG_MAX) then
            Schedule("bags", false)
        end
        if isBankOpen and (not bag or bag == BANK_ID or (bag >= BANK_BAG_MIN and bag <= BANK_BAG_MAX)) then
            Schedule("bank", false)
        end
    elseif event == "BANKFRAME_OPENED" then
        isBankOpen = true
        Schedule("bags", true)
        Schedule("bank", true)
    elseif event == "BANKFRAME_CLOSED" then
        pendingBankScan = false
        bankScanDueAt = nil
        ScanBankNow()
        isBankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        if isBankOpen then Schedule("bank", false) end
    end
end)

local function AddCountsFromSnapshot(counts, snapshot)
    if type(snapshot) ~= "table" or type(snapshot.containers) ~= "table" then return end
    for _, container in pairs(snapshot.containers) do
        if type(container) == "table" and type(container.slots) == "table" then
            for _, item in pairs(container.slots) do
                if type(item) == "table" and item.itemId then
                    counts[item.itemId] = (counts[item.itemId] or 0) + (tonumber(item.count) or 1)
                end
            end
        end
    end
end

local function CountItemInSnapshot(snapshot, itemId)
    if type(snapshot) ~= "table" then return 0 end
    if type(snapshot.counts) ~= "table" then RebuildSnapshotCounts(snapshot) end
    return tonumber(snapshot.counts[itemId] or 0) or 0
end

function WowNote_ItemSnapshots_GetCurrentCharacterCount(itemId, includeBank)
    InitDB()
    itemId = tonumber(itemId)
    if not itemId then return 0 end
    local realm = RealmName()
    local char = CharacterName()
    local total = 0
    if WowNoteDB.inventorySnapshots[realm] then
        total = total + CountItemInSnapshot(WowNoteDB.inventorySnapshots[realm][char], itemId)
    end
    if includeBank and WowNoteDB.bankSnapshots[realm] then
        total = total + CountItemInSnapshot(WowNoteDB.bankSnapshots[realm][char], itemId)
    end
    return total
end

function WowNote_ItemSnapshots_GetAccountCount(itemId)
    InitDB()
    itemId = tonumber(itemId)
    if not itemId then return 0 end
    local total = 0
    for _, chars in pairs(WowNoteDB.inventorySnapshots) do
        if type(chars) == "table" then
            for _, snapshot in pairs(chars) do total = total + CountItemInSnapshot(snapshot, itemId) end
        end
    end
    for _, chars in pairs(WowNoteDB.bankSnapshots) do
        if type(chars) == "table" then
            for _, snapshot in pairs(chars) do total = total + CountItemInSnapshot(snapshot, itemId) end
        end
    end
    return total
end

function WowNote_ItemSnapshots_CountTracked(itemId, mode)
    if mode == "account" then
        return WowNote_ItemSnapshots_GetAccountCount(itemId)
    end
    return WowNote_ItemSnapshots_GetCurrentCharacterCount(itemId, true)
end

function WowNote_ItemSnapshots_ScanNow()
    pendingBagScan = false
    pendingBankScan = false
    bagScanDueAt = nil
    bankScanDueAt = nil
    scheduler:Hide()
    ScanInventoryNow()
    if isBankOpen then ScanBankNow() end
end

function WowNote_ItemSnapshots_RequestScan(immediate, includeBank)
    Schedule("bags", immediate == true)
    if includeBank and isBankOpen then Schedule("bank", immediate == true) end
end

function WowNote_ItemSnapshots_GetScanInterval()
    return INVENTORY_SCAN_INTERVAL
end

function WowNote_ItemSnapshots_IsBankOpen()
    return isBankOpen
end

function WowNote_ItemSnapshots_ExtractItemId(link)
    return ExtractItemId(link)
end
