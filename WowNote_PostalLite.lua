-- WowNote_PostalLite.lua
-- Lightweight mailbox toolbar used when the embedded Postal package is not present.

local toolbar, openAllButton, deleteEmptyButton, cleanManabonkButton
local workerFrame
local toolbarRepairFrame
local toolbarRepairRemaining = 0
local toolbarRepairElapsed = 0
local openAllActive = false
local openAllIdleCycles = 0
local openAllSafetyCycles = 0
local openAllLooted = 0
local openAllDeleted = 0
local openAllStartMoney = nil
local mailSessionActive = false
local mailSessionLastMoney = nil
local mailSessionGoldGained = 0

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function FormatMoneyAmount(copper)
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    copper = math.floor(copper + 0.5)

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper - (gold * 10000)) / 100)
    local cop = copper - (gold * 10000) - (silver * 100)

    if gold > 0 then
        return string.format("%dg %02ds %02dc", gold, silver, cop)
    end
    if silver > 0 then
        return string.format("%ds %02dc", silver, cop)
    end
    return string.format("%dc", cop)
end

local function UpdateMailSessionMoney()
    if not mailSessionActive or not GetMoney then return end
    local current = tonumber(GetMoney()) or 0
    if mailSessionLastMoney ~= nil then
        local delta = current - (tonumber(mailSessionLastMoney) or current)
        -- Count only increases. Sending mail/postage or other deductions during
        -- the mailbox session must not reduce already collected mailbox income.
        if delta > 0 then mailSessionGoldGained = mailSessionGoldGained + delta end
    end
    mailSessionLastMoney = current
end

local function StartMailSession()
    if mailSessionActive then return end
    mailSessionActive = true
    mailSessionGoldGained = 0
    mailSessionLastMoney = GetMoney and (tonumber(GetMoney()) or 0) or nil
end

local function FinishMailSession()
    if not mailSessionActive then return end
    UpdateMailSessionMoney()
    local gained = tonumber(mailSessionGoldGained) or 0
    mailSessionActive = false
    mailSessionLastMoney = nil
    mailSessionGoldGained = 0
    Print("Mailbox gold collected: " .. FormatMoneyAmount(gained) .. ".")
end

local function GetOpenAllGoldGained()
    if not GetMoney or not openAllStartMoney then return nil end
    local current = tonumber(GetMoney()) or 0
    local gained = current - (tonumber(openAllStartMoney) or current)
    if gained < 0 then gained = 0 end
    return gained
end

local function BuildOpenAllSummary(prefix)
    local msg = (prefix or "Open All done.") .. " Looted: " .. tostring(openAllLooted) .. ", deleted empty: " .. tostring(openAllDeleted) .. "."
    local gained = GetOpenAllGoldGained()
    if gained then
        msg = msg .. " Gold earned: " .. FormatMoneyAmount(gained) .. "."
    end
    return msg
end

local function GetOpenAllInterval()
    if WowNote_GetPostalOpenInterval then return WowNote_GetPostalOpenInterval() end
    if type(WowNoteDB) == "table" and type(WowNoteDB.postalLite) == "table" then
        local value = tostring(WowNoteDB.postalLite.openAllInterval or "")
        value = string.gsub(value, ",", ".")
        local number = tonumber(value)
        if number and number > 0 then
            if number < 0.05 then return 0.05 end
            return number
        end
    end
    return 0.50
end

local function MailVisible()
    return MailFrame and MailFrame:IsShown()
end

local function GetInboxCount()
    if not GetInboxNumItems then return 0 end
    local visible = GetInboxNumItems()
    return tonumber(visible) or 0
end

local function GetHeader(index)
    if not GetInboxHeaderInfo then return nil end
    local packageIcon, stationeryIcon, sender, subject, money, codAmount, daysLeft, itemCount = GetInboxHeaderInfo(index)
    return {
        packageIcon = packageIcon,
        stationeryIcon = stationeryIcon,
        sender = sender,
        subject = subject,
        money = tonumber(money) or 0,
        codAmount = tonumber(codAmount) or 0,
        daysLeft = daysLeft,
        itemCount = tonumber(itemCount) or 0,
    }
