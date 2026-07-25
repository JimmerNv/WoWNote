-- WowNote HUD Draw Overlay
-- Gatherer-style HUD projection for tactical-map drawings.
-- It interprets tactical-board points as current map coordinates and renders
-- them relative to the player's current map position and facing.

local HD = {}
WowNote_HudDraw = HD

local hudFrame, controlFrame, statusText, scaleText, scaleSlider
local activeDrawing = nil
local renderTextures = {}
local hudScale = 42000
local visible = false
local hudElapsed = 0
local HUD_UPDATE_INTERVAL = 0.10

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
    if WowNote_Internal and WowNote_Internal.RaiseFrame then
        WowNote_Internal.RaiseFrame(f)
        return
    end
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(100)
    if f.SetToplevel then f:SetToplevel(true) end
    if f.Raise then f:Raise() end
end

local function EnsureDB()
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.hudDraw) ~= "table" then WowNoteCharDB.hudDraw = {} end
    hudScale = tonumber(WowNoteCharDB.hudDraw.scale) or hudScale
end

local function SaveDB()
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.hudDraw) ~= "table" then WowNoteCharDB.hudDraw = {} end
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
    if not GetPlayerMapPosition then return nil, nil end
    local x, y = GetPlayerMapPosition("player")
    if (not x or not y or (x == 0 and y == 0)) and SetMapToCurrentZone then
        pcall(SetMapToCurrentZone)
        x, y = GetPlayerMapPosition("player")
    end
    if not x or not y or (x == 0 and y == 0) then return nil, nil end
    local map = GetMapInfo and GetMapInfo() or nil
    local floor = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
    return x, y, map, floor
end

local function ProjectPoint(px, py, pointX, pointY, facing)
    facing = facing or 0
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
    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    for _, stroke in ipairs(activeDrawing.strokes or {}) do
        local c = colors[stroke.color or 1] or colors[1]
        local size = math.max(3, math.min(18, tonumber(stroke.size) or 5))
        for _, p in ipairs(stroke.points or {}) do
            local mx, my = tonumber(p.x), tonumber(p.y)
            if mx and my and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
                local sx, sy = ProjectPoint(px, py, mx, my, facing)
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
    if scaleSlider and scaleSlider:GetValue() ~= hudScale then scaleSlider:SetValue(hudScale) end
end

local function HudOnUpdate(self, elapsed)
    if not visible or not activeDrawing or not self:IsShown() then return end
    hudElapsed = hudElapsed + (elapsed or 0)
    if hudElapsed < HUD_UPDATE_INTERVAL then return end
    hudElapsed = 0
    RenderHUD()
end

local function SetHudActive(active)
    visible = active and activeDrawing ~= nil
    hudElapsed = 0
    if not hudFrame then return end
    if visible then
        hudFrame:Show()
        WowNoteProfiler_SetScript(hudFrame, "OnUpdate", "TacticalHUD.Render", HudOnUpdate)
    else
        WowNoteProfiler_SetScript(hudFrame, "OnUpdate", "TacticalHUD.Render", nil)
        hudFrame:Hide()
        HideAllTextures(1)
    end
end

local function CreateUI()
    if hudFrame then return end
    EnsureDB()

    hudFrame = CreateFrame("Frame", "WowNoteHudDrawOverlay", UIParent)
    hudFrame:SetAllPoints(UIParent)
    hudFrame:SetFrameStrata("FULLSCREEN")
    hudFrame:SetFrameLevel(20)
    hudFrame:EnableMouse(false)
    hudFrame:Hide()

    controlFrame = CreateFrame("Frame", "WowNoteHudDrawControl", UIParent)
    controlFrame:SetSize(430, 90)
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
    -- Keep the close button slightly above the HUD control frame background
    -- without forcing the whole window above unrelated dialogs.
    close:SetFrameLevel((controlFrame:GetFrameLevel() or 0) + 10)
    close:EnableMouse(true)
    close:Enable()
    close:SetScript("OnMouseDown", function() controlFrame:Hide() end)
    close:SetScript("OnClick", function() controlFrame:Hide() end)
    controlFrame.closeButton = close

    local clearBtn = MakeButton(controlFrame, "Clear HUD", 76, 22)
    clearBtn:SetPoint("TOPLEFT", 12, -34)
    clearBtn:SetScript("OnClick", function() activeDrawing = nil; SetHudActive(false); Print("HUD drawing cleared.") end)

    local scaleLabel = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleLabel:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    scaleLabel:SetText("Scale")

    scaleSlider = CreateFrame("Slider", "WowNoteHudDrawScaleSlider", controlFrame, "OptionsSliderTemplate")
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
    scaleSlider:SetWidth(170)
    scaleSlider:SetHeight(18)
    scaleSlider:SetMinMaxValues(1000, 200000)
    scaleSlider:SetValueStep(1000)
    if scaleSlider.SetObeyStepOnDrag then scaleSlider:SetObeyStepOnDrag(true) end
    scaleSlider:SetFrameLevel((controlFrame:GetFrameLevel() or 0) + 12)
    scaleSlider:EnableMouse(true)
    local sliderLow = getglobal(scaleSlider:GetName() .. "Low")
    local sliderHigh = getglobal(scaleSlider:GetName() .. "High")
    local sliderText = getglobal(scaleSlider:GetName() .. "Text")
    if sliderLow then sliderLow:SetText("1k") end
    if sliderHigh then sliderHigh:SetText("200k") end
    if sliderText then sliderText:SetText("") end
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor((tonumber(value) or hudScale) / 1000 + 0.5) * 1000
        rounded = math.max(1000, math.min(200000, rounded))
        if rounded == hudScale then return end
        hudScale = rounded
        if self:GetValue() ~= rounded then self:SetValue(rounded) end
        SaveDB()
        RenderHUD()
    end)
    scaleSlider:SetValue(hudScale)

    scaleText = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleText:SetPoint("LEFT", scaleSlider, "RIGHT", 10, 0)
    scaleText:SetWidth(58)
    scaleText:SetJustifyH("LEFT")
    scaleText:SetText(tostring(hudScale))

    statusText = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 12, 10)
    statusText:SetWidth(406)
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
    SetHudActive(true)
    controlFrame:Show()
    SetFront(controlFrame)
    controlFrame:Raise()
    RenderHUD()
    Print("Tactical HUD enabled. Use the scale slider to calibrate distance scale.")
end

function WowNote_HudDraw_Clear()
    if not hudFrame then return end
    activeDrawing = nil
    SetHudActive(false)
end

Print("Tactical HUD loaded.")
