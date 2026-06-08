-- WowNote_Restock.lua
-- Merchant restock assistant for tracked items.

local frame, listFrame, statusText
local rows = {}
local merchantOpen = false
local pendingBuys = {}
local autoBuyPending = {}
local manualBuyPending = {}
local purchasePendingAt = {}
local purchasePendingExpected = {}
local boughtThisMerchant = {}
local lastAutoAttemptAt = 0
local IsPending
local ClearPendingBuys
local PurchaseOneVendorUnit

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function InitDB()
    if WowNote_Internal and WowNote_Internal.InitDB then WowNote_Internal.InitDB() end
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.itemTracker) ~= "table" and type(WowNoteDB) == "table" and type(WowNoteDB.itemTracker) == "table" then
        WowNoteCharDB.itemTracker = WowNoteDB.itemTracker
    end
    if type(WowNoteCharDB.itemTracker) ~= "table" then WowNoteCharDB.itemTracker = {} end
    if type(WowNoteCharDB.itemTracker.trackedItems) ~= "table" then WowNoteCharDB.itemTracker.trackedItems = {} end
end

local function ExtractItemId(link)
    if WowNote_ItemSnapshots_ExtractItemId then return WowNote_ItemSnapshots_ExtractItemId(link) end
    local id = link and string.match(link, "item:(%-?%d+)")
    return id and tonumber(id) or nil
end

local function CurrentCount(itemId)
    if WowNote_ItemSnapshots_GetCurrentCharacterCount then return WowNote_ItemSnapshots_GetCurrentCharacterCount(itemId, false) end
    return 0
end

local function MakeButton(parent, text, width, height)
    if WowNote_Internal and WowNote_Internal.MakeButton then return WowNote_Internal.MakeButton(parent, text, width, height) end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width or 80); b:SetHeight(height or 22); b:SetText(text or "")
    return b
end

local function SetStatus(msg)
    if statusText then statusText:SetText(msg or "") end
end

local function EnsureFrame()
    if frame then return end
    frame = CreateFrame("Frame", "WowNoteRestockFrame", UIParent)
    frame:SetWidth(430); frame:SetHeight(260); frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); if frame.SetToplevel then frame:SetToplevel(true) end
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    frame:Hide()
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -18); title:SetText("WowNote Restock")
    local bank = MakeButton(frame, "Bank", 60, 24); bank:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -48); bank:SetScript("OnClick", function() if WowNote_OpenBankViewer then WowNote_OpenBankViewer() end end)
    local tracker = MakeButton(frame, "Tracker", 78, 24); tracker:SetPoint("LEFT", bank, "RIGHT", 8, 0); tracker:SetScript("OnClick", function() if WowNote_OpenItemTracker then WowNote_OpenItemTracker() end end)
    local help = MakeButton(frame, "Help", 60, 24); help:SetPoint("LEFT", tracker, "RIGHT", 8, 0); help:SetScript("OnClick", function() if WowNote_PrintHelp then WowNote_PrintHelp() end end)
    local buyAll = MakeButton(frame, "Buy selected", 110, 24); buyAll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -48)
    buyAll:SetScript("OnClick", function()
        local bought = 0
        for i = 1, table.getn(pendingBuys) do
            local buy = pendingBuys[i]
            if buy and buy.merchantIndex and buy.units and buy.units > 0 and not IsPending(buy.itemId) then
                if PurchaseOneVendorUnit(buy, "manual") then bought = bought + 1 end
            end
        end
        if bought == 0 then SetStatus("Nothing bought. Waiting for bag update or no restock needed.") end
    end)
    local bg = CreateFrame("Frame", nil, frame)
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -80); bg:SetWidth(390); bg:SetHeight(130)
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    bg:SetBackdropColor(0,0,0,0.75)
    listFrame = CreateFrame("Frame", nil, bg); listFrame:SetPoint("TOPLEFT", bg, "TOPLEFT", 8, -8); listFrame:SetWidth(360); listFrame:SetHeight(110)
    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 18); statusText:SetText("")
