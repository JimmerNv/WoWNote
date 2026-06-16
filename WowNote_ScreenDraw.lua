-- WowNote Screen Draw Overlay
-- Stable screen-space drawing overlay for raid explanations.
-- This module intentionally does not try to anchor drawings to the world.

local SD = {}
WowNote_ScreenDraw = SD

local frame, overlay, statusText, thicknessText, transferFrame, transferEdit, receiveFrame
local colorButtons = {}
local strokes = {}
local currentStroke, isDrawing
local drawMode = false
local visibleOverlay = true
local currentColorIndex = 1
local thickness = 6
local lastX, lastY

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

local function SetShownCompat(f, shown)
    if not f then return end
    if shown then f:Show() else f:Hide() end
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

local function MakeButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 80, height or 22)
    b:SetText(text or "Button")
    if parent and parent.GetFrameLevel then b:SetFrameLevel((parent:GetFrameLevel() or 0) + 5) end
    b:Enable()
    b:EnableMouse(true)
    return b
end

local function BoardSize()
    if not overlay then return 1, 1 end
    return math.max(1, overlay:GetWidth() or 1), math.max(1, overlay:GetHeight() or 1)
end

local function GetCursorOverlayPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local left = overlay:GetLeft() or 0
    local bottom = overlay:GetBottom() or 0
    local w, h = BoardSize()
    x = math.max(0, math.min(w, x - left))
    y = math.max(0, math.min(h, y - bottom))
    return x, y
end

local function AddDot(x, y, stroke)
    if not overlay or not stroke then return end
    local c = colors[stroke.color or 1] or colors[1]
    local tex = overlay:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(c.r, c.g, c.b, 0.92)
    tex:SetWidth(stroke.size or thickness)
    tex:SetHeight(stroke.size or thickness)
    tex:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
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

local function StartStroke()
    local x, y = GetCursorOverlayPosition()
    currentStroke = { color = currentColorIndex, size = thickness, points = {}, textures = {} }
    table.insert(strokes, currentStroke)
    lastX, lastY = x, y
    AddDot(x, y, currentStroke)
    isDrawing = true
end

local function StopStroke()
    isDrawing = false
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
        local stroke = { color = s.color or 1, size = s.size or 6, points = {}, textures = {} }
        table.insert(strokes, stroke)
        for _, p in ipairs(s.points or {}) do AddDot(p.x or 0, p.y or 0, stroke) end
    end
end

local function UpdateStatus()
    if statusText then
        local w, h = BoardSize()
        statusText:SetText("Mode: " .. (drawMode and "Draw" or "Locked") .. " | Color: " .. colors[currentColorIndex].name .. " | Size: " .. thickness .. " | Surface: " .. math.floor(w) .. "x" .. math.floor(h))
    end
    if thicknessText then thicknessText:SetText(tostring(thickness)) end
    if overlay then overlay:EnableMouse(drawMode) end
    for i, b in ipairs(colorButtons) do
        if b.label then b.label:SetText(i == currentColorIndex and "*" or "") end
    end
end

local function SerializeDrawing()
    local w, h = BoardSize()
    local parts = { "WNDRAW1" }
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
        if #pts > 0 then table.insert(parts, tostring(s.color or 1) .. ":" .. tostring(s.size or 6) .. ":" .. table.concat(pts, ";")) end
    end
    local raw = table.concat(parts, "|")
    if WowNote_Internal and WowNote_Internal.Base64Encode then
        return "WNDRAW1:" .. WowNote_Internal.Base64Encode(raw), string.len(raw)
    end
    return raw, string.len(raw)
end

local function LoadSerialized(text)
    if not text or text == "" then return false, "empty import" end
    local raw = text
    if string.sub(raw, 1, 8) == "WNDRAW1:" and WowNote_Internal and WowNote_Internal.Base64Decode then
        raw = WowNote_Internal.Base64Decode(string.sub(raw, 9)) or ""
    end
    local fields = {}
    for token in string.gmatch(raw, "([^|]+)") do table.insert(fields, token) end
    if fields[1] ~= "WNDRAW1" then return false, "invalid screen drawing" end
    Clear()
    local w, h = BoardSize()
    for i = 2, #fields do
        local color, size, data = string.match(fields[i], "^(%d+):(%d+):(.+)$")
        if color and data then
            local stroke = { color = tonumber(color) or 1, size = tonumber(size) or 6, points = {}, textures = {} }
            table.insert(strokes, stroke)
            for pair in string.gmatch(data, "([^;]+)") do
                local rx, ry = string.match(pair, "^(%-?%d+),(%-?%d+)$")
                if rx and ry then AddDot((tonumber(rx) or 0) / 10000 * w, (tonumber(ry) or 0) / 10000 * h, stroke) end
            end
        end
    end
    return true
