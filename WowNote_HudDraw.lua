-- WowNote HUD Draw Overlay
-- Gatherer-style HUD projection for tactical-map drawings.
-- It interprets tactical-board points as current map coordinates and renders
-- them relative to the player's current map position and facing.

local HD = {}
WowNote_HudDraw = HD

local hudFrame, controlFrame, statusText, scaleText
local activeDrawing = nil
local renderTextures = {}
local hudScale = 42000
local visible = false

local colors = {
    { r = 1.00, g = 0.90, b = 0.00 },
    { r = 1.00, g = 0.05, b = 0.05 },
    { r = 0.10, g = 1.00, b = 0.10 },
    { r = 0.20, g = 0.50, b = 1.00 },
    { r = 0.00, g = 1.00, b = 1.00 },
    { r = 0.75, g = 0.20, b = 1.00 },
    { r = 1.00, g = 0.45, b = 0.00 },
    { r = 1.00, g = 1.00, b = 1.00 },
    { r = 0.00, g = 0.00, b = 0.00 },
    { r = 1.00, g = 0.25, b = 0.65 },
}

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("WowNote: " .. tostring(msg)) end
end

local function MakeButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 80, height or 22)
    b:SetText(text or "Button")
    if parent and parent.GetFrameLevel then b:SetFrameLevel((parent:GetFrameLevel() or 0) + 8) end
    b:Enable()
    b:EnableMouse(true)
    return b
end

local function SetFront(f)
    if not f then return end
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(910)
end

local function EnsureDB()
    WowNoteCharDB = WowNoteCharDB or {}
    WowNoteCharDB.hudDraw = WowNoteCharDB.hudDraw or {}
    hudScale = tonumber(WowNoteCharDB.hudDraw.scale) or hudScale
end

local function SaveDB()
    WowNoteCharDB = WowNoteCharDB or {}
    WowNoteCharDB.hudDraw = WowNoteCharDB.hudDraw or {}
    WowNoteCharDB.hudDraw.scale = hudScale
end

local function AcquireTexture(index)
    if renderTextures[index] then return renderTextures[index] end
    local tex = hudFrame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    renderTextures[index] = tex
    return tex
end

local function HideAllTextures(fromIndex)
    for i = fromIndex or 1, #renderTextures do
        renderTextures[i]:Hide()
    end
end

local function GetPlayerMapXY()
    if SetMapToCurrentZone then pcall(SetMapToCurrentZone) end
    if not GetPlayerMapPosition then return nil, nil end
    local x, y = GetPlayerMapPosition("player")
    if not x or not y or (x == 0 and y == 0) then return nil, nil end
    local map = GetMapInfo and GetMapInfo() or nil
    local floor = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
    return x, y, map, floor
end

local function ProjectPoint(px, py, pointX, pointY)
    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    local dx = (pointX or 0) - px
    local dy = (pointY or 0) - py
    local dist = math.sqrt(dx * dx + dy * dy) * hudScale
    local angle = math.atan2(dx, -dy) + facing
    local sx = dist * math.sin(angle)
    local sy = dist * math.cos(angle)
    return sx, sy
end

