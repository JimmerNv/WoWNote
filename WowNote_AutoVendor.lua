local MODULE_NAME = "WowNote Auto Vendor"

local eventFrame
local summaryFrame
local pendingSellSummary
local tooltipScanner
local tooltipLines = {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg))
end

local function Trim(text)
    text = text or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function EnsureVendorDB()
    if type(WowNoteCharDB) ~= "table" then
        WowNoteCharDB = {}
    end
    if type(WowNoteCharDB.autoVendor) ~= "table" then
        WowNoteCharDB.autoVendor = {}
    end

    local settings = WowNoteCharDB.autoVendor
    if settings.sellEnabled == nil then settings.sellEnabled = false end
    if settings.sellGray == nil then settings.sellGray = true end
    if settings.sellWeapons == nil then settings.sellWeapons = false end
    if settings.sellArmor == nil then settings.sellArmor = false end
    if settings.sellEquipmentMaxQuality == nil then settings.sellEquipmentMaxQuality = 1 end
    if settings.useEquipmentMaxItemLevel == nil then settings.useEquipmentMaxItemLevel = false end
    if settings.equipmentMaxItemLevel == nil then settings.equipmentMaxItemLevel = 200 end
    if settings.printSellSummary == nil then settings.printSellSummary = true end
    if settings.forceSell == nil then settings.forceSell = "" end
    if settings.neverSell == nil then settings.neverSell = "" end
    if settings.quickAddEnabled == nil then settings.quickAddEnabled = true end
    if settings.quickAddModifier == nil then settings.quickAddModifier = "ALT" end
    if settings.quickAddTarget == nil then settings.quickAddTarget = "force" end
    if settings.repairEnabled == nil then settings.repairEnabled = false end
    if settings.repairGuild == nil then settings.repairGuild = false end
    if settings.printRepairSummary == nil then settings.printRepairSummary = true end
    return settings
end

local function FormatMoney(copper)
    copper = tonumber(copper) or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperOnly = copper % 100
    if gold > 0 then
        return string.format("%dg %02ds %02dc", gold, silver, copperOnly)
    elseif silver > 0 then
        return string.format("%ds %02dc", silver, copperOnly)
    end
    return string.format("%dc", copperOnly)
end

local function ExtractItemId(itemLink)
    if not itemLink then return nil end
    return tonumber(string.match(itemLink, "item:(%d+):"))
end

local function ExtractBracketName(text)
    if not text then return nil end
    return string.match(text, "%[(.-)%]")
end

local function BuildListIndex(listText)
    local names = {}
    local ids = {}
    for rawLine in string.gmatch((listText or "") .. "\n", "(.-)\n") do
        local entry = Trim(rawLine)
        entry = string.gsub(entry, "^%-+%s*", "")
        if entry ~= "" then
            local id = ExtractItemId(entry) or tonumber(entry)
            if id then
                ids[id] = true
            end

            local bracketName = ExtractBracketName(entry)
            if bracketName and bracketName ~= "" then
                names[string.lower(Trim(bracketName))] = true
            elseif not tonumber(entry) and not ExtractItemId(entry) then
                names[string.lower(entry)] = true
            end
        end
    end
    return names, ids
end

local function MatchesList(item, names, ids)
    if not item then return false end
    if item.id and ids[item.id] then return true end
    local name = item.name and string.lower(Trim(item.name)) or ""
    return name ~= "" and names[name]
end

local function GetListSortKey(entry)
    local id = ExtractItemId(entry) or tonumber(Trim(entry))
    if id then return string.format("id:%010d", id) end
    local bracketName = ExtractBracketName(entry)
    if bracketName and bracketName ~= "" then return string.lower(Trim(bracketName)) end
    return string.lower(Trim(entry))
end

local function NormalizeListText(listText)
    local seen = {}
    local entries = {}
    for rawLine in string.gmatch((listText or "") .. "\n", "(.-)\n") do
        local entry = Trim(rawLine)
        entry = string.gsub(entry, "^%-+%s*", "")
        if entry ~= "" then
            local key = GetListSortKey(entry)
            if not seen[key] then
                seen[key] = true
                table.insert(entries, entry)
            end
        end
    end
    table.sort(entries, function(a, b) return GetListSortKey(a) < GetListSortKey(b) end)
    return table.concat(entries, "\n")
end

local function AddEntryToListText(listText, entry)
    entry = Trim(entry or "")
    if entry == "" then return NormalizeListText(listText) end
    local current = Trim(listText or "")
    if current ~= "" then
        current = current .. "\n" .. entry
    else
        current = entry
    end
    return NormalizeListText(current)
end

function WowNote_NormalizeAutoVendorList(listText)
    return NormalizeListText(listText)
end

function WowNote_AddAutoVendorListEntry(listName, entry)
    local settings = EnsureVendorDB()
    local key = listName == "never" and "neverSell" or "forceSell"
    settings[key] = AddEntryToListText(settings[key], entry)
    Print("Added " .. tostring(entry) .. " to " .. (key == "neverSell" and "Never Sell" or "Force Sell") .. ".")
    return settings[key]