end

local function RefreshInbox()
    if CheckInbox then pcall(CheckInbox) end
    if InboxFrame_Update then pcall(InboxFrame_Update) end
end

local function GetMaxAttachmentSlots()
    return tonumber(ATTACHMENTS_MAX_RECEIVE) or 16
end

local function SlotHasAttachment(index, slot)
    if GetInboxItemLink then
        local ok, link = pcall(GetInboxItemLink, index, slot)
        if ok and link then return true end
    end
    if GetInboxItem then
        local ok, name, itemID, texture, count = pcall(GetInboxItem, index, slot)
        if ok and (name or itemID or texture or (tonumber(count) or 0) > 0) then return true end
    end
    return false
end

local function CountVisibleAttachments(index)
    local found = 0
    local slot
    for slot = 1, GetMaxAttachmentSlots() do
        if SlotHasAttachment(index, slot) then found = found + 1 end
    end
    return found
end

local function EffectiveItemCount(index, header)
    local visible = CountVisibleAttachments(index)
    local fromHeader = header and (tonumber(header.itemCount) or 0) or 0
    if visible > fromHeader then return visible end
    return fromHeader
end

local function IsSafeEmpty(index)
    local header = GetHeader(index)
    if not header then return false end
    return (header.money or 0) == 0 and (header.codAmount or 0) == 0 and EffectiveItemCount(index, header) == 0
end

local function StopWorker(doneMessage)
    openAllActive = false
    openAllIdleCycles = 0
    openAllSafetyCycles = 0
    if workerFrame then WowNoteProfiler_SetScript(workerFrame, "OnUpdate", "Postal.OpenAllWorker", nil) end
    if doneMessage then
        Print(BuildOpenAllSummary("Open All done."))
    end
end

local function AutoLootOneMail(index)
    if not AutoLootMailItem then return false end
    local ok = pcall(AutoLootMailItem, index)
    return ok
end

local function TakeOneInboxItem(index, itemCount)
    if not TakeInboxItem then return false end

    -- Prefer actually visible attachment slots. Header itemCount can be stale
    -- on 3.3.5a/Warmane AH mail after a take/reindex cycle.
    local slot
    for slot = 1, GetMaxAttachmentSlots() do
        if SlotHasAttachment(index, slot) then
            local ok = pcall(TakeInboxItem, index, slot)
            return ok
        end
    end

    -- Fallback for cores where GetInboxItem/GetInboxItemLink does not expose
    -- the slot reliably, but header.itemCount still says there are items.
    -- AH-returned items on 3.3.5a are commonly in slot 1, so try in
    -- ascending order instead of starting at a possibly non-existent slot.
    for slot = 1, (tonumber(itemCount) or 0) do
        local ok = pcall(TakeInboxItem, index, slot)
        if ok then return true end
    end
    return false
end

local function ProcessOneMailboxAction()
    local count = GetInboxCount()
    local index

    -- Work backwards. Deleting or looting can shift/reindex the inbox; starting
    -- at the bottom is the least fragile order on 3.3.5a AH mailboxes.
    for index = count, 1, -1 do
        local header = GetHeader(index)
        if header and (header.codAmount or 0) == 0 then
            local itemCount = EffectiveItemCount(index, header)

            -- Prefer the native mailbox auto-loot helper when present. It is
            -- more reliable for Auction House item mails on 3.3.5a/Warmane
            -- than mixing stale header data with manual TakeInboxItem slots.
            if ((header.money or 0) > 0 or itemCount > 0) and AutoLootOneMail(index) then
                openAllLooted = openAllLooted + 1
                return true
            end

            if (header.money or 0) > 0 and TakeInboxMoney then
                local ok = pcall(TakeInboxMoney, index)
                if ok then
                    openAllLooted = openAllLooted + 1
                    return true
                end
            end

            if itemCount > 0 and TakeOneInboxItem(index, itemCount) then
                openAllLooted = openAllLooted + 1
                return true
            end

            -- Important for Auction House mail: after money/item pickup the
            -- mailbox may be full of empty letters. Postal users expect Open
            -- All to clear those, not to stop with "nothing lootable".
            if DeleteInboxItem and IsSafeEmpty(index) then
                DeleteInboxItem(index)
                openAllDeleted = openAllDeleted + 1
                return true
            end
        end
    end
    return false
