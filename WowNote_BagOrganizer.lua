-- WowNote_BagOrganizer.lua
-- Manual bag sorting with protected-item awareness. Protected items are not protected
-- from movement; protection only blocks sell/delete. Reserved slots are authoritative:
-- they must contain their reserved item or stay empty whenever there is free bag space.

local MODULE_NAME = "WowNote Bag Organizer"
local VERSION = "1.15.58"

BINDING_NAME_WOWNOTE_BAG_RESERVE_HOVER = "Reserve hovered bag slot for current item"
BINDING_NAME_WOWNOTE_BAG_CLEAR_HOVER = "Clear hovered bag slot reservation"

local BAG_IDS = { 0, 1, 2, 3, 4 }
local SORT_INTERVAL = 0.18
local button
local workerFrame
local pendingPlan
local currentMoveIndex = 0
local isSorting = false
local lastStatus = "Idle"

local reserveUpdateFrame
local reserveUpdatePending = false
local reserveCustomScanPending = false
local reserveButtonPool = {}

local function EnsureDB()
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.bagOrganizer) ~= "table" then WowNoteCharDB.bagOrganizer = {} end
    local db = WowNoteCharDB.bagOrganizer
    if type(db.slotRules) ~= "table" then db.slotRules = {} end
    if db.showReserveButtons == nil then db.showReserveButtons = false end
    if db.sortDirection ~= "bottom" then db.sortDirection = "top" end
    return db
end

local function SafeCallMethod(object, methodName, ...)
    if type(object) ~= "table" then return nil end
    local method = object[methodName]
    if type(method) ~= "function" then return nil end
    local ok, a, b, c = pcall(method, object, ...)
    if ok then return a, b, c end
    return nil
end


local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function Trim(text)
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function Lower(text)
    return string.lower(Trim(text or ""))
end

local function NormalizeSortDirection(direction)
    local value = Lower(direction or "")
    if value == "bottom" or value == "down" or value == "unten" or value == "reverse" or value == "reversed" then
        return "bottom"
    end
    return "top"
end

local function GetSortDirection()
    local db = EnsureDB()
    return db.sortDirection == "bottom" and "bottom" or "top"
end

function WowNote_BagOrganizer_GetSortDirection()
    return GetSortDirection()
end

function WowNote_BagOrganizer_SetSortDirection(direction, silent)
    local db = EnsureDB()
    db.sortDirection = NormalizeSortDirection(direction)
    if not silent then
        Print("Bag Organizer: sort direction set to " .. (db.sortDirection == "bottom" and "bottom" or "top") .. ".")
    end
    return db.sortDirection
end

function WowNote_BagOrganizer_ToggleSortDirection()
    local nextDirection = GetSortDirection() == "bottom" and "top" or "bottom"
    return WowNote_BagOrganizer_SetSortDirection(nextDirection)
end

local function IsCallable(value)
    return type(value) == "function"
end

local function IsShownFrame(frame)
    return type(frame) == "table" and IsCallable(frame.IsShown) and frame:IsShown()
end

local function GetSlotKey(bag, slot)
    return tostring(bag) .. ":" .. tostring(slot)
end

local function ExtractItemId(itemLink)
    if not itemLink then return nil end
    return tonumber(string.match(tostring(itemLink), "item:(%d+):")) or tonumber(tostring(itemLink))
end


local function ExtractItemName(itemLink)
    if not itemLink then return "" end
    return string.match(tostring(itemLink), "%[(.-)%]") or tostring(itemLink or "")
end

local function NormalizeRule(rule)
    if type(rule) ~= "table" then return nil end
    if type(rule.allowed) ~= "table" then rule.allowed = {} end
    -- Older development builds may have stored a simple numeric/string array.
    local index
    for index = 1, table.getn(rule) do
        local value = rule[index]
        if value ~= nil then
            table.insert(rule.allowed, { id = tonumber(value), name = tonumber(value) and nil or tostring(value) })
            rule[index] = nil
        end
    end
    rule.keepEmpty = rule.keepEmpty ~= false
    return rule
end

local function GetSlotRule(bag, slot)
    local db = EnsureDB()
    local rule = db.slotRules[GetSlotKey(bag, slot)]
    return NormalizeRule(rule)
end

local function RuleHasEntries(rule)
    return type(rule) == "table" and type(rule.allowed) == "table" and table.getn(rule.allowed) > 0
end

