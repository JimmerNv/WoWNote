-- Minimap button module ----------------------------------------------------
WowNote_Internal = WowNote_Internal or {}
local minimapButton
local minimapDragging = false

local function GetMinimapButtonAngle()
    WowNote_Internal.InitDB()
    WowNoteDB.minimap = WowNoteDB.minimap or {}
    return WowNoteDB.minimap.angle or 225
end

local function SetMinimapButtonPosition(angle)
    if not minimapButton or not Minimap then return end
    WowNote_Internal.InitDB()
    WowNoteDB.minimap = WowNoteDB.minimap or {}
    WowNoteDB.minimap.angle = angle
    local radius = 80
    local rad = math.rad(angle)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function UpdateMinimapButtonPositionFromCursor()
    if not minimapButton or not Minimap then return end
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    px = px / scale
    py = py / scale
    local atan2 = math.atan2 or atan2
    local angle
    if atan2 then
        angle = math.deg(atan2(py - my, px - mx))
    else
        angle = math.deg(math.atan((py - my) / ((px - mx) == 0 and 0.0001 or (px - mx))))
        if px < mx then angle = angle + 180 end
    end
    SetMinimapButtonPosition(angle)
end

function WowNote_CreateMinimapButton()
    if minimapButton or not Minimap then return end
    WowNote_Internal.InitDB()
    WowNoteDB.minimap = WowNoteDB.minimap or {}
    if WowNoteDB.minimap.hide then return end

    local b = CreateFrame("Button", "WowNoteMinimapButton", Minimap)
    minimapButton = b
    b:SetWidth(31)
    b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    b:RegisterForDrag("LeftButton")

    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("WowNote", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: open notes", 1, 1, 1)
        GameTooltip:AddLine("Right-click: open raid planner", 1, 1, 1)
        GameTooltip:AddLine("Middle-click: open loot tools", 1, 1, 1)
        GameTooltip:AddLine("Drag: move icon", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(_, buttonName)
        if buttonName == "RightButton" and WowNote_OpenRaidPlanner then
            WowNote_OpenRaidPlanner()
        elseif buttonName == "MiddleButton" and WowNote_OpenAutoLootRoller then
            WowNote_OpenAutoLootRoller()
        else
            WowNote_Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        minimapDragging = true
        self:SetScript("OnUpdate", UpdateMinimapButtonPositionFromCursor)
    end)
    b:SetScript("OnDragStop", function(self)
        minimapDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    SetMinimapButtonPosition(GetMinimapButtonAngle())
end

function WowNote_ShowMinimapButton()
    WowNote_Internal.InitDB()
    WowNoteDB.minimap = WowNoteDB.minimap or {}
    WowNoteDB.minimap.hide = false
    WowNote_CreateMinimapButton()
    if minimapButton then minimapButton:Show() end
end

function WowNote_HideMinimapButton()
    WowNote_Internal.InitDB()
    WowNoteDB.minimap = WowNoteDB.minimap or {}
    WowNoteDB.minimap.hide = true
    if minimapButton then minimapButton:Hide() end
end
