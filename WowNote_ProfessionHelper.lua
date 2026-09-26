-- WowNote Profession Helper
-- WotLK 3.3.5a: Milling / Prospecting queues.
-- Protected actions still require one hardware click per 5-item batch.

local PH = {}
WowNote_ProfessionHelper = PH

local MILLING_SPELL = "Milling"
local PROSPECTING_SPELL = "Prospecting"

-- Static WotLK material lists. Only materials present in the player's bags are shown.
local MILLABLE = {
    {2447, "Peacebloom"}, {765, "Silverleaf"}, {2449, "Earthroot"}, {785, "Mageroyal"},
    {2450, "Briarthorn"}, {3820, "Stranglekelp"}, {2453, "Bruiseweed"}, {3355, "Wild Steelbloom"},
    {3369, "Grave Moss"}, {3356, "Kingsblood"}, {3357, "Liferoot"}, {3818, "Fadeleaf"},
    {3821, "Goldthorn"}, {3358, "Khadgar's Whisker"}, {3819, "Wintersbite"}, {4625, "Firebloom"},
    {8831, "Purple Lotus"}, {8836, "Arthas' Tears"}, {8838, "Sungrass"}, {8839, "Blindweed"},
    {8845, "Ghost Mushroom"}, {8846, "Gromsblood"}, {13464, "Golden Sansam"}, {13463, "Dreamfoil"},
    {13465, "Mountain Silversage"}, {13466, "Plaguebloom"}, {13467, "Icecap"},
    {22785, "Felweed"}, {22786, "Dreaming Glory"}, {22787, "Ragveil"}, {22789, "Terocone"},
    {22790, "Ancient Lichen"}, {22791, "Netherbloom"}, {22792, "Nightmare Vine"}, {22793, "Mana Thistle"},
    {36901, "Goldclover"}, {36904, "Tiger Lily"}, {36907, "Talandra's Rose"}, {36903, "Adder's Tongue"},
    {36905, "Lichbloom"}, {36906, "Icethorn"}, {37921, "Deadnettle"}, {39970, "Fire Leaf"},
}

local PROSPECTABLE = {
    {2770, "Copper Ore"}, {2771, "Tin Ore"}, {2772, "Iron Ore"}, {3858, "Mithril Ore"},
    {10620, "Thorium Ore"}, {23424, "Fel Iron Ore"}, {23425, "Adamantite Ore"},
    {36909, "Cobalt Ore"}, {36912, "Saronite Ore"}, {36910, "Titanium Ore"},
}

local MODES = {
    milling = { title = "Milling", spell = MILLING_SPELL, items = MILLABLE },
    prospecting = { title = "Prospecting", spell = PROSPECTING_SPELL, items = PROSPECTABLE },
}

local function DB()
    WowNoteDB = WowNoteDB or {}
    WowNoteDB.professionHelper = WowNoteDB.professionHelper or {}
    local db = WowNoteDB.professionHelper
    db.milling = db.milling or { selected = {} }
    db.prospecting = db.prospecting or { selected = {} }
    db.milling.selected = db.milling.selected or {}
    db.prospecting.selected = db.prospecting.selected or {}
    return db
end

local function ItemIDFromLink(link)
    if not link then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

local function ScanBags()
    local result = {}
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local _, count, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
            local id = ItemIDFromLink(link)
            if id and count and count > 0 then
                result[id] = result[id] or { count = 0, stacks = {} }
                result[id].count = result[id].count + count
                table.insert(result[id].stacks, { bag = bag, slot = slot, count = count, locked = locked })
            end
        end
    end
    return result
end

local function FindUsableStack(itemId, bags)
    local data = bags[itemId]
    if not data then return nil end
    for _, stack in ipairs(data.stacks) do
        if (stack.count or 0) >= 5 and not stack.locked then
            return stack
        end
    end
    return nil
end

local function PlayerKnowsSpell(spellName)
    if not spellName then return false end
    if GetSpellInfo then
        local name = GetSpellInfo(spellName)
        if name then
            -- GetSpellInfo(string) may resolve even if not known, so scan spellbook as fallback truth.
        end
    end
    if GetNumSpellTabs and GetSpellTabInfo and GetSpellName then
        local tabs = GetNumSpellTabs() or 0
        for tab = 1, tabs do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            offset, numSpells = offset or 0, numSpells or 0
            for i = offset + 1, offset + numSpells do
                local name = GetSpellName(i, BOOKTYPE_SPELL)
                if name == spellName then return true end
            end
        end
    end
    return false
end

local function ModeDB(mode)
    return DB()[mode]
end

local function MaterialName(itemId, fallback)
    local name = GetItemInfo(itemId)
    return name or fallback or ("item:" .. tostring(itemId))
end

