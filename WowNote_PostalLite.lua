-- WowNote_PostalLite.lua
-- Lightweight mailbox toolbar used when the embedded Postal package is not present.

local toolbar, openAllButton, deleteEmptyButton, cleanManabonkButton
local workerFrame
local openQueue = {}

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function MailVisible()
    return MailFrame and MailFrame:IsShown()
end

local function GetInboxCount()
    if not GetInboxNumItems then return 0 end
    return tonumber(GetInboxNumItems()) or 0
end

local function GetHeader(index)
    if not GetInboxHeaderInfo then return nil end
    local _, _, sender, subject, money, codAmount, _, itemCount = GetInboxHeaderInfo(index)
    return {
        sender = sender,
        subject = subject,
        money = money or 0,
        codAmount = codAmount or 0,
        itemCount = itemCount or 0,
    }
end

local function IsSafeEmpty(index)
    local header = GetHeader(index)
    if not header then return false end
    return (header.money or 0) == 0 and (header.codAmount or 0) == 0 and (header.itemCount or 0) == 0
end

local function HasLoot(index)
    local header = GetHeader(index)
    if not header then return false end
    if (header.codAmount or 0) > 0 then return false end
    return (header.money or 0) > 0 or (header.itemCount or 0) > 0
end

local function BuildOpenQueue()
    openQueue = {}
    for index = GetInboxCount(), 1, -1 do
        if HasLoot(index) then table.insert(openQueue, index) end
    end
end

local function StopWorker()
    if workerFrame then workerFrame:SetScript("OnUpdate", nil) end
end

local function StartWorker()
    StopWorker()
    workerFrame = workerFrame or CreateFrame("Frame")
    local elapsed = 0
    workerFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + (delta or 0)
        if elapsed < 0.35 then return end
        elapsed = 0

        if not MailVisible() or table.getn(openQueue) == 0 then
            StopWorker()
            return
        end

        local index = table.remove(openQueue, 1)
        if index and index <= GetInboxCount() then
            local header = GetHeader(index)
            if header and (header.codAmount or 0) == 0 then
                if (header.money or 0) > 0 and TakeInboxMoney then TakeInboxMoney(index) end
                if (header.itemCount or 0) > 0 and TakeInboxItem then
                    local item
                    for item = 1, (header.itemCount or 0) do
                        TakeInboxItem(index, item)
                    end
                end
            end
        end
    end)
end

local function OpenAll()
    if not MailVisible() then return end
    BuildOpenQueue()
    if table.getn(openQueue) == 0 then
        Print("No lootable mailbox items found.")
        return
    end
    Print("Opening mailbox loot...")
    StartWorker()
end

local function DeleteEmpty()
    if not MailVisible() or not DeleteInboxItem then return end
    local deleted = 0
    for index = GetInboxCount(), 1, -1 do
        if IsSafeEmpty(index) then
            DeleteInboxItem(index)
            deleted = deleted + 1
        end
    end
    Print("Deleted empty mailbox letters: " .. tostring(deleted))
end

local function MakeButton(parent, name, text, width)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetWidth(width or 86)
    button:SetHeight(22)
    button:SetText(text or "")
    return button
end

local function CreateToolbar()
    if toolbar or not CreateFrame then return end
    local parent = InboxFrame or MailFrame or UIParent
    toolbar = CreateFrame("Frame", "WowNotePostalLiteToolbar", parent)
    toolbar:SetWidth(305)
    toolbar:SetHeight(24)
    toolbar:SetPoint("TOPLEFT", parent, "TOPLEFT", 58, -52)

    openAllButton = MakeButton(toolbar, "WowNotePostalLiteOpenAllButton", "Open All", 84)
    openAllButton:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    openAllButton:SetScript("OnClick", OpenAll)

    deleteEmptyButton = MakeButton(toolbar, "WowNotePostalLiteDeleteEmptyButton", "Del Empty", 84)
    deleteEmptyButton:SetPoint("LEFT", openAllButton, "RIGHT", 6, 0)
    deleteEmptyButton:SetScript("OnClick", DeleteEmpty)

    cleanManabonkButton = MakeButton(toolbar, "WowNotePostalLiteCleanManabonkButton", "Clean MB", 84)
    cleanManabonkButton:SetPoint("LEFT", deleteEmptyButton, "RIGHT", 6, 0)
    cleanManabonkButton:SetScript("OnClick", function()
        if WowNote_SetManabonkMailCleanerEnabled then WowNote_SetManabonkMailCleanerEnabled(true) end
        if WowNote_TryCleanManabonkMail then WowNote_TryCleanManabonkMail() end
    end)
    toolbar:Hide()
end

local function UpdateToolbar()
    CreateToolbar()
    if not toolbar then return end
    if MailVisible() then toolbar:Show() else toolbar:Hide() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:SetScript("OnEvent", function(self, event)
    if event == "MAIL_CLOSED" then StopWorker() end
    UpdateToolbar()
end)