local function RuleEntryMatchesItem(entry, item)
    if type(entry) ~= "table" or type(item) ~= "table" then return false end
    local entryId = tonumber(entry.id)
    if entryId and item.itemId and tonumber(item.itemId) == entryId then return true end
    local entryName = Lower(entry.name or entry.link or "")
    if entryName ~= "" and item.lowerName == entryName then return true end
    if entryName ~= "" and item.link and Lower(item.link) == entryName then return true end
    return false
end

local function RuleAllowsItem(rule, item)
    if not RuleHasEntries(rule) then return false end
    local i
    for i = 1, table.getn(rule.allowed) do
        if RuleEntryMatchesItem(rule.allowed[i], item) then return true end
    end
    return false
end

local function FindPreferredItemForRule(rule, items, assigned)
    if not RuleHasEntries(rule) then return nil end
    local ruleIndex
    for ruleIndex = 1, table.getn(rule.allowed) do
        local entry = rule.allowed[ruleIndex]
        local itemIndex
        for itemIndex = 1, table.getn(items) do
            local item = items[itemIndex]
            if item and not assigned[item] and RuleEntryMatchesItem(entry, item) then
                assigned[item] = true
                return item
            end
        end
    end
    return nil
end

local function AddItemToSlotRule(bag, slot, itemId, itemLink, itemName)
    local db = EnsureDB()
    local key = GetSlotKey(bag, slot)
    local rule = NormalizeRule(db.slotRules[key])
    if not rule then
        rule = { allowed = {}, keepEmpty = true }
        db.slotRules[key] = rule
    end
    local id = tonumber(itemId) or ExtractItemId(itemLink)
    local name = itemName or ExtractItemName(itemLink)
    local lowerName = Lower(name or "")
    local i
    for i = 1, table.getn(rule.allowed) do
        local entry = rule.allowed[i]
        if entry then
            if id and tonumber(entry.id) == id then return false, "already" end
            if not id and lowerName ~= "" and Lower(entry.name or entry.link or "") == lowerName then return false, "already" end
        end
    end
    table.insert(rule.allowed, { id = id, name = name, link = itemLink, addedAt = time and time() or nil })
    rule.keepEmpty = true
    rule.updatedAt = time and time() or nil
    return true, key
end

local function ReserveEmptySlot(bag, slot)
    local db = EnsureDB()
    local key = GetSlotKey(bag, slot)
    local rule = NormalizeRule(db.slotRules[key])
    if not rule then
        rule = { allowed = {}, keepEmpty = true }
        db.slotRules[key] = rule
    end
    rule.keepEmpty = true
    rule.updatedAt = time and time() or nil
    return true, key
end

local function ClearSlotRule(bag, slot)
    local db = EnsureDB()
    local key = GetSlotKey(bag, slot)
    if db.slotRules[key] then
        db.slotRules[key] = nil
        return true
    end
    return false
end

local function FormatRuleText(rule)
    if not rule then return "No reservation" end
    if not RuleHasEntries(rule) then return "Reserved empty slot" end
    local parts = {}
    local i
    for i = 1, table.getn(rule.allowed) do
        local entry = rule.allowed[i]
        if entry then
            table.insert(parts, tostring(entry.name or entry.link or entry.id or "?"))
        end
    end
    return table.concat(parts, " > ")
end

local function GetItemIdFromSlot(bag, slot, link)
    local itemId = ExtractItemId(link)
    if itemId then return itemId end
    if GetContainerItemID then
        return GetContainerItemID(bag, slot)
    end
    return nil
end

local function GetSlotLink(bag, slot)
    if not GetContainerItemLink then return nil end
    return GetContainerItemLink(bag, slot)
end

local function GetSlotInfo(bag, slot)
    if not GetContainerItemInfo then return nil end
    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    if not texture then return nil end
    return texture, count, locked, quality
end

local function IsSlotLocked(bag, slot)
    local _, _, locked = GetSlotInfo(bag, slot)
    return locked and true or false
end

local function IsProtectedSlot(bag, slot)
    if WowNote_IsBagSlotProtected and WowNote_IsBagSlotProtected(bag, slot) then return true end
    local link = GetSlotLink(bag, slot)
    if link and WowNote_IsItemProtected and WowNote_IsItemProtected(link) then return true end
    return false
end

local function IsItemDataProtected(item)
    if type(item) ~= "table" then return false end
    if item.protected then return true end
    if WowNote_IsItemProtected and item.link and WowNote_IsItemProtected(item.link) then return true end
    return false
end

local function AnyRuleAllowsItem(rules, item)
    if type(rules) ~= "table" or type(item) ~= "table" then return false end
    local i
    for i = 1, table.getn(rules) do
        if RuleAllowsItem(rules[i], item) then return true end
    end
    return false
