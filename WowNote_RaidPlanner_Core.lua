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

function WowNote_RaidPlanner_SendToConfiguredChannel(message)
    local channel = WowNote_RaidPlanner_GetText(RP.channelEdit, "/2")
    channel = string.lower(channel)
    channel = string.gsub(channel, "^%s+", "")
    channel = string.gsub(channel, "%s+$", "")

    if message == "" then
        return false, "Message is empty."
    end

    if channel == "/y" or channel == "y" or channel == "/yell" or channel == "yell" then
        return pcall(SendChatMessage, message, "YELL")
    elseif channel == "/s" or channel == "s" or channel == "/say" or channel == "say" then
        return pcall(SendChatMessage, message, "SAY")
    elseif channel == "/g" or channel == "g" or channel == "/guild" or channel == "guild" then
        return pcall(SendChatMessage, message, "GUILD")
    elseif channel == "/p" or channel == "p" or channel == "/party" or channel == "party" then
        return pcall(SendChatMessage, message, "PARTY")
    elseif channel == "/r" or channel == "r" or channel == "/raid" or channel == "raid" then
        return pcall(SendChatMessage, message, "RAID")
    end

    local number = string.match(channel, "^/?(%d+)$")
    if number then
        return pcall(SendChatMessage, message, "CHANNEL", nil, tonumber(number))
    end

    if GetChannelName then
        local channelNumber = GetChannelName(channel)
        if channelNumber and channelNumber ~= 0 then
            return pcall(SendChatMessage, message, "CHANNEL", nil, channelNumber)
        end
    end

    return false, "Unknown channel: " .. tostring(channel)
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
    local ok, err = WowNote_RaidPlanner_SendToConfiguredChannel(message)
    if ok then
        WowNote_RaidPlanner_SetStatus("Raid message posted.")
    else
        WowNote_RaidPlanner_SetStatus(err or "Could not post raid message.")
    end
end
