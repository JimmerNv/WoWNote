-- WowNote_ThreatHelper.lua
-- Combat-safe raid helper for the WowNote Threat Meter.
-- Secure buttons keep fixed unit assignments in combat; threat state only changes visuals.

local TH = {}
WowNoteThreatHelper = TH

local MAX_RAID = 40
local INITIAL_BUILD_BATCH = 8
local UPDATE_INTERVAL = 0.50
local BUTTON_HEIGHT = 24
local BUTTON_SPACING = 2
local UnitExists, UnitName, UnitGUID, UnitClass = UnitExists, UnitName, UnitGUID, UnitClass
local UnitCanAttack, UnitIsDead, UnitIsUnit = UnitCanAttack, UnitIsDead, UnitIsUnit
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local UnitAffectingCombat = UnitAffectingCombat
local InCombatLockdown = InCombatLockdown
local GetNumRaidMembers, GetNumPartyMembers = GetNumRaidMembers, GetNumPartyMembers
local GetSpellInfo, GetSpellCooldown = GetSpellInfo, GetSpellCooldown
local GetCursorInfo, ClearCursor = GetCursorInfo, ClearCursor
local tonumber, tostring, type = tonumber, tostring, type
local pairs, ipairs = pairs, ipairs
local math_floor, math_max, math_min = math.floor, math.max, math.min
local table_sort = table.sort

local DEFAULTS = {
    enabled = true,
    warningThreshold = 85,
    showOnlyInCombat = true,
    playAggroSound = true,
    muted = false,
    suspended = false,
    testMode = false,
    testAggroName = "",
    testAggroGUID = "",
    testAggroUnit = "",
    point = "TOPLEFT", x = 690, y = -220,
    configPoint = "CENTER", configX = 0, configY = 0,
    width = 260,
    height = 420,
    focus1 = "",
    focus2 = "",
    tanks = {},
    spells = {
        left = nil,
        right = nil,
        shiftLeft = nil,
        shiftRight = nil,
    },
}

local db
local frame, title, listFrame, focusFrame, configFrame
local rosterButtons, warningRows, focusButtons = {}, {}, {}
local testButton
local testModeText, muteButton, pauseButton, setMTButton, setOTButton
local RefreshFocusButtons, RefreshTestButton, LayoutPlayerBars
local updateFrame = CreateFrame("Frame")
local elapsedTotal = 0
local rosterDirty = true
local pendingSecureRefresh = false
local secureBuildUnits = nil
local secureBuildIndex = nil
local secureBuildActive = false
local lastAggro = {}

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote Threat Helper:|r " .. tostring(msg)) end
end

local function AddCounter(name, amount)
    if WowNoteProfiler_AddCounter then WowNoteProfiler_AddCounter("ThreatHelper." .. tostring(name), amount or 1) end
end

local function SetGauge(name, value)
    if WowNoteProfiler_SetGauge then WowNoteProfiler_SetGauge("ThreatHelper." .. tostring(name), value or 0) end
end

