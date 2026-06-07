-- WowNote_Social.lua
-- Small social-protection helpers.

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GUILD_INVITE_REQUEST")
frame:SetScript("OnEvent", function(self, event, inviter)
    if event == "GUILD_INVITE_REQUEST" and WowNote_IsModuleEnabled and WowNote_IsModuleEnabled("social") and WowNote_IsGuildInviteBlockEnabled and WowNote_IsGuildInviteBlockEnabled() then
        if DeclineGuild then DeclineGuild() end
        if StaticPopup_Hide then StaticPopup_Hide("GUILD_INVITE") end
        Print("Blocked guild invite" .. (inviter and inviter ~= "" and (" from " .. inviter) or "") .. ".")
    end
end)