end

local function StartWorker()
    StopWorker(false)
    openAllActive = true
    openAllIdleCycles = 0
    openAllSafetyCycles = 0
    openAllLooted = 0
    openAllDeleted = 0
    openAllStartMoney = GetMoney and (tonumber(GetMoney()) or 0) or nil
    workerFrame = workerFrame or CreateFrame("Frame")
    local elapsed = 0
    WowNoteProfiler_SetScript(workerFrame, "OnUpdate", "Postal.OpenAllWorker", function(self, delta)
        elapsed = elapsed + (delta or 0)
        local interval = GetOpenAllInterval()
        if elapsed < interval then return end
        elapsed = 0

        if not MailVisible() then
            StopWorker(false)
            return
        end

        openAllSafetyCycles = openAllSafetyCycles + 1
        if openAllSafetyCycles > 900 then
            Print(BuildOpenAllSummary("Open All stopped after safety timeout."))
            StopWorker(false)
            return
        end

        if ProcessOneMailboxAction() then
            openAllIdleCycles = 0
            RefreshInbox()
            return
        end

        -- AH mail updates can lag. Keep polling long enough for the server to
        -- expose the next money/item/empty-letter state. Also call CheckInbox
        -- occasionally so a stale first scan does not make the worker give up.
        openAllIdleCycles = openAllIdleCycles + 1
        if (openAllIdleCycles % 4) == 0 then RefreshInbox() end
        if openAllIdleCycles >= 24 then
            StopWorker(true)
        end
    end)
end

local function OpenAll()
    if not MailVisible() then return end
    Print("Open All started... interval " .. string.format("%.2f", GetOpenAllInterval()) .. " sec")
    RefreshInbox()
    StartWorker()
end

local function DeleteEmpty()
    if not MailVisible() or not DeleteInboxItem then return end
    local deleted = 0
    local index
    for index = GetInboxCount(), 1, -1 do
        if IsSafeEmpty(index) then
            DeleteInboxItem(index)
            deleted = deleted + 1
        end
    end
    RefreshInbox()
    Print("Deleted empty mailbox letters: " .. tostring(deleted))
end

local function MakeButton(parent, name, text, width)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetWidth(width or 86)
    button:SetHeight(22)
    button:SetText(text or "")
    return button
end

local function GetToolbarParent()
    if InboxFrame then return InboxFrame end
    if MailFrame then return MailFrame end
    return UIParent
end

local function ConfigureToolbarFrame()
    if not toolbar then return end
    local parent = GetToolbarParent()
    if parent and toolbar:GetParent() ~= parent then toolbar:SetParent(parent) end

    toolbar:ClearAllPoints()
    toolbar:SetPoint("TOPLEFT", parent, "TOPLEFT", 58, -52)
    toolbar:SetWidth(305)
    toolbar:SetHeight(24)
    toolbar:EnableMouse(true)
    if toolbar.SetFrameStrata then toolbar:SetFrameStrata("DIALOG") end
    if toolbar.SetFrameLevel then
        local baseLevel = parent and parent.GetFrameLevel and parent:GetFrameLevel() or 1
        toolbar:SetFrameLevel((tonumber(baseLevel) or 1) + 20)
    end

    local function PrepareButton(button, levelOffset)
        if not button then return end
        button:EnableMouse(true)
        button:Enable()
        if button.SetFrameLevel and toolbar.GetFrameLevel then
            button:SetFrameLevel((toolbar:GetFrameLevel() or 20) + (levelOffset or 1))
        end
        button:Show()
    end
    PrepareButton(openAllButton, 1)
    PrepareButton(deleteEmptyButton, 1)
    PrepareButton(cleanManabonkButton, 1)