local function Copy(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do out[k] = Copy(v) end
    return out
end

local function Merge(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then dst[k] = Merge(dst[k], v)
        elseif dst[k] == nil then dst[k] = v end
    end
    return dst
end

local function EnsureDB()
    WowNoteDB = WowNoteDB or {}
    WowNoteDB.threatHelper = Merge(WowNoteDB.threatHelper, Copy(DEFAULTS))
    db = WowNoteDB.threatHelper
end

local function ResolveSpell(value)
    if value == nil or value == "" then return nil, nil, nil end
    local numeric = tonumber(value)
    local name, rank, icon
    if numeric then name, rank, icon = GetSpellInfo(numeric) else name, rank, icon = GetSpellInfo(value) end
    if not name then return nil, nil, nil end
    return name, numeric, icon
end

local function SpellLabel(value)
    local name, id = ResolveSpell(value)
    if not name then return "Not assigned" end
    return id and (name .. " [" .. id .. "]") or name
end

local function SaveSize()
    if not frame or not db then return end
    db.width = math_floor((frame:GetWidth() or DEFAULTS.width) + 0.5)
    db.height = math_floor((frame:GetHeight() or DEFAULTS.height) + 0.5)
    if WowNote_SaveWindowGeometry then WowNote_SaveWindowGeometry("ThreatHelper", frame, true) end
end

local function ContentWidth()
    if frame and frame.GetWidth then
        return math_max(1, (frame:GetWidth() or db.width or DEFAULTS.width) - 16)
    end
    return math_max(1, (db.width or DEFAULTS.width) - 16)
end

local function BarContentWidth(button)
    if button and button.GetWidth then
        local width = button:GetWidth()
        if width and width > 2 then return width - 2 end
    end
    return ContentWidth()
end

local function ResetBarVisual(button)
    if not button or not button:IsShown() then return end
    button.fill:SetWidth(1)
    button.stateText:SetText("")
    button.glow:Hide()
    button:SetBackdropBorderColor(0.55, 0.42, 0.14, 1)
end

-- Secure player buttons remain created, shown and bound before combat. Threat
-- relevance only changes the visual alpha and a normal mouse blocker. This
-- avoids protected Show/Hide or unit reassignment while combat lockdown is
-- active, while irrelevant roster rows are neither visible nor clickable.
local function SetBarActive(button, active)
    if not button then return end
    button.threatVisible = active and true or false
    button:SetAlpha(active and 1 or 0)
    if button.inactiveBlocker then
        if active then button.inactiveBlocker:Hide() else button.inactiveBlocker:Show() end
    end
end

local function UpdateControlButtons()
    if muteButton then
        muteButton:SetText(db and db.muted and "Sound Off" or "Mute")
    end
    if pauseButton then
        pauseButton:SetText(db and db.suspended and "Resume" or "Pause")
    end
    SetGauge("Visible", frame and frame:IsShown() and 1 or 0)
    SetGauge("Suspended", db and db.suspended and 1 or 0)
    SetGauge("Muted", db and db.muted and 1 or 0)
end

local function DeactivateAllBars()
    if testButton then
        ResetBarVisual(testButton)
        SetBarActive(testButton, false)
    end
    for i = 1, #rosterButtons do
        local b = rosterButtons[i]
        if b then
            ResetBarVisual(b)
            SetBarActive(b, false)
        end
    end
    for i = 1, #focusButtons do
        local b = focusButtons[i]
        if b then
            ResetBarVisual(b)
            SetBarActive(b, false)
            b:Hide()
        end
    end
end

local function HelperPollAllowed()
    EnsureDB()
    if not db.enabled or db.suspended then return false end
    if not frame or not frame:IsShown() then return false end
    if db.testMode then return true end
    if db.showOnlyInCombat and not UnitAffectingCombat("player") then return false end
    return true
end

local function StopHelperTicker(clearVisuals)
    if updateFrame then updateFrame:Hide() end
    elapsedTotal = 0
    if clearVisuals then DeactivateAllBars() end
    SetGauge("Active", 0)
end

local function HelperCanRunBackgroundWork()
    EnsureDB()
    if not db.enabled or db.suspended then return false end
    if not frame or not frame:IsShown() then return false end
    return true
end

local function StartHelperTicker()
    if not HelperCanRunBackgroundWork() then
        StopHelperTicker(true)
        return
    end
    if HelperPollAllowed() or secureBuildActive or pendingSecureRefresh or rosterDirty then
        if updateFrame then updateFrame:Show() end
    else
        StopHelperTicker(true)
    end
end

local function SavePosition()
    if not frame or not db or not UIParent then return end
    if WowNote_SaveWindowGeometry then WowNote_SaveWindowGeometry("ThreatHelper", frame, true) end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        db.point = point
        db.relativePoint = relativePoint or point
        db.x = tonumber(x) or 0
        db.y = tonumber(y) or 0
    end
end

local function SaveConfigPosition()
    if not configFrame or not db or not UIParent then return end
    if WowNote_SaveWindowGeometry then WowNote_SaveWindowGeometry("ThreatHelperConfig", configFrame, false) end
    local point, _, relativePoint, x, y = configFrame:GetPoint(1)
    if point then
        db.configPoint = point
        db.configRelativePoint = relativePoint or point
        db.configX = tonumber(x) or 0
        db.configY = tonumber(y) or 0
    end
end

local function SaveWindowState()
    EnsureDB()
    SavePosition()
    SaveSize()
    SaveConfigPosition()
end

local function GroupUnits()
    local units = {}
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local party = GetNumPartyMembers and GetNumPartyMembers() or 0
    if raid > 0 then
        for i = 1, raid do units[#units + 1] = "raid" .. i end
    else
        units[#units + 1] = "player"
        for i = 1, party do units[#units + 1] = "party" .. i end
    end
    return units
end

local function FindUnitByName(name)
    if not name or name == "" then return nil end
    local lower = string.lower(name)
    local units = GroupUnits()
    for i = 1, #units do
        local n = UnitName(units[i])
        if n and string.lower(n) == lower then return units[i] end
    end
    return nil
end

local function FindUnitByGUID(guid)
    if not guid or guid == "" then return nil end
    local units = GroupUnits()
    for i = 1, #units do
        if UnitGUID(units[i]) == guid then return units[i] end
    end
    return nil
end

local function FindTargetGroupUnit()
    if not UnitExists("target") or not UnitIsPlayer("target") then return nil end
    local units = GroupUnits()
    for i = 1, #units do
        if UnitExists(units[i]) and UnitIsUnit("target", units[i]) then
            return units[i]
        end
    end
    return nil
end

local function ResolveTestUnit()
    if not db or not db.testMode then return nil end
    local unit = FindUnitByGUID(db.testAggroGUID)
    if unit then return unit end
    if db.testAggroUnit and db.testAggroUnit ~= "" and UnitExists(db.testAggroUnit) then
        local units = GroupUnits()
        for i = 1, #units do
            if UnitIsUnit(db.testAggroUnit, units[i]) then return units[i] end
        end
    end
    return FindUnitByName(db.testAggroName)
end

local function IsTankName(name)
    if not name then return false end
    if db.tanks[name] then return true end
    if db.focus1 == name or db.focus2 == name then return true end
    local me = UnitName("player")
    if me and name == me and WowNote_ThreatMeter_IsSelfTank and WowNote_ThreatMeter_IsSelfTank() then return true end
    return me and name == me and db.tanks[me] == true
end

local function ApplySecureAttributes(button, unit)
    if InCombatLockdown and InCombatLockdown() then
        pendingSecureRefresh = true
        return false
    end

    local actionButton = button.secureButton or button
    local left = ResolveSpell(db.spells.left)
    local right = ResolveSpell(db.spells.right)
    local shiftLeft = ResolveSpell(db.spells.shiftLeft)
    local shiftRight = ResolveSpell(db.spells.shiftRight)

    -- Every protected player button keeps a fixed unit token.
    -- Clicks are bound with direct secure spell attributes per mouse button/modifier.
    actionButton:SetAttribute("unit", unit)
    actionButton:SetAttribute("useparent-unit", false)
    actionButton:SetAttribute("checkselfcast", false)
    actionButton:SetAttribute("checkfocuscast", false)
    actionButton.unit = unit

    local function ClearDirect(prefix, mouseButton)
        actionButton:SetAttribute(prefix .. "helpbutton" .. mouseButton, nil)
        actionButton:SetAttribute(prefix .. "type" .. mouseButton, nil)
        actionButton:SetAttribute(prefix .. "spell" .. mouseButton, nil)
        actionButton:SetAttribute(prefix .. "macrotext" .. mouseButton, nil)
    end

    local function BindDirect(prefix, mouseButton, spellName)
        ClearDirect(prefix, mouseButton)
        if not spellName then return end
        -- Direct modified attributes are the most reliable route on 3.3.5.
        -- The button is a SecureUnitButtonTemplate and keeps its fixed unit,
        -- so spell casts target the player row that was bound before combat.
        actionButton:SetAttribute(prefix .. "type" .. mouseButton, "spell")
        actionButton:SetAttribute(prefix .. "spell" .. mouseButton, spellName)
    end

    BindDirect("", 1, left)
    BindDirect("", 2, right)
    BindDirect("shift-", 1, shiftLeft)
    BindDirect("shift-", 2, shiftRight)

    local function ConfigureSpellButton(btn, spellName)
        if not btn then return end
        btn:SetAttribute("unit", unit)
        btn:SetAttribute("useparent-unit", false)
        btn:SetAttribute("checkselfcast", false)
        btn:SetAttribute("checkfocuscast", false)
        btn:SetAttribute("helpbutton1", nil)
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("spell1", nil)
        btn:SetAttribute("macrotext1", nil)
        if spellName then
            btn:SetAttribute("type1", "spell")
            btn:SetAttribute("spell1", spellName)
        end
        btn.secureUnit = unit
    end
    if button.spellButtons then
        ConfigureSpellButton(button.spellButtons.left, left)
        ConfigureSpellButton(button.spellButtons.right, right)
        ConfigureSpellButton(button.spellButtons.shiftLeft, shiftLeft)
        ConfigureSpellButton(button.spellButtons.shiftRight, shiftRight)
    end

    -- Clear attributes used by older WowNote builds so they cannot intercept
    -- the direct secure routing above.
    actionButton:SetAttribute("type-heal1", nil)
    actionButton:SetAttribute("spell-heal1", nil)
    actionButton:SetAttribute("type-heal2", nil)
    actionButton:SetAttribute("spell-heal2", nil)
    actionButton:SetAttribute("shift-type-heal1", nil)
    actionButton:SetAttribute("shift-spell-heal1", nil)
    actionButton:SetAttribute("shift-type-heal2", nil)
    actionButton:SetAttribute("shift-spell-heal2", nil)
    actionButton:SetAttribute("*type1", nil)
    actionButton:SetAttribute("*spell1", nil)
    actionButton:SetAttribute("*type2", nil)
    actionButton:SetAttribute("*spell2", nil)
    actionButton:SetAttribute("macrotext1", nil)
    actionButton:SetAttribute("macrotext2", nil)
    actionButton:SetAttribute("shift-macrotext1", nil)
    actionButton:SetAttribute("shift-macrotext2", nil)

    button.secureUnit = unit
    button.unit = unit
    actionButton.secureUnit = unit
    return true
end

local function SetClassColor(texture, unit, alpha)
    local _, class = UnitClass(unit)
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class]
    if c then texture:SetVertexColor(c.r, c.g, c.b, alpha or 0.8)
    else texture:SetVertexColor(0.35, 0.35, 0.35, alpha or 0.8) end
end

local function ShowClickAssignmentsTooltip(owner, playerName, note)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(playerName or "Threat helper", 1, 0.82, 0)
    if note then GameTooltip:AddLine(note, 1, 0.55, 0.2, true) end
    GameTooltip:AddLine("Left click: " .. SpellLabel(db.spells.left), 1, 1, 1)
    GameTooltip:AddLine("Right click: " .. SpellLabel(db.spells.right), 1, 1, 1)
    GameTooltip:AddLine("Shift + left: " .. SpellLabel(db.spells.shiftLeft), 1, 1, 1)
    GameTooltip:AddLine("Shift + right: " .. SpellLabel(db.spells.shiftRight), 1, 1, 1)
    GameTooltip:Show()
end

local function SpellIcon(value)
    local _, _, icon = ResolveSpell(value)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function MakeMiniSpellButton(parent, key, label)
    local btn = CreateFrame("Button", nil, parent, "SecureUnitButtonTemplate")
    btn:SetWidth(20)
    btn:SetHeight(20)
    btn:RegisterForClicks("AnyUp")
    btn:EnableMouse(true)
    btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(btn)
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetAllPoints(btn)
    btn.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints(btn)
    btn.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    btn.highlight:SetBlendMode("ADD")
    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints(btn)
    btn.cooldown:Hide()
    btn.wowNoteSpellKey = key
    btn.wowNoteSpellLabel = label
    btn:SetScript("OnEnter", function(self)
        local owner = self:GetParent()
        ShowClickAssignmentsTooltip(self, owner and owner.displayName, (label or "Spell") .. " button -> " .. SpellLabel(db.spells[key]))
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Show()
    return btn
end

local function SetCooldownFrame(frame, start, duration, enabled)
    if not frame then return end
    if start and duration and duration > 1.5 and enabled ~= 0 then
        if CooldownFrame_SetTimer then
            CooldownFrame_SetTimer(frame, start, duration, enabled)
        elseif frame.SetCooldown then
            frame:SetCooldown(start, duration)
        end
        frame:Show()
    else
        if CooldownFrame_SetTimer then
            CooldownFrame_SetTimer(frame, 0, 0, 0)
        elseif frame.SetCooldown then
            frame:SetCooldown(0, 0)
        end
        frame:Hide()
    end
end

local function RefreshMiniSpellButton(button, key)
    if not button then return end
    local name, _, icon = ResolveSpell(db.spells[key])
    button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if name and GetSpellCooldown then
        local start, duration, enabled = GetSpellCooldown(name)
        SetCooldownFrame(button.cooldown, start, duration, enabled)
        if start and duration and duration > 1.5 and enabled ~= 0 then
            button.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
        else
            button.icon:SetVertexColor(1, 1, 1, 1)
        end
    else
        SetCooldownFrame(button.cooldown, 0, 0, 0)
        button.icon:SetVertexColor(name and 1 or 0.35, name and 1 or 0.35, name and 1 or 0.35, 1)
    end
end

local function RefreshMiniSpellButtonIcons(button)
    if not button or not button.spellButtons then return end
    RefreshMiniSpellButton(button.spellButtons.left, "left")
    RefreshMiniSpellButton(button.spellButtons.right, "right")
    RefreshMiniSpellButton(button.spellButtons.shiftLeft, "shiftLeft")
    RefreshMiniSpellButton(button.spellButtons.shiftRight, "shiftRight")
end

local function CreateSecureButton(parent, index, prefix)
    -- Render the bar on a normal frame and place a transparent protected
    -- SecureUnitButtonTemplate over the complete bar. This keeps the visual
    -- bar reliable while the click target remains a real HealBot-style unit
    -- button with a fixed unit token.
    local barName = "WowNoteThreatHelper" .. prefix .. "Visual" .. index
    local actionName = "WowNoteThreatHelper" .. prefix .. index
    local b = CreateFrame("Frame", barName, parent)
    b:SetHeight(BUTTON_HEIGHT)
    b:EnableMouse(false)
    b:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropColor(0.03, 0.03, 0.04, 0.95)
    b:SetBackdropBorderColor(0.55, 0.42, 0.14, 1)

    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMLEFT", 1, 1)
    b.fill:SetWidth(1)
    b.fill:SetTexture("Interface\\Buttons\\WHITE8X8")

    b.nameText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.nameText:SetPoint("LEFT", 48, 0)
    b.stateText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.stateText:SetPoint("RIGHT", -48, 0)
    b.clickText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.clickText:SetPoint("CENTER", 0, 0)
    b.clickText:SetText("")
    b.clickText:SetTextColor(1, 0.82, 0.2, 0.75)

    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetAllPoints(b)
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.1, 0.05, 1)
    b.glow:Hide()

    local action = CreateFrame("Button", actionName, b, "SecureUnitButtonTemplate")
    action:SetPoint("TOPLEFT", b, "TOPLEFT", 44, 0)
    action:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -44, 0)
    action:SetFrameLevel(b:GetFrameLevel() + 10)
    action:EnableMouse(true)
    action:RegisterForClicks("AnyUp")
    action:Show()
    action.ownerBar = b
    action:SetScript("OnEnter", function(self)
        local owner = self.ownerBar
        ShowClickAssignmentsTooltip(self, owner and owner.displayName, "Secure unit: " .. tostring(owner and owner.secureUnit or "unknown"))
    end)
    action:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b.spellButtons = {
        left = MakeMiniSpellButton(b, "left", "Spell 1 / left-click"),
        right = MakeMiniSpellButton(b, "right", "Spell 2 / right-click"),
        shiftLeft = MakeMiniSpellButton(b, "shiftLeft", "Spell 3 / Shift-left"),
        shiftRight = MakeMiniSpellButton(b, "shiftRight", "Spell 4 / Shift-right"),
    }
    b.spellButtons.left:SetPoint("LEFT", b, "LEFT", 2, 0)
    b.spellButtons.right:SetPoint("LEFT", b.spellButtons.left, "RIGHT", 2, 0)
    b.spellButtons.shiftLeft:SetPoint("RIGHT", b.spellButtons.shiftRight, "LEFT", -2, 0)
    b.spellButtons.shiftRight:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    RefreshMiniSpellButtonIcons(b)

    -- A non-secure transparent blocker sits above inactive bars. The secure
    -- action button stays prepared for combat, but blank rows cannot cast a
    -- spell when clicked accidentally.
    local blocker = CreateFrame("Frame", nil, b)
    blocker:SetAllPoints(b)
    blocker:SetFrameLevel((b:GetFrameLevel() or 1) + 30)
    blocker:EnableMouse(true)
    blocker:Show()

    b.secureButton = action
    b.inactiveBlocker = blocker
    SetBarActive(b, false)
    return b
end

local function IsValidEnemy(unit)
    return unit and UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit)
end

local function CurrentMob()
    if IsValidEnemy("target") then return "target" end
    if IsValidEnemy("focus") then return "focus" end
    if IsValidEnemy("focustarget") then return "focustarget" end
    if IsValidEnemy("targettarget") then return "targettarget" end
    return nil
end

-- Returns enemy unit tokens currently exposed through raid/party targets.
-- This is deliberately lightweight: off-target enemies are only inspected for
-- their current victim instead of running a full 40-player threat scan per mob.
local function ObservedMobUnits()
    AddCounter("OffTargetScans", 1)
    local result, seen = {}, {}
    local function Add(unit)
        if not IsValidEnemy(unit) then return end
        local key = UnitGUID(unit) or unit
        if seen[key] then return end
        seen[key] = true
        result[#result + 1] = unit
    end

    Add("target")
    Add("focus")
    Add("focustarget")
    Add("targettarget")

    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local party = GetNumPartyMembers and GetNumPartyMembers() or 0
    if raid > 0 then
        for i = 1, raid do
            Add("raid" .. i .. "target")
            Add("raidpet" .. i .. "target")
        end
    else
        Add("pettarget")
        for i = 1, party do
            Add("party" .. i .. "target")
            Add("partypet" .. i .. "target")
        end
    end
    return result
end

local function FindGroupVictim(mob, units)
    local victim = mob and (mob .. "target") or nil
    if not victim or not UnitExists(victim) then return nil end
    for i = 1, #units do
        if UnitExists(units[i]) and UnitIsUnit(victim, units[i]) then
            return units[i]
        end
    end
    return nil
end

local function ThreatInfo(unit, mob)
    if not mob or not UnitExists(unit) then return nil end
    AddCounter("ThreatQueries", 1)
    local tanking, status, scaled, raw, value = UnitDetailedThreatSituation(unit, mob)
    if value == nil then return nil end
    return { tanking = tanking and true or false, status = status or 0, scaled = scaled or 0, raw = raw or 0, value = value or 0 }
end

local function CreateWarningRow(index)
    local row = CreateFrame("Frame", nil, listFrame)
    row:SetHeight(20)
    -- The dynamically sorted warning is intentionally display-only. Secure
    -- click targets cannot be reassigned or reordered while combat lockdown is
    -- active. The matching fixed player button below performs the actual cast.
    row:EnableMouse(false)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    row:SetBackdropColor(0.04, 0.04, 0.05, 0.94)
    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("TOPLEFT", 1, -1); row.fill:SetPoint("BOTTOMLEFT", 1, 1); row.fill:SetWidth(1)
    row.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 5, 0)
    row.valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.valueText:SetPoint("RIGHT", -5, 0)
    row.glow = row:CreateTexture(nil, "OVERLAY")
    row.glow:SetAllPoints(row); row.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    row.glow:SetBlendMode("ADD"); row.glow:SetVertexColor(1, 0.05, 0.02, 1); row.glow:Hide()
    warningRows[index] = row
    return row
end

local function UpdateWarningList(entries)
    -- The protected player bars themselves display the threat state. A second
    -- dynamically rebound row cannot remain secure during combat.
    if listFrame then listFrame:Hide() end
end

LayoutPlayerBars = function()
    if not focusFrame or (InCombatLockdown and InCombatLockdown()) then return end
    local y = -2
    local function Place(button)
        if not button or not button:IsShown() then return end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", focusFrame, "TOPLEFT", 0, y)
        button:SetPoint("TOPRIGHT", focusFrame, "TOPRIGHT", 0, y)
        y = y - BUTTON_HEIGHT - BUTTON_SPACING
    end

    Place(testButton)
    -- Tank-focus players are deliberately never rendered in the helper. They
    -- are tank references for threat comparison only and must not expose a
    -- click-cast surface that could accidentally receive Hand of Protection.
    for i = 1, #rosterButtons do Place(rosterButtons[i]) end
end

RefreshTestButton = function()
    if InCombatLockdown and InCombatLockdown() then
        pendingSecureRefresh = true
        return
    end
    if not focusFrame then return end
    if not testButton then
        testButton = CreateSecureButton(focusFrame, 1, "TestButton")
    end

    local unit = db.testMode and ResolveTestUnit() or nil
    if unit and UnitExists(unit) then
        ApplySecureAttributes(testButton, unit)
        testButton.displayName = UnitName(unit) or db.testAggroName or unit
        testButton.nameText:SetText(testButton.displayName)
        testButton.stateText:SetText("TEST AGGRO")
        testButton.fill:SetWidth(BarContentWidth(testButton))
        testButton.fill:SetVertexColor(0.95, 0.05, 0.08, 0.95)
        testButton.glow:Show()
        testButton:SetBackdropBorderColor(1, 0.1, 0.02, 1)
        testButton:Show()
        SetBarActive(testButton, true)
    else
        SetBarActive(testButton, false)
        testButton:Hide()
    end
    LayoutPlayerBars()
end

local function BeginSecureRosterRefresh()
    if InCombatLockdown and InCombatLockdown() then
        pendingSecureRefresh = true
        return false
    end
    EnsureDB()
    local sourceUnits = GroupUnits()
    local orderedUnits, seenUnits = {}, {}
    local testUnit = ResolveTestUnit()
    local focusUnit1 = FindUnitByName(db.focus1)
    local focusUnit2 = FindUnitByName(db.focus2)

    local function IsReserved(unit)
        if testUnit and UnitIsUnit(unit, testUnit) then return true end
        if focusUnit1 and UnitIsUnit(unit, focusUnit1) then return true end
        if focusUnit2 and UnitIsUnit(unit, focusUnit2) then return true end
        return false
    end
    local function AddUnit(unit)
        if not unit or seenUnits[unit] or not UnitExists(unit) or IsReserved(unit) then return end
        seenUnits[unit] = true
        orderedUnits[#orderedUnits + 1] = unit
    end

    for i = 1, #sourceUnits do AddUnit(sourceUnits[i]) end
    secureBuildUnits = orderedUnits
    secureBuildIndex = 1
    secureBuildActive = true
    rosterDirty = false
    RefreshTestButton()
    RefreshFocusButtons()
    return true
end

local function ProcessSecureRosterRefresh(maxButtons)
    if not secureBuildActive then return true end
    if InCombatLockdown and InCombatLockdown() then
        secureBuildActive = false
        secureBuildUnits = nil
        secureBuildIndex = nil
        pendingSecureRefresh = true
        return false
    end

    local units = secureBuildUnits or {}
    local limit = math_min(#units, MAX_RAID)
    local processed = 0
    while secureBuildIndex and secureBuildIndex <= limit and processed < (maxButtons or 4) do
        local i = secureBuildIndex
        local unit = units[i]
        local b = rosterButtons[i]
        if not b then
            b = CreateSecureButton(focusFrame, i, "RosterButton")
            rosterButtons[i] = b
        end
        if unit and UnitExists(unit) then
            ApplySecureAttributes(b, unit)
            b.displayName = UnitName(unit) or unit
            b.nameText:SetText(b.displayName)
            b.stateText:SetText("")
            b.fill:SetWidth(1)
            b.glow:Hide()
            b:SetBackdropBorderColor(0.55, 0.42, 0.14, 1)
            b:Show()
            b.barKind = "roster"
            SetBarActive(b, false)
        else
            SetBarActive(b, false)
            b:Hide()
        end
        secureBuildIndex = i + 1
        processed = processed + 1
    end

    if secureBuildIndex and secureBuildIndex > limit then
        for i = limit + 1, #rosterButtons do
            if rosterButtons[i] then rosterButtons[i]:Hide() end
        end
        secureBuildActive = false
        secureBuildUnits = nil
        secureBuildIndex = nil
        pendingSecureRefresh = false
        RefreshTestButton()
        RefreshFocusButtons()
        LayoutPlayerBars()
        return true
    end
    LayoutPlayerBars()
    return false
end

local function RefreshSecureRoster()
    if BeginSecureRosterRefresh() then
        ProcessSecureRosterRefresh(4)
    end
end

RefreshFocusButtons = function()
    -- Focus players are used only as tank references. Never create or expose a
    -- secure click-cast bar for them in the Threat Helper. Hide any legacy
    -- focus bars that may still exist until the next UI reload.
    for i = 1, #focusButtons do
        local b = focusButtons[i]
        if b then
            SetBarActive(b, false)
            b:Hide()
        end
    end
    LayoutPlayerBars()
end


local function UpdateThreatVisuals()
    if not frame or not frame:IsShown() then return end
    UpdateControlButtons()
    if not HelperPollAllowed() then
        if db.suspended and testModeText then
            testModeText:SetText("Threat Helper paused")
            testModeText:Show()
        elseif testModeText and not db.testMode then
            testModeText:Hide()
        end
        DeactivateAllBars()
        SetGauge("Active", 0)
        return
    end
    AddCounter("VisualUpdates", 1)
    SetGauge("Active", 1)
    if db.suspended then
        DeactivateAllBars()
        if testModeText then
            testModeText:SetText("Threat Helper paused")
            testModeText:Show()
        end
        return
    end
    if db.showOnlyInCombat and not UnitAffectingCombat("player") and not db.testMode then
        UpdateWarningList({})
        for i = 1, #rosterButtons do
            ResetBarVisual(rosterButtons[i])
            SetBarActive(rosterButtons[i], false)
        end
        -- Focus players are never displayed or clickable in the helper.
        for i = 1, #focusButtons do
            local b = focusButtons[i]
            if b then SetBarActive(b, false); b:Hide() end
        end
        return
    end

    local units = GroupUnits()
    local currentMob = CurrentMob()
    local byUnit = {}

    -- Test mode injects a visible AGGRO state for one real group member.
    -- The secure unit assignment itself is unchanged, so configured clicks can
    -- be tested safely outside an instance.
    if db.testMode then
        local testUnit = ResolveTestUnit()
        if testUnit then
            byUnit[testUnit] = { percent = 130, aggro = true, info = nil, test = true }
        end
    end
    if testModeText then
        if db.testMode then
            local testUnit = ResolveTestUnit()
            local testName = testUnit and UnitName(testUnit) or db.testAggroName
            testModeText:SetText(testName and testName ~= "" and ("TEST AGGRO: " .. testName) or "TEST AGGRO: player not found")
            testModeText:Show()
        else
            testModeText:Hide()
        end
    end
    local warningByKey = {}
    local activeAggro = {}

    local function MergeUnitState(unit, percent, aggro, info)
        local existing = byUnit[unit]
        if existing and existing.test then return end
        if not existing or (aggro and not existing.aggro) or (aggro == existing.aggro and percent > existing.percent) then
            byUnit[unit] = { percent = percent, aggro = aggro, info = info }
        end
    end

    local function AddWarning(unit, name, percent, aggro, value, mob)
        if not unit or not name or IsTankName(name) then return end
        local key = UnitGUID(unit) or name
        local existing = warningByKey[key]
        local entry = {
            unit = unit,
            name = name,
            percent = percent or 0,
            aggro = aggro and true or false,
            value = value or 0,
            mob = mob and UnitName(mob) or nil,
        }
        if not existing or (entry.aggro and not existing.aggro) or
           (entry.aggro == existing.aggro and entry.percent > existing.percent) then
            warningByKey[key] = entry
        end
        if entry.aggro then activeAggro[key] = true end
    end

    -- Full Omen-style threat comparison remains limited to the selected mob.
    if currentMob then
        local all = {}
        local highestTank = 0
        for i = 1, #units do
            local unit = units[i]
            local name = UnitName(unit)
            local info = ThreatInfo(unit, currentMob)
            if name and info then
                all[#all + 1] = { unit = unit, name = name, info = info }
                if IsTankName(name) and info.value > highestTank then highestTank = info.value end
            end
        end
        if highestTank <= 0 then
            for i = 1, #all do
                if all[i].info.tanking and all[i].info.value > highestTank then highestTank = all[i].info.value end
            end
        end
        if highestTank <= 0 then
            for i = 1, #all do
                if all[i].info.value > highestTank then highestTank = all[i].info.value end
            end
        end

        for i = 1, #all do
            local e = all[i]
            local percent = highestTank > 0 and (e.info.value / highestTank * 100) or e.info.scaled
            local aggro = e.info.tanking or e.info.status >= 2
            MergeUnitState(e.unit, percent, aggro, e.info)
            if aggro or percent >= db.warningThreshold then
                AddWarning(e.unit, e.name, percent, aggro, e.info.value, currentMob)
            end
        end
    end

    -- Also detect mobs exposed through other raid members' targets. If such a
    -- mob is currently attacking a non-tank, warn immediately even when the
    -- local player has never targeted that mob.
    local mobs = ObservedMobUnits()
    for i = 1, #mobs do
        local mob = mobs[i]
        local victimUnit = FindGroupVictim(mob, units)
        if victimUnit then
            local victimName = UnitName(victimUnit)
            if victimName and not IsTankName(victimName) then
                local info = ThreatInfo(victimUnit, mob)
                local percent = info and math_max(info.scaled or 0, 100) or 100
                local value = info and info.value or 0
                MergeUnitState(victimUnit, percent, true, info)
                AddWarning(victimUnit, victimName, percent, true, value, mob)
            end
        end
    end

    local warnings = {}
    for _, entry in pairs(warningByKey) do warnings[#warnings + 1] = entry end
    table_sort(warnings, function(a, b)
        if a.aggro ~= b.aggro then return a.aggro end
        if a.value ~= b.value then return a.value > b.value end
        if a.percent ~= b.percent then return a.percent > b.percent end
        return a.name < b.name
    end)
    UpdateWarningList(warnings)

    for key in pairs(activeAggro) do
        if not lastAggro[key] and db.playAggroSound and not db.muted and PlaySoundFile then
            PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
        end
    end
    lastAggro = activeAggro

    if testButton and testButton:IsShown() then
        RefreshMiniSpellButtonIcons(testButton)
        local testUnit = testButton.secureUnit
        local data = testUnit and byUnit[testUnit]
        if data then
            testButton.fill:SetWidth(BarContentWidth(testButton))
            testButton.fill:SetVertexColor(0.95, 0.05, 0.08, 0.95)
            testButton.stateText:SetText("TEST AGGRO")
            testButton.glow:Show()
            testButton:SetBackdropBorderColor(1, 0.1, 0.02, 1)
        end
    end

    for i = 1, #rosterButtons do
        local b = rosterButtons[i]
        local data = b.secureUnit and byUnit[b.secureUnit]
        if b:IsShown() then
            RefreshMiniSpellButtonIcons(b)
            local relevant = data and (data.aggro or data.percent >= db.warningThreshold)
            SetBarActive(b, relevant and true or false)
            if relevant then
                local w = math_max(1, BarContentWidth(b) * math_min(1, data.percent / 130))
                b.fill:SetWidth(w); SetClassColor(b.fill, b.secureUnit, data.aggro and 1 or 0.7)
                if data.aggro then
                    b.stateText:SetText(data.test and "TEST AGGRO" or "AGGRO")
                    b.glow:Show()
                    b:SetBackdropBorderColor(1, 0.1, 0.02, 1)
                else
                    b.stateText:SetText(string.format("%.0f%%", data.percent))
                    b.glow:Hide()
                    b:SetBackdropBorderColor(0.95, 0.65, 0.1, 1)
                end
            else
                ResetBarVisual(b)
            end
        end
    end
    -- Focus players remain excluded from the visible/clickable helper list in
    -- every state, including combat and active threat.
    for i = 1, #focusButtons do
        local b = focusButtons[i]
        if b then SetBarActive(b, false); b:Hide() end
    end
end

local function CreateMainFrame()
    if frame then return end
    EnsureDB()
    frame = CreateFrame("Frame", "WowNoteThreatHelperFrame", UIParent)
    frame:SetWidth(db.width); frame:SetHeight(db.height or DEFAULTS.height)
    if WowNote_RestoreWindowGeometry then
        WowNote_RestoreWindowGeometry("ThreatHelper", frame, {
            point = db.point or "CENTER",
            relativePoint = db.relativePoint or db.point or "CENTER",
            x = db.x or 0,
            y = db.y or 0,
        }, true)
    else
        frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or db.point or "CENTER", db.x or 0, db.y or 0)
    end
    frame:SetMovable(true); frame:SetResizable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:SetMinResize(240, 280); frame:SetMaxResize(720, 900)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropBorderColor(0.92, 0.65, 0.18, 1)
    title = CreateFrame("Frame", nil, frame); title:SetHeight(22); title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT")
    title:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); title:SetBackdropColor(0.08, 0.065, 0.035, 0.98)
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function(self)
        frame:StartMoving()
        self.positionSaveElapsed = 0
        self:SetScript("OnUpdate", function(owner, elapsed)
            owner.positionSaveElapsed = (owner.positionSaveElapsed or 0) + elapsed
            if owner.positionSaveElapsed >= 0.10 then
                owner.positionSaveElapsed = 0
                SavePosition()
            end
        end)
    end)
    title:SetScript("OnDragStop", function(self)
        frame:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        SavePosition()
    end)
    frame:SetScript("OnHide", function() SavePosition(); SaveSize() end)
    local text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); text:SetPoint("LEFT", 7, 0); text:SetText("WowNote Threat Helper")
    local gear = CreateFrame("Button", nil, title); gear:SetSize(18, 18); gear:SetPoint("RIGHT", -20, 0)
    gear:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01"); gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    gear:SetScript("OnClick", function() TH:OpenConfig() end)
    local close = CreateFrame("Button", nil, title, "UIPanelCloseButton"); close:SetSize(20,20); close:SetPoint("RIGHT", 2, 0); close:SetScript("OnClick", function() TH:Hide() end)
    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(16, 16); resize:SetPoint("BOTTOMRIGHT", -2, 2)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not (InCombatLockdown and InCombatLockdown()) then frame:StartSizing("BOTTOMRIGHT") end
    end)
    resize:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing(); SaveSize(); UpdateThreatVisuals()
    end)
    resize:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Resize Threat Helper", 1, 0.82, 0)
        GameTooltip:AddLine("Drag to change width and height.", 1, 1, 1)
        GameTooltip:Show()
    end)
    resize:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnSizeChanged", function(self, width, height)
        if not db then return end
        db.width = math_floor((width or DEFAULTS.width) + 0.5)
        db.height = math_floor((height or DEFAULTS.height) + 0.5)
    end)
    local secureLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    secureLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -28)
    secureLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -82, -28)
    secureLabel:SetJustifyH("LEFT")
    secureLabel:SetText("Player bars")

    muteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    muteButton:SetSize(66, 21)
    muteButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -25)
    muteButton:SetScript("OnClick", function() TH:ToggleMute() end)
    muteButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mute Threat Helper sounds", 1, 0.82, 0)
        GameTooltip:AddLine("Toggles warning sounds only. Visual threat checks and click helpers keep working.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    muteButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pauseButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pauseButton:SetSize(66, 21)
    pauseButton:SetPoint("TOPRIGHT", muteButton, "TOPLEFT", -4, 0)
    pauseButton:SetScript("OnClick", function() TH:ToggleSuspended() end)
    pauseButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Pause Threat Helper", 1, 0.82, 0)
        GameTooltip:AddLine("Soft-disables helper warnings and click surfaces without changing secure unit bindings. Safe during combat.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pauseButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    setMTButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    setMTButton:SetSize(122, 22)
    setMTButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -50)
    setMTButton:SetText("Set target as MT")
    setMTButton:SetScript("OnClick", function() TH:SetFocusTarget(1) end)
    setMTButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Set target as MT", 1, 0.82, 0)
        GameTooltip:AddLine("Marks your current target as Main Tank for Threat Helper comparisons. MT is never shown as a clickable helper bar.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    setMTButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    setOTButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    setOTButton:SetSize(122, 22)
    setOTButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -50)
    setOTButton:SetText("Set target as OT")
    setOTButton:SetScript("OnClick", function() TH:SetFocusTarget(2) end)
    setOTButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Set target as OT", 1, 0.82, 0)
        GameTooltip:AddLine("Marks your current target as Off Tank for Threat Helper comparisons. OT is never shown as a clickable helper bar.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    setOTButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    testModeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    testModeText:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -78)
    testModeText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -78)
    testModeText:SetJustifyH("LEFT")
    testModeText:SetTextColor(1, 0.2, 0.1, 1)
    testModeText:SetText("")
    testModeText:Hide()

    listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -96)
    listFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 22)
    listFrame:Hide()

    -- Definite opposing anchors are important here. The former mixed top
    -- anchors could collapse the effective width of all child bars in 3.3.5.
    focusFrame = CreateFrame("Frame", "WowNoteThreatHelperSecureContainer", frame)
    focusFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -96)
    focusFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 22)
    focusFrame:SetFrameLevel(frame:GetFrameLevel() + 2)
    focusFrame:Show()
    UpdateControlButtons()
    frame:Hide()
