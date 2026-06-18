-- WowNote Raid Planner core logic
-- Loaded after WowNote.lua through WowNote.toc.

WowNote_RaidPlanner = WowNote_RaidPlanner or {}
local RP = WowNote_RaidPlanner
local WNI = WowNote_Internal or {}

local InitDB = WNI.InitDB
local PercentEncode = WNI.PercentEncode
local PercentDecode = WNI.PercentDecode
local Base64Encode = WNI.Base64Encode
local Base64Decode = WNI.Base64Decode
local Trim = WNI.Trim or function(text)
    text = text or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end
local CompressText = WNI.CompressText or function(text) return text or "" end
local DecompressText = WNI.DecompressText or function(text) return text or "" end

RP.defaultTemplate = "LFM %name %size, %tank, %heal, %dps %info %contact"
RP.roles = { "tanks", "healers", "dps", "mdps", "rdps" }
RP.roleLabels = {
    tanks = "Tanks",
    healers = "Healers",
    dps = "DPS",
    mdps = "mDPS",
    rdps = "rDPS",
}

function WowNote_RaidPlanner_SetStatus(text)
    if RP.statusText then RP.statusText:SetText(text or "") end
end

function WowNote_RaidPlanner_GetText(edit, fallback)
    if edit and edit.GetText then
        local text = Trim(edit:GetText() or "")
        if text ~= "" then return text end
    end
    return fallback or ""
end

function WowNote_RaidPlanner_GetNumber(edit)
    local text = edit and edit.GetText and edit:GetText() or "0"
    local value = tonumber(text) or 0
    if value < 0 then value = 0 end
    return value
end

function WowNote_RaidPlanner_SetNumber(edit, value)
    if not edit then return end
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    edit:SetText(tostring(value))
end

function WowNote_RaidPlanner_FormatRole(count, singular, plural)
    count = tonumber(count) or 0
    if count <= 0 then return "" end
    if count == 1 then return "1 " .. singular end
    return tostring(count) .. " " .. (plural or (singular .. "s"))
end