end

local function RefreshFrame()
    EnsureFrame()
    for i = 1, table.getn(rows) do rows[i]:Hide() end
    for i = 1, table.getn(pendingBuys) do
        local buy = pendingBuys[i]
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, listFrame); row:SetWidth(360); row:SetHeight(24)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.text:SetPoint("LEFT", row, "LEFT", 0, 0); row.text:SetWidth(250); row.text:SetJustifyH("LEFT")
            row.button = MakeButton(row, "Buy", 55, 22); row.button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            rows[i] = row
        end
        row.buy = buy
        local pending = IsPending(buy.itemId)
        local label = (buy.name or "Item") .. "  " .. tostring(buy.current) .. " -> " .. tostring(buy.target) .. "  (need " .. tostring(buy.missing or 0) .. ", " .. tostring(buy.units or 0) .. " vendor units)"
        if pending then label = label .. "  |cffaaaaaawaiting for bags|r" end
        row.text:SetText(label)
        row.button:SetText(pending and "Wait" or "Buy need")
        row.button:SetScript("OnClick", function(self) local buy = self:GetParent().buy; if buy then PurchaseOneVendorUnit(buy, "manual") end end)
        row:ClearAllPoints(); if i == 1 then row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, 0) else row:SetPoint("TOPLEFT", rows[i-1], "BOTTOMLEFT", 0, -4) end
        row:Show()
    end
    if table.getn(pendingBuys) > 0 then frame:Show(); SetStatus("Review restock before buying.") else frame:Hide() end
end

local function MerchantItemsById()
    local byId = {}
    if not GetMerchantNumItems then return byId end
    for i = 1, GetMerchantNumItems() do
        local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
        local link = GetMerchantItemLink(i)
        local itemId = ExtractItemId(link)
        if itemId then
            byId[itemId] = { index = i, name = name, price = price or 0, quantity = quantity or 1, numAvailable = numAvailable, extendedCost = extendedCost }
        end
    end
    return byId
end

local function CanSpend(item, merchant, stacks)
    local maxSpend = item.restock and tonumber(item.restock.maxSpendCopper) or 1000000
    if merchant.extendedCost then return false end
    local cost = (merchant.price or 0) * stacks
    if maxSpend and maxSpend > 0 and cost > maxSpend then return false end
    if GetMoney and cost > GetMoney() then return false end
    return true
end

local function MerchantUnitCount(merchant)
    local quantity = tonumber(merchant and merchant.quantity) or 1
    if quantity < 1 then quantity = 1 end
    return quantity
end

local function MissingVendorUnits(current, target, merchant)
    local missing = (tonumber(target) or 0) - (tonumber(current) or 0)
    if missing <= 0 then return 0, 0 end
    local unitCount = MerchantUnitCount(merchant)
    local units = math.ceil(missing / unitCount)
    if merchant and merchant.numAvailable and merchant.numAvailable > 0 and units > merchant.numAvailable then units = merchant.numAvailable end
    return missing, units
end

IsPending = function(itemId)
    itemId = tonumber(itemId)
    return itemId and (autoBuyPending[itemId] or manualBuyPending[itemId])
end

ClearPendingBuys = function()
    autoBuyPending = {}
    manualBuyPending = {}
    purchasePendingAt = {}
    purchasePendingExpected = {}
end