end

local spellDropDownFrame
local configSpellRows = {}
local configFocusEdits = {}

local function GetSpellbookGroups()
    local groups = {}
    local seen = {}
    local tabCount = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, tabCount do
        local tabName, _, offset, numSpells = GetSpellTabInfo(tab)
        local spells = {}
        for i = 1, (numSpells or 0) do
            local slot = (offset or 0) + i
            local name = GetSpellName and GetSpellName(slot, BOOKTYPE_SPELL)
            if name and name ~= "" and not seen[name] then
                seen[name] = true
                local icon = select(3, GetSpellInfo(name))
                local spellId
                if GetSpellLink then
                    local link = GetSpellLink(slot, BOOKTYPE_SPELL)
                    spellId = link and tonumber(string.match(link, "spell:(%d+)")) or nil
                end
                spells[#spells + 1] = { name = name, id = spellId, icon = icon }
            end
        end
        table_sort(spells, function(a, b) return a.name < b.name end)
        if #spells > 0 then groups[#groups + 1] = { name = tabName or ("Tab " .. tab), spells = spells } end
    end
    return groups
end

local function ApplyConfiguredSpell(key, value, row)
    value = value or ""
    local name, id, icon = ResolveSpell(value)
    if value ~= "" and not name then
        row.status:SetText("Unknown spell")
        row.status:SetTextColor(1, 0.2, 0.2)
        return false
    end
    db.spells[key] = id or name or nil
    row.edit:SetText(db.spells[key] and tostring(db.spells[key]) or "")
    row.status:SetText(name or "Not assigned")
    row.status:SetTextColor(name and 0.85 or 0.55, name and 0.85 or 0.55, name and 0.85 or 0.55)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if InCombatLockdown and InCombatLockdown() then
        pendingSecureRefresh = true
        Print("Spell change queued until combat ends.")
    else
        RefreshSecureRoster()
        RefreshFocusButtons()
    end
    return true
end

local function OpenSpellDropdown(anchor, key, row)
    if not EasyMenu then
        Print("Spell dropdown is not available in this client.")
        return
    end
    spellDropDownFrame = spellDropDownFrame or CreateFrame("Frame", "WowNoteThreatHelperSpellDropDown", UIParent, "UIDropDownMenuTemplate")
    local menu = {
        { text = "Select spell", isTitle = true, notCheckable = true },
        { text = "Clear assignment", notCheckable = true, func = function() ApplyConfiguredSpell(key, "", row) end },
    }
    local groups = GetSpellbookGroups()
    for i = 1, #groups do
        local group = groups[i]
        local submenu = {}
        for j = 1, #group.spells do
            local spell = group.spells[j]
            submenu[#submenu + 1] = {
                text = spell.name,
                icon = spell.icon,
                notCheckable = true,
                func = function()
                    ApplyConfiguredSpell(key, spell.id or spell.name, row)
                    CloseDropDownMenus()
                end,
            }
        end
        menu[#menu + 1] = { text = group.name, hasArrow = true, notCheckable = true, menuList = submenu }
    end
    if #groups == 0 then
        menu[#menu + 1] = { text = "No learned spells found", disabled = true, notCheckable = true }
    end
    EasyMenu(menu, spellDropDownFrame, anchor, 0, 0, "MENU")
end

local function CreateSection(parent, titleText, top, height)
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("TOPLEFT", 18, top)
    section:SetPoint("TOPRIGHT", -18, top)
    section:SetHeight(height)
    section:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    section:SetBackdropColor(0.025, 0.025, 0.03, 0.82)
    section:SetBackdropBorderColor(0.34, 0.27, 0.12, 1)
    local heading = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 10, -9)
    heading:SetText(titleText)
    return section
end

local editBoxCounter = 0

local function CreateStyledEditBox(parent, width, height)
    editBoxCounter = editBoxCounter + 1
    local edit = CreateFrame("EditBox", "WowNoteThreatHelperEditBox" .. editBoxCounter, parent)
    edit:SetSize(width, height)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetTextInsets(7, 7, 0, 0)
    edit:SetMaxLetters(80)
    edit:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    edit:SetBackdropColor(0.015, 0.015, 0.018, 0.95)
    edit:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(0.85, 0.62, 0.12, 1) end)
    edit:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0.32, 0.32, 0.32, 1) end)
    return edit
