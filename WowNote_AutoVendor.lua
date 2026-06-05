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
    if settings.printSellSummary == nil then settings.printSellSummary = true end
    if settings.forceSell == nil then settings.forceSell = "" end
    if settings.neverSell == nil then settings.neverSell = "" end
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
        vendorPrice = vendorPrice or 0,
    }
end

local function ShouldSellItem(item, settings, forceNames, forceIds, neverNames, neverIds)
    if not item or item.locked then return false end

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
        summaryFrame:SetScript("OnUpdate", function(self, elapsed)
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
    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "MERCHANT_SHOW" then
            OnMerchantShow()
        end
    end)
end