end

function WowNote_GetAutoVendorListText(listName)
    local settings = EnsureVendorDB()
    return listName == "never" and (settings.neverSell or "") or (settings.forceSell or "")
end

local function EnsureTooltipScanner()
    if tooltipScanner then return tooltipScanner end
    tooltipScanner = CreateFrame("GameTooltip", "WowNoteAutoVendorTooltipScanner", UIParent, "GameTooltipTemplate")
    tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")
    for index = 1, 12 do
        tooltipLines[index] = _G["WowNoteAutoVendorTooltipScannerTextLeft" .. index]
    end
    return tooltipScanner
end

local function IsBindOnEquip(itemLink)
    if not itemLink then return false end
    local scanner = EnsureTooltipScanner()
    scanner:ClearLines()
    scanner:SetHyperlink(itemLink)

    local boeText = ITEM_BIND_ON_EQUIP or "Binds when equipped"
    for index = 1, scanner:NumLines() do
        local line = tooltipLines[index]
        local text = line and line:GetText()
        if text and text == boeText then
            return true
        end
    end
    return false
end

local function IsPrimordialSaronite(item)
    if not item then return false end
    if item.id == 49908 then return true end
    return string.lower(item.name or "") == "primordial saronite"
end

local function IsSafetyExcluded(item)
    if not item then return false end
    if IsPrimordialSaronite(item) then
        return true, "Primordial Saronite"
    end
    if tonumber(item.quality) == 4 and IsBindOnEquip(item.link) then
        return true, "Epic BoE"
    end
    return false
end