end

local function MakeSpellRow(parent, label, key, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 10, y)
    row:SetPoint("TOPRIGHT", -10, y)
    row:SetHeight(50)

    local labelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelText:SetPoint("LEFT", 0, 7)
    labelText:SetWidth(115)
    labelText:SetJustifyH("LEFT")
    labelText:SetText(label)

    local iconBorder = CreateFrame("Frame", nil, row)
    iconBorder:SetSize(30, 30)
    iconBorder:SetPoint("LEFT", 118, 2)
    iconBorder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    iconBorder:SetBackdropColor(0, 0, 0, 1)
    iconBorder:SetBackdropBorderColor(0.45, 0.35, 0.12, 1)
    local icon = iconBorder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)

    local edit = CreateStyledEditBox(row, 190, 22)
    edit:SetPoint("LEFT", iconBorder, "RIGHT", 10, 3)

    local choose = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    choose:SetSize(125, 24)
    choose:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    choose:SetText("Choose spell")

    local clear = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    clear:SetSize(58, 24)
    clear:SetPoint("LEFT", choose, "RIGHT", 8, 0)
    clear:SetText("Clear")

    local status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 3, -1)
    status:SetPoint("RIGHT", clear, "RIGHT", 0, 0)
    status:SetJustifyH("LEFT")

    row.edit, row.status, row.icon = edit, status, icon
    configSpellRows[key] = row

    local function Commit()
        ApplyConfiguredSpell(key, edit:GetText() or "", row)
    end
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit() end)
    edit:SetScript("OnEditFocusLost", Commit)
    edit:SetScript("OnReceiveDrag", function(self)
        local kind, id = GetCursorInfo()
        if kind == "spell" and id then
            ClearCursor()
            ApplyConfiguredSpell(key, id, row)
        end
    end)
    choose:SetScript("OnClick", function(self) OpenSpellDropdown(self, key, row) end)
    clear:SetScript("OnClick", function() ApplyConfiguredSpell(key, "", row) end)

    local value = db.spells[key]
    local name, _, spellIcon = ResolveSpell(value)
    edit:SetText(value and tostring(value) or "")
    status:SetText(name or "Not assigned")
    icon:SetTexture(spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    return row
end

local function MakeFocusRow(parent, label, key, y, focusIndex)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelText:SetPoint("TOPLEFT", 10, y)
    labelText:SetWidth(125)
    labelText:SetJustifyH("LEFT")
    labelText:SetText(label)

    local edit = CreateStyledEditBox(parent, 280, 22)
    edit:SetPoint("TOPLEFT", 145, y + 6)
    edit:SetText(db[key] or "")

    local useTarget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    useTarget:SetSize(125, 24)
    useTarget:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    useTarget:SetText("Use target")

    local clear = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clear:SetSize(62, 24)
    clear:SetPoint("LEFT", useTarget, "RIGHT", 8, 0)
    clear:SetText("Clear")

    local function Commit(value)
        db[key] = value ~= nil and value or (edit:GetText() or "")
        edit:SetText(db[key])
        if InCombatLockdown and InCombatLockdown() then pendingSecureRefresh = true else RefreshFocusButtons() end
    end
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit() end)
    edit:SetScript("OnEditFocusLost", function() Commit() end)
    useTarget:SetScript("OnClick", function()
        if UnitExists("target") and UnitIsPlayer("target") then Commit(UnitName("target") or "") else Print("Target a player first.") end
    end)
    clear:SetScript("OnClick", function() Commit("") end)
    configFocusEdits[focusIndex] = edit