end

local function IsUnsafeContext()
    if InCombatLockdown and InCombatLockdown() then return "combat" end
    if CursorHasItem and CursorHasItem() then return "cursor" end
    if IsShownFrame(MerchantFrame) then return "merchant" end
    if IsShownFrame(MailFrame) then return "mail" end
    if IsShownFrame(TradeFrame) then return "trade" end
    if IsShownFrame(AuctionFrame) then return "auction" end
    if IsShownFrame(LootFrame) then return "loot" end
    return nil
end

local CLASS_ORDER = {
    ["Quest"] = 10,
    ["Consumable"] = 20,
    ["Glyph"] = 25,
    ["Trade Goods"] = 30,
    ["Recipe"] = 40,
    ["Gem"] = 45,
    ["Armor"] = 50,
    ["Weapon"] = 55,
    ["Projectile"] = 60,
    ["Quiver"] = 61,
    ["Container"] = 70,
    ["Miscellaneous"] = 90,
}

local function BuildItemSortData(bag, slot, link, count, quality)
    local itemId = GetItemIdFromSlot(bag, slot, link) or 0
    local name = ""
    local itemQuality = quality or 0
    local itemLevel = 0
    local itemType = ""
    local itemSubType = ""
    local equipLoc = ""
    local stackCount = 1
    if GetItemInfo and link then
        local infoName, itemLink, infoQuality, infoLevel, minLevel, infoType, infoSubType, infoStackCount, infoEquipLoc = GetItemInfo(link)
        name = infoName or ""
        itemQuality = infoQuality or itemQuality or 0
        itemLevel = infoLevel or 0
        itemType = infoType or ""
        itemSubType = infoSubType or ""
        equipLoc = infoEquipLoc or ""
        stackCount = infoStackCount or 1
    end
    if name == "" and link then
        name = string.match(link, "%[(.-)%]") or tostring(link)
    end
    local classRank = CLASS_ORDER[itemType] or 80
    local equipRank = equipLoc ~= "" and 1 or 9
    return {
        bag = bag,
        slot = slot,
        key = GetSlotKey(bag, slot),
        link = link,
        itemId = itemId,
        name = name,
        lowerName = Lower(name),
        count = count or 1,
        quality = itemQuality or 0,
        itemLevel = itemLevel or 0,
        itemType = itemType,
        itemSubType = itemSubType,
        lowerType = Lower(itemType),
        lowerSubType = Lower(itemSubType),
        equipLoc = equipLoc,
        equipRank = equipRank,
        classRank = classRank,
        stackCount = stackCount or 1,
    }
end

local function CompareItems(a, b)
    if a.classRank ~= b.classRank then return a.classRank < b.classRank end
    if a.lowerType ~= b.lowerType then return a.lowerType < b.lowerType end
    if a.lowerSubType ~= b.lowerSubType then return a.lowerSubType < b.lowerSubType end
    if a.equipRank ~= b.equipRank then return a.equipRank < b.equipRank end
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
    if a.lowerName ~= b.lowerName then return a.lowerName < b.lowerName end
    if a.itemId ~= b.itemId then return a.itemId < b.itemId end
    if a.count ~= b.count then return a.count > b.count end
    return a.key < b.key
end

local function CompareSlots(a, b)
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

local function SortSlotsByDirection(slots)
    table.sort(slots, CompareSlots)
    if GetSortDirection() == "bottom" then
        local reversed = {}
        local i
        for i = table.getn(slots), 1, -1 do
            table.insert(reversed, slots[i])
        end
        return reversed
    end
    return slots
end

