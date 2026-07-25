-- WowNote_Social.lua
-- Small social-protection helpers.

local MANABONK_ITEM_ID = 44817 -- The Mischief Maker
local pendingManabonkMail
local cleanupScheduled = false
local cleanupButton
local retryFrame

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function SocialEnabled()
    return WowNote_IsModuleEnabled and WowNote_IsModuleEnabled("social")
end

local function CleanerEnabled()
    return SocialEnabled() and WowNote_IsManabonkMailCleanerEnabled and WowNote_IsManabonkMailCleanerEnabled()
end

local function ExtractItemId(itemLink)
    if not itemLink then return nil end
    return tonumber(string.match(itemLink, "item:(%d+)"))
end

local function GetInboxCount()
    if not GetInboxNumItems then return 0 end
    local count = GetInboxNumItems()
    if type(count) == "number" then return count end
    return 0
end

local function TextLooksLikeManabonk(text)
    text = string.lower(tostring(text or ""))
    return string.find(text, "manabonk", 1, true)
        or string.find(text, "mischief", 1, true)
        or string.find(text, "zauberstab", 1, true)
        or string.find(text, "streich", 1, true)
end

local function GetInboxHeader(mailIndex)
    if not mailIndex or not GetInboxHeaderInfo then return nil end
    local packageIcon, stationeryIcon, sender, subject, money, codAmount, daysLeft, itemCount, wasRead, wasReturned, textCreated, canReply = GetInboxHeaderInfo(mailIndex)
    return {
        sender = sender,
        subject = subject,
        money = money or 0,
        codAmount = codAmount or 0,
        itemCount = itemCount or 0,
        wasRead = wasRead,
        textCreated = textCreated,
    }
end

local function HeaderLooksLikeManabonk(header)
    if type(header) ~= "table" then return false end
    return TextLooksLikeManabonk(header.subject) or TextLooksLikeManabonk(header.sender)
end

local function IsSafeManabonkMail(mailIndex)
    local header = GetInboxHeader(mailIndex)
    if not header then return false end
    if (header.money or 0) > 0 or (header.codAmount or 0) > 0 then return false end

    if header.itemCount == 1 and GetInboxItemLink then
        local itemLink = GetInboxItemLink(mailIndex, 1)
        if ExtractItemId(itemLink) == MANABONK_ITEM_ID then
            return true, header.sender, header.subject, itemLink, "attachment"
        end
    end

    -- After TakeInboxItem() some 3.3.5a servers leave the empty Manabonk letter in
    -- the inbox with no attachment. At that point the attachment ID is gone, so the
    -- remaining safe signal is an empty, no-money/no-COD mail with Manabonk-like text.
    if (header.itemCount or 0) == 0 and HeaderLooksLikeManabonk(header) then
        return true, header.sender, header.subject, nil, "empty"
    end

    return false
end

local function FindMischiefMakerInBags()
    if not GetContainerNumSlots or not GetContainerItemLink then return nil, nil end
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if ExtractItemId(link) == MANABONK_ITEM_ID then
                local _, itemCount, locked = GetContainerItemInfo(bag, slot)
                if not locked and (itemCount or 0) > 0 then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

local function DestroyMischiefMakerFromBags()
    if not PickupContainerItem or not DeleteCursorItem or not CursorHasItem then return false end
    if CursorHasItem() then return false end

    local bag, slot = FindMischiefMakerInBags()
    if not bag then return false end

    if WowNote_IsBagSlotProtected and WowNote_IsBagSlotProtected(bag, slot) then
        Print("Skipped deleting The Mischief Maker because it is protected in WowNote Item Protection.")
        return false
    end

    PickupContainerItem(bag, slot)
    if CursorHasItem() then
        DeleteCursorItem()
        if ClearCursor then ClearCursor() end
        return true
    end
    return false
end

local function PendingMailStillExists(index)
    return index and index >= 1 and index <= GetInboxCount()
end

local function PendingMailHasNoAttachment(index)
    if not PendingMailStillExists(index) then return false end

    local header = GetInboxHeader(index)
    if not header then return false end
    if (header.money or 0) > 0 or (header.codAmount or 0) > 0 then return false end

    -- On 3.3.5a the header can lag behind after TakeInboxItem(). The item link is the
    -- more reliable signal that the attachment slot is already empty. For already-empty
    -- Manabonk letters, also accept the subject/sender marker.
    local itemLink = GetInboxItemLink and GetInboxItemLink(index, 1) or nil
    return (header.itemCount or 0) == 0 or itemLink == nil or HeaderLooksLikeManabonk(header)
end

local function DeletePendingMailIfEmpty()
    if not pendingManabonkMail or not DeleteInboxItem then return false end
    local index = pendingManabonkMail.mailIndex
    if not PendingMailHasNoAttachment(index) then return false end

    DeleteInboxItem(index)
    Print("Cleaned Manabonk mail and removed The Mischief Maker.")
    pendingManabonkMail = nil
    return true
end