local function GetBagItem(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return nil end

    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    local name, itemLink, itemQuality, itemLevel, requiredLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, vendorPrice = GetItemInfo(link)
    return {
        bag = bag,
        slot = slot,
        link = itemLink or link,
        id = ExtractItemId(link),
        name = name or ExtractBracketName(link),
        count = count or 1,
        locked = locked,
        quality = itemQuality or quality,
        itemLevel = itemLevel or 0,
        itemType = itemType,
        itemSubType = itemSubType,
        itemEquipLoc = itemEquipLoc,
        vendorPrice = vendorPrice or 0,
    }
end

local function NormalizeText(text)
    return string.lower(tostring(text or ""))
end

local function IsWeaponItem(item)
    if not item then return false end
    local itemType = NormalizeText(item.itemType)
    local weaponText = NormalizeText(_G.WEAPON or "Weapon")
    if itemType ~= "" and itemType == weaponText then return true end

    local equipLoc = item.itemEquipLoc or ""
    return equipLoc == "INVTYPE_WEAPON"
        or equipLoc == "INVTYPE_2HWEAPON"
        or equipLoc == "INVTYPE_WEAPONMAINHAND"
        or equipLoc == "INVTYPE_WEAPONOFFHAND"
        or equipLoc == "INVTYPE_RANGED"
        or equipLoc == "INVTYPE_RANGEDRIGHT"
        or equipLoc == "INVTYPE_THROWN"
end

local function IsArmorItem(item)
    if not item then return false end
    local itemType = NormalizeText(item.itemType)
    local armorText = NormalizeText(_G.ARMOR or "Armor")
    if itemType ~= "" and itemType == armorText then return true end

    local equipLoc = item.itemEquipLoc or ""
    return equipLoc == "INVTYPE_HEAD"
        or equipLoc == "INVTYPE_NECK"
        or equipLoc == "INVTYPE_SHOULDER"
        or equipLoc == "INVTYPE_BODY"
        or equipLoc == "INVTYPE_CHEST"
        or equipLoc == "INVTYPE_ROBE"
        or equipLoc == "INVTYPE_WAIST"
        or equipLoc == "INVTYPE_LEGS"
        or equipLoc == "INVTYPE_FEET"
        or equipLoc == "INVTYPE_WRIST"
        or equipLoc == "INVTYPE_HAND"
        or equipLoc == "INVTYPE_FINGER"
        or equipLoc == "INVTYPE_TRINKET"
        or equipLoc == "INVTYPE_CLOAK"
        or equipLoc == "INVTYPE_SHIELD"
        or equipLoc == "INVTYPE_HOLDABLE"
        or equipLoc == "INVTYPE_TABARD"
end

local function MatchesEquipmentRule(item, settings)
    if not item then return false end
    local quality = tonumber(item.quality) or -1
    local maxQuality = tonumber(settings.sellEquipmentMaxQuality) or 1
    if quality > maxQuality then return false end

    if settings.useEquipmentMaxItemLevel then
        local itemLevel = tonumber(item.itemLevel) or 0
        local maxItemLevel = tonumber(settings.equipmentMaxItemLevel) or 0
        if maxItemLevel > 0 and itemLevel > maxItemLevel then return false end
    end

    if settings.sellWeapons and IsWeaponItem(item) then
        return true, "weapon rule"
    end
    if settings.sellArmor and IsArmorItem(item) then
        return true, "armor rule"
    end
    return false
end

local function ShouldSellItem(item, settings, forceNames, forceIds, neverNames, neverIds)
    if not item or item.locked then return false end

    if WowNote_IsItemProtected and (WowNote_IsItemProtected(item.link) or WowNote_IsItemProtected(item.id) or WowNote_IsItemProtected(item.name)) then
        return false, "protected item"
    end

    if MatchesList(item, neverNames, neverIds) then
        return false, "never-sell list"
    end

    if IsSafetyExcluded(item) then
        return false, "safety exclusion"
    end

    if MatchesList(item, forceNames, forceIds) then
        return true, "force-sell list"
    end

    if settings.sellGray and tonumber(item.quality) == 0 then
        return true, "gray item"
    end

    local equipmentMatch = MatchesEquipmentRule(item, settings)
    if equipmentMatch then
        return true, "equipment rule"
    end

    return false
end

local function ScheduleSellSummary(itemCount, estimatedCopper, beforeMoney)
    if not itemCount or itemCount <= 0 then return end
    pendingSellSummary = {
        timeLeft = 0.75,
        itemCount = itemCount,
        estimatedCopper = estimatedCopper or 0,
        beforeMoney = beforeMoney or GetMoney(),
    }
    if not summaryFrame then
        summaryFrame = CreateFrame("Frame")
        WowNoteProfiler_SetScript(summaryFrame, "OnUpdate", "AutoVendor.SummaryDelay", function(self, elapsed)
            if not pendingSellSummary then
                self:Hide()
                return
            end
            pendingSellSummary.timeLeft = pendingSellSummary.timeLeft - (elapsed or 0)
            if pendingSellSummary.timeLeft > 0 then return end

            local gained = GetMoney() - (pendingSellSummary.beforeMoney or GetMoney())
            if gained < 0 then gained = pendingSellSummary.estimatedCopper or 0 end
            if gained == 0 then gained = pendingSellSummary.estimatedCopper or 0 end

            Print("Auto-sold " .. tostring(pendingSellSummary.itemCount) .. " item(s) for " .. FormatMoney(gained) .. ".")
            pendingSellSummary = nil
            self:Hide()
        end)
    end
    summaryFrame:Show()
end

local function AutoSellItems()
    local settings = EnsureVendorDB()
    if not settings.sellEnabled then return end

    local forceNames, forceIds = BuildListIndex(settings.forceSell or "")
    local neverNames, neverIds = BuildListIndex(settings.neverSell or "")
    local soldCount = 0
    local estimatedCopper = 0
    local beforeMoney = GetMoney()

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local item = GetBagItem(bag, slot)
            local shouldSell = ShouldSellItem(item, settings, forceNames, forceIds, neverNames, neverIds)
            if shouldSell then
                soldCount = soldCount + (item.count or 1)
                estimatedCopper = estimatedCopper + ((item.vendorPrice or 0) * (item.count or 1))
                UseContainerItem(bag, slot)
            end
        end
    end

    if settings.printSellSummary and soldCount > 0 then
        ScheduleSellSummary(soldCount, estimatedCopper, beforeMoney)
    end
end

local function AutoRepairItems()
    local settings = EnsureVendorDB()
    if not settings.repairEnabled then return end
    if not CanMerchantRepair or not CanMerchantRepair() then return end

    local repairCost = 0
    local canRepair = false
    if GetRepairAllCost then
        repairCost, canRepair = GetRepairAllCost()
    end
    if not canRepair or (repairCost or 0) <= 0 then return end

    local usedGuild = false
    if settings.repairGuild then
        local guildAllowed = true
        if CanGuildBankRepair then
            local ok, result = pcall(CanGuildBankRepair)
            guildAllowed = ok and result
        end
        if guildAllowed then
            pcall(RepairAllItems, 1)
            usedGuild = true
        else
            RepairAllItems()
        end
    else
        RepairAllItems()
    end

    if settings.printRepairSummary then
        if usedGuild then
            Print("Repaired for " .. FormatMoney(repairCost) .. " using guild repair if available.")
        else
            Print("Repaired for " .. FormatMoney(repairCost) .. ".")
        end
    end
end

local function OnMerchantShow()
    AutoRepairItems()
    AutoSellItems()
end

function WowNote_GetAutoVendorSettings()
    return EnsureVendorDB()
end

function WowNote_SaveAutoVendorSettings(values)
    local settings = EnsureVendorDB()
    if type(values) == "table" then
        for key, value in pairs(values) do
            settings[key] = value
        end
    end
    settings.forceSell = NormalizeListText(settings.forceSell or "")
    settings.neverSell = NormalizeListText(settings.neverSell or "")
    return settings
end

function WowNote_RunAutoVendorNow()
    if MerchantFrame and MerchantFrame:IsShown() then
        OnMerchantShow()
    else
        Print("Open a vendor first.")
    end
end

EnsureVendorDB()
if not eventFrame then
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    WowNoteProfiler_SetScript(eventFrame, "OnEvent", "AutoVendor.Events", function(self, event)
        if event == "MERCHANT_SHOW" then
            OnMerchantShow()
        end
    end)
end