local function BuildSortPlan(options)
    options = options or {}
    if not GetContainerNumSlots or not GetContainerItemInfo or not PickupContainerItem then
        return nil, "missing bag API"
    end

    local unsafe = IsUnsafeContext()
    if unsafe then return nil, unsafe end

    local slots = {}
    local items = {}
    local currentByKey = {}
    local locationByItem = {}
    local protectedCount = 0
    local reservedCount = 0
    local rules = {}

    local bagIndex
    for bagIndex = 1, table.getn(BAG_IDS) do
        local bag = BAG_IDS[bagIndex]
        local slotCount = GetContainerNumSlots(bag) or 0
        local slot
        for slot = 1, slotCount do
            local locked = IsSlotLocked(bag, slot)
            if not locked then
                local key = GetSlotKey(bag, slot)
                local rule = GetSlotRule(bag, slot)
                local isProtected = IsProtectedSlot(bag, slot)
                if isProtected then protectedCount = protectedCount + 1 end
                if rule then
                    reservedCount = reservedCount + 1
                    table.insert(rules, rule)
                end

                local slotInfoTexture, count, _, quality = GetSlotInfo(bag, slot)
                local item = nil
                if slotInfoTexture then
                    local link = GetSlotLink(bag, slot)
                    item = BuildItemSortData(bag, slot, link, count, quality)
                    item.protected = isProtected
                    table.insert(items, item)
                    currentByKey[key] = item
                    locationByItem[item] = key
                else
                    currentByKey[key] = nil
                end

                -- Every unlocked bag slot participates in the plan. Protected items
                -- are allowed to move; their protection only applies to sell/delete.
                -- Reserved slots are authoritative and are filled first or kept empty.
                table.insert(slots, { bag = bag, slot = slot, key = key, rule = rule, protected = isProtected })
            end
        end
    end

    slots = SortSlotsByDirection(slots)
    table.sort(items, CompareItems)

    local desiredByKey = {}
    local assigned = {}
    local itemDesiredKey = {}
    local freeSlots = {}
    local reservedSlots = {}
    local i
    for i = 1, table.getn(slots) do
        local slotEntry = slots[i]
        if slotEntry.rule then
            table.insert(reservedSlots, slotEntry)
        else
            -- Free slots are needed even for reserved-only sorting so wrong
            -- occupants can be moved out of reserved slots.
            table.insert(freeSlots, slotEntry)
        end
    end

    -- Reserved slots are authoritative: they are filled before normal sorting.
    -- If no allowed item exists for a reserved slot, the desired state is empty.
    for i = 1, table.getn(reservedSlots) do
        local slotEntry = reservedSlots[i]
        local preferred = FindPreferredItemForRule(slotEntry.rule, items, assigned)
        desiredByKey[slotEntry.key] = preferred
        if preferred then itemDesiredKey[preferred] = slotEntry.key end
    end

    local remainingItems = {}
    for i = 1, table.getn(items) do
        local item = items[i]
        -- Protected items are valid sorting candidates. Protection only blocks
        -- selling/deleting, not movement inside bags.
        if item and not assigned[item] then
            table.insert(remainingItems, item)
        end
    end

    if table.getn(remainingItems) > table.getn(freeSlots) then
        return nil, "not enough free slots to keep reserved slots empty"
    end

    if not options.reservedOnly then
        table.sort(remainingItems, CompareItems)
    end

    -- Even reserved-only sorting needs spillover destinations so wrong items can
    -- be moved out of reserved slots. In reserved-only mode the current bag order
    -- is kept for all non-reserved items instead of applying the full item sort.
    for i = 1, table.getn(freeSlots) do
        desiredByKey[freeSlots[i].key] = remainingItems[i]
        if remainingItems[i] then itemDesiredKey[remainingItems[i]] = freeSlots[i].key end
    end

    local moves = {}
    for i = 1, table.getn(slots) do
        local dest = slots[i]
        local desired = desiredByKey[dest.key]
        local current = currentByKey[dest.key]
        if desired and current ~= desired then
            local srcKey = locationByItem[desired]
            if srcKey and srcKey ~= dest.key then
                local srcBag, srcSlot = string.match(srcKey, "^(%-?%d+):(%d+)$")
                srcBag = tonumber(srcBag)
                srcSlot = tonumber(srcSlot)
                if srcBag and srcSlot then
                    table.insert(moves, {
                        srcBag = srcBag,
                        srcSlot = srcSlot,
                        dstBag = dest.bag,
                        dstSlot = dest.slot,
                        reservedMove = dest.rule and true or false,
                    })
                    local srcCurrent = currentByKey[srcKey]
                    local dstCurrentAfter = currentByKey[dest.key]
                    currentByKey[dest.key] = srcCurrent
                    currentByKey[srcKey] = dstCurrentAfter
                    if srcCurrent then locationByItem[srcCurrent] = dest.key end
                    if dstCurrentAfter then locationByItem[dstCurrentAfter] = srcKey end
                end
            end
        end
    end

    return {
        moves = moves,
        totalItems = table.getn(items),
        protectedCount = protectedCount,
        reservedCount = reservedCount,
        slotCount = table.getn(slots),
        reservedOnly = options.reservedOnly == true,
        sortDirection = GetSortDirection(),
    }
end

local function FinishSorting(message)
    isSorting = false
    pendingPlan = nil
    currentMoveIndex = 0
    if workerFrame then workerFrame:SetScript("OnUpdate", nil) end
    lastStatus = message or "Idle"
    if button and button.text then button.text:SetText("Sort") end
    Print(lastStatus)