end

function TH:OpenConfig()
    EnsureDB(); CreateMainFrame()
    if not configFrame then
        configFrame = CreateFrame("Frame", "WowNoteThreatHelperConfigFrame", UIParent)
        configFrame:SetSize(760, 665)
        if WowNote_RestoreWindowGeometry then
            WowNote_RestoreWindowGeometry("ThreatHelperConfig", configFrame, {
                point = db.configPoint or "CENTER",
                relativePoint = db.configRelativePoint or db.configPoint or "CENTER",
                x = db.configX or 0,
                y = db.configY or 0,
            }, false)
        else
            configFrame:SetPoint(db.configPoint or "CENTER", UIParent, db.configRelativePoint or db.configPoint or "CENTER", db.configX or 0, db.configY or 0)
        end
        configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        configFrame:SetMovable(true)
        configFrame:EnableMouse(true)
        configFrame:RegisterForDrag("LeftButton")
        configFrame:SetScript("OnDragStart", function(self)
            self:StartMoving()
            self.positionSaveElapsed = 0
            self:SetScript("OnUpdate", function(owner, elapsed)
                owner.positionSaveElapsed = (owner.positionSaveElapsed or 0) + elapsed
                if owner.positionSaveElapsed >= 0.10 then
                    owner.positionSaveElapsed = 0
                    SaveConfigPosition()
                end
            end)
        end)
        configFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self:SetScript("OnUpdate", nil)
            SaveConfigPosition()
        end)
        configFrame:SetScript("OnHide", function() SaveConfigPosition() end)
        configFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })

        local titleText = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleText:SetPoint("TOPLEFT", 22, -18)
        titleText:SetText("WowNote Threat Helper")
        local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -5, -5)

        local info = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        info:SetPoint("TOPLEFT", 22, -48)
        info:SetWidth(710)
        info:SetJustifyH("LEFT")
        info:SetText("Assign learned spells from the dropdown, enter a spell ID/name, or drag a spell from the spellbook. Changes made in combat are queued until combat ends.")

        local spellSection = CreateSection(configFrame, "Click assignments", -78, 270)
        MakeSpellRow(spellSection, "Left click", "left", -34)
        MakeSpellRow(spellSection, "Right click", "right", -92)
        MakeSpellRow(spellSection, "Shift + left", "shiftLeft", -150)
        MakeSpellRow(spellSection, "Shift + right", "shiftRight", -208)

        local focusSection = CreateSection(configFrame, "MT / OT tank references (excluded from helper bars)", -358, 112)
        MakeFocusRow(focusSection, "Main Tank (MT)", "focus1", -32, 1)
        MakeFocusRow(focusSection, "Off Tank (OT)", "focus2", -68, 2)

        local behaviorSection = CreateSection(configFrame, "Threat behavior and test mode", -480, 112)
        local thresholdLabel = behaviorSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        thresholdLabel:SetPoint("TOPLEFT", 10, -35)
        thresholdLabel:SetText("Warning threshold (%)")
        local threshold = CreateStyledEditBox(behaviorSection, 80, 22)
        threshold:SetPoint("TOPLEFT", 160, -29)
        threshold:SetNumeric(true)
        threshold:SetText(tostring(db.warningThreshold))
        threshold:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        threshold:SetScript("OnEditFocusLost", function(self)
            db.warningThreshold = math_max(1, math_min(200, tonumber(self:GetText()) or 85))
            self:SetText(tostring(db.warningThreshold))
        end)

        local testTarget = CreateFrame("Button", nil, behaviorSection, "UIPanelButtonTemplate")
        testTarget:SetSize(180, 24)
        testTarget:SetPoint("TOPLEFT", 270, -29)
        testTarget:SetText("Target = TEST AGGRO")
        testTarget:SetScript("OnClick", function() TH:SetTestAggroTarget() end)

        local testClear = CreateFrame("Button", nil, behaviorSection, "UIPanelButtonTemplate")
        testClear:SetSize(110, 24)
        testClear:SetPoint("LEFT", testTarget, "RIGHT", 10, 0)
        testClear:SetText("Clear test")
        testClear:SetScript("OnClick", function() TH:ClearTestAggro() end)

        local testStatus = behaviorSection:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        testStatus:SetPoint("TOPLEFT", 10, -72)
        testStatus:SetWidth(690)
        testStatus:SetJustifyH("LEFT")
        testStatus:SetText("Select a real group member, then mark it as TEST AGGRO to verify all four click assignments outside an instance.")

        local hint = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMLEFT", 22, 18)
        hint:SetWidth(710)
        hint:SetJustifyH("LEFT")
        hint:SetText("MT/OT players are used for threat comparison only and are never shown or clickable in the helper. Mark further tanks with /wn threathelper tank.")
    end

    for key, row in pairs(configSpellRows) do
        local value = db.spells[key]
        local name, _, icon = ResolveSpell(value)
        row.edit:SetText(value and tostring(value) or "")
        row.status:SetText(name or "Not assigned")
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    if configFocusEdits[1] then configFocusEdits[1]:SetText(db.focus1 or "") end
    if configFocusEdits[2] then configFocusEdits[2]:SetText(db.focus2 or "") end
    configFrame:Show()