end

local function CreateToolbar()
    if not CreateFrame then return end
    if toolbar then
        ConfigureToolbarFrame()
        return
    end

    local parent = GetToolbarParent()
    toolbar = CreateFrame("Frame", "WowNotePostalLiteToolbar", parent)
    toolbar:SetWidth(305)
    toolbar:SetHeight(24)

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

    ConfigureToolbarFrame()
    toolbar:Hide()
end

local function InboxVisible()
    if not MailVisible() then return false end
    if InboxFrame and InboxFrame.IsShown then return InboxFrame:IsShown() end
    return true
end

local function UpdateToolbar()
    CreateToolbar()
    if not toolbar then return end
    ConfigureToolbarFrame()
    if InboxVisible() then
        toolbar:Show()
        if openAllButton then openAllButton:Enable() end
        if deleteEmptyButton then deleteEmptyButton:Enable() end
        if cleanManabonkButton then cleanManabonkButton:Enable() end
    else
        toolbar:Hide()
    end
end

local function StopToolbarRepair()
    toolbarRepairRemaining = 0
    toolbarRepairElapsed = 0
    if toolbarRepairFrame then
        WowNoteProfiler_SetScript(toolbarRepairFrame, "OnUpdate", "Postal.ToolbarRepair", nil)
    end
end

local function StartToolbarRepair()
    toolbarRepairRemaining = 2.0
    toolbarRepairElapsed = 0
    toolbarRepairFrame = toolbarRepairFrame or CreateFrame("Frame")
    WowNoteProfiler_SetScript(toolbarRepairFrame, "OnUpdate", "Postal.ToolbarRepair", function(self, elapsed)
        toolbarRepairRemaining = toolbarRepairRemaining - (tonumber(elapsed) or 0)
        toolbarRepairElapsed = toolbarRepairElapsed + (tonumber(elapsed) or 0)
        if toolbarRepairElapsed >= 0.10 then
            toolbarRepairElapsed = 0
            UpdateToolbar()
        end
        if toolbarRepairRemaining <= 0 or not MailVisible() then
            StopToolbarRepair()
        end
    end)
    UpdateToolbar()
end

local function HookMailboxFrames()
    if InboxFrame and InboxFrame.HookScript and not InboxFrame.WowNotePostalHooked then
        InboxFrame.WowNotePostalHooked = true
        InboxFrame:HookScript("OnShow", function() StartToolbarRepair() end)
        InboxFrame:HookScript("OnHide", function() UpdateToolbar() end)
    end
    if MailFrame and MailFrame.HookScript and not MailFrame.WowNotePostalHooked then
        MailFrame.WowNotePostalHooked = true
        MailFrame:HookScript("OnShow", function() StartToolbarRepair() end)
        MailFrame:HookScript("OnHide", function() StopToolbarRepair(); UpdateToolbar() end)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("PLAYER_LOGIN")
WowNoteProfiler_SetScript(frame, "OnEvent", "Postal.Events", function(self, event)
    if event == "PLAYER_LOGIN" then
        HookMailboxFrames()
        UpdateToolbar()
        return
    elseif event == "MAIL_SHOW" then
        StartMailSession()
        self:RegisterEvent("PLAYER_MONEY")
        HookMailboxFrames()
        StartToolbarRepair()
        return
    elseif event == "PLAYER_MONEY" then
        UpdateMailSessionMoney()
        return
    elseif event == "MAIL_CLOSED" then
        StopWorker(false)
        StopToolbarRepair()
        FinishMailSession()
        self:UnregisterEvent("PLAYER_MONEY")
        UpdateToolbar()
        return
    elseif event == "MAIL_INBOX_UPDATE" then
        -- MailFrame/InboxFrame can finish their layout a frame or two after
        -- MAIL_SHOW. Reassert parent, frame level and enabled state here too.
        HookMailboxFrames()
        UpdateToolbar()
    end
end)