end

local function ExecuteMove(move)
    if not move then return true end
    -- Protected items may be moved by the organizer. ItemProtection still
    -- protects them from selling/deleting; it must not lock sorting movement.
    if IsSlotLocked(move.srcBag, move.srcSlot) or IsSlotLocked(move.dstBag, move.dstSlot) then
        return false
    end
    if CursorHasItem and CursorHasItem() then
        return nil, "cursor not empty"
    end
    PickupContainerItem(move.srcBag, move.srcSlot)
    if CursorHasItem and CursorHasItem() then
        PickupContainerItem(move.dstBag, move.dstSlot)
    end
    if CursorHasItem and CursorHasItem() then
        -- Failed move. Try to put the item back into its source slot and abort.
        PickupContainerItem(move.srcBag, move.srcSlot)
        return nil, "move failed"
    end
    return true
end

local function StartWorker()
    if not pendingPlan or table.getn(pendingPlan.moves or {}) == 0 then
        FinishSorting("Bag Organizer: reserved slots already match their rules; protected items may move during sorting.")
        return
    end
    if not workerFrame then workerFrame = CreateFrame("Frame") end
    local elapsedTotal = 0
    workerFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedTotal = elapsedTotal + (elapsed or 0)
        if elapsedTotal < SORT_INTERVAL then return end
        elapsedTotal = 0

        local unsafe = IsUnsafeContext()
        if unsafe then
            FinishSorting("Bag Organizer stopped: unsafe context (" .. tostring(unsafe) .. ").")
            return
        end

        currentMoveIndex = currentMoveIndex + 1
        local move = pendingPlan.moves[currentMoveIndex]
        if not move then
            FinishSorting("Bag Organizer: sorted " .. tostring(pendingPlan.totalItems or 0) .. " items; reserved slots enforced: " .. tostring(pendingPlan.reservedCount or 0) .. "; protected items: " .. tostring(pendingPlan.protectedCount or 0) .. "; direction: " .. tostring(pendingPlan.sortDirection or "top") .. ".")
            return
        end

        local ok, reason = ExecuteMove(move)
        if ok == false then
            -- Slot is locked. Retry the same move on the next tick.
            currentMoveIndex = currentMoveIndex - 1
            return
        elseif ok == nil then
            FinishSorting("Bag Organizer stopped: " .. tostring(reason or "move failed") .. ".")
            return
        end

        if button and button.text then
            button.text:SetText(tostring(currentMoveIndex) .. "/" .. tostring(table.getn(pendingPlan.moves or {})))
        end
    end)
end

local function StartSortPlan(options, label)
    if isSorting then
        FinishSorting("Bag Organizer: sorting cancelled.")
        return
    end
    local plan, reason = BuildSortPlan(options)
    if not plan then
        Print("Bag Organizer cannot sort now: " .. tostring(reason or "unknown reason") .. ".")
        return
    end
    if table.getn(plan.moves or {}) == 0 then
        Print("Bag Organizer: already sorted. Protected items: " .. tostring(plan.protectedCount or 0) .. "; reserved slots: " .. tostring(plan.reservedCount or 0) .. "; direction: " .. tostring(plan.sortDirection or "top") .. ".")
        return
    end
    pendingPlan = plan
    currentMoveIndex = 0
    isSorting = true
    if button and button.text then button.text:SetText("0/" .. tostring(table.getn(plan.moves))) end
    Print("Bag Organizer: " .. tostring(label or "sorting bags") .. " with " .. tostring(table.getn(plan.moves)) .. " moves. Protected items: " .. tostring(plan.protectedCount or 0) .. "; reserved slots: " .. tostring(plan.reservedCount or 0) .. "; direction: " .. tostring(plan.sortDirection or "top") .. ".")
    StartWorker()
end

function WowNote_BagOrganizer_SortBags()
    StartSortPlan({ reservedOnly = false }, "sorting bags")
end

function WowNote_BagOrganizer_SortReservedSlots()
    StartSortPlan({ reservedOnly = true }, "sorting reserved/protected slots")
end

function WowNote_BagOrganizer_IsSorting()
    return isSorting == true
end

function WowNote_BagOrganizer_GetStatus()
    return lastStatus or "Idle"
end



local function IsValidBagSlot(bag, slot)
    bag = tonumber(bag)
    slot = tonumber(slot)
    if not bag or not slot then return false end
    if bag < 0 or bag > 4 or slot < 1 then return false end
    if GetContainerNumSlots then
        local maxSlots = GetContainerNumSlots(bag) or 0
        if maxSlots > 0 then return slot <= maxSlots end
    end
    return slot <= 40