end

function TH:Show()
    EnsureDB()
    CreateMainFrame()
    if WowNote_SetWindowVisibility then WowNote_SetWindowVisibility("ThreatHelper", true) end
    db.suspended = false
    UpdateControlButtons()
    frame:Show()
    if focusFrame then focusFrame:Show() end
    rosterDirty = true
    if not (InCombatLockdown and InCombatLockdown()) then
        RefreshTestButton()
        RefreshFocusButtons()
        BeginSecureRosterRefresh()
        ProcessSecureRosterRefresh(INITIAL_BUILD_BATCH)
        LayoutPlayerBars()
    else
        pendingSecureRefresh = true
    end
    UpdateThreatVisuals()
    StartHelperTicker()
end

function TH:Hide()
    EnsureDB()
    if InCombatLockdown and InCombatLockdown() then
        db.suspended = true
        UpdateControlButtons()
        DeactivateAllBars()
        StopHelperTicker(false)
        if testModeText then testModeText:SetText("Threat Helper paused in combat"); testModeText:Show() end
        Print("Combat lockdown: Threat Helper paused instead of hidden. Use again after combat to fully close it.")
        return
    end
    db.suspended = false
    if WowNote_SetWindowVisibility then WowNote_SetWindowVisibility("ThreatHelper", false) end
    StopHelperTicker(false)
    if frame then SavePosition(); SaveSize(); frame:Hide() end