PurchaseOneVendorUnit = function(buy, reason)
    if not buy or not buy.merchantIndex or not buy.itemId then return false end
    local itemId = tonumber(buy.itemId)
    if not itemId then return false end
    if IsPending(itemId) then
        SetStatus("Waiting for bag update before buying more.")
        return false
    end
    local current = CurrentCount(itemId)
    local target = tonumber(buy.target) or 0
    local missing = target - current
    if missing <= 0 then
        autoBuyPending[itemId] = nil
        manualBuyPending[itemId] = nil
        purchasePendingAt[itemId] = nil
        purchasePendingExpected[itemId] = nil
        SetStatus("Target already reached.")
        return false
    end
    local vendorUnits = tonumber(buy.units) or 0
    if vendorUnits <= 0 then return false end
    if BuyMerchantItem then
        -- Buy exactly the currently missing amount expressed as vendor units.
        -- Do not loop-buy here; the next decision is made only after the bags were recounted.
        if reason == "auto" then autoBuyPending[itemId] = true; boughtThisMerchant[itemId] = true else manualBuyPending[itemId] = true end
        purchasePendingAt[itemId] = GetTime and GetTime() or time()
        purchasePendingExpected[itemId] = current + missing
        BuyMerchantItem(buy.merchantIndex, vendorUnits)
        SetStatus("Bought " .. tostring(vendorUnits) .. " vendor units for " .. tostring(missing) .. " missing items. Waiting for bag recount...")
        return true
    end
    return false
end

function WowNote_Restock_CheckMerchant()
    InitDB()
    pendingBuys = {}
    if not merchantOpen then if frame then frame:Hide() end; return end
    local merchant = MerchantItemsById()
    for itemId, item in pairs(WowNoteCharDB.itemTracker.trackedItems) do
        if type(item) == "table" and type(item.restock) == "table" and item.restock.enabled then
            local m = merchant[tonumber(itemId)]
            if m then
                local current = CurrentCount(itemId)
                local threshold = tonumber(item.threshold) or 0
                local target = tonumber(item.restock.target or item.target or threshold) or threshold
                -- Restock is target-based: alerts use the minimum threshold, but buying should
                -- top the character back up to the configured target whenever it is below target.
                if target > 0 and current < target then
                    local missing, units = MissingVendorUnits(current, target, m)
                    if units > 0 and CanSpend(item, m, 1) then
                        local buy = { itemId = tonumber(itemId), name = item.name or m.name, merchantIndex = m.index, units = units, missing = missing, current = current, target = target }
                        table.insert(pendingBuys, buy)
                        if item.restock.autoBuy and not IsPending(itemId) and not boughtThisMerchant[tonumber(itemId)] then
                            if PurchaseOneVendorUnit(buy, "auto") then
                                Print("Auto-restock: " .. tostring(item.name or m.name) .. " bought the missing restock amount; waiting for bag recount.")
                            end
                        end
                    end
                elseif target > 0 and current >= target then
                    autoBuyPending[tonumber(itemId)] = nil
                    manualBuyPending[tonumber(itemId)] = nil
                end
            end
        end
    end
    RefreshFrame()
end

function WowNote_OpenRestock()
    EnsureFrame(); merchantOpen = MerchantFrame and MerchantFrame:IsShown(); WowNote_Restock_CheckMerchant(); if table.getn(pendingBuys) == 0 then frame:Show(); SetStatus("No matching restock item at this merchant.") end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnUpdate", function(self)
    if not merchantOpen then return end
    local now = GetTime and GetTime() or time()
    local changed = false
    for itemId, startedAt in pairs(purchasePendingAt) do
        if startedAt and (now - startedAt) > 1.25 then
            autoBuyPending[itemId] = nil
            manualBuyPending[itemId] = nil
            purchasePendingAt[itemId] = nil
            purchasePendingExpected[itemId] = nil
            changed = true
        end
    end
    if changed then
        WowNote_Restock_CheckMerchant()
    end
end)
events:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_CLOSED" then
        merchantOpen = false
        ClearPendingBuys()
        boughtThisMerchant = {}
        pendingBuys = {}
        if frame then frame:Hide() end
        return
    end
    if event == "BAG_UPDATE" then
        if merchantOpen then SetStatus("Bag update received. Waiting for final bag count...") end
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        if not merchantOpen then return end
        ClearPendingBuys()
        SetStatus("Bags recounted.")
        WowNote_Restock_CheckMerchant()
        return
    end
    if event == "MERCHANT_SHOW" then boughtThisMerchant = {} end
    merchantOpen = true
    WowNote_Restock_CheckMerchant()
end)