end

local function GetBagSlotFromButton(button)
    if type(button) ~= "table" then return nil, nil end
    local parent = SafeCallMethod(button, "GetParent")
    local bag, slot
    if type(parent) == "table" and type(parent.GetID) == "function" then bag = parent:GetID() end
    if type(button.GetID) == "function" then slot = button:GetID() end
    bag = button.bagID or button.BagID or button.bag or button.Bag or button.bagId or button.BagId or bag
    slot = button.slotID or button.SlotID or button.slot or button.Slot or button.slotId or button.SlotId or slot
    if (not bag or not slot) and type(parent) == "table" then
        bag = bag or parent.bagID or parent.BagID or parent.bag or parent.Bag or parent.bagId or parent.BagId
        slot = slot or parent.slotID or parent.SlotID or parent.slot or parent.Slot or parent.slotId or parent.SlotId
    end
    bag = tonumber(bag)
    slot = tonumber(slot)
    if not IsValidBagSlot(bag, slot) then return nil, nil end
    return bag, slot
end

function WowNote_BagOrganizer_ReserveSlot(bag, slot)
    bag = tonumber(bag)
    slot = tonumber(slot)
    if not bag or not slot then
        Print("Bag Organizer: cannot resolve bag slot.")
        return false
    end
    local link = GetSlotLink(bag, slot)
    local itemId = GetItemIdFromSlot(bag, slot, link)
    if itemId or link then
        local added = AddItemToSlotRule(bag, slot, itemId, link, ExtractItemName(link))
        if added then
            Print("Bag Organizer: reserved slot " .. tostring(bag) .. ":" .. tostring(slot) .. " for " .. tostring(ExtractItemName(link) or itemId) .. ".")
        else
            Print("Bag Organizer: this item is already allowed on slot " .. tostring(bag) .. ":" .. tostring(slot) .. ".")
        end
    else
        ReserveEmptySlot(bag, slot)
        Print("Bag Organizer: reserved empty slot " .. tostring(bag) .. ":" .. tostring(slot) .. ".")
    end
    WowNote_BagOrganizer_UpdateReserveButtons()
    return true
end

function WowNote_BagOrganizer_ClearSlotReservation(bag, slot)
    bag = tonumber(bag)
    slot = tonumber(slot)
    if not bag or not slot then return false end
    if ClearSlotRule(bag, slot) then
        Print("Bag Organizer: cleared reservation for slot " .. tostring(bag) .. ":" .. tostring(slot) .. ".")
        WowNote_BagOrganizer_UpdateReserveButtons()
        return true
    end
    Print("Bag Organizer: slot " .. tostring(bag) .. ":" .. tostring(slot) .. " has no reservation.")
    return false
end

local function GetHoveredBagSlot()
    if not GetMouseFocus then return nil, nil end
    local frame = GetMouseFocus()
    local seen = 0
    while type(frame) == "table" and seen < 8 do
        local bag, slot = GetBagSlotFromButton(frame)
        if bag and slot then return bag, slot end
        if type(frame.GetParent) ~= "function" then break end
        frame = frame:GetParent()
        seen = seen + 1
    end
    return nil, nil
end

function WowNote_BagOrganizer_ReserveHoveredSlot(clearReservation)
    local bag, slot = GetHoveredBagSlot()
    if not bag or not slot then
        Print("Bag Organizer: hover a real bag slot first, then press the keybinding.")
        return false
    end
    if clearReservation then
        return WowNote_BagOrganizer_ClearSlotReservation(bag, slot)
    end
    return WowNote_BagOrganizer_ReserveSlot(bag, slot)
end

function WOWNOTE_BAG_RESERVE_HOVER()
    return WowNote_BagOrganizer_ReserveHoveredSlot(false)
end

function WOWNOTE_BAG_CLEAR_HOVER()
    return WowNote_BagOrganizer_ReserveHoveredSlot(true)
end

local function ScanBagsForItemId(itemId)
    itemId = tonumber(itemId)
    if not itemId or not GetContainerNumSlots then return nil, nil end
    local bagIndex
    for bagIndex = 1, table.getn(BAG_IDS) do
        local bag = BAG_IDS[bagIndex]
        local maxSlots = GetContainerNumSlots(bag) or 0
        local slot
        for slot = 1, maxSlots do
            local currentId = GetItemIdFromSlot(bag, slot, GetSlotLink(bag, slot))
            if tonumber(currentId) == itemId then return bag, slot end
        end
    end
    return nil, nil
end