end
function TH:Toggle()
    EnsureDB()
    if frame and frame:IsShown() then
        if InCombatLockdown and InCombatLockdown() then self:ToggleSuspended() else self:Hide() end
    else
        self:Show()
    end
end

function TH:SetMuted(value)
    EnsureDB()
    db.muted = value and true or false
    UpdateControlButtons()
    -- Mute is audio-only. Do not pause or clear the helper here; the Pause
    -- button/suspended state is the explicit switch for stopping background
    -- threat checks. Keeping mute audio-only prevents the helper from going
    -- dead after users muted warning sounds.
    if frame and frame:IsShown() and not db.suspended and db.enabled then
        StartHelperTicker()
        UpdateThreatVisuals()
    end
    Print(db.muted and "Threat Helper muted: sound warnings disabled; visual threat checks stay active." or "Threat Helper unmuted.")
end

function TH:ToggleMute()
    EnsureDB()
    self:SetMuted(not db.muted)
end

function TH:SetSuspended(value)
    EnsureDB()
    CreateMainFrame()
    db.suspended = value and true or false
    UpdateControlButtons()
    if db.suspended then
        DeactivateAllBars()
        StopHelperTicker(false)
        if testModeText then testModeText:SetText("Threat Helper paused"); testModeText:Show() end
        Print("Threat Helper paused.")
    else
        Print("Threat Helper resumed.")
        if frame and not frame:IsShown() then frame:Show() end
        if not (InCombatLockdown and InCombatLockdown()) then
            RefreshTestButton()
            BeginSecureRosterRefresh()
            ProcessSecureRosterRefresh(INITIAL_BUILD_BATCH)
        end
        StartHelperTicker()
        UpdateThreatVisuals()
    end
end

function TH:ToggleSuspended()
    EnsureDB()
    self:SetSuspended(not db.suspended)
end

function TH:Refresh()
    EnsureDB()
    rosterDirty = true
    if frame and frame:IsShown() then
        if RefreshFocusButtons then RefreshFocusButtons() end
        StartHelperTicker()
    end
end

function TH:ToggleTankTarget()
    EnsureDB()
    if not UnitExists("target") or not UnitIsPlayer("target") then Print("Target a player first."); return end
    local name=UnitName("target")
    db.tanks[name]=not db.tanks[name]
    Print(name .. (db.tanks[name] and " marked as tank." or " removed as tank."))
end