end

local function ShowTransfer(mode)
    if not transferFrame then
        transferFrame = CreateFrame("Frame", "WowNoteScreenDrawTransferFrame", UIParent)
        transferFrame:SetSize(520, 300)
        transferFrame:SetPoint("CENTER")
        SetFront(transferFrame)
        transferFrame:EnableMouse(true)
        transferFrame:SetMovable(true)
        transferFrame:RegisterForDrag("LeftButton")
        transferFrame:SetScript("OnDragStart", transferFrame.StartMoving)
        transferFrame:SetScript("OnDragStop", transferFrame.StopMovingOrSizing)
        transferFrame.bg = transferFrame:CreateTexture(nil, "BACKGROUND")
        transferFrame.bg:SetAllPoints(transferFrame)
        transferFrame.bg:SetTexture(0, 0, 0, 0.88)
        transferFrame.title = transferFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        transferFrame.title:SetPoint("TOP", 0, -12)
        local close = CreateFrame("Button", nil, transferFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() transferFrame:Hide() end)
        local scroll = CreateFrame("ScrollFrame", "WowNoteScreenDrawTransferScroll", transferFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -42)
        scroll:SetPoint("BOTTOMRIGHT", -34, 52)
        transferEdit = CreateFrame("EditBox", nil, scroll)
        transferEdit:SetMultiLine(true)
        transferEdit:SetAutoFocus(false)
        transferEdit:SetFontObject(ChatFontNormal)
        transferEdit:SetWidth(455)
        transferEdit:SetHeight(190)
        scroll:SetScrollChild(transferEdit)
        local action = MakeButton(transferFrame, "Action", 90, 24)
        action:SetPoint("BOTTOMLEFT", 18, 16)
        action:SetScript("OnClick", function()
            if transferFrame.mode == "import" then
                local ok, err = LoadSerialized(transferEdit:GetText() or "")
                if ok then transferFrame:Hide(); Print("Screen drawing imported.") else Print(err or "Import failed.") end
            else
                transferEdit:HighlightText(); transferEdit:SetFocus()
            end
        end)
        transferFrame.action = action
    end
    transferFrame.mode = mode
    transferFrame.title:SetText(mode == "import" and "Import Screen Drawing" or "Export Screen Drawing")
    transferFrame.action:SetText(mode == "import" and "Import" or "Select all")
    if mode == "export" then
        local text, rawLen = SerializeDrawing()
        transferEdit:SetText(text or "")
        Print("Screen export ready (raw " .. tostring(rawLen or 0) .. " bytes, encoded " .. tostring(string.len(text or "")) .. " bytes).")
    else
        transferEdit:SetText("")
    end
    transferFrame:Show()
    SetFront(transferFrame)
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
            SendAddonMessage("WowNote", "DRAW:" .. id .. ":" .. i .. ":" .. total .. ":" .. chunk, "RAID")
        end
        Print("Shared screen drawing to raid (" .. total .. " packets).")
    else
        Print("SendAddonMessage is not available.")
    end
end

local incoming = {}
local function OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= "WowNote" or type(msg) ~= "string" then return end
    local id, idx, total, chunk = string.match(msg, "^DRAW:([^:]+):(%d+):(%d+):(.+)$")
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
        if ok then Print("Received screen drawing from " .. tostring(sender or "raid") .. ".") end
    end
end

local function EnsureReceiver()
    if receiveFrame then return end
    if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix("WowNote") end
    receiveFrame = CreateFrame("Frame")
    receiveFrame:RegisterEvent("CHAT_MSG_ADDON")
    receiveFrame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender) OnAddonMessage(prefix, msg, channel, sender) end)
end