local function ScheduleManabonkCleanup(delay)
    if cleanupScheduled then return end
    cleanupScheduled = true

    retryFrame = retryFrame or CreateFrame("Frame")
    local elapsed = 0
    WowNoteProfiler_SetScript(retryFrame, "OnUpdate", "Social.MailCleanupRetry", function(self, delta)
        elapsed = elapsed + (delta or 0)
        if elapsed >= (delay or 0.25) then
            WowNoteProfiler_SetScript(self, "OnUpdate", "Social.MailCleanupRetry", nil)
            cleanupScheduled = false
            if WowNote_ContinueManabonkCleanup then WowNote_ContinueManabonkCleanup() end
        end
    end)
end

function WowNote_ContinueManabonkCleanup()
    if not CleanerEnabled() then return end

    if pendingManabonkMail then
        pendingManabonkMail.attempts = (pendingManabonkMail.attempts or 0) + 1

        -- First try to delete the already-looted wand. Do not depend on BAG_UPDATE_DELAYED:
        -- older 3.3.5a clients/servers are inconsistent here, so timed retries are required.
        if not pendingManabonkMail.destroyed then
            pendingManabonkMail.destroyed = DestroyMischiefMakerFromBags()
        end

        -- Then delete the now-empty mail. The mailbox often needs one or two update ticks
        -- before the attachment state is visible to DeleteInboxItem().
        if DeletePendingMailIfEmpty() then
            ScheduleManabonkCleanup(0.4)
            return
        end

        if pendingManabonkMail.attempts < 30 then
            ScheduleManabonkCleanup(0.5)
        else
            Print("Manabonk cleanup stopped: mailbox did not confirm an empty Manabonk mail.")
            pendingManabonkMail = nil
        end
        return
    end

    if not TakeInboxItem then return end
    local numItems = GetInboxCount()
    for mailIndex = 1, numItems do
        local isManabonk, sender, subject, itemLink, mode = IsSafeManabonkMail(mailIndex)
        if isManabonk and mode == "empty" then
            pendingManabonkMail = { mailIndex = mailIndex, sender = sender, subject = subject, itemLink = itemLink, attempts = 0, destroyed = true }
            if DeletePendingMailIfEmpty() then
                ScheduleManabonkCleanup(0.4)
                return
            end
        elseif isManabonk then
            pendingManabonkMail = { mailIndex = mailIndex, sender = sender, subject = subject, itemLink = itemLink, attempts = 0, destroyed = false }
            TakeInboxItem(mailIndex, 1)
            Print("Manabonk mail detected. Taking The Mischief Maker for cleanup.")
            ScheduleManabonkCleanup(0.5)
            return
        end
    end
end

function WowNote_TryCleanManabonkMail()
    if not CleanerEnabled() then return end
    ScheduleManabonkCleanup(0.1)
end

local function CreateMailboxCleanupButton()
    if cleanupButton or not CreateFrame then return end
    local parent = InboxFrame or MailFrame or UIParent
    cleanupButton = CreateFrame("Button", "WowNoteManabonkCleanButton", parent, "UIPanelButtonTemplate")
    cleanupButton:SetWidth(118)
    cleanupButton:SetHeight(22)
    cleanupButton:SetText("Clean MB")
    if cleanupButton.SetPoint then
        cleanupButton:ClearAllPoints()
        if InboxFrame then
            cleanupButton:SetPoint("TOPRIGHT", InboxFrame, "TOPRIGHT", -34, -52)
        elseif MailFrame then
            cleanupButton:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -42, -58)
        else
            cleanupButton:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    cleanupButton:SetScript("OnClick", function()
        if WowNote_SetManabonkMailCleanerEnabled and not CleanerEnabled() then
            WowNote_SetManabonkMailCleanerEnabled(true)
        end
        WowNote_TryCleanManabonkMail()
    end)
    cleanupButton:Hide()
end

local function UpdateMailboxCleanupButton()
    -- The mailbox-facing button is provided by WowNote_PostalLite. Keep this
    -- function as a safe no-op so the automatic cleaner cannot disturb existing
    -- mailbox buttons or third-party Postal UI.
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GUILD_INVITE_REQUEST")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
WowNoteProfiler_SetScript(frame, "OnEvent", "Social.Events", function(self, event, inviter)
    if event == "GUILD_INVITE_REQUEST" and SocialEnabled() and WowNote_IsGuildInviteBlockEnabled and WowNote_IsGuildInviteBlockEnabled() then
        if DeclineGuild then DeclineGuild() end
        if StaticPopup_Hide then StaticPopup_Hide("GUILD_INVITE") end
        Print("Blocked guild invite" .. (inviter and inviter ~= "" and (" from " .. inviter) or "") .. ".")
        return
    end

    if event == "MAIL_SHOW" then
        UpdateMailboxCleanupButton()
        if CleanerEnabled() then ScheduleManabonkCleanup(0.2) end
        return
    end

    if event == "MAIL_CLOSED" then
        UpdateMailboxCleanupButton()
        pendingManabonkMail = nil
        return
    end

    if event == "MAIL_INBOX_UPDATE" then
        if CleanerEnabled() then ScheduleManabonkCleanup(0.2) end
        return
    end

    if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        if pendingManabonkMail then ScheduleManabonkCleanup(0.2) end
        return
    end
end)

function WowNote_OpenSocial()
    if WowNote_OpenSettings then
        WowNote_OpenSettings()
    end
end