function TH:SetFocusTarget(index)
    EnsureDB()
    if not UnitExists("target") or not UnitIsPlayer("target") then Print("Target a player first."); return end
    local name = UnitName("target") or ""
    if name == "" then Print("Target a player first."); return end
    local key = index == 1 and "focus1" or "focus2"
    local otherKey = index == 1 and "focus2" or "focus1"
    db[key] = name
    if db[otherKey] == name then db[otherKey] = "" end
    if db.testAggroName == name or db.testAggroGUID == UnitGUID("target") then
        db.testMode = false
        db.testAggroName = ""
        db.testAggroGUID = ""
        db.testAggroUnit = ""
    end
    Print(name .. " marked as " .. (index == 1 and "MT" or "OT") .. ".")
    if InCombatLockdown and InCombatLockdown() then
        for i = 1, #rosterButtons do
            local b = rosterButtons[i]
            if b and b.secureUnit and UnitIsUnit(b.secureUnit, "target") then
                ResetBarVisual(b)
                SetBarActive(b, false)
            end
        end
        pendingSecureRefresh = true
    else
        RefreshTestButton()
        BeginSecureRosterRefresh()
        ProcessSecureRosterRefresh(INITIAL_BUILD_BATCH)
        RefreshFocusButtons()
    end
    UpdateThreatVisuals()
end


function TH:SetTestAggroTarget()
    EnsureDB()
    if InCombatLockdown and InCombatLockdown() then
        Print("The test player can only be changed outside combat.")
        return
    end
    local unit = FindTargetGroupUnit()
    if not unit then
        Print("Target a real member of your current group or raid first.")
        return
    end
    local name = UnitName(unit) or UnitName("target") or unit
    if name == db.focus1 or name == db.focus2 then
        Print("MT/OT players are never shown in the Threat Helper. Select a non-tank group member for the test.")
        return
    end
    db.testAggroName = name
    db.testAggroGUID = UnitGUID(unit) or ""
    db.testAggroUnit = unit
    db.testMode = true
    Print(name .. " marked as TEST AGGRO.")

    self:Show()
    RefreshTestButton()
    BeginSecureRosterRefresh()
    ProcessSecureRosterRefresh(INITIAL_BUILD_BATCH)
    UpdateThreatVisuals()
    StartHelperTicker()
end

function TH:ClearTestAggro()
    EnsureDB()
    if InCombatLockdown and InCombatLockdown() then
        Print("Test mode can only be cleared outside combat.")
        return
    end
    db.testMode = false
    db.testAggroName = ""
    db.testAggroGUID = ""
    db.testAggroUnit = ""
    Print("Threat Helper test mode disabled.")
    if testModeText then testModeText:Hide() end
    RefreshTestButton()
    if frame and frame:IsShown() then
        BeginSecureRosterRefresh()
        ProcessSecureRosterRefresh(INITIAL_BUILD_BATCH)
        RefreshFocusButtons()
        UpdateThreatVisuals()
    end
end

function TH:DiagnoseTestMode()
    EnsureDB()
    local unit = ResolveTestUnit()
    Print("Test mode: " .. tostring(db.testMode) .. ", player: " .. tostring(db.testAggroName) .. ", unit: " .. tostring(unit))
    if not unit then return end
    local found = testButton and testButton:IsShown() and testButton or nil
    if not found then
        for i = 1, #rosterButtons do
            local button = rosterButtons[i]
            if button and button.secureUnit and UnitIsUnit(button.secureUnit, unit) then
                found = button
                break
            end
        end
    end
    if not found then
        Print("No secure player bar is currently bound to the test player.")
        return
    end
    local action = found.secureButton or found
    Print("Secure bar: " .. tostring(found:GetName()) .. ", unit=" .. tostring(action:GetAttribute("unit")))
    Print("L=" .. tostring(action:GetAttribute("spell1")) .. ", R=" .. tostring(action:GetAttribute("spell2")))
    Print("Shift-L=" .. tostring(action:GetAttribute("shift-spell1")) .. ", Shift-R=" .. tostring(action:GetAttribute("shift-spell2")))
end

function WowNote_OpenThreatHelper() TH:Show() end
function WowNote_OpenThreatHelperConfig() TH:OpenConfig() end
function WowNote_ThreatHelperHandleSlash(args)
    local s=string.lower(tostring(args or "")); s=string.gsub(s,"^%s+",""); s=string.gsub(s,"%s+$","")
    if s=="show" or s=="" then TH:Show()
    elseif s=="hide" then TH:Hide()
    elseif s=="toggle" then TH:Toggle()
    elseif s=="config" then TH:OpenConfig()
    elseif s=="tank" then TH:ToggleTankTarget()
    elseif s=="mt" or s=="focus1" then TH:SetFocusTarget(1)
    elseif s=="ot" or s=="focus2" then TH:SetFocusTarget(2)
    elseif s=="mute" then TH:SetMuted(true)
    elseif s=="unmute" then TH:SetMuted(false)
    elseif s=="pause" or s=="suspend" then TH:SetSuspended(true)
    elseif s=="resume" then TH:SetSuspended(false)
    elseif s=="testaggro" or s=="test" then TH:SetTestAggroTarget()
    elseif s=="testclear" or s=="testoff" then TH:ClearTestAggro()
    elseif s=="testdebug" or s=="diagnose" then TH:DiagnoseTestMode()
    else Print("Commands: show, hide, toggle, config, tank, mt, ot, mute, pause, testaggro, testclear, testdebug") end
end

local function ThreatHelperOnUpdate(self, elapsed)
    if not frame or not frame:IsShown() then
        StopHelperTicker(false)
        return
    end
    if db and (db.suspended or not db.enabled) then
        secureBuildActive = false
        pendingSecureRefresh = false
        rosterDirty = false
        StopHelperTicker(true)
        return
    end
    if not HelperCanRunBackgroundWork() and not secureBuildActive and not pendingSecureRefresh and not rosterDirty then
        StopHelperTicker(true)
        return
    end
    elapsedTotal = elapsedTotal + (elapsed or 0)
    if elapsedTotal < UPDATE_INTERVAL then return end
    elapsedTotal = 0
    AddCounter("Ticker", 1)
    if rosterDirty and not secureBuildActive and not (InCombatLockdown and InCombatLockdown()) then
        BeginSecureRosterRefresh()
    end
    if secureBuildActive then
        ProcessSecureRosterRefresh(4)
    end
    if HelperPollAllowed() then
        UpdateThreatVisuals()
    else
        DeactivateAllBars()
        if not secureBuildActive and not pendingSecureRefresh and not rosterDirty then
            StopHelperTicker(false)
        end
    end
end

if WowNoteProfiler_SetScript then
    WowNoteProfiler_SetScript(updateFrame, "OnUpdate", "ThreatHelper.Ticker", ThreatHelperOnUpdate)
else
    updateFrame:SetScript("OnUpdate", ThreatHelperOnUpdate)
end
updateFrame:Hide()

local event=CreateFrame("Frame")
event:RegisterEvent("PLAYER_LOGIN"); event:RegisterEvent("PLAYER_LOGOUT"); event:RegisterEvent("PLAYER_LEAVING_WORLD"); event:RegisterEvent("RAID_ROSTER_UPDATE"); event:RegisterEvent("PARTY_MEMBERS_CHANGED"); event:RegisterEvent("PLAYER_REGEN_DISABLED"); event:RegisterEvent("PLAYER_REGEN_ENABLED"); event:RegisterEvent("PLAYER_TARGET_CHANGED")
event:SetScript("OnEvent",function(_,ev)
    EnsureDB()
    if ev=="PLAYER_LOGIN" then
        CreateMainFrame()
        local restoreVisible = WowNote_GetWindowVisibility and WowNote_GetWindowVisibility("ThreatHelper")
        if restoreVisible then TH:Show() else frame:Hide() end
    elseif ev=="PLAYER_LOGOUT" or ev=="PLAYER_LEAVING_WORLD" then
        SaveWindowState()
    elseif ev=="PLAYER_REGEN_DISABLED" then
        UpdateControlButtons()
        if frame and frame:IsShown() and not db.suspended then StartHelperTicker() end
    elseif ev=="PLAYER_REGEN_ENABLED" then
        UpdateControlButtons()
        if pendingSecureRefresh or rosterDirty then
            RefreshTestButton()
            BeginSecureRosterRefresh()
            ProcessSecureRosterRefresh(INITIAL_BUILD_BATCH)
            RefreshFocusButtons()
            StartHelperTicker()
        end
    else
        rosterDirty=true
        if db.testMode then
            local testUnit = ResolveTestUnit()
            if testUnit then db.testAggroUnit = testUnit end
        end
        if frame and frame:IsShown() then
            if not (InCombatLockdown and InCombatLockdown()) then
                RefreshTestButton()
                BeginSecureRosterRefresh()
                ProcessSecureRosterRefresh(INITIAL_BUILD_BATCH)
            end
            StartHelperTicker()
        end
    end
end)
