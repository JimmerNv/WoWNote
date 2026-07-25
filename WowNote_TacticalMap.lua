-- WowNote Tactical Map / Boss Board
-- Shareable drawing board for boss and raid planning. This is not world-bound.

local TM = {}
WowNote_TacticalMap = TM

local frame, board, statusText, nameEdit, transferFrame, transferEdit
local mapInfoText, currentMapName, currentMapToken, currentMapFloor
local boardTiles = {}
local mapTileContainer, drawLayer, mapSourceTextures = nil, nil, {}
local presetScrollFrame, presetContentFrame, presetRows, selectedPresetName = nil, nil, {}, nil
local colorButtons = {}
local strokes = {}
local currentStroke, isDrawing
local drawMode = false
local currentColorIndex = 1
local thickness = 5
local lastX, lastY
local receiveFrame

local colors = {
    { name = "Yellow", r = 1.00, g = 0.90, b = 0.00 },
    { name = "Red",    r = 1.00, g = 0.05, b = 0.05 },
    { name = "Green",  r = 0.10, g = 1.00, b = 0.10 },
    { name = "Blue",   r = 0.20, g = 0.50, b = 1.00 },
    { name = "Cyan",   r = 0.00, g = 1.00, b = 1.00 },
    { name = "Purple", r = 0.75, g = 0.20, b = 1.00 },
    { name = "Orange", r = 1.00, g = 0.45, b = 0.00 },
    { name = "White",  r = 1.00, g = 1.00, b = 1.00 },
    { name = "Black",  r = 0.00, g = 0.00, b = 0.00 },
    { name = "Pink",   r = 1.00, g = 0.25, b = 0.65 },
}

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("WowNote: " .. tostring(msg)) end
end

local function MakeButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 80, height or 22)
    b:SetText(text or "Button")
    if parent and parent.GetFrameLevel then b:SetFrameLevel((parent:GetFrameLevel() or 0) + 5) end
    b:Enable()
    b:EnableMouse(true)
    return b
end

local function LiftControl(control, parent, offset)
    if control and control.SetFrameLevel and parent and parent.GetFrameLevel then
        control:SetFrameLevel((parent:GetFrameLevel() or 0) + (offset or 5))
    end
    if control and control.EnableMouse then control:EnableMouse(true) end
    if control and control.Enable then control:Enable() end
end

local function EnsureDB()
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.tacticalMaps) ~= "table" then WowNoteDB.tacticalMaps = {} end
end

local function SetFront(f)
    if not f then return end
    if WowNote_Internal and WowNote_Internal.RaiseFrame then
        WowNote_Internal.RaiseFrame(f)
        return
    end
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(100)
    if f.SetToplevel then f:SetToplevel(true) end
    if f.Raise then f:Raise() end
end

local function BoardSize()
    if not board then return 1, 1 end
    return math.max(1, board:GetWidth() or 1), math.max(1, board:GetHeight() or 1)
end

local function EnsureBoardTiles()
    if not board then return end
    if not mapTileContainer then
        mapTileContainer = CreateFrame("Frame", nil, board)
        mapTileContainer:SetAllPoints(board)
        mapTileContainer:SetFrameLevel((board:GetFrameLevel() or 0) + 1)
        mapTileContainer:EnableMouse(false)
    end
    if #boardTiles > 0 then return end
    for i = 1, 12 do
        local tex = mapTileContainer:CreateTexture(nil, "ARTWORK")
        tex:SetVertexColor(1, 1, 1, 0.94)
        tex:Hide()
        boardTiles[i] = tex
    end
end

local function HideBoardTiles()
    for _, tex in ipairs(boardTiles) do
        tex:Hide()
        tex:SetTexture(nil)
    end
end