local function Selected(mode, itemId)
    return ModeDB(mode).selected[tostring(itemId)] == true
end

local function SetSelected(mode, itemId, value)
    ModeDB(mode).selected[tostring(itemId)] = value and true or nil
end

local function NextMaterial(mode)
    local def = MODES[mode]
    if not def then return nil end
    local bags = ScanBags()
    for _, entry in ipairs(def.items) do
        local id, fallback = entry[1], entry[2]
        if Selected(mode, id) then
            local stack = FindUsableStack(id, bags)
            if stack then
                return id, fallback, stack, bags[id] and bags[id].count or 0
            end
        end
    end
    return nil
end

local frame
local rows = {}
local currentMode = "milling"
local bagDirtyAt = 0

local RefreshRows

local function SetButtonText(button, text)
    if not button then return end
    if button.label then
        button.label:SetText(text or "")
    elseif button.SetText then
        button:SetText(text or "")
    end
end

local function QueueSummary(mode)
    local def = MODES[mode]
    local bags = ScanBags()
    local batches, materials = 0, 0
    for _, entry in ipairs(def.items) do
        local id = entry[1]
        if Selected(mode, id) and bags[id] then
            local itemBatches = 0
            for _, stack in ipairs(bags[id].stacks or {}) do
                itemBatches = itemBatches + math.floor((stack.count or 0) / 5)
            end
            if itemBatches > 0 then
                batches = batches + itemBatches
                materials = materials + 1
            end
        end
    end
    return batches, materials
end

local function PrepareProcessButton()
    if not frame or not frame.process then return end
    local id, fallback, stack, total = NextMaterial(currentMode)
    frame.nextItemId = id

    if InCombatLockdown and InCombatLockdown() then
        frame.status:SetText("Locked in combat. Queue updates after combat.")
        frame.process:EnableMouse(false)
        frame.process:SetAlpha(0.45)
        return
    end

    frame.process:SetAttribute("type", nil)
    frame.process:SetAttribute("macrotext", nil)

    if not id or not stack then
        frame.process:EnableMouse(false)
        frame.process:SetAlpha(0.45)
        SetButtonText(frame.process, "Nothing ready (need 5)")
        frame.status:SetText("No selected material has a stack of at least 5. Remainders are skipped.")
        return
    end

    local def = MODES[currentMode]
    if not PlayerKnowsSpell(def.spell) then
        frame.process:EnableMouse(false)
        frame.process:SetAlpha(0.45)
        SetButtonText(frame.process, def.spell .. " not learned")
        frame.status:SetText("This character does not know " .. def.spell .. ".")
        return
    end
    local name = MaterialName(id, fallback)
    local macro = "/cast " .. def.spell .. "\n/use " .. tostring(stack.bag) .. " " .. tostring(stack.slot)
    frame.process:SetAttribute("type", "macro")
    frame.process:SetAttribute("macrotext", macro)
    frame.process:EnableMouse(true)
    frame.process:SetAlpha(1)
    local batches, materials = QueueSummary(currentMode)
    SetButtonText(frame.process, def.title .. ": " .. name .. "  |  CLICK NEXT")
    frame.status:SetText(
        tostring(batches) .. " batch" .. (batches == 1 and "" or "es") ..
        " ready across " .. tostring(materials) .. " selected material" .. (materials == 1 and "" or "s") ..
        ". Keep clicking this same button; remainders below 5 are skipped."
    )
end

RefreshRows = function()
    if not frame then return end
    local def = MODES[currentMode]
    local bags = ScanBags()
    frame.title:SetText("Profession Helper - " .. def.title)
    frame.modeMilling:SetAlpha(currentMode == "milling" and 1 or 0.65)
    frame.modeProspecting:SetAlpha(currentMode == "prospecting" and 1 or 0.65)

    local visible = {}
    for _, entry in ipairs(def.items) do
        local id, fallback = entry[1], entry[2]
        local data = bags[id]
        if data and (data.count or 0) > 0 then
            table.insert(visible, {id=id, fallback=fallback, count=data.count})
        end
    end

    for i = 1, #rows do
        local row = rows[i]
        local data = visible[i]
        if data then
            row.itemId = data.id
            row.text:SetText(MaterialName(data.id, data.fallback) .. "  x" .. tostring(data.count))
            row.check:SetChecked(Selected(currentMode, data.id))
            row:Show()
        else
            row.itemId = nil
            row:Hide()
        end
    end

    if #visible == 0 then frame.empty:Show() else frame.empty:Hide() end
    PrepareProcessButton()
end

local function MakeCheck(parent, x, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(360); row:SetHeight(24); row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetWidth(24); check:SetHeight(24); check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check = check

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0); text:SetJustifyH("LEFT"); text:SetWidth(320)
    row.text = text

    check:SetScript("OnClick", function(self)
        if row.itemId then
            SetSelected(currentMode, row.itemId, self:GetChecked() and true or false)
            PrepareProcessButton()
        end
    end)
    return row