local function CreateUI()
    if frame then return end
    EnsureReceiver()

    overlay = CreateFrame("Frame", "WowNoteScreenDrawOverlay", UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("HIGH")
    overlay:SetFrameLevel(20)
    overlay:EnableMouse(false)
    overlay:SetScript("OnMouseDown", function(_, button)
        if frame and frame:IsShown() and MouseIsOver and MouseIsOver(frame) then return end
        if button == "LeftButton" and drawMode then StartStroke() end
    end)
    overlay:SetScript("OnMouseUp", function() StopStroke() end)
    overlay:SetScript("OnUpdate", function()
        if not isDrawing or not currentStroke or not drawMode then return end
        local x, y = GetCursorOverlayPosition()
        local dx, dy = x - (lastX or x), y - (lastY or y)
        if (dx * dx + dy * dy) >= 9 then AddLinePoints(lastX, lastY, x, y, currentStroke); lastX, lastY = x, y end
    end)

    frame = CreateFrame("Frame", "WowNoteScreenDrawFrame", UIParent)
    frame:SetSize(430, 220)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 190)
    SetFront(frame)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture(0, 0, 0, 0.86)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("WowNote Screen Draw")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
    close:EnableMouse(true)
    close:SetScript("OnMouseDown", function() frame:Hide() end)
    close:SetScript("OnClick", function() frame:Hide() end)

    local drawBtn = MakeButton(frame, "Draw: OFF", 78, 22)
    drawBtn:SetPoint("TOPLEFT", 14, -36)
    drawBtn:SetScript("OnClick", function() drawMode = not drawMode; drawBtn:SetText(drawMode and "Draw: ON" or "Draw: OFF"); UpdateStatus() end)
    local undoBtn = MakeButton(frame, "Undo", 54, 22)
    undoBtn:SetPoint("LEFT", drawBtn, "RIGHT", 6, 0)
    undoBtn:SetScript("OnClick", Undo)
    local clearBtn = MakeButton(frame, "Clear", 54, 22)
    clearBtn:SetPoint("LEFT", undoBtn, "RIGHT", 6, 0)
    clearBtn:SetScript("OnClick", Clear)
    local hideBtn = MakeButton(frame, "Hide", 54, 22)
    hideBtn:SetPoint("LEFT", clearBtn, "RIGHT", 6, 0)
    hideBtn:SetScript("OnClick", function() visibleOverlay = not visibleOverlay; SetShownCompat(overlay, visibleOverlay); hideBtn:SetText(visibleOverlay and "Hide" or "Show") end)

    local minus = MakeButton(frame, "-", 26, 22)
    minus:SetPoint("TOPLEFT", 14, -64)
    minus:SetScript("OnClick", function() thickness = math.max(2, thickness - 1); UpdateStatus() end)
    thicknessText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thicknessText:SetPoint("LEFT", minus, "RIGHT", 8, 0)
    thicknessText:SetWidth(24)
    local plus = MakeButton(frame, "+", 26, 22)
    plus:SetPoint("LEFT", thicknessText, "RIGHT", 4, 0)
    plus:SetScript("OnClick", function() thickness = math.min(22, thickness + 1); UpdateStatus() end)

    local expBtn = MakeButton(frame, "Export", 58, 22)
    expBtn:SetPoint("LEFT", plus, "RIGHT", 10, 0)
    expBtn:SetScript("OnClick", function() ShowTransfer("export") end)
    local impBtn = MakeButton(frame, "Import", 58, 22)
    impBtn:SetPoint("LEFT", expBtn, "RIGHT", 6, 0)
    impBtn:SetScript("OnClick", function() ShowTransfer("import") end)
    local shareBtn = MakeButton(frame, "Share", 58, 22)
    shareBtn:SetPoint("LEFT", impBtn, "RIGHT", 6, 0)
    shareBtn:SetScript("OnClick", ShareDrawing)

    for i, c in ipairs(colors) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(22, 22)
        b:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + ((i - 1) * 27), -96)
        b.tex = b:CreateTexture(nil, "BACKGROUND")
        b.tex:SetAllPoints(b)
        b.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.tex:SetVertexColor(c.r, c.g, c.b, 1)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.label:SetPoint("CENTER")
        b:EnableMouse(true)
        b:Enable()
        b:SetScript("OnMouseDown", function() currentColorIndex = i; UpdateStatus() end)
        b:SetScript("OnClick", function() currentColorIndex = i; UpdateStatus() end)
        colorButtons[i] = b
    end

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 14, 14)
    statusText:SetWidth(360)
    statusText:SetJustifyH("LEFT")
    UpdateStatus()
end

function WowNote_OpenScreenDraw()
    CreateUI()
    frame:Show()
    SetFront(frame)
    frame:Raise()
    UpdateStatus()
end

function WowNote_ToggleScreenDraw()
    if frame and frame:IsShown() then frame:Hide() else WowNote_OpenScreenDraw() end
end

EnsureReceiver()
Print("Screen Draw loaded. Use /wn draw.")