function WowNote_RaidPlanner_CleanMessage(text)
    text = tostring(text or "")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "%s+,", ",")
    for _ = 1, 8 do
        text = string.gsub(text, ",%s*,", ",")
    end
    text = string.gsub(text, ",%s*/", " /")
    text = string.gsub(text, ",%s*$", "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

function WowNote_RaidPlanner_UpdateHaveFromRoster()
    if RP.UpdateHaveFromRoster then
        RP.UpdateHaveFromRoster()
    end
end

function WowNote_RaidPlanner_UpdatePreview()
    if not RP.frame then return "" end

    WowNote_RaidPlanner_UpdateHaveFromRoster()

    local raidName = WowNote_RaidPlanner_GetText(RP.raidNameEdit, "Raid")
    local raidSize = WowNote_RaidPlanner_GetText(RP.sizeEdit, "10")
    local info = WowNote_RaidPlanner_GetText(RP.infoEdit, "")
    local contact = WowNote_RaidPlanner_GetText(RP.contactEdit, "/w me")
    local template = WowNote_RaidPlanner_GetText(RP.templateEdit, RP.defaultTemplate)

    local tanksMissing = WowNote_RaidPlanner_GetNumber(RP.tankNeedEdit) - WowNote_RaidPlanner_GetNumber(RP.tankHaveEdit)
    local healsMissing = WowNote_RaidPlanner_GetNumber(RP.healNeedEdit) - WowNote_RaidPlanner_GetNumber(RP.healHaveEdit)
    local dpsNeed = WowNote_RaidPlanner_GetNumber(RP.dpsNeedEdit)
    local mdpsNeed = WowNote_RaidPlanner_GetNumber(RP.mdpsNeedEdit)
    local rdpsNeed = WowNote_RaidPlanner_GetNumber(RP.rdpsNeedEdit)
    local dpsMissing = dpsNeed - WowNote_RaidPlanner_GetNumber(RP.dpsHaveEdit)
    local mdpsMissing = mdpsNeed - WowNote_RaidPlanner_GetNumber(RP.mdpsHaveEdit)
    local rdpsMissing = rdpsNeed - WowNote_RaidPlanner_GetNumber(RP.rdpsHaveEdit)

    local tankText = WowNote_RaidPlanner_FormatRole(tanksMissing, "Tank", "Tanks")
    local healText = WowNote_RaidPlanner_FormatRole(healsMissing, "Heal", "Heals")
    local dpsText = ""

    if mdpsNeed > 0 or rdpsNeed > 0 then
        local parts = {}
        local mdpsText = WowNote_RaidPlanner_FormatRole(mdpsMissing, "mDPS", "mDPS")
        local rdpsText = WowNote_RaidPlanner_FormatRole(rdpsMissing, "rDPS", "rDPS")
        if mdpsText ~= "" then table.insert(parts, mdpsText) end
        if rdpsText ~= "" then table.insert(parts, rdpsText) end
        dpsText = table.concat(parts, ", ")
    else
        dpsText = WowNote_RaidPlanner_FormatRole(dpsMissing, "DPS", "DPS")
    end

    local message = template
    message = string.gsub(message, "%%name", raidName)
    message = string.gsub(message, "%%size", raidSize)
    message = string.gsub(message, "%%tank", tankText)
    message = string.gsub(message, "%%heal", healText)
    message = string.gsub(message, "%%dps", dpsText)
    message = string.gsub(message, "%%mdps", "")
    message = string.gsub(message, "%%rdps", "")
    message = string.gsub(message, "%%info", info)
    message = string.gsub(message, "%%contact", contact)
    message = WowNote_RaidPlanner_CleanMessage(message)

    if RP.previewEdit then RP.previewEdit:SetText(message) end
    return message
end

local function SafeSendChatMessage(message, chatType, language, target)
    if not SendChatMessage then return false, "Chat API is unavailable." end
    local ok, result = pcall(SendChatMessage, message, chatType, language, target)
    if not ok then return false, result end
    if result == false then return false, "Chat message was rejected." end
    return true
end

local function ResolveConfiguredChannel(token)
    local original = Trim(token or "")
    local channel = string.lower(original)

    if channel == "" then
        return nil, "Channel is empty."
    elseif channel == "/y" or channel == "y" or channel == "/yell" or channel == "yell" then
        return { chatType = "YELL", label = original }
    elseif channel == "/s" or channel == "s" or channel == "/say" or channel == "say" then
        return { chatType = "SAY", label = original }
    elseif channel == "/g" or channel == "g" or channel == "/guild" or channel == "guild" then
        return { chatType = "GUILD", label = original }
    elseif channel == "/o" or channel == "o" or channel == "/officer" or channel == "officer" then
        return { chatType = "OFFICER", label = original }
    elseif channel == "/p" or channel == "p" or channel == "/party" or channel == "party" then
        return { chatType = "PARTY", label = original }
    elseif channel == "/r" or channel == "r" or channel == "/raid" or channel == "raid" then
        return { chatType = "RAID", label = original }
    elseif channel == "/rw" or channel == "rw" or channel == "/raidwarning" or channel == "raidwarning" then
        return { chatType = "RAID_WARNING", label = original }
    elseif channel == "/bg" or channel == "bg" or channel == "/battleground" or channel == "battleground" then
        return { chatType = "BATTLEGROUND", label = original }
    end

    local number = string.match(channel, "^/?(%d+)$")
    if number then
        return { chatType = "CHANNEL", target = tonumber(number), label = original }
    end

    if GetChannelName then
        local lookupName = string.gsub(original, "^/", "")
        local channelNumber = GetChannelName(lookupName)
        if channelNumber and channelNumber ~= 0 then
            return { chatType = "CHANNEL", target = channelNumber, label = original }
        end
    end

    return nil, "Unknown channel: " .. tostring(original)
end

local function ParseConfiguredChannels(text)
    text = tostring(text or "")
    text = string.gsub(text, "[,;+|\r\n\t]+", " ")

    local channels = {}
    local seen = {}
    for token in string.gmatch(text, "%S+") do
        local destination, err = ResolveConfiguredChannel(token)
        if not destination then return nil, err end

        local key = destination.chatType .. ":" .. tostring(destination.target or "")
        if not seen[key] then
            seen[key] = true
            table.insert(channels, destination)
        end
    end

    if table.getn(channels) == 0 then
        return nil, "No post channel configured."
    end
    return channels
end
RP.ParseConfiguredChannels = ParseConfiguredChannels

local function FinishRaidPostQueue()
    local queue = RP.postQueue
    if not queue then return end

    if RP.postQueueFrame then
        WowNoteProfiler_SetScript(RP.postQueueFrame, "OnUpdate", "RaidPlanner.PostQueue", nil)
        RP.postQueueFrame:Hide()
    end
    RP.postQueue = nil
    RP.postQueueActive = false

    local total = queue.total or 0
    local successCount = queue.successCount or 0
    local failures = queue.failures or {}
    if table.getn(failures) == 0 then
        if total == 1 then
            WowNote_RaidPlanner_SetStatus("Raid message posted.")
        else
            WowNote_RaidPlanner_SetStatus("Raid message posted to " .. tostring(total) .. " channels.")
        end
    elseif successCount > 0 then
        WowNote_RaidPlanner_SetStatus("Posted to " .. tostring(successCount) .. " of " .. tostring(total)
            .. " channels. Failed: " .. table.concat(failures, "; "))
    else
        WowNote_RaidPlanner_SetStatus("Could not post raid message. " .. table.concat(failures, "; "))
    end
end

local function ProcessNextRaidPost()
    local queue = RP.postQueue
    if not queue then return end

    local item = table.remove(queue.items, 1)
    if not item then
        FinishRaidPostQueue()
        return
    end

    local ok, err = SafeSendChatMessage(queue.message, item.chatType, nil, item.target)
    if ok then
        queue.successCount = queue.successCount + 1
    else
        table.insert(queue.failures, tostring(item.label or item.chatType) .. " (" .. tostring(err or "unknown error") .. ")")
    end

    if table.getn(queue.items) == 0 then
        FinishRaidPostQueue()
    end
end

local function StartRaidPostQueue(message, channels)
    if RP.postQueueActive then
        return false, "A raid message is already being posted."
    end

    local total = table.getn(channels)
    RP.postQueue = {
        message = message,
        items = channels,
        total = total,
        successCount = 0,
        failures = {},
        elapsed = 0,
    }
    RP.postQueueActive = true

    -- Send the first destination immediately. Additional channels are delayed
    -- slightly so identical cross-channel posts are not dropped by chat throttling.
    ProcessNextRaidPost()
    if RP.postQueueActive then
        if not RP.postQueueFrame then
            RP.postQueueFrame = CreateFrame("Frame")
        end
        WowNoteProfiler_SetScript(RP.postQueueFrame, "OnUpdate", "RaidPlanner.PostQueue", function(_, elapsed)
            local queue = RP.postQueue
            if not queue then return end
            queue.elapsed = (queue.elapsed or 0) + (elapsed or 0)
            if queue.elapsed < 0.75 then return end
            queue.elapsed = queue.elapsed - 0.75
            ProcessNextRaidPost()
        end)
        RP.postQueueFrame:Show()
    end

    return true, nil, total
end

function WowNote_RaidPlanner_SendToConfiguredChannel(message)
    if message == "" then
        return false, "Message is empty."
    end
    if not SendChatMessage then
        return false, "Chat API is unavailable."
    end

    local configured = WowNote_RaidPlanner_GetText(RP.channelEdit, "/2")
    local channels, err = ParseConfiguredChannels(configured)
    if not channels then return false, err end

    return StartRaidPostQueue(message, channels)
end

function WowNote_RaidPlanner_GetCurrentPresetData()
    if InitDB then InitDB() end
    return {
        size = WowNote_RaidPlanner_GetText(RP.sizeEdit, "10"),
        raidName = WowNote_RaidPlanner_GetText(RP.raidNameEdit, ""),
        tankNeed = WowNote_RaidPlanner_GetNumber(RP.tankNeedEdit),
        tankHave = WowNote_RaidPlanner_GetNumber(RP.tankHaveEdit),
        healNeed = WowNote_RaidPlanner_GetNumber(RP.healNeedEdit),
        healHave = WowNote_RaidPlanner_GetNumber(RP.healHaveEdit),
        dpsNeed = WowNote_RaidPlanner_GetNumber(RP.dpsNeedEdit),
        dpsHave = WowNote_RaidPlanner_GetNumber(RP.dpsHaveEdit),
        mdpsNeed = WowNote_RaidPlanner_GetNumber(RP.mdpsNeedEdit),
        mdpsHave = WowNote_RaidPlanner_GetNumber(RP.mdpsHaveEdit),
        rdpsNeed = WowNote_RaidPlanner_GetNumber(RP.rdpsNeedEdit),
        rdpsHave = WowNote_RaidPlanner_GetNumber(RP.rdpsHaveEdit),
        channel = WowNote_RaidPlanner_GetText(RP.channelEdit, "/2"),
        template = WowNote_RaidPlanner_GetText(RP.templateEdit, RP.defaultTemplate),
        info = WowNote_RaidPlanner_GetText(RP.infoEdit, ""),
        contact = WowNote_RaidPlanner_GetText(RP.contactEdit, "/w me"),
        internalNote = WowNote_RaidPlanner_GetText(RP.internalNoteEdit, ""),
        autoRemove = RP.autoRemoveCheck and RP.autoRemoveCheck:GetChecked() and true or false,
        roster = RP.GetRosterData and RP.GetRosterData() or {},
    }
end

function WowNote_RaidPlanner_ApplyPresetData(preset, presetName)
    if type(preset) ~= "table" then
        WowNote_RaidPlanner_SetStatus("Import failed: invalid preset data.")
        return false
    end

    RP.sizeEdit:SetText(preset.size or "10")
    RP.raidNameEdit:SetText(preset.raidName or "")
    RP.tankNeedEdit:SetText(tostring(preset.tankNeed or 0)); RP.tankHaveEdit:SetText(tostring(preset.tankHave or 0))
    RP.healNeedEdit:SetText(tostring(preset.healNeed or 0)); RP.healHaveEdit:SetText(tostring(preset.healHave or 0))
    RP.dpsNeedEdit:SetText(tostring(preset.dpsNeed or 0)); RP.dpsHaveEdit:SetText(tostring(preset.dpsHave or 0))
    RP.mdpsNeedEdit:SetText(tostring(preset.mdpsNeed or 0)); RP.mdpsHaveEdit:SetText(tostring(preset.mdpsHave or 0))
    RP.rdpsNeedEdit:SetText(tostring(preset.rdpsNeed or 0)); RP.rdpsHaveEdit:SetText(tostring(preset.rdpsHave or 0))
    RP.channelEdit:SetText(preset.channel or "/2")
    RP.templateEdit:SetText(preset.template or RP.defaultTemplate)
    RP.infoEdit:SetText(preset.info or "")
    RP.contactEdit:SetText(preset.contact or "/w me")
    RP.internalNoteEdit:SetText(preset.internalNote or "")
    if RP.autoRemoveCheck then RP.autoRemoveCheck:SetChecked(preset.autoRemove and true or false) end
    if RP.SetRosterData then RP.SetRosterData(preset.roster or {}) end
    if presetName and presetName ~= "" and RP.presetNameEdit then
        RP.presetNameEdit:SetText(presetName)
    end
    WowNote_RaidPlanner_UpdatePreview()
    return true
end


function WowNote_RaidPlanner_GetPresetNames()
    if InitDB then InitDB() end
    local names = {}
    if WowNoteDB and WowNoteDB.raidPlannerPresets then
        for name in pairs(WowNoteDB.raidPlannerPresets) do
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function WowNote_RaidPlanner_SelectPreset(name)
    if not name or name == "" then return end
    if RP.presetNameEdit then RP.presetNameEdit:SetText(name) end
    RP.selectedPresetName = name
    WowNote_RaidPlanner_SetStatus("Selected raid preset: " .. name .. ". Click Load to open it or Save Preset to overwrite it.")
    if WowNote_RaidPlanner_RefreshPresetList then WowNote_RaidPlanner_RefreshPresetList(name) end
end

function WowNote_RaidPlanner_SavePreset()
    if InitDB then InitDB() end
    local name = WowNote_RaidPlanner_GetText(RP.presetNameEdit, "")
    if name == "" then
        WowNote_RaidPlanner_SetStatus("Enter a preset name first.")
        return
    end
    WowNoteDB.raidPlannerPresets[name] = WowNote_RaidPlanner_GetCurrentPresetData()
    WowNote_RaidPlanner_SetStatus("Raid preset saved: " .. name)
    RP.selectedPresetName = name
    if WowNote_RaidPlanner_RefreshPresetList then WowNote_RaidPlanner_RefreshPresetList(name) end
end

function WowNote_RaidPlanner_LoadPreset()
    if InitDB then InitDB() end
    local name = WowNote_RaidPlanner_GetText(RP.presetNameEdit, "")
    local preset = name ~= "" and WowNoteDB.raidPlannerPresets[name]
    if type(preset) ~= "table" then
        WowNote_RaidPlanner_SetStatus("Preset not found: " .. tostring(name))
        return
    end
    if WowNote_RaidPlanner_ApplyPresetData(preset, name) then
        WowNote_RaidPlanner_SetStatus("Raid preset loaded: " .. name)
        RP.selectedPresetName = name
        if WowNote_RaidPlanner_RefreshPresetList then WowNote_RaidPlanner_RefreshPresetList(name) end
    end
end

function WowNote_RaidPlanner_DeletePreset()
    if InitDB then InitDB() end
    local name = WowNote_RaidPlanner_GetText(RP.presetNameEdit, "")
    if name == "" or not WowNoteDB.raidPlannerPresets[name] then
        WowNote_RaidPlanner_SetStatus("Preset not found.")
        return
    end
    WowNoteDB.raidPlannerPresets[name] = nil
    WowNote_RaidPlanner_SetStatus("Raid preset deleted: " .. name)
    RP.selectedPresetName = nil
    if RP.presetNameEdit then RP.presetNameEdit:SetText("") end
    if WowNote_RaidPlanner_RefreshPresetList then WowNote_RaidPlanner_RefreshPresetList(nil) end
end

local function SerializeRoster(roster)
    local parts = {}
    for _, role in ipairs(RP.roles) do
        local roleRows = roster and roster[role] or {}
        local roleParts = {}
        for _, entry in ipairs(roleRows) do
            local name = entry and entry.name or ""
            local class = entry and entry.class or ""
            if name ~= "" or class ~= "" then
                table.insert(roleParts, PercentEncode(name) .. "," .. PercentEncode(class))
            end
        end
        table.insert(parts, role .. ":" .. table.concat(roleParts, ";"))
    end
    return table.concat(parts, "|")
end

local function DeserializeRoster(text)
    local roster = {}
    for _, role in ipairs(RP.roles) do roster[role] = {} end
    text = text or ""
    for block in string.gmatch(text .. "|", "(.-)|") do
        local role, payload = string.match(block, "^([^:]+):(.*)$")
        if role and roster[role] then
            for item in string.gmatch((payload or "") .. ";", "(.-);") do
                if item ~= "" then
                    local name, class = string.match(item, "^([^,]*),(.*)$")
                    table.insert(roster[role], { name = PercentDecode(name or ""), class = PercentDecode(class or "") })
                end
            end
        end
    end
    return roster
end

function WowNote_RaidPlanner_SerializePreset(preset, presetName)
    preset = preset or {}
    return "raidPresetVersion=1.1.0"
        .. "\nname=" .. PercentEncode(presetName or "")
        .. "\nsize=" .. PercentEncode(preset.size or "10")
        .. "\nraidName=" .. PercentEncode(preset.raidName or "")
        .. "\ntankNeed=" .. tostring(preset.tankNeed or 0)
        .. "\ntankHave=" .. tostring(preset.tankHave or 0)
        .. "\nhealNeed=" .. tostring(preset.healNeed or 0)
        .. "\nhealHave=" .. tostring(preset.healHave or 0)
        .. "\ndpsNeed=" .. tostring(preset.dpsNeed or 0)
        .. "\ndpsHave=" .. tostring(preset.dpsHave or 0)
        .. "\nmdpsNeed=" .. tostring(preset.mdpsNeed or 0)
        .. "\nmdpsHave=" .. tostring(preset.mdpsHave or 0)
        .. "\nrdpsNeed=" .. tostring(preset.rdpsNeed or 0)
        .. "\nrdpsHave=" .. tostring(preset.rdpsHave or 0)
        .. "\nchannel=" .. PercentEncode(preset.channel or "/2")
        .. "\ntemplate=" .. PercentEncode(preset.template or RP.defaultTemplate)
        .. "\ninfo=" .. PercentEncode(preset.info or "")
        .. "\ncontact=" .. PercentEncode(preset.contact or "/w me")
        .. "\ninternalNote=" .. PercentEncode(preset.internalNote or "")
        .. "\nautoRemove=" .. (preset.autoRemove and "1" or "0")
        .. "\nroster=" .. PercentEncode(SerializeRoster(preset.roster or {}))
end

function WowNote_RaidPlanner_DeserializePreset(text)
    local preset = {}
    local presetName = ""
    text = text or ""
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        local key, value = string.match(line, "^([^=]+)=(.*)$")
        if key == "name" then presetName = PercentDecode(value or "")
        elseif key == "size" then preset.size = PercentDecode(value or "")
        elseif key == "raidName" then preset.raidName = PercentDecode(value or "")
        elseif key == "tankNeed" then preset.tankNeed = tonumber(value) or 0
        elseif key == "tankHave" then preset.tankHave = tonumber(value) or 0
        elseif key == "healNeed" then preset.healNeed = tonumber(value) or 0
        elseif key == "healHave" then preset.healHave = tonumber(value) or 0
        elseif key == "dpsNeed" then preset.dpsNeed = tonumber(value) or 0
        elseif key == "dpsHave" then preset.dpsHave = tonumber(value) or 0
        elseif key == "mdpsNeed" then preset.mdpsNeed = tonumber(value) or 0
        elseif key == "mdpsHave" then preset.mdpsHave = tonumber(value) or 0
        elseif key == "rdpsNeed" then preset.rdpsNeed = tonumber(value) or 0
        elseif key == "rdpsHave" then preset.rdpsHave = tonumber(value) or 0
        elseif key == "channel" then preset.channel = PercentDecode(value or "")
        elseif key == "template" then preset.template = PercentDecode(value or "")
        elseif key == "info" then preset.info = PercentDecode(value or "")
        elseif key == "contact" then preset.contact = PercentDecode(value or "")
        elseif key == "internalNote" then preset.internalNote = PercentDecode(value or "")
        elseif key == "autoRemove" then preset.autoRemove = value == "1"
        elseif key == "roster" then preset.roster = DeserializeRoster(PercentDecode(value or ""))
        end
    end
    return preset, presetName
end

function WowNote_RaidPlanner_EncodePreset(preset, presetName)
    local serialized = WowNote_RaidPlanner_SerializePreset(preset, presetName)
    local compressed = CompressText(serialized)
    return "WNRP1:" .. Base64Encode(compressed)
end

function WowNote_RaidPlanner_DecodePreset(exportText)
    exportText = Trim(exportText or "")
    exportText = string.gsub(exportText, "%s+", "")
    if string.sub(exportText, 1, 6) ~= "WNRP1:" then
        return nil, nil, "Invalid raid preset export. Expected WNRP1: prefix."
    end
    local encoded = string.sub(exportText, 7)
    local decoded = Base64Decode(encoded)
    if not decoded or decoded == "" then
        return nil, nil, "Import failed: Base64 decode returned empty data."
    end
    local serialized = DecompressText(decoded)
    local preset, presetName = WowNote_RaidPlanner_DeserializePreset(serialized)
    if type(preset) ~= "table" then
        return nil, nil, "Import failed: invalid preset payload."
    end
    return preset, presetName, nil
end

function WowNote_RaidPlanner_Reset()
    RP.sizeEdit:SetText("10")
    RP.raidNameEdit:SetText("")
    RP.tankNeedEdit:SetText("2"); RP.tankHaveEdit:SetText("0")
    RP.healNeedEdit:SetText("3"); RP.healHaveEdit:SetText("0")
    RP.dpsNeedEdit:SetText("5"); RP.dpsHaveEdit:SetText("0")
    RP.mdpsNeedEdit:SetText("0"); RP.mdpsHaveEdit:SetText("0")
    RP.rdpsNeedEdit:SetText("0"); RP.rdpsHaveEdit:SetText("0")
    RP.channelEdit:SetText("/2")
    RP.templateEdit:SetText(RP.defaultTemplate)
    RP.infoEdit:SetText("")
    RP.contactEdit:SetText("/w me")
    RP.internalNoteEdit:SetText("")
    if RP.autoRemoveCheck then RP.autoRemoveCheck:SetChecked(true) end
    if RP.ClearRoster then RP.ClearRoster() end
    WowNote_RaidPlanner_UpdatePreview()
    WowNote_RaidPlanner_SetStatus("Raid planner reset.")
end

function WowNote_RaidPlanner_Post()
    local message = WowNote_RaidPlanner_UpdatePreview()
    local ok, err, channelCount = WowNote_RaidPlanner_SendToConfiguredChannel(message)
    if not ok then
        WowNote_RaidPlanner_SetStatus(err or "Could not post raid message.")
    elseif RP.postQueueActive then
        WowNote_RaidPlanner_SetStatus("Posting raid message to " .. tostring(channelCount or 0) .. " channels...")
    end
end