end

local events

local function CreateUI()
    if frame then return frame end

    local f = CreateFrame("Frame", "WowNoteProfessionHelperFrame", UIParent)
    f:SetWidth(430); f:SetHeight(560); f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=32, insets={left=11,right=12,top=12,bottom=11}})
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    local mill = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    mill:SetWidth(120); mill:SetHeight(24); mill:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -48); mill:SetText("Milling")
    mill:SetScript("OnClick", function() currentMode = "milling"; RefreshRows() end)
    f.modeMilling = mill

    local pros = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    pros:SetWidth(120); pros:SetHeight(24); pros:SetPoint("LEFT", mill, "RIGHT", 8, 0); pros:SetText("Prospecting")
    pros:SetScript("OnClick", function() currentMode = "prospecting"; RefreshRows() end)
    f.modeProspecting = pros

    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    all:SetWidth(72); all:SetHeight(24); all:SetPoint("LEFT", pros, "RIGHT", 8, 0); all:SetText("All")
    all:SetScript("OnClick", function()
        local def, bags = MODES[currentMode], ScanBags()
        for _, entry in ipairs(def.items) do
            local id = entry[1]
            if bags[id] and bags[id].count > 0 then SetSelected(currentMode, id, true) end
        end
        RefreshRows()
    end)

    local none = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    none:SetWidth(72); none:SetHeight(24); none:SetPoint("TOPLEFT", all, "BOTTOMLEFT", 0, -4); none:SetText("None")
    none:SetScript("OnClick", function()
        ModeDB(currentMode).selected = {}
        RefreshRows()
    end)

    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -98)
    empty:SetText("No matching materials found in your bags.")
    f.empty = empty

    for i = 1, 15 do
        local row = MakeCheck(f, 24, -96 - ((i-1)*25))
        rows[i] = row
    end

    local process = CreateFrame("Button", "WowNoteProfessionHelperProcessButton", f, "SecureActionButtonTemplate")
    process:SetWidth(360); process:SetHeight(38); process:SetPoint("BOTTOM", f, "BOTTOM", 0, 54)
    process:RegisterForClicks("AnyUp")
    process:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    process:SetBackdropColor(0.03, 0.10, 0.22, 0.98)
    process:SetBackdropBorderColor(0.20, 0.55, 1.00, 1.00)

    local processLabel = process:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    processLabel:SetPoint("LEFT", process, "LEFT", 10, 0)
    processLabel:SetPoint("RIGHT", process, "RIGHT", -10, 0)
    processLabel:SetJustifyH("CENTER")
    process.label = processLabel

    process:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.35, 0.75, 1.00, 1.00)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Profession queue")
        GameTooltip:AddLine("Click once per 5-item batch. The next valid stack is selected automatically.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    process:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.20, 0.55, 1.00, 1.00)
        GameTooltip:Hide()
    end)
    f.process = process

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 26, 22); status:SetWidth(378); status:SetJustifyH("LEFT")
    status:SetText("")
    f.status = status

    events = CreateFrame("Frame")
    local refreshPending = false
    local refreshDelay = 0

    local function QueueRefresh(delay)
        refreshPending = true
        refreshDelay = tonumber(delay) or 0.15
        events:Show()
    end

    events:RegisterEvent("BAG_UPDATE")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE" then
            bagDirtyAt = GetTime()
            -- Milling/Prospecting can fire several BAG_UPDATE events.
            -- Wait briefly until bag/loot changes have settled, then rebind
            -- the same secure button to the next valid 5-item stack.
            QueueRefresh(0.20)
        elseif event == "PLAYER_REGEN_ENABLED" then
            QueueRefresh(0.05)
        end
    end)
    events:SetScript("OnUpdate", function(self, elapsed)
        if not refreshPending then return end
        refreshDelay = refreshDelay - (elapsed or 0)
        if refreshDelay <= 0 then
            refreshPending = false
            self:Hide()
            if f:IsShown() then RefreshRows() end
        end
    end)
    events:Hide()

    process:SetScript("PostClick", function()
        -- A fallback refresh also covers clients/addons where BAG_UPDATE arrives
        -- in an unexpected order. The secure click itself has already happened.
        QueueRefresh(0.35)
    end)

    f:SetScript("OnShow", function()
        RefreshRows()
    end)

    frame = f
    return f
end

function WowNote_OpenProfessionHelper(mode)
    local f = CreateUI()
    if mode == "milling" or mode == "prospecting" then currentMode = mode end
    if f:IsShown() then
        RefreshRows()
    else
        f:Show()
    end
end