local function FindWorldMapSourceTextures()
    local function collect()
        local found = {}
        local patterns = { "WorldMapDetailFrameTile", "WorldMapDetailTile", "WorldMapDetailFrameTexture" }
        for _, prefix in ipairs(patterns) do
            for i = 1, 20 do
                local tex = _G[prefix .. i]
                if tex and tex.GetTexture and tex:GetTexture() then
                    found[#found + 1] = tex
                end
            end
            if #found > 0 then break end
        end
        return found
    end

    local found = collect()
    if #found > 0 then return found end

    local wasShown = WorldMapFrame and WorldMapFrame:IsShown()
    if WorldMapFrame and WorldMapFrame.Show then
        pcall(WorldMapFrame.Show, WorldMapFrame)
        if WorldMapFrame_Update then pcall(WorldMapFrame_Update) end
        found = collect()
        if WorldMapFrame.Hide and not wasShown then
            pcall(WorldMapFrame.Hide, WorldMapFrame)
        end
    end
    return found
end

local function LayoutBoardTilesFromSource(sources)
    if not board then return false end
    EnsureBoardTiles()
    HideBoardTiles()
    sources = sources or mapSourceTextures or {}
    if #sources == 0 then return false end

    local parent = nil
    for _, src in ipairs(sources) do
        if src and src.GetParent then
            parent = src:GetParent()
            if parent then break end
        end
    end
    if not parent then return false end

    local pW = parent.GetWidth and parent:GetWidth() or 1002
    local pH = parent.GetHeight and parent:GetHeight() or 668
    local bW, bH = BoardSize()
    if pW <= 0 or pH <= 0 then return false end

    for i, src in ipairs(sources) do
        local dst = boardTiles[i]
        if src and dst then
            local texturePath = src:GetTexture()
            if texturePath then
                local l = (src:GetLeft() or 0) - (parent:GetLeft() or 0)
                local t = (parent:GetTop() or 0) - (src:GetTop() or 0)
                local w = src:GetWidth() or 256
                local h = src:GetHeight() or 256
                dst:ClearAllPoints()
                dst:SetPoint("TOPLEFT", mapTileContainer, "TOPLEFT", (l / pW) * bW, -((t / pH) * bH))
                dst:SetWidth((w / pW) * bW)
                dst:SetHeight((h / pH) * bH)
                dst:SetTexture(texturePath)
                if src.GetTexCoord then
                    local ulx, uly, llx, lly, urx, ury, lrx, lry = src:GetTexCoord()
                    if ulx then
                        dst:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
                    else
                        dst:SetTexCoord(0,1,0,1)
                    end
                end
                dst:Show()
            end
        end
    end
    return true
end

local function TryLegacyTexturePaths(token, floor)
    return false
end

local function SetFallbackBoardBackground(label)
    if not board then return end
    EnsureBoardTiles()
    HideBoardTiles()
    if board.bg then
        board.bg:SetTexture(0.08, 0.08, 0.08, 0.95)
    end
    if mapInfoText then
        mapInfoText:SetText(label or "Map background: manual board")
    end
end

local function ApplyMapBackground(token, floor, displayName)
    if not board then return false end
    EnsureBoardTiles()

    if SetMapToCurrentZone then pcall(SetMapToCurrentZone) end
    local numFloors = GetNumDungeonMapLevels and GetNumDungeonMapLevels() or 0
    local wantedFloor = floor or 0
    if numFloors and numFloors > 0 then
        if wantedFloor <= 0 then wantedFloor = 1 end
        if SetDungeonMapLevel then pcall(SetDungeonMapLevel, wantedFloor) end
    end
    if WorldMapFrame_Update then pcall(WorldMapFrame_Update) end

    mapSourceTextures = FindWorldMapSourceTextures()
    if #mapSourceTextures == 0 or not LayoutBoardTilesFromSource(mapSourceTextures) then
        if not TryLegacyTexturePaths(token, wantedFloor) then
            SetFallbackBoardBackground("Map background: unavailable. Open the world map once, then click Use Current Map again.")
            return false
        end
    end

    if board.bg then board.bg:SetTexture(0.02, 0.02, 0.02, 0.82) end
    currentMapName = displayName or token or (GetMapInfo and GetMapInfo()) or "Unknown"
    currentMapToken = token or (GetMapInfo and GetMapInfo()) or nil
    currentMapFloor = wantedFloor or 0
    if mapInfoText then
        local floorText = (currentMapFloor and currentMapFloor > 0) and (" | Floor " .. tostring(currentMapFloor)) or ""
        mapInfoText:SetText("Map background: " .. tostring(currentMapName or "Unknown") .. floorText .. " (auto)")
    end
    return true
end

local function CaptureCurrentMapBackground()
    if SetMapToCurrentZone then pcall(SetMapToCurrentZone) end
    local token = GetMapInfo and GetMapInfo() or nil
    local floor = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
    local numFloors = GetNumDungeonMapLevels and GetNumDungeonMapLevels() or 0
    if numFloors and numFloors > 0 and floor <= 0 then floor = 1 end

    if not token or token == "" then
        SetFallbackBoardBackground("Map background: unavailable in this area")
        return false
    end

    local ok = ApplyMapBackground(token, floor, token)
    if nameEdit and (nameEdit:GetText() == "" or nameEdit:GetText() == "ICC - Boss Tactic") then
        if floor and floor > 0 then
            nameEdit:SetText((token or "Map") .. " - Floor " .. tostring(floor))
        else
            nameEdit:SetText(token or "Map")
        end
    end
    return ok
end

local function LayoutBoardTiles()
    if #mapSourceTextures > 0 then
        LayoutBoardTilesFromSource(mapSourceTextures)
    end
end

local function GetCursorBoardPosition()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local left = board:GetLeft() or 0
    local bottom = board:GetBottom() or 0
    local w, h = BoardSize()
    x = math.max(0, math.min(w, x - left))
    y = math.max(0, math.min(h, y - bottom))
    return x, y
end

local function AddDot(x, y, stroke)
    if not board or not stroke then return end
    local c = colors[stroke.color or 1] or colors[1]
    local parentFrame = drawLayer or board
    local tex = parentFrame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(c.r, c.g, c.b, 0.92)
    tex:SetWidth(stroke.size or thickness)
    tex:SetHeight(stroke.size or thickness)
    tex:SetPoint("CENTER", parentFrame, "BOTTOMLEFT", x, y)
    table.insert(stroke.textures, tex)
    table.insert(stroke.points, { x = math.floor(x + 0.5), y = math.floor(y + 0.5) })
end

local function AddLinePoints(x1, y1, x2, y2, stroke)
    local dx, dy = x2 - x1, y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    local step = math.max(2, math.floor((stroke.size or thickness) * 0.55))
    local count = math.max(1, math.floor(dist / step))
    for i = 1, count do
        local t = i / count
        AddDot(x1 + dx * t, y1 + dy * t, stroke)
    end
end

local function DrawingOnUpdate(self)
    if not isDrawing or not currentStroke or not drawMode then return end
    local x, y = GetCursorBoardPosition()
    local dx, dy = x - (lastX or x), y - (lastY or y)
    if (dx * dx + dy * dy) >= 9 then AddLinePoints(lastX, lastY, x, y, currentStroke); lastX, lastY = x, y end
end

local function StartStroke()
    local x, y = GetCursorBoardPosition()
    currentStroke = { color = currentColorIndex, size = thickness, points = {}, textures = {} }
    table.insert(strokes, currentStroke)
    lastX, lastY = x, y
    AddDot(x, y, currentStroke)
    isDrawing = true
    if board then WowNoteProfiler_SetScript(board, "OnUpdate", "TacticalMap.Drawing", DrawingOnUpdate) end
end

local function StopStroke()
    isDrawing = false
    if board then WowNoteProfiler_SetScript(board, "OnUpdate", "TacticalMap.Drawing", nil) end
    currentStroke = nil
    lastX, lastY = nil, nil
end

local function Undo()
    local stroke = table.remove(strokes)
    if not stroke then return end
    for _, tex in ipairs(stroke.textures or {}) do
        tex:Hide()
        tex:SetTexture(nil)
    end
end

local function Clear()
    while #strokes > 0 do Undo() end
end

local function Redraw()
    local copy = {}
    for i, s in ipairs(strokes) do copy[i] = { color = s.color, size = s.size, points = s.points } end
    Clear()
    for _, s in ipairs(copy) do
        local stroke = { color = s.color or 1, size = s.size or 5, points = {}, textures = {} }
        table.insert(strokes, stroke)
        for _, p in ipairs(s.points or {}) do AddDot(p.x or 0, p.y or 0, stroke) end
    end
end

local function UpdateStatus()
    if statusText then
        statusText:SetText("Mode: " .. (drawMode and "Draw" or "Locked") .. " | Color: " .. (colors[currentColorIndex].name) .. " | Size: " .. thickness)
    end
    if board then board:EnableMouse(drawMode) end
    for i, b in ipairs(colorButtons) do
        if i == currentColorIndex then b.label:SetText("*") else b.label:SetText("") end
    end
end

local function SerializeDrawing()
    local w, h = BoardSize()
    local parts = { "WNTAC1", nameEdit and nameEdit:GetText() or "Tactic" }
    for _, s in ipairs(strokes) do
        local pts = {}
        local lastRX, lastRY
        for _, p in ipairs(s.points or {}) do
            local rx = math.floor(((p.x or 0) / w) * 10000 + 0.5)
            local ry = math.floor(((p.y or 0) / h) * 10000 + 0.5)
            if rx ~= lastRX or ry ~= lastRY then
                table.insert(pts, tostring(rx) .. "," .. tostring(ry))
                lastRX, lastRY = rx, ry
            end
        end
        if #pts > 0 then table.insert(parts, tostring(s.color or 1) .. ":" .. tostring(s.size or 5) .. ":" .. table.concat(pts, ";")) end
    end
    local raw = table.concat(parts, "|")
    if WowNote_Internal and WowNote_Internal.Base64Encode then
        return "WNTAC1:" .. WowNote_Internal.Base64Encode(raw), string.len(raw)
    end
    return raw, string.len(raw)
end

local function LoadSerialized(text)
    if not text or text == "" then return false, "empty import" end
    local raw = text
    if string.sub(raw, 1, 7) == "WNTAC1:" and WowNote_Internal and WowNote_Internal.Base64Decode then
        raw = WowNote_Internal.Base64Decode(string.sub(raw, 8)) or ""
    end
    local fields = {}
    for token in string.gmatch(raw, "([^|]+)") do table.insert(fields, token) end
    if fields[1] ~= "WNTAC1" then return false, "invalid tactical drawing" end
    Clear()
    if nameEdit then nameEdit:SetText(fields[2] or "Imported Tactic") end
    local w, h = BoardSize()
    for i = 3, #fields do
        local color, size, data = string.match(fields[i], "^(%d+):(%d+):(.+)$")
        if color and data then
            local stroke = { color = tonumber(color) or 1, size = tonumber(size) or 5, points = {}, textures = {} }
            table.insert(strokes, stroke)
            for pair in string.gmatch(data, "([^;]+)") do
                local rx, ry = string.match(pair, "^(%-?%d+),(%-?%d+)$")
                if rx and ry then
                    local x = (tonumber(rx) or 0) / 10000 * w
                    local y = (tonumber(ry) or 0) / 10000 * h
                    AddDot(x, y, stroke)
                end
            end
        end
    end
    return true
end

local function ShowTransfer(mode)
    if not transferFrame then
        transferFrame = CreateFrame("Frame", "WowNoteTacticalTransferFrame", UIParent)
        transferFrame:SetSize(560, 330)
        transferFrame:SetPoint("CENTER")
        SetFront(transferFrame)
        transferFrame:EnableMouse(true)
        transferFrame:SetMovable(true)
        transferFrame:RegisterForDrag("LeftButton")
        transferFrame:SetScript("OnDragStart", transferFrame.StartMoving)
        transferFrame:SetScript("OnDragStop", transferFrame.StopMovingOrSizing)
        transferFrame.bg = transferFrame:CreateTexture(nil, "BACKGROUND")
        transferFrame.bg:SetAllPoints(transferFrame)
        transferFrame.bg:SetTexture(0, 0, 0, 0.93)
        transferFrame.title = transferFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        transferFrame.title:SetPoint("TOP", 0, -12)
        local close = CreateFrame("Button", nil, transferFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetFrameLevel(transferFrame:GetFrameLevel() + 10)
        close:EnableMouse(true)
        close:Enable()
        close:SetScript("OnMouseDown", function() transferFrame:Hide() end)
        close:SetScript("OnClick", function() transferFrame:Hide() end)
        transferFrame.closeButton = close

        local scroll = CreateFrame("ScrollFrame", "WowNoteTacticalTransferScroll", transferFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -42)
        scroll:SetPoint("BOTTOMRIGHT", -34, 58)
        scroll:SetFrameLevel(transferFrame:GetFrameLevel() + 3)
        scroll:EnableMouse(true)

        transferEdit = CreateFrame("EditBox", "WowNoteTacticalTransferEdit", scroll)
        transferEdit:SetMultiLine(true)
        transferEdit:SetAutoFocus(false)
        transferEdit:SetFontObject(ChatFontNormal)
        transferEdit:SetWidth(485)
        transferEdit:SetHeight(220)
        transferEdit:EnableMouse(true)
        transferEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        transferEdit:SetScript("OnMouseDown", function(self) self:SetFocus() end)
        transferEdit:SetScript("OnEditFocusGained", function(self)
            if transferFrame and transferFrame.mode == "export" then self:HighlightText() end
        end)
        scroll:SetScrollChild(transferEdit)

        local action = MakeButton(transferFrame, "Action", 90, 24)
        action:SetPoint("BOTTOMLEFT", 18, 18)
        action:SetFrameLevel(transferFrame:GetFrameLevel() + 5)
        action:SetScript("OnMouseDown", function()
            if transferFrame.mode ~= "import" then
                transferEdit:SetFocus()
                transferEdit:HighlightText()
            end
        end)
        action:SetScript("OnClick", function()
            if transferFrame.mode == "import" then
                local ok, err = LoadSerialized(transferEdit:GetText() or "")
                if ok then transferFrame:Hide(); Print("Tactical drawing imported.") else Print(err or "Import failed.") end
            else
                transferEdit:SetFocus()
                transferEdit:HighlightText()
            end
        end)
        transferFrame.action = action
    end
    transferFrame.mode = mode
    transferFrame.title:SetText(mode == "import" and "Import Tactical Drawing" or "Export Tactical Drawing")
    transferFrame.action:SetText(mode == "import" and "Import" or "Select all")
    if mode == "export" then
        local text, rawLen = SerializeDrawing()
        transferEdit:SetText(text or "")
        transferEdit:SetFocus()
        transferEdit:HighlightText()
        Print("Tactical export ready (raw " .. tostring(rawLen or 0) .. " bytes, encoded " .. tostring(string.len(text or "")) .. " bytes). Use Ctrl+C after Select all.")
    else
        transferEdit:SetText("")
        transferEdit:SetFocus()
    end
    transferFrame:Show()
    SetFront(transferFrame)
    if transferFrame.closeButton then transferFrame.closeButton:SetFrameLevel(transferFrame:GetFrameLevel() + 10) end
end

local function GetPresetNames()
    EnsureDB()
    local names = {}
    for name in pairs(WowNoteDB.tacticalMaps or {}) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

local function LoadPresetByName(name)
    EnsureDB()
    local data = name and WowNoteDB.tacticalMaps[name] or nil
    if not data then return false end
    local ok, err = LoadSerialized(data)
    if ok then
        selectedPresetName = name
        if nameEdit then nameEdit:SetText(name) end
        return true
    end
    Print(err or "Load failed.")
    return false
end

local function RefreshPresetList()
    if not frame then return end
    local names = GetPresetNames()
    local rowHeight = 22
    local listX = 660
    local listY = -170
    local maxRows = 16

    for i = 1, maxRows do
        local row = presetRows[i]
        if not row then
            row = CreateFrame("Button", nil, frame)
            row:SetSize(210, 20)
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWidth(202)
            local function SelectPreset(self)
                selectedPresetName = self.name
                if nameEdit then nameEdit:SetText(self.name or "") end
                RefreshPresetList()
            end
            row:SetScript("OnMouseDown", SelectPreset)
            row:SetScript("OnClick", SelectPreset)
            presetRows[i] = row
        end
        row:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
        row.text:SetDrawLayer("OVERLAY", 7)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", listX, listY - ((i - 1) * rowHeight))
        local name = names[i]
        if name then
            row.name = name
            row.text:SetText(name)
            if selectedPresetName == name then
                row.text:SetTextColor(1, 0.82, 0)
            else
                row.text:SetTextColor(1, 1, 1)
            end
            row:Show()
        else
            row.name = nil
            row:Hide()
        end
    end
end

local function SelectAndLoadPreset()
    if not selectedPresetName or selectedPresetName == "" then
        Print("Select a saved tactic from the list first.")
        return
    end
    if LoadPresetByName(selectedPresetName) then
        Print("Loaded tactical drawing: " .. selectedPresetName)
        RefreshPresetList()
    end
end

local function SavePreset()
    EnsureDB()
    local name = nameEdit and nameEdit:GetText() or ""
    if name == "" then Print("Enter a tactic name first."); return end
    WowNoteDB.tacticalMaps[name] = SerializeDrawing()
    selectedPresetName = name
    RefreshPresetList()
    Print("Saved tactical drawing: " .. name)
end

local function LoadPreset()
    local name = nameEdit and nameEdit:GetText() or ""
    if name == "" then name = selectedPresetName or "" end
    if name == "" then Print("Enter or select a tactic name first."); return end
    if LoadPresetByName(name) then
        Print("Loaded tactical drawing: " .. name)
        RefreshPresetList()
    else
        Print("No tactical drawing found: " .. tostring(name))
    end
end

local function DeletePreset()
    EnsureDB()
    local name = nameEdit and nameEdit:GetText() or ""
    if name == "" then name = selectedPresetName or "" end
    if name ~= "" and WowNoteDB.tacticalMaps[name] then
        WowNoteDB.tacticalMaps[name] = nil
        if selectedPresetName == name then selectedPresetName = nil end
        RefreshPresetList()
        Print("Deleted tactical drawing: " .. name)
    end
end

local function BuildHudPayload()
    local w, h = BoardSize()
    local payload = {
        name = nameEdit and nameEdit:GetText() or currentMapName or "Tactic",
        map = currentMapToken,
        floor = currentMapFloor or 0,
        strokes = {},
    }
    for _, s in ipairs(strokes or {}) do
        local out = { color = s.color or 1, size = s.size or 5, points = {} }
        for _, p in ipairs(s.points or {}) do
            table.insert(out.points, {
                x = (p.x or 0) / math.max(1, w),
                y = 1 - ((p.y or 0) / math.max(1, h)),
            })
        end
        if #out.points > 0 then table.insert(payload.strokes, out) end
    end
    return payload
end

local function ShowDrawingInHUD()
    if not WowNote_HudDraw_ShowDrawing then
        Print("HUD Draw module is not loaded.")
        return
    end
    local payload = BuildHudPayload()
    WowNote_HudDraw_ShowDrawing(payload)
end

local function ShareDrawing()
    local text = SerializeDrawing()
    if not text or text == "" then Print("Nothing to share."); return end
    if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix("WowNote") end
    if SendAddonMessage then
        local max = 220
        local total = math.ceil(string.len(text) / max)
        local id = tostring(time and time() or GetTime())
        for i = 1, total do
            local chunk = string.sub(text, ((i - 1) * max) + 1, i * max)
            local packet = "TAC:" .. id .. ":" .. i .. ":" .. total .. ":" .. chunk
            SendAddonMessage("WowNote", packet, "RAID")
            if WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("out", "WowNote RAID TAC", string.len(packet), true) end
        end
        Print("Shared tactical drawing to raid (" .. total .. " packets).")
    else
        Print("SendAddonMessage is not available.")
    end
end

local incoming = {}
local function OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= "WowNote" or type(msg) ~= "string" then return end
    local id, idx, total, chunk = string.match(msg, "^TAC:([^:]+):(%d+):(%d+):(.+)$")
    if id and WowNoteProfiler_RecordComm then WowNoteProfiler_RecordComm("in", "WowNote " .. tostring(channel or "?") .. " TAC", string.len(msg), true) end
    if not id then return end
    idx, total = tonumber(idx), tonumber(total)
    if not idx or not total then return end
    incoming[id] = incoming[id] or { total = total, chunks = {} }
    incoming[id].chunks[idx] = chunk
    local done = true
    for i = 1, total do if not incoming[id].chunks[i] then done = false break end end
    if done then
        local data = table.concat(incoming[id].chunks, "")
        incoming[id] = nil
        local ok = LoadSerialized(data)
        if ok then Print("Received tactical drawing from " .. tostring(sender or "raid") .. ".") end
    end
end

local function EnsureReceiver()
    if receiveFrame then return end
    if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix("WowNote") end
    receiveFrame = CreateFrame("Frame")
    receiveFrame:RegisterEvent("CHAT_MSG_ADDON")
    WowNoteProfiler_SetScript(receiveFrame, "OnEvent", "TacticalMap.CommEvents", function(_, _, prefix, msg, channel, sender) OnAddonMessage(prefix, msg, channel, sender) end)
end

local function CreateUI()
    if frame then return end
    EnsureDB()
    EnsureReceiver()
    frame = CreateFrame("Frame", "WowNoteTacticalMapFrame", UIParent)
    frame:SetSize(920, 690)
    frame:SetPoint("CENTER")
    SetFront(frame)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture(0, 0, 0, 0.88)
    frame.border = CreateFrame("Frame", nil, frame)
    frame.border:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
    frame.border:EnableMouse(false)
    frame.border:SetAllPoints(frame)
    frame.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame.border:SetBackdropBorderColor(1, 0.82, 0, 1)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("WowNote Tactical Board")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    LiftControl(close, frame, 10)
    close:SetScript("OnClick", function() frame:Hide() end)

    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", 22, -42)
    nameLabel:SetText("Map/Boss:")
    nameEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameEdit:SetSize(260, 22)
    LiftControl(nameEdit, frame, 8)
    nameEdit:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
    nameEdit:SetAutoFocus(false)
    nameEdit:SetText("ICC - Boss Tactic")

    local autoMapBtn = MakeButton(frame, "Use Current Map", 120, 22)
    autoMapBtn:SetPoint("LEFT", nameEdit, "RIGHT", 12, 0)
    autoMapBtn:SetScript("OnClick", CaptureCurrentMapBackground)

    mapInfoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mapInfoText:SetPoint("TOPLEFT", 18, -58)
    mapInfoText:SetWidth(860)
    mapInfoText:SetJustifyH("LEFT")
    mapInfoText:SetText("Map background: manual board")

    local drawBtn = MakeButton(frame, "Draw: OFF", 80, 22)
    drawBtn:SetPoint("TOPLEFT", 22, -86)
    drawBtn:SetScript("OnClick", function() drawMode = not drawMode; drawBtn:SetText(drawMode and "Draw: ON" or "Draw: OFF"); UpdateStatus() end)
    local undoBtn = MakeButton(frame, "Undo", 58, 22)
    undoBtn:SetPoint("LEFT", drawBtn, "RIGHT", 8, 0)
    undoBtn:SetScript("OnClick", Undo)
    local clearBtn = MakeButton(frame, "Clear", 58, 22)
    clearBtn:SetPoint("LEFT", undoBtn, "RIGHT", 8, 0)
    clearBtn:SetScript("OnClick", Clear)
    local minus = MakeButton(frame, "-", 28, 22)
    minus:SetPoint("LEFT", clearBtn, "RIGHT", 12, 0)
    minus:SetScript("OnClick", function() thickness = math.max(2, thickness - 1); UpdateStatus() end)
    local plus = MakeButton(frame, "+", 28, 22)
    plus:SetPoint("LEFT", minus, "RIGHT", 34, 0)
    plus:SetScript("OnClick", function() thickness = math.min(18, thickness + 1); UpdateStatus() end)

    for i, c in ipairs(colors) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(22, 22)
        LiftControl(b, frame, 5)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 22 + ((i - 1) * 28), -118)
        b.tex = b:CreateTexture(nil, "BACKGROUND")
        b.tex:SetAllPoints(b)
        b.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.tex:SetVertexColor(c.r, c.g, c.b, 1)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.label:SetPoint("CENTER")
        b:SetScript("OnMouseDown", function() currentColorIndex = i; UpdateStatus() end)
        b:SetScript("OnClick", function() currentColorIndex = i; UpdateStatus() end)
        colorButtons[i] = b
    end

    local saveBtn = MakeButton(frame, "Save", 58, 22)
    saveBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 430, -86)
    saveBtn:SetScript("OnClick", SavePreset)
    local loadBtn = MakeButton(frame, "Load", 58, 22)
    loadBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    loadBtn:SetScript("OnClick", LoadPreset)
    local delBtn = MakeButton(frame, "Delete", 62, 22)
    delBtn:SetPoint("LEFT", loadBtn, "RIGHT", 6, 0)
    delBtn:SetScript("OnClick", DeletePreset)
    local expBtn = MakeButton(frame, "Export", 62, 22)
    expBtn:SetPoint("LEFT", delBtn, "RIGHT", 6, 0)
    expBtn:SetScript("OnClick", function() ShowTransfer("export") end)
    local impBtn = MakeButton(frame, "Import", 62, 22)
    impBtn:SetPoint("LEFT", expBtn, "RIGHT", 6, 0)
    impBtn:SetScript("OnClick", function() ShowTransfer("import") end)
    local shareBtn = MakeButton(frame, "Share", 62, 22)
    shareBtn:SetPoint("LEFT", impBtn, "RIGHT", 6, 0)
    shareBtn:SetScript("OnClick", ShareDrawing)
    local hudBtn = MakeButton(frame, "HUD", 50, 22)
    hudBtn:SetPoint("LEFT", shareBtn, "RIGHT", 6, 0)
    hudBtn:SetScript("OnClick", ShowDrawingInHUD)

    local presetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    presetLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 660, -150)
    presetLabel:SetText("Saved Drawings:")
    presetLabel:SetDrawLayer("OVERLAY", 7)

    presetScrollFrame = CreateFrame("Frame", nil, frame)
    presetScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 656, -166)
    presetScrollFrame:SetSize(224, 370)
    presetScrollFrame:SetFrameLevel((frame:GetFrameLevel() or 0) + 2)
    presetScrollFrame:EnableMouse(false)
    presetScrollFrame.bg = presetScrollFrame:CreateTexture(nil, "BACKGROUND")
    presetScrollFrame.bg:SetAllPoints(presetScrollFrame)
    presetScrollFrame.bg:SetTexture(0, 0, 0, 0.35)
    presetScrollFrame.border = CreateFrame("Frame", nil, presetScrollFrame)
    presetScrollFrame.border:SetAllPoints(presetScrollFrame)
    presetScrollFrame.border:EnableMouse(false)
    presetScrollFrame.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    presetScrollFrame.border:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    presetContentFrame = nil

    local listLoadBtn = MakeButton(frame, "Load Sel", 72, 22)
    listLoadBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 660, -590)
    listLoadBtn:SetScript("OnClick", SelectAndLoadPreset)
    local listRefreshBtn = MakeButton(frame, "Refresh", 72, 22)
    listRefreshBtn:SetPoint("LEFT", listLoadBtn, "RIGHT", 8, 0)
    listRefreshBtn:SetScript("OnClick", RefreshPresetList)

    board = CreateFrame("Frame", "WowNoteTacticalBoardCanvas", frame)
    board:SetFrameLevel((frame:GetFrameLevel() or 0) + 2)
    board:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -150)
    board:SetSize(620, 470)
    board:EnableMouse(false)
    board.bg = board:CreateTexture(nil, "BACKGROUND")
    board.bg:SetAllPoints(board)
    board.bg:SetTexture(0.08, 0.08, 0.08, 0.95)

    drawLayer = CreateFrame("Frame", nil, board)
    drawLayer:SetAllPoints(board)
    drawLayer:SetFrameLevel((board:GetFrameLevel() or 0) + 5)
    drawLayer:EnableMouse(false)

    board.border = CreateFrame("Frame", nil, board)
    board.border:SetFrameLevel((board:GetFrameLevel() or 0) + 1)
    board.border:EnableMouse(false)
    board.border:SetAllPoints(board)
    board.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    board.border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    board:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" and drawMode then StartStroke() end end)
    board:SetScript("OnMouseUp", function() StopStroke() end)
    board:SetScript("OnSizeChanged", function()
        LayoutBoardTiles()
    end)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 22, 18)
    statusText:SetWidth(860)
    statusText:SetJustifyH("LEFT")
    CaptureCurrentMapBackground()
    RefreshPresetList()
    UpdateStatus()
end

function WowNote_OpenTacticalMap()
    CreateUI()
    frame:Show()
    SetFront(frame)
    frame:Raise()
    RefreshPresetList()
    CaptureCurrentMapBackground()
    UpdateStatus()
end

function WowNote_ToggleTacticalMap()
    if frame and frame:IsShown() then frame:Hide() else WowNote_OpenTacticalMap() end
end

EnsureReceiver()
Print("Tactical Board loaded. Use /wn tactics.")