local function AddEquipmentSetIds(target)
    if not GetNumEquipmentSets or not GetEquipmentSetInfo or not GetEquipmentSetItemIDs then return 0 end
    local count = 0
    local numSets = GetNumEquipmentSets() or 0
    local index
    for index = 1, numSets do
        local name, icon, setID = GetEquipmentSetInfo(index)
        local ok, ids = pcall(GetEquipmentSetItemIDs, name)
        if not ok or type(ids) ~= "table" then ok, ids = pcall(GetEquipmentSetItemIDs, setID) end
        if ok and type(ids) == "table" then
            for _, itemId in pairs(ids) do
                itemId = tonumber(itemId)
                if itemId and itemId > 0 and not target[itemId] then
                    target[itemId] = true
                    count = count + 1
                end
            end
        end
    end
    return count
end

function WowNote_BagOrganizer_ReserveEquipmentSetSlots()
    local ids = {}
    local setItemCount = AddEquipmentSetIds(ids)
    if setItemCount <= 0 then
        Print("Bag Organizer: no Equipment Manager set items found.")
        return 0
    end
    local reserved = 0
    local missing = 0
    for itemId in pairs(ids) do
        local bag, slot = ScanBagsForItemId(itemId)
        if bag and slot then
            local link = GetSlotLink(bag, slot)
            local added = AddItemToSlotRule(bag, slot, itemId, link, ExtractItemName(link))
            if added then reserved = reserved + 1 end
        else
            missing = missing + 1
        end
    end
    WowNote_BagOrganizer_UpdateReserveButtons()
    Print("Bag Organizer: reserved " .. tostring(reserved) .. " current set item slot(s); " .. tostring(missing) .. " set item(s) not found in bags.")
    return reserved, missing
end

local function HideAllReserveButtons()
    local i
    for i = 1, table.getn(reserveButtonPool) do
        local reserveButton = reserveButtonPool[i]
        if reserveButton and type(reserveButton.Hide) == "function" then reserveButton:Hide() end
    end
end

-- v1.15.54: visible per-slot R buttons were removed. They caused false
-- positives on non-bag frames such as HealBot and PallyBuffs. Slot reservation
-- now uses the normal WoW keybinding WOWNOTE_BAG_RESERVE_HOVER while the
-- mouse is hovering a real bag slot. Keep these no-op functions so older calls
-- and saved settings cannot recreate overlay buttons.
function WowNote_BagOrganizer_UpdateReserveButtons(includeCustomScan)
    HideAllReserveButtons()
end

local function QueueReserveButtonUpdate(includeCustomScan, delay)
    HideAllReserveButtons()
end


local function AnchorBagButton()
    if not button then return end
    button:ClearAllPoints()
    if MainMenuBarBackpackButton then
        button:SetPoint("BOTTOMRIGHT", MainMenuBarBackpackButton, "TOPRIGHT", 0, 2)
    elseif CharacterBag0Slot then
        button:SetPoint("BOTTOMRIGHT", CharacterBag0Slot, "TOPRIGHT", 0, 2)
    else
        button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -220, 120)
    end
end