local function RenderHUD()
    if not visible or not activeDrawing or not hudFrame then HideAllTextures(1); return end
    local px, py, currentMap, currentFloor = GetPlayerMapXY()
    if not px or not py then
        HideAllTextures(1)
        if statusText then statusText:SetText("HUD: no player map position") end
        return
    end

    if activeDrawing.map and currentMap and activeDrawing.map ~= currentMap then
        HideAllTextures(1)
        if statusText then statusText:SetText("HUD: map mismatch (" .. tostring(activeDrawing.map) .. " / " .. tostring(currentMap) .. ")") end
        return
    end

    local index = 1
    local centerX, centerY = 0, 0
    local visiblePoints = 0
    for _, stroke in ipairs(activeDrawing.strokes or {}) do
        local c = colors[stroke.color or 1] or colors[1]
        local size = math.max(3, math.min(18, tonumber(stroke.size) or 5))
        for _, p in ipairs(stroke.points or {}) do
            local mx, my = tonumber(p.x), tonumber(p.y)
            if mx and my and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
                local sx, sy = ProjectPoint(px, py, mx, my)
                if math.abs(sx) < 1200 and math.abs(sy) < 900 then
                    local tex = AcquireTexture(index)
                    tex:SetWidth(size)
                    tex:SetHeight(size)
                    tex:SetVertexColor(c.r, c.g, c.b, 0.92)
                    tex:ClearAllPoints()
                    tex:SetPoint("CENTER", hudFrame, "CENTER", centerX + sx, centerY + sy)
                    tex:Show()
                    index = index + 1
                    visiblePoints = visiblePoints + 1
                end
            end
        end
    end
    HideAllTextures(index)
    if statusText then
        statusText:SetText("HUD: " .. tostring(activeDrawing.name or "Tactic") .. " | points " .. tostring(visiblePoints) .. " | scale " .. tostring(hudScale))
    end
    if scaleText then scaleText:SetText(tostring(hudScale)) end
end

local function CreateUI()
    if hudFrame then return end
    EnsureDB()

    hudFrame = CreateFrame("Frame", "WowNoteHudDrawOverlay", UIParent)
    hudFrame:SetAllPoints(UIParent)
    hudFrame:SetFrameStrata("FULLSCREEN")
    hudFrame:SetFrameLevel(830)
    hudFrame:EnableMouse(false)
    hudFrame:SetScript("OnUpdate", RenderHUD)

    controlFrame = CreateFrame("Frame", "WowNoteHudDrawControl", UIParent)
    controlFrame:SetSize(300, 90)
    controlFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    SetFront(controlFrame)
    controlFrame:EnableMouse(true)
    controlFrame:SetMovable(true)
    controlFrame:RegisterForDrag("LeftButton")
    controlFrame:SetScript("OnDragStart", controlFrame.StartMoving)
    controlFrame:SetScript("OnDragStop", controlFrame.StopMovingOrSizing)
    controlFrame.bg = controlFrame:CreateTexture(nil, "BACKGROUND")
    controlFrame.bg:SetAllPoints(controlFrame)
    controlFrame.bg:SetTexture(0, 0, 0, 0.86)
    local title = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("WowNote Tactical HUD")
    local close = CreateFrame("Button", nil, controlFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() controlFrame:Hide() end)

    local clearBtn = MakeButton(controlFrame, "Clear HUD", 76, 22)
    clearBtn:SetPoint("TOPLEFT", 12, -34)
    clearBtn:SetScript("OnClick", function() activeDrawing = nil; visible = false; HideAllTextures(1); Print("HUD drawing cleared.") end)
    local minus = MakeButton(controlFrame, "S-", 36, 22)
    minus:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    minus:SetScript("OnClick", function() hudScale = math.max(1000, hudScale - 2000); SaveDB(); RenderHUD() end)
    scaleText = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleText:SetPoint("LEFT", minus, "RIGHT", 8, 0)
    scaleText:SetWidth(58)
    local plus = MakeButton(controlFrame, "S+", 36, 22)
    plus:SetPoint("LEFT", scaleText, "RIGHT", 4, 0)
    plus:SetScript("OnClick", function() hudScale = math.min(200000, hudScale + 2000); SaveDB(); RenderHUD() end)

    statusText = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 12, 10)
    statusText:SetWidth(276)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("HUD: no drawing")
end

function WowNote_HudDraw_ShowDrawing(drawing)
    CreateUI()
    if not drawing or not drawing.strokes or #drawing.strokes == 0 then
        Print("No tactical drawing available for HUD.")
        return
    end
    activeDrawing = drawing
    visible = true
    hudFrame:Show()
    controlFrame:Show()
    SetFront(controlFrame)
    controlFrame:Raise()
    RenderHUD()
    Print("Tactical HUD enabled. Use S-/S+ to calibrate distance scale.")
end

function WowNote_HudDraw_Clear()
    if not hudFrame then return end
    activeDrawing = nil
    visible = false
    HideAllTextures(1)
end

Print("Tactical HUD loaded.")
