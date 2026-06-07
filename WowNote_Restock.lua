-- WowNote_Restock.lua
-- Merchant restock assistant for tracked items.

local frame, listFrame, statusText
local rows = {}
local merchantOpen = false
local pendingBuys = {}

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function InitDB()
    if WowNote_Internal and WowNote_Internal.InitDB then WowNote_Internal.InitDB() end
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.itemTracker) ~= "table" then WowNoteDB.itemTracker = {} end
    if type(WowNoteDB.itemTracker.trackedItems) ~= "table" then WowNoteDB.itemTracker.trackedItems = {} end
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
        for i = 1, table.getn(pendingBuys) do
            local buy = pendingBuys[i]
            if buy and buy.merchantIndex and buy.stacks and buy.stacks > 0 then
                BuyMerchantItem(buy.merchantIndex, buy.stacks)
            end
        end
        SetStatus("Restock purchase sent.")
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
        row.text:SetText((buy.name or "Item") .. "  " .. tostring(buy.current) .. " -> " .. tostring(buy.target) .. "  (" .. tostring(buy.stacks) .. "x)")
        row.button:SetScript("OnClick", function(self) local buy = self:GetParent().buy; if buy then BuyMerchantItem(buy.merchantIndex, buy.stacks) end end)
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

function WowNote_Restock_CheckMerchant()
    InitDB()
    pendingBuys = {}
    if not merchantOpen then if frame then frame:Hide() end; return end
    local merchant = MerchantItemsById()
    for itemId, item in pairs(WowNoteDB.itemTracker.trackedItems) do
        if type(item) == "table" and type(item.restock) == "table" and item.restock.enabled then
            local m = merchant[tonumber(itemId)]
            if m then
                local current = CurrentCount(itemId)
                local threshold = tonumber(item.threshold) or 0
                local target = tonumber(item.restock.target or item.target or threshold) or threshold
                if current < threshold and target > current then
                    local missing = target - current
                    local quantity = tonumber(m.quantity) or 1
                    if quantity < 1 then quantity = 1 end
                    local stacks = math.ceil(missing / quantity)
                    if m.numAvailable and m.numAvailable > 0 and stacks > m.numAvailable then stacks = m.numAvailable end
                    if stacks > 0 and CanSpend(item, m, stacks) then
                        table.insert(pendingBuys, { itemId = tonumber(itemId), name = item.name or m.name, merchantIndex = m.index, stacks = stacks, current = current, target = target })
                        if item.restock.autoBuy then
                            BuyMerchantItem(m.index, stacks)
                            Print("Auto-restock: " .. tostring(item.name or m.name) .. " x" .. tostring(stacks))
                        end
                    end
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
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_CLOSED" then merchantOpen = false; if frame then frame:Hide() end; return end
    merchantOpen = true
    WowNote_Restock_CheckMerchant()
end)