local function CreateBagButton()
    if button then return button end
    button = CreateFrame("Button", "WowNoteBagOrganizerSortButton", UIParent)
    button:SetWidth(30)
    button:SetHeight(30)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(50)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    button.border:SetAllPoints(button)

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:SetText("Sort")
    button.text:SetTextColor(1, 0.82, 0)

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Print("Bag Organizer: Left-click sorts bags. Use the keybinding \"Reserve hovered bag slot\" while hovering a bag slot to reserve it. Reserved slots are enforced first; protected items may move during sorting. Current direction: " .. tostring(GetSortDirection()) .. ".")
            return
        end
        WowNote_BagOrganizer_SortBags()
    end)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("WowNote Bag Sort", 1, 0.82, 0)
            GameTooltip:AddLine("Left-click: sort bags like a lightweight bag sort.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("Reserved slots are enforced first. Protected items may move; reserved slots are kept with their reserved item or empty.", 0.1, 1, 0.1, true)
            GameTooltip:AddLine("Keybinding: Reserve hovered bag slot. Default: R, changeable in WoW Key Bindings.", 0.7, 0.9, 1, true)
            GameTooltip:AddLine("Sort direction: " .. tostring(GetSortDirection()) .. " (toggle in Settings or Titan menu).", 0.8, 0.8, 1, true)
            GameTooltip:AddLine("Does not run during combat, merchant, mail, trade, auction or loot windows.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    AnchorBagButton()
    button:Show()
    return button
end

local TITAN_SORT_ID = "WowNoteBagSort"

function TitanPanelWowNoteBagSortButton_GetButtonText(id)
    return "WN Sort", TitanUtils_GetHighlightText(isSorting and "..." or "")
end

function TitanPanelWowNoteBagSortButton_GetTooltipText()
    return "Protected-safe bag sort\n" ..
        "Left-click: " .. TitanUtils_GetHighlightText("sort bags") .. "\n" ..
        "Reserved slots: " .. TitanUtils_GetHighlightText("reserved item or empty") .. "\n" ..
        "Direction: " .. TitanUtils_GetHighlightText(GetSortDirection()) .. "\n" ..
        "Keybind: " .. TitanUtils_GetHighlightText("reserve hovered bag slot, default R") .. "\n" ..
        "Slash: " .. TitanUtils_GetHighlightText("/wn bagsort")
end

function TitanPanelRightClickMenu_PrepareWowNoteBagSortMenu()
    local hideText = TITAN_PANEL_MENU_HIDE or "Hide"
    TitanPanelRightClickMenu_AddTitle("WowNote Bag Sort")
    TitanPanelRightClickMenu_AddCommand("Sort bags now", TITAN_SORT_ID, "WowNote_BagOrganizer_SortBags")
    TitanPanelRightClickMenu_AddCommand("Sort reserved/protected slots", TITAN_SORT_ID, "WowNote_BagOrganizer_SortReservedSlots")
    TitanPanelRightClickMenu_AddCommand("Reserve hovered slot", TITAN_SORT_ID, "WOWNOTE_BAG_RESERVE_HOVER")
    TitanPanelRightClickMenu_AddCommand("Clear hovered slot reservation", TITAN_SORT_ID, "WOWNOTE_BAG_CLEAR_HOVER")
    TitanPanelRightClickMenu_AddCommand("Reserve current set slots", TITAN_SORT_ID, "WowNote_BagOrganizer_ReserveEquipmentSetSlots")
    TitanPanelRightClickMenu_AddCommand("Toggle direction: " .. (GetSortDirection() == "bottom" and "Bottom" or "Top"), TITAN_SORT_ID, "WowNote_BagOrganizer_ToggleSortDirection")
    TitanPanelRightClickMenu_AddSpacer()
    TitanPanelRightClickMenu_AddToggleIcon(TITAN_SORT_ID)
    TitanPanelRightClickMenu_AddToggleLabelText(TITAN_SORT_ID)
    TitanPanelRightClickMenu_AddSpacer()
    TitanPanelRightClickMenu_AddCommand(hideText, TITAN_SORT_ID, TITAN_PANEL_MENU_FUNC_HIDE)
end

function TitanPanelWowNoteBagSortButton_OnLoad(self)
    self.registry = {
        id = TITAN_SORT_ID,
        menuText = "WowNote Bag Sort",
        version = VERSION,
        category = "Interface",
        buttonTextFunction = "TitanPanelWowNoteBagSortButton_GetButtonText",
        tooltipTitle = "WowNote Bag Sort",
        tooltipTextFunction = "TitanPanelWowNoteBagSortButton_GetTooltipText",
        icon = "Interface\\Icons\\INV_Misc_Bag_10",
        iconWidth = 16,
        savedVariables = {
            ShowIcon = 1,
            ShowLabelText = 1,
            DisplayOnRightSide = false,
        },
        controlVariables = {
            ShowIcon = true,
            ShowLabelText = true,
            DisplayOnRightSide = true,
        },
    }
end

local function CreateTitanBagSortPlugin()
    if not TitanPanelButton_OnLoad then return end
    if _G and _G["TitanPanelWowNoteBagSortButton"] then return end
    local ok, titanButton = pcall(CreateFrame, "Button", "TitanPanelWowNoteBagSortButton", UIParent, "TitanPanelComboTemplate")
    if ok and titanButton then
        TitanPanelWowNoteBagSortButton_OnLoad(titanButton)
        TitanPanelButton_OnLoad(titanButton)
        titanButton:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "LeftButton" then
                WowNote_BagOrganizer_SortBags()
            elseif TitanPanelButton_OnClick then
                TitanPanelButton_OnClick(self, mouseButton)
            end
        end)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        CreateBagButton()
        CreateTitanBagSortPlugin()
        HideAllReserveButtons()
    end
end)

-- If the file is loaded after PLAYER_LOGIN for any reason, still expose the sort button.
if IsLoggedIn and IsLoggedIn() then
    CreateBagButton()
    CreateTitanBagSortPlugin()
    HideAllReserveButtons()
end
