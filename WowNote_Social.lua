-- WowNote_Social.lua
-- Small social-protection helpers.

local MANABONK_ITEM_ID = 44817 -- The Mischief Maker
local pendingManabonkMail
local waitingForBagUpdate = false
local cleanupScheduled = false

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

local function IsManabonkAttachment(mailIndex)
    if not mailIndex or not GetInboxHeaderInfo or not GetInboxItemLink then return false end
    local _, _, sender, subject, money, codAmount, _, itemCount, _, _, _, _ = GetInboxHeaderInfo(mailIndex)
    if (codAmount or 0) > 0 or (money or 0) > 0 then return false end
    if itemCount ~= 1 then return false end

    local itemLink = GetInboxItemLink(mailIndex, 1)
    if ExtractItemId(itemLink) ~= MANABONK_ITEM_ID then return false end

    -- Keep the check intentionally conservative without relying on localized sender text.
    -- The exact attachment item ID plus exactly one attachment is the stable identifier.
    return true, sender, subject, itemLink
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
    PickupContainerItem(bag, slot)
    if CursorHasItem() then
        DeleteCursorItem()
        return true
    end
    return false
end

local function DeletePendingMailIfEmpty()
    if not pendingManabonkMail or not DeleteInboxItem or not GetInboxHeaderInfo then return false end
    local index = pendingManabonkMail.mailIndex
    if not index then return false end
    local _, _, _, _, money, codAmount, _, itemCount = GetInboxHeaderInfo(index)
    if (money or 0) == 0 and (codAmount or 0) == 0 and (itemCount or 0) == 0 then
        DeleteInboxItem(index)
        Print("Cleaned Manabonk mail and removed The Mischief Maker.")
        pendingManabonkMail = nil
        waitingForBagUpdate = false
        return true
    end
    return false
end

local function ContinueManabonkCleanup()
    cleanupScheduled = false
    if not CleanerEnabled() then return end

    if pendingManabonkMail then
        if waitingForBagUpdate then return end
        local destroyed = DestroyMischiefMakerFromBags()
        if destroyed then
            DeletePendingMailIfEmpty()
        else
            -- If the item is still moving/locked, try again after the next bag update.
            waitingForBagUpdate = true
        end
        return
    end

    if not GetInboxNumItems or not TakeInboxItem then return end
    local numItems = GetInboxNumItems() or 0
    for mailIndex = 1, numItems do
        local isManabonk, sender, subject, itemLink = IsManabonkAttachment(mailIndex)
        if isManabonk then
            pendingManabonkMail = { mailIndex = mailIndex, sender = sender, subject = subject, itemLink = itemLink }
            waitingForBagUpdate = true
            TakeInboxItem(mailIndex, 1)
            Print("Manabonk mail detected. Taking The Mischief Maker for cleanup.")
            return
        end
    end
end

local function ScheduleManabonkCleanup()
    if cleanupScheduled then return end
    cleanupScheduled = true
    local delayFrame = CreateFrame("Frame")
    local elapsed = 0
    delayFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + (delta or 0)
        if elapsed >= 0.25 then
            self:SetScript("OnUpdate", nil)
            ContinueManabonkCleanup()
        end
    end)
end

function WowNote_TryCleanManabonkMail()
    if not CleanerEnabled() then return end
    ScheduleManabonkCleanup()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GUILD_INVITE_REQUEST")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function(self, event, inviter)
    if event == "GUILD_INVITE_REQUEST" and SocialEnabled() and WowNote_IsGuildInviteBlockEnabled and WowNote_IsGuildInviteBlockEnabled() then
        if DeclineGuild then DeclineGuild() end
        if StaticPopup_Hide then StaticPopup_Hide("GUILD_INVITE") end
        Print("Blocked guild invite" .. (inviter and inviter ~= "" and (" from " .. inviter) or "") .. ".")
        return
    end

    if event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        if CleanerEnabled() then ScheduleManabonkCleanup() end
        return
    end

    if event == "BAG_UPDATE_DELAYED" then
        if pendingManabonkMail then
            waitingForBagUpdate = false
            ScheduleManabonkCleanup()
        end
        return
    end
end)
